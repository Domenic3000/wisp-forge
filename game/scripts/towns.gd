## Living towns: the people of the villages that still stand (buildings.gd `towns` with "living").
## Near you a village fills with its folk (`_fill`): a keeper in every shop, smithy, tavern and inn, day and
## night, and its residents, each with a home (and those who live over a shop, a workplace). Their day
## follows the local hour (`want_place`): out in the street in the morning and by day, some at work in their
## shop, the tavern of an evening, home asleep at night. Going in or out of a house, or past one that's in
## the way, they step through it (a short fade at its side). In the street they turn at walls and drops and
## run from foes; indoors they potter about the room.
## Talk to anyone (F) for a word or a rumour (`line_for`). One resident of each village (marked "!") has a
## request (`_request`: bring something, thin out a creature, carry a letter to another village); a second F
## takes it, and talking to them again hands it in (a letter is handed to the keeper it's for). Talk to a
## keeper to trade (main state "shop", ui.gd's shop panel): coins for what you gather, and the shop's stock
## (`shop_def`: Defs.SHOPS by role, plus Defs.KIND_TRADE for this kind of planet and an imported ore).
## The folk are made again from their village's seed each time you come (same names, same looks);
## requests (planet_state["requests"], ["req_n"]) and coins are kept.
extends RefCounted

const FolkArt := preload("res://scripts/folk_art.gd")
const NEAR := 520.0          # a village this near (cells round the planet) has its folk out
const FAR := 760.0           # ...and this far off they're gone again
const TALK := 24.0           # how close to talk to someone
const WALK := 0.55
const HURRY := 0.8           # (going somewhere: home, to work, to the tavern)
const MAX_FOLK := 10         # residents a village (keepers besides)
const FADE := 18             # ticks to fade out (and in again) stepping through a house's side
const STREET := {}           # (the place "out in the street")
## Guards (26 Nov, "town guards"): every living village has GUARDS_MIN of them (one more for four houses or more,
## and one more for each house it has grown, up to GUARDS_MAX). They walk the village end to end day and night
## (with a lantern after dark), and go for any foe that comes within GUARD_SIGHT of them inside the village (or
## GUARD_ROAM past its ends): never a guardian or other boss, nor wild things that leave folk alone (prey and the
## neutral, unless they've been roused). Their spear strikes for GUARD_HIT every GUARD_EVERY ticks. They can't be
## killed. `guard_count`, `_guard`, `_guard_target`; folk_art.gd's "guard" look; overlay's "jab".
const GUARDS_MIN := 1
const GUARDS_MAX := 4
const GUARD_SIGHT := 170.0
const GUARD_ROAM := 90
const GUARD_REACH := 12.0
const GUARD_TURN := 3.0          # (how far to one side a foe must be before a guard turns to it)
const GUARD_HIGH := 30.0         # (a foe further above or below than this is out of a guard's reach: ignored)
const GUARD_HIT := 9.0
const GUARD_EVERY := 34
## A village grows as you help it (26 Nov): at GROW_AT requests done there (`town_rep`), its folk build a new house
## at one end (buildings.gd `grow_house`, laid by rebuild.gd a course at a time, furniture and all); a family moves
## in and another guard walks it. `planet_state["grown"]`: village seed -> houses grown, planned again on loading
## (`replay_growth`).
const GROW_AT := [2, 5, 9]
const GUARD_LINES := ["Keep your wits about you out there, mage. We'll see off whatever comes in.", "Nothing gets past this spear. Well, nothing small.",
	"Quiet night so far. I like quiet.", "If you see wolves on the road, send them my way.", "The village sleeps easier with us walking it.",
	"I'd fight a guardian if they let me. They don't let me."]

var game
var folk: Array = []         # main.gd Villager bodies
var _peopled := {}           # village seed -> true
var shop_of = null           # the keeper you're trading with (main state "shop")
var stats := {}              # (counts for the tests)
var rebuild                  # rebuild.gd: villages put back the houses knocked down (user, 23 Nov)
var no_grow := false         # (the test mode's requests check: done requests don't grow the village)
var test_guards := false     # (the test mode: guards stand by, so they don't spear the foes other checks set up)

func _init(g) -> void:
	game = g
	rebuild = preload("res://scripts/rebuild.gd").new(g, self)

func clear() -> void:
	rebuild.job = {}
	rebuild._look = {}
	folk.clear()
	_peopled.clear()
	shop_of = null

## every tick on the planet
func tick() -> void:
	if game.frame % 30 == 0:
		_people()
	rebuild.tick()
	for k in range(folk.size() - 1, -1, -1):
		var v = folk[k]
		if v.gone:
			folk.remove_at(k)
			continue
		_walk(v)
		if v.lying and not v.lie_ok:
			_settle_sleeper(v)

## Someone lying down is put on what's really there (user, 23 Nov: "villagers are floating in their
## sleeping bags, one was inside the roof triangle"): a bed's mattress (the top of the furniture over its
## middle), or the floor under a bedroll, read from the collision grid once they're near enough to have
## it; a spot with no room over it (under a roof's slope) is no place to sleep, so it's the floor then.
func _settle_sleeper(v) -> void:
	if not game.in_grid(v.pos, 24.0):
		return
	v.lie_ok = true
	var cf: float = fposmod(atan2(v.pos.y, v.pos.x), TAU) / TAU * float(Defs.NS) - 0.5
	var col := int(round(cf))
	var hc: float = fposmod(atan2(v.lie_head.y, v.lie_head.x), TAU) / TAU * float(Defs.NS) - 0.5
	if not v.bedroll and not v.bed.is_empty():
		var brow := int(v.bed["row"])
		var top := -1
		for k in range(0, 16):
			if game._bg_at(col, brow - k) == 1:
				top = brow - k
			elif top >= 0:
				break
		if top >= 0 and _headroom(col, top - 1, 7):
			v.pos = _at(cf, float(top), 3.5)
			v.lie_head = _at(hc, float(top), 3.5)
			return
		v.bedroll = true                     # (no bed there after all, or no room over it: the floor)
	var row0 := int(floor(float(Defs.R_TOP) - v.pos.length()))
	var fr: int = game._floor_below(col, row0 - 10, 28)
	while fr >= 0 and not _headroom(col, fr, 9):
		fr = game._floor_below(col, fr + 1, 28)
	if fr < 0:
		return
	v.pos = _at(cf, float(fr), 4.0)
	v.lie_head = _at(hc, float(fr), 4.0)

## is a sleeper still lying on something (a bed's furniture or solid floor a few rows under them), with no fire
## right beside them?
func _sleeper_safe(v) -> bool:
	var col := _col(v.pos)
	var row := int(floor(float(Defs.R_TOP) - v.pos.length()))
	var held := false
	for k in range(1, 8):
		if game._solid_at(col, row + k) or game._bg_at(col, row + k) == 1:
			held = true
			break
	if not held:
		return false
	var a := atan2(v.pos.y, v.pos.x)
	for off in [Vector2(-8, 0), Vector2(8, 0), Vector2(0, -6), Vector2(-4, -3), Vector2(4, -3), Vector2(0, 3)]:
		var p: Vector2 = v.pos + game.basis_r(a) * off.x + game.basis_d(a) * off.y
		if game.type_at(p) == Defs.FIRE:
			return false
	return true

## open rows from `row` up (count of them): room to lie or stand there
func _headroom(col: int, row: int, n: int) -> bool:
	for k in n:
		if not game._open_at(col, row - k):
			return false
	return true

## which column a world point is over
func _col(p: Vector2) -> int:
	return int(fposmod(atan2(p.y, p.x), TAU) / TAU * Defs.NS)

func _cdist(a: int, b: int) -> int:
	var d := absi(posmod(a - b, Defs.NS))
	return mini(d, Defs.NS - d)

## a point over column c, `up` cells above row `row`
func _at(c: float, row: float, up: float) -> Vector2:
	var a := (c + 0.5) / float(Defs.NS) * TAU
	return Vector2(cos(a), sin(a)) * (Defs.R_TOP - row - 0.5 + up)

## the hour (0-24) at a point: noon when the sun is overhead
func hour_at(p: Vector2) -> float:
	var sun_a: float = game.spawn_angle - 1.1 + game.time / game.DAY_LEN * TAU
	var d := wrapf(atan2(p.y, p.x) - sun_a, -PI, PI)
	return fposmod(12.0 - d / TAU * 24.0, 24.0)

## the clock (game.time) that makes it `hour` o'clock at a point (tests; nothing else turns the clock)
func time_for_hour(p: Vector2, hour: float) -> float:
	var sun_a := atan2(p.y, p.x) - (12.0 - hour) / 24.0 * TAU
	return fposmod((sun_a - game.spawn_angle + 1.1) / TAU * game.DAY_LEN, game.DAY_LEN)

static func is_night(hr: float) -> bool:
	return hr >= 22.0 or hr < 6.0

## fill the villages near you, and empty the ones you've left
func _people() -> void:
	var pc := _col(game.player.pos)
	for t in game.builds.towns:
		if not bool(t["living"]):
			continue
		var mid := int(t["x0"]) + int(t["w"]) / 2
		var d := _cdist(pc, mid)
		var tk := int(t["seed"])
		if d < NEAR and not _peopled.has(tk):
			_peopled[tk] = true
			_fill(t)
		elif d > FAR and _peopled.has(tk):
			_peopled.erase(tk)
			for v in folk:
				if int(v.town["seed"]) == tk:
					v.gone = true

## a village's keepers and residents, each put where the hour says they'd be
func _fill(t: Dictionary) -> void:
	var houses: Array = t["houses"]
	var n := 0
	var asker := asker_index(t)
	for hi in houses.size():
		var h: Dictionary = houses[hi]
		if bool(h["ruined"]):
			continue
		var role := String(h["role"])
		if Defs.SHOPS.has(role):
			var kc := float(int(h["x0"]) + int(h["w"]) / 2)
			var kv = _add(t, h, STREET, hseed(t, hi, 0), role, true)
			kv.pos = _at(kc, float(h["floor"]), 9.0)
			kv.inside = h
		for k in (2 if role == "home" else 1):
			if n >= MAX_FOLK:
				break
			var v = _add(t, h, STREET if role == "home" else h, hseed(t, hi, k + 1), "folk", false)
			v.idx = n
			v.asker = n == asker
			var beds: Array = h.get("beds", [])
			if k < beds.size():
				v.bed = beds[k]
			var hr_now := hour_at(_at(float(int(t["x0"]) + int(t["w"]) / 2), 0.0, 0.0))
			_place(v, want_place(v, hr_now))
			if is_night(hr_now) and v.inside == v.house:
				_lie_down(v, true)
			n += 1
	# its guards, out in the street whatever the hour
	for gk in guard_count(t):
		var gv = _add(t, {}, STREET, hseed(t, 900 + gk, 0), "folk", false)
		gv.role = "guard"
		gv.idx = -1 - gk
		gv.asker = false
		_place(gv, STREET)
	stats["filled"] = int(stats.get("filled", 0)) + 1
	var seen: Array = game.planet_state.get("towns_seen", [])
	if not seen.has(int(t["seed"])):
		seen.append(int(t["seed"]))
		game.planet_state["towns_seen"] = seen
		game.ui.toast("%s: a village. Talk to its folk (F), and trade at its shops." % t["name"], Color(0.95, 0.85, 0.6), 4.0)

## how many guards walk a village: one, one more for four houses or more, one more for each house it has grown
func guard_count(t: Dictionary) -> int:
	var n := GUARDS_MIN
	if (t["houses"] as Array).size() >= 4:
		n += 1
	for h in t["houses"]:
		if bool(h.get("grown", false)) and not bool(h.get("new", false)):
			n += 1                                   # (a house grown and built)
	return mini(n, GUARDS_MAX)

## how many residents a village has (MAX_FOLK at most)
static func resident_count(t: Dictionary) -> int:
	var n := 0
	for h in t["houses"]:
		if not bool(h["ruined"]):
			n += 2 if String(h["role"]) == "home" else 1
	return mini(n, MAX_FOLK)

static func hseed(t: Dictionary, hi: int, n: int) -> int:
	return posmod(hash([int(t["seed"]), hi, n]), 0x7FFFFFFF)

func _add(t: Dictionary, h: Dictionary, job: Dictionary, fseed: int, role: String, keeper: bool) -> Variant:
	var v = game.new_villager()
	v.fseed = fseed
	v.role = role if keeper else "folk"
	v.keeper = keeper
	v.town = t
	v.house = h
	v.job = job
	v.name = FolkArt.name_for(fseed)
	v.w = 7.0
	v.h = 17.0
	v.step_h = 3
	v.idle_t = randi_range(30, 200)
	v.facing = 1 if randf() < 0.5 else -1
	folk.append(v)
	return v

# ------------------------------------------------------------------ the day ---

## where someone would be at an hour: a house (home, work, the tavern), or STREET
func want_place(v, hr: float) -> Dictionary:
	if is_night(hr):
		return v.house                                       # (asleep at home)
	if hr >= 17.5:
		var tav := _house_of(v.town, "tavern")
		if not tav.is_empty() and v.fseed % 3 != 0:
			return tav                                       # (an evening at the tavern)
		return v.house if v.fseed % 2 == 0 else STREET
	if hr < 7.0 and v.fseed % 2 == 0:
		return v.house                                       # (not up yet)
	if not v.job.is_empty() and hr >= 9.0 and hr < 16.0 and v.fseed % 4 != 3:
		return v.job                                         # (at work)
	return STREET

func _house_of(t: Dictionary, role: String) -> Dictionary:
	for h in t["houses"]:
		if String(h["role"]) == role and not bool(h["ruined"]):
			return h
	return {}

## the house of a village over column c (its walls and a little round them), or {}
func _house_at(t: Dictionary, c: float) -> Dictionary:
	for h in t["houses"]:
		var off := fposmod(c - float(int(h["x0"])) + 4.0, float(Defs.NS))
		if off < float(int(h["w"])) + 8.0:
			return h
	return {}

## put someone straight where they'd be (when a village is filled)
func _place(v, where: Dictionary) -> void:
	v.inside = where
	if not where.is_empty():
		v.pos = _spot_in(where)
	else:
		var t: Dictionary = v.town
		for k in 10:
			var c := float(int(t["x0"]) + 12 + randi() % maxi(1, int(t["w"]) - 24))
			if (_house_at(t, c).is_empty() and not _taken(_street_at(c), STREET, 9.0)) or k == 9:
				v.pos = _street_at(c)
				break
	v.goal_c = float(_col(v.pos))

## a spot on a house's ground floor, clear of anyone already there (a few tries, then the last)
func _spot_in(h: Dictionary) -> Vector2:
	var c := 0.0
	for k in 8:
		c = float(int(h["x0"]) + 7) + randf() * maxf(1.0, float(int(h["w"]) - 14))
		if not _taken(_at(c, float(h["floor"]), 9.0), h, 9.0):
			break
	return _at(c, float(h["floor"]), 9.0)

## where someone is, or is about to be (stepping through a door: where they'll come out), and in what place
func _spot_of(f) -> Array:
	if f.fade > 0:
		return [f.fade_to, f.fade_in]
	return [f.pos, f.inside]

## is someone already standing (or lying) within `gap` columns of p, on the same floor of the same place?
func _taken(p: Vector2, place: Dictionary, gap: float, but = null) -> bool:
	return _clearance(p, place, but, gap) < gap

## how many columns from p to the nearest other person on the same floor of the same place (and to the
## nearest chest at that height), up to `cap`
func _clearance(p: Vector2, place: Dictionary, but, cap: float) -> float:
	var best := cap
	var pc := float(_col(p))
	for f in folk:
		if f == but or f.gone:
			continue
		var sp: Array = _spot_of(f)
		if sp[1] != place:
			continue
		var fp: Vector2 = sp[0]
		if absf(fp.length() - p.length()) < 10.0:
			best = minf(best, absf(_dc(pc, fp)))
	for ch in game.chests:
		var cp: Vector2 = ch.pos
		if absf(cp.length() - p.length()) < 14.0:
			best = minf(best, absf(_dc(pc, cp)) * 0.7)
	return best

## which way (in columns) to step to get clear of whoever is standing in the same spot: 0 = nobody there
func _crowd_side(v) -> float:
	var p: Vector2 = v.pos
	for f in folk:
		if f == v or f.gone or f.fade > 0 or f.lying or f.inside != v.inside:
			continue
		var fp: Vector2 = f.pos
		if absf(fp.length() - p.length()) >= 10.0:
			continue
		var d := _dc(float(_col(p)), fp)          # (where I am, from them)
		if absf(d) < 6.0:
			if absf(d) < 0.5:
				return 1.0 if v.fseed > f.fseed else -1.0
			return signf(d)
	return 0.0

## standing in the street over column c
func _street_at(c: float) -> Vector2:
	return _at(c, float(game.builds.ground_row(int(c))), 11.0)

## just outside a house: on side `side` (-1 its start, 1 its end), or the side nearer p
func _outside(h: Dictionary, side: float) -> Vector2:
	var c := float(int(h["x0"])) - 8.0 if side < 0.0 else float(int(h["x0"]) + int(h["w"])) + 7.0
	return _street_at(c)

func _nearer_side(h: Dictionary, p: Vector2) -> float:
	var x0 := float(int(h["x0"]))
	return -1.0 if absf(_dc(x0, p)) < absf(_dc(x0 + float(int(h["w"])), p)) else 1.0

## a day's walking: keepers stand at their counters (turning to you); the rest go where the hour says,
## stepping through a house's side to go in, out, or past it, potter about where they are, and run from foes
func _walk(v) -> void:
	if v.say_t > 0:
		v.say_t -= 1
	if v.offer_t > 0:
		v.offer_t -= 1
		if v.offer_t == 0:
			v.offer = {}
	# stepping through a house's side: fade out, move, fade in
	if v.fade > 0:
		v.fade -= 1
		if v.fade == FADE:
			v.pos = v.fade_to
			v.vx = 0.0
			v.vy = 0.0
			v.inside = v.fade_in
			v.goal_c = float(_col(v.pos))
			v.idle_t = randi_range(20, 120)
			v.block_t = 0
			v.lying = v.lie_next
			v.lie_next = false
			v.asleep = v.lying
		return
	# lying down asleep: still till morning (or till something sends them out)
	if v.lying:
		# (user, 26 Nov: "a villager house got burned down while he was in it and he just stayed floating in the air
		# sleeping"): the bed or floor gone from under them, or fire beside them, wakes them where they are, to fall
		if v.lie_ok and (game.frame + v.fseed) % 20 == 0 and game.in_grid(v.pos, 24.0) and not _sleeper_safe(v):
			v.wake_at = Vector2.ZERO
			_get_up(v)
			stats["woke_unsafe"] = int(stats.get("woke_unsafe", 0)) + 1
			if v.say_t <= 0:
				_say(v, ["Fire! Fire!", "My house!", "Wha-! Where's the floor?"][randi() % 3], 90)
			return
		var hl := hour_at(v.pos)
		if is_night(hl) and want_place(v, hl) == v.house and v.inside == v.house and _foe_near(v.pos, 50.0) == null:
			v.asleep = true
			return
		_get_up(v)
	if v.role == "guard":
		_guard(v)
		return
	if not game.in_grid(v.pos, 12.0):
		# outside the simulated neighbourhood (and the view): no walking, but they still keep the hours
		if not v.keeper and game.frame % 30 == v.fseed % 30:
			var hr0 := hour_at(v.pos)
			var pl0 := want_place(v, hr0)
			if pl0 != v.inside:
				if not pl0.is_empty():
					v.pos = _spot_in(pl0)
				elif not v.inside.is_empty():
					v.pos = _outside(v.inside, _nearer_side(v.inside, game.player.pos))
				v.inside = pl0
				v.vx = 0.0
				v.vy = 0.0
				v.goal_c = float(_col(v.pos))
				stats["moved_off"] = int(stats.get("moved_off", 0)) + 1
			v.asleep = is_night(hr0) and not v.inside.is_empty() and v.inside == v.house
			if v.asleep and not v.lying:
				_lie_down(v, true)
			elif not v.asleep and v.lying:
				_get_up(v)
		return
	var p: Vector2 = v.pos
	var a := atan2(p.y, p.x)
	v.vy = minf(v.vy + 0.17 * game.gravity_at(p), 5.0)
	var want := 0.0
	v.asleep = false
	if v.keeper:
		if p.distance_to(game.player.pos) < 70.0:
			v.facing = 1 if (game.player.pos - p).dot(game.basis_r(a)) > 0.0 else -1
		elif v.role == "smithy" and game.frame % 45 == v.fseed % 45 and p.distance_to(game.player.pos) < 320.0:
			# the smith at the anvil, by day: a spray of sparks now and then
			var hk := hour_at(p)
			if hk > 8.0 and hk < 18.0:
				var at: Vector2 = p + game.basis_r(a) * float(v.facing) * 6.0 + game.basis_d(a) * 1.0
				for k in 7:
					game._particle(at, game.basis_r(a) * (randf() - 0.5) * 1.8 - game.basis_d(a) * randf() * 1.3, 14 + randi() % 16,
						Color(1.0, 0.75 + randf() * 0.2, 0.3), true, 0.06)
	else:
		var hr := hour_at(p)
		var place := want_place(v, hr)
		var foe = _foe_near(p, 70.0) if v.inside.is_empty() else null
		if foe != null:
			want = -signf((foe.pos - p).dot(game.basis_r(a))) * 1.25
			if v.say_t <= 0 and randf() < 0.01:
				_say(v, ["Help!", "Run!", "Get away from me!"][randi() % 3], 90)
			stats["fled"] = int(stats.get("fled", 0)) + 1
		elif v.talk_t > 0:
			v.talk_t -= 1
			v.facing = 1 if (game.player.pos - p).dot(game.basis_r(a)) > 0.0 else -1
		elif place != v.inside:
			if not v.inside.is_empty():
				# out of where they are first, on the side toward where they're going
				var side := _nearer_side(v.inside, p)
				if not place.is_empty():
					side = signf(_dc(float(int(place["x0"]) + int(place["w"]) / 2), p))
				_step(v, _outside(v.inside, side), STREET)
				stats["went_out"] = int(stats.get("went_out", 0)) + 1
				return
			# to the house, and in through its side (or past any house in the way)
			var mid := float(int(place["x0"]) + int(place["w"]) / 2)
			var dc := _dc(mid, p)
			var s := signf(dc)
			if absf(dc) < float(int(place["w"])) * 0.5 + 4.0:
				_step(v, _spot_in(place), place)
				stats["went_in"] = int(stats.get("went_in", 0)) + 1
				return
			if v.hit_wall:
				var hb := _house_at(v.town, float(_col(p)) + s * 8.0)
				if hb == place:
					_step(v, _spot_in(place), place)
					stats["went_in"] = int(stats.get("went_in", 0)) + 1
					return
				if not hb.is_empty():
					_step(v, _outside(hb, s), STREET)             # (through a neighbour's house)
					stats["passed"] = int(stats.get("passed", 0)) + 1
					return
				v.block_t += 1
				if v.on_ground and v.block_t % 25 == 1:
					v.vy = -1.75                                 # (a ledge in the way: up it)
				if v.block_t > 90:
					_step(v, _spot_in(place), place)             # (stuck: they know another way)
					stats["stuck"] = int(stats.get("stuck", 0)) + 1
					return
			want = -s * HURRY                                  # (basis_r points toward FEWER columns)
		elif not v.inside.is_empty() and is_night(hr):
			v.asleep = v.inside == v.house                    # (asleep where they live: in bed)
			if v.asleep:
				_lie_down(v, false)
				return
		elif (v.idle_t > 0 or absf(v.vx) < 0.05) and (game.frame + v.fseed) % 12 == 0 and _crowd_side(v) != 0.0:
			# (standing on top of someone: step aside, a little way)
			var aside := _crowd_side(v)
			# (not into a wall or off a drop when the other side is open: 26 Nov, one kept stepping toward a wall
			# two cells off and stood stuck on the other. `aside` counts columns; basis_r points to fewer)
			if _blocked(v, -aside) and not _blocked(v, aside):
				aside = -aside
			v.goal_c = float(_col(p)) + aside * randf_range(8.0, 16.0)
			v.idle_t = 0
			stats["stepped_aside"] = int(stats.get("stepped_aside", 0)) + 1
		elif v.idle_t > 0:
			v.idle_t -= 1
		else:
			var dc2 := _dc(v.goal_c, p)
			if absf(dc2) < 3.0:
				v.idle_t = randi_range(60, 260)
				_new_goal(v)
			else:
				want = -signf(dc2) * WALK
				if v.hit_wall or (v.inside.is_empty() and _drop_ahead(v, -signf(dc2))):
					v.idle_t = randi_range(20, 90)
					_new_goal(v, -signf(dc2))
					want = 0.0
	v.vx += (want - v.vx) * 0.25
	if absf(want) > 0.05:
		v.facing = 1 if want > 0.0 else -1
		v.anim += absf(v.vx) * 0.16
	game.move_body(v)

# ------------------------------------------------------------------ guards ---
## a guard's tick: after the nearest foe in the village (`_guard_target`), striking with the spear in reach;
## else walking the village end to end, a while at each end; through a house in the way; a lantern after dark
func _guard(v) -> void:
	if v.strike_t > 0:
		v.strike_t -= 1
	if not game.in_grid(v.pos, 12.0):
		return
	var p: Vector2 = v.pos
	var a := atan2(p.y, p.x)
	var up := Vector2(cos(a), sin(a))
	v.vy = minf(v.vy + 0.17 * game.gravity_at(p), 5.0)
	var want := 0.0
	v.asleep = false
	if is_night(hour_at(p)) and p.distance_to(game.cam_c) < 500.0:
		game.lights.append([p + up * 6.0, 44.0, Color(1.6, 1.15, 0.6)])
	var foe = _guard_target(v)
	if foe != null:
		var d: Vector2 = foe.pos - p
		var along := d.dot(game.basis_r(a))
		# (a dead zone: with the foe right over or under them its side flickered, and they spun on the spot;
		# user, 26 Nov: "the town gaurds get stuck rapidly flipping left and right when im near them")
		if absf(along) > GUARD_TURN:
			v.facing = 1 if along > 0.0 else -1
		var reach_up: bool = absf(d.dot(up)) < 16.0 + foe.h * 0.5
		if absf(along) < GUARD_REACH + foe.w * 0.5 and reach_up:
			if v.strike_t <= 0:
				v.strike_t = GUARD_EVERY
				game._hurt_enemy(foe, GUARD_HIT, float(v.facing) * 1.6, -0.5)
				game.audio.play("hit", foe.pos, 0.6, 1.1)
				for k in 5:
					game._particle(foe.pos - game.basis_r(a) * float(v.facing) * foe.w * 0.4, game.basis_r(a) * float(v.facing) * randf_range(0.3, 1.2) + up * randf_range(-0.4, 0.6), 10 + randi() % 8, Color(1.0, 0.95, 0.8), true, 0.05)
				stats["guard_hits"] = int(stats.get("guard_hits", 0)) + 1
		elif absf(along) > GUARD_REACH * 0.5:
			want = signf(along) * 1.25
			if v.hit_wall and v.on_ground:
				var s0 := -signf(along)                       # (in columns: basis_r points toward fewer)
				var hb := _house_at(v.town, float(_col(p)) + s0 * 8.0)
				if not hb.is_empty():
					_step(v, _outside(hb, s0), STREET)
					return
				v.vy = -1.9
		if v.say_t <= 0 and randf() < 0.008:
			_say(v, ["For %s!" % String(v.town.get("name", "the village")), "Back, beast!", "Stand clear, mage!", "To me!"][randi() % 4], 90)
	elif v.idle_t > 0:
		v.idle_t -= 1
	else:
		var t: Dictionary = v.town
		var ends := [float(int(t["x0"]) + 10), float(int(t["x0"]) + int(t["w"]) - 10)]
		var dc := _dc(v.goal_c, p)
		if absf(dc) < 3.0 or absf(dc) > float(int(t["w"])) + 40.0:
			v.idle_t = randi_range(90, 260)
			v.goal_c = ends[1] if absf(_dc(ends[0], p)) < absf(_dc(ends[1], p)) else ends[0]
		else:
			want = -signf(dc) * WALK
			if v.hit_wall and v.on_ground:
				var hb2 := _house_at(v.town, float(_col(p)) + signf(dc) * 8.0)
				if not hb2.is_empty():
					_step(v, _outside(hb2, signf(dc)), STREET)       # (through the house in the way)
					return
				v.vy = -1.75
	v.vx += (want - v.vx) * 0.25
	if absf(want) > 0.05:
		v.facing = 1 if want > 0.0 else -1
		v.anim += absf(v.vx) * 0.16
	game.move_body(v)

## the foe a guard goes for: the nearest within GUARD_SIGHT that's in the village or close to its ends; never a
## boss, nor a wild thing that leaves folk alone (prey, the neutral) unless roused
func _guard_target(v):
	if game.testing and not test_guards:
		return null
	var t: Dictionary = v.town
	var best = null
	var bd := GUARD_SIGHT
	for e in game.enemies:
		if e.dead or e.boss or e.under:
			continue
		if e.type.begins_with("c_") and e.d.has("def"):
			var tmp := String(e.d["def"].get("temper", "predator"))
			if (tmp == "prey" or tmp == "neutral") and not e.provoked:
				continue
		var dd: float = (e.pos as Vector2).distance_to(v.pos)
		if dd >= bd:
			continue
		# (only what they could get at: not a foe in a cave under the street or up in the sky)
		if absf((e.pos as Vector2).length() - (v.pos as Vector2).length()) > GUARD_HIGH + e.h * 0.5:
			continue
		var off := fposmod(float(_col(e.pos)) - float(int(t["x0"])) + float(GUARD_ROAM), float(Defs.NS))
		if off > float(int(t["w"]) + 2 * GUARD_ROAM):
			continue
		bd = dd
		best = e
	return best

## step through a house's side: fade out here, come out (or in) at `to`
func _step(v, to: Vector2, into: Dictionary) -> void:
	v.fade = FADE * 2
	v.fade_to = to
	v.fade_in = into

## to bed: their own bed if it's still there (its pillow end where the head goes), else a bedroll on the
## floor of the room they're in. `now`: straight there (out of sight, or when the village is filled);
## otherwise a fade, like going through a door.
func _lie_down(v, now: bool) -> void:
	var h: Dictionary = v.inside
	var to: Vector2
	var b: Dictionary = v.bed
	var in_bed := not b.is_empty()
	if in_bed:
		var flip := bool(b["flip"])
		var bw := int(b["w"])
		var mid := float(int(b["c"])) + (11.0 if not flip else float(bw) - 12.0)
		var head := float(int(b["c"])) + (4.0 if not flip else float(bw) - 5.0)
		var row := int(b["row"])
		# (taken or burnt? the collision grid knows where furniture is; out of it, trust it's there. A chest
		# set down in front of it, or someone already in it, and they sleep on the floor instead)
		if game._bg_at(int(head), row - 5) == 0 and game._bg_at(int(mid), row - 5) == 0:
			in_bed = false
		elif _chest_near(_at(mid, float(row - 4), 0.0), float(bw) * 0.5 + 6.0) or _taken(_at(mid, float(row - 6), 2.5), h, float(bw) * 0.5, v):
			in_bed = false
		else:
			to = _at(mid, float(row - 6), 2.5)
			v.lie_head = _at(head, float(row - 6), 2.5)
			v.wake_at = _at(mid, float(row + 1), 9.0)
	if not in_bed:
		var x0 := float(int(h["x0"]) + 12)
		var x1 := float(int(h["x0"]) + int(h["w"]) - 12)
		var c := clampf(float(_col(v.pos)), minf(x0, x1), maxf(x0, x1))
		# (the roomiest bit of floor: farthest from the others asleep there and from any chest)
		var room := _clearance(_at(c, float(h["floor"]), 4.5), h, v, 40.0)
		for k in 12:
			var cc := minf(x0, x1) + absf(x1 - x0) * (float(k) + 0.5) / 12.0
			var rk := _clearance(_at(cc, float(h["floor"]), 4.5), h, v, 40.0)
			if rk > room + 0.5:
				room = rk
				c = cc
		to = _at(c, float(h["floor"]) - 1.0, 4.0)
		var side := 1.0 if (v.fseed % 2) == 0 else -1.0
		v.lie_head = _at(c + side * 7.0, float(h["floor"]) - 1.0, 4.0)
		v.wake_at = _at(c, float(h["floor"]), 9.0)
	v.bedroll = not in_bed
	v.lie_ok = false
	if now:
		v.pos = to
		v.lying = true
		v.asleep = true
	else:
		_step(v, to, h)
		v.lie_next = true
	v.vx = 0.0
	v.vy = 0.0
	stats["to_bed" if in_bed else "bedroll"] = int(stats.get("to_bed" if in_bed else "bedroll", 0)) + 1

## is a chest within `cols` columns of p, at about its height (so a sleeper there would hide it)?
func _chest_near(p: Vector2, cols: float) -> bool:
	for ch in game.chests:
		var cp: Vector2 = ch.pos
		if absf(cp.length() - p.length()) < 14.0 and absf(_dc(float(_col(p)), cp)) < cols:
			return true
	return false

## up again, standing beside where they slept
func _get_up(v) -> void:
	v.lying = false
	v.asleep = false
	if v.wake_at != Vector2.ZERO:
		v.pos = v.wake_at
	v.vx = 0.0
	v.vy = 0.0
	v.goal_c = float(_col(v.pos))

## how visible someone is (fading through a house's side)
static func alpha_of(v) -> float:
	if v.fade <= 0:
		return 1.0
	if v.fade > FADE:
		return float(v.fade - FADE) / float(FADE)
	return 1.0 - float(v.fade) / float(FADE)

## the column offset from p to column c (the short way round). Columns count with the angle, and a body's vx
## runs along basis_r, toward FEWER columns: to walk toward c, want -sign(offset).
func _dc(c: float, p: Vector2) -> float:
	return fposmod(c - float(_col(p)) + Defs.NS * 0.5, float(Defs.NS)) - Defs.NS * 0.5

## somewhere else to walk to: along the village, or across the room they're in (on one side, if given)
func _new_goal(v, side := 0.0) -> void:
	var x0: float
	var x1: float
	if not v.inside.is_empty():
		x0 = float(int(v.inside["x0"]) + 6)
		x1 = float(int(v.inside["x0"]) + int(v.inside["w"]) - 6)
	else:
		x0 = float(int(v.town["x0"]) + 8)
		x1 = float(int(v.town["x0"]) + int(v.town["w"]) - 8)
	var here := float(_col(v.pos))
	for k in 8:
		var c := x0 + randf() * maxf(1.0, fposmod(x1 - x0, float(Defs.NS)))
		if (side == 0.0 or signf(_dc(c, v.pos)) == side) and (k >= 6 or not _taken(_at(c, 0.0, 0.0).normalized() * v.pos.length(), v.inside, 8.0, v)):
			v.goal_c = c
			return
	v.goal_c = here + side * randf_range(8.0, 30.0)

func _drop_ahead(v, dir: float) -> bool:
	var a := atan2(v.pos.y, v.pos.x)
	var ahead: Vector2 = v.pos + game.basis_r(a) * dir * 7.0
	for k in range(8, 16, 2):
		var t: int = game.type_at(ahead + game.basis_d(a) * float(k))
		if Defs.KIND[t] == Defs.K_SOLID or Defs.KIND[t] == Defs.K_POWDER:
			return false
	return true

## a wall at body height or a drop within a few cells, going `dir` (basis_r terms, as `_drop_ahead`)
func _blocked(v, dir: float) -> bool:
	if _drop_ahead(v, dir):
		return true
	var a := atan2(v.pos.y, v.pos.x)
	for k in [3.0, 6.0, 9.0]:
		for up in [-3.0, 2.0]:
			var t: int = game.type_at(v.pos + game.basis_r(a) * dir * k + game.basis_d(a) * up)
			if Defs.KIND[t] == Defs.K_SOLID:
				return true
	return false

func _foe_near(p: Vector2, r: float):
	for e in game.enemies:
		if not e.dead and not e.under and (e.pos as Vector2).distance_to(p) < r and not game.calm_foe(e, game.player):
			return e
	return null

func _say(v, text: String, ticks := 300) -> void:
	v.say = text
	v.say_t = ticks

# ------------------------------------------------------------------ talking ---

## F near someone: a keeper takes a letter that's for them, or opens their shop; the asker offers their
## request (a second F takes it) or takes it back done; anyone else stops for a word
func talk(m) -> bool:
	var best = null
	var bd := TALK
	for v in folk:
		var d: float = v.pos.distance_to(m.pos)
		if d < bd and v.fade == 0:
			bd = d
			best = v
	if best == null:
		return false
	if best.keeper:
		if _deliver_to(best):
			return true
		open_shop(best)
		return true
	best.talk_t = 240
	if best.asker and not best.asleep and _request_talk(best):
		_meet(best)
		return true
	best.talks += 1
	_say(best, line_for(best), 330)
	if not best.asleep:
		_meet(best)
	stats["talked"] = int(stats.get("talked", 0)) + 1
	return true

# ------------------------------------------------------------------ memory ---
# The folk remember you: planet_state["folk_known"][their seed] = {"met": times you've talked, "helped": your
# requests they've had done}, and each village how much you've done for it: planet_state["town_rep"][its
# seed] = {"n": requests done there, "last": who for}. They greet you by it, the village's shops give a friend
# a better price (`price_of`), and you know the names of the folk you've met (overlay's name tags).

func memory(v) -> Dictionary:
	var fk: Dictionary = game.planet_state.get("folk_known", {})
	return fk.get(str(v.fseed), {})

func knows(v) -> bool:
	return int(memory(v).get("met", 0)) > 0

func _meet(v) -> void:
	var fk: Dictionary = game.planet_state.get("folk_known", {})
	var m: Dictionary = fk.get(str(v.fseed), {})
	m["met"] = int(m.get("met", 0)) + 1
	fk[str(v.fseed)] = m
	game.planet_state["folk_known"] = fk

func rep(t: Dictionary) -> Dictionary:
	var tr: Dictionary = game.planet_state.get("town_rep", {})
	return tr.get(str(t["seed"]), {})

## what a thing costs from this keeper: a friend of the village (5% for every request done there, up to a
## quarter) pays less
func price_of(v, it: Dictionary) -> int:
	var n := int(rep(v.town).get("n", 0))
	return maxi(1, int(round(float(int(it["price"])) * (1.0 - minf(0.25, 0.05 * float(n))))))

## a greeting that knows you: a stranger's introduction, a welcome back, a friend's
func _hello(v, r: RandomNumberGenerator, hr: float) -> String:
	var mem := memory(v)
	var met := int(mem.get("met", 0))
	var rp := rep(v.town)
	var town_name := String(v.town["name"])
	if met == 0:
		return "%s I'm %s. Not seen you in %s before, mage." % [["Hello there!", "Oh! A mage.", "Well met."][r.randi_range(0, 2)], v.name, town_name]
	if int(mem.get("helped", 0)) > 0:
		return ["My friend the mage!", "Ah, it's you! Good to see you.", "There's my favourite mage."][r.randi_range(0, 2)]
	if int(rp.get("n", 0)) > 0 and r.randf() < 0.5:
		return "You're the one who helped %s! %s" % [String(rp.get("last", "us")), "Thank you." if r.randf() < 0.5 else "Folk talk of nothing else."]
	if met >= 3:
		return ["Back again, mage?", "You again! Hello.", "Hello again."][r.randi_range(0, 2)]
	return (["Morning!", "Good day.", "Well met, mage."] if hr > 5.0 and hr < 17.0 else ["Evening.", "Late to be out."])[r.randi_range(0, 1)]

## what someone says: a greeting, then (in turn, as you keep asking) a rumour about the nearest guardian, a
## dungeon, this world's ore, its danger, the village's shops, or just village talk
func line_for(v) -> String:
	if v.role == "guard":
		var gr := RandomNumberGenerator.new()
		gr.seed = v.fseed + v.talks * 977
		return "%s, guard of %s. %s" % [v.name, String(v.town.get("name", "the village")), GUARD_LINES[gr.randi_range(0, GUARD_LINES.size() - 1)]]
	if v.asleep:
		return "Mmh... wha'? It's the middle of the night. Come back in the morning."
	var r := RandomNumberGenerator.new()
	r.seed = v.fseed + v.talks * 977
	var hr := hour_at(v.pos)
	var hello := _hello(v, r, hr)
	if not knows(v):
		return hello                                  # (the first time, they just introduce themselves)
	var topics := ["lair", "dungeon", "ore", "hazard", "shops", "chat", "secret"]
	var topic: String = topics[(v.talks + r.randi_range(0, 6)) % topics.size()]
	var said := ""
	match topic:
		"lair":
			# (guardians are called at an altar now, summoning.gd: who can be, and where)
			var cb: Array = game.summoning.callable_biomes()
			if not cb.is_empty():
				var gb: String = cb[r.randi_range(0, cb.size() - 1)]
				var bdef: Dictionary = Defs.BOSSES[gb]
				said = "They say %s, %s, answers anyone who lays its sigil on an altar in the %s. Few come back the same." % [bdef["name"], bdef["title"], String(Defs.BIOMES[gb]["name"]) if Defs.BIOMES.has(gb) else gb]
		"dungeon":
			if not game.builds.warden_list.is_empty():
				var w: Dictionary = game.builds.warden_list[r.randi_range(0, game.builds.warden_list.size() - 1)]
				said = "There's an old crypt %s %s. Something guards its deepest room." % [_far((w["pos"] as Vector2).distance_to(v.pos)), _way(v.pos, w["pos"])]
		"ore":
			var ko: int = Defs.kind_ore(game.planet)
			if ko >= 0:
				said = "The miners go after %s here. Nowhere else has it, they say." % Defs.NAMES[ko]
			else:
				said = "Copper near the top, wisp ore deep down. Mind the heat below."
		"hazard":
			for hz in Defs.HAZARDS:
				if float(game.clim.get(hz, 0.0)) > 0.0:
					said = "%s is no friend out there. Folk who wander far carry a %s." % [Defs.HAZARDS[hz]["name"], _ward_name(hz)]
			if said == "" and float(game.clim.get("heat", 0.0)) > 0.0:
				said = "The air out there would cook you. Get a Heat Ward."
		"secret":
			# a workshop's secret, as a riddle (it goes into your notes: the station's panel shows it)
			var sp: Dictionary = game.workshops.unheard(r)
			if not sp.is_empty():
				var who: String = ["An old smith once told me", "My gran swore by this", "A traveller said", "They say in the next village"][r.randi_range(0, 3)]
				said = "%s: \"%s\"" % [who, String(sp["hint"])]
				game.workshops.hear(sp)
		"shops":
			for h in v.town["houses"]:
				if Defs.SHOPS.has(h["role"]) and not bool(h["ruined"]):
					said = "The %s is open, if you've coins to spend. Or things to sell." % String(Defs.SHOPS[h["role"]]["title"]).to_lower()
					break
	if said == "":
		said = ["The harvest's late this year.", "My gran says the stars used to be closer.", "Don't dig under your own house. Ask me how I know.",
			"Wisps in the marsh lead folk astray.", "Bring me a draught and I'll tell you a secret.", "Strange lights over the hills last night."][r.randi_range(0, 5)]
	return "%s %s" % [hello, said]

func _ward_name(hz: String) -> String:
	var wid := String(Defs.HAZARDS[hz]["ward"])
	for rr in Defs.RECIPES:
		if rr["id"] == wid:
			return String(rr["name"])
	return "ward"

func _far(d: float) -> String:
	return "not far" if d < 900.0 else ("a fair walk" if d < 2600.0 else "far off")

## east or west of p (along the planet's turn)
func _way(p: Vector2, q: Vector2) -> String:
	var d := fposmod(atan2(q.y, q.x) - atan2(p.y, p.x) + PI, TAU) - PI
	return "to the east" if d > 0.0 else "to the west"

# ----------------------------------------------------------------- requests ---

## which resident of a village has a request for you (it moves on to another as you finish them)
func asker_index(t: Dictionary) -> int:
	var rn: Dictionary = game.planet_state.get("req_n", {})
	return posmod(hash([int(t["seed"]), int(rn.get(str(t["seed"]), 0))]), maxi(1, resident_count(t)))

func requests() -> Array:
	if not game.planet_state.has("requests"):
		game.planet_state["requests"] = []
	return game.planet_state["requests"]

func active_from(v) -> Variant:
	for rq in requests():
		if int(rq["from"]) == int(v.fseed):
			return rq
	return null

## the mark over an asker (overlay draws it): "offer" a request for you (a gold "!"), "wait" one you took and
## haven't done (a grey "?"), "ready" done, to hand in (a gold "?"), "" nothing (asleep, or hands full)
func mark_of(v) -> String:
	if not v.asker or v.asleep or v.fade > 0:
		return ""
	var rq = active_from(v)
	if rq != null:
		return "ready" if _done(rq) else "wait"
	return "offer" if requests().size() < Defs.MAX_REQUESTS else ""

## the request a village's asker has, made from the village's seed and how many you've done there:
## {kind, from (their seed), who, town (seed), town_name, text, reward, and per kind: mat/n, foe/n/got, to (a
## village's seed)/to_name/to_role}
func make_request(v, kind_pick := "") -> Dictionary:
	var t: Dictionary = v.town
	var rn: Dictionary = game.planet_state.get("req_n", {})
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(t["seed"]), int(rn.get(str(t["seed"]), 0)), 7])
	var rq := {"from": int(v.fseed), "who": String(v.name), "town": int(t["seed"]), "town_name": String(t["name"])}
	var kinds := ["fetch", "fetch"]
	var foes: Array = Defs.creatures_of(String(t.get("biome", "")))
	if not foes.is_empty():
		kinds.append("hunt")
	var others := []
	for t2 in game.builds.towns:
		if bool(t2["living"]) and int(t2["seed"]) != int(t["seed"]) and (not _house_of(t2, "shop").is_empty() or not _house_of(t2, "tavern").is_empty()):
			others.append(t2)
	if not others.is_empty():
		kinds.append("deliver")
	var kind: String = kinds[r.randi_range(0, kinds.size() - 1)]
	if kind_pick != "" and kinds.has(kind_pick):
		kind = kind_pick
	rq["kind"] = kind
	match kind:
		"fetch":
			var f: Array = Defs.FETCH[r.randi_range(0, Defs.FETCH.size() - 1)]
			rq["mat"] = int(f[0])
			rq["n"] = int(f[1])
			rq["reward"] = 15 + int(f[1]) / 2
			rq["text"] = "Could you bring me %d %s? I'd pay you %d coins." % [int(f[1]), Defs.NAMES[int(f[0])], rq["reward"]]
		"hunt":
			var fid: String = foes[r.randi_range(0, foes.size() - 1)]
			rq["foe"] = "c_" + fid
			rq["n"] = r.randi_range(2, 4)
			rq["got"] = 0
			rq["reward"] = 25 + 10 * int(rq["n"])
			rq["text"] = "%ss have been at our stores. Thin them out, %d of them, and %d coins are yours." % [String(Defs.CREATURES[fid]["name"]), rq["n"], rq["reward"]]
		"deliver":
			var t3: Dictionary = others[r.randi_range(0, others.size() - 1)]
			var role := "shop" if not _house_of(t3, "shop").is_empty() else "tavern"
			rq["to"] = int(t3["seed"])
			rq["to_name"] = String(t3["name"])
			rq["to_role"] = role
			var dist := _cdist(int(t["x0"]), int(t3["x0"]))
			rq["reward"] = 30 + dist / 60
			rq["text"] = "Would you take this letter to the %s in %s? It's %s %s. %d coins when it's there." % [String(Defs.SHOPS[role]["title"]).to_lower(),
				t3["name"], _far(float(dist)), _way(_at(float(int(t["x0"])), 0.0, 0.0), _at(float(int(t3["x0"])), 0.0, 0.0)), rq["reward"]]
	return rq

## the asker: offer a request (a second F takes it), remind you of one, or take it back done
func _request_talk(v) -> bool:
	var rq = active_from(v)
	if rq != null:
		if _done(rq):
			_finish(rq, v)
		else:
			_say(v, _remind(rq), 300)
		return true
	if v.offer.is_empty():
		if requests().size() >= Defs.MAX_REQUESTS:
			return false
		v.offer = make_request(v)
		v.offer_t = 600
		_say(v, String(v.offer["text"]) + "  [F: agree]", 600)
		return true
	take(v)
	return true

## a second F: the request is yours
func take(v) -> void:
	var taken: Dictionary = v.offer if not v.offer.is_empty() else make_request(v)
	v.offer = {}
	v.offer_t = 0
	requests().append(taken)
	_say(v, ["Thank you!", "Bless you, mage.", "I knew you'd help."][randi() % 3], 180)
	game.ui.toast("Request taken: %s" % short(taken), Color(1, 0.9, 0.55), 3.5)
	stats["taken"] = int(stats.get("taken", 0)) + 1

func _done(rq: Dictionary) -> bool:
	match String(rq["kind"]):
		"fetch": return int(game.player.inv[int(rq["mat"])]) >= int(rq["n"])
		"hunt": return int(rq["got"]) >= int(rq["n"])
	return false

func _remind(rq: Dictionary) -> String:
	match String(rq["kind"]):
		"fetch":
			return "Still %d %s, if you can. You've %d." % [int(rq["n"]), Defs.NAMES[int(rq["mat"])], int(game.player.inv[int(rq["mat"])])]
		"hunt":
			return "%d of %d so far. Keep at it." % [int(rq["got"]), int(rq["n"])]
		"deliver":
			return "The letter's for the %s in %s." % [String(Defs.SHOPS[rq["to_role"]]["title"]).to_lower(), rq["to_name"]]
	return ""

## the reward: coins, and now and then a Healing Draught; the village's asker moves on to someone else
func _finish(rq: Dictionary, v) -> void:
	if String(rq["kind"]) == "fetch":
		game.player.inv[int(rq["mat"])] -= int(rq["n"])
	requests().erase(rq)
	game.items["coins"] = int(game.items.get("coins", 0)) + int(rq["reward"])
	var extra := ""
	var rh := posmod(hash([int(rq["from"]), int(rq["reward"])]), 3)
	if rh == 0:
		game.items["potion"] = int(game.items.get("potion", 0)) + 1
		extra = " and a Healing Draught"
	elif rh == 1:
		# a keeper's recipe, taught as thanks (one not yet known, of any trade sold on this world)
		var tl := []
		for r in game.shop_recipes():
			if not game.knows(r):
				tl.append(String(r["id"]))
		if not tl.is_empty():
			game.learn(String(tl[posmod(int(rq["from"]), tl.size())]), "taught as thanks")
			extra = " and a recipe"
	var rn: Dictionary = game.planet_state.get("req_n", {})
	rn[str(rq["town"])] = int(rn.get(str(rq["town"]), 0)) + 1
	game.planet_state["req_n"] = rn
	# remembered: by the one you helped, and by their village
	var fk: Dictionary = game.planet_state.get("folk_known", {})
	var fm: Dictionary = fk.get(str(rq["from"]), {})
	fm["helped"] = int(fm.get("helped", 0)) + 1
	fm["met"] = maxi(1, int(fm.get("met", 0)))
	fk[str(rq["from"])] = fm
	game.planet_state["folk_known"] = fk
	var tr: Dictionary = game.planet_state.get("town_rep", {})
	tr[str(rq["town"])] = {"n": int((tr.get(str(rq["town"]), {}) as Dictionary).get("n", 0)) + 1, "last": String(rq["who"])}
	game.planet_state["town_rep"] = tr
	_maybe_grow(int(rq["town"]))
	for f in folk:
		if int(f.town["seed"]) == int(rq["town"]) and not f.keeper:
			f.asker = f.idx == asker_index(f.town)
	if v != null:
		_say(v, ["Wonderful, thank you!", "Just what I needed.", "You're a good sort, mage."][randi() % 3], 200)
	game.audio.play("coin")
	game.ui.toast("Request done: +%d coins%s" % [int(rq["reward"]), extra], Color(1, 0.85, 0.4), 3.5)
	stats["done"] = int(stats.get("done", 0)) + 1
	game.save_game()

## grow village `tseed` if you've helped it enough since it last grew (true if a house was planned)
func _maybe_grow(tseed: int) -> bool:
	var t := {}
	for tt in game.builds.towns:
		if int(tt["seed"]) == tseed and bool(tt["living"]):
			t = tt
	if t.is_empty() or no_grow:
		return false
	var gr: Dictionary = game.planet_state.get("grown", {})
	var g := int(gr.get(str(tseed), 0))
	var n := int((game.planet_state.get("town_rep", {}) as Dictionary).get(str(tseed), {}).get("n", 0))
	if g >= GROW_AT.size() or n < int(GROW_AT[g]):
		return false
	var h: Dictionary = game.builds.grow_house(t, g)
	if h.is_empty():
		return false
	gr[str(tseed)] = g + 1
	game.planet_state["grown"] = gr
	h["new"] = true
	stats["growing"] = int(stats.get("growing", 0)) + 1
	game.ui.toast("Word of your help spreads: %s is growing" % String(t["name"]), Color(1.0, 0.88, 0.5), 4.0)
	if rebuild.job.is_empty() and rebuild._look.is_empty():
		rebuild.look_at(h, t)
	return true

## planned again on loading: each village's grown houses, in the order they grew (the cells are in the world)
func replay_growth() -> void:
	var gr: Dictionary = game.planet_state.get("grown", {})
	for tt in game.builds.towns:
		var g := int(gr.get(str(tt["seed"]), 0))
		for q in g:
			game.builds.grow_house(tt, q)

## a new house is built (rebuild.gd): a family moves in, and another guard comes to walk the village
func move_in(t: Dictionary, h: Dictionary) -> void:
	if not _peopled.has(int(t["seed"])):
		return
	var hi := (t["houses"] as Array).find(h)
	var n := 0
	for f in folk:
		if int(f.town["seed"]) == int(t["seed"]) and not f.keeper and f.role != "guard":
			n += 1
	for k in 2:
		if n >= MAX_FOLK + 2:
			break
		var v = _add(t, h, STREET, hseed(t, hi, k + 1), "folk", false)
		v.idx = n
		var beds: Array = h.get("beds", [])
		if k < beds.size():
			v.bed = beds[k]
		_place(v, h)
		n += 1
	var ng := 0
	for f2 in folk:
		if int(f2.town["seed"]) == int(t["seed"]) and f2.role == "guard":
			ng += 1
	if ng < guard_count(t):
		var gv = _add(t, {}, STREET, hseed(t, 900 + ng, 0), "folk", false)
		gv.role = "guard"
		gv.idx = -1 - ng
		_place(gv, STREET)

## a letter for this keeper? Then it's handed over
func _deliver_to(k) -> bool:
	for rq in requests():
		if String(rq["kind"]) == "deliver" and int(rq["to"]) == int(k.town["seed"]) and String(rq["to_role"]) == String(k.role):
			_say(k, "A letter? From %s in %s! Thank you." % [rq["who"], rq["town_name"]], 220)
			_finish(rq, null)
			return true
	return false

## a creature died: a hunt that wanted it counts it
func on_kill(type: String) -> void:
	for rq in requests():
		if String(rq["kind"]) == "hunt" and String(rq["foe"]) == type and int(rq["got"]) < int(rq["n"]):
			rq["got"] = int(rq["got"]) + 1
			game.ui.toast(short(rq) + (" · done: back to %s" % rq["who"] if int(rq["got"]) >= int(rq["n"]) else ""), Color(1, 0.9, 0.55), 2.5)
			return

## a request in a few words (the HUD's list)
func short(rq: Dictionary) -> String:
	match String(rq["kind"]):
		"fetch": return "%d %s for %s of %s" % [int(rq["n"]), Defs.NAMES[int(rq["mat"])], rq["who"], rq["town_name"]]
		"hunt":
			var nm := String(Defs.CREATURES.get(String(rq["foe"]).substr(2), {}).get("name", "creature"))
			return "Hunt %s %d/%d for %s of %s" % [nm, int(rq["got"]), int(rq["n"]), rq["who"], rq["town_name"]]
		"deliver": return "A letter to the %s in %s, from %s" % [String(Defs.SHOPS[rq["to_role"]]["title"]).to_lower(), rq["to_name"], rq["who"]]
	return ""

# ------------------------------------------------------------------ trading ---

func open_shop(v) -> void:
	shop_of = v
	v.facing = 1 if (game.player.pos - v.pos).dot(game.basis_r(atan2(v.pos.y, v.pos.x))) > 0.0 else -1
	if not knows(v):
		_say(v, "Welcome, stranger. I'm %s. Take a look." % v.name, 220)
	elif int(rep(v.town).get("n", 0)) > 0:
		_say(v, "For a friend of %s, a better price!" % v.town["name"], 220)
	else:
		_say(v, ["Welcome back! What'll it be?", "Back again? Come in.", "Good to see you. Take a look."][randi() % 3], 200)
	_meet(v)
	game.state = "shop"
	game.ui.show_shop(v)
	stats["shops"] = int(stats.get("shops", 0)) + 1

func close_shop() -> void:
	shop_of = null
	if game.state == "shop":
		game.state = "play"
	game.ui.hide_shop()

func coins() -> int:
	return int(game.items.get("coins", 0))

func shop_def(v) -> Dictionary:
	var sd := shop_def_for(String(v.role), String(game.planet.get("kind", "temperate")), int(game.planet.get("seed", 0)))
	if sd.is_empty():
		return sd
	# recipes of the keeper's trade (Defs.LEARN "shop"): always listed (a known one shows "yours")
	for r in game.shop_recipes(String(v.role)):
		(sd["sell"] as Array).append({"name": "Recipe: %s" % r["name"], "price": int(Defs.learn_of(r).get("price", 50)), "recipe": String(r["id"])})
	if String(v.role) == "outpost":
		# (an outpost's own goods, crate by crate, into your ship's hold)
		var tr := Defs.trade_of(int(v.town.get("seed", 0)))
		for gd in tr["sells"]:
			(sd["sell"] as Array).append({"name": "%s (a crate)" % Defs.GOODS[gd]["name"], "price": int(tr["sells"][gd]), "good": String(gd)})
	if String(v.role) == "cantina":
		# (the job board: space.gd's offers, taken for nothing, paid when done)
		for jb in game.space.job_offers(int(v.town.get("seed", 0)), String(v.town.get("name", "")), int(v.town.get("sys", -1))):
			(sd["sell"] as Array).append({"name": "Job: %s" % jb["name"], "price": 0, "job": jb})
	return sd

## what this keeper pays for a crate of each good (only an outpost trades in them): {good: price}
func good_pays(v) -> Dictionary:
	if String(v.role) != "outpost":
		return {}
	return Defs.trade_of(int(v.town.get("seed", 0)))["pays"]

## the goods this keeper wants most: {good: price}
func good_wants(v) -> Dictionary:
	if String(v.role) != "outpost":
		return {}
	return Defs.trade_of(int(v.town.get("seed", 0)))["wants"]

## sell a crate of a good from the hold
func sell_good(v, gd: String) -> bool:
	var cargo: Dictionary = game.items.get("cargo", {})
	var pays := good_pays(v)
	if int(cargo.get(gd, 0)) <= 0 or not pays.has(gd):
		return false
	cargo[gd] = int(cargo[gd]) - 1
	if int(cargo[gd]) <= 0:
		cargo.erase(gd)
	game.items["cargo"] = cargo
	game.items["coins"] = coins() + int(pays[gd])
	game.audio.play("coin")
	stats["goods_sold"] = int(stats.get("goods_sold", 0)) + 1
	return true

## a shop's stock on a kind of planet: Defs.SHOPS[role], plus KIND_TRADE's, plus (the smithy, on a world
## with its own ore) an imported ore and a better price for the world's own
static func shop_def_for(role: String, kind: String, pseed: int) -> Dictionary:
	var sd: Dictionary = (Defs.SHOPS.get(role, {}) as Dictionary).duplicate(true)
	if sd.is_empty():
		return sd
	for it in (Defs.KIND_TRADE.get(kind, {}) as Dictionary).get(role, []):
		(sd["sell"] as Array).append(it)
	if role == "smithy" and Defs.KIND_ORES.has(kind):
		var own := int(Defs.KIND_ORES[kind]["mat"])
		var others := []
		for k2 in Defs.KIND_ORES:
			if int(Defs.KIND_ORES[k2]["mat"]) != own:
				others.append(int(Defs.KIND_ORES[k2]["mat"]))
		var im: int = others[posmod(pseed * 7 + 3, others.size())]
		(sd["sell"] as Array).append({"name": "Imported %s x%d" % [Defs.NAMES[im], Defs.IMPORT[0]], "price": Defs.IMPORT[1], "give": {im: Defs.IMPORT[0]}})
		sd["own_ore"] = [own, Defs.OWN_ORE[0], Defs.OWN_ORE[1]]
	return sd

## what the keeper pays for: [material, how many, coins]
func buys(v) -> Array:
	var sd := shop_def(v)
	var out := []
	var own := -1
	if sd.has("own_ore"):
		own = int(sd["own_ore"][0])
		out.append([own, int(sd["own_ore"][1]), int(sd["own_ore"][2])])
	var b: Dictionary = sd.get("buy", {})
	for m in b:
		out.append([int(m), int(b[m][0]), int(b[m][1])])
	if sd.has("ores"):
		for m2 in range(Defs.FIREOPAL, Defs.SILVER + 1):
			if m2 != own:
				out.append([m2, int(sd["ores"][0]), int(sd["ores"][1])])
	return out

## is a thing for sale one you already have (a ward, the Heat Ward, a spell)?
func owned(it: Dictionary) -> bool:
	if it.has("item"):
		return game.items.has(String(it["item"]))
	if it.has("heat_ward"):
		return bool(game.heat_ward)
	if it.has("spell"):
		return game.known.has(String(it["spell"]))
	if it.has("recipe"):
		return game.knows(game.recipe_by_id(String(it["recipe"])))
	if it.has("part"):
		var pid := String(it["part"])
		return game.items.has("part_" + pid) or game.items.has(pid)
	if it.has("repair"):
		var at_dock: bool = game.pocket.active and game.pocket.place == "outpost"     # (docked: your ship's in the hangar)
		return game.skiff == null or game.skiff.missing() == 0 or (game.skiff.pos.distance_to(game.player.pos) > 600.0 and not at_dock)
	if it.has("job"):
		return game.space.has_job(String(it["job"]["id"]))
	return false

## buy the i-th thing the keeper sells
func buy(v, i: int) -> bool:
	var it: Dictionary = shop_def(v)["sell"][i]
	if it.has("job"):
		var took: bool = game.space.take_job(it["job"])
		if took:
			game.save_game()
		return took
	var price := price_of(v, it)
	if coins() < price or owned(it):
		return false
	if it.has("good") and game.cargo_count() >= game.hold_cap():
		game.ui.toast("Your ship's hold is full (%d crates): a bigger hull, with more room closed in, carries more" % game.hold_cap() if game.hold_cap() > 0 else "Crates ride in your ship's hold: you need a skiff", Color(1, 0.7, 0.5), 2.5)
		return false
	game.items["coins"] = coins() - price
	grant(it)
	game.audio.play("coin")
	game.ui.toast("Bought: %s" % it["name"], Color(1, 0.85, 0.4), 2.0)
	stats["bought"] = int(stats.get("bought", 0)) + 1
	game.save_game()
	return true

## what a bought thing does
func grant(it: Dictionary) -> void:
	var m = game.player
	if it.has("give"):
		for mt in it["give"]:
			m.inv[int(mt)] += int(it["give"][mt])
	if it.has("potion"):
		game.items["potion"] = int(game.items.get("potion", 0)) + int(it["potion"])
	if it.has("meal"):
		m.heal_left += float(it["meal"])
	if it.has("rest"):
		m.heal_left = 0.0
		m.hp = m.max_hp
		game.sleep_till_morning()
	if it.has("chart"):
		_chart()
	if it.has("item"):
		game.items[String(it["item"])] = true
	if it.has("heat_ward"):
		game.heat_ward = true
	if it.has("spell") and not game.known.has(String(it["spell"])):
		game.known.append(String(it["spell"]))
	if it.has("recipe"):
		game.learn(String(it["recipe"]), "bought")
	if it.has("part"):
		game.items["part_" + String(it["part"])] = 1
		game.ui.toast("The Wisp Forge can fit it to your skiff (Travel)", Color(1.0, 0.85, 0.4), 3.0)
	if it.has("star_chart"):
		for k in int(it["star_chart"]):
			game.space._star_chart()
	if it.has("repair") and game.skiff != null:
		game.skiff.mend(100000)
	if it.has("good"):
		var cargo: Dictionary = game.items.get("cargo", {})
		cargo[String(it["good"])] = int(cargo.get(String(it["good"]), 0)) + 1
		game.items["cargo"] = cargo

## sell what the keeper pays for, one lot
func sell(v, mat: int) -> bool:
	for b in buys(v):
		if int(b[0]) != mat:
			continue
		var n := int(b[1])
		if game.player.inv[mat] < n:
			return false
		game.player.inv[mat] -= n
		game.items["coins"] = coins() + int(b[2])
		game.audio.play("coin")
		stats["sold"] = int(stats.get("sold", 0)) + 1
		return true
	return false

## the planet's dungeons, marked on your map
func _chart() -> void:
	var ch := []
	for l in game.builds.lair_list:
		ch.append({"pos": [l["pos"].x, l["pos"].y], "name": String(l["name"]), "kind": "lair"})
	for w in game.builds.warden_list:
		ch.append({"pos": [w["pos"].x, w["pos"].y], "name": "Crypt", "kind": "dungeon"})
	game.planet_state["charted"] = ch
	game.ui.toast("The dungeons of %s are on your map now (M)" % game.planet.get("name", ""), Color(0.9, 0.85, 1.0), 4.0)
