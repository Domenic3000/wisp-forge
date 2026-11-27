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
## (user, 26 Nov: "the pocket dimension inside the ship the building does not work like the main world ... i cant
## place any workshops or anything"): the workshops standing in your ship's pocket, saved with it (pocket.dat); they
## work while you're there, as a planet's work while you're on it
var pocket_list: Array = []
var open_st = null            # the station whose panel is open
var stats := {"batches": 0, "sparks": 0, "doused": 0}      # (for the tests)
var spark_mult := 1.0         # (the tests raise it)
var _t := 0

func _init(g) -> void:
	game = g

# ------------------------------------------------------------ saving ---
func load_from(ps: Dictionary) -> void:
	list = unpack(ps.get("stations", []), false)
	open_st = null

func save_to(ps: Dictionary) -> void:
	ps["stations"] = pack(list)

## stations as saved (a planet's, or the pocket's)
func pack(arr: Array) -> Array:
	var a := []
	for st in arr:
		var sto := {}
		for k in st.store:
			sto[str(k)] = st.store[k]
		a.append({"kind": st.kind, "pos": [st.pos.x, st.pos.y], "fuel": st.fuel, "heat": st.heat, "prog": st.prog,
			"cur": st.cur, "facing": st.facing, "store": sto, "out": st.out})
	return a

func unpack(saved, in_pocket: bool) -> Array:
	var out := []
	if typeof(saved) != TYPE_ARRAY:
		return out
	for e in saved:
		if typeof(e) != TYPE_DICTIONARY or not Defs.STATIONS.has(String(e.get("kind", ""))):
			continue
		var st = game.new_station(String(e["kind"]))
		st.pos = Vector2(float(e["pos"][0]), float(e["pos"][1]))
		st.pocket = in_pocket
		st.on_ground = true
		st.fuel = float(e.get("fuel", 0.0))
		st.heat = float(e.get("heat", 0.0))
		st.prog = float(e.get("prog", 0.0))
		st.cur = String(e.get("cur", ""))
		st.facing = int(e.get("facing", 1))
		for k in e.get("store", {}):
			st.store[int(k)] = int(e["store"][k])
		for k2 in e.get("out", {}):
			st.out[String(k2)] = int(e["out"][k2])
		out.append(st)
	return out

## a new station of `kind` standing at world point `pos` (its middle)
func add(kind: String, pos: Vector2):
	var st = game.new_station(kind)
	st.pos = pos
	list.append(st)
	return st

## one set down in the pocket, at the pocket's point `pos` (its middle)
func add_pocket(kind: String, pos: Vector2):
	var st = game.new_station(kind)
	st.pos = pos
	st.pocket = true
	st.on_ground = true
	pocket_list.append(st)
	return st

## are we in the pocket's isle (its workshops the ones at hand)?
func in_pocket() -> bool:
	return game.pocket != null and game.pocket.active and game.pocket.place == "isle"

## the workshops where you are: the pocket's in there, the planet's outside
func here_list() -> Array:
	return pocket_list if in_pocket() else list

# --------------------------------------------------------- the panel ---
## the station nearest the local mage within reach (null: none)
func nearest(m, reach := REACH):
	var best = null
	var bd := reach * reach
	for st in here_list():
		var d: float = st.pos.distance_squared_to(m.pos)
		if d < bd:
			bd = d
			best = st
	return best

## F: open the nearest station's panel (true if there was one)
func interact(m, pick = null) -> bool:
	var st = nearest(m) if pick == null else pick     # (pick: the one Z chose, main.gd `f_pick`)
	if st == null:
		return false
	if st.kind == "altar":
		# (no panel: F lays a guardian's sigil on it, summoning.gd)
		game.summoning.try_summon(m, st)
		return true
	# (user, 25 Nov: "finished goods stack on a tray beside it, taken with F, no panel needed", and "with
	# something in hand, F at a workshop drops it in"): what it made comes first, then what's in your hand
	# if it's any use here and not in yet; otherwise (and for fuel by the panel, details, Load buttons) the panel
	if has_out(st):
		take_out(st, true)
		return true
	if drop_in(st, m) > 0:
		return true
	open_st = st
	game.state = "station"
	game.ui.show_station(st)
	game.audio.play("chest_open", st.pos, 0.4)
	return true

## (user, 25 Nov: a forge card that needs a workshop gets "Send to the Kiln"): the nearest station of a kind
## within SEND_REACH of m (a workshop in your home, a room or two away), or null
const SEND_REACH := 160.0
func nearest_kind(kind: String, m, reach := SEND_REACH):
	var best = null
	var bd := reach * reach
	for st in here_list():
		if st.kind != kind:
			continue
		var d: float = st.pos.distance_squared_to(m.pos)
		if d < bd:
			bd = d
			best = st
	return best

## load n batches of a process into the nearest station of its kind from the forge's book: what goes in flies
## there from your satchel. How many batches went in (0: none near, or not enough in the satchel; said in a toast).
func send(pr: Dictionary, n: int) -> int:
	var m = game.player
	var st = nearest_kind(String(pr["at"]), m)
	var sname := String(Defs.STATIONS[pr["at"]]["name"])
	if st == null:
		game.ui.toast("No %s near enough to send it to" % sname, Color(1, 0.7, 0.5), 2.5)
		return 0
	var got := load_recipe(st, pr, n)
	if got <= 0:
		game.ui.toast("Not enough in your satchel for one batch", Color(1, 0.7, 0.5), 2.5)
		return 0
	var top := _world(st, Vector2(0, -st.h * 0.4))
	for k in pr["in"]:
		game.vfx.fly(m.pos, top, Defs.COLOR[int(k)], 6)
	game.ui.toast("Sent to the %s: %d batch%s of %s" % [sname, got, "" if got == 1 else "es", String(Defs.process_out(pr)[0])], Color(1, 0.85, 0.5), 3.0)
	game.audio.play("place", m.pos, 0.6)
	stats["sent"] = int(stats.get("sent", 0)) + got
	return got

## anything made waiting on its tray?
func has_out(st) -> bool:
	for k in st.out:
		if int(st.out[k]) > 0:
			return true
	return false

## F with a material in your hand (holding Conjure): drop some into the station, if it works that material or
## burns it and doesn't hold it yet: a known recipe's worth for four batches (all you have if less), or ten
## for a mix still to be tried; fuel feeds the fire. How many went in (0: nothing, the panel opens).
func drop_in(st, m) -> int:
	if m != game.player or not game.conjuring(m) or not game.hand_item.is_empty():
		return 0
	var mt: int = game.mat
	if mt <= 0 or m.inv[mt] <= 0:
		return 0
	var want := 0
	var used := false
	for pr in Defs.PROCESS:
		if pr["at"] == st.kind and (pr["in"] as Dictionary).has(mt):
			used = true
			if not pr.get("secret", false) or is_secret_known(String(pr["id"])):
				want = maxi(want, int(pr["in"][mt]) * 4)
	var n := 0
	var into := ""
	if used:
		if int(st.store.get(mt, 0)) > 0:
			return 0
		n = load_mat(st, mt, want if want > 0 else 10)
		into = "into"
	elif Defs.FUEL_TICKS.has(mt) and float(Defs.STATIONS[st.kind]["burn"]) > 0.0 and st.fuel < FUEL_MAX * 0.25:
		n = add_fuel(st, mt, maxi(1, int(FUEL_MAX * 0.5 / float(Defs.FUEL_TICKS[mt]))))
		into = "on the fire of"
	if n <= 0:
		return 0
	var top := _world(st, Vector2(0, -st.h * 0.4))
	game.vfx.fly(m.pos, top, Defs.COLOR[mt], 8)
	game.popups.append([top + st.pos.normalized() * 4.0, "%d %s %s the %s" % [n, Defs.NAMES[mt], into, Defs.STATIONS[st.kind]["name"]], Defs.COLOR[mt], 70])
	game.audio.play("place", st.pos, 0.6)
	stats["dropped"] = int(stats.get("dropped", 0)) + n
	return n

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

## (user, 25 Nov: "if you click a known recipe it will load by itself"): load n more batches of a recipe it
## knows, as many as the satchel holds, on top of what's in already (user, 26 Nov: "when i use the forge and load 1
## or 5 or however many it is set to it does not add to whatever is in there it starts it over with exactly how
## many you have set"); anything loaded that isn't in it goes back first (a mix it knows must be exactly its kinds),
## and a batch under way keeps going. How many batches went in.
func load_recipe(st, pr: Dictionary, n: int) -> int:
	if pr.is_empty() or pr["at"] != st.kind:
		return 0
	var need: Dictionary = pr["in"]
	for m in st.store.keys():
		if not need.has(int(m)):
			unload(st, int(m))
	var fresh: bool = st.store.is_empty()
	var can := maxi(1, n)
	for m2 in need:
		can = mini(can, game.player.inv[int(m2)] / int(need[m2]))
	if can <= 0:
		return 0
	for m3 in need:
		load_mat(st, int(m3), int(need[m3]) * can)
	if fresh:
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

## take everything it made (`here`: taken off its tray with F, said beside it rather than in a toast)
func take_out(st, here := false) -> void:
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
		if here:
			var top := _world(st, Vector2(st.facing * (st.w * 0.5 + 3.0), st.h * 0.5 - 4.0))
			game.vfx.fly(top, game.player.pos, Color(1, 0.85, 0.5), 8)
			var up: Vector2 = st.pos.normalized()
			for q in mini(parts.size(), 3):
				game.popups.append([top + up * (6.0 + 6.0 * q), "+" + String(parts[q]), Color(1, 0.85, 0.5), 70])
			stats["trays"] = int(stats.get("trays", 0)) + 1
		else:
			game.ui.toast("Taken: " + ", ".join(parts), Color(1, 0.85, 0.5), 2.5)
		if not game.testing_no_learn():
			game._learn_from_finds()           # (a first find teaches at once, though the panel keeps the world waiting)
		game.audio.play("coin", st.pos, 0.4)
		game.save_game()

## Shift + right-click on a station: take it up (into the satchel as a station you can set down again for
## free, `items["st_<kind>"]`), with what's in it and what it made. True if there was one at p.
func take_at(m, p: Vector2) -> bool:
	var arr: Array = here_list()
	for k in range(arr.size() - 1, -1, -1):
		var st = arr[k]
		var l := _local(st, p)
		if absf(l.x) > st.w * 0.5 + 1.0 or absf(l.y) > st.h * 0.5 + 1.0:
			continue
		for mt in st.store:
			game.player.inv[int(mt)] += int(st.store[mt])
		st.store.clear()
		take_out(st)
		var key: String = "st_" + st.kind
		game.items[key] = int(game.items.get(key, 0)) + 1
		arr.remove_at(k)
		if open_st == st:
			close()
		game.ui.toast("%s taken up: it's in your satchel (I), click it there to set it down again" % Defs.STATIONS[st.kind]["name"], Color(1, 0.85, 0.5), 2.5)
		game.audio.play("dig", st.pos, 0.6)
		return true
	return false

## p in a station's own frame (x along the ground, y down), from its middle
func _local(st, p: Vector2) -> Vector2:
	var a := _ang(st)
	var o: Vector2 = p - st.pos
	return Vector2(o.dot(game.basis_r(a)), o.dot(game.basis_d(a)))

func _world(st, l: Vector2) -> Vector2:
	var a := _ang(st)
	return st.pos + game.basis_r(a) * l.x + game.basis_d(a) * l.y

## the angle whose up is a station's: away from the planet's middle, or in the pocket the screen's up
func _ang(st) -> float:
	return -PI * 0.5 if st.pocket else atan2(st.pos.y, st.pos.x)

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
	if st.pocket:
		# (the pocket keeps the hours of where you came in from)
		return game._local_daylight(game.pocket.back.get("pos", game.player.pos)) < 0.3
	return game._local_daylight(st.pos) < 0.3

func is_secret_known(id: String) -> bool:
	return game.items.has("secret_" + id)

func tick() -> void:
	work_all()
	if in_pocket():
		_pocket_physics()
	else:
		_physics()

func work_all() -> void:
	_t += 1
	for st in here_list():
		_work(st)

## the pocket's workshops: each stands on the isle (taken from under it, it drops until something holds it; off
## the isle altogether, it comes back to your satchel); a lit one smokes and glows (no sparks: nothing in here burns)
func _pocket_physics() -> void:
	var isle = game.pocket.isle
	if isle == null:
		return
	for k in range(pocket_list.size() - 1, -1, -1):
		var st = pocket_list[k]
		var bb: Vector2 = isle.to_body(st.pos) + isle.com
		var c0 := int(round(bb.x - st.w * 0.5))
		var bot := int(round(bb.y + st.h * 0.5 - 1.0))
		var held := 0
		for i in int(st.w):
			if isle.solid_cell(c0 + i, bot + 1):
				held += 1
		if held == 0:
			st.pos = isle.cell_world(c0, bot + 1) + (st.pos - isle.cell_world(c0, bot))
			if bot > isle.h + 10:
				for mt in st.store:
					game.player.inv[int(mt)] += int(st.store[mt])
				st.store.clear()
				take_out(st)
				game.items["st_" + st.kind] = int(game.items.get("st_" + st.kind, 0)) + 1
				pocket_list.remove_at(k)
				game.ui.toast("The %s fell from the isle: it's back in your satchel" % Defs.STATIONS[st.kind]["name"], Color(1, 0.85, 0.5), 2.5)
			continue
		if st.lit and st.kind != "altar":
			var top := _world(st, Vector2(0, -st.h * 0.5 + 0.5))
			var mouth := _world(st, Vector2(0, st.h * 0.5 - 3.0))
			var hk: float = st.heat
			if (_t + st.kind.length()) % 7 == 0:
				game.vfx.spawn(Vfx.SMOKE, top, Vector2(0, -1) * (0.25 + randf() * 0.2) + Vector2(randf() - 0.5, randf() - 0.5) * 0.1,
					90 + randi() % 60, Color(0.35, 0.33, 0.32, 0.55 * hk), Color(0.5, 0.5, 0.5, 0.0), 1.5, 5.0, false, -0.004, 0.99)
			if randf() < 0.12 * hk:
				game.vfx.spawn(Vfx.DOT, mouth, Vector2(0, -1) * (0.3 + randf() * 0.5) + Vector2(randf() - 0.5, randf() - 0.5) * 0.4,
					20 + randi() % 25, Color(1, 0.8, 0.35), Color(1, 0.3, 0.1, 0), 1.0, 0.5, true, 0.01)
		if not st.out.is_empty() and (_t + int(absf(st.pos.x))) % 24 == 0:
			var gp := _world(st, Vector2((randf() - 0.5) * st.w * 0.6, -st.h * 0.5 - 2.0))
			game._particle(gp, Vector2(0, -0.25), 45, Color(1.0, 0.85, 0.35), true, -0.004)

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

