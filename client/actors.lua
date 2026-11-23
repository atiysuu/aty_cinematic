-- Local (non-networked) actors: peds, owner clone, vehicles. Static staging only (MVP).
-- Entities exist only on this client; the model pin is released right after each create.
Cine.Actors = { ent = {}, selected = {} }   -- selected = ids of the actors picked in the Actors panel
local A = Cine.Actors

--- Entity handle of an actor, or nil if it is gone.
function A.GetEntity(id)
    local e = id and A.ent[id]
    if e and DoesEntityExist(e) then return e end
    return nil
end

--- World position of an actor entity as {x, y, z} (DOF autofocus / rigs).
function A.GetPos(id)
    local e = A.GetEntity(id)
    if not e then return nil end
    local c = GetEntityCoords(e)
    return { c.x, c.y, c.z }
end

local function loadVehicleModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local deadline = GetGameTimer() + Config.Actors.ModelLoadTimeoutMs
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return false end
        Wait(50)
    end
    return true
end

local function settle(e, isPed)
    SetEntityAsMissionEntity(e, true, true)
    SetEntityInvincible(e, Config.Actors.Invincible)
    if isPed then
        SetBlockingOfNonTemporaryEvents(e, true)
        SetPedKeepTask(e, true)
        SetPedCanRagdoll(e, false)
    end
end

--- Put the entity at the stored transform.
function A.Place(a, e)
    local p, r = a.pos, a.rot
    SetEntityCoordsNoOffset(e, p[1] + 0.0, p[2] + 0.0, p[3] + 0.0, false, false, false)
    if a.kind == 'vehicle' then
        SetEntityRotation(e, r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, 2, true)
    else
        SetEntityHeading(e, r[3] + 0.0)
    end
end

--- Start the stored animation or scenario on a ped actor. Returns ok.
function A.PlayAnim(a)
    local e = A.GetEntity(a.id)
    if not e or a.kind == 'vehicle' then return false end
    FreezeEntityPosition(e, false)
    ClearPedTasksImmediately(e)
    A.Place(a, e)
    local ok = true
    if a.anim then
        local dict = a.anim.dict
        if not DoesAnimDictExist(dict) then
            Cine.Notify(_L('anim_missing', dict), 'error')
            ok = false
        else
            Modules.LoadAnimDict(dict)
            if HasAnimDictLoaded(dict) then
                TaskPlayAnim(e, dict, a.anim.name, 8.0, -8.0, -1, a.anim.flag or 1, 0.0, false, false, false)
                RemoveAnimDict(dict)
            else
                Cine.Notify(_L('anim_missing', dict), 'error')
                ok = false
            end
        end
    elseif a.scenario then
        TaskStartScenarioInPlace(e, a.scenario, 0, true)
    end
    FreezeEntityPosition(e, true)
    return ok
end

--- Start a two-person emote: both dictionaries are loaded first, then both clips are started in
--- the same frame so the two stay in step. Yields (dictionary load). Returns ok.
function A.PlayPair(a, b)
    local ea, eb = A.GetEntity(a.id), A.GetEntity(b.id)
    if not ea or not eb or not a.anim or not b.anim then return false end
    for _, dict in ipairs({ a.anim.dict, b.anim.dict }) do
        if DoesAnimDictExist(dict) then Modules.LoadAnimDict(dict) end
        if not DoesAnimDictExist(dict) or not HasAnimDictLoaded(dict) then
            Cine.Notify(_L('anim_missing', dict), 'error')
            return false
        end
    end
    for _, x in ipairs({ { a, ea }, { b, eb } }) do
        FreezeEntityPosition(x[2], false)
        ClearPedTasksImmediately(x[2])
        A.Place(x[1], x[2])
    end
    TaskPlayAnim(ea, a.anim.dict, a.anim.name, 8.0, -8.0, -1, a.anim.flag or 0, 0.0, false, false, false)
    TaskPlayAnim(eb, b.anim.dict, b.anim.name, 8.0, -8.0, -1, b.anim.flag or 0, 0.0, false, false, false)
    RemoveAnimDict(a.anim.dict)
    if b.anim.dict ~= a.anim.dict then RemoveAnimDict(b.anim.dict) end
    FreezeEntityPosition(ea, true)
    FreezeEntityPosition(eb, true)
    return true
end

--- Start again what belongs to the start of a shot: emotes that play once, and two-person
--- emotes (in step). Looping emotes and scenarios keep running. pairsOnly = only the pairs
--- (after a project load, where each half started when its own ped spawned).
function A.Restart(pairsOnly)
    local p = Cine.Store.project
    if not p then return end
    local token = Cine.Session.token
    CreateThread(function()
        -- a playback that preloads its first frame starts moving a moment later: start with it
        local deadline = GetGameTimer() + 6000
        while Cine.Timeline.preloading and GetGameTimer() < deadline do Wait(0) end
        local done = {}
        for _, a in ipairs(p.actors) do
            if Cine.Session.token ~= token then return end
            if a.kind ~= 'vehicle' and a.anim and not done[a.id] then
                local partner = a.pair and Cine.Store.GetActor(a.pair) or nil
                if partner and partner.pair == a.id and partner.anim then
                    done[a.id], done[partner.id] = true, true
                    pcall(A.PlayPair, a, partner)
                elseif not pairsOnly and (a.anim.flag or 1) % 2 == 0 then
                    pcall(A.PlayAnim, a)
                end
            end
        end
    end)
end

--- Spawn the entity of an actor (yields). fresh = true for a newly added actor (vehicles are put on the ground and
--- the settled position is written back to the actor). Safe to call from a thread only.
function A.Spawn(a, fresh)
    if A.GetEntity(a.id) then return A.ent[a.id] end
    local token = Cine.Session.token
    local p = a.pos
    local e = nil

    if a.kind == 'clone' then
        e = ClonePed(PlayerPedId(), false, false, true)
        if not e or e == 0 then e = nil end
    elseif a.kind == 'ped' then
        e = Modules.CreatePedOnCoord(p[1] + 0.0, p[2] + 0.0, p[3] + 0.0, a.rot[3] + 0.0, a.model, false, false, Config.Actors.Invincible)
        if not e or e == 0 then e = nil end
    elseif a.kind == 'vehicle' then
        local hash = GetHashKey(a.model)
        local loaded = loadVehicleModel(hash)
        if loaded and Cine.Session.token == token then
            e = CreateVehicle(hash, p[1] + 0.0, p[2] + 0.0, p[3] + 0.0, a.rot[3] + 0.0, false, false)
            if not e or e == 0 then e = nil end
        end
        SetModelAsNoLongerNeeded(hash) -- always release, also when the create failed
    end

    if not e then
        Cine.Notify(_L('model_failed', tostring(a.model or a.kind)), 'error')
        return nil
    end
    if Cine.Session.token ~= token or not Cine.Session.active then
        if IsEntityAPed(e) then
            Modules.RemovePed(e)
        else
            SetEntityAsMissionEntity(e, true, true)
            DeleteEntity(e)
        end
        return nil
    end

    -- deleted from the project while the model was loading (a scene removed right after it was
    -- placed): nobody would ever remove this entity
    if (Cine.Store.GetActor(a.id)) ~= a then
        if IsEntityAPed(e) then
            Modules.RemovePed(e)
        else
            SetEntityAsMissionEntity(e, true, true)
            DeleteEntity(e)
        end
        return nil
    end

    settle(e, a.kind ~= 'vehicle')
    if a.kind == 'vehicle' then
        if a.props and Modules.SetVehicleProperties ~= nil then pcall(Modules.SetVehicleProperties, e, a.props) end
        SetVehicleEngineOn(e, true, true, true)
        SetVehicleDoorsLocked(e, 2)
        SetVehicleTyresCanBurst(e, false)
        if fresh then
            SetEntityCoordsNoOffset(e, p[1] + 0.0, p[2] + 0.0, p[3] + 0.0, false, false, false)
            SetVehicleOnGroundProperly(e)
            local c = GetEntityCoords(e)
            local r = GetEntityRotation(e, 2)
            a.pos = { c.x, c.y, c.z }
            a.rot = { r.x, r.y, r.z }
            Cine.Store.Touch()
        end
    end
    A.ent[a.id] = e
    A.Place(a, e)
    if a.kind ~= 'vehicle' and (a.anim or a.scenario) then
        A.PlayAnim(a)
    else
        FreezeEntityPosition(e, true)
    end
    return e
end

--- Spawn every actor of a list, one at a time; one failure never blocks the others.
function A.SpawnAll(list)
    local token = Cine.Session.token
    CreateThread(function()
        for _, a in ipairs(list) do
            if Cine.Session.token ~= token then return end
            local ok, err = pcall(A.Spawn, a, false)
            if not ok then Cine.Err('actor %s failed: %s', tostring(a.id), tostring(err)) end
        end
        A.Restart(true) -- everyone is there: put the two-person emotes in step
    end)
end

-- Selection highlight ----------------------------------------------------------------------------
-- Drawn by script every frame: corner brackets around the actor's bounding box and a ring on the
-- ground. The game's own entity outline (SetEntityDrawOutline) is NOT used: on a ped it crashes
-- the game inside the renderer (GTA5_b3889.exe+8FC265, 2026-11-23; see bug-lessons).

--- Mark the actors picked in the panel (A.selected). show = false hides them (clean view,
--- playback, recording). Call every frame; nothing to undo afterwards.
local mark

function A.Highlight(show)
    local cfg = Config.Actors.Highlight
    if not show or not cfg then return end
    for _, id in ipairs(A.selected) do
        local e = A.GetEntity(id)
        if e then mark(e, cfg) end
    end
end

mark = function(e, cfg)
    local c = cfg.Color
    local lo, hi = GetModelDimensions(GetEntityModel(e))
    local xs, ys, zs = { lo.x, hi.x }, { lo.y, hi.y }, { lo.z, hi.z }
    local f = cfg.Bracket
    -- a short line from every corner of the box along each of its three edges
    for i = 1, 2 do
        for j = 1, 2 do
            for k = 1, 2 do
                local x, y, z = xs[i], ys[j], zs[k]
                local p = GetOffsetFromEntityInWorldCoords(e, x, y, z)
                local qx = GetOffsetFromEntityInWorldCoords(e, x + (xs[3 - i] - x) * f, y, z)
                local qy = GetOffsetFromEntityInWorldCoords(e, x, y + (ys[3 - j] - y) * f, z)
                local qz = GetOffsetFromEntityInWorldCoords(e, x, y, z + (zs[3 - k] - z) * f)
                DrawLine(p.x, p.y, p.z, qx.x, qx.y, qx.z, c[1], c[2], c[3], c[4])
                DrawLine(p.x, p.y, p.z, qy.x, qy.y, qy.z, c[1], c[2], c[3], c[4])
                DrawLine(p.x, p.y, p.z, qz.x, qz.y, qz.z, c[1], c[2], c[3], c[4])
            end
        end
    end
    if cfg.Ring then
        local p = GetEntityCoords(e)
        local radius = math.max(math.abs(lo.x), math.abs(hi.x), math.abs(lo.y), math.abs(hi.y)) + 0.2
        DrawMarker(25, p.x, p.y, p.z - GetEntityHeightAboveGround(e) + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            radius * 2.0, radius * 2.0, 1.0, c[1], c[2], c[3], 170, false, false, 2, false, nil, nil, false)
    end
end

function A.Remove(id)
    local e = A.ent[id]
    A.ent[id] = nil
    if not e or not DoesEntityExist(e) then return end
    if IsEntityAPed(e) then
        Modules.RemovePed(e)
    else
        SetEntityAsMissionEntity(e, true, true)
        DeleteEntity(e)
    end
end

function A.DespawnAll()
    local ids = {}
    for id in pairs(A.ent) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do pcall(A.Remove, id) end
    A.ent = {}
    A.selected = {}
end
