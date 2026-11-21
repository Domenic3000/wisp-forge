extends Node2D
const FoeAI := preload("res://scripts/foe_ai.gd")
## Draws everything that isn't terrain, in screen pixels on top of the GPU
## picture: the mage, the wisp, foes, spells, particles and the reticle.

const MageRig := preload("res://scripts/mage_rig.gd")
const BossArt := preload("res://scripts/boss_art.gd")
const FolkArt := preload("res://scripts/folk_art.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Ecology := preload("res://scripts/ecology.gd")

var _gaps := {}             # empty rows under each sprite frame's feet (`_gap_under`)
var game
var tex := {}
var _door_keys := []          # pictures of damaged open doors made so far (oldest first)
var _masks := {}
var _boss_made := {}          # guardians whose frames have been grown (boss_art.gd), by type

func _ready() -> void:
	for k in Defs.SPRITES:
		tex[k] = Defs.sprite_texture(k)
	# a bat asleep under a cave roof: its first frame upside down
	var bh: Image = tex["bat1"].get_image()
	bh.flip_y()
	tex["bat_hang"] = ImageTexture.create_from_image(bh)
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
		var rot := 0.0 if game.unrolled() else wrapf(game.view_angle() - atan2(pv["corner"].y, pv["corner"].x), -PI, PI)
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
	if e.d.has("def"):
		return _boss_frame(e)
	var key: String = e.d["spr"]
	match e.type:
		"bat":
			if e.pose == "hang":
				return "bat_hang"
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
			if e.act == "windup" and tex.has(key + "_draw"):
				return key + "_draw"         # (an archer drawing its bow)
			if tex.has(key + "2") and absf(e.vx) > 0.1 and int(e.anim) % 2 == 1:
				return key + "2"
	return key

## A creature's life (ecology.gd) shown over it: a frog's tongue out, the "z"s of a sleeper.
func _eco_marks(e) -> void:
	if e.under:
		return
	if e.tongue > 0.5:
		var m: Vector2 = Ecology._mouth(game, e)
		var a0: Vector2 = game.world_to_screen(m)
		var a1: Vector2 = game.world_to_screen(m + e.aim * e.tongue)
		var lc := _lit(a0)
		var n := int(ceil(a0.distance_to(a1))) + 1
		for k in n + 1:
			var q := a0.lerp(a1, float(k) / float(n)).floor()
			draw_rect(Rect2(q, Vector2.ONE), Color(0.92, 0.42, 0.5) * lc)
		draw_rect(Rect2(a1.floor() - Vector2(1, 1), Vector2(2, 2)), Color(0.98, 0.55, 0.62) * lc)
	if e.asleep and e.pose != "hang":
		var a := atan2(e.pos.y, e.pos.x)
		var px: float = float(game.scale_px)
		var u: int = game.ui.U
		var fb: Font = PixelFont.make(true)
		for k2 in 2:
			var ph := fposmod(float(game.frame) * 0.008 + float(k2) * 0.5 + e.phase, 1.0)
			var zp: Vector2 = game.world_to_screen(e.pos - game.basis_d(a) * (e.h * 0.5 + 2.0 + ph * 8.0) + game.basis_r(a) * float(e.facing) * (e.w * 0.3 + ph * 3.0))
			draw_set_transform(zp.round(), 0.0, Vector2.ONE / px)
			draw_string(fb, Vector2.ZERO, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE * u, Color(0.85, 0.9, 1.0, sin(ph * PI) * 0.7))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## creatures killed by others (ecology.gd): on their backs, darkened, fading as they go
func _draw_carcasses() -> void:
	for cc in game.eco_carcasses:
		var key: String = cc["type"]
		if not tex.has(key):
			continue
		var t: Texture2D = tex[key]
		var sp: Vector2 = game.world_to_screen(cc["pos"])
		if sp.x < -60 or sp.y < -60 or sp.x > game.VW + 60 or sp.y > game.VH + 60:
			continue
		var z: float = game.zoom
		var ts := t.get_size()
		var mod := _lit(sp) * Color(0.62, 0.55, 0.52)
		mod.a = clampf(float(cc["t"]) / 300.0, 0.0, 1.0)
		# (flipped top to bottom: its back on the ground, the empty margin over its head sunk into it)
		draw_set_transform(_snap(sp), 0.0, Vector2(-1.0 if int(cc["facing"]) < 0 else 1.0, -1.0) / z)
		draw_texture(t, Vector2(-floorf(ts.x * 0.5), -floorf(ts.y - float(cc["h"]) - 3.0)), mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## a guardian's frame for what it's doing (boss_art.gd names them)
func _boss_frame(e) -> String:
	var id: String = e.type
	var plan: String = e.d["def"]["body"]["plan"]
	if plan == "bird":
		if e.move.begins_with("dive") and e.act == "go":
			return id + "_dive"
		if e.act == "windup":
			return id + "_wind"
		if e.pose != "" and tex.has(id + "_" + e.pose):
			return id + "_" + e.pose            # (perched in a tree, asleep there)
		return "%s_fly%d" % [id, int(float(game.frame) * 0.16 + e.phase) % 4]
	if plan == "serpent":
		return id + "_head"
	if not e.awake:
		return id
	if e.act == "windup":
		return id + "_wind"
	# its daily life (ecology.gd): grazing, asleep, croaking, growling at you
	if e.act == "" and e.pose != "" and not e.air_on and tex.has(id + "_" + e.pose):
		return id + "_" + e.pose
	# jumping, or falling more than a step (one frame's on_ground flickers on a curved slope; main.gd keeps
	# `air_on` at least 3 frames once it shows)
	if e.leaping or e.air_on:
		return id + "_air"
	if plan == "toad":
		# a frog sits or hops, it never walks: it crouches before a hop and squashes as it lands
		if (e.crouch_t > 0 or e.land_t > 0) and tex.has(id + "_crouch"):
			return id + "_crouch"
		return id
	if absf(e.vx) > 0.1:
		return "%s_walk%d" % [id, int(e.anim * 0.6) % 4]
	return id

func _boss_art(e) -> void:
	if _boss_made.has(e.type):
		return
	_boss_made[e.type] = true
	var fr: Dictionary = BossArt.frames(e.type, e.d["def"]["body"])
	for k in fr:
		tex[k] = ImageTexture.create_from_image(fr[k])

## a serpent: its segments along its trail (tail first; a burrower's are hidden in the ground), then
## its head, jaws open while it strikes
func _draw_serpent(e, tint: Color) -> void:
	var white: bool = e.flash > 0
	var burrow: bool = e.d["def"]["go"] == "burrow"
	for k in range(e.trail.size() - 1, -1, -1):
		var p: Vector2 = e.trail[k]
		if burrow:
			var kd: int = Defs.KIND[game.type_at(p)]
			if e.under or kd == Defs.K_SOLID or kd == Defs.K_POWDER:
				continue
		_sprite_mid("%s_seg%d" % [e.type, k], p, false, white, tint)
	if e.under:
		return
	var open: bool = e.act == "windup" or e.act == "go"
	_sprite_mid(e.type + ("_head_open" if open else "_head"), e.pos, e.facing < 0, white, tint)

## A burrower under the ground: the ground over it heaves up in a moving mound (its own colour,
## lit on top, a crack of shadow under the lip), so you can always see where it is and where it goes.
## Over the spot it is about to burst from, the mound swells and shudders.
func _draw_mound(e) -> void:
	var up: Vector2 = e.pos.normalized()
	var p: Vector2 = e.pos
	var found := false
	for k in 48:
		if Defs.KIND[game.type_at(p + up)] == Defs.K_EMPTY:
			found = true
			break
		p += up
	if not found:
		return                         # (deep under: nothing shows on the surface)
	var sp: Vector2 = game.world_to_screen(p + up * 0.5)
	if sp.x < -30 or sp.y < -30 or sp.x > game.VW + 30 or sp.y > game.VH + 30:
		return
	var t := float(game.frame)
	var tell: bool = e.act == "windup" and e.move.begins_with("breach")
	var z: float = game.zoom
	var hw: float = (float(e.w) * 0.5 + 3.0) / z
	var hh: float = (2.4 + sin(t * 0.25) * 0.6 + (2.5 if tell else 0.0)) / z
	var jit := Vector2((randf() - 0.5) * 2.0, 0.0) if tell else Vector2.ZERO
	var base: Vector2 = _snap(sp) + jit
	var gt: int = game.type_at(p - up * 1.5)
	var col: Color = Defs.COLOR[gt] if Defs.KIND[gt] != Defs.K_EMPTY else Color(0.86, 0.74, 0.5)
	col = col * _lit(sp)
	col.a = 1.0
	var n := int(ceil(hw))
	for i in range(-n, n + 1):
		var f := float(i) / maxf(hw, 1.0)
		if absf(f) > 1.0:
			continue
		var h := roundf(hh * sqrt(1.0 - f * f))
		if h < 1.0:
			continue
		draw_rect(Rect2(base + Vector2(i, -h), Vector2(1, h)), col)
		draw_rect(Rect2(base + Vector2(i, -h), Vector2(1, 1)), col.lightened(0.25))
	# the crack along its foot
	draw_rect(Rect2(base + Vector2(-n, 0), Vector2(2 * n + 1, 1)), col.darkened(0.45))

## a picture centred on a world point (fliers and serpents, which have no feet to stand on)
func _sprite_mid(key: String, wpos: Vector2, flip: bool, white: bool, tint := Color(1, 1, 1)) -> void:
	if not tex.has(key):
		return
	var t: Texture2D = tex[key]
	var sp: Vector2 = game.world_to_screen(wpos)
	if sp.x < -80 or sp.y < -80 or sp.x > game.VW + 80 or sp.y > game.VH + 80:
		return
	var rot := 0.0 if game.close_view() else wrapf(atan2(game.cam_c.y, game.cam_c.x) - atan2(wpos.y, wpos.x), -PI, PI)
	var sc := Vector2(-1.0 if flip else 1.0, 1.0) / float(game.zoom)
	draw_set_transform(_snap(sp) if game.close_view() else sp, rot, sc)
	var mod := Color(4, 4, 4) if white else _lit(sp) * tint
	var ts := t.get_size()
	draw_texture(t, -(ts * 0.5).floor(), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _lit(sp: Vector2) -> Color:
	if game.space.active and not game.space.live:
		return Color(1, 1, 1)               # (out in space: full sun, and no light grid to read)
	var c: Color = game.gpu.light_at(game.screen_to_pic(sp))
	return Color(clampf(c.r, 0.12, 1.0), clampf(c.g, 0.12, 1.0), clampf(c.b, 0.12, 1.0))

## Where a body's feet are drawn on screen. Sprites hang from the feet, not the centre: a body
## standing on the ground has its feet snapped onto the same cell row as the ground under it,
## so it can't flicker a pixel up and down against the terrain while the camera eases (with
## an odd body height the centre sits right on a half pixel, and rounding it flipped back and
## forth). Returns [drawn position, unsnapped position].
func _feet(wpos: Vector2, body_h: float, grounded: bool, body_w := 0.0) -> Array:
	var up := wpos.normalized()
	var feet := wpos - up * (body_h * 0.5)
	var raw: Vector2 = game.world_to_screen(feet)
	if grounded:
		# on the top of the very cell it stands on, as the terrain draws it (the body rests on the collision
		# grid, which is laid out round you: its rows sit a fraction of a cell off the world's far out);
		# else to the nearest cell row (rows are whole numbers of radius: R_TOP is a whole number)
		var gt: float = game.ground_top(feet, body_w) if body_w > 0.0 else -1.0
		if gt > 0.0 and absf(gt - feet.length()) < 1.2:
			feet = up * gt
		else:
			feet = up * roundf(feet.length())
	var sp: Vector2 = game.world_to_screen(feet)
	if game.close_view() or absf(wrapf(atan2(game.cam_c.y, game.cam_c.x) - atan2(wpos.y, wpos.x), -PI, PI)) < 0.02:
		sp = _snap(sp)
	return [sp, raw]

## A point snapped to whole SCREEN pixels (the overlay draws in game pixels, `scale_px` screen pixels each).
## Sprites go here, not to whole game pixels: the ground under them is drawn a screen pixel at a time and
## turns a little as you walk (the view turns to the column you're on), so snapping a standing foe to the
## coarser game-pixel grid made it hop a whole cell up and down against the ground (user, 21 Nov).
func _snap(p: Vector2) -> Vector2:
	var k := float(game.scale_px)
	return (p * k).round() / k

func _sprite(key: String, wpos: Vector2, flip: bool, white: bool, body_h: float, grounded := false, alpha := 1.0, squash := 1.0, tint := Color(1, 1, 1), turn := false, body_w := 0.0) -> void:
	var t: Texture2D = tex[key]
	var sp: Vector2 = _feet(wpos, body_h, grounded, body_w)[0]
	# upright in the close view (crisp pixels: turned a few degrees they'd go jagged); turned with the
	# planet's curve in the round map view. `turn`: always turned with the world under it (an open door
	# stands with its house, which leans with the curve: upright it seemed to turn as you walked)
	var rot := 0.0 if game.close_view() else wrapf(atan2(game.cam_c.y, game.cam_c.x) - atan2(wpos.y, wpos.x), -PI, PI)
	if turn and game.close_view() and not game.unrolled():
		rot = wrapf(game.view_angle() - atan2(wpos.y, wpos.x), -PI, PI)
	var z: float = game.zoom
	var sc := Vector2((-1.0 if flip else 1.0) * (2.0 - squash), squash) / z
	draw_set_transform(sp, rot, sc)
	var mod := Color(4, 4, 4) if white else _lit(game.world_to_screen(wpos)) * tint
	mod.a = alpha
	# feet (the last opaque row above the outline) rest on the bottom of the body box, wherever they are in
	# the frame: a frame with empty rows under its feet (most of the grown creatures had one or two, a
	# small one four) stood that much over the ground (user, 21 Nov: "look more like their feet are on
	# the ground"); and a walk frame with a leg lifted lowers the body onto the other. (Not a door or chest,
	# `turn`: a door with its bottom burnt off still hangs where it hung.)
	var ts := t.get_size()
	draw_texture(t, Vector2(-floorf(ts.x * 0.5), -ts.y + 1.0 + (0.0 if turn else _gap_under(key, t))), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## how many empty rows a frame has under its lowest opaque row (its feet's outline), cached by key
func _gap_under(key: String, t: Texture2D) -> float:
	if _gaps.has(key):
		return _gaps[key]
	var gap := 0
	var img := t.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var hh := img.get_height()
		gap = hh
		for yy in range(hh - 1, -1, -1):
			var any := false
			for xx in w:
				if img.get_pixel(xx, yy).a > 0.5:
					any = true
					break
			if any:
				gap = hh - 1 - yy
				break
		if gap >= hh:
			gap = 0
	_gaps[key] = float(gap)
	return float(gap)

## A mage: the frame, plus the parts mage_rig.gd simulates (the scarf behind him; the hat's tip,
## the beard's end and the staff in front), all in the sprite's own pixels and transform.
## The rig keeps moving while he blinks invisible after a hit, so nothing jumps when he reappears.
func _draw_mage(m, aim_w: Vector2, gem: Color, visible_now: bool, place: Array = []) -> void:
	var key := _mage_frame(m)
	if m.rig == null:
		m.rig = MageRig.new()
	var a := atan2(m.pos.y, m.pos.x)
	if game.space.active:
		a = (m.pos - game.space.centre).angle()      # (out in space: upright over the nearest planet)
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
	var sp: Vector2 = _feet(m.pos, m.h, m.on_ground, m.w)[0]
	var rot := 0.0 if game.close_view() else wrapf((game.view_angle() if game.space.active else atan2(game.cam_c.y, game.cam_c.x)) - a, -PI, PI)
	# (out in space the view zooms far out: the mage stays big enough to see)
	var zs: float = minf(game.zoom, 2.0) if game.space.active else game.zoom
	var sc: Vector2 = Vector2(-1.0 if m.facing < 0 else 1.0, 1.0) / zs
	if not place.is_empty():
		# (seated in the skiff: placed and turned with it)
		sp = place[0]
		rot = place[1]
		sc = Vector2(-1.0 if m.facing < 0 else 1.0, 1.0) * float(place[2])
	draw_set_transform(sp, rot, sc)
	var mod := _lit(game.world_to_screen(m.pos))
	mod = mod.lerp(Color(0.86, 0.88, 0.95), clampf(m.fog, 0.0, 1.0) * 0.55)   # misted over inside a cloud
	var ts := t.get_size()
	var origin := Vector2(-floorf(ts.x * 0.5) + 1.0, -ts.y + 2.0)
	MageRig.draw_pixels(self, m.rig.back_pixels(), origin, 1.0, mod, _masks[key])
	draw_texture(t, Vector2(-floorf(ts.x * 0.5), -ts.y + 1.0), mod)
	MageRig.draw_pixels(self, m.rig.front_pixels(gem), origin, 1.0, mod, _masks[key])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## The skiff's body -> screen map: turned with its own frame, one body cell to one pixel at the
## view's zoom, like every sprite. (In the close view the terrain's columns are drawn a pixel each,
## and they widen with height, so a map taken straight from the world would stretch the ship as it
## climbs.) Out in space, where the view zooms far out, it's drawn bigger, like the mage.
func _skiff_xf(sk) -> Transform2D:
	var p: Vector2 = game.world_to_screen(sk.pos)
	var ex: Vector2 = game.world_to_screen(sk.pos + sk.axis_x()) - p
	var ey: Vector2 = game.world_to_screen(sk.pos + sk.axis_y()) - p
	var zs: float = minf(float(game.zoom), 2.0) if game.space.active else float(game.zoom)
	var xn := ex.normalized()
	var yn := Vector2(-xn.y, xn.x)
	if yn.dot(ey) < 0.0:
		yn = -yn                     # (the same way round as the world's own axes: mirrored when it is)
	# turning round, it narrows to its edge and opens out the other way
	var turn: float = sk.look * float(sk.facing)
	turn = signf(turn) * maxf(absf(turn), 0.08) if turn != 0.0 else 0.08
	return Transform2D(xn * turn / zs, yn / zs, p)

## The skiff, with its riders seated in it (drawn first: the hull hides their legs, the canopy
## is glass), turning and mirroring with it.
func _draw_skiff() -> void:
	var sk = game.skiff
	if sk == null:
		return
	if game.space.active and sk.pos.length() < Defs.R_SPACE - 9.5 and sk.pilot() == null:
		return                       # (left on the planet below: not drawn out in space)
	var xf := _skiff_xf(sk)
	var p := xf.origin
	if p.x < -200 or p.y < -200 or p.x > game.VW + 200 or p.y > game.VH + 200:
		return
	var rot := wrapf(xf.y.angle() - PI * 0.5, -PI, PI)
	# the cabin's back (glass, and whatever is built there), then whoever sits in it, then the hull
	draw_set_transform_matrix(xf)
	draw_texture(sk.back_texture(), -sk.com, _lit(p))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	for k in sk.riders.size():
		var m = sk.riders[k]
		if m == null or m.dead:
			continue
		var sc_cell: Vector2i = sk.seat_cells[k]
		var feet: Vector2 = xf * (Vector2(sc_cell.x + 0.5, sc_cell.y + 1.0) - sk.com)
		var gem: Color = Defs.SPELLS[game.known[game.sel]]["color"] if m == game.player else Color("#46e6f0")
		var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px) if m == game.player else m.input.aim
		_draw_mage(m, aim, gem, true, [feet, rot, xf.y.length()])
	draw_set_transform_matrix(xf)
	draw_texture(sk.texture(), -sk.com, _lit(p))
	draw_set_transform_matrix(Transform2D.IDENTITY)

## Out in space (space.gd draws the stars, the sun and the planets): just you, your wisp, the
## light streaming from the staff, and the reticle.
func _draw_in_space() -> void:
	for p in game.parts:
		_px(p["pos"], p["col"])
	var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
	if game.player.aboard == null:
		_draw_mage(game.player, aim, Defs.SPELLS[game.known[game.sel]]["color"], true)
	_draw_skiff()
	if game.ui.mouse_over_ui():
		return
	var m: Vector2 = (get_viewport().get_mouse_position() / game.scale_px).floor()
	var rc := Color(0.7, 0.9, 1.0, 0.7)
	for k in range(2, 5):
		draw_rect(Rect2(m + Vector2(k, 0), Vector2.ONE), rc)
		draw_rect(Rect2(m - Vector2(k, 0), Vector2.ONE), rc)
		draw_rect(Rect2(m + Vector2(0, k), Vector2.ONE), rc)
		draw_rect(Rect2(m - Vector2(0, k), Vector2.ONE), rc)

func _px(wpos: Vector2, col: Color) -> void:
	var sp: Vector2 = game.world_to_screen(wpos)
	draw_rect(Rect2(sp.floor(), Vector2.ONE), col)

func _draw() -> void:
	if game == null or game.state == "title" or game.state == "loading" or game.state == "error" or game.state == "map":
		return                       # (the map draws its own markers: map_view.gd)
	var t_draw := Time.get_ticks_usec()
	_draw_all()
	if not game.space.active:
		_draw_sky()
	game.prof_add("drawing sprites", Time.get_ticks_usec() - t_draw)

## a speech bubble over someone's head: a rounded box with a little tail, the words wrapped to a width
func _bubble(wpos: Vector2, text: String, alpha: float) -> void:
	var px: float = float(game.scale_px)
	var head: Vector2 = game.world_to_screen(wpos - game.basis_d(atan2(wpos.y, wpos.x)) * 13.0)
	var f: Font = PixelFont.make()
	var u: int = game.ui.U
	var sz := PixelFont.SIZE * u
	var maxw := 150.0 * u
	# wrap the words into lines no wider than maxw (in screen pixels)
	var lines := []
	var cur := ""
	for word in text.split(" "):
		var tryl := word if cur == "" else cur + " " + word
		if f.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > maxw and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = tryl
	if cur != "":
		lines.append(cur)
	var wmax := 0.0
	for ln in lines:
		wmax = maxf(wmax, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
	var lh := float(sz + u)
	var pad := 4.0 * u
	var bw := (wmax + pad * 2.0) / px
	var bh := (lh * lines.size() - u + pad * 2.0) / px
	var x0 := clampf(head.x - bw * 0.5, 2.0, float(game.VW) - bw - 2.0)
	var y0 := head.y - bh - 4.0 / px
	var bg := Color(0.98, 0.96, 0.9, 0.92 * alpha)
	var edge := Color(0.18, 0.14, 0.1, 0.9 * alpha)
	draw_rect(Rect2(x0 - 1.0 / px, y0 - 1.0 / px, bw + 2.0 / px, bh + 2.0 / px), edge)
	draw_rect(Rect2(x0, y0, bw, bh), bg)
	draw_colored_polygon(PackedVector2Array([Vector2(head.x - 3.0 / px * 2.0, y0 + bh), Vector2(head.x + 3.0 / px * 2.0, y0 + bh), Vector2(head.x, y0 + bh + 5.0 / px * 2.0)]), bg)
	draw_set_transform(Vector2(x0, y0), 0.0, Vector2.ONE / px)
	for li in lines.size():
		draw_string(f, Vector2(pad, pad + float(PixelFont.ASCENT * u) + li * lh), lines[li], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0.15, 0.11, 0.08, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## the sky events' own pictures (main `sky_fx`, `sky_wisps`): shooting stars, lightning bolts, rockets,
## will-o'-wisps, and a tint over the whole view (a sandstorm's haze, an eruption's glow)
func _draw_sky() -> void:
	var z: float = game.zoom
	for fx in game.sky_fx:
		match String(fx["kind"]):
			"streak":
				var a: Vector2 = game.world_to_screen(fx["pos"])
				var b: Vector2 = game.world_to_screen((fx["pos"] as Vector2) - (fx["vel"] as Vector2) * 3.0)
				var c: Color = fx["col"]
				var fl := clampf(float(fx["life"]) / 10.0, 0.0, 1.0)
				draw_line(b, a, Color(c.r, c.g, c.b, 0.25 * fl), 2.0)
				draw_line(b.lerp(a, 0.5), a, Color(c.r, c.g, c.b, 0.9 * fl), 1.0)
			"bolt":
				var spts := PackedVector2Array()
				for q in fx["pts"]:
					spts.append(game.world_to_screen(q))
				var la := float(fx["life"]) / 9.0
				draw_polyline(spts, Color(0.55, 0.7, 1.0, 0.35 * la), 3.0)
				draw_polyline(spts, Color(1.0, 1.0, 1.0, 0.95 * la), 1.0)
			"rocket":
				var rp: Vector2 = game.world_to_screen(fx["pos"])
				draw_rect(Rect2(rp.floor(), Vector2.ONE), Color(1.0, 0.92, 0.7))
	for w in game.sky_wisps:
		var wp: Vector2 = game.world_to_screen(w["pos"])
		var pul := 0.75 + 0.25 * sin(float(w["ph"]) * 3.0)
		draw_circle(wp, 3.5 / maxf(z, 0.5), Color(0.45, 0.8, 1.0, 0.18 * pul))
		draw_circle(wp, 1.8 / maxf(z, 0.5), Color(0.7, 0.92, 1.0, 0.5 * pul))
		draw_rect(Rect2(wp.floor(), Vector2.ONE), Color(1.0, 1.0, 1.0, 0.95))
	var t: Color = game.sky_tint
	if t.a > 0.003:
		draw_rect(Rect2(0, 0, game.VW, game.VH), t)

func _draw_all() -> void:
	var z: float = game.zoom
	if game.space.active and not game.space.live:
		_draw_in_space()
		return
	# the villagers (towns.gd), behind the chests so a chest in front of one is never hidden
	_draw_folk()
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
		_sprite("chest_open" if c.opened else "chest", c.pos, false, c.open_t > 50 and (c.open_t / 4) % 2 == 0, c.h, true, ch_a, ch_sq, Color(1, 1, 1), true)
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
		_sprite(dkey, game.door_panel_pos(d), swing < 0.0, false, float(d["h"]), true, 1.0, 1.0, Color(1, 1, 1), true)
	# foes
	# pieces breaking off: felled trees and fragments of buildings, turned as they tumble
	if game.chunks != null:
		for c in game.chunks.list:
			game.chunks.textures(c)
			if c.tex_f == null:
				continue
			var csp: Vector2 = game.world_to_screen(c.pos)
			var ref: float = atan2(c.pos.y, c.pos.x) if game.unrolled() else game.view_angle()
			draw_set_transform(csp, game.chunks.screen_angle(c, ref), Vector2.ONE / float(game.zoom))
			var cm := _lit(csp)
			draw_texture(c.tex_b, c.img_origin, cm)
			draw_texture(c.tex_f, c.img_origin, cm)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# what the villagers are saying (they're drawn before the chests: `_draw_folk`)
	for v2 in game.towns.folk:
		if v2.fade > 0:
			continue
		if v2.say_t > 0 and v2.say != "":
			_bubble(v2.pos, v2.say, clampf(float(v2.say_t) / 30.0, 0.0, 1.0))
		elif v2.keeper and (v2.pos as Vector2).distance_to(game.player.pos) < 60.0:
			_bubble(v2.pos, "%s · %s  [F]" % [v2.name, Defs.SHOPS[v2.role]["title"]], 0.75)
		else:
			_folk_mark(v2)

	_draw_carcasses()
	# (a foe winding up an attack glows hot and flickers: the tell; a leaper crouches)
	for e in game.enemies:
		var tl: float = FoeAI.tell(e)
		var tint := Color(1, 1, 1).lerp(Color(2.2, 0.75, 0.5), tl)
		var sq := 1.0 - 0.22 * tl if (e.type == "slime" or e.type == "mimic") else 1.0
		if e.d.has("def"):
			# a guardian: its frames grown from parts the first time it's seen
			_boss_art(e)
			var plan: String = e.d["def"]["body"]["plan"]
			if plan == "serpent":
				if e.under:
					_draw_mound(e)
				_draw_serpent(e, tint)
				continue
			if plan == "bird" and e.on_ground and not e.under:
				# (standing on the ground: feet on it, as the walkers)
				_sprite(_boss_frame(e), e.pos, e.facing < 0, e.flash > 0, e.h, true, 1.0, 1.0, tint, false, e.w)
				_eco_marks(e)
				continue
			if plan == "bird":
				_sprite_mid(_boss_frame(e), e.pos, e.facing < 0, e.flash > 0, tint)
				_eco_marks(e)
				continue
		_sprite(_foe_frame(e), e.pos, e.facing < 0, e.flash > 0, e.h, e.on_ground or e.off_t <= 3, 1.0, sq, tint, false, e.w)
		_eco_marks(e)
	# projectiles
	for pr in game.projs:
		if pr["type"] == "arrow":
			# a skeleton's arrow (user, 21 Nov: hard to see): a bone-pale shaft five cells long with red
			# fletching and a spectral green head and wake, which stay visible in the dark
			var av: Vector2 = pr["vel"]
			var ap: Vector2 = pr["pos"]
			var dn := av.normalized()
			var lc: Color = _lit(game.world_to_screen(ap))
			lc = Color(maxf(lc.r, 0.6), maxf(lc.g, 0.6), maxf(lc.b, 0.6))
			for k in 6:
				var q: Vector2 = game.world_to_screen(ap - dn * float(5 + k * 2)).floor()
				draw_rect(Rect2(q, Vector2.ONE), Color(0.45, 1.0, 0.5, 0.32 * (1.0 - float(k) / 6.0)))
			for k in 6:
				var q2: Vector2 = game.world_to_screen(ap - dn * float(k)).floor()
				var col2 := Color(0.93, 0.9, 0.8) * lc
				if k == 0:
					col2 = Color(0.55, 1.0, 0.45)
				elif k >= 4:
					col2 = Color(0.95, 0.3, 0.22) * lc
				draw_rect(Rect2(q2, Vector2.ONE), col2)
			var side: Vector2 = game.world_to_screen(ap - dn * 5.0 + dn.orthogonal() * 1.0).floor()
			draw_rect(Rect2(side, Vector2.ONE), Color(0.95, 0.3, 0.22) * lc)
			continue
		if Defs.SPELL_FX.has(pr["type"]):
			continue                  # (vfx.gd draws the spells, with their glow)
		var c: Color = Defs.SPELLS[pr["type"]]["color"] if Defs.SPELLS.has(pr["type"]) else Color(1, 0.35, 0.12)
		var sp: Vector2 = game.world_to_screen(pr["pos"])
		var big := 1 if pr["type"] == "fireball" or pr["type"] == "quake" else 0
		draw_rect(Rect2(sp.floor() - Vector2(big, big), Vector2(1 + 2 * big, 1 + 2 * big)), c)
		draw_rect(Rect2(sp.floor(), Vector2.ONE), Color(1, 1, 0.9))
	# build mode: what would go where, in its own colours (red where it doesn't fit)
	_draw_build_preview()
	# the mages, with their simulated hats, beards, scarves and staves
	for m in game.players:
		if m != game.player and not m.dead and m.aboard == null:
			_draw_mage(m, m.input.aim, Color("#46e6f0"), true)
	if not game.dead and game.player.aboard == null:
		var blink: bool = game.iframes > 0 and (game.iframes / 4) % 2 == 0
		var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
		_draw_mage(game.player, aim, Defs.SPELLS[game.known[game.sel]]["color"], not blink)
	# the skiff (over its riders: the hull hides their legs, the canopy is glass)
	_draw_skiff()
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

## over a villager: the asker's mark (towns.gd `mark_of`: a gold "!" for a request, a "?" for one under
## way, gold when it's done), or a sleeper's drifting "z"s. (The overlay draws in game pixels, `scale_px` screen
## pixels each, so text is drawn through a 1/px transform at its screen size.)
func _folk_mark(v) -> void:
	var mk: String = game.towns.mark_of(v)
	var a := atan2(v.pos.y, v.pos.x)
	var f: Font = PixelFont.make()
	var fb: Font = PixelFont.make(true)
	var px: float = float(game.scale_px)
	var u: int = game.ui.U
	if mk != "":
		var bob := sin(float(game.frame) * 0.08) * 1.2
		var hp: Vector2 = game.world_to_screen(v.pos - game.basis_d(a) * (13.0 + bob))
		var ch := "!" if mk == "offer" else "?"
		var col := Color(0.62, 0.62, 0.68) if mk == "wait" else Color(1.0, 0.82, 0.25)
		var fs := PixelFont.SIZE * 2 * u
		var sz := fb.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_set_transform(hp.round(), 0.0, Vector2.ONE / px)
		var at := Vector2(-roundf(sz.x * 0.5 / u) * u, 0.0)
		for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
			draw_string(fb, at + o * u, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.06, 0.02))
		draw_string(fb, at, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif not v.asleep and v.fade == 0 and (v.pos as Vector2).distance_to(game.player.pos) < 45.0 and game.towns.knows(v):
		# someone you've met: their name over their head
		var np: Vector2 = game.world_to_screen(v.pos - game.basis_d(a) * 11.5)
		var nfs := PixelFont.SIZE * u
		var nsz := f.get_string_size(v.name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
		draw_set_transform(np.round(), 0.0, Vector2.ONE / px)
		var nat := Vector2(-roundf(nsz.x * 0.5 / u) * u, 0.0)
		for o in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(f, nat + o * u, v.name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(0.08, 0.05, 0.03, 0.8))
		draw_string(f, nat, v.name, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, Color(0.98, 0.93, 0.8, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif v.asleep:
		for k in 3:
			var ph := fposmod(float(game.frame) * 0.01 + float(k) / 3.0, 1.0)
			var zb: Vector2 = v.lie_head if v.lying else v.pos
			var zp: Vector2 = game.world_to_screen(zb - game.basis_d(a) * ((3.0 if v.lying else 9.0) + ph * 9.0) + game.basis_r(a) * (1.0 + ph * 4.0))
			draw_set_transform(zp.round(), 0.0, Vector2.ONE / px)
			draw_string(fb, Vector2.ZERO, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE * u * (1 if ph < 0.5 else 2), Color(0.85, 0.9, 1.0, sin(ph * PI) * 0.8))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## a villager asleep: the figure turned a quarter (still whole pixels) with its head toward the pillow, on
## a bedroll if there's no bed for them, the blanket pulled up to the chin
func _lying(v, t: Texture2D) -> void:
	var c: Vector2 = _snap(game.world_to_screen(v.pos))
	var hs: Vector2 = game.world_to_screen(v.lie_head)
	var head_right: bool = hs.x > c.x
	var z: float = game.zoom
	var mod := _lit(c)
	mod.a = game.towns.alpha_of(v)
	var ts := t.get_size()
	if v.bedroll:
		# a rolled-out blanket under them, in a colour from their seed
		var bc := Color.from_hsv(fposmod(float(v.fseed % 97) / 97.0, 1.0), 0.45, 0.55) * mod
		bc.a = mod.a
		draw_set_transform(c, 0.0, Vector2.ONE / z)
		draw_rect(Rect2(-ts.y * 0.5 - 1.0, ts.x * 0.5 - 4.0, ts.y + 2.0, 3.0), bc)
		draw_rect(Rect2(-ts.y * 0.5 - 1.0, ts.x * 0.5 - 1.0, ts.y + 2.0, 1.0), bc.darkened(0.35))
	draw_set_transform(c, PI * 0.5 if head_right else -PI * 0.5, Vector2.ONE / z)
	draw_texture(t, -(ts * 0.5).floor(), mod)
	# a quilt over the body from the shoulders down (just the body's width), its own colour, edged and
	# folded back at the top, with a stripe
	var bl := Color.from_hsv(fposmod(float(v.fseed % 89) / 89.0 + 0.3, 1.0), 0.55, 0.78) * mod
	bl.a = mod.a
	var ed := bl.darkened(0.45)
	var qx := -4.0
	var qy := -floorf(ts.y * 0.5) + 8.0
	var qh := ts.y - 9.0
	draw_rect(Rect2(qx - 1.0, qy, 10.0, qh + 1.0), ed)
	draw_rect(Rect2(qx, qy, 8.0, qh), bl)
	draw_rect(Rect2(qx, qy, 8.0, 2.0), bl.lightened(0.35))
	draw_rect(Rect2(qx, qy + floorf(qh * 0.55), 8.0, 1.0), bl.darkened(0.2))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## the villagers (towns.gd): walking, standing, or asleep lying down
func _draw_folk() -> void:
	for v in game.towns.folk:
		var vsp: Vector2 = game.world_to_screen(v.pos)
		if vsp.x < -30 or vsp.y < -40 or vsp.x > game.VW + 30 or vsp.y > game.VH + 40:
			continue
		var fk := "folk_%d" % v.fseed
		if not tex.has(fk + "_stand"):
			var fr: Dictionary = FolkArt.frames(v.fseed, v.role)
			for fn in fr:
				tex[fk + "_" + fn] = ImageTexture.create_from_image(fr[fn])
		if v.lying:
			_lying(v, tex[fk + "_stand"])
			continue
		var walking: bool = absf(v.vx) > 0.08
		var frn := ("_walk%d" % (int(v.anim) % 2)) if walking else "_stand"
		_sprite(fk + frn, v.pos, v.facing < 0, false, v.h, v.on_ground, game.towns.alpha_of(v), 1.0, Color(1, 1, 1), false, v.w)
