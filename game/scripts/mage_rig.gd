extends RefCounted
## The mage's secondary motion: the floppy tip of his hat, the end of his beard, his scarf and the
## staff in his hand are simulated, not drawn into the sprite frames. Each chain is a few points
## (Verlet) pulled toward its rest shape, weighed down by gravity, thrown about by the body's own
## acceleration (inertia: they lag when he sets off, swing on when he stops, flop when he lands)
## and blown back by the air when he runs or falls. The staff is a stiff pole on an angular spring
## that leans with his movement and points where he casts.
##
## Everything lives in the sprite's own pixel space (x forward, y down, 1 unit = 1 sprite pixel,
## the frame's top-left pixel at 0, 0), so the parts are drawn as crisp pixels with the sprite's
## transform and outline. Anchors per frame come from Defs.MAGE_ANCHORS.

const OUTLINE := Color(0.07, 0.04, 0.1, 1.0)
const HAT_REST := [Vector2(-0.4, -1.4), Vector2(-1.1, -1.0), Vector2(-1.4, 0.0), Vector2(-1.1, 0.9)]
const BEARD_REST := [Vector2(0.0, 1.2), Vector2(-0.3, 1.0)]
const SCARF_REST := [Vector2(-0.7, 1.0), Vector2(-0.7, 1.0), Vector2(-0.7, 1.0), Vector2(-0.7, 1.0), Vector2(-0.7, 1.0)]
const HAT_COLS := [Color("#2c1f6e"), Color("#4632a4"), Color("#4632a4"), Color("#6a52d0")]
const HAT_DARK := [Color("#1a1146"), Color("#2c1f6e"), Color("#4632a4"), Color("#4632a4")]
const STAR := Color("#fff1a8")
const BEARD := [Color("#f6f6fc"), Color("#cfcce4")]
const SCARF := [Color("#b8283a"), Color("#f05a4c")]
const WOOD := [Color("#583619"), Color("#86552a"), Color("#3a2210")]
const GOLD := Color("#e2b048")
const SKIN := [Color("#f2c9a2"), Color("#c88a64")]

class Chain:
	var rest: Array
	var p := PackedVector2Array()
	var q := PackedVector2Array()
	var stiff := 0.2
	var grav := 0.05
	var drag := 0.3
	var damp := 0.9
	var placed := false
	func _init(r: Array, s: float, g: float, d: float, dm: float) -> void:
		rest = r
		stiff = s
		grav = g
		drag = d
		damp = dm
		p.resize(r.size() + 1)
		q.resize(r.size() + 1)
	func place(anchor: Vector2) -> void:
		p[0] = anchor
		for i in rest.size():
			p[i + 1] = p[i] + rest[i]
		q = p.duplicate()
		placed = true
	func step(anchor: Vector2, inertia: Vector2, air: Vector2, flutter: float, t: float) -> void:
		if not placed:
			place(anchor)
		# the anchor moves with the frame (breathing, walking): carry the chain along with it
		var shift := anchor - p[0]
		p[0] = anchor
		q[0] = anchor
		for i in range(1, p.size()):
			var cur := p[i] + shift * 0.6
			var vel := (cur - q[i]) * damp
			q[i] = cur
			var target: Vector2 = p[i - 1] + rest[i - 1]
			var f := (target - cur) * stiff + Vector2(0.0, grav) - inertia + air * drag
			if flutter > 0.0:
				f.y += sin(t * 0.45 + i * 1.3) * flutter * float(i) / p.size()
			var np := cur + vel + f
			# keep each link its own length
			var d := np - p[i - 1]
			var L: float = rest[i - 1].length()
			if d.length() > 0.0001:
				np = p[i - 1] + d.normalized() * L
			p[i] = np

var hat := Chain.new(HAT_REST, 0.28, 0.04, 0.22, 0.86)
var beard := Chain.new(BEARD_REST, 0.35, 0.06, 0.18, 0.84)
var scarf := Chain.new(SCARF_REST, 0.03, 0.10, 0.55, 0.9)
var staff_a := -0.1       # radians from straight up; positive leans the top forward
var staff_w := 0.0
var _prev_v := Vector2.ZERO
var _t := 0.0
var _anch := {}

## One frame of motion. vel: the body's velocity in sprite space (x forward, y down, cells per
## frame). pose: the frame's name (for its anchors). aim: the casting direction in sprite space
## (zero when not casting). wind: a breeze in sprite space (the title screen's).
func update(pose: String, vel: Vector2, aim: Vector2, wind := Vector2.ZERO) -> void:
	_t += 1.0
	_anch = Defs.MAGE_ANCHORS.get(pose, Defs.MAGE_ANCHORS["mage"])
	var acc := (vel - _prev_v).limit_length(3.0)
	_prev_v = vel
	var air := -vel.limit_length(4.0) + wind
	var run := absf(vel.x)
	hat.step(_v(_anch["hat"]) + Vector2(0.5, 0.5), acc * 0.9, air, 0.0, _t)
	beard.step(_v(_anch["chin"]) + Vector2(0.5, 0.5), acc * 0.6, air, 0.0, _t)
	scarf.step(_v(_anch["neck"]) + Vector2(0.5, 0.5), acc, air, 0.06 + run * 0.12 + wind.length() * 0.2, _t)
	# the staff: an angular spring toward a lean that suits what he's doing
	var target := -0.08
	if aim != Vector2.ZERO:
		target = clampf(atan2(aim.x, -aim.y), -0.4, 2.6)
	elif run > 0.2:
		target = -0.12 - run * 0.12
	if vel.y < -0.5 and aim == Vector2.ZERO:
		target -= 0.15
	staff_w += (target - staff_a) * (0.22 if aim != Vector2.ZERO else 0.07) - staff_w * 0.2 - acc.x * 0.05 + acc.y * 0.02
	staff_a += staff_w

func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## Pixels of the parts drawn behind the body (the scarf): Vector2i -> Color
func back_pixels() -> Dictionary:
	var px := {}
	_raster(scarf.p, [2, 2, 1, 1, 1], 0, px)
	return px

## Pixels of the parts drawn in front (the hat's tip, the beard's end, the staff and the fist).
## gem: the crystal's colour (the selected spell's).
func front_pixels(gem: Color) -> Dictionary:
	var px := {}
	_raster(hat.p, [2, 2, 1, 1], 1, px)
	var tip: Vector2 = hat.p[hat.p.size() - 1]
	px[Vector2i(floori(tip.x), floori(tip.y))] = STAR
	_raster(beard.p, [2, 1], 2, px)
	# the staff from below the fist up to its crystal
	var hand := _v(_anch.get("hand", [14, 17])) + Vector2(0.5, 0.5)
	var dir := Vector2(sin(staff_a), -cos(staff_a))
	for i in range(-6, 15):
		var s := hand + dir * float(i)
		var c: Color = WOOD[0] if (i % 3 != 0) else WOOD[1]
		if i == 11 or i == 12:
			c = GOLD
		elif i < -4:
			c = WOOD[2]
		px[Vector2i(floori(s.x), floori(s.y))] = c
	var top := hand + dir * 15.5
	var glow := 0.75 + 0.25 * sin(_t * 0.12)
	for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		px[Vector2i(floori(top.x), floori(top.y)) + o] = gem * glow
	px[Vector2i(floori(top.x), floori(top.y)) + Vector2i(0, -1)] = Color(1, 1, 1).lerp(gem, 0.2)
	# the fist closes over the staff
	var hi := Vector2i(floori(hand.x), floori(hand.y))
	px[hi] = SKIN[0]
	px[hi + Vector2i(1, 0)] = SKIN[1]
	return px

## the crystal's position (for a light), in sprite space
func crystal() -> Vector2:
	var hand := _v(_anch.get("hand", [14, 17])) + Vector2(0.5, 0.5)
	return hand + Vector2(sin(staff_a), -cos(staff_a)) * 15.5

## the colour of a part's pixel: part 0 scarf, 1 hat, 2 beard; k = which link
func _col(part: int, x: int, y: int, k: int) -> Color:
	match part:
		0:
			return SCARF[1] if (x + y + k) % 3 == 0 else SCARF[0]
		1:
			return HAT_COLS[k] if x % 2 == 0 else HAT_DARK[k]
	return BEARD[mini(k, 1)]

func _raster(pts: PackedVector2Array, widths: Array, part: int, out: Dictionary) -> void:
	for k in range(pts.size() - 1):
		var a := pts[k]
		var b := pts[k + 1]
		var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y)) * 2.0) + 1
		for t in n + 1:
			var s := a.lerp(b, float(t) / n)
			var x := floori(s.x)
			var y := floori(s.y)
			out[Vector2i(x, y)] = _col(part, x, y, k)
			if int(widths[k]) > 1:
				out[Vector2i(x - 1, y)] = _col(part, x - 1, y, k)

## Draws a set of pixels (and their dark outline wherever it doesn't fall on the body, given by
## `mask`) on canvas item ci: pixel (x, y) at origin + (x, y) * unit, tinted by mod.
static func draw_pixels(ci: CanvasItem, px: Dictionary, origin: Vector2, unit: float, mod: Color, mask: Dictionary) -> void:
	var edge := {}
	for p in px:
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + o
			if not px.has(n) and not mask.has(n):
				edge[n] = true
	var oc := OUTLINE
	oc.a = mod.a
	for e in edge:
		ci.draw_rect(Rect2(origin + Vector2(e) * unit, Vector2(unit, unit)), oc)
	for p in px:
		var c: Color = px[p] * mod
		c.a = mod.a
		ci.draw_rect(Rect2(origin + Vector2(p) * unit, Vector2(unit, unit)), c)

## The opaque pixels of a sprite frame plus its outline ring (where a part's own outline would
## draw a dark line across the body), as a set of Vector2i.
static func body_mask(key: String) -> Dictionary:
	var rows: Array = Defs.SPRITES[key]["rows"]
	var m := {}
	for y in rows.size():
		var r: String = rows[y]
		for x in r.length():
			if r[x] != ".":
				for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					m[Vector2i(x, y) + o] = true
	return m
