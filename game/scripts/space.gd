## Space: everything above the orbit band (Defs.R_SPACE).
##
## Out here nobody touches the planet's cells, so they are neither simulated nor drawn: as you climb
## the camera keeps zooming out, and once a cell is smaller than a pixel (SWAP_ZOOM) the planet is
## shown as a picture of itself taken the moment you left (main.capture_planet: one render of the
## whole planet), so the swap can't be seen. The other planets hang as discs at their own distances,
## grown procedurally from their biomes until you've been there. The sun, a starfield.
##
## The mage flies by the staff jet (hold cast: a push toward where you aim, paid in mana) inside a
## wisp bubble (no breath needed out here), and the planet's pull fades with distance. Falling back
## into the orbit band brings the live planet back while it is still far below.
##
## Space shares the planet's world coordinates (the planet you're on at the origin), so the zoom
## carries on smoothly from the close-up view. A prototype: the skiff will take over the flying.
extends Node2D

const SWAP_ZOOM := 3.0          # zoomed out this far, a cell is smaller than a pixel: the picture takes over
const JET := 0.075              # the staff jet's push, per tick
const JET_MANA := 0.32
const MAX_SPEED := 36.0
const DRAG := 0.999             # (a whisper of drag, so a prototype flight can be steered)
const SUN_DIST := 170000.0
const SUN_R := 9000.0
## where the other planets hang, relative to the one you're on (world units; a prototype layout)
const ORBITS := [Vector2(-52000, 18000), Vector2(41000, 47000), Vector2(66000, -24000), Vector2(-30000, -61000)]
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
var pictures := {}              # planet index -> {"tex", "zoom", "angle", "side"}: how each planet looked as you left
var discs := []                 # the other planets: {"pos", "radius", "tex", "name"}
var stars := []                 # [position in a 1024 x 1024 tile, brightness, twinkle phase]
var planet_sprite: Sprite2D
var _discs_for := -1

func _ready() -> void:
	planet_sprite = Sprite2D.new()
	planet_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = PLANET_MASK
	mat.shader = sh
	planet_sprite.material = mat
	add_child(planet_sprite)
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
	pictures[int(game.planet["index"])] = game.capture_planet()
	_make_discs()
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
	if sk != null and (sk.pilot() != null or sk.pos.length() > Defs.R_SPACE - 9.5):
		# the skiff: flown by its pilot (hold cast), or drifting if nobody's aboard (one left down on
		# the planet waits there)
		var pl = sk.pilot()
		var aim: Vector2 = pl.input.aim if pl != null else sk.pos
		sk.fly(aim, pl != null and pl.input.cast, pull(sk.pos), 0.9995)
		sk.advance(Callable())
		for rider in sk.riders:
			if rider != null:
				game._ride(rider)
		if sk.thrusting:
			game._skiff_exhaust()
	if m.aboard != null:
		vel = sk.vel
		_follow(m)
		if sk.pos.length() < Defs.R_SPACE - 10.0 and sk.vel.dot(sk.pos.normalized()) < 0.0:
			exit()
		return
	var r: float = m.pos.length()
	var up: Vector2 = m.pos / r
	# the planet's pull: as at the top of the orbit band, fading with the square of the distance
	vel -= up * pull(m.pos)
	jetting = false
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
			if dir.dot(game.basis_r(atan2(m.pos.y, m.pos.x))) != 0.0:
				m.facing = 1 if dir.dot(game.basis_r(atan2(m.pos.y, m.pos.x))) > 0.0 else -1
	vel *= DRAG
	if vel.length() > MAX_SPEED:
		vel = vel.normalized() * MAX_SPEED
	m.pos += vel
	var a := atan2(m.pos.y, m.pos.x)
	m.vx = vel.dot(game.basis_r(a))
	m.vy = vel.dot(game.basis_d(a))
	m.on_ground = false
	m.floating = true
	m.mana = minf(m.max_mana, m.mana + m.mana_regen)
	m.breath = minf(m.max_breath, m.breath + 4.0)       # (inside the wisp bubble)
	if m.iframes > 0:
		m.iframes -= 1
	_follow(m)
	# back down into the orbit band
	if m.pos.length() < Defs.R_SPACE - 10.0 and vel.dot(up) < 0.0:
		exit()

## the planet's pull out here (per tick, toward its centre): as at the top of the orbit band,
## fading with the square of the distance
func pull(p: Vector2) -> float:
	return 0.17 * 0.06 * pow(Defs.R_SPACE / maxf(p.length(), Defs.R_SPACE), 2.0)

## the camera follows the mage
func _follow(m) -> void:
	# the camera follows, zooming out as you go so the planet's near side stays well on screen (a
	# quarter of the view's height below you)
	var zt := clampf((m.pos.length() - Defs.R_TOP) / (0.25 * float(game.VH)), SWAP_ZOOM * 0.98, 160.0)
	game.zoom = lerpf(game.zoom, zt, 0.035)
	game.cam_c = game.cam_c.lerp(m.pos, 0.2)
	live = game.zoom < SWAP_ZOOM
	if not live:
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
	var drift: Vector2 = game.cam_c * 0.004
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
	# the sun, far off where the light comes from
	var sun_w := Vector2(cos(game.sun_angle()), sin(game.sun_angle())) * SUN_DIST
	var sun_s: Vector2 = xf * sun_w
	var sun_r := maxf(3.0, SUN_R / game.zoom)
	for k in 4:
		draw_circle(sun_s, sun_r * (2.2 - k * 0.38), Color(1.0, 0.85, 0.5, 0.06 + k * 0.05))
	draw_circle(sun_s, sun_r, Color(1.0, 0.97, 0.85))
	# the other planets
	for d in discs:
		var c: Vector2 = d["pos"]
		var rr: float = d["radius"]
		draw_set_transform_matrix(xf)
		draw_texture_rect(d["tex"], Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var ls: Vector2 = xf * (c + Vector2(0, 0)) + Vector2(0, rr / game.zoom + 6.0)
		_label(ls, String(d["name"]))
	# the planet you left, as its picture (a child sprite, masked to a disc)
	var pic: Dictionary = pictures.get(int(game.planet["index"]), {})
	planet_sprite.visible = not pic.is_empty()
	if not pic.is_empty():
		var zc: float = pic["zoom"]
		var ang: float = pic["angle"]
		# picture pixel (u, v) from its centre is the world point camR * u * zc + camD * v * zc
		var pr := Vector2(sin(ang), -cos(ang)) * zc
		var pd := Vector2(-cos(ang), -sin(ang)) * zc
		planet_sprite.texture = pic["tex"]
		planet_sprite.transform = xf * Transform2D(pr, pd, Vector2.ZERO)
		(planet_sprite.material as ShaderMaterial).set_shader_parameter("edge", pic["edge"])
		if game.zoom > 8.0:
			_label(xf * Vector2.ZERO + Vector2(0, (Defs.R_TOP + 60.0) / game.zoom + 6.0), String(game.planet["name"]))
	# where the planets are when they're off screen: a marker at the edge, pointing the way
	_marker(xf, Vector2.ZERO, Defs.R_TOP, String(game.planet["name"]), Color(0.6, 1.0, 0.7))
	for d2 in discs:
		_marker(xf, d2["pos"], d2["radius"], String(d2["name"]), Color(0.85, 0.85, 1.0))
	# you, in your wisp bubble (drawn by the overlay; the bubble here, under the sprite)
	if game.player.aboard == null:
		var ms: Vector2 = xf * game.player.pos
		draw_arc(ms, 11.0, 0.0, TAU, 28, Color(0.55, 0.85, 1.0, 0.35 if jetting else 0.22), 1.0)

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

## The neighbouring planets as discs: grown from each one's biomes (their ground's colours in
## sectors round the globe, seas where it has them), its sky as a haze, lit from the sun.
func _make_discs() -> void:
	var cur := int(game.planet["index"])
	if _discs_for == cur:
		return
	_discs_for = cur
	discs.clear()
	var sun_dir := Vector2(cos(game.sun_angle()), sin(game.sun_angle()))
	for k in ORBITS.size():
		var pl: Dictionary = Defs.make_planet(cur + 1 + k)
		var rad: float = float(pl["radius"]) + Defs.ATMO
		var pos: Vector2 = ORBITS[k]
		discs.append({"pos": pos, "radius": rad, "name": pl["name"],
			"tex": ImageTexture.create_from_image(_disc_image(pl, (sun_dir * SUN_DIST - pos).normalized()))})

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
