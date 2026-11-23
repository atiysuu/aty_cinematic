Config = {}

Config.Debug = false
Config.Locale = 'en' -- 'tr' | 'en' (UI + notifications)

-- Access -------------------------------------------------------------------------------------
Config.Access = {
    Ace = false,                    -- false = no permission check (anyone on the server can use it) | 'aty_cinematic.use' = ACE object checked on every call
    FrameworkLevels = false,        -- false | string[] : optional fallback via Modules.HasPermission (e.g. { 'god' })
    Command = 'director',           -- client command that toggles the session
}

-- Session ------------------------------------------------------------------------------------
Config.Session = {
    HidePlayer = true,
    FreezePlayer = true,
    StartWithCursor = true,         -- open with NUI focus (mouse on panels); hold RMB to fly, release for the cursor (G still toggles)
    AutoOpenProject = true,         -- on open: reload the most recent project, or create the first one
    StreamAroundCamera = true,
    EaseInMs = 0,
    CloseOnDeath = true,
    ClearAmbientPopulation = false,
    AckTimeoutMs = 3000,            -- NUI must answer sessionAck within this or the session closes
}

-- Freecam ------------------------------------------------------------------------------------
Config.Freecam = {
    Speed = 6.0, MinSpeed = 0.25, MaxSpeed = 120.0, SpeedStep = 1.15,
    FastMult = 4.0, SlowMult = 0.2,
    Inertia = 0.15,             -- 0 = stops dead when you let go, 1 = long glide (Camera panel)
    LookSmoothing = 0.2,        -- 0 = look follows the mouse instantly, 1 = heavy (Camera panel)
    MoveRate = { 40.0, 3.0 },   -- how fast velocity follows the keys at inertia 0 / 1 (1/s)
    LookRate = { 60.0, 5.0 },   -- how fast the view follows the mouse at smoothing ~0 / 1 (1/s)
    LookSensitivity = 8.0,
    PreciseLook = 0.3,          -- look sensitivity multiplier while Slow (Ctrl) is held
    RollRate = 35.0,
    Fov = 50.0, FovMin = 5.0, FovMax = 130.0, FovStep = 2.0,
    PitchLimit = 89.0,
}

-- Rigs ---------------------------------------------------------------------------------------
Config.Rigs = {
    Orbit = { Distance = 6.0, MinDistance = 0.5, MaxDistance = 80.0, AutoSpeed = 0.0, HeightOffset = 0.8,
              MinLift = -10.0, MaxLift = 40.0, MaxSpin = 120.0 }, -- lift (m) / spin (deg/s): Camera panel, Q/E
    Follow = { Offset = vector3(0.0, -6.0, 2.0), PosLag = 6.0, RotLag = 8.0, LookBone = 31086 },
}

-- Timeline -----------------------------------------------------------------------------------
Config.Timeline = {
    DefaultInterp = 'smooth',       -- 'smooth' | 'linear' | 'hold'
    DefaultEase = 'flow',           -- 'flow' (keeps moving through keys) | 'linear' | 'easeIn' | 'easeOut' | 'easeInOut' | 'bezier'
    DefaultKeyGap = 3.0,
    PathWeights = { Rot = 0.05, Fov = 0.05 }, -- path distance: 1 m = 20 deg of turn = 20 deg of FOV
    MaxKeysPerShot = 200,
    MaxShots = 100,
    PlayheadHz = 20,
    ClockSource = 'game',           -- 'game' (GetGameTimer) | 'network' (GetNetworkTimeAccurate), see spec risk R3
    PreloadScene = true,
    PreloadTimeoutMs = 4000,
}

-- Rockstar Editor recording (timeline "R* record" button) --------------------------------------
-- Loads the scene, starts a replay clip, holds the first frame for the lead-in (the editor's
-- watermark), plays the shot, holds the last frame for the tail, saves the clip.
Config.RockstarEditor = {
    Enabled = true,
    Mode = 1,                 -- StartRecording(mode)
    LeadIn = 4.0,             -- default seconds on the first frame (per project, Camera panel)
    Single = true,            -- "All" records every shot into ONE clip, cutting straight between shots
    Tail = 1.0,               -- default seconds on the last frame
    MaxLeadIn = 10.0, MaxTail = 10.0,
    StartTimeoutMs = 3000,    -- give up if the game does not start recording
    Gap = 1.5,                -- seconds between two clips when recording every shot
}

-- Camera path preview (lines in the world; hidden in clean view and while playing) ------------
Config.PathViz = {
    Enabled = false,             -- off until turned on in the Camera panel
    SamplesPerSec = 15,          -- line resolution along the shot
    MaxSamples = 600,
    StartColor = { 90, 220, 255 }, EndColor = { 255, 160, 60 }, -- gradient shows the direction
    Alpha = 210,
    ArrowEvery = 6,              -- a direction chevron every N samples
    KeyDirLength = 1.5,          -- line showing where the camera looks at each key (m)
}

-- Camera shake (per shot + per key) ----------------------------------------------------------------
-- Everything is in the camera's own frame: rot = { tilt, roll, pan } degrees, pos = { right, forward,
-- up } metres. The numbers are roughly the peak of a layer at 'Strength' 1.0 in the panel.
-- Layer kinds:
--   { freq, oct, gain, rot, pos }  fractal noise. freq = base rate, oct = octaves (each about twice
--                                  as fast), gain = strength of each next octave (0.7 = drift-heavy
--                                  and organic like hands, 0.5 = smooth)
--   { bob, rot, pos, impact }      footsteps. bob = steps per second, impact = heel-strike jolt (deg)
Config.Shake = {
    Presets = {
        handheld = {
            { freq = 0.4, oct = 4, gain = 0.50, rot = { 0.60, 0.22, 0.70 }, pos = { 0.014, 0.008, 0.012 } },
            { freq = 9.0, oct = 2, rot = { 0.012, 0.005, 0.012 } },                 -- muscle tremor
        },
        walk = {
            { freq = 0.5, oct = 4, gain = 0.66, rot = { 0.45, 0.20, 0.50 }, pos = { 0.008, 0.005, 0.005 } },
            { bob = 1.9, rot = { 0.30, 0.55, 0.22 }, pos = { 0.018, 0.006, 0.028 } },
        },
        run = {
            { freq = 0.8, oct = 4, gain = 0.66, rot = { 0.90, 0.45, 1.00 }, pos = { 0.015, 0.010, 0.010 } },
            { bob = 2.8, rot = { 0.70, 1.20, 0.45 }, pos = { 0.035, 0.012, 0.065 }, impact = 0.35 },
        },
        vehicle = {
            { freq = 0.6, oct = 3, gain = 0.6, rot = { 0.30, 0.28, 0.22 }, pos = { 0.004, 0.0, 0.008 } },   -- body sway
            { freq = 4.5, oct = 2, rot = { 0.10, 0.05, 0.04 }, pos = { 0.0, 0.0, 0.006 } },                 -- bumps
            { freq = 15.0, oct = 2, rot = { 0.035, 0.025, 0.025 }, pos = { 0.0, 0.0, 0.002 } },             -- road buzz
        },
        action = {
            { freq = 0.9, oct = 5, gain = 0.70, rot = { 1.30, 0.60, 1.50 }, pos = { 0.030, 0.020, 0.025 } },
            { freq = 9.0, oct = 2, rot = { 0.08, 0.04, 0.08 } },
        },
        drone = {
            { freq = 0.25, oct = 3, gain = 0.5, rot = { 0.45, 0.35, 0.60 }, pos = { 0.100, 0.060, 0.080 } },
        },
    },
    Breath = { Freq = 0.15, Depth = 0.35 },  -- the whole preset shake swells and calms slowly
    -- Presets react to the camera: livelier while it travels (Start..Full m/s; a pan counts as
    -- Turn m/s per deg/s) by up to +Gain. Footsteps shrink to BobIdle while it stands still.
    Move = { Start = 0.3, Full = 6.0, Turn = 0.04, Gain = 0.5, BobIdle = 0.45 },
    -- A long lens magnifies shake. Comp 0 = the same angle at every FOV (true to life, harsh when
    -- zoomed in), 1 = the same size on screen at every FOV. Ref = the FOV the numbers are tuned for.
    Fov = { Ref = 50.0, Comp = 0.5 },
    Motion = {
        -- "Tremor at speed": grows from Start to Full m/s
        Speed = {
            Start = 1.5, Full = 15.0,
            Sway = 0.60, SwayFreq = 3.0,       -- buffeting: a loose, slow wobble (deg, base rate)
            Buzz = 0.12, BuzzFreq = 13.0,      -- fine vibration on top (deg, base rate)
            Pos = 0.025,                       -- sideways / vertical float (m)
            Gust = 0.55, GustFreq = 0.45,      -- how uneven it is over time (0 = constant), how fast
        },
        Jolt = { Gain = 0.008, Max = 0.22, Decay = 5.0 },   -- rattle on hard speed changes: deg per m/s^2, cap, fade (1/s)
        -- "Lean"
        Lean = {
            Turn = 0.06, Side = 0.55, MaxRoll = 11.0,    -- bank: deg per deg/s of pan, deg per m/s^2 sideways, soft limit
            Nod = 0.22, Lift = 0.28, MaxPitch = 5.0,     -- nod: deg per m/s^2 forward / upward, soft limit
            Omega = 6.5, Damping = 0.55,                 -- spring: speed (rad/s), damping (1 = no overshoot at all)
            -- weight on pans and tilts: lags at the start, runs past the end, settles.
            -- Gain = how much of it shows, Max = soft limit (deg)
            Follow = { Gain = 0.18, Max = 3.0, Omega = 9.0, Damping = 0.6 },
        },
        Sign = 1.0,              -- -1.0 if the camera banks the wrong way
        VelSmoothing = 15.0, AccSmoothing = 8.0,
        CutDistance = 6.0, CutSpeed = 150.0, CutYaw = 25.0, -- a bigger jump in one frame is a cut
    },
}

-- "Put it where I look" placing of actors (Actors panel) --------------------------------------
Config.Placer = {
    Distance = 200.0,               -- how far the mouse ray reaches (m)
    Turn = 5.0,                     -- degrees per wheel step
    TurnFast = 15.0,                -- with Shift held
    TurnFine = 1.0,                 -- with Ctrl held
    Alpha = 190,                    -- 0..255: the actor is a little see-through while it follows the mouse
}

-- Ready-made moves / scenes --------------------------------------------------------------------
Config.Presets = {
    ProbeDistance = 200.0,          -- how far the "what does the camera look at" ray reaches (m)
    SubjectFallback = 8.0,          -- nothing hit (sky): frame a point this far ahead (m)
    SceneMaxDistance = 60.0,        -- a scene goes where the camera looks only when that is this close (m)
    MaxScenes = 24,                 -- placed scenes remembered per project
}

-- Depth of field -----------------------------------------------------------------------------
Config.Dof = {
    Enabled = true,                 -- master switch (turn off if ReShade DOF is used)
    Defaults = { near = 0.5, far = 12.0, strength = 1.0 },
    AutoFocusRate = 6.0,
}

-- Environment --------------------------------------------------------------------------------
Config.Env = {
    Weathers = nil,                 -- nil = shared/weather.lua list
    TimeScaleMin = 0.05,
    SyncAdapter = 'auto',           -- 'auto' | 'cd_easytime' | 'none'
    -- Applied the moment the director opens (Environment panel shows them; change them there).
    -- tod = minutes after midnight (13:00 = 780). nil / {} = keep the server's weather and time.
    OnOpen = { weather = 'EXTRASUNNY', tod = 13 * 60.0 },
}

-- Actors -------------------------------------------------------------------------------------
Config.Actors = {
    Max = 12,
    -- When a shot starts playing from its beginning (Space, or a Rockstar Editor take), emotes that
    -- play once (a salute, a handshake) start again, and two-person emotes start in step.
    RestartOnPlay = true,
    -- The actor picked in the Actors panel is marked in the world: corner brackets around it and a
    -- ring on the ground. Never drawn in clean view, during playback or while recording.
    -- Bracket = how much of each box edge is drawn from a corner (0.5 = a full wire box).
    Highlight = { Color = { 105, 255, 236, 230 }, Bracket = 0.22, Ring = true },
    Invincible = true,
    ModelLoadTimeoutMs = 8000,
}

-- Lights -------------------------------------------------------------------------------------
Config.Lights = {
    Max = 32,
    MaxActive = 16,
    MaxShadowed = 4,
    ShadowIdBase = 7300,
    DrawDistance = 150.0,
    Defaults = { type = 'point', color = { 255, 214, 170 }, range = 8.0, intensity = 4.0,
                 radius = 25.0, roundness = 0.0, falloff = 1.0, shadow = false },
}

-- Output -------------------------------------------------------------------------------------
Config.Output = {
    Letterbox = { Enabled = false, Ratio = 2.39 },
    Ratios = { 2.39, 2.35, 2.0, 1.85, 1.333 },
    HudHooks = {                    -- other resources' HUDs hidden during a session (called with false on open, true on close)
        { resource = 'aty_interface', export = 'SetHudVisible' },
    },
}

-- Storage ------------------------------------------------------------------------------------
Config.Storage = {
    MaxProjects = 200,
    MaxProjectBytes = 524288,
    LatentBps = 1000000,
    Backup = true,
    AutosaveSec = 120,              -- 0 = off; autosave only when dirty
    SaveTimeoutMs = 30000,
}

-- Game controls polled in the loop (all controls are disabled while a session runs) ----------
Config.Controls = {
    Forward = 32, Back = 33, Left = 34, Right = 35, Up = 38, Down = 44,
    Fast = 21, Slow = 36,
    RollLeft = 20, RollRight = 26,
    ScrollUp = 241, ScrollDown = 242,
    LookHold = 25,
    Place = 24,                 -- left mouse: drop the actor that follows the mouse (Config.Placer)
    Exit = 194,                 -- INPUT_FRONTEND_RRIGHT = Backspace only (177 also fires on right mouse)
    LookX = 1, LookY = 2,
    -- While a Rockstar Editor clip records, DisableAllControlActions makes the game drop the
    -- recording within a frame (measured with /cinerecdiag). Then only these player actions are
    -- blocked; no replay control is in here. 24 attack, 25 aim, 37 weapon wheel, 22 jump, 44 cover,
    -- 38 pickup, 14-17 / 261-262 weapon switch, 172 phone, 20 MP info, 199 / 200 pause.
    RecordBlock = { 24, 25, 37, 22, 44, 38, 14, 15, 16, 17, 261, 262, 172, 20, 199, 200 },
}

-- Key mappings (rebindable in FiveM settings). They fire only while a session is active.
Config.Keys = {
    Cursor     = { command = 'cine_cursor',      key = 'G',          label = 'Director: cursor / fly' },
    HideUi     = { command = 'cine_hideui',      key = 'H',          label = 'Director: clean view' },
    AddKey     = { command = 'cine_addkey',      key = 'F',          label = 'Director: add keyframe' },
    Play       = { command = 'cine_play',        key = 'SPACE',      label = 'Director: play / pause' },
    GizmoSel   = { command = 'cine_gizmo_sel',   key = 'MOUSE_LEFT', mapper = 'MOUSE_BUTTON', label = 'Director: gizmo drag' },
    GizmoMode  = { command = 'cine_gizmo_mode',  key = 'R',          label = 'Director: gizmo move / rotate' },
    GizmoSpace = { command = 'cine_gizmo_space', key = 'L',          label = 'Director: gizmo local / world' },
}

-- Locale (inline, single table; add Locales.tr later) -----------------------------------------
Locales = {
    en = {
        denied = 'You are not allowed to use the director.',
        busy = 'Director is busy, try again.',
        ack_failed = 'Director UI did not respond, session closed.',
        error_closed = 'Director session ended after an error (see F8).',
        need_keys = 'Add at least one keyframe first.',
        need_actor = 'Select an actor first.',
        max_keys = 'Keyframe limit reached.',
        max_shots = 'Shot limit reached.',
        max_actors = 'Actor limit reached.',
        max_lights = 'Light limit reached.',
        saved = 'Project saved.',
        save_failed = 'Save failed: %s',
        load_failed = 'Load failed: %s',
        model_failed = 'Could not load model: %s',
        anim_missing = 'Animation dictionary not found: %s',
        no_project = 'No project open.',
        default_project = 'My cinematic',
        key_updated = 'Keyframe updated from the camera.',
        rec_done = 'Recording done (%d clip). The game shows whether each clip saved.',
        rec_failed = 'The game did not start recording (Rockstar Editor blocked on this server?).',
        rec_busy = 'A Rockstar Editor recording is already running.',
        rec_aborted = 'Recording aborted, the clip was discarded.',
        scene_placed = 'Scene placed: %d actor(s), %d light(s).',
        placer_start = 'Move the mouse to place it, wheel turns it, left click drops it.',
        scene_removed = 'Scene removed: %d actor(s), %d light(s).',
        stage_cleared = 'Everything removed: %d actor(s), %d light(s).',
        scene_shot_deleted = 'Shot deleted. The actors of that scene are still there: Presets > Scenes > Placed removes them.',
        scene_no_room = 'The scene needs %d actors, only %d free. Remove some or tick "clear first".',
        scene_no_light_room = 'The scene needs %d lights, only %d free.',
    },
    tr = {
        denied = 'Director\'ı kullanma yetkin yok.',
        busy = 'Director meşgul, tekrar dene.',
        ack_failed = 'Director arayüzü yanıt vermedi, kapatıldı.',
        error_closed = 'Bir hata yüzünden director kapandı (F8\'e bak).',
        need_keys = 'Önce en az bir keyframe ekle (F).',
        need_actor = 'Önce bir aktör seç.',
        max_keys = 'Keyframe sınırına ulaşıldı.',
        max_shots = 'Çekim sınırına ulaşıldı.',
        max_actors = 'Aktör sınırına ulaşıldı.',
        max_lights = 'Işık sınırına ulaşıldı.',
        saved = 'Proje kaydedildi.',
        save_failed = 'Kaydetme başarısız: %s',
        load_failed = 'Yükleme başarısız: %s',
        model_failed = 'Model yüklenemedi: %s',
        anim_missing = 'Animasyon sözlüğü bulunamadı: %s',
        no_project = 'Açık proje yok.',
        default_project = 'Sinematiğim',
        key_updated = 'Keyframe kameranın yeni konumuyla güncellendi.',
        rec_done = 'Kayıt bitti (%d klip). Her klibin kaydedilip kaydedilmediğini oyun bildirir.',
        rec_failed = 'Oyun kaydı başlatmadı (bu sunucuda Rockstar Editor kapalı olabilir).',
        rec_busy = 'Zaten bir Rockstar Editor kaydı sürüyor.',
        rec_aborted = 'Kayıt iptal edildi, klip silindi.',
        scene_placed = 'Sahne yerleştirildi: %d aktör, %d ışık.',
        placer_start = 'Fareyi gezdirerek yerini seç, tekerlekle çevir, sol tıkla bırak.',
        scene_removed = 'Sahne kaldırıldı: %d aktör, %d ışık.',
        stage_cleared = 'Hepsi kaldırıldı: %d aktör, %d ışık.',
        scene_shot_deleted = 'Çekim silindi. O sahnenin aktörleri duruyor: Hazır > Sahne > Yerleştirilenler bölümünden kaldırabilirsin.',
        scene_no_room = 'Sahne %d aktör istiyor, yalnızca %d yer var. Birkaçını sil ya da "önce temizle"yi aç.',
        scene_no_light_room = 'Sahne %d ışık istiyor, yalnızca %d yer var.',
    },
}

function _L(key, ...)
    local l = Locales[Config.Locale] or Locales.en
    local s = (l and l[key]) or (Locales.en and Locales.en[key]) or ('[' .. tostring(key) .. ']')
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then return out end
    end
    return s
end
