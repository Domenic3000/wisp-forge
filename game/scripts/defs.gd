extends Node
## Wisp Forge — shared game data (autoload singleton "Defs").
const Props := preload("res://scripts/props.gd")
## Materials are defined once here; the GPU shaders get the same tables
## through glsl_prefix(), so CPU and GPU always agree.

const NM := 50
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
## The back walls a piece of furniture can stand in front of (see behind_index). 0 is none.
const BEHIND := [0, PLANK, WOOD, MASONRY, BRICK, SANDSTONE, GLASS, MOSSBLOCK, STONE, TILE, OBSIDIAN,
	RUNESTONE, DRYGRASS, CAP, STALK, DIRT, DEEPSTONE, ICE, LEAF, SCAFFOLD]

const MAT_NAMES := {
	0: "AIR", 1: "STONE", 2: "DIRT", 3: "GRASS", 4: "SAND", 5: "WATER", 6: "LAVA", 7: "WOOD", 8: "LEAF",
	9: "FIRE", 10: "SMOKE", 11: "STEAM", 12: "OBSIDIAN", 13: "DEEPSTONE", 14: "COPPER", 15: "COAL",
	16: "EMBER", 17: "FROST", 18: "WISP", 19: "MUD", 20: "ICE", 21: "MAGMAROCK", 22: "CORE",
	23: "SHROOM", 24: "GRAVEL", 25: "BRICK", 26: "GLASS", 27: "SNOW", 28: "CRYSTAL", 29: "ASH",
	30: "PLANK", 31: "CACTUS", 32: "TIMBER", 33: "LITTER", 34: "MASONRY", 35: "SANDSTONE", 36: "TILE",
	37: "MOSSBLOCK", 38: "TREASURE", 39: "TORCH", 40: "OPENCHEST", 41: "SCAFFOLD", 42: "RUNESTONE", 43: "DECOR", 44: "WOODDOOR", 45: "CAP", 46: "STALK", 47: "MYCELIUM", 48: "DRYGRASS", 49: "ROOT",
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
			[SHROOM, 6], [CAP, 6], [STALK, 14], [MYCELIUM, 10], [DRYGRASS, 10], [MASONRY, 28], [MOSSBLOCK, 22], [SANDSTONE, 20], [TILE, 14], [TREASURE, 14], [TORCH, 4]]:
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

## Where the planets hang (world units, Verdance at the centre): space travel flies between them. Each
## further round of five planets lies far off along x (a prototype layout).
const SYSTEM := [Vector2(0, 0), Vector2(-52000, 18000), Vector2(41000, 47000), Vector2(66000, -24000), Vector2(-30000, -61000)]

func planet_pos(i: int) -> Vector2:
	return SYSTEM[i % SYSTEM.size()] + Vector2(float(i / SYSTEM.size()) * 400000.0, 0.0)

## Each planet has its own size: "radius" is its mean surface radius in cells (Verdance 1304).
const PLANETS := [
	{"name": "Verdance", "radius": 1304.0, "desc": "A temperate cradle world of woods, bogs and peaks.", "biomes": ["forest", "jungle", "marsh", "tundra", "mountain", "savanna", "desert", "grove"], "magmaR": 600.0, "sea": -1.0, "rich": 1.0, "lava": 1.0, "sky": Color(1, 1, 1)},
	{"name": "Cindrel", "radius": 1100.0, "desc": "A volcanic world. The mantle is close to the surface.", "biomes": ["ashland", "mountain", "desert", "ashland", "ashland"], "magmaR": 780.0, "sea": -1.0, "rich": 1.4, "lava": 2.6, "sky": Color(1.25, 0.78, 0.7)},
	{"name": "Thalassa", "radius": 1600.0, "desc": "A water world: scattered islands over drowned shelves.", "biomes": ["ocean", "forest", "ocean", "marsh", "ocean", "tundra", "ocean"], "magmaR": 580.0, "sea": 26.0, "rich": 1.2, "lava": 0.8, "sky": Color(0.85, 1.05, 1.15)},
	{"name": "Sere", "radius": 1450.0, "desc": "An endless desert world baked under twin suns.", "biomes": ["desert", "mountain", "desert", "desert", "ashland"], "magmaR": 640.0, "sea": -1.0, "rich": 1.5, "lava": 1.5, "sky": Color(1.15, 1.0, 0.8)},
	{"name": "Fenhollow", "radius": 950.0, "desc": "A drowned marsh world with deep black lakes.", "biomes": ["marsh", "grove", "marsh", "tundra", "marsh", "jungle"], "magmaR": 600.0, "sea": 18.0, "rich": 1.6, "lava": 1.0, "sky": Color(0.85, 1.0, 0.85)},
]

func make_planet(i: int) -> Dictionary:
	var base: Dictionary = PLANETS[i % PLANETS.size()].duplicate(true)
	var cycle := i / PLANETS.size()
	base["index"] = i
	base["seed"] = 1337 + i * 7919
	if cycle > 0:
		base["name"] = "%s %d" % [base["name"], cycle + 1]
	base["rich"] = float(base["rich"]) * (1.0 + cycle * 0.25)
	# depths were set for a planet of Verdance's size: the mantle sits as deep in proportion
	base["magmaR"] = float(base["magmaR"]) * float(base["radius"]) / 1304.0
	return base

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
	{"id": "skiff", "cat": "Travel", "name": "Wisp Skiff", "cost": {PLANK: 40, GLASS: 12, WISP: 10, COPPER: 8}, "desc": "A small ship for two. K calls it to you, F to board or step out, hold cast to fly toward the cursor. It flies out into space and back."},
	{"id": "gate", "cat": "World Gate", "name": "Forge the World Gate", "cost": {CORE: 40, WISP: 20}, "desc": "Travel to the next planet. Needs the Core Siphon."},
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
}

## The relics the guardians keep (items[id]; main.gd applies them where they matter).
const RELICS := {
	"ironbark": {"name": "Ironbark Shell", "desc": "You take a quarter less damage."},
	"coil": {"name": "Serpent's Coil", "desc": "You move a fifth faster."},
	"pearl": {"name": "Mire Pearl", "desc": "You breathe under water."},
	"rimefang": {"name": "Rimefang's Tooth", "desc": "Your Spark Bolts chill what they hit."},
	"roc": {"name": "Roc Feather", "desc": "Levitating costs half the mana."},
	"lionheart": {"name": "Lionheart", "desc": "+40 max health."},
	"sunidol": {"name": "Sun Idol", "desc": "Your spells hit a quarter harder."},
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

## any foe's definition (the fixed ones, or a guardian)
func enemy_def(type: String) -> Dictionary:
	if ENEMY.has(type):
		return ENEMY[type]
	return creature_enemy(type) if type.begins_with("c_") else boss_enemy(type)

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
