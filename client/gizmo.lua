-- DrawGizmo wrapper for actor entities and virtual light matrices.
-- Engine commands (+gizmoSelect / +gizmoTranslation / +gizmoRotation / +gizmoLocal) are pressed ONLY from
-- inside key-mapping handlers (bug-lessons: ExecuteCommand on engine commands is denied from threads and
-- NUI callbacks). The handlers are registered in input.lua and call G.OnSelect / G.OnMode / G.OnSpace.
Cine.Gizmo = { active = false, kind = nil, id = nil, mode = 'translate', space = 'world' }
local G = Cine.Gizmo
local M = CineMath

local buf = nil
local cursorOn = false
local selectHeld, modeHeld, spaceHeld = false, nil, false
local sawSelect = false
local startedAt = 0

local MODE_CMD = { translate = 'gizmoTranslation', rotate = 'gizmoRotation' }

local function setMatrix(view, r, f, u, p)
    view:SetFloat32(0, r[1]):SetFloat32(4, r[2]):SetFloat32(8, r[3]):SetFloat32(12, 0)
        :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
        :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
        :SetFloat32(48, p[1]):SetFloat32(52, p[2]):SetFloat32(56, p[3]):SetFloat32(60, 1)
end

local function normalize(x, y, z)
    local l = math.sqrt(x * x + y * y + z * z)
    if l == 0 then return 0.0, 0.0, 0.0 end
    return x / l, y / l, z / l
end

--- Euler (GTA order 2, degrees) from an orthonormal basis; same convention as aty_mapeditor.
local function basisToEuler(fx, fy, fz, rx, ry, rz, ux, uy, uz)
    local c = M.Clamp(fz, -1.0, 1.0)
    return math.deg(math.asin(c)), math.deg(math.atan(-rz, uz)), math.deg(math.atan(-fx, fy))
end

local function target()
    if G.kind == 'actor' then
        local a = Cine.Store.GetActor(G.id)
        return a, a and Cine.Actors.GetEntity(G.id)
    elseif G.kind == 'light' then
        return Cine.Store.GetLight(G.id), nil
    end
end

local function buildMatrix()
    local obj, ent = target()
    if not obj then return false end
    buf = buf or DataView.ArrayBuffer(64)
    if ent then
        local f, r, u, p = GetEntityMatrix(ent)
        setMatrix(buf, { r.x, r.y, r.z }, { f.x, f.y, f.z }, { u.x, u.y, u.z }, { p.x, p.y, p.z })
    else
        local fx, fy, fz, rx, ry = M.Basis(obj.rot[1], obj.rot[3])
        local r = { rx, ry, 0.0 }
        local f = { fx, fy, fz }
        -- up = right x forward
        local u = { r[2] * f[3] - r[3] * f[2], r[3] * f[1] - r[1] * f[3], r[1] * f[2] - r[2] * f[1] }
        setMatrix(buf, r, f, u, obj.pos)
    end
    return true
end

function G.Start(kind, id)
    if G.active then G.Stop() end
    G.kind, G.id = kind, id
    if not buildMatrix() then G.kind, G.id = nil, nil; return false end
    G.active = true
    G.warned = false
    sawSelect = false
    startedAt = GetGameTimer()
    Cine.Input.SetCursor(true)
    if not cursorOn then EnterCursorMode(); cursorOn = true end
    if kind == 'light' then Cine.Lights.selected = id end
    Cine.Nui.Send('gizmo', { active = true, kind = kind, id = id, mode = G.mode, space = G.space })
    return true
end

function G.Stop()
    local wasActive = G.active
    G.active = false
    G.kind, G.id = nil, nil
    Cine.Lights.selected = nil
    if cursorOn then pcall(LeaveCursorMode); cursorOn = false end
    selectHeld, modeHeld, spaceHeld = false, nil, false
    if wasActive then Cine.Nui.Send('gizmo', { active = false }) end
end

-- Key-mapping handlers (called from input.lua) ----------------------------------------------

function G.OnSelect(down)
    if down then
        sawSelect = true
        if not G.active or Cine.Input.overUi then return end
        selectHeld = true
        ExecuteCommand('+gizmoSelect')
    elseif selectHeld then
        selectHeld = false
        ExecuteCommand('-gizmoSelect')
    end
end

function G.OnMode(down)
    if down then
        if not G.active then return end
        G.mode = (G.mode == 'translate') and 'rotate' or 'translate'
        modeHeld = MODE_CMD[G.mode]
        ExecuteCommand('+' .. modeHeld)
        Cine.Nui.Send('gizmo', { active = true, kind = G.kind, id = G.id, mode = G.mode, space = G.space })
    elseif modeHeld then
        ExecuteCommand('-' .. modeHeld)
        modeHeld = nil
    end
end

function G.OnSpace(down)
    if down then
        if not G.active then return end
        G.space = (G.space == 'world') and 'local' or 'world'
        spaceHeld = true
        ExecuteCommand('+gizmoLocal')
        Cine.Nui.Send('gizmo', { active = true, kind = G.kind, id = G.id, mode = G.mode, space = G.space })
    elseif spaceHeld then
        spaceHeld = false
        ExecuteCommand('-gizmoLocal')
    end
end

--- Per frame while a session runs. Returns nothing; stops itself when the target is gone.
function G.Tick()
    if not G.active then return end
    local obj, ent = target()
    if not obj or (G.kind == 'actor' and not ent) then G.Stop(); return end
    if not Cine.Input.cursor then Cine.Input.SetCursor(true) end

    local changed = Citizen.InvokeNative(0xEB2EDCA2, buf:Buffer(), 'aty_cine', Citizen.ReturnResultAnyway())
    if not changed then
        if not sawSelect and GetGameTimer() - startedAt > 8000 and not G.warned then
            G.warned = true
            print(('^3[%s] gizmo: no select key press seen yet. Check the "Director: gizmo drag" key binding in FiveM settings.^7'):format(Cine.Resource))
        end
        return
    end

    local x1, y1, z1 = buf:GetFloat32(16), buf:GetFloat32(20), buf:GetFloat32(24)
    local x2, y2, z2 = buf:GetFloat32(0), buf:GetFloat32(4), buf:GetFloat32(8)
    local x3, y3, z3 = buf:GetFloat32(32), buf:GetFloat32(36), buf:GetFloat32(40)
    local px, py, pz = buf:GetFloat32(48), buf:GetFloat32(52), buf:GetFloat32(56)
    local fx, fy, fz = normalize(x1, y1, z1)
    local rx, ry, rz = normalize(x2, y2, z2)
    local ux, uy, uz = normalize(x3, y3, z3)

    if G.kind == 'actor' then
        local pitch, roll, yaw = basisToEuler(fx, fy, fz, rx, ry, rz, ux, uy, uz)
        -- one write per frame through one native family; never SetEntityMatrix on peds
        SetEntityCoordsNoOffset(ent, px, py, pz, false, false, false)
        SetEntityRotation(ent, pitch, roll, yaw, 2, true)
        Cine.Store.ActorTransform(G.id, { px, py, pz }, { pitch, roll, yaw })
    else
        local pitch, yaw = M.DirToRot(fx, fy, fz)
        Cine.Store.LightTransform(G.id, { px, py, pz }, { pitch, obj.rot[2], yaw })
    end
end
