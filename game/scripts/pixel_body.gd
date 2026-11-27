## A body made of real cells that moves as one: the general type for everything that flies or
## drifts as an object (the skiff now; asteroids, enemy ships and wrecks later).
##
## Its cells sit in a w x h grid (material per cell, 0 = empty; colour variant per cell), in body
## coordinates: x along the nose, y down. It has a place and a turn in the world (`pos`, the angle of
## its +x axis `ang`, `facing` -1 to mirror it), a velocity and a spin. From the cells come its mass,
## centre of mass (`com`, the point `pos` is), the outline it collides by, and a texture made of the
## materials' own palette colours. Damage carves cells out (`carve`); a body cut in two can be
## pulled apart into its joined-up pieces (`pieces`).
##
## Room inside: the cells its hull closes in (`room`, found from the outside by `rebuild`) are a
## space that can be built in, like a house: blocks in front (`place`, `remove`: they never change
## the outline it collides by) and a back layer behind (`bg`: back walls, later furniture), drawn
## behind whoever is inside. What was built is told apart from the hull (`made`), and everything is
## saved cell by cell (`save_cells` / `load_cells`).
extends RefCounted

const Props := preload("res://scripts/props.gd")

var w := 0
var h := 0
var cells := PackedByteArray()     # material per cell (0 = empty)
var vars := PackedByteArray()      # colour variant per cell
var made := PackedByteArray()      # 1: built inside (not part of the hull)
var bg := PackedByteArray()        # back layer: material per cell (0 = none)
var bgv := PackedByteArray()       # back layer: colour variant
var deco := PackedByteArray()      # furniture in front of the back layer (Props.PALETTE index + 1; 0 = none)
var room := PackedByteArray()      # 1: closed in by the hull (a place to build)
var outside := PackedByteArray()   # 1: open to the outside (rebuild's flood)
var keel := Vector2.ZERO           # its lowest outline point (body coordinates, from the centre of mass)
var pos := Vector2.ZERO            # where the centre of mass is (world, or the space frame)
var ang := 0.0                     # world angle of the body's +x axis
var facing := 1                    # -1: mirrored (the nose points along -x)
var vel := Vector2.ZERO
var omega := 0.0
var mass := 0.0
var com := Vector2.ZERO            # centre of mass, in cell coordinates
var outline := PackedVector2Array()   # boundary cells (body coordinates, from the centre of mass)
var tex: ImageTexture
var dirty := true                  # the texture needs making again
var bg_tex: ImageTexture

func setup(width: int, height: int) -> void:
	w = width
	h = height
	cells.resize(w * h)
	cells.fill(0)
	vars.resize(w * h)
	vars.fill(0)
	# (one by one: packed arrays taken out of an Array in a loop would be copies)
	made.resize(w * h)
	made.fill(0)
	bg.resize(w * h)
	bg.fill(0)
	bgv.resize(w * h)
	bgv.fill(0)
	deco.resize(w * h)
	deco.fill(0)
	room.resize(w * h)
	room.fill(0)
	outside.resize(w * h)
	outside.fill(0)

func at(i: int, j: int) -> int:
	if i < 0 or j < 0 or i >= w or j >= h:
		return 0
	return cells[j * w + i]

func put(i: int, j: int, m: int, v := -1) -> void:
	if i < 0 or j < 0 or i >= w or j >= h:
		return
	cells[j * w + i] = m
	vars[j * w + i] = (randi() & 3) if v < 0 else v

func hull_at(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= w or j >= h:
		return false
	return cells[j * w + i] != 0 and made[j * w + i] == 0

## Mass, centre of mass, the room inside and the outline from the cells (after building or damage).
func rebuild() -> void:
	mass = 0.0
	var sum := Vector2.ZERO
	for j in h:
		for i in w:
			var k := j * w + i
			var dm := 0.0
			var m := cells[k]
			if m != 0:
				dm = 0.4 if m == Defs.GLASS else 1.0
			if bg[k] != 0:
				dm += 0.1 if bg[k] == Defs.GLASS else 0.25
			if dm > 0.0:
				mass += dm
				sum += Vector2(i + 0.5, j + 0.5) * dm
	com = sum / maxf(mass, 0.001)
	# what's open to the outside: a flood from the edges through everything but the hull
	outside.fill(0)
	var q := PackedInt32Array()
	for k2 in w * h:
		var bi := k2 % w
		var bj := k2 / w
		if (bi == 0 or bj == 0 or bi == w - 1 or bj == h - 1) and not hull_at(bi, bj):
			outside[k2] = 1
			q.append(k2)
	while not q.is_empty():
		var c: int = q[q.size() - 1]
		q.resize(q.size() - 1)
		var ci := c % w
		var cj := c / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = ci + d.x
			var nj: int = cj + d.y
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var nk := nj * w + ni
			if outside[nk] == 0 and not hull_at(ni, nj):
				outside[nk] = 1
				q.append(nk)
	# the room: closed in, and not hull
	for k3 in w * h:
		room[k3] = 1 if outside[k3] == 0 and (cells[k3] == 0 or made[k3] == 1) else 0
	# the outline it collides by: cells that touch the outside (what's built inside never does)
	outline = PackedVector2Array()
	keel = Vector2.ZERO
	for j2 in h:
		for i2 in w:
			if cells[j2 * w + i2] == 0:
				continue
			if _open(i2 - 1, j2) or _open(i2 + 1, j2) or _open(i2, j2 - 1) or _open(i2, j2 + 1):
				var b := Vector2(i2 + 0.5, j2 + 0.5) - com
				outline.append(b)
				if b.y > keel.y:
					keel = b
	dirty = true

func _open(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= w or j >= h:
		return true
	return outside[j * w + i] == 1

# ------------------------------------------------------------- building ---

## a cell of the room inside (closed in by the hull)
func in_room(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= w or j >= h:
		return false
	return room[j * w + i] == 1

## Build a block inside (front, `back` false: only into an empty cell of the room) or a back wall
## (`back` true: anywhere in the room). Returns whether it went in.
func place(i: int, j: int, m: int, back := false, v := -1) -> bool:
	if not in_room(i, j) or m == 0:
		return false
	var k := j * w + i
	if back:
		bg[k] = m
		bgv[k] = (randi() & 3) if v < 0 else v
	else:
		if cells[k] != 0:
			return false
		cells[k] = m
		vars[k] = (randi() & 3) if v < 0 else v
		made[k] = 1
	rebuild()
	return true

## can the Remove tab take the front of cell k? (only what was built inside; the pocket's isle: anything but
## its heart and arch)
func can_take(k: int) -> bool:
	return made[k] == 1 and cells[k] != 0

## a cell changed outside place/remove (furniture): the picture is made again
func touch(_i: int, _j: int) -> void:
	dirty = true

## Take out what was built in a cell of the room (the hull itself only comes away by `carve`).
## Returns the material taken, 0 if none.
func remove(i: int, j: int, back := false) -> int:
	if not in_room(i, j):
		return 0
	var k := j * w + i
	var m := 0
	if back:
		m = bg[k]
		bg[k] = 0
	elif made[k] == 1:
		m = cells[k]
		cells[k] = 0
		made[k] = 0
	if m != 0:
		rebuild()
	return m

## the cells as saved: both layers, what was built and the furniture, packed
func save_cells() -> Dictionary:
	var raw := PackedByteArray()
	for a in [cells, vars, made, bg, bgv, deco]:
		raw.append_array(a)
	return {"w": w, "h": h, "cells": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))}

## Back from `save_cells` (a body of the same size only). Returns whether it took.
func load_cells(d: Dictionary) -> bool:
	if int(d.get("w", -1)) != w or int(d.get("h", -1)) != h or not d.has("cells"):
		return false
	var n := w * h
	# (six layers since the furniture came in; a save from before has five)
	var raw := Marshalls.base64_to_raw(String(d["cells"])).decompress(n * 6, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != n * 5 and raw.size() != n * 6:
		return false
	cells = raw.slice(0, n)
	vars = raw.slice(n, n * 2)
	made = raw.slice(n * 2, n * 3)
	bg = raw.slice(n * 3, n * 4)
	bgv = raw.slice(n * 4, n * 5)
	if raw.size() == n * 6:
		deco = raw.slice(n * 5, n * 6)
	else:
		deco.resize(n)
		deco.fill(0)
	rebuild()
	return true

# ------------------------------------------------------------ transforms ---

## the body's axes in the world: x along the nose (mirrored when facing -1), y "down" through the keel
func axis_x() -> Vector2:
	return Vector2(cos(ang), sin(ang)) * float(facing)

func axis_y() -> Vector2:
	var d := Vector2(cos(ang), sin(ang))
	return Vector2(d.y, -d.x)          # (the planet's own "down" is "right" turned a quarter clockwise)

## a point in body coordinates (cells, from the centre of mass) -> world
func to_world(b: Vector2) -> Vector2:
	return pos + axis_x() * b.x + axis_y() * b.y

## a cell's centre -> world
func cell_world(i: int, j: int) -> Vector2:
	return to_world(Vector2(i + 0.5, j + 0.5) - com)

## world -> body coordinates (cells, from the centre of mass)
func to_body(p: Vector2) -> Vector2:
	var o := p - pos
	var ax := axis_x()
	var ay := axis_y()
	return Vector2(o.dot(ax), o.dot(ay))

## the nose's direction in the world
func nose() -> Vector2:
	return axis_x()

# ---------------------------------------------------------------- looks ---

## The body as a picture: each cell in its material's palette colour (variant-shaded), glass
## see-through.
func texture() -> ImageTexture:
	if not dirty and tex != null:
		return tex
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for j in h:
		for i in w:
			var m := cells[j * w + i]
			if m == 0:
				continue
			var c := Color.hex((Defs.PAL[m * 4 + (vars[j * w + i] & 3)] << 8) | 0xff)
			if m == Defs.GLASS:
				c.a = 0.42
			img.set_pixel(i, j, c)
	if tex == null or tex.get_width() != w or tex.get_height() != h:
		tex = ImageTexture.create_from_image(img)
	else:
		tex.update(img)
	# the back layer, drawn behind whoever is inside (shaded like a back wall; glass faint)
	var bimg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for j2 in h:
		for i2 in w:
			var dk: int = deco[j2 * w + i2] if deco.size() == w * h else 0
			if dk > Props.PALETTE.size():
				bimg.set_pixel(i2, j2, Color(1.0, 0.62, 0.25))       # (a torch's flame: pocket_isle.gd FLAME)
				continue
			if dk > 0:
				# (furniture, in front of the back wall: its own palette colour, a touch shaded)
				bimg.set_pixel(i2, j2, Color.html(String(Props.PALETTE[dk - 1])).darkened(0.08))
				continue
			var bm := bg[j2 * w + i2]
			if bm == 0:
				continue
			var bc := Color.hex((Defs.PAL[bm * 4 + (bgv[j2 * w + i2] & 3)] << 8) | 0xff).darkened(0.35)
			if bm == Defs.GLASS:
				bc.a = 0.2
			bimg.set_pixel(i2, j2, bc)
	if bg_tex == null or bg_tex.get_width() != w or bg_tex.get_height() != h:
		bg_tex = ImageTexture.create_from_image(bimg)
	else:
		bg_tex.update(bimg)
	dirty = false
	return tex

func back_texture() -> ImageTexture:
	texture()
	return bg_tex

# --------------------------------------------------------------- damage ---

## Is the world point p inside one of its cells?
func solid_at(p: Vector2) -> bool:
	var b := to_body(p) + com
	var i := int(floor(b.x))
	var j := int(floor(b.y))
	return i >= 0 and j >= 0 and i < w and j < h and cells[j * w + i] != 0

## Carve the cells within `r` of a world point out of the body. Returns how many went.
func carve(p: Vector2, r: float) -> int:
	var b := to_body(p) + com
	var n := 0
	for j in range(maxi(0, int(b.y - r - 1)), mini(h, int(b.y + r + 2))):
		for i in range(maxi(0, int(b.x - r - 1)), mini(w, int(b.x + r + 2))):
			if cells[j * w + i] != 0 and Vector2(i + 0.5, j + 0.5).distance_to(b) <= r:
				cells[j * w + i] = 0
				made[j * w + i] = 0
				n += 1
	if n > 0:
		rebuild()
	return n

## The body's joined-up pieces (8-neighbour), biggest first, each a list of cell indices. One
## piece: still whole.
func pieces() -> Array:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var out := []
	for k in w * h:
		if cells[k] == 0 or seen[k] == 1:
			continue
		var comp := PackedInt32Array([k])
		seen[k] = 1
		var q := PackedInt32Array([k])
		while not q.is_empty():
			var c: int = q[q.size() - 1]
			q.resize(q.size() - 1)
			var ci := c % w
			var cj := c / w
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var ni := ci + di
					var nj := cj + dj
					if ni < 0 or nj < 0 or ni >= w or nj >= h:
						continue
					var nk := nj * w + ni
					if cells[nk] != 0 and seen[nk] == 0:
						seen[nk] = 1
						comp.append(nk)
						q.append(nk)
		out.append(comp)
	out.sort_custom(func(a, b): return a.size() > b.size())
	return out

# ------------------------------------------------- moving about inside it ---
# (a derelict station's rooms, a ship's decks: a body the mage's size moves through its cells)

## is a cell solid to someone in it? (a scaffold only to someone falling onto it in a powered room)
func solid_cell(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= w or j >= h:
		return false
	var t := cells[j * w + i]
	return t != 0 and t != Defs.SCAFFOLD

func scaffold_cell(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < w and j < h and cells[j * w + i] == Defs.SCAFFOLD

## a box (body cell coords of its middle, half sizes) clear of solid cells?
## (a little give at the edges: a body resting on a floor sits on a cell boundary exactly, and world positions
## are single floats, good to about 0.005 of a cell this far out, so the trip there and back can move it a hair
## into the next cell)
const EPS := 0.04

func box_free(b: Vector2, hw: float, hh: float) -> bool:
	var i0 := int(floor(b.x - hw + EPS))
	var i1 := int(ceil(b.x + hw - EPS))
	var j0 := int(floor(b.y - hh + EPS))
	var j1 := int(ceil(b.y + hh - EPS))
	for j in range(j0, j1):
		if j < 0 or j >= h:
			continue
		var row := j * w
		for i in range(i0, i1):
			if i < 0 or i >= w:
				continue
			var t := cells[row + i]
			if t != 0 and t != Defs.SCAFFOLD:
				return false
	return true

## a one-way floor under a box's feet, crossing from `fy0` down to `fy1` (rows)?
func platform_under(b: Vector2, hw: float, fy0: float, fy1: float) -> bool:
	var j0 := int(ceil(fy0 - EPS))
	var j1 := int(floor(fy1))
	for j in range(j0, j1 + 1):
		for i in range(int(floor(b.x - hw + EPS)), int(ceil(b.x + hw - EPS))):
			if scaffold_cell(i, j):
				return true
	return false

## Moves a box (middle `b`, half sizes, velocity `v`, body cells) through the body a cell at a time:
## across, stepping up to `step` cells onto a ledge; then along +y, landing on solid cells and, falling
## (`grav`) and not dropping through (`drop`), on a scaffold's top. Returns [b, v, on_ground, hit a wall].
func move_box(b: Vector2, v: Vector2, hw: float, hh: float, grav: bool, step: int, drop: bool) -> Array:
	var ground := false
	var wall := false
	var n := int(ceil(absf(v.x)))
	if n > 0:
		var sx := v.x / float(n)
		for k in n:
			var nb := Vector2(b.x + sx, b.y)
			if box_free(nb, hw, hh):
				b = nb
				continue
			var up := false
			for s in range(1, step + 1):
				var ub := Vector2(nb.x, nb.y - float(s))
				if box_free(ub, hw, hh):
					b = ub
					up = true
					break
			if not up:
				v.x = 0.0
				wall = true
				break
	n = int(ceil(absf(v.y)))
	if n > 0:
		var sy := v.y / float(n)
		for k2 in n:
			var nb2 := Vector2(b.x, b.y + sy)
			var blocked := not box_free(nb2, hw, hh)
			if not blocked and grav and sy > 0.0 and not drop and platform_under(b, hw, b.y + hh, nb2.y + hh):
				blocked = true
				var pb := Vector2(b.x, floor(nb2.y + hh) - hh)
				if pb.y >= b.y:
					b = pb
			if blocked:
				if sy > 0.0:
					ground = true
					var sb := Vector2(b.x, floor(nb2.y + hh) - hh)
					if sb.y > b.y and box_free(sb, hw, hh):
						b = sb
				v.y = 0.0
				break
			b = nb2
	return [b, v, ground, wall]

