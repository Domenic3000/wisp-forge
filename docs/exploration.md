# Wisp Forge: Exploration: world-bound finds, places to discover, gear as a project, traits, artifacts, the Worldsong, bigger worlds

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Why (27 Nov)
The user: "what else can we add content wise to make finding and exploring distant worlds have meaning and be more
exciting. it seems very easy to get the new gear once you find a recipe. it doesnt really feel like a very developed
gameplay loop yet." They chose all four of world-bound materials, places to discover, multi-step crafting and gear with
rolled traits, and "study artifacts" for how recipes are learned. Then: "an idea i would like to implement somehow to
make the game world regenerate itself and make the worlds larger still while not making it to hard to find key quest
and progression enemies" (chose plants and trees regrow, creatures repopulate, "a magical force that will slowly
rebuild the terrain. maybe part of the story?", worlds 1.5x with the wisp's guidance), and "foliage that goes a bit
underground and doesnt just cut off" (new worlds only).

## The loop
Land on a world -> the wisp feels its hidden places and marks its heart, dungeons and villages -> the places' chests,
its deep creatures and its bosses give its OWN FIND and ARTIFACTS -> a Lectern's study of an artifact teaches that
world's better recipes -> the workshops make PARTS -> forging gear (better at an anvil, on its own world, in a Wisp
Archive) rolls TRAITS -> reforging at the anvil, with more of the world's finds, chases better ones -> on to the next world.

## World-bound finds and parts (defs.gd)
- Materials 72-83 (NM 84; satchel-only, `PLACE` 0): finds PHOENIXASH volcanic, SIRENSCALE ocean, MIRAGEGLASS desert,
  BOGLOTUS marsh, EVERFROST frozen, HEARTSAP wild, KINGSGILT realm, LEVIINK the deep ocean world (`KIND_REAGENT`,
  `kind_reagent(pl)`, `is_reagent`, `reagent_kind`, `reagent_where`); parts LENS (Kiln: 4 glass, a crystal), FRAME
  (Smelter: 2 copper ingots, a wisp ingot), THREAD (Still: 6 leaves, 2 wisp, 2 water), SETTING (Smelter: star iron, 2
  wisp cells, a crystal) in `PROCESS`. Icons: icons.gd `ART_MATS` rows ("art" style). The satchel's "Rare finds & parts".
- Where finds come from (main): a place's chest (`place_loot`), a guardian 3 and an artifact, a warden 2 (half the time an
  artifact), a heart 6 and an artifact (`give_reagent`, `add_artifact`), a chest 120+ under the ground now and then, and
  a creature killed 120+ deep (6%, 12% past 300). None on a temperate world.
- `gear_cost(id)` (what the forge asks; GEAR "cost" is the base): tier (`gear_tier`: an ore's 1st piece 0, 2nd 1, 3rd 2,
  alloys 2, core gear 3, the void's mantle 1) and part (`gear_part` by its first mod, `PART_STATS`): tier 0 + a part;
  1 + 2 parts, 2 finds; 2 + 2 parts, 4 finds (an alloy 3 of each world's); 3 + 2 parts, a Star Setting, 5 finds.

## Traits (main)
- `Defs.TRAITS` (16: swift, keen, thrifty, warded, steady, deep, bright, springy, hardy, brimming, far, tidal, cooled,
  fiery, crackling, biting), each one stat and "v" at full strength. `roll_gear_traits(id, who)` on forging (and
  reforging): how many by `TRAIT_ODDS[quality]`, each strength 0.6..1.0 x (1 + 0.12 q); kept in items["t_<id>"]
  [[trait, strength]]. `gear()` reads them (`_trait_keys`, `_trait_stats`); max health / mana / regen given once
  (`_trait_once`, taken off again when rerolled). Names: `gear_name` ("Fine ...": `GRADES` by count), `gear_traits_text`.
- `forge_quality(id)` [0..3, reasons]: an anvil within reach, the piece's own world (`gear_kinds`), inside a Wisp Archive.
  The forge card says it (`forge_quality_text`). `roll_traits` false in the test mode (gear's stats checks), but in
  `_test_loop`.
- Reforging at the anvil's panel (ui `_render_station`): `reforge_block` / `reforge_gear`, paid `Defs.reforge_cost`
  (2 of its world's finds, 1 of each for an alloy, and a Wisp Cell).

## Artifacts and the Lectern
- items["artifacts"] [{k: world kind, n: name, s: seed}] (`Defs.make_artifact`: name from `ART_STUFF` x `ART_THING`;
  icons.gd `artifact(a)`, `ARTIFACT_ART`). The satchel's "Artifacts" section.
- The Lectern (`STATIONS` "lectern", burn 0; workshop_art `_lectern`: glyphs and a mote glow while studying; forged at
  the Wisp Forge's Workshops): F opens its panel (ui `_render_lectern`): Study lays one on it (workshops.gd `study`:
  `st.cur` "art:<kind>:<seed>", `st.prog`), Take it back (`unstudy`; taking the Lectern up returns it too). `_study`
  counts `Defs.STUDY_TICKS` (2700) while you're on its world, then main `study_done`: a recipe from `study_pool(kind)`
  (LEARN "study": the 2nd/3rd ore pieces, alloys and core gear by their world; a temperate artifact any), or with none
  left 3 of its finds (or 40 coins); 60% of the time it reveals a place not yet found (`places.reveal_one`).
- `Defs.learn_of` for gear: the 1st piece still on finding its ore; the rest "study" (and a smithy or a hoard as before).

## Places to discover (places.gd)
- Planned by buildings.gd `plan` last (`Places.plan_all`, its own RNG; `buildings.places`), only when `with_places`:
  main sets planet_state["places"] when a world is first made, so a world made before has none. Not on exotic worlds.
  Each kind `round(N0 / 8192)` times, 380+ columns from where you arrive: `_archive` (124 x 60 underground, two floors,
  gallery gap, crystals, bookshelves, 3 skeletons, 2 sure chests), `_sanctum` (116 x 46: antechamber with three
  pedestals under glyphs and the order high on the wall (Mystery GLYPHS), a RUNESTONE wall "ward", the vault with 2 sure
  chests), `_wreck` (96 wide on the surface: a crater, a HULL capsule half buried, glass canopy, wisp engine, star iron
  specks, torn open on top, a sure chest on its deck; `_claim`ed).
- As you play: `tick` (every 10 frames): found within FOUND_R (or inside), hinted within HINT_R ("something old, far
  below us"); a sanctum's braziers in reach (F: `kindle`, KINDLE_MANA; wrong one: all out; all three in order: `_open`
  stamps the ward away); a wreck smokes. `marks()` on the map and minimap, `summary()` in the journal. Saved:
  planet_state["places"] {v, found, hinted, revealed, opened}. Overlay `_draw_places` (bowls and flames).
- The wisp's guidance (`guide`, every GUIDE_EVERY): the heart (until beaten), then the nearest dungeon (warden alive)
  or living village not seen, within GUIDE_R: planet_state["guided"], drawn on the map and minimap.

## The Worldsong (mending.gd, gen.comp mend mode)
- Digs, blasts and chips (main's brushes after each step) mark 64 x 64 blocks (`note`; planet_state["wounds"]). A block
  left AFTER (150) s, no mage within FAR (260), not near home, a workshop, the skiff, a chest, a place or a structure
  (`kept`) gets a pass every EVERY (90) frames, up to PASSES (40): gpu_world `mend_jobs` -> gen.comp with pc.a.w = 1 over
  that window: an empty cell whose made self was ground fills (2+ solid sides, CHANCE per mil: holes close from their
  walls; ore comes back as stone), plants grow back where nothing is; never within 2 cells of anything built, a back
  wall, furniture or a chest, never the heart. `gpu.mend_prepare(boss_info, sites)` once a world (the generator's inputs).
- The wisp names it once you come near a block mended 8 passes (items["worldsong"]).
- Fallen guards (planet_state["slain"]) come back GUARD_BACK (1500) s after they fell, with you 600+ off
  (planet_state["slain_t"]). Wild creatures already come and go; bosses and wardens stay beaten.
- `enabled` is off in the test mode but for `_test_loop`'s check (`run(w, 1000)` on a dug pit).

## Bigger worlds (defs.gd)
- `WORLD_GROWTH` 1.5 x the radius of a world first made from now on (`growth_of(i)`; exotic worlds as they were); the
  journey's worlds with a world file when its save was first loaded after this keep their size (`small_worlds`, saved
  "small_worlds" / "gset"; `planet_key` has it). Biomes, structures and places scale with the columns.

## Roots under the small plants (gen.comp `rootlets`, new worlds only)
- Front ROOT cells in soil (`rootSoil`: dirt, grass, mycelium, dry grass, moss; not sand, snow or mud, where burrowers live) from the soil's second row: a tap root and a fan of fibres under bushes and
  hedges, a thread under each tuft, shallow and wide under cacti, under ferns' and mushrooms' stems.

## Also this round
- The skiff's turn (skiff.gd `sweep_u`, `sweep_s`, `sweep_rows`, TURN_STEP; overlay `_draw_swept`, `_draw_sweep_line`;
  main `_skiff_turn_fx`): redrawn column by column behind a line of wisp light, never narrowed (user: the old flip
  "looks like a piece of paper ... use the pixel identity").
- Creatures and villagers stand steady (overlay `_steady_feet`; user: "the lizards in the desert move up and down a few
  pixels as the player moves"): the grid is sampled at your exact place, so as you walk the ground row under a still
  creature flips a cell; each body remembers its column and drawn ground and keeps the higher within a cell.
- What's built of hardness 2 or less comes away whatever the staff (brush.comp `powF`/`powB`, `BUILT_SOFT`; main
  `remove_cells`; user: "i crafted brick ... now i cannot use the right click gather or unmake to remove it").
- Test: `_test_loop` ("loop", tests/player.gd), pictures place_archive.png, place_sanctum.png, place_sanctum_open.png,
  place_wreck.png, lectern_panel.png, worldsong.png.
