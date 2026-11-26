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
##
## A dying star's (kind "lenses", buildings.gd `_star_relay`; 26 Nov): the SUN WELL and five SUN LENSES along its
## widest raft, and the SOLAR SANCTUM with a crystal eye on its dome. Each lens faces one of eight ways (`st["face"]`,
## saved); F turns it an eighth. The well's light goes the way it faces to the nearest lens that way (Defs.octant,
## within RELAY_RANGE), which lights and throws it on the way it faces, and so on (`relay`); reach the eye and the
## ward breaks. The vault: the SUN'S HEART (Defs.RELICS "sunheart": lava, fire, the star's heat and flares can't
## hurt you) and a hoard.
##
## A black hole's Hollow (kind "echoes", buildings.gd `_void_shrines`; 26 Nov): an ECHO SHRINE on each shard of a
## swallowed world and the SINGULARITY GATE. F at a shrine wakes the echo of that world's guardian (Defs.BOSSES, a
## little weaker, `e.d["echo"]`: main `_kill_enemy` calls `echo_falls`); beat it and the shrine's shard is yours
## (`st["won"]`, saved). Walk far off and the echo fades (wake it again). With all five, F at the Gate's
## inscription sets them and the ward breaks. The vault: the VOID HEART (Defs.RELICS "voidheart") and a hoard.
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
const RELAY_RANGE := 700.0
const SUN_LOOT := {"opal": 16, "star": 8, "ember": 24, "coins": 240, "potion": 2}
const VOID_LOOT := {"essence": 20, "star": 10, "xenite": 8, "coins": 260, "potion": 2}
const ECHO_HP := 0.7           # (an echo has this share of its guardian's health)
const ECHO_FADE := 700.0       # (walk this far from its shrine and it fades)
var echo = null                # the echo awake now (an Enemy), or null
const WAYS := ["right", "up and right", "up", "up and left", "left", "down and left", "down", "down and right"]

var game
var st := {}
var lit := {}          # pillar index -> true while it glows (rung in turn)
var near := {}         # what's within reach now: {"kind": "stone" / "pillar" / "vault", "i": index}
var flash := {}        # pillar index -> ticks of a wrong note's red flash
var stats := {"read": 0, "rung": 0, "wrong": 0, "solved": 0, "lit": 0, "out": 0}
var burn := {}         # (beacons) index -> the frame it goes out at
var path := []         # (lenses) the lenses the well's light reaches, in order (0, the well, first)
var path_eye := false  # (lenses) and whether it goes on into the sanctum's eye
var path_end := Vector2.ZERO   # (lenses) where the last beam ends, if it reaches nothing

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
	if kind() == "echoes":
		var wn := []
		for wv in st.get("won", []):
			wn.append(int(wv))
		st["won"] = wn
		echo = null
	if kind() == "lenses":
		var fc := []
		for fv in st.get("face", d.get("facing", [])):
			fc.append(int(fv))
		st["face"] = fc
		relay()
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
	if kind() == "lenses":
		_tick_lenses()
	if kind() == "echoes":
		_tick_echoes()
	if game.frame % 6 != 0:
		return
	near = {}
	var d := data()
	if d.is_empty() or game.player == null or game.player.dead:
		return
	var p: Vector2 = game.player.pos
	if kind() == "echoes":
		var be := REACH + 6.0
		var shs: Array = d.get("shrines", [])
		for k6 in shs.size():
			var de: float = minf((shs[k6]["pos"] as Vector2).distance_to(p), (shs[k6]["stand"] as Vector2).distance_to(p))
			if de < be:
				be = de
				near = {"kind": "shrine", "i": k6}
		if d.has("plaque") and (d["plaque"] as Vector2).distance_to(p) < be:
			near = {"kind": "plaque", "i": 0}
		if bool(st["solved"]) and not bool(st["claimed"]) and d.has("vault") and (d["vault"] as Vector2).distance_to(p) < REACH:
			near = {"kind": "vault", "i": 0}
		return
	if kind() == "lenses":
		var bl := REACH + 6.0
		var lzs: Array = d.get("lenses", [])
		for k1 in lzs.size():
			var dl: float = minf((lzs[k1]["pos"] as Vector2).distance_to(p), (lzs[k1]["stand"] as Vector2).distance_to(p))
			if dl < bl:
				bl = dl
				near = {"kind": "lens", "i": k1}
		if d.has("plaque") and (d["plaque"] as Vector2).distance_to(p) < bl:
			near = {"kind": "plaque", "i": 0}
		if bool(st["solved"]) and not bool(st["claimed"]) and d.has("vault") and (d["vault"] as Vector2).distance_to(p) < REACH:
			near = {"kind": "vault", "i": 0}
		return
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
		"lens": turn(int(near["i"]))
		"shrine": wake(int(near["i"]))
		"plaque": inscription()
		"vault": claim()
	return true

# ---- a dying star's sun lenses ----
## Follow the well's light: from each lit lens the way it faces to the nearest lens that way not yet lit (or the
## eye), within RELAY_RANGE. Sets `path`, `path_eye`, `path_end`.
func relay() -> void:
	var d := data()
	var lzs: Array = d.get("lenses", [])
	path = []
	path_eye = false
	if lzs.is_empty():
		return
	var face: Array = st.get("face", [])
	var cur := 0
	path.append(0)
	for step in lzs.size() + 1:
		var from: Vector2 = lzs[cur]["pos"]
		var f := int(face[cur]) if cur < face.size() else 0
		var best := -1
		var bd := RELAY_RANGE
		for q in lzs.size():
			if path.has(q):
				continue
			var to: Vector2 = lzs[q]["pos"]
			var dq := from.distance_to(to)
			if dq < bd and Defs.octant(from, to) == f:
				bd = dq
				best = q
		if d.has("eye"):
			var de: float = from.distance_to(d["eye"])
			if de < bd and Defs.octant(from, d["eye"]) == f:
				path_eye = true
				path_end = d["eye"]
				return
		if best < 0:
			path_end = from + Defs.octant_dir(from, f) * 260.0
			return
		path.append(best)
		cur = best

## turn lens i an eighth (the way the sun goes)
func turn(i: int) -> void:
	var face: Array = st["face"]
	var before := path.size()
	face[i] = (int(face[i]) + 1) % 8
	var lp: Vector2 = data()["lenses"][i]["pos"]
	game.audio.play("creak", lp, 0.5, 1.3)
	game.vfx.spawn(Vfx.RING, lp, Vector2.ZERO, 16, Color(1.0, 0.85, 0.4), Color(1.0, 0.5, 0.2, 0.0), 1.5, 12.0)
	stats["rung"] = int(stats["rung"]) + 1
	relay()
	if bool(st["solved"]):
		return
	if path_eye:
		_solve()
	elif path.size() > before:
		game.ui.toast("The light reaches a lens further: %d of 5 lit" % (path.size() - 1), Color(1.0, 0.85, 0.5), 2.5)
		game.audio.play("blink", lp, 0.6, 0.7 + 0.12 * path.size())
		if not st.has("lit_once") and game.quest != null:
			st["lit_once"] = true
			game.quest.say("It caught the light! Lens to lens, then: each one has to throw it on to the next.")
	_summary()

## each tick: light where the beams fall, the lit lenses glowing, and the sanctum's braziers answering them
func _tick_lenses() -> void:
	if game.frame % 4 != 0:
		return
	var d := data()
	var lzs: Array = d.get("lenses", [])
	var ech: Array = d.get("echoes", [])
	var solved := bool(st.get("solved", false))
	for k in path.size():
		var lp: Vector2 = lzs[int(path[k])]["pos"]
		game.vfx.light(lp, 60.0 if k > 0 else 80.0, Color(1.4, 1.0, 0.55), 6)
		if int(path[k]) > 0 and int(path[k]) - 1 < ech.size() and game.frame % 8 == 0:
			game.vfx.light(ech[int(path[k]) - 1], 40.0, Color(1.3, 0.9, 0.5), 10)
	if path_eye or solved:
		game.vfx.light(d["eye"], 90.0, Color(1.5, 1.1, 0.6), 6)

# ---- a black hole's echoes ----
## F at shrine i: wake the echo of its world's guardian, near the shrine and away from you
func wake(i: int) -> void:
	var d := data()
	var sh: Dictionary = d["shrines"][i]
	var won: Array = st["won"]
	var biome: String = sh["biome"]
	var bd: Dictionary = Defs.BOSSES[biome]
	if won.has(i):
		game.ui.toast("Its shard is yours: the shrine is still", Color(0.8, 0.7, 1.0), 2.5)
		return
	if echo != null and not echo.dead:
		game.ui.toast("The echo of %s is already awake" % bd["name"] if int(echo.d.get("echo", -1)) == i else "Another echo is awake: beat it first", Color(0.85, 0.7, 1.0), 2.5)
		return
	var spot: Vector2 = game.summoning.find_spot({"pos": sh["pos"]}, biome, game.player)
	if spot == Vector2.INF:
		spot = (sh["pos"] as Vector2) + (sh["pos"] as Vector2).normalized() * 50.0
	var ge = game.spawn_enemy("boss_" + biome, spot)
	ge.d = ge.d.duplicate()
	ge.d["echo"] = i
	ge.hp *= ECHO_HP
	ge.max_hp *= ECHO_HP
	ge.home = spot
	ge.tether = 520.0             # (as a called guardian: summoning.gd LEASH, CEIL, ARENA)
	ge.ceil = 110.0
	ge.arena = 170.0
	ge.awake = true
	ge.act_cd = 60
	echo = ge
	stats["rung"] = int(stats["rung"]) + 1
	var col := Color(0.75, 0.5, 1.0)
	for kk in 40:
		var dv: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.6, 2.2)
		game.vfx.spawn(Vfx.STREAK, spot, dv, 18 + randi() % 14, col.lightened(0.5), Color(col.r, col.g, col.b, 0.0), 1.5, 1.0, true, 0.02, 0.9)
	game.vfx.spawn(Vfx.RING, sh["pos"], Vector2.ZERO, 24, col, Color(col.r, col.g, col.b, 0.0), 2.0, 40.0)
	game.vfx.screen_flash(col, 0.4)
	game.shake = 12.0
	game.audio.play("roar", spot, 1.0, 0.8)
	game.ui.toast("The shard stirs: THE ECHO OF %s, %s, wakes out of the dark!" % [String(bd["name"]).to_upper(), String(bd["title"]).to_upper()], col, 5.0)
	if not st.has("woke_once") and game.quest != null:
		st["woke_once"] = true
		game.quest.say("An echo of a guardian this world once had... It's only an echo. Beat it, and the shard is ours.")

## an echo is beaten (main `_kill_enemy`): its shrine's shard is yours
func echo_falls(e) -> void:
	var i := int(e.d.get("echo", -1))
	if echo == e:
		echo = null
	var won: Array = st["won"]
	if i < 0 or won.has(i):
		return
	won.append(i)
	var sp: Vector2 = data()["shrines"][i]["pos"]
	game.vfx.spawn(Vfx.RING, sp, Vector2.ZERO, 50, Color(0.85, 0.7, 1.0), Color(0.5, 0.3, 1.0, 0.0), 4.0, 60.0)
	game.vfx.light(sp, 70.0, Color(0.9, 0.6, 1.3), 60)
	game.audio.play("rare", sp)
	game.ui.toast("The echo fades, and the shrine gives up its shard: %d of 5" % won.size(), Color(0.85, 0.7, 1.0), 4.0)
	if won.size() >= 5 and game.quest != null:
		game.quest.say("Five shards. Back to the Gate, then: set them in it.")
	_summary()
	game.save_game()

## each tick: the won shards glow in their shrines and in the Gate's braziers; an echo left far behind fades
func _tick_echoes() -> void:
	if echo != null:
		if echo.dead:
			echo = null
		else:
			var sh: Dictionary = data()["shrines"][int(echo.d.get("echo", 0))]
			if game.player.pos.distance_to(sh["pos"]) > ECHO_FADE:
				echo.dead = true
				echo = null
				game.ui.toast("Too far from its shrine: the echo fades back into the dark", Color(0.8, 0.7, 1.0), 3.0)
	if game.frame % 6 != 0:
		return
	var d := data()
	var shs: Array = d.get("shrines", [])
	var ech: Array = d.get("echoes", [])
	var won: Array = st.get("won", [])
	for k in shs.size():
		var lit_k: bool = won.has(k) or bool(st.get("solved", false))
		game.vfx.light(shs[k]["pos"], 50.0 if not lit_k else 30.0, Color(0.7, 0.5, 1.2) if not lit_k else Color(0.5, 0.4, 0.7), 8)
	for q in mini(won.size(), ech.size()):
		game.vfx.light(ech[q], 40.0, Color(0.85, 0.6, 1.3), 10)

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
	if kind() == "echoes":
		var won: Array = st["won"]
		if won.size() >= 5 and not bool(st["solved"]):
			_solve()
			_summary()
			return
		var ln2 := "Carved on the Gate: \"Five worlds it swallowed; their echoes keep their shards. Bring the five, and the Gate shall open.\" Five hollows in it, %d filled." % won.size()
		game.ui.toast(ln2, Color(0.85, 0.75, 1.0), 6.0)
		if not st.has("read_plaque"):
			st["read_plaque"] = true
			if game.quest != null:
				game.quest.say("A shrine on each shard of a world, then, and an echo in each. Five shards for five hollows.")
		_summary()
		return
	if kind() == "lenses":
		var ln := "Carved over the door of the Sanctum: \"Lead the fire of the well, lens to lens, into the eye, and the Sanctum shall open.\" Five braziers along the hall wait to be lit."
		game.ui.toast(ln, Color(1.0, 0.85, 0.55), 6.0)
		if not st.has("read_plaque"):
			st["read_plaque"] = true
			if game.quest != null:
				game.quest.say("The well's fire, lens to lens, into the eye on the dome. Each lens turns: F turns it an eighth. Watch where the light goes.")
		_summary()
		return
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
	elif kind() == "echoes":
		game.ui.toast("You set the five shards in the Gate: the dark folds back, and its ward breaks!", Color(0.85, 0.7, 1.0), 6.0)
	elif kind() == "lenses":
		game.ui.toast("The well's fire pours into the eye: the Sanctum blazes, and the ward on its vault breaks!", Color(1.0, 0.85, 0.5), 6.0)
	else:
		game.ui.toast("The Drowned Choir sings its song again, and the ward on the vault breaks!", Color(0.6, 0.9, 1.0), 6.0)
	if game.quest != null:
		game.quest.say("The ward is gone. Whatever they sealed in that vault is yours.")
	game.save_game()

func claim() -> void:
	st["claimed"] = true
	var it: Dictionary = game.items
	if kind() == "echoes":
		it["voidheart"] = true
		game.player.max_mana += 60.0
		game._apply_gear()
		game.player.inv[Defs.VOIDESS] += int(VOID_LOOT["essence"])
		game.player.inv[Defs.STARIRON] += int(VOID_LOOT["star"])
		game.player.inv[Defs.XENITE] += int(VOID_LOOT["xenite"])
		it["coins"] = int(it.get("coins", 0)) + int(VOID_LOOT["coins"])
		it["potion"] = int(it.get("potion", 0)) + int(VOID_LOOT["potion"])
		var vp2: Vector2 = data()["vault"]
		game.vfx.spawn(Vfx.RING, vp2, Vector2.ZERO, 60, Color(0.85, 0.65, 1.0), Color(0.4, 0.2, 1.0, 0.0), 4.0, 70.0)
		game.vfx.light(vp2, 80.0, Color(1.0, 0.7, 1.4), 90)
		game.audio.play("rare", vp2)
		game.ui.toast("The Void Heart: +60 max mana, spells cost a sixth less, and the rifts can't unmake you. And the Gate's hoard: %d void essence, %d star iron, %d xenite, %d coins, %d draughts" % [VOID_LOOT["essence"], VOID_LOOT["star"], VOID_LOOT["xenite"], VOID_LOOT["coins"], VOID_LOOT["potion"]], Color(0.85, 0.75, 1.0), 8.0)
		_summary()
		game.save_game()
		return
	if kind() == "lenses":
		it["sunheart"] = true
		game.player.inv[Defs.FIREOPAL] += int(SUN_LOOT["opal"])
		game.player.inv[Defs.STARIRON] += int(SUN_LOOT["star"])
		game.player.inv[Defs.EMBER] += int(SUN_LOOT["ember"])
		it["coins"] = int(it.get("coins", 0)) + int(SUN_LOOT["coins"])
		it["potion"] = int(it.get("potion", 0)) + int(SUN_LOOT["potion"])
		var sp: Vector2 = data()["vault"]
		game.vfx.spawn(Vfx.RING, sp, Vector2.ZERO, 60, Color(1.0, 0.9, 0.5), Color(1.0, 0.5, 0.2, 0.0), 4.0, 70.0)
		game.vfx.light(sp, 80.0, Color(1.5, 1.1, 0.6), 90)
		game.audio.play("rare", sp)
		game.ui.toast("The Sun's Heart: lava and fire can't hurt you, nor a star's heat and flares, and Fireball strikes harder. And the Sanctum's hoard: %d fire opal, %d star iron, %d ember crystal, %d coins, %d draughts" % [SUN_LOOT["opal"], SUN_LOOT["star"], SUN_LOOT["ember"], SUN_LOOT["coins"], SUN_LOOT["potion"]], Color(1.0, 0.9, 0.55), 8.0)
		_summary()
		game.save_game()
		return
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
	if kind() == "echoes":
		all[str(int(game.planet.get("index", 0)))] = {"name": String(data().get("planet", "")), "kind": "echoes",
			"shards": (st.get("won", []) as Array).size(), "read": st.has("read_plaque"),
			"solved": bool(st["solved"]), "claimed": bool(st["claimed"])}
		game.items["myst"] = all
		return
	if kind() == "lenses":
		all[str(int(game.planet.get("index", 0)))] = {"name": String(data().get("planet", "")), "kind": "lenses",
			"lit": 5 if bool(st["solved"]) else maxi(0, path.size() - 1), "read": st.has("read_plaque"),
			"solved": bool(st["solved"]), "claimed": bool(st["claimed"])}
		game.items["myst"] = all
		return
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
		"plaque":
			if kind() == "echoes" and (st.get("won", []) as Array).size() >= 5 and not bool(st["solved"]):
				return "[F] set the five shards in the Gate"
			return "[F] read the inscription"
		"shrine":
			var sbm := String(data()["shrines"][int(near["i"])]["biome"])
			if (st.get("won", []) as Array).has(int(near["i"])):
				return "the echo shrine of %s: its shard is yours" % Defs.BIOMES[sbm]["name"]
			return "[F] wake the echo of %s" % Defs.BOSSES[sbm]["name"]
		"lens":
			var li := int(near["i"])
			var fw := int(st["face"][li])
			return "[F] turn the %s (it faces %s)" % ["sun well's lens" if li == 0 else "sun lens", WAYS[fw]]
	return ""
