-- aty_lib bridge init (client) + shared namespace + small helpers.
Cine = {}
Cine.Resource = GetCurrentResourceName()
Cine.Ready = false

Modules, Utils, Shared = nil, nil, nil

CreateThread(function()
    while GetResourceState('aty_lib') ~= 'started' do Wait(100) end
    Modules = exports['aty_lib']:getModules()
    Utils   = exports['aty_lib']:getUtils()
    Shared  = exports['aty_lib']:getShared()
    Cine.Ready = Modules ~= nil
    if not Cine.Ready then
        print(('^1[%s] aty_lib returned no modules, the director cannot run.^7'):format(Cine.Resource))
    end
end)

--- Blocks until the bridge is usable. Returns false if it never arrives.
function Cine.WaitReady(timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 30000)
    while not Cine.Ready do
        if GetGameTimer() > deadline then return false end
        Wait(50)
    end
    return true
end

function Cine.Notify(message, kind)
    pcall(function()
        exports['aty_lib']:Notify({ title = 'Director', message = message, type = kind or 'info' })
    end)
end

function Cine.Debug(...)
    if Config.Debug then print(('[%s]'):format(Cine.Resource), ...) end
end

--- Print where the developer sees it (F8).
function Cine.Err(fmt, ...)
    print(('^1[%s] ' .. fmt .. '^7'):format(Cine.Resource, ...))
end

--- Real-time clock in seconds (see Config.Timeline.ClockSource and spec risk R3).
function Cine.Clock()
    if Config.Timeline.ClockSource == 'network' then
        return GetNetworkTimeAccurate() / 1000.0
    end
    return GetGameTimer() / 1000.0
end

local lists = {}
--- Load lists/<name>.json once (array of strings or of tables).
function Cine.List(name)
    if lists[name] then return lists[name] end
    local raw = LoadResourceFile(Cine.Resource, 'lists/' .. name .. '.json')
    local ok, decoded = false, nil
    if raw and raw ~= '' then ok, decoded = pcall(json.decode, raw) end
    lists[name] = (ok and type(decoded) == 'table') and decoded or {}
    return lists[name]
end

function Cine.Ground(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 0.0, false)
    if ok then return gz end
    return nil
end

--- Entity coordinates as a plain 3-array.
function Cine.EntityPos(e)
    local c = GetEntityCoords(e)
    return { c.x, c.y, c.z }
end
