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

var game
var st := {}
var lit := {}          # pillar index -> true while it glows (rung in turn)
var near := {}         # what's within reach now: {"kind": "stone" / "pillar" / "vault", "i": index}
var flash := {}        # pillar index -> ticks of a wrong note's red flash
var stats := {"read": 0, "rung": 0, "wrong": 0, "solved": 0}

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
	near = {}
	var d := data()
	if not d.is_empty():
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
	if game.frame % 6 != 0:
		return
	near = {}
	var d := data()
	if d.is_empty() or game.player == null or game.player.dead:
		return
	var p: Vector2 = game.player.pos
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
		"vault": claim()
	return true

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
	game.ui.toast("The Drowned Choir sings its song again, and the ward on the vault breaks!", Color(0.6, 0.9, 1.0), 6.0)
	if game.quest != null:
		game.quest.say("The ward is gone. Whatever they sealed in that vault is yours.")
	game.save_game()

func claim() -> void:
	st["claimed"] = true
	var it: Dictionary = game.items
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
	return ""
