## The galaxy between the planets (user, 22 Nov: infinite space with content in it). Pure functions of
## the world seed, so every journey's galaxy is its own and the same each time you come back:
## - star systems: Defs.system_g (a jittered grid, SYS_GAP apart, numbered in a spiral), a star name
##   each (`star_name`), its planets Defs.planet_g(5r..5r+4);
## - sectors: space is cut into SECTOR-wide squares; each one's content (`sector_content`) is grown
##   from its own seed: an asteroid field now and then, sometimes a big drifting field, sometimes a
##   comet on its long loop. Nothing is grown near a planet (its own asteroid clusters are its world's).
##   space.gd streams the sectors round you in and out, and keeps the ones you've changed (mined).
## - nebulae: great clouds of coloured gas over the galaxy (`nebula`, low-frequency noise).
## Galaxy positions are doubles: PackedFloat64Array([x, y]).
extends RefCounted

const SECTOR := 25000.0          # a sector's width (cells)
const NEAR_PLANET := 14000.0     # nothing grown this close to a planet
const FIELD := 0.3               # a sector's chance of an asteroid field...
const BIG := 0.06                # ...of a big drifting one
const COMET := 0.07              # ...of a comet
const WRECK := 0.045             # ...of a derelict wreck (wreck.gd) with scrap drifting round it
const FIRST_WRECK := 22000.0     # every journey's first wreck drifts about this far from the home planet
const OUTPOST_D := 27000.0       # every system's trading outpost (outpost.gd) is about this far from its first planet
const STATION_D := 38000.0       # every system's derelict station (station.gd) about this far
const STATION := 0.012           # a deep-space sector's chance of a derelict station of its own
const CHART_R := 220000.0        # a system is charted (its planets on the map) once you come this close
const SCAN_R := 32000.0          # what you see round you marks the map's sectors as explored
const BODY_R := 300000.0         # the planets of systems this close are out there with you (space.gd bodies)

const STAR_A := ["Al", "Be", "Cor", "Dra", "El", "Fen", "Gal", "Hy", "Ir", "Ka", "Lu", "Mir", "Nor", "Or", "Pyx",
	"Qua", "Ri", "Sel", "Tor", "Ul", "Vae", "Wy", "Xe", "Zan"]
const STAR_B := ["", "a", "e", "i", "o", "u", "ae", "ei"]
const STAR_C := ["ra", "nis", "dor", "lith", "mar", "vex", "thys", "rion", "sel", "kar", "dun", "phae", "lon", "zar"]

static var _neb: FastNoiseLite = null
static var _neb2: FastNoiseLite = null
static var _neb_seed := -1
static var _content := {}

## the sector a galaxy point is in
static func sector_of(gx: float, gy: float) -> Vector2i:
	return Vector2i(int(floor(gx / SECTOR)), int(floor(gy / SECTOR)))

static func key_of(s: Vector2i) -> String:
	return "%d,%d" % [s.x, s.y]

static func sector_g(s: Vector2i) -> PackedFloat64Array:
	return PackedFloat64Array([float(s.x) * SECTOR, float(s.y) * SECTOR])

## the systems whose first planet lies within `rad` of (gx, gy)
static func systems_near(gx: float, gy: float, rad: float) -> Array:
	var out := []
	var c := Vector2i(roundi(gx / Defs.SYS_GAP), roundi(gy / Defs.SYS_GAP))
	var n := int(ceil(rad / Defs.SYS_GAP)) + 1
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			var r: int = Defs.spiral_index(c + Vector2i(dx, dy))
			var g: PackedFloat64Array = Defs.system_g(r)
			var ddx: float = g[0] - gx
			var ddy: float = g[1] - gy
			if ddx * ddx + ddy * ddy < rad * rad:
				out.append(r)
	return out

## a name for system r's star
static func star_name(r: int) -> String:
	var nr := RandomNumberGenerator.new()
	nr.seed = hash([Defs.world_seed, r, 13])
	var s: String = STAR_A[nr.randi_range(0, STAR_A.size() - 1)] + STAR_B[nr.randi_range(0, STAR_B.size() - 1)] + STAR_C[nr.randi_range(0, STAR_C.size() - 1)]
	return s

## a star's colour (system r): white-yellow mostly, some orange, red or blue-white
static func star_col(r: int) -> Color:
	var nr := RandomNumberGenerator.new()
	nr.seed = hash([Defs.world_seed, r, 17])
	return [Color(1.0, 0.95, 0.8), Color(1.0, 0.95, 0.8), Color(1.0, 0.8, 0.55), Color(1.0, 0.6, 0.45), Color(0.75, 0.85, 1.0)][nr.randi_range(0, 4)]

## How thick a nebula is at a galaxy point (0 = clear space), and its colour.
static func nebula(gx: float, gy: float) -> Array:
	if _neb == null or _neb_seed != Defs.world_seed:
		_neb_seed = Defs.world_seed
		_neb = FastNoiseLite.new()
		_neb.seed = Defs.world_seed ^ 0x4E42
		_neb.frequency = 1.0 / 260000.0
		_neb.fractal_octaves = 3
		_neb2 = FastNoiseLite.new()
		_neb2.seed = Defs.world_seed ^ 0x2C01
		_neb2.frequency = 1.0 / 900000.0
	# (noise takes single floats: wrapped to a period it can hold exactly enough for clouds this big)
	var x := fposmod(gx, 4.0e7)
	var y := fposmod(gy, 4.0e7)
	var d := clampf((_neb.get_noise_2d(x, y) - 0.32) / 0.3, 0.0, 1.0)
	# (its colour from a few that read as nebulae: violet, magenta, teal, deep blue, rose)
	var h := clampf(_neb2.get_noise_2d(x, y) * 0.5 + 0.5, 0.0, 0.999)
	var pal := [Color(0.55, 0.35, 1.0), Color(0.95, 0.35, 0.8), Color(0.25, 0.85, 0.85), Color(0.3, 0.45, 1.0), Color(1.0, 0.45, 0.55)]
	var f := h * float(pal.size() - 1)
	var col: Color = (pal[int(f)] as Color).lerp(pal[mini(int(f) + 1, pal.size() - 1)], f - floorf(f))
	return [d, col]

## True if (gx, gy) is too near a planet for anything to be grown there.
static func _near_planet(gx: float, gy: float) -> bool:
	for r in systems_near(gx, gy, 140000.0):
		for k in Defs.SYSTEM.size():
			var g: PackedFloat64Array = Defs.planet_g(r * Defs.SYSTEM.size() + k)
			var dx: float = g[0] - gx
			var dy: float = g[1] - gy
			if dx * dx + dy * dy < NEAR_PLANET * NEAR_PLANET:
				return true
	return false

## What sector s holds: a list of {"type": "field"/"comet", "at": Vector2 (from the sector's corner),
## "name", "rocks": [{"seed", "r", "kind", "off" (from "at"), "vel", "orbit" (a comet's loop)}]}.
static func sector_content(s: Vector2i) -> Array:
	var key := "%d:%s" % [Defs.world_seed, key_of(s)]
	if _content.has(key):
		return _content[key]
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Defs.world_seed, s.x, s.y, 77])
	var roll := rng.randf()
	var at := Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8)) * SECTOR
	var sg := sector_g(s)
	var fw := first_wreck()
	# (a system's trading outpost, if it's in this sector: then nothing else is grown here)
	var op_here := false
	for r in systems_near(sg[0] + SECTOR * 0.5, sg[1] + SECTOR * 0.5, OUTPOST_D + SECTOR * 2.0):
		var og := system_outpost(r)
		if sector_of(og[0], og[1]) == s:
			op_here = true
			out.append({"type": "outpost", "at": Vector2(og[0] - sg[0], og[1] - sg[1]), "sys": r,
				"name": outpost_name(r), "rocks": [{"seed": outpost_seed(r), "r": 0.0, "kind": "outpost", "off": Vector2.ZERO, "vel": Vector2.ZERO}]})
	# (and its derelict station: nothing else is grown there either)
	for r2 in systems_near(sg[0] + SECTOR * 0.5, sg[1] + SECTOR * 0.5, STATION_D + SECTOR * 2.0):
		var stg := system_station(r2)
		if sector_of(stg[0], stg[1]) == s:
			op_here = true
			out.append(_station(station_seed(r2), Vector2(stg[0] - sg[0], stg[1] - sg[1])))
	if s == sector_of(fw[0], fw[1]):
		# (the first wreck: near home, so every journey finds one; its bridge always holds a ship part)
		out.append(_wreck(rng, Vector2(fw[0] - sg[0], fw[1] - sg[1]), true))
	elif roll < FIELD + BIG + COMET + WRECK + STATION and not op_here and not _near_planet(sg[0] + at.x, sg[1] + at.y):
		if roll < BIG:
			out.append(_field(rng, at, true))
		elif roll < BIG + FIELD:
			out.append(_field(rng, at, false))
		elif roll < BIG + FIELD + COMET:
			out.append(_comet(rng, at))
		elif roll < BIG + FIELD + COMET + WRECK:
			out.append(_wreck(rng, at, false))
		else:
			out.append(_station(rng.randi() & 0xFFFFFF, at))
	_content[key] = out
	return out

## where every journey's first wreck drifts: FIRST_WRECK from the home planet, the way (from the
## journey's seed) that keeps it clear of every planet
static func first_wreck() -> PackedFloat64Array:
	var key := "first:%d" % Defs.world_seed
	if _content.has(key):
		return _content[key]
	var hg: PackedFloat64Array = Defs.planet_g(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Defs.world_seed, 991])
	var best := PackedFloat64Array([hg[0] + FIRST_WRECK, hg[1]])
	for t in 24:
		var a := rng.randf() * TAU
		var gx: float = hg[0] + cos(a) * FIRST_WRECK
		var gy: float = hg[1] + sin(a) * FIRST_WRECK
		best = PackedFloat64Array([gx, gy])
		if not _near_planet_r(gx, gy, NEAR_PLANET + 4000.0):
			break
	_content[key] = best
	return best

## where system r's trading outpost is: OUTPOST_D from its first planet, the way (from the journey's seed)
## that keeps it clear of every planet (and, in the first system, of the first wreck)
static func system_outpost(r: int) -> PackedFloat64Array:
	var key := "outpost:%d:%d" % [Defs.world_seed, r]
	if _content.has(key):
		return _content[key]
	var hg: PackedFloat64Array = Defs.planet_g(r * Defs.SYSTEM.size())
	var fw := first_wreck()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Defs.world_seed, r, 4242])
	var best := PackedFloat64Array([hg[0] - OUTPOST_D, hg[1]])
	for t in 32:
		var a := rng.randf() * TAU
		var d := OUTPOST_D + rng.randf_range(-2000.0, 2000.0)
		var gx: float = hg[0] + cos(a) * d
		var gy: float = hg[1] + sin(a) * d
		best = PackedFloat64Array([gx, gy])
		var by_wreck: bool = (gx - fw[0]) * (gx - fw[0]) + (gy - fw[1]) * (gy - fw[1]) < 12000.0 * 12000.0
		if not by_wreck and not _near_planet_r(gx, gy, NEAR_PLANET + 6000.0):
			break
	_content[key] = best
	return best

## where system r's derelict station hangs: STATION_D from its first planet, clear of every planet, its
## outpost and the first wreck
static func system_station(r: int) -> PackedFloat64Array:
	var key := "station:%d:%d" % [Defs.world_seed, r]
	if _content.has(key):
		return _content[key]
	var hg: PackedFloat64Array = Defs.planet_g(r * Defs.SYSTEM.size())
	var fw := first_wreck()
	var og := system_outpost(r)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Defs.world_seed, r, 5150])
	var best := PackedFloat64Array([hg[0] + STATION_D, hg[1]])
	for t in 40:
		var a := rng.randf() * TAU
		var d := STATION_D + rng.randf_range(-3000.0, 3000.0)
		var gx: float = hg[0] + cos(a) * d
		var gy: float = hg[1] + sin(a) * d
		best = PackedFloat64Array([gx, gy])
		var by_wreck: bool = (gx - fw[0]) * (gx - fw[0]) + (gy - fw[1]) * (gy - fw[1]) < 14000.0 * 14000.0
		var by_op: bool = (gx - og[0]) * (gx - og[0]) + (gy - og[1]) * (gy - og[1]) < 16000.0 * 16000.0
		if not by_wreck and not by_op and not _near_planet_r(gx, gy, NEAR_PLANET + 8000.0):
			break
	_content[key] = best
	return best

static func station_seed(r: int) -> int:
	return hash([Defs.world_seed, r, 5151]) & 0xFFFFFF

static func station_name(r: int) -> String:
	return load("res://scripts/station.gd").station_name(station_seed(r))

static func _station(sd: int, at: Vector2) -> Dictionary:
	return {"type": "station", "at": at, "name": "Derelict " + String(load("res://scripts/station.gd").station_name(sd)),
		"rocks": [{"seed": sd, "r": 0.0, "kind": "station", "off": Vector2.ZERO, "vel": Vector2.ZERO}]}

static func outpost_seed(r: int) -> int:
	return hash([Defs.world_seed, r, 4243]) & 0xFFFFFF

static func outpost_name(r: int) -> String:
	return load("res://scripts/outpost.gd").outpost_name(outpost_seed(r))

static func _near_planet_r(gx: float, gy: float, r: float) -> bool:
	for sr in systems_near(gx, gy, 140000.0):
		for k in Defs.SYSTEM.size():
			var g: PackedFloat64Array = Defs.planet_g(sr * Defs.SYSTEM.size() + k)
			if (g[0] - gx) * (g[0] - gx) + (g[1] - gy) * (g[1] - gy) < r * r:
				return true
	return false

## a derelict and the scrap drifting round it
static func _wreck(rng: RandomNumberGenerator, at: Vector2, is_first: bool) -> Dictionary:
	var rocks := [{"seed": rng.randi(), "r": 0.0, "kind": "wreck", "off": Vector2.ZERO, "first": is_first,
		"vel": Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.004}]
	for k in rng.randi_range(3, 6):
		rocks.append({"seed": rng.randi(), "r": rng.randf_range(4.0, 10.0), "kind": "scrap",
			"off": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(140.0, 380.0),
			"vel": Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.02})
	var wn: String = load("res://scripts/wreck.gd").name_of(int(rocks[0]["seed"]))
	return {"type": "wreck", "at": at, "name": "Wreck of " + wn, "rocks": rocks}

static func _field(rng: RandomNumberGenerator, at: Vector2, big: bool) -> Dictionary:
	var kinds := ["stony", "stony", "icy", "metallic"]
	var main: String = kinds[rng.randi_range(0, kinds.size() - 1)]
	var n := rng.randi_range(6, 10) if big else rng.randi_range(2, 5)
	var spread := 900.0 if big else 420.0
	var rocks := []
	for k in n:
		var kind: String = main if rng.randf() < 0.7 else kinds[rng.randi_range(0, kinds.size() - 1)]
		var r := rng.randf_range(14.0, 36.0) if k > 0 else rng.randf_range(28.0, 46.0 if big else 38.0)
		var off := Vector2.ZERO if k == 0 else Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(90.0, spread)
		rocks.append({"seed": rng.randi(), "r": r, "kind": kind, "off": off,
			"vel": Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 0.012})
	var names := {"stony": "Asteroid field", "icy": "Ice field", "metallic": "Metal-rich field"}
	return {"type": "field", "at": at, "name": ("Great " if big else "") + String(names[main]), "rocks": rocks, "big": big}

## a comet: a ball of ice on a long loop round the middle of its sector, its tail streaming behind it
static func _comet(rng: RandomNumberGenerator, at: Vector2) -> Dictionary:
	var orbit := {"a": rng.randf_range(5000.0, 8500.0), "b": rng.randf_range(1800.0, 3500.0), "rot": rng.randf() * TAU,
		"w": TAU / rng.randf_range(9000.0, 16000.0) * (1.0 if rng.randf() < 0.5 else -1.0), "ph": rng.randf() * TAU}
	var rocks := [{"seed": rng.randi(), "r": rng.randf_range(16.0, 24.0), "kind": "icy", "off": Vector2.ZERO, "vel": Vector2.ZERO, "orbit": orbit}]
	return {"type": "comet", "at": at, "name": "Comet", "rocks": rocks}

## where a comet is at game time t (ticks), from the middle of its loop
static func comet_at(o: Dictionary, t: float) -> Vector2:
	var th := float(o["ph"]) + float(o["w"]) * t
	return Vector2(cos(th) * float(o["a"]), sin(th) * float(o["b"])).rotated(float(o["rot"]))
