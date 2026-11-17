extends Node2D
## Draws everything that isn't terrain, in screen pixels on top of the GPU
## picture: the mage, the wisp, foes, spells, particles and the reticle.

const MageRig := preload("res://scripts/mage_rig.gd")

var game
var tex := {}
var _masks := {}

func _ready() -> void:
	for k in Defs.SPRITES:
		tex[k] = Defs.sprite_texture(k)
	tex["door_open"] = ImageTexture.create_from_image(_door_open_image(30))

## An open door, swung into the room and seen a little from the side: the hinge edge at the left,
## the far edge one pixel shorter top and bottom, planks, two iron straps and the handle.
static func _door_open_image(h: int) -> Image:
	var w := 8
	var img := Image.create(w, h + 1, false, Image.FORMAT_RGBA8)   # an empty last row, like the sprites' outline
	var dk := Color("#3a2412")
	var md := Color("#7a4e28")
	var lt := Color("#9a6634")
	var hl := Color("#b98048")
	var ir := Color("#50505a")
	var irl := Color("#8a8a96")
	for x in w:
		var inset := int(round(float(x) / float(w - 1) * 1.5))
		for y in range(inset, h - inset):
			var c := lt if x % 3 != 2 else md
			if x == 0:
				c = hl
			var from_top := y - inset
			var from_bot := h - inset - 1 - y
			if from_top == 5 or from_top == 6 or from_bot == 5 or from_bot == 6:
				c = irl if x == 0 else ir
			if from_top == 0 or from_bot == 0 or x == w - 1:
				c = dk
			img.set_pixel(x, y, c)
	img.set_pixel(w - 2, h / 2, Color("#e2b048"))
	img.set_pixel(w - 2, h / 2 + 1, Color("#9a6c24"))
	return img

# which animation frame a mage shows
func _mage_frame(m) -> String:
	if m.iframes > 28 and m.iframes <= 40:
		return "mage_hurt"            # just hit (a hit gives 40 frames of grace)
	if game.frame - m.cast_frame < 10:
		return "mage_cast"
	if not m.on_ground and not m.in_liquid:
		if m.floating:
			return "mage_float"
		return "mage_jump" if m.vy < 0.0 else "mage_fall"
	if absf(m.vx) > 0.15:
		return "mage_walk%d" % (int(m.anim * 1.5) % 6 + 1)
	if game.frame % 260 < 7:
		return "mage_blink"
	return "mage_idle2" if int(game.frame / 40) % 3 == 2 else "mage"

# two-frame foes: slimes squash as they hop, imps and bats flap, skeletons and golems step, mimics bite
func _foe_frame(e) -> String:
	var key: String = e.d["spr"]
	match e.type:
		"bat":
			return "bat1" if int(e.phase * 2.0) % 2 == 0 else "bat2"
		"slime":
			return "slime2" if (not e.on_ground or int(e.anim * 3.0) % 2 == 1) else "slime"
		"imp":
			return "imp2" if int(e.phase * 3.0) % 2 == 1 else "imp"
		"mimic":
			return "mimic2" if (not e.on_ground or int(game.frame / 6) % 2 == 1) else "mimic"
		"golem":
			if not e.awake:
				return "golem_sleep"
			if e.leaping or not e.on_ground:
				return "golem_leap"
			if absf(e.vx) > 0.1:
				return ["golem", "golem2", "golem", "golem3"][int(e.anim * 0.7) % 4]
			return "golem"
		_:
			if tex.has(key + "2") and absf(e.vx) > 0.1 and int(e.anim) % 2 == 1:
				return key + "2"
	return key

func _lit(sp: Vector2) -> Color:
	var c: Color = game.gpu.light_at(sp)
	return Color(clampf(c.r, 0.12, 1.0), clampf(c.g, 0.12, 1.0), clampf(c.b, 0.12, 1.0))

## Where a body's feet are drawn on screen. Sprites hang from the feet, not the centre: a body
## standing on the ground has its feet snapped onto the same cell row as the ground under it,
## so it can't flicker a pixel up and down against the terrain while the camera eases (with
## an odd body height the centre sits right on a half pixel, and rounding it flipped back and
## forth). Returns [drawn position, unsnapped position].
func _feet(wpos: Vector2, body_h: float, grounded: bool) -> Array:
	var up := wpos.normalized()
	var feet := wpos - up * (body_h * 0.5)
	var raw: Vector2 = game.world_to_screen(feet)
	if grounded:
		# cell rows are whole numbers of radius (R_TOP is a whole number)
		feet = up * roundf(feet.length())
	var sp: Vector2 = game.world_to_screen(feet)
	if game.unrolled() or absf(wrapf(atan2(game.cam_c.y, game.cam_c.x) - atan2(wpos.y, wpos.x), -PI, PI)) < 0.02:
		sp = sp.round()
	return [sp, raw]

func _sprite(key: String, wpos: Vector2, flip: bool, white: bool, body_h: float, grounded := false, alpha := 1.0, squash := 1.0) -> void:
	var t: Texture2D = tex[key]
	var sp: Vector2 = _feet(wpos, body_h, grounded)[0]
	# upright in the unrolled view; turned with the planet's curve in the round map view
	var rot := 0.0 if game.unrolled() else wrapf(atan2(game.cam_c.y, game.cam_c.x) - atan2(wpos.y, wpos.x), -PI, PI)
	var z: float = game.zoom
	var sc := Vector2((-1.0 if flip else 1.0) * (2.0 - squash), squash) / z
	draw_set_transform(sp, rot, sc)
	var mod := Color(4, 4, 4) if white else _lit(game.world_to_screen(wpos))
	mod.a = alpha
	# feet (last opaque row, above the outline) rest on the bottom of the body box
	var ts := t.get_size()
	draw_texture(t, Vector2(-floorf(ts.x * 0.5), -ts.y + 1.0), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A mage: the frame, plus the parts mage_rig.gd simulates (the scarf behind him; the hat's tip,
## the beard's end and the staff in front), all in the sprite's own pixels and transform.
## The rig keeps moving while he blinks invisible after a hit, so nothing jumps when he reappears.
func _draw_mage(m, aim_w: Vector2, gem: Color, visible_now: bool) -> void:
	var key := _mage_frame(m)
	if m.rig == null:
		m.rig = MageRig.new()
	var a := atan2(m.pos.y, m.pos.x)
	var fwd := float(m.facing)
	# the staff points at the cursor (snappier while casting)
	var d: Vector2 = aim_w - m.pos
	var aim := Vector2(d.dot(game.basis_r(a)) * fwd, d.dot(game.basis_d(a))).normalized()
	var casting: bool = game.frame - m.cast_frame < 14 or m.input.cast
	m.rig.update(key, Vector2(m.vx * fwd, m.vy), aim, Vector2.ZERO, casting)
	if not visible_now:
		return
	if not _masks.has(key):
		_masks[key] = MageRig.body_mask(key)
	var t: Texture2D = tex[key]
	var sp: Vector2 = _feet(m.pos, m.h, m.on_ground)[0]
	var rot := 0.0 if game.unrolled() else wrapf(atan2(game.cam_c.y, game.cam_c.x) - a, -PI, PI)
	var sc: Vector2 = Vector2(-1.0 if m.facing < 0 else 1.0, 1.0) / float(game.zoom)
	draw_set_transform(sp, rot, sc)
	var mod := _lit(game.world_to_screen(m.pos))
	mod = mod.lerp(Color(0.86, 0.88, 0.95), clampf(m.fog, 0.0, 1.0) * 0.55)   # misted over inside a cloud
	var ts := t.get_size()
	var origin := Vector2(-floorf(ts.x * 0.5) + 1.0, -ts.y + 2.0)
	MageRig.draw_pixels(self, m.rig.back_pixels(), origin, 1.0, mod, _masks[key])
	draw_texture(t, Vector2(-floorf(ts.x * 0.5), -ts.y + 1.0), mod)
	MageRig.draw_pixels(self, m.rig.front_pixels(gem), origin, 1.0, mod, _masks[key])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _px(wpos: Vector2, col: Color) -> void:
	var sp: Vector2 = game.world_to_screen(wpos)
	draw_rect(Rect2(sp.floor(), Vector2.ONE), col)

func _draw() -> void:
	if game == null or game.state == "title" or game.state == "loading" or game.state == "error":
		return
	var z: float = game.zoom
	# treasure chests (whole objects)
	for c in game.chests:
		var csp: Vector2 = game.world_to_screen(c.pos)
		if csp.x < -20 or csp.y < -20 or csp.x > game.VW + 20 or csp.y > game.VH + 20:
			continue
		# an opened chest stands open for a moment, then glows, shrinks and fades into sparkles
		var ch_a := 1.0
		var ch_sq := 1.0
		if c.open_t > 50:
			var ch_f := clampf(float(c.open_t - 50) / 60.0, 0.0, 1.0)   # CHEST_VANISH (110) - 50
			ch_a = 1.0 - ch_f * ch_f
			ch_sq = 1.0 - ch_f * 0.7
		_sprite("chest_open" if c.opened else "chest", c.pos, false, c.open_t > 50 and (c.open_t / 4) % 2 == 0, c.h, true, ch_a, ch_sq)
	# open doors, swung into their houses
	for d in game.doors:
		if not d["open"]:
			continue
		var dp: Vector2 = d["pos"]
		var dsp: Vector2 = game.world_to_screen(dp)
		if dsp.x < -40 or dsp.y < -40 or dsp.x > game.VW + 40 or dsp.y > game.VH + 40:
			continue
		var da := atan2(dp.y, dp.x)
		# the local "inside" direction (columns increasing) is against basis_r, which is screen right
		var side := float(d["side"])
		var wp: Vector2 = dp - game.basis_r(da) * side * (float(d["w"]) * 0.5 + 4.0)
		_sprite("door_open", wp, side > 0.0, false, float(d["h"]), true)
	# foes
	for e in game.enemies:
		_sprite(_foe_frame(e), e.pos, e.facing < 0, e.flash > 0, e.h, e.on_ground)
	# projectiles
	for pr in game.projs:
		var c: Color = Defs.SPELLS[pr["type"]]["color"] if Defs.SPELLS.has(pr["type"]) else Color(1, 0.35, 0.12)
		var sp: Vector2 = game.world_to_screen(pr["pos"])
		var big := 1 if pr["type"] == "fireball" or pr["type"] == "quake" else 0
		draw_rect(Rect2(sp.floor() - Vector2(big, big), Vector2(1 + 2 * big, 1 + 2 * big)), c)
		draw_rect(Rect2(sp.floor(), Vector2.ONE), Color(1, 1, 0.9))
	# the mages, with their simulated hats, beards, scarves and staves
	for m in game.players:
		if m != game.player and not m.dead:
			_draw_mage(m, m.input.aim, Color("#46e6f0"), true)
	if not game.dead:
		var blink: bool = game.iframes > 0 and (game.iframes / 4) % 2 == 0
		var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
		_draw_mage(game.player, aim, Defs.SPELLS[game.known[game.sel]]["color"], not blink)
	# wisp companion
	var ws: Vector2 = game.world_to_screen(game.wisp)
	var wf := ws.floor()
	draw_rect(Rect2(wf - Vector2(1, 0), Vector2(3, 1)), Color8(90, 170, 255, 200))
	draw_rect(Rect2(wf - Vector2(0, 1), Vector2(1, 3)), Color8(90, 170, 255, 200))
	draw_rect(Rect2(wf, Vector2.ONE), Color8(245, 252, 255))
	# particles
	for p in game.parts:
		var c2: Color = p["col"]
		if not p["self"]:
			c2 = c2 * _lit(game.world_to_screen(p["pos"]))
		_px(p["pos"], c2)
	# reticle + reach circle (the normal pointer takes over above menus)
	if game.ui.mouse_over_ui():
		return
	var m: Vector2 = (get_viewport().get_mouse_position() / game.scale_px).floor()
	var rc := Color(1, 1, 1, 0.7)
	for k in range(2, 5):
		draw_rect(Rect2(m + Vector2(k, 0), Vector2.ONE), rc)
		draw_rect(Rect2(m - Vector2(k, 0), Vector2.ONE), rc)
		draw_rect(Rect2(m + Vector2(0, k), Vector2.ONE), rc)
		draw_rect(Rect2(m - Vector2(0, k), Vector2.ONE), rc)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if game.state == "play" and (rmb or game.known[game.sel] == "conjure"):
		var aim2: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
		var rp: Vector2 = game.world_to_screen(game._reach(game.player, aim2))
		var r: float = ((game.dig_r * (0.8 if Input.is_key_pressed(KEY_SHIFT) else 1.0)) if rmb else 2.6) / z
		var col := Color(0.55, 1.0, 0.67, 0.55) if rmb else Color(1.0, 0.94, 0.63, 0.55)
		if rmb and Input.is_key_pressed(KEY_SHIFT):
			col = Color(1.0, 0.6, 0.3, 0.6)   # deconstructing background tiles
		for a in 24:
			var t := a / 24.0 * TAU
			draw_rect(Rect2((rp + Vector2(cos(t), sin(t)) * (r + 0.5)).round(), Vector2.ONE), col)
