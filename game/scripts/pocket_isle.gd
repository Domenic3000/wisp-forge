## The isle in your ship's pocket dimension (user, 24 Nov: "the inside of the ship be like a pocket dimension
## that you can enter ... an instanced area that you can expand and build inside. a beautiful pocket
## dimension"; chose an isle in a nebula): a pixel body (pixel_body.gd) that never moves, so the cabin
## builder's tools (main `_cabin_edit`) build on it as they do in a ship: blocks and back walls into its
## open cells, furniture, the Remove tab.
##
## Its cells: W x H, laid out so body +x is screen right and +y screen down (ang PI, facing 1, at the origin:
## `to_world(b)` = (-b.x, b.y)). The isle's own ground (`natural`) is grown from its `level` (`LEVELS`: half
## widths): grass, earth, stone with crystal specks, a lumpy underside with crystal drips; trees and bushes on
## the back layer (scenery you walk past). `guard` cells (the Isle Heart's obelisk and the arch you leave by)
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

## the isle's own matter at a cell for a level, or 0
func ground_at(i: int, j: int, lv: int) -> int:
	var dep := depth_at(i, lv)
	if dep <= 0.0:
		return 0
	var top := top_at(i, lv)
	var fj := float(j)
	var bottom := top + dep
	# crystal drips hanging under the isle
	var drip := 0.0
	if _h(float(i) * 1.7 + 3.0) > 0.8:
		drip = 3.0 + _h(float(i) * 2.3) * 9.0 * (1.0 - absf(float(i - W / 2)) / float(LEVELS[lv]))
	if fj < floor(top) or fj > bottom + drip:
		return 0
	if fj > bottom:
		return Defs.CRYSTAL if _h(float(i) * 3.1) > 0.45 else Defs.STONE
	var d := fj - floorf(top)
	if d < 2.0:
		return Defs.GRASS
	if d < 8.0 + 3.0 * sin(float(i) * 0.29):
		return Defs.DIRT
	if _h(float(i) * 7.13 + float(j) * 3.7) > 0.985:
		return Defs.CRYSTAL
	if fj > bottom - 3.0:
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

## the arch (leave by it), the Isle Heart (grow the isle there), a tree, bushes
func _features() -> void:
	var cx := W / 2
	# the Isle Heart: a crystal obelisk on a runestone plinth, a seam of wisp light up its middle
	var hx := cx + HEART_DX
	var ht := int(floor(top_at(hx, 0)))
	for dj in 3:
		for di in range(-5, 6):
			_guard_put(hx + di, ht - 1 - dj, Defs.RUNESTONE)
	for dj2 in 20:
		var half := int(round(3.5 * (1.0 - float(dj2) / 21.0))) + (1 if dj2 < 3 else 0)
		for di2 in range(-half, half + 1):
			_guard_bg(hx + di2, ht - 4 - dj2, Defs.WISP if di2 == 0 and dj2 < 15 else Defs.CRYSTAL)
	# the arch: two runestone pillars and a round top, the opening clear (the obelisk and the arch stand on the
	# back layer: you walk in front of them, nothing on the isle bars your way)
	var ax := cx + ARCH_DX
	var at := int(floor(top_at(ax, 0)))
	for dj3 in ARCH_H + 6:
		for di3 in range(-ARCH_W / 2 - 4, ARCH_W / 2 + 5):
			var y := at - 1 - dj3
			var inner_r := float(ARCH_W) * 0.5
			var oy := float(dj3) - float(ARCH_H - ARCH_W / 2)
			var inside: bool = absf(float(di3)) < inner_r and (oy < 0.0 or Vector2(float(di3), oy).length() < inner_r)
			var outer: bool = absf(float(di3)) < inner_r + 4.0 and (oy < 0.0 or Vector2(float(di3), oy).length() < inner_r + 4.0)
			if outer and not inside:
				_guard_bg(ax + di3, y, Defs.RUNESTONE)
			elif inside:
				guard[y * W + ax + di3] = 1        # (the opening: kept clear)
	# (its pillars and the obelisk's plinth go down to the ground under them, where the isle dips: the arch stood
	# a little over the ground; user, 25 Nov)
	for di4 in range(-ARCH_W / 2 - 4, ARCH_W / 2 + 5):
		if absf(float(di4)) >= float(ARCH_W) * 0.5:
			var gj := _ground_row(ax + di4, at)
			for y2 in range(at, gj):
				_guard_bg(ax + di4, y2, Defs.RUNESTONE)
	for di5 in range(-5, 6):
		var y3 := ht
		while y3 < H and y3 < ht + 30 and cells[y3 * W + hx + di5] == 0:
			_guard_put(hx + di5, y3, Defs.RUNESTONE)
			y3 += 1
	# a tree and a few bushes (the back layer: scenery you walk past)
	_tree(cx + 46, 26, 13)
	_tree(cx - 62, 18, 9)                  # (was 74 out: past the first ground's edge, its trunk down the side)
	for bx in [cx - 24, cx + 22, cx + 64, cx - 58]:
		_bush(bx)

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
func _guard_bg(i: int, j: int, m: int) -> void:
	if i < 0 or j < 0 or i >= W or j >= H:
		return
	var k := j * W + i
	bg[k] = m
	bgv[k] = (i + j) % 4
	guard[k] = 1

func _tree(tx: int, trunk: int, crown: int) -> void:
	# (stood on the ground really there: the isle's edge curves away under its smooth top, and a tree at a new
	# edge stood a few cells over it, its trunk in the air and its crown touching the ground; user, 25 Nov)
	var tt := _ground_row(tx, int(floor(top_at(tx, level))))
	for dj in trunk:
		for di in range(-1, 2):
			_bg_put(tx + di, tt - 1 - dj, Defs.WOOD)
	var cy := tt - trunk
	for dj2 in range(-crown, crown + 1):
		for di2 in range(-crown - 6, crown + 7):
			var e := pow(float(di2) / float(crown + 6), 2.0) + pow(float(dj2) / float(crown), 2.0)
			if e < 1.0 - _h(float(di2 * 31 + dj2)) * 0.12:
				_bg_put(tx + di2, cy + dj2, Defs.LEAF)

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
	for dj in 5:
		for di in range(-5, 6):
			if pow(float(di) / 5.5, 2.0) + pow(float(dj) / 4.5, 2.0) < 1.0:
				_bg_put(bx + di, bt - 1 - dj, Defs.LEAF)

func _bg_put(i: int, j: int, m: int) -> void:
	if i < 0 or j < 0 or i >= W or j >= H:
		return
	var k := j * W + i
	if guard[k] == 1:
		return
	bg[k] = m
	bgv[k] = int(_h(float(k) * 0.71) * 4.0) & 3

## the next level's ground round what's there (never over what you built), and a tree or two at its new edges
func expand() -> bool:
	if level >= LEVELS.size() - 1:
		return false
	level += 1
	_grow_ground(level)
	if level % 2 == 0:
		var hw: int = LEVELS[level]
		_tree(W / 2 - hw + 26, 18 + level, 9 + level)
		_tree(W / 2 + hw - 26, 20 + level, 10 + level)
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
	if bm == Defs.LEAF or bm == Defs.WOOD:
		return bc.darkened(0.18)            # (scenery: a little behind)
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
					if m == 0 and guard[j * W + i] == 1:
						m = bg[j * W + i]              # (the obelisk glows from the back layer)
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
	_ground_features()
	_all = true
	_lights_dirty = true
	return true

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
	var trees := [cx + 46, cx - 74, cx - 62]
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
