-- Ready-made camera moves, atmospheres and scene set-ups: turns the data of shared/moves.lua,
-- looks.lua and scenes.lua into project changes. Every document change goes through Cine.Store.
-- Input comes from the NUI and is untrusted: ids are looked up, numbers clamped, names sanitized.
Cine.Presets = {}
local P = Cine.Presets
local M = CineMath
local S = CineSchema
local St = Cine.Store

local function copy3(a) return { a[1], a[2], a[3] } end

--- What the camera looks at: the first thing a ray along its view axis hits, or nil.
local function probe(cam)
    local fx, fy, fz = M.Basis(cam.rot[1], cam.rot[3])
    local p, far = cam.pos, Config.Presets.ProbeDistance
    local handle = StartExpensiveSynchronousShapeTestLosProbe(p[1] + 0.0, p[2] + 0.0, p[3] + 0.0,
        p[1] + fx * far, p[2] + fy * far, p[3] + fz * far, 511, PlayerPedId(), 7)
    local status, hit, c = GetShapeTestResult(handle)
    if status ~= 2 or not (hit == true or hit == 1) or not c then return nil end
    local dx, dy, dz = c.x - p[1], c.y - p[2], c.z - p[3]
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist < 0.8 then return nil end
    return { c.x, c.y, c.z }, dist
end

--- The point a move should frame: the chosen actor, else the orbit pivot, else what the camera
--- looks at, else a point straight ahead. Returns { x, y, z }, kind.
function P.Subject(actorId)
    local cam = Cine.Camera.state
    local a = actorId and St.GetActor(actorId) or nil
    if a then
        local e = Cine.Actors.GetEntity(a.id)
        if e and IsEntityAPed(e) then
            local b = GetPedBoneCoords(e, Config.Rigs.Follow.LookBone, 0.0, 0.0, 0.0)
            return { b.x, b.y, b.z }, 'actor'
        elseif e then
            local c = GetEntityCoords(e)
            return { c.x, c.y, c.z + 0.3 }, 'actor'
        end
        -- still spawning: the stored position (peds: centre -> head height)
        return { a.pos[1], a.pos[2], a.pos[3] + (a.kind == 'vehicle' and 0.3 or 0.65) }, 'actor'
    end
    local orbit = (not Cine.Timeline.Active()) and Cine.Rigs.OrbitKey() or nil
    if orbit then return copy3(orbit.c), 'pivot' end
    local hit = probe(cam)
    if hit then return hit, 'ray' end
    local fx, fy, fz = M.Basis(cam.rot[1], cam.rot[3])
    local d = Config.Presets.SubjectFallback
    return { cam.pos[1] + fx * d, cam.pos[2] + fy * d, cam.pos[3] + fz * d }, 'ahead'
end

--- Show the shot at time t (same as clicking a key on the timeline).
local function showAt(shot, t)
    local TL = Cine.Timeline
    St.ShotSelect(shot.id)
    Cine.Gizmo.Stop()
    if TL.playing then TL.Pause() end
    TL.Seek(shot, t)
    if not TL.Active() then Cine.Session.ParkAt(shot, t) end
    Cine.Rigs.userMoved = false
    Cine.Nui.Send('playhead', { t = t, playing = false })
    St.PushNow()
end

-- camera moves --------------------------------------------------------------------------------------

--- o = { id, dur, amount, dir, soft, shake, mode = 'new' | 'append', target = actor id, name }
--- from = { pos, rot, fov, subject, ground }: build the move from that pose instead of the live
--- camera (the camera of a placed scene).
function P.ApplyMove(o, from)
    local live = Cine.Camera.state
    if not St.project or not live or type(o) ~= 'table' or not CineMoves.Get(o.id) then return { ok = false } end
    local cam = from or live
    local subject, kind
    if from then subject, kind = from.subject, 'scene' else subject, kind = P.Subject(S.Id(o.target)) end
    local keys, shake = CineMoves.Build(o.id, {
        pos = copy3(cam.pos), rot = copy3(cam.rot), fov = cam.fov, subject = subject,
        ground = from and from.ground or Cine.Ground(subject[1], subject[2], subject[3] + 0.5),
    }, { dur = o.dur, amount = o.amount, dir = o.dir, soft = o.soft ~= false })
    if not keys then return { ok = false } end
    if o.shake == false then shake = nil end

    local shot = St.CurrentShot()
    local append = o.mode == 'append' and shot ~= nil and #shot.keys > 0
    if not append and (not shot or #shot.keys > 0) then
        shot = St.ShotAdd(S.Name(o.name, nil))
        if not shot then return { ok = false, reason = 'max_shots' } end
    end

    local t0, first, last = 0.0, 1, nil
    if append then
        last = shot.keys[#shot.keys]
        t0 = last.t + last.hold + Config.Timeline.DefaultKeyGap
        -- the camera still sits on the last key and the move starts there: carry on from that key
        -- instead of adding a twin of it after a pause
        local k = keys[1]
        local dx, dy, dz = k.pos[1] - last.pos[1], k.pos[2] - last.pos[2], k.pos[3] - last.pos[3]
        local near = dx * dx + dy * dy + dz * dz < 0.0025 and math.abs(k.rot[1] - last.rot[1]) < 0.5
            and math.abs(M.WrapAngle(k.rot[3] - last.rot[3])) < 0.5 and math.abs(k.fov - last.fov) < 0.5
        if near and #keys > 1 then
            t0, first = last.t + last.hold, 2
            if k.orbit then St.KeyUpdate(shot.id, last.id, { orbit = k.orbit }) end
        else
            last = nil
        end
    end

    local d = live.dof or {}
    local raws = {}
    for i = first, #keys do
        local k = keys[i]
        raws[#raws + 1] = {
            t = t0 + k.t, pos = k.pos, rot = k.rot, fov = k.fov, ease = k.ease, orbit = k.orbit,
            dof = { on = d.on == true, near = d.near, far = d.far, str = d.str, target = d.target },
        }
    end
    if shake and append then raws[1].shake = shake end
    local added = St.KeysInsert(shot.id, raws)
    if not added or #added == 0 then return { ok = false, reason = 'max_keys' } end
    if shake and not append then St.ShotUpdate(shot.id, { shake = shake }) end
    showAt(shot, last and (last.t + last.hold) or added[1].t)
    return { ok = true, shotId = shot.id, keys = #added, subject = kind }
end

-- atmospheres ---------------------------------------------------------------------------------------

--- o = { id, dof = bool, shake = bool, target = actor id }
function P.ApplyLook(o)
    local look = type(o) == 'table' and CineLook(o.id) or nil
    local cam = Cine.Camera.state
    if not look or not cam then return { ok = false } end
    local clean = S.Env(look.env, (CineWeatherSet()))
    if not clean then return { ok = false } end
    Cine.Session.ReleaseToRig()
    local live = Cine.Env.live
    for f, v in pairs(clean) do live[f] = v end
    Cine.Nui.Send('env', live)

    if o.dof == true and look.dof and Config.Dof.Enabled then
        -- focus where the subject is; the look only decides how strong the blur is
        local id = S.Id(o.target)
        local subject, kind = P.Subject(id)
        local dx, dy, dz = subject[1] - cam.pos[1], subject[2] - cam.pos[2], subject[3] - cam.pos[3]
        local dist = math.max(math.sqrt(dx * dx + dy * dy + dz * dz), 0.5)
        local dof = Cine.Session.dof
        dof.on, dof.str = true, look.dof
        dof.near, dof.far = dist * 0.6, dist * 1.6 + 0.5
        dof.target = kind == 'actor' and id or nil      -- an actor keeps the focus when it moves
    end
    if o.shake == true and look.shake and St.shotId then
        St.ShotUpdate(St.shotId, { shake = look.shake })
    end
    Cine.Nui.Send('state', Cine.Session.StatePayload())
    return { ok = true }
end

-- scene set-ups -------------------------------------------------------------------------------------
-- A placed scene is a record in the project (St.SceneAdd) and a tag on every actor / light it
-- added. So it can be removed or filmed as one thing at any time, also after a reload.

--- o = { id = scene record id }: remove that scene's actors and lights.
function P.RemoveScene(o)
    local actors, lights = St.SceneRemove(type(o) == 'table' and S.Id(o.id) or nil)
    if not actors then return { ok = false } end
    Cine.Notify(_L('scene_removed', actors, lights), 'info')
    return { ok = true, actors = actors, lights = lights }
end

--- Remove every actor and light of the project.
function P.ClearStage()
    local actors, lights = St.StageClear()
    if not actors then return { ok = false } end
    Cine.Notify(_L('stage_cleared', actors, lights), 'info')
    return { ok = true, actors = actors, lights = lights }
end

--- o = { id, lights = bool, look = bool, clear = bool }
function P.ApplyScene(o)
    local p, cam = St.project, Cine.Camera.state
    local sc = type(o) == 'table' and CineScene(o.id) or nil
    if not p or not cam or not sc then return { ok = false } end
    local withLights = o.lights ~= false

    if o.clear == true then St.StageClear() end
    local free = Config.Actors.Max - #p.actors
    if #sc.actors > free then
        Cine.Notify(_L('scene_no_room', #sc.actors, free), 'error')
        return { ok = false, reason = 'no_room' }
    end
    if withLights and #sc.lights > Config.Lights.Max - #p.lights then
        Cine.Notify(_L('scene_no_light_room', #sc.lights, Config.Lights.Max - #p.lights), 'error')
        return { ok = false, reason = 'no_room' }
    end

    -- scene centre: the ground the camera looks at when that is close enough, else straight ahead
    local yr = math.rad(cam.rot[3])
    local ox, oy = cam.pos[1] - math.sin(yr) * sc.dist, cam.pos[2] + math.cos(yr) * sc.dist
    local gz = nil
    local hit, hitDist = probe(cam)
    if hit and hitDist <= Config.Presets.SceneMaxDistance then
        ox, oy = hit[1], hit[2]
        gz = Cine.Ground(ox, oy, hit[3] + 1.0) or hit[3]
    end
    gz = gz or Cine.Ground(ox, oy, cam.pos[3] + 20.0) or (cam.pos[3] - 1.5)
    local toWorld, facing = CineSceneFrame({ ox, oy }, cam.rot[3])
    local rec = St.SceneAdd({ preset = sc.id, pos = { ox, oy, gz }, yaw = cam.rot[3] })
    local tag = rec and rec.id or nil

    local raws = {}
    for _, a in ipairs(sc.actors) do
        local wx, wy = toWorld(a.at[1], a.at[2])
        local g = Cine.Ground(wx, wy, gz + 3.0) or gz
        local heading = facing
        if a.kind == 'vehicle' then
            heading = facing + (a.h or 0.0)
        elseif type(a.face) == 'table' then
            local tx, ty = toWorld(a.face[1], a.face[2])
            local _, yaw = M.DirToRot(tx - wx, ty - wy, 0.0)
            heading = yaw
        end
        raws[#raws + 1] = {
            kind = a.kind, model = a.model, name = CineSceneName(a.name, Config.Locale),
            pos = { wx, wy, g + (a.kind == 'vehicle' and 0.8 or 1.0) }, rot = { 0.0, 0.0, heading % 360.0 },
            scenario = a.scenario, anim = a.anim, scene = tag,
        }
    end
    local added = St.ActorsInsert(raws) or {}

    local lights = 0
    if withLights then
        local d = Config.Lights.Defaults
        for _, l in ipairs(sc.lights) do
            local wx, wy = toWorld(l.at[1], l.at[2])
            local wz = gz + l.at[3]
            local rot = { 0.0, 0.0, 0.0 }
            if l.type == 'spot' and l.aim then
                local ax, ay = toWorld(l.aim[1], l.aim[2])
                local pitch, yaw = M.DirToRot(ax - wx, ay - wy, gz + l.aim[3] - wz)
                rot = { pitch, 0.0, yaw }
            end
            local light = St.LightInsert({
                type = l.type, name = CineSceneName(l.name, Config.Locale), pos = { wx, wy, wz }, rot = rot,
                color = l.color, range = l.range, intensity = l.intensity, radius = l.radius or d.radius,
                roundness = d.roundness, falloff = l.falloff or d.falloff, shadow = l.shadow == true, scene = tag,
            })
            if light then lights = lights + 1 end
        end
    end

    if o.look == true and sc.look then P.ApplyLook({ id = sc.look }) end
    local main = added[sc.main or 1] or added[1]
    Cine.Notify(_L('scene_placed', #added, lights), 'success')
    return { ok = true, scene = tag, main = main and main.id or nil, actors = #added, lights = lights }
end

--- Build the camera move that suits a placed scene, from the scene's own camera position: in
--- front of the scene, wherever the user's camera is. o = { scene = record id, name }.
function P.SceneMove(o)
    local rec = type(o) == 'table' and St.GetScene(S.Id(o.scene)) or nil
    local sc = rec and CineScene(rec.preset) or nil
    if not sc or not sc.move or not sc.cam then return { ok = false } end
    local gz = rec.pos[3]
    local toWorld = CineSceneFrame(rec.pos, rec.yaw)
    local c, mo = sc.cam, sc.mo or {}
    local px, py = toWorld(c.at[1], c.at[2])
    local ax, ay = toWorld(c.aim[1], c.aim[2])
    local pz, az = gz + c.at[3], gz + c.aim[3]
    local pitch, yaw = M.DirToRot(ax - px, ay - py, az - pz)
    local res = P.ApplyMove(
        { id = sc.move, mode = 'new', name = o.name, dir = mo.dir, amount = mo.amount, dur = mo.dur },
        { pos = { px, py, pz }, rot = { pitch, 0.0, yaw }, fov = c.fov or 45.0, subject = { ax, ay, az }, ground = gz })
    if res.ok then St.ShotUpdate(res.shotId, { scene = rec.id }) end
    return res
end
