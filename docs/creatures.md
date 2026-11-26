# Wisp Forge: Wild life, creatures, foe AI and pathfinding

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

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
- A beast asleep ("_sleep": lie, graze 0.9) rests its head low in front, long ears laid back along its body and
  antlers tilted back (user, 22 Nov: held up over a body flat on the ground they read as legs in the air, and
  deer and hares looked upside down until they woke). `_test_ecology` saves `eco_prey_sleep.png` / `_woke.png`.
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
  overlay `_eco_marks`). New frames: beast "_graze", "_sleep" (26 Nov, the art pass: a six-step walk "_walk0".."_walk5" with each
  foot lifted as it swings forward and the body a pixel down as the feet land, overlay picks `int(anim * 0.9) % 6`;
  standing, `_beast_idle` shows "_breathe" (the body a pixel up, the tail flicked) half of each 90 frames and
  "_blink" (eyes shut) 7 frames in 230, each creature in its own time by `phase`; the walk cycles are drawn into
  saves/shots/beasts_walk.png by `_test_ui`); toad "_croak", "_crouch", "_sleep"; bird "_perch",
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

## Wild creatures and foes
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
- The new biomes' own (26 Nov, see generation.md): basalt: basaltmonitor, steammoth; kelp: tideotter,
  kelpserpent (plus stormgull); saltflats: salthopper, miragefox (plus vulture); mangrove: mirecroc, heron (plus
  reedfrog); crystalfields: crystalstag, shardlynx (plus snowhare); elder: mossbackelk, fernstalker (plus hare,
  deer); meadow: meadowsheep, bumblewing, hedgefox (plus hare).
- The exotic worlds' (26 Nov, docs/exotic-worlds.md): a dying star: flare wisp, slag crawler (and the basalt
  monitor); a black hole's rifts: rift ray, null stalker (its shards of worlds keep their own biomes' creatures).
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
- A burrower whose ground is dug away round it (`Enemy.was_in`: it was in its ground last frame) is not
  deleted: `Ecology.unearth` throws it out onto the ground (`stranded_t` = `STRANDED` 150), `_stranded`
  writhes it there (hittable), then digs back into soft ground under it, or crawls (`goal_p`) to the
  nearest ground deep enough within ~48 cells (the bottom of your hole may be too shallow), tunnelling
  straight into it when it's within 14 (a pit's side), or stays out on rock and looks again. A burrower spawned in the open still sinks as before.

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
