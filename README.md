# Wisp Forge

A pixel-simulated mage crafting game on a **round planet**, built in **Godot 4** with the
whole world simulated on the GPU.

## Play

Double-click **`Play Wisp Forge.bat`**. Everything it needs is in this folder:

| Path | What it is |
|---|---|
| `Play Wisp Forge.bat` | Starts the game |
| `Play (debug console).bat` | Starts the game with a console window that shows errors |
| `Edit in Godot.bat` | Opens the project in the Godot editor |
| `engine\` | Godot 4.7.2 (portable, nothing installed; not stored in git, see `engine\README.md`) |
| `game\` | The Godot project: scripts, GPU shaders, scene |
| `web-prototype\` | The original browser prototype (flat planet), kept for reference |
| `saves\` | Your progress and saved worlds |
| `Check scripts.bat` | For development: checks the game's scripts for errors (writes `saves\check.txt`) |
| `Run tests.bat` | For development: builds a fresh test planet (your saves aren't touched), checks that buildings stand, chests open, guards appear, blocks fall, saves round-trip and the frame rate holds, then writes `saves\test_report.txt` |

Needs a graphics card with Vulkan or Direct3D 12 (any GPU from roughly the last eight years).

## Controls

| Key | Action |
|---|---|
| A / D | Walk |
| W / Space | Jump. Hold in the air to levitate (uses mana); hold in water to swim |
| Right mouse | Excavate: pull material into your satchel (hold, or tap for a short burst). Never takes a building's back walls or chests |
| Shift + right mouse | Deconstruct: take background tiles (back walls, furniture, plants), on purpose |
| Left mouse | Cast the selected spell |
| 1–6 / mouse wheel | Select spell |
| Q / E, or click the satchel | Choose what Conjure places |
| F | Open a treasure chest you're standing next to |
| C | Open the Wisp Forge (crafting, pauses the game) |
| M | Zoom out in steps, all the way to the whole planet |
| Esc | Settings: quality, dithering, pixel size |
| F9 / F8 / F7 | Developer keys: +200 of every material / move 120 cells down / up |

## The round planet

- The world is a disc of about **11 million simulated cells**: 8,192 cells around at the surface,
  ~1,300 cells deep to the heart. Walk all the way around and you come back to where you started.
- "Down" always points at the core. The camera turns as you walk so your feet stay at the bottom.
- Cells are stored in **ring shells**. Every time the radius halves, the number of cells per ring
  halves too, so pixels stay roughly square all the way to the core.
- Day and night are real: the sun lights the side of the planet facing it, and the far side is in night.
- Fly high enough and the sky fades into space; gravity weakens with altitude.
- Layers from the top: biomes (forest, bog, tundra, mountains, desert) → cave biomes
  (Glowroot Caverns, Prism Hollows, Frostvein Grottos) → stone → the Umbral Deep → the Molten Mantle → the Planet Core.
- **Vulkhar, the Ember Golem** waits in an arena on the opposite side of the planet from where you start,
  at the top of the mantle. Defeating him gives you the Ember Heart.

## Foreground and background

Every cell has two layers:

- **Foreground**: terrain, sand, water, lava, gases, fire and anything you place. It collides with
  the mage and enemies, stops spells, and takes part in the falling-sand physics.
- **Background**: trees, bushes, reeds, kelp, cacti, cave decorations (glowshrooms, crystal and
  ice spikes) and the back walls of buildings. You, enemies, projectiles, sand and water all pass
  through it. Fire still burns background plants and wooden walls (Fireball sets forests alight),
  and **right-click harvests them** when nothing is in front. Other spells don't affect them.
- Plants need support too: cut a trunk or dig out what holds a plant up and it crumbles into falling
  **timber** and **leaf litter** (which floats on water). Excavating these gives Wood and Leaves.
- Falling sand, snow, ash and rain don't push or drag bodies; only settled material counts for collisions.

## Things fall when nothing holds them up

Every solid block knows how it is supported:

- **Untouched natural ground is part of the planet** and never falls by itself, so caves, cliffs
  and overhangs stay up however wide they are.
- **Digging or blasting loosens the ground around it.** Cut a chunk of rock free, or dig out what
  holds up a ledge, and it **creaks and sheds dust for a moment**, then drops as one piece, keeping
  its shape until it lands. After a long fall,
  rock, brick and wood break into gravel and timber. **Falling rock hurts**: the further it fell,
  the harder it hits, so mind what's above you when you undermine something.
- **Blocks you place have a strength.** Stacking straight up is always fine, but each material can
  only reach out so far sideways (or hang) before it gives way. Dirt: 10, planks: 12, wood: 16,
  sandstone: 20, brick: 24, stone blocks: 28, stone: 40, obsidian: 60. Conjure something in mid-air
  and it falls; build a bridge too long and the far end comes down.
- Ice, wood and planks float on water; anything else sinks through liquids.

## Ruins, castles and towns

Each planet grows about 35 structures from simple rules (no hand-made maps), in materials that suit
the biome. You'll find:

- **Cottages and villages**: plank houses with tiled roofs in forests, log cabins in the tundra,
  sandstone dwellings with domes in the desert, brick houses in the ash lands.
- **Watchtowers and castles**: stone towers, and on the mountains whole castles with two towers,
  curtain walls with gates, and a keep holding the lord's hoard.
- **Sun temples**: stepped sandstone pyramids with a passage to a treasure chamber.
- **Stilt huts** standing in the marsh water.
- **Mines**: a headframe over a deep shaft with plank landings and timbered tunnels.
- **Catacombs**: a shrine on the surface with a stairwell down to stone corridors and burial rooms.
- **Sealed vaults** deep underground, full of treasure, with no way in but digging.

Many are **ruins**: the generator damages an intact building (broken tops, holes, rotten wood,
moss, missing torches), then lets the planet's physics run before you arrive, so whatever lost its
support has already fallen into rubble. Desert ruins are half buried in sand, forest ruins are
overgrown with vines. The HUD shows the name of the structure you're in.

**Treasure chests** sit in rooms, tombs, mines and vaults. They're furniture in the background, so you
walk past them instead of bumping into them. Stand next to one and press **F**: it
opens with its full loot (ores, crystals, wisp ore, glass, torches, stone blocks; more in deep places
and on richer planets) and stays behind as an opened chest. Digging a chest out with right-click
isn't possible any more; chests only open with F. Chests can hold **rare finds** that exist nowhere else:

- **Scroll of Blink**: unlocks the Blink spell at the Forge (step through space to the cursor).
- **Scroll of Starfall**: unlocks Starfall (a falling star: a huge fiery blast).
- **Warden's Ring** (+25 max health), **Sage's Circlet** (+40 max mana), **Featherstep Boots** (higher jumps).

Castles and vaults hide the best chests, then temples and catacombs. In ruins, some chests are
**mimics** that bite back, and drop rich loot (often a rare find) when beaten.

**Guardians** wait inside: skeleton wardens in castles, towers, temples, catacombs and mines, and bats
in the mine tunnels. They appear as you come near and stay dead once you've beaten them. The first
building near where you arrive on a planet is always unguarded.

Rooms are 18 cells floor to floor (the mage is 12), cottages are 22 to 32 cells wide, and castles
spread over about 140 columns: two corner towers, outer walls with gates, courtyards, and a great keep.

Buildings have **back walls**, which are part of the structure, the way a real wall has depth: they
hold up the wall above a doorway and the floors in front of them. Knock enough of a building away and
the rest comes down; wooden houses burn.

## Settings

Press **Esc** in the game, or **Settings** on the title screen. Your choices are saved in `saves\settings.json`.

- **Quality**: High, Medium or Low. Low runs fewer simulation and lighting passes per frame and uses
  bigger pixels, for weaker graphics cards (and phones later).
- **Dithering**: Off (the default) draws clean colour bands, SNES-style. Subtle adds a little texture,
  and Retro is the old checkerboard look.
- **Pixel size**: Auto, or a fixed 2 to 5 screen pixels per world pixel. Bigger is closer up.

## Art style

16-bit / SNES-inspired: four-tone material ramps with textured stone, dirt, bark and bricks,
lit top edges and shaded undersides, grass tufts and flowers, two-tone clouds, two parallax hill layers,
outlined sprites, lighting in hard bands, and final colour reduced to 15-bit (32 levels per channel).
Dithering is off by default; see Settings.

## Progression

Excavate → forge Fireball / Tidecall / Copper Focus → go deeper for ember, wisp and frost →
Heat Ward and Obsidian Focus → defeat Vulkhar → Core Siphon → harvest 40 Planet Core →
forge the **World Gate** to travel to the next planet. The planets are Verdance → Cindrel (volcanic) →
Thalassa (water world) → Sere (desert) → Fenhollow (marsh), then they repeat with richer ores.

Progress (satchel, spells, upgrades, planet) is saved automatically, and so is **the whole world**:
every cell of the planet is saved, compressed, every two minutes, when you quit and when you travel.
**Continue** puts you back exactly where you were, in the world as you left it. **New Journey** wipes the saved worlds.
Planets saved by an earlier version of the structure generator are built again once when you
load them (your satchel, spells and upgrades are kept). Saves live in the `saves\` folder next to this README (`progress.json` plus one `world_<n>.wfw` per planet,
about 15 MB each), so copying the whole Wisp Forge folder carries your game with it. Closing the window
with the X saves first, then quits.

The weather can't bury the world: rain that lands in lakes merges in instead of raising them,
rain puddles dry up in the sun and soak into soil, exposed snow melts in sunlight (very slowly in
cold biomes), ash blows away over time, and fresh snow and ash pack down once drifts get deep.

## How it works (`game\`)

| File | Role |
|---|---|
| `scripts/defs.gd` | Materials, biomes, planets, spells, recipes, sprites. Generates the GLSL material tables |
| `scripts/gpu_world.gd` | Compiles the compute shaders, generates planets, steps the sim, reads results back |
| `scripts/main.gd` | Frame loop, player and enemy physics, spells, crafting, weather, saving |
| `scripts/overlay.gd`, `scripts/ui.gd` | Sprites and particles drawn over the world; HUD, forge, menus |
| `shaders/gen.comp` | Planet generation: strata, caves, ores, pools, plants, boss arena |
| `shaders/move.comp`, `boundary.comp` | Falling sand on the GPU (2×2 Margolus blocks), plus moving material across shell seams |
| `shaders/support.comp`, `topple.comp` | Structural support for every solid and back wall, and loose pieces falling as one |
| `scripts/buildings.gd`, `shaders/stamp.comp` | The structure generator (towns, castles, ruins, mines, catacombs, vaults) and writing them into the planet |
| `shaders/react.comp` | Fire, burning, lava + water → obsidian, melting, steam, rain |
| `shaders/brush.comp` | Excavate, explode, fill, freeze and conjure |
| `shaders/light.comp`, `blur.comp`, `render.comp` | Sunlight, canopy shade, glow, coloured light, and the 16-bit renderer (textures, edges, parallax, dithering) |
| `shaders/grid.comp` | A 384×384 sample around the mage, used for collisions on the CPU |

Each frame only the area around the camera is simulated (about 700×500 cells), entirely on the GPU.
The CPU gets back the finished picture, a collision grid and dig counts.

## Next steps

- A guardian boss for every biome
- Seamless flight from orbit to other planets
- Sound, gamepad support, and an exported single `.exe`
