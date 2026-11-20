## Pathfinding for foes, on the coarse nav map of a mage's collision grid (shaders/navmap.comp: one
## byte per 4 x 4 cells, read back with the grid every frame). Every EVERY frames, while some foe is
## asking, the map goes to a worker thread, which builds a graph for each kind of body that asked:
##   walk  a platform graph (AStar2D): a node wherever the body can stand; edges to walk to the next
##         block (level, or a step up or down), drop off an edge or down through the platform it
##         stands on, jump straight up to a ledge or a platform within its jump and move over at the
##         top, or jump a gap
##   fly   a grid of the places the body fits (AStarGrid2D)
##   swim  the same, in water only
## Godot searches them in C++. Paths come back as world points, so they stay good while the grid
## moves with the mage. A body's class is its size in blocks (and for walkers its jump): key_for.
extends RefCounted

const C := 4                    # grid cells to a nav block
const EVERY := 12               # frames between builds (while asked)
const FORGET := 150             # a class nobody has asked for this many frames isn't built again

var g                           # main.gd
var slot := 0                   # whose collision grid it reads
var data := {}                  # the graphs in use: {"G", "A", "half", "n", "np", "map", "fit": {key: bytes}, "graph": {key: graph}}
var want := {}                  # class key -> [kind, wb, hb, jh, frame last asked]
var builds := 0                 # (how many graphs it has built: the tests look)
var build_us := 0               # (how long the last build took on its thread)
var _task := -1
var _job := {}
var _built_f := -99999

func _init(game, s: int) -> void:
	g = game
	slot = s

## the class a body paths as: "w<wb>x<hb>j<jh>" (walks; jh: blocks it can jump up; a "d" after it:
## it opens doors, so they don't stop it), "f<wb>x<hb>" (flies), "s<wb>x<hb>" (swims)
static func key_for(kind: String, w: float, h: float, jump_h := 0.0, doors := false) -> String:
	# (a flier keeps a little room round it: its way runs clear of ceilings and walls, not along them)
	var pad := 0.0 if kind == "walk" else 4.0
	var wb := clampi(int(ceil((w + pad) / C)), 1, 9)
	var hb := clampi(int(ceil((h + pad) / C)), 1, 10)
	if kind == "walk":
		return "w%dx%dj%d%s" % [wb, hb, clampi(int(floor(jump_h / C)), 0, 12), "d" if doors else ""]
	return "%s%dx%d" % [kind.left(1), wb, hb]

## a foe asks for its class to be built (every frame it wants paths)
func ask(key: String) -> void:
	if want.has(key):
		(want[key] as Array)[4] = g.frame
		return
	var kind := "walk" if key.begins_with("w") else ("fly" if key.begins_with("f") else "swim")
	var p := key.substr(1).replace("d", "").replace("x", " ").replace("j", " ").split(" ")
	want[key] = [kind, int(p[0]), int(p[1]), int(p[2]) if p.size() > 2 else 0, g.frame, key.ends_with("d")]

func has(key: String) -> bool:
	return data.has("graph") and (data["graph"] as Dictionary).has(key)

## (main.gd, each frame its grid has just been read back: m is the mage whose grid this is)
func tick(m) -> void:
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		data = _job
		_job = {}
		builds += 1
	for k in want.keys():
		if g.frame - int(want[k][4]) > FORGET:
			want.erase(k)
	if want.is_empty() or g.frame - _built_f < EVERY:
		return
	var gpu = g.gpu
	var nb: int = gpu.NG * gpu.NGP
	if gpu.nav_off <= 0 or gpu.grid.size() < gpu.nav_off + (slot + 1) * nb:
		return
	_built_f = g.frame
	_job = {"G": m.grid_g, "A": m.grid_a, "half": float(gpu.GS) * 0.5, "n": gpu.NG, "np": gpu.NGP,
		"map": gpu.grid.slice(gpu.nav_off + slot * nb, gpu.nav_off + (slot + 1) * nb), "classes": want.duplicate(true)}
	_task = WorkerThreadPool.add_task(_build, false, "nav graphs")

## (main.gd, leaving the planet) forget everything
func clear() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	data = {}
	_job = {}
	want.clear()

# ------------------------------------------------------------------ building ---
## (worker thread) the graphs for every class asked for, from the job's map
func _build() -> void:
	var t0 := Time.get_ticks_usec()
	var job := _job
	var n: int = job["n"]
	var np: int = job["np"]
	var map: PackedByteArray = job["map"]
	# open blocks in a row going up, ending at each block (doors shut, and doors walked through)
	var up := PackedByteArray()
	var up_d := PackedByteArray()
	up.resize(n * n)
	up_d.resize(n * n)
	for x in n:
		var run := 0
		var run_d := 0
		for y in n:
			var b := map[y * np + x]
			run = 0 if (b & 17) != 0 else mini(run + 1, 255)
			run_d = 0 if (b & 1) != 0 else mini(run_d + 1, 255)
			up[y * n + x] = run
			up_d[y * n + x] = run_d
	var fits := {}
	var graphs := {}
	var classes: Dictionary = job["classes"]
	for key in classes:
		var cl: Array = classes[key]
		var fit := _fit(up_d if (cl.size() > 5 and bool(cl[5])) else up, n, int(cl[1]), int(cl[2]))
		fits[key] = fit
		match String(cl[0]):
			"walk":
				graphs[key] = _walk_graph(map, np, fit, n, int(cl[1]), int(cl[3]))
			"fly":
				graphs[key] = _grid_graph(map, np, fit, n, int(cl[2]), false)
			"swim":
				graphs[key] = _grid_graph(map, np, fit, n, int(cl[2]), true)
	job["fit"] = fits
	job["graph"] = graphs
	build_us = Time.get_ticks_usec() - t0

## fit[y * n + x]: a body wb x hb blocks fits with its feet in block row y, centred on column x
static func _fit(up: PackedByteArray, n: int, wb: int, hb: int) -> PackedByteArray:
	var fit := PackedByteArray()
	fit.resize(n * n)
	var lo := (wb - 1) / 2
	for y in n:
		var row := y * n
		for x in range(lo, n - (wb - 1 - lo)):
			var ok := 1
			for c in range(x - lo, x - lo + wb):
				if up[row + c] < hb:
					ok = 0
					break
			fit[row + x] = ok
	return fit

## the walkers' graph: nodes where the body stands, edges to where it can get from there
static func _walk_graph(map: PackedByteArray, np: int, fit: PackedByteArray, n: int, wb: int, jh: int) -> AStar2D:
	var a := AStar2D.new()
	var lo := (wb - 1) / 2
	# standing: it fits and something holds it up under one of its columns (2: only a platform)
	var stand := PackedByteArray()
	stand.resize(n * n)
	var count := 0
	for y in n - 1:
		var row := y * n
		var below := (y + 1) * np
		for x in n:
			if fit[row + x] == 0:
				continue
			var held := 0
			for c in range(maxi(x - lo, 0), mini(x - lo + wb, n)):
				var b := map[below + c]
				if (b & 17) != 0:
					held = 1
					break
				if (b & 2) != 0:
					held = 2
			if held != 0:
				stand[row + x] = held
				count += 1
	if count == 0:
		return a
	a.reserve_space(count)
	for y2 in n - 1:
		for x2 in n:
			if stand[y2 * n + x2] != 0:
				a.add_point(y2 * n + x2, Vector2(x2, y2))
	var jx := wb + 2                 # how far over it reaches at the top of a jump
	var gx := 4                      # the widest gap it jumps
	for y in n - 1:
		for x in n:
			var id := y * n + x
			if stand[id] == 0:
				continue
			for dx in [-1, 1]:
				var nx: int = x + dx
				if nx < 0 or nx >= n:
					continue
				# walking on: level, or a step up or down
				var walked := false
				for dy in [0, -1, 1]:
					var ny: int = y + dy
					if ny >= 0 and ny < n - 1 and stand[ny * n + nx] != 0:
						a.connect_points(id, ny * n + nx, false)
						walked = true
						break
				if walked:
					continue
				if fit[id - x + nx] != 0:
					# off the edge: down that column to whatever it lands on
					var yy := y + 1
					while yy < n - 1 and fit[yy * n + nx] != 0 and stand[yy * n + nx] == 0:
						yy += 1
					if yy < n - 1 and stand[yy * n + nx] != 0:
						a.connect_points(id, yy * n + nx, false)
				# a gap: a jump over it to the far side (clear a block above the way across)
				for dist in range(2, gx + 1):
					var tx: int = x + dx * dist
					if tx < 0 or tx >= n:
						break
					var clear := true
					for k in range(1, dist + 1):
						if y < 1 or fit[(y - 1) * n + x + dx * k] == 0:
							clear = false
							break
					if not clear:
						break
					var landed := false
					for dy2 in [0, -1, 1]:
						var ty: int = y + dy2
						if ty >= 0 and ty < n - 1 and stand[ty * n + tx] != 0:
							a.connect_points(id, ty * n + tx, false)
							landed = true
							break
					if landed:
						break
			# down through the platform it stands on
			if stand[id] == 2:
				var yd := y + 1
				while yd < n - 1 and fit[yd * n + x] != 0 and stand[yd * n + x] == 0:
					yd += 1
				if yd < n - 1 and stand[yd * n + x] != 0 and yd > y:
					a.connect_points(id, yd * n + x, false)
			# up: straight up from here (its head clear all the way), then over onto a ledge or a
			# platform at the top
			for dy3 in range(1, jh + 1):
				var ty2 := y - dy3
				if ty2 < 0 or fit[ty2 * n + x] == 0:
					break
				for dx3 in range(-jx, jx + 1):
					var tx2 := x + dx3
					if tx2 < 0 or tx2 >= n or stand[ty2 * n + tx2] == 0:
						continue
					if dy3 == 1 and absi(dx3) <= 1:
						continue          # (a step: walking covers it)
					var over := true
					var s := signi(dx3)
					for k2 in range(1, absi(dx3)):
						if fit[ty2 * n + x + s * k2] == 0:
							over = false
							break
					if over:
						a.connect_points(id, ty2 * n + tx2, false)
	return a

## fliers (and swimmers, in water only): a grid of the blocks the body's middle can be in
static func _grid_graph(map: PackedByteArray, np: int, fit: PackedByteArray, n: int, hb: int, water: bool) -> AStarGrid2D:
	var ag := AStarGrid2D.new()
	ag.region = Rect2i(0, 0, n, n)
	ag.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	ag.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	ag.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	ag.update()
	var lift := hb / 2               # its middle is this many blocks above its feet
	for y in n:
		var run0 := -1
		for x in n + 1:
			var open := false
			if x < n:
				var fy := y + lift
				open = fy < n and fit[fy * n + x] != 0
				if open and water:
					open = (map[y * np + x] & 4) != 0
			if not open:
				if run0 < 0:
					run0 = x
			elif run0 >= 0:
				ag.fill_solid_region(Rect2i(run0, y, x - run0, 1), true)
				run0 = -1
		if run0 >= 0 and run0 < n:
			ag.fill_solid_region(Rect2i(run0, y, n - run0, 1), true)
	return ag

# ------------------------------------------------------------------- queries ---
## a world point as nav blocks (fractional) in the graphs' frame
func to_block(p: Vector2) -> Vector2:
	var o: Vector2 = p - data["G"]
	var a: float = data["A"]
	return Vector2(o.dot(Vector2(sin(a), -cos(a))) + float(data["half"]), o.dot(Vector2(-cos(a), -sin(a))) + float(data["half"])) / float(C)

func from_block(b: Vector2) -> Vector2:
	var a: float = data["A"]
	var q := b * float(C) - Vector2(float(data["half"]), float(data["half"]))
	return data["G"] + Vector2(sin(a), -cos(a)) * q.x + Vector2(-cos(a), -sin(a)) * q.y

## The way a walker of class key gets from its feet (world) to near `to` (the feet of what it's
## after): the feet points it stands at along the way (the first is where it is). With no way all the
## way there, the way to where it can get nearest. [] when its graph isn't built yet.
func walk_path(key: String, feet: Vector2, to: Vector2) -> PackedVector2Array:
	if not has(key):
		return PackedVector2Array()
	var ag: AStar2D = data["graph"][key]
	var n: int = data["n"]
	var fa := _stand_near(ag, to_block(feet), n)
	var fb := _stand_near(ag, to_block(to), n)
	var out := PackedVector2Array()
	if fa < 0 or fb < 0:
		return out
	for id in ag.get_id_path(fa, fb, true):
		out.append(from_block(Vector2(float(id % n) + 0.5, float(id / n) + 1.0)))
	return out

## the standing node nearest a feet point (block coordinates), -1 if there are none
static func _stand_near(ag: AStar2D, b: Vector2, n: int) -> int:
	var bx := int(floor(b.x))
	var by := int(floor(b.y - 0.25))          # (feet on a block's bottom edge stand in that block)
	var best := -1
	var bd := 1e9
	for dy in [0, -1, 1, -2, 2]:
		for dx in [0, -1, 1, -2, 2]:
			var x: int = bx + dx
			var y: int = by + dy
			if x < 0 or y < 0 or x >= n or y >= n:
				continue
			var id: int = y * n + x
			if ag.has_point(id):
				var d := Vector2(x + 0.5, y + 1.0).distance_squared_to(b)
				if d < bd:
					bd = d
					best = id
	if best < 0 and ag.get_point_count() > 0:
		best = ag.get_closest_point(Vector2(bx, by))
	return best

## The way a flier (or swimmer) of class key gets from `from` to near `to` (world points of its
## middle). [] when its graph isn't built yet.
func fly_path(key: String, from: Vector2, to: Vector2) -> PackedVector2Array:
	if not has(key):
		return PackedVector2Array()
	var ag: AStarGrid2D = data["graph"][key]
	var a := _open_near(ag, to_block(from))
	var b := _open_near(ag, to_block(to))
	var out := PackedVector2Array()
	if a.x < 0 or b.x < 0:
		return out
	for p in ag.get_id_path(a, b, true):
		out.append(from_block(Vector2(p) + Vector2(0.5, 0.5)))
	return out

## is the straight line between two world points open all the way for a flier of class key?
func fly_clear(key: String, from: Vector2, to: Vector2) -> bool:
	if not has(key):
		return true
	var ag: AStarGrid2D = data["graph"][key]
	var a := to_block(from)
	var b := to_block(to)
	var steps := int(ceil(a.distance_to(b) * 1.5)) + 1
	for k in steps + 1:
		var q := a.lerp(b, float(k) / float(steps))
		var c := Vector2i(int(floor(q.x)), int(floor(q.y)))
		if not ag.is_in_boundsv(c) or ag.is_point_solid(c):
			return false
	return true

static func _open_near(ag: AStarGrid2D, b: Vector2) -> Vector2i:
	var c := Vector2i(int(floor(b.x)), int(floor(b.y)))
	for r in 4:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if ag.is_in_boundsv(q) and not ag.is_point_solid(q):
					return q
	return Vector2i(-1, -1)
