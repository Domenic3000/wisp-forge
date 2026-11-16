extends RefCounted
## Procedural structures: cottages, towns, towers, castles, desert temples, stilt huts,
## mineshafts, catacombs and sealed vaults. Nothing is hand-drawn: each structure is grown
## from simple rules (floors, walls, doors, roofs) in materials that suit its biome, and
## built within each material's strength (SPAN) so it stands up on its own.
## Ruins are made by damaging an intact building (jagged walls, holes, rotten wood, moss),
## then letting the planet's physics settle it at generation: whatever lost its support
## falls and breaks into rubble, so every ruin collapses differently.
##
## Coordinates: shell-0 columns (x, wraps at N0) and rows (y, 0 = edge of space, grows inward).
## A blueprint is a w x h grid; local (i, j) is column x0 + i, row y0 + j.

const N0 := 8192
const KEEP := 0xffff              # keep foreground and background as generated
const F_FILL := 0x10000           # only fill where there is no solid ground
const F_ANCHOR := 0x20000         # part of the planet (foundations)
const F_WALL := 0x40000           # background is a built back wall
const STOREY := 40                # floor to floor; the mage is 24 tall with the hat, so rooms feel roomy
const DOOR := 30                  # doorway height
const GAP := 14                   # the hole in each upper floor that you levitate through

var surf: PackedFloat32Array
var rng := RandomNumberGenerator.new()
var structs := []                 # {x0, y0, w, h, data} ready for the GPU stamp pass
var sites := []                   # Vector2(x0, x1): surface columns kept free of trees
var settle := []                  # [world position, half size] windows to settle after stamping
var labels := []                  # {x0, x1, ymin, ymax, name}: for the region name on the HUD
var guards := []                  # {pos, type}: foes that wait inside castles, catacombs, temples and mines
var infos := []                   # what was built (for the test mode): {x0, y0, w, h, ruined, solid, chests}
var used := []                    # occupied surface column ranges
var deep := []                    # column ranges taken by underground tunnels (mines, catacombs, vaults)
var spawn_col := 0
var boss_col := 0
var biome_names := []
var _quiet := false               # the first structure near your arrival has no guards

class BP:
	var chests := []          # Vector2i(left column, floor row), local
	var ruined := false
	var x0 := 0
	var y0 := 0
	var w := 0
	var h := 0
	var c := PackedInt32Array()
	func _init(x: int, y: int, ww: int, hh: int) -> void:
		x0 = x
		y0 = y
		w = ww
		h = hh
		c.resize(w * h)
		c.fill(0xffff)
	func ok(i: int, j: int) -> bool:
		return i >= 0 and j >= 0 and i < w and j < h
	func fg(i: int, j: int, m: int, flags := 0) -> void:
		if ok(i, j):
			var k := j * w + i
			c[k] = (c[k] & 0xff00) | (m & 255) | flags | (c[k] & 0x40000)
	func bg(i: int, j: int, m: int, wall := true) -> void:
		if ok(i, j):
			var k := j * w + i
			c[k] = (c[k] & 0xff300ff) | ((m & 255) << 8) | (0x40000 if wall and m != 0 else 0)
	## a background object with a fixed part number, in front of open air (chests)
	func bgv(i: int, j: int, m: int, v: int) -> void:
		if ok(i, j):
			c[j * w + i] = ((m & 255) << 8) | ((v & 255) << 19) | 0x8000000
	## foreground with a fixed colour variant
	func fgv(i: int, j: int, m: int, v: int) -> void:
		if ok(i, j):
			var k := j * w + i
			c[k] = (c[k] & 0x4ff00) | (m & 255) | ((v & 255) << 19) | 0x8000000
	func getf(i: int, j: int) -> int:
		return c[j * w + i] & 255 if ok(i, j) else 255
	func getb(i: int, j: int) -> int:
		return (c[j * w + i] >> 8) & 255 if ok(i, j) else 255
	func is_fill(i: int, j: int) -> bool:
		return ok(i, j) and (c[j * w + i] & 0x10000) != 0
	func rect(i0: int, j0: int, i1: int, j1: int, m: int, flags := 0) -> void:
		for j in range(mini(j0, j1), maxi(j0, j1) + 1):
			for i in range(mini(i0, i1), maxi(i0, i1) + 1):
				fg(i, j, m, flags)
	## solid block with its own back wall (so it is part of the building's structure)
	func solid(i0: int, j0: int, i1: int, j1: int, m: int, flags := 0) -> void:
		rect(i0, j0, i1, j1, m, flags)
		rect_bg(i0, j0, i1, j1, m)
	func rect_bg(i0: int, j0: int, i1: int, j1: int, m: int, wall := true) -> void:
		for j in range(mini(j0, j1), maxi(j0, j1) + 1):
			for i in range(mini(i0, i1), maxi(i0, i1) + 1):
				bg(i, j, m, wall)

# ------------------------------------------------------------------ styles ---
func _style(bname: String, kind: String) -> Dictionary:
	var st := {"wall": Defs.PLANK, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.TILE,
		"roof_kind": "pitch", "found": Defs.MASONRY, "thick": 1}
	match bname:
		"desert":
			st = {"wall": Defs.SANDSTONE, "post": Defs.SANDSTONE, "slab": Defs.SANDSTONE, "back": Defs.SANDSTONE,
				"roof": Defs.SANDSTONE, "roof_kind": "dome" if rng.randf() < 0.5 else "flat", "found": Defs.SANDSTONE, "thick": 2}
		"tundra":
			st = {"wall": Defs.WOOD, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.PLANK,
				"roof_kind": "steep", "found": Defs.MASONRY, "thick": 1}
		"mountain":
			st = {"wall": Defs.MASONRY, "post": Defs.MASONRY, "slab": Defs.PLANK, "back": Defs.MASONRY, "roof": Defs.TILE,
				"roof_kind": "steep", "found": Defs.MASONRY, "thick": 1}
		"marsh":
			st = {"wall": Defs.PLANK, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.LEAF,
				"roof_kind": "pitch", "found": Defs.WOOD, "thick": 1}
		"ashland":
			st = {"wall": Defs.BRICK, "post": Defs.OBSIDIAN, "slab": Defs.BRICK, "back": Defs.BRICK, "roof": Defs.BRICK,
				"roof_kind": "battle", "found": Defs.OBSIDIAN, "thick": 2}
	if kind == "fort":
		# towers, keeps and castle walls are always stone
		var stone := Defs.MASONRY
		if bname == "desert":
			stone = Defs.SANDSTONE
		elif bname == "ashland":
			stone = Defs.BRICK
		st["wall"] = stone
		st["post"] = stone
		st["back"] = stone
		st["found"] = stone
		st["slab"] = Defs.PLANK if rng.randf() < 0.5 and bname != "ashland" else stone
		st["thick"] = 2
		st["roof"] = Defs.TILE if bname != "ashland" else stone
		st["roof_kind"] = "battle" if rng.randf() < 0.55 or bname == "ashland" or bname == "desert" else "steep"
	return st

# ------------------------------------------------------------- terrain info ---
func ground_row(col: int) -> int:
	var x := posmod(col, N0)
	return int(floor(Defs.R_TOP - surf[x * 8] - 0.5)) + 1

func wet(col: int) -> bool:
	var x := posmod(col, N0)
	return surf[x * 8 + 5] > surf[x * 8] + 0.5

func biome(col: int) -> String:
	var x := posmod(col, N0)
	return biome_names[clampi(int(surf[x * 8 + 1]), 0, biome_names.size() - 1)]

func cdist(a: int, b: int) -> int:
	var d := posmod(a - b, N0)
	return mini(d, N0 - d)

func free_span(x0: int, w: int, margin: int) -> bool:
	for u in used:
		var a: int = u.x - margin
		var ln: int = u.y - u.x + 2 * margin
		var d0 := posmod(x0 - a, N0)
		if d0 < ln or posmod(a - x0, N0) < w:
			return false
	return true

func _ground_range(x0: int, w: int) -> Vector2i:
	var gmin := 1 << 30
	var gmax := -1
	for i in w:
		var g := ground_row(x0 + i)
		gmin = mini(gmin, g)
		gmax = maxi(gmax, g)
	return Vector2i(gmin, gmax)

func _median_ground(x0: int, w: int) -> int:
	var a := []
	for i in w:
		a.append(ground_row(x0 + i))
	a.sort()
	return a[a.size() / 2]

func _any_wet(x0: int, w: int) -> bool:
	for i in range(0, w, 2):
		if wet(x0 + i):
			return true
	return false

# ---------------------------------------------------------------- planning ---
## Plans every structure on the planet. Deterministic for a given planet, so it can be
## re-run when a saved world is loaded (for the region names) without stamping again.
func plan(planet: Dictionary, surface: PackedFloat32Array, spawn_angle: float, boss_angle: float, build: bool) -> void:
	surf = surface
	rng.seed = int(planet["seed"]) * 31 + 7
	biome_names = []
	for b in planet["biomes"]:
		biome_names.append(str(b))
	spawn_col = int(fposmod(spawn_angle, TAU) / TAU * N0)
	boss_col = int(fposmod(boss_angle, TAU) / TAU * N0)
	structs.clear()
	sites.clear()
	settle.clear()
	labels.clear()
	guards.clear()
	infos.clear()
	used.clear()
	deep.clear()
	used.append(Vector2i(spawn_col - 70, spawn_col + 70))
	# something to discover a short walk from where you arrive
	for tries in 40:
		var side := 1 if tries % 2 == 0 else -1
		var x := posmod(spawn_col + side * (115 + tries * 9), N0)
		_quiet = true
		var ok := _try_place(x, true, build)
		_quiet = false
		if ok:
			break
	var target := 26
	var placed := 0
	for tries in 900:
		if placed >= target:
			break
		var x := rng.randi_range(0, N0 - 1)
		if _try_place(x, false, build):
			placed += 1
	# underground: sealed vaults, out of sight
	for k in 6:
		_vault(rng.randi_range(0, N0 - 1), build)

func _pick(weights: Dictionary) -> String:
	var tot := 0.0
	for k in weights:
		tot += float(weights[k])
	var r := rng.randf() * tot
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]

func _try_place(x: int, near_spawn: bool, build: bool) -> bool:
	var b := biome(x)
	var w := {}
	match b:
		"forest": w = {"town": 3, "cottage": 3, "tower": 1.5, "mine": 1, "catacomb": 1.5}
		"desert": w = {"temple": 3.5, "cottage": 2, "town": 1.5, "tower": 1, "catacomb": 1.5}
		"marsh": w = {"stilt": 5, "tower": 2, "catacomb": 2}
		"mountain": w = {"castle": 3.5, "tower": 2.5, "mine": 3, "cottage": 1}
		"tundra": w = {"cottage": 3.5, "town": 2.5, "tower": 1.5, "mine": 2.5}
		"ashland": w = {"tower": 3.5, "castle": 2.5, "catacomb": 2, "cottage": 2}
		"ocean": w = {"cottage": 6, "tower": 4}
		_: w = {"cottage": 1}
	if near_spawn:
		w = {"cottage": 2, "tower": 2} if b != "desert" else {"temple": 1}
		if b == "marsh":
			w = {"stilt": 1}
	var kind := _pick(w)
	var ruin_p := 0.5
	match kind:
		"castle", "temple", "catacomb": ruin_p = 0.7
		"town": ruin_p = 0.3
		"mine": ruin_p = 0.6
	if near_spawn:
		ruin_p = 0.75
	var ruined := rng.randf() < ruin_p
	match kind:
		"cottage": return _cottage(x, b, ruined, build)
		"town": return _town(x, b, ruined, build)
		"tower": return _tower(x, b, ruined, build)
		"castle": return _castle(x, b, ruined, build)
		"temple": return _temple(x, ruined, build)
		"stilt": return _stilt(x, ruined, build)
		"mine": return _mine(x, b, ruined, build)
		"catacomb": return _catacomb(x, b, ruined, build)
	return false

## checks a surface footprint: dry, not too steep, not taken
func _site_ok(x0: int, w: int, max_slope: int, allow_wet := false) -> bool:
	if not free_span(x0, w, 6):
		return false
	if not allow_wet and _any_wet(x0 - 2, w + 4):
		return false
	var g := _ground_range(x0, w)
	return g.y - g.x <= max_slope

## underground tunnels must not run into each other (their surface footprints are much smaller)
func _deep_free(x0: int, w: int) -> bool:
	for u in deep:
		var a: int = u.x - 8
		var ln: int = u.y - u.x + 16
		if posmod(x0 - a, N0) < ln or posmod(a - x0, N0) < w:
			return false
	return true

func _claim(x0: int, w: int, name: String, ymin: int, ymax: int) -> void:
	used.append(Vector2i(x0, x0 + w))
	sites.append(Vector2(posmod(x0, N0), posmod(x0, N0) + w))
	labels.append({"x0": posmod(x0, N0), "w": w, "ymin": ymin, "ymax": ymax, "name": name})

## Is cell (i, j) part of the built structure (a solid in front, or a back wall)?
func _built(bp: BP, i: int, j: int) -> bool:
	if not bp.ok(i, j):
		return false
	var v: int = bp.c[j * bp.w + i]
	var f := v & 255
	var g := (v >> 8) & 255
	return (f != 255 and f != 0 and Defs.KIND[f] == Defs.K_SOLID) or (g != 255 and g != 0 and (v & F_WALL) != 0)

## Is cell (i, j) untouched natural ground (outside the blueprint or left as it is, below the surface)?
func _natural(bp: BP, i: int, j: int) -> bool:
	if bp.ok(i, j) and (bp.c[j * bp.w + i] & 255) != 255:
		return false
	return j >= ground_row(bp.x0 + i) - bp.y0

## Generated structures don't move until you come and dig: every piece that is still joined to
## the ground (through other pieces, front or back) is anchored as built, and any piece the
## ruin generator left floating is removed, so nothing falls into rubble before you arrive.
func _anchor_and_tidy(bp: BP) -> void:
	var w := bp.w
	var seen := PackedByteArray()
	seen.resize(w * bp.h)
	var stack := PackedInt32Array()
	for j in bp.h:
		for i in w:
			if not _built(bp, i, j):
				continue
			var v: int = bp.c[j * w + i]
			var root := (v & (F_FILL | F_ANCHOR)) != 0
			if not root:
				for dv in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
					if _natural(bp, i + dv.x, j + dv.y):
						root = true
						break
			if root:
				seen[j * w + i] = 1
				stack.append(j * w + i)
	while not stack.is_empty():
		var k: int = stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var i := k % w
		var j := k / w
		for dv in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var ni: int = i + dv.x
			var nj: int = j + dv.y
			if bp.ok(ni, nj) and seen[nj * w + ni] == 0 and _built(bp, ni, nj):
				seen[nj * w + ni] = 1
				stack.append(nj * w + ni)
	for k in w * bp.h:
		var v: int = bp.c[k]
		var f := v & 255
		var g := (v >> 8) & 255
		var is_built := (f != 255 and f != 0 and Defs.KIND[f] == Defs.K_SOLID) or (g != 255 and g != 0 and (v & F_WALL) != 0)
		if not is_built:
			continue
		if seen[k] == 0:
			# a floating fragment: gone (front and back)
			if f != 255 and f != 0:
				v = (v & ~255) | 0     # (a chest left floating in a ruin goes too)
			if g != 255 and g != 0 and (v & F_WALL) != 0:
				v = v & ~0xff00 & ~F_WALL
			bp.c[k] = v
		else:
			bp.c[k] = v | F_ANCHOR
	# forget chests that were removed with a floating fragment
	var keep := []
	for q in bp.chests:
		if bp.getf(q.x, q.y - 1) == Defs.TREASURE:
			keep.append(q)
	bp.chests = keep

func _finish(bp: BP, build: bool) -> void:
	if not build:
		return
	# what the tests check later: the built cells (not fills and foundations), before anchoring
	var cells := PackedInt32Array()
	for k in bp.c.size():
		var v0: int = bp.c[k]
		var f0: int = v0 & 255
		if f0 != 255 and f0 != 0 and Defs.KIND[f0] == Defs.K_SOLID and (v0 & (F_FILL | F_ANCHOR)) == 0:
			cells.append(k)
	_anchor_and_tidy(bp)
	var kept := PackedInt32Array()
	for k in cells:
		if (bp.c[k] & 255) != 0:
			kept.append(k)
	structs.append({"x0": posmod(bp.x0, N0), "y0": bp.y0, "w": bp.w, "h": bp.h, "data": bp.c})
	var solid := kept.size()
	var ch := []
	for q in bp.chests:
		ch.append(Vector2i(posmod(bp.x0 + q.x, N0), bp.y0 + q.y))
	infos.append({"x0": posmod(bp.x0, N0), "y0": bp.y0, "w": bp.w, "h": bp.h, "ruined": bp.ruined, "solid": solid, "chests": ch, "cells": kept})
	var ci := bp.x0 + bp.w / 2
	var cj := bp.y0 + bp.h / 2
	var a := (float(posmod(ci, N0)) + 0.5) / N0 * TAU
	var r := Defs.R_TOP - (cj + 0.5)
	settle.append([Vector2(cos(a), sin(a)) * r, maxf(bp.w, bp.h) * 0.5 + 26.0])

# ------------------------------------------------------- chests and guards ---
## an 8 x 6 treasure chest standing on the floor row fl, left column i. A chest is a real object
## (it falls if you dig out its floor), but you walk through it; open it with F or by digging at it.
func _chest(bp: BP, i: int, fl: int) -> void:
	bp.chests.append(Vector2i(i, fl))
	for cj in Defs.CHEST_H:
		for ci in Defs.CHEST_W:
			bp.fgv(i + ci, fl - Defs.CHEST_H + cj, Defs.TREASURE, ci | (cj << 3))

## a foe waiting on the floor row fl at column i (local), spawned when you come near
func _guard(bp: BP, i: int, fl: int, type: String) -> void:
	if _quiet:
		return
	var d: Dictionary = Defs.ENEMY[type]
	var col := posmod(bp.x0 + i, N0)
	var a := (float(col) + 0.5) / N0 * TAU
	var r := Defs.R_TOP - float(bp.y0 + fl) + float(d["h"]) * 0.5 + 1.0
	if type == "bat":
		r += 6.0
	guards.append({"pos": Vector2(cos(a), sin(a)) * r, "type": type})

# -------------------------------------------------------- building pieces ---
## A building's shell: walls, floors (with a gap to float up through), doors, back wall
## with windows, torches, maybe a treasure chest. ox = left column (local), base = local row
## of the ground floor, w = width, floors = storeys. Returns the local row of the top slab.
func _building(bp: BP, ox: int, base: int, w: int, floors: int, st: Dictionary, doors := 3, ruined := false, guard := "", chest_p := 0.3, max_guards := 99) -> int:
	var top := base - floors * STOREY
	var th: int = st["thick"]
	# interior: clear and put up the back wall
	bp.rect(ox, top, ox + w - 1, base - 1, 0)
	bp.rect_bg(ox, top, ox + w - 1, base, st["back"])
	# outer walls
	for t in th:
		bp.rect(ox + t, top, ox + t, base, st["wall"])
		bp.rect(ox + w - 1 - t, top, ox + w - 1 - t, base, st["wall"])
	if st["post"] != st["wall"]:
		bp.rect(ox, top, ox, base, st["post"])
		bp.rect(ox + w - 1, top, ox + w - 1, base, st["post"])
	# floors, each with a gap at alternating ends to levitate through
	for k in floors + 1:
		var j := base - k * STOREY
		bp.rect(ox, j, ox + w - 1, j, st["slab"])
		if th > 1 and k > 0 and k < floors:
			bp.rect(ox + th, j + 1, ox + w - 1 - th, j + 1, st["slab"])
		if k > 0 and k < floors:
			var left := k % 2 == 1
			var g0 := ox + th + 1 if left else ox + w - th - 1 - GAP
			bp.rect(g0, j, g0 + GAP - 1, j + (1 if th > 1 else 0), 0)
	# doorways: open to walk through, with a dark wooden door frame behind
	if doors & 1:
		bp.rect(ox, base - DOOR, ox + th - 1, base - 1, 0)
		bp.rect_bg(ox, base - DOOR, ox + th - 1, base - 1, Defs.WOOD)
	if doors & 2:
		bp.rect(ox + w - th, base - DOOR, ox + w - 1, base - 1, 0)
		bp.rect_bg(ox + w - th, base - DOOR, ox + w - 1, base - 1, Defs.WOOD)
	# windows in the back wall, torches, treasure and whoever guards it
	for k in floors:
		var fl := base - k * STOREY
		var i := ox + th + 3
		while i + 7 < ox + w - th - 2:
			if rng.randf() < 0.55:
				bp.rect_bg(i - 1, fl - 31, i + 7, fl - 16, st["post"])
				bp.rect_bg(i, fl - 30, i + 6, fl - 17, 0)
				bp.rect_bg(i + 3, fl - 30, i + 3, fl - 17, st["post"])
				bp.rect_bg(i, fl - 24, i + 6, fl - 24, st["post"])
			i += 18
		if not ruined and rng.randf() < 0.85:
			var ti := rng.randi_range(ox + th + 2, ox + w - th - 3)
			bp.bg(ti, fl - 24, Defs.TORCH)
			bp.bg(ti, fl - 23, Defs.WOOD)
		# a chest must stand on solid floor: keep it off the gap you float up through
		var spots := []
		for ci in range(ox + th + 2, ox + w - th - 1 - Defs.CHEST_W):
			if k == 0 or not _over_gap(ci, ci + Defs.CHEST_W - 1, ox, w, th, k):
				spots.append(ci)
		if not spots.is_empty() and rng.randf() < chest_p:
			_chest(bp, spots[rng.randi_range(0, spots.size() - 1)], fl)
		# guards keep to the upper floors first
		if guard != "" and max_guards > 0 and k >= floors - max_guards and rng.randf() < 0.75:
			_guard(bp, ox + w / 2 + rng.randi_range(-w / 4, w / 4), fl, guard)
	return top

## does columns [i0, i1] overlap the gap left in floor k (floors above the ground floor have one)?
func _over_gap(i0: int, i1: int, ox: int, w: int, th: int, k: int) -> bool:
	var g0 := ox + th + 1 if k % 2 == 1 else ox + w - th - 1 - GAP
	return i1 >= g0 - 1 and i0 <= g0 + GAP

func _roof(bp: BP, ox: int, top: int, w: int, st: Dictionary) -> int:
	var kind: String = st["roof_kind"]
	var m: int = st["roof"]
	var hi := top
	match kind:
		"pitch", "steep":
			var t := 0
			var over := 2 if kind == "pitch" else 1
			while true:
				var step := t if kind == "pitch" else t / 2
				var L := ox - over + step
				var R := ox + w - 1 + over - step
				var j := top - 1 - t
				bp.rect_bg(L, j, R, j, st["back"])
				if R - L < 3:
					bp.rect(L, j, R, j, m)
					hi = j
					break
				bp.fg(L, j, m)
				bp.fg(L + 1, j, m)
				bp.fg(R, j, m)
				bp.fg(R - 1, j, m)
				if R - L > 3:
					bp.rect(L + 2, j, R - 2, j, 0)
					bp.rect_bg(L + 2, j, R - 2, j, st["back"])
				hi = j
				t += 1
		"flat":
			bp.rect(ox, top - 2, ox + 1, top - 1, m)
			bp.rect(ox + w - 2, top - 2, ox + w - 1, top - 1, m)
			hi = top - 2
		"battle":
			var i := ox
			while i < ox + w:
				if ((i - ox) / 2) % 2 == 0 or i >= ox + w - 2:
					bp.rect(i, top - 3, mini(i + 1, ox + w - 1), top - 1, m)
				i += 2
			bp.rect(ox, top - 1, ox + w - 1, top - 1, m)
			hi = top - 3
		"dome":
			var rad := w * 0.5
			var cx := ox + (w - 1) * 0.5
			for j in range(top - int(rad) - 1, top):
				for i in range(ox, ox + w):
					var d := Vector2(i - cx, (j - top) * 1.15).length()
					if d < rad and d >= rad - 2.0:
						bp.fg(i, j, m)
						bp.bg(i, j, st["back"])
					elif d < rad - 2.0:
						bp.fg(i, j, 0)
						bp.bg(i, j, st["back"])
			hi = top - int(rad) - 1
	return hi

## foundation from the floor down into the ground, so the building never hangs over a dip
func _foundation(bp: BP, ox: int, base: int, w: int, m: int) -> void:
	for i in range(ox, ox + w):
		var g := ground_row(bp.x0 + i) - bp.y0
		for j in range(base + 1, maxi(base + 2, g + 3)):
			bp.fg(i, j, m, F_FILL | F_ANCHOR)

## dig out the hillside in front of doors so you can walk in
func _yard(bp: BP, i0: int, i1: int, base: int) -> void:
	bp.rect(i0, base - DOOR - 5, i1, base - 1, 0)
	for i in range(i0, i1 + 1):
		var g := ground_row(bp.x0 + i) - bp.y0
		for j in range(base, maxi(base + 1, g + 2)):
			bp.fg(i, j, Defs.DIRT, F_FILL | F_ANCHOR)

# ------------------------------------------------------------------ ruins ---
## Damage an intact structure inside [i0, i1] x [j0, j1]: jagged broken tops, holes, rotten
## wood, moss, back walls with gaps. The physics finishes the job when the planet settles.
func _ruin(bp: BP, i0: int, i1: int, j0: int, j1: int, b: String, outdoors := true) -> void:
	# Damage comes in chunks, never single cells: a jagged broken top, a few big holes with
	# rough edges, whole sections of rotten wood and missing back wall, patches of moss. (Single
	# missing cells looked like pinholes and left lots of tiny loose bits to drop off.)
	var hgt := j1 - j0
	var cut := rng.randi_range(int(hgt * 0.15), maxi(int(hgt * 0.15), int(hgt * 0.55)))
	var wob := 0.0
	var col := i0
	while col <= i1:
		# the broken top steps in runs of 2-4 columns, so it reads as broken masonry, not noise
		wob = clampf(wob + rng.randf_range(-3.0, 3.0), -8.0, 8.0)
		var run := rng.randi_range(2, 4)
		for k in run:
			if col + k > i1:
				break
			var c := int(cut + wob)
			for j in range(j0, mini(j1, j0 + c)):
				_break(bp, col + k, j)
		col += run
	for n in rng.randi_range(2, 5):
		var ci := rng.randi_range(i0, i1)
		var cj := rng.randi_range(mini(j0 + cut, j1 - 2), maxi(j0 + cut, j1 - 2))
		var rr := rng.randf_range(3.0, 8.0)
		var ph := rng.randf() * TAU
		for j in range(cj - int(rr) - 2, cj + int(rr) + 3):
			for ii in range(ci - int(rr) - 2, ci + int(rr) + 3):
				var dv := Vector2(ii - ci, j - cj)
				var edge := rr + sin(dv.angle() * 3.0 + ph) * 1.4
				if dv.length() < edge:
					_break(bp, ii, j)
	# chunky decay: decided per block of cells
	var seed_r := rng.randi()
	for j in range(j0, j1 + 1):
		for ii in range(i0, i1 + 1):
			if not bp.ok(ii, j) or bp.is_fill(ii, j):
				continue
			var f := bp.getf(ii, j)
			if (f == Defs.PLANK or f == Defs.WOOD or f == Defs.LEAF) and _blockr(seed_r, ii / 3, j / 3, 1) < 0.2:
				bp.fg(ii, j, 0)
			elif f == Defs.MASONRY and _blockr(seed_r, (ii + 2) / 5, j / 4, 2) < 0.55:
				bp.fg(ii, j, Defs.MOSSBLOCK)
			var g := bp.getb(ii, j)
			if g == Defs.TORCH:
				bp.bg(ii, j, 0)
			elif g != 255 and g != 0 and _blockr(seed_r, ii / 6, j / 5, 3) < 0.22:
				bp.bg(ii, j, 0)
	# the wilds move in
	if not outdoors:
		return
	if b == "desert":
		var bury := rng.randi_range(3, 12)
		for i in range(i0 - 4, i1 + 5):
			var g := ground_row(bp.x0 + i) - bp.y0
			# a drift that slopes off at the ends (no sand wall to pour down)
			var hb := mini(bury, mini(i - (i0 - 4), (i1 + 4) - i) + 1)
			for j in range(g - hb, g):
				if bp.ok(i, j) and bp.getf(i, j) == 0:
					bp.fg(i, j, Defs.SAND)
				elif bp.ok(i, j) and bp.getf(i, j) == 255:
					bp.fg(i, j, Defs.SAND, F_FILL)
	elif b == "forest" or b == "marsh" or b == "ocean":
		for n in rng.randi_range(2, 5):
			var vi := rng.randi_range(i0, i1)
			var vj := rng.randi_range(j0 + cut, j1)
			for k in rng.randi_range(4, 12):
				if bp.ok(vi, vj) and bp.getb(vi, vj) != 255:
					bp.bg(vi, vj, Defs.LEAF, false)
				vj += 1
				vi += rng.randi_range(-1, 1)

func _break(bp: BP, i: int, j: int) -> void:
	if not bp.ok(i, j) or bp.is_fill(i, j):
		return
	var f := bp.getf(i, j)
	if f != 255 and f != 0 and f != Defs.TREASURE:
		bp.fg(i, j, 0)
	var g := bp.getb(i, j)
	if g != 255 and g != 0:
		bp.bg(i, j, 0)

## a repeatable random number for a block of cells (the same for every cell in the block)
func _blockr(seed_r: int, bi: int, bj: int, k: int) -> float:
	var h := hash(Vector3i(bi, bj, seed_r + k * 7919))
	return float(posmod(h, 10007)) / 10007.0

# ------------------------------------------------------------- structures ---
const YARD := 8

func _cottage(x: int, b: String, ruined: bool, build: bool, label := true, w_in := 0) -> bool:
	var w := w_in if w_in > 0 else rng.randi_range(46, 62)
	var floors := 1 if rng.randf() < 0.55 else 2
	var tw := w + 2 * YARD + 4
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, w + 4, 18):
		return false
	var st := _style(b, "home")
	var base := _median_ground(x0 + YARD, w + 4) - 1
	var up := floors * STOREY + w / 2 + 10
	var bp := BP.new(x0, base - up, tw, up + 40)
	bp.ruined = ruined
	var lb := up
	var ox := YARD + 2
	_yard(bp, 0, tw - 1, lb)
	_foundation(bp, ox - 1, lb, w + 2, st["found"])
	var top := _building(bp, ox, lb, w, floors, st, 3, ruined, "", 0.3)
	var hi := _roof(bp, ox, top, w, st)
	if ruined:
		_ruin(bp, ox - 2, ox + w + 1, hi, lb - 1, b)
	if label:
		_claim(x0, tw, ("Ruined " if ruined else "Abandoned ") + ("Cottage" if b != "desert" else "Dwelling"), bp.y0, base + 2)
	else:
		used.append(Vector2i(x0, x0 + tw))
		sites.append(Vector2(posmod(x0, N0), posmod(x0, N0) + tw))
	_finish(bp, build)
	return true

## a row of houses with real gaps between them
func _town(x: int, b: String, ruined: bool, build: bool) -> bool:
	var n := rng.randi_range(3, 5)
	var widths := []
	var span := 0
	for k in n:
		var w := rng.randi_range(44, 58)
		widths.append(w)
		span += w + 2 * YARD + 4 + rng.randi_range(10, 24)
	if not _site_ok(x - span / 2, span, 50):
		return false
	var cx := x - span / 2
	var made := 0
	for k in n:
		var w: int = widths[k]
		var tw := w + 2 * YARD + 4
		if _cottage(cx + tw / 2, b, ruined and rng.randf() < 0.8, build, false, w):
			made += 1
		cx += tw + rng.randi_range(10, 24)
	if made == 0:
		return false
	labels.append({"x0": posmod(x - span / 2, N0), "w": span, "ymin": ground_row(x) - 170, "ymax": ground_row(x) + 4,
		"name": ("Ruins of a Village" if ruined else "Deserted Village")})
	return true

func _tower(x: int, b: String, ruined: bool, build: bool) -> bool:
	var w := rng.randi_range(32, 38)
	var floors := rng.randi_range(3, 4)
	var tw := w + 2 * YARD + 4
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, w + 4, 20):
		return false
	var st := _style(b, "fort")
	var base := _median_ground(x0 + YARD, w + 4) - 1
	var up := floors * STOREY + w + 12
	var bp := BP.new(x0, base - up, tw, up + 40)
	bp.ruined = ruined
	var ox := YARD + 2
	_yard(bp, 0, tw - 1, up)
	_foundation(bp, ox - 1, up, w + 2, st["found"])
	var top := _building(bp, ox, up, w, floors, st, 3, ruined, "skeleton" if rng.randf() < 0.6 else "", 0.3, 1)
	var hi := _roof(bp, ox, top, w, st)
	if ruined:
		_ruin(bp, ox - 1, ox + w, hi, up - 1, b)
	_claim(x0, tw, "Ruined Watchtower" if ruined else "Old Watchtower", bp.y0, base + 2)
	_finish(bp, build)
	return true

## Two corner towers, outer walls with gates, courtyards, and a great keep in the middle
## holding the lord's hoard and its guards.
func _castle(x: int, b: String, ruined: bool, build: bool) -> bool:
	var tw_w := 32
	var curt := 14
	var court := rng.randi_range(28, 40)
	var keep_w := rng.randi_range(76, 96)
	var inner := tw_w + curt + court + keep_w + court + curt + tw_w
	var tw := inner + 2 * YARD
	var x0 := x - tw / 2
	if not _site_ok(x0, tw, 80):
		return false
	var st := _style(b, "fort")
	st["roof_kind"] = "battle"
	var g := _ground_range(x0 + YARD, inner)
	var base := g.x + (g.y - g.x) / 3 - 1   # sits high: tall foundations on the low side
	var up := 4 * STOREY + 16
	var bp := BP.new(x0, base - up, tw, up + 70)
	bp.ruined = ruined
	var lb := up
	_yard(bp, 0, tw - 1, lb)
	var ox := YARD
	_foundation(bp, ox, lb, inner, st["found"])
	bp.solid(ox, lb, ox + inner - 1, lb, st["wall"])     # paved ground through the whole castle
	var hi := lb
	var t1 := _building(bp, ox, lb, tw_w, 4, st, 3, ruined, "skeleton", 0.2, 1)
	hi = mini(hi, _roof(bp, ox, t1, tw_w, st))
	var cx := ox + tw_w
	_curtain(bp, cx, lb, curt, 2 * STOREY + 4, st)
	_guard(bp, cx + curt + court / 2, lb, "skeleton")
	var kx := cx + curt + court
	var kt := _building(bp, kx, lb, keep_w, 3, st, 3, ruined, "skeleton", 0.35, 1)
	hi = mini(hi, _roof(bp, kx, kt, keep_w, st))
	# the lord's hoard on the top floor, well guarded
	var hf := lb - 2 * STOREY
	_chest(bp, kx + keep_w / 2 - 13, hf)
	_chest(bp, kx + keep_w / 2 + 5, hf)
	_guard(bp, kx + keep_w / 2 - 24, hf, "skeleton")
	_guard(bp, kx + keep_w / 2 + 24, hf, "skeleton")
	var c2 := kx + keep_w + court
	_guard(bp, kx + keep_w + court / 2, lb, "skeleton")
	_curtain(bp, c2, lb, curt, 2 * STOREY + 4, st)
	var t2 := _building(bp, c2 + curt, lb, tw_w, 4, st, 3, ruined, "skeleton", 0.2, 1)
	hi = mini(hi, _roof(bp, c2 + curt, t2, tw_w, st))
	if ruined:
		_ruin(bp, ox, ox + inner - 1, hi, lb - 1, b)
	_claim(x0, tw, "Ruined Castle" if ruined else "Silent Castle", bp.y0, base + 2)
	_finish(bp, build)
	return true

## a castle wall: solid stone with a gate passage through it and battlements on top
func _curtain(bp: BP, ox: int, base: int, w: int, hgt: int, st: Dictionary) -> void:
	var top := base - hgt
	bp.solid(ox, top, ox + w - 1, base, st["wall"])
	bp.rect(ox, base - DOOR, ox + w - 1, base - 1, 0)
	bp.rect_bg(ox, base - DOOR, ox + w - 1, base - 1, Defs.WOOD)
	var i := ox
	while i < ox + w:
		if ((i - ox) / 2) % 2 == 0:
			bp.rect(i, top - 3, mini(i + 1, ox + w - 1), top - 1, st["wall"])
		i += 2

func _temple(x: int, ruined: bool, build: bool) -> bool:
	var half := rng.randi_range(46, 58)
	var W := half * 2 + 1
	var tw := W + 2 * YARD
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, W, 26):
		return false
	var m := Defs.SANDSTONE
	var base := _median_ground(x0 + YARD, W) - 1
	var steps := half / 3
	var up := steps * 3 + 8
	var bp := BP.new(x0, base - up, tw, up + 40)
	bp.ruined = ruined
	var lb := up
	var ox := YARD
	_foundation(bp, ox, lb, W, m)
	for s in steps:
		bp.solid(ox + s * 3, lb - s * 3 - 2, ox + W - 1 - s * 3, lb - s * 3, m)
	bp.solid(ox, lb, ox + W - 1, lb, m)
	# entrance passage and the inner sanctum
	var cx := ox + half
	bp.rect(ox, lb - DOOR, cx - 22, lb - 1, 0)
	bp.rect_bg(ox + 3, lb - DOOR, cx - 22, lb - 1, m)
	bp.rect(cx - 22, lb - 36, cx + 22, lb - 1, 0)
	bp.rect_bg(cx - 22, lb - 36, cx + 22, lb - 1, m)
	_chest(bp, cx - 17, lb)
	_chest(bp, cx + 9, lb)
	if rng.randf() < 0.6:
		_chest(bp, cx - 4, lb)
	_guard(bp, cx - 10, lb, "skeleton")
	_guard(bp, cx + 13, lb, "skeleton")
	if not ruined:
		bp.bg(cx - 22, lb - 24, Defs.TORCH)
		bp.bg(cx + 22, lb - 24, Defs.TORCH)
	if ruined:
		_ruin(bp, ox, ox + W - 1, lb - steps * 3, lb - 37, "desert")
	_claim(x0, tw, "Buried Temple" if ruined else "Sun Temple", bp.y0, base + 2)
	_finish(bp, build)
	return true

func _stilt(x: int, ruined: bool, build: bool) -> bool:
	var w := rng.randi_range(32, 42)
	var tw := w + 2 * YARD + 4
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, w + 4, 10, true):
		return false
	var st := _style("marsh", "home")
	var gnd := _ground_range(x0 + YARD, w + 4)
	var lift := rng.randi_range(10, 16)
	var base := gnd.x - 1 - lift
	var up := STOREY + w / 2 + 10
	var bp := BP.new(x0, base - up, tw, up + lift + 40)
	bp.ruined = ruined
	var lb := up
	var ox := YARD + 2
	# stilts every few columns down into the mud
	var i := ox
	while i < ox + w:
		var g := ground_row(bp.x0 + i) - bp.y0
		bp.rect(i, lb + 1, i, g + 4, Defs.WOOD, F_ANCHOR)
		i += 6
	bp.rect(ox + w - 1, lb + 1, ox + w - 1, ground_row(bp.x0 + ox + w - 1) - bp.y0 + 4, Defs.WOOD, F_ANCHOR)
	var top := _building(bp, ox, lb, w, 1, st, 3, ruined, "", 0.35)
	var hi := _roof(bp, ox, top, w, st)
	if ruined:
		_ruin(bp, ox - 2, ox + w + 1, hi, lb, "marsh")
	_claim(x0, tw, "Sunken Hut" if ruined else "Stilt Hut", bp.y0, base + lift + 4)
	_finish(bp, build)
	return true

## Abandoned mine: a headframe at the top, a shaft with plank landings, and drifts propped
## up with timber.
func _mine(x: int, b: String, ruined: bool, build: bool) -> bool:
	var sw := 13
	var depth := rng.randi_range(60, 130)
	var dl := rng.randi_range(40, 80)
	var dr := rng.randi_range(40, 80)
	var tw := sw + dl + dr + 6
	var x0 := x - dl - 3
	if not _site_ok(x - 6, sw + 12, 12) or not _deep_free(x0, tw):
		return false
	deep.append(Vector2i(x0, x0 + tw))
	var g0 := ground_row(x)
	var bp := BP.new(x0, g0 - 26, tw, depth + 56)
	bp.ruined = ruined
	var gl := 26                      # local ground row at the shaft
	var sx := dl + 3                  # shaft left column
	# headframe
	for pc in [sx - 2, sx + sw + 1]:
		bp.rect(pc, gl - 22, pc, gl - 1, Defs.WOOD)
		bp.rect(pc, gl, pc, ground_row(bp.x0 + pc) - bp.y0 + 2, Defs.WOOD, F_FILL | F_ANCHOR)
	bp.rect(sx - 3, gl - 23, sx + sw + 2, gl - 23, Defs.PLANK)
	bp.bg(sx + sw / 2, gl - 22, Defs.TORCH)
	# shaft, lined with planking behind (a load-bearing back wall), which carries the landings
	# where a cave has eaten away the rock beside the shaft
	bp.rect(sx, gl - 1, sx + sw - 1, gl + depth, 0)
	bp.rect_bg(sx, gl + 1, sx + sw - 1, gl + depth - 33, Defs.PLANK)
	var j := gl + 22
	var left := true
	while j < gl + depth - 6:
		if left:
			bp.rect(sx, j, sx + sw - 9, j, Defs.PLANK)
		else:
			bp.rect(sx + 8, j, sx + sw - 1, j, Defs.PLANK)
		left = not left
		j += 22
	# drifts at the bottom
	var fj := gl + depth
	bp.rect(sx - dl, fj - 32, sx + sw + dr - 1, fj - 1, 0)
	var p := sx - dl + 2
	while p < sx + sw + dr - 2:
		if p < sx - 2 or p > sx + sw + 1:
			bp.rect(p, fj - 31, p, fj - 1, Defs.WOOD)
			bp.rect(p - 3, fj - 32, p + 3, fj - 32, Defs.PLANK)
			if not ruined and rng.randf() < 0.5:
				bp.bg(p + 2, fj - 20, Defs.TORCH)
		p += 13
	# what the miners left behind, and what moved in after
	_chest(bp, sx - dl + 3, fj)
	if rng.randf() < 0.6:
		_chest(bp, sx + sw + dr - 3 - Defs.CHEST_W, fj)
	_guard(bp, sx - dl / 2, fj, "bat")
	_guard(bp, sx + sw + dr / 2, fj, "bat")
	if rng.randf() < 0.5:
		_guard(bp, sx - dl / 2 - 8, fj, "skeleton")
	if ruined:
		# cave-ins and rotten timber
		for j2 in range(gl - 23, fj + 1):
			for i2 in tw:
				var f := bp.getf(i2, j2)
				if (f == Defs.PLANK or f == Defs.WOOD) and rng.randf() < 0.3:
					bp.fg(i2, j2, 0)
		for n in rng.randi_range(1, 3):
			var ci := rng.randi_range(2, tw - 3)
			var rr := rng.randf_range(4.0, 8.0)
			for jj in range(fj - 34, fj + 1):
				for ii in range(ci - 9, ci + 10):
					if bp.ok(ii, jj) and bp.getf(ii, jj) == 0 and Vector2(ii - ci, (jj - (fj - 10)) * 1.5).length() < rr:
						bp.fg(ii, jj, Defs.GRAVEL)
	used.append(Vector2i(x - 6, x + sw + 6))
	sites.append(Vector2(posmod(x - 6, N0), posmod(x - 6, N0) + sw + 12))
	labels.append({"x0": posmod(x0, N0), "w": tw, "ymin": g0 - 28, "ymax": g0 + depth + 4,
		"name": "Collapsed Mine" if ruined else "Abandoned Mine"})
	_finish(bp, build)
	return true

## Catacombs: a small shrine on the surface, a lined stairwell down, and stone corridors
## with tombs, burial rooms, treasure, and the dead who keep it.
func _catacomb(x: int, b: String, ruined: bool, build: bool) -> bool:
	var shrine := 30
	if not _site_ok(x - shrine / 2 - YARD, shrine + 2 * YARD, 8):
		return false
	var st := _style(b, "fort")
	st["roof_kind"] = "flat"
	var m: int = st["wall"]
	var depth := rng.randi_range(70, 120)
	var cl := rng.randi_range(60, 110)
	var cr := rng.randi_range(60, 110)
	var tw := cl + cr + shrine + 50
	var x0 := x - shrine / 2 - cl - 25
	if not _deep_free(x0, tw):
		return false
	deep.append(Vector2i(x0, x0 + tw))
	var g0 := _median_ground(x - shrine / 2, shrine) - 1
	var bp := BP.new(x0, g0 - STOREY - 8, tw, STOREY + depth + 34)
	bp.ruined = ruined
	var lb := STOREY + 8
	var sx := cl + 25
	_yard(bp, sx - YARD, sx + shrine + YARD - 1, lb)
	_foundation(bp, sx, lb, shrine, m)
	var top := _building(bp, sx, lb, shrine, 1, st, 3, ruined, "", 0.0)
	_roof(bp, sx, top, shrine, st)
	# stairwell: lined shaft
	var s0 := sx + 3
	var s1 := sx + shrine - 4
	var fj := lb + depth
	bp.solid(s0 - 2, lb, s1 + 2, fj, m)
	bp.rect(s0, lb, s1, fj - 1, 0)
	# corridors left and right, with a burial room at each end
	var c0 := sx - cl
	var c1 := sx + shrine + cr
	bp.solid(c0 - 2, fj - 34, c1 + 2, fj + 2, m)
	for e0 in [c0, c1 - 40]:
		bp.solid(e0 - 2, fj - 42, e0 + 42, fj + 2, m)
		bp.rect(e0, fj - 40, e0 + 40, fj - 1, 0)
	# open the corridor through the room walls and the stairwell down into it
	bp.rect(c0, fj - 32, c1, fj - 1, 0)
	bp.rect(s0, lb, s1, fj - 1, 0)
	for e0 in [c0, c1 - 40]:
		_chest(bp, e0 + 16, fj)
		_guard(bp, e0 + 6, fj, "skeleton")
	# wall niches (tombs), torches and the corridor's watchers
	var p := c0 + 44
	var n := 0
	while p < c1 - 44:
		if p < s0 - 3 or p > s1 + 3:
			bp.rect_bg(p, fj - 20, p + 7, fj - 12, Defs.OBSIDIAN)
			if not ruined and rng.randf() < 0.6:
				bp.bg(p + 10, fj - 22, Defs.TORCH)
			n += 1
			if n % 3 == 0:
				_guard(bp, p + 3, fj, "skeleton")
		p += 18
	_guard(bp, (c0 + s0) / 2, fj, "bat")
	if ruined:
		_ruin(bp, c0 - 2, c1 + 2, fj - 42, fj, b, false)
		_ruin(bp, sx, sx + shrine - 1, top - 2, lb, b)
	_claim(x - shrine / 2 - YARD, shrine + 2 * YARD, "Forgotten Catacombs" if ruined else "Catacombs", g0 - 40, g0 + depth + 6)
	labels.append({"x0": posmod(x0, N0), "w": tw, "ymin": g0 + 8, "ymax": g0 + depth + 6, "name": "Forgotten Catacombs" if ruined else "Catacombs"})
	_finish(bp, build)
	return true

## A sealed vault deep underground, full of treasure, with no way in but digging.
func _vault(x: int, build: bool) -> void:
	if cdist(x, spawn_col) < 200 or cdist(x, boss_col) < 260:
		return
	if not _deep_free(x - 30, 60):
		return
	deep.append(Vector2i(x - 30, x + 30))
	var w := 47
	var h := 34
	var g := ground_row(x)
	var y := g + rng.randi_range(140, 260)
	var bp := BP.new(x - w / 2, y, w, h)
	bp.solid(0, 0, w - 1, h - 1, Defs.OBSIDIAN)
	bp.rect(2, 2, w - 3, h - 3, 0)
	bp.rect_bg(2, 2, w - 3, h - 3, Defs.BRICK)
	for k in 4:
		_chest(bp, 4 + k * 9, h - 2)
	bp.bg(3, h - 22, Defs.TORCH)
	bp.bg(w - 4, h - 22, Defs.TORCH)
	labels.append({"x0": posmod(x - w / 2, N0), "w": w, "ymin": y, "ymax": y + h, "name": "Sealed Vault"})
	_finish(bp, build)

## name of the structure at a world position, or ""
func label_at(pos: Vector2) -> String:
	var a := fposmod(atan2(pos.y, pos.x), TAU)
	var col := int(a / TAU * N0)
	var row := int(Defs.R_TOP - pos.length())
	for l in labels:
		if posmod(col - int(l["x0"]), N0) < int(l["w"]) and row >= int(l["ymin"]) and row <= int(l["ymax"]):
			return l["name"]
	return ""
