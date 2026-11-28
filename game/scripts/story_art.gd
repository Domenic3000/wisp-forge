## The story's illustrated panels (story.gd, cutscene.gd): each grown in code at 320 x 180 from a seed, in the
## game's pixel style (no hand-drawn layouts: skies, ridgelines, trees, fire and the wisp's glow are made from
## parts, so they match the world's own look). `panel(name)` returns the Image; cutscene.gd scales it up crisp.
extends RefCounted

const W := 320
const H := 180

static func panel(name: String) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name) & 0x7fffffff
	match name:
		"hush": _hush_panel(img, rng)
		"fall": _fall_panel(img, rng)
		"camp": _camp_panel(img, rng)
		"wisp": _wisp_panel(img, rng)
		_: img.fill(Color(0.02, 0.02, 0.05))
	return img

# ------------------------------------------------------------------ parts ---
static func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		img.set_pixel(x, y, c)

static func _mix(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x >= 0 and y >= 0 and x < W and y < H and a > 0.0:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(c, clampf(a, 0.0, 1.0)))

## a night sky: dark at the top to a deep teal at the horizon `hz`, in bands (the game's sky has hard bands)
static func _sky(img: Image, hz: int, top: Color, low: Color) -> void:
	for y in H:
		var k := clampf(float(y) / float(maxi(hz, 1)), 0.0, 1.0)
		k = floorf(k * 7.0) / 7.0
		var c := top.lerp(low, k)
		for x in W:
			img.set_pixel(x, y, c)

static func _stars(img: Image, rng: RandomNumberGenerator, n: int, below: int) -> void:
	for k in n:
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(0, below)
		var b := rng.randf()
		var c := Color(1.0, 0.95, 0.85) if b < 0.2 else (Color(0.75, 0.85, 1.0) if b < 0.5 else Color(1, 1, 1))
		_mix(img, x, y, c, 0.35 + b * 0.65)
		if b > 0.93:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_mix(img, x + o.x, y + o.y, c, 0.35)

## the Hush: a patch where the stars are gone, ringed with a faint violet and reaching out in tendrils
static func _hush(img: Image, cx: float, cy: float, r: float, ph: float) -> void:
	var x0 := int(cx - r * 1.6)
	var x1 := int(cx + r * 1.6)
	var y0 := int(cy - r * 1.6)
	var y1 := int(cy + r * 1.6)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var dx := float(x) - cx
			var dy := (float(y) - cy) * 1.1
			var ang := atan2(dy, dx)
			var wob := 1.0 + 0.2 * sin(ang * 5.0 + ph) + 0.12 * sin(ang * 13.0 - ph * 2.0) + 0.3 * maxf(0.0, sin(ang * 3.0 + ph * 0.5)) ** 6.0
			var d := sqrt(dx * dx + dy * dy) / (r * wob)
			if d < 0.92:
				_put(img, x, y, Color(0.008, 0.0, 0.02))
			elif d < 1.25:
				var rim := exp(-pow((d - 1.0) * 7.0, 2.0))
				var band := floorf(rim * 4.0) / 4.0
				_mix(img, x, y, Color(0.42, 0.16, 0.62), band * 0.75)
				if d < 1.0:
					_mix(img, x, y, Color(0.02, 0.0, 0.04), 0.7)

## a ridgeline of hills or mountains from `base` up, by the sum of a few waves; returns nothing, fills below it
static func _ridge(img: Image, rng: RandomNumberGenerator, base: float, amp: float, col: Color, rough: float) -> void:
	var p1 := rng.randf() * TAU
	var p2 := rng.randf() * TAU
	var p3 := rng.randf() * TAU
	for x in W:
		var fx := float(x)
		var h := base - amp * (0.5 + 0.35 * sin(fx * 0.013 + p1) + 0.25 * sin(fx * 0.031 + p2) + rough * 0.15 * sin(fx * 0.11 + p3))
		for y in range(int(h), H):
			_put(img, x, y, col)

## pines along a line: tiered dark triangles of their own heights
static func _pines(img: Image, rng: RandomNumberGenerator, base: float, n: int, hmin: int, hmax: int, col: Color) -> void:
	for k in n:
		var cx := rng.randi_range(-4, W + 4)
		var h := rng.randi_range(hmin, hmax)
		var top := int(base) - h
		for y in range(top, int(base) + 2):
			var t := float(y - top) / float(h)
			var tier := fmod(t * 3.0, 1.0)
			var half := int(1.0 + t * float(h) * 0.28 * (0.6 + 0.4 * tier))
			for x in range(cx - half, cx + half + 1):
				_put(img, x, y, col)
		for y in range(int(base), int(base) + 3):
			_put(img, cx, y, col.darkened(0.2))

## a glow: soft rings banded like the game's light
static func _glow(img: Image, cx: float, cy: float, r: float, col: Color, strength: float) -> void:
	for y in range(int(cy - r), int(cy + r) + 1):
		for x in range(int(cx - r), int(cx + r) + 1):
			var d := Vector2(float(x) - cx, float(y) - cy).length() / r
			if d < 1.0:
				var a := floorf((1.0 - d) * (1.0 - d) * 5.0) / 5.0
				_mix(img, x, y, col, a * strength)

## the wisp: a bright core and a cross of light
static func _wisp(img: Image, cx: int, cy: int, size: int) -> void:
	_glow(img, float(cx), float(cy), float(size) * 6.0, Color(0.35, 0.62, 1.0), 0.75)
	_glow(img, float(cx), float(cy), float(size) * 2.5, Color(0.7, 0.88, 1.0), 0.9)
	for k in range(-size * 2, size * 2 + 1):
		_mix(img, cx + k, cy, Color(0.6, 0.85, 1.0), 0.8 - absf(float(k)) / float(size * 2 + 1) * 0.7)
		_mix(img, cx, cy + k, Color(0.6, 0.85, 1.0), 0.8 - absf(float(k)) / float(size * 2 + 1) * 0.7)
	for y in range(cy - size / 2, cy + size / 2 + 1):
		for x in range(cx - size / 2, cx + size / 2 + 1):
			_put(img, x, y, Color(0.96, 0.99, 1.0))

# ----------------------------------------------------------------- panels ---
## the stars going out: deep space, a band of the galaxy, and the Hush eating into it
static func _hush_panel(img: Image, rng: RandomNumberGenerator) -> void:
	_sky(img, H, Color(0.01, 0.012, 0.04), Color(0.03, 0.035, 0.09))
	# the galaxy's band, a soft diagonal haze of violet and blue
	for y in H:
		for x in W:
			var d := absf(float(y) - (float(x) * 0.35 + 30.0)) / 34.0
			if d < 1.0:
				var n := 0.5 + 0.25 * sin(float(x) * 0.07 + float(y) * 0.11) + 0.25 * sin(float(x) * 0.023 - float(y) * 0.05)
				_mix(img, x, y, Color(0.22, 0.2, 0.42), floorf((1.0 - d) * n * 4.0) / 4.0 * 0.5)
	_stars(img, rng, 420, H - 1)
	_hush(img, 92.0, 92.0, 52.0, 1.3)
	# stars at its edge going dim, one with a dying flicker
	for k in 9:
		var a := rng.randf() * TAU
		var rr := 58.0 + rng.randf() * 10.0
		var sx := int(92.0 + cos(a) * rr)
		var sy := int(92.0 + sin(a) * rr / 1.1)
		_mix(img, sx, sy, Color(0.6, 0.55, 0.8), 0.45)
	_glow(img, 160.0, 64.0, 7.0, Color(0.85, 0.75, 1.0), 0.6)
	_put(img, 160, 64, Color(0.9, 0.85, 1.0))

## a light falling over Verdance's forests by night
static func _fall_panel(img: Image, rng: RandomNumberGenerator) -> void:
	_sky(img, 130, Color(0.015, 0.02, 0.06), Color(0.07, 0.14, 0.2))
	_stars(img, rng, 170, 120)
	_hush(img, 52.0, 30.0, 22.0, 0.4)
	_ridge(img, rng, 128.0, 34.0, Color(0.05, 0.07, 0.11), 1.0)
	_ridge(img, rng, 150.0, 18.0, Color(0.03, 0.05, 0.07), 0.6)
	_pines(img, rng, 156.0, 44, 10, 22, Color(0.02, 0.035, 0.04))
	_ridge(img, rng, 176.0, 8.0, Color(0.01, 0.02, 0.02), 0.3)
	# the falling light: a long tail from the upper right, its head bright
	var hx := 196.0
	var hy := 92.0
	for k in 120:
		var t := float(k) / 120.0
		var x := hx + t * 110.0
		var y := hy - t * 78.0
		var a := (1.0 - t) * (1.0 - t)
		_mix(img, int(x), int(y), Color(0.65, 0.85, 1.0), a * 0.9)
		_mix(img, int(x), int(y) + 1, Color(0.4, 0.6, 1.0), a * 0.5)
		if k % 9 == 0:
			_mix(img, int(x) + rng.randi_range(-3, 3), int(y) + rng.randi_range(1, 5), Color(0.8, 0.9, 1.0), a * 0.6)
	_wisp(img, int(hx), int(hy), 2)

## the young mage's fire, and the light come to rest beside it
static func _camp_panel(img: Image, rng: RandomNumberGenerator) -> void:
	_sky(img, 120, Color(0.012, 0.016, 0.05), Color(0.05, 0.09, 0.13))
	_stars(img, rng, 150, 100)
	_ridge(img, rng, 116.0, 22.0, Color(0.035, 0.05, 0.08), 0.8)
	_pines(img, rng, 132.0, 26, 18, 38, Color(0.02, 0.03, 0.04))
	for y in range(132, H):
		for x in W:
			_put(img, x, y, Color(0.03, 0.035, 0.04).lerp(Color(0.05, 0.045, 0.04), float(y - 132) / 48.0))
	# the fire's light on the ground and the trees
	_glow(img, 168.0, 146.0, 70.0, Color(0.95, 0.5, 0.18), 0.45)
	# logs and flames
	for x in range(158, 179):
		_put(img, x, 150, Color(0.25, 0.14, 0.07))
		_put(img, x, 151, Color(0.18, 0.1, 0.05))
	for k in 70:
		var fx := 168.0 + (rng.randf() - 0.5) * 14.0
		var h := 3.0 + rng.randf() * 14.0 * (1.0 - absf(fx - 168.0) / 8.0)
		var fy := 149.0 - rng.randf() * h
		var t := (149.0 - fy) / maxf(h, 1.0)
		_put(img, int(fx), int(fy), Color(1.0, 0.95, 0.55).lerp(Color(0.95, 0.35, 0.1), t))
	# the mage, sitting at the fire's left: a pointed hat, a cloak, a staff leant beside, lit on the fire's side
	var mx := 140
	var my := 150
	var cloak := Color(0.16, 0.14, 0.34)
	var lit := Color(0.5, 0.36, 0.42)
	for y in range(my - 18, my):
		var w := int(2.0 + float(y - (my - 18)) * 0.42)
		for x in range(mx - w, mx + w + 1):
			_put(img, x, y, lit if x > mx + w - 2 else cloak)
	for y in range(my - 31, my - 17):
		var w2 := int(float(y - (my - 31)) * 0.45)
		for x in range(mx - w2 - 2, mx + w2 + 1):
			_put(img, x, y, Color(0.2, 0.18, 0.46) if x < mx + w2 - 1 else Color(0.55, 0.4, 0.5))
	for x in range(mx - 8, mx + 7):
		_put(img, x, my - 17, Color(0.24, 0.2, 0.5))
	_put(img, mx + 2, my - 14, Color(0.95, 0.85, 0.7))          # (a face in the firelight)
	for y in range(my - 34, my + 1):
		_put(img, mx - 9, y, Color(0.35, 0.22, 0.12))
	_put(img, mx - 9, my - 35, Color(0.6, 0.85, 1.0))
	# the wisp, come down beside the fire
	_wisp(img, 188, 122, 2)

## the wisp up close, frightened and bright, the dark at the edges
static func _wisp_panel(img: Image, rng: RandomNumberGenerator) -> void:
	img.fill(Color(0.01, 0.01, 0.03))
	_stars(img, rng, 90, H - 1)
	for y in H:
		for x in W:
			var e := minf(minf(float(x), float(W - 1 - x)), minf(float(y), float(H - 1 - y)))
			var ang := atan2(float(y) - 90.0, float(x) - 160.0)
			var reach := 26.0 + 12.0 * sin(ang * 7.0) + 8.0 * sin(ang * 17.0 + 1.0)
			if e < reach:
				_mix(img, x, y, Color(0.008, 0.0, 0.02), floorf((1.0 - e / reach) * 4.0) / 4.0 * 0.95)
	_glow(img, 160.0, 90.0, 80.0, Color(0.2, 0.36, 0.8), 0.45)
	_wisp(img, 160, 90, 6)
	for k in 14:
		var a := rng.randf() * TAU
		var rr := 18.0 + rng.randf() * 34.0
		_mix(img, int(160.0 + cos(a) * rr), int(90.0 + sin(a) * rr * 0.8), Color(0.8, 0.92, 1.0), 0.8)
