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
			if e.see and e.act_cd <= 0 and dist < float(s["range"]):
				start(e, "windup", int(s["windup"]))
				return true
			return false
		"windup":
			e.vx *= 0.85
			e.vy = e.vy * 0.85 - 0.04
			e.act_t -= 1
			if e.act_t <= 0:
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
