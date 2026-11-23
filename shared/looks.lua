-- Ready-made atmospheres: weather + time of day + colour filter (timecycle modifier) + wind / rain.
-- A full look sets every one of those (so nothing of the previous look is left behind); a
-- filter look (group 'filter') only changes the colour filter and keeps the weather and the clock.
--
--   tod      minutes after midnight
--   tc / tcs colour filter name (lists/timecycles.json) and its strength 0..1
--   rain     0..1, nil = whatever the weather brings
--   sw       two colours for the swatch in the panel
--   dof      suggested blur strength 0..1 ("also set depth of field")
--   shake    suggested shot shake ("also set the shake")
CineLooks = {}

local function look(id, group, f)
    local full = group ~= 'filter'
    local env = { timecycle = f.tc or '', tcStrength = f.tcs or 1.0 }
    if full then
        env.weather, env.tod = f.weather, f.tod
        env.wind = f.wind or 1.0
        env.rain = f.rain or -1.0          -- -1 = back to automatic
        env.blackout = f.blackout == true
    end
    CineLooks[#CineLooks + 1] = { id = id, group = group, env = env, sw = f.sw, dof = f.dof, shake = f.shake }
end

-- day ------------------------------------------------------------------------------------------------
look('noon', 'day', { weather = 'EXTRASUNNY', tod = 13 * 60, sw = { '8fd3ff', 'fff4c2' }, dof = 0.4 })
look('golden', 'day', { weather = 'EXTRASUNNY', tod = 19 * 60 + 15, tc = 'rply_saturation', tcs = 0.35,
    sw = { 'ffb347', 'ff6a3d' }, dof = 0.7, shake = { preset = 'handheld', amount = 0.3, speed = 0.0, whip = 0.15 } })
look('sunrise', 'day', { weather = 'CLEAR', tod = 6 * 60 + 10, wind = 0.5, sw = { 'ffd9a0', '9fb8ff' }, dof = 0.6 })
look('overcast', 'day', { weather = 'OVERCAST', tod = 15 * 60, tc = 'rply_saturation_neg', tcs = 0.5, wind = 2.0,
    sw = { '9aa3ad', '5f6b78' }, dof = 0.5 })
look('smog', 'day', { weather = 'SMOG', tod = 16 * 60 + 30, wind = 0.5, sw = { 'd9c08f', '9c8a6b' }, dof = 0.5 })
look('fog', 'day', { weather = 'FOGGY', tod = 6 * 60 + 40, wind = 0.0, sw = { 'cfd6dc', '8a949c' }, dof = 0.3 })

-- night ----------------------------------------------------------------------------------------------
look('blue_hour', 'night', { weather = 'CLEAR', tod = 20 * 60 + 40, sw = { '3c5a9a', '1b2440' }, dof = 0.7 })
look('night_city', 'night', { weather = 'CLEAR', tod = 23 * 60 + 30, tc = 'rply_contrast', tcs = 0.4,
    sw = { '1c2233', 'ffb86b' }, dof = 0.8 })
look('neon_rain', 'night', { weather = 'RAIN', tod = 22 * 60 + 30, rain = 0.7, wind = 3.0, tc = 'rply_saturation', tcs = 0.4,
    sw = { 'ff4fd8', '35e0ff' }, dof = 0.8, shake = { preset = 'handheld', amount = 0.35, speed = 0.0, whip = 0.2 } })
look('blackout', 'night', { weather = 'CLEAR', tod = 1 * 60, blackout = true, sw = { '0b0e16', '2a3350' }, dof = 0.6 })
look('noir', 'night', { weather = 'CLEAR', tod = 22 * 60, tc = 'blackNwhite', tcs = 1.0, sw = { 'f2f2f2', '111111' }, dof = 0.8 })

-- weather --------------------------------------------------------------------------------------------
look('storm', 'weather', { weather = 'THUNDER', tod = 18 * 60 + 30, rain = 1.0, wind = 10.0,
    sw = { '3b4558', '9fb3ff' }, dof = 0.3, shake = { preset = 'handheld', amount = 0.7, speed = 0.4, whip = 0.3 } })
look('drizzle', 'weather', { weather = 'RAIN', tod = 11 * 60, rain = 0.3, wind = 2.0, tc = 'rply_saturation_neg', tcs = 0.3,
    sw = { '8794a3', '4e5a68' }, dof = 0.5 })
look('snow', 'weather', { weather = 'XMAS', tod = 14 * 60, wind = 1.0, sw = { 'ffffff', 'bcd4e6' }, dof = 0.5 })
look('blizzard', 'weather', { weather = 'BLIZZARD', tod = 16 * 60, wind = 12.0, sw = { 'e6eef5', '7f8fa3' }, dof = 0.3,
    shake = { preset = 'handheld', amount = 0.8, speed = 0.5, whip = 0.3 } })
look('halloween', 'weather', { weather = 'HALLOWEEN', tod = 30, wind = 2.0, sw = { 'ff7a1a', '2a1036' }, dof = 0.6 })

-- colour filter only -----------------------------------------------------------------------------------
look('f_vivid', 'filter', { tc = 'rply_saturation', tcs = 0.6, sw = { 'ff5e62', '35d979' } })
look('f_muted', 'filter', { tc = 'rply_saturation_neg', tcs = 0.6, sw = { 'a9a9a9', '6f7c85' } })
look('f_contrast', 'filter', { tc = 'rply_contrast', tcs = 0.6, sw = { 'ffffff', '000000' } })
look('f_vignette', 'filter', { tc = 'rply_vignette', tcs = 0.8, sw = { '9aa3ad', '0a0a0a' } })
look('f_bw', 'filter', { tc = 'blackNwhite', tcs = 1.0, sw = { 'e8e8e8', '2b2b2b' } })
look('f_bloom', 'filter', { tc = 'BloomLight', tcs = 0.8, sw = { 'fff6d6', 'ffd27a' } })
look('f_cctv', 'filter', { tc = 'scanline_cam', tcs = 1.0, sw = { '6dff9c', '0c1f14' } })
look('f_none', 'filter', { tc = '', tcs = 1.0, sw = { '3a3a3a', '3a3a3a' } })

CineLookGroups = { 'day', 'night', 'weather', 'filter' }

function CineLook(id)
    for _, l in ipairs(CineLooks) do
        if l.id == id then return l end
    end
    return nil
end

--- What the panel needs to draw the list.
function CineLooksMeta()
    local out = {}
    for _, l in ipairs(CineLooks) do
        out[#out + 1] = {
            id = l.id, group = l.group, sw = l.sw, weather = l.env.weather or false, tod = l.env.tod or false,
            filter = l.env.timecycle ~= '' and l.env.timecycle or false, dof = l.dof ~= nil, shake = l.shake ~= nil,
        }
    end
    return out
end
