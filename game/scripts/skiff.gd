## The Wisp Skiff: a small ship for two, a pixel body (pixel_body.gd) grown from parts.
##
## Parts, each a small function so other ships can reuse them: a planked hull with a keel that
## rises to the bow (`_hull`), a trim stripe along the gunwale (`_trim`), a cabin under a glass
## canopy (`_canopy`: a timber frame, a glass shell, open room inside with a glass back pane), a
## wisp-ore engine at the stern (`_engine`), a tail fin (`_fin`). The seed varies the proportions.
## Two seats on the cabin floor (pilot forward). The cabin is the body's room (pixel_body.gd): it can
## be built in.
##
## Flying (`fly`): the pilot steers with the movement keys (up and down too) or by holding cast
## toward the cursor (`steer`). In the air the skiff eases to the speed you steer for and, hands
## off, to a hover (just above the ground it settles onto it, softly); its engine holds it up. The
## hull stays level with the ground below, tilting into climbs and dives on a spring, and turns
## round when you steer the other way (`look` eases through the turn for the picture). Nobody at the
## controls: it falls. In space it keeps its speed (thrust adds to it) and the nearest planet pulls.
## It collides with the world by its outline (`collide`, through main's collision grid).
##
## Damage (user, 23 Nov: pirates, and "hull damage and repair for the skiff"): what hits it (a pirate's
## bolt, a storm belt's lightning, a crash into rock at speed) carves cells out of its hull (`damage`).
## `hull_f` is how much of the hull as forged (`design`) is left, `engine_f` how much of its wisp
## engine (its thrust goes with it). Below `HULL_FLOOR` the hull holds by its wisp-binding and the hits
## go through to the riders. Mending (`mend`, main `_mend_skiff`: hold R by it or aboard) knits the
## cells forged back, from what's left outward.
extends "res://scripts/pixel_body.gd"

const CRUISE := 7.0             # top speed in the air (cells a tick)
const CRUISE_HIGH := 16.0       # above the atmosphere
const ACCEL := 0.32             # how quickly it reaches the speed you steer for (a tick)
const BRAKE := 0.2              # hands off: how quickly it slows to a hover
const SPACE_THRUST := 0.3
const MAX_SPEED := 40.0
const TILT := 0.42              # the most it tilts into a climb or a dive (radians)
const SEATS := 2

var design_seed := 0       # (the shape of this skiff)
var seat_cells: Array = []      # [Vector2i] the cell each seat's feet rest on, pilot first
var riders: Array = []          # [mage or null] per seat
var thrusting := false
var grounded := false
var ground_t := 0               # ticks resting on something
var centre := Vector2.ZERO      # the centre of the planet it flies over (space.gd: the nearest one)
var look := 1.0                 # which way it's drawn facing: eases from one side to the other in a turn
var clear_below := 99.0         # air under the keel (cells, up to 24; `advance` measures it)
var power := 1.0                # its engine (1.5 with the Star-Iron Engine): thrust and top speed in space
const HULL_FLOOR := 0.25        # below this much hull, hits go through to the riders
var design := PackedByteArray() # the hull as forged (material per cell): what mending puts back
var design_v := PackedByteArray()
var hull0 := 1                  # cells of the hull as forged
var engine0 := 1                # (its engine's wisp cells as forged)
var hull_f := 1.0               # how much of the hull is left (0..1)
var engine_f := 1.0             # how much of its engine (thrust goes with it)
var bump := 0.0                 # the hardest knock into something since `advance` began (speed into it)
var bump_at := Vector2.ZERO     # (where: the middle of what touched)

static func make(sd: int):
	var s = load("res://scripts/skiff.gd").new()
	s.design_seed = sd
	s._design()
	return s

func _design() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = design_seed
	var length := 52 + rng.randi_range(0, 8)
	var deck := 27 + rng.randi_range(0, 2)          # the deck's row; the canopy rises above it (room for a hat)
	var depth := 9 + rng.randi_range(0, 3)          # hull depth below the deck
	setup(length + 4, deck + depth + 2)
	var cx := int(length * (0.5 + rng.randf_range(0.0, 0.06)))   # the cockpit's middle
	var crx := 15 + rng.randi_range(0, 3)
	_hull(length, deck, depth, rng)
	_trim(length, deck)
	_engine(deck, depth)
	_fin(deck, rng)
	_canopy(cx, deck, crx, deck - 1, rng)          # (last: its room stays clear)
	seat_cells = [Vector2i(cx + 4, deck - 1), Vector2i(cx - 6, deck - 1)]
	riders = []
	riders.resize(SEATS)
	rebuild()
	# (the hull as forged: what mending puts back)
	design = cells.duplicate()
	design_v = vars.duplicate()
	hull0 = 0
	engine0 = 0
	for k in design.size():
		if design[k] != 0:
			hull0 += 1
			if design[k] == Defs.WISP:
				engine0 += 1
	hull0 = maxi(hull0, 1)
	engine0 = maxi(engine0, 1)
	_recount()

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

## a cabin over the cockpit: a timber frame, a glass shell, and the room inside left open (its back
## a pane of glass), so the riders sit in it and it can be built in
func _canopy(cx: int, deck: int, rx: float, ry: float, rng: RandomNumberGenerator) -> void:
	var lean := rng.randf_range(-0.15, 0.25)          # (the dome leans back a little)
	for j in range(deck - int(ry), deck):
		for i in range(cx - int(rx) - 4, cx + int(rx) + 5):
			var up_by := float(deck - j)
			var shift := up_by / float(ry) * lean * rx
			if _ellipse(float(i - cx) + shift, up_by, rx, ry, 0.0) > 1.0:
				continue
			if _ellipse(float(i - cx) + shift, up_by, rx, ry, 1.5) > 1.0:
				put(i, j, Defs.WOOD)                       # the frame
			elif _ellipse(float(i - cx) + shift, up_by, rx, ry, 3.0) > 1.0:
				put(i, j, Defs.GLASS if up_by > 2.5 else Defs.WOOD)   # the shell (timber at its foot)
			else:
				cells[j * w + i] = 0
				bg[j * w + i] = Defs.GLASS                 # the room inside: a glass back pane
				bgv[j * w + i] = randi() & 3

## (how far out a point is in an ellipse shrunk by `inset` cells: 1 on its edge)
func _ellipse(x: float, y: float, rx: float, ry: float, inset: float) -> float:
	var ax := maxf(rx - inset, 1.0)
	var ay := maxf(ry - inset, 1.0)
	return (x * x) / (ax * ax) + (y * y) / (ay * ay)

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

## The pilot's wish as a direction in the world (length up to 1): the movement keys (left, right, up,
## down over the planet below) and, holding cast, toward the cursor.
func steer(inp) -> Vector2:
	var up := (pos - centre).normalized()
	var right := Vector2(up.y, -up.x)
	var s := right * float(inp.move) + up * ((1.0 if inp.jump else 0.0) - (1.0 if inp.down else 0.0))
	if inp.cast:
		var d: Vector2 = inp.aim - pos
		if d.length() > 4.0:
			s += d.normalized()
	return s.limit_length(1.0)

## One tick of flight (speeds and turning; `advance` moves it). `want`: the pilot's wish (`steer`),
## `piloted`: someone is at the controls, `g`: the pull here (toward `centre`, per tick), `in_space`:
## no air (it keeps its speed), `cruise`: its top speed in the air here, `drag`: the air's, per tick.
func fly(want: Vector2, piloted: bool, g: float, in_space: bool, cruise: float, drag: float) -> void:
	thrusting = false
	var up := (pos - centre).normalized()      # (centre: the planet it flies over; out in space the nearest)
	var right := Vector2(up.y, -up.x)          # the planet's "right" here (its "up" turned a quarter clockwise)
	var steering := piloted and want.length() > 0.05
	# turn round when steered the other way (the picture eases through it: `look`)
	if steering and want.dot(right) * float(facing) < -0.25:
		facing = -facing
	if not piloted:
		# nobody at the controls: it falls, and drifts
		if grounded and vel.length() < 0.5:
			vel = Vector2.ZERO
		else:
			vel -= up * g
			vel *= drag
	elif in_space:
		if steering:
			vel += want * SPACE_THRUST * power * thrust()
			thrusting = true
		vel -= up * g
		vel *= drag
	elif grounded and not steering and vel.length() < 0.6:
		vel = Vector2.ZERO                     # resting on its keel
	else:
		# the engine holds it up: it eases to the speed you steer for, or to a hover
		var target := want * cruise * thrust()
		if not steering and clear_below < 10.0:
			target = -up * 1.2                 # (hands off just above the ground: it settles onto it)
		var down := -target.dot(up)
		if down > 0.0 and clear_below < 16.0:
			# coming down close to the ground: gently
			target += up * (down - minf(down, lerpf(1.2, cruise, clear_below / 16.0)))
		vel += (target - vel).limit_length(ACCEL if steering else BRAKE)
		# (faster than it can fly here, coming in from above: the air takes the extra off quickly)
		if vel.length() > cruise:
			vel = vel.normalized() * maxf(cruise, vel.length() * 0.93)
		thrusting = steering
	if vel.length() > MAX_SPEED * power:
		vel = vel.normalized() * MAX_SPEED * power
	# the hull: level with the ground below, tilted into a climb or a dive, on a spring
	var tilt := 0.0
	if not (grounded and vel.length() < 0.6):
		tilt = clampf(vel.dot(up) * 0.07, -TILT, TILT)
	var nd := (right * float(facing) + up * tilt).normalized()
	omega += angle_difference(ang, (nd * float(facing)).angle()) * 0.05
	omega *= 0.78
	ang += omega
	look = move_toward(look, float(facing), 0.14)

## Move by this tick's velocity, in steps small enough not to pass through the ground, colliding
## at each (no `solid`: out in space, or away from any collision grid); then how much air is under
## the keel.
func advance(solid: Callable) -> void:
	bump = 0.0
	if not solid.is_valid():
		pos += vel
		grounded = false
		clear_below = 99.0
		return
	var n := clampi(int(ceil(vel.length() / 2.0)), 1, 24)
	var was_grounded := false
	for k in n:
		pos += vel / float(n)
		collide(solid)
		was_grounded = was_grounded or grounded
	grounded = was_grounded
	var up := (pos - centre).normalized()
	var kp := to_world(keel)
	clear_below = 24.0
	for d in range(1, 25):
		if solid.call(kp - up * float(d)):
			clear_below = float(d - 1)
			break

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
		if -vn > bump:
			bump = -vn
			bump_at = pos - nsum / float(hit)
		vel -= n * vn
	# friction along whatever it scrapes
	vel -= (vel - n * vel.dot(n)) * 0.12
	if n.dot(up) > 0.5:
		grounded = true
		ground_t += 1

# --------------------------------------------------------------- damage ---

## Mass and the rest from the cells, and then how much of the hull and engine is left.
func rebuild() -> void:
	super()
	_recount()

func _recount() -> void:
	if design.size() != cells.size():
		hull_f = 1.0
		engine_f = 1.0
		return
	var nh := 0
	var ne := 0
	for k in design.size():
		var d := design[k]
		if d != 0 and cells[k] != 0 and made[k] == 0:
			nh += 1
			if d == Defs.WISP:
				ne += 1
	hull_f = float(nh) / float(hull0)
	engine_f = float(ne) / float(engine0)

## its thrust (and cruise) as its engine is: a hit to it tells, but a wounded skiff still limps home
func thrust() -> float:
	return 0.4 + 0.6 * sqrt(engine_f)

## A hit at world point p: the hull's cells within r are carved out. Returns how many went (0 once
## the hull is down to HULL_FLOOR: it holds, and the hit goes through to whoever is aboard).
func damage(p: Vector2, r: float) -> int:
	if hull_f <= HULL_FLOOR:
		return 0
	return carve(p, r)

## cells of the hull as forged that are gone
func missing() -> int:
	var n := 0
	if design.size() != cells.size():
		return 0
	for k in design.size():
		if design[k] != 0 and cells[k] == 0:
			n += 1
	return n

## Mend up to n of the hull's lost cells, from what's left outward (a gone cell beside one still there
## first). Returns the world points of the cells put back.
func mend(n: int) -> Array:
	var out := []
	if design.size() != cells.size() or n <= 0:
		return out
	var cand := PackedInt32Array()
	var lone := PackedInt32Array()
	for k in design.size():
		if design[k] == 0 or cells[k] != 0:
			continue
		var i := k % w
		var j := k / w
		if at(i - 1, j) != 0 or at(i + 1, j) != 0 or at(i, j - 1) != 0 or at(i, j + 1) != 0:
			cand.append(k)
		else:
			lone.append(k)
	if cand.is_empty():
		cand = lone
	for q in mini(n, cand.size()):
		var pick := randi() % cand.size()
		var k2: int = cand[pick]
		cand.remove_at(pick)
		cells[k2] = design[k2]
		vars[k2] = design_v[k2]
		made[k2] = 0
		out.append(cell_world(k2 % w, k2 / w))
	if not out.is_empty():
		rebuild()
	return out
