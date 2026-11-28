# Wisp Forge: notes for development sessions

Godot 4.7.2 game, a pixel-simulated mage on a round planet. The whole world is simulated in GLSL
compute shaders through a local RenderingDevice. The roadmap and design decisions live in the
claude.ai project doc `claude/roadmap-and-decisions.md`.

## Layout
- `game/` is the Godot project (no imported resources, no `class_name`; scripts are preloaded, `Defs` is an autoload).
- `game/scripts/defs.gd`: materials, biomes, planets, spells, recipes, enemies, sprites. `glsl_prefix()`
  generates the GLSL tables, so CPU and GPU always agree. `NM` is the material count.
- `game/scripts/gpu_world.gd`: shader compile (custom `#include "name"` from `shaders/inc/`), buffers,
  generation, `step()`, `stamp()`, `settle()`, save readback.
- `game/scripts/buildings.gd`: procedural structures (blueprints stamped by `shaders/stamp.comp`).
  Deterministic per planet, and re-planned on load for labels and guards. `GEN_VERSION` in main.gd makes saved
  worlds generate again when bumped (see the rules below).
- `game/scripts/main.gd`: game loop, physics, spells, enemies, chests, guards, saving.
- `game/scripts/tests.gd` is the test mode's `run()`; its checks and helpers are in `game/scripts/tests/` (a chain of
  scripts, each extending the one before: base, creatures, world, building, towns, player, space, exotic, perf),
  so a file may only call into files before it. `docs/testing.md` has more.
- The other scripts are one file per system (`space.gd`, `skiff.gd`, `towns.gd`, `ecology.gd`, `quest.gd`...);
  `docs/` says which file holds what. Shaders are in `game/shaders/` (`gen`, `move`, `boundary`, `support`,
  `topple`, `plants`, `react`, `brush`, `stamp`, `light`, `blur`, `render`, `grid`, `navmap`, `rectread`,
  `surface`), with shared code in `shaders/inc/`.

## Notes on each system: `docs/`
Read the file for the system you're about to change before changing it. Each keeps the user's own words for
why things are the way they are (quoted, with the date), the names in the code, and its test.

| File | What it covers |
|---|---|
| `docs/world.md` | Planet geometry (shells, seams, the shell table, stamps cell for cell at any depth), worlds per game, the cell format of both layers, GPU counters |
| `docs/generation.md` | Structures (chests, dungeons, props), terrain (foundations, packed ground, biome borders, roots, mud), each kind of world's own biome |
| `docs/rendering.md` | The sky into space, the parallax background, the close view and its picture, the map, fog of war, point lights, clouds |
| `docs/space.md` | Space and travel between planets, asteroids, the galaxy (systems, sectors, nebulae, charting, the Starsail, the space map), space's view |
| `docs/space-places.md` | Derelict wrecks, pirates, trading outposts (docked into their halls, an instance), derelict stations and aliens, void life and anomalies |
| `docs/ship.md` | Pixel bodies, ship classes (forged whole), ship parts, hull damage and mending, fuel, the pocket dimension (its isle, the home terrace), cargo; the old builder |
| `docs/exotic-worlds.md` | The deep ocean world, the gas giant, the dying star and the black hole, with their mysteries |
| `docs/progression.md` | The main quest, getting off the first planet, barriers by kind, cores, ores and gear, hazards, skiff upgrades |
| `docs/climate.md` | Settlement and climate per planet kind, weather, sky events |
| `docs/towns.md` | Living towns: villagers, requests, trade, sleep, memory, rebuilding |
| `docs/exploration.md` | The exploration loop: world-bound finds, places to discover, parts, rolled traits, artifacts and the Lectern, the Worldsong (the world mending itself), bigger worlds, roots |
| `docs/crafting.md` | Workshops, crafting as one system, mana for shaping the world, recipes you discover |
| `docs/building.md` | Build mode, furniture, doors, stairs, precise removal, torches, carried pieces, home |
| `docs/effects.md` | Spell effects (vfx.gd) |
| `docs/ui.md` | The UI style, font, icons, HUD, forge cards, speech bubbles, the satchel, the minimap, the Esc pause |
| `docs/creatures.md` | Wild life (tempers, hunting, sleep, habitats), wild creatures, foe AI, pathfinding |
| `docs/bosses.md` | Summoning guardians, biome guardians and lairs, heart bosses per kind of world, wardens, Vulkhar, bosses that come to you and hunt you down |
| `docs/player.md` | The mage's art and rig, the starting power, spells' cooldowns, digging speed, health |
| `docs/physics.md` | Rigid chunks (felled trees, falling building pieces), standing on the curved world, chests at rest, scaffold |
| `docs/performance.md` | Making a planet quickly, the profiler, the benchmarks, quality levels for lower-end PCs, hot paths, no stalls, read-back |
| `docs/testing.md` | The test mode in full: time limits, running one section, the checks that sometimes fail |
| `docs/release.md` | Building the shareable .exe, music, sound effects and ambience, save slots, the window |

## Rules that hold everywhere
- Everything is modular and procedural: structures, planets, ships, creatures and their art are grown from
  parts by a seed, never hand-drawn layouts. New features are added as parts other generators can reuse.
- Don't bump `GEN_VERSION` unless the user agrees: worlds already made would be generated again.
- Material limits: world materials stay under 64 (the collision grid keeps a cell's type in 6 bits), and every
  material under 112 (the GPU counters). The planet seed stays under 2^24 (it goes to the GPU as a float).
- Rows go negative in the orbit band: use `floor` for rows; in scripts use `Defs.NS` (typed) for surface columns.
- The collision grid is flat around the mage, so level ground curves away in it: never assume a floor is on
  one row; follow it.
- Code that reads the GPU now and then while you play asks (`gpu.request_rect` / `take_rect`) instead of
  `read_rect`, which waits for the frame in flight. Never call `get_image()` on a texture while drawing.
- Hot per-cell loops in buildings.gd work on a local copy of the cells and plain tables and write back once:
  in the editor-build engine every call on an object goes through a shared lock.
- Keys are rebindable (keys.gd): test a key with `key_is(k, "action")` / `key_held("action")`, never `KEY_F` and the
  like (only Esc, F11, 1-9 and the developer keys are fixed). A prompt naming a key goes through `keys_in`.
- Read mana regen through `mana_regen_of(m)`, never `m.mana_regen` directly; read gear stats through
  `gear(stat, m)`.
- A test that sets something up in the air takes it away again; one that sets up near where you arrive looks
  for a clear spot first (`_clear_stretch`).

## Testing
- `Run tests.bat` runs every check on a test planet (the classic system, world seed 0) and writes
  `saves/test_report.txt` (and `test_log.txt`, pictures in `saves/shots/`). A full run takes about 22 minutes.
- A non-empty `saves/test_only.txt` naming one section runs just that one (25-50 s); `docs/testing.md` lists
  the names. Leave it empty when done.
- `Check scripts.bat` checks the scripts for parse errors (`saves/check.txt`; "Identifier not found: Defs" is
  expected).
- Some checks fail now and then in the full run but pass alone (recipes, a village's sleepers; the felled tree,
  digging a pit and the wild-life checks were fixed 26 Nov, see docs/testing.md); run one alone before chasing it.

## Keeping these notes
- A new system or a change to one goes in its file in `docs/` (or a new file there, added to the table above),
  with the user's words and the date for why. Keep this file short: only what holds everywhere.
- The roadmap and decisions (`claude/roadmap-and-decisions.md` in the claude.ai project) say what was decided
  and what's next; the docs here say how the code does it.

## Gotchas
- Never take `%` of a negative number in a shader: Vulkan leaves it undefined, and on the NVIDIA laptop it came out
  right only when the divisor was a power of two (Verdance was 8192 columns round; at 12288, every stamp anchored to
  its right vanished). common.comp `wrapc` only ever takes `%` of non-negative numbers; use it. (render.comp's brick
  and plank patterns still take `%` of rows, which go negative in the orbit band: only a look, but mind it.)
- Tests that set something up "a little way from where you arrive" must look for a clear spot (`_clear_stretch`:
  level ground, nothing standing over it), not trust the layout: the planet changes size and seed.
- Windows reserves file names like `aux`, `con`, `nul`, `prn`. Never name a shader include that way.
- Local variables must not shadow Object methods (`set`, `_set`, `get`) or each other inside one function.
- Shaders: `/home/claude/tools/glcheck` plus `build_shaders.py` syntax-check them with Mesa, if those tools exist in the session.
- Scripts: run `Check scripts.bat` on the PC; it writes `saves/check.txt`. Under `--check-only`,
  "Identifier not found: Defs" is expected (the autoload isn't loaded); real parse errors show up as Parse Error.
- The test mode saves pictures of a few ruins and buildings to `saves/shots/` (midday, no title screen);
  stage them through the device bridge to look at the art without walking around in the game.
- Don't take computer-use screenshots while the test mode runs: the screenshot hides (minimizes) the Godot window,
  it stops redrawing, and every picture in `saves/shots/` after that is the same stale frame (the tests still pass).
- Testing on the user's laptop: files are committed to `C:\Wisp Forge` through the device bridge. Wait about 12 s after
  writing to `/mnt/user-data/outputs` before committing, otherwise stale copies get written.
