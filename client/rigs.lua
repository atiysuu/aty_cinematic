-- Camera rigs: 'free' (Freecam), 'orbit' around an actor / point, 'follow' an actor with lag.
-- Rigs.Tick returns the camera state to apply (key form) and whether the user gave input.
Cine.Rigs = { mode = 'free', target = nil }
local R = Cine.Rigs
local M = CineMath

local orbit = { x = 0.0, y = 0.0, z = 0.0, hasPoint = false, pitch = 0.0, yaw = 0.0, tpitch = 0.0, tyaw = 0.0, dist = 6.0, roll = 0.0, fov = 50.0,
    lift = 0.0, spin = 0.0, ox = 0.0, oy = 0.0, vx = 0.0, vy = 0.0, vz = 0.0, cx = 0.0, cy = 0.0, cz = 0.0 }
-- lift / ox / oy = pivot offset (m) moved with Q E / W A S D, spin = automatic turn (deg/s)
local follow = { x = 0.0, y = 0.0, z = 0.0, pitch = 0.0, yaw = 0.0, roll = 0.0, fov = 50.0, scale = 1.0 }
local out = nil

local function pressed(c) return IsDisabledControlPressed(0, c) or IsControlPressed(0, c) end
local function justPressed(c) return IsDisabledControlJustPressed(0, c) or IsControlJustPressed(0, c) end

--- Aim point of an actor entity: head bone for peds, entity centre + lift otherwise.
local function targetPoint(actorId, lift)
    local e = Cine.Actors.GetEntity(actorId)
    if not e or not DoesEntityExist(e) then return nil end
    if IsEntityAPed(e) then
        local b = GetPedBoneCoords(e, Config.Rigs.Follow.LookBone, 0.0, 0.0, 0.0)
        return b.x, b.y, b.z, e
    end
    local c = GetEntityCoords(e)
    return c.x, c.y, c.z + (lift or 0.5), e
end

--- Switch rig, continuing from the current camera state so nothing jumps.
--- keep = re-seat the same rig on a new pose (after timeline preview) without resetting its settings.
--- Returns ok, reason.
function R.Set(mode, targetId, s, keep)
    if mode == 'free' then
        R.mode, R.target = 'free', nil
        Cine.Freecam.SetFromState(s)
        return true
    end
    if mode == 'orbit' then
        local cfg = Config.Rigs.Orbit
        local fx, fy, fz = M.Basis(s.rot[1], s.rot[3])
        local tx, ty, tz = targetPoint(targetId, cfg.HeightOffset)
        if tx then
            orbit.hasPoint = false
            orbit.x, orbit.y, orbit.z = tx, ty, tz
            local dx, dy, dz = tx - s.pos[1], ty - s.pos[2], tz - s.pos[3]
            orbit.dist = M.Clamp(math.sqrt(dx * dx + dy * dy + dz * dz), cfg.MinDistance, cfg.MaxDistance)
            orbit.pitch, orbit.yaw = M.DirToRot(dx, dy, dz)
            R.target = targetId
        else
            -- No actor: orbit a point straight ahead of the camera.
            orbit.hasPoint = true
            if not keep then orbit.dist = cfg.Distance end -- re-seated: keep the radius the user set
            local d = orbit.dist
            orbit.x, orbit.y, orbit.z = s.pos[1] + fx * d, s.pos[2] + fy * d, s.pos[3] + fz * d
            orbit.pitch, orbit.yaw = s.rot[1], s.rot[3]
            R.target = nil
        end
        orbit.tpitch, orbit.tyaw = orbit.pitch, orbit.yaw
        orbit.roll, orbit.fov = s.rot[2], s.fov
        orbit.lift, orbit.ox, orbit.oy = 0.0, 0.0, 0.0
        orbit.vx, orbit.vy, orbit.vz = 0.0, 0.0, 0.0
        if not keep then orbit.spin = cfg.AutoSpeed end
        R.mode = 'orbit'
        return true
    end
    if mode == 'follow' then
        local tx = targetPoint(targetId, 0.5)
        if not tx then return false, 'need_actor' end
        follow.x, follow.y, follow.z = s.pos[1], s.pos[2], s.pos[3]
        follow.pitch, follow.yaw, follow.roll, follow.fov = s.rot[1], s.rot[3], s.rot[2], s.fov
        if not keep then follow.scale = 1.0 end
        R.target = targetId
        R.mode = 'follow'
        return true
    end
    return false, 'bad_rig'
end

--- Orbit data for a key taken right now (nil when not orbiting).
function R.OrbitKey()
    if R.mode ~= 'orbit' then return nil end
    return { c = { orbit.cx, orbit.cy, orbit.cz }, d = orbit.dist }
end

--- Live orbit values for the Camera panel.
function R.OrbitInfo()
    return { dist = orbit.dist, lift = orbit.lift, spin = orbit.spin }
end

--- Panel edits: { dist?, lift?, spin? } (already range-checked by the NUI callback).
function R.SetOrbit(p)
    local cfg = Config.Rigs.Orbit
    if p.dist then orbit.dist = M.Clamp(p.dist, cfg.MinDistance, cfg.MaxDistance) end
    if p.lift then orbit.lift = M.Clamp(p.lift, cfg.MinLift, cfg.MaxLift) end
    if p.spin then orbit.spin = M.Clamp(p.spin, -cfg.MaxSpin, cfg.MaxSpin) end
end

function R.SetFov(v)
    local f = M.Clamp(v, Config.Freecam.FovMin, Config.Freecam.FovMax)
    orbit.fov, follow.fov = f, f
    Cine.Freecam.SetFov(f)
end

function R.ResetRoll()
    orbit.roll, follow.roll = 0.0, 0.0
    Cine.Freecam.ResetRoll()
end

function R.Fov()
    if R.mode == 'orbit' then return orbit.fov end
    if R.mode == 'follow' then return follow.fov end
    return Cine.Freecam.st.fov
end

local function tickOrbit(dt, ctx, dof)
    local cfg, K, fc = Config.Rigs.Orbit, Config.Controls, Config.Freecam
    local any = false
    local tx, ty, tz = orbit.x, orbit.y, orbit.z
    if not orbit.hasPoint then
        local ax, ay, az = targetPoint(R.target, cfg.HeightOffset)
        if ax then tx, ty, tz = ax, ay, az; orbit.x, orbit.y, orbit.z = ax, ay, az end
    end

    local looking = (not ctx.cursor) or (pressed(K.LookHold) and not ctx.overUi)
    local mf, mr, mu = 0.0, 0.0, 0.0
    if not ctx.typing then
        if looking then
            local mx, my = GetDisabledControlNormal(0, K.LookX), GetDisabledControlNormal(0, K.LookY)
            if mx ~= 0.0 or my ~= 0.0 then any = true end
            orbit.tyaw = orbit.tyaw - mx * fc.LookSensitivity
            orbit.tpitch = M.Clamp(orbit.tpitch - my * fc.LookSensitivity, -fc.PitchLimit, fc.PitchLimit)
        end
        mf = (pressed(K.Forward) and 1.0 or 0.0) - (pressed(K.Back) and 1.0 or 0.0)
        mr = (pressed(K.Right) and 1.0 or 0.0) - (pressed(K.Left) and 1.0 or 0.0)
        mu = (pressed(K.Up) and 1.0 or 0.0) - (pressed(K.Down) and 1.0 or 0.0)
        -- wheel = radius (the camera slides toward / away from the pivot)
        if not ctx.overUi and not Cine.Placer.active then
            if justPressed(K.ScrollUp) then orbit.dist = M.Clamp(orbit.dist / fc.SpeedStep, cfg.MinDistance, cfg.MaxDistance); any = true end
            if justPressed(K.ScrollDown) then orbit.dist = M.Clamp(orbit.dist * fc.SpeedStep, cfg.MinDistance, cfg.MaxDistance); any = true end
        end
        local rollDir = (pressed(K.RollRight) and 1.0 or 0.0) - (pressed(K.RollLeft) and 1.0 or 0.0)
        if rollDir ~= 0.0 then orbit.roll = orbit.roll + rollDir * fc.RollRate * dt; any = true end
    end
    if orbit.spin ~= 0.0 then orbit.tyaw = orbit.tyaw + orbit.spin * dt end

    -- W A S D (flat, relative to where the camera faces) and Q E move the pivot, i.e. the whole
    -- orbit, with the same glide as the free camera. Radius and angle stay as they are.
    local yr = math.rad(orbit.yaw)
    local ix = -math.sin(yr) * mf + math.cos(yr) * mr
    local iy = math.cos(yr) * mf + math.sin(yr) * mr
    local iz = mu
    local len = math.sqrt(ix * ix + iy * iy + iz * iz)
    local has = len > 0.001
    if has then any = true; ix, iy, iz = ix / len, iy / len, iz / len end
    local mult = pressed(K.Fast) and fc.FastMult or (pressed(K.Slow) and fc.SlowMult or 1.0)
    local sp = Cine.Freecam.Speed() * mult
    local a = Cine.Freecam.MoveBlend(dt, has)
    orbit.vx = orbit.vx + (ix * sp - orbit.vx) * a
    orbit.vy = orbit.vy + (iy * sp - orbit.vy) * a
    orbit.vz = orbit.vz + (iz * sp - orbit.vz) * a
    orbit.ox, orbit.oy = orbit.ox + orbit.vx * dt, orbit.oy + orbit.vy * dt
    orbit.lift = M.Clamp(orbit.lift + orbit.vz * dt, cfg.MinLift, cfg.MaxLift)

    local sm = Cine.Freecam.Smoothing()
    if sm > 0.0 then
        local a = M.Smooth(sm, dt)
        orbit.yaw = orbit.yaw + (orbit.tyaw - orbit.yaw) * a
        orbit.pitch = orbit.pitch + (orbit.tpitch - orbit.pitch) * a
    else
        orbit.yaw, orbit.pitch = orbit.tyaw, orbit.tpitch
    end

    local fx, fy, fz = M.Basis(orbit.pitch, orbit.yaw)
    tx, ty, tz = tx + orbit.ox, ty + orbit.oy, tz + orbit.lift
    orbit.cx, orbit.cy, orbit.cz = tx, ty, tz
    out = out or Cine.Camera.NewState(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, orbit.fov)
    out.pos[1], out.pos[2], out.pos[3] = tx - fx * orbit.dist, ty - fy * orbit.dist, tz - fz * orbit.dist
    out.rot[1], out.rot[2], out.rot[3] = orbit.pitch, orbit.roll, orbit.yaw
    out.fov = orbit.fov
    out.dof = dof
    return out, any
end

local function tickFollow(dt, ctx, dof)
    local cfg, K, fc = Config.Rigs.Follow, Config.Controls, Config.Freecam
    local tx, ty, tz, e = targetPoint(R.target, 0.5)
    if not tx then return nil, false end
    local off = cfg.Offset
    local sc = follow.scale
    local want = GetOffsetFromEntityInWorldCoords(e, off.x * sc, off.y * sc, off.z * sc)
    local pa = M.Smooth(cfg.PosLag, dt)
    follow.x = follow.x + (want.x - follow.x) * pa
    follow.y = follow.y + (want.y - follow.y) * pa
    follow.z = follow.z + (want.z - follow.z) * pa
    local dp, dy = M.DirToRot(tx - follow.x, ty - follow.y, tz - follow.z)
    local ra = M.Smooth(cfg.RotLag, dt)
    follow.yaw = follow.yaw + M.AngleDelta(follow.yaw, dy) * ra
    follow.pitch = follow.pitch + (dp - follow.pitch) * ra

    local any = false
    if not ctx.typing and not ctx.overUi and not Cine.Placer.active then
        if justPressed(K.ScrollUp) then follow.scale = M.Clamp(follow.scale / fc.SpeedStep, 0.2, 10.0); any = true end
        if justPressed(K.ScrollDown) then follow.scale = M.Clamp(follow.scale * fc.SpeedStep, 0.2, 10.0); any = true end
    end
    if not ctx.typing then
        local rollDir = (pressed(K.RollRight) and 1.0 or 0.0) - (pressed(K.RollLeft) and 1.0 or 0.0)
        if rollDir ~= 0.0 then follow.roll = follow.roll + rollDir * fc.RollRate * dt; any = true end
    end

    out = out or Cine.Camera.NewState(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, follow.fov)
    out.pos[1], out.pos[2], out.pos[3] = follow.x, follow.y, follow.z
    out.rot[1], out.rot[2], out.rot[3] = follow.pitch, follow.roll, follow.yaw
    out.fov = follow.fov
    out.dof = dof
    return out, any
end

--- Returns the camera state for this frame and whether the user gave input.
function R.Tick(dt, ctx, dof)
    if R.mode == 'orbit' then
        return tickOrbit(dt, ctx, dof)
    elseif R.mode == 'follow' then
        local s, any = tickFollow(dt, ctx, dof)
        if s then return s, any end
        -- Target vanished: fall back to the free rig where the camera is.
        R.mode, R.target = 'free', nil
        Cine.Freecam.SetFromState(Cine.Camera.state)
        Cine.Nui.Send('state', Cine.Session.StatePayload())
    end
    return Cine.Freecam.Tick(dt, ctx, dof)
end
