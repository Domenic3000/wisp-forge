# Wisp Forge: Bosses: guardians, summoning, heart bosses, wardens, Vulkhar, pursuit

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Summoning and guardians
- SUMMONING, NOT LAIRS (user, 22 Nov: "The gaurdian seemed to be stuck in the ground when i found him. maybe we
  move away from gaurdian lairs and go to a summoning them mechanic?"; chosen: "At an altar you build", "An
  offering you forge"): buildings.gd `LAIRS := false` (the lair code stays; GEN_VERSION not bumped, so lairs
  already stamped in a world stay as ruins, with no guardian). A guardian is called (scripts/summoning.gd, main
  `summoning`): build a Summoning Altar (`Defs.STATIONS["altar"]`, 22 x 15, Workshops tab; workshop_art.gd
  `_altar`, runes always glowing, no fuel) in a biome of this planet's "guardians", forge that biome's sigil at the
  Wisp Forge (`Defs.sigil_recipes()`, category "Summoning", `SIGIL_MATS[biome]` + `SIGIL_COMMON`; shown only for
  `callable_biomes()`; `items["sigil_<biome>"]`, shown in the satchel, `Icons.thing("sigil_<b>")` in the boss's
  colour), then F at the altar (`try_summon(m, st)`: returns why not, or "" and uses the sigil). A ritual of
  `RITUAL` frames (rune circles, motes, shaking), then `_arrive`: the guardian appears at a spot `find_spot` picked
  BEFORE the sigil was taken (open room the size of its body on the far side of the altar from you; fliers above,
  swimmers in water within 260, burrowers over diggable ground), awake, its home there, `tether` `ARENA` (+ main's
  `LEASH`), and `Enemy.summoned` set. Wander off and it leaves (`dismiss`, the sigil given back); one called but
  not beaten when you save is given back on load (`on_save`/`on_load`, `planet_state["summoned"]`). Beaten:
  `_guardian_falls` as before (relic, loot, `bosses_dead`). Villagers' "lair" rumour now names a guardian and
  where its altar must stand; a tavern's chart marks dungeons. Test: `_test_guardians` (each callable biome: an
  altar on clear ground in it, or the seabed; the sigil; it comes, `box_solid` says not in the ground, it fights,
  falls, gives its relic; `guard_info` for `_test_far_biomes`'s check that Thalassor comes in the water).
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
  every second or two) by the nav graph (`_nav_around`; see docs/creatures.md, Pathfinding), hop what's under `CLIMB` (`_clear_way` only turns
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

- The new biomes' guardians (26 Nov): Basalthor (basalt, relic basaltheart), Marelle the Kelp Wyrm (kelp, swims,
  relic kelpcrown), Brinemaw (saltflats, saltglass), The Rootmother (mangrove, mangroveseed), Prismara
  (crystalfields, prismheart), Old Mossjaw (elder, mossjaw), Queen Bombyla (meadow, honeycomb). Each has its
  `SIGIL_MATS` entry. A guardian relic's max_hp / max_mana / mana_regen mods are granted once when it falls
  (`_guardian_falls`), the rest through `gear()`.

## Heart bosses (user, 26 Nov: "i would like different bosses at the heart of different kinds of worlds"; chose every kind its own with Vulkhar staying on temperate worlds, a storm boss at the gas giant's Eye, and each giving its own relic)
- `Defs.HEARTS` (kind -> a guardian-style definition: body plan and features, stats, `go`, moves/rage, "biome" (whose
  fighters `_call_type` calls), "relic", "loot", "wet"/"swim" for the deep ocean world's): Pyrrhax the Molten Wyrm
  (volcanic, serpent), Kharybdos the Deep Maw (ocean, toad), Ankhet the Sun Sphinx (desert, beast), Gulgoth the Mire
  Wyrm (marsh, serpent), Hiemora the Glacier Queen (frozen, bird), Gorrath the Elder Beast (wild, beast), Aurelis the
  Gryphon King (realm, bird), Nhal'Zuur the Abyssal Eye (the deep ocean world, a swimming serpent in a flooded
  chamber), Tempestra the Storm Roc (the gas giant, bird), and (26 Nov) Solarion the Sun Phoenix (a dying star,
  bird, over the Solar Sanctum) and Nul'Ghora the Devourer (a black hole's Hollow, serpent, over the Singularity Gate). `Defs.heart_type(kind)`: "heart_<kind>", or "golem"
  (Vulkhar) for temperate and any kind without one. `heart_enemy` (via `enemy_def`, prefix "heart_"): "boss",
  "heart", "hall" (it wakes only with you inside its chamber: boss_ai's wake test, as a warden's `_in_hall`), "key".
- main `_spawn_heart_boss` (where Vulkhar was spawned, unless `planet_state["boss_dead"]`): on the chamber's floor,
  `tether` = the chamber's half width - 12, `ceil` its height - 8, `home` where it stands. The gas giant's (its heart
  can't be reached), the dying star's and the black hole's: over their mystery's hall (the Eye of the Storm, the
  Solar Sanctum, the Singularity Gate: `builds.mystery["hall"]` + 110 up), `arena` 260, tether 420, ceil 260,
  and no "hall" (it wakes as you come near). Beaten: `_heart_falls` (main's `_kill_enemy` routes "heart" there):
  `boss_dead`, its relic (max health / mana / regen given once, `_apply_gear`), its loot, 24 of the world's ore, a
  recipe, 120 coins, `_roll_loot(6, 2.0)`. Guardians' moves, chase (pursuit), wall-breaking and calls all apply.
- Relics with "mods" (`Defs.RELICS`: moltenheart, deeppearl, sunankh, mireeye, frostplume, elderheart, gryphoncrown,
  abyssallure, stormheart): gear's stats, summed in main `gear` (max_hp, max_mana and mana_regen excepted: given
  once when won).
- The chamber's lining by kind (`Defs.HEART_CHAMBER` -> gpu `chamber_theme` -> gen.comp P.p[121].z): obsidian and
  embers (temperate, volcanic, as before), deep stone and crystal (ocean), sandstone (desert), moss and glowcaps
  (marsh), ice and frost (frozen), moss and amber (wild), masonry and runestone (realm), and flooded (the deep ocean
  world). Only worlds generated from now on; GEN_VERSION not bumped, so worlds already made keep obsidian.
- A charge that reaches its bounds (`tether`) brakes there (`vx` 0.4 of its way) before it recovers: it used to
  slide ~30 cells on past the edge (guardians too).
- The quest: a later world's core step names its heart boss. Test: `_test_hearts` ("hearts"; after
  `_test_guardians`): the mapping, each one's frames, and each that fights on land set down on clear ground near
  the start in a chamber's bounds (asleep with you outside, wakes with you in, moves, in bounds, clear of the ground,
  falls, relic), and a relic's mods in `gear`; pictures `heart_<kind>.png`.

## Wardens
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

## Out of reach: Vulkhar, pursuit, hunting you down
- Vulkhar out of reach (user, 23 Nov: cheesed "through a hole in the ground"): main `_golem_reach` looks for a way
  to you (`FoeAI.can_reach`) every 30 frames; kept from you `GOLEM_SURGE_AFTER` he surges every
  `GOLEM_SURGE_EVERY` (a tight stream of efire straight at you, two imps called up, at most 4), and past
  `GOLEM_MEND_AFTER` he mends 9 health a second.
- A BOSS COMES TO YOU (scripts/pursuit.gd; user, 24 Nov: shot Vulkhar through a hole and stepped back, again and
  again; chose "it comes to you"): main `_hurt_enemy` -> `Pursuit.struck` on any boss; on its next tick (`Pursuit.tick`,
  from boss_ai `tick` for walkers, hoppers, fliers and serpents (not burrowers or swimmers), and from the "golem" branch)
  the hit is weighed by its OWN nav graph (`reach_now`: its size, its jump; `Pursuit.walk_key`/`fly_key`, asked every
  tick): no way to you = a `grudge` that stepping back or out of sight doesn't wipe (only `FORGET` frames without
  another). `GRUDGE_AT` (2) and it comes: `TELL` frames (a rune circle and embers where it will stand, it flickers, the
  ground shakes, a toast), then it is set down there (`_coming`). Where: `Nav.meet_spots` (a standing node of its class
  from RMIN to `RMAX` of you with a way to your nearest node; fliers `Nav.fly_spots`), kept to `_allowed` (a guardian's
  tether, a warden's hall); with none (you in a tunnel narrower than it), `_pocket` beside you (only where every solid
  cell is HARD <= its power: 2, Vulkhar 3; never runestone), cut at `CARVE_AT` by an AIR STAMP (`_carve`; a blast
  loosened the rock round it, which fell in and filled it), its corners kept as WORLD points (the grid moves as you
  step back: kept in grid cells it was cut 30 cells off). `COOLDOWN` before it may come again. Vulkhar's surge
  (`_golem_reach`) now works too: `FoeAI.can_reach` says yes with no graph, and nothing asked for his class's graph
  until Pursuit did. Test: `_test_pursuit` ("pursuit"; in the full run after `_test_nav`; pictures
  `pursuit_tell.png`, `pursuit_came.png`).
- BOSSES HUNT YOU DOWN (user, 24 Nov: "make them break walls chase and summon enemies aggresively"):
  CHASE: `Pursuit` also comes when it has had no way to you for `KEPT_AT` (300) frames with you within `KEPT_R`,
  struck or not (`Enemy.kept_t`, looked at twice a second); a summoned guardian's leash is 520 (summoning
  `LEASH`, 230 before); a boss gives up only past main `GIVE_UP_D` (520) for `GIVE_UP_T` (420) frames (300 / 200
  before). BREAK WALLS: boss_ai `tick`: any WALKING guardian (not wardens), kept from you `BREACH_AFTER` (75)
  frames within `BREACH_R` (200) on its level, charges through (its own charge, else a plain "charge"), up to
  `BREACH_HOLES` (4) holes, then `BREACH_CD` (240); Vulkhar held at a wall with no way to you blasts it (power 3,
  every 28 frames). SUMMON: a guardian with no summoning of its own gets `CALL` ("summon9") among its moves:
  its biome's fighters (`_call_type`: predators, then territorial, then any not prey; swimmers only for a swimmer;
  never burrowers; cached in `static var _calls`): 2, at most 3; every summon calls one more and keeps two more
  about it when enraged; what's called comes awake, provoked and after you. Vulkhar calls imps every
  `GOLEM_CALL_EVERY` (600, 420 enraged) while you're within 260 (`_golem_imps`), not only when kept off. Coming
  to you, a boss's next move is its summoning (`Enemy.call_next`, boss_ai `_begin`; Vulkhar calls imps as he
  lands). Checked in `_test_pursuit` (hidden and unstruck it gets to you; the Mycelord, with no charge, smashes
  into a brick hut; Bramblehorn calls boars, roused; Vulkhar calls imps in reach). Since bosses break in, a test
  that expects one to "come" accepts it getting to you either way.
