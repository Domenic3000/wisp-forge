extends Node2D

const MysteryArt := preload("res://scripts/mystery.gd")
const WorkshopArt := preload("res://scripts/workshop_art.gd")
const FoeAI := preload("res://scripts/foe_ai.gd")
## Draws everything that isn't terrain, in screen pixels on top of the GPU
## picture: the mage, the wisp, foes, spells, particles and the reticle.

const MageRig := preload("res://scripts/mage_rig.gd")
const BossArt := preload("res://scripts/boss_art.gd")
const FolkArt := preload("res://scripts/folk_art.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Speech := preload("res://scripts/speech.gd")
const Ecology := preload("res://scripts/ecology.gd")

var _art_jobs := {}         # foe type -> [worker task, {"fr", "gaps"}] (`_boss_art`)
var _gaps := {}             # empty rows under each sprite frame's feet (`_gap_under`)
var game
var tex := {}
var _door_keys := []          # pictures of damaged open doors made so far (oldest first)
var _masks := {}
var _boss_made := {}          # guardians whose frames have been grown (boss_art.gd), by type

func _ready() -> void:
	for k in Defs.SPRITES:
		tex[k] = Defs.sprite_texture(k)
		# (empty rows under the lowest drawn row: the outline takes one of them)
		var srows: Array = Defs.SPRITES[k]["rows"]
		var last := -1
		for sy in srows.size():
			if String(srows[sy]).replace(".", "") != "":
				last = sy
		_gaps[k] = float(maxi(0, srows.size() - 1 - last)) if last >= 0 else 0.0
	# a bat asleep under a cave roof: its first frame upside down
	var bh: Image = tex["bat1"].get_image()
	bh.flip_y()
	_make_tex("bat_hang", bh)
	tex["door_open_30"] = ImageTexture.create_from_image(_door_open_image(30))

## The summoned forge beside you (main `forge_at`, `forge_vis`): it rises out of the ground as it comes and
## sinks as it fades, its violet flame flickering on its own clock (`forge_t`)
func _draw_forge() -> void:
	if game.forge_vis <= 0.0:
		return
	if not tex.has("_spirit"):
		var fr: Dictionary = WorkshopArt.spirit_forge()
		_make_tex("_spirit", fr["body"])
		_make_tex("_spirit_f0", fr["fire0"])
		_make_tex("_spirit_f1", fr["fire1"])
	var v: float = game.forge_vis
	var rise := v * v * (3.0 - 2.0 * v)
	var z: float = game.zoom
	var up: Vector2 = game.view_up()
	var base: Vector2 = game.forge_at - up * (1.0 - rise) * 10.0 + up * sin(float(game.forge_t + game.frame) * 0.05) * 0.6
	var sp: Vector2 = game.world_to_screen(base)
	var t: Texture2D = tex["_spirit"]
	var ts := t.get_size()
	draw_set_transform(sp, 0.0, Vector2.ONE / z)
	var at := Vector2(-floorf(ts.x * 0.5), -ts.y + 1.0)
	draw_texture(t, at, Color(1, 1, 1, rise))
	var fk := "_spirit_f%d" % ((int(game.forge_t + game.frame) / 5) % 2)
	draw_texture(tex[fk], at, Color(1.2, 1.15, 1.3, rise * (0.75 + 0.25 * sin(float(game.forge_t) * 0.3))))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Pages flying into your book as you learn recipes (main `pages`): a little parchment page turning over as it
## flies down to your satchel, then the book there a moment, its clasp glinting, fading away
func _draw_pages() -> void:
	if game.pages.is_empty() or game.player == null:
		return
	var z: float = game.zoom
	var m = game.player
	var up: Vector2 = game.view_up()
	var right: Vector2 = Vector2(-up.y, up.x)
	var book: Vector2 = m.pos + right * float(m.facing) * 4.0 - up * 1.0
	var c := 1.0 / z
	for pg in game.pages:
		var t := int(pg[1])
		if t < 0:
			continue
		if t < game.PAGE_FLY:
			var f := float(t) / float(game.PAGE_FLY)
			var e := f * f * (3.0 - 2.0 * f)
			var wp: Vector2 = (pg[0] as Vector2).lerp(book, e) + up * sin(f * PI) * 8.0
			var sp: Vector2 = game.world_to_screen(wp)
			var flip := absf(cos(float(t) * 0.35))
			var pw := maxf(1.0, roundf(4.0 * flip))
			var o := (sp - Vector2(pw * 0.5, 2.5) * c).floor()
			draw_rect(Rect2(o - Vector2.ONE * c, Vector2(pw + 2.0, 7.0) * c), Color(0.9, 0.95, 1.0, 0.18))
			draw_rect(Rect2(o, Vector2(pw, 5.0) * c), Color(0.93, 0.86, 0.66))
			if pw >= 3.0:
				draw_rect(Rect2(o + Vector2(1, 1) * c, Vector2(pw - 2.0, 1.0) * c), Color(0.35, 0.25, 0.15, 0.8))
				draw_rect(Rect2(o + Vector2(1, 3) * c, Vector2(pw - 2.0, 1.0) * c), Color(0.35, 0.25, 0.15, 0.6))
		else:
			var a := 1.0 - float(t - game.PAGE_FLY) / float(game.PAGE_BOOK)
			var bs: Vector2 = game.world_to_screen(book)
			var bo := (bs - Vector2(2.5, 2.0) * c).floor()
			draw_rect(Rect2(bo - Vector2.ONE * c, Vector2(7, 6) * c), Color(0.08, 0.05, 0.03, 0.8 * a))
			draw_rect(Rect2(bo, Vector2(5, 4) * c), Color(0.45, 0.2, 0.18, a))
			draw_rect(Rect2(bo, Vector2(1, 4) * c), Color(0.3, 0.12, 0.1, a))
			draw_rect(Rect2(bo + Vector2(3, 1) * c, Vector2(2, 2) * c), Color(1.0, 0.85, 0.4, a))

## What's in your hand, carried out in front of the mage while Conjure is held (user, 25 Nov; held in his
## hand, not floating over his head, 26 Nov): mage_rig.gd draws it (`carry`) with his near arm; here is what it
## is and its colours, or {} when nothing is carried.
func _carry_of(m) -> Dictionary:
	if m != game.player or game.build_on or m.dead or m.aboard != null or not game.conjuring(m) or game.hand_name() == "":
		return {}
	if game.hand_item.is_empty():
		var mt: int = game.mat
		var base := Color(0, 0, 0)
		for k in 4:
			base += Color.hex((Defs.PAL[mt * 4 + k] << 8) | 0xff) * 0.25
		base.a = 1.0
		var kind := "solid"
		if mt == Defs.TORCH:
			kind = "torch"
		elif mt == Defs.WOODDOOR:
			kind = "door"
		elif Defs.KIND[mt] == Defs.K_POWDER:
			kind = "powder"
		elif Defs.KIND[mt] == Defs.K_LIQUID or Defs.KIND[mt] == Defs.K_GAS:
			kind = "liquid"
		return {"kind": kind, "cols": [base.lightened(0.28), base, base.darkened(0.32)]}
	if String(game.hand_item["what"]) == "plan":
		return {"kind": "plan", "cols": []}
	var pc := Color(0.85, 0.62, 0.38) if String(game.hand_item["what"]) == "station" else Color(0.72, 0.5, 0.3)
	return {"kind": "piece", "cols": [pc.lightened(0.25), pc, pc.darkened(0.3)]}

## (the old floating block is gone: the mage carries it, `_carry_of`)
func _draw_hand() -> void:
	pass

## "+3 Sand" rising from where it was dug, fading (main `popups`)
func _draw_popups() -> void:
	if game.popups.is_empty():
		return
	var f: Font = PixelFont.make()
	var px: float = float(game.scale_px)
	var u: int = game.ui.U
	var fs := PixelFont.SIZE * u
	for pu in game.popups:
		var t := int(pu[3])
		var age := float(70 - t)                 # (main POPUP_TICKS)
		var wp: Vector2 = pu[0]
		var sp: Vector2 = game.world_to_screen(wp + wp.normalized() * age * 0.12)
		var col: Color = pu[2]
		col = col.lightened(0.25)
		col.a = clampf(float(t) / 20.0, 0.0, 1.0) * clampf(age / 6.0, 0.0, 1.0)
		var txt: String = pu[1]
		var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_set_transform(sp.round(), 0.0, Vector2.ONE / px)
		var at := Vector2(-roundf(sz.x * 0.5 / u) * u, 0.0)
		for o2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			draw_string(f, at + o2 * u, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.06, 0.04, 0.08, col.a * 0.85))
		draw_string(f, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

const HAND_COL := Color(0.45, 0.85, 1.0)   # (vfx MANA_COL: the hand's ghost is drawn in the staff's light)

func _draw_build_preview() -> void:
	if (not game.build_on and not game.hand_live) or game.build_prev.is_empty():
		return
	var pv: Dictionary = game.build_prev
	var ok: bool = pv.get("ok", false)
	var z: float = game.zoom
	var hand: bool = not game.build_on
	var pulse := 0.55 + 0.2 * sin(float(game.frame) * 0.15)
	var mid := Vector2.ZERO
	var nmid := 0
	for c in pv.get("cells", []):
		var sp: Vector2 = game.world_to_screen(c[0])
		var col: Color = c[1]
		if not ok:
			col = col.lerp(Color(1, 0.2, 0.15), 0.6)
		elif hand:
			col = col.lightened(0.15).lerp(HAND_COL, 0.25)
		col.a = minf(1.0, pulse + (0.15 if hand else 0.0))
		draw_rect(Rect2(sp - Vector2(0.5, 0.5) / z, Vector2.ONE / z), col)
		if nmid < 400:
			mid += c[0]
			nmid += 1
	if hand and game.player.aboard == null:
		# (user, 25 Nov: "the preview drawn as a faint outline in mana-blue light off the staff tip")
		var to: Vector2 = (mid / nmid) if nmid > 0 else (pv["circle"][0] if pv.has("circle") else Vector2.ZERO)
		if to != Vector2.ZERO:
			var tip: Vector2 = game._staff(game.player, to)[0]
			var a0: Vector2 = game.world_to_screen(tip)
			var a1: Vector2 = game.world_to_screen(to)
			var n := int(a0.distance_to(a1) / 3.0)
			var lc := HAND_COL if ok else Color(1, 0.4, 0.35)
			for k in n:
				var f := (float(k) + fposmod(float(game.frame) * 0.15, 1.0)) / maxf(n, 1)
				lc.a = 0.35 * (1.0 - absf(f - 0.5))
				draw_rect(Rect2((a0.lerp(a1, f)).floor(), Vector2.ONE), lc)
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
	# (6 wide: swung open, the panel is seen at a slant, so it takes little room beside its doorway;
	# user, 23 Nov: doors took up a lot of space and got in the way of building)
	var w := 6
	var img := Image.create(w, h + 1, false, Image.FORMAT_RGBA8)   # an empty last row, like the sprites' outline
	var dk := Color("#3a2412")
	var md := Color("#6b4423")
	var lt := Color("#8f5f33")
	var hl := Color("#a8743e")
	var ir := Color("#50505a")
	var irl := Color("#8a8a96")
	for x in w:
		for y in h:
			var c := lt if (x % 2) != 0 else md
			if x == 1:
				c = hl
			if (y * 7 + x * 3) % 13 == 0:
				c = md                                   # grain
			if y == 4 or y == 5 or y == h - 6 or y == h - 5:
				c = ir
				if (y == 4 or y == h - 6) and x % 2 == 1:
					c = irl                              # rivets
			if y >= 8 and y <= 11 and x >= 2 and x <= 3:
				c = Color("#141018") if not (y == 10) else ir    # the barred window
			if x == 0 or x == w - 1 or y == 0 or y == h - 1:
				c = dk
			img.set_pixel(x, y, c)
	img.set_pixel(w - 2, h / 2, Color("#e2b048"))
	img.set_pixel(w - 2, h / 2 + 1, Color("#9a6c24"))
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
			draw_string(fb, Vector2.ZERO, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE * u, Color(0.85, 0.9, 1.0, sin(ph * PI) * 0.7 * _lit(zp).a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## Ore Sense (the quest's gift for the skiff): the ore the wisp's last pulse found, drawn over rock and fog as a
## wave spreads from where it pulsed, then fading. Each ore cell a pixel of its own colour with a faint halo.
## the resonance pillars' glyphs over them: dim, lit (rung in turn, or all once the song is sung), or a red
## flash for a wrong note
func _draw_mystery() -> void:
	var md: Dictionary = game.mystery.data()
	var view := Rect2(-12.0, -12.0, float(game.VW) + 24.0, float(game.VH) + 24.0)
	var pil: Array = md.get("pillars", [])
	for k in pil.size():
		var pw: Vector2 = pil[k]["pos"]
		var sp: Vector2 = game.world_to_screen(pw - game.basis_d(atan2(pw.y, pw.x)) * 31.0)
		if not view.has_point(sp):
			continue
		var col := Color(0.45, 0.55, 0.75, 0.55)
		if game.mystery.flash.has(k):
			col = Color(1.0, 0.35, 0.3, 0.9)
		elif game.mystery.lit.has(k):
			var pulse := 0.8 + 0.2 * sin(float(game.frame) * 0.1 + float(k))
			col = Color(0.6 * pulse, 0.95 * pulse, 1.0, 1.0)
			for q in 10:
				var a := float(q) / 10.0 * TAU + float(game.frame) * 0.02
				draw_rect(Rect2((sp + Vector2(cos(a), sin(a)) * 7.0).floor(), Vector2.ONE), Color(0.6, 0.9, 1.0, 0.4))
		_glyph(sp, int(pil[k]["glyph"]), col)
	# a gas giant's beacons: a flame in each basin that burns (mystery.gd `burn`), and the Eye's braziers that
	# answer them
	var bcs: Array = md.get("beacons", [])
	var ech: Array = md.get("echoes", [])
	var solved := bool(game.mystery.st.get("solved", false))
	for k2 in bcs.size():
		if not (solved or game.mystery.burn.has(k2)):
			continue
		_flame(game.world_to_screen(bcs[k2]["pos"]), 1.0, k2, view)
		if k2 < ech.size():
			_flame(game.world_to_screen(ech[k2]), 0.6, k2 + 7, view)

## a pixel flame standing on screen point sp (s: its size), flickering
func _flame(sp: Vector2, s: float, fseed: int, view: Rect2) -> void:
	if not view.has_point(sp):
		return
	var t := float(game.frame) * 0.25 + float(fseed) * 1.7
	var hgt := (7.0 + 2.0 * sin(t) + randf()) * s
	var base := sp.floor()
	for y in int(hgt):
		var f := float(y) / maxf(hgt, 1.0)
		var wv := maxf(1.0, (3.5 * s) * (1.0 - f * 0.85))
		var sway := sin(t * 1.3 + f * 3.0) * f * 1.5 * s
		var col := Color(1.0, 0.95, 0.6).lerp(Color(1.0, 0.45, 0.15), f)
		col.a = 1.0 - f * 0.4
		draw_rect(Rect2((base + Vector2(-wv * 0.5 + sway, -1.0 - float(y))).floor(), Vector2(ceil(wv), 1.0)), col)

func _glyph(sp: Vector2, g: int, col: Color) -> void:
	var art: Array = MysteryArt.GLYPH_ART[g]
	var o := (sp - Vector2(3.5, 3.5)).floor()
	for y in 7:
		var line: String = art[y]
		for x in 7:
			if line[x] == "#":
				draw_rect(Rect2(o + Vector2(x, y), Vector2.ONE), col)

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
		mod.a = clampf(float(cc["t"]) / 300.0, 0.0, 1.0) * _lit(sp).a
		# (flipped top to bottom: its back on the ground, the empty margin over its head sunk into it)
		draw_set_transform(_snap(sp), 0.0, Vector2(-1.0 if int(cc["facing"]) < 0 else 1.0, -1.0) / z)
		draw_texture(t, Vector2(-floorf(ts.x * 0.5), -floorf(ts.y - float(cc["h"]) - 3.0)), mod)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## a guardian's frame for what it's doing (boss_art.gd names them)
func _boss_frame(e) -> String:
	var id: String = e.type
	var plan: String = e.d["def"]["body"]["plan"]
	if e.asleep and plan != "serpent":
		# (asleep, it shows its sleep, never a move it was in the middle of: user, 22 Nov, birds frozen in
		# their attack until woken)
		if tex.has(id + "_sleep"):
			return id + "_sleep"
		if e.pose != "" and tex.has(id + "_" + e.pose):
			return id + "_" + e.pose
		return id if plan != "bird" else "%s_fly0" % id
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

## A creature's, guardian's or warden's frames, grown from parts on a worker thread the first time one is
## in the list of foes: true once they're made. (Grown all at once on the main thread as the planet's
## guardians and wardens were first drawn, the first frame took 750 ms: user, 21 Nov, "a hitch on start up".)
func _boss_art(e) -> bool:
	if _boss_made.has(e.type):
		return true
	if not _art_jobs.has(e.type):
		var box := {}
		var typ: String = e.type
		var body: Dictionary = e.d["def"]["body"]
		var tid := WorkerThreadPool.add_task(func():
			var fr: Dictionary = BossArt.frames(typ, body)
			var gp := {}
			for fk in fr:
				gp[fk] = _image_gap(fr[fk])
			box["fr"] = fr
			box["gaps"] = gp)
		_art_jobs[e.type] = [tid, box]
		return false
	var job: Array = _art_jobs[e.type]
	if not WorkerThreadPool.is_task_completed(int(job[0])):
		return false
	WorkerThreadPool.wait_for_task_completion(int(job[0]))
	var bx: Dictionary = job[1]
	var frs: Dictionary = bx.get("fr", {})
	for k in frs:
		tex[k] = ImageTexture.create_from_image(frs[k])
		_gaps[k] = bx["gaps"][k]
	_art_jobs.erase(e.type)
	_boss_made[e.type] = true
	return true

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
	if white:
		mod.a = _lit(sp).a
	var ts := t.get_size()
	draw_texture(t, -(ts * 0.5).floor(), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _lit(sp: Vector2) -> Color:
	if game.pocket.active:
		return Color(1, 0.97, 1.0)          # (the pocket's soft, even light)
	if game.space.active and not game.space.live:
		return Color(1, 1, 1)               # (out in space: full sun, and no light grid to read)
	var c: Color = game.gpu.light_at(game.screen_to_pic(sp))
	# (in the fog over the unseen underground a creature is as hidden as the ground round it)
	var f := 0.04 + 0.96 * c.a
	# (deep in the fog it's gone altogether, not a dark shape against the mist: user, 22 Nov, "I can see
	# enemies under the fog of war")
	var fa := clampf((c.a - 0.12) / 0.35, 0.0, 1.0)
	return Color(clampf(c.r, 0.12, 1.0) * f, clampf(c.g, 0.12, 1.0) * f, clampf(c.b, 0.12, 1.0) * f, fa)

## Where a body's feet are drawn on screen. Sprites hang from the feet, not the centre: a body
## standing on the ground has its feet snapped onto the same cell row as the ground under it,
## so it can't flicker a pixel up and down against the terrain while the camera eases (with
## an odd body height the centre sits right on a half pixel, and rounding it flipped back and
## forth). Returns [drawn position, unsnapped position].
func _feet(wpos: Vector2, body_h: float, grounded: bool, body_w := 0.0) -> Array:
	var up := wpos.normalized()
	if game.pocket.active:
		up = Vector2(0, -1)                  # (the pocket's isle: its up is the screen's)
		grounded = false
	elif game.space.active:
		# (out in space "up" is away from space.centre: the nearest planet, or under a station's floor; and
		# there's no planet's ground to stand the feet on)
		up = (wpos - game.space.centre).normalized()
		grounded = false
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

func _sprite(key: String, wpos: Vector2, flip: bool, white: bool, body_h: float, grounded := false, alpha := 1.0, squash := 1.0, tint := Color(1, 1, 1), turn := false, body_w := 0.0, glow := false) -> void:
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
	var lc: Color = Color(1, 1, 1) if glow else _lit(game.world_to_screen(wpos))
	var mod := Color(4, 4, 4) if white else (tint if glow else lc * tint)
	mod.a = alpha * lc.a
	# feet (the last opaque row above the outline) rest on the bottom of the body box, wherever they are in
	# the frame: a frame with empty rows under its feet (most of the grown creatures had one or two, a
	# small one four) stood that much over the ground (user, 21 Nov: "look more like their feet are on
	# the ground"); and a walk frame with a leg lifted lowers the body onto the other. (Not a door or chest,
	# `turn`: a door with its bottom burnt off still hangs where it hung.)
	var ts := t.get_size()
	draw_texture(t, Vector2(-floorf(ts.x * 0.5), -ts.y + 1.0 + (0.0 if turn else _gap_under(key, t))), mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## how many empty rows a frame has under its lowest opaque row (its feet's outline), cached by key: worked
## out from the Image as each texture is made (`_make_tex`). (Read back from a texture as it was first
## drawn, each one stalled the renderer: arriving on a planet full of new creatures took a 280 ms frame.)
func _gap_under(key: String, t: Texture2D) -> float:
	if not _gaps.has(key):
		_gaps[key] = _image_gap(t.get_image())
	return _gaps[key]

func _make_tex(key: String, img: Image) -> void:
	tex[key] = ImageTexture.create_from_image(img)
	_gaps[key] = _image_gap(img)

static func _image_gap(img: Image) -> float:
	if img == null:
		return 0.0
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var hh := img.get_height()
	for yy in range(hh - 1, -1, -1):
		for xx in w:
			if img.get_pixel(xx, yy).a > 0.5:
				return float(hh - 1 - yy)
	return 0.0

## A mage: the frame, plus the parts mage_rig.gd simulates (the scarf behind him; the hat's tip,
## the beard's end and the staff in front), all in the sprite's own pixels and transform.
## The rig keeps moving while he blinks invisible after a hit, so nothing jumps when he reappears.
func _draw_mage(m, aim_w: Vector2, gem: Color, visible_now: bool, place: Array = []) -> void:
	var key := _mage_frame(m)
	if m.rig == null:
		m.rig = MageRig.new()
	var a := atan2(m.pos.y, m.pos.x)
	if game.pocket.active:
		a = -PI * 0.5
	elif game.space.active:
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
	# (out in space, zoomed out by hand: true to scale up to 4x, then held there so you can still find him)
	var zs: float = minf(game.zoom, 4.0) if game.space.active else game.zoom
	var sc: Vector2 = Vector2(-1.0 if m.facing < 0 else 1.0, 1.0) / zs
	if not place.is_empty():
		# (seated in the skiff: placed and turned with it)
		sp = place[0]
		rot = place[1]
		sc = Vector2(-1.0 if m.facing < 0 else 1.0, 1.0) * float(place[2])
	draw_set_transform(sp, rot, sc)
	var mod := _lit(game.world_to_screen(m.pos))
	mod.a = 1.0                                  # (a mage is always seen)
	mod = mod.lerp(Color(0.86, 0.88, 0.95), clampf(m.fog, 0.0, 1.0) * 0.55)   # misted over inside a cloud
	var ts := t.get_size()
	var origin := Vector2(-floorf(ts.x * 0.5) + 1.0, -ts.y + 2.0)
	MageRig.draw_pixels(self, m.rig.back_pixels(), origin, 1.0, mod, _masks[key])
	draw_texture(t, Vector2(-floorf(ts.x * 0.5), -ts.y + 1.0), mod)
	m.rig.carry = _carry_of(m)
	var cm: Vector2 = m.rig.carry_mid()
	if cm.is_finite():
		# a faint glow of the staff's light round what's carried (it rests on mana over his palm)
		var glow := HAND_COL
		glow.a = (0.07 + 0.03 * sin(float(game.frame) * 0.1)) * mod.a
		# (two crossed rects, so it's round-cornered and brightest in the middle, not a hard square)
		draw_rect(Rect2(origin + cm - Vector2(3, 4), Vector2(6, 8)), glow)
		draw_rect(Rect2(origin + cm - Vector2(4, 3), Vector2(8, 6)), glow)
	MageRig.draw_pixels(self, m.rig.front_pixels(_gem_now(m, gem)), origin, 1.0, mod, _masks[key])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## (user, 25 Nov: "the staff's gem shows your mana, dimming as it drains and flaring when full"): the crystal's
## colour dims toward dark glass as mana runs low, and flashes white for a moment as it fills up again
var _gem_was := {}       # mage id -> [mana fraction last drawn, frame it last filled]
var stats_gem_flares := 0
func _gem_now(m, gem: Color) -> Color:
	var mf := clampf(m.mana / maxf(1.0, m.max_mana), 0.0, 1.0)
	var id: int = m.get_instance_id()
	var was: Array = _gem_was.get(id, [mf, -1000])
	if mf >= 0.999 and float(was[0]) < 0.999:
		was[1] = game.frame
		stats_gem_flares += 1
	was[0] = mf
	_gem_was[id] = was
	var c := gem.lerp(Color(0.12, 0.1, 0.18), 0.7 * (1.0 - mf) * (1.0 - mf) + 0.15 * (1.0 - mf))
	var since: int = int(game.frame) - int(was[1])
	if since < 24:
		c = c.lerp(Color(1, 1, 1), 0.8 * (1.0 - float(since) / 24.0))
	return c

## The skiff's body -> screen map: turned with its own frame, one body cell to one pixel at the
## view's zoom, like every sprite. (In the close view the terrain's columns are drawn a pixel each,
## and they widen with height, so a map taken straight from the world would stretch the ship as it
## climbs.) Out in space, zoomed out past 4x, it's held at its 4x size, like the mage.
func _skiff_xf(sk) -> Transform2D:
	var p: Vector2 = game.world_to_screen(sk.pos)
	var ex: Vector2 = game.world_to_screen(sk.pos + sk.axis_x()) - p
	var ey: Vector2 = game.world_to_screen(sk.pos + sk.axis_y()) - p
	var zs: float = minf(float(game.zoom), 4.0) if game.space.active else float(game.zoom)
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
## a crate of trade goods (7 x 6 cells): planks, iron corners, a band of the good's colour, stencilled
var _crates := {}
func _crate_tex(gd: String) -> ImageTexture:
	if _crates.has(gd):
		return _crates[gd]
	var im := Image.create(7, 6, false, Image.FORMAT_RGBA8)
	var wood := Color(0.55, 0.38, 0.22)
	var dark := Color(0.3, 0.19, 0.1)
	# (a courier job's sealed crate: gold bands)
	var col: Color = Defs.GOODS[gd]["col"] if Defs.GOODS.has(gd) else Color(0.95, 0.78, 0.3)
	for y in 6:
		for x in 7:
			var c := wood.darkened(0.12) if y % 2 == 1 else wood
			if x == 0 or y == 0 or x == 6 or y == 5:
				c = dark
			if y == 2 or y == 3:
				c = col if (x > 0 and x < 6) else dark
			im.set_pixel(x, y, c)
	for q in [Vector2i(0, 0), Vector2i(6, 0), Vector2i(0, 5), Vector2i(6, 5)]:
		im.set_pixel(q.x, q.y, Color(0.42, 0.44, 0.5))
	im.set_pixel(3, 2, col.lightened(0.45))
	var t := ImageTexture.create_from_image(im)
	_crates[gd] = t
	return t

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
	draw_texture(sk.back_texture(), -sk.com, Color(_lit(p), 1.0))
	# the hold's crates (trade goods), stacked away from the helm
	var cargo_ids := []
	var cargo: Dictionary = game.items.get("cargo", {})
	var gkeys: Array = cargo.keys()
	gkeys.sort()
	for gd in gkeys:
		for cn in int(cargo.get(gd, 0)):
			cargo_ids.append(gd)
	if not cargo_ids.is_empty():
		var slots: Array = sk.crate_slots(cargo_ids.size())
		for ck in slots.size():
			var at: Vector2i = slots[ck]
			draw_texture(_crate_tex(String(cargo_ids[ck])), Vector2(at) - sk.com, Color(_lit(p), 1.0))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# (seated riders aren't drawn: they're inside the ship; user, 25 Nov, "when you enter the ship i want the player
	# model to go away so it looks like your inside the ship". Up and about on the deck (X), you're seen.)
	# whoever's up and about on its deck (behind the hull too: it's their floor and walls)
	for m2 in game.players:
		if m2.aboard != sk or not m2.deck or m2.dead:
			continue
		var feet2: Vector2 = xf * (m2.deck_b + Vector2(0.0, float(m2.h) * 0.5) - sk.com)
		var gem2: Color = Defs.SPELLS[game.known[game.sel]]["color"] if m2 == game.player else Color("#46e6f0")
		var aim2: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px) if m2 == game.player else m2.input.aim
		_draw_mage(m2, aim2, gem2, true, [feet2, rot, xf.y.length()])
	draw_set_transform_matrix(xf)
	draw_texture(sk.texture(), -sk.com, Color(_lit(p), 1.0))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# (the pocket is below decks now: aboard and parked, a word on how to go down)
	if game.player.aboard == sk and not game.player.deck and game.items.has("skiff") and game.shipyard.parked():
		_bubble(sk.pos - game.view_up() * 30.0, "[G] Go below to the pocket", 0.9, "door", Speech.PROMPT)

## Out in space (space.gd draws the stars, the sun and the planets): just you, your wisp, the
## light streaming from the staff, and the reticle.
func _draw_in_space() -> void:
	for p in game.parts:
		_px(p["pos"], p["col"])
	var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
	if game.player.aboard == null:
		_draw_mage(game.player, aim, Defs.SPELLS[game.known[game.sel]]["color"], true)
	_draw_skiff()
	_draw_build_preview()                 # (building in the skiff's cabin out here)
	if game.ui.mouse_over_ui():
		return
	var m: Vector2 = (get_viewport().get_mouse_position() / game.scale_px).floor()
	var rc := Color(0.7, 0.9, 1.0, 0.7)
	for k in range(2, 5):
		draw_rect(Rect2(m + Vector2(k, 0), Vector2.ONE), rc)
		draw_rect(Rect2(m - Vector2(k, 0), Vector2.ONE), rc)
		draw_rect(Rect2(m + Vector2(0, k), Vector2.ONE), rc)
		draw_rect(Rect2(m - Vector2(0, k), Vector2.ONE), rc)

## inside the ship's pocket dimension (pocket.gd draws the nebula and the isle under this): you, the sparks,
## what you're building, the cursor
func _draw_in_pocket() -> void:
	for p in game.parts:
		_px(p["pos"], p["col"])
	var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
	_draw_mage(game.player, aim, Defs.SPELLS[game.known[game.sel]]["color"], true)
	_draw_build_preview()
	_draw_forge()
	_draw_hand()
	if game.wisp_say_t > 0 and game.wisp_say != "":
		_bubble(game.player.pos - game.basis_d(game.view_angle()) * 16.0, game.wisp_say, clampf(float(game.wisp_say_t) / 30.0, 0.0, 1.0), "wisp", Speech.WISP, 1.0)
	if game.ui.mouse_over_ui():
		return
	var m: Vector2 = (get_viewport().get_mouse_position() / game.scale_px).floor()
	var rc := Color(0.85, 0.75, 1.0, 0.7)
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
	if not game.space.active and not game.pocket.active:
		_draw_sky()
	game.prof_add("drawing sprites", Time.get_ticks_usec() - t_draw)

## a speech bubble over someone's head: a rounded box with a little tail, the words wrapped to a width
## a speech bubble over a world point (speech.gd: it pops in, types out and speaks at `pitch`; style
## Speech.SPEECH, WISP or PROMPT; `key` says who's speaking, so it's remembered from frame to frame)
func _bubble(wpos: Vector2, text: String, alpha: float, key := "", style := 0, pitch := 1.0) -> void:
	var head: Vector2 = game.world_to_screen(wpos - _down_at(wpos) * 13.0)
	game.speech.draw(self, head, text, alpha, key, style, wpos, pitch)

## down at a world point: toward the planet's centre (the pocket's down is the screen's)
func _down_at(wpos: Vector2) -> Vector2:
	if game.pocket.active:
		return Vector2(0, 1)
	return game.basis_d(atan2(wpos.y, wpos.x))

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

## (a part of the drawing timed for the profiler: its time since `t0`, and now)
func _part(nm: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	game.prof_add(nm, t1 - t0)
	return t1

func _draw_all() -> void:
	var z: float = game.zoom
	if game.pocket.active:
		_draw_in_pocket()
		return
	if game.space.active and not game.space.live:
		_draw_in_space()
		return
	# the villagers (towns.gd), behind the chests so a chest in front of one is never hidden
	var tq := Time.get_ticks_usec()
	# open doors, swung out of their houses (before the villagers: they walk past in front of them)
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
		var dkey := "door_open_%d" % int(d["h"])
		if not tex.has(dkey):
			tex[dkey] = ImageTexture.create_from_image(_door_open_image(int(d["h"])))
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
	tq = _part("draw: doors", tq)
	_draw_folk()
	tq = _part("draw: folk", tq)
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
	tq = _part("draw: chests", tq)
	_draw_stations()
	tq = _part("draw: workshops", tq)
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
	tq = _part("draw: chunks", tq)
	# what the villagers are saying (they're drawn before the chests: `_draw_folk`); the bubbles
	# themselves go on after the mages, so a mage standing by never hides the words
	var bubbles := []
	for v2 in game.towns.folk:
		if v2.fade > 0:
			continue
		if v2.say_t > 0 and v2.say != "":
			bubbles.append([v2.pos, v2.say, clampf(float(v2.say_t) / 30.0, 0.0, 1.0), "f%d" % v2.fseed, Speech.SPEECH, Speech.pitch_of(v2.fseed)])
		elif v2.keeper and (v2.pos as Vector2).distance_to(game.player.pos) < 60.0:
			bubbles.append([v2.pos, "%s · %s  [F]" % [v2.name, Defs.SHOPS[v2.role]["title"]], 0.85, "k%d" % v2.fseed, Speech.PROMPT, 1.0])
		else:
			_folk_mark(v2)

	_draw_carcasses()
	# a deep ocean world's mystery: the pillars' glyphs, and what F would do in reach
	if game.mystery != null and not game.mystery.data().is_empty():
		_draw_mystery()
		var mp: String = game.mystery.prompt()
		if mp != "":
			var nr: Dictionary = game.mystery.near
			var md: Dictionary = game.mystery.data()
			var at: Vector2 = game.player.pos
			match String(nr["kind"]):
				"stone": at = md["stones"][int(nr["i"])]["pos"]
				"pillar": at = md["pillars"][int(nr["i"])]["pos"]
				"vault": at = md["vault"]
			bubbles.append([at - game.basis_d(atan2(at.y, at.x)) * 6.0, mp, 0.85, "mystery", Speech.PROMPT, 1.0])
	tq = _part("draw: words, carcasses", tq)
	# (a foe winding up an attack glows hot and flickers: the tell; a leaper crouches)
	var vr := Rect2(-120.0, -120.0, float(game.VW) + 240.0, float(game.VH) + 240.0)
	for e in game.enemies:
		# (off the screen, nothing to draw: foes come in 160+ cells away and wait there, so most of the
		# list often is; a serpent's tail can reach in from further off)
		var reach: float = 120.0 + (float(e.trail.size()) * 3.0 if e.d.has("def") else 0.0)
		if not vr.grow(reach - 120.0).has_point(game.world_to_screen(e.pos)):
			continue
		var tl: float = FoeAI.tell(e)
		var tint := Color(1, 1, 1).lerp(Color(2.2, 0.75, 0.5), tl)
		var sq := 1.0 - 0.22 * tl if (e.type == "slime" or e.type == "mimic") else 1.0
		if e.d.has("def"):
			# a guardian or creature: its frames grown from parts (on a worker thread) the first time it's
			# in the list; until they're ready it isn't drawn
			if not _boss_art(e):
				continue
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
	tq = _part("draw: foes", tq)
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
	tq = _part("draw: projectiles, preview", tq)
	# the mages, with their simulated hats, beards, scarves and staves
	for m in game.players:
		if m != game.player and not m.dead and m.aboard == null:
			_draw_mage(m, m.input.aim, Color("#46e6f0"), true)
	if not game.dead and game.player.aboard == null:
		var blink: bool = game.iframes > 0 and (game.iframes / 4) % 2 == 0
		var aim: Vector2 = game.screen_to_world(get_viewport().get_mouse_position() / game.scale_px)
		_draw_mage(game.player, aim, Defs.SPELLS[game.known[game.sel]]["color"], not blink)
	bubbles.append_array(game.test_bubbles)
	for bb in bubbles:
		_bubble(bb[0], bb[1], bb[2], bb[3], bb[4], bb[5])
	tq = _part("draw: mages", tq)
	# the skiff (over its riders: the hull hides their legs, the canopy is glass)
	_draw_skiff()
	tq = _part("draw: skiff", tq)
	# wisp companion
	var ws: Vector2 = game.world_to_screen(game.wisp)
	var wf := ws.floor()
	draw_rect(Rect2(wf - Vector2(1, 0), Vector2(3, 1)), Color8(90, 170, 255, 200))
	draw_rect(Rect2(wf - Vector2(0, 1), Vector2(1, 3)), Color8(90, 170, 255, 200))
	draw_rect(Rect2(wf, Vector2.ONE), Color8(245, 252, 255))
	if game.wisp_ward_t <= 0 and game.player.items.has("wisp_ward"):
		# (the Wisp Ward ready: a faint ring round the wisp)
		var wr := 3.0 + 0.5 * sin(float(game.frame) * 0.08)
		for k in 12:
			var wa := float(k) / 12.0 * TAU
			draw_rect(Rect2((ws + Vector2(cos(wa), sin(wa)) * wr).floor(), Vector2.ONE), Color(0.7, 0.92, 1.0, 0.35))
	if game.quest != null and game.quest.say_t > 0 and game.quest.say_text != "":
		_bubble(game.wisp + _down_at(game.wisp) * 9.0, game.quest.say_text, clampf(float(game.quest.say_t) / 30.0, 0.0, 1.0), "wisp", Speech.WISP, 1.0)
	elif game.wisp_say_t > 0 and game.wisp_say != "":
		_bubble(game.wisp + _down_at(game.wisp) * 9.0, game.wisp_say, clampf(float(game.wisp_say_t) / 30.0, 0.0, 1.0), "wisp", Speech.WISP, 1.0)
	_draw_forge()
	_draw_hand()
	_draw_pages()
	_draw_popups()
	# particles (the light read where each is in the picture: near enough, the light is soft)
	var pxf: Transform2D = game.screen_xf()
	var paff: bool = game.screen_xf_ok()
	var pm := Vector2(game.gpu.PMX, game.gpu.PMY)
	for p in game.parts:
		var c2: Color = p["col"]
		if not p["self"]:
			var psp: Vector2 = pxf * p["pos"] if paff else game.world_to_screen(p["pos"])
			var lc: Color = game.gpu.light_at(psp + pm)
			var lf := 0.04 + 0.96 * lc.a
			c2 = c2 * Color(clampf(lc.r, 0.12, 1.0) * lf, clampf(lc.g, 0.12, 1.0) * lf, clampf(lc.b, 0.12, 1.0) * lf)
		var psp2: Vector2 = pxf * p["pos"] if paff else game.world_to_screen(p["pos"])
		draw_rect(Rect2(psp2.floor(), Vector2.ONE), c2)
	tq = _part("draw: particles", tq)
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
		# (its underside on the floor: they lie 4.5 cells over the floor's top, towns.gd `_settle_sleeper`)
		draw_rect(Rect2(-ts.y * 0.5 - 1.0, 1.5, ts.y + 2.0, 3.0), bc)
		draw_rect(Rect2(-ts.y * 0.5 - 1.0, 3.5, ts.y + 2.0, 1.0), bc.darkened(0.35))
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
				_make_tex(fk + "_" + fn, fr[fn])
		if v.lying:
			_lying(v, tex[fk + "_sleep"])
			continue
		_sprite(fk + "_" + _folk_frame(v), v.pos, v.facing < 0, false, v.h, v.on_ground, game.towns.alpha_of(v), 1.0, Color(1, 1, 1), false, v.w)

## Which of a villager's frames (folk_art.gd POSES) to show (user, 26 Nov: "villagers are still basic
## animations"): running from a foe with both arms up; a four-step walk; talking to you (a hand out, then at
## the chest); a keeper waving as you come up; the smith hammering at the anvil by day, the blow landing with
## towns.gd's sparks; otherwise standing, breathing slowly and blinking now and then.
func _folk_frame(v) -> String:
	var ph: int = game.frame + v.fseed % 97
	var spd := absf(v.vx)
	if spd > 0.08:
		var step := int(v.anim * 2.0) % 4
		return ("flee%d" if spd > 1.0 else "walk%d") % step
	var near: bool = v.pos.distance_to(game.player.pos) < 60.0 and not game.player.dead
	if near and not v.near_you and v.keeper:
		v.greet_t = 70
	v.near_you = near
	if v.say_t > 0 or v.talk_t > 0:
		return "talk%d" % ((ph / 12) % 2)
	if v.greet_t > 0:
		v.greet_t -= 1
		return "wave%d" % ((v.greet_t / 9) % 2)
	if v.keeper and v.role == "smithy" and v.pos.distance_to(game.player.pos) < 320.0:
		var hk: float = game.towns.hour_at(v.pos)
		if hk > 8.0 and hk < 18.0:
			# (towns.gd throws the sparks when game.frame % 45 == fseed % 45: the hammer comes down then)
			var k := posmod(game.frame - v.fseed % 45, 45)
			return "work1" if k < 10 else ("work0" if k > 24 else "stand")
	if ph % 230 < 7:
		return "blink"
	return "breathe" if (ph / 50) % 2 == 1 else "stand"

## The workshop stations (workshops.gd): the body, lit by the world; a lit one's fire over it, unlit and
## flickering (two frames), as bright as it is hot; a Still's jar coloured by what it's steeping.
## the material a station is working (the most of what's loaded, not counting what only feeds the fire), or 0
func _working_mat(st) -> int:
	var best := 0
	var bn := 0
	for k in st.store:
		if int(st.store[k]) > bn:
			bn = int(st.store[k])
			best = int(k)
	return best

## (user, 25 Nov: "finished goods stacking on a tray beside it, taken with F"): a little plank tray at the
## station's side with what it made on it: bars and lumps of a material as little ingots in its colour,
## draughts as tiny stoppered bottles, gear as a gold glint. Up to eight shown.
func _draw_tray(st) -> void:
	if not game.workshops.has_out(st):
		return
	var z: float = game.zoom
	var side := float(st.facing)
	var base: Vector2 = game.workshops._world(st, Vector2(side * (st.w * 0.5 + 3.0), st.h * 0.5))
	var sp: Vector2 = game.world_to_screen(base)
	var rot := 0.0 if game.close_view() else wrapf(atan2(game.cam_c.y, game.cam_c.x) - atan2(base.y, base.x), -PI, PI)
	if game.close_view() and not game.unrolled():
		rot = wrapf(game.view_angle() - atan2(base.y, base.x), -PI, PI)
	var lc: Color = _lit(sp)
	var lit := Color(lc.r, lc.g, lc.b, 1.0)
	draw_set_transform(sp.floor(), rot, Vector2.ONE / z)
	# the tray: a plank on two little legs
	draw_rect(Rect2(-4, -4, 9, 1), Color(0.55, 0.38, 0.22) * lit)
	draw_rect(Rect2(-4, -3, 9, 1), Color(0.33, 0.21, 0.12) * lit)
	draw_rect(Rect2(-3, -2, 1, 2), Color(0.3, 0.19, 0.1) * lit)
	draw_rect(Rect2(3, -2, 1, 2), Color(0.3, 0.19, 0.1) * lit)
	var shown := 0
	for key in st.out:
		var n := int(st.out[key])
		var k := String(key)
		var col := Color(1.0, 0.85, 0.4)
		var bottle := false
		if k.begins_with("m"):
			col = Defs.COLOR[int(k.substr(1))]
		elif k == "potion":
			col = Color(0.9, 0.25, 0.3)
			bottle = true
		elif Defs.DRAUGHTS.has(k):
			col = Defs.DRAUGHTS[k]["col"]
			bottle = true
		for q in n:
			if shown >= 8:
				break
			var cx := -4 + (shown % 4) * 2 + (1 if bottle else 0)
			var row := shown / 4
			if bottle:
				draw_rect(Rect2(cx, -7 - row * 3, 1, 2), col * lit)
				draw_rect(Rect2(cx, -8 - row * 3, 1, 1), Color(0.5, 0.35, 0.2) * lit)
			else:
				draw_rect(Rect2(cx, -5 - row * 2, 2, 1), col * lit)
				draw_rect(Rect2(cx, -5 - row * 2, 1, 1), col.lightened(0.35) * lit)
			shown += 1
	# a glint now and then, so it catches the eye
	if (int(game.frame) / 8) % 12 == 0:
		draw_rect(Rect2(-3, -6 - ((shown - 1) / 4) * 2, 1, 1), Color(1, 1, 0.9, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_stations() -> void:
	for st in game.workshops.list:
		var ssp: Vector2 = game.world_to_screen(st.pos)
		if ssp.x < -30 or ssp.y < -30 or ssp.x > game.VW + 30 or ssp.y > game.VH + 30:
			continue
		var key: String = "st_" + st.kind
		if not tex.has(key):
			var fr: Dictionary = WorkshopArt.frames(st.kind)
			_make_tex(key, fr["body"])
			_make_tex(key + "_fire0", fr["fire0"])
			_make_tex(key + "_fire1", fr["fire1"])
			if fr["fill"] != null:
				_make_tex(key + "_fill", fr["fill"])
				# (user, 25 Nov: "the still's jar filling"): the jar's liquid at four levels, from the bottom up
				var fimg: Image = fr["fill"]
				var fy0 := fimg.get_height()
				var fy1 := -1
				for fy in fimg.get_height():
					for fx in fimg.get_width():
						if fimg.get_pixel(fx, fy).a > 0.05:
							fy0 = mini(fy0, fy)
							fy1 = maxi(fy1, fy)
				for lv in range(1, 5):
					var li: Image = fimg.duplicate()
					var cut := fy1 + 1 - int(ceilf(float(fy1 + 1 - fy0) * float(lv) / 4.0))
					for fy2 in cut:
						for fx2 in li.get_width():
							li.set_pixel(fx2, fy2, Color(0, 0, 0, 0))
					_make_tex(key + "_fill%d" % lv, li)
			# (user, 25 Nov: "ore glowing in the kiln's mouth"): a glowing lump where its fire burns lowest
			var fimg2: Image = fr["fire0"]
			var ore := Image.create(fimg2.get_width(), fimg2.get_height(), false, Image.FORMAT_RGBA8)
			ore.fill(Color(0, 0, 0, 0))
			var by := -1
			var bx0 := 0
			var bx1 := 0
			for fy3 in range(fimg2.get_height() - 1, -1, -1):
				for fx3 in fimg2.get_width():
					if fimg2.get_pixel(fx3, fy3).a > 0.3:
						if by < 0:
							by = fy3
							bx0 = fx3
						bx1 = fx3
				if by >= 0:
					break
			if by >= 0:
				var cx := (bx0 + bx1) / 2
				for ox in range(-1, 2):
					for oy in range(0, 2):
						var px2 := cx + ox
						var py2 := by - oy
						if px2 >= 0 and px2 < ore.get_width() and py2 >= 0:
							ore.set_pixel(px2, py2, Color(1, 1, 1, 1.0 if oy == 0 or ox == 0 else 0.7))
			_make_tex(key + "_ore", ore)
		var fl: bool = st.facing < 0
		_sprite(key, st.pos, fl, false, st.h, true, 1.0, 1.0, Color(1, 1, 1), true)
		var wmat := _working_mat(st)
		var fill_col := Color(0, 0, 0, 0)
		if st.kind == "still":
			var pr: Dictionary = Defs.process_by_id(st.cur)
			var it := String(pr.get("item", ""))
			if Defs.DRAUGHTS.has(it):
				fill_col = Defs.DRAUGHTS[it]["col"]
			elif it == "potion":
				fill_col = Color(0.9, 0.25, 0.3)
			elif int(st.store.get(Defs.WATER, 0)) > 0:
				fill_col = Color(0.35, 0.55, 0.95)
			if fill_col.a > 0.0 and tex.has(key + "_fill1"):
				# (the jar fills as the batch is worked: a little water in it to start)
				var pr2: Dictionary = Defs.process_by_id(st.cur)
				var lv2 := 1
				if not pr2.is_empty():
					lv2 = clampi(1 + int(4.0 * st.prog / maxf(1.0, float(pr2["ticks"]))), 1, 4)
				_sprite(key + "_fill%d" % lv2, st.pos, fl, false, st.h, true, 0.85, 1.0, fill_col * (0.7 + 0.5 * st.heat), true, 0.0, st.heat > 0.3)
		# what it's working glows in its mouth, hotter as it heats, and tints the flame toward its own colour
		var fire_tint := Color(1.3, 1.2, 1.1)
		if wmat > 0 and st.kind != "still":
			var mc: Color = Defs.COLOR[wmat]
			var hot := mc.lerp(Color(1.0, 0.6, 0.25), 0.55 * st.heat)
			_sprite(key + "_ore", st.pos, fl, false, st.h, true, 1.0, 1.0, hot * (0.8 + 0.9 * st.heat), true, 0.0, st.heat > 0.15)
			fire_tint = fire_tint.lerp(Color(mc.r * 1.4, mc.g * 1.4, mc.b * 1.4), 0.3)
		if st.heat > 0.02:
			var fk := "%s_fire%d" % [key, (int(game.frame) / 6 + int(absf(st.pos.x))) % 2]
			var fa: float = clampf(st.heat * 1.3, 0.2, 1.0) if st.lit else st.heat
			_sprite(fk, st.pos, fl, false, st.h, true, fa, 1.0, fire_tint, true, 0.0, true)
		_draw_tray(st)

