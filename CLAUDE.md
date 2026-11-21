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
  the origin); every planet's place is `Defs.planet_pos(i)` (`Defs.SYSTEM`, a round of five; the next round lies
  400000 along x), and `bodies` are the round's planets relative to home. The nearest planet (`near`, `centre`)
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
  sky), hail (pellets; a sting every 35-70 ticks in the open), bloodmoon (`spawn_mult` 2.5, up to 12 foes),
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

## The UI (scripts/ui.gd, pixel_font.gd, icons.gd; user, 21 Nov: a pixel-art UI)
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
- The satchel is a grid of `_slot`s (icon at 2x, count), the spell bar slots with glyphs, their number, the
  cooldown and a red wash when mana is short (`_draw_slot_over`), the chosen spell's name over it; the forge
  fills the screen (`show_forge`: 3-5 columns), with a tab per category (jumps the list) and cost chips
  (`_cost_chip`); shops in two columns. Test: `_test_ui` ("ui": the font has every character the game writes,
  whole-pixel scale, satchel and spell bar on screen; pictures `ui_hud/forge/settings/shop/title.png`).

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
- Prey creatures: hare (forest, savanna, mountain), snowhare, deer (a herd of 3), skink, reedfrog. Test: `_test_ecology`
  ("ecology").

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
    tree is only held by its wood touching the ground, so a cut tree drops whole and fast.
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
- Straight building (build.gd `SHAPES`, main's `_update_shape`): back walls (Back Walls tab) and solid blocks
  (Blocks tab, `CAT_BLOCKS`) are laid by pressing, dragging and letting go: a line snapped across, up or at 45
  degrees, a filled rectangle, or a frame; G cycles the shape (back walls can also be brushed), [ ] the
  thickness. `Build.shape_cells` / `shape_stamp`; one material per cell; blocks skip cells where someone stands.
- Spells with "single" in `Defs.SPELLS` cast once a click (user, 21 Nov: the start was too strong): `Mage.cast_latch`
  is set by `_cast` and cleared when the button is let go. Spark Bolt is single, 12 mana, 30 ticks, reaches 220
  cells (it was 4 mana every 9 ticks while held). Test: in `_test_vfx`.
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
- Running one test section: a non-empty `saves/test_only.txt` naming it ("climb", "nav", "guardians", "wardens", "biomes",
  "worlds", "creatures", "ecology", "sky", "gear", "towns", "vfx", "ui", "stampdiag" or "mines": a print of each mine the soundness pass cut, with where) runs just that
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
  arena (`_lair`: dry, level enough, `LAIR_W` 440 wide (360 at a pinch), levelled and paved, ramping to the land,
  cleared `LAIR_UP` 150 to the sky, a stepped `_mesa` beside the middle) at least 600/8192 of the way round from the
  start, else an underground hall (`_lair_deep`: 360 x 120, 200 rows down, a shaft with landings from a small gate
  on the surface), then the same at 380/8192; never within `LAIR_W` + 160 columns of another lair. Only biomes in
  the planet's "guardians" get one (`guardian_biomes`). Both use `_pillar` and `_shrine` (cover stubs, a stepped dais
  with an altar, braziers, a carved stele standing on the floor, a sure chest). `lair_list` ({biome, pos, name, deep,
  tether, arena, ceil}) -> main `_spawn_guardians` (`Enemy.arena`: the arena's half width; `tether` reaches `LEASH`
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
  liquid test reversed). Test: `_test_far_biomes` ("biomes": enters Cindrel and Thalassa, `_test_guardians(["ashland"])`
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
  `prof_reset`]. GPU stages are timed with RenderingDevice timestamps in `gpu.step` (simulation, collision grid,
  light, picture). F3 shows the top sections; `main.hitch_us` is the longest frame of the game's own work (tests
  reset and read it). The test "frame time with no cap" turns vsync off and logs the breakdown.
- Readback: `gpu.step` copies counts, light, the picture and the collision grids into one buffer (`rb_buf`, offsets
  `rb_off`) read in one call; `grid` is that whole buffer, so index it from `grid_off` (grids) and `light_off`
  (light), never from 0.
- Chests at rest only fall after CHEST_LET_GO frames with nothing found up to 3.5 cells under them (the
  collision grid tilts with the planet's curve as the mage walks, so a single check flickered).
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
