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
  (`PLANETS[i]["radius"]`, Verdance 1304). Rows count down from the top of the atmosphere (`R_TOP` = radius +
  `ATMO`, row 0) to `R_IN`; the orbit band above the atmosphere has NEGATIVE rows (-`ORBIT_ROWS`..-1) up to `R_SPACE`.
  Shells are stored top to bottom (`SH_Y0`/`SH_Y1`/`SH_N`/`SH_OFF`; every `SH_Y0` even). The surface shell (`SURF`,
  `NS` columns = square cells at the mean surface, a multiple of 64) reaches `SURF_HALF` (330) rows up and down, so
  the ground lies in it. Above and below it the shells are thin (`SEAM_STEP` 0.021: each has about 2% more or
  fewer columns than its neighbour, multiples of 16; under 3.2% above radius 320, larger only near the heart), and
  every shell's cells are square at its middle, so the view never visibly changes size at a seam (the user saw a
  2x squeeze at the old halving seams). Verdance: 110 shells, 13 M cells. Neighbours across a seam: `colTo(from, to, x)`
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
- Space (`scripts/space.gd`, a Node2D under the overlay): levitating into the top of the orbit band
  (`R_SPACE - 9.5`) calls `space.try_enter()` (a party can't leave yet: more than one player blocks it). It takes the
  planet's picture (`main.capture_planet`: one render with the camera at the centre, zoomed so the band fits,
  turned to the view's angle), and from then `_tick` hands over to `space.tick()`: the staff jet (hold cast, push
  toward the aim, mana), the planet's pull fading with distance, a wisp bubble (no breath), the camera zooming out
  with distance. While `zoom < SWAP_ZOOM` the live planet is still rendered (`live`); beyond it the GPU does
  nothing (`_process` skips `_gpu_frame`), `view_c` follows `cam_c`, and space.gd draws the stars, the sun, the
  other planets (procedural discs from their biomes, `_disc_image`) and the planet's picture (a Sprite2D masked to a
  disc, placed by the world->screen affine). Back below `R_SPACE - 10` moving inward: `exit()`, the zoom eases back
  (`planet_tick`), a short cooldown. Space shares the world coordinates of `space.home` (the planet the GPU holds, at
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
  is (`sun_ang`), its picture is taken, and it is saved. `_enter_planet` (title, portals) runs the same
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
  of 2-4 over the orbit band from the planet's seed, or loaded from `planet_state["asteroids"]`, written by
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
- Test mode quits by itself after 7 minutes, so a broken run never leaves the game open. tests.gd is loaded at run
  time (not preloaded), so a parse error in it quits the game instead of leaving a blank window. `Check scripts.bat`
  stops at the first error per file (the expected Defs one), so it can't catch later parse errors in tests.gd:
  watch for a local that reuses a name already declared in the same function (lambdas included).
- Below-ground masonry (dungeon runestone too) gets ragged, stepped outer edges (`_roughen_underground`, run by
  `_finish`), so shafts and buried halls don't meet the earth with ruler-straight lines. The added cells are written
  outright (anchored, not F_FILL: a fill only lands in open space, so it never showed against solid earth), and only
  ever outward into the blueprint's untouched (255) cells, so halls and shafts stay as built.
- Biome borders: gen.comp picks one of the two neighbouring biomes per cell with noise at three scales (lobes,
  fingers, single grains), so their layers interfinger instead of meeting at a seam.
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
  back). Archers are a third of structure guards (picked by position in `_guard`); the dead walk at night.
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
