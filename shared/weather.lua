-- Weather type names (from the timecycle reference header). Used for the picker and for validation.
CineWeather = {
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'CLEARING', 'RAIN', 'THUNDER', 'SMOG', 'FOGGY',
    'SNOW', 'SNOWLIGHT', 'BLIZZARD', 'XMAS', 'HALLOWEEN', 'NEUTRAL',
}

function CineWeatherSet()
    local list = (Config.Env and Config.Env.Weathers) or CineWeather
    local set = {}
    for _, name in ipairs(list) do set[name] = true end
    return set, list
end
