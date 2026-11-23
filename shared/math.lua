-- Pure math helpers shared by client (evaluation) and server (nothing heavy). No natives in here.
CineMath = {}
local M = CineMath

local floor, abs, sqrt, exp = math.floor, math.abs, math.sqrt, math.exp

function M.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function M.Lerp(a, b, t)
    return a + (b - a) * t
end

function M.Round(v, step)
    return floor(v / step + 0.5) * step
end

--- Exponential smoothing factor for a rate k (1/s) and frame time dt: 1 - exp(-k*dt).
function M.Smooth(k, dt)
    return 1.0 - exp(-k * dt)
end

--- Wrap an angle in degrees into [-180, 180).
function M.WrapAngle(a)
    a = (a + 180.0) % 360.0 - 180.0
    return a
end

--- Return a (equal modulo 360) closest to prev, so consecutive keys take the short arc.
function M.UnwrapTo(prev, a)
    return a + 360.0 * floor((prev - a) / 360.0 + 0.5)
end

--- Shortest signed delta between two angles (degrees).
function M.AngleDelta(from, to)
    return M.WrapAngle(to - from)
end

--- Heading / pitch (degrees) of a direction, GTA convention (forward = (-sin yaw, cos yaw)).
function M.DirToRot(dx, dy, dz)
    local hd = sqrt(dx * dx + dy * dy)
    local pitch = math.deg(math.atan(dz, hd))
    local yaw = math.deg(math.atan(-dx, dy))
    return pitch, yaw
end

--- Forward and right unit vectors (x, y, z each) from pitch / yaw degrees.
function M.Basis(pitch, yaw)
    local rp, ry = math.rad(pitch), math.rad(yaw)
    local cp = math.cos(rp)
    return -math.sin(ry) * cp, math.cos(ry) * cp, math.sin(rp), math.cos(ry), math.sin(ry), 0.0
end

--- Turn a GTA (rotation order 2) pitch / roll / yaw by offsets in the CAMERA's own frame:
--- dp about its right axis (tilt), dr about its view axis (roll), dy about its up axis (pan).
--- Degrees in and out. Unlike adding the numbers, this is right at any pitch: a pan offset on a
--- camera that looks straight down still slides the picture sideways instead of spinning it.
function M.ComposeRot(pitch, roll, yaw, dp, dr, dy)
    local a, b, g = math.rad(pitch), math.rad(roll), math.rad(yaw)
    local sa, ca, sb, cb, sg, cg = math.sin(a), math.cos(a), math.sin(b), math.cos(b), math.sin(g), math.cos(g)
    a, b, g = math.rad(dp), math.rad(dr), math.rad(dy)
    local sx, cx, sy, cy, sz, cz = math.sin(a), math.cos(a), math.sin(b), math.cos(b), math.sin(g), math.cos(g)
    -- base B = Rz(yaw) * Rx(pitch) * Ry(roll), offset O built the same way, result = B * O
    local b00, b01, b02 = cg * cb - sg * sa * sb, -sg * ca, cg * sb + sg * sa * cb
    local b10, b11, b12 = sg * cb + cg * sa * sb, cg * ca, sg * sb - cg * sa * cb
    local b20, b21, b22 = -ca * sb, sa, ca * cb
    local o00, o10, o20 = cz * cy - sz * sx * sy, sz * cy + cz * sx * sy, -cx * sy
    local o01, o11, o21 = -sz * cx, cz * cx, sx
    local o02, o12, o22 = cz * sy + sz * sx * cy, sz * sy - cz * sx * cy, cx * cy
    local c01 = b00 * o01 + b01 * o11 + b02 * o21
    local c11 = b10 * o01 + b11 * o11 + b12 * o21
    local c21 = b20 * o01 + b21 * o11 + b22 * o21
    local c20 = b20 * o00 + b21 * o10 + b22 * o20
    local c22 = b20 * o02 + b21 * o12 + b22 * o22
    return math.deg(math.asin(M.Clamp(c21, -1.0, 1.0))), math.deg(math.atan(-c20, c22)), math.deg(math.atan(-c01, c11))
end

-- Easing ---------------------------------------------------------------------------------------

local function cubicBezier(x1, y1, x2, y2, x)
    if x <= 0.0 then return 0.0 end
    if x >= 1.0 then return 1.0 end
    local cx = 3.0 * x1
    local bx = 3.0 * (x2 - x1) - cx
    local ax = 1.0 - cx - bx
    local cy = 3.0 * y1
    local by = 3.0 * (y2 - y1) - cy
    local ay = 1.0 - cy - by
    -- Newton, 4 iterations
    local t = x
    for _ = 1, 4 do
        local xt = ((ax * t + bx) * t + cx) * t - x
        local dx = (3.0 * ax * t + 2.0 * bx) * t + cx
        if abs(xt) < 1e-5 then break end
        if abs(dx) < 1e-6 then break end
        t = t - xt / dx
    end
    local ok = abs(((ax * t + bx) * t + cx) * t - x) < 1e-4 and t >= 0.0 and t <= 1.0
    if not ok then -- bisection fallback
        local lo, hi = 0.0, 1.0
        t = x
        for _ = 1, 24 do
            local xt = ((ax * t + bx) * t + cx) * t
            if xt < x then lo = t else hi = t end
            t = (lo + hi) * 0.5
        end
    end
    return ((ay * t + by) * t + cy) * t
end

--- ease: 'flow' (handled in timeline.lua, = linear here) | 'linear' | 'easeIn' | 'easeOut' | 'easeInOut' | 'bezier' ; bez = { x1, y1, x2, y2 }.
function M.Ease(ease, u, bez)
    if u <= 0.0 then return 0.0 end
    if u >= 1.0 then return 1.0 end
    if ease == 'easeIn' then
        return u * u * u
    elseif ease == 'easeOut' then
        local v = 1.0 - u
        return 1.0 - v * v * v
    elseif ease == 'easeInOut' then
        if u < 0.5 then return 4.0 * u * u * u end
        local v = -2.0 * u + 2.0
        return 1.0 - v * v * v / 2.0
    elseif ease == 'bezier' and bez then
        return cubicBezier(bez[1], bez[2], bez[3], bez[4], u)
    end
    return u
end

-- Centripetal Catmull-Rom (Barry-Goldman) over N channels ---------------------------------------

--- Knot interval between two keys. The "length" of the step counts turning and zooming too
--- (Config.Timeline.PathWeights, the same mix the path distance uses), not just metres: with the
--- position alone, a pan on the spot is a zero-length step, and next to a normal step that makes
--- the rotation overshoot by thousands of degrees (the camera spins round and round).
--- Channels: 1-3 position (or orbit pivot), 4-6 pitch / roll / yaw, 7 FOV, 11 orbit radius.
local function knotStep(a, b)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local d2 = dx * dx + dy * dy + dz * dz
    if a[7] ~= nil and b[7] ~= nil then
        local W = Config and Config.Timeline and Config.Timeline.PathWeights
        local wr, wf = W and W.Rot or 0.05, W and W.Fov or 0.05
        local dp, dr, dw, df = (b[4] - a[4]) * wr, (b[5] - a[5]) * wr, (b[6] - a[6]) * wr, (b[7] - a[7]) * wf
        d2 = d2 + dp * dp + dr * dr + dw * dw + df * df
        if a[11] ~= nil and b[11] ~= nil then d2 = d2 + (b[11] - a[11]) ^ 2 end
    end
    return math.max(sqrt(sqrt(d2)), 1e-3) -- alpha 0.5 on the length, never zero (duplicate end points)
end

--- p0..p3: arrays of numbers (camera or orbit channels, see knotStep for what the spacing uses).
--- Returns the interpolated array at local parameter u (0..1) of the segment p1 -> p2.
function M.CatmullRom(p0, p1, p2, p3, u, out)
    local t0 = 0.0
    local t1 = t0 + knotStep(p0, p1)
    local t2 = t1 + knotStep(p1, p2)
    local t3 = t2 + knotStep(p2, p3)
    local t = t1 + (t2 - t1) * u
    local n = #p1
    out = out or {}
    local d01, d12, d23, d02, d13 = t1 - t0, t2 - t1, t3 - t2, t2 - t0, t3 - t1
    for i = 1, n do
        local a1 = (t1 - t) / d01 * p0[i] + (t - t0) / d01 * p1[i]
        local a2 = (t2 - t) / d12 * p1[i] + (t - t1) / d12 * p2[i]
        local a3 = (t3 - t) / d23 * p2[i] + (t - t2) / d23 * p3[i]
        local b1 = (t2 - t) / d02 * a1 + (t - t0) / d02 * a2
        local b2 = (t3 - t) / d13 * a2 + (t - t1) / d13 * a3
        out[i] = (t2 - t) / d12 * b1 + (t - t1) / d12 * b2
    end
    return out
end

--- Interpolate time of day (minutes on a 1440 circle). dir: 'short' | 'forward'.
function M.LerpTod(a, b, u, dir)
    local d = b - a
    if dir == 'forward' then
        d = d % 1440.0
    else
        d = (d + 720.0) % 1440.0 - 720.0
    end
    return (a + d * u) % 1440.0
end

--- Binary search: index i such that keys[i].t <= t < keys[i+1].t (1..n-1), or 0 before first / n at/after last.
function M.FindSegment(keys, t)
    local n = #keys
    if n == 0 or t < keys[1].t then return 0 end
    if t >= keys[n].t then return n end
    local lo, hi = 1, n
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if keys[mid].t <= t then lo = mid else hi = mid end
    end
    return lo
end
