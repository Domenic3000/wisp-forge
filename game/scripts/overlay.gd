extends Node2D
## Draws everything that isn't terrain, in screen pixels on top of the GPU
## picture: the mage, the wisp, foes, spells, particles and the reticle.

var game
var tex := {}

func _ready() -> void:
	for k in Defs.SPRITES:
		tex[k] = Defs.sprite_texture(k)

# which animation frame a mage shows
func _mage_frame(m) -> String:
	if game.frame - m.cast_frame < 10:
		return "mage_cast"
	if not m.on_ground and not m.in_liquid:
		if m.floating:
			return "mage_float"
		return "mage_jump" if m.vy < 0.0 else "mage_fall"
	if absf(m.vx) > 0.15:
		return "mage_walk%d" % (int(m.anim) % 4 + 1)
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
		_:
			if tex.has(key + "2") and absf(e.vx) > 0.1 and int(e.anim) % 2 == 1:
				return key + "2"
	return key

func _lit(sp: Vector2) -> Color:
	var c: Color = game.gpu.light_at(sp)
	return Color(clampf(c.r, 0.12, 1.0), clampf(c.g, 0.12, 1.0), clampf(c.b, 0.12, 1.0))

func _sprite(key: String, wpos: Vector2, flip: bool, white: bool, body_h: float) -> void:
	var t: Texture2D = tex[key]
	var sp: Vector2 = game.world_to_screen(wpos)
	var cam_a := atan2(game.cam_c.y, game.cam_c.x)
	var rot := cam_a - atan2(wpos.y, wpos.x)
	var z: float = game.zoom
	var sc := Vector2(-1.0 if flip else 1.0, 1.0) / z
	draw_set_transform(sp.round() if absf(rot) < 0.02 else sp, rot, sc)
	var mod := Color(4, 4, 4) if white else _lit(sp)
	# feet (last opaque row, above the outline) rest on the bottom of the body box
	var ts := t.get_size()
	draw_texture(t, Vector2(-floorf(ts.x * 0.5), body_h * 0.5 - ts.y + 1.0), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _px(wpos: Vector2, col: Color) -> void:
	var sp: Vector2 = game.world_to_screen(wpos)
	draw_rect(Rect2(sp.floor(), Vector2.ONE), col)

func _draw() -> void:
	if game == null or game.state == "title" or game.state == "loading" or game.state == "error":
		return
	var z: float = game.zoom
	# foes
	for e in game.enemies:
		_sprite(_foe_frame(e), e.pos, e.facing < 0, e.flash > 0, e.h)
	# projectiles
	for pr in game.projs:
		var c: Color = Defs.SPELLS[pr["type"]]["color"] if Defs.SPELLS.has(pr["type"]) else Color(1, 0.35, 0.12)
		var sp: Vector2 = game.world_to_screen(pr["pos"])
		var big := 1 if pr["type"] == "fireball" or pr["type"] == "quake" else 0
		draw_rect(Rect2(sp.floor() - Vector2(big, big), Vector2(1 + 2 * big, 1 + 2 * big)), c)
		draw_rect(Rect2(sp.floor(), Vector2.ONE), Color(1, 1, 0.9))
	# the mage and staff
	for m in game.players:
		if m != game.player and not m.dead:
			_sprite(_mage_frame(m), m.pos, m.facing < 0, false, m.h)
	if not game.dead:
		var blink: bool = game.iframes > 0 and (game.iframes / 4) % 2 == 0
		if not blink:
			_sprite(_mage_frame(game.player), game.player.pos, game.player.facing < 0, false, game.player.h)
		var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
		var st: Array = game._staff(game.player, aim)
		var hand: Vector2 = st[2]
		var dir: Vector2 = st[1]
		for s in 10:
			_px(hand + dir * s, Color8(120, 82, 44) * _lit(game.world_to_screen(hand)))
		var sc: Color = Defs.SPELLS[game.known[game.sel]]["color"]
		_px(st[0], sc)
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
