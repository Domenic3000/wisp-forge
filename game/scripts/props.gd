extends RefCounted
## Props: furniture and town details (tables, beds, shelves, barrels, signs, lamp posts, fences,
## wells, market stalls, hedges...). Each is grown procedurally from a few parts with its own
## random sizes, colours and contents, as a small pixel grid. buildings.gd stamps a prop's pixels
## into the BACKGROUND layer (material DECOR, the pixel's palette colour kept in the cell), so props
## never block you or the foes; 't' pixels become real torches (they light the room).
##
## Pixel chars index PALETTE through CHARS. '.' is empty.

const PALETTE := [
	"#3a2412", "#6b4423", "#8f5f33", "#b07a44",     # 0-3 wood: dark, mid, light, highlight
	"#9c2a2a", "#c84a3a", "#2a4a8c", "#4a72c0",     # 4-7 cloth: red, red light, blue, blue light
	"#2e6a34", "#4f9a4a", "#e8d8b0", "#f4f0e6",     # 8-11 green, green light, cream, white
	"#2a2a30", "#50505a", "#8a8a96", "#e2b048",     # 12-15 iron dark, iron, iron light, gold
	"#9a6c24", "#4a4a52", "#6e6e78", "#9a9aa4",     # 16-19 gold dark, stone dark, stone, stone light
	"#c8a85a", "#9a7a3a", "#a85a3a", "#c8784a",     # 20-23 straw, straw dark, clay, clay light
	"#5ac8e8", "#e05a6a", "#6ad86a", "#5a3a2a",     # 24-27 potion blue, red, green, book brown
	"#8a2a2a", "#2a5a3a", "#e86aa0", "#f0d040",     # 28-31 book red, book green, flower pink, yellow
	"#141018", "#ff8a3a", "#2a5a2a", "#3f8a3a",     # 32-35 black, ember, leaf dark, leaf
	"#6a3a9a", "#9a6ad0", "#7ab0e0", "#3a6a9a",     # 36-39 purple, purple light, sky, water
]
const CHARS := {
	"d": 0, "w": 1, "W": 2, "h": 3, "r": 4, "R": 5, "b": 6, "B": 7, "g": 8, "G": 9, "c": 10, "C": 11,
	"i": 12, "I": 13, "j": 14, "y": 15, "Y": 16, "s": 17, "S": 18, "z": 19, "a": 20, "A": 21, "k": 22,
	"K": 23, "p": 24, "P": 25, "q": 26, "n": 27, "m": 28, "o": 29, "f": 30, "F": 31, "x": 32, "e": 33,
	"l": 34, "L": 35, "v": 36, "V": 37, "u": 38, "U": 39,
}
const CLOTHS := [["r", "R"], ["b", "B"], ["g", "G"], ["v", "V"]]

## A small pixel canvas the props are drawn on.
class Grid:
	var w := 0
	var h := 0
	var px: Array = []
	func _init(ww: int, hh: int) -> void:
		w = ww
		h = hh
		for y in h:
			var row := []
			row.resize(w)
			row.fill(".")
			px.append(row)
	func put(x: int, y: int, ch: String) -> void:
		if x >= 0 and y >= 0 and x < w and y < h:
			px[y][x] = ch
	func rect(x0: int, y0: int, x1: int, y1: int, ch: String) -> void:
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				put(x, y, ch)
	func hline(x0: int, x1: int, y: int, ch: String) -> void:
		rect(x0, y, x1, y, ch)
	func vline(x: int, y0: int, y1: int, ch: String) -> void:
		rect(x, y0, x, y1, ch)
	func rows() -> Array:
		var out := []
		for y in h:
			out.append("".join(PackedStringArray(px[y])))
		return out

static func _done(g: Grid, kind: String, wall := false) -> Dictionary:
	return {"rows": g.rows(), "kind": kind, "wall": wall}

# ------------------------------------------------------------------ furniture --
static func table(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(12, 18)
	var g := Grid.new(w, 8)
	g.hline(0, w - 1, 2, "h")
	g.hline(0, w - 1, 3, "W")
	g.put(0, 3, "d")
	g.put(w - 1, 3, "d")
	for y in range(4, 8):
		g.put(1, y, "d")
		g.put(w - 2, y, "d")
	if rng.randf() < 0.5:
		var cl: Array = CLOTHS[rng.randi_range(0, 3)]
		g.hline(2, w - 3, 2, cl[1])
		g.vline(2, 3, 4, cl[0])
		g.vline(w - 3, 3, 4, cl[0])
	# things on the table: a candle, a mug, a bowl, a bottle
	var x := 2
	while x < w - 3:
		var r := rng.randf()
		if r < 0.2:
			g.put(x, 1, "c")
			g.put(x, 0, "t")
		elif r < 0.4:
			g.rect(x, 0, x + 1, 1, "a")
			g.put(x + 2, 1, "A")
		elif r < 0.55:
			g.hline(x, x + 2, 1, "k")
		elif r < 0.7:
			g.put(x, 1, ["p", "P", "q"][rng.randi_range(0, 2)])
			g.put(x, 0, "j")
		x += rng.randi_range(3, 5)
	return _done(g, "table")

static func chair(rng: RandomNumberGenerator) -> Dictionary:
	var g := Grid.new(6, 11)
	g.vline(0, 0, 10, "d")
	g.vline(1, 1, 5, "w")
	g.hline(0, 5, 6, "W")
	g.vline(5, 6, 10, "d")
	g.vline(0, 6, 10, "d")
	if rng.randf() < 0.5:
		var cl: Array = CLOTHS[rng.randi_range(0, 3)]
		g.hline(1, 4, 5, cl[0])
	return _done(g, "chair")

static func bed(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(20, 25)
	var cl: Array = CLOTHS[rng.randi_range(0, 3)]
	var g := Grid.new(w, 11)
	g.rect(0, 0, 2, 10, "d")
	g.rect(1, 1, 1, 7, "W")
	g.put(1, 0, "h")
	g.rect(3, 4, 6, 6, "C")                          # pillow
	g.put(6, 4, "c")
	g.rect(7, 4, w - 2, 7, cl[0])                     # blanket
	g.hline(7, w - 2, 4, cl[1])
	for x in range(8, w - 2, 3):
		g.put(x, 6, cl[1])
	g.rect(3, 7, w - 1, 8, "w")
	g.vline(w - 1, 5, 10, "d")
	g.rect(3, 9, 3, 10, "d")
	g.vline(w - 2, 9, 10, "d")
	return _done(g, "bed")

## a bookshelf, or a shop's shelf of goods (potions, jars, coins)
static func shelf(rng: RandomNumberGenerator, goods := false) -> Dictionary:
	var w := rng.randi_range(11, 16)
	var h := rng.randi_range(18, 23)
	var g := Grid.new(w, h)
	g.rect(0, 0, w - 1, h - 1, "d")
	g.rect(1, 1, w - 2, h - 2, "x")
	g.hline(0, w - 1, 0, "h")
	var y := h - 2
	while y > 3:
		g.hline(1, w - 2, y, "W")
		var x := 1
		while x < w - 1:
			if goods:
				var r := rng.randf()
				if r < 0.45:
					var pc: String = ["p", "P", "q", "V"][rng.randi_range(0, 3)]
					g.vline(x, y - 3, y - 1, pc)
					g.put(x, y - 4, "j")
				elif r < 0.65:
					g.rect(x, y - 2, x + 1, y - 1, "k")
					x += 1
				elif r < 0.8:
					g.put(x, y - 1, "y")
					g.put(x, y - 2, "Y")
			else:
				if rng.randf() < 0.85:
					var bk: String = ["n", "m", "o", "b", "r", "a"][rng.randi_range(0, 5)]
					var bh := rng.randi_range(3, 4)
					g.vline(x, y - bh, y - 1, bk)
					if rng.randf() < 0.3:
						g.put(x, y - bh, "c")
			x += 1 if not goods else 2
		y -= 5
	return _done(g, "shelf")

## an upright barrel: staves bulging out in the middle, iron hoops, a lid seen a little from above
static func barrel(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(10, 12)
	var h := rng.randi_range(12, 14)
	var g := Grid.new(w, h)
	var cx := (w - 1) * 0.5
	for y in h:
		var bul := sin(PI * (y + 0.5) / h)
		var half := cx - (1.0 - bul) * 2.4
		for x in w:
			var u := (x - cx) / maxf(half, 0.5)
			if absf(u) > 1.0:
				continue
			var ch := "w"
			if u < -0.85 or u > 0.8:
				ch = "d"
			elif u < -0.45:
				ch = "W"
			elif u < 0.35:
				ch = "w" if x % 3 != 0 else "W"
			else:
				ch = "w" if x % 3 != 0 else "d"
			g.put(x, y, ch)
	for hy in [2, h - 3]:
		for x in w:
			if g.px[hy][x] != ".":
				g.put(x, hy, "I" if (x - cx) / cx > -0.4 else "j")
	for x in w:
		if g.px[0][x] != ".":
			g.put(x, 0, "h" if x > 0 and x < w - 1 and g.px[0][x - 1] != "." and g.px[0][x + 1] != "." else "d")
		if g.px[1][x] != ".":
			g.put(x, 1, "d")
	return _done(g, "barrel")

## a keg lying on a cradle: its round end shows (planks, iron rim, a tap)
static func keg(rng: RandomNumberGenerator) -> Dictionary:
	var sz := rng.randi_range(11, 13)
	var g := Grid.new(sz + 2, sz + 3)
	var c := (sz - 1) * 0.5
	for y in sz:
		for x in sz:
			var d := Vector2(x - c, y - c).length()
			if d > c + 0.5:
				continue
			var ch := "W" if x % 3 != 0 else "w"
			if d > c - 0.7:
				ch = "j" if x + y < sz - 3 else "I"
			elif d > c - 1.5:
				ch = "d"
			elif d < 1.0:
				ch = "d"
			g.put(x + 1, y, ch)
	g.put(int(c) + 1, int(c) + 2, "j")
	g.put(int(c) + 1, int(c) + 3, "i")
	for y in range(sz - 2, sz + 3):
		g.put(1, y, "d")
		g.put(sz, y, "d")
	g.hline(0, sz + 1, sz + 1, "w")
	g.hline(0, sz + 1, sz + 2, "d")
	return _done(g, "keg")

## two or three barrels together, sometimes one on top
static func barrels(rng: RandomNumberGenerator) -> Dictionary:
	var parts := [barrel(rng), barrel(rng)]
	if rng.randf() < 0.4:
		parts.append(keg(rng))
	var w := 0
	var h := 0
	for p in parts:
		var pr: Array = p["rows"]
		w += pr[0].length()
		h = maxi(h, pr.size())
	var top := barrel(rng) if rng.randf() < 0.45 else {}
	var th := 0 if top.is_empty() else (top["rows"] as Array).size()
	var g := Grid.new(w, h + th)
	var ox := 0
	for p in parts:
		var pr: Array = p["rows"]
		for y in pr.size():
			for x in pr[y].length():
				if pr[y][x] != ".":
					g.put(ox + x, g.h - pr.size() + y, pr[y][x])
		ox += pr[0].length()
	if th > 0:
		var tr: Array = top["rows"]
		var tx: int = ((parts[0]["rows"] as Array)[0].length()) / 2
		for y in tr.size():
			for x in tr[y].length():
				if tr[y][x] != ".":
					g.put(tx + x, g.h - h - th + y + 1, tr[y][x])
	return _done(g, "barrels")

## any of the barrel kinds
static func barrel_any(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	if r < 0.45:
		return barrel(rng)
	if r < 0.7:
		return keg(rng)
	return barrels(rng)

static func crate(rng: RandomNumberGenerator) -> Dictionary:
	var s := rng.randi_range(8, 10)
	var g := Grid.new(s, s)
	g.rect(0, 0, s - 1, s - 1, "w")
	for k in s:
		g.put(k, k, "W")
		g.put(s - 1 - k, k, "W")
	g.hline(0, s - 1, 0, "h")
	g.hline(0, s - 1, s - 1, "d")
	g.vline(0, 0, s - 1, "d")
	g.vline(s - 1, 0, s - 1, "d")
	return _done(g, "crate")

static func crates(rng: RandomNumberGenerator) -> Dictionary:
	var a := crate(rng)
	var b := crate(rng)
	var ra: Array = a["rows"]
	var rb: Array = b["rows"]
	var w: int = ra[0].length() + rb[0].length()
	var h: int = maxi(ra.size(), rb.size())
	var top := rng.randf() < 0.6
	var g := Grid.new(w, h + (rb.size() if top else 0))
	var oy := g.h - ra.size()
	for y in ra.size():
		for x in ra[y].length():
			g.put(x, oy + y, ra[y][x])
	var bx: int = ra[0].length() if not top else 1
	var by: int = g.h - rb.size() if not top else 0
	for y in rb.size():
		for x in rb[y].length():
			g.put(bx + x, by + y, rb[y][x])
	return _done(g, "crates")

static func dresser(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(10, 13)
	var g := Grid.new(w, 12)
	g.rect(0, 2, w - 1, 11, "w")
	g.hline(0, w - 1, 2, "h")
	for y in [5, 8]:
		g.hline(1, w - 2, y, "d")
	for y in [3, 6, 9]:
		g.put(w / 2, y + 1, "y")
	g.vline(0, 2, 11, "d")
	g.vline(w - 1, 2, 11, "d")
	g.put(2, 1, "k")
	g.put(2, 0, "L")
	g.put(w - 3, 1, "j")
	return _done(g, "dresser")

static func fireplace(rng: RandomNumberGenerator, forge := false) -> Dictionary:
	var w := rng.randi_range(15, 19)
	var h := 15
	var g := Grid.new(w, h)
	g.rect(0, 2, w - 1, h - 1, "S")
	for y in range(2, h):
		for x in w:
			if (x + (y / 2) * 3) % 5 == 0 or y % 2 == 0 and x % 7 == 3:
				g.put(x, y, "s")
	g.hline(0, w - 1, 2, "z")
	g.rect(0, 0, w - 1, 1, "s")
	g.rect(3, 6, w - 4, h - 1, "x")
	g.rect(4, h - 3, w - 5, h - 2, "e" if not forge else "e")
	g.hline(4, w - 5, h - 1, "d")
	g.put(w / 2, h - 4, "t")
	if not forge:
		g.put(4, 1, "k")
		g.put(w - 5, 1, "y")
	return _done(g, "fireplace")

static func painting(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(9, 14)
	var h := rng.randi_range(7, 10)
	var g := Grid.new(w, h)
	g.rect(0, 0, w - 1, h - 1, "y")
	g.rect(1, 1, w - 2, h - 2, "u")
	var hz := rng.randi_range(h / 2, h - 3)
	for x in range(1, w - 1):
		var hill := hz - int(round(sin(float(x) * 0.7 + rng.randf()) * 1.2))
		g.vline(x, clampi(hill, 1, h - 2), h - 2, "g" if x % 3 else "G")
	g.put(rng.randi_range(2, w - 3), 2, "F")
	g.hline(0, w - 1, h - 1, "Y")
	return _done(g, "painting", true)

static func banner(rng: RandomNumberGenerator) -> Dictionary:
	var cl: Array = CLOTHS[rng.randi_range(0, 3)]
	var w := 7
	var h := rng.randi_range(14, 18)
	var g := Grid.new(w + 2, h)
	g.hline(0, w + 1, 0, "d")
	g.rect(1, 1, w, h - 3, cl[0])
	g.put(1, h - 2, cl[0])
	g.put(w, h - 2, cl[0])
	g.vline(1, 1, h - 3, "y")
	g.vline(w, 1, h - 3, "y")
	# an emblem: a star, a sword or a crown, in gold
	var cy := h / 2 - 1
	match rng.randi_range(0, 2):
		0:
			g.put(4, cy - 1, "y"); g.hline(3, 5, cy, "y"); g.put(4, cy + 1, "y")
		1:
			g.vline(4, cy - 3, cy + 2, "j"); g.hline(3, 5, cy + 1, "y")
		_:
			g.hline(3, 5, cy, "y"); g.put(3, cy - 1, "y"); g.put(5, cy - 1, "y"); g.put(4, cy - 1, cl[1])
	return _done(g, "banner", true)

static func potted_plant(rng: RandomNumberGenerator) -> Dictionary:
	var g := Grid.new(7, 11)
	g.rect(1, 7, 5, 10, "k")
	g.hline(0, 6, 7, "K")
	for k in 9:
		var x := 3 + rng.randi_range(-3, 3)
		var y := rng.randi_range(0, 6)
		g.put(x, y, "L" if rng.randf() < 0.6 else "l")
		g.vline(3, y, 6, "l")
	if rng.randf() < 0.6:
		g.put(rng.randi_range(1, 5), rng.randi_range(0, 3), "f" if rng.randf() < 0.5 else "F")
	return _done(g, "plant")

static func rug(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(14, 22)
	var cl: Array = CLOTHS[rng.randi_range(0, 3)]
	var g := Grid.new(w, 2)
	g.hline(0, w - 1, 0, cl[0])
	g.hline(0, w - 1, 1, cl[0])
	for x in range(1, w - 1, 3):
		g.put(x, 0, "y")
		g.put(x + 1, 1, cl[1])
	return _done(g, "rug")

static func anvil(_rng: RandomNumberGenerator) -> Dictionary:
	var g := Grid.new(12, 8)
	g.hline(0, 11, 0, "j")
	g.rect(0, 1, 9, 2, "I")
	g.rect(10, 1, 11, 1, "I")
	g.rect(3, 3, 7, 4, "i")
	g.rect(2, 5, 8, 7, "s")
	g.hline(2, 8, 5, "S")
	return _done(g, "anvil")

static func cauldron(_rng: RandomNumberGenerator) -> Dictionary:
	var g := Grid.new(11, 9)
	g.rect(1, 2, 9, 7, "i")
	g.hline(0, 10, 2, "I")
	g.hline(2, 8, 1, "q")
	g.put(4, 0, "q")
	g.put(7, 0, "G")
	g.hline(2, 8, 8, "e")
	g.put(2, 8, "d")
	g.put(8, 8, "d")
	return _done(g, "cauldron")

static func weapon_rack(rng: RandomNumberGenerator) -> Dictionary:
	var g := Grid.new(12, 16)
	g.hline(0, 11, 3, "d")
	g.hline(0, 11, 12, "d")
	g.vline(0, 3, 15, "d")
	g.vline(11, 3, 15, "d")
	var x := 2
	while x < 10:
		if rng.randf() < 0.5:
			g.vline(x, 0, 11, "j")
			g.hline(x - 1, x + 1, 9, "y")
			g.vline(x, 10, 11, "w")
		else:
			g.vline(x, 1, 13, "w")
			g.put(x, 0, "j")
		x += 3
	return _done(g, "rack", true)

## a shop counter with goods on it
static func counter(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(18, 24)
	var g := Grid.new(w, 11)
	g.rect(0, 3, w - 1, 10, "w")
	g.hline(0, w - 1, 3, "h")
	for x in range(2, w - 1, 4):
		g.vline(x, 5, 9, "d")
	var x2 := 1
	while x2 < w - 2:
		var r := rng.randf()
		if r < 0.3:
			g.put(x2, 2, "y"); g.put(x2 + 1, 2, "Y")
		elif r < 0.6:
			g.vline(x2, 0, 2, ["p", "P", "q"][rng.randi_range(0, 2)])
		elif r < 0.75:
			g.rect(x2, 1, x2 + 1, 2, "k")
		x2 += rng.randi_range(2, 4)
	return _done(g, "counter")

# ------------------------------------------------------------------ outdoors --
## A signpost with a hanging board; the board shows what the place is (a coin for a shop, an
## anvil for a smithy, a mug for a tavern, a bed for an inn, a house otherwise).
static func signpost(_rng: RandomNumberGenerator, icon: String) -> Dictionary:
	var g := Grid.new(13, 22)
	g.vline(0, 0, 21, "d")
	g.vline(1, 0, 21, "w")
	g.hline(0, 11, 1, "d")
	g.vline(5, 2, 3, "i")
	g.vline(10, 2, 3, "i")
	g.rect(3, 4, 12, 11, "w")
	g.hline(3, 12, 4, "h")
	g.hline(3, 12, 11, "d")
	g.vline(3, 4, 11, "d")
	g.vline(12, 4, 11, "d")
	match icon:
		"shop":
			g.rect(6, 6, 9, 9, "y"); g.put(7, 7, "Y"); g.put(8, 8, "Y")
		"smithy":
			g.hline(5, 10, 7, "i"); g.rect(6, 8, 8, 8, "i"); g.hline(6, 9, 9, "i")
		"tavern":
			g.rect(6, 6, 8, 9, "a"); g.vline(9, 7, 8, "A"); g.hline(6, 8, 6, "C")
		"inn":
			g.rect(5, 8, 10, 9, "r"); g.rect(5, 7, 6, 7, "C")
		_:
			g.rect(6, 7, 9, 9, "W"); g.hline(5, 10, 6, "r"); g.put(7, 5, "r"); g.put(8, 5, "r"); g.put(7, 9, "d")
	return _done(g, "sign")

static func lamppost(_rng: RandomNumberGenerator, lit := true) -> Dictionary:
	var h := 28
	var g := Grid.new(5, h)
	g.vline(2, 4, h - 1, "i")
	g.vline(1, h - 3, h - 1, "i")
	g.vline(3, h - 3, h - 1, "i")
	g.hline(0, 4, 0, "i")
	g.vline(0, 1, 3, "i")
	g.vline(4, 1, 3, "i")
	g.vline(1, 1, 3, "t" if lit else "x")
	g.vline(3, 1, 3, "t" if lit else "x")
	g.vline(2, 1, 3, "F" if lit else "x")
	g.hline(0, 4, 4, "I")
	return _done(g, "lamp")

static func fence(_rng: RandomNumberGenerator, length: int) -> Dictionary:
	var g := Grid.new(length, 9)
	for x in range(0, length, 5):
		g.vline(x, 0, 8, "w")
		g.put(x, 0, "h")
	g.vline(length - 1, 0, 8, "w")
	g.hline(0, length - 1, 2, "W")
	g.hline(0, length - 1, 6, "W")
	return _done(g, "fence")

static func hedge(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(8, 15)
	var h := rng.randi_range(6, 9)
	var g := Grid.new(w, h)
	for y in h:
		for x in w:
			var dx := (float(x) - (w - 1) * 0.5) / (w * 0.5)
			var dy := (float(y) - h) / h
			if dx * dx + dy * dy < 1.0 - rng.randf() * 0.15:
				g.put(x, y, "L" if (y < h / 3 or rng.randf() < 0.35) else "l")
	for k in rng.randi_range(0, 4):
		g.put(rng.randi_range(1, w - 2), rng.randi_range(1, h - 3), "f" if rng.randf() < 0.5 else "F")
	return _done(g, "hedge")

static func flowerbed(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(8, 14)
	var g := Grid.new(w, 5)
	g.hline(0, w - 1, 4, "d")
	g.hline(0, w - 1, 3, "w")
	for x in range(1, w - 1):
		if rng.randf() < 0.7:
			var fh := rng.randi_range(1, 2)
			g.vline(x, 3 - fh, 2, "l")
			g.put(x, 2 - fh, ["f", "F", "C", "V"][rng.randi_range(0, 3)])
	return _done(g, "flowers")

static func well(rng: RandomNumberGenerator) -> Dictionary:
	var w := 19
	var h := 26
	var g := Grid.new(w, h)
	g.rect(1, h - 8, w - 2, h - 1, "S")
	for y in range(h - 8, h):
		for x in range(1, w - 1):
			if (x + (y % 2) * 2) % 4 == 0:
				g.put(x, y, "s")
	g.hline(0, w - 1, h - 8, "z")
	g.rect(3, h - 7, w - 4, h - 6, "U")
	g.vline(2, 7, h - 9, "d")
	g.vline(w - 3, 7, h - 9, "d")
	g.hline(2, w - 3, 9, "w")
	g.vline(w / 2, 10, 13, "c")
	g.rect(w / 2 - 1, 14, w / 2 + 1, 16, "w")
	var roof: String = "r" if rng.randf() < 0.6 else "w"
	for k in 7:
		g.hline(k, w - 1 - k, 6 - k, roof if k % 2 == 0 else ("R" if roof == "r" else "W"))
	return _done(g, "well")

static func stall(rng: RandomNumberGenerator) -> Dictionary:
	var w := rng.randi_range(22, 28)
	var h := 26
	var cl: Array = CLOTHS[rng.randi_range(0, 3)]
	var g := Grid.new(w, h)
	g.vline(1, 3, h - 1, "d")
	g.vline(w - 2, 3, h - 1, "d")
	# a striped awning, scalloped at the front
	for y in 4:
		for x in range(0, w):
			g.put(x, y, cl[0] if (x / 3) % 2 == 0 else "C")
	for x in range(0, w, 3):
		g.put(x + 1, 4, cl[0] if (x / 3) % 2 == 0 else "C")
	# the counter and its goods
	var c := counter(rng)
	var cr: Array = c["rows"]
	var cw: int = mini(cr[0].length(), w - 4)
	for y in cr.size():
		for x in cw:
			g.put(2 + x, h - cr.size() + y, cr[y][x])
	# crates of produce under the awning, behind the counter
	for x in range(3, w - 4, 4):
		g.rect(x, h - 14, x + 2, h - 12, "w")
		g.put(x + 1, h - 15, ["q", "R", "F", "K"][rng.randi_range(0, 3)])
	return _done(g, "stall")

static func haybale(_rng: RandomNumberGenerator) -> Dictionary:
	var g := Grid.new(11, 7)
	g.rect(0, 0, 10, 6, "a")
	for x in range(0, 11, 2):
		g.vline(x, 0, 6, "A")
	g.hline(0, 10, 0, "a")
	g.vline(3, 0, 6, "d")
	g.vline(7, 0, 6, "d")
	return _done(g, "hay")

## A prop by name (the furnishing tables in buildings.gd use these names).
static func make(kind: String, rng: RandomNumberGenerator, arg = null) -> Dictionary:
	match kind:
		"table": return table(rng)
		"chair": return chair(rng)
		"bed": return bed(rng)
		"bookshelf": return shelf(rng, false)
		"goods": return shelf(rng, true)
		"barrel": return barrel_any(rng)
		"keg": return keg(rng)
		"barrels": return barrels(rng)
		"crate": return crate(rng)
		"crates": return crates(rng)
		"dresser": return dresser(rng)
		"fireplace": return fireplace(rng)
		"forge": return fireplace(rng, true)
		"painting": return painting(rng)
		"banner": return banner(rng)
		"plant": return potted_plant(rng)
		"rug": return rug(rng)
		"anvil": return anvil(rng)
		"cauldron": return cauldron(rng)
		"rack": return weapon_rack(rng)
		"counter": return counter(rng)
		"sign": return signpost(rng, str(arg) if arg != null else "home")
		"lamp": return lamppost(rng, arg == null or bool(arg))
		"fence": return fence(rng, int(arg) if arg != null else 16)
		"hedge": return hedge(rng)
		"flowers": return flowerbed(rng)
		"well": return well(rng)
		"stall": return stall(rng)
		"hay": return haybale(rng)
	return table(rng)
