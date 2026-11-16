extends Node
## Wisp Forge — shared game data (autoload singleton "Defs").
## Materials are defined once here; the GPU shaders get the same tables
## through glsl_prefix(), so CPU and GPU always agree.

const NM := 48
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

const MAT_NAMES := {
	0: "AIR", 1: "STONE", 2: "DIRT", 3: "GRASS", 4: "SAND", 5: "WATER", 6: "LAVA", 7: "WOOD", 8: "LEAF",
	9: "FIRE", 10: "SMOKE", 11: "STEAM", 12: "OBSIDIAN", 13: "DEEPSTONE", 14: "COPPER", 15: "COAL",
	16: "EMBER", 17: "FROST", 18: "WISP", 19: "MUD", 20: "ICE", 21: "MAGMAROCK", 22: "CORE",
	23: "SHROOM", 24: "GRAVEL", 25: "BRICK", 26: "GLASS", 27: "SNOW", 28: "CRYSTAL", 29: "ASH",
	30: "PLANK", 31: "CACTUS", 32: "TIMBER", 33: "LITTER", 34: "MASONRY", 35: "SANDSTONE", 36: "TILE",
	37: "MOSSBLOCK", 38: "TREASURE", 39: "TORCH", 40: "OPENCHEST",
}

# ---- planet geometry (polar shells; column count halves as radius halves) ----
const R_TOP := 1800.0        # edge of space
const R_IN := 80.0           # the planet's heart (not simulated)
const RS0 := 1304.0          # mean surface radius (cells are ~square here)
const SH_Y0 := [0, 1148, 1474, 1638, 1720]   # shell start rows (row 0 = R_TOP)
const SH_N := [8192, 4096, 2048, 1024]       # columns per shell
const ROWS := 1720

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
	_def(MUD, "Mud", K_LIQUID, ["#4b3a26", "#56432c", "#423320", "#5c4830"], {"dens": 4})
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
	PLACE[TIMBER] = 0
	PLACE[LITTER] = 0
	PLACE[TREASURE] = 0
	# structural strength: how many cells a solid can reach sideways (or hang) from something
	# resting on the ground before it breaks loose. Stacking straight up is always fine.
	for kv in [[STONE, 40], [DEEPSTONE, 48], [MAGMAROCK, 56], [OBSIDIAN, 60], [CORE, 63], [DIRT, 10], [GRASS, 10],
			[ICE, 14], [FROST, 24], [WOOD, 16], [LEAF, 4], [PLANK, 12], [BRICK, 24], [GLASS, 6], [CACTUS, 8],
			[SHROOM, 6], [MASONRY, 28], [MOSSBLOCK, 22], [SANDSTONE, 20], [TILE, 14], [TREASURE, 6], [TORCH, 4]]:
		SPAN[kv[0]] = kv[1]
	for kv in [[STONE, GRAVEL], [DEEPSTONE, GRAVEL], [MAGMAROCK, GRAVEL], [BRICK, GRAVEL], [MASONRY, GRAVEL],
			[MOSSBLOCK, GRAVEL], [TILE, GRAVEL], [SANDSTONE, SAND], [WOOD, TIMBER], [PLANK, TIMBER], [LEAF, LITTER],
			[CACTUS, LITTER], [ICE, SNOW], [GLASS, AIR], [TORCH, AIR]]:
		DEBRIS[kv[0]] = kv[1]
	for kv in [[WOOD, TIMBER], [PLANK, TIMBER], [LEAF, LITTER], [CACTUS, LITTER], [SHROOM, LITTER], [CRYSTAL, GRAVEL],
			[ICE, SNOW], [EMBER, GRAVEL], [MASONRY, GRAVEL], [MOSSBLOCK, GRAVEL], [BRICK, GRAVEL], [STONE, GRAVEL],
			[SANDSTONE, SAND], [TILE, GRAVEL], [OBSIDIAN, GRAVEL]]:
		BGDEBRIS[kv[0]] = kv[1]
	var off := 0
	for s in 4:
		SH_OFF.append(off)
		off += (SH_Y0[s + 1] - SH_Y0[s]) * SH_N[s]
	SH_OFF.append(off)

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
	return SH_OFF[4]

## GLSL constants injected in front of every compute shader.
func glsl_prefix() -> String:
	var s := "#version 450\n#define NM %d\n#define TAU 6.28318530718\n" % NM
	s += "#define R_TOP %.1f\n#define R_IN %.1f\n#define RS0 %.1f\n#define ROWS %d\n" % [R_TOP, R_IN, RS0, ROWS]
	s += "#define K_EMPTY 0u\n#define K_SOLID 1u\n#define K_POWDER 2u\n#define K_LIQUID 3u\n#define K_GAS 4u\n#define K_FIRE 5u\n"
	for id in MAT_NAMES:
		s += "#define M_%s %du\n" % [MAT_NAMES[id], id]
	s += "const int SH_Y0[5] = int[5](%s);\n" % _join_i(SH_Y0)
	s += "const int SH_N[4] = int[4](%s);\n" % _join_i(SH_N)
	s += "const int SH_OFF[5] = int[5](%s);\n" % _join_i(SH_OFF)
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
	return s

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
# flora: 0 none, 1 trees, 2 pines, 3 cactus, 4 reeds, 5 dead trees, 6 kelp
# ug (underground): 0 fungal, 1 crystal, 2 ice, 3 ember
# flags: 1 snowcap, 2 pond, 4 lava lake, 8 spawn ok
const BIOMES := {
	"forest": {"name": "Whisperwood", "under": "Glowroot Caverns", "off": 0.0, "amp": 14.0, "top": GRASS, "topD": 1, "sub": DIRT, "subD": 12, "weather": "rain", "flora": 1, "ug": 0, "flags": 8},
	"desert": {"name": "Sunscar Dunes", "under": "Prism Hollows", "off": 14.0, "amp": 9.0, "top": SAND, "topD": 5, "sub": SAND, "subD": 14, "weather": "clear", "flora": 3, "ug": 1, "flags": 8},
	"marsh": {"name": "Murkfen Bog", "under": "Glowroot Caverns", "off": 22.0, "amp": 4.0, "top": MUD, "topD": 3, "sub": DIRT, "subD": 8, "weather": "rain", "flora": 4, "ug": 0, "flags": 2 | 8},
	"mountain": {"name": "Greyspire Peaks", "under": "Frostvein Grottos", "off": -75.0, "amp": 48.0, "top": STONE, "topD": 0, "sub": STONE, "subD": 0, "weather": "snow", "flora": 2, "ug": 2, "flags": 1},
	"tundra": {"name": "Rimefrost Steppe", "under": "Frostvein Grottos", "off": -6.0, "amp": 8.0, "top": SNOW, "topD": 3, "sub": DIRT, "subD": 8, "weather": "snow", "flora": 2, "ug": 2, "flags": 8},
	"ashland": {"name": "Cinderwaste", "under": "Smoldering Vaults", "off": 6.0, "amp": 20.0, "top": ASH, "topD": 4, "sub": STONE, "subD": 0, "weather": "ash", "flora": 5, "ug": 3, "flags": 4},
	"ocean": {"name": "Drowned Shelf", "under": "Abyssal Grottos", "off": 62.0, "amp": 18.0, "top": SAND, "topD": 3, "sub": SAND, "subD": 8, "weather": "rain", "flora": 6, "ug": 0, "flags": 0},
}

const PLANETS := [
	{"name": "Verdance", "desc": "A temperate cradle world of woods, bogs and peaks.", "biomes": ["forest", "marsh", "tundra", "mountain", "desert", "forest", "mountain"], "magmaR": 600.0, "sea": -1.0, "rich": 1.0, "lava": 1.0, "sky": Color(1, 1, 1)},
	{"name": "Cindrel", "desc": "A volcanic world. The mantle is close to the surface.", "biomes": ["ashland", "mountain", "desert", "ashland", "ashland"], "magmaR": 780.0, "sea": -1.0, "rich": 1.4, "lava": 2.6, "sky": Color(1.25, 0.78, 0.7)},
	{"name": "Thalassa", "desc": "A water world: scattered islands over drowned shelves.", "biomes": ["ocean", "forest", "ocean", "marsh", "ocean", "tundra", "ocean"], "magmaR": 580.0, "sea": 26.0, "rich": 1.2, "lava": 0.8, "sky": Color(0.85, 1.05, 1.15)},
	{"name": "Sere", "desc": "An endless desert world baked under twin suns.", "biomes": ["desert", "mountain", "desert", "desert", "ashland"], "magmaR": 640.0, "sea": -1.0, "rich": 1.5, "lava": 1.5, "sky": Color(1.15, 1.0, 0.8)},
	{"name": "Fenhollow", "desc": "A drowned marsh world with deep black lakes.", "biomes": ["marsh", "forest", "marsh", "tundra", "marsh"], "magmaR": 600.0, "sea": 18.0, "rich": 1.6, "lava": 1.0, "sky": Color(0.85, 1.0, 0.85)},
]

func make_planet(i: int) -> Dictionary:
	var base: Dictionary = PLANETS[i % PLANETS.size()].duplicate(true)
	var cycle := i / PLANETS.size()
	base["index"] = i
	base["seed"] = 1337 + i * 7919
	if cycle > 0:
		base["name"] = "%s %d" % [base["name"], cycle + 1]
	base["rich"] = float(base["rich"]) * (1.0 + cycle * 0.25)
	return base

# ---------------------------------------------------------------- spells ----
const SPELL_ORDER := ["spark", "conjure", "fireball", "tide", "frost", "quake", "blink", "starfall"]
const SPELLS := {
	"spark": {"name": "Spark Bolt", "mana": 4.0, "cd": 9, "color": Color(1.0000, 0.9020, 0.5020), "desc": "A quick bolt. Chips terrain, stings foes."},
	"conjure": {"name": "Conjure", "mana": 0.0, "cd": 2, "color": Color(0.7451, 1.0000, 0.7451), "desc": "Place the selected material. Q/E to choose."},
	"fireball": {"name": "Fireball", "mana": 18.0, "cd": 28, "color": Color(1.0000, 0.4706, 0.1569), "desc": "Explodes and ignites anything that burns."},
	"tide": {"name": "Tidecall", "mana": 14.0, "cd": 22, "color": Color(0.3529, 0.6275, 1.0000), "desc": "Bursts into water. Cools lava into obsidian."},
	"frost": {"name": "Frostbite", "mana": 12.0, "cd": 18, "color": Color(0.6667, 0.9412, 1.0000), "desc": "Freezes water and lava. Slows foes."},
	"quake": {"name": "Quake Orb", "mana": 40.0, "cd": 60, "color": Color(0.7843, 0.5490, 1.0000), "desc": "A heavy orb that shatters a huge cavity."},
	"blink": {"name": "Blink", "mana": 22.0, "cd": 30, "color": Color(0.55, 0.95, 1.0), "desc": "Step through space to the cursor."},
	"starfall": {"name": "Starfall", "mana": 45.0, "cd": 70, "color": Color(1.0, 0.82, 0.45), "desc": "A falling star: a huge fiery blast."},
}
const PROJ := {
	"spark": {"speed": 5.5, "g": 0.0, "life": 55, "dmg": 11.0, "light": 18.2},
	"fireball": {"speed": 3.9, "g": 0.035, "life": 140, "dmg": 0.0, "light": 33.8},
	"tide": {"speed": 3.5, "g": 0.07, "life": 120, "dmg": 6.0, "light": 15.6},
	"frost": {"speed": 4.7, "g": 0.0, "life": 80, "dmg": 14.0, "light": 20.8},
	"quake": {"speed": 3.0, "g": 0.09, "life": 160, "dmg": 0.0, "light": 28.6},
	"starfall": {"speed": 3.4, "g": 0.02, "life": 160, "dmg": 0.0, "light": 41.6},
	"efire": {"speed": 2.2, "g": 0.0, "life": 200, "dmg": 12.0, "light": 18.2},
}

# ---------------------------------------------------------------- recipes ---
const RECIPES := [
	{"id": "plank", "cat": "Materials", "name": "Planks x4", "cost": {WOOD: 2}, "give": {PLANK: 4}, "desc": "Flammable building boards."},
	{"id": "brick", "cat": "Materials", "name": "Bricks x4", "cost": {STONE: 3, DIRT: 1}, "give": {BRICK: 4}, "desc": "Tough blocks (staff tier 2 to carve)."},
	{"id": "glass", "cat": "Materials", "name": "Glass x4", "cost": {SAND: 4, COAL: 1}, "give": {GLASS: 4}, "desc": "See-through blocks."},
	{"id": "masonry", "cat": "Materials", "name": "Stone Blocks x4", "cost": {STONE: 4}, "give": {MASONRY: 4}, "desc": "Strong building blocks (span 28)."},
	{"id": "torch", "cat": "Materials", "name": "Torches x4", "cost": {WOOD: 1, COAL: 1}, "give": {TORCH: 4}, "desc": "Light that never goes out."},
	{"id": "obsid", "cat": "Materials", "name": "Obsidian x4", "cost": {LAVA: 4, WATER: 4}, "give": {OBSIDIAN: 4}, "desc": "Quench lava in water."},
	{"id": "fireball", "cat": "Spells", "name": "Fireball", "cost": {COAL: 12, COPPER: 6}, "spell": "fireball"},
	{"id": "tide", "cat": "Spells", "name": "Tidecall", "cost": {WATER: 40, COPPER: 4}, "spell": "tide"},
	{"id": "frost", "cat": "Spells", "name": "Frostbite", "cost": {FROST: 10, SNOW: 10}, "spell": "frost"},
	{"id": "quake", "cat": "Spells", "name": "Quake Orb", "cost": {WISP: 10, STONE: 40, COAL: 10}, "spell": "quake"},
	{"id": "blink", "cat": "Spells", "name": "Blink", "cost": {WISP: 6, CRYSTAL: 6}, "spell": "blink", "scroll": "scroll_blink"},
	{"id": "starfall", "cat": "Spells", "name": "Starfall", "cost": {EMBER: 12, OBSIDIAN: 6, COAL: 10}, "spell": "starfall", "scroll": "scroll_starfall"},
	{"id": "tier2", "cat": "Staff & Body", "name": "Copper Focus", "cost": {COPPER: 20, STONE: 20}, "desc": "Staff tier 2: Deepstone, Ember, Wisp, Brick, Lava."},
	{"id": "wide", "cat": "Staff & Body", "name": "Wide Excavation", "cost": {COPPER: 10, CRYSTAL: 10}, "desc": "Bigger excavation radius (7.5 to 11)."},
	{"id": "vital", "cat": "Staff & Body", "name": "Vital Bloom", "cost": {SHROOM: 16, LEAF: 12}, "desc": "+50 max health."},
	{"id": "mana", "cat": "Staff & Body", "name": "Mana Crystal", "cost": {WISP: 8, CRYSTAL: 8}, "desc": "+70 max mana, faster regeneration."},
	{"id": "ward", "cat": "Staff & Body", "name": "Heat Ward", "cost": {EMBER: 15, FROST: 10, OBSIDIAN: 6}, "desc": "Survive the mantle heat."},
	{"id": "tier3", "cat": "Staff & Body", "name": "Obsidian Focus", "cost": {OBSIDIAN: 15, EMBER: 12, WISP: 6}, "desc": "Staff tier 3: Obsidian and Magma Rock."},
	{"id": "tier4", "cat": "Staff & Body", "name": "Core Siphon", "cost": {OBSIDIAN: 20, WISP: 15}, "desc": "Staff tier 4: harvest the Planet Core. Needs the Ember Heart."},
	{"id": "gate", "cat": "World Gate", "name": "Forge the World Gate", "cost": {CORE: 40, WISP: 20}, "desc": "Travel to the next planet. Needs the Core Siphon."},
]

# ---------------------------------------------------------------- sprites ---
# ---- sprites (drawn as text; tools/sprites.py checks them). The mage is 16x24 with animation
# frames: idle (2), walk (4), jump, fall, levitate (float), cast and hurt, drawn 18 wide (a cape
# behind, an arm and hand in front). Enemies have 2 frames each.
const CHEST_W := 8   # treasure chests are 8 x 6 cells (each cell stores its part: col | row << 3)
const CHEST_H := 6
const SPRITES := {
	"mage": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrd..",
			"...hHrRqdrrrrrdrd.",
			"...h.cccccccccccc.",
			".....kKk..kKk.....",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_idle2": {"rows": [
			".........hH.......",
			"........hHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrd..",
			"..hHHrRqdrrrrrdrd.",
			"..h..cccccccccccc.",
			".....kKk..kKk.....",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_walk1": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"..hHrRRqdrrrrdrdd.",
			"..hHrRqdrrrrrrdrd.",
			"..h.cccccccccccccc",
			"...kKk.......kKk..",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_walk2": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrd..",
			"...hHrRqdrrrrdrd..",
			"...h.cccccccccc...",
			"......kKkkK.......",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_walk3": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrdd.",
			"..hHHrRqdrrrrrdrd.",
			"..h..ccccccccccccc",
			"....kKk.....kKk...",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_walk4": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrd..",
			"...hHrRqdrrrrdrd..",
			"...h.ccccccccccc..",
			"........kKkkK.....",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_jump": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrd..",
			"..hH.rRqdrrrrdrd..",
			"..h...ccccccccccc.",
			"......kKk.kKk.....",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_fall": {"rows": [
			"..................",
			"........hH........",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"..hHHrRdrrrprdrdd.",
			"..hHrRqdrrrrrrdrd.",
			".h..rRqdrrrrrrrdrd",
			"....c.ccccccccc.c.",
			".....kK....kK.....",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_float": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrcss",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"..hHHrRqdrrrrdrd..",
			"..hH.rRqdrrrrrdrd.",
			"..h..c.cccccccc.c.",
			"...q...kKkK...q...",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_cast": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......sssssWW.....",
			"......ssssness....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwrcss",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrrd.",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrd..",
			"...hHrRqdrrrrrdrd.",
			"...h.cccccccccccc.",
			".....kKk..kKk.....",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
	"mage_hurt": {"rows": [
			"........hH........",
			".......hHHl.......",
			".......hHHl.......",
			"......hhHHLl......",
			"......hHHYHL......",
			".....hhHHHHLl.....",
			".....hHHHHHHLl....",
			"....hgGGGGGGGGg...",
			"...hhhHHHHHHHHLl..",
			"..h...SSSSSSSS..l.",
			"......ssssSSS.....",
			"......ssssnSSs....",
			".....hsvwwwwwS....",
			".....hrvwwwwwwr...",
			"....hHrvwWwwwWRr..",
			"....hHrqvwwwwWrRcs",
			"....hHrRvwWwvrd...",
			"....hHrRRvwvrdd...",
			"....hHBBBBGBBBd...",
			"....hHrRdrrprdd...",
			"...hHrRqdrrrrdrd..",
			"...hHrRqdrrrrrdrd.",
			"...h.cccccccccccc.",
			".....kKk..kKk.....",
		],
		"pal": {"h": "#2a1d62", "H": "#4630a0", "L": "#6f55d4", "l": "#a28aff", "Y": "#fff0a0", "g": "#9a6c24", "G": "#e8b84a", "s": "#f2c9a2", "S": "#b98060", "e": "#1a1430", "n": "#e89a8a", "w": "#f4f4fb", "W": "#c4c2d8", "v": "#8a87a4", "d": "#141e50", "r": "#28408f", "R": "#3f62c4", "q": "#7a9cf6", "B": "#5e361a", "p": "#94602e", "c": "#d8a83a", "k": "#2a1810", "K": "#5c3a22"}},
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
			"......oooooooo......",
			".....oLooooooLo.....",
			"....ooyyooooyyoo....",
			"....oooooccooooo....",
			".....oLooooooLo.....",
			"..oooooooooooooooo..",
			".ooLooooocccoooLooo.",
			"oooooocooccocoooooo.",
			"ooLoooocccccccooLooo",
			"ooo.oooocccccoooooo.",
			"ooo.ooooocccoooo.ooo",
			"oo..oooooocooooo..oo",
			"oo..ooLooooooLoo..oo",
			"cc..oooooooooooo..cc",
			"cc...oooo..oooo...cc",
			".....oooo..oooo.....",
			".....oLoo..ooLo.....",
			".....oooo..oooo.....",
			"....ooooo..ooooo....",
			"....ccccc..ccccc....",
		],
		"pal": {"o": "#5a4640", "O": "#3a2c28", "c": "#ff7a2a", "y": "#ffd23a", "L": "#7a6058"}},
	"golem2": {"rows": [
			"......oooooooo......",
			".....oLooooooLo.....",
			"....ooyyooooyyoo....",
			"....oooooccooooo....",
			".....oLooooooLo.....",
			"..oooooooooooooooo..",
			".ooLooooocccoooLooo.",
			"oooooocooccocoooooo.",
			"ooLoooocccccccooLooo",
			"ooo.oooocccccoooooo.",
			"ooo.ooooocccoooo.ooo",
			"oo..oooooocooooo..oo",
			"oo..ooLooooooLoo..oo",
			"cc..oooooooooooo..cc",
			"cc...oooo..oooo...cc",
			"....oooo....oooo....",
			"....oLoo....ooLo....",
			"...oooo......oooo...",
			"...ooooo.....ooooo..",
			"...ccccc.....ccccc..",
		],
		"pal": {"o": "#5a4640", "O": "#3a2c28", "c": "#ff7a2a", "y": "#ffd23a", "L": "#7a6058"}},
}

const ENEMY := {
	"slime": {"w": 12.0, "h": 9.0, "hp": 22.0, "dmg": 6.0, "fly": false, "spr": "slime", "drops": [[WISP, 1, 0.35], [WATER, 4, 1.0]]},
	"bat": {"w": 11.0, "h": 6.0, "hp": 16.0, "dmg": 7.0, "fly": true, "spr": "bat1", "drops": [[COAL, 2, 0.8], [SHROOM, 2, 0.5]]},
	"imp": {"w": 9.0, "h": 12.0, "hp": 34.0, "dmg": 11.0, "fly": true, "spr": "imp", "drops": [[EMBER, 3, 1.0], [OBSIDIAN, 2, 0.4]]},
	"skeleton": {"w": 7.0, "h": 17.0, "hp": 40.0, "dmg": 8.0, "fly": false, "spr": "skeleton", "step": 2, "drops": [[TORCH, 2, 0.5], [CRYSTAL, 2, 0.4], [WISP, 1, 0.25]]},
	"mimic": {"w": 16.0, "h": 9.0, "hp": 90.0, "dmg": 14.0, "fly": false, "spr": "mimic", "step": 2, "drops": [[WISP, 4, 1.0], [EMBER, 4, 0.8], [CRYSTAL, 4, 0.8]]},
	"golem": {"w": 17.0, "h": 20.0, "hp": 900.0, "dmg": 18.0, "fly": false, "spr": "golem", "boss": true, "drops": []},
}

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
