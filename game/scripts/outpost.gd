## A trading outpost: a great living station grown from parts by its seed (user, 23 Nov: outposts with traders;
## then "much bigger more complex outposts"). It extends station.gd, so it is laid out the same way (a grid of
## rooms joined by doorways and hatches; see station.gd), streamed, drawn and collided like a derelict; but
## every room has power (gravity, light), nothing of it is dug or blasted (`guarded`), and it is busy:
##
##   the HANGAR   two rooms wide and two high at one end of the lowest deck, its outer wall open (MOUTH_H
##                high) onto a landing apron with lights and hazard stripes: the skiff (or a hull you built)
##                flies in and docks; you step out onto its floor.
##   the SHOPS    the lowest deck's rooms beside the hangar, one after another through doorways (no hatch
##                to climb): the MARKET nearest (role "outpost": salvage, ingots, trade goods), then the
##                SHIPWRIGHT ("shipwright": mending at the dock, plating, fuel, ship's parts), the CANTINA
##                ("cantina": meals, draughts and the job board) and the CARTOGRAPHER ("cartographer": star
##                charts, the Scanner Lens), in an order of the seed's. Each keeper (`keepers`, a `Trader`)
##                stands behind a counter drawn in front of them.
##   the rest     quarters, gardens, stores, a promenade with windows, an observatory up top, the reactor:
##                reached up through hatches.
##   spacers      folk who live and work here (`folk_plan`: seeds and rooms), walking their deck through its
##                doorways; space.gd makes and ticks them (`Spacer`) and they talk (F).
extends "res://scripts/station.gd"

const OP_A := ["Kestrel", "Lantern", "Halcyon", "Meridian", "Tinker's", "Wayfarer's", "Cinder", "Harbor",
	"Lodestar", "Driftwood", "Gilded", "Quiet", "Copper", "Starwatch"]
const OP_B := ["Post", "Station", "Haven", "Rest", "Landing", "Exchange", "Waystation", "Market"]
const MOUTH_H := 80                 # the hangar's open mouth (cells high, from its floor)
const SHOPS := ["market", "shipwright", "cantina", "charts"]
## a shop room's keeper: their towns.gd shop role, and what the room is called
const KEEP_ROLE := {"market": "outpost", "shipwright": "shipwright", "cantina": "cantina", "charts": "cartographer"}
const OP_ROOMS := {"hangar": "Hangar", "market": "Market", "shipwright": "Shipwright", "cantina": "Cantina",
	"charts": "Cartographer", "quarters": "Quarters", "hydro": "Gardens", "reactor": "Reactor", "stores": "Stores",
	"promenade": "Promenade", "observatory": "Observatory", "hall": "Hall"}
## each shop's colour (its counter's front, its sign)
const SHOP_COL := {"market": Color(1.0, 0.82, 0.4), "shipwright": Color(0.6, 0.78, 0.95), "cantina": Color(0.95, 0.55, 0.35),
	"charts": Color(0.7, 0.6, 1.0)}

var hangar := -1
var hangar_side := -1        # -1: the hangar is at the -x end, its mouth facing -x; 1: the +x end
var sys := -1                # the star system it serves (galaxy.gd), when known: the job board's courier runs
var keepers := []            # [Trader]: one per shop room
var folk_plan := []          # [{"fseed", "room", "b"}]: the spacers who live here
var _trader = null
# (`halls`, from station.gd: made for docking, its halls, the instance you walk; else the shell seen out in space)

## a keeper behind a counter: what towns.gd's shop and ui.gd's panel need of one
class Trader:
	var role := "outpost"        # (towns.gd's shop: "outpost" is the market)
	var shop := "market"         # (the room's role)
	var name := ""
	var town := {}
	var fseed := 0
	var pos := Vector2.ZERO
	var facing := -1
	var room := -1
	var b := Vector2.ZERO        # feet (cells, from the corner)
	var tex: ImageTexture
	var counter: ImageTexture

static func outpost_name(sd: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd ^ 0x7057
	return "%s %s" % [OP_A[rng.randi_range(0, OP_A.size() - 1)], OP_B[rng.randi_range(0, OP_B.size() - 1)]]

## (user, 25 Nov: "derelict ships and outposts and so on should be redesigned so that you press a button to dock
## and go inside an instanced area so we can make them larger and more intricate with their own scenery"):
## `halls` (made with in_side) are its halls for docking (pocket.gd's "outpost" place): a deck more and more rooms, more folk, the
## hangar open onto space; the shell out in space is the same station with its hangar's mouth sealed behind a
## force-field pane and nobody walking it (you dock with F as you fly by).
static func make_outpost(sd: int, system := -1, in_side := false) -> RefCounted:
	var op = load("res://scripts/outpost.gd").new()
	op.sys = system
	op.halls = in_side
	op._build_outpost(sd)
	return op

func _build_outpost(sd: int) -> void:
	seed_ = sd
	kind = "outpost"
	wname = outpost_name(sd)
	fate = ""
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	cols = rng.randi_range(6, 7)
	rows = 3
	if halls:
		cols = rng.randi_range(8, 9)
		rows = 4
	var lo := rows - 1               # (the lowest deck's row: the shops, and the hangar's lower half)
	setup(OX * 2 + cols * PX + T, OY * 2 + rows * PY + T)
	var noise := FastNoiseLite.new()
	noise.seed = sd
	noise.frequency = 0.09
	hangar_side = -1 if rng.randf() < 0.5 else 1
	var hc0: int = 0 if hangar_side < 0 else cols - 2
	var inner: int = hc0 + 2 if hangar_side < 0 else hc0 - 1      # (the column beside the hangar)
	# ---- the rooms: the hangar (2 x 2 cells of the grid) first, then every other cell; a top corner away
	# from the hangar sometimes left out
	var hx0: int = OX + T + hc0 * PX
	var hy0: int = OY + T + (lo - 1) * PY
	hangar = 0
	mods.append({"c": hc0, "r": lo - 1, "x0": hx0, "y0": hy0, "x1": hx0 + 2 * MW + T, "y1": hy0 + 2 * MH + T, "role": "hangar",
		"powered": true, "links": [], "cells": [Vector2i(hc0, lo - 1), Vector2i(hc0 + 1, lo - 1), Vector2i(hc0, lo), Vector2i(hc0 + 1, lo)]})
	for hv in mods[0]["cells"]:
		grid[hv] = 0
	var far_corner := Vector2i(cols - 1 if hangar_side < 0 else 0, 0)
	var drop_corner := rng.randf() < 0.5
	for r in rows:
		for c in cols:
			var v := Vector2i(c, r)
			if grid.has(v) or (drop_corner and v == far_corner):
				continue
			var x0: int = OX + T + c * PX
			var y0: int = OY + T + r * PY
			grid[v] = mods.size()
			mods.append({"c": c, "r": r, "x0": x0, "y0": y0, "x1": x0 + MW, "y1": y0 + MH, "role": "hall", "powered": true,
				"links": [], "cells": [v]})
	# ---- how they join: a spanning tree over every room but the hangar, then loops; the lowest deck is one
	# run of doorways (the shops: no hatch to climb), and the hangar opens onto it
	var edges := {}
	var seen := {1: true}
	var stack := [1]
	while not stack.is_empty():
		var cur: int = stack[stack.size() - 1]
		var fresh := []
		for n in _op_nb(cur):
			if not seen.has(n):
				fresh.append(n)
		if fresh.is_empty():
			stack.pop_back()
			continue
		var n2: int = fresh[rng.randi_range(0, fresh.size() - 1)]
		seen[n2] = true
		edges[_ekey(cur, n2)] = true
		stack.append(n2)
	for i2 in range(1, mods.size()):
		for n3 in _op_nb(i2):
			if n3 > i2 and not edges.has(_ekey(i2, n3)) and rng.randf() < 0.45:
				edges[_ekey(i2, n3)] = true
	var deck := []                 # (the lowest deck's rooms, from the hangar outward)
	var c2: int = inner
	while c2 >= 0 and c2 < cols:
		deck.append(int(grid[Vector2i(c2, lo)]))
		c2 -= hangar_side
	for d in range(deck.size() - 1):
		edges[_ekey(deck[d], deck[d + 1])] = true
	edges[_ekey(hangar, deck[0])] = true
	_link(edges)
	dock = hangar
	# ---- roles: the shops along the lowest deck (the market by the hangar), the reactor up top far from it,
	# the rest from a pool
	var rest_shops := ["shipwright", "cantina", "charts"]
	for k in range(rest_shops.size() - 1, 0, -1):
		var sw := rng.randi_range(0, k)
		var tmp: String = rest_shops[k]
		rest_shops[k] = rest_shops[sw]
		rest_shops[sw] = tmp
	var shop_order: Array = ["market"] + rest_shops
	for d2 in deck.size():
		mods[deck[d2]]["role"] = shop_order[d2] if d2 < shop_order.size() else "stores"
	var dist := _bfs(hangar)
	reactor = -1
	for i3 in range(1, mods.size()):
		if int(mods[i3]["r"]) == lo:
			continue
		if reactor < 0 or int(dist[i3]) > int(dist[reactor]):
			reactor = i3
	if reactor >= 0:
		mods[reactor]["role"] = "reactor"
	var pool := ["quarters", "hydro", "stores", "promenade", "quarters", "hydro", "promenade", "hall"]
	var obs := false
	for i4 in range(1, mods.size()):
		var md: Dictionary = mods[i4]
		if String(md["role"]) != "hall" or i4 == reactor:
			continue
		if int(md["r"]) == 0 and not obs:
			md["role"] = "observatory"
			obs = true
			continue
		md["role"] = pool[rng.randi_range(0, pool.size() - 1)]
	# ---- the shell: plating round every room, then each hollowed out (the hangar's inner walls with it)
	for md2 in mods:
		for j in range(int(md2["y0"]) - T, int(md2["y1"]) + T):
			for i in range(int(md2["x0"]) - T, int(md2["x1"]) + T):
				_plate(i, j)
	for md3 in mods:
		for j2 in range(int(md3["y0"]), int(md3["y1"])):
			for i5 in range(int(md3["x0"]), int(md3["x1"])):
				cells[j2 * w + i5] = 0
	# ---- doorways and hatches
	for ek in edges:
		var ab: Array = _ekey_parts(ek)
		var ma: Dictionary = mods[ab[0]]
		var mb: Dictionary = mods[ab[1]]
		if ab[0] == hangar or ab[1] == hangar:
			var other: Dictionary = mb if ab[0] == hangar else ma
			if hangar_side < 0:
				_doorway(int(mods[hangar]["x1"]), int(mods[hangar]["y1"]), false)
			else:
				_doorway(int(other["x1"]), int(other["y1"]), false)
			continue
		if int(ma["r"]) == int(mb["r"]):
			var left: Dictionary = ma if int(ma["c"]) < int(mb["c"]) else mb
			_doorway(int(left["x1"]), int(left["y1"]), false)
		else:
			var up: Dictionary = ma if int(ma["r"]) < int(mb["r"]) else mb
			var dn: Dictionary = mb if int(ma["r"]) < int(mb["r"]) else ma
			var hx: int = (int(up["x0"]) + int(up["x1"])) / 2 + rng.randi_range(-14, 14)
			_hatch(hx, int(up["y1"]), int(dn["y0"]), false)
	# ---- the hangar's mouth and its landing apron
	var hm: Dictionary = mods[hangar]
	var wx0: int = int(hm["x0"]) - T if hangar_side < 0 else int(hm["x1"])
	var hy1: int = int(hm["y1"])
	ways.append(Rect2i(wx0, hy1 - MOUTH_H, T, MOUTH_H))
	for j3 in range(hy1 - MOUTH_H, hy1):
		for i6 in range(wx0, wx0 + T):
			cells[j3 * w + i6] = 0
	if not halls:
		# (out in space its mouth is sealed: a force-field pane, glowing at its edges; you dock with F)
		var pane: int = wx0 + T / 2
		for j5 in range(hy1 - MOUTH_H, hy1):
			put(pane, j5, Defs.FROST if (j5 - (hy1 - MOUTH_H)) % 9 == 0 else Defs.GLASS, j5 & 3)
	var apron0: int = wx0 - 40 if hangar_side < 0 else wx0 + T
	for i7 in range(apron0, apron0 + 40):
		for j4 in range(hy1, hy1 + T):
			_plate(i7, j4)
		if (i7 - apron0) % 6 == 2:
			put(i7, hy1, Defs.CRYSTAL, 0)
	for i8 in range(mini(apron0, wx0), maxi(apron0 + 40, wx0 + T)):
		for jj in [hy1 - MOUTH_H - 1, hy1 - MOUTH_H - 2, hy1 + T - 1]:
			if at(i8, int(jj)) != 0:
				put(i8, int(jj), Defs.COAL if ((i8 + int(jj)) / 3) % 2 == 0 else Defs.SUNSTONE, 0)
	# ---- each room dressed (the station's own looks with power, then an outpost's)
	for k2 in mods.size():
		_dress(k2, rng, noise)
		_dress_op(k2, rng, noise)
	_outside_op(rng)
	# ---- the keepers and the folk
	for d3 in deck.size():
		var role: String = mods[deck[d3]]["role"]
		if not KEEP_ROLE.has(role):
			continue
		var kp := Trader.new()
		kp.shop = role
		kp.role = String(KEEP_ROLE[role])
		kp.room = deck[d3]
		kp.fseed = (seed_ ^ 0x51ED) + d3 * 7919
		kp.name = load("res://scripts/folk_art.gd").name_for(kp.fseed)
		kp.town = {"name": wname, "seed": seed_, "sys": sys}
		kp.facing = hangar_side
		var mk: Dictionary = mods[deck[d3]]
		kp.b = Vector2(float(int(mk["x0"]) + int(mk["x1"])) * 0.5 - float(hangar_side) * 14.0, float(int(mk["y1"])))
		keepers.append(kp)
	var nfolk := rng.randi_range(13, 17) if halls else 0       # (outside, nobody walks the shell)
	var homes := []
	for i9 in range(1, mods.size()):
		homes.append(i9)
	for f in nfolk:
		var hr: int = homes[rng.randi_range(0, homes.size() - 1)]
		if f < 3:
			hr = deck[rng.randi_range(0, deck.size() - 1)]      # (the deck is always busy)
		var fm: Dictionary = mods[hr]
		var fx := float(rng.randi_range(int(fm["x0"]) + 10, int(fm["x1"]) - 10))
		folk_plan.append({"fseed": (seed_ * 31 + f * 104729) & 0xFFFFFF, "room": hr, "b": Vector2(fx, float(int(fm["y1"])) - 9.5)})
	meta = {"rooms": mods.size(), "hangar": hangar, "deck": deck, "reactor": reactor}
	rebuild()
	rad = maxf(3.0, sqrt(mass / PI))
	ang = 0.0
	omega = 0.0
	_bg_dirty = true
	dirty = true

## the rooms beside room i (the hangar's four cells all count), never the hangar itself
func _op_nb(i: int) -> Array:
	var out := []
	for cv in mods[i]["cells"]:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var v: Vector2i = (cv as Vector2i) + d
			if grid.has(v):
				var n := int(grid[v])
				if n != i and n != hangar and not out.has(n):
					out.append(n)
	return out

## an outpost's own looks, over the station's (`_dress`, with power)
func _dress_op(k: int, rng: RandomNumberGenerator, noise: FastNoiseLite) -> void:
	var md: Dictionary = mods[k]
	var x0: int = md["x0"]
	var y0: int = md["y0"]
	var x1: int = md["x1"]
	var y1: int = md["y1"]
	var mx := (x0 + x1) / 2
	match String(md["role"]):
		"hangar":
			# a bay: dark ribbed back wall, a gantry along the roof with hooks, landing lights and clamps
			for j in range(y0, y1):
				for i in range(x0, x1):
					var rib := (i - x0) % 16 == 0 or (i - x0) % 16 == 1
					bg[j * w + i] = Defs.HULL if rib else Defs.COAL
					bgv[j * w + i] = 2 if rib else (0 if (j / 6) % 2 == 0 else 1)
					if j == y0 + 30 and not rib:
						bg[j * w + i] = Defs.SUNSTONE if ((i / 3) % 2) == 0 else Defs.COAL
			for i2 in range(x0, x1):
				put(i2, y1, Defs.SUNSTONE if ((i2 / 4) % 2) == 0 else Defs.HULL, 0)
				if (i2 - x0) % 10 == 5:
					put(i2, y1, Defs.CRYSTAL, 0)
				if not _near_way(i2, y0, 2):
					put(i2, y0, Defs.COPPERBAR, 2)
			for hk in range(x0 + 30, x1 - 20, 46):
				for jh in range(y0 + 1, y0 + 14):
					bg[jh * w + hk] = Defs.TIMBER
				bg[(y0 + 14) * w + hk - 1] = Defs.COPPERBAR
				bg[(y0 + 14) * w + hk + 1] = Defs.COPPERBAR
			# fuel lines down the back wall, a pump with a glowing gauge
			for fx in [x0 + 12, x1 - 12]:
				for jf in range(y0 + 2, y1):
					bg[jf * w + int(fx)] = Defs.COPPERBAR
					bgv[jf * w + int(fx)] = 1
				for jp in range(y1 - 14, y1):
					for ip in range(int(fx) - 3, int(fx) + 4):
						bg[jp * w + ip] = Defs.HULL
						bgv[jp * w + ip] = 2
				bg[(y1 - 10) * w + int(fx)] = Defs.WISPCELL
		"market":
			# a striped awning over the counter, shelves of goods in crates, banners
			for i3 in range(x0 + 4, x1 - 4):
				for ja in range(y0 + 8, y0 + 12):
					bg[ja * w + i3] = Defs.TILE if ((i3 - x0) / 4) % 2 == 0 else Defs.SNOW
					bgv[ja * w + i3] = 0
				if (i3 - x0) % 4 == 2:
					bg[(y0 + 12) * w + i3] = Defs.TILE
			for row in [y1 - 16, y1 - 28]:
				for i4 in range(x0 + 3, x1 - 3):
					bg[int(row) * w + i4] = Defs.TIMBER
					bgv[int(row) * w + i4] = 0
				for cb in range(x0 + 4, x1 - 8, 6):
					var cm: int = [Defs.PLANK, Defs.TILE, Defs.WISPBAR, Defs.SUNSTONE, Defs.LEAF, Defs.COPPERBAR][rng.randi_range(0, 5)]
					for j5 in range(int(row) - 4, int(row)):
						for i5 in range(cb, cb + 4):
							bg[j5 * w + i5] = cm
							bgv[j5 * w + i5] = (i5 + j5) % 3
		"shipwright":
			# a hull frame up on the wall (copper ribs), plates racked, a crane with its hook, tools on a board
			var fc := Vector2(float(mx) + 8.0, float(y0) + 18.0)
			for i6 in range(x0 + 6, x1 - 6):
				for j6 in range(y0 + 4, y0 + 30):
					var e := pow((float(i6) - fc.x) / 26.0, 2.0) + pow((float(j6) - fc.y) / 10.0, 2.0)
					if e <= 1.0 and j6 >= int(fc.y) and ((i6 - x0) % 6 == 0 or e > 0.8):
						bg[j6 * w + i6] = Defs.COPPERBAR
						bgv[j6 * w + i6] = 2
			for rk in 5:
				for jr in range(y1 - 20, y1 - 2):
					bg[jr * w + x0 + 4 + rk * 3] = Defs.HULL
					bgv[jr * w + x0 + 4 + rk * 3] = 2 if rk % 2 == 0 else 0
			for i7 in range(x1 - 22, x1 - 6):
				for j7 in range(y1 - 26, y1 - 16):
					bg[j7 * w + i7] = Defs.PLANK
					bgv[j7 * w + i7] = 1
				if (i7 - x1) % 3 == 0:
					bg[(y1 - 22) * w + i7] = Defs.COPPERBAR
					bg[(y1 - 21) * w + i7] = Defs.HULL
		"cantina":
			# a bar's back shelves of bottles, lanterns, tables, the job board
			for row2 in [y0 + 12, y0 + 20]:
				for i8 in range(x0 + 6, x0 + 40):
					bg[int(row2) * w + i8] = Defs.TIMBER
					bgv[int(row2) * w + i8] = 0
				for bx in range(x0 + 7, x0 + 39, 3):
					var bm: int = [Defs.GLASS, Defs.EMBER, Defs.WISP, Defs.LEAF, Defs.CRYSTAL][rng.randi_range(0, 4)]
					for jb in range(int(row2) - 3, int(row2)):
						bg[jb * w + bx] = bm
						bgv[jb * w + bx] = 1
			for lx in range(x0 + 10, x1 - 6, 18):
				for jl in range(y0, y0 + 6):
					bg[jl * w + lx] = Defs.TIMBER
				for jl2 in range(y0 + 6, y0 + 9):
					bg[jl2 * w + lx] = Defs.EMBER
					bg[jl2 * w + lx + 1] = Defs.EMBER
			for tx in [x0 + 48, x0 + 66]:
				for it in range(int(tx) - 5, int(tx) + 6):
					bg[(y1 - 9) * w + it] = Defs.PLANK
				for jt in range(y1 - 8, y1):
					bg[jt * w + int(tx)] = Defs.TIMBER
			# the job board: a plank board with notes pinned on it
			for jj in range(y0 + 26, y0 + 38):
				for ij in range(x1 - 20, x1 - 4):
					var edge := jj == y0 + 26 or jj == y0 + 37 or ij == x1 - 20 or ij == x1 - 5
					bg[jj * w + ij] = Defs.TIMBER if edge else Defs.PLANK
					bgv[jj * w + ij] = 0 if edge else 2
			for nt in 4:
				var nx := x1 - 18 + (nt % 2) * 7
				var ny := y0 + 28 + (nt / 2) * 5
				for jn in range(ny, ny + 3):
					for i_n in range(nx, nx + 5):
						bg[jn * w + i_n] = Defs.SNOW
						bgv[jn * w + i_n] = 0
		"charts":
			# a great star map on the wall, an orrery's rings
			for j9 in range(y0 + 4, y1 - 14):
				for i9 in range(x0 + 6, x0 + 50):
					var edge2 := j9 == y0 + 4 or j9 == y1 - 15 or i9 == x0 + 6 or i9 == x0 + 49
					bg[j9 * w + i9] = Defs.COPPERBAR if edge2 else Defs.COAL
					bgv[j9 * w + i9] = 2 if edge2 else 0
					if not edge2 and noise.get_noise_2d(i9 * 7.0, j9 * 7.0) > 0.42:
						bg[j9 * w + i9] = Defs.CRYSTAL if (i9 + j9) % 3 != 0 else Defs.WISP
			var oc := Vector2(float(x1) - 16.0, float(y0) + 16.0)
			for j10 in range(y0 + 2, y0 + 32):
				for i10 in range(x1 - 32, x1 - 1):
					var dd := Vector2(float(i10) - oc.x, (float(j10) - oc.y) * 1.6).length()
					if absf(dd - 12.0) < 0.7 or absf(dd - 7.0) < 0.6:
						bg[j10 * w + i10] = Defs.COPPERBAR
					elif dd < 2.5:
						bg[j10 * w + i10] = Defs.SUNSTONE
		"promenade":
			# great windows onto the stars, planters under them, benches
			for wx in range(x0 + 6, x1 - 14, 24):
				for j11 in range(y0 + 6, y1 - 14):
					for i11 in range(wx, wx + 18):
						var frame := i11 == wx or i11 == wx + 17 or j11 == y0 + 6 or j11 == y1 - 15 or (i11 - wx) == 8
						bg[j11 * w + i11] = Defs.COPPERBAR if frame else Defs.GLASS
						bgv[j11 * w + i11] = 2 if frame else 0
				for i12 in range(wx, wx + 18):
					for j12 in range(y1 - 14, y1 - 10):
						bg[j12 * w + i12] = Defs.LEAF if noise.get_noise_2d(i12 * 4.0, j12 * 4.0) > -0.2 else Defs.MOSSBLOCK
						bgv[j12 * w + i12] = (i12 + j12) % 4
					bg[(y1 - 10) * w + i12] = Defs.PLANK
		"observatory":
			# a telescope on its mount, aimed up through the roof's windows
			for q in 30:
				var tp := Vector2(float(mx) - 8.0 + float(q) * 0.55, float(y1) - 12.0 - float(q) * 0.8)
				for t2 in range(-2, 3):
					var pi := int(tp.x) + t2
					var pj := int(tp.y)
					if pi > x0 and pi < x1 and pj > y0:
						bg[pj * w + pi] = Defs.COPPERBAR if q < 26 else Defs.GLASS
			for jm in range(y1 - 12, y1):
				for im in range(mx - 9, mx - 6):
					bg[jm * w + im] = Defs.HULL
					bgv[jm * w + im] = 2

## the outside: windows in the roofs, masts and beacons, trusses under, solar wings at the far end, a
## comms dish, the hangar's beacons either side of its mouth
func _outside_op(rng: RandomNumberGenerator) -> void:
	for mi in mods.size():
		if mi == hangar:
			continue
		var md: Dictionary = mods[mi]
		var v := Vector2i(int(md["c"]), int(md["r"]))
		var x0: int = md["x0"]
		var x1: int = md["x1"]
		var y0: int = md["y0"]
		var y1: int = md["y1"]
		if not grid.has(v + Vector2i(0, -1)):
			for i in range(x0 + 6, x1 - 6):
				if (i - x0) % 12 < 8 and at(i, y0 - 2) == Defs.HULL:
					put(i, y0 - 2, Defs.GLASS, 0)
					put(i, y0 - 3, Defs.GLASS, 0)
			if rng.randf() < 0.55:
				var mx := rng.randi_range(x0 + 10, x1 - 10)
				var top := y0 - T - rng.randi_range(14, OY - 8)
				for j in range(top, y0 - T):
					put(mx, j, Defs.TIMBER, 0)
					if (j - top) % 5 == 0:
						put(mx - 1, j, Defs.COPPERBAR, 0)
						put(mx + 1, j, Defs.COPPERBAR, 0)
				for j2 in range(top - 3, top):
					for i2 in range(mx - 1, mx + 2):
						put(i2, j2, Defs.EMBER, 1)
			elif String(md["role"]) != "observatory" and rng.randf() < 0.5:
				# a comms dish on a short mast
				var dx := rng.randi_range(x0 + 16, x1 - 16)
				for jd in range(y0 - T - 8, y0 - T):
					put(dx, jd, Defs.HULL, 2)
				for q in range(-9, 10):
					var dy := int(round(float(q * q) / 14.0))
					put(dx + q, y0 - T - 9 - dy, Defs.COPPERBAR if absi(q) < 9 else Defs.HULL, 2)
				put(dx, y0 - T - 16, Defs.CRYSTAL, 0)
		if not grid.has(v + Vector2i(0, 1)):
			for i3 in range(x0 - 2, x1 + 2):
				var depth := 12 + int(5.0 * sin(float(i3) * 0.05))
				for j3 in range(y1 + T, y1 + T + depth):
					var dj := j3 - y1 - T
					if dj == depth - 1 or (i3 + dj) % 12 == 0 or (i3 - dj) % 12 == 0:
						put(i3, j3, Defs.COPPERBAR if dj == depth - 1 else Defs.HULL, 2)
		for side in [-1, 1]:
			if grid.has(v + Vector2i(side, 0)) or side == hangar_side and int(md["r"]) >= 1:
				continue
			var a0: int = x0 - T - 1 if side < 0 else x1 + T
			var my := (y0 + y1) / 2
			for q2 in OX - 6:
				var i4: int = a0 + side * q2
				put(i4, my, Defs.HULL, 0)
				put(i4, my + 1, Defs.HULL, 2)
				if q2 > 3 and q2 % 10 < 7:
					for j4 in range(my - 12, my - 2):
						put(i4, j4, Defs.WISPBAR if (j4 - my) % 3 != 0 else Defs.COPPERBAR, 0)
					for j5 in range(my + 4, my + 14):
						put(i4, j5, Defs.WISPBAR if (j5 - my) % 3 != 0 else Defs.COPPERBAR, 0)
	# trusses under the hangar, beacons either side of its mouth
	var hm: Dictionary = mods[hangar]
	for i5 in range(int(hm["x0"]) - 2, int(hm["x1"]) + 2):
		var depth2 := 14 + int(6.0 * sin(float(i5) * 0.04))
		for j6 in range(int(hm["y1"]) + T, int(hm["y1"]) + T + depth2):
			var dj2 := j6 - int(hm["y1"]) - T
			if dj2 == depth2 - 1 or (i5 + dj2) % 12 == 0 or (i5 - dj2) % 12 == 0:
				put(i5, j6, Defs.COPPERBAR if dj2 == depth2 - 1 else Defs.HULL, 2)
	var bx: int = int(hm["x0"]) - T - 2 if hangar_side < 0 else int(hm["x1"]) + T + 1
	for by in [int(hm["y1"]) - MOUTH_H - 6, int(hm["y1"]) + T + 1]:
		for jb in range(int(by), int(by) + 3):
			for ib in range(bx - 1, bx + 2):
				put(ib, jb, Defs.EMBER, 1)

# ----------------------------------------------------------------- queries --

func role_name(k: int) -> String:
	return String(OP_ROOMS.get(String(mods[k]["role"]), "A hall")) if k >= 0 else ""

## a room by its role (-1 if it has none)
func room_of(role: String) -> int:
	for k in mods.size():
		if String(mods[k]["role"]) == role:
			return k
	return -1

## the keeper of a shop room by its role ("market", "shipwright", "cantina", "charts"), or null
func keeper(shop: String) -> Variant:
	for kp in keepers:
		if kp.shop == shop:
			kp.pos = to_world(kp.b - com)
			return kp
	return null

## the market's keeper (the trader of old: towns.gd's "outpost" shop)
func trader():
	if _trader == null:
		_trader = keeper("market")
	_trader.pos = to_world(_trader.b - com)
	return _trader

## where the market's keeper's feet are, in the world
func keeper_world() -> Vector2:
	return to_world(trader().b - com)

## a keeper's picture (made once)
func keeper_texture(kp = null) -> ImageTexture:
	if kp == null:
		kp = trader()
	if kp.tex == null:
		var apron := {"outpost": "shop", "shipwright": "smithy", "cantina": "tavern", "cartographer": "inn"}
		var fr: Dictionary = load("res://scripts/folk_art.gd").frames(kp.fseed, String(apron.get(kp.role, "shop")))
		kp.tex = ImageTexture.create_from_image(fr["stand"])
	return kp.tex

## a keeper's counter (17 x 9): a copper top, a front panel in the shop's colour, drawn in front of them
func counter_texture(kp) -> ImageTexture:
	if kp.counter == null:
		var im := Image.create(17, 9, false, Image.FORMAT_RGBA8)
		var col: Color = SHOP_COL.get(kp.shop, Color(0.8, 0.8, 0.8))
		for y in 9:
			for x in 17:
				var c := Color(0.42, 0.29, 0.17) if (x + y / 3) % 5 != 0 else Color(0.34, 0.22, 0.12)
				if y <= 1:
					c = Color(0.86, 0.55, 0.3) if y == 0 else Color(0.62, 0.36, 0.18)
				elif y >= 4 and y <= 5 and x > 1 and x < 15:
					c = col.darkened(0.15 if y == 5 else 0.0)
				if x == 0 or x == 16 or y == 8:
					c = Color(0.18, 0.12, 0.07)
				im.set_pixel(x, y, c)
		kp.counter = ImageTexture.create_from_image(im)
	return kp.counter

## is a world point inside the hangar (the skiff docked there)?
func in_hangar(p: Vector2) -> bool:
	var b := to_body(p) + com
	var hm: Dictionary = mods[hangar]
	return Rect2(Vector2(int(hm["x0"]), int(hm["y0"])), Vector2(int(hm["x1"]) - int(hm["x0"]), int(hm["y1"]) - int(hm["y0"]))).grow(2.0).has_point(b)

## the hangar's inside (body cells)
func hangar_rect() -> Rect2i:
	var hm: Dictionary = mods[hangar]
	return Rect2i(int(hm["x0"]), int(hm["y0"]), int(hm["x1"]) - int(hm["x0"]), int(hm["y1"]) - int(hm["y0"]))

## rooms joined to room k by a doorway on its own deck (spacers walk only those)
func walk_links(k: int) -> Array:
	var out := []
	for n in mods[k]["links"]:
		if int(n) != hangar and int(mods[n]["r"]) == int(mods[k]["r"]) and k != hangar:
			out.append(int(n))
	return out

## an outpost never changes (nothing taken, nothing broken): grown again the same
func state() -> Dictionary:
	return {}

func apply_state(_d: Dictionary) -> void:
	pass
