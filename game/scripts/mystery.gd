## A deep ocean world's sunken mystery, as you play it (user, 23 Nov: exotic worlds "with different mysteries to
## solve"; chose clues and puzzles, optional, with big rewards). buildings.gd `_abyss_mystery` plans it: five
## TIDE-STONES on the islands and shelves, each carved with a glyph and dots for its place in a song of five
## notes, and the TEMPLE OF THE DROWNED CHOIR on the deepest sea floor, dry inside (up through a moon pool from a
## flooded tunnel), with five resonance pillars, one glyph each, and a vault behind a ward of runestone.
##
## F at a stone reads it (the note goes in the journal); F at a pillar rings it: the right note in turn lights it,
## a wrong one silences them all and the song starts again; the fifth note breaks the ward (a stamp of air, like a
## warden's). F at the vault's altar: the Tide Heart (breathe and swim the deep, bear its crush) and a hoard.
## Kept in `planet_state["mystery"]` {known: {place: glyph}, rung: [glyph], solved, claimed}; a summary in
## `items["myst"][planet index]` for the journal and the quest wherever you are.
##
## A gas giant's (kind "beacons", buildings.gd `_giant_sky`; user, 24 Nov): five BEACONS on isles round the EYE
## OF THE STORM. F at one lights it (LIGHT_MANA) and it burns BURN ticks; the Eye's inscription says the five
## must burn as one, and its braziers answer the beacons that burn; all five at once break the ward. The vault:
## the STORM CROWN (no wind pushes you, lightning can't touch you, you levitate for nothing, the air under the
## clouds can't crush you) and a hoard. What burns isn't saved (it would have gone out).
extends RefCounted

const Vfx := preload("res://scripts/vfx.gd")

const GLYPHS := ["Moon", "Wave", "Shell", "Eye", "Star", "Leviathan"]
const GLYPH_ART := [
	["..###..", ".##....", "##.....", "##.....", "##.....", ".##....", "..###.."],
	[".......", ".##..##", "#..##..", ".......", ".##..##", "#..##..", "......."],
	["...#...", "..###..", ".#.#.#.", "#..#..#", "#.###.#", ".#####.", "..###.."],
	[".......", "..###..", ".#...#.", "#..#..#", ".#...#.", "..###..", "......."],
	["...#...", "...#...", "#######", "..###..", ".##.##.", ".#...#.", "......."],
	[".......", "...##..", "#.####.", "##.####", "#.####.", "...##..", "......."],
]
const NOTE := ["first", "second", "third", "fourth", "fifth"]
const REACH := 24.0
const HEART_LOOT := {"pearls": 30, "star": 8, "coins": 220, "potion": 2}
const CROWN_LOOT := {"essence": 12, "star": 10, "wisp": 8, "coins": 260, "potion": 2}
const BURN := 4500           # ticks a beacon burns (75 s)
const LIGHT_MANA := 15.0
const RUNES := ["the Gale", "the Bolt", "the Cloud", "the Wheel", "the Eye"]

var game
var st := {}
var lit := {}          # pillar index -> true while it glows (rung in turn)
var near := {}         # what's within reach now: {"kind": "stone" / "pillar" / "vault", "i": index}
var flash := {}        # pillar index -> ticks of a wrong note's red flash
var stats := {"read": 0, "rung": 0, "wrong": 0, "solved": 0, "lit": 0, "out": 0}
var burn := {}         # (beacons) index -> the frame it goes out at

func kind() -> String:
	return String(data().get("kind", "song"))

func _init(g) -> void:
	game = g

func data() -> Dictionary:
	return game.builds.mystery if game.builds != null else {}

func load_from(ps: Dictionary) -> void:
	st = ps.get("mystery", {})
	var kn := {}
	for kk in (st.get("known", {}) as Dictionary):
		kn[str(kk)] = int(st["known"][kk])
	st["known"] = kn
	var rg := []
	for gv in st.get("rung", []):
		rg.append(int(gv))
	st["rung"] = rg
	if not st.has("solved"):
		st["solved"] = false
	if not st.has("claimed"):
		st["claimed"] = false
	lit.clear()
	flash.clear()
	burn.clear()
	near = {}
	var d := data()
	if not d.is_empty() and d.has("pillars"):
		var rung: Array = st["rung"]
		for k2 in (d["pillars"] as Array).size():
			if rung.has(int(d["pillars"][k2]["glyph"])) or bool(st["solved"]):
				lit[k2] = true
	_summary()

func save_to(ps: Dictionary) -> void:
	if not data().is_empty():
		ps["mystery"] = st

## every tick on the planet: what's in reach (every few ticks), the wrong notes' flashes fading
func tick() -> void:
	for k in flash.keys():
		flash[k] = int(flash[k]) - 1
		if int(flash[k]) <= 0:
			flash.erase(k)
	if kind() == "beacons":
		_tick_beacons()
	if game.frame % 6 != 0:
		return
	near = {}
	var d := data()
	if d.is_empty() or game.player == null or game.player.dead:
		return
	var p: Vector2 = game.player.pos
	if kind() == "beacons":
		var bb := REACH + 6.0
		var bcs: Array = d.get("beacons", [])
		for k0 in bcs.size():
			var db: float = minf((bcs[k0]["pos"] as Vector2).distance_to(p), (bcs[k0]["stand"] as Vector2).distance_to(p))
			if db < bb:
				bb = db
				near = {"kind": "beacon", "i": k0}
		if d.has("plaque") and (d["plaque"] as Vector2).distance_to(p) < bb:
			near = {"kind": "plaque", "i": 0}
		if bool(st["solved"]) and not bool(st["claimed"]) and d.has("vault") and (d["vault"] as Vector2).distance_to(p) < REACH:
			near = {"kind": "vault", "i": 0}
		return
	var best := REACH
	var stones: Array = d.get("stones", [])
	for k in stones.size():
		var dd: float = (stones[k]["pos"] as Vector2).distance_to(p)
		if dd < best + 6.0:
			best = dd
			near = {"kind": "stone", "i": k}
	var pillars: Array = d.get("pillars", [])
	for k2 in pillars.size():
		var dd2: float = (pillars[k2]["pos"] as Vector2).distance_to(p)
		if dd2 < best:
			best = dd2
			near = {"kind": "pillar", "i": k2}
	if bool(st["solved"]) and not bool(st["claimed"]) and d.has("vault"):
		if (d["vault"] as Vector2).distance_to(p) < REACH:
			near = {"kind": "vault", "i": 0}

## F: read a stone, ring a pillar, or claim the vault (true if it did)
func interact(_m) -> bool:
	if near.is_empty():
		return false
	match String(near["kind"]):
		"stone": read(int(near["i"]))
		"pillar": ring(int(near["i"]))
		"beacon": light(int(near["i"]))
		"plaque": inscription()
		"vault": claim()
	return true

# ---- a gas giant's beacons ----
## each tick: the burning beacons give light and embers (their braziers in the Eye answer), and go out in time
func _tick_beacons() -> void:
	var d := data()
	var bcs: Array = d.get("beacons", [])
	var ech: Array = d.get("echoes", [])
	var solved := bool(st.get("solved", false))
	for k in bcs.size():
		var on := solved or burn.has(k)
		if not on:
			continue
		if not solved and game.frame >= int(burn[k]):
			burn.erase(k)
			stats["out"] = int(stats["out"]) + 1
			game.ui.toast("A beacon gutters out (%d still burning)" % burn.size(), Color(1.0, 0.7, 0.45), 3.0)
			_summary()
			continue
		if game.frame % 4 == 0:
			var bp: Vector2 = bcs[k]["pos"]
			var up := bp.normalized()
			game.vfx.light(bp + up * 4.0, 90.0, Color(1.3, 0.85, 0.45), 6)
			game._particle(bp + up * 3.0 + up.orthogonal() * randf_range(-2.0, 2.0), up * randf_range(0.3, 0.8), 24, Color(1.0, 0.7, 0.3), true, -0.01)
			if k < ech.size() and game.frame % 8 == 0:
				game.vfx.light(ech[k], 40.0, Color(1.3, 0.85, 0.45), 10)

## light beacon i: it burns BURN ticks; all five at once break the Eye's ward
func light(i: int) -> void:
	var d := data()
	var bp: Vector2 = d["beacons"][i]["pos"]
	if bool(st["solved"]):
		game.ui.toast("The beacons burn on: the Eye is open", Color(1.0, 0.85, 0.5), 2.5)
		return
	if burn.has(i):
		game.ui.toast("This beacon burns: %d s left" % int((int(burn[i]) - game.frame) / 60), Color(1.0, 0.85, 0.5), 2.0)
		return
	var m = game.player
	if m.mana < LIGHT_MANA:
		game.ui.toast("Lighting a beacon takes %d mana" % int(LIGHT_MANA), Color(1.0, 0.6, 0.5), 2.5)
		game.vfx.fizzle(bp)
		return
	m.mana -= LIGHT_MANA
	m.mana_spent_t = 30
	burn[i] = game.frame + BURN
	stats["lit"] = int(stats["lit"]) + 1
	game.audio.play("fire", bp, 0.8, 0.8)
	game.vfx.spawn(Vfx.RING, bp, Vector2.ZERO, 34, Color(1.0, 0.8, 0.4), Color(1.0, 0.4, 0.2, 0.0), 3.0, 30.0)
	game.vfx.light(bp, 110.0, Color(1.4, 0.9, 0.5), 30)
	if burn.size() >= 5:
		_solve()
	else:
		var first := not st.has("lit_once")
		st["lit_once"] = true
		game.ui.toast("The beacon of %s blazes up: %d of 5 burning (each burns %d s)" % [RUNES[i], burn.size(), BURN / 60], Color(1.0, 0.85, 0.5), 3.5)
		if first and game.quest != null:
			game.quest.say("It burns! But not for long. If all five must burn at once, we'll have to be quick between the isles.")
	_summary()

func inscription() -> void:
	var line := "Carved over the door of the Eye: \"When the five fires burn as one, the Eye shall open.\" Five braziers along the hall answer them."
	game.ui.toast(line, Color(1.0, 0.85, 0.55), 6.0)
	if not st.has("read_plaque"):
		st["read_plaque"] = true
		if game.quest != null:
			game.quest.say("Five beacons on the isles round this hall, then. Light them all, and fast: a fire up here won't wait for us.")
	_summary()

func read(i: int) -> void:
	var s: Dictionary = data()["stones"][i]
	var place := int(s["place"])
	var g := int(s["glyph"])
	var known: Dictionary = st["known"]
	var fresh := not known.has(str(place))
	known[str(place)] = g
	stats["read"] = int(stats["read"]) + 1
	game.audio.play("blink", s["pos"], 0.6, 0.7 + 0.1 * place)
	game.vfx.spawn(Vfx.RING, s["pos"], Vector2.ZERO, 30, Color(0.7, 0.9, 1.0), Color(0.4, 0.6, 1.0, 0.0), 3.0, 18.0)
	var line := "A tide-stone, carved with the %s under %d marks: the %s note of the song is the %s." % [GLYPHS[g], place + 1, NOTE[place], GLYPHS[g]]
	game.ui.toast(line, Color(0.7, 0.9, 1.0), 6.0)
	if fresh and game.quest != null:
		game.quest.say("%s Five stones, five notes. %d of them read." % [line, known.size()])
	_summary()

func ring(i: int) -> void:
	var d := data()
	if bool(st["solved"]):
		game.audio.play("blink", d["pillars"][i]["pos"], 0.7, 0.8 + 0.12 * i)
		return
	var g := int(d["pillars"][i]["glyph"])
	var rung: Array = st["rung"]
	var want := int(d["order"][rung.size()])
	stats["rung"] = int(stats["rung"]) + 1
	var pp: Vector2 = d["pillars"][i]["pos"]
	if g == want and not lit.has(i):
		rung.append(g)
		lit[i] = true
		game.audio.play("blink", pp, 0.9, 0.7 + 0.15 * rung.size())
		game.vfx.spawn(Vfx.RING, pp, Vector2.ZERO, 36, Color(0.75, 0.95, 1.0), Color(0.4, 0.7, 1.0, 0.0), 3.0, 26.0)
		game.vfx.light(pp, 50.0, Color(0.5, 0.8, 1.2), 40)
		if rung.size() >= 5:
			_solve()
		else:
			game.ui.toast("The %s rings true: the %s note" % [GLYPHS[g], NOTE[rung.size() - 1]], Color(0.75, 0.92, 1.0), 2.5)
	else:
		# (a wrong note: they all fall silent, and the song begins again)
		stats["wrong"] = int(stats["wrong"]) + 1
		rung.clear()
		lit.clear()
		flash[i] = 30
		game.audio.play("zap", pp, 0.5, 0.6)
		game.shake = maxf(game.shake, 3.0)
		game.ui.toast("A wrong note: the pillars fall silent. The song begins again from its first note", Color(1.0, 0.6, 0.5), 3.5)
	_summary()

func _solve() -> void:
	var d := data()
	st["solved"] = true
	stats["solved"] = int(stats["solved"]) + 1
	var wr: Dictionary = d["ward"]
	var air := PackedInt32Array()
	air.resize(int(wr["w"]) * int(wr["h"]))
	air.fill(Defs.AIR | 0xFF00)
	game.stamps.append({"x0": wr["x0"], "y0": wr["y0"], "w": wr["w"], "h": wr["h"], "data": air, "ax": wr["ax"], "aw": wr["aw"]})
	var mid: Vector2 = Defs.stamp_pos(int(wr["y0"]) + int(wr["h"]) / 2, int(wr["ax"]), int(wr["aw"]), Defs.k_of(int(wr["x0"]) + int(wr["w"]) / 2, int(wr["ax"])))
	for k in 60:
		var dv := Vector2.from_angle(randf() * TAU)
		game._particle(mid + dv * randf() * 10.0, dv * (0.8 + randf() * 1.8), 30 + randi() % 30, Color(0.6, 0.9, 1.0), true, 0.0)
	game.vfx.spawn(Vfx.RING, mid, Vector2.ZERO, 50, Color(0.8, 0.95, 1.0), Color(0.4, 0.7, 1.0, 0.0), 6.0, 90.0)
	game.shake = 12.0
	game.audio.play("rare")
	if kind() == "beacons":
		game.ui.toast("The five fires burn as one: the Eye opens, and the ward on its vault breaks!", Color(1.0, 0.85, 0.5), 6.0)
	else:
		game.ui.toast("The Drowned Choir sings its song again, and the ward on the vault breaks!", Color(0.6, 0.9, 1.0), 6.0)
	if game.quest != null:
		game.quest.say("The ward is gone. Whatever they sealed in that vault is yours.")
	game.save_game()

func claim() -> void:
	st["claimed"] = true
	var it: Dictionary = game.items
	if kind() == "beacons":
		it["stormcrown"] = true
		game.player.inv[Defs.VOIDESS] += int(CROWN_LOOT["essence"])
		game.player.inv[Defs.STARIRON] += int(CROWN_LOOT["star"])
		game.player.inv[Defs.WISPBAR] += int(CROWN_LOOT["wisp"])
		it["coins"] = int(it.get("coins", 0)) + int(CROWN_LOOT["coins"])
		it["potion"] = int(it.get("potion", 0)) + int(CROWN_LOOT["potion"])
		var cp: Vector2 = data()["vault"]
		game.vfx.spawn(Vfx.RING, cp, Vector2.ZERO, 60, Color(1.0, 0.9, 0.5), Color(1.0, 0.5, 0.2, 0.0), 4.0, 70.0)
		game.vfx.light(cp, 80.0, Color(1.3, 1.0, 0.6), 90)
		game.audio.play("rare", cp)
		game.ui.toast("The Storm Crown: no wind pushes you, lightning can't touch you, you levitate for nothing, and the air under the clouds can't crush you. And the Eye's hoard: %d void essence, %d star iron, %d wisp ingots, %d coins, %d draughts" % [CROWN_LOOT["essence"], CROWN_LOOT["star"], CROWN_LOOT["wisp"], CROWN_LOOT["coins"], CROWN_LOOT["potion"]], Color(1.0, 0.9, 0.55), 8.0)
		_summary()
		game.save_game()
		return
	it["tideheart"] = true
	game.player.inv[Defs.ABYSSPEARL] += int(HEART_LOOT["pearls"])
	game.player.inv[Defs.STARIRON] += int(HEART_LOOT["star"])
	it["coins"] = int(it.get("coins", 0)) + int(HEART_LOOT["coins"])
	it["potion"] = int(it.get("potion", 0)) + int(HEART_LOOT["potion"])
	var vp: Vector2 = data()["vault"]
	game.vfx.spawn(Vfx.RING, vp, Vector2.ZERO, 60, Color(0.6, 1.0, 0.95), Color(0.3, 0.6, 1.0, 0.0), 4.0, 70.0)
	game.vfx.light(vp, 80.0, Color(0.5, 1.0, 1.1), 90)
	game.audio.play("rare", vp)
	game.ui.toast("The Tide Heart: you breathe the deep, swim it fast, and neither the deep nor the abyss can crush you. And the Choir's hoard: %d abyss pearls, %d star iron, %d coins, %d draughts" % [HEART_LOOT["pearls"], HEART_LOOT["star"], HEART_LOOT["coins"], HEART_LOOT["potion"]], Color(0.6, 1.0, 0.95), 8.0)
	_summary()
	game.save_game()

## what the journal and the quest know of this world's mystery, wherever you are
func _summary() -> void:
	if data().is_empty():
		return
	var all: Dictionary = game.items.get("myst", {})
	if kind() == "beacons":
		all[str(int(game.planet.get("index", 0)))] = {"name": String(data().get("planet", "")), "kind": "beacons",
			"lit": 5 if bool(st["solved"]) else burn.size(), "read": st.has("read_plaque"),
			"solved": bool(st["solved"]), "claimed": bool(st["claimed"])}
		game.items["myst"] = all
		return
	var known: Dictionary = st["known"]
	var notes := []
	for k in 5:
		notes.append(int(known[str(k)]) if known.has(str(k)) else -1)
	all[str(int(game.planet.get("index", 0)))] = {"name": String(data().get("planet", "")), "notes": notes,
		"solved": bool(st["solved"]), "claimed": bool(st["claimed"])}
	game.items["myst"] = all

## the prompt for what's in reach ("" for none)
func prompt() -> String:
	if near.is_empty():
		return ""
	match String(near["kind"]):
		"stone": return "[F] read the tide-stone"
		"pillar": return "[F] ring the %s" % GLYPHS[int(data()["pillars"][int(near["i"])]["glyph"])]
		"vault": return "[F] take what lies on the altar"
		"beacon":
			if bool(st["solved"]) or burn.has(int(near["i"])):
				return "the beacon of %s burns" % RUNES[int(near["i"])]
			return "[F] light the beacon of %s (%d mana)" % [RUNES[int(near["i"])], int(LIGHT_MANA)]
		"plaque": return "[F] read the inscription"
	return ""
