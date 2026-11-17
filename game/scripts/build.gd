extends RefCounted
## Player building (build mode, B). Everything you can put up is a "piece" from the same procedural
## parts the planet's own buildings are made of:
##  - back walls, painted with a brush (one material per cell) where there is no background yet;
##    they are load-bearing like a generated building's walls;
##  - doors (a 3 x 30 doorway filled with door cells, then opened and closed like any other door);
##  - platforms (a strip of one-way scaffold);
##  - furniture and outdoor details, grown by props.gd: you see the exact design before placing it,
##    R rolls a new one, T mirrors it.
## Placed things are ordinary cells (they obey the physics: put a shelf on nothing and it falls),
## so they are saved with the world and taken down with the dig and deconstruct actions.

const Props := preload("res://scripts/props.gd")

const CATS := ["Walls", "Doors & Platforms", "Furniture", "Outdoors"]
const DOOR_W := 3
const DOOR_H := 30
const PLATFORM_W := 9
const WALL_R := 2.6

## The catalogue. kind: "wall" (painted), "door", "platform", "prop" (a props.gd design, `prop` is
## its name, `arg` its option). cost: material id -> amount (a wall's cost is per cell).
static func pieces() -> Array:
	return [
		{"cat": 0, "name": "Plank Wall", "kind": "wall", "mat": Defs.PLANK, "cost": {Defs.PLANK: 1}},
		{"cat": 0, "name": "Log Wall", "kind": "wall", "mat": Defs.WOOD, "cost": {Defs.WOOD: 1}},
		{"cat": 0, "name": "Stone Wall", "kind": "wall", "mat": Defs.MASONRY, "cost": {Defs.MASONRY: 1}},
		{"cat": 0, "name": "Brick Wall", "kind": "wall", "mat": Defs.BRICK, "cost": {Defs.BRICK: 1}},
		{"cat": 0, "name": "Sandstone Wall", "kind": "wall", "mat": Defs.SANDSTONE, "cost": {Defs.SANDSTONE: 1}},
		{"cat": 0, "name": "Glass Pane", "kind": "wall", "mat": Defs.GLASS, "cost": {Defs.GLASS: 1}},
		{"cat": 1, "name": "Wooden Door", "kind": "door", "cost": {Defs.WOODDOOR: 1}, "alt": {Defs.PLANK: 8}},
		{"cat": 1, "name": "Platform", "kind": "platform", "cost": {Defs.PLANK: 4}},
		{"cat": 2, "name": "Table", "kind": "prop", "prop": "table", "cost": {Defs.PLANK: 6}},
		{"cat": 2, "name": "Chair", "kind": "prop", "prop": "chair", "cost": {Defs.PLANK: 3}},
		{"cat": 2, "name": "Bed", "kind": "prop", "prop": "bed", "cost": {Defs.PLANK: 8, Defs.LEAF: 4}},
		{"cat": 2, "name": "Bookshelf", "kind": "prop", "prop": "bookshelf", "cost": {Defs.PLANK: 10}},
		{"cat": 2, "name": "Shop Shelf", "kind": "prop", "prop": "goods", "cost": {Defs.PLANK: 10, Defs.GLASS: 2}},
		{"cat": 2, "name": "Dresser", "kind": "prop", "prop": "dresser", "cost": {Defs.PLANK: 8}},
		{"cat": 2, "name": "Counter", "kind": "prop", "prop": "counter", "cost": {Defs.PLANK: 8}},
		{"cat": 2, "name": "Barrel", "kind": "prop", "prop": "barrel", "cost": {Defs.PLANK: 5}},
		{"cat": 2, "name": "Crates", "kind": "prop", "prop": "crates", "cost": {Defs.PLANK: 6}},
		{"cat": 2, "name": "Fireplace", "kind": "prop", "prop": "fireplace", "cost": {Defs.MASONRY: 12, Defs.COAL: 2}},
		{"cat": 2, "name": "Anvil", "kind": "prop", "prop": "anvil", "cost": {Defs.COPPER: 6}},
		{"cat": 2, "name": "Cauldron", "kind": "prop", "prop": "cauldron", "cost": {Defs.COPPER: 4, Defs.COAL: 1}},
		{"cat": 2, "name": "Weapon Rack", "kind": "prop", "prop": "rack", "cost": {Defs.PLANK: 4, Defs.COPPER: 2}},
		{"cat": 2, "name": "Painting", "kind": "prop", "prop": "painting", "cost": {Defs.PLANK: 2, Defs.GLASS: 1}},
		{"cat": 2, "name": "Banner", "kind": "prop", "prop": "banner", "cost": {Defs.LEAF: 4, Defs.PLANK: 1}},
		{"cat": 2, "name": "Potted Plant", "kind": "prop", "prop": "plant", "cost": {Defs.LEAF: 2, Defs.DIRT: 2}},
		{"cat": 2, "name": "Rug", "kind": "prop", "prop": "rug", "cost": {Defs.LEAF: 3}},
		{"cat": 3, "name": "Lamp Post", "kind": "prop", "prop": "lamp", "arg": true, "cost": {Defs.MASONRY: 2, Defs.TORCH: 1}},
		{"cat": 3, "name": "Sign", "kind": "prop", "prop": "sign", "arg": "home", "cost": {Defs.PLANK: 4}},
		{"cat": 3, "name": "Fence", "kind": "prop", "prop": "fence", "arg": 16, "cost": {Defs.PLANK: 4}},
		{"cat": 3, "name": "Hedge", "kind": "prop", "prop": "hedge", "cost": {Defs.LEAF: 6}},
		{"cat": 3, "name": "Flower Bed", "kind": "prop", "prop": "flowers", "cost": {Defs.LEAF: 3, Defs.DIRT: 2}},
		{"cat": 3, "name": "Hay Bale", "kind": "prop", "prop": "hay", "cost": {Defs.LEAF: 4}},
		{"cat": 3, "name": "Well", "kind": "prop", "prop": "well", "cost": {Defs.MASONRY: 16, Defs.PLANK: 6}},
		{"cat": 3, "name": "Market Stall", "kind": "prop", "prop": "stall", "cost": {Defs.PLANK: 12, Defs.LEAF: 4}},
	]

static func in_cat(all: Array, cat: int) -> Array:
	var out := []
	for p in all:
		if int(p["cat"]) == cat:
			out.append(p)
	return out

## which of a piece's costs the satchel can pay (the door's own cost first, else its alternative),
## or {} if neither
static func payable(piece: Dictionary, inv: PackedInt32Array) -> Dictionary:
	for key in ["cost", "alt"]:
		if not piece.has(key):
			continue
		var c: Dictionary = piece[key]
		var ok := true
		for m in c:
			if inv[int(m)] < int(c[m]):
				ok = false
		if ok:
			return c
	return {}

static func cost_text(c: Dictionary) -> String:
	var parts := []
	for m in c:
		parts.append("%d %s" % [int(c[m]), Defs.NAMES[int(m)]])
	return ", ".join(parts)

## a prop's design for this piece and seed (the same seed always gives the same design)
static func design(piece: Dictionary, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Props.make(String(piece["prop"]), rng, piece.get("arg", null))

# ---------------------------------------------------------------- cells --
## world position of a cell's centre (shell 0: column, row)
static func cell_pos(col: int, row: int) -> Vector2:
	var a := (float(posmod(col, Defs.SH_N[0])) + 0.5) / Defs.SH_N[0] * TAU
	var r := Defs.R_TOP - (float(row) + 0.5)
	return Vector2(cos(a), sin(a)) * r

static func cell_of(p: Vector2) -> Vector2i:
	var a := fposmod(atan2(p.y, p.x), TAU)
	return Vector2i(int(a / TAU * Defs.SH_N[0]), int(floor(Defs.R_TOP - p.length())))

## The cells a prop would fill with its bottom row on `bottom` and its middle at column `col`:
## [[col, row, char], ...] (columns increase to the left on screen, as in the generator).
static func prop_cells(rows: Array, col: int, bottom: int, flip: bool) -> Array:
	var out := []
	var h := rows.size()
	var w: int = rows[0].length()
	var c0 := col - w / 2
	for y in h:
		var r: String = rows[y]
		for x in w:
			var ch := r[w - 1 - x] if flip else r[x]
			if ch != ".":
				out.append([c0 + x, bottom - h + 1 + y, ch])
	return out

## A small blueprint (the same data stamp.comp writes at generation) for a prop's cells: each pixel
## is a background furniture cell with its palette colour that stands in for a back wall; 't' is a
## torch. Nothing is anchored, so what you build obeys the physics.
static func prop_stamp(cells: Array) -> Dictionary:
	var c0 := 1 << 30
	var r0 := 1 << 30
	var c1 := -(1 << 30)
	var r1 := -(1 << 30)
	for c in cells:
		c0 = mini(c0, int(c[0]))
		c1 = maxi(c1, int(c[0]))
		r0 = mini(r0, int(c[1]))
		r1 = maxi(r1, int(c[1]))
	var w := c1 - c0 + 1
	var h := r1 - r0 + 1
	var data := PackedInt32Array()
	data.resize(w * h)
	data.fill(0xffff)
	for c in cells:
		var k := (int(c[1]) - r0) * w + (int(c[0]) - c0)
		var ch: String = c[2]
		if ch == "t":
			data[k] = (Defs.TORCH << 8) | 0x40000
		else:
			data[k] = (Defs.DECOR << 8) | ((int(Props.CHARS[ch]) & 255) << 19) | 0x8000000 | 0x40000
	return {"x0": posmod(c0, Defs.SH_N[0]), "y0": r0, "w": w, "h": h, "data": data}

## a strip of scaffold, as a blueprint
static func platform_stamp(col: int, row: int) -> Dictionary:
	var data := PackedInt32Array()
	data.resize(PLATFORM_W)
	data.fill(0xff00 | Defs.SCAFFOLD)
	return {"x0": posmod(col - PLATFORM_W / 2, Defs.SH_N[0]), "y0": row, "w": PLATFORM_W, "h": 1, "data": data}
