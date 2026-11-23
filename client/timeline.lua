-- Keyframe evaluation (pure) + playback clock / scrub.
-- Camera time t advances in real time (Config.Timeline.ClockSource). Evaluate is O(log n) per frame.
Cine.Timeline = {
    playing = false, scrub = false, t = 0.0, shotId = nil, loop = false,
    preloading = false,
}
local TL = Cine.Timeline
local M = CineMath

local cache = setmetatable({}, { __mode = 'k' })   -- shot table -> { rev, ex, envKeys, duration }
local baseT, startClock = 0.0, 0.0
local outState = nil
local outEnv = {}
local ch = {}

local ENV_NUM = { 'tcStrength', 'timeScale', 'wind', 'rain' }
-- speed multiplier at a key per ease (see build); linear / bezier work per segment instead
local PASS = { flow = 1.0, easeOut = 0.35, easeIn = 1.6, easeInOut = 0.0 }
local ENV_STEP = { 'weather', 'timecycle', 'blackout', 'population', 'todDir' }

local PATH_SAMPLES = 32
local bufA, bufB = {}, {}

--- Distance between two channel arrays: metres + weighted degrees + weighted FOV.
local function metric(a, b, W)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local dp, dr, dyw = b[4] - a[4], b[5] - a[5], b[6] - a[6]
    local rot = math.sqrt(dp * dp + dr * dr + dyw * dyw) * W.Rot
    local fov = (b[7] - a[7]) * W.Fov
    return math.sqrt(dx * dx + dy * dy + dz * dz + rot * rot + fov * fov)
end

--- Distance along segment e -> spline parameter u (0..1), via the segment's distance table.
local function paramAt(e, sl, frac)
    local tbl, len = e.tbl, e.len
    if not tbl or len <= 1e-6 then return frac end
    if sl <= 0.0 then return 0.0 end
    if sl >= len then return 1.0 end
    local lo, hi = 1, #tbl
    while hi - lo > 1 do
        local mid = (lo + hi) // 2
        if tbl[mid] <= sl then lo = mid else hi = mid end
    end
    local seg = tbl[hi] - tbl[lo]
    local f = seg > 0.0 and (sl - tbl[lo]) / seg or 0.0
    return ((lo - 1) + f) / PATH_SAMPLES
end

--- Orbit channels: pivot xyz, pitch, roll, yaw, fov, dof near / far / str, radius.
local function orbitChannels(k)
    if not k.orbit then return nil end
    local c = k.orbit.c
    return { c[1], c[2], c[3], k.rot[1], k.rot[2], k.rot[3], k.fov, k.dof.near, k.dof.far, k.dof.str, k.orbit.d }
end

--- Orbit channels -> camera channels: the camera sits on the sphere around the pivot, facing it.
local function orbitToCam(o, out)
    local fx, fy, fz = M.Basis(o[4], o[6])
    local d = o[11]
    out[1], out[2], out[3] = o[1] - fx * d, o[2] - fy * d, o[3] - fz * d
    for j = 4, 10 do out[j] = o[j] end
    return out
end
local obuf = {}

local function channels(k)
    return {
        k.pos[1], k.pos[2], k.pos[3], k.rot[1], k.rot[2], k.rot[3], k.fov,
        k.dof.near, k.dof.far, k.dof.str,
    }
end

--- Build (or reuse) the expanded key list and the env track of a shot.
local function build(shot)
    local c = cache[shot]
    if c and c.rev == shot.rev and c.n == #shot.keys then return c end
    local ex, envKeys = {}, {}
    local merged = nil
    for _, k in ipairs(shot.keys) do
        local e = {
            t = k.t, ch = channels(k), interp = k.interp, ease = k.ease, bez = k.bez,
            dofOn = k.dof.on, target = k.dof.target, shk = k.shake, och = orbitChannels(k),
        }
        ex[#ex + 1] = e
        if k.hold and k.hold > 0.0 then
            e.still = true -- the camera parks here: arrive and leave at rest
            ex[#ex + 1] = {
                t = k.t + k.hold, ch = e.ch, interp = k.interp, ease = k.ease, bez = k.bez,
                dofOn = e.dofOn, target = e.target, still = true, shk = k.shake, och = e.och,
            }
        end
        if k.env then
            local nm = {}
            if merged then for key, v in pairs(merged) do nm[key] = v end end
            for key, v in pairs(k.env) do nm[key] = v end
            merged = nm
            envKeys[#envKeys + 1] = { t = k.t, e = nm, interp = k.interp, ease = k.ease, bez = k.bez }
        end
    end
    table.sort(ex, function(a, b) return a.t < b.t end)

    -- PATH: centripetal Catmull-Rom through the keys (no overshoot, no loops). Each segment gets
    -- a table of the distance travelled along it, so a distance can be turned back into a spot.
    -- Distance mixes metres, degrees and FOV (Config.Timeline.PathWeights): a pure pan still moves.
    local W = Config.Timeline.PathWeights
    local S = 0.0
    for i = 1, #ex do
        local e, q = ex[i], ex[i + 1]
        e.s, e.len, e.tbl = S, 0.0, nil
        -- two keys taken in the orbit rig: circle their pivot instead of cutting across
        e.orbSeg = q ~= nil and e.och ~= nil and q.och ~= nil and e.interp ~= 'linear'
        if q then
            local p0, p3 = ex[i - 1] or e, ex[i + 2] or q
            local o0 = (ex[i - 1] and ex[i - 1].och) or e.och
            local o3 = (ex[i + 2] and ex[i + 2].och) or (q and q.och)
            local function sample(u, out)
                if e.orbSeg then
                    M.CatmullRom(o0, e.och, q.och, o3, u, obuf)
                    return orbitToCam(obuf, out)
                end
                return M.CatmullRom(p0.ch, e.ch, q.ch, p3.ch, u, out)
            end
            local tbl, acc = { 0.0 }, 0.0
            sample(0.0, bufA)
            local a, b = bufA, bufB
            for k = 1, PATH_SAMPLES do
                sample(k / PATH_SAMPLES, b)
                acc = acc + metric(a, b, W)
                tbl[k + 1] = acc
                a, b = b, a
            end
            e.len, e.tbl = acc, tbl
            S = S + acc
        end
    end

    -- SPEED: one curve s(t) = distance travelled, through every key. Its slope at a key is the
    -- slope through the neighbours, scaled by the key's ease (HOW the camera passes this key):
    --   flow = natural, easeOut = passes slowly (never stops), easeIn = passes fast,
    --   easeInOut = stops here. First / last key and hold edges rest, except a "pass fast" end
    --   key, which starts / ends the shot already moving. Because this is ONE curve for the whole
    --   camera (not one per axis), the speed no longer dips at keys where an axis turns around.
    for i = 1, #ex do
        local e, p, q = ex[i], ex[i - 1], ex[i + 1]
        local f = PASS[e.ease] or 1.0
        local m = 0.0
        if not e.still then
            if p and q and q.t > p.t then m = (q.s - p.s) / (q.t - p.t) * f
            elseif e.ease == 'easeIn' and q and q.t > e.t then m = (q.s - e.s) / (q.t - e.t) * f
            elseif e.ease == 'easeIn' and p and e.t > p.t then m = (e.s - p.s) / (e.t - p.t) * f end
        end
        e.ms = m
    end
    -- Fritsch-Carlson: s(t) never runs backwards (the camera never overshoots a key and returns)
    for i = 1, #ex - 1 do
        local a, b = ex[i], ex[i + 1]
        local dt = b.t - a.t
        if dt > 0.0 then
            local delta = a.len / dt
            if delta <= 1e-9 then
                a.ms, b.ms = 0.0, 0.0
            else
                local al, be = a.ms / delta, b.ms / delta
                local s2 = al * al + be * be
                if s2 > 9.0 then
                    local tau = 3.0 / math.sqrt(s2)
                    a.ms, b.ms = tau * al * delta, tau * be * delta
                end
            end
        end
    end
    c = { rev = shot.rev, n = #shot.keys, ex = ex, envKeys = envKeys, duration = (#ex > 0) and ex[#ex].t or 0.0 }
    cache[shot] = c
    return c
end

local NO_SHAKE = { preset = 'none', amount = 0.0, speed = 0.0, whip = 0.0 }
local outShake = { pa = 'none', aa = 0.0, pb = nil, ab = 0.0, speed = 0.0, whip = 0.0 }

--- Shake parameters at time t. Every key has an effective shake: its own, else the previous key's,
--- else the shot default. Between two keys it blends (presets cross-fade). Shared table.
function TL.ShakeAt(shot, t)
    local def = shot.shake or NO_SHAKE
    local c = build(shot)
    local ex, n = c.ex, #c.ex
    if c.sdef ~= def then
        local cur = def
        for i = 1, n do
            if ex[i].shk then cur = ex[i].shk end
            ex[i].seff = cur
        end
        c.sdef = def
    end
    local a, b, u = def, nil, 0.0
    if n > 0 then
        local i = M.FindSegment(ex, t)
        if i == 0 then a = ex[1].seff
        elseif i >= n then a = ex[n].seff
        else
            a, b = ex[i].seff, ex[i + 1].seff
            local span = ex[i + 1].t - ex[i].t
            u = span > 0.0 and M.Clamp((t - ex[i].t) / span, 0.0, 1.0) or 1.0
            u = u * u * (3.0 - 2.0 * u)
        end
    end
    local o = outShake
    if not b or b == a then
        o.pa, o.aa, o.pb, o.ab, o.speed, o.whip = a.preset, a.amount, nil, 0.0, a.speed, a.whip
    else
        if a.preset == b.preset then
            o.pa, o.aa, o.pb, o.ab = a.preset, M.Lerp(a.amount, b.amount, u), nil, 0.0
        else
            o.pa, o.aa, o.pb, o.ab = a.preset, a.amount * (1.0 - u), b.preset, b.amount * u
        end
        o.speed, o.whip = M.Lerp(a.speed, b.speed, u), M.Lerp(a.whip, b.whip, u)
    end
    return o
end

function TL.Duration(shot)
    if not shot then return 0.0 end
    return build(shot).duration
end

function TL.HasEnv(shot)
    return shot ~= nil and #build(shot).envKeys > 0
end

local fillTarget = nil -- set per Evaluate call: a caller-owned state, or nil = the shared one

local function fillState(a, k)
    outState = outState or Cine.Camera.NewState(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 50.0)
    local s = fillTarget or outState
    s.pos[1], s.pos[2], s.pos[3] = a[1], a[2], a[3]
    s.rot[1] = M.Clamp(a[4], -89.0, 89.0)
    s.rot[2], s.rot[3] = a[5], a[6]
    s.fov = M.Clamp(a[7], Config.Freecam.FovMin, Config.Freecam.FovMax)
    local d = s.dof
    d.on = k.dofOn
    d.near = math.max(a[8], 0.0)
    d.far = math.max(a[9], d.near)
    d.str = M.Clamp(a[10], 0.0, 1.0)
    d.target = k.target
    return s
end

local function evalEnv(c, t)
    local keys = c.envKeys
    local n = #keys
    if n == 0 then return nil end
    local i = M.FindSegment(keys, t)
    local k1 = keys[i == 0 and 1 or i]
    local e = outEnv
    for key in pairs(e) do e[key] = nil end
    for key, v in pairs(k1.e) do e[key] = v end
    if i == 0 or i >= n then return e end
    local k2 = keys[i + 1]
    if k1.interp == 'hold' or k2.t <= k1.t then return e end
    local u = M.Ease(k1.ease, (t - k1.t) / (k2.t - k1.t), k1.bez)
    if k1.e.tod and k2.e.tod then e.tod = M.LerpTod(k1.e.tod, k2.e.tod, u, k2.e.todDir or k1.e.todDir) end
    for _, f in ipairs(ENV_NUM) do
        local a, b = k1.e[f], k2.e[f]
        if a ~= nil and b ~= nil and (f ~= 'tcStrength' or k1.e.timecycle == k2.e.timecycle) then
            e[f] = M.Lerp(a, b, u)
        end
    end
    -- discrete fields keep the outgoing key's value (switch at the next key)
    for _, f in ipairs(ENV_STEP) do e[f] = k1.e[f] end
    return e
end

--- Evaluate the camera and environment of a shot at time t.
--- Returns camState (shared table, copy before keeping), env (shared table | nil).
--- into = a caller-owned state to fill instead (tools like the path preview must not touch the
--- shared one, which is the live camera state); noEnv = skip the environment.
function TL.Evaluate(shot, t, into, noEnv)
    fillTarget = into
    local c = build(shot)
    local ex = c.ex
    local n = #ex
    if n == 0 then return nil, nil end
    local i = M.FindSegment(ex, t)
    local env = (not noEnv) and evalEnv(c, t) or nil
    if i == 0 then return fillState(ex[1].ch, ex[1]), env end
    if i >= n then return fillState(ex[n].ch, ex[n]), env end
    local k1, k2 = ex[i], ex[i + 1]
    local span = k2.t - k1.t
    if k1.interp == 'hold' or span <= 0.0 then return fillState(k1.ch, k1), env end
    if k1.interp == 'linear' then
        -- straight line at constant speed (a custom bezier curve can still shape it)
        local u = (t - k1.t) / span
        if k1.ease == 'bezier' then u = M.Ease('bezier', u, k1.bez) end
        local a, b = k1.ch, k2.ch
        for j = 1, #a do ch[j] = a[j] + (b[j] - a[j]) * u end
        return fillState(ch, k1), env
    end
    -- distance travelled inside this segment at t
    local frac = (t - k1.t) / span
    local sl
    if PASS[k1.ease] then
        -- cubic Hermite of s(t): speed is continuous through the keys
        local f2, f3 = frac * frac, frac * frac * frac
        sl = (f3 - 2 * f2 + frac) * span * k1.ms + (-2 * f3 + 3 * f2) * k1.len + (f3 - f2) * span * k2.ms
    else
        -- 'linear' = even speed inside the gap, 'bezier' = the user's own speed curve
        sl = M.Ease(k1.ease, frac, k1.bez) * k1.len
    end
    local u = paramAt(k1, sl, frac)
    if k1.orbSeg then
        local o0 = (ex[i - 1] and ex[i - 1].och) or k1.och
        local o3 = (ex[i + 2] and ex[i + 2].och) or k2.och
        M.CatmullRom(o0, k1.och, k2.och, o3, u, obuf)
        return fillState(orbitToCam(obuf, ch), k1), env
    end
    local p0 = ex[i - 1] or k1
    local p3 = ex[i + 2] or k2
    M.CatmullRom(p0.ch, k1.ch, k2.ch, p3.ch, u, ch)
    return fillState(ch, k1), env
end

-- Playback ---------------------------------------------------------------------------------

function TL.Active()
    return TL.playing or TL.scrub
end

local function startClockNow()
    startClock = Cine.Clock()
end

--- Begin playback of a shot. Preloads the scene at the first key, then starts the clock.
function TL.Play(shot, from, loop, noPreload)
    local dur = TL.Duration(shot)
    if not shot or #shot.keys == 0 then Cine.Notify(_L('need_keys'), 'error'); return false end
    if dur <= 0.0 then Cine.Notify(_L('need_keys'), 'error'); return false end
    local token = Cine.Session.token
    TL.shotId = shot.id
    TL.loop = loop == true
    TL.scrub = true
    TL.playing = false
    TL.t = M.Clamp(from or 0.0, 0.0, dur)
    if TL.t >= dur then TL.t = 0.0 end
    baseT = TL.t
    if Config.Timeline.PreloadScene and not noPreload and not TL.preloading then
        local k = shot.keys[1]
        TL.preloading = true
        CreateThread(function()
            NewLoadSceneStartSphere(k.pos[1] + 0.0, k.pos[2] + 0.0, k.pos[3] + 0.0, 50.0, 0)
            local deadline = GetGameTimer() + Config.Timeline.PreloadTimeoutMs
            while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do
                Wait(50)
                if Cine.Session.token ~= token then break end
            end
            NewLoadSceneStop()
            TL.preloading = false
            if Cine.Session.token == token and TL.shotId == shot.id then
                startClockNow()
                baseT = TL.t
                TL.playing = true
                Cine.Nui.Send('state', Cine.Session.StatePayload())
            end
        end)
    else
        startClockNow()
        TL.playing = true
    end
    return true
end

function TL.Pause()
    if TL.playing then
        baseT = TL.t
        TL.playing = false
    end
    TL.preloading = false
end

--- Stop: playhead back to 0 and the edit rig takes over from the last pose.
function TL.Stop()
    TL.playing = false
    TL.scrub = false
    TL.t = 0.0
    baseT = 0.0
end

--- Move the playhead. It may go past the last key (that is where new keys are placed): there the
--- camera stays free; inside the shot the timeline holds the camera for preview.
function TL.Seek(shot, t)
    local dur = TL.Duration(shot)
    TL.shotId = shot and shot.id or TL.shotId
    TL.t = M.Clamp(t or 0.0, 0.0, 36000.0)
    baseT = TL.t
    if TL.playing then
        if TL.t > dur then TL.t, baseT = dur, dur end
        startClockNow()
    else
        TL.scrub = dur > 0.0 and TL.t <= dur
    end
end

--- Park the playhead without taking the camera (after a key was added there).
function TL.SetHead(t)
    if TL.playing then return end
    TL.t = M.Clamp(t or 0.0, 0.0, 36000.0)
    baseT = TL.t
    TL.scrub = false
end

--- Hand control back to the rig (user moved the camera while scrubbing / paused).
function TL.ReleaseScrub()
    if not TL.playing then TL.scrub = false end
end

--- Advance the clock. Returns 'ended' when a non-looping playback reached the end.
function TL.Tick(shot)
    if not TL.playing or not shot then return nil end
    local dur = TL.Duration(shot)
    local t = baseT + (Cine.Clock() - startClock)
    if t >= dur then
        if TL.loop and dur > 0.0 then
            t = t % dur
            baseT = t
            startClock = Cine.Clock()
        else
            TL.t = dur
            TL.playing = false
            return 'ended'
        end
    end
    TL.t = t
    return nil
end

--- Reset everything (session close / project switch).
function TL.Reset()
    TL.playing, TL.scrub, TL.t, TL.preloading, TL.shotId = false, false, 0.0, false, nil
    baseT = 0.0
end
