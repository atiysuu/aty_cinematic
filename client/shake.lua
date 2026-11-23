-- Procedural camera shake, applied on top of the camera pose at render time only.
-- The pose that keys capture (Cine.Camera.state) never contains shake.
--
-- Rotation offsets are in the CAMERA's own frame (tilt / roll / pan about its right / view / up
-- axis), so a shot that looks straight down shakes the same way as a level one.
-- Cine.Camera.Apply composes them onto the pose.
--
--   preset layers : fractal noise with most of its energy in slow drift and a tail of fast jitter;
--                   the noise of every axis and octave is shifted so they never line up (no
--                   repeating "pulse"); footsteps with an uneven cadence; the whole thing calms when
--                   the camera stands still and grows when it travels or pans
--   speed tremor  : loose low-frequency buffeting plus a fine buzz, both in gusts, growing with
--                   camera speed; a short rattle when the camera speeds up or brakes hard
--                   ("Tremor at speed" slider)
--   motion lean   : the camera has weight. It banks into turns and sideways moves, nods when it
--                   speeds up, brakes, drops or climbs, and on pans and tilts it lags at the start,
--                   runs a little past the end and settles ("Lean" slider)
--
-- Noise runs on timeline time while the timeline drives the camera, so every playback of a shot
-- shakes exactly the same way (repeatable takes). In free flight it runs on real time.
Cine.Shake = {}
local SH = Cine.Shake
local M = CineMath

local abs, sqrt, floor, sin, cos, exp = math.abs, math.sqrt, math.floor, math.sin, math.cos, math.exp
local PI = math.pi

-- motion state ------------------------------------------------------------------------------------
local freeT = 0.0
local prev = nil                                     -- { x, y, z, pitch, yaw }
local vx, vy, vz = 0.0, 0.0, 0.0                     -- smoothed velocity (m/s)
local ax, ay, az = 0.0, 0.0, 0.0                     -- smoothed acceleration (m/s^2)
local speed, yawRate, pitchRate = 0.0, 0.0, 0.0
local jolt = 0.0                                     -- decaying rattle amplitude (deg)
local roll = { x = 0.0, v = 0.0 }                    -- lean springs
local nod = { x = 0.0, v = 0.0 }
local panF = { x = 0.0, v = 0.0 }                    -- pan / tilt followers (weight)
local tiltF = { x = 0.0, v = 0.0 }
local fx = { pos = { 0.0, 0.0, 0.0 }, rot = { 0.0, 0.0, 0.0 } }
local rp, rr, ry, ox, oy, oz = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0

-- One seed per axis. The fraction is where that axis sits between two noise lattice points, spread
-- out so no two axes pass through zero together.
local SEED = { 11.13, 27.47, 43.81, 61.29, 79.63, 97.95 }   -- presets: tilt, roll, pan, right, forward, up
local WIND = { 113.21, 131.55, 149.89, 167.37, 181.71 }     -- speed tremor: tilt, roll, pan, right, up
local NORM = 1.3                                            -- fbm output: rms about 0.4, peaks about 1

-- noise ---------------------------------------------------------------------------------------------

--- Pseudo-random slope in [-1, 1] for an integer lattice point (deterministic).
local function grad(i, s)
    local n = sin(i * 127.1 + s * 311.7) * 43758.5453
    return (n - floor(n)) * 2.0 - 1.0
end

--- 1D gradient (Perlin) noise, smooth.
local function gnoise(x, s)
    local i = floor(x)
    local f = x - i
    local g0, g1 = grad(i, s), grad(i + 1, s)
    local u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0)
    return (g0 * f + (g1 * (f - 1.0) - g0 * f) * u) * 2.0
end

--- Fractal noise, about [-1, 1]. Each octave is about twice as fast and `gain` times as strong:
--- 0.7 = drift-heavy and organic (hands), 0.5 = smooth. Every octave is shifted by the seed.
local function fbm(t, freq, s, oct, gain)
    local v, a, f, norm = 0.0, 1.0, freq, 0.0
    for o = 1, oct do
        v = v + gnoise(t * f + s + o * 0.618, s + o * 17.3) * a
        norm = norm + a * a
        a, f = a * gain, f * 1.97
    end
    return v / sqrt(norm) * NORM
end

local function smoothstep(e0, e1, x)
    local t = M.Clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
end

--- Soft limit: follows x while it is small, approaches +-lim without a flat top.
local function soft(x, lim)
    if lim <= 0.0 then return 0.0 end
    local q = x / lim
    return x / sqrt(1.0 + q * q)
end

--- Damped spring towards `target` (sub-stepped: the same motion at 30 and 144 fps).
local function spring(sp, target, omega, zeta, dt)
    local n = floor(dt * 120.0) + 1
    local h = dt / n
    for _ = 1, n do
        sp.v = sp.v + (omega * omega * (target - sp.x) - 2.0 * zeta * omega * sp.v) * h
        sp.x = sp.x + sp.v * h
    end
    return sp.x
end

--- A weight on a spring that follows an angle turning at `rate` (deg/s). x = how far it is ahead
--- (+) or behind (-): behind while the turn speeds up, ahead when it stops, zero on a steady turn.
local function follow(sp, rate, omega, zeta, dt)
    local n = floor(dt * 120.0) + 1
    local h = dt / n
    for _ = 1, n do
        sp.v = sp.v + (2.0 * zeta * omega * (rate - sp.v) - omega * omega * sp.x) * h
        sp.x = sp.x + (sp.v - rate) * h
    end
    return sp.x
end

-- parameters ------------------------------------------------------------------------------------------

-- pa / aa = preset + amount, pb / ab = a second preset cross-fading in (between two keys with
-- different presets), speed / whip = 0..1 sliders. TL.ShakeAt builds these per key.
local fromShot = { pa = 'none', aa = 0.0, pb = nil, ab = 0.0, speed = 0.0, whip = 0.0 }

--- Parameters from a single shake setting (the shot default in free flight).
function SH.Params(s)
    local o = fromShot
    if not s then o.pa, o.aa, o.pb, o.ab, o.speed, o.whip = 'none', 0.0, nil, 0.0, 0.0, 0.0; return o end
    o.pa, o.aa, o.pb, o.ab, o.speed, o.whip = s.preset, s.amount, nil, 0.0, s.speed, s.whip
    return o
end

--- Do these parameters do anything at all?
function SH.Active(s)
    return s ~= nil and ((s.pa ~= 'none' and s.aa > 0.0) or (s.pb ~= nil and s.pb ~= 'none' and s.ab > 0.0)
        or s.speed > 0.0 or s.whip > 0.0)
end

local function resetMotion()
    vx, vy, vz, ax, ay, az = 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
    speed, yawRate, pitchRate, jolt = 0.0, 0.0, 0.0, 0.0
    roll.x, roll.v, nod.x, nod.v = 0.0, 0.0, 0.0, 0.0
    panF.x, panF.v, tiltF.x, tiltF.v = 0.0, 0.0, 0.0, 0.0
end

function SH.Reset()
    freeT, prev = 0.0, nil
    resetMotion()
end

-- presets -----------------------------------------------------------------------------------------------

--- Add one preset's layers at amount a, at noise time t. move = 0 (camera still) .. 1 (travelling).
local function addPreset(name, a, t, move)
    local layers = name and name ~= 'none' and a > 0.0 and Config.Shake.Presets[name] or nil
    if not layers then return end
    local cfg = Config.Shake
    -- nobody is equally steady all the time: the whole shake swells and calms slowly,
    -- and a camera that travels shakes more than one that stands still
    a = a * (1.0 + cfg.Breath.Depth * fbm(t, cfg.Breath.Freq, 5.21, 2, 0.5)) * (1.0 + cfg.Move.Gain * move)
    for j, L in ipairs(layers) do
        local rot, pos = L.rot, L.pos
        if L.bob then
            -- footsteps. ph counts steps; the cadence wanders so the steps are never metronomic
            local ph = L.bob * t + 0.12 * fbm(t, 0.5, 3.37, 2, 0.5)
            local side = sin(PI * ph)                            -- one half-wave per step: which foot
            -- body height: an arc over each stance leg, lowest and sharpest at the heel strike
            local arc = (sqrt(side * side + 0.02) - 0.66) / 0.66
            local idle = cfg.Move.BobIdle
            local k = a * (idle + (1.0 - idle) * move) * (1.0 + 0.3 * fbm(ph, 0.7, 7.77, 2, 0.5))
            if rot then rp, rr, ry = rp + rot[1] * arc * k, rr + rot[2] * side * k, ry + rot[3] * side * k end
            if pos then ox, oy, oz = ox + pos[1] * side * k, oy + pos[2] * arc * k, oz + pos[3] * arc * k end
            if L.impact then
                -- heel strike: a short ring that dies out before the next step
                local fr = ph - floor(ph)
                local ring = exp(-6.0 * fr) * sin(6.0 * PI * fr) * L.impact * k
                rp, rr = rp - ring, rr + 0.4 * ring * (side >= 0.0 and 1.0 or -1.0)
            end
        else
            local f, oct, g, so = L.freq, L.oct or 4, L.gain or 0.6, j * 3.37
            if rot then
                rp = rp + rot[1] * fbm(t, f, SEED[1] + so, oct, g) * a
                rr = rr + rot[2] * fbm(t, f, SEED[2] + so, oct, g) * a
                ry = ry + rot[3] * fbm(t, f, SEED[3] + so, oct, g) * a
            end
            if pos then
                ox = ox + pos[1] * fbm(t, f, SEED[4] + so, oct, g) * a
                oy = oy + pos[2] * fbm(t, f, SEED[5] + so, oct, g) * a
                oz = oz + pos[3] * fbm(t, f, SEED[6] + so, oct, g) * a
            end
        end
    end
end

-- per frame -----------------------------------------------------------------------------------------------

--- Offsets for this frame, or nil when shake is off.
--- cam = base pose, s = parameters (SH.Params / TL.ShakeAt), tlTime = timeline time while the
--- timeline drives the camera.
function SH.Tick(cam, dt, s, tlTime)
    if not SH.Active(s) or dt <= 0.0 then
        SH.Reset()
        return nil
    end
    local cfg = Config.Shake
    local mo = cfg.Motion
    -- free time carries on from the timeline's, so the noise does not jump when a playback ends
    if tlTime then freeT = tlTime else freeT = freeT + dt end
    local t = freeT

    -- 1) how the camera moves (velocity, acceleration, turn rates) from the base pose.
    --    A jump no real move could make in one frame is a cut: forget the motion, no lean spike.
    local p, r = cam.pos, cam.rot
    if prev then
        local dx, dy, dz = p[1] - prev[1], p[2] - prev[2], p[3] - prev[3]
        local dist = sqrt(dx * dx + dy * dy + dz * dz)
        local dyaw = M.WrapAngle(r[3] - prev[5])
        if dist > mo.CutDistance or dist / dt > mo.CutSpeed or abs(dyaw) > mo.CutYaw then
            resetMotion()
        else
            local kv = M.Smooth(mo.VelSmoothing, dt)
            local nvx = vx + (dx / dt - vx) * kv
            local nvy = vy + (dy / dt - vy) * kv
            local nvz = vz + (dz / dt - vz) * kv
            local ka = M.Smooth(mo.AccSmoothing, dt)
            ax = ax + ((nvx - vx) / dt - ax) * ka
            ay = ay + ((nvy - vy) / dt - ay) * ka
            az = az + ((nvz - vz) / dt - az) * ka
            vx, vy, vz = nvx, nvy, nvz
            speed = sqrt(vx * vx + vy * vy + vz * vz)
            yawRate = yawRate + (dyaw / dt - yawRate) * kv
            pitchRate = pitchRate + ((r[1] - prev[4]) / dt - pitchRate) * kv
        end
    end
    prev = prev or {}
    prev[1], prev[2], prev[3], prev[4], prev[5] = p[1], p[2], p[3], r[1], r[3]

    -- camera axes (world): forward, right, up
    local fX, fY, fZ, rX, rY = M.Basis(r[1], r[3])
    local uX, uY, uZ = rY * fZ, -rX * fZ, rX * fY - rY * fX
    local pan = yawRate * (rX * fY - rY * fX)     -- turn rate about the camera's own up axis

    rp, rr, ry = 0.0, 0.0, 0.0    -- tilt, roll, pan offsets (deg, camera frame)
    ox, oy, oz = 0.0, 0.0, 0.0    -- right, forward, up offsets (m, camera frame)

    -- 2) preset layers (two presets while one cross-fades into the next)
    local mv = cfg.Move
    local move = smoothstep(mv.Start, mv.Full, speed + abs(pan) * mv.Turn)
    addPreset(s.pa, s.aa, t, move)
    addPreset(s.pb, s.ab, t, move)

    -- 3) tremor at speed: buffeting + buzz in gusts, and a rattle when the speed changes hard
    if s.speed > 0.0 then
        local c, j = mo.Speed, mo.Jolt
        local k = smoothstep(c.Start, c.Full, speed) * s.speed
        local accel = sqrt(ax * ax + ay * ay + az * az)
        jolt = math.max(M.Clamp(accel * j.Gain, 0.0, j.Max) * s.speed, jolt * exp(-j.Decay * dt))
        if k > 0.0 or jolt > 0.0 then
            k = k * math.max(1.0 + c.Gust * fbm(t, c.GustFreq, 71.43, 2, 0.5), 0.15)
            local lo, hi = c.Sway * k, c.Buzz * k + jolt
            local sf, bf = c.SwayFreq, c.BuzzFreq
            rp = rp + lo * fbm(t, sf, WIND[1], 3, 0.6) + hi * fbm(t, bf, WIND[1] + 9.3, 2, 0.5)
            rr = rr + lo * 0.6 * fbm(t, sf, WIND[2], 3, 0.6) + hi * 0.6 * fbm(t, bf, WIND[2] + 9.3, 2, 0.5)
            ry = ry + lo * fbm(t, sf, WIND[3], 3, 0.6) + hi * fbm(t, bf, WIND[3] + 9.3, 2, 0.5)
            ox = ox + c.Pos * k * fbm(t, sf * 0.8, WIND[4], 2, 0.5)
            oz = oz + c.Pos * k * fbm(t, sf * 0.8, WIND[5], 2, 0.5)
        end
    else
        jolt = 0.0
    end

    -- 4) lean: bank into turns and sideways moves, nod on speed changes and vertical moves,
    --    weight on pans and tilts
    if s.whip > 0.0 then
        local c, w = mo.Lean, s.whip
        local aF = ax * fX + ay * fY + az * fZ
        local aR = ax * rX + ay * rY
        local aU = ax * uX + ay * uY + az * uZ
        local rollT = soft(-mo.Sign * (c.Turn * pan - c.Side * aR), c.MaxRoll) * w
        local nodT = soft(c.Nod * aF - c.Lift * aU, c.MaxPitch) * w
        rr = rr + spring(roll, rollT, c.Omega, c.Damping, dt)
        rp = rp + spring(nod, nodT, c.Omega, c.Damping, dt)
        local fo = c.Follow
        ry = ry + soft(follow(panF, pan, fo.Omega, fo.Damping, dt) * fo.Gain, fo.Max) * w
        rp = rp + soft(follow(tiltF, pitchRate, fo.Omega, fo.Damping, dt) * fo.Gain, fo.Max) * w
    else
        roll.x, roll.v, nod.x, nod.v = 0.0, 0.0, 0.0, 0.0
        panF.x, panF.v, tiltF.x, tiltF.v = 0.0, 0.0, 0.0, 0.0
    end

    -- a long lens magnifies tilt and pan (roll looks the same at every FOV)
    local fk = 1.0
    if cam.fov and cfg.Fov.Comp > 0.0 then
        fk = M.Clamp((cam.fov / cfg.Fov.Ref) ^ cfg.Fov.Comp, 0.35, 1.3)
    end

    -- camera-frame position offset -> world; rotation stays in the camera frame
    fx.pos[1] = rX * ox + fX * oy + uX * oz
    fx.pos[2] = rY * ox + fY * oy + uY * oz
    fx.pos[3] = fZ * oy + uZ * oz
    fx.rot[1], fx.rot[2], fx.rot[3] = rp * fk, rr, ry * fk
    return fx
end
