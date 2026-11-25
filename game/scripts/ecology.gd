extends RefCounted
## The wild creatures' lives (user, 21 Nov: "make the worlds more realistic, like the enemies fit into the
## world better"): what a creature does when it isn't fighting you. Called by boss_ai.gd's tick for every
## wild creature (Defs.CREATURES, foe type "c_<id>") before its hunting, so a creature is a mix of:
##
##   temper    "predator" hunts you on sight (as all of them used to); "territorial" warns you off (it
##             faces you and growls) and charges if you stay too close; "neutral" only fights back once
##             hurt; "prey" never fights: it runs from you and from its hunters
##   eats      the creatures a predator hunts (it chases one down, bites until it falls, then eats at the
##             carcass a while); "scavenge" ones come to carcasses (vultures circle, then land)
##   active    "day" / "night" / "any": out of its hours it goes back to its den (where it was first
##             met) or a perch and sleeps there, and wakes to you beside it, a spell, digging or a blast
##   idle      what it does with itself (weights): wander, graze, sniff, rest, drink (walks to water and
##             lowers its head), sit, croak, flick (a frog's tongue at a fly), hop, perch (in a tree),
##             circle, soar, coil, lurk (a burrower, still under the ground), roost (on a cave ceiling),
##             bask, follow (a pack or a herd keeps to its leader)
##   habitat   where it is met: "water" (frogs, leeches: near water only), "soft" (burrowers: only
##             in soft ground, never through rock, floors or the air), "trees" (perching birds),
##             "ceiling" (glow worms hang from cave roofs)
##   fireproof creatures of fire don't fear it
##
## And they react to the world: fire close by and blasts send them running (a predator only flinches),
## wounded ones run from you, the open sky in a storm sends them to shelter (under an overhang or a tree),
## walkers never step into lava, and a hunted creature's herd runs with it.
## Returns to boss_ai.gd: HUNT (0: it's after you, boss_ai's moves run), DONE (1: moved here), WANDER (2:
## boss_ai's own idle wander).

const FoeAI := preload("res://scripts/foe_ai.gd")
const BossArt := preload("res://scripts/boss_art.gd")

const HUNT := 0
const DONE := 1
const WANDER := 2
const TERR := 34.0            # a territorial creature's space: closer than this (plus its size) is too close
const WARN := 80              # frames of warning before it charges
const FLEE := 1.35            # prey runs this much faster than it walks
const CHASE := 1.5            # and a hunter after it this much
const SENSE_EVERY := 12

# ------------------------------------------------------------------ data ---
static func temper(e) -> String:
	return String(e.d["def"].get("temper", "predator"))

static func _idle_of(c: Dictionary) -> Dictionary:
	if c.has("idle"):
		return c["idle"]
	var plan: String = c["body"]["plan"]
	match String(c["go"]):
		"walk":
			if plan == "fungus":
				return {"sit": 3, "wander": 2}
			return {"wander": 3, "graze": 3, "sniff": 1, "rest": 1, "drink": 1}
		"hop":
			if plan == "toad":
				return {"sit": 4, "croak": 2, "flick": 2, "hop": 2}
			return {"sit": 3, "hop": 2}
		"fly":
			if c.get("swim", false):
				return {"circle": 1}
			return {"circle": 2, "perch": 3, "soar": 1}
		"slither":
			return {"wander": 3, "coil": 2}
		"burrow":
			return {"lurk": 3, "wander": 1}
	return {"wander": 1}

const LENGTH := {"wander": [150, 300], "graze": [180, 360], "sniff": [60, 120], "rest": [300, 600], "drink": [400, 400],
	"sit": [120, 300], "croak": [70, 110], "flick": [16, 16], "hop": [50, 50], "perch": [400, 900], "circle": [200, 400],
	"soar": [300, 600], "coil": [200, 500], "lurk": [200, 400], "roost": [600, 1200], "bask": [300, 600], "follow": [120, 240],
	"scavenge": [600, 600], "shelter": [240, 240]}

## soft ground: what a burrower can swim through
static func soft(t: int) -> bool:
	return t == Defs.DIRT or t == Defs.GRASS or t == Defs.SAND or t == Defs.MUD or t == Defs.GRAVEL or t == Defs.SNOW \
		or t == Defs.ASH or t == Defs.SANDSTONE or t == Defs.LITTER or t == Defs.MYCELIUM or t == Defs.DRYGRASS

static func _ground(t: int) -> bool:
	var kd: int = Defs.KIND[t]
	return kd == Defs.K_SOLID or kd == Defs.K_POWDER

## is it its time of day to be out? (underground it's always the creature's time)
static func active_now(g, e) -> bool:
	var act: String = e.d["def"].get("active", "any")
	if act == "any" or e.pos.length() < g.gpu.surf_at(atan2(e.pos.y, e.pos.x)).x - 30.0:
		return true
	var dl: float = g._local_daylight(e.pos)
	return dl > 0.2 if act == "day" else dl < 0.45

static func _stormy(g) -> bool:
	return g.rain > 0.45 or g.sky_ev == "squall" or g.sky_ev == "hail" or g.sky_ev == "sandstorm"

# ------------------------------------------------------------------ tick ---
static func tick(g, e, tgt, dist: float, gacc: float, slow_f: float) -> int:
	var c: Dictionary = e.d["def"]
	var go: String = c["go"]
	var spd: float = float(c["speed"]) * slow_f
	e.pose = ""
	# a tongue is only out while it flicks at a fly or lashes at you (a frog roused mid-flick left it
	# standing up in the air: user, 21 Nov)
	if e.doing != "flick" and not (e.act == "go" and e.move == "tongue"):
		e.tongue = 0.0
	if e.bite_t > 0:
		e.bite_t -= 1
	if e.hunger_t > 0:
		e.hunger_t -= 1
	if go == "burrow":
		keep_under(g, e)
		if e.stranded_t > 0:
			_stranded(g, e, tgt, gacc)
			return DONE
	if e.act != "":
		return HUNT                       # (mid-attack: boss_ai.gd's)
	_sense(g, e, tgt, dist)
	var tp := temper(e)
	if e.provoked and not e.was_prov:
		# struck: it knows where you are (and prey only runs the harder)
		e.was_prov = true
		e.asleep = false
		e.warn_t = 0
		e.alert_t = 240
		e.seen_pos = tgt.pos
		if tp == "prey":
			scare_one(e, tgt.pos, 240)
	if e.fear_t > 0:
		e.fear_t -= 1
		_flee(g, e, gacc, spd)
		return DONE
	# badly hurt, it runs from you (unless you're right on it: cornered, it fights)
	if e.hp < e.max_hp * 0.25 and not tgt.dead and dist > 22.0 and dist < 150.0 and tp != "predator":
		scare_one(e, tgt.pos, 60)
		_flee(g, e, gacc, spd)
		return DONE
	if _hostile(g, e, tgt, dist, tp, go):
		e.asleep = false
		e.doing = ""
		e.eat_t = 0
		return HUNT
	if e.asleep:
		_sleep(g, e, gacc, go)
		return DONE
	if e.eat_t > 0:
		e.eat_t -= 1
		e.pose = "graze"
		e.vx *= 0.8
		if g.frame % 20 == 0:
			g._particle(_mouth(g, e), Vector2(randf() - 0.5, -0.6) * 0.6, 20, Color(0.55, 0.12, 0.1), false, 0.05)
		_fall(g, e, gacc, go)
		return DONE
	if e.prey != null and _chase(g, e, gacc, spd, go):
		return DONE
	return _life(g, e, tgt, dist, gacc, spd, go)

## Is it after you? Its temper says, then the old rule: while it sees you or remembers where you were
## (a burrower feels you through the ground).
static func _hostile(g, e, tgt, dist: float, tp: String, go: String) -> bool:
	if tgt.dead or g.calm_foe(e, tgt):
		e.warn_t = 0
		return false
	match tp:
		"prey":
			return false
		"neutral":
			if not e.provoked:
				return false
		"territorial":
			if not e.provoked:
				if not e.asleep and e.see and dist < TERR + e.w:
					e.warn_t += 1
					if e.warn_t > WARN:
						e.provoked = true     # (you stayed: it charges)
				else:
					e.warn_t = maxi(0, e.warn_t - 2)
				if not e.provoked:
					return false
		_:
			if e.asleep:
				return false
			if e.prey != null and dist > 50.0 and not e.provoked:
				return false                  # (busy with a hunt of its own)
	return e.see or e.alert_t > 0 or (go == "burrow" and dist < 120.0)

## What it notices, every few frames: being woken, fire, you or a hunter (prey), a meal (hunters),
## a carcass (scavengers).
static func _sense(g, e, tgt, dist: float) -> void:
	e.sense_t -= 1
	if e.sense_t > 0:
		return
	e.sense_t = SENSE_EVERY
	var c: Dictionary = e.d["def"]
	var tp := temper(e)
	var noise: bool = not tgt.dead and dist < 100.0 and g.frame - tgt.cast_frame < SENSE_EVERY + 2
	if not noise and g.brushes.size() < 64:
		for b in g.brushes:
			if (b[0] as Vector2).distance_squared_to(e.pos) < 55.0 * 55.0:
				noise = true
				break
	if e.asleep and (dist < 30.0 or noise or e.provoked):
		wake(g, e, tgt)
	if not c.get("fireproof", false):
		var fp := _fire_near(g, e)
		if fp != Vector2.ZERO:
			scare_one(e, fp, 90)
	if tp == "prey" and not e.asleep:
		if not tgt.dead and ((e.see and dist < 90.0) or dist < 42.0 or (noise and dist < 120.0)):
			scare_one(e, tgt.pos, 150)
			_herd_alarm(g, e, tgt.pos)
		var h = _hunter_near(g, e)
		if h != null:
			scare_one(e, h.pos, 120)
			_herd_alarm(g, e, h.pos)
	elif tp == "neutral" and not e.provoked and String(c["go"]) == "fly" and not c.get("swim", false) and dist < 34.0 and not tgt.dead:
		if e.doing == "perch" and e.fear_t <= 0:
			g.audio.play("chirp", e.pos, 0.5)
		scare_one(e, tgt.pos, 90)          # (a bird you walk up to flies off)
	if c.has("eats") and e.prey == null and e.hunger_t <= 0 and not e.asleep and e.fear_t <= 0:
		e.prey = _find_prey(g, e)
		e.chase_t = 0
	if e.prey != null and (e.prey.dead or e.prey.pos.distance_to(e.pos) > 260.0):
		e.prey = null
	if c.get("scavenge", false) and e.prey == null and e.hunger_t <= 0 and e.doing != "scavenge" and not e.asleep:
		var cc := _carcass_near(g, e.pos, 240.0)
		if not cc.is_empty():
			e.doing = "scavenge"
			e.doing_t = LENGTH["scavenge"][0]
			e.goal_p = cc["pos"]
	e.storm = _stormy(g) and e.pos.length() > g.gpu.surf_at(atan2(e.pos.y, e.pos.x)).x - 20.0 and not c.get("swim", false)

## does touching it hurt? (prey never; the neutral and the territorial only once roused; nothing asleep)
static func harmful(e) -> bool:
	if e.boss or not e.d.has("def") or not e.d.get("creature", false):
		return true
	if e.asleep:
		return false
	match temper(e):
		"prey":
			return false
		"neutral", "territorial":
			return e.provoked
	return true

static func wake(g, e, tgt) -> void:
	e.asleep = false
	var tp := temper(e)
	if tgt == null or tgt.dead:
		return
	if tp == "prey":
		scare_one(e, tgt.pos, 150)
	elif e.pos.distance_to(tgt.pos) < 140.0 and (tp == "predator" or e.provoked):
		e.alert_t = 240
		e.seen_pos = tgt.pos
	FoeAI.puff(g, e.pos - g.basis_d(atan2(e.pos.y, e.pos.x)) * (e.h * 0.6), Color(1, 1, 0.85))

static func scare_one(e, from: Vector2, t: int) -> void:
	if e.boss:
		return
	if e.fear_t <= 0:
		e.flee_lock = 0                     # (a fresh fright: which way is worked out anew)
		e.flee_chk = Vector2.ZERO
	e.fear_t = maxi(e.fear_t, t)
	e.fear_from = from
	e.asleep = false
	e.prey = null
	e.doing = ""

## A blast (main `_explode`, lightning): prey and the timid run from it; hunters flinch away; sleepers wake.
static func scare(g, p: Vector2, r: float) -> void:
	for e in g.enemies:
		if e.boss or e.dead or not e.d.has("def"):
			continue
		var d: float = e.pos.distance_to(p)
		if d > r * 4.0 + 50.0:
			continue
		var tp := temper(e)
		e.asleep = false
		if tp == "prey" or (tp == "neutral" and not e.provoked) or e.hp < e.max_hp * 0.4:
			scare_one(e, p, 180)
		elif d < r * 2.0 + 24.0:
			scare_one(e, p, 40)

## the herd runs with it
static func _herd_alarm(g, e, from: Vector2) -> void:
	for o in g.enemies:
		if o != e and o.type == e.type and not o.dead and o.fear_t < 60 and o.pos.distance_squared_to(e.pos) < 90.0 * 90.0:
			scare_one(o, from, 120)

## a creature close by that hunts this one
static func _hunter_near(g, e):
	for o in g.enemies:
		if o == e or o.dead or not o.d.has("def") or o.asleep:
			continue
		if not (o.d["def"].get("eats", []) as Array).has(e.type.trim_prefix("c_")):
			continue
		if o.pos.distance_squared_to(e.pos) < (130.0 * 130.0 if o.prey == e else 80.0 * 80.0):
			return o
	return null

static func _find_prey(g, e):
	var eats: Array = e.d["def"]["eats"]
	var best = null
	var bd := 170.0 * 170.0
	for o in g.enemies:
		if o == e or o.dead or not eats.has(o.type.trim_prefix("c_")):
			continue
		var d2: float = o.pos.distance_squared_to(e.pos)
		if d2 < bd and g.in_grid(o.pos, 14.0):
			bd = d2
			best = o
	return best

## fire within a few strides: the side it's on (a world point), or ZERO
static func _fire_near(g, e) -> Vector2:
	if not g.in_grid(e.pos, 20.0):
		return Vector2.ZERO
	var l: Vector2 = g.to_grid(e.pos)
	var lf: int = g.box_count(l.x - 16.0, l.y - 12.0, 16.0, 22.0, Defs.FIRE)
	var rf: int = g.box_count(l.x, l.y - 12.0, 16.0, 22.0, Defs.FIRE)
	if lf + rf < 2:
		return Vector2.ZERO
	return g.from_grid(l + Vector2(8.0 if rf > lf else -8.0, 0.0))

# ----------------------------------------------------------------- moving ---
## gravity for walkers and hoppers (a frog floats and paddles in water)
static func _fall(g, e, gacc: float, go: String) -> void:
	if go != "walk" and go != "hop":
		return
	e.vy += gacc
	if e.in_liquid and (String(e.d["def"]["body"]["plan"]) == "toad" or e.d["def"].get("habitat", "") == "water"):
		e.vy = e.vy * 0.85 - gacc * 1.25            # (it floats up and bobs at the top)

## walk along the ground toward a world point; hops low steps, never into lava. True once there.
static func walk_to(g, e, p: Vector2, spd: float, gacc: float, near := 4.0) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var along: float = (p - e.pos).dot(g.basis_r(a))
	var footed: bool = e.on_ground or absf(e.vy) < 0.25
	if absf(along) <= near:
		if footed:
			e.vx *= 0.8
		return true
	var dirx := signf(along)
	e.facing = 1 if dirx > 0.0 else -1
	if footed:
		e.vx += (dirx * spd - e.vx) * 0.14
	# a wall it can clear (only from the ground: jumping again at the top of a jump walked it up walls)
	if e.hit_wall and (e.on_ground or e.in_liquid):
		var need: int = g._wall_height(e, dirx, jump_reach(e))
		if need >= 0:
			e.vy = -sqrt(2.0 * gacc * (float(need) + 4.0))
	return false

## how high a creature can jump a wall: about its own height and a bit (a deer clears a fence, a hare
## a tuft; none goes up the side of a house)
static func jump_reach(e) -> float:
	return clampf(e.h * 1.3 + 2.0, 4.0, 24.0)

## a frog's way about: hop after hop toward a point. True once there.
static func hop_to(g, e, p: Vector2, spd: float, gacc: float, big := 1.0) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var along: float = (p - e.pos).dot(g.basis_r(a))
	if absf(along) < 6.0:
		return true
	e.facing = 1 if along > 0.0 else -1
	var footed: bool = e.on_ground or e.in_liquid
	if footed and e.crouch_t == 0 and e.off_t == 0:
		e.vx *= 0.5
		e.t += 1.0
		if int(e.t) % 26 == 0:
			var vy0 := sqrt(2.0 * gacc * (9.0 + 7.0 * big))
			var air := 2.0 * vy0 / maxf(gacc, 0.01)
			hop(e, signf(along) * clampf(absf(along) / air, 0.6, spd * 2.0 * big), -vy0)
	return false

## A frog's hop: it crouches a moment first (boss_ai.gd's tick plays the crouch out, then jumps).
static func hop(e, vx: float, vy: float) -> void:
	e.hop_v = Vector2(vx, vy)
	e.crouch_t = 6

static func fly_to(g, e, want: Vector2, spd: float, acc := 0.06) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var o: Vector2 = want - e.pos
	var mag := minf(spd, o.length() * 0.05 + 0.2)
	var lw := Vector2(o.dot(g.basis_r(a)), o.dot(g.basis_d(a)))
	var dirv: Vector2 = g._flier_steer(e, lw) if lw.length() > 1.0 else Vector2.ZERO
	e.vx += (dirv.x * mag - e.vx) * acc
	e.vy += (dirv.y * mag - e.vy) * acc
	if absf(e.vx) > 0.2:
		e.facing = 1 if e.vx > 0.0 else -1
	return o.length() < 3.0

static func _move_to(g, e, p: Vector2, spd: float, gacc: float, go: String) -> bool:
	match go:
		"walk":
			return walk_to(g, e, p, spd, gacc)
		"hop":
			return hop_to(g, e, p, spd, gacc)
		"fly", "slither":
			return fly_to(g, e, p, spd)
		"burrow":
			burrow_toward(g, e, p, spd, depth(e))
			return absf((p - e.pos).dot(g.basis_r(atan2(e.pos.y, e.pos.x)))) < 3.0
	return true

## Away from what frightened it: along the ground (a frog toward water if there is some), up and away
## (fliers), deeper away (burrowers).
static func _flee(g, e, gacc: float, spd: float) -> void:
	var go: String = e.d["def"]["go"]
	var a := atan2(e.pos.y, e.pos.x)
	var br: Vector2 = g.basis_r(a)
	var up: Vector2 = e.pos.normalized()
	var side: float = signf((e.pos - e.fear_from).dot(br))
	if side == 0.0:
		side = float(e.facing)
	var fast := spd * FLEE
	if e.flee_lock > 0:
		e.flee_lock -= 1
		side = float(e.flee_dir)
	if e.flee_cd > 0:
		e.flee_cd -= 1
	if go == "walk" or go == "hop":
		# cornered (a wall it can't clear, or no headway for most of a second): it doubles back, past
		# whatever chased it there, and keeps that way a while instead of turning back into the corner
		# each time it looks round at you (user, 21 Nov: prey chased into a wall kept running at it)
		var stuck: bool = e.hit_wall and e.on_ground and g._wall_height(e, side, jump_reach(e)) < 0
		e.flee_chk_t += 1
		if e.flee_chk_t >= 40:
			if e.flee_chk != Vector2.ZERO and e.pos.distance_to(e.flee_chk) < 4.0 and not e.in_liquid:
				stuck = true
			e.flee_chk = e.pos
			e.flee_chk_t = 0
		if stuck and e.flee_cd <= 0:
			side = -side
			e.flee_dir = int(side)
			e.flee_lock = 150 + randi() % 90
			e.flee_cd = 25
			e.flee_chk = e.pos
			e.flee_chk_t = 0
			e.facing = int(side)
			if e.on_ground and e.fear_from.distance_to(e.pos) < 45.0:
				# bolting back past you: a leap as it goes
				e.vy = -sqrt(2.0 * gacc * minf(jump_reach(e), e.h + 4.0))
				e.vx = side * fast
	match go:
		"walk":
			walk_to(g, e, e.pos + br * side * 80.0, fast, gacc, 0.0)
		"hop":
			var wp: Vector2 = e.goal_p if e.doing == "to_water" else Vector2.ZERO
			if e.in_liquid:
				# under the surface, away
				e.vx += (side * spd * 1.4 - e.vx) * 0.1
				e.vy += gacc * 0.4
			elif e.d["def"].get("habitat", "") == "water" and wp == Vector2.ZERO and e.fear_t % 30 == 0:
				var w := find_water(g, e, 90.0, false)
				if w != Vector2.ZERO and signf((w - e.pos).dot(br)) == side:
					e.doing = "to_water"
					e.goal_p = w
				hop_to(g, e, e.pos + br * side * 60.0, fast, gacc, 1.4)
			else:
				hop_to(g, e, wp if wp != Vector2.ZERO else e.pos + br * side * 60.0, fast, gacc, 1.4)
		"fly", "slither":
			fly_to(g, e, e.pos + up * (30.0 if not e.d["def"].get("swim", false) else -10.0) + br * side * 80.0, fast * 1.2, 0.09)
		"burrow":
			e.under = true
			burrow_toward(g, e, e.pos + br * side * 40.0, fast, depth(e))
	_fall(g, e, gacc, go)

## A hunter after its prey: it runs it down and bites until it falls, then eats there.
static func _chase(g, e, gacc: float, spd: float, go: String) -> bool:
	var p = e.prey
	if p == null or p.dead:
		e.prey = null
		return false
	e.chase_t += 1
	if e.chase_t > 900:
		e.prey = null                          # (it got away: it rests a while before trying again)
		e.hunger_t = 900
		return false
	if go == "burrow":
		e.under = true
		burrow_toward(g, e, p.pos, spd * CHASE, depth(e))
		if (p.pos - e.pos).length() < 16.0 and e.bite_t <= 0:
			_bite(g, e, p)
		return true
	_move_to(g, e, p.pos, spd * CHASE, gacc, go)
	if go == "fly" and e.pos.distance_to(p.pos) < 40.0:
		e.vx *= 1.04                           # (the last of a stoop)
	if e.pos.distance_to(p.pos) < (e.w + p.w) * 0.5 + 4.0 and e.bite_t <= 0:
		_bite(g, e, p)
	_fall(g, e, gacc, go)
	return true

static func _bite(g, e, p) -> void:
	e.bite_t = 40
	p.hp -= float(e.d["dmg"])
	p.flash = 6
	p.vx += signf((p.pos - e.pos).dot(g.basis_r(atan2(p.pos.y, p.pos.x)))) * 1.5
	p.vy -= 1.2
	scare_one(p, e.pos, 200)
	g.audio.play("hit", p.pos, 0.4)
	if p.hp <= 0.0:
		slay(g, p, e)

## A creature killed by another (not by you: nothing for your satchel), left as a carcass a while.
static func slay(g, p, by) -> void:
	p.dead = true
	g.audio.play("foe_die", p.pos, 0.5)
	var b: Dictionary = p.d["def"]["body"]
	for k in 18:
		var col: Color = Color(b["base"]) if k % 3 != 0 else Color(0.6, 0.1, 0.08)
		g._particle(p.pos, Vector2(randf() - 0.5, -randf() * 0.8) * 1.8, 30 + randi() % 20, col, false, 0.08)
	var a := atan2(p.pos.y, p.pos.x)
	var foot: Vector2 = p.pos + g.basis_d(a) * (p.h * 0.5)
	g.eco_carcasses.append({"pos": foot, "type": p.type, "facing": p.facing, "t": 2400, "h": p.h})
	if by != null:
		by.prey = null
		by.eat_t = 360
		by.hunger_t = 3600
		by.goal_p = foot

static func _carcass_near(g, p: Vector2, r: float) -> Dictionary:
	for cc in g.eco_carcasses:
		if (cc["pos"] as Vector2).distance_squared_to(p) < r * r:
			return cc
	return {}

## The carcasses: they fall to the ground (or rise to the top of the water they died in), fade, and
## flies buzz over them. (One killed mid-hop stayed in the air where it died: user, 21 Nov.)
static func update_world(g) -> void:
	for k in range(g.eco_carcasses.size() - 1, -1, -1):
		var cc: Dictionary = g.eco_carcasses[k]
		cc["t"] = int(cc["t"]) - 1
		if int(cc["t"]) <= 0:
			g.eco_carcasses.remove_at(k)
			continue
		if int(cc["t"]) % 30 == 0:
			cc["rest"] = false                 # (ground dug out from under it: it falls again)
		if not cc.get("rest", false) and g.in_grid(cc["pos"], 4.0):
			var p: Vector2 = cc["pos"]
			var up: Vector2 = p.normalized()
			if Defs.KIND[g.type_at(p + up * 0.5)] == Defs.K_LIQUID:
				cc["pos"] = p + up * 0.25      # (it floats up through the water)
				cc["vy"] = 0.0
				continue
			var vy: float = minf(float(cc.get("vy", 0.0)) + 0.12, 3.0)
			var moved := 0.0
			while moved < vy:
				var st := minf(0.5, vy - moved)
				var kd: int = Defs.KIND[g.type_at(p - up * (st + 0.05))]
				if kd == Defs.K_SOLID or kd == Defs.K_POWDER or kd == Defs.K_LIQUID:
					cc["rest"] = true
					vy = 0.0
					break
				p -= up * st
				moved += st
			cc["pos"] = p
			cc["vy"] = vy
		elif g.frame % 25 == 0 and g.in_grid(cc["pos"], 4.0):
			var up: Vector2 = (cc["pos"] as Vector2).normalized()
			g._particle(cc["pos"] + up * (3.0 + randf() * 5.0) + g.basis_r(atan2(cc["pos"].y, cc["pos"].x)) * (randf() - 0.5) * 8.0,
				Vector2(randf() - 0.5, randf() - 0.5) * 0.4, 40, Color(0.08, 0.08, 0.06), false, 0.0)

# ------------------------------------------------------------- daily life ---
static func _life(g, e, tgt, dist: float, gacc: float, spd: float, go: String) -> int:
	var c: Dictionary = e.d["def"]
	# out of its hours: home to its den (a bird to a perch) and to sleep
	if not active_now(g, e):
		if go == "fly" and not c.get("swim", false):
			if e.doing != "perch":
				e.doing = "perch"
				e.goal_p = find_perch(g, e)
			if e.goal_p == Vector2.ZERO or _perch(g, e, spd):
				e.asleep = true                   # (nowhere to perch: it dozes on the wing)
				e.act = ""
			return DONE
		if go == "burrow" or go == "slither" or e.den == Vector2.ZERO or e.pos.distance_to(e.den) < 8.0 or e.den_t > 600:
			e.asleep = true
			e.act = ""
			e.den_t = 0
			_fall(g, e, gacc, go)
			return DONE
		e.den_t += 1
		_move_to(g, e, e.den, spd, gacc, go)
		_fall(g, e, gacc, go)
		return DONE
	# a storm in the open: off to shelter (an overhang, a tree), and it huddles there
	if e.storm and go != "burrow":
		if go == "fly" and not c.get("swim", false):
			if e.doing != "perch":
				e.doing = "perch"
				e.goal_p = find_perch(g, e)
				e.doing_t = 300
			if e.goal_p == Vector2.ZERO:
				return WANDER
			_perch(g, e, spd)
			return DONE
		if e.doing != "shelter":
			e.doing = "shelter"
			e.doing_t = LENGTH["shelter"][0]
			e.goal_p = find_shelter(g, e)
		if e.goal_p == Vector2.ZERO or _move_to(g, e, e.goal_p, spd * 1.2, gacc, go):
			e.pose = "sleep" if go == "walk" else ""
			e.vx *= 0.7
		_fall(g, e, gacc, go)
		return DONE
	# too close to a territorial one: it faces you and growls (it charges if you stay)
	if e.warn_t > 0 and not tgt.dead:
		e.facing = 1 if (tgt.pos - e.pos).dot(g.basis_r(atan2(e.pos.y, e.pos.x))) > 0.0 else -1
		e.vx *= 0.7
		e.pose = "wind" if (g.frame / 12) % 3 != 0 else ""
		if e.warn_t % 40 == 1:
			g.audio.play("roar", e.pos, 0.35, 1.6)
		_fall(g, e, gacc, go)
		return DONE
	if e.leader != null and (e.leader.dead or e.leader.pos.distance_to(e.pos) > 220.0):
		e.leader = null
	e.doing_t -= 1
	if e.doing_t <= 0 or e.doing == "" or e.doing == "to_water":
		_pick(g, e, c, go)
	var up: Vector2 = e.pos.normalized()
	match e.doing:
		"wander":
			return WANDER
		"follow":
			var off := float(e.follow_off)
			var lp: Vector2 = e.leader.pos + g.basis_r(atan2(e.leader.pos.y, e.leader.pos.x)) * off if e.leader != null else e.home
			if _move_to(g, e, lp, spd, gacc, go) and e.leader != null:
				e.pose = e.leader.pose if e.leader.pose != "wind" else ""
		"graze":
			e.vx *= 0.8
			e.pose = "graze"
			if g.frame % 30 == 0:
				g._particle(_mouth(g, e), up * 0.4 + Vector2(randf() - 0.5, 0.0) * 0.3, 18, Color(0.35, 0.6, 0.25), false, 0.04)
		"sniff":
			e.vx *= 0.8
			if e.doing_t % 40 == 0:
				e.facing = -e.facing
		"rest":
			e.vx *= 0.7
			e.pose = "sleep"
		"drink":
			if e.goal_p == Vector2.ZERO:
				e.goal_p = find_water(g, e, 130.0, true)
				if e.goal_p == Vector2.ZERO:
					e.doing = "graze"
			elif _move_to(g, e, e.goal_p, spd, gacc, go):
				e.pose = "graze"
				if g.frame % 24 == 0:
					g._particle(_mouth(g, e) - up * 2.0, up * 0.2, 24, Color(0.6, 0.8, 1.0, 0.7), true, 0.0)
		"sit", "bask", "coil":
			e.vx *= 0.6 if e.on_ground else 0.95
			if go == "slither" or (go == "fly" and e.d["def"].get("swim", false)):
				e.vy *= 0.9
		"croak":
			e.vx *= 0.6
			e.pose = "croak" if (e.doing_t / 14) % 2 == 0 else ""
			if e.doing_t % 28 == 0:
				g.audio.play("croak", e.pos, 0.6, 1.25 if e.h < 9.0 else 0.85)
		"flick":
			# its tongue out at a fly above it, and back
			var k := 1.0 - float(e.doing_t) / 16.0
			e.aim = (up * 0.8 + g.basis_r(atan2(e.pos.y, e.pos.x)) * float(e.facing) * 0.6).normalized()
			e.tongue = sin(PI * clampf(k, 0.0, 1.0)) * minf(14.0, e.w + 4.0)
			if e.doing_t == 15:
				g._particle(_mouth(g, e) + e.aim * minf(14.0, e.w + 4.0), Vector2.ZERO, 7, Color(0.08, 0.08, 0.06), false, 0.0)
			if e.doing_t <= 1:
				e.tongue = 0.0
			e.vx *= 0.6
		"hop":
			if e.goal_p == Vector2.ZERO:
				var wp := find_water(g, e, 80.0, false) if c.get("habitat", "") == "water" else Vector2.ZERO
				var br: Vector2 = g.basis_r(atan2(e.pos.y, e.pos.x))
				e.goal_p = (wp + br * randf_range(-14.0, 14.0)) if wp != Vector2.ZERO and randf() < 0.6 else e.home + br * randf_range(-40.0, 40.0)
			if hop_to(g, e, e.goal_p, spd, gacc):
				e.doing_t = 0
		"perch":
			if e.goal_p == Vector2.ZERO:
				e.goal_p = find_perch(g, e)
				if e.goal_p == Vector2.ZERO:
					e.doing = "circle"
					return WANDER
			_perch(g, e, spd)
		"circle":
			return WANDER
		"soar":
			var ha := atan2(e.home.y, e.home.x)
			fly_to(g, e, e.home + e.home.normalized() * 70.0 + g.basis_r(ha) * sin(float(g.frame) * 0.006 + e.phase) * 110.0, spd * 0.8, 0.03)
		"lurk":
			e.under = true
		"roost":
			if e.goal_p == Vector2.ZERO:
				e.goal_p = find_ceiling(g, e)
			if e.goal_p == Vector2.ZERO:
				e.doing = "coil"
			elif fly_to(g, e, e.goal_p, spd):
				e.pos = e.goal_p
				e.vx = 0.0
				e.vy = 0.0
		"scavenge":
			var cc := _carcass_near(g, e.goal_p, 6.0)
			if cc.is_empty():
				e.doing = ""
			else:
				var cp: Vector2 = cc["pos"]
				var stand: Vector2 = cp + cp.normalized() * (e.h * 0.5 + 1.0)
				if go == "fly" and e.doing_t > 360:
					# circling it high up first, as vultures do
					var ca := atan2(cp.y, cp.x)
					fly_to(g, e, cp + cp.normalized() * 60.0 + g.basis_r(ca) * sin(float(g.frame) * 0.02) * 40.0, spd, 0.04)
				elif _move_to(g, e, stand, spd, gacc, go):
					e.eat_t = 300
					e.hunger_t = 3000
					cc["t"] = int(cc["t"]) - 900
					e.doing = ""
	_fall(g, e, gacc, go)
	return DONE

## picks what it does next, by its "idle" weights (a follower keeps to its leader)
static func _pick(g, e, c: Dictionary, go: String) -> void:
	var w := _idle_of(c)
	e.goal_p = Vector2.ZERO
	if e.leader != null:
		var ld: String = e.leader.doing
		e.doing = ld if ld in ["graze", "rest", "sniff", "sit", "croak", "lurk"] else "follow"
		e.doing_t = 90 + randi() % 90
		if e.follow_off == 0.0:
			e.follow_off = (8.0 + randf() * 14.0) * (1.0 if randf() < 0.5 else -1.0)
		return
	var tot := 0.0
	for k in w:
		tot += float(w[k])
	var r := randf() * tot
	var pick := "wander"
	for k2 in w:
		r -= float(w[k2])
		if r <= 0.0:
			pick = k2
			break
	if go == "fly" and pick == "perch" and e.pos.length() < g.gpu.surf_at(atan2(e.pos.y, e.pos.x)).x - 30.0:
		pick = "circle"                       # (no trees down here)
	e.doing = pick
	var ln: Array = LENGTH.get(pick, [150, 300])
	e.doing_t = int(ln[0]) + randi() % (int(ln[1]) - int(ln[0]) + 1)
	e.tongue = 0.0

static func _sleep(g, e, gacc: float, go: String) -> void:
	e.vx *= 0.5
	if go == "fly" and not e.d["def"].get("swim", false) and e.doing == "perch" and e.goal_p != Vector2.ZERO:
		e.pos = e.goal_p
		e.vx = 0.0
		e.vy = 0.0
	elif go == "fly" or go == "slither":
		e.vy *= 0.8
	elif go == "burrow":
		e.under = true
	e.pose = "sleep"
	_fall(g, e, gacc, go)
	if not active_now(g, e) or e.storm:
		return
	# its hours have come round (it was only napping through a storm, or the night's over)
	if randf() < 0.004:
		e.asleep = false

## A bird to its perch: it flies there, then sits (true once it's sitting).
static func _perch(g, e, spd: float) -> bool:
	if e.goal_p == Vector2.ZERO:
		return false
	if e.pos.distance_to(e.goal_p) < 3.0:
		e.pos = e.goal_p
		e.vx = 0.0
		e.vy = 0.0
		e.pose = "perch"
		return true
	fly_to(g, e, e.goal_p, spd, 0.08)
	return false

static func _mouth(g, e) -> Vector2:
	var a := atan2(e.pos.y, e.pos.x)
	return e.pos + g.basis_r(a) * float(e.facing) * (e.w * 0.45) + g.basis_d(a) * (e.h * 0.1)

# ------------------------------------------------------------ the land ---
## The surface along a radial line through p: the first ground (solid or powder) going down from
## `above` over p, as a world point on its top; INF where there is none (open sky, water, or p is
## under an overhang it can't see past).
static func surface_under(g, p: Vector2, above := 30.0, below := 80.0) -> Vector2:
	var up := p.normalized()
	var q := p + up * above
	var tries := 0
	while _ground(g.type_at(q)) and tries < 40:
		q += up
		tries += 1
	if tries >= 40:
		return Vector2.INF
	for k in int(above + below) + tries:
		q -= up
		var t: int = g.type_at(q)
		if _ground(t):
			return q + up * 0.5
		if Defs.KIND[t] == Defs.K_LIQUID:
			return Vector2.INF
	return Vector2.INF

## soft ground from s down `d` cells (a burrower fits there)
static func diggable(g, s: Vector2, d: float) -> bool:
	var up := s.normalized()
	for k in range(1, int(d) + 2):
		if not soft(g.type_at(s - up * float(k))):
			return false
	return true

static func depth(e) -> float:
	return 14.0 if e.boss else 6.0

## is there soft ground under p a burrower could come up through?
static func diggable_under(g, p: Vector2) -> bool:
	var s := surface_under(g, p, 10.0, 60.0)
	return s.is_finite() and diggable(g, s, 4.0)

## Under the ground toward a point (along it): never through the air, rock, a floor or water; it waits at
## the edge of the soft ground instead. True if it moved.
static func burrow_toward(g, e, goal: Vector2, spd: float, dpt: float) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var br: Vector2 = g.basis_r(a)
	var along: float = (goal - e.pos).dot(br)
	if absf(along) < 0.5:
		return false
	e.facing = 1 if along > 0.0 else -1
	var np: Vector2 = e.pos + br * clampf(along, -spd, spd)
	var s := surface_under(g, np, dpt + 24.0, 60.0)
	if not s.is_finite() or not diggable(g, s, dpt):
		return false
	e.pos = s - s.normalized() * dpt
	return true

## A burrower under the ground must be IN it: one that finds itself in the open (spawned on the
## surface, the ground dug away round it, an old save) sinks into the soft ground under it, or
## goes back down its hole; with no soft ground anywhere near, a creature leaves.
static func keep_under(g, e) -> void:
	if not e.under:
		e.was_in = false
		return
	if _ground(g.type_at(e.pos)):
		e.was_in = true
		return
	if e.was_in and not e.boss:
		unearth(g, e)                      # (its ground dug away round it: it's flushed out, not gone)
		return
	var dpt := depth(e)
	var s := surface_under(g, e.pos, 6.0, 120.0)
	if s.is_finite() and diggable(g, s, dpt):
		e.pos = s - s.normalized() * dpt
		return
	if e.spot != Vector2.ZERO:
		var s2 := surface_under(g, e.spot, 6.0, 30.0)
		if s2.is_finite() and diggable(g, s2, dpt):
			e.pos = s2 - s2.normalized() * dpt
			return
	if not e.boss:
		e.dead = true                      # (nowhere to burrow: it's gone)

## A burrower whose ground was dug away round it (user, 25 Nov: "I harvested the sand where a worm hole was
## and it dissapeared"): thrown out onto the open ground, where it writhes a while (and can be hit) before
## it digs back into soft ground near it; on rock it stays out.
static func unearth(g, e) -> void:
	e.under = false
	e.was_in = false
	e.act = ""
	e.stranded_t = STRANDED
	var up: Vector2 = e.pos.normalized()
	var br: Vector2 = g.basis_r(atan2(e.pos.y, e.pos.x))
	e.vx = (randf() - 0.5) * 1.2
	e.vy = -1.6
	e.gvel = Vector2.ZERO
	g.audio.play("dig", e.pos, 0.6)
	for k in 8:
		g._particle(e.pos, up * randf_range(0.6, 1.6) + br * randf_range(-0.8, 0.8), 30, Color(0.82, 0.7, 0.5), false, 0.05)

const STRANDED := 150        # frames a dug-out burrower lies out before it tries to dig back in

static func _stranded(g, e, tgt, gacc: float) -> void:
	e.stranded_t -= 1
	e.under = false
	e.act = ""
	e.pose = ""
	# writhing where it lies, edging away from you
	if e.on_ground:
		var side := signf((e.pos - tgt.pos).dot(g.basis_r(atan2(e.pos.y, e.pos.x)))) if tgt != null else 1.0
		e.vx += ((side if side != 0.0 else 1.0) * 0.35 * (0.5 + 0.5 * sin(float(g.frame) * 0.3 + e.phase)) - e.vx) * 0.2
		e.facing = 1 if e.vx >= 0.0 else -1
	_fall(g, e, gacc, "walk")
	if e.stranded_t > 0 and (e.stranded_t > STRANDED - 60 or e.stranded_t % 20 != 0):
		return
	var dpt := depth(e)
	var s := surface_under(g, e.pos, 8.0, 30.0)
	if e.on_ground and s.is_finite() and diggable(g, s, dpt):
		e.stranded_t = 0
		e.under = true
		e.was_in = false
		e.pos = s - s.normalized() * dpt
		g.audio.play("dig", s, 0.5)
	elif e.stranded_t <= 0:
		e.stranded_t = 60                  # (on rock: it stays out, and looks again in a moment)

## Out of the ground after a breach and back down: into the soft ground where it lands, or back down its
## own hole.
static func dig_in(g, e) -> void:
	e.under = true
	var dpt := depth(e)
	var s := surface_under(g, e.pos, 8.0, 40.0)
	if s.is_finite() and diggable(g, s, dpt):
		e.pos = s - s.normalized() * dpt
	else:
		e.pos = e.spot - e.spot.normalized() * dpt
	keep_under(g, e)

## Water along the ground within `reach` (a frog's pond, a beast's drinking place): the water's edge
## (`edge`: the last dry ground before it), or the water itself; ZERO if none.
static func find_water(g, e, reach: float, edge: bool) -> Vector2:
	var a := atan2(e.pos.y, e.pos.x)
	var br: Vector2 = g.basis_r(a)
	var best := Vector2.ZERO
	var bd := 1e9
	for side in [-1.0, 1.0]:
		var dry := Vector2.ZERO
		var k := 4.0
		while k <= reach:
			var q: Vector2 = e.pos + br * side * k
			if not g.in_grid(q, 6.0):
				break
			var top := q + q.normalized() * 30.0
			var found := false
			for j in 70:
				var t: int = g.type_at(top)
				var kd: int = Defs.KIND[t]
				if t == Defs.WATER:
					if k < bd:
						bd = k
						best = (dry if edge and dry != Vector2.ZERO else top)
					found = true
					break
				if kd == Defs.K_SOLID or kd == Defs.K_POWDER:
					dry = top + top.normalized() * (e.h * 0.5 + 0.5)
					break
				top -= top.normalized()
			if found:
				break
			k += 5.0
	return best

## a tree's crown top near it (a bird's perch), or open ground if there's no tree
static func find_perch(g, e) -> Vector2:
	var a := atan2(e.pos.y, e.pos.x)
	var br: Vector2 = g.basis_r(a)
	var b: Dictionary = e.d["def"]["body"]
	var feet: float = BossArt.bird_feet(b) if String(b["plan"]) == "bird" else e.h * 0.5
	var best := Vector2.ZERO
	var bd := 1e9
	for k in range(-10, 11):
		var q: Vector2 = e.pos + br * float(k) * 6.0
		var top := q + q.normalized() * 50.0
		if not g.in_grid(top, 4.0):
			continue
		for j in 110:
			var t: int = g.type_at(top)
			var bg := _bg(g, top)
			if bg == 3 or t == Defs.LEAF or Defs.KIND[t] == Defs.K_SOLID or Defs.KIND[t] == Defs.K_POWDER:
				var d: float = absf(float(k)) * 6.0 - (20.0 if bg == 3 or t == Defs.LEAF else 0.0)
				if d < bd:
					bd = d
					best = top + top.normalized() * (feet + 0.5)
				break
			if Defs.KIND[t] == Defs.K_LIQUID:
				break
			top -= top.normalized()
	return best

## the cave roof over it (a glow worm hangs there), or ZERO
static func find_ceiling(g, e) -> Vector2:
	var up: Vector2 = e.pos.normalized()
	for k in range(int(e.h * 0.5) + 1, 60):
		var q: Vector2 = e.pos + up * float(k)
		if _solid(g, q):
			return q - up * (e.h * 0.5 + 1.0)
	return Vector2.ZERO

## somewhere out of the rain near it: under an overhang, a roof or a tree; ZERO if none
static func find_shelter(g, e) -> Vector2:
	var a := atan2(e.pos.y, e.pos.x)
	var br: Vector2 = g.basis_r(a)
	for k in [0, 8, -8, 16, -16, 26, -26, 38, -38, 52, -52, 68, -68, 86, -86, 104, -104]:
		var q: Vector2 = e.pos + br * float(k)
		var s := surface_under(g, q, 20.0, 40.0)
		if not s.is_finite():
			continue
		if sheltered(g, s + s.normalized() * 2.0):
			return s + s.normalized() * (e.h * 0.5 + 0.5)
	return Vector2.ZERO

static func sheltered(g, p: Vector2) -> bool:
	var up := p.normalized()
	for k in range(4, 44, 3):
		var q := p + up * float(k)
		if _solid(g, q) or _bg(g, q) == 3:
			return true
	return false

static func _solid(g, p: Vector2) -> bool:
	var l: Vector2 = g.to_grid(p)
	return g.gsolid(int(floor(l.x)), int(floor(l.y)))

static func _bg(g, p: Vector2) -> int:
	var l: Vector2 = g.to_grid(p)
	return g.gpu.grid_bg(g._gslot, int(floor(l.x)), int(floor(l.y)))

# --------------------------------------------------------------- the world ---
## Walkers never step into lava (or off into it): run by main.gd just before a creature moves.
static func guard_lava(g, e) -> void:
	if e.boss or not e.d.has("def") or e.d["def"].get("fireproof", false) or absf(e.vx) < 0.05:
		return
	var go: String = e.d["def"]["go"]
	if go != "walk" and go != "hop":
		return
	var l: Vector2 = g.to_grid(e.pos)
	var dirx := signf(e.vx)
	var fx: float = l.x + dirx * (e.w * 0.5 + 2.0)
	for dy in [0.0, 2.0, 5.0, 9.0]:
		if g.gtype(int(floor(fx)), int(floor(l.y + e.h * 0.5 + dy))) == Defs.LAVA:
			e.vx = 0.0
			if e.act == "" and e.fear_t <= 0:
				e.pace = -e.pace
				e.goal_p = Vector2.ZERO
				e.doing_t = 0
			return

## Habitat: could this creature be met near angle `a` (spawning)? Water-dwellers need water near.
static func habitat_ok(g, id: String, a: float) -> bool:
	var c: Dictionary = Defs.CREATURES[id]
	match String(c.get("habitat", "")):
		"water":
			var n: int = Defs.NS
			for k in range(-40, 41, 2):
				var b: float = a + float(k) * 6.0 / float(n) * TAU
				var sb: Vector4 = g.gpu.surf_b(b)
				if sb.y > g.gpu.surf_at(b).x - 1.0 and int(sb.z) == Defs.WATER:
					return true
			return false
	return true

## how welcome a creature is in the spawn roll now: out of its hours it's met asleep, more rarely
static func spawn_weight(g, id: String, a: float, p: Vector2) -> float:
	if not habitat_ok(g, id, a):
		return 0.0
	var c: Dictionary = Defs.CREATURES[id]
	var act: String = c.get("active", "any")
	if act == "any":
		return 1.0 + (0.4 if c.get("temper", "") == "prey" else 0.0)
	var dl: float = g._local_daylight(p)
	var on: bool = dl > 0.2 if act == "day" else dl < 0.45
	return (1.0 + (0.4 if c.get("temper", "") == "prey" else 0.0)) if on else 0.3

## a creature come across in the wild (main `_try_spawn`): asleep if it isn't its time
static func on_spawn(g, e) -> void:
	if not active_now(g, e):
		e.asleep = true
		e.act = ""
