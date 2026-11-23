## The guardians' bodies, grown from parts into pixel frames (no hand-drawn sprites).
##
## `frames(id, body)` draws every frame a guardian needs into Images, keyed "<id>", "<id>_walk0".. etc.
## A body plan (body["plan"]) puts parts together: blobs (shaded ellipses with a skin: fur, moss,
## warts, spots, scales), limbs (tapered capsules), polygons (horns, beaks, feathers, spikes), eyes;
## a dark outline goes round the whole. Plans and their features:
##   beast   four legs, a neck and head; antlers (forest), a mane (savanna), crystal spikes along the
##           back (tundra), ears, a short, long or tufted tail. Frames: idle, walk0-3, wind (head
##           down, crouched, jaws open), air (legs tucked)
##   bird    body, hooked beak, crest, two wings and a fanned tail. Frames: fly0-3 (wingbeat), wind
##           (wings raised, talons out), dive (wings swept back)
##   toad    a broad squat body, eyes on top, throat sac, folded hind legs. Frames: idle, walk0-3
##           (a hop's squash and stretch), wind (crouched, sac puffed), air
##   fungus  a stalk on writhing roots under a spotted cap, eyes in the stalk. Frames: idle, walk0-3, wind, air
##   serpent a head (head, head_open) and round body segments (seg0..segN-1, shrinking to the tail),
##           drawn along its trail by overlay.gd
## The art faces right; overlay.gd mirrors it. Feet rest on the bottom row (the sprite hangs from them).
extends RefCounted

# --------------------------------------------------------------- canvas ---
class Canvas:
	var img: Image
	var w := 0
	var h := 0
	var seed_ := 0
	func _init(ww: int, hh: int, sd: int) -> void:
		w = ww
		h = hh
		seed_ = sd
		img = Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))

	func px(x: int, y: int, c: Color) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			img.set_pixel(x, y, c)

	func hash01(x: int, y: int) -> float:
		var n := (x * 374761393 + y * 668265263 + seed_ * 2147483) & 0x7fffffff
		n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
		return float(n & 0xffff) / 65535.0

	## four tones, light from the upper left: s 0 (shadow) .. 1 (lit)
	func tone(base: Color, s: float) -> Color:
		if s < 0.22:
			return base.darkened(0.42)
		if s < 0.48:
			return base.darkened(0.2)
		if s < 0.8:
			return base
		return base.lightened(0.17)

	## a skin's pattern over a lit pixel
	func skin(c: Color, kind: String, alt: Color, x: int, y: int, s: float) -> Color:
		var r := hash01(x, y)
		match kind:
			"fur":
				if (x + int(r * 3.0)) % 3 == 0 and r < 0.6:
					return c.darkened(0.12)
			"moss":
				if r < 0.2 + 0.25 * s:
					return tone(alt, s)
			"warts":
				if r < 0.07:
					return c.lightened(0.25)
				if r > 0.95:
					return c.darkened(0.25)
			"spots":
				if hash01(x / 4, y / 4) < 0.22 and r < 0.85:
					return tone(alt, s).lightened(0.1)
			"scales":
				if (x + y * 2) % 4 == 0:
					return c.darkened(0.15)
		return c

	## a shaded ellipse (turned by rot), with a skin
	func blob(cx: float, cy: float, rx: float, ry: float, base: Color, kind := "", alt := Color(), rot := 0.0, top_only := false) -> void:
		var ext := maxf(rx, ry) + 1.0
		var cr := cos(-rot)
		var sr := sin(-rot)
		for y in range(int(cy - ext), int(cy + ext) + 1):
			for x in range(int(cx - ext), int(cx + ext) + 1):
				var ox := x + 0.5 - cx
				var oy := y + 0.5 - cy
				var lx := ox * cr - oy * sr
				var ly := ox * sr + oy * cr
				var u := lx / rx
				var v := ly / ry
				var d := u * u + v * v
				if d > 1.0 or (top_only and ly > 0.0):
					continue
				var s := 0.6 - 0.5 * (u * 0.5 + v * 0.75) - (0.18 if d > 0.72 else 0.0)
				px(x, y, skin(tone(base, s), kind, alt, x, y, s))

	## a tapered capsule from a (radius r0) to b (radius r1), shaded across its width
	func limb(a: Vector2, b: Vector2, r0: float, r1: float, base: Color, kind := "", alt := Color()) -> void:
		var ab := b - a
		var l2 := maxf(ab.length_squared(), 0.0001)
		var ext := maxf(r0, r1) + 1.0
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(ext, ext)
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(ext, ext)
		for y in range(int(lo.y), int(hi.y) + 1):
			for x in range(int(lo.x), int(hi.x) + 1):
				var p := Vector2(x + 0.5, y + 0.5)
				var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
				var q := a + ab * t
				var r := lerpf(r0, r1, t)
				var o := p - q
				if o.length() > r:
					continue
				var n := o / maxf(r, 0.5)
				var s := 0.62 - 0.5 * (n.x * 0.5 + n.y * 0.75)
				px(x, y, skin(tone(base, s), kind, alt, x, y, s))

	func poly(pts: PackedVector2Array, c: Color, shade := true) -> void:
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
		for y in range(int(lo.y), int(hi.y) + 1):
			for x in range(int(lo.x), int(hi.x) + 1):
				var p2 := Vector2(x + 0.5, y + 0.5)
				if Geometry2D.is_point_in_polygon(p2, pts):
					var s := 0.65 - 0.5 * ((p2.y - lo.y) / maxf(hi.y - lo.y, 1.0) - 0.5) if shade else 0.6
					px(x, y, tone(c, s))

	func line(a: Vector2, b: Vector2, c: Color, thick := 1.0) -> void:
		var n := int(ceil(a.distance_to(b) * 2.0)) + 1
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			if thick <= 1.0:
				px(int(p.x), int(p.y), c)
			else:
				for dy in range(-1, 1):
					for dx in range(-1, 1):
						if Vector2(dx + 0.5, dy + 0.5).length() <= thick * 0.6:
							px(int(p.x) + dx, int(p.y) + dy, c)

	## a glowing eye: a bright pixel pair with a dark pupil edge
	func eye(x: float, y: float, c: Color) -> void:
		px(int(x), int(y), c.lightened(0.4))
		px(int(x) + 1, int(y), c)
		px(int(x), int(y) + 1, c.darkened(0.3))

	## a dark outline round every drawn pixel
	func outline(c: Color) -> void:
		var src := img.duplicate()
		for y in h:
			for x in w:
				if src.get_pixel(x, y).a > 0.5:
					continue
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + o
					if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and src.get_pixel(q.x, q.y).a > 0.5:
						img.set_pixel(x, y, c)
						break

# ---------------------------------------------------------------- frames ---
static func frames(id: String, b: Dictionary) -> Dictionary:
	var out := {}
	var sd := id.hash() & 0xffff
	match String(b["plan"]):
		"beast":
			out[id] = _beast(b, sd, {})
			for k in 4:
				out["%s_walk%d" % [id, k]] = _beast(b, sd, {"phase": float(k) / 4.0, "bob": 1.0 if k % 2 == 1 else 0.0})
			out[id + "_wind"] = _beast(b, sd, {"lower": 1.0, "crouch": 0.6, "mouth": 1.0})
			out[id + "_air"] = _beast(b, sd, {"tuck": 1.0, "mouth": 1.0})
			# its daily life (ecology.gd): head down to the grass or the water, and asleep, lying down
			out[id + "_graze"] = _beast(b, sd, {"graze": 1.0, "crouch": 0.15})
			# (asleep its head lies low in front and its ears and antlers lie back: held up, over a body flat on
			# the ground they read as legs in the air, and deer and hares looked upside down: user, 22 Nov)
			out[id + "_sleep"] = _beast(b, sd, {"crouch": 1.0, "lie": 1.0, "graze": 0.9, "shut": 1.0})
		"toad":
			out[id] = _toad(b, sd, {})
			for k in 4:
				out["%s_walk%d" % [id, k]] = _toad(b, sd, {"squash": [0.15, 0.0, -0.12, 0.0][k]})
			out[id + "_wind"] = _toad(b, sd, {"squash": 0.3, "sac": 1.0})
			out[id + "_air"] = _toad(b, sd, {"squash": -0.25, "legs": 1.0})
			out[id + "_croak"] = _toad(b, sd, {"sac": 1.0})
			out[id + "_crouch"] = _toad(b, sd, {"squash": 0.22})
			out[id + "_sleep"] = _toad(b, sd, {"squash": 0.18, "shut": 1.0})
		"fungus":
			out[id] = _fungus(b, sd, {})
			for k in 4:
				out["%s_walk%d" % [id, k]] = _fungus(b, sd, {"phase": float(k) / 4.0})
			out[id + "_wind"] = _fungus(b, sd, {"swell": 1.0})
			out[id + "_air"] = _fungus(b, sd, {"phase": 0.25, "tuck": 1.0})
		"bird":
			for k in 4:
				out["%s_fly%d" % [id, k]] = _bird(b, sd, {"flap": [1.0, 0.3, -0.8, 0.2][k]})
			out[id] = out[id + "_fly0"]
			out[id + "_wind"] = _bird(b, sd, {"flap": 1.25, "talons": 1.0})
			out[id + "_dive"] = _bird(b, sd, {"flap": 0.0, "swept": 1.0, "talons": 1.0})
			out[id + "_perch"] = _bird(b, sd, {"fold": 1.0, "talons": 1.0})
			out[id + "_sleep"] = _bird(b, sd, {"fold": 1.0, "talons": 1.0, "shut": 1.0})
		"serpent":
			out[id + "_head"] = _serpent_head(b, sd, false)
			out[id + "_head_open"] = _serpent_head(b, sd, true)
			var n: int = int(b.get("segs", 10))
			for k in n:
				out["%s_seg%d" % [id, k]] = _segment(b, sd, seg_radius(b, k), k)
			out[id] = out[id + "_head"]
	return out

## One pose for a statue of the guardian at its lair (lairs.gd carves it in stone): a beast with its
## jaws open, a toad croaking, a fungus swollen, a bird with its wings raised, a serpent reared up out of
## its coils. Cropped to the figure; it faces right.
static func statue(id: String, b: Dictionary) -> Image:
	var sd := id.hash() & 0xffff
	var img: Image
	match String(b["plan"]):
		"beast":
			img = _beast(b, sd, {"mouth": 1.0, "lower": 0.25})
		"toad":
			img = _toad(b, sd, {"sac": 1.0})
		"fungus":
			img = _fungus(b, sd, {"swell": 0.6})
		"bird":
			img = _bird(b, sd, {"flap": 1.25, "talons": 1.0})
		"serpent":
			img = _serpent_reared(b, sd)
		_:
			return null
	var ur := img.get_used_rect()
	if ur.size.x <= 0 or ur.size.y <= 0:
		return null
	return img.get_region(ur)

## a serpent reared up: its tail curled on the ground, its body rising in an S, its head on top, jaws open
static func _serpent_reared(b: Dictionary, sd: int) -> Image:
	var n: int = int(b.get("segs", 10))
	var r: float = float(b["rad"])
	var head := _serpent_head(b, sd, true)
	var rise := r * float(n) * 0.62
	var W := int(r * 9.0) + head.get_width() + 8
	var H := int(rise + r * 3.0) + head.get_height() + 8
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var base := Vector2(float(W) * 0.38, float(H) - r * 1.3 - 2.0)
	var pts := []
	for k in n:
		var t := 1.0 - float(k) / float(maxi(1, n - 1))          # 0 at the tail, 1 behind the head
		pts.append(base + Vector2(sin(t * PI * 1.7) * r * 2.4 * (1.0 - t * 0.45), -t * rise))
	for k2 in range(n - 1, -1, -1):
		var sg := _segment(b, sd, seg_radius(b, k2), k2)
		var at: Vector2 = pts[k2] - Vector2(sg.get_width(), sg.get_height()) * 0.5
		img.blend_rect(sg, Rect2i(Vector2i.ZERO, sg.get_size()), Vector2i(at.round()))
	var hp: Vector2 = pts[0] + Vector2(r * 0.4, -r * 0.7) - Vector2(float(head.get_width()) * 0.35, float(head.get_height()) * 0.55)
	img.blend_rect(head, Rect2i(Vector2i.ZERO, head.get_size()), Vector2i(hp.round()))
	return img

## how far below its picture's middle a bird's perched talons reach (cells): where it stands on a branch
static func bird_feet(b: Dictionary) -> float:
	var L: float = b["len"]
	var S: float = b["span"]
	var H := int(S * 1.4 + 16.0)
	return float(H) * 0.58 + L * 0.18 + 8.0 * minf(1.0, L / 12.0) - float(int(float(H) * 0.5))

## a serpent's k-th segment radius (cells): full behind the head, thinning to the tail
static func seg_radius(b: Dictionary, k: int) -> float:
	var n: int = int(b.get("segs", 10))
	var r: float = float(b["rad"])
	return maxf(minf(2.0, r * 0.6), r * (1.0 - 0.7 * pow(float(k) / float(n), 1.4)))

static func _cols(b: Dictionary) -> Array:
	return [Color(b["base"]), Color(b["belly"]), Color(b["accent"]), Color(b["dark"]), Color(b["eye"])]

# ---------------------------------------------------------------- beast ---
## how far a beast's tail reaches behind its rump (cells)
static func _tail_len(kind: String, L: float) -> float:
	match kind:
		"long":
			return clampf(L * 0.75, 9.0, 22.0)
		"tuft":
			return clampf(L * 0.5, 7.0, 13.0)
	return clampf(L * 0.28, 4.0, 7.0)

## A tail from its root `a`, `len` cells back: a chain of short tapering limbs along a curve, leaving at
## `lift` (radians above straight back; negative droops) and turning up by `bend` along its length, swaying
## with the walk; its radius runs from r0 to a point. Returns the tip.
static func _tail(c, a: Vector2, tlen: float, r0: float, lift: float, bend: float, ph: float, bob: float, base: Color, skin: String, acc: Color) -> Vector2:
	var n := maxi(3, int(tlen / 2.5))
	var sway := sin(TAU * ph) * 0.25
	var prev := a
	var ang := PI + lift                      # (screen y is down: PI + x points back and up)
	for k in n:
		var t1 := float(k + 1) / float(n)
		var seg := tlen / float(n)
		ang += (bend + sway) / float(n)
		var p := prev + Vector2(cos(ang), sin(ang)) * seg + Vector2(0.0, -bob * t1 * 0.5)
		var ra := lerpf(r0, 0.5, float(k) / float(n))
		var rb := lerpf(r0, 0.5, t1)
		c.limb(prev, p, ra, rb, base, skin, acc)
		prev = p
	return prev
static func _beast(b: Dictionary, sd: int, pose: Dictionary) -> Image:
	var cs := _cols(b)
	var base: Color = cs[0]
	var belly: Color = cs[1]
	var acc: Color = cs[2]
	var dark: Color = cs[3]
	var L: float = b["len"]
	var T: float = b["tall"]
	var leg: float = b["leg"]
	var hd: float = b["head"]
	var neck: float = b["neck"]
	var skin: String = b.get("skin", "")
	var ant: int = int(b.get("antlers", 0))
	var tail := String(b.get("tail", "short"))
	var tl := _tail_len(tail, L)
	# (the fixed-size details shrink with a small body, so a hare is drawn as a hare, not a dog's parts:
	# user, 21 Nov, creatures true to size beside you)
	var ks := minf(1.0, L / 18.0)
	# room for the tail behind: both sides grow alike, so the body keeps its place in the frame
	var pad := maxf(0.0, ceilf(tl + (3.0 if tail == "tuft" else 1.0) - 6.0))
	var W := int(L + hd * 3.0 + 14.0 + pad * 2.0)
	var H := int(leg + T + neck + hd * 2.0 + (ant * 5) + 8.0 + (hd if b.get("long_ears", false) else 0.0))
	var c := Canvas.new(W, H, sd)
	var ph: float = pose.get("phase", 0.0)
	var crouch: float = pose.get("crouch", 0.0)
	var lower: float = pose.get("lower", 0.0)
	var tuck: float = pose.get("tuck", 0.0)
	var bob: float = pose.get("bob", 0.0)
	var ground := float(H) - 2.0
	var lie: float = pose.get("lie", 0.0)
	var graze: float = pose.get("graze", 0.0)
	var lg := leg * (1.0 - 0.3 * crouch) * (1.0 - 0.35 * tuck) * (1.0 - 0.75 * lie)
	var cx := 6.0 + pad + L * 0.5 + 2.0
	var cy := ground - lg - T * 0.42 + bob - tuck * leg * 0.25
	# the legs on the far side first, darker
	var hips := [Vector2(cx - L * 0.32, cy + T * 0.18), Vector2(cx + L * 0.3, cy + T * 0.18)]
	for side in [1, 0]:
		for hi in 2:
			var hip: Vector2 = hips[hi] + Vector2(-2.0 if side == 1 else 0.0, -1.0 if side == 1 else 0.0)
			var off := 0.5 * float(side) + 0.25 * float(hi)
			var sw := sin(TAU * (ph + off)) * 0.5 * (1.0 - tuck)
			var foot := Vector2(hip.x + sin(sw) * lg * 0.7 + tuck * (4.0 if hi == 0 else -4.0) * ks, minf(ground, hip.y + lg))
			if tuck > 0.0:
				foot.y = hip.y + lg * 0.75
			var knee := (hip + foot) * 0.5 + Vector2((2.5 if hi == 1 else -2.5) * (1.0 - tuck * 0.5) * ks, 0.0)
			var lc := base.darkened(0.3) if side == 1 else base
			c.limb(hip, knee, T * 0.26, T * 0.17, lc, skin, acc)
			c.limb(knee, foot, T * 0.17, T * 0.12, lc, skin, acc)
			c.blob(foot.x + ks, foot.y - 0.5, T * 0.16, maxf(0.7, 1.5 * ks), dark)
	# the tail: sized to the body, curving and tapering to a point (it used to be a fixed length, so a small
	# beast's ran off the picture's edge and was cut square)
	var tb := Vector2(cx - L * 0.5 + 1.0, cy - T * 0.15)
	var tr0 := clampf(T * 0.3, 1.2, 3.0)
	match tail:
		"short":
			_tail(c, tb, tl, tr0, 0.6, 0.0, ph, bob, base, skin, acc)
		"long":
			_tail(c, tb, tl, tr0, -0.25, 0.7, ph, bob, base, skin, acc)
		"tuft":
			var tip := _tail(c, tb, tl, tr0 * 0.6, -0.7, 0.6, ph, bob, base, "", acc)
			c.blob(tip.x - 0.5, tip.y + 0.5, 2.6 * ks, 2.6 * ks, acc, "fur")
	# the body
	c.blob(cx, cy, L * 0.5, T * 0.5, base, skin, acc)
	c.blob(cx + 1.0, cy + T * 0.24, L * 0.36, T * 0.2, belly, skin, acc)
	# spikes of crystal along the back
	var nsp: int = int(b.get("spikes", 0))
	for kspk in nsp:
		var t := float(kspk + 1) / float(nsp + 1)
		var bx := cx - L * 0.38 + t * L * 0.72
		var by := cy - T * 0.5 * sqrt(maxf(0.0, 1.0 - pow((bx - cx) / (L * 0.5), 2.0))) + 1.0
		var hgt := (4.0 + 3.0 * sin(t * PI)) * ks
		c.poly(PackedVector2Array([Vector2(bx - 2.0 * ks, by + 1.0), Vector2(bx + 0.5 * ks, by - hgt), Vector2(bx + 2.5 * ks, by + 1.0)]), acc)
	# the near legs
	for hi2 in 2:
		var hip2: Vector2 = hips[hi2]
		var sw2 := sin(TAU * (ph + 0.25 * float(hi2))) * 0.5 * (1.0 - tuck)
		var foot2 := Vector2(hip2.x + sin(sw2) * lg * 0.7 + tuck * (4.0 if hi2 == 0 else -4.0) * ks, minf(ground, hip2.y + lg))
		if tuck > 0.0:
			foot2.y = hip2.y + lg * 0.75
		var knee2 := (hip2 + foot2) * 0.5 + Vector2((2.5 if hi2 == 1 else -2.5) * (1.0 - tuck * 0.5) * ks, 0.0)
		c.limb(hip2, knee2, T * 0.28, T * 0.18, base, skin, acc)
		c.limb(knee2, foot2, T * 0.18, T * 0.13, base, skin, acc)
		c.blob(foot2.x + ks, foot2.y - 0.5, T * 0.17, maxf(0.7, 1.6 * ks), dark)
	# neck and head (lowered to charge)
	var nb := Vector2(cx + L * 0.36, cy - T * 0.12)
	var hp := Vector2(cx + L * 0.5 + hd * 0.55, cy - T * 0.4 - neck)
	hp = hp.lerp(Vector2(cx + L * 0.5 + hd * 0.9, cy + T * 0.05), lower)
	hp = hp.lerp(Vector2(cx + L * 0.5 + hd * 0.75, ground - hd * 0.55), graze)    # (nose to the ground)
	if b.get("mane", false):
		c.blob(hp.x - hd * 0.5, hp.y + hd * 0.25, hd * 1.15, hd * 1.2, acc, "fur", acc.darkened(0.3))
	c.limb(nb, hp, T * 0.34, hd * 0.45, base, skin, acc)
	c.blob(hp.x, hp.y, hd * 0.72, hd * 0.56, base, skin, acc)
	var sn := hp + Vector2(hd * 0.62, hd * 0.18)
	c.blob(sn.x, sn.y, hd * 0.48, hd * 0.32, belly.lerp(base, 0.4), skin, acc)
	var mouth: float = pose.get("mouth", 0.0)
	if mouth > 0.0:
		c.poly(PackedVector2Array([sn + Vector2(-hd * 0.3, ks), sn + Vector2(hd * 0.55, 0.0), sn + Vector2(hd * 0.45, 3.5 * ks)]), Color(0.25, 0.04, 0.06), false)
		c.px(int(sn.x + hd * 0.2), int(sn.y + 1.0), Color(0.95, 0.92, 0.85))
	c.px(int(sn.x + hd * 0.42), int(sn.y - 1.0), dark)
	if b.get("tusks", false):
		# a boar's tusks curling up from the jaw
		var tb2 := sn + Vector2(hd * 0.1, hd * 0.25)
		c.poly(PackedVector2Array([tb2, tb2 + Vector2(hd * 0.35, -hd * 0.1), tb2 + Vector2(hd * 0.5, -hd * 0.55), tb2 + Vector2(hd * 0.2, 0.0)]), Color(0.95, 0.92, 0.82))
	if b.get("horns", false):
		# a ram's horns, curled round beside the head
		var hc := hp + Vector2(-hd * 0.25, -hd * 0.3)
		var prev := hc
		for k5 in 9:
			var aa := -1.9 + float(k5) * 0.62
			var rr := hd * (0.75 - 0.05 * float(k5))
			var q := hc + Vector2(cos(aa), sin(aa)) * rr
			c.line(prev, q, belly.darkened(0.25), 2.0 if k5 < 6 and ks > 0.6 else 1.0)
			prev = q
	if b.get("long_ears", false):
		# a hare's: long, laid back a little, the far one darker
		for side3 in [1, 0]:
			var eb := hp + Vector2(-hd * (0.2 + 0.2 * side3), -hd * 0.3)
			var tip3 := eb + Vector2(-hd * (0.55 + 0.15 * side3), -hd * 1.7).lerp(Vector2(-hd * (1.7 + 0.2 * side3), -hd * (0.45 - 0.15 * side3)), lie)
			c.limb(eb, tip3, maxf(0.7, 1.3 * ks * 1.6), maxf(0.5, 0.9 * ks * 1.6), base.darkened(0.25 * side3))
			if side3 == 0:
				c.line(eb + Vector2(0.0, -1.0), tip3 + Vector2(0.5, 1.0), belly.lerp(Color(0.95, 0.7, 0.7), 0.4))
	elif b.get("ears", false) or b.get("mane", false):
		c.poly(PackedVector2Array([hp + Vector2(-hd * 0.45, -hd * 0.3), hp + Vector2(-hd * 0.2, -hd * 1.0), hp + Vector2(hd * 0.05, -hd * 0.35)]), base)
	if pose.get("shut", 0.0) > 0.0:
		c.line(Vector2(hp.x + hd * 0.02, hp.y - hd * 0.15), Vector2(hp.x + hd * 0.3, hp.y - hd * 0.15), dark)
	else:
		c.eye(hp.x + hd * 0.12, hp.y - hd * 0.2, cs[4])
	# antlers: a beam each side, tines off it, moss and leaves hanging on them
	var sides: Array = [0, 1] if ant > 0 else []
	for side2 in sides:
		var root := hp + Vector2(-hd * (0.15 + 0.25 * side2), -hd * 0.45)
		var dirn := Vector2(-0.35 - 0.25 * side2 - 0.9 * lie, -1.0 + 0.35 * lie).normalized()
		var p0 := root
		for k2 in ant:
			var p1 := p0 + dirn * (6.0 - k2 * 0.6) * ks
			c.line(p0, p1, belly.darkened(0.15 + 0.2 * side2), 2.0 if ks > 0.6 else 1.0)
			var tine := p1 + Vector2(3.5 - side2, -3.0) * ks
			c.line(p1, tine, belly.darkened(0.1 + 0.2 * side2), 1.0)
			if c.hash01(k2, side2) < 0.7 and ks > 0.6:
				c.blob(p1.x, p1.y + 1.5, 1.8, 1.4, acc, "moss", acc.darkened(0.3))
			p0 = p1
			dirn = dirn.rotated(0.32)
	c.outline(Color(0.06, 0.04, 0.05))
	return c.img

# ----------------------------------------------------------------- toad ---
static func _toad(b: Dictionary, sd: int, pose: Dictionary) -> Image:
	var cs := _cols(b)
	var L: float = b["len"]
	var T: float = b["tall"]
	var W := int(L + 16.0)
	var H := int(T * 1.5 + 10.0)
	var c := Canvas.new(W, H, sd)
	var kt := minf(1.0, L / 15.0)          # (fixed details shrink with a small frog)
	var sq: float = pose.get("squash", 0.0)
	var ground := float(H) - 2.0
	var rx := L * 0.5 * (1.0 + sq * 0.3)
	var ry := T * 0.5 * (1.0 - sq)
	var cx := float(W) * 0.5 - 2.0
	var cy := ground - ry - (6.0 * kt if pose.get("legs", 0.0) > 0.0 else 1.0)
	# hind leg folded at the back, stretched when it leaps
	if pose.get("legs", 0.0) > 0.0:
		c.limb(Vector2(cx - rx * 0.6, cy + ry * 0.3), Vector2(cx - rx * 1.05, ground), maxf(0.8, 5.0 * kt), maxf(0.6, 2.5 * kt), cs[0].darkened(0.15), "warts")
	else:
		c.blob(cx - rx * 0.62, ground - ry * 0.45, rx * 0.42, ry * 0.5, cs[0].darkened(0.12), "warts")
	c.blob(cx, cy, rx, ry, cs[0], b.get("skin", ""), cs[2])
	c.blob(cx + rx * 0.15, cy + ry * 0.45, rx * 0.7, ry * 0.4, cs[1])
	# throat sac
	var sac: float = pose.get("sac", 0.0)
	if sac > 0.0:
		c.blob(cx + rx * 0.55, cy + ry * 0.45, rx * 0.35, ry * 0.4, cs[1].lightened(0.15))
	# front leg
	c.limb(Vector2(cx + rx * 0.45, cy + ry * 0.3), Vector2(cx + rx * 0.62, ground), maxf(0.6, 3.2 * kt), maxf(0.5, 2.2 * kt), cs[0])
	c.blob(cx + rx * 0.7, ground - 0.5, maxf(0.8, 3.0 * kt), maxf(0.6, 1.4 * kt), cs[3])
	# eyes on top, the mouth a long dark line
	for k2e in 2:
		var ex := cx + rx * (0.3 + 0.28 * k2e)
		var ey := cy - ry * (0.78 - 0.08 * k2e)
		c.blob(ex, ey, maxf(1.0, 3.6 * kt), maxf(0.9, 3.0 * kt), cs[0].darkened(0.1 * k2e))
		if pose.get("shut", 0.0) > 0.0:
			c.line(Vector2(ex - 2.0 * kt, ey - 0.5), Vector2(ex + kt, ey - 0.5), cs[3])
		elif kt < 0.5:
			c.px(int(ex), int(ey - 0.5), cs[4])          # (a small frog's eye: one bright pixel)
		else:
			c.eye(ex - 0.5, ey - 1.0, cs[4])
	c.line(Vector2(cx + rx * 0.2, cy + ry * 0.12), Vector2(cx + rx * 0.98, cy - ry * 0.05), cs[3], 1.0)
	c.outline(Color(0.05, 0.05, 0.03))
	return c.img

# --------------------------------------------------------------- fungus ---
static func _fungus(b: Dictionary, sd: int, pose: Dictionary) -> Image:
	var cs := _cols(b)
	var L: float = b["len"]
	var T: float = b["tall"]
	var W := int(L + 18.0)
	var H := int(T + 8.0)
	var c := Canvas.new(W, H, sd)
	var kf := minf(1.0, L / 12.0)         # (fixed details shrink with a small one)
	var ph: float = pose.get("phase", 0.0)
	var swell: float = pose.get("swell", 0.0)
	var ground := float(H) - 2.0
	var cx := float(W) * 0.5
	var tk: float = pose.get("tuck", 0.0)
	var base_y := ground - (4.0 + tk * 4.0) * kf
	# roots: writhing legs
	for k in 5:
		var a := -0.9 + 0.45 * k
		var wig := sin(TAU * (ph + k * 0.23)) * 2.5 * kf
		var r0 := Vector2(cx + a * 4.0 * kf, base_y)
		var r1 := Vector2(cx + a * 11.0 * kf + wig, ground - 1.0)
		var mid := (r0 + r1) * 0.5 + Vector2(0, (-2.0 + wig * 0.3) * kf)
		c.limb(r0, mid, maxf(0.6, 2.4 * kf), maxf(0.5, 1.6 * kf), cs[1].darkened(0.25))
		c.limb(mid, r1, maxf(0.5, 1.6 * kf), maxf(0.4, 1.0 * kf), cs[1].darkened(0.3))
	# the stalk
	var top := Vector2(cx, ground - T * 0.62)
	c.limb(Vector2(cx, base_y), top, (6.0 + swell) * kf, maxf(0.8, 4.5 * kf), cs[1], "scales")
	if kf < 0.6:
		c.px(int(cx + 1.0), int(top.y + T * 0.25), cs[4])
	else:
		c.eye(cx + 1.0 * kf, top.y + T * 0.2, cs[4])
		c.eye(cx + 4.0 * kf, top.y + T * 0.19, cs[4])
		c.line(Vector2(cx - 1.0 * kf, top.y + T * 0.3), Vector2(cx + 5.0 * kf, top.y + T * 0.3), cs[3])
	# the cap: a dome, gills under it, spots on it
	var capr := L * 0.5 * (1.0 + 0.12 * swell)
	c.blob(cx, top.y + 2.0 * kf, capr, T * 0.32, cs[1].darkened(0.35), "", Color(), 0.0, false)
	c.blob(cx, top.y + kf, capr, T * 0.38 * (1.0 + 0.1 * swell), cs[0], "spots", cs[2], 0.0, true)
	c.outline(Color(0.06, 0.03, 0.08))
	return c.img

# ----------------------------------------------------------------- bird ---
static func _bird(b: Dictionary, sd: int, pose: Dictionary) -> Image:
	var cs := _cols(b)
	var L: float = b["len"]
	var S: float = b["span"]
	var W := int(L + S * 0.7 + 20.0)
	var H := int(S * 1.4 + 16.0)
	var c := Canvas.new(W, H, sd)
	var flap: float = pose.get("flap", 0.0)
	var swept: float = pose.get("swept", 0.0)
	var cx := float(W) * 0.48
	var cy := float(H) * 0.58
	var kb := minf(1.0, L / 12.0)          # (fixed details shrink with a small bird)
	var root := Vector2(cx - 2.0 * kb, cy - 3.0 * kb)
	# far wing, darker; then tail, body, near wing
	var wing := func(dark_by: float, lift: float) -> void:
		var ang := -PI * 0.5 - (flap * 0.9) + swept * 1.6 + lift
		var dirv := Vector2(cos(ang), sin(ang))
		var back := Vector2(-1.0, 0.0)
		var tip := root + dirv * S * (1.0 - 0.45 * swept) + back * S * 0.25
		var pts := PackedVector2Array([root + Vector2(4.0 * kb, 0.0), tip])
		for kw in 5:
			var t := float(kw) / 4.0
			var edge := tip.lerp(root + back * 10.0 * kb, t)
			pts.append(edge + back.rotated(-0.6) * 3.0 * kb * (1.0 if kw % 2 == 0 else 0.3))
		pts.append(root + back * 8.0 * kb)
		c.poly(pts, cs[0].darkened(dark_by))
		c.line(root, tip, cs[1].darkened(dark_by + 0.1))
	var fold: float = pose.get("fold", 0.0)
	if fold <= 0.0:
		wing.call(0.35, 0.25)
	c.poly(PackedVector2Array([Vector2(cx - L * 0.4, cy), Vector2(cx - L * 0.75, cy - 5.0 * kb), Vector2(cx - L * 0.8, cy + 4.0 * kb), Vector2(cx - L * 0.7, cy + 7.0 * kb)]), cs[0].darkened(0.1))
	c.blob(cx, cy, L * 0.42, L * 0.22, cs[0], b.get("skin", ""), cs[2])
	c.blob(cx + 2.0 * kb, cy + L * 0.08, L * 0.3, L * 0.12, cs[1], "fur")
	# talons
	if pose.get("talons", 0.0) > 0.0:
		for k2 in 2:
			var tp := Vector2(cx + (-2.0 + k2 * 6.0) * kb, cy + L * 0.18)
			c.limb(tp, tp + Vector2(2.0, 7.0) * kb, maxf(0.6, 1.6 * kb), maxf(0.5, 1.2 * kb), cs[2].darkened(0.2))
			c.line(tp + Vector2(2.0, 7.0) * kb, tp + Vector2(5.0, 8.0) * kb, cs[3])
	# head, crest, hooked beak
	var hp := Vector2(cx + L * 0.45, cy - L * 0.12)
	c.blob(hp.x, hp.y, L * 0.17, L * 0.15, cs[0], "fur", cs[2])
	for k3 in (3 if kb > 0.6 else 1):
		c.poly(PackedVector2Array([hp + Vector2(-2.0 - k3 * 2.0, -L * 0.1) * Vector2(kb, 1.0), hp + Vector2((-6.0 - k3 * 3.0) * kb, -L * 0.25 - k3 * kb), hp + Vector2(-k3 * 2.0 * kb, -L * 0.13)]), cs[2])
	var bk := hp + Vector2(L * 0.13, 0.0)
	c.poly(PackedVector2Array([bk + Vector2(0, -2.5) * kb, bk + Vector2(7.0, 0.5) * kb, bk + Vector2(5.0, 4.0) * kb, bk + Vector2(0, 2.0) * kb]), cs[2])
	if pose.get("shut", 0.0) > 0.0:
		c.line(Vector2(hp.x - 0.5, hp.y - 1.0), Vector2(hp.x + 2.0, hp.y - 1.0), cs[3])
	else:
		c.eye(hp.x + 1.0, hp.y - 1.5, cs[4])
	if fold > 0.0:
		# perched: the wing folded along its side, its tip over the tail
		c.blob(cx - 2.0 * kb, cy - kb, L * 0.4, L * 0.17, cs[0].darkened(0.18), b.get("skin", ""), cs[2])
		c.line(Vector2(cx + L * 0.15, cy - 2.0 * kb), Vector2(cx - L * 0.6, cy + 2.0 * kb), cs[1].darkened(0.2))
	else:
		wing.call(0.0, 0.0)
	c.outline(Color(0.05, 0.04, 0.04))
	return c.img

# -------------------------------------------------------------- serpent ---
static func _serpent_head(b: Dictionary, sd: int, open: bool) -> Image:
	var cs := _cols(b)
	var r: float = maxf(float(b["rad"]), 1.4)       # (a thin snake's head is a little wider than its neck)
	var W := int(r * 4.0 + 8.0)
	var H := int(r * 3.0 + 8.0)
	var c := Canvas.new(W, H, sd)
	var cx := float(W) * 0.42
	var cy := float(H) * 0.5
	# frill behind the head
	for k in 4:
		var a := -2.2 + k * 0.45
		c.poly(PackedVector2Array([Vector2(cx - r * 0.3, cy), Vector2(cx - r * 0.3, cy) + Vector2(cos(a), sin(a)) * r * 1.5, Vector2(cx - r * 0.3, cy) + Vector2(cos(a + 0.3), sin(a + 0.3)) * r * 1.1]), cs[2])
	if open:
		c.poly(PackedVector2Array([Vector2(cx, cy + 1.0), Vector2(cx + r * 1.9, cy + r * 0.9), Vector2(cx + r * 1.4, cy + r * 1.4), Vector2(cx, cy + r * 0.6)]), cs[1].darkened(0.1))
		c.poly(PackedVector2Array([Vector2(cx + r * 0.3, cy), Vector2(cx + r * 1.6, cy + r * 0.3), Vector2(cx + r * 1.4, cy + r * 0.9)]), Color(0.35, 0.05, 0.08), false)
		if b.get("teeth", false):
			for k2 in 4:
				c.px(int(cx + r * (0.6 + 0.25 * k2)), int(cy + r * 0.3 + k2 * 0.4), Color(0.95, 0.93, 0.85))
	c.blob(cx + r * 0.4, cy - r * 0.1, r * 1.35, r * 0.85, cs[0], "scales", cs[2], -0.1)
	c.blob(cx + r * 0.6, cy + r * 0.35, r * 0.9, r * 0.3, cs[1])
	c.eye(cx + r * 0.85, cy - r * 0.45, cs[4])
	c.px(int(cx + r * 1.6), int(cy - r * 0.15), cs[3])
	c.outline(Color(0.04, 0.05, 0.03))
	return c.img

static func _segment(b: Dictionary, sd: int, r: float, k: int) -> Image:
	var cs := _cols(b)
	var W := int(r * 2.0 + 4.0)
	var c := Canvas.new(W, W, sd + k)
	var m := float(W) * 0.5
	c.blob(m, m, r, r, cs[0], "scales", cs[2])
	c.blob(m, m + r * 0.45, r * 0.8, r * 0.38, cs[1])
	if k % 2 == 0:
		c.blob(m - r * 0.1, m - r * 0.55, r * 0.35, r * 0.25, cs[2])
	c.outline(Color(0.04, 0.05, 0.03))
	return c.img
