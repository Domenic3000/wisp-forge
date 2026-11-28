## Places to discover (27 Nov; user: "what else can we add content wise to make finding and exploring distant worlds
## have meaning and be more exciting. it seems very easy to get the new gear once you find a recipe. it doesnt really
## feel like a very developed gameplay loop yet."; chose world-bound materials, places to discover, multi-step crafting,
## gear with rolled traits, and recipes learned by studying artifacts).
##
## Each world first made since then (not the exotic ones, which have their mysteries) hides a few places, planned by
## buildings.gd after everything else with a sequence of their own (`plan_all`), each grown from parts:
##  - a WISP ARCHIVE deep underground: a two-storey hall of masonry and crystal, shelves of old books, its dead keepers
##    on guard, two sure chests; forging gear inside one is a better forging (main `forge_quality`);
##  - a SEALED SANCTUM underground: an antechamber with three braziers under glyphs and, high on its wall, the glyphs in
##    the order they must burn; F kindles a brazier (KINDLE_MANA); the wrong one puts them all out; all three in turn
##    and the runestone wall to its vault crumbles (a stamp of air, like a warden's ward); two sure chests behind it;
##  - a FALLEN STARSHIP on the surface: a hull of plating half buried in its crater, its canopy glass, its wisp engine
##    cold, torn open at the top; a sure chest on its deck.
## Their chests hold the world's own finds (Defs.KIND_REAGENT) and an artifact to study (main `place_loot`).
## As you play (`tick`): within HINT_R the wisp feels one ("something old, far below us"), within FOUND_R (or inside
## it) it's found: a toast, the wisp, the map and minimap mark it, the journal lists it. Studying an artifact can
## reveal one not yet found (`reveal_one`). Kept in planet_state["places"] {v, found, hinted, revealed, opened}; a world
## made before places came in has no "places" key and none are planned there (main `_make_world`).
extends RefCounted

const Vfx := preload("res://scripts/vfx.gd")
const Props := preload("res://scripts/props.gd")
const MysteryArt := preload("res://scripts/mystery.gd")

const KINDS := {
	"archive": {"name": "Wisp Archive", "col": Color(0.6, 0.85, 1.0),
		"found": "A Wisp Archive: the old wisp-scholars kept their learning here. Forge your gear in here and the forging takes better."},
	"sanctum": {"name": "Sealed Sanctum", "col": Color(1.0, 0.72, 0.4),
		"found": "A Sealed Sanctum. Three braziers, and glyphs high on the wall. The order must matter."},
	"wreck": {"name": "Fallen Starship", "col": Color(0.78, 0.84, 0.95),
		"found": "A ship fell here, long ago. Whoever flew it may have left something aboard."},
}
const ORDER := ["archive", "sanctum", "wreck"]
const FOUND_R := 70.0
const HINT_R := 520.0
const REACH := 20.0
const KINDLE_MANA := 6.0

var game
var found := {}
var hinted := {}
var revealed := {}
var opened := {}
var lit := {}            # sanctum id -> [brazier index], lit in turn (not saved: they'd have gone out)
var near := {}           # {"id", "i"}: the brazier F would kindle
var flash := {}          # "id:i" -> ticks of a wrong brazier's puff
var stats := {"found": 0, "hinted": 0, "lit": 0, "wrong": 0, "opened": 0, "revealed": 0}

func _init(g) -> void:
	game = g

func list() -> Array:
	return game.builds.places if game.builds != null else []

func by_id(id: String) -> Dictionary:
	for pl in list():
		if String(pl["id"]) == id:
			return pl
	return {}

# ------------------------------------------------------------ saving ---
func load_from(ps: Dictionary) -> void:
	var d = ps.get("places", {})
	if not (d is Dictionary):
		d = {}
	found = _set_of(d.get("found", []))
	hinted = _set_of(d.get("hinted", []))
	revealed = _set_of(d.get("revealed", []))
	opened = _set_of(d.get("opened", []))
	lit.clear()
	near = {}
	flash.clear()

func save_to(ps: Dictionary) -> void:
	if not ps.has("places"):
		return
	ps["places"] = {"v": 1, "found": found.keys(), "hinted": hinted.keys(), "revealed": revealed.keys(), "opened": opened.keys()}

func _set_of(a) -> Dictionary:
	var out := {}
	if a is Array:
		for v in a:
			out[String(v)] = true
	return out

# ------------------------------------------------------------ as you play ---
## is world point p inside a place (its rectangle of cells, like buildings.gd `label_at`)?
func inside(pl: Dictionary, p: Vector2) -> bool:
	var row := int(Defs.R_TOP - p.length())
	if row < int(pl["ymin"]) or row > int(pl["ymax"]):
		return false
	var lax: int = int(pl["x0"])
	var k: int = Defs.stamp_k(p, lax, int(pl["w"])).x - Defs.k_of(int(pl["x0"]), lax)
	return k >= 0 and k < int(pl["w"])

## the place of `kind` you're in at p, or {}
func place_at(p: Vector2, kind := "") -> Dictionary:
	for pl in list():
		if (kind == "" or String(pl["kind"]) == kind) and inside(pl, p):
			return pl
	return {}

# ------------------------------------------------------------ the wisp's guidance ---
## (27 Nov; worlds are bigger now, and the user asked that key quest and progression foes stay easy to find): the wisp
## marks the world's heart when you land (until it's beaten), and every GUIDE_EVERY frames the nearest dungeon
## (its warden not beaten) or living village not yet seen, within GUIDE_R: planet_state["guided"] [{pos, name, kind}],
## drawn on the map and the minimap with the tavern's charted places.
const GUIDE_EVERY := 1800
const GUIDE_R := 2600.0
var stats_guided := 0

func _guided_has(gd: Array, kind: String, p: Vector2) -> bool:
	for e in gd:
		if String(e["kind"]) == kind and Vector2(float(e["pos"][0]), float(e["pos"][1])).distance_to(p) < 30.0:
			return true
	return false

func guide(force := false) -> void:
	if game.builds == null or game.player == null:
		return
	var gd: Array = game.planet_state.get("guided", [])
	var p: Vector2 = game.player.pos
	var bi: Vector4 = game.boss_info
	if bi.y > 0.0 and not bool(game.planet_state.get("boss_dead", false)):
		var hp := Vector2(cos(bi.x), sin(bi.x)) * bi.y
		if not _guided_has(gd, "heart", hp):
			gd.append({"pos": [hp.x, hp.y], "name": "The heart of %s" % String(game.planet.get("name", "this world")), "kind": "heart"})
			game.planet_state["guided"] = gd
			stats_guided += 1
			if game.quest != null:
				game.quest.say_later("Far below, on the other side of this world, its heart beats, and something guards it. I've marked it on your map.")
			return
	var best := {}
	var bd := GUIDE_R
	var dead: Array = game.planet_state.get("bosses_dead", [])
	for w in game.builds.warden_list:
		var wp: Vector2 = w["pos"]
		if dead.has(String(w["key"])) or _guided_has(gd, "dungeon", wp):
			continue
		var d := wp.distance_to(p)
		if d < bd:
			bd = d
			best = {"pos": [wp.x, wp.y], "name": String(w.get("name", "Crypt")), "kind": "dungeon"}
	var seen: Array = game.planet_state.get("towns_seen", [])
	for t in game.builds.towns:
		if not bool(t["living"]) or seen.has(int(t["seed"])):
			continue
		var tc := float(int(t["x0"]) + int(t["w"]) / 2)
		var a := (tc + 0.5) / float(Defs.NS) * TAU
		var tp := Vector2(cos(a), sin(a)) * (Defs.R_TOP - float(game.builds.ground_row(int(tc))) + 6.0)
		if _guided_has(gd, "town", tp):
			continue
		var d2 := tp.distance_to(p)
		if d2 < bd:
			bd = d2
			best = {"pos": [tp.x, tp.y], "name": String(t["name"]), "kind": "town"}
	if best.is_empty():
		return
	gd.append(best)
	game.planet_state["guided"] = gd
	stats_guided += 1
	if game.quest != null:
		var bp := Vector2(float(best["pos"][0]), float(best["pos"][1]))
		var what := "a village, %s," % String(best["name"]) if String(best["kind"]) == "town" else "a dungeon, %s, with its warden," % String(best["name"])
		game.quest.say_later("There's %s %s. I've marked it on your map." % [what, _way(bp, p)])

func tick() -> void:
	if game.frame % GUIDE_EVERY == 120 and not game.space.active and not game.pocket.active:
		guide()
	for fk in flash.keys():
		flash[fk] = int(flash[fk]) - 1
		if int(flash[fk]) <= 0:
			flash.erase(fk)
	if game.frame % 10 != 0:
		return
	near = {}
	if list().is_empty() or game.player == null or game.player.dead or game.space.active or game.pocket.active:
		return
	var p: Vector2 = game.player.pos
	for pl in list():
		var id := String(pl["id"])
		var mid: Vector2 = pl["mid"]
		var d := mid.distance_to(p)
		if not found.has(id) and (d < FOUND_R or inside(pl, p)):
			discover(pl)
		elif not found.has(id) and not hinted.has(id) and d < HINT_R:
			_hint(pl, p)
		if String(pl["kind"]) == "sanctum" and not opened.has(id) and d < 160.0:
			var best := REACH
			var bz: Array = pl["braziers"]
			for k in bz.size():
				var db: float = (bz[k]["pos"] as Vector2).distance_to(p)
				if db < best:
					best = db
					near = {"id": id, "i": k}
		if String(pl["kind"]) == "wreck" and d < 220.0 and randf() < 0.4:
			# (it still smokes a little where its engine burned out)
			var eng: Vector2 = pl.get("engine", mid)
			game.vfx.spawn(Vfx.SMOKE, eng, eng.normalized() * (0.2 + randf() * 0.2), 120 + randi() % 60,
				Color(0.3, 0.3, 0.33, 0.35), Color(0.5, 0.5, 0.5, 0.0), 1.5, 5.0, false, -0.003, 0.99)

func discover(pl: Dictionary) -> void:
	var id := String(pl["id"])
	if found.has(id):
		return
	found[id] = true
	hinted[id] = true
	stats["found"] = int(stats["found"]) + 1
	var kd: Dictionary = KINDS[String(pl["kind"])]
	game.ui.toast("Discovered: %s" % String(pl["name"]), kd["col"], 5.0)
	game.audio.play("rare", pl["mid"], 0.6)
	if game.quest != null:
		game.quest.say_later(String(kd["found"]))
	game.save_game()

func _way(to: Vector2, from: Vector2) -> String:
	var a: float = game.view_angle()
	var rel := to - from
	var side: float = rel.dot(game.basis_r(a))
	var down := from.length() - to.length()
	var words := []
	if down > 90.0:
		words.append("far below us" if down > 260.0 else "below us")
	elif down < -90.0:
		words.append("above us")
	if absf(side) > 90.0:
		words.append("off to the right" if side > 0.0 else "off to the left")
	return " and ".join(words) if not words.is_empty() else "close by"

func _hint(pl: Dictionary, p: Vector2) -> void:
	hinted[String(pl["id"])] = true
	stats["hinted"] = int(stats["hinted"]) + 1
	var what := {"archive": "an old wisp-place, full of learning", "sanctum": "something sealed, and waiting", "wreck": "cold metal, fallen from the sky"}
	if game.quest != null:
		game.quest.say_later("I can feel something %s: %s." % [_way(pl["mid"], p), what.get(String(pl["kind"]), "something old")])

## studying an artifact: its markings show the way to a place on this world not yet found (true if there was one)
func reveal_one() -> Dictionary:
	var pool := []
	for pl in list():
		var id := String(pl["id"])
		if not found.has(id) and not revealed.has(id):
			pool.append(pl)
	if pool.is_empty():
		return {}
	var pl2: Dictionary = pool[randi() % pool.size()]
	revealed[String(pl2["id"])] = true
	stats["revealed"] = int(stats["revealed"]) + 1
	return pl2

## the places to show on the map and the minimap: found or revealed. [world point, name, colour]
func marks() -> Array:
	var out := []
	for pl in list():
		var id := String(pl["id"])
		if found.has(id) or revealed.has(id):
			var nm := String(pl["name"]) + ("" if found.has(id) else " (?)")
			out.append([pl["mid"], nm, KINDS[String(pl["kind"])]["col"]])
	return out

## for the journal: [name, "found" / "revealed" / ""] for every place here (the unfound ones unnamed)
func summary() -> Array:
	var out := []
	for pl in list():
		var id := String(pl["id"])
		var stt := "found" if found.has(id) else ("revealed" if revealed.has(id) else "")
		var extra := ""
		if stt == "found" and String(pl["kind"]) == "sanctum":
			extra = " (open)" if opened.has(id) else " (sealed)"
		out.append([String(pl["name"]) + extra, stt])
	return out

# ------------------------------------------------------------ a sanctum's braziers ---
func near_pos() -> Variant:
	if near.is_empty():
		return null
	var pl := by_id(String(near["id"]))
	if pl.is_empty():
		return null
	return pl["braziers"][int(near["i"])]["pos"]

func near_name() -> String:
	return "Kindle the brazier"

func prompt() -> String:
	if near.is_empty():
		return ""
	var pl := by_id(String(near["id"]))
	if pl.is_empty():
		return ""
	var g := int(pl["braziers"][int(near["i"])]["glyph"])
	if (lit.get(String(near["id"]), []) as Array).has(int(near["i"])):
		return "the brazier of the %s burns" % MysteryArt.GLYPHS[g]
	return "[F] kindle the brazier of the %s (%d mana)" % [MysteryArt.GLYPHS[g], int(KINDLE_MANA)]

func interact(m) -> bool:
	if near.is_empty():
		return false
	kindle(String(near["id"]), int(near["i"]), m)
	return true

func is_lit(id: String, i: int) -> bool:
	return opened.has(id) or (lit.get(id, []) as Array).has(i)

func kindle(id: String, i: int, m) -> void:
	var pl := by_id(id)
	if pl.is_empty() or opened.has(id):
		return
	var lst: Array = lit.get(id, [])
	if lst.has(i):
		return
	var bz: Dictionary = pl["braziers"][i]
	var bp: Vector2 = bz["pos"]
	if not game.pay_mana(m, KINDLE_MANA, bp, "kindle"):
		return
	stats["lit"] = int(stats["lit"]) + 1
	var order: Array = pl["order"]
	if int(bz["glyph"]) == int(order[lst.size()]):
		lst.append(i)
		lit[id] = lst
		game.audio.play("fire", bp, 0.6)
		game.vfx.spawn(Vfx.RING, bp, Vector2.ZERO, 30, Color(1.0, 0.85, 0.5), Color(1.0, 0.5, 0.2, 0.0), 2.0, 18.0)
		game.vfx.light(bp, 50.0, Color(1.3, 0.9, 0.5), 40)
		if lst.size() >= order.size():
			_open(pl)
		else:
			game.ui.toast("The brazier of the %s catches" % MysteryArt.GLYPHS[int(bz["glyph"])], Color(1.0, 0.85, 0.55), 2.5)
	else:
		stats["wrong"] = int(stats["wrong"]) + 1
		for k in lst:
			flash["%s:%d" % [id, int(k)]] = 30
		flash["%s:%d" % [id, i]] = 30
		lit[id] = []
		for q in 12:
			game.vfx.spawn(Vfx.SMOKE, bp, Vector2(randf() - 0.5, -0.5 - randf() * 0.4) * 0.6, 60 + randi() % 40,
				Color(0.32, 0.3, 0.3, 0.6), Color(0.5, 0.5, 0.5, 0.0), 1.5, 4.0, false, -0.004, 0.98)
		game.audio.play("zap", bp, 0.5, 0.6)
		game.ui.toast("The flames gutter out, every one. The glyphs on the wall say in what order they must burn", Color(1.0, 0.6, 0.5), 3.5)

func _open(pl: Dictionary) -> void:
	var id := String(pl["id"])
	opened[id] = true
	stats["opened"] = int(stats["opened"]) + 1
	var wr: Dictionary = pl["ward"]
	var air := PackedInt32Array()
	air.resize(int(wr["w"]) * int(wr["h"]))
	air.fill(Defs.AIR | 0xFF00)
	game.stamps.append({"x0": wr["x0"], "y0": wr["y0"], "w": wr["w"], "h": wr["h"], "data": air, "ax": wr["ax"], "aw": wr["aw"]})
	var mid: Vector2 = Defs.stamp_pos(int(wr["y0"]) + int(wr["h"]) / 2, int(wr["ax"]), int(wr["aw"]), Defs.k_of(int(wr["x0"]) + int(wr["w"]) / 2, int(wr["ax"])))
	for k in 60:
		var dv := Vector2.from_angle(randf() * TAU)
		game._particle(mid + dv * randf() * 10.0, dv * (0.8 + randf() * 1.8), 30 + randi() % 30, Color(1.0, 0.8, 0.5), true, 0.0)
	game.vfx.spawn(Vfx.RING, mid, Vector2.ZERO, 50, Color(1.0, 0.9, 0.7), Color(1.0, 0.5, 0.2, 0.0), 6.0, 80.0)
	game.shake = 10.0
	game.audio.play("rare")
	game.ui.toast("The three fires burn in their order: the runestone wall of the sanctum crumbles!", Color(1.0, 0.85, 0.5), 6.0)
	if game.quest != null:
		game.quest.say_later("The wall is gone. What they sealed in there is yours.")
	game.save_game()

# ------------------------------------------------------------ planning ---
## (buildings.gd `plan`, last: `b` is the planner; its own sequence, so nothing else moves)
static func plan_all(b, build: bool) -> void:
	var keep = b.rng
	b.rng = RandomNumberGenerator.new()
	b.rng.seed = int(b._planet["seed"]) * 113 + 5821
	var each := maxi(1, int(round(float(b.N0) / 8192.0)))
	for kind in ORDER:
		var made := 0
		for tries in 90:
			if made >= each:
				break
			var x: int = b.rng.randi_range(0, b.N0 - 1)
			if b.cdist(x, b.spawn_col) < 380 or b.cdist(x, b.boss_col) < 260:
				continue
			var ok := false
			match kind:
				"archive": ok = _archive(b, x, build)
				"sanctum": ok = _sanctum(b, x, build)
				"wreck": ok = _wreck(b, x, build)
			if ok:
				made += 1
	b.rng = keep

static func _record(b, bp, kind: String, x0: int, w: int, y0: int, h: int, label := true) -> Dictionary:
	var nm := String(KINDS[kind]["name"])
	if label:
		b.labels.append({"x0": posmod(x0, b.N0), "w": w, "ymin": y0, "ymax": y0 + h, "name": nm})
	var midrow := y0 + h / 2
	var pl := {"id": "%s_%d" % [kind, posmod(x0 + w / 2, b.N0)], "kind": kind, "name": nm,
		"mid": b._bp_at(bp, float(w) * 0.5, midrow, Defs.R_TOP - float(midrow) - 0.5),
		"x0": posmod(x0, b.N0), "w": w, "ymin": y0, "ymax": y0 + h}
	b.places.append(pl)
	return pl

## a Wisp Archive: a sealed two-storey hall deep down
static func _archive(b, x: int, build: bool) -> bool:
	var W := 124
	var H := 60
	if not b._deep_free(x - W / 2 - 6, W + 12):
		return false
	var y: int = b.ground_row(x) + b.rng.randi_range(170, 300)
	b.deep.append(Vector2i(x - W / 2 - 6, x + W / 2 + 6))
	var bp = b.new_bp(x - W / 2, y, W, H)
	var fl := H - 3                      # the ground floor's row
	var m := 30                          # the gallery's floor row
	bp.solid(0, 0, W - 1, H - 1, Defs.MASONRY)
	bp.rect(3, 3, W - 4, H - 4, 0)
	bp.rect_bg(3, 3, W - 4, H - 4, Defs.BRICK)
	bp.rect(3, fl, W - 4, fl, Defs.TILE)
	# the gallery, with a gap to levitate up through
	var g0 := W / 2 - 8
	var g1 := W / 2 + 7
	for i in range(3, W - 3):
		if i < g0 or i > g1:
			bp.fg(i, m, Defs.PLANK)
			bp.fg(i, m + 1, Defs.TIMBER)
	# pillars in the back, crystals hanging from the ceilings
	for pi in range(10, W - 8, 20):
		bp.rect_bg(pi, 3, pi + 2, fl - 1, Defs.MASONRY)
	for ci in range(8, W - 6, 14):
		bp.fg(ci, 3, Defs.CRYSTAL)
		bp.fg(ci + 1, 3, Defs.CRYSTAL)
		bp.fg(ci, 4, Defs.CRYSTAL)
		if ci < g0 - 2 or ci > g1 + 2:
			bp.fg(ci + 6, m + 2, Defs.CRYSTAL)
	for ti in range(18, W - 10, 26):
		bp.bg(ti, fl - 12, Defs.TORCH)
		bp.bg(ti + 8, m - 12, Defs.TORCH)
	# shelves of old books on both floors
	for k in 5:
		b._place_prop(bp, Props.make("bookshelf", b.rng), 4, W - 5, fl - 1, true, 12)
		b._place_prop(bp, Props.make("bookshelf", b.rng), 4, W - 5, m - 1, true, 12)
	b._chest(bp, 8, fl, true)
	b._chest(bp, W - 24, m, true)
	b._guard(bp, 34, fl, "skeleton")
	b._guard(bp, W - 40, fl, "skeleton")
	b._guard(bp, W / 2 + 24, m, "skeleton")
	_record(b, bp, "archive", x - W / 2, W, y, H)
	b._finish(bp, build)
	return true

## a Sealed Sanctum: an antechamber of three braziers, and behind a wall of runestone its vault
static func _sanctum(b, x: int, build: bool) -> bool:
	var W := 116
	var H := 46
	if not b._deep_free(x - W / 2 - 6, W + 12):
		return false
	var y: int = b.ground_row(x) + b.rng.randi_range(130, 260)
	b.deep.append(Vector2i(x - W / 2 - 6, x + W / 2 + 6))
	var bp = b.new_bp(x - W / 2, y, W, H)
	var fl := H - 3
	var D0 := 74
	var D1 := 79
	bp.solid(0, 0, W - 1, H - 1, Defs.MASONRY)
	bp.solid(D0, 0, W - 1, H - 1, Defs.RUNESTONE)
	bp.rect(3, 3, D0 - 1, H - 4, 0)
	bp.rect_bg(3, 3, D0 - 1, H - 4, Defs.MASONRY)
	bp.rect(D1 + 1, 3, W - 4, H - 4, 0)
	bp.rect_bg(D1 + 1, 3, W - 4, H - 4, Defs.BRICK)
	bp.rect(3, fl, D0 - 1, fl, Defs.TILE)
	# three glyphs, and the order they burn in high on the wall (with a dot for each one's place)
	var gl: Array = range(MysteryArt.GLYPHS.size())
	for k0 in gl.size():
		var sw: int = b.rng.randi_range(k0, gl.size() - 1)
		var tmp = gl[k0]
		gl[k0] = gl[sw]
		gl[sw] = tmp
	var glyphs: Array = gl.slice(0, 3)
	var order: Array = glyphs.duplicate()
	for k1 in 3:
		var sw2: int = b.rng.randi_range(k1, 2)
		var tmp2 = order[k1]
		order[k1] = order[sw2]
		order[sw2] = tmp2
	if order == glyphs:
		order = [glyphs[1], glyphs[2], glyphs[0]]
	bp.rect_bg(23, 4, 53, 16, Defs.BRICK)
	for q in 3:
		_glyph_bg(bp, int(order[q]), 25 + q * 10, 5)
		for d in q + 1:
			bp.bg(27 + q * 10 + d * 2 - q, 14, Defs.WISP)
	var braz := []
	for k2 in 3:
		var pc := 14 + k2 * 22
		bp.solid(pc - 2, fl - 6, pc + 2, fl - 1, Defs.MASONRY)
		_glyph_bg(bp, int(glyphs[k2]), pc - 3, fl - 22)
		var brow: int = y + fl - 7
		braz.append({"pos": b._bp_at(bp, float(pc) + 0.5, brow, Defs.R_TOP - float(brow) - 0.5), "glyph": int(glyphs[k2])})
	bp.bg(6, fl - 14, Defs.TORCH)
	bp.bg(D0 - 4, fl - 14, Defs.TORCH)
	bp.bg(D1 + 4, fl - 14, Defs.TORCH)
	bp.bg(W - 6, fl - 14, Defs.TORCH)
	b._chest(bp, D1 + 4, fl, true)
	b._chest(bp, W - 4 - 14, fl, true)
	b._guard(bp, 26, fl, "skeleton")
	b._guard(bp, 50, fl, "skeleton")
	var pl := _record(b, bp, "sanctum", x - W / 2, W, y, H)
	pl["braziers"] = braz
	pl["order"] = order
	pl["ward"] = {"x0": posmod(bp.x0 + D0, b.N0), "y0": y + 3, "w": D1 - D0 + 1, "h": H - 6, "ax": posmod(bp.x0, b.N0), "aw": W}
	b._finish(bp, build)
	return true

## glyph g inlaid in glowing crystal on the back wall, its top left at (i, j)
static func _glyph_bg(bp, g: int, i: int, j: int) -> void:
	var art: Array = MysteryArt.GLYPH_ART[g]
	for gy in 7:
		var line: String = art[gy]
		for gx in 7:
			if line[gx] == "#":
				bp.bg(i + gx, j + gy, Defs.CRYSTAL)

## a Fallen Starship: a hull of plating half buried in its crater
static func _wreck(b, x: int, build: bool) -> bool:
	var W := 96
	var x0 := x - W / 2
	if not b._site_ok(x0, W, 12):
		return false
	var base: int = b._median_ground(x0, W)
	var up := 28
	var H := up + 20
	var y0 := base - up
	var bp = b.new_bp(x0, y0, W, H)
	var gj := up
	# the crater
	for i in W:
		var t := (float(i) - float(W) * 0.5) / (float(W) * 0.5)
		var d := int(round(7.0 * maxf(0.0, 1.0 - t * t)))
		var gr: int = b.ground_row(x0 + i) - y0
		for j in range(0, mini(H, gr + d)):
			bp.fg(i, j, 0)
	# the hull: a capsule, its nose dipped into the ground
	var cx := float(W) * 0.5
	var cy := float(gj) - 2.0
	var deck := int(cy) + 4
	var L := 33.0
	for i in W:
		var u := float(i) + 0.5 - cx
		if absf(u) > L:
			continue
		var f := 1.0 - pow(absf(u) / L, 2.2 if u > 0.0 else 3.0)
		var hh := 10.0 * sqrt(maxf(f, 0.0))
		for j in H:
			var v := float(j) + 0.5 - (cy + u * 0.1)
			if absf(v) > hh:
				continue
			var inner := absf(v) < hh - 2.2 and absf(u) < L - 3.0
			if inner and j < deck:
				bp.fg(i, j, 0)
				bp.bg(i, j, Defs.HULL)
				continue
			var mt := Defs.HULL
			if v < 0.0 and u > 12.0 and u < 26.0:
				mt = Defs.GLASS
			elif absf(v + 4.0) < 1.0 and u > -20.0 and u < 10.0 and posmod(int(floor(u)), 6) < 2:
				mt = Defs.GLASS                 # (portholes along its flank)
			elif u < -L + 3.5:
				mt = Defs.WISP
			elif ((i * 7919 + j * 104729) % 100) < 5:
				mt = Defs.STARIRON
			if v < -1.0 and u > -22.0 and u < -12.0:
				bp.fg(i, j, 0)              # (torn open at the top: the way in)
				continue
			bp.fg(i, j, mt)
			bp.bg(i, j, Defs.HULL)
	# its tail fin, standing up over the stern
	for i2 in W:
		var u2 := float(i2) + 0.5 - cx
		if u2 < -L + 1.0 or u2 > -L + 12.0:
			continue
		var top := cy + u2 * 0.1 - 10.0 * sqrt(maxf(1.0 - pow(absf(u2) / L, 3.0), 0.0))
		var fh := 9.0 * (1.0 - (u2 + L - 1.0) / 11.0)
		for j2 in range(int(floor(top - fh)), int(ceil(top)) + 1):
			if j2 >= 0 and j2 < H:
				bp.fg(i2, j2, Defs.HULL)
	# plating thrown out round the crater
	for k in 4:
		var di: int = b.rng.randi_range(4, W - 8)
		if absf(float(di) - cx) < L + 2.0:
			continue
		var dgr: int = b.ground_row(x0 + di) - y0
		for q in 3:
			bp.fg(di + q, dgr - 1, Defs.HULL)
			if q < 2:
				bp.fg(di + q, dgr - 2, Defs.HULL)
	bp.bg(int(cx) + 4, deck - 7, Defs.TORCH)
	b._chest(bp, int(cx) - 10, deck, true)
	var pl := _record(b, bp, "wreck", x0, W, y0, H, false)
	var erow: int = y0 + int(cy) - 2
	pl["engine"] = b._bp_at(bp, cx - L + 2.0, erow, Defs.R_TOP - float(erow) - 0.5)
	b._claim(x0, W, "Fallen Starship", y0, base + 10)
	b._finish(bp, build)
	return true
