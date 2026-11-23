# aty_cinematic

A cinematic director for FiveM: fly a free camera, lay keyframes on a timeline, stage actors and
lights, drop in ready-made camera moves and scenes, and record the result with the Rockstar Editor.

Everything runs on the client of the person filming. Actors and lights are local, so nothing is
synced to other players.

## Features

**Camera**
- Free, orbit and follow rigs with adjustable glide and look smoothing.
- Keyframe timeline per shot: position, rotation, field of view, depth of field, weather and time.
- One speed curve for the whole camera, so it keeps moving through keyframes instead of stopping
  at each one. Per-key easing, including a bezier editor.
- Keys taken in the orbit rig travel on an arc around their pivot.
- Camera path preview in the world.

**Camera shake**
- Presets (handheld, walk, run, vehicle, action, drone) built from fractal noise.
- Tremor that grows with camera speed, and lean: the camera banks into turns, nods when it
  speeds up or brakes, and carries weight on pans and tilts.
- Per shot, or per keyframe with blending between keys.

**Ready-made presets**
- 19 camera moves (push in, orbit, crane, dolly zoom, fly-by, top-down descent and more) that
  build their own keyframes around what the camera frames.
- 12 scene set-ups that place actors, vehicles and lights in one go, each with its own camera.
- 24 atmospheres: weather, time of day, colour filter, wind and rain in one click.

**Actors and lights**
- Peds, vehicles and a clone of yourself, placed with a gizmo or by pointing with the mouse.
- Multi-select: move a group in formation, give everyone an emote, or deal out a mix for a crowd.
- 87 emotes with categories, plus 12 two-person emotes (handshake, hug, punch) that start in step.
- Point and spot lights with colour, range, cone and shadows.

**Output**
- Rockstar Editor recording of one shot or every shot in a single clip, with a lead-in for the
  editor's watermark.
- Framing guides: rule of thirds, golden ratio, safe areas, crop frames for vertical video,
  cinema bars, level and lens readout.

## Requirements

- FiveM server, `lua54`.
- The `aty_lib` bridge library (framework, notifications, key mappings, ped helpers). It is a
  separate resource and has to start before this one.
- Node.js 20.19+ only if you want to rebuild the interface. A built copy ships in `ui/`.

Optional: if `cd_easytime` runs on the server, the director asks it to stop writing the clock and
weather while a session is open through an export named `SetExternalControl(boolean)`. Stock
`cd_easytime` does not have that export; without it the call does nothing and the sync script may
overwrite the time you set.

## Installation

1. Put the folder in your resources directory as `aty_cinematic`.
2. Add to `server.cfg`, after `aty_lib`:

   ```cfg
   ensure aty_lib
   ensure aty_cinematic
   ```

3. Restart the server or run `refresh` and `ensure aty_cinematic`.

Projects are saved on the server in `data/projects/`.

## Usage

Open the director with `/director`. The default keys can be rebound in the FiveM key binding
settings.

| Key | Action |
| --- | --- |
| Right mouse (hold) | Fly and look around |
| W A S D, Q / E | Move, down / up |
| Mouse wheel | Speed (with Shift: field of view) |
| F | Add a keyframe at the playhead |
| Space | Play / pause |
| G | Cursor / fly |
| H | Clean view (hide the panels) |
| Delete | Delete the selected keyframe |
| Backspace | Close the director |

A first shot in four steps: fly to a start pose and press `F`, fly to the end pose and press `F`
again, press `Space` to play it, then use the record button on the timeline to capture it with
the Rockstar Editor.

## Configuration

Everything is in `config.lua`: access, camera feel, shake presets, limits, the Rockstar Editor
lead-in, key bindings and the interface language (`Config.Locale`, `'en'` or `'tr'`).

By default anyone on the server can open the director. To restrict it, set `Config.Access.Ace`
to an ACE object such as `'aty_cinematic.use'` and grant it:

```cfg
add_ace group.admin aty_cinematic.use allow
```

Ready-made content lives in plain data files:

| File | Content |
| --- | --- |
| `shared/moves.lua` | Camera moves |
| `shared/scenes.lua` | Scene set-ups |
| `shared/looks.lua` | Atmospheres |
| `lists/anims.json` | Emotes |
| `lists/shared.json` | Two-person emotes |
| `lists/peds.json`, `lists/vehicles.json` | Models offered in the Actors panel |

## Building the interface

```bash
cd web
npm install
npm run build
```

The build writes to `ui/`, which the resource serves.

## Known limits

- Actors are static: they stand where you put them and play an emote. There is no path recording
  for peds or vehicles.
- The game's entity outline is deliberately not used to mark a selected actor. On a ped it
  crashes the game, so selection is drawn with lines instead.
- The distances of the two-person emotes are estimates; the panel has a slider to adjust them.

## License

MIT. See [LICENSE](LICENSE).
