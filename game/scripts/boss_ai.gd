## The biome guardians' behaviour (Defs.BOSSES): put together from a way of getting around and a set of
## moves, so every guardian is a different mix of the same parts.
##
## Getting around (`go`): walk (on the ground toward you), hop (a toad's leaps), fly (circling above
## you), slither (a serpent weaving through the air on its trail of segments), burrow (under the ground,
## invisible and untouchable, breaching where you stand).
##
## Moves, each a little state machine on Enemy.act: "windup" (the tell: it glows, overlay.gd), then
## "go", then "recover":
##   charge  lowers its head, then runs at you; slamming into a wall stuns it and breaks the wall
##   slam    crouches, leaps to land on you; the landing breaks the ground and knocks you flying
##   spit    shots that lead you (Defs.PROJ: venom, mudball, ice, rock, sandball, spore)
##   rain    a roar, then shots fall on you from above
##   erupt   marks the ground under you, then it bursts up (thorns, roots) and breaks the ground
##   roar    a wave that throws you back
##   summon  calls foes to its side (only so many at once)
##   cloud   a lingering cloud of spores where you stand that hurts while you're in it
##   dive    hovers, then dives straight at you, then climbs away (fliers)
##   gust    a beat of its wings that throws you back (fliers)
##   breach  (burrowers) bursts out of the ground under you, spitting, and dives back in
## Moves named with a trailing digit ("spit2") are the same move with other settings. Below half its
## health it is enraged: faster, and its `rage` moves join the others.
extends RefCounted

const FoeAI := preload("res://scripts/foe_ai.gd")
const WAKE := 110.0            # (you have to come into its lair to wake it)

static func tick(g, e, tgt, dist: float, dx: float, dy: float, gacc: float, slow_f: float) -> void:
	var bd: Dictionary = e.d["def"]
	var go: String = bd["go"]
	if not e.awake:
		if dist < WAKE and not tgt.dead and not g.test_calm:
			wake(g, e)
		else:
			_rest(g, e, gacc)
			return
	if tgt.dead:
		e.vx *= 0.9
		_rest(g, e, gacc)
		return
	e.see = true
	if not e.raged and e.hp < e.max_hp * 0.5:
		e.raged = true
		g.ui.toast("%s is enraged!" % bd["name"], bd["col"], 3.0)
		g.audio.play("roar", e.pos, 1.0)
		g.shake = maxf(g.shake, 8.0)
	var spd: float = float(bd["speed"]) * (1.25 if e.raged else 1.0) * slow_f
	if e.act != "":
		_run(g, e, tgt, dx, dy, dist, gacc, spd)
	else:
		if e.act_cd > 0:
			e.act_cd -= 1
		_get_around(g, e, tgt, dx, dy, dist, gacc, spd, go)
		if e.act_cd <= 0:
			_begin(g, e, tgt, dx, dy, dist)
	if go == "slither" or go == "burrow":
		_trail(e)
	if go != "fly" and go != "slither" and go != "burrow" and not e.leaping:
		e.vy += gacc

static func wake(g, e) -> void:
	var bd: Dictionary = e.d["def"]
	e.awake = true
	e.act_cd = 60
	g.ui.toast("%s, %s, awakens!" % [String(bd["name"]).to_upper(), String(bd["title"]).to_upper()], bd["col"], 4.0)
	g.audio.play("roar", e.pos, 1.2)
	g.shake = maxf(g.shake, 10.0)

## asleep (or with nobody to fight): settled where it is; a burrower waits under the sand
static func _rest(g, e, gacc: float) -> void:
	var go: String = e.d["def"]["go"]
	if go == "burrow":
		e.under = true
		e.vx = 0.0
		e.vy = 0.0
		_trail(e)
	elif go == "fly" or go == "slither":
		e.vx *= 0.9
		e.vy *= 0.9
		if go == "slither":
			_trail(e)
	else:
		e.vy += gacc

# ------------------------------------------------------------ getting around ---
static func _get_around(g, e, tgt, dx: float, dy: float, dist: float, gacc: float, spd: float, go: String) -> void:
	e.t += 1.0
	match go:
		"walk":
			e.facing = -1 if dx < 0 else 1
			if absf(dx) > 26.0:
				var nd: float = g._walker_nav(e, dx, dist, 0.5, 5.0, gacc)
				if e.on_ground:
					e.vx += (nd * spd - e.vx) * 0.12
			elif e.on_ground:
				e.vx *= 0.8
		"hop":
			e.facing = -1 if dx < 0 else 1
			if e.on_ground:
				e.vx *= 0.7
				if int(e.t) % 70 == 0:
					e.vx = signf(dx) * spd * 2.0
					e.vy = -4.0
		"fly", "slither":
			# circle above you (a serpent weaves wider and lower)
			var up: Vector2 = tgt.pos.normalized()
			var side: Vector2 = g.basis_r(atan2(tgt.pos.y, tgt.pos.x))
			var sway := sin(e.t * (0.013 if go == "slither" else 0.01))
			var want: Vector2 = tgt.pos + up * (36.0 if go == "slither" else 58.0) + side * sway * (95.0 if go == "slither" else 70.0)
			_steer(g, e, want, spd, 0.08)
		"burrow":
			# under the ground toward the spot under you
			e.under = true
			var below: Vector2 = tgt.pos.normalized() * (tgt.pos.length() - 26.0)
			var to: Vector2 = below - e.pos
			if to.length() > 1.0:
				e.pos += to.normalized() * minf(spd, to.length())
			e.facing = -1 if dx < 0 else 1
			_rumble(g, e)

## fliers: ease toward a point (world velocity -> the body's own frame)
static func _steer(g, e, want: Vector2, spd: float, acc: float) -> void:
	var a := atan2(e.pos.y, e.pos.x)
	var o: Vector2 = want - e.pos
	var v := o.normalized() * minf(spd, o.length() * 0.05 + 0.3)
	var lx: float = v.dot(g.basis_r(a))
	var ly: float = v.dot(g.basis_d(a))
	e.vx += (lx - e.vx) * acc
	e.vy += (ly - e.vy) * acc
	if absf(e.vx) > 0.2:
		e.facing = 1 if e.vx > 0.0 else -1

## a burrower moving under you: the ground above it trembles
static func _rumble(g, e) -> void:
	if g.frame % 3 != 0:
		return
	var up: Vector2 = e.pos.normalized()
	var p: Vector2 = e.pos
	for k in 40:
		p += up
		if Defs.KIND[g.type_at(p)] == Defs.K_EMPTY:
			break
	g._particle(p + g.basis_r(atan2(p.y, p.x)) * (randf() - 0.5) * 10.0, up * (0.3 + randf() * 0.5), 20 + randi() % 14, Color(0.85, 0.72, 0.5), false, 0.04)

## a serpent's segments follow its head, each a fixed step behind the one before
static func _trail(e) -> void:
	var n: int = int(e.d["def"]["body"].get("segs", 10))
	var step := float(e.d["def"]["body"]["rad"]) * 0.95
	if e.trail.size() != n:
		e.trail.resize(n)
		for k in n:
			e.trail[k] = e.pos + Vector2(-e.pos.y, e.pos.x).normalized() * float(k + 1) * step
	var prev: Vector2 = e.pos
	for k2 in n:
		var p: Vector2 = e.trail[k2]
		var o := p - prev
		var sk := step * (0.8 if k2 > 0 else 1.0)
		if o.length() > sk:
			p = prev + o.normalized() * sk
		e.trail[k2] = p
		prev = p

# ------------------------------------------------------------------ moves ---
## the moves it has now (its rage moves join them below half health)
static func _moves(e) -> Array:
	var bd: Dictionary = e.d["def"]
	var out: Array = bd["moves"].keys()
	if e.raged:
		out.append_array(bd["rage"].keys())
	return out

static func _params(e, mv: String) -> Dictionary:
	var bd: Dictionary = e.d["def"]
	if bd["moves"].has(mv):
		return bd["moves"][mv]
	return bd["rage"].get(mv, {})

## the kind of move ("spit2" is a spit)
static func kind_of(mv: String) -> String:
	return mv.rstrip("0123456789")

## Picks the next move: in turn, skipping the ones that don't suit where you are.
static func _begin(g, e, tgt, dx: float, dy: float, dist: float) -> void:
	var ms := _moves(e)
	if ms.is_empty():
		return
	for k in ms.size():
		e.mi = (e.mi + 1) % ms.size()
		var mv: String = ms[e.mi]
		if _suits(e, kind_of(mv), dx, dy, dist):
			e.move = mv
			e.moves_done += 1
			var wt := {"charge": 40, "slam": 30, "spit": 26, "rain": 45, "erupt": 45, "roar": 32, "summon": 30,
				"cloud": 30, "dive": 30, "gust": 30, "breach": 50}
			FoeAI.start(e, "windup", int(float(wt.get(kind_of(mv), 30)) * (0.75 if e.raged else 1.0)))
			e.hit_done = false
			e.spot = tgt.pos
			if kind_of(mv) == "erupt":
				e.spot = _ground_under(g, tgt.pos)
			return

static func _suits(e, k: String, dx: float, dy: float, dist: float) -> bool:
	match k:
		"charge":
			return e.on_ground and absf(dy) < 30.0 and absf(dx) > 30.0 and absf(dx) < 190.0
		"slam":
			return e.on_ground and dist < 170.0
		"spit":
			return dist > 30.0 and dist < 240.0
		"dive":
			return dist < 200.0
		"roar", "gust":
			return dist < 120.0
		"summon":
			return true
	return dist < 230.0

## where the ground is under a point (the first solid cell going down, up to 50 cells)
static func _ground_under(g, p: Vector2) -> Vector2:
	var dn: Vector2 = -p.normalized()
	var q := p
	for k in 50:
		var kd: int = Defs.KIND[g.type_at(q + dn)]
		if kd == Defs.K_SOLID or kd == Defs.K_POWDER:
			return q
		q += dn
	return p

static func _run(g, e, tgt, dx: float, dy: float, dist: float, gacc: float, spd: float) -> void:
	var mv: String = e.move
	var k: String = kind_of(mv)
	var pr := _params(e, mv)
	var bd: Dictionary = e.d["def"]
	var a := atan2(e.pos.y, e.pos.x)
	var up: Vector2 = e.pos.normalized()
	e.act_t -= 1
	match e.act:
		"windup":
			# the tell: it gathers itself (and shows where it will strike)
			if k == "dive" or bd["go"] == "fly" or bd["go"] == "slither":
				e.vx *= 0.88
				e.vy = e.vy * 0.88 - 0.03
			elif k != "breach":
				e.vx *= 0.8
				e.facing = -1 if dx < 0 else 1
			if k == "erupt" and g.frame % 2 == 0:
				g._particle(e.spot + g.basis_r(atan2(e.spot.y, e.spot.x)) * (randf() - 0.5) * 14.0, up * (0.2 + randf() * 0.6), 16, pr.get("col", Color(0.6, 0.5, 0.3)), true, 0.0)
			if k == "breach":
				_get_around(g, e, tgt, dx, dy, dist, gacc, spd * 1.4, "burrow")
				_rumble(g, e)
			if e.act_t <= 0:
				_strike(g, e, tgt, dx, dy, dist, k, pr, spd)
		"go":
			_going(g, e, tgt, dx, dy, k, pr, spd, gacc)
		"recover":
			e.vx *= 0.85
			if bd["go"] == "fly" or bd["go"] == "slither":
				e.vy = e.vy * 0.9 - 0.05
			if e.act_t <= 0:
				e.act = ""
				e.move = ""
				e.act_cd = int((50.0 if e.raged else 80.0) * (0.6 + randf() * 0.6))

## the moment the wind-up ends
static func _strike(g, e, tgt, dx: float, dy: float, dist: float, k: String, pr: Dictionary, spd: float) -> void:
	var up: Vector2 = e.pos.normalized()
	var ta := atan2(tgt.pos.y, tgt.pos.x)
	match k:
		"charge":
			FoeAI.start(e, "go", 75)
			e.aim = Vector2(signf(dx), 0.0)
			e.facing = int(e.aim.x)
		"slam":
			# a leap aimed to land on you
			var gg: float = g.gravity_at(e.pos)
			var air: float = 2.0 * 5.6 / (0.17 * gg)
			e.vx = clampf(dx / air, -4.5, 4.5) if pr.get("far", false) else clampf(dx / air, -3.0, 3.0)
			e.vy = -5.6
			e.leaping = true
			FoeAI.start(e, "go", 140)
		"spit":
			var n: int = int(pr.get("n", 3)) + (1 if e.raged else 0)
			FoeAI.shoot(g, e, tgt, String(pr.get("proj", "efire")), n, float(pr.get("spread", 0.2)), 0.8)
			FoeAI.start(e, "recover", 24)
		"rain":
			FoeAI.start(e, "go", 4 * (int(pr.get("n", 6)) + (3 if e.raged else 0)))
			g.audio.play("roar", e.pos, 0.8)
		"erupt":
			_burst(g, e.spot, 9.0, 2, pr.get("col", Color(0.5, 0.4, 0.3)))
			if tgt.pos.distance_to(e.spot) < 16.0:
				g.hurt(tgt, float(e.d["dmg"]) * 1.4, Vector2(0.0, -5.0), true)
			# enraged, it strikes again where you are now
			if e.raged and not e.raged_burst:
				e.raged_burst = true
				e.spot = _ground_under(g, tgt.pos)
				FoeAI.start(e, "windup", 26)
				return
			e.raged_burst = false
			FoeAI.start(e, "recover", 30)
		"roar", "gust":
			if dist < 140.0:
				g.hurt(tgt, 6.0, Vector2(signf(dx) * 6.0, -3.0), true)
			for kk in 40:
				var dirv := Vector2.from_angle(randf() * TAU)
				g._particle(e.pos + dirv * 8.0, dirv * (1.5 + randf()), 24, Color(1, 1, 1, 0.8) if k == "gust" else e.d["def"]["col"], k == "roar", 0.0)
			g.shake = maxf(g.shake, 9.0)
			g.audio.play("roar" if k == "roar" else "levitate", e.pos, 1.0)
			FoeAI.start(e, "recover", 34)
		"summon":
			var mine := 0
			for o in g.enemies:
				if o.summoner == e and not o.dead:
					mine += 1
			var want: int = mini(int(pr.get("n", 2)), int(pr.get("max", 4)) - mine)
			for s in want:
				var at: Vector2 = e.pos + g.basis_r(atan2(e.pos.y, e.pos.x)) * (randf() - 0.5) * 40.0 + up * 10.0
				var m = g.spawn_enemy(String(pr.get("type", "slime")), g.free_spot(at, 12.0, 10.0, 12))
				m.summoner = e
				FoeAI.puff(g, m.pos, e.d["def"]["col"])
			FoeAI.start(e, "recover", 30)
		"cloud":
			g.boss_clouds.append({"pos": tgt.pos, "r": 22.0, "t": 300, "col": e.d["def"]["col"]})
			FoeAI.start(e, "recover", 24)
		"dive":
			e.aim = (tgt.pos - e.pos).normalized()
			FoeAI.start(e, "go", 42)
			g.audio.play("roar", e.pos, 0.7)
		"breach":
			# out of the ground under you: a crater, a burst of sand at you, then an arc back down
			var ground: Vector2 = _ground_under(g, tgt.pos)
			e.pos = ground - up * 4.0
			_burst(g, ground, 11.0, 2, Color(0.9, 0.78, 0.5))
			if tgt.pos.distance_to(ground) < 20.0:
				g.hurt(tgt, float(e.d["dmg"]) * 1.3, Vector2(signf(dx) * 2.0, -5.5), true)
			e.under = false
			e.gvel = up * 6.4 + g.basis_r(atan2(e.pos.y, e.pos.x)) * signf(dx) * 1.2
			FoeAI.start(e, "go", 120)
			e.hit_done = false

## a move under way
static func _going(g, e, tgt, dx: float, dy: float, k: String, pr: Dictionary, spd: float, gacc: float) -> void:
	var a := atan2(e.pos.y, e.pos.x)
	match k:
		"charge":
			var dirx: float = e.aim.x
			e.vx = dirx * (4.2 + (0.8 if e.raged else 0.0))
			if not e.hit_done and _touching(g, e, tgt, 4.0):
				e.hit_done = true
				g.hurt(tgt, float(e.d["dmg"]) * 1.5, Vector2(dirx * 5.0, -3.0), true)
			# into a wall: it breaks the wall and is stunned for a moment
			var wh: int = g._wall_height(e, dirx, 8.0)
			if e.act_t < 70 and (wh < 0 or wh > 5):
				var front: Vector2 = e.pos + g.basis_r(a) * dirx * (e.w * 0.5 + 3.0)
				g._explode(front, 8.0, 1, 0, 0.0)
				g.shake = maxf(g.shake, 10.0)
				e.vx = -dirx * 1.5
				FoeAI.start(e, "recover", 70)
				return
			if e.act_t <= 0 or (dx * dirx < -60.0):
				FoeAI.start(e, "recover", 26)
		"slam":
			if e.on_ground and e.act_t < 136:
				e.leaping = false
				var feet: Vector2 = e.pos + g.basis_d(a) * (e.h * 0.5 + 1.0)
				_burst(g, feet, 10.0, 1, Color(0.7, 0.6, 0.45))
				if absf(dx) < 48.0 and absf(dy) < 30.0:
					g.hurt(tgt, float(e.d["dmg"]) * 1.2, Vector2(signf(dx) * 3.5, -3.5), true)
				FoeAI.start(e, "recover", 28)
			elif e.act_t <= 0:
				e.leaping = false
				FoeAI.start(e, "recover", 10)
		"rain":
			if e.act_t % 4 == 0:
				var up: Vector2 = tgt.pos.normalized()
				var side: Vector2 = g.basis_r(atan2(tgt.pos.y, tgt.pos.x))
				var from: Vector2 = tgt.pos + up * (100.0 + randf() * 30.0) + side * (randf() - 0.5) * 140.0
				g._spawn_proj(String(pr.get("proj", "rock")), from, -up * 1.2 + side * (randf() - 0.5) * 0.4, "enemy")
			if e.act_t <= 0:
				FoeAI.start(e, "recover", 30)
		"dive":
			var v: Vector2 = e.aim * (5.0 + (0.8 if e.raged else 0.0))
			e.vx = v.dot(g.basis_r(a))
			e.vy = v.dot(g.basis_d(a))
			if not e.hit_done and _touching(g, e, tgt, 4.0):
				e.hit_done = true
				g.hurt(tgt, float(e.d["dmg"]) * 1.4, e.aim * 4.0 + Vector2(0.0, -2.0), true)
			if e.on_ground or e.act_t <= 0:
				if e.on_ground:
					_burst(g, e.pos + g.basis_d(a) * (e.h * 0.5), 7.0, 1, Color(0.7, 0.6, 0.45))
				FoeAI.start(e, "recover", 36)
		"breach":
			# flung up out of the ground, then down and back in
			e.gvel -= e.pos.normalized() * 0.17 * g.gravity_at(e.pos)
			e.pos += e.gvel
			if e.act_t == 112:
				var n: int = int(pr.get("n", 5)) + (2 if e.raged else 0)
				FoeAI.shoot(g, e, tgt, String(pr.get("proj", "sandball")), n, float(pr.get("spread", 0.3)), 0.7)
			if not e.hit_done and _touching(g, e, tgt, 3.0):
				e.hit_done = true
				g.hurt(tgt, float(e.d["dmg"]), Vector2(signf(dx) * 3.0, -3.0), true)
			var kd: int = Defs.KIND[g.type_at(e.pos)]
			if (e.gvel.dot(e.pos.normalized()) < 0.0 and (kd == Defs.K_SOLID or kd == Defs.K_POWDER) and e.act_t < 100) or e.act_t <= 0:
				_burst(g, e.pos, 7.0, 2, Color(0.9, 0.78, 0.5))
				e.under = true
				FoeAI.start(e, "recover", 40)

## is it touching you (its body box grown by `pad`)?
static func _touching(g, e, tgt, pad: float) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var o: Vector2 = tgt.pos - e.pos
	return absf(o.dot(g.basis_r(a))) < (e.w + tgt.w) * 0.5 + pad and absf(o.dot(g.basis_d(a))) < (e.h + tgt.h) * 0.5 + pad

## the ground bursts: it breaks (as a blast does), with a spray of its colour
static func _burst(g, p: Vector2, r: float, power: int, col: Color) -> void:
	g._explode(p, r, power, 0, 0.0)
	var up: Vector2 = p.normalized()
	for k in 30:
		g._particle(p, (up * (1.0 + randf() * 2.0) + Vector2(randf() - 0.5, randf() - 0.5) * 2.0), 20 + randi() % 20, col, false, 0.08)
	g.shake = maxf(g.shake, 7.0)

## The spore clouds (cloud): drifting colour, hurting whoever stands in them.
static func update_clouds(g) -> void:
	for k in range(g.boss_clouds.size() - 1, -1, -1):
		var c: Dictionary = g.boss_clouds[k]
		c["t"] = int(c["t"]) - 1
		var p: Vector2 = c["pos"]
		var r: float = c["r"]
		if randf() < 0.7:
			var o := Vector2(randf() - 0.5, randf() - 0.5) * r * 2.0
			if o.length() < r:
				g._particle(p + o, Vector2(randf() - 0.5, randf() - 0.5) * 0.15, 40 + randi() % 30, c["col"], true, 0.0)
		g.lights.append([p, r * 1.6, Color(c["col"]) * 0.5])
		for m in g.players:
			if not m.dead and m.pos.distance_to(p) < r:
				g.hurt(m, 0.22, Vector2.ZERO, false)
		if int(c["t"]) <= 0:
			g.boss_clouds.remove_at(k)
