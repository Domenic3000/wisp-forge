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
