## Space: everything above the orbit band (Defs.R_SPACE).
##
## Out here nobody touches the planet's cells, so they are neither simulated nor drawn: as you climb
## the camera keeps zooming out, and once a cell is smaller than a pixel (SWAP_ZOOM) the planet is
## shown as a picture of itself taken the moment you left (main.capture_planet: one render of the
## whole planet), so the swap can't be seen. The other planets hang where Defs.planet_pos puts them,
## as discs grown from their biomes until you've been there (then as their pictures). A sun, stars.
##
## Space shares the world coordinates of `home`, the planet the GPU holds, which sits at the origin.
## Fly toward another planet and, once it is clearly the nearer one, it is made in the background
## while you fly (main.arrive_planet: the planet you left is saved first); until it's ready you can't
## come closer than HOLD above its orbit band. Then everything is moved over so that it is at the
## origin (`_reanchor`), and it becomes home: drop into its orbit band to land.
##
## The mage flies by the staff jet (hold cast: a push toward where you aim, paid in mana) inside a
## wisp bubble (no breath needed out here), or the skiff carries the party. The nearest planet pulls,
## fading with distance; the view turns (`view_ang`, eased) to keep it below you.
extends Node2D

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
var _mask: Shader

func _ready() -> void:
	_mask = Shader.new()
	_mask.code = PLANET_MASK
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
		game.ui.toast("Space. Hold cast to fly the skiff toward the cursor; head back down to land.", Color(0.75, 0.9, 1.0), 4.0)
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
	if sk != null and (sk.pilot() != null or sk.pos.length() > Defs.R_SPACE - 9.5):
		# the skiff: flown by its pilot (hold cast), or drifting if nobody's aboard (one left down on
		# the planet waits there)
		var pl = sk.pilot()
		var aim: Vector2 = pl.input.aim if pl != null else sk.pos
		sk.centre = centre
		sk.fly(aim, pl != null and pl.input.cast, pull(sk.pos), 0.9995)
		sk.pos = _hold(sk.pos, sk)
		sk.advance(Callable())
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
	var held := _hold(m.pos + vel, null)
	vel = held - m.pos
	m.pos = held
	m.vx = vel.dot(game.basis_r(a))
	m.vy = vel.dot(game.basis_d(a))
	m.on_ground = false
	m.floating = true
	m.mana = minf(m.max_mana, m.mana + m.mana_regen)
	m.breath = minf(m.max_breath, m.breath + 4.0)       # (inside the wisp bubble)
	if m.iframes > 0:
		m.iframes -= 1
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
## above its orbit band: `p` pushed back out, and a skiff's speed toward it taken away.
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
				game.ui.toast("Approaching %s… %d%%" % [b["name"], int(game.travel_progress * 100.0)], Color(0.75, 0.9, 1.0), 2.0)
			p = c + n * lim
	return p

## Clearly nearer to another planet than to home: make it in the background, then move over to it.
func _maybe_travel(p: Vector2) -> void:
	if game.travelling or target >= 0 or int(near["index"]) == home:
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
	_reanchor(Defs.planet_pos(home) - Defs.planet_pos(index))
	home = index
	target = -1
	_make_bodies()
	_find_near(game.skiff.pos if riding else game.player.pos)
	# the planet's own clock, set so that its sun stands where the sun is now
	game.time += fposmod(sun_ang - game.sun_angle(), TAU) / TAU * game.day_len()
	pictures[home] = game.capture_planet()
	game.ui.toast("%s: %s" % [game.planet["name"], game.planet["desc"]], Color(0.8, 0.95, 0.9), 5.0)
	game.save_game()
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

## the nearest planet's pull out here (per tick, toward its centre): as at the top of its orbit
## band, fading with the square of the distance
func pull(p: Vector2) -> float:
	var top: float = float(near.get("space", Defs.R_SPACE))
	return 0.17 * 0.06 * pow(top / maxf((p - centre).length(), top), 2.0)

## the camera follows the mage, zooming out with the height over the nearest planet so its near
## side stays well on screen (a quarter of the view's height below you), and turning to keep it below
func _follow(m) -> void:
	var h: float = (m.pos - centre).length() - float(near.get("top", Defs.R_TOP))
	var zt := clampf(h / (0.25 * float(game.VH)), SWAP_ZOOM * 0.98, 160.0)
	game.zoom = lerpf(game.zoom, zt, 0.035)
	game.cam_c = game.cam_c.lerp(m.pos, 0.2)
	live = game.zoom < SWAP_ZOOM and not game.travelling and int(near.get("index", home)) == home
	var cc: Vector2 = game.cam_c
	var va := (cc - centre).angle()
	if live:
		view_ang = va
	else:
		view_ang = lerp_angle(view_ang, va, 0.03)
		game.view_c = game.cam_c         # (nothing from the GPU to line the sprites up with)
	visible = not live
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
	if not active or live:
		return
	var w: int = game.VW
	var h: int = game.VH
	draw_rect(Rect2(0, 0, w, h), Color(0.006, 0.006, 0.02))
	var xf := _world_xf()
	# stars: a fixed field turned with the view, drifting a little as you travel
	var rot := xf.x.angle()
	var drift: Vector2 = (game.cam_c + Defs.planet_pos(maxi(home, 0))) * 0.004   # (whole-system coordinates: no jump when home moves)
	var ctr := Vector2(w, h) * 0.5
	var reach := Vector2(w, h).length() * 0.5 + 4.0
	var tw := float(game.frame) * 0.03
	for s in stars:
		var p0: Vector2 = s[0] - drift
		var q := Vector2(fposmod(p0.x, 1024.0) - 512.0, fposmod(p0.y, 1024.0) - 512.0)
		if q.length() > reach:
			continue
		var sp := ctr + q.rotated(rot)
		var b: float = 0.35 + 0.65 * float(s[1]) * (0.75 + 0.25 * sin(tw + float(s[2])))
		draw_rect(Rect2(sp.floor(), Vector2.ONE), Color(b, b, b * 1.08))
	# the sun, far off where the light comes from (so far that it keeps its place as you travel)
	var sun_s: Vector2 = xf * (game.cam_c + Vector2(cos(sun_ang), sin(sun_ang)) * SUN_DIST)
	var sun_r := maxf(3.0, SUN_R / game.zoom)
	for k in 4:
		draw_circle(sun_s, sun_r * (2.2 - k * 0.38), Color(1.0, 0.85, 0.5, 0.06 + k * 0.05))
	draw_circle(sun_s, sun_r, Color(1.0, 0.97, 0.85))
	# the planets: as they looked when you left them, or as discs grown from their biomes
	var shown := {}
	for bd in bodies:
		var c: Vector2 = bd["pos"]
		var idx := int(bd["index"])
		var pic: Dictionary = pictures.get(idx, {})
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
	# where the planets are when they're off screen: a marker at the edge, pointing the way
	for b2 in bodies:
		var hc := Color(0.6, 1.0, 0.7) if int(b2["index"]) == home else Color(0.85, 0.85, 1.0)
		_marker(xf, b2["pos"], b2["top"], String(b2["name"]), hc)
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
		bodies.append({"index": i, "pos": Defs.planet_pos(i) - Defs.planet_pos(home), "top": top,
			"space": top + Defs.ORBIT_ROWS, "name": pl["name"],
			"tex": ImageTexture.create_from_image(_disc_image(pl, sun_dir))})

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
			var bi := int(fposmod(ang / TAU * cols.size() + nv * 0.6, float(cols.size())))
			var c: Color = cols[bi]
			c = c.lightened(nv * 0.25) if nv > 0.0 else c.darkened(-nv * 0.3)
			if sea and nv < -0.05:
				c = Color(0.16, 0.36, 0.68).darkened(clampf(-nv, 0.0, 0.5))
			c = c * lam
			c = c.lerp(haze * lam, 0.18)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img
