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
const Buildings := preload("res://scripts/buildings.gd")

const CATS := ["Back Walls", "Doors & Platforms", "Furniture", "Outdoors", "Structures", "Satchel", "Blocks"]
const CAT_SATCHEL := 5        # furniture you carry (picked up whole, or forged): set down for free
const CAT_BLOCKS := 6         # solid blocks, laid in straight lines and rectangles
## the order the tabs are shown in (and Q/E steps through)
const CAT_ORDER := [0, 6, 1, 2, 3, 4, 5]

## How back walls and blocks are laid (G cycles): painted with a round brush (back walls only), or
## dragged out (press, drag, release) as a straight line (snapped across, up or at 45 degrees), a
## filled rectangle, or a frame (a rectangle's outline). [ ] set the thickness of lines and frames.
const SHAPES := ["Brush", "Line", "Rectangle", "Frame"]
const THICK_MAX := 8
const SHAPE_MAX_CELLS := 5000  # the most one drag can lay
const SHAPE_REACH := 110.0     # how far from you a drag may reach (further than digging)
## building styles for structures: [name, the biome whose house style it is]
const STYLES := [["Timber", "forest"], ["Log Cabin", "tundra"], ["Stone", "mountain"], ["Sandstone", "desert"],
	["Brick", "ashland"], ["Swamp", "marsh"], ["Jungle", "jungle"], ["Mud-brick", "savanna"], ["Mushroom", "grove"]]
const STRUCT_W_MIN := 24
const STRUCT_W_MAX := 96
const STRUCT_FLOORS_MAX := 4
const FOUND_MAX := 10         # how far a structure's floor may stand above the ground (filled with a plinth)
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
		{"cat": 6, "name": "Stone Blocks", "kind": "block", "mat": Defs.MASONRY, "cost": {Defs.MASONRY: 1}},
		{"cat": 6, "name": "Bricks", "kind": "block", "mat": Defs.BRICK, "cost": {Defs.BRICK: 1}},
		{"cat": 6, "name": "Planks", "kind": "block", "mat": Defs.PLANK, "cost": {Defs.PLANK: 1}},
		{"cat": 6, "name": "Logs", "kind": "block", "mat": Defs.WOOD, "cost": {Defs.WOOD: 1}},
		{"cat": 6, "name": "Sandstone", "kind": "block", "mat": Defs.SANDSTONE, "cost": {Defs.SANDSTONE: 1}},
		{"cat": 6, "name": "Mossy Blocks", "kind": "block", "mat": Defs.MOSSBLOCK, "cost": {Defs.MOSSBLOCK: 1}},
		{"cat": 6, "name": "Roof Tiles", "kind": "block", "mat": Defs.TILE, "cost": {Defs.TILE: 1}},
		{"cat": 6, "name": "Glass Window", "kind": "block", "mat": Defs.GLASS, "cost": {Defs.GLASS: 1}},
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
		# whole structures, put together by the planet's own building generator; the cost is worked
		# out from what's in them (see structure_cost)
		{"cat": 4, "name": "House", "kind": "structure", "struct": "house", "cost": {}},
		{"cat": 4, "name": "Room", "kind": "structure", "struct": "room", "cost": {}},
		{"cat": 4, "name": "Roof", "kind": "structure", "struct": "roof", "cost": {}},
	]

## The pieces you carry (Mage.furn: picked up whole with Shift + right-click, or forged at the Wisp
## Forge), as build pieces: each keeps its exact pixels and costs nothing to set down.
static func carried_pieces(furn: Array) -> Array:
	var out := []
	for k in furn.size():
		var it: Dictionary = furn[k]
		out.append({"cat": CAT_SATCHEL, "name": it["name"], "kind": "carried", "item": k, "rows": it["rows"],
			"wall": bool(it.get("wall", false)), "kid": int(it.get("kind", 0)), "cost": {}})
	return out

## Furniture recipes for the Wisp Forge, from the same catalogue (the indoor pieces): forging one
## makes a piece with a design of its own and puts it in the satchel.
static func furniture_recipes() -> Array:
	var out := []
	for p in pieces():
		if int(p["cat"]) == 2:
			out.append({"id": "furn_" + String(p["prop"]), "cat": "Furniture", "name": p["name"], "cost": p["cost"],
				"furniture": p["prop"], "desc": "Carried in your satchel; set it down from build mode's Satchel tab."})
	return out

## a carried piece for a satchel: a design of this piece (forged) or the pixels picked up
static func carried_item(name: String, d: Dictionary, prop: String) -> Dictionary:
	return {"name": name, "rows": d["rows"], "wall": bool(d.get("wall", false)), "kind": Props.kind_id(prop)}

## The cells a drag from cell a to cell b covers in `shape` (1 line, 2 rectangle, 3 frame) with
## lines and frames `thick` cells thick; a line is snapped to across, up or 45 degrees. Columns
## wrap around the planet, so a drag across the seam still goes the short way.
static func shape_cells(a: Vector2i, b: Vector2i, shape: int, thick: int) -> Array:
	var n0: int = Defs.NS
	var dx := b.x - a.x
	if dx > n0 / 2:
		dx -= n0
	elif dx < -n0 / 2:
		dx += n0
	var dy := b.y - a.y
	var out := {}
	var t0 := -(thick - 1) / 2
	if shape <= 1:
		var ax := absi(dx)
		var ay := absi(dy)
		var sx := signi(dx)
		var sy := signi(dy)
		var steps := 0
		if ax >= 2 * ay:
			sy = 0
			steps = ax
		elif ay >= 2 * ax:
			sx = 0
			steps = ay
		else:
			steps = maxi(ax, ay)
		for k in steps + 1:
			for oy in thick:
				for ox in thick:
					out[Vector2i(a.x + sx * k + t0 + ox, a.y + sy * k + t0 + oy)] = true
	else:
		var x0 := mini(0, dx)
		var x1 := maxi(0, dx)
		var y0 := mini(a.y, b.y)
		var y1 := maxi(a.y, b.y)
		var area := (x1 - x0 + 1) * (y1 - y0 + 1)
		var edge_cells := mini(area, 2 * thick * (x1 - x0 + y1 - y0 + 2))
		if (shape == 2 and area > SHAPE_MAX_CELLS) or (shape == 3 and edge_cells > SHAPE_MAX_CELLS):
			var too := []                   # too big to lay in one go (the caller says so)
			too.resize(SHAPE_MAX_CELLS + 1)
			too.fill(a)
			return too
		for y in range(y0, y1 + 1):
			var full := shape == 2 or y - y0 < thick or y1 - y < thick
			var xs: Array = range(x0, x1 + 1) if full else range(x0, mini(x0 + thick, x1 + 1)) + range(maxi(x1 - thick + 1, x0), x1 + 1)
			for x in xs:
				out[Vector2i(a.x + x, y)] = true
	var keys := out.keys()
	for k in keys.size():
		var v: Vector2i = keys[k]
		keys[k] = Vector2i(posmod(v.x, n0), v.y)
	return keys

## a stamp laying `mat` on these cells, as solid blocks or (back) as a built back wall; not anchored,
## so it obeys the physics like everything you build
static func shape_stamp(cells: Array, mat: int, back: bool) -> Dictionary:
	var n0: int = Defs.NS
	var c0: int = cells[0].x
	var r0: int = cells[0].y
	var c1 := c0
	var r1 := r0
	# columns relative to the first cell, the short way round
	var rel := []
	for c in cells:
		var dx: int = posmod(c.x - cells[0].x + n0 / 2, n0) - n0 / 2
		rel.append(Vector2i(cells[0].x + dx, c.y))
	for c in rel:
		c0 = mini(c0, c.x)
		c1 = maxi(c1, c.x)
		r0 = mini(r0, c.y)
		r1 = maxi(r1, c.y)
	var w := c1 - c0 + 1
	var h := r1 - r0 + 1
	var data := PackedInt32Array()
	data.resize(w * h)
	data.fill(0xffff)
	var v := (0xff | (mat << 8) | 0x40000) if back else (0xff00 | mat)
	for c in rel:
		data[(c.y - r0) * w + (c.x - c0)] = v
	return {"x0": posmod(c0, n0), "y0": r0, "w": w, "h": h, "data": data}

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
		if c.is_empty() and key == "cost" and piece["kind"] == "structure":
			return {}                   # not worked out yet
		if piece["kind"] == "carried":
			return {Defs.AIR: 0}        # already yours: nothing to pay
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
		if int(c[m]) <= 0:
			continue
		parts.append("%d %s" % [int(c[m]), Defs.NAMES[int(m)]])
	return ", ".join(parts)

## a prop's design for this piece and seed (the same seed always gives the same design)
static func design(piece: Dictionary, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Props.make(String(piece["prop"]), rng, piece.get("arg", null))

# ---------------------------------------------------------------- cells --
## World position of a cell's centre (surface column, row). Columns here are as a stamp anchored
## near you (Defs.anchor_c) puts them: cell for cell in any shell, so what you build, pick up or
## look at nearby is the same at any depth (in the surface shell, simply the surface column).
static func cell_pos(col: int, row: int) -> Vector2:
	if row >= Defs.SURF_Y0 and row < Defs.SURF_Y1:
		# (the surface shell: simply the surface column, whatever the anchor; most lookups are here)
		var a := (float(posmod(col, Defs.NS)) + 0.5) / float(Defs.NS) * TAU
		return Vector2(cos(a), sin(a)) * (Defs.R_TOP - (float(row) + 0.5))
	return Defs.stamp_pos(row, Defs.anchor_c, 1, Defs.k_of(col, Defs.anchor_c))

static func cell_of(p: Vector2) -> Vector2i:
	var row := int(floor(Defs.R_TOP - p.length()))
	if row >= Defs.SURF_Y0 and row < Defs.SURF_Y1:
		return Vector2i(int(fposmod(atan2(p.y, p.x), TAU) / TAU * float(Defs.NS)) % Defs.NS, row)
	var kr: Vector2i = Defs.stamp_k(p, Defs.anchor_c, 1)
	return Vector2i(posmod(Defs.anchor_c + kr.x, Defs.NS), kr.y)

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
static func prop_stamp(cells: Array, kid := 0) -> Dictionary:
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
			data[k] = (Defs.DECOR << 8) | ((int(Props.CHARS[ch]) & 255) << 19) | 0x8000000 | 0x40000 | ((kid & 15) << 28)
	return {"x0": posmod(c0, Defs.NS), "y0": r0, "w": w, "h": h, "data": data}

## a strip of scaffold, as a blueprint
static func platform_stamp(col: int, row: int) -> Dictionary:
	var data := PackedInt32Array()
	data.resize(PLATFORM_W)
	data.fill(0xff00 | Defs.SCAFFOLD)
	return {"x0": posmod(col - PLATFORM_W / 2, Defs.NS), "y0": row, "w": PLATFORM_W, "h": 1, "data": data}

# ------------------------------------------------------------- structures --
## A structure's blueprint, put together from the planet generator's own parts (builds: the planet's
## Buildings instance, whose part functions do the work): "house" is rooms and a roof, "room" the rooms
## alone (to add to or put a roof on later), "roof" a roof alone, resting on whatever is at `floor_row`.
## Seeded, so the preview and what's built are the same. Returns {bp, st, lb (local floor row), ox}.
static func structure(builds, kind: String, style: int, seed: int, w: int, floors: int, col: int, floor_row: int) -> Dictionary:
	var saved: int = builds.rng.state
	builds.rng.seed = seed
	var st: Dictionary = builds._style(STYLES[style][1], "home")
	if kind != "house":
		st["chimney"] = false
	var roof_h: int = builds._roof_h(w, st) if kind != "room" else 0
	var rooms_h: int = floors * Buildings.STOREY if kind != "roof" else 0
	var up := rooms_h + roof_h + 4
	var bw := w + 6
	var bp = Buildings.BP.new(col - bw / 2, floor_row - up, bw, up + 1 + FOUND_MAX)   # room under it for a plinth
	var ox := 3
	var lb := up
	var top := lb
	if kind != "roof":
		top = builds._building(bp, ox, lb, w, floors, st, 3, false, "", 0.0)
	if kind != "room":
		builds._roof(bp, ox, top, w, st)
		if kind == "house" and st.get("chimney", false):
			builds._chimney(bp, ox, top, w, st)
	builds.rng.state = saved
	return {"bp": bp, "st": st, "lb": lb, "ox": ox}

## what a material is paid for with (the things a player can gather or forge)
static func buy_mat(m: int) -> int:
	if m == Defs.MOSSBLOCK:
		return Defs.MASONRY
	if m == Defs.SCAFFOLD or m == Defs.DECOR:
		return Defs.PLANK
	return m

## What a structure costs: a quarter of its solid cells (walls, floors and roof go up with magic, not
## block by block), a tenth of its back wall, a torch for each torch and 8 planks a door.
static func structure_cost(bp, n_doors: int) -> Dictionary:
	var fgc := {}
	var bgc := {}
	var torches := 0
	for v in bp.c:
		var f: int = v & 255
		var g: int = (v >> 8) & 255
		if f != 255 and f != 0 and f != Defs.WOODDOOR:
			var mf := buy_mat(f)
			fgc[mf] = int(fgc.get(mf, 0)) + 1
		if g == Defs.TORCH:
			torches += 1
		elif g != 255 and g != 0:
			var mg := buy_mat(g)
			bgc[mg] = int(bgc.get(mg, 0)) + 1
	var cost := {}
	for m in fgc:
		cost[m] = int(cost.get(m, 0)) + int(ceil(float(fgc[m]) / 4.0))
	for m2 in bgc:
		cost[m2] = int(cost.get(m2, 0)) + int(ceil(float(bgc[m2]) / 10.0))
	if torches > 0:
		cost[Defs.TORCH] = torches
	if n_doors > 0:
		cost[Defs.PLANK] = int(cost.get(Defs.PLANK, 0)) + 8 * n_doors
	return cost

## a picture of a blueprint for the preview (columns increase to the left on screen, so it's mirrored)
static func preview_image(bp, ok: bool) -> Image:
	var img := Image.create(bp.w, bp.h, false, Image.FORMAT_RGBA8)
	for j in bp.h:
		for i in bp.w:
			var v: int = bp.c[j * bp.w + i]
			var f: int = v & 255
			var g: int = (v >> 8) & 255
			var col := Color(0, 0, 0, 0)
			if f != 255 and f != 0:
				col = Defs.COLOR[f]
				col.a = 0.8
			elif g == Defs.TORCH:
				col = Color(1, 0.85, 0.35, 0.9)
			elif g != 255 and g != 0:
				col = Defs.COLOR[g].darkened(0.45)
				col.a = 0.55
			if col.a > 0.0 and not ok:
				col = Color(col.lerp(Color(1, 0.2, 0.15), 0.6), col.a)
			img.set_pixel(bp.w - 1 - i, j, col)
	return img
