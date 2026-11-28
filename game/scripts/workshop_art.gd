## Pixel art for the workshops (Defs.STATIONS), grown from parts like the rest of the game: a beehive Kiln of
## brick courses with an arched mouth, a Smelter's stone firebox under a brick stack with a crucible's
## spout, a copper Still over a little firebox with its coil running down into a glass jar, an Anvil on a
## stump. Each kind gives three pictures of the same size: "body" (lit by the world), "fire" (what glows
## when it's lit: flames in the mouth, the glow of hot slits and molten metal; drawn unlit by the overlay,
## two flickering frames "fire0"/"fire1") and, for the Still, "fill" (the jar's liquid, tinted by what it
## is making). `frames(kind)` -> {"body": Image, "fire0": Image, "fire1": Image, "fill": Image or null}.
extends RefCounted

const CLEAR := Color(0, 0, 0, 0)

static var _cache := {}

static func frames(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var sd: Dictionary = Defs.STATIONS[kind]
	var w: int = sd["w"]
	var h: int = sd["h"]
	var body := Image.create(w, h, false, Image.FORMAT_RGBA8)
	body.fill(CLEAR)
	var fire := []
	for k in 2:
		var fi := Image.create(w, h, false, Image.FORMAT_RGBA8)
		fi.fill(CLEAR)
		fire.append(fi)
	var fill: Image = null
	match kind:
		"kiln": _kiln(body, fire)
		"smelter": _smelter(body, fire)
		"still":
			fill = Image.create(w, h, false, Image.FORMAT_RGBA8)
			fill.fill(CLEAR)
			_still(body, fire, fill)
		"anvil": _anvil(body)
		"altar": _altar(body, fire)
		"lectern": _lectern(body, fire)
	_outline(body)
	var out := {"body": body, "fire0": fire[0], "fire1": fire[1], "fill": fill}
	_cache[kind] = out
	return out

static func _h(a: int, b: int) -> int:
	var x := (a * 73856093) ^ (b * 19349663) ^ 0x5bd1e995
	x = (x ^ (x >> 13)) * 1274126177
	return absi(x ^ (x >> 16))

## a darker line round the picture's edge (only inside it: the overlay's own outline isn't drawn on these)
static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src: Image = img.duplicate()
	for y in h:
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				continue
			var edge := false
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x < 0 or q.x >= w or q.y < 0 or src.get_pixel(q.x, q.y).a < 0.5:
					edge = true
			if edge:
				img.set_pixel(x, y, c.darkened(0.45))

## flames in a mouth: each column's flame reaches a random height, white-yellow at the bottom to red at
## the top, a different draw for each flicker frame
static func _flames(fire: Array, x0: int, x1: int, y_top: int, y_bot: int, seed: int) -> void:
	var cols := [Color(1.0, 0.95, 0.6), Color(1.0, 0.78, 0.25), Color(1.0, 0.5, 0.12), Color(0.85, 0.22, 0.08)]
	for k in 2:
		var img: Image = fire[k]
		for x in range(x0, x1 + 1):
			var span := y_bot - y_top + 1
			var hgt := 1 + _h(x * 7 + k * 131, seed) % maxi(span, 1)
			for j in hgt:
				var y := y_bot - j
				var f := float(j) / float(maxi(span - 1, 1))
				img.set_pixel(x, y, cols[mini(int(f * 4.0), 3)])

static func _kiln(body: Image, fire: Array) -> void:
	var w := body.get_width()
	var h := body.get_height()
	var bricks := [Color8(156, 74, 58), Color8(168, 84, 64), Color8(142, 66, 52), Color8(128, 60, 48)]
	var mortar := Color8(92, 50, 40)
	var cx := w * 0.5
	var base := h - 2
	# the dome: brick courses two rows high, each brick four long, every other course set over by two
	for y in range(0, base):
		for x in w:
			var dx := (x + 0.5 - cx) / (w * 0.5 - 0.5)
			var dy := (base - 0.5 - y) / float(base - 1)
			if dx * dx + dy * dy > 1.0:
				continue
			var course := y / 2
			var bx := x + (course % 2) * 2
			var c: Color = bricks[_h(course, bx / 4) % 4]
			if bx % 4 == 0 or y % 2 == 1 and _h(x, y) % 3 == 0:
				c = mortar
			# lit from the top left
			if dx < -0.35 and dy > 0.25:
				c = c.lightened(0.12)
			elif dx > 0.45:
				c = c.darkened(0.18)
			body.set_pixel(x, y, c)
	# a flue at the top
	for x in range(int(cx) - 2, int(cx) + 2):
		for y in 2:
			body.set_pixel(x, y, Color8(70, 66, 64) if y == 0 else Color8(96, 90, 86))
	# the stone footing
	for y in range(base, h):
		for x in w:
			var s := Color8(110, 106, 102) if (x + y * 3) % 5 != 0 else Color8(84, 80, 78)
			body.set_pixel(x, y, s if y == base else s.darkened(0.2))
	# the arched mouth, dark inside, and the fire in it
	var mx0 := int(cx) - 3
	var mx1 := int(cx) + 2
	var my0 := base - 6
	for y in range(my0, base):
		for x in range(mx0, mx1 + 1):
			var ax := x + 0.5 - cx
			if y < my0 + 2 and absf(ax) > 2.2 - (y - my0):
				continue
			body.set_pixel(x, y, Color8(26, 14, 10))
	_flames(fire, mx0 + 1, mx1 - 1, my0 + 1, base - 1, 11)
	# hot vents in the dome and a glow at the flue
	for k in 2:
		var img: Image = fire[k]
		img.set_pixel(3, base - 9, Color(1.0, 0.55, 0.2, 0.8))
		img.set_pixel(w - 4, base - 10, Color(1.0, 0.55, 0.2, 0.8 if k == 0 else 0.5))
		img.set_pixel(int(cx) - 1, 1, Color(1.0, 0.7, 0.3, 0.6 + 0.3 * k))
		img.set_pixel(int(cx), 1, Color(1.0, 0.7, 0.3, 0.9 - 0.3 * k))

static func _smelter(body: Image, fire: Array) -> void:
	var w := body.get_width()
	var h := body.get_height()
	var stone := [Color8(120, 118, 124), Color8(104, 102, 110), Color8(136, 134, 140), Color8(92, 90, 98)]
	var bricks := [Color8(150, 70, 54), Color8(164, 80, 60), Color8(136, 62, 48)]
	var top := 11
	# the firebox: big dressed stones
	for y in range(top, h):
		for x in range(1, w - 1):
			var course := (y - top) / 3
			var bx := x + (course % 2) * 3
			var c: Color = stone[_h(course, bx / 6) % 4]
			if bx % 6 == 0 or (y - top) % 3 == 0:
				c = Color8(74, 72, 80)
			body.set_pixel(x, y, c)
	for x in w:
		body.set_pixel(x, h - 1, Color8(70, 68, 76))
		body.set_pixel(x, h - 2, Color8(96, 94, 102))
	# the stack, narrowing as it goes up
	for y in range(0, top):
		var half := 3.0 - float(top - 1 - y) * 0.09
		for x in w:
			if absf(x + 0.5 - w * 0.5) > half:
				continue
			var c2: Color = bricks[_h(y / 2, (x + (y / 2 % 2)) / 3) % 3]
			if (x + (y / 2 % 2)) % 3 == 0 and y % 2 == 0:
				c2 = Color8(88, 46, 38)
			if x + 0.5 < w * 0.5 - 1.5:
				c2 = c2.lightened(0.1)
			body.set_pixel(x, y, c2)
	for x in range(int(w * 0.5) - 4, int(w * 0.5) + 4):
		body.set_pixel(x, 0, Color8(70, 66, 70))
	# a lip round the top of the firebox
	for x in w:
		body.set_pixel(x, top, Color8(150, 148, 154))
	# the crucible's spout on the right, and an ingot mould under it
	body.set_pixel(w - 1, top + 2, Color8(80, 60, 50))
	body.set_pixel(w - 2, top + 2, Color8(80, 60, 50))
	body.set_pixel(w - 1, top + 3, Color8(60, 44, 36))
	# the mouth
	var mx0 := 5
	var mx1 := w - 6
	var my0 := h - 8
	for y in range(my0, h - 2):
		for x in range(mx0, mx1 + 1):
			if y == my0 and (x == mx0 or x == mx1):
				continue
			body.set_pixel(x, y, Color8(24, 14, 12))
	_flames(fire, mx0 + 1, mx1 - 1, my0 + 1, h - 3, 23)
	for k in 2:
		var img: Image = fire[k]
		# a heat slit across the firebox, the molten drip at the spout, the stack's mouth glowing
		for x in range(3, w - 3):
			if _h(x, k) % 4 != 0:
				img.set_pixel(x, top + 2, Color(1.0, 0.6, 0.2, 0.85))
		img.set_pixel(w - 1, top + 4 + k, Color(1.0, 0.85, 0.35))
		for x2 in range(int(w * 0.5) - 2, int(w * 0.5) + 2):
			img.set_pixel(x2, 1, Color(1.0, 0.5 + 0.2 * k, 0.2, 0.7))

static func _still(body: Image, fire: Array, fill: Image) -> void:
	var w := body.get_width()
	var h := body.get_height()
	var cu := [Color8(184, 101, 46), Color8(224, 154, 90), Color8(150, 78, 36), Color8(110, 56, 28)]
	# the firebox under the pot (open at the front)
	for y in range(h - 4, h):
		for x in range(1, 9):
			var c := Color8(112, 108, 104) if (x + y) % 4 != 0 else Color8(88, 84, 82)
			if y >= h - 3 and y < h - 1 and x >= 3 and x <= 6:
				c = Color8(28, 18, 14)
			body.set_pixel(x, y, c)
	_flames(fire, 3, 6, h - 3, h - 2, 37)
	# the pot: a round copper belly, lit on the left
	var pcx := 4.5
	var pcy := 7.0
	for y in range(2, h - 4):
		for x in range(0, 10):
			var dx := (x + 0.5 - pcx) / 4.3
			var dy := (y + 0.5 - pcy) / 4.2
			if dx * dx + dy * dy > 1.0:
				continue
			var c2: Color = cu[0]
			if dx < -0.3 and dy < 0.1:
				c2 = cu[1]
			elif dx > 0.5 or dy > 0.6:
				c2 = cu[2]
			if y == int(pcy) + 1 and _h(x, 3) % 2 == 0:
				c2 = cu[3]                       # (a band of rivets)
			body.set_pixel(x, y, c2)
	# its neck and cap
	for y in range(0, 3):
		for x in range(3, 7):
			if y == 0 and (x == 3 or x == 6):
				continue
			body.set_pixel(x, y, cu[1] if x == 3 else cu[0])
	# the coil: along the top, then down to the jar
	for x in range(7, 12):
		body.set_pixel(x, 1, cu[2])
	for y in range(1, 8):
		body.set_pixel(12, y, cu[2] if y % 2 == 0 else cu[0])
	# the glass jar on a little stand
	for y in range(8, h - 1):
		for x in range(10, 15):
			var edge := x == 10 or x == 14 or y == 8 or y == h - 2
			if edge:
				body.set_pixel(x, y, Color(0.75, 0.9, 0.95))
			else:
				body.set_pixel(x, y, Color(0.6, 0.78, 0.86, 0.45))
				if y >= 10:
					fill.set_pixel(x, y, Color(1, 1, 1, 0.9 if y > 10 else 0.6))
	for x in range(10, 15):
		body.set_pixel(x, h - 1, Color8(122, 80, 44))

static func _anvil(body: Image) -> void:
	var w := body.get_width()
	var h := body.get_height()
	var iron := Color8(70, 70, 84)
	var hi := Color8(118, 118, 136)
	var dk := Color8(44, 44, 54)
	# the face and the horn
	for x in range(1, w - 1):
		body.set_pixel(x, 0, hi)
		body.set_pixel(x, 1, iron)
	body.set_pixel(0, 1, iron)
	for x in range(w - 4, w):
		body.set_pixel(x, 2, iron)
	# the waist and the foot
	for y in range(2, 4):
		for x in range(4, 9):
			body.set_pixel(x, y, dk if x == 8 else iron)
	for x in range(3, 10):
		body.set_pixel(x, 4, iron)
	# the stump
	for y in range(5, h):
		for x in range(3, 10):
			var c := Color8(110, 72, 40) if (x + y) % 3 != 0 else Color8(88, 56, 30)
			if y == 5:
				c = Color8(160, 120, 76)
			body.set_pixel(x, y, c)

## The summoned forge (user, 25 Nov: "C summons the forge into the world"): a spectral anvil on a floating
## plinth of light, a violet flame over its face (the Wisp Forge's own fire). Grown like the rest: a larger
## anvil than the workshop's (horn, face, waist, foot), its pixels in ghost-light by their shade, a hollow
## glowing edge, and two flickering flame frames. {"body", "fire0", "fire1"}, 17 x 24, the base at the bottom.
static func spirit_forge() -> Dictionary:
	if _cache.has("_spirit"):
		return _cache["_spirit"]
	var w := 17
	var h := 24
	var body := Image.create(w, h, false, Image.FORMAT_RGBA8)
	body.fill(CLEAR)
	var lit := Color(0.86, 0.9, 1.0, 0.95)
	var mid := Color(0.55, 0.62, 1.0, 0.85)
	var dk := Color(0.36, 0.3, 0.78, 0.8)
	var y0 := h - 12                # the face's top row
	# the face, the horn pointing left, a heel step on the right
	for x in range(2, w - 1):
		body.set_pixel(x, y0, lit)
		body.set_pixel(x, y0 + 1, mid)
	for x in range(0, 4):
		body.set_pixel(x, y0 + 1, mid)
	body.set_pixel(0, y0 + 2, dk)
	body.set_pixel(1, y0 + 2, mid)
	for x in range(w - 4, w - 1):
		body.set_pixel(x, y0 + 2, mid)
	# the waist and the foot
	for y in range(y0 + 2, y0 + 6):
		for x in range(6, 11):
			body.set_pixel(x, y, dk if x == 10 else mid)
	for x in range(4, 13):
		body.set_pixel(x, y0 + 6, mid)
		body.set_pixel(x, y0 + 7, dk)
	# a plinth of light it stands on, fading downward
	for y in range(y0 + 8, h):
		var a := 0.55 - 0.13 * float(y - y0 - 8)
		for x in range(3, 14):
			if (x + y) % 2 == 0 or y == y0 + 8:
				body.set_pixel(x, y, Color(0.6, 0.7, 1.0, maxf(a, 0.1)))
	# the flame over the face: violet at the root, white at the heart
	var fire := []
	var cols := [Color(1.0, 0.97, 1.0), Color(0.85, 0.72, 1.0), Color(0.62, 0.45, 1.0), Color(0.42, 0.26, 0.9)]
	for k in 2:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(CLEAR)
		for x in range(5, 12):
			var dx: int = absi(x - 8)
			var hgt := 9 - dx * 2 + _h(x * 5 + k * 77, 31) % 3
			for j in maxi(hgt, 1):
				var y := y0 - 1 - j
				if y < 0:
					break
				var f := float(j) / float(maxi(hgt - 1, 1))
				img.set_pixel(x, y, cols[mini(int(f * 3.0 + float(dx) * 0.4), 3)])
		fire.append(img)
	var out := {"body": body, "fire0": fire[0], "fire1": fire[1]}
	_cache["_spirit"] = out
	return out

## A Summoning Altar: a stepped plinth of dressed stone, a block carved with runes and a basin on top
## between two short pillars capped with crystals. Its "fire" is the runes, the basin and the crystals
## glowing mana-blue (always: an altar is never cold).
static func _altar(body: Image, fire: Array) -> void:
	var w := body.get_width()
	var h := body.get_height()
	var lt := Color8(168, 166, 178)
	var md := Color8(124, 122, 138)
	var dk := Color8(84, 82, 100)
	var glow := [Color8(140, 200, 255), Color8(190, 150, 255)]
	var core := Color8(235, 245, 255)
	# three steps, widest at the bottom
	for y in range(h - 3, h):
		for x in w:
			body.set_pixel(x, y, lt if y == h - 3 else (dk if (x + y) % 5 == 0 else md))
	for y in range(h - 6, h - 3):
		for x in range(2, w - 2):
			body.set_pixel(x, y, lt if y == h - 6 else md)
	# the block, with a row of carved runes
	var bt := h - 11
	for y in range(bt, h - 6):
		for x in range(4, w - 4):
			body.set_pixel(x, y, lt if y == bt else (md if (x % 6) != 3 else dk))
	var rune_y := bt + 2
	for x in range(6, w - 6):
		if _h(x, 7) % 3 != 0:
			body.set_pixel(x, rune_y, dk)
			body.set_pixel(x, rune_y + 1, dk if _h(x, 9) % 2 == 0 else md)
			for k in 2:
				var fi: Image = fire[k]
				fi.set_pixel(x, rune_y, glow[(x + k) % 2])
				if _h(x, 9) % 2 == 0:
					fi.set_pixel(x, rune_y + 1, glow[(x + k + 1) % 2])
	# the basin on top
	for x in range(7, w - 7):
		body.set_pixel(x, bt - 1, dk)
	body.set_pixel(6, bt - 2, md)
	body.set_pixel(w - 7, bt - 2, md)
	for k2 in 2:
		var fi2: Image = fire[k2]
		for x2 in range(8, w - 8):
			fi2.set_pixel(x2, bt - 1, core if (x2 + k2) % 3 == 0 else glow[k2])
			if (x2 + k2) % 2 == 0:
				fi2.set_pixel(x2, bt - 2, glow[(x2 + k2) % 2])
	# two short pillars with crystal caps
	for px in [1, w - 3]:
		for y2 in range(3, h - 3):
			body.set_pixel(px, y2, lt)
			body.set_pixel(px + 1, y2, md if y2 % 4 != 0 else dk)
		body.set_pixel(px, 2, md)
		body.set_pixel(px + 1, 2, md)
		for k3 in 2:
			var fi3: Image = fire[k3]
			fi3.set_pixel(px, 1, glow[k3])
			fi3.set_pixel(px + 1, 1, core if k3 == 0 else glow[1])
			fi3.set_pixel(px, 0, core if k3 == 1 else glow[0])



## The Lectern (27 Nov: where artifacts are studied): a carved wooden stand on a foot, its slanted top holding an
## open book of pale pages; studying, the pages' glyphs and a little floating mote glow (the "fire" frames).
static func _lectern(body: Image, fire: Array) -> void:
	var w := body.get_width()
	var h := body.get_height()
	var wood := Color8(120, 80, 46)
	var hi := Color8(160, 112, 66)
	var dk := Color8(78, 50, 28)
	var page := Color8(226, 214, 186)
	var page_dk := Color8(186, 170, 140)
	var ink := Color8(70, 56, 92)
	# the foot
	for x in range(1, w - 1):
		body.set_pixel(x, h - 1, dk)
		body.set_pixel(x, h - 2, wood if x > 1 and x < w - 2 else dk)
	for x in range(2, w - 2):
		body.set_pixel(x, h - 3, hi if x == 2 else wood)
	# the post, carved with two rings
	var cx := w / 2
	for y in range(6, h - 3):
		for x in range(cx - 1, cx + 1):
			var c := wood if x == cx - 1 else dk
			if y == 9 or y == h - 6:
				c = hi
			body.set_pixel(x, y, c)
	# the slanted top under the book
	for k in w:
		var y := 6 - int(float(k) * 0.35)
		if y >= 1:
			body.set_pixel(k, y, dk)
			body.set_pixel(k, mini(y + 1, 6), wood)
	# the open book on it: two pages, a spine in the middle
	for k in range(1, w - 1):
		var top := 5 - int(float(k) * 0.35)
		for d in range(1, 3):
			var y2 := top - d
			if y2 >= 0:
				body.set_pixel(k, y2, page if d == 2 else page_dk)
		if k == cx - 1:
			for d2 in range(0, 3):
				if top - d2 >= 0:
					body.set_pixel(k, top - d2, Color8(140, 60, 50))
	# the glyphs on the pages (lit when studying), and a mote over the book
	for f in 2:
		var img: Image = fire[f]
		for k2 in range(2, w - 2, 2):
			if k2 == cx - 1:
				continue
			var y3 := 5 - int(float(k2) * 0.35) - 2
			if y3 >= 0 and _h(k2, f) % 3 != 0:
				img.set_pixel(k2, y3, Color(0.6, 0.85, 1.0))
		var my := 0 if f == 0 else 1
		img.set_pixel(cx - 1, my, Color(0.85, 0.95, 1.0))
	# (a little ink on the pages unlit, so the book reads as written in)
	for k3 in range(2, w - 2, 3):
		var y4 := 5 - int(float(k3) * 0.35) - 2
		if y4 >= 0 and k3 != cx - 1:
			body.set_pixel(k3, y4, ink)
