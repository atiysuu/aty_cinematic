-- Director session: Open / master loop / the ONE guarded Close.
-- States: closed -> opening -> edit <-> preview (timeline active) -> closing -> closed.
Cine.Session = { active = false, opened = false, closing = false, busy = false, token = 0, acked = false, ped = 0 }
local S = Cine.Session
local M = CineMath

S.dof = { on = false, near = Config.Dof.Defaults.near, far = Config.Dof.Defaults.far, str = Config.Dof.Defaults.strength, target = nil }

local lastCamSig, lastCamAt, lastPlayheadAt = nil, 0, 0

-- Payloads --------------------------------------------------------------------------------------

function S.Mode()
    if Cine.Timeline.Active() then return 'preview' end
    return 'edit'
end

function S.StatePayload()
    local TL, I, St, R = Cine.Timeline, Cine.Input, Cine.Store, Cine.Rigs
    return {
        mode = S.Mode(), rig = R.mode, rigTarget = R.target,
        cursor = I.cursor, clean = I.clean,
        playing = TL.playing, scrub = TL.scrub, preloading = TL.preloading,
        dirty = St.dirty, saving = Cine.Persist.saving,
        shotId = St.shotId, projectId = St.project and St.project.id or nil,
        gizmo = { active = Cine.Gizmo.active, kind = Cine.Gizmo.kind, id = Cine.Gizmo.id, mode = Cine.Gizmo.mode, space = Cine.Gizmo.space },
        speed = Cine.Freecam.Speed(), smoothing = Cine.Freecam.SmoothAmount(), inertia = Cine.Freecam.Inertia(),
        pathViz = Cine.PathViz.enabled, recording = S.rec and S.rec.phase or false,
        placer = Cine.Placer.active and Cine.Placer.id or false,
    }
end

function S.EventPayload()
    return { active = S.active, mode = S.Mode(), clean = Cine.Input.clean }
end

local function fireState()
    TriggerEvent('aty_cinematic:client:state', S.EventPayload())
end

local function setupPayload()
    local keys = {}
    for _, def in pairs(Config.Keys) do keys[#keys + 1] = { label = def.label, key = def.key, command = def.command } end
    table.sort(keys, function(a, b) return a.command < b.command end)
    local _, weathers = CineWeatherSet()
    return {
        locale = Config.Locale,
        strings = Locales[Config.Locale] or Locales.en,
        keys = keys,
        version = GetResourceMetadata(Cine.Resource, 'version', 0),
        config = {
            fov = { min = Config.Freecam.FovMin, max = Config.Freecam.FovMax },
            speed = { min = Config.Freecam.MinSpeed, max = Config.Freecam.MaxSpeed },
            dof = { enabled = Config.Dof.Enabled, defaults = Config.Dof.Defaults },
            lights = { max = Config.Lights.Max, defaults = Config.Lights.Defaults },
            actors = { max = Config.Actors.Max },
            timeline = { maxKeys = Config.Timeline.MaxKeysPerShot, playheadHz = Config.Timeline.PlayheadHz },
            ratios = Config.Output.Ratios,
            letterbox = Config.Output.Letterbox,
            weathers = weathers,
            timeScaleMin = Config.Env.TimeScaleMin,
            autosaveSec = Config.Storage.AutosaveSec,
            presets = {
                moves = CineMoves.Meta(), moveGroups = CineMoves.Groups,
                looks = CineLooksMeta(), lookGroups = CineLookGroups,
                scenes = CineScenesMeta(), sceneGroups = CineSceneGroups,
            },
        },
    }
end

-- Camera adoption ------------------------------------------------------------------------------

--- Continue in the current rig from this pose (orbit stays orbit); free if the rig cannot.
local function adoptRig(cam)
    local R = Cine.Rigs
    if R.mode ~= 'free' and R.Set(R.mode, R.target, cam, true) then return end
    R.Set('free', nil, cam)
end

local function adoptCamera()
    local cam = Cine.Camera.state
    if not cam then return end
    local d = cam.dof
    S.dof.on, S.dof.near, S.dof.far, S.dof.str, S.dof.target = d.on, d.near, d.far, d.str, d.target
    adoptRig(cam)
end

--- The timeline held the camera (scrub / paused / ended) and the user takes over: continue from that pose.
function S.ReleaseToRig()
    local TL = Cine.Timeline
    if TL.playing or not TL.scrub then return end
    adoptCamera()
    TL.ReleaseScrub()
    Cine.Nui.Send('state', S.StatePayload())
end

--- The playhead went past the last key: the free camera continues from the shot's end pose,
--- unless the user has flown it somewhere since (that pose is about to become the next key).
function S.ParkAtEnd(shot)
    if not shot or Cine.Rigs.userMoved then return end
    S.ParkAt(shot, Cine.Timeline.Duration(shot))
end

--- Put the free camera on the shot's pose at time t (used when the timeline does not hold it).
function S.ParkAt(shot, t)
    local cam = shot and Cine.Timeline.Evaluate(shot, t)
    if not cam then return end
    Cine.Rigs.userMoved = false
    local d = cam.dof
    S.dof.on, S.dof.near, S.dof.far, S.dof.str, S.dof.target = d.on, d.near, d.far, d.str, d.target
    adoptRig(cam)
end

-- Rockstar Editor recording ---------------------------------------------------------------------

local recWatch = nil -- { t0, lost } while a clip records: when did the game drop the recording?

local function watchRec()
    if recWatch and not recWatch.lost and not IsRecording() then
        recWatch.lost = true
        print(('[aty_cinematic] rec: the game STOPPED recording by itself during %s, %d ms after start')
            :format(S.rec and S.rec.phase or '?', GetGameTimer() - recWatch.t0))
    end
end

local function recWait(ms, token)
    local untilT = GetGameTimer() + ms
    while GetGameTimer() < untilT do
        Wait(0)
        watchRec()
        if S.token ~= token or not S.rec then return false end
    end
    return true
end

--- One line per recording step in the FiveM client log (CitizenFX_log_*.log), so a failed save
--- can be traced afterwards.
local function rlog(fmt, ...)
    print(('[aty_cinematic] rec: ' .. fmt):format(...))
end

local function camToPlayer(pos)
    local pc = GetEntityCoords(PlayerPedId())
    local dx, dy, dz = pos[1] - pc.x, pos[2] - pc.y, pos[3] - pc.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Record shots into Rockstar Editor clips, one clip per shot, one after another:
--- preload -> start recording -> hold the first frame (lead-in) -> play -> hold the last frame
--- (tail) -> save -> short gap -> next shot. all = every shot of the project, else the current one.
--- Backspace / closing the director aborts and discards the running clip.
function S.Record(all)
    local cfg = Config.RockstarEditor
    if not cfg.Enabled or S.rec or not S.active then return false end
    local St, TL = Cine.Store, Cine.Timeline
    if not St.project then return false end
    local shots = {}
    if all then
        for _, sh in ipairs(St.project.shots) do
            if #sh.keys >= 2 and TL.Duration(sh) > 0.0 then shots[#shots + 1] = sh end
        end
    else
        local sh = St.CurrentShot()
        if sh and #sh.keys >= 2 and TL.Duration(sh) > 0.0 then shots[1] = sh end
    end
    if #shots == 0 then Cine.Notify(_L('need_keys'), 'error'); return false end
    if IsRecording() then Cine.Notify(_L('rec_busy'), 'error'); return false end
    local set = St.project.settings
    local leadIn = set.leadIn or cfg.LeadIn
    local tail = set.tail or cfg.Tail
    local token = S.token
    -- every shot into ONE clip, cut straight from one shot to the next (no waiting in between):
    -- lead-in once at the start, tail once at the end
    local single = all and set.recSingle ~= false and #shots > 1

    S.rec = { phase = 'prepare', index = 0, total = #shots }
    Cine.Gizmo.Stop()
    Cine.Input.SetClean(true)
    Cine.Nui.Send('state', S.StatePayload())
    rlog('start: %d shot(s), %s, lead-in %.1fs, tail %.1fs, actors %d, build %d',
        #shots, single and 'one clip' or 'one clip per shot', leadIn, tail, #St.project.actors, GetGameBuildNumber())

    CreateThread(function()
        local function alive() return S.token == token and S.rec ~= nil end
        local function finish(key, ...)
            S.rec = nil
            if S.token == token and S.active then
                Cine.Input.SetClean(false)
                Cine.Nui.Send('state', S.StatePayload())
                Cine.Notify(_L(key, ...), key == 'rec_done' and 'success' or 'error')
            end
        end
        local done = 0
        local t0 = 0
        for i, shot in ipairs(shots) do
            S.rec.index = i
            local first = (not single) or i == 1
            local last = (not single) or i == #shots
            -- the frame loop shows the CURRENT shot: switch to this one, camera on its first frame
            if St.shotId ~= shot.id then St.ShotSelect(shot.id) end
            TL.Stop()
            TL.Seek(shot, 0.0)
            St.PushNow()
            local k = shot.keys[1]

            if first then
                -- 1) stream the area of the first key before the clip starts
                NewLoadSceneStartSphere(k.pos[1] + 0.0, k.pos[2] + 0.0, k.pos[3] + 0.0, 50.0, 0)
                local deadline = GetGameTimer() + Config.Timeline.PreloadTimeoutMs
                while not IsNewLoadSceneLoaded() and GetGameTimer() < deadline do
                    Wait(50)
                    if not alive() then NewLoadSceneStop(); rlog('aborted while loading'); return end
                end
                NewLoadSceneStop()
            end
            rlog('shot %s (%d/%d): length %.2fs, first key %.0fm from the player, env keys %s, shake %s',
                shot.id, i, #shots, TL.Duration(shot), camToPlayer(k.pos), tostring(TL.HasEnv(shot)),
                shot.shake and shot.shake.preset or '-')

            if first then
                -- 2) start the clip
                t0 = GetGameTimer()
                StartRecording(cfg.Mode)
                local deadline = t0 + cfg.StartTimeoutMs
                while not IsRecording() and GetGameTimer() < deadline do
                    Wait(0)
                    if not alive() then rlog('aborted while starting'); return end
                end
                rlog('StartRecording(%d): IsRecording=%s after %d ms', cfg.Mode, tostring(IsRecording()), GetGameTimer() - t0)
                recWatch = { t0 = t0, lost = false }
                if not IsRecording() then
                    if done == 0 then return finish('rec_failed') end
                    return finish('rec_done', done)
                end
                -- 3) lead-in: first frame held while the editor shows its watermark
                S.rec.phase = 'leadin'
                if not recWait(math.floor(leadIn * 1000), token) then rlog('aborted in lead-in'); return end
            end

            -- 4) the shot (in one-clip mode the next shot starts on the very next frame: a cut)
            S.rec.phase = 'play'
            if Config.Actors.RestartOnPlay then Cine.Actors.Restart() end
            TL.Play(shot, 0.0, false, true)
            while TL.playing or TL.preloading do
                Wait(0)
                watchRec()
                if not alive() then rlog('aborted while playing'); return end
            end

            if last then
                -- 5) tail on the last frame, then save
                S.rec.phase = 'tail'
                if not recWait(math.floor(tail * 1000), token) then rlog('aborted in tail'); return end
                local rec = IsRecording()
                rlog('saving after %d ms of recording: IsRecording=%s', GetGameTimer() - t0, tostring(rec))
                if rec then StopRecordingAndSaveClip() end
                -- give the game time to write the clip before the next one starts
                local t1 = GetGameTimer()
                while IsRecording() and GetGameTimer() - t1 < 5000 do Wait(50) end
                rlog('save requested: IsRecording=%s %d ms later', tostring(IsRecording()), GetGameTimer() - t1)
                done = done + 1
                if i < #shots and not recWait(math.floor(cfg.Gap * 1000), token) then rlog('aborted between shots'); return end
            end
        end
        rlog('finished: %d clip(s) requested', done)
        finish('rec_done', done)
    end)
    return true
end

--- Abort a running recording (the clip is discarded).
function S.RecordAbort()
    if not S.rec then return end
    S.rec = nil
    rlog('aborted: clip discarded')
    if IsRecording() then pcall(StopRecordingAndDiscardClip) end
end

--- Diagnostic: which thing the director does every frame makes the game drop a recording?
--- Runs one short recording per ingredient (director must be closed), discards every clip and
--- writes one result line per test into the client log.
RegisterCommand('cinerecdiag', function()
    if S.active then rlog('diag: close the director first'); return end
    if IsRecording() then rlog('diag: already recording'); return end
    CreateThread(function()
        local ped = PlayerPedId()
        local cam = nil
        local tcName = nil
        local tcs = Cine.List('timecycles')
        if type(tcs[1]) == 'string' then tcName = tcs[1] elseif type(tcs[1]) == 'table' then tcName = tcs[1].name end
        local function camOn()
            local p, r = GetGameplayCamCoord(), GetGameplayCamRot(2)
            cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y, p.z + 15.0, r.x, 0.0, r.z, 50.0, true, 2)
            SetCamActive(cam, true)
            RenderScriptCams(true, false, 0, true, false)
        end
        local function camOff()
            RenderScriptCams(false, false, 0, true, false)
            if cam then DestroyCam(cam, false); cam = nil end
        end
        local tests = {
            { 'baseline (nothing)' },
            { 'script camera rendering', camOn, nil, camOff },
            { 'DisableAllControlActions every frame', nil, function() DisableAllControlActions(0) end },
            { 'HUD + feed hidden every frame', nil, function() HideHudAndRadarThisFrame(); ThefeedHideThisFrame() end },
            { 'player locally invisible every frame', nil, function() SetEntityLocallyInvisible(ped) end },
            { 'player frozen + invincible', function() FreezeEntityPosition(ped, true); SetEntityInvincible(ped, true) end, nil,
                function() FreezeEntityPosition(ped, false); SetEntityInvincible(ped, false) end },
            { 'streaming focus 20 m away every frame', nil, function()
                local c = GetEntityCoords(ped); SetFocusPosAndVel(c.x + 0.0, c.y + 20.0, c.z + 10.0, 0.0, 0.0, 0.0) end, ClearFocus },
            { 'clock override every frame', nil, function() NetworkOverrideClockTime(GetClockHours(), GetClockMinutes(), 0) end },
            { 'weather set (persist)', function() SetOverrideWeather('EXTRASUNNY'); SetWeatherTypeNowPersist('EXTRASUNNY') end, nil,
                function() ClearOverrideWeather(); ClearWeatherTypePersist() end },
            { 'timecycle modifier (' .. tostring(tcName) .. ')', function() if tcName then SetTimecycleModifier(tcName) end end, nil, ClearTimecycleModifier },
            { 'time scale 0.9', function() SetTimeScale(0.9) end, nil, function() SetTimeScale(1.0) end },
            { 'NUI focus (cursor)', function() SetNuiFocus(true, true); SetNuiFocusKeepInput(true) end, nil,
                function() SetNuiFocus(false, false); SetNuiFocusKeepInput(false) end },
        }
        rlog('diag: %d tests, 3 s each, clips are discarded', #tests)
        for i, tst in ipairs(tests) do
            local name, setup, tick, cleanup = tst[1], tst[2], tst[3], tst[4]
            if setup then pcall(setup) end
            local t0 = GetGameTimer()
            StartRecording(1)
            while not IsRecording() and GetGameTimer() - t0 < 2000 do if tick then tick() end; Wait(0) end
            local started, lostAt = IsRecording(), nil
            local tStart = GetGameTimer()
            while GetGameTimer() - tStart < 3000 do
                if tick then tick() end
                if started and not lostAt and not IsRecording() then lostAt = GetGameTimer() - tStart end
                Wait(0)
            end
            if IsRecording() then StopRecordingAndDiscardClip() end
            if cleanup then pcall(cleanup) end
            rlog('diag %2d %-42s started=%s  %s', i, name, tostring(started),
                lostAt and ('DROPPED after ' .. lostAt .. ' ms') or (started and 'kept recording' or '-'))
            local tw = GetGameTimer()
            while IsRecording() and GetGameTimer() - tw < 3000 do Wait(50) end
            Wait(800)
        end
        rlog('diag: done')
    end)
end, false)

--- Diagnostic: a plain 5 s clip with nothing else going on (works with the director closed).
--- If this one also fails to save, the cause is the game / server / location, not the director.
RegisterCommand('cinerectest', function()
    if IsRecording() then rlog('test: already recording'); return end
    CreateThread(function()
        rlog('test: plain 5 s clip, director %s, build %d', S.active and 'OPEN' or 'closed', GetGameBuildNumber())
        local t0 = GetGameTimer()
        StartRecording(1)
        while not IsRecording() and GetGameTimer() - t0 < 3000 do Wait(0) end
        rlog('test: IsRecording=%s after %d ms', tostring(IsRecording()), GetGameTimer() - t0)
        Wait(5000)
        StopRecordingAndSaveClip()
        rlog('test: save requested')
    end)
end, false)

--- Stop playback: playhead to 0, the free rig continues from the last pose.
function S.Stop()
    local TL = Cine.Timeline
    if TL.Active() then adoptCamera() end
    TL.Stop()
    Cine.Nui.Send('playhead', { t = 0.0, playing = false })
    Cine.Nui.Send('state', S.StatePayload())
end

function S.SetRig(mode, targetId)
    local cam = Cine.Camera.state
    if not cam then return false, 'no_camera' end
    S.ReleaseToRig()
    local ok, why = Cine.Rigs.Set(mode, targetId, cam)
    Cine.Nui.Send('state', S.StatePayload())
    return ok, why
end

function S.Play(shotId, from, loop)
    local shot = Cine.Store.GetShot(shotId or Cine.Store.shotId)
    if not shot then return false end
    Cine.Gizmo.Stop()
    Cine.Placer.Stop(true)
    local ok = Cine.Timeline.Play(shot, from, loop == nil and shot.loop or loop)
    if ok and Config.Actors.RestartOnPlay and (from or 0.0) <= 0.05 then Cine.Actors.Restart() end
    return ok
end

function S.TogglePlay()
    local TL = Cine.Timeline
    if TL.playing or TL.preloading then
        TL.Pause()
    else
        local shot = Cine.Store.CurrentShot()
        if not shot then Cine.Notify(_L('need_keys'), 'error'); return end
        S.Play(shot.id, TL.scrub and TL.t or 0.0, shot.loop)
    end
    Cine.Nui.Send('state', S.StatePayload())
end

--- Called by the NUI once it has shown the director.
function S.Ack()
    S.acked = true
end

-- Master loop -------------------------------------------------------------------------------------

local MOVE_CONTROLS = { 32, 33, 34, 35, 38, 44 }

--- True when the user asks to move / look while the timeline holds the camera.
local function userWantsControl(ctx)
    local K = Config.Controls
    for _, c in ipairs(MOVE_CONTROLS) do
        if IsDisabledControlPressed(0, c) then return true end
    end
    local looking = (not ctx.cursor) or (IsDisabledControlPressed(0, K.LookHold) and not ctx.overUi)
    if looking and (GetDisabledControlNormal(0, K.LookX) ~= 0.0 or GetDisabledControlNormal(0, K.LookY) ~= 0.0) then
        return true
    end
    return false
end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function sendReadouts(cam, now)
    local TL = Cine.Timeline
    if now - lastCamAt >= 100 then
        lastCamAt = now
        local d = cam.dof or S.dof
        local ob = Cine.Rigs.mode == 'orbit' and Cine.Rigs.OrbitInfo() or nil
        local sig = ('%.2f|%.2f|%.2f|%.1f|%.1f|%.1f|%.1f|%s|%.1f|%.1f|%.2f|%s|%.2f|%s'):format(
            cam.pos[1], cam.pos[2], cam.pos[3], cam.rot[1], cam.rot[2], cam.rot[3], cam.fov,
            tostring(d.on), d.near, d.far, d.str, tostring(d.target), Cine.Freecam.Speed(),
            ob and ('%.2f/%.2f/%.1f'):format(ob.dist, ob.lift, ob.spin) or '-')
        if sig ~= lastCamSig then
            lastCamSig = sig
            Cine.Nui.Send('cam', {
                pos = { round2(cam.pos[1]), round2(cam.pos[2]), round2(cam.pos[3]) },
                rot = { round2(cam.rot[1]), round2(cam.rot[2]), round2(cam.rot[3]) },
                fov = round2(cam.fov), speed = round2(Cine.Freecam.Speed()),
                dof = { on = d.on == true, near = round2(d.near), far = round2(d.far), str = round2(d.str), target = d.target },
                orbit = ob and { dist = round2(ob.dist), lift = round2(ob.lift), spin = round2(ob.spin) } or false,
            })
        end
    end
    if TL.playing and now - lastPlayheadAt >= 1000 / Config.Timeline.PlayheadHz then
        lastPlayheadAt = now
        Cine.Nui.Send('playhead', { t = round2(TL.t), playing = true })
    end
end

local function frame(token)
    local dt = math.min(GetFrameTime(), 0.1)
    local now = GetGameTimer()
    local I, TL, St = Cine.Input, Cine.Timeline, Cine.Store

    I.DisableControls()
    I.Tick()

    if not I.typing and IsDisabledControlJustPressed(0, Config.Controls.Exit) then
        S.Close('user')
        return
    end
    local ped = PlayerPedId()
    if ped ~= S.ped then S.Close('ped_changed'); return end
    if Config.Session.CloseOnDeath and IsPedDeadOrDying(ped, true) then S.Close('death'); return end

    local shot = St.CurrentShot()
    local result = TL.Tick(shot)

    local cam, env = nil, nil
    if TL.Active() and shot then
        cam, env = TL.Evaluate(shot, TL.t)
        -- while a R* clip records, the timeline keeps the camera (lead-in / tail frames too)
        if cam and not TL.playing and not S.rec and userWantsControl(I) then
            S.ReleaseToRig()
            cam, env = nil, nil
        end
    end
    if not cam then
        local any
        cam, any = Cine.Rigs.Tick(dt, I, S.dof)
        if any then Cine.Rigs.userMoved = true end
        if any and TL.scrub and not TL.playing then S.ReleaseToRig() end
    end
    if result == 'ended' then Cine.Nui.Send('playhead', { t = round2(TL.t), playing = false }); Cine.Nui.Send('state', S.StatePayload()) end

    -- shake: per-key blend while the timeline drives the camera, the shot default in free flight
    local sp
    if TL.Active() and shot then sp = TL.ShakeAt(shot, TL.t) else sp = Cine.Shake.Params(shot and shot.shake) end
    local fx = Cine.Shake.Tick(cam, dt, sp, TL.Active() and TL.t or nil)
    Cine.Camera.Apply(cam, dt, Cine.Actors.GetPos, fx)
    Cine.Env.Tick((TL.Active() and env) or Cine.Env.live)
    Cine.Lights.Tick(St.project, shot, cam.pos, TL.Active(), (not I.clean) and not TL.playing)
    Cine.Actors.Highlight((not I.clean) and not TL.playing and not S.rec)
    Cine.Gizmo.Tick()
    Cine.Placer.Tick()

    Cine.Hud.Tick()
    if Config.Session.HidePlayer then SetEntityLocallyInvisible(ped) end
    if Config.Session.StreamAroundCamera then
        SetFocusPosAndVel(cam.pos[1] + 0.0, cam.pos[2] + 0.0, cam.pos[3] + 0.0, 0.0, 0.0, 0.0)
    end

    Cine.Persist.Tick()
    St.Flush(now)
    sendReadouts(cam, now)
    -- last: it evaluates the timeline into its own tables, after everything that reads cam
    Cine.PathViz.Tick(shot, (not I.clean) and not TL.playing and not TL.preloading)
end

local function masterLoop(token)
    while S.active and S.token == token do
        Wait(0)
        if S.token ~= token or not S.active then return end -- state can change during any yield
        local ok, err = pcall(frame, token)
        if not ok then
            Cine.Err('director frame error: %s', tostring(err))
            S.Close('error')
            Cine.Notify(_L('error_closed'), 'error')
            return
        end
    end
end

-- Open ----------------------------------------------------------------------------------------------

local function doOpen()
    if not Cine.WaitReady(10000) then return false end
    local res = Cine.Persist.Open()
    if not res.ok then
        Cine.Notify(res.reason == 'denied' and _L('denied') or _L('busy'), 'error')
        return false
    end

    S.opened = true
    S.token = S.token + 1
    local token = S.token
    S.acked, S.closing = false, false
    lastCamSig, lastCamAt, lastPlayheadAt = nil, 0, 0

    Cine.Env.Reset()
    Cine.Shake.Reset()
    Cine.Input.Reset()
    Cine.Persist.Reset()
    Cine.Timeline.Reset()
    S.dof = { on = false, near = Config.Dof.Defaults.near, far = Config.Dof.Defaults.far, str = Config.Dof.Defaults.strength, target = nil }

    local ped = PlayerPedId()
    S.ped = ped

    local state = Cine.Camera.Create()
    state.fov = M.Clamp(state.fov, Config.Freecam.FovMin, Config.Freecam.FovMax)
    state.dof = S.dof
    Cine.Camera.Activate()
    Cine.Rigs.mode, Cine.Rigs.target = 'free', nil
    Cine.Freecam.SetFromState(state)

    if Config.Session.FreezePlayer then
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
    end
    DisableIdleCamera(true)
    Cine.Hud.Open()

    S.active = true
    Cine.Nui.Send('setup', setupPayload())
    Cine.Nui.Send('open', {})
    Cine.Nui.Send('projects', res.projects or {})
    Cine.Nui.Send('env', Cine.Env.live) -- the Environment panel shows the start look
    Cine.Store.PushNow()
    Cine.Input.SetCursor(Config.Session.StartWithCursor ~= false)
    fireState()

    -- Straight to work: reopen the most recent project, or create the first one.
    if Config.Session.AutoOpenProject ~= false then
        CreateThread(function()
            if S.token ~= token or not S.active or Cine.Store.project then return end
            local list = res.projects or {}
            if list[1] and list[1].id then
                Cine.Persist.Load(list[1].id)
            else
                local made = Cine.Persist.Create(_L('default_project'))
                if made.ok then Cine.Nui.Send('projects', made.projects or {}) end
            end
        end)
    end

    -- The NUI must confirm the director is visible, or the session ends (bug-lessons: camera view needs an ack).
    CreateThread(function()
        local deadline = GetGameTimer() + Config.Session.AckTimeoutMs
        while GetGameTimer() < deadline and not S.acked do
            Wait(100)
            if S.token ~= token or not S.active then return end
        end
        if S.token == token and S.active and not S.acked then
            Cine.Notify(_L('ack_failed'), 'error')
            S.Close('ack_timeout')
        end
    end)

    CreateThread(function() masterLoop(token) end)
    return true
end

function S.Open()
    if S.busy or S.active or S.closing then return false end
    S.busy = true
    local ok, res = pcall(doOpen)
    S.busy = false
    if not ok then
        Cine.Err('open failed: %s', tostring(res))
        S.Close('open_error')
        return false
    end
    if res ~= true and S.opened then S.Close('open_failed') end
    return res == true
end

-- Close -----------------------------------------------------------------------------------------------

local function step(name, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Cine.Err('close step %s failed: %s', name, tostring(err)) end
end

--- The ONLY exit. Idempotent, synchronous (also runs from onResourceStop), every step guarded.
function S.Close(reason)
    if not S.opened or S.closing then return end
    S.closing = true
    if S.rec then step('rec', S.RecordAbort); Cine.Notify(_L('rec_aborted'), 'error') end
    S.active = false
    S.token = S.token + 1 -- invalidates the loop and every pending thread of this session
    local ped = S.ped

    if reason ~= 'resource_stop' and Cine.Store.project and Cine.Store.dirty then
        step('autosave', Cine.Persist.Save, true) -- fire-and-forget latent save
    end
    step('gizmo', Cine.Gizmo.Stop)
    step('placer', Cine.Placer.Stop, true)
    step('timeline', Cine.Timeline.Reset)
    step('env', Cine.Env.Restore)
    step('actors', Cine.Actors.DespawnAll)
    step('shake', Cine.Shake.Reset)
    step('camera', Cine.Camera.Destroy)
    step('focus', ClearFocus)
    step('ped', function()
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            FreezeEntityPosition(ped, false)
            SetEntityInvincible(ped, false)
            SetEntityVisible(ped, true, false)
        end
    end)
    step('idle', DisableIdleCamera, false)
    step('hud', Cine.Hud.Close)
    step('nui', function()
        Cine.Nui.Send('close', {})
        Cine.Nui.SetFocus(false, false)
    end)
    step('rig', function() Cine.Rigs.mode, Cine.Rigs.target = 'free', nil end)
    step('store', function()
        Cine.Store.project, Cine.Store.shotId, Cine.Store.dirty = nil, nil, false
    end)
    step('input', Cine.Input.Reset)

    S.opened, S.closing, S.ped = false, false, 0
    fireState()
    Cine.Debug('session closed:', reason)
end

-- Entry points ----------------------------------------------------------------------------------------

RegisterCommand(Config.Access.Command, function()
    if S.active then S.Close('command') else CreateThread(S.Open) end
end, false)

exports('IsDirectorActive', function() return S.active end)
exports('GetDirectorCam', function() return Cine.Camera.handle end)
exports('IsCinematicPlaying', function() return Cine.Timeline.playing end)
exports('CloseDirector', function(reason) S.Close(type(reason) == 'string' and reason or 'export') end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == Cine.Resource then S.Close('resource_stop') end
end)
