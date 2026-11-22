## The guardians' lairs, dressed as places (user, 21 Nov: "make the boss arenas feel waaay more epic ...
## they should have an entrance ... themed areas ... way more detailed and epic and fit the size of the
## bosses"). buildings.gd `_lair` / `_lair_deep` shape the ground; this lays out what stands on it,
## grown from parts with the lair's own random sequence:
##   - a GATEHOUSE you come in by (towers with pointed roofs, battlements, arrow slits, a vaulted
##     passage with banners, torches and a raised portcullis, the guardian's effigy over the arch,
##     braziers either side)
##   - a DAIS at the far end (broad steps up to a plinth) and on it a STATUE of the guardian itself,
##     carved from its own picture (BossArt.statue) at about twice its size, in the theme's stones with
##     glowing eyes, standing in an arched niche cut into the BACKDROP that closes the arena: a cliff, a
##     glacier, a caldera wall, a sandstone outcrop, a ziggurat, a ruined fortress wall or a temple front
##   - a ruined COLONNADE behind the fighting floor (arches, broken piers, banners, torches), a floor
##     inlaid in the trim, and the theme's own SET: great trees and standing stones (glade), a jungle
##     temple's trees and vines, a drowned pool with dead trees (mire), ice fangs (den), crags with a
##     giant nest (eyrie), acacias and termite mounds (pride rock), obelisks and buried columns (sands),
##     giant mushrooms (hollow), obsidian spires and lava channels (caldera), a drowned temple (sanctum)
## Everything tall stands in the BACKGROUND (you fight in front of it; in a side view anything solid on the
## floor is in your way): only low cover, the dais, the gate and the backdrop are solid in front. Natural
## rock is written with the NATURAL bit (stamp.comp: not marked built), so crags and cliffs look and
## behave like the land. Everything is anchored (kept by the generator's soundness pass; in the game it
## stays put until dug or blasted near, then obeys the physics).
extends RefCounted

const BossArt := preload("res://scripts/boss_art.gd")

const F_FILL := 0x10000
const F_ANCHOR := 0x20000
const F_WALL := 0x40000
const NATURAL := 0x80000
const BANNER := 13                 # props.gd KINDS: a banner (pick it up whole and it stays a banner)

const GATE_W := 62                 # the gatehouse's width
const BACK_W := 210                # the dais and the backdrop at the far end
const MASS_W := 62                 # the backdrop (with the niche cut into its first NICHE_D columns)
const NICHE_D := 24

## what each guardian's lair is made of and how it is dressed
static func theme(biome: String) -> Dictionary:
	var t := {}
	match biome:
		"forest":
			t = {"set": "glade", "back": "cliff", "stat": [Defs.MOSSBLOCK, Defs.STONE, Defs.DEEPSTONE, Defs.EMBER], "glow": Defs.SHROOM,
				"cloth": [8, 9], "roof": Defs.WOOD, "rock": Defs.STONE, "moss": Defs.MOSSBLOCK, "wood": Defs.WOOD, "leaf": Defs.LEAF}
		"jungle":
			t = {"set": "temple", "back": "ziggurat", "stat": [Defs.MOSSBLOCK, Defs.MASONRY, Defs.DEEPSTONE, Defs.EMBER], "glow": Defs.SHROOM,
				"cloth": [4, 5], "roof": Defs.TILE, "rock": Defs.STONE, "moss": Defs.MOSSBLOCK, "wood": Defs.WOOD, "leaf": Defs.LEAF}
		"marsh":
			t = {"set": "mire", "back": "ruin", "stat": [Defs.MOSSBLOCK, Defs.STONE, Defs.DEEPSTONE, Defs.EMBER], "glow": Defs.SHROOM,
				"cloth": [34, 35], "roof": Defs.WOOD, "rock": Defs.STONE, "moss": Defs.MOSSBLOCK, "wood": Defs.ROOT, "leaf": Defs.LEAF}
		"tundra":
			t = {"set": "den", "back": "glacier", "stat": [Defs.ICE, Defs.ICE, Defs.DEEPSTONE, Defs.FROST], "glow": Defs.FROST,
				"cloth": [6, 7], "roof": Defs.ICE, "rock": Defs.STONE, "moss": Defs.ICE, "wood": Defs.WOOD, "leaf": Defs.LEAF}
		"mountain":
			t = {"set": "eyrie", "back": "cliff", "stat": [Defs.MASONRY, Defs.STONE, Defs.DEEPSTONE, Defs.EMBER], "glow": Defs.EMBER,
				"cloth": [4, 5], "roof": Defs.TILE, "rock": Defs.STONE, "moss": Defs.GRASS, "wood": Defs.WOOD, "leaf": Defs.LEAF}
		"savanna":
			t = {"set": "pride", "back": "outcrop", "stat": [Defs.SANDSTONE, Defs.SANDSTONE, Defs.DEEPSTONE, Defs.EMBER], "glow": Defs.EMBER,
				"cloth": [16, 15], "roof": Defs.TILE, "rock": Defs.SANDSTONE, "moss": Defs.DRYGRASS, "wood": Defs.WOOD, "leaf": Defs.LEAF}
		"desert":
			t = {"set": "sands", "back": "temple", "stat": [Defs.SANDSTONE, Defs.SANDSTONE, Defs.TILE, Defs.EMBER], "glow": Defs.EMBER,
				"cloth": [6, 7], "roof": Defs.TILE, "rock": Defs.SANDSTONE, "moss": Defs.SANDSTONE, "wood": Defs.WOOD, "leaf": Defs.LEAF}
		"grove":
			t = {"set": "hollow", "back": "ruin", "stat": [Defs.MASONRY, Defs.STONE, Defs.DEEPSTONE, Defs.SHROOM], "glow": Defs.SHROOM,
				"cloth": [36, 37], "roof": Defs.CAP, "rock": Defs.STONE, "moss": Defs.MYCELIUM, "wood": Defs.STALK, "leaf": Defs.CAP}
		"ashland":
			t = {"shade": Defs.OBSIDIAN, "set": "caldera", "back": "caldera", "stat": [Defs.MAGMAROCK, Defs.OBSIDIAN, Defs.OBSIDIAN, Defs.EMBER], "glow": Defs.EMBER,
				"cloth": [32, 33], "roof": Defs.OBSIDIAN, "rock": Defs.MAGMAROCK, "moss": Defs.OBSIDIAN, "wood": Defs.ROOT, "leaf": Defs.ASH}
		"ocean":
			t = {"set": "sanctum", "back": "temple", "stat": [Defs.MASONRY, Defs.STONE, Defs.DEEPSTONE, Defs.CRYSTAL], "glow": Defs.CRYSTAL,
				"cloth": [38, 39], "roof": Defs.SANDSTONE, "rock": Defs.STONE, "moss": Defs.MOSSBLOCK, "wood": Defs.WOOD, "leaf": Defs.LEAF}
		_:
			t = {"set": "glade", "back": "ruin", "stat": [Defs.MASONRY, Defs.STONE, Defs.DEEPSTONE, Defs.EMBER], "glow": Defs.EMBER,
				"cloth": [4, 5], "roof": Defs.TILE, "rock": Defs.STONE, "moss": Defs.MOSSBLOCK, "wood": Defs.WOOD, "leaf": Defs.LEAF}
	return t

# ------------------------------------------------------------- the layout ---
## Where things go, and the cells, written straight into a copy of the blueprint (one call a cell, on
## local arrays: the planner's own calls are shared and slow), then given back by `commit`.
class Lay:
	var pl                        # the planner (buildings.gd)
	var bp                        # its blueprint (BP)
	var bd: Dictionary            # Defs.BOSSES[biome]
	var biome := ""
	var th: Dictionary            # theme()
	var rng: RandomNumberGenerator
	var c: PackedInt32Array
	var bw := 0
	var bh := 0
	var W := 0                    # the arena's columns, from ox
	var ox := 0
	var fl := 0                   # the floor's top row (its first solid row)
	var right := true             # the dais at the right end (u counts from the gate's end)
	var sea := -1                 # a drowned lair: the water's top row (else -1)
	var gtop := PackedInt32Array()   # the ground's top row under each blueprint column (foundations)
	var sd := 0
	var simg: Image = null        # the guardian's statue pose (drawn once a lair)
	var simg_done := false

	func _init(p_pl, p_bp, boss: Dictionary, bio: String, w0: int, o: int, f: int, rt: bool) -> void:
		pl = p_pl
		bp = p_bp
		bd = boss
		biome = bio
		rng = p_pl.rng
		c = p_bp.c
		bw = p_bp.w
		bh = p_bp.h
		W = w0
		ox = o
		fl = f
		right = rt
		sd = rng.randi() & 0xffff
		gtop.resize(bw)
		gtop.fill(f)

	func commit() -> void:
		bp.c = c

	## the blueprint column of the arena's column u (counted from the gate's end)
	func at(u: float) -> int:
		return ox + int(round(u)) if right else ox + W - 1 - int(round(u))

	## +1 if u grows to the right in the blueprint
	func dir() -> int:
		return 1 if right else -1

	func ok(i: int, j: int) -> bool:
		return i >= 0 and j >= 0 and i < bw and j < bh

	func air(j: int) -> int:
		return Defs.WATER if sea >= 0 and j >= sea else 0

	## a built block in front, with its back wall (anchored)
	func s(i: int, j: int, m: int) -> void:
		if ok(i, j):
			c[j * bw + i] = (m & 255) | ((m & 255) << 8) | F_ANCHOR | F_WALL

	## natural rock in front, its back the same rock: part of the land, not built
	func n(i: int, j: int, m: int) -> void:
		if ok(i, j):
			c[j * bw + i] = (m & 255) | ((m & 255) << 8) | F_ANCHOR | F_WALL | NATURAL

	## a back wall only: what's in front stays
	func b(i: int, j: int, m: int) -> void:
		if ok(i, j):
			var k := j * bw + i
			var v: int = c[k]
			var f0 := v & 255
			c[k] = f0 | ((m & 255) << 8) | F_WALL | F_ANCHOR | (v & (NATURAL | F_FILL))

	## open the front (air, or water under a drowned lair's sea); the back stays
	func clear(i: int, j: int) -> void:
		if ok(i, j):
			var k := j * bw + i
			var v: int = c[k]
			var g := (v >> 8) & 255
			if g == 255:
				c[k] = air(j) | (255 << 8)
			else:
				c[k] = air(j) | (v & (0xff00 | F_WALL)) | F_ANCHOR

	## open sky: nothing in front or behind
	func sky(i: int, j: int) -> void:
		if ok(i, j):
			c[j * bw + i] = air(j)

	## a back wall carved open: front open, back this material
	func hollow(i: int, j: int, m: int) -> void:
		if ok(i, j):
			c[j * bw + i] = air(j) | ((m & 255) << 8) | F_WALL | F_ANCHOR

	## a banner's pixel (furniture in the background, palette colour pal)
	func deco(i: int, j: int, pal: int) -> void:
		if ok(i, j):
			c[j * bw + i] = air(j) | (Defs.DECOR << 8) | ((pal & 255) << 19) | 0x8000000 | F_WALL | F_ANCHOR | ((BANNER & 15) << 28)

	## a torch (background, it burns)
	func torch(i: int, j: int) -> void:
		if ok(i, j):
			c[j * bw + i] = air(j) | (Defs.TORCH << 8) | F_WALL | F_ANCHOR

	## a cell written as it is (front, back and flags)
	func raw(i: int, j: int, v: int) -> void:
		if ok(i, j):
			c[j * bw + i] = v

	func fg_of(i: int, j: int) -> int:
		return c[j * bw + i] & 255 if ok(i, j) else 255

	## layer 0 built front, 1 natural front, 2 back
	func put(layer: int, i: int, j: int, m: int) -> void:
		if layer == 0:
			s(i, j, m)
		elif layer == 1:
			n(i, j, m)
		else:
			b(i, j, m)

	func h(x: int, y: int) -> float:
		var q := (x * 374761393 + y * 668265263 + sd * 2147483) & 0x7fffffff
		q = ((q ^ (q >> 13)) * 1274126177) & 0x7fffffff
		return float(q & 0xffff) / 65535.0

# ------------------------------------------------------------- the pieces ---
## a tapering spire (ice fang, crag, obelisk, standing stone): w wide at its foot on row base, h tall,
## leaning `lean` columns a row, its sides ragged by `jag`; `tip` its top few rows (-1: none)
static func spire(L: Lay, cx: float, base: int, w: float, hgt: int, m: int, layer: int, lean := 0.0, jag := 0.0, tip := -1, taper := 0.85) -> void:
	var jl := 0.0
	var jr := 0.0
	for up in hgt:
		var fr := float(up) / float(hgt)
		var hw := maxf(0.5, w * 0.5 * pow(1.0 - fr, taper))
		jl = lerpf(jl, (L.h(up, 11) - 0.5) * jag, 0.5)
		jr = lerpf(jr, (L.h(up, 23) - 0.5) * jag, 0.5)
		var x := cx + lean * float(up)
		var m2 := tip if tip >= 0 and up >= hgt - 3 else m
		for i in range(int(round(x - hw + jl)), int(round(x + hw + jr)) + 1):
			L.put(layer, i, base - 1 - up, m2)

## a rough ellipse
static func blob(L: Lay, cx: float, cy: float, rx: float, ry: float, m: int, layer: int, rough := 0.25) -> void:
	for dy in range(-int(ry) - 1, int(ry) + 2):
		for dx in range(-int(rx) - 1, int(rx) + 2):
			var d := pow(float(dx) / maxf(rx, 0.5), 2.0) + pow(float(dy) / maxf(ry, 0.5), 2.0)
			if d <= 1.0 - rough * L.h(int(cx) + dx, int(cy) + dy):
				L.put(layer, int(round(cx)) + dx, int(round(cy)) + dy, m)

## an arch between columns i0..i1 on row base: piers t thick and ph tall, a round arch over them,
## a keystone of `key` (-1: none)
static func arch(L: Lay, i0: int, i1: int, base: int, ph: int, t: int, m: int, layer: int, key := -1) -> void:
	for j in range(base - ph, base):
		for q in t:
			L.put(layer, i0 + q, j, m)
			L.put(layer, i1 - q, j, m)
	var cx := float(i0 + i1) * 0.5
	var R := float(i1 - i0 + 1) * 0.5
	var cy := base - ph
	for i in range(i0, i1 + 1):
		for dy in range(0, int(R) + 2):
			var r := sqrt(pow(float(i) - cx, 2.0) + float(dy * dy))
			if r <= R and r >= R - float(t):
				var km := key if key >= 0 and absf(float(i) - cx) <= 1.6 else m
				L.put(layer, i, cy - dy, km)

## a great tree in the background: a swaying trunk flaring into roots, branches reaching out and up,
## crowns of leaves (none if dead: gnarled twigs instead), vines hanging from the crowns
static func tree(L: Lay, cx: float, base: int, hgt: int, tw: float, wood: int, leaf: int, dead := false, vines := 0) -> void:
	var tth := int(float(hgt) * 0.62)
	var ph := L.rng.randf() * TAU
	var tops := []
	for up in tth:
		var wv := tw * (1.0 - 0.45 * float(up) / float(tth))
		if up < 12:
			wv += tw * 1.1 * pow(1.0 - float(up) / 12.0, 2.0)
		var x := cx + sin(float(up) * 0.05 + ph) * tw * 0.45
		for i in range(int(round(x - wv * 0.5)), int(round(x + wv * 0.5)) + 1):
			L.b(i, base - 1 - up, wood)
	var topx := cx + sin(float(tth) * 0.05 + ph) * tw * 0.45
	# roots arching over the ground either side
	for k in 4:
		var sgn := -1.0 if k % 2 == 0 else 1.0
		var rl := tw * L.rng.randf_range(1.2, 2.4)
		var rh := L.rng.randf_range(2.0, 5.0)
		for q in int(rl * 2.0):
			var t := float(q) / (rl * 2.0)
			var x2 := cx + sgn * (tw * 0.4 + rl * t)
			var y2 := float(base - 1) - sin(t * PI) * rh - (1.0 - t) * 3.0
			for th2 in maxi(1, int((1.0 - t) * tw * 0.3)):
				L.b(int(round(x2)), int(round(y2)) - th2, wood)
	# branches
	var nb := L.rng.randi_range(4, 6)
	for k2 in nb:
		var side := -1.0 if k2 % 2 == 0 else 1.0
		var hb := float(tth) * (0.45 + 0.5 * float(k2) / float(nb))
		var x0 := cx + sin(hb * 0.05 + ph) * tw * 0.45
		var y0 := float(base - 1) - hb
		var bl := float(hgt) * L.rng.randf_range(0.26, 0.42)
		var rise := bl * L.rng.randf_range(0.25, 0.65)
		var steps := int(bl * 1.5)
		var ex := x0
		var ey := y0
		for q2 in steps + 1:
			var t2 := float(q2) / float(steps)
			ex = x0 + side * bl * t2
			ey = y0 - rise * sin(t2 * PI * 0.5) + (bl * 0.12) * t2 * t2
			var r2 := lerpf(tw * 0.32, 1.0, t2)
			for dy in range(-int(r2), int(r2) + 1):
				L.b(int(round(ex)), int(round(ey)) + dy, wood)
		if dead:
			# gnarled twigs
			for q3 in 3:
				var a := -PI * 0.5 + side * L.rng.randf_range(0.2, 1.2)
				var tl := L.rng.randf_range(5.0, 12.0)
				for q4 in int(tl):
					L.b(int(round(ex + cos(a) * q4)), int(round(ey + sin(a) * q4)), wood)
		else:
			tops.append(Vector3(ex, ey, bl))
	if not dead:
		tops.append(Vector3(topx, float(base - tth), float(hgt) * 0.4))
		for tp: Vector3 in tops:
			var rx: float = tp.z * 0.42 + 7.0
			var ry := rx * 0.5
			blob(L, tp.x, tp.y - ry * 0.3, rx, ry, leaf, 2, 0.35)
			blob(L, tp.x + rx * 0.45, tp.y + ry * 0.2, rx * 0.6, ry * 0.6, leaf, 2, 0.35)
			blob(L, tp.x - rx * 0.45, tp.y + ry * 0.25, rx * 0.55, ry * 0.55, leaf, 2, 0.35)
			# vines hanging from under the crown
			for v in vines:
				var vx := tp.x + L.rng.randf_range(-rx * 0.8, rx * 0.8)
				var vl := L.rng.randi_range(8, 30)
				for q5 in vl:
					var wob := int(round(sin(float(q5) * 0.4 + vx) * 0.8))
					var vj := int(tp.y + ry * 0.5) + q5
					if vj >= base - 2:
						break
					L.b(int(vx) + wob, vj, leaf)

## a giant mushroom: a curving stalk with a ring, a domed cap with gills under it and glowing spots
static func shroom(L: Lay, cx: float, base: int, hgt: int, sw: float, capw: float, layer: int) -> void:
	var bend := L.rng.randf_range(-0.22, 0.22) * float(hgt)
	var stalk := Defs.STALK
	var x := cx
	for up in hgt:
		var fr := float(up) / float(hgt)
		x = cx + bend * fr * fr
		var wv := sw * (1.0 - 0.25 * fr) + (2.0 if absf(fr - 0.62) < 0.03 else 0.0) + (sw * 0.6 * pow(1.0 - fr * 6.0, 2.0) if fr < 0.16 else 0.0)
		for i in range(int(round(x - wv * 0.5)), int(round(x + wv * 0.5)) + 1):
			L.put(layer, i, base - 1 - up, stalk)
	var top := base - hgt
	var rx := capw * 0.5
	var ry := capw * 0.34
	for dy in range(0, int(ry) + 1):
		for dx in range(-int(rx) - 1, int(rx) + 2):
			if pow(float(dx) / rx, 2.0) + pow(float(dy) / ry, 2.0) <= 1.0:
				var spot := L.h(int(x) + dx, top - dy) < 0.07
				L.put(layer, int(round(x)) + dx, top - dy, Defs.SHROOM if spot else Defs.CAP)
	# gills under the cap, and a glowing drip at its rim
	for dx2 in range(-int(rx * 0.92), int(rx * 0.92) + 1):
		if absf(float(dx2)) > sw * 0.5 + 0.5:
			L.put(layer, int(round(x)) + dx2, top + 1, Defs.MYCELIUM)
	for e: int in [-1, 1]:
		L.put(layer, int(round(x + e * rx)), top + 1, Defs.SHROOM)

## a banner hanging from row jtop: a rod, a cloth `ln` long and `w` wide in two colours with a border,
## a gold emblem, and a swallowtail at its foot
static func banner(L: Lay, i0: int, jtop: int, ln: int, w: int, ca: int, cb: int) -> void:
	for i in range(i0 - 1, i0 + w + 1):
		L.deco(i, jtop, 13)
	var mid := float(w - 1) * 0.5
	for r in range(1, ln + 1):
		for q in w:
			var tailr := r - (ln - int(w / 2))
			if tailr > 0 and absf(float(q) - mid) < float(tailr):
				continue
			var border := q == 0 or q == w - 1 or r == 1
			var pal := ca if border else cb
			# the emblem: a diamond a third of the way down
			var ey := int(ln * 0.38)
			if absi(r - ey) + absf(float(q) - mid) <= float(w) * 0.3:
				pal = 15
			L.deco(i0 + q, jtop + r, pal)

## a brazier on row base: a stand, a bowl, coals glowing and a fire (a real torch) over it
static func brazier(L: Lay, i: int, base: int, hgt: int, stand: int, bowl: int, glow: int) -> void:
	for j in range(base - hgt + 3, base):
		for q in range(-1, 2):
			L.s(i + q, j, stand)
	for q2 in range(-4, 5):
		L.s(i + q2, base - hgt + 2, bowl)
	for q3 in range(-3, 4):
		L.s(i + q3, base - hgt + 1, bowl if absi(q3) == 3 else glow)
	for q4 in range(-1, 2):
		L.torch(i + q4, base - hgt)

## a guardian's effigy in stone (background): its statue pose scaled to fit maxw x maxh, standing on row
## base, centred on column cx, facing toward the gate (`face` -1 = left). The picture's dark outline is
## the dark stone, its light parts the light stone, the rest the main stone; its eyes glow.
static func statue_img(L: Lay) -> Image:
	if not L.simg_done:
		L.simg = BossArt.statue("boss_" + L.biome, L.bd["body"])
		L.simg_done = true
	return L.simg

static func statue(L: Lay, cx: int, base: int, maxw: float, maxh: float, face: int) -> Vector2i:
	var img: Image = statue_img(L)
	if img == null:
		return Vector2i.ZERO
	var sc := minf(maxh / float(img.get_height()), maxw / float(img.get_width()))
	sc = clampf(sc, 0.6, 3.0)
	var sw := int(float(img.get_width()) * sc)
	var shh := int(float(img.get_height()) * sc)
	var mats: Array = L.th["stat"]
	var eye := Color(String(L.bd["body"].get("eye", "#ffff00")))
	for v in shh:
		for u in sw:
			var px := img.get_pixel(mini(int(float(u) / sc), img.get_width() - 1), mini(int(float(v) / sc), img.get_height() - 1))
			if px.a < 0.5:
				continue
			var lum := px.get_luminance()
			var m: int = mats[1]
			if absf(px.r - eye.r) + absf(px.g - eye.g) + absf(px.b - eye.b) < 0.25:
				m = mats[3]
			elif lum < 0.13:
				m = mats[2]
			elif lum > 0.56:
				m = mats[0]
			var uu := u if face > 0 else sw - 1 - u
			L.b(cx - sw / 2 + uu, base - shh + v, m)
	return Vector2i(sw, shh)

# -------------------------------------------------------------- the gate ---
## the gatehouse: its first column at arena column u0 (the ramp's top), GATE_W wide
static func gatehouse(L: Lay, u0: int) -> void:
	var wall: int = L.bd["wall"]
	var trim: int = L.bd["trim"]
	var dark: int = L.th.get("shade", Defs.DEEPSTONE)
	var roof: int = L.th["roof"]
	var tw := 15
	var th_ := L.rng.randi_range(88, 100)
	var mh := th_ - L.rng.randi_range(18, 24)
	var tun := 48                 # the passage's height at its mouths (a guardian walks through)
	var fl := L.fl
	for q in GATE_W:
		var i := L.at(u0 + q)
		var tower := q < tw or q >= GATE_W - tw
		var hh := th_ if tower else mh
		# the passage: vaulted, higher in the middle
		var mid := absf(float(q) - float(GATE_W - 1) * 0.5) / (float(GATE_W) * 0.5)
		var vault := tun + int(round(10.0 * sqrt(maxf(0.0, 1.0 - mid * mid))))
		for j in range(fl - hh, fl):
			if j >= fl - vault:
				L.hollow(i, j, dark)
			else:
				L.s(i, j, wall)
		# the arch's ring and the courses in the trim
		L.s(i, fl - vault - 1, trim)
		L.s(i, fl - vault - 2, trim)
		L.s(i, fl - hh + 4, trim)
		if tower:
			L.s(i, fl - mh + 2, trim)
		# battlements: merlons and crenels
		var qq := q if q < GATE_W / 2 else GATE_W - 1 - q
		if (qq / 3) % 2 == 1:
			for j2 in range(fl - hh, fl - hh + 3):
				L.sky(i, j2)
		# foundations down to the land
		for j3 in range(fl, maxi(fl + 2, L.gtop[i] + 2)):
			L.s(i, j3, wall)
	# arrow slits in the towers, and a pointed roof on each
	for side in 2:
		var sq := 6 if side == 0 else GATE_W - 8
		for k in 2:
			var jt := fl - th_ + 14 + k * 18
			for j4 in range(jt, jt + 7):
				L.hollow(L.at(u0 + sq), j4, dark)
				L.hollow(L.at(u0 + sq + 1), j4, dark)
		var rcx := float(tw - 1) * 0.5 if side == 0 else float(GATE_W) - float(tw + 1) * 0.5
		var rh := L.rng.randi_range(16, 22)
		for up in rh:
			var hw := (float(tw) * 0.5 + 2.0) * (1.0 - float(up) / float(rh))
			for q2 in range(int(round(rcx - hw)), int(round(rcx + hw)) + 1):
				L.s(L.at(u0 + q2), fl - th_ - 1 - up, roof)
		L.s(L.at(u0 + rcx), fl - th_ - rh - 1, trim)
		L.s(L.at(u0 + rcx), fl - th_ - rh - 2, trim)
	# the portcullis, raised: its teeth showing under the vault at the arena's mouth
	for q3 in range(GATE_W - 9, GATE_W - 3, 2):
		for j5 in range(fl - tun, fl - tun + 9):
			L.s(L.at(u0 + q3), j5, Defs.WOOD)
	# banners and torches in the passage
	var cl: Array = L.th["cloth"]
	banner(L, mini(L.at(u0 + 12), L.at(u0 + 18)), fl - tun + 3, 22, 7, cl[0], cl[1])
	banner(L, mini(L.at(u0 + GATE_W - 20), L.at(u0 + GATE_W - 14)), fl - tun + 3, 22, 7, cl[0], cl[1])
	for tq: int in [3, GATE_W - 4]:
		L.torch(L.at(u0 + tq), fl - 20)
	# the guardian's effigy over the arch, on the battlements
	statue(L, L.at(u0 + GATE_W * 0.5), fl - mh, 44.0, 30.0, L.dir())
	# braziers outside (on the land where the ramp comes up) and in
	var bo := L.at(u0 - 9)
	brazier(L, bo, mini(L.gtop[bo], fl + 6), 14, trim, wall, L.th["glow"])
	brazier(L, L.at(u0 + GATE_W + 8), fl, 14, trim, wall, L.th["glow"])

# ----------------------------------------------------------- the far end ---
## the dais from arena column ua to the backdrop (BACK_W), the statue on it in the backdrop's niche,
## braziers, banners and the sure chest. Returns the statue's size.
static func far_end(L: Lay, ua: int, mass: bool, cap: int) -> Vector2i:
	var wall: int = L.bd["wall"]
	var pave: int = L.bd["floor"]
	var trim: int = L.bd["trim"]
	var fl := L.fl
	var ub := L.W - (MASS_W - NICHE_D) if mass else L.W     # the platform runs into the niche
	var steps := 4
	var rise := 5
	var p0 := ua + steps * 12                 # the platform's first column
	var ptop := fl - rise * steps
	# the statue, as big as the platform and the niche allow
	var maxh := float(mini(cap - rise * steps - (62 if mass else 14), 84))
	var maxw := float(ub - p0 - 24)
	var scx := (p0 + 18 + ub) / 2
	var img: Image = statue_img(L)
	var sz := Vector2i(int(maxw), int(maxh))
	if img != null:
		var sc := clampf(minf(maxh / float(img.get_height()), maxw / float(img.get_width())), 0.6, 3.0)
		sz = Vector2i(int(float(img.get_width()) * sc), int(float(img.get_height()) * sc))
	var pw := mini(sz.x + 8, ub - p0 - 16)
	var pl0 := scx - pw / 2
	# the backdrop first: the steps, the plinth and the statue go in front of it
	if mass:
		backdrop(L, L.W - MASS_W, ptop - 6, sz.y + 10, cap)
	for k in steps:
		for u in range(ua + k * 12, ub):
			var i := L.at(u)
			var top := fl - rise * (k + 1)
			for j in range(top, fl):
				L.s(i, j, trim if j == top and k < steps - 1 else (pave if j == top else wall))
	for u2 in range(pl0, pl0 + pw):
		for j2 in range(ptop - 6, ptop):
			L.s(L.at(u2), j2, trim if j2 == ptop - 6 or j2 == ptop - 1 else wall)
	statue(L, L.at(scx), ptop - 6, float(sz.x), float(sz.y), -L.dir())
	# braziers: at the dais's foot, and at the plinth's front corner
	brazier(L, L.at(ua - 8), fl, 18, trim, wall, L.th["glow"])
	brazier(L, L.at(pl0 + 2), ptop - 6, 12, trim, wall, L.th["glow"])
	# banners either side of the statue
	var cl: Array = L.th["cloth"]
	for side: int in [-1, 1]:
		var bu: int = scx + side * (sz.x / 2 + 8) - (6 if side < 0 else 0)
		if bu > p0 + 6 and bu + 7 < ub:
			banner(L, mini(L.at(bu), L.at(bu + 6)), ptop - 6 - sz.y + 4, 24, 7, cl[0], cl[1])
	# the sure chest at the top of the steps, before the plinth
	L.pl._chest(L.bp, mini(L.at(p0 + 3), L.at(p0 + 3 + Defs.CHEST_W - 1)), ptop, true)
	return sz

## the backdrop closing the arena, from arena column u0 to its end, with an arched niche (its floor
## row nfl, nh high) in its first NICHE_D columns
static func backdrop(L: Lay, u0: int, nfl: int, nh: int, cap: int) -> void:
	var style: String = L.th["back"]
	var rock: int = L.th["rock"]
	var wall: int = L.bd["wall"]
	var trim: int = L.bd["trim"]
	var moss: int = L.th["moss"]
	var dark: int = L.th.get("shade", Defs.DEEPSTONE)
	var fl := L.fl
	var nw := NICHE_D + 4
	var need := fl - (nfl - nh - nw / 2) + 14         # rock over the niche's arch
	if style == "outcrop":
		need += 36
	var hgt := mini(cap - 6, maxi(need + 6, L.rng.randi_range(120, 140)))
	var natural := style in ["cliff", "glacier", "caldera", "outcrop"]
	var layer := 1 if natural else 0
	var m: int = rock if natural else wall
	for q in L.W - u0:
		var u := u0 + q
		var i := L.at(u)
		var hh := hgt
		match style:
			"cliff", "glacier", "caldera":
				hh = hgt - int(absf(sin(float(q) * 0.11 + L.sd)) * 18.0) - int(L.h(q, 3) * 6.0)
				if style == "caldera":
					hh = hgt + 6 - int(absf(sin(float(q) * 0.21 + L.sd)) * 26.0)
			"outcrop":
				hh = hgt - int(pow(float(q) / float(L.W - u0), 2.0) * 30.0)
			"ziggurat":
				hh = mini(hgt, 26 + (q / 8) * 11)
			"ruin":
				hh = hgt - int(L.h(q / 3, 7) * 22.0) - (12 if (q / 9) % 3 == 0 else 0)
			"temple":
				hh = hgt - 18
		if q < NICHE_D + 12:
			hh = maxi(hh, mini(need, cap - 6))
		var ground := maxi(fl + 2, L.gtop[i] + 2)
		for j in range(fl - hh, ground):
			var mm := m
			if natural:
				if style == "glacier" and q < 6 + int(L.h(j, 5) * 4.0):
					mm = Defs.ICE
				elif style == "caldera" and L.h(q * 3 + j / 4, j) < 0.04:
					mm = Defs.EMBER
				elif style == "caldera" and L.h(q / 2, j / 3) < 0.25:
					mm = Defs.OBSIDIAN
			else:
				if style == "ziggurat" and (fl - j) % 11 == 0:
					mm = trim
				elif style == "temple" and (q % 10 < 2 or (fl - j) % 24 == 0):
					mm = trim
				elif style == "ruin" and (fl - j) % 14 == 0:
					mm = trim
			L.put(layer, i, j, mm)
		# the top: moss or snow or grass on natural rock, crenels on a wall
		if natural and moss != rock:
			L.put(1, i, fl - hh - 1, moss)
		if style == "ruin" and (q / 4) % 2 == 0:
			L.put(0, i, fl - hh - 1, wall)
			L.put(0, i, fl - hh - 2, wall)
	# the face: a ledge or two (cliffs), icicles hanging (glacier), the outcrop's jutting lip
	if natural:
		for k in 2:
			var lj := fl - int(float(hgt) * (0.45 + 0.3 * k))
			var ll := L.rng.randi_range(5, 10)
			for q2 in ll:
				for t in 3:
					L.n(L.at(u0 - q2), lj + t, rock)
				if moss != rock:
					L.n(L.at(u0 - q2), lj - 1, moss)
			if style == "glacier":
				for q3 in range(0, ll, 2):
					for d in L.rng.randi_range(3, 9):
						L.n(L.at(u0 - q3), lj + 3 + d, Defs.ICE)
	if style == "outcrop":
		# a great lip of rock jutting out over the statue, the pride rock's own, grass on top
		var lj2 := nfl - nh - nw / 2 - 30
		for q4 in 58:
			var fr := float(q4) / 58.0
			var thk := int(20.0 * pow(1.0 - fr, 0.7)) + 3
			var drop := int(float(q4) * 0.12)
			for t2 in thk:
				L.n(L.at(u0 + 10 - q4), lj2 + drop + t2, rock)
			L.n(L.at(u0 + 10 - q4), lj2 + drop - 1, Defs.DRYGRASS)
	if style == "temple":
		# a pediment on top
		var ph := 22
		for up in ph:
			var hw := float(L.W - u0) * 0.5 * (1.0 - float(up) / float(ph)) + 4.0
			var cx := float(u0) + float(L.W - u0) * 0.5
			for q5 in range(int(cx - hw), int(cx + hw) + 1):
				if q5 >= u0 - 4 and q5 < L.W:
					L.s(L.at(q5), fl - (hgt - 18) - 1 - up, trim if up == 0 or up == ph - 1 else wall)
	if style == "ziggurat":
		# a shrine house on its top tier
		var sq := L.W - 26
		var sj := fl - mini(hgt, 26 + ((L.W - u0 - 26) / 8) * 11) - 1
		arch(L, L.at(sq - 8) if L.right else L.at(sq + 8), L.at(sq + 8) if L.right else L.at(sq - 8), sj + 1, 14, 3, trim, 0, L.th["glow"])
	# the niche: an arched alcove cut into it for the statue
	for q6 in nw:
		var i2 := L.at(u0 + q6 - 4)
		for j3 in range(nfl - nh, nfl):
			L.hollow(i2, j3, dark)
	var ncx := float(u0) - 4.0 + float(nw) * 0.5
	for q7 in range(-nw, nw + 1):
		for dy in range(0, nw / 2 + 4):
			var r := sqrt(float(q7 * q7) + float(dy * dy) * 4.0)
			var i3 := L.at(ncx + q7)
			if r <= float(nw) and float(q7) + ncx >= float(u0) - 4.0:
				L.hollow(i3, nfl - nh - dy, dark)
			elif r <= float(nw) + 3.0 and float(q7) + ncx >= float(u0) - 4.0:
				L.s(i3, nfl - nh - dy, trim)

# ------------------------------------------------------------ the middle ---
## a ruined colonnade behind the fighting floor (arena columns ua..ub): piers on plinths with
## capitals, round arches between them, some broken; banners in some arches, torches on the piers
static func colonnade(L: Lay, ua: int, ub: int, cap: int, pier := -1) -> void:
	var wall: int = L.bd["wall"] if pier < 0 else pier
	var trim: int = L.bd["trim"]
	var cl: Array = L.th["cloth"]
	var fl := L.fl
	var span := L.rng.randi_range(34, 42)
	var ph := mini(cap - span / 2 - 10, L.rng.randi_range(44, 58))
	var piers := []
	var u := ua
	while u <= ub:
		piers.append(u)
		u += span
	for k in piers.size():
		var pu: int = piers[k]
		var broken := L.rng.randf() < 0.3
		var top := ph if not broken else L.rng.randi_range(10, ph - 10)
		for up in top:
			for q in range(-2, 3):
				var m := wall
				if up < 2 or (not broken and up >= top - 2):
					m = trim
				L.b(L.at(pu + q), fl - 1 - up, m)
		for q2 in range(-3, 4):
			L.b(L.at(pu + q2), fl - 1, trim)
			L.b(L.at(pu + q2), fl - 2, trim)
			if not broken:
				L.b(L.at(pu + q2), fl - ph, trim)
		if broken:
			# its fallen drum lying at its foot (in front: a little cover)
			var du := pu + (4 if L.rng.randf() < 0.5 else -9)
			for q3 in 6:
				for t in 3:
					L.s(L.at(du + q3), fl - 1 - t, wall if t < 2 else trim)
		else:
			L.torch(L.at(pu + 0), fl - 18)
		piers[k] = [pu, broken]
	for k2 in piers.size() - 1:
		var a: Array = piers[k2]
		var bb: Array = piers[k2 + 1]
		if a[1] or bb[1]:
			continue
		var i0 := mini(L.at(int(a[0]) + 2), L.at(int(bb[0]) - 2))
		var i1 := maxi(L.at(int(a[0]) + 2), L.at(int(bb[0]) - 2))
		arch(L, i0, i1, fl - ph + 1, 0, 3, wall, 2, trim)
		if L.rng.randf() < 0.6:
			var bwid := 7
			var bi := (i0 + i1) / 2 - bwid / 2
			var archtop := fl - ph - (i1 - i0) / 2 + 3
			banner(L, bi, archtop + 1, L.rng.randi_range(16, 24), bwid, cl[0], cl[1])

## the floor inlaid in the trim: a band every so often, and rings round the middle
static func inlay(L: Lay, ua: int, ub: int) -> void:
	var trim: int = L.bd["trim"]
	var mid := (ua + ub) / 2
	for u in range(ua, ub):
		var d := absi(u - mid)
		var on := (d < 40 and (d % 9 == 0 or d % 9 == 1)) or (u - ua) % 24 == 0
		if on:
			L.s(L.at(u), L.fl, trim)

## low cover: a broken stub or a fallen block, no taller than `hmax`
static func stub(L: Lay, u: int, hmax: int, m: int, cap_m: int) -> void:
	var w := L.rng.randi_range(5, 8)
	var hh := L.rng.randi_range(maxi(3, hmax / 2), hmax)
	for q in w:
		var col := hh - absi(q - w / 2) * L.rng.randi_range(0, 2)
		for up in maxi(1, col):
			L.s(L.at(u + q), L.fl - 1 - up, cap_m if up == col - 1 else m)

## the theme's own set over the fighting floor (arena columns ua..ub; mid is where the guardian waits
## and you're brought for the tests: nothing solid in front within `keep` of it)
static func dress(L: Lay, ua: int, ub: int, cap: int) -> void:
	var mid := (ua + ub) / 2
	var keep := 64
	var wall: int = L.bd["wall"]
	var trim: int = L.bd["trim"]
	var glow: int = L.th["glow"]
	var rock: int = L.th["rock"]
	var fl := L.fl
	var sides := [ua + 10 + L.rng.randi_range(0, 20), ub - 10 - L.rng.randi_range(0, 20)]
	var coverat := [L.rng.randi_range(ua + 6, maxi(ua + 7, mid - keep - 8)), L.rng.randi_range(mini(mid + keep, ub - 9), ub - 8)]
	match String(L.th["set"]):
		"glade":
			for su: int in sides:
				tree(L, float(L.at(su)), fl, L.rng.randi_range(int(cap * 0.72), int(cap * 0.9)), L.rng.randf_range(9.0, 12.0), L.th["wood"], L.th["leaf"])
			# a ring of standing stones (behind), carved with glowing runes
			for k in 5:
				var su2 := lerpf(float(ua + 30), float(ub - 30), float(k) / 4.0) + L.rng.randf_range(-6.0, 6.0)
				var hh := L.rng.randi_range(22, 40)
				spire(L, float(L.at(su2)), fl, L.rng.randf_range(7.0, 10.0), hh, L.th["moss"], 2, L.rng.randf_range(-0.06, 0.06), 1.5, -1, 0.25)
				for r in range(6, hh - 6, 3):
					L.b(L.at(su2), fl - r, glow)
			for cu: int in coverat:
				stub(L, cu, 8, L.th["moss"], L.th["moss"])
		"temple":
			for su3: int in sides:
				tree(L, float(L.at(su3)), fl, L.rng.randi_range(int(cap * 0.75), int(cap * 0.92)), L.rng.randf_range(8.0, 11.0), L.th["wood"], L.th["leaf"], false, 3)
			for cu2: int in coverat:
				stub(L, cu2, 9, wall, trim)
		"mire":
			# a sunken pool in the middle, rimmed in stone, drowned columns standing in it
			var pw := L.rng.randi_range(46, 58)
			for u in range(mid - pw, mid + pw):
				var i := L.at(u)
				var e := mini(u - (mid - pw), mid + pw - 1 - u)
				var depth := mini(7, 2 + e / 3)
				for j in range(fl, fl + depth):
					L.raw(i, j, Defs.WATER | (wall << 8) | F_WALL | F_ANCHOR)
				for j2 in range(fl + depth, fl + depth + 2):
					L.raw(i, j2, Defs.MUD | (wall << 8) | F_WALL | F_ANCHOR)
				for j3 in range(fl + depth + 2, fl + depth + 4):
					L.s(i, j3, wall)
			for e2: int in [-1, 1]:
				for t in 3:
					L.s(L.at(mid + e2 * pw + (0 if e2 > 0 else -1)), fl - 1 - t + 1, trim)
			for k2 in 3:
				var cu3 := mid - pw + 14 + k2 * (pw - 14)
				var ch := L.rng.randi_range(6, 14)
				for q in 5:
					for up in range(-6, ch - absi(q - 2) * L.rng.randi_range(0, 2)):
						L.s(L.at(cu3 + q), fl - 1 - up, L.th["moss"] if up >= 0 else wall)
			for su4: int in sides:
				tree(L, float(L.at(su4)), fl, L.rng.randi_range(int(cap * 0.55), int(cap * 0.75)), L.rng.randf_range(6.0, 9.0), Defs.ROOT, L.th["leaf"], true)
				# moss hanging from the dead boughs
				for v in 6:
					var vx := L.at(su4 + L.rng.randi_range(-24, 24))
					var vt := fl - L.rng.randi_range(40, 70)
					for q2 in L.rng.randi_range(6, 16):
						L.b(vx, vt + q2, Defs.LEAF)
		"den":
			# great ice spires behind, smaller fangs and snowdrifts in front at the sides
			for k3 in 6:
				var su5 := lerpf(float(ua + 6), float(ub - 6), float(k3) / 5.0) + L.rng.randf_range(-8.0, 8.0)
				spire(L, float(L.at(su5)), fl, L.rng.randf_range(12.0, 22.0), L.rng.randi_range(48, int(cap * 0.85)), Defs.ICE, 2, L.rng.randf_range(-0.12, 0.12), 3.0, Defs.FROST)
			for cu4: int in coverat:
				spire(L, float(L.at(cu4)), fl, L.rng.randf_range(7.0, 10.0), L.rng.randi_range(7, 11), Defs.ICE, 0, L.rng.randf_range(-0.2, 0.2), 1.0, Defs.FROST)
			for u2 in range(mid - 30, mid + 30):
				L.s(L.at(u2), fl, Defs.ICE)
		"eyrie":
			# two great crags behind, the taller crowned with the roc's nest
			var tall := 0
			var nest_at := Vector2i.ZERO
			for su6: int in sides:
				var ch2 := L.rng.randi_range(int(cap * 0.7), int(cap * 0.86))
				var top_at := crag(L, float(L.at(su6)), fl, L.rng.randf_range(58.0, 74.0), ch2, rock)
				if ch2 > tall:
					tall = ch2
					nest_at = top_at + Vector2i(0, 3)
			nest(L, nest_at.x, nest_at.y)
			for cu5: int in coverat:
				blob(L, float(L.at(cu5 + 3)), float(fl - 3), 6.0, 4.0, rock, 1, 0.3)
		"pride":
			for su7: int in sides:
				acacia(L, L.at(su7), fl, L.rng.randi_range(46, 64))
			for cu6: int in coverat:
				spire(L, float(L.at(cu6 + 3)), fl, 7.0, L.rng.randi_range(8, 12), rock, 1, 0.0, 1.5, -1, 0.6)
			for u3 in range(ua, ub):
				if L.h(u3, 9) < 0.5:
					for t2 in L.rng.randi_range(1, 4):
						L.b(L.at(u3), fl - 1 - t2, Defs.DRYGRASS)
		"sands":
			# obelisks behind, toppled columns half sunk in the floor
			for k4 in 4:
				var su8 := lerpf(float(ua + 14), float(ub - 14), float(k4) / 3.0)
				var oh := L.rng.randi_range(56, int(cap * 0.8))
				spire(L, float(L.at(su8)), fl, 12.0, oh - 8, wall, 2, 0.0, 0.0, -1, 0.18)
				spire(L, float(L.at(su8)), fl - oh + 9, 9.0, 9, trim, 2, 0.0, 0.0, glow, 1.0)
				for r2 in range(12, oh - 16, 5):
					L.b(L.at(su8), fl - r2, trim)
			for cu7: int in coverat:
				for q3 in 16:
					for t3 in 4:
						L.s(L.at(cu7 + q3 - 4), fl - 1 - t3 + (1 if q3 > 12 else 0), wall if t3 < 3 else trim)
			for u4 in range(ua, ub):
				if L.h(u4 / 5, 4) < 0.4:
					L.s(L.at(u4), fl - 1, Defs.SANDSTONE)
		"hollow":
			for k5 in 4:
				var su9 := lerpf(float(ua + 10), float(ub - 10), float(k5) / 3.0) + L.rng.randf_range(-10.0, 10.0)
				shroom(L, float(L.at(su9)), fl, L.rng.randi_range(46, int(cap * 0.85)), L.rng.randf_range(7.0, 11.0), L.rng.randf_range(34.0, 54.0), 2)
			for cu8: int in coverat:
				shroom(L, float(L.at(cu8 + 4)), fl, L.rng.randi_range(6, 9), 2.0, L.rng.randf_range(10.0, 14.0), 0)
		"caldera":
			# obsidian spires behind, lava channels across the floor near its ends, cracks glowing
			for k6 in 7:
				var su10 := lerpf(float(ua), float(ub), float(k6) / 6.0) + L.rng.randf_range(-8.0, 8.0)
				spire(L, float(L.at(su10)), fl, L.rng.randf_range(8.0, 16.0), L.rng.randi_range(30, int(cap * 0.7)), Defs.OBSIDIAN, 2, L.rng.randf_range(-0.15, 0.15), 3.0, glow)
			for lu: int in [ua + 6, ub - 12]:
				for q4 in 6:
					var i4 := L.at(lu + q4)
					for j4 in range(fl, fl + 4):
						L.raw(i4, j4, Defs.LAVA | (Defs.OBSIDIAN << 8) | F_WALL | F_ANCHOR)
					for j5 in range(fl + 4, fl + 6):
						L.s(i4, j5, Defs.OBSIDIAN)
				L.s(L.at(lu - 1), fl - 1, Defs.OBSIDIAN)
				L.s(L.at(lu + 6), fl - 1, Defs.OBSIDIAN)
			for u5 in range(ua + 12, ub - 12):
				if L.h(u5, 2) < 0.12:
					L.s(L.at(u5), fl, glow)
		"sanctum":
			for k7 in 5:
				var su11 := lerpf(float(ua + 10), float(ub - 10), float(k7) / 4.0)
				for q5 in L.rng.randi_range(14, 34):
					L.b(L.at(su11) + int(round(sin(float(q5) * 0.3 + su11) * 1.2)), fl - 1 - q5, Defs.LEAF)
			for cu9: int in coverat:
				stub(L, cu9, 7, wall, trim)
				L.s(L.at(cu9 + 2), fl - 9, glow)
				L.s(L.at(cu9 + 3), fl - 10, glow)

## a crag (background): a main peak with lower shoulders either side, ragged, with ledges and tufts of
## grass on them; returns its summit
static func crag(L: Lay, cx: float, base: int, w: float, hgt: int, m: int) -> Vector2i:
	var lean := L.rng.randf_range(-0.06, 0.06)
	spire(L, cx, base, w * 0.7, hgt, m, 2, lean, 9.0, -1, 0.75)
	spire(L, cx - w * 0.3, base, w * 0.62, int(float(hgt) * L.rng.randf_range(0.45, 0.68)), m, 2, -0.12, 8.0, -1, 0.8)
	spire(L, cx + w * 0.32, base, w * 0.55, int(float(hgt) * L.rng.randf_range(0.35, 0.6)), m, 2, 0.12, 8.0, -1, 0.8)
	# darker bands of strata, ledges with grass
	for k in range(6, hgt - 8, L.rng.randi_range(9, 13)):
		var hw := w * 0.35 * pow(1.0 - float(k) / float(hgt), 0.75)
		for q in range(int(-hw), int(hw) + 1):
			if L.h(q, k) < 0.7:
				L.b(int(round(cx + lean * k)) + q, base - 1 - k, Defs.DEEPSTONE)
	for k2 in 3:
		var up := int(float(hgt) * L.rng.randf_range(0.25, 0.7))
		var side := -1.0 if k2 % 2 == 0 else 1.0
		var hw2 := w * 0.35 * pow(1.0 - float(up) / float(hgt), 0.75)
		var ex := cx + lean * up + side * hw2
		for q2 in L.rng.randi_range(5, 9):
			L.b(int(round(ex + side * q2)), base - 1 - up, m)
			L.b(int(round(ex + side * q2)), base - up, m)
			if L.h(q2, up) < 0.6:
				L.b(int(round(ex + side * q2)), base - 2 - up, Defs.GRASS)
	return Vector2i(int(round(cx + lean * float(hgt - 1))), base - hgt)

## the roc's nest: a woven bowl of sticks on a crag's top, three great eggs in it
static func nest(L: Lay, cx: int, base: int) -> void:
	var rx := 20
	for q in range(-rx, rx + 1):
		var d := absf(float(q)) / float(rx)
		var depth := int(round(8.0 * sqrt(maxf(0.0, 1.0 - d * d))))
		for t in 3:
			L.s(cx + q, base - 8 + depth + t - 1, Defs.WOOD if (q + t) % 3 != 0 else Defs.PLANK)
	for k in 10:
		var a := L.rng.randf_range(-0.5, 0.5)
		var sx := cx + L.rng.randi_range(-rx, rx)
		for q2 in L.rng.randi_range(6, 12):
			L.s(sx + int(round(cos(a) * q2)), base - 9 + int(round(sin(a) * q2)) + 4, Defs.WOOD)
	for e: int in [-7, 0, 7]:
		blob(L, float(cx + e), float(base - 8), 3.0, 4.0, Defs.MASONRY, 0, 0.05)
		L.s(cx + e - 1, base - 9, Defs.DEEPSTONE)
		L.s(cx + e + 1, base - 7, Defs.DEEPSTONE)

## an acacia: a leaning, forked trunk under a broad flat crown
static func acacia(L: Lay, cx: int, base: int, hgt: int) -> void:
	var lean := L.rng.randf_range(-0.3, 0.3)
	var fork := int(float(hgt) * 0.55)
	for up in fork:
		for q in range(-2, 3):
			L.b(cx + int(round(lean * up)) + q, base - 1 - up, Defs.WOOD)
	var fx := float(cx) + lean * fork
	for side: int in [-1, 1]:
		for up2 in hgt - fork:
			var x := fx + side * float(up2) * 0.8
			for q2 in range(-1, 2):
				L.b(int(round(x)) + q2, base - 1 - fork - up2, Defs.WOOD)
		blob(L, fx + side * float(hgt - fork) * 0.8, float(base - hgt - 3), 22.0, 5.0, Defs.LEAF, 2, 0.3)

# --------------------------------------------------------------- an arena ---
## Dress an open-air lair (buildings.gd `_lair` has levelled and paved it): `tops` is the ground's top
## row under each blueprint column after shaping. Returns the arena column (blueprint) of the fighting
## floor's middle, where the guardian waits, and its half width.
static func open_arena(pl, bp, bd: Dictionary, biome: String, W: int, fl: int, tops: PackedInt32Array, ramp: int, sea: int) -> Vector2i:
	var L := Lay.new(pl, bp, bd, biome, W, 0, fl, pl.rng.randf() < 0.5)
	L.th = theme(biome)
	L.sea = sea
	for i in mini(tops.size(), L.bw):
		L.gtop[i] = tops[i]
	var cap: int = fl - 4
	var g0 := ramp
	var ua := g0 + GATE_W + 14
	var ub := W - BACK_W
	colonnade(L, ua - 4, ub - 6, cap)
	inlay(L, ua, ub)
	dress(L, ua, ub, cap)
	gatehouse(L, g0)
	far_end(L, ub, true, cap)
	L.commit()
	var mid := (ua + ub) / 2
	return Vector2i(L.at(mid), (ub - ua) / 2)

## Dress a lair dug underground: a hall W wide from column ox, its floor row fl, hh high (the shaft
## comes down from above near `shaft_u`, a column of the hall). Returns the same as open_arena.
static func hall(pl, bp, bd: Dictionary, biome: String, W: int, ox: int, fl: int, hh: int, shaft_i: int) -> Vector2i:
	var L := Lay.new(pl, bp, bd, biome, W, ox, fl, shaft_i - ox < W / 2)
	L.th = theme(biome)
	var cap := hh - 4
	var ua := 24
	var ub := W - BACK_W + 40
	colonnade(L, ua, ub - 6, cap, bd["floor"] if bd["floor"] != bd["wall"] else Defs.MASONRY)
	inlay(L, ua, ub)
	dress(L, ua, ub, cap)
	far_end(L, ub, false, cap)
	L.commit()
	var mid := (ua + ub) / 2
	return Vector2i(L.at(mid), (ub - ua) / 2)

## the gate on the surface over a hall's shaft (columns i0..i1 of the blueprint, ground row gl): two
## towers, an arch with the guardian's effigy, braziers, banners
static func shaft_gate(pl, bp, bd: Dictionary, biome: String, i0: int, i1: int, gl: int) -> void:
	var L := Lay.new(pl, bp, bd, biome, bp.w, 0, gl, true)
	L.th = theme(biome)
	var wall: int = bd["wall"]
	var trim: int = bd["trim"]
	var roof: int = L.th["roof"]
	var th_ := 44
	for side in 2:
		var a := i0 - 10 if side == 0 else i1 + 1
		for q in 10:
			for j in range(gl - th_, gl):
				L.s(a + q, j, trim if (gl - j) % 12 == 0 else wall)
			for j2 in range(gl, gl + 6):
				L.s(a + q, j2, wall)
			if (q / 2) % 2 == 1:
				L.sky(a + q, gl - th_)
				L.sky(a + q, gl - th_ + 1)
		for up in 12:
			var hw := 6.0 * (1.0 - float(up) / 12.0)
			for q2 in range(int(round(4.5 - hw)), int(round(4.5 + hw)) + 1):
				L.s(a + q2, gl - th_ - 1 - up, roof)
		brazier(L, a - 6 if side == 0 else a + 15, gl, 12, trim, wall, L.th["glow"])
	var ab := gl - th_ + 10
	arch(L, i0 - 10, i1 + 10, ab, 0, 4, wall, 0, trim)
	var cl: Array = L.th["cloth"]
	banner(L, i0 + 1, ab - 2, 18, 6, cl[0], cl[1])
	banner(L, i1 - 6, ab - 2, 18, 6, cl[0], cl[1])
	statue(L, (i0 + i1) / 2, ab - (i1 - i0 + 21) / 2 + 1, 40.0, 26.0, 1)
	L.commit()
