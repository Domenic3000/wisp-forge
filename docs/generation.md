# Wisp Forge: Generating the planet: structures and terrain

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Structures
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

## Terrain
- Foundations: two courses of the building's stone, then the biome's own ground layers (`_ground_mats`); yards are
  made of the biome's soil too. `_weather_ground_line` (run by `_finish`) blends masonry at the ground line outside
  buildings: course ends crumble into earth, topsoil drifts over exposed tops (never at doors), and a ruin's
  buried part is half swallowed by the ground.
- Packed ground: gen.comp `settleSafe` generates powder that couldn't rest (over caves, on steep faces, around
  building sites, to a wobbling depth) as its packed solid (sand -> SANDSTONE). render.comp draws SANDSTONE without
  ST_BUILT as natural wavy strata and only built sandstone as dressed blocks; conjured solids are marked built.
- Below-ground masonry (dungeon runestone too) gets ragged, stepped outer edges (`_roughen_underground`, run by
  `_finish`), so shafts and buried halls don't meet the earth with ruler-straight lines. The added cells are written
  outright (anchored, not F_FILL: a fill only lands in open space, so it never showed against solid earth), and only
  ever outward into the blueprint's untouched (255) cells, so halls and shafts stay as built.
- Biome borders: gen.comp picks one of the two neighbouring biomes per cell with noise at three scales (lobes,
  fingers, single grains), so their layers interfinger instead of meeting at a seam. Undergrowth (grass, bushes,
  tufts) picks per COLUMN the same way (`floraType` in main), trees by their own trunk's biome; overlapping
  mushroom caps: the shorter one wins the cells (in front), not the nearer trunk (that split them down a line, each
  its own colour). render.comp: a cave's back wall bands (`wallColor`) have ragged edges, and the far tree line
  (near parallax hills) takes each tree's kind from the biome at that tree (user, 21 Nov: sharp transitions).
- Back walls (and furniture, which is stamped as back wall) rest on settled powder below them (`support.comp`),
  the way front blocks do: a table set on sand or soil stays.
- Biomes: at most 8 per planet (their parameters fill P.p[8..23]). Flora types are numbered in defs.gd; each
  has a tree function in gen.comp (oak, pine, cactus, willow, charred, palm, jungle, acacia, mushroom, mangrove,
  elder) plus undergrowth in `flora()`; plant materials get their look in render.comp's `plantColor`.
- Roots (`ROOT`, background only): gen.comp `treeRoots` draws a taproot and a few side roots under each tree
  (`rootWidth` per flora type), into the ground below the surface and into the air where a slope drops away
  under the trunk, so no tree shows a flat underside. Roots score lowest in `flora` (every other part of any
  tree wins a cell), aren't tree-flagged in the collision grid (build over them freely), and dig up as Wood.
- Mud (`MUD`, a liquid): a biome's liquid ground layer (marsh top, jungle subsoil) is only liquid in bogs
  (gen.comp `bogDepth`: hollows the ground rises around, or under standing water, never on building sites or
  over caves); everywhere else it is generated as grass over dirt, so ground never hides a pool you sink into.
  render.comp draws mud dark and glossy with a wet top sheen and bubbles. react.comp: loose (unanchored) dirt
  touching water turns to mud; unanchored mud in the open with no water near dries back to dirt.

## Terrain 2 (user, 26 Nov: "the top layer of a planet is a bit too thin. i want to really feel the ambiance of each biome, and i think we should make the cave shapes more realistic ... more height variation to the planets and just more detailed surfaces in general with more natural land shapes going deeper and higher"; chose "Only on new journeys")
- Per save: `Defs.TERRAIN_SET` (2) is the set a new journey gets; `Defs.terrain` is the one in play, saved as "tset"
  (old saves have none and keep 1, so their unvisited planets generate as before). gpu_world `build_surface` sends
  it as P.p[26].x; gen.comp's `TV2` and surface.comp branch on it. Set 1 stays exactly as it was.
- Height (surface.comp): a broad swell (fbm /420), the hills (fbm /120, x3.8 of the biome's relief, more for
  mountain biomes), ridged crests (1-|2n-1| at /70, centred on its mean 0.77 so ridges don't sink the ground),
  knolls (/24) and fine roughness (/7). Meadows and plateaus (`flt`, fbm /260) fade the knolls and roughness and
  soften the hills between rougher stretches, so level ground to build on is about as common as in terrain 1
  (/home/claude/tools/level_measure.py: without them a 40-wide spot within 3 rows was a fifth as common, and the
  tests' `_clear_stretch` found none). A bog's pond level and a lava lake's (surface.comp `swell`) rise and fall
  with the broad swell, so only the hills' own hollows fill: about as much of the marsh and jungle under water as
  terrain 1 (measured offline: marsh 19%, jungle 40%; a flat level drowned half of them). Seas stay flat.
- Bogs: on terrain 2 a hollow must be up to a cell deeper to be a bog (more on hilly ground: gen.comp
  `bogDepth`'s `amp`), so the jungle stays about as firm as before and the marsh keeps its bogs.
- Layers (gen.comp strata): the top layer is about 1.6x deeper, the subsoil 2.6x plus 6 with a wandering lower edge
  (fbm along the arc, +-7) and lobes of stone reaching into its lower part; on steep slopes both thin out
  (`steep` from the surface's slope), so cliffs show rock.
- Caves (`caves2`): tunnels on a domain-warped noise, varying in width, looping and branching, a second, finer set
  below 40 cells deep; caverns are wide and low (the radial axis stretched x1.8), kept below a lid that wobbles
  ~30 cells under the mean surface (so mountains stay solid, not hollow). `caveSpike`: stalactites hang from cavern
  ceilings and stalagmites rise from floors as tapering cones, one chance per 11 columns. Overall about as much
  rock is hollow as in terrain 1 (~25%, /home/claude/tools/cave_measure.py), in fewer, bigger shapes.
- Trees (all sets, gen.comp `trunkIn`, `limbIn`, `twigsIn`): oak, elder and jungle trunks taper toward the top,
  limbs taper toward their ends and end in twig forks, so big trees no longer end in square stubs (user, 26 Nov:
  "very large trees that look very square at the end of the branches ... the trunk and branches end too abruptly
  for how thick they are"). Trees already generated on a visited planet stay as they were saved.
- Previews: /home/claude/tools/terrain_preview.py (v1 against v2 per biome) and tree_preview.py, if present.

## Each kind of world's own biome (user, 26 Nov: "do other worlds have unique biomes and unique enemies?"; chose a set of seven, each with its own ground, plants, 2-3 creatures and a guardian, showing up mostly on its kind of world)
- `Defs.BIOMES`: basalt (Basalt Columns, volcanic), kelp (Kelp Isles, ocean), saltflats (Saltglass Flats, desert),
  mangrove (Sunken Mangroves, marsh), crystalfields (Crystal Fields, frozen), elder (Elder Canopy, wild), meadow
  (Flower Meadows, realm). Each kind's `pool` in `Defs.KINDS` weights its own one in (and the others rarely,
  0.5, anywhere); the sea rule covers kelp as well as ocean (kelp: off 34, amp 16, so sand bars stand above the sea
  and channels run deep enough for Marelle).
- World materials are full (64), so the new biomes reuse materials: their look is gen.comp flora 11-17 and
  render-only touches keyed by the column's flora. gen.comp `flora()`: 11 basalt column clusters (DEEPSTONE,
  OBSIDIAN caps), 12 palms on the bars and kelp strands in the water, 13 salt pillars and knee-high salt heaps
  (SANDSTONE), 14 `mangroveTree` (arched stilt roots, trunks may stand in up to 12 cells of water), 15 ice spires
  tipped with FROST, 16 `elderTree` (a flared trunk, a wide crown of overlapping masses) with ferns, 17 hedgerows
  (LEAF), dry-stone walls (MASONRY), flowers and a lone oak. Scenery stone is background with floraId 0, so
  support.comp leaves it standing. render.comp: meadow petals on hedge tops and in the grass, the salt flats'
  sand and pillars whitened and cracked, basalt fissures glowing, glints on the crystal fields' snow; the far tree
  line maps elder/mangrove to jungle trees and meadow to sparse oaks.
- Old saves keep their planets: `Defs.BIOME_SET` (2) is saved as "bset"; a save from before (or the
  `world_N.wfw` files beside one) fills `Defs.legacy_biomes`, and `make_planet_for` grows those planets from
  each kind's `pool_v1` (cache key "ws:i:v1"), so a planet already generated gets the same biomes (`_grown_planet`
  draws one randf per biome pick whatever the pool, so radius, name and the rest never move). New journeys clear it.
- Anything that looks up a biome's buildings, dungeons or styles goes through `Defs.base_biome(b)` (`BASE_BIOME`:
  basalt -> ashland, kelp -> ocean, saltflats -> desert, mangrove -> marsh, crystalfields -> tundra, elder ->
  forest, meadow -> forest).
- Test: `_test_newbiomes` (tests/exotic.gd, section "newbiomes"): an old planet keeps its biomes; then a planet
  with all seven (cache entry "0:7:v2" overridden), a picture of each (`saves/shots/newbiome_<b>.png`), plant
  and scenery counts, its creatures, and `_test_guardians` for the seven (a swimmer's altar on the seabed where
  the water is deepest).

## Ore is rarer (user, 25 Nov: "ore is much too abundant. it is very easy to find ore. i dont want it to be be super hard to find but currently it is everywhere")
- gen.comp `ORE_T` (0.025) raises every common ore's threshold (copper, coal, crystal, frost, ember, wisp): about
  half the veins. Under the test planet's start (600 x 300 cells): copper 1772 -> 934, coal 1629 -> 870, wisp ore
  149 -> 92, frost 58 -> 25, prism crystal 54 -> 18 (`_test_quest` prints it). Each kind's own ore is as it was.
  Only worlds made from now on: saved worlds keep their cells.


## Terrain 3 (27 Nov; user: "the ocean isnt nearly deep enough on the water world i went to. how do we make it really feel like a deep dark vast ocean. same thing with other worlds. they feel a bit shallow still i can dig away the entire surface very easily. Underground feels vast, but i want the biomes to feel vast as well. i also feel a lack of enemies digging underground, we need developed cave systel with underground foliage and creatures living there as well."; chose "New journeys only", "Abyssal", and all of "Deeper biome ground", "A cave layer per biome", "Wider biomes")
- `Defs.TERRAIN_SET` 3: new journeys only (a journey saved with "tset" 2 keeps terrain 2; 1 keeps 1). Everything of
  terrain 2 holds as well (gen.comp `TV2` is true on 3; `TV3` adds).
- Abyssal seas (surface.comp): an "ocean" biome gets flags 32 from gpu_world `build_surface` on terrain 3. Its
  columns keep the sandy shelf for `shelf` cells (120 +-45) out from each shore, dip 20 toward the lip, then drop off
  over 60-100 cells into the abyss: 500-800 cells of water (fbm /330), with trenches a few hundred cells across (a ridged fbm /420 to the
  6th power) up to 280 deeper. The deep ground under it follows (deepR = rs - 40). The floor's plants are the deep
  ocean world's (gen.comp flora 6 on terrain 3 takes flora 10's branch: kelp above 170 down, then glowing coral fans,
  tube worms and glowcaps). Deep in that water (150+ under the sea's top) main `_try_spawn` brings the abyss's own
  (lantern eels, abyss jellies, gulpers). Water darkens with depth as every sea does.
- Deeper ground (gen.comp `strata`): the top layer (sand, snow, ash, mud, mycelium) 3x + 2 deep, the subsoil 6x + 20
  (+-13): about 70-110 cells of the biome's own ground under most biomes (grass stays one cell; stone biomes stay
  stone). Below terrain 2's depth, sand has packed into sandstone (a tunnel through it doesn't pour a hundred cells
  of sand). The deep soil has its own boulders (fbm /8 > 0.74), gravel, and a little copper and coal (thresholds 0.85
  + ORE_T), so the first ore isn't a hundred cells down.
- Wider biomes (defs.gd `_grown_planet`): about two thirds as many biomes round a grown planet (never fewer than its
  must-haves and one), so each is half again as wide. The classic system's hand-made lists are unchanged. The
  planet cache key carries the terrain (`make_planet_for`).
- The cave layer per biome: under each biome's ground, in the stone, the rock takes its `ug`'s look (gen.comp
  `caveLayerRock`): Glowroot Caverns (ug 0) moss-grown stone (MOSSBLOCK) and root-soil pockets; Prism Hollows (1)
  banded sandstone; Frostvein Grottos (2) ice lenses and snow; Smoldering Vaults (3) magma rock and obsidian streaks.
  So every cave wall in it shows it. Its plants (`caveFlora`, background, keyed by the floor or roof they grow from):
  Glowroot: glowcap clusters, tall glowing stalks, moss and ferns on floors, roots and vines (some with a glowing
  bud) hanging from roofs; Prism: crystal clusters up and down; Frostvein: frost blooms, snow, icicles; Smoldering:
  ember vents, ash, glowing drips. Deeper than the stone, glowcaps now and then. Materials reused (no new world
  materials: they stay under 64).
- Creatures: see creatures.md (each cave layer's own, and more of them underground).
- Test: `_test_terrain3` (the "worlds" section): fewer biomes a planet over 20 seeds; a new game's planet made on
  terrain 3: the soil's depth at 12 columns, the cave layer's themed rock and plants (picture cave_layer.png); an
  ocean world made: its deepest water, the share past 300, a shelf (picture abyss.png).
