-- aty_cinematic server: ACE gate, project callbacks, latent save / load transport.
local Modules, Utils, Shared

local RES = GetCurrentResourceName()
local EV_SAVE = 'aty_cinematic:server:save'
local EV_SAVED = 'aty_cinematic:client:saved'
local EV_LOADED = 'aty_cinematic:client:loaded'

CreateThread(function()
    while GetResourceState('aty_lib') ~= 'started' do Wait(100) end
    Modules = exports['aty_lib']:getModules()
    Utils   = exports['aty_lib']:getUtils()
    Shared  = exports['aty_lib']:getShared()
    if Modules == nil then
        print(('^1[%s] aty_lib returned no modules, the director cannot run.^7'):format(RES))
        return
    end
    RegisterCallbacks()
end)

--- ACE is re-checked on EVERY call (no cached grant: it can be revoked live).
local function allowed(src)
    if type(src) ~= 'number' or src <= 0 then return false end
    if not Config.Access.Ace then return true end
    if IsPlayerAceAllowed(src, Config.Access.Ace) then return true end
    local levels = Config.Access.FrameworkLevels
    if levels and Modules ~= nil and Modules.HasPermission ~= nil then
        local ok, res = pcall(Modules.HasPermission, src, levels)
        return ok and res == true
    end
    return false
end

local lastCall = {}
local busy = {}

local function gap(src)
    local now = GetGameTimer()
    if lastCall[src] and now - lastCall[src] < 300 then return false end
    lastCall[src] = now
    return true
end

AddEventHandler('playerDropped', function()
    local src = source
    lastCall[src] = nil
    busy[src] = nil
end)

local DENIED = { ok = false, reason = 'denied' }

--- Wrap a callback body: ACE gate, rate gap, never throw into aty_lib.
local function guarded(fn)
    return function(src, args)
        if not allowed(src) then return DENIED end
        if not gap(src) then return { ok = false, reason = 'rate_limited' } end
        local ok, res = pcall(fn, src, type(args) == 'table' and args or {})
        if not ok then
            print(('^1[%s] callback error: %s^7'):format(RES, tostring(res)))
            return { ok = false, reason = 'server_error' }
        end
        return res
    end
end

function RegisterCallbacks()
    Modules.RegisterCallback('aty_cinematic:open', guarded(function()
        return { ok = true, projects = Storage.List() }
    end))

    Modules.RegisterCallback('aty_cinematic:list', guarded(function()
        return { ok = true, projects = Storage.List() }
    end))

    Modules.RegisterCallback('aty_cinematic:create', guarded(function(_, a)
        local id, doc = Storage.Create(a.name)
        if not id then return { ok = false, reason = doc } end
        return { ok = true, id = id, project = doc, projects = Storage.List() }
    end))

    Modules.RegisterCallback('aty_cinematic:load', guarded(function(src, a)
        if a.kind ~= 'project' then return { ok = false, reason = 'bad_kind' } end
        local id = CineSchema.Id(a.id)
        local reqId = math.floor(CineSchema.Num(a.reqId, 0, 2147483647, 0))
        if not id then return { ok = false, reason = 'bad_id' } end
        local raw = Storage.Read(id)
        if not raw then return { ok = false, reason = 'not_found' } end
        TriggerLatentClientEvent(EV_LOADED, src, Config.Storage.LatentBps,
            { reqId = reqId, kind = 'project', id = id, json = raw })
        return { ok = true }
    end))

    Modules.RegisterCallback('aty_cinematic:delete', guarded(function(_, a)
        local id = CineSchema.Id(a.id)
        if not id then return { ok = false, reason = 'bad_id' } end
        local ok, why = Storage.Delete(id)
        return { ok = ok, reason = why, projects = Storage.List() }
    end))

    Modules.RegisterCallback('aty_cinematic:rename', guarded(function(_, a)
        local id = CineSchema.Id(a.id)
        if not id then return { ok = false, reason = 'bad_id' } end
        local ok, why = Storage.Rename(id, a.name)
        return { ok = ok, reason = why, projects = Storage.List() }
    end))

    Modules.RegisterCallback('aty_cinematic:duplicate', guarded(function(_, a)
        local id = CineSchema.Id(a.id)
        if not id then return { ok = false, reason = 'bad_id' } end
        local newId, why = Storage.Duplicate(id, a.newName)
        if not newId then return { ok = false, reason = why } end
        return { ok = true, id = newId, projects = Storage.List() }
    end))
end

--- Project save (latent from the client). ACE -> busy guard -> checks -> sanitize -> write -> ack.
RegisterNetEvent(EV_SAVE, function(payload)
    local src = source
    if type(payload) ~= 'table' then return end
    local reqId = math.floor(CineSchema.Num(payload.reqId, 0, 2147483647, 0))

    local function ack(ok, reason, bytes, savedAt)
        TriggerClientEvent(EV_SAVED, src, { reqId = reqId, ok = ok, reason = reason, bytes = bytes, savedAt = savedAt })
    end

    if not allowed(src) then return ack(false, 'denied') end
    if busy[src] then return ack(false, 'busy') end
    busy[src] = true
    local ok, a, b, c, d = pcall(function()
        if payload.kind ~= 'project' then return false, 'bad_kind' end
        local id = CineSchema.Id(payload.id)
        if not id then return false, 'bad_id' end
        return Storage.Save(id, payload.json)
    end)
    busy[src] = nil
    if not ok then
        print(('^1[%s] save error: %s^7'):format(RES, tostring(a)))
        return ack(false, 'server_error')
    end
    ack(a, b, c, d)
end)
