## A pirate ship: a ship of real cells grown from parts by its seed (user, 23 Nov: pirates, "enemy ships
## made of real cells, fought with the cannon and shield"). It extends wreck.gd, so space.gd draws it,
## lets it drift, collides with it and blasts its cells exactly as it does a wreck's; and once it is
## beaten it simply becomes one (kind "wreck", its strongbox a cache) to drift into and loot.
##
## `Pirate.make_pirate(seed, cls)` grows it (`CLASSES`: a quick "cutter", a heavier "brig"): a dark
## plated hull over a keel that rises to the bow, a red stripe along it, an obsidian ram, a raised
## stern castle with lit windows and a red lantern, an ember engine glowing at the stern, one or two
## masts with tattered black sails (the main one marked with a skull), a pennant, deck guns, and a
## strongbox lashed to the castle's roof (`caches`, kind "pirate"). Its own life (hunting you, firing) is
## space.gd's (`_update_pirates`); here are its numbers: `hp`, the guns' cells, its engine's cell.
extends "res://scripts/wreck.gd"

const CLASSES := {
	"cutter": {"len": [64, 72], "depth": [10, 12], "mast": 20, "hp": 90.0, "accel": 0.34, "max_v": 20.0,
		"range": 140.0, "fire": [60, 85], "masts": 1, "guns": 1, "castle": 16, "name": "pirate cutter"},
	"brig": {"len": [88, 100], "depth": [13, 15], "mast": 26, "hp": 170.0, "accel": 0.22, "max_v": 14.0,
		"range": 165.0, "fire": [80, 110], "masts": 2, "guns": 2, "castle": 20, "name": "pirate brig"},
}
const PNAME_A := ["Black", "Red", "Grim", "Rusty", "Crimson", "Howling", "Iron", "Jagged", "Mad", "Bitter",
	"Hungry", "Scarlet"]
const PNAME_B := ["Gull", "Jackal", "Maw", "Fang", "Widow", "Corsair", "Raven", "Hook", "Barracuda",
	"Cutlass", "Shark", "Vulture"]
## the skull on the main sail (".": sail, "#": bone)
const SKULL := [".###.", "#####", "#.#.#", "#####", ".#.#.", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"]

var cls := "cutter"
var hp := 90.0
var hp_max := 90.0
var guns := []                 # [Vector2i] the cells its bolts leave from (a barrel's mouth)
var stern := Vector2i.ZERO     # its engine's middle (the exhaust streams from here)
var fire_t := 0                # ticks to its next volley
var side := 1                  # which way round you it works
var side_t := 0
var beaten := false
var thrusting := false
var hit_t := 0                 # (frames since a bolt struck it: drawn as a flash)

## its name, from its seed
static func pirate_name(sd: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd ^ 0x5EA
	return "the %s %s" % [PNAME_A[rng.randi_range(0, PNAME_A.size() - 1)], PNAME_B[rng.randi_range(0, PNAME_B.size() - 1)]]

static func make_pirate(sd: int, c := "cutter") -> RefCounted:
	var pr = load("res://scripts/pirate.gd").new()
	pr._build_pirate(sd, c)
	return pr

func spec() -> Dictionary:
	return CLASSES[cls]

func _build_pirate(sd: int, c: String) -> void:
	seed_ = sd
	cls = c if CLASSES.has(c) else "cutter"
	kind = "pirate"
	var sp: Dictionary = CLASSES[cls]
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	wname = pirate_name(sd)
	fate = ""
	var L := rng.randi_range(int(sp["len"][0]), int(sp["len"][1]))
	var depth := rng.randi_range(int(sp["depth"][0]), int(sp["depth"][1]))
	var mast_h := int(sp["mast"]) + rng.randi_range(0, 4)
	var deck := mast_h + 4                       # the deck's row (masts and sails above it)
	var ram := 9
	var x0 := 4                                  # the stern's column
	setup(L + ram + 8, deck + depth + 5)
	# ---- the hull: dark plating from the deck down to a keel rising to the bow
	var bots := PackedInt32Array()
	bots.resize(w)
	for i in range(x0, x0 + L):
		var t := float(i - x0) / float(L - 1)
		var kd := float(depth) * (1.0 - pow(maxf(0.0, (t - 0.58) / 0.42), 1.5) * 0.72 - pow(maxf(0.0, (0.08 - t) / 0.08), 2.0) * 0.3)
		var b := deck + int(round(kd))
		bots[i] = b
		for j in range(deck, b + 1):
			_dark_plate(i, j)
		# the keel's own dark timber, and a red stripe along the hull under the deck
		put(i, b, Defs.TIMBER, 0)
		if deck + 3 < b:
			put(i, deck + 2, Defs.TILE, 3)
			put(i, deck + 3, Defs.TILE, 0)
	# the bow rises over the deck to a point, with a bowsprit reaching forward
	var bow := x0 + L - 1
	for k in 6:
		for j in range(deck - k, deck):
			_dark_plate(bow - k, j)
	for k2 in 12:
		put(bow + 1 + k2, deck - 5 - k2 / 3, Defs.TIMBER, 0)
		put(bow + 1 + k2, deck - 4 - k2 / 3, Defs.TIMBER, 1)
	# the ram: an obsidian wedge forward of the bow, low on the hull
	var rj := deck + 4
	for k3 in ram:
		var half := maxi(0, 3 - k3 / 3)
		for j2 in range(rj - half, rj + half + 1):
			put(bow + 1 + k3, j2, Defs.OBSIDIAN, 2 if j2 == rj - half else 0)
	# ---- the stern castle: plated walls round a lit cabin, its windows aglow
	var cw := int(sp["castle"]) + rng.randi_range(0, 4)
	var ch := 10 + (2 if cls == "brig" else 0)
	var ct := deck - ch
	for i2 in range(x0, x0 + cw):
		for j3 in range(ct, deck):
			var wall := i2 < x0 + 2 or i2 >= x0 + cw - 2 or j3 < ct + 2
			if wall:
				_dark_plate(i2, j3)
			else:
				bg[j3 * w + i2] = Defs.PLANK
				bgv[j3 * w + i2] = (i2 / 5 + j3) % 3
	# (a roof edge of red tile, and its windows: glass in the walls, the cabin's lamp behind them)
	for i3 in range(x0 - 1, x0 + cw + 1):
		put(i3, ct - 1, Defs.TILE, 1)
	for wy in range(ct + 3, ct + 6):
		for wx in range(x0 + cw - 2, x0 + cw):
			put(wx, wy, Defs.GLASS)
		for wx2 in range(x0, x0 + 2):
			put(wx2, wy, Defs.GLASS)
	for lx in range(x0 + cw / 2 - 1, x0 + cw / 2 + 1):
		put(lx, ct + 2, Defs.EMBER, 1)
	# a red lantern hanging off the castle's stern
	for ly in 3:
		put(x0 - 2, ct - 1 + ly, Defs.TIMBER if ly == 0 else Defs.EMBER, 3)
	# ---- the engine: ember crystal glowing through the stern
	var e0 := deck + 2
	var e1 := maxi(e0 + 3, bots[x0] - 2)
	for j4 in range(e0, e1):
		for i4 in range(0, x0 + 2):
			put(i4, j4, Defs.EMBER, (i4 + j4) % 4)
	stern = Vector2i(0, (e0 + e1) / 2)
	# ---- masts and sails: black, tattered, the main one marked with a skull
	var mx := []
	if int(sp["masts"]) == 1:
		mx = [x0 + int(float(L) * 0.55)]
	else:
		mx = [x0 + int(float(L) * 0.44), x0 + int(float(L) * 0.72)]
	for mk in mx.size():
		var m0: int = mx[mk]
		var top := 2 + (4 if mk == 1 else 0)
		for j5 in range(top, deck):
			put(m0, j5, Defs.TIMBER, 0)
			put(m0 + 1, j5, Defs.TIMBER, 1)
		# the yard, and the pennant flying aft from the masthead
		var sw := 16 + rng.randi_range(0, 4) + (4 if cls == "brig" and mk == 0 else 0)
		for i5 in range(m0 - sw / 2, m0 + sw / 2 + 2):
			put(i5, top + 3, Defs.TIMBER, 0)
		for pk in 7:
			var ph := 1 if pk < 4 else 0
			for pj in range(-ph, ph + 1):
				put(m0 - 1 - pk, top + 1 + pj, Defs.TILE, 2 if pk % 2 == 0 else 1)
		# the sail: hung from the yard, bellied forward, ragged at its foot and edges
		var s_top := top + 4
		var s_bot := deck - 6
		for j6 in range(s_top, s_bot):
			var f := float(j6 - s_top) / float(maxi(1, s_bot - s_top))
			var belly := int(round(sin(f * PI) * 4.0))
			var l := m0 - sw / 2 + belly
			var r := m0 + sw / 2 + 1 + belly
			for i6 in range(l, r + 1):
				if i6 == m0 or i6 == m0 + 1:
					continue
				var edge := i6 <= l + 1 or i6 >= r - 1 or j6 >= s_bot - 2
				if edge and rng.randf() < 0.22:
					continue
				put(i6, j6, Defs.COAL, rng.randi_range(0, 2))
		if mk == 0:
			var sx := m0 + 2 + int(round(sin(0.5 * PI) * 4.0)) - 3
			var sy := s_top + (s_bot - s_top) / 2 - 5
			for qj in SKULL.size():
				var row: String = SKULL[qj]
				for qi in row.length():
					if row[qi] == "#":
						put(sx + qi, sy + qj, Defs.SNOW, 0)
	# ---- guns on deck: a copper carriage, a star-iron barrel run out toward the bow
	var gx := [x0 + int(float(L) * 0.82)]
	if int(sp["guns"]) > 1:
		gx = [x0 + int(float(L) * 0.84), x0 + cw + 6]
	guns = []
	for gi in gx:
		var g0: int = gi
		for j7 in range(deck - 3, deck):
			for i7 in range(g0, g0 + 5):
				put(i7, j7, Defs.COPPERBAR, 2 if j7 == deck - 3 else 0)
		for i8 in range(g0 + 3, g0 + 9):
			put(i8, deck - 4, Defs.STARIRON, 2)
			put(i8, deck - 5, Defs.STARIRON, 0)
		guns.append(Vector2i(g0 + 9, deck - 5))
	# ---- a rail along the deck, and the strongbox lashed down on the castle
	# (the strongbox sits on the castle's roof: open over it, clear of the sails)
	_crate_near(x0 + cw / 2 - CRATE_W / 2, ct - 1, "pirate", x0, x0 + cw)
	for i9 in range(x0 + cw, bow - 6):
		if (i9 - x0) % 6 == 0 and at(i9, deck - 1) == 0 and at(i9, deck - 2) == 0:
			put(i9, deck - 1, Defs.TIMBER, 0)
			put(i9, deck - 2, Defs.TIMBER, 0)
	rebuild()
	rad = maxf(3.0, sqrt(mass / PI))
	hp_max = float(sp["hp"])
	hp = hp_max
	fire_t = rng.randi_range(40, 90)
	side = 1 if rng.randf() < 0.5 else -1
	ang = 0.0
	omega = 0.0
	meta = {"cls": cls, "len": L, "deck": deck}
	_bg_dirty = true
	dirty = true

## a cell of its plating: dark, in courses, seams and rivets as a wreck's but blacker
func _dark_plate(i: int, j: int) -> void:
	var v := 2 if (j / 4) % 2 == 0 else 0
	if i % 12 == 0:
		v = 0
	elif (i % 12 == 1 or i % 12 == 11) and j % 4 == 1:
		v = 3
	put(i, j, Defs.HULL, v)

## where its guns fire from, in the world
func gun_world(k: int) -> Vector2:
	var gc: Vector2i = guns[k]
	return cell_world(gc.x, gc.y)

## its engine's place in the world (the stern)
func stern_world() -> Vector2:
	return cell_world(stern.x, stern.y)

## a gun still on its ship? (a barrel shot away fires no more)
func gun_ok(k: int) -> bool:
	var gc: Vector2i = guns[k]
	return at(gc.x - 1, gc.y) != 0 or at(gc.x - 2, gc.y) != 0
