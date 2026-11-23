fx_version 'cerulean'
game 'gta5'

author 'atiysu'
description 'aty_cinematic - cinematic director: free camera, keyframe timeline, actors, lights, ready-made moves and scenes, Rockstar Editor recording'
version '0.1.0'
lua54 'yes'

dependencies {
    'aty_lib'
}

shared_scripts {
    'config.lua',
    'shared/*.lua',
}

client_scripts {
    'client/lib/dataview.lua',
    'client/bootstrap.lua',
    'client/store.lua',
    'client/nui.lua',
    'client/camera.lua',
    'client/shake.lua',
    'client/pathviz.lua',
    'client/freecam.lua',
    'client/rigs.lua',
    'client/timeline.lua',
    'client/env.lua',
    'client/actors.lua',
    'client/lights.lua',
    'client/presets.lua',
    'client/gizmo.lua',
    'client/placer.lua',
    'client/hud.lua',
    'client/persist.lua',
    'client/input.lua',
    'client/session.lua',
}

server_scripts {
    'server/storage.lua',
    'server/main.lua',
}

ui_page 'ui/index.html'

files {
    'ui/**/*',
    'lists/*.json',
}
