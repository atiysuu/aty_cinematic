-- The ONLY file that calls SendNUIMessage / RegisterNUICallback / SetNuiFocus.
-- Lua owns the project; the NUI renders echoes. Every callback validates its input (the NUI is untrusted).
Cine.Nui = {}
local N = Cine.Nui
local S -- Cine.Session, resolved lazily (loaded later)

function N.Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

function N.SetFocus(has, keepInput)
    SetNuiFocus(has == true, has == true)
    SetNuiFocusKeepInput(keepInput == true)
end

--- Register a callback: pcall + { ok = false } on error. needsSession = the director must be open.
local function cb(name, needsSession, fn)
    RegisterNUICallback(name, function(data, respond)
        if type(data) ~= 'table' then data = {} end
        if needsSession and not Cine.Session.active then
            respond({ ok = false, reason = 'inactive' })
            return
        end
        local ok, res = pcall(fn, data)
        if not ok then
            Cine.Err('NUI callback %s failed: %s', name, tostring(res))
            respond({ ok = false, reason = 'error' })
            return
        end
        if res == nil then res = { ok = true } elseif res == true then res = { ok = true } elseif res == false then res = { ok = false } end
        respond(res)
    end)
end

local function str(v, max) return CineSchema.Str(v, max or 64, nil) end

-- Session ------------------------------------------------------------------------------------------

cb('nuiReady', false, function()
    S = Cine.Session
    if S.active and S.acked then
        -- the page reloaded under a running session: it lost its state, end the session cleanly
        CreateThread(function() S.Close('nui_reload') end)
    end
    return true
end)

cb('sessionAck', true, function()
    Cine.Session.Ack()
    return true
end)

cb('close', true, function()
    CreateThread(function() Cine.Session.Close('ui') end)
    return true
end)

cb('setCursor', true, function(d) Cine.Input.SetCursor(d.on == true); return true end)
cb('setClean', true, function(d) Cine.Input.SetClean(d.on == true); return true end)
cb('inputFocus', true, function(d) Cine.Input.SetTyping(d.on == true); return true end)
cb('pointerOver', true, function(d) Cine.Input.SetOverUi(d.over == true); return true end)

cb('setRig', true, function(d)
    local rig = d.rig
    if rig ~= 'free' and rig ~= 'orbit' and rig ~= 'follow' then return { ok = false, reason = 'bad_rig' } end
    local ok, why = Cine.Session.SetRig(rig, CineSchema.Id(d.target))
    if not ok and why == 'need_actor' then Cine.Notify(_L('need_actor'), 'error') end
    return { ok = ok == true, reason = why }
end)

cb('orbitSet', true, function(d)
    local cfg, num = Config.Rigs.Orbit, CineSchema.Num
    local p = {}
    if d.dist ~= nil then p.dist = num(d.dist, cfg.MinDistance, cfg.MaxDistance, cfg.Distance) end
    if d.lift ~= nil then p.lift = num(d.lift, cfg.MinLift, cfg.MaxLift, 0.0) end
    if d.spin ~= nil then p.spin = num(d.spin, -cfg.MaxSpin, cfg.MaxSpin, 0.0) end
    Cine.Rigs.SetOrbit(p)
    return true
end)

cb('camSet', true, function(d)
    local S2 = Cine.Session
    S2.ReleaseToRig()
    local cfg, num = Config.Freecam, CineSchema.Num
    if d.speed ~= nil then Cine.Freecam.SetSpeed(num(d.speed, cfg.MinSpeed, cfg.MaxSpeed, cfg.Speed)) end
    if d.smoothing ~= nil then Cine.Freecam.SetSmoothing(num(d.smoothing, 0.0, 1.0, cfg.LookSmoothing)) end
    if d.inertia ~= nil then Cine.Freecam.SetInertia(num(d.inertia, 0.0, 1.0, cfg.Inertia)) end
    if d.pathViz ~= nil then Cine.PathViz.enabled = d.pathViz == true end
    if d.fov ~= nil then Cine.Rigs.SetFov(num(d.fov, cfg.FovMin, cfg.FovMax, cfg.Fov)) end
    if d.resetRoll == true then Cine.Rigs.ResetRoll() end
    if type(d.dof) == 'table' then
        local dd, dof = d.dof, S2.dof
        if dd.on ~= nil then dof.on = CineSchema.Bool(dd.on, dof.on) end
        if dd.near ~= nil then dof.near = num(dd.near, 0.0, 1000.0, dof.near) end
        if dd.far ~= nil then dof.far = num(dd.far, 0.0, 5000.0, dof.far) end
        if dd.str ~= nil then dof.str = num(dd.str, 0.0, 1.0, dof.str) end
        if dd.target ~= nil then dof.target = CineSchema.Id(dd.target) end -- false / '' clears
    end
    Cine.Nui.Send('state', S2.StatePayload())
    return true
end)

-- Shots / keys --------------------------------------------------------------------------------------

local St = Cine.Store

cb('shotAdd', true, function(d) return { ok = St.ShotAdd(str(d.name, 48)) ~= nil } end)
cb('shotUpdate', true, function(d) return { ok = St.ShotUpdate(str(d.id), d.patch) } end)
cb('shotDelete', true, function(d) return { ok = St.ShotDelete(str(d.id)) } end)
cb('shotDuplicate', true, function(d) return { ok = St.ShotDuplicate(str(d.id)) ~= nil } end)
cb('shotSelect', true, function(d)
    local ok = St.ShotSelect(str(d.id))
    St.PushNow()
    return { ok = ok }
end)

cb('keyAdd', true, function(d)
    local key = St.KeyAdd(str(d.shotId), { t = d.t, env = d.env == true })
    return { ok = key ~= nil, id = key and key.id }
end)
cb('keyUpdate', true, function(d) return { ok = St.KeyUpdate(str(d.shotId), str(d.keyId), d.patch) } end)
cb('keyDelete', true, function(d) return { ok = St.KeyDelete(str(d.shotId), str(d.keyId)) } end)
-- Drop every key's own shake so the shot default applies everywhere again.
cb('keysClearShake', true, function(d)
    local shot = St.GetShot(str(d.shotId))
    if not shot then return { ok = false } end
    local ids = {}
    for _, k in ipairs(shot.keys) do if k.shake then ids[#ids + 1] = k.id end end
    for _, id in ipairs(ids) do St.KeyUpdate(shot.id, id, { shakeClear = true }) end
    return { ok = true, cleared = #ids }
end)
-- Copy one key's motion settings (interp / ease / bezier) to every key of the shot.
cb('keysApplyMotion', true, function(d)
    local shot = St.GetShot(str(d.shotId))
    local src = shot and St.GetKey(shot.id, str(d.keyId))
    if not src then return { ok = false } end
    local ids = {}
    for _, k in ipairs(shot.keys) do ids[#ids + 1] = k.id end
    for _, id in ipairs(ids) do
        St.KeyUpdate(shot.id, id, { interp = src.interp, ease = src.ease, bez = src.bez })
    end
    return true
end)
cb('keyFromCamera', true, function(d)
    local ok = St.KeyFromCamera(str(d.shotId), str(d.keyId))
    if ok then
        Cine.Rigs.userMoved = false
        Cine.Notify(_L('key_updated'), 'success')
    end
    return { ok = ok }
end)
cb('keyGoto', true, function(d)
    local shot = St.GetShot(str(d.shotId))
    local key = shot and St.GetKey(shot.id, str(d.keyId))
    if not key then return { ok = false } end
    St.ShotSelect(shot.id)
    Cine.Gizmo.Stop()
    if Cine.Timeline.playing then Cine.Timeline.Pause() end
    Cine.Timeline.Seek(shot, key.t)
    -- a lone key gives the shot no length, so the timeline will not hold the camera: put it there
    if not Cine.Timeline.Active() then Cine.Session.ParkAt(shot, key.t) end
    Cine.Nui.Send('playhead', { t = key.t, playing = false })
    Cine.Nui.Send('state', Cine.Session.StatePayload())
    return true
end)

-- Playback ------------------------------------------------------------------------------------------

cb('play', true, function(d)
    local ok = Cine.Session.Play(str(d.shotId), tonumber(d.from), d.loop)
    Cine.Nui.Send('state', Cine.Session.StatePayload())
    return { ok = ok == true }
end)
cb('recordShot', true, function()
    return { ok = Cine.Session.Record(false) == true }
end)
cb('recordAll', true, function()
    return { ok = Cine.Session.Record(true) == true }
end)
cb('pause', true, function()
    Cine.Timeline.Pause()
    Cine.Nui.Send('state', Cine.Session.StatePayload())
    return true
end)
cb('stop', true, function()
    Cine.Session.Stop()
    return true
end)
cb('scrub', true, function(d)
    local shot = St.CurrentShot()
    if not shot then return { ok = false } end
    Cine.Gizmo.Stop()
    local wasHeld = Cine.Timeline.scrub
    Cine.Timeline.Seek(shot, tonumber(d.t) or 0.0)
    if wasHeld then Cine.Rigs.userMoved = false end -- the camera showed the timeline, not a flown pose
    if not Cine.Timeline.Active() then Cine.Session.ParkAtEnd(shot) end
    Cine.Nui.Send('playhead', { t = Cine.Timeline.t, playing = Cine.Timeline.playing })
    return true
end)

-- Environment ---------------------------------------------------------------------------------------

cb('envSet', true, function(d)
    local live = Cine.Env.live
    Cine.Session.ReleaseToRig()
    if type(d.clear) == 'table' then
        for _, f in ipairs(d.clear) do if type(f) == 'string' then live[f] = nil end end
    end
    if type(d.patch) == 'table' then
        local clean = CineSchema.Env(d.patch, (CineWeatherSet()))
        if clean then for f, v in pairs(clean) do live[f] = v end end
    end
    Cine.Nui.Send('env', live)
    return true
end)

-- Actors / lights -----------------------------------------------------------------------------------

cb('actorAdd', true, function(d)
    local kind = d.kind
    if kind ~= 'ped' and kind ~= 'vehicle' and kind ~= 'clone' then return { ok = false } end
    local a = St.ActorAdd({ kind = kind, model = str(d.model, 64), useMyCar = d.useMyCar == true })
    if a then
        -- a new actor goes straight onto the mouse: point, turn with the wheel, click to drop
        Cine.Session.ReleaseToRig()
        if Cine.Placer.Start(a.id) then Cine.Notify(_L('placer_start'), 'info') end
    end
    return { ok = a ~= nil, id = a and a.id }
end)
cb('actorUpdate', true, function(d) return { ok = St.ActorUpdate(str(d.id), d.patch) } end)
--- Ids from the NUI: an array (or one id), sanitized and capped.
local function idList(v)
    if type(v) ~= 'table' then v = { v } end
    local out = {}
    for i = 1, math.min(#v, Config.Actors.Max) do
        local id = CineSchema.Id(v[i])
        if id then out[#out + 1] = id end
    end
    return out
end

cb('actorSelect', true, function(d) Cine.Actors.selected = idList(d.ids); return true end)
cb('actorsDelete', true, function(d)
    local n = 0
    for _, id in ipairs(idList(d.ids)) do
        if St.ActorDelete(id) then n = n + 1 end
    end
    return { ok = n > 0, removed = n }
end)
--- Animation / scenario for several actors at once. d.items = { { kind, dict, name, flag } }: one
--- item = the same for everyone, several = dealt out in turn (a crowd that does not move in step).
--- d.clear = true stops them.
cb('actorsAnim', true, function(d)
    local ids = idList(d.ids)
    local items = type(d.items) == 'table' and d.items or {}
    local n = 0
    for i, id in ipairs(ids) do
        local args = {}
        local it = d.clear ~= true and items[(i - 1) % math.max(#items, 1) + 1] or nil
        if type(it) == 'table' then
            if it.kind == 'scenario' then args = { scenario = it.name } else args = { dict = it.dict, name = it.name, flag = it.flag } end
        end
        if (d.clear == true or type(it) == 'table') and St.ActorAnim(id, args) then n = n + 1 end
    end
    return { ok = n > 0, applied = n }
end)
cb('actorDelete', true, function(d) return { ok = St.ActorDelete(str(d.id)) } end)
cb('actorDropAtCamera', true, function(d) return { ok = St.ActorDropAtCamera(str(d.id)) } end)
cb('actorAnim', true, function(d)
    return { ok = St.ActorAnim(str(d.id), { dict = d.dict, name = d.name, flag = d.flag }) }
end)
cb('actorScenario', true, function(d)
    return { ok = St.ActorAnim(str(d.id), { scenario = d.name or false }) }
end)
cb('actorPlace', true, function(d)
    local id = str(d.id)
    if Cine.Gizmo.active and Cine.Gizmo.id == id then Cine.Gizmo.Stop(); return true end
    if not St.GetActor(id) then return { ok = false } end
    Cine.Session.ReleaseToRig()
    Cine.Placer.Stop(true)
    return { ok = Cine.Gizmo.Start('actor', id) }
end)
--- Two-person emote (lists/shared.json) for exactly two peds. d = { ids = { first, second }, id,
--- scale = distance factor }. The clips come from the list, never from the NUI.
cb('actorsPair', true, function(d)
    local ids = idList(d.ids)
    local id = str(d.id, 40)
    local item = nil
    for _, it in ipairs(Cine.List('shared')) do
        if type(it) == 'table' and it.id == id then item = it; break end
    end
    if #ids ~= 2 or not item then return { ok = false } end
    local scale = CineSchema.Num(d.scale, 0.5, 2.0, 1.0)
    return { ok = St.ActorsPair(ids[1], ids[2], item, (tonumber(item.gap) or 1.0) * scale) }
end)
cb('actorDrop', true, function(d)
    local ids = idList(d.ids or d.id)
    if #ids == 0 then return { ok = false } end
    Cine.Session.ReleaseToRig()
    return { ok = Cine.Placer.Start(ids) }
end)
cb('placerStop', true, function(d) Cine.Placer.Stop(d.keep ~= false); return true end)

cb('lightAdd', true, function(d)
    local l = St.LightAdd(d.type)
    return { ok = l ~= nil, id = l and l.id }
end)
cb('lightUpdate', true, function(d) return { ok = St.LightUpdate(str(d.id), d.patch) } end)
cb('lightDelete', true, function(d) return { ok = St.LightDelete(str(d.id)) } end)
cb('lightShot', true, function(d) return { ok = St.LightShot(str(d.shotId), str(d.id), d.on ~= false) } end)
cb('lightPlace', true, function(d)
    local id = str(d.id)
    if Cine.Gizmo.active and Cine.Gizmo.id == id then Cine.Gizmo.Stop(); return true end
    if not St.GetLight(id) then return { ok = false } end
    Cine.Session.ReleaseToRig()
    return { ok = Cine.Gizmo.Start('light', id) }
end)

cb('gizmoStop', true, function() Cine.Gizmo.Stop(); return true end)

-- Ready-made moves / atmospheres / scenes (validated inside Cine.Presets) ----------------------------

cb('moveApply', true, function(d) return Cine.Presets.ApplyMove(d) end)
cb('lookApply', true, function(d) return Cine.Presets.ApplyLook(d) end)
cb('sceneApply', true, function(d) return Cine.Presets.ApplyScene(d) end)
cb('sceneRemove', true, function(d) return Cine.Presets.RemoveScene(d) end)
cb('stageClear', true, function() return Cine.Presets.ClearStage() end)
cb('sceneMove', true, function(d) return Cine.Presets.SceneMove(d) end)

cb('settingsSet', true, function(d) return { ok = St.SetSettings(d) } end)

-- Projects ------------------------------------------------------------------------------------------

cb('projectsList', true, function()
    local res = Cine.Persist.List()
    if res.ok then Cine.Nui.Send('projects', res.projects or {}) end
    return { ok = res.ok == true, projects = res.projects }
end)
cb('projectNew', true, function(d)
    local res = Cine.Persist.Create(str(d.name, 48) or 'Untitled')
    if res.ok then Cine.Nui.Send('projects', res.projects or {}) end
    return { ok = res.ok == true, reason = res.reason }
end)
cb('projectOpen', true, function(d)
    local id = CineSchema.Id(str(d.id))
    if not id then return { ok = false, reason = 'bad_id' } end
    local res = Cine.Persist.Load(id)
    return { ok = res.ok == true, reason = res.reason }
end)
cb('projectSave', true, function()
    return { ok = Cine.Persist.Save(false) == true }
end)
cb('projectRename', true, function(d)
    local res = Cine.Persist.Rename(str(d.id), str(d.name, 48))
    if res.ok then
        if St.project and St.project.id == d.id then
            St.project.name = CineSchema.Name(d.name, St.project.name)
            St.PushNow()
        end
        Cine.Nui.Send('projects', res.projects or {})
    end
    return { ok = res.ok == true, reason = res.reason }
end)
cb('projectDuplicate', true, function(d)
    local res = Cine.Persist.Duplicate(str(d.id), str(d.name, 48))
    if res.ok then Cine.Nui.Send('projects', res.projects or {}) end
    return { ok = res.ok == true, reason = res.reason }
end)
cb('projectDelete', true, function(d)
    local res = Cine.Persist.Delete(str(d.id))
    if res.ok then Cine.Nui.Send('projects', res.projects or {}) end
    return { ok = res.ok == true, reason = res.reason }
end)

-- Lookups / notifications ----------------------------------------------------------------------------

local LOOKUP = { ped = 'peds', vehicle = 'vehicles', timecycle = 'timecycles', anim = 'anims', shared = 'shared' }

cb('lookup', true, function(d)
    local file = LOOKUP[d.kind]
    if not file then return { ok = false } end
    local q = (str(d.q, 40) or ''):lower() -- length-capped before any pattern
    local list = Cine.List(file)
    local items = {}
    for i = 1, #list do
        local entry = list[i]
        -- entries with a label per language (label_tr) are sent with the one for Config.Locale
        local tabled = type(entry) == 'table'
        local label = tabled and (entry['label_' .. Config.Locale] or entry.label) or nil
        local hay = tabled and ((label or '') .. ' ' .. (entry.name or '')) or entry
        if q == '' or hay:lower():find(q, 1, true) then
            local item = entry
            if tabled then
                item = {}
                for k, v in pairs(entry) do if k:sub(1, 6) ~= 'label_' then item[k] = v end end
                item.label = label
            end
            items[#items + 1] = item
            if #items >= (d.kind == 'anim' and 300 or 50) then break end
        end
    end
    return { ok = true, items = items }
end)

cb('notify', true, function(d)
    local kind = d.type
    if kind ~= 'success' and kind ~= 'error' and kind ~= 'info' then kind = 'info' end
    Cine.Notify(str(d.message, 120) or '', kind)
    return true
end)
