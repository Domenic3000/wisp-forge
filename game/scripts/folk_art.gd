## Villagers' pictures, grown from parts by their own seed (towns.gd): a small figure 13 x 21 with a
## dark outline like every sprite. Parts: skin, hair (short, long, a bun, bald) or a hat (hood, cap,
## straw hat, kerchief), maybe a beard, a tunic with a belt, an apron by trade (a smith's leather, a
## shopkeeper's or innkeeper's linen, a tavern keeper's brown), a dress or trousers, boots. Frames:
## "stand", "walk0", "walk1" (legs and arms swinging).
extends RefCounted

const W := 13
const H := 21
const SKIN := ["#f2cfa8", "#e0b088", "#c08a60", "#8e5a38", "#6a3f26"]
const HAIR := ["#2a1c12", "#5b3a20", "#9a6a34", "#d8c070", "#b04a22", "#8c8c8c", "#e8e8e0"]
const CLOTH := ["#6a7a3a", "#3e5a8a", "#8a3a30", "#7a5a9a", "#c08a30", "#4a7a6a", "#a05a6a", "#5a5a5a", "#2e4e3e", "#b0a070", "#9a4a2a", "#4a5a7a"]
const LEGS := ["#4a3a2a", "#3a3a4a", "#5a4a3a", "#2e2e2e", "#4a4030"]
const BOOT := ["#2a1e14", "#3a2a1a", "#1e1a18"]
const APRON := {"smithy": "#5a3a22", "shop": "#e8e4d8", "inn": "#e8e4d8", "tavern": "#8a5a30"}
const OUTLINE := Color(0.1, 0.08, 0.06)

## the frames for a villager of this seed (and trade: a keeper wears an apron)
static func frames(fseed: int, role: String) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = fseed
	var skin := Color.html(SKIN[r.randi_range(0, SKIN.size() - 1)])
	var hair := Color.html(HAIR[r.randi_range(0, HAIR.size() - 1)])
	var cloth := Color.html(CLOTH[r.randi_range(0, CLOTH.size() - 1)])
	var legs := Color.html(LEGS[r.randi_range(0, LEGS.size() - 1)])
	var boot := Color.html(BOOT[r.randi_range(0, BOOT.size() - 1)])
	var belt := cloth.darkened(0.55)
	var top: String = ["short", "long", "bun", "bald", "hood", "cap", "straw", "kerchief"][r.randi_range(0, 7)]
	var hat_col := Color.html(CLOTH[r.randi_range(0, CLOTH.size() - 1)])
	var beard := r.randf() < 0.3
	var dress := r.randf() < 0.35
	var apron: String = APRON.get(role, "")
	var out := {}
	for fr in ["stand", "walk0", "walk1"]:
		var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var swing := 0 if fr == "stand" else (1 if fr == "walk0" else -1)
		# legs and boots (rows 15-19), swinging when it walks
		_rect(img, 4 + swing, 15, 2, 4, legs)
		_rect(img, 7 - swing, 15, 2, 4, legs.darkened(0.15))
		_rect(img, 4 + swing, 19, 2, 1, boot)
		_rect(img, 7 - swing, 19, 2, 1, boot)
		# body: a tunic (or a dress down to the shins), the right side shaded
		_rect(img, 3, 9, 7, 6, cloth)
		_rect(img, 9, 10, 1, 5, cloth.darkened(0.18))
		if dress:
			_rect(img, 3, 14, 7, 3, cloth.darkened(0.08))
			_rect(img, 2, 16, 9, 1, cloth.darkened(0.12))
		_rect(img, 3, 12, 7, 1, belt)
		if apron != "":
			var ac := Color.html(apron)
			_rect(img, 4, 10, 5, 6, ac)
			_rect(img, 4, 12, 5, 1, ac.darkened(0.25))
		# arms and hands, swinging the other way to the legs
		_rect(img, 2, 9, 1, 4 - swing, cloth.darkened(0.08))
		_rect(img, 10, 9, 1, 4 + swing, cloth.darkened(0.22))
		_px(img, 2, 13 - swing, skin)
		_px(img, 10, 13 + swing, skin.darkened(0.1))
		# neck and head
		_rect(img, 5, 8, 3, 1, skin.darkened(0.12))
		_rect(img, 4, 3, 5, 5, skin)
		_rect(img, 8, 4, 1, 4, skin.darkened(0.1))
		_px(img, 5, 5, Color(0.12, 0.1, 0.1))
		_px(img, 7, 5, Color(0.12, 0.1, 0.1))
		_px(img, 6, 7, skin.darkened(0.25))
		if beard:
			_rect(img, 4, 6, 5, 2, hair)
			_px(img, 6, 8, hair)
			_px(img, 6, 6, skin.darkened(0.25))
		# what's on top
		match top:
			"short":
				_rect(img, 4, 2, 5, 1, hair)
				_px(img, 4, 3, hair)
				_px(img, 8, 3, hair)
			"long":
				_rect(img, 4, 2, 5, 1, hair)
				_rect(img, 3, 3, 1, 6, hair)
				_rect(img, 9, 3, 1, 6, hair.darkened(0.15))
			"bun":
				_rect(img, 4, 2, 5, 1, hair)
				_rect(img, 5, 1, 3, 1, hair)
				_px(img, 4, 3, hair)
				_px(img, 8, 3, hair)
			"hood":
				_rect(img, 3, 1, 7, 2, hat_col)
				_rect(img, 3, 3, 1, 5, hat_col)
				_rect(img, 9, 3, 1, 5, hat_col.darkened(0.18))
				_px(img, 4, 3, hat_col)
				_px(img, 8, 3, hat_col)
			"cap":
				_rect(img, 4, 1, 5, 2, hat_col)
				_rect(img, 4, 3, 6, 1, hat_col.darkened(0.25))
			"straw":
				_rect(img, 4, 1, 5, 2, Color(0.86, 0.74, 0.38))
				_rect(img, 2, 3, 9, 1, Color(0.78, 0.64, 0.3))
			"kerchief":
				_rect(img, 4, 2, 5, 2, hat_col)
				_px(img, 3, 3, hat_col.darkened(0.2))
		_outline(img)
		out[fr] = img
	return out

## a villager's name from parts
static func name_for(fseed: int) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = fseed ^ 0x5bd1e995
	return "%s %s" % [Defs.FOLK_FIRST[r.randi_range(0, Defs.FOLK_FIRST.size() - 1)], Defs.FOLK_LAST[r.randi_range(0, Defs.FOLK_LAST.size() - 1)]]

static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		img.set_pixel(x, y, c)

## a dark outline round every opaque pixel
static func _outline(img: Image) -> void:
	var solid := []
	for y in H:
		for x in W:
			if img.get_pixel(x, y).a > 0.5:
				solid.append(Vector2i(x, y))
	var seen := {}
	for p in solid:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x < 0 or q.y < 0 or q.x >= W or q.y >= H or seen.has(q):
				continue
			if img.get_pixel(q.x, q.y).a < 0.5:
				seen[q] = true
	for q in seen:
		img.set_pixel(q.x, q.y, OUTLINE)
