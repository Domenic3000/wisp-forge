extends Node2D
## Draws everything that isn't terrain, in screen pixels on top of the GPU
## picture: the mage, the wisp, foes, spells, particles and the reticle.

const MageRig := preload("res://scripts/mage_rig.gd")

var game
var tex := {}
var _door_keys := []          # pictures of damaged open doors made so far (oldest first)
var _masks := {}

func _ready() -> void:
	for k in Defs.SPRITES:
		tex[k] = Defs.sprite_texture(k)
	tex["door_open"] = ImageTexture.create_from_image(_door_open_image(30))

func _draw_build_preview() -> void:
	if not game.build_on or game.build_prev.is_empty():
		return
	var pv: Dictionary = game.build_prev
	var ok: bool = pv.get("ok", false)
	var z: float = game.zoom
	var pulse := 0.55 + 0.2 * sin(float(game.frame) * 0.15)
	for c in pv.get("cells", []):
		var sp: Vector2 = game.world_to_screen(c[0])
		var col: Color = c[1]
		if not ok:
			col = col.lerp(Color(1, 0.2, 0.15), 0.6)
		col.a = pulse
		draw_rect(Rect2(sp - Vector2(0.5, 0.5) / z, Vector2.ONE / z), col)
	if pv.get("tex") != null:
		# a whole structure, as one picture, its top-left corner (on screen) on its corner cell
		var tx: Texture2D = pv["tex"]
		var csp: Vector2 = game.world_to_screen(pv["corner"]) - Vector2(0.5, 0.5) / z
		var rot := 0.0 if game.unrolled() else wrapf(atan2(game.cam_c.y, game.cam_c.x) - atan2(pv["corner"].y, pv["corner"].x), -PI, PI)
		draw_set_transform(csp, rot, Vector2.ONE / z)
		draw_texture(tx, Vector2.ZERO, Color(1, 1, 1, pulse + 0.2))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if pv.has("circle"):
		var cp: Vector2 = game.world_to_screen(pv["circle"][0])
		var rr: float = float(pv["circle"][1]) / z
		draw_arc(cp, rr + 0.5, 0.0, TAU, 20, Color(0.6, 1.0, 0.6, 0.8) if ok else Color(1, 0.35, 0.3, 0.8), 1.0 / maxf(z, 1.0))

## An open door, swung open towards you and seen face-on (no perspective): a plank door with
## a frame, two iron straps with rivets, a little barred window and a brass handle on the far
## edge (the hinge edge is at the left; the overlay mirrors it for doors that swing the other way).
## (`cells`: the door's parts across its doorway, `dw` wide, -1 where a part is gone: that slice
## of the panel is missing, and the wood around a hole is charred dark)
static func _door_open_image(h: int, cells := [], dw := 3) -> Image:
	var w := 10
	var img := Image.create(w, h + 1, false, Image.FORMAT_RGBA8)   # an empty last row, like the sprites' outline
	var dk := Color("#3a2412")
	var md := Color("#6b4423")
	var lt := Color("#8f5f33")
	var hl := Color("#a8743e")
	var ir := Color("#50505a")
	var irl := Color("#8a8a96")
	for x in w:
		for y in h:
			var c := lt if (x % 3) != 0 else md
			if x == 1:
				c = hl
			if (y * 7 + x * 3) % 13 == 0:
				c = md                                   # grain
			if y == 5 or y == 6 or y == h - 7 or y == h - 6:
				c = ir
				if (y == 5 or y == h - 7) and x % 3 == 1:
					c = irl                              # rivets
			if y >= 9 and y <= 13 and x >= 3 and x <= 6:
				c = Color("#141018") if not (y == 11 or x == 4) else ir    # the barred window
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				c = dk
			img.set_pixel(x, y, c)
	img.set_pixel(w - 3, h / 2, Color("#e2b048"))
	img.set_pixel(w - 3, h / 2 + 1, Color("#9a6c24"))
	if cells.size() == dw * h:
		var gone := func(x: int, y: int) -> bool:
			if x < 0 or y < 0 or x >= w or y >= h:
				return false
			return int(cells[y * dw + mini(int(float(x) * dw / w), dw - 1)]) < 0
		var out := img.duplicate()
		for x in w:
			for y in h:
				if gone.call(x, y):
					out.set_pixel(x, y, Color(0, 0, 0, 0))
				elif gone.call(x - 1, y) or gone.call(x + 1, y) or gone.call(x, y - 1) or gone.call(x, y + 1):
					out.set_pixel(x, y, img.get_pixel(x, y).lerp(Color("#1a1008"), 0.6))
		return out
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
	# open doors, swung out of their houses
	for d in game.doors:
		if not d["open"]:
			continue
		var dp: Vector2 = d["pos"]
		var dsp: Vector2 = game.world_to_screen(dp)
		if dsp.x < -40 or dsp.y < -40 or dsp.x > game.VW + 40 or dsp.y > game.VH + 40:
			continue
		# a door swings away from whoever opened it; the panel stands face-on beside the doorway,
		# hinged at its edge
		var swing := float(d.get("swing", d["side"]))
		var dkey := "door_open"
		var dc: Array = d.get("cells", [])
		if dc.has(-1):
			# a damaged door: its own picture, with the holes (made once per state of damage)
			dkey = "door_open_%d_%d" % [int(d["h"]), hash(dc)]
			if not tex.has(dkey):
				if _door_keys.size() > 64:
					tex.erase(_door_keys.pop_front())
				_door_keys.append(dkey)
				tex[dkey] = ImageTexture.create_from_image(_door_open_image(int(d["h"]), dc, int(d["w"])))
		_sprite(dkey, game.door_panel_pos(d), swing < 0.0, false, float(d["h"]), true)
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
	# build mode: what would go where, in its own colours (red where it doesn't fit)
	_draw_build_preview()
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
