## Villagers' pictures, grown from parts by their own seed (towns.gd): a small figure with a dark outline like
## every sprite. Parts: skin, hair (short, long, a bun, bald) or a hat (hood, cap, straw hat, kerchief), maybe a
## beard, a tunic with a collar and a belt, an apron by trade (a smith's leather, a shopkeeper's or innkeeper's
## linen, a tavern keeper's brown), a dress or trousers, boots.
## Frames (user, 26 Nov: "villagers are still basic animations"), each the same parts in another pose (`POSES`):
## "stand", "breathe" (a pixel lower), "blink", "sleep" (eyes shut), a four-step walk "walk0".."walk3" (legs
## apart with the body down a pixel, then passing with a foot lifted; arms swinging against the legs), "talk0",
## "talk1" (a hand out, then at the chest), "wave0", "wave1", the smith's hammer "work0" (raised), "work1"
## (struck), and running away with both arms up "flee0".."flee3". overlay.gd `_folk_frame` picks one.
extends RefCounted

const W := 19                # (13 wide before; 3 spare columns each side for arms and tools held out)
const H := 21
const X0 := 3                # the parts are laid out on the old 13-wide grid, this many columns in
const SKIN := ["#f2cfa8", "#e0b088", "#c08a60", "#8e5a38", "#6a3f26"]
const HAIR := ["#2a1c12", "#5b3a20", "#9a6a34", "#d8c070", "#b04a22", "#8c8c8c", "#e8e8e0"]
const CLOTH := ["#6a7a3a", "#3e5a8a", "#8a3a30", "#7a5a9a", "#c08a30", "#4a7a6a", "#a05a6a", "#5a5a5a", "#2e4e3e", "#b0a070", "#9a4a2a", "#4a5a7a"]
const LEGS := ["#4a3a2a", "#3a3a4a", "#5a4a3a", "#2e2e2e", "#4a4030"]
const BOOT := ["#2a1e14", "#3a2a1a", "#1e1a18"]
const APRON := {"smithy": "#5a3a22", "shop": "#e8e4d8", "inn": "#e8e4d8", "tavern": "#8a5a30"}
const OUTLINE := Color(0.1, 0.08, 0.06)
const HANDLE := Color(0.45, 0.3, 0.17)
const IRON := Color(0.42, 0.43, 0.48)
const IRON_DK := Color(0.32, 0.33, 0.38)
const IRON_HI := Color(0.62, 0.63, 0.68)
const MOUTH := Color(0.35, 0.1, 0.1)
## each frame: "sw" legs apart (+1 / -1), "lift" a foot raised (+1 the near one, -1 the far), "dy" the body a
## pixel down, "back" / "front" the arms' poses ([name, n]), "eyes" "shut", "mouth" open
const POSES := {
	"stand": {}, "breathe": {"dy": 1}, "blink": {"eyes": "shut"}, "sleep": {"eyes": "shut"},
	"walk0": {"sw": 1, "dy": 1, "back": ["swing", -1], "front": ["swing", 1]},
	"walk1": {"lift": 1},
	"walk2": {"sw": -1, "dy": 1, "back": ["swing", 1], "front": ["swing", -1]},
	"walk3": {"lift": -1},
	"talk0": {"front": ["out", 0], "mouth": true},
	"talk1": {"front": ["chest", 0]},
	"wave0": {"front": ["up", 0], "mouth": true},
	"wave1": {"front": ["up", 1], "mouth": true},
	"work0": {"front": ["hammer_up", 0]},
	"work1": {"front": ["hammer_down", 0], "dy": 1},
	"flee0": {"sw": 1, "dy": 1, "back": ["up", 0], "front": ["up", 1], "mouth": true},
	"flee1": {"lift": 1, "back": ["up", 1], "front": ["up", 0], "mouth": true},
	"flee2": {"sw": -1, "dy": 1, "back": ["up", 0], "front": ["up", 1], "mouth": true},
	"flee3": {"lift": -1, "back": ["up", 1], "front": ["up", 0], "mouth": true},
	"jab": {"front": ["jab", 0], "mouth": true, "sw": 1},
}
## (26 Nov) a village's guard (towns.gd `_guard`): an iron kettle helmet, a tabard in the village's colour over
## mail, and a spear held upright (thrust out level in "jab")
const TABARD := ["#8a2a2a", "#2a4a8a", "#2a6a3a", "#7a5a1a", "#5a2a6a"]

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
	var guard := role == "guard"
	if guard:
		top = "helm"
		dress = false
		cloth = Color.html(TABARD[r.randi_range(0, TABARD.size() - 1)])
		legs = Color(0.36, 0.37, 0.42)
	var out := {}
	for fr in POSES:
		var f: Dictionary = POSES[fr]
		var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var dy: int = int(f.get("dy", 0))
		var sw: int = int(f.get("sw", 0))
		var lift: int = int(f.get("lift", 0))
		# legs and boots (rows 15-19, never moved by dy): apart, or together with a foot lifted
		var la := 4 + sw
		var ra := 7 - sw
		if lift != 0:
			la = 5
			ra = 6
		var lh := 3 if lift == 1 else 4
		var rh := 3 if lift == -1 else 4
		_rect(img, la, 15, 2, lh, legs)
		_rect(img, ra, 15, 2, rh, legs.darkened(0.15))
		_rect(img, la, 15 + lh, 2, 1, boot)
		_rect(img, ra, 15 + rh, 2, 1, boot)
		_px(img, la + 1, 15 + lh, boot.lightened(0.25))
		_px(img, ra + 1, 15 + rh, boot.lightened(0.25))
		# body: a tunic (or a dress down to the shins), lit from the left, a collar, a belt and its buckle
		_rect(img, 3, 9 + dy, 7, 6, cloth)
		_rect(img, 9, 10 + dy, 1, 5, cloth.darkened(0.18))
		_rect(img, 3, 9 + dy, 1, 5, cloth.lightened(0.1))
		_rect(img, 4, 9 + dy, 5, 1, cloth.lightened(0.06))
		_px(img, 5, 9 + dy, cloth.darkened(0.3))
		_px(img, 7, 9 + dy, cloth.darkened(0.3))
		_px(img, 6, 9 + dy, skin.darkened(0.12))
		_px(img, 6, 10 + dy, cloth.darkened(0.3))
		if dress:
			_rect(img, 3, 14 + dy, 7, 3, cloth.darkened(0.08))
			_rect(img, 2, 16 + dy, 9, 1, cloth.darkened(0.12))
		_rect(img, 3, 12 + dy, 7, 1, belt)
		_px(img, 6, 12 + dy, Color(0.78, 0.62, 0.3))
		if guard:
			# (mail at the shoulders and hem, a pale cross on the tabard)
			_rect(img, 3, 9 + dy, 7, 1, IRON)
			_rect(img, 3, 14 + dy, 7, 1, IRON_DK)
			_rect(img, 6, 10 + dy, 1, 4, cloth.lightened(0.45))
			_rect(img, 5, 11 + dy, 3, 1, cloth.lightened(0.45))
		if apron != "":
			var ac := Color.html(apron)
			_rect(img, 4, 10 + dy, 5, 6, ac)
			_rect(img, 4, 12 + dy, 5, 1, ac.darkened(0.25))
		# arms and hands
		_arm(img, 2, -1, f.get("back", ["down", 0]), cloth.darkened(0.08), skin, dy)
		var front: Array = f.get("front", ["down", 0])
		if guard and String(front[0]) != "jab" and String(front[0]) != "up":
			front = ["spear", 0]
		_arm(img, 10, 1, front, cloth.darkened(0.22), skin.darkened(0.1), dy)
		# neck and head
		_rect(img, 5, 8 + dy, 3, 1, skin.darkened(0.12))
		_rect(img, 4, 3 + dy, 5, 5, skin)
		_rect(img, 8, 4 + dy, 1, 4, skin.darkened(0.1))
		var eye := skin.darkened(0.35) if String(f.get("eyes", "")) == "shut" else Color(0.12, 0.1, 0.1)
		_px(img, 5, 5 + dy, eye)
		_px(img, 7, 5 + dy, eye)
		var talking: bool = f.get("mouth", false)
		_px(img, 6, 7 + dy, MOUTH if talking else skin.darkened(0.25))
		if beard:
			_rect(img, 4, 6 + dy, 5, 2, hair)
			_px(img, 6, 8 + dy, hair)
			_px(img, 6, 6 + dy, skin.darkened(0.25))
			if talking:
				_px(img, 6, 7 + dy, MOUTH)
		# what's on top
		match top:
			"short":
				_rect(img, 4, 2 + dy, 5, 1, hair)
				_px(img, 4, 3 + dy, hair)
				_px(img, 8, 3 + dy, hair)
			"long":
				_rect(img, 4, 2 + dy, 5, 1, hair)
				_rect(img, 3, 3 + dy, 1, 6, hair)
				_rect(img, 9, 3 + dy, 1, 6, hair.darkened(0.15))
			"bun":
				_rect(img, 4, 2 + dy, 5, 1, hair)
				_rect(img, 5, 1 + dy, 3, 1, hair)
				_px(img, 4, 3 + dy, hair)
				_px(img, 8, 3 + dy, hair)
			"hood":
				_rect(img, 3, 1 + dy, 7, 2, hat_col)
				_rect(img, 3, 3 + dy, 1, 5, hat_col)
				_rect(img, 9, 3 + dy, 1, 5, hat_col.darkened(0.18))
				_px(img, 4, 3 + dy, hat_col)
				_px(img, 8, 3 + dy, hat_col)
			"cap":
				_rect(img, 4, 1 + dy, 5, 2, hat_col)
				_rect(img, 4, 3 + dy, 6, 1, hat_col.darkened(0.25))
			"straw":
				_rect(img, 4, 1 + dy, 5, 2, Color(0.86, 0.74, 0.38))
				_rect(img, 2, 3 + dy, 9, 1, Color(0.78, 0.64, 0.3))
			"kerchief":
				_rect(img, 4, 2 + dy, 5, 2, hat_col)
				_px(img, 3, 3 + dy, hat_col.darkened(0.2))
			"helm":
				_rect(img, 4, 1 + dy, 5, 2, IRON)
				_rect(img, 3, 3 + dy, 7, 1, IRON_DK)
				_px(img, 5, 1 + dy, IRON_HI)
				_px(img, 6, 0 + dy, IRON)
		if top == "short" or top == "long" or top == "bun":
			_px(img, 5, 2 + dy, hair.lightened(0.3))       # (a shine on the hair)
		_outline(img)
		out[fr] = img
	return out

## an arm from the shoulder at column x (side: -1 the back arm, 1 the front), in a pose
static func _arm(img: Image, x: int, side: int, pose: Array, col: Color, hand: Color, dy: int) -> void:
	var n: int = int(pose[1])
	match String(pose[0]):
		"swing":
			_rect(img, x, 9 + dy, 1, 4 - n, col)
			_px(img, x, 13 - n + dy, hand)
		"out":
			_px(img, x, 9 + dy, col)
			_px(img, x, 10 + dy, col)
			_px(img, x + side, 10 + dy, col)
			_px(img, x + 2 * side, 10 + dy, hand)
		"chest":
			_px(img, x, 9 + dy, col)
			_px(img, x, 10 + dy, col)
			_px(img, x - side, 11 + dy, hand)
		"up":
			_px(img, x, 9 + dy, col)
			_px(img, x + side, 8 + dy, col)
			_px(img, x + side, 7 + dy, col)
			_px(img, x + side * (1 + n), 6 + dy, hand)
		"hammer_up":
			_px(img, x, 9 + dy, col)
			_px(img, x + side, 8 + dy, col)
			_px(img, x + side, 7 + dy, col)
			_px(img, x + side, 6 + dy, hand)
			_px(img, x + side, 5 + dy, HANDLE)
			_px(img, x + side, 4 + dy, HANDLE)
			_rect(img, x if side > 0 else x - 2, 2 + dy, 3, 2, IRON)
			_px(img, x + side, 2 + dy, IRON_HI)
		"spear":
			# (upright beside them, the hand at its middle)
			_rect(img, x, 9 + dy, 1, 3, col)
			_px(img, x, 12 + dy, hand)
			for j in range(1, 20):
				_px(img, x + side, j, HANDLE if j > 3 else IRON)
			_px(img, x + side, 0, IRON_HI)
		"jab":
			# (thrust out level)
			_px(img, x, 9 + dy, col)
			_px(img, x + side, 10 + dy, col)
			_px(img, x + 2 * side, 10 + dy, hand)
			for i in range(-4, 4):
				_px(img, x + (2 + i) * side, 11 + dy, HANDLE if i < 2 else IRON)
			_px(img, x + 5 * side, 11 + dy, IRON_HI)
		"hammer_down":
			_px(img, x, 9 + dy, col)
			_px(img, x, 10 + dy, col)
			_px(img, x + side, 11 + dy, hand)
			_px(img, x + 2 * side, 11 + dy, HANDLE)
			for j in [10, 11, 12]:
				_px(img, x + 3 * side, j + dy, IRON)
				_px(img, x + 4 * side, j + dy, IRON_DK)
			_px(img, x + 3 * side, 10 + dy, IRON_HI)
		_:
			_rect(img, x, 9 + dy, 1, 4, col)
			_px(img, x, 13 + dy, hand)

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
	if x + X0 >= 0 and y >= 0 and x + X0 < W and y < H:
		img.set_pixel(x + X0, y, c)

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
