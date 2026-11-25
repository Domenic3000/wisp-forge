# Wisp Forge: Space, travel and the galaxy

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Space and travel
- Space (`scripts/space.gd`, a Node2D under the overlay): levitating into the top of the orbit band
  (`R_SPACE - 9.5`) calls `space.try_enter()` (a party can't leave yet: more than one player blocks it). It takes the
  planet's picture (`main.capture_planet`: one render with the camera at the centre, zoomed so the band fits,
  turned to the view's angle), and from then `_tick` hands over to `space.tick()`: the staff jet (hold cast, push
  toward the aim, mana), the planet's pull fading with distance, a wisp bubble (no breath). The camera stays on you
  at the ground's zoom (user, 20 Nov: no zooming out by itself; 23 Nov: "a zoom in and out feature in space. Not
  auto zoom though": the wheel or - / + choose `space.ZOOMS` 1..8 (`zoom_by`, eased in `_follow`, back to 1 each time
  you leave the planet; `close_view()` is false in space above 1.01, so a live planet is drawn as on the map; the
  mage and skiff are true to scale up to 4x and held at their 4x size past it, overlay `zs`). While any of the orbit band is within the screen's half
  diagonal the live planet is rendered (`live`; space.gd, drawn UNDER the picture, shows its stars past the band);
  beyond it the GPU does nothing (`_process` skips `_gpu_frame`), `view_c` follows `cam_c`, and space.gd draws the
  stars (two depths of drift, so speed shows), the sun (a small disc toward the screen's edge, as in the planet's
  sky) and the other planets (procedural discs from their biomes, `_disc_image`, or the pictures taken as you left
  them, a Sprite2D masked to a disc, placed by the world->screen affine); where things are is on the minimap.
  Back below `R_SPACE - 10` moving inward: `exit()`, a short cooldown. Space shares the world coordinates of `space.home` (the planet the GPU holds, at
  the origin while you're near it: see The galaxy); every planet's place is `Defs.planet_g(i)` (`Defs.SYSTEM`, a
  round of five, is a star system), and `bodies` are the planets of the systems near you. The nearest planet (`near`, `centre`)
  pulls and, close in, turns the view upright (`view_ang`; `main.view_angle()` uses it in space; see "Space's view
  turns only when you turn it"); the skiff's `centre` is set to it so it levels over that planet.
- Travel: once another planet is clearly nearer (`NEARER` of home's distance), `space.travel(i)` saves the old
  world (`save_world_async(without_skiff)`: read back 8 MB a frame by `gpu.read_world_async`, written on a thread;
  the skiff you ride goes with you), then awaits `main.arrive_planet(i)`: `_make_world(i, true)` makes the planet a
  step a frame (`gpu.init_async` for another size: SPIR-V for every shader on a worker thread, then one made on the
  device a frame; `builds.plan` on a WorkerThreadPool task; `gpu.generate_prepare`/`generate_band` two bands a
  frame; settle 2 frames at a time; `travelling` blocks saves and GPU frames meanwhile, `travel_progress` 0..1). In
  test mode `[travel]` prints the slowest step of each kind (`_phase`) and each shader's set-up time. Until it's ready no planet
  can be approached closer than `HOLD` above its orbit band (`_hold`). Then `_reanchor` shifts players, skiff,
  camera, wisp and particles so the new planet is at the origin, its clock is set so its sun stands where the sun
  is (`sun_ang`), its picture is taken, and it is saved (each in a frame of its own; the other planets' discs
  are kept in `_discs`, not made again on every journey). The test allows no frame over 250 ms on the way. `_enter_planet` (title, portals) runs the same
  `_make_world` all at once.
- Asteroids (`scripts/asteroid.gd`, extends pixel_body.gd; `Asteroid.make(seed, radius, kind)`): a lumpy outline
  (harmonics + grain, sometimes stretched), craters bitten from the edge, matter by depth and noise per `KINDS`
  (stony: gravel crust, stone, copper veins, coal, prism crystal deep; icy: snow, ice, frost veins; metallic:
  deepstone, copper, wisp ore deep, so a better staff is needed). Its own light `rebuild` (mass and centre only,
  no room or outline), `take(k)` clears a cell and its pixel (the picture `img` is kept, updated in place),
  `settle_mass` rebuilds keeping every cell where it was, `split_off(idx)` makes a piece a rock of its own,
  `solid_at`, `save`/`from_save` (base64 cells). space.gd keeps home's `rocks` (`_ensure_rocks`: three clusters
  of 2-4 over the orbit band from the planet's seed, or loaded from `planet_state["asteroids"]`; every draw is
  made at once into `_rock_plan`, then one rock is made a tick (`_ensure_rocks(true)` makes the rest now, and
  `rocks_state` does before saving), written by
  `_world_meta` via `rocks_state`; `_reanchor` drops them, they were saved with the old home). Out there:
  `mine` (hold dig: cells within `dig_r` of the reach point, `HARD <= tier`, the brush's rate, into `inv`, dust
  streams to you), `_update_rocks` (drift, spin, rebuild a few frames after digging, `_split` once you stop:
  pieces drift apart, scraps under `ROCK_SCRAP` crumble), `_rock_push` (the mage moved in 2-cell steps near
  rock and pushed back out along the rock's radius), the skiff's own `advance(collide)` against `_rock_solid`.
  The camera frames the nearest rock (`_follow`; `live` stays false up there, judged by height over the
  planet), `_draw_rocks` makes a Sprite2D per rock with the `LIT` shader (a lumpy sphere lit by `sun_ang`,
  self-lit ores bright: their alpha is 250), and a marker points to the nearest. Test mode: `test_dig`.

## The galaxy (scripts/galaxy.gd, space.gd, map_view.gd; user, 22 Nov: "eventually i want space to be infinite with content in space"; "there is no space map")
- Systems: every round of five planets is a star system; system r holds planets 5r..5r+4. `Defs.system_g(r)`: grid cell `spiral_cell(r)` (a square
  spiral from (0, 0); `spiral_index` is its inverse) times `SYS_GAP` (600000) plus a seeded jitter; system 0 is
  at (0, 0), so the first system's planets are where they always were. Galaxy positions are DOUBLES
  (PackedFloat64Array [x, y]): `planet_g`, `system_g`, `g_rel(a, b)` (exact a - b as a Vector2); `planet_pos` is
  only exact near the first system. `planet_local(i)` = the planet's offset in its system.
- Space's origin follows you: space.gd `org` is the galaxy point at (0, 0) out there. Past `RECENTRE` (80000)
  from it (and not `live`) everything out there is moved over (`_shift`: players, skiff, camera, wisp,
  particles, vfx (`vfx.shift`), rocks, bodies, bolts) and `org` with it; back within `BACK_HOME` of home it's
  put back on home exactly (the GPU world needs home at the origin). `home_at()` (home out there), `at_home()`
  (landing and the live planet need it), `galaxy_of`/`local_of`, `player_g()`. Overlay draws only space's
  things while not live, so the planet's objects never show at their old coordinates.
- `bodies` are the planets of the systems within `Galaxy.BODY_R` of you (`_make_bodies` every 30 ticks; each
  has "sys"); a new system's discs grow one a tick (`_grow_disc`, a plain disc meanwhile). With no planet near,
  `near` is {} and "down" stays as it was. Markers: the planets of the system you're in, the three nearest
  other systems, the nearest rock or comet, a waypoint.
- Sectors (`Galaxy.SECTOR` 25000): `sector_content(s)` is grown from (world seed, s): an asteroid field
  (`FIELD`), a great field (`BIG`) or a comet (`COMET`), nothing within `NEAR_PLANET` of a planet. `_stream`
  loads the 3 x 3 round you (`_load_sector`: one rock a tick from `_sect_plan`) and drops sectors past 2
  (`_unload_sector`). Asteroid `sect` (sector key; "" = home's clusters, saved with the world; `home_rocks()`),
  `touched` (mined), `orbit`/`loop_at` (a comet: `Galaxy.comet_at(orbit, game.time)` from its loop's middle,
  so it's where it should be whenever you come; tail by `_comet_tail`). A sector with a mined rock keeps it
  in `sect_state` (rock saves with "rel" from the sector's corner).
- Nebulae: `Galaxy.nebula(gx, gy)` (low-frequency noise: density, colour from a palette); space.gd tints the view
  and drifts dust (`neb`, `neb_col`).
- Charting: `_scan` every 30 ticks out there marks sectors within `SCAN_R` as `seen` and charts systems within
  `CHART_R` (a toast); on a planet `planet_tick` marks its own. `save_state`/`load_state` in progress.json
  "space" (seen, charted, waypoint, sectors). Saving far out still returns you to home's orbit band on load.
- The Starsail (recipe "sail", Travel, `items["sail"]`; `PlayerInput.sail` = Shift): `_sail` runs the skiff up to
  `SAIL_SPEED` (320) the way it's steered, capped by `_clearance` (what's in the way ahead: planets' air or
  storm belts, rocks near the line) / `SAIL_CLEAR`; let go and it sheds the extra speed (x0.96 a tick). Near
  stars streak past at speed; a glow round the skiff.
- The map's "space" tab (map_view.gd `_draw_space`): galaxy coordinates north up, `gc` (centre, doubles), `gz`
  (cells a pixel, `Z_MIN`..`Z_MAX`); WASD/arrows or a drag pan, the wheel zooms about the cursor, + / -, H
  centres on you, a click sets `space.waypoint`, a right click (or Backspace) clears it. The fog and nebulae
  are a small picture made again when the view moves (`_background`); sector grid and explored sectors'
  fields and comets close in; every star (named once charted), a charted system's planets (discs, storm-belt
  rings) closer in; you, the waypoint and a line to it, a scale bar. The HUD says "Deep space" and the nearest
  planet's distance while you're away from home.
- A journey to another planet only begins within `TRAVEL_R` (40000) of it (and clearly nearer than home): far
  out, which planet is "nearer" means nothing, and making one is work.
- space.gd `_world_xf()` is `main.screen_xf()` (built from the view's angle and zoom). It used to difference
  `world_to_screen` at the origin, and far from home float precision put rocks, wrecks and outposts dozens of
  pixels from where they were (the overlay's mage and skiff looked outside a station they were inside).
- Test: `_test_galaxy` ("galaxy"; in the full run right after the skiff's journey to Cindrel): the spiral, the
  Starsail (sailing the way farthest from every planet, home too), recentring, a field streamed in and kept as
  mined, a comet on its loop, a nebula (both chosen 80000+ from any planet, or a journey begins), the chart,
  saving, back home and landing; pictures `galaxy_*.png`. The wild-life checks (`_test_creatures`,
  `_test_ecology`) pass alone but now and then fail in the full run (what earlier checks leave near the start).

## Space's view, loading
- Space's view turns only when you turn it (user, 23 Nov: "the camera keeps reorienting"; 24 Nov: still "spinning
  around on its own especially near a derelict"; "how do we make it so you cant land upside down"): in deep space
  `centre` is 400000 under the VIEW (`p - from_angle(view_ang) * 400000`), and Q / E (`PlayerInput.turn`, main
  `test_turn`; Q / E don't cycle Conjure's material out there) turn `view_ang` by `TURN_RATE` a tick
  (`_manual_turn`). Within `VIEW_NEAR` (4000) of a planet's air `centre` is the planet and `_follow` eases the view
  upright, harder the closer (`near_best`; fully by `UPRIGHT_NEAR` 900), and the turn keys only give a note; at a
  station (`frame_st`) its floor holds it the same way. Physics never follows the view: the pull, the skiff's
  levelling and landing go by the planet. `_align_far` (every 10 ticks) turns stations and outposts that are off
  screen (and not docked at, nor with the skiff beside them) to stand upright in the view, so coming up to one
  never turns it (they were set upright for the view they streamed in with, often near home). `pull` measures
  from the planet itself (`near["pos"]`), not `centre`.
- Loading a game leaves space altogether (space `reset_for_load`, from `start_game`; user, 23 Nov: reloaded by a
  derelict, the station came down with him). Stepping off the skiff out there picks a spot clear of every hull
  (`clear_spot`), `_shortest_out` searches up to 24 cells, and a derelict's dock says it's for drifting in on
  foot (`_dock_hint`).
