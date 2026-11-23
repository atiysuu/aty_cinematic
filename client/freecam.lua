-- Free rig: dt-based movement with inertia, smoothed look, roll, FOV, speed.
-- Controls are polled as disabled reads (the session disables every control each frame).
Cine.Freecam = {}
local F = Cine.Freecam
local M = CineMath

local st = {
    x = 0.0, y = 0.0, z = 0.0, vx = 0.0, vy = 0.0, vz = 0.0,
    pitch = 0.0, yaw = 0.0, roll = 0.0, tpitch = 0.0, tyaw = 0.0,
    fov = Config.Freecam.Fov, speed = Config.Freecam.Speed,
    smooth = Config.Freecam.LookSmoothing,   -- 0..1
    inertia = Config.Freecam.Inertia,        -- 0..1
}
F.st = st

local out = nil

--- 0..1 slider value -> follow rate (1/s), exponential between the two ends so the slider feels even.
local function rate(amount, range)
    return range[1] * (range[2] / range[1]) ^ amount
end

function F.Speed() return st.speed end

--- Velocity follow factor for this frame, shared with the rigs that move (1 = snap to the keys).
function F.MoveBlend(dt, hasInput)
    if st.inertia <= 0.0 then return 1.0 end
    local k = rate(st.inertia, Config.Freecam.MoveRate)
    if not hasInput then k = k * 0.75 end
    return M.Smooth(k, dt)
end
function F.SmoothAmount() return st.smooth end
function F.Inertia() return st.inertia end

--- Look follow rate for the rigs (0 = instant).
function F.Smoothing()
    if st.smooth <= 0.0 then return 0.0 end
    return rate(st.smooth, Config.Freecam.LookRate)
end

function F.SetSpeed(v)
    st.speed = M.Clamp(v, Config.Freecam.MinSpeed, Config.Freecam.MaxSpeed)
end

function F.SetSmoothing(v)
    st.smooth = M.Clamp(v, 0.0, 1.0)
end

function F.SetInertia(v)
    st.inertia = M.Clamp(v, 0.0, 1.0)
end

function F.SetFov(v)
    st.fov = M.Clamp(v, Config.Freecam.FovMin, Config.Freecam.FovMax)
end

function F.ResetRoll()
    st.roll = 0.0
end

--- Continue from a camera state (key form): used when entering the free rig / leaving scrub.
function F.SetFromState(s)
    st.x, st.y, st.z = s.pos[1], s.pos[2], s.pos[3]
    st.pitch, st.roll, st.yaw = s.rot[1], s.rot[2], s.rot[3]
    st.tpitch, st.tyaw = st.pitch, st.yaw
    st.fov = s.fov
    st.vx, st.vy, st.vz = 0.0, 0.0, 0.0
end

local function pressed(c) return IsDisabledControlPressed(0, c) or IsControlPressed(0, c) end
local function justPressed(c) return IsDisabledControlJustPressed(0, c) or IsControlJustPressed(0, c) end

--- Advance the rig. ctx = { cursor, overUi, typing }. Returns the camera state and whether the
--- user gave any movement / look input this frame.
function F.Tick(dt, ctx, dof)
    local cfg, K = Config.Freecam, Config.Controls
    local any = false

    -- Look: always in fly mode, only while RMB is held (and not over a panel) in cursor mode.
    local looking = (not ctx.cursor) or (pressed(K.LookHold) and not ctx.overUi)
    if looking and not ctx.typing then
        local mx = GetDisabledControlNormal(0, K.LookX)
        local my = GetDisabledControlNormal(0, K.LookY)
        if mx ~= 0.0 or my ~= 0.0 then any = true end
        local sens = cfg.LookSensitivity * (pressed(K.Slow) and cfg.PreciseLook or 1.0) -- Ctrl = fine aim
        st.tyaw = st.tyaw - mx * sens
        st.tpitch = M.Clamp(st.tpitch - my * sens, -cfg.PitchLimit, cfg.PitchLimit)
    end
    local lk = F.Smoothing()
    if lk > 0.0 then
        local a = M.Smooth(lk, dt)
        st.yaw = st.yaw + (st.tyaw - st.yaw) * a
        st.pitch = st.pitch + (st.tpitch - st.pitch) * a
    else
        st.yaw, st.pitch = st.tyaw, st.tpitch
    end

    if not ctx.typing then
        -- Roll
        if pressed(K.RollLeft) then st.roll = st.roll - cfg.RollRate * dt; any = true end
        if pressed(K.RollRight) then st.roll = st.roll + cfg.RollRate * dt; any = true end

        -- Scroll: speed, or FOV while Fast (Shift) is held. Ignored while the pointer is over a panel.
        if not ctx.overUi and not Cine.Placer.active then
            local up, down = justPressed(K.ScrollUp), justPressed(K.ScrollDown)
            if up or down then
                if pressed(K.Fast) then
                    local d = up and -cfg.FovStep or cfg.FovStep
                    st.fov = M.Clamp(st.fov + d, cfg.FovMin, cfg.FovMax)
                elseif up then
                    F.SetSpeed(st.speed * cfg.SpeedStep)
                else
                    F.SetSpeed(st.speed / cfg.SpeedStep)
                end
            end
        end
    end

    -- Movement
    local fx, fy, fz, rx, ry = M.Basis(st.pitch, st.yaw)
    local ix, iy, iz = 0.0, 0.0, 0.0
    if not ctx.typing then
        local f = (pressed(K.Forward) and 1.0 or 0.0) - (pressed(K.Back) and 1.0 or 0.0)
        local r = (pressed(K.Right) and 1.0 or 0.0) - (pressed(K.Left) and 1.0 or 0.0)
        local u = (pressed(K.Up) and 1.0 or 0.0) - (pressed(K.Down) and 1.0 or 0.0)
        ix, iy, iz = fx * f + rx * r, fy * f + ry * r, fz * f + u
    end
    local len = math.sqrt(ix * ix + iy * iy + iz * iz)
    local hasInput = len > 0.001
    if hasInput then any = true; ix, iy, iz = ix / len, iy / len, iz / len end

    local mult = 1.0
    if pressed(K.Fast) then mult = cfg.FastMult elseif pressed(K.Slow) then mult = cfg.SlowMult end
    local tvx, tvy, tvz = ix * st.speed * mult, iy * st.speed * mult, iz * st.speed * mult
    -- inertia 0: velocity snaps to the keys (stops dead); higher: speeds up and glides out
    local a = 1.0
    if st.inertia > 0.0 then
        local k = rate(st.inertia, cfg.MoveRate)
        if not hasInput then k = k * 0.75 end -- the glide out is a little longer than the ramp up
        a = M.Smooth(k, dt)
    end
    st.vx = st.vx + (tvx - st.vx) * a
    st.vy = st.vy + (tvy - st.vy) * a
    st.vz = st.vz + (tvz - st.vz) * a
    st.x, st.y, st.z = st.x + st.vx * dt, st.y + st.vy * dt, st.z + st.vz * dt

    out = out or Cine.Camera.NewState(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, st.fov)
    out.pos[1], out.pos[2], out.pos[3] = st.x, st.y, st.z
    out.rot[1], out.rot[2], out.rot[3] = st.pitch, st.roll, st.yaw
    out.fov = st.fov
    out.dof = dof
    return out, any
end
