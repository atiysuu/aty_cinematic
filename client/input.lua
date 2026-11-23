-- Input state (cursor / fly / typing / clean) and key mappings.
-- Key mappings fire for every resource that maps the same key, even under DisableAllControlActions,
-- so each handler checks Session.active first and does nothing outside a session.
Cine.Input = { cursor = false, overUi = false, typing = false, clean = false, flyHold = false }
local I = Cine.Input

--- Cursor mode: NUI focus + keep game input (panels clickable, RMB looks). Fly mode: no NUI focus.
function I.SetCursor(on)
    if I.clean then on = false end
    on = on == true
    if I.cursor == on then return end
    I.cursor = on
    if not on then I.overUi = false end
    Cine.Nui.SetFocus(on, on and not I.typing)
    Cine.Nui.Send('state', Cine.Session.StatePayload())
end

--- A text field in the NUI has focus: the game must not receive the keys.
function I.SetTyping(on)
    on = on == true
    if I.typing == on then return end
    I.typing = on
    if I.cursor then Cine.Nui.SetFocus(true, not on) end
end

function I.SetOverUi(over)
    I.overUi = over == true
end

function I.SetClean(on)
    on = on == true
    if I.clean == on then return end
    I.clean = on
    if on then
        Cine.Gizmo.Stop()
        Cine.Placer.Stop(true)
        I.SetCursor(false)
        I.typing = false
    end
    TriggerEvent('aty_cinematic:client:state', Cine.Session.EventPayload())
    Cine.Nui.Send('state', Cine.Session.StatePayload())
    if not on then I.SetCursor(true) end -- panels are back: so is the mouse
end

--- Reset on session open / close.
function I.Reset()
    I.cursor, I.overUi, I.typing, I.clean, I.flyHold = false, false, false, false, false
end

--- Per frame while a session runs.
function I.DisableControls()
    if Cine.Session.rec then
        -- recording a R* clip: DisableAllControlActions would stop the recording (see config)
        for _, c in ipairs(Config.Controls.RecordBlock) do DisableControlAction(0, c, true) end
        return
    end
    DisableAllControlActions(0)
end

--- Hold right mouse (off the panels) = fly: the NUI lets go of the mouse so it steers the camera.
--- Release = back to the cursor. Runs every frame after DisableControls.
function I.Tick()
    local hold = Config.Controls.LookHold
    if I.flyHold then
        if not IsDisabledControlPressed(0, hold) then
            I.flyHold = false
            I.SetCursor(true)
        end
    elseif I.cursor and not I.overUi and not I.typing and IsDisabledControlJustPressed(0, hold) then
        I.flyHold = true
        I.SetCursor(false)
    end
end

local function whenActive(fn)
    return function()
        if not Cine.Session.active or I.typing or Cine.Session.rec then return end
        local ok, err = pcall(fn)
        if not ok then Cine.Err('key handler failed: %s', tostring(err)) end
    end
end

local function register(def, onPress, onRelease)
    Modules.RegisterKeyMapping(def.command, def.label, def.mapper or 'keyboard', def.key, onPress, onRelease)
end

CreateThread(function()
    if not Cine.WaitReady(60000) then return end
    local K = Config.Keys

    register(K.Cursor, whenActive(function()
        if I.clean then return end
        I.SetCursor(not I.cursor)
    end))

    register(K.HideUi, whenActive(function() I.SetClean(not I.clean) end))

    register(K.AddKey, whenActive(function()
        local St, TL = Cine.Store, Cine.Timeline
        if not St.project then Cine.Notify(_L('no_project'), 'error'); return end
        if not St.CurrentShot() and not St.ShotAdd() then return end -- no shot yet: make one, then key it
        St.KeyAdd(St.shotId, { t = TL.t }) -- always at the playhead (falls back to "after the last key")
        Cine.Nui.Send('state', Cine.Session.StatePayload())
    end))

    register(K.Play, whenActive(function() Cine.Session.TogglePlay() end))

    -- Gizmo engine commands: pressed here only (bug-lessons). Release always goes through, typing or not.
    register(K.GizmoSel,
        function() if Cine.Session.active and not I.typing then Cine.Gizmo.OnSelect(true) end end,
        function() Cine.Gizmo.OnSelect(false) end)
    register(K.GizmoMode,
        function() if Cine.Session.active and not I.typing then Cine.Gizmo.OnMode(true) end end,
        function() Cine.Gizmo.OnMode(false) end)
    register(K.GizmoSpace,
        function() if Cine.Session.active and not I.typing then Cine.Gizmo.OnSpace(true) end end,
        function() Cine.Gizmo.OnSpace(false) end)
end)
