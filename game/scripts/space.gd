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
const Wreck := preload("res://scripts/wreck.gd")
const Pirate := preload("res://scripts/pirate.gd")
const Outpost := preload("res://scripts/outpost.gd")
const Station := preload("res://scripts/station.gd")
const Alien := preload("res://scripts/alien.gd")
const Spacer := preload("res://scripts/spacer.gd")
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
const SAIL_BURN := 150.0        # wisp fuel (user, 23 Nov: "Only the long hauls"): the Starsail burns a Wisp Cell this
const JOURNEY_CELLS := 3        # many ticks; a journey to another planet costs this many (twice into another system)
const SKIFF_MAX := 40.0              # (skiff.gd MAX_SPEED)          # it slows to keep this many ticks from anything ahead
const ROCK_SCRAP := 10          # a piece smaller than this (cells) crumbles to dust
const ROCK_DRAG := 0.9995
## lit by the sun: a lumpy sphere's shading (the direction from its middle, bent by its edges),
## and ores that glow by themselves (alpha a hair under 1) left bright
const LIT := "shader_type canvas_item;
uniform vec2 sun = vec2(1.0, 0.0);
uniform vec2 ctr = vec2(0.0);
uniform float rad = 20.0;
uniform float flat_l = 0.0;
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
	vec2 nxy = mix(p * 0.75 - g * 0.2, -g * 0.22, flat_l);
	vec3 n = normalize(vec3(nxy, sqrt(max(0.08, 1.0 - min(dot(nxy, nxy), 0.92)))));
	float d = max(dot(n, normalize(vec3(sun, 0.5))), 0.0);
	float lit = mix(0.14 + 0.98 * d, 0.34 + 0.72 * d, flat_l);
	if (c.a < 0.995) lit = max(lit, 1.0);
	COLOR = vec4(c.rgb * lit, 1.0);
}"

const SWAP_ZOOM := 3.0          # zoomed out this far, a cell is smaller than a pixel: the picture takes over
const ZOOMS := [1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]   # the zooms you can choose out here (wheel, - and +)
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
const CANNON_MANA := 6.0        # the Wisp Cannon: mana a shot, ticks between shots, speed, blast radius
const CANNON_CD := 16
const CANNON_SPEED := 9.0
const CANNON_R := 4.5
const SHIELD_RECHARGE := 480.0  # the Wisp Shield: ticks to charge again after it takes a strike
const CACHE_REACH := 18.0       # how near a wreck's cache you open it (F)
const CANNON_DMG := 12.0        # what a cannon bolt takes off a pirate
const PIRATE_BOLT := 7.0        # a pirate's bolt: speed, the hull it carves, what it does to whoever it hits
const PIRATE_BOLT_R := 3.5
const PIRATE_HURT := 9.0        # (a mage on foot, or riders once the hull is down to its floor)
const PIRATE_SHOCK := 2.0       # (riders, when the hull takes it)
const PIRATE_LOSE := 7000.0     # a pirate this far off has lost you
const PIRATE_CLEAR := 8000.0    # pirates only come out of the dark this far above any planet's orbit band
const PIRATE_EVERY := Vector2i(2400, 4200)   # ticks between their chances to find you
const PIRATE_MAX := 3
const CRASH_SPACE := 7.0        # the skiff is hurt hitting rock faster than this
const TRADE_REACH := 40.0       # how near the trader you trade (F)
const BOUNTY := 35              # coins an outpost pays for each pirate you've beaten
const OUTPOST_SAFE := 12000.0   # pirates never come out of the dark this near an outpost...
const OUTPOST_GUNS := 2500.0    # ...and one that comes this near is driven off by its guns
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
var zoom_i := 0                 # the zoom you chose out here (ZOOMS; never changed for you)
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
var stats := {"recentred": 0, "sectors": 0, "rocks_made": 0, "shots": 0, "shot_hits": 0, "caches": 0, "shield_saves": 0,
	"pirates": 0, "pirate_shots": 0, "pirate_hits": 0, "pirates_beaten": 0, "hull_hits": 0, "crashes": 0, "trades": 0, "bounty": 0}   # (for the tests)
var shots := []                 # the Wisp Cannon's bolts: [pos, vel, ticks left]
var _cannon_cd := 0
var shield := 1.0               # the Wisp Shield's charge (1 = ready to take a strike)
var shield_hit := 0             # (frames since it took one: drawn as a flash)
var _rock_backs := []           # a wreck's back layer, a sprite under its hull's
var _top: Node2D                # drawn over the rocks: prompts, cannon bolts, the shield
var _mid: Node2D                # over the rocks but UNDER the mage (overlay): aliens, traders, spacers
var near_cache = null           # the closed cache you could open now (a wreck's cache dict) and its wreck
var foe_shots := []             # pirates' bolts: [pos, vel, ticks left, the ship that fired]
var _pirate_t := 1800           # ticks to the pirates' next chance to find you
var allow_pirates := false      # (the test mode: pirates come only when a check asks)
var _hull_warn := 1.0           # (the hull warning given last, so it's said once per step down)
var near_trader = null          # the outpost whose keeper you're beside (F trades), or null
var near_keeper = null          # (that keeper: outpost.gd's Trader)
var near_folk = null            # a spacer you're beside in an outpost (F talks), or null
var folk := []                  # the spacers of the outposts streamed in (Spacer)
var _cast_note := 0
var docked = null               # the outpost whose hangar the skiff is in, or null
var near_wreck = null
# derelict stations (station.gd) and their aliens (alien.gd)
const STATION_DOWN := 400000.0  # inside a station, "down" is its floor: `centre` is put this far under it
const ST_JET := 0.085           # a dead room's jet: the movement keys push you (cast casts)
const ST_JET_MANA := 0.12
const ST_DRAG := 0.985
const ALIEN_NEAR := 1400.0      # aliens are ticked while you're this near their station
var station_state := {}         # a station's seed (String) -> {"open": [cache], "seal": bool, "dead": [alien ids]}
var aliens := []                # the aliens of the stations out here now
var acid := []                  # what they spit: [pos, vel, ticks left, damage]
var sbolts := []                # your spells out here (in a station): {"type", "pos", "vel", "life", "st"}
var in_station = null           # the station the local mage is inside (its rooms), or null
var frame_st = null             # the station whose floor is "down" now (you're within its bounds), or null
var st_room := -1               # (the room you were in last: a note when you come into another)
var _st_jump := false
var _st_b := Vector2.ZERO       # (the mage's place in the station's cells last tick, and the world point it was put at:
var _st_w := Vector2.INF        # kept, so a single float's rounding far out never moves you a hair a tick)
var _drop_t := 0
var _burn := 0.0               # (ticks of sailing since the last Wisp Cell burned)
var _fuel_warn := 0
var _st_jobs := []              # stations being grown on a worker thread: [task id, its plan]
var scan_marks := []            # the Wisp Scanner: [galaxy point, name, colour] of wrecks and stations near you

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
	_mid = Node2D.new()
	add_child(_mid)
	_mid.draw.connect(_draw_mid)
	_top = Node2D.new()
	_top.z_index = 1
	add_child(_top)
	_top.draw.connect(_draw_top)

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
	zoom_i = 0                      # (you come out as close as on the ground; zoom out yourself)
	if sk != null:
		game.ui.toast("Space. Fly with WASD (or hold cast toward the cursor)%s; head back down to land. M: the galaxy chart." % (", hold Shift for the Starsail" if game.items.has("sail") else ""), Color(0.75, 0.9, 1.0), 4.5)
	else:
		game.ui.toast("Space. Hold cast to fly by the staff's jet; fall back to land.", Color(0.75, 0.9, 1.0), 4.0)

## Back into the orbit band: the planet's own physics take over again, and the view eases back in.
func exit() -> void:
	shots.clear()
	acid.clear()
	sbolts.clear()
	in_station = null
	frame_st = null
	_drop_pirates()
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
	_station_frame(focus)
	_grow_disc()
	_ensure_rocks()
	_stream(focus)
	_update_rocks()
	_update_aliens(focus)
	_update_folk(focus)
	_update_acid()
	_update_sbolts()
	if game.frame % 60 == 11:
		_scanner_marks()
	_pirate_chance(focus)
	_update_pirates()
	game._mend_skiff(m)
	if game.build_on and m.aboard != null and not m.dead:
		game._update_cabin(m)
	if sk != null and (sk.pilot() != null or sk.pos.length() > Defs.R_SPACE - 9.5):
		# the skiff: flown by its pilot (keys, or hold cast toward the cursor), or drifting if nobody's
		# aboard (one left down on the planet waits there)
		var pl = sk.pilot()
		sk.centre = centre
		# (with the Wisp Cannon fitted, the cast button fires it: the keys steer)
		var firing: bool = pl != null and game.items.has("cannon") and pl.input.cast
		if firing:
			pl.input.cast = false
		var want: Vector2 = sk.steer(pl.input) if pl != null else Vector2.ZERO
		if firing:
			pl.input.cast = true
			_fire_cannon(pl, sk)
		sk.power = 1.5 if game.items.has("engine") else 1.0
		var v0: Vector2 = sk.vel
		sk.fly(want, pl != null or game.crew_on_deck(), pull(sk.pos), true, 0.0, 0.9995)
		_sail(sk, pl, want, v0)
		sk.vel = _storm(sk.pos, sk.vel)
		sk.pos = _hold(sk.pos, sk)
		# (it bumps against asteroids: the skiff's own collision, against their cells)
		sk.advance(Callable(self, "_rock_solid") if not _rocks_near(sk.pos, 120.0).is_empty() else Callable())
		if sk.bump > CRASH_SPACE:
			skiff_crash(sk)
		for rider in sk.riders:
			if rider != null:
				game._ride(rider)
		for pm in game.players:
			if pm.aboard == sk and pm.deck:
				game._ride(pm)                     # (up and about on its deck)
		if sk.thrusting:
			game._skiff_exhaust()
	_age_bolts()
	_update_shots()
	_update_foe_shots()
	if _cannon_cd > 0:
		_cannon_cd -= 1
	shield = minf(1.0, shield + 1.0 / SHIELD_RECHARGE)
	if shield_hit > 0:
		shield_hit -= 1
	near_cache = null
	near_wreck = null
	near_trader = null
	near_keeper = null
	near_folk = null
	beam_to = null
	_dock_check(sk)
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
	jetting = false
	var a := up.angle()
	if m.cast_cd > 0:
		m.cast_cd -= 1
	if not m.input.cast:
		m.cast_latch = false
	if in_station != null and not m.dead:
		_station_move(m, in_station)
		if m.input.cast and not m.cast_latch:
			if in_station.kind == "outpost":
				# (an outpost is a peaceful place: no spells in its halls)
				m.cast_latch = true
				if game.frame - _cast_note > 240:
					_cast_note = game.frame
					game.ui.toast("Spells stay sheathed in an outpost's halls", Color(0.8, 0.85, 1.0), 2.0)
			else:
				_space_cast(m, in_station)
		_after_move(m, a)
		return
	vel -= up * pull(m.pos)
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
	m.vx = vel.dot(game.basis_r(a))
	m.vy = vel.dot(game.basis_d(a))
	m.on_ground = false
	m.floating = true
	_after_move(m, a)

## on foot out here, after moving (in open space or in a station): digging, what's near, mana and breath
func _after_move(m, _a: float) -> void:
	if m.input.dig and not m.dead:
		mine(m)
	_wreck_near(m)
	_trader_near(m)
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
	var struck := {}
	for m in game.players:
		if not m.dead and m.pos.distance_to(p) < 60.0:
			if m.aboard != null:
				# (aboard, the skiff takes it: once, on the side the bolt comes from)
				if not struck.has(m.aboard):
					struck[m.aboard] = true
					skiff_hit(m.aboard, _first_cell(m.aboard, from, m.aboard.pos), 3.0, 3.0 + 6.0 * f)
				continue
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
	var dn := (p - (near["pos"] as Vector2)).length()
	if dn < NEARER * (p - home_at()).length() and dn < TRAVEL_R:
		# (a journey to another planet burns Wisp Cells: without them it holds you off at its edge, `_hold`)
		var cost := journey_cost(int(near["index"]))
		if not game.free_fuel:
			if fuel() < cost:
				_fuel_note("Not enough Wisp Cells to make landfall on %s: %d needed, you have %d" % [near["name"], cost, fuel()])
				return
			game.player.inv[Defs.WISPCELL] -= cost
			stats["cells_burned"] = int(stats.get("cells_burned", 0)) + cost
			game.ui.toast("%d Wisp Cells burned for the landfall on %s" % [cost, near["name"]], Color(0.6, 0.85, 1.0), 3.0)
		travel(int(near["index"]))

## the skiff's fuel for the long hauls: the Wisp Cells you carry
func fuel() -> int:
	return int(game.player.inv[Defs.WISPCELL])

## what a journey to planet i burns: JOURNEY_CELLS in home's system, twice that into another
func journey_cost(i: int) -> int:
	var same: bool = i / Defs.SYSTEM.size() == home / Defs.SYSTEM.size()
	return JOURNEY_CELLS if same else JOURNEY_CELLS * 2

func _fuel_note(txt: String) -> void:
	if game.frame >= _fuel_warn:
		_fuel_warn = game.frame + 300
		game.ui.toast(txt, Color(0.6, 0.85, 1.0), 4.0)

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
	_st_w = Vector2.INF
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
	for sh in shots:
		sh[0] = (sh[0] as Vector2) + d
	for fs in foe_shots:
		fs[0] = (fs[0] as Vector2) + d
	for ac in acid:
		ac[0] = (ac[0] as Vector2) + d
	for sb in sbolts:
		sb["pos"] = (sb["pos"] as Vector2) + d
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
	# (the Wisp Scanner sees three times as far, and charts systems from farther off)
	var scanner: bool = game.items.has("scanner")
	var r := Galaxy.SCAN_R * (3.0 if scanner else 1.0)
	var s0 := Galaxy.sector_of(g[0] - r, g[1] - r)
	var s1 := Galaxy.sector_of(g[0] + r, g[1] + r)
	for sy in range(s0.y, s1.y + 1):
		for sx in range(s0.x, s1.x + 1):
			seen[Galaxy.key_of(Vector2i(sx, sy))] = true
	for sr in Galaxy.systems_near(g[0], g[1], Galaxy.CHART_R * (1.6 if scanner else 1.0)):
		if not charted.has(sr):
			charted[sr] = true
			game.ui.toast("Charted: the %s system" % Galaxy.star_name(sr), Galaxy.star_col(sr), 3.5)

## The Starsail (items["sail"]): the pilot holds Shift in open space and the skiff runs up to
## SAIL_SPEED the way it's steered (or heading), slowing by itself as anything comes up ahead (a
## planet's air, a storm belt, rock); let go and it sheds the extra speed in a few seconds.
func _sail(sk, pl, want: Vector2, v0: Vector2) -> void:
	var cap: float = SKIFF_MAX * sk.power
	sailing = pl != null and pl.input.sail and game.items.has("sail") and not pl.dead
	var sdir: Vector2 = want if want.length() > 0.05 else (v0.normalized() if v0.length() > 1.0 else Vector2.ZERO)
	if sailing and sdir != Vector2.ZERO and not game.free_fuel:
		# (the Starsail burns Wisp Cells: one now and then while it's out; none left, it won't unfurl)
		if _burn <= 0.0:
			if fuel() <= 0:
				sailing = false
				_fuel_note("The Starsail needs Wisp Cells to burn: refine them at a smelter (wisp ore and coal) or buy them at an outpost")
			else:
				game.player.inv[Defs.WISPCELL] -= 1
				_burn = SAIL_BURN
				stats["cells_burned"] = int(stats.get("cells_burned", 0)) + 1
		if sailing:
			_burn -= 1.0
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
	# a station grown on a worker thread (it's ten times a wreck): in when it's done
	for k in range(_st_jobs.size() - 1, -1, -1):
		var job: Array = _st_jobs[k]
		if WorkerThreadPool.is_task_completed(int(job[0])):
			WorkerThreadPool.wait_for_task_completion(int(job[0]))
			_st_jobs.remove_at(k)
			var jp: Dictionary = job[1]
			if _loaded.has(String(jp["sect"])) and jp.has("made"):
				_place_rock(jp["made"], jp)
	# one rock a tick, so a sector coming in never stalls a frame
	if not _sect_plan.is_empty():
		var pl: Dictionary = _sect_plan.pop_front()
		if not _loaded.has(String(pl["sect"])):
			return
		if String(pl.get("kind", "")) == "station" and not pl.has("save"):
			var sdd := int(pl["seed"])
			var tid := WorkerThreadPool.add_task(func() -> void: pl["made"] = Station.make_station(sdd))
			_st_jobs.append([tid, pl])
			return
		if String(pl.get("kind", "")) == "outpost":
			var osd := int(pl["seed"])
			var osys := int(pl.get("sys", -1))
			var tid2 := WorkerThreadPool.add_task(func() -> void: pl["made"] = Outpost.make_outpost(osd, osys))
			_st_jobs.append([tid2, pl])
			return
		var a
		if pl.has("save"):
			a = _rock_from_save(pl["save"])
			if a == null:
				return
			a.touched = true
		else:
			match String(pl["kind"]):
				"wreck": a = Wreck.make_wreck(int(pl["seed"]), bool(pl.get("first", false)))
				"scrap": a = Wreck.scrap(int(pl["seed"]), float(pl["r"]))
				_: a = Asteroid.make(int(pl["seed"]), float(pl["r"]), String(pl["kind"]))
		_place_rock(a, pl)

## a rock (asteroid, wreck, outpost, station) made for a sector: placed out here, and in
func _place_rock(a, pl: Dictionary) -> void:
	if not pl.has("save"):
		a.vel = pl["vel"]
	a.sect = String(pl["sect"])
	a.pos = local_of(pl["g"])
	if a.kind == "station":
		_station_in(a)
	if a.kind == "outpost":
		_outpost_in(a)
	if a.kind == "outpost" or a.kind == "station":
		# (an outpost stands level over the planet the view turns to: its floors are floors)
		var oup: Vector2 = (a.pos - centre).normalized() if not near.is_empty() else Vector2.from_angle(view_ang)
		a.ang = Vector2(oup.y, -oup.x).angle()
	if pl.has("orbit") and not (pl["orbit"] as Dictionary).is_empty():
		a.orbit = pl["orbit"]
		a.loop_at = pl["at"]
		a.pos = local_of(_g_add(Galaxy.sector_g(_loaded[a.sect]), a.loop_at + Galaxy.comet_at(a.orbit, game.time)))
	rocks.append(a)
	stats["rocks_made"] += 1

## a rock back from its save: a wreck if it was one
func _rock_from_save(d: Dictionary) -> RefCounted:
	if d.has("wreck"):
		return Wreck.from_save(d)
	return Asteroid.from_save(d)

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
			_sect_plan.append({"sect": key, "seed": r["seed"], "r": r["r"], "kind": r["kind"], "vel": r["vel"], "first": r.get("first", false), "sys": r.get("sys", -1),
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
		if a.kind == "station" or a.kind == "outpost":
			_station_out(a)
			rocks.remove_at(k)
			continue                       # (grown again as it was: a station's changes are in station_state)
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
			if a.sect == key and a.kind != "station" and a.kind != "outpost":
				any = any or a.touched
				keep.append(_rock_save(a, sg))
		if any:
			ss[key] = keep
	return {"seen": seen.keys(), "charted": charted.keys(), "waypoint": null if waypoint == null else [waypoint[0], waypoint[1]],
		"sectors": ss, "stations": station_state}

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
	var sts = d.get("stations", {})
	station_state = sts if sts is Dictionary else {}
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

## the camera stays on you, as close as on the ground unless you zoom out yourself (the user: no zooming
## out as you leave; 23 Nov: "a zoom in and out feature in space. Not auto zoom though"), turning
## to keep the nearest planet below you. Home (at the origin) is drawn from its cells while any of its
## orbit band is on screen; past that the GPU rests.
func _follow(m) -> void:
	var zt: float = ZOOMS[zoom_i]
	game.zoom = zt if absf(game.zoom - zt) < 0.02 else lerpf(game.zoom, zt, 0.2)
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
## (built from the view's own angle and zoom, not by differencing screen points of the origin: far from home
## that lost so much to float precision that rocks, wrecks and outposts were drawn dozens of pixels away from
## where they are, the mage and skiff (drawn by the overlay) seemingly outside a station they were inside)
func _world_xf() -> Transform2D:
	if game.screen_xf_ok():
		return game.screen_xf()
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
	# this system's trading outpost (from the galaxy: you can find it before its sector comes in)
	if near_sys >= 0:
		var opl: Vector2 = game.cam_c + Defs.g_rel(Galaxy.system_outpost(near_sys), galaxy_of(game.cam_c))
		_marker(xf, opl, 120.0, Galaxy.outpost_name(near_sys) + " · trading post", Color(1.0, 0.82, 0.45))
		# and its derelict station
		if frame_st == null:
			var stl: Vector2 = game.cam_c + Defs.g_rel(Galaxy.system_station(near_sys), galaxy_of(game.cam_c))
			_marker(xf, stl, 200.0, "Derelict " + Galaxy.station_name(near_sys), Color(0.75, 0.55, 1.0))
	for smk in scan_marks:
		_marker(xf, game.cam_c + Defs.g_rel(smk[0], galaxy_of(game.cam_c)), 100.0, String(smk[1]), smk[2])
	for pa in rocks:
		if pa.kind == "pirate":
			_marker(xf, pa.pos, pa.reach(), "%s, %s" % [String(pa.spec()["name"]).capitalize(), pa.wname], Color(1.0, 0.45, 0.4))
	var nwk = nearest_wreck(game.player.pos)
	if nwk != null:
		_marker(xf, nwk.pos, nwk.reach(), "Wreck of " + String(nwk.wname), Color(0.75, 0.9, 0.85))
	_top.queue_redraw()
	if _mid.get_index() != get_child_count() - 1:
		move_child(_mid, -1)        # (after every rock sprite, still before the overlay's mage)
	_mid.queue_redraw()
	# the Starsail unfurled: a glow round the skiff
	if sail > 0.02 and game.skiff != null and game.player.aboard != null:
		var ssp: Vector2 = xf * game.skiff.pos
		var sa := sail * (0.75 + 0.25 * sin(tw * 4.0))
		draw_arc(ssp, 34.0, 0.0, TAU, 40, Color(0.6, 0.9, 1.0, 0.25 * sa), 2.0)
		draw_arc(ssp, 30.0, 0.0, TAU, 40, Color(0.85, 1.0, 1.0, 0.35 * sa), 1.0)
	# you, in your wisp bubble (drawn by the overlay; the bubble here, under the sprite)
	if game.player.aboard == null and not (in_station != null and in_station.powered_at(in_station.to_body(game.player.pos) + in_station.com)):
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
			var a = _rock_from_save(pl["save"])
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
	if a.kind == "wreck" or a.kind == "pirate" or a.kind == "outpost" or a.kind == "station":
		return                             # (a wreck holds together: its caches are in its cells)
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
				if t == 0 or Vector2(i + 0.5, j + 0.5).distance_to(b) > r or a.guarded(ck):
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
		if a.kind == "wreck" or a.kind == "scrap" or a.kind == "pirate" or a.kind == "outpost" or a.kind == "station":
			continue
		var d: float = (a.pos - p).length() - a.reach()
		if d < bd:
			bd = d
			best = a
	return best

## the nearest wreck (by its edge), within `within`; null if none
func nearest_wreck(p: Vector2, within := 30000.0) -> Variant:
	var best = null
	var bd := within
	for a in rocks:
		if a.kind != "wreck":
			continue
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
	var pts := box_pts(m)
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
		if a.kind == "wreck" or a.kind == "scrap" or a.kind == "pirate" or a.kind == "outpost" or a.kind == "station":
			# (a hull has rooms inside: out the shortest way, never "away from its middle", which would
			# push you on through the wall you touched from inside)
			var out := _shortest_out(m, a, pts, rr, dd)
			if out != Vector2.ZERO:
				m.pos += out
				n = out.normalized()
				var rel0: Vector2 = vel - a.vel
				if rel0.dot(n) < 0.0:
					rel0 -= n * rel0.dot(n)
				vel = a.vel + rel0 * 0.85
				continue
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

## points over the mage's box (4 across, 9 down: no wall two cells thick fits between them)
func box_pts(m, k := 1.0) -> Array:
	var hw: float = float(m.w) * 0.5 * k
	var hh: float = float(m.h) * 0.5 * k
	var out := []
	for yi in 9:
		for xi in 4:
			out.append(Vector2(-hw + hw * 2.0 * float(xi) / 3.0, -hh + hh * 2.0 * float(yi) / 8.0))
	return out

## the least move (up to 6 cells, 16 ways round) that takes the mage's box out of a body's cells
func _shortest_out(m, a, pts: Array, rr: Vector2, dd: Vector2) -> Vector2:
	for step in range(1, 13):
		var dist := float(step) * 0.5
		for k in 16:
			var dv := Vector2.from_angle(float(k) * TAU / 16.0) * dist
			var free := true
			for q in pts:
				if a.solid_at(m.pos + dv + rr * q.x + dd * q.y):
					free = false
					break
			if free:
				return dv
	return Vector2.ZERO

## each rock as a sprite of its cells, turned with it, lit by the sun
func _draw_rocks(xf: Transform2D) -> void:
	while _rock_sprites.size() < rocks.size():
		# (a wreck's back layer under its hull: added first, so it draws first)
		var bspr := Sprite2D.new()
		bspr.centered = false
		bspr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bspr.visible = false
		add_child(bspr)
		_rock_backs.append(bspr)
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
		var bk: Sprite2D = _rock_backs[k]
		bk.visible = false
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
		sm.set_shader_parameter("flat_l", 1.0 if a.kind == "wreck" or a.kind == "scrap" or a.kind == "pirate" or a.kind == "outpost" or a.kind == "station" else 0.0)
		spr2.modulate = Color(1.6, 1.3, 1.3) if a.kind == "pirate" and a.hit_t > 0 else Color.WHITE
		if a.kind == "wreck" or a.kind == "pirate" or a.kind == "outpost" or a.kind == "station":
			bk.visible = true
			bk.texture = a.back_texture()
			bk.transform = spr2.transform

# ------------------------------------------------------------------ wrecks ---

## Near a wreck on foot: the first time you're inside it, its name and fate; and the closed cache within
## reach, if there is one (F opens it: `wreck_interact`).
func _wreck_near(m) -> void:
	for a in _rocks_near(m.pos, 4.0):
		if a.kind != "wreck" and a.kind != "station":
			continue
		var b: Vector2 = a.to_body(m.pos) + a.com
		var inside: bool = a.kind == "wreck" and b.x > 0.0 and b.y > 0.0 and b.x < float(a.w) and b.y < float(a.h) and int(a.bg[int(b.y) * a.w + int(b.x)]) != 0
		if inside and not a.visited:
			a.visited = true
			a.touched = true
			game.ui.toast("Aboard the wreck of %s. %s" % [a.wname, a.fate], Color(0.75, 0.9, 0.85), 5.0)
			game.audio.play("creak", m.pos, 0.7)
		var bd := CACHE_REACH
		for c in a.caches:
			if c["open"]:
				continue
			var d: float = (a.cache_pos(c) as Vector2).distance_to(m.pos)
			if d < bd:
				bd = d
				near_cache = c
				near_wreck = a

## F out in space: open the cache within reach. True if it did.
func wreck_interact(m) -> bool:
	if active and m.aboard == null and near_trader != null:
		open_trade(near_trader, near_keeper)
		return true
	if active and m.aboard == null and near_folk != null:
		_folk_talk(near_folk)
		return true
	if not active or m.aboard != null or near_cache == null:
		return false
	var wk = near_wreck
	var c: Dictionary = near_cache
	wk.open_cache(c)
	stats["caches"] += 1
	if wk.kind == "station":
		(_st_state(wk)["open"] as Array).append(wk.caches.find(c))
	var cp: Vector2 = wk.cache_pos(c)
	game.audio.play("chest_open", cp, 0.9)
	for k in 26:
		game.vfx.spawn(Vfx.DOT, cp, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.4), 30 + randi() % 30,
			Color(1.0, 0.9, 0.5), Color(1.0, 0.6, 0.2, 0.0), 1.5, 0.5, true, 0.0, 0.95)
	game.vfx.spawn(Vfx.GLOW, cp, Vector2.ZERO, 24, Color(1.0, 0.85, 0.45, 0.8), Color(1.0, 0.6, 0.2, 0.0), 8.0, 18.0)
	_loot(m, wk, c)
	near_cache = null
	return true

## What a cache holds, decided as you open it: salvage in the hold, star iron and wisp ingots in the
## engine room, and on the bridge coins, a ship's part you haven't found yet (the first wreck always
## has one), a star chart, a recipe scroll.
func _loot(m, wk, c: Dictionary) -> void:
	var got := []
	var it: Dictionary = game.items
	var give := func(mat: int, n: int) -> void:
		if n > 0:
			m.inv[mat] += n
			got.append("%d %s" % [n, Defs.NAMES[mat]])
	match String(c["kind"]):
		"engine":
			give.call(Defs.STARIRON, randi_range(3, 6))
			give.call(Defs.WISPBAR, randi_range(2, 4))
			give.call(Defs.COPPERBAR, randi_range(2, 4))
		"bridge":
			var coins := randi_range(25, 60)
			it["coins"] = int(it.get("coins", 0)) + coins
			got.append("%d coins" % coins)
			var part := ""
			if wk.first or randf() < 0.7:
				if not it.has("part_shield") and not it.has("shield"):
					part = "part_shield"
				elif not it.has("part_cannon") and not it.has("cannon"):
					part = "part_cannon"
			if part != "":
				it[part] = 1
				game.ui.toast("Salvaged a %s! The Wisp Forge can fit it to your skiff (Travel)" % ("Shield Emitter" if part == "part_shield" else "Cannon Coil"), Color(1.0, 0.85, 0.4), 5.0)
				game.audio.play("rare", null, 0.9)
			else:
				give.call(Defs.STARIRON, randi_range(2, 4))
			if randf() < 0.5:
				_star_chart()
			if randf() < 0.4:
				game._chest_recipe(3)
			game.ui.toast("The captain's log: %s" % wk.fate, Color(0.75, 0.9, 0.85), 4.0)
		"vault":
			# (a derelict station's vault, past the Broodmother: its crew's best)
			var vc := randi_range(120, 220)
			it["coins"] = int(it.get("coins", 0)) + vc
			got.append("%d coins" % vc)
			give.call(Defs.STARIRON, randi_range(6, 10))
			give.call(Defs.WISPBAR, randi_range(4, 8))
			give.call(Defs.XENITE, randi_range(6, 10))
			if not it.has("part_scanner") and not it.has("scanner"):
				it["part_scanner"] = 1
				game.ui.toast("A Scanner Lens! The Wisp Forge can build it into a Wisp Scanner for your skiff (Travel)", Color(0.8, 1.0, 0.6), 5.0)
				game.audio.play("rare", null, 0.9)
			_star_chart()
			game._chest_recipe(3)
			it["potion"] = int(it.get("potion", 0)) + 1
			got.append("a Healing Draught")
		"nest":
			give.call(Defs.XENITE, randi_range(6, 12))
			if randf() < 0.5:
				give.call(Defs.CRYSTAL, randi_range(2, 5))
			var nc := randi_range(20, 50)
			it["coins"] = int(it.get("coins", 0)) + nc
			got.append("%d coins (a lost crewman's)" % nc)
		"lab":
			give.call(Defs.XENITE, randi_range(2, 5))
			give.call(Defs.CRYSTAL, randi_range(2, 4))
			give.call(Defs.GLASS, randi_range(4, 8))
			if randf() < 0.4:
				game._chest_recipe(2)
			if randf() < 0.35:
				it["potion"] = int(it.get("potion", 0)) + 1
				got.append("a Healing Draught")
		"quarters":
			var qc := randi_range(15, 45)
			it["coins"] = int(it.get("coins", 0)) + qc
			got.append("%d coins" % qc)
			if randf() < 0.4:
				it["potion"] = int(it.get("potion", 0)) + 1
				got.append("a Healing Draught")
			if randf() < 0.3:
				_star_chart()
			give.call(Defs.PLANK, randi_range(4, 10))
		"stores":
			give.call(Defs.HULL, randi_range(8, 16))
			give.call(Defs.COPPERBAR, randi_range(3, 6))
			if randf() < 0.6:
				give.call(Defs.WISPBAR, randi_range(2, 4))
			if randf() < 0.35:
				give.call(Defs.STARIRON, randi_range(1, 3))
			var sc := randi_range(10, 30)
			it["coins"] = int(it.get("coins", 0)) + sc
			got.append("%d coins" % sc)
		"pirate":
			# (a pirate's strongbox: their takings)
			var pc := randi_range(45, 110)
			it["coins"] = int(it.get("coins", 0)) + pc
			got.append("%d coins" % pc)
			give.call(Defs.STARIRON, randi_range(2, 5))
			give.call(Defs.WISPBAR, randi_range(2, 4))
			give.call(Defs.HULL, randi_range(8, 14))
			if randf() < 0.35:
				var ores: Array = Defs.KIND_ORES.values()
				if not ores.is_empty():
					give.call(int((ores[randi() % ores.size()] as Dictionary)["mat"]), randi_range(3, 6))
			if randf() < 0.35:
				_star_chart()
			if randf() < 0.35:
				game._chest_recipe(3)
			if randf() < 0.3:
				it["potion"] = int(it.get("potion", 0)) + 1
				got.append("a Healing Draught")
		_:
			give.call(Defs.HULL, randi_range(6, 12))
			if randf() < 0.7:
				give.call(Defs.COPPERBAR, randi_range(2, 4))
			if randf() < 0.5:
				give.call(Defs.PLANK, randi_range(8, 16))
			if randf() < 0.4:
				give.call(Defs.GLASS, randi_range(3, 6))
			if randf() < 0.35:
				give.call(Defs.WISPBAR, randi_range(1, 2))
			if randf() < 0.2:
				give.call(Defs.STARIRON, randi_range(1, 3))
			var cn := randi_range(10, 30)
			it["coins"] = int(it.get("coins", 0)) + cn
			got.append("%d coins" % cn)
			if randf() < 0.2:
				it["potion"] = int(it.get("potion", 0)) + 1
				got.append("a Healing Draught")
	game.ui.toast("The cache held " + ", ".join(got), Color(1.0, 0.9, 0.6), 4.0)

## a star chart from a wreck's bridge: the nearest system you haven't charted goes on your map
func _star_chart() -> void:
	var g := player_g()
	var best := -1
	var bd := 1e18
	for r in Galaxy.systems_near(g[0], g[1], 2400000.0):
		if charted.has(int(r)):
			continue
		var sg: PackedFloat64Array = Defs.system_g(int(r))
		var d: float = (sg[0] - g[0]) * (sg[0] - g[0]) + (sg[1] - g[1]) * (sg[1] - g[1])
		if d < bd:
			bd = d
			best = int(r)
	if best >= 0:
		charted[best] = true
		game.ui.toast("A star chart: the %s system is on your map (M, Tab)" % Galaxy.star_name(best), Color(0.8, 0.9, 1.0), 4.0)

# ------------------------------------------------------------ ship parts ---

## The Wisp Cannon: a bolt of wisp-light from the skiff toward the cursor (the pilot's mana)
func _fire_cannon(pl, sk) -> void:
	if _cannon_cd > 0 or pl.mana < CANNON_MANA or pl.dead:
		return
	var d: Vector2 = pl.input.aim - sk.pos
	if d.length() < 2.0:
		return
	var dir := d.normalized()
	var from: Vector2 = sk.pos + dir * (float(sk.w) * 0.5 + 2.0)
	shots.append([from, sk.vel + dir * CANNON_SPEED, 110])
	pl.mana -= CANNON_MANA
	_cannon_cd = CANNON_CD
	stats["shots"] += 1
	game.vfx.spawn(Vfx.GLOW, from, sk.vel, 8, Color(0.75, 0.95, 1.0), Color(0.4, 0.6, 1.0, 0.0), 6.0, 2.0)
	game.vfx.spawn(Vfx.RING, from, sk.vel, 8, Color(0.6, 0.9, 1.0), Color(0.4, 0.6, 1.0, 0.0), 1.0, 7.0)
	game.audio.play("zap", from, 0.5)

## the bolts fly (in 2-cell steps, so none goes through a thin hull) and burst on rock or hull
func _update_shots() -> void:
	for k in range(shots.size() - 1, -1, -1):
		var sh: Array = shots[k]
		var p: Vector2 = sh[0]
		var v: Vector2 = sh[1]
		var n := maxi(1, int(ceil(v.length() / 2.0)))
		var hit = null
		for q in n:
			p += v / float(n)
			hit = _rock_at(p, null)
			if hit != null:
				break
		sh[0] = p
		sh[2] = int(sh[2]) - 1
		if hit != null:
			if hit.kind == "pirate":
				_hurt_pirate(hit, CANNON_DMG, p)
			_blast_rocks(p, CANNON_R)
			stats["shot_hits"] += 1
			shots.remove_at(k)
		elif int(sh[2]) <= 0:
			shots.remove_at(k)
		elif game.frame % 2 == 0:
			game.vfx.spawn(Vfx.DOT, p, v * 0.1, 10, Color(0.8, 0.95, 1.0), Color(0.4, 0.6, 1.0, 0.0), 1.5, 0.5, true, 0.0, 0.9)

## a cannon bolt bursts: the cells round it are blown away (a wreck's caches stay), as sparks and dust
func _blast_rocks(p: Vector2, r: float) -> void:
	for a in _rocks_near(p, r + 2.0):
		var b: Vector2 = a.to_body(p) + a.com
		for j in range(maxi(0, int(b.y - r - 1.0)), mini(a.h, int(b.y + r + 2.0))):
			for i in range(maxi(0, int(b.x - r - 1.0)), mini(a.w, int(b.x + r + 2.0))):
				var ck: int = j * a.w + i
				var t: int = a.cells[ck]
				if t == 0 or Vector2(i + 0.5, j + 0.5).distance_to(b) > r or a.guarded(ck):
					continue
				if randf() < 0.35:
					game._particle(a.cell_world(i, j), a.vel + Vector2(randf() - 0.5, randf() - 0.5) * 1.2, 30 + randi() % 30,
						Color.hex((Defs.PAL[t * 4 + (int(a.vars[ck]) & 3)] << 8) | 0xff), false, 0.0)
				a.take(ck)
		if a.kind != "outpost" and a.kind != "station":
			a.vel += (a.pos - p).normalized() * 0.02 / maxf(1.0, a.mass / 400.0)
	_mining = 0
	game.vfx.blast(p, 6.0, 2)
	game.audio.play("boom", p, 0.5)

## over the rocks: the cannon's bolts, the shield, the prompt at a cache
func _draw_top() -> void:
	if not active:
		return
	var xf := _world_xf()
	for sh in shots:
		var sp: Vector2 = xf * (sh[0] as Vector2)
		var tail: Vector2 = xf * ((sh[0] as Vector2) - (sh[1] as Vector2) * 1.2)
		_top.draw_line(tail, sp, Color(0.5, 0.8, 1.0, 0.6), 2.0)
		_top.draw_line(tail.lerp(sp, 0.5), sp, Color(0.9, 1.0, 1.0), 1.0)
		_top.draw_rect(Rect2(sp.floor() - Vector2.ONE, Vector2(2, 2)), Color(1, 1, 1))
	var sk = game.skiff
	if sk != null and game.player.aboard != null and game.items.has("shield"):
		var ssp: Vector2 = xf * sk.pos
		var r: float = float(maxi(sk.w, sk.h)) * 0.62 / game.zoom
		if shield_hit > 0:
			var f := float(shield_hit) / 30.0
			_top.draw_arc(ssp, r, 0.0, TAU, 48, Color(0.6, 0.95, 1.0, 0.8 * f), 2.0)
			_top.draw_arc(ssp, r - 3.0, 0.0, TAU, 48, Color(0.85, 1.0, 1.0, 0.5 * f), 1.0)
		elif shield >= 1.0:
			var tw := float(game.frame) * 0.05
			for q in 6:
				var a0 := tw + float(q) * TAU / 6.0
				_top.draw_arc(ssp, r, a0, a0 + 0.35, 6, Color(0.6, 0.9, 1.0, 0.25), 1.0)
	# pirates' bolts, red; a pirate's hull, over it while it's hurt
	for fs in foe_shots:
		var fp: Vector2 = xf * (fs[0] as Vector2)
		var ft: Vector2 = xf * ((fs[0] as Vector2) - (fs[1] as Vector2) * 1.3)
		_top.draw_line(ft, fp, Color(1.0, 0.35, 0.2, 0.6), 2.0)
		_top.draw_line(ft.lerp(fp, 0.5), fp, Color(1.0, 0.8, 0.55), 1.0)
		_top.draw_rect(Rect2(fp.floor() - Vector2.ONE, Vector2(2, 2)), Color(1.0, 0.95, 0.8))
	for pa in rocks:
		if pa.kind != "pirate" or pa.hp >= pa.hp_max:
			continue
		var pc: Vector2 = xf * pa.pos
		var up_s: Vector2 = xf.basis_xform((pa.pos - centre).normalized()).normalized()
		var bar_at: Vector2 = (pc + up_s * (float(pa.h) * 0.55 / game.zoom + 6.0)).floor()
		var bw := 30.0
		_top.draw_rect(Rect2(bar_at - Vector2(bw * 0.5 + 1.0, 1.0), Vector2(bw + 2.0, 4.0)), Color(0.05, 0.02, 0.04, 0.8))
		_top.draw_rect(Rect2(bar_at - Vector2(bw * 0.5, 0.0), Vector2(bw * clampf(pa.hp / pa.hp_max, 0.0, 1.0), 2.0)), Color(1.0, 0.35, 0.3))
	_draw_alien_marks(xf)
	# each outpost's name over it
	for oa in rocks:
		if oa.kind != "outpost":
			continue
		var osp: Vector2 = xf * oa.pos
		if osp.distance_to(Vector2(game.VW, game.VH) * 0.5) > Vector2(game.VW, game.VH).length() * 0.5 + oa.reach() / game.zoom:
			continue
		var up_o: Vector2 = xf.basis_xform(-oa.axis_y()).normalized()
		_top_text(osp + up_o * (float(oa.h) * 0.55 / game.zoom + 8.0), oa.wname, Color(1.0, 0.85, 0.5))
	# an outpost's shop signs over its counters, the prompt by the one you're at, what spacers say
	for sa in rocks:
		if sa.kind != "outpost" or sa.pos.distance_to(game.player.pos) > 500.0:
			continue
		for skp in sa.keepers:
			var sgn: Vector2 = sa.to_world(skp.b + Vector2(0.0, -34.0) - sa.com)
			if near_keeper != skp:
				_top_text(xf * sgn, String(Outpost.OP_ROOMS[skp.shop]).to_upper(), Outpost.SHOP_COL[skp.shop])
	if near_trader != null and near_keeper != null:
		var kw: Vector2 = near_trader.to_world(near_keeper.b + Vector2(0.0, -34.0) - near_trader.com)
		_top_text(xf * kw, "[F] trade with %s, %s" % [near_keeper.name, String(Outpost.OP_ROOMS[near_keeper.shop]).to_lower()], Color(1.0, 0.88, 0.5))
	for f2 in folk:
		if f2.say_t > 0:
			_top_text(xf * (f2.world() - f2.op.axis_y() * 16.0), f2.say, Color(0.92, 0.95, 1.0))
		elif f2 == near_folk:
			_top_text(xf * (f2.world() - f2.op.axis_y() * 16.0), "[F] talk to %s" % f2.name, Color(1.0, 0.88, 0.5))
	if near_cache != null and near_wreck != null:
		var cp: Vector2 = xf * (near_wreck.cache_pos(near_cache) as Vector2)
		var f2: Font = PixelFont.make()
		var px: float = float(game.scale_px)
		var sz: int = PixelFont.SIZE * int(game.ui.U)
		var txt := "[F] open the cache"
		var wd := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		_top.draw_set_transform(cp + Vector2(0, -30), 0.0, Vector2.ONE / px)
		_top.draw_string(f2, Vector2(-wd * 0.5 + 1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.7))
		_top.draw_string(f2, Vector2(-wd * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(1.0, 0.88, 0.5))
		_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ----------------------------------------------------------- the skiff hit ---

## the first rock (or wreck, or ship) with a cell at p, but `skip`; null if none
func _rock_at(p: Vector2, skip) -> Variant:
	for a in _rocks_near(p, 2.0):
		if a != skip and a.solid_at(p):
			return a
	return null

## where a line from `from` to `to` first meets a body's cells (`to` if it never does)
func _first_cell(body, from: Vector2, to: Vector2) -> Vector2:
	var d := to - from
	var n := int(ceil(d.length()))
	for k in n:
		var p := from + d * (float(k) / float(maxi(n, 1)))
		if body.solid_at(p):
			return p
	return to

## Something strikes the skiff at p (a pirate's bolt, lightning, rock it crashed into): the Wisp Shield
## takes it if it's charged (out here); else its hull is carved there (r) and its riders shaken, or, once
## the hull is down to its floor, hurt (`through`).
func skiff_hit(sk, p: Vector2, r: float, through: float) -> void:
	if active and game.items.has("shield") and shield >= 1.0:
		# (the Wisp Shield takes the strike, then needs a while to charge again)
		shield = 0.0
		shield_hit = 30
		stats["shield_saves"] += 1
		game.vfx.spawn(Vfx.RING, sk.pos, Vector2.ZERO, 18, Color(0.6, 0.95, 1.0), Color(0.4, 0.7, 1.0, 0.0), 30.0, 44.0)
		game.audio.play("blink", sk.pos, 0.8)
		return
	stats["hull_hits"] += 1
	var n: int = sk.damage(p, r)
	for k in 10:
		game.vfx.spawn(Vfx.DOT, p, sk.vel + Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.8), 20 + randi() % 20,
			Color(1.0, 0.8, 0.45), Color(0.9, 0.4, 0.2, 0.0), 1.5, 0.5, true, 0.0, 0.93)
	game.vfx.spawn(Vfx.GLOW, p, sk.vel, 10, Color(1.0, 0.75, 0.4, 0.8), Color(1.0, 0.4, 0.2, 0.0), 7.0, 2.0)
	game.shake = maxf(game.shake, 5.0)
	game.audio.play("crack", p, 0.8)
	for rider in sk.riders:
		if rider != null:
			if n == 0:
				game.hurt(rider, through, Vector2.ZERO, true)
			else:
				game.hurt(rider, PIRATE_SHOCK, Vector2.ZERO, false)
	_hull_warning(sk)

## the skiff ran into rock (or the ground) hard: the faster, the bigger the hole
func skiff_crash(sk) -> void:
	stats["crashes"] += 1
	var lim: float = CRASH_SPACE if active else 9.0          # (main CRASH_PLANET)
	var r := clampf(1.5 + (sk.bump - lim) * 0.35, 1.5, 5.0)
	skiff_hit(sk, sk.bump_at, r, sk.bump * 0.8)

## a word as the hull goes down past 75%, half, and its floor
func _hull_warning(sk) -> void:
	var f: float = sk.hull_f
	if f > _hull_warn:
		_hull_warn = f
	for step in [0.75, 0.5, 0.25]:                           # (the last: skiff.gd HULL_FLOOR)
		if f <= float(step) and _hull_warn > float(step):
			_hull_warn = float(step)
			var msg := "The skiff's hull is holed. Hold R by it or aboard to mend it (Hull Plating or planks, and mana)"
			if float(step) == 0.5:
				msg = "The hull is at half, and its engine %s. Hold R to mend it" % ("is hit" if sk.engine_f < 0.9 else "holds")
			elif float(step) < 0.5:
				msg = "The hull can't take much more: hits will go through to you. Mend it (R) or run!"
			game.ui.toast(msg, Color(1.0, 0.6, 0.45), 4.0)
			return

# --------------------------------------------------------------- pirates ---

## Out in deep space, now and then, pirates find you: only aboard the skiff, never near a planet, not
## while you outrun everything under the Starsail, and only once you've a cannon to answer them with
## (or are far out from the first system).
func _pirate_chance(focus: Vector2) -> void:
	var m = game.player
	if m.aboard == null or game.travelling or (game.testing and not allow_pirates):
		return
	_pirate_t -= 1
	if _pirate_t > 0:
		return
	_pirate_t = randi_range(PIRATE_EVERY.x, PIRATE_EVERY.y)
	if not pirates_ok() or pirate_count() >= 2 or game.skiff.vel.length() > 50.0:
		return
	if not near.is_empty() and (focus - centre).length() - float(near["space"]) < PIRATE_CLEAR:
		return
	if nearest_outpost(focus, OUTPOST_SAFE) != null:
		return
	if randf() < 0.55:
		spawn_pirates(focus)

func pirates_ok() -> bool:
	return game.items.has("cannon") or Defs.g_rel(player_g(), Defs.planet_g(0)).length() > 150000.0

func pirate_count() -> int:
	var n := 0
	for a in rocks:
		if a.kind == "pirate":
			n += 1
	return n

## Pirates come out of the dark round `focus` (from `dir`, or any way): a cutter, a brig, or two
## cutters (or the class asked for). Returns them.
func spawn_pirates(focus: Vector2, dir := Vector2.ZERO, cls := "") -> Array:
	var group := []
	var roll := randf()
	if cls != "":
		group = [cls]
	elif roll < 0.25:
		group = ["brig"]
	elif roll < 0.45:
		group = ["cutter", "cutter"]
	else:
		group = ["cutter"]
	var d: Vector2 = dir.normalized() if dir != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
	var made := []
	for k in group.size():
		if pirate_count() >= PIRATE_MAX:
			break
		var pr = Pirate.make_pirate(randi() & 0xFFFFFF, String(group[k]))
		pr.pos = focus + d.rotated(float(k) * 0.35) * randf_range(1300.0, 1700.0)
		pr.sect = "pirate"
		pr.vel = (focus - pr.pos).normalized() * float(pr.spec()["max_v"]) * 0.6
		var up: Vector2 = (pr.pos - centre).normalized()
		var head: Vector2 = (focus - pr.pos).normalized()
		pr.facing = 1 if head.dot(Vector2(up.y, -up.x)) >= 0.0 else -1
		pr.ang = (head * float(pr.facing)).angle()
		rocks.append(pr)
		made.append(pr)
		stats["pirates"] += 1
	if not made.is_empty():
		var p0 = made[0]
		var txt := "Pirates! %s, a %s, comes out of the dark" % [String(p0.wname).capitalize(), p0.spec()["name"]]
		if made.size() > 1:
			txt = "Pirates! Two cutters come out of the dark, %s leading" % String(p0.wname).capitalize()
		game.ui.toast(txt, Color(1.0, 0.45, 0.4), 4.0)
		game.audio.play("rumble", null, 0.8)
	return made

## (landing or falling: the pirates and their bolts are gone, and anything torn off one that has no
## sector to keep it)
func _drop_pirates() -> void:
	for k in range(rocks.size() - 1, -1, -1):
		if rocks[k].kind == "pirate" or rocks[k].sect == "pirate":
			rocks.remove_at(k)
	foe_shots.clear()

## Each pirate works round you at its range (a ring it circles, now one way, now the other), matching
## your speed, keeping off rock, each other and any planet's air; it turns its bow on you to fight, and
## fires its guns (leading you) every so often. Too far off, it has lost you.
func _update_pirates() -> void:
	var m = game.player
	var sk = game.skiff
	var riding: bool = m.aboard != null and sk != null
	var tgt: Vector2 = sk.pos if riding else m.pos
	var tv: Vector2 = sk.vel if riding else vel
	for k in range(rocks.size() - 1, -1, -1):
		var pr = rocks[k]
		if pr.kind != "pirate":
			continue
		if pr.hit_t > 0:
			pr.hit_t -= 1
		var sp: Dictionary = pr.spec()
		var to: Vector2 = tgt - pr.pos
		var d := to.length()
		if d > PIRATE_LOSE or m.dead:
			rocks.remove_at(k)
			if not m.dead:
				game.ui.toast("You've shaken off %s" % pr.wname, Color(0.8, 0.9, 1.0), 3.0)
			continue
		var guard = nearest_outpost(pr.pos, OUTPOST_GUNS)
		if guard != null:
			# (an outpost's guns drive pirates off: a flash, and it's gone into the dark)
			game.vfx.blast(pr.pos, 10.0, 2)
			rocks.remove_at(k)
			game.ui.toast("%s's guns drive off %s" % [guard.wname, pr.wname], Color(1.0, 0.85, 0.4), 3.0)
			continue
		pr.side_t -= 1
		if pr.side_t <= 0:
			pr.side_t = randi_range(240, 420)
			if randf() < 0.4:
				pr.side = -pr.side
		var rng_: float = sp["range"]
		var off: Vector2 = (-to / d if d > 1.0 else Vector2.RIGHT).rotated(0.5 * float(pr.side))
		# (a ring flattened top to bottom, as the screen is: it fights where you can see it)
		var vup: Vector2 = (tgt - centre).normalized()
		var vright := Vector2(vup.y, -vup.x)
		var want: Vector2 = tgt + (vright * off.dot(vright) + vup * off.dot(vup) * 0.55) * rng_
		var dv: Vector2 = (want - pr.pos) * 0.035 + tv
		for o in _rocks_near(pr.pos, 90.0):
			if o == pr:
				continue
			var aw: Vector2 = pr.pos - o.pos
			var gap: float = aw.length() - o.reach() - pr.reach() * 0.6
			if gap < 70.0:
				dv += aw.normalized() * (70.0 - gap) * 0.08
		if not near.is_empty():
			var oc: Vector2 = pr.pos - centre
			if oc.length() < float(near["space"]) + 600.0:
				dv += oc.normalized() * 6.0
		dv = dv.limit_length(float(sp["max_v"]))
		var acc := float(sp["accel"])
		var dvv: Vector2 = dv - pr.vel
		pr.thrusting = dvv.length() > acc * 0.5
		pr.vel += dvv.limit_length(acc)
		# its bow on you once it's close enough to fight, else the way it goes
		var head: Vector2 = to / maxf(d, 0.001)
		if d > rng_ * 2.0 and pr.vel.length() > 0.5:
			head = pr.vel.normalized()
		var up: Vector2 = (pr.pos - centre).normalized()
		var right := Vector2(up.y, -up.x)
		# (a ship keeps its deck up: it pitches toward you only so far, never stands on its stern)
		var hx: float = head.dot(right)
		var elev := clampf(atan2(head.dot(up), absf(hx)), -0.45, 0.45)
		var hside: float = 1.0 if hx >= 0.0 else -1.0
		if absf(hx) < 0.3:
			hside = float(pr.facing)               # (straight above or below: keep the way it faces)
		head = right * hside * cos(elev) + up * sin(elev)
		if head.dot(right) * float(pr.facing) < -0.3:
			pr.facing = -pr.facing
			pr.ang = (head * float(pr.facing)).angle()
		else:
			pr.ang = lerp_angle(pr.ang, (head * float(pr.facing)).angle(), 0.06)
		if pr.thrusting and game.frame % 2 == 0 and pr.pos.distance_to(game.cam_c) < 1200.0:
			game._particle(pr.stern_world() + Vector2(randf() - 0.5, randf() - 0.5) * 4.0, -pr.nose() * (1.0 + randf()) + pr.vel * 0.7,
				12 + randi() % 8, Color8(255, 110, 60), true, 0.0)
		pr.fire_t -= 1
		if pr.fire_t <= 0:
			pr.fire_t = randi_range(int(sp["fire"][0]), int(sp["fire"][1]))
			if d < rng_ * 2.2 and not m.dead:
				_pirate_fire(pr, tgt, tv, d)

## a volley from a pirate's guns, led to where you'll be
func _pirate_fire(pr, tgt: Vector2, tv: Vector2, d: float) -> void:
	for gk in pr.guns.size():
		if not pr.gun_ok(gk):
			continue
		var from: Vector2 = pr.gun_world(gk)
		var t := d / PIRATE_BOLT
		var aim: Vector2 = tgt + (tv - pr.vel) * t * 0.8
		var dir: Vector2 = (aim - from).normalized().rotated(randf_range(-0.05, 0.05))
		foe_shots.append([from, pr.vel + dir * PIRATE_BOLT, int(d / PIRATE_BOLT) + 90, pr])
		stats["pirate_shots"] += 1
		game.vfx.spawn(Vfx.GLOW, from, pr.vel, 8, Color(1.0, 0.6, 0.35), Color(1.0, 0.3, 0.2, 0.0), 6.0, 2.0)
		game.vfx.spawn(Vfx.RING, from, pr.vel, 8, Color(1.0, 0.5, 0.3), Color(1.0, 0.3, 0.2, 0.0), 1.0, 7.0)
	game.audio.play("zap", pr.pos, 0.45, 0.6)

## pirates' bolts fly (2-cell steps) and strike the skiff, a mage on foot, or rock
func _update_foe_shots() -> void:
	var m = game.player
	var sk = game.skiff
	for k in range(foe_shots.size() - 1, -1, -1):
		var sh: Array = foe_shots[k]
		var p: Vector2 = sh[0]
		var v: Vector2 = sh[1]
		var src = sh[3]
		var n := maxi(1, int(ceil(v.length() / 2.0)))
		var done := false
		for q in n:
			p += v / float(n)
			if sk != null and (sk.pos - p).length() < float(maxi(sk.w, sk.h)) and sk.solid_at(p):
				stats["pirate_hits"] += 1
				skiff_hit(sk, p, PIRATE_BOLT_R, PIRATE_HURT)
				done = true
				break
			if m.aboard == null and not m.dead and _hits_mage(m, p):
				stats["pirate_hits"] += 1
				game.hurt(m, PIRATE_HURT, v.normalized() * 2.0, true)
				game.vfx.spawn(Vfx.GLOW, p, vel, 10, Color(1.0, 0.6, 0.35, 0.8), Color(1.0, 0.3, 0.2, 0.0), 6.0, 2.0)
				done = true
				break
			var hr = _rock_at(p, src)
			if hr != null:
				if hr.kind != "pirate":
					_chip(hr, p, 2.0)
				done = true
				break
		sh[0] = p
		sh[2] = int(sh[2]) - 1
		if done or int(sh[2]) <= 0:
			foe_shots.remove_at(k)
		elif game.frame % 2 == 0:
			game.vfx.spawn(Vfx.DOT, p, v * 0.1, 10, Color(1.0, 0.6, 0.35), Color(1.0, 0.3, 0.2, 0.0), 1.5, 0.5, true, 0.0, 0.9)

## is world point p in the mage's box?
func _hits_mage(m, p: Vector2) -> bool:
	var ua: float = (m.pos - centre).angle()
	var o: Vector2 = p - m.pos
	return absf(o.dot(game.basis_r(ua))) < float(m.w) * 0.5 + 1.0 and absf(o.dot(game.basis_d(ua))) < float(m.h) * 0.5 + 1.0

## a bolt chips a rock: a few cells round p knocked off as sparks
func _chip(a, p: Vector2, r: float) -> void:
	var b: Vector2 = a.to_body(p) + a.com
	for j in range(maxi(0, int(b.y - r - 1.0)), mini(a.h, int(b.y + r + 2.0))):
		for i in range(maxi(0, int(b.x - r - 1.0)), mini(a.w, int(b.x + r + 2.0))):
			var ck: int = j * a.w + i
			if a.cells[ck] != 0 and Vector2(i + 0.5, j + 0.5).distance_to(b) <= r and not a.guarded(ck):
				a.take(ck)
	game.vfx.spawn(Vfx.GLOW, p, a.vel, 8, Color(1.0, 0.6, 0.35, 0.7), Color(1.0, 0.3, 0.2, 0.0), 5.0, 1.5)
	_mining = 0

## a cannon bolt strikes a pirate
func _hurt_pirate(pr, dmg: float, p: Vector2) -> void:
	if pr.beaten:
		return
	pr.hp -= dmg
	pr.hit_t = 6
	for k in 8:
		game.vfx.spawn(Vfx.DOT, p, pr.vel + Vector2.from_angle(randf() * TAU) * randf_range(0.5, 2.0), 18 + randi() % 14,
			Color(1.0, 0.85, 0.5), Color(1.0, 0.4, 0.2, 0.0), 1.5, 0.5, true, 0.0, 0.93)
	if pr.hp <= 0.0:
		_beat_pirate(pr)
	elif randf() < 0.5:
		pr.side_t = mini(pr.side_t, 20)           # (hit, it jinks)

## Beaten: it strikes its colours. Its crew flees in a lifeboat, torn plating flies off, and what's left
## is a wreck like any other (kept with its sector), its strongbox yours to open.
func _beat_pirate(pr) -> void:
	pr.beaten = true
	pr.kind = "wreck"
	pr.fate = "Her pirate crew took to a lifeboat when you beat her."
	pr.visited = false
	pr.touched = true
	pr.thrusting = false
	pr.omega = randf_range(-0.0015, 0.0015)
	pr.vel *= 0.25
	var g := galaxy_of(pr.pos)
	var key := Galaxy.key_of(Galaxy.sector_of(g[0], g[1]))
	pr.sect = key if _loaded.has(key) else "pirate"
	for k in randi_range(2, 4):
		var sc = Wreck.scrap(randi() & 0xFFFFFF, randf_range(3.5, 7.0))
		var dk := Vector2.from_angle(randf() * TAU)
		sc.pos = pr.pos + dk * (pr.reach() * 0.7 + 12.0)
		sc.vel = pr.vel + dk * randf_range(0.3, 0.8)
		sc.sect = pr.sect
		sc.touched = true
		rocks.append(sc)
	game.vfx.blast(pr.pos, 16.0, 2)
	for k2 in 3:
		game.vfx.blast(pr.cell_world(randi() % pr.w, randi() % pr.h), 7.0, 2)
	game.vfx.spawn(Vfx.GLOW, pr.pos, Vector2.from_angle(randf() * TAU) * 3.0 + pr.vel, 160, Color(1.0, 0.6, 0.4, 0.9), Color(1.0, 0.3, 0.2, 0.0), 3.0, 2.0)
	game.shake = maxf(game.shake, 10.0)
	game.audio.play("boom", pr.pos, 1.0)
	stats["pirates_beaten"] += 1
	game.items["pirates_beaten"] = int(game.items.get("pirates_beaten", 0)) + 1
	game.ui.toast("%s strikes her colours! Her crew flees in a lifeboat: her strongbox is yours (drift aboard, F)" % String(pr.wname).capitalize(), Color(1.0, 0.85, 0.4), 5.0)

## Fallen out here: back to the planet's own frame (home at the origin), no pirates, nobody aboard
## (main `_respawn` puts you at home, and the skiff answers you there).
func reset_after_death() -> void:
	if not active:
		return
	if not at_home():
		_shift(-home_at())
		org = Defs.planet_g(home)
	_drop_pirates()
	shots.clear()
	acid.clear()
	sbolts.clear()
	in_station = null
	frame_st = null
	bolts.clear()
	belt = 0.0
	beam_to = null
	_flash = 0.0
	sail = 0.0
	sailing = false
	var sk = game.skiff
	if sk != null:
		for k in sk.riders.size():
			if sk.riders[k] != null:
				sk.riders[k].aboard = null
				sk.riders[k] = null
		for pm in game.players:
			if pm.aboard == sk:
				pm.aboard = null
				pm.deck = false
		sk.vel = Vector2.ZERO
		sk.centre = Vector2.ZERO
		sk.pos = sk.pos.normalized() * (Defs.R_SPACE - 30.0)
	active = false
	live = true
	easing = true
	cooldown = 90
	visible = false
	game.view_rect.visible = true
	game.view_c = Vector2.ZERO

## Out here you choose how far you see: the wheel or - zooms out, + back in (`ZOOMS`, eased to)
func zoom_by(d: int) -> void:
	var zi := clampi(zoom_i + d, 0, ZOOMS.size() - 1)
	if zi == zoom_i:
		return
	zoom_i = zi
	game.ui.toast("View: %sx" % str(ZOOMS[zoom_i]).trim_suffix(".0"), Color(0.75, 0.9, 1.0), 1.0)

# --------------------------------------------------------------- outposts ---

## the nearest outpost out here (by its middle) within `within`, or null
func nearest_outpost(p: Vector2, within: float) -> Variant:
	var best = null
	var bd := within
	for a in rocks:
		if a.kind != "outpost":
			continue
		var d: float = (a.pos - p).length()
		if d < bd:
			bd = d
			best = a
	return best

## on foot by an outpost's counter: its keeper is near_keeper (near_trader the outpost; F trades); beside a
## spacer, near_folk (F talks)
func _trader_near(m) -> void:
	var op = nearest_outpost(m.pos, 1200.0)
	if op == null:
		return
	var best := TRADE_REACH
	for kp in op.keepers:
		var chest: Vector2 = op.to_world(kp.b - op.com) - op.axis_y() * 12.0
		var d: float = chest.distance_to(m.pos)
		if d < best:
			best = d
			near_trader = op
			near_keeper = kp
	if near_trader != null:
		return
	var fb := 16.0
	for f in folk:
		if f.op != op:
			continue
		var fd: float = f.world().distance_to(m.pos)
		if fd < fb:
			fb = fd
			near_folk = f

## the skiff flown into an outpost's hangar: docked (a word the first time each visit)
func _dock_check(sk) -> void:
	if sk == null:
		docked = null
		return
	var op = nearest_outpost(sk.pos, 1200.0)
	var now = op if op != null and op.in_hangar(sk.pos) else null
	if now != null and now != docked:
		game.ui.toast("Docked at %s. Step out (F): its shops are along the deck through the hangar's door" % now.wname, Color(1.0, 0.85, 0.5), 4.5)
		game.audio.play("blink", sk.pos, 0.6)
	docked = now

## F at the counter: the trader's shop (towns.gd's shop and ui.gd's panel, Defs.SHOPS["outpost"]); first,
## a bounty for every pirate you've beaten since you last traded at an outpost
func open_trade(op, kp = null) -> void:
	_settle_jobs(op)
	var it: Dictionary = game.items
	var owed := int(it.get("pirates_beaten", 0)) - int(it.get("bounty_paid", 0))
	if owed > 0:
		it["coins"] = int(it.get("coins", 0)) + owed * BOUNTY
		it["bounty_paid"] = int(it.get("pirates_beaten", 0))
		stats["bounty"] += owed * BOUNTY
		game.ui.toast("A bounty: %d coins for the %d pirate ship%s you beat" % [owed * BOUNTY, owed, "" if owed == 1 else "s"], Color(1.0, 0.85, 0.4), 4.0)
		game.audio.play("coin", null, 0.9)
	var tr = kp if kp != null else op.trader()
	tr.pos = op.to_world(tr.b - op.com)
	game.towns.shop_of = tr
	game.state = "shop"
	game.ui.show_shop(tr)
	stats["trades"] += 1

## a line of text on the top layer, centred at a screen point, with a shadow
func _top_text(at: Vector2, txt: String, col: Color) -> void:
	var f2: Font = PixelFont.make()
	var px: float = float(game.scale_px)
	var sz: int = PixelFont.SIZE * int(game.ui.U)
	var wd := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	_top.draw_set_transform(at, 0.0, Vector2.ONE / px)
	_top.draw_string(f2, Vector2(-wd * 0.5 + 1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.7))
	_top.draw_string(f2, Vector2(-wd * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------- an outpost's folk, its jobs ---
# (user, 23 Nov: "much bigger more complex outposts": a living station with shops along its lowest deck,
# spacers about its halls, and a job board in its cantina)

const JOB_MAX := 3

## an outpost streamed in: its spacers
func _outpost_in(op) -> void:
	for pl in op.folk_plan:
		folk.append(Spacer.make(op, pl))

## the spacers of the outposts near you, walking their decks
func _update_folk(focus: Vector2) -> void:
	if game.frame % 60 == 7:
		for k in range(folk.size() - 1, -1, -1):
			if not rocks.has(folk[k].op):
				folk.remove_at(k)
	for f in folk:
		if f.op.pos.distance_to(focus) < float(maxi(f.op.w, f.op.h)) + 600.0:
			f.tick()
	# (two standing on one spot: one of them steps aside)
	if game.frame % 20 == 3:
		for i in folk.size():
			var fa = folk[i]
			if fa.wait <= 0:
				continue
			for k in range(i + 1, folk.size()):
				var fb = folk[k]
				if fb.op == fa.op and fb.wait > 0 and absf(fb.b.x - fa.b.x) < 8.0 and absf(fb.b.y - fa.b.y) < 4.0:
					fb.step_aside(1 if fb.b.x >= fa.b.x else -1)
					break

## F beside a spacer: they stop and say something (what they say moves on each time)
func _folk_talk(f) -> void:
	var lines := _folk_lines(f)
	f.say = String(lines[(f.talked + f.fseed) % lines.size()])
	f.say_t = 240
	f.talked += 1
	var to: Vector2 = game.player.pos - f.world()
	f.facing = 1 if to.dot(f.op.axis_x()) > 0.0 else -1
	game.audio.play("blink", f.world(), 0.25, 1.6)
	stats["folk_talks"] = int(stats.get("folk_talks", 0)) + 1

## what a spacer might say: the derelict near this system, a trade tip from the next one over, pirates, the job
## board, fuel, and a word about the outpost itself
func _folk_lines(f) -> Array:
	var op = f.op
	var out := ["%s, they call me. Welcome to %s." % [f.name, op.wname],
		"The board in the cantina has work, if you've a hold to fill.",
		"Long hauls burn Wisp Cells. The shipwright sells them by the ten.",
		"Pirates hunt the dark between the stars. They never come near our guns."]
	if op.sys >= 0:
		var sg: PackedFloat64Array = Galaxy.system_station(op.sys)
		var dk: float = Defs.g_rel(sg, galaxy_of(op.pos)).length() / 1000.0
		out.append("There's a dead station out there, the %s, %.0fk off. Something lives in its dark halls." % [Galaxy.station_name(op.sys), dk])
		var nx: int = op.sys + 1
		var tr: Dictionary = Defs.trade_of(Galaxy.outpost_seed(nx))
		var wants: Array = (tr["wants"] as Dictionary).keys()
		if not wants.is_empty():
			var gd: String = wants[0]
			out.append("%s pays well for %s, they say. It's in the %s system." % [Galaxy.outpost_name(nx), String(Defs.GOODS[gd]["name"]).to_lower(), Galaxy.star_name(nx)])
	out.append(["The reactor hums all night. You stop hearing it.", "I came out here for a season. That was eleven years ago.",
		"Mind the hatches: down and jump drops you through.", "The cartographer will sell you the stars, a few at a time."][f.fseed % 4])
	return out

## the job board's offers at an outpost (its seed, name and system): three, from its seed and how many jobs
## you've done (so they change once you finish one). courier: sealed crates carried to another system's
## outpost; salvage: matter brought back here; hunt: pirate ships beaten, then back here.
func job_offers(oseed: int, oname: String, osys: int) -> Array:
	var n := int(game.items.get("jobs_done", 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([oseed, n, 77])
	var out := []
	for k in 3:
		var kind: String = ["courier", "courier", "salvage", "hunt"][rng.randi_range(0, 3)]
		if kind == "courier" and osys < 0:
			kind = "salvage"
		var jb := {"id": "%d:%d:%d" % [oseed, n, k], "kind": kind, "from": oseed, "from_name": oname}
		match kind:
			"courier":
				var to_sys: int = [osys + 1, osys + 2, osys + 3, osys - 1][rng.randi_range(0, 3)]
				if to_sys < 0 or to_sys == osys:
					to_sys = osys + 1
				var crates := rng.randi_range(1, 3)
				var dist: float = Defs.g_rel(Galaxy.system_outpost(to_sys), Galaxy.system_outpost(osys)).length()
				jb["to"] = Galaxy.outpost_seed(to_sys)
				jb["to_name"] = Galaxy.outpost_name(to_sys)
				jb["n"] = crates
				jb["pay"] = 60 + 45 * crates + int(dist / 6000.0)
				jb["name"] = "Carry %d sealed crate%s to %s, in the %s system" % [crates, "" if crates == 1 else "s", jb["to_name"], Galaxy.star_name(to_sys)]
			"salvage":
				var opts := [[Defs.HULL, 20, 2.2], [Defs.XENITE, 8, 6.0], [Defs.STARIRON, 4, 18.0], [Defs.ICE, 30, 1.2], [Defs.CRYSTAL, 6, 7.0]]
				var o: Array = opts[rng.randi_range(0, opts.size() - 1)]
				var cnt := int(round(float(int(o[1])) * rng.randf_range(1.0, 1.5)))
				jb["mat"] = int(o[0])
				jb["n"] = cnt
				jb["pay"] = int(round(float(cnt) * float(o[2]) * 1.6)) + 20
				jb["name"] = "Bring %d %s back here" % [cnt, Defs.NAMES[int(o[0])]]
			"hunt":
				var np := rng.randi_range(1, 3)
				jb["n"] = np
				jb["pay"] = 70 * np
				jb["name"] = "Beat %d pirate ship%s, then come back" % [np, "" if np == 1 else "s"]
		out.append(jb)
	return out

func jobs() -> Array:
	return game.items.get("jobs", [])

func has_job(id: String) -> bool:
	for jb in jobs():
		if String(jb["id"]) == id:
			return true
	return false

## take a job from the board: a courier run loads its sealed crates into your hold (room for them, or no)
func take_job(jb: Dictionary) -> bool:
	if has_job(String(jb["id"])):
		return false
	var js: Array = jobs()
	if js.size() >= JOB_MAX:
		game.ui.toast("You've %d jobs already: finish one first" % JOB_MAX, Color(1, 0.7, 0.5), 2.5)
		return false
	var j2: Dictionary = jb.duplicate()
	match String(jb["kind"]):
		"courier":
			if game.hold_cap() - game.cargo_count() < int(jb["n"]):
				game.ui.toast("No room in your hold for %d crates" % int(jb["n"]) if game.hold_cap() > 0 else "Crates ride in your ship's hold: you need a skiff", Color(1, 0.7, 0.5), 2.5)
				return false
			var cargo: Dictionary = game.items.get("cargo", {})
			cargo["sealed"] = int(cargo.get("sealed", 0)) + int(jb["n"])
			game.items["cargo"] = cargo
		"hunt":
			j2["base"] = int(game.items.get("pirates_beaten", 0))
	js.append(j2)
	game.items["jobs"] = js
	game.ui.toast("Job taken: %s (%d coins)" % [String(jb["name"]), int(jb["pay"])], Color(1.0, 0.88, 0.5), 3.5)
	game.audio.play("blink", null, 0.5)
	stats["jobs_taken"] = int(stats.get("jobs_taken", 0)) + 1
	return true

## at an outpost: every job that ends here and is done is paid
func _settle_jobs(op) -> void:
	var js: Array = jobs()
	var keep := []
	for jb in js:
		var done := false
		match String(jb["kind"]):
			"courier":
				var cargo: Dictionary = game.items.get("cargo", {})
				if int(jb["to"]) == op.seed_ and int(cargo.get("sealed", 0)) >= int(jb["n"]):
					cargo["sealed"] = int(cargo["sealed"]) - int(jb["n"])
					if int(cargo["sealed"]) <= 0:
						cargo.erase("sealed")
					game.items["cargo"] = cargo
					done = true
			"salvage":
				if int(jb["from"]) == op.seed_ and game.player.inv[int(jb["mat"])] >= int(jb["n"]):
					game.player.inv[int(jb["mat"])] -= int(jb["n"])
					done = true
			"hunt":
				if int(jb["from"]) == op.seed_ and int(game.items.get("pirates_beaten", 0)) - int(jb.get("base", 0)) >= int(jb["n"]):
					done = true
		if done:
			game.items["coins"] = int(game.items.get("coins", 0)) + int(jb["pay"])
			game.items["jobs_done"] = int(game.items.get("jobs_done", 0)) + 1
			stats["jobs_done"] = int(stats.get("jobs_done", 0)) + 1
			game.ui.toast("Job done: %s. Paid %d coins" % [String(jb["name"]), int(jb["pay"])], Color(1.0, 0.85, 0.4), 4.0)
			game.audio.play("coin", null, 1.0)
		else:
			keep.append(jb)
	game.items["jobs"] = keep

## a job in a few words (the HUD)
func job_short(jb: Dictionary) -> String:
	match String(jb["kind"]):
		"courier":
			return "Courier: %d crate%s to %s" % [int(jb["n"]), "" if int(jb["n"]) == 1 else "s", String(jb["to_name"])]
		"salvage":
			return "Salvage: %d/%d %s to %s" % [mini(game.player.inv[int(jb["mat"])], int(jb["n"])), int(jb["n"]), Defs.NAMES[int(jb["mat"])], String(jb["from_name"])]
		"hunt":
			return "Hunt: %d/%d pirates, then %s" % [mini(int(game.items.get("pirates_beaten", 0)) - int(jb.get("base", 0)), int(jb["n"])), int(jb["n"]), String(jb["from_name"])]
	return ""

# ------------------------------------------------------- derelict stations ---
# (user, 23 Nov: "much bigger more complex outposts ... Derelict space stations and everything with aliens
# and such to fight"; inside, "Both, by section": a powered room keeps its gravity, a dead one has none)

## a station streamed in: what changed in it before, and the aliens still living in it
func _station_in(st) -> void:
	var sd: Dictionary = station_state.get(str(st.seed_), {})
	st.apply_state(sd)
	var dead := {}
	for d in sd.get("dead", []):
		dead[int(d)] = true
	for sp in st.spawns:
		if dead.has(int(sp["id"])):
			continue
		aliens.append(Alien.make(String(sp["kind"]), st, sp["b"], int(sp["id"]), int(sp["mod"])))

## a station streamed out: its aliens go with it (they're grown again with it); an outpost's spacers too
func _station_out(st) -> void:
	for kf in range(folk.size() - 1, -1, -1):
		if folk[kf].op == st:
			folk.remove_at(kf)
	for k in range(aliens.size() - 1, -1, -1):
		if aliens[k].st == st:
			aliens.remove_at(k)
	for k2 in range(sbolts.size() - 1, -1, -1):
		if sbolts[k2]["st"] == st:
			sbolts.remove_at(k2)
	if in_station == st:
		in_station = null
	if frame_st == st:
		frame_st = null

func _st_state(st) -> Dictionary:
	var key := str(st.seed_)
	if not station_state.has(key):
		station_state[key] = {"open": [], "seal": false, "dead": []}
	return station_state[key]

## Near a station (within its bounds) its floor is "down": `centre` goes far under it, so the view, your
## upright pose and the skiff all level with it. Inside its rooms on foot (`in_station`), you move by its
## rules (`_station_move`) and your spells are cast (`_space_cast`).
func _station_frame(focus: Vector2) -> void:
	frame_st = null
	in_station = null
	var m = game.player
	for a in _rocks_near(focus, 40.0):
		if a.kind != "station" and a.kind != "outpost":
			continue
		var b: Vector2 = a.to_body(focus) + a.com
		if b.x < -30.0 or b.y < -30.0 or b.x > float(a.w) + 30.0 or b.y > float(a.h) + 30.0:
			continue
		frame_st = a
		if m.aboard == null and not m.dead and a.inside(b):
			in_station = a
			var op: bool = a.kind == "outpost"
			if not a.visited:
				a.visited = true
				if op:
					var shops := []
					for kp in a.keepers:
						shops.append(String(Outpost.OP_ROOMS[kp.shop]).to_lower())
					game.ui.toast("Welcome aboard %s. Along this deck: the %s" % [a.wname, ", the ".join(shops)], Color(1.0, 0.88, 0.55), 5.0)
					game.audio.play("blink", m.pos, 0.5)
				else:
					game.ui.toast("Aboard %s, a derelict. %s" % [a.wname, a.fate], Color(0.8, 0.7, 1.0), 5.0)
					game.audio.play("creak", m.pos, 0.8)
			var rk: int = a.module_at(b)
			if rk >= 0 and rk != st_room:
				st_room = rk
				if op:
					var who := ""
					for kp2 in a.keepers:
						if kp2.room == rk:
							who = " · %s keeps it" % kp2.name
					game.ui.toast(a.role_name(rk) + who, Color(1.0, 0.9, 0.65), 2.0)
				else:
					var pw: bool = a.mods[rk]["powered"]
					game.ui.toast("%s · %s" % [a.role_name(rk), "its gravity holds" if pw else "no gravity: the movement keys push you"],
						Color(0.85, 0.8, 1.0) if pw else Color(0.6, 0.75, 0.9), 2.0)
		break
	if in_station == null:
		st_room = -1
	if frame_st != null:
		centre = frame_st.pos + frame_st.axis_y() * STATION_DOWN

## On foot in a station, in its own cells: a powered room pulls you to its floor (walk, jump, drop down
## through a hatch's floor with down + jump, step up onto a ledge like on a planet); a dead room has no
## gravity, and the movement keys push you by the staff's jet (the cast button casts).
func _station_move(m, st) -> void:
	var ax: Vector2 = st.axis_x()
	var ay: Vector2 = st.axis_y()
	var b: Vector2 = _st_b if m.pos == _st_w else st.to_body(m.pos) + st.com
	var bv := Vector2(vel.dot(ax), vel.dot(ay))
	var hw := float(m.w) * 0.5
	var hh := float(m.h) * 0.5
	var pw: bool = st.powered_at(b)
	var face: float = (m.input.aim - m.pos).dot(ax)
	if absf(face) > 1.0:
		m.facing = 1 if face > 0.0 else -1
	var jump: bool = m.input.jump
	if _drop_t > 0:
		_drop_t -= 1
	jetting = false
	if pw:
		var speed: float = 1.5 * game.gear("speed", m) * (1.2 if m.items.has("coil") else 1.0)
		bv.x += (float(m.input.move) * speed - bv.x) * (0.35 if m.on_ground else 0.12)
		if m.on_ground:
			m.ground_t = 0
		else:
			m.ground_t += 1
		if jump and not _st_jump:
			if m.input.down and _on_platform(st, b, hw, hh):
				_drop_t = 12
				bv.y = maxf(bv.y, 1.0)
			elif m.ground_t <= 6:
				bv.y = (-4.6 if m.items.has("boots") else -3.9) * sqrt(game.gear("jump", m))
				game.audio.play("jump", m.pos, 0.6)
				m.ground_t = 99
		bv.y = minf(bv.y + Alien.G, 6.0)
		m.floating = false
	else:
		var want := Vector2(float(m.input.move), (1.0 if m.input.down else 0.0) - (1.0 if jump else 0.0))
		if want != Vector2.ZERO and m.mana > ST_JET_MANA:
			var dirb := want.normalized()
			bv += dirb * ST_JET
			m.mana -= ST_JET_MANA
			jetting = true
			var dw: Vector2 = ax * dirb.x + ay * dirb.y
			if game.frame % 2 == 0:
				game._particle(m.pos - dw * 4.0 + Vector2(randf() - 0.5, randf() - 0.5) * 3.0, -dw * (0.4 + randf() * 0.6) + vel,
					12 + randi() % 8, Color8(140, 220, 255), true, 0.0)
		bv *= ST_DRAG
		bv = bv.limit_length(4.5)
		m.floating = true
	var was_ground: bool = m.on_ground
	var r: Array = st.move_box(b, bv, hw, hh, pw, 5 if (pw and m.on_ground) else 0, _drop_t > 0)
	b = r[0]
	bv = r[1]
	m.on_ground = bool(r[2]) and pw
	if m.on_ground and not was_ground and m.air_time > 18:
		game.audio.play("land", m.pos, clampf(float(m.air_time) / 60.0, 0.3, 1.0))
	m.air_time = 0 if m.on_ground else m.air_time + 1
	if m.on_ground:
		var a0: float = m.anim
		m.anim += absf(bv.x) * 0.13
		if int(m.anim * 0.5) != int(a0 * 0.5):
			game.audio.play("step", m.pos, 0.3)
	_st_jump = jump
	m.pos = st.to_world(b - st.com)
	_st_b = b
	_st_w = m.pos
	vel = ax * bv.x + ay * bv.y
	m.vx = bv.x
	m.vy = bv.y
	m.in_liquid = false

func _on_platform(st, b: Vector2, hw: float, hh: float) -> bool:
	var fy := int(round(b.y + hh))
	for i in range(int(floor(b.x - hw)), int(ceil(b.x + hw))):
		if st.scaffold_cell(i, fy):
			return true
	return false

## Your spell, cast in a station: the same spell and look as on a planet, its bolt flying through the
## station's rooms (a powered room's pull bends a fireball's arc), hurting the aliens it meets. Mending heals
## as ever; Blink steps through the rooms; Conjure has no ground to draw from.
func _space_cast(m, st) -> void:
	if m.known.is_empty():
		return
	m.sel = clampi(m.sel, 0, m.known.size() - 1)
	var id: String = m.known[m.sel]
	var s: Dictionary = Defs.SPELLS[id]
	var cost: float = float(s["mana"]) * game.gear("mana_cost", m)
	if m.cast_cd > 0 or m.mana < cost:
		return
	match id:
		"mend":
			game._cast(m, id, m.input.aim)
			return
		"conjure":
			m.cast_latch = true
			m.cast_cd = 30
			game.ui.toast("Conjure needs ground to draw from: there's none out here", Color(0.7, 0.8, 1.0), 1.6)
			game.vfx.fizzle(m.input.aim)
			return
		"blink":
			if _st_blink(m, st):
				game.audio.play("blink", m.pos)
				m.mana -= cost
				m.cast_cd = int(s["cd"])
				m.cast_frame = game.frame
			return
	if not Defs.PROJ.has(id):
		return
	m.cast_frame = game.frame
	m.cast_latch = bool(s.get("single", false))
	m.mana -= cost
	m.cast_cd = int(s["cd"])
	var snd := {"mote": "spark", "spark": "spark", "fireball": "fire", "tide": "water", "frost": "frost", "quake": "boom", "starfall": "rare"}
	game.audio.play(snd.get(id, "spark"), m.pos, 0.8)
	var hand: Vector2 = m.pos + st.axis_x() * (float(m.facing) * 6.0) - st.axis_y() * 0.5
	var dir: Vector2 = (m.input.aim - hand).normalized()
	if dir == Vector2.ZERO:
		dir = st.axis_x() * float(m.facing)
	var pd: Dictionary = Defs.PROJ[id]
	var at: Vector2 = hand + dir * 10.0
	sbolts.append({"type": id, "pos": at, "vel": dir * float(pd["speed"]), "life": int(pd["life"]), "st": st, "owner": "player"})
	game.vfx.cast(id, at, dir, m)
	stats["spells"] = int(stats.get("spells", 0)) + 1

## Blink through the rooms: to the cursor (up to 48 cells), or the last clear spot inside on the way
func _st_blink(m, st) -> bool:
	var b0: Vector2 = st.to_body(m.pos) + st.com
	var d: Vector2 = st.to_body(m.input.aim) + st.com - b0
	if d.length() > 48.0:
		d = d.normalized() * 48.0
	var n := int(d.length())
	for k in range(n, 3, -1):
		var tb := b0 + d * (float(k) / float(n))
		if st.inside(tb) and st.box_free(tb, float(m.w) * 0.5, float(m.h) * 0.5):
			var to: Vector2 = st.to_world(tb - st.com)
			game.vfx.blink(m.pos, to)
			m.pos = to
			vel = Vector2.ZERO
			return true
	return false

## your spells in flight out here
func _update_sbolts() -> void:
	for k in range(sbolts.size() - 1, -1, -1):
		var pr: Dictionary = sbolts[k]
		var pd: Dictionary = Defs.PROJ[pr["type"]]
		var st = pr["st"]
		var p: Vector2 = pr["pos"]
		var v: Vector2 = pr["vel"]
		if st != null and st.powered_at(st.to_body(p) + st.com):
			v += st.axis_y() * float(pd["g"])
		pr["life"] = int(pr["life"]) - 1
		var steps := maxi(1, int(ceil(v.length() * 2.0)))
		var hit := false
		var hit_a = null
		for q in steps:
			p += v / float(steps)
			if _bolt_blocked(p):
				hit = true
				break
			hit_a = _alien_at(p)
			if hit_a != null:
				hit = true
				break
		pr["pos"] = p
		pr["vel"] = v
		if hit or int(pr["life"]) <= 0:
			_sbolt_impact(pr, hit, hit_a)
			sbolts.remove_at(k)
			continue
		game.vfx.trail(pr)

## is p in a solid cell of anything out here (a scaffold is no wall to a bolt)?
func _bolt_blocked(p: Vector2) -> bool:
	for a in _rocks_near(p, 2.0):
		var bb: Vector2 = a.to_body(p) + a.com
		var t: int = a.at(int(floor(bb.x)), int(floor(bb.y)))
		if t != 0 and t != Defs.SCAFFOLD:
			return true
	return false

func _alien_at(p: Vector2) -> Variant:
	for al in aliens:
		if al.dead:
			continue
		var bb: Vector2 = al.st.to_body(p) + al.st.com
		if al.touches(bb, 1.0, 1.0):
			return al
	return null

func _sbolt_impact(pr: Dictionary, hit: bool, al) -> void:
	var p: Vector2 = pr["pos"]
	var type: String = pr["type"]
	var pd: Dictionary = Defs.PROJ[type]
	match type:
		"mote":
			if al != null:
				_hurt_alien(al, float(pd["dmg"]), p, 0.6)
		"spark":
			if al != null:
				_hurt_alien(al, float(pd["dmg"]) * game.gear("spell_spark"), p, 1.0)
				if game.items.has("rimefang"):
					al.slow = maxi(al.slow, 150)
		"frost":
			var rk: float = game.gear("spell_frost")
			for o in aliens:
				if not o.dead and o.world().distance_to(p) < 13.0 * rk + o.hw:
					o.slow = int(200.0 * rk)
			if al != null:
				_hurt_alien(al, float(pd["dmg"]) * rk, p, 0.8)
		"tide":
			if al != null:
				_hurt_alien(al, float(pd["dmg"]), p, 2.4)
		"fireball":
			var fk: float = game.gear("spell_fireball")
			_alien_blast(p, 10.0 * fk, 38.0 * fk)
			game.vfx.blast(p, 10.0 * fk, 1)
		"quake":
			_alien_blast(p, 22.0, 70.0)
			game.vfx.blast(p, 22.0, 2)
		"starfall":
			_alien_blast(p, 17.0, 80.0)
			game.vfx.blast(p, 17.0, 1)
	game.vfx.impact(type, p, hit)

## a blast out here: every alien within r of p takes it (less toward the edge)
func _alien_blast(p: Vector2, r: float, dmg: float) -> void:
	game.audio.play("boom", p, clampf(r / 14.0, 0.4, 1.2), 1.3 - clampf(r / 40.0, 0.0, 0.5))
	game.shake = maxf(game.shake, r * 0.25)
	for al in aliens:
		if al.dead:
			continue
		var d: float = maxf(0.0, al.world().distance_to(p) - maxf(al.hw, al.hh))
		if d < r:
			_hurt_alien(al, dmg * (1.0 - 0.5 * d / r), p, 1.6)

## an alien hurt: it flashes, is knocked back (not the Broodmother), wakes its room, and dies at 0
func _hurt_alien(al, dmg: float, p: Vector2, kb: float) -> void:
	if al.dead:
		return
	al.hp -= dmg
	al.hit_t = 8
	al.awake = true
	stats["alien_hits"] = int(stats.get("alien_hits", 0)) + 1
	if al.kind != "brood":
		var away: Vector2 = al.world() - p
		if away.length() > 0.01:
			away = away.normalized()
			var kbb := Vector2(away.dot(al.st.axis_x()), away.dot(al.st.axis_y()))
			al.v += kbb * kb * (0.35 if al.kind == "brute" else 1.0)
	game.audio.play("hit", p, 0.6)
	alien_wake(al)
	if al.hp <= 0.0:
		_kill_alien(al)

func _kill_alien(al) -> void:
	al.dead = true
	var wp: Vector2 = al.world()
	var xr: Array = al.spec()["xen"]
	var n := randi_range(int(xr[0]), int(xr[1]))
	var m = game.player
	m.inv[Defs.XENITE] += n
	stats["aliens_killed"] = int(stats.get("aliens_killed", 0)) + 1
	game.audio.play("foe_die", wp, 0.9)
	for k in 18 + int(al.hw) * 2:
		game.vfx.spawn(Vfx.DOT, wp + Vector2(randf() - 0.5, randf() - 0.5) * al.hw, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.6),
			24 + randi() % 30, Alien.C_GLOW2, Color(Alien.C_MID.r, Alien.C_MID.g, Alien.C_MID.b, 0.0), 1.5, 0.5, true, 0.0, 0.94)
	game.vfx.spawn(Vfx.GLOW, wp, Vector2.ZERO, 20, Color(0.7, 1.0, 0.45, 0.8), Color(0.4, 0.2, 0.7, 0.0), 6.0, 6.0 + al.hw)
	for k2 in mini(n, 8):
		game.parts.append({"pos": wp + Vector2(randf() - 0.5, randf() - 0.5) * 6.0, "vel": Vector2(randf() - 0.5, randf() - 0.5) * 1.5,
			"life": 70, "col": Defs.COLOR[Defs.XENITE], "self": true, "grav": 0.0, "home": true})
	if al.id >= 0:
		(_st_state(al.st)["dead"] as Array).append(al.id)
	if al.kind == "brood":
		al.st.open_seal()
		_st_state(al.st)["seal"] = true
		game.shake = maxf(game.shake, 8.0)
		game.audio.play("rare", null, 1.0)
		game.ui.toast("The Broodmother falls! The seal on the vault breaks (%d Xenite)" % n, Color(0.8, 1.0, 0.55), 5.0)
		for c in al.st.seal_cells:
			if randf() < 0.3:
				game.vfx.spawn(Vfx.DOT, al.st.cell_world(int(c) % al.st.w, int(c) / al.st.w), Vector2.from_angle(randf() * TAU) * 0.8, 40,
					Color(0.6, 0.7, 1.0), Color(0.3, 0.4, 1.0, 0.0), 1.5, 0.5, true, 0.0, 0.95)

## the aliens near you: ticked in their station's cells; touching you hurts
var _mb = null                  # (the mage's middle in the station's cells, for the aliens this tick)
func _update_aliens(focus: Vector2) -> void:
	for k in range(aliens.size() - 1, -1, -1):
		if aliens[k].dead:
			aliens.remove_at(k)
	var m = game.player
	_mb = null
	if m.aboard == null and in_station != null and not m.dead:
		_mb = in_station.to_body(m.pos) + in_station.com
	for al in aliens.duplicate():
		if al.dead:
			continue
		if (al.st.pos - focus).length() > al.st.reach() + ALIEN_NEAR:
			continue
		var mine_mb = _mb if al.st == in_station else null
		al.tick(mine_mb, self)
		if mine_mb != null and al.bite_cd <= 0 and al.touches(mine_mb, float(m.w) * 0.5, float(m.h) * 0.5):
			var dmg: float = float(al.spec()["dmg"])
			if al.kind == "brute" and al.act != "charge":
				dmg *= 0.5
			var kx: float = signf((mine_mb as Vector2).x - al.b.x)
			var kn := Vector2(kx * (3.2 if al.act == "charge" else 2.0), -1.4)
			var before: int = m.iframes
			game.hurt(m, dmg, Vector2.ZERO, true)
			if before == 0 and m.iframes > 0:
				vel += al.st.axis_x() * kn.x + al.st.axis_y() * kn.y
				game.audio.play("chitter", m.pos, 0.6)
			al.bite_cd = 50
			if al.act == "leap":
				al.v *= -0.3

## an alien wakes, and its room with it
func alien_wake(al) -> void:
	var woke := false
	for o in aliens:
		if o.st == al.st and o.home == al.home and not o.awake:
			o.awake = true
			woke = true
	if woke or al.kind == "brood":
		game.audio.play("hiss", al.world(), 0.7)

## can it see you (no wall between, in its station's cells)?
func alien_sees(al) -> bool:
	if _mb == null:
		return false
	var d: Vector2 = (_mb as Vector2) - al.b
	var n := int(d.length() / 2.0) + 1
	for k in range(1, n):
		var q: Vector2 = al.b + d * (float(k) / float(n))
		if al.st.solid_cell(int(floor(q.x)), int(floor(q.y))):
			return false
	return true

## it spits acid at you: `n` globs, `spread` apart
func alien_spit(al, spread: float, n: int, speed: float) -> void:
	if _mb == null:
		return
	var st = al.st
	var from_b: Vector2 = al.b + Vector2(float(al.facing) * al.hw * 0.8, -al.hh * 0.2)
	var dir_b: Vector2 = ((_mb as Vector2) - from_b).normalized()
	var from_w: Vector2 = st.to_world(from_b - st.com)
	for k in n:
		var d: Vector2 = dir_b.rotated((float(k) - float(n - 1) * 0.5) * spread)
		var wv: Vector2 = (st.axis_x() * d.x + st.axis_y() * d.y) * speed
		acid.append([from_w, wv, 160, 10.0 if al.kind == "brood" else 7.0])
	game.audio.play("spit", from_w, 0.7)
	for k2 in 6:
		game.vfx.spawn(Vfx.DOT, from_w, Vector2.from_angle(randf() * TAU) * randf_range(0.2, 0.8), 14 + randi() % 8,
			Alien.C_GLOW, Color(0.3, 0.6, 0.1, 0.0), 1.0, 0.5, true, 0.0, 0.92)

## the Broodmother lays a skitter (at most 4 of hers at once)
func alien_lay(al) -> void:
	var mine := 0
	for o in aliens:
		if not o.dead and o.mother == al:
			mine += 1
	if mine >= 4:
		return
	var y = Alien.make("skitter", al.st, al.b + Vector2(-float(al.facing) * al.hw * 0.5, al.hh * 0.3), -1, al.home)
	y.mother = al
	y.awake = true
	y.cd = 40
	aliens.append(y)
	stats["laid"] = int(stats.get("laid", 0)) + 1
	var wp: Vector2 = y.world()
	game.audio.play("chitter", wp, 0.8)
	for k in 10:
		game.vfx.spawn(Vfx.DOT, wp, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.0), 20 + randi() % 10,
			Alien.C_GLOW2, Color(0.3, 0.6, 0.1, 0.0), 1.5, 0.5, true, 0.0, 0.93)

## the aliens' acid in flight: it splashes on walls, and burns you
func _update_acid() -> void:
	var m = game.player
	for k in range(acid.size() - 1, -1, -1):
		var ac: Array = acid[k]
		var p: Vector2 = ac[0]
		var v: Vector2 = ac[1]
		ac[2] = int(ac[2]) - 1
		var hit := false
		for q in 2:
			p += v * 0.5
			if _bolt_blocked(p):
				hit = true
				break
			if m.aboard == null and not m.dead and _hits_mage(m, p):
				var before: int = m.iframes
				game.hurt(m, float(ac[3]), Vector2.ZERO, true)
				if before == 0 and m.iframes > 0:
					vel += v.normalized() * 1.4
				stats["acid_hits"] = int(stats.get("acid_hits", 0)) + 1
				hit = true
				break
		ac[0] = p
		if hit or int(ac[2]) <= 0:
			for k2 in 7:
				game.vfx.spawn(Vfx.DOT, p, Vector2.from_angle(randf() * TAU) * randf_range(0.2, 0.9), 16 + randi() % 10,
					Alien.C_GLOW, Color(0.25, 0.5, 0.1, 0.0), 1.0, 0.5, true, 0.0, 0.9)
			if hit:
				game.audio.play("hit", p, 0.3, 1.6)
			acid.remove_at(k)
		elif game.frame % 3 == 0:
			game.vfx.spawn(Vfx.DOT, p, -v * 0.15, 12, Alien.C_GLOW.darkened(0.2), Color(0.3, 0.5, 0.1, 0.0), 1.0, 0.5, true, 0.0, 0.9)

## figures among the rooms, under the mage: the aliens' bodies, the outposts' traders
func _draw_mid() -> void:
	if not active:
		return
	var xf := _world_xf()
	_draw_aliens(xf)
	var zs: float = minf(float(game.zoom), 4.0)
	for oa in rocks:
		if oa.kind != "outpost":
			continue
		var osp: Vector2 = xf * oa.pos
		if osp.distance_to(Vector2(game.VW, game.VH) * 0.5) > Vector2(game.VW, game.VH).length() * 0.5 + oa.reach() / game.zoom:
			continue
		var kang: float = xf.basis_xform(oa.axis_x()).angle()
		# the keepers, each behind a counter drawn in front of them
		for kpr in oa.keepers:
			var kt: ImageTexture = oa.keeper_texture(kpr)
			var kps: Vector2 = xf * oa.to_world(kpr.b - oa.com)
			_mid.draw_set_transform(kps.floor(), kang, Vector2(float(kpr.facing), 1.0) / zs)
			_mid.draw_texture(kt, Vector2(-float(kt.get_width()) * 0.5, -float(kt.get_height()) + 1.0))
			var ct: ImageTexture = oa.counter_texture(kpr)
			_mid.draw_texture(ct, Vector2(-6.0, -float(ct.get_height())))
			_mid.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the spacers
	var scr := Vector2(game.VW, game.VH)
	for f in folk:
		var fs: Vector2 = xf * f.world()
		if fs.x < -40.0 or fs.y < -40.0 or fs.x > scr.x + 40.0 or fs.y > scr.y + 40.0:
			continue
		var ft: ImageTexture = f.texture()
		var fang: float = xf.basis_xform(f.op.axis_x()).angle()
		_mid.draw_set_transform(fs.floor(), fang, Vector2(float(f.facing), 1.0) / zs)
		_mid.draw_texture(ft, Vector2(-float(ft.get_width()) * 0.5, 9.5 + 1.0 - float(ft.get_height())))
		_mid.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## the aliens' bodies (on `_mid`, under the mage)
func _draw_aliens(xf: Transform2D) -> void:
	var zs: float = minf(float(game.zoom), 4.0)
	var scr := Vector2(game.VW, game.VH)
	for al in aliens:
		if al.dead:
			continue
		var sp: Vector2 = xf * al.world()
		if sp.x < -60.0 or sp.y < -60.0 or sp.x > scr.x + 60.0 or sp.y > scr.y + 60.0:
			continue
		var t: ImageTexture = al.frame()
		var tw := float(t.get_width())
		var th := float(t.get_height())
		var ang: float = xf.basis_xform(al.st.axis_x()).angle()
		_mid.draw_set_transform(sp.floor(), ang, Vector2(float(al.facing), 1.0) / zs)
		var mod := Color.WHITE
		if al.hit_t > 0:
			mod = Color(2.0, 2.0, 2.0)
		elif al.act == "windup" or al.act == "spit":
			mod = Color(1.5, 1.25, 0.85)
		elif al.slow > 0:
			mod = Color(0.75, 0.9, 1.3)
		var top: float = -th * 0.5 if al.flies() else al.hh + 1.0 - th
		_mid.draw_texture(t, Vector2(-tw * 0.5, top), mod)
		_mid.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## the aliens' health bars and their acid, over everything (`_top`)
func _draw_alien_marks(xf: Transform2D) -> void:
	var zs: float = minf(float(game.zoom), 4.0)
	var scr := Vector2(game.VW, game.VH)
	for al in aliens:
		if al.dead:
			continue
		var sp: Vector2 = xf * al.world()
		if sp.x < -60.0 or sp.y < -60.0 or sp.x > scr.x + 60.0 or sp.y > scr.y + 60.0:
			continue
		if al.hp < al.hp_max or (al.kind == "brood" and al.awake):
			var up_s: Vector2 = xf.basis_xform(-al.st.axis_y()).normalized()
			var bw: float = 50.0 if al.kind == "brood" else 16.0
			var bar_at: Vector2 = (sp + up_s * ((al.hh + 6.0) / zs)).floor()
			_top.draw_rect(Rect2(bar_at - Vector2(bw * 0.5 + 1.0, 1.0), Vector2(bw + 2.0, 4.0)), Color(0.05, 0.02, 0.06, 0.8))
			_top.draw_rect(Rect2(bar_at - Vector2(bw * 0.5, 0.0), Vector2(bw * clampf(al.hp / al.hp_max, 0.0, 1.0), 2.0)), Color(0.65, 1.0, 0.4))
			if al.kind == "brood":
				_top_text(bar_at + up_s * 8.0, "The Broodmother", Color(0.8, 1.0, 0.6))
	for ac in acid:
		var ap: Vector2 = xf * (ac[0] as Vector2)
		var at2: Vector2 = xf * ((ac[0] as Vector2) - (ac[1] as Vector2) * 1.6)
		_top.draw_line(at2, ap, Color(0.5, 0.9, 0.3, 0.45), 2.0)
		_top.draw_rect(Rect2(ap.floor() - Vector2(1, 1), Vector2(3, 3)), Color(0.25, 0.5, 0.12))
		_top.draw_rect(Rect2(ap.floor() - Vector2(0, 0), Vector2(1, 1)), Color(0.9, 1.0, 0.7))

## The Wisp Scanner (items["scanner"]): the nearest wreck and derelict station in the sectors round you,
## known before their sectors come in
func _scanner_marks() -> void:
	scan_marks.clear()
	if not active or not game.items.has("scanner"):
		return
	var g := player_g()
	var sc := Galaxy.sector_of(g[0], g[1])
	var best := {}
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var s := sc + Vector2i(dx, dy)
			var sg := Galaxy.sector_g(s)
			for c in Galaxy.sector_content(s):
				var ty: String = c["type"]
				if ty != "wreck" and ty != "station":
					continue
				var at: Vector2 = c["at"]
				var gp := PackedFloat64Array([sg[0] + at.x, sg[1] + at.y])
				var d := Vector2(gp[0] - g[0], gp[1] - g[1]).length()
				if d < 2500.0:
					continue
				if not best.has(ty) or d < float(best[ty][0]):
					best[ty] = [d, gp, String(c["name"])]
	for ty2 in best:
		scan_marks.append([best[ty2][1], best[ty2][2], Color(0.75, 0.9, 0.85) if ty2 == "wreck" else Color(0.75, 0.55, 1.0)])
