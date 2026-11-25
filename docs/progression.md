# Wisp Forge: Progression: the main quest, barriers, cores, ores, gear, hazards

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## The main quest (scripts/quest.gd; user, 23 Nov: "add a main quest system to guide the player through the main progressions"; chose: the wisp companion speaks it, a HUD line + journal, and the wisp's own powers as rewards)
- main `quest` (a RefCounted), `quest.tick()` from `_tick` on the planet and in space; every 30 frames it ticks off
  steps whose condition holds (`need`: a list of conditions, ANY one does: "held" mat n, "found" ore, "spell",
  "tier", "item", "landed" planet index (main `landed_on`: `items["landed"]`, set by `_make_world`'s `note_landed`;
  a save from before gets every planet it has a world file for), "landed_other" (any round planet but c[1]),
  "landed_sys" (any planet of another system than c[1]), "count" items key n, "station" kind (set down or carried), "learned", "heat").
  Chapter 0 (`_first_chapter`, 19 steps: dig, Spark Bolt, Kiln, smelt, Copper Focus, Levitation, the Mana Crystal
  (learned on finding a Wisp Ingot; the Obsidian Focus also ticks it off), Obsidian Focus,
  a Summoning Altar, a guardian beaten (half the skiff's plans), a second (the plans whole: the skiff's recipe),
  Heat Ward, Vulkhar, Core Siphon, 30 core, Core Drive, the skiff, star iron, the voyage to
  `open_target(0)`: the round's first world with no barrier); a later planet you land on gets `_world_chapter(i)`
  (its ore, a ward per hazard of its climate, the Heat Ward on a hot one, then `next_target(sys, i)`: the next
  world of the round not landed on, one in reach first, with "key_<item>" (forge its barrier's key) when it's
  walled, then "voyage_<i>"; with all of them landed on: the Starsail, 15 Wisp Cells, "stars" (another system)).
  Chapters follow the planet you're on in any order: one not finished (`items["qfin"]`) is taken up when you land
  there; a step done once (`items["qdone"]` "ch:id") stays done and never pays twice. Each step: "title" (the
  HUD's gold line, ui `quest_lbl`), "say" (the wisp, overlay `_bubble` over `main.wisp`; a toast instead out in
  space), "how" (the journal), "reward" (coins / potion / cells), "power". Saved as `items["quest"]` {ch, at, v: 4};
  a game with none, or with an older "v" (the steps moved), catches up QUIETLY from the top (no rewards, the powers
  earned granted), so old saves are fine. `quest.reset()` on
  `start_game`. In the test mode it only runs while `quest_test` is set.
- The journal: L (ui `toggle_journal`, `journal_open`; Esc or L closes; `menu_paused` includes it, so the world
  waits): the chapter, every step (done, now with its "how", to come), the wisp's gifts.
- The wisp's powers (`items["wisp_<id>"]`, `Quest.POWERS`): LANTERN (Copper Focus: `_update_wisp` light 92, not
  46), SENSE (the second guardian: `_wisp_powers` every `SENSE_EVERY` 480 ticks on the planet `gpu.request_rect`s 260 x 170
  cells round you, `_sense_take` keeps up to `SENSE_MAX` ore cells of `SENSE_ORES` as world points; overlay
  `_draw_sense` shows them over rock and fog as a wave spreads, `SENSE_SHOW` ticks), WARD (Vulkhar: `hurt`'s
  first hit of 1+ on the local mage is taken, `wisp_ward_t` = `WARD_RECHARGE` 1800; a faint ring round the wisp
  while ready), HANDS (the Core Drive: `_reach` x1.5, voidlife's mote reach x2).
- Fixes from play (25 Nov): "station" needs count only a workshop standing in the world (`workshops.list`), not one
  forged and still in the satchel (user: "the wisp said to set down a kiln and as soon as i crafted it the next part
  started"); a step "Find copper ore" ("copperore": found copper, or Spark Bolt known) comes before forging Spark
  Bolt, since its recipe is learned from the first copper (user: "the wisp says press c, but i dont see it in
  there"). Inserting a step is safe for saved journeys: done steps are kept by id (`qdone`) and the walk from `at`
  skips them. The kiln and smelter steps' "how" say F with ore in hand drops it in and F takes the tray.
- Test: `_test_quest` ("quest"; in the full run after `_test_start`): a bare start, every step made true in turn
  ticks off in order with its rewards and powers, each power works, the journal pauses, an old journey catches
  up quietly, chapters 2-8 well formed; pictures `quest_wisp.png`, `quest_sense.png`, `quest_journal.png`.

## Progression and climate (user, 20 Nov: fewer towns unless it's that kind of planet; the progression pass)
- Getting off the first planet (user, 24 Nov: "Core drive is required to craft the wisp skiff"): the Core Drive
  (recipe "drive": 30 Planet Core, 10 Wisp, 4 Copper Ingots; needs the Core Siphon, tier 4, which needs Vulkhar's
  Ember Heart) is `items["drive"]`, and the skiff can't be forged without it (`recipe_unlocked` "skiff"). A save with
  a skiff counts as having one. (`items["reach"]`, `skiff_reach` and the per-planet drive are gone.) The skiff's
  RECIPE (user, 24 Nov: "more gauranteed and feel more like a quest ... summoning and killing a gaurdian or some
  gaurdians"): no shop or scroll; every guardian beaten (`_guardian_falls` -> main `skiff_plan_found`) gives half of
  a wisp shipwright's plans (`items["skiff_plans"]`), and `Defs.PLAN_HALVES` (2) teach it (LEARN "guardians").
- BARRIERS BY KIND (user, 24 Nov: "only gate the planets in types not individually ... if you have the item to
  traverse storms it u locks all storm covered planets"; chose: by planet kind, procedural and thematic):
  `Defs.BARRIERS` (storm: Storm Lattice "lattice"; radiation: Radiation Ward "radward"; shards: Rime Prow
  "rimeprow"; maelstrom: Tempest Keel "keel"; each with name, key, key_name, col, tell), `KIND_BARRIER` (temperate,
  wild, realm, marsh: none; ocean and giant: storm; volcanic and desert: radiation; frozen: shards; abyss:
  maelstrom), `Defs.planet_kind(i)` / `barrier_of(i)`. A first system always has one of `OPEN_KINDS` (`_planet_kind`
  swaps one in; the classic system's is Fenhollow). main `barrier_ok(i)` (`exotic_ok` is the same); space.gd
  `reachable(i)` = home or barrier_ok, `barrier_name`, `barrier_key_name`; bodies carry "barrier" and its colour.
  Keys: lattice (copper ingots, star iron, glass; learned on star iron), radward (hull plating, wisp ingots,
  crystal, star iron; on hull plating), rimeprow (xenite, star iron, hull plating; on xenite), keel (as before);
  all hidden until the skiff. NO INVISIBLE WALL (user, 20 Nov): a walled planet's barrier (`_storm`,
  `BELT_IN`..`BELT_OUT` above its orbit band): `_draw_belts` shows a shimmering curtain at its outer edge and a haze
  inside, plus per kind: radiation's rippling bands and flaring motes, a shard ring's tumbling slivers, the
  maelstrom's spiral arms, a Thunderhead's forks; in it the wind pushes outward (0.03 + 0.85 f^2 a tick, f = how
  deep, 0..1), takes speed coming in, gusts sideways, blows sparks past, and it hurts its own way: storms and
  maelstroms strike (`_strike`, a Thunderhead x4), radiation burns through the hull onto you (`_irradiate`),
  shards hole the hull (`_shard` -> `skiff_hit`); at f >= 1 you're thrown clear. Full thrust stalls about halfway
  in. A toast names the key. `_hold` is only for a reachable planet still being made. Markers and the map's
  system chart say "<barrier>: needs a <key>". STAR IRON (material 50) is only in asteroids (asteroid.gd: metallic rocks' hearts, a speck in stony
  ones).
- CORES BY KIND (user, 24 Nov: "Different types of cores for different types of planet allow crafting powerful
  spells and gear ... Rare planet types have rarer core materials"): materials 64-71 (NM 72): EMBERCORE volcanic,
  TIDECORE ocean, SUNCORE desert, MIRECORE marsh, RIMECORE frozen, WILDCORE wild, CROWNCORE realm, ABYSSCORE (the deep
  ocean world: the rarest); `Defs.KIND_CORE`, `kind_core(pl)` (a temperate world's, and a giant's, is CORE),
  `is_kind_core`. Never in the world: every heart is CORE cells, and main `_apply_counts` puts what the siphon takes
  into `core_mat` (set in `_make_world`). The collision grid keeps a cell's type in 6 bits: world materials must
  stay under 64 (chunks.gd `_solid`). The forge's "Core Arts": a spell and a gear piece per core, learned on
  finding it (LEARN "find"). The spells are DATA: SPELLS ("art" the glyph they share, "snd"), SPELL_FX, PROJ with
  "multi"/"spread" (a fan: main `_cast`, space `_space_cast`) and "arts" (hit, blast/bkind/bdmg/bpow, splat+sr,
  freeze, area/area_r/knock, slow/slow_r, heal, chip), done by main `_arts_impact` (and space `_sbolt_impact` on
  aliens): Cinderstorm (cinder: three fireballs), Tidal Surge (tidal: "surge" is a guardian's shot), Sunlance,
  Mire Grasp, Glacier Nova, Thornburst (five thorns), Sovereign Bolt (heals you), Leviathan's Wrath. The gear is
  GEAR entries with "core" (cinder crown, tidewalker's greaves, sunforged diadem, bogheart plate, rimeglass lens
  "rimelens2", heart of the wild, crown of ages, abyssal heart). A later world's quest chapter asks for 10 of its
  core. Test: `_test_cores` ("cores"; in the full run after `_test_giant`; picture `core_spells.png`).
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
