## Your ship's pocket dimension (user, 24 Nov: "have the inside of the ship be like a pocket dimension that
## you can enter. once inside you just see the ship, and you can enter the ship which is an instanced area that
## you can expand and build inside. a beautiful pocket dimension"; chose an isle in a nebula, and "Pocket =
## home": Wisp Recall takes you in from anywhere, leaving puts you back where you cast it, or by the ship).
##
## main `pocket` (a Node2D in `pix` before the overlay). While `active` main `_tick` hands each tick to `tick`
## (as it does to space.gd out there) and the GPU's world rests: the planet (or space) waits as you left it.
## The isle (pocket_isle.gd) lies at the world's origin, body +x to the right and +y down; the view looks at
## it upright (main `view_angle` -PI/2). You walk it as a ship's deck (pixel_body `move_box`), levitate if you
## can, and fall back onto it if you drop off its edge. B builds on it (main `_cabin_edit` with the isle).
## F at the ARCH leaves (`leave`: back where you came in from; G out by your ship); F at the ISLE HEART grows
## the isle (`expand_cost`, a second F within 4 s pays). Kept in the save slot's folder (`pocket.dat`).
##
## Drawn: a nebula (`NEBULA` shader on `bgrect`, behind: slow coloured clouds, two depths of stars, drifting
## with you), far isles, the isle's back and front pictures, halos over its glowing cells (`glow`, additive),
## wisp-lights drifting, a shimmer in the arch, and the prompts (`top`).
##
## The same instance holds a trading OUTPOST's halls (`place` "outpost"; user, 25 Nov: "derelict ships and outposts
## and so on should be redesigned so that you press a button to dock and go inside an instanced area so we can make
## them larger and more intricate with their own scenery"; chose outposts first). Flying by one, F docks (`dock`):
## its halls are grown in a worker (outpost.gd made with `halls`: a deck more, more rooms and folk), then you stand in
## its hangar beside your ship, space waiting outside. Its spacers walk (spacer.gd), its keepers stand at their
## counters (F trades: space.gd `open_trade`), F by a spacer talks, F at your ship undocks (`leave`: aboard, by the
## outpost). Behind it all, through its windows and the hangar's mouth, its own sky (`SKY` shader): the star it
## serves, a planet, a nebula's haze. Spells stay sheathed; nothing is built here.
extends Node2D

const PixelFont := preload("res://scripts/pixel_font.gd")
const Isle := preload("res://scripts/pocket_isle.gd")
const Build := preload("res://scripts/build.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Outpost := preload("res://scripts/outpost.gd")
const Spacer := preload("res://scripts/spacer.gd")
const PROMPT_REACH := 16.0

## an outpost's sky, behind its halls: a starfield, a nebula's haze, the system's star glowing off to one side and a
## banded planet hanging below (its colours by `hue`), drifting a little with you
const SKY := """
shader_type canvas_item;
uniform vec2 cam = vec2(0.0);
uniform float t = 0.0;
uniform vec2 size = vec2(480.0, 270.0);
uniform float hue = 0.0;
float hh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hh(i), hh(i + vec2(1.0, 0.0)), f.x), mix(hh(i + vec2(0.0, 1.0)), hh(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float s = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { s += a * nn(p); p = p * 2.07 + vec2(3.1, 1.7); a *= 0.5; } return s; }
vec3 hsv(float h, float s, float v) { vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0); return v * mix(vec3(1.0), k, s); }
void fragment() {
	vec2 px = floor(UV * size);
	vec2 p = px + cam * 0.02;
	vec3 col = mix(vec3(0.01, 0.012, 0.035), vec3(0.03, 0.02, 0.07), UV.y);
	float n = fbm(p / 120.0 + vec2(t * 0.0008, 0.0));
	col = mix(col, hsv(hue + 0.55, 0.5, 0.22), smoothstep(0.5, 0.9, n) * 0.6);
	if (hh(floor(p)) > 0.997) { col += vec3(0.8, 0.85, 1.0) * (0.5 + 0.5 * sin(t * 0.04 + hh(floor(p) + 3.0) * 50.0)); }
	if (hh(floor(p / 2.0) + 9.0) > 0.9985) { col += vec3(1.0, 0.9, 0.75) * 0.7; }
	// the star: a glow off to the upper right
	vec2 sc = vec2(size.x * 0.82, size.y * 0.18) - cam * 0.01;
	float sd = length(px - sc);
	col += hsv(hue + 0.08, 0.35, 1.0) * (0.9 * exp(-sd * 0.09) + 0.25 * exp(-sd * 0.015));
	// the planet below, lit from the star
	vec2 pc = vec2(size.x * 0.3, size.y * 1.45) - cam * 0.015;
	float pr = size.y * 0.85;
	vec2 q = (px - pc) / pr;
	float d = length(q);
	if (d < 1.0) {
		float band = fbm(vec2(q.x * 3.0 + t * 0.0004, q.y * 14.0));
		vec3 pcol = mix(hsv(hue, 0.45, 0.35), hsv(hue + 0.05, 0.55, 0.6), band);
		vec3 nrm = vec3(q, sqrt(max(0.0, 1.0 - d * d)));
		float lit = clamp(dot(nrm, normalize(vec3(0.7, -0.6, 0.5))), 0.0, 1.0);
		col = mix(col, pcol * (0.12 + 0.95 * lit), 1.0);
	} else if (d < 1.06) {
		col += hsv(hue + 0.5, 0.4, 0.6) * (1.0 - (d - 1.0) / 0.06) * 0.35;      // (its air, a thin rim)
	}
	COLOR = vec4(col, 1.0);
}
"""

const NEBULA := """
shader_type canvas_item;
uniform vec2 cam = vec2(0.0);
uniform float t = 0.0;
uniform vec2 size = vec2(480.0, 270.0);
float hh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float nn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hh(i), hh(i + vec2(1.0, 0.0)), f.x), mix(hh(i + vec2(0.0, 1.0)), hh(i + vec2(1.0, 1.0)), f.x), f.y);
}
// (each octave turned: plain value noise lines up with its lattice, and banded it showed as squares)
float fbm(vec2 p) { float s = 0.0; float a = 0.5; mat2 r = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)); for (int k = 0; k < 5; k++) { s += a * nn(p); p = r * p * 2.03 + vec2(1.7, 9.2); a *= 0.5; } return s; }
void fragment() {
	vec2 px = floor(UV * size);                       // (whole game pixels)
	vec2 p1 = mat2(vec2(0.87, 0.5), vec2(-0.5, 0.87)) * (px + cam * 0.06) / 150.0;
	vec2 p2 = mat2(vec2(0.6, -0.8), vec2(0.8, 0.6)) * (px + cam * 0.12) / 76.0;
	// (warped by noise of its own: plain value noise's edges run straight, and the retro filter's bands showed them)
	vec2 wp = vec2(fbm(p1 * 1.9 + vec2(3.1, t * 0.001)), fbm(p1 * 1.9 + vec2(-7.4, 1.3)));
	p1 += (wp - 0.5) * 1.4;
	float n1 = fbm(p1 + vec2(t * 0.004, -t * 0.002));
	float n2 = fbm(p2 + vec2(-t * 0.006, t * 0.003) + n1 * 1.6);
	vec3 deep = mix(vec3(0.04, 0.03, 0.10), vec3(0.08, 0.04, 0.16), UV.y);
	vec3 violet = vec3(0.42, 0.18, 0.62);
	vec3 teal = vec3(0.10, 0.48, 0.58);
	vec3 rose = vec3(0.70, 0.26, 0.46);
	vec3 col = deep;
	col = mix(col, violet, smoothstep(0.42, 0.85, n1) * 0.7);
	col = mix(col, teal, smoothstep(0.5, 0.9, n2) * 0.55);
	col = mix(col, rose, smoothstep(0.62, 0.95, n1 * n2 * 1.6) * 0.45);
	col += (hh(px + floor(t * 0.25)) - 0.5) * 0.012;   // (a breath of grain: the retro filter bands it)
	// stars at two depths, twinkling
	vec2 s1 = floor(px + cam * 0.03);
	float st = hh(s1);
	if (st > 0.9965) { col += vec3(0.75, 0.8, 1.0) * (0.55 + 0.45 * sin(t * 0.05 + st * 90.0)); }
	vec2 s2 = floor((px + cam * 0.09) / 2.0);
	float st2 = hh(s2 + 17.0);
	if (st2 > 0.9985) { col += vec3(1.0, 0.92, 0.8) * 0.8; }
	COLOR = vec4(col, 1.0);
}
"""

var game
var isle = null
var active := false
var back := {}                  # where you came in from: {pos, space, zoom, how}
var b := Vector2.ZERO           # your body's middle, in the isle's cells
var v := Vector2.ZERO
var near := ""                  # what F would do: "arch", "heart" or ""
var _offer_t := 0               # (the heart's offer stands this long: F again grows the isle)
var _calm_note := -1000
var motes: Array = []           # [cell position, phase, speed, colour]
var t := 0.0
var bgrect: ColorRect
var glow: Node2D
var top: Node2D
var _halo: ImageTexture
var stats := {"entered": 0, "left": 0, "expanded": 0, "fell": 0, "docked": 0, "undocked": 0, "trades": 0, "talks": 0}
var place := "isle"             # "isle": your ship's pocket; "outpost": a trading outpost's halls, docked
var op = null                   # (docked) the outpost's halls (outpost.gd, made with `halls`)
var op_folk := []               # its spacers (spacer.gd)
var near_keeper = null          # (docked) the keeper whose counter you're at, or a spacer beside you
var near_folk = null
var _dock_task := -1            # (docking: the halls being grown in a worker)
var _dock_made := []
var _dock_from = null           # the outpost out in space you're docking at
var _sky_mat: ShaderMaterial
var _neb_mat: ShaderMaterial
var _op_lights: Array = []      # [cell middle, radius, colour]

func _ready() -> void:
	visible = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bgrect = ColorRect.new()
	bgrect.show_behind_parent = true
	bgrect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = NEBULA
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bgrect.material = mat
	_neb_mat = mat
	var sh2 := Shader.new()
	sh2.code = SKY
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sh2
	add_child(bgrect)
	glow = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	glow.draw.connect(_draw_glow)
	add_child(glow)
	top = Node2D.new()
	top.z_index = 2
	top.draw.connect(_draw_top)
	add_child(top)

## a new journey (or another save slot): nothing in memory; the isle comes from its file when you go in
func reset() -> void:
	if active:
		game.view_rect.visible = true
		game.space.visible = true
		game.weather.visible = true
	active = false
	visible = false
	isle = null
	back = {}
	place = "isle"
	op = null
	op_folk.clear()
	_dock_task = -1
	_dock_from = null

func _path() -> String:
	return game._save_dir().path_join("pocket.dat")

func _ensure() -> void:
	if isle != null:
		return
	isle = Isle.new()
	var ok := false
	if FileAccess.file_exists(_path()):
		var f := FileAccess.open(_path(), FileAccess.READ)
		if f:
			var d = f.get_var()
			if d is Dictionary:
				ok = isle.load_isle(d)
	if not ok:
		isle.make()
	motes.clear()
	for k in 34:
		motes.append([Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 0.4)), randf() * TAU, randf_range(0.4, 1.0),
			[Color(0.6, 0.8, 1.0), Color(0.85, 0.6, 1.0), Color(0.6, 1.0, 0.85), Color(1.0, 0.85, 0.55)][k % 4]])

func save() -> void:
	if isle == null:
		return
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f:
		f.store_var(isle.save_isle())

# ------------------------------------------------------------ in and out ---

## where you stand when you come in: before the arch
func spawn_b(m) -> Vector2:
	# (clear of the arch's right pillar, which reaches ARCH_W / 2 + 4 from its middle)
	var ax: int = Isle.W / 2 + Isle.ARCH_DX + Isle.ARCH_W / 2 + 4 + 7
	var at := Vector2(float(ax) + 0.5, floorf(isle.top_at(ax, isle.level)) - float(m.h) * 0.5 - 0.05)
	for k in 30:
		if isle.box_free(at, float(m.w) * 0.5, float(m.h) * 0.5):
			break
		at.y -= 1.0
	return at

## Step in (G aboard the parked ship, "ship"; or by Wisp Recall from anywhere): the world outside waits.
func enter(m, how: String) -> void:
	if active:
		return
	_ensure()
	place = "isle"
	bgrect.material = _neb_mat
	back = {"pos": m.pos, "space": game.space.active, "zoom": game.zoom, "how": how}
	if m.aboard != null:
		m.aboard.leave(m)
		m.aboard = null
		m.deck = false
	if game.space.active:
		game.space.vel = Vector2.ZERO
	game.build_on = false
	game.build_prev = {}
	active = true
	visible = true
	b = spawn_b(m)
	v = Vector2.ZERO
	m.pos = isle.to_world(b)
	m.vx = 0.0
	m.vy = 0.0
	m.on_ground = false
	m.recall_t = 0
	game.zoom = 1.0
	game.view_c = Vector2.ZERO
	game.cam_c = m.pos.round()
	game.view_rect.visible = false
	game.space.visible = false
	game.weather.visible = false
	stats["entered"] += 1
	game.audio.play("blink", m.pos, 0.8)
	for k in 3:
		game.vfx.spawn(Vfx.RING, m.pos, Vector2.ZERO, 20 + k * 8, Color(0.75, 0.6, 1.0), Color(0.5, 0.8, 1.0, 0.0), 4.0, 26.0 + k * 10.0)
	var first: bool = not game.items.has("pocket_seen")
	game.items["pocket_seen"] = true
	if first:
		if not m.known.has("recall"):
			m.known.append("recall")
		game.ui.toast("Your ship's pocket: an isle in a nebula, yours to build on. The wisp teaches you Wisp Recall: cast it anywhere to come back here", Color(0.85, 0.75, 1.0), 7.0)
	else:
		game.ui.toast("Your ship's pocket. [F] at the arch to go back, at the Isle Heart to grow the isle. Build here as outside: Conjure what's in your hand, Unmake to take away", Color(0.85, 0.75, 1.0), 4.0)

## is your ship where you could come out by it? (on this planet while you're on it, or out in space while you are)
func ship_here() -> bool:
	var sk = game.skiff
	if sk == null or not game.items.has("skiff"):
		return false
	var in_space: bool = sk.pos.length() > Defs.R_SPACE - 9.5
	return in_space == bool(back.get("space", false))

## Step out: back where you came in from (aboard, if you came down from the ship), or (`by_ship`) aboard the ship.
func leave(m, by_ship := false) -> void:
	if not active:
		return
	if place == "outpost":
		_undock(m)
		return
	game._raise_finish_all()             # (anything still rising into the isle goes up whole first)
	save()
	active = false
	visible = false
	game.build_on = false
	game.build_prev = {}
	var p: Vector2 = back.get("pos", m.pos)
	# (user, 25 Nov: in from inside the ship, not by a door on its hull): you came down from the ship, or G at the
	# arch, so you go back up into it, aboard
	var aboard_after: bool = (by_ship or String(back.get("how", "")) == "ship") and ship_here()
	if aboard_after:
		p = game.skiff.pos
	m.pos = p
	m.vx = 0.0
	m.vy = 0.0
	game.zoom = float(back.get("zoom", 1.0))
	if game.space.active:
		game.space.visible = true
		game.space.vel = Vector2.ZERO
	else:
		game.view_rect.visible = true
		game.view_mat.set_shader_parameter("alpha", 0.0)
		game._map_shown = 2                  # (the picture on screen is from before: shown again once a new one is in)
		game._use_grid(m)
	game.weather.visible = true
	game.cam_c = m.pos
	game.view_c = Vector2.ZERO
	stats["left"] += 1
	if aboard_after and game.skiff.board(m):
		m.aboard = game.skiff
	game.audio.play("blink", m.pos, 0.7)
	game.vfx.blink(m.pos, m.pos)

# ----------------------------------------------------------------- ticks ---

func tick() -> void:
	var m = game.player
	t += 1.0
	game.heal_tick(m)
	if m.cast_cd > 0:
		m.cast_cd -= 1
	game.tick_spell_cds(m)
	if not m.input.cast:
		m.cast_latch = false
	elif not m.cast_latch and not game.build_on and not game.hand_live and not game.ui.mouse_over_ui():
		m.cast_latch = true
		if game.frame - _calm_note > 240:
			_calm_note = game.frame
			game.ui.toast("The pocket is calm: spells rest here" if place == "isle" else "Spells stay sheathed in an outpost's halls", Color(0.8, 0.75, 1.0), 1.6)
	m.mana = minf(m.max_mana, m.mana + game.mana_regen_of(m))
	m.breath = minf(m.max_breath, m.breath + 4.0)
	if m.iframes > 0:
		m.iframes -= 1
	_move(m)
	if place == "outpost":
		game.build_on = false
		_op_tick(m)
	elif game.build_on:
		game._cabin_edit(m, isle)
	elif game.unmaking(m):
		game.pocket_unmake(m, isle)      # (Unmake takes away here as outside)
	else:
		game.hand_body(m, isle)          # (what's in your hand, with Conjure held, builds here: plans too)
	if not game.raising.is_empty() and place == "isle":
		game._raise_tick()               # (a plan rising into the isle: the world's tick waits while you're here)
	if place == "isle":
		_near(m)
	if _offer_t > 0:
		_offer_t -= 1
	game.cam_c = m.pos.round()
	game.view_c = Vector2.ZERO
	queue_redraw()

func _move(m) -> void:
	var hw := float(m.w) * 0.5
	var hh := float(m.h) * 0.5
	var right_w: Vector2 = game.basis_r(game.view_angle())
	var face: float = (m.input.aim - m.pos).dot(right_w)
	if absf(face) > 1.0:
		m.facing = 1 if face > 0.0 else -1
	var speed: float = 1.5 * game.gear("speed", m) * (1.2 if m.items.has("coil") else 1.0)
	v.x += (float(m.input.move) * speed - v.x) * (0.35 if m.on_ground else 0.12)
	if m.on_ground:
		m.ground_t = 0
	else:
		m.ground_t += 1
	var jump: bool = m.input.jump and game.state == "play" and not game.build_on
	m.floating = false
	var bd = isle if place == "isle" else op
	if jump and not m.jump_held:
		var on_plat := false
		var fy := int(round(b.y + hh))
		for i in range(int(floor(b.x - hw)), int(ceil(b.x + hw))):
			if bd.scaffold_cell(i, fy):
				on_plat = true
		if m.input.down and on_plat:
			m.drop_t = 12
			v.y = maxf(v.y, 1.0)
		elif m.ground_t <= 6:
			v.y = (-4.6 if m.items.has("boots") else -3.9) * sqrt(game.gear("jump", m))
			game.audio.play("jump", m.pos, 0.6)
			m.ground_t = 99
	elif jump and not m.on_ground and m.ground_t > 14 and (m.items.has("levitate") or m.items.has("roc")) and m.mana > 0.5:
		v.y = maxf(v.y - 0.32, -1.4)              # (levitating: the pocket asks only a little mana)
		m.mana -= 0.12
		m.floating = true
	m.jump_held = jump
	v.y = minf(v.y + 0.17, 6.0)
	var was_ground: bool = m.on_ground
	var r: Array = bd.move_box(b, v, hw, hh, true, 5 if m.on_ground else 0, m.drop_t > 0)
	if m.drop_t > 0:
		m.drop_t -= 1
	b = r[0]
	v = r[1]
	m.on_ground = bool(r[2])
	if m.on_ground and not was_ground and m.air_time > 18:
		game.audio.play("land", m.pos, 0.5)
	m.air_time = 0 if m.on_ground else m.air_time + 1
	if m.on_ground:
		var a0: float = m.anim
		m.anim += absf(v.x) * 0.13
		if int(m.anim * 0.5) != int(a0 * 0.5):
			game.audio.step(m.pos, m.h, 0.3, "metal" if place == "outpost" else "soft")
	# (fallen off the isle into the nebula: it sets you gently back by the arch; out of an outpost's hangar mouth,
	# its tractor beam sets you back on the hangar's floor)
	if b.y > float(bd.h) + 40.0 or b.x < -80.0 or b.x > float(bd.w) + 80.0 or b.y < -80.0:
		b = spawn_b(m) if place == "isle" else _op_spawn(m)
		v = Vector2.ZERO
		stats["fell"] += 1
		game.ui.toast("The pocket sets you back on its isle" if place == "isle" else "The hangar's tractor beam sets you back on its floor", Color(0.8, 0.75, 1.0), 2.0)
		game.audio.play("blink", m.pos, 0.5)
	m.pos = bd.to_world(b)
	m.vx = v.x
	m.vy = v.y

## the arch or the heart within reach
func _near(m) -> void:
	near = ""
	var cx: int = Isle.W / 2
	var ah := Vector2(float(cx + Isle.ARCH_DX) + 0.5, isle.top_at(cx + Isle.ARCH_DX, 0) - 12.0)
	var hp := Vector2(float(cx + Isle.HEART_DX) + 0.5, isle.top_at(cx + Isle.HEART_DX, 0) - 10.0)
	if b.distance_to(ah) < 18.0:
		near = "arch"
	elif b.distance_to(hp) < 16.0:
		near = "heart"

## F in the pocket
func interact(m) -> bool:
	if place == "outpost":
		return _op_interact(m)
	match near:
		"arch":
			leave(m, false)
			return true
		"heart":
			_heart(m)
			return true
	return false

## G at the arch: out by your ship
func leave_by_ship(m) -> bool:
	if place != "isle" or near != "arch":
		return false
	if not ship_here():
		game.ui.toast("Your ship isn't where you came in from: the arch takes you back there", Color(1, 0.75, 0.55), 2.5)
		return true
	leave(m, true)
	return true

# ------------------------------------------------------------- growing ---

## what growing the isle to level lv costs (materials; and 40 mana)
static func expand_cost(lv: int) -> Dictionary:
	match lv:
		1: return {Defs.WISPBAR: 6, Defs.CRYSTAL: 10}
		2: return {Defs.WISPBAR: 10, Defs.STARIRON: 8}
		3: return {Defs.STARIRON: 12, Defs.HULL: 16}
		4: return {Defs.STARIRON: 16, Defs.VOIDESS: 16, Defs.XENITE: 8}
		5: return {Defs.VOIDESS: 24, Defs.XENITE: 12, Defs.HULL: 20}
		6: return {Defs.VOIDESS: 30, Defs.STARIRON: 20}
	return {}

const EXPAND_MANA := 40.0

func _heart(m) -> void:
	var lv: int = isle.level + 1
	if lv >= Isle.LEVELS.size():
		game.ui.toast("The Isle Heart hums, content: your isle is as large as it can grow", Color(0.85, 0.75, 1.0), 2.5)
		return
	var cost := expand_cost(lv)
	var ct: String = Build.cost_text(cost)
	if _offer_t <= 0:
		_offer_t = 240
		game.ui.toast("The Isle Heart can grow the isle (%d of %d): %s and %d mana. F again to grow it" % [lv, Isle.LEVELS.size() - 1, ct, int(EXPAND_MANA)], Color(0.85, 0.75, 1.0), 4.0)
		return
	_offer_t = 0
	for k in cost:
		if m.inv[int(k)] < int(cost[k]):
			game.ui.toast("Growing the isle needs %s" % ct, Color(1, 0.7, 0.5), 2.5)
			return
	if m.mana < EXPAND_MANA:
		game.ui.toast("Growing the isle needs %d mana" % int(EXPAND_MANA), Color(1, 0.7, 0.5), 2.0)
		return
	for k2 in cost:
		m.inv[int(k2)] -= int(cost[k2])
	m.mana -= EXPAND_MANA
	isle.expand()
	stats["expanded"] += 1
	save()
	game.audio.play("rare", m.pos, 0.8)
	var hw: Vector2 = isle.to_world(Vector2(float(Isle.W / 2), float(Isle.SURF)))
	for k3 in 4:
		game.vfx.spawn(Vfx.RING, hw, Vector2.ZERO, 30 + k3 * 10, Color(0.85, 0.6, 1.0), Color(0.4, 0.8, 1.0, 0.0), 6.0, 60.0 + k3 * 40.0)
	game.ui.toast("The isle grows", Color(0.85, 0.75, 1.0), 2.5)

# -------------------------------------------------------------- drawing ---

func _draw() -> void:
	if not active or (isle == null and place == "isle") or (op == null and place == "outpost"):
		return
	var vw := float(game.VW)
	var vh := float(game.VH)
	bgrect.position = Vector2.ZERO
	bgrect.size = Vector2(vw, vh)
	var mat: ShaderMaterial = bgrect.material
	mat.set_shader_parameter("cam", Vector2(-game.cam_c.x, game.cam_c.y))
	mat.set_shader_parameter("t", float(game.frame))
	mat.set_shader_parameter("size", Vector2(vw, vh))
	if place == "outpost":
		_draw_op()
		glow.queue_redraw()
		top.queue_redraw()
		return
	isle.pictures()
	isle.gather_lights()
	var xf: Transform2D = game.screen_xf()
	_far_isles(xf)
	# the isle: texture pixel (u, v) is cell (u, v), at world (-u, v)
	draw_set_transform_matrix(xf * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO))
	draw_texture(isle.tex_b, Vector2.ZERO)
	draw_texture(isle.tex_f, Vector2.ZERO)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	glow.queue_redraw()
	top.queue_redraw()

## a few far isles drifting behind (dark, small, slow: depth), each a low dome of grass over a tapering crag
func _far_isles(xf: Transform2D) -> void:
	var c: Vector2 = xf * Vector2.ZERO
	for k in 4:
		var par := 0.14 + 0.05 * float(k % 3)
		var px := float(k) * 170.0 - 260.0 + float(k % 2) * 40.0
		var at := Vector2(c.x * par + px + float(game.VW) * 0.5 * (1.0 - par), c.y * par - 40.0 + float((k * 53) % 90) + float(game.VH) * 0.35 * (1.0 - par))
		at.y += sin(t * 0.004 + float(k)) * 2.0
		var wdt := 12.0 + float((k * 37) % 14)
		var deep := wdt * (1.1 + 0.25 * float(k % 2))
		var fade := 0.35 + par * 1.6
		var top := PackedVector2Array()
		var body := PackedVector2Array()
		for q in 13:
			var u := float(q) / 12.0 * 2.0 - 1.0
			top.append((at + Vector2(u * wdt, -2.5 * (1.0 - u * u) - 1.0)).round())
		for q2 in 13:
			var u2 := 1.0 - float(q2) / 12.0 * 2.0
			var lump := 1.0 + 0.18 * sin(float(q2 * 5 + k * 3))
			body.append((at + Vector2(u2 * wdt, deep * pow(1.0 - absf(u2), 1.4) * lump)).round())
		var shape := PackedVector2Array(top)
		shape.append_array(body)
		draw_colored_polygon(shape, Color(0.13, 0.08, 0.22, fade))
		draw_polyline(top, Color(0.2, 0.36, 0.32, fade * 0.9), 1.0)
		# (a speck of crystal light under it)
		draw_rect(Rect2((at + Vector2(-1.0, deep * 0.55)).round(), Vector2(1, 1)), Color(0.8, 0.5, 1.0, fade))

func _halo_tex() -> ImageTexture:
	if _halo != null:
		return _halo
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		for i in n:
			var d := Vector2(i + 0.5 - n * 0.5, j + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = floor(a * a * 6.0) / 6.0             # (banded, as the spells' halos)
			img.set_pixel(i, j, Color(1, 1, 1, a))
	_halo = ImageTexture.create_from_image(img)
	return _halo

func _draw_glow() -> void:
	if active and place == "outpost":
		_draw_op_glow()
		return
	if not active or isle == null:
		return
	var xf: Transform2D = game.screen_xf()
	var ht := _halo_tex()
	var z: float = maxf(float(game.zoom), 0.01)
	for lt in isle.lights:
		var sp: Vector2 = xf * isle.to_world(lt[0])
		var r: float = float(lt[1]) / z
		var c: Color = lt[2]
		var pul := 0.32 + 0.06 * sin(t * 0.04 + sp.x * 0.05)
		glow.draw_texture_rect(ht, Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c.r, c.g, c.b, pul))
	# the arch: a shimmer in its opening
	var cx: int = Isle.W / 2 + Isle.ARCH_DX
	var at: float = floor(isle.top_at(cx, 0))
	for k in range(-Isle.ARCH_W / 2 + 1, Isle.ARCH_W / 2):
		var hgt: float = float(Isle.ARCH_H - Isle.ARCH_W / 2) + sqrt(maxf(0.0, pow(Isle.ARCH_W * 0.5 - 0.5, 2.0) - float(k * k)))
		var a := 0.12 + 0.1 * sin(t * 0.07 + float(k) * 0.7)
		var p0: Vector2 = xf * isle.to_world(Vector2(float(cx + k) + 0.5, at))
		var p1: Vector2 = xf * isle.to_world(Vector2(float(cx + k) + 0.5, at - hgt))
		glow.draw_line(p0, p1, Color(0.55, 0.45, 1.0, a), 1.0 / z)
	glow.draw_texture_rect(ht, Rect2(xf * isle.to_world(Vector2(float(cx) + 0.5, at - 14.0)) - Vector2(22, 22) / z, Vector2(44, 44) / z), false, Color(0.6, 0.45, 1.0, 0.25 + 0.08 * sin(t * 0.05)))
	# wisp-lights drifting over the isle
	var hw: float = float(Isle.LEVELS[isle.level]) + 30.0
	for md in motes:
		var base: Vector2 = md[0]
		var ph: float = float(md[1]) + t * 0.01 * float(md[2])
		var cp := Vector2(float(Isle.W) * 0.5 + base.x * hw + sin(ph) * 14.0, float(Isle.SURF) + base.y * 90.0 + cos(ph * 0.7) * 8.0)
		var sp2: Vector2 = xf * isle.to_world(cp)
		var mc: Color = md[3]
		var fl := 0.55 + 0.45 * sin(ph * 3.0)
		glow.draw_rect(Rect2(sp2.floor(), Vector2.ONE), Color(mc.r, mc.g, mc.b, fl))
		glow.draw_texture_rect(ht, Rect2(sp2 - Vector2(5, 5) / z, Vector2(10, 10) / z), false, Color(mc.r, mc.g, mc.b, 0.22 * fl))

func _draw_top() -> void:
	if active and place == "outpost":
		_draw_op_top()
		return
	if not active or isle == null:
		return
	var txt := ""
	var at := Vector2.ZERO
	var cx: int = Isle.W / 2
	if near == "arch":
		txt = "[F] Leave" + ("   [G] Out by your ship" if ship_here() else "")
		at = isle.to_world(Vector2(float(cx + Isle.ARCH_DX) + 0.5, isle.top_at(cx + Isle.ARCH_DX, 0) - float(Isle.ARCH_H) - 8.0))
	elif near == "heart":
		txt = "[F] The Isle Heart: grow the isle" if isle.level < Isle.LEVELS.size() - 1 else "The Isle Heart"
		at = isle.to_world(Vector2(float(cx + Isle.HEART_DX) + 0.5, isle.top_at(cx + Isle.HEART_DX, 0) - 30.0))
	if txt == "":
		return
	game.speech.draw(top, game.world_to_screen(at), txt, 1.0, "pocket_" + near, game.Speech.PROMPT)

# ============================================================ an outpost ===
# (docked: its halls as an instance; see the top of this file)

## F flying by an outpost out in space: its halls are grown in a worker, and you're in once they're ready
func dock(m, ext) -> bool:
	if active or _dock_task >= 0 or ext == null:
		return false
	_dock_from = ext
	_dock_made = [null]
	var sd: int = ext.seed_
	var sy: int = ext.sys
	var into: Array = _dock_made
	_dock_task = WorkerThreadPool.add_task(func() -> void: into[0] = Outpost.make_outpost(sd, sy, true))
	game.ui.toast("Docking at %s..." % ext.wname, Color(1.0, 0.85, 0.5), 1.5)
	game.audio.play("creak", m.pos, 0.6)
	return true

func docking() -> bool:
	return _dock_task >= 0

func _process(_d: float) -> void:
	if _dock_task < 0 or not WorkerThreadPool.is_task_completed(_dock_task):
		return
	WorkerThreadPool.wait_for_task_completion(_dock_task)
	_dock_task = -1
	var o = _dock_made[0]
	if o == null or game.state != "play" or not game.space.active or game.player.aboard == null:
		return                           # (left space, or off the ship, while it was being made: no docking)
	_enter_outpost(game.player, o)

## the docking finished at once (the tests; and a save loaded mid-dock)
func dock_now(m, ext) -> void:
	var o = Outpost.make_outpost(ext.seed_, ext.sys, true)
	_dock_from = ext
	_enter_outpost(m, o)

func _enter_outpost(m, o) -> void:
	op = o
	op.ang = PI
	op.facing = 1
	op.pos = Vector2.ZERO
	op.com = Vector2.ZERO
	op.texture()
	var sk = game.skiff
	back = {"pos": m.pos, "space": true, "zoom": game.zoom, "how": "dock", "ship": sk.pos if sk != null else m.pos,
		"ship_ang": sk.ang if sk != null else 0.0, "name": op.wname}
	if m.aboard != null:
		m.aboard.leave(m)
		m.aboard = null
		m.deck = false
	game.space.vel = Vector2.ZERO
	if sk != null:
		sk.vel = Vector2.ZERO
	game.build_on = false
	game.build_prev = {}
	place = "outpost"
	bgrect.material = _sky_mat
	_sky_mat.set_shader_parameter("hue", fposmod(float(op.seed_ % 997) / 997.0, 1.0))
	active = true
	visible = true
	op_folk.clear()
	for pl in op.folk_plan:
		op_folk.append(Spacer.make(op, pl))
	_op_lights = _gather_op_lights()
	b = _op_spawn(m)
	v = Vector2.ZERO
	m.pos = op.to_world(b)
	m.vx = 0.0
	m.vy = 0.0
	m.on_ground = false
	m.recall_t = 0
	game.zoom = 1.0
	game.view_c = Vector2.ZERO
	game.cam_c = m.pos.round()
	game.view_rect.visible = false
	game.space.visible = false
	game.weather.visible = false
	stats["docked"] += 1
	game.audio.play("dock", m.pos, 0.7)
	game.ui.toast("Docked at %s. Its shops are along the deck through the hangar's door; F at your ship to undock" % op.wname, Color(1.0, 0.85, 0.5), 4.5)

## your ship parked on the hangar's floor: [middle cell, floor row]
func _op_ship_at() -> Vector2:
	var hm: Dictionary = op.mods[op.hangar]
	var x0 := float(int(hm["x0"]))
	var x1 := float(int(hm["x1"]))
	var mid := (x0 + x1) * 0.5 + float(op.hangar_side) * (x1 - x0) * 0.12
	return Vector2(mid, float(int(hm["y1"])))

## where you stand when you come in: on the hangar's floor between your ship and the door to the deck
func _op_spawn(m) -> Vector2:
	var hm: Dictionary = op.mods[op.hangar]
	var x0 := float(int(hm["x0"]))
	var x1 := float(int(hm["x1"]))
	var sx: float = x1 - 22.0 if op.hangar_side < 0 else x0 + 22.0       # (the deck's door is away from the mouth)
	var at := Vector2(sx, float(int(hm["y1"])) - float(m.h) * 0.5 - 0.05)
	for k in 40:
		if op.box_free(at, float(m.w) * 0.5, float(m.h) * 0.5):
			break
		at.y -= 1.0
	return at

func _undock(m) -> void:
	active = false
	visible = false
	stats["undocked"] += 1
	var sk = game.skiff
	var at: Vector2 = back.get("ship", back.get("pos", m.pos))
	if sk != null:
		sk.pos = at
		sk.vel = Vector2.ZERO
		sk.ang = float(back.get("ship_ang", sk.ang))
	m.pos = at
	m.vx = 0.0
	m.vy = 0.0
	game.zoom = float(back.get("zoom", 1.0))
	game.space.visible = true
	game.space.vel = Vector2.ZERO
	game.weather.visible = true
	game.cam_c = m.pos
	game.view_c = Vector2.ZERO
	if sk != null and sk.board(m):
		m.aboard = sk
	place = "isle"
	bgrect.material = _neb_mat
	op = null
	op_folk.clear()
	near_keeper = null
	near_folk = null
	game.audio.play("dock", m.pos, 0.6)
	game.ui.toast("Undocked: you're aboard, by %s" % String(back.get("name", "the outpost")), Color(1.0, 0.85, 0.5), 2.5)

func _op_tick(m) -> void:
	for f in op_folk:
		f.tick()
	if game.frame % 20 == 3:
		for i in op_folk.size():
			var fa = op_folk[i]
			if fa.wait <= 0:
				continue
			for k in range(i + 1, op_folk.size()):
				var fb = op_folk[k]
				if fb.wait > 0 and absf(fb.b.x - fa.b.x) < 8.0 and absf(fb.b.y - fa.b.y) < 4.0:
					fb.step_aside(1 if fb.b.x >= fa.b.x else -1)
					break
	# what F would do: your ship, a keeper's counter, a spacer beside you
	near = ""
	near_keeper = null
	near_folk = null
	var sa := _op_ship_at()
	if b.distance_to(sa + Vector2(0.0, -10.0)) < 34.0:
		near = "ship"
		return
	var best := PROMPT_REACH + 6.0
	for kp in op.keepers:
		var d: float = b.distance_to(kp.b + Vector2(0.0, -10.0))
		if d < best:
			best = d
			near_keeper = kp
	if near_keeper != null:
		near = "keeper"
		return
	var fb2 := PROMPT_REACH
	for f2 in op_folk:
		var fd: float = b.distance_to(f2.b)
		if fd < fb2:
			fb2 = fd
			near_folk = f2
	if near_folk != null:
		near = "folk"

func _op_interact(m) -> bool:
	match near:
		"ship":
			leave(m)
			return true
		"keeper":
			stats["trades"] += 1
			game.space.open_trade(op, near_keeper)
			return true
		"folk":
			stats["talks"] += 1
			game.space._folk_talk(near_folk)
			return true
	return false

## the glowing cells of its halls, gathered into a few halos (blocks of 16)
func _gather_op_lights() -> Array:
	var out := []
	for by in range(0, op.h, 16):
		for bx in range(0, op.w, 16):
			var n := 0
			var col := Color(0, 0, 0)
			var sx := 0.0
			var sy := 0.0
			for j in range(by, mini(by + 16, op.h)):
				for i in range(bx, mini(bx + 16, op.w)):
					var mt: int = op.cells[j * op.w + i]
					if mt == 0 or Defs.SELF[mt] == 0:
						continue
					var c := Color.hex((Defs.PAL[mt * 4] << 8) | 0xff)
					n += 1
					col += c
					sx += float(i)
					sy += float(j)
			if n > 0:
				out.append([Vector2(sx / n + 0.5, sy / n + 0.5), 12.0 + sqrt(float(n)) * 4.0, col / float(n)])
	return out

func _draw_op() -> void:
	var xf: Transform2D = game.screen_xf()
	draw_set_transform_matrix(xf * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO))
	draw_texture(op.back_texture(), Vector2.ZERO)
	# your ship, parked on the hangar's floor (its back, then its hull)
	var sk = game.skiff
	if sk != null:
		var sa := _op_ship_at()
		var st: ImageTexture = sk.texture()
		var stb: ImageTexture = sk.back_texture()
		var o := Vector2(sa.x - float(sk.w) * 0.5, sa.y - float(sk.h) + 1.0)
		var mir: bool = op.hangar_side < 0          # (its nose toward the hangar's mouth)
		if mir:
			draw_set_transform_matrix(xf * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO) * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(sa.x * 2.0, 0.0)))
		draw_texture(stb, o)
		draw_texture(st, o)
		draw_set_transform_matrix(xf * Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2.ZERO))
	draw_texture(op.texture(), Vector2.ZERO)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# the keepers, each behind a counter drawn in front of them; the spacers
	for kp in op.keepers:
		var kt: ImageTexture = op.keeper_texture(kp)
		var kps: Vector2 = (xf * op.to_world(kp.b)).floor()
		draw_set_transform(kps, 0.0, Vector2(float(-kp.facing), 1.0))
		draw_texture(kt, Vector2(-float(kt.get_width()) * 0.5, -float(kt.get_height()) + 1.0))
		var ct: ImageTexture = op.counter_texture(kp)
		draw_texture(ct, Vector2(-6.0, -float(ct.get_height())))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for f in op_folk:
		var ft: ImageTexture = f.texture()
		var fs: Vector2 = (xf * op.to_world(f.b)).floor()
		draw_set_transform(fs, 0.0, Vector2(float(-f.facing), 1.0))
		draw_texture(ft, Vector2(-float(ft.get_width()) * 0.5, 9.5 + 1.0 - float(ft.get_height())))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_op_glow() -> void:
	var xf: Transform2D = game.screen_xf()
	var ht := _halo_tex()
	var z: float = maxf(float(game.zoom), 0.01)
	var scr := Vector2(float(game.VW), float(game.VH))
	for lt in _op_lights:
		var sp: Vector2 = xf * op.to_world(lt[0])
		var r: float = float(lt[1]) / z
		if sp.x < -r or sp.y < -r or sp.x > scr.x + r or sp.y > scr.y + r:
			continue
		var c: Color = lt[2]
		glow.draw_texture_rect(ht, Rect2(sp - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c.r, c.g, c.b, 0.28 + 0.04 * sin(t * 0.03 + sp.x * 0.05)))

func _draw_op_top() -> void:
	var xf: Transform2D = game.screen_xf()
	# the shops' signs over their counters
	for kp in op.keepers:
		if kp == near_keeper:
			continue
		var sp: Vector2 = xf * op.to_world(kp.b + Vector2(0.0, -34.0))
		_top_text(sp, String(Outpost.OP_ROOMS[kp.shop]).to_upper(), Outpost.SHOP_COL[kp.shop])
	for f in op_folk:
		if f.say_t > 0:
			game.speech.draw(top, xf * op.to_world(f.b + Vector2(0.0, -12.0)), f.say, clampf(float(f.say_t) / 30.0, 0.0, 1.0), "s%d" % f.fseed, game.Speech.SPEECH, op.to_world(f.b), game.Speech.pitch_of(f.fseed))
	var txt := ""
	var at := Vector2.ZERO
	match near:
		"ship":
			txt = "[F] Undock"
			at = _op_ship_at() + Vector2(0.0, -float(game.skiff.h if game.skiff != null else 30) - 6.0)
		"keeper":
			txt = "[F] trade with %s, %s" % [near_keeper.name, String(Outpost.OP_ROOMS[near_keeper.shop]).to_lower()]
			at = near_keeper.b + Vector2(0.0, -34.0)
		"folk":
			if near_folk.say_t <= 0:
				txt = "[F] talk to %s" % near_folk.name
				at = near_folk.b + Vector2(0.0, -14.0)
	if txt != "":
		game.speech.draw(top, xf * op.to_world(at), txt, 1.0, "op_" + near, game.Speech.PROMPT)

func _top_text(at: Vector2, txt: String, col: Color) -> void:
	var f2: Font = PixelFont.make()
	var px: float = float(game.scale_px)
	var sz: int = PixelFont.SIZE * int(game.ui.U)
	var wd := f2.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	top.draw_set_transform(at, 0.0, Vector2.ONE / px)
	top.draw_string(f2, Vector2(-wd * 0.5 + 1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.7))
	top.draw_string(f2, Vector2(-wd * 0.5, 0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
