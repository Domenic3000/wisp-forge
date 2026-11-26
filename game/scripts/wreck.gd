## A derelict: a wisp ship dead in space, grown from parts by its seed (user, 23 Nov: "things to find
## out there ... derelict wrecks to fly into and loot"). It extends asteroid.gd, so space.gd streams it in
## with its sector, lets it drift and turn, lets you dig its hull for salvage (Hull Plating, ingots, star
## iron from its engine) and keeps it as you left it, exactly as it does a rock.
##
## `Wreck.make_wreck(seed, first)` grows it: a hull of plating, long and tapering to a prow, a stern
## engine room (a star-iron nozzle, a glowing wisp core, copper pipes), a hold of one or two decks cut
## into rooms by bulkheads with doorways, a bridge cabin raised over the hull with a cracked glass front;
## timber panelling and ribs on the back layer, a few lamps still glowing. Then the damage: breaches torn
## through the hull (the first always opens the upper hold from above, wide enough to drift in), sometimes
## the prow broken off, scorching round the tears. Last its caches: crates on the floors of the rooms
## (`caches`: hold, engine, bridge), opened with F from inside (space.gd `wreck_interact`); what they hold
## is decided as you open them (space.gd `_loot`). Cache cells are `guarded`: mining leaves them be.
##
## `scrap(seed, r)` is a torn piece of plating drifting near a wreck: an asteroid of kind "scrap".
## A wreck saves its name, fate, caches and back layer with the rock's own save (`save` / `from_save`).
extends "res://scripts/asteroid.gd"

const NAME_A := ["Silent", "Last", "Pale", "Drowned", "Hollow", "Burning", "Wandering", "Broken", "Lost",
	"Quiet", "Ashen", "Starless", "Gilded", "Faithful", "Distant", "Sleeping"]
const NAME_B := ["Lantern", "Heron", "Promise", "Tide", "Wisp", "Crown", "Errand", "Comet", "Vigil",
	"Harvest", "Ember", "Psalm", "Moth", "Covenant", "Kestrel", "Meridian"]
const FATES := ["Her engines burned out far from any star.", "Something tore her open from below.",
	"Pirates stripped her hold and left her drifting.", "A storm belt's lightning gutted her bridge.",
	"Her crew left in a hurry: the hatches stand open.", "An asteroid caught her amidships.",
	"Her log ends mid-sentence.", "She was running from something. Her guns are cold."]
const CRATE_W := 9
const CRATE_H := 6

var wname := ""
var fate := ""
var caches := []          # [{"i", "j" (top-left cell), "w", "h", "kind": "hold"/"engine"/"bridge", "open"}]
var first := false        # (the wreck near home every journey finds first: its bridge always holds a part)
var visited := false      # (you've been aboard: its name was told)
var _bg_dirty := true
var meta := {}            # (how it was laid out: the tests print it)
var board_at := Vector2i(-1, -1)   # (the first breach's middle at the hull's top: where you board it, your ship above)

## its name, from its seed (the map names it before you've been near)
static func name_of(sd: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	return "the %s %s" % [NAME_A[rng.randi_range(0, NAME_A.size() - 1)], NAME_B[rng.randi_range(0, NAME_B.size() - 1)]]

## (user, 25 Nov: "derelict ships and outposts and so on should be redesigned so that you press a button to dock
## and go inside an instanced area so we can make them larger and more intricate"): `in_halls` grows the wreck you
## board (space.gd `dock_station` with a wreck): about twice as long, three decks, more rooms and caches; the one
## drifting out in space is its shell, with no caches (you board it with F).
static func make_wreck(sd: int, is_first := false, in_halls := false) -> RefCounted:
	var wk = load("res://scripts/wreck.gd").new()
	wk.halls = in_halls
	wk._build(sd, is_first)
	return wk

var halls := false        # (the wreck you board, an instance; else its shell out in space)

## a torn piece of hull plating drifting near a wreck (an ordinary rock of kind "scrap")
static func scrap(sd: int, r: float) -> RefCounted:
	var a = load("res://scripts/asteroid.gd").new()
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	a.seed_ = sd
	a.kind = "scrap"
	var ww := int(r * 2.0) + 4
	var hh := int(r * rng.randf_range(0.5, 0.9)) + 4
	a.setup(ww, hh)
	var noise := FastNoiseLite.new()
	noise.seed = sd
	noise.frequency = 0.18
	for j in hh:
		for i in ww:
			var e: float = noise.get_noise_2d(i, j) * 3.0
			if i < 2.0 + e or i > ww - 3.0 + e or j < 2.0 + e * 0.5 or j > hh - 3.0 + e * 0.5:
				continue
			var m := Defs.HULL
			if rng.randf() < 0.06:
				m = Defs.COPPERBAR
			elif j == 2 or rng.randf() < 0.03:
				m = Defs.TIMBER
			a.put(i, j, m, (0 if i % 10 == 0 else (1 if (j / 4) % 2 == 0 else 2)) if m == Defs.HULL else -1)
	a.rebuild()
	a.rad = maxf(3.0, sqrt(a.mass / PI))
	a.ang = rng.randf() * TAU
	a.omega = rng.randf_range(-0.004, 0.004)
	return a

func _build(sd: int, is_first: bool) -> void:
	seed_ = sd
	kind = "wreck"
	first = is_first
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	wname = name_of(sd)
	rng.randi()
	rng.randi()
	fate = FATES[rng.randi_range(0, FATES.size() - 1)]
	var L := rng.randi_range(128, 168)            # hull length
	var hh := rng.randi_range(52, 70)             # hull height
	var cab := rng.randi_range(18, 22)            # the bridge cabin over it
	if halls:
		L = rng.randi_range(280, 340)
		hh = rng.randi_range(100, 110)
		cab = rng.randi_range(24, 28)
	var x0 := 4
	var top := cab + 4
	var bot := top + hh
	setup(L + 10, bot + 6)
	var noise := FastNoiseLite.new()
	noise.seed = sd
	noise.frequency = 0.09
	# ---- the hull: plating in panels, rivets at their corners; a blunt stern, a prow sweeping down
	var tops := PackedInt32Array()
	var bots := PackedInt32Array()
	tops.resize(w)
	bots.resize(w)
	for i in w:
		tops[i] = bot
		bots[i] = bot
	for i in range(x0, x0 + L):
		var x := float(i - x0) / float(L)
		var t0 := top
		var b0 := bot
		if x > 0.7:
			var f := (x - 0.7) / 0.3
			t0 = top + int(f * f * float(hh) * 0.55)
			b0 = bot - int(f * float(hh) * 0.2)
		if x < 0.03:
			t0 += 4
			b0 -= 4
		tops[i] = t0
		bots[i] = b0
		for j in range(t0, b0):
			_plate(i, j)
	# ---- the rooms: an engine room at the stern, the hold in one or two decks, bulkheads with doors
	var xs := x0 + 32                              # the hold's stern end (the engine room behind it)
	var xe := x0 + int(float(L) * 0.7)             # its bow end
	var in_top := top + 4
	var floor_y := bot - 4                         # the lower deck's floor (first plating row under it)
	var two := floor_y - in_top >= 56              # (two decks only where each is 27 high: room over a crate)
	var deck := (in_top + floor_y) / 2 if two else -1
	# (the boarded wreck: three decks, each about 30 high)
	var nd := 3 if halls and floor_y - in_top >= 90 else (2 if two else 1)
	var decks := []
	for dk in range(1, nd):
		decks.append(in_top + (floor_y - in_top) * dk / nd)
	if not decks.is_empty():
		deck = int(decks[0])
	for j in range(in_top, floor_y):
		for i in range(xs, xe):
			_hollow(i, j)
	for dy in decks:
		for i in range(xs, xe):
			put(i, int(dy), Defs.PLANK)
			put(i, int(dy) + 1, Defs.PLANK)
	# the engine room, through a door in the stern bulkhead
	var e_top := top + 8
	var e_bot := floor_y - 2
	for j in range(e_top, e_bot):
		for i in range(x0 + 6, xs - 2):
			_hollow(i, j)
	for j in range(e_bot - 24, e_bot):
		for i in range(xs - 2, xs):
			_hollow(i, j)
	# its machinery: a star-iron nozzle through the stern, a wisp core, copper pipes along the roof
	var ny := (e_top + e_bot) / 2
	for j in range(ny - 6, ny + 6):
		for i in range(x0, x0 + 6):
			put(i, j, Defs.STARIRON)
	for j in range(ny - 4, ny + 4):
		for i in range(x0 + 6, x0 + 11):
			put(i, j, Defs.WISPBAR if (i + j) % 3 != 0 else Defs.COPPERBAR)
	for i in range(x0 + 6, xs - 2):
		put(i, e_top, Defs.COPPERBAR)
		if i % 5 == 0:
			put(i, e_top + 1, Defs.COPPERBAR)
	# bulkheads across the hold, a doorway at each deck's floor
	var nb := rng.randi_range(1, 2) if not halls else rng.randi_range(3, 5)
	var walls := []
	for b in nb:
		var bx := xs + int(float(xe - xs) * float(b + 1) / float(nb + 1)) + rng.randi_range(-6, 6)
		walls.append(bx)
		for j in range(in_top, floor_y):
			put(bx, j, Defs.HULL, 1)
			put(bx + 1, j, Defs.HULL, 2)
		for dfl in (decks + [floor_y]):
			for j in range(int(dfl) - 24, int(dfl)):
				_hollow(bx, j)
				_hollow(bx + 1, j)
	# the hatch between the decks: in the widest room, clear of its bulkheads, wide enough for you to
	# drift through whichever way the wreck lies
	var ed := [xs] + walls + [xe]
	ed.sort()
	for dy2 in decks:
		# (each deck's hatch in a room of its own when it can: the widest first, then the next)
		var r0 := 0
		for rk in range(ed.size() - 1):
			if int(ed[rk + 1]) - int(ed[rk]) > int(ed[r0 + 1]) - int(ed[r0]):
				r0 = rk
		if decks.size() > 1 and int(dy2) != int(decks[0]):
			r0 = (r0 + 1 + rng.randi_range(0, maxi(0, ed.size() - 3))) % (ed.size() - 1)
		var hx := rng.randi_range(int(ed[r0]) + 5, maxi(int(ed[r0]) + 5, int(ed[r0 + 1]) - 25))
		for i in range(hx, mini(hx + 20, int(ed[r0 + 1]) - 1)):
			_hollow(i, int(dy2))
			_hollow(i, int(dy2) + 1)
	# ---- the bridge: a cabin raised over the hull near the bow, open down into the upper deck
	var xb0 := x0 + int(float(L) * 0.5)
	var xb1 := mini(x0 + int(float(L) * 0.72), xe + 6)
	var cab_top := top - cab
	for i in range(xb0, xb1):
		for j in range(cab_top, top):
			_plate(i, j)
		tops[i] = cab_top
	for i in range(xb0 + 3, xb1 - 3):
		for j in range(cab_top + 3, in_top + 1):
			_hollow(i, j)
	# its front: glass, slanting back, cracked
	for j in range(cab_top, top):
		var gx := xb1 - 4 + (j - cab_top) / 4
		for i in range(gx - 3, mini(gx + 1, w)):
			if rng.randf() < 0.75:
				put(i, j, Defs.GLASS)
			else:
				put(i, j, 0)
	# ---- the back layer: timber panelling, darker ribs, and a few lamps still lit
	for j in h:
		for i in w:
			var k := j * w + i
			if cells[k] == 0 and i > x0 and i < x0 + L - 2 and j > tops[i] and j < bots[i]:
				bg[k] = Defs.TIMBER if (i - xs) % 12 == 0 else Defs.PLANK
				bgv[k] = 0 if (i - xs) % 12 == 0 else ((j / 3 + i / 9) % 3)
	for i in range(xs + 6, xe - 4, rng.randi_range(18, 26)):
		var lit: bool = rng.randf() < 0.7
		var lamp_rows := [in_top]
		for dy3 in decks:
			lamp_rows.append(int(dy3) + 2)
		for lj in lamp_rows:
			if at(i, int(lj)) == 0 and at(i, int(lj) - 1) != 0 and at(i + 1, int(lj) - 1) != 0:
				put(i, int(lj), Defs.CRYSTAL if lit else Defs.COPPERBAR)
				put(i + 1, int(lj), Defs.CRYSTAL if lit else Defs.COPPERBAR)
	# ---- the damage: breaches, sometimes a lost prow, scorching
	if rng.randf() < 0.35:
		var cut := x0 + int(float(L) * rng.randf_range(0.82, 0.9))
		for j in h:
			var cx := cut + int(noise.get_noise_2d(cut, j * 3) * 8.0)
			for i in range(cx, w):
				_take_cell(i, j)
	# (the first opens the upper hold from above, wide enough to drift in: never under the bridge's
	# cabin, whose roof would close it over)
	var lo := xs + 14
	var hi := xb0 - 16
	if hi < lo:
		lo = xb1 + 16
		hi = xe - 14
	if hi < lo:
		lo = xs + 14
		hi = xe - 14
	var bx0 := rng.randi_range(lo, maxi(lo, hi))
	_breach(Vector2(bx0, top + 1), rng.randf_range(12.0, 14.0), noise)
	board_at = Vector2i(bx0, top)
	# (a tear or two more: at most one through the keel, smaller, so the floors stay mostly whole)
	var keel := false
	for b2 in rng.randi_range(1, 2):
		var side := rng.randi_range(0, 2)
		if side == 0 and keel:
			side = 1
		var bi := rng.randi_range(xs + 6, xe - 6)
		if side == 1 and bi >= xb0 - 4 and bi < xb1 + 4:
			bi = rng.randi_range(xs + 6, maxi(xs + 6, xb0 - 8))
		var bc := Vector2(bi, bots[bi] - 2) if side == 0 else (Vector2(bi, tops[bi] + 1) if side == 1 else Vector2(x0 + rng.randi_range(2, 5), rng.randi_range(top + 6, bot - 6)))
		keel = keel or side == 0
		_breach(bc, rng.randf_range(6.0, 9.0) if side == 0 else rng.randf_range(6.0, 11.0), noise)
	# ---- the caches: one under the bridge first (the best of them), one in the engine room, then a
	# crate in each room on its floor (and on the upper deck)
	var bfl: int = int(decks[0]) if not decks.is_empty() else floor_y
	if not _crate_near((xb0 + xb1) / 2 - CRATE_W / 2, bfl, "bridge", xs + 2, xe - 2):
		_crate_near((xb0 + xb1) / 2 - CRATE_W / 2, floor_y, "bridge", xs + 2, xe - 2)
	_crate_near(x0 + 16, e_bot, "engine", x0 + 12, xs - 3)
	var edges := [xs] + walls + [xe]
	for r in range(edges.size() - 1):
		var a0: int = int(edges[r]) + 4
		var a1: int = int(edges[r + 1]) - 4 - CRATE_W
		if a1 > a0:
			_crate_near(rng.randi_range(a0, a1), floor_y, "hold", a0, a1 + CRATE_W)
			for dy4 in decks:
				if rng.randf() < 0.6:
					_crate_near(rng.randi_range(a0, a1), int(dy4), "hold", a0, a1 + CRATE_W)
	meta = {"decks": nd, "xs": xs, "xe": xe, "walls": walls, "bridge": [xb0, xb1], "floor": floor_y, "deck": deck, "in_top": in_top}
	rebuild()
	rad = maxf(3.0, sqrt(mass / PI))
	ang = rng.randf() * TAU
	omega = rng.randf_range(-0.00025, 0.00025)
	_bg_dirty = true
	dirty = true

## a cell of hull plating, in panels with rivets
func _plate(i: int, j: int) -> void:
	# (courses of plates four rows high, alternating shade; a dark seam every ten columns, a rivet
	# either side of it)
	var v := 1 if (j / 4) % 2 == 0 else 2
	if i % 10 == 0:
		v = 0
	elif (i % 10 == 1 or i % 10 == 9) and j % 4 == 1:
		v = 3
	put(i, j, Defs.HULL, v)

func _hollow(i: int, j: int) -> void:
	if i >= 0 and j >= 0 and i < w and j < h:
		cells[j * w + i] = 0

func _take_cell(i: int, j: int) -> void:
	if i >= 0 and j >= 0 and i < w and j < h:
		cells[j * w + i] = 0
		bg[j * w + i] = 0

## a hole torn through the hull: a ragged round of cells gone (the back layer torn less), scorched round
func _breach(c: Vector2, r: float, noise: FastNoiseLite) -> void:
	for j in range(int(c.y - r - 4.0), int(c.y + r + 5.0)):
		for i in range(int(c.x - r - 4.0), int(c.x + r + 5.0)):
			if i < 0 or j < 0 or i >= w or j >= h:
				continue
			var d := Vector2(i, j).distance_to(c)
			var e: float = r + noise.get_noise_2d(i * 2.0, j * 2.0) * 3.5
			var k := j * w + i
			if d < e:
				cells[k] = 0
				if d < e * 0.6:
					bg[k] = 0
			elif d < e + 3.0 and cells[k] == Defs.HULL:
				vars[k] = 0
				if noise.get_noise_2d(i * 7.0, j * 7.0) > 0.35:
					cells[k] = Defs.COAL

## a crate standing on the floor row `floor_y` (its bottom just over it) at column x: only where the
## floor under it is whole and the space for it is open
func _crate(x: int, floor_y: int, knd: String) -> bool:
	if not halls and kind == "wreck":
		return true                        # (the shell out in space: nothing in it; its caches are in the wreck you board)
	var j0 := floor_y - CRATE_H
	for i in range(x, x + CRATE_W):
		if at(i, floor_y) == 0:
			return false
		for j in range(j0, floor_y):
			if at(i, j) != 0:
				return false
	for j in range(j0, floor_y):
		for i in range(x, x + CRATE_W):
			var edge := i == x or i == x + CRATE_W - 1 or j == j0 or j == floor_y - 1
			put(i, j, Defs.COPPERBAR if edge else Defs.PLANK, 0 if edge else ((i + j) % 3))
	put(x + CRATE_W / 2, j0, Defs.WISP)
	caches.append({"i": x, "j": j0, "w": CRATE_W, "h": CRATE_H, "kind": knd, "open": false})
	return true

## a crate as near column x as it fits, between lo and hi (its right edge under hi)
func _crate_near(x: int, floor_y: int, knd: String, lo: int, hi: int) -> bool:
	for d in range(0, 80, 3):
		for sgn in [1, -1]:
			var cx: int = x + d * sgn
			if cx >= lo and cx + CRATE_W <= hi and _crate(cx, floor_y, knd):
				return true
	return false

# ------------------------------------------------------------------ caches ---

## the world point at a cache's middle
func cache_pos(c: Dictionary) -> Vector2:
	return to_world(Vector2(float(c["i"]) + float(c["w"]) * 0.5, float(c["j"]) + float(c["h"]) * 0.5) - com)

## (a closed cache's cells are left alone by mining and blasts)
func guarded(k: int) -> bool:
	var i := k % w
	var j := k / w
	for c in caches:
		if not c["open"] and i >= int(c["i"]) and j >= int(c["j"]) and i < int(c["i"]) + int(c["w"]) and j < int(c["j"]) + int(c["h"]):
			return true
	return false

## open a cache: its lid comes away and its lock goes dark
func open_cache(c: Dictionary) -> void:
	c["open"] = true
	touched = true
	var i0 := int(c["i"])
	var j0 := int(c["j"])
	for i in range(i0 + 1, i0 + int(c["w"]) - 1):
		cells[j0 * w + i] = 0
		if cells[(j0 + 1) * w + i] == Defs.PLANK:
			cells[(j0 + 1) * w + i] = 0
	dirty = true

# ------------------------------------------------------------------- looks ---

func texture() -> ImageTexture:
	var t := super.texture()
	if _bg_dirty or bg_tex == null:
		var bimg := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for j in h:
			for i in w:
				var bm := bg[j * w + i]
				if bm == 0:
					continue
				bimg.set_pixel(i, j, Color.hex((Defs.PAL[bm * 4 + (bgv[j * w + i] & 3)] << 8) | 0xff).darkened(0.55))
		if bg_tex == null or bg_tex.get_width() != w or bg_tex.get_height() != h:
			bg_tex = ImageTexture.create_from_image(bimg)
		else:
			bg_tex.update(bimg)
		_bg_dirty = false
	return t

func back_texture() -> ImageTexture:
	texture()
	return bg_tex

# ------------------------------------------------------------------ saving ---

func save() -> Dictionary:
	var d := super.save()
	d["wreck"] = {"name": wname, "fate": fate, "caches": caches, "first": first, "visited": visited, "halls": halls,
		"board": [board_at.x, board_at.y],
		"bg": Marshalls.raw_to_base64(bg), "bgv": Marshalls.raw_to_base64(bgv)}
	return d

static func from_save(d: Dictionary) -> RefCounted:
	var a = load("res://scripts/asteroid.gd").from_save(d)
	if a == null:
		return null
	var wk = load("res://scripts/wreck.gd").new()
	wk.seed_ = a.seed_
	wk.kind = "wreck"
	wk.setup(a.w, a.h)
	wk.cells = a.cells
	wk.vars = a.vars
	wk.rebuild()
	wk.pos = a.pos
	wk.ang = a.ang
	wk.omega = a.omega
	wk.vel = a.vel
	wk.rad = a.rad
	var x: Dictionary = d.get("wreck", {})
	wk.wname = String(x.get("name", "a wreck"))
	wk.fate = String(x.get("fate", ""))
	wk.first = bool(x.get("first", false))
	wk.halls = bool(x.get("halls", false))
	var ba = x.get("board", [-1, -1])
	wk.board_at = Vector2i(int(ba[0]), int(ba[1])) if ba is Array and ba.size() == 2 else Vector2i(-1, -1)
	wk.visited = bool(x.get("visited", false))
	wk.caches = []
	for c in x.get("caches", []):
		wk.caches.append({"i": int(c["i"]), "j": int(c["j"]), "w": int(c["w"]), "h": int(c["h"]), "kind": String(c["kind"]), "open": bool(c["open"])})
	var bb: PackedByteArray = Marshalls.base64_to_raw(String(x.get("bg", "")))
	var bv: PackedByteArray = Marshalls.base64_to_raw(String(x.get("bgv", "")))
	if bb.size() == wk.w * wk.h and bv.size() == wk.w * wk.h:
		wk.bg = bb
		wk.bgv = bv
	return wk
