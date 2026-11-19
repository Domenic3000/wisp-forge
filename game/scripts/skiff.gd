## The Wisp Skiff: a small ship for two, a pixel body (pixel_body.gd) grown from parts.
##
## Parts, each a small function so other ships can reuse them: a planked hull with a keel that
## rises to the bow (`_hull`), a trim stripe along the gunwale (`_trim`), a glass canopy over the
## cockpit (`_canopy`), a wisp-ore engine at the stern (`_engine`), a tail fin (`_fin`). The seed
## varies the proportions. Two seats under the canopy (pilot forward).
##
## Flying (`fly`): hold cast to push toward the cursor; the skiff turns its nose that way first
## (mirroring when you aim behind it, so it never flies upside down). On a planet the pull of the
## ground and the air's drag act on it, and it collides with the world by its outline (`collide`,
## through main's collision grid), settling level on its keel; in space there's only the planet's
## fading pull.
extends "res://scripts/pixel_body.gd"

const THRUST := 0.24            # (gravity at the surface is 0.17 a tick)
const TURN := 0.06              # how fast it turns toward the cursor (radians a tick)
const MAX_SPEED := 40.0
const SEATS := 2

var design_seed := 0       # (the shape of this skiff)
var seat_cells: Array = []      # [Vector2i] the cell each seat's feet rest on, pilot first
var riders: Array = []          # [mage or null] per seat
var thrusting := false
var grounded := false
var ground_t := 0               # ticks resting on something

static func make(sd: int):
	var s = load("res://scripts/skiff.gd").new()
	s.design_seed = sd
	s._design()
	return s

func _design() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = design_seed
	var length := 52 + rng.randi_range(0, 8)
	var deck := 20 + rng.randi_range(0, 2)          # the deck's row; the canopy rises above it
	var depth := 9 + rng.randi_range(0, 3)          # hull depth below the deck
	setup(length + 4, deck + depth + 2)
	var cx := int(length * (0.5 + rng.randf_range(0.0, 0.06)))   # the cockpit's middle
	var crx := 15 + rng.randi_range(0, 3)
	_hull(length, deck, depth, rng)
	_trim(length, deck)
	_canopy(cx, deck, crx, deck - 1, rng)
	_engine(deck, depth)
	_fin(deck, rng)
	seat_cells = [Vector2i(cx + 6, deck - 1), Vector2i(cx - 7, deck - 1)]
	riders = []
	riders.resize(SEATS)
	rebuild()

## the hull: planks from the deck down to a keel that rises toward the bow and the stern
func _hull(length: int, deck: int, depth: int, rng: RandomNumberGenerator) -> void:
	var bow_rise := 0.55 + rng.randf() * 0.2
	for i in length:
		var t := float(i) / float(length - 1)         # 0 stern .. 1 bow
		var keel := depth * (1.0 - pow(maxf(0.0, (t - 0.55) / 0.45), 1.6) * bow_rise - pow(maxf(0.0, (0.12 - t) / 0.12), 2.0) * 0.5)
		for j in range(deck, deck + int(round(keel)) + 1):
			put(i + 2, j, Defs.PLANK if (j - deck) % 4 != 3 else Defs.WOOD)
	# the bow comes up to a point above the deck
	for k in 5:
		for j2 in range(deck - k, deck):
			put(length + 1 - k, j2, Defs.PLANK)

## a stripe of copper along the gunwale, and the keel's own dark timber
func _trim(length: int, deck: int) -> void:
	for i in range(2, length + 2):
		if at(i, deck) != 0:
			put(i, deck, Defs.COPPER)
	for i2 in range(2, length + 2):
		for j in range(h - 1, -1, -1):
			if at(i2, j) != 0:
				put(i2, j, Defs.WOOD)
				break

## a glass dome over the cockpit, with a timber rim
func _canopy(cx: int, deck: int, rx: int, ry: int, rng: RandomNumberGenerator) -> void:
	var lean := rng.randf_range(-0.15, 0.25)          # (the dome leans back a little)
	for j in range(deck - ry, deck):
		for i in range(cx - rx - 4, cx + rx + 5):
			var dy := float(deck - j) / float(ry)
			var dx := (float(i - cx) + dy * lean * rx) / float(rx)
			var d := dx * dx + dy * dy
			if d <= 1.0:
				put(i, j, Defs.WOOD if d > 0.86 else Defs.GLASS)

## the wisp-ore engine at the stern, glowing where it pushes
func _engine(deck: int, depth: int) -> void:
	for j in range(deck - 2, deck + depth - 3):
		for i in range(0, 4):
			put(i, j, Defs.WISP)

## a fin at the stern
func _fin(deck: int, rng: RandomNumberGenerator) -> void:
	var ht := 7 + rng.randi_range(0, 4)
	for k in ht:
		for i in range(4, 4 + maxi(1, 6 - k / 2)):
			put(i + k / 3, deck - 1 - k, Defs.WOOD)

# ------------------------------------------------------------- riders ---

func seat_of(m) -> int:
	return riders.find(m)

func pilot():
	return riders[0]

## where a seat's rider stands (their body's centre), in the world
func seat_world(k: int, body_h: float) -> Vector2:
	var sc: Vector2i = seat_cells[k]
	var feet := Vector2(sc.x + 0.5, sc.y + 1.0) - com
	return to_world(feet - Vector2(0, body_h * 0.5))

func board(m) -> bool:
	for k in SEATS:
		if riders[k] == null:
			riders[k] = m
			return true
	return false

func leave(m) -> void:
	var k := riders.find(m)
	if k >= 0:
		riders[k] = null
		# (with no pilot, the next rider takes the controls)
		if k == 0:
			for k2 in range(1, SEATS):
				if riders[k2] != null:
					riders[0] = riders[k2]
					riders[k2] = null
					break

func aboard_all(ps: Array) -> bool:
	for m in ps:
		if not m.dead and riders.find(m) < 0:
			return false
	return true

# ------------------------------------------------------------- flying ---

## One tick of flight (speeds and turning; `advance` moves it). `aim` is where the pilot points
## (world), `push` whether they hold cast, `g` the planet's pull here (toward the centre, per tick),
## `drag` per tick.
func fly(aim: Vector2, push: bool, g: float, drag: float) -> void:
	thrusting = false
	var up := pos.normalized()
	var right := Vector2(up.y, -up.x)          # the planet's "right" here (its "up" turned a quarter clockwise)
	if not push and grounded and vel.length() < 0.5:
		# resting on its keel: it stays put, settling level
		vel = Vector2.ZERO
		ang = rotate_toward(ang, right.angle(), TURN * 0.6)
		return
	if push:
		var d := aim - pos
		if d.length() > 2.0:
			var want := d.normalized()
			# face the way you push: mirror when aiming clearly behind (keel stays down; straight up or
			# down it keeps the way it faces, so it doesn't flip back and forth)
			var side := want.dot(right)
			if side * float(facing) < -0.15:
				facing = -facing
			var target := (want * float(facing)).angle()
			ang = rotate_toward(ang, target, TURN)
			vel += nose() * THRUST * clampf(nose().dot(want) * 1.2, 0.2, 1.0)
			thrusting = true
	else:
		# hands off: it eases level
		ang = rotate_toward(ang, right.angle(), TURN * (0.6 if grounded else 0.25))
	vel -= up * g
	vel *= drag
	if vel.length() > MAX_SPEED:
		vel = vel.normalized() * MAX_SPEED

## Move by this tick's velocity, in steps small enough not to pass through the ground, colliding
## at each (no `solid`: out in space, or away from any collision grid).
func advance(solid: Callable) -> void:
	if not solid.is_valid():
		pos += vel
		grounded = false
		return
	var n := clampi(int(ceil(vel.length() / 2.0)), 1, 24)
	var was_grounded := false
	for k in n:
		pos += vel / float(n)
		collide(solid)
		was_grounded = was_grounded or grounded
	grounded = was_grounded

## Push it out of the ground: `solid(p)` says whether a world point is solid. Its outline is
## checked; where it has gone into something it steps back out along the way it came (and up),
## losing the speed it had into the ground and some along it.
func collide(solid: Callable) -> void:
	var up := pos.normalized()
	var hit := 0
	var nsum := Vector2.ZERO
	for b in outline:
		var p := to_world(b)
		if solid.call(p):
			hit += 1
			nsum += pos - p
	grounded = false
	if hit == 0:
		# not in the ground, but maybe resting right on it
		for b3 in outline:
			if solid.call(to_world(b3) - up * 1.0):
				grounded = true
				ground_t += 1
				return
		ground_t = 0
		return
	var n := (nsum.normalized() + up * 0.6).normalized()
	# step out (a few cells at most), then lose the speed into the ground
	for k in 8:
		pos += n * 0.6
		var still := false
		for b2 in outline:
			if solid.call(to_world(b2)):
				still = true
				break
		if not still:
			break
	var vn := vel.dot(n)
	if vn < 0.0:
		vel -= n * vn
	vel *= 0.82
	if n.dot(up) > 0.5:
		grounded = true
		ground_t += 1
