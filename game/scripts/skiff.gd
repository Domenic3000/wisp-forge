## The Wisp Skiff: a small ship for two, a pixel body (pixel_body.gd) grown from parts.
##
## Parts, each a small function so other ships can reuse them: a planked hull with a keel that
## rises to the bow (`_hull`), a trim stripe along the gunwale (`_trim`), a cabin under a glass
## canopy (`_canopy`: a timber frame, a glass shell, open room inside with a glass back pane), a
## wisp-ore engine at the stern (`_engine`), a tail fin (`_fin`). The seed varies the proportions.
## Two seats on the cabin floor (pilot forward). The cabin is the body's room (pixel_body.gd): it can
## be built in.
##
## Flying (`fly`): the pilot steers with the movement keys (up and down too) or by holding cast
## toward the cursor (`steer`). In the air the skiff eases to the speed you steer for and, hands
## off, to a hover (just above the ground it settles onto it, softly); its engine holds it up. The
## hull stays level with the ground below, tilting into climbs and dives on a spring, and turns
## round when you steer the other way (`look` eases through the turn for the picture). Nobody at the
## controls: it falls. In space it keeps its speed (thrust adds to it) and the nearest planet pulls.
## It collides with the world by its outline (`collide`, through main's collision grid).
##
## Damage (user, 23 Nov: pirates, and "hull damage and repair for the skiff"): what hits it (a pirate's
## bolt, a storm belt's lightning, a crash into rock at speed) carves cells out of its hull (`damage`).
## `hull_f` is how much of the hull as forged (`design`) is left, `engine_f` how much of its wisp
## engine (its thrust goes with it). Below `HULL_FLOOR` the hull holds by its wisp-binding and the hits
## go through to the riders. Mending (`mend`, main `_mend_skiff`: hold R by it or aboard) knits the
## cells forged back, from what's left outward.
extends "res://scripts/pixel_body.gd"

const CRUISE := 7.0             # top speed in the air (cells a tick)
const CRUISE_HIGH := 16.0       # above the atmosphere
const ACCEL := 0.32             # how quickly it reaches the speed you steer for (a tick)
const BRAKE := 0.2              # hands off: how quickly it slows to a hover
const SPACE_THRUST := 0.3
const MAX_SPEED := 40.0
const TILT := 0.42              # the most it tilts into a climb or a dive (radians)
const SEATS := 4                # (the party aboard: inside the ship, not drawn; pilot first)
const MAX_SEATS := 8
const MAX_W := 200              # the biggest hull you can grow it to (cells)
const MAX_H := 110

var design_seed := 0       # (the shape of this skiff)
var seat_cells: Array = []      # [Vector2i] the cell each seat's feet rest on, pilot first
var riders: Array = []          # [mage or null] per seat
var thrusting := false
var grounded := false
var ground_t := 0               # ticks resting on something
var centre := Vector2.ZERO      # the centre of the planet it flies over (space.gd: the nearest one)
var look := 1.0                 # which way it's drawn facing: eases from one side to the other in a turn
var clear_below := 99.0         # air under the keel (cells, up to 24; `advance` measures it)
var power := 1.0                # its engine (1.5 with the Star-Iron Engine): thrust and top speed in space
const HULL_FLOOR := 0.25        # below this much hull, hits go through to the riders
var design := PackedByteArray() # the hull as forged (material per cell): what mending puts back
var design_v := PackedByteArray()
var design_bg := PackedByteArray() # (its back layer as forged: the cabin's glass pane, given nothing back for)
var hull0 := 1                  # cells of the hull as forged
var engine0 := 1                # (its engine's wisp cells as forged)
var hull_f := 1.0               # how much of the hull is left (0..1)
var engine_f := 1.0             # how much of its engine (thrust goes with it)
var bump := 0.0                 # the hardest knock into something since `advance` began (speed into it)
var bump_at := Vector2.ZERO     # (where: the middle of what touched)
var designed := false           # its hull has been built on (user, 23 Nov: "Design your own hull"): thrust from its engines
static var _ratio0 := -1.0      # (a skiff as forged: its engine cells to its mass, what `drive` measures against)

## Ship classes (user, 25 Nov: "maybe we have prefab ships instead that you can get recipes for different ships";
## chose classes from recipes, each with stats, its look grown from parts by its seed; no building on it, no seats
## to sit in: you're inside). speed: thrust and cruise; armour: a hit carves less of it (radius / sqrt(armour));
## cargo: crates its hold carries; guns: bolts the Wisp Cannon fires at once.
const CLASSES := {
	"skiff": {"name": "Wisp Skiff", "speed": 1.0, "armour": 1.0, "cargo": 3, "guns": 1,
		"desc": "A small ship round a Core Drive: a planked hull under a glass canopy. Quick enough, carries a little."},
	"cutter": {"name": "Wisp Cutter", "speed": 1.35, "armour": 0.8, "cargo": 2, "guns": 1,
		"desc": "A long, slim hull on swept wings: the fastest ship there is, lightly built, room for two crates."},
	"hauler": {"name": "Wisp Hauler", "speed": 0.75, "armour": 1.3, "cargo": 12, "guns": 0,
		"desc": "A deep-bellied freighter with cargo pods slung under it: slow and sturdy, it carries twelve crates."},
	"corvette": {"name": "Wisp Corvette", "speed": 1.1, "armour": 1.7, "cargo": 5, "guns": 2,
		"desc": "A plated warship with a turret: it shrugs off hits and its cannon fires two bolts at once."},
}
var klass := "skiff"
const RIG := 1                  # (the ships' look: 1 = sails, 26 Nov; a ship saved with less is grown again on load)

func cls() -> Dictionary:
	return CLASSES.get(klass, CLASSES["skiff"])

static func make(sd: int, k := "skiff"):
	var s = load("res://scripts/skiff.gd").new()
	s.design_seed = sd
	s.klass = k if CLASSES.has(k) else "skiff"
	s._design()
	return s

## A new ship's keel (user, 24 Nov: "Forge a keel, then build"): a planked keel rising to a bow, a little
## wisp engine at the stern, the helm amidships and the door into its pocket dimension by it. The ship
## builder (shipyard.gd) lays the rest.
static func make_keel(sd: int):
	var s = load("res://scripts/skiff.gd").new()
	s.design_seed = sd
	s._keel()
	return s

func _keel() -> void:
	var deck := 26
	setup(48, deck + 6)
	for i in range(5, 41):
		var bow := i >= 37
		var depth := 2 if bow else 3
		for j in range(deck, deck + depth + (0 if i > 8 else -1)):
			put(i, j, Defs.WOOD if j == deck + depth - 1 else Defs.PLANK, (j / 3 + i / 9) % 3)
	for k in 4:
		for j2 in range(deck - 1 - k, deck + 1):
			put(41 + k, j2, Defs.PLANK, 1)              # (the bow rising to a point, joined along the deck row)
	for j3 in range(deck - 3, deck + 2):
		for i3 in range(1, 5):
			put(i3, j3, Defs.WISP, (i3 + j3) % 4)        # (the engine at the stern)
	seat_cells = [Vector2i(24, deck - 1)]
	riders = []
	riders.resize(1)
	door_cell = Vector2i(14, deck)
	rebuild()
	design = cells.duplicate()
	design_v = vars.duplicate()
	design_bg = bg.duplicate()
	designed = true
	_count_design()
	_recount()
	_seat_marks()

# --------------------------------------------------- the door to the pocket ---
## (user, 24 Nov: "have the inside of the ship be like a pocket dimension that you can enter"): a hull cell
## marked as its door (pocket.gd: F by it steps inside). A ship from before has it under the helm.
var door_cell := Vector2i(-1, -1)

func door() -> Vector2i:
	if door_cell.x >= 0 and door_cell.y >= 0 and door_cell.x < w and door_cell.y < h:
		return door_cell
	if not seat_cells.is_empty():
		return (seat_cells[0] as Vector2i) + Vector2i(0, 1)
	return Vector2i(w / 2, h / 2)

## a ship from before the pocket gets its door: the lowest cell of its stern end (you walk up behind it)
func ensure_door() -> void:
	if door_cell.x >= 0:
		return
	for i in w:
		for j in range(h - 1, -1, -1):
			if at(i, j) != 0:
				door_cell = Vector2i(i, j)
				return

## where you stand to go in at the door (in the world): just above its cell
func door_world() -> Vector2:
	var d := door()
	return cell_world(d.x, d.y) - axis_y() * 9.0

## the cells the helm stands on: never cut away, and every other cell must join them (`prune_loose`)
func keep_cells() -> Array:
	var out := []
	if seat_cells.is_empty():
		return out
	var c: Vector2i = seat_cells[0]
	for di in range(-1, 2):
		out.append(Vector2i(c.x + di, c.y + 1))
	return out

## Cuts away whatever no longer joins the helm's floor (a piece cut loose falls away from the ship).
## Returns material -> how many cells went.
func prune_loose() -> Dictionary:
	var got := {}
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	for kc in keep_cells():
		var c: Vector2i = kc
		if c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and cells[c.y * w + c.x] != 0:
			stack.append(c.y * w + c.x)
			seen[c.y * w + c.x] = 1
	if stack.is_empty():
		return got
	while not stack.is_empty():
		var k: int = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var i := k % w
		var j := k / w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = i + (d as Vector2i).x
			var nj: int = j + (d as Vector2i).y
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var nk := nj * w + ni
			if seen[nk] == 0 and cells[nk] != 0:
				seen[nk] = 1
				stack.append(nk)
	for k2 in cells.size():
		if cells[k2] != 0 and seen[k2] == 0:
			var m := int(cells[k2])
			got[m] = int(got.get(m, 0)) + 1
			cells[k2] = 0
			made[k2] = 0
			design[k2] = 0
	return got

## how many cells the hull has as built (the quest counts it)
func hull_count() -> int:
	var n := 0
	for k in design.size():
		if design[k] != 0:
			n += 1
	return n

func _design() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = design_seed
	var length := 52 + rng.randi_range(0, 8)
	var deck := 27 + rng.randi_range(0, 2)          # the deck's row; the canopy rises above it (room for a hat)
	var depth := 9 + rng.randi_range(0, 3)          # hull depth below the deck
	var main_m := Defs.PLANK
	var band_m := Defs.WOOD
	var trim_m := Defs.COPPER
	match klass:
		"cutter":
			length = 66 + rng.randi_range(0, 8)
			deck = 22 + rng.randi_range(0, 2)
			depth = 6 + rng.randi_range(0, 2)
		"hauler":
			length = 74 + rng.randi_range(0, 8)
			deck = 26 + rng.randi_range(0, 2)
			depth = 13 + rng.randi_range(0, 2)
		"corvette":
			length = 72 + rng.randi_range(0, 8)
			deck = 28 + rng.randi_range(0, 2)
			depth = 12 + rng.randi_range(0, 2)
			main_m = Defs.HULL
			band_m = Defs.HULL
			trim_m = Defs.WISPBAR
	var extra := 12 if klass == "hauler" else (6 if klass == "cutter" else 0)
	setup(length + 4, deck + depth + 2 + extra)
	_hull(length, deck, depth, rng, main_m, band_m)
	_trim(length, deck, trim_m)
	_engine(deck, depth, 2 if klass == "hauler" else 1)
	match klass:
		"cutter":
			_wing(length, deck, depth, rng)
			_fin(deck, rng, 4)
		"hauler":
			_pods(length, deck, depth, rng)
			_fin(deck, rng)
		"corvette":
			_turret(int(length * 0.3), deck, rng)
			_fin(deck, rng)
		_:
			_fin(deck, rng)
	# (sails, not a glass bubble: you're inside the ship now, never drawn; user, 26 Nov: "You still have the bubble
	# where the player goes. Can we just have sails since the player is not gonna show up anymore")
	if main_m == Defs.HULL:
		_plates()
	_sails(length, deck, rng)
	# (seats kept only for the riders' places: inside the ship, never drawn; forward, by the helm)
	var hx := int(float(length) * 0.8)
	seat_cells = [Vector2i(hx, deck - 1), Vector2i(hx - 2, deck - 1), Vector2i(hx + 2, deck - 1), Vector2i(hx - 4, deck - 1)]
	riders = []
	riders.resize(SEATS)
	rebuild()
	# (the hull as forged: what mending puts back)
	design = cells.duplicate()
	design_v = vars.duplicate()
	design_bg = bg.duplicate()
	hull0 = 0
	engine0 = 0
	for k in design.size():
		if design[k] != 0:
			hull0 += 1
			if design[k] == Defs.WISP:
				engine0 += 1
	hull0 = maxi(hull0, 1)
	engine0 = maxi(engine0, 1)
	_recount()

## the hull: planks from the deck down to a keel that rises toward the bow and the stern
func _hull(length: int, deck: int, depth: int, rng: RandomNumberGenerator, main_m := Defs.PLANK, band_m := Defs.WOOD) -> void:
	var bow_rise := 0.55 + rng.randf() * 0.2
	for i in length:
		var t := float(i) / float(length - 1)         # 0 stern .. 1 bow
		var keel := depth * (1.0 - pow(maxf(0.0, (t - 0.55) / 0.45), 1.6) * bow_rise - pow(maxf(0.0, (0.12 - t) / 0.12), 2.0) * 0.5)
		for j in range(deck, deck + int(round(keel)) + 1):
			put(i + 2, j, main_m if (j - deck) % 4 != 3 else band_m)
	# the bow comes up to a point above the deck
	for k in 5:
		for j2 in range(deck - k, deck):
			put(length + 1 - k, j2, main_m)

## a stripe of copper along the gunwale, and the keel's own dark timber
func _trim(length: int, deck: int, trim_m := Defs.COPPER) -> void:
	for i in range(2, length + 2):
		if at(i, deck) != 0:
			put(i, deck, trim_m)
	for i2 in range(2, length + 2):
		for j in range(h - 1, -1, -1):
			if at(i2, j) != 0:
				put(i2, j, Defs.WOOD)
				break

## a cabin over the cockpit: a timber frame, a glass shell, and the room inside left open (its back
## a pane of glass), so the riders sit in it and it can be built in
## (plating's look: panels a few cells across with dark seams between, a light top edge on each; not random specks)
func _plates() -> void:
	for j in h:
		for i in w:
			var k := j * w + i
			if cells[k] != Defs.HULL:
				continue
			var seam: bool = j % 5 == 4 or (i + (j / 5) * 4) % 9 == 0
			vars[k] = 2 if seam else (3 if j % 5 == 0 else (1 if (i / 9 + j / 5) % 2 == 0 else 0))

func _canopy(cx: int, deck: int, rx: float, ry: float, rng: RandomNumberGenerator, frame_m := Defs.WOOD) -> void:
	var lean := rng.randf_range(-0.15, 0.25)          # (the dome leans back a little)
	for j in range(deck - int(ry), deck):
		for i in range(cx - int(rx) - 4, cx + int(rx) + 5):
			var up_by := float(deck - j)
			var shift := up_by / float(ry) * lean * rx
			if _ellipse(float(i - cx) + shift, up_by, rx, ry, 0.0) > 1.0:
				continue
			if _ellipse(float(i - cx) + shift, up_by, rx, ry, 1.5) > 1.0:
				put(i, j, frame_m)                         # the frame
			elif _ellipse(float(i - cx) + shift, up_by, rx, ry, 3.0) > 1.0:
				put(i, j, Defs.GLASS if up_by > 2.5 else frame_m)   # the shell (timber at its foot)
			else:
				cells[j * w + i] = 0
				bg[j * w + i] = Defs.GLASS                 # the room inside: a glass back pane
				bgv[j * w + i] = randi() & 3

## Sails by class, grown from parts: masts (timber, or star iron on a plated hull) with a yard, square sails
## bellied forward with seams and shading, a jib on a stay down to the bow, a fore-and-aft sail on a boom for the
## Cutter, a wisp sigil on the Skiff's mainsail, a glowing pennant at each masthead.
##   skiff: one mast, a square sail of white canvas with the sigil, and a jib
##   cutter: one tall mast, a long fore-and-aft sail swept aft, and a jib
##   hauler: two masts of tan canvas, square sails
##   corvette: two star-iron masts, square sails of red war-canvas
func _sails(length: int, deck: int, rng: RandomNumberGenerator) -> void:
	var cloth := Defs.SNOW
	var mast_m := Defs.TIMBER
	var masts := [int(float(length) * (0.5 + rng.randf_range(0.0, 0.06)))]
	match klass:
		"cutter":
			masts = [int(float(length) * 0.6)]
		"hauler":
			cloth = Defs.SAND
			masts = [int(float(length) * 0.36), int(float(length) * 0.64)]
		"corvette":
			cloth = Defs.TILE
			mast_m = Defs.STARIRON
			masts = [int(float(length) * 0.46), int(float(length) * 0.8)]
	var bow := length + 1
	for mk in masts.size():
		var m0: int = masts[mk]
		var top := 1 + (5 if mk > 0 and klass == "hauler" else 0) + (4 if mk == 1 and klass == "corvette" else 0)
		for j in range(top, deck):
			put(m0, j, mast_m, 0)
			put(m0 + 1, j, mast_m, 1)
		# a pennant flying aft from the masthead (it glows)
		for pk in 6:
			for pj in range(-(1 if pk < 3 else 0), (1 if pk < 3 else 0) + 1):
				put(m0 - 1 - pk, top + 1 + pj, Defs.WISPBAR, 1 if pk % 2 == 0 else 3)
		if klass == "cutter":
			_fore_aft(m0, top, deck, cloth, rng)
		else:
			var sw := 16 + rng.randi_range(0, 4) + (4 if mk == 0 and masts.size() == 1 else 0)
			if klass == "hauler" or klass == "corvette":
				sw = 18 + rng.randi_range(0, 3) - mk * 2
			_square(m0, top + 3, deck - 8, sw, cloth, mast_m, mk == 0 and klass == "skiff")     # (its foot clear of crates on deck)
		# a jib on a stay from the foremost masthead down to the bow
		if mk == masts.size() - 1 and klass != "corvette" and klass != "hauler":
			_jib(m0 + 2, top + 2, bow - 3, deck - 2, cloth, deck - 8)

## a square sail hung from a yard at row y0 down to y1, `sw` wide round the mast at m0, bellied toward the bow
func _square(m0: int, y0: int, y1: int, sw: int, cloth: int, yard_m: int, sigil: bool) -> void:
	for i in range(m0 - sw / 2 - 1, m0 + sw / 2 + 3):
		put(i, y0, yard_m, 2)                           # the yard
	var mid := m0 + 1
	for j in range(y0 + 1, y1):
		var f := float(j - y0) / float(maxi(1, y1 - y0))
		var belly := int(round(sin(f * PI) * 3.0))
		var l := m0 - sw / 2 + belly
		var r := m0 + sw / 2 + 1 + belly
		for i2 in range(l, r + 1):
			if i2 == m0 or i2 == m0 + 1:
				continue
			# (lit where it bellies out toward the light, shaded at its edges and foot; a seam every five rows)
			var edge: bool = i2 <= l or i2 >= r or j >= y1 - 1
			var v := 0
			if (j - y0) % 5 == 0:
				v = 1
			elif edge:
				v = 3
			elif absi(i2 - mid - belly) < sw / 4 and f > 0.2 and f < 0.8:
				v = 2
			put(i2, j, cloth, v)
	if sigil:
		# the wisp's sigil: a small glowing diamond in the middle of the sail
		var sy := (y0 + y1) / 2
		var sx := mid + 3
		for dj in range(-3, 4):
			for di in range(-3, 4):
				var dd := absi(di) + absi(dj)
				if dd == 3 or (dd == 0):
					put(sx + di, sy + dj, Defs.WISP, 3 if dd == 0 else 1)

## a fore-and-aft sail (the Cutter's): from the masthead down to a boom along the deck, swept aft, its back edge curved
func _fore_aft(m0: int, top: int, deck: int, cloth: int, rng: RandomNumberGenerator) -> void:
	var foot := deck - 8
	var reach := 22 + rng.randi_range(0, 6)
	for i in range(m0 - reach - 2, m0):
		put(i, foot + 1, Defs.TIMBER, 2)               # the boom
	for j in range(top + 2, foot + 1):
		var f := float(j - (top + 2)) / float(maxi(1, foot - top - 2))
		var back := int(round(float(reach) * pow(f, 0.8)))
		for i2 in range(m0 - back, m0):
			var v := 0
			if i2 <= m0 - back + 1:
				v = 3
			elif (j - top) % 5 == 0:
				v = 1
			elif i2 > m0 - back / 2:
				v = 2
			put(i2, j, cloth, v)

## a jib: the stay from (x0, y0) at the masthead down to the bow at (x1, y1), and a triangle of sail under it
func _jib(x0: int, y0: int, x1: int, y1: int, cloth: int, foot: int) -> void:
	var dx := maxi(1, x1 - x0)
	var dy := maxi(1, y1 - y0)
	var px := x0
	var py := y0
	for k in dx + dy + 1:
		put(px, py, Defs.TIMBER, 3)                    # (stepped, so the stay stays in one piece)
		var t := float(px - x0 + 1) / float(dx)
		if float(py - y0) / float(dy) < t and py < y1:
			py += 1
		elif px < x1:
			px += 1
		else:
			py += 1
		if px >= x1 and py >= y1:
			break
	for j in range(y0 + 3, mini(y1 - 1, foot)):
		var reach := int(float(j - y0) / float(dy) * float(dx)) - 1
		for i in range(x0, x0 + reach):
			put(i, j, cloth, 3 if i >= x0 + reach - 1 else (1 if (j - y0) % 5 == 0 else 0))

## (how far out a point is in an ellipse shrunk by `inset` cells: 1 on its edge)
func _ellipse(x: float, y: float, rx: float, ry: float, inset: float) -> float:
	var ax := maxf(rx - inset, 1.0)
	var ay := maxf(ry - inset, 1.0)
	return (x * x) / (ax * ax) + (y * y) / (ay * ay)

## the wisp-ore engine at the stern, glowing where it pushes
func _engine(deck: int, depth: int, n := 1) -> void:
	for j in range(deck - 2, deck + depth - 3):
		for i in range(0, 4):
			put(i, j, Defs.WISP)
	if n > 1:
		# (a second engine below the first, for a heavy hull)
		for j2 in range(deck + depth - 3, mini(h - 1, deck + depth + 3)):
			for i2 in range(1, 5):
				put(i2, j2, Defs.WISP)

## a fin at the stern
func _fin(deck: int, rng: RandomNumberGenerator, more := 0) -> void:
	var ht := 7 + rng.randi_range(0, 4) + more
	for k in ht:
		for i in range(4, 4 + maxi(1, 6 - k / 2)):
			put(i + k / 3, deck - 1 - k, Defs.WOOD)

## (a Cutter's) a swept wing under the hull from amidships aft, timber framed with a glass-thin trailing edge
func _wing(length: int, deck: int, depth: int, rng: RandomNumberGenerator) -> void:
	# (seen from the side: a thin blade swept back from under the hull, its tip trailing aft and a little down)
	var root := int(length * 0.6)
	var span := 22 + rng.randi_range(0, 6)
	var y0 := deck + depth
	for q in span:
		var t := float(q) / float(span)
		var x := root - q
		var y := y0 + int(round(t * t * 5.0))
		var thick := 3 if t < 0.5 else (2 if t < 0.85 else 1)
		var from := (deck + depth - 4) if q < 5 else y      # (its root: up into the hull, so it holds)
		for dj in range(from, y + thick):
			put(x, dj, Defs.WOOD if dj == y + thick - 1 else Defs.PLANK)
	for k in 3:
		put(root - span - k, y0 + 5, Defs.COPPER)      # (a copper tip)

## (a Hauler's) cargo pods slung under the hull: timber crates in a plank frame, held by a strut each
func _pods(length: int, deck: int, depth: int, rng: RandomNumberGenerator) -> void:
	var n := 3 + rng.randi_range(0, 1)
	var pw := int((length - 24) / n) - 3
	for p in n:
		var x0 := 10 + p * (pw + 3)
		var y0 := deck + depth + 2
		for j in range(y0, mini(h, y0 + 8)):
			for i in range(x0, x0 + pw):
				var edge: bool = j == y0 or j == mini(h, y0 + 8) - 1 or i == x0 or i == x0 + pw - 1
				put(i, j, Defs.PLANK if edge else Defs.WOOD)
		# (the strut from the hull's underside, wherever that is over this pod)
		var sx := x0 + pw / 2
		var top := deck
		while top < y0 and at(sx, top + 1) != 0:
			top += 1
		for j2 in range(top, y0):
			put(sx, j2, Defs.WOOD)
			put(sx + 1, j2, Defs.WOOD)

## (a Corvette's) a turret on the deck: a plated dome and a barrel to the bow
func _turret(tx: int, deck: int, rng: RandomNumberGenerator) -> void:
	var r := 5 + rng.randi_range(0, 1)
	for j in range(deck - r, deck):
		for i in range(tx - r - 1, tx + r + 2):
			if Vector2(float(i - tx), float(j - deck) * 1.3).length() <= float(r) + 0.5:
				put(i, j, Defs.HULL)
	for i2 in range(tx, tx + r + 7):
		put(i2, deck - r + 2, Defs.STARIRON)

# ------------------------------------------------------------- riders ---

func seat_of(m) -> int:
	return riders.find(m)

func pilot():
	return riders[0]

## where a seat's rider stands (their body's centre), in the world
func seat_world(k: int, body_h: float) -> Vector2:
	var sc: Vector2i = seat_cells[k]
	var feet := Vector2(sc.x + 0.5, sc.y + 1.0) - com
	return to_world(feet - Vector2(0, body_h * 0.5))

func board(m) -> bool:
	for k in riders.size():
		if riders[k] == null:
			riders[k] = m
			return true
	return false

func leave(m) -> void:
	var k := riders.find(m)
	if k >= 0:
		riders[k] = null
		# (with no pilot, the next rider takes the controls)
		if k == 0:
			for k2 in range(1, riders.size()):
				if riders[k2] != null:
					riders[0] = riders[k2]
					riders[k2] = null
					break

func aboard_all(ps: Array) -> bool:
	for m in ps:
		if not m.dead and riders.find(m) < 0:
			return false
	return true

# ------------------------------------------------------------- flying ---

## The pilot's wish as a direction in the world (length up to 1): the movement keys (left, right, up,
## down over the planet below) and, holding cast, toward the cursor.
func steer(inp) -> Vector2:
	var up := (pos - centre).normalized()
	var right := Vector2(up.y, -up.x)
	var s := right * float(inp.move) + up * ((1.0 if inp.jump else 0.0) - (1.0 if inp.down else 0.0))
	if inp.cast:
		var d: Vector2 = inp.aim - pos
		if d.length() > 4.0:
			s += d.normalized()
	return s.limit_length(1.0)

## One tick of flight (speeds and turning; `advance` moves it). `want`: the pilot's wish (`steer`),
## `piloted`: someone is at the controls, `g`: the pull here (toward `centre`, per tick), `in_space`:
## no air (it keeps its speed), `cruise`: its top speed in the air here, `drag`: the air's, per tick.
func fly(want: Vector2, piloted: bool, g: float, in_space: bool, cruise: float, drag: float) -> void:
	thrusting = false
	var up := (pos - centre).normalized()      # (centre: the planet it flies over; out in space the nearest)
	var right := Vector2(up.y, -up.x)          # the planet's "right" here (its "up" turned a quarter clockwise)
	var steering := piloted and want.length() > 0.05
	# turn round when steered the other way (the picture eases through it: `look`)
	if steering and want.dot(right) * float(facing) < -0.25:
		facing = -facing
	if not piloted and in_space:
		# nobody at the controls out in space: its wisp engine holds it where it was left (user, 23 Nov: "when
		# i got out to mine the asteroid my wisp skiff floated away"), easing out what speed it had
		vel *= 0.93
		if vel.length() < 0.02:
			vel = Vector2.ZERO
	elif not piloted:
		# nobody at the controls: it falls, and drifts
		if grounded and vel.length() < 0.5:
			vel = Vector2.ZERO
		else:
			vel -= up * g
			vel *= drag
	elif in_space:
		if steering:
			vel += want * SPACE_THRUST * power * thrust()
			thrusting = true
		vel -= up * g
		vel *= drag
	elif grounded and not steering and vel.length() < 0.6:
		vel = Vector2.ZERO                     # resting on its keel
	else:
		# the engine holds it up: it eases to the speed you steer for, or to a hover
		var target := want * cruise * thrust()
		if not steering and clear_below < 10.0:
			target = -up * 1.2                 # (hands off just above the ground: it settles onto it)
		var down := -target.dot(up)
		if down > 0.0 and clear_below < 16.0:
			# coming down close to the ground: gently
			target += up * (down - minf(down, lerpf(1.2, cruise, clear_below / 16.0)))
		vel += (target - vel).limit_length(ACCEL if steering else BRAKE)
		# (faster than it can fly here, coming in from above: the air takes the extra off quickly)
		if vel.length() > cruise:
			vel = vel.normalized() * maxf(cruise, vel.length() * 0.93)
		thrusting = steering
	if vel.length() > MAX_SPEED * power:
		vel = vel.normalized() * MAX_SPEED * power
	# the hull: level with the ground below, tilted into a climb or a dive, on a spring
	var tilt := 0.0
	if not (grounded and vel.length() < 0.6):
		tilt = clampf(vel.dot(up) * 0.07, -TILT, TILT)
	var nd := (right * float(facing) + up * tilt).normalized()
	omega += angle_difference(ang, (nd * float(facing)).angle()) * 0.05
	omega *= 0.78
	ang += omega
	look = move_toward(look, float(facing), TURN_STEP)

## Turning round (user, 27 Nov: the old flip narrowed it to its edge, "it looks like a piece of paper ... maybe we
## can use the pixel identity somehow"): the hull is redrawn column by column, a line of wisp light sweeping from
## its stern to its new bow, the columns behind the line already facing the new way (overlay `_draw_skiff`).
const TURN_STEP := 0.12         # (`look` a tick: about 17 ticks for a whole turn)
## how far through a turn it is: 0 just turned (drawn as before), 1 done
func sweep_u() -> float:
	return clampf((look * float(facing) + 1.0) * 0.5, 0.0, 1.0)

## where the sweep line is, along the body's x (from the centre of mass, the new bow +): from the far end of
## either picture to the other's, so both are covered
func sweep_s() -> float:
	var l0 := minf(-com.x, com.x - float(w))
	var l1 := maxf(float(w) - com.x, com.x)
	return lerpf(l0, l1, sweep_u())

## the hull's cells in the sweep line's column (either picture's), for its light and its sparks: [j]
func sweep_rows() -> PackedInt32Array:
	var out := PackedInt32Array()
	var s := sweep_s()
	var i_new := int(floor(s + com.x))
	var i_old := int(floor(com.x - s))
	for j in h:
		var a := i_new >= 0 and i_new < w and cells[j * w + i_new] != 0
		var b := i_old >= 0 and i_old < w and cells[j * w + i_old] != 0
		if a or b:
			out.append(j)
	return out

## Move by this tick's velocity, in steps small enough not to pass through the ground, colliding
## at each (no `solid`: out in space, or away from any collision grid); then how much air is under
## the keel.
func advance(solid: Callable) -> void:
	bump = 0.0
	if not solid.is_valid():
		pos += vel
		grounded = false
		clear_below = 99.0
		return
	var n := clampi(int(ceil(vel.length() / 2.0)), 1, 24)
	var was_grounded := false
	for k in n:
		pos += vel / float(n)
		collide(solid)
		was_grounded = was_grounded or grounded
	grounded = was_grounded
	var up := (pos - centre).normalized()
	var kp := to_world(keel)
	clear_below = 24.0
	for d in range(1, 25):
		if solid.call(kp - up * float(d)):
			clear_below = float(d - 1)
			break

## Push it out of the ground: `solid(p)` says whether a world point is solid. Its outline is
## checked; where it has gone into something it steps back out along the way it came (and up),
## losing the speed it had into the ground and some along it.
func collide(solid: Callable) -> void:
	var up := pos.normalized()
	var hit := 0
	var nsum := Vector2.ZERO
	for b in outline:
		var p := to_world(b)
		if solid.call(p):
			hit += 1
			nsum += pos - p
	grounded = false
	if hit == 0:
		# not in the ground, but maybe resting right on it
		for b3 in outline:
			if solid.call(to_world(b3) - up * 1.0):
				grounded = true
				ground_t += 1
				return
		ground_t = 0
		return
	var n := (nsum.normalized() + up * 0.6).normalized()
	# step out (a few cells at most), then lose the speed into the ground
	for k in 8:
		pos += n * 0.6
		var still := false
		for b2 in outline:
			if solid.call(to_world(b2)):
				still = true
				break
		if not still:
			break
	var vn := vel.dot(n)
	if vn < 0.0:
		if -vn > bump:
			bump = -vn
			bump_at = pos - nsum / float(hit)
		vel -= n * vn
	# friction along whatever it scrapes
	vel -= (vel - n * vel.dot(n)) * 0.12
	if n.dot(up) > 0.5:
		grounded = true
		ground_t += 1

# --------------------------------------------------------------- damage ---

## Mass and the rest from the cells, and then how much of the hull and engine is left.
## (anything changed in its cells: the crates are placed again)
func texture() -> ImageTexture:
	if dirty:
		_crates_key = ""
	return super()

func rebuild() -> void:
	super()
	_crates_key = ""
	room_cells = 0
	for r in room:
		room_cells += r
	_recount()

## the crates its hold carries (trade goods): one for every HOLD_ROOM cells its hull closes in, at least 2
const HOLD_ROOM := 120
var room_cells := 0
func hold_cap() -> int:
	return int(cls()["cargo"])

## where n crates (CRATE_W x CRATE_H cells, top-left corners) stand: in its room first (on the floor or on each
## other, as far from the helm as they go, never in a seat's space or over furniture), then lashed on its open
## deck (outside, on the hull's top: the skiff as forged has little room in its cabin but seats), at last on
## anything it can rest on (the canopy's slope, the fin). A crate that finds no place is left out: still
## carried, just not drawn. Kept until the hull or n changes.
const CRATE_W := 7
const CRATE_H := 6
var _crates := []
var _crates_key := ""
func crate_slots(n: int) -> Array:
	var key := "%d:%d:%d" % [n, w, h]
	if key == _crates_key:
		return _crates
	_crates_key = key
	_crates = []
	if n <= 0 or room.size() != w * h:
		return _crates
	var taken := PackedByteArray()
	taken.resize(w * h)
	var helm_x: float = float((seat_cells[0] as Vector2i).x) if not seat_cells.is_empty() else float(w) * 0.5
	for c in n:
		var best := Vector2i(-1, -1)
		var best_s := -1e9
		for pass_k in 3:
			if best.x >= 0:
				break
			for j in range(1, h - CRATE_H):
				for i in range(0, w - CRATE_W + 1):
					if not _crate_fits(i, j, taken, pass_k >= 1, 4 if pass_k < 2 else 1):
						continue
					# (far from the helm first, then low down)
					var sc := absf(float(i) + float(CRATE_W) * 0.5 - helm_x) * 4.0 + float(j)
					if sc > best_s:
						best_s = sc
						best = Vector2i(i, j)
		if best.x < 0:
			break
		_crates.append(best)
		for jj in CRATE_H:
			for ii in CRATE_W:
				taken[(best.y + jj) * w + best.x + ii] = 1
	return _crates

func _crate_fits(i: int, j: int, taken: PackedByteArray, on_deck := false, min_held := 4) -> bool:
	for jj in CRATE_H:
		for ii in CRATE_W:
			var k := (j + jj) * w + i + ii
			var place_ok: bool = (outside[k] != 0) if on_deck else (room[k] != 0)
			if not place_ok or cells[k] != 0 or taken[k] != 0 or (deco.size() == w * h and deco[k] != 0) or in_seat(i + ii, j + jj):
				return false
	# (resting on the hull, a deck or another crate: most of the way across, so a crown or a slope of deck
	# still holds one)
	var below := (j + CRATE_H) * w
	var held := 0
	for ii2 in CRATE_W:
		var kb := below + i + ii2
		if cells[kb] != 0 or taken[kb] != 0:
			held += 1
	return held >= min_held

func _recount() -> void:
	if design.size() != cells.size():
		hull_f = 1.0
		engine_f = 1.0
		return
	var nh := 0
	var ne := 0
	for k in design.size():
		var d := design[k]
		if d != 0 and cells[k] != 0 and made[k] == 0:
			nh += 1
			if d == Defs.WISP:
				ne += 1
	hull_f = float(nh) / float(hull0)
	engine_f = float(ne) / float(engine0)

## its thrust (and cruise) as its engine is: a hit to it tells, but a wounded skiff still limps home; a hull you
## designed flies by how much engine it has for its mass (`drive`)
func thrust() -> float:
	return (0.4 + 0.6 * sqrt(engine_f)) * drive()

## a designed hull's engines against its mass, measured against a skiff as forged (1 for that): a big hull with
## a little engine is sluggish, more engine makes it lively (0.35 .. 1.5)
func drive() -> float:
	if not designed:
		return float(cls()["speed"])
	if _ratio0 < 0.0:
		var ref = load("res://scripts/skiff.gd").make(1)
		_ratio0 = float(ref.engine0) / maxf(ref.mass, 1.0)
	var r := float(engine0) * engine_f / maxf(mass, 1.0)
	return clampf(sqrt(r / maxf(_ratio0, 0.0001)), 0.35, 1.5)

## A hit at world point p: the hull's cells within r are carved out. Returns how many went (0 once
## the hull is down to HULL_FLOOR: it holds, and the hit goes through to whoever is aboard).
func damage(p: Vector2, r: float) -> int:
	if hull_f <= HULL_FLOOR:
		return 0
	return carve(p, r / sqrt(float(cls()["armour"])))       # (a plated hull: a hit carves less)

## cells of the hull as forged that are gone
func missing() -> int:
	var n := 0
	if design.size() != cells.size():
		return 0
	for k in design.size():
		if design[k] != 0 and cells[k] == 0:
			n += 1
	return n

## Mend up to n of the hull's lost cells, from what's left outward (a gone cell beside one still there
## first, pass after pass, so a deep hole fills from its edges in). Returns the world points of the cells put
## back.
func mend(n: int) -> Array:
	var out := []
	if design.size() != cells.size() or n <= 0:
		return out
	var left := n
	while left > 0:
		var cand := PackedInt32Array()
		var lone := PackedInt32Array()
		for k in design.size():
			if design[k] == 0 or cells[k] != 0:
				continue
			var i := k % w
			var j := k / w
			if at(i - 1, j) != 0 or at(i + 1, j) != 0 or at(i, j - 1) != 0 or at(i, j + 1) != 0:
				cand.append(k)
			else:
				lone.append(k)
		if cand.is_empty():
			cand = lone
		if cand.is_empty():
			break
		for q in mini(left, cand.size()):
			var pick := randi() % cand.size()
			var k2: int = cand[pick]
			cand.remove_at(pick)
			cells[k2] = design[k2]
			vars[k2] = design_v[k2]
			made[k2] = 0
			out.append(cell_world(k2 % w, k2 / w))
			left -= 1
	if not out.is_empty():
		rebuild()
	return out

# ------------------------------------------------------------ the cabin ---

## is cell (i, j) where a rider sits (their box over the seat)? Blocks aren't built there.
func in_seat(i: int, j: int) -> bool:
	for sc in seat_cells:
		var c: Vector2i = sc
		if i >= c.x - 4 and i <= c.x + 4 and j >= c.y - 17 and j <= c.y:
			return true
	return false

# --------------------------------------------------------- your own hull ---
# (user, 23 Nov: "Design your own hull": the skiff grows into a ship you lay out yourself, cell by cell, from
# build mode's Ship tab while aboard: main `_update_hull`)

## is cell (i, j) (it may lie outside the grid) a place to add hull? empty, touching the ship, clear of every
## seat, and the ship no bigger than MAX_W x MAX_H with it
func can_hull(i: int, j: int) -> bool:
	if at(i, j) != 0 or in_seat(i, j):
		return false
	var nw := maxi(w, i + 1) - mini(0, i)
	var nh := maxi(h, j + 1) - mini(0, j)
	if nw > MAX_W or nh > MAX_H:
		return false
	return at(i - 1, j) != 0 or at(i + 1, j) != 0 or at(i, j - 1) != 0 or at(i, j + 1) != 0

## Makes room in the grid for cell (i, j) (outside it, the grid grows with a margin, and every layer, seat and
## the centre of mass move over with it). Returns the offset added to every cell's place.
func grow_for(i: int, j: int) -> Vector2i:
	if i >= 0 and j >= 0 and i < w and j < h:
		return Vector2i.ZERO
	var pl := maxi(0, -i) + (8 if i < 0 else 0)
	var pt := maxi(0, -j) + (8 if j < 0 else 0)
	var pr := maxi(0, i - w + 1) + (8 if i >= w else 0)
	var pb := maxi(0, j - h + 1) + (8 if j >= h else 0)
	var nw := w + pl + pr
	var nh := h + pt + pb
	for ln in ["cells", "vars", "made", "bg", "bgv", "deco", "design", "design_v", "design_bg"]:
		var old: PackedByteArray = get(ln)
		var nu := PackedByteArray()
		nu.resize(nw * nh)
		if old.size() == w * h:
			for jj in h:
				for ii in w:
					nu[(jj + pt) * nw + ii + pl] = old[jj * w + ii]
		set(ln, nu)
	room.resize(nw * nh)
	outside.resize(nw * nh)
	var nm := PackedInt32Array()
	for k0 in seat_marks:
		nm.append((k0 / w + pt) * nw + k0 % w + pl)
	seat_marks = nm
	w = nw
	h = nh
	var off := Vector2i(pl, pt)
	for k in seat_cells.size():
		seat_cells[k] = (seat_cells[k] as Vector2i) + off
	if door_cell.x >= 0:
		door_cell += off
	com += Vector2(off)
	return off

## lays a hull cell (part of the ship as built: what mending puts back)
func add_hull(i: int, j: int, m: int, v: int) -> void:
	var k := j * w + i
	cells[k] = m
	vars[k] = v
	made[k] = 0
	design[k] = m
	design_v[k] = v

## takes a cell of the hull (or what was built there) away: its material, or 0
func cut(i: int, j: int) -> int:
	if i < 0 or j < 0 or i >= w or j >= h:
		return 0
	var k := j * w + i
	var m := cells[k]
	if m == 0:
		return 0
	cells[k] = 0
	made[k] = 0
	design[k] = 0
	return m

## can someone sit at cell (i, j): their feet on something there, room for them over it, clear of the other
## seats (`skip`: a seat that's moving, not counted)
func seat_ok(i: int, j: int, skip := -1) -> bool:
	if at(i, j + 1) == 0 or at(i, j + 1) == Defs.SCAFFOLD:
		return false
	for dj in range(-16, 1):
		for di in range(-3, 4):
			if at(i + di, j + dj) != 0:
				return false
	for k in seat_cells.size():
		if k == skip:
			continue
		var c: Vector2i = seat_cells[k]
		if absi(c.x - i) < 7 and absi(c.y - j) < 17:
			return false
	return true

## the helm (the pilot's seat) moved to cell (i, j)
func set_helm(i: int, j: int) -> void:
	seat_cells[0] = Vector2i(i, j)
	_seat_marks()

## another seat at (i, j)
func add_seat(i: int, j: int) -> bool:
	if seat_cells.size() >= MAX_SEATS:
		return false
	seat_cells.append(Vector2i(i, j))
	riders.append(null)
	_seat_marks()
	return true

## the seat (not the helm) whose place is near (i, j), or -1
func seat_near(i: int, j: int) -> int:
	for k in range(1, seat_cells.size()):
		var c: Vector2i = seat_cells[k]
		if absi(c.x - i) <= 3 and j <= c.y and j >= c.y - 16:
			return k
	return -1

func remove_seat(k: int) -> void:
	if k <= 0 or k >= seat_cells.size() or riders[k] != null:
		return
	seat_cells.remove_at(k)
	riders.remove_at(k)
	_seat_marks()

## the seats drawn on the back layer: a chair's back and seat at each, the helm's console with a glowing pane
## in front of the pilot (only over back wall that's as forged, or bare)
var seat_marks := PackedInt32Array()
func _seat_marks() -> void:
	for k in seat_marks:
		if k < bg.size():
			bg[k] = design_bg[k] if design_bg.size() == bg.size() else 0
	seat_marks = PackedInt32Array()
	for s in seat_cells.size():
		var c: Vector2i = seat_cells[s]
		for dj in range(0, 7):
			_mark(c.x - 3, c.y - dj, Defs.TIMBER, 0)
		for di in range(-3, 2):
			_mark(c.x + di, c.y - 3, Defs.TIMBER, 1)
		if s == 0:
			for dj2 in range(0, 6):
				_mark(c.x + 5, c.y - dj2, Defs.COPPERBAR, 2)
			_mark(c.x + 4, c.y - 6, Defs.CRYSTAL, 0)
			_mark(c.x + 5, c.y - 6, Defs.CRYSTAL, 0)
	dirty = true

func _mark(i: int, j: int, m: int, v: int) -> void:
	if i < 0 or j < 0 or i >= w or j >= h:
		return
	var k := j * w + i
	if bg[k] != 0 and bg[k] != (design_bg[k] if design_bg.size() == bg.size() else 0):
		return
	bg[k] = m
	bgv[k] = v
	seat_marks.append(k)

## after building on the hull: mass, room and outline again, and it stays where it was in the world (its
## centre of mass moved); what's built is counted again (engine cells: the wisp ore in it)
func finish_edit(old_com: Vector2) -> void:
	rebuild()
	pos += axis_x() * (com.x - old_com.x) + axis_y() * (com.y - old_com.y)
	designed = true
	_count_design()
	_recount()

func _count_design() -> void:
	hull0 = 0
	engine0 = 0
	for k in design.size():
		if design[k] != 0:
			hull0 += 1
			if design[k] == Defs.WISP:
				engine0 += 1
	hull0 = maxi(hull0, 1)
	engine0 = maxi(engine0, 1)

# --------------------------------------------------------------- saving ---
# (a hull you designed: its size, seats and its layers as built go with its cells)

func save_cells() -> Dictionary:
	var d := super.save_cells()
	var raw := PackedByteArray()
	for a in [design, design_v, design_bg]:
		raw.append_array(a)
	d["design"] = Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	var seats := []
	for c in seat_cells:
		seats.append([(c as Vector2i).x, (c as Vector2i).y])
	d["seats"] = seats
	d["designed"] = designed
	d["marks"] = Array(seat_marks)
	d["door"] = [door_cell.x, door_cell.y]
	d["klass"] = klass
	d["rig"] = RIG
	return d

func load_cells(d: Dictionary) -> bool:
	if String(d.get("klass", "skiff")) != klass or bool(d.get("designed", false)) or int(d.get("rig", 0)) < RIG:
		# (another class's cells, a hull built in the old builder, or one saved with the glass canopy before the
		# sails: forged afresh, whole)
		return false
	var nw := int(d.get("w", w))
	var nh := int(d.get("h", h))
	if bool(d.get("designed", false)) and (nw != w or nh != h):
		setup(nw, nh)
		design.resize(nw * nh)
		design_v.resize(nw * nh)
		design_bg.resize(nw * nh)
	if not super.load_cells(d):
		return false
	if d.has("design"):
		var n := w * h
		var raw := Marshalls.base64_to_raw(String(d["design"])).decompress(n * 3, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == n * 3:
			design = raw.slice(0, n)
			design_v = raw.slice(n, n * 2)
			design_bg = raw.slice(n * 2, n * 3)
	if d.has("seats"):
		seat_cells = []
		for c in d["seats"]:
			seat_cells.append(Vector2i(int(c[0]), int(c[1])))
		riders = []
		riders.resize(seat_cells.size())
	seat_marks = PackedInt32Array(d.get("marks", []))
	var dr = d.get("door", null)
	door_cell = Vector2i(int(dr[0]), int(dr[1])) if dr is Array and (dr as Array).size() == 2 else Vector2i(-1, -1)
	designed = bool(d.get("designed", false))
	if designed:
		_count_design()
	_recount()
	return true
