-- Ready-made scene set-ups: actors, vehicles and lights placed in one go in front of the camera.
--
-- Positions are in the scene's own frame, seen from the camera:
--   x = metres to the camera's right, y = metres towards the camera, z = metres above the ground
-- Actors:  { kind, model, name, at = { x, y }, face = 'cam' | { x, y } (peds look at that spot),
--            h = degrees (vehicles: 0 = nose to the camera, + = turned anticlockwise seen from above),
--            scenario = name | anim = { dict, name, flag } }
-- Lights:  { type, name, at = { x, y, z }, aim = { x, y, z } (spots), color, intensity, range,
--            radius (spot cone), falloff, shadow }
-- dist = how far in front of the camera the scene centre goes. main = index of the actor the
-- camera should frame. look / move = the atmosphere and the camera move that suit the scene.
-- cam = where the scene's own camera stands and what it looks at (scene frame, z above the
-- ground) + its FOV: the suggested move is built from there, not from wherever the user's camera
-- happens to be. mo = { dir, amount, dur } for that move when its defaults do not suit the scene.
--
-- Models come from lists/peds.json and lists/vehicles.json, scenarios / animations from
-- lists/anims.json and the scenario names in the native reference.

local WARM, COOL, WHITE = { 255, 214, 170 }, { 170, 205, 255 }, { 255, 255, 255 }
local MAGENTA, CYAN, RED, BLUE = { 255, 60, 200 }, { 60, 220, 255 }, { 255, 40, 40 }, { 50, 90, 255 }

local BOUNCER = { dict = 'mini@strip_club@idles@bouncer@base', name = 'base', flag = 1 }
local HANDS_UP = { dict = 'random@arrests', name = 'idle_2_hands_up', flag = 2 }

--- Classic three-point lighting around a subject at (x, y), head height h.
local function threePoint(x, y, h)
    return {
        { type = 'spot', name = 'Key', at = { x - 2.2, y + 2.4, h + 0.9 }, aim = { x, y, h }, color = WARM, intensity = 9.0, range = 9.0, radius = 38.0, falloff = 6.0, shadow = true },
        { type = 'point', name = 'Fill', at = { x + 2.0, y + 1.6, h - 0.2 }, color = COOL, intensity = 1.6, range = 5.5 },
        { type = 'spot', name = 'Rim', at = { x + 0.9, y - 2.6, h + 1.1 }, aim = { x, y, h + 0.1 }, color = WHITE, intensity = 11.0, range = 8.0, radius = 30.0, falloff = 6.0 },
    }
end

CineScenes = {
    -- people -----------------------------------------------------------------------------------------
    {
        id = 'portrait', group = 'people', dist = 5.0, main = 1, move = 'push_in', look = 'golden',
        cam = { at = { 0.0, 3.2, 1.6 }, aim = { 0.0, 0.0, 1.55 }, fov = 40.0 },
        actors = {
            { kind = 'ped', model = 'a_m_y_business_03', name = 'Subject', at = { 0.0, 0.0 }, face = 'cam', scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
        },
        lights = threePoint(0.0, 0.0, 1.65),
    },
    {
        id = 'dialogue', group = 'people', dist = 6.0, main = 1, move = 'arc_push', look = 'golden',
        cam = { at = { 0.0, 4.5, 1.55 }, aim = { 0.0, 0.0, 1.5 }, fov = 40.0 },
        actors = {
            { kind = 'ped', model = 'a_m_y_business_03', name = 'Speaker A', at = { -0.75, 0.0 }, face = { 0.75, 0.0 }, scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
            { kind = 'ped', model = 'a_f_y_business_02', name = 'Speaker B', at = { 0.75, 0.0 }, face = { -0.75, 0.0 }, scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },
        lights = {
            { type = 'spot', name = 'Key', at = { -2.4, 2.8, 2.6 }, aim = { 0.4, 0.0, 1.6 }, color = WARM, intensity = 9.0, range = 10.0, radius = 42.0, falloff = 6.0, shadow = true },
            { type = 'point', name = 'Fill', at = { 2.2, 2.0, 1.5 }, color = COOL, intensity = 1.6, range = 6.0 },
            { type = 'spot', name = 'Rim', at = { 0.0, -3.0, 2.8 }, aim = { 0.0, 0.0, 1.7 }, color = WHITE, intensity = 10.0, range = 9.0, radius = 40.0, falloff = 6.0 },
        },
    },
    {
        id = 'interview', group = 'people', dist = 6.0, main = 1, move = 'handheld_hold', look = 'noon',
        cam = { at = { -2.2, 3.0, 1.65 }, aim = { 0.0, 0.0, 1.6 }, fov = 35.0 },
        actors = {
            { kind = 'ped', model = 'a_f_y_bevhills_01', name = 'Guest', at = { 0.0, 0.0 }, face = { -1.1, 2.2 }, scenario = 'WORLD_HUMAN_HANG_OUT_STREET' },
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Reporter', at = { -1.1, 2.2 }, face = { 0.0, 0.0 }, scenario = 'WORLD_HUMAN_CLIPBOARD' },
            { kind = 'ped', model = 'a_m_y_business_03', name = 'Photographer', at = { 1.6, 2.6 }, face = { 0.0, 0.0 }, scenario = 'WORLD_HUMAN_PAPARAZZI' },
        },
        lights = threePoint(0.0, 0.0, 1.65),
    },
    {
        id = 'street_night', group = 'people', dist = 5.5, main = 1, move = 'arc_push', look = 'neon_rain',
        cam = { at = { 1.2, 3.6, 1.5 }, aim = { 0.0, 0.0, 1.55 }, fov = 38.0 },
        actors = {
            { kind = 'ped', model = 'a_f_y_bevhills_01', name = 'Smoker', at = { 0.0, 0.0 }, face = { 1.5, 2.0 }, scenario = 'WORLD_HUMAN_SMOKING' },
        },
        lights = {
            { type = 'point', name = 'Neon magenta', at = { -2.2, -0.8, 2.2 }, color = MAGENTA, intensity = 7.0, range = 7.0 },
            { type = 'point', name = 'Neon cyan', at = { 2.4, -0.6, 1.8 }, color = CYAN, intensity = 6.0, range = 7.0 },
            { type = 'spot', name = 'Key', at = { 1.6, 2.6, 2.4 }, aim = { 0.0, 0.0, 1.6 }, color = WARM, intensity = 5.0, range = 8.0, radius = 34.0, falloff = 6.0 },
        },
    },
    {
        id = 'standoff', group = 'people', dist = 9.0, main = 1, move = 'slide', look = 'overcast',
        cam = { at = { -2.0, 9.5, 1.6 }, aim = { -2.0, 0.0, 1.4 }, fov = 45.0 }, mo = { amount = 0.4 },
        actors = {
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Left 1', at = { -3.5, 0.0 }, face = { 3.5, 0.0 }, anim = BOUNCER },
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Left 2', at = { -4.4, 1.0 }, face = { 3.5, 0.0 }, scenario = 'WORLD_HUMAN_GUARD_STAND' },
            { kind = 'ped', model = 'a_m_y_business_03', name = 'Right 1', at = { 3.5, 0.0 }, face = { -3.5, 0.0 }, anim = BOUNCER },
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Right 2', at = { 4.4, -1.0 }, face = { -3.5, 0.0 }, scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
        },
        lights = {
            { type = 'spot', name = 'Rim left', at = { -6.5, -2.5, 3.0 }, aim = { -3.8, 0.4, 1.6 }, color = COOL, intensity = 11.0, range = 10.0, radius = 40.0, falloff = 6.0 },
            { type = 'spot', name = 'Rim right', at = { 6.5, -2.5, 3.0 }, aim = { 3.8, -0.4, 1.6 }, color = WARM, intensity = 11.0, range = 10.0, radius = 40.0, falloff = 6.0 },
            { type = 'point', name = 'Fill', at = { 0.0, 4.0, 2.0 }, color = WHITE, intensity = 1.5, range = 10.0 },
        },
    },
    {
        id = 'crowd', group = 'people', dist = 8.0, main = 2, move = 'crane', look = 'noon',
        cam = { at = { 0.0, 6.5, 1.5 }, aim = { 0.0, -0.8, 1.5 }, fov = 50.0 },
        actors = {
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Front left', at = { -1.6, 0.0 }, face = 'cam', scenario = 'WORLD_HUMAN_CHEERING' },
            { kind = 'ped', model = 'a_f_y_bevhills_01', name = 'Front centre', at = { 0.0, 0.0 }, face = 'cam', scenario = 'WORLD_HUMAN_CHEERING' },
            { kind = 'ped', model = 'a_m_y_business_03', name = 'Front right', at = { 1.6, 0.0 }, face = 'cam', scenario = 'WORLD_HUMAN_CHEERING' },
            { kind = 'ped', model = 'a_f_y_business_02', name = 'Back left', at = { -0.8, -1.3 }, face = 'cam', scenario = 'WORLD_HUMAN_CHEERING' },
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Back right', at = { 0.8, -1.3 }, face = 'cam', scenario = 'WORLD_HUMAN_CHEERING' },
            { kind = 'ped', model = 'a_f_y_bevhills_01', name = 'Back row', at = { 0.0, -2.6 }, face = 'cam', scenario = 'WORLD_HUMAN_TOURIST_MOBILE' },
        },
        lights = {
            { type = 'spot', name = 'Key', at = { -3.5, 4.5, 3.4 }, aim = { 0.0, -0.8, 1.6 }, color = WARM, intensity = 10.0, range = 13.0, radius = 50.0, falloff = 6.0, shadow = true },
            { type = 'spot', name = 'Rim', at = { 2.5, -5.5, 3.6 }, aim = { 0.0, -0.8, 1.7 }, color = WHITE, intensity = 10.0, range = 12.0, radius = 50.0, falloff = 6.0 },
        },
    },
    {
        id = 'security_line', group = 'people', dist = 8.0, main = 5, move = 'orbit', look = 'night_city',
        cam = { at = { -3.0, 6.0, 1.5 }, aim = { 0.0, -0.3, 1.5 }, fov = 45.0 }, mo = { amount = 50, dur = 7.0 },
        actors = {
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Guard 1', at = { -2.4, 0.0 }, face = 'cam', scenario = 'WORLD_HUMAN_GUARD_STAND' },
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Guard 2', at = { -0.8, 0.0 }, face = 'cam', anim = BOUNCER },
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Guard 3', at = { 0.8, 0.0 }, face = 'cam', anim = BOUNCER },
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Guard 4', at = { 2.4, 0.0 }, face = 'cam', scenario = 'WORLD_HUMAN_GUARD_STAND' },
            { kind = 'ped', model = 'a_m_y_business_03', name = 'VIP', at = { 0.0, -1.7 }, face = 'cam', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
        },
        lights = {
            { type = 'spot', name = 'Key', at = { -4.0, 4.0, 3.2 }, aim = { 0.0, 0.0, 1.6 }, color = WARM, intensity = 10.0, range = 12.0, radius = 52.0, falloff = 6.0, shadow = true },
            { type = 'spot', name = 'Rim', at = { 1.5, -5.0, 3.4 }, aim = { 0.0, -1.0, 1.7 }, color = COOL, intensity = 11.0, range = 11.0, radius = 46.0, falloff = 6.0 },
        },
    },

    -- vehicles ---------------------------------------------------------------------------------------
    {
        id = 'car_showcase', group = 'vehicles', dist = 10.0, main = 1, move = 'orbit', look = 'night_city',
        cam = { at = { 0.0, 8.0, 1.1 }, aim = { 0.0, 0.0, 0.7 }, fov = 40.0 },
        actors = {
            { kind = 'vehicle', model = 'zentorno', name = 'Hero car', at = { 0.0, 0.0 }, h = 35.0 },
        },
        lights = {
            { type = 'spot', name = 'Softbox left', at = { -4.5, 3.0, 2.6 }, aim = { 0.0, 0.0, 0.6 }, color = WHITE, intensity = 12.0, range = 11.0, radius = 46.0, falloff = 6.0, shadow = true },
            { type = 'spot', name = 'Softbox right', at = { 4.5, 2.5, 2.2 }, aim = { 0.0, 0.0, 0.6 }, color = COOL, intensity = 7.0, range = 11.0, radius = 46.0, falloff = 6.0 },
            { type = 'spot', name = 'Top', at = { 0.0, 0.0, 5.5 }, aim = { 0.0, 0.0, 0.0 }, color = WHITE, intensity = 8.0, range = 9.0, radius = 44.0, falloff = 6.0 },
            { type = 'spot', name = 'Rim', at = { -1.0, -5.5, 2.4 }, aim = { 0.0, 0.0, 0.8 }, color = WARM, intensity = 12.0, range = 10.0, radius = 40.0, falloff = 6.0 },
        },
    },
    {
        id = 'hero_car', group = 'vehicles', dist = 9.0, main = 2, move = 'hero_low', look = 'golden',
        cam = { at = { -1.0, 5.0, 1.4 }, aim = { -1.3, 1.4, 1.6 }, fov = 45.0 },
        actors = {
            { kind = 'vehicle', model = 'comet2', name = 'Car', at = { 0.6, -1.4 }, h = 30.0 },
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Driver', at = { -1.3, 1.4 }, face = 'cam', anim = BOUNCER },
        },
        lights = {
            { type = 'spot', name = 'Key', at = { -3.6, 4.0, 2.6 }, aim = { -1.3, 1.4, 1.6 }, color = WARM, intensity = 9.0, range = 10.0, radius = 40.0, falloff = 6.0, shadow = true },
            { type = 'spot', name = 'Car rim', at = { 3.5, -5.5, 2.6 }, aim = { 0.6, -1.4, 0.8 }, color = WHITE, intensity = 12.0, range = 11.0, radius = 44.0, falloff = 6.0 },
        },
    },
    {
        id = 'car_meet', group = 'vehicles', dist = 13.0, main = 2, move = 'orbit', look = 'night_city',
        cam = { at = { -5.5, 11.0, 1.7 }, aim = { 0.2, 3.7, 1.4 }, fov = 45.0 }, mo = { amount = 60, dur = 9.0 },
        actors = {
            { kind = 'vehicle', model = 'adder', name = 'Car left', at = { -4.4, 0.0 }, h = 25.0 },
            { kind = 'vehicle', model = 'zentorno', name = 'Car centre', at = { 0.0, -1.0 }, h = 0.0 },
            { kind = 'vehicle', model = 'comet2', name = 'Car right', at = { 4.4, 0.0 }, h = -25.0 },
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Guest 1', at = { -1.0, 3.4 }, face = { 0.1, 3.9 }, scenario = 'WORLD_HUMAN_DRINKING' },
            { kind = 'ped', model = 'a_f_y_bevhills_01', name = 'Guest 2', at = { 0.3, 4.4 }, face = { 0.1, 3.4 }, scenario = 'WORLD_HUMAN_STAND_MOBILE' },
            { kind = 'ped', model = 'a_m_y_business_03', name = 'Guest 3', at = { 1.2, 3.3 }, face = { 0.1, 3.9 }, scenario = 'WORLD_HUMAN_SMOKING' },
        },
        lights = {
            { type = 'point', name = 'Glow cyan', at = { -4.4, 2.6, 1.0 }, color = CYAN, intensity = 6.0, range = 7.0 },
            { type = 'point', name = 'Glow magenta', at = { 4.4, 2.6, 1.0 }, color = MAGENTA, intensity = 6.0, range = 7.0 },
            { type = 'spot', name = 'Top', at = { 0.0, 0.5, 6.5 }, aim = { 0.0, 0.5, 0.0 }, color = WARM, intensity = 9.0, range = 12.0, radius = 58.0, falloff = 6.0, shadow = true },
        },
    },
    {
        id = 'police_stop', group = 'vehicles', dist = 12.0, main = 3, move = 'slide', look = 'night_city',
        cam = { at = { 4.0, 9.0, 1.6 }, aim = { 4.0, 0.0, 1.2 }, fov = 40.0 }, mo = { dir = -1 },
        actors = {
            { kind = 'vehicle', model = 'schafter3', name = 'Stopped car', at = { 2.0, 0.0 }, h = 90.0 },
            { kind = 'vehicle', model = 'police3', name = 'Police car', at = { -4.8, 0.0 }, h = 90.0 },
            { kind = 'ped', model = 's_m_y_cop_01', name = 'Officer', at = { 1.2, 1.7 }, face = { 2.6, 2.0 }, scenario = 'WORLD_HUMAN_CLIPBOARD' },
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Driver', at = { 2.7, 2.0 }, face = { 1.2, 1.7 }, anim = HANDS_UP },
        },
        lights = {
            { type = 'point', name = 'Light bar red', at = { -4.8, 0.45, 1.9 }, color = RED, intensity = 8.0, range = 9.0 },
            { type = 'point', name = 'Light bar blue', at = { -4.8, -0.45, 1.9 }, color = BLUE, intensity = 8.0, range = 9.0 },
            { type = 'spot', name = 'Headlights', at = { -2.4, 0.0, 0.8 }, aim = { 2.0, 0.6, 1.0 }, color = WHITE, intensity = 9.0, range = 10.0, radius = 40.0, falloff = 6.0, shadow = true },
        },
    },
    {
        id = 'vip_arrival', group = 'vehicles', dist = 11.0, main = 2, move = 'push_in', look = 'blue_hour',
        cam = { at = { 0.3, 7.5, 1.5 }, aim = { 0.3, 0.9, 1.5 }, fov = 38.0 },
        actors = {
            { kind = 'vehicle', model = 'baller4', name = 'SUV', at = { 0.0, -1.8 }, h = 90.0 },
            { kind = 'ped', model = 'a_f_y_business_02', name = 'VIP', at = { 0.3, 0.9 }, face = 'cam', scenario = 'WORLD_HUMAN_STAND_MOBILE' },
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Guard left', at = { -1.3, 1.3 }, face = 'cam', scenario = 'WORLD_HUMAN_GUARD_STAND' },
            { kind = 'ped', model = 's_m_m_highsec_01', name = 'Guard right', at = { 1.9, 1.3 }, face = 'cam', anim = BOUNCER },
            { kind = 'ped', model = 'a_m_y_hipster_01', name = 'Photographer', at = { -3.0, 4.6 }, face = { 0.3, 0.9 }, scenario = 'WORLD_HUMAN_PAPARAZZI' },
            { kind = 'ped', model = 'a_f_y_bevhills_01', name = 'Fan', at = { 3.2, 4.8 }, face = { 0.3, 0.9 }, scenario = 'WORLD_HUMAN_TOURIST_MOBILE' },
        },
        lights = {
            { type = 'spot', name = 'Key', at = { -3.0, 4.6, 2.6 }, aim = { 0.3, 0.9, 1.6 }, color = WHITE, intensity = 10.0, range = 10.0, radius = 40.0, falloff = 6.0, shadow = true },
            { type = 'point', name = 'Fill', at = { 3.0, 3.0, 1.6 }, color = COOL, intensity = 1.8, range = 7.0 },
            { type = 'spot', name = 'Rim', at = { 2.5, -5.0, 3.0 }, aim = { 0.3, 0.6, 1.6 }, color = WARM, intensity = 11.0, range = 11.0, radius = 44.0, falloff = 6.0 },
        },
    },
}

CineSceneGroups = { 'people', 'vehicles' }

-- Names of the actors and lights a scene adds, per locale (missing = the English name).
local NAMES = {
    tr = {
        ['Subject'] = 'Özne', ['Speaker A'] = 'Konuşmacı A', ['Speaker B'] = 'Konuşmacı B', ['Guest'] = 'Konuk',
        ['Reporter'] = 'Muhabir', ['Photographer'] = 'Fotoğrafçı', ['Smoker'] = 'Sigara içen',
        ['Left 1'] = 'Sol 1', ['Left 2'] = 'Sol 2', ['Right 1'] = 'Sağ 1', ['Right 2'] = 'Sağ 2',
        ['Front left'] = 'Ön sol', ['Front centre'] = 'Ön orta', ['Front right'] = 'Ön sağ',
        ['Back left'] = 'Arka sol', ['Back right'] = 'Arka sağ', ['Back row'] = 'Arka sıra',
        ['Guard 1'] = 'Koruma 1', ['Guard 2'] = 'Koruma 2', ['Guard 3'] = 'Koruma 3', ['Guard 4'] = 'Koruma 4',
        ['Guard left'] = 'Sol koruma', ['Guard right'] = 'Sağ koruma', ['Fan'] = 'Hayran',
        ['Hero car'] = 'Ana araç', ['Car'] = 'Araç', ['Driver'] = 'Sürücü', ['Car left'] = 'Sol araç',
        ['Car centre'] = 'Orta araç', ['Car right'] = 'Sağ araç', ['Guest 1'] = 'Misafir 1', ['Guest 2'] = 'Misafir 2',
        ['Guest 3'] = 'Misafir 3', ['Stopped car'] = 'Durdurulan araç', ['Police car'] = 'Polis aracı',
        ['Officer'] = 'Polis memuru',
        ['Key'] = 'Ana ışık', ['Fill'] = 'Dolgu ışığı', ['Rim'] = 'Kontur ışığı', ['Top'] = 'Tepe ışığı',
        ['Rim left'] = 'Sol kontur', ['Rim right'] = 'Sağ kontur', ['Car rim'] = 'Araç konturu',
        ['Softbox left'] = 'Sol softbox', ['Softbox right'] = 'Sağ softbox',
        ['Neon magenta'] = 'Neon pembe', ['Neon cyan'] = 'Neon turkuaz',
        ['Glow cyan'] = 'Turkuaz parıltı', ['Glow magenta'] = 'Pembe parıltı',
        ['Light bar red'] = 'Tepe lambası kırmızı', ['Light bar blue'] = 'Tepe lambası mavi', ['Headlights'] = 'Farlar',
    },
}

function CineSceneName(name, locale)
    local t = NAMES[locale]
    return (t and t[name]) or name
end

function CineScene(id)
    for _, s in ipairs(CineScenes) do
        if s.id == id then return s end
    end
    return nil
end

--- What the panel needs to draw the list.
function CineScenesMeta()
    local out = {}
    for _, s in ipairs(CineScenes) do
        local peds, vehicles = 0, 0
        for _, a in ipairs(s.actors) do
            if a.kind == 'vehicle' then vehicles = vehicles + 1 else peds = peds + 1 end
        end
        out[#out + 1] = { id = s.id, group = s.group, peds = peds, vehicles = vehicles, lights = #s.lights, move = s.move or false, look = s.look or false }
    end
    return out
end

--- Scene frame -> world. origin = ground point of the scene centre { x, y }, yaw = camera yaw (deg).
--- Returns a function (x, y) -> worldX, worldY and the heading of something that faces the camera.
function CineSceneFrame(origin, yaw)
    local yr = math.rad(yaw)
    local rx, ry = math.cos(yr), math.sin(yr)        -- the camera's right
    local bx, by = math.sin(yr), -math.cos(yr)       -- towards the camera (minus its forward)
    return function(x, y)
        return origin[1] + rx * x + bx * y, origin[2] + ry * x + by * y
    end, (yaw + 180.0) % 360.0
end
