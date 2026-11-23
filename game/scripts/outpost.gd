## A trading outpost: a station of real cells grown from parts by its seed (user, 23 Nov: outposts with
## traders, so salvage, coins and pirates' loot have somewhere to go). It extends wreck.gd, so space.gd
## streams it with its sector, draws it with its back layer and collides you and the skiff with it; but
## nothing of it can be dug or blasted (`guarded` is always true) and it never drifts.
##
## `Outpost.make_outpost(seed)` grows it: a HANGAR open on one side, big enough to fly the skiff into
## (landing lights along its floor, hazard stripes at its mouth, ribs on its back wall), a TRADING HALL
## through a doorway beside it (a counter with the trader behind it, shelves of crates, lamps, a strip of
## windows to the stars), a domed HUB over both with a band of lit windows, an antenna with a beacon,
## SOLAR WINGS of glowing wisp panels either side, and a keel spire with a red light under it. The trader
## (`trader()`: a folk_art figure with an apron, a name from folk_art) keeps the outpost's shop
## (Defs.SHOPS["outpost"], through towns.gd's shop and ui.gd's shop panel; space.gd `open_trade`).
extends "res://scripts/wreck.gd"

const OP_A := ["Kestrel", "Lantern", "Halcyon", "Meridian", "Tinker's", "Wayfarer's", "Cinder", "Harbor",
	"Lodestar", "Driftwood", "Gilded", "Quiet", "Copper", "Starwatch"]
const OP_B := ["Post", "Station", "Haven", "Rest", "Landing", "Exchange", "Waystation", "Market"]
const W := 232
const H := 132
## the hangar's inside (body cells): x0, y0, x1, y1 (exclusive); the hall's; where the trader stands
const HANGAR := Rect2i(14, 54, 88, 52)
const HALL := Rect2i(106, 68, 60, 38)
const KEEPER := Vector2(157.5, 106.0)   # (the trader's feet)
const COUNTER := Rect2i(140, 96, 11, 10)

var keeper_tex: ImageTexture
var _trader = null

## the trader behind the counter: what towns.gd's shop and ui.gd's panel need of a keeper
class Trader:
	var role := "outpost"
	var name := ""
	var town := {}
	var fseed := 0
	var pos := Vector2.ZERO
	var facing := -1

static func outpost_name(sd: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd ^ 0x7057
	return "%s %s" % [OP_A[rng.randi_range(0, OP_A.size() - 1)], OP_B[rng.randi_range(0, OP_B.size() - 1)]]

static func make_outpost(sd: int) -> RefCounted:
	var op = load("res://scripts/outpost.gd").new()
	op._build_outpost(sd)
	return op

func _build_outpost(sd: int) -> void:
	seed_ = sd
	kind = "outpost"
	wname = outpost_name(sd)
	fate = ""
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	setup(W, H)
	var hx0 := HANGAR.position.x
	var hy0 := HANGAR.position.y
	var hx1 := HANGAR.end.x
	var hy1 := HANGAR.end.y
	# ---- the hangar: plating round an open mouth on the left, ribs on its back wall
	_box_walls(hx0 - 4, hy0 - 4, hx1 + 4, hy1 + 4, 4)
	for j in range(hy0, hy1):
		for i in range(hx0 - 4, hx0):
			cells[j * w + i] = 0                       # (the mouth)
	for j2 in range(hy0, hy1):
		for i2 in range(hx0, hx1):
			# (a dark back wall, ribbed: it reads as the inside of a bay, not a block of plating)
			var rib := (i2 - hx0) % 16 == 0 or (i2 - hx0) % 16 == 1
			bg[j2 * w + i2] = Defs.HULL if rib else Defs.COAL
			bgv[j2 * w + i2] = 2 if rib else (0 if (j2 / 6) % 2 == 0 else 1)
	# hazard stripes at the mouth's lips, landing lights along the floor, clamps on it
	for i3 in range(hx0 - 4, hx0 + 6):
		for j3 in [hy0 - 4, hy0 - 3, hy1 + 2, hy1 + 3]:
			put(i3, int(j3), Defs.COAL if ((i3 + int(j3)) / 3) % 2 == 0 else Defs.SUNSTONE, 0)
	for i4 in range(hx0 + 4, hx1 - 2, 8):
		put(i4, hy1, Defs.CRYSTAL, 0)
		put(i4, hy0 - 1, Defs.CRYSTAL, 0)
	for cx in [hx0 + 24, hx1 - 24]:
		for i5 in range(int(cx) - 3, int(cx) + 3):
			put(i5, hy1 - 1, Defs.COPPERBAR, 2)
	# ---- the trading hall beside it, through a doorway in the hangar's back wall
	var ax0 := HALL.position.x
	var ay0 := HALL.position.y
	var ax1 := HALL.end.x
	var ay1 := HALL.end.y
	_box_walls(ax0 - 4, ay0 - 4, ax1 + 4, ay1 + 4, 4)
	for j6 in range(ay0, ay1):
		for i6 in range(ax0 - 4, ax0):
			if j6 >= ay1 - 26:
				cells[j6 * w + i6] = 0                 # (the doorway, 26 high)
	for j7 in range(ay0, ay1):
		for i7 in range(ax0 - 4, ax1):
			if cells[j7 * w + i7] == 0:
				bg[j7 * w + i7] = Defs.PLANK if (j7 - ay0) % 9 != 0 else Defs.TIMBER
				bgv[j7 * w + i7] = (i7 / 6 + j7 / 3) % 3
	# windows to the stars along its roof, lamps under it
	for i8 in range(ax0 + 6, ax1 - 6):
		if (i8 - ax0) % 10 < 7:
			for j8 in range(ay0 - 3, ay0 - 1):
				put(i8, j8, Defs.GLASS, 0)
	for i9 in range(ax0 + 8, ax1 - 4, 14):
		put(i9, ay0, Defs.CRYSTAL, 0)
		put(i9 + 1, ay0, Defs.CRYSTAL, 0)
	# the counter, and shelves of crates behind the trader (back layer)
	for j10 in range(COUNTER.position.y, COUNTER.end.y):
		for i10 in range(COUNTER.position.x, COUNTER.end.x):
			var top := j10 == COUNTER.position.y
			put(i10, j10, Defs.COPPERBAR if top else Defs.PLANK, 2 if top else (i10 + j10) % 3)
	for sh in [ay0 + 10, ay0 + 22]:
		for i11 in range(ax1 - 16, ax1):
			bg[int(sh) * w + i11] = Defs.TIMBER
			bgv[int(sh) * w + i11] = 0
		for cb in range(ax1 - 15, ax1 - 1, 5):
			var cm: int = [Defs.COPPERBAR, Defs.WISPBAR, Defs.HULL, Defs.CRYSTAL][rng.randi_range(0, 3)]
			for j12 in range(int(sh) - 3, int(sh)):
				for i12 in range(cb, cb + 3):
					bg[j12 * w + i12] = cm
					bgv[j12 * w + i12] = rng.randi_range(0, 3)
	# ---- the hub: a dome over both, a band of lit windows round it
	var dc := Vector2(104.0, 52.0)
	for j13 in range(18, 52):
		for i13 in range(46, 164):
			var e := pow((float(i13) - dc.x) / 58.0, 2.0) + pow((float(j13) - dc.y) / 34.0, 2.0)
			if e <= 1.0 and cells[j13 * w + i13] == 0 and bg[j13 * w + i13] == 0:
				var band := j13 >= 34 and j13 <= 37 and i13 % 6 < 4
				put(i13, j13, Defs.WISPBAR if band else Defs.HULL, 0 if band else (1 if (j13 / 4) % 2 == 0 else 2))
	# (plating between the dome and the hall's roof, so they're one block)
	for j20 in range(48, 64):
		for i20 in range(100, 170):
			if cells[j20 * w + i20] == 0:
				_plate(i20, j20)
	# the antenna and its beacon
	for j14 in range(4, 19):
		put(104, j14, Defs.TIMBER, 0)
		if j14 % 5 == 0:
			put(103, j14, Defs.COPPERBAR, 0)
			put(105, j14, Defs.COPPERBAR, 0)
	for j15 in range(1, 4):
		for i15 in range(103, 106):
			put(i15, j15, Defs.EMBER, 1)
	# ---- solar wings: an arm each side with glowing wisp panels over and under it
	for side in [-1, 1]:
		var a0: int = 54 if side < 0 else 154
		var a1: int = 2 if side < 0 else W - 2
		var i16: int = a0
		while i16 != a1:
			put(i16, 40, Defs.HULL, 0)
			put(i16, 41, Defs.HULL, 2)
			var k: int = absi(i16 - a0)
			if k > 4 and k % 11 < 8:
				for j16 in range(30, 39):
					put(i16, j16, Defs.WISPBAR if (j16 - 30) % 3 != 2 else Defs.COPPERBAR, 0)
				for j17 in range(43, 48):
					put(i16, j17, Defs.WISPBAR if (j17 - 43) % 3 != 2 else Defs.COPPERBAR, 0)
			i16 += side
	# ---- the keel spire under the floor, a red light at its tip
	var kx := 104
	for j18 in range(hy1 + 4, H - 4):
		var half := maxi(1, int(round(22.0 * (1.0 - float(j18 - hy1 - 4) / float(H - 8 - hy1)))))
		for i18 in range(kx - half, kx + half):
			put(i18, j18, Defs.HULL, 1 if (j18 / 4) % 2 == 0 else 2)
	for j19 in range(H - 4, H - 1):
		put(kx - 1, j19, Defs.EMBER, 0)
		put(kx, j19, Defs.EMBER, 0)
	rebuild()
	rad = maxf(3.0, sqrt(mass / PI))
	ang = 0.0
	omega = 0.0
	meta = {"hangar": HANGAR, "hall": HALL}
	_bg_dirty = true
	dirty = true

## walls of plating `t` thick round a box (x0, y0)..(x1, y1) (exclusive), courses and rivets
func _box_walls(x0: int, y0: int, x1: int, y1: int, t: int) -> void:
	for j in range(y0, y1):
		for i in range(x0, x1):
			if i < x0 + t or i >= x1 - t or j < y0 + t or j >= y1 - t:
				_plate(i, j)

## nothing of an outpost is dug, blasted or chipped
func guarded(_k: int) -> bool:
	return true

## the trader: a figure grown from the outpost's seed, behind the counter
func trader():
	if _trader == null:
		_trader = Trader.new()
		_trader.fseed = seed_ ^ 0x51ED
		_trader.name = load("res://scripts/folk_art.gd").name_for(_trader.fseed)
		_trader.town = {"name": wname, "seed": seed_}
	_trader.pos = keeper_world()
	return _trader

## where the trader's feet are, in the world
func keeper_world() -> Vector2:
	return to_world(KEEPER - com)

## the picture of the trader (made once)
func keeper_texture() -> ImageTexture:
	if keeper_tex == null:
		var fr: Dictionary = load("res://scripts/folk_art.gd").frames(seed_ ^ 0x51ED, "shop")
		keeper_tex = ImageTexture.create_from_image(fr["stand"])
	return keeper_tex

## is a world point inside the hangar (the skiff docked there)?
func in_hangar(p: Vector2) -> bool:
	var b := to_body(p) + com
	return Rect2(HANGAR).grow(2.0).has_point(b)
