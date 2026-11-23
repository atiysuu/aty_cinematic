-- "Put it where I look": actors follow the point under the mouse (or the centre of the picture
-- while flying with right mouse held), the wheel turns them, a left click drops them. A quick
-- alternative to the gizmo for staging peds and vehicles.
-- One actor or a group: the first one (the anchor) goes to the mouse, the others keep their place
-- in the formation, and the wheel turns the whole formation around the anchor.
Cine.Placer = { active = false, id = nil, count = 0 }
local PL = Cine.Placer
local M = CineMath

local members = nil     -- { { id, origin = { pos, rot }, dx, dy, lift } }, members[1] = the anchor
local heading = 0.0     -- the anchor's heading now
local heading0 = 0.0    -- ... and when placing started
local since = 0
local hit = nil         -- last surface point under the mouse { x, y, z }
local ghosts = {}       -- entities that were made see-through
local lastKey = nil     -- what was last written to the project (no write when nothing moved)

local function pressed(c) return IsDisabledControlPressed(0, c) or IsControlPressed(0, c) end
local function justPressed(c) return IsDisabledControlJustPressed(0, c) or IsControlJustPressed(0, c) end

local function notify()
    Cine.Nui.Send('state', Cine.Session.StatePayload())
end

--- Ray into the world from the mouse cursor (cursor mode) or from the centre of the screen (flying).
local function lookRay()
    local sx, sy = 0.5, 0.5
    if Cine.Input.cursor then
        local cx, cy = GetNuiCursorPosition()
        local w, h = (GetActualScreenResolution or GetActiveScreenResolution)()
        if cx and cy and w and h and w > 0 and h > 0 then
            sx, sy = M.Clamp(cx / w, 0.0, 1.0), M.Clamp(cy / h, 0.0, 1.0)
        end
    end
    return GetWorldCoordFromScreenCoord(sx + 0.0, sy + 0.0)
end

local function unghost()
    for e in pairs(ghosts) do
        if DoesEntityExist(e) then ResetEntityAlpha(e) end
    end
    ghosts = {}
end

--- Start placing. ids = one actor id or a list (the first is the anchor). Asking again for the same
--- selection drops it where it is.
function PL.Start(ids)
    if type(ids) ~= 'table' then ids = { ids } end
    local list, seen = {}, {}
    for _, id in ipairs(ids) do
        local a = Cine.Store.GetActor(id)
        if a and not seen[id] then
            seen[id] = true
            list[#list + 1] = a
        end
    end
    if #list == 0 then return false end
    if PL.active then
        local same = PL.id == list[1].id and PL.count == #list
        PL.Stop(true)
        if same then return true end
    end
    Cine.Gizmo.Stop()

    local anchor = list[1]
    members = {}
    for i, a in ipairs(list) do
        members[i] = {
            id = a.id,
            origin = { pos = { a.pos[1], a.pos[2], a.pos[3] }, rot = { a.rot[1], a.rot[2], a.rot[3] } },
            dx = a.pos[1] - anchor.pos[1], dy = a.pos[2] - anchor.pos[2],
            lift = a.kind ~= 'vehicle' and 1.0 or nil,     -- vehicles: measured once the entity exists
        }
    end
    PL.active, PL.id, PL.count = true, anchor.id, #list
    heading, heading0 = anchor.rot[3], anchor.rot[3]
    hit, lastKey = nil, nil
    since = GetGameTimer()
    notify()
    return true
end

--- End placing. keep = true drops the actors where they are, false puts them back where they were.
function PL.Stop(keep)
    if not PL.active then return end
    local list = members or {}
    PL.active, PL.id, PL.count = false, nil, 0
    members = nil
    unghost()
    for _, m in ipairs(list) do
        local a = Cine.Store.GetActor(m.id)
        local e = Cine.Actors.GetEntity(m.id)
        if a then
            if not keep then
                a.pos, a.rot = m.origin.pos, m.origin.rot
                if e then Cine.Actors.Place(a, e) end
            elseif e and a.kind == 'vehicle' then
                -- let the car settle on its wheels (slopes, kerbs) and keep that pose
                FreezeEntityPosition(e, false)
                SetVehicleOnGroundProperly(e)
                FreezeEntityPosition(e, true)
                local c, r = GetEntityCoords(e), GetEntityRotation(e, 2)
                a.pos, a.rot = { c.x, c.y, c.z }, { r.x, r.y, r.z }
            end
        end
    end
    Cine.Store.Touch()
    hit, lastKey = nil, nil
    notify()
end

--- Per frame while a session runs.
function PL.Tick()
    if not PL.active then return end
    local St, A = Cine.Store, Cine.Actors
    if not St.GetActor(PL.id) then PL.Stop(true); return end        -- the anchor was deleted: drop the rest
    for i = #members, 2, -1 do
        if not St.GetActor(members[i].id) then table.remove(members, i) end
    end
    PL.count = #members
    local I, K, cfg = Cine.Input, Config.Controls, Config.Placer
    local free = not I.overUi and not I.typing     -- the pointer is on the picture, not on a panel

    -- wheel turns it (Shift = big steps, Ctrl = fine)
    if free then
        local step = (pressed(K.Fast) and cfg.TurnFast) or (pressed(K.Slow) and cfg.TurnFine) or cfg.Turn
        if justPressed(K.ScrollUp) then heading = (heading + step) % 360.0 end
        if justPressed(K.ScrollDown) then heading = (heading - step) % 360.0 end
    end

    -- see-through while they follow; measure how high a vehicle's origin rides
    for _, m in ipairs(members) do
        local e = A.GetEntity(m.id)                 -- nil while the model still loads
        if e then
            if not ghosts[e] then
                SetEntityAlpha(e, cfg.Alpha, false)
                ghosts[e] = true
            end
            if not m.lift then m.lift = M.Clamp(GetEntityHeightAboveGround(e), 0.1, 2.0) end
        end
    end

    -- what is under the mouse? The anchor itself is ignored and peds are never a surface. A group
    -- also ignores vehicles, or it would climb onto its own cars.
    if free then
        local from, dir = lookRay()
        if from and dir and (dir.x ~= 0.0 or dir.y ~= 0.0 or dir.z ~= 0.0) then
            local far = cfg.Distance
            local probe = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z,
                from.x + dir.x * far, from.y + dir.y * far, from.z + dir.z * far,
                #members > 1 and 17 or 19, A.GetEntity(PL.id) or 0, 7)
            local status, found, c = GetShapeTestResult(probe)
            if status == 2 and (found == true or found == 1) and c then hit = { c.x, c.y, c.z } end
        end
    end

    -- the anchor stands on the point; the others keep their place, turned with the formation
    local anchor = members[1]
    local bx, by = anchor.origin.pos[1], anchor.origin.pos[2]
    local bz = anchor.origin.pos[3] - (anchor.lift or 0.8)
    if hit then bx, by, bz = hit[1], hit[2], hit[3] end
    local delta = heading - heading0
    local key = string.format('%.3f/%.3f/%.3f/%.2f/%d', bx, by, bz, heading, #members)
    local moved = key ~= lastKey
    lastKey = key
    local dr = math.rad(delta)
    local c, s = math.cos(dr), math.sin(dr)
    local hr = math.rad(heading)
    for i, m in ipairs(members) do
        local x, y = bx + m.dx * c - m.dy * s, by + m.dx * s + m.dy * c
        local ground = bz
        if i > 1 and hit then ground = Cine.Ground(x, y, bz + 2.0) or bz end
        if moved then
            local a = St.GetActor(m.id)
            local e = A.GetEntity(m.id)
            St.ActorTransform(m.id, { x, y, ground + (m.lift or 0.8) }, { 0.0, 0.0, (m.origin.rot[3] + delta) % 360.0 })
            if e then A.Place(a, e) end
        end
        if hit then
            DrawMarker(25, x, y, ground + 0.04, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, i == 1 and 1.1 or 0.7, i == 1 and 1.1 or 0.7, 1.0,
                105, 255, 236, i == 1 and 190 or 120, false, false, 2, false, nil, nil, false)
        end
    end
    if hit then
        DrawLine(bx, by, bz + 0.06, bx - math.sin(hr) * 1.6, by + math.cos(hr) * 1.6, bz + 0.06, 105, 255, 236, 230)
    end

    -- left click on the picture drops them (not the click that started the placing)
    if free and GetGameTimer() - since > 250 and IsDisabledControlJustPressed(0, K.Place) then
        PL.Stop(true)
    end
end
