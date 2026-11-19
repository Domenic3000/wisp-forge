extends RefCounted
## Procedural structures: cottages, towns, towers, castles, desert temples, stilt huts,
## mineshafts, catacombs and sealed vaults. Nothing is hand-drawn: each structure is grown
## from simple rules (floors, walls, doors, roofs) in materials that suit its biome, and
## built within each material's strength (SPAN) so it stands up on its own.
## Ruins are made by damaging an intact building (jagged walls, holes, rotten wood, moss),
## then letting the planet's physics settle it at generation: whatever lost its support
## falls and breaks into rubble, so every ruin collapses differently.
##
## Coordinates: shell-0 columns (x, wraps at N0) and rows (y, 0 = edge of space, grows inward).
## A blueprint is a w x h grid; local (i, j) is column x0 + i, row y0 + j.

var N0: int = Defs.NS        # the surface shell's columns (Defs.NS), taken when a planet is planned
const Props := preload("res://scripts/props.gd")
## the test mode keeps each blueprint (to draw it), the game doesn't need them after stamping
var KEEP_DATA := "--test" in OS.get_cmdline_user_args()
const KEEP := 0xffff              # keep foreground and background as generated
const F_FILL := 0x10000           # only fill where there is no solid ground
const F_ANCHOR := 0x20000         # part of the planet (foundations)
const F_WALL := 0x40000           # background is a built back wall
const STOREY := 40                # floor to floor; the mage is 24 tall with the hat, so rooms feel roomy
const DOOR := 30                  # doorway height
const GAP := 14                   # the hole in each upper floor that you levitate through
const CHEST_KEEP := 0.45          # share of the possible chest spots that get a chest

var surf: PackedFloat32Array
var rng := RandomNumberGenerator.new()
var structs := []                 # {x0, y0, w, h, data} ready for the GPU stamp pass
var sites := []                   # Vector2(x0, x1): surface columns kept free of trees
var settle := []                  # [world position, half size] windows to settle after stamping
var labels := []                  # {x0, x1, ymin, ymax, name}: for the region name on the HUD
var chest_list := []             # {pos (world centre), ruined}: treasure chests (objects, not cells)
var door_list := []              # {pos (world centre), w, h, side}: doors (closed cells; the game opens and closes them)
var guards := []                  # {pos, type}: foes that wait inside castles, catacombs, temples and mines
var infos := []                   # what was built (for the test mode): {x0, y0, w, h, ruined, solid, chests}
var used := []                    # occupied surface column ranges
var deep := []                    # column ranges taken by underground tunnels (mines, catacombs, vaults)
var spawn_col := 0
var boss_col := 0
var biome_names := []
var _quiet := false               # the first structure near your arrival has no guards

class BP:
	var chests := []          # Vector2i(left column, floor row), local
	var doors := []           # [left column, top row, width, height, side (+1: the inside is to the right)], local
	var meta := {}            # extra facts for the test mode (a dungeon's rooms and what reaches them)
	var ruined := false
	var x0 := 0
	var y0 := 0
	var w := 0
	var h := 0
	var c := PackedInt32Array()
	func _init(x: int, y: int, ww: int, hh: int) -> void:
		x0 = x
		y0 = y
		w = ww
		h = hh
		c.resize(w * h)
		c.fill(0xffff)
	func ok(i: int, j: int) -> bool:
		return i >= 0 and j >= 0 and i < w and j < h
	func fg(i: int, j: int, m: int, flags := 0) -> void:
		if ok(i, j):
			var k := j * w + i
			c[k] = (c[k] & 0xff00) | (m & 255) | flags | (c[k] & 0x40000)
	func bg(i: int, j: int, m: int, wall := true) -> void:
		if ok(i, j):
			var k := j * w + i
			c[k] = (c[k] & 0xff300ff) | ((m & 255) << 8) | (0x40000 if wall and m != 0 else 0)
	## a background object with a fixed part number, in front of open air (furniture: its palette
	## colour). wall: it stands in for the back wall it covers, so it carries the structure the way
	## that wall did (furniture used to leave holes in the wall's support, and the generator's
	## soundness pass then cut the wall and roof above a wide bed or counter away)
	## (kid: a furniture piece's kind, props.gd KINDS, kept in the cell so the game knows a bed for a bed)
	func bgv(i: int, j: int, m: int, v: int, wall := false, kid := 0) -> void:
		if ok(i, j):
			c[j * w + i] = ((m & 255) << 8) | ((v & 255) << 19) | 0x8000000 | (0x40000 if wall else 0) | ((kid & 15) << 28)
	## foreground with a fixed colour variant
	func fgv(i: int, j: int, m: int, v: int) -> void:
		if ok(i, j):
			var k := j * w + i
			c[k] = (c[k] & 0x4ff00) | (m & 255) | ((v & 255) << 19) | 0x8000000
	func getf(i: int, j: int) -> int:
		return c[j * w + i] & 255 if ok(i, j) else 255
	func getb(i: int, j: int) -> int:
		return (c[j * w + i] >> 8) & 255 if ok(i, j) else 255
	func is_fill(i: int, j: int) -> bool:
		return ok(i, j) and (c[j * w + i] & 0x10000) != 0
	func rect(i0: int, j0: int, i1: int, j1: int, m: int, flags := 0) -> void:
		for j in range(mini(j0, j1), maxi(j0, j1) + 1):
			for i in range(mini(i0, i1), maxi(i0, i1) + 1):
				fg(i, j, m, flags)
	## solid block with its own back wall (so it is part of the building's structure)
	func solid(i0: int, j0: int, i1: int, j1: int, m: int, flags := 0) -> void:
		rect(i0, j0, i1, j1, m, flags)
		rect_bg(i0, j0, i1, j1, m)
	func rect_bg(i0: int, j0: int, i1: int, j1: int, m: int, wall := true) -> void:
		for j in range(mini(j0, j1), maxi(j0, j1) + 1):
			for i in range(mini(i0, i1), maxi(i0, i1) + 1):
				bg(i, j, m, wall)

# ------------------------------------------------------------------ styles ---
func _style(bname: String, kind: String) -> Dictionary:
	var st := {"wall": Defs.PLANK, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.TILE,
		"roof_kind": "pitch", "found": Defs.MASONRY, "thick": 1}
	match bname:
		"desert":
			st = {"wall": Defs.SANDSTONE, "post": Defs.SANDSTONE, "slab": Defs.SANDSTONE, "back": Defs.SANDSTONE,
				"roof": Defs.SANDSTONE, "roof_kind": "dome" if rng.randf() < 0.5 else "flat", "found": Defs.SANDSTONE, "thick": 2}
		"tundra":
			st = {"wall": Defs.WOOD, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.PLANK,
				"roof_kind": "steep", "found": Defs.MASONRY, "thick": 1}
		"mountain":
			st = {"wall": Defs.MASONRY, "post": Defs.MASONRY, "slab": Defs.PLANK, "back": Defs.MASONRY, "roof": Defs.TILE,
				"roof_kind": "steep", "found": Defs.MASONRY, "thick": 1}
		"marsh":
			st = {"wall": Defs.PLANK, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.DRYGRASS,
				"roof_kind": "pitch", "found": Defs.WOOD, "thick": 1}
		"ashland":
			st = {"wall": Defs.BRICK, "post": Defs.OBSIDIAN, "slab": Defs.BRICK, "back": Defs.BRICK, "roof": Defs.BRICK,
				"roof_kind": "battle", "found": Defs.OBSIDIAN, "thick": 2}
		"jungle":
			# timber halls with grass thatch, raised on stone
			st = {"wall": Defs.WOOD, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.DRYGRASS,
				"roof_kind": "steep", "found": Defs.MOSSBLOCK, "thick": 1}
		"savanna":
			# mud-brick walls under golden grass thatch
			st = {"wall": Defs.SANDSTONE, "post": Defs.WOOD, "slab": Defs.PLANK, "back": Defs.SANDSTONE, "roof": Defs.DRYGRASS,
				"roof_kind": "pitch", "found": Defs.SANDSTONE, "thick": 2}
		"grove":
			# mushroom houses: walls of pale stalk, a cap for a roof
			st = {"wall": Defs.STALK, "post": Defs.STALK, "slab": Defs.PLANK, "back": Defs.PLANK, "roof": Defs.CAP,
				"roof_kind": "dome", "found": Defs.MASONRY, "thick": 1}
	if kind == "fort":
		# towers, keeps and castle walls are always stone
		var stone := Defs.MASONRY
		if bname == "desert":
			stone = Defs.SANDSTONE
		elif bname == "ashland":
			stone = Defs.BRICK
		st["wall"] = stone
		st["post"] = stone
		st["back"] = stone
		st["found"] = stone
		st["slab"] = Defs.PLANK if rng.randf() < 0.5 and bname != "ashland" else stone
		st["thick"] = 2
		st["roof"] = Defs.TILE if bname != "ashland" else stone
		st["roof_kind"] = "battle" if rng.randf() < 0.55 or bname == "ashland" or bname == "desert" else "steep"
	# walls and floors sized for 40-cell storeys: homes 3 thick, towers and castles 4
	st["thick"] = 4 if kind == "fort" else 3
	# --- variations: every building picks its own details from these parts ---
	var wooden: bool = st["wall"] == Defs.PLANK or st["wall"] == Defs.WOOD
	# roof covering: clay tiles, wooden shingles or slate
	if st["roof"] == Defs.TILE and kind == "home":
		st["roof"] = [Defs.TILE, Defs.TILE, Defs.PLANK, Defs.MASONRY][rng.randi_range(0, 3)]
	st["trim"] = Defs.WOOD if st["roof"] != Defs.WOOD else Defs.PLANK       # eaves and barge boards
	st["ridge"] = Defs.MASONRY if st["roof"] == Defs.TILE else (Defs.TILE if st["roof"] == Defs.MASONRY else Defs.WOOD)
	# windows: cross-paned, arched, round or tall; wooden houses often have shutters
	var wins := ["cross", "arch", "tall"] if bname != "desert" else ["arch", "round", "tall"]
	if kind == "fort":
		wins = ["arch", "tall", "round"]
	else:
		wins.append("round")
	st["window"] = wins[rng.randi_range(0, wins.size() - 1)]
	st["shutters"] = wooden and kind == "home" and rng.randf() < 0.55
	# the back wall: half-timbered, banded with stone courses, or plain
	var frames := ["plain"]
	if wooden:
		frames = ["timber", "timber", "plain"]
	elif kind == "fort" or st["wall"] == Defs.MASONRY or st["wall"] == Defs.BRICK:
		frames = ["course", "course", "plain"]
	elif st["wall"] == Defs.SANDSTONE:
		frames = ["course", "plain"]
	st["frame"] = frames[rng.randi_range(0, frames.size() - 1)]
	st["course"] = Defs.BRICK if st["back"] == Defs.MASONRY else (Defs.MASONRY if st["back"] == Defs.BRICK else st["found"])
	st["chimney"] = kind == "home" and bname != "desert" and st["roof_kind"] != "flat" and st["roof_kind"] != "dome" and rng.randf() < 0.65
	return st

## How many rows a roof of this kind rises above the top slab of a building w wide (so the
## blueprint is always tall enough for the whole roof, chimney included).
func _roof_h(w: int, st: Dictionary) -> int:
	var h := 6
	match st["roof_kind"]:
		"pitch": h = (w + 4) / 2 + 3
		"steep": h = w + 6
		"dome": h = w / 2 + 3
		"battle": h = 5
		"flat": h = 4
	if st.get("chimney", false):
		h += 10
	return h

# ------------------------------------------------------------- terrain info ---
func ground_row(col: int) -> int:
	var x := posmod(col, N0)
	return int(floor(Defs.R_TOP - surf[x * 8] - 0.5)) + 1

func wet(col: int) -> bool:
	var x := posmod(col, N0)
	return surf[x * 8 + 5] > surf[x * 8] + 0.5

func biome(col: int) -> String:
	var x := posmod(col, N0)
	return biome_names[clampi(int(surf[x * 8 + 1]), 0, biome_names.size() - 1)]

func cdist(a: int, b: int) -> int:
	var d := posmod(a - b, N0)
	return mini(d, N0 - d)

func free_span(x0: int, w: int, margin: int) -> bool:
	for u in used:
		var a: int = u.x - margin
		var ln: int = u.y - u.x + 2 * margin
		var d0 := posmod(x0 - a, N0)
		if d0 < ln or posmod(a - x0, N0) < w:
			return false
	return true

func _ground_range(x0: int, w: int) -> Vector2i:
	var gmin := 1 << 30
	var gmax := -1
	for i in w:
		var g := ground_row(x0 + i)
		gmin = mini(gmin, g)
		gmax = maxi(gmax, g)
	return Vector2i(gmin, gmax)

func _median_ground(x0: int, w: int) -> int:
	var a := []
	for i in w:
		a.append(ground_row(x0 + i))
	a.sort()
	return a[a.size() / 2]

func _any_wet(x0: int, w: int) -> bool:
	for i in range(0, w, 2):
		if wet(x0 + i):
			return true
	return false

# ---------------------------------------------------------------- planning ---
## Plans every structure on the planet. Deterministic for a given planet, so it can be
## re-run when a saved world is loaded (for the region names) without stamping again.
func plan(planet: Dictionary, surface: PackedFloat32Array, spawn_angle: float, boss_angle: float, build: bool) -> void:
	N0 = Defs.NS
	surf = surface
	rng.seed = int(planet["seed"]) * 31 + 7
	biome_names = []
	for b in planet["biomes"]:
		biome_names.append(str(b))
	spawn_col = int(fposmod(spawn_angle, TAU) / TAU * N0)
	boss_col = int(fposmod(boss_angle, TAU) / TAU * N0)
	structs.clear()
	sites.clear()
	settle.clear()
	labels.clear()
	guards.clear()
	infos.clear()
	used.clear()
	deep.clear()
	chest_list.clear()
	door_list.clear()
	used.append(Vector2i(spawn_col - 70, spawn_col + 70))
	# something to discover a short walk from where you arrive
	for tries in 40:
		var side := 1 if tries % 2 == 0 else -1
		var x := posmod(spawn_col + side * (115 + tries * 9), N0)
		_quiet = true
		var ok := _try_place(x, true, build)
		_quiet = false
		if ok:
			break
	var target := 26
	var placed := 0
	for tries in 900:
		if placed >= target:
			break
		var x := rng.randi_range(0, N0 - 1)
		if _try_place(x, false, build):
			placed += 1
	# dungeons: a gatehouse on the surface over a maze of halls below
	var dn := 0
	for tries in 80:
		if dn >= DUNGEONS:
			break
		if _dungeon(rng.randi_range(0, N0 - 1), build):
			dn += 1
	# underground: sealed vaults, out of sight
	for k in 6:
		_vault(rng.randi_range(0, N0 - 1), build)

func _pick(weights: Dictionary) -> String:
	var tot := 0.0
	for k in weights:
		tot += float(weights[k])
	var r := rng.randf() * tot
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return k
	return weights.keys()[0]

func _try_place(x: int, near_spawn: bool, build: bool) -> bool:
	var b := biome(x)
	var w := {}
	match b:
		"forest": w = {"town": 3, "cottage": 3, "tower": 1.5, "mine": 1, "catacomb": 1.5}
		"desert": w = {"temple": 3.5, "cottage": 2, "town": 1.5, "tower": 1, "catacomb": 1.5}
		"marsh": w = {"stilt": 5, "tower": 2, "catacomb": 2}
		"mountain": w = {"castle": 3.5, "tower": 2.5, "mine": 3, "cottage": 1}
		"tundra": w = {"cottage": 3.5, "town": 2.5, "tower": 1.5, "mine": 2.5}
		"ashland": w = {"tower": 3.5, "castle": 2.5, "catacomb": 2, "cottage": 2}
		"ocean": w = {"cottage": 6, "tower": 4}
		"jungle": w = {"temple": 2.5, "stilt": 2, "tower": 1, "catacomb": 1.5, "cottage": 1.5}
		"savanna": w = {"town": 2.5, "cottage": 3, "tower": 1, "mine": 1.5, "catacomb": 1}
		"grove": w = {"cottage": 3, "town": 1.5, "tower": 1.5, "catacomb": 2}
		_: w = {"cottage": 1}
	if near_spawn:
		w = {"cottage": 2, "tower": 2} if b != "desert" else {"temple": 1}
		if b == "marsh":
			w = {"stilt": 1}
	var kind := _pick(w)
	var ruin_p := 0.5
	match kind:
		"castle", "temple", "catacomb": ruin_p = 0.7
		"town": ruin_p = 0.3
		"mine": ruin_p = 0.6
	if near_spawn:
		ruin_p = 0.75
	var ruined := rng.randf() < ruin_p
	match kind:
		"cottage": return _cottage(x, b, ruined, build)
		"town": return _town(x, b, ruined, build)
		"tower": return _tower(x, b, ruined, build)
		"castle": return _castle(x, b, ruined, build)
		"temple": return _temple(x, ruined, build)
		"stilt": return _stilt(x, ruined, build)
		"mine": return _mine(x, b, ruined, build)
		"catacomb": return _catacomb(x, b, ruined, build)
	return false

## checks a surface footprint: dry, not too steep, not taken
func _site_ok(x0: int, w: int, max_slope: int, allow_wet := false) -> bool:
	if not free_span(x0, w, 6):
		return false
	if not allow_wet and _any_wet(x0 - 2, w + 4):
		return false
	var g := _ground_range(x0, w)
	return g.y - g.x <= max_slope

## underground tunnels must not run into each other (their surface footprints are much smaller)
func _deep_free(x0: int, w: int) -> bool:
	for u in deep:
		var a: int = u.x - 8
		var ln: int = u.y - u.x + 16
		if posmod(x0 - a, N0) < ln or posmod(a - x0, N0) < w:
			return false
	return true

func _claim(x0: int, w: int, name: String, ymin: int, ymax: int) -> void:
	used.append(Vector2i(x0, x0 + w))
	sites.append(Vector2(posmod(x0, N0), posmod(x0, N0) + w))
	labels.append({"x0": posmod(x0, N0), "w": w, "ymin": ymin, "ymax": ymax, "name": name})

## Is cell (i, j) part of the built structure (a solid in front, or a back wall)?
func _built(bp: BP, i: int, j: int) -> bool:
	if not bp.ok(i, j):
		return false
	var v: int = bp.c[j * bp.w + i]
	var f := v & 255
	var g := (v >> 8) & 255
	return (f != 255 and f != 0 and Defs.KIND[f] == Defs.K_SOLID) or (g != 255 and g != 0 and (v & F_WALL) != 0)

## Is cell (i, j) untouched natural ground (outside the blueprint or left as it is, below the surface)?
func _natural(bp: BP, i: int, j: int) -> bool:
	if bp.ok(i, j) and (bp.c[j * bp.w + i] & 255) != 255:
		return false
	return j >= ground_row(bp.x0 + i) - bp.y0

## Generated structures don't move until you come and dig: everything is anchored as built.
## And so a structure doesn't fall apart the moment your digging wakes it either, it is first
## made physically sound: the support rules of shaders/support.comp are run here on the
## blueprint as if nothing were anchored, and anything that would be unsupported (a floor
## hanging too far from a broken wall, a floating fragment, a chest left in the air) is
## removed, repeating until everything left holds itself up.
func _anchor_and_tidy(bp: BP) -> int:
	var w := bp.w
	var h := bp.h
	var n_all := w * h
	var removed_all := 0
	for it in 6:
		var removed := _stabilize_pass(bp)
		removed_all += removed
		if removed == 0:
			break
	for k in n_all:
		var v: int = bp.c[k]
		var f := v & 255
		var g := (v >> 8) & 255
		if (f != 255 and f != 0 and Defs.KIND[f] == Defs.K_SOLID) or (g != 255 and g != 0 and (v & F_WALL) != 0):
			bp.c[k] = v | F_ANCHOR
	_place_chests(bp)
	return removed_all

## Chests go only where they will stay found: standing on solid built floor (or natural ground)
## across their whole width, with open air around and above them, and nothing loose (rubble,
## sand, gravel) overhead that could bury them unless you dig it down yourself. A spot that
## fails slides sideways along the same floor to the nearest good one, or the chest is left out.
## Chests also keep their distance from each other.
func _place_chests(bp: BP) -> void:
	var keep := []
	for q in bp.chests:
		var found := false
		# a chest planned indoors (a built back wall behind it) stays indoors
		var indoors := _backed(bp, q.x, q.y - 1, 1)
		for d in range(0, 25):
			for sgn in ([1] if d == 0 else [1, -1]):
				var i: int = q.x + d * sgn
				if indoors and not _backed(bp, i - 2, q.y - 1, Defs.CHEST_W + 4):
					continue
				if _chest_spot_ok(bp, i, q.y, keep):
					keep.append(Vector2i(i, q.y))
					found = true
					break
			if found:
				break
	bp.chests = keep

## is there a built back wall behind all n columns from i on, in row j?
func _backed(bp: BP, i: int, j: int, n: int) -> bool:
	for k in n:
		var g := bp.getb(i + k, j)
		if g == 0 or g == 255:
			return false
	return true

func _floor_at(bp: BP, i: int, j: int) -> bool:
	var f := bp.getf(i, j)
	if f == 255:
		return j >= ground_row(bp.x0 + i) - bp.y0    # natural ground
	return f != 0 and Defs.KIND[f] == Defs.K_SOLID and f != Defs.SCAFFOLD

func _open_at(bp: BP, i: int, j: int) -> bool:
	var f := bp.getf(i, j)
	if f == 255:
		return j < ground_row(bp.x0 + i) - bp.y0 - 1    # natural air above the surface
	return f == 0

func _chest_spot_ok(bp: BP, i: int, fl: int, taken: Array) -> bool:
	if i < 1 or i + Defs.CHEST_W >= bp.w - 1:
		return false
	for t in taken:
		if t.y == fl and absi(t.x - i) < Defs.CHEST_W + 8:
			return false
	for ci in range(i, i + Defs.CHEST_W):
		if not _floor_at(bp, ci, fl):
			return false
		for j0 in range(fl - Defs.CHEST_H, fl):
			if bp.getb(ci, j0) == Defs.DECOR:
				return false                  # not in front of furniture
	# open air around and above: room to see it and open it
	for j in range(fl - Defs.CHEST_H - 5, fl):
		for ci in range(i - 2, i + Defs.CHEST_W + 2):
			if not _open_at(bp, ci, j):
				return false
	# nothing loose overhead, up to the ceiling
	for ci in range(i - 1, i + Defs.CHEST_W + 1):
		var j := fl - Defs.CHEST_H - 6
		while j >= 0:
			var f := bp.getf(ci, j)
			if f != 0 and f != 255:
				if Defs.KIND[f] == Defs.K_POWDER or Defs.KIND[f] == Defs.K_LIQUID:
					return false
				break
			j -= 1
	return true

## One round of support on the blueprint (Dial's algorithm over front and back cells). Returns
## how many cells it removed.
func _stabilize_pass(bp: BP) -> int:
	var w := bp.w
	var h := bp.h
	var n_all := w * h
	var fs := PackedByteArray()
	var bs := PackedByteArray()
	fs.resize(n_all)
	bs.resize(n_all)
	fs.fill(99)
	bs.fill(99)
	var fgb := PackedByteArray()   # 1 = built solid in front, 2 = placed powder
	var bgb := PackedByteArray()   # 1 = built back wall
	fgb.resize(n_all)
	bgb.resize(n_all)
	var nat := PackedByteArray()   # 1 = untouched natural ground
	nat.resize(n_all)
	var groundj := PackedInt32Array()
	groundj.resize(w)
	for i in w:
		groundj[i] = ground_row(bp.x0 + i) - bp.y0
	for k in n_all:
		var v: int = bp.c[k]
		var f := v & 255
		var g := (v >> 8) & 255
		if f != 255 and f != 0:
			fgb[k] = 1 if Defs.KIND[f] == Defs.K_SOLID else (2 if Defs.KIND[f] == Defs.K_POWDER else 0)
		if f == 255 and k / w >= groundj[k % w]:
			nat[k] = 1
		if g != 255 and g != 0 and (v & F_WALL) != 0:
			bgb[k] = 1
	var buckets := []
	for c in 64:
		buckets.append([])     # plain Arrays: shared, so appending while scanning a bucket works
	# seeds: resting on (or beside) natural ground, foundations
	for k in n_all:
		var i := k % w
		var j := k / w
		var below_nat := j + 1 >= h or nat[k + w] == 1 or (j + 1 < h and fgb[k + w] == 2)
		if j + 1 >= h:
			below_nat = j + 1 >= groundj[i]
		var side_nat := (i == 0 and j >= groundj[i]) or (i == w - 1 and j >= groundj[i]) or (i > 0 and nat[k - 1] == 1) or (i < w - 1 and nat[k + 1] == 1) or (j > 0 and nat[k - w] == 1)
		var v2: int = bp.c[k]
		var flagged := (v2 & (F_FILL | F_ANCHOR)) != 0
		if fgb[k] == 1:
			var sv := 0 if (below_nat or flagged) else (1 if side_nat else 99)
			if sv < 99:
				fs[k] = sv
				buckets[sv].append(k * 2)
		if bgb[k] == 1:
			var bv := 0 if flagged else (1 if below_nat else (2 if side_nat else 99))
			if bv < 99:
				bs[k] = bv
				buckets[bv].append(k * 2 + 1)
	for c in 64:
		var q: Array = buckets[c]
		var qi := 0
		while qi < q.size():
			var node: int = q[qi]
			qi += 1
			var k := node >> 1
			var layer := node & 1
			if (fs[k] if layer == 0 else bs[k]) != c:
				continue
			var i := k % w
			var j := k / w
			# neighbours: [index, is_up] for up, down, left, right
			var cand := []
			if j > 0: cand.append([k - w, 0])
			if j + 1 < h: cand.append([k + w, 1])
			if i > 0: cand.append([k - 1, 2])
			if i + 1 < w: cand.append([k + 1, 3])
			if layer == 0:
				for e in cand:
					var nk: int = e[0]
					var dirn: int = e[1]
					if fgb[nk] == 1:
						var nc := c if dirn == 0 else c + 1      # the block above rests on this one
						if nc < fs[nk]:
							fs[nk] = nc
							buckets[mini(nc, 63)].append(nk * 2)
					if bgb[nk] == 1:
						var nb := c + 1 if dirn == 0 else c + 2  # a back wall leans on blocks around it
						if nb < bs[nk]:
							bs[nk] = nb
							buckets[mini(nb, 63)].append(nk * 2 + 1)
				if bgb[k] == 1 and c + 1 < bs[k]:
					bs[k] = c + 1
					buckets[mini(c + 1, 63)].append(k * 2 + 1)
			else:
				for e in cand:
					var nk2: int = e[0]
					var dirn2: int = e[1]
					if bgb[nk2] == 1:
						var nc2 := c if dirn2 == 0 else c + 1
						if nc2 < bs[nk2]:
							bs[nk2] = nc2
							buckets[mini(nc2, 63)].append(nk2 * 2 + 1)
				var f3: int = bp.c[k] & 255
				if fgb[k] == 1 and f3 != Defs.TREASURE and c + 1 < fs[k]:
					fs[k] = c + 1
					buckets[mini(c + 1, 63)].append(k * 2)
	var removed := 0
	for k in n_all:
		var v3: int = bp.c[k]
		if fgb[k] == 1 and fs[k] > Defs.SPAN[v3 & 255]:
			_note_cut(bp, Defs.NAMES[v3 & 255])
			v3 = v3 & ~255
			removed += 1
		if bgb[k] == 1 and bs[k] > Defs.SPAN[(v3 >> 8) & 255]:
			_note_cut(bp, "bg " + Defs.NAMES[(v3 >> 8) & 255])
			v3 = v3 & ~0xff00 & ~F_WALL
			removed += 1
		bp.c[k] = v3
	return removed

## what the soundness pass cut away, by material (for the test report)
func _note_cut(bp: BP, nm: String) -> void:
	var cuts: Dictionary = bp.meta.get("cuts", {})
	cuts[nm] = int(cuts.get(nm, 0)) + 1
	bp.meta["cuts"] = cuts

func _finish(bp: BP, build: bool) -> void:
	if not build:
		return
	_roughen_underground(bp)
	_weather_ground_line(bp)
	# what the tests check later: the built cells (not fills and foundations), before anchoring
	var cells := PackedInt32Array()
	for k in bp.c.size():
		var v0: int = bp.c[k]
		var f0: int = v0 & 255
		if f0 != 255 and f0 != 0 and Defs.KIND[f0] == Defs.K_SOLID and (v0 & (F_FILL | F_ANCHOR)) == 0:
			cells.append(k)
	var unsound := _anchor_and_tidy(bp)
	var kept := PackedInt32Array()
	for k in cells:
		if (bp.c[k] & 255) != 0:
			kept.append(k)
	structs.append({"x0": posmod(bp.x0, N0), "y0": bp.y0, "w": bp.w, "h": bp.h, "data": bp.c})
	var solid := kept.size()
	# props (background furniture): how many pixels, and how many ended up behind something solid
	var decor := 0
	var decor_hid := 0
	for v1 in bp.c:
		if ((v1 >> 8) & 255) == Defs.DECOR:
			decor += 1
			var f1: int = v1 & 255
			if f1 != 0 and f1 != 255 and Defs.KIND[f1] != Defs.K_EMPTY:
				decor_hid += 1
	var ch := []
	for q in bp.chests:
		ch.append(Vector2i(posmod(bp.x0 + q.x, N0), bp.y0 + q.y))
		# the chest object: its middle, standing on the floor row
		var ang := float(posmod(bp.x0 + q.x, N0) + Defs.CHEST_W / 2) / N0 * TAU
		var rr := Defs.R_TOP - float(bp.y0 + q.y) + Defs.CHEST_H * 0.5 + 0.05
		chest_list.append({"pos": Vector2(cos(ang), sin(ang)) * rr, "ruined": bp.ruined})
	for d in bp.doors:
		var da := (float(posmod(bp.x0 + int(d[0]), N0)) + float(d[2]) * 0.5) / N0 * TAU
		var dr := Defs.R_TOP - float(bp.y0 + int(d[1])) - float(d[3]) * 0.5
		door_list.append({"pos": Vector2(cos(da), sin(da)) * dr, "w": int(d[2]), "h": int(d[3]), "side": int(d[4]), "col": posmod(bp.x0 + int(d[0]), N0), "row": bp.y0 + int(d[1])})
	infos.append({"x0": posmod(bp.x0, N0), "y0": bp.y0, "w": bp.w, "h": bp.h, "ruined": bp.ruined, "solid": solid, "chests": ch, "cells": kept, "meta": bp.meta, "decor": decor, "decor_hid": decor_hid, "unsound": unsound, "data": bp.c if KEEP_DATA else PackedInt32Array()})
	var ci := bp.x0 + bp.w / 2
	var cj := bp.y0 + bp.h / 2
	var a := (float(posmod(ci, N0)) + 0.5) / N0 * TAU
	var r := Defs.R_TOP - (cj + 0.5)
	settle.append([Vector2(cos(a), sin(a)) * r, maxf(bp.w, bp.h) * 0.5 + 26.0])

# ------------------------------------------------------- chests and guards ---
## a 12 x 9 treasure chest standing on the floor row fl, left column i. A chest is a real object
## (it falls if you dig out its floor), but you walk through it; open it with F or by digging at it.
func _chest(bp: BP, i: int, fl: int, sure := false) -> void:
	# treasure is meant to be found, not tripped over: most possible chests are left out
	if not sure and rng.randf() > CHEST_KEEP:
		return
	bp.chests.append(Vector2i(i, fl))

## a foe waiting on the floor row fl at column i (local), spawned when you come near
func _guard(bp: BP, i: int, fl: int, type: String) -> void:
	if _quiet:
		return
	var col := posmod(bp.x0 + i, N0)
	# about a third of the skeletons on guard carry bows instead (picked by where they stand, so
	# planning stays the same from run to run)
	if type == "skeleton" and posmod(col * 7 + fl * 13, 3) == 0:
		type = "archer"
	var d: Dictionary = Defs.ENEMY[type]
	var a := (float(col) + 0.5) / N0 * TAU
	var r := Defs.R_TOP - float(bp.y0 + fl) + float(d["h"]) * 0.5 + 1.0
	if type == "bat":
		r += 6.0
	guards.append({"pos": Vector2(cos(a), sin(a)) * r, "type": type})

# -------------------------------------------------------- building pieces ---
## The first row (from the top) where column i of the blueprint is built solid, or h.
func _top_solid(bp: BP, i: int) -> int:
	for j in bp.h:
		var f := bp.getf(i, j)
		if f != 0 and f != 255 and Defs.KIND[f] == Defs.K_SOLID:
			return j
	return bp.h

## Hollow out [i0, i1] x [j0, j1] inside a solid mass (a pyramid, a mound), keeping a shell at
## least `shell` rows thick under its outer surface, and put a back wall of m behind what's
## hollowed. open_top: clear the whole box anyway (a doorway or cutting); the back wall still only
## goes where the mass was above it, so it never stands out against the sky.
func _carve_inside(bp: BP, i0: int, i1: int, j0: int, j1: int, m: int, shell: int, open_top: bool) -> void:
	for i in range(i0, i1 + 1):
		var t := _top_solid(bp, i)
		var j_from := j0 if open_top else maxi(j0, t + shell)
		for j in range(j_from, j1 + 1):
			bp.fg(i, j, 0)
			if j > t + 1:
				bp.bg(i, j, m)

## Scaffold landings down a shaft [i0, i1] from row j0 to j1: one-way platforms jutting from
## alternate sides every 22 rows, so you can climb a shaft by jumping and drop down it with
## down + jump. Each landing reaches about 60% across, two cells thick, on a bracket.
func _landings(bp: BP, i0: int, i1: int, j0: int, j1: int, spacing := 22) -> void:
	var span := maxi(6, int((i1 - i0 + 1) * 0.6))
	var j := j0
	var left := true
	while j < j1:
		var a := i0 if left else i1 - span + 1
		var b2 := a + span - 1
		bp.rect(a, j, b2, j + 1, Defs.SCAFFOLD)
		# a diagonal bracket behind it, from the wall up to the landing's middle
		var wall_i := i0 if left else i1
		var dir := 1 if left else -1
		for k in mini(5, span / 2):
			bp.bg(wall_i + dir * k, j + 2 + (4 - k), Defs.WOOD)
		left = not left
		j += spacing

## A building's shell: walls, floors (with a gap to float up through), doors, back wall
## with windows, torches, maybe a treasure chest. ox = left column (local), base = local row
## of the ground floor, w = width, floors = storeys. Returns the local row of the top slab.
func _building(bp: BP, ox: int, base: int, w: int, floors: int, st: Dictionary, doors := 3, ruined := false, guard := "", chest_p := 0.3, max_guards := 99) -> int:
	var top := base - floors * STOREY
	var th: int = st["thick"]
	# interior: clear and put up the back wall
	bp.rect(ox, top, ox + w - 1, base - 1, 0)
	bp.rect_bg(ox, top, ox + w - 1, base, st["back"])
	# outer walls
	for t in th:
		bp.rect(ox + t, top, ox + t, base, st["wall"])
		bp.rect(ox + w - 1 - t, top, ox + w - 1 - t, base, st["wall"])
	if st["post"] != st["wall"]:
		bp.rect(ox, top, ox, base, st["post"])
		bp.rect(ox + w - 1, top, ox + w - 1, base, st["post"])
	# floors, each with a gap at alternating ends to levitate through
	var ft := mini(th, 3)     # floor thickness
	for k in floors + 1:
		var j := base - k * STOREY
		bp.rect(ox, j, ox + w - 1, j, st["slab"])
		if k > 0:
			for r in range(1, ft):
				bp.rect(ox + th, j + r, ox + w - 1 - th, j + r, st["slab"])
		if k > 0 and k < floors:
			var left := k % 2 == 1
			var g0 := ox + th + 1 if left else ox + w - th - 1 - GAP
			bp.rect(g0, j, g0 + GAP - 1, j + ft - 1, 0)
	# doorways: open to walk through, with a dark wooden door frame behind
	if doors & 1:
		bp.rect(ox, base - DOOR, ox + th - 1, base - 1, 0)
		bp.rect_bg(ox, base - DOOR, ox + th - 1, base - 1, Defs.WOOD)
		_door(bp, ox, base - DOOR, th, DOOR, 1, ruined)
	if doors & 2:
		bp.rect(ox + w - th, base - DOOR, ox + w - 1, base - 1, 0)
		bp.rect_bg(ox + w - th, base - DOOR, ox + w - 1, base - 1, Defs.WOOD)
		_door(bp, ox + w - th, base - DOOR, th, DOOR, -1, ruined)
	# framing on the back wall, then windows, torches, treasure and whoever guards it
	_back_frame(bp, ox + th, top, ox + w - 1 - th, base, floors, st)
	for k in floors:
		var fl := base - k * STOREY
		var i := ox + th + 4
		while i + 7 < ox + w - th - 3:
			if rng.randf() < 0.55:
				_window(bp, i, fl, st)
			i += 18
		if not ruined and rng.randf() < 0.85:
			var ti := rng.randi_range(ox + th + 2, ox + w - th - 3)
			bp.bg(ti, fl - 24, Defs.TORCH)
			bp.bg(ti, fl - 23, Defs.WOOD)
		# a chest must stand on solid floor: keep it off the gap you float up through
		var spots := []
		for ci in range(ox + th + 2, ox + w - th - 1 - Defs.CHEST_W):
			if k == 0 or not _over_gap(ci, ci + Defs.CHEST_W - 1, ox, w, th, k):
				spots.append(ci)
		if not spots.is_empty() and rng.randf() < chest_p:
			_chest(bp, spots[rng.randi_range(0, spots.size() - 1)], fl)
		# guards keep to the upper floors first
		if guard != "" and max_guards > 0 and k >= floors - max_guards and rng.randf() < 0.75:
			_guard(bp, ox + w / 2 + rng.randi_range(-w / 4, w / 4), fl, guard)
	return top

## A window in the back wall, 9 wide, its sill 16 rows above the floor row fl. The style's
## "window" picks the shape; "shutters" hangs a pair beside it.
func _window(bp: BP, i: int, fl: int, st: Dictionary) -> void:
	var fr: int = st["post"]
	match st.get("window", "cross"):
		"arch":
			bp.rect_bg(i - 1, fl - 33, i + 7, fl - 16, fr)
			bp.rect_bg(i, fl - 30, i + 6, fl - 17, 0)
			bp.rect_bg(i + 1, fl - 32, i + 5, fl - 31, 0)
			bp.rect_bg(i + 2, fl - 33, i + 4, fl - 33, 0)
			bp.rect_bg(i + 3, fl - 32, i + 3, fl - 17, fr)
			bp.rect_bg(i - 2, fl - 16, i + 8, fl - 15, st.get("course", fr))      # sill
		"round":
			for dj in range(-6, 7):
				for di in range(-6, 7):
					var d := Vector2(di, dj).length()
					if d < 5.6:
						bp.bg(i + 3 + di, fl - 24 + dj, fr if (d >= 4.3 or di == 0 or dj == 0) else 0)
		"tall":
			bp.rect_bg(i, fl - 35, i + 6, fl - 14, fr)
			bp.rect_bg(i + 1, fl - 34, i + 5, fl - 15, 0)
			bp.rect_bg(i + 1, fl - 28, i + 5, fl - 28, fr)
			bp.rect_bg(i - 1, fl - 14, i + 7, fl - 13, st.get("course", fr))      # sill
		_:
			bp.rect_bg(i - 1, fl - 31, i + 7, fl - 16, fr)
			bp.rect_bg(i, fl - 30, i + 6, fl - 17, 0)
			bp.rect_bg(i + 3, fl - 30, i + 3, fl - 17, fr)
			bp.rect_bg(i, fl - 24, i + 6, fl - 24, fr)
	if st.get("shutters", false):
		for side in [i - 4, i + 8]:
			for j in range(fl - 31, fl - 15):
				bp.rect_bg(side, j, side + 2, j, Defs.WOOD if j % 3 != 0 else Defs.PLANK)

## Texture on a building's back wall between columns i0 and i1: half-timbering (posts, beams
## and braces in dark wood) or stone courses (a band of a second stone at each storey, with
## pilasters), as the style's "frame" says.
func _back_frame(bp: BP, i0: int, top: int, i1: int, base: int, floors: int, st: Dictionary) -> void:
	match st.get("frame", "plain"):
		"timber":
			for k in floors:
				var fl := base - k * STOREY
				var ceil_j := fl - STOREY + 3
				bp.rect_bg(i0, fl - 20, i1, fl - 20, Defs.WOOD)
				bp.rect_bg(i0, ceil_j, i1, ceil_j, Defs.WOOD)
				var p := i0 + 1
				var n := 0
				while p <= i1:
					bp.rect_bg(p, ceil_j, p, fl - 1, Defs.WOOD)
					# a brace across every other bay, in the lower half
					if n % 2 == 0 and p + 12 <= i1:
						for d in 12:
							bp.bg(p + d, fl - 2 - d * 18 / 12, Defs.WOOD)
					p += 14
					n += 1
				bp.rect_bg(i1, ceil_j, i1, fl - 1, Defs.WOOD)
		"course":
			var cm: int = st.get("course", st["back"])
			for k in floors:
				var fl := base - k * STOREY
				bp.rect_bg(i0, fl - 11, i1, fl - 10, cm)
				bp.rect_bg(i0, fl - STOREY + 4, i1, fl - STOREY + 4, cm)
			var q := i0 + 9
			while q < i1 - 3:
				bp.rect_bg(q, top + 1, q + 1, base - 1, cm)
				q += 24

## A chimney stack through one side of a pitched roof: masonry or brick from the top slab up,
## standing a few rows proud of the roof, with a cap.
func _chimney(bp: BP, ox: int, top: int, w: int, st: Dictionary) -> void:
	var ci := ox + int(w * (0.22 if rng.randf() < 0.5 else 0.7))
	var m := Defs.BRICK if st["wall"] != Defs.BRICK else Defs.MASONRY
	# where the roof's outer surface is over this column
	var rs := top
	for j in range(0, top):
		var f := bp.getf(ci + 2, j)
		if f != 0 and f != 255:
			rs = j
			break
	var ct := rs - 8
	bp.rect(ci, ct, ci + 4, top - 1, m)
	bp.rect_bg(ci, ct, ci + 4, top - 1, m)
	bp.rect(ci - 1, ct - 1, ci + 5, ct - 1, Defs.MASONRY)
	bp.fg(ci + 2, ct - 1, 0)

## A porch over a door: a little sloped roof on brackets jutting `depth` cells out from the wall
## whose outer column is wall_i (side -1 = out to the left, 1 = to the right), with a post at its outer
## corner standing against the background so you walk past it.
func _porch(bp: BP, wall_i: int, base: int, side: int, st: Dictionary, depth := 9) -> void:
	var j := base - DOOR - 3
	var m: int = st["roof"]
	for d in range(1, depth + 1):
		var i := wall_i + side * d
		bp.fg(i, j, st.get("trim", Defs.WOOD))
		var rise := (depth - d) / 3
		for r in range(1, rise + 2):
			bp.fg(i, j - r, m)
	# the post reaches down to the yard's ground (which may dip below the floor out here), so the
	# porch stands on something instead of hanging
	var pi := wall_i + side * (depth - 1)
	var pb := base - 1
	while pb + 1 < bp.h:
		var fb := bp.getf(pi, pb + 1)
		if (fb != 0 and fb != 255) or (fb == 255 and pb + 1 >= ground_row(bp.x0 + pi) - bp.y0):
			break
		pb += 1
	bp.rect_bg(pi, j, pi, pb, Defs.WOOD)        # from the roof's edge board down: it holds the roof up
	for d in 4:
		bp.bg(wall_i + side * (1 + d), j + 1 + d, Defs.WOOD)

## does columns [i0, i1] overlap the gap left in floor k (floors above the ground floor have one)?
func _over_gap(i0: int, i1: int, ox: int, w: int, th: int, k: int) -> bool:
	var g0 := ox + th + 1 if k % 2 == 1 else ox + w - th - 1 - GAP
	return i1 >= g0 - 1 and i0 <= g0 + GAP

func _roof(bp: BP, ox: int, top: int, w: int, st: Dictionary) -> int:
	var kind: String = st["roof_kind"]
	var m: int = st["roof"]
	var hi := top
	match kind:
		"pitch", "steep":
			var t := 0
			var over := 2 if kind == "pitch" else 1
			var trim: int = st.get("trim", m)
			# eaves: the roof's foot overhangs a little further, in a darker board
			bp.rect(ox - over - 1, top - 1, ox - over, top - 1, trim)
			bp.rect(ox + w - 1 + over, top - 1, ox + w + over, top - 1, trim)
			while true:
				var step := t if kind == "pitch" else t / 2
				var L := ox - over + step
				var R := ox + w - 1 + over - step
				var j := top - 1 - t
				bp.rect_bg(L, j, R, j, st["back"])
				if R - L < 3:
					# the ridge: a capping row and a finial on top
					bp.rect(L - 1, j, R + 1, j, st.get("ridge", m))
					bp.fg((L + R) / 2, j - 1, st.get("ridge", m))
					if R - L >= 2:
						bp.fg((L + R) / 2 + 1, j - 1, st.get("ridge", m))
					hi = j - 1
					break
				# roof slopes 3 tiles thick, to match the thicker walls
				bp.rect(L, j, mini(L + 2, R), j, m)
				bp.rect(maxi(R - 2, L), j, R, j, m)
				if R - L > 5:
					bp.rect(L + 3, j, R - 3, j, 0)
					bp.rect_bg(L + 3, j, R - 3, j, st["back"])
				hi = j
				t += 1
		"flat":
			bp.rect(ox, top - 2, ox + 1, top - 1, m)
			bp.rect(ox + w - 2, top - 2, ox + w - 1, top - 1, m)
			hi = top - 2
		"battle":
			var i := ox
			while i < ox + w:
				if ((i - ox) / 2) % 2 == 0 or i >= ox + w - 2:
					bp.rect(i, top - 3, mini(i + 1, ox + w - 1), top - 1, m)
				i += 2
			bp.rect(ox, top - 1, ox + w - 1, top - 1, m)
			hi = top - 3
		"dome":
			var rad := w * 0.5
			var cx := ox + (w - 1) * 0.5
			for j in range(top - int(rad) - 1, top):
				for i in range(ox, ox + w):
					var d := Vector2(i - cx, (j - top) * 1.15).length()
					if d < rad and d >= rad - 2.0:
						bp.fg(i, j, m)
						bp.bg(i, j, st["back"])
					elif d < rad - 2.0:
						bp.fg(i, j, 0)
						bp.bg(i, j, st["back"])
			hi = top - int(rad) - 1
	return hi

## foundation from the floor down into the ground, so the building never hangs over a dip
## A plinth of the building's stone (two courses under the floor), and below it, where the ground dips,
## the ground itself built back up in its own layers (topsoil, then what lies under it), so a house on a
## slope doesn't stand on a block of bricks with ruler-straight sides.
func _foundation(bp: BP, ox: int, base: int, w: int, m: int) -> void:
	for i in range(ox, ox + w):
		var g := ground_row(bp.x0 + i) - bp.y0
		var gm := _ground_mats(bp.x0 + i)
		for j in range(base + 1, maxi(base + 2, g + 3)):
			var depth := j - base - 1
			var mat := m
			if depth >= 2:
				mat = gm[0] if depth - 2 < int(gm[1]) else gm[2]
			bp.fg(i, j, mat, F_FILL | F_ANCHOR)

## the ground's own materials at a column: [top, top depth, what lies under it] (anything that would
## run or flow, like mud, becomes dirt; a snow cap is the snow's business, not ours)
func _ground_mats(col: int) -> Array:
	var bd: Dictionary = Defs.BIOMES.get(biome(col), {})
	var top: int = bd.get("top", Defs.DIRT)
	var sub: int = bd.get("sub", Defs.DIRT)
	var td: int = bd.get("topD", 1)
	for k in 2:
		var mm: int = top if k == 0 else sub
		var kd: int = Defs.KIND[mm]
		if kd != Defs.K_SOLID and kd != Defs.K_POWDER:
			if k == 0:
				top = Defs.GRASS   # gen.comp packs a liquid top layer (mud) to grass over dirt
				td = 1
			else:
				sub = Defs.DIRT
	if td <= 0:
		top = sub
		td = 1
	return [top, td, sub]

## dig out the hillside in front of doors so you can walk in
## The level ground in front of a building's doors. Across the outer YARD columns at each end
## it ramps smoothly back to the natural ground (no vertical cuts or steps to trip on).
func _yard(bp: BP, i0: int, i1: int, base: int) -> void:
	for i in range(i0, i1 + 1):
		var g := ground_row(bp.x0 + i) - bp.y0
		var e := mini(i - i0, i1 - i)
		var t := clampf(1.0 - float(e) / float(YARD), 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var target := int(round(lerpf(float(base), float(g), t)))
		bp.rect(i, mini(target, base) - DOOR - 5, i, target - 1, 0)
		# the yard is made of the ground around it: its topsoil, then what lies under that
		var gm := _ground_mats(bp.x0 + i)
		for j in range(target, maxi(target + 1, g + 2)):
			bp.fg(i, j, gm[0] if j - target < int(gm[1]) else gm[2], F_FILL | F_ANCHOR)

# ------------------------------------------------------------------ ruins ---
## Damage an intact structure inside [i0, i1] x [j0, j1]: jagged broken tops, holes, rotten
## wood, moss, back walls with gaps. The physics finishes the job when the planet settles.
func _ruin(bp: BP, i0: int, i1: int, j0: int, j1: int, b: String, outdoors := true) -> void:
	# A ruin is drawn as a ruin, not as a building with squares cut out of it:
	#  - the walls crumble from the top in a stepped skyline, with one to three V-shaped breaches
	#    where whole sections came down (stepped edges, like fallen masonry courses);
	#  - wooden walls lose whole boards (vertical streaks from the top), not single cells;
	#  - moss grows on every exposed top surface and creeps down the stone; the back wall is
	#    stained with moss in patches;
	#  - rubble mounds (gravel, or timber for wood) lie under each breach, sloped so they rest,
	#    with a fallen beam or two on the ground floor;
	#  - vines hang from broken tops in the wilder biomes.
	# Floors left hanging too far from what's still standing are removed afterwards by the
	# support pass (_stabilize_pass), so what remains is sound.
	var hgt := j1 - j0
	var wid := i1 - i0 + 1
	var depth := PackedInt32Array()
	depth.resize(wid)
	if outdoors:
		var base_cut := int(hgt * rng.randf_range(0.2, 0.45))
		var wob := 0.0
		var col := 0
		while col < wid:
			wob = clampf(wob + rng.randf_range(-4.0, 4.0), -10.0, 10.0)
			var run := rng.randi_range(2, 5)
			for k in run:
				if col + k < wid:
					depth[col + k] = base_cut + int(wob)
			col += run
		for n in rng.randi_range(1, 3):
			var bc := rng.randi_range(0, wid - 1)
			var bw := rng.randf_range(wid * 0.12, wid * 0.35) + 4.0
			var bd := hgt * rng.randf_range(0.3, 0.75)
			for c2 in wid:
				var t := 1.0 - absf(c2 - bc) / (bw * 0.5)
				if t > 0.0:
					depth[c2] = maxi(depth[c2], int(floor(bd * t / 2.0)) * 2 + base_cut / 2)
		for c3 in wid:
			for j in range(j0, mini(j1 + 1, j0 + depth[c3])):
				_break(bp, i0 + c3, j)
	# rotten boards: whole vertical strips from the top of what's left
	for c4 in wid:
		if rng.randf() < 0.16:
			var top := j0 + depth[c4]
			var run2 := rng.randi_range(4, 14)
			for j in range(top, mini(j1 + 1, top + run2)):
				var f := bp.getf(i0 + c4, j)
				if f == Defs.PLANK or f == Defs.WOOD:
					bp.fg(i0 + c4, j, 0)
	# moss on exposed tops, creeping down the stone; stains on the back wall
	for c5 in wid:
		var ii := i0 + c5
		var creep := 0
		for j in range(j0, j1 + 1):
			var f2 := bp.getf(ii, j)
			var stone := f2 == Defs.MASONRY or f2 == Defs.BRICK or f2 == Defs.SANDSTONE
			if stone and (bp.getf(ii, j - 1) == 0 or bp.getf(ii, j - 1) == 255):
				creep = rng.randi_range(1, 4)
			if stone and creep > 0:
				bp.fg(ii, j, Defs.MOSSBLOCK)
				creep -= 1
			elif f2 != 0 and f2 != 255:
				creep = 0
			var g2 := bp.getb(ii, j)
			if g2 == Defs.TORCH:
				bp.bg(ii, j, 0)
			elif (g2 == Defs.MASONRY or g2 == Defs.BRICK) and sin(ii * 0.31 + j * 0.17) + sin(ii * 0.13 - j * 0.29) > 1.2:
				bp.bg(ii, j, Defs.MOSSBLOCK)
	# rubble under each breach and a few more mounds, plus fallen beams on the ground floor
	var rub := Defs.TIMBER
	for c6 in range(0, wid, 3):
		var f3 := bp.getf(i0 + c6, j1 + 1)
		if f3 == Defs.MASONRY or f3 == Defs.BRICK or f3 == Defs.SANDSTONE or f3 == Defs.OBSIDIAN:
			rub = Defs.GRAVEL
			break
	var mounds := []
	for c7 in range(1, wid - 1):
		if depth[c7] > depth[c7 - 1] + 3 and depth[c7] > depth[c7 + 1] - 1 and rng.randf() < 0.35:
			mounds.append(c7)
	for n2 in rng.randi_range(1, 3):
		mounds.append(rng.randi_range(2, wid - 3))
	for mc in mounds:
		var mh := rng.randi_range(3, 7)
		for dc in range(-mh - 1, mh + 2):
			var colh := mh - absf(dc)        # slope 1: it rests
			for k2 in int(colh):
				var jj: int = j1 - k2
				if bp.ok(i0 + mc + dc, jj) and bp.getf(i0 + mc + dc, jj) == 0:
					bp.fg(i0 + mc + dc, jj, rub, F_FILL)
	for n3 in rng.randi_range(0, 2):
		var bx := rng.randi_range(2, maxi(2, wid - 12))
		var bl := rng.randi_range(5, 10)
		for dx in bl:
			if bp.ok(i0 + bx + dx, j1) and bp.getf(i0 + bx + dx, j1) == 0:
				bp.fg(i0 + bx + dx, j1, Defs.WOOD, F_FILL)
	# hanging vines in the wilder places
	if outdoors and (b == "forest" or b == "marsh" or b == "ocean" or b == "mountain" or b == "jungle" or b == "grove"):
		for n4 in rng.randi_range(3, 7):
			var vc := rng.randi_range(0, wid - 1)
			var vj := j0 + depth[vc]
			var vl := rng.randi_range(5, 16)
			for k3 in vl:
				if bp.ok(i0 + vc, vj + k3) and bp.getf(i0 + vc, vj + k3) == 0:
					bp.bg(i0 + vc, vj + k3, Defs.LEAF, false)
	# the wilds move in
	if not outdoors:
		return
	if b == "desert":
		var bury := rng.randi_range(3, 12)
		for i in range(i0 - 4, i1 + 5):
			var g := ground_row(bp.x0 + i) - bp.y0
			# a drift that slopes off at the ends (no sand wall to pour down)
			var hb := mini(bury, mini(i - (i0 - 4), (i1 + 4) - i) + 1)
			for j in range(g - hb, g):
				if bp.ok(i, j) and bp.getf(i, j) == 0:
					bp.fg(i, j, Defs.SAND)
				elif bp.ok(i, j) and bp.getf(i, j) == 255:
					bp.fg(i, j, Defs.SAND, F_FILL)

func _break(bp: BP, i: int, j: int) -> void:
	if not bp.ok(i, j) or bp.is_fill(i, j):
		return
	var f := bp.getf(i, j)
	if f != 255 and f != 0 and f != Defs.TREASURE:
		bp.fg(i, j, 0)
	var g := bp.getb(i, j)
	if g != 255 and g != 0:
		bp.bg(i, j, 0)

## Masonry set into the ground (shaft linings, buried corridors, foundations) gets a ragged outer
## edge instead of a ruler-straight one: along every side that meets natural ground, the stones
## reach out 0-3 cells further, course by course (runs of 2-4 rows), and flare out near the surface
## like a footing. Only natural ground is replaced (fill), so nothing built is touched.
func _roughen_underground(bp: BP) -> void:
	var w := bp.w
	var h := bp.h
	var gj := PackedInt32Array()
	gj.resize(w)
	for i in w:
		gj[i] = ground_row(bp.x0 + i) - bp.y0
	var rs := rng.randi()
	var adds := []
	for j in h:
		for i in w:
			var f := bp.getf(i, j)
			if not _rough_mat(f) or bp.is_fill(i, j):
				continue
			for dir in [-1, 1, 0]:
				var di: int = dir
				var dj := 1 if dir == 0 else 0
				var ni := i + di
				var nj := j + dj
				if not bp.ok(ni, nj) or bp.getf(ni, nj) != 255 or nj <= gj[ni]:
					continue
				# the course this edge cell belongs to (rows in runs of 2-4) and how far it reaches
				var course := (j + int(_blockr(rs, i, 0, 3) * 3.0)) / (2 + int(_blockr(rs, i, j / 4, 4) * 2.99))
				var reach := int(_blockr(rs, i * 3 + dir, course, 5) * 3.99)
				if dir != 0 and nj - gj[ni] < 7:
					reach += 2                     # a footing near the surface
				if dir == 0:
					reach = mini(reach, 2)
				for k in range(1, reach + 1):
					adds.append(Vector3i(i + di * k, j + dj * k, f))
	# written outright, not as a fill: a fill only goes where the world is open, so the ragged edge
	# would show in caves but never where the masonry meets solid earth, which is where it matters
	for a in adds:
		if bp.ok(a.x, a.y) and bp.getf(a.x, a.y) == 255 and a.y > gj[a.x]:
			bp.fg(a.x, a.y, a.z, F_ANCHOR)
	# the same for back walls underground: where a buried hall's back wall meets the natural rock
	# behind a cave, its edge is ragged too, not a straight cut
	var badds := []
	for j in h:
		for i in w:
			var g := bp.getb(i, j)
			if g == 255 or g == 0 or (bp.c[j * w + i] & F_WALL) == 0 or j <= gj[i]:
				continue
			for dir in [-1, 1, 0, 2]:
				var di2: int = -1 if dir == -1 else (1 if dir == 1 else 0)
				var dj2: int = 1 if dir == 0 else (-1 if dir == 2 else 0)
				var ni := i + di2
				var nj := j + dj2
				if not bp.ok(ni, nj) or bp.getb(ni, nj) != 255 or nj <= gj[ni] + 2:
					continue
				var course := (j + int(_blockr(rs, i, 1, 6) * 3.0)) / (2 + int(_blockr(rs, i, j / 4, 7) * 2.99))
				var reach := int(_blockr(rs, i * 3 + dir, course, 8) * 3.99)
				for k in range(1, reach + 1):
					badds.append(Vector3i(i + di2 * k, j + dj2 * k, g))
	for a2 in badds:
		if bp.ok(a2.x, a2.y) and bp.getb(a2.x, a2.y) == 255 and a2.y > gj[a2.x] + 2:
			bp.bg(a2.x, a2.y, a2.z)

## (a dungeon's runestone too: the roughening only ever adds cells outward into the earth, so its
## shafts and halls stay exactly as built)
## Where masonry meets the ground line outside a building (a foundation's courses past its walls,
## the buried steps of a ruin), the ground takes it back a little, so it doesn't sit in the earth
## as a ruler-straight band: the ends of courses crumble into the ground around them, and the
## biome's topsoil drifts unevenly over the exposed tops. Never inside a building (where there's a
## back wall), never in front of a door, never the warded stone of dungeons and vaults.
func _weather_ground_line(bp: BP) -> void:
	var w := bp.w
	var h := bp.h
	var wr := RandomNumberGenerator.new()
	wr.seed = hash(Vector2i(bp.x0, bp.y0)) ^ 0x5eed
	var gj := PackedInt32Array()
	gj.resize(w)
	for i in w:
		gj[i] = ground_row(bp.x0 + i) - bp.y0
	# columns in front of doors stay clear (a drift there would trip you on the doorstep)
	var near_door := PackedByteArray()
	near_door.resize(w)
	for d in bp.doors:
		for i in range(int(d[0]) - 8, int(d[0]) + int(d[2]) + 8):
			if i >= 0 and i < w:
				near_door[i] = 1
	var weatherable := func(f: int) -> bool:
		return f == Defs.MASONRY or f == Defs.BRICK or f == Defs.SANDSTONE or f == Defs.MOSSBLOCK or f == Defs.STONE
	var outside := func(i: int, j: int) -> bool:
		var b: int = bp.getb(i, j)
		return b == 255 or b == 0
	var earthy := func(f: int) -> bool:
		return f == 255 or (f != 0 and Defs.KIND[f] == Defs.K_POWDER) or f == Defs.DIRT or f == Defs.GRASS or f == Defs.MUD
	# 0. a ruin is half swallowed by the ground: its masonry near the ground line gives way to the
	# ground's own soil in uneven lumps (most of it right at the surface, less deeper down), so its
	# buried part reads as a ruin in the sand, not a band of bricks
	if bp.ruined:
		var p1 := wr.randf() * TAU
		var p2 := wr.randf() * TAU
		for i in w:
			var gm0 := _ground_mats(bp.x0 + i)
			for j in range(maxi(gj[i] - 1, 0), mini(gj[i] + 16, h)):
				var f0 := bp.getf(i, j)
				if not weatherable.call(f0):
					continue
				var nz := sin(float(i) * 0.21 + float(j) * 0.37 + p1) + sin(float(i) * 0.083 - float(j) * 0.19 + p2) + wr.randf() * 0.7
				var depth0: int = j - gj[i]
				if nz > -0.3 + float(maxi(depth0, 0)) * 0.12:
					bp.fg(i, j, gm0[0] if depth0 < int(gm0[1]) else gm0[2], F_FILL | F_ANCHOR)
	# 1. the ends of courses crumble: a block with earth beside it gives way to earth, and now and
	# then the one behind it too
	for pass_k in 2:
		var turn := []
		for i in w:
			for j in range(maxi(gj[i], 0), mini(gj[i] + 9, h)):      # (at and below the ground line only)
				var f := bp.getf(i, j)
				if not weatherable.call(f) or not outside.call(i, j):
					continue
				var el: bool = (not bp.ok(i - 1, j)) or earthy.call(bp.getf(i - 1, j))
				var er: bool = (not bp.ok(i + 1, j)) or earthy.call(bp.getf(i + 1, j))
				if (el or er) and wr.randf() < (0.55 if pass_k == 0 else 0.3):
					turn.append(Vector2i(i, j))
		for q in turn:
			var gm := _ground_mats(bp.x0 + q.x)
			var depth: int = q.y - gj[q.x]
			bp.fg(q.x, q.y, gm[0] if depth < int(gm[1]) else gm[2], F_FILL | F_ANCHOR)
	# 2. drifts over the exposed tops near the ground line, a smooth bumpy height along the run,
	# and a top block here and there worn away to soil
	var phase := wr.randf() * TAU
	for i in w:
		if near_door[i] != 0:
			continue
		for j in range(maxi(gj[i] - 3, 1), mini(gj[i] + 5, h)):
			var f := bp.getf(i, j)
			if not weatherable.call(f) or not outside.call(i, j):
				continue
			var above := bp.getf(i, j - 1)
			if not (above == 0 or above == 255) or not outside.call(i, j - 1):
				break
			var gm2 := _ground_mats(bp.x0 + i)
			var dh := int(round(1.2 + sin(float(i) * 0.45 + phase) * 1.1 + wr.randf() * 0.9))
			for k in range(1, dh + 1):
				var a2 := bp.getf(i, j - k)
				if (a2 == 0 or a2 == 255) and outside.call(i, j - k):
					bp.fg(i, j - k, gm2[0], F_FILL | F_ANCHOR)
			if wr.randf() < 0.3:
				bp.fg(i, j, gm2[0], F_FILL | F_ANCHOR)
			break

func _rough_mat(f: int) -> bool:
	return f == Defs.MASONRY or f == Defs.BRICK or f == Defs.SANDSTONE or f == Defs.OBSIDIAN or f == Defs.MOSSBLOCK or f == Defs.RUNESTONE

## A wooden door filling a doorway (i0, j0, w x h, local). Its cells know which part of the door they
## are, for drawing; the game opens it when you walk into it or press F. A ruin has lost most of its
## doors. side: which way the inside is (the open door swings that way).
func _door(bp: BP, i0: int, j0: int, w: int, h: int, side: int, ruined: bool) -> void:
	if ruined and rng.randf() < 0.7:
		return
	for j in h:
		for i in w:
			bp.fgv(i0 + i, j0 + j, Defs.WOODDOOR, (mini(j, 31) << 2) | mini(i, 3))
	bp.doors.append([i0, j0, w, h, side])

## back-wall cells set into solid rock (a mine shaft's planking, timber props, torches on a drift's
## wall): anchored as built, so the soundness pass doesn't cut them away for want of a wall below
func _set_in_rock(bp: BP, i0: int, j0: int, i1: int, j1: int) -> void:
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if bp.ok(i, j) and bp.getb(i, j) != 255 and bp.getb(i, j) != 0:
				bp.c[j * bp.w + i] |= F_ANCHOR

## a repeatable random number for a block of cells (the same for every cell in the block)
func _blockr(seed_r: int, bi: int, bj: int, k: int) -> float:
	var h := hash(Vector3i(bi, bj, seed_r + k * 7919))
	return float(posmod(h, 10007)) / 10007.0

# ------------------------------------------------------------- structures ---
const YARD := 12

func _cottage(x: int, b: String, ruined: bool, build: bool, label := true, w_in := 0, role := "home") -> bool:
	var w := w_in if w_in > 0 else rng.randi_range(46, 62)
	var floors := 1 if rng.randf() < 0.55 else 2
	var st := _style(b, "home")
	var th: int = st["thick"]
	# parts: sometimes a lower wing on one side (the house is then two storeys), sometimes a
	# porch over the other door, maybe a chimney (in the style)
	var aw := 0
	var aside := 0
	if b != "desert" and w_in == 0 and rng.randf() < 0.4:
		aw = rng.randi_range(24, 30)
		aside = -1 if rng.randf() < 0.5 else 1
		floors = 2
	var porch := b != "desert" and rng.randf() < 0.45
	var full := w + (aw - th if aw > 0 else 0)
	var tw := full + 2 * YARD + 4
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, full + 4, 18):
		return false
	var base := _median_ground(x0 + YARD, full + 4) - 1
	var up := floors * STOREY + _roof_h(w, st) + 12
	var bp := BP.new(x0, base - up, tw, up + 40)
	bp.ruined = ruined
	var lb := up
	var left := YARD + 2
	var ox := left + (aw - th if aside < 0 else 0)
	_yard(bp, 0, tw - 1, lb)
	_foundation(bp, left - 1, lb, full + 2, st["found"])
	var hi := lb
	if aw > 0:
		# the wing first: the house's own wall then stands where the two meet, with a doorway
		var ax := left if aside < 0 else ox + w - th
		var at := _building(bp, ax, lb, aw, 1, st, 1 if aside < 0 else 2, ruined, "", 0.3)
		var wst := st.duplicate()
		wst["chimney"] = false
		hi = mini(hi, _roof(bp, ax, at, aw, wst))
	var top := _building(bp, ox, lb, w, floors, st, 3, ruined, "", 0.3)
	hi = mini(hi, _roof(bp, ox, top, w, st))
	if st["chimney"]:
		_chimney(bp, ox, top, w, st)
		hi -= 10
	if porch:
		if aside >= 0:
			_porch(bp, ox, lb, -1, st)
		if aside <= 0 and (aside < 0 or rng.randf() < 0.5):
			_porch(bp, ox + w - 1, lb, 1, st)
	if ruined:
		_ruin(bp, left - 3, left + full + 2, hi, lb - 1, b)
	# inside and out: furniture by what the house was, then the yard
	var kit := "dwelling" if b == "desert" and role == "home" else role
	_furnish(bp, ox, w, th, lb, floors, kit, ruined)
	if aw > 0:
		_furnish(bp, left if aside < 0 else ox + w - th, aw, th, lb, 1, "hut" if role != "home" else "home", ruined)
	_dress_yard(bp, left, full, role, ruined)
	if label:
		_claim(x0, tw, ("Ruined " if ruined else "Abandoned ") + ("Cottage" if b != "desert" else "Dwelling"), bp.y0, base + 2)
	else:
		used.append(Vector2i(x0, x0 + tw))
		sites.append(Vector2(posmod(x0, N0), posmod(x0, N0) + tw))
	_finish(bp, build)
	return true

## a row of houses with real gaps between them
func _town(x: int, b: String, ruined: bool, build: bool) -> bool:
	var n := rng.randi_range(3, 5)
	var widths := []
	var gaps := []
	var span := 0
	for k in n:
		var w := rng.randi_range(44, 58)
		widths.append(w)
		gaps.append(rng.randi_range(14, 40))
		span += w + 2 * YARD + 4 + int(gaps[k])
	# what each house is: a shop always, then maybe a smithy, a tavern or an inn; the rest are homes
	var roles := ["shop"]
	for r in ["smithy", "tavern", "inn"]:
		if rng.randf() < 0.45:
			roles.append(r)
	while roles.size() < n:
		roles.append("home")
	roles.resize(n)
	for k in range(n - 1, 0, -1):
		var o := rng.randi_range(0, k)
		var tmp = roles[k]
		roles[k] = roles[o]
		roles[o] = tmp
	if not _site_ok(x - span / 2, span, 50):
		return false
	var cx := x - span / 2
	var made := 0
	for k in n:
		var w: int = widths[k]
		var tw := w + 2 * YARD + 4
		if _cottage(cx + tw / 2, b, ruined and rng.randf() < 0.8, build, false, w, roles[k]):
			made += 1
		cx += tw
		# the open ground before the next house: sometimes a well, a market stall, lamps, flowers
		var gap: int = gaps[k]
		if k < n - 1 and gap >= 20 and rng.randf() < 0.75:
			_town_square(cx, gap, ruined, build)
		cx += gap
	if made == 0:
		return false
	labels.append({"x0": posmod(x - span / 2, N0), "w": span, "ymin": ground_row(x) - 170, "ymax": ground_row(x) + 4,
		"name": ("Ruins of a Village" if ruined else "Deserted Village")})
	return true

func _tower(x: int, b: String, ruined: bool, build: bool) -> bool:
	var w := rng.randi_range(32, 38)
	var floors := rng.randi_range(3, 4)
	var tw := w + 2 * YARD + 4
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, w + 4, 20):
		return false
	var st := _style(b, "fort")
	var base := _median_ground(x0 + YARD, w + 4) - 1
	var up := floors * STOREY + _roof_h(w, st) + 12
	var bp := BP.new(x0, base - up, tw, up + 40)
	bp.ruined = ruined
	var ox := YARD + 2
	_yard(bp, 0, tw - 1, up)
	_foundation(bp, ox - 1, up, w + 2, st["found"])
	var top := _building(bp, ox, up, w, floors, st, 3, ruined, "skeleton" if rng.randf() < 0.6 else "", 0.3, 1)
	var hi := _roof(bp, ox, top, w, st)
	if ruined:
		_ruin(bp, ox - 1, ox + w, hi, up - 1, b)
	_furnish(bp, ox, w, int(st["thick"]), up, floors, "tower", ruined)
	_claim(x0, tw, "Ruined Watchtower" if ruined else "Old Watchtower", bp.y0, base + 2)
	_finish(bp, build)
	return true

## Two corner towers, outer walls with gates, courtyards, and a great keep in the middle
## holding the lord's hoard and its guards.
func _castle(x: int, b: String, ruined: bool, build: bool) -> bool:
	var tw_w := 32
	var curt := 14
	var court := rng.randi_range(28, 40)
	var keep_w := rng.randi_range(76, 96)
	var inner := tw_w + curt + court + keep_w + court + curt + tw_w
	var tw := inner + 2 * YARD
	var x0 := x - tw / 2
	if not _site_ok(x0, tw, 80):
		return false
	var st := _style(b, "fort")
	st["roof_kind"] = "battle"
	var g := _ground_range(x0 + YARD, inner)
	var base := g.x + (g.y - g.x) / 3 - 1   # sits high: tall foundations on the low side
	var up := 4 * STOREY + 16
	var bp := BP.new(x0, base - up, tw, up + 70)
	bp.ruined = ruined
	var lb := up
	_yard(bp, 0, tw - 1, lb)
	var ox := YARD
	_foundation(bp, ox, lb, inner, st["found"])
	bp.solid(ox, lb, ox + inner - 1, lb, st["wall"])     # paved ground through the whole castle
	var hi := lb
	var t1 := _building(bp, ox, lb, tw_w, 4, st, 3, ruined, "skeleton", 0.2, 1)
	hi = mini(hi, _roof(bp, ox, t1, tw_w, st))
	var cx := ox + tw_w
	_curtain(bp, cx, lb, curt, 2 * STOREY + 4, st)
	_guard(bp, cx + curt + court / 2, lb, "skeleton")
	var kx := cx + curt + court
	var kt := _building(bp, kx, lb, keep_w, 3, st, 3, ruined, "skeleton", 0.35, 1)
	hi = mini(hi, _roof(bp, kx, kt, keep_w, st))
	# the lord's hoard on the top floor, well guarded
	var hf := lb - 2 * STOREY
	_chest(bp, kx + keep_w / 2 - 15, hf, true)
	_chest(bp, kx + keep_w / 2 + 3, hf)
	_guard(bp, kx + keep_w / 2 - 24, hf, "skeleton")
	_guard(bp, kx + keep_w / 2 + 24, hf, "skeleton")
	var c2 := kx + keep_w + court
	_guard(bp, kx + keep_w + court / 2, lb, "skeleton")
	_curtain(bp, c2, lb, curt, 2 * STOREY + 4, st)
	var t2 := _building(bp, c2 + curt, lb, tw_w, 4, st, 3, ruined, "skeleton", 0.2, 1)
	hi = mini(hi, _roof(bp, c2 + curt, t2, tw_w, st))
	if ruined:
		_ruin(bp, ox, ox + inner - 1, hi, lb - 1, b)
	_furnish(bp, kx, keep_w, int(st["thick"]), lb, 3, "keep", ruined)
	_furnish(bp, ox, tw_w, int(st["thick"]), lb, 4, "tower", ruined)
	_furnish(bp, c2 + curt, tw_w, int(st["thick"]), lb, 4, "tower", ruined)
	_claim(x0, tw, "Ruined Castle" if ruined else "Silent Castle", bp.y0, base + 2)
	_finish(bp, build)
	return true

## a castle wall: solid stone with a gate passage through it and battlements on top
func _curtain(bp: BP, ox: int, base: int, w: int, hgt: int, st: Dictionary) -> void:
	var top := base - hgt
	bp.solid(ox, top, ox + w - 1, base, st["wall"])
	bp.rect(ox, base - DOOR, ox + w - 1, base - 1, 0)
	bp.rect_bg(ox, base - DOOR, ox + w - 1, base - 1, Defs.WOOD)
	var i := ox
	while i < ox + w:
		if ((i - ox) / 2) % 2 == 0:
			bp.rect(i, top - 3, mini(i + 1, ox + w - 1), top - 1, st["wall"])
		i += 2

func _temple(x: int, ruined: bool, build: bool) -> bool:
	var half := rng.randi_range(46, 58)
	var W := half * 2 + 1
	var tw := W + 2 * YARD
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, W, 26):
		return false
	# a step pyramid of sandstone in the desert, of mossy stone in the jungle
	var m := Defs.MOSSBLOCK if biome(x) == "jungle" else Defs.SANDSTONE
	var base := _median_ground(x0 + YARD, W) - 1
	var steps := half / 3
	var up := steps * 4 + 8
	var bp := BP.new(x0, base - up, tw, up + 40)
	bp.ruined = ruined
	var lb := up
	var ox := YARD
	_foundation(bp, ox, lb, W, m)
	# steps 3 across and 4 up: a steep, stepped pyramid
	for s in steps:
		bp.solid(ox + s * 3, lb - s * 4 - 3, ox + W - 1 - s * 3, lb - s * 4, m)
	bp.solid(ox, lb, ox + W - 1, lb, m)
	# entrance passage and the inner sanctum, carved inside the pyramid's outline: the sanctum's
	# ceiling steps up under the slopes (a corbelled vault), and where the passage runs out under
	# the low outer steps it becomes an open cutting, with no back wall standing up into the sky
	var cx := ox + half
	_carve_inside(bp, ox, cx - 17, lb - DOOR, lb - 1, m, 4, true)
	_carve_inside(bp, cx - 16, cx + 16, lb - 44, lb - 1, m, 6, false)
	_chest(bp, cx - 14, lb, true)
	_chest(bp, cx + 4, lb)
	_guard(bp, cx - 8, lb, "skeleton")
	_guard(bp, cx + 10, lb, "skeleton")
	if not ruined:
		bp.bg(cx - 15, lb - 24, Defs.TORCH)
		bp.bg(cx + 15, lb - 24, Defs.TORCH)
	if ruined:
		_ruin(bp, ox, ox + W - 1, lb - steps * 4, lb - 46, "desert")
	_claim(x0, tw, "Buried Temple" if ruined else "Sun Temple", bp.y0, base + 2)
	_finish(bp, build)
	return true

func _stilt(x: int, ruined: bool, build: bool) -> bool:
	var w := rng.randi_range(32, 42)
	var tw := w + 2 * YARD + 4
	var x0 := x - tw / 2
	if not _site_ok(x0 + YARD, w + 4, 10, true):
		return false
	var st := _style("marsh", "home")
	var gnd := _ground_range(x0 + YARD, w + 4)
	var lift := rng.randi_range(10, 16)
	var base := gnd.x - 1 - lift
	var up := STOREY + _roof_h(w, st) + 12
	var bp := BP.new(x0, base - up, tw, up + lift + 40)
	bp.ruined = ruined
	var lb := up
	var ox := YARD + 2
	# stilts every few columns down into the mud
	var i := ox
	while i < ox + w:
		var g := ground_row(bp.x0 + i) - bp.y0
		bp.rect(i, lb + 1, i, g + 4, Defs.WOOD, F_ANCHOR)
		i += 6
	bp.rect(ox + w - 1, lb + 1, ox + w - 1, ground_row(bp.x0 + ox + w - 1) - bp.y0 + 4, Defs.WOOD, F_ANCHOR)
	var top := _building(bp, ox, lb, w, 1, st, 3, ruined, "", 0.35)
	var hi := _roof(bp, ox, top, w, st)
	if st["chimney"]:
		_chimney(bp, ox, top, w, st)
		hi -= 10
	if ruined:
		_ruin(bp, ox - 2, ox + w + 1, hi, lb, "marsh")
	_furnish(bp, ox, w, int(st["thick"]), lb, 1, "hut", ruined)
	_claim(x0, tw, "Sunken Hut" if ruined else "Stilt Hut", bp.y0, base + lift + 4)
	_finish(bp, build)
	return true

## Abandoned mine: a headframe at the top, a shaft with plank landings, and drifts propped
## up with timber.
func _mine(x: int, b: String, ruined: bool, build: bool) -> bool:
	var sw := 20
	var depth := rng.randi_range(60, 130)
	var dl := rng.randi_range(40, 80)
	var dr := rng.randi_range(40, 80)
	var tw := sw + dl + dr + 6
	var x0 := x - dl - 3
	if not _site_ok(x - 6, sw + 12, 12) or not _deep_free(x0, tw):
		return false
	deep.append(Vector2i(x0, x0 + tw))
	var g0 := ground_row(x)
	var bp := BP.new(x0, g0 - 26, tw, depth + 56)
	bp.ruined = ruined
	var gl := 26                      # local ground row at the shaft
	var sx := dl + 3                  # shaft left column
	# headframe
	for pc in [sx - 2, sx + sw + 1]:
		bp.rect(pc, gl - 22, pc, gl - 1, Defs.WOOD)
		bp.rect(pc, gl, pc, ground_row(bp.x0 + pc) - bp.y0 + 2, Defs.WOOD, F_FILL | F_ANCHOR)
	bp.rect(sx - 3, gl - 23, sx + sw + 2, gl - 23, Defs.PLANK)
	bp.bg(sx + sw / 2, gl - 22, Defs.TORCH)
	# shaft, lined with planking behind (a load-bearing back wall), which carries the landings
	# where a cave has eaten away the rock beside the shaft
	bp.rect(sx, gl - 1, sx + sw - 1, gl + depth, 0)
	bp.rect_bg(sx, gl + 1, sx + sw - 1, gl + depth - 33, Defs.PLANK)
	_set_in_rock(bp, sx, gl + 1, sx + sw - 1, gl + depth - 33)
	_landings(bp, sx, sx + sw - 1, gl + 22, gl + depth - 6)
	# drifts at the bottom
	var fj := gl + depth
	bp.rect(sx - dl, fj - 40, sx + sw + dr - 1, fj - 1, 0)
	var p := sx - dl + 2
	while p < sx + sw + dr - 2:
		if p < sx - 2 or p > sx + sw + 1:
			# props stand against the back of the drift (you walk past them), holding a cap
			# beam up under the roof
			bp.rect_bg(p, fj - 39, p + 1, fj - 1, Defs.WOOD)
			bp.rect(p - 3, fj - 40, p + 4, fj - 40, Defs.PLANK)
			_set_in_rock(bp, p, fj - 39, p + 1, fj - 1)
			if not ruined and rng.randf() < 0.5:
				bp.bg(p + 3, fj - 24, Defs.TORCH)
				_set_in_rock(bp, p + 3, fj - 24, p + 3, fj - 24)
		p += 16
	# what the miners left behind, and what moved in after
	_chest(bp, sx - dl + 3, fj)
	if rng.randf() < 0.6:
		_chest(bp, sx + sw + dr - 3 - Defs.CHEST_W, fj)
	_guard(bp, sx - dl / 2, fj, "bat")
	_guard(bp, sx + sw + dr / 2, fj, "bat")
	if rng.randf() < 0.5:
		_guard(bp, sx - dl / 2 - 8, fj, "skeleton")
	if ruined:
		# cave-ins and rotten timber
		for j2 in range(gl - 23, fj + 1):
			for i2 in tw:
				var f := bp.getf(i2, j2)
				if (f == Defs.PLANK or f == Defs.WOOD) and rng.randf() < 0.3:
					bp.fg(i2, j2, 0)
		for n in rng.randi_range(1, 3):
			var ci := rng.randi_range(2, tw - 3)
			var rr := rng.randf_range(4.0, 8.0)
			for jj in range(fj - 42, fj + 1):
				for ii in range(ci - 9, ci + 10):
					if bp.ok(ii, jj) and bp.getf(ii, jj) == 0 and Vector2(ii - ci, (jj - (fj - 10)) * 1.5).length() < rr:
						bp.fg(ii, jj, Defs.GRAVEL)
	used.append(Vector2i(x - 6, x + sw + 6))
	sites.append(Vector2(posmod(x - 6, N0), posmod(x - 6, N0) + sw + 12))
	labels.append({"x0": posmod(x0, N0), "w": tw, "ymin": g0 - 28, "ymax": g0 + depth + 4,
		"name": "Collapsed Mine" if ruined else "Abandoned Mine"})
	_finish(bp, build)
	return true

## Catacombs: a small shrine on the surface, a lined stairwell down, and stone corridors
## with tombs, burial rooms, treasure, and the dead who keep it.
func _catacomb(x: int, b: String, ruined: bool, build: bool) -> bool:
	var shrine := 36
	if not _site_ok(x - shrine / 2 - YARD, shrine + 2 * YARD, 8):
		return false
	var st := _style(b, "fort")
	st["roof_kind"] = "flat"
	var m: int = st["wall"]
	var depth := rng.randi_range(70, 120)
	var cl := rng.randi_range(60, 110)
	var cr := rng.randi_range(60, 110)
	var tw := cl + cr + shrine + 50
	var x0 := x - shrine / 2 - cl - 25
	if not _deep_free(x0, tw):
		return false
	deep.append(Vector2i(x0, x0 + tw))
	var g0 := _median_ground(x - shrine / 2, shrine) - 1
	var bp := BP.new(x0, g0 - STOREY - 8, tw, STOREY + depth + 34)
	bp.ruined = ruined
	var lb := STOREY + 8
	var sx := cl + 25
	_yard(bp, sx - YARD, sx + shrine + YARD - 1, lb)
	_foundation(bp, sx, lb, shrine, m)
	var top := _building(bp, sx, lb, shrine, 1, st, 3, ruined, "", 0.0)
	_roof(bp, sx, top, shrine, st)
	# stairwell: lined shaft
	var s0 := sx + 3
	var s1 := sx + shrine - 4
	var fj := lb + depth
	bp.solid(s0 - 2, lb, s1 + 2, fj, m)
	bp.rect(s0, lb, s1, fj - 1, 0)
	# corridors left and right, with a burial room at each end
	var c0 := sx - cl
	var c1 := sx + shrine + cr
	bp.solid(c0 - 2, fj - 42, c1 + 2, fj + 2, m)
	for e0 in [c0, c1 - 54]:
		bp.solid(e0 - 2, fj - 52, e0 + 56, fj + 2, m)
		bp.rect(e0, fj - 50, e0 + 54, fj - 1, 0)
	# open the corridor through the room walls and the stairwell down into it
	bp.rect(c0, fj - 40, c1, fj - 1, 0)
	bp.rect(s0, lb, s1, fj - 1, 0)
	_landings(bp, s0, s1, lb + 20, fj - 40)
	for e0 in [c0, c1 - 54]:
		_chest(bp, e0 + 20, fj, e0 == c0)
		_guard(bp, e0 + 6, fj, "skeleton")
	# wall niches (tombs), torches and the corridor's watchers
	var p := c0 + 58
	var n := 0
	while p < c1 - 58:
		if p < s0 - 3 or p > s1 + 3:
			bp.rect_bg(p, fj - 20, p + 7, fj - 12, Defs.OBSIDIAN)
			if not ruined and rng.randf() < 0.6:
				bp.bg(p + 10, fj - 22, Defs.TORCH)
			n += 1
			if n % 3 == 0:
				_guard(bp, p + 3, fj, "skeleton")
		p += 18
	_guard(bp, (c0 + s0) / 2, fj, "bat")
	if ruined:
		_ruin(bp, c0 - 2, c1 + 2, fj - 52, fj, b, false)
		_ruin(bp, sx, sx + shrine - 1, top - 2, lb, b)
	_claim(x - shrine / 2 - YARD, shrine + 2 * YARD, "Forgotten Catacombs" if ruined else "Catacombs", g0 - 40, g0 + depth + 6)
	labels.append({"x0": posmod(x0, N0), "w": tw, "ymin": g0 + 8, "ymax": g0 + depth + 6, "name": "Forgotten Catacombs" if ruined else "Catacombs"})
	_finish(bp, build)
	return true

## A sealed vault deep underground, full of treasure, with no way in but digging.
func _vault(x: int, build: bool) -> void:
	if cdist(x, spawn_col) < 200 or cdist(x, boss_col) < 260:
		return
	if not _deep_free(x - 30, 60):
		return
	deep.append(Vector2i(x - 30, x + 30))
	var w := 60
	var h := 44
	var g := ground_row(x)
	var y := g + rng.randi_range(140, 260)
	var bp := BP.new(x - w / 2, y, w, h)
	bp.solid(0, 0, w - 1, h - 1, Defs.OBSIDIAN)
	bp.rect(2, 2, w - 3, h - 3, 0)
	bp.rect_bg(2, 2, w - 3, h - 3, Defs.BRICK)
	# the one place treasure is sure: two chests, well apart
	_chest(bp, 6, h - 2, true)
	_chest(bp, w - 6 - Defs.CHEST_W, h - 2, true)
	bp.bg(3, h - 22, Defs.TORCH)
	bp.bg(w - 4, h - 22, Defs.TORCH)
	labels.append({"x0": posmod(x - w / 2, N0), "w": w, "ymin": y, "ymax": y + h, "name": "Sealed Vault"})
	_finish(bp, build)

## name of the structure at a world position, or ""
func label_at(pos: Vector2) -> String:
	var a := fposmod(atan2(pos.y, pos.x), TAU)
	var col := int(a / TAU * N0)
	var row := int(Defs.R_TOP - pos.length())
	for l in labels:
		if posmod(col - int(l["x0"]), N0) < int(l["w"]) and row >= int(l["ymin"]) and row <= int(l["ymax"]):
			return l["name"]
	return ""

# --------------------------------------------------------------- dungeons ---
## A dungeon: a stone gatehouse on the surface with a shaft down to a grid of halls far below.
## The layout is grown, not drawn: rooms sit in a grid of slots, a random spanning tree (with a
## few extra loops) joins them with corridors (side by side) and shafts with landings (one above
## the other), and each room gets a theme. The room farthest from the entrance is a reliquary
## walled in a material the staff can't cut yet (brick or obsidian): the treasure there waits
## for a stronger focus.
const DUNGEONS := 4
const DSW := 112       # slot width: a room up to 96 wide with its walls and a gap
const DSH := 86        # slot height: a room up to 72 tall
const DW := 5          # wall thickness
const DSHAFT := 22     # shaft width
const DCOR := 40       # corridor height

const DUNGEON_NAMES := {
	"forest": ["Overgrown Halls", "Rootbound Crypts"], "marsh": ["Drowned Crypts", "Mire Halls"],
	"desert": ["Tomb of the Sun Kings", "Sandsworn Tomb"], "tundra": ["Frozen Crypts", "Rimeheart Halls"],
	"mountain": ["Deep Halls of Karn", "Stonewarden Halls"], "ashland": ["Cinder Halls", "Emberdeep Crypts"],
	"jungle": ["Vinechoked Halls", "Sunken Ziggurat"], "savanna": ["Goldmane Halls", "Dustwind Crypts"],
	"grove": ["Sporehollow Crypts", "Mycel Halls"],
}
const ROOM_KINDS := ["guard", "hall", "roost", "crypt", "treasure", "pool", "hall", "guard"]

func _dungeon(x: int, build: bool) -> bool:
	if cdist(x, spawn_col) < 280 or cdist(x, boss_col) < 320:
		return false
	var b := biome(x)
	if not DUNGEON_NAMES.has(b):
		return false
	var nc := rng.randi_range(3, 4)
	var nr := rng.randi_range(2, 3)
	var dw := nc * DSW + 2 * DW + 8
	var dx0 := x - dw / 2
	if not _deep_free(dx0, dw):
		return false
	# --- the rooms, one per slot (local columns and rows of the dungeon blueprint) ---
	var rooms := []
	for r in nr:
		var slot_top := 6 + r * DSH
		var fl := slot_top + DSH - DW - 1          # floor row (solid), shared by the whole row
		for c in nc:
			var w := rng.randi_range(66, DSW - 2 * DW - 8)
			var left := DW + 4 + c * DSW + DW + rng.randi_range(0, DSW - 2 * DW - 6 - w)
			var h := rng.randi_range(54, DSH - 2 * DW - 6)
			rooms.append({"r": r, "c": c, "i0": left, "i1": left + w - 1, "top": fl - h, "fl": fl, "on": false, "kind": ""})
	# --- grow a spanning tree from the entrance (a random room on the top row) ---
	var ce := rng.randi_range(0, nc - 1)
	var edges := []
	var want := maxi(3, int(round(nc * nr * rng.randf_range(0.7, 0.9))))
	rooms[ce]["on"] = true
	var on_n := 1
	for guard_k in 400:
		if on_n >= want:
			break
		var a := rng.randi_range(0, rooms.size() - 1)
		if not rooms[a]["on"]:
			continue
		var opts := _dungeon_neighbours(rooms, a, nc, nr)
		if opts.is_empty():
			continue
		var bk: int = opts[rng.randi_range(0, opts.size() - 1)]
		if rooms[bk]["on"]:
			continue
		rooms[bk]["on"] = true
		on_n += 1
		edges.append(Vector2i(a, bk))
	# a few loops, so it isn't all dead ends
	for a2 in rooms.size():
		for bk2 in _dungeon_neighbours(rooms, a2, nc, nr):
			if bk2 > a2 and rooms[a2]["on"] and rooms[bk2]["on"] and not edges.has(Vector2i(a2, bk2)) and not edges.has(Vector2i(bk2, a2)) and rng.randf() < 0.2:
				edges.append(Vector2i(a2, bk2))
	# the reliquary: the room farthest from the entrance (deepest first)
	var dist := _dungeon_dist(rooms, edges, ce)
	var vault := -1
	var best := -1
	for k in rooms.size():
		if rooms[k]["on"] and k != ce:
			var score: int = dist[k] * 10 + int(rooms[k]["r"])
			if score > best:
				best = score
				vault = k
	if vault < 0:
		return false
	# --- where it goes: the gatehouse sits over the entrance room ---
	var entry: Dictionary = rooms[ce]
	var s0 := (int(entry["i0"]) + int(entry["i1"])) / 2 - DSHAFT / 2     # the shaft's left column, local
	var gc := dx0 + s0 + DSHAFT / 2
	var gw := 40
	if not _site_ok(gc - gw / 2 - 2, gw + 4, 14):
		return false
	var base := _median_ground(gc - gw / 2 - 2, gw + 4) - 1
	var by0 := base + rng.randi_range(80, 130)
	var bh := 6 + nr * DSH + 4
	if by0 + bh > Defs.ROWS - 20:
		return false
	for i in range(0, dw, 6):
		if ground_row(dx0 + i) > by0 - 30:
			return false          # a valley would cut into the halls
	deep.append(Vector2i(dx0, dx0 + dw))
	var st := _style(b, "fort")
	st["roof_kind"] = "battle"
	st["frame"] = "course"
	var house_wall: int = st["wall"]
	st["wall"] = Defs.RUNESTONE     # warded: explored through its halls, not dug around
	var seal := Defs.BRICK if rng.randf() < 0.6 else Defs.OBSIDIAN
	var name: String = DUNGEON_NAMES[b][rng.randi_range(0, 1)]
	# --- the halls ---
	var bp := BP.new(dx0, by0, dw, bh)
	var wall: int = st["wall"]
	# 1) shells: each room, corridor and shaft walled in stone (the reliquary in its seal)
	for k in rooms.size():
		var rm: Dictionary = rooms[k]
		if rm["on"]:
			bp.solid(rm["i0"] - DW, rm["top"] - DW, rm["i1"] + DW, rm["fl"] + DW - 1, seal if k == vault else wall)
	var links := []
	for e in edges:
		var ra: Dictionary = rooms[mini(e.x, e.y)]
		var rb: Dictionary = rooms[maxi(e.x, e.y)]
		if ra["r"] == rb["r"]:
			var lo: Dictionary = ra if ra["c"] < rb["c"] else rb
			var hi: Dictionary = rb if ra["c"] < rb["c"] else ra
			if hi["i0"] - DW - 1 >= lo["i1"] + DW + 1:
				bp.solid(lo["i1"] + DW + 1, lo["fl"] - DCOR - DW, hi["i0"] - DW - 1, lo["fl"] + DW - 1, wall)
			links.append({"kind": "corridor", "a": lo, "b": hi, "va": lo == rooms[vault], "vb": hi == rooms[vault]})
		else:
			var up: Dictionary = ra if ra["r"] < rb["r"] else rb
			var dn: Dictionary = rb if ra["r"] < rb["r"] else ra
			var ov0 := maxi(up["i0"], dn["i0"]) + 2
			var ov1 := mini(up["i1"], dn["i1"]) - 2
			var sw := mini(DSHAFT, ov1 - ov0 + 1)
			var si := ov0 + rng.randi_range(0, maxi(0, ov1 - ov0 + 1 - sw))
			bp.solid(si - DW, up["fl"] + DW, si + sw - 1 + DW, dn["top"] - DW - 1, wall)
			links.append({"kind": "shaft", "a": up, "b": dn, "si": si, "sw": sw, "va": up == rooms[vault], "vb": dn == rooms[vault]})
	bp.solid(s0 - DW, 0, s0 + DSHAFT - 1 + DW, int(entry["top"]) - DW - 1, wall)
	# 2) hollow everything out, with the back wall behind
	var back: int = st["back"]
	for k in rooms.size():
		var rm2: Dictionary = rooms[k]
		if rm2["on"]:
			bp.rect(rm2["i0"], rm2["top"], rm2["i1"], rm2["fl"] - 1, 0)
			bp.rect_bg(rm2["i0"], rm2["top"], rm2["i1"], rm2["fl"] - 1, seal if k == vault else back)
	for ln in links:
		var la: Dictionary = ln["a"]
		var lb2: Dictionary = ln["b"]
		if ln["kind"] == "corridor":
			bp.rect(la["i1"] + 1, la["fl"] - DCOR, lb2["i0"] - 1, la["fl"] - 1, 0)
			bp.rect_bg(la["i1"] + 1, la["fl"] - DCOR, lb2["i0"] - 1, la["fl"] - 1, back)
			# the reliquary's doorway is walled up
			if ln["vb"]:
				bp.rect(lb2["i0"] - DW, la["fl"] - DCOR, lb2["i0"] - 1, la["fl"] - 1, seal)
			if ln["va"]:
				bp.rect(la["i1"] + 1, la["fl"] - DCOR, la["i1"] + DW, la["fl"] - 1, seal)
		else:
			var si2: int = ln["si"]
			var sw2: int = ln["sw"]
			bp.rect(si2, la["fl"], si2 + sw2 - 1, lb2["top"] - 1, 0)
			bp.rect_bg(si2, la["fl"], si2 + sw2 - 1, lb2["top"] - 1, back)
			# landings all the way down into the lower room (its back wall holds them up)
			_landings(bp, si2, si2 + sw2 - 1, la["fl"] + DW + 8, lb2["fl"] - 18)
			if ln["vb"]:
				bp.rect(si2, lb2["top"] - DW, si2 + sw2 - 1, lb2["top"] - 1, seal)
			if ln["va"]:
				bp.rect(si2, la["fl"], si2 + sw2 - 1, la["fl"] + DW - 1, seal)
	bp.rect(s0, 0, s0 + DSHAFT - 1, int(entry["top"]) - 1, 0)
	bp.rect_bg(s0, 0, s0 + DSHAFT - 1, int(entry["top"]) - 1, back)
	_landings(bp, s0, s0 + DSHAFT - 1, 10, int(entry["fl"]) - 18)
	# 3) furnish each room by its theme (a room with a shaft down through its floor gets no pool
	# or rubble, which would pour down it)
	var has_down := {}
	for ln2 in links:
		if ln2["kind"] == "shaft":
			has_down[ln2["a"]["r"] * nc + ln2["a"]["c"]] = true
	var kinds := ROOM_KINDS.duplicate()
	var sure_treasure := true
	var ki := rng.randi_range(0, kinds.size() - 1)
	for k in rooms.size():
		var rm3: Dictionary = rooms[k]
		if not rm3["on"]:
			continue
		_back_frame(bp, rm3["i0"], rm3["top"], rm3["i1"], rm3["fl"], 1, st)
		if k == ce:
			rm3["kind"] = "entry"
		elif k == vault:
			rm3["kind"] = "reliquary"
		else:
			rm3["kind"] = kinds[ki % kinds.size()]
			ki += 1
			if rm3["kind"] == "pool" and (b == "desert" or has_down.has(k)):
				rm3["kind"] = "hall"
		rm3["down"] = has_down.has(k)
		sure_treasure = _dungeon_room(bp, rm3, st, b, sure_treasure) and sure_treasure
	# --- check it: every room but the reliquary can be reached from the gatehouse shaft ---
	bp.meta = _dungeon_reach(bp, rooms, vault, s0 + DSHAFT / 2)
	var shot_rm: Dictionary = rooms[ce]
	bp.meta["shot"] = Vector2i(posmod(dx0 + (int(shot_rm["i0"]) + int(shot_rm["i1"])) / 2, N0), by0 + int(shot_rm["fl"]))
	var vr: Dictionary = rooms[vault]
	labels.append({"x0": posmod(dx0 + int(vr["i0"]) - DW, N0), "w": int(vr["i1"]) - int(vr["i0"]) + 1 + 2 * DW,
		"ymin": by0 + int(vr["top"]) - DW, "ymax": by0 + int(vr["fl"]) + DW, "name": "Sealed Reliquary"})
	labels.append({"x0": posmod(dx0, N0), "w": dw, "ymin": by0 - 4, "ymax": by0 + bh, "name": name})
	_finish(bp, build)
	# --- the gatehouse, and the shaft from its floor down to the halls ---
	var gx0 := gc - gw / 2 - YARD - 2
	var gtw := gw + 2 * YARD + 4
	var up2 := STOREY + _roof_h(gw, st) + 12
	var gbp := BP.new(gx0, base - up2, gtw, up2 + (by0 - base) + 3)
	var lb := up2
	var ox := YARD + 2
	_yard(gbp, 0, gtw - 1, lb)
	_foundation(gbp, ox - 1, lb, gw + 2, st["found"])
	var gst := st.duplicate()
	gst["wall"] = house_wall        # the gatehouse itself is ordinary stone
	gst["post"] = house_wall
	var top := _building(gbp, ox, lb, gw, 1, gst, 3, false, "", 0.0)
	_roof(gbp, ox, top, gw, gst)
	var gs0 := dx0 + s0 - gx0
	gbp.solid(gs0 - DW, lb + 1, gs0 + DSHAFT - 1 + DW, gbp.h - 1, wall)
	gbp.rect(gs0, lb, gs0 + DSHAFT - 1, gbp.h - 1, 0)
	gbp.rect_bg(gs0, lb + 1, gs0 + DSHAFT - 1, gbp.h - 1, back)
	_landings(gbp, gs0, gs0 + DSHAFT - 1, lb + 22, gbp.h - 6)
	gbp.bg(ox + 6, lb - 24, Defs.TORCH)
	gbp.bg(ox + gw - 7, lb - 24, Defs.TORCH)
	_claim(gx0, gtw, name, gbp.y0, base + 2)
	_finish(gbp, build)
	return true

## the rooms next to room k that a corridor or shaft could join it to
func _dungeon_neighbours(rooms: Array, k: int, nc: int, nr: int) -> Array:
	var r: int = rooms[k]["r"]
	var c: int = rooms[k]["c"]
	var out := []
	if c > 0:
		out.append(k - 1)
	if c < nc - 1:
		out.append(k + 1)
	for dr in [-1, 1]:
		var r2: int = r + dr
		if r2 < 0 or r2 >= nr:
			continue
		var o: Dictionary = rooms[r2 * nc + c]
		# a shaft needs the two rooms to overlap enough to drop straight down
		if mini(rooms[k]["i1"], o["i1"]) - maxi(rooms[k]["i0"], o["i0"]) >= 20:
			out.append(r2 * nc + c)
	return out

## steps from room `from` to every room along the links (-1: not joined)
func _dungeon_dist(rooms: Array, edges: Array, from: int) -> Array:
	var d := []
	d.resize(rooms.size())
	d.fill(-1)
	d[from] = 0
	var q := [from]
	while not q.is_empty():
		var a: int = q.pop_front()
		for e in edges:
			var o := -1
			if e.x == a:
				o = e.y
			elif e.y == a:
				o = e.x
			if o >= 0 and d[o] < 0:
				d[o] = d[a] + 1
				q.append(o)
	return d

## Furnishes one room by its kind. Returns false once it has placed the sure chest.
func _dungeon_room(bp: BP, rm: Dictionary, st: Dictionary, b: String, sure: bool) -> bool:
	var i0: int = rm["i0"]
	var i1: int = rm["i1"]
	var top: int = rm["top"]
	var fl: int = rm["fl"]
	var mid := (i0 + i1) / 2
	var placed_sure := false
	var torches := true
	match rm["kind"]:
		"entry":
			pass
		"hall":
			# pillars standing against the back wall, with capitals
			var p := i0 + 8
			while p < i1 - 8:
				bp.rect_bg(p, top, p + 2, fl - 1, st["post"] if st["post"] != st["back"] else st.get("course", st["back"]))
				bp.rect_bg(p - 1, top + 2, p + 3, top + 3, st.get("course", st["back"]))
				bp.rect_bg(p - 1, fl - 2, p + 3, fl - 1, st.get("course", st["back"]))
				p += 15
			_guard(bp, mid, fl, "skeleton")
		"guard":
			_guard(bp, i0 + 10, fl, "skeleton")
			_guard(bp, i1 - 10, fl, "skeleton")
		"roost":
			torches = false
			# roots and creepers hanging from the ceiling
			for n in rng.randi_range(5, 9):
				var vc := rng.randi_range(i0, i1)
				for k in rng.randi_range(5, 14):
					bp.bg(vc, top + k, Defs.WOOD if b == "desert" or b == "ashland" else Defs.LEAF, false)
			_guard(bp, i0 + 12, fl - 20, "bat")
			_guard(bp, i1 - 12, fl - 20, "bat")
		"crypt":
			var n2 := i0 + 5
			while n2 + 8 < i1 - 3:
				bp.rect_bg(n2, fl - 20, n2 + 8, fl - 11, Defs.OBSIDIAN)
				bp.rect_bg(n2 + 1, fl - 19, n2 + 7, fl - 12, 0)
				n2 += 15
			_guard(bp, mid, fl, "skeleton")
		"treasure":
			_chest(bp, mid - Defs.CHEST_W / 2, fl, sure)
			placed_sure = sure
			_guard(bp, i0 + 8, fl, "skeleton")
		"pool":
			# a sunken pool in the floor (water; mud in the marsh; lava in the ashlands)
			var liq := Defs.WATER
			if b == "marsh":
				liq = Defs.MUD
			elif b == "ashland":
				liq = Defs.LAVA
			var p0 := mid - (i1 - i0) / 4
			var p1 := mid + (i1 - i0) / 4
			bp.solid(p0 - DW, fl, p1 + DW, fl + 7 + DW, st["wall"])
			bp.rect(p0, fl, p1, fl + 7, 0)
			bp.rect_bg(p0, fl, p1, fl + 7, st["back"])
			bp.rect(p0, fl + 1, p1, fl + 7, liq)
		"reliquary":
			_chest(bp, i0 + 6, fl, true)
			_chest(bp, i1 - 5 - Defs.CHEST_W, fl, true)
			_guard(bp, mid, fl, "skeleton")
	if torches:
		bp.bg(i0 + 3, fl - 24, Defs.TORCH)
		bp.bg(i1 - 3, fl - 24, Defs.TORCH)
	# age: a rubble heap now and then, moss staining the back wall in the wetter biomes
	if rm["kind"] != "reliquary" and rm["kind"] != "pool" and not rm.get("down", false) and rng.randf() < 0.35:
		var mc := rng.randi_range(i0 + 4, i1 - 4)
		var mh := rng.randi_range(3, 6)
		for dc in range(-mh, mh + 1):
			for k2 in int(mh - absi(dc)):
				if bp.getf(mc + dc, fl - 1 - k2) == 0:
					bp.fg(mc + dc, fl - 1 - k2, Defs.GRAVEL)
	if b == "forest" or b == "marsh" or b == "mountain" or b == "jungle" or b == "grove":
		for j in range(top, fl):
			for i in range(i0, i1 + 1):
				if bp.getb(i, j) == st["back"] and sin(i * 0.31 + j * 0.17) + sin(i * 0.13 - j * 0.29) > 1.35:
					bp.bg(i, j, Defs.MOSSBLOCK)
	return not placed_sure

## Flood-fills the open cells from the top of the entrance shaft (column si) and reports how many
## rooms it reaches, and whether it gets into the reliquary (it shouldn't).
func _dungeon_reach(bp: BP, rooms: Array, vault: int, si: int) -> Dictionary:
	var seen := PackedByteArray()
	seen.resize(bp.w * bp.h)
	var stack := [Vector2i(si, 0)]
	while not stack.is_empty():
		var q: Vector2i = stack.pop_back()
		if not bp.ok(q.x, q.y) or seen[q.y * bp.w + q.x] == 1:
			continue
		var f := bp.getf(q.x, q.y)
		if not (f == 0 or f == Defs.SCAFFOLD or Defs.KIND[f] == Defs.K_LIQUID or Defs.KIND[f] == Defs.K_POWDER):
			continue
		seen[q.y * bp.w + q.x] = 1
		stack.append(q + Vector2i(1, 0))
		stack.append(q + Vector2i(-1, 0))
		stack.append(q + Vector2i(0, 1))
		stack.append(q + Vector2i(0, -1))
	var n := 0
	var reached := 0
	var vault_open := false
	for k in rooms.size():
		var rm: Dictionary = rooms[k]
		if not rm["on"]:
			continue
		var c := Vector2i((int(rm["i0"]) + int(rm["i1"])) / 2, int(rm["top"]) + 2)
		var hit := seen[c.y * bp.w + c.x] == 1
		if k == vault:
			vault_open = hit
		else:
			n += 1
			if hit:
				reached += 1
	return {"dungeon": true, "rooms": n, "reached": reached, "vault_open": vault_open}

# ------------------------------------------------------------------ props ---
## Furniture and town details (props.gd) are stamped into the background layer, so they never
## block movement. A prop goes down only where every one of its pixels lands on open space: in
## front of a building's back wall (indoors) or in open air (outdoors), not over a window, a torch
## or another prop. Standing props need ground or floor under their feet.

## the cell a prop pixel at (x, y) of a w-wide prop lands on, mirrored if flipped
static func _prop_px(rows: Array, x: int, y: int, flip: bool) -> String:
	var r: String = rows[y]
	return r[r.length() - 1 - x] if flip else r[x]

func _prop_fits(bp: BP, rows: Array, i0: int, bottom: int, flip: bool, indoors: bool, standing: bool) -> bool:
	var h := rows.size()
	var w: int = rows[0].length()
	var top := bottom - h + 1
	var feet := 0
	var held := 0
	for x in w:
		var lowest := -1
		for y in h:
			if _prop_px(rows, x, y, flip) == ".":
				continue
			lowest = y
			var i := i0 + x
			var j := top + y
			if not bp.ok(i, j):
				return false
			var f := bp.getf(i, j)
			var g := bp.getb(i, j)
			if indoors:
				if f != 0 or g == 0 or g == 255 or g == Defs.TORCH or g == Defs.DECOR or g == Defs.GLASS:
					return false
			else:
				if f == 255:
					if j >= ground_row(bp.x0 + i) - bp.y0:
						return false          # natural ground
				elif f != 0:
					return false
				if g != 255 and g != 0:
					return false
		if standing and lowest == h - 1:
			feet += 1
			var below := bp.getf(i0 + x, bottom + 1)
			var solid_below := (below != 255 and below != 0 and Defs.KIND[below] == Defs.K_SOLID) or \
				(below == 255 and bottom + 1 >= ground_row(bp.x0 + i0 + x) - bp.y0)
			if solid_below:
				held += 1
	return not standing or (feet > 0 and held * 10 >= feet * 7)

func _stamp_prop(bp: BP, rows: Array, i0: int, bottom: int, flip: bool, lit := true, kid := 0) -> void:
	var h := rows.size()
	var top := bottom - h + 1
	for y in h:
		for x in rows[y].length():
			var ch := _prop_px(rows, x, y, flip)
			if ch == ".":
				continue
			if ch == "t":
				if lit:
					bp.fg(i0 + x, top + y, 0)
					bp.bg(i0 + x, top + y, Defs.TORCH)
				else:
					bp.bgv(i0 + x, top + y, Defs.DECOR, Props.CHARS["x"], true, kid)
			else:
				bp.bgv(i0 + x, top + y, Defs.DECOR, Props.CHARS[ch], true, kid)

## Tries to put a prop somewhere in columns [i0, i1] with its feet on row `bottom` (or, for a wall
## prop, its bottom `lift` rows above it). Returns the column it went to, or -1.
func _place_prop(bp: BP, prop: Dictionary, i0: int, i1: int, bottom: int, indoors: bool, tries := 10, lift := 0, lit := true) -> int:
	var rows: Array = prop["rows"]
	var w: int = rows[0].length()
	if i1 - i0 + 1 < w:
		return -1
	var wall: bool = prop.get("wall", false)
	for t in tries:
		var x := rng.randi_range(i0, i1 - w + 1)
		var flip := rng.randf() < 0.5
		var b := bottom if bottom >= 0 else _yard_bottom(bp, x, x + w - 1)
		if not wall and _near_chest(bp, x, x + w - 1, b + 1):
			continue
		if _prop_fits(bp, rows, x, b - lift, flip, indoors, not wall):
			_stamp_prop(bp, rows, x, b - lift, flip, lit, Props.kind_id(String(prop.get("kind", ""))))
			return x
	return -1

## a planned chest stands on floor row fl somewhere in columns [a, b] (props leave it room)
func _near_chest(bp: BP, a: int, b: int, fl: int) -> bool:
	for q in bp.chests:
		if q.y == fl and q.x - 3 <= b and q.x + Defs.CHEST_W + 3 >= a:
			return true
	return false

## What a room holds, by the building's role: [prop, chance] in the order they're tried.
const FURNISH := {
	"home0": [["table", 0.9], ["chair", 0.8], ["chair", 0.5], ["fireplace", 0.5], ["barrel", 0.4], ["plant", 0.5], ["painting", 0.6], ["rug", 0.4]],
	"home1": [["bed", 0.95], ["dresser", 0.6], ["bookshelf", 0.5], ["painting", 0.5], ["plant", 0.4], ["rug", 0.3]],
	"shop0": [["counter", 1.0], ["goods", 0.9], ["goods", 0.6], ["crates", 0.7], ["barrel", 0.6], ["plant", 0.4]],
	"smithy0": [["forge", 0.9], ["anvil", 1.0], ["rack", 0.8], ["barrel", 0.7], ["crates", 0.6]],
	"tavern0": [["counter", 0.9], ["table", 1.0], ["chair", 0.9], ["chair", 0.9], ["table", 0.7], ["chair", 0.7], ["barrel", 0.8], ["barrel", 0.6], ["banner", 0.5]],
	"inn0": [["counter", 0.8], ["table", 0.8], ["chair", 0.7], ["plant", 0.5], ["painting", 0.5]],
	"inn1": [["bed", 1.0], ["bed", 0.7], ["dresser", 0.5], ["painting", 0.4]],
	"tower": [["rack", 0.7], ["table", 0.5], ["chair", 0.4], ["barrel", 0.6], ["crates", 0.5], ["banner", 0.6]],
	"keep": [["banner", 0.9], ["banner", 0.7], ["table", 0.7], ["chair", 0.6], ["bookshelf", 0.6], ["rack", 0.5], ["rug", 0.6], ["painting", 0.4]],
	"hut": [["table", 0.6], ["barrel", 0.6], ["plant", 0.5], ["crate", 0.4], ["cauldron", 0.3]],
	"dwelling": [["rug", 0.9], ["plant", 0.6], ["barrel", 0.4], ["table", 0.4], ["cauldron", 0.2]],
}
const WALL_LIFT := {"painting": 22, "banner": 18, "rack": 0}

## Furnishes a building's rooms (rows `base - k * STOREY`) by its role. Ruins keep fewer things.
func _furnish(bp: BP, ox: int, w: int, th: int, base: int, floors: int, role: String, ruined: bool) -> void:
	for k in floors:
		var fl := base - k * STOREY
		# the kit for this floor: role0 downstairs, role1 upstairs; a shop or smithy is lived in above
		var key := "%s%d" % [role, mini(k, 1)]
		if not FURNISH.has(key):
			key = "home1" if k > 0 and FURNISH.has(role + "0") else (role + "0" if FURNISH.has(role + "0") else role)
		if not FURNISH.has(key):
			continue
		for item in FURNISH[key]:
			var kind: String = item[0]
			if rng.randf() > float(item[1]) * (0.5 if ruined else 1.0):
				continue
			var prop := Props.make(kind, rng)
			if kind == "rug":
				# a rug lies on the floor where nothing else stands
				_place_prop(bp, prop, ox + th + 2, ox + w - th - 3, fl - 1, true, 6)
				continue
			_place_prop(bp, prop, ox + th + 2, ox + w - th - 3, fl - 1, true, 10, WALL_LIFT.get(kind, 0), not ruined)

## Outside a house: a sign by the door (what the place is), hedges and flowers along the walls,
## a lamp post, a fence along the yard.
func _dress_yard(bp: BP, ox: int, w: int, role: String, ruined: bool) -> void:
	var left_end := ox - 2
	var right_start := ox + w + 1
	if role != "home" or rng.randf() < 0.3:
		var board := Props.make("sign", rng, role)
		if rng.randf() < 0.5:
			_place_prop(bp, board, 1, left_end, -1, false, 10)
		else:
			_place_prop(bp, board, right_start, bp.w - 2, -1, false, 10)
	for n in rng.randi_range(1, 3) - (1 if ruined else 0):
		var kind: String = ["hedge", "flowers", "hedge", "hay", "barrel", "crates"][rng.randi_range(0, 3 if role == "home" else 5)]
		var pr := Props.make(kind, rng)
		var left := rng.randf() < 0.5
		var a0 := 1 if left else right_start
		var a1 := left_end if left else bp.w - 2
		_place_prop(bp, pr, a0, a1, -1, false, 8)
	if rng.randf() < 0.45:
		var a2 := 1 if rng.randf() < 0.5 else right_start
		var a3 := left_end if a2 == 1 else bp.w - 2
		_place_prop(bp, Props.make("lamp", rng, not ruined), a2, a3, -1, false, 8)

## the row a prop's feet would stand on in the yard between columns a0 and a1 (the highest ground)
func _yard_bottom(bp: BP, a0: int, a1: int) -> int:
	var best := bp.h - 1
	for i in range(maxi(a0, 0), mini(a1, bp.w - 1) + 1):
		var gr := bp.h - 1
		for j in bp.h:
			var f := bp.getf(i, j)
			if (f != 255 and f != 0 and Defs.KIND[f] != Defs.K_EMPTY) or (f == 255 and j >= ground_row(bp.x0 + i) - bp.y0):
				gr = j
				break
		best = mini(best, gr)
	return best - 1

## The open ground between two houses of a village: a well, a market stall, lamp posts, a fence
## or flower beds. Its own small blueprint (nothing solid), so the gap stays a gap.
func _town_square(x0: int, w: int, ruined: bool, build: bool) -> void:
	var g0 := ground_row(x0 + w / 2)
	var bp := BP.new(x0, g0 - 40, w, 44)
	var kinds := ["well", "stall", "lamp", "flowers", "fence", "hedge"]
	var main: String = kinds[rng.randi_range(0, 1)] if w >= 30 else kinds[rng.randi_range(2, 5)]
	if ruined and main == "stall":
		main = "well"
	var placed := _place_prop(bp, Props.make(main, rng, null if main != "fence" else w - 6), 2, w - 3, -1, false, 12)
	var lamps := 0
	if placed >= 0 or rng.randf() < 0.5:
		for side in [[1, 8], [w - 9, w - 2]]:
			if rng.randf() < 0.6 and _place_prop(bp, Props.make("lamp", rng, not ruined), side[0], side[1], -1, false, 6) >= 0:
				lamps += 1
	used.append(Vector2i(x0, x0 + w))
	sites.append(Vector2(posmod(x0, N0), posmod(x0, N0) + w))
	if placed >= 0 or lamps > 0:
		_finish(bp, build)
