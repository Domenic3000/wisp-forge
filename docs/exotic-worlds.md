# Wisp Forge: Exotic worlds: the deep ocean world, the gas giant, the dying star and the black hole

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Exotic worlds: the deep ocean world first (user, 23 Nov: "are there super deep ocean worlds? also different types of planets would be nice with different mysteries to solve, along with different hazards to traverse to get to" them; chose: the deep ocean first, clues and puzzles, optional with big rewards; gas giants, stars and black holes later)
- Indices: `Defs.EXOTIC` (100000) + system x `EXO_SLOTS` (8) + k; `is_exotic`, `system_of(i)` (never `i / 5` for a
  planet index any more), `exotics_of(r)` (system 0 always one, others half the time), `planets_of(r)` (the round
  of five plus its exotics: space `_make_bodies`, galaxy `_near_planet`, the map), `exotic_kind(i)`,
  `_exotic_local` (92-118k from the first planet on the bearing farthest from the others), `_exotic_planet`
  (kind "abyss", "exotic": "abyss", a name + " Deep", biomes mostly "abyss" with two "ocean" shelves and two narrow
  islands (jungle, forest: where you come down), sea 8-12, "guardians" ["ocean"]). Reached through its barrier like
  any planet (abyss: the maelstrom, `items["keel"]`; giant: a storm belt, the lattice); quest chapters ignore
  exotic indices.
- THE MAELSTROM: an unreachable exotic's storm belt (`body["exotic"]`): `_storm` spins you round it (0.25 + 1.1 f a
  tick along it, more than it throws you out) and swirls the gale; `_draw_belts` adds wheeling spiral arms; markers
  say "maelstrom" (`barrier_name`). The TEMPEST KEEL (recipe "keel", Travel: 12 Abyss Pearl, 6 Star Iron, 10 Hull
  Plating; learned on finding pearls, hidden until the skiff) lets you through.
- The ABYSS biome (`BIOMES["abyss"]`: off 430, amp 26, gravel over sand, flora 10, ug 1): its floor 400-480 under
  the sea. gen.comp flora 10: kelp where the sea is under 170 deep, below that glowing coral fans (CRYSTAL), tube
  worms (STALK, lit SHROOM tips) and glowcaps. light.comp: under a sea the daylight fades as exp(-depth / 110) and
  turns blue-green (`uw`); render.comp draws open water over the sky LIT and opaque (`col = mc * 0.82; flag 0`), so
  every sea darkens with depth and at night. Hazards: "deep" (Tide Charm) and "crush" (`HAZARDS["crush"]`, 160+
  under the sea, ward "depthseal": the DEPTH SEAL, Wards, abyss pearls), climate `CLIMATES["abyss"]`; KIND_ORES and
  KIND_TRADE "abyss" (island shops sell both wards). Creatures "lanterneel", "abyssjelly", "gulper" ("glow": main gives
  up to 6 near you a light). buildings `_try_place` puts nothing on the abyss floor; no dungeons on an exotic world.
- THE MYSTERY (buildings `_abyss_mystery`, its own RNG; scripts/mystery.gd, main `mystery`): five of six glyphs
  (`Mystery.GLYPHS`, 7 x 7 `GLYPH_ART`) in an order; five TIDE-STONES (`_tide_stone`: a slab carved with its glyph in
  CRYSTAL and place + 1 WISP dots; islands first, then shelves, 140+ apart); the TEMPLE OF THE DROWNED CHOIR
  (`_sunken_temple`, `TEMPLE_W` 250, on the deepest level stretch): a masonry plinth, a RUNESTONE hall 62 high written
  as AIR (dry: water never rises in the simulation) entered by a MOON POOL (a scaffold over a gap in the floor) from a
  WATER-filled tunnel out of the plinth's side, five resonance pillars (background; glyph shuffled), a ward of
  RUNESTONE before the vault's altar, crystal lamps, a pediment roof, a chest. `mystery` dict: order, stones [{pos,
  glyph, place}], pillars [{pos (where you stand), glyph}], ward {x0, y0, w, h, ax, aw}, vault, hall, pool, mouth.
  mystery.gd: `tick` (what's in reach), F `interact` -> `read` (the note into `st["known"]`, a wisp line), `ring` (the
  right note lights it; a wrong one silences them all: `rung` cleared, a red flash), `_solve` (an air stamp over the
  ward, like a warden's), `claim` (the TIDE HEART `items["tideheart"]`: no breath lost under water, bears "deep" and
  "crush", swim x1.5; 30 pearls, 8 star iron, 220 coins, 2 draughts). Saved in `planet_state["mystery"]`; a summary
  in `items["myst"][index]`. Overlay `_draw_mystery` (glyphs over the pillars: dim, lit, red) and the "[F] ..."
  prompt bubble. quest.gd `mystery_world`, `mystery_steps` (keel, fly there, read the stones n/5, sing the song,
  claim), `mystery_notes`, `_mystery_tick` (the wisp speaks on first coming near a maelstrom and on landing); the HUD
  line on an exotic world is its next mystery step; the journal (L) has "A mystery" with the song so far.
- Test: `_test_abyss` ("abyss"; in the full run after `_test_far_biomes`): placement, the maelstrom's spin and the
  keel, the sea 380+ deep, the light at depth, the crushing deep and the Depth Seal, every stone read, the hall dry
  and the pool flooded, a wrong note then the song, the ward's cells gone, the Tide Heart; pictures `abyss_deep.png`,
  `abyss_stone.png`, `abyss_temple.png`, `abyss_vault.png`, `abyss_journal.png`.

## The gas giant (user, 24 Nov: "maybe some gas giants with no ground or only clouds"; built while he was away)
- The second exotic kind, slot 1: `Defs.exotics_of(r)` is [EXOTIC, EXOTIC + 1] for system 0, and for the others the
  deep ocean world half the time (its draw unchanged) plus a giant two times in five (its own draw, seed 49);
  `EXO_KINDS` by slot (`exotic_kind`). `_exotic_local` keeps a later exotic clear of the ones before it (the first
  is placed as it always was). `_giant_planet`: kind/exotic "giant", one biome "giant" all round (`off` 560: its
  ground lies hundreds of cells under the mean surface, out of reach), sea -1, no guardians, name + "Thunder",
  "Gale", ... (`GIANT_NAMES`), sky tint amber. CLIMATES "giant": storm 2.2, wind 1.0, "pressure", settle 0.
- THE THUNDERHEAD: its storm belt (space.gd `_storm`, `thunder`) strikes four times as often; `_draw_belts`
  flickers forks of lightning through it; `barrier_name` "thunderhead". The STORM LATTICE (recipe "lattice",
  Travel: 12 Copper Ingots, 6 Star Iron, 8 Glass; learned on finding star iron, hidden until the skiff) grounds it,
  and every storm belt (the giant's barrier is "storm", BARRIERS). Its disc is banded amber and rust with a storm's eye (`_disc_image`).
- THE CLOUD DECK: main sets P.p[125].x to -1 on a giant (it's a frozen world's icing chance otherwise);
  clouds.comp `cloudDeck` (from about 40 under the mean surface down, a billowing top drifting with the wind) is
  part of `cloudDensity`; render.comp bands it amber and rust and makes it opaque deep in (nothing under it shows),
  and draws no mountains or hills behind a giant. Under it main `_hazard_level` "pressure" (`HAZARDS`: ward Depth
  Seal, relic Storm Crown): from `PRESSURE_D` (110) under the mean surface, 1 + (depth - 110) / 60.
- ISLES (buildings.gd `_giant_sky`, its own RNG; `_sky_island(cx, h, w, build, trees, flat)`: grass, earth, stone
  with copper/wisp/coal, a lumpy underside with crystal drips, living trees by `Lairs.tree`; written through
  `Lairs.Lay.n` (natural rock, anchored: they float and stay until dug)): the landing isle at the spawn column
  (`builds.landing`: main `_respawn` puts you there), the Eye's isle on the far side (205 up), five beacon isles round
  it (two each side, one under it), and isles all round the rest (150-270 apart). Creatures: skyray (neutral, big,
  a little glow), stormkite (predator); both fliers. `_try_place` puts nothing on a giant.
- THE MYSTERY (mystery.gd kind "beacons"; buildings `_beacon`, `_eye_hall`): five BEACONS (a masonry pillar with a
  copper basin, k + 1 crystal marks; `mystery["beacons"]` [{pos (the basin), stand}]); THE EYE OF THE STORM
  (`EYE_W` 150, a hall `EYE_HALL` 56 high under a tiled dome, its door under a round window, five braziers along
  the floor (`echoes`), an inscription by the door (`plaque`), the vault behind a 4-thick RUNESTONE ward (`ward`),
  an altar (`vault`) and a chest). Beacons and the hall are `_pin`ned (every cell anchored before `_finish`): with no
  ground under them in their own blueprint the soundness pass cut them all away (the test now reads the ward's runestone back). F at a beacon lights it (`light`: `LIGHT_MANA` 15) and it burns `BURN` (4500
  ticks; `burn`: index -> frame, not saved); `_tick_beacons` gives light and embers, its brazier answers, and puts
  it out in time; all five at once -> `_solve` (the ward's air stamp). The vault: the STORM CROWN
  (`items["stormcrown"]`: main skips the wind's push and lightning's hurt, levitation costs no mana, it bears
  "pressure") and `CROWN_LOOT`. Overlay `_flame` draws a burning beacon and brazier. quest.gd: `mystery_world`
  (this world, or the first of the system's exotics not yet claimed), `mystery_steps`/`mystery_notes` by kind,
  `_mystery_tick` (the wisp on landing, and near the Thunderhead: `myst_heard_giant`).
- Test: `_test_giant` ("giant"; in the full run after `_test_abyss`): where it lies, the Thunderhead's strikes and
  the lattice, standing on the landing isle with no ground in reach, the crushing air and the Depth Seal, the
  inscription, four beacons lit and one let burn out, all five as one and the ward's cells gone, the Storm
  Crown; pictures `giant_landing/beacon/eye/vault/journal.png`.

## The dying star (26 Nov; the roadmap's "stars (a heat shield to land)", built while the user was away)
- Slot 2: `Defs.exotics_of(0)` is all four exotics; later systems have a star one time in three (its own draw, seed
  59). `_star_planet`: kind/exotic "star", eight biomes alternating "slag" (rafts of crust: MAGMAROCK over
  DEEPSTONE, flora 11 so basalt columns stand on them; flags 8 | 16) and "corona" (the molten sea, its floor of
  obsidian 90 down; flags 16), the landing raft first, `planet["sanctum"]` (2) the widest raft. Sea 9-13. Name +
  "Pyre", "Ember"... (`STAR_NAMES`). No guardians.
- THE MOLTEN SEA: biome flags 16 (on either biome of a border) make surface.comp lay the sea as LAVA instead of
  water (`waterMat`), so the shores never turn to water. react.comp leaves lava alone unless water touches it.
- THE CORONA: its barrier (`BARRIERS["corona"]`, KIND_BARRIER "star"): space.gd `_storm` burns through the hull as a
  radiation belt does (`_irradiate`), `_draw_belts` adds loops of fire arching off it; the HEAT SHIELD (recipe
  "heatshield", Travel: 10 fire opal, 20 obsidian, 6 star iron, 12 hull plating; learned on finding fire opal,
  hidden until the skiff) passes it. Its disc (`_disc_image`) is white-gold fire with dark rafts, giving its own
  light.
- CLIMATES "star": heat 1.5 (the Heat Ward, as on volcanic worlds), "flare" 1.0. FLARES: the sky event "flare"
  (`SKY_EVENTS`, the only one a star has; main rolls three times as often there): `_sky_flare` washes the sky
  white-gold and drops burning motes; HAZARDS "flare" (`_hazard_level`: `sky_level("flare")` under the open sky)
  sears you, borne by the SOLAR SHROUD (Wards: fire opal, sunstone, obsidian, crystal) or the Sun's Heart. No night:
  main pins the clock to midday where you stand (`_physics` tick, as the Hollow's to dusk).
- THE SUN RELAY (buildings.gd `_star_relay`, its own RNG; mystery.gd kind "lenses"): THE SOLAR SANCTUM (`_eye_hall`
  on a plinth, `eye`: a crystal eye on its dome) 450 columns one way from the sanctum raft's middle; the path planned
  BACKWARD from the eye: five SUN LENSES and the SUN WELL's lens (`_sun_lens`: an obsidian spire 6-130 high with a
  ledge and a crystal lens in a copper ring; `_sun_well`: the first lens beside a pit of lava), each exactly one of
  eight ways (`Defs.octant` / `octant_dir`, in the frame of the ground under the lens) from the one before it, 110-190
  apart, on slag, tried (120 times) until `_relay_clear`: no later lens or the eye nearer along any step's way.
  mystery: lenses [{pos, stand}] (0 the well), eye, need (the path's turns), facing (each lens's first turn, never
  right), planned, plaque, vault, hall, ward, echoes. Playing it: `st["face"]` (saved); F turns a lens an eighth
  (`turn`); `relay()` follows the light from the well: each lit lens throws it the way it faces to the nearest
  unlit lens (or the eye) that way within `RELAY_RANGE` (700); into the eye -> `_solve` (the ward's air stamp).
  Overlay `_draw_lenses`: the beams (bright, with motes running along; the last one fading where it reaches
  nothing) and each lens's way as a tick; the Sanctum's braziers light with the lenses. The prompt names the way
  a lens faces as it looks on screen (`WAYS`; Defs.octant's 0 is main's `basis_r`, screen right). The vault: the
  SUN'S HEART (`Defs.RELICS["sunheart"]`, mods: no lava or fire damage, Fireball 1.3, a light; it bears "flare",
  and main treats it as the Cinderheart for the heat and the mantle) and `SUN_LOOT`.
- Heart boss: SOLARION the Sun Phoenix (`HEARTS["star"]`, a bird, calls flare wisps; relic "flareheart") flies over
  the Sanctum (main `_spawn_heart_boss`, as the gas giant's over its Eye). Creatures: flare wisp (slag/corona, a
  flier with a glow), slag crawler (territorial), the basalt monitor (slag too).
- Quest: `mystery_steps` (Heat Shield, fly there, find the Sanctum, the relay n/5, claim), `mystery_notes`, the
  wisp near the corona (`myst_heard_star`) and on landing. Audio: the molten sea roars as the deep's lava.
- Test: `_test_star` ("star"; in the full run after `_test_giant`): where it lies, the corona (strikes counted by
  `space.belt_strikes`) and the shield, the sea molten in the plan and in the world, a flare (2 s: ~9 health; none
  with the Shroud), the inscription and the ward's runestone, the well turned by hand until it lights a lens, the
  rest set to `need`, the eye reached and the ward gone, the Sun's Heart (no loss in the lava), Solarion there;
  pictures `star_landing/flare/sanctum/relay/vault/journal.png`.

## The black hole and its Hollow (26 Nov, the roadmap's "black holes with a pocket dimension inside", built while the user was away)
- Slot 3: system 0 always; later systems one time in four (seed 61). `_void_planet`: kind/exotic "void", small
  (1150-1300 before PLANET_SCALE); its biomes are SHARDS of the worlds it swallowed (forest, desert, tundra,
  jungle, grove: their own ground, plants and creatures) with "rift" between them (off 560: the floor far down
  in the dark, like the gas giant's). Sky a dim violet; the clock pinned to dusk where you stand. No guardians,
  no structures (`_try_place` refuses a void world), no dungeons.
- THE HORIZON: its barrier (`BARRIERS["horizon"]`): `_storm` PULLS you in (the only barrier that does) and tears at
  you (`_tear`: hurts aboard or not), and at its inner edge spits you out battered; `_draw_belts` wheels the
  accretion disc's streaks; its disc is black, ringed with light. The VOID ANCHOR (Travel: 20 void essence, 8 xenite,
  10 star iron, 10 hull plating; learned on holding void essence) passes it.
- CLIMATES "void": no storm or wind, "void" 1.0: HAZARDS "void" (main `_hazard_level`: from `VOID_D` (120) under the
  mean surface, down a rift) unmakes you, borne by the Mantle of the Void ("voidmantle") or the Void Heart.
- THE ECHOES (buildings.gd `_void_shrines`, its own RNG; mystery.gd kind "echoes"): THE SINGULARITY GATE
  (`_eye_hall` on a plinth, 190 columns from where you land) and an ECHO SHRINE (`_echo_shrine`: an arch of obsidian
  and runestone over a floating crystal shard) in the middle of every shard of a world (on the one you land on, on
  the far side from the Gate). mystery: shrines [{pos, stand, biome}], plaque, vault, hall, ward, echoes. F at a
  shrine (`wake`) calls the shrine biome's guardian (`Defs.BOSSES`) as an ECHO: `summoning.find_spot` (or over the
  shrine), its definition copied with `d["echo"] = i`, `ECHO_HP` (0.7) of its health, awake, leashed like a called
  guardian; overlay washes it violet and flickering. Beaten, main `_kill_enemy` calls `echo_falls` (not
  `_guardian_falls`: no relic, no hoard): the shard is yours (`st["won"]`, saved), one of the Gate's braziers
  lights. Walk `ECHO_FADE` (700) from its shrine and it fades (wake it again); an echo isn't saved. With all five, F
  at the Gate's inscription sets them (`_solve`). The vault: the VOID HEART (`RELICS["voidheart"]`: +60 max mana,
  given once in `claim`, spells 0.85; it bears "void") and `VOID_LOOT`.
- Heart boss: NUL'GHORA the Devourer (`HEARTS["void"]`, a serpent, calls null stalkers; relic "nullheart") over the
  Gate. Creatures of the rifts: rift ray (a big glowing glider), null stalker (predator). Quest steps: the Anchor,
  fall in, find the Gate, the shards n/5, set them, claim; the wisp near the horizon (`myst_heard_void`). Audio: no
  wind in the Hollow, space's drone instead.
- Test: `_test_void` ("void"; after `_test_star`): where it lies, the horizon's pull and the Anchor, the Hollow made
  (rifts 400+ deep), the unmaking 200 down a rift, the inscription, an echo woken (70% health) that fades when you
  go 900 off, all five woken and beaten, the shards set and the ward gone, the Void Heart (+60 mana, no unmaking),
  Nul'Ghora there; pictures `void_landing/echo/gate/vault/journal.png`.
