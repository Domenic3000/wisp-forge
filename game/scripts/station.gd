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

const Art := preload("res://scripts/station_art.gd")

const MW := 112           # a room's inside: width, height (cells; user, 23 Nov: "they didnt have very much room
const MH := 64            # for the player or enemies to move around": 80 x 44 before)
const T := 4              # walls
const PX := MW + T        # (room pitch)
const PY := MH + T
const OX := 44            # margins round the grid: the docking arm and wings at the sides,
const OY := 36            # masts on top, trusses under it
const DOOR_H := 34
const HATCH_W := 28
const MOUTH := 56         # the dock's open mouth, cells high from its floor: room for the skiff to fly in
const LEDGES := [22, 44]  # scaffold ledges under a hatch, this far down from the room's roof, to climb by
const VAULT_CRATE := "vault"

const ST_A := ["Halcyon", "Meridian", "Concord", "Aurora", "Bastion", "Vigil", "Zenith", "Solace", "Tessera",
	"Harrow", "Lumen", "Cassia", "Obelisk", "Perihelion", "Threnody", "Wayward"]
const ST_B := ["Station", "Array", "Spire", "Citadel", "Platform", "Hub", "Observatory", "Foundry"]
const ST_FATES := ["Something came aboard with the last supply run, and stayed.",
	"Its crew sealed the vault and fled; the hive took the rest.",
	"The reactor still hums, but nobody has answered a hail in years.",
	"A storm belt's lightning broke its back; the dark halls belong to the swarm now.",
	"Its log speaks of eggs found in an asteroid, and then of nothing at all."]
const ROLE_NAMES := {"dock": "Docking bay", "reactor": "Reactor", "hydro": "Hydroponics", "quarters": "Crew quarters",
	"lab": "Laboratory", "stores": "Stores", "hall": "Hall", "nest": "The nest", "vault": "The vault", "mess": "Mess hall",
	"medbay": "Medbay", "engineering": "Engineering", "command": "Command deck", "lounge": "Lounge", "comms": "Comms",
	"corridor": "Corridor", "shaft": "Access shaft", "brig": "Brig", "cabins": "Cabins", "armory": "Armory", "galley": "Galley"}

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

## (user, 25 Nov: "derelict ships and outposts and so on should be redesigned so that you press a button to dock and
## go inside an instanced area so we can make them larger and more intricate"): `in_halls` grows its HALLS, docked
## into as an instance (space.gd `dock_station`): a bigger grid (7-9 rooms by 3-4 decks), its caches and aliens; the
## SHELL out in space is the same kind of station, its dock's mouth sealed behind a force-field pane, nothing in it.
static func make_station(sd: int, in_halls := false) -> RefCounted:
	var st = load("res://scripts/station.gd").new()
	st.halls = in_halls
	st._build_station(sd)
	return st

# (`halls`, from wreck.gd: its halls, docked into; else the shell seen out in space)

## its key in space.gd's station_state: the halls keep what you did in them (the shell keeps nothing)
func state_key() -> String:
	return str(seed_) + ("h" if halls else "")

func _build_station(sd: int) -> void:
	if halls:
		_build_level_station(sd)
		return
	seed_ = sd
	kind = "station"
	wname = station_name(sd)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	fate = ST_FATES[rng.randi_range(0, ST_FATES.size() - 1)]
	cols = rng.randi_range(4, 6)
	rows = rng.randi_range(2, 3)
	if halls:
		cols = rng.randi_range(7, 9)
		rows = rng.randi_range(3, 4)
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
	# (no hatch into the bay: its ledges would be in the skiff's way. The bay joins the room beside it by a
	# doorway instead, unless that would cut the station in two)
	var inner_v := dv + Vector2i(-dock_side, 0)
	var above_v := dv + Vector2i(0, -1)
	if grid.has(inner_v) and grid.has(above_v) and edges.has(_ekey(dock, int(grid[above_v]))):
		var ek_up := _ekey(dock, int(grid[above_v]))
		var ek_in := _ekey(dock, int(grid[inner_v]))
		var had_in: bool = edges.has(ek_in)
		edges.erase(ek_up)
		edges[ek_in] = true
		_link(edges)
		var dd0 := _bfs(dock)
		if dd0.has(9999):
			edges[ek_up] = true
			if not had_in:
				edges.erase(ek_in)
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
	mods[dock]["powered"] = true       # (the docking cradle still holds: you come aboard on your feet)
	mods[nest]["powered"] = false
	# ---- every other room's role
	var pool := ["hydro", "quarters", "lab", "stores", "hall", "quarters", "mess", "medbay", "engineering", "command", "lounge", "comms"]
	var bag := []
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
			role = _deal(pool, bag, rng)
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
	# ---- the dock's mouth (big enough to fly the skiff in: user, 23 Nov: "docking to the derelict space
	# stations needs work") and a landing apron with a lip over it
	var dm: Dictionary = mods[dock]
	var wx0: int = int(dm["x0"]) - T if dock_side < 0 else int(dm["x1"])
	ways.append(Rect2i(wx0, int(dm["y1"]) - MOUTH, T, MOUTH))
	for j3 in range(int(dm["y1"]) - MOUTH, int(dm["y1"])):
		for i10 in range(wx0, wx0 + T):
			cells[j3 * w + i10] = 0
	var arm0: int = wx0 - 36 if dock_side < 0 else wx0 + T
	for i11 in range(arm0, arm0 + 36):
		for j4 in range(int(dm["y1"]), int(dm["y1"]) + T):
			_plate(i11, j4)
		if (i11 - arm0) % 6 == 2:
			put(i11, int(dm["y1"]), Defs.CRYSTAL, 0)
	var lip0: int = wx0 - 10 if dock_side < 0 else wx0 + T
	for i11b in range(lip0, lip0 + 10):
		for j5 in range(int(dm["y1"]) - MOUTH - T, int(dm["y1"]) - MOUTH):
			_plate(i11b, j5)
	for i12 in range(mini(arm0, wx0), maxi(arm0 + 36, wx0 + T)):
		for jj in [int(dm["y1"]) - MOUTH - 1, int(dm["y1"]) + T - 1]:
			if at(i12, int(jj)) != 0:
				put(i12, int(jj), Defs.COAL if ((i12 + int(jj)) / 3) % 2 == 0 else Defs.SUNSTONE, 0)
	for bj in [int(dm["y1"]) - MOUTH - T - 2, int(dm["y1"]) + T + 1]:
		var bx: int = wx0 - 3 if dock_side < 0 else wx0 + T + 2
		put(bx, int(bj), Defs.EMBER, 1)
	if not halls:
		# (out in space its mouth is sealed: a force-field pane with frost lights; F docks you into its halls)
		var pane: int = wx0 + T / 2
		for j6 in range(int(dm["y1"]) - MOUTH, int(dm["y1"])):
			put(pane, j6, Defs.FROST if (j6 - (int(dm["y1"]) - MOUTH)) % 8 == 0 else Defs.GLASS, j6 & 3)
	# ---- each room dressed for its role and its power
	for k in mods.size():
		_dress(k, rng, noise)
	# ---- the outside: windows in the roofs, masts and beacons on top, trusses under, solar wings
	_outside(rng)
	# ---- the caches (only in its halls)
	for k2 in (mods.size() if halls else 0):
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
			"medbay":
				_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, "lab", a0, a1)
			"hydro", "hall", "reactor", "mess", "engineering", "command", "lounge", "comms":
				if rng.randf() < 0.5:
					_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, "stores", a0, a1)
			"nest":
				_crate_near(a1 - 14, fl, "nest", a0, a1)
			"vault":
				_crate_near((a0 + a1) / 2 - CRATE_W / 2, fl, VAULT_CRATE, a0, a1)
	# ---- the aliens that live here (in its halls)
	if halls:
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
	ways.append(Rect2i(hx - HATCH_W / 2 - 3, y1a - 4, HATCH_W + 6, y0b + int(LEDGES[LEDGES.size() - 1]) + 2 - y1a + 4))
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
	# (ledges to climb by, staggered so each hop is about 22 cells: rooms are 64 high)
	for li in LEDGES.size():
		var off := (HATCH_W / 2 + 4) * (1 if li % 2 == 0 else -1)
		for i3 in range(hx - HATCH_W / 2 - 3, hx + HATCH_W / 2 + 3):
			put(i3 + (0 if li == 0 else off), y0b + int(LEDGES[li]), Defs.SCAFFOLD, 0)
		ways.append(Rect2i(hx - HATCH_W / 2 - 3 + (0 if li == 0 else off), y0b + int(LEDGES[li]) - 18, HATCH_W + 6, 20))
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
	# (27 Nov, user: "different types of rooms with different shapes and decorations. make it feel alive like its
	# being lived in": station_art.gd's walls and parts; a derelict's dark rooms abandoned, an outpost's kept up)
	var cv := Art.Cv.new()
	cv.bg = bg
	cv.bgv = bgv
	cv.w = w
	cv.h = h
	cv.rng = rng
	cv.noise = noise
	cv.dead = not pw
	cv.lived = kind == "outpost"
	var drop := _shape(k, rng)
	if role != "nest" and role != "vault":
		Art.wall(cv, x0, y0, x1, y1, Art.style_for(role, rng), drop)
	# the floor: gravity runes glowing in it where there's power
	for i2 in range(x0, x1):
		if at(i2, y1) == Defs.HULL:
			if pw:
				put(i2, y1, Defs.WISP if (i2 - x0) % 8 == 4 else Defs.RUNESTONE, 0)
			elif (i2 - x0) % 8 == 4:
				put(i2, y1, Defs.RUNESTONE, 0)
	# lamps under the roof (where it comes down to): lit, or dead
	for i3 in range(x0 + 8, x1 - 6, 16):
		var lj: int = y0 + int(drop[i3 - x0])
		if at(i3, lj) == 0 and at(i3 + 1, lj) == 0 and at(i3, lj - 1) != 0 and not _near_way(i3, lj, 2) and not _near_way(i3 + 1, lj, 2):
			put(i3, lj, Defs.CRYSTAL if pw else Defs.COPPERBAR, 0)
			put(i3 + 1, lj, Defs.CRYSTAL if pw else Defs.COPPERBAR, 0)
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
		_:
			Art.furnish(cv, role, x0, y0, x1, y1)
			# (a derelict's rooms that kept their power are abandoned too: litter, and the odd alien stain)
			if kind == "station" and pw and halls:
				Art.debris(cv, x0, x1, y1)
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

## the next room type from a shuffled deck of `pool` (dealt out before any comes again: 27 Nov, one outpost had six
## hydroponics rooms)
static func _deal(pool: Array, bag: Array, rng: RandomNumberGenerator) -> String:
	if bag.is_empty():
		bag.append_array(pool)
		for k in range(bag.size() - 1, 0, -1):
			var sw := rng.randi_range(0, k)
			var tmp = bag[k]
			bag[k] = bag[sw]
			bag[sw] = tmp
	return String(bag.pop_back())

## a room's shape (27 Nov): its roof brought down as an arch, a dome, stepped vaults, chamfered corners or a duct run
## along one side, in plating, never over a way in or out (doorways, hatches and their ledges stay as they were).
## Returns how many rows the roof comes down at each column (0 where it doesn't).
func _shape(k: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var md: Dictionary = mods[k]
	var x0: int = md["x0"]
	var y0: int = md["y0"]
	var x1: int = md["x1"]
	var role: String = md["role"]
	var rw := x1 - x0
	var drop := PackedInt32Array()
	drop.resize(rw)
	var kind_s := "flat"
	match role:
		"dock", "hangar", "reactor", "nest", "vault":
			return drop
		"observatory", "command":
			kind_s = "dome"
		"lounge", "quarters", "mess", "cantina":
			kind_s = "arch" if rng.randf() < 0.6 else "chamfer"
		"engineering", "stores", "comms", "shipwright":
			kind_s = "duct"
		"hall", "promenade":
			kind_s = "vault"
		_:
			kind_s = "chamfer"
	var duct_l := rng.randf() < 0.5
	for i in rw:
		var u := (float(i) + 0.5) / float(rw) * 2.0 - 1.0        # (-1 at one wall, 1 at the other)
		var d := 0.0
		match kind_s:
			"dome":
				d = 18.0 * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
			"arch":
				d = 11.0 * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
			"vault":
				d = 12.0 if absf(u) > 0.82 else (6.0 if absf(u) > 0.55 else 0.0)
			"duct":
				var side := i < 34 if duct_l else i >= rw - 34
				d = 7.0 if side else 0.0
				d = maxf(d, 6.0 - float(mini(i, rw - 1 - i)))
			_:
				d = maxf(0.0, 7.0 - float(mini(i, rw - 1 - i)))
		drop[i] = int(d)
	for i2 in rw:
		var ci := x0 + i2
		for j in range(y0, y0 + int(drop[i2])):
			if _near_way(ci, j, 3):
				drop[i2] = j - y0
				break
			put(ci, j, Defs.HULL, 0 if j == y0 + int(drop[i2]) - 1 else (1 if (j / 4) % 2 == 0 else 2))
	# a duct's run: a pipe along its underside
	if kind_s == "duct":
		for i3 in rw:
			var ci3 := x0 + i3
			var dj: int = y0 + int(drop[i3])
			if int(drop[i3]) >= 6 and at(ci3, dj) == 0 and not _near_way(ci3, dj, 3):
				bg[dj * w + ci3] = Art.PIPE
				bgv[dj * w + ci3] = 3 if ci3 % 12 == 0 else 0
	return drop

## near a room's ways in or out (a doorway, a hatch and the ledge under it, the dock's mouth): growth,
## girders, troughs and crates keep clear of them
func _near_way(i: int, j: int, pad := 8) -> bool:
	if not _wmask.is_empty():
		if i < 0 or j < 0 or i >= w or j >= h or _wmask[j * w + i] == 0:
			return false
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
				# (in its halls the station goes on all round them, station_back.gd: no masts or wings out there)
				for j in range(top, y0 - T if not halls else top):
					put(mx, j, Defs.TIMBER, 0)
					if (j - top) % 5 == 0:
						put(mx - 1, j, Defs.COPPERBAR, 0)
						put(mx + 1, j, Defs.COPPERBAR, 0)
				for j2 in range(top - 3, top if not halls else top - 3):
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
			if mi == dock or halls:
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
	if lv:
		return _room_at(b)
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

## (27 Nov; user: "when i was using the shift key in space to travel faster the game crashed": under the Starsail
## a system's station and its outpost come in a moment apart, each grown on a worker thread, and both could fill
## this table at once: two threads resizing one array. Now it's filled under a lock, into new arrays, and only then
## put in place)
static var _lut_mx := Mutex.new()

static func _ensure_lut() -> void:
	_lut_mx.lock()
	if _lut_fg.size() != 256 * 4:
		var fg := PackedInt32Array()
		var bg := PackedInt32Array()
		fg.resize(256 * 4)
		bg.resize(256 * 4)
		for code in Art.PAINT:
			for v2 in 4:
				var pc := Art.color(int(code), v2)
				fg[int(code) * 4 + v2] = _pack(pc)
				bg[int(code) * 4 + v2] = _pack(pc)
		for m in Defs.NM:
			for v in 4:
				var c := Color.hex((Defs.PAL[m * 4 + v] << 8) | 0xff)
				var cf := c
				if Defs.SELF[m] != 0:
					cf.a = 250.0 / 255.0
				fg[m * 4 + v] = _pack(cf)
				bg[m * 4 + v] = _pack(c.darkened(0.55))
		_lut_bg = bg
		_lut_fg = fg
	_lut_mx.unlock()

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
	if _pre_fg != null:
		# (a level: its pictures were painted as it was grown, off the main thread)
		if tex == null:
			img = _pre_fg
			tex = ImageTexture.create_from_image(img)
			bg_tex = ImageTexture.create_from_image(_pre_bg)
			dirty = false
			img_dirty = false
			_bg_dirty = false
		elif img_dirty:
			tex.update(img)
			img_dirty = false
		return tex
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
	var im: Image = img if img != null else _pre_fg
	if im == null or (dirty and _pre_fg == null):
		dirty = true
		return
	var m := cells[j * w + i]
	if m == 0:
		im.set_pixel(i, j, Color(0, 0, 0, 0))
	else:
		var c := Color.hex((Defs.PAL[m * 4 + (vars[j * w + i] & 3)] << 8) | 0xff)
		if Defs.SELF[m] != 0:
			c.a = 250.0 / 255.0
		im.set_pixel(i, j, c)
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
	if lv:
		# (a level's seal is the nest's door into the vault: the runestone falls away and it's a door again, shut)
		for c0 in seal_cells:
			cells[c0] = 0
			_repaint(c0 % w, c0 / w)
		for dr in doors:
			if dr["sealed"]:
				dr["sealed"] = false
				dr["f"] = 0.0
				dr["n"] = 0
				_door_set(dr)
		return
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

# ================================================================== levels ===
# (27 Nov; user: "can we make the derelict space staions feel linke they are not just squares and are much larger. like
# whole levels by themselves complete with hallways doors you cant see through destroyed rooms. not just all square
# rooms. room to maneuver around where the enemies are. creepy abandonded ambience. loong hallways, as if it is a real
# spaceship that was killed by aliens. there should be room to move around in each room. room for a full jump and
# levitation in the rooms. same thing with outposts ... there are curently no hallways, doors, and decorative rooms,
# sleeping areas, mess halls, brig, crew quarters, so on"; "with room to jump and move around. currently the rooms or
# only like 2 player lengths high".)
# Its HALLS (the instance you dock into) are a LEVEL: three or four DECKS stacked, each a run of tall ROOMS (136-176
# high: a jump is about 44, so there's room to jump and levitate) and long CORRIDORS (64 high, bays rising to 100),
# side by side through BULKHEADS with a DOOR in each at the deck's floor: solid, it opens as you (or a woken alien, or a
# spacer) come near and shuts behind you, and in a derelict what's past a shut door is dark (`see_from`, `draw_level`).
# SHAFTS join the decks (one-way landings at each deck's floor, ledges every 26 rows to climb by), and the REACTOR is a
# great room two decks high with a catwalk across it. Rooms aren't boxes: domes, arches and vaults in their roofs,
# soffits hanging over one side, MEZZANINES (one-way catwalks with railings, furnished up there too), raised DAISES
# with steps; a derelict's broken rooms are DESTROYED (the roof caved in over a heap of rubble, girders down, breaches,
# scorching, claw marks and the hive's goo). The shells out in space keep the old grid (`_build_station`).
const BW := 8             # the bulkheads between a level's rooms, corridors and shafts
const FS := 10            # the slab between two decks
const HDOOR := 44         # a level's doorways and doors (the mage is 24 tall, a brute 22)
const CH := 64            # a corridor's ceiling (its bays rise to CH_BAY)
const CH_BAY := 100
const SW := 60            # a shaft's width
const HM := 28            # the hull round a level (the station goes on behind it: station_back.gd)
const LSTEP := 26         # one-way ledges up a shaft or a tall room, this far apart (a jump is about 44)
const MEZZ := 54          # a mezzanine's floor, this far over its room's floor (a ledge half way to climb by)
const NO_FEATURES := ["dock", "vault", "nest", "hangar", "reactor", "market", "shipwright", "cantina", "charts"]

var lv := false           # laid out as a level (its halls, since 27 Nov); else the old grid (the shells out in space)
var decks := []           # [{"top", "floor"}]: each deck's highest row inside, and its floor's row
var doors := []           # [{"x" (its bulkhead's first column), "y1" (the deck's floor row), "a", "b" (the rooms either
                          #   side), "f" (0 shut .. 1 open), "n" (rows of it shut), "sealed", "d" (its deck)}]
var vis := PackedFloat32Array()   # how much of each room you can see (a derelict's: past a shut door it's dark)
var lights := []          # (an outpost's halos: gathered as it's grown)
var _wmask := PackedByteArray()   # cells near a way in or out: `_near_way` looks closer only there
var _pre_fg: Image        # (its pictures, painted as it's grown, off the main thread)
var _pre_bg: Image
var _door_tex: ImageTexture

## a level's mass and middle: plain numbers (nothing of it moves; the cell-by-cell sums cost half a second)
func rebuild() -> void:
	if lv:
		com = Vector2(float(w), float(h)) * 0.5
		mass = float(w * h) * 0.5
		return
	super.rebuild()

## the room (or corridor, or shaft) a point is in: the one whose inside holds it, else the nearest within a bulkhead
func _room_at(b: Vector2) -> int:
	for k in mods.size():
		var md: Dictionary = mods[k]
		if b.x >= float(md["x0"]) and b.x < float(md["x1"]) and b.y >= float(md["y0"]) and b.y < float(md["y1"]):
			return k
	var best := -1
	var bd := float(BW) + 1.5
	for k2 in mods.size():
		var md2: Dictionary = mods[k2]
		var dx := maxf(maxf(float(md2["x0"]) - b.x, b.x - float(md2["x1"])), 0.0)
		var dy := maxf(maxf(float(md2["y0"]) - b.y, b.y - float(md2["y1"])), 0.0)
		var dd := maxf(dx, dy)
		if dd < bd:
			bd = dd
			best = k2
	return best

## the transform from its cells (from the corner) to the world
func body_xf() -> Transform2D:
	var ax := axis_x()
	var ay := axis_y()
	return Transform2D(ax, ay, pos - ax * com.x - ay * com.y)

func _build_level_station(sd: int) -> void:
	seed_ = sd
	kind = "station"
	wname = station_name(sd)
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	fate = ST_FATES[rng.randi_range(0, ST_FATES.size() - 1)]
	var t0 := Time.get_ticks_msec()
	var nd := rng.randi_range(3, 4)
	var width := rng.randi_range(1800, 2250) if nd == 4 else rng.randi_range(2000, 2450)
	var dh := []
	for d in nd:
		dh.append(rng.randi_range(136, 176))
	dock_side = -1 if rng.randf() < 0.5 else 1
	var rd := 1 if nd == 4 else rng.randi_range(0, 1)
	var fixed := [
		{"role": "dock", "kind": "room", "d0": nd - 1, "d1": nd - 1, "w": rng.randi_range(250, 290), "end": dock_side},
		{"role": "vault", "kind": "room", "d0": 0, "d1": 0, "w": rng.randi_range(150, 180), "end": -dock_side},
		{"role": "nest", "kind": "room", "d0": 0, "d1": 0, "w": rng.randi_range(270, 320), "end": -dock_side},
		{"role": "reactor", "kind": "room", "d0": rd, "d1": rd + 1, "w": rng.randi_range(220, 270), "end": 0},
	]
	_add_shafts(rng, nd, fixed)
	# (laid out again if a deck came out cut off from the rest, or the reactor found no room: it never should)
	for attempt in 4:
		_reset_level()
		_lay_level(rng, nd, width, dh, fixed)
		for k in mods.size():
			match String(mods[k]["role"]):
				"dock": dock = k
				"vault": vault = k
				"nest": nest = k
				"reactor": reactor = k
		if reactor >= 0 and not _bfs(dock).has(9999):
			break
	if reactor < 0:
		reactor = dock
	# every other room's role, dealt from a deck (corridors and shafts are what they are)
	var pool := ["quarters", "cabins", "mess", "galley", "medbay", "brig", "engineering", "command", "lounge", "comms", "hydro",
		"lab", "stores", "armory", "hall", "quarters", "stores"]
	var bag := []
	for md in mods:
		if String(md["role"]) == "":
			md["role"] = _deal(pool, bag, rng)
	# power: the rooms nearest the reactor still have it (gravity, light); the bay and the vault too, never the nest
	var rdist := _bfs(reactor)
	var order := range(mods.size())
	order.sort_custom(func(a, b): return int(rdist[a]) < int(rdist[b]))
	var n_pow := maxi(3, int(ceil(float(mods.size()) * rng.randf_range(0.4, 0.6))))
	var npw := 0
	for i7 in order:
		if npw >= n_pow:
			break
		if i7 == nest:
			continue
		mods[i7]["powered"] = true
		npw += 1
	mods[vault]["powered"] = true
	mods[dock]["powered"] = true
	mods[nest]["powered"] = false
	# the nest's door into the vault is sealed with runestone until the Broodmother falls
	for dr in doors:
		if (int(dr["a"]) == nest and int(dr["b"]) == vault) or (int(dr["a"]) == vault and int(dr["b"]) == nest):
			dr["sealed"] = true
	_level_body(rng, sd)
	# the bay's mouth (out to space, past the hull) and its apron
	var dm: Dictionary = mods[dock]
	_mouth(int(dm["x0"]), int(dm["x1"]), int(dm["y1"]), MOUTH, dock_side)
	_dress_all(rng, sd)
	for k3 in mods.size():
		_caches_level(k3, rng)
	_plan_aliens_level(rng)
	meta = {"rooms": mods.size(), "powered": npw, "dock": dock, "nest": nest, "vault": vault, "reactor": reactor,
		"decks": nd, "doors": doors.size(), "size": [w, h]}
	_finish_level()
	meta["ms"] = Time.get_ticks_msec() - t0

## (a level begun again from nothing)
func _reset_level() -> void:
	mods = []
	doors = []
	decks = []
	ways = []
	seal_cells = PackedInt32Array()
	caches = []
	spawns = []
	dock = -1
	nest = -1
	vault = -1
	reactor = -1

## shafts between the decks: one or two for each pair (now and then running a deck further), placed among the rest
func _add_shafts(rng: RandomNumberGenerator, nd: int, fixed: Array) -> void:
	for d in nd - 1:
		var n := 1 + (1 if rng.randf() < 0.6 else 0)
		for q in n:
			var d1 := d + 1
			if d + 2 < nd and rng.randf() < 0.25:
				d1 = d + 2
			fixed.append({"role": "shaft", "kind": "shaft", "d0": d, "d1": d1, "w": SW, "end": 0})

## the decks, the pieces on them, their doors and the cells (hull everywhere, each piece hollowed out)
func _lay_level(rng: RandomNumberGenerator, nd: int, width: int, dh: Array, fixed: Array) -> void:
	lv = true
	var yy := HM
	for d in nd:
		decks.append({"top": yy, "floor": yy + int(dh[d])})
		yy += int(dh[d]) + FS
	setup(width + HM * 2, yy - FS + HM)
	rows = nd
	var lo_x := HM
	var hi_x := HM + width
	var cl := []
	var cr := []
	for d2 in nd:
		cl.append(lo_x)
		cr.append(hi_x)
	# the pieces placed first: those at an end (the bay, the hangar, the vault and the nest, an outpost's shops) one
	# after another inward, then those in the middle (the reactor, the shafts) clear of them
	var vert := []
	for f in fixed:
		var e: int = int(f.get("end", 0))
		if e == 0:
			continue
		var d0: int = f["d0"]
		var d1: int = f["d1"]
		var fw: int = f["w"]
		var x0 := 0
		if e < 0:
			for d3 in range(d0, d1 + 1):
				x0 = maxi(x0, int(cl[d3]))
			for d4 in range(d0, d1 + 1):
				cl[d4] = x0 + fw + BW
		else:
			var x1 := hi_x
			for d5 in range(d0, d1 + 1):
				x1 = mini(x1, int(cr[d5]))
			x0 = x1 - fw
			for d6 in range(d0, d1 + 1):
				cr[d6] = x0 - BW
		vert.append({"x0": x0, "x1": x0 + fw, "d0": d0, "d1": d1, "role": f["role"], "kind": f["kind"]})
	for f2 in fixed:
		if int(f2.get("end", 0)) != 0:
			continue
		var px := _place_mid(rng, vert, cl, cr, int(f2["d0"]), int(f2["d1"]), int(f2["w"]))
		if px >= 0:
			vert.append({"x0": px, "x1": px + int(f2["w"]), "d0": f2["d0"], "d1": f2["d1"], "role": f2["role"], "kind": f2["kind"]})
	for v in vert:
		_add_piece(String(v["kind"]), int(v["x0"]), int(v["x1"]), int(v["d0"]), int(v["d1"]), String(v["role"]), rng)
	# what's left of each deck dealt out as rooms and corridors, turn about
	for d7 in nd:
		var occ := []
		for v2 in vert:
			if int(v2["d0"]) <= d7 and d7 <= int(v2["d1"]):
				occ.append(v2)
		occ.sort_custom(func(p, q): return int(p["x0"]) < int(q["x0"]))
		var a := lo_x
		var left := "edge"
		for v3 in occ:
			var b := int(v3["x0"]) - BW
			if b - a >= 40:
				_fill_deck(rng, d7, a, b, left)
			a = int(v3["x1"]) + BW
			left = "corridor" if String(v3["kind"]) == "shaft" else String(v3["kind"])
		if hi_x - a >= 40:
			_fill_deck(rng, d7, a, hi_x, left)
	# side by side on a deck, two pieces share a bulkhead with a door in it at that deck's floor
	cols = 0
	for d8 in nd:
		var on := []
		for k in mods.size():
			if int(mods[k]["d0"]) <= d8 and d8 <= int(mods[k]["d1"]):
				on.append(k)
		on.sort_custom(func(p, q): return int(mods[p]["x0"]) < int(mods[q]["x0"]))
		for q2 in range(on.size() - 1):
			var ka: int = on[q2]
			var kb: int = on[q2 + 1]
			if int(mods[kb]["x0"]) - int(mods[ka]["x1"]) != BW:
				continue
			doors.append({"x": int(mods[ka]["x1"]), "y1": int(decks[d8]["floor"]), "a": ka, "b": kb, "f": 0.0, "n": 0, "sealed": false, "d": d8})
			(mods[ka]["links"] as Array).append(kb)
			(mods[kb]["links"] as Array).append(ka)
		var c := 0
		for k2 in on:
			if int(mods[k2]["d1"]) == d8:
				mods[k2]["c"] = c
				c += 1
		cols = maxi(cols, on.size())
	# the cells: hull everywhere, each piece hollowed out, a corridor's ceiling brought down to its line, the doorways
	var ci := Image.create(w, h, false, Image.FORMAT_R8)
	ci.fill(Art.r8(Defs.HULL))
	for md in mods:
		var mx0: int = md["x0"]
		var my0: int = md["y0"]
		var my1: int = md["y1"]
		ci.fill_rect(Rect2i(mx0, my0, int(md["x1"]) - mx0, my1 - my0), Art.r8(0))
		if String(md["kind"]) == "corridor":
			var pf: PackedInt32Array = md["prof"]
			var i := 0
			while i < pf.size():
				var hg := pf[i]
				var e2 := i
				while e2 < pf.size() and pf[e2] == hg:
					e2 += 1
				var open_top := my1 - hg
				if open_top > my0:
					ci.fill_rect(Rect2i(mx0 + i, my0, e2 - i, open_top - my0), Art.r8(Defs.HULL))
				i = e2
	for dr in doors:
		ci.fill_rect(Rect2i(int(dr["x"]), int(dr["y1"]) - HDOOR, BW, HDOOR), Art.r8(0))
	cells = ci.get_data()
	# the plates' look (as `_plate`: courses four rows high, a seam every ten columns with rivets), row by row
	var rowv := []
	for jm in 8:
		var row := PackedByteArray()
		row.resize(w)
		for i2 in w:
			var pv := 1 if (jm / 4) % 2 == 0 else 2
			if i2 % 10 == 0:
				pv = 0
			elif (i2 % 10 == 1 or i2 % 10 == 9) and jm % 4 == 1:
				pv = 3
			row[i2] = pv
		rowv.append(row)
	var vv := PackedByteArray()
	for j in h:
		vv.append_array(rowv[j % 8])
	vars = vv

## somewhere in the middle for a piece spanning decks d0..d1: clear of the others, leaving either no room at all or
## room for a room between them. -1 if nowhere.
func _place_mid(rng: RandomNumberGenerator, vert: Array, cl: Array, cr: Array, d0: int, d1: int, fw: int) -> int:
	var lo := 0
	var hi := 1 << 30
	for d in range(d0, d1 + 1):
		lo = maxi(lo, int(cl[d]))
		hi = mini(hi, int(cr[d]))
	if hi - lo < fw:
		return -1
	for gmin in [140, 100]:
		for tries in 60:
			var x0 := rng.randi_range(lo, hi - fw)
			if _fits(x0, fw, d0, d1, vert, cl, cr, gmin):
				return x0
	# (right beside another, or at an end)
	var cands := [lo, hi - fw]
	for v in vert:
		cands.append(int(v["x1"]) + BW)
		cands.append(int(v["x0"]) - BW - fw)
	for x1 in cands:
		if int(x1) >= lo and int(x1) <= hi - fw and _fits(int(x1), fw, d0, d1, vert, cl, cr, 100):
			return int(x1)
	return -1

func _fits(x0: int, fw: int, d0: int, d1: int, vert: Array, cl: Array, cr: Array, gmin: int) -> bool:
	var x1 := x0 + fw
	for d in range(d0, d1 + 1):
		var gl := (x0 - BW) - int(cl[d])
		if gl != -BW and gl < gmin:
			return false
		var gr := int(cr[d]) - (x1 + BW)
		if gr != -BW and gr < gmin:
			return false
	for v in vert:
		if int(v["d1"]) < d0 or int(v["d0"]) > d1:
			continue
		var vx0: int = v["x0"]
		var vx1: int = v["x1"]
		if vx1 <= x0:
			var g := (x0 - BW) - (vx1 + BW)
			if g != -BW and g < gmin:
				return false
		elif vx0 >= x1:
			var g2 := (vx0 - BW) - (x1 + BW)
			if g2 != -BW and g2 < gmin:
				return false
		else:
			return false
	return true

## a stretch a..b of deck d (inside: walls between the pieces) dealt out as rooms and corridors, turn about
func _fill_deck(rng: RandomNumberGenerator, d: int, a: int, b: int, left: String) -> void:
	var span := b - a
	var out := []
	var t := "corridor" if left == "room" else "room"
	var rem := span
	while rem > 0:
		var wmin := 150 if t == "room" else 90
		if rem < wmin:
			break
		var wv := rng.randi_range(170, 300) if t == "room" else (rng.randi_range(280, 460) if rng.randf() < 0.4 else rng.randi_range(110, 220))
		wv = mini(wv, rem)
		if rem - wv - BW < 100:
			wv = rem
		out.append([t, wv])
		rem -= wv + BW
		t = "room" if t == "corridor" else "corridor"
	if out.is_empty():
		out.append(["corridor" if span < 150 else "room", span])
	var tot := -BW
	for p in out:
		tot += int(p[1]) + BW
	out[out.size() - 1][1] = int(out[out.size() - 1][1]) + (span - tot)
	var x := a
	for p2 in out:
		_add_piece(String(p2[0]), x, x + int(p2[1]), d, d, "corridor" if String(p2[0]) == "corridor" else "", rng)
		x += int(p2[1]) + BW

func _add_piece(knd: String, x0: int, x1: int, d0: int, d1: int, role: String, rng: RandomNumberGenerator) -> void:
	var fl: int = decks[d1]["floor"]
	var y0: int = decks[d0]["top"]
	if knd == "corridor":
		y0 = fl - CH_BAY
	var md := {"c": 0, "r": d1 if knd != "shaft" else -1, "x0": x0, "y0": y0, "x1": x1, "y1": fl, "role": role, "powered": false,
		"links": [], "kind": knd, "d0": d0, "d1": d1}
	if knd == "corridor":
		md["prof"] = _corr_profile(rng, x1 - x0)
	if role == "" and knd == "shaft":
		md["role"] = "shaft"
	mods.append(md)

## a corridor's ceiling, column by column: CH high, rising into a bay or two along a long one (chamfered: four rows a
## column), clear of its ends
func _corr_profile(rng: RandomNumberGenerator, ln: int) -> PackedInt32Array:
	var pf := PackedInt32Array()
	pf.resize(ln)
	pf.fill(CH)
	if ln > 150:
		for k in rng.randi_range(1, 1 + ln / 220):
			var bw2 := rng.randi_range(46, 90)
			var bx := rng.randi_range(30, maxi(31, ln - bw2 - 30))
			for i in range(bx, mini(ln, bx + bw2)):
				var e := mini(i - bx, bx + bw2 - 1 - i)
				pf[i] = maxi(pf[i], mini(CH_BAY, CH + e * 4))
	return pf

## the back wall in bulk, the doors shut, the frames (shafts' landings and ledges, catwalks and balconies in the rooms
## two decks high, mezzanines, daises), the ways kept clear, the roofs' shapes: after the roles are known
func _level_body(rng: RandomNumberGenerator, sd: int) -> void:
	var bi := Image.create(w, h, false, Image.FORMAT_R8)
	var vi := Image.create(w, h, false, Image.FORMAT_R8)
	for md in mods:
		var role: String = md["role"]
		var sty := Art.style_for(role if String(md["kind"]) == "room" else String(md["kind"]), rng)
		md["style"] = sty
		Art.wall_bulk(bi, vi, int(md["x0"]), int(md["y0"]), int(md["x1"]), int(md["y1"]), sty)
	for dr in doors:
		bi.fill_rect(Rect2i(int(dr["x"]), int(dr["y1"]) - HDOOR, BW, HDOOR), Art.r8(Defs.HULL))
		vi.fill_rect(Rect2i(int(dr["x"]), int(dr["y1"]) - HDOOR, BW, HDOOR), Art.r8(2))
	bg = bi.get_data()
	bgv = vi.get_data()
	# the doors: shut (or sealed), a lintel and a lamp over each
	for dr2 in doors:
		var dx: int = dr2["x"]
		var dy: int = dr2["y1"]
		ways.append(Rect2i(dx - 12, dy - HDOOR - 2, BW + 24, HDOOR + 2))
		for i in range(dx - 2, dx + BW + 2):
			put(i, dy - HDOOR - 1, Defs.COPPERBAR, 2)
			put(i, dy - HDOOR - 2, Defs.COPPERBAR, 0)
		put(dx + BW / 2, dy - HDOOR - 4, Defs.CRYSTAL if not dr2["sealed"] else Defs.EMBER, 0)
		if dr2["sealed"]:
			for j in range(dy - HDOOR, dy):
				for i2 in range(dx, dx + BW):
					put(i2, j, Defs.RUNESTONE if (i2 + j) % 7 != 0 else Defs.WISP, 0)
					seal_cells.append(j * w + i2)
		else:
			_door_set(dr2)
	for k in mods.size():
		_frame_piece(k, rng)
	# (the cells near a way in or out: everything that might stand in one looks closer there)
	var mi := Image.create(w, h, false, Image.FORMAT_R8)
	for r in ways:
		mi.fill_rect((r as Rect2i).grow(10).intersection(Rect2i(0, 0, w, h)), Color(1.0 / 255.0, 0, 0))
	_wmask = mi.get_data()

## a shaft's landings and ledges; a tall room's catwalk or balconies and the ledges up to them; a room's mezzanine
## and dais
func _frame_piece(k: int, rng: RandomNumberGenerator) -> void:
	var md: Dictionary = mods[k]
	var x0: int = md["x0"]
	var x1: int = md["x1"]
	var y1: int = md["y1"]
	var d0: int = md["d0"]
	var d1: int = md["d1"]
	var knd: String = md["kind"]
	if knd == "shaft":
		for d in range(d0, d1):
			var fy: int = decks[d]["floor"]
			for i in range(x0, x1):
				put(i, fy, Defs.SCAFFOLD, 0)
			ways.append(Rect2i(x0, fy - 22, x1 - x0, 24))
		for d2 in range(d0 + 1, d1 + 1):
			_ledges(x0, x1, int(decks[d2]["floor"]), int(decks[d2 - 1]["floor"]), 26)
		return
	if d1 > d0:
		for d3 in range(d0, d1):
			var fy2: int = decks[d3]["floor"]
			if String(md["role"]) == "reactor":
				# a catwalk right across, ledges up to it along both walls
				for i3 in range(x0, x1):
					put(i3, fy2, Defs.SCAFFOLD, 0)
				ways.append(Rect2i(x0, fy2 - 22, x1 - x0, 24))
				_ledges(x0, x0 + 64, int(decks[d3 + 1]["floor"]), fy2, 28)
				_ledges(x1 - 64, x1, int(decks[d3 + 1]["floor"]), fy2, 28)
				md["catwalks"] = (md.get("catwalks", []) as Array) + [[x0, x1, fy2]]
				continue
			# a balcony at each door this deck has into it, ledges up to it
			for dr in doors:
				if int(dr["d"]) != d3 or (int(dr["a"]) != k and int(dr["b"]) != k):
					continue
				var on_left: bool = int(dr["x"]) < x0
				var bx0 := x0 if on_left else x1 - 60
				var bx1 := x0 + 60 if on_left else x1
				for i4 in range(bx0, bx1):
					put(i4, fy2, Defs.SCAFFOLD, 0)
				ways.append(Rect2i(bx0, fy2 - 22, bx1 - bx0, 24))
				_ledges(bx0 - (0 if on_left else 30), bx1 + (30 if on_left else 0), int(decks[d3 + 1]["floor"]), fy2, 30)
				md["catwalks"] = (md.get("catwalks", []) as Array) + [[bx0, bx1, fy2]]
		return
	if knd != "room" or NO_FEATURES.has(String(md["role"])) or x1 - x0 < 170:
		return
	var rw := x1 - x0
	# a mezzanine along one wall (a one-way catwalk; a ledge at its end to climb by)
	if rng.randf() < 0.5:
		var left := rng.randf() < 0.5
		var span := int(float(rw) * rng.randf_range(0.32, 0.45))
		var mx0 := x0 if left else x1 - span
		var mx1 := x0 + span if left else x1
		var my := y1 - MEZZ
		for i5 in range(mx0, mx1):
			put(i5, my, Defs.SCAFFOLD, 0)
		var lx := mx1 - 6 if left else mx0 - 22
		for i6 in range(lx, lx + 28):
			put(i6, y1 - 28, Defs.SCAFFOLD, 0)
		ways.append(Rect2i(mx0, my - 22, mx1 - mx0, 24))
		ways.append(Rect2i(lx, y1 - 50, 28, 24))
		md["mezz"] = [mx0, mx1, my, left]
	# a dais in the middle, steps up either side
	if rng.randf() < 0.3:
		var dw := int(float(rw) * rng.randf_range(0.22, 0.3))
		var dhh := rng.randi_range(3, 4) * 4
		var dx0 := x0 + rw / 2 - dw / 2 + rng.randi_range(-20, 20)
		var mz: Array = md.get("mezz", [])
		if not mz.is_empty() and dx0 < int(mz[1]) + 30 and dx0 + dw > int(mz[0]) - 30:
			return
		for i7 in range(dx0 - dhh, dx0 + dw + dhh):
			var hgt := dhh
			if i7 < dx0:
				hgt = ((i7 - (dx0 - dhh)) / 4 + 1) * 4
			elif i7 >= dx0 + dw:
				hgt = ((dx0 + dw + dhh - 1 - i7) / 4 + 1) * 4
			hgt = mini(hgt, dhh)
			for j in range(y1 - hgt, y1):
				put(i7, j, Defs.HULL, 0 if j == y1 - hgt else (1 if (j / 4) % 2 == 0 else 2))
		md["dais"] = [dx0 - dhh, dx0 + dw + dhh, y1 - dhh]

## one-way ledges to climb by, from a floor (row fy) up toward a landing (row top), every `step` rows, turn about
## between the two ends of x0..x1 (26 wide)
func _ledges(x0: int, x1: int, fy: int, top: int, step: int) -> void:
	var side := 0
	var ly := fy - step
	while ly > top + 12:
		var lx := x0 if side == 0 else x1 - 26
		for i in range(lx, lx + 26):
			put(i, ly, Defs.SCAFFOLD, 0)
		ways.append(Rect2i(lx, ly - 22, 26, 24))
		side = 1 - side
		ly -= step

## the mouth of a bay or a hangar at the end of a level: open from its floor up, out through the hull to space
func _mouth(x0: int, x1: int, y1: int, mh: int, side: int) -> void:
	var a := 0 if side < 0 else x1
	var b := x0 if side < 0 else w
	ways.append(Rect2i(a, y1 - mh, b - a, mh))
	for j in range(y1 - mh, y1):
		for i in range(a, b):
			cells[j * w + i] = 0
			bg[j * w + i] = 0
	# the apron: lights along its top, hazard stripes at the lip
	for i2 in range(a, b):
		if (i2 - a) % 6 == 2:
			put(i2, y1, Defs.CRYSTAL, 0)
		put(i2, y1 - mh - 1, Defs.COAL if ((i2 + y1) / 3) % 2 == 0 else Defs.SUNSTONE, 0)

## every piece dressed
func _dress_all(rng: RandomNumberGenerator, sd: int) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = sd
	noise.frequency = 0.09
	for k in mods.size():
		_dress_level(k, rng, noise)
		if has_method("_dress_op"):
			call("_dress_op", k, rng, noise)

## a piece's look: its roof's shape, the wall's details, lamps, the floor (gravity runes where there's power), what
## it holds for its role, upstairs on its mezzanine too; a derelict's broken ones destroyed
func _dress_level(k: int, rng: RandomNumberGenerator, noise: FastNoiseLite) -> void:
	var md: Dictionary = mods[k]
	var x0: int = md["x0"]
	var y0: int = md["y0"]
	var x1: int = md["x1"]
	var y1: int = md["y1"]
	var pw: bool = md["powered"]
	var role: String = md["role"]
	var knd: String = md["kind"]
	var derelict := kind == "station"
	var cv := Art.Cv.new()
	cv.bg = bg
	cv.bgv = bgv
	cv.w = w
	cv.h = h
	cv.rng = rng
	cv.noise = noise
	cv.dead = not pw
	cv.lived = kind == "outpost"
	var rw := x1 - x0
	var drop := PackedInt32Array()
	drop.resize(rw)
	if knd == "room" and int(md["d0"]) == int(md["d1"]):
		drop = _shape_level(k, rng, noise)
	elif knd == "corridor":
		var pf: PackedInt32Array = md["prof"]
		for i in rw:
			drop[i] = CH_BAY - pf[i]
	if role != "nest" and role != "vault":
		Art.wall_detail(cv, x0, y0, x1, y1, String(md.get("style", "plate")), drop)
	# the floor: gravity runes glowing in it where there's power
	for i2 in range(x0, x1):
		if at(i2, y1) == Defs.HULL:
			if pw:
				put(i2, y1, Defs.WISP if (i2 - x0) % 8 == 4 else Defs.RUNESTONE, 0)
			elif (i2 - x0) % 8 == 4:
				put(i2, y1, Defs.RUNESTONE, 0)
	# lamps under the roof (where it comes down to): lit, or dead
	if knd != "shaft":
		for i3 in range(x0 + 8, x1 - 6, 16):
			var lj: int = y0 + int(drop[i3 - x0])
			if at(i3, lj) == 0 and at(i3 + 1, lj) == 0 and at(i3, lj - 1) != 0 and not _near_way(i3, lj, 2) and not _near_way(i3 + 1, lj, 2):
				put(i3, lj, Defs.CRYSTAL if pw else Defs.COPPERBAR, 0)
				put(i3 + 1, lj, Defs.CRYSTAL if pw else Defs.COPPERBAR, 0)
	for cw in md.get("catwalks", []):
		Art.railing(cv, int(cw[0]), int(cw[1]), int(cw[2]))
	var mx := (x0 + x1) / 2
	var my := (y0 + y1) / 2
	match role:
		"reactor":
			# a great wisp core on the back wall, rings of crystal round it, conduits to the roof and the floor
			var cr := int(float(mini(rw, y1 - y0)) * 0.2)
			for j4 in range(my - cr - 6, my + cr + 6):
				for i4 in range(mx - cr - 6, mx + cr + 6):
					var dd := Vector2(i4 - mx, j4 - my).length()
					if dd < float(cr):
						bg[j4 * w + i4] = Defs.WISP if pw else Defs.WISPBAR
						bgv[j4 * w + i4] = int(dd) % 4
					elif dd < float(cr) + 3.0 or (absf(dd - float(cr) - 5.0) < 0.8 and int(dd * 3.0 + float(i4)) % 5 != 0):
						bg[j4 * w + i4] = Defs.CRYSTAL if pw else Defs.COPPERBAR
						bgv[j4 * w + i4] = 0
			for cx in [mx - 6, mx + 6]:
				for j5 in range(y0 + 4, my - cr - 6):
					bg[j5 * w + int(cx)] = Defs.COPPERBAR
					bg[j5 * w + int(cx) + 1] = Defs.COPPERBAR
				for j6 in range(my + cr + 6, y1):
					bg[j6 * w + int(cx)] = Defs.COPPERBAR
					bg[j6 * w + int(cx) + 1] = Defs.COPPERBAR
			Art.pipes(cv, x0, x1, y0 + 8, 3)
		"dock":
			for i13 in range(x0, x1):
				if ((i13 / 4) % 2) == 0:
					put(i13, y1, Defs.SUNSTONE, 0)
			for cx2 in [x0 + 24, x1 - 24]:
				for i14 in range(int(cx2) - 3, int(cx2) + 3):
					if not _near_way(i14, y1 - 1, 2):
						put(i14, y1 - 1, Defs.COPPERBAR, 2)
		"nest":
			# the hive: xenite grown over the walls, the floor and the roof, egg sacs on the floor
			for j15 in range(y0, y1):
				for i15 in range(x0, x1):
					var wall_d := mini(mini(i15 - x0, x1 - 1 - i15), mini(j15 - y0, y1 - 1 - j15))
					var n := noise.get_noise_2d(i15 * 2.3, j15 * 2.3)
					if wall_d < 4 and n > 0.05 and not _near_way(i15, j15, 4):
						put(i15, j15, Defs.XENITE, (i15 + j15) % 4)
					if n > -0.2:
						bg[j15 * w + i15] = Defs.XENITE if n > 0.25 else Defs.COAL
						bgv[j15 * w + i15] = (i15 * 3 + j15) % 4
			for ex in range(x0 + 14, x1 - 14, 13):
				if rng.randf() < 0.7 and not _near_way(ex, y1 - 3):
					for je in range(y1 - 6, y1):
						for ie in range(ex - 2, ex + 3):
							if Vector2(ie - ex, (je - (y1 - 3)) * 0.8).length() < 2.8:
								put(ie, je, Defs.XENITE, 1 if (ie + je) % 2 == 0 else 3)
			# strands hanging from the roof
			for sx in range(x0 + 10, x1 - 10, 9):
				if rng.randf() < 0.5:
					var sl := rng.randi_range(10, 50)
					for q in sl:
						bg[(y0 + q) * w + sx + (1 if q % 7 > 4 else 0)] = Defs.XENITE
		"vault":
			for j16 in range(y0, y1):
				for i16 in range(x0, x1):
					bg[j16 * w + i16] = Defs.RUNESTONE
					bgv[j16 * w + i16] = (i16 / 4 + j16 / 4) % 3
					if (i16 - x0) % 10 == 5 and (j16 - y0) % 10 == 5:
						bg[j16 * w + i16] = Defs.WISP
		"corridor":
			Art.corridor(cv, x0, y0, x1, y1, md["prof"])
		"shaft":
			# a sign at each landing, pipes up its back wall, hazard stripes along its landings
			for d in range(int(md["d0"]), int(md["d1"]) + 1):
				var fy: int = decks[d]["floor"]
				Art.signboard(cv, x0 + 18, fy - 34, 24, Art.LED_Y)
				for i17 in range(x0, x1):
					cv.p(i17, fy - 1, Art.HAZARD if ((i17 - x0) / 3) % 2 == 0 else Art.BLACK, 0)
			for px in [x0 + 6, x1 - 8]:
				for j17 in range(y0, y1):
					cv.p(int(px), j17, Art.PIPE, 2 if j17 % 22 == 0 else 0)
		"hangar":
			pass
		_:
			# what the room holds, at the floor (its things on the wall about head height up), its mezzanine's
			# things up there, and on a tall wall with nothing above, pipes, windows and signs
			var band_top := y0 if role == "hall" or role == "promenade" or role == "observatory" else maxi(y0, y1 - 84)
			var mz: Array = md.get("mezz", [])
			if mz.is_empty():
				Art.furnish(cv, role, x0, band_top, x1, y1)
				if y1 - y0 > 120 and band_top > y0:
					Art.pipes(cv, x0, x1, y1 - 100, 2)
					var wx := x0 + rng.randi_range(10, 40)
					while wx + 24 < x1 - 10:
						if rng.randf() < 0.45:
							Art.window(cv, wx, y0 + int(drop[wx - x0]) + 12, 22, 14)
						elif rng.randf() < 0.4:
							Art.poster(cv, wx, y1 - 116, 8, 11)
						wx += rng.randi_range(40, 70)
			else:
				var mx0: int = mz[0]
				var mx1: int = mz[1]
				var myy: int = mz[2]
				# downstairs, and upstairs on the catwalk
				Art.furnish(cv, role, x0, maxi(y0, y1 - 84), x1, y1)
				Art.furnish(cv, _upstairs(role), mx0 + 2, maxi(y0, myy - 70), mx1 - 2, myy)
				Art.railing(cv, mx0, mx1, myy)
			if derelict and pw:
				Art.debris(cv, x0, x1, y1)
	if derelict and not pw and role != "vault":
		_destroy(k, rng, noise, cv)

## what stands up on a mezzanine, by the room under it
func _upstairs(role: String) -> String:
	match role:
		"quarters", "cabins":
			return "quarters"
		"mess", "galley", "lounge":
			return "lounge"
		"lab", "medbay":
			return "lab"
		"engineering", "armory":
			return "stores"
		"command", "comms":
			return "comms"
		"hydro":
			return "hydro"
		"brig":
			return "stores"
	return "stores"

## a room's roof: its shape by role (as `_shape`), deeper for a tall room, sometimes a soffit hanging over one side;
## in a derelict's broken rooms caved in over a heap of rubble
func _shape_level(k: int, rng: RandomNumberGenerator, noise: FastNoiseLite) -> PackedInt32Array:
	var md: Dictionary = mods[k]
	var x0: int = md["x0"]
	var y0: int = md["y0"]
	var x1: int = md["x1"]
	var y1: int = md["y1"]
	var role: String = md["role"]
	var rw := x1 - x0
	var rh := y1 - y0
	var drop := PackedInt32Array()
	drop.resize(rw)
	if role == "dock" or role == "hangar" or role == "reactor" or role == "nest" or role == "vault":
		return drop
	var sc := float(rh) / 64.0 * 0.8
	var kind_s := "chamfer"
	match role:
		"observatory", "command":
			kind_s = "dome"
		"lounge", "quarters", "mess", "cantina", "cabins", "galley":
			kind_s = "arch" if rng.randf() < 0.6 else "chamfer"
		"engineering", "stores", "comms", "shipwright", "armory":
			kind_s = "duct"
		"hall", "promenade":
			kind_s = "vault"
	var duct_l := rng.randf() < 0.5
	for i in rw:
		var u := (float(i) + 0.5) / float(rw) * 2.0 - 1.0
		var d := 0.0
		match kind_s:
			"dome":
				d = 18.0 * sc * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
			"arch":
				d = 11.0 * sc * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
			"vault":
				d = (12.0 if absf(u) > 0.82 else (6.0 if absf(u) > 0.55 else 0.0)) * sc
			"duct":
				var side := i < 40 if duct_l else i >= rw - 40
				d = 9.0 * sc if side else 0.0
				d = maxf(d, 8.0 - float(mini(i, rw - 1 - i)))
			_:
				d = maxf(0.0, 10.0 - float(mini(i, rw - 1 - i)))
		drop[i] = int(d)
	# a soffit: the roof hanging low over one side (an L of a room), its inner corner chamfered
	if rh > 120 and rng.randf() < 0.3 and not md.has("mezz"):
		var sw2 := int(float(rw) * rng.randf_range(0.25, 0.38))
		var sd2 := rh - rng.randi_range(96, 112)
		var on_l := rng.randf() < 0.5
		for i2 in rw:
			var inn := (sw2 - i2) if on_l else (i2 - (rw - sw2))
			if inn >= 0:
				drop[i2] = maxi(int(drop[i2]), sd2 - maxi(0, 12 - inn))
	# caved in: a jagged chunk of the roof come down, over the heap it made
	if kind == "station" and not bool(md["powered"]) and rng.randf() < 0.7:
		var cw := rng.randi_range(30, 70)
		var cx := rng.randi_range(x0 + 50, maxi(x0 + 51, x1 - 50 - cw))
		for i3 in range(cx, cx + cw):
			var u2 := float(i3 - cx) / float(cw)
			var dep := int((sin(u2 * PI) * float(rng.randi_range(26, 46))) + noise.get_noise_2d(float(i3) * 3.0, 7.0) * 8.0)
			drop[i3 - x0] = maxi(int(drop[i3 - x0]), dep)
		md["cave"] = [cx, cx + cw]
	for i4 in rw:
		var ci := x0 + i4
		for j in range(y0, y0 + int(drop[i4])):
			if _near_way(ci, j, 3):
				drop[i4] = j - y0
				break
			put(ci, j, Defs.HULL, 0 if j == y0 + int(drop[i4]) - 1 else (1 if (j / 4) % 2 == 0 else 2))
	if kind_s == "duct":
		for i5 in rw:
			var ci5 := x0 + i5
			var dj: int = y0 + int(drop[i5])
			if int(drop[i5]) >= 6 and at(ci5, dj) == 0 and not _near_way(ci5, dj, 3):
				bg[dj * w + ci5] = Art.PIPE
				bgv[dj * w + ci5] = 3 if ci5 % 12 == 0 else 0
	return drop

## a derelict's broken room torn up: scorched near its walls, a heap of rubble under where its roof caved in (or just
## on the floor), a girder fallen, a breach through an outer wall into the dark beyond, claws and goo
func _destroy(k: int, rng: RandomNumberGenerator, noise: FastNoiseLite, cv) -> void:
	var md: Dictionary = mods[k]
	var x0: int = md["x0"]
	var y0: int = md["y0"]
	var x1: int = md["x1"]
	var y1: int = md["y1"]
	for j in range(y0 - BW, y1 + FS):
		for i in range(x0 - BW, x1 + BW):
			if i > x0 + 6 and i < x1 - 6 and j > y0 + 6 and j < y1 - 4:
				continue
			if at(i, j) == Defs.HULL and noise.get_noise_2d(i * 5.0, j * 5.0) > 0.4:
				put(i, j, Defs.COAL, 0)
	if String(md["kind"]) == "room" and x1 - x0 >= 160:
		var cave: Array = md.get("cave", [])
		var hx0: int = int(cave[0]) - 10 if not cave.is_empty() else rng.randi_range(x0 + 50, x1 - 120)
		var hx1: int = int(cave[1]) + 10 if not cave.is_empty() else hx0 + rng.randi_range(40, 70)
		var top := rng.randi_range(10, 22)
		var prev := 0
		for i2 in range(hx0, hx1):
			if _near_way(i2, y1 - 2, 6):
				prev = 0
				continue
			var u := float(i2 - hx0) / float(hx1 - hx0)
			var hg := int(sin(u * PI) * float(top) + noise.get_noise_2d(float(i2) * 4.0, 31.0) * 4.0)
			hg = clampi(hg, 0, prev + 4)
			prev = hg
			for j2 in range(y1 - hg, y1):
				var rr := absi(int(noise.get_noise_2d(float(i2) * 9.0, float(j2) * 9.0) * 100.0)) % 10
				put(i2, j2, Defs.HULL if rr < 6 else (Defs.COAL if rr < 9 else Defs.COPPERBAR), rr % 4)
		# (and back down the far side, never a cliff)
		var i3 := hx1
		while prev > 0 and i3 < x1 - 2:
			prev -= 4
			for j3 in range(y1 - maxi(prev, 0), y1):
				if at(i3, j3) == 0:
					put(i3, j3, Defs.HULL, 1)
			i3 += 1
	if rng.randf() < 0.6 and x1 - x0 > 60:
		var gx := rng.randi_range(x0 + 6, x1 - 40)
		var gy := rng.randi_range(y0 + 10, maxi(y0 + 11, y1 - 60))
		for q in 34:
			var gi := gx + q
			var gj := gy + q / 2
			if not _near_way(gi, gj) and gj < y1 - 20:
				put(gi, gj, Defs.COPPERBAR, 2)
				put(gi, gj + 1, Defs.COPPERBAR, 0)
	var outer := []
	if int(md["d0"]) == 0:
		outer.append(Vector2(rng.randi_range(x0 + 20, x1 - 20), y0 - 2))
	if x0 <= HM + 1 and k != dock:
		outer.append(Vector2(x0 - 2, rng.randi_range(y0 + 20, y1 - 60)))
	if x1 >= w - HM - 1 and k != dock:
		outer.append(Vector2(x1 + 1, rng.randi_range(y0 + 20, y1 - 60)))
	if not outer.is_empty() and rng.randf() < 0.75:
		_breach(outer[rng.randi_range(0, outer.size() - 1)], rng.randf_range(9.0, 15.0), noise)
	for q2 in rng.randi_range(1, 3):
		Art.claws(cv, rng.randi_range(x0 + 6, maxi(x0 + 7, x1 - 20)), y1 - rng.randi_range(24, 60))
	if rng.randf() < 0.7:
		Art.smear(cv, rng.randi_range(x0 + 4, maxi(x0 + 5, x1 - 40)), y1, rng.randi_range(16, 40))

## a level's crates, by the role of the room they're in
func _caches_level(k: int, rng: RandomNumberGenerator) -> void:
	if kind != "station":
		return
	var mk: Dictionary = mods[k]
	var fl: int = int(mk["y1"])
	var a0: int = int(mk["x0"]) + 3
	var a1: int = int(mk["x1"]) - 3
	match String(mk["role"]):
		"stores", "armory":
			_crate_near(a0 + 12, fl, "stores", a0, a1)
			_crate_near(a1 - 24, fl, "stores", a0, a1)
		"quarters", "cabins", "lab", "brig":
			_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, "quarters" if String(mk["role"]) != "lab" else "lab", a0, a1)
		"medbay":
			_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, "lab", a0, a1)
		"nest":
			_crate_near(a1 - 18, fl, "nest", a0, a1)
		"vault":
			_crate_near((a0 + a1) / 2 - CRATE_W / 2, fl, VAULT_CRATE, a0, a1)
		"corridor", "shaft", "dock":
			if rng.randf() < 0.2:
				_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, "stores", a0, a1)
		_:
			if rng.randf() < 0.55:
				_crate_near(rng.randi_range(a0, a1 - CRATE_W), fl, "stores", a0, a1)
	var mz: Array = mk.get("mezz", [])
	if not mz.is_empty() and rng.randf() < 0.5:
		_crate_near(int(mz[0]) + 6, int(mz[2]), "stores", int(mz[0]) + 2, int(mz[1]) - 2)

## where a level's aliens live: more in a big room, a few along the corridors, now and then one in a shaft, the brood
## in her nest
func _plan_aliens_level(rng: RandomNumberGenerator) -> void:
	var id := 0
	for k in mods.size():
		var md: Dictionary = mods[k]
		var role: String = md["role"]
		var knd: String = md["kind"]
		if role == "dock" or role == "vault":
			continue
		var pw: bool = md["powered"]
		var rw: int = int(md["x1"]) - int(md["x0"])
		var list := []
		if role == "nest":
			list = ["brood", "skitter", "skitter", "skitter", "drifter", "drifter"]
		elif knd == "corridor":
			for q in clampi(rw / 180, 0, 2):
				if rng.randf() < 0.6:
					list.append("skitter" if pw or rng.randf() < 0.5 else "drifter")
		elif knd == "shaft":
			if rng.randf() < 0.45:
				list.append("drifter" if not pw else "skitter")
		else:
			for q2 in clampi(rw / 110, 1, 3):
				if pw:
					list.append("brute" if rng.randf() < 0.28 and role != "reactor" else "skitter")
				else:
					list.append("drifter" if rng.randf() < 0.55 else "skitter")
		for kd in list:
			var half: Vector2 = {"skitter": Vector2(5, 3), "drifter": Vector2(5.5, 6.5), "brute": Vector2(7, 10), "brood": Vector2(19, 13)}[kd]
			var x0: int = md["x0"]
			var x1: int = md["x1"]
			var y1: int = md["y1"]
			var ytop: int = maxi(int(md["y0"]), y1 - 130)
			var flier: bool = kd == "drifter" or kd == "brood"
			var b := Vector2(float(rng.randi_range(x0 + 14, x1 - 14)), float(y1) - half.y - 1.0)
			if flier:
				b.y = float(rng.randi_range(ytop + int(half.y) + 4, y1 - 30))
			if kd == "brood":
				b = Vector2(float(x0 + x1) * 0.5, float(y1) - 70.0)
			for t in 20:
				if box_free(b, half.x + 0.5, half.y + 0.5):
					break
				b.x = float(rng.randi_range(x0 + int(half.x) + 2, x1 - int(half.x) - 2))
				if flier:
					b.y = float(rng.randi_range(ytop + int(half.y) + 4, y1 - int(half.y) - 4))
				else:
					b.y = float(y1) - half.y - 1.0
			spawns.append({"id": id, "kind": kd, "b": b, "mod": k})
			id += 1

## the last of growing a level: its mass, its pictures painted (the doors' panels are drawn apart, `draw_level`)
func _finish_level() -> void:
	rebuild()
	rad = maxf(3.0, sqrt(mass / PI))
	ang = 0.0
	omega = 0.0
	_pre_fg = _paint(cells, vars, false)
	for dr in doors:
		if not dr["sealed"]:
			_pre_fg.fill_rect(Rect2i(int(dr["x"]), int(dr["y1"]) - HDOOR, BW, HDOOR), Color(0, 0, 0, 0))
	_pre_bg = _paint(bg, bgv, true)
	vis.resize(mods.size())
	vis.fill(0.0)
	_bg_dirty = true
	dirty = true

# ------------------------------------------------------------------- doors ---

## the doors: each opens as someone comes near it (you, a woken alien, a spacer: `pts`, in its cells) and shuts behind
## them, never on anyone in it; a sealed one stays shut. Returns what happened: [[where (cells), "open" / "shut"]]
func doors_tick(pts: Array) -> Array:
	var ev := []
	for dr in doors:
		if dr["sealed"]:
			continue
		var cx := float(int(dr["x"])) + float(BW) * 0.5
		var cy := float(int(dr["y1"])) - float(HDOOR) * 0.5
		var want := false
		for p in pts:
			if absf((p as Vector2).x - cx) < 44.0 and absf((p as Vector2).y - cy) < 36.0:
				want = true
				break
		var f0: float = dr["f"]
		var f1 := minf(1.0, f0 + 0.1) if want else maxf(0.0, f0 - 0.05)
		if f1 == f0:
			continue
		if f1 < f0:
			var busy := false
			for p2 in pts:
				var pv: Vector2 = p2
				if absf(pv.x - cx) < float(BW) * 0.5 + 9.0 and pv.y > float(int(dr["y1"]) - HDOOR) - 12.0 and pv.y < float(int(dr["y1"])) + 2.0:
					busy = true
			if busy:
				continue
		dr["f"] = f1
		_door_set(dr)
		if f0 == 0.0:
			ev.append([Vector2(cx, cy), "open"])
		elif f1 == 0.0:
			ev.append([Vector2(cx, cy), "shut"])
	return ev

## a door's cells as its panel stands: shut from its top down by how far it's open (the panel slides up into the
## lintel); its picture is drawn apart (`draw_level`), so the cells change and nothing is painted
func _door_set(dr: Dictionary) -> void:
	var n := int(round((1.0 - float(dr["f"])) * float(HDOOR)))
	var n0: int = dr["n"]
	if n == n0:
		return
	var x: int = dr["x"]
	var ytop: int = int(dr["y1"]) - HDOOR
	for j in range(ytop + mini(n, n0), ytop + maxi(n, n0)):
		var m := Defs.HULL if j < ytop + n else 0
		for i in range(x, x + BW):
			cells[j * w + i] = m
	dr["n"] = n

## every door open (the tests' look at what's reachable)
func open_all_doors() -> void:
	for dr in doors:
		if not dr["sealed"]:
			dr["f"] = 1.0
			_door_set(dr)

## what you can see from room k (a derelict's): that room, and through each open door of it the room beyond; what
## you saw before fades back into the dark
func see_from(k: int) -> void:
	if vis.size() != mods.size():
		vis.resize(mods.size())
		vis.fill(0.0)
	var want := PackedFloat32Array()
	want.resize(mods.size())
	want.fill(0.0)
	if k >= 0:
		want[k] = 1.0
		for dr in doors:
			if float(dr["f"]) > 0.2 and (int(dr["a"]) == k or int(dr["b"]) == k):
				want[int(dr["b"]) if int(dr["a"]) == k else int(dr["a"])] = 1.0
	for q in vis.size():
		vis[q] = move_toward(vis[q], want[q], 0.07)

## can you see room k (well enough to see what's in it)?
func seen(k: int) -> bool:
	return not lv or kind != "station" or k < 0 or k >= vis.size() or vis[k] > 0.5

## a level's doors drawn over its picture (each as far shut as it is), and in a derelict the dark: rooms you can't
## see into black, a broken room dim even when you're in it, its emergency light failing now and then. `xf`: its
## cells (from the corner) to the screen.
func draw_level(ci: CanvasItem, xf: Transform2D, dark: bool, t: float) -> void:
	ci.draw_set_transform_matrix(xf)
	if _door_tex == null:
		_door_tex = ImageTexture.create_from_image(Art.door_image(BW, HDOOR, kind == "station"))
	for dr in doors:
		if dr["sealed"]:
			continue
		var n: int = dr["n"]
		if n <= 0:
			continue
		ci.draw_texture_rect_region(_door_tex, Rect2(float(int(dr["x"])), float(int(dr["y1"]) - HDOOR), float(BW), float(n)),
			Rect2(0.0, float(HDOOR - n), float(BW), float(n)))
	if dark and vis.size() == mods.size():
		var tick := int(t / 5.0)
		for k in mods.size():
			var md: Dictionary = mods[k]
			var a := (1.0 - vis[k]) * 0.95
			if not md["powered"]:
				var fl := 0.32
				if ((tick * 7919 + k * 104729) >> 3) % 61 < 2:
					fl = 0.62
				a = maxf(a, fl)
			if a > 0.01:
				ci.draw_rect(Rect2(float(int(md["x0"])), float(int(md["y0"])), float(int(md["x1"]) - int(md["x0"])), float(int(md["y1"]) - int(md["y0"]))), Color(0.0, 0.0, 0.015, a))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

## an outpost's glowing cells gathered into halos (blocks of 16, every other cell looked at), as it's grown
func _gather_lights() -> void:
	lights = []
	for by in range(0, h, 16):
		for bx in range(0, w, 16):
			var n := 0
			var col := Color(0, 0, 0)
			var sx := 0.0
			var sy := 0.0
			for j in range(by, mini(by + 16, h), 2):
				var row := j * w
				for i in range(bx, mini(bx + 16, w), 2):
					var mt: int = cells[row + i]
					if mt == 0 or Defs.SELF[mt] == 0:
						var bm: int = bg[row + i]
						if bm >= 128 and Art.glows(bm):
							n += 1
							col += Art.GLOW[bm]
							sx += float(i)
							sy += float(j)
						continue
					n += 1
					col += Color.hex((Defs.PAL[mt * 4] << 8) | 0xff)
					sx += float(i)
					sy += float(j)
			if n > 0:
				lights.append([Vector2(sx / n + 0.5, sy / n + 0.5), 12.0 + sqrt(float(n * 4)) * 4.0, col / float(n)])
