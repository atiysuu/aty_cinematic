-- The one scripted camera: create / apply state / destroy, DOF.
-- State shape (same as a timeline key): { pos = {x,y,z}, rot = {pitch, roll, yaw}, fov, dof = { on, near, far, str, target } }
Cine.Camera = { handle = nil, state = nil }
local C = Cine.Camera

local lastFov = nil
local focusDist = nil
local dofWasOn = false

function C.NewState(x, y, z, pitch, roll, yaw, fov)
    return {
        pos = { x, y, z }, rot = { pitch, roll, yaw }, fov = fov,
        dof = { on = false, near = Config.Dof.Defaults.near, far = Config.Dof.Defaults.far,
                str = Config.Dof.Defaults.strength, target = nil },
    }
end

--- Create the camera at the current gameplay camera pose. Returns the initial state.
function C.Create()
    if C.handle and DoesCamExist(C.handle) then return C.state end
    local p = GetGameplayCamCoord()
    local r = GetGameplayCamRot(2)
    local fov = GetGameplayCamFov()
    C.handle = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y, p.z, r.x, 0.0, r.z, fov, true, 2)
    C.state = C.NewState(p.x, p.y, p.z, r.x, 0.0, r.z, fov)
    lastFov = fov
    focusDist = nil
    dofWasOn = false
    return C.state
end

function C.Activate()
    if C.handle and DoesCamExist(C.handle) then
        SetCamActive(C.handle, true)
        RenderScriptCams(true, false, Config.Session.EaseInMs, true, false)
    end
end

--- Every step guarded so a failure cannot skip the rest of the teardown.
function C.Destroy()
    local h = C.handle
    C.handle = nil
    pcall(RenderScriptCams, false, false, Config.Session.EaseInMs, true, false)
    if h and DoesCamExist(h) then
        pcall(SetCamUseShallowDofMode, h, false)
        pcall(SetCamActive, h, false)
        pcall(DestroyCam, h, false)
    end
    lastFov = nil
    focusDist = nil
    dofWasOn = false
end

function C.Exists()
    return C.handle ~= nil and DoesCamExist(C.handle)
end

--- Apply a state to the camera (call every frame). dt for autofocus smoothing.
--- getTargetPos(id) -> {x,y,z} | nil resolves a DOF autofocus target.
--- fx = { pos = {dx,dy,dz} world metres, rot = {tilt,roll,pan} degrees in the camera's own frame } | nil:
--- render-only offsets (shake); C.state stays clean.
function C.Apply(state, dt, getTargetPos, fx)
    local h = C.handle
    if not h or not DoesCamExist(h) then return end
    C.state = state
    local p, r = state.pos, state.rot
    if fx then
        local o, q = fx.pos, fx.rot
        local rx, ry, rz = CineMath.ComposeRot(r[1], r[2], r[3], q[1], q[2], q[3])
        SetCamCoord(h, p[1] + o[1] + 0.0, p[2] + o[2] + 0.0, p[3] + o[3] + 0.0)
        SetCamRot(h, rx + 0.0, ry + 0.0, rz + 0.0, 2)
    else
        SetCamCoord(h, p[1] + 0.0, p[2] + 0.0, p[3] + 0.0)
        SetCamRot(h, r[1] + 0.0, r[2] + 0.0, r[3] + 0.0, 2)
    end
    if state.fov ~= lastFov then
        lastFov = state.fov
        SetCamFov(h, state.fov + 0.0)
    end

    local d = state.dof
    if Config.Dof.Enabled and d and d.on then
        local near, far = d.near, d.far
        if d.target and getTargetPos then
            local tp = getTargetPos(d.target)
            if tp then
                local dx, dy, dz = tp[1] - p[1], tp[2] - p[2], tp[3] - p[3]
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if focusDist then
                    focusDist = focusDist + (dist - focusDist) * CineMath.Smooth(Config.Dof.AutoFocusRate, dt)
                else
                    focusDist = dist
                end
                local half = math.max((far - near) * 0.5, 0.05)
                near = math.max(focusDist - half, 0.0)
                far = focusDist + half
            end
        else
            focusDist = nil
        end
        SetCamUseShallowDofMode(h, true)
        SetUseHiDof() -- must be called every tick
        SetCamNearDof(h, near + 0.0)
        SetCamFarDof(h, far + 0.0)
        SetCamDofStrength(h, d.str + 0.0)
        dofWasOn = true
    elseif dofWasOn then
        SetCamUseShallowDofMode(h, false)
        SetCamDofStrength(h, 0.0)
        dofWasOn = false
        focusDist = nil
    end
end
