## A body made of real cells that moves as one: the general type for everything that flies or
## drifts as an object (the skiff now; asteroids, enemy ships and wrecks later).
##
## Its cells sit in a w x h grid (material per cell, 0 = empty; colour variant per cell), in body
## coordinates: x along the nose, y down. It has a place and a turn in the world (`pos`, the angle of
## its +x axis `ang`, `facing` -1 to mirror it), a velocity and a spin. From the cells come its mass,
## centre of mass (`com`, the point `pos` is), the outline it collides by, and a texture made of the
## materials' own palette colours. Damage carves cells out (`carve`); a body cut in two can be
## pulled apart into its joined-up pieces (`pieces`).
extends RefCounted

var w := 0
var h := 0
var cells := PackedByteArray()     # material per cell (0 = empty)
var vars := PackedByteArray()      # colour variant per cell
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

func setup(width: int, height: int) -> void:
	w = width
	h = height
	cells.resize(w * h)
	cells.fill(0)
	vars.resize(w * h)
	vars.fill(0)

func at(i: int, j: int) -> int:
	if i < 0 or j < 0 or i >= w or j >= h:
		return 0
	return cells[j * w + i]

func put(i: int, j: int, m: int, v := -1) -> void:
	if i < 0 or j < 0 or i >= w or j >= h:
		return
	cells[j * w + i] = m
	vars[j * w + i] = (randi() & 3) if v < 0 else v

## Mass, centre of mass and outline from the cells (after building or damage).
func rebuild() -> void:
	mass = 0.0
	var sum := Vector2.ZERO
	for j in h:
		for i in w:
			var m := cells[j * w + i]
			if m != 0:
				var dm := 0.4 if m == Defs.GLASS else 1.0
				mass += dm
				sum += Vector2(i + 0.5, j + 0.5) * dm
	com = sum / maxf(mass, 0.001)
	outline = PackedVector2Array()
	for j2 in h:
		for i2 in w:
			if cells[j2 * w + i2] == 0:
				continue
			if at(i2 - 1, j2) == 0 or at(i2 + 1, j2) == 0 or at(i2, j2 - 1) == 0 or at(i2, j2 + 1) == 0:
				outline.append(Vector2(i2 + 0.5, j2 + 0.5) - com)
	dirty = true

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
	dirty = false
	return tex

# --------------------------------------------------------------- damage ---

## Carve the cells within `r` of a world point out of the body. Returns how many went.
func carve(p: Vector2, r: float) -> int:
	var b := to_body(p) + com
	var n := 0
	for j in range(maxi(0, int(b.y - r - 1)), mini(h, int(b.y + r + 2))):
		for i in range(maxi(0, int(b.x - r - 1)), mini(w, int(b.x + r + 2))):
			if cells[j * w + i] != 0 and Vector2(i + 0.5, j + 0.5).distance_to(b) <= r:
				cells[j * w + i] = 0
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
