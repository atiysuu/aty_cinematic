-- Environment: time of day / weather / timecycle / time scale / wind / rain / blackout / population.
-- Apply on change (clock every frame), restore only what THIS session changed.
Cine.Env = { live = {} }
local E = Cine.Env
local M = CineMath

local applied = {}
local touched = {}
local paused = false
local weatherSet = nil

local function adapterActive()
    local a = Config.Env.SyncAdapter
    if a == 'none' then return false end
    return (a == 'auto' or a == 'cd_easytime') and GetResourceState('cd_easytime') == 'started'
end

--- Ask the sync resource to stop writing the clock / weather. A harmless no-op when the export is
--- missing (pcall), so cd_easytime does not have to be patched for the director to run.
local function pauseSync()
    if paused or not adapterActive() then return end
    paused = true
    pcall(function() exports['cd_easytime']:SetExternalControl(true) end)
end

local function resumeSync()
    if not paused then return end
    paused = false
    pcall(function() exports['cd_easytime']:SetExternalControl(false) end)
end

function E.Reset()
    applied, touched = {}, {}
    E.live = {}
    -- the director starts in a fixed look (Config.Env.OnOpen) until the user changes it
    for k, v in pairs(Config.Env.OnOpen or {}) do E.live[k] = v end
end

--- Current effective values for a new env key: the live panel values + the clock when none is set.
function E.Capture()
    local out = {}
    for k, v in pairs(E.live) do out[k] = v end
    if out.tod == nil then
        out.tod = (GetClockHours() * 60 + GetClockMinutes()) % 1440 + 0.0
    end
    return out
end

--- Apply an env table. Called every frame; cheap when nothing changed.
function E.Tick(e)
    if not e then return end
    weatherSet = weatherSet or CineWeatherSet()

    if e.tod ~= nil then
        pauseSync()
        local minutes = e.tod % 1440.0
        local h = math.floor(minutes / 60.0)
        local m = math.floor(minutes % 60.0)
        local s = math.floor((minutes * 60.0) % 60.0)
        NetworkOverrideClockTime(h, m, s) -- every frame: sync scripts write the clock continuously
        touched.clock = true
    end

    if e.weather ~= nil and e.weather ~= applied.weather and weatherSet[e.weather] then
        pauseSync()
        applied.weather = e.weather
        SetOverrideWeather(e.weather)
        SetWeatherTypeNowPersist(e.weather)
        touched.weather = true
    end

    if e.timecycle ~= nil and e.timecycle ~= applied.timecycle then
        applied.timecycle = e.timecycle
        applied.tcStrength = nil
        if e.timecycle == '' then
            if touched.tc then ClearTimecycleModifier(); touched.tc = false end
        else
            SetTimecycleModifier(e.timecycle)
            touched.tc = true
        end
    end
    if touched.tc then
        local str = e.tcStrength or 1.0
        if applied.tcStrength == nil or math.abs(str - applied.tcStrength) > 0.001 then
            applied.tcStrength = str
            SetTimecycleModifierStrength(str + 0.0)
        end
    end

    if e.timeScale ~= nil then
        local ts = M.Clamp(e.timeScale, Config.Env.TimeScaleMin, 1.0)
        if applied.timeScale == nil or math.abs(ts - applied.timeScale) > 0.001 then
            applied.timeScale = ts
            SetTimeScale(ts + 0.0)
        end
    end

    if e.wind ~= nil and e.wind ~= applied.wind then
        applied.wind = e.wind
        SetWindSpeed(e.wind + 0.0)
        touched.wind = true
    end

    if e.rain ~= nil and e.rain ~= applied.rain then
        applied.rain = e.rain
        SetRainLevel(e.rain + 0.0) -- -1.0 = back to automatic
        touched.rain = e.rain >= 0.0
    end

    if e.blackout ~= nil and e.blackout ~= applied.blackout then
        applied.blackout = e.blackout
        SetArtificialLightsState(e.blackout == true)
        touched.lights = e.blackout == true
    end

    if e.population == true or Config.Session.ClearAmbientPopulation then
        SetPedDensityMultiplierThisFrame(0.0)
        SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
        SetVehicleDensityMultiplierThisFrame(0.0)
        SetRandomVehicleDensityMultiplierThisFrame(0.0)
        SetParkedVehicleDensityMultiplierThisFrame(0.0)
    end
end

--- Restore everything this session changed. Each step in its own pcall; idempotent.
function E.Restore()
    pcall(SetTimeScale, 1.0)
    if touched.clock then pcall(NetworkClearClockTimeOverride) end
    if touched.weather then
        pcall(ClearOverrideWeather)
        pcall(ClearWeatherTypePersist)
    end
    if touched.tc then pcall(ClearTimecycleModifier) end
    if touched.lights then pcall(SetArtificialLightsState, false) end
    if touched.rain then pcall(SetRainLevel, -1.0) end
    resumeSync()
    applied, touched = {}, {}
end
