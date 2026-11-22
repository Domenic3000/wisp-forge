# Wisp Forge: notes for development sessions

Godot 4.7.2 game, a pixel-simulated mage on a round planet. The whole world is simulated in GLSL
compute shaders through a local RenderingDevice. The roadmap and design decisions live in the
claude.ai project doc `claude/roadmap-and-decisions.md`.

## Layout
- `game/` is the Godot project (no imported resources, no `class_name`; scripts are preloaded, `Defs` is an autoload).
- `game/scripts/defs.gd`: materials, biomes, planets, spells, recipes, enemies, sprites. `glsl_prefix()`
  generates the GLSL tables, so CPU and GPU always agree. `NM` is the material count.
- `game/scripts/gpu_world.gd`: shader compile (custom `#include "name"` from `shaders/inc/`), buffers,
  generation, `step()`, `stamp()`, `settle()`, save readback.
- `game/scripts/buildings.gd`: procedural structures (blueprints stamped by `shaders/stamp.comp`).
  Deterministic per planet, and re-planned on load for labels and guards. Bump `GEN_VERSION` in main.gd when it changes.
- `game/scripts/main.gd`: game loop, physics, spells, enemies, chests, guards, saving.

## Planet geometry (per planet)
- `Defs.set_geometry(radius)` lays out the shells ("rings") for a planet's mean surface radius
  (`Defs.make_planet(i)["radius"]`: every planet is `PLANET_SCALE` (1.5) times the size it was first designed at;
  classic Verdance 1956). Rows count down from the top of the atmosphere (`R_TOP` = radius +
  `ATMO`, row 0) to `R_IN`; the orbit band above the atmosphere has NEGATIVE rows (-`ORBIT_ROWS`..-1) up to `R_SPACE`.
  Shells are stored top to bottom (`SH_Y0`/`SH_Y1`/`SH_N`/`SH_OFF`; every `SH_Y0` even). The surface shell (`SURF`,
  `NS` columns = square cells at the mean surface, a multiple of 64) reaches `SURF_HALF` (330) rows up and down, so
  the ground lies in it. Above and below it the shells are thin (`SEAM_STEP` 0.021: each has about 2% more or
  fewer columns than its neighbour, multiples of 16; under 3.2% above radius 320, larger only near the heart), and
  every shell's cells are square at its middle, so the view never visibly changes size at a seam (the user saw a
  2x squeeze at the old halving seams). Classic Verdance (1956): 139 shells, about 22 M cells (a 175 MB raw save). Neighbours across a seam: `colTo(from, to, x)`
  (the cell whose middle is nearest; GLSL and `Defs.col_to`), `stepC`/`nbr`, `shAbove`/`shBelow`; a surface column
  in shell s: `colIn` / `Defs.col_in`; a cell of the read-back world: `Defs.raw_idx(row, surface col)`. `shellOf` /
  `shell_of_row` binary-search the shells. Use `floor` for rows (they go negative). In scripts use `Defs.NS` (typed)
  for surface columns.
- The geometry and shell table are a buffer, not compiled in: `Defs.shell_table()` (binding 10 in every uniform
  set, added by `gpu._mkset`; common.comp `SHL`, macros `R_TOP`, `RS0`, `R_SPACE`, `ROWS`, `NSH`, `SURF`, `NS`,
  `SH_Y0(s)` etc.). Constant arrays indexed per cell made NVIDIA copy them for every cell (simulation 38 ms a frame);
  and with nothing planet-specific in the SPIR-V, a planet of another size reuses the driver's cached pipelines.
- Simulation passes are one dispatch per window (not per shell): rows `pc.a.y..pc.a.z`, the window's start angle and
  span in `pc.d.x`/`pc.d.y`; each thread works out its shell from its row (`winCount`/`winX0`). `move` never pairs
  rows across a seam; `boundary` moves powder, liquid and gas across every seam in the window (each inner cell owns
  the 1-2 outer cells over it; straight down, or diagonally into the inner cell beside, so piles have no step at a
  seam; every inner write is an `atomicCompSwap`, outer cells are written only by their owner); `topple` runs a thread per column per shell and drops a block across a seam by
  `atomicCompSwap` on the cell below. The unrolled view's scale (`main.unroll_step`) is the row-weighted average of
  the shells' column steps within `UNROLL_EASE` rows: exact inside a shell, smooth across seams.
- Worlds per game: `Defs.world_seed` (picked at a new journey in `start_game`, kept in progress.json; 0 = the
  classic hand-made system of `PLANETS`/`SYSTEM`, which the test mode plays so its checks stay repeatable).
  `Defs.make_planet(i)` = `make_planet_for(world_seed, i)` (cached, a fresh copy each call; the title's slot list uses
  a slot's own seed). `_grown_planet`: planet 0 is always "temperate" (a friendly start biome), the others of
  `PLANET_KINDS` (volcanic, ocean, desert, marsh, frozen, wild) in a seeded order: biomes from the kind's must-haves +
  weighted pool, shuffled, each with its own width (`"starts"`: fractions round the planet; `Defs.biome_starts`,
  `biome_mid`, `biome_index_at`; params P.p[24..25] for surface.comp), radius/sea/lava/rich/magma/sky from the kind's
  ranges (any ocean means a sea), a name from parts (`NAME_A/B/C`, unique in the round), a description from its
  commonest biomes, and `"guardians"`: which biomes have a lair (2 on the first planet, 2-4 on the rest of its round,
  2 more each round after; classic planets have none listed = every biome). `planet_pos` grows the round's places
  (46-74 thousand from home). The planet seed stays under 2^24 (it goes to the GPU as a float).
- A planet of another size re-creates the GPU world (`gpu.cleanup()` + `init()`) in `_make_world`. buildings.gd takes
  `N0` from `Defs.NS`. Depths that scale with size: `magmaR` (make_planet), the core radius (surface.comp).
- Stamps and `read_rect` go in CELL FOR CELL at any depth (the user wants buildings built down or underground to keep
  exactly their width and shape): a blueprint is laid out in surface columns, and in every shell column k of it
  (counted from its anchor) is the cell `stampLeft(n, ax, aw) + k`, centred on the anchor's middle (GLSL `stampX`/
  `kOf`, `Defs.stamp_x`/`stamp_pos`/`stamp_k`/`k_of`; the identity in the surface shell). A side can step about a
  cell at a seam, never more for an ordinary building. The anchor: a generated structure's own (x0, w; `BP.ax/aw`
  when parts must line up, a dungeon's gatehouse uses its halls'; saved in structs, infos, doors, labels);
  anything else is anchored near you, `Defs.anchor_c` (your surface column, moved only right after the stamps are
  flushed in `_gpu_frame`, or at a tick with none waiting), the default of `gpu.stamp` ("ax"/"aw" keys),
  `gpu.read_rect(..., ax, aw)`, `Defs.raw_idx(row, col, ax, aw)` and `Build.cell_pos`/`cell_of` (build mode, chunks,
  furniture). Anything that keeps cells for later keeps its anchor: doors (`_door_rec`, saved), home (`"ax"`), build
  mode's drag start is kept as a world point.
- Vacuum (react.comp, row < 0): fire and gases vanish, water freezes, mud dries, lava sets; no weather; the mage
  holds his breath above `R_TOP + 4`. Bodies are held below `R_SPACE - 8` (the space map comes later).
- Render: above `R_TOP` the sky is drawn unless the orbit band has something there (`orbitEmpty`).
- The parallax background (render.comp `skyColor`; user, 22 Nov: "make the background look higher detail and
  fade into each other better"): far mountains (ridged noise at 0.12 of your speed, crests lit on the sun's
  side by their slope, rock strata, snow over a ragged snowline, a pale crest line), far hills (0.25) and near
  hills (0.5) with the tree line (each tree shaded by height and sun side, leaves speckled, pines in tiers,
  ragged crowns). Hills take the colour of the biome's top ground (`palColor` of P.p[8 + 2b].z) mixed with
  the haze; each layer is mottled in its own coordinates (so its detail drifts with it) and misted toward
  its foot where a nearer layer rises in front (`mist`, 26-40 rows), so layers fade into each other.
- The view (user, 20 Nov: "switch from bent strips to world coordinates"): the close view is the world as it is
  (setting "view": "world", the default), turned so up points away from the planet's centre, a pixel always
  `zoom` world units, so nothing squeezes going up or down; the horizon curves a little. `_write_frame_params`
  locks the camera to a corner of a cell of the shell it's in and turns the view to that cell's column, so moving
  a cell moves the picture exactly a cell (no shimmer). `main.close_view()` (zoomed in, not out in space with the
  planet out of sight): sprites upright, snapped to whole SCREEN pixels (overlay `_snap`; user, 21 Nov: snapped
  to whole game pixels a standing foe hopped a cell against the ground as you walked); open doors are turned
  with the world under them (`_sprite(..., turn)`), so they lean with their house. `main.unrolled()` = close view AND the "unrolled" setting:
  the old strips (screenToWorld branch on P.p[122].w bit 1; `unroll_step`). P.p[122].w bit 2: past `R_SPACE` the
  picture is clear (out in space and on the map), so what's under it shows (space.gd's stars, the clear colour).
  The picture is drawn a CELL a pixel (bit 4, `cellPicToWorld`: picture row j = cell row y0 + j in its own shell's
  columns counted from the one under the camera; `main._cell_rows` fills P.p[ROWT + j] = (N, that column, how far
  into it the angle is) in doubles, once) and the view's shader (`main.VIEW_SHADER` on `view_rect`, uniforms set
  by `_show_pic` from the picture actually on screen) finds for every SCREEN pixel its world point, its cell and
  that cell's picture pixel: cells keep their true shape (6 or 7 screen pixels for 6.6), none drawn twice or
  dropped. (Sampling the world a unit a pixel did that wherever cells aren't exactly a unit wide: the surface
  shell's are up to 17% off at +-330 rows, and the doubled columns showed as bands that stayed put as you
  walked; the user saw them.) The picture is the screen plus a margin (`gpu.PW/PH/PMX/PMY`, P.p[123]); light,
  readback and chunk colours index it by `main.world_to_pic` / `screen_to_pic`. Below radius 900 (the curve
  bends the corners past the margin), on the map and in the unrolled setting it is drawn as before ("mode" 0).
- The map (M, `main.open_map`; state "map", the game waits): "planet" renders the planet zoomed out (`map_zooms()`:
  4, 10 and one that fits the whole planet with its band; turned to `map_ang`: A/D or a drag; W/S or the wheel
  zoom), `scripts/map_view.gd` draws the markers (you, the party, home, the skiff) and, on Tab, "system": the round
  of planets laid out round their middle (`space.disc_texture`), the one you're on marked. The play camera never
  zooms out any more (zoom_levels[0] = 1); closing hides the picture until one from the play camera is back.
- Space (`scripts/space.gd`, a Node2D under the overlay): levitating into the top of the orbit band
  (`R_SPACE - 9.5`) calls `space.try_enter()` (a party can't leave yet: more than one player blocks it). It takes the
  planet's picture (`main.capture_planet`: one render with the camera at the centre, zoomed so the band fits,
  turned to the view's angle), and from then `_tick` hands over to `space.tick()`: the staff jet (hold cast, push
  toward the aim, mana), the planet's pull fading with distance, a wisp bubble (no breath). The camera stays on you
  at the ground's zoom (user, 20 Nov: no zooming out). While any of the orbit band is within the screen's half
  diagonal the live planet is rendered (`live`; space.gd, drawn UNDER the picture, shows its stars past the band);
  beyond it the GPU does nothing (`_process` skips `_gpu_frame`), `view_c` follows `cam_c`, and space.gd draws the
  stars (two depths of drift, so speed shows), the sun (a small disc toward the screen's edge, as in the planet's
  sky), the other planets (procedural discs from their biomes, `_disc_image`, or the pictures taken as you left
  them, a Sprite2D masked to a disc, placed by the world->screen affine) and markers at the edge pointing to each.
  Back below `R_SPACE - 10` moving inward: `exit()`, a short cooldown. Space shares the world coordinates of `space.home` (the planet the GPU holds, at
  the origin while you're near it: see The galaxy); every planet's place is `Defs.planet_g(i)` (`Defs.SYSTEM`, a
  round of five, is a star system), and `bodies` are the planets of the systems near you. The nearest planet (`near`, `centre`)
  pulls, sets the zoom, and turns the view (`view_ang`, eased; `main.view_angle()` uses it in space); the skiff's
  `centre` is set to it so it levels over that planet.
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
- Pixel bodies (`scripts/pixel_body.gd`, RefCounted): the general flying/drifting object made of cells (material
  + variant per cell in a w x h grid, body coords x along the nose, y down; `pos` = centre of mass, `ang` the +x
  axis's world angle, `facing` -1 mirrors). `rebuild` (mass, `com`, `outline`), `to_world`/`to_body`, `texture()`
  (palette colours, glass see-through), `carve` (damage), `pieces` (joined-up parts). The skiff uses it; asteroids,
  enemy ships and wrecks are meant to. Room inside: `rebuild` floods from the grid's edges through everything that
  isn't hull (`outside`); what the hull closes in is `room`, a place to build: `place(i, j, m, back)` (front blocks
  only into empty room cells, marked `made`; back layer `bg`/`bgv` anywhere in the room) and `remove` (only what was
  built; the hull comes away by `carve`). The `outline` it collides by is only cells touching the outside, so
  building inside never changes how it collides; `keel` is its lowest outline point. `save_cells`/`load_cells`
  pack all five layers (saved in `planet_state["skiff"]["cells"]`). `back_texture()` is drawn behind the riders.
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
- The Wisp Skiff (`scripts/skiff.gd`, extends pixel_body.gd; `Skiff.make(seed)`): grown from parts (`_hull`, `_trim`,
  `_engine`, `_fin`, then `_canopy`: a timber frame and glass shell around an open cabin with a glass back pane, the
  body's room), two seats on the cabin floor (`seat_cells`, `riders`, pilot first). `steer(input)`: the movement keys
  (over the planet below: left/right, W/space up, S down) plus, holding cast, toward the cursor. `fly(want, piloted,
  g, in_space, cruise, drag)`: piloted in the air it eases to `want * cruise` (`ACCEL`) or, hands off, to a hover
  (`BRAKE`; within 10 cells of the ground it settles onto it; coming down near the ground it slows); `CRUISE` in the
  air, `CRUISE_HIGH` above it, extra speed shed quickly in the air; nobody at the controls it falls with drag; in
  space thrust adds to its speed. The hull stays level over `centre`'s ground, tilted into climbs and dives on a
  spring (`omega`); `facing` flips when steered the other way and `look` eases through it (overlay squashes the
  picture by `look * facing`). `advance` (moves in sub-steps, colliding its outline through main's collision
  grid via `collide`, which slides with friction; then `clear_below`, the air under the keel). Forged at the Wisp Forge (recipe "skiff": `items["skiff"]` is its seed); K `call_skiff`
  sets it down beside you; F (`_skiff_interact`, before chests and doors) boards or steps out; riders follow their
  seat (`_ride`: no casting or digging aboard, its air to breathe). main `_update_skiff` flies it on the planet;
  flown out of the top of the orbit band it takes everyone into space (`space.try_enter` needs the whole party
  aboard), and space.gd flies it out there. Saved per planet in `planet_state["skiff"]`; overlay `_draw_skiff`.
  Drawn by `_skiff_xf`: turned with the ship but one body cell to one pixel (never a map taken straight from the
  world: the close view's columns widen with height and would stretch it); its riders are drawn inside that
  transform (`_draw_mage(..., place)`), so they sit and turn with it. Air drag 0.97 a tick below `R_TOP` (none above);
  coming back from space it sheds its speed to 8 a tick, and glows coming down fast through the air.

## The galaxy (scripts/galaxy.gd, space.gd, map_view.gd; user, 22 Nov: "eventually i want space to be infinite with content in space"; "there is no space map")
- Systems: every round of five planets is a star system; system r holds planets 5r..5r+4 (so a Core Drive's
  reach, index + 1, leads on to the next system out). `Defs.system_g(r)`: grid cell `spiral_cell(r)` (a square
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
- Test: `_test_galaxy` ("galaxy"; in the full run right after the skiff's journey to Cindrel): the spiral, the
  Starsail (sailing the way farthest from every planet, home too), recentring, a field streamed in and kept as
  mined, a comet on its loop, a nebula (both chosen 80000+ from any planet, or a journey begins), the chart,
  saving, back home and landing; pictures `galaxy_*.png`. The wild-life checks (`_test_creatures`,
  `_test_ecology`) pass alone but now and then fail in the full run (what earlier checks leave near the start).

## Progression and climate (user, 20 Nov: fewer towns unless it's that kind of planet; the progression pass)
- Settlement: `Defs.CLIMATES[kind]` "settle" scales buildings.gd's structure count (26 per 8192 columns x settle:
  Verdance 0.5, a "realm" world of kingdoms 1.35), "towns" multiplies town and castle weights in `_try_place` (and
  gives a realm towns in biomes that had none), "ruin" shifts how many lie in ruins. `Defs.climate(pl)` fills every
  key (buildings `_clim`, main `clim`). Planet kinds: `PLANET_ORDER` (volcanic, ocean, desert, marsh, frozen,
  wild, realm); the classic five are temperate, volcanic, ocean, desert, marsh.
- Travel is gated: `main.skiff_reach()` (`items["reach"]`, saved; a save from before keeps every planet it has a
  world file for) is the highest planet index the skiff can fly to. The Core Drive (recipe "drive": 30 Planet
  Core, 12 Star Iron, 10 Wisp, plus `Defs.DRIVE_ORE` of this planet's own ore if it has one: `main._refresh_recipes`
  rewrites its cost in `_make_world`; needs the Core Siphon, tier 4, which needs Vulkhar's Ember Heart, and the skiff)
  raises it to this planet's index + 1. space.gd `reachable(i)`: `_maybe_travel` never starts for a planet out of
  reach. NO INVISIBLE WALL (user, 20 Nov): such a planet is wrapped in a STORM BELT (`_storm`, `BELT_IN`..`BELT_OUT`
  above its orbit band, coloured by its kind's `CLIMATES` "belt"): `_draw_belts` shows a shimmering curtain at its
  outer edge and a haze inside; in it the wind pushes outward (0.03 + 0.85 f^2 a tick, f = how deep, 0..1), takes
  speed coming in, gusts sideways, blows sparks past, and lightning strikes (`_strike`: hurts, knocks out, flash,
  shake, "zap"; at f >= 1 a great bolt throws you clear). Full thrust stalls about halfway in. `_hold` is only for
  a reachable planet still being made. Markers and the map's system chart (a dashed ring) say "storm belt: needs a
  Core Drive". STAR IRON (material 50) is only in asteroids (asteroid.gd: metallic rocks' hearts, a speck in stony
  ones).
- GPU counters: `Defs.CNT` (128) per player, one per material below `C_HARD` (112), then `C_HARD`, `C_PLACED`,
  `C_FALL_N`/`C_FALL_MAX`, `C_CHEST_OPEN`, `C_CHEST`, `C_CREAK_N`/`C_CREAK`, `C_FOG`, `C_FELL_N`/`C_FELL`,
  `C_TREASURE` (also #defines in every shader). They used to start at 50, so digging what the staff couldn't cut
  counted as star iron; a save without "cnt": 2 has its star iron zeroed on load. Materials must stay below 112.
- Each planet kind's own ore (`Defs.KIND_ORES`, materials 51-57: Fire Opal volcanic, Abyss Pearl ocean (seabed
  only, 30+ under the sea), Sunstone desert, Bog Iron marsh, Rime Crystal frozen, Amber wild, Silver realm; temperate
  has none): gen.comp `strata` lays it as veins in its host ground at its depths (P.p[126] = material + 3 hosts,
  P.p[127] = depth from/to, threshold, 4th host + 1000 for seabed only; set in `gpu.build_surface`). Guardians'
  hoards hold 16 of the planet's ore, wardens' 6 (`_hoard_ore`), chests a little.
- Ore gear is DATA (`Defs.GEAR`, three pieces per ore; the forge's "Ore Gear" via `Defs.gear_recipes()`): each
  piece's "mods" are stat -> multiplier (or an amount for `GEAR_ADD` stats), and main `gear(stat, m)` combines what
  m owns; every stat is read in ONE place: dig_rate (excavation brush B.z), breath (`_apply_gear`), dmg_taken and
  knock (`hurt`), mana_cost (`_cast`), lava_dmg, swim, speed, jump, levitate (`_update_player`), reach (`_reach`),
  draught_heal (`_drink`), spell_spark/spell_fireball/spell_frost (`_impact`), undead_dmg (`_hurt_enemy`: skeletons,
  archers, wardens), calm_wild (`calm_foe`: foe_ai `think` and contact damage skip an unprovoked creature; any hurt
  sets `Enemy.provoked`), light (a light that goes with you). max_hp, max_mana, mana_regen and dig_r are applied once
  in `craft`. A new piece needs only a GEAR entry (and a stat hook if its stat is new). `recipe_hidden`: a piece
  stays out of the forge until its ore is found (`ore_found`: held some, or `items["found_<mat>"]`), except each
  ore's first, shown locked with where it's found. ALLOYS: a GEAR entry whose "ore" is a list of two (bound with
  6 Star Iron; `Defs.gear_ores(id)`; the forge's "Alloys"), shown locked once either ore is found. Test: `_test_gear`
  ("gear").
- Hazards (`Defs.HAZARDS`, CLIMATES keys "cold" frozen, "sun" desert, "miasma" marsh, "deep" ocean; main `_hazards`
  / `_hazard_level`, local player only, `hazard` = the one hurting you now): cold under the open sky (x1.6 at night,
  x1.6 in wind; a fire, torch or lava within ~14 cells, `_near_warmth`, keeps it off), sun under the open sky when
  `sun_overhead` > 0.72, miasma in fog (`m.fog` > 0.25) near the ground, deep in liquid 35+ under the sea's level (the Abyss Pearl beds).
  Each is borne by a ward (Wards: Hearth Charm, Sun Veil, Fen Mask, Tide Charm; `items[id]`) or a guardian's relic
  (rimefang, sunidol, pearl, tidefin: relics are keys past hazards). Volcanic heat stays the Heat Ward's (or the
  Cinderheart's).
- Skiff upgrades (Travel): Star-Iron Engine (`items["engine"]`: `skiff.power` 1.5, thrust and top speed in space,
  cruise in the air), Prospector's Beam (`items["beam"]`: the pilot holds dig in space, space.gd `_beam` mines
  asteroids within `BEAM_REACH` of the skiff via `_mine_at`; drawn as a line to `beam_to`).
- Climate per kind (`CLIMATES`): "storm" (how often it rains, lightning), "wind" (main `wind`, gusting with the
  storm, turning with each spell of weather; pushes you while `exposed`, i.e. `_open_sky`: nothing solid 6-72
  cells over you, above the ground), "heat" (volcanic: the open air hurts 0.012 a tick without the Heat Ward or the
  Cinderheart), "freeze" (frozen: P.p[125].x, react.comp ices open water over from the top near the surface),
  "fog" (marsh: P.p[125].w, clouds.comp `groundFog` in the lowlands), "dust" (desert: dust storms in clear-weather
  biomes), "wild" (wild: creatures spawn more often). `_update_climate` blows snow (a blizzard), sand or embers
  across the view as particles. Prism Crystal is rarer (gen.comp thresholds, chest loot), and so are draughts in
  chests (0.1 + rare x 0.3).

## Weather you can tell apart (scripts/weather.gd; user, 22 Nov: "a hail storm that looked the same as rain ... weather patterns need distinct art")
- main `weather` (a Node2D in `pix` after vfx): its own particles in packed arrays, whole game pixels, lit by
  `gpu.light_at` (embers unlit), each kind with its own look and landing: RAIN thin slanting streaks + SPLASH,
  HAIL 2-3 px stones (white core, pale-blue edge, dark rim) that bounce twice (CHIP), then lie melting, SNOW
  swaying dots and crosses that rest a moment, ASH dark tumbling flakes, EMBER flickering sparks rising, DUST
  streaks along the wind. `emit(kind, n, br, bd, wind)` brings them in at the top edge (and the windward side);
  `_hit` steps a cell at a time against the collision grid (solid, powder or liquid), so a roof keeps them off.
  `CAP` per kind, `stats` (hail_bounces, rain_splashes, landed) for the tests.
- main `_weather_fx` (from `_update_climate`, near the surface only, not in space or on the map) says what
  falls: the biome's "weather" while `sky_rain` is up (the GPU's rain, snow and ash cells still fall too:
  real matter), a blizzard in wind, dust storms, embers on a hot world, the sandstorm and hail events.
  A hail storm drops NO rain cells (P.p[3].x 0: render.comp draws a falling drop pale, just like a hailstone),
  only weather.gd's stones, with a cold haze (`sky_tint`); a sting cracks a stone on your hat.
- Test: in `_test_sky` (hail: stones bounced and lay, no rain cells; rain: splashes; `sky_rain.png`).

## Sky events (main.gd `_update_sky_events`; user, 20 Nov: "weather and sky events for each kind of planet")
- `Defs.SKY_EVENTS`: meteors, eruption, squall, sandstorm, wisps, aurora, hail, bloodmoon, fireworks, each with a
  weight per planet kind ("kinds"), "when" (night/day/any), "dur" and a message. Every `SKY_EVENT_EVERY` ticks a
  `SKY_EVENT_CHANCE` roll picks one (`_pick_sky_event`; never in test mode); `start_sky_event(id)` /
  `end_sky_event()` (also in `_make_world`); `sky_ramp()` fades it in and out over 5 s; `sky_level(id)` is the
  GPU's share (P.p[125].y aurora, .z blood moon: render.comp `skyColor` draws the aurora's curtains by screen row
  and reddens the night and the moon). State: `sky_ev`, `sky_t`, `sky_dur`, `_sky_next` (ticks to its next
  meteor, bomb, strike, rocket, hail sting), `sky_wind` (added to the climate's wind target), `sky_tint` (overlay
  draws it over the view), `sky_fx` (overlay `_draw_sky`: "streak" shooting stars, "bolt" lightning, "rocket"),
  `sky_wisps`, `sky_vent`, `sky_stats` (counts for the tests).
- Doings: meteors (streaks; `meteor_fall(cells)`: PROJ "meteor" from high up, `_meteorite`: a blast, fire, a lump
  of MAGMAROCK round a few cells of STARIRON at the crater's bottom (so it rests on ground and no chunk carries it off; about 4: asteroids stay the real source), hurts anyone close), eruption (`_eruption_vent`: the highest of a few spots
  110-220 cells off; smoke, glow, rumbles, PROJ "lavabomb" (splat lava) every 22-45 ticks), squall (gale, rain,
  `lightning_strike(cells)`: a drawn bolt, fire, hurts within 12), sandstorm (gale, haze, blown sand), wisps (5
  drifting lights, shy of you; touching one gives 4 Wisp Ore and 30 mana), aurora (mana regen x2 under the open
  sky), hail (weather.gd stones; a sting every 35-70 ticks in the open), bloodmoon (`spawn_mult` 2.5, up to 12 foes),
  fireworks (rockets that burst into coloured particles). The HUD's weather shows the event, then " · <hazard>!".
  Test: `_test_sky` ("sky").

## Living towns (scripts/towns.gd, folk_art.gd; user, 20 Nov: "towns with people walking around and shops"; then their days, requests, trades per kind)
- buildings.gd `_town` records each village in `towns` ({x0, w, name, ruined, living (not ruined), seed, biome,
  houses: [{role, x0, w, floor (the ground floor's row), ruined}]}; `_cottage` leaves its house in `_house`); a
  standing village gets a name from parts (`town_name`, its own seed: nothing else moves) instead of "Deserted".
- towns.gd (main `towns`, ticked on the planet): `_people` every 30 ticks fills a living village within `NEAR` columns
  (`_fill`) and drops it past `FAR`: a keeper per shop/smithy/tavern/inn (in the middle of its ground floor, always
  there; the smith throws sparks by day) and its residents (two per home, one living over each other house, that
  house their `job`; `MAX_FOLK`), each put where `want_place(v, hour)` says: home asleep 22-6, some still in bed
  before 7, the job 9-16 (three in four), the tavern of an evening if there is one, else the street. `hour_at(p)`
  is the local hour (noon = sun overhead; `time_for_hour` for tests). main `Villager` (a Body): seed -> look
  (folk_art.gd `frames`: a 13 x 21 figure from parts; overlay caches "folk_<seed>_stand/walk0/walk1") and name
  (`name_for`); `inside` (a house dict or {} = `STREET`), `job`, `asleep`, `fade` (`_step`: they fade out at a
  house's side and in at `fade_to`, going in, out, or PAST a house in the way: houses block the street; stuck for
  90 ticks they step to where they're going). `_walk`: keepers face you; in the street residents wander the
  village, turn at walls and drops, run from foes; indoors they potter about the room; overlay draws a sleeper's
  drifting "z"s. F (main `_interact`, after chests): `talk` — a keeper takes a letter that's for them
  (`_deliver_to`) or opens the shop (state "shop", the game waits; ui.gd `show_shop`, F/Esc leave), the asker deals
  with their request, anyone else says `line_for` (a greeting and a rumour: the nearest living guardian and its
  lair, a crypt, this world's ore, its hazard and ward, the village's shops, or village talk; sleepers grumble),
  drawn as a speech bubble (overlay `_bubble`).
- Requests: one resident per village is the asker (`asker_index`: from the village's seed and `planet_state["req_n"]`
  (done there), so it moves on), marked by overlay `_folk_mark` from `mark_of` (gold "!" offer, grey "?" under way,
  gold "?" done). `make_request` (seeded the same way): "fetch" (`Defs.FETCH` material and count), "hunt" (2-4 of
  a `Defs.creatures_of(village biome)`, counted by `on_kill` from main `_kill_enemy`), "deliver" (a letter to the
  shop or tavern keeper of another living village). F shows it, a second F `take`s it (into
  `planet_state["requests"]`, `Defs.MAX_REQUESTS` at once; the HUD lists them by `short`), talking to them again
  hands it in (`_finish`: coins, a Healing Draught one time in three). Test: `_test_requests`.
- Trade: `shop_def` = `shop_def_for(role, planet kind, planet seed)`: `Defs.SHOPS[role]` ("sell": give/potion/meal/
  rest/chart/item (an `items` key, a ward)/heat_ward/spell; "buy": material -> [how many, coins]; the smithy also
  buys every world's ore) plus `Defs.KIND_TRADE[kind][role]` (each world's ward for its danger, its fare, the Heat
  Ward on volcanic, Silver and the Scroll of Mending in a realm) and, at the smithy of a world with its own ore, an
  imported ore (`Defs.IMPORT`, picked by the seed) and a better price for its own (`Defs.OWN_ORE`, "own_ore").
  `buy`/`grant`/`owned` (a ward you have shows "yours")/`sell`; coins in `items["coins"]` (from chests, guardians
  60, wardens 30, requests, selling). "chart" puts the lairs and crypts in `planet_state["charted"]`, which the map
  draws; villages you've been to (`planet_state["towns_seen"]`) are on the map too.
- Sleep: buildings.gd `_furnish` records each bed it places (`_beds`: {c, w, row, flip}, from `_place_prop`'s
  `_last_flip`) into its house's "beds" (no rng drawn, so layouts don't move); towns.gd gives each resident one
  (`v.bed`). Asleep at home they `_lie_down` (in their bed if the collision grid still has furniture there, the
  head at the pillow end; else on a bedroll on the floor), `lying` (no physics), `_get_up` at `wake_at` in the
  morning; overlay `_lying` draws them turned a quarter (whole pixels) under a quilt, "z"s from the head.
- Keeping apart (user, 21 Nov: "villagers standing on top of each other"): `_spot_in`, the street placement and
  `_new_goal` pick spots clear of others (`_taken` / `_clearance`, which counts where someone stepping through a
  door is about to come out, `_spot_of`, and chests); someone standing still on top of another steps aside
  (`_crowd_side`, checked every 12 ticks). A sleeper never lies over a chest: a bed with one in front of it
  (`_chest_near`), or already taken, means the floor, and a bedroll goes on the roomiest bit of floor. The overlay
  draws the folk before the chests (`_draw_folk`), so a chest is never hidden behind one.
- Memory: `planet_state["folk_known"][seed]` = {met, helped}, `["town_rep"][town seed]` = {n, last}: `_hello`
  (a stranger introduces themselves, a friend you helped greets you so, a village talks of what you did),
  `knows` (overlay name tags of folk you've met), `price_of` (5% off a village's shops per request done there,
  a quarter at most; the shop shows it).
- Tests ("towns"): `_test_towns` (walk, talk, trade), `_test_town_days` (home, in bed and asleep at night, out in
  the morning; a picture `town_night.png`), `_test_requests` (and being remembered), `_test_kind_trade` (every
  kind's stock is real, and its danger's ward is sold).

## Workshops (scripts/workshops.gd, workshop_art.gd; user, 22 Nov: real kilns and smelters, a small bonus for forging in a proper workshop, "some secrets that can be discovered through experimenting")
- A station is an OBJECT (main `Station`, a Body like `Chest`; `new_station(kind)`), not cells: `Defs.STATIONS`
  (kiln, smelter, still, anvil: size, "burn" fuel a tick, "spark" chance, build cost). Set down from build mode's
  Workshops tab (`Build.CAT_WORKSHOPS` 7, kind "station": on level ground, not on another; one taken up,
  `items["st_<kind>"]`, sets down free); Shift + right-click takes it up with what's in it (`take_at`). Saved in
  `planet_state["stations"]` (`save_to` in `_world_meta`, `load_from` after `_make_chests`). Drawn by overlay
  `_draw_stations`: body lit by the world, fire layer unlit and flickering (`_sprite(..., glow)`), a Still's jar
  tinted by what it brews.
- F beside one (`interact`, after the villagers) opens its panel: main state "station" (the world waits, but
  `work_all` keeps running so you watch it), ui.gd `show_station`/`update_station`/`_render_station`: load from
  the satchel (left 1, right 10), feed the fire (`Defs.FUEL_TICKS`: coal, wood, planks...), take back, take out,
  and "It makes" (secrets as riddles heard, or "?").
- Working (`_work`): what's loaded must be EXACTLY the kinds of a `Defs.PROCESS` entry (enough of each); a mix it
  doesn't know does nothing. Then it burns fuel, warms (`heat`, 4 s from cold) and works batch after batch at
  its heat into `out` ("m<mat>", "potion", "d_<draught>", "gear:<id>"). "night": only after dark. A secret's
  first batch is a discovery (`items["secret_<id>"]`, toast, burst); hints (`items["hint_<id>"]`) come from
  villagers (towns.gd `line_for` topic "secret") and torn notes in chests (`hint_note`).
- Real fire (`_fire`, near a mage): smoke, embers, a light, and every `SPARK_EVERY` ticks a chance (`_spark`)
  that a spark lights anything that burns just beside it (FIRE brushes). In water it goes out ("wet").
- Refined materials: COPPERBAR 58 and WISPBAR 59 (Smelter only, `PLACE` 0; NM 60). Glass and roof tiles are
  fired in the Kiln now (no forge recipe); many recipes take ingots (Copper Focus, Levitation, Fireball,
  the skiff, wards...).
- Secrets: kiln obsidian (ash + sand) and grown prism (glass + glowcap); smelter Wispsteel Band and Starsteel
  Edge (`Defs.WORK_GEAR`, "once", read by `gear()`, `own_work_gear`); still draughts (`Defs.DRAUGHTS`: Ember,
  Swiftfoot, Mana, Moonlit at night), drunk from the satchel (`drink_draught`), working through `gear()` while in
  `Mage.buffs` (new stat "fire_dmg" in the hazards).
- Masterwork: ore gear forged within `ANVIL_REACH` of an anvil station (`anvil_near`) keeps `items["q_<id>"]`
  (`MASTERWORK` 1.25): `gear()` scales its mods ((mod - 1) x q + 1, an added stat x q), the once-applied ones too.
- Test: `_test_workshops` ("workshops": on a natural slab in the air; pictures `workshops.png`,
  `workshop_panel.png`).

## Shaping the world is magic (user, 22 Nov: "tie excavating and removing blocks to mana ... everything ideally would be tied into the fact that we are using magic including vfx")
- Mana per cell, harder costs more: main `dig_mana(t)` = `DIG_MANA` (0.08) x (1 + 1.5 x HARD) x gear("mana_cost");
  `_apply_counts` spends it for everything the GPU brushes collected this frame (dig, deconstruct, plants) and
  `place_mana(cells)` (`PLACE_MANA` 0.04) for what conjuring / back-wall painting placed (C_PLACED), and lights
  the HUD's mana bar (`Mage.mana_spent_t`). `has_mana(m, need, p, what)`: below `MANA_FLOOR` (1) digging,
  deconstructing and conjuring don't start (a toast, `vfx.fizzle`). Precise removal and Flatten work out their cost
  from what they read back and `pay_mana` it first (nothing happens without it; previews say "about N mana");
  build pieces pay `_place_mana_of(place)` (cells stamped, a door's doorway, a structure's blueprint; a torch
  `TORCH_MANA` 2, a workshop `STATION_MANA` 8), shapes `place_mana(cells)`. `free_magic` (the test mode, but in
  `_test_remove`'s mana check) makes it all free.
- vfx.gd: `dig(m, p, r, take)` every frame of digging / deconstructing (motes along a tether from the staff's
  tip, a turning rune circle where it bites, loosened sparks drawn home), `conjure(p, col)`, `shape_burst(cells,
  place)` (remove/flatten: mana-blue sparks rising; laying blocks: gold motes gathering; a rune circle over the
  middle), `place_flash(p, size)` (a piece put up), `fizzle(p)`. `MANA_COL` / `SHAPE_COL`.

## Spell effects (scripts/vfx.gd; user, 21 Nov: "epic vfx for the spells")
- main `vfx` (a Node2D in `pix` after the overlay, its child `glow` additive via CanvasItemMaterial): its own
  particles in packed arrays (`spawn(kind, pos, vel, life, c0, c1, s0, s1, add, grav, drag, f)`; kinds DOT, STREAK,
  GLOW (banded halo texture), SMOKE, RING (whole-pixel circles), SHARD, FLARE, BOLT (jagged, re-jittered), BEAM,
  RUNE (a turning magic circle), CHUNK; `MAX` 2200, swap-removed), `light(p, r, col, ticks)` (fading lights into
  `game.lights`), `screen_flash`. Everything in whole game pixels. `tick()` with the game's ticks.
- What a spell looks like is DATA, `Defs.SPELL_FX` (core, glow, glow_r, "trail", "impact", "cast" styles); main
  calls `vfx.cast` (`_cast`), `trail` (each tick a projectile in SPELL_FX flies; the overlay skips drawing those),
  `impact` (`_impact`, then returns), `blast` (every `_explode`: fireball, quake, starfall, meteors, lava bombs),
  `blink`, `mend`. Test: `_test_vfx` ("vfx": each spell cast on fresh ground, pictures `vfx_<spell>_fly/_hit.png`,
  particles die away, the effects' worst frame under 4 ms).

## The UI (scripts/ui.gd, pixel_font.gd, icons.gd; user, 21 Nov: a pixel-art UI; 22 Nov: arcane and decluttered)
- Arcane style, all through `_frame`: panels (pad 4 and up) are runed 24 x 24 nine-slices tiled in the middle (an
  ink outline, the astral-violet `TRIM`, a dark gap, a faint `MANA`-blue inner line, a cut gem in each corner, a
  faint field of stars inside); smaller frames (slots, small buttons, recipe cards) are plain 8 x 8. Gold is for
  what's chosen, `MANA` blue trims a recipe you can forge now.
- Decluttered HUD: the plate shows health, mana (shining while mana goes on shaping, a red wash under 1), breath
  when it matters, the place and the time (weather only when there is some, depth only underground; FPS and the
  profile only on F3; requests under it). The satchel is a POUCH (what Conjure places, draughts, coins, "I
  satchel") until I or Tab (`toggle_satchel`, `satchel_open`) opens the grid; its heading names the staff and the
  relics. Toasts are short notes at the bottom left (four at most, the same note freshens the one showing). The
  spell bar sits in a runed panel. `_test_ui` saves `ui_hud_pouch.png` and `ui_hud.png` (open).
- ui.gd's `root` is scaled by `U` (screen pixels per UI pixel: floor(screen height / 540), so 2 at 1080p and
  1440p) and sized to the screen in UI pixels (`_relayout` on resize): every size in ui.gd is UI pixels. Screen
  rectangles of controls: `_on_screen(c)` (get_global_rect ignores the scale). Tooltips pop up outside the root,
  so their frame and font are scaled by U in `_relayout`. title_screen.gd draws by its own `size` (UI pixels).
- pixel_font.gd: the game's bitmap font (`GLYPHS`: char -> [top row, rows]; caps 7, x-height 5, descent 2;
  `SIZE` 10), built at start-up into a FontFile (`make()`, `make(true)` bold), integer scaling only. Always use
  it at a multiple of SIZE (ui `fsize`; the old design sizes map to 1x/2x/3x). Bitmap fonts take no outline:
  labels get a one-pixel shadow. The overlay's bubbles, name tags and marks, map_view and space labels use it at
  SIZE * ui.U through a 1/scale_px transform. A new character is one line in GLYPHS.
- icons.gd: `mat(m)` (style by `MAT_STYLE` or the material's kind: block with its pattern, pile, drop, ore,
  gem, pearl/orb, ingot, log, leaf, shroom, cactus, torch, door, pane, rune), `spell(id)` (`SPELL_ART`, 11 x 11),
  `item(key)` (`ITEM_ART`/`ITEM_COL`: potion, coin, letter, chair, heart, drop, bubble, skull, book); outlined
  and cached.
- Weights (user, 21 Nov: "the new font is a little thick"): buttons and 1x headings use the regular face; the bold
  face only for headings at 2x and up (`_head`). The title (title_screen.gd): a main menu of Play / Settings / Quit
  (`MENU_W`, one width), Play opens the journeys panel (`show_slots`; Back or Esc `show_main`): a card per save slot
  (`CARD_W`) and its Delete (`DEL_W`), an empty slot's card the whole row, so every row lines up. Test: `_test_ui` checks both and saves
  `ui_slots.png`.
- Forge cards line up (user, 22 Nov: "the forge buttons are moving based on how much text is in the box"): a
  row's cards are as tall as its tallest (GridContainer), and `_recipe_card` puts an expanding gap under the
  description, then the lock text, the cost chips and ALWAYS a button (Forge, or greyed "Locked"/"Forged"), so
  costs and buttons sit at the bottom of every card. Icons (missing artwork: wards, travel, staff and body
  recipes all showed a red book): `Icons.thing(id)` (`THING_ART` shapes + `THINGS` id -> [shape, colours]: the
  foci as staves by tier, feather, rings, bloom, crystal, the wards (shield, amulets, veil, mask), skiff, Core
  Drive, engine, sail, beam, the smelter's band and edge, a recipe scroll), `Icons.prop(kind)` (a furniture
  recipe drawn from the piece itself, seed 7, shrunk to 13 px) and `Icons.prop_rows(rows)` (a carried piece in
  the satchel). ui `_recipe_icon(r)` picks; locked book pages show it dimmed; shops and stations use them too.
  Shop and station panels are violet like the rest. Speech bubbles and keepers' "[F]" go on after the mages
  (overlay `bubbles`), so the mage never hides the words.
- The satchel is a grid of `_slot`s (icon at 2x, count), the spell bar slots with glyphs, their number, the
  cooldown and a red wash when mana is short (`_draw_slot_over`), the chosen spell's name over it; the forge
  fills the screen (`show_forge`: 3-5 columns), with a tab per category (jumps the list) and cost chips
  (`_cost_chip`); shops in two columns. Test: `_test_ui` ("ui": the font has every character the game writes,
  whole-pixel scale, satchel and spell bar on screen; pictures `ui_hud/forge/settings/shop/title.png`).

## Building the game to share (Build game.bat; user, 22 Nov: "build the game into an easily distributable .exe")
- `Build game.bat` (repo root): finds the console Godot in engine/, works out the template version from
  `--version` (4.7.2.stable -> templates "4.7.2.stable", release "4.7.2-stable"), and if Godot's export templates
  aren't in %APPDATA%\Godot\export_templates\<version> asks (Y/N, No after 30 s) before downloading them (~1 GB,
  from the godotengine GitHub release; unpacked with tar). Then `--headless --export-release "Windows Desktop"`
  (game/export_presets.cfg: one .exe with the pack embedded, `*.comp` shaders included as plain files, audio/
  left out) into build\Wisp Forge\, the music copied beside it into "music", a README, and build\Wisp Forge.zip.
  Its steps go to build\build_log.txt ("BUILD OK" at the end). build/ is git-ignored.
- An exported game (`OS.has_feature("template")`): saves in %APPDATA%\Wisp Forge\saves (`_real_save_dir`; never
  beside the .exe), music from the "music" folder beside the .exe (audio.gd `music_dir`). A built game's own test
  run (`"Wisp Forge.exe" -- --test`, e.g. with saves\test_only.txt "newgame" beside it) reports into a saves
  folder beside the .exe instead (run Build game.bat again afterwards: it wipes build\Wisp Forge first). Checked
  22 Nov: the built game starts, compiles its shaders, plays its music, makes and saves a new world.

## Music (scripts/audio.gd)
- Tracks in game/audio/music/ by name: mood (surface_day, surface_night, underground, deep, boss, space, title) or
  kind + "_" + mood (`track_key`: "volcanic_surface_day.mp3"); `_pick` tries this planet kind's own, then the common
  one, then the fallbacks. A new kind of planet counts as a new mood (crossfade). The user makes tracks with Suno.

## Wild life (scripts/ecology.gd; user, 21 Nov: "make the worlds more realistic, like the enemies fit into the world")
- Every wild creature's life outside a fight. boss_ai.gd's `tick` calls `Ecology.tick` first for a creature (not a
  guardian): HUNT (0: it's after you, boss_ai's moves as before), DONE (1: ecology moved it), WANDER (2: boss_ai's
  `_wander`). Data per `Defs.CREATURES` entry: "temper" (predator: hunts you on sight; territorial: `warn_t` faces you
  and growls (pose "wind") within `TERR` + its width, charges after `WARN` frames; neutral: only once `provoked`; prey:
  never fights, runs from you and its hunters, a herd runs together), "eats" (creature ids it hunts: `_find_prey`,
  `_chase` at `CHASE` x speed (prey runs at `FLEE` x), `_bite`, `slay` leaves a carcass in `main.eco_carcasses` drawn
  on its back by overlay `_draw_carcasses`; it eats there, `eat_t`; a predator busy with prey ignores you past 50
  cells unless provoked), "scavenge" (vultures circle a carcass, then land and eat), "active" (day/night/any: out of
  its hours it goes to its `den` (spawn point; birds a perch) and sleeps, `asleep`, pose "sleep", "z"s; wakes to you
  within 30, a spell, digging (`brushes`) or a blast), "idle" (weights over wander, graze, sniff, rest, drink
  (`find_water`), sit, croak (sfx "croak"), flick (a frog's tongue at a fly), hop, perch (`find_perch`: a tree's
  crown, collision grid bg 3), circle, soar, coil, lurk, roost (`find_ceiling`), bask, follow (pack/herd `leader`,
  set in `_try_spawn`); `_idle_of` has defaults per plan), "habitat" (water: `habitat_ok` needs water within ~240
  columns by the surface table; soft: burrowers; trees; ceiling), "fireproof".
- Reacting to the world: `_sense` every `SENSE_EVERY` frames (fire within ~16 cells via `box_count` FIRE -> runs;
  `storm` = rain > 0.45 or a squall/hail/sandstorm under the open sky -> `find_shelter` (an overhang, a roof or a tree
  over it) and it huddles; birds perch), `Ecology.scare` from main `_explode` and `lightning_strike` (prey and the
  neutral run; the rest flinch), wounded below a quarter health run (not predators), `guard_lava` (main, before
  `move_body`) stops walkers stepping into lava. `harmful(e)` (main's contact damage): prey, unroused neutral or
  territorial ones and sleepers don't hurt to touch.
- Spawning (`main._wild_pick`): weighed by `spawn_weight` (habitat, and out of its hours 0.3: met asleep, `on_spawn`);
  prey counts apart (3 at most) from the rest. A burrower only spawns over soft ground.
- Fewer, farther foes (user, 22 Nov: too many, too often on the first planet; one fell in from the top of the
  screen; "breathing room" after clearing an area): `_try_spawn` every `SPAWN_EVERY` (150) ticks / (wild x
  `spawn_mult`), x `FIRST_CALM` (1.7) on planet 0; at most `spawn_cap(night)` (planet 0: 3 by day, 5 at night;
  else 5 / 7; a blood moon 12). Every spawn is at least `SPAWN_MIN_DIST` (160) cells to the side, past the
  screen's edge: on the ground by the surface table; in caves and for fliers by `gpu.read_rect` (40 x 90 cells
  beside you, three tries) for an open box the size of the foe (water for swimmers), walkers with a floor under
  it, surface fliers above the ground (the collision grid is only about as wide as the view, so a spot in it was
  always over or under the screen). Killing the last roused foe within 320 (`_check_cleared`, from `_kill_enemy`)
  makes the area quiet: no spawns for `QUIET_TICKS` (90 s) within `QUIET_R` (450) of there (a blood moon
  ignores it), toast "The area falls quiet". Test: `_test_spawns` ("spawns").
- Asleep means asleep (user: birds frozen in their attack pose until woken): falling asleep clears `e.act`, and
  overlay `_boss_frame` picks the "_sleep" frame (or the pose, or standing / flying) before any attack frame.
- Burrowers (user, 21 Nov: "the holes they pop out of are floating way above the ground"): under the ground they're
  always IN soft ground (`soft`: dirt, grass, sand, mud, gravel, snow, ash, sandstone, litter, mycelium, dry grass):
  `burrow_toward` follows the surface (`surface_under`) at `depth` (6, a guardian 14) and stops at rock, floors,
  water or the air; `keep_under` sinks one found in the open (a creature with no soft ground near is gone); a
  breach's `spot` is the surface over the burrower, only begun over `diggable_under` ground, a creature's lunge
  low (0.3 of `BREACH_H`) toward you; `dig_in` back into the ground where it lands or down its hole.
- Frogs (user: "glitchy, flicker between jump and not jumping"): `Enemy.off_t` (frames off the ground, main after
  `move_body`) and `air_on` (set by a jump, vy < -0.3, or a fall past 8 frames; held at least 3 frames) pick "_air"; `Ecology.hop` crouches 6 frames first (boss_ai `tick` plays
  `crouch_t` out, frame "_crouch"), `land_t` squashes on landing; a frog never shows walk frames. They float in
  water (`_fall`). Move "tongue" (boss_ai: out at you and back, stings and pulls; `e.tongue` along `e.aim`, drawn by
  overlay `_eco_marks`). New frames: beast "_graze", "_sleep"; toad "_croak", "_crouch", "_sleep"; bird "_perch",
  "_sleep" (`BossArt.bird_feet` puts it on its branch). Bats roost on cave roofs (`main._bat_roost`, "bat_hang").
- Cornered (user, 21 Nov: prey chased into a wall kept running at it, some went up a house wall): `_flee` turns a
  walker or hopper round when it meets a wall it can't clear (`jump_reach`: about its own height, at most 24) or
  makes no headway for 40 frames, and keeps that way (`flee_dir`, `flee_lock` 150-240 frames, `flee_cd`) so it
  bolts back past you (a leap if you're close) instead of turning back into the corner at each look round.
  `walk_to` jumps a wall only from the ground (jumping again at the top of each jump walked it up walls).
  Test: `_test_corner` (in "ecology": a course in open air with a 56-high wall).
- A tongue shows only while a frog flicks at a fly or lashes at you (`Ecology.tick` clears it otherwise: one roused
  mid-flick kept it standing up). Carcasses fall to the ground or rise to the top of water (`update_world`: "rest",
  re-checked every 30 frames). Mire Leech rad 2.3, Sand Viper rad 2.4, Glow Worm 1.9 (user: the small worms were tiny).
- Prey creatures: hare (forest, savanna, mountain), snowhare, deer (a herd of 3), skink, reedfrog. Test: `_test_ecology`
  ("ecology").
- Sizes true to life (user, 21 Nov: "accurate to size compared to the player"): a cell is about 10 cm (the mage's
  body is 17 tall). Wolves, hyenas, hounds ~12 x 9, boars and rams ~13 x 9-10, deer 13 x 14, jackals 8 x 6, hares
  6 x 4, skinks 5 x 2, frogs 4-8 wide, hawks/owls/gulls len 5-6 (wing 7), vultures 9 (wing 11), snakes rad 1 (2 cells
  thick, 12-16 segments), fungi ~5. boss_art.gd scales its fixed-size details by `minf(1, size / design size)`
  (beast L/18, toad L/15, bird L/12, fungus L/12), so guardians (larger) are drawn as before; a serpent's segments
  thin to 0.6 x rad, its head at least 1.4. `_test_ui` saves `lineup.png` (the mage and every creature, feet on one
  line). Treasure chests lean with the ground like doors (`_sprite(..., turn)`).

## Pathfinding (scripts/nav.gd)
- `shaders/navmap.comp` runs after grid.comp: one byte per 4 x 4 grid cells per mage (bit 0 blocks, 1 platform, 2
  liquid, 3 all blocked, 4 a door), read back in the same buffer as the grids (`gpu.nav_off`, `NG` blocks a side,
  `NGP` bytes a row). `main.nav_of_slot(k)` keeps a Nav per mage; `_take_gpu_results` ticks it: every `EVERY` frames,
  while any foe has `ask`ed for a class, the map goes to a WorkerThreadPool task that builds a graph per class:
  walkers `w<wb>x<hb>j<jh>[d]` (AStar2D: stand nodes; edges walk/step, drop off an edge or through a platform, jump
  straight up within jh blocks then over at the top, jump a gap of up to 4; "d" opens doors), fliers `f..`/swimmers
  `s..` (AStarGrid2D of where the body plus a block of room fits; swimmers in water only). Queries on the main
  thread: `walk_path`, `fly_path`, `fly_clear` (world points; the graphs keep the grid frame they were built in).
- foe_ai.gd `nav_walk(g, e, feet_goal, jump_v, gacc, tol, doors)`: the heading (-1/0/1) and it makes the jumps and
  drops itself (`Enemy.path`, `path_i`, `path_t`, `nav_air`, `nav_dx` for hoppers' hop size); 0 = there or as near as
  it gets (it stands, never pushing: `wall_t` > 50 drops the way and waits); NAN = no graph yet, or swimming / in the
  air with no way (callers fall back on the old `climb`/`_walker_nav`). Standing where the graph has no room for it
  (a shaft a little narrower than its 4-cell blocks think it needs) it stands and jumps straight up every 75 frames
  (`lost_t`), never running at the walls (a creature fallen down a shaft did). `nav_fly` (straight when `fly_clear`, else along the grid, cutting corners);
  `fly_line` (a bat only dives with a clear line); `can_reach` (could it stand within a quarter of its width + 10 of
  you). Used by skeletons/archers (doors), slimes/mimics, creatures and guardians (`BossAI._nav_around`), and every
  flier through main's `_flier_steer`.
- Guardians out of reach: `unreach_t` counts while `can_reach` fails (charge and slam are then left out of `_suits`);
  past 150 frames, within 110 and on its level, a walking guardian with a charge does a breach (`Enemy.breach`): the
  charge blasts a hole of its own size (power 2: brick and stone, not obsidian or runestone) in one go, at most twice.
  Wardens don't breach (their halls are warded). Test: `_test_nav` ("nav").

## Making a planet quickly
- `_make_world` times its steps (`gen_times`, printed by the test mode with `builds.plan_times` and the settle split).
  Verdance at 1.5x is made in about 3.7 s on the RTX 3070 laptop (12.3 s at the old size before this work).
- buildings.gd `_finish` only queues a blueprint (with the `rng.randi()` its roughening used, so layouts don't
  change); `finish_all` / `finish_start` + `finish_collect` finish every queued blueprint on WorkerThreadPool
  (`_finish_bp` through a helper copy of the planner per job, `_take_terrain`), results gathered in order.
- In the editor-build engine every call on an object (and every `bp.c[k]` read) goes through a shared lock: the hot
  loops (`_roughen_underground`, `_weather_ground_line`, `_stabilize_pass` with flat-array buckets, `_anchor_and_tidy`,
  `_place_chests`, BP.rect/rect_bg) work on a local copy of the cells and plain tables (`_kind`, `_span`, `_gmf`) and
  write it back once. Keep new per-cell code that way, or threads slow each other down tenfold.
- Settling (`gpu.settle`) covers only windows round each blueprint's loose matter (unanchored powder or liquid; none
  for a structure without any), with fewer plant and liquid passes than a game frame.
- Structures, vaults and the lair spacing scale with the planet's columns (per 8192); dungeons stay at `DUNGEONS` (4).

## Cell format
- Main buffer (binding 0), uint per cell:
  - bits 0-7: material
  - bits 8-15: colour variant
- Treasure chests are objects, not cells: `Chest` in main.gd (a 12 x 9 Body with its own physics, sprites
  "chest" / "chest_open"), planned by buildings.gd (`chest_list`) and saved in the world's `planet_state["chests"]`.
  - bits 16-23: life (fall distance for falling blocks)
  - bits 24-29: support distance
  - bit 30: anchored (untouched natural ground)
  - bit 31: BUILT (`ST_BUILT`: stamped from a blueprint, a structure rather than the planet's own ground)
- Background buffer (binding 8, `inc/bglayer.comp`):
  - bits 0-7: material
  - bits 8-13: support
  - bit 14: built back wall
  - bit 15: anchored (generated structures stay as built until digging nearby clears it, like bit 30 in front)
  - bits 16-31: plant id (bit 31 set; 0x8000 range = a tree, 0xC000 range = a bush), written by gen.comp.
    `shaders/plants.comp` (6 passes per frame) only lets cells of the same plant hold each other up, and a
    tree is only held by its wood touching the ground, so a cut tree drops whole and fast. Resting on its own
    cell below OR diagonally below is free (sideways and hanging cost 1, 62 = loose), so a branch or crown two
    or more cells thick carries itself out (user, 22 Nov: lair trees and natural trees and mushrooms fell apart
    untouched).
  - Knitting (plants.comp mode 1, pc.b.z = 1; `gpu.knit_windows` / `knit_plants`, `KNIT_PASSES` 160, run in
    `_make_world` right after the stamps, ~130 ms): over the whole land, a piece of one plant that gen.comp's
    overlap rules cut off from its own wood takes the id of the plant of its kind it leans on, and on the last
    pass (pc.b.w = 1) any plant cell still at 62 (support only rises from 0 while knitting, so it really is
    that far: a vine tip, a scrap) is trimmed. Nothing is left to come loose when you arrive.
  - Lairs' trees and giant mushrooms are living plants: lairs.gd `Lay.p` / `begin_plant` (layer 3) sets
    blueprint bit 20 (`Lairs.PLANT`, without the fixed-variant bit 27) and a per-plant number in bits 21-26;
    stamp.comp gives them a tree id hashed from the stamp seed and that number. (They were anchored back walls,
    and broke apart when the lair woke.) The generator's soundness pass (`_stabilize_pass`) lets them bear load
    as the back wall they stand in place of, never cutting them (a hall's wall hangs on its trees). Tests
    that look at the planet's own trees skip lairs (`_near_lair`). chunks.gd `_take_tree` reads again over a block twice the size when
    what looks loose touches the block's edge (a lair tree is taller than `TREE_READ`).
- A building's back walls are load-bearing (`support.comp`); the anchored flag is cleared near digging (`brush.comp`),
  but only for materials the digging staff could dig (so a vault's obsidian never comes loose early).
- A structure wakes as a whole: in `support.comp` an anchored built cell (front with ST_BUILT, or a BG_WALL back
  wall) wakes when a built neighbour or its own other layer is awake, so digging near any part of a building lets
  all of it obey the physics (anything harder than brick, HARD > 2, never wakes by spreading). Natural ground
  never takes part.
- Resting on powder (`restOn` in support.comp) looks down through the pile (up to 48 cells) to what's under it:
  only solid ground or a real dune holds, so rubble lying on a hanging floor never holds that floor up.

## Generation rules
- Keep everything modular and procedural: structures are assembled from parts in buildings.gd (`_roof`
  with eaves and ridge, `_window` shapes, `_back_frame` timbering or stone courses, `_chimney`, `_porch`,
  wings, `_landings`, `_carve_inside` for rooms inside a solid mass like a pyramid). Style choices live in
  `_style()`; blueprints are sized with `_roof_h()` so roofs are never cut off.
- Chests: `_chest(bp, i, floor_row, sure)` keeps only CHEST_KEEP of the optional ones; `_place_chests` then
  moves each to a clear spot on the same floor (solid floor, open air around and above, nothing loose
  overhead, indoors if planned indoors) or drops it.
- Dungeons (`_dungeon`, DUNGEONS per planet): a gatehouse blueprint with a shaft down, and a separate
  blueprint of rooms in a grid of slots joined by a random spanning tree plus loops (corridors side by side,
  shafts with landings one above the other). Rooms get themes (`_dungeon_room`); the farthest is a reliquary
  walled in brick or obsidian. `_dungeon_reach` flood-fills from the shaft and stores the result in `bp.meta`
  for the tests.
- Dungeon wardens: the reliquary's neighbour nearest the way in (never the entrance) is the warden's hall, as big
  as its slot allows (94 x 70), furnished as kind "warden" (pillars, braziers, no guards). The door between it and the
  reliquary is a ward of RUNESTONE (the reliquary's other doors keep its seal). `scripts/wardens.gd` `make(seed,
  biome, dungeon)` grows the warden from the dungeon's own seed (never the planet's `rng`): a body plan of
  boss_art.gd in crypt colours (bone, shade, rot, ember) with the biome's accent, guardian moves plus `summon`
  (skeletons; bats for a bird), a name from parts ("Gravemaw, Warden of the Frozen Crypts"). buildings.gd
  `warden_list` ({key "warden_<seed>_<col>", pos, def, tether, ceil, ward stamp rect, name}); main `_spawn_guardians`
  registers each (`Defs.register_warden`; `Defs.warden_enemy`, `enemy_def` for "warden_") and spawns it unless
  `bosses_dead` has its key. It wakes only with you inside its hall (`BossAI._in_hall`). `_guardian_falls` hands a
  warden to `_warden_falls`: loot, a Healing Draught, and a stamp clears the ward. A boss's summons appear on the
  floor under it (`_ground_under`), never through the stone into the room above. Test: `_test_wardens` ("wardens").
- Dungeon walls, floors and shafts are `RUNESTONE` (warded stone, hardness 4: only the Core Siphon cuts it), so
  dungeons are explored through their halls; the gatehouse above ground is ordinary stone.
- Props (`scripts/props.gd`): furniture and town details grown procedurally as small pixel grids (chars index
  `Props.PALETTE`, emitted to GLSL as `DECOR_PAL`). buildings.gd stamps them into the BACKGROUND as material
  `DECOR` with the palette index in aux bits 16-23 (`bp.bgv`), so they never block movement; 't' pixels become
  real torches. `_furnish` fills rooms by role (`FURNISH` kits: home, shop, smithy, tavern, inn, tower, keep,
  hut, dwelling), `_dress_yard` adds signs (icon by role), hedges, lamps; `_town_square` fills gaps in villages
  (well, market stall, lamps, flowers). A prop only goes where every pixel lands on open space (`_prop_fits`).
  Digging leaves furniture alone; Shift + right-click (deconstruct) takes it as planks.
- Doors (`WOODDOOR`): `_door` in buildings.gd fills a doorway with door cells whose colour variant is their
  part (row << 2 | column) and records it in `door_list`; main.gd keeps `doors` (saved in
  `planet_state["doors"]`). Walking into one opens it (`_door_bump` from `move_body`), F toggles the nearest
  (`_interact`), and a door won't close on someone standing in it. Opening and closing is brush mode 9
  (brush.comp clears or refills the doorway rectangle); the open door is drawn by overlay.gd, swung outward.
- Build mode (B, `scripts/build.gd`): a catalogue of pieces (back walls painted with brush mode 10, doors,
  scaffold platforms, and props.gd furniture with a seeded design: R rerolls, T mirrors). main.gd's
  `_update_build` previews (overlay draws `build_prev`) and places: furniture and platforms become small
  blueprints in `stamps`, written by `gpu.stamp` just before the next GPU frame. Placed pieces are not anchored,
  so they obey the physics. Digging a door (open or shut) takes it whole into the satchel as a Door item.
  Structures (House, Room, Roof) are put together by buildings.gd's own parts (`Build.structure`, seeded, with
  `builds.rng` saved and restored); [ ] width, - = storeys, T style, R variation; cost from `structure_cost`.
- Furniture is a layer in front of the back wall: each DECOR cell remembers the wall behind it (an index into
  `Defs.BEHIND`, in background bits 22-23 and 28-30; bglayer.comp `behindIdx`/`withBehind`/`decorGone`). stamp.comp
  fills it in as furniture is written (the wall already there, or the nearest wall beside it in the blueprint
  row); burning (react.comp, brush ignition), breaking up (deconstruct) and taking a piece whole give the wall
  back instead of a hole.
- Furniture kinds: a prop's kind (props.gd `KINDS`, 15 at most: table, chair, bed...) travels in blueprint bits 28-31
  and lives in background bits 24-27 of its DECOR cells (`bp.bgv(..., kid)`, `Build.prop_stamp(cells, kid)`), so
  a picked-up piece keeps its name and a bed is known for a bed (`Props.BED`).
- Carried furniture (`Mage.furn`, saved in progress.json): Shift + right-click on furniture takes the whole piece
  (`_pick_up_furniture`: `gpu.read_rect` reads the block, `_furniture_piece` flood-fills cells of the same kind plus
  its torches, a stamp clears them and puts back the back wall it hid). The Wisp Forge forges the indoor pieces
  (`Build.furniture_recipes`, in main's `recipes`); build mode's Satchel tab (`Build.CAT_SATCHEL`) sets them down free.
- Home: F at a bed (`_try_home`; a bed right beside you comes before a door) with a roof over it and back wall
  behind the room above it (`_home_check`) sets `planet_state["home"]`; `_respawn` brings you back there while
  most of the bed is still there (`_home_pos`).
- Collision grid background bits: 0x40 furniture, 0x80 built back wall, 0xC0 a tree (building over one would
  fell it, so build mode refuses; bushes are just covered).
- Staircases (build.gd "stairs" pieces in "Doors & Stairs": Wooden, Stone, Brick; roadmap step 8): steps
  `STAIR_STEP` (4) up and along, so the mage (step_h 5) walks up; a flight `STAIR_BAND` thick under the treads;
  a post of back wall down to the floor every `STAIR_POST` columns and under the last step (support reaches only
  12 cells sideways through planks: a flight held at its foot alone gave way); balusters and a two-thick handrail
  (a one-cell diagonal touches only at corners and fell). `Build.stair_cells` / `stair_stamp` / `stair_cost` (a
  quarter of the flight, a tenth of posts and rail); main `_update_build` "stairs": its foot on the highest ground
  under its first step, it climbs away from you (`build_flip`, T), `build_rise` ([ ] a step, - = a storey,
  8..160); the treads need open space, under them it merges into a hillside (never into anything built,
  `_built_at`); a post through a tree refuses it ("a tree is in the way"). Test: `_test_stairs` ("stairs": on a
  NATURAL slab in open air (a built one woke with the stairs on it and fell), stands, and you walk up it;
  `stairs.png`).
- Taking away precisely (user, 22 Nov: "a precise way to be able to remove materials, flatten the ground, remove
  background decorations without remove the entire background"; physics applies): build mode's Remove tab
  (`Build.CAT_REMOVE` 8, kinds "remove" with "layer" front / back / furn / all, and "flatten" with a fill "mat").
  Remove drags the block shapes (a click is a thick x thick square, one cell at 1): main `_update_remove` previews
  from the collision grid (`_removable_guess`; a cave's natural back wall doesn't show there), and on release
  `remove_cells(m, cells, layer)` reads the block back (`_cells_box`, `gpu.read_rect`), stamps out exactly that
  layer where the staff's tier can (HARD), furniture giving back the wall it hid (`Defs.BEHIND`), and puts what it
  gives in the satchel (`_collect_as`, as the dig's collectAs; five flame cells are a torch). `_wake_round` then
  adds brushes of mode 11 (brush.comp: only the anchor-clearing of digging, within rad + 12) over what was taken,
  so what held on only by it comes down. Flatten (`flatten_plan(a, b)`: the row you press is the new top; solid
  and powder up to `FLAT_CUT` over it cut, open cells down to ground within `FLAT_FILL` under it filled, deepest
  first; `flatten_apply` reads back, cuts what the staff can, fills from the satchel, wakes). Test: `_test_remove`
  ("remove": on a 20-thick natural slab in the air, as a thin slab woken would give way; picture
  `torches_night.png`).
- Torches are one piece (user, 22 Nov: placing torches laid a whole brush of them; "a torch model that placed as one
  piece and gave a nice range of lighting"): `Build.SCONCE` (3 x 7) / `STANDING` (3 x 12) prop rows, flame 't'
  cells (real TORCH) over an iron cup and a wooden handle. main `torch_plan(cell)`: pointed at a built back wall, a
  sconce; else with a floor within 12 under the cursor, standing on it; else a sconce, if a wall, solid beside it
  or a cave (6+ under the surface) holds it. `place_torch(m, p)` (build mode's Furniture tab "Torch", or Conjure
  with torches chosen: one a click, `cast_latch`), `add_torch` -> `planet_state["torches"]` ([x, y, frame] of the
  flame). `_torch_lights` (in `_write_frame_params` BEFORE the light count is set) puts the nearest in view into
  what's left of the 32 point lights, `TORCH_R` 60 across, warm, flickering; `_check_torches` (every 60 ticks)
  forgets one whose flame cell isn't furniture any more in the collision grid. Digging leaves torch cells
  (brush.comp keepBg), deconstruct puts a flame out without giving anything, and Shift + right-click on a torch
  piece (kind 0, 3+ flame cells, at most `TORCH_CELLS_MAX` cells) gives back one torch (`_pick_up_furniture`).
- Straight building (build.gd `SHAPES`, main's `_update_shape`): back walls (Back Walls tab) and solid blocks
  (Blocks tab, `CAT_BLOCKS`) are laid by pressing, dragging and letting go: a line snapped across, up or at 45
  degrees, a filled rectangle, or a frame; G cycles the shape (back walls can also be brushed), [ ] the
  thickness. `Build.shape_cells` / `shape_stamp`; one material per cell; blocks skip cells where someone stands.
- Spells with "single" in `Defs.SPELLS` cast once a click (user, 21 Nov: the start was too strong): `Mage.cast_latch`
  is set by `_cast` and cleared when the button is let go. Spark Bolt is single, 12 mana, 30 ticks, reaches 220
  cells (it was 4 mana every 9 ticks while held). Test: in `_test_vfx`.
- A modest start (user, 21 Nov: "make the starting power of the player lower"): a new journey knows only the
  Wisp Mote (`Defs.SPELLS` "mote": single, 8 mana, slow, short, 6 damage, never touches terrain) and Conjure;
  Spark Bolt is forged (recipe "spark": stone, coal, a little copper). Levitation is forged too (recipe
  "levitate", `items["levitate"]`; needs Wisp, so the Copper Focus first) or comes with the Roc Feather;
  `_update_player`'s `floating` checks it. A save from before ("start" < 1 in progress.json) keeps levitation.
  The test mode starts with spark and levitation (tests.gd sets them), and `_test_start` ("start") checks the gate.
  Digging: the excavation brush's rate is scaled by the staff's tier (`tier_rate` 0.55, 0.8, 1.0, 1.2), so a plain
  staff digs about half as fast. Ores are a little rarer (gen.comp `strata` thresholds +0.015, each planet
  kind's own ore +0.012 in `gpu.build_surface`).
- Recipes you discover (user, 21 Nov; roadmap step 13): `Defs.LEARN` / `learn_of(r)` says how each recipe is
  learned ("start"; "find" [materials]: the first time you hold one; "scroll" 1-3: a recipe scroll in a chest of
  that grade; "shop" role + "kind" + "price": sold by village keepers, and taught as a request's thanks; "hoard":
  a guardian's hoard or a warden's reliquary). Ore gear: an ore's first piece on finding it, its second at a smithy
  on that ore's world, its third and every alloy in a hoard; furniture and anything unlisted is known from the
  start. main: `learned` (ids, saved as "learned"; a save without it learns all), `knows(r)`, `learn(id, why)`
  (a spell with its own "scroll" item gets that item too), `learn_all` (old saves, the test mode, F9),
  `_learn_from_finds` (every second), `_chest_recipe(level)` (in `_try_open_chest`: 0.3 + rare x 0.4, level 3 in
  dungeons and temples, 2 in ruins, keeps, mines or 150 below the surface), `_hoard_recipe` (this world's own
  first), `shop_recipes(role)`. `craft` refuses an unknown recipe. towns.gd `shop_def` lists a keeper's recipes
  ("recipe" sale items; `owned` = known, `grant` learns), `_finish` teaches one as thanks (one request in three).
  ui.gd: the forge lists what you know, then the Recipe Book (`_book_page`: locked pages with `Defs.learn_hint`;
  J opens the forge there, `show_forge(true)`). Test: `_test_recipes` ("recipes", picture `forge_book.png`).
- Boss art is grown on a worker thread (overlay `_boss_art`, `_art_jobs`): a foe isn't drawn until its frames are
  ready. (Grown on the main thread the first time the planet's guardians and wardens were drawn, the first frame
  took 750 ms: the user's start-up hitch.) The tests print `[startup]` frames over 40 ms (`_trace_frames`), and
  F3 shows the overlay's parts ("draw: foes", "draw: mages"...).
- Health doesn't regenerate. Healing Draughts (`items["potion"]`, H to drink, `_drink`; forged or found in chests,
  two at the start) and the Mending spell (its scroll is a rare find) heal over a moment (`Mage.heal_left`).
- Falling rock hurts only after falling `ROCK_HURT_FALL` cells and only through your upper half (grid.comp), so
  digging a pit under yourself doesn't.
- Doors swing either way (away from whoever opens them, `swing`). A door keeps its damage: opening it reads which
  parts are left (`_read_door_cells` -> `d["cells"]`, the part per doorway cell or -1, saved with the doors);
  shutting it stamps back only those parts; fire and blasts take parts off the open panel where they reach
  (`_hurt_open_door`), and overlay.gd draws the panel with those holes, charred at the edges. Less than a third
  left and the door falls apart.
- Holding Shift + right mouse keeps harvesting: after a piece is taken whole there is a short pause
  (`Mage.decon_pause`), not a need to let go.
- Background harvest (`_pick_up_furniture`) checks the collision grid for furniture before reading the world back;
  a read that finds none isn't repeated at the same spot (`_pick_miss`).
- Save slots: saves/slot_1..3 (`SLOTS`, `slot`, `_save_dir`), each with its progress.json and worlds; the title
  lists them (title_screen.gd `refresh_slots`: continue a saved one, start in an empty one, Delete twice);
  `quit_to_title` (Esc menu) saves and returns there. Saves from before slots move into slot 1
  (`_migrate_old_saves`). settings.json stays in saves/; the test mode uses saves/test.
- Window: setting "window" (windowed, fullscreen, exclusive), F11 / Alt+Enter switch; the test mode stays windowed.
- Foundations: two courses of the building's stone, then the biome's own ground layers (`_ground_mats`); yards are
  made of the biome's soil too. `_weather_ground_line` (run by `_finish`) blends masonry at the ground line outside
  buildings: course ends crumble into earth, topsoil drifts over exposed tops (never at doors), and a ruin's
  buried part is half swallowed by the ground.
- Packed ground: gen.comp `settleSafe` generates powder that couldn't rest (over caves, on steep faces, around
  building sites, to a wobbling depth) as its packed solid (sand -> SANDSTONE). render.comp draws SANDSTONE without
  ST_BUILT as natural wavy strata and only built sandstone as dressed blocks; conjured solids are marked built.
- Test mode quits by itself after 13 minutes (a full run takes about 9), so a broken run never leaves the game open;
  `scripts/watchdog.gd` (an autoload ahead of Defs, kept tiny) also quits a `--test` run whose main scene never came
  up (a parse error in main.gd used to leave a blank window), whose main.gd `_ready` stopped before `booted` (a
  script it preloads failed to compile: 25 s), or that passes 14 minutes. tests.gd is loaded at run
  time (not preloaded), so a parse error in it quits the game instead of leaving a blank window. `Check scripts.bat`
  stops at the first error per file (the expected Defs one), so it can't catch later parse errors in tests.gd:
  watch for a local that reuses a name already declared in the same function (lambdas included).
- Below-ground masonry (dungeon runestone too) gets ragged, stepped outer edges (`_roughen_underground`, run by
  `_finish`), so shafts and buried halls don't meet the earth with ruler-straight lines. The added cells are written
  outright (anchored, not F_FILL: a fill only lands in open space, so it never showed against solid earth), and only
  ever outward into the blueprint's untouched (255) cells, so halls and shafts stay as built.
- Biome borders: gen.comp picks one of the two neighbouring biomes per cell with noise at three scales (lobes,
  fingers, single grains), so their layers interfinger instead of meeting at a seam. Undergrowth (grass, bushes,
  tufts) picks per COLUMN the same way (`floraType` in main), trees by their own trunk's biome; overlapping
  mushroom caps: the shorter one wins the cells (in front), not the nearer trunk (that split them down a line, each
  its own colour). render.comp: a cave's back wall bands (`wallColor`) have ragged edges, and the far tree line
  (near parallax hills) takes each tree's kind from the biome at that tree (user, 21 Nov: sharp transitions).
- Back walls (and furniture, which is stamped as back wall) rest on settled powder below them (`support.comp`),
  the way front blocks do: a table set on sand or soil stays.
- Biomes: at most 8 per planet (their parameters fill P.p[8..23]). Flora types are numbered in defs.gd; each
  has a tree function in gen.comp (oak, pine, cactus, willow, charred, palm, jungle, acacia, mushroom) plus
  undergrowth in `flora()`; plant materials get their look in render.comp's `plantColor`.
- Roots (`ROOT`, background only): gen.comp `treeRoots` draws a taproot and a few side roots under each tree
  (`rootWidth` per flora type), into the ground below the surface and into the air where a slope drops away
  under the trunk, so no tree shows a flat underside. Roots score lowest in `flora` (every other part of any
  tree wins a cell), aren't tree-flagged in the collision grid (build over them freely), and dig up as Wood.
- Fog over the unseen underground (user, 21 Nov: "fog to underground areas the player has not illuminated yet ...
  soft fall off"): `shaders/inc/seen.comp`, binding 12, `gpu.seen_buf` (`seen_bytes()` = total cells / 2): a level
  0..16 per block of 2 x 2 cells as a 16-bit thermometer, two blocks a word (`seenWord`, `seenAt`, `markSeen` =
  one atomicOr, levels only go up). render.comp marks what's lit now (`visNow`: the light less a lightning flash,
  smoothstep 0.02..0.25; never from the map or space, P.p[122].w bit 2); light.comp puts how clear each light
  point is in the light's w (4 samples of the seen map, or what's lit now, times `fogUnder`: none in the top 5
  rows under the surface, all of it from 26 down), blurred with the light, so the edge falls off softly; render
  mixes in a drifting dark mist by 1 - w, over lava and glowing ore too. Sprites: `gpu.light_at(...).a`, overlay
  `_lit` darkens them to match and returns the fog as alpha (clear 0.12..0.47), so foes, creatures, villagers,
  sleep marks and carcasses fade out under the fog (user, 22 Nov: "I can see enemies under the fog of war");
  the mage, the skiff and glowing sprites stay opaque; chunks.gd takes no colour from a fogged spot. Saved in the world file as a block
  of its own after the cells (`SEEN_MAGIC`, compressed apart; `gpu.read_seen`/`write_seen`, `read_world_async`
  returns [cells, seen]; a world without it loads all unseen); cleared for a new planet (`generate_prepare`).
  (`read_world(true)` / `write_world` with the seen map appended are for the tests.) Test: `_test_fog` ("fog",
  picture `fog.png`).
- Point lights are given to light.comp in the PICTURE's pixels (`world_to_screen` + `PMX/PMY`): in the screen's
  they shone a margin up and left of where they were (since the picture got its margin), so underground the wisp
  lit the rock beside you.
- Clouds live in world space (`shaders/inc/clouds.comp`: `cloudLow` near the ground, `cloudHigh` the weather
  layer above the mountains; `cloudDensity` is both): render.comp draws them over everything
  at their height (fog when you fly in), react.comp spawns rain/snow/ash only under the high layer's undersides, and
  grid.comp writes each mage's cloud depth to counts[58] (`Mage.fog`: misted sprite, wisps in overlay).
- Mud (`MUD`, a liquid): a biome's liquid ground layer (marsh top, jungle subsoil) is only liquid in bogs
  (gen.comp `bogDepth`: hollows the ground rises around, or under standing water, never on building sites or
  over caves); everywhere else it is generated as grass over dirt, so ground never hides a pool you sink into.
  render.comp draws mud dark and glossy with a wet top sheen and bubbles. react.comp: loose (unanchored) dirt
  touching water turns to mud; unanchored mud in the open with no water near dries back to dirt.
- Foe AI (`scripts/foe_ai.gd`, static behaviours; each foe's `ai` entry in `Defs.ENEMY` picks and tunes them):
  `think` (line of sight through the collision grid every few frames, spells heard nearby, memory of where you
  were, `rally` alerts foes within 90 cells), `goal`, and attacks as small state machines on `Enemy.act`
  ("windup" -> "strike" / "air" / "dive" -> "recover"): `leap` (slimes, mimics, aimed ballistic jump), `melee`
  (skeleton lunge + blade reach), `ranged` (archers' arrows, imps' fire; `shoot` leads the target and allows for
  drop), `swoop` (bats), `blink` (imps). Every wind-up is a tell: overlay.gd tints the foe (`FoeAI.tell`).
  Foes with `ai.doors` open doors by walking into them (`move_body` -> `_door_bump`, `door_t` stops them turning
  back). Archers are a third of structure guards (hooded, cloaked, a quiver and a long bow; sprite "archer_draw" while
  winding up, picked by overlay `_foe_frame` for any `<spr>_draw`; their arrows are drawn bone-pale with red fletching
  and a spectral green head, wake and faint light; picked by position in `_guard`); the dead walk at night.
  Other levels (`FoeAI.climb`, used by skeletons/archers, slimes/mimics and wild walking/hopping creatures, never
  guardians): when its goal is well above or below and not far to the side, a foe looks about (`_plan_up`: tops within
  `CLIMB_LOOK` columns and its jump; `_plan_down`: the platform it stands on, or a gap/edge wide enough) at most every
  half second, keeps the plan in `Enemy.climb_*` (world points: `climb_from` take-off at its FEET, `climb_to` landing),
  walks (hoppers hop, `climb_gap`) to the take-off and jumps straight up just high enough (up through a one-way
  platform, or beside a solid ledge, moving over once its feet clear the top) or drops (`drop_t`); on landing it
  looks again at once. With you above, walkers won't step off their level (`edge_ahead`). An archer that sees you
  shoots instead; a creature only charges on its own level. The collision grid is FLAT around the mage, so level
  ground curves away in it (a row every 10-15 cells far out): never assume a floor is on one row; follow it
  (`_ground`, `_walk_to`, `_standable3`). `Enemy.climb_why` says why the last look found no way up (tests print it).
  Test: `_test_climb`, a course in open air (floor, platform 22 up, ledge 22 above), up and back down.
- The wild-life checks (`_test_creatures`, `_test_ecology`) are set up near `start_pos` (where you arrived), in clear
  weather (rain off, `weather_timer` held), as when run alone. The skiff-travel check prints `[travel] a N ms
  frame ...` for any frame over 150 ms (the game's process, drawing, GPU wait).
- Running one test section: a non-empty `saves/test_only.txt` naming it ("climb", "nav", "guardians", "wardens", "biomes",
  "worlds", "creatures", "ecology", "fog", "start", "recipes", "sky", "gear", "towns", "vfx", "ui", "bench", "lairs", "stairs", "workshops", "galaxy", "remove", "spawns", "newgame", "stampdiag" or "mines": a print of each mine the soundness pass cut, with where) runs just that
  section after the planet is made (25-50 s; "guardians" also prints a `[guardian]` trace every 15 frames); empty runs
  everything. Leave it empty when done. A section that can run alone is its own function (`_test_climb`,
  `_test_guardians`) called from `run()` in its usual place.
- Biome guardians (one boss per biome; Vulkhar the Ember Golem stays the planet's deep boss): `Defs.BOSSES` (per
  biome: name, title, lair name, colour, `body` (plan + features), stats, `go`, `moves`/`rage` (dicts of move ->
  settings; a trailing digit is the same move with other settings), `relic`, `loot`, lair materials `wall`, `floor`,
  `trim`, optional `glow`), `Defs.RELICS`, `Defs.boss_enemy("boss_<biome>")` / `enemy_def` (the foe dict, with
  "def" and "biome"). Bodies: `scripts/boss_art.gd` grows pixel frames from parts at first sight (overlay
  `_boss_art`): plans beast (antlers, mane, spikes, ears, tails), bird, toad, fungus, serpent (head + segments drawn
  along `Enemy.trail` by overlay `_draw_serpent`; birds and serpents are drawn centred, `_sprite_mid`). Behaviour:
  `scripts/boss_ai.gd` `tick` (called from `_update_enemies` before the fixed foes' match): getting around (walk,
  hop, fly, slither, burrow: `Enemy.under` = hidden and untouchable, not moved by move_body; overlay `_draw_mound` heaves
  the ground over a burrower so you see where it goes, and a breach's last `BREACH_TELL` frames of wind-up it keeps
  still under `e.spot` while the sand there boils up (`_boil`), then bursts out there, not under where you are now), moves as state
  machines on `Enemy.act` windup -> go -> recover (charge, slam, spit, rain, erupt, roar, summon, cloud, dive, gust,
  breach), enraged below half health. A guardian stays in its lair: `Enemy.tether` (cells along the ground from
  its home, from the lair's "tether") and `ceil` (how high fliers go) bound where it heads (`_in_lair`,
  `_lair_point`), a charge stops at the edge, a slam lands inside; walkers keep moving round you (`pace`, a new side
  every second or two) by the nav graph (`_nav_around`, below), hop what's under `CLIMB` (`_clear_way` only turns
  them back now: the old chipping at walls just made a hole to shoot through; a charge bounds over a low step), steer whenever
  resting on something (a chest isn't "ground"), and hop free after 1.5 s without progress; fliers steer round
  obstacles with main's `_flier_steer`. Leaps are worked out from the planet's pull to rise `SLAM_H`/`HOP_H`/
  `BREACH_H` cells, and gravity always applies to walkers (it used to be off for a slam: they flew off screen). New enemy projectiles in `Defs.PROJ` (venom, mudball, ice, rock, sandball,
  spore) with "col", "splat" (matter left where they land) and "home" (spores drift after you); `boss_clouds`.
  A beast's tail (`_tail_len`, `_tail`) is sized to its body and drawn as a tapering, curving chain, and the frame
  is padded on both sides to hold it (it used to be a fixed length, so small beasts' tails were cut square at the
  picture's edge); `_test_ui` checks no beast frame touches its edge.
  Lairs: buildings.gd `_lairs` runs LAST in `plan`, with its own RNG (so adding lairs moved no other structure:
  several tests depend on the layout near the start), one per biome: spots deep inside the biome first; an open
  arena (`_lair`: dry, level enough, `LAIR_W` 540 wide (460 at a pinch), levelled and paved, ramping to the land,
  cleared `LAIR_UP` 170 to the sky) at least 600/8192 of the way round from the start, else an underground hall
  (`_lair_deep`: 360 x 120, 200 rows down, a shaft with landings), then the same at 380/8192; never within `LAIR_W`
  + 160 columns of another lair. Only biomes in the planet's "guardians" get one (`guardian_biomes`). Both are
  DRESSED by `scripts/lairs.gd` (user, 21 Nov: "make the boss arenas feel waaay more epic ... an entrance ... themed
  areas ... that fit the size of the bosses"): `open_arena` / `hall` / `shaft_gate`, per `Lairs.theme(biome)` (its
  "set", "back", statue stones "stat" [light, main, dark outline, eyes], "glow", banner "cloth" palette pair, "roof",
  "rock", "moss", "shade"). An open lair: a GATEHOUSE at the ramp's top (`GATE_W` 62: towers with pointed roofs,
  battlements, arrow slits, a vaulted passage 48-58 high a guardian walks through, banners, torches, a raised
  portcullis, the guardian's effigy on top, braziers); a ruined COLONNADE behind the fighting floor; the floor
  `inlay`; the theme's SET (`dress`: glade trees and rune stones, temple trees with vines, mire pool and dead trees,
  den ice spires, eyrie `crag`s and the roc's `nest`, pride `acacia`s and termite mounds, sands obelisks, hollow
  giant `shroom`s, caldera obsidian spires and lava channels, sanctum kelp and glowing crystals); at the far end
  (`far_end`, `BACK_W` 210) a stepped dais, a plinth and a STATUE of the guardian (`BossArt.statue`: one pose,
  a serpent reared out of its coils; scaled up to 84 tall, carved in the theme's stones, eyes glowing) in an
  arched niche of the BACKDROP (`backdrop`, `MASS_W` 62: cliff, glacier, caldera, outcrop with the pride rock's
  lip (natural rock), ziggurat, ruin, temple front) that closes the arena; the sure chest at the statue's feet.
  Everything tall is BACKGROUND (in a side view anything solid on the floor is in the way): in front only low cover
  (<= 12), the dais, the gate and the backdrop; nothing solid within 64 of the middle (`keep`: where the guardian
  waits and the tests put you). Natural rock carries blueprint bit 19 (`Lairs.NATURAL`, without the fixed-variant
  bit): stamp.comp leaves it unbuilt, so it looks and acts like the land. All of it is anchored (the generator's
  soundness pass keeps overhangs; in the game it stays until dug or blasted near). Lay writes a copy of the
  blueprint's cells and `commit`s them, so nothing else may write the blueprint while a Lay is open. A hall gets
  the colonnade (in its floor stone, to show on the wall), set, dais and statue (no backdrop); its shaft a gate on
  the surface (`shaft_gate`). `lair_list` ({biome, pos (the fighting floor's middle), name, deep, tether, arena
  (half the fighting floor), ceil, bx0 (the blueprint's x0, for the tests)}) -> main `_spawn_guardians`
  (`Enemy.arena`: the arena's half width; `tether` reaches `LEASH`
  200 past it, so a guardian follows you out). A guardian wakes within `BossAI.WAKE` (110) or once you're in its arena.
  Left alone (you 300 away for 200 frames) it heals and goes home. Test mode sets `test_calm` (guardians stay asleep)
  except during the guardians' own test, so other checks aren't disturbed by a boss nearby. Beaten: `_guardian_falls`
  (relic into `items`, loot, `planet_state["bosses_dead"]`). Relic effects live where they matter: ironbark in
  `hurt`, coil in `_update_player`'s speed, pearl in the breath check, rimefang in the spark's impact, roc in
  levitation, lionheart +40 max health once, sunidol in `_hurt_enemy`, lantern a light in `_tick`, cinderheart in the
  player's hazards (no fire or deep-heat damage, lava x0.3), tidefin in `_update_player`'s swimming.
  The other planets' biomes: ashland (Kragmor, the Cinder Beast: Cindrel, Sere) and ocean (Thalassor, the Tide Wyrm:
  Thalassa). A boss with "wet" gets a drowned arena (`_lair` levels it on the seabed and clears it to WATER below
  `water_row`, air above; `_lair_deep` can't work there); "swim" (a boss or creature) keeps to the water
  (`BossAI._swim_hold`: out of it, it can't rise). Swimmers spawn in water (`_try_spawn`'s open-cell path with the
  liquid test reversed). Lairs' test: `_test_lairs` ("lairs": banners, background, chest per lair; pictures
  `lair_<biome>_bp.png` (the whole blueprint) and `lair_<biome>_mid/_a/_b.png` in the game). Test: `_test_far_biomes` ("biomes": enters Cindrel and Thalassa, `_test_guardians(["ashland"])`
  etc., the sanctum under water, the swimmers in the sea).
- Wild creatures (`Defs.CREATURES`, foe type "c_<id>", `Defs.creature_enemy` / `creatures_of(where)`): two or so per
  biome and per depth underground ("cave1" upper caves, "cave2" middle, "cave3" the deep), grown by boss_art.gd's
  body plans (beast with tusks/horns too) and moved by boss_ai.gd's moves, with `e.boss` false: foe_ai.gd `think`
  gives them sight/hearing/memory; with nothing to hunt they `_wander` near `home`; moves are half size (`_sz`:
  slam/breach heights), charges shorter, and they never break the land (`_burst(..., wreck=false)`, `_clear_way`
  turns them back instead of smashing). Optional `pack` (wolves, hyenas, jackals), `pace`, `cd`, `drops`. `_try_spawn`:
  the biome's creatures by day and night on the surface (`_wild_pick`, `_biome_name_at`; fliers come in through
  the air, serpents and burrowers on the ground), each depth band's underground. Test: every creature hunts,
  stays on screen and moves (`saves/shots/creatures_N.png`). Test mode sets `test_no_wild` so none come by
  themselves into the other checks.
- Rigid chunks (`scripts/chunks.gd`): grid.comp reports one felled-tree cell (counts[59]/[60]: a plant cell whose
  support reached 62) and one creaking block (counts[56]/[57]) per mage; `detect` reads the world around it
  (`gpu.read_rect`: `shaders/rectread.comp` copies just the rectangle into a small buffer, read back in one go), takes the loose cells out with a stamp and makes
  rigid bodies: a tree's detached cells (CPU flood from wood on the ground), or a building piece (loose blocks +
  the loose back walls and furniture joined to them) split along staggered, jittered lines. `update` steps them
  against the collision grid and each other (one averaged contact, impulse, friction); hard landings knock pixels
  off as chips and rubble (`_splinter`); hits on mages/foes hurt (`_strike`). A tree collides by its wood only; its crown
  edge (`soft`) crushes: leaves that touch ground are knocked off as drifting leaf particles (`_crush`, once a
  frame), so the crown flattens instead of sinking. At rest (it hasn't moved or turned more than ~1 cell for 20
  frames) `_settle` writes it back with a raw stamp (stamp.comp mode 1: two words a cell, each layer only where
  it is empty): blocks unanchored (keeping their own built flag); a tree's wood in FRONT as ANCHORED logs (no
  creaking apart), its crown in the background as a fallen plant (id 0xF000.., bush rules: held by any part
  resting on something), pruned to the leaves joined to the logs (`_prune_crown`). Felled scraps under
  SMALL_TREE cells just flutter away. A piece only hurts after a ROCK_HURT_FALL-cell fall, through the upper
  half (as falling rock). plants.comp lets felled trees wait (0.002 a pass) for the CPU; pieces nobody lifts out
  still crumble the old way. In test mode each lift-out prints a `[chunks]` line. Pixel colours come from the picture on screen divided by the light.
  `save_world` settles everything still moving first.
  A tree's still-standing cells are found the way plants.comp grounds them (`_grounded`: wood on solid, on
  settled powder or liquid), and what came loose is split into its joined-up pieces (`_spread` floods a byte
  mark array); each piece falls on its own, scraps under SMALL_TREE flutter off as leaves.
- Profiler: `main.prof_add(section, usec)` anywhere; `prof` holds [average, recent peak, this frame, max since
  `prof_reset`, last frame]. GPU stages are timed with RenderingDevice timestamps in `gpu.step` (simulation, collision grid,
  light, picture). F3 shows the top sections; `main.hitch_us` is the longest frame of the game's own work (tests
  reset and read it). The test "frame time with no cap" turns vsync off and logs the breakdown. Foes are timed by
  part ("foes: think", "foes: creatures", "foes: <type>", "foes: moving", "foes: ecology"), drawing by overlay `_part`.
- The busy-scene benchmark (`_test_bench`, "bench"; the full run's LAST check, its fires and pits spoiled the checks
  after it; user, 21 Nov: the
  performance pass): 24 provoked foes, rain, a fireball every 20 frames, digging every frame, sand poured, vsync
  off, 600 frames; prints every frame over 50 ms with the parts over 3 ms, each part's worst, a histogram. Passes
  under 16.7 ms on average and 25 at the 95th percentile (27 ms average / 115 worst before; 7.6 / 14.7 after).
- Hot paths: `box_solid` / `box_count` read the collision grid bytes straight from `gpu.grid` through a 64-entry
  table (`_solid_table`), falling back on `gsolid` only off the grid's edge (cell by cell through `gsolid` they
  took 55 ms a frame with 24 foes). Loops over many points (vfx particles, overlay particles) use
  `main.screen_xf()` (world_to_screen as one Transform2D) when `screen_xf_ok()` (not the unrolled view), and
  particles read the light straight from `gpu.light_at`. The remaining spike is chunks' `read_rect` (a GPU sync
  when a tree or piece is lifted out, ~8 ms).
- No stalls (user, 22 Nov: "a small hitch when starting a new game"; a performance pass): `gpu.read_rect` waits
  for the frame in flight (flush + its own submit and sync), so code that reads now and then while you play
  asks instead: `gpu.request_rect(c0, r0, w, h)` goes out with the next frame's commands (dispatched at the end
  of `step`, read in its `flush`) and `take_rect(id)` has it a frame or two later. Spawning uses it
  (`_spawn_req`, `_spawn_ask`, `_spawn_finish`: the first creature a few seconds into a new game stalled the
  frame and then searched the block cell by cell; now open runs per column, `run`). The AUTOSAVE (every 7200
  ticks) no longer reads the planet back in one go (about 175 MB at ~0.75 GB/s: a quarter-second freeze every
  two minutes): `_autosave_begin` copies the world, back layer and seen map into a kept buffer on the GPU
  (`gpu.snapshot_begin`, `_snap_keep`, made at the first autosave), `_autosave_step` (right after the frame's
  flush) reads 8 MB a frame (`snapshot_step`), and `_write_world_parts` joins the slices and writes on a thread.
  Reading a slice straight out of a big buffer costs ~13 ms a call whatever its size (Godot's path for a buffer
  that size); `gpu._read_slice` copies it on the GPU into a small buffer (`_slice_buf`) and reads that: 4 MB in
  ~1.5 ms. `read_world_async` (leaving a planet) uses it too.
  A save of the world as it is now (`save_world`, `save_world_async`) cancels one on its way. Music is read on a
  worker thread (audio.gd `_read_music`, taken in by `_take_music`). Off-screen foes aren't drawn (overlay: most
  of them wait 160+ cells off), and `_sprite` reads the light once. Test: `_test_newgame` ("newgame": the title,
  Play on an empty slot with a grown seed (`test_seed`), 900 frames traced with creatures coming by, then an
  autosave; not in the full run).
- Readback: `gpu.step` copies counts, light, the picture and the collision grids into one buffer (`rb_buf`, offsets
  `rb_off`) read in one call; `grid` is that whole buffer, so index it from `grid_off` (grids) and `light_off`
  (light), never from 0.
- Chests at rest only fall after CHEST_LET_GO frames with nothing found up to 3.5 cells under them (the
  collision grid tilts with the planet's curve as the mage walks, so a single check flickered).
- Standing on the curved world through the flat grid (user, 21 Nov: foes bobbed as you walked): far from you the
  grid's rows sit up to half a cell off the world's, and that drifts as you walk, so a body resting on the grid is
  up to half a cell into or over the ground's top. `move_body`: `_unsink` first takes a body out of a sliver it sank
  into (it used to be lifted a whole cell, by a step "up" or the unstick, then fell back for frames), a fall ends
  right on the row it met (`_rest_on`), and a body standing last frame is put straight down on ground up to 1.05
  below (`was_ground`). Drawing: overlay `_feet` puts a grounded body's feet on the top of the world cell the grid
  has under it (`main.ground_top`), and `_sprite` hangs a frame by its lowest opaque row (`_gap_under`, not doors
  or chests), so frames with empty rows under the feet don't float; birds on the ground are drawn by their feet.
  The gap is worked out from the Image as a texture is made (`_make_tex`, `_image_gap`; Defs sprites from their
  rows): never `get_image()` on a texture while drawing, it stalls the renderer.
- `SCAFFOLD` is a one-way platform: `gsolid` ignores it, `move_body` lands on it from above
  (`platform_below`), and down + jump drops through (`drop_t`).

## The mage
- Frames (16 x 24) come from `/home/claude/tools/art/mage3.py` via `tools/sprites.py`, which also writes
  `Defs.MAGE_ANCHORS` (where the hat tip, beard, scarf and staff attach in each frame).
- `scripts/mage_rig.gd` simulates the hat tip, beard end and scarf (Verlet chains: rest shape, gravity,
  the body's inertia, air drag) and the staff (an angular spring that points where he casts). overlay.gd
  and title_screen.gd draw them as crisp pixels in the sprite's own transform, with the sprite outline.

## Gotchas
- Never take `%` of a negative number in a shader: Vulkan leaves it undefined, and on the NVIDIA laptop it came out
  right only when the divisor was a power of two (Verdance was 8192 columns round; at 12288, every stamp anchored to
  its right vanished). common.comp `wrapc` only ever takes `%` of non-negative numbers; use it. (render.comp's brick
  and plank patterns still take `%` of rows, which go negative in the orbit band: only a look, but mind it.)
- Tests that set something up "a little way from where you arrive" must look for a clear spot (`_clear_stretch`:
  level ground, nothing standing over it), not trust the layout: the planet changes size and seed.
- Windows reserves file names like `aux`, `con`, `nul`, `prn`. Never name a shader include that way.
- Local variables must not shadow Object methods (`set`, `_set`, `get`) or each other inside one function.
- Shaders: `/home/claude/tools/glcheck` plus `build_shaders.py` syntax-check them with Mesa, if those tools exist in the session.
- Scripts: run `Check scripts.bat` on the PC; it writes `saves/check.txt`. Under `--check-only`,
  "Identifier not found: Defs" is expected (the autoload isn't loaded); real parse errors show up as Parse Error.
- The test mode saves pictures of a few ruins and buildings to `saves/shots/` (midday, no title screen);
  stage them through the device bridge to look at the art without walking around in the game.
- Don't take computer-use screenshots while the test mode runs: the screenshot hides (minimizes) the Godot window,
  it stops redrawing, and every picture in `saves/shots/` after that is the same stale frame (the tests still pass).
- Testing on the user's laptop: files are committed to `C:\Wisp Forge` through the device bridge. Wait about 12 s after
  writing to `/mnt/user-data/outputs` before committing, otherwise stale copies get written.
