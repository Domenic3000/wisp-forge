## Living towns: the people of the villages that still stand (buildings.gd `towns` with "living").
## Near you a village fills with its folk: by day each house's people walk the street (turning at walls
## and drops, running from foes, going indoors at night), and a keeper stands in every shop, smithy,
## tavern and inn, day and night. Talk to anyone (F) for a word or a rumour; talk to a keeper to trade
## (main state "shop", ui.gd's shop panel): coins for what you gather, and what the shop sells for coins
## (Defs.SHOPS, by the keeper's role). The folk are made again from their village's seed each time you
## come (same names, same looks); only your coins and what you bought are kept.
extends RefCounted

const FolkArt := preload("res://scripts/folk_art.gd")
const NEAR := 520.0          # a village this near (cells round the planet) has its folk out
const FAR := 760.0           # ...and this far off they're gone again
const TALK := 24.0           # how close to talk to someone
const WALK := 0.55
const MAX_WALKERS := 8

var game
var folk: Array = []         # main.gd Villager bodies
var _peopled := {}           # village seed -> true (its keepers are in)
var _out := {}               # village seed -> true (its walkers are out: by day)
var shop_of = null           # the keeper you're trading with (main state "shop")
var stats := {}              # (counts for the tests)

func _init(g) -> void:
	game = g

func clear() -> void:
	folk.clear()
	_peopled.clear()
	_out.clear()
	shop_of = null

## every tick on the planet
func tick() -> void:
	if game.frame % 30 == 0:
		_people()
	for k in range(folk.size() - 1, -1, -1):
		var v = folk[k]
		if v.gone:
			folk.remove_at(k)
			continue
		_walk(v)

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

## fill the villages near you, and empty the ones you've left
func _people() -> void:
	var pc := _col(game.player.pos)
	for t in game.builds.towns:
		if not bool(t["living"]):
			continue
		var mid := int(t["x0"]) + int(t["w"]) / 2
		var d := _cdist(pc, mid)
		var tk := int(t["seed"])
		if d < NEAR:
			if not _peopled.has(tk):
				_peopled[tk] = true
				_fill(t, true)
			var day: bool = game._local_daylight(_at(mid, game.builds.ground_row(mid), 10.0)) > 0.3
			if day and not _out.has(tk):
				_out[tk] = true
				_fill(t, false)
			elif not day and _out.has(tk):
				var any := false
				for v0 in folk:
					if v0.town["seed"] == tk and not v0.keeper and not v0.gone:
						any = true
				if not any:
					_out.erase(tk)              # (all home for the night: out again in the morning)
		elif d > FAR and _peopled.has(tk):
			_peopled.erase(tk)
			_out.erase(tk)
			for v in folk:
				if v.town["seed"] == tk:
					v.gone = true

## a village's keepers (`keepers`), or its walkers
func _fill(t: Dictionary, keepers: bool) -> void:
	var walkers := 0
	var houses: Array = t["houses"]
	for hi in houses.size():
		var h: Dictionary = houses[hi]
		if bool(h["ruined"]):
			continue
		var role := String(h["role"])
		if keepers:
			if Defs.SHOPS.has(role):
				# the keeper, in the middle of the ground floor
				var kc := float(int(h["x0"]) + int(h["w"]) / 2)
				_add(t, h, hseed(t, hi, 0), role, true, _at(kc, float(h["floor"]), 9.0))
			continue
		for n in (2 if role == "home" else 1):
			if walkers >= MAX_WALKERS:
				break
			var c := float(int(t["x0"]) + 12 + randi() % maxi(1, int(t["w"]) - 24))
			_add(t, h, hseed(t, hi, n + 1), "folk", false, _at(c, float(game.builds.ground_row(int(c))), 12.0))
			walkers += 1
	if not keepers:
		return
	stats["filled"] = int(stats.get("filled", 0)) + 1
	var seen: Array = game.planet_state.get("towns_seen", [])
	if not seen.has(int(t["seed"])):
		seen.append(int(t["seed"]))
		game.planet_state["towns_seen"] = seen
		game.ui.toast("%s: a village. Talk to its folk (F), and trade at its shops." % t["name"], Color(0.95, 0.85, 0.6), 4.0)

static func hseed(t: Dictionary, hi: int, n: int) -> int:
	return posmod(hash([int(t["seed"]), hi, n]), 0x7FFFFFFF)

func _add(t: Dictionary, h: Dictionary, fseed: int, role: String, keeper: bool, p: Vector2) -> void:
	var v = game.new_villager()
	v.fseed = fseed
	v.role = role if keeper else "folk"
	v.keeper = keeper
	v.town = t
	v.house = h
	v.name = FolkArt.name_for(fseed)
	v.pos = p
	v.w = 7.0
	v.h = 17.0
	v.step_h = 3
	v.goal_c = float(_col(p))
	v.idle_t = randi_range(30, 200)
	v.facing = 1 if randf() < 0.5 else -1
	folk.append(v)

## a villager's day: keepers stand at their counters (turning to you); the rest walk the street, idle,
## turn at walls and drops, run from foes, and go home at night
func _walk(v) -> void:
	if v.say_t > 0:
		v.say_t -= 1
	if not game.in_grid(v.pos, 12.0):
		return                                   # (outside the simulated neighbourhood: still)
	var a := atan2(v.pos.y, v.pos.x)
	var g: float = 0.17 * game.gravity_at(v.pos)
	v.vy = minf(v.vy + g, 5.0)
	var want := 0.0
	var pd: float = v.pos.distance_to(game.player.pos)
	if v.keeper:
		if pd < 70.0:
			v.facing = 1 if (game.player.pos - v.pos).dot(game.basis_r(a)) > 0.0 else -1
	else:
		var day: bool = game._local_daylight(v.pos) > 0.22
		var foe = _foe_near(v.pos, 70.0)
		if foe != null:
			# run from it
			want = -signf((foe.pos - v.pos).dot(game.basis_r(a))) * 1.25
			if v.say_t <= 0 and randf() < 0.01:
				_say(v, ["Help!", "Run!", "Get away from me!"][randi() % 3], 90)
			stats["fled"] = int(stats.get("fled", 0)) + 1
		elif not day:
			# home for the night: to the house, then indoors
			var hc := float(int(v.house["x0"]) + int(v.house["w"]) / 2)
			var dc := _dc(hc, v.pos)
			if absf(dc) < 6.0:
				v.gone = true
				return
			want = signf(dc) * WALK
		elif v.talk_t > 0:
			v.talk_t -= 1
			v.facing = 1 if (game.player.pos - v.pos).dot(game.basis_r(a)) > 0.0 else -1
		elif v.idle_t > 0:
			v.idle_t -= 1
		else:
			var dc2 := _dc(v.goal_c, v.pos)
			if absf(dc2) < 3.0:
				v.idle_t = randi_range(60, 260)
				_new_goal(v)
			else:
				want = signf(dc2) * WALK
				# a wall, or a drop ahead: turn back
				if v.hit_wall or _drop_ahead(v, signf(dc2)):
					v.idle_t = randi_range(20, 90)
					_new_goal(v, -signf(dc2))
					want = 0.0
	v.vx += (want - v.vx) * 0.25
	if absf(want) > 0.05:
		v.facing = 1 if want > 0.0 else -1
		v.anim += absf(v.vx) * 0.16
	game.move_body(v)

## the column offset from p to column c (the short way round)
func _dc(c: float, p: Vector2) -> float:
	var d := fposmod(c - float(_col(p)) + Defs.NS * 0.5, float(Defs.NS)) - Defs.NS * 0.5
	return d

## somewhere else along the village to walk to (on one side, if `side` is given)
func _new_goal(v, side := 0.0) -> void:
	var t: Dictionary = v.town
	var x0 := float(int(t["x0"]) + 8)
	var x1 := float(int(t["x0"]) + int(t["w"]) - 8)
	var here := float(_col(v.pos))
	for k in 6:
		var c := randf_range(x0, x1)
		if side == 0.0 or signf(_dc(c, v.pos)) == side:
			v.goal_c = c
			return
	v.goal_c = here + side * randf_range(20.0, 60.0)

func _drop_ahead(v, dir: float) -> bool:
	var a := atan2(v.pos.y, v.pos.x)
	var ahead: Vector2 = v.pos + game.basis_r(a) * dir * 7.0
	for k in range(8, 16, 2):
		var t: int = game.type_at(ahead + game.basis_d(a) * float(k))
		if Defs.KIND[t] == Defs.K_SOLID or Defs.KIND[t] == Defs.K_POWDER:
			return false
	return true

func _foe_near(p: Vector2, r: float):
	for e in game.enemies:
		if not e.dead and not e.under and (e.pos as Vector2).distance_to(p) < r and not game.calm_foe(e, game.player):
			return e
	return null

func _say(v, text: String, ticks := 300) -> void:
	v.say = text
	v.say_t = ticks

# ------------------------------------------------------------------ talking ---

## F near someone: a keeper opens their shop; anyone else stops and says a word or a rumour
func talk(m) -> bool:
	var best = null
	var bd := TALK
	for v in folk:
		var d: float = v.pos.distance_to(m.pos)
		if d < bd:
			bd = d
			best = v
	if best == null:
		return false
	if best.keeper:
		open_shop(best)
		return true
	best.talks += 1
	best.talk_t = 240
	_say(best, line_for(best), 330)
	stats["talked"] = int(stats.get("talked", 0)) + 1
	return true

## what someone says: a greeting, then (in turn, as you keep asking) a rumour about the nearest guardian, a
## dungeon, this world's ore, its danger, the village's shops, or just village talk
func line_for(v) -> String:
	var r := RandomNumberGenerator.new()
	r.seed = v.fseed + v.talks * 977
	var day: float = game._local_daylight(v.pos)
	var hello: String = (["Morning!", "Good day.", "Well met, mage."] if day > 0.5 else ["Evening.", "Late to be out."])[r.randi_range(0, 1)]
	var topics := ["lair", "dungeon", "ore", "hazard", "shops", "chat"]
	var topic: String = topics[(v.talks + r.randi_range(0, 5)) % topics.size()]
	var said := ""
	match topic:
		"lair":
			var best = null
			var bd := 1e9
			var dead: Array = game.planet_state.get("bosses_dead", [])
			for l in game.builds.lair_list:
				if dead.has(l["biome"]):
					continue
				var dd: float = (l["pos"] as Vector2).distance_to(v.pos)
				if dd < bd:
					bd = dd
					best = l
			if best != null:
				var bdef: Dictionary = Defs.BOSSES.get(best["biome"], {})
				said = "They say %s sleeps in %s, %s %s." % [bdef.get("name", "something"), best["name"], _far(bd), _way(v.pos, best["pos"])]
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

# ------------------------------------------------------------------ trading ---

func open_shop(v) -> void:
	shop_of = v
	v.facing = 1 if (game.player.pos - v.pos).dot(game.basis_r(atan2(v.pos.y, v.pos.x))) > 0.0 else -1
	_say(v, ["What'll it be?", "Come in, come in.", "Take a look."][randi() % 3], 200)
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
	return Defs.SHOPS.get(v.role, {})

## what the keeper pays for: [material, how many, coins]
func buys(v) -> Array:
	var sd := shop_def(v)
	var out := []
	var b: Dictionary = sd.get("buy", {})
	for m in b:
		out.append([int(m), int(b[m][0]), int(b[m][1])])
	if sd.has("ores"):
		for m2 in range(Defs.FIREOPAL, Defs.SILVER + 1):
			out.append([m2, int(sd["ores"][0]), int(sd["ores"][1])])
	return out

## buy the i-th thing the keeper sells
func buy(v, i: int) -> bool:
	var it: Dictionary = shop_def(v)["sell"][i]
	var price := int(it["price"])
	if coins() < price:
		return false
	game.items["coins"] = coins() - price
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
	game.audio.play("coin")
	game.ui.toast("Bought: %s" % it["name"], Color(1, 0.85, 0.4), 2.0)
	stats["bought"] = int(stats.get("bought", 0)) + 1
	game.save_game()
	return true

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

## the planet's guardian lairs and dungeons, marked on your map
func _chart() -> void:
	var ch := []
	for l in game.builds.lair_list:
		ch.append({"pos": [l["pos"].x, l["pos"].y], "name": String(l["name"]), "kind": "lair"})
	for w in game.builds.warden_list:
		ch.append({"pos": [w["pos"].x, w["pos"].y], "name": "Crypt", "kind": "dungeon"})
	game.planet_state["charted"] = ch
	game.ui.toast("The lairs and dungeons of %s are on your map now (M)" % game.planet.get("name", ""), Color(0.9, 0.85, 1.0), 4.0)
