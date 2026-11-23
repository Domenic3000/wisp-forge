## An asteroid: a pixel body (pixel_body.gd) of rock drifting in space, grown from parts by its seed.
##
## `Asteroid.make(seed, radius, kind)` grows it: a lumpy outline (a few harmonics plus fine grain,
## sometimes drawn out long), bites taken out of its edge as craters, then its matter by depth and
## noise: a crust of loose regolith, a body of stone or ice, and veins and pockets of ore that
## depend on its kind (KINDS: stony rocks carry copper, coal and prism crystal; icy ones frost and
## ice; dark metallic ones deepstone and wisp ore, which a better staff is needed for, and in their
## hearts star iron, which no planet has: the Core Drive that takes the skiff to the next planet needs it).
##
## You mine it with the staff (space.gd `mine`): cells within reach come out into the satchel at the
## same pace and by the same hardness rules as digging on a planet. A rock cut through drifts apart
## into its pieces (space.gd splits it with `split_off`); scraps too small to keep crumble to dust.
## Its picture is lit by the sun in space.gd's shader (`LIT`), its glowing ores excepted.
extends "res://scripts/pixel_body.gd"

const KINDS := ["stony", "icy", "metallic"]

var seed_ := 0
var kind := "stony"
var rad := 20.0              # its rough radius (cells): the light's sphere, the camera's framing
var dust := 0                # (carved since it was last rebuilt: rebuilding waits a few frames)
var img: Image               # its picture, kept so mining only clears the pixels it takes
var img_dirty := false
var sect := ""                # the galaxy sector it belongs to (space.gd streams them); "" = one of home's clusters
var touched := false          # mined since it was grown (its sector keeps it as it is now)
var orbit := {}               # a comet's loop (galaxy.gd comet_at); empty for a drifting rock
var loop_at := Vector2.ZERO   # (a comet: the middle of its loop, from its sector's corner)

static func make(sd: int, radius: float, knd: String) -> RefCounted:
	var a = load("res://scripts/asteroid.gd").new()
	a._grow(sd, radius, knd)
	return a

func _grow(sd: int, radius: float, knd: String) -> void:
	seed_ = sd
	kind = knd
	rad = radius
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var stretch := rng.randf_range(1.0, 1.45)              # some are drawn out long
	var size := int(ceil(radius * 2.0 * stretch * 1.25)) + 6
	setup(size, size)
	# the outline: radius by angle (a few harmonics), then fine grain at the edge
	var harm := []
	for k in range(2, 7):
		harm.append([k, rng.randf_range(0.04, 0.2) / float(k - 1), rng.randf() * TAU])
	var grain := FastNoiseLite.new()
	grain.seed = sd
	grain.frequency = 0.09
	var veins := FastNoiseLite.new()
	veins.seed = sd + 17
	veins.frequency = 0.07
	veins.fractal_octaves = 2
	var blobs := FastNoiseLite.new()
	blobs.seed = sd + 31
	blobs.frequency = 0.11
	var c := Vector2(size, size) * 0.5
	var turn := rng.randf() * TAU
	var depth := PackedFloat32Array()
	depth.resize(size * size)
	for j in size:
		for i in size:
			var o := (Vector2(i + 0.5, j + 0.5) - c).rotated(-turn)
			o.x /= stretch
			var th := o.angle()
			var r := radius
			for hm in harm:
				r += radius * float(hm[1]) * cos(float(hm[0]) * th + float(hm[2]))
			r += grain.get_noise_2d(i, j) * 2.2
			var d := r - o.length()
			if d > 0.0:
				cells[j * size + i] = Defs.STONE
				depth[j * size + i] = d
	# craters: bites out of the edge
	for k2 in rng.randi_range(2, 4):
		var ca := rng.randf() * TAU
		var cr := radius * rng.randf_range(0.14, 0.3)
		var at := c + Vector2(cos(ca) * stretch, sin(ca)).rotated(turn) * radius * rng.randf_range(0.85, 1.0)
		for j2 in size:
			for i2 in size:
				if Vector2(i2 + 0.5, j2 + 0.5).distance_to(at) < cr:
					cells[j2 * size + i2] = 0
	# its matter, by how deep a cell lies and the noise there
	for k3 in size * size:
		if cells[k3] == 0:
			continue
		var i3 := k3 % size
		var j3 := k3 / size
		var d3 := depth[k3]
		var vn := absf(veins.get_noise_2d(i3, j3))          # (near zero along a vein)
		var bn := blobs.get_noise_2d(i3, j3)
		var m := Defs.STONE
		match knd:
			"icy":
				m = Defs.ICE if bn > -0.25 else Defs.STONE
				if d3 < 2.5:
					m = Defs.SNOW if rng.randf() < 0.6 else Defs.ICE
				elif vn < 0.05:
					m = Defs.FROST
			"metallic":
				m = Defs.DEEPSTONE if bn > -0.35 else Defs.STONE
				if d3 < 2.0:
					m = Defs.GRAVEL
				elif bn > 0.42 and d3 > radius * 0.3:
					m = Defs.STARIRON                      # (star iron: found nowhere else)
				elif vn < 0.045 and d3 > radius * 0.25:
					m = Defs.WISP
				elif vn < 0.08:
					m = Defs.COPPER
			_:
				if d3 < 2.5:
					m = Defs.GRAVEL if rng.randf() < 0.7 else Defs.STONE
				elif vn < 0.05:
					m = Defs.COPPER
				elif bn > 0.55:
					m = Defs.COAL
				elif bn < -0.62 and d3 > radius * 0.35:
					m = Defs.CRYSTAL
				elif bn > 0.48 and d3 > radius * 0.45:
					m = Defs.STARIRON                      # (a speck now and then in a stony one too)
		cells[k3] = m
		vars[k3] = rng.randi() & 3
	_trim()
	rebuild()
	omega = rng.randf_range(0.0006, 0.003) * (1.0 if rng.randf() < 0.5 else -1.0)
	ang = rng.randf() * TAU

## Shrink the grid to the cells it has (a margin of one).
func _trim() -> void:
	var i0 := w
	var j0 := h
	var i1 := -1
	var j1 := -1
	for k in w * h:
		if cells[k] != 0:
			i0 = mini(i0, k % w)
			i1 = maxi(i1, k % w)
			j0 = mini(j0, k / w)
			j1 = maxi(j1, k / w)
	if i1 < 0:
		return
	var nw := i1 - i0 + 3
	var nh := j1 - j0 + 3
	var oc := cells.duplicate()          # (packed arrays are shared by reference)
	var ov := vars.duplicate()
	var ow := w
	setup(nw, nh)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k2 := (j - j0 + 1) * nw + (i - i0 + 1)
			cells[k2] = oc[j * ow + i]
			vars[k2] = ov[j * ow + i]

## Rebuild after cells changed, keeping every remaining cell where it was in the world (the centre
## of mass, which `pos` is, moves with what was taken).
func settle_mass() -> void:
	var c0 := com
	rebuild()
	if mass > 0.0:
		pos += axis_x() * (com - c0).x + axis_y() * (com - c0).y
	rad = maxf(3.0, sqrt(mass / PI))
	dust = 0

## A new asteroid of the cells `idx` (indices into this one's grid), placed and moving where they
## were; they are taken out of this one.
func split_off(idx: PackedInt32Array) -> RefCounted:
	var i0 := w
	var j0 := h
	var i1 := -1
	var j1 := -1
	for k in idx:
		i0 = mini(i0, k % w)
		i1 = maxi(i1, k % w)
		j0 = mini(j0, k / w)
		j1 = maxi(j1, k / w)
	var b = load("res://scripts/asteroid.gd").new()
	b.kind = kind
	b.seed_ = seed_
	b.sect = sect
	b.touched = true
	b.setup(i1 - i0 + 3, j1 - j0 + 3)
	for k2 in idx:
		var nk: int = (k2 / w - j0 + 1) * b.w + (k2 % w - i0 + 1)
		b.cells[nk] = cells[k2]
		b.vars[nk] = vars[k2]
		take(k2)
	b.rebuild()
	b.ang = ang
	b.facing = facing
	# the same cells in the same places: its cell (i, j) is this one's (i + i0 - 1, j + j0 - 1)
	var off: Vector2 = Vector2(i0 - 1, j0 - 1) + b.com - com
	b.pos = pos + axis_x() * off.x + axis_y() * off.y
	var r: Vector2 = b.pos - pos
	b.vel = vel + Vector2(-r.y, r.x) * omega
	b.omega = omega
	b.rad = maxf(3.0, sqrt(b.mass / PI))
	return b

## Mass and centre of mass from the cells (an asteroid has no room inside and collides cell by cell,
## so none of the skiff's flood or outline is needed).
func rebuild() -> void:
	mass = 0.0
	var sum := Vector2.ZERO
	for k in w * h:
		if cells[k] != 0:
			mass += 1.0
			sum += Vector2(k % w + 0.5, k / w + 0.5)
	com = sum / maxf(mass, 0.001)

## a cell mined or crumbled away: gone from the grid and from the picture
func take(k: int) -> void:
	cells[k] = 0
	dust += 1
	touched = true
	if img != null:
		img.set_pixel(k % w, k / w, Color(0, 0, 0, 0))
		img_dirty = true

## the half-diagonal of its grid: no cell of it lies farther than this from its middle
func reach() -> float:
	return 0.5 * Vector2(w, h).length() + 1.0

## Its picture: each cell in its material's colour; cells that glow by themselves (ores, crystal)
## are marked by an alpha a hair under 1, which the lighting shader leaves unshaded.
func texture() -> ImageTexture:
	if img_dirty and tex != null and img != null:
		tex.update(img)
		img_dirty = false
	if not dirty and tex != null:
		return tex
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for j in h:
		for i in w:
			var m := cells[j * w + i]
			if m == 0:
				continue
			var c := Color.hex((Defs.PAL[m * 4 + (vars[j * w + i] & 3)] << 8) | 0xff)
			if Defs.SELF[m] != 0:
				c.a = 250.0 / 255.0
			img.set_pixel(i, j, c)
	if tex == null or tex.get_width() != w or tex.get_height() != h:
		tex = ImageTexture.create_from_image(img)
	else:
		tex.update(img)
	dirty = false
	img_dirty = false
	return tex

## How many cells it holds.
func count() -> int:
	var n := 0
	for v in cells:
		if v != 0:
			n += 1
	return n

## (a wreck's closed caches: mining and blasts leave those cells alone; a rock has none)
func guarded(_k: int) -> bool:
	return false

## Is the world point p inside one of its cells?
func solid_at(p: Vector2) -> bool:
	var b := to_body(p) + com
	var i := int(floor(b.x))
	var j := int(floor(b.y))
	return i >= 0 and j >= 0 and i < w and j < h and cells[j * w + i] != 0

## Saving: its own place and motion, and its cells.
func save() -> Dictionary:
	return {"seed": seed_, "kind": kind, "pos": [pos.x, pos.y], "ang": ang, "omega": omega, "vel": [vel.x, vel.y],
		"w": w, "h": h, "cells": Marshalls.raw_to_base64(cells), "vars": Marshalls.raw_to_base64(vars)}

static func from_save(d: Dictionary) -> RefCounted:
	var a = load("res://scripts/asteroid.gd").new()
	a.seed_ = int(d.get("seed", 0))
	a.kind = String(d.get("kind", "stony"))
	a.setup(int(d["w"]), int(d["h"]))
	var cs: PackedByteArray = Marshalls.base64_to_raw(String(d["cells"]))
	var vs: PackedByteArray = Marshalls.base64_to_raw(String(d["vars"]))
	if cs.size() != a.w * a.h or vs.size() != a.w * a.h:
		return null
	a.cells = cs
	a.vars = vs
	a.rebuild()
	var p: Array = d["pos"]
	a.pos = Vector2(float(p[0]), float(p[1]))
	a.ang = float(d.get("ang", 0.0))
	a.omega = float(d.get("omega", 0.0))
	var v: Array = d.get("vel", [0.0, 0.0])
	a.vel = Vector2(float(v[0]), float(v[1]))
	a.rad = maxf(3.0, sqrt(a.mass / PI))
	return a
