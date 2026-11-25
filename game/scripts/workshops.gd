## Workshops (user, 22 Nov: real smelters and kilns, a small bonus for forging in a proper workshop, and
## "some secrets that can be discovered through experimenting"). A station (main `Station`, a Body) stands
## in the world: forged at the Wisp Forge (Workshops) into the satchel and set down from it, saved with the planet (planet_state["stations"]),
## taken up again with Shift + right-click (what's in it comes back to the satchel). F beside one opens its
## panel (main state "station", ui.gd `show_station`): load materials into it from the satchel, feed its
## fire, take out what it made.
## Working (`_work`, every tick, near or far): what's loaded must be EXACTLY the kinds of one of its
## Defs.PROCESS entries (enough of each); then while its fire has fuel it warms up (`heat` 0..1, a cold
## station takes a few seconds to come up to heat) and works batch after batch at its heat, using fuel
## (STATIONS "burn" a tick), until what's loaded runs short. A mix it doesn't know does nothing: trying a
## mix out is how its secrets are found (`_done`: the first batch of a secret is a discovery,
## items["secret_<id>"]). Hints for secrets (items["hint_<id>"]) are heard from villagers (towns.gd) and
## read in notes found in chests (`hint_note`).
## Its fire is real (`_fire`): near a mage, a lit station throws sparks that set fire to anything that
## burns right beside it (keep your kiln off a plank floor and away from timber walls), it smokes and
## glows and lights the world, and standing in water puts it out.
extends RefCounted

const Vfx := preload("res://scripts/vfx.gd")

const REACH := 26.0           # how close to open a station
const SPARK_EVERY := 90       # ticks between spark checks
const WARM := 1.0 / 240.0     # heat gained a tick while burning (four seconds from cold)
const COOL := 1.0 / 900.0
const FUEL_MAX := 18000.0     # (twenty coal)

var game
var list: Array = []          # main Station bodies on this planet
var open_st = null            # the station whose panel is open
var stats := {"batches": 0, "sparks": 0, "doused": 0}      # (for the tests)
var spark_mult := 1.0         # (the tests raise it)
var _t := 0

func _init(g) -> void:
	game = g

# ------------------------------------------------------------ saving ---
func load_from(ps: Dictionary) -> void:
	list.clear()
	open_st = null
	for e in ps.get("stations", []):
		if typeof(e) != TYPE_DICTIONARY or not Defs.STATIONS.has(String(e.get("kind", ""))):
			continue
		var st = add(String(e["kind"]), Vector2(float(e["pos"][0]), float(e["pos"][1])))
		st.fuel = float(e.get("fuel", 0.0))
		st.heat = float(e.get("heat", 0.0))
		st.prog = float(e.get("prog", 0.0))
		st.cur = String(e.get("cur", ""))
		st.facing = int(e.get("facing", 1))
		for k in e.get("store", {}):
			st.store[int(k)] = int(e["store"][k])
		for k2 in e.get("out", {}):
			st.out[String(k2)] = int(e["out"][k2])

func save_to(ps: Dictionary) -> void:
	var a := []
	for st in list:
		var sto := {}
		for k in st.store:
			sto[str(k)] = st.store[k]
		a.append({"kind": st.kind, "pos": [st.pos.x, st.pos.y], "fuel": st.fuel, "heat": st.heat, "prog": st.prog,
			"cur": st.cur, "facing": st.facing, "store": sto, "out": st.out})
	ps["stations"] = a

## a new station of `kind` standing at world point `pos` (its middle)
func add(kind: String, pos: Vector2):
	var st = game.new_station(kind)
	st.pos = pos
	list.append(st)
	return st

# --------------------------------------------------------- the panel ---
## the station nearest the local mage within reach (null: none)
func nearest(m, reach := REACH):
	var best = null
	var bd := reach * reach
	for st in list:
		var d: float = st.pos.distance_squared_to(m.pos)
		if d < bd:
			bd = d
			best = st
	return best

## F: open the nearest station's panel (true if there was one)
func interact(m) -> bool:
	var st = nearest(m)
	if st == null:
		return false
	if st.kind == "altar":
		# (no panel: F lays a guardian's sigil on it, summoning.gd)
		game.summoning.try_summon(m, st)
		return true
	open_st = st
	game.state = "station"
	game.ui.show_station(st)
	game.audio.play("chest_open", st.pos, 0.4)
	return true

func close() -> void:
	open_st = null
	game.ui.hide_station()
	if game.state == "station":
		game.state = "play"

## is anything (that isn't fuel) loaded?
func loaded(st) -> bool:
	for k in st.store:
		if int(st.store[k]) > 0:
			return true
	return false

## put n of material m from the satchel into the station (what it works)
func load_mat(st, m: int, n: int) -> int:
	n = mini(n, game.player.inv[m])
	if n <= 0:
		return 0
	game.player.inv[m] -= n
	st.store[m] = int(st.store.get(m, 0)) + n
	return n

## (user, 25 Nov: "if you click a known recipe it will load by itself"): load n batches of a recipe it
## knows, as many as the satchel holds; anything loaded that isn't in it goes back first (a mix it knows must
## be exactly its kinds). How many batches went in.
func load_recipe(st, pr: Dictionary, n: int) -> int:
	if pr.is_empty() or pr["at"] != st.kind:
		return 0
	var need: Dictionary = pr["in"]
	for m in st.store.keys():
		if not need.has(int(m)):
			unload(st, int(m))
	# (what's already in counts toward the batches)
	var batches := maxi(1, n)
	var can := batches
	for m2 in need:
		var have: int = game.player.inv[int(m2)] + int(st.store.get(int(m2), 0))
		can = mini(can, have / int(need[m2]))
	if can <= 0:
		return 0
	for m3 in need:
		var want: int = int(need[m3]) * can - int(st.store.get(int(m3), 0))
		if want > 0:
			load_mat(st, int(m3), want)
	st.prog = 0.0
	return can

## the recipes a station of this kind can be loaded with by a click: its plain ones and the secrets found
func known_recipes(kind: String) -> Array:
	var out := []
	for pr in Defs.PROCESS:
		if pr["at"] == kind and (not pr.get("secret", false) or is_secret_known(String(pr["id"]))):
			out.append(pr)
	return out

## take material m back out (all of it)
func unload(st, m: int) -> void:
	var n := int(st.store.get(m, 0))
	if n > 0:
		game.player.inv[m] += n
	st.store.erase(m)
	st.prog = 0.0

## feed n of material m to the fire
func add_fuel(st, m: int, n: int) -> int:
	if not Defs.FUEL_TICKS.has(m):
		return 0
	var per := float(Defs.FUEL_TICKS[m])
	n = mini(n, mini(game.player.inv[m], int((FUEL_MAX - st.fuel) / per) + 1))
	if n <= 0:
		return 0
	game.player.inv[m] -= n
	st.fuel = minf(st.fuel + per * n, FUEL_MAX)
	return n

## take everything it made
func take_out(st) -> void:
	var parts := []
	for key in st.out.keys():
		var n := int(st.out[key])
		if n <= 0:
			continue
		var k := String(key)
		if k.begins_with("m"):
			var mt := int(k.substr(1))
			game.player.inv[mt] += n
			parts.append("%d %s" % [n, Defs.NAMES[mt]])
		elif k.begins_with("gear:"):
			game.own_work_gear(k.substr(5))
			parts.append(String(Defs.WORK_GEAR[k.substr(5)]["name"]))
		else:
			game.items[k] = int(game.items.get(k, 0)) + n
			var nm := "Healing Draught" if k == "potion" else String(Defs.DRAUGHTS.get(k, {}).get("name", k))
			parts.append("%d %s" % [n, nm])
	st.out.clear()
	if not parts.is_empty():
		game.ui.toast("Taken: " + ", ".join(parts), Color(1, 0.85, 0.5), 2.5)
		if not game.testing_no_learn():
			game._learn_from_finds()           # (a first find teaches at once, though the panel keeps the world waiting)
		game.audio.play("coin", st.pos, 0.4)
		game.save_game()

## Shift + right-click on a station: take it up (into the satchel as a station you can set down again for
## free, `items["st_<kind>"]`), with what's in it and what it made. True if there was one at p.
func take_at(m, p: Vector2) -> bool:
	for k in range(list.size() - 1, -1, -1):
		var st = list[k]
		var l := _local(st, p)
		if absf(l.x) > st.w * 0.5 + 1.0 or absf(l.y) > st.h * 0.5 + 1.0:
			continue
		for mt in st.store:
			game.player.inv[int(mt)] += int(st.store[mt])
		st.store.clear()
		take_out(st)
		var key: String = "st_" + st.kind
		game.items[key] = int(game.items.get(key, 0)) + 1
		list.remove_at(k)
		if open_st == st:
			close()
		game.ui.toast("%s taken up: it's in your satchel (I), click it there to set it down again" % Defs.STATIONS[st.kind]["name"], Color(1, 0.85, 0.5), 2.5)
		game.audio.play("dig", st.pos, 0.6)
		return true
	return false

## p in a station's own frame (x along the ground, y down), from its middle
func _local(st, p: Vector2) -> Vector2:
	var a := atan2(st.pos.y, st.pos.x)
	var o: Vector2 = p - st.pos
	return Vector2(o.dot(game.basis_r(a)), o.dot(game.basis_d(a)))

func _world(st, l: Vector2) -> Vector2:
	var a := atan2(st.pos.y, st.pos.x)
	return st.pos + game.basis_r(a) * l.x + game.basis_d(a) * l.y

# ------------------------------------------------------------ working ---
## the process what's loaded makes (exactly its kinds, enough of each), or {}
func match_process(st) -> Dictionary:
	var kinds := []
	for k in st.store:
		if int(st.store[k]) > 0:
			kinds.append(int(k))
	if kinds.is_empty():
		return {}
	for pr in Defs.PROCESS:
		if pr["at"] != st.kind:
			continue
		var need: Dictionary = pr["in"]
		if need.size() != kinds.size():
			continue
		var ok := true
		for m in need:
			if not kinds.has(int(m)) or int(st.store[int(m)]) < int(need[m]):
				ok = false
				break
		if not ok:
			continue
		if pr.get("once", false) and _made_once(st, pr):
			continue
		return pr
	return {}

func _made_once(st, pr: Dictionary) -> bool:
	var it := String(pr.get("item", ""))
	if it.begins_with("gear:"):
		return game.items.has(it.substr(5)) or st.out.has(it)
	return false

## is the mix loaded one it knows but can't make now (a night-only one by day)? "" if not
func waiting(st) -> String:
	var pr := match_process(st)
	if pr.is_empty():
		return ""
	if pr.get("night", false) and not _night(st):
		return "night"
	var burn := float(Defs.STATIONS[st.kind]["burn"])
	if burn > 0.0 and st.fuel <= 0.0:
		return "fuel"
	if burn > 0.0 and st.in_liquid:
		return "wet"
	return ""

func _night(st) -> bool:
	return game._local_daylight(st.pos) < 0.3

func is_secret_known(id: String) -> bool:
	return game.items.has("secret_" + id)

func tick() -> void:
	work_all()
	_physics()

func work_all() -> void:
	_t += 1
	for st in list:
		_work(st)

func _work(st) -> void:
	if st.kind == "altar":
		st.lit = true                  # (its runes always glow a little: no fire, no fuel)
		return
	var sd: Dictionary = Defs.STATIONS[st.kind]
	var burn := float(sd["burn"])
	if burn <= 0.0:
		st.lit = false
		return
	var pr := match_process(st)
	var why := waiting(st) if not pr.is_empty() else "idle"
	if why == "wet" and st.lit:
		stats["doused"] += 1
		game.audio.play("water", st.pos, 0.4)
	if why != "":
		st.lit = false
		st.heat = maxf(st.heat - COOL, 0.0)
		if pr.is_empty():
			st.cur = ""
			st.prog = 0.0
		return
	if st.cur != String(pr["id"]):
		st.cur = String(pr["id"])
		st.prog = 0.0
	st.lit = true
	st.fuel = maxf(st.fuel - burn, 0.0)
	st.heat = minf(st.heat + WARM, 1.0)
	st.prog += st.heat
	if st.prog >= float(pr["ticks"]):
		st.prog = 0.0
		_done(st, pr)

## a batch made: what it used goes, what it made waits in `out`
func _done(st, pr: Dictionary) -> void:
	for m in pr["in"]:
		st.store[int(m)] = int(st.store[int(m)]) - int(pr["in"][m])
		if int(st.store[int(m)]) <= 0:
			st.store.erase(int(m))
	var key := ""
	var n := 1
	if pr.has("give"):
		for m2 in pr["give"]:
			key = "m%d" % int(m2)
			n = int(pr["give"][m2])
	else:
		key = String(pr["item"])
	st.out[key] = int(st.out.get(key, 0)) + n
	stats["batches"] += 1
	var near: bool = st.pos.distance_squared_to(game.player.pos) < 300.0 * 300.0
	if near:
		game.audio.play("forge", st.pos, 0.35)
		for q in 10:
			game.vfx.spawn(Vfx.DOT, _world(st, Vector2(0, -st.h * 0.2)), Vector2(randf() - 0.5, -randf()) * 0.8, 30 + randi() % 20,
				Color(1, 0.9, 0.5), Color(1, 0.5, 0.2, 0), 1.0, 0.5, true, 0.02)
	if pr.get("secret", false) and not is_secret_known(String(pr["id"])):
		game.items["secret_" + String(pr["id"])] = true
		game.items["hint_" + String(pr["id"])] = true
		game.ui.toast("SECRET DISCOVERED: %s!" % String(pr["name"]), Color(1.0, 0.8, 1.0), 6.0)
		game.audio.play("rare", st.pos, 0.8)
		var c := _world(st, Vector2(0, -st.h * 0.5))
		game.vfx.spawn(Vfx.RING, c, Vector2.ZERO, 40, Color(1, 0.8, 1), Color(0.6, 0.4, 1, 0), 2.0, 22.0, true)
		for q2 in 30:
			var dv := Vector2.from_angle(randf() * TAU) * (0.5 + randf() * 1.2)
			game.vfx.spawn(Vfx.STREAK, c, dv, 30 + randi() % 30, Color(1, 0.9, 1), Color(0.6, 0.4, 1, 0), 1.0, 0.5, true, 0.01, 0.96)
		game.vfx.light(c, 60.0, Color(1.2, 0.9, 1.4), 60)
		game.save_game()

## each station near a mage: falls and lands like a chest; a lit one smokes, glows and throws sparks
func _physics() -> void:
	for st in list:
		var near = game._nearest_mage(st.pos)
		if st.pos.distance_squared_to(near.pos) > 250.0 * 250.0:
			continue
		game._use_grid(near)
		if not game.in_grid(st.pos, 20.0):
			continue
		var l: Vector2 = game.to_grid(st.pos)
		var held := false
		if st.on_ground:
			held = game.box_solid(l.x - st.w * 0.5, l.y - st.h * 0.5 + 1.5, st.w, st.h) \
				or game.box_solid(l.x - st.w * 0.5 + 1.0, l.y + st.h * 0.5, st.w - 2.0, 3.5)
			st.unsup_t = 0 if held else st.unsup_t + 1
		if not (st.on_ground and st.unsup_t < 12):
			st.unsup_t = 0
			st.vx *= 0.8
			st.vy = minf(st.vy + 0.17 * game.gravity_at(st.pos), 6.0)
			game.move_body(st)
		else:
			st.vy = 0.0
			# (still in water? the fire can't burn there)
			st.in_liquid = game.box_count(l.x - st.w * 0.5, l.y + st.h * 0.5 - 4.0, st.w, 3.0, Defs.WATER) > st.w
		if st.lit and st.kind != "altar":
			_fire(st)
		if not st.out.is_empty() and (_t + int(absf(st.pos.x))) % 24 == 0:
			# (something made waits in it: a glint over it)
			var gp := _world(st, Vector2((randf() - 0.5) * st.w * 0.6, -st.h * 0.5 - 2.0))
			game._particle(gp, Vfx._up_of(gp) * 0.25, 45, Color(1.0, 0.85, 0.35), true, -0.004)
	game._use_grid(game.player)

func _fire(st) -> void:
	var sd: Dictionary = Defs.STATIONS[st.kind]
	var top := _world(st, Vector2(0, -st.h * 0.5 + 0.5))
	var mouth := _world(st, Vector2(0, st.h * 0.5 - 3.0))
	var hk: float = st.heat
	if (_t + st.kind.length()) % 7 == 0:
		game.vfx.spawn(Vfx.SMOKE, top, Vfx._up_of(top) * (0.25 + randf() * 0.2) + Vector2(randf() - 0.5, randf() - 0.5) * 0.1,
			90 + randi() % 60, Color(0.35, 0.33, 0.32, 0.55 * hk), Color(0.5, 0.5, 0.5, 0.0), 1.5, 5.0, false, -0.004, 0.99)
	if randf() < 0.12 * hk:
		game.vfx.spawn(Vfx.DOT, mouth, Vfx._up_of(mouth) * (0.3 + randf() * 0.5) + Vector2(randf() - 0.5, randf() - 0.5) * 0.4,
			20 + randi() % 25, Color(1, 0.8, 0.35), Color(1, 0.3, 0.1, 0), 1.0, 0.5, true, 0.01)
	game.lights.append([mouth, 18.0 + 26.0 * hk, Color(1.25, 0.65, 0.28) * (0.6 + 0.4 * hk)])
	# sparks: anything that burns right beside it may catch
	if (_t + int(absf(st.pos.x))) % SPARK_EVERY != 0 or randf() > float(sd["spark"]) * hk * spark_mult:
		return
	_spark(st)

## what burns beside a station where its sparks fly (its sides and over it), or -1: a word of warning as
## it's set down
func burnable_near(st) -> int:
	for k in 24:
		var ang := -PI - 0.4 + (PI + 0.8) * float(k) / 23.0
		var p := _world(st, Vector2(cos(ang) * (st.w * 0.5 + 2.0), sin(ang) * (st.h * 0.5 + 2.0)))
		var t: int = game.type_at(p)
		if t > 0 and Defs.FUEL[t] > 0 and t != Defs.COAL:
			return t
	return -1

## a spark flies from a lit station to a random spot just beside it: if what's there burns, it catches
## (returns true then)
func _spark(st) -> bool:
	var sd: Dictionary = Defs.STATIONS[st.kind]
	# (out of its sides and top only: never down into the floor it stands on; user, 23 Nov: a smelter on a
	# plank floor set the house on fire)
	var ang := randf_range(-PI - 0.4, 0.4)
	var l := Vector2(cos(ang) * (st.w * 0.5 + 2.0), sin(ang) * (st.h * 0.5 + 2.0))
	var p := _world(st, l)
	var t: int = game.type_at(p)
	if t <= 0 or Defs.FUEL[t] <= 0 or t == Defs.COAL:
		return false
	var p2 := _world(st, l * 0.85)
	game.brushes.append([p2, 1.6, 3, Defs.FIRE, 0, 0, 0])
	game.brushes.append([p, 1.2, 3, Defs.FIRE, 0, 0, 0])
	stats["sparks"] += 1
	if not game.items.has("tip_sparks"):
		game.items["tip_sparks"] = true
		game.ui.toast("Sparks from the %s caught the %s! Keep workshops clear of things that burn." % [String(sd["name"]).to_lower(), Defs.NAMES[t].to_lower()], Color(1, 0.6, 0.4), 5.0)
	return true

# ------------------------------------------------------------- secrets ---
## the secrets a station can make, [process, known, hint heard]
func secrets_of(kind: String) -> Array:
	var out := []
	for pr in Defs.PROCESS:
		if pr["at"] == kind and pr.get("secret", false):
			var id := String(pr["id"])
			out.append([pr, is_secret_known(id), game.items.has("hint_" + id)])
	return out

## a secret whose hint you haven't heard (for a villager or a note), from r; {} when you've heard them all
func unheard(r: RandomNumberGenerator) -> Dictionary:
	var opts := []
	for pr in Defs.PROCESS:
		if pr.get("secret", false) and not game.items.has("hint_" + String(pr["id"])):
			opts.append(pr)
	if opts.is_empty():
		return {}
	return opts[r.randi_range(0, opts.size() - 1)]

func hear(pr: Dictionary) -> void:
	if pr.is_empty():
		return
	game.items["hint_" + String(pr["id"])] = true

## a note found in a chest: a hint (true if there was one to give)
func hint_note() -> bool:
	var r := RandomNumberGenerator.new()
	r.randomize()
	var pr := unheard(r)
	if pr.is_empty():
		return false
	hear(pr)
	game.ui.toast("A torn note: \"%s\"" % String(pr["hint"]), Color(0.95, 0.85, 1.0), 7.0)
	return true

