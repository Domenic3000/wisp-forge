## The isle in your ship's pocket dimension (user, 24 Nov: "the inside of the ship be like a pocket dimension
## that you can enter ... an instanced area that you can expand and build inside. a beautiful pocket
## dimension"; chose an isle in a nebula): a pixel body (pixel_body.gd) that never moves, so the cabin
## builder's tools (main `_cabin_edit`) build on it as they do in a ship: blocks and back walls into its
## open cells, furniture, the Remove tab.
##
## Its cells: W x H, laid out so body +x is screen right and +y screen down (ang PI, facing 1, at the origin:
## `to_world(b)` = (-b.x, b.y)). The isle's own ground (`natural`) is grown from its `level` (`LEVELS`: half
## widths): grass, soil threaded with roots, a gravel seam, rock in wavy strata, a few crystal geodes, stalactites
## underneath with crystal tips (`ground_at`, `drip_at`); a flagstone path from the arch to the heart, the home
## terrace beside the heart (`_terrace`), trees, bushes, tufts, flowers, stones, vines down the rim and roots under it
## on the back layer (scenery you walk past; `_dress`). `guard` cells (the Isle Heart's obelisk and the arch you leave by)
## are never built over or taken. `expand()` grows the ground to the next level round what's there, never
## over what you built.
##
## Pictures: `img_f`/`img_b` painted a cell at a time (`touch`), whole only on making or growing; natural
## ground darkens with its depth. `lights`: glowing cells gathered into a few points for pocket.gd's halos.
extends "res://scripts/pixel_body.gd"

const W := 640
const H := 380
const SURF := 236                   # the isle's top row at its middle
const LEVELS := [70, 100, 132, 168, 208, 252, 296]
const ARCH_DX := -44                # the arch you leave by, from the middle
const ARCH_W := 16                  # its opening
const ARCH_H := 30
const HEART_DX := 0
const TER_A := 12                   # the home terrace: from the heart, cells to its right (user, 25 Nov: "a home spot")
const TER_B := 54
## the isle's look (25 Nov: strata, a path, a terrace, a carved arch and heart, vines, roots, flowers); an isle saved
## with less is dressed again on load (`_restyle`)
const ART := 1
const BUILD_UP := 200               # how far over the ground you can build

var level := 0
var natural := PackedByteArray()    # 1: the isle's own ground; 2: dug out of it (left open)
var guard := PackedByteArray()      # 1: the heart's obelisk and the arch: never taken or built over
var design_bg := PackedByteArray()  # (the cabin builder's Remove gives a back wall's "as forged" back: none here)
var img_f: Image
var img_b: Image
var tex_f: ImageTexture
var tex_b: ImageTexture
var _changed := {}                  # cell index -> true: to paint again before drawing
var _all := true                    # paint everything again
var lights: Array = []              # [cell middle (Vector2), radius, colour]
var _lights_dirty := true

func make() -> void:
	setup(W, H)
	natural = PackedByteArray()
	natural.resize(W * H)
	guard = PackedByteArray()
	guard.resize(W * H)
	design_bg = PackedByteArray()
	design_bg.resize(W * H)
	ang = PI
	facing = 1
	pos = Vector2.ZERO
	com = Vector2.ZERO
	level = 0
	_grow_ground(0)
	_features()
	_all = true
	_lights_dirty = true

# ------------------------------------------------------------ the ground ---

static func _h(n: float) -> float:
	var v := sin(n * 12.9898) * 43758.5453
	return v - floor(v)

## the ground's top row over column i at a level (its edges round down)
func top_at(i: int, lv: int) -> float:
	var hw := float(LEVELS[clampi(lv, 0, LEVELS.size() - 1)])
	var ax := absf(float(i - W / 2)) / hw
	var t := float(SURF) + 2.6 * sin(float(i) * 0.061 + 1.3) + 1.4 * sin(float(i) * 0.173)
	t += pow(maxf(0.0, ax - 0.74) / 0.3, 2.0) * 16.0
	return t

## the ground's depth under column i (0 past its edge)
func depth_at(i: int, lv: int) -> float:
	var hw := float(LEVELS[clampi(lv, 0, LEVELS.size() - 1)])
	var ax := absf(float(i - W / 2)) / hw
	if ax >= 1.0:
		return 0.0
	var d := (30.0 + hw * 0.36) * pow(1.0 - ax * ax, 0.62)
	d += 5.0 * sin(float(i) * 0.11) + 3.0 * sin(float(i) * 0.37 + 2.0)
	return maxf(d, 3.0)

## stalactites under the isle (user, 25 Nov: the pocket "looks a little thrown together"): [extra length below
## the underside at column i, a crystal tip]: cones every 7 or so columns, some left out
func drip_at(i: int, lv: int) -> Array:
	var hw := float(LEVELS[clampi(lv, 0, LEVELS.size() - 1)])
	var ax := absf(float(i - W / 2)) / hw
	if ax >= 0.92:
		return [0.0, false]
	var best := 0.0
	var tip := false
	var c0 := int(floor(float(i) / 7.0)) * 7
	for c in [c0 - 7, c0, c0 + 7]:
		if _h(float(c) * 0.913 + 5.1) < 0.35:
			continue
		var cc: int = c + int(_h(float(c) * 1.37) * 5.0)
		var wd := 2.5 + _h(float(c) * 2.11) * 3.0
		var ln := (5.0 + _h(float(c) * 3.7) * 18.0) * pow(1.0 - ax, 0.6)
		var d := absf(float(i - cc))
		if d >= wd:
			continue
		var e := ln * pow(1.0 - d / wd, 1.3)
		if e > best:
			best = e
			tip = _h(float(c) * 4.3) > 0.62
	return [best, tip]

## the isle's own matter at a cell for a level, or 0: grass, soil threaded with roots, a gravel seam, then rock in
## wavy strata (darker deeper), a few crystal geodes, stalactites under it with crystal tips
func ground_at(i: int, j: int, lv: int) -> int:
	var dep := depth_at(i, lv)
	if dep <= 0.0:
		return 0
	var top := top_at(i, lv)
	var fj := float(j)
	var bottom := top + dep
	var dr: Array = drip_at(i, lv)
	var drip: float = dr[0]
	if fj < floor(top) or fj > bottom + drip:
		return 0
	if fj > bottom:
		if bool(dr[1]) and fj > bottom + drip - 3.0:
			return Defs.CRYSTAL
		return Defs.DEEPSTONE if _h(float(i) * 0.7 + fj * 0.3) > 0.4 else Defs.STONE
	var d := fj - floorf(top)
	if d < 2.0:
		return Defs.GRASS
	var soil := 7.0 + 2.5 * sin(float(i) * 0.29) + 1.5 * sin(float(i) * 0.07)
	if d < soil:
		var i3 := float(i) / 3.0
		if _h(floorf(i3) * 1.9) > 0.72 and absf((i3 - floorf(i3)) * 3.0 - 1.0 - sin(fj * 0.6) * 0.8) < 0.6:
			return Defs.ROOT
		return Defs.DIRT
	if d < soil + 1.5 + _h(float(i) * 1.3):
		return Defs.GRAVEL
	# a few crystal geodes in the rock
	var gx := floorf(float(i) / 22.0)
	var gy := floorf(fj / 16.0)
	if _h(gx * 7.7 + gy * 3.3) > 0.72:
		var cxg := gx * 22.0 + 5.0 + _h(gx * 1.1 + gy) * 12.0
		var cyg := gy * 16.0 + 4.0 + _h(gx + gy * 2.3) * 8.0
		var r := 1.6 + _h(gx * 5.0 + gy * 9.0) * 1.6
		var dd := Vector2(float(i) - cxg, (fj - cyg) * 1.2).length()
		if dd < r and fj > top + soil + 3.0 and fj < bottom - 2.0:
			return Defs.CRYSTAL
		if dd < r + 1.2 and fj > top + soil + 2.0 and fj < bottom - 1.0:
			return Defs.DEEPSTONE
	# strata: wavy bands of stone and deepstone, more deepstone the deeper
	var sj := fj + 3.0 * sin(float(i) * 0.045 + 0.7) + 1.5 * sin(float(i) * 0.13)
	var band := floorf(sj / 6.0)
	var fr := (fj - top) / maxf(dep, 1.0)
	if _h(band * 3.17) < 0.25 + fr * 0.55:
		return Defs.DEEPSTONE
	if fj > bottom - 2.0:
		return Defs.GRAVEL
	return Defs.STONE

func _grow_ground(lv: int) -> void:
	var hw: int = LEVELS[lv]
	for i in range(maxi(0, W / 2 - hw - 2), mini(W, W / 2 + hw + 3)):
		for j in range(maxi(0, SURF - 30), H):
			var k := j * W + i
			if guard[k] == 1 or natural[k] == 2 or (cells[k] != 0 and natural[k] == 0):
				continue                    # (never over what you built, the heart or the arch)
			var m := ground_at(i, j, lv)
			if m == 0 or m == cells[k]:
				continue                    # (the isle's own ground is laid again as it is at this level: old grass
											#  edges buried by the growth turn to earth)
			cells[k] = m
			vars[k] = int(_h(float(k) * 0.37) * 4.0) & 3
			natural[k] = 1
			made[k] = 0

# ----------------------------------------------------------- what's on it ---

## the path from the arch, the home terrace, the Isle Heart (grow the isle there), the arch (leave by it), two
## trees, bushes, and the isle dressed (tufts, flowers, stones, vines, roots)
func _features() -> void:
	var cx := W / 2
	_path(cx)
	_terrace(cx)
	_heart(cx + HEART_DX)
	_arch(cx + ARCH_DX)
	_tree(cx + 63, 24, 12, 1.0)
	_tree(cx - 63, 17, 9, 2.0)
	for bx in [cx - 56, cx + 8 + TER_B]:
		_bush(bx)
	_dress(0)

## (a cell of the isle's own make that isn't its natural ground: the path, the terrace, the plinth; never over what
## you built)
func _iput(i: int, j: int, m: int, v: int, guarded := false) -> void:
	if i < 0 or j < 0 or i >= W or j >= H:
		return
	var k := j * W + i
	if made[k] == 1:
		return
	cells[k] = m
	vars[k] = v & 3
	natural[k] = 0
	if guarded:
		guard[k] = 1

## a flagstone path from the arch to the heart: the grass's top worn to stones, gravel in the joints
func _path(cx: int) -> void:
	var a := cx + ARCH_DX + ARCH_W / 2 + 5
	var b := cx + HEART_DX - 9
	for i in range(a - 3, b + 3):
		var t := _ground_row(i, int(floor(top_at(i, 0))))
		var fade := 1.0 if i >= a and i < b else 0.45
		for dj in 2:
			var k := (t + dj) * W + i
			if natural[k] != 1:
				continue
			var st := int(_h(floorf(float(i + dj * 2) / 4.0) * 3.1 + float(dj)) * 3.0)
			if _h(float(i) * 1.7 + float(dj) * 5.0) > fade:
				continue
			if (i + dj * 2) % 4 == 0:
				_iput(i, t + dj, Defs.GRAVEL, 3)
			else:
				_iput(i, t + dj, Defs.MASONRY, [2, 0, 1][st] if dj == 0 else 1)
		if i >= a and i < b and _h(float(i) * 3.3) > 0.7:
			_iput(i, t + 2, Defs.GRAVEL, 0)

## the home terrace (user, 25 Nov: "the pocket dimension be the safe haven for crafting a home and workstations"):
## level paving beside the heart to build on, a wisp lantern at each end
func _terrace(cx: int) -> void:
	var fl := _terrace_floor(cx)
	var a := cx + TER_A
	var b := cx + TER_B
	for i in range(a - 1, b + 1):
		var g0 := _ground_row(i, int(floor(top_at(i, 0))))
		for j in range(fl - 12, fl):              # (the ground over the floor: cut away)
			var k := j * W + i
			if natural[k] == 1:
				cells[k] = 0
				natural[k] = 2
		for j2 in range(fl, maxi(g0, fl) + 4):    # (under it: filled down to the ground)
			var k2 := j2 * W + i
			if cells[k2] == 0 or natural[k2] == 1:
				var edge := i == a - 1 or i == b
				if j2 < fl + 2:
					var pv := 3 if (edge or (i - a) % 6 == 5 or j2 == fl + 1) else (2 if j2 == fl else (i / 6) % 2)
					_iput(i, j2, Defs.MASONRY, pv)
				elif cells[k2] == 0:
					_iput(i, j2, Defs.DIRT if j2 < fl + 5 else Defs.STONE, (i + j2) & 3)
	for lx in [a + 1, b - 2]:
		for dj in range(1, 9):
			_bg_put(lx, fl - dj, Defs.WOOD, 1)
		for di in [-1, 0, 1]:
			for dj2 in [9, 10, 11]:
				_bg_put(lx + di, fl - dj2, Defs.WISPBAR if di == 0 and dj2 == 10 else Defs.WOOD, 3 if di == 0 else 0)
		_bg_put(lx, fl - 12, Defs.WOOD, 1)

func _terrace_floor(cx: int) -> int:
	var lo := 1 << 20
	var sum := 0
	for i in range(cx + TER_A, cx + TER_B):
		var g := _ground_row(i, int(floor(top_at(i, 0))))
		lo = mini(lo, g)
		sum += g
	return maxi(lo, int(round(float(sum) / float(TER_B - TER_A))))

## the Isle Heart: a tiered plinth you walk up (dressed stone, warded trim, rune lights), a faceted crystal obelisk
## with a wisp seam, a shard floating over its tip, crystal clusters at its foot
func _heart(hx: int) -> void:
	var ht := _ground_row(hx, int(floor(top_at(hx, 0))))
	var tiers := [[8, 2], [5, 2]]
	for tier in tiers.size():
		var hw: int = tiers[tier][0]
		var rows: int = tiers[tier][1]
		var base := ht - 1 - tier * 2
		for dj in rows:
			for di in range(-hw, hw + 1):
				var trim: bool = dj == rows - 1
				var v := (2 if di < 0 else 0) if not trim else (2 if absi(di) % 3 == 0 else 1)
				if not trim and absi(di) == hw:
					v = 3
				_iput(hx + di, base - dj, Defs.RUNESTONE if trim else Defs.MASONRY, v, true)
		for di2 in range(-hw, hw + 1):
			var j3 := base + 1
			while j3 < H and j3 < base + 20 and cells[j3 * W + hx + di2] == 0:
				_iput(hx + di2, j3, Defs.MASONRY, 3, true)
				j3 += 1
	_iput(hx - 6, ht - 2, Defs.WISPBAR, 2, true)
	_iput(hx + 6, ht - 2, Defs.WISPBAR, 2, true)
	var top := ht - 5
	var hgt := 24
	for dj4 in hgt:
		var f := float(dj4) / float(hgt)
		var hi := int(round(3.8 * pow(1.0 - f, 0.8) + (0.7 if dj4 < 2 else 0.0)))
		for di4 in range(-hi, hi + 1):
			if dj4 == hgt - 1 and di4 != 0:
				continue
			if di4 == 0 and dj4 < hgt - 4:
				_guard_bg(hx, top - dj4, Defs.WISP, 3 if dj4 % 5 == 2 else 0)
			elif di4 < 0:
				_guard_bg(hx + di4, top - dj4, Defs.CRYSTAL, 3 if di4 == -hi else 1)
			else:
				_guard_bg(hx + di4, top - dj4, Defs.CRYSTAL, 2 if di4 == hi else 0)
	for dj5 in 7:
		var w2 := 2 - absi(dj5 - 3) * 2 / 3
		for di5 in range(-w2, w2 + 1):
			_guard_bg(hx + di5, top - hgt - 3 - dj5, Defs.CRYSTAL, 3 if di5 <= 0 else 2)
	for sgn in [-1, 1]:
		var sx: int = hx + 4 * sgn
		for q in 3:
			for dj6 in [4, 6, 3][q]:
				_guard_bg(sx + sgn * q, top - dj6, Defs.CRYSTAL, 3 if sgn < 0 else 2)

## the arch: a stepped base, pillars of dressed stone in courses (a lit inner edge, warded joints, rune lights),
## warded capitals, a ring of voussoirs, a wisp keystone; the opening kept clear
func _arch(ax: int) -> void:
	var at := _ground_row(ax, int(floor(top_at(ax, 0))))
	var r_in := float(ARCH_W) * 0.5
	var r_out := r_in + 4.0
	var spring := ARCH_H - ARCH_W / 2
	for dj in ARCH_H + 7:
		for di in range(-ARCH_W / 2 - 6, ARCH_W / 2 + 7):
			var y := at - 1 - dj
			var oy := dj - spring
			var fdi := float(di)
			var rr := Vector2(fdi, float(oy)).length()
			var inside: bool = absf(fdi) < r_in and (oy < 0 or rr < r_in)
			var outer: bool = absf(fdi) < r_out and (oy < 0 or rr < r_out)
			if inside:
				if y >= 0:
					guard[y * W + ax + di] = 1
				continue
			if dj < 2 and absf(fdi) < r_out + 2.0:
				_guard_bg(ax + di, y, Defs.MASONRY, 3 if dj == 1 else 1)
				continue
			if not outer:
				continue
			if oy < 0:
				var face := absf(fdi) - r_in
				var course := (dj - 2) / 5
				if oy >= -2:
					_guard_bg(ax + di, y, Defs.RUNESTONE, 2)
				elif face >= 3.0:
					_guard_bg(ax + di, y, Defs.RUNESTONE, 1)
				elif (dj - 2) % 5 == 4:
					_guard_bg(ax + di, y, Defs.RUNESTONE, 0)
				elif face < 1.0:
					_guard_bg(ax + di, y, Defs.MASONRY, 2)
				else:
					_guard_bg(ax + di, y, Defs.MASONRY, 0 if course % 2 == 1 else 1)
				if int(face) == 2 and (dj - 2) % 10 == 7 and oy < -4:
					_guard_bg(ax + di, y, Defs.WISP, 3)
			else:
				var an := atan2(float(oy), fdi) / PI * 9.0
				var seg := int(floor(an))
				var jn: bool = absf((an - floorf(an)) - 0.5) > 0.42
				if rr >= r_out - 1.0:
					_guard_bg(ax + di, y, Defs.RUNESTONE, 1)
				elif jn:
					_guard_bg(ax + di, y, Defs.RUNESTONE, 2)
				else:
					_guard_bg(ax + di, y, Defs.MASONRY, 2 if seg % 2 != 0 else 0)
	var ky := at - 1 - spring - int(r_in)
	for dj2 in range(-1, 4):
		for di2 in range(-1, 2):
			var lit: bool = absi(di2) + absi(dj2 - 1) < 2
			_guard_bg(ax + di2, ky - dj2, Defs.WISPBAR if lit else Defs.RUNESTONE, 3 if di2 == 0 and dj2 == 1 else 0)
	# (its feet go down to the ground under them, where the isle dips: the arch stood a little over the ground;
	# user, 25 Nov)
	for di3 in range(-ARCH_W / 2 - 6, ARCH_W / 2 + 7):
		if absf(float(di3)) >= r_in:
			var gj := _ground_row(ax + di3, at)
			for y2 in range(at, gj):
				_guard_bg(ax + di3, y2, Defs.MASONRY, 3)

func _guard_put(i: int, j: int, m: int) -> void:
	if i < 0 or j < 0 or i >= W or j >= H:
		return
	var k := j * W + i
	cells[k] = m
	vars[k] = (i + j) % 4
	guard[k] = 1
	natural[k] = 0
	made[k] = 0

## the heart's obelisk and the arch: back layer, never taken, drawn at full strength
func _guard_bg(i: int, j: int, m: int, v := -1) -> void:
	if i < 0 or j < 0 or i >= W or j >= H:
		return
	var k := j * W + i
	bg[k] = m
	bgv[k] = ((i + j) % 4) if v < 0 else (v & 3)
	guard[k] = 1

## a tree (back layer: scenery you walk past): a flared trunk tapering up, two boughs, a crown of blobs lit from
## the upper left. Stood on the ground really there (the isle's edge curves away under its smooth top; user, 25 Nov:
## "a tree that was attached to the ground by its leaves and its trunk was floating")
func _tree(tx: int, trunk: int, crown: int, sd := 0.0) -> void:
	var tt := _ground_row(tx, int(floor(top_at(tx, level))))
	for dj in trunk:
		var hw := 2 if float(dj) < float(trunk) * 0.45 else 1
		for di in range(-hw, hw + (1 if dj < 3 else 0)):
			_bg_put(tx + di, tt - 1 - dj, Defs.WOOD, 3 if di == -hw else (1 if di >= hw - 1 else 0))
	for di2 in [-4, -3, 3, 4]:
		_bg_put(tx + di2, tt - 1, Defs.ROOT, 1)
	_bg_put(tx - 3, tt - 2, Defs.ROOT, 0)
	_bg_put(tx + 3, tt - 2, Defs.ROOT, 0)
	var cy := tt - trunk
	for sg in [-1, 1]:
		for q in int(float(crown) * 0.7):
			_bg_put(tx + sg * (q + 1), cy + 4 - q / 2, Defs.WOOD, 0)
	var fc := float(crown)
	var blobs := [[0.0, -2.0, 1.0], [-fc * 0.62, 2.0, 0.72], [fc * 0.62, 2.0, 0.75], [-fc * 0.3, -fc * 0.5, 0.7], [fc * 0.35, -fc * 0.45, 0.68]]
	for bl in blobs:
		var bx: float = bl[0]
		var by: float = bl[1]
		var rx: float = (fc + 4.0) * float(bl[2])
		var ry: float = fc * float(bl[2]) * 0.85
		for dj2 in range(-int(ry) - 1, int(ry) + 2):
			for di3 in range(-int(rx) - 1, int(rx) + 2):
				var e := pow(float(di3) / rx, 2.0) + pow(float(dj2) / ry, 2.0)
				var jit := _h((float(tx) + bx + float(di3)) * 31.0 + (float(cy) + by + float(dj2)) * 7.0 + sd) * 0.16
				if e >= 1.0 - jit:
					continue
				var lit := -float(di3) / rx * 0.6 - float(dj2) / ry * 0.9
				var v := 3 if lit > 0.45 else (1 if lit > -0.1 else (0 if lit > -0.6 else 2))
				if e > 0.8 and lit < 0.2:
					v = 2
				_bg_put(int(float(tx) + bx) + di3, int(float(cy) + by) + dj2, Defs.LEAF, v)

## the first row at or below `from` (searching from a little above) where column i has ground: the isle's real top
func _ground_row(i: int, from: int) -> int:
	if i < 0 or i >= W:
		return from
	for j in range(maxi(0, from - 6), mini(H, from + 30)):
		if cells[j * W + i] != 0:
			return j
	return from

func _bush(bx: int) -> void:
	var bt := _ground_row(bx, int(floor(top_at(bx, level))))
	for dj in 6:
		for di in range(-6, 7):
			var e := pow(float(di) / 6.5, 2.0) + pow(float(dj) / 5.0, 2.0)
			if e < 1.0 - _h(float(di) * 13.0 + float(dj) * 5.0 + float(bx)) * 0.15:
				var lit := -float(di) / 6.5 * 0.5 + float(dj) / 5.0 * 0.9
				_bg_put(bx + di, bt - 1 - dj, Defs.LEAF, 3 if lit > 0.5 else (1 if lit > 0.0 else 0))
	if _h(float(bx) * 1.3) > 0.4:
		for q in 3:
			_bg_put(bx - 3 + q * 3, bt - 3 - (q % 2) * 2, Defs.CAP if _h(float(bx + q)) > 0.5 else Defs.CRYSTAL, 1)

## the isle dressed at a level (back layer, only where nothing is): grass tufts, flowers and stones on its top,
## vines down its rim, roots hanging under it
func _dress(lv: int) -> void:
	var hw: int = LEVELS[lv]
	var cx := W / 2
	var flowers := [Defs.CRYSTAL, Defs.SUNSTONE, Defs.FROST, Defs.CAP]
	for i in range(cx - hw, cx + hw + 1):
		var t := _ground_row(i, int(floor(top_at(i, lv))))
		if cells[t * W + i] != Defs.GRASS:
			continue
		var h1 := _h(float(i) * 2.31 + 0.7)
		if h1 > 0.55:
			var ln := 1 + int(_h(float(i) * 5.1) * 2.5)
			for dj in ln:
				_bg_put(i, t - 1 - dj, Defs.GRASS, 3 if dj == ln - 1 else 1, false)
		if h1 > 0.93:
			var fm: int = flowers[int(_h(float(i) * 8.3) * 4.0) % 4]
			_bg_put(i, t - 1, Defs.LEAF, 1, false)
			_bg_put(i, t - 2, Defs.LEAF, 3, false)
			_bg_put(i, t - 3, fm, 1, false)
			_bg_put(i - 1, t - 3, fm, 0, false)
			_bg_put(i + 1, t - 3, fm, 2, false)
			_bg_put(i, t - 4, fm, 3, false)
		if h1 > 0.18 and h1 < 0.2:
			for di in range(-2, 3):
				for dj2 in (2 if absi(di) < 2 else 1):
					_bg_put(i + di, t - 1 - dj2, Defs.MOSSBLOCK if dj2 == 1 or di < 0 else Defs.STONE, 2 if dj2 == 1 else 0, false)
	for i2 in range(cx - hw, cx + hw + 1):
		var ax := absf(float(i2 - cx)) / float(hw)
		var t2 := _ground_row(i2, int(floor(top_at(i2, lv))))
		# vines down the rim
		if ax > 0.72 and _h(float(i2) * 3.9 + 1.0) > 0.45:
			var vl := int(6.0 + _h(float(i2) * 4.7) * 18.0 * ax)
			var x := i2
			for dj3 in vl:
				var y := t2 + 2 + dj3
				if _h(float(i2) * 9.1 + float(dj3)) > 0.8:
					x += 1 if i2 > cx else -1
				if x >= 0 and x < W and y < H and cells[y * W + x] == 0:
					var leafy: bool = dj3 % 3 != 1 or _h(float(x) + float(dj3) * 3.3) > 0.5
					_bg_put(x, y, Defs.LEAF if leafy else Defs.WOOD, 3 if dj3 % 4 == 0 else 1, false)
					if dj3 == vl - 1 and _h(float(i2) * 1.1) > 0.6:
						_bg_put(x, y + 1, Defs.CRYSTAL, 3, false)
		# roots hanging from under it
		if ax < 0.9 and _h(float(i2) * 6.3 + 2.0) > 0.86:
			var b := int(float(t2) + depth_at(i2, lv)) + 1
			var rl := int(4.0 + _h(float(i2) * 2.9) * 14.0)
			var x2 := i2
			for dj4 in rl:
				var y2 := b + dj4
				if dj4 == 0:
					while y2 < H - 1 and cells[y2 * W + x2] != 0:
						y2 += 1
						b += 1
				if _h(float(i2) * 7.7 + float(dj4)) > 0.75:
					x2 += 1 if _h(float(i2 + dj4)) > 0.5 else -1
				if x2 >= 0 and x2 < W and y2 < H and cells[y2 * W + x2] == 0:
					_bg_put(x2, y2, Defs.ROOT, 1 if dj4 % 3 != 0 else 0, false)

func _bg_put(i: int, j: int, m: int, v := -1, over := true) -> void:
	if i < 0 or j < 0 or i >= W or j >= H:
		return
	var k := j * W + i
	if guard[k] == 1:
		return
	if not over and bg[k] != 0:
		return
	bg[k] = m
	bgv[k] = (int(_h(float(k) * 0.71) * 4.0) & 3) if v < 0 else (v & 3)

## the next level's ground round what's there (never over what you built), and a tree or two at its new edges
func expand() -> bool:
	if level >= LEVELS.size() - 1:
		return false
	level += 1
	_grow_ground(level)
	if level % 2 == 0:
		var hw: int = LEVELS[level]
		_tree(W / 2 - hw + 26, 18 + level, 9 + level, float(level))
		_tree(W / 2 + hw - 26, 20 + level, 10 + level, float(level) + 0.5)
	_dress(level)
	_all = true
	_lights_dirty = true
	return true

# ------------------------------------------------------------- building ---
# (the cabin builder's calls, as in a ship's room: here the room is everywhere over the isle)

func rebuild() -> void:
	pass                                # (it never moves: no mass or outline to work out)

func in_room(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= W or j >= H:
		return false
	if guard[j * W + i] == 1:
		return false
	var hw: int = LEVELS[level] + 40
	return absi(i - W / 2) <= hw and j >= SURF - BUILD_UP

func in_seat(_i: int, _j: int) -> bool:
	return false

func place(i: int, j: int, m: int, back := false, v := -1) -> bool:
	if not in_room(i, j) or m == 0:
		return false
	var k := j * W + i
	if back:
		bg[k] = m
		bgv[k] = (randi() & 3) if v < 0 else v
	else:
		if cells[k] != 0:
			return false
		cells[k] = m
		vars[k] = (randi() & 3) if v < 0 else v
		made[k] = 1
		natural[k] = 0
	touch(i, j)
	return true

## can the Remove tab take the front of cell k? (built or the isle's own, never the heart or the arch)
func can_take(k: int) -> bool:
	return cells[k] != 0 and guard[k] == 0

func remove(i: int, j: int, back := false) -> int:
	if i < 0 or j < 0 or i >= W or j >= H:
		return 0
	var k := j * W + i
	if guard[k] == 1:
		return 0
	var m := 0
	if back:
		m = bg[k]
		bg[k] = 0
	elif cells[k] != 0:
		m = cells[k]
		cells[k] = 0
		made[k] = 0
		natural[k] = 2                  # (dug out: growing the isle never fills it again)
		if m == Defs.GRASS:
			m = Defs.DIRT
	if m != 0:
		touch(i, j)
	return m

## a cell painted again before the next drawing
func touch(i: int, j: int) -> void:
	if i >= 0 and j >= 0 and i < W and j < H:
		_changed[j * W + i] = true
		_lights_dirty = true

func touch_all() -> void:
	_all = true
	_lights_dirty = true

# --------------------------------------------------------------- looks ---

func _front_col(i: int, j: int) -> Color:
	var k := j * W + i
	var m := cells[k]
	if m == 0:
		return Color(0, 0, 0, 0)
	var c := Color.hex((Defs.PAL[m * 4 + (vars[k] & 3)] << 8) | 0xff)
	if m == Defs.GLASS:
		c.a = 0.42
	elif natural[k] == 1 and m != Defs.CRYSTAL:
		# (the isle's own ground darkens with depth: a soft, deep underside)
		var d := float(j) - top_at(i, level)
		c = c.darkened(clampf(d / 70.0, 0.0, 0.5))
	return c

func _back_col(i: int, j: int) -> Color:
	var k := j * W + i
	var dk: int = deco[k]
	if dk > 0:
		return Color.html(String(Props.PALETTE[dk - 1])).darkened(0.08)
	var bm := bg[k]
	if bm == 0:
		return Color(0, 0, 0, 0)
	var bc := Color.hex((Defs.PAL[bm * 4 + (bgv[k] & 3)] << 8) | 0xff)
	if guard[k] == 1:
		return bc.darkened(0.05)            # (the heart and the arch: landmarks, not scenery)
	if bm in [Defs.LEAF, Defs.WOOD, Defs.GRASS, Defs.ROOT, Defs.CRYSTAL, Defs.SUNSTONE, Defs.FROST, Defs.CAP, Defs.WISPBAR]:
		return bc.darkened(0.16)            # (scenery: a little behind)
	bc = bc.darkened(0.35)
	if bm == Defs.GLASS:
		bc.a = 0.2
	return bc

## the pictures, painted again where something changed
func pictures() -> void:
	if img_f == null:
		img_f = Image.create(W, H, false, Image.FORMAT_RGBA8)
		img_b = Image.create(W, H, false, Image.FORMAT_RGBA8)
		_all = true
	if _all:
		img_f.fill(Color(0, 0, 0, 0))
		img_b.fill(Color(0, 0, 0, 0))
		# (only over the isle and what can be built round it: nothing lies past that)
		var hw: int = LEVELS[level] + 44
		for j in range(maxi(0, SURF - BUILD_UP - 4), H):
			for i in range(maxi(0, W / 2 - hw), mini(W, W / 2 + hw + 1)):
				var k := j * W + i
				if cells[k] != 0:
					img_f.set_pixel(i, j, _front_col(i, j))
				if bg[k] != 0 or deco[k] != 0:
					img_b.set_pixel(i, j, _back_col(i, j))
		_all = false
		_changed.clear()
	elif not _changed.is_empty():
		for k2 in _changed:
			var i2: int = int(k2) % W
			var j2: int = int(k2) / W
			img_f.set_pixel(i2, j2, _front_col(i2, j2))
			img_b.set_pixel(i2, j2, _back_col(i2, j2))
		_changed.clear()
	else:
		if tex_f != null:
			return
	if tex_f == null:
		tex_f = ImageTexture.create_from_image(img_f)
		tex_b = ImageTexture.create_from_image(img_b)
	else:
		tex_f.update(img_f)
		tex_b.update(img_b)

## the glowing cells gathered into a few halos (blocks of 12 x 12)
func gather_lights() -> void:
	if not _lights_dirty:
		return
	_lights_dirty = false
	lights.clear()
	var hw: int = LEVELS[level] + 44
	for by in range(0, H, 12):
		for bx in range(maxi(0, W / 2 - hw), mini(W, W / 2 + hw), 12):
			var n := 0
			var col := Color(0, 0, 0)
			var sx := 0.0
			var sy := 0.0
			for j in range(by, mini(by + 12, H)):
				for i in range(bx, mini(bx + 12, W)):
					var m := cells[j * W + i]
					if m == 0 and (guard[j * W + i] == 1 or bg[j * W + i] == Defs.WISPBAR):
						m = bg[j * W + i]              # (the obelisk and the terrace's lanterns glow from the back layer)
					var c := Color(0, 0, 0)
					if m == Defs.CRYSTAL:
						c = Color(0.85, 0.45, 1.0)
					elif m == Defs.WISP or m == Defs.WISPBAR:
						c = Color(0.45, 0.6, 1.0)
					elif m == Defs.TORCH or m == Defs.EMBER:
						c = Color(1.0, 0.65, 0.3)
					else:
						continue
					n += 1
					col += c
					sx += float(i)
					sy += float(j)
			if n > 0:
				lights.append([Vector2(sx / n + 0.5, sy / n + 0.5), 10.0 + sqrt(float(n)) * 5.0, col / float(n)])

# --------------------------------------------------------------- saving ---

func save_isle() -> Dictionary:
	var d := save_cells()
	var raw := PackedByteArray()
	raw.append_array(natural)
	raw.append_array(guard)
	d["isle"] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	d["level"] = level
	d["v"] = 2
	d["art"] = ART
	return d

func load_isle(d: Dictionary) -> bool:
	make()
	if int(d.get("v", 1)) < 2:
		return false                    # (before the heart and arch stood on the back layer: made afresh)
	if not load_cells(d):
		return false
	var n := W * H
	var raw := Marshalls.base64_to_raw(String(d.get("isle", ""))).decompress(n * 2, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() == n * 2:
		natural = raw.slice(0, n)
		guard = raw.slice(n, n * 2)
	level = clampi(int(d.get("level", 0)), 0, LEVELS.size() - 1)
	ang = PI
	facing = 1
	pos = Vector2.ZERO
	com = Vector2.ZERO
	if int(d.get("art", 0)) < ART:
		_ground_features()
		_restyle()
	_all = true
	_lights_dirty = true
	return true

## An isle made before its new look (25 Nov; user: "the pocket dimension still needs work. it looks a little thrown
## together still"): its ground laid again in strata (only its own cells, the shape kept), the heart and the arch
## carved afresh, the path, the terrace where nothing's built there, new trees, and the isle dressed. Nothing you
## built is touched.
func _restyle() -> void:
	for k in W * H:
		if guard[k] == 1:
			guard[k] = 0
			if bg[k] != 0:
				bg[k] = 0
			if cells[k] != 0 and made[k] == 0:
				cells[k] = 0                # (the old plinth)
				natural[k] = 0
	_grow_ground(level)
	var cx := W / 2
	_path(cx)
	# the terrace, if nothing's built where it goes (the old big tree there goes with the ground cut for it)
	var clear := true
	for i in range(cx + TER_A - 22, cx + TER_B + 22):
		for j in range(SURF - 60, SURF + 20):
			if made[j * W + i] == 1 or (natural[j * W + i] == 2 and j > SURF - 30):
				clear = false
	if clear:
		for i2 in range(cx + 46 - 22, cx + 46 + 23):
			for j2 in range(SURF - 60, SURF + 4):
				var k2 := j2 * W + i2
				if bg[k2] == Defs.LEAF or bg[k2] == Defs.WOOD:
					bg[k2] = 0
		_terrace(cx)
		_tree(cx + 63, 24, 12, 1.0)
	_heart(cx + HEART_DX)
	_arch(cx + ARCH_DX)
	_tree(cx - 63, 17, 9, 2.0)
	for lv in level + 1:
		_dress(lv)

## An isle made before 25 Nov: its own trees, the arch's pillars and the obelisk's plinth could stand over a dip
## in the ground (user: "a tree that was attached to the ground by its leaves and its trunk was floating along
## with the portal was a little bit floating"). Only empty cells straight under them are filled, down to ground.
func _ground_features() -> void:
	var cx := W / 2
	var cols := []
	var ax := cx + ARCH_DX
	for di in range(-ARCH_W / 2 - 4, ARCH_W / 2 + 5):
		if absf(float(di)) >= float(ARCH_W) * 0.5:
			cols.append([ax + di, Defs.RUNESTONE, true])
	var trees := [cx + 46, cx - 74, cx - 62, cx + 63, cx - 63]
	for lv in range(2, level + 1, 2):
		trees.append(W / 2 - int(LEVELS[lv]) + 26)
		trees.append(W / 2 + int(LEVELS[lv]) - 26)
	for tx in trees:
		for di2 in range(-1, 2):
			cols.append([int(tx) + di2, Defs.WOOD, false])
	for c in cols:
		var i: int = c[0]
		var mt: int = c[1]
		if i < 0 or i >= W:
			continue
		# the lowest cell of it in this column, then down through empty cells to the ground
		var low := -1
		for j in range(H - 1, -1, -1):
			if bg[j * W + i] == mt:
				low = j
				break
		if low < 0:
			continue
		var j2 := low + 1
		while j2 < H and j2 < low + 16 and cells[j2 * W + i] == 0 and bg[j2 * W + i] == 0:
			j2 += 1
		if j2 >= H or j2 >= low + 16 or cells[j2 * W + i] == 0:
			continue                    # (nothing under it near enough: leave it be)
		for j3 in range(low + 1, j2):
			if bool(c[2]):
				_guard_bg(i, j3, mt)
			else:
				_bg_put(i, j3, mt)
	var hx := cx + HEART_DX
	var ht := int(floor(top_at(hx, 0)))
	for di5 in range(-5, 6):
		var y3 := ht
		while y3 < H and y3 < ht + 30 and cells[y3 * W + hx + di5] == 0:
			_guard_put(hx + di5, y3, Defs.RUNESTONE)
			y3 += 1
