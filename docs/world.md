# Wisp Forge: The planet: geometry, cells and counters

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

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

## GPU counters
- GPU counters: `Defs.CNT` (128) per player, one per material below `C_HARD` (112), then `C_HARD`, `C_PLACED`,
  `C_FALL_N`/`C_FALL_MAX`, `C_CHEST_OPEN`, `C_CHEST`, `C_CREAK_N`/`C_CREAK`, `C_FOG`, `C_FELL_N`/`C_FELL`,
  `C_TREASURE` (also #defines in every shader). They used to start at 50, so digging what the staff couldn't cut
  counted as star iron; a save without "cnt": 2 has its star iron zeroed on load. Materials must stay below 112.

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
