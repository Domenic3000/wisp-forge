## Space: everything above the orbit band (Defs.R_SPACE).
##
## The camera stays on you, as close as on the ground (the whole planet is on the map, M). While any of
## the planet is on screen it is drawn from its cells (`live`; out here the picture is clear past the
## orbit band, and this node, drawn under it, shows the stars there); once it's out of sight the GPU
## rests and only this node draws: stars, the sun, the other planets where Defs.planet_pos puts them
## (discs grown from their biomes, or the pictures taken as you left them: main.capture_planet), the
## asteroids, and markers at the screen's edge pointing to each planet.
##
## Space shares the world coordinates of `home`, the planet the GPU holds, which sits at the origin.
## Fly toward another planet and, once it is clearly the nearer one, it is made in the background
## while you fly (main.arrive_planet: the planet you left is saved first); until it's ready you can't
## come closer than HOLD above its orbit band. Then everything is moved over so that it is at the
## origin (`_reanchor`), and it becomes home: drop into its orbit band to land.
##
## Asteroids (asteroid.gd, pixel bodies of rock) hang in a few clusters above each planet's orbit
## band (`_ensure_rocks`: grown from the planet's seed the first time, then saved with its world in
## planet_state["asteroids"]). Near one the camera comes in close; hold dig on it to mine it (`mine`,
## the staff's reach and hardness as on the ground); a rock cut through drifts apart into its pieces
## (`_split`), scraps crumble to dust. The mage and the skiff bump against them (`_rock_push`,
## `_rock_solid`). A marker points to the nearest one.
##
## The mage flies by the staff jet (hold cast: a push toward where you aim, paid in mana) inside a
## wisp bubble (no breath needed out here), or the skiff carries the party. The nearest planet pulls,
## fading with distance; the view turns (`view_ang`, eased) to keep it below you.
extends Node2D

const Asteroid := preload("res://scripts/asteroid.gd")
const Galaxy := preload("res://scripts/galaxy.gd")
const Vfx := preload("res://scripts/vfx.gd")
## The galaxy (user, 22 Nov: infinite space). Space's origin follows you (`org`: the galaxy point that
## is (0, 0) out here, as doubles): once you're RECENTRE from it everything out here is moved over so
## you're near (0, 0) again (`_shift`), and coming back within BACK_HOME of home it is put back on home,
## which the GPU world needs at the origin. The planets of the systems round you are `bodies`; the
## sectors round you are streamed in with their asteroid fields and comets (`_stream`), and ones you've
## changed are kept (`sect_state`, saved with the journey). What you've seen is charted for the map.
const RECENTRE := 80000.0
const BACK_HOME := 40000.0
const LOAD_R := 1                 # sectors loaded round yours (a 3 x 3 block); dropped past 2
const SAIL_SPEED := 320.0         # the Starsail: top speed in open space (cells a tick)
const SAIL_ACCEL := 2.5
const SAIL_CLEAR := 22.0
const SKIFF_MAX := 40.0              # (skiff.gd MAX_SPEED)          # it slows to keep this many ticks from anything ahead
const ROCK_SCRAP := 10          # a piece smaller than this (cells) crumbles to dust
const ROCK_DRAG := 0.9995
## lit by the sun: a lumpy sphere's shading (the direction from its middle, bent by its edges),
## and ores that glow by themselves (alpha a hair under 1) left bright
const LIT := "shader_type canvas_item;
uniform vec2 sun = vec2(1.0, 0.0);
uniform vec2 ctr = vec2(0.0);
uniform float rad = 20.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) discard;
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec2 g = vec2(0.0);
	for (int k = 1; k <= 3; k++) {
		float f = float(k);
		g.x += texture(TEXTURE, UV + vec2(px.x * f, 0.0)).a - texture(TEXTURE, UV - vec2(px.x * f, 0.0)).a;
		g.y += texture(TEXTURE, UV + vec2(0.0, px.y * f)).a - texture(TEXTURE, UV - vec2(0.0, px.y * f)).a;
	}
	vec2 p = (UV / px - ctr) / rad;
	vec2 nxy = p * 0.75 - g * 0.2;
	vec3 n = normalize(vec3(nxy, sqrt(max(0.08, 1.0 - min(dot(nxy, nxy), 0.92)))));
	float d = max(dot(n, normalize(vec3(sun, 0.5))), 0.0);
	float lit = 0.14 + 0.98 * d;
	if (c.a < 0.995) lit = max(lit, 1.0);
	COLOR = vec4(c.rgb * lit, 1.0);
}"

const SWAP_ZOOM := 3.0          # zoomed out this far, a cell is smaller than a pixel: the picture takes over
const JET := 0.075              # the staff jet's push, per tick
const JET_MANA := 0.32
const MAX_SPEED := 36.0
const DRAG := 0.999             # (a whisper of drag, so a prototype flight can be steered)
const SUN_DIST := 170000.0
const SUN_R := 9000.0
const HOLD := 3000.0             # a planet still being made: you're held this far above its orbit band
const BELT_IN := 1400.0         # a planet out of the skiff's reach is wrapped in a storm belt: from this far
const BELT_OUT := 4400.0        # above its orbit band out to this. Its wind throws you back, harder the deeper
                                # you go, and lightning strikes; a Core Drive carries the skiff through.
const BEAM_REACH := 150.0       # the Prospector's Beam: how far from the skiff it mines
const NEARER := 0.8             # another planet is clearly nearer: at this fraction of home's distance
const TRAVEL_R := 40000.0       # ...and within this of its middle: then it's made while you come in
const PLANET_MASK := "shader_type canvas_item;
uniform float edge = 0.45;
void fragment() {
	float d = length(UV - vec2(0.5));
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= 1.0 - smoothstep(edge - 0.012, edge, d);
}"

const PixelFont := preload("res://scripts/pixel_font.gd")
var game
var active := false             # the local mage is out in space
var live := true                # the planet is still drawn from its cells (zoomed in close enough)
var easing := false             # back on the planet: the zoom eases back to the chosen view
var vel := Vector2.ZERO         # the mage's velocity out here (world units a tick)
var jetting := false
var cooldown := 0               # (just back from space: a moment before you can leave again)
var pictures := {}              # planet index -> {"tex", "zoom", "angle", "edge"}: how each planet looked as you left
var bodies := []                # this system's planets: {"index", "pos", "top", "space", "name", "tex"}
var stars := []                 # [position in a 1024 x 1024 tile, brightness, twinkle phase]
var sprites := {}               # planet index -> Sprite2D showing its picture
var home := -1                  # the planet the GPU holds, at the origin
var target := -1                # the planet being made while you fly (main.travelling)
var near := {}                  # the nearest planet (one of `bodies`): it pulls, and the view turns to it
var centre := Vector2.ZERO      # (its centre)
var view_ang := 0.0             # the view's turn out here (main.world_to_screen uses it)
var sun_ang := 0.0              # where the sun is (it turns once a day, as on the planet)
var _bodies_for := -1
var _discs := {}                # (each planet's disc picture, kept between journeys: [texture, sun angle])
var rocks := []                 # the asteroids near home (asteroid.gd), in its coordinates
var _rocks_for := -1            # (the planet they belong to)
var _rock_plan := []            # (rocks still to be made for it: one a tick, so arriving doesn't stall)
var _rock_sprites := []
var _lit: Shader
var _mining := 0                # (frames since you last dug at a rock)
var _mask: Shader
var belt := 0.0                 # how deep you are in a storm belt (0 outside it, 1 at its inner edge)
var belt_max := 0.0             # (the deepest since the tests last reset it)
var belt_hits := 0              # (lightning strikes taken: the tests read it)
var bolts := []                 # lightning out here: [points (world), frames left]
var _flash := 0.0               # (a strike lights up the view)
var _belt_warn := 0
var beam_to = null              # the Prospector's Beam: where it reaches now (null when off)
var belt_dir := Vector2.ZERO    # (the way the belt's wind blows where you are, outward)
var _lrects: Array = []         # (labels drawn this frame: a new one steps aside rather than overlap one)
var belt_col := Color.WHITE
var org := PackedFloat64Array([0.0, 0.0])     # the galaxy point that is (0, 0) out here
var seen := {}                  # explored sectors (Galaxy.key_of) for the map
var charted := {}               # systems whose planets are on the map (index -> true)
var waypoint = null             # a galaxy point marked on the map (PackedFloat64Array), or null
var sect_state := {}            # sector key -> its rocks as you left them (mined ones)
var _loaded := {}               # sector key -> Vector2i: sectors whose rocks are out here now
var _sect_plan := []            # rocks of loaded sectors still to be made (one a tick)
var _body_key := ""             # (which systems `bodies` were made for)
var _disc_queue := []           # (planet discs still to be grown: one a tick)
var sail := 0.0                 # the Starsail: how far unfurled (0..1)
var sailing := false
var neb := 0.0                  # how thick the nebula is round you, and its colour
var neb_col := Color.WHITE
var stats := {"recentred": 0, "sectors": 0, "rocks_made": 0}   # (for the tests)

func _ready() -> void:
	_mask = Shader.new()
	_mask.code = PLANET_MASK
	_lit = Shader.new()
	_lit.code = LIT
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for k in 420:
		stars.append([Vector2(rng.randf() * 1024.0, rng.randf() * 1024.0), rng.randf(), rng.randf() * TAU])
	visible = false

# ------------------------------------------------------------- crossing ---

## The mage (or the skiff they ride) has risen to the top of the orbit band: out into space. A party
## travels together: in the skiff, everyone has to be aboard; on foot, only a mage on their own.
func try_enter() -> void:
	if active or cooldown > 0:
		return
	var m = game.player
	var sk = m.aboard
	if sk != null:
		if not sk.aboard_all(game.players):
			if game.frame % 90 == 0:
				game.ui.toast("Everyone has to be aboard to leave the planet", Color(0.8, 0.9, 1.0), 2.0)
			return
	elif game.players.size() > 1:
		if game.frame % 90 == 0:
			game.ui.toast("Your party has to leave together: in the skiff", Color(0.8, 0.9, 1.0), 2.0)
		return
	var a := atan2(m.pos.y, m.pos.x)
	vel = game.basis_r(a) * m.vx + game.basis_d(a) * m.vy
	vel += m.pos.normalized() * 0.6          # (a nudge out, so you don't drop straight back in)
	home = int(game.planet["index"])
	org = Defs.planet_g(home)
	charted[home / Defs.SYSTEM.size()] = true
	pictures[home] = game.capture_planet()
	sun_ang = game.sun_angle()
	_make_bodies(true)
	near = bodies[0]
	for b in bodies:
		if int(b["index"]) == home:
			near = b
	centre = Vector2.ZERO
	view_ang = atan2(game.cam_c.y, game.cam_c.x)
	active = true
	live = true
	easing = false
	jetting = false
	if sk != null:
		game.ui.toast("Space. Fly with WASD (or hold cast toward the cursor)%s; head back down to land. M: the galaxy chart." % (", hold Shift for the Starsail" if game.items.has("sail") else ""), Color(0.75, 0.9, 1.0), 4.5)
	else:
		game.ui.toast("Space. Hold cast to fly by the staff's jet; fall back to land.", Color(0.75, 0.9, 1.0), 4.0)

## Back into the orbit band: the planet's own physics take over again, and the view eases back in.
func exit() -> void:
	var m = game.player
	var sk = game.skiff
	belt = 0.0
	bolts.clear()
	_flash = 0.0
	beam_to = null
	if m.aboard != null:
		sk.pos = sk.pos.normalized() * minf(sk.pos.length(), Defs.R_SPACE - 12.0)
		# (coming back in, the skiff sheds its space speed: it drops into the sky, not through it)
		if sk.vel.length() > 8.0:
			sk.vel = sk.vel.normalized() * 8.0
		game._ride(m)
	else:
		var a := atan2(m.pos.y, m.pos.x)
		m.vx = vel.dot(game.basis_r(a))
		m.vy = clampf(vel.dot(game.basis_d(a)), -6.0, 6.0)
		m.pos = m.pos.normalized() * minf(m.pos.length(), Defs.R_SPACE - 12.0)
		if sk != null and sk.pos.length() > Defs.R_SPACE - 9.0:
			# a skiff left drifting out there follows you home, into the orbit band above you
			sk.pos = m.pos.normalized() * (Defs.R_SPACE - 30.0) + game.basis_r(atan2(m.pos.y, m.pos.x)) * 50.0
			sk.vel = Vector2.ZERO
	if sk != null:
		sk.centre = Vector2.ZERO
	active = false
	live = true
	easing = true
	cooldown = 90
	visible = false
	game.view_rect.visible = true
	game.view_c = Vector2.ZERO           # (take the next picture's camera as it comes)

# ---------------------------------------------------------------- ticks ---

## One tick out in space (main._tick hands over to this while active).
func tick() -> void:
	var m = game.player
	var sk = game.skiff
	sun_ang += TAU / game.day_len()
	var focus: Vector2 = sk.pos if m.aboard != null else m.pos
	_galaxy(focus)
	focus = sk.pos if m.aboard != null else m.pos      # (moved over if space's origin just followed you)
	_find_near(focus)
	_grow_disc()
	_ensure_rocks()
	_stream(focus)
	_update_rocks()
	if sk != null and (sk.pilot() != null or sk.pos.length() > Defs.R_SPACE - 9.5):
		# the skiff: flown by its pilot (keys, or hold cast toward the cursor), or drifting if nobody's
		# aboard (one left down on the planet waits there)
		var pl = sk.pilot()
		sk.centre = centre
		var want: Vector2 = sk.steer(pl.input) if pl != null else Vector2.ZERO
		sk.power = 1.5 if game.items.has("engine") else 1.0
		var v0: Vector2 = sk.vel
		sk.fly(want, pl != null, pull(sk.pos), true, 0.0, 0.9995)
		_sail(sk, pl, want, v0)
		sk.vel = _storm(sk.pos, sk.vel)
		sk.pos = _hold(sk.pos, sk)
		# (it bumps against asteroids: the skiff's own collision, against their cells)
		sk.advance(Callable(self, "_rock_solid") if not _rocks_near(sk.pos, 120.0).is_empty() else Callable())
		for rider in sk.riders:
			if rider != null:
				game._ride(rider)
		if sk.thrusting:
			game._skiff_exhaust()
	_age_bolts()
	beam_to = null
	if m.aboard != null:
		vel = sk.vel
		if sk.pilot() == m and m.input.dig and game.items.has("beam") and not m.dead:
			_beam(m, sk)
		_follow(m)
		_maybe_travel(sk.pos)
		if _landing(sk.pos, sk.vel):
			exit()
		return
	var up: Vector2 = (m.pos - centre).normalized()
	vel -= up * pull(m.pos)
	jetting = false
	var a := up.angle()
	if m.input.cast and m.mana > JET_MANA:
		var d: Vector2 = m.input.aim - m.pos
		if d.length() > 1.0:
			var dir := d.normalized()
			vel += dir * JET
			m.mana -= JET_MANA
			jetting = true
			# wisp-light streaming from the staff, behind you
			for k in 2:
				game._particle(m.pos - dir * 3.0 + Vector2(randf() - 0.5, randf() - 0.5) * 3.0, -dir * (0.6 + randf()) * game.zoom * 0.5 + vel,
					14 + randi() % 10, Color8(140, 220, 255), true, 0.0)
			var side: float = dir.dot(game.basis_r(a))
			if side != 0.0:
				m.facing = 1 if side > 0.0 else -1
	vel *= DRAG
	if vel.length() > MAX_SPEED:
		vel = vel.normalized() * MAX_SPEED
	vel = _storm(m.pos, vel)
	var goal := _hold(m.pos + vel, null)
	var dv: Vector2 = goal - m.pos
	vel = dv
	var close := _rocks_near(m.pos, dv.length() + 30.0)
	if close.is_empty():
		m.pos = goal
	else:
		# near rock: move in small steps so the jet never carries you through one
		var ns := clampi(int(ceil(dv.length() / 2.0)), 1, 40)
		for k in ns:
			m.pos += dv / float(ns)
			if _rock_push(m, close):
				break
	if m.input.dig and not m.dead:
		mine(m)
	m.vx = vel.dot(game.basis_r(a))
	m.vy = vel.dot(game.basis_d(a))
	m.on_ground = false
	m.floating = true
	m.mana = minf(m.max_mana, m.mana + m.mana_regen)
	m.breath = minf(m.max_breath, m.breath + 4.0)       # (inside the wisp bubble)
	if m.iframes > 0:
		m.iframes -= 1
	if m.dig_blocked > 0:
		m.dig_blocked -= 1
	_follow(m)
	_maybe_travel(m.pos)
	if _landing(m.pos, vel):
		exit()

## the nearest planet (by its atmosphere's edge): it pulls, and the view turns toward it
func _find_near(p: Vector2) -> void:
	if bodies.is_empty():
		# (deep space, no planet near: "down" stays the way it was)
		near = {}
		centre = p + (centre - p).normalized() * 400000.0 if centre != p else p + Vector2(0, 400000.0)
		return
	var best := 1e30
	for b in bodies:
		var d: float = (p - b["pos"]).length() - float(b["top"])
		if d < best:
			best = d
			near = b
	centre = near["pos"]

## dropping back into home's orbit band (once it is the planet the GPU holds)
func _landing(p: Vector2, v: Vector2) -> bool:
	if game.travelling or not at_home():
		return false
	return p.length() < Defs.R_SPACE - 10.0 and v.dot(p.normalized()) < 0.0

## A planet that isn't ready yet (one that isn't home, or any while one is being made) keeps you HOLD
## above its orbit band: `p` pushed back out, and a skiff's speed toward it taken away. (One beyond the
## skiff's reach is kept off by its storm belt instead: `_storm`.)
func _hold(p: Vector2, sk) -> Vector2:
	for b in bodies:
		if int(b["index"]) == home and not game.travelling:
			continue
		if not reachable(int(b["index"])):
			continue
		var c: Vector2 = b["pos"]
		var lim: float = float(b["space"]) + HOLD
		var o := p - c
		if o.length() < lim:
			var n := o.normalized()
			if sk != null and sk.vel.dot(n) < 0.0:
				sk.vel -= n * sk.vel.dot(n)
			if game.frame % 120 == 0:
				game.ui.toast("Approaching %s… %d%%" % [b["name"], int(game.travel_progress * 100.0)], Color(0.75, 0.9, 1.0), 2.0)
			p = c + n * lim
	return p

## A planet out of the skiff's reach is wrapped in a storm belt (BELT_IN..BELT_OUT above its orbit band,
## coloured by its kind): you see it from outside as a shimmering curtain, and inside it the wind throws
## you back out, harder the deeper you go, takes the speed you come in with, gusts along the belt, and
## lightning strikes (it hurts and knocks you outward; at the inner edge a great bolt throws you clear).
## Returns the velocity v becomes at p.
func _storm(p: Vector2, v: Vector2) -> Vector2:
	belt = 0.0
	for b in bodies:
		var bi := int(b["index"])
		if bi == home or reachable(bi):
			continue
		var o: Vector2 = p - b["pos"]
		var h: float = o.length() - float(b["space"])
		if h > BELT_OUT:
			continue
		var f := clampf((BELT_OUT - h) / (BELT_OUT - BELT_IN), 0.0, 1.2)
		belt = maxf(belt, f)
		belt_max = maxf(belt_max, f)
		var n := o.normalized()
		belt_dir = n
		belt_col = b["belt"]
		var t := Vector2(-n.y, n.x)
		v += n * (0.03 + 0.85 * f * f)
		var vin := -v.dot(n)
		if vin > 0.0:
			v += n * vin * (0.02 + 0.1 * f)
		v += t * sin(float(game.frame) * 0.021 + o.angle() * 40.0) * 0.12 * f
		var col: Color = b["belt"]
		# wind-blown sparks streaming past: you can see which way it throws you
		for k in int(f * 3.0) + (1 if randf() < f * 3.0 - floorf(f * 3.0) else 0):
			var off: Vector2 = Vector2(randf() - 0.5, randf() - 0.5) * Vector2(game.VW, game.VH).length() * float(game.zoom)
			game._particle(p + off, n * (3.0 + randf() * 4.0) + t * (randf() - 0.5) * 3.0, 16 + randi() % 12, col.lightened(0.3), true, 0.0)
		if f >= 1.0 or randf() < 0.004 + 0.035 * f:
			v += n * (2.0 + 4.0 * f)
			_strike(p, n, f, col)
			if f >= 1.0:
				v = n * 14.0                       # (a great bolt at the inner edge throws you clear)
		_belt_warn -= 1
		if _belt_warn <= 0:
			_belt_warn = 420
			game.ui.toast("%s is wrapped in a storm belt that throws you back. A Core Drive (forged at the Wisp Forge from this world's Planet Core and star iron) carries the skiff through." % b["name"], col.lightened(0.4), 4.5)
	return v

## lightning out of the belt onto whoever is at p: it hurts, shakes the view and lights it up
func _strike(p: Vector2, n: Vector2, f: float, col: Color) -> void:
	var from := p + n.rotated(randf_range(-1.2, 1.2)) * randf_range(140.0, 300.0)
	var pts := PackedVector2Array([from])
	var steps := 9
	for k in range(1, steps):
		var q := from.lerp(p, float(k) / float(steps))
		var side := (p - from).normalized().orthogonal()
		pts.append(q + side * randf_range(-18.0, 18.0) * (1.0 - float(k) / float(steps)))
	pts.append(p)
	bolts.append([pts, 10, col])
	if p.distance_to(game.cam_c) < 500.0:
		_flash = maxf(_flash, 0.25 + 0.3 * f)
		belt_hits += 1
		game.shake = maxf(game.shake, 6.0 + 8.0 * f)
		game.audio.play("zap", null, 0.9)
	for m in game.players:
		if not m.dead and m.pos.distance_to(p) < 60.0:
			game.hurt(m, 3.0 + 6.0 * f, Vector2.ZERO, true)

func _age_bolts() -> void:
	for k in range(bolts.size() - 1, -1, -1):
		bolts[k][1] -= 1
		if int(bolts[k][1]) <= 0:
			bolts.remove_at(k)
	_flash = maxf(0.0, _flash - 0.03)

## The Prospector's Beam: the skiff's pilot holds dig and it mines asteroids at the cursor, up to
## BEAM_REACH from the skiff
func _beam(m, sk) -> void:
	var d: Vector2 = m.input.aim - sk.pos
	if d.length() > BEAM_REACH:
		d = d.normalized() * BEAM_REACH
	var p: Vector2 = sk.pos + d
	beam_to = p
	_mine_at(m, p, m.dig_r * 1.2)

## can the skiff go to planet i? (home and any planet up to its reach; on foot, only home)
func reachable(i: int) -> bool:
	return i == home or i <= game.skiff_reach()

## Clearly nearer to another planet than to home: make it in the background, then move over to it.
func _maybe_travel(p: Vector2) -> void:
	if near.is_empty() or game.travelling or target >= 0 or int(near["index"]) == home or not reachable(int(near["index"])):
		return
	# (and close to it: far out in the dark, which planet is "nearer" means nothing, and making one is work)
	var dn := (p - centre).length()
	if dn < NEARER * (p - home_at()).length() and dn < TRAVEL_R:
		travel(int(near["index"]))

## Saves the planet you're leaving, makes `index` while you fly, then puts it at the origin.
## (A coroutine; space.gd starts it itself, tests may await it.)
func travel(index: int) -> void:
	target = index
	var riding: bool = game.player.aboard != null
	var tname := String(Defs.make_planet(index)["name"])
	game.ui.toast("Bound for %s" % tname, Color(0.75, 0.9, 1.0), 3.0)
	# the planet you leave is written in the background (the skiff you ride goes with you)
	await game.save_world_async(riding)
	await game.arrive_planet(index)
	var ta := Time.get_ticks_usec()
	_reanchor(-Defs.g_rel(Defs.planet_g(index), org))
	home = index
	org = Defs.planet_g(index)
	charted[index / Defs.SYSTEM.size()] = true
	target = -1
	_make_bodies(true)
	_find_near(game.skiff.pos if riding else game.player.pos)
	# the planet's own clock, set so that its sun stands where the sun is now
	game.time += fposmod(sun_ang - game.sun_angle(), TAU) / TAU * game.day_len()
	var t_move := Time.get_ticks_usec() - ta
	# (its picture, and saving it, each in a frame of its own: the first picture from a new device
	# is slow, and with the rest it made the longest frame of a journey)
	await get_tree().process_frame
	ta = Time.get_ticks_usec()
	pictures[home] = game.capture_planet()
	var t_pic := Time.get_ticks_usec() - ta
	game.ui.toast("%s: %s" % [game.planet["name"], game.planet["desc"]], Color(0.8, 0.95, 0.9), 5.0)
	await get_tree().process_frame
	ta = Time.get_ticks_usec()
	game.save_game()
	var t_prog := Time.get_ticks_usec() - ta
	if game.testing:
		print("[travel] after arriving (ms): moving over %d, the planet's picture %d, progress saved %d" % [t_move / 1000, t_pic / 1000, t_prog / 1000])
	await game.save_world_async()

## Moves everything out here by `d` (the new home to the origin).
func _reanchor(d: Vector2) -> void:
	_shift(d)
	# (the old home's asteroids were saved with it; the new home's are made next. The galaxy's stay.)
	for k in range(rocks.size() - 1, -1, -1):
		if rocks[k].sect == "":
			rocks.remove_at(k)
	_rock_plan.clear()
	_rocks_for = -1

## Moves everything out here by `d`, and space's origin with it (the galaxy doesn't move: `org` does).
func _shift(d: Vector2) -> void:
	for m in game.players:
		m.pos += d
		m.grid_g = m.pos
	if game.skiff != null:
		game.skiff.pos += d
	game.cam_c += d
	if game.view_c != Vector2.ZERO:
		game.view_c += d
	game.wisp += d
	for p in game.parts:
		p["pos"] += d
	game.vfx.shift(d)
	centre += d
	for a in rocks:
		a.pos += d
	for b in bodies:
		b["pos"] += d
	for bo in bolts:
		var pts: PackedVector2Array = bo[0]
		for q in pts.size():
			pts[q] += d
		bo[0] = pts
	if beam_to != null:
		beam_to = (beam_to as Vector2) + d
	org[0] -= d.x
	org[1] -= d.y
	stats["recentred"] += 1

## the galaxy point a point out here is
func galaxy_of(p: Vector2) -> PackedFloat64Array:
	return PackedFloat64Array([org[0] + p.x, org[1] + p.y])

## where a galaxy point is out here
func local_of(g: PackedFloat64Array) -> Vector2:
	return Defs.g_rel(g, org)

## where home (the planet the GPU holds) is out here: (0, 0) unless you're far off
func home_at() -> Vector2:
	return local_of(Defs.planet_g(home))

## where the local mage (or the skiff they ride) is out here
func galaxy_focus_local() -> Vector2:
	var m = game.player
	return game.skiff.pos if m.aboard != null and game.skiff != null else m.pos

func at_home() -> bool:
	return home_at() == Vector2.ZERO

## where the local mage is in the galaxy (on a planet: that planet)
func player_g() -> PackedFloat64Array:
	if not active:
		return Defs.planet_g(int(game.planet.get("index", 0)))
	var m = game.player
	return galaxy_of(game.skiff.pos if m.aboard != null and game.skiff != null else m.pos)

## Each tick out here: space's origin follows you far from home and goes back onto home as you come
## back (only while the planet isn't drawn: `live`); the systems round you, what you've seen, the
## nebula you're in, a waypoint reached.
func _galaxy(focus: Vector2) -> void:
	var ha := home_at()
	if ha == Vector2.ZERO:
		if focus.length() > RECENTRE and not live:
			_shift(-focus.round())
	elif (focus - ha).length() < BACK_HOME:
		_shift(-ha)
		org = Defs.planet_g(home)              # (exactly home again)
	elif focus.length() > RECENTRE:
		_shift(-focus.round())
	var g := player_g()
	if game.frame % 30 == 0:
		_make_bodies()
		_scan(g)
	var nb := Galaxy.nebula(g[0], g[1])
	neb = lerpf(neb, float(nb[0]), 0.05)
	neb_col = nb[1]
	if waypoint != null and Defs.g_rel(waypoint, g).length() < 1500.0:
		waypoint = null
		game.ui.toast("Waypoint reached", Color(1.0, 0.85, 0.4), 2.0)
		game.audio.play("coin", null, 0.5)

## what you see round you goes on the map: the sectors within SCAN_R, and a system once you're near it
func _scan(g: PackedFloat64Array) -> void:
	var r := Galaxy.SCAN_R
	var s0 := Galaxy.sector_of(g[0] - r, g[1] - r)
	var s1 := Galaxy.sector_of(g[0] + r, g[1] + r)
	for sy in range(s0.y, s1.y + 1):
		for sx in range(s0.x, s1.x + 1):
			seen[Galaxy.key_of(Vector2i(sx, sy))] = true
	for sr in Galaxy.systems_near(g[0], g[1], Galaxy.CHART_R):
		if not charted.has(sr):
			charted[sr] = true
			game.ui.toast("Charted: the %s system" % Galaxy.star_name(sr), Galaxy.star_col(sr), 3.5)

## The Starsail (items["sail"]): the pilot holds Shift in open space and the skiff runs up to
## SAIL_SPEED the way it's steered (or heading), slowing by itself as anything comes up ahead (a
## planet's air, a storm belt, rock); let go and it sheds the extra speed in a few seconds.
func _sail(sk, pl, want: Vector2, v0: Vector2) -> void:
	var cap: float = SKIFF_MAX * sk.power
	sailing = pl != null and pl.input.sail and game.items.has("sail") and not pl.dead
	sail = move_toward(sail, 1.0 if sailing else 0.0, 0.03)
	if sailing:
		var dir: Vector2 = want if want.length() > 0.05 else (v0.normalized() if v0.length() > 1.0 else Vector2.ZERO)
		if dir != Vector2.ZERO:
			var top := clampf(_clearance(sk.pos, dir) / SAIL_CLEAR, cap, SAIL_SPEED)
			sk.vel = v0.move_toward(dir.normalized() * top, SAIL_ACCEL * (0.4 + sail))
			sk.thrusting = true
		return
	if v0.length() > cap:
		# (let go: the extra speed goes in a few seconds, not at once)
		sk.vel = v0.normalized() * maxf(cap, v0.length() * 0.96)

## how far the way ahead is clear: to the nearest planet's air (or a storm belt round one out of
## reach), or rock, along `dir` (anything within a wide cone counts)
func _clearance(p: Vector2, dir: Vector2) -> float:
	var best := 1e9
	var d := dir.normalized()
	for b in bodies:
		var o: Vector2 = b["pos"] - p
		var edge: float = float(b["space"]) + (BELT_OUT if not reachable(int(b["index"])) else HOLD * 0.5)
		var dist := o.length() - edge
		var t := o.dot(d)
		if dist < 2000.0 or (t > 0.0 and (o - d * t).length() < edge + 3000.0):
			best = minf(best, maxf(dist, 0.0))
	for a in rocks:
		var o2: Vector2 = a.pos - p
		var t2 := o2.dot(d)
		# (only what's in the way: ahead, and near the line you're on)
		if t2 > 0.0 and (o2 - d * t2).length() < a.reach() + 400.0:
			best = minf(best, maxf(t2 - a.reach() - 300.0, 0.0))
	return best

## The sectors round you: their asteroid fields and comets come in (a rock a tick), the ones you've
## left behind go (kept as they are if you mined them).
func _stream(focus: Vector2) -> void:
	if game.frame % 15 == 0:
		var g := galaxy_of(focus)
		var sc := Galaxy.sector_of(g[0], g[1])
		for dy in range(-LOAD_R, LOAD_R + 1):
			for dx in range(-LOAD_R, LOAD_R + 1):
				var s := sc + Vector2i(dx, dy)
				var key := Galaxy.key_of(s)
				if not _loaded.has(key):
					_load_sector(s, key)
		for key2 in _loaded.keys():
			var s2: Vector2i = _loaded[key2]
			if absi(s2.x - sc.x) > LOAD_R + 1 or absi(s2.y - sc.y) > LOAD_R + 1:
				_unload_sector(key2)
	# one rock a tick, so a sector coming in never stalls a frame
	if not _sect_plan.is_empty():
		var pl: Dictionary = _sect_plan.pop_front()
		if not _loaded.has(String(pl["sect"])):
			return
		var a
		if pl.has("save"):
			a = Asteroid.from_save(pl["save"])
			if a == null:
				return
			a.touched = true
		else:
			a = Asteroid.make(int(pl["seed"]), float(pl["r"]), String(pl["kind"]))
			a.vel = pl["vel"]
		a.sect = String(pl["sect"])
		a.pos = local_of(pl["g"])
		if pl.has("orbit") and not (pl["orbit"] as Dictionary).is_empty():
			a.orbit = pl["orbit"]
			a.loop_at = pl["at"]
			a.pos = local_of(_g_add(Galaxy.sector_g(_loaded[a.sect]), a.loop_at + Galaxy.comet_at(a.orbit, game.time)))
		rocks.append(a)
		stats["rocks_made"] += 1

static func _g_add(g: PackedFloat64Array, v: Vector2) -> PackedFloat64Array:
	return PackedFloat64Array([g[0] + v.x, g[1] + v.y])

func _load_sector(s: Vector2i, key: String) -> void:
	_loaded[key] = s
	stats["sectors"] += 1
	var sg := Galaxy.sector_g(s)
	if sect_state.has(key):
		for d in sect_state[key]:
			var dd: Dictionary = (d as Dictionary).duplicate()
			var rp: Array = dd["rel"]
			_sect_plan.append({"sect": key, "save": dd, "g": _g_add(sg, Vector2(float(rp[0]), float(rp[1]))),
				"orbit": dd.get("orbit", {}), "at": Vector2(float(dd.get("at", [0, 0])[0]), float(dd.get("at", [0, 0])[1]))})
		return
	for c in Galaxy.sector_content(s):
		for r in c["rocks"]:
			_sect_plan.append({"sect": key, "seed": r["seed"], "r": r["r"], "kind": r["kind"], "vel": r["vel"],
				"g": _g_add(sg, (c["at"] as Vector2) + (r["off"] as Vector2)), "orbit": r.get("orbit", {}), "at": c["at"]})

func _unload_sector(key: String) -> void:
	var s: Vector2i = _loaded[key]
	var sg := Galaxy.sector_g(s)
	var keep := []
	var any := false
	for k in range(rocks.size() - 1, -1, -1):
		var a = rocks[k]
		if a.sect != key:
			continue
		any = any or a.touched
		keep.append(_rock_save(a, sg))
		rocks.remove_at(k)
	if any:
		sect_state[key] = keep
	_loaded.erase(key)

## a sector's rock as saved: its place from the sector's corner, not out here
func _rock_save(a, sg: PackedFloat64Array) -> Dictionary:
	var d: Dictionary = a.save()
	var g := galaxy_of(a.pos)
	d["rel"] = [g[0] - sg[0], g[1] - sg[1]]
	if not a.orbit.is_empty():
		d["orbit"] = a.orbit
		d["at"] = [a.loop_at.x, a.loop_at.y]
	return d

## For progress.json: what's charted and explored, the waypoint, the sectors you changed (the ones
## loaded now as they are).
func save_state() -> Dictionary:
	var ss := sect_state.duplicate()
	for key in _loaded:
		var sg := Galaxy.sector_g(_loaded[key])
		var keep := []
		var any := false
		for a in rocks:
			if a.sect == key:
				any = any or a.touched
				keep.append(_rock_save(a, sg))
		if any:
			ss[key] = keep
	return {"seen": seen.keys(), "charted": charted.keys(), "waypoint": null if waypoint == null else [waypoint[0], waypoint[1]],
		"sectors": ss}

func load_state(d: Dictionary) -> void:
	seen.clear()
	charted.clear()
	sect_state.clear()
	for k in d.get("seen", []):
		seen[String(k)] = true
	for c in d.get("charted", []):
		charted[int(c)] = true
	var wp = d.get("waypoint", null)
	waypoint = PackedFloat64Array([float(wp[0]), float(wp[1])]) if wp is Array and wp.size() == 2 else null
	var ss = d.get("sectors", {})
	if ss is Dictionary:
		sect_state = ss
	# (a new game: what's round the home planet)
	var hs := Defs.planet_g(0)
	_scan_quiet(hs)
	charted[0] = true

## mark the sectors round a galaxy point seen, without a word (a planet you're on)
func _scan_quiet(g: PackedFloat64Array) -> void:
	var r := Galaxy.SCAN_R
	var s0 := Galaxy.sector_of(g[0] - r, g[1] - r)
	var s1 := Galaxy.sector_of(g[0] + r, g[1] + r)
	for sy in range(s0.y, s1.y + 1):
		for sx in range(s0.x, s1.x + 1):
			seen[Galaxy.key_of(Vector2i(sx, sy))] = true

## the nearest planet's pull out here (per tick, toward its centre): as at the top of its orbit
## band, fading with the square of the distance
func pull(p: Vector2) -> float:
	var top: float = float(near.get("space", Defs.R_SPACE))
	return 0.17 * 0.06 * pow(top / maxf((p - centre).length(), top), 2.0)

## the camera stays on you, as close as on the ground (the user: no zooming out as you leave), turning
## to keep the nearest planet below you. Home (at the origin) is drawn from its cells while any of its
## orbit band is on screen; past that the GPU rests.
func _follow(m) -> void:
	game.zoom = float(game.zoom_levels[0])
	game.cam_c = m.pos                   # (on you exactly: out here you can go very fast)
	var reach: float = Vector2(game.VW, game.VH).length() * 0.5 * game.zoom + 8.0
	live = game.cam_c.length() - Defs.R_SPACE < reach and not game.travelling and at_home()
	var cc: Vector2 = game.cam_c
	var va := (cc - centre).angle()
	if live:
		view_ang = va
	else:
		view_ang = lerp_angle(view_ang, va, 0.03)
		game.view_c = game.cam_c         # (nothing from the GPU to line the sprites up with)
	visible = true
	game.view_rect.visible = live
	queue_redraw()

## Where to keep you (and the skiff) if the game is saved out here: just inside the orbit band
## above where you'd come back down.
func safe_return() -> Vector2:
	var p: Vector2 = game.player.pos - home_at() if active else game.player.pos
	return p.normalized() * (Defs.R_SPACE - 20.0)

## Every tick on the planet: just back from space, the view eases in to the zoom you chose.
## High in the sky (or out here) the stars of space are drawn behind the planet's picture, which fades
## out over the top of the atmosphere (render.comp, P.p[122].w bit 8): climbing out, the sky thins into
## the same starfield you fly through, instead of being swapped for it at the edge of space (user,
## 22 Nov: "the transition to space is still jaring").
func backdrop() -> bool:
	return active or (game.state == "play" and game.cam_c.length() > Defs.R_TOP - 320.0)

var _backdrop_was := false

func planet_tick() -> void:
	var bd := backdrop()
	if bd or _backdrop_was:
		visible = bd
		queue_redraw()
	_backdrop_was = bd
	if cooldown > 0:
		cooldown -= 1
	if game.frame % 600 == 0 and game.planet.has("index"):
		# (the planet you're on and the sky round it are on the map)
		_scan_quiet(Defs.planet_g(int(game.planet["index"])))
		charted[int(game.planet["index"]) / Defs.SYSTEM.size()] = true
	if not easing:
		return
	var zt: float = game.zoom_levels[game.zoom_i]
	game.zoom = lerpf(game.zoom, zt, 0.05)
	if absf(game.zoom - zt) < 0.01:
		game.zoom = zt
		easing = false

# ------------------------------------------------------------- the view ---

## world -> screen as one affine map (valid in the round view, where space always is)
func _world_xf() -> Transform2D:
	var t: Vector2 = game.world_to_screen(Vector2.ZERO)
	return Transform2D(game.world_to_screen(Vector2(1, 0)) - t, game.world_to_screen(Vector2(0, 1)) - t, t)

func _draw() -> void:
	if not active and not backdrop():
		return
	var w: int = game.VW
	var h: int = game.VH
	_lrects.clear()
	draw_rect(Rect2(0, 0, w, h), Color(0.006, 0.006, 0.02))
	var xf := _world_xf()
	# stars: a fixed field turned with the view, drifting as you travel (two depths: the nearer half
	# drifts faster, so you can feel your speed with the camera always on you)
	var rot := xf.x.angle()
	# (galaxy coordinates, as doubles: no jump when space's origin moves, and exact however far out)
	var gcx: float = org[0] + game.cam_c.x
	var gcy: float = org[1] + game.cam_c.y
	var drift := [Vector2(fposmod(gcx * 0.004, 1024.0), fposmod(gcy * 0.004, 1024.0)), Vector2(fposmod(gcx * 0.03, 1024.0), fposmod(gcy * 0.03, 1024.0))]
	var ctr := Vector2(w, h) * 0.5
	var reach := Vector2(w, h).length() * 0.5 + 4.0
	var tw := float(game.frame) * 0.03
	# going fast (the Starsail), the near stars streak past
	var fv: Vector2 = game.skiff.vel if game.player.aboard != null and game.skiff != null else vel
	var streak: Vector2 = fv.rotated(rot) * 0.03 * 5.0 if fv.length() > 60.0 else Vector2.ZERO
	for si in stars.size():
		var s: Array = stars[si]
		var p0: Vector2 = s[0] - drift[si % 2]
		var q := Vector2(fposmod(p0.x, 1024.0) - 512.0, fposmod(p0.y, 1024.0) - 512.0)
		if q.length() > reach:
			continue
		var sp := ctr + q.rotated(rot)
		var b: float = 0.35 + 0.65 * float(s[1]) * (0.75 + 0.25 * sin(tw + float(s[2])))
		if si % 2 == 1 and streak != Vector2.ZERO:
			draw_line(sp, sp + streak.limit_length(160.0), Color(b, b, b * 1.1, 0.8), 1.0)
		else:
			draw_rect(Rect2(sp.floor(), Vector2.ONE), Color(b, b, b * 1.08))
	# a nebula you're in: its colour over everything, and its dust drifting past
	if neb > 0.01:
		draw_rect(Rect2(0, 0, w, h), Color(neb_col.r, neb_col.g, neb_col.b, 0.09 * neb))
		for k in int(60.0 * neb):
			var hs := Vector2(float((k * 7919) % 1024), float((k * 104729) % 1024))
			var p1: Vector2 = hs - drift[1] * 1.6
			var q1 := Vector2(fposmod(p1.x, 1024.0) - 512.0, fposmod(p1.y, 1024.0) - 512.0)
			if q1.length() > reach:
				continue
			var sz := 2.0 + float(k % 4)
			draw_rect(Rect2((ctr + q1.rotated(rot)).floor(), Vector2(sz, sz)), Color(neb_col.r, neb_col.g, neb_col.b, 0.12 + 0.1 * neb))
	if not active:
		return                            # (still in the planet's sky: only the stars behind its fading top)
	# the other systems near you (the nearest three get a marker at the screen's edge, below)
	var g := player_g()
	var near_sys: int = int(near.get("sys", -1))
	var others := []
	for r in Galaxy.systems_near(g[0], g[1], Defs.SYS_GAP * 2.6):
		if r == near_sys:
			continue
		var sv: Vector2 = Defs.g_rel(Defs.system_g(r), g)
		others.append([sv.length(), r, sv])
	others.sort_custom(func(x, y): return x[0] < y[0])

	# the sun, far off where the light comes from (so far that it keeps its place as you travel): as on
	# the planet's sky, a small disc out toward the edge of the view, the way it lies
	var sun_dir: Vector2 = xf.basis_xform(Vector2(cos(sun_ang), sin(sun_ang))).normalized()
	var sun_s: Vector2 = ctr + sun_dir * float(h) * 0.42
	var sun_r := 5.5
	for k in 4:
		draw_circle(sun_s, sun_r * (2.2 - k * 0.38), Color(1.0, 0.85, 0.5, 0.06 + k * 0.05))
	draw_circle(sun_s, sun_r, Color(1.0, 0.97, 0.85))
	# the planets: as they looked when you left them, or as discs grown from their biomes
	var shown := {}
	for bd in bodies:
		var c: Vector2 = bd["pos"]
		var idx := int(bd["index"])
		var pic: Dictionary = pictures.get(idx, {})
		if live and idx == home:
			continue                      # (drawn from its cells, over this)
		if pic.is_empty():
			var rr: float = bd["top"]
			var spc: Vector2 = xf * c
			var rpx: float = rr / game.zoom
			if spc.x + rpx < -20.0 or spc.y + rpx < -20.0 or spc.x - rpx > w + 20 or spc.y - rpx > h + 20:
				pass                          # (off screen)
			elif bd["tex"] == null:
				var bc: Color = bd["col"]
				draw_circle(spc, rpx * 0.82, bc.darkened(0.2))          # (its disc is still being grown)
			else:
				draw_set_transform_matrix(xf)
				draw_texture_rect(bd["tex"], Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false)
				draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			var spr := _sprite_for(idx)
			var zc: float = pic["zoom"]
			var ang: float = pic["angle"]
			# picture pixel (u, v) from its centre is the world point c + camR * u * zc + camD * v * zc
			var pr := Vector2(sin(ang), -cos(ang)) * zc
			var pd := Vector2(-cos(ang), -sin(ang)) * zc
			spr.texture = pic["tex"]
			spr.transform = xf * Transform2D(pr, pd, c)
			(spr.material as ShaderMaterial).set_shader_parameter("edge", pic["edge"])
			spr.visible = true
			shown[idx] = true
		if game.zoom > 8.0:
			_label(xf * c + Vector2(0, (float(bd["top"]) + 60.0) / game.zoom + 6.0), String(bd["name"]))
	for si in sprites:
		if not shown.has(si):
			sprites[si].visible = false
	_draw_belts(xf)
	_draw_rocks(xf)
	# where the planets are when they're off screen: a marker at the edge, pointing the way
	for b2 in bodies:
		if int(b2["sys"]) != near_sys:
			continue                         # (only the system you're in: the others show as their stars)
		var hc := Color(0.6, 1.0, 0.7) if int(b2["index"]) == home else Color(0.85, 0.85, 1.0)
		var bi := int(b2["index"])
		if not reachable(bi):
			hc = Color(0.62, 0.6, 0.66)
		_marker(xf, b2["pos"], b2["top"], String(b2["name"]) + ("" if reachable(bi) else " · storm belt"), hc)
	# the nearest other systems, by their stars (at most three)
	for k3 in mini(3, others.size()):
		var o3: Array = others[k3]
		var sp3: Vector2 = game.cam_c + (o3[2] as Vector2)
		_marker(xf, sp3, 0.0, "%s system" % Galaxy.star_name(int(o3[1])), Galaxy.star_col(int(o3[1])))
	# a waypoint from the map
	if waypoint != null:
		var wl: Vector2 = game.cam_c + Defs.g_rel(waypoint, galaxy_of(game.cam_c))
		var wsp: Vector2 = xf * wl
		if wsp.x > 0 and wsp.y > 0 and wsp.x < w and wsp.y < h:
			var wb := 0.7 + 0.3 * sin(tw * 3.0)
			draw_colored_polygon(PackedVector2Array([wsp + Vector2(0, -5), wsp + Vector2(4, 0), wsp + Vector2(0, 5), wsp + Vector2(-4, 0)]), Color(1.0, 0.82, 0.3, wb))
			_label(wsp + Vector2(0, -8), "Waypoint")
		else:
			_marker(xf, wl, 0.0, "Waypoint", Color(1.0, 0.82, 0.3))
	var nr = nearest_rock(game.player.pos, 20000.0)
	if nr != null:
		_marker(xf, nr.pos, nr.reach(), "Comet" if not nr.orbit.is_empty() else "Asteroid", Color(0.95, 0.82, 0.62))
	# the Starsail unfurled: a glow round the skiff
	if sail > 0.02 and game.skiff != null and game.player.aboard != null:
		var ssp: Vector2 = xf * game.skiff.pos
		var sa := sail * (0.75 + 0.25 * sin(tw * 4.0))
		draw_arc(ssp, 34.0, 0.0, TAU, 40, Color(0.6, 0.9, 1.0, 0.25 * sa), 2.0)
		draw_arc(ssp, 30.0, 0.0, TAU, 40, Color(0.85, 1.0, 1.0, 0.35 * sa), 1.0)
	# you, in your wisp bubble (drawn by the overlay; the bubble here, under the sprite)
	if game.player.aboard == null:
		var ms: Vector2 = xf * game.player.pos
		draw_arc(ms, 11.0, 0.0, TAU, 28, Color(0.55, 0.85, 1.0, 0.35 if jetting else 0.22), 1.0)
	# the Prospector's Beam
	if beam_to != null and game.skiff != null:
		var bd: Vector2 = ((beam_to as Vector2) - game.skiff.pos).normalized()
		var b0: Vector2 = xf * (game.skiff.pos + bd * 22.0)
		var b1: Vector2 = xf * (beam_to as Vector2)
		var fl := 0.6 + 0.4 * sin(float(game.frame) * 0.9)
		draw_line(b0, b1, Color(0.5, 0.95, 1.0, 0.25 * fl), 5.0)
		draw_line(b0, b1, Color(0.85, 1.0, 1.0, 0.8 * fl), 1.5)
		draw_circle(b1, 3.0 + fl * 2.0, Color(0.7, 1.0, 1.0, 0.5))
	# lightning from a storm belt, and the flash it lights the view with
	for bo in bolts:
		var spts := PackedVector2Array()
		for q in bo[0]:
			spts.append(xf * q)
		var bc: Color = bo[2]
		var la := float(bo[1]) / 10.0
		draw_polyline(spts, Color(bc.r, bc.g, bc.b, 0.35 * la), 5.0)
		draw_polyline(spts, Color(1.0, 1.0, 1.0, 0.95 * la), 1.5)
	if belt > 0.0:
		_draw_gale(xf, w, h)
	if belt > 0.0 or _flash > 0.0:
		draw_rect(Rect2(0, 0, w, h), Color(1.0, 1.0, 1.0, _flash * 0.35))

## the storm belts round the planets out of reach: a shimmering curtain at the belt's outer edge (the part
## of the ring near the view), and a haze inside it
func _draw_belts(xf: Transform2D) -> void:
	var hd: float = Vector2(game.VW, game.VH).length() * 0.5 * game.zoom
	var tt := float(game.frame)
	for b in bodies:
		var bi := int(b["index"])
		if bi == home or reachable(bi):
			continue
		var c: Vector2 = b["pos"]
		var r_out: float = float(b["space"]) + BELT_OUT
		var r_in: float = float(b["space"]) + BELT_IN
		var dc: float = (game.cam_c - c).length()
		if dc - hd > r_out + 400.0 or dc + hd < r_in:
			continue
		var col: Color = b["belt"]
		var ac: float = (game.cam_c - c).angle()
		var span := clampf((hd + 600.0) / r_out, 0.02, PI)
		var nseg := 90
		for k in nseg:
			var t0 := ac - span + 2.0 * span * float(k) / float(nseg)
			var t1 := ac - span + 2.0 * span * float(k + 1) / float(nseg)
			var i0 := _shimmer(t0, r_out, tt)
			var i1 := _shimmer(t1, r_out, tt)
			var d0 := Vector2(cos(t0), sin(t0))
			var d1 := Vector2(cos(t1), sin(t1))
			# the curtain: bright at the edge, fading inward and up into long rays
			var mid0 := xf * (c + d0 * r_out)
			var mid1 := xf * (c + d1 * r_out)
			var in0 := xf * (c + d0 * (r_out - 90.0))
			var in1 := xf * (c + d1 * (r_out - 90.0))
			var out0 := xf * (c + d0 * (r_out + 120.0 + 260.0 * i0))
			var out1 := xf * (c + d1 * (r_out + 120.0 + 260.0 * i1))
			var cm0 := Color(col.r, col.g, col.b, 0.18 + 0.4 * i0)
			var cm1 := Color(col.r, col.g, col.b, 0.18 + 0.4 * i1)
			var cz := Color(col.r, col.g, col.b, 0.0)
			draw_polygon(PackedVector2Array([in0, mid0, mid1, in1]), PackedColorArray([cz, cm0, cm1, cz]))
			draw_polygon(PackedVector2Array([mid0, out0, out1, mid1]), PackedColorArray([cm0, cz, cz, cm1]))
			# and the belt's body, a faint haze down to its inner edge
			var deep0 := xf * (c + d0 * r_in)
			var deep1 := xf * (c + d1 * r_in)
			var ch := Color(col.r, col.g, col.b, 0.05 + 0.03 * i0)
			draw_polygon(PackedVector2Array([deep0, in0, in1, deep1]), PackedColorArray([Color(col.r, col.g, col.b, 0.13), ch, ch, Color(col.r, col.g, col.b, 0.13)]))

## inside a storm belt: streaks of its wind racing past outward (more and brighter the deeper you are),
## and a tint of its colour over the view
func _draw_gale(xf: Transform2D, w: int, h: int) -> void:
	var f := clampf(belt, 0.0, 1.0)
	draw_rect(Rect2(0, 0, w, h), Color(belt_col.r, belt_col.g, belt_col.b, 0.05 + 0.1 * f))
	var d: Vector2 = xf.basis_xform(belt_dir).normalized()
	var side := d.orthogonal()
	var span := Vector2(w, h).length()
	var ctr := Vector2(w, h) * 0.5
	var tt := float(game.frame)
	var n := int(30.0 + 90.0 * f)
	for k in n:
		var hs := float((k * 7919) % 1000) / 1000.0
		var hs2 := float((k * 104729) % 1000) / 1000.0
		var spd := 9.0 + 14.0 * hs2 + 10.0 * f
		var along := fposmod(hs * span + tt * spd, span) - span * 0.5
		var across := (hs2 - 0.5) * span + sin(tt * 0.02 + hs * 9.0) * 30.0
		var p: Vector2 = ctr + d * along + side * across
		if p.x < -60.0 or p.y < -60.0 or p.x > w + 60.0 or p.y > h + 60.0:
			continue
		var ln := 18.0 + 50.0 * hs * (0.5 + f)
		var a := (0.12 + 0.3 * hs2) * (0.4 + 0.6 * f)
		draw_line(p, p - d * ln, Color(belt_col.r, belt_col.g, belt_col.b, a), 1.0 + float(k % 3 == 0))

## how bright the curtain is at angle t (rays that drift and pulse)
func _shimmer(t: float, r: float, tt: float) -> float:
	var u := t * r
	return clampf((0.5 + 0.5 * sin(u / 70.0 + tt * 0.05)) * (0.55 + 0.45 * sin(u / 23.0 - tt * 0.031)) + 0.15 * sin(u / 9.0 + tt * 0.11), 0.0, 1.0)

func _sprite_for(idx: int) -> Sprite2D:
	if sprites.has(idx):
		return sprites[idx]
	var spr := Sprite2D.new()
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var mat := ShaderMaterial.new()
	mat.shader = _mask
	spr.material = mat
	add_child(spr)
	sprites[idx] = spr
	return spr

func _marker(xf: Transform2D, wpos: Vector2, rad: float, text: String, col: Color) -> void:
	var w := float(game.VW)
	var h := float(game.VH)
	var sp: Vector2 = xf * wpos
	var rpx: float = rad / game.zoom
	if sp.x + rpx > 0.0 and sp.y + rpx > 0.0 and sp.x - rpx < w and sp.y - rpx < h:
		return                                   # (on screen: it shows itself)
	var ctr := Vector2(w, h) * 0.5
	var dir := (sp - ctr).normalized()
	# where the line from the centre leaves the screen (inset a little)
	var t := minf((w * 0.5 - 10.0) / maxf(absf(dir.x), 0.001), (h * 0.5 - 10.0) / maxf(absf(dir.y), 0.001))
	var at := ctr + dir * t
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([at + dir * 4.0, at - dir * 2.0 + side * 3.0, at - dir * 2.0 - side * 3.0]), col)
	var dist: float = (wpos - game.player.pos).length() - rad
	_label(at - dir * 9.0, "%s  %.0fk" % [text, maxf(dist, 0.0) / 1000.0])

func _label(at: Vector2, text: String) -> void:
	var f: Font = PixelFont.make()
	var px: float = float(game.scale_px)
	draw_set_transform(at, 0.0, Vector2.ONE / px)
	var sz: int = PixelFont.SIZE * int(game.ui.U)
	var wd := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	# (kept on screen: a marker at the edge used to push its label half off it; and moved up or down,
	# toward the middle, while it would overlap a label already drawn)
	var half := wd * 0.5 / px + 6.0
	var cx := clampf(at.x, half, float(game.VW) - half)
	var cy := at.y
	var lh := float(sz + 2 * int(game.ui.U)) / px
	var step := lh if at.y < float(game.VH) * 0.5 else -lh
	for k in 6:
		var rr := Rect2(cx - half, cy - lh, half * 2.0, lh)
		var hit := false
		for o in _lrects:
			if (o as Rect2).intersects(rr):
				hit = true
				break
		if not hit:
			break
		cy += step
	_lrects.append(Rect2(cx - half, cy - lh, half * 2.0, lh))
	if cx != at.x or cy != at.y:
		draw_set_transform(Vector2(cx, cy), 0.0, Vector2.ONE / px)
	draw_string(f, Vector2(-wd * 0.5 + 1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.6))
	draw_string(f, Vector2(-wd * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.85, 0.9, 1.0, 0.85))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------- other planets ---

## This system's planets (the round of Defs.SYSTEM that home belongs to), placed relative to home,
## each with a disc grown from its biomes (their ground's colours in sectors round the globe, seas
## where it has them), its sky as a haze, lit from the sun.
func _make_bodies(force := false) -> void:
	# the systems within Galaxy.BODY_R of you (home's always, while you're near it)
	var g := player_g() if active else Defs.planet_g(home)
	var sys: Array = Galaxy.systems_near(g[0], g[1], Galaxy.BODY_R)
	if not sys.has(home / Defs.SYSTEM.size()) and at_home():
		sys.append(home / Defs.SYSTEM.size())
	sys.sort()
	var key := str(sys) + ":" + str(home)
	if key == _body_key and not force:
		return
	_body_key = key
	_bodies_for = home
	bodies.clear()
	var n: int = Defs.SYSTEM.size()
	var sun_dir := Vector2(cos(sun_ang), sin(sun_ang))
	for r in sys:
		for i in range(r * n, r * n + n):
			var pl: Dictionary = Defs.make_planet(i)
			var top: float = float(pl["radius"]) + Defs.ATMO
			# (a disc is ~17 ms of script: kept until the sun has moved well round, and a new system's
			# grown one a tick (`_grow_disc`), a plain disc of its colour meanwhile)
			var dk := "%d_%d" % [Defs.world_seed, i]
			var dc: Array = _discs.get(dk, [])
			var tex = null
			if dc.is_empty() or absf(angle_difference(float(dc[1]), sun_ang)) > 0.5:
				if r == home / n and dc.is_empty():
					dc = [ImageTexture.create_from_image(_disc_image(pl, sun_dir)), sun_ang]
					_discs[dk] = dc
					tex = dc[0]
				else:
					if not _disc_queue.has(i):
						_disc_queue.append(i)
					if not dc.is_empty():
						tex = dc[0]
			else:
				tex = dc[0]
			bodies.append({"index": i, "pos": local_of(Defs.planet_g(i)), "top": top, "sys": r,
				"space": top + Defs.ORBIT_ROWS, "name": pl["name"], "tex": tex, "belt": Defs.climate(pl)["belt"],
				"col": Defs.COLOR[int(Defs.BIOMES[pl["biomes"][0]]["top"])]})

## one planet disc grown a tick (a system coming into view)
func _grow_disc() -> void:
	if _disc_queue.is_empty():
		return
	var i: int = _disc_queue.pop_front()
	var dk := "%d_%d" % [Defs.world_seed, i]
	var dc := [ImageTexture.create_from_image(_disc_image(Defs.make_planet(i), Vector2(cos(sun_ang), sin(sun_ang)))), sun_ang]
	_discs[dk] = dc
	for b in bodies:
		if int(b["index"]) == i:
			b["tex"] = dc[0]

## a planet's disc picture (for the map's system chart): the one kept for space, or made now
func disc_texture(i: int) -> Texture2D:
	var dk := "%d_%d" % [Defs.world_seed, i]
	var dc: Array = _discs.get(dk, [])
	if dc.is_empty():
		var sa: float = game.sun_angle()
		dc = [ImageTexture.create_from_image(_disc_image(Defs.make_planet(i), Vector2(cos(sa), sin(sa)))), sa]
		_discs[dk] = dc
	return dc[0]

func _disc_image(pl: Dictionary, light: Vector2) -> Image:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = int(pl["seed"])
	noise.frequency = 0.045
	var cols := []
	for b in pl["biomes"]:
		cols.append(Defs.COLOR[int(Defs.BIOMES[b]["top"])])
	var sea := float(pl["sea"]) > 0.0
	var sky: Color = pl["sky"]
	var haze := Color(0.45, 0.65, 1.0) * sky
	var rs := float(pl["radius"]) / (float(pl["radius"]) + Defs.ATMO)
	var half := n * 0.5
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half) / half
			var l := d.length()
			if l > 1.0:
				continue
			if l > rs:
				# the atmosphere's haze, thinning outward, brighter on the sunny side
				var t := (l - rs) / (1.0 - rs)
				var lit_a := clampf(d.normalized().dot(light) * 0.6 + 0.5, 0.15, 1.0)
				var hc := haze * lit_a
				hc.a = (1.0 - t) * (1.0 - t) * 0.55
				img.set_pixel(x, y, hc)
				continue
			var s := d / rs
			var nz := sqrt(maxf(0.0, 1.0 - s.length_squared()))
			var lam := clampf(s.dot(light) + nz * 0.35, 0.0, 1.0) * 0.9 + 0.1
			var ang := fposmod(atan2(s.y, s.x), TAU)
			var nv := noise.get_noise_2d(float(x), float(y))
			var bi := Defs.biome_index_at(pl, ang + nv * 0.6 / float(cols.size()) * TAU)
			var c: Color = cols[bi]
			c = c.lightened(nv * 0.25) if nv > 0.0 else c.darkened(-nv * 0.3)
			if sea and nv < -0.05:
				c = Color(0.16, 0.36, 0.68).darkened(clampf(-nv, 0.0, 0.5))
			c = c * lam
			c = c.lerp(haze * lam, 0.18)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img

# ------------------------------------------------------------- asteroids ---

## The asteroids of home: loaded with its world, or grown from its seed the first time (a few
## clusters over its orbit band, each of its own kind: stony, icy, metallic).
func _ensure_rocks(all := false) -> void:
	var idx := int(game.planet.get("index", -1))
	if idx >= 0 and idx != _rocks_for and idx == home:
		_rocks_for = idx
		rocks.clear()
		_rock_plan.clear()
		var saved = game.planet_state.get("asteroids", null)
		if typeof(saved) == TYPE_ARRAY:
			for d in saved:
				_rock_plan.append({"save": d})
		else:
			# (every draw from the planet's seed is made here, in the order it always was, so the rocks
			# come out the same however many ticks they take to make)
			var rng := RandomNumberGenerator.new()
			rng.seed = int(game.planet.get("seed", idx)) ^ 0xA57E
			var ncl := 3
			var a0 := rng.randf() * TAU
			for c in ncl:
				var ca := a0 + float(c) * TAU / float(ncl) + rng.randf_range(-0.3, 0.3)
				var cpos := Vector2(cos(ca), sin(ca)) * (Defs.R_SPACE + rng.randf_range(700.0, 1900.0))
				var ckind: String = Asteroid.KINDS[c % Asteroid.KINDS.size()]
				for k in rng.randi_range(2, 4):
					var kind: String = ckind if k == 0 or rng.randf() < 0.65 else "stony"
					var r := rng.randf_range(12.0, 34.0) if k > 0 else rng.randf_range(26.0, 38.0)
					var rs := rng.randi()
					var p := cpos + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 240.0 * float(mini(k, 1))
					var v := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.01
					_rock_plan.append({"seed": rs, "r": r, "kind": kind, "pos": p, "vel": v})
	if _rocks_for != home:
		return
	var ha := home_at()
	while not _rock_plan.is_empty():
		var pl: Dictionary = _rock_plan.pop_front()
		if pl.has("save"):
			var a = Asteroid.from_save(pl["save"])
			if a != null:
				a.pos += ha
				rocks.append(a)
		else:
			var a2 = Asteroid.make(int(pl["seed"]), float(pl["r"]), String(pl["kind"]))
			a2.pos = (pl["pos"] as Vector2) + ha
			a2.vel = pl["vel"]
			# (not on top of one already there)
			for o in rocks:
				var gap: Vector2 = a2.pos - o.pos
				if gap.length() < a2.reach() + o.reach():
					a2.pos = o.pos + gap.normalized() * (a2.reach() + o.reach() + 10.0)
			rocks.append(a2)
		if not all:
			break

## for saving with the world: home's asteroids, or null if they aren't the ones for `index`
func rocks_state(index: int) -> Variant:
	if _rocks_for != index:
		return null
	_ensure_rocks(true)               # (any still to be made: all of them are saved)
	var out := []
	var ha := home_at()
	for a in rocks:
		if a.sect != "":
			continue                      # (the galaxy's: kept with the journey, not this world)
		var d: Dictionary = a.save()
		d["pos"] = [a.pos.x - ha.x, a.pos.y - ha.y]
		out.append(d)
	return out

## They drift and turn; what you dug at is rebuilt (a few frames at a time) and split if it came
## apart. Pieces that drift far off are gone.
func _update_rocks() -> void:
	_mining += 1
	var ha := home_at()
	for k in range(rocks.size() - 1, -1, -1):
		var a = rocks[k]
		if not a.orbit.is_empty() and _loaded.has(a.sect):
			# a comet keeps to its loop (where it is follows from the time: the same whenever you come)
			var np := local_of(_g_add(Galaxy.sector_g(_loaded[a.sect]), a.loop_at + Galaxy.comet_at(a.orbit, game.time)))
			a.vel = np - a.pos
			a.pos = np
			if game.frame % 2 == 0 and a.pos.distance_to(game.cam_c) < 1600.0:
				_comet_tail(a)
		else:
			a.pos += a.vel
		a.ang = wrapf(a.ang + a.omega, -PI, PI)
		a.vel *= ROCK_DRAG
		if a.dust > 0 and (game.frame % 6 == 0 or _mining > 2):
			a.settle_mass()
			# (splitting is a flood over its cells: only once you stop digging, or now and then)
			if _mining > 8 or game.frame % 45 == 0:
				_split(a)
		if a.mass < 1.0 or (a.sect == "" and (a.pos - ha).length() > Defs.R_SPACE + 12000.0):
			rocks.remove_at(k)

## a comet's tail: ice and light streaming away from the sun and behind it
func _comet_tail(a) -> void:
	var away := -Vector2(cos(sun_ang), sin(sun_ang))
	var back: Vector2 = -a.vel.normalized() if a.vel.length() > 0.01 else away
	var dir := (away * 0.6 + back * 0.4).normalized()
	for q in 2:
		var p: Vector2 = a.pos + Vector2(randf() - 0.5, randf() - 0.5) * a.rad * 1.2
		game.vfx.spawn(Vfx.GLOW, p, a.vel * 0.6 + dir * (0.6 + randf() * 1.6), 90 + randi() % 60,
			Color(0.7, 0.9, 1.0, 0.5), Color(0.4, 0.6, 1.0, 0.0), 2.5, 9.0, true, 0.0, 0.995)
	if randf() < 0.5:
		game.vfx.spawn(Vfx.DOT, a.pos, a.vel * 0.5 + dir * (1.0 + randf() * 2.5) + Vector2(randf() - 0.5, randf() - 0.5) * 0.5, 60 + randi() % 50,
			Color(0.9, 0.97, 1.0), Color(0.5, 0.7, 1.0, 0.0), 1.0, 0.5, true, 0.0, 0.99)

## A rock cut through: its smaller pieces drift off as rocks of their own, scraps crumble to dust.
func _split(a) -> void:
	var pcs: Array = a.pieces()
	if pcs.size() <= 1 and (pcs.is_empty() or pcs[0].size() >= ROCK_SCRAP):
		return
	for k in range(pcs.size()):
		var piece: PackedInt32Array = pcs[k]
		if k == 0 and piece.size() >= ROCK_SCRAP:
			continue                       # (the biggest stays this rock)
		if piece.size() < ROCK_SCRAP:
			for ci in piece:
				var col := Color.hex((Defs.PAL[int(a.cells[ci]) * 4 + (int(a.vars[ci]) & 3)] << 8) | 0xff)
				game._particle(a.cell_world(ci % a.w, ci / a.w), a.vel + Vector2(randf() - 0.5, randf() - 0.5) * 0.4, 40 + randi() % 40, col, false, 0.0)
				a.take(ci)
			continue
		var b = a.split_off(piece)
		var away: Vector2 = (b.pos - a.pos).normalized()
		b.vel += away * 0.04
		a.vel -= away * 0.04 * b.mass / maxf(a.mass, 1.0)
		rocks.append(b)
		game.audio.play("creak", b.pos, 0.6)
	a.settle_mass()

## Dig at the rock under the cursor (within the staff's reach): its cells come into the satchel at
## the pace and by the hardness rules of digging on a planet; dust streams to you.
func mine(m) -> void:
	_mine_at(m, game._reach(m, m.input.aim), m.dig_r)

## digs the asteroid cells within r of p into m's satchel (what m's staff can cut)
func _mine_at(m, p: Vector2, r: float) -> void:
	var hard := false
	var got := 0
	for a in _rocks_near(p, r + 2.0):
		var b: Vector2 = a.to_body(p) + a.com
		for j in range(maxi(0, int(b.y - r - 1.0)), mini(a.h, int(b.y + r + 2.0))):
			for i in range(maxi(0, int(b.x - r - 1.0)), mini(a.w, int(b.x + r + 2.0))):
				var ck: int = j * a.w + i
				var t: int = a.cells[ck]
				if t == 0 or Vector2(i + 0.5, j + 0.5).distance_to(b) > r:
					continue
				if Defs.HARD[t] > m.tier:
					hard = true
					continue
				if randf() > 0.32 / (1.0 + float(Defs.HARD[t]) * 1.2):
					continue
				a.take(ck)
				m.inv[t] += 1
				got += 1
				if randf() < 0.5:
					game.parts.append({"pos": a.cell_world(i, j), "vel": Vector2(randf() - 0.5, randf() - 0.5), "life": 60,
						"col": Defs.COLOR[t], "self": true, "grav": 0.0, "home": true})
	if got > 0:
		_mining = 0
		game.audio.play("dig", p, 0.7)
	if hard:
		m.dig_blocked = 30

## home's own asteroids (its clusters, saved with its world; not the galaxy's)
func home_rocks() -> Array:
	var out := []
	for a in rocks:
		if a.sect == "":
			out.append(a)
	return out

## the asteroids within `pad` of their reach of p
func _rocks_near(p: Vector2, pad: float) -> Array:
	var out := []
	for a in rocks:
		var lim: float = a.reach() + pad
		if (a.pos - p).length_squared() < lim * lim:
			out.append(a)
	return out

## the nearest asteroid to p (by its edge), within `within`; null if none
func nearest_rock(p: Vector2, within := 900.0) -> Variant:
	var best = null
	var bd := within
	for a in rocks:
		var d: float = (a.pos - p).length() - a.reach()
		if d < bd:
			bd = d
			best = a
	return best

## is world point p inside an asteroid's cell? (the skiff collides by this)
func _rock_solid(p: Vector2) -> bool:
	for a in _rocks_near(p, 2.0):
		if a.solid_at(p):
			return true
	return false

## The mage inside a rock: pushed back out the way it faces you, keeping the rock's own drift and
## losing the speed you had into it (and some along it). True if it touched.
func _rock_push(m, close: Array) -> bool:
	var ua: float = (m.pos - centre).angle()
	var rr: Vector2 = game.basis_r(ua)
	var dd: Vector2 = game.basis_d(ua)
	var hw: float = float(m.w) * 0.5
	var hh: float = float(m.h) * 0.5
	var pts := [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(-hw, hh), Vector2(hw, hh), Vector2(-hw, 0.0), Vector2(hw, 0.0),
		Vector2(0.0, -hh), Vector2(0.0, hh), Vector2.ZERO]
	var touched := false
	for a in close:
		var inside := false
		for q in pts:
			if a.solid_at(m.pos + rr * q.x + dd * q.y):
				inside = true
				break
		if not inside:
			continue
		touched = true
		var n: Vector2 = (m.pos - a.pos).normalized()
		for step in 60:
			m.pos += n * 0.5
			var still := false
			for q2 in pts:
				if a.solid_at(m.pos + rr * q2.x + dd * q2.y):
					still = true
					break
			if not still:
				break
		var rel: Vector2 = vel - a.vel
		if rel.dot(n) < 0.0:
			rel -= n * rel.dot(n)
		vel = a.vel + rel * 0.8
	return touched

## each rock as a sprite of its cells, turned with it, lit by the sun
func _draw_rocks(xf: Transform2D) -> void:
	while _rock_sprites.size() < rocks.size():
		var spr := Sprite2D.new()
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var mat := ShaderMaterial.new()
		mat.shader = _lit
		spr.material = mat
		add_child(spr)
		_rock_sprites.append(spr)
	var sun := Vector2(cos(sun_ang), sin(sun_ang))
	var vw := float(game.VW)
	var vh := float(game.VH)
	for k in _rock_sprites.size():
		var spr2: Sprite2D = _rock_sprites[k]
		if k >= rocks.size():
			spr2.visible = false
			continue
		var a = rocks[k]
		var sp: Vector2 = xf * a.pos
		var rp: float = a.reach() / game.zoom + 2.0
		if sp.x < -rp or sp.y < -rp or sp.x > vw + rp or sp.y > vh + rp:
			spr2.visible = false
			continue
		spr2.visible = true
		spr2.texture = a.texture()
		var ax: Vector2 = a.axis_x()
		var ay: Vector2 = a.axis_y()
		spr2.transform = xf * Transform2D(ax, ay, a.pos) * Transform2D(Vector2.RIGHT, Vector2.DOWN, -a.com)
		var sm := spr2.material as ShaderMaterial
		sm.set_shader_parameter("sun", Vector2(sun.dot(ax), sun.dot(ay)).normalized())
		sm.set_shader_parameter("ctr", a.com)
		sm.set_shader_parameter("rad", a.rad * 1.2)
