# Wisp Forge

A pixel-art mage game where the whole world is simulated, cell by cell. You start with a plain staff and a
couple of small spells on a round planet you can dig all the way to its heart: sand pours, water flows,
trees fall, buildings come down when you dig out what holds them up. Gather what the world is made of,
forge it into spells, staves and gear, call up the guardians of each land, build a ship, and sail out to
the other worlds of the system and on to the stars beyond.

Built in Godot 4; the world runs on the graphics card.

## Starting the game

- **From this folder:** double-click **`Play Wisp Forge.bat`**. Everything it needs is here.
- **A shared copy:** unzip `Wisp Forge.zip` and double-click **`Wisp Forge.exe`**.

Needs a graphics card with Vulkan or Direct3D 12 (anything from about the last eight years).

The title screen has three save slots: click a saved journey to carry on, or an empty slot to start a new
one. Every journey grows a new star system of its own.

## Controls

**Moving and the staff**

| Key | Does |
|---|---|
| A / D | Walk |
| W / Space | Jump; hold to levitate once you've forged Levitation; hold in water to swim |
| Down + jump | Drop through a wooden platform |
| Left mouse | Cast the chosen spell |
| 1–9 / mouse wheel | Choose a spell |
| Right mouse | Dig: pulls matter into your satchel (costs mana, more for harder stuff) |
| Shift + right mouse | Take back walls, furniture, torches and workshops (furniture and workshops come whole) |
| Q / E | Step along the item belt over the spell bar: what you pinned (right-click it in the satchel) and what you held lately (in space: turn the view) |
| H | Drink a Healing Draught (health doesn't come back by itself) |

**Menus**

| Key | Opens |
|---|---|
| I / Tab | The satchel |
| C | The Wisp Forge (crafting, anywhere) |
| J | The recipe book |
| L | The journal (the main quest) |
| M | The map: the planet, then Tab for the galaxy. Click to set a waypoint, right-click or Backspace clears it |
| N | Show or hide the minimap |
| B | The satchel's Plans (see below) |
| Esc | Settings and pause; "Save and return to title" |
| F11 or Alt + Enter | Fullscreen |
| F3 | Frame time and where it goes |

**Things in the world**

| Key | Does |
|---|---|
| F | Talk, trade, open a chest or door, use a workshop or altar, board or leave the skiff. At a bed with a roof over it: make it home |

**Placing what you carry**

Click anything in the satchel (I) to take it in your hand: the cast button becomes Conjure, which places it
where you point, within your staff's reach. Sand, water and other loose stuff pours from the staff; blocks are
painted with the brush or laid in shapes; furniture, workshops, torches and doors show where they'll go first.
**Plans** (the satchel's Plans; B opens it) are rooms, houses, roofs, stairs and platforms:
take one in your hand and Conjure raises it from your materials, course by course, as you cast. A plan is
never used up. You start with a few; others come from your first stone blocks or bricks, village shopkeepers
and scrolls in chests.

| Key | Does |
|---|---|
| Left mouse | Place (for a line, rectangle or frame: press, drag and let go) |
| Right mouse | Dig |
| Shift + right mouse | Take furniture, a torch or a workshop whole |
| G | How blocks are laid: brush, line, rectangle, frame |
| [ ] | Thickness of a line or frame; a structure's width; a staircase's step |
| - / = | A structure's storeys; a staircase's height |
| V | Blocks in front, or as a back wall (planks, logs, stone, brick, sandstone, glass) |
| R | The next design (furniture in a stack, a structure's variation, Level the Ground's fill) |
| T | Mirror a piece; a structure's style |
| B | Open the satchel at its Plans (aboard a parked ship: the ship builder) |

**Unmake** (a spell beside Conjure) takes away what's built or grown: press, drag and let go. G picks a line, a
rectangle, a frame or Level the Ground (press where the ground should be, drag along, let go; R the fill); V picks
what it takes: blocks, back walls, furniture or everything; [ ] the thickness.

**The skiff and space**

| Key | Does |
|---|---|
| K | Call the skiff to you (in space: the wisp carries you back aboard) |
| F | Board or step off |
| W A S D / Space | Fly; holding cast steers toward the cursor (in space with the cannon fitted, cast fires it) |
| X | Stand up out of your seat to walk the deck, or sit back down |
| Hold R | Mend the hull (planks or hull plating, and a little mana) |
| B | The ship builder (only while it's parked) |
| G | Go below into the ship's pocket (while it's parked); at the pocket's arch, back up aboard |
| Shift | The Starsail, for crossing between stars (burns Wisp Cells) |
| Mouse wheel, - / + | Zoom out in space |

**Developer keys:** F9 a stock of every material, F7 / F8 move 120 cells up / down.

## How a journey goes

The wisp beside you speaks the next step, the gold line on the screen repeats it, and the journal (L)
lists them all. Roughly:

1. Dig, forge your first spells, build a kiln and a smelter, and work up through better staves.
2. Build a Summoning Altar, forge a guardian's sigil and beat two guardians for the plans of a ship.
3. Dig to the planet's heart, beat Vulkhar the Ember Golem, harvest the core and forge the Core Drive.
4. Forge the Wisp Keel and build it out into a ship of your own in the ship builder.
5. Fly to the other worlds. Some are walled by storms, radiation or shards, and each wall has a key you
   forge. Each kind of world has its own ore, dangers, core and creatures.
6. Out in space: derelict wrecks and stations, pirates, trading outposts, creatures between the stars,
   strange worlds with mysteries, and the Starsail to the next system.

## Settings and saves

Esc (or Settings on the title screen): quality (Auto by default: it steps down by itself if the game runs
slowly), the retro dithering filter, the view (the world as it is, or laid out flat), the window, pixel size, music and sound volume. Choices are kept
in `saves\settings.json`.

Saves are kept per slot in `saves\slot_1` to `slot_3` (a shared build keeps them in
`%APPDATA%\Wisp Forge\saves`). The whole world is saved, every cell, every two minutes, when you quit and
when you travel. Copying this folder copies your games.

## What's in this folder

| Path | What it is |
|---|---|
| `Play Wisp Forge.bat` | Starts the game |
| `Play (debug console).bat` | Starts the game with a console that shows errors |
| `Edit in Godot.bat` | Opens the project in the Godot editor |
| `Build game.bat` | Builds `Wisp Forge.exe` and a zip to share, into `build\` |
| `Run tests.bat` | Runs the automated checks (on a test planet; your saves aren't touched) and writes `saves\test_report.txt` |
| `Check scripts.bat` | Checks the scripts for errors (`saves\check.txt`) |
| `game\` | The Godot project: scripts, GPU shaders, audio |
| `engine\` | Godot 4.7.2, portable (not stored in git; see `engine\README.md`) |
| `saves\` | Your games and settings |
| `web-prototype\` | The first browser prototype (a flat planet), kept for reference |

## For development

- `CLAUDE.md`: the guide for working on the code: how it's laid out, conventions, testing, gotchas, and an
  index of the notes on each system in `docs\`.
- The roadmap and the design decisions live in the claude.ai project ("Wisp Forge"), in
  `claude/roadmap-and-decisions.md`.
- Music: `game\audio\music\README.txt` says which tracks play where.
