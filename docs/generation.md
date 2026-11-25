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
  has a tree function in gen.comp (oak, pine, cactus, willow, charred, palm, jungle, acacia, mushroom) plus
  undergrowth in `flora()`; plant materials get their look in render.comp's `plantColor`.
- Roots (`ROOT`, background only): gen.comp `treeRoots` draws a taproot and a few side roots under each tree
  (`rootWidth` per flora type), into the ground below the surface and into the air where a slope drops away
  under the trunk, so no tree shows a flat underside. Roots score lowest in `flora` (every other part of any
  tree wins a cell), aren't tree-flagged in the collision grid (build over them freely), and dig up as Wood.
- Mud (`MUD`, a liquid): a biome's liquid ground layer (marsh top, jungle subsoil) is only liquid in bogs
  (gen.comp `bogDepth`: hollows the ground rises around, or under standing water, never on building sites or
  over caves); everywhere else it is generated as grass over dirt, so ground never hides a pool you sink into.
  render.comp draws mud dark and glossy with a wet top sheen and bubbles. react.comp: loose (unanchored) dirt
  touching water turns to mud; unanchored mud in the open with no water near dries back to dirt.
