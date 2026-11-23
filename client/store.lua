-- Project state: the single source of truth on the client. The Vue stores only render echoes.
-- Every mutation validates through CineSchema (NUI input is untrusted) and calls Touch().
Cine.Store = { project = nil, shotId = nil, dirty = false, rev = 0 }
local St = Cine.Store
local S = CineSchema
local M = CineMath

local pushPending = false
local lastPush = 0
local weatherSet = nil

local function wset()
    weatherSet = weatherSet or CineWeatherSet()
    return weatherSet
end

local function copyArr(a)
    local o = {}
    for i = 1, #a do o[i] = a[i] end
    return o
end

local function shallowCopy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end

local function nextId(prefix, list)
    local max = 0
    for _, item in ipairs(list) do
        local n = tonumber(item.id:sub(#prefix + 1))
        if n and n > max then max = n end
    end
    local id = prefix .. (max + 1)
    return id
end

function St.Touch()
    St.dirty = true
    St.rev = St.rev + 1
    pushPending = true
end

--- Called every frame: pushes the project to the NUI at most every 80 ms after a change.
function St.Flush(now)
    if pushPending and St.project and now - lastPush >= 80 then
        pushPending = false
        lastPush = now
        Cine.Nui.Send('project', St.project)
        Cine.Nui.Send('state', Cine.Session.StatePayload())
    end
end

function St.PushNow()
    pushPending = false
    lastPush = GetGameTimer()
    Cine.Nui.Send('project', St.project or false)
    Cine.Nui.Send('state', Cine.Session.StatePayload())
end

function St.GetShot(id)
    if not St.project then return nil end
    for _, s in ipairs(St.project.shots) do
        if s.id == id then return s end
    end
    return nil
end

function St.CurrentShot()
    return St.shotId and St.GetShot(St.shotId) or nil
end

function St.GetActor(id)
    if not St.project then return nil end
    for _, a in ipairs(St.project.actors) do
        if a.id == id then return a, _ end
    end
    return nil
end

function St.GetLight(id)
    if not St.project then return nil end
    for _, l in ipairs(St.project.lights) do
        if l.id == id then return l end
    end
    return nil
end

local function bumpShot(shot)
    shot.rev = (shot.rev or 0) + 1
end

--- Sort keys, re-unwrap roll / yaw so each key is within +-180 of the previous one (short arc).
local function normalizeShot(shot)
    table.sort(shot.keys, function(a, b) return a.t < b.t end)
    for i = 2, #shot.keys do
        local prev, k = shot.keys[i - 1], shot.keys[i]
        k.rot[2] = M.UnwrapTo(prev.rot[2], k.rot[2])
        k.rot[3] = M.UnwrapTo(prev.rot[3], k.rot[3])
    end
    bumpShot(shot)
end

-- Load / unload -------------------------------------------------------------------------------

function St.Unload()
    Cine.Gizmo.Stop()
    Cine.Timeline.Reset()
    Cine.Actors.DespawnAll()
    St.project, St.shotId, St.dirty = nil, nil, false
    St.PushNow()
end

--- Make a sanitized project document current: respawn actors, select the first shot.
function St.Load(doc)
    Cine.Gizmo.Stop()
    Cine.Timeline.Reset()
    Cine.Actors.DespawnAll()
    for _, shot in ipairs(doc.shots) do shot.rev = 1 end
    St.project = doc
    St.shotId = doc.shots[1] and doc.shots[1].id or nil
    St.dirty = false
    St.rev = St.rev + 1
    if Cine.Rigs.mode ~= 'free' and Cine.Camera.state then
        Cine.Rigs.Set('free', nil, Cine.Camera.state)
    end
    Cine.Actors.SpawnAll(doc.actors)
    if not St.shotId then St.ShotAdd() end -- an empty project starts with one shot, ready for F
    St.PushNow()
end

--- A brand-new local state when no server project is open (never saved).
function St.SetSettings(patch)
    local p = St.project
    if not p or type(patch) ~= 'table' then return false end
    if patch.letterbox ~= nil then p.settings.letterbox = S.Num(patch.letterbox, 0.0, 4.0, p.settings.letterbox) end
    local R = Config.RockstarEditor
    if patch.leadIn ~= nil then p.settings.leadIn = S.Num(patch.leadIn, 0.0, R.MaxLeadIn, p.settings.leadIn or R.LeadIn) end
    if patch.tail ~= nil then p.settings.tail = S.Num(patch.tail, 0.0, R.MaxTail, p.settings.tail or R.Tail) end
    if patch.recSingle ~= nil then p.settings.recSingle = S.Bool(patch.recSingle, R.Single) end
    St.Touch()
    return true
end

-- Shots ---------------------------------------------------------------------------------------

function St.ShotAdd(name)
    local p = St.project
    if not p then return nil end
    if #p.shots >= Config.Timeline.MaxShots then Cine.Notify(_L('max_shots'), 'error'); return nil end
    local shot = { id = nextId('shot_', p.shots), name = S.Name(name, 'Shot ' .. (#p.shots + 1)), loop = false, keys = {}, lights = {}, shake = S.Shake(nil), rev = 1 }
    p.shots[#p.shots + 1] = shot
    St.shotId = shot.id
    St.Touch()
    return shot
end

function St.ShotUpdate(id, patch)
    local shot = St.GetShot(id)
    if not shot or type(patch) ~= 'table' then return false end
    if patch.name ~= nil then shot.name = S.Name(patch.name, shot.name) end
    if patch.loop ~= nil then shot.loop = S.Bool(patch.loop, shot.loop) end
    if patch.scene ~= nil then shot.scene = S.Id(patch.scene) end
    if type(patch.shake) == 'table' then
        local merged = shallowCopy(shot.shake or S.Shake(nil))
        for f, v in pairs(patch.shake) do merged[f] = v end
        shot.shake = S.Shake(merged)
    end
    St.Touch()
    return true
end

function St.ShotDelete(id)
    local p = St.project
    if not p then return false end
    for i, s in ipairs(p.shots) do
        if s.id == id then
            table.remove(p.shots, i)
            -- deleting the camera of a placed scene does not delete the scene: say where that is done
            if s.scene and St.GetScene(s.scene) then Cine.Notify(_L('scene_shot_deleted'), 'info') end
            if St.shotId == id then
                Cine.Timeline.Reset()
                St.shotId = (p.shots[i] or p.shots[i - 1] or {}).id
            end
            St.Touch()
            return true
        end
    end
    return false
end

function St.ShotDuplicate(id)
    local p = St.project
    local shot = St.GetShot(id)
    if not p or not shot then return nil end
    if #p.shots >= Config.Timeline.MaxShots then Cine.Notify(_L('max_shots'), 'error'); return nil end
    local ok, decoded = pcall(json.decode, json.encode(shot))
    if not ok then return nil end
    local copy = S.Shot(decoded, wset(), nil)
    if not copy then return nil end
    copy.id = nextId('shot_', p.shots)
    copy.name = S.Name(shot.name .. ' copy', 'Shot')
    copy.rev = 1
    p.shots[#p.shots + 1] = copy
    St.shotId = copy.id
    St.Touch()
    return copy
end

function St.ShotSelect(id)
    if not St.GetShot(id) then return false end
    if St.shotId ~= id then
        Cine.Timeline.Reset()
        St.shotId = id
    end
    pushPending = true
    return true
end

-- Keys ----------------------------------------------------------------------------------------

local function captureKey(shot, t, withEnv)
    local cam = Cine.Camera.state
    if not cam then return nil end
    local d = cam.dof or {}
    local raw = {
        id = nextId('key_', shot.keys),
        t = t, hold = 0.0,
        pos = copyArr(cam.pos), rot = copyArr(cam.rot), fov = cam.fov,
        dof = { on = d.on == true, near = d.near, far = d.far, str = d.str, target = d.target },
        interp = Config.Timeline.DefaultInterp, ease = Config.Timeline.DefaultEase,
        bez = { 0.42, 0.0, 0.58, 1.0 },
        env = withEnv and Cine.Env.Capture() or nil,
        orbit = (not Cine.Timeline.Active()) and Cine.Rigs.OrbitKey() or nil,
    }
    -- keep the rotation near the previous key (short arc) before sanitizing
    return S.Key(raw, wset(), raw.id)
end

--- Park the playhead (camera stays free) and tell the NUI.
local function headTo(shot, t)
    local TL = Cine.Timeline
    if TL.shotId ~= nil and TL.shotId ~= shot.id then return end
    TL.shotId = shot.id
    TL.SetHead(t)
    Cine.Nui.Send('playhead', { t = TL.t, playing = false })
end

--- Capture the current camera as a NEW key at the playhead. opts = { t?, env? }.
--- F never overwrites: if a key already sits at the playhead the new one goes after the last key.
--- (Changing an existing key is explicit: inspector "Set from camera".)
--- A new key moves the playhead one gap further, so "fly, F, fly, F" lays keys out in a row.
function St.KeyAdd(shotId, opts)
    local shot = St.GetShot(shotId or St.shotId)
    if not shot then return nil end
    opts = opts or {}
    if #shot.keys >= Config.Timeline.MaxKeysPerShot then Cine.Notify(_L('max_keys'), 'error'); return nil end
    local t = tonumber(opts.t)
    if t then
        for _, k in ipairs(shot.keys) do
            if math.abs(k.t - t) < 0.05 then t = nil; break end
        end
    end
    if not t then
        local last = shot.keys[#shot.keys]
        t = last and (last.t + last.hold + Config.Timeline.DefaultKeyGap) or 0.0
    end
    local key = captureKey(shot, M.Clamp(t, 0.0, 36000.0), opts.env == true)
    if not key then return nil end
    shot.keys[#shot.keys + 1] = key
    normalizeShot(shot)
    St.Touch()
    Cine.Rigs.userMoved = false -- the flown pose is now saved in this key
    headTo(shot, key.t + key.hold + Config.Timeline.DefaultKeyGap)
    return key
end

--- Put prepared keys on a shot (ready-made camera moves): sanitized, given ids, sorted.
--- raws = { { t, pos, rot, fov, ease, orbit, dof, shake } }. Returns the keys added, or nil when
--- the shot would go over its key limit.
function St.KeysInsert(shotId, raws)
    local shot = St.GetShot(shotId)
    if not shot or type(raws) ~= 'table' then return nil end
    if #shot.keys + #raws > Config.Timeline.MaxKeysPerShot then Cine.Notify(_L('max_keys'), 'error'); return nil end
    local added = {}
    for _, raw in ipairs(raws) do
        raw.id = nextId('key_', shot.keys)
        local key = S.Key(raw, wset(), raw.id)
        if key then
            shot.keys[#shot.keys + 1] = key
            added[#added + 1] = key
        end
    end
    normalizeShot(shot)
    St.Touch()
    return added
end

local function findKey(shot, keyId)
    for i, k in ipairs(shot.keys) do
        if k.id == keyId then return k, i end
    end
    return nil
end

function St.GetKey(shotId, keyId)
    local shot = St.GetShot(shotId)
    if not shot then return nil end
    return (findKey(shot, keyId))
end

function St.KeyUpdate(shotId, keyId, patch)
    local shot = St.GetShot(shotId)
    if not shot or type(patch) ~= 'table' then return false end
    local k, idx = findKey(shot, keyId)
    if not k then return false end
    local raw = shallowCopy(k)
    raw.dof = shallowCopy(k.dof)
    raw.env = k.env and shallowCopy(k.env) or nil
    if patch.t ~= nil then raw.t = patch.t end
    if patch.hold ~= nil then raw.hold = patch.hold end
    if patch.interp ~= nil then raw.interp = patch.interp end
    if patch.ease ~= nil then raw.ease = patch.ease end
    if type(patch.bez) == 'table' then raw.bez = patch.bez end
    if patch.fov ~= nil then raw.fov = patch.fov end
    if type(patch.pos) == 'table' then raw.pos = patch.pos end
    if type(patch.rot) == 'table' then raw.rot = patch.rot end
    if type(patch.dof) == 'table' then
        for f, v in pairs(patch.dof) do raw.dof[f] = v end
        if patch.dof.target == false or patch.dof.target == '' then raw.dof.target = nil end
    end
    if type(patch.env) == 'table' then
        raw.env = raw.env or {}
        for f, v in pairs(patch.env) do raw.env[f] = v end
    end
    if type(patch.envClear) == 'table' then
        if raw.env then
            for _, f in ipairs(patch.envClear) do if type(f) == 'string' then raw.env[f] = nil end end
        end
    end
    if patch.envClearAll == true then raw.env = nil end
    if type(patch.shake) == 'table' then
        -- start from this key's own shake, else what it inherits now (the shot default)
        local merged = shallowCopy(raw.shake or shot.shake or {})
        for f, v in pairs(patch.shake) do merged[f] = v end
        raw.shake = merged
    end
    if patch.shakeClear == true then raw.shake = nil end
    if patch.orbit ~= nil then raw.orbit = patch.orbit or nil end
    local clean = S.Key(raw, wset(), k.id)
    if not clean then return false end
    shot.keys[idx] = clean
    normalizeShot(shot)
    St.Touch()
    return true
end

function St.KeyDelete(shotId, keyId)
    local shot = St.GetShot(shotId)
    if not shot then return false end
    local _, idx = findKey(shot, keyId)
    if not idx then return false end
    table.remove(shot.keys, idx)
    bumpShot(shot)
    St.Touch()
    return true
end

--- Overwrite a key's camera values from the live camera.
function St.KeyFromCamera(shotId, keyId)
    local shot = St.GetShot(shotId)
    local cam = Cine.Camera.state
    if not shot or not cam then return false end
    local k = findKey(shot, keyId)
    if not k then return false end
    return St.KeyUpdate(shotId, keyId, {
        pos = copyArr(cam.pos), rot = copyArr(cam.rot), fov = cam.fov,
        dof = { on = cam.dof.on == true, near = cam.dof.near, far = cam.dof.far, str = cam.dof.str, target = cam.dof.target or false },
        orbit = (not Cine.Timeline.Active()) and Cine.Rigs.OrbitKey() or false,
    })
end

-- Actors --------------------------------------------------------------------------------------

--- A position in front of the camera on the ground. lift = height of the entity centre above ground.
local function frontOfCamera(dist, lift)
    local cam = Cine.Camera.state
    local fx, fy = M.Basis(cam.rot[1], cam.rot[3])
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 0.001 then fx, fy, len = 0.0, 1.0, 1.0 end
    local x, y = cam.pos[1] + fx / len * dist, cam.pos[2] + fy / len * dist
    local gz = Cine.Ground(x, y, cam.pos[3] + 20.0)
    return { x, y, (gz or (cam.pos[3] - 1.5)) + lift }
end

function St.ActorAdd(args)
    local p = St.project
    if not p or type(args) ~= 'table' then return nil end
    if #p.actors >= Config.Actors.Max then Cine.Notify(_L('max_actors'), 'error'); return nil end
    local kind = args.kind
    local cam = Cine.Camera.state
    local lift = kind == 'vehicle' and 0.8 or 1.0
    local raw = {
        id = nextId('act_', p.actors), kind = kind, model = args.model,
        pos = frontOfCamera(6.0, lift),
        rot = { 0.0, 0.0, (cam.rot[3] + 180.0) % 360.0 },
    }
    if kind == 'vehicle' and args.useMyCar == true then
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= 0 and DoesEntityExist(veh) then
            raw.model = GetDisplayNameFromVehicleModel(GetEntityModel(veh)):lower()
            local ok, props = pcall(Modules.GetVehicleProperties, veh)
            if ok then raw.props = props end
        end
    end
    local a = S.Actor(raw, raw.id)
    if not a then Cine.Notify(_L('model_failed', tostring(args.model or kind)), 'error'); return nil end
    p.actors[#p.actors + 1] = a
    St.Touch()
    CreateThread(function()
        local ok, err = pcall(Cine.Actors.Spawn, a, true)
        if not ok then Cine.Err('actor spawn failed: %s', tostring(err)) end
    end)
    return a
end

--- Add prepared actors (ready-made scenes): { kind, model, name, pos, rot, anim, scenario }.
--- Returns the actors added; they spawn one after another (vehicles settle on the ground).
function St.ActorsInsert(raws)
    local p = St.project
    if not p or type(raws) ~= 'table' then return nil end
    local added = {}
    for _, raw in ipairs(raws) do
        if #p.actors >= Config.Actors.Max then break end
        raw.id = nextId('act_', p.actors)
        local a = S.Actor(raw, raw.id)
        if a then
            p.actors[#p.actors + 1] = a
            added[#added + 1] = a
        end
    end
    if #added == 0 then return added end
    St.Touch()
    local token = Cine.Session.token
    CreateThread(function()
        for _, a in ipairs(added) do
            if Cine.Session.token ~= token then return end
            if (St.GetActor(a.id)) ~= a then goto continue end -- removed again before its turn came
            local ok, err = pcall(Cine.Actors.Spawn, a, true)
            if not ok then Cine.Err('actor spawn failed: %s', tostring(err)) end
            ::continue::
        end
    end)
    return added
end

function St.ActorUpdate(id, patch)
    local a = St.GetActor(id)
    if not a or type(patch) ~= 'table' then return false end
    if patch.name ~= nil then a.name = S.Name(patch.name, a.name) end
    if type(patch.pos) == 'table' then a.pos = S.Vec3(patch.pos, a.pos) end
    if type(patch.rot) == 'table' then a.rot = S.Vec3(patch.rot, a.rot) end
    local e = Cine.Actors.GetEntity(id)
    if e and (patch.pos or patch.rot) then Cine.Actors.Place(a, e) end
    St.Touch()
    return true
end

--- An actor stops being half of a two-person emote: its partner stops too (it would be shaking
--- hands with nobody).
local function unpair(a)
    local partner = a.pair and St.GetActor(a.pair) or nil
    a.pair = nil
    if not partner or partner.pair ~= a.id then return end
    partner.pair, partner.anim = nil, nil
    local e = Cine.Actors.GetEntity(partner.id)
    if e then
        FreezeEntityPosition(e, false)
        ClearPedTasksImmediately(e)
        Cine.Actors.Place(partner, e)
        FreezeEntityPosition(e, true)
    end
end

--- Two-person emote for two ped actors: the first stays where it is, the second steps in front
--- of it, face to face, `gap` metres away, and both start their half in the same frame.
--- item = { a = { dict, name, flag }, b = { dict, name, flag } }. Returns ok.
function St.ActorsPair(idA, idB, item, gap)
    local a, b = St.GetActor(idA), St.GetActor(idB)
    if not a or not b or a == b or a.kind == 'vehicle' or b.kind == 'vehicle' or type(item) ~= 'table' then return false end
    local function clip(raw)
        if type(raw) ~= 'table' then return nil end
        local dict, name = S.Ident(raw.dict, 80), S.Ident(raw.name, 80)
        if not dict or not name then return nil end
        return { dict = dict, name = name, flag = math.floor(S.Num(raw.flag, 0, 65535, 0)) }
    end
    local ca, cb = clip(item.a), clip(item.b)
    if not ca or not cb then return false end
    unpair(a)
    unpair(b)
    a.anim, a.scenario, a.pair = ca, nil, b.id
    b.anim, b.scenario, b.pair = cb, nil, a.id
    gap = S.Num(gap, 0.3, 3.0, 1.0)
    local hr = math.rad(a.rot[3])
    local x, y = a.pos[1] - math.sin(hr) * gap, a.pos[2] + math.cos(hr) * gap
    local feet = a.pos[3] - 1.0
    a.rot = { 0.0, 0.0, a.rot[3] }
    b.pos = { x, y, (Cine.Ground(x, y, feet + 1.5) or feet) + 1.0 }
    b.rot = { 0.0, 0.0, (a.rot[3] + 180.0) % 360.0 }
    St.Touch()
    CreateThread(function()
        local ok, err = pcall(Cine.Actors.PlayPair, a, b)
        if not ok then Cine.Err('two-person emote failed: %s', tostring(err)) end
    end)
    return true
end

--- Set / clear the animation or scenario of a ped actor. args = { dict, name, flag } or { scenario } or {} (clear).
function St.ActorAnim(id, args)
    local a = St.GetActor(id)
    if not a or a.kind == 'vehicle' then return false end
    args = type(args) == 'table' and args or {}
    unpair(a)
    a.anim, a.scenario = nil, nil
    if args.scenario ~= nil then
        a.scenario = (type(args.scenario) == 'string') and S.Ident(args.scenario, 64) or nil
    elseif args.dict ~= nil then
        local dict, name = S.Ident(args.dict, 80), S.Ident(args.name, 80)
        if dict and name then
            a.anim = { dict = dict, name = name, flag = math.floor(S.Num(args.flag, 0, 65535, 1)) }
        end
    end
    St.Touch()
    CreateThread(function()
        local e = Cine.Actors.GetEntity(id)
        if not e then return end
        if a.anim or a.scenario then
            Cine.Actors.PlayAnim(a)
        else
            FreezeEntityPosition(e, false)
            ClearPedTasksImmediately(e)
            Cine.Actors.Place(a, e)
            FreezeEntityPosition(e, true)
        end
    end)
    return true
end

function St.ActorDelete(id)
    local p = St.project
    if not p then return false end
    for i, a in ipairs(p.actors) do
        if a.id == id then
            if Cine.Gizmo.id == id then Cine.Gizmo.Stop() end
            if Cine.Placer.id == id then Cine.Placer.Stop(true) end
            unpair(a)
            if Cine.Rigs.target == id and Cine.Rigs.mode ~= 'free' and Cine.Camera.state then
                Cine.Rigs.Set('free', nil, Cine.Camera.state)
            end
            Cine.Actors.Remove(id)
            table.remove(p.actors, i)
            St.Touch()
            return true
        end
    end
    return false
end

function St.ActorDropAtCamera(id)
    local a = St.GetActor(id)
    if not a then return false end
    a.pos = frontOfCamera(6.0, a.kind == 'vehicle' and 0.8 or 1.0)
    local e = Cine.Actors.GetEntity(id)
    if e then
        Cine.Actors.Place(a, e)
        if a.kind == 'vehicle' then
            FreezeEntityPosition(e, false)
            SetVehicleOnGroundProperly(e)
            FreezeEntityPosition(e, true)
            local c = GetEntityCoords(e)
            a.pos = { c.x, c.y, c.z }
        end
    end
    St.Touch()
    return true
end

--- From the gizmo (once per frame while dragging).
function St.ActorTransform(id, pos, rot)
    local a = St.GetActor(id)
    if not a then return end
    a.pos, a.rot = pos, rot
    St.Touch()
end

-- Lights --------------------------------------------------------------------------------------

function St.LightAdd(ltype)
    local p = St.project
    if not p then return nil end
    if #p.lights >= Config.Lights.Max then Cine.Notify(_L('max_lights'), 'error'); return nil end
    local cam = Cine.Camera.state
    local fx, fy, fz = M.Basis(cam.rot[1], cam.rot[3])
    local d = Config.Lights.Defaults
    local raw = {
        id = nextId('lgt_', p.lights), type = ltype == 'spot' and 'spot' or 'point',
        pos = { cam.pos[1] + fx * 3.0, cam.pos[2] + fy * 3.0, cam.pos[3] + fz * 3.0 },
        rot = { ltype == 'spot' and -90.0 or 0.0, 0.0, cam.rot[3] },
        color = d.color, range = d.range, intensity = d.intensity, radius = d.radius,
        roundness = d.roundness, falloff = d.falloff, shadow = d.shadow,
    }
    local l = S.Light(raw, raw.id)
    p.lights[#p.lights + 1] = l
    St.Touch()
    return l
end

--- Add a prepared light (ready-made scenes). Returns the light or nil.
function St.LightInsert(raw)
    local p = St.project
    if not p or type(raw) ~= 'table' or #p.lights >= Config.Lights.Max then return nil end
    raw.id = nextId('lgt_', p.lights)
    local l = S.Light(raw, raw.id)
    if not l then return nil end
    p.lights[#p.lights + 1] = l
    St.Touch()
    return l
end

function St.LightUpdate(id, patch)
    local p = St.project
    local l = St.GetLight(id)
    if not l or type(patch) ~= 'table' then return false end
    local raw = shallowCopy(l)
    for _, f in ipairs({ 'name', 'type', 'pos', 'rot', 'color', 'range', 'intensity', 'radius', 'roundness', 'falloff', 'shadow' }) do
        if patch[f] ~= nil then raw[f] = patch[f] end
    end
    local clean = S.Light(raw, l.id)
    if not clean then return false end
    for i, item in ipairs(p.lights) do
        if item.id == id then p.lights[i] = clean break end
    end
    St.Touch()
    return true
end

function St.LightDelete(id)
    local p = St.project
    if not p then return false end
    for i, l in ipairs(p.lights) do
        if l.id == id then
            if Cine.Gizmo.id == id then Cine.Gizmo.Stop() end
            table.remove(p.lights, i)
            for _, s in ipairs(p.shots) do s.lights[id] = nil end
            St.Touch()
            return true
        end
    end
    return false
end

function St.LightTransform(id, pos, rot)
    local l = St.GetLight(id)
    if not l then return end
    l.pos, l.rot = pos, rot
    St.Touch()
end

-- Placed scenes --------------------------------------------------------------------------------

function St.GetScene(id)
    if not St.project or not id then return nil end
    for i, s in ipairs(St.project.scenes) do
        if s.id == id then return s, i end
    end
    return nil
end

--- Remember a placed scene: { preset, pos = { x, y, ground z }, yaw }. Returns the record or nil.
function St.SceneAdd(raw)
    local p = St.project
    if not p or type(raw) ~= 'table' or #p.scenes >= Config.Presets.MaxScenes then return nil end
    raw.id = nextId('scn_', p.scenes)
    local s = S.Scene(raw, raw.id)
    if not s then return nil end
    p.scenes[#p.scenes + 1] = s
    St.Touch()
    return s
end

--- Remove a placed scene: its record and every actor and light it added. Its camera shots stay
--- (they may have been edited). Returns actors removed, lights removed, or nil.
function St.SceneRemove(id)
    local p = St.project
    local _, index = St.GetScene(id)
    if not p or not index then return nil end
    local ids = {}
    for _, a in ipairs(p.actors) do if a.scene == id then ids[#ids + 1] = a.id end end
    for _, aid in ipairs(ids) do St.ActorDelete(aid) end
    local actors = #ids
    ids = {}
    for _, l in ipairs(p.lights) do if l.scene == id then ids[#ids + 1] = l.id end end
    for _, lid in ipairs(ids) do St.LightDelete(lid) end
    for _, s in ipairs(p.shots) do if s.scene == id then s.scene = nil end end
    table.remove(p.scenes, index)
    St.Touch()
    return actors, #ids
end

--- Remove every actor and light of the project (placed by a scene or by hand) and every scene record.
function St.StageClear()
    local p = St.project
    if not p then return nil end
    local ids = {}
    for _, a in ipairs(p.actors) do ids[#ids + 1] = a.id end
    for _, aid in ipairs(ids) do St.ActorDelete(aid) end
    local actors = #ids
    ids = {}
    for _, l in ipairs(p.lights) do ids[#ids + 1] = l.id end
    for _, lid in ipairs(ids) do St.LightDelete(lid) end
    for _, s in ipairs(p.shots) do s.scene = nil end
    p.scenes = {}
    St.Touch()
    return actors, #ids
end

--- Enable / disable a light for one shot (missing = enabled).
function St.LightShot(shotId, lightId, on)
    local shot = St.GetShot(shotId)
    if not shot or not St.GetLight(lightId) then return false end
    if on == false then shot.lights[lightId] = false else shot.lights[lightId] = nil end
    St.Touch()
    return true
end
