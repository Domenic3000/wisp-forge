## A derelict space station: a great wreck of rooms grown from parts by its seed (user, 23 Nov: "much
## bigger more complex outposts ... Derelict space stations and everything with aliens and such to
## fight"; inside, chosen "Both, by section": powered sections keep their gravity, broken ones have lost it).
## It extends wreck.gd, so space.gd streams it with its sector, draws it with its back layer and collides
## you with it; nothing of it is dug or blasted (`guarded`), and it never drifts. What changes as you
## explore (caches opened, aliens killed, the vault's seal broken) is kept apart in space.gd `station_state`
## by its seed, and the station is grown again the same each time it streams in.
##
## `Station.make_station(seed)` lays out a grid of MODULES (rooms MW x MH inside, walls T thick), some
## corners left out, joined by a spanning tree plus a few loops: side by side through a DOORWAY at floor
## level (26 high), one over the other through a HATCH in the floor (22 wide, a one-way SCAFFOLD floor you
## jump up through or drop down through, with a scaffold ledge halfway down to climb by). Each room has a
## role: the DOCK (an open mouth in the outer wall with a docking arm, where you come in), the REACTOR (a
## wisp core: the power), hydroponics, quarters, a lab, stores, halls; the farthest room from the dock is
## the VAULT, reached only through the alien NEST before it, its way in sealed with runestone until the
## nest's Broodmother falls. Rooms near the reactor are POWERED: gravity runes glow in their floors, lamps
## burn, the walls are clean panels. The rest are BROKEN: no gravity, dark, scorched, torn open to space.
## `spawns` lists the aliens that live here (alien.gd), `caches` the crates (wreck.gd's), `mods` the rooms.
extends "res://scripts/wreck.gd"

const MW := 80            # a room's inside: width, height (cells)
const MH := 44
const T := 4              # walls
const PX := MW + T        # (room pitch)
const PY := MH + T
const OX := 44            # margins round the grid: the docking arm and wings at the sides,
const OY := 36            # masts on top, trusses under it
const DOOR_H := 26
const HATCH_W := 22
const VAULT_CRATE := "vault"

const ST_A := ["Halcyon", "Meridian", "Concord", "Aurora", "Bastion", "Vigil", "Zenith", "Solace", "Tessera",
	"Harrow", "Lumen", "Cassia", "Obelisk", "Perihelion", "Threnody", "Wayward"]
const ST_B := ["Station", "Array", "Spire", "Citadel", "Platform", "Hub", "Observatory", "Foundry"]
const ST_FATES := ["Something came aboard with the last supply run, and stayed.",
	"Its crew sealed the vault and fled; the hive took the rest.",
	"The reactor still hums, but nobody has answered a hail in years.",
	"A storm belt's lightning broke its back; the dark halls belong to the swarm now.",
	"Its log speaks of eggs found in an asteroid, and then of nothing at all."]
const ROLE_NAMES := {"dock": "Docking bay", "reactor": "Reactor", "hydro": "Hydroponics", "quarters": "Quarters",
	"lab": "Laboratory", "stores": "Stores", "hall": "Hall", "nest": "The nest", "vault": "The vault"}

var cols := 0
var rows := 0
var mods := []            # [{"c", "r", "x0", "y0", "x1", "y1" (inside, exclusive), "role", "powered", "links": [index]}]
var grid := {}            # Vector2i(c, r) -> index into mods
var spawns := []          # [{"id", "kind", "b" (body cell coords of its middle), "mod"}]
var seal_cells := PackedInt32Array()   # the runestone over the vault's way in (cleared when the seal breaks)
var seal_open := false
var dock := -1
var nest := -1
var vault := -1
var reactor := -1
var dock_side := -1       # -1: the dock's mouth faces -x; 1: +x
var ways := []            # [Rect2i]: doorways, hatches (with the ledge under them), the dock's mouth: kept clear

static func station_name(sd: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd ^ 0x5717
	return "%s %s" % [ST_A[rng.randi_range(0, ST_A.size() - 1)], ST_B[rng.randi_range(0, ST_B.size() - 1)]]

static func make_station(sd: int) -> RefCounted:
	var st = load("res://scripts/station.gd").new()
	st._build_station(sd)
	return st

func _build_station(sd: int) -> void:
	seed_ = sd
	kind = "station"
	wname = station_name(sd)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	fate = ST_FATES[rng.randi_range(0, ST_FATES.size() - 1)]
	cols = rng.randi_range(4, 6)
	rows = rng.randi_range(2, 3)
	setup(OX * 2 + cols * PX + T, OY * 2 + rows * PY + T)
	var noise := FastNoiseLite.new()
	noise.seed = sd
	noise.frequency = 0.09
	# ---- which rooms are there: the whole grid, but a corner or two left out
	var have := {}
	for r in rows:
		for c in cols:
			have[Vector2i(c, r)] = true
	for corner in [Vector2i(0, 0), Vector2i(cols - 1, 0), Vector2i(0, rows - 1), Vector2i(cols - 1, rows - 1)]:
		if have.size() > cols * rows - 3 and rng.randf() < 0.4:
			have.erase(corner)
	for v in have:
		var x0: int = OX + T + v.x * PX
		var y0: int = OY + T + v.y * PY
		grid[v] = mods.size()
		mods.append({"c": v.x, "r": v.y, "x0": x0, "y0": y0, "x1": x0 + MW, "y1": y0 + MH, "role": "hall", "powered": false, "links": []})
	# ---- how they join: a spanning tree (random depth-first), then a few loops
	var edges := {}
	var seen := {0: true}
	var stack := [0]
	while not stack.is_empty():
		var cur: int = stack[stack.size() - 1]
		var nb := _neighbours(cur)
		var fresh := []
		for n in nb:
			if not seen.has(n):
				fresh.append(n)
		if fresh.is_empty():
			stack.pop_back()
			continue
		var n2: int = fresh[rng.randi_range(0, fresh.size() - 1)]
		seen[n2] = true
		edges[_ekey(cur, n2)] = true
		stack.append(n2)
	for i2 in mods.size():
		for n3 in _neighbours(i2):
			if n3 > i2 and not edges.has(_ekey(i2, n3)) and rng.randf() < 0.3:
				edges[_ekey(i2, n3)] = true
	# ---- the dock: a room on an outer side (the lowest row it can), facing out
	var cands := []
	for i3 in mods.size():
		var md: Dictionary = mods[i3]
		var v3 := Vector2i(int(md["c"]), int(md["r"]))
		if not grid.has(v3 + Vector2i(-1, 0)) or not grid.has(v3 + Vector2i(1, 0)):
			cands.append(i3)
	cands.sort_custom(func(a, b): return int(mods[a]["r"]) > int(mods[b]["r"]))
	var lowest: int = int(mods[cands[0]]["r"])
	var low := []
	for i4 in cands:
		if int(mods[i4]["r"]) == lowest:
			low.append(i4)
	dock = low[rng.randi_range(0, low.size() - 1)]
	var dv := Vector2i(int(mods[dock]["c"]), int(mods[dock]["r"]))
	dock_side = -1 if not grid.has(dv + Vector2i(-1, 0)) else 1
	# ---- the vault: the farthest room from the dock, reached only through the nest before it
	_link(edges)
	var dist := _bfs(dock)
	vault = 0
	for i5 in mods.size():
		if int(dist[i5]) > int(dist[vault]) or (int(dist[i5]) == int(dist[vault]) and rng.randf() < 0.5):
			vault = i5
	if vault == dock:
		vault = (dock + 1) % mods.size()
	for n4 in (mods[vault]["links"] as Array).duplicate():
		if int(dist[n4]) == int(dist[vault]) - 1 and nest < 0:
			nest = n4
	if nest < 0:
		nest = int((mods[vault]["links"] as Array)[0])
	for n5 in (mods[vault]["links"] as Array).duplicate():
		if n5 != nest:
			edges.erase(_ekey(vault, n5))
	_link(edges)
	# ---- the reactor: a room about halfway in; the rooms nearest it keep their power
	dist = _bfs(dock)
	var half := int(dist[vault]) / 2
	var rc := []
	for i6 in mods.size():
		if i6 != dock and i6 != nest and i6 != vault:
			rc.append(i6)
	rc.sort_custom(func(a, b): return absi(int(dist[a]) - half) < absi(int(dist[b]) - half))
	reactor = rc[0] if not rc.is_empty() else dock
	var rd := _bfs(reactor)
	var order := range(mods.size())
	order.sort_custom(func(a, b): return int(rd[a]) < int(rd[b]))
	var n_pow := maxi(2, int(ceil(float(mods.size()) * rng.randf_range(0.4, 0.6))))
	var npw := 0
	for i7 in order:
		if npw >= n_pow:
			break
		if i7 == nest:
			continue
		mods[i7]["powered"] = true
		npw += 1
	mods[vault]["powered"] = true
	mods[nest]["powered"] = false
	# ---- every other room's role
	var pool := ["hydro", "quarters", "lab", "stores", "stores", "hall", "quarters", "hydro", "lab", "hall"]
	for i8 in mods.size():
		var role := "hall"
		if i8 == dock:
			role = "dock"
		elif i8 == reactor:
			role = "reactor"
		elif i8 == nest:
			role = "nest"
		elif i8 == vault:
			role = "vault"
		else:
			role = pool[rng.randi_range(0, pool.size() - 1)]
		mods[i8]["role"] = role
	# ---- the shell: plating round every room, then the rooms hollowed out
	for md2 in mods:
		for j in range(int(md2["y0"]) - T, int(md2["y1"]) + T):
			for i in range(int(md2["x0"]) - T, int(md2["x1"]) + T):
				_plate(i, j)
	for md3 in mods:
		for j2 in range(int(md3["y0"]), int(md3["y1"])):
			for i9 in range(int(md3["x0"]), int(md3["x1"])):
				cells[j2 * w + i9] = 0
	# ---- doorways and hatches
	for ek in edges:
		var ab: Array = _ekey_parts(ek)
		var ma: Dictionary = mods[ab[0]]
		var mb: Dictionary = mods[ab[1]]
		if int(ma["r"]) == int(mb["r"]):
			var left: Dictionary = ma if int(ma["c"]) < int(mb["c"]) else mb
			_doorway(int(left["x1"]), int(left["y1"]), ab[0] == vault or ab[1] == vault)
		else:
			var up: Dictionary = ma if int(ma["r"]) < int(mb["r"]) else mb
			var dn: Dictionary = mb if int(ma["r"]) < int(mb["r"]) else ma
			var hx: int = (int(up["x0"]) + int(up["x1"])) / 2 + rng.randi_range(-16, 16)
			_hatch(hx, int(up["y1"]), int(dn["y0"]), ab[0] == vault or ab[1] == vault)
	# ---- the dock's mouth and arm
	var dm: Dictionary = mods[dock]
	var wx0: int = int(dm["x0"]) - T if dock_side < 0 else int(dm["x1"])
	ways.append(Rect2i(wx0, int(dm["y1"]) - 30, T, 30))
	for j3 in range(int(dm["y1"]) - 30, int(dm["y1"])):
		for i10 in range(wx0, wx0 + T):
			cells[j3 * w + i10] = 0
	var arm0: int = wx0 - 32 if dock_side < 0 else wx0 + T
	for i11 in range(arm0, arm0 + 32):
		for j4 in range(int(dm["y1"]), int(dm["y1"]) + T):
			_plate(i11, j4)
		for j5 in range(int(dm["y1"]) - 34, int(dm["y1"]) - 30):
			_plate(i11, j5)
		if (i11 - arm0) % 8 == 3:
			put(i11, int(dm["y1"]), Defs.CRYSTAL, 0)
	for i12 in range(mini(arm0, wx0), maxi(arm0 + 32, wx0 + T)):
		for jj in [int(dm["y1"]) - 31, int(dm["y1"])]:
			if at(i12, int(jj)) != 0:
				put(i12, int(jj), Defs.COAL if ((i12 + int(jj)) / 3) % 2 == 0 else Defs.SUNSTONE, 0)
	# ---- each room dressed for its role and its power
	for k in mods.size():
		_dress(k, rng, noise)
	# ---- the outside: windows in the roofs, masts and beacons on top, trusses under, solar wings
	_outside(rng)
	# ---- the caches
	for k2 in mods.size():
		var mk: Dictionary = mods[k2]
		var fl: int = int(mk["y1"])
		var a0: int = int(mk["x0"]) + 3
		var a1: int = int(mk["x1"]) - 3
		match String(mk["role"]):
			"stores":
				_crate_near(a0 + 8, fl, "stores", a0, a1)
				_crate_near(a1 - 20, fl, "stores", a0, a1)
			"quarters", "lab":
				_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, String(mk["role"]), a0, a1)
			"hydro", "hall", "reactor":
				if rng.randf() < 0.5:
					_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, "stores", a0, a1)
			"nest":
				_crate_near(a1 - 14, fl, "nest", a0, a1)
			"vault":
				_crate_near((a0 + a1) / 2 - CRATE_W / 2, fl, VAULT_CRATE, a0, a1)
	# ---- the aliens that live here
	_plan_aliens(rng)
	meta = {"rooms": mods.size(), "powered": npw, "dock": dock, "nest": nest, "vault": vault, "reactor": reactor}
	rebuild()
	rad = maxf(3.0, sqrt(mass / PI))
	ang = 0.0
	omega = 0.0
	_bg_dirty = true
	dirty = true

# ------------------------------------------------------------------ layout --

func _ekey(a: int, b: int) -> String:
	return "%d-%d" % [mini(a, b), maxi(a, b)]

func _ekey_parts(k: String) -> Array:
	var p := k.split("-")
	return [int(p[0]), int(p[1])]

func _neighbours(i: int) -> Array:
	var v := Vector2i(int(mods[i]["c"]), int(mods[i]["r"]))
	var out := []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if grid.has(v + d):
			out.append(int(grid[v + d]))
	return out

func _link(edges: Dictionary) -> void:
	for md in mods:
		md["links"] = []
	for ek in edges:
		var ab: Array = _ekey_parts(ek)
		(mods[ab[0]]["links"] as Array).append(ab[1])
		(mods[ab[1]]["links"] as Array).append(ab[0])

func _bfs(from: int) -> Array:
	var d := []
	d.resize(mods.size())
	d.fill(9999)
	d[from] = 0
	var q := [from]
	while not q.is_empty():
		var i: int = q.pop_front()
		for n in mods[i]["links"]:
			if int(d[n]) > int(d[i]) + 1:
				d[n] = int(d[i]) + 1
				q.append(n)
	return d

## a doorway through the wall right of a room (its floor row y1): DOOR_H high; the vault's sealed
func _doorway(wx: int, y1: int, sealed: bool) -> void:
	ways.append(Rect2i(wx, y1 - DOOR_H, T, DOOR_H))
	for j in range(y1 - DOOR_H, y1):
		for i in range(wx, wx + T):
			cells[j * w + i] = 0
			bg[j * w + i] = Defs.HULL
			bgv[j * w + i] = 2
			if sealed:
				put(i, j, Defs.RUNESTONE if (i + j) % 7 != 0 else Defs.WISP, 0)
				seal_cells.append(j * w + i)
	for i2 in range(wx - 1, wx + T + 1):
		put(i2, y1 - DOOR_H - 1, Defs.COPPERBAR, 2)

## a hatch at column hx through the floor of the room above (its floor row y1a) into the one below (its
## top row y0b): a one-way scaffold floor, and a scaffold ledge halfway down the room below to climb by
func _hatch(hx: int, y1a: int, y0b: int, sealed: bool) -> void:
	ways.append(Rect2i(hx - HATCH_W / 2 - 3, y1a - 4, HATCH_W + 6, y0b + 24 - y1a + 4))
	for j in range(y1a, y0b):
		for i in range(hx - HATCH_W / 2, hx + HATCH_W / 2):
			cells[j * w + i] = 0
			bg[j * w + i] = Defs.HULL
			bgv[j * w + i] = 2
			if sealed:
				put(i, j, Defs.RUNESTONE if (i + j) % 7 != 0 else Defs.WISP, 0)
				seal_cells.append(j * w + i)
	if not sealed:
		for i2 in range(hx - HATCH_W / 2, hx + HATCH_W / 2):
			put(i2, y1a, Defs.SCAFFOLD, 0)
	for i3 in range(hx - HATCH_W / 2 - 3, hx + HATCH_W / 2 + 3):
		put(i3, y0b + 22, Defs.SCAFFOLD, 0)
	for side in [hx - HATCH_W / 2 - 1, hx + HATCH_W / 2]:
		put(int(side), y1a, Defs.SUNSTONE, 0)

## a room's look, by its role and whether it has power
func _dress(k: int, rng: RandomNumberGenerator, noise: FastNoiseLite) -> void:
	var md: Dictionary = mods[k]
	var x0: int = md["x0"]
	var y0: int = md["y0"]
	var x1: int = md["x1"]
	var y1: int = md["y1"]
	var pw: bool = md["powered"]
	var role: String = md["role"]
	# the back wall: clean panels with light strips where there's power; dark, ribbed and burnt where not
	for j in range(y0, y1):
		for i in range(x0, x1):
			var c := j * w + i
			if pw:
				bg[c] = Defs.HULL
				bgv[c] = 0 if (i - x0) % 20 == 0 else (1 if ((j - y0) / 11) % 2 == 0 else 3)
				if (j - y0) == 6 and (i - x0) % 20 > 4 and (i - x0) % 20 < 16:
					bg[c] = Defs.WISPBAR
					bgv[c] = 1
			else:
				var rib := (i - x0) % 14 == 0 or (i - x0) % 14 == 1
				bg[c] = Defs.HULL if rib else Defs.COAL
				bgv[c] = 2 if rib else (0 if (j / 5) % 2 == 0 else 1)
				if noise.get_noise_2d(i * 1.7, j * 1.7) > 0.45:
					bg[c] = Defs.ASH
	# the floor: gravity runes glowing in it where there's power
	for i2 in range(x0, x1):
		if at(i2, y1) == Defs.HULL:
			if pw:
				put(i2, y1, Defs.WISP if (i2 - x0) % 8 == 4 else Defs.RUNESTONE, 0)
			elif (i2 - x0) % 8 == 4:
				put(i2, y1, Defs.RUNESTONE, 0)
	# lamps under the roof: lit, or dead
	for i3 in range(x0 + 8, x1 - 6, 16):
		if at(i3, y0) == 0 and at(i3, y0 - 1) != 0 and not _near_way(i3, y0, 2) and not _near_way(i3 + 1, y0, 2):
			put(i3, y0, Defs.CRYSTAL if pw else Defs.COPPERBAR, 0)
			put(i3 + 1, y0, Defs.CRYSTAL if pw else Defs.COPPERBAR, 0)
	var mx := (x0 + x1) / 2
	var my := (y0 + y1) / 2
	match role:
		"reactor":
			# a great wisp core on the back wall, a ring of crystal round it, pipes along the roof
			for j4 in range(y0 + 2, y1 - 2):
				for i4 in range(mx - 18, mx + 18):
					var d := Vector2(i4 - mx, j4 - my).length()
					if d < 13.0:
						bg[j4 * w + i4] = Defs.WISP if pw else Defs.WISPBAR
						bgv[j4 * w + i4] = int(d) % 4
					elif d < 15.0:
						bg[j4 * w + i4] = Defs.CRYSTAL if pw else Defs.COPPERBAR
						bgv[j4 * w + i4] = 0
			for i5 in range(x0, x1):
				if _near_way(i5, y0, 2):
					continue
				put(i5, y0, Defs.COPPERBAR, 2)
				if i5 % 6 == 0:
					put(i5, y0 + 1, Defs.COPPERBAR, 1)
			for i6 in range(mx - 10, mx + 10):
				if not _near_way(i6, y1 - 2):
					put(i6, y1 - 1, Defs.COPPERBAR, 2)
					put(i6, y1 - 2, Defs.COPPERBAR, 0)
		"hydro":
			# planters on the back wall, troughs on the floor (low: you step over them)
			for row in [y0 + 10, y0 + 24]:
				for i7 in range(x0 + 4, x1 - 4):
					bg[int(row) * w + i7] = Defs.TIMBER
					bgv[int(row) * w + i7] = 0
					for jj in range(int(row) - 6, int(row)):
						if noise.get_noise_2d(i7 * 3.0, jj * 3.0) > (-0.1 if pw else 0.25):
							bg[jj * w + i7] = Defs.LEAF if pw else (Defs.XENITE if noise.get_noise_2d(i7, jj) > 0.2 else Defs.ASH)
							bgv[jj * w + i7] = (i7 + jj) % 4
			for i8 in range(x0 + 10, x1 - 10):
				if (i8 - x0) % 24 < 14 and not _near_way(i8, y1 - 2):
					put(i8, y1 - 1, Defs.PLANK, 1)
					put(i8, y1 - 2, Defs.MOSSBLOCK if pw else Defs.ASH, 0)
		"quarters":
			# bunks on the back wall, two high
			for bx in range(x0 + 6, x1 - 20, 24):
				for row2 in [y1 - 6, y1 - 20]:
					for i9 in range(bx, bx + 18):
						bg[int(row2) * w + i9] = Defs.TIMBER
						bgv[int(row2) * w + i9] = 0
						bg[(int(row2) - 1) * w + i9] = Defs.PLANK
						bgv[(int(row2) - 1) * w + i9] = 2
					for jb in range(int(row2) - 10, int(row2) + 1):
						bg[jb * w + bx] = Defs.TIMBER
						bg[jb * w + bx + 17] = Defs.TIMBER
		"lab":
			# glass tanks on the back wall with something kept in each
			for tx in range(x0 + 6, x1 - 14, 18):
				for jt in range(y1 - 26, y1 - 2):
					for it in range(tx, tx + 12):
						var edge := it == tx or it == tx + 11 or jt == y1 - 26
						bg[jt * w + it] = Defs.GLASS if not edge else Defs.COPPERBAR
						bgv[jt * w + it] = 0
						var dd := Vector2(it - tx - 5.5, jt - (y1 - 14)).length()
						if not edge and dd < 4.0 + noise.get_noise_2d(it * 4.0, jt * 4.0) * 2.0:
							bg[jt * w + it] = Defs.XENITE
							bgv[jt * w + it] = int(dd) % 4
			for i10 in range(x0 + 4, x1 - 4):
				if (i10 - x0) % 30 < 12 and not _near_way(i10, y1 - 2):
					put(i10, y1 - 3, Defs.COPPERBAR, 2)
					put(i10, y1 - 2, Defs.HULL, 2)
					put(i10, y1 - 1, Defs.HULL, 2)
		"stores":
			# shelves of crates on the back wall
			for row3 in [y0 + 12, y0 + 26]:
				for i11 in range(x0 + 3, x1 - 3):
					bg[int(row3) * w + i11] = Defs.TIMBER
					bgv[int(row3) * w + i11] = 0
				for cb in range(x0 + 4, x1 - 8, 7):
					if rng.randf() < 0.7:
						var cm: int = [Defs.PLANK, Defs.COPPERBAR, Defs.HULL, Defs.WISPBAR][rng.randi_range(0, 3)]
						for j12 in range(int(row3) - 4, int(row3)):
							for i12 in range(cb, cb + 5):
								bg[j12 * w + i12] = cm
								bgv[j12 * w + i12] = (i12 + j12) % 3
		"hall":
			# pillars on the back wall
			for px in range(x0 + 12, x1 - 6, 20):
				for jp in range(y0, y1):
					for ip in range(px, px + 4):
						bg[jp * w + ip] = Defs.HULL
						bgv[jp * w + ip] = 2 if ip == px else 1
		"dock":
			# hazard stripes along the floor, clamps
			for i13 in range(x0, x1):
				if ((i13 / 4) % 2) == 0:
					put(i13, y1, Defs.SUNSTONE, 0)
			for cx in [x0 + 20, x1 - 20]:
				for i14 in range(int(cx) - 3, int(cx) + 3):
					if not _near_way(i14, y1 - 1, 2):
						put(i14, y1 - 1, Defs.COPPERBAR, 2)
		"nest":
			# the hive: xenite grown over the walls, the floor and the roof, egg sacs on the floor
			for j15 in range(y0, y1):
				for i15 in range(x0, x1):
					var wall_d := mini(mini(i15 - x0, x1 - 1 - i15), mini(j15 - y0, y1 - 1 - j15))
					var n := noise.get_noise_2d(i15 * 2.3, j15 * 2.3)
					if wall_d < 3 and n > 0.05 and not _near_way(i15, j15, 4):
						put(i15, j15, Defs.XENITE, (i15 + j15) % 4)
					if n > -0.2:
						bg[j15 * w + i15] = Defs.XENITE if n > 0.25 else Defs.COAL
						bgv[j15 * w + i15] = (i15 * 3 + j15) % 4
			for ex in range(x0 + 10, x1 - 10, 13):
				if rng.randf() < 0.7 and not _near_way(ex, y1 - 3):
					for je in range(y1 - 6, y1):
						for ie in range(ex - 2, ex + 3):
							if Vector2(ie - ex, (je - (y1 - 3)) * 0.8).length() < 2.8:
								put(ie, je, Defs.XENITE, 1 if (ie + je) % 2 == 0 else 3)
		"vault":
			# runestone on the back wall, wisp glyphs in it
			for j16 in range(y0, y1):
				for i16 in range(x0, x1):
					bg[j16 * w + i16] = Defs.RUNESTONE
					bgv[j16 * w + i16] = (i16 / 4 + j16 / 4) % 3
					if (i16 - x0) % 10 == 5 and (j16 - y0) % 10 == 5:
						bg[j16 * w + i16] = Defs.WISP
	if not pw and role != "vault":
		# torn and burnt: scorching on the walls, a girder fallen across the roof, a breach to space
		# through an outer wall
		for j17 in range(y0 - T, y1 + T):
			for i17 in range(x0 - T, x1 + T):
				if at(i17, j17) == Defs.HULL and noise.get_noise_2d(i17 * 5.0, j17 * 5.0) > 0.4:
					put(i17, j17, Defs.COAL, 0)
		if rng.randf() < 0.6:
			var gx := rng.randi_range(x0 + 6, x1 - 30)
			for q in 24:
				var gi := gx + q
				var gj := y0 + 2 + q / 3
				if not _near_way(gi, gj):
					put(gi, gj, Defs.COPPERBAR, 2)
					put(gi, gj + 1, Defs.COPPERBAR, 0)
		var v := Vector2i(int(md["c"]), int(md["r"]))
		var outer := []
		if not grid.has(v + Vector2i(0, -1)):
			outer.append(Vector2(rng.randi_range(x0 + 14, x1 - 14), y0 - 2))
		if not grid.has(v + Vector2i(-1, 0)) and k != dock:
			outer.append(Vector2(x0 - 2, rng.randi_range(y0 + 8, y1 - 16)))
		if not grid.has(v + Vector2i(1, 0)) and k != dock:
			outer.append(Vector2(x1 + 1, rng.randi_range(y0 + 8, y1 - 16)))
		if not outer.is_empty() and rng.randf() < 0.75:
			_breach(outer[rng.randi_range(0, outer.size() - 1)], rng.randf_range(7.0, 10.0), noise)

## near a room's ways in or out (a doorway, a hatch and the ledge under it, the dock's mouth): growth,
## girders, troughs and crates keep clear of them
func _near_way(i: int, j: int, pad := 8) -> bool:
	for r in ways:
		if (r as Rect2i).grow(pad).has_point(Vector2i(i, j)):
			return true
	return false

## a crate (wreck.gd), but never over a hatch or in front of a way in
func _crate(x: int, floor_y: int, knd: String) -> bool:
	for i in range(x, x + CRATE_W):
		if _near_way(i, floor_y - 3, 6):
			return false
	return super._crate(x, floor_y, knd)

## windows in the roofs, masts with beacons on top, trusses under, solar wings at the ends
func _outside(rng: RandomNumberGenerator) -> void:
	for mi in mods.size():
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
			if rng.randf() < 0.6:
				var mx := rng.randi_range(x0 + 10, x1 - 10)
				var top := y0 - T - rng.randi_range(14, OY - 8)
				for j in range(top, y0 - T):
					put(mx, j, Defs.TIMBER, 0)
					if (j - top) % 5 == 0:
						put(mx - 1, j, Defs.COPPERBAR, 0)
						put(mx + 1, j, Defs.COPPERBAR, 0)
				for j2 in range(top - 3, top):
					for i2 in range(mx - 1, mx + 2):
						put(i2, j2, Defs.EMBER if md["powered"] else Defs.COAL, 1)
		if not grid.has(v + Vector2i(0, 1)):
			# trusses: a lattice of girders under the room
			for i3 in range(x0 - 2, x1 + 2):
				var depth := 14 + int(6.0 * sin(float(i3) * 0.05))
				for j3 in range(y1 + T, y1 + T + depth):
					var dj := j3 - y1 - T
					if dj == depth - 1 or (i3 + dj) % 12 == 0 or (i3 - dj) % 12 == 0:
						put(i3, j3, Defs.COPPERBAR if dj == depth - 1 else Defs.HULL, 2)
		for side in [-1, 1]:
			if grid.has(v + Vector2i(side, 0)):
				continue
			if mi == dock:
				continue
			# a solar wing: an arm out, wisp panels over and under it
			var a0: int = x0 - T - 1 if side < 0 else x1 + T
			var my := (y0 + y1) / 2
			for q in OX - 6:
				var i4: int = a0 + side * q
				put(i4, my, Defs.HULL, 0)
				put(i4, my + 1, Defs.HULL, 2)
				if q > 3 and q % 10 < 7:
					for j4 in range(my - 12, my - 2):
						put(i4, j4, Defs.WISPBAR if (j4 - my) % 3 != 0 and md["powered"] else (Defs.COPPERBAR if (j4 - my) % 3 == 0 else Defs.HULL), 0)
					for j5 in range(my + 4, my + 14):
						put(i4, j5, Defs.WISPBAR if (j5 - my) % 3 != 0 and md["powered"] else (Defs.COPPERBAR if (j5 - my) % 3 == 0 else Defs.HULL), 0)

## where its aliens live: walkers on the floors, drifters in the dark, the Broodmother in the nest
func _plan_aliens(rng: RandomNumberGenerator) -> void:
	var id := 0
	for k in mods.size():
		var md: Dictionary = mods[k]
		var role: String = md["role"]
		if role == "dock" or role == "vault":
			continue
		var pw: bool = md["powered"]
		var list := []
		if role == "nest":
			list = ["brood", "skitter", "skitter", "drifter"]
		elif pw:
			list = ["skitter"]
			if rng.randf() < 0.6:
				list.append("skitter")
			if rng.randf() < 0.35 and role != "reactor":
				list.append("brute")
		else:
			list = ["drifter"]
			if rng.randf() < 0.5:
				list.append("drifter")
			if rng.randf() < 0.6:
				list.append("skitter")
		for kd in list:
			# (its half size, as alien.gd has it: walkers stand on the floor, clear of crates and troughs)
			var half: Vector2 = {"skitter": Vector2(5, 3), "drifter": Vector2(5.5, 6.5), "brute": Vector2(7, 10), "brood": Vector2(19, 13)}[kd]
			var x := float(rng.randi_range(int(md["x0"]) + 14, int(md["x1"]) - 14))
			var y := float(int(md["y1"])) - half.y - 1.0
			if kd == "drifter":
				y = float(int(md["y0"]) + int(md["y1"])) * 0.5 - 4.0
			elif kd == "brood":
				x = float(int(md["x0"]) + int(md["x1"])) * 0.5
				y = float(int(md["y0"]) + int(md["y1"])) * 0.5
			for t in 12:
				if box_free(Vector2(x, y), half.x + 0.5, half.y + 0.5):
					break
				x = float(rng.randi_range(int(md["x0"]) + int(half.x) + 2, int(md["x1"]) - int(half.x) - 2))
				if kd == "drifter" or kd == "brood":
					y = float(rng.randi_range(int(md["y0"]) + int(half.y) + 2, int(md["y1"]) - int(half.y) - 2))
			spawns.append({"id": id, "kind": kd, "b": Vector2(x, y), "mod": k})
			id += 1

# ----------------------------------------------------------------- queries --

## the room a body point (cells, from the corner) is in (its walls split between it and the next), or -1
func module_at(b: Vector2) -> int:
	var c := int(floor((b.x - float(OX) - float(T) * 0.5) / float(PX)))
	var r := int(floor((b.y - float(OY) - float(T) * 0.5) / float(PY)))
	var v := Vector2i(c, r)
	return int(grid[v]) if grid.has(v) else -1

## is a body point inside the station (in a room or a way between rooms, not out in space)?
func inside(b: Vector2) -> bool:
	var i := int(floor(b.x))
	var j := int(floor(b.y))
	if i < 0 or j < 0 or i >= w or j >= h:
		return false
	return module_at(b) >= 0 and bg[j * w + i] != 0

## does the room this body point is in still have its gravity?
func powered_at(b: Vector2) -> bool:
	var k := module_at(b)
	return k >= 0 and bool(mods[k]["powered"])

func role_name(k: int) -> String:
	return String(ROLE_NAMES.get(String(mods[k]["role"]), "A hall")) if k >= 0 else ""

## a room's middle (station cells)
func room_mid(k: int) -> Vector2:
	var md: Dictionary = mods[k]
	return Vector2(float(int(md["x0"]) + int(md["x1"])) * 0.5, float(int(md["y0"]) + int(md["y1"])) * 0.5)

## a room's middle in the world
func room_world(k: int) -> Vector2:
	var md: Dictionary = mods[k]
	return to_world(Vector2(float(int(md["x0"]) + int(md["x1"])) * 0.5, float(int(md["y0"]) + int(md["y1"])) * 0.5) - com)

## nothing of a station is dug, blasted or chipped
func guarded(_k: int) -> bool:
	return true

# ------------------------------------------------------------------- looks ---
# (a station is ten times a wreck's cells: its pictures are painted through a colour table into raw bytes,
# not a pixel at a time, and what changes later (a cache opened, the seal broken) is painted cell by cell)
static var _lut_fg := PackedInt32Array()
static var _lut_bg := PackedInt32Array()

static func _ensure_lut() -> void:
	if _lut_fg.size() == Defs.NM * 4:
		return
	_lut_fg.resize(Defs.NM * 4)
	_lut_bg.resize(Defs.NM * 4)
	for m in Defs.NM:
		for v in 4:
			var c := Color.hex((Defs.PAL[m * 4 + v] << 8) | 0xff)
			var cf := c
			if Defs.SELF[m] != 0:
				cf.a = 250.0 / 255.0
			_lut_fg[m * 4 + v] = _pack(cf)
			_lut_bg[m * 4 + v] = _pack(c.darkened(0.55))

static func _pack(c: Color) -> int:
	return c.r8 | (c.g8 << 8) | (c.b8 << 16) | (c.a8 << 24)

func _paint(src: PackedByteArray, sv: PackedByteArray, back: bool) -> Image:
	_ensure_lut()
	var lut := _lut_bg if back else _lut_fg
	var px := PackedInt32Array()
	px.resize(w * h)
	for k in w * h:
		var m := src[k]
		if m != 0:
			px[k] = lut[m * 4 + (sv[k] & 3)]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px.to_byte_array())

func texture() -> ImageTexture:
	if img_dirty and tex != null and img != null:
		tex.update(img)
		img_dirty = false
	if dirty or tex == null or img == null:
		img = _paint(cells, vars, false)
		if tex == null or tex.get_width() != w or tex.get_height() != h:
			tex = ImageTexture.create_from_image(img)
		else:
			tex.update(img)
		dirty = false
		img_dirty = false
	if _bg_dirty or bg_tex == null:
		var bimg := _paint(bg, bgv, true)
		if bg_tex == null or bg_tex.get_width() != w or bg_tex.get_height() != h:
			bg_tex = ImageTexture.create_from_image(bimg)
		else:
			bg_tex.update(bimg)
		_bg_dirty = false
	return tex

## a cell changed after its picture was made: its pixel painted again
func _repaint(i: int, j: int) -> void:
	if img == null or dirty:
		dirty = true
		return
	var m := cells[j * w + i]
	if m == 0:
		img.set_pixel(i, j, Color(0, 0, 0, 0))
	else:
		var c := Color.hex((Defs.PAL[m * 4 + (vars[j * w + i] & 3)] << 8) | 0xff)
		if Defs.SELF[m] != 0:
			c.a = 250.0 / 255.0
		img.set_pixel(i, j, c)
	img_dirty = true

## a cache opened: its lid comes away (wreck.gd's, painted cell by cell)
func open_cache(c: Dictionary) -> void:
	c["open"] = true
	var i0 := int(c["i"])
	var j0 := int(c["j"])
	for i in range(i0 + 1, i0 + int(c["w"]) - 1):
		cells[j0 * w + i] = 0
		_repaint(i, j0)
		if cells[(j0 + 1) * w + i] == Defs.PLANK:
			cells[(j0 + 1) * w + i] = 0
			_repaint(i, j0 + 1)

## the seal over the vault's way in breaks (the Broodmother has fallen)
func open_seal() -> void:
	if seal_open:
		return
	seal_open = true
	for c in seal_cells:
		cells[c] = 0
	# (a hatch's top row goes back to a one-way floor)
	for c2 in seal_cells:
		var i := c2 % w
		var j := c2 / w
		if _hatch_top(i, j):
			cells[c2] = Defs.SCAFFOLD
			vars[c2] = 0
	for c3 in seal_cells:
		_repaint(c3 % w, c3 / w)

func _hatch_top(i: int, j: int) -> bool:
	# (the top row of a hatch is a room's floor row: a room's y1)
	for md in mods:
		if j == int(md["y1"]) and i >= int(md["x0"]) and i < int(md["x1"]):
			return true
	return false

## what's kept of it between visits (space.gd station_state)
func state() -> Dictionary:
	var open := []
	for k in caches.size():
		if caches[k]["open"]:
			open.append(k)
	return {"open": open, "seal": seal_open}

func apply_state(d: Dictionary) -> void:
	for k in d.get("open", []):
		if int(k) < caches.size() and not caches[int(k)]["open"]:
			open_cache(caches[int(k)])
	if bool(d.get("seal", false)):
		open_seal()
