# Wisp Forge: Places in space: wrecks, pirates, outposts, stations, void life

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Wrecks, pirates, outposts, stations and the life between the stars
- DERELICT WRECKS (scripts/wreck.gd; user, 23 Nov: the roadmap's next step, "things to find out there", starting
  with wrecks): `Wreck` extends asteroid.gd, so space.gd streams, drifts, mines and keeps it like a rock (kind
  "wreck"; torn plating round it is an ordinary rock of kind "scrap", `Wreck.scrap`). `make_wreck(seed, first)`
  grows a wisp ship from parts: HULL plating (material 60, "Hull Plating", hard 2: salvage) in courses with
  seams and rivets (`_plate`), a prow sweeping down, a stern engine room (star-iron nozzle, wisp core, copper
  pipes) through a bulkhead door, a hold of one or two decks (two only where each is 27 high; the hatch, 20
  wide, in the widest room), bulkheads with 24-high doorways, a bridge cabin over the hull with a cracked glass
  front, timber panelling and ribs on the back layer (`bg`, drawn by its own sprite under the hull), lamps
  (CRYSTAL) under ceilings; then damage (`_breach`: the first always through the roof of the hold away from
  the bridge, 12-14 across, wide enough to drift in; one or two more, at most one small one through the keel;
  sometimes the prow broken off; scorching and coal round the tears); then CACHES (`caches`, 9 x 6 crates:
  bridge first, engine, a hold crate per room; `_crate_near`). Every passage is 18+ across so the mage's
  7 x 17 box drifts through whichever way the wreck lies. `guarded(k)`: a closed cache's cells are left by
  mining and blasts. A wreck never splits (`_split`). `save`/`from_save` add name, fate, caches, the back layer
  (space `_rock_from_save` picks the class). Galaxy: `WRECK` 0.045 a sector (`_wreck`: the wreck + 3-6
  scrap), and `first_wreck()`: every journey's first, `FIRST_WRECK` (22000) from home on a bearing kept
  18000 from every planet (so no journey begins near it); its bridge always holds a part.
  In space (space.gd): the mage collides with a wreck by `_shortest_out` (the least move out, 16 ways, up to
  6 cells; never "away from its middle", which pushed you through a wall from inside), over `box_pts` (4 x 9
  points: no 2-thick wall fits between them). `_wreck_near` (on foot): aboard the first time, a toast of its
  name and fate (`visited`); the closed cache within `CACHE_REACH` (18) is `near_cache`, drawn "[F] open the
  cache" by `_top` (a child Node2D at z 1, over the rock sprites: prompts, cannon bolts, the shield). main
  `_interact` -> `space.wreck_interact` -> `_loot`: hold (plating, ingots, planks, glass, now and then star
  iron, coins, a draught), engine (star iron, wisp and copper ingots), bridge (coins; a part you lack, the
  first wreck always, else 70%: `items["part_shield"]` then `["part_cannon"]`; half the time a star chart,
  `_star_chart`, the nearest uncharted system; a recipe scroll 40%; the captain's log, its fate). Markers:
  `nearest_wreck` ("Wreck of the ..."); `nearest_rock` leaves wrecks and scrap out. The map draws a wreck in
  explored sectors with its name.
- PIRATES (scripts/pirate.gd; user, 23 Nov: pirates with skiff hull damage and repair): `Pirate` extends wreck.gd,
  so it lives in space.gd's `rocks` (kind "pirate", sect "pirate": never saved, dropped by `_drop_pirates` on
  landing or falling) and is drawn, collided with and blasted like a wreck. `make_pirate(seed, cls)` grows it
  (`CLASSES`: "cutter" 64-72 long, 90 hp, one gun; "brig" 88-100, 170 hp, two guns, two masts): dark plating
  (`_dark_plate`) over a keel rising to the bow, a red TILE stripe, an obsidian ram and a bowsprit, a raised stern
  castle (glass windows, an ember lamp, a red lantern), an EMBER engine (`stern`), masts with tattered COAL sails
  (the main one with a SNOW skull), pennants, deck guns (`guns`: barrel mouths; `gun_ok` once one's shot away)
  and a strongbox on the castle's roof (a cache of kind "pirate", always reachable from above). space.gd:
  `_pirate_chance` (aboard, deep space only: `PIRATE_CLEAR` above any orbit band, not over 50 a tick, every
  `PIRATE_EVERY` ticks a 55% roll; `pirates_ok`: the cannon fitted, or 150000 from the first system; never in test
  mode unless `allow_pirates`), `spawn_pirates(focus, dir, cls)` (1300-1700 off: a cutter, a brig or two cutters,
  `PIRATE_MAX` 3), `_update_pirates` (a ring round you at its "range", flattened top to bottom (0.55) so it fights
  on screen, switching sides; keeps off rock, each other, planets' air; pitches toward you at most 0.45 rad and
  flips `facing` to keep its deck up; fires every "fire" ticks within 2.2 x range, `_pirate_fire` leading you; lost
  past `PIRATE_LOSE`), `foe_shots` (`_update_foe_shots`: 2-cell steps against the skiff's cells, a mage on foot's
  box, rock (`_chip`)), cannon hits `_hurt_pirate` (`CANNON_DMG` 12), `_beat_pirate` at 0 hp: kind "wreck", a fate,
  2-4 scrap, blasts, a lifeboat streak, kept with the sector it's in (`touched`), `items["pirates_beaten"]`; its
  strongbox loot in `_loot` "pirate" (coins, star iron, wisp ingots, plating, sometimes an ore, chart, scroll,
  draught). Markers in red, a hull bar over a hurt one (`_draw_top`), HUD weather " · Pirates!".
- TRADING OUTPOSTS (scripts/outpost.gd, spacer.gd; user, 23 Nov: outposts with traders, then "much bigger more
  complex outposts"): `Outpost` extends station.gd, kind "outpost": laid out like a derelict (`mods`, `grid`, doorways,
  hatches, `ways`; every room powered, so `_station_frame` / `_station_move` give it gravity and you walk it), but
  `guarded` and never saved (`state()` is {}: grown again by seed, on a WorkerThreadPool task like stations, with its
  system `sys` passed through the sector plan from galaxy.gd). `make_outpost(seed, sys)`: `cols` 6-7 x `rows` 3; the
  HANGAR is mod 0, 2 x 2 grid cells (`cells` per mod; `_op_nb` handles it) at one end of the lowest deck
  (`hangar_side`), its outer wall open `MOUTH_H` (80) onto a landing apron; the lowest deck's other rooms (`meta["deck"]`,
  from the hangar outward, one run of forced doorways: no hatch to climb) are the shops: MARKET first (role "outpost",
  towns.gd's old trading-post shop with the goods), then shipwright, cantina, charts in the seed's order; a reactor up
  top farthest from the hangar, an observatory, then quarters/hydro/stores/promenade/hall. `_dress` (the station's,
  powered) then `_dress_op` (bay, awning and goods, hull frame and plate racks, bar shelves and the job board, a star
  map and orrery, windows); `_outside_op` (roof windows, masts, comms dishes, trusses, solar wings, beacons at the
  mouth). `keepers` (`Trader`: role = towns.gd shop role via `KEEP_ROLE`, shop = room role, `b` feet in cells, a
  `counter_texture` drawn on `_mid` in front of them, `facing` toward the hangar), `keeper(shop)`, `trader()` (the
  market's), `in_hangar`, `hangar_rect`, `walk_links` (same-deck doorways), `role_name` (`OP_ROOMS`), `SHOP_COL`.
  Defs.SHOPS "outpost" (market: plating, ingots, star iron, a draught; buys salvage), "shipwright" (mending at the
  dock, plating, Wisp Cells, wisp ore, glass, the Shield Emitter and Cannon Coil), "cantina" (stew, a draught; the job
  board), "cartographer" (star charts 2 / 5, the Scanner Lens). SPACERS (spacer.gd, space.gd `folk`, made by
  `_outpost_in`, dropped with their outpost): walk their deck under its pull (`move_box`), wait, cross doorways to
  same-deck rooms, step apart when two stand on one spot; F beside one (`near_folk`, `_folk_talk`): a line from
  `_folk_lines` (the system's derelict, a trade tip from the next system, fuel, pirates, the job board). space.gd:
  `_trader_near` sets `near_trader` (the outpost) and `near_keeper` (within `TRADE_REACH` of a keeper's chest);
  `open_trade(op, kp)` settles jobs, pays the pirate BOUNTY (35 a ship since `items["bounty_paid"]`), opens that
  keeper's shop. No spells in an outpost's halls (a toast). JOBS (the cantina's board; `job_offers(seed, name, sys)`:
  three from the seed and `items["jobs_done"]`; taken for nothing through the shop (towns.gd "job" sale items, ui.gd
  "Take", "+pay"), at most `JOB_MAX` 3 in `items["jobs"]`; `_settle_jobs(op)` pays at the outpost where one ends):
  courier (sealed crates, cargo "sealed", to another system's outpost), salvage (matter brought back), hunt (pirates
  beaten since taking it, then back); `job_short` lists them on the HUD. HUD in an outpost: its name and the room.
  Overlay draws a docked skiff's hold crates. Galaxy: every system r has one, `Galaxy.system_outpost(r)` (`OUTPOST_D`
  27000 +- 2000 from its first planet, clear of every planet by NEAR_PLANET + 6000 and 12000 from the first wreck).
  Pirates never come out of the dark within `OUTPOST_SAFE` of one and are driven off within `OUTPOST_GUNS`. Markers:
  this system's outpost (gold); the map draws a little station at every charted system's outpost. Test:
  `_test_outposts` ("outposts"; pictures `outpost_layout_0/1.png`, `outpost.png`, `outpost_hangar.png`,
  `outpost_trader.png`, `outpost_shop.png`, `outpost_jobs.png`, `outpost_folk.png`, `outpost_map.png`).
- Figures among a station's or outpost's rooms (aliens' bodies, keepers and their counters, spacers) are drawn on
  space.gd `_mid` (a child kept last among space's children, z 0: over the rock sprites, under the overlay's mage);
  health bars, prompts, signs and speech on `_top` (z 1).
- DERELICT STATIONS AND ALIENS (scripts/station.gd, alien.gd; user, 23 Nov: "much bigger more complex outposts ...
  Derelict space stations and everything with aliens and such to fight"; inside, chosen "Both, by section"):
  `Station` extends wreck.gd, kind "station"; `make_station(seed)` lays out a grid (`cols` 4-6 x `rows` 2-3, a corner
  or two left out) of MODULES (`mods`: x0..x1, y0..y1 inside = `MW` 80 x `MH` 44, walls `T` 4, margins `OX`/`OY`),
  joined by a random spanning tree plus loops: side by side a DOORWAY at floor level (`DOOR_H` 26), one over another
  a HATCH (`HATCH_W` 22: its top row a one-way SCAFFOLD floor, and a scaffold LEDGE 22 down the room below to climb
  by). Roles: dock (the lowest outer room; an open mouth 30 high and a docking arm, `dock_side`), reactor (a wisp
  core about halfway in), the VAULT (farthest from the dock; every link but one cut) behind the NEST (its link
  sealed with runestone: `seal_cells`, `open_seal`), the rest hydro/quarters/lab/stores/hall. POWERED rooms (the
  ones nearest the reactor, 40-60%, the vault too, never the nest): gravity runes (RUNESTONE + WISP) in the floor,
  lit lamps, clean panels; BROKEN rooms: dark ribbed back wall, scorching, a fallen girder, a breach in an outer
  wall. Props, girders, troughs, lamps and crates keep clear of `ways` (doorways, hatches with their ledges, the
  mouth; `_near_way`): a lamp under a sealed hatch once choked the vault's way in. `spawns` (aliens), caches
  (wreck.gd's crates: stores/quarters/lab/nest/vault). Queries in station cells: `module_at`, `inside` (a room or
  way: bg set), `powered_at`, `box_free` / `platform_under` (with `EPS` give: world positions are single floats, about
  0.005 of a cell out here), `move_box` (a box a cell at a time: across with a step up, then along +y landing on solid
  or, falling, on a scaffold's top). Its pictures are painted through a colour table (`_paint`), and what changes is
  repainted cell by cell (`_repaint`): it's ten times a wreck. Never saved as a rock: grown again by seed;
  `state()` / `apply_state` (open caches, seal) plus the dead aliens' ids live in space.gd `station_state` (saved in
  progress.json "space" "stations"). Galaxy: every system's `system_station(r)` (`STATION_D` 38000 from its first
  planet, clear of planets, its outpost and the first wreck), `station_seed`/`station_name`, and `STATION` 0.012 a
  deep sector (`_station`). space.gd grows one on a WorkerThreadPool task as its sector streams in (`_st_jobs`), then
  `_place_rock` (aligned like an outpost) and `_station_in` (state, aliens).
  GRAVITY BY SECTION: `_station_frame` (each tick after `_find_near`): within a station's bounds (`frame_st`) its floor
  is "down" (`centre` = its pos + axis_y x `STATION_DOWN`, so the view, your upright pose and the skiff level with
  it); inside its rooms on foot (`in_station`, a toast on boarding and per room) `_station_move` runs in its cells
  (kept between ticks in `_st_b`/`_st_w`, so float rounding far out never drifts you): a powered room pulls you
  (`Alien.G` 0.17), you walk, jump, step up, land on and (down + jump) drop through scaffold; a broken room has no
  gravity and the movement keys push you by the jet (`ST_JET`, `ST_JET_MANA`, `ST_DRAG`); the cast button CASTS
  (`_space_cast`: the spell's projectile as `sbolts`, the same SPELL_FX looks, bent by a powered room's pull; mending
  heals, Blink steps through the rooms (`_st_blink`), Conjure fizzles). `_update_sbolts` / `_sbolt_impact` /
  `_alien_blast` / `_hurt_alien` / `_kill_alien` (Xenite into the satchel; the Broodmother's death breaks the seal).
  Overlay `_feet` in space: up is away from `space.centre` and nothing stands on the planet's ground.
  ALIENS (alien.gd, `Alien.make(kind, station, b, id, room)`; `KINDS`): live in their station's cells (`b`, `v`, +y
  down), ticked by space.gd `_update_aliens` within `ALIEN_NEAR` of their station; asleep until you're within 110 or in
  their room (`alien_wake` wakes the room, "hiss"); without you inside they go home. skitter (walks, hops when stuck,
  winds up and leaps; in a dead room kicks after you), drifter (floats at 80, `alien_spit` acid when `alien_sees` you),
  brute (powered rooms: plods, rears up 36 ticks (its tell), charges; flounders without gravity), brood (the
  Broodmother: hovers over you in the nest, volleys of 3 (5 enraged), `alien_lay` skitters, at most 4). Touching you
  bites (`spec()["dmg"]`, knock in the station's frame). `acid` ([pos, vel, ticks, dmg]: `_update_acid`). Art grown
  in code (`frames`: skitter 4, drifter 4, brute 4, brood 3; outlined; violet chitin, green glow), drawn by
  `_draw_aliens` on `_top` (walkers by their feet; a hull bar when hurt; "The Broodmother" over hers). XENITE (material
  61, NM 62): their glowing chitin; outposts buy it. The vault's cache: coins, star iron, wisp ingots, Xenite, a
  chart, a recipe, a draught and a Scanner Lens (`items["part_scanner"]`) -> the WISP SCANNER (recipe "scanner",
  Travel: `_scan` sees 3x as far and charts 1.6x as far; `_scanner_marks` marks the nearest wreck and station in the 7
  x 7 sectors round you). HUD: "Derelict <name>" and the room with "gravity"/"no gravity". Map: stations in explored
  sectors and at every charted system. Sounds "hiss", "chitter", "spit". Test: `_test_stations` ("stations"; in the
  full run after `_test_cabin`): 10 grown (every room reached by drifting, the vault only once unsealed:
  `_station_rooms_reached`), the system's station streamed in, drifted in through the dock, a powered room (fall,
  walk, jump, a ledge stood on and dropped through), a dead room (hangs, the jet pushes), a skitter's bite, sparks kill
  it, a drifter spits, the Broodmother lays and falls, the seal breaks, the vault's Scanner Lens, kept after streaming
  out and in; pictures `station_layout_0..2.png` (whole layouts, aliens marked), `station_outside/dock/powered/
  dead_room/fight/drifter/brood/vault/map.png`.
- ROOMIER STATIONS, A REAL DOCK, BACK TO THE SKIFF (user, 23 Nov: "docking to the derelict space stations needs work,
  and also they didnt have very much room for the player or enemies to move around"; "losing the skiff in space was a
  little hard maybe someway to teleport to the skiff"): station.gd rooms `MW` 112 x `MH` 64 (80 x 44 before; outposts
  extend it, so theirs grew too: about 900 x 280), `DOOR_H` 34, `HATCH_W` 28, two staggered scaffold ledges under a
  hatch (`LEDGES` 22 and 44 under the roof). The dock is always powered, its mouth `MOUTH` 56 high with an apron and a
  lip, and no hatch drops into it (its link above becomes a doorway to the room beside it unless that would cut the
  station in two): the skiff flies in. space.gd `docked_st` (`_dock_check`: the skiff in a station's dock room, a
  toast), `bay_spots(m, sk)` (stepping off there puts you on the bay's floor, main `_skiff_interact`). K in space:
  main `recall_skiff()` (`RECALL_MANA` 12, `vfx.blink`, aboard at once; space `recalled()`); the "Your skiff [K]"
  marker. Checked in `_test_stations` (flown in, docked, stepped out aboard; carried back aboard from the vault).
- SPACE'S OWN LIFE AND ANOMALIES (scripts/voidlife.gd, monolith.gd; user, 23 Nov: "space creatures and anomalies",
  each with a secret): space.gd `vl` (VoidLife, a RefCounted) holds them in space's coordinates (`vl.shift` from
  `_shift`), streamed with their sectors (`_load_sector` -> `vl.sector_in` BEFORE the sect_state early return,
  `_unload_sector` -> `sector_out`), ticked by `vl.tick` (space `_pmark` "void life"), drawn by `draw_under`
  (wells, rifts: on space under the rock sprites), `draw_mid` (creatures, essence motes, glyph light: `_mid`),
  `draw_top` (bars), `draw_markers`. galaxy.gd `_void_content` (its own RNG, seed 78, so nothing older moved):
  in an empty deep sector (`DEEP` 50000 from planets) a gravity well (`WELL`) or an ancient monolith (`MONOLITH`,
  a rock of kind "monolith"); a manta herd where the nebula is thick; eels with a deep field; jellies with a
  comet (they ride its loop: `_home` from `comet_at`); rift ends (`rift_pair(r)`: 60% of systems, end "a" RIFT_D
  from its first planet, its twin "b" by system r + 4..11; `rifts_near`; ends 46000+ from any planet so no
  journey begins there). A content entry may have no "rocks" (space uses `c.get("rocks", [])`).
  CREATURES (`Beast`, `groups`; art grown in code: `_manta_img` 6 flap frames from above, `_eel_head`/`_eel_seg`
  along `trail` (`_segments`), `_jelly_img` 4 pulse frames + pixel tentacles): mantas glide after a leader in a
  V, shed a mote now and then, a hurt one scatters the herd (`scared`); eels patrol, hunt the skiff (or you on
  foot), bite (`_bites`: `skiff_hit` at `_first_cell`, the shield takes it), recoil, flee after 3 bites or half
  hp; jellies pulse round their comet and sting on touch. `hostile_ok()`: never in the test mode unless
  `allow_hostile`. The cannon (`shot_hit` in `_update_shots`) and your staff on foot (`sear`, from `_mine_at`,
  mana a tick) hurt them; killed (`_kill`) they drop Void Essence motes (`motes`, drawn to you within
  `MOTE_REACH`). VOIDESS (material 63, NM 64). Outposts buy it.
  WELLS: `well_force(p, v, who)` from the skiff's tick and the mage's (pull WELL_G/d^2, at most WELL_MAX; the
  heart CORE_R spits you out hurt; at the nearest point of a fast pass (`in`/`min` per who) a slingshot x1.35
  (harness x1.8), `sling_t` slows the Starsail's shedding and the mage's speed cap; the Void Harness
  (`items["harness"]`) zeroes the pull toward EDGE_R and pushes out inside it, no spit), 6 orbiting essence
  crystals (`_update_crystals`, back after 4000 ticks), `clearance` for the Starsail.
  RIFTS: within RIFT_IN of an end, `_through`: space `carry(d)` moves you, the skiff and what follows you (not
  the world; bolts and pirates are left), then `_shift` recentres; `known` (pair -> [end a, end b]) for markers
  and the map's dashed line. MONOLITHS (monolith.gd extends wreck.gd; never saved as a rock, `mono_state` by
  seed): 5 glyphs that wake only root first (`next_glyph`; out of turn "early" fizzles), each burns `FADE` ticks;
  the cannon (`strike_at` looks 18 cells on along the bolt) or the staff on foot; the last opens the seal (an
  OBSIDIAN alcove), its cache (`_loot` "monolith" -> `vl.mono_loot`: essence, star iron, coins, a scroll, and
  `reveal_rift`). Recipes: "harness" (Travel) and the GEAR "voidmantle" (stat "space_mana", read in `vl.tick`),
  both learned on finding Void Essence. HUD: "Lumen eels!", "Gravity well". Test: `_test_voidlife`
  ("voidlife"; in the full run after `_test_cargo`; pictures `void_mantas/eels/jellies/well/monolith/
  monolith_open/rift/map.png`).
