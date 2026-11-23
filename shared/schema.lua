-- Project schema v1: defaults and sanitizers. Used by the client (before send / after load) and
-- by the server (before write). Everything is rebuilt field by field: unknown keys are dropped,
-- numbers clamped, arrays capped. Never depends on decoder metatables.
CineSchema = {}
local S = CineSchema

S.Version = 1
local COORD = 100000.0

local function isNum(v)
    return type(v) == 'number' and v == v and v > -1e12 and v < 1e12
end

function S.Num(v, lo, hi, def)
    if not isNum(v) then return def end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function S.Bool(v, def)
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return def
end

--- Cap the length BEFORE any pattern (bug-lessons: O(n^2) trims on long input).
function S.Str(v, maxLen, def)
    if type(v) ~= 'string' then return def end
    if #v > maxLen then v = v:sub(1, maxLen) end
    return v
end

function S.Name(v, def)
    local s = S.Str(v, 48, nil)
    if not s then return def end
    s = s:gsub('%c', '')
    s = s:match('^%s*(.-)%s*$') or ''
    if s == '' then return def end
    return s
end

--- Ids are lowercase [a-z0-9_], 3-40 chars. Returns the id or nil.
function S.Id(v)
    if type(v) ~= 'string' or #v < 3 or #v > 40 then return nil end
    if not v:match('^[a-z0-9_]+$') then return nil end
    return v
end

local function ident(v, maxLen)
    local s = S.Str(v, maxLen or 64, nil)
    if not s or s == '' then return nil end
    if not s:match('^[%w_@%.%-]+$') then return nil end
    return s
end
S.Ident = ident

function S.Vec3(v, def)
    if type(v) ~= 'table' then return def end
    local x, y, z = v[1], v[2], v[3]
    if not (isNum(x) and isNum(y) and isNum(z)) then return def end
    return {
        S.Num(x, -COORD, COORD, 0.0), S.Num(y, -COORD, COORD, 0.0), S.Num(z, -COORD, COORD, 0.0),
    }
end

local function oneOf(v, list, def)
    for _, name in ipairs(list) do
        if v == name then return v end
    end
    return def
end

local INTERP = { 'smooth', 'linear', 'hold' }
local EASE = { 'flow', 'linear', 'easeIn', 'easeOut', 'easeInOut', 'bezier' }
S.Interps, S.Eases = INTERP, EASE

local SHAKE_PRESETS = { 'none', 'handheld', 'walk', 'run', 'vehicle', 'action', 'drone' }
S.ShakePresets = SHAKE_PRESETS

--- Per-shot camera shake settings (always a full table).
function S.Shake(raw)
    raw = type(raw) == 'table' and raw or {}
    return {
        preset = oneOf(raw.preset, SHAKE_PRESETS, 'none'),
        amount = S.Num(raw.amount, 0.0, 3.0, 1.0),
        speed = S.Num(raw.speed, 0.0, 1.0, 0.0),
        whip = S.Num(raw.whip, 0.0, 1.0, 0.0),
    }
end

function S.Env(raw, weatherSet)
    if type(raw) ~= 'table' then return nil end
    local e, any = {}, false
    local function put(k, v) if v ~= nil then e[k] = v; any = true end end
    if raw.tod ~= nil then put('tod', S.Num(raw.tod, 0.0, 1439.999, nil)) end
    if raw.todDir ~= nil then put('todDir', oneOf(raw.todDir, { 'short', 'forward' }, nil)) end
    if type(raw.weather) == 'string' and weatherSet and weatherSet[raw.weather] then put('weather', raw.weather) end
    if raw.timecycle ~= nil then
        local tc = S.Str(raw.timecycle, 64, nil)
        if tc and (tc == '' or tc:match('^[%w_%-]+$')) then put('timecycle', tc) end
    end
    if raw.tcStrength ~= nil then put('tcStrength', S.Num(raw.tcStrength, 0.0, 1.0, nil)) end
    if raw.timeScale ~= nil then put('timeScale', S.Num(raw.timeScale, 0.05, 1.0, nil)) end
    if raw.wind ~= nil then put('wind', S.Num(raw.wind, 0.0, 12.0, nil)) end
    if raw.rain ~= nil then put('rain', S.Num(raw.rain, -1.0, 1.0, nil)) end
    if raw.blackout ~= nil then put('blackout', S.Bool(raw.blackout, nil)) end
    if raw.population ~= nil then put('population', S.Bool(raw.population, nil)) end
    if not any then return nil end
    return e
end

function S.Dof(raw)
    local d = Config.Dof.Defaults
    raw = type(raw) == 'table' and raw or {}
    local target = nil
    if raw.target ~= nil then target = S.Id(raw.target) end
    return {
        on = S.Bool(raw.on, false),
        near = S.Num(raw.near, 0.0, 1000.0, d.near),
        far = S.Num(raw.far, 0.0, 5000.0, d.far),
        str = S.Num(raw.str, 0.0, 1.0, d.strength),
        target = target,
    }
end

--- { c = pivot {x,y,z}, d = radius } | nil. Keys taken while orbiting carry it, so the timeline
--- can circle the pivot between two such keys instead of cutting straight across.
function S.KeyOrbit(raw)
    if type(raw) ~= 'table' then return nil end
    local c = S.Vec3(raw.c, nil)
    if not c then return nil end
    return { c = c, d = S.Num(raw.d, 0.05, 500.0, 6.0) }
end

function S.Key(raw, weatherSet, fallbackId)
    if type(raw) ~= 'table' then return nil end
    local pos = S.Vec3(raw.pos, nil)
    if not pos then return nil end
    local rr = type(raw.rot) == 'table' and raw.rot or {}
    local rot = {
        S.Num(rr[1], -89.0, 89.0, 0.0),
        S.Num(rr[2], -3600.0, 3600.0, 0.0),
        S.Num(rr[3], -3600.0, 3600.0, 0.0),
    }
    local bez = { 0.42, 0.0, 0.58, 1.0 }
    if type(raw.bez) == 'table' then
        bez = {
            S.Num(raw.bez[1], 0.0, 1.0, 0.42), S.Num(raw.bez[2], -1.0, 2.0, 0.0),
            S.Num(raw.bez[3], 0.0, 1.0, 0.58), S.Num(raw.bez[4], -1.0, 2.0, 1.0),
        }
    end
    return {
        id = S.Id(raw.id) or fallbackId,
        t = S.Num(raw.t, 0.0, 36000.0, 0.0),
        hold = S.Num(raw.hold, 0.0, 600.0, 0.0),
        pos = pos,
        rot = rot,
        fov = S.Num(raw.fov, Config.Freecam.FovMin, Config.Freecam.FovMax, Config.Freecam.Fov),
        dof = S.Dof(raw.dof),
        interp = oneOf(raw.interp, INTERP, Config.Timeline.DefaultInterp),
        ease = oneOf(raw.ease, EASE, Config.Timeline.DefaultEase),
        bez = bez,
        env = S.Env(raw.env, weatherSet),
        shake = type(raw.shake) == 'table' and S.Shake(raw.shake) or nil, -- nil = carry the previous
        orbit = S.KeyOrbit(raw.orbit), -- set when the key was taken in the orbit rig
    }
end

function S.Actor(raw, fallbackId)
    if type(raw) ~= 'table' then return nil end
    local kind = oneOf(raw.kind, { 'ped', 'vehicle', 'clone' }, nil)
    if not kind then return nil end
    local pos = S.Vec3(raw.pos, nil)
    if not pos then return nil end
    local model = nil
    if kind ~= 'clone' then
        model = ident(raw.model, 64)
        if not model then return nil end
    end
    local props = nil
    if kind == 'vehicle' and type(raw.props) == 'table' then
        local ok, enc = pcall(json.encode, raw.props)
        if ok and enc and #enc <= 16384 then props = raw.props end
    end
    local anim = nil
    if type(raw.anim) == 'table' then
        local dict, name = ident(raw.anim.dict, 80), ident(raw.anim.name, 80)
        if dict and name then
            anim = { dict = dict, name = name, flag = math.floor(S.Num(raw.anim.flag, 0, 65535, 1)) }
        end
    end
    local rot = S.Vec3(raw.rot, { 0.0, 0.0, 0.0 })
    return {
        id = S.Id(raw.id) or fallbackId,
        name = S.Name(raw.name, kind),
        kind = kind,
        model = model,
        props = props,
        pos = pos,
        rot = rot,
        anim = anim,
        scenario = (type(raw.scenario) == 'string') and ident(raw.scenario, 64) or nil,
        scene = S.Id(raw.scene), -- the placed scene this actor belongs to (nil = added by hand)
        pair = S.Id(raw.pair),   -- the other actor of a two-person emote (hug, handshake)
    }
end

function S.Light(raw, fallbackId)
    if type(raw) ~= 'table' then return nil end
    local d = Config.Lights.Defaults
    local pos = S.Vec3(raw.pos, nil)
    if not pos then return nil end
    local color = { 255, 214, 170 }
    if type(raw.color) == 'table' then
        color = {
            math.floor(S.Num(raw.color[1], 0, 255, 255)),
            math.floor(S.Num(raw.color[2], 0, 255, 255)),
            math.floor(S.Num(raw.color[3], 0, 255, 255)),
        }
    end
    return {
        id = S.Id(raw.id) or fallbackId,
        name = S.Name(raw.name, 'light'),
        type = oneOf(raw.type, { 'point', 'spot' }, 'point'),
        pos = pos,
        rot = S.Vec3(raw.rot, { 0.0, 0.0, 0.0 }),
        color = color,
        range = S.Num(raw.range, 0.1, 500.0, d.range),
        intensity = S.Num(raw.intensity, 0.0, 200.0, d.intensity),
        radius = S.Num(raw.radius, 1.0, 90.0, d.radius),
        roundness = S.Num(raw.roundness, 0.0, 100.0, d.roundness),
        falloff = S.Num(raw.falloff, 0.0, 1000.0, d.falloff),
        shadow = S.Bool(raw.shadow, false),
        scene = S.Id(raw.scene),
    }
end

--- A placed ready-made scene: which preset, where its centre is on the ground, which way it faces.
--- Its actors / lights carry its id in `scene`, so it can be removed (or filmed) as one thing, also
--- after the project was closed and opened again.
function S.Scene(raw, fallbackId)
    if type(raw) ~= 'table' then return nil end
    local preset = ident(raw.preset, 40)
    local pos = S.Vec3(raw.pos, nil)
    if not preset or not pos then return nil end
    return { id = S.Id(raw.id) or fallbackId, preset = preset, pos = pos, yaw = S.Num(raw.yaw, -3600.0, 3600.0, 0.0) }
end

local function uniqueId(used, id, prefix, counter)
    if id and not used[id] then used[id] = true; return id end
    local n = counter
    local cand
    repeat
        n = n + 1
        cand = prefix .. n
    until not used[cand]
    used[cand] = true
    return cand
end

function S.Shot(raw, weatherSet, fallbackId)
    if type(raw) ~= 'table' then return nil end
    local shot = {
        id = S.Id(raw.id) or fallbackId,
        name = S.Name(raw.name, 'Shot'),
        loop = S.Bool(raw.loop, false),
        keys = {},
        lights = {},
        shake = S.Shake(raw.shake),
        scene = S.Id(raw.scene), -- the placed scene whose camera this shot is
    }
    if type(raw.keys) == 'table' then
        local used = {}
        for i = 1, math.min(#raw.keys, Config.Timeline.MaxKeysPerShot) do
            local k = S.Key(raw.keys[i], weatherSet, nil)
            if k then
                k.id = uniqueId(used, k.id, 'key_', i)
                shot.keys[#shot.keys + 1] = k
            end
        end
        table.sort(shot.keys, function(a, b) return a.t < b.t end)
    end
    if type(raw.lights) == 'table' then
        local n = 0
        for id, v in pairs(raw.lights) do
            if n >= Config.Lights.Max then break end
            if S.Id(id) and v == false then shot.lights[id] = false; n = n + 1 end
        end
    end
    return shot
end

--- Rebuild a whole project document. Returns doc or nil, reason.
function S.Project(raw)
    if type(raw) ~= 'table' then return nil, 'not_a_table' end
    local v = tonumber(raw.v)
    if v ~= S.Version then return nil, 'schema_version' end
    local id = S.Id(raw.id)
    if not id then return nil, 'bad_id' end
    local weatherSet = CineWeatherSet()
    local doc = {
        v = S.Version,
        id = id,
        name = S.Name(raw.name, 'Untitled'),
        created = math.floor(S.Num(raw.created, 0, 4e9, 0)),
        updated = math.floor(S.Num(raw.updated, 0, 4e9, 0)),
        settings = { letterbox = 2.39, fps = 60, leadIn = Config.RockstarEditor.LeadIn, tail = Config.RockstarEditor.Tail, recSingle = Config.RockstarEditor.Single, recV = 2 },
        shots = {}, actors = {}, lights = {}, takes = {}, scenes = {},
    }
    if type(raw.settings) == 'table' then
        doc.settings.letterbox = S.Num(raw.settings.letterbox, 0.0, 4.0, 2.39)
        doc.settings.fps = math.floor(S.Num(raw.settings.fps, 1, 240, 60))
        doc.settings.leadIn = S.Num(raw.settings.leadIn, 0.0, Config.RockstarEditor.MaxLeadIn, Config.RockstarEditor.LeadIn)
        doc.settings.tail = S.Num(raw.settings.tail, 0.0, Config.RockstarEditor.MaxTail, Config.RockstarEditor.Tail)
        doc.settings.recSingle = S.Bool(raw.settings.recSingle, Config.RockstarEditor.Single)
        if raw.settings.recV ~= 2 and doc.settings.leadIn == 2.0 then doc.settings.leadIn = Config.RockstarEditor.LeadIn end
        doc.settings.recV = 2
    end
    local used = {}
    if type(raw.shots) == 'table' then
        for i = 1, math.min(#raw.shots, Config.Timeline.MaxShots) do
            local s = S.Shot(raw.shots[i], weatherSet, nil)
            if s then
                s.id = uniqueId(used, s.id, 'shot_', i)
                doc.shots[#doc.shots + 1] = s
            end
        end
    end
    used = {}
    if type(raw.actors) == 'table' then
        for i = 1, math.min(#raw.actors, Config.Actors.Max) do
            local a = S.Actor(raw.actors[i], nil)
            if a then
                a.id = uniqueId(used, a.id, 'act_', i)
                doc.actors[#doc.actors + 1] = a
            end
        end
    end
    used = {}
    if type(raw.lights) == 'table' then
        for i = 1, math.min(#raw.lights, Config.Lights.Max) do
            local l = S.Light(raw.lights[i], nil)
            if l then
                l.id = uniqueId(used, l.id, 'lgt_', i)
                doc.lights[#doc.lights + 1] = l
            end
        end
    end
    used = {}
    if type(raw.scenes) == 'table' then
        for i = 1, math.min(#raw.scenes, Config.Presets.MaxScenes) do
            local s = S.Scene(raw.scenes[i], nil)
            if s then
                s.id = uniqueId(used, s.id, 'scn_', i)
                doc.scenes[#doc.scenes + 1] = s
            end
        end
    end
    return doc
end

function S.NewProject(id, name, now)
    return {
        v = S.Version, id = id, name = S.Name(name, 'Untitled'),
        created = now or 0, updated = now or 0,
        settings = { letterbox = Config.Output.Letterbox.Ratio, fps = 60, leadIn = Config.RockstarEditor.LeadIn, tail = Config.RockstarEditor.Tail, recSingle = Config.RockstarEditor.Single, recV = 2 },
        shots = {}, actors = {}, lights = {}, takes = {}, scenes = {},
    }
end
