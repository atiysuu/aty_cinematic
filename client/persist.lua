-- Save / load bridge to the server. Small calls go through aty_lib callbacks, the project document
-- (up to Config.Storage.MaxProjectBytes) travels as a latent event with a reqId and an explicit ack.
Cine.Persist = { saving = false, lastSaveAt = 0 }
local P = Cine.Persist

local reqCounter = 0
local pendingSave = nil     -- { reqId, deadline }
local pendingLoad = nil     -- { reqId, id }

local function nextReq()
    reqCounter = reqCounter + 1
    return reqCounter
end

local function reasonText(r)
    return tostring(r or 'unknown')
end

--- Callback wrapper: every server call goes through aty_lib, never throws into the NUI.
local function call(name, args)
    local ok, res = pcall(Modules.TriggerCallback, name, args or {})
    if not ok or type(res) ~= 'table' then return { ok = false, reason = 'no_answer' } end
    return res
end

function P.Open()
    return call('aty_cinematic:open')
end

function P.List()
    return call('aty_cinematic:list')
end

function P.Create(name)
    local res = call('aty_cinematic:create', { name = name })
    if res.ok and res.project then
        local doc = CineSchema.Project(res.project)
        if doc then Cine.Store.Load(doc) else res = { ok = false, reason = 'bad_schema' } end
    end
    return res
end

function P.Rename(id, name)
    return call('aty_cinematic:rename', { id = id, name = name })
end

function P.Duplicate(id, newName)
    return call('aty_cinematic:duplicate', { id = id, newName = newName })
end

function P.Delete(id)
    local res = call('aty_cinematic:delete', { id = id })
    local proj = Cine.Store.project
    if res.ok and proj and proj.id == id then Cine.Store.Unload() end
    return res
end

--- Request a project from the server; the document arrives as a latent client event.
function P.Load(id)
    local reqId = nextReq()
    pendingLoad = { reqId = reqId, id = id }
    local res = call('aty_cinematic:load', { kind = 'project', id = id, reqId = reqId })
    if not res.ok then
        pendingLoad = nil
        Cine.Notify(_L('load_failed', reasonText(res.reason)), 'error')
    end
    return res
end

--- Send the open project to the server (non-blocking). The result goes to the NUI as 'saveResult'.
function P.Save(silent)
    local proj = Cine.Store.project
    if not proj then Cine.Notify(_L('no_project'), 'error'); return false end
    if pendingSave then return false end
    local doc = CineSchema.Project(proj)
    if not doc then
        Cine.Nui.Send('saveResult', { ok = false, reason = 'bad_schema' })
        return false
    end
    local enc = json.encode(doc)
    if #enc > Config.Storage.MaxProjectBytes then
        Cine.Nui.Send('saveResult', { ok = false, reason = 'too_large' })
        Cine.Notify(_L('save_failed', 'too_large'), 'error')
        return false
    end
    local reqId = nextReq()
    pendingSave = { reqId = reqId, silent = silent == true, deadline = GetGameTimer() + Config.Storage.SaveTimeoutMs, revAtSend = Cine.Store.rev }
    P.saving = true
    Cine.Nui.Send('state', Cine.Session.StatePayload())
    TriggerLatentServerEvent('aty_cinematic:server:save', Config.Storage.LatentBps,
        { reqId = reqId, kind = 'project', id = doc.id, json = enc })
    return true
end

--- Per-frame housekeeping: save timeout + autosave. Cheap.
function P.Tick()
    if pendingSave and GetGameTimer() > pendingSave.deadline then
        pendingSave = nil
        P.saving = false
        Cine.Nui.Send('saveResult', { ok = false, reason = 'timeout' })
        Cine.Nui.Send('state', Cine.Session.StatePayload())
    end
    local every = Config.Storage.AutosaveSec
    if every > 0 and not pendingSave and Cine.Store.project and Cine.Store.dirty
        and GetGameTimer() - P.lastSaveAt > every * 1000 then
        P.lastSaveAt = GetGameTimer()
        P.Save(true)
    end
end

function P.Reset()
    pendingSave, pendingLoad, P.saving = nil, nil, false
    P.lastSaveAt = GetGameTimer()
end

RegisterNetEvent('aty_cinematic:client:saved', function(payload)
    if type(payload) ~= 'table' or not pendingSave or payload.reqId ~= pendingSave.reqId then return end
    local silent = pendingSave.silent
    local sentRev = pendingSave.revAtSend
    pendingSave = nil
    P.saving = false
    P.lastSaveAt = GetGameTimer()
    if payload.ok == true then
        -- edits made while the save was in flight keep the project dirty
        if Cine.Store.rev == sentRev then Cine.Store.dirty = false end
        Cine.Nui.Send('saveResult', { ok = true, savedAt = payload.savedAt, silent = silent })
        if not silent then Cine.Notify(_L('saved'), 'success') end
    else
        Cine.Nui.Send('saveResult', { ok = false, reason = reasonText(payload.reason) })
        Cine.Notify(_L('save_failed', reasonText(payload.reason)), 'error')
    end
    Cine.Nui.Send('state', Cine.Session.StatePayload())
end)

RegisterNetEvent('aty_cinematic:client:loaded', function(payload)
    if type(payload) ~= 'table' or not pendingLoad or payload.reqId ~= pendingLoad.reqId then return end
    pendingLoad = nil
    if type(payload.json) ~= 'string' or #payload.json > Config.Storage.MaxProjectBytes then
        Cine.Notify(_L('load_failed', 'bad_payload'), 'error')
        return
    end
    local ok, decoded = pcall(json.decode, payload.json)
    local doc = ok and type(decoded) == 'table' and CineSchema.Project(decoded) or nil
    if not doc then
        Cine.Notify(_L('load_failed', 'bad_schema'), 'error')
        return
    end
    if not Cine.Session.active then return end
    Cine.Store.Load(doc)
end)
