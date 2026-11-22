## Spell effects (user, 21 Nov: "a vfx overhaul for the spells... epic vfx"). A particle system of its own,
## drawn over the world in two layers: this node (normal blending: smoke, dust, rubble, the dark heart of a
## quake orb) and its child `glow` (additive: fire, sparks, halos, shockwaves, lightning, beams, a flash over
## the whole screen). Everything is drawn in whole game pixels (one world cell each at the play zoom), so it
## stays pixel art: halos are banded, rings and lines are runs of square pixels.
## What a spell looks like is DATA (`Defs.SPELL_FX`: colours, halo size and a style for each part: its
## projectile and trail, the cast at the staff, the impact); the styles live here, so a new spell needs only
## an entry. main.gd calls `cast`, `trail` (each tick a projectile flies), `impact`, `blast` (every
## explosion, a fireball's or a meteor's), `blink` and `mend`; `tick` runs with the game's ticks.
## Big moments also light the world (`game.lights`, while they burn) and shake the view (`game.shake`).
extends Node2D

enum {DOT, STREAK, GLOW, SMOKE, RING, SHARD, FLARE, BOLT, BEAM, RUNE, CHUNK}
const MAX := 2200

var game
var glow: Node2D                     # the additive layer
var stats := {}                      # (counts for the tests)

# particles, in parallel arrays (thousands of dictionaries would be slow)
var P := PackedVector2Array()        # where (world)
var V := PackedVector2Array()        # its velocity a tick (a BOLT: where it ends; a BEAM: which way is up)
var L := PackedInt32Array()          # ticks left
var LM := PackedInt32Array()         # ticks it had
var K := PackedByteArray()           # kind
var A := PackedByteArray()           # 1 glow layer (additive), 0 normal
var C0 := PackedColorArray()         # colour at birth...
var C1 := PackedColorArray()         # ...and at death (alpha fades with it)
var S0 := PackedFloat32Array()       # size at birth (cells)...
var S1 := PackedFloat32Array()       # ...and at death
var G := PackedFloat32Array()        # gravity (cells a tick per tick; negative rises)
var D := PackedFloat32Array()        # velocity kept each tick
var F := PackedFloat32Array()        # a number of its own (a rune's spin, a bolt's seed)

var _flashes := []                   # [pos, radius, colour, ticks left, ticks] lighting the world
var flash_col := Color(0, 0, 0)      # the whole screen, added (fades)
var flash_k := 0.0
var _glow_tex: ImageTexture
var _smoke_tex: ImageTexture
var _t := 0                          # ticks

func _ready() -> void:
	glow = Node2D.new()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = mat
	glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(glow)
	glow.draw.connect(_draw_glow)
	_glow_tex = _banded(16, 1.8, 5)
	_smoke_tex = _banded(12, 0.9, 4)

## a round soft spot in a few hard bands (pixel-art glow), white, alpha by distance from the middle
static func _banded(n: int, soft: float, bands: int) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), soft)
			a = ceilf(a * bands) / bands if a > 0.02 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func clear() -> void:
	_resize(0)
	_flashes.clear()
	flash_k = 0.0

func count() -> int:
	return P.size()

## one particle
func spawn(kind: int, p: Vector2, v: Vector2, life: int, c0: Color, c1: Color, s0: float, s1: float, add := true, grav := 0.0, drag := 1.0, f := 0.0) -> void:
	if P.size() >= MAX:
		return
	P.append(p)
	V.append(v)
	L.append(life)
	LM.append(life)
	K.append(kind)
	A.append(1 if add else 0)
	C0.append(c0)
	C1.append(c1)
	S0.append(s0)
	S1.append(s1)
	G.append(grav)
	D.append(drag)
	F.append(f)

## (the last particle takes its place)
func _kill(i: int) -> void:
	var n := P.size() - 1
	if i != n:
		P[i] = P[n]
		V[i] = V[n]
		L[i] = L[n]
		LM[i] = LM[n]
		K[i] = K[n]
		A[i] = A[n]
		C0[i] = C0[n]
		C1[i] = C1[n]
		S0[i] = S0[n]
		S1[i] = S1[n]
		G[i] = G[n]
		D[i] = D[n]
		F[i] = F[n]
	_resize(n)

## (packed arrays are values: each is resized by name)
func _resize(n: int) -> void:
	P.resize(n)
	V.resize(n)
	L.resize(n)
	LM.resize(n)
	K.resize(n)
	A.resize(n)
	C0.resize(n)
	C1.resize(n)
	S0.resize(n)
	S1.resize(n)
	G.resize(n)
	D.resize(n)
	F.resize(n)

## a light in the world for a while (it fades), and a flash over the screen
func light(p: Vector2, r: float, col: Color, ticks: int) -> void:
	_flashes.append([p, r, col, ticks, ticks])

func screen_flash(col: Color, k: float) -> void:
	if k > flash_k:
		flash_col = col
		flash_k = k

func _up(p: Vector2) -> Vector2:
	return -game.basis_d(atan2(p.y, p.x))

## up (away from the planet's middle) at p
static func _up_of(p: Vector2) -> Vector2:
	return p.normalized() if p.length_squared() > 0.0 else Vector2.UP

func _rand_dir() -> Vector2:
	return Vector2.from_angle(randf() * TAU)

static func fx(id: String) -> Dictionary:
	return Defs.SPELL_FX.get(id, {})

# ------------------------------------------------------------------ ticking ---

## everything moved by d (space's origin followed you: space.gd `_shift`)
func shift(d: Vector2) -> void:
	for i in P.size():
		P[i] += d
		if K[i] == BOLT:
			V[i] += d
	for f in _flashes:
		f[0] += d

func tick() -> void:
	_t += 1
	var t0 := Time.get_ticks_usec()
	var down: Vector2 = game.basis_d(atan2(game.player.pos.y, game.player.pos.x))
	var i := P.size() - 1
	while i >= 0:
		var l := L[i] - 1
		if l <= 0:
			_kill(i)
			i -= 1
			continue
		L[i] = l
		var k := K[i]
		if k != BOLT and k != BEAM and k != RUNE:
			var v := V[i] + down * G[i]
			v *= D[i]
			V[i] = v
			P[i] = P[i] + v
		i -= 1
	for j in range(_flashes.size() - 1, -1, -1):
		var fl: Array = _flashes[j]
		fl[3] = int(fl[3]) - 1
		if int(fl[3]) <= 0:
			_flashes.remove_at(j)
			continue
		var k2 := float(fl[3]) / float(fl[4])
		if game.lights.size() < 28:
			game.lights.append([fl[0], float(fl[1]) * (0.4 + 0.6 * k2), (fl[2] as Color) * k2])
	flash_k = maxf(0.0, flash_k * 0.86 - 0.01)
	game.prof_add("spell effects", Time.get_ticks_usec() - t0)

func _process(_dt: float) -> void:
	queue_redraw()
	glow.queue_redraw()

func _showing() -> bool:
	return game != null and game.state != "title" and game.state != "loading" and game.state != "error" and game.state != "map"

# ------------------------------------------------------------- spell parts ---

## casting: a flash at the staff's tip, sparks out along the aim; the heavy spells draw a circle of runes
## round the caster first
func cast(id: String, at: Vector2, dir: Vector2, m = null) -> void:
	var f := fx(id)
	if f.is_empty():
		return
	var gc: Color = f["glow"]
	var cc: Color = f["core"]
	var d := dir.normalized()
	spawn(GLOW, at, Vector2.ZERO, 9, cc, gc * Color(1, 1, 1, 0), 3.0, 7.0)
	spawn(RING, at, Vector2.ZERO, 8, cc, gc * Color(1, 1, 1, 0), 1.0, 6.0)
	for k in 8:
		var sd := d.rotated(randf_range(-0.6, 0.6)) * randf_range(0.8, 2.4)
		spawn(STREAK, at, sd, 6 + randi() % 6, cc, gc * Color(1, 1, 1, 0), 2.0, 1.0, true, 0.0, 0.86)
	match String(f.get("cast", "flick")):
		"rune":
			var c: Vector2 = m.pos if m != null else at
			spawn(RUNE, c, Vector2.ZERO, 34, cc, gc * Color(1, 1, 1, 0), 13.0, 17.0, true, 0.0, 1.0, 0.09 * (1.0 if randf() < 0.5 else -1.0))
			spawn(RING, c, Vector2.ZERO, 16, gc, gc * Color(1, 1, 1, 0), 4.0, 20.0)
			for k2 in 18:
				var o := _rand_dir() * randf_range(14.0, 20.0)
				spawn(DOT, c + o, -o * 0.06, 14 + randi() % 8, cc, gc * Color(1, 1, 1, 0), 1.0, 1.0)
			light(c, 40.0, gc * 1.2, 20)
		"burst":
			for k3 in 6:
				spawn(DOT, at, d.rotated(randf_range(-0.9, 0.9)) * randf_range(0.4, 1.4), 10 + randi() % 8, cc, gc * Color(1, 1, 1, 0), 2.0, 1.0, true, -0.02, 0.9)
			light(at, 26.0, gc, 8)
		_:
			light(at, 16.0, gc, 5)
	stats["casts"] = int(stats.get("casts", 0)) + 1

## a projectile in flight leaves a trail of its kind behind it
func trail(pr: Dictionary) -> void:
	var f := fx(String(pr["type"]))
	if f.is_empty():
		return
	var p: Vector2 = pr["pos"]
	var v: Vector2 = pr["vel"]
	var gc: Color = f["glow"]
	var cc: Color = f["core"]
	var clear := Color(gc.r, gc.g, gc.b, 0.0)
	match String(f.get("trail", "")):
		"spark":
			for k in 2:
				spawn(STREAK, p - v * randf() * 0.6, -v * 0.1 + _rand_dir() * randf_range(0.3, 1.1), 5 + randi() % 6, cc, clear, 1.5, 1.0, true, 0.04, 0.88)
			if randf() < 0.25:
				spawn(BOLT, p, p - v * 2.2 + _rand_dir() * 3.0, 3, cc, clear, 1.0, 1.0, true, 0.0, 1.0, randf() * 1000.0)
		"flame":
			for k in 5:
				spawn(DOT, p + _rand_dir() * randf() * 2.5, -v * 0.15 + _rand_dir() * 0.3, 12 + randi() % 12, Color(1, 0.95, 0.6), Color(0.9, 0.15, 0.02, 0.0), 3.5, 1.0, true, -0.03, 0.92)
			spawn(SMOKE, p - v * 0.8, _up(p) * 0.12 + _rand_dir() * 0.1, 40 + randi() % 30, Color(0.22, 0.18, 0.17, 0.55), Color(0.3, 0.28, 0.28, 0.0), 2.0, 7.0, false, -0.004, 0.97)
			if randf() < 0.35:
				spawn(STREAK, p, _rand_dir() * randf_range(0.5, 1.4) - v * 0.2, 14 + randi() % 10, Color(1, 0.8, 0.3), Color(1, 0.3, 0.05, 0.0), 1.0, 1.0, true, 0.05, 0.95)
		"frost":
			spawn(DOT, p + _rand_dir() * randf() * 1.5, -v * 0.05 + _rand_dir() * 0.15, 16 + randi() % 14, Color(0.95, 1, 1), clear, 1.0, 1.0, true, 0.01, 0.96)
			if _t % 2 == 0:
				spawn(SMOKE, p, _rand_dir() * 0.08, 26, Color(0.6, 0.85, 1.0, 0.22), Color(0.6, 0.85, 1.0, 0.0), 2.0, 5.0, true, 0.0, 0.97)
			if randf() < 0.18:
				spawn(FLARE, p + _rand_dir() * 2.0, Vector2.ZERO, 10, Color(1, 1, 1), clear, 2.0, 0.0)
		"water":
			for k in 2:
				spawn(DOT, p + _rand_dir(), -v * 0.1 + _rand_dir() * 0.35, 18 + randi() % 10, Color(0.6, 0.8, 1.0, 0.95), Color(0.2, 0.45, 0.95, 0.0), 1.0, 1.0, false, 0.06, 0.98)
			if randf() < 0.3:
				spawn(DOT, p + _rand_dir() * 2.0, _up(p) * 0.1, 22, Color(0.85, 0.95, 1.0, 0.8), Color(0.85, 0.95, 1.0, 0.0), 1.0, 1.0, true, -0.005, 0.98)
		"rocks":
			if _t % 2 == 0:
				spawn(SMOKE, p, _rand_dir() * 0.15, 36, Color(0.32, 0.24, 0.38, 0.5), Color(0.25, 0.2, 0.25, 0.0), 2.0, 6.0, false, -0.002, 0.96)
			spawn(DOT, p + _rand_dir() * 3.0, _rand_dir() * 0.3, 12, gc, clear, 1.0, 1.0, true, 0.0, 0.9)
			if randf() < 0.3:
				spawn(CHUNK, p + _rand_dir() * 2.0, -v * 0.2 + _rand_dir() * 0.4, 30, Color(0.4, 0.33, 0.38), Color(0.3, 0.25, 0.3, 0.0), 1.0, 1.0, false, 0.07, 0.99)
		"star":
			for k in 3:
				spawn(DOT, p - v * randf() * 1.5 + _rand_dir(), _rand_dir() * 0.3, 18 + randi() % 16, Color(1, 1, 0.9), Color(1.0, 0.55, 0.15, 0.0), 1.5, 1.0, true, 0.01, 0.95)
			spawn(STREAK, p, -v * 0.5 + _rand_dir() * 0.4, 10, cc, clear, 2.0, 1.0, true, 0.0, 0.9)
			if randf() < 0.3:
				spawn(FLARE, p + _rand_dir() * 4.0, Vector2.ZERO, 12, Color(1, 1, 0.9), clear, 3.0, 0.0)
		"ember":
			if randf() < 0.6:
				spawn(DOT, p, _rand_dir() * 0.25 - v * 0.1, 10 + randi() % 8, cc, clear, 1.0, 1.0, true, 0.0, 0.92)

## a projectile lands: each style its own burst (an explosion's own bang is `blast`)
func impact(type: String, p: Vector2, hit: bool) -> void:
	var f := fx(type)
	if f.is_empty():
		return
	var gc: Color = f["glow"]
	var cc: Color = f["core"]
	var clear := Color(gc.r, gc.g, gc.b, 0.0)
	match String(f.get("impact", "")):
		"zap":
			spawn(GLOW, p, Vector2.ZERO, 10, Color(1, 1, 1), clear, 10.0, 2.0)
			spawn(RING, p, Vector2.ZERO, 10, cc, clear, 1.0, 13.0)
			for k in 9:
				spawn(BOLT, p, p + _rand_dir() * randf_range(7.0, 17.0), 5 + randi() % 5, cc, clear, 1.0, 1.0, true, 0.0, 1.0, randf() * 1000.0)
			for k2 in 22:
				spawn(STREAK, p, _rand_dir() * randf_range(0.8, 3.0), 7 + randi() % 9, cc, clear, 1.5, 1.0, true, 0.06, 0.88)
			light(p, 38.0, gc * 1.4, 10)
			screen_flash(Color(0.5, 0.45, 0.25), 0.08)
		"shatter":
			spawn(GLOW, p, Vector2.ZERO, 16, Color(0.95, 1, 1), clear, 14.0, 3.0)
			spawn(RING, p, Vector2.ZERO, 14, Color(0.9, 1, 1), clear, 2.0, 22.0)
			spawn(RING, p, Vector2.ZERO, 20, Color(0.55, 0.85, 1.0), clear, 1.0, 14.0)
			for k in 28:
				var sd := _rand_dir() * randf_range(0.8, 2.8)
				spawn(SHARD, p, sd, 20 + randi() % 16, Color(0.9, 1.0, 1.0), Color(0.5, 0.8, 1.0, 0.0), 4.5, 2.0, k % 2 == 0, 0.07, 0.95)
			for k2 in 12:
				spawn(FLARE, p + _rand_dir() * randf_range(2.0, 12.0), Vector2.ZERO, 14 + randi() % 10, Color(1, 1, 1), clear, 3.0, 0.0)
			for k3 in 6:
				spawn(SMOKE, p + _rand_dir() * 4.0, _rand_dir() * 0.2, 50, Color(0.7, 0.9, 1.0, 0.25), Color(0.7, 0.9, 1.0, 0.0), 4.0, 11.0, true, -0.003, 0.96)
			light(p, 34.0, gc * 1.2, 14)
			screen_flash(Color(0.3, 0.5, 0.7), 0.12)
		"splash":
			spawn(RING, p, Vector2.ZERO, 14, Color(0.7, 0.85, 1.0), clear, 2.0, 19.0)
			spawn(RING, p, Vector2.ZERO, 20, Color(0.4, 0.65, 1.0), clear, 1.0, 12.0)
			spawn(GLOW, p, Vector2.ZERO, 12, gc, clear, 11.0, 2.0)
			var up := _up(p)
			for k in 30:
				spawn(DOT, p, (_rand_dir() * 0.7 + up * 0.9) * randf_range(0.6, 2.4), 24 + randi() % 14, Color(0.65, 0.85, 1.0), Color(0.25, 0.5, 1.0, 0.0), randf_range(1.0, 2.0), 1.0, false, 0.08, 0.98)
			for k4 in 16:
				# the crown: a column of drops thrown straight up
				spawn(DOT, p + up.orthogonal() * randf_range(-3.0, 3.0), (up * randf_range(1.6, 3.2) + _rand_dir() * 0.3), 30 + randi() % 12, Color(0.8, 0.92, 1.0), Color(0.3, 0.55, 1.0, 0.0), 1.5, 1.0, false, 0.1, 0.99)
			for k2 in 14:
				spawn(DOT, p + _rand_dir() * 4.0, _rand_dir() * 0.3, 20, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0), 1.0, 1.0, true, 0.0, 0.92)
			light(p, 32.0, gc * 1.2, 10)
		"quake":
			# (the blast itself is `blast`: this is the rest of a quake's ruin)
			spawn(RING, p, Vector2.ZERO, 26, Color(0.85, 0.7, 1.0), Color(0.45, 0.2, 0.8, 0.0), 6.0, 52.0)
			spawn(RING, p, Vector2.ZERO, 18, Color(1, 1, 1), clear, 3.0, 34.0)
			spawn(GLOW, p, Vector2.ZERO, 22, Color(0.9, 0.75, 1.0), clear, 26.0, 8.0)
			for k in 7:
				spawn(BOLT, p, p + _rand_dir() * randf_range(16.0, 30.0), 10 + randi() % 6, Color(0.95, 0.85, 1.0), clear, 1.0, 1.0, true, 0.0, 1.0, randf() * 1000.0)
			for k2 in 34:
				spawn(CHUNK, p + _rand_dir() * 4.0, (_rand_dir() + _up(p) * 0.8) * randf_range(0.8, 2.8), 50 + randi() % 30, Color(0.45, 0.38, 0.42), Color(0.3, 0.25, 0.28, 0.0), randf_range(1.0, 2.0), 1.0, false, 0.08, 0.99)
			for k3 in 14:
				spawn(SMOKE, p + _rand_dir() * 8.0, _rand_dir() * 0.25 + _up(p) * 0.1, 90 + randi() % 50, Color(0.35, 0.28, 0.33, 0.6), Color(0.3, 0.26, 0.3, 0.0), 5.0, 18.0, false, -0.002, 0.97)
			light(p, 70.0, gc * 1.4, 26)
			screen_flash(Color(0.5, 0.3, 0.8), 0.3)
		"nova":
			# a falling star: a pillar of light, a blinding flash, sparks everywhere
			spawn(BEAM, p, _up(p), 30, Color(1, 1, 0.95), Color(1.0, 0.7, 0.3, 0.0), 9.0, 200.0)
			spawn(GLOW, p, Vector2.ZERO, 28, Color(1, 1, 1), Color(1.0, 0.6, 0.2, 0.0), 40.0, 10.0)
			spawn(RING, p, Vector2.ZERO, 22, Color(1, 1, 0.9), clear, 4.0, 60.0)
			spawn(RING, p, Vector2.ZERO, 30, Color(1.0, 0.75, 0.35), clear, 2.0, 42.0)
			for k in 44:
				spawn(STREAK, p, _rand_dir() * randf_range(1.0, 4.2), 16 + randi() % 18, Color(1, 1, 0.85), Color(1, 0.5, 0.1, 0.0), 2.0, 1.0, true, 0.05, 0.93)
			for k2 in 16:
				spawn(FLARE, p + _rand_dir() * randf_range(4.0, 34.0), Vector2.ZERO, 16 + randi() % 20, Color(1, 1, 0.9), clear, 5.0, 0.0)
			light(p, 90.0, Color(1.6, 1.3, 0.9), 30)
			screen_flash(Color(1.0, 0.85, 0.6), 0.55)
	stats["impacts"] = int(stats.get("impacts", 0)) + 1
	stats["last_impact"] = type

## an explosion (a fireball's, a quake orb's, a falling star's, a meteor's, a lava bomb's): `kind` 1 fire, 2 a
## crushing blow. A fireball of light that swells and dies, a shockwave, fire billowing out and up, smoke
## that hangs about, embers raining down
func blast(p: Vector2, r: float, kind: int) -> void:
	var up := _up(p)
	var hot := kind != 2
	var core := Color(1, 1, 0.85) if hot else Color(0.95, 0.9, 1.0)
	var mid := Color(1.0, 0.55, 0.15) if hot else Color(0.6, 0.4, 0.9)
	var clear := Color(mid.r, mid.g, mid.b, 0.0)
	spawn(GLOW, p, Vector2.ZERO, 22, mid, clear, r * 2.0, r * 3.2)
	spawn(GLOW, p, Vector2.ZERO, 16, core, clear, r * 1.4, r * 2.2)
	spawn(GLOW, p, Vector2.ZERO, 8, Color(1, 1, 1), clear, r * 1.0, r * 0.3)
	spawn(RING, p, Vector2.ZERO, 14, core, clear, r * 0.5, r * 2.8)
	spawn(RING, p, Vector2.ZERO, 22, mid, clear, r * 0.3, r * 1.9)
	if hot:
		# the fire climbs in a column over it
		for kc in int(clampf(r * 1.2, 6.0, 30.0)):
			spawn(DOT, p + up.orthogonal() * randf_range(-r * 0.3, r * 0.3), up * randf_range(0.4, 1.3) + _rand_dir() * 0.15, 18 + randi() % 16, Color(1, 0.95, 0.7), Color(0.8, 0.12, 0.02, 0.0), randf_range(2.5, 4.0), 1.0, true, -0.02, 0.95)
	var n := int(clampf(r * 5.0, 24.0, 90.0))
	for k in n:
		var dv := _rand_dir() * randf_range(0.3, 1.0) * (0.25 + r * 0.06)
		if hot:
			spawn(DOT, p + _rand_dir() * randf() * r * 0.4, dv + up * 0.25, 14 + randi() % 18, Color(1, 0.95, 0.6), Color(0.85, 0.12, 0.02, 0.0), randf_range(2.0, 3.5), 1.0, true, -0.025, 0.9)
		else:
			spawn(DOT, p + _rand_dir() * randf() * r * 0.4, dv, 14 + randi() % 12, core, clear, 2.0, 1.0, true, 0.0, 0.9)
	for k2 in int(clampf(r * 0.9, 5.0, 22.0)):
		spawn(SMOKE, p + _rand_dir() * randf() * r * 0.6, _rand_dir() * 0.2 + up * randf_range(0.08, 0.22), 70 + randi() % 60,
			Color(0.2, 0.17, 0.16, 0.6) if hot else Color(0.33, 0.28, 0.32, 0.6), Color(0.32, 0.3, 0.3, 0.0), r * 0.4, r * 1.3, false, -0.002, 0.975)
	for k3 in int(clampf(r * 2.2, 14.0, 44.0)):
		spawn(STREAK, p, (_rand_dir() + up * 0.6) * randf_range(0.8, 2.6), 24 + randi() % 24, Color(1, 0.85, 0.4) if hot else core, Color(1, 0.3, 0.05, 0.0) if hot else clear, 1.0, 1.0, true, 0.07, 0.97)
	light(p, r * 5.0, Color(1.6, 0.9, 0.4) if hot else Color(1.0, 0.7, 1.4), int(10 + r))
	screen_flash(Color(1.0, 0.6, 0.25) if hot else Color(0.6, 0.4, 0.9), clampf(r / 60.0, 0.05, 0.3))
	stats["blasts"] = int(stats.get("blasts", 0)) + 1

## a blink: drawn in where you were (a ring of sparks sucked into nothing), a streak of light along the way,
## a burst where you come out
func blink(from: Vector2, to: Vector2) -> void:
	var f := fx("blink")
	var gc: Color = f.get("glow", Color(0.5, 0.9, 1.0))
	var clear := Color(gc.r, gc.g, gc.b, 0.0)
	for k in 26:
		var o := _rand_dir() * randf_range(9.0, 15.0)
		spawn(DOT, from + o, -o / 10.0, 10, Color(1, 1, 1), clear, 1.0, 1.0, true, 0.0, 1.0)
	spawn(GLOW, from, Vector2.ZERO, 12, gc, clear, 2.0, 12.0)
	var n := int(from.distance_to(to) / 2.0)
	for k2 in n:
		var q := from.lerp(to, float(k2) / maxf(1.0, float(n)))
		spawn(DOT, q + _rand_dir() * randf(), _rand_dir() * 0.15, 14 + randi() % 16, Color(0.9, 1, 1), clear, 1.0, 1.0, true, 0.0, 0.95)
	spawn(BOLT, from, to, 6, Color(0.9, 1, 1), clear, 1.0, 1.0, true, 0.0, 1.0, randf() * 1000.0)
	spawn(RING, to, Vector2.ZERO, 12, Color(0.9, 1, 1), clear, 3.0, 16.0)
	spawn(GLOW, to, Vector2.ZERO, 12, Color(1, 1, 1), clear, 12.0, 2.0)
	for k3 in 16:
		spawn(STREAK, to, _rand_dir() * randf_range(0.8, 2.2), 8 + randi() % 8, Color(1, 1, 1), clear, 1.5, 1.0, true, 0.0, 0.88)
	light(to, 32.0, gc * 1.3, 12)
	screen_flash(Color(0.3, 0.6, 0.8), 0.1)
	stats["blinks"] = int(stats.get("blinks", 0)) + 1

## mending: a ring of runes at your feet, motes of light rising round you, a pulse going out
func mend(m) -> void:
	var f := fx("mend")
	var gc: Color = f.get("glow", Color(0.5, 1.0, 0.6))
	var clear := Color(gc.r, gc.g, gc.b, 0.0)
	var up := _up(m.pos)
	var feet: Vector2 = m.pos - up * 8.0
	spawn(RUNE, feet, Vector2.ZERO, 60, Color(0.85, 1, 0.85), clear, 11.0, 13.0, true, 0.0, 1.0, 0.06)
	for k in 3:
		spawn(RING, m.pos, Vector2.ZERO, 16 + k * 8, Color(0.85, 1, 0.85), clear, 2.0 + k * 2.0, 18.0 + k * 6.0)
	for k2 in 36:
		var o := _rand_dir() * randf_range(3.0, 11.0)
		spawn(DOT, feet + o, up * randf_range(0.2, 0.55) + o.orthogonal() * 0.03, 30 + randi() % 30, Color(0.9, 1, 0.9), clear, 1.0, 1.0, true, 0.0, 0.99)
	spawn(FLARE, m.pos, Vector2.ZERO, 20, Color(1, 1, 1), clear, 7.0, 0.0)
	light(m.pos, 34.0, gc * 1.2, 40)
	stats["mends"] = int(stats.get("mends", 0)) + 1

# ------------------------------------------------------------------ drawing ---

func _draw() -> void:
	if not _showing():
		return
	var t0 := Time.get_ticks_usec()
	_draw_layer(self, 0)
	# the dark heart of a quake orb (normal blending: it's dark)
	for pr in game.projs:
		var f := fx(String(pr["type"]))
		if not f.is_empty() and String(f.get("trail", "")) == "rocks":
			var sp: Vector2 = game.world_to_screen(pr["pos"]).floor()
			_disc(self, sp, 2.5 / game.zoom, Color(0.12, 0.05, 0.18))
	game.prof_add("spell effects", Time.get_ticks_usec() - t0)

func _draw_glow() -> void:
	if not _showing():
		return
	var t0 := Time.get_ticks_usec()
	_draw_layer(glow, 1)
	_draw_projectiles()
	if flash_k > 0.01:
		var fc := flash_col * flash_k
		fc.a = 1.0
		glow.draw_rect(Rect2(0, 0, game.VW, game.VH), fc)
	game.prof_add("spell effects", Time.get_ticks_usec() - t0)

## the flying spells themselves (each by its style), on the glow layer
func _draw_projectiles() -> void:
	var z: float = game.zoom
	for pr in game.projs:
		var f := fx(String(pr["type"]))
		if f.is_empty():
			continue
		var p: Vector2 = pr["pos"]
		var v: Vector2 = pr["vel"]
		var sp: Vector2 = game.world_to_screen(p).floor()
		var gc: Color = f["glow"]
		var cc: Color = f["core"]
		var pulse := 0.85 + 0.15 * sin(float(_t + int(pr["life"])) * 0.7)
		var gr := float(f.get("glow_r", 8.0)) * pulse / z
		_halo(glow, sp, gr * 2.3, gc * Color(1, 1, 1, 0.22))
		_halo(glow, sp, gr, gc * Color(1, 1, 1, 0.95))
		_halo(glow, sp, gr * 0.45, cc)
		var tail: Vector2 = game.world_to_screen(p - v * 2.0) - sp
		match String(f.get("trail", "")):
			"spark":
				# crackling: a jagged bolt behind it that jumps every frame
				_bolt(glow, sp, (sp + tail * 2.2).floor(), gc, float(_t) * 3.1 + float(int(pr["life"])))
				_line(glow, sp, sp + tail, cc)
				_disc(glow, sp, 1.5 / z, cc)
				_flare(glow, sp, 4.0 / z * pulse, Color(1, 1, 1))
			"flame":
				var j := Vector2(randf() - 0.5, randf() - 0.5) * 1.5
				_disc(glow, sp + j, 4.5 / z, Color(0.95, 0.32, 0.06))
				_disc(glow, sp + j * 0.5, 3.0 / z, Color(1.0, 0.7, 0.2))
				_disc(glow, sp, 1.6 / z, Color(1, 1, 0.85))
				for k in 4:
					# tongues of flame licking back along its path
					var tp: Vector2 = game.world_to_screen(p - v.normalized() * randf_range(3.0, 7.0) + _rand_dir() * 2.0).floor()
					glow.draw_rect(Rect2(tp, Vector2.ONE * 2.0), Color(1.0, 0.55, 0.12))
			"frost":
				var d := v.normalized()
				var a: Vector2 = game.world_to_screen(p + d * 5.0).floor()
				var b: Vector2 = game.world_to_screen(p - d * 6.0).floor()
				var o2: Vector2 = game.world_to_screen(p + d.orthogonal() * 2.5).floor()
				var o3: Vector2 = game.world_to_screen(p - d.orthogonal() * 2.5).floor()
				_line(glow, b, a, Color(0.6, 0.9, 1.0))
				_line(glow, o3, o2, Color(0.7, 0.95, 1.0))
				_disc(glow, sp, 1.5 / z, Color(0.85, 1, 1))
				glow.draw_rect(Rect2(a, Vector2.ONE), Color(1, 1, 1))
				_flare(glow, sp, 3.0 / z * pulse, Color(1, 1, 1))
			"water":
				var w := Vector2(sin(float(_t) * 0.5), cos(float(_t) * 0.6)) * 0.4
				_disc(glow, sp + w, 3.5 / z, Color(0.2, 0.45, 1.0))
				_disc(glow, sp, 2.2 / z, Color(0.55, 0.82, 1.0))
				glow.draw_rect(Rect2(sp + Vector2(-1, -1), Vector2.ONE), Color(1, 1, 1))
			"rocks":
				_ring(glow, sp, 3.5 / z, Color(0.7, 0.45, 1.0))
				for k in 3:
					var o := Vector2.from_angle(float(_t) * 0.25 + k * TAU / 3.0) * (5.0 / z)
					glow.draw_rect(Rect2((sp + o).floor(), Vector2.ONE * 2.0), Color(0.6, 0.45, 0.7))
			"star":
				# a long tapering tail of light behind it, and a four-pointed glint
				var tl: Vector2 = game.world_to_screen(p - v * 7.0) - sp
				_line(glow, sp, sp + tl, Color(1.0, 0.6, 0.2) * Color(1, 1, 1, 0.6))
				_line(glow, sp, sp + tl * 0.55, Color(1.0, 0.85, 0.5))
				_line(glow, sp, sp + tl * 0.25, Color(1, 1, 0.9))
				_disc(glow, sp, 2.0 / z, Color(1, 1, 0.9))
				_flare(glow, sp, 6.0 / z * pulse, Color(1, 1, 0.9))
			_:
				_disc(glow, sp, 1.0 / z, cc)

## every particle of one layer
func _draw_layer(ci: CanvasItem, add: int) -> void:
	var z: float = game.zoom
	var vw := float(game.VW) + 40.0
	var vh := float(game.VH) + 40.0
	# (one transform for every particle: world_to_screen per particle worked out the view each time)
	var xf: Transform2D = game.screen_xf()
	var affine: bool = game.screen_xf_ok()
	for i in P.size():
		if A[i] != add:
			continue
		var sp: Vector2 = xf * P[i] if affine else game.world_to_screen(P[i])
		var k := K[i]
		if k != BEAM and k != BOLT and (sp.x < -40.0 or sp.y < -40.0 or sp.x > vw or sp.y > vh):
			continue
		var t := 1.0 - float(L[i]) / float(LM[i])
		var c := C0[i].lerp(C1[i], t)
		var s := lerpf(S0[i], S1[i], t) / z
		sp = sp.floor()
		match k:
			DOT:
				var n := maxf(1.0, roundf(s))
				ci.draw_rect(Rect2(sp - Vector2(floorf(n * 0.5), floorf(n * 0.5)), Vector2(n, n)), c)
			CHUNK:
				var n2 := maxf(1.0, roundf(s))
				ci.draw_rect(Rect2(sp, Vector2(n2, n2)), c)
				ci.draw_rect(Rect2(sp, Vector2(n2, 1.0)), c.lightened(0.25))
			STREAK:
				var tail: Vector2 = (xf * (P[i] - V[i] * maxf(1.0, s)) if affine else game.world_to_screen(P[i] - V[i] * maxf(1.0, s))) - sp
				_line(ci, sp, sp + tail, c)
			SHARD:
				var dv := V[i].normalized() * s * 0.5
				var a: Vector2 = game.world_to_screen(P[i] + dv)
				var b: Vector2 = game.world_to_screen(P[i] - dv)
				_line(ci, b.floor(), a.floor(), c)
			GLOW:
				_halo(ci, sp, s, c)
			SMOKE:
				ci.draw_texture_rect(_smoke_tex, Rect2(sp - Vector2(s, s), Vector2(s, s) * 2.0), false, c)
			RING:
				_ring(ci, sp, s, c)
			FLARE:
				_flare(ci, sp, s * (1.0 - t * 0.6) * (0.7 + 0.3 * sin(float(_t + i) * 0.9)), c)
			BOLT:
				_bolt(ci, sp, game.world_to_screen(V[i]).floor(), c, F[i] + float(_t / 2))
			BEAM:
				_beam(ci, P[i], V[i], s, lerpf(S1[i], S1[i] * 0.6, t) / z, c)
			RUNE:
				_rune(ci, sp, s, c, F[i] * float(LM[i] - L[i]))

## a soft halo of radius r (banded: pixel-art glow)
func _halo(ci: CanvasItem, sp: Vector2, r: float, c: Color) -> void:
	if r < 0.6:
		return
	var rr := roundf(r)
	ci.draw_texture_rect(_glow_tex, Rect2(sp - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, c)

## a filled disc of whole pixels
func _disc(ci: CanvasItem, sp: Vector2, r: float, c: Color) -> void:
	var ri := int(ceil(r))
	for y in range(-ri, ri + 1):
		var hw := floorf(sqrt(maxf(0.0, r * r - float(y * y)) ) + 0.35)
		if hw < 0.0:
			continue
		ci.draw_rect(Rect2(sp.x - hw, sp.y + y, hw * 2.0 + 1.0, 1.0), c)

## a ring of whole pixels (one around), drawn as an arc past the size where that gets costly
func _ring(ci: CanvasItem, sp: Vector2, r: float, c: Color) -> void:
	if r < 1.0:
		ci.draw_rect(Rect2(sp, Vector2.ONE), c)
		return
	if r > 70.0:
		ci.draw_arc(sp + Vector2(0.5, 0.5), r, 0.0, TAU, 96, c, 1.0)
		return
	var n := int(ceil(TAU * r * 0.9))
	var last := Vector2(1e9, 0)
	for k in n:
		var q := (sp + Vector2.from_angle(TAU * float(k) / float(n)) * r).floor()
		if q != last:
			ci.draw_rect(Rect2(q, Vector2.ONE), c)
			last = q

## a line of whole pixels
func _line(ci: CanvasItem, a: Vector2, b: Vector2, c: Color) -> void:
	var d := b - a
	var n := int(maxf(absf(d.x), absf(d.y)))
	if n <= 0:
		ci.draw_rect(Rect2(a.floor(), Vector2.ONE), c)
		return
	n = mini(n, 120)
	for k in n + 1:
		ci.draw_rect(Rect2((a + d * (float(k) / float(n))).floor(), Vector2.ONE), c)

## a four-pointed glint
func _flare(ci: CanvasItem, sp: Vector2, r: float, c: Color) -> void:
	var ri := maxf(1.0, roundf(r))
	ci.draw_rect(Rect2(sp.x - ri, sp.y, ri * 2.0 + 1.0, 1.0), c * Color(1, 1, 1, 0.75))
	ci.draw_rect(Rect2(sp.x, sp.y - ri, 1.0, ri * 2.0 + 1.0), c * Color(1, 1, 1, 0.75))
	ci.draw_rect(Rect2(sp - Vector2(1, 1), Vector2(3, 3)), c * Color(1, 1, 1, 0.5))
	ci.draw_rect(Rect2(sp, Vector2.ONE), Color(1, 1, 1, c.a))

## a jagged bolt of lightning from a to b (it jumps about every other tick), with a fainter fork
func _bolt(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, sd: float) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(sd * 7919.0)
	var d := b - a
	var nrm := d.orthogonal().normalized()
	var n := clampi(int(d.length() / 4.0), 2, 12)
	var prev := a
	var mid := a
	for k in range(1, n + 1):
		var q := a + d * (float(k) / float(n))
		if k < n:
			q += nrm * r.randf_range(-1.0, 1.0) * minf(4.0, d.length() * 0.15)
		_line(ci, prev, q, c)
		if k == n / 2:
			mid = q
		prev = q
	if d.length() > 10.0:
		var fe := mid + (d * 0.4).rotated(r.randf_range(-0.9, 0.9))
		_line(ci, mid, fe, c * Color(1, 1, 1, 0.55))

## a pillar of light rising from p (world) along `up`, w wide and h tall (pixels), brightest at its foot
func _beam(ci: CanvasItem, p: Vector2, up: Vector2, w: float, h: float, c: Color) -> void:
	var a: Vector2 = game.world_to_screen(p)
	var b: Vector2 = game.world_to_screen(p + up * h * game.zoom)
	var d := b - a
	var nrm := d.orthogonal().normalized()
	# three bands, the outer ones faint, each narrowing to nothing at the top
	for band in 3:
		var ww: float = w * float([1.0, 0.55, 0.22][band])
		var cc: Color = c * Color(1, 1, 1, float([0.16, 0.32, 0.85][band]))
		var pts := PackedVector2Array([(a - nrm * ww).floor(), (a + nrm * ww).floor(), b.floor()])
		ci.draw_colored_polygon(pts, cc)

## a magic circle: two rings and runes between them, turning
func _rune(ci: CanvasItem, sp: Vector2, r: float, c: Color, ang: float) -> void:
	_ring(ci, sp, r, c)
	_ring(ci, sp, r * 0.72, c * Color(1, 1, 1, 0.8))
	for k in 8:
		var a := ang + TAU * float(k) / 8.0
		var q := (sp + Vector2.from_angle(a) * r * 0.86).floor()
		# a little glyph: a tick and a dot, turned with the circle
		var t := Vector2.from_angle(a + PI * 0.5)
		ci.draw_rect(Rect2(q, Vector2.ONE), c)
		ci.draw_rect(Rect2((q + t).floor(), Vector2.ONE), c)
		ci.draw_rect(Rect2((q - t).floor(), Vector2.ONE), c * Color(1, 1, 1, 0.6))
	for k2 in 3:
		var a2 := -ang * 1.5 + TAU * float(k2) / 3.0
		_line(ci, (sp + Vector2.from_angle(a2) * r * 0.72).floor(), (sp + Vector2.from_angle(a2 + TAU / 3.0) * r * 0.72).floor(), c * Color(1, 1, 1, 0.5))
