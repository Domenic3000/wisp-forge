extends RefCounted
## Foe behaviours, shared by the foes in Defs.ENEMY: each foe's "ai" entry picks and tunes them, so a
## new foe is mostly data. main.gd's _update_enemies moves the bodies; these decide what a foe knows
## (where it saw or heard you last) and run its attacks as small state machines on Enemy.act:
##   ""        free: main.gd walks or flies it toward where it thinks you are
##   "windup"  the tell: it stops and glows (overlay.gd), so you can see the attack coming
##   "strike" / "air" / "dive"  the attack itself
##   "recover" a moment of weakness afterwards
## Every behaviour returns true while it is driving the body (main.gd then leaves its speed alone).

const SIGHT := 160.0
const MEMORY := 240          # frames a foe keeps hunting where it last saw or heard you
const LOOK_EVERY := 6        # line-of-sight checks are spread out (each foe looks every few frames)
const RALLY := 90.0          # a foe that spots you alerts the others this close to it

## Can a foe at `from` see point `p`? Steps along the line through the collision grid; solid cells
## (walls, the ground, a shut door) block the view.
static func clear_line(g, from: Vector2, p: Vector2) -> bool:
	if not g.in_grid(from, 1.0) or not g.in_grid(p, 1.0):
		return false
	var la: Vector2 = g.to_grid(from)
	var lb: Vector2 = g.to_grid(p)
	var n := int(la.distance_to(lb) / 2.0)
	for k in range(1, n):
		var q := la.lerp(lb, float(k) / float(n))
		if g.gsolid(int(floor(q.x)), int(floor(q.y))):
			return false
	return true

## the foe's eyes: a little above its middle
static func eye(g, e) -> Vector2:
	return e.pos - g.basis_d(atan2(e.pos.y, e.pos.x)) * (e.h * 0.3)

## What the foe knows this frame: e.see (it can see you), e.alert_t (still hunting), e.seen_pos
## (where it last saw or heard you). Spotting you rallies the foes around it.
static func think(g, e, tgt, dist: float) -> void:
	if e.act_cd > 0:
		e.act_cd -= 1
	if e.door_t > 0:
		e.door_t -= 1
	if e.alert_t > 0:
		e.alert_t -= 1
	if tgt.dead:
		e.see = false
		e.alert_t = 0
		return
	if g.calm_foe(e, tgt):
		# (the Amber Totem: a wild creature leaves you be until you strike it)
		e.see = false
		e.alert_t = 0
		return
	var ai: Dictionary = e.d.get("ai", {})
	var sight: float = ai.get("sight", SIGHT)
	e.look_t -= 1
	if e.look_t <= 0:
		e.look_t = LOOK_EVERY
		e.see = dist < sight and clear_line(g, eye(g, e), tgt.pos)
	var close := dist < 26.0                                         # right beside it: it knows
	var heard: bool = dist < sight * 0.7 and g.frame - tgt.cast_frame < 2   # spells are loud
	if e.see or close or heard:
		if e.alert_t <= 0:
			rally(g, e, tgt.pos)
		e.alert_t = MEMORY
		e.seen_pos = tgt.pos

## a foe that spots you warns the others near it
static func rally(g, e, p: Vector2) -> void:
	for o in g.enemies:
		if o == e or o.boss or o.dead:
			continue
		if o.pos.distance_squared_to(e.pos) < RALLY * RALLY and o.alert_t < MEMORY / 2:
			o.alert_t = MEMORY / 2
			o.seen_pos = p

## Where it is heading, in its collision-grid frame (x across, y down): you if it sees you, else the
## spot it last saw or heard you; Vector2.ZERO when it has nothing to go on (it idles).
static func goal(g, e, tgt) -> Vector2:
	if e.see and not tgt.dead:
		return g.to_grid(tgt.pos) - g.to_grid(e.pos)
	if e.alert_t > 0:
		var d: Vector2 = g.to_grid(e.seen_pos) - g.to_grid(e.pos)
		if d.length() < 10.0:
			e.alert_t = mini(e.alert_t, 60)        # nobody here: it gives up soon
		return d
	return Vector2.ZERO

# ------------------------------------------------------------------ attacks ---

## The leap (slimes, mimics): a crouch, then a jump worked out to land on you.
static func leap(g, e, tgt, dx: float, dy: float, gacc: float) -> bool:
	var l: Dictionary = e.d["ai"]["leap"]
	match e.act:
		"":
			if e.see and e.on_ground and e.act_cd <= 0 and absf(dx) < float(l["range"]) and dy > -70.0:
				start(e, "windup", int(l["windup"]))
				return true
			return false
		"windup":
			e.vx *= 0.6
			e.act_t -= 1
			if e.act_t <= 0:
				# time in the air, then the speed that lands it where you are (dy is down)
				var T := clampf(absf(dx) / float(l["speed"]), 14.0, 36.0)
				e.vx = dx / T
				e.vy = clampf((dy - 0.5 * gacc * T * T) / T, -float(l["v"]), 2.0)
				e.act = "air"
				e.act_t = 120
				g.audio.play("jump", e.pos, 0.5)
			return true
		"air":
			e.act_t -= 1
			if (e.on_ground and e.act_t < 115) or e.act_t <= 0:
				e.act = ""
				e.act_cd = int(l["cd"])
			return true
	return false

## The lunge (skeletons): it stops and raises its blade, then lunges and cuts; the cut reaches a
## little past its body. A moment to recover afterwards.
static func melee(g, e, tgt, dx: float, dy: float) -> bool:
	var m: Dictionary = e.d["ai"]["melee"]
	match e.act:
		"":
			if e.see and e.on_ground and e.act_cd <= 0 and absf(dx) < float(m["reach"]) + tgt.w * 0.5 and absf(dy) < 20.0:
				start(e, "windup", int(m["windup"]))
				e.facing = -1 if dx < 0 else 1
				e.hit_done = false
				return true
			return false
		"windup":
			e.vx *= 0.6
			e.act_t -= 1
			if e.act_t <= 0:
				e.act = "strike"
				e.act_t = 12
				e.vx = float(e.facing) * float(m["lunge"])
				e.vy = minf(e.vy, -1.2)
				g.audio.play("swing", e.pos, 0.6)
			return true
		"strike":
			e.act_t -= 1
			if not e.hit_done and not tgt.dead and blade_hits(g, e, tgt, 12.0):
				e.hit_done = true
				g.hurt(tgt, float(m["dmg"]), Vector2(float(e.facing) * 3.0, -1.8), true)
			if e.act_t <= 0:
				e.act = "recover"
				e.act_t = 24
			return true
		"recover":
			e.vx *= 0.8
			e.act_t -= 1
			if e.act_t <= 0:
				e.act = ""
				e.act_cd = int(m["cd"])
			return true
	return false

## does a foe's blade (reaching `reach` cells past its front) touch the mage?
static func blade_hits(g, e, tgt, reach: float) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var o: Vector2 = tgt.pos - e.pos
	var along := o.dot(g.basis_r(a)) * float(e.facing)
	var up := absf(o.dot(g.basis_d(a)))
	return along > -e.w * 0.5 and along < e.w * 0.5 + reach + tgt.w * 0.5 and up < (e.h + tgt.h) * 0.5

## Shooting (archers, imps): a wind-up (a drawn bow, a gathering flame), then a shot aimed where you
## will be, raised to allow for the drop. Returns true while a walker should stand still to shoot.
static func ranged(g, e, tgt, dist: float) -> bool:
	var r: Dictionary = e.d["ai"]["ranged"]
	match e.act:
		"":
			if e.see and e.act_cd <= 0 and dist < float(r["range"]) and dist > 14.0:
				start(e, "windup", int(r["windup"]))
				return not e.d["fly"]
			return false
		"windup":
			e.vx *= 0.7
			e.act_t -= 1
			if e.act_t <= 0:
				e.act = ""
				if e.see or e.alert_t > MEMORY - 30:
					var n := int(r.get("n", 1))
					var spread := 0.0
					# an imp below half health looses a fan of fire
					var bu: Dictionary = e.d["ai"].get("burst", {})
					if not bu.is_empty() and e.hp < e.max_hp * float(bu.get("below", 0.5)):
						n = int(bu["n"])
						spread = float(bu["spread"])
					shoot(g, e, tgt, String(r["proj"]), n, spread, float(r.get("lead", 1.0)))
					e.act_cd = int(r["cd"])
				else:
					e.act_cd = 20          # lost sight of you: it waits for another chance
			return not e.d["fly"]
	return false

## Fire `n` shots of `proj` at the mage, leading a moving target and allowing for the drop.
static func shoot(g, e, tgt, proj: String, n: int, spread: float, lead: float) -> void:
	var pd: Dictionary = Defs.PROJ[proj]
	var sp: float = pd["speed"]
	var from := eye(g, e)
	var ta := atan2(tgt.pos.y, tgt.pos.x)
	var tv: Vector2 = g.basis_r(ta) * tgt.vx + g.basis_d(ta) * tgt.vy
	var t := from.distance_to(tgt.pos) / sp
	var aim: Vector2 = tgt.pos + tv * t * lead
	t = from.distance_to(aim) / sp
	aim += aim.normalized() * (0.5 * float(pd["g"]) * g.gravity_at(from) * t * t)
	var dir := (aim - from).normalized()
	for k in n:
		g._spawn_proj(proj, from, dir.rotated((float(k) - float(n - 1) * 0.5) * spread) * sp, "enemy")
	g.audio.play("bow" if proj == "arrow" else "fire", from, 0.5)

## The swoop (bats): it hangs still a moment, screeching, then dives straight at you, then climbs away.
static func swoop(g, e, tgt, dx: float, dy: float, dist: float) -> bool:
	var s: Dictionary = e.d["ai"]["swoop"]
	match e.act:
		"":
			# (only when its whole body has a clear way down to you: it used to dive into walls)
			if e.see and e.act_cd <= 0 and dist < float(s["range"]) and fly_line(g, e, tgt.pos):
				start(e, "windup", int(s["windup"]))
				return true
			return false
		"windup":
			e.vx *= 0.85
			e.vy = e.vy * 0.85 - 0.04
			e.act_t -= 1
			if e.act_t <= 0:
				if not fly_line(g, e, tgt.pos):
					# you moved behind something: no dive this time
					e.act = ""
					e.act_cd = 20
					return true
				e.aim = Vector2(dx, dy).normalized()
				e.act = "dive"
				e.act_t = int(s["time"])
				g.audio.play("screech", e.pos, 0.5)
			return true
		"dive":
			e.vx = e.aim.x * float(s["speed"])
			e.vy = e.aim.y * float(s["speed"])
			e.act_t -= 1
			if e.act_t <= 0 or e.hit_wall:
				e.act = "recover"
				e.act_t = 34
			return true
		"recover":
			e.vx *= 0.9
			e.vy = e.vy * 0.9 - 0.1          # climbs back out of reach
			e.act_t -= 1
			if e.act_t <= 0:
				e.act = ""
				e.act_cd = int(s["cd"])
			return true
	return false

## The blink (imps): when you close in, it vanishes in a puff and appears again some way off.
static func blink(g, e, tgt, dist: float) -> void:
	var b: Dictionary = e.d["ai"].get("blink", {})
	if b.is_empty():
		return
	if e.blink_cd > 0:
		e.blink_cd -= 1
		return
	if dist > float(b["near"]) or tgt.dead:
		return
	for tries in 12:
		var ang := randf() * TAU
		var p: Vector2 = tgt.pos + Vector2(cos(ang), sin(ang)) * randf_range(48.0, 75.0)
		if not g.in_grid(p, 12.0):
			continue
		var l: Vector2 = g.to_grid(p)
		if g.box_solid(l.x - e.w * 0.5 - 2.0, l.y - e.h * 0.5 - 2.0, e.w + 4.0, e.h + 4.0):
			continue
		puff(g, e.pos, Color(0.9, 0.3, 0.1))
		e.pos = p
		e.vx = 0.0
		e.vy = 0.0
		e.act = ""
		puff(g, p, Color(1.0, 0.5, 0.15))
		e.blink_cd = int(b["cd"])
		g.audio.play("blink", p, 0.6)
		return

static func start(e, act: String, t: int) -> void:
	e.act = act
	e.act_t = t
	e.act_len = t

static func puff(g, p: Vector2, c: Color) -> void:
	for k in 18:
		g._particle(p, Vector2(randf() - 0.5, randf() - 0.5).normalized() * (0.4 + randf()), 14 + randi() % 14, c, true, 0.0)
	g.lights.append([p, 20.0, c])

## how brightly a foe glows with its tell (0..1): through a wind-up it flickers brighter and brighter
static func tell(e) -> float:
	if e.act != "windup":
		return 0.0
	var k := 1.0 - float(e.act_t) / maxf(float(e.act_len), 1.0)
	return clampf(0.35 + 0.65 * k, 0.0, 1.0) * (1.0 if (e.act_t / 3) % 2 == 0 else 0.75)

# ------------------------------------------------------------ other levels ---
## Getting to you when you're on another level, for every foe that walks or hops: UP onto a
## platform or a ledge above (it stands under a one-way platform and jumps up through it; beside
## a solid ledge it jumps straight up and moves over once its feet clear the top), or DOWN
## (through the platform it stands on, or off an edge or through a gap in the floor). A plan is
## found by looking about (`_plan_up`, `_plan_down`, at most every half second) and kept for a few
## seconds in `e.climb_*`; each frame this takes it to the take-off point and jumps or drops
## there. Returns the way it should head (-1 or 1), or 0 with no such plan (it walks on as
## usual). gl: where it's going, from it (grid cells, y down); jump_v: its strongest jump; tol:
## how near the take-off point counts (hoppers land less exactly); may_plan: false keeps it from
## starting a new plan (an archer that can see you shoots instead).
static func climb(g, e, gl: Vector2, jump_v: float, gacc: float, tol := 2.5, may_plan := true) -> float:
	if e.climb_cd > 0:
		e.climb_cd -= 1
	var l: Vector2 = g.to_grid(e.pos)
	var feet: float = l.y + e.h * 0.5
	if e.climb_t > 0:
		e.climb_t -= 1
		if e.climb_t == 0:
			e.climb_cd = 90                     # (it took too long: try something else for a while)
			return 0.0
		var to: Vector2 = g.to_grid(e.climb_to)
		var from: Vector2 = g.to_grid(e.climb_from)
		if e.climb_up:
			if e.on_ground and feet < to.y + 3.0:
				return _climb_end(e, 1)             # up there (or higher still): look again at once
			if e.on_ground and e.climb_air:
				return _climb_end(e, 90)            # came back down without making it
			if e.on_ground:
				if absf(l.x - from.x) <= tol:
					# the take-off: (nearly) straight up, just high enough to clear the top
					e.vy = -minf(jump_v, sqrt(2.0 * gacc * (feet - to.y + 8.0)))
					e.vx = clampf((to.x - l.x) * 0.02, -0.3, 0.3)
					e.climb_air = true
					return signf(to.x - l.x)
				return signf(from.x - l.x)
			# in the air: once its feet are over the top, over onto it
			if feet < to.y - 1.0:
				e.vx = clampf((to.x - l.x) * 0.2, -1.8, 1.8)
			return signf(to.x - l.x) if absf(to.x - l.x) > 0.5 else float(e.facing)
		# going down
		if feet > from.y + 6.0:
			return _climb_end(e, 30)                # down
		if e.on_ground and absf(l.x - from.x) <= tol:
			if e.on_platform:
				e.drop_t = 14                       # through the platform
			return signf(to.x - l.x) if absf(to.x - l.x) > 0.5 else float(e.facing)
		return signf(from.x - l.x) if absf(from.x - l.x) > 0.5 else float(e.facing)
	if not may_plan or e.climb_cd > 0 or not e.on_ground or gl == Vector2.ZERO:
		return 0.0
	e.climb_cd = 30                                 # (looking about isn't free: not every frame)
	var made := false
	if gl.y < -14.0 and (absf(gl.x) < 90.0 or e.hit_wall):
		made = _plan_up(g, e, l, feet, gl, jump_v, gacc)
	elif gl.y > 16.0 and absf(gl.x) < 56.0:
		made = _plan_down(g, e, l, feet, gl)
	if not made:
		return 0.0
	e.climb_t = 240
	e.climb_air = false
	var f2: Vector2 = g.to_grid(e.climb_from)
	return signf(f2.x - l.x) if absf(f2.x - l.x) > 0.5 else float(e.facing)

static func _climb_end(e, cd: int) -> float:
	e.climb_t = 0
	e.climb_cd = cd
	e.climb_air = false
	return 0.0

## the horizontal way (cells) from it to its take-off point (0 with no plan): a hopper hops there
static func climb_gap(g, e) -> float:
	if e.climb_t <= 0:
		return 0.0
	return (g.to_grid(e.climb_from) - g.to_grid(e.pos)).x

## can it stand on cell (x, y)? (solid ground, or a one-way platform)
static func _standable(g, x: int, y: int) -> bool:
	return g.gtype(x, y) == Defs.SCAFFOLD or g.gsolid(x, y)

## the same, a row either way (the collision grid is flat: level ground curves away in it, by a
## row every ten or fifteen cells far from the middle)
static func _standable3(g, x: int, y: int) -> bool:
	return _standable(g, x, y) or _standable(g, x, y + 1) or _standable(g, x, y - 1)

## would a step or two more that way take it off an edge (no ground a few rows down; a wall
## ahead doesn't count, walking deals with those)? A foe whose goal is above stays on its level.
static func edge_ahead(g, e, dir: float) -> bool:
	var l: Vector2 = g.to_grid(e.pos)
	var feet: float = l.y + e.h * 0.5
	var x := int(floor(l.x + dir * (e.w * 0.5 + 2.0)))
	if g.gsolid(x, int(floor(feet)) - 2):
		return false
	return _ground(g, x, feet, int(e.step_h) + 1, 6) == INF

## Somewhere above to jump up to, nearer the height of its goal: each column within CLIMB_LOOK
## cells is searched upward (as high as it can jump) for tops (something to stand on with open
## space over it); the best few are checked properly: room to stand there, and a take-off point
## on its own level from which a straight jump up has a clear way (right under it for a one-way
## platform; beside the edge nearest it for a solid ledge), with room at the top to move over.
const CLIMB_LOOK := 54
static func _plan_up(g, e, l: Vector2, feet: float, gl: Vector2, jump_v: float, gacc: float) -> bool:
	var reach := minf(jump_v * jump_v / (2.0 * maxf(gacc, 0.001)) - 6.0, 64.0)
	if reach < 8.0:
		return false
	var fx := int(floor(l.x))
	var fy := int(floor(feet))           # (the row under its feet)
	var gx := l.x + gl.x
	var gy := feet + gl.y
	var tops := []
	for k in range(-CLIMB_LOOK, CLIMB_LOOK + 1, 3):
		var cx := fx + k
		var stand_y := fy
		var open := 0
		for ry in range(fy - 1, fy - int(reach) - 5, -1):
			if _standable(g, cx, ry):
				stand_y = ry
				open = 0
			else:
				open += 1
				if open == 4 and stand_y == ry + 4 and stand_y <= fy - 5:
					tops.append([absf(float(stand_y) - gy) + 0.35 * absf(float(cx) - gx) + 0.15 * absf(float(k)), cx, stand_y])
	tops.sort_custom(func(p, q): return p[0] < q[0])
	e.climb_why = "%d tops (reach %.0f):" % [tops.size(), reach]
	for n in mini(tops.size(), 5):
		var cx2: int = tops[n][1]
		var top: int = tops[n][2]
		e.climb_why += " %d,%d" % [cx2 - fx, top - fy]
		if feet - float(top) + 6.0 > reach + 6.0:
			e.climb_why += "R"
			continue
		if g.box_solid(float(cx2) - e.w * 0.5, float(top) - e.h, e.w, e.h):
			e.climb_why += "B"
			continue                          # no room to stand there
		var ledge: bool = g.gsolid(cx2, top)
		var takeoffs := []
		if not ledge:
			takeoffs.append([float(cx2), float(cx2)])       # right under a platform: up through it
		# beside the edge of it nearest the foe (or the other one)
		var s0 := signf(l.x - float(cx2)) if absf(l.x - float(cx2)) > 0.5 else 1.0
		for s in [s0, -s0]:
			var ex := cx2
			var steps := 0
			while steps < 40 and _standable3(g, ex + int(s), top):
				ex += int(s)
				steps += 1
			if steps >= 40:
				continue
			var tx: float = float(ex) + s * (e.w * 0.5 + 2.0)
			var land: float = float(ex) - s * (e.w * 0.5 + 2.0)
			takeoffs.append([tx, land])
		for tk in takeoffs:
			var tx2: float = tk[0]
			var land2: float = tk[1]
			if not _footing(g, e, land2, top):
				e.climb_why += "F"
				continue
			if _can_jump(g, e, l, feet, tx2, land2, top):
				e.climb_up = true
				e.climb_to = g.from_grid(Vector2(land2, float(top)))
				e.climb_from = g.from_grid(Vector2(tx2, feet))
				return true
	return false

## enough to stand on at `x` on row `top` (most of its width: not the top of a thin post; a row
## either way, since the collision grid is flat and the planet's level ground curves away in it)
static func _footing(g, e, x: float, top: int) -> bool:
	var x0 := int(floor(x - e.w * 0.5))
	var x1 := int(floor(x + e.w * 0.5 - 0.001))
	var n := 0
	for xx in range(x0, x1 + 1):
		if _standable3(g, xx, top):
			n += 1
	return float(n) >= (x1 - x0 + 1) * 0.6

## the top of the ground in column x near height y (grid rows, y down): the first cell it could
## stand on with open space over it, from `up` rows above y to `down` rows below; INF if none
static func _ground(g, x: int, y: float, up: int, down: int) -> float:
	var y0 := int(floor(y)) - up
	for yy in range(y0, int(floor(y)) + down + 1):
		if _standable(g, x, yy) and not _standable(g, x, yy - 1):
			return float(yy)
	return INF

## Walking along its own level from where it is to column tx, following the ground (it curves away
## in the flat collision grid, and has its own steps and slopes): the height of the ground at tx,
## or INF where the way has a gap or something it can't step over.
static func _walk_to(g, e, l: Vector2, feet: float, tx: float) -> float:
	var s := signf(tx - l.x)
	var f := feet
	var span := absf(tx - l.x)
	var n := int(ceil(span / 2.0))
	for i in range(1, n + 1):
		var x: float = l.x + s * minf(float(i) * 2.0, span)
		var gnd := _ground(g, int(floor(x)), f, int(e.step_h) + 1, 3)
		if gnd == INF:
			return INF
		if g.box_solid(x - e.w * 0.5, gnd - e.h - 0.5, e.w, e.h - 1.0):
			return INF
		f = gnd
	return f

## from take-off point tx (reached along its own level) straight up past `top`, then across to `land`
static func _can_jump(g, e, l: Vector2, feet: float, tx: float, land: float, top: int) -> bool:
	var ft := _walk_to(g, e, l, feet, tx)
	if ft == INF:
		e.climb_why += "p"
		return false
	var apex: float = float(top) - e.h - 3.0
	if g.box_solid(tx - e.w * 0.5, apex, e.w, ft - apex - 1.0):
		e.climb_why += "v"
		return false
	if g.box_solid(minf(tx, land) - e.w * 0.5, apex, absf(land - tx) + e.w, e.h):
		e.climb_why += "a"
		return false
	return true

## Somewhere to get down: standing on a platform it drops right here; otherwise it follows its
## floor either way (toward its goal first) to a gap or an edge wide enough to fall through (or a
## platform to drop through), with room below.
static func _plan_down(g, e, l: Vector2, feet: float, gl: Vector2) -> bool:
	if e.on_platform:
		e.climb_up = false
		e.climb_from = g.from_grid(Vector2(l.x, feet))       # (its feet: "down" is measured from them)
		e.climb_to = g.from_grid(Vector2(l.x, feet + e.h))
		return true
	var s0 := signf(gl.x) if absf(gl.x) > 0.5 else 1.0
	for s in [s0, -s0]:
		var f := feet
		var gap := 0.0
		for i in range(1, int(CLIMB_LOOK / 2.0) + 1):
			var x: float = l.x + s * float(i) * 2.0
			var gnd := _ground(g, int(floor(x)), f, int(e.step_h) + 1, 3)
			if gnd == INF or g.gtype(int(floor(x)), int(gnd)) == Defs.SCAFFOLD:
				gap += 2.0
				if gap >= e.w + 2.0:
					var cx: float = x - s * (e.w * 0.5 + 1.0)
					if g.box_solid(cx - e.w * 0.5, f + 1.0, e.w, e.h):
						break                             # no room to fall into
					e.climb_up = false
					e.climb_from = g.from_grid(Vector2(cx, f))
					e.climb_to = g.from_grid(Vector2(cx, f + e.h))
					return true
				continue
			gap = 0.0
			if g.box_solid(x - e.w * 0.5, gnd - e.h - 0.5, e.w, e.h - 1.0):
				break                                     # a wall: not this way
			f = gnd
	return false

# ------------------------------------------------------------- pathfinding ---
const Nav := preload("res://scripts/nav.gd")

## Walking (or hopping) to the feet point `to` (world) along the nav graph (nav.gd): returns the way
## to head (-1, 0 or 1), and makes the jumps and drops along the way itself (straight up from the
## take-off spot, then over once its feet clear the top; across a gap; down through the platform it
## stands on). 0: it's there, or as near as it can get, so it stands: it never pushes on against a
## wall. NAN: no graph for it yet (the caller gets about its own way meanwhile).
## jump_v: its strongest jump; tol: how near the take-off spot counts; doors: it opens doors.
## e.path_ok says whether the way it has gets all the way to `to`.
static func nav_walk(g, e, to: Vector2, jump_v: float, gacc: float, tol := 3.0, doors := false) -> float:
	var nav = g.nav_of_grid()
	var jump_h := jump_v * jump_v / (2.0 * maxf(gacc, 0.01)) - 4.0
	var key := Nav.key_for("walk", e.w, e.h, jump_h, doors)
	nav.ask(key)
	if not nav.has(key):
		return NAN
	var a := atan2(e.pos.y, e.pos.x)
	var feet: Vector2 = e.pos + g.basis_d(a) * (e.h * 0.5)
	if e.hold_t > 0:
		e.hold_t -= 1
		return 0.0
	if e.wall_t > 50 and not e.nav_air:
		# pushing at a wall it thought it could pass (something just built, a door it can't open):
		# it stops, and looks for another way in a moment
		e.wall_t = 0
		e.path = PackedVector2Array()
		e.path_t = 0
		e.hold_t = 20
		return 0.0
	e.path_t -= 1
	if e.path_t <= 0 or e.path_key != key or to.distance_to(e.path_goal) > 16.0:
		e.path = nav.walk_path(key, feet, to)
		e.path_i = 1
		e.path_t = 24 + randi() % 12
		e.path_goal = to
		e.path_key = key
		e.path_ok = e.path.size() > 0 and e.path[e.path.size() - 1].distance_to(to) < 14.0
	e.nav_dx = 0.0
	if e.path.is_empty():
		e.nav_air = false
		if e.in_liquid or not e.on_ground:
			return NAN               # (swimming, or in the air: the old way)
		# standing somewhere the graph has no room for it (down a shaft a little narrower than the
		# map's 4-cell blocks think it needs, wedged): it doesn't run at the walls; it stands, and now
		# and then jumps straight up to try to get out
		e.lost_t += 1
		if e.lost_t % 75 == 0:
			e.vy = -jump_v
		return 0.0
	e.lost_t = 0
	if e.path.size() < 2:
		e.nav_air = false
		return 0.0
	var l: Vector2 = g.to_grid(e.pos)
	var fy: float = l.y + e.h * 0.5
	while e.path_i < e.path.size():
		var wq: Vector2 = g.to_grid(e.path[e.path_i])
		if absf(wq.x - l.x) < 3.0 and absf(wq.y - fy) < 4.5:
			e.path_i += 1
		else:
			break
	if e.path_i >= e.path.size():
		e.nav_air = false
		return 0.0
	var wp: Vector2 = g.to_grid(e.path[e.path_i])
	var prev: Vector2 = g.to_grid(e.path[e.path_i - 1])
	var rise: float = fy - wp.y
	var dirx := signf(wp.x - l.x)
	e.nav_dx = wp.x - l.x                # (hoppers size their hops by it)
	if e.nav_air:
		if e.on_ground and e.vy >= 0.0:
			e.nav_air = false
		else:
			# on its way up: straight up, then over once its feet are above where it lands
			if e.nav_gap or fy < wp.y + 1.5:
				e.vx = dirx * maxf(absf(e.vx), 1.3)
			else:
				e.vx *= 0.6
			return dirx
	var gap := absf(wp.x - prev.x) > 6.0 and absf(rise) < 7.0
	if rise > float(e.step_h) + 1.5 or gap:
		# a jump, from the take-off spot (the last place on the way it stood)
		if absf(prev.x - l.x) > tol:
			e.nav_dx = prev.x - l.x
			return signf(prev.x - l.x)
		if e.on_ground:
			var hgt := maxf(rise, 0.0) + (8.0 if gap else 5.0)
			e.vy = -minf(jump_v, sqrt(2.0 * gacc * hgt))
			var air: float = 2.0 * -e.vy / maxf(gacc, 0.01)
			e.vx = dirx * clampf(absf(wp.x - l.x) / maxf(air, 1.0), 0.8, 3.0) if gap else 0.0
			e.nav_air = true
			e.nav_gap = gap
		return 0.0
	if rise < -6.0 and e.on_platform and absf(wp.x - l.x) < 5.0:
		e.drop_t = 12                # down through the platform
		return 0.0
	return dirx if absf(wp.x - l.x) > 1.0 else 0.0

## Could a walker get to the feet point `to` at all? (its own way about, not just near: where it
## could stand nearest that spot is no further off than a quarter of its width and ten cells.) True
## with no graph yet.
static func can_reach(g, e, to: Vector2, jump_v: float, gacc: float, doors := false) -> bool:
	var nav = g.nav_of_grid()
	var key := Nav.key_for("walk", e.w, e.h, jump_v * jump_v / (2.0 * maxf(gacc, 0.01)) - 4.0, doors)
	if not nav.has(key):
		return true
	var feet: Vector2 = e.pos + g.basis_d(atan2(e.pos.y, e.pos.x)) * (e.h * 0.5)
	var p: PackedVector2Array = nav.walk_path(key, feet, to)
	return p.size() > 0 and p[p.size() - 1].distance_to(to) < 10.0 + e.w * 0.25

## A flier's heading toward `to` (world; swim: a swimmer, in water only): straight there when the way
## is open, else along the nav grid (the furthest point of its way it can fly straight to). In the
## local frame (x along the ground, y down); ZERO when it can't get anywhere nearer. NAN-free: with no
## graph yet it's the straight heading.
static func nav_fly(g, e, to: Vector2, swim := false) -> Vector2:
	var nav = g.nav_of_grid()
	var key := Nav.key_for("swim" if swim else "fly", e.w, e.h)
	nav.ask(key)
	var a := atan2(e.pos.y, e.pos.x)
	var r: Vector2 = g.basis_r(a)
	var dn: Vector2 = g.basis_d(a)
	var o: Vector2 = to - e.pos
	var direct := Vector2(o.dot(r), o.dot(dn))
	if not nav.has(key):
		return direct.normalized() if direct.length() > 0.5 else Vector2.ZERO
	e.path_t -= 1
	if e.path_t <= 0 or e.path_key != key or to.distance_to(e.path_goal) > 16.0:
		e.fly_open = nav.fly_clear(key, e.pos, to)
		e.path = PackedVector2Array() if e.fly_open else nav.fly_path(key, e.pos, to)
		e.path_i = 1
		e.path_t = 12 + randi() % 8
		e.path_goal = to
		e.path_key = key
		e.path_ok = e.fly_open or (e.path.size() > 0 and e.path[e.path.size() - 1].distance_to(to) < 14.0)
	if e.fly_open or e.path.is_empty():
		# (straight there: nothing in the way, or it isn't anywhere the grid has room for it, wedged)
		return direct.normalized() if direct.length() > 0.5 else Vector2.ZERO
	while e.path_i < e.path.size() and e.path[e.path_i].distance_to(e.pos) < 5.0:
		e.path_i += 1
	if e.path_i >= e.path.size():
		return Vector2.ZERO
	# (cutting corners: the furthest of the next few points it can fly straight to)
	var ti: int = e.path_i
	if g.frame % 4 == e.look_t % 4:
		for k in range(e.path_i + 1, mini(e.path_i + 4, e.path.size())):
			if nav.fly_clear(key, e.pos, e.path[k]):
				ti = k
		e.path_i = ti
	var o2: Vector2 = e.path[ti] - e.pos
	return Vector2(o2.dot(r), o2.dot(dn)).normalized()

## can a flier fly straight at a world point without hitting anything? (true with no graph yet)
static func fly_line(g, e, to: Vector2) -> bool:
	var nav = g.nav_of_grid()
	var key := Nav.key_for("fly", e.w, e.h)
	nav.ask(key)
	return nav.fly_clear(key, e.pos, to)
