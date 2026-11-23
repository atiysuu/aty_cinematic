-- Static scene lights: per-frame draw calls with a budget, editor locators.
-- Every float argument is coerced with + 0.0 (an integer silently kills the light), colours stay ints.
Cine.Lights = { selected = nil }
local L = Cine.Lights

local active = {}

--- Light direction from rotation (pitch, roll, yaw), GTA convention.
local function direction(rot)
    local fx, fy, fz = CineMath.Basis(rot[1], rot[3])
    return fx, fy, fz
end
L.Direction = direction

--- Draw the lights of the open project. playback = true: only lights enabled for the shot are drawn.
function L.Tick(project, shot, camPos, playback, showLocators)
    if not project or #project.lights == 0 then return end
    local cfg = Config.Lights
    local n = 0
    local maxD2 = cfg.DrawDistance * cfg.DrawDistance
    for i = 1, #project.lights do
        local l = project.lights[i]
        local on = true
        if playback and shot and shot.lights[l.id] == false then on = false end
        if on then
            local dx, dy, dz = l.pos[1] - camPos[1], l.pos[2] - camPos[2], l.pos[3] - camPos[3]
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 <= maxD2 then
                n = n + 1
                local entry = active[n]
                if not entry then entry = {}; active[n] = entry end
                entry.l, entry.d2, entry.index = l, d2, i
            end
        end
    end
    for i = n + 1, #active do active[i] = nil end
    if n > 1 then table.sort(active, function(a, b) return a.d2 < b.d2 end) end

    local shadowed = 0
    for i = 1, math.min(n, cfg.MaxActive) do
        local e = active[i]
        local l = e.l
        local c = l.color
        local x, y, z = l.pos[1] + 0.0, l.pos[2] + 0.0, l.pos[3] + 0.0
        local wantShadow = l.shadow and shadowed < cfg.MaxShadowed
        if wantShadow then shadowed = shadowed + 1 end
        if l.type == 'spot' then
            local dx, dy, dz = direction(l.rot)
            if wantShadow then
                DrawSpotLightWithShadow(x, y, z, dx + 0.0, dy + 0.0, dz + 0.0, c[1], c[2], c[3],
                    l.range + 0.0, l.intensity + 0.0, l.roundness + 0.0, l.radius + 0.0, l.falloff + 0.0,
                    cfg.ShadowIdBase + e.index)
            else
                DrawSpotLight(x, y, z, dx + 0.0, dy + 0.0, dz + 0.0, c[1], c[2], c[3],
                    l.range + 0.0, l.intensity + 0.0, l.roundness + 0.0, l.radius + 0.0, l.falloff + 0.0)
            end
        else
            if wantShadow then
                DrawLightWithRangeAndShadow(x, y, z, c[1], c[2], c[3], l.range + 0.0, l.intensity + 0.0, 1.0)
            else
                DrawLightWithRange(x, y, z, c[1], c[2], c[3], l.range + 0.0, l.intensity + 0.0)
            end
        end
    end

    if showLocators then
        for i = 1, #project.lights do
            local l = project.lights[i]
            local c = l.color
            local sel = L.selected == l.id
            local scale = sel and 0.22 or 0.14
            DrawMarker(28, l.pos[1] + 0.0, l.pos[2] + 0.0, l.pos[3] + 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                scale, scale, scale, c[1], c[2], c[3], sel and 220 or 140, false, false, 2, false, nil, nil, false)
            if l.type == 'spot' then
                local dx, dy, dz = direction(l.rot)
                local len = math.min(l.range, 3.0)
                DrawLine(l.pos[1] + 0.0, l.pos[2] + 0.0, l.pos[3] + 0.0,
                    l.pos[1] + dx * len, l.pos[2] + dy * len, l.pos[3] + dz * len, c[1], c[2], c[3], 200)
            end
        end
    end
end
