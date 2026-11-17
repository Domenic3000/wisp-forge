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
- Background harvest (`_pick_up_furniture`) checks the collision grid for furniture before reading the world back;
  a read that finds none isn't repeated at the same spot (`_pick_miss`).
- Save slots: saves/slot_1..3 (`SLOTS`, `slot`, `_save_dir`), each with its progress.json and worlds; the title
  lists them (title_screen.gd `refresh_slots`: continue a saved one, start in an empty one, Delete twice);
  `quit_to_title` (Esc menu) saves and returns there. Saves from before slots move into slot 1
  (`_migrate_old_saves`). settings.json stays in saves/; the test mode uses saves/test.
- Window: setting "window" (windowed, fullscreen, exclusive), F11 / Alt+Enter switch; the test mode stays windowed.
- Foundations: two courses of the building's stone, then the biome's own ground layers (`_ground_mats`); yards are
  made of the biome's soil too.
- Test mode quits by itself after 7 minutes, so a broken run never leaves the game open.
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
- Clouds live in world space (`shaders/inc/clouds.comp`: `cloudLow` near the ground, `cloudHigh` the weather
  layer above the mountains; `cloudDensity` is both): render.comp draws them over everything
  at their height (fog when you fly in), react.comp spawns rain/snow/ash only under the high layer's undersides, and
  grid.comp writes each mage's cloud depth to counts[58] (`Mage.fog`: misted sprite, wisps in overlay).
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
- Testing on the user's laptop: files are committed to `C:\Wisp Forge` through the device bridge. Wait about 12 s after
  writing to `/mnt/user-data/outputs` before committing, otherwise stale copies get written.
