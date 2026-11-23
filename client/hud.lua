-- Game HUD hiding and hooks into other resources' HUDs.
Cine.Hud = { hooked = {} }
local H = Cine.Hud

local function callHook(hook, visible)
    if GetResourceState(hook.resource) ~= 'started' then return false end
    local ok = pcall(function() exports[hook.resource][hook.export](exports[hook.resource], visible) end)
    return ok
end

function H.Open()
    pcall(DisplayRadar, false)
    for _, hook in ipairs(Config.Output.HudHooks) do
        if callHook(hook, false) then H.hooked[#H.hooked + 1] = hook end
    end
end

--- Per frame.
function H.Tick()
    HideHudAndRadarThisFrame()
    ThefeedHideThisFrame()
end

function H.Close()
    pcall(DisplayRadar, true)
    for _, hook in ipairs(H.hooked) do callHook(hook, true) end
    H.hooked = {}
end
