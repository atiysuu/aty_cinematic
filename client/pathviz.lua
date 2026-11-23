-- Camera path preview: the current shot's camera path drawn in the world while editing.
--   line    = where the camera travels (orbit keys show their arc), coloured start -> end
--   chevron = direction of travel
--   sphere  = a key (first key in the start colour, last in the end colour), with a short line
--             showing where the camera looks there
--   white   = where the camera is at the playhead, when the timeline is not holding the camera
-- Samples are rebuilt only when the shot changes; per frame it is just DrawLine / DrawMarker.
Cine.PathViz = { enabled = Config.PathViz.Enabled }
local PV = Cine.PathViz
local M = CineMath

local cache = { shot = nil, rev = -1, n = -1, pts = {}, keys = {} }
local scratch = nil -- caller-owned state for TL.Evaluate (never the shared live camera state)

local function lerpColor(u)
    local a, b = Config.PathViz.StartColor, Config.PathViz.EndColor
    return math.floor(a[1] + (b[1] - a[1]) * u), math.floor(a[2] + (b[2] - a[2]) * u), math.floor(a[3] + (b[3] - a[3]) * u)
end

local function rebuild(shot)
    local cfg, TL = Config.PathViz, Cine.Timeline
    scratch = scratch or Cine.Camera.NewState(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 50.0)
    local pts, keys = {}, {}
    local dur = TL.Duration(shot)
    if #shot.keys >= 2 and dur > 0.0 then
        local steps = M.Clamp(math.ceil(dur * cfg.SamplesPerSec), 16, cfg.MaxSamples)
        for i = 0, steps do
            local c = TL.Evaluate(shot, dur * i / steps, scratch, true)
            if c then pts[#pts + 1] = { c.pos[1], c.pos[2], c.pos[3] } end
        end
    end
    local n = #shot.keys
    for i, k in ipairs(shot.keys) do
        local fx, fy, fz = M.Basis(k.rot[1], k.rot[3])
        local L = cfg.KeyDirLength
        keys[#keys + 1] = {
            k.pos[1], k.pos[2], k.pos[3],
            k.pos[1] + fx * L, k.pos[2] + fy * L, k.pos[3] + fz * L,
            n > 1 and (i - 1) / (n - 1) or 0.0,
        }
    end
    cache.shot, cache.rev, cache.n, cache.pts, cache.keys = shot, shot.rev, n, pts, keys
end

function PV.Tick(shot, visible)
    if not PV.enabled or not visible or not shot or #shot.keys == 0 then return end
    if cache.shot ~= shot or cache.rev ~= shot.rev or cache.n ~= #shot.keys then rebuild(shot) end
    local cfg = Config.PathViz
    local alpha = cfg.Alpha
    local pts = cache.pts
    local np = #pts

    -- path, coloured from start to end, with chevrons pointing the way
    for i = 1, np - 1 do
        local a, b = pts[i], pts[i + 1]
        local r, g, bl = lerpColor((i - 1) / math.max(np - 1, 1))
        DrawLine(a[1] + 0.0, a[2] + 0.0, a[3] + 0.0, b[1] + 0.0, b[2] + 0.0, b[3] + 0.0, r, g, bl, alpha)
        if i % cfg.ArrowEvery == 0 then
            local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
            local len = math.sqrt(dx * dx + dy * dy + dz * dz)
            if len > 0.001 then
                dx, dy, dz = dx / len, dy / len, dz / len
                -- a side vector across the direction (horizontal; falls back for vertical moves)
                local sx, sy, sz = -dy, dx, 0.0
                local sl = math.sqrt(sx * sx + sy * sy)
                if sl < 0.2 then sx, sy, sz, sl = 1.0, 0.0, 0.0, 1.0 end
                sx, sy = sx / sl * 0.25, sy / sl * 0.25
                local bx, by, bz = b[1] - dx * 0.45, b[2] - dy * 0.45, b[3] - dz * 0.45
                DrawLine(b[1] + 0.0, b[2] + 0.0, b[3] + 0.0, bx + sx, by + sy, bz + sz, r, g, bl, alpha)
                DrawLine(b[1] + 0.0, b[2] + 0.0, b[3] + 0.0, bx - sx, by - sy, bz - sz, r, g, bl, alpha)
            end
        end
    end

    -- keys and their look direction
    for _, k in ipairs(cache.keys) do
        local r, g, bl = lerpColor(k[7])
        DrawMarker(28, k[1] + 0.0, k[2] + 0.0, k[3] + 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            0.18, 0.18, 0.18, r, g, bl, 230, false, false, 2, false, nil, nil, false)
        DrawLine(k[1] + 0.0, k[2] + 0.0, k[3] + 0.0, k[4] + 0.0, k[5] + 0.0, k[6] + 0.0, 255, 255, 255, 200)
    end

    -- where the playhead is on the path (only when the camera is free, else it IS the camera)
    local TL = Cine.Timeline
    if not TL.Active() and np > 1 then
        local dur = TL.Duration(shot)
        if TL.t > 0.0 and TL.t < dur then
            local c = TL.Evaluate(shot, TL.t, scratch, true)
            if c then
                DrawMarker(28, c.pos[1] + 0.0, c.pos[2] + 0.0, c.pos[3] + 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    0.12, 0.12, 0.12, 255, 255, 255, 240, false, false, 2, false, nil, nil, false)
            end
        end
    end
end
