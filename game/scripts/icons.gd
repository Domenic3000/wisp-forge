## Pixel icons for the UI (user, 21 Nov: a pixel-art UI), grown from parts like everything else: every
## material gets one from its own colour and what it is (a bevelled block with its pattern, a pile of
## powder, a drop of liquid, a lump of ore with its glints, a cut gem, a log, a leaf...), every spell a
## glyph from `SPELL_ART` in its colour, a few things (a draught, a coin, a letter, furniture) from
## `ITEM_ART`. Each is outlined in the UI's dark ink and cached. `mat(m)`, `spell(id)`, `item(key)`.
extends RefCounted

const INK := Color(0.03, 0.02, 0.06)
const _PROPS := preload("res://scripts/props.gd")
const _WART := preload("res://scripts/workshop_art.gd")

## what a material's icon looks like (by id; the rest: a block, or a pile for powders, a drop for liquids)
const MAT_STYLE := {
	1: "speckle", 2: "speckle", 3: "grass", 12: "glassy", 13: "speckle", 14: "ore", 15: "ore", 16: "gem", 17: "gem",
	18: "orb", 20: "glassy", 21: "speckle", 22: "orb", 23: "shroom", 25: "brick", 26: "pane", 28: "gem", 30: "plank",
	31: "cactus", 32: "plank", 34: "masonry", 35: "masonry", 36: "masonry", 37: "grass", 39: "torch", 42: "rune",
	44: "door", 7: "log", 8: "leaf", 49: "log", 50: "ingot", 51: "gem", 52: "pearl", 53: "gem", 54: "ore",
	55: "gem", 56: "gem", 57: "ingot", 58: "ingot", 59: "ingot", 61: "gem", 62: "orb", 63: "gem",
	64: "orb", 65: "orb", 66: "orb", 67: "orb", 68: "orb", 69: "orb", 70: "orb", 71: "orb", 45: "shroom", 46: "plank", 47: "grass", 48: "grass", 27: "pile", 24: "pile",
}

## spell glyphs, 11 x 11: "#" the spell's colour, "o" its light, "w" white-hot
const SPELL_ART := {
	"mire": ["...........", "...........", "...........", ".#.....#...", "#o#...#o#..", "#o#.#.#o#.#", ".#o#o#o#.#o", "..#owwwo#o#", ".#owwwwwo#.", "#ooooooooo#", ".#########."],
	"thorns": ["#.........#", ".#o.....o#.", "..#o...o#..", "...#o.o#...", "#oo##w##oo#", "...owwwo...", "#oo##w##oo#", "...#o.o#...", "..#o...o#..", ".#o.....o#.", "#.........#"],
	"sovereign": ["...........", "#....#....#", "#o..#o#..o#", "#oo#owo#oo#", "#owoowoowo#", "#ooooooooo#", "#owwwwwwwo#", "###########", "...........", "...........", "..........."],
	"mote": ["...........", "...........", "....#.#....", "...#o#o#...", "..#owwwo#..", "...#www#...", "..#owwwo#..", "...#o#o#...", "....#.#....", "...........", "..........."],
	"spark": ["......#o#..", ".....#o#...", "....#o#....", "...#ow#....", "..#owwww#..", "....#ow#...", "...#o#.....", "..#o#......", ".#o#.......", "#o#........", "#.........."],
	"conjure": ["...........", "..o.....o..", "...........", "...#####...", "..#ooooo#..", "..#o###o#..", "..#o#w#o#..", "..#o###o#..", "..#ooooo#..", "...#####...", ".o.......o."],
	"fireball": ["....#......", "...#o#..#..", "...#oo#.#o.", "..#owo##o#.", ".#owwwoo#..", ".#owwwwo#..", "#owwwwwwo#.", "#owwwwwwo#.", ".#owwwwo#..", "..#oooo#...", "...####...."],
	"tide": ["...........", "....##.....", "...#oo#....", "..#owwo#...", ".#ow..wo#..", "#ow....o#..", "#o....#o#..", "..##.#o##o#", ".#oo#o#.#o#", "#owwo#...##", ".###......."],
	"frost": [".....#.....", "..#..o..#..", "...#.o.#...", "....#w#....", ".#..owo..#.", "#oowwwwwoo#", ".#..owo..#.", "....#w#....", "...#.o.#...", "..#..o..#..", ".....#....."],
	"quake": ["...#####...", "..#ooo#o#..", ".#oo#o##o#.", "#oo#..#oo#.", "#o#.w.#.o#.", "#o##.##oo#.", "#oo##.#oo#.", ".#oo#oooo#.", "..#oo#oo#..", "...#####...", "#.#...#.#.#"],
	"blink": ["...........", "...#####...", "..#ooooo#..", ".#o##w##o#.", "#o#..w..#o#", "#ow.www.wo#", "#o#..w..#o#", ".#o##w##o#.", "..#ooooo#..", "...#####...", "..........."],
	"starfall": [".....#.....", ".....o.....", "....#w#....", "....owo....", "#oowwwwwoo#", ".#owwwwwo#.", "..#owwwo#..", "..#ow#wo#..", ".#o#...#o#.", ".#.......#.", "..........."],
	"mend": ["...........", "....###....", "....#o#....", "....#w#....", ".###owo###.", ".#owwwwwo#.", ".###owo###.", "....#w#....", "....#o#....", "....###....", "..........."],
	"recall": ["...#####...", "..#ooooo#..", ".#o#####o#.", "#o#.....#o#", "#o#.....#o#", "#o#..w..#o#", "#o#.www.#o#", "#o#..w..#o#", "#o#.....#o#", "#####w#####", "..........."],
}

## items: chars map to colours in `ITEM_COL` per key ("." empty)
const ITEM_ART := {
	"potion": ["...ww...", "...cc...", "...cc...", "..#rr#..", ".#rrrr#.", "#rwrrrr#", "#rrrrrr#", "#rrrrrr#", ".#rrrr#.", "..####.."],
	"coin": ["..####..", ".#yyyy#.", "#yywyyy#", "#ywy#yy#", "#yyy#yy#", "#yyy#yy#", "#yyy#yy#", ".#yyyy#.", "..####.."],
	"crate": ["#########", "#bbbbbbb#", "#b#####b#", "#b#bbb#b#", "#bb#b#bb#", "#b#bbb#b#", "#b#####b#", "#bbbbbbb#", "#########"],
	"letter": ["##########", "#wwwwwwww#", "#ww#ww#ww#", "#w#wwww#w#", "##wwrrww##", "#wwwrrwww#", "#wwwwwwww#", "##########"],
	"chair": ["#.......", "#.......", "#.......", "#.......", "######..", "#....#..", "#....#..", "#....#.."],
	"heart": [".##.##.", "#ww####", "#######", ".#####.", "..###..", "...#..."],
	"drop": ["..#..", "..#..", ".###.", "#w###", "#w###", "#####", ".###."],
	"bubble": [".###.", "#w..#", "#...#", "#...#", ".###."],
	"skull": [".###.", "#####", "#.#.#", "#####", ".#.#."],
	"hull": ["..w..", "..w..", "#####", "c###c", ".###."],
	"book": ["########.", "#rrrrrr#.", "#ryyyyr##", "#rrrrrr#w", "#ryyyyr#w", "#rrrrrr#w", "#rrrrrr#w", "########w", ".wwwwwwww"],
}
## things you forge or buy that aren't a material, spell or draught (a recipe's or ward's own picture;
## `thing(id)` picks the art and its colours by id: `THINGS`)
const THING_ART := {
	"staff": [".......##.", "......#ow#", "......#wo#", ".....b.##.", "....b.....", "...b......", "..b.......", ".b........", "b........."],
	"feather": [".......w.", "......wwl", ".....wwwl", "....wwwwl", "...wwwlw.", "..wwwlw..", "..wwlw...", ".wl......", ".l.......", "l........"],
	"rings": ["..ooooo..", ".o.....o.", "o..www..o", "o.w...w.o", "o.w.y.w.o", "o.w...w.o", "o..www..o", ".o.....o.", "..ooooo.."],
	"bloom": ["..p...p..", ".pPp.pPp.", "..pyyyp..", ".pPyyyPp.", "..pPpPp..", "....g....", "..g.g....", "...gg.g..", "....gg...", "....g...."],
	"crystal": ["....#....", "...#w#...", "..#wo##..", "..#oo##..", ".#woo###.", ".#ooo###.", "..#oo##..", "...#o#...", "....#...."],
	"shield": ["#########", "#ssssssS#", "#sffffsS#", "#sfwwfsS#", "#sfwwfsS#", ".#sffsS#.", ".#ssssS#.", "..#ssS#..", "...###..."],
	"amulet": ["c.......c", ".c.....c.", "..c...c..", "...c.c...", "...###...", "..#ooo#..", "..#owo#..", "..#ooo#..", "...###..."],
	"veil": ["..yyyyy..", ".yyyyyyy.", "yywyyyyyy", "yyyyyyyyy", "vvvvvvvvv", "vVvVvVvVv", "vvvvvvvvv", ".v.v.v.v."],
	"mask": [".#######.", "#mmmmmmm#", "#m##m##m#", "#mmmmmmm#", "#mmm#mmm#", ".#mmmmm#.", "..#fff#..", "..#f#f#..", "...###..."],
	"skiff": ["...ggggg...", "..g.....g..", ".g...o...g.", "bbbbbbbbbbb", ".bBBBBBBBb.", "..bbbbbbb..", "...o...o..."],
	"drive": ["..#####..", ".#iiiii#.", "#ii###ii#", "#i#rrr#i#", "#i#rwr#i#", "#i#rrr#i#", "#ii###ii#", ".#iiiii#.", "..#####.."],
	"engine": ["..iiiii..", ".iIIIIIi.", ".iIiiiIi.", ".iIIIIIi.", "..iiiii..", "...fff...", "..fwwwf..", "...fwf...", "....f...."],
	"bubble": ["..ccccc..", ".c.....c.", "c..ggg..c", "c.gbbbg.c", "c.bbbbb.c", "c..o.o..c", ".c.....c.", "..ccccc..", "........."],
	"cannon": [".........", "......ww.", "..iiiiIIw", ".iIIIIIIw", "biIiiiIIw", ".iIIIIIIw", "..iiiiIIw", "......ww.", "...bb...."],
	"sail": ["....m....", "....ms...", "....mss..", "....msss.", "....mssss", "....msss.", "....mss..", "bbbbbbbbb", ".bbbbbbb."],
	"lens": ["..###....", ".#www#...", "#wcccw#..", "#wcccwoo.", "#wcccwooo", ".#www#...", "..###....", "..#.#....", ".##.##..."],
	"band": ["..#####..", ".#ooooo#.", "#oo...oo#", "#o.....o#", "#o..w..o#", "#oo...oo#", ".#ooooo#.", "..#####.."],
	"blade": ["........w", ".......wo", "......wo.", ".....wo..", "....wo...", "...wo....", ".#wo.....", "..#......", ".b.#.....", "b........"],
	"sigil": ["..#####..", ".#ooooo#.", "#oo#w#oo#", "#o#ooo#o#", "#owoooow#", "#o#ooo#o#", "#oo#w#oo#", ".#ooooo#.", "..#####.."],
	"cloak": ["...###...", "..#ooo#..", ".#owwwo#.", ".#ooooo#.", "#oo#o#oo#", "#o#ooo#o#", "#ooo#ooo#", "#o#ooo#o#", ".#.#.#.#."],
	"keel": ["....c....", "...cwc...", "#########", "#ccc#ccc#", ".#bbbbb#.", "..#bbb#..", "...#c#...", "....c....", "........."],
	"lattice": ["#.#.#.#.#", "#########", "#.c.#.c.#", "#########", "#.#.w.#.#", "#########", "#.c.#.c.#", "#########", "#.#.#.#.#"],
	"prow": ["........w", "......##i", ".....#iii", "....#iiii", "..##iiiii", "##iiwiiii", "..##iiiii", "....#iiii", ".....##.."],
	"scroll": ["yyyyyyyy.", "ywwwwwwy.", ".wkkkkw..", ".wwwwww..", ".wkkkw...", ".wwwwww..", ".wkkkkw..", "ywwwwwwy.", "yyyyyyyy."],
}
## id -> [art, {char: colour}]
const THINGS := {
	"tier2": ["staff", {"b": Color(0.55, 0.36, 0.2), "o": Color(0.95, 0.55, 0.25), "w": Color(1, 0.85, 0.6), "#": Color(0.45, 0.22, 0.08)}],
	"tier3": ["staff", {"b": Color(0.42, 0.28, 0.18), "o": Color(0.5, 0.3, 0.75), "w": Color(0.85, 0.7, 1.0), "#": Color(0.16, 0.08, 0.26)}],
	"tier4": ["staff", {"b": Color(0.3, 0.2, 0.15), "o": Color(1.0, 0.4, 0.2), "w": Color(1, 0.95, 0.5), "#": Color(0.5, 0.1, 0.05)}],
	"delve1": ["sigil", {"#": Color(0.35, 0.2, 0.1), "o": Color(0.85, 0.5, 0.25), "w": Color(1, 0.85, 0.6)}],
	"delve2": ["sigil", {"#": Color(0.15, 0.15, 0.35), "o": Color(0.5, 0.58, 1.0), "w": Color(0.9, 0.92, 1.0)}],
	"delve3": ["sigil", {"#": Color(0.2, 0.25, 0.35), "o": Color(0.7, 0.8, 0.95), "w": Color(1, 1, 1)}],
	"levitate": ["feather", {"w": Color(0.92, 0.95, 1.0), "l": Color(0.55, 0.6, 0.8)}],
	"wide": ["rings", {"o": Color(0.4, 0.6, 1.0), "w": Color(0.85, 0.92, 1.0), "y": Color(1, 0.8, 0.3)}],
	"vital": ["bloom", {"p": Color(0.9, 0.3, 0.45), "P": Color(1, 0.6, 0.7), "y": Color(1, 0.85, 0.35), "g": Color(0.3, 0.7, 0.3)}],
	"mana": ["crystal", {"#": Color(0.12, 0.2, 0.55), "o": Color(0.35, 0.55, 1.0), "w": Color(0.85, 0.95, 1.0)}],
	"ward": ["shield", {"#": Color(0.2, 0.2, 0.25), "s": Color(0.62, 0.64, 0.7), "S": Color(0.4, 0.42, 0.48), "f": Color(1.0, 0.45, 0.15), "w": Color(1, 0.88, 0.4)}],
	"heat_ward": ["shield", {"#": Color(0.2, 0.2, 0.25), "s": Color(0.62, 0.64, 0.7), "S": Color(0.4, 0.42, 0.48), "f": Color(1.0, 0.45, 0.15), "w": Color(1, 0.88, 0.4)}],
	"hearth": ["amulet", {"c": Color(0.85, 0.65, 0.3), "#": Color(0.45, 0.12, 0.05), "o": Color(1.0, 0.45, 0.15), "w": Color(1, 0.9, 0.5)}],
	"tidecharm": ["amulet", {"c": Color(0.75, 0.78, 0.85), "#": Color(0.08, 0.2, 0.45), "o": Color(0.3, 0.6, 1.0), "w": Color(0.85, 0.95, 1.0)}],
	"sunveil": ["veil", {"y": Color(1.0, 0.82, 0.3), "w": Color(1, 1, 0.85), "v": Color(0.82, 0.72, 0.55), "V": Color(0.95, 0.88, 0.72)}],
	"fenmask": ["mask", {"#": Color(0.12, 0.22, 0.12), "m": Color(0.38, 0.6, 0.32), "f": Color(0.6, 0.6, 0.55)}],
	"skiff": ["skiff", {"g": Color(0.6, 0.9, 1.0), "b": Color(0.5, 0.32, 0.18), "B": Color(0.72, 0.5, 0.3), "o": Color(0.55, 0.95, 1.0)}],
	"drive": ["drive", {"#": Color(0.15, 0.15, 0.22), "i": Color(0.5, 0.55, 0.68), "r": Color(1.0, 0.35, 0.15), "w": Color(1, 0.9, 0.45)}],
	"engine": ["engine", {"i": Color(0.4, 0.44, 0.55), "I": Color(0.65, 0.7, 0.82), "f": Color(0.4, 0.8, 1.0), "w": Color(0.9, 1, 1)}],
	"shield": ["bubble", {"c": Color(0.55, 0.92, 1.0), "g": Color(0.6, 0.9, 1.0), "b": Color(0.5, 0.32, 0.18), "o": Color(0.55, 0.95, 1.0)}],
	"cannon": ["cannon", {"i": Color(0.36, 0.4, 0.48), "I": Color(0.6, 0.66, 0.76), "w": Color(0.7, 0.95, 1.0), "b": Color(0.5, 0.32, 0.18)}],
	"sail": ["sail", {"m": Color(0.5, 0.32, 0.18), "s": Color(0.6, 0.92, 1.0), "b": Color(0.45, 0.3, 0.17)}],
	"beam": ["lens", {"#": Color(0.3, 0.32, 0.4), "w": Color(0.75, 0.8, 0.9), "c": Color(0.75, 0.5, 1.0), "o": Color(0.85, 0.7, 1.0)}],
	"scanner": ["lens", {"#": Color(0.25, 0.12, 0.4), "w": Color(0.6, 0.95, 0.4), "c": Color(0.5, 0.25, 0.85), "o": Color(0.75, 1.0, 0.55)}],
	"part_scanner": ["lens", {"#": Color(0.25, 0.12, 0.4), "w": Color(0.6, 0.95, 0.4), "c": Color(0.5, 0.25, 0.85), "o": Color(0.75, 1.0, 0.55)}],
	"gear:wispband": ["band", {"#": Color(0.15, 0.25, 0.35), "o": Color(0.5, 0.85, 0.95), "w": Color(1, 1, 1)}],
	"gear:staredge": ["blade", {"w": Color(0.95, 0.95, 1.0), "o": Color(0.6, 0.65, 0.8), "#": Color(0.85, 0.7, 0.3), "b": Color(0.45, 0.3, 0.18)}],
	"voidmantle": ["cloak", {"#": Color(0.12, 0.06, 0.25), "o": Color(0.4, 0.22, 0.72), "w": Color(0.85, 0.7, 1.0)}],
	"keel": ["keel", {"#": Color(0.2, 0.18, 0.25), "c": Color(0.85, 0.95, 1.0), "w": Color(1, 1, 1), "b": Color(0.35, 0.6, 0.7)}],
	"lattice": ["lattice", {"#": Color(0.85, 0.5, 0.25), "c": Color(0.6, 0.8, 1.0), "w": Color(1, 1, 1)}],
	"radward": ["shield", {"#": Color(0.15, 0.25, 0.1), "s": Color(0.6, 0.66, 0.6), "S": Color(0.4, 0.46, 0.4), "f": Color(0.6, 1.0, 0.35), "w": Color(0.95, 1.0, 0.75)}],
	"rimeprow": ["prow", {"#": Color(0.25, 0.3, 0.4), "i": Color(0.68, 0.74, 0.86), "w": Color(0.85, 1.0, 0.75)}],
	"harness": ["keel", {"#": Color(0.15, 0.08, 0.28), "c": Color(0.75, 0.5, 1.0), "w": Color(0.95, 0.9, 1.0), "b": Color(0.5, 0.32, 0.18)}],
	"recipe": ["scroll", {"y": Color(0.75, 0.55, 0.3), "w": Color(0.95, 0.9, 0.75), "k": Color(0.45, 0.35, 0.3)}],
}

const ITEM_COL := {
	"potion": {"#": Color(0.45, 0.08, 0.14), "r": Color(0.9, 0.2, 0.3), "w": Color(1, 0.85, 0.85), "c": Color(0.7, 0.52, 0.3)},
	"coin": {"#": Color(0.6, 0.38, 0.06), "y": Color(1.0, 0.8, 0.25), "w": Color(1, 0.97, 0.75)},
	"crate": {"#": Color(0.35, 0.22, 0.12), "b": Color(0.72, 0.5, 0.28)},
	"letter": {"#": Color(0.55, 0.45, 0.32), "w": Color(0.95, 0.9, 0.78), "r": Color(0.8, 0.15, 0.15)},
	"chair": {"#": Color(0.6, 0.4, 0.22)},
	"heart": {"#": Color(0.95, 0.3, 0.35), "w": Color(1, 0.8, 0.8)},
	"drop": {"#": Color(0.4, 0.58, 1.0), "w": Color(0.8, 0.9, 1.0)},
	"bubble": {"#": Color(0.6, 0.9, 0.95), "w": Color(1, 1, 1)},
	"skull": {"#": Color(0.95, 0.88, 0.75)},
	"hull": {"#": Color(0.62, 0.42, 0.26), "c": Color(0.85, 0.55, 0.3), "w": Color(0.75, 0.9, 1.0)},
	"book": {"#": Color(0.3, 0.12, 0.2), "r": Color(0.6, 0.2, 0.3), "y": Color(1.0, 0.8, 0.3), "w": Color(0.92, 0.88, 0.78)},
}

static var _cache := {}

static func _outlined(img: Image) -> ImageTexture:
	var w := img.get_width()
	var h := img.get_height()
	var out := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(img, Rect2i(0, 0, w, h), Vector2i(1, 1))
	var src: Image = out.duplicate()
	for y in h + 2:
		for x in w + 2:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < w + 2 and q.y < h + 2 and src.get_pixel(q.x, q.y).a > 0.5:
					out.set_pixel(x, y, INK)
					break
	return ImageTexture.create_from_image(out)

static func _art(rows: Array, cols: Dictionary) -> Image:
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var img := Image.create(w, rows.size(), false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in rows.size():
		var r2: String = rows[y]
		for x in r2.length():
			if cols.has(r2[x]):
				img.set_pixel(x, y, cols[r2[x]])
	return img

## a spell's glyph, in its colour
static func spell(id: String) -> ImageTexture:
	var key := "s_" + id
	if _cache.has(key):
		return _cache[key]
	var c: Color = Defs.SPELLS.get(id, {}).get("color", Color(0.8, 0.8, 1.0))
	var rows: Array = SPELL_ART.get(String(Defs.SPELLS.get(id, {}).get("art", id)), SPELL_ART["spark"])
	var tex := _outlined(_art(rows, {"#": c.darkened(0.25), "o": c.lightened(0.25), "w": Color(1, 1, 0.95)}))
	_cache[key] = tex
	return tex

static func item(key: String) -> ImageTexture:
	var k := "i_" + key
	if _cache.has(k):
		return _cache[k]
	var tex := _outlined(_art(ITEM_ART[key], ITEM_COL[key]))
	_cache[k] = tex
	return tex

## a forged or bought thing's own picture (`THINGS`), or null when it has none
static func thing(id: String) -> ImageTexture:
	var k := "t_" + id
	if _cache.has(k):
		return _cache[k]
	if id.begins_with("sigil_") and Defs.BOSSES.has(id.substr(6)):
		# (a guardian's sigil: a seal in its colour)
		var bc: Color = Defs.BOSSES[id.substr(6)]["col"]
		var stex := _outlined(_art(THING_ART["sigil"], {"#": bc.darkened(0.55), "o": bc, "w": bc.lightened(0.7)}))
		_cache[k] = stex
		return stex
	if not THINGS.has(id):
		return null
	var t: Array = THINGS[id]
	var tex := _outlined(_art(THING_ART[t[0]], t[1]))
	_cache[k] = tex
	return tex

## a piece of furniture's icon: its own pixel rows (props.gd's palette), shrunk to fit 13 x 13
static func prop_rows(rows: Array) -> ImageTexture:
	var k := "p_" + str(hash(rows))
	if _cache.has(k):
		return _cache[k]
	var h := rows.size()
	var w := 0
	for r in rows:
		w = maxi(w, (r as String).length())
	var stp := maxi(1, int(ceil(float(maxi(w, h)) / 13.0)))
	var ow := maxi(1, (w + stp - 1) / stp)
	var oh := maxi(1, (h + stp - 1) / stp)
	var img := Image.create(ow, oh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in oh:
		for x in ow:
			# (the first filled pixel of the block, so thin legs and edges aren't lost)
			var ch := "."
			for dy in stp:
				for dx in stp:
					var yy := y * stp + dy
					var xx := x * stp + dx
					if ch == "." and yy < h and xx < (rows[yy] as String).length():
						ch = (rows[yy] as String)[xx]
			if ch != "." and _PROPS.CHARS.has(ch):
				img.set_pixel(x, y, Color(String(_PROPS.PALETTE[int(_PROPS.CHARS[ch])])))
			elif ch == "t":
				img.set_pixel(x, y, Color(1.0, 0.7, 0.2))
	var tex := _outlined(img)
	_cache[k] = tex
	return tex

## a workshop carried in the satchel: its own picture shrunk to an icon (the first filled pixel of each block)
static func station(kind: String) -> ImageTexture:
	var k := "st_" + kind
	if _cache.has(k):
		return _cache[k]
	var src: Image = _WART.frames(kind)["body"]
	var w := src.get_width()
	var h := src.get_height()
	var stp := maxi(1, int(ceil(float(maxi(w, h)) / 13.0)))
	var ow := maxi(1, (w + stp - 1) / stp)
	var oh := maxi(1, (h + stp - 1) / stp)
	var img := Image.create(ow, oh, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in oh:
		for x in ow:
			var c := Color(0, 0, 0, 0)
			for dy in stp:
				for dx in stp:
					var yy := y * stp + dy
					var xx := x * stp + dx
					if c.a < 0.5 and yy < h and xx < w:
						c = src.get_pixel(xx, yy)
			if c.a >= 0.5:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	var tex := _outlined(img)
	_cache[k] = tex
	return tex

## a furniture recipe's icon: the piece drawn with a fixed seed (its look in the forge never flickers)
static func prop(kind: String) -> ImageTexture:
	var k := "pk_" + kind
	if _cache.has(k):
		return _cache[k]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var d: Dictionary = _PROPS.make(kind, rng, null)
	var tex := prop_rows(d.get("rows", ["#"]))
	_cache[k] = tex
	return tex

## a Still's draught (Defs.DRAUGHTS): the potion bottle in the draught's colour
static func draught(id: String) -> ImageTexture:
	var k := "d_" + id
	if _cache.has(k):
		return _cache[k]
	var c: Color = Defs.DRAUGHTS[id]["col"]
	var tex := _outlined(_art(ITEM_ART["potion"], {"#": c.darkened(0.55), "r": c, "w": c.lightened(0.6), "c": Color(0.7, 0.52, 0.3)}))
	_cache[k] = tex
	return tex

## a material's icon, 9 x 9 (11 with its outline)
## (user, 25 Nov: locked pages of the recipe book "as smudged sketches"): an icon redrawn as an ink sketch on
## a page: sepia strokes by its shading, a few gaps where the ink didn't take, and a faint smudge beside each
## stroke. Cached by the icon.
static func sketch(src: Texture2D) -> ImageTexture:
	var key := "sk_%d" % src.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var im: Image = src.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var w := im.get_width()
	var h := im.get_height()
	var out := Image.create(w + 1, h + 1, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var ink := Color(0.27, 0.19, 0.11)
	for y in h:
		for x in w:
			var c := im.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if ((x * 73856093) ^ (y * 19349663)) % 7 == 0:
				continue                                     # (where the ink didn't take)
			var lum := c.get_luminance()
			out.set_pixel(x, y, Color(ink.r, ink.g, ink.b, clampf(0.25 + 0.6 * (1.0 - lum), 0.25, 0.85)))
			if out.get_pixel(x + 1, y + 1).a < 0.05:
				out.set_pixel(x + 1, y + 1, Color(ink.r, ink.g, ink.b, 0.12))     # (the smudge)
	var t := ImageTexture.create_from_image(out)
	_cache[key] = t
	return t

static func mat(m: int) -> ImageTexture:
	var key := "m_%d" % m
	if _cache.has(key):
		return _cache[key]
	var base: Color = Defs.COLOR[m]
	base.a = 1.0
	var style: String = MAT_STYLE.get(m, "")
	if style == "":
		var kd: int = Defs.KIND[m]
		style = "pile" if kd == Defs.K_POWDER else ("drop" if kd == Defs.K_LIQUID else "block")
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := RandomNumberGenerator.new()
	r.seed = m * 7919 + 13
	var hi := base.lightened(0.35)
	var lo := base.darkened(0.35)
	var dk := base.darkened(0.55)
	match style:
		"block", "speckle", "glassy", "grass", "brick", "plank", "masonry", "rune", "door", "pane":
			# a bevelled block, lit from the top left, with the material's own pattern
			for y in 9:
				for x in 9:
					var c := base
					if x == 0 or y == 0:
						c = hi
					elif x == 8 or y == 8:
						c = lo
					img.set_pixel(x, y, c)
			match style:
				"speckle", "block":
					for k in 9:
						img.set_pixel(r.randi_range(1, 7), r.randi_range(1, 7), base.darkened(0.2) if k % 2 == 0 else base.lightened(0.15))
				"glassy":
					for k2 in 4:
						img.set_pixel(2 + k2, 5 - k2, hi.lightened(0.3))
				"grass":
					var g := Color(0.35, 0.75, 0.3) if m == Defs.GRASS or m == Defs.MOSSBLOCK else base.lightened(0.2)
					for x2 in 9:
						img.set_pixel(x2, 0, g.lightened(0.2))
						img.set_pixel(x2, 1, g)
						if r.randf() < 0.5:
							img.set_pixel(x2, 2, g.darkened(0.2))
					if m == Defs.GRASS or m == Defs.MOSSBLOCK:
						for x3 in range(1, 8):
							for y3 in range(3, 8):
								img.set_pixel(x3, y3, Defs.COLOR[Defs.DIRT] if m == Defs.GRASS else base)
				"brick":
					for y4 in 9:
						for x4 in 9:
							if y4 % 3 == 2 or (x4 + (4 if (y4 / 3) % 2 == 1 else 0)) % 8 == 0:
								img.set_pixel(x4, y4, dk)
				"plank":
					for y5 in [2, 5]:
						for x5 in 9:
							img.set_pixel(x5, y5, lo)
					img.set_pixel(6, 1, lo)
					img.set_pixel(2, 4, lo)
					img.set_pixel(5, 7, lo)
				"masonry":
					for x6 in 9:
						img.set_pixel(x6, 4, dk)
					for y6 in 9:
						img.set_pixel(4 if y6 < 4 else 2, y6, dk)
				"rune":
					for p in [Vector2i(4, 2), Vector2i(3, 3), Vector2i(5, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(3, 6), Vector2i(5, 6)]:
						img.set_pixel(p.x, p.y, Color(0.6, 0.85, 1.0))
				"door":
					for y7 in 9:
						img.set_pixel(4, y7, lo)
					img.set_pixel(6, 4, Color(1, 0.85, 0.3))
				"pane":
					for y8 in 9:
						for x8 in 9:
							var cc := Color(base.r, base.g, base.b, 0.55)
							if x8 == 0 or y8 == 0 or x8 == 8 or y8 == 8 or x8 == 4 or y8 == 4:
								cc = Color(0.55, 0.42, 0.28)
							img.set_pixel(x8, y8, cc)
					img.set_pixel(1, 2, Color(1, 1, 1, 0.9))
					img.set_pixel(2, 1, Color(1, 1, 1, 0.9))
		"pile":
			# a mound of grains
			for y in range(2, 9):
				var hw := int((y - 1) * 0.75) + 1
				for x in range(4 - hw, 5 + hw):
					if x >= 0 and x < 9:
						var c2 := base if r.randf() < 0.6 else (hi if r.randf() < 0.5 else lo)
						if y == 8:
							c2 = lo
						img.set_pixel(x, y, c2)
		"drop":
			var rows := ["....#....", "....#....", "...###...", "..##w##..", ".###w###.", ".###.###.", ".#######.", "..#####..", "...###..."]
			for y in 9:
				for x in 9:
					var ch: String = rows[y][x]
					if ch != ".":
						img.set_pixel(x, y, hi.lightened(0.4) if ch == "w" else (base if y < 6 else lo))
		"ore":
			# a grey lump with glints of the ore
			var rock := Color(0.42, 0.4, 0.44) if m != Defs.COAL else Color(0.25, 0.24, 0.27)
			var lump := ["..#####..", ".#######.", "#########", "#########", "#########", "#########", ".#######.", "..#####..", "........."]
			for y in 9:
				for x in 9:
					if lump[y][x] == "#":
						img.set_pixel(x, y, rock.lightened(0.2) if y < 2 else (rock.darkened(0.25) if y > 5 else rock))
			for p2 in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(5, 4), Vector2i(6, 4), Vector2i(5, 5), Vector2i(2, 5), Vector2i(3, 6)]:
				img.set_pixel(p2.x, p2.y, base.lightened(0.15))
			img.set_pixel(3, 2, base.lightened(0.5))
		"gem":
			# a cut crystal, faceted
			var gem := ["....#....", "...###...", "..#####..", ".#######.", "#########", ".#######.", "..#####..", "...###...", "....#...."]
			for y in 9:
				for x in 9:
					if gem[y][x] == "#":
						var c3 := base
						if x < 4 and y < 5:
							c3 = hi
						elif x > 4 and y > 4:
							c3 = lo
						img.set_pixel(x, y, c3)
			img.set_pixel(3, 2, Color(1, 1, 1))
		"pearl", "orb":
			for y in 9:
				for x in 9:
					var d := Vector2(x - 4, y - 4).length()
					if d <= 4.2:
						img.set_pixel(x, y, hi if d < 2.0 else (base if d < 3.4 else lo))
			img.set_pixel(3, 2, Color(1, 1, 1))
			img.set_pixel(2, 3, Color(1, 1, 1, 0.7))
		"ingot":
			var ing := [".........", ".........", "..#####..", ".#######.", "#########", "#########", "#########", ".........", "........."]
			for y in 9:
				for x in 9:
					if ing[y][x] == "#":
						img.set_pixel(x, y, hi if y == 2 else (base if y < 5 else lo))
			img.set_pixel(3, 3, Color(1, 1, 1))
		"log":
			for y in range(1, 8):
				for x in 9:
					img.set_pixel(x, y, base if y > 1 and y < 7 else lo)
			for y9 in range(1, 8):
				img.set_pixel(7, y9, Color(0.85, 0.7, 0.45))
				img.set_pixel(8, y9, Color(0.7, 0.55, 0.32))
			img.set_pixel(7, 4, Color(0.55, 0.4, 0.22))
			for x9 in [1, 4]:
				img.set_pixel(x9, 3, lo)
		"leaf":
			var lf := [".......##", ".....####", "...######", "..#####.#", ".#####.##", ".####.###", "..#.####.", ".#.####..", "#........"]
			for y in 9:
				for x in 9:
					if lf[y][x] == "#":
						img.set_pixel(x, y, hi if x + y < 8 else base)
		"shroom":
			var sh := ["..#####..", ".#######.", "####w####", "#########", "...###...", "...###...", "...###...", "..#####..", "........."]
			for y in 9:
				for x in 9:
					var ch2: String = sh[y][x]
					if ch2 != ".":
						img.set_pixel(x, y, Color(1, 1, 0.9) if ch2 == "w" else (base if y < 4 else Color(0.9, 0.85, 0.72)))
		"cactus":
			for y in 9:
				for x in range(3, 6):
					img.set_pixel(x, y, base if x == 4 else lo)
			for y2 in range(2, 5):
				img.set_pixel(1, y2, base)
				img.set_pixel(7, y2 + 1, base)
			img.set_pixel(2, 4, base)
			img.set_pixel(6, 5, base)
		"torch":
			for y in range(4, 9):
				img.set_pixel(4, y, Color(0.55, 0.38, 0.2))
			img.set_pixel(4, 1, Color(1, 0.95, 0.6))
			img.set_pixel(4, 2, Color(1, 0.7, 0.2))
			img.set_pixel(3, 2, Color(1, 0.5, 0.1))
			img.set_pixel(5, 2, Color(1, 0.5, 0.1))
			img.set_pixel(4, 3, Color(1, 0.55, 0.15))
	var tex := _outlined(img)
	_cache[key] = tex
	return tex
