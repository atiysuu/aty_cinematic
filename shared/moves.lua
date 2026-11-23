-- Ready-made camera moves. Each one turns "where the camera is now" + "the point it frames" into a
-- list of keys for the timeline. Pure maths, no natives (runs offline in the tests).
--
-- Every move keeps the framing the user composed: a subject placed off-centre (rule of thirds)
-- stays that far off-centre for the whole move. Only a camera that points somewhere else entirely
-- (more than 35 degrees away) is re-aimed at the subject.
--
-- `amount` means something different per move and is always relative, so the same move works on a
-- face 2 m away and on a building 80 m away:
--   deg = degrees, pct = per cent of the distance to the subject, x = times that distance
CineMoves = {}
local MV = CineMoves
local M -- CineMath, resolved on first use: shared files load in glob order, not dependency order

local sqrt, sin, cos, tan, atan, rad, deg, pi = math.sqrt, math.sin, math.cos, math.tan, math.atan, math.rad, math.deg, math.pi
local max, min, ceil, abs = math.max, math.min, math.ceil, math.abs

-- frame ---------------------------------------------------------------------------------------------

--- Everything a move needs. ctx = { pos, rot, fov, subject = {x,y,z}, ground = z | nil }.
local function frame(ctx)
    local C, R = ctx.pos, ctx.rot
    local fx, fy, fz = M.Basis(R[1], R[3])
    local T = ctx.subject
    local vx, vy, vz = T[1] - C[1], T[2] - C[2], T[3] - C[3]
    local dist = sqrt(vx * vx + vy * vy + vz * vz)
    if dist < 0.5 then
        -- no usable subject: a point 8 m ahead
        dist = 8.0
        vx, vy, vz = fx * dist, fy * dist, fz * dist
        T = { C[1] + vx, C[2] + vy, C[3] + vz }
    end
    local F = { C = C, rot = { R[1], R[2], R[3] }, fov = ctx.fov, aim = { T[1], T[2], T[3] }, d = max(dist, 0.8) }
    -- direction to the subject, and how far off it the camera points (the framing to keep)
    F.pitch, F.yaw = M.DirToRot(vx, vy, vz)
    F.pitch = M.Clamp(F.pitch, -89.0, 89.0)
    F.offP, F.offY = R[1] - F.pitch, M.WrapAngle(R[3] - F.yaw)
    if (vx * fx + vy * fy + vz * fz) / dist < 0.819 then
        F.offP, F.offY = 0.0, 0.0
        F.rot = { F.pitch, R[2], F.yaw }
    end
    F.centred = abs(F.offP) < 0.3 and abs(F.offY) < 0.3
    F.vx, F.vy, F.vz = vx / dist, vy / dist, vz / dist   -- unit vector to the subject
    local yr = rad(F.yaw)
    F.fx, F.fy = -sin(yr), cos(yr)                       -- flat forward / right, towards the subject
    F.rx, F.ry = cos(yr), sin(yr)
    yr = rad(F.rot[3])
    F.cx, F.cy = cos(yr), sin(yr)                        -- the camera's own flat right
    F.floor = min(ctx.ground or (F.aim[3] - 1.6), C[3] - 0.3)
    return F
end

--- Rotation at p that frames the subject the way the camera frames it now (keeps the roll).
local function look(F, p)
    local dx, dy, dz = F.aim[1] - p[1], F.aim[2] - p[2], F.aim[3] - p[3]
    local pitch, yaw
    if dx * dx + dy * dy < 1e-6 then
        pitch, yaw = (dz >= 0.0 and 89.0 or -89.0), F.yaw
    else
        pitch, yaw = M.DirToRot(dx, dy, dz)
    end
    return { M.Clamp(pitch + F.offP, -89.0, 89.0), F.rot[2], yaw + F.offY }
end

local function key(t, pos, rot, fov, orbit)
    return { t = t, pos = pos, rot = rot, fov = fov, ease = 'flow', orbit = orbit }
end

--- A key on the sphere around the subject; pitch / yaw = the direction from the camera to it.
--- A centred subject gives a true orbit key (the timeline circles between two of these); an
--- off-centre one gives a plain key that keeps the offset, so those are laid closer together.
local function orbitKey(F, t, pitch, yaw, radius, fov)
    pitch = M.Clamp(pitch, -89.0, 89.0)
    local vx, vy, vz = M.Basis(pitch, yaw)
    local pos = { F.aim[1] - vx * radius, F.aim[2] - vy * radius, F.aim[3] - vz * radius }
    if F.centred then
        return key(t, pos, { pitch, F.rot[2], yaw }, fov, { c = { F.aim[1], F.aim[2], F.aim[3] }, d = radius })
    end
    return key(t, pos, { M.Clamp(pitch + F.offP, -89.0, 89.0), F.rot[2], yaw + F.offY }, fov)
end

--- n segments along a path: at(u) -> pos [, fov]. Every key frames the subject.
local function path(F, dur, n, at)
    local keys = {}
    for i = 0, n do
        local u = i / n
        local p, fov = at(u)
        keys[#keys + 1] = key(dur * u, p, look(F, p), fov or F.fov)
    end
    return keys
end

local function smooth(u) return u * u * (3.0 - 2.0 * u) end
local function fovClamp(v) return M.Clamp(v, Config.Freecam.FovMin, Config.Freecam.FovMax) end

--- Number of steps for a turn of `a` degrees: 45 degrees each for true orbit keys, 22.5 for plain ones.
local function arcSteps(F, a) return max(2, ceil(abs(a) / (F.centred and 45.0 or 22.5))) end

-- moves ---------------------------------------------------------------------------------------------
-- { id, group, dur, amt = { def, min, max, step, unit }, dir = 'side' | 'inout' | 'updown' | nil,
--   shake = suggested shake | nil, build(F, dur, amount, dir) -> keys }
-- dir is +1 (right / in / up) or -1 (left / out / down).

local DEFS = {
    -- towards / away ---------------------------------------------------------------------------
    {
        id = 'push_in', group = 'depth', dur = 5.0, amt = { 50, 10, 90, 5, 'pct' },
        shake = { preset = 'handheld', amount = 0.2, speed = 0.0, whip = 0.1 },
        build = function(F, dur, a)
            local g = min(F.d * a / 100.0, F.d - 0.6)
            return {
                key(0.0, { F.C[1], F.C[2], F.C[3] }, F.rot, F.fov),
                key(dur, { F.C[1] + F.vx * g, F.C[2] + F.vy * g, F.C[3] + F.vz * g }, F.rot, F.fov),
            }
        end,
    },
    {
        id = 'pull_back', group = 'depth', dur = 6.0, amt = { 1.5, 0.5, 5.0, 0.1, 'x' },
        shake = { preset = 'drone', amount = 0.3, speed = 0.1, whip = 0.2 },
        build = function(F, dur, a)
            local back, up = F.d * a, F.d * a * 0.35
            return path(F, dur, 3, function(u)
                local e = smooth(u)
                return { F.C[1] - F.vx * back * e, F.C[2] - F.vy * back * e, F.C[3] - F.vz * back * e + up * e }
            end)
        end,
    },
    {
        id = 'dolly_zoom', group = 'depth', dur = 4.0, amt = { 45, 10, 80, 5, 'pct' }, dir = 'inout',
        build = function(F, dur, a, s)
            -- the subject keeps its size: tan(fov / 2) * distance stays constant
            local k = tan(rad(F.fov) * 0.5) * F.d
            local d1 = s > 0 and max(F.d * (1.0 - a / 100.0), 0.6) or F.d * (1.0 + a / 100.0)
            local keys = {}
            for i = 0, 4 do
                local u = i / 4
                local d = F.d + (d1 - F.d) * u
                local fov = fovClamp(deg(2.0 * atan(k / d)))
                keys[#keys + 1] = key(dur * u, { F.aim[1] - F.vx * d, F.aim[2] - F.vy * d, F.aim[3] - F.vz * d }, F.rot, fov)
            end
            return keys
        end,
    },
    {
        id = 'zoom', group = 'depth', dur = 4.0, amt = { 40, 5, 80, 5, 'pct' }, dir = 'inout',
        build = function(F, dur, a, s)
            local fov = fovClamp(s > 0 and F.fov * (1.0 - a / 100.0) or F.fov * (1.0 + a / 100.0))
            return {
                key(0.0, { F.C[1], F.C[2], F.C[3] }, F.rot, F.fov),
                key(dur, { F.C[1], F.C[2], F.C[3] }, F.rot, fov),
            }
        end,
    },

    -- around the subject -------------------------------------------------------------------------
    {
        id = 'orbit', group = 'around', dur = 8.0, amt = { 90, 15, 360, 15, 'deg' }, dir = 'side',
        build = function(F, dur, a, s)
            local n, keys = arcSteps(F, a), {}
            for i = 0, n do
                keys[#keys + 1] = orbitKey(F, dur * i / n, F.pitch, F.yaw + s * a * i / n, F.d, F.fov)
            end
            return keys
        end,
    },
    {
        id = 'arc_push', group = 'around', dur = 6.0, amt = { 60, 15, 180, 15, 'deg' }, dir = 'side',
        shake = { preset = 'handheld', amount = 0.2, speed = 0.0, whip = 0.15 },
        build = function(F, dur, a, s)
            local n, keys = arcSteps(F, a), {}
            for i = 0, n do
                local u = i / n
                keys[#keys + 1] = orbitKey(F, dur * u, F.pitch, F.yaw + s * a * u, max(F.d * (1.0 - 0.4 * u), 0.8), F.fov)
            end
            return keys
        end,
    },
    {
        id = 'spiral', group = 'around', dur = 10.0, amt = { 180, 45, 540, 15, 'deg' }, dir = 'side',
        shake = { preset = 'drone', amount = 0.3, speed = 0.1, whip = 0.2 },
        build = function(F, dur, a, s)
            local n, keys = arcSteps(F, a), {}
            for i = 0, n do
                local u = i / n
                keys[#keys + 1] = orbitKey(F, dur * u, max(F.pitch - 25.0 * u, -80.0), F.yaw + s * a * u, F.d * (1.0 + 0.6 * u), F.fov)
            end
            return keys
        end,
    },
    {
        id = 'truck', group = 'around', dur = 6.0, amt = { 0.6, 0.1, 3.0, 0.1, 'x' }, dir = 'side',
        build = function(F, dur, a, s)
            local l = F.d * a * s
            return path(F, dur, 3, function(u) return { F.C[1] + F.rx * l * u, F.C[2] + F.ry * l * u, F.C[3] } end)
        end,
    },
    {
        id = 'slide', group = 'around', dur = 6.0, amt = { 0.6, 0.1, 3.0, 0.1, 'x' }, dir = 'side',
        build = function(F, dur, a, s)
            local l = F.d * a * s
            return {
                key(0.0, { F.C[1], F.C[2], F.C[3] }, F.rot, F.fov),
                key(dur, { F.C[1] + F.cx * l, F.C[2] + F.cy * l, F.C[3] }, F.rot, F.fov),
            }
        end,
    },
    {
        id = 'flyby', group = 'around', dur = 4.0, amt = { 1.0, 0.3, 3.0, 0.1, 'x' }, dir = 'side',
        shake = { preset = 'none', amount = 1.0, speed = 0.35, whip = 0.6 },
        build = function(F, dur, a, s)
            -- straight past the subject and on, sliding out sideways so it never flies through it
            local total = F.d * (1.0 + a)
            local side = max(1.0, F.d * 0.35) * s
            local pass = 1.0 / (1.0 + a)
            return path(F, dur, 8, function(u)
                local o = side * smooth(min(u / pass, 1.0))
                return { F.C[1] + F.vx * total * u + F.rx * o, F.C[2] + F.vy * total * u + F.ry * o, F.C[3] + F.vz * total * u }
            end)
        end,
    },

    -- height ---------------------------------------------------------------------------------------
    {
        id = 'crane', group = 'height', dur = 6.0, amt = { 0.6, 0.1, 3.0, 0.1, 'x' }, dir = 'updown',
        build = function(F, dur, a, s)
            local h = F.d * a * s
            return path(F, dur, 3, function(u)
                return { F.C[1], F.C[2], max(F.C[3] + h * u, F.floor + 0.3) }
            end)
        end,
    },
    {
        id = 'reveal_rise', group = 'height', dur = 5.0, amt = { 0.5, 0.1, 3.0, 0.1, 'x' },
        build = function(F, dur, a)
            -- comes up from below with the camera locked off, ends on the pose it has now
            local z0 = max(F.C[3] - F.d * a, F.floor + 0.25)
            return {
                key(0.0, { F.C[1], F.C[2], z0 }, F.rot, F.fov),
                key(dur, { F.C[1], F.C[2], F.C[3] }, F.rot, F.fov),
            }
        end,
    },
    {
        id = 'top_drop', group = 'height', dur = 5.0, amt = { 2.0, 0.5, 6.0, 0.1, 'x' },
        shake = { preset = 'none', amount = 1.0, speed = 0.35, whip = 0.5 },
        build = function(F, dur, a)
            -- starts high above the subject looking down, swings out and lands on the current pose
            local h = F.d * a
            local sx, sy, sz = F.aim[1] - F.fx * h * 0.12, F.aim[2] - F.fy * h * 0.12, F.aim[3] + h
            return path(F, dur, 6, function(u)
                local e = u * u
                return { sx + (F.C[1] - sx) * e, sy + (F.C[2] - sy) * e, sz + (F.C[3] - sz) * smooth(u) }
            end)
        end,
    },
    {
        id = 'establish', group = 'height', dur = 8.0, amt = { 3.0, 1.0, 10.0, 0.5, 'x' },
        shake = { preset = 'drone', amount = 0.4, speed = 0.15, whip = 0.25 },
        build = function(F, dur, a)
            -- far back and high, flies in and settles on the current pose
            local sx, sy, sz = F.C[1] - F.fx * F.d * a, F.C[2] - F.fy * F.d * a, F.C[3] + F.d * a * 0.5
            return path(F, dur, 4, function(u)
                local e = smooth(u)
                return { sx + (F.C[1] - sx) * e, sy + (F.C[2] - sy) * e, sz + (F.C[3] - sz) * e }
            end)
        end,
    },
    {
        id = 'top_spin', group = 'height', dur = 8.0, amt = { 90, 15, 360, 15, 'deg' }, dir = 'side',
        build = function(F, dur, a, s)
            -- bird's eye straight above the subject, turning while it sinks a little
            local n, keys = arcSteps(F, a), {}
            for i = 0, n do
                local u = i / n
                keys[#keys + 1] = orbitKey(F, dur * u, -89.0, F.yaw + s * a * u, F.d * (1.0 - 0.2 * u), F.fov)
            end
            return keys
        end,
    },

    -- character ------------------------------------------------------------------------------------
    {
        id = 'hero_low', group = 'character', dur = 5.0, amt = { 20, 0, 60, 5, 'pct' },
        shake = { preset = 'handheld', amount = 0.2, speed = 0.0, whip = 0.1 },
        build = function(F, dur, a)
            -- knee height in front of the subject, looking up, creeping in and rising
            local hd = max(1.6, sqrt(max(F.d * F.d - (F.C[3] - F.aim[3]) ^ 2, 0.0)) * 0.6)
            local z0 = F.floor + 0.35
            return path(F, dur, 2, function(u)
                local d = hd * (1.0 - a / 100.0 * u)
                return { F.aim[1] - F.fx * d, F.aim[2] - F.fy * d, z0 + 0.25 * u }
            end)
        end,
    },
    {
        id = 'tilt', group = 'character', dur = 5.0, amt = { 30, 5, 80, 5, 'deg' }, dir = 'updown',
        build = function(F, dur, a, s)
            -- locked position; starts below (or above) and tilts onto the current frame
            local p0 = M.Clamp(F.rot[1] - a * s, -89.0, 89.0)
            return {
                key(0.0, { F.C[1], F.C[2], F.C[3] }, { p0, F.rot[2], F.rot[3] }, F.fov),
                key(dur, { F.C[1], F.C[2], F.C[3] }, F.rot, F.fov),
            }
        end,
    },
    {
        id = 'whip_in', group = 'character', dur = 3.0, amt = { 90, 20, 180, 5, 'deg' }, dir = 'side',
        shake = { preset = 'handheld', amount = 0.4, speed = 0.1, whip = 0.8 },
        build = function(F, dur, a, s)
            -- already whipping when the shot starts, lands on the current frame, then creeps in
            local tw = min(0.45, dur * 0.25)
            local g = min(F.d * 0.06, F.d - 0.6)
            local k0 = key(0.0, { F.C[1], F.C[2], F.C[3] }, { F.rot[1], F.rot[2], F.rot[3] + a * s }, F.fov)
            k0.ease = 'easeIn'
            local k1 = key(tw, { F.C[1], F.C[2], F.C[3] }, F.rot, F.fov)
            k1.ease = 'easeOut'
            return { k0, k1, key(dur, { F.C[1] + F.vx * g, F.C[2] + F.vy * g, F.C[3] + F.vz * g }, F.rot, F.fov) }
        end,
    },
    {
        id = 'handheld_hold', group = 'character', dur = 6.0, amt = { 3, 0, 15, 1, 'pct' },
        shake = { preset = 'handheld', amount = 0.4, speed = 0.0, whip = 0.1 },
        build = function(F, dur, a)
            local g = min(F.d * a / 100.0, F.d - 0.6)
            return {
                key(0.0, { F.C[1], F.C[2], F.C[3] }, F.rot, F.fov),
                key(dur, { F.C[1] + F.vx * g, F.C[2] + F.vy * g, F.C[3] + F.vz * g }, F.rot, F.fov),
            }
        end,
    },
}

local byId = {}
for _, d in ipairs(DEFS) do byId[d.id] = d end

MV.Groups = { 'depth', 'around', 'height', 'character' }

function MV.Get(id) return byId[id] end

--- What the panel needs to draw the list (no functions).
function MV.Meta()
    local out = {}
    for _, d in ipairs(DEFS) do
        out[#out + 1] = {
            id = d.id, group = d.group, dur = d.dur, dir = d.dir or false, shake = d.shake ~= nil,
            amt = { def = d.amt[1], min = d.amt[2], max = d.amt[3], step = d.amt[4], unit = d.amt[5] },
        }
    end
    return out
end

--- Build the keys of a move. opt = { dur, amount, dir, soft }. Returns keys (t from 0) and the
--- suggested shake, or nil when the id is unknown.
function MV.Build(id, ctx, opt)
    M = M or CineMath
    local d = byId[id]
    if not d or type(ctx) ~= 'table' or not ctx.pos or not ctx.rot or not ctx.subject then return nil end
    opt = opt or {}
    local dur = M.Clamp(tonumber(opt.dur) or d.dur, 0.5, 120.0)
    local amount = M.Clamp(tonumber(opt.amount) or d.amt[1], d.amt[2], d.amt[3])
    local dir = (tonumber(opt.dir) or 1) < 0 and -1 or 1
    local keys = d.build(frame(ctx), dur, amount, dir)
    if opt.soft == false and #keys >= 2 then
        -- no ease at the ends: the shot starts and ends already moving (loops, cutting on motion)
        keys[1].ease, keys[#keys].ease = 'easeIn', 'easeIn'
    end
    return keys, d.shake
end
