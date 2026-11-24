## A great foe (Vulkhar, a guardian, a warden) struck from where it can't follow you COMES TO YOU (user,
## 24 Nov: "I was able to shoot it through a hole and easily just shoot through it and move back
## repeatedly. How can we make sure the boss has a clear way to attack the player making sure they cant
## avoid the mechanics"; chose: it comes to you).
##
## Every hit on it (main `_hurt_enemy` -> `struck`) is weighed on its next tick: if its way-finding graph
## (its own size and jump) has no way from it to you, the hit is a GRUDGE. Stepping back out of sight or
## out of range doesn't wipe a grudge (the old timers did: peeking through a hole, then stepping back,
## reset them before they ever answered); only FORGET frames without another one does. GRUDGE_AT of them
## and it comes: TELL frames of warning (a rune circle and rising embers where it will stand, the ground
## shaking, the boss flickering in its own glow), then it bursts out there. Where it stands is a spot of
## the graph where its whole body stands, from RMIN to RMAX of you, with a way from there to you
## (`Nav.meet_spots`; a flier: `Nav.fly_spots`). With none (you in a tunnel narrower than it) it blasts a
## pocket of its own size beside you (`_pocket`, only through what its blast can cut: `power`, never
## warded stone; cut out exactly, `_carve`) and comes out of that. Guardians keep to their leash, wardens
## to their hall. It comes too when it has had no way to you for KEPT_AT frames with you near, struck or
## not (user, 24 Nov: "chase ... aggresively"), and calls its help as it lands (`call_next`, boss_ai
## `_begin`; Vulkhar's imps).
extends RefCounted

const VFX := preload("res://scripts/vfx.gd")
const Nav := preload("res://scripts/nav.gd")
const Build := preload("res://scripts/build.gd")
const GRUDGE_AT := 2       # hits from where it can't follow before it comes
const FORGET := 900        # frames after the last such hit that it lets it go
const TELL := 66           # frames of warning
const CARVE_AT := 22       # (frames before it comes out that its pocket is blasted: the grid catches up)
const WAIT := 30           # (frames it may wait for that pocket to clear)
const COOLDOWN := 420      # frames before it may come again
const RMAX := 130.0        # how far from you it may come out (cells)
const KEPT_AT := 300       # frames with no way to you (and you within KEPT_R) before it comes unhit
const KEPT_R := 260.0

## (main `_hurt_enemy`: a hit on a great foe, weighed on its next tick)
static func struck(e) -> void:
	e.struck_n += 1

## A walker's way-finding class (its jump `jv` under the pull `gacc`), as `FoeAI.can_reach` uses it.
static func walk_key(e, jv: float, gacc: float) -> String:
	return Nav.key_for("walk", e.w, e.h, jv * jv / (2.0 * maxf(gacc, 0.01)) - 4.0)

static func fly_key(e) -> String:
	return Nav.key_for("fly", e.w, e.h)

## Each tick of an awake great foe with a target. True while it is coming to you: the caller lets it
## do nothing else (it holds still).
static func tick(g, e, tgt, key: String, power: int, fly: bool) -> bool:
	var nav = g.nav_of_grid()
	nav.ask(key)
	if e.come_cd > 0:
		e.come_cd -= 1
	if e.come_t > 0:
		_coming(g, e, tgt)
		return true
	if e.struck_n > 0 and nav.has(key):
		var n: int = e.struck_n
		e.struck_n = 0
		if not tgt.dead and e.pos.distance_to(tgt.pos) < 380.0 and not reach_now(g, e, tgt, key, fly):
			e.grudge += n
			e.grudge_f = g.frame
	if e.grudge > 0 and g.frame - e.grudge_f > FORGET:
		e.grudge = 0
	# kept from you with no hits at all (hiding where it can't follow): looked at twice a second
	if g.frame % 30 == 0:
		if not tgt.dead and nav.has(key) and e.pos.distance_to(tgt.pos) < KEPT_R and not reach_now(g, e, tgt, key, fly):
			e.kept_t += 30
		else:
			e.kept_t = 0
	if (e.grudge >= GRUDGE_AT or e.kept_t >= KEPT_AT) and e.come_cd <= 0 and (e.act == "" or e.act == "recover") and g.frame % 6 == 0:
		_begin(g, e, tgt, key, power, fly)
		return e.come_t > 0
	return false

## Is there a way from it to you right now (its graph, its size)? (A graph not built yet says yes.)
static func reach_now(g, e, tgt, key: String, fly: bool) -> bool:
	var nav = g.nav_of_grid()
	if not nav.has(key):
		return true
	var tol: float = 10.0 + e.w * 0.25
	if fly:
		var fp: PackedVector2Array = nav.fly_path(key, e.pos, tgt.pos)
		return fp.size() > 0 and fp[fp.size() - 1].distance_to(tgt.pos) < tol
	var tf: Vector2 = _feet(g, tgt)
	var p: PackedVector2Array = nav.walk_path(key, _feet(g, e), tf)
	return p.size() > 0 and p[p.size() - 1].distance_to(tf) < tol

static func _feet(g, b) -> Vector2:
	return b.pos + g.basis_d(atan2(b.pos.y, b.pos.x)) * (b.h * 0.5)

## where it will come out: a spot from which it can get at you, or a pocket it blasts beside you
static func _begin(g, e, tgt, key: String, power: int, fly: bool) -> void:
	var nav = g.nav_of_grid()
	var rmin: float = tgt.w * 0.5 + e.w * 0.5 + 6.0
	var spots: PackedVector2Array
	if fly:
		spots = nav.fly_spots(key, tgt.pos, 10.0 + e.w * 0.25, rmin, RMAX)
	else:
		spots = nav.meet_spots(key, _feet(g, tgt), 10.0 + e.w * 0.25, rmin, RMAX)
	var to := Vector2.INF
	for s in spots:
		var p: Vector2 = s if fly else s - g.basis_d(atan2(s.y, s.x)) * (e.h * 0.5 + 0.3)
		if _allowed(g, e, p):
			to = p
			break
	e.come_carve = false
	if to == Vector2.INF:
		to = _pocket(g, e, tgt, power)
		if to == Vector2.INF:
			e.come_why = "no spot and no pocket"
			e.come_cd = 120           # (it looks again in a while: you may move somewhere it can get at)
			return
		e.come_carve = true
	e.come_to = to
	e.come_t = TELL
	e.come_wait = 0
	e.act = ""
	e.vx = 0.0
	e.vy = 0.0
	e.come_why = "carve" if e.come_carve else "spot"
	var col: Color = _col(e)
	var ra: float = maxf(e.w, e.h) * 0.45
	g.vfx.spawn(VFX.RUNE, _feet_at(g, e, to), Vector2.ZERO, TELL, col, col * Color(1, 1, 1, 0), ra * 0.7, ra, true, 0.0, 1.0, 0.07)
	g.vfx.spawn(VFX.RUNE, e.pos, Vector2.ZERO, TELL, col, col * Color(1, 1, 1, 0), ra, ra * 0.6, true, 0.0, 1.0, -0.07)
	g.audio.play("roar", e.pos, 0.9)
	g.ui.toast("%s comes for you!" % _name(e), col, 3.0)

## the warning plays out, then it bursts out where it means to
static func _coming(g, e, tgt) -> void:
	e.come_t -= 1
	e.vx = 0.0
	e.vy = 0.0
	var col: Color = _col(e)
	var feet: Vector2 = _feet_at(g, e, e.come_to)
	var up: Vector2 = feet.normalized()
	var r: Vector2 = g.basis_r(atan2(feet.y, feet.x))
	if e.come_t % 3 == 0:
		for k in 3:
			g._particle(feet + r * (randf() - 0.5) * e.w, up * (0.4 + randf() * 1.2) + r * (randf() - 0.5) * 0.4, 26 + randi() % 20, col, true, -0.01)
		g._particle(e.pos + Vector2(randf() - 0.5, randf() - 0.5) * Vector2(e.w, e.h), Vector2.ZERO, 20, col, true, 0.0)
	if e.come_t % 10 == 0:
		e.flash = 4
	g.shake = maxf(g.shake, 1.5 + 4.0 * (1.0 - float(e.come_t) / float(TELL)))
	if e.come_carve and e.come_t == CARVE_AT:
		_carve(g, e)
	if e.come_t > 0:
		return
	# out it comes, once there's room for it
	var l: Vector2 = g.to_grid(e.come_to)
	var blocked: bool = g.box_solid(l.x - e.w * 0.5, l.y - e.h * 0.5, e.w, e.h)
	if blocked and e.come_wait < WAIT:
		e.come_wait += 1
		e.come_t = 1
		return
	var to: Vector2 = e.come_to
	if blocked:
		to = g.free_spot(e.come_to, e.w, e.h, 12)
		var l2: Vector2 = g.to_grid(to)
		if g.box_solid(l2.x - e.w * 0.5, l2.y - e.h * 0.5, e.w, e.h):
			e.come_why = "blocked"
			e.come_cd = 120
			e.grudge = 0
			return
	e.pos = to
	e.vx = 0.0
	e.vy = 0.0
	for k in e.trail.size():
		e.trail[k] = to
	e.path = PackedVector2Array()
	e.path_t = 0
	e.nav_air = false
	e.leaping = false
	e.act = ""
	e.act_cd = 24
	e.unreach_t = 0
	e.reach_ok = true
	e.grudge = 0
	e.kept_t = 0
	e.come_cd = COOLDOWN
	e.came_n += 1
	# (and it comes with help: a guardian's or warden's next move is its summoning, Vulkhar calls imps)
	e.call_next = true
	if e.type == "golem":
		g._golem_imps(e)
	e.awake = true
	e.see = true
	g.vfx.blast(to, maxf(e.w, e.h) * 0.55, 0)
	g.shake = maxf(g.shake, 12.0)
	g.audio.play("boom", to, 1.0, 0.8)
	g.audio.play("roar", to, 1.1)
	for k in 40:
		g._particle(to + Vector2(randf() - 0.5, randf() - 0.5) * Vector2(e.w, e.h), Vector2(randf() - 0.5, randf() - 0.5) * 3.0, 20 + randi() % 25, col if k % 2 == 0 else Color(1, 0.8, 0.5), k % 2 == 0, 0.05)

## A pocket its size right beside you, carved through what its blast can cut (HARD <= power; never warded
## stone), opening onto you. Where it will stand (world), or INF if neither side will do.
static func _pocket(g, e, tgt, power: int) -> Vector2:
	var l: Vector2 = g.to_grid(tgt.pos)
	var fy: float = l.y + tgt.h * 0.5
	var bx: float = g.to_grid(e.pos).x
	var sides := [1.0, -1.0] if bx >= l.x else [-1.0, 1.0]
	var gs: int = g.gpu.GS
	for s in sides:
		var x_in: float = l.x + s * tgt.w * 0.5          # (the near edge: right against you)
		var x_out: float = x_in + s * (e.w + 2.0)
		var x0 := int(floor(minf(x_in, x_out)))
		var x1 := int(ceil(maxf(x_in, x_out)))
		var y0 := int(floor(fy - e.h - 1.0))
		var y1 := int(floor(fy - 0.01))
		if x0 < 1 or y0 < 1 or x1 >= gs - 1 or y1 >= gs - 1:
			continue
		var ok := true
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var t: int = g.gtype(xx, yy)
				if g.gsolid(xx, yy) and (t >= Defs.HARD.size() or Defs.HARD[t] > power):
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		var cx: float = x_in + s * (e.w * 0.5 + 2.0)
		var p: Vector2 = g.from_grid(Vector2(cx, fy - e.h * 0.5 - 0.3))
		if not _allowed(g, e, p):
			continue
		# (kept as world points: the grid is laid out round you and moves as you step back)
		var bx0 := float(x0)
		var by0 := float(y0)
		var bx1 := float(x1 + 1) - 0.01
		var by1 := float(y1 + 1) - 0.01
		e.come_box = PackedVector2Array([g.from_grid(Vector2(bx0, by0)), g.from_grid(Vector2(bx1, by0)), g.from_grid(Vector2(bx0, by1)), g.from_grid(Vector2(bx1, by1))])
		return p
	return Vector2.INF

## the pocket cut out cell for cell (an air stamp: a blast would loosen everything within a dozen cells
## of it, and the rock over the pocket fell in and filled it), with a blast's look and sound
static func _carve(g, e) -> void:
	var ns: int = Defs.NS
	var cs := []
	var mid := Vector2.ZERO
	for q in e.come_box:
		cs.append(Build.cell_of(q))
		mid += q * 0.25
	var c0: int = cs[0].x
	var mn := 0
	var mx := 0
	var r0 := 1 << 30
	var r1 := -(1 << 30)
	for c in cs:
		var dc: int = posmod(int(c.x) - c0 + ns / 2, ns) - ns / 2
		mn = mini(mn, dc)
		mx = maxi(mx, dc)
		r0 = mini(r0, int(c.y))
		r1 = maxi(r1, int(c.y))
	var w := mx - mn + 1
	var h := r1 - r0 + 1
	var data := PackedInt32Array()
	data.resize(w * h)
	data.fill(Defs.AIR | 0xFF00)
	g.stamps.append({"x0": posmod(c0 + mn, ns), "y0": r0, "w": w, "h": h, "data": data})
	var size := Vector2(e.come_box[0].distance_to(e.come_box[1]), e.come_box[0].distance_to(e.come_box[2]))
	g.vfx.blast(mid, maxf(size.x, size.y) * 0.5, 0)
	for k in 36:
		var off := Vector2(randf() - 0.5, randf() - 0.5) * size
		g._particle(mid + off, off.normalized() * (0.8 + randf() * 2.0), 20 + randi() % 20, Color(0.45, 0.42, 0.4).lerp(Color(1, 0.6, 0.3), randf() * 0.4), false, 0.09)
	g.audio.play("boom", mid, 1.2, 0.7)
	g.shake = maxf(g.shake, 10.0)

## guardians keep to their lair and leash, wardens to their hall (Vulkhar to his heart: anywhere)
static func _allowed(g, e, p: Vector2) -> bool:
	if e.tether <= 0.0:
		return true
	var off: float = (p - e.home).dot(g.basis_r(atan2(e.home.y, e.home.x)))
	if absf(off) > e.tether:
		return false
	if e.d.get("warden", false):
		var up: float = (p - e.home).dot(e.home.normalized())
		return up > -float(e.h) and up < e.ceil + 12.0
	return true

static func _feet_at(g, e, p: Vector2) -> Vector2:
	return p + g.basis_d(atan2(p.y, p.x)) * (e.h * 0.5)

static func _col(e) -> Color:
	if e.d.has("def"):
		return Color(e.d["def"].get("col", Color(1, 0.6, 0.3)))
	return Color(1, 0.48, 0.16)

static func _name(e) -> String:
	if e.d.has("def"):
		return String(e.d["def"]["name"])
	return "Vulkhar"
