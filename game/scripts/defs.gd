extends Node
## Wisp Forge — shared game data (autoload singleton "Defs").
const Props := preload("res://scripts/props.gd")
## Materials are defined once here; the GPU shaders get the same tables
## through glsl_prefix(), so CPU and GPU always agree.

const NM := 58
const K_EMPTY := 0
const K_SOLID := 1
const K_POWDER := 2
const K_LIQUID := 3
const K_GAS := 4
const K_FIRE := 5

const AIR := 0
const STONE := 1
const DIRT := 2
const GRASS := 3
const SAND := 4
const WATER := 5
const LAVA := 6
const WOOD := 7
const LEAF := 8
const FIRE := 9
const SMOKE := 10
const STEAM := 11
const OBSIDIAN := 12
const DEEPSTONE := 13
const COPPER := 14
const COAL := 15
const EMBER := 16
const FROST := 17
const WISP := 18
const MUD := 19
const ICE := 20
const MAGMAROCK := 21
const CORE := 22
const SHROOM := 23
const GRAVEL := 24
const BRICK := 25
const GLASS := 26
const SNOW := 27
const CRYSTAL := 28
const ASH := 29
const PLANK := 30
const CACTUS := 31
const TIMBER := 32
const LITTER := 33
const MASONRY := 34
const SANDSTONE := 35
const TILE := 36
const MOSSBLOCK := 37
const TREASURE := 38
const TORCH := 39
const OPENCHEST := 40
const SCAFFOLD := 41      # a one-way platform: you jump up through it and drop down through it
const RUNESTONE := 42     # warded stone: dungeon walls, only the Core Siphon cuts it
const DECOR := 43         # props (furniture, signs, lamps...): background pixels, colour from Props.PALETTE
const WOODDOOR := 44      # a closed door in a doorway (its cells know which part they are: row << 2 | column)
const CAP := 45           # a giant mushroom's cap (each mushroom has its own colour, from its plant id)
const STALK := 46         # a giant mushroom's pale stem
const MYCELIUM := 47      # fungal ground (the Mirecap Grove)
const DRYGRASS := 48      # golden savanna grass: the ground's top and the tall tufts on it
const ROOT := 49          # a tree's roots (background): they give way to every other part of a tree, and
                          # building over them is fine (it can't fell the tree); dug up they give Wood
const STARIRON := 50      # star iron: found only in asteroids (the metallic ones, deep in), for the Core Drive
# each kind of planet's own ore (KIND_ORES): found only on planets of that kind, for its gear and the Core Drive
const FIREOPAL := 51      # volcanic
const ABYSSPEARL := 52    # ocean: in the seabed, deep under the sea
const SUNSTONE := 53      # desert
const BOGIRON := 54       # marsh
const RIMECRYSTAL := 55   # frozen
const AMBER := 56         # wild
const SILVER := 57        # realm
## The GPU's counters, CNT per player: one per material (what the staff collected this frame) below
## C_HARD, then the rest. (They used to start at 50, so star iron counted as "too hard".)
const CNT := 128
const C_HARD := 112        # cells the staff was too weak for
const C_PLACED := 113      # cells placed by conjuring
const C_FALL_N := 114      # falling blocks overlapping the mage
const C_FALL_MAX := 115    # the longest fall among them
const C_CHEST_OPEN := 116  # chest cells opened (brush mode 7)
const C_CHEST := 117       # the nearest chest: (4095 - dist^2) << 20 | j << 10 | i
const C_CREAK_N := 118     # creaking blocks nearby
const C_CREAK := 119       # one of them: random << 20 | j << 10 | i
const C_FOG := 120         # how deep in cloud the mage stands (0-1000)
const C_FELL_N := 121      # cells of a felled tree or bush nearby
const C_FELL := 122        # one of them
const C_TREASURE := 123    # treasure cells dug
## The back walls a piece of furniture can stand in front of (see behind_index). 0 is none.
const BEHIND := [0, PLANK, WOOD, MASONRY, BRICK, SANDSTONE, GLASS, MOSSBLOCK, STONE, TILE, OBSIDIAN,
	RUNESTONE, DRYGRASS, CAP, STALK, DIRT, DEEPSTONE, ICE, LEAF, SCAFFOLD]

const MAT_NAMES := {
	0: "AIR", 1: "STONE", 2: "DIRT", 3: "GRASS", 4: "SAND", 5: "WATER", 6: "LAVA", 7: "WOOD", 8: "LEAF",
	9: "FIRE", 10: "SMOKE", 11: "STEAM", 12: "OBSIDIAN", 13: "DEEPSTONE", 14: "COPPER", 15: "COAL",
	16: "EMBER", 17: "FROST", 18: "WISP", 19: "MUD", 20: "ICE", 21: "MAGMAROCK", 22: "CORE",
	23: "SHROOM", 24: "GRAVEL", 25: "BRICK", 26: "GLASS", 27: "SNOW", 28: "CRYSTAL", 29: "ASH",
	30: "PLANK", 31: "CACTUS", 32: "TIMBER", 33: "LITTER", 34: "MASONRY", 35: "SANDSTONE", 36: "TILE",
	37: "MOSSBLOCK", 38: "TREASURE", 39: "TORCH", 40: "OPENCHEST", 41: "SCAFFOLD", 42: "RUNESTONE", 43: "DECOR", 44: "WOODDOOR", 45: "CAP", 46: "STALK", 47: "MYCELIUM", 48: "DRYGRASS", 49: "ROOT", 50: "STARIRON",
	51: "FIREOPAL", 52: "ABYSSPEARL", 53: "SUNSTONE", 54: "BOGIRON", 55: "RIMECRYSTAL", 56: "AMBER", 57: "SILVER",
}

# ---- planet geometry: rings ("shells") of cells, set per planet by set_geometry(radius) ----
# Rows count down from the top of the atmosphere (row 0, radius R_TOP) to the heart; the orbit band
# above the atmosphere has negative rows (-ORBIT_ROWS .. -1). The rows are cut into shells, each with
# its own number of columns, stored top to bottom. The surface shell (SURF, NS columns, square cells at
# the mean surface) reaches SURF_HALF rows up and down so the ground and nearly every structure lie in
# it. Above and below it the shells are thin, with square cells, and each has at most ~2% more or
# fewer columns than its neighbour: the view (one column of the camera's shell per pixel) changes
# too little at a seam to be seen, and a building that straddles one stays straight to a pixel.
#
# Stamps (blueprints, laid out in surface columns) go into every shell cell for cell, centred on
# their anchor (`stamp_x`): a building is the same, pixel for pixel, at any depth. Generated
# structures anchor on themselves; things placed or picked up near you anchor on `anchor_c`, your
# column (main sets it every tick), and so does `Build.cell_pos`/`cell_of`. In the surface shell
# the mapping is just the surface column, whatever the anchor.
const ATMO := 496.0          # the atmosphere's height above the mean surface
const ORBIT_ROWS := 256      # the orbit band's height: room to build into space
const R_IN := 80.0           # the planet's heart (not simulated)
const SURF_HALF := 330.0     # the surface shell reaches this far above and below the mean surface
const SEAM_STEP := 0.021     # the most a shell's columns differ from its neighbour's (away from the heart)
var RS0 := 1304.0            # mean surface radius (cells are ~square here)
var R_TOP := 1800.0          # top of the atmosphere: row 0
var R_SPACE := 2056.0        # the orbit band's ceiling: nothing above is cells
var ROWS := 1720             # rows from the top of the atmosphere to the heart
var NSH := 5                 # shells
var SURF := 0                # the surface shell
var SH_Y0 := []              # each shell's first row (shells top to bottom; SH_Y0 always even)
var SH_Y1 := []              # one past each shell's last row
var SH_N := []               # columns per shell
var NS := 8192               # columns of the surface shell (the surface table, blueprints), typed for scripts
var SURF_Y0 := 0             # the surface shell's rows (typed, for the quick paths)
var SURF_Y1 := 0

var KIND := PackedInt32Array()
var DENS := PackedInt32Array()
var HARD := PackedInt32Array()
var FUEL := PackedInt32Array()
var IGN := PackedFloat32Array()
var SELF := PackedInt32Array()
var ALPHA := PackedFloat32Array()
var GLOW := []          # Vector3 per material
var PAL := PackedInt32Array()   # NM*4 colours, 0xRRGGBB
var COLLECT := PackedInt32Array()
var PLACE := PackedInt32Array()
var NAMES := PackedStringArray()
var SPAN := PackedInt32Array()     # how far a solid can reach out from support before it gives way
var DEBRIS := PackedInt32Array()   # what a solid breaks into when it lands after a long fall (itself = stays whole)
var BGDEBRIS := PackedInt32Array() # what a background object crumbles into when nothing holds it up
var COLOR := []         # Color per material (UI swatch)
var SH_OFF := []

func _init() -> void:
	KIND.resize(NM); DENS.resize(NM); HARD.resize(NM); FUEL.resize(NM); IGN.resize(NM)
	SELF.resize(NM); ALPHA.resize(NM); PAL.resize(NM * 4); COLLECT.resize(NM); PLACE.resize(NM); NAMES.resize(NM)
	SPAN.resize(NM); DEBRIS.resize(NM); BGDEBRIS.resize(NM)
	GLOW.resize(NM); COLOR.resize(NM)
	for i in NM:
		ALPHA[i] = 1.0
		GLOW[i] = Vector3.ZERO
		COLOR[i] = Color.BLACK
		NAMES[i] = ""
		SPAN[i] = 32
		DEBRIS[i] = i
		BGDEBRIS[i] = 0
	_def(AIR, "Air", K_EMPTY, ["#000000"], {})
	_def(STONE, "Stone", K_SOLID, ["#6b6f7a", "#626672", "#737786", "#5b5f6a"], {"hard": 1})
	_def(DIRT, "Dirt", K_SOLID, ["#7a5234", "#6e4a2f", "#845a39", "#704c30"], {})
	_def(GRASS, "Grass", K_SOLID, ["#4f9a3a", "#5aa842", "#478f34", "#62b04a"], {"fuel": 18, "ign": 0.25})
	_def(SAND, "Sand", K_POWDER, ["#e0c27a", "#d6b66c", "#e8cc88", "#d0ad62"], {"dens": 5})
	_def(WATER, "Water", K_LIQUID, ["#2d6fd1", "#3478dc", "#2a68c6", "#3a80e0"], {"dens": 2, "alpha": 0.72})
	_def(LAVA, "Lava", K_LIQUID, ["#ff6a1a", "#ff8c22", "#f2501a", "#ffa531"], {"dens": 3, "hard": 2, "self": 1, "glow": Vector3(1.0, 0.42, 0.1)})
	_def(WOOD, "Wood", K_SOLID, ["#6b4423", "#5f3c1f", "#774b27", "#633f20"], {"fuel": 130, "ign": 0.035})
	_def(LEAF, "Leaves", K_SOLID, ["#2f7a32", "#37883a", "#29702c", "#3f9442"], {"fuel": 28, "ign": 0.22})
	_def(FIRE, "Fire", K_FIRE, ["#ffd23a", "#ff9a1f", "#ff6a12", "#fff07a"], {"self": 1, "glow": Vector3(1.0, 0.55, 0.18)})
	_def(SMOKE, "Smoke", K_GAS, ["#555555", "#4a4a4a", "#606060", "#525252"], {"alpha": 0.55})
	_def(STEAM, "Steam", K_GAS, ["#d8e4ee", "#c8d6e2", "#e6eef4", "#bfcfdc"], {"alpha": 0.45})
	_def(OBSIDIAN, "Obsidian", K_SOLID, ["#2a1f3d", "#231a33", "#33264a", "#1e1630"], {"hard": 3})
	_def(DEEPSTONE, "Deepstone", K_SOLID, ["#474258", "#3f3a50", "#4f4962", "#3a3549"], {"hard": 2})
	_def(COPPER, "Copper Ore", K_SOLID, ["#c8743a", "#e09a5a", "#6b6f7a", "#b8652e"], {"hard": 1})
	_def(COAL, "Coal", K_SOLID, ["#2b2b2e", "#38383c", "#222224", "#55575e"], {"hard": 1, "fuel": 250, "ign": 0.015})
	_def(EMBER, "Ember Crystal", K_SOLID, ["#ff3d2e", "#ff7a3d", "#c22a20", "#ffb14a"], {"hard": 2, "self": 1, "glow": Vector3(0.9, 0.22, 0.12)})
	_def(FROST, "Frost Shard", K_SOLID, ["#8fe8ff", "#c4f4ff", "#5ccfee", "#e6fcff"], {"hard": 1, "self": 1, "glow": Vector3(0.3, 0.7, 0.95)})
	_def(WISP, "Wisp Ore", K_SOLID, ["#7a8cff", "#a9b6ff", "#5c66e8", "#d4dbff"], {"hard": 2, "self": 1, "glow": Vector3(0.4, 0.45, 1.0)})
	_def(MUD, "Mud", K_LIQUID, ["#2b2318", "#382d20", "#45382a", "#7a6a52"], {"dens": 4})   # dark to light; render.comp gives it a wet sheen
	_def(ICE, "Ice", K_SOLID, ["#a8d8f0", "#bfe4f6", "#96cce8", "#cfeefa"], {"hard": 1, "alpha": 0.85})
	_def(MAGMAROCK, "Magma Rock", K_SOLID, ["#3a1e1a", "#44211a", "#331a16", "#55261a"], {"hard": 3, "glow": Vector3(0.07, 0.015, 0.005)})
	_def(CORE, "Planet Core", K_SOLID, ["#fff2b0", "#ffe066", "#ffd23a", "#ffffff"], {"hard": 4, "self": 1, "glow": Vector3(1.0, 0.85, 0.45)})
	_def(SHROOM, "Glowshroom", K_SOLID, ["#3fe0c8", "#6ff5dc", "#2bb8a6", "#a0fff0"], {"self": 1, "fuel": 40, "ign": 0.08, "glow": Vector3(0.15, 0.85, 0.75)})
	_def(GRAVEL, "Gravel", K_POWDER, ["#7d7a78", "#6a6866", "#8a8784", "#5e5c5a"], {"dens": 6})
	_def(BRICK, "Brick", K_SOLID, ["#9c4a3a", "#a85440", "#8e4234", "#6d625a"], {"hard": 2})
	_def(GLASS, "Glass", K_SOLID, ["#bfe6f0", "#d2f0f8", "#aee0ec", "#e4f8ff"], {"alpha": 0.4})
	_def(SNOW, "Snow", K_POWDER, ["#f0f6ff", "#e4eefa", "#ffffff", "#dae6f4"], {"dens": 3})
	_def(CRYSTAL, "Prism Crystal", K_SOLID, ["#e070ff", "#f2a6ff", "#b84cf0", "#ffd6ff"], {"hard": 1, "self": 1, "glow": Vector3(0.75, 0.3, 0.95)})
	_def(ASH, "Ash", K_POWDER, ["#5a5552", "#4e4a48", "#686260", "#454240"], {"dens": 3})
	_def(PLANK, "Planks", K_SOLID, ["#b07a44", "#a06c3a", "#bc864e", "#966434"], {"fuel": 110, "ign": 0.05})
	_def(CACTUS, "Cactus", K_SOLID, ["#4e8a3a", "#5a9a44", "#447c32", "#66a64e"], {"fuel": 40, "ign": 0.05})
	# debris from collapsing background plants (collected as Wood / Leaves)
	_def(TIMBER, "Timber", K_POWDER, ["#8a5a2e", "#6b4423", "#9c6a38", "#5f3c1f"], {"dens": 4, "fuel": 100, "ign": 0.04})
	_def(LITTER, "Leaf Litter", K_POWDER, ["#3f8a38", "#2f7a32", "#58a048", "#6a5a2a"], {"dens": 1, "fuel": 30, "ign": 0.25})
	# building materials (found in ruins, castles and towns; some can be forged)
	_def(MASONRY, "Stone Block", K_SOLID, ["#8a8c96", "#7c7e88", "#989aa4", "#6e707a"], {"hard": 1})
	_def(SANDSTONE, "Sandstone", K_SOLID, ["#d8b878", "#c8a868", "#e4c88a", "#b8985c"], {"hard": 1})
	_def(TILE, "Roof Tile", K_SOLID, ["#a8483a", "#94402f", "#bc5a44", "#7c3428"], {"hard": 1})
	_def(MOSSBLOCK, "Mossy Block", K_SOLID, ["#6e7a62", "#5e6a54", "#7e8a70", "#526048"], {"hard": 1})
	_def(TREASURE, "Treasure", K_SOLID, ["#e8b830", "#ffd85a", "#b8862a", "#fff2a0"], {"self": 1, "glow": Vector3(0.35, 0.28, 0.08)})
	_def(TORCH, "Torch", K_SOLID, ["#ffd23a", "#ff9a1f", "#ff6a12", "#fff07a"], {"self": 1, "fuel": 60, "ign": 0.02, "glow": Vector3(7.0, 3.6, 1.2)})
	# an opened chest stays behind as a background decoration
	_def(OPENCHEST, "Opened Chest", K_SOLID, ["#6b4423", "#3a2416", "#e8b830", "#1a120c"], {})
	PLACE[OPENCHEST] = 0
	# a one-way platform (landings, walkways): solid to sand and water, but you and the foes
	# jump up through it and can drop down through it (down + jump)
	_def(SCAFFOLD, "Scaffold", K_SOLID, ["#a87442", "#8a5c32", "#bc864e", "#4a2e18"], {"fuel": 90, "ign": 0.05})
	SPAN[SCAFFOLD] = 20
	# props: furniture and town details stamped into the background (props.gd); each cell keeps its
	# palette colour. Harvesting one gives planks.
	_def(DECOR, "Furnishings", K_SOLID, ["#6b4423", "#3a2412", "#8f5f33", "#b07a44"], {"fuel": 80, "ign": 0.05})
	PLACE[DECOR] = 0
	BGDEBRIS[DECOR] = TIMBER
	# doors: walk into one (or press F) to open it, F again to close it; the open door is drawn by the
	# overlay, the closed one is cells that block like a wall
	_def(WOODDOOR, "Door", K_SOLID, ["#5a3a1e", "#7a4e28", "#9a6634", "#b98048"], {"hard": 1, "fuel": 120, "ign": 0.03})
	PLACE[WOODDOOR] = 0
	SPAN[WOODDOOR] = 40
	# the new biomes' plants and ground: giant mushrooms (caps glow faintly), fungal ground, dry grass
	_def(CAP, "Mushroom Cap", K_SOLID, ["#8a2a3a", "#b83a4a", "#d8586a", "#5a1a2a"], {"fuel": 30, "ign": 0.03, "glow": Vector3(0.012, 0.006, 0.016)})
	_def(STALK, "Mushroom Stalk", K_SOLID, ["#cfc4a8", "#b8ab8c", "#e4dcc4", "#9a8e72"], {"fuel": 40, "ign": 0.03})
	_def(MYCELIUM, "Mycelium", K_SOLID, ["#4a3a58", "#5e4a70", "#7a6290", "#3a2c46"], {"glow": Vector3(0.004, 0.002, 0.008)})
	_def(DRYGRASS, "Dry Grass", K_SOLID, ["#9a7a2a", "#c8a040", "#e0c060", "#7a5a1e"], {"fuel": 30, "ign": 0.06})
	_def(ROOT, "Roots", K_SOLID, ["#4a2e18", "#5a3820", "#6a4428", "#3e2614"], {"fuel": 110, "ign": 0.03})
	# star iron: no planet has it; it comes from the hearts of metallic asteroids
	_def(STARIRON, "Star Iron", K_SOLID, ["#8fa4c8", "#c4d4ee", "#64789e", "#eef4ff"], {"hard": 2, "self": 1, "glow": Vector3(0.25, 0.32, 0.5)})
	# each kind of planet's own ore (KIND_ORES says where it lies)
	_def(FIREOPAL, "Fire Opal", K_SOLID, ["#e8582a", "#ff9a3a", "#c8304a", "#ffd070"], {"hard": 2, "self": 1, "glow": Vector3(0.7, 0.25, 0.1)})
	_def(ABYSSPEARL, "Abyss Pearl", K_SOLID, ["#e4ecf4", "#c4d4ec", "#f4dcea", "#9cb8d8"], {"hard": 1, "self": 1, "glow": Vector3(0.3, 0.38, 0.5)})
	_def(SUNSTONE, "Sunstone", K_SOLID, ["#f0b030", "#ffd860", "#c88420", "#fff0a0"], {"hard": 2, "self": 1, "glow": Vector3(0.75, 0.55, 0.12)})
	_def(BOGIRON, "Bog Iron", K_SOLID, ["#7a4a2a", "#9a5e34", "#553220", "#b4743e"], {"hard": 1})
	_def(RIMECRYSTAL, "Rime Crystal", K_SOLID, ["#8ae8ff", "#c8f8ff", "#58bce8", "#ffffff"], {"hard": 2, "self": 1, "glow": Vector3(0.35, 0.75, 1.0)})
	_def(AMBER, "Amber", K_SOLID, ["#d88a20", "#f0a838", "#a86418", "#ffc860"], {"hard": 1, "self": 1, "glow": Vector3(0.35, 0.2, 0.04)})
	_def(SILVER, "Silver Ore", K_SOLID, ["#b8c0c8", "#e0e8f0", "#6e767e", "#ffffff"], {"hard": 2})
	# warded stone: the walls of dungeons, carved with faintly glowing runes. Too hard for any staff
	# but the Core Siphon, so a dungeon is explored through its halls, not dug around.
	_def(RUNESTONE, "Warded Stone", K_SOLID, ["#2c3044", "#353a52", "#3f4560", "#24283a"], {"hard": 4, "glow": Vector3(0.025, 0.045, 0.06)})
	PLACE[TIMBER] = 0
	PLACE[LITTER] = 0
	PLACE[TREASURE] = 0
	# structural strength: how many cells a solid can reach sideways (or hang) from something
	# (a chest reaches further than its 8-cell width, so it never breaks in pieces: any part
	# resting on something holds the whole chest, and with nothing under it, it drops whole)
	# resting on the ground before it breaks loose. Stacking straight up is always fine.
	for kv in [[STONE, 40], [DEEPSTONE, 48], [MAGMAROCK, 56], [OBSIDIAN, 60], [CORE, 63], [DIRT, 10], [GRASS, 10],
			[ICE, 14], [FROST, 24], [WOOD, 16], [LEAF, 4], [PLANK, 12], [BRICK, 24], [GLASS, 6], [CACTUS, 8],
			[SHROOM, 6], [CAP, 6], [STALK, 14], [MYCELIUM, 10], [DRYGRASS, 10], [MASONRY, 28], [MOSSBLOCK, 22], [SANDSTONE, 20], [TILE, 14], [TREASURE, 14], [TORCH, 4],
			[STARIRON, 40], [FIREOPAL, 30], [ABYSSPEARL, 20], [SUNSTONE, 30], [BOGIRON, 24], [RIMECRYSTAL, 26], [AMBER, 18], [SILVER, 40]]:
		SPAN[kv[0]] = kv[1]
	for kv in [[STONE, GRAVEL], [DEEPSTONE, GRAVEL], [MAGMAROCK, GRAVEL], [BRICK, GRAVEL], [MASONRY, GRAVEL],
			[MOSSBLOCK, GRAVEL], [TILE, GRAVEL], [SANDSTONE, SAND], [WOOD, TIMBER], [PLANK, TIMBER], [LEAF, LITTER],
			[CACTUS, LITTER], [ICE, SNOW], [GLASS, AIR], [TORCH, AIR], [MYCELIUM, DIRT], [DRYGRASS, DIRT]]:
		DEBRIS[kv[0]] = kv[1]
	for kv in [[WOOD, TIMBER], [PLANK, TIMBER], [LEAF, LITTER], [CACTUS, LITTER], [SHROOM, LITTER], [CAP, LITTER], [STALK, TIMBER], [DRYGRASS, LITTER], [CRYSTAL, GRAVEL],
			[ICE, SNOW], [EMBER, GRAVEL], [MASONRY, GRAVEL], [MOSSBLOCK, GRAVEL], [BRICK, GRAVEL], [STONE, GRAVEL],
			[SANDSTONE, SAND], [TILE, GRAVEL], [OBSIDIAN, GRAVEL]]:
		BGDEBRIS[kv[0]] = kv[1]
	set_geometry(RS0)

## Lays out the shells for a planet of mean surface radius `rs`. The surface shell gets as many
## columns as fit square cells at the surface (a multiple of 64, so every shell inward halves evenly).
func set_geometry(rs: float) -> void:
	RS0 = rs
	R_TOP = rs + ATMO
	R_SPACE = R_TOP + ORBIT_ROWS
	ROWS = int(R_TOP - R_IN)
	NS = int(round(TAU * rs / 64.0)) * 64
	var top := _even(R_TOP - (rs + SURF_HALF))
	var bot := _even(R_TOP - (rs - SURF_HALF))
	var shells := [[top, bot, NS]]            # [first row, end row, columns]
	# inward: thin shells, each as many columns as make its cells square at its middle, but never more
	# than SEAM_STEP fewer than the shell above (so a seam is a ~2% step, too little to see: where the
	# surface shell's narrowed cells meet them, they drift back to square over several shells); near
	# the heart the radius falls so fast that the step has to be bigger
	var y := bot
	var n := NS
	while y < ROWS:
		var r := R_TOP - float(y)
		var t := maxi(8, _even(r * SEAM_STEP * 0.75))
		if y + t >= ROWS - 8:
			t = ROWS - y
		var cap := maxf(SEAM_STEP, 1.25 * float(t) / r)
		var want := TAU * (r - float(t) * 0.5)
		var nb := _r16(clampf(want, float(n) * (1.0 - cap), float(n) * 0.998))
		if nb >= n:
			nb = n - 16
		shells.append([y, y + t, nb])
		y += t
		n = nb
	# outward, the same up to the orbit band's ceiling
	y = top
	n = NS
	var up := []
	while y > -ORBIT_ROWS:
		var r2 := R_TOP - float(y)
		var t2 := maxi(8, _even(r2 * SEAM_STEP * 0.75))
		if y - t2 <= -ORBIT_ROWS + 8:
			t2 = y + ORBIT_ROWS
		var cap2 := maxf(SEAM_STEP, 1.25 * float(t2) / r2)
		var want2 := TAU * (r2 + float(t2) * 0.5)
		var na := _r16(clampf(want2, float(n) * 1.002, float(n) * (1.0 + cap2)))
		if na <= n:
			na = n + 16
		up.append([y - t2, y, na])
		y -= t2
		n = na
	up.reverse()
	shells = up + shells
	SURF = up.size()
	SH_Y0 = []
	SH_Y1 = []
	SH_N = []
	for sh in shells:
		SH_Y0.append(int(sh[0]))
		SH_Y1.append(int(sh[1]))
		SH_N.append(int(sh[2]))
	NSH = SH_N.size()
	SURF_Y0 = int(SH_Y0[SURF])
	SURF_Y1 = int(SH_Y1[SURF])
	SH_OFF = []
	var off := 0
	for k in NSH:
		SH_OFF.append(off)
		off += (int(SH_Y1[k]) - int(SH_Y0[k])) * int(SH_N[k])
	SH_OFF.append(off)

func _even(v: float) -> int:
	return int(round(v * 0.5)) * 2

func _r16(v: float) -> int:
	return int(round(v / 16.0)) * 16

## the shell holding a row (rows outside the planet's cells: the nearest shell)
func shell_of_row(row: int) -> int:
	var lo := 0
	var hi := NSH - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if row >= int(SH_Y0[mid]):
			lo = mid
		else:
			hi = mid - 1
	return lo

## the shell just outward of shell s, or -1 at the orbit band's ceiling
func shell_above(s: int) -> int:
	return s - 1

## the shell just inward of shell s, or -1 at the heart
func shell_below(s: int) -> int:
	return s + 1 if s + 1 < NSH else -1

var anchor_c := 0             # the surface column stamps and cell lookups near you are centred on

## A stamp's column k (counted from its anchor column `ax`, of an anchor `aw` wide) in row `row`:
## the cell of that row's shell, one cell per blueprint column, centred on the anchor's middle
## (GLSL stampX does the same). In the surface shell it is column ax + k.
func stamp_x(row: int, ax: int, aw: int, k: int) -> int:
	var n: int = SH_N[shell_of_row(row)]
	return posmod(stamp_left(n, ax, aw) + k, n)

## the stamp's left edge (k = 0) in a shell of n columns: the cell nearest half its width left of
## the anchor's middle (GLSL stampLeft); column ax itself in the surface shell
func stamp_left(n: int, ax: int, aw: int) -> int:
	return ((2 * posmod(ax, NS) + aw) * n + (1 - aw) * NS + 2 * NS * aw) / (2 * NS) - aw

## where that cell's middle is
func stamp_pos(row: int, ax: int, aw: int, k: int) -> Vector2:
	var n: int = SH_N[shell_of_row(row)]
	var a := (float(posmod(stamp_left(n, ax, aw) + k, n)) + 0.5) / float(n) * TAU
	return Vector2(cos(a), sin(a)) * (R_TOP - (float(row) + 0.5))

## the cell holding world point p, as (stamp column k from the anchor, row)
func stamp_k(p: Vector2, ax: int, aw: int) -> Vector2i:
	var row := int(floor(R_TOP - p.length()))
	var s := shell_of_row(row)
	var n: int = SH_N[s]
	var x := int(fposmod(atan2(p.y, p.x), TAU) / TAU * float(n))
	var k := posmod(x - stamp_left(n, ax, aw), n)
	if k > n / 2:
		k -= n                                 # (the nearer way round)
	return Vector2i(k, row)

## a surface column's offset from an anchor, the short way round
func k_of(col: int, ax: int) -> int:
	var k := posmod(col - ax, NS)
	return k - NS if k > NS / 2 else k

## the column in shell `to` (next to shell `from`) over column x of shell `from`: the cell whose
## middle is nearest to x's middle (GLSL colTo does the same)
func col_to(from: int, to: int, x: int) -> int:
	return ((2 * x + 1) * int(SH_N[to])) / (2 * int(SH_N[from]))

## The shell table the shaders read (binding 10, common.comp SH_Y0(s) etc.): the planet's geometry,
## then (first row, end row, columns, offset) per shell, and one more entry whose offset is the total. A buffer, not constant
## arrays in the shaders: with ~50 shells, indexing constant arrays per cell made the GPU copy them
## for every cell (the simulation ran ten times slower).
func shell_table() -> PackedByteArray:
	# first the planet's geometry, two vec4 (common.comp R_TOP, RS0, R_SPACE, ROWS; NSH, SURF, NS)
	var head := PackedFloat32Array([R_TOP, RS0, R_SPACE, float(ROWS), float(NSH), float(SURF), float(NS), 0.0])
	var t := PackedInt32Array()
	for k in NSH:
		t.append(int(SH_Y0[k]))
		t.append(int(SH_Y1[k]))
		t.append(int(SH_N[k]))
		t.append(int(SH_OFF[k]))
	for v in [ROWS, ROWS, 0, int(SH_OFF[NSH])]:
		t.append(v)
	var out := head.to_byte_array()
	out.append_array(t.to_byte_array())
	return out

## the index of a cell (row, surface column, placed as a stamp anchored at `ax` / `aw`: by default the
## one near you) in the world buffer as read back (read_world; the background layer follows the
## cells); 0 outside the planet's cells
func raw_idx(row: int, col: int, ax := -1, aw := 1) -> int:
	if row < -ORBIT_ROWS or row >= ROWS:
		return 0
	var s := shell_of_row(row)
	var a := anchor_c if ax < 0 else ax
	return int(SH_OFF[s]) + (row - int(SH_Y0[s])) * int(SH_N[s]) + stamp_x(row, a, aw, k_of(col, a))

## a column of the surface shell (blueprints, the surface table) in shell s
func col_in(s: int, c: int) -> int:
	return ((2 * c + 1) * int(SH_N[s])) / (2 * NS)

## the row of a cell at radius r (negative in the orbit band)
func row_at(r: float) -> int:
	return int(floor(R_TOP - r))

func _def(id: int, nm: String, kind: int, cols: Array, o: Dictionary) -> void:
	KIND[id] = kind
	DENS[id] = int(o.get("dens", 0))
	HARD[id] = int(o.get("hard", 0))
	FUEL[id] = int(o.get("fuel", 0))
	IGN[id] = float(o.get("ign", 0.0))
	SELF[id] = int(o.get("self", 0))
	ALPHA[id] = float(o.get("alpha", 1.0))
	GLOW[id] = o.get("glow", Vector3.ZERO)
	NAMES[id] = nm
	# store the four colours as a ramp from darkest to lightest (used for 16-bit style shading)
	var ramp := []
	for k in 4:
		ramp.append(Color.html(cols[k % cols.size()]))
	ramp.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
	for k in 4:
		var c: Color = ramp[k]
		PAL[id * 4 + k] = (int(c.r8) << 16) | (int(c.g8) << 8) | int(c.b8)
	COLOR[id] = Color.html(cols[0])
	var collect := kind != K_EMPTY and kind != K_GAS and kind != K_FIRE
	COLLECT[id] = 1 if collect else 0
	PLACE[id] = 1 if collect else 0

func total_cells() -> int:
	return SH_OFF[NSH]

## GLSL constants injected in front of every compute shader.
func glsl_prefix() -> String:
	var s := "#version 450\n#define NM %d\n#define TAU 6.28318530718\n" % NM
	# (the planet's own geometry, R_TOP, NS, the shells..., is in the shell table, not here: the
	# shaders are then the same for every planet and a planet of another size needs no new compile)
	s += "#define R_IN %.1f\n#define ORBIT_ROWS %d\n" % [R_IN, ORBIT_ROWS]
	s += "#define CNT %du\n" % CNT
	for cn in ["C_HARD", "C_PLACED", "C_FALL_N", "C_FALL_MAX", "C_CHEST_OPEN", "C_CHEST", "C_CREAK_N", "C_CREAK", "C_FOG", "C_FELL_N", "C_FELL", "C_TREASURE"]:
		s += "#define %s %du\n" % [cn, get(cn)]
	s += "#define K_EMPTY 0u\n#define K_SOLID 1u\n#define K_POWDER 2u\n#define K_LIQUID 3u\n#define K_GAS 4u\n#define K_FIRE 5u\n"
	for id in MAT_NAMES:
		s += "#define M_%s %du\n" % [MAT_NAMES[id], id]
	var dp := []
	for k in 64:
		var c := Color.html(Props.PALETTE[k % Props.PALETTE.size()])
		dp.append("vec3(%.4f, %.4f, %.4f)" % [c.r, c.g, c.b])
	s += "const vec3 DECOR_PAL[64] = vec3[64](%s);\n" % ", ".join(dp)
	s += "const uint KIND[NM] = uint[NM](%s);\n" % _join_u(KIND)
	s += "const uint DENS[NM] = uint[NM](%s);\n" % _join_u(DENS)
	s += "const uint HARD[NM] = uint[NM](%s);\n" % _join_u(HARD)
	s += "const uint FUEL[NM] = uint[NM](%s);\n" % _join_u(FUEL)
	s += "const uint SELFL[NM] = uint[NM](%s);\n" % _join_u(SELF)
	s += "const uint COLLECT[NM] = uint[NM](%s);\n" % _join_u(COLLECT)
	s += "const float IGN[NM] = float[NM](%s);\n" % _join_f(IGN)
	s += "const float ALPHA[NM] = float[NM](%s);\n" % _join_f(ALPHA)
	var g := []
	for v in GLOW:
		g.append("vec3(%.4f,%.4f,%.4f)" % [v.x, v.y, v.z])
	s += "const vec3 GLOW[NM] = vec3[NM](%s);\n" % ", ".join(g)
	s += "const uint PAL[%d] = uint[%d](%s);\n" % [NM * 4, NM * 4, _join_u(PAL)]
	s += "const uint SPAN[NM] = uint[NM](%s);\n" % _join_u(SPAN)
	s += "const uint DEBRIS[NM] = uint[NM](%s);\n" % _join_u(DEBRIS)
	s += "const uint BGDEBRIS[NM] = uint[NM](%s);\n" % _join_u(BGDEBRIS)
	var bh := []
	for k in 32:
		bh.append(str(BEHIND[k]) + "u" if k < BEHIND.size() else "0u")
	s += "const uint BEHIND[32] = uint[32](%s);\n" % ", ".join(bh)
	return s

## The back walls a piece of furniture can stand in front of. Furniture is stamped into the
## background layer, and each of its cells remembers which of these walls is behind it (an index,
## in background bits 22-23 and 28-30), so when the piece burns, is taken whole or broken up for
## planks, the wall behind it is still there: furniture is a layer in front of the wall. 0 is none.
func behind_index(m: int) -> int:
	return maxi(BEHIND.find(m), 0)

func _join_i(a) -> String:
	var p := []
	for v in a:
		p.append(str(int(v)))
	return ", ".join(p)

func _join_u(a) -> String:
	var p := []
	for v in a:
		p.append(str(int(v)) + "u")
	return ", ".join(p)

func _join_f(a) -> String:
	var p := []
	for v in a:
		p.append("%.4f" % float(v))
	return ", ".join(p)

# ---------------------------------------------------------------- biomes ----
# flora: 0 none, 1 trees, 2 pines, 3 cactus, 4 reeds, 5 dead trees, 6 kelp, 7 jungle, 8 acacia, 9 giant mushrooms
# (a planet has at most 8 biomes: their parameters fill P.p[8..23])
# ug (underground): 0 fungal, 1 crystal, 2 ice, 3 ember
# flags: 1 snowcap, 2 pond, 4 lava lake, 8 spawn ok
const BIOMES := {
	"forest": {"name": "Whisperwood", "under": "Glowroot Caverns", "off": 0.0, "amp": 14.0, "top": GRASS, "topD": 1, "sub": DIRT, "subD": 12, "weather": "rain", "flora": 1, "ug": 0, "flags": 8},
	"desert": {"name": "Sunscar Dunes", "under": "Prism Hollows", "off": 14.0, "amp": 9.0, "top": SAND, "topD": 5, "sub": SAND, "subD": 14, "weather": "clear", "flora": 3, "ug": 1, "flags": 8},
	"marsh": {"name": "Murkfen Bog", "under": "Glowroot Caverns", "off": 22.0, "amp": 4.0, "top": MUD, "topD": 3, "sub": DIRT, "subD": 8, "weather": "rain", "flora": 4, "ug": 0, "flags": 2 | 8},
	"mountain": {"name": "Greyspire Peaks", "under": "Frostvein Grottos", "off": -75.0, "amp": 48.0, "top": STONE, "topD": 0, "sub": STONE, "subD": 0, "weather": "snow", "flora": 2, "ug": 2, "flags": 1},
	"tundra": {"name": "Rimefrost Steppe", "under": "Frostvein Grottos", "off": -6.0, "amp": 8.0, "top": SNOW, "topD": 3, "sub": DIRT, "subD": 8, "weather": "snow", "flora": 2, "ug": 2, "flags": 8},
	"ashland": {"name": "Cinderwaste", "under": "Smoldering Vaults", "off": 6.0, "amp": 20.0, "top": ASH, "topD": 4, "sub": STONE, "subD": 0, "weather": "ash", "flora": 5, "ug": 3, "flags": 4},
	"jungle": {"name": "Thornvine Jungle", "under": "Glowroot Caverns", "off": 4.0, "amp": 16.0, "top": GRASS, "topD": 1, "sub": MUD, "subD": 10, "weather": "rain", "flora": 7, "ug": 0, "flags": 2 | 8},
	"savanna": {"name": "Goldgrass Savanna", "under": "Prism Hollows", "off": 8.0, "amp": 6.0, "top": DRYGRASS, "topD": 1, "sub": DIRT, "subD": 10, "weather": "clear", "flora": 8, "ug": 1, "flags": 8},
	"grove": {"name": "Mirecap Grove", "under": "Glowroot Caverns", "off": 2.0, "amp": 11.0, "top": MYCELIUM, "topD": 2, "sub": DIRT, "subD": 10, "weather": "rain", "flora": 9, "ug": 0, "flags": 8},
	"ocean": {"name": "Drowned Shelf", "under": "Abyssal Grottos", "off": 62.0, "amp": 18.0, "top": SAND, "topD": 3, "sub": SAND, "subD": 8, "weather": "rain", "flora": 6, "ug": 0, "flags": 0},
}

## Where the planets hang (world units, the home planet of the system at the centre): space travel
## flies between them. Each further round of five planets lies far off along x. The classic system
## (world_seed 0, the test mode) uses SYSTEM; every game's own system is grown from its seed.
const SYSTEM := [Vector2(0, 0), Vector2(-52000, 18000), Vector2(41000, 47000), Vector2(66000, -24000), Vector2(-30000, -61000)]

func planet_pos(i: int) -> Vector2:
	var rnd := Vector2(float(i / SYSTEM.size()) * 400000.0, 0.0)
	var k := i % SYSTEM.size()
	if world_seed == 0 or k == 0:
		return SYSTEM[k] + rnd if world_seed == 0 else rnd
	# this game's round: the planets spread round the home one, each at its own distance
	var prng := RandomNumberGenerator.new()
	prng.seed = hash([world_seed, i / SYSTEM.size(), 11])
	var a0 := prng.randf() * TAU
	var p := Vector2.ZERO
	for q in range(1, SYSTEM.size()):
		var a := a0 + float(q - 1) / float(SYSTEM.size() - 1) * TAU + prng.randf_range(-0.35, 0.35)
		var d := prng.randf_range(46000.0, 74000.0)
		if q == k:
			p = Vector2(cos(a), sin(a)) * d
	return p + rnd

## ---- the planets ----
## Every planet is half as wide again as the first designs (PLANET_SCALE). The classic system is
## the hand-made table (PLANETS: the test mode plays it, so its checks stay repeatable); every game
## (world_seed, picked when a journey starts and kept in its save) grows a system of its own:
## the first planet always a temperate world to start on, the others of kinds (PLANET_KINDS) in a
## random order, each with a name from parts, its own mix of biomes in an order and widths of its
## own, its size, sea, lava, wealth, sky and place in the system.
const PLANET_SCALE := 1.5
var world_seed := 0
var _planet_cache := {}

## Each planet has its own size: "radius" is its mean surface radius in cells (classic Verdance
## 1304 before PLANET_SCALE).
const PLANETS := [
	{"name": "Verdance", "radius": 1304.0, "desc": "A temperate cradle world of woods, bogs and peaks.", "biomes": ["forest", "jungle", "marsh", "tundra", "mountain", "savanna", "desert", "grove"], "magmaR": 600.0, "sea": -1.0, "rich": 1.0, "lava": 1.0, "sky": Color(1, 1, 1)},
	{"name": "Cindrel", "radius": 1100.0, "desc": "A volcanic world. The mantle is close to the surface, and the air scorches.", "biomes": ["ashland", "mountain", "desert", "ashland", "ashland"], "magmaR": 780.0, "sea": -1.0, "rich": 1.4, "lava": 2.6, "sky": Color(1.25, 0.78, 0.7)},
	{"name": "Thalassa", "radius": 1600.0, "desc": "A water world: scattered islands over drowned shelves, and storms.", "biomes": ["ocean", "forest", "ocean", "marsh", "ocean", "tundra", "ocean"], "magmaR": 580.0, "sea": 26.0, "rich": 1.2, "lava": 0.8, "sky": Color(0.85, 1.05, 1.15)},
	{"name": "Sere", "radius": 1450.0, "desc": "An endless desert world baked under twin suns, swept by dust storms.", "biomes": ["desert", "mountain", "desert", "desert", "ashland"], "magmaR": 640.0, "sea": -1.0, "rich": 1.5, "lava": 1.5, "sky": Color(1.15, 1.0, 0.8)},
	{"name": "Fenhollow", "radius": 950.0, "desc": "A drowned marsh world with deep black lakes under the fog.", "biomes": ["marsh", "grove", "marsh", "tundra", "marsh", "jungle"], "magmaR": 600.0, "sea": 18.0, "rich": 1.6, "lava": 1.0, "sky": Color(0.85, 1.0, 0.85)},
]

## What each kind of planet is like to be on (Defs.climate): how often storms come ("storm", x the
## temperate chance), the wind ("wind", 0-1: gusts that push you in the air and blow snow, sand or
## embers across the view), ground fog ("fog"), scorching air ("heat": hurts under the open sky without
## the Heat Ward or the Cinderheart), lakes that ice over ("freeze"), dust storms instead of rain
## ("dust"), and how many wild creatures roam ("wild"). And how settled it is: "settle" scales how many
## structures it has (towns and the rest), "towns" how many of those are towns and castles, "ruin" how
## many more of them lie in ruins.
## Its hazards (HAZARDS: "cold", "sun", "miasma", "deep", each 0-1) hurt you slowly unless a ward or a
## guardian's relic bears them. "belt": the colour of the storm belt round it while it's out of reach.
const CLIMATES := {
	"temperate": {"settle": 0.5, "towns": 0.6, "belt": Color(0.45, 0.7, 1.0)},
	"volcanic": {"storm": 0.6, "wind": 0.3, "heat": 1.0, "settle": 0.25, "towns": 0.2, "ruin": 0.3, "belt": Color(1.0, 0.45, 0.2)},
	"ocean": {"storm": 1.8, "wind": 0.5, "deep": 1.0, "settle": 0.35, "towns": 0.5, "belt": Color(0.3, 0.85, 0.95)},
	"desert": {"storm": 0.8, "wind": 0.7, "dust": 1.0, "sun": 1.0, "settle": 0.35, "towns": 0.3, "ruin": 0.25, "belt": Color(1.0, 0.8, 0.35)},
	"marsh": {"storm": 1.3, "fog": 1.0, "miasma": 1.0, "settle": 0.3, "towns": 0.3, "ruin": 0.15, "belt": Color(0.55, 0.95, 0.45)},
	"frozen": {"storm": 1.4, "wind": 0.8, "freeze": 1.0, "cold": 1.0, "settle": 0.3, "towns": 0.5, "belt": Color(0.7, 0.9, 1.0)},
	"wild": {"wild": 1.7, "settle": 0.3, "towns": 0.4, "ruin": 0.2, "belt": Color(0.75, 1.0, 0.4)},
	"realm": {"storm": 0.9, "settle": 1.35, "towns": 3.0, "ruin": -0.2, "belt": Color(0.8, 0.55, 1.0)},
}

## The slow hazards of a kind of planet (its CLIMATES key, 0-1), and what bears each: a ward forged at
## the Wisp Forge (its `items` key) or a guardian's relic (keys past the hazard, found on earlier
## worlds). Where: "cold" under the open sky (worse at night and in a blizzard; a fire, torch or lava
## close by warms you), "sun" under the open sky near midday, "miasma" in a marsh world's low fog,
## "deep" 35+ cells under the sea's level (its pearl beds). dmg: health a tick. (Volcanic heat stays with the Heat Ward, which also
## bears the mantle and lava.)
const HAZARDS := {
	"cold": {"ward": "hearth", "relic": "rimefang", "dmg": 0.011, "name": "The cold",
		"msg": "The cold of %s bites under the open sky: forge the Hearth Charm, warm yourself by a fire, or keep to shelter"},
	"sun": {"ward": "sunveil", "relic": "sunidol", "dmg": 0.010, "name": "The sun",
		"msg": "The midday sun of %s scorches you in the open: forge the Sun Veil, or keep to the shade until it's lower"},
	"miasma": {"ward": "fenmask", "relic": "pearl", "dmg": 0.012, "name": "The miasma",
		"msg": "The fog of %s chokes you: forge the Fen Mask, or climb out of the lowlands"},
	"deep": {"ward": "tidecharm", "relic": "tidefin", "dmg": 0.03, "name": "The deep",
		"msg": "The deep sea of %s crushes you: forge the Tide Charm, or stay nearer the surface"},
}

## Sky events (main `_update_sky_events`): now and then something happens in the sky, picked by the
## planet's kind ("kinds": a weight per kind; a kind not listed never has it) and the time of day ("when":
## night, day or any). dur: how long, in ticks [from, to]. "msg" is shown as it begins.
const SKY_EVENTS := {
	"meteors": {"name": "Meteor shower", "when": "night", "dur": [2400, 3600],
		"kinds": {"temperate": 3.0, "desert": 1.5, "wild": 1.0, "realm": 1.0, "frozen": 1.0, "ocean": 0.6, "marsh": 0.6, "volcanic": 0.6},
		"msg": "Shooting stars streak across the sky. Some come down nearby: a meteorite carries a little star iron."},
	"eruption": {"name": "Eruption", "when": "any", "dur": [1500, 2400], "kinds": {"volcanic": 4.0},
		"msg": "The ground shakes: a volcano nearby is erupting. Lava bombs are falling, so take cover."},
	"squall": {"name": "Squall", "when": "any", "dur": [1800, 3000], "kinds": {"ocean": 4.0, "marsh": 0.8, "temperate": 0.5},
		"msg": "A squall sweeps in: gales, and lightning striking the ground."},
	"sandstorm": {"name": "Great sandstorm", "when": "day", "dur": [1800, 3000], "kinds": {"desert": 4.0},
		"msg": "A great sandstorm rolls in. It pushes you about and hides what's far off: wait it out in shelter."},
	"wisps": {"name": "Will-o'-wisps", "when": "night", "dur": [3000, 4200], "kinds": {"marsh": 4.0, "wild": 0.6, "temperate": 0.4},
		"msg": "Will-o'-wisps drift through the dark. Catch one and it leaves its wisp ore behind."},
	"aurora": {"name": "Aurora", "when": "night", "dur": [3600, 5400], "kinds": {"frozen": 4.0, "temperate": 0.5, "realm": 0.4},
		"msg": "An aurora lights the night. Under the open sky your mana comes back twice as fast."},
	"hail": {"name": "Hailstorm", "when": "any", "dur": [1200, 2000], "kinds": {"frozen": 2.0, "temperate": 0.3},
		"msg": "Hail is falling, and it stings in the open: find a roof."},
	"bloodmoon": {"name": "Blood moon", "when": "night", "dur": [4800, 6000], "kinds": {"wild": 4.0, "volcanic": 0.4},
		"msg": "A blood moon rises. The wild things are restless tonight: far more of them are about."},
	"fireworks": {"name": "Fireworks", "when": "night", "dur": [2400, 3600], "kinds": {"realm": 4.0},
		"msg": "Fireworks burst over the kingdom: a festival tonight."},
}
const SKY_EVENT_EVERY := 600       # ticks between chances of one starting
const SKY_EVENT_CHANCE := 0.035    # (about one a day)

## Living towns (scripts/towns.gd): what each kind of shop in a village sells and buys, by its keeper's
## role. "sell": what you can buy ({"name", "price" in coins, and one of "give": {material: how many},
## "potion": draughts, "meal": health now, "rest": a night's sleep (full health, morning), "chart": the
## planet's guardian lairs and dungeons marked on your map}); "buy": material -> [how many, coins paid].
## "ores": the smith also buys every world's own ore, [how many, coins].
const SHOPS := {
	"shop": {"title": "General Store", "sell": [
			{"name": "Healing Draught", "price": 40, "potion": 1},
			{"name": "Torches x6", "price": 6, "give": {TORCH: 6}},
			{"name": "Glass x6", "price": 8, "give": {GLASS: 6}},
			{"name": "Planks x10", "price": 6, "give": {PLANK: 10}}],
		"buy": {WOOD: [8, 2], LEAF: [10, 1], SHROOM: [4, 2], SAND: [12, 1], CACTUS: [6, 1]}},
	"smithy": {"title": "Smithy", "sell": [
			{"name": "Bricks x8", "price": 10, "give": {BRICK: 8}},
			{"name": "Stone Blocks x8", "price": 8, "give": {MASONRY: 8}},
			{"name": "Copper Ore x10", "price": 18, "give": {COPPER: 10}},
			{"name": "Coal x10", "price": 10, "give": {COAL: 10}}],
		"buy": {COPPER: [5, 2], COAL: [5, 2], STONE: [20, 1], DEEPSTONE: [10, 3], OBSIDIAN: [4, 3], EMBER: [2, 3], FROST: [2, 3]}, "ores": [2, 5]},
	"tavern": {"title": "Tavern", "sell": [
			{"name": "Hearty Meal (30 health)", "price": 10, "meal": 30.0},
			{"name": "Rumours: the lairs and dungeons, on your map", "price": 30, "chart": true}],
		"buy": {SHROOM: [4, 3], LEAF: [10, 2], WATER: [20, 2]}},
	"inn": {"title": "Inn", "sell": [
			{"name": "A night's rest (full health, till morning)", "price": 15, "rest": true},
			{"name": "Hearty Meal (30 health)", "price": 12, "meal": 30.0}],
		"buy": {PLANK: [10, 3], WOOD: [8, 2]}},
}
## What a village's shops add on each kind of planet (towns.gd `shop_def` merges it into SHOPS): the ward its
## danger calls for, its own fare, building stock it's known for. Entries as in SHOPS, plus "item": an
## `items` key you then own (a ward), "heat_ward": the Heat Ward, "spell": a spell you then know. On every
## world but the first, the smithy also sells a few of another world's ore ("import", picked by the planet's
## seed) and pays better for this world's own ore ("own_ore": [how many, coins]).
const KIND_TRADE := {
	"volcanic": {"smithy": [{"name": "Heat Ward", "price": 120, "heat_ward": true}, {"name": "Obsidian x6", "price": 12, "give": {OBSIDIAN: 6}}],
		"tavern": [{"name": "Fire-roasted Feast (45 health)", "price": 16, "meal": 45.0}]},
	"ocean": {"shop": [{"name": "Tide Charm", "price": 90, "item": "tidecharm"}], "tavern": [{"name": "Fish Stew (45 health)", "price": 16, "meal": 45.0}]},
	"desert": {"shop": [{"name": "Sun Veil", "price": 90, "item": "sunveil"}, {"name": "Glass x12", "price": 12, "give": {GLASS: 12}}],
		"tavern": [{"name": "Date Cakes (45 health)", "price": 16, "meal": 45.0}]},
	"marsh": {"shop": [{"name": "Fen Mask", "price": 90, "item": "fenmask"}], "tavern": [{"name": "Bog Tea (45 health)", "price": 16, "meal": 45.0}]},
	"frozen": {"shop": [{"name": "Hearth Charm", "price": 90, "item": "hearth"}], "tavern": [{"name": "Hot Cider (45 health)", "price": 16, "meal": 45.0}]},
	"wild": {"shop": [{"name": "Healing Draught x2", "price": 70, "potion": 2}], "tavern": [{"name": "Hunter's Stew (45 health)", "price": 16, "meal": 45.0}]},
	"realm": {"shop": [{"name": "Scroll of Mending", "price": 150, "spell": "mend"}], "smithy": [{"name": "Silver Ore x4", "price": 40, "give": {SILVER: 4}}],
		"inn": [{"name": "A royal suite (full health, till morning)", "price": 25, "rest": true}]},
}
const IMPORT := [3, 45]          # (an imported ore: how many, coins)
const OWN_ORE := [2, 8]          # (what a smith pays for this world's own ore)

## What villagers ask of you (towns.gd `_request`): bring them something ("fetch": [material, how many]),
## thin out a creature that troubles them ("hunt": 2-4 of a creature of the village's biome), or carry a
## letter to a keeper in another village ("deliver"). Rewards in coins, now and then a draught too.
const FETCH := [[WOOD, 20], [LEAF, 30], [COPPER, 12], [COAL, 12], [SHROOM, 6], [STONE, 40], [GLASS, 6], [PLANK, 16], [SAND, 30], [TORCH, 6], [BRICK, 10]]
const MAX_REQUESTS := 3

const FOLK_FIRST := ["Ada", "Bram", "Cora", "Dell", "Edda", "Finn", "Gwen", "Hob", "Ida", "Jory", "Kit", "Lene", "Mags", "Ned",
	"Orla", "Pip", "Rosk", "Sela", "Tam", "Una", "Vik", "Wynn", "Yara", "Zeb", "Bess", "Col", "Dov", "Ena", "Hale", "Moll"]
const FOLK_LAST := ["Miller", "Thatcher", "Brook", "Ashdown", "Fletcher", "Cooper", "Hale", "Reed", "Marsh", "Stone", "Wright", "Farrow", "Tanner", "Shaw"]

## Each kind of planet's own ore: where gen.comp lays it (`hosts`: the ground it forms in, `depth`: cells
## under the surface, `thr`: the vein noise's threshold, higher = rarer; `sea`: only in the seabed, well
## under the sea). The Core Drive that leaves a planet needs some of its ore (`drive_ore`), and so does the
## gear made from it.
const KIND_ORES := {
	"volcanic": {"mat": FIREOPAL, "hosts": [MAGMAROCK, OBSIDIAN, STONE, DEEPSTONE], "depth": [6.0, 900.0], "thr": 0.80},
	"ocean": {"mat": ABYSSPEARL, "hosts": [SAND, GRAVEL, STONE, MUD], "depth": [0.0, 70.0], "thr": 0.77, "sea": true},
	"desert": {"mat": SUNSTONE, "hosts": [SANDSTONE, STONE, SAND, GRAVEL], "depth": [8.0, 320.0], "thr": 0.80},
	"marsh": {"mat": BOGIRON, "hosts": [MUD, DIRT, STONE, MOSSBLOCK], "depth": [3.0, 200.0], "thr": 0.79},
	"frozen": {"mat": RIMECRYSTAL, "hosts": [ICE, STONE, DEEPSTONE, SNOW], "depth": [10.0, 520.0], "thr": 0.80},
	"wild": {"mat": AMBER, "hosts": [DIRT, STONE, MOSSBLOCK, MYCELIUM], "depth": [4.0, 260.0], "thr": 0.80},
	"realm": {"mat": SILVER, "hosts": [STONE, DEEPSTONE, GRAVEL, SANDSTONE], "depth": [20.0, 700.0], "thr": 0.81},
}
const DRIVE_ORE := 12

## Gear forged from each kind of planet's own ore (the Wisp Forge's "Ore Gear"; `gear_recipes`). What a
## piece does is its "mods": stat -> a multiplier, or for the stats in GEAR_ADD an amount added; main
## `gear(stat)` combines what you own, and each stat is used in one place (dig_rate: the excavation brush;
## breath; dmg_taken and knock: `hurt`; mana_cost: `_cast`; lava_dmg; swim; speed; jump; levitate;
## reach: `_reach`; draught_heal: `_drink`; spell_spark / spell_fireball / spell_frost: their impacts;
## undead_dmg: `_hurt_enemy`; calm_wild: foe_ai `think`; light: a light that goes with you). max_hp, max_mana,
## mana_regen and dig_r are applied once, when it's forged (they are saved numbers). A piece shows at the
## forge once you've held some of its ore; the first of each ore shows sooner, locked, saying where it's found.
const GEAR_ADD := ["light", "max_hp", "max_mana", "mana_regen"]
const GEAR := {
	"opal": {"name": "Fire Opal Focus", "ore": FIREOPAL, "cost": {FIREOPAL: 14, OBSIDIAN: 6, GLASS: 4}, "mods": {"dig_rate": 1.5}, "desc": "Your staff digs half again as fast."},
	"opalflame": {"name": "Opal Flamecore", "ore": FIREOPAL, "cost": {FIREOPAL: 10, EMBER: 8, COAL: 10}, "mods": {"spell_fireball": 1.5}, "desc": "Fireball blasts half again as wide and hard."},
	"firetreads": {"name": "Firewalker Treads", "ore": FIREOPAL, "cost": {FIREOPAL: 12, OBSIDIAN: 8, PLANK: 4}, "mods": {"lava_dmg": 0.15}, "desc": "Lava hurts you far less."},
	"pearlcharm": {"name": "Pearl Lung", "ore": ABYSSPEARL, "cost": {ABYSSPEARL: 12, GLASS: 4, COPPER: 6}, "mods": {"breath": 3.0}, "desc": "Your breath lasts three times as long."},
	"pearlfins": {"name": "Pearl Fins", "ore": ABYSSPEARL, "cost": {ABYSSPEARL: 10, LEAF: 10, GLASS: 2}, "mods": {"swim": 1.6}, "desc": "You swim much faster."},
	"pearlvial": {"name": "Pearl Vial", "ore": ABYSSPEARL, "cost": {ABYSSPEARL: 8, GLASS: 6, CRYSTAL: 1}, "mods": {"draught_heal": 1.6}, "desc": "Your Healing Draughts heal 60% more."},
	"sunstone": {"name": "Sunstone Circlet", "ore": SUNSTONE, "cost": {SUNSTONE: 12, COPPER: 8, CRYSTAL: 2}, "mods": {"max_mana": 60.0, "mana_regen": 0.08}, "desc": "+60 max mana, and it comes back faster."},
	"sunlantern": {"name": "Sun Lantern", "ore": SUNSTONE, "cost": {SUNSTONE: 8, GLASS: 6, COPPER: 4}, "mods": {"light": 44.0}, "desc": "A warm light goes with you, in caves and at night."},
	"sunspark": {"name": "Sunspark Focus", "ore": SUNSTONE, "cost": {SUNSTONE: 12, COPPER: 10, WISP: 4}, "mods": {"spell_spark": 1.6}, "desc": "Your Spark Bolts hit 60% harder."},
	"bogmail": {"name": "Bog Iron Mail", "ore": BOGIRON, "cost": {BOGIRON: 16, COPPER: 8, PLANK: 6}, "mods": {"dmg_taken": 0.8}, "desc": "You take a fifth less damage."},
	"bogshield": {"name": "Bog Iron Bulwark", "ore": BOGIRON, "cost": {BOGIRON: 14, PLANK: 6, COPPER: 4}, "mods": {"knock": 0.3}, "desc": "Blows barely knock you about."},
	"bogspade": {"name": "Bog Iron Spade", "ore": BOGIRON, "cost": {BOGIRON: 12, WOOD: 10, COPPER: 4}, "mods": {"reach": 1.4}, "desc": "You dig from further away."},
	"rimelens": {"name": "Rime Lens", "ore": RIMECRYSTAL, "cost": {RIMECRYSTAL: 12, GLASS: 6, WISP: 4}, "mods": {"dig_r": 14.0}, "needs": "wide", "desc": "A still wider excavation (radius 11 to 14). Needs Wide Excavation."},
	"rimeheart": {"name": "Rime Heart", "ore": RIMECRYSTAL, "cost": {RIMECRYSTAL: 10, FROST: 8, SNOW: 12}, "mods": {"spell_frost": 1.6}, "desc": "Frostbite freezes wider and slows foes longer."},
	"rimewings": {"name": "Rime Wings", "ore": RIMECRYSTAL, "cost": {RIMECRYSTAL: 12, GLASS: 4, LEAF: 8}, "mods": {"levitate": 0.5}, "desc": "Levitating costs half the mana."},
	"amber": {"name": "Amber Heart", "ore": AMBER, "cost": {AMBER: 12, SHROOM: 8, LEAF: 10}, "mods": {"max_hp": 40.0}, "desc": "+40 max health."},
	"ambertotem": {"name": "Amber Totem", "ore": AMBER, "cost": {AMBER: 10, WOOD: 12, LEAF: 8}, "mods": {"calm_wild": 2.0}, "desc": "Wild creatures leave you be unless you strike them first."},
	"amberanklet": {"name": "Amber Anklet", "ore": AMBER, "cost": {AMBER: 8, COPPER: 6, LEAF: 6}, "mods": {"speed": 1.15}, "desc": "You run a little faster."},
	"silver": {"name": "Silver Sigil", "ore": SILVER, "cost": {SILVER: 14, CRYSTAL: 2, WISP: 6}, "mods": {"mana_cost": 0.75}, "desc": "Your spells cost a quarter less mana."},
	"silverbane": {"name": "Silverbane Charm", "ore": SILVER, "cost": {SILVER: 10, BRICK: 6, WISP: 4}, "mods": {"undead_dmg": 2.0}, "desc": "Your spells hurt the dead (skeletons, archers and wardens) twice as hard."},
	"silverthread": {"name": "Silver-Thread Cloak", "ore": SILVER, "cost": {SILVER: 12, LEAF: 10, PLANK: 4}, "mods": {"jump": 1.2}, "desc": "You jump higher."},
	# alloys: two worlds' ores bound in star iron ("ore" is then a list; the forge's "Alloys")
	"steamheart": {"name": "Steamheart Focus", "ore": [FIREOPAL, RIMECRYSTAL], "cost": {FIREOPAL: 10, RIMECRYSTAL: 10, STARIRON: 6}, "mods": {"spell_fireball": 1.3, "spell_frost": 1.3, "mana_cost": 0.9}, "desc": "Fire and frost in one stone: Fireball and Frostbite a third stronger, every spell a tenth cheaper."},
	"solarlens": {"name": "Solar Forge Lens", "ore": [FIREOPAL, SUNSTONE], "cost": {FIREOPAL: 10, SUNSTONE: 10, STARIRON: 6}, "mods": {"dig_rate": 1.35, "spell_spark": 1.3, "light": 24.0}, "desc": "Your staff digs faster, your Spark Bolts hit harder, and its tip glows."},
	"diverharness": {"name": "Diver's Harness", "ore": [ABYSSPEARL, BOGIRON], "cost": {ABYSSPEARL: 10, BOGIRON: 10, STARIRON: 6}, "mods": {"swim": 1.4, "breath": 2.0, "knock": 0.6}, "desc": "Swim faster, hold your breath twice as long, and stand firm against blows."},
	"tidefrost": {"name": "Tidefrost Mantle", "ore": [ABYSSPEARL, RIMECRYSTAL], "cost": {ABYSSPEARL: 10, RIMECRYSTAL: 10, STARIRON: 6}, "mods": {"levitate": 0.6, "swim": 1.3, "draught_heal": 1.3}, "desc": "Levitate cheaper, swim faster, and draughts heal more."},
	"sunsilver": {"name": "Sunsilver Crown", "ore": [SUNSTONE, SILVER], "cost": {SUNSTONE: 10, SILVER: 10, STARIRON: 6}, "mods": {"max_mana": 80.0, "mana_cost": 0.85}, "desc": "+80 max mana, and spells cost less."},
	"ironbarkplate": {"name": "Ironwood Plate", "ore": [AMBER, BOGIRON], "cost": {AMBER: 10, BOGIRON: 10, STARIRON: 6}, "mods": {"dmg_taken": 0.75, "max_hp": 30.0}, "desc": "You take a quarter less damage, and +30 max health."},
	"moonsilver": {"name": "Moonsilver Charm", "ore": [SILVER, AMBER], "cost": {SILVER: 10, AMBER: 10, STARIRON: 6}, "mods": {"undead_dmg": 1.6, "speed": 1.1, "jump": 1.1}, "desc": "Hunt the dead harder, and move quicker on your feet."},
	"emberamber": {"name": "Emberamber Heart", "ore": [FIREOPAL, AMBER], "cost": {FIREOPAL: 10, AMBER: 10, STARIRON: 6}, "mods": {"max_hp": 30.0, "lava_dmg": 0.5}, "desc": "+30 max health, and lava hurts you half as much."},
}

## the ores a piece of gear is made from (one, or two for an alloy)
func gear_ores(id: String) -> Array:
	var o = GEAR[id]["ore"]
	return o if typeof(o) == TYPE_ARRAY else [o]

## the forge's recipes for the ore gear (main appends them to its `recipes`)
func gear_recipes() -> Array:
	var out := []
	for id in GEAR:
		var gd: Dictionary = GEAR[id]
		var ores := gear_ores(id)
		out.append({"id": id, "cat": "Ore Gear" if ores.size() == 1 else "Alloys", "name": gd["name"], "cost": gd["cost"], "ore": ores[0], "ores": ores, "desc": gd["desc"], "gear": true})
	return out

## a planet's own ore (KIND_ORES), or -1 (a temperate world has none of its own)
func kind_ore(pl: Dictionary) -> int:
	var ko: Dictionary = KIND_ORES.get(String(pl.get("kind", "temperate")), {})
	return int(ko["mat"]) if not ko.is_empty() else -1

## which kind of planet an ore comes from ("" for none)
func ore_kind(mat: int) -> String:
	for k in KIND_ORES:
		if int(KIND_ORES[k]["mat"]) == mat:
			return k
	return ""

## a planet's climate and settlement (see CLIMATES), every key filled in
func climate(pl: Dictionary) -> Dictionary:
	var out := {"storm": 1.0, "wind": 0.0, "fog": 0.0, "heat": 0.0, "freeze": 0.0, "dust": 0.0, "wild": 1.0,
		"cold": 0.0, "sun": 0.0, "miasma": 0.0, "deep": 0.0, "settle": 1.0, "towns": 1.0, "ruin": 0.0,
		"belt": Color(0.45, 0.7, 1.0)}
	var c: Dictionary = CLIMATES.get(String(pl.get("kind", "temperate")), {})
	for k in c:
		out[k] = c[k]
	return out

## The kinds of planet a system grows (sizes before PLANET_SCALE; magma: the mantle's top as a share
## of the radius; sea: its level in cells under the mean surface, -1 for none; must: biomes it always
## has). A planet with any ocean always has a sea.
const PLANET_KINDS := {
	"temperate": {"pool": {"forest": 3, "jungle": 2, "marsh": 2, "tundra": 2, "mountain": 2, "savanna": 2, "desert": 2, "grove": 2},
		"n": [6, 8], "must": ["forest"], "radius": [1250, 1450], "sea": [-1, -1], "lava": [0.8, 1.2], "rich": [0.9, 1.1],
		"magma": [0.42, 0.5], "sky": Color(1, 1, 1), "adj": ["temperate cradle", "green", "gentle", "living"]},
	"volcanic": {"pool": {"ashland": 6, "mountain": 2, "desert": 1},
		"n": [4, 6], "must": ["ashland", "ashland"], "radius": [1000, 1200], "sea": [-1, -1], "lava": [2.2, 3.0], "rich": [1.3, 1.5],
		"magma": [0.6, 0.72], "sky": Color(1.25, 0.78, 0.7), "adj": ["volcanic", "smouldering", "burning"]},
	"ocean": {"pool": {"ocean": 6, "forest": 1, "marsh": 1, "tundra": 1, "jungle": 1},
		"n": [5, 8], "must": ["ocean", "ocean", "ocean"], "radius": [1450, 1700], "sea": [20, 32], "lava": [0.6, 1.0], "rich": [1.1, 1.3],
		"magma": [0.36, 0.44], "sky": Color(0.85, 1.05, 1.15), "adj": ["water", "storm-swept", "island"]},
	"desert": {"pool": {"desert": 6, "mountain": 2, "savanna": 2, "ashland": 1},
		"n": [4, 6], "must": ["desert", "desert"], "radius": [1300, 1550], "sea": [-1, -1], "lava": [1.2, 1.8], "rich": [1.4, 1.6],
		"magma": [0.42, 0.5], "sky": Color(1.15, 1.0, 0.8), "adj": ["desert", "sun-baked", "parched"]},
	"marsh": {"pool": {"marsh": 5, "grove": 2, "jungle": 2, "tundra": 1},
		"n": [5, 7], "must": ["marsh", "marsh"], "radius": [900, 1100], "sea": [14, 20], "lava": [0.8, 1.2], "rich": [1.5, 1.7],
		"magma": [0.6, 0.66], "sky": Color(0.85, 1.0, 0.85), "adj": ["marsh", "drowned", "misty"]},
	"frozen": {"pool": {"tundra": 6, "mountain": 3, "grove": 1, "forest": 1},
		"n": [4, 7], "must": ["tundra", "tundra"], "radius": [1100, 1400], "sea": [-1, -1], "lava": [0.6, 1.0], "rich": [1.3, 1.5],
		"magma": [0.42, 0.5], "sky": Color(0.9, 0.97, 1.12), "adj": ["frozen", "ice-bound", "wind-scoured"]},
	"wild": {"pool": {"forest": 1, "jungle": 1, "marsh": 1, "tundra": 1, "mountain": 1, "savanna": 1, "desert": 1, "grove": 1, "ashland": 1, "ocean": 1},
		"n": [6, 8], "must": [], "radius": [1200, 1600], "sea": [-1, -1], "lava": [0.9, 1.6], "rich": [1.3, 1.6],
		"magma": [0.42, 0.55], "sky": Color(1.05, 0.95, 1.1), "adj": ["strange", "wild", "patchwork"]},
	# a world of kingdoms: towns, castles and keeps on every good stretch of land (CLIMATES "realm")
	"realm": {"pool": {"forest": 3, "savanna": 3, "mountain": 2, "tundra": 1, "desert": 1, "grove": 1},
		"n": [5, 7], "must": ["forest", "savanna"], "radius": [1300, 1550], "sea": [-1, -1], "lava": [0.8, 1.1], "rich": [1.2, 1.4],
		"magma": [0.42, 0.5], "sky": Color(1.04, 1.0, 0.95), "adj": ["settled", "crowded", "kingdom", "old"]},
}
const PLANET_ORDER := ["volcanic", "ocean", "desert", "marsh", "frozen", "wild", "realm"]
const BIOME_WORDS := {"forest": "woods", "jungle": "jungle", "marsh": "bogs", "tundra": "snowfields", "mountain": "peaks",
	"savanna": "grasslands", "desert": "dunes", "grove": "mushroom groves", "ashland": "ash plains", "ocean": "seas"}
const NAME_A := ["Ver", "Cin", "Thal", "Ser", "Fen", "Ar", "Bel", "Cor", "Dra", "El", "Gal", "Hal", "Ith", "Kel", "Lor", "Mor",
	"Nev", "Or", "Pyr", "Quel", "Ryn", "Syl", "Tor", "Ul", "Vel", "Wyn", "Zar", "Ash", "Brim", "Cal", "Del", "Em", "Fal", "Gry",
	"Hes", "Ka", "Mal", "Nim", "Oss", "Per", "Rhe", "Sol", "Tav", "Va", "Yr"]
const NAME_B := ["", "", "", "a", "e", "i", "o", "an", "el", "or", "is", "en", "ar", "u"]
const NAME_C := ["dance", "drel", "lassa", "re", "hollow", "mere", "holm", "dor", "eth", "ion", "ara", "ox", "une", "ys", "ath",
	"eil", "ant", "ora", "is", "ul", "wyn", "mar", "thas", "vane", "ris", "gard", "phe", "dun", "nor", "lis"]

func make_planet(i: int) -> Dictionary:
	return make_planet_for(world_seed, i)

## planet i of the system grown from ws (0: the classic one); a fresh copy each time
func make_planet_for(ws: int, i: int) -> Dictionary:
	var key := "%d:%d" % [ws, i]
	if not _planet_cache.has(key):
		_planet_cache[key] = _classic_planet(i) if ws == 0 else _grown_planet(ws, i)
	return (_planet_cache[key] as Dictionary).duplicate(true)

func _classic_planet(i: int) -> Dictionary:
	var base: Dictionary = PLANETS[i % PLANETS.size()].duplicate(true)
	var cycle := i / PLANETS.size()
	base["index"] = i
	base["seed"] = 1337 + i * 7919
	base["kind"] = ["temperate", "volcanic", "ocean", "desert", "marsh"][i % PLANETS.size()]
	if cycle > 0:
		base["name"] = "%s %d" % [base["name"], cycle + 1]
	base["rich"] = float(base["rich"]) * (1.0 + cycle * 0.25)
	# depths were set for a planet of Verdance's size: the mantle sits as deep in proportion
	base["radius"] = float(base["radius"]) * PLANET_SCALE
	base["magmaR"] = float(base["magmaR"]) * float(base["radius"]) / 1304.0
	return base

## which kind planet i of the system grown from ws is (the first always temperate)
func _planet_kind(ws: int, i: int) -> String:
	if i == 0:
		return "temperate"
	var krng := RandomNumberGenerator.new()
	krng.seed = hash([ws, i / 5, 3])
	var order := PLANET_ORDER.duplicate()
	for q in range(order.size() - 1, 0, -1):
		var r := krng.randi_range(0, q)
		var t = order[q]
		order[q] = order[r]
		order[r] = t
	if i < 5:
		return order[(i - 1) % order.size()]
	# later rounds: any kind, a temperate one now and then
	return "temperate" if i % 5 == 0 else order[(i % 5 - 1) % order.size()]

func _grown_planet(ws: int, i: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ws, i, 7])
	var kind := _planet_kind(ws, i)
	var kd: Dictionary = PLANET_KINDS[kind]
	var cycle := i / 5
	# biomes: the kind's must-haves, filled from its pool, then shuffled round the planet
	var n := rng.randi_range(int(kd["n"][0]), int(kd["n"][1]))
	var bl: Array = (kd["must"] as Array).duplicate()
	var pool: Dictionary = kd["pool"]
	var tot := 0.0
	for bp_ in pool:
		tot += float(pool[bp_])
	while bl.size() < n:
		var r := rng.randf() * tot
		for bq in pool:
			r -= float(pool[bq])
			if r <= 0.0:
				bl.append(bq)
				break
	for q in range(bl.size() - 1, 0, -1):
		var r2 := rng.randi_range(0, q)
		var t = bl[q]
		bl[q] = bl[r2]
		bl[r2] = t
	# widths: each biome its own share of the way round (0.6 to 1.5 of an even share)
	var ws_ := PackedFloat32Array()
	var wt := 0.0
	for q in bl.size():
		ws_.append(rng.randf_range(0.6, 1.5))
		wt += ws_[q]
	var starts := PackedFloat32Array()
	var acc := 0.0
	for q in bl.size():
		starts.append(acc / wt)
		acc += ws_[q]
	var radius := rng.randf_range(float(kd["radius"][0]), float(kd["radius"][1])) * PLANET_SCALE
	var sea := -1.0
	if float(kd["sea"][0]) >= 0.0:
		sea = rng.randf_range(float(kd["sea"][0]), float(kd["sea"][1]))
	if bl.has("ocean") and sea < 0.0:
		sea = rng.randf_range(20.0, 30.0)
	var sky: Color = kd["sky"]
	sky = Color(sky.r + rng.randf_range(-0.06, 0.06), sky.g + rng.randf_range(-0.06, 0.06), sky.b + rng.randf_range(-0.06, 0.06))
	# a name from parts, never one another planet of the round already has
	var pname := ""
	for tries in 20:
		var nrng := RandomNumberGenerator.new()
		nrng.seed = hash([ws, i, 13, tries])
		pname = String(NAME_A[nrng.randi_range(0, NAME_A.size() - 1)]) + String(NAME_B[nrng.randi_range(0, NAME_B.size() - 1)]) + String(NAME_C[nrng.randi_range(0, NAME_C.size() - 1)])
		var clash := false
		for o in range(i - i % 5, i):
			if String(make_planet_for(ws, o)["name"]).begins_with(pname):
				clash = true
		if not clash:
			break
	if cycle > 0:
		pname = "%s %s" % [pname, ["", "II", "III", "IV", "V", "VI"][mini(cycle, 5)]]
	# what it's like, from its kind and its commonest biomes
	var counts := {}
	for bc in bl:
		counts[bc] = int(counts.get(bc, 0)) + 1
	var common: Array = counts.keys()
	common.sort_custom(func(ca, cb): return int(counts[ca]) > int(counts[cb]))
	var words := []
	for cw in common.slice(0, 3):
		words.append(BIOME_WORDS[cw])
	var list := String(words[0]) if words.size() == 1 else ", ".join(words.slice(0, words.size() - 1)) + " and " + String(words[-1])
	var adjs: Array = kd["adj"]
	var adj := String(adjs[rng.randi_range(0, adjs.size() - 1)])
	var desc := "%s %s world of %s." % ["An" if "aeiou".contains(adj.left(1)) else "A", adj, list]
	# which biomes have a guardian: not all of them; more on the planets further on (2 on the first,
	# 2-4 on the rest of its round, two more each round after)
	var distinct := []
	for bd_ in bl:
		if not distinct.has(bd_) and BOSSES.has(bd_):
			distinct.append(bd_)
	for q2 in range(distinct.size() - 1, 0, -1):
		var r3 := rng.randi_range(0, q2)
		var t3 = distinct[q2]
		distinct[q2] = distinct[r3]
		distinct[r3] = t3
	var ng: int = 2 if i == 0 else int([2, 3, 3, 4, 4][i % 5]) + cycle * 2 + rng.randi_range(-1, 0)
	var guardians: Array = distinct.slice(0, clampi(ng, 1, distinct.size()))
	return {"name": pname, "index": i, "kind": kind, "seed": 1 + posmod(hash([ws, i, 5]), 0xFFFFFE), "guardians": guardians,
		"radius": radius, "desc": desc, "biomes": bl, "starts": starts,
		"magmaR": radius * rng.randf_range(float(kd["magma"][0]), float(kd["magma"][1])), "sea": sea,
		"rich": rng.randf_range(float(kd["rich"][0]), float(kd["rich"][1])) * (1.0 + cycle * 0.25),
		"lava": rng.randf_range(float(kd["lava"][0]), float(kd["lava"][1])), "sky": sky}

## where each of a planet's biomes starts, as a share of the way round (an even share each unless
## the planet says otherwise)
func biome_starts(pl: Dictionary) -> PackedFloat32Array:
	if pl.has("starts"):
		return pl["starts"]
	var st := PackedFloat32Array()
	var n: int = (pl["biomes"] as Array).size()
	for q in n:
		st.append(float(q) / float(n))
	return st

## the middle of a planet's biome b, as an angle
func biome_mid(pl: Dictionary, b: int) -> float:
	var st := biome_starts(pl)
	var hi := st[b + 1] if b + 1 < st.size() else 1.0
	return (st[b] + hi) * 0.5 * TAU

## which of a planet's biomes is at angle a (its index)
func biome_index_at(pl: Dictionary, a: float) -> int:
	var st := biome_starts(pl)
	var u := fposmod(a, TAU) / TAU
	var bi := st.size() - 1
	for q in range(1, st.size()):
		if u < st[q]:
			bi = q - 1
			break
	return bi

# ---------------------------------------------------------------- spells ----
const SPELL_ORDER := ["spark", "conjure", "fireball", "tide", "frost", "quake", "blink", "starfall", "mend"]
const SPELLS := {
	"spark": {"name": "Spark Bolt", "mana": 4.0, "cd": 9, "color": Color(1.0000, 0.9020, 0.5020), "desc": "A quick bolt. Chips terrain, stings foes."},
	"conjure": {"name": "Conjure", "mana": 0.0, "cd": 2, "color": Color(0.7451, 1.0000, 0.7451), "desc": "Place the selected material. Q/E to choose."},
	"fireball": {"name": "Fireball", "mana": 18.0, "cd": 28, "color": Color(1.0000, 0.4706, 0.1569), "desc": "Explodes and ignites anything that burns."},
	"tide": {"name": "Tidecall", "mana": 14.0, "cd": 22, "color": Color(0.3529, 0.6275, 1.0000), "desc": "Bursts into water. Cools lava into obsidian."},
	"frost": {"name": "Frostbite", "mana": 12.0, "cd": 18, "color": Color(0.6667, 0.9412, 1.0000), "desc": "Freezes water and lava. Slows foes."},
	"quake": {"name": "Quake Orb", "mana": 40.0, "cd": 60, "color": Color(0.7843, 0.5490, 1.0000), "desc": "A heavy orb that shatters a huge cavity."},
	"blink": {"name": "Blink", "mana": 22.0, "cd": 30, "color": Color(0.55, 0.95, 1.0), "desc": "Step through space to the cursor."},
	"starfall": {"name": "Starfall", "mana": 45.0, "cd": 70, "color": Color(1.0, 0.82, 0.45), "desc": "A falling star: a huge fiery blast."},
	"mend": {"name": "Mending", "mana": 60.0, "cd": 600, "color": Color(0.55, 1.0, 0.62), "desc": "Knit your wounds: 30 health over a second. Ten seconds to recover."},
}
## Health doesn't come back by itself: Healing Draughts (H to drink; forged, or found in chests) and
## the Mending spell are the only ways back up. Both heal over a moment, not at once.
const POTION_HEAL := 35.0
const POTION_CD := 600         # frames between draughts
const MEND_HEAL := 30.0
const HEAL_RATE := 0.5         # health per frame while healing
const PROJ := {
	"spark": {"speed": 5.5, "g": 0.0, "life": 55, "dmg": 11.0, "light": 18.2},
	"fireball": {"speed": 3.9, "g": 0.035, "life": 140, "dmg": 0.0, "light": 33.8},
	"tide": {"speed": 3.5, "g": 0.07, "life": 120, "dmg": 6.0, "light": 15.6},
	"frost": {"speed": 4.7, "g": 0.0, "life": 80, "dmg": 14.0, "light": 20.8},
	"quake": {"speed": 3.0, "g": 0.09, "life": 160, "dmg": 0.0, "light": 28.6},
	"starfall": {"speed": 3.4, "g": 0.02, "life": 160, "dmg": 0.0, "light": 41.6},
	"efire": {"speed": 2.2, "g": 0.0, "life": 200, "dmg": 12.0, "light": 18.2},
	"arrow": {"speed": 4.4, "g": 0.05, "life": 130, "dmg": 10.0, "light": 0.0},
	# the biome guardians' (scripts/boss_ai.gd): "col" their glow, "splat" what they leave where they land
	"venom": {"speed": 3.0, "g": 0.05, "life": 160, "dmg": 11.0, "light": 14.0, "col": Color(0.55, 1.0, 0.3)},
	"mudball": {"speed": 3.2, "g": 0.08, "life": 160, "dmg": 10.0, "light": 0.0, "col": Color(0.42, 0.32, 0.2), "splat": MUD},
	"ice": {"speed": 3.6, "g": 0.06, "life": 200, "dmg": 12.0, "light": 12.0, "col": Color(0.7, 0.92, 1.0), "splat": SNOW},
	"rock": {"speed": 3.0, "g": 0.09, "life": 220, "dmg": 16.0, "light": 0.0, "col": Color(0.55, 0.52, 0.5), "splat": GRAVEL},
	"sandball": {"speed": 3.4, "g": 0.07, "life": 160, "dmg": 9.0, "light": 0.0, "col": Color(0.93, 0.8, 0.5), "splat": SAND},
	"spore": {"speed": 1.6, "g": 0.0, "life": 260, "dmg": 9.0, "light": 16.0, "col": Color(0.8, 0.5, 1.0), "home": 0.03},
	"surge": {"speed": 3.2, "g": 0.03, "life": 180, "dmg": 11.0, "light": 10.0, "col": Color(0.4, 0.8, 1.0), "splat": WATER},
	# sky events' (main `_update_sky_events`): a meteorite coming down, an eruption's lava bombs
	"meteor": {"speed": 4.5, "g": 0.02, "life": 260, "dmg": 22.0, "light": 44.0, "col": Color(1.0, 0.75, 0.4)},
	"lavabomb": {"speed": 4.0, "g": 0.06, "life": 260, "dmg": 14.0, "light": 26.0, "col": Color(1.0, 0.4, 0.1), "splat": LAVA},
}

# ---------------------------------------------------------------- recipes ---
const RECIPES := [
	{"id": "plank", "cat": "Materials", "name": "Planks x4", "cost": {WOOD: 2}, "give": {PLANK: 4}, "desc": "Flammable building boards."},
	{"id": "brick", "cat": "Materials", "name": "Bricks x4", "cost": {STONE: 3, DIRT: 1}, "give": {BRICK: 4}, "desc": "Tough blocks (staff tier 2 to carve)."},
	{"id": "glass", "cat": "Materials", "name": "Glass x4", "cost": {SAND: 4, COAL: 1}, "give": {GLASS: 4}, "desc": "See-through blocks."},
	{"id": "masonry", "cat": "Materials", "name": "Stone Blocks x4", "cost": {STONE: 4}, "give": {MASONRY: 4}, "desc": "Strong building blocks (span 28)."},
	{"id": "torch", "cat": "Materials", "name": "Torches x4", "cost": {WOOD: 1, COAL: 1}, "give": {TORCH: 4}, "desc": "Light that never goes out."},
	{"id": "tile", "cat": "Materials", "name": "Roof Tiles x4", "cost": {DIRT: 3, COAL: 1}, "give": {TILE: 4}, "desc": "Fired clay, for roofs (build mode)."},
	{"id": "sandstone", "cat": "Materials", "name": "Sandstone x4", "cost": {SAND: 6}, "give": {SANDSTONE: 4}, "desc": "Pressed sand, for desert houses."},
	{"id": "door", "cat": "Materials", "name": "Wooden Door", "cost": {PLANK: 8}, "give": {WOODDOOR: 1}, "desc": "Put it up in build mode (B)."},
	{"id": "obsid", "cat": "Materials", "name": "Obsidian x4", "cost": {LAVA: 4, WATER: 4}, "give": {OBSIDIAN: 4}, "desc": "Quench lava in water."},
	{"id": "fireball", "cat": "Spells", "name": "Fireball", "cost": {COAL: 12, COPPER: 6}, "spell": "fireball"},
	{"id": "tide", "cat": "Spells", "name": "Tidecall", "cost": {WATER: 40, COPPER: 4}, "spell": "tide"},
	{"id": "frost", "cat": "Spells", "name": "Frostbite", "cost": {FROST: 10, SNOW: 10}, "spell": "frost"},
	{"id": "quake", "cat": "Spells", "name": "Quake Orb", "cost": {WISP: 10, STONE: 40, COAL: 10}, "spell": "quake"},
	{"id": "blink", "cat": "Spells", "name": "Blink", "cost": {WISP: 6, CRYSTAL: 6}, "spell": "blink", "scroll": "scroll_blink"},
	{"id": "mend", "cat": "Spells", "name": "Mending", "cost": {WISP: 8, SHROOM: 12, CRYSTAL: 4}, "spell": "mend", "scroll": "scroll_mend"},
	{"id": "potion", "cat": "Potions", "name": "Healing Draught", "cost": {CRYSTAL: 2, SHROOM: 6, GLASS: 2}, "potion": 1, "desc": "Drink with H: 35 health over a moment."},
	{"id": "starfall", "cat": "Spells", "name": "Starfall", "cost": {EMBER: 12, OBSIDIAN: 6, COAL: 10}, "spell": "starfall", "scroll": "scroll_starfall"},
	{"id": "tier2", "cat": "Staff & Body", "name": "Copper Focus", "cost": {COPPER: 20, STONE: 20}, "desc": "Staff tier 2: Deepstone, Ember, Wisp, Brick, Lava."},
	{"id": "wide", "cat": "Staff & Body", "name": "Wide Excavation", "cost": {COPPER: 10, CRYSTAL: 10}, "desc": "Bigger excavation radius (7.5 to 11)."},
	{"id": "vital", "cat": "Staff & Body", "name": "Vital Bloom", "cost": {SHROOM: 16, LEAF: 12}, "desc": "+50 max health."},
	{"id": "mana", "cat": "Staff & Body", "name": "Mana Crystal", "cost": {WISP: 8, CRYSTAL: 8}, "desc": "+70 max mana, faster regeneration."},
	{"id": "ward", "cat": "Staff & Body", "name": "Heat Ward", "cost": {EMBER: 15, FROST: 10, OBSIDIAN: 6}, "desc": "Survive the mantle heat."},
	{"id": "tier3", "cat": "Staff & Body", "name": "Obsidian Focus", "cost": {OBSIDIAN: 15, EMBER: 12, WISP: 6}, "desc": "Staff tier 3: Obsidian and Magma Rock."},
	{"id": "tier4", "cat": "Staff & Body", "name": "Core Siphon", "cost": {OBSIDIAN: 20, WISP: 15}, "desc": "Staff tier 4: harvest the Planet Core. Needs the Ember Heart."},
	# wards: each bears one kind of planet's hazard (HAZARDS); a guardian's relic can do it instead
	{"id": "hearth", "cat": "Wards", "name": "Hearth Charm", "cost": {EMBER: 10, COAL: 16, COPPER: 6}, "desc": "Keeps a frozen world's cold off you under the open sky."},
	{"id": "sunveil", "cat": "Wards", "name": "Sun Veil", "cost": {GLASS: 10, LEAF: 12, COPPER: 6}, "desc": "Shades you from a desert world's midday sun."},
	{"id": "fenmask", "cat": "Wards", "name": "Fen Mask", "cost": {SHROOM: 10, LEAF: 10, GLASS: 4}, "desc": "Lets you breathe a marsh world's choking fog."},
	{"id": "tidecharm", "cat": "Wards", "name": "Tide Charm", "cost": {WISP: 8, GLASS: 6, COPPER: 10}, "desc": "Bears the crushing deep of an ocean world's sea."},
	{"id": "skiff", "cat": "Travel", "name": "Wisp Skiff", "cost": {PLANK: 40, GLASS: 12, WISP: 10, COPPER: 8}, "desc": "A small ship for two. K calls it to you, F to board or step out, hold cast to fly toward the cursor. It flies out into space and back."},
	{"id": "drive", "cat": "Travel", "name": "Core Drive", "cost": {CORE: 30, STARIRON: 12, WISP: 10}, "desc": "This planet's heart, bound in star iron and fitted to your skiff: it carries the skiff through the next planet's storm belt. Needs the Core Siphon (for the Planet Core) and the skiff; star iron is only found in asteroids, and a world with an ore of its own wants some of that too."},
	{"id": "engine", "cat": "Travel", "name": "Star-Iron Engine", "cost": {STARIRON: 10, WISP: 12, COPPER: 16}, "desc": "Your skiff flies half again as fast, in the air and in space. Needs the skiff."},
	{"id": "beam", "cat": "Travel", "name": "Prospector's Beam", "cost": {STARIRON: 6, CRYSTAL: 3, GLASS: 8}, "desc": "Fitted to the skiff: hold dig while you fly it in space to mine asteroids at the cursor from aboard. Needs the skiff."},
]

# ---------------------------------------------------------------- sprites ---
# ---- sprites (drawn as text; tools/sprites.py checks them). The mage is 16x24 with animation
# frames: idle (2), walk (4), jump, fall, levitate (float), cast and hurt, drawn 16 wide (a slim
# cape behind, an arm and hand in front). Enemies have 2 frames each.
const CHEST_W := 12  # treasure chests are 12 x 9 objects (sprites "chest" / "chest_open"), not cells
const CHEST_H := 9
const SPRITES := {
	"chest": {"rows": [
			"gWWIWWWWIWWg",
			"gwwiwwwwiwwg",
			"gWWiWWWWiWWg",
			"gddiddGGiddg",
			"GggggggGgggG",
			"gwwiwwkowwwg",
			"gWWiWWGgiWWg",
			"gwwIwwwwIwwg",
			"oodddddddddo",
		],
		"pal": {"g": "#e8b830", "G": "#fff2a0", "o": "#9a6c24", "w": "#7e4e28", "W": "#9e6634", "d": "#54331a", "i": "#52505c", "I": "#807e8c", "k": "#140c08", "n": "#1e1410", "c": "#ffd85a"}},
	"chest_open": {"rows": [
			"oddddddddddd",
			"gnnnnnnnnnng",
			"gnnnnnnnnnng",
			"gnncnngnncng",
			"GggcgggcgggG",
			"gwwiwwwwiwwg",
			"gWWiWWWWiWWg",
			"gwwIwwwwIwwg",
			"oodddddddddo",
		],
		"pal": {"g": "#e8b830", "G": "#fff2a0", "o": "#9a6c24", "w": "#7e4e28", "W": "#9e6634", "d": "#54331a", "i": "#52505c", "I": "#807e8c", "k": "#140c08", "n": "#1e1410", "c": "#ffd85a"}},
	"mage": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			".....dRRRRRRqq..",
			"....ddRRRRRRqq..",
			"....gGGGGGGGGg..",
			"......KK.kKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_idle2": {"rows": [
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			"....ahhHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			".....dRRRRRRqq..",
			"....ddRRRRRRqq..",
			"....gGGGGGGGGg..",
			"......KK.kKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_blink": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......sssswsn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			".....dRRRRRRqq..",
			"....ddRRRRRRqq..",
			"....gGGGGGGGGg..",
			"......KK.kKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_walk1": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRRqQ..",
			"....ddRRRRRRqq..",
			"...ddrRRRRRRRqq.",
			"...gGGGGGGGGGGg.",
			"...kKK.....kKK..",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_walk2": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRRqQ..",
			".....dRRRRRRqq..",
			"....ddRRRRRRqq..",
			"....gGGGGGGGGg..",
			".....kK...kKK...",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_walk3": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			".....dRRRRRRq...",
			".....dRRRRRRq...",
			".....gGGGGGGg...",
			"......kKKkKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_walk4": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			"....ddRRRRRRqQ..",
			"...ddrRRRRRRRq..",
			"...drRRRRRRRRqq.",
			"...gGGGGGGGGGGg.",
			"...kKK......kK..",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_walk5": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRRqQ..",
			".....dRRRRRRqq..",
			"....ddRRRRRRqq..",
			"....gGGGGGGGGg..",
			".....kKK..kK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_walk6": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			".....dRRRRRRq...",
			".....dRRRRRRq...",
			".....gGGGGGGg...",
			"......kKKKkK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_jump": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			"....ddRRRRRRqq..",
			"....gdRRRRRRqg..",
			".....gGGGGGGg...",
			"......KK.kKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_fall": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			"....ddRbRRRRqq..",
			"...ddrRRRRRRRqQ.",
			"...drRRRRRRRRRq.",
			"..dgRRRRRRRRRRg.",
			"..g.gGGGGGGGGg.g",
			".....kK...kKK...",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_float": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			".....dvWwWwWvRq.",
			".....dRvWWWvRqQ.",
			".....dRRvWvRrqGG",
			".....dbBGJGBBBss",
			"....ddRbRRRRqq..",
			"....drRRRRRRRqQ.",
			"...ddrRRRRRRRRq.",
			"...gGRRRRRRRRGg.",
			"....gGGGGGGGGg..",
			"......kKKkKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_cast": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......ssssesn...",
			"......WssnwWw...",
			"......wwWwwwW...",
			".....dWwWwwWRqq.",
			".....dvWwWwWvRrQ",
			".....dRvWWWvRRGs",
			".....dRRvWvRRr.s",
			".....dbBGJGBBB..",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			".....dRRRRRRqq..",
			"....ddRRRRRRqq..",
			"....gGGGGGGGGg..",
			"......KK.kKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"mage_hurt": {"rows": [
			"................",
			"........hl......",
			".......hHL......",
			".......hHLl.....",
			"......hHHYL.....",
			"......hHHHLl....",
			".....ahHHHHLl...",
			".....gGGGmGGGg..",
			".....ahHHHHHLl..",
			"......SSSSwwS...",
			"......sssSeSn...",
			"......WsnSwww...",
			"......wwWwwwW...",
			".....dWwWwwWRq..",
			"....ddvWwWwWvRq.",
			"....drRvWWWvRqQ.",
			"....drRRvWvRRGss",
			".....dbBGJGBBB..",
			".....dRbRRRRq...",
			".....dRRRRRqQ...",
			".....dRRRRRRqq..",
			"....ddRRRRRRqq..",
			"....gGGGGGGGGg..",
			"......KK.kKK....",
		],
		"pal": {"a": "#1a1146", "h": "#2c1f6e", "H": "#4632a4", "L": "#6a52d0", "l": "#9f88ff", "Y": "#fff1a8", "m": "#46e6f0", "g": "#8a5a1c", "G": "#e2b048", "J": "#fff0b0", "s": "#f2c9a2", "S": "#c88a64", "n": "#e5907e", "e": "#16102c", "w": "#f6f6fc", "W": "#cfcce4", "v": "#8b88aa", "d": "#101746", "r": "#213488", "R": "#3657bd", "q": "#6690f0", "Q": "#a9c5ff", "B": "#4e2c14", "b": "#86552a", "k": "#20120a", "K": "#583619"}},
	"slime": {"rows": [
			"....gggggg....",
			"..gGGGGggggg..",
			".gGGggggggggg.",
			".gGwwgggggwwg.",
			"ggGwkgggggwkgg",
			"gggggggggggggg",
			"gggggddddggggg",
			"ggdgggggggggdg",
			".gddddddddddg.",
			"..dddddddddd..",
		],
		"pal": {"g": "#5fd16a", "G": "#c8ffc8", "w": "#ffffff", "k": "#1d3a20", "d": "#3a9a48"}},
	"slime2": {"rows": [
			"..............",
			"....gggggg....",
			"..gGGGgggggg..",
			".gGwwgggggwwg.",
			"gGgwkgggggwkgg",
			"gggggddddggggg",
			"gggggggggggggg",
			"gdgggggggggggd",
			"gddddddddddddg",
			".dddddddddddd.",
		],
		"pal": {"g": "#5fd16a", "G": "#c8ffc8", "w": "#ffffff", "k": "#1d3a20", "d": "#3a9a48"}},
	"bat1": {"rows": [
			"b....b..b....b",
			"bB..bbbbbb..Bb",
			"bbB.bebbeb.Bbb",
			".bbBbbbbbbBbb.",
			"..bbbddddbbb..",
			".....dddd.....",
			"..............",
			"..............",
			"..............",
		],
		"pal": {"b": "#4a3a5c", "B": "#7a6a90", "e": "#ff4a4a", "d": "#2e2238"}},
	"bat2": {"rows": [
			"..............",
			".....b..b.....",
			"....bbbbbb....",
			"...bbebbebb...",
			".bbbbbbbbbbbb.",
			"bbBbbddddbbBbb",
			"bB...dddd...Bb",
			"b............b",
			"..............",
		],
		"pal": {"b": "#4a3a5c", "B": "#7a6a90", "e": "#ff4a4a", "d": "#2e2238"}},
	"imp": {"rows": [
			"...r......r...",
			"...rr....rr...",
			"....rrrrrr....",
			"...rryrryrr...",
			"W..rRrrrRrr..W",
			"WV.rrrffrrr.VW",
			"WVVrrrrrrrrVVW",
			".WV.rRrrRr.VW.",
			"..W.rrrrrr.W..",
			"....rddddr....",
			"....rr..rr....",
			"....r....r....",
			"...rr....rr...",
		],
		"pal": {"r": "#c23a2a", "R": "#e8684a", "y": "#ffe14a", "f": "#ff9a3a", "d": "#7a1a14", "W": "#5a1a14", "V": "#8a2a1e"}},
	"imp2": {"rows": [
			"...r......r...",
			"...rr....rr...",
			"....rrrrrr....",
			"...rryrryrr...",
			"...rRrrrRrr...",
			"...rrrffrrr...",
			"..VrrrrrrrrV..",
			".VW.rRrrRr.WV.",
			"VW..rrrrrr..WV",
			"W...rddddr...W",
			"....rr..rr....",
			"....r....r....",
			"...rr....rr...",
		],
		"pal": {"r": "#c23a2a", "R": "#e8684a", "y": "#ffe14a", "f": "#ff9a3a", "d": "#7a1a14", "W": "#5a1a14", "V": "#8a2a1e"}},
	"skeleton": {"rows": [
			"....xmmmMx....",
			"...xmmmmMMx...",
			"..xmmmmmmmMx..",
			"..xbbbbbbbbx..",
			"...bDebbDeb...",
			"...bbbBbbbb...",
			"....bDbDbB....",
			".....bBBb.....",
			"......bb......",
			"...bbbbbbbb..S",
			"..b.bbbbbb.b.S",
			"..b...bb...b.S",
			"..b.bBbbBb.b.S",
			"..b...bb...bES",
			"..B..bBBb..uuS",
			"..b...bb.....s",
			"....tTbbTt....",
			"....tTtTtt....",
			"....bt..tb....",
			"....bB..Bb....",
			"...bb....bb...",
			"...bB....Bb...",
		],
		"pal": {"b": "#e2dccb", "B": "#a8a08c", "D": "#6e6858", "e": "#ff6a3a", "E": "#ffd27a", "m": "#7a7e8c", "M": "#a6aab8", "x": "#4a4e5a", "t": "#5a3a2a", "T": "#7a5236", "s": "#9a8e7a", "S": "#c9bfa8", "u": "#6a5a44"}},
	"skeleton2": {"rows": [
			"....xmmmMx....",
			"...xmmmmMMx...",
			"..xmmmmmmmMx..",
			"..xbbbbbbbbx..",
			"...bDebbDeb...",
			"...bbbBbbbb...",
			"....bDbDbB....",
			".....bBBb.....",
			"......bb......",
			"...bbbbbbbb..S",
			"..b.bbbbbb.b.S",
			"..b...bb...b.S",
			"..b.bBbbBb.b.S",
			"..b...bb...bES",
			"..B..bBBb..uuS",
			"..b...bb.....s",
			"....tTttTt...s",
			"....ttTtTt....",
			"....bb...bb...",
			"....bB...Bb...",
			"...bb.....bb..",
			"..bB.......Bb.",
		],
		"pal": {"b": "#e2dccb", "B": "#a8a08c", "D": "#6e6858", "e": "#ff6a3a", "E": "#ffd27a", "m": "#7a7e8c", "M": "#a6aab8", "x": "#4a4e5a", "t": "#5a3a2a", "T": "#7a5236", "s": "#9a8e7a", "S": "#c9bfa8", "u": "#6a5a44"}},
	"archer": {"rows": [
			"....xmmmMx....",
			"...xmmmmMMx...",
			"..xmmmmmmmMx..",
			"..xbbbbbbbbx..",
			"...bDebbDeb...",
			"...bbbBbbbb...",
			"....bDbDbB....",
			".....bBBb...w.",
			"......bb....lw",
			"...bbbbbbbb.lw",
			"..b.bbbbbb.blw",
			"..b...bb...bhw",
			"..b.bBbbBb.blw",
			"..b...bb...blw",
			"..B..bBBb..blw",
			"..b...bb....w.",
			"....tTbbTt....",
			"....tTtTtt....",
			"....bt..tb....",
			"....bB..Bb....",
			"...bb....bb...",
			"...bB....Bb...",
		],
		"pal": {"b": "#e2dccb", "B": "#a8a08c", "D": "#6e6858", "e": "#7aff6a", "E": "#ffd27a", "m": "#3e5a36", "M": "#5f7d4c", "x": "#26341f", "t": "#4a3a2a", "T": "#6a5236", "w": "#8a5a2e", "l": "#d8d0b8", "h": "#a8a08c"}},
	"archer2": {"rows": [
			"....xmmmMx....",
			"...xmmmmMMx...",
			"..xmmmmmmmMx..",
			"..xbbbbbbbbx..",
			"...bDebbDeb...",
			"...bbbBbbbb...",
			"....bDbDbB....",
			".....bBBb...w.",
			"......bb....lw",
			"...bbbbbbbb.lw",
			"..b.bbbbbb.blw",
			"..b...bb...bhw",
			"..b.bBbbBb.blw",
			"..b...bb...blw",
			"..B..bBBb..blw",
			"..b...bb....w.",
			"....tTttTt....",
			"....ttTtTt....",
			"....bb...bb...",
			"....bB...Bb...",
			"...bb.....bb..",
			"..bB.......Bb.",
		],
		"pal": {"b": "#e2dccb", "B": "#a8a08c", "D": "#6e6858", "e": "#7aff6a", "E": "#ffd27a", "m": "#3e5a36", "M": "#5f7d4c", "x": "#26341f", "t": "#4a3a2a", "T": "#6a5236", "w": "#8a5a2e", "l": "#d8d0b8", "h": "#a8a08c"}},
	"mimic": {"rows": [
			"...wwwwwwwwwwww...",
			"..wWWWWWWWWWWWWw..",
			".wwgwwwwwwwwwwgww.",
			".wwgwwwwkkwwwwgww.",
			"ggggggggkkgggggggg",
			"wwgwwwwwwwwwwwgwww",
			"wwgwwwwwwwwwwwgwww",
			"wwgwwwwwwwwwwwgwww",
			".wwwwwwwwwwwwwwww.",
		],
		"pal": {"w": "#7a4a24", "W": "#a06a38", "g": "#ffd85a", "t": "#ffffff", "r": "#c0283a", "k": "#3a2416", "e": "#ffe14a"}},
	"mimic2": {"rows": [
			"...wwwwwwwwwwww...",
			"..wWWWWWWWWWWWWw..",
			".wwgwweewwweewgww.",
			"gtgtgtgtgtgtgtgtgg",
			"r................r",
			"r.......rr.......r",
			"rtgtgtgtgtgtgtgtgr",
			"wwgwwwwwkkwwwwgwww",
			".wwwwwwwwwwwwwwww.",
		],
		"pal": {"w": "#7a4a24", "W": "#a06a38", "g": "#ffd85a", "t": "#ffffff", "r": "#c0283a", "k": "#3a2416", "e": "#ffe14a"}},
	"golem": {"rows": [
			".................y......................",
			"........................................",
			"........y........llLLL..................",
			"...............llllllLLO........c.......",
			"............c.LLLLLLOOOOo...............",
			".............ooOooOooOooO...............",
			".............LleeLLLLeeOOk..............",
			".....l.......LlyLLLLOOyOok.......llL....",
			"..llllllL.....LLLLOOOOOoo.L....lllllLO..",
			".lllllLlLOOl.lOLccccccookLL...llllllLOo.",
			".llllLLLLLollllkmmmmmmoklLOOOLllllLLLOo.",
			"lLllLLLmOOollllllkkokkLLLlLOlLlllLLLOOok",
			".LlLLLLcOOollllllllllcLOOLLLLLlLLLOOOOok",
			".OLLLOOOmoollllllllLmmcLooLLLOLLmOOOooo.",
			".OOlllOoookllmllllLcLLLOOokmOOOmclllLok.",
			"..lllLLOollLllmcLLLLmLOOOckLOOkollllLO..",
			"..llLLOOLllLlllLcLLOcOOOcokOOOOollLLLO..",
			"..lLOOooLllLOLLLLOOcycOoookOOOOoLLOOOo..",
			"..OOOOokLlLlOOLLOLcywycookOOOOOokLOOok..",
			"....koLLLlLLLOoOmcywwwycmOOOOOook.ll....",
			"...lllLOLLLlLLLkoocywyckOOOOoookklllLO..",
			"..LlLLLoOOLLcLLLcOLcycOOOoOooooklllLLo..",
			"..llLOOoOOOLcLLOcOOOcOOOcooooookllLLOO..",
			"..OLOOoo.OOLLLmcOOOOmOOOocmoookkOLLOoo..",
			"..OOOoo.O.OOomOOOOOOooooooomokk..OOoo...",
			"....lLO...okoooOOoOOOoooooookk....LL....",
			"..llllLO...lkkoooooooooookLkk...llllL...",
			"..llllLL..lllllkkkkokkkkkklllO..lLllLO..",
			".cmlllLLOlllllLLOk..kk.llllLLLOlllllLLO.",
			"llmlLLLLOklllLLLo......lllLLLLlllllLLOLk",
			"LllLLLLOOklLLLLOO......llLLLOOLllLLLOOOk",
			"LlLLLOOOOkLLLLOOO......llLLLOOLLLLLcOOok",
			".LLLOOOookLLOOOoo......OLLOOOoLLLLcOOoo.",
			".OLOOOookOLllLLok......OLllLLokOOOcoooo.",
			"..kLOLoL..lllllO........lllllOk.kLoLoL..",
			".....k...llllLLOk.......lllLLL....k.....",
			".........LlLLLLOo......LllLLLOk.........",
			".........LLLLOOOo......LLLLOOOo.........",
			".........OLLLOook......LLLOOOok.........",
			".........OOOOOoo........OOOooo..........",
			"........OOOOOoooooo...OOOOOoooooo.......",
			"........ocoocoocooo...ocoocoocooo.......",
		],
		"pal": {"k": "#1c1418", "o": "#3e2f32", "O": "#5c4744", "L": "#7e6560", "l": "#a58a7c", "m": "#8a2a12", "c": "#e2521c", "y": "#ffb53a", "w": "#fff2b0", "e": "#ffe14a", "d": "#5a2a18"}},
	"golem2": {"rows": [
			".......y................................",
			"........................................",
			".......................c................",
			".................llLLL..................",
			"......c........llllllLLO................",
			"..............LLLLLLOOOOo...............",
			".............ooOooOooOooO...............",
			".............LleeLLLLeeOOk..............",
			".....l.......LlyLLLLOOyOok.......llL....",
			"..llllllL.....LLLLOOOOOoo.L....lllllLO..",
			".lllllLlLOOl.lOLccccccookLL...llllllLOo.",
			".llllLLLLLollllkmmmmmmoklLOOOLllllLLLOo.",
			"lLllLLLmOOollllllkkokkLLLlLOlLlllLLLOOok",
			".LlLLLLcOOollllllllllcLOOLLLLLlLLLOOOOok",
			".OLLLOOOmoollllllllLmmcLooLLLOLLmOOOooo.",
			".OOlllLoookllmllllLcLLLOOokmOOOmclllLok.",
			"...llLLLollLllmcLLLLmLOOOckLOOkolllLLL..",
			"..LllLLOLllLlllLcLLOcOOOcokOOOOoLlLLOO..",
			"..LLLOOOLllLOLLLLOOcycOoookOOOOoLLLOOo..",
			"...LOOooLlLlOOLLOLcywycookOOOOOokLOOoo..",
			"....kokLLlLLLOoOmcywwwycmOOOOOook.kll...",
			"....lllLOLLlLLLkoocywyckOOOOoookk.lllLO.",
			"...LlLLLoOLLcLLLcOLcycOOOoOooookklllLLo.",
			"...llLOOoOOLcLLOcOOOcOOOcooooook.llLLOO.",
			"...OLOOooOOLLLmcOOOOmOOOocmoookk.OLLOoo.",
			"...OOOooO.OOomOOOOOOooooooomokk...OOoo..",
			"......lL.lokoooOOoOOOoooooookk.....lLL..",
			"....lllLLLllkkoooooooooookLkk.....llllL.",
			"....llllLLlLLLLkkkkokkkkkklllO...llLllLO",
			"...cmlllLLOLLOOOok..kk.llllLLLO..lllllLL",
			"..llmlLLLLOklLOoo......lllLLLLo.lllllLLO",
			"..LllLLLLOOkllOOk......llLLLOOokLllLLLOO",
			"..LlLLLOOOOklLLL.......llLLOOOo.LLLLLcOO",
			"...LLLOOOooklLLOk......OLLOOooo.LLLLcOOo",
			"...OLOOOookLLLOOo......OLLllLO...OOOcooo",
			"....kLOLoLLLLOOOo.......lllLLLo...kLoLoL",
			".......k.OOOOoook......lllLLOOo.....k...",
			"........OOOOOoooooo....LlLLLOOo.........",
			"........ocoocoocooo....OLLLOOOk.........",
			".......................OOOOooo..........",
			"......................OOOOOoooooo.......",
			"......................ocoocoocooo.......",
		],
		"pal": {"k": "#1c1418", "o": "#3e2f32", "O": "#5c4744", "L": "#7e6560", "l": "#a58a7c", "m": "#8a2a12", "c": "#e2521c", "y": "#ffb53a", "w": "#fff2b0", "e": "#ffe14a", "d": "#5a2a18"}},
	"golem3": {"rows": [
			"........................................",
			"........................................",
			"............c...........................",
			".................llLLL..................",
			"...............llllllLLO................",
			"..............LLLLLLOOOOo.........c.....",
			"....y........ooOooOooOooO...............",
			".............LleeLLLLeeOOk..............",
			".....l.......LlyLLLLOOyOok.......llL....",
			"..llllllL.....LLLLOOOOOoo.L....lllllLO..",
			".lllllLlLOOl.lOLccccccookLL...llllllLOo.",
			".llllLLLLLollllkmmmmmmoklLOOOLllllLLLOo.",
			"lLllLLLmOOollllllkkokkLLLlLOlLlllLLLOOok",
			".LlLLLLcOOollllllllllcLOOLLLLLlLLLOOOOok",
			".OLLLOOOmoollllllllLmmcLooLLLOLLmOOOooo.",
			".OlllLLoookllmllllLcLLLOOokmOOOmlllLLok.",
			"..lllLLoollLllmcLLLLmLOOOckLOOkolllLLk..",
			".LlLLLOkLllLlllLcLLOcOOOcokOOOOllLLOOo..",
			".LLLLOooLllLOLLLLOOcycOoookOOOOoLLOOoo..",
			"..OOOooLLlLlOOLLOLcywycookOOOOOoOLOoo...",
			"...lkkLLLlLLLOoOmcywwwycmOOOOOookllk....",
			"..lllL.LLLLlLLLkoocywyckOOOOoooklllLO...",
			".LlLLLoOOOLLcLLLcOLcycOOOoOoooolllLLo...",
			".llLLOo.OOOLcLLOcOOOcOOOcoooooollLLOO...",
			".OLLOOo..OOLLLmcOOOOmOOOocmoookOLLOoo...",
			"..LOook.O.OOomOOOOOOooooooomokk.OOoo....",
			"..lLL.....okoooOOoOOOoooooookkO.lLk.....",
			".lllLO.....lkkoooooooooookLkkLolllLO....",
			"llllLL....llllLkkkkokkkkkkLLOOlLllLO....",
			"mlllLLO..lllllLLOk..kk.llLLOOlllllLLO...",
			"mlLLLLOk.LlllLLLo......OLLOOlllllLLOLk..",
			"lLLLLOOk.llLLLLOO......OLLllLllLLLOOOk..",
			"LLLOOOOk.lLLLOOOo.......lllLLLLLLcOOok..",
			"LLOOOook.LLLlLOoo......lllLLLLLLcOOoo...",
			"LOOOook..OllllOOk......LlLLLOOOOcoooo...",
			"kLOLoL...llllLLL.......OLLLOOOkLoLoL....",
			"...k.....llllLLOk......OOOOooo..k.......",
			".........LlLLLOOo.....OOOOOoooooo.......",
			".........LLLLOOOo.....ocoocoocooo.......",
			".........OOOOoook.......................",
			"........OOOOOoooooo.....................",
			"........ocoocoocooo.....................",
		],
		"pal": {"k": "#1c1418", "o": "#3e2f32", "O": "#5c4744", "L": "#7e6560", "l": "#a58a7c", "m": "#8a2a12", "c": "#e2521c", "y": "#ffb53a", "w": "#fff2b0", "e": "#ffe14a", "d": "#5a2a18"}},
	"golem_leap": {"rows": [
			".....llllLL..y...llLLL......lllllLL.....",
			"....lllllLLO...llllllLLO....llllccLO....",
			"...lllllLLLOk.LLLLLLOOOOo..llllLLLLOk...",
			"...LllLLLLccoooOooOooOooO..LlLlLLLOOk...",
			"...LlLLLOOOOkLleeLLLLeeOOk.LLLLLLOOOk...",
			"..lOLLLOOOookLlyLLLLOOyOok.LLLOOOOOokk..",
			".lLOOOOOOOok..LLLLOOOOOoo.L.OOOOOOooOko.",
			".lOLkoLoLoLl.lOLccccccookLL..kLoLoLkoOo.",
			"lLlkOOokOOollllkmmmmmmoklLOOlLlkkkookOok",
			".LlLLLLcOOollllllkkokkLLLlLOOLlLLLOOOOok",
			".OLLLOOOmoollllllllllcLOOLLLLOLLmOOOooo.",
			".OOOOOooookllllllllLmmcLooLLLOOmcOOOook.",
			"...oOOooollllmllllLcLLLOOokmOOkoOooook..",
			".....klLLllLllmcLLLLmLOOOckLOOOok.kk....",
			".......lLllLlllLcLLOcOOOcokOOOOok.......",
			"......LLLllLOLLLLOOcycOoookOOOOok.......",
			".......LLlLlOOLLOLcywycookOOOOOokk......",
			"......LLLlLLLOoOmcywwwycmOOOOOook.......",
			".......LLLLlLLLkoocywyckOOOOoookk.......",
			".......OOOLLcLLLcOLcycOOOoOooookk.......",
			"........OOOLcLLOcOOOcOOOcooooook........",
			".........OOLLLmcOOOOmOOOocmoookk........",
			"........O.OOomOOOOOOooooooomokk.........",
			"..........okoooOOoOOOoooooookk..........",
			"............kkoooooooooook.kk...........",
			"...............kkkkokkkkkk..............",
			"...........ll....k..kk....llL...........",
			"..........lllllO........lllllO..........",
			".........llllLLLo......llllLLLO.........",
			".........LllLLLOo......LllLLOOo.........",
			".........llLLOOOok.....lLLLLOOok........",
			".........LLLOOOoo......OLLLOOoo.........",
			".........OllllOo.......OLllllLk.........",
			".........llllLLO........lllLLLo.........",
			".........llLLLOO.......lllLLOOOk........",
			"........LLLLOOOo........LLLOOOO.........",
			".........OLOOOoo........OLOOooo.........",
			".......OOOOOOooooo.....OOOOooooooo......",
			".......ocoocoocooo.....ocoocoocooo......",
			"........................................",
			"........................................",
			"........................................",
		],
		"pal": {"k": "#1c1418", "o": "#3e2f32", "O": "#5c4744", "L": "#7e6560", "l": "#a58a7c", "m": "#8a2a12", "c": "#e2521c", "y": "#ffb53a", "w": "#fff2b0", "e": "#ffe14a", "d": "#5a2a18"}},
	"golem_sleep": {"rows": [
			"........................................",
			"........................................",
			"........................................",
			"........................................",
			"........................................",
			"........................................",
			".................llLLL..................",
			"...............llllllLLO................",
			"..............LLLLLLOOOOo...............",
			".....l.......ooOooOooOooO........llL....",
			"..llllllL....LlddLLLLddOOkL....lllllLO..",
			".lllllLlLOOl.LllLLLLOOOOokL...llllllLOo.",
			".llllLLLLLolllLLLLOOOOOooLOOOLllllLLLOo.",
			"lLllLLLmOOolllOLddddddooklLOlLlllLLLOOok",
			".LlLLLLcOOollllkoooooookOLLLLLlLLLOOOOok",
			".OLLLOOOmoollllllkkokkcLooLLLOLLmOOOooo.",
			".OOllLooooklldllllLcLLLOOokdOOOmcOlLLok.",
			"...llLLOollLllddLLLLoLOOOdkLOOkollllLo..",
			"..llLLOOLllLlllLdLLOdOOOdokOOOOollLLOO..",
			"..lLLLOoLllLOLLLLOOdmdOoookOOOOollLOOo..",
			"..OLOOooLlLlOOLLOLdmcmdookOOOOOoOLOOoo..",
			"...oookLLlLLLOoOodmcccmdoOOOOOookoook...",
			".......LLLLlLLLkoodmcmdkOOOOoookk.ll....",
			"...lllLOOOLLcLLLcOLdmdOOOoOooookklllLO..",
			"..LlLLLoOOOLcLLOcOOOdOOOdooooooklllLLo..",
			"..llLOOo.OOLLLddOOOOoOOOoddoookkllLLOO..",
			"..OLOOooO.OOodOOOOOOooooooodokk.OLLOoo..",
			"..OOOoo...okoooOOoOOOoooooookk...OOoo...",
			".....k.....lkkoooooooooookLkk......k....",
			"...lllL...lllllkkkkokkkkkklllO...lllO...",
			"..lllLLo.llllLLLOk..kk.llllLLLO.llllLo..",
			"..llllLL.lllLLLLo......lllLLLLo.lLllLO..",
			".cmlllLLOllLLLOOO......lLLLLOOolllllLLO.",
			"llmlLLLLOkLLLOOOo......LLLLOOOlllllLLOLk",
			"LllLLLLOOkLllLLok......OLllLLoLllLLLOOOk",
			"LlLLLOOOOklllLLO.......OlllLLOLLLLLcOOok",
			".LLLOOOookllLLLOk......lllLLLLLLLLcOOoo.",
			".OLOOOookLlLLOOOo......LlLLOLOoOOOcoooo.",
			"..kLOLoL.LLLLOOok......LLLLOOok.kLoLoL..",
			".....k....LLOOoo........LOOOook...k.....",
			"........OOOOOoooooo...OOOOOoooooo.......",
			"........ocoocoocooo...ocoocoocooo.......",
		],
		"pal": {"k": "#1c1418", "o": "#3e2f32", "O": "#5c4744", "L": "#7e6560", "l": "#a58a7c", "m": "#8a2a12", "c": "#e2521c", "y": "#ffb53a", "w": "#fff2b0", "e": "#ffe14a", "d": "#5a2a18"}},
}

const MAGE_ANCHORS := {
	"mage": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_idle2": {"hat": [8, 0], "hand": [14, 17], "chin": [9, 15], "neck": [5, 11]},
	"mage_blink": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_walk1": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_walk2": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_walk3": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_walk4": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_walk5": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_walk6": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_jump": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_fall": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_float": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
	"mage_cast": {"hat": [8, 1], "hand": [15, 16], "chin": [9, 16], "neck": [5, 12]},
	"mage_hurt": {"hat": [8, 1], "hand": [14, 17], "chin": [9, 16], "neck": [5, 12]},
}

## Foes. "ai" picks and tunes the shared behaviours in scripts/foe_ai.gd:
##   sight: how far it notices you (with a clear line of sight; close by, or when you cast nearby, it
##     notices anyway), and it hunts where it last saw you for a few seconds, rallying foes near it
##   doors: it opens doors to get at you
##   leap: a crouch, then a jump aimed to land on you    melee: a wind-up, then a lunge with its blade
##   ranged: a wind-up, then a shot that leads you (and allows for the drop)    keep: the distance it holds
##   swoop: a hover, then a dive straight at you, then it climbs away    blink: it vanishes when you close in
## Every attack is telegraphed: the foe glows (overlay.gd) through its wind-up.
const ENEMY := {
	"slime": {"w": 12.0, "h": 9.0, "hp": 22.0, "dmg": 6.0, "fly": false, "spr": "slime", "drops": [[WISP, 1, 0.35], [WATER, 4, 1.0]],
		"ai": {"sight": 150.0, "leap": {"range": 90.0, "windup": 22, "speed": 3.2, "v": 5.6, "cd": 80}}},
	"bat": {"w": 11.0, "h": 6.0, "hp": 16.0, "dmg": 7.0, "fly": true, "spr": "bat1", "drops": [[COAL, 2, 0.8], [SHROOM, 2, 0.5]],
		"ai": {"sight": 160.0, "swoop": {"range": 100.0, "windup": 16, "speed": 3.8, "time": 30, "cd": 100}}},
	"imp": {"w": 9.0, "h": 12.0, "hp": 34.0, "dmg": 11.0, "fly": true, "spr": "imp", "drops": [[EMBER, 3, 1.0], [OBSIDIAN, 2, 0.4]],
		"ai": {"sight": 210.0, "ranged": {"proj": "efire", "range": 200.0, "windup": 26, "cd": 130, "n": 1, "lead": 0.8},
			"burst": {"n": 3, "spread": 0.16, "below": 0.5}, "blink": {"near": 34.0, "cd": 220}}},
	"skeleton": {"w": 7.0, "h": 17.0, "hp": 40.0, "dmg": 6.0, "fly": false, "spr": "skeleton", "step": 2, "drops": [[TORCH, 2, 0.5], [CRYSTAL, 2, 0.4], [WISP, 1, 0.25]],
		"ai": {"sight": 180.0, "doors": true, "melee": {"reach": 22.0, "windup": 16, "lunge": 3.4, "dmg": 14.0, "cd": 50}}},
	"archer": {"w": 7.0, "h": 17.0, "hp": 30.0, "dmg": 5.0, "fly": false, "spr": "archer", "step": 2, "drops": [[TORCH, 1, 0.4], [CRYSTAL, 1, 0.35], [WISP, 1, 0.3], [WOOD, 3, 0.5]],
		"ai": {"sight": 230.0, "doors": true, "keep": [55.0, 140.0], "ranged": {"proj": "arrow", "range": 220.0, "windup": 38, "cd": 85, "n": 1, "lead": 1.0}}},
	"mimic": {"w": 16.0, "h": 9.0, "hp": 90.0, "dmg": 14.0, "fly": false, "spr": "mimic", "step": 2, "drops": [[WISP, 4, 1.0], [EMBER, 4, 0.8], [CRYSTAL, 4, 0.8]],
		"ai": {"sight": 160.0, "leap": {"range": 110.0, "windup": 14, "speed": 3.8, "v": 5.0, "cd": 45}}},
	"golem": {"w": 28.0, "h": 40.0, "hp": 900.0, "dmg": 18.0, "fly": false, "spr": "golem", "boss": true, "drops": []},
}

# ------------------------------------------------------------- guardians ---
## Each biome's guardian, waiting in its lair (buildings.gd `_lair`) over the relic it guards. Bodies
## are grown from parts by scripts/boss_art.gd (`body`: a plan and its features), behaviour is put
## together from moves by scripts/boss_ai.gd (`moves`: what it does, in turn; `rage`: added below half
## health), `go`: how it gets around (walk, hop, fly, slither, burrow).
## Body plans: beast (four legs; antlers, tusks, mane, spikes, tail), bird, toad, fungus, serpent.
const BOSSES := {
	"forest": {"name": "Bramblehorn", "title": "the Thicket King", "lair": "Bramblehorn's Glade", "col": Color(0.55, 0.85, 0.35),
		"body": {"plan": "beast", "len": 40, "tall": 18, "leg": 17, "head": 10, "neck": 9, "base": "#6a4e33", "belly": "#9c8160",
			"accent": "#5e9a34", "dark": "#2e2216", "eye": "#ffd23a", "skin": "moss", "antlers": 4, "tail": "short"},
		"w": 30.0, "h": 34.0, "hp": 620.0, "dmg": 14.0, "go": "walk", "speed": 0.95,
		"moves": {"charge": {}, "erupt": {"mat": WOOD, "col": Color(0.45, 0.32, 0.18)}, "slam": {}}, "rage": {"roar": {}},
		"relic": "ironbark", "loot": {WOOD: 40, LEAF: 20, MOSSBLOCK: 20}, "wall": MOSSBLOCK, "floor": MASONRY, "trim": WOOD},
	"jungle": {"name": "Ssirra", "title": "the Canopy Serpent", "lair": "Ssirra's Coil", "col": Color(0.45, 1.0, 0.45),
		"body": {"plan": "serpent", "segs": 11, "rad": 6.5, "base": "#2f8a3c", "belly": "#d4c75a", "accent": "#d84a2a", "dark": "#173f1d", "eye": "#ffe14a"},
		"w": 14.0, "h": 12.0, "hp": 520.0, "dmg": 13.0, "go": "slither", "speed": 2.4, "fly": true,
		"moves": {"spit": {"proj": "venom", "n": 3, "spread": 0.22}, "dive": {}}, "rage": {"spit2": {"proj": "venom", "n": 5, "spread": 0.18}},
		"relic": "coil", "loot": {WOOD: 30, CRYSTAL: 6, MOSSBLOCK: 10}, "wall": MOSSBLOCK, "floor": MASONRY, "trim": TIMBER},
	"marsh": {"name": "The Bog Mother", "title": "Queen of the Mire", "lair": "The Bog Mother's Pool", "col": Color(0.6, 0.8, 0.4),
		"body": {"plan": "toad", "len": 38, "tall": 24, "base": "#5a6e34", "belly": "#b8b070", "accent": "#8a5a2a", "dark": "#26301a", "eye": "#ffb21a", "skin": "warts"},
		"w": 32.0, "h": 24.0, "hp": 600.0, "dmg": 13.0, "go": "hop", "speed": 1.0,
		"moves": {"slam": {"far": true}, "spit": {"proj": "mudball", "n": 4, "spread": 0.2}, "summon": {"type": "slime", "n": 2, "max": 4}},
		"rage": {"summon2": {"type": "slime", "n": 3, "max": 5}},
		"relic": "pearl", "loot": {MUD: 40, WATER: 30, SHROOM: 8}, "wall": MASONRY, "floor": MOSSBLOCK, "trim": WOOD},
	"tundra": {"name": "Rimefang", "title": "the Winter Wolf", "lair": "Rimefang's Den", "col": Color(0.7, 0.9, 1.0),
		"body": {"plan": "beast", "len": 38, "tall": 16, "leg": 16, "head": 10, "neck": 5, "base": "#d8e2ea", "belly": "#f4f8fc",
			"accent": "#8fe8ff", "dark": "#5a6a7a", "eye": "#5cf0ff", "skin": "fur", "spikes": 6, "tail": "long", "ears": true},
		"w": 30.0, "h": 28.0, "hp": 580.0, "dmg": 15.0, "go": "walk", "speed": 1.2,
		"moves": {"charge": {}, "rain": {"proj": "ice", "n": 7}, "spit": {"proj": "ice", "n": 3, "spread": 0.12}}, "rage": {"roar": {}},
		"relic": "rimefang", "loot": {ICE: 30, FROST: 12, SNOW: 30}, "wall": STONE, "floor": MASONRY, "trim": ICE, "glow": FROST},
	"mountain": {"name": "Skarn", "title": "the Crag Roc", "lair": "Skarn's Eyrie", "col": Color(0.85, 0.75, 0.6),
		"body": {"plan": "bird", "len": 30, "span": 40, "base": "#6a5442", "belly": "#b49a78", "accent": "#e8b23a", "dark": "#2e241c", "eye": "#ff5a2a", "skin": "fur"},
		"w": 26.0, "h": 20.0, "hp": 560.0, "dmg": 14.0, "go": "fly", "speed": 2.6, "fly": true,
		"moves": {"dive": {}, "rain": {"proj": "rock", "n": 5}, "gust": {}}, "rage": {"dive2": {}},
		"relic": "roc", "loot": {STONE: 40, COPPER: 15, DEEPSTONE: 10}, "wall": STONE, "floor": MASONRY, "trim": TIMBER},
	"savanna": {"name": "Sunmane", "title": "Lord of the Grasslands", "lair": "Sunmane's Rock", "col": Color(1.0, 0.8, 0.35),
		"body": {"plan": "beast", "len": 38, "tall": 17, "leg": 16, "head": 10, "neck": 5, "base": "#c8923e", "belly": "#e8c88a",
			"accent": "#8a4a1a", "dark": "#4a2c12", "eye": "#ffe85a", "skin": "fur", "mane": true, "tail": "tuft"},
		"w": 30.0, "h": 28.0, "hp": 600.0, "dmg": 15.0, "go": "walk", "speed": 1.15,
		"moves": {"slam": {"far": true}, "charge": {}, "roar": {}}, "rage": {"charge2": {}},
		"relic": "lionheart", "loot": {DRYGRASS: 30, SANDSTONE: 20, COPPER: 10}, "wall": SANDSTONE, "floor": SANDSTONE, "trim": TIMBER},
	"desert": {"name": "The Dune Wyrm", "title": "Devourer of Caravans", "lair": "The Wyrm's Hollow", "col": Color(1.0, 0.75, 0.4),
		"body": {"plan": "serpent", "segs": 13, "rad": 8.5, "base": "#b8864a", "belly": "#e8cf96", "accent": "#7a3a1a", "dark": "#4e3218", "eye": "#ff3a1a", "teeth": true},
		"w": 18.0, "h": 16.0, "hp": 640.0, "dmg": 16.0, "go": "burrow", "speed": 2.0, "fly": true,
		"moves": {"breach": {"proj": "sandball", "n": 5, "spread": 0.3}}, "rage": {},
		"relic": "sunidol", "loot": {SAND: 40, SANDSTONE: 20, CRYSTAL: 8}, "wall": SANDSTONE, "floor": SANDSTONE, "trim": TILE},
	"grove": {"name": "The Mycelord", "title": "Heart of the Rot", "lair": "The Mycelord's Hollow", "col": Color(0.85, 0.55, 1.0),
		"body": {"plan": "fungus", "len": 30, "tall": 36, "base": "#7a4aa0", "belly": "#e8d4c0", "accent": "#3fe0c8", "dark": "#2e1c3e", "eye": "#3fffe0", "skin": "spots"},
		"w": 26.0, "h": 34.0, "hp": 600.0, "dmg": 12.0, "go": "walk", "speed": 0.6,
		"moves": {"cloud": {}, "erupt": {"mat": MYCELIUM, "col": Color(0.6, 0.4, 0.8)}, "spit": {"proj": "spore", "n": 3, "spread": 0.5}},
		"rage": {"cloud2": {}},
		"relic": "lantern", "loot": {SHROOM: 20, MYCELIUM: 30, CRYSTAL: 6}, "wall": MASONRY, "floor": MYCELIUM, "trim": MYCELIUM, "glow": SHROOM},
	# the other planets' biomes (Cindrel and Sere's ashlands, Thalassa's drowned shelves)
	"ashland": {"name": "Kragmor", "title": "the Cinder Beast", "lair": "Kragmor's Caldera", "col": Color(1.0, 0.5, 0.2),
		"body": {"plan": "beast", "len": 40, "tall": 17, "leg": 15, "head": 11, "neck": 6, "base": "#3a2420", "belly": "#7a3a22",
			"accent": "#ff7a2a", "dark": "#160a08", "eye": "#ffd23a", "skin": "scales", "spikes": 8, "horns": true, "tail": "long"},
		"w": 30.0, "h": 30.0, "hp": 640.0, "dmg": 16.0, "go": "walk", "speed": 1.05,
		"moves": {"charge": {}, "erupt": {"mat": MAGMAROCK, "col": Color(1.0, 0.45, 0.1)}, "spit": {"proj": "efire", "n": 3, "spread": 0.2}},
		"rage": {"rain": {"proj": "efire", "n": 6}},
		"relic": "cinderheart", "loot": {EMBER: 12, OBSIDIAN: 20, MAGMAROCK: 30}, "wall": OBSIDIAN, "floor": MAGMAROCK, "trim": EMBER, "glow": EMBER},
	# ("wet": its lair is an arena on the seabed, full of water; "swim": it keeps to the water)
	"ocean": {"name": "Thalassor", "title": "the Tide Wyrm", "lair": "The Drowned Sanctum", "col": Color(0.35, 0.85, 1.0),
		"body": {"plan": "serpent", "segs": 13, "rad": 7.5, "base": "#1f5a7a", "belly": "#9ae0e8", "accent": "#3affd8", "dark": "#0c2a3a", "eye": "#e8ff7a", "teeth": true},
		"w": 16.0, "h": 14.0, "hp": 620.0, "dmg": 14.0, "go": "slither", "speed": 2.2, "fly": true, "swim": true, "wet": true,
		"moves": {"dive": {}, "spit": {"proj": "surge", "n": 4, "spread": 0.2}, "summon": {"type": "c_reefeel", "n": 2, "max": 3}},
		"rage": {"gust": {}, "spit2": {"proj": "surge", "n": 6, "spread": 0.16}},
		"relic": "tidefin", "loot": {SAND: 30, CRYSTAL: 10, WATER: 40}, "wall": MASONRY, "floor": SANDSTONE, "trim": CRYSTAL, "glow": CRYSTAL},
}

## The relics the guardians keep (items[id]; main.gd applies them where they matter).
const RELICS := {
	"ironbark": {"name": "Ironbark Shell", "desc": "You take a quarter less damage."},
	"coil": {"name": "Serpent's Coil", "desc": "You move a fifth faster."},
	"pearl": {"name": "Mire Pearl", "desc": "You breathe under water, and a marsh world's choking fog can't harm you."},
	"cinderheart": {"name": "Cinderheart", "desc": "Fire can't burn you, lava hurts far less, and a volcanic world's air can't scorch you."},
	"tidefin": {"name": "Tidefin", "desc": "You swim as fast as you walk, and the deep sea can't crush you."},
	"rimefang": {"name": "Rimefang's Tooth", "desc": "Your Spark Bolts chill what they hit, and a frozen world's cold can't touch you."},
	"roc": {"name": "Roc Feather", "desc": "Levitating costs half the mana."},
	"lionheart": {"name": "Lionheart", "desc": "+40 max health."},
	"sunidol": {"name": "Sun Idol", "desc": "Your spells hit a quarter harder, and a desert world's sun can't scorch you."},
	"lantern": {"name": "Glowcap Lantern", "desc": "A soft light goes with you."},
}

# ------------------------------------------------------------- creatures ---
## The wild creatures of each biome and each depth underground: small cousins of the guardians, grown
## from the same body plans (scripts/boss_art.gd) and moved by the same brain (scripts/boss_ai.gd),
## but without a lair: they wander until they see or hear you (foe_ai.gd `think`), hunt while they
## remember you, then wander again. `where`: biome names, or "cave1" (the upper caves), "cave2" (the
## middle depths), "cave3" (the deep, near the magma). `pack`: how many come together. `pace`: how
## widely it circles you (1 = a guardian's). `cd`: frames between its moves.
const CREATURES := {
	"boar": {"name": "Thornback Boar", "where": ["forest"], "w": 18.0, "h": 13.0, "hp": 40.0, "dmg": 8.0, "go": "walk", "speed": 1.1,
		"body": {"plan": "beast", "len": 20, "tall": 11, "leg": 7, "head": 7, "neck": 2, "base": "#5e4430", "belly": "#8e7258", "accent": "#3a2a1c",
			"dark": "#22180f", "eye": "#ffb03a", "skin": "fur", "tusks": true, "tail": "short", "ears": true},
		"moves": {"charge": {"v": 3.4}}, "drops": [[WOOD, 3, 0.5], [LEAF, 3, 0.4]]},
	"greenwing": {"name": "Greenwing", "where": ["forest", "jungle"], "w": 10.0, "h": 8.0, "hp": 18.0, "dmg": 6.0, "go": "fly", "speed": 1.7,
		"body": {"plan": "bird", "len": 11, "span": 14, "base": "#3e7a3a", "belly": "#b8d88a", "accent": "#e8c83a", "dark": "#1a301a", "eye": "#ff4a2a", "skin": "fur"},
		"moves": {"dive": {"v": 3.8}}, "drops": [[LEAF, 3, 0.6]]},
	"viper": {"name": "Vine Viper", "where": ["jungle"], "w": 7.0, "h": 6.0, "hp": 26.0, "dmg": 7.0, "go": "slither", "speed": 1.7,
		"body": {"plan": "serpent", "segs": 7, "rad": 2.8, "base": "#2a9a4a", "belly": "#e8e070", "accent": "#e83a2a", "dark": "#123a1a", "eye": "#ffe14a"},
		"moves": {"spit": {"proj": "venom", "n": 1, "spread": 0.1}, "dive": {"v": 3.6}}, "drops": [[WOOD, 2, 0.5], [CRYSTAL, 1, 0.15]]},
	"redfrog": {"name": "Ember Frog", "where": ["jungle"], "w": 11.0, "h": 8.0, "hp": 22.0, "dmg": 6.0, "go": "hop", "speed": 0.9,
		"body": {"plan": "toad", "len": 13, "tall": 8, "base": "#d8402a", "belly": "#f0d070", "accent": "#2a3ad8", "dark": "#401a10", "eye": "#1a1a1a", "skin": "spots"},
		"moves": {"spit": {"proj": "venom", "n": 2, "spread": 0.2}}, "drops": [[SHROOM, 1, 0.3], [CRYSTAL, 1, 0.1]]},
	"bogtoad": {"name": "Bog Toad", "where": ["marsh"], "w": 14.0, "h": 10.0, "hp": 34.0, "dmg": 7.0, "go": "hop", "speed": 0.9,
		"body": {"plan": "toad", "len": 16, "tall": 10, "base": "#5a6a34", "belly": "#b0a868", "accent": "#7a5a2a", "dark": "#26301a", "eye": "#ffb21a", "skin": "warts"},
		"moves": {"slam": {}, "spit": {"proj": "mudball", "n": 2, "spread": 0.2}}, "drops": [[MUD, 4, 0.8], [SHROOM, 1, 0.3]]},
	"leech": {"name": "Mire Leech", "where": ["marsh"], "w": 6.0, "h": 5.0, "hp": 18.0, "dmg": 6.0, "go": "slither", "speed": 1.4,
		"body": {"plan": "serpent", "segs": 6, "rad": 2.4, "base": "#3a3028", "belly": "#8a5a4a", "accent": "#c83a3a", "dark": "#1a1410", "eye": "#ff6a3a"},
		"moves": {"dive": {"v": 3.4}}, "drops": [[MUD, 3, 0.6], [WATER, 3, 0.6]]},
	"frostwolf": {"name": "Frost Wolf", "where": ["tundra"], "pack": 3, "w": 17.0, "h": 13.0, "hp": 30.0, "dmg": 8.0, "go": "walk", "speed": 1.5,
		"body": {"plan": "beast", "len": 20, "tall": 9, "leg": 9, "head": 7, "neck": 3, "base": "#c8d4de", "belly": "#eef4f8", "accent": "#8fe8ff",
			"dark": "#4a5a6a", "eye": "#5cf0ff", "skin": "fur", "tail": "long", "ears": true},
		"moves": {"charge": {"v": 3.8}}, "drops": [[SNOW, 4, 0.6], [FROST, 1, 0.3]]},
	"snowowl": {"name": "Snow Owl", "where": ["tundra"], "w": 10.0, "h": 8.0, "hp": 20.0, "dmg": 6.0, "go": "fly", "speed": 1.6,
		"body": {"plan": "bird", "len": 11, "span": 14, "base": "#e8eef4", "belly": "#ffffff", "accent": "#e8b03a", "dark": "#6a7a8a", "eye": "#ffd23a", "skin": "fur"},
		"moves": {"dive": {"v": 3.8}}, "drops": [[SNOW, 3, 0.6], [FROST, 1, 0.2]]},
	"craghawk": {"name": "Crag Hawk", "where": ["mountain"], "w": 11.0, "h": 8.0, "hp": 22.0, "dmg": 7.0, "go": "fly", "speed": 1.9,
		"body": {"plan": "bird", "len": 12, "span": 16, "base": "#7a5a3a", "belly": "#c8a878", "accent": "#e8c040", "dark": "#2e2018", "eye": "#ffea3a", "skin": "fur"},
		"moves": {"dive": {"v": 4.2}}, "drops": [[STONE, 3, 0.5], [COPPER, 1, 0.25]]},
	"ram": {"name": "Rock Ram", "where": ["mountain"], "w": 18.0, "h": 14.0, "hp": 46.0, "dmg": 10.0, "go": "walk", "speed": 1.0,
		"body": {"plan": "beast", "len": 20, "tall": 12, "leg": 9, "head": 7, "neck": 3, "base": "#8a8478", "belly": "#d8d0c0", "accent": "#5a5248",
			"dark": "#2a2622", "eye": "#ffb03a", "skin": "fur", "horns": true, "tail": "short"},
		"moves": {"charge": {"v": 3.6}, "slam": {}}, "drops": [[STONE, 4, 0.6], [COPPER, 1, 0.3]]},
	"hyena": {"name": "Dust Hyena", "where": ["savanna"], "pack": 3, "w": 16.0, "h": 12.0, "hp": 28.0, "dmg": 7.0, "go": "walk", "speed": 1.5,
		"body": {"plan": "beast", "len": 19, "tall": 9, "leg": 9, "head": 7, "neck": 3, "base": "#b89058", "belly": "#e0c898", "accent": "#5a3a1a",
			"dark": "#3a2410", "eye": "#ffd25a", "skin": "spots", "tail": "tuft", "ears": true},
		"moves": {"charge": {"v": 3.8}}, "drops": [[DRYGRASS, 4, 0.6], [COPPER, 1, 0.2]]},
	"vulture": {"name": "Vulture", "where": ["savanna", "desert"], "w": 11.0, "h": 8.0, "hp": 22.0, "dmg": 6.0, "go": "fly", "speed": 1.6,
		"body": {"plan": "bird", "len": 12, "span": 18, "base": "#3a2e28", "belly": "#d8b8a0", "accent": "#e8a0a0", "dark": "#1a1410", "eye": "#ffd23a", "skin": "fur"},
		"moves": {"dive": {"v": 3.6}}, "drops": [[DRYGRASS, 2, 0.5]]},
	"sandviper": {"name": "Sand Viper", "where": ["desert"], "w": 8.0, "h": 7.0, "hp": 30.0, "dmg": 9.0, "go": "burrow", "speed": 1.4,
		"body": {"plan": "serpent", "segs": 8, "rad": 3.2, "base": "#c8985a", "belly": "#f0dca8", "accent": "#8a4a1a", "dark": "#5a3a1a", "eye": "#ff3a1a", "teeth": true},
		"moves": {"breach": {"proj": "sandball", "n": 2, "spread": 0.3}}, "drops": [[SAND, 4, 0.8], [CRYSTAL, 1, 0.15]]},
	"jackal": {"name": "Desert Jackal", "where": ["desert"], "pack": 2, "w": 15.0, "h": 12.0, "hp": 24.0, "dmg": 7.0, "go": "walk", "speed": 1.5,
		"body": {"plan": "beast", "len": 18, "tall": 8, "leg": 9, "head": 7, "neck": 3, "base": "#d0a868", "belly": "#f0dcb0", "accent": "#7a5a2a",
			"dark": "#4a3418", "eye": "#ffd23a", "skin": "fur", "tail": "long", "ears": true},
		"moves": {"charge": {"v": 3.8}}, "drops": [[SAND, 3, 0.5], [SANDSTONE, 2, 0.3]]},
	"sporepuff": {"name": "Spore Puff", "where": ["grove"], "w": 12.0, "h": 13.0, "hp": 30.0, "dmg": 5.0, "go": "walk", "speed": 0.45,
		"body": {"plan": "fungus", "len": 13, "tall": 14, "base": "#a05ac8", "belly": "#f0e0d0", "accent": "#e8a0ff", "dark": "#3a1c4a", "eye": "#3fffe0", "skin": "spots"},
		"moves": {"cloud": {"r": 12.0, "t": 200}}, "drops": [[SHROOM, 2, 0.7], [MYCELIUM, 3, 0.5]]},
	"mycelite": {"name": "Mycelite", "where": ["grove"], "w": 9.0, "h": 10.0, "hp": 20.0, "dmg": 5.0, "go": "hop", "speed": 0.8,
		"body": {"plan": "fungus", "len": 10, "tall": 11, "base": "#4a8ac8", "belly": "#e8e0d8", "accent": "#3fe0c8", "dark": "#1a2a4a", "eye": "#ffea5a", "skin": "spots"},
		"moves": {"spit": {"proj": "spore", "n": 1, "spread": 0.1}}, "drops": [[SHROOM, 2, 0.6]]},
	"crawler": {"name": "Cave Crawler", "where": ["cave1"], "w": 17.0, "h": 9.0, "hp": 30.0, "dmg": 8.0, "go": "walk", "speed": 1.2,
		"body": {"plan": "beast", "len": 19, "tall": 7, "leg": 5, "head": 6, "neck": 1, "base": "#4a4a52", "belly": "#7a7a84", "accent": "#7affd0",
			"dark": "#1a1a20", "eye": "#7affd0", "skin": "scales", "spikes": 4, "tail": "long"},
		"moves": {"charge": {"v": 3.4}}, "drops": [[STONE, 3, 0.5], [COAL, 2, 0.4], [COPPER, 1, 0.3]]},
	"glowworm": {"name": "Glow Worm", "where": ["cave2"], "w": 7.0, "h": 6.0, "hp": 30.0, "dmg": 7.0, "go": "slither", "speed": 1.5,
		"body": {"plan": "serpent", "segs": 9, "rad": 3.0, "base": "#2a4a5a", "belly": "#9affe8", "accent": "#3fffe0", "dark": "#0e1a22", "eye": "#c8ffff"},
		"moves": {"spit": {"proj": "spore", "n": 1, "spread": 0.1}}, "drops": [[SHROOM, 2, 0.6], [CRYSTAL, 1, 0.25]]},
	"stonetoad": {"name": "Stone Toad", "where": ["cave2"], "w": 15.0, "h": 11.0, "hp": 50.0, "dmg": 9.0, "go": "hop", "speed": 0.8,
		"body": {"plan": "toad", "len": 17, "tall": 11, "base": "#6a6a64", "belly": "#a8a49a", "accent": "#d8a03a", "dark": "#2a2a26", "eye": "#ffb03a", "skin": "warts"},
		"moves": {"slam": {}, "spit": {"proj": "rock", "n": 1, "spread": 0.1}}, "drops": [[STONE, 4, 0.6], [DEEPSTONE, 2, 0.4], [COPPER, 1, 0.3]]},
	"magmahound": {"name": "Magma Hound", "where": ["cave3"], "w": 19.0, "h": 13.0, "hp": 60.0, "dmg": 12.0, "go": "walk", "speed": 1.4,
		"body": {"plan": "beast", "len": 22, "tall": 10, "leg": 9, "head": 8, "neck": 3, "base": "#4a1a14", "belly": "#8a3a1a", "accent": "#ff8a2a",
			"dark": "#1a0a08", "eye": "#ffd23a", "skin": "scales", "spikes": 5, "tail": "long", "ears": true},
		"moves": {"charge": {"v": 4.0}, "spit": {"proj": "efire", "n": 2, "spread": 0.2}}, "drops": [[EMBER, 3, 1.0], [OBSIDIAN, 2, 0.4]]},
	# the ashlands (Cindrel, Sere)
	"cinderwing": {"name": "Cinderwing", "where": ["ashland"], "w": 11.0, "h": 8.0, "hp": 22.0, "dmg": 7.0, "go": "fly", "speed": 1.8,
		"body": {"plan": "bird", "len": 12, "span": 16, "base": "#3a2e2a", "belly": "#8a4a2a", "accent": "#ff8a2a", "dark": "#140c0a", "eye": "#ffd23a", "skin": "fur"},
		"moves": {"dive": {"v": 4.0}}, "drops": [[ASH, 3, 0.6], [EMBER, 1, 0.2]]},
	"scorchhound": {"name": "Scorch Hound", "where": ["ashland"], "pack": 2, "w": 16.0, "h": 12.0, "hp": 32.0, "dmg": 9.0, "go": "walk", "speed": 1.5,
		"body": {"plan": "beast", "len": 19, "tall": 9, "leg": 8, "head": 7, "neck": 2, "base": "#4a2a22", "belly": "#8a4a2a", "accent": "#ff7a2a",
			"dark": "#1a0c08", "eye": "#ffd23a", "skin": "scales", "spikes": 4, "tail": "long", "ears": true},
		"moves": {"charge": {"v": 3.8}}, "drops": [[ASH, 3, 0.5], [OBSIDIAN, 1, 0.3]]},
	"lavatoad": {"name": "Lava Toad", "where": ["ashland"], "w": 14.0, "h": 10.0, "hp": 36.0, "dmg": 8.0, "go": "hop", "speed": 0.9,
		"body": {"plan": "toad", "len": 15, "tall": 10, "base": "#5a2a1a", "belly": "#c8602a", "accent": "#ffb03a", "dark": "#1e0c08", "eye": "#ffe14a", "skin": "warts"},
		"moves": {"slam": {}, "spit": {"proj": "efire", "n": 2, "spread": 0.2}}, "drops": [[MAGMAROCK, 3, 0.6], [EMBER, 1, 0.3]]},
	# the drowned shelves (Thalassa): "swim" ones keep to the water
	"reefeel": {"name": "Reef Eel", "where": ["ocean"], "swim": true, "w": 7.0, "h": 6.0, "hp": 26.0, "dmg": 8.0, "go": "slither", "speed": 1.9,
		"body": {"plan": "serpent", "segs": 8, "rad": 2.8, "base": "#2a6a6a", "belly": "#c8e870", "accent": "#ffd23a", "dark": "#0e2a2a", "eye": "#ff6a3a"},
		"moves": {"dive": {"v": 3.6}}, "drops": [[SAND, 2, 0.5], [CRYSTAL, 1, 0.15]]},
	"driftjelly": {"name": "Drift Jelly", "where": ["ocean"], "swim": true, "w": 11.0, "h": 11.0, "hp": 18.0, "dmg": 6.0, "go": "fly", "speed": 0.5,
		"col": Color(1.0, 0.5, 0.85),
		"body": {"plan": "fungus", "len": 12, "tall": 12, "base": "#8ac8ff", "belly": "#e8f4ff", "accent": "#ff7ad8", "dark": "#2a4a8a", "eye": "#ffffff", "skin": "spots"},
		"moves": {"cloud": {"r": 10.0, "t": 160}}, "drops": [[WATER, 3, 0.6], [CRYSTAL, 1, 0.2]]},
	"stormgull": {"name": "Storm Gull", "where": ["ocean"], "w": 10.0, "h": 8.0, "hp": 18.0, "dmg": 6.0, "go": "fly", "speed": 1.9,
		"body": {"plan": "bird", "len": 11, "span": 16, "base": "#e8eef0", "belly": "#ffffff", "accent": "#ffb03a", "dark": "#5a6670", "eye": "#1a1a1a", "skin": "fur"},
		"moves": {"dive": {"v": 3.8}}, "drops": [[SAND, 2, 0.4]]},
}

## the creatures that live in a place ("forest", "cave2"...)
func creatures_of(where: String) -> Array:
	var out := []
	for id in CREATURES:
		if (CREATURES[id]["where"] as Array).has(where):
			out.append(id)
	return out

var _creature_enemy := {}

## a creature as a foe ("c_<id>"): like a guardian's, but not a boss (no lair, no rage), its own sight
func creature_enemy(type: String) -> Dictionary:
	if _creature_enemy.has(type):
		return _creature_enemy[type]
	var c: Dictionary = CREATURES[type.trim_prefix("c_")]
	var go: String = c["go"]
	var d := {"w": c["w"], "h": c["h"], "hp": c["hp"], "dmg": c["dmg"], "fly": go == "fly" or go == "slither" or go == "burrow", "spr": type,
		"boss": false, "drops": c.get("drops", []), "def": c, "creature": true, "ai": {"sight": 170.0}}
	_creature_enemy[type] = d
	return d

var _boss_enemy := {}

## A guardian as a foe ("boss_<biome>"): the fields every foe has, the boss's own definition in "def".
func boss_enemy(type: String) -> Dictionary:
	if _boss_enemy.has(type):
		return _boss_enemy[type]
	var b: Dictionary = BOSSES[type.trim_prefix("boss_")]
	var d := {"w": b["w"], "h": b["h"], "hp": b["hp"], "dmg": b["dmg"], "fly": bool(b.get("fly", false)), "spr": type,
		"boss": true, "drops": [], "def": b, "biome": type.trim_prefix("boss_"), "ai": {"sight": 400.0}}
	_boss_enemy[type] = d
	return d

## The dungeon wardens of the planet the GPU holds ("warden_<key>" -> its definition from
## wardens.gd), registered by main.gd as the world is made (they come from the dungeons' seeds).
var WARDENS := {}
var _warden_enemy := {}

func register_warden(type: String, wd: Dictionary) -> void:
	WARDENS[type] = wd
	_warden_enemy.erase(type)

## a warden as a foe: a boss like a guardian ("def" is its definition, "key" what marks it beaten)
func warden_enemy(type: String) -> Dictionary:
	if _warden_enemy.has(type):
		return _warden_enemy[type]
	var b: Dictionary = WARDENS[type]
	var d := {"w": b["w"], "h": b["h"], "hp": b["hp"], "dmg": b["dmg"], "fly": bool(b.get("fly", false)), "spr": type,
		"boss": true, "warden": true, "drops": [], "def": b, "biome": "", "key": type, "ai": {"sight": 300.0}}
	_warden_enemy[type] = d
	return d

## any foe's definition (the fixed ones, a creature, a guardian or a warden)
func enemy_def(type: String) -> Dictionary:
	if ENEMY.has(type):
		return ENEMY[type]
	if type.begins_with("c_"):
		return creature_enemy(type)
	return warden_enemy(type) if type.begins_with("warden_") else boss_enemy(type)

func sprite_texture(key: String) -> ImageTexture:
	# draws the sprite with a 1-pixel dark outline, 16-bit style
	var d: Dictionary = SPRITES[key]
	var rows: Array = d["rows"]
	var w: int = rows[0].length()
	var h: int = rows.size()
	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		for x in w:
			var ch := row[x]
			if ch != ".":
				img.set_pixel(x + 1, y + 1, Color.html(d["pal"][ch]))
	var outline := Color(0.07, 0.04, 0.1, 1.0)
	var src: Image = img.duplicate()
	for y in h + 2:
		for x in w + 2:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < w + 2 and q.y < h + 2 and src.get_pixel(q.x, q.y).a > 0.5:
					img.set_pixel(x, y, outline)
					break
	return ImageTexture.create_from_image(img)
