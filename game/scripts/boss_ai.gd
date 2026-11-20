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
# how high it leaps (cells), whatever the planet's pull: the jump speed is worked out from it, so a
# leap always stays on screen
const SLAM_H := 34.0
const HOP_H := 20.0
const BREACH_H := 50.0
const CLIMB := 24.0            # the tallest thing it jumps over; anything taller it smashes through

static func tick(g, e, tgt, dist: float, dx: float, dy: float, gacc: float, slow_f: float) -> void:
	var bd: Dictionary = e.d["def"]
	var go: String = bd["go"]
	if not e.boss:
		# a wild creature: it hunts while it sees you or remembers where you were (foe_ai.gd's
		# think, run just before this), and wanders about where it lives otherwise
		# (a burrower feels you through the ground: it needs no line of sight)
		if tgt.dead or not (e.see or e.alert_t > 0 or (go == "burrow" and dist < 120.0)):
			if e.act == "":
				_wander(g, e, gacc, go, float(bd["speed"]) * slow_f)
				_swim_hold(g, e, bd, gacc)
				return
	elif not e.awake:
		var in_arena: bool = e.arena > 0.0 and absf(_off(g, e, tgt.pos)) < e.arena and absf((tgt.pos - e.home).dot(e.home.normalized())) < e.ceil
		if (dist < WAKE or in_arena) and not tgt.dead and not g.test_calm and (not e.d.get("warden", false) or _in_hall(g, e, tgt)):
			wake(g, e)
		else:
			_rest(g, e, gacc)
			return
	if tgt.dead:
		e.vx *= 0.9
		_rest(g, e, gacc)
		return
	if e.boss:
		e.see = true
	if e.boss and not e.raged and e.hp < e.max_hp * 0.5:
		e.raged = true
		g.ui.toast("%s is enraged!" % bd["name"], bd["col"], 3.0)
		g.audio.play("roar", e.pos, 1.0)
		g.shake = maxf(g.shake, 8.0)
	var spd: float = float(bd["speed"]) * (1.25 if e.raged else 1.0) * slow_f
	# out of its reach a while (in a building, behind a wall) and close: a guardian that charges
	# smashes its way in, a hole as big as itself, in one go
	if e.boss and not e.d.get("warden", false) and e.act == "" and go == "walk" and e.unreach_t > 150 and dist < 110.0 and absf(dy) < 40.0 and e.on_ground:
		var cm := _move_of_kind(e, "charge")
		if cm != "":
			e.move = cm
			e.breach = true
			e.breach_hits = 0
			e.unreach_t = 0
			e.hit_done = false
			e.spot = tgt.pos
			FoeAI.start(e, "windup", 40)
	if e.act != "":
		_run(g, e, tgt, dx, dy, dist, gacc, spd)
	else:
		if e.act_cd > 0 and e.boss:
			e.act_cd -= 1            # (a creature's counts down in foe_ai.gd's think)
		_get_around(g, e, tgt, dx, dy, dist, gacc, spd, go)
		if e.act_cd <= 0:
			_begin(g, e, tgt, dx, dy, dist)
	if go == "slither" or go == "burrow":
		_trail(e)
	if go != "fly" and go != "slither" and go != "burrow":
		e.vy += gacc
	_swim_hold(g, e, bd, gacc)

static func wake(g, e) -> void:
	var bd: Dictionary = e.d["def"]
	e.awake = true
	e.act_cd = 60
	g.ui.toast("%s, %s, awakens!" % [String(bd["name"]).to_upper(), String(bd["title"]).to_upper()], bd["col"], 4.0)
	g.audio.play("roar", e.pos, 1.2)
	g.shake = maxf(g.shake, 10.0)

## A swimmer ("swim" in its definition) keeps to the water: out of it, it can't rise and falls back in.
static func _swim_hold(g, e, bd: Dictionary, gacc: float) -> void:
	if not bd.get("swim", false) or e.under:
		return
	if Defs.KIND[g.type_at(e.pos)] != Defs.K_LIQUID:
		e.vy = maxf(e.vy, 0.0) + gacc         # (even mid-dive: it only skims the surface)

## A creature with nothing to hunt: it ambles about near where it lives (walkers and hoppers to and
## fro, fliers circling, burrowers under the ground).
static func _wander(g, e, gacc: float, go: String, spd: float) -> void:
	e.t += 1.0
	e.pace_t -= 1
	if e.pace_t <= 0:
		e.pace_t = 90 + randi() % 140
		e.pace = randf_range(-40.0, 40.0) if randf() < 0.7 else _off(g, e, e.pos)
	var d: float = e.pace - _off(g, e, e.pos)
	var footed: bool = e.on_ground or absf(e.vy) < 0.25
	match go:
		"walk":
			if absf(d) > 3.0 and footed:
				e.vx += (signf(d) * spd * 0.4 - e.vx) * 0.1
				e.facing = 1 if d > 0.0 else -1
				_clear_way(g, e, signf(d), gacc)
			elif footed:
				e.vx *= 0.8
		"hop":
			if footed:
				e.vx *= 0.7
				if int(e.t) % 80 == 0 and absf(d) > 6.0:
					e.vy = -sqrt(2.0 * gacc * HOP_H * 0.6)
					e.vx = clampf(d * 0.03, -spd, spd)
					e.facing = 1 if d > 0.0 else -1
		"fly", "slither":
			var up: Vector2 = e.home.normalized()
			var br: Vector2 = g.basis_r(atan2(e.home.y, e.home.x))
			_steer(g, e, e.home + br * e.pace + up * (8.0 + 6.0 * sin(e.t * 0.02)), spd * 0.5, 0.05)
			if go == "slither":
				_trail(e)
		"burrow":
			e.under = true
			_trail(e)
	if go == "walk" or go == "hop":
		e.vy += gacc

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
## how far along the ground a point is from its lair's middle (cells; + is the lair's "right")
static func _off(g, e, p: Vector2) -> float:
	return (p - e.home).dot(g.basis_r(atan2(e.home.y, e.home.x)))

## is the target inside a warden's hall? (it wakes only then: through the walls of a room next door
## it would only rage at the stone)
static func _in_hall(g, e, tgt) -> bool:
	var up: float = (tgt.pos - e.home).dot(e.home.normalized())
	return absf(_off(g, e, tgt.pos)) < e.tether + 16.0 and up > -float(e.h) and up < e.ceil + 12.0

## Getting about by the nav graph (nav.gd), walkers and hoppers: to a spot round you (its `pace`,
## a new side every second or two), kept inside its lair and leash (`tether`). It never stands
## pushing at a wall: with no way to you it waits as near as it can get (and `unreach_t` counts, for
## the breach in `tick` and the moves `_suits` leaves out). False with no graph yet.
static func _nav_around(g, e, tgt, dx: float, gacc: float, spd: float, go: String) -> bool:
	var po := _off(g, e, tgt.pos)
	if e.pace_t <= 0:
		e.pace_t = 60 + randi() % 80
		e.pace = (26.0 + randf() * 44.0) * float(e.d["def"].get("pace", 1.0 if e.boss else 0.5)) * (1.0 if randf() < 0.5 else -1.0)
	var along := _in_lair(e, po + e.pace) - po
	var ta := atan2(tgt.pos.y, tgt.pos.x)
	var tfeet: Vector2 = tgt.pos + g.basis_d(ta) * (tgt.h * 0.5)
	var gfeet: Vector2 = tfeet + g.basis_r(ta) * along
	var jv := sqrt(2.0 * gacc * ((CLIMB + 6.0) if e.boss else 46.0))
	if not e.boss and not e.reach_ok:
		# a creature that can't get to you from here doesn't stand frozen: it roams the ground it has
		var ea := atan2(e.pos.y, e.pos.x)
		gfeet = e.pos + g.basis_d(ea) * (e.h * 0.5) + g.basis_r(ea) * e.roam
	var nd: float = FoeAI.nav_walk(g, e, gfeet, jv, gacc, 4.0 if go == "walk" else 7.0)
	if is_nan(nd):
		return false
	e.pace_t -= 1
	e.facing = -1 if dx < 0 else 1
	# (can it get to you at all? looked at every third of a second)
	if (g.frame + e.look_t) % 20 == 0:
		e.reach_ok = FoeAI.can_reach(g, e, tfeet, jv, gacc)
		if not e.reach_ok and (absf(e.roam) < 1.0 or nd == 0.0):
			e.roam = randf_range(24.0, 60.0) * (1.0 if randf() < 0.5 else -1.0)
	e.unreach_t = 0 if e.reach_ok else e.unreach_t + 1
	if e.nav_air or not (e.on_ground or absf(e.vy) < 0.25):
		return true
	if go == "walk":
		if nd != 0.0:
			e.vx += (nd * spd - e.vx) * 0.14
		else:
			e.vx *= 0.8
			e.pace_t = mini(e.pace_t, 20)      # there (or as near as it gets): another side soon
	else:
		e.vx *= 0.7
		if nd != 0.0 and int(e.t) % (55 if e.boss else 24) == 0:
			var vy0 := sqrt(2.0 * gacc * HOP_H * (1.0 if e.boss else 0.6))
			var air := 2.0 * vy0 / maxf(gacc, 0.01)
			e.vx = nd * clampf((absf(e.nav_dx) + 4.0) / air, 0.4, spd * 2.2)
			e.vy = -vy0
		elif nd == 0.0:
			e.pace_t = mini(e.pace_t, 20)
	return true

## the first of its moves of kind k ("" if it has none)
static func _move_of_kind(e, k: String) -> String:
	for mv in _moves(e):
		if kind_of(mv) == k:
			return mv
	return ""

## a place along the ground, kept within its lair (`tether` cells either side of the middle)
static func _in_lair(e, off: float) -> float:
	return clampf(off, -e.tether, e.tether) if e.tether > 0.0 else off

static func _get_around(g, e, tgt, dx: float, dy: float, dist: float, gacc: float, spd: float, go: String) -> void:
	e.t += 1.0
	# walkers and hoppers find their way by the nav graph (the old ways below until it's built)
	if (go == "walk" or go == "hop") and _nav_around(g, e, tgt, dx, gacc, spd, go):
		return
	# a wild creature follows you to another level: up onto a platform or ledge, down through a floor
	# (a guardian keeps to its lair's floor)
	if not e.boss and (go == "walk" or go == "hop"):
		var cdir: float = FoeAI.climb(g, e, Vector2(dx, dy), sqrt(2.0 * gacc * 46.0), gacc, 2.5 if go == "walk" else 5.0)
		if cdir != 0.0:
			e.facing = -1 if cdir < 0.0 else 1
			if e.on_ground and e.vy >= 0.0:
				if go == "walk":
					e.vx += (cdir * spd - e.vx) * 0.2
				else:
					e.vx *= 0.7
					var cgap: float = FoeAI.climb_gap(g, e)
					if int(e.t) % 20 == 0 and absf(cgap) > 4.0:
						e.vy = -2.4
						e.vx = clampf(cgap / (4.8 / maxf(gacc, 0.01)), -spd * 2.2, spd * 2.2)
			return
	var po := _off(g, e, tgt.pos)
	var bo := _off(g, e, e.pos)
	# where it wants to be: round you, never still for long (a new side every second or two),
	# always inside its lair (you can leave it; it won't follow you out among the buildings)
	e.pace_t -= 1
	if e.pace_t <= 0:
		e.pace_t = 60 + randi() % 80
		e.pace = (26.0 + randf() * 44.0) * float(e.d["def"].get("pace", 1.0 if e.boss else 0.5)) * (1.0 if randf() < 0.5 else -1.0)
	var goal := _in_lair(e, po + e.pace)
	var d := goal - bo
	# resting on something (the ground, or a chest or a body that doesn't count as ground)
	var footed: bool = e.on_ground or absf(e.vy) < 0.25
	# not getting anywhere for a second and a half (wedged on something): it hops free
	if go == "walk" or go == "hop":
		e.prog_t += 1
		if e.prog_t >= 90:
			if absf(d) > 10.0 and e.prog_pos.distance_to(e.pos) < 3.0 and footed:
				e.vy = -sqrt(2.0 * gacc * 16.0)
				e.vx = signf(d) * spd * 1.6
			e.prog_pos = e.pos
			e.prog_t = 0
	match go:
		"walk":
			e.facing = -1 if dx < 0 else 1
			if absf(d) > 4.0:
				var dirx := signf(d)
				if not e.boss and dy < -14.0 and footed and FoeAI.edge_ahead(g, e, dirx):
					e.vx *= 0.6                  # you're above it: a creature won't step off its level
				else:
					e.vx += (dirx * spd - e.vx) * (0.14 if footed else 0.04)
					_clear_way(g, e, dirx, gacc)
			elif footed:
				e.vx *= 0.8
				e.pace_t = mini(e.pace_t, 20)      # there: another side soon, not standing about
		"hop":
			e.facing = -1 if dx < 0 else 1
			if footed:
				e.vx *= 0.7
				if int(e.t) % 55 == 0 and absf(d) > 6.0:
					var vy0 := sqrt(2.0 * gacc * HOP_H)
					var air := 2.0 * vy0 / maxf(gacc, 0.01)
					e.vx = clampf(d / air, -spd * 2.2, spd * 2.2)
					e.vy = -vy0
		"fly", "slither":
			# circle above you (a serpent weaves wider and lower), within its lair and under its roof
			var up: Vector2 = tgt.pos.normalized()
			var sway := sin(e.t * (0.013 if go == "slither" else 0.01))
			var sc := 1.0 if e.boss else 0.45      # (a small creature keeps closer)
			var hover := (36.0 if go == "slither" else 58.0) * sc
			if e.d["def"].get("swim", false):
				hover = -6.0                         # (a swimmer keeps level with you or below: in the water)
			var want: Vector2 = tgt.pos + up * hover + g.basis_r(atan2(tgt.pos.y, tgt.pos.x)) * sway * (95.0 if go == "slither" else 70.0) * sc
			_steer(g, e, _lair_point(g, e, want), spd, 0.08)
		"burrow":
			# under the ground toward the spot under you (within its lair)
			e.under = true
			var below: Vector2 = _lair_point(g, e, tgt.pos)
			below = below.normalized() * (tgt.pos.length() - (26.0 if e.boss else 16.0))
			var to: Vector2 = below - e.pos
			if to.length() > 1.0:
				e.pos += to.normalized() * minf(spd, to.length())
			e.facing = -1 if dx < 0 else 1
			_rumble(g, e)

## a point brought inside its lair: along the ground within its tether, no higher than its roof
static func _lair_point(g, e, p: Vector2) -> Vector2:
	if e.tether <= 0.0:
		return p
	var ha := atan2(e.home.y, e.home.x)
	var br: Vector2 = g.basis_r(ha)
	var up: Vector2 = e.home.normalized()
	var o: Vector2 = p - e.home
	var along := clampf(o.dot(br), -e.tether, e.tether)
	var high := clampf(o.dot(up), -20.0, e.ceil)
	return e.home + br * along + up * high

## something in its way on the ground: hop over it if it's low; if it's tall, smash through it
static func _clear_way(g, e, dirx: float, gacc: float) -> void:
	if not e.hit_wall or not (e.on_ground or absf(e.vy) < 0.25):
		return
	var need: int = g._wall_height(e, dirx, CLIMB)
	if need >= 0:
		e.vy = -sqrt(2.0 * gacc * (float(need) + 4.0))
	else:
		# too tall to hop: it turns back (a guardian used to chip at it, which only made a hole to
		# shoot it through; it breaks in with a breach now, `tick`)
		e.pace = -e.pace
		e.pace_t = 60

## fliers: ease toward a point, steering round anything solid in the way
static func _steer(g, e, want: Vector2, spd: float, acc: float) -> void:
	var a := atan2(e.pos.y, e.pos.x)
	var o: Vector2 = want - e.pos
	var mag := minf(spd, o.length() * 0.05 + 0.3)
	var lw := Vector2(o.dot(g.basis_r(a)), o.dot(g.basis_d(a)))
	var dirv: Vector2 = g._flier_steer(e, lw) if lw.length() > 1.0 else Vector2.ZERO
	e.vx += (dirv.x * mag - e.vx) * acc
	e.vy += (dirv.y * mag - e.vy) * acc
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
		out.append_array(bd.get("rage", {}).keys())
	return out

static func _params(e, mv: String) -> Dictionary:
	var bd: Dictionary = e.d["def"]
	if bd["moves"].has(mv):
		return bd["moves"][mv]
	return bd.get("rage", {}).get(mv, {})

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
			if e.unreach_t > 60:
				return false             # (you're out of its reach: no running at a wall)
			# (along the ground: a creature only charges you on its own level, not off a ledge)
			return e.on_ground and absf(dy) < (30.0 if e.boss else 12.0) and absf(dx) > (30.0 if e.boss else 12.0) and absf(dx) < 190.0
		"slam":
			return e.on_ground and dist < 170.0 and e.unreach_t <= 60
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
static func _ground_under(g, p: Vector2, reach := 50) -> Vector2:
	var dn: Vector2 = -p.normalized()
	var q := p
	for k in reach:
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
				e.breach = false
				e.act_cd = int((50.0 if e.raged else 80.0) * (0.6 + randf() * 0.6)) if e.boss else int(e.d["def"].get("cd", 120)) + randi() % 60

## the moment the wind-up ends
static func _strike(g, e, tgt, dx: float, dy: float, dist: float, k: String, pr: Dictionary, spd: float) -> void:
	var up: Vector2 = e.pos.normalized()
	var ta := atan2(tgt.pos.y, tgt.pos.x)
	match k:
		"charge":
			FoeAI.start(e, "go", 75 if e.boss else 45)
			e.aim = Vector2(signf(dx), 0.0)
			e.facing = int(e.aim.x)
		"slam":
			# a leap aimed to land on you (or as near as its lair allows), never higher than SLAM_H
			var gs: float = 0.17 * float(g.gravity_at(e.pos))
			var vy0 := sqrt(2.0 * gs * SLAM_H * _sz(e))
			var air: float = 2.0 * vy0 / maxf(gs, 0.01)
			var land := _in_lair(e, _off(g, e, tgt.pos)) - _off(g, e, e.pos)
			var lim := (4.5 if pr.get("far", false) else 3.0) * (1.0 if e.boss else 0.8)
			e.vx = clampf(land / air, -lim, lim)
			e.vy = -vy0
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
			_burst(g, e.spot, 9.0, 2, pr.get("col", Color(0.5, 0.4, 0.3)), e.boss)
			if tgt.pos.distance_to(e.spot) < 16.0:
				g.hurt(tgt, float(e.d["dmg"]) * 1.4, Vector2(0.0, -3.6), true)
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
				# on the floor below it, near it (a flier up by the ceiling mustn't call them into the
				# room above through the stone)
				var mt: String = String(pr.get("type", "slime"))
				var mdef: Dictionary = Defs.enemy_def(mt)
				var foot := _ground_under(g, e.pos + g.basis_r(atan2(e.pos.y, e.pos.x)) * (randf() - 0.5) * 32.0, 90)
				var at: Vector2 = foot + up * (float(mdef["h"]) * 0.5 + 1.0)
				var m = g.spawn_enemy(mt, g.free_spot(at, float(mdef["w"]), float(mdef["h"]), 6))
				m.summoner = e
				FoeAI.puff(g, m.pos, e.d["def"]["col"])
			FoeAI.start(e, "recover", 30)
		"cloud":
			g.boss_clouds.append({"pos": tgt.pos, "r": float(pr.get("r", 22.0)), "t": int(pr.get("t", 300)), "col": e.d["def"].get("col", Color(0.8, 0.5, 1.0))})
			FoeAI.start(e, "recover", 24)
		"dive":
			e.aim = (tgt.pos - e.pos).normalized()
			FoeAI.start(e, "go", 42)
			g.audio.play("roar", e.pos, 0.7)
		"breach":
			# out of the ground under you: a crater, a burst of sand at you, then an arc back down
			var ground: Vector2 = _ground_under(g, tgt.pos)
			e.pos = ground - up * 4.0
			_burst(g, ground, 11.0, 2, Color(0.9, 0.78, 0.5), e.boss)
			if tgt.pos.distance_to(ground) < 20.0:
				g.hurt(tgt, float(e.d["dmg"]) * 1.3, Vector2(signf(dx) * 2.0, -3.8), true)
			e.under = false
			e.gvel = up * sqrt(2.0 * 0.17 * float(g.gravity_at(e.pos)) * BREACH_H * _sz(e)) + g.basis_r(atan2(e.pos.y, e.pos.x)) * signf(dx) * 1.0
			FoeAI.start(e, "go", 120)
			e.hit_done = false

## a move under way
static func _going(g, e, tgt, dx: float, dy: float, k: String, pr: Dictionary, spd: float, gacc: float) -> void:
	var a := atan2(e.pos.y, e.pos.x)
	match k:
		"charge":
			var dirx: float = e.aim.x
			e.vx = dirx * (float(pr.get("v", 4.2)) + (0.8 if e.raged else 0.0))
			if not e.hit_done and _touching(g, e, tgt, 4.0):
				e.hit_done = true
				g.hurt(tgt, float(e.d["dmg"]) * 1.5, Vector2(dirx * 5.0, -3.0), true)
			# into a wall: it breaks the wall and is stunned for a moment
			var wh: int = g._wall_height(e, dirx, 8.0)
			if e.breach and (wh < 0 or wh > 5):
				# a breach: a hole as big as itself through whatever's in the way (brick and stone,
				# not warded stone or obsidian), then on through it; twice and still blocked, it gives up
				e.vx = dirx * 0.5
				if g.frame - e.smash_f > 16:
					if e.breach_hits >= 2:
						e.breach = false
						FoeAI.start(e, "recover", 50)
						return
					e.smash_f = g.frame
					e.breach_hits += 1
					var fr: Vector2 = e.pos + g.basis_r(a) * dirx * (e.w * 0.5 + 2.0)
					g._explode(fr, maxf(e.w, e.h) * 0.6 + 3.0, 2, 0, 0.0)
					g.shake = maxf(g.shake, 12.0)
					e.act_t = maxi(e.act_t, 30)
				return
			if e.act_t < (70 if e.boss else 40) and (wh < 0 or wh > 5) and g.frame - e.smash_f > 16:
				if e.boss:
					var front: Vector2 = e.pos + g.basis_r(a) * dirx * (e.w * 0.5 + 3.0)
					g._explode(front, 8.0, 1, 0, 0.0)
				g.shake = maxf(g.shake, 10.0 * _sz(e))
				e.vx = -dirx * 1.5
				FoeAI.start(e, "recover", 70)
				return
			if e.hit_wall and wh > 0 and (e.on_ground or absf(e.vy) < 0.25):
				# something low in the way (a step of the shrine, a stub of a pillar): over it, still
				# charging (it used to stand pushing against it until the charge ran out)
				e.vy = -sqrt(2.0 * gacc * (float(wh) + 3.0))
			if e.act_t <= 0 or (dx * dirx < -60.0) or (e.tether > 0.0 and _off(g, e, e.pos) * dirx > e.tether + 6.0):
				FoeAI.start(e, "recover", 26)
		"slam":
			if e.on_ground and e.act_t < 136:
				e.leaping = false
				var feet: Vector2 = e.pos + g.basis_d(a) * (e.h * 0.5 + 1.0)
				_burst(g, feet, 10.0, 1, Color(0.7, 0.6, 0.45), e.boss)
				if absf(dx) < 48.0 * _sz(e) + 8.0 and absf(dy) < 30.0 * _sz(e) + 6.0:
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
			var v: Vector2 = e.aim * (float(pr.get("v", 5.0)) + (0.8 if e.raged else 0.0))
			e.vx = v.dot(g.basis_r(a))
			e.vy = v.dot(g.basis_d(a))
			if not e.hit_done and _touching(g, e, tgt, 4.0):
				e.hit_done = true
				g.hurt(tgt, float(e.d["dmg"]) * 1.4, e.aim * 4.0 + Vector2(0.0, -2.0), true)
			if e.on_ground or e.act_t <= 0:
				if e.on_ground:
					_burst(g, e.pos + g.basis_d(a) * (e.h * 0.5), 7.0, 1, Color(0.7, 0.6, 0.45), e.boss)
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
				_burst(g, e.pos, 7.0, 2, Color(0.9, 0.78, 0.5), e.boss)
				e.under = true
				FoeAI.start(e, "recover", 40)

## is it touching you (its body box grown by `pad`)?
static func _touching(g, e, tgt, pad: float) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var o: Vector2 = tgt.pos - e.pos
	return absf(o.dot(g.basis_r(a))) < (e.w + tgt.w) * 0.5 + pad and absf(o.dot(g.basis_d(a))) < (e.h + tgt.h) * 0.5 + pad

## the ground bursts: it breaks (as a blast does), with a spray of its colour
## (a wild creature's only throws up dust: it never breaks the land)
static func _burst(g, p: Vector2, r: float, power: int, col: Color, wreck := true) -> void:
	if wreck:
		g._explode(p, r, power, 0, 0.0)
	var up: Vector2 = p.normalized()
	for k in (30 if wreck else 14):
		g._particle(p, (up * (1.0 + randf() * 2.0) + Vector2(randf() - 0.5, randf() - 0.5) * 2.0), 20 + randi() % 20, col, false, 0.08)
	g.shake = maxf(g.shake, 7.0 if wreck else 2.0)

## how big its moves are: a guardian's in full, a wild creature's about half
static func _sz(e) -> float:
	return 1.0 if e.boss else 0.5

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
