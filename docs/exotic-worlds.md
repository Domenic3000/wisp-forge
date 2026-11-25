# Wisp Forge: Exotic worlds: the deep ocean world and the gas giant

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
