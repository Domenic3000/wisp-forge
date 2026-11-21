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
const NEARER := 0.8             # another planet is clearly nearer: at this fraction of home's distance
const PLANET_MASK := "shader_type canvas_item;
uniform float edge = 0.45;
void fragment() {
	float d = length(UV - vec2(0.5));
	COLOR = texture(TEXTURE, UV);
	COLOR.a *= 1.0 - smoothstep(edge - 0.012, edge, d);
}"

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
	pictures[home] = game.capture_planet()
	sun_ang = game.sun_angle()
	_make_bodies()
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
		game.ui.toast("Space. Fly with WASD (or hold cast toward the cursor); head back down to land.", Color(0.75, 0.9, 1.0), 4.0)
	else:
		game.ui.toast("Space. Hold cast to fly by the staff's jet; fall back to land.", Color(0.75, 0.9, 1.0), 4.0)

## Back into the orbit band: the planet's own physics take over again, and the view eases back in.
func exit() -> void:
	var m = game.player
	var sk = game.skiff
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
	_find_near(focus)
	_ensure_rocks()
	_update_rocks()
	if sk != null and (sk.pilot() != null or sk.pos.length() > Defs.R_SPACE - 9.5):
		# the skiff: flown by its pilot (keys, or hold cast toward the cursor), or drifting if nobody's
		# aboard (one left down on the planet waits there)
		var pl = sk.pilot()
		sk.centre = centre
		var want: Vector2 = sk.steer(pl.input) if pl != null else Vector2.ZERO
		sk.fly(want, pl != null, pull(sk.pos), true, 0.0, 0.9995)
		sk.pos = _hold(sk.pos, sk)
		# (it bumps against asteroids: the skiff's own collision, against their cells)
		sk.advance(Callable(self, "_rock_solid") if not _rocks_near(sk.pos, 120.0).is_empty() else Callable())
		for rider in sk.riders:
			if rider != null:
				game._ride(rider)
		if sk.thrusting:
			game._skiff_exhaust()
	if m.aboard != null:
		vel = sk.vel
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
	var best := 1e30
	for b in bodies:
		var d: float = (p - b["pos"]).length() - float(b["top"])
		if d < best:
			best = d
			near = b
	centre = near["pos"]

## dropping back into home's orbit band (once it is the planet the GPU holds)
func _landing(p: Vector2, v: Vector2) -> bool:
	if game.travelling:
		return false
	return p.length() < Defs.R_SPACE - 10.0 and v.dot(p.normalized()) < 0.0

## A planet that isn't ready (one that isn't home, or any while one is being made) keeps you HOLD
## above its orbit band: `p` pushed back out, and a skiff's speed toward it taken away. One beyond the
## skiff's reach (main.skiff_reach: a Core Drive for each planet further) never gets ready.
func _hold(p: Vector2, sk) -> Vector2:
	for b in bodies:
		if int(b["index"]) == home and not game.travelling:
			continue
		var c: Vector2 = b["pos"]
		var lim: float = float(b["space"]) + HOLD
		var o := p - c
		if o.length() < lim:
			var n := o.normalized()
			if sk != null and sk.vel.dot(n) < 0.0:
				sk.vel -= n * sk.vel.dot(n)
			if game.frame % 120 == 0:
				if not reachable(int(b["index"])):
					game.ui.toast("%s is beyond your skiff's reach: fit a Core Drive at the Wisp Forge (a Planet Core bound in star iron from the asteroids)" % b["name"], Color(1.0, 0.8, 0.55), 3.0)
				else:
					game.ui.toast("Approaching %s… %d%%" % [b["name"], int(game.travel_progress * 100.0)], Color(0.75, 0.9, 1.0), 2.0)
			p = c + n * lim
	return p

## can the skiff go to planet i? (home and any planet up to its reach; on foot, only home)
func reachable(i: int) -> bool:
	return i == home or i <= game.skiff_reach()

## Clearly nearer to another planet than to home: make it in the background, then move over to it.
func _maybe_travel(p: Vector2) -> void:
	if game.travelling or target >= 0 or int(near["index"]) == home or not reachable(int(near["index"])):
		return
	if (p - centre).length() < NEARER * p.length():
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
	_reanchor(Defs.planet_pos(home) - Defs.planet_pos(index))
	home = index
	target = -1
	_make_bodies()
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
	centre += d
	rocks.clear()                 # (the old home's: saved with it; the new home's are made next)
	_rock_plan.clear()
	_rocks_for = -1

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
	live = game.cam_c.length() - Defs.R_SPACE < reach and not game.travelling
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
	return game.player.pos.normalized() * (Defs.R_SPACE - 20.0)

## Every tick on the planet: just back from space, the view eases in to the zoom you chose.
func planet_tick() -> void:
	if cooldown > 0:
		cooldown -= 1
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
	if not active:
		return
	var w: int = game.VW
	var h: int = game.VH
	draw_rect(Rect2(0, 0, w, h), Color(0.006, 0.006, 0.02))
	var xf := _world_xf()
	# stars: a fixed field turned with the view, drifting as you travel (two depths: the nearer half
	# drifts faster, so you can feel your speed with the camera always on you)
	var rot := xf.x.angle()
	var sys_c: Vector2 = game.cam_c + Defs.planet_pos(maxi(home, 0))   # (whole-system coordinates: no jump when home moves)
	var ctr := Vector2(w, h) * 0.5
	var reach := Vector2(w, h).length() * 0.5 + 4.0
	var tw := float(game.frame) * 0.03
	for si in stars.size():
		var s: Array = stars[si]
		var p0: Vector2 = s[0] - sys_c * (0.004 if si % 2 == 0 else 0.03)
		var q := Vector2(fposmod(p0.x, 1024.0) - 512.0, fposmod(p0.y, 1024.0) - 512.0)
		if q.length() > reach:
			continue
		var sp := ctr + q.rotated(rot)
		var b: float = 0.35 + 0.65 * float(s[1]) * (0.75 + 0.25 * sin(tw + float(s[2])))
		draw_rect(Rect2(sp.floor(), Vector2.ONE), Color(b, b, b * 1.08))
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
	_draw_rocks(xf)
	# where the planets are when they're off screen: a marker at the edge, pointing the way
	for b2 in bodies:
		var hc := Color(0.6, 1.0, 0.7) if int(b2["index"]) == home else Color(0.85, 0.85, 1.0)
		var bi := int(b2["index"])
		if not reachable(bi):
			hc = Color(0.62, 0.6, 0.66)
		_marker(xf, b2["pos"], b2["top"], String(b2["name"]) + ("" if reachable(bi) else " (needs a Core Drive)"), hc)
	var nr = nearest_rock(game.player.pos, 20000.0)
	if nr != null:
		_marker(xf, nr.pos, nr.reach(), "Asteroid", Color(0.95, 0.82, 0.62))
	# you, in your wisp bubble (drawn by the overlay; the bubble here, under the sprite)
	if game.player.aboard == null:
		var ms: Vector2 = xf * game.player.pos
		draw_arc(ms, 11.0, 0.0, TAU, 28, Color(0.55, 0.85, 1.0, 0.35 if jetting else 0.22), 1.0)

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
	var f := ThemeDB.fallback_font
	var px: float = float(game.scale_px)
	draw_set_transform(at, 0.0, Vector2.ONE / px)
	var sz := 15
	var wd := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(f, Vector2(-wd * 0.5 + 1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.6))
	draw_string(f, Vector2(-wd * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.85, 0.9, 1.0, 0.85))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------- other planets ---

## This system's planets (the round of Defs.SYSTEM that home belongs to), placed relative to home,
## each with a disc grown from its biomes (their ground's colours in sectors round the globe, seas
## where it has them), its sky as a haze, lit from the sun.
func _make_bodies() -> void:
	if _bodies_for == home:
		return
	_bodies_for = home
	bodies.clear()
	var n: int = Defs.SYSTEM.size()
	var base := (home / n) * n
	var sun_dir := Vector2(cos(sun_ang), sin(sun_ang))
	for i in range(base, base + n):
		var pl: Dictionary = Defs.make_planet(i)
		var top: float = float(pl["radius"]) + Defs.ATMO
		# (a disc is ~17 ms of script: the five of them made again on every journey were most of the
		# frame you arrive in, so one is kept until the sun has moved well round)
		var dk := "%d_%d" % [Defs.world_seed, i]
		var dc: Array = _discs.get(dk, [])
		if dc.is_empty() or absf(angle_difference(float(dc[1]), sun_ang)) > 0.5:
			dc = [ImageTexture.create_from_image(_disc_image(pl, sun_dir)), sun_ang]
			_discs[dk] = dc
		bodies.append({"index": i, "pos": Defs.planet_pos(i) - Defs.planet_pos(home), "top": top,
			"space": top + Defs.ORBIT_ROWS, "name": pl["name"], "tex": dc[0]})

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
	while not _rock_plan.is_empty():
		var pl: Dictionary = _rock_plan.pop_front()
		if pl.has("save"):
			var a = Asteroid.from_save(pl["save"])
			if a != null:
				rocks.append(a)
		else:
			var a2 = Asteroid.make(int(pl["seed"]), float(pl["r"]), String(pl["kind"]))
			a2.pos = pl["pos"]
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
	for a in rocks:
		out.append(a.save())
	return out

## They drift and turn; what you dug at is rebuilt (a few frames at a time) and split if it came
## apart. Pieces that drift far off are gone.
func _update_rocks() -> void:
	_mining += 1
	for k in range(rocks.size() - 1, -1, -1):
		var a = rocks[k]
		a.pos += a.vel
		a.ang = wrapf(a.ang + a.omega, -PI, PI)
		a.vel *= ROCK_DRAG
		if a.dust > 0 and (game.frame % 6 == 0 or _mining > 2):
			a.settle_mass()
			# (splitting is a flood over its cells: only once you stop digging, or now and then)
			if _mining > 8 or game.frame % 45 == 0:
				_split(a)
		if a.mass < 1.0 or a.pos.length() > Defs.R_SPACE + 12000.0:
			rocks.remove_at(k)

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
	var p: Vector2 = game._reach(m, m.input.aim)
	var r: float = m.dig_r
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
