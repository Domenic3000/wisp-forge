## The world mends itself (27 Nov; user: "an idea i would like to implement somehow to make the game world regenerate
## itself"; chose plants and trees regrow, creatures repopulate, and "a magical force that will slowly rebuild the
## terrain. maybe part of the story?"). The wisp calls it the Worldsong: every world remembers the shape it was made
## in and slowly sings itself back to it.
##
## WOUNDS: every dig, blast or chip (main's brushes, `note`) marks the BLOCK x BLOCK block of cells it's in, with the
## time. A block left alone AFTER seconds, with no mage within FAR, not near your home, a workshop, your skiff, a chest,
## a structure or a place to discover, gets a mending pass every EVERY frames (gpu_world `mend_jobs`, gen.comp's mend
## mode): ground the planet was made with fills back into empty cells from the walls of a hole inward (ore comes back
## as plain stone), and plants grow back where nothing stands; nothing within two cells of anything built is touched.
## After PASSES passes the block is let be. Saved as planet_state["wounds"].
## THE FALLEN RETURN: foes on guard in a structure (planet_state["slain"]) come back GUARD_BACK seconds after they fell,
## when you're far off (planet_state["slain_t"]). Wild creatures already come and go; bosses and wardens stay beaten.
extends RefCounted

const BLOCK := 64
const AFTER := 150.0         # seconds after the last dig there before it mends
const FAR := 260.0           # (cells) never where a mage could see it
const EVERY := 90            # frames between passes
const PASSES := 40
const CHANCE := 350          # per mil: how likely a cell with two solid sides fills in a pass
const KEEP_HOME := 170.0
const KEEP_NEAR := 110.0     # (workshops, the skiff, places to discover)
const GUARD_BACK := 1500.0   # seconds before a fallen guard is back at its post (25 minutes)
const SAY_R := 170.0

var game
var enabled := true          # (the test mode keeps it off but in its own check)
var wounds := {}             # "kc:kr" -> [surface column, row, unix time of the last dig, passes]
var ready := false
var healed := []             # [world point] blocks mended a good deal this session (the wisp says so, once)
var stats := {"noted": 0, "passes": 0, "kept": 0, "returned": 0}

func _init(g) -> void:
	game = g

func load_from(ps: Dictionary) -> void:
	wounds.clear()
	var wd = ps.get("wounds", {})
	if wd is Dictionary:
		for k in wd:
			var a = wd[k]
			if a is Array and a.size() >= 4:
				wounds[String(k)] = [int(a[0]), int(a[1]), float(a[2]), int(a[3])]
	ready = false
	healed.clear()
	# (the guards that fell before this came in: they wait from now)
	var st: Dictionary = ps.get("slain_t", {})
	var now := Time.get_unix_time_from_system()
	for gid in ps.get("slain", []):
		if not st.has(str(gid)):
			st[str(gid)] = now
	ps["slain_t"] = st

func save_to(ps: Dictionary) -> void:
	ps["wounds"] = wounds

## a dig, a blast or a chip at world point p
func note(p: Vector2) -> void:
	if p.length() > Defs.R_TOP + 40.0:
		return
	var col := int(floor(fposmod(atan2(p.y, p.x), TAU) / TAU * float(Defs.NS)))
	var row := int(floor(Defs.R_TOP - p.length()))
	var kc := col / BLOCK
	var kr := int(floor(float(row) / float(BLOCK)))
	var key := "%d:%d" % [kc, kr]
	if not wounds.has(key):
		stats["noted"] = int(stats["noted"]) + 1
	wounds[key] = [kc * BLOCK + BLOCK / 2, kr * BLOCK + BLOCK / 2, Time.get_unix_time_from_system(), 0]

static func block_mid(w: Array) -> Vector2:
	var a := (float(w[0]) + 0.5) / float(Defs.NS) * TAU
	return Vector2(cos(a), sin(a)) * (Defs.R_TOP - float(w[1]) - 0.5)

## is the block round world point q one to leave alone (someone near, or something of yours)? why, or ""
func kept(q: Vector2) -> String:
	for m in game.players:
		if not m.dead and m.pos.distance_to(q) < FAR:
			return "seen"
	var home = game.planet_state.get("home", null)
	if home != null and Vector2(float(home["pos"][0]), float(home["pos"][1])).distance_to(q) < KEEP_HOME:
		return "home"
	for st in game.workshops.list:
		if st.pos.distance_to(q) < KEEP_NEAR:
			return "workshop"
	if game.skiff != null and game.skiff.pos.distance_to(q) < KEEP_NEAR:
		return "skiff"
	for c in game.chests:
		if (c.pos as Vector2).distance_to(q) < 60.0:
			return "chest"
	if game.places != null:
		for pl in game.places.list():
			if (pl["mid"] as Vector2).distance_to(q) < KEEP_NEAR + float(pl["w"]) * 0.5:
				return "place"
	if game.builds != null:
		var off := float(BLOCK) * 0.5
		for d in [Vector2.ZERO, Vector2(off, off), Vector2(-off, off), Vector2(off, -off), Vector2(-off, -off)]:
			var up := q.normalized()
			var rt := Vector2(-up.y, up.x)
			if game.builds.label_at(q + rt * d.x + up * d.y) != "":
				return "structure"
	return ""

func tick() -> void:
	if game.space.active or game.pocket.active or game.builds == null or game.gpu == null:
		return
	if not ready:
		game.gpu.mend_prepare(game.boss_info, game.builds.sites)
		ready = true
	if game.frame % EVERY == 0 and enabled:
		_mend_one()
	if game.frame % 600 == 300 and enabled:
		_guards_return()
	if game.frame % 60 == 30 and not healed.is_empty() and not game.items.has("worldsong"):
		for hp in healed:
			if (hp as Vector2).distance_to(game.player.pos) < SAY_R:
				game.items["worldsong"] = true
				if game.quest != null:
					game.quest.say_later("Feel that? The ground here has knitted itself back together. Every world remembers the shape it was made in, and sings itself back to it while no one's looking. The old wisps called it the Worldsong. It leaves alone what you build.")
				break

func _mend_one() -> void:
	var now := Time.get_unix_time_from_system()
	for key in wounds.keys():
		var w: Array = wounds[key]
		if now - float(w[2]) < AFTER:
			continue
		var q := block_mid(w)
		if kept(q) != "":
			stats["kept"] = int(stats["kept"]) + 1
			continue
		run(w)
		w[3] = int(w[3]) + 1
		if int(w[3]) == 8:
			healed.append(q)
		if int(w[3]) >= PASSES:
			wounds.erase(key)
		return

## one mending pass over a wound's block (queued for the next frame)
func run(w: Array, chance := CHANCE) -> void:
	var row: int = clampi(int(w[1]), 0, Defs.ROWS - 1)
	var s: int = Defs.shell_of_row(row)
	var y0: int = maxi(row - BLOCK / 2, int(Defs.SH_Y0[s]))
	var y1: int = mini(row + BLOCK / 2, int(Defs.SH_Y1[s]))
	if y1 <= y0:
		return
	var n: int = int(Defs.SH_N[s])
	var cs := int(floor(float(w[0]) * float(n) / float(Defs.NS)))
	var bw := int(ceil(float(BLOCK) * float(n) / float(Defs.NS))) + 2
	game.gpu.mend_jobs.append([s, y0, y1, posmod(cs - bw / 2, n), bw, chance])
	stats["passes"] = int(stats["passes"]) + 1

## foes on guard come back to their posts a while after they fell, while you're far off
func _guards_return() -> void:
	var slain: Array = game.planet_state.get("slain", [])
	if slain.is_empty():
		return
	var st: Dictionary = game.planet_state.get("slain_t", {})
	var now := Time.get_unix_time_from_system()
	var back := []
	for gid in slain:
		var gi := int(gid)
		var t := float(st.get(str(gi), now))
		if now - t < GUARD_BACK or gi < 0 or gi >= game.builds.guards.size():
			continue
		var gp: Vector2 = game.builds.guards[gi]["pos"]
		if gp.distance_to(game.player.pos) < 600.0:
			continue
		back.append(gid)
	for b in back:
		slain.erase(b)
		st.erase(str(int(b)))
		stats["returned"] = int(stats["returned"]) + 1
	game.planet_state["slain"] = slain
	game.planet_state["slain_t"] = st
