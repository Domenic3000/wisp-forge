## The main quest (user, 23 Nov: "Maybe we just add a main quest system to guide the player through the main
## progressions?"; chose: the wisp companion speaks it, a line on the HUD and a journal (L), and special rewards:
## the wisp's own powers, found nowhere else).
##
## A chapter is a list of steps, each with what to do (`title`, the HUD's line), what the wisp says when it
## comes up (`say`), how to do it (`how`, the journal), and when it's done (`need`: any of its conditions holds,
## so a step already done by another way ticks at once). Chapter 0 is the first planet (16 steps, from digging
## in, down to its heart for the Core Drive the skiff is built round, to the first voyage: user, 24 Nov); each
## later planet you land on gets a chapter of its own (its ore, its hazards' wards, then the next world of the
## system you haven't been to and the key to its barrier if it has one; once you've been to them all, the
## Starsail and its cells, on to another star system). Chapters follow the planet you're on, in any order: a
## step done once (`items["qdone"]` "ch:id") stays done and never pays twice, and a chapter finished
## (`items["qfin"]`) is never taken up again. Progress is `items["quest"]` {"ch", "at", "v"};
## the powers are `items["wisp_lantern"]`, `["wisp_sense"]`, `["wisp_ward"]`, `["wisp_hands"]` (main reads them).
## A journey from before the quest catches up silently the first time, with the powers it has earned.
extends RefCounted

const Vfx := preload("res://scripts/vfx.gd")
const MysteryArt := preload("res://scripts/mystery.gd")

const SAY_TICKS := 60 * 8
const HULL_STEP := 180       # (the first ship built out: the keel's 134 cells and fifty more)
const POWERS := {
	"lantern": {"name": "Wisp Lantern", "desc": "The wisp's light reaches twice as far, and the fog lifts before it."},
	"sense": {"name": "Ore Sense", "desc": "Every few seconds the wisp pulses, and ore veins near you glow a moment, through rock and fog."},
	"ward": {"name": "Wisp Ward", "desc": "The wisp takes one hit for you, then needs half a minute to gather itself again."},
	"hands": {"name": "Wisp Hands", "desc": "You dig and shape from half again as far, and essence drifts to you from twice as far."},
}

var game
var steps: Array = []
var chapter := -1
var at := 0
var say_text := ""
var say_t := 0
var stats := {"done": 0, "said": 0, "rewards": 0}

func _init(g) -> void:
	game = g

## a game started or loaded: read progress from its items again
func reset() -> void:
	chapter = -1
	steps = []
	at = 0
	say_t = 0
	say_text = ""

## every tick (main `_tick`): every half second, tick off what's done and speak up for what's next
func tick() -> void:
	if say_t > 0:
		say_t -= 1
	if game.testing and not game.quest_test:
		return
	if game.frame % 30 != 0:
		return
	var q: Dictionary = game.items.get("quest", {})
	var first := q.is_empty()
	# (a journey from before the barriers, 24 Nov: its chapters were laid out by index, so it catches up
	# again from the top, quietly)
	var quiet := first or int(q.get("v", 1)) < 5
	if quiet and not first:
		q = {"ch": int(q.get("ch", 0)), "at": 0}
	var ch := int(q.get("ch", 0))
	# (a world whose chapter isn't finished: its own chapter begins)
	var here := int(game.planet.get("index", 0))
	_mystery_tick(here)
	if Defs.is_exotic(here):
		here = ch                    # (an exotic world has no chapter of its own: its mystery is its quest)
	if here != ch and not finished(here):
		ch = here
		q = {"ch": ch, "at": 0}
	if ch != chapter:
		chapter = ch
		steps = chapter_steps(ch)
		at = int(q.get("at", 0))
		if not quiet:
			_announce()
	var moved := false
	while at < steps.size() and (_met(steps[at]) or _was_done(steps[at])):
		_complete(steps[at], quiet or _was_done(steps[at]))
		at += 1
		moved = true
	if at >= steps.size():
		if not game.items.has("qfin"):
			game.items["qfin"] = {}
		(game.items["qfin"] as Dictionary)[str(chapter)] = true
	game.items["quest"] = {"ch": chapter, "at": at, "v": 5}
	if first:
		say(("I'm your wisp. I'll guide you from here. " + String(steps[at]["say"])) if at < steps.size() else "I'm your wisp. I'll light your way.")
	elif moved:
		_announce()

## the HUD's line: what to do now ("" when the chapter's done); on an exotic world, its mystery's next step
func hud_line() -> String:
	if Defs.is_exotic(int(game.planet.get("index", 0))) and not game.space.active:
		for ms in mystery_steps():
			if not bool(ms["done"]):
				return String(ms["title"])
	if at >= steps.size():
		return ""
	return String(steps[at]["title"])

func say(t: String) -> void:
	say_text = t
	say_t = SAY_TICKS
	stats["said"] = int(stats["said"]) + 1
	if game.space.active and not game.space.live:
		game.ui.toast("Wisp: " + t, Color(0.62, 0.86, 1.0), 6.0)     # (out there the overlay draws no bubble)

func _announce() -> void:
	if at < steps.size():
		say(String(steps[at]["say"]))

## has chapter c been finished? (never taken up again)
func finished(c: int) -> bool:
	return (game.items.get("qfin", {}) as Dictionary).has(str(c))

func _was_done(st: Dictionary) -> bool:
	return (game.items.get("qdone", {}) as Dictionary).has("%d:%s" % [chapter, String(st["id"])])

func _complete(st: Dictionary, quiet: bool) -> void:
	if not game.items.has("qdone"):
		game.items["qdone"] = {}
	(game.items["qdone"] as Dictionary)["%d:%s" % [chapter, String(st["id"])]] = true
	stats["done"] = int(stats["done"]) + 1
	var pw := String(st.get("power", ""))
	if pw != "" and not game.items.has("wisp_" + pw):
		game.items["wisp_" + pw] = true
		if not quiet:
			game.ui.toast("The wisp grows: %s. %s" % [POWERS[pw]["name"], POWERS[pw]["desc"]], Color(0.7, 0.95, 1.0), 7.0)
			game.vfx.spawn(Vfx.RING, game.wisp, Vector2.ZERO, 40, Color(0.7, 0.95, 1.0), Color(0.4, 0.7, 1.0, 0.0), 4.0, 40.0)
			game.audio.play("blink", game.wisp, 0.9)
	if quiet:
		return
	var rw: Dictionary = st.get("reward", {})
	var got := []
	if rw.has("coins"):
		game.items["coins"] = int(game.items.get("coins", 0)) + int(rw["coins"])
		got.append("%d coins" % int(rw["coins"]))
	if rw.has("potion"):
		game.items["potion"] = int(game.items.get("potion", 0)) + int(rw["potion"])
		got.append("a Healing Draught" if int(rw["potion"]) == 1 else "%d Healing Draughts" % int(rw["potion"]))
	if rw.has("cells"):
		game.player.inv[Defs.WISPCELL] += int(rw["cells"])
		got.append("%d Wisp Cells" % int(rw["cells"]))
	if not got.is_empty():
		stats["rewards"] = int(stats["rewards"]) + 1
	game.ui.toast("Done: %s%s" % [String(st["title"]), (" · " + ", ".join(got)) if not got.is_empty() else ""], Color(1.0, 0.86, 0.45), 4.0)

## is step st done? (any one of its conditions)
func _met(st: Dictionary) -> bool:
	for c in st["need"]:
		if _holds(c):
			return true
	return false

func _holds(c: Array) -> bool:
	var inv: PackedInt32Array = game.player.inv
	match String(c[0]):
		"held": return inv[int(c[1])] >= int(c[2])
		"count": return int(game.items.get(String(c[1]), 0)) >= int(c[2])
		"found": return game.ore_found(int(c[1]))
		"spell": return game.known.has(String(c[1]))
		"tier": return int(game.tier) >= int(c[1])
		"item": return game.items.has(String(c[1]))
		"landed": return game.landed_on(int(c[1]))
		"landed_other":
			# (any planet of the round but the one you started on)
			for k in (game.items.get("landed", {}) as Dictionary):
				var li := int(k)
				if li != int(c[1]) and not Defs.is_exotic(li):
					return true
			return false
		"landed_sys":
			# (any planet of another star system than c[1])
			for k2 in (game.items.get("landed", {}) as Dictionary):
				var lj := int(k2)
				if not Defs.is_exotic(lj) and Defs.system_of(lj) != int(c[1]):
					return true
			return false
		"station":
			if game.items.has("st_" + String(c[1])):
				return true
			for s in game.workshops.list:
				if s.kind == String(c[1]):
					return true
			return false
		"learned":
			for r in game.recipes:
				if String(r["id"]) == String(c[1]):
					return game.knows(r)
			return false
		"heat": return game.heat_ward or game.items.has("cinderheart")
	return false

## the steps of chapter ch (planet ch)
func chapter_steps(ch: int) -> Array:
	if ch == 0:
		return _first_chapter()
	return _world_chapter(ch)

## (the chapter read from the save, if no tick has done it yet: the journal can open first)
func ensure() -> void:
	if chapter >= 0:
		return
	var q: Dictionary = game.items.get("quest", {})
	chapter = int(q.get("ch", 0))
	steps = chapter_steps(chapter)
	at = int(q.get("at", 0))

func chapter_title(ch: int) -> String:
	if ch == 0:
		return "Chapter One: The First Light"
	return "Chapter %d: %s" % [ch + 1, String(Defs.make_planet(ch)["name"])]

func _first_chapter() -> Array:
	var tg := open_target(0)
	var nxt := String(Defs.make_planet(tg)["name"]) if tg >= 0 else "another world"
	return [
		{"id": "dig", "title": "Dig in: gather some stone", "need": [["held", Defs.STONE, 15], ["tier", 2]],
			"say": "Let's begin: hold right-click on the ground to dig, and gather some stone.",
			"how": "Hold the right mouse button on the ground to dig. What you dig goes into your satchel (I). Digging costs a little mana, harder rock more."},
		{"id": "spark", "title": "Forge Spark Bolt at the Wisp Forge", "need": [["spell", "spark"]], "reward": {"potion": 1},
			"say": "Open the Wisp Forge (C) and forge Spark Bolt: stone, coal and a little copper ore. Copper glints orange in the rock.",
			"how": "C opens the Wisp Forge. Spark Bolt is under Spells: stone, coal and a little copper ore. Coal is black, copper ore orange, both near the surface."},
		{"id": "kiln", "title": "Set down a Kiln", "need": [["station", "kiln"], ["tier", 2]], "reward": {"coins": 10},
			"say": "Workshops refine what you gather. Forge a Kiln at the Wisp Forge (C, Workshops), then set it down from your satchel. It fires sand into glass.",
			"how": "Open the Wisp Forge (C), Workshops: forge a Kiln (stone and dirt). It goes into your satchel: open it (I), click the Kiln and click level ground to set it down. F beside it opens it: click Glass under \"It makes\" (or load sand yourself), feed its fire with coal or wood."},
		{"id": "smelt", "title": "Smelt copper ingots", "need": [["held", Defs.COPPERBAR, 1], ["tier", 2]], "reward": {"coins": 10},
			"say": "Now a Smelter: stone, copper ore and twelve bricks (fire mud in the kiln). Load it with copper ore, feed its fire, and it makes Copper Ingots.",
			"how": "The Smelter (Wisp Forge, Workshops) costs 30 stone, 12 bricks and 4 copper ore; the Kiln fires 3 mud into 4 bricks. Keep it off plank floors: its sparks catch. F beside it: click Copper Ingot under \"It makes\" to load copper ore (the Amount sets how many batches), click coal, wood or planks to feed the fire. It warms up, then works batch after batch; take the ingots out when they're made."},
		{"id": "copper", "title": "Forge the Copper Focus", "need": [["tier", 2]], "power": "lantern",
			"say": "Six copper ingots and some stone make the Copper Focus: harder rock, and faster digging.",
			"how": "At the Wisp Forge (C), Staff & Body: the Copper Focus. It digs deepstone, ember, wisp ore and brick, and digs faster."},
		{"id": "levitate", "title": "Forge Levitation", "need": [["item", "levitate"]], "reward": {"potion": 1},
			"say": "Deeper down, wisp ore glows blue: the Copper Focus cuts it. Three copper ingots, four wisp ore and ten leaves forge Levitation.",
			"how": "Wisp ore lies deep, glowing blue; only the Copper Focus cuts it. Levitation is at the Wisp Forge (C, Staff & Body). Hold jump in the air to float on your mana. Smelt wisp ore too (3 to an ingot): you'll want Wisp Ingots."},
		{"id": "mana", "title": "Forge the Mana Crystal", "need": [["item", "mana_crystal"], ["tier", 3]], "reward": {"potion": 1},
			"say": "Your first Wisp Ingot! Three of them and eight prism crystals forge a Mana Crystal: more mana, and it comes back faster.",
			"how": "At the Wisp Forge (C), Staff & Body: the Mana Crystal (3 Wisp Ingots, 8 Prism Crystal). Prism crystal glows pink-violet in the rock. +70 max mana, and mana comes back almost half again as fast. Each new focus also makes digging cheaper and brings mana back faster."},
		{"id": "obsidian", "title": "Forge the Obsidian Focus", "need": [["tier", 3]], "reward": {"coins": 20},
			"say": "Deeper still you'll need the Obsidian Focus: obsidian (or ash and sand fired in a kiln), ember crystals and two wisp ingots.",
			"how": "Obsidian forms where lava meets water deep down, or fire ash and sand together in a Kiln. Ember crystals glow red in the deep. Forge the Obsidian Focus (C, Staff & Body): it cuts obsidian and magma rock."},
		{"id": "altar", "title": "Build a Summoning Altar", "need": [["station", "altar"], ["count", "skiff_plans", 1], ["learned", "skiff"]], "reward": {"coins": 15},
			"say": "Listen: the guardians of this world keep a wisp shipwright's plans for a skiff, torn in halves. To face one, build a Summoning Altar where it rules.",
			"how": "The Wisp Forge (C), Workshops: the Summoning Altar (masonry, stone and two prism crystals); set it down from your satchel. Villagers know which guardians answer here and where their altar must stand."},
		{"id": "guardian1", "title": "Summon a guardian and beat it", "need": [["count", "skiff_plans", 1], ["learned", "skiff"]], "reward": {"potion": 1},
			"say": "Forge a guardian's sigil at the Wisp Forge, lay it on the altar in its own land (F), and beat what comes. It keeps half the plans.",
			"how": "The Wisp Forge's Summoning tab has a sigil for each guardian of this world you can call. Set the altar down in that guardian's biome, then F at it with the sigil. Healing Draughts help; it comes for you if you hide."},
		{"id": "guardian2", "title": "Beat a second guardian: the skiff's plans", "need": [["learned", "skiff"]], "power": "sense", "reward": {"coins": 40},
			"say": "Half the plans! Another guardian keeps the rest. Summon a second one and the skiff's plans are whole.",
			"how": "Any other guardian of this world: forge its sigil and call it at an altar in its biome. With both halves you know the Wisp Skiff's recipe; it's built round a Core Drive from the planet's heart."},
		{"id": "heat", "title": "Forge the Heat Ward", "need": [["heat"], ["item", "heart"]], "reward": {"potion": 1},
			"say": "The deep mantle's heat would cook you. Forge the Heat Ward: ember crystals, frost and obsidian.",
			"how": "The Heat Ward (C, Staff & Body) lets you bear the mantle's heat near the planet's heart. Frost crystals lie in cold caves, ember crystals glow red in the deep."},
		{"id": "vulkhar", "title": "Defeat Vulkhar at the planet's heart", "need": [["item", "heart"]], "power": "ward",
			"say": "Now down to the heart of the world. Vulkhar the Ember Golem guards it: beat him for the Ember Heart. Bring draughts.",
			"how": "Dig down and down, through magma rock, to the heart of the planet. Vulkhar wakes when you come near. Healing Draughts (H) help; so does fighting him where he can reach you, or he comes for you."},
		{"id": "siphon", "title": "Forge the Core Siphon", "need": [["tier", 4]], "reward": {"coins": 30},
			"say": "With the Ember Heart, forge the Core Siphon: it cuts the planet's core itself.",
			"how": "At the Wisp Forge, Staff & Body: the Core Siphon (obsidian and wisp ingots, and the Ember Heart). It cuts warded stone and the Planet Core."},
		{"id": "core", "title": "Harvest 30 Planet Core", "need": [["held", Defs.CORE, 30], ["item", "drive"]],
			"say": "Harvest the core: thirty pieces of it. It burns bright at the very middle of the world.",
			"how": "The Planet Core is the glowing heart below the magma. Dig it with the Core Siphon: thirty pieces for a Core Drive."},
		{"id": "drive", "title": "Forge the Core Drive", "need": [["item", "drive"]], "power": "hands", "reward": {"coins": 30},
			"say": "Bind the world's heart into a Core Drive: thirty core, ten wisp ore and four copper ingots. A ship is built round it.",
			"how": "At the Wisp Forge, Travel: the Core Drive. The Wisp Skiff can't be forged without one."},
		{"id": "skiff", "title": "Forge your ship's keel", "need": [["item", "skiff"]], "reward": {"coins": 25},
			"say": "A ship begins with its keel: eighty-two planks, thirty-two wood, twenty wisp ore, four wisp ingots and three copper ingots round the Core Drive. K calls it to you, F boards.",
			"how": "At the Wisp Forge, Travel: the Wisp Keel (it needs the Core Drive). K calls it beside you, F boards or steps out. Steer with the movement keys (W up), or hold cast toward the cursor."},
		{"id": "hull", "title": "Build out your ship", "need": [["count", "hull_cells", HULL_STEP]], "reward": {"coins": 30},
			"say": "A keel won't keep the wind off. Set it down, board it and press B: the ship builder. Lay a hull round the helm, a canopy of glass if you like: whatever you build, it flies.",
			"how": "Land the ship (or dock it at a station or outpost), board it (F) and press B for the ship builder. Left button lays the chosen part (planks, hull plating, glass, wisp engines...), right button cuts away; every cell must join the ship. Build it out to %d cells. Wisp engine cells push it; a bigger ship needs more of them. B closes the builder. Out of the builder you can only mend (hold R)." % HULL_STEP},
		{"id": "pocket", "title": "Step into your ship's pocket", "need": [["item", "pocket_seen"]], "reward": {"potion": 1},
			"say": "Your ship is bigger inside than out. See the violet seam on its hull? That's its door: stand by it and press F.",
			"how": "Stand by the ship's door (the violet seam on its hull: the ship builder's Pocket Door moves it) and press F. Inside is a pocket dimension, an isle in a nebula: build there as you would in the world (B), grow the isle at its heart, and step out at the arch. Once you've been in, Wisp Recall takes you back there from anywhere."},
		{"id": "star", "title": "Mine Star Iron from an asteroid", "need": [["found", Defs.STARIRON], ["landed_other", 0]], "reward": {"potion": 1},
			"say": "Fly the skiff up out of the sky. The metallic asteroids above hold Star Iron at their hearts: step out (F) and dig.",
			"how": "Fly straight up out of the atmosphere. Asteroids hang above the planet (the minimap, top right, shows the nearest). Step out with F, push yourself with the staff's jet (hold cast) and dig the dark metallic rock; Star Iron glints blue-white inside. The skiff's fittings and the keys to the barriers round other worlds need it."},
		{"id": "voyage", "title": "Fly to %s" % nxt, "need": [["landed_other", 0]], "reward": {"coins": 50},
			"say": "Fly up, and on to %s: no barrier stands round it. The minimap shows the way. I'll be with you." % nxt,
			"how": "Fly up out of the sky and head for %s (on the minimap, top right; point at it for its name). Once it's clearly nearer than home the journey begins, and you come down into its sky. Worlds wrapped in a barrier (a storm belt, a radiation belt, a shard ring...) need a key forged at the Wisp Forge: the minimap names which." % nxt},
	]

## a later world's chapter: its ore, its hazards' wards, then on: the next world of the system you haven't
## made landfall on (and the key to its barrier, if it has one); with every one of them seen, the Starsail
## and its cells, and on to another star system
func _world_chapter(ch: int) -> Array:
	var pl: Dictionary = Defs.make_planet(ch)
	var nm := String(pl["name"])
	var out := []
	var ko: int = Defs.kind_ore(pl)
	if ko >= 0:
		out.append({"id": "ore", "title": "Find %s" % Defs.NAMES[ko], "need": [["found", ko]], "reward": {"coins": 20},
			"say": "%s has an ore of its own: %s. Nowhere else has it. The villagers will know where it lies." % [nm, Defs.NAMES[ko]],
			"how": "Every kind of planet hides an ore of its own; its first piece of gear shows in the forge, locked, with where it's found. Villagers' rumours tell too."})
	var clim: Dictionary = Defs.climate(pl)
	if float(clim.get("heat", 0.0)) > 0.0:
		out.append({"id": "heat", "title": "Forge the Heat Ward", "need": [["heat"]], "reward": {"potion": 1},
			"say": "The air of %s would cook you. Forge the Heat Ward: ember, frost and obsidian." % nm,
			"how": "The Heat Ward (C, Staff & Body) lets you breathe the scorching air of a volcanic world; the Cinderheart, Kragmor's relic, does too."})
	for hz in Defs.HAZARDS:
		if float(clim.get(hz, 0.0)) > 0.0:
			var hd: Dictionary = Defs.HAZARDS[hz]
			var wn := _recipe_name(String(hd["ward"]))
			out.append({"id": "ward_" + String(hz), "title": "Forge the %s" % wn, "need": [["item", String(hd["ward"])], ["item", String(hd["relic"])]], "reward": {"potion": 1},
				"say": "%s of %s will wear you down. The %s bears it; a village keeper sells it, or forge it." % [String(hd["name"]), nm, wn],
				"how": "%s: the %s (Wards, at the Wisp Forge, or bought from a keeper here) bears it, and so does the relic of the guardian who knows it." % [String(hd["name"]), wn]})
	# (its heart: each kind of world's core is its own, for the Core Arts; user, 24 Nov)
	var kc: int = Defs.kind_core(pl)
	if kc != Defs.CORE:
		var kn: String = Defs.NAMES[kc]
		out.append({"id": "core", "title": "Harvest 10 %s" % kn, "need": [["held", kc, 10]], "reward": {"coins": 30},
			"say": "The heart of %s is its own: %s. Siphon it, and the Core Arts at the Wisp Forge make a spell and a piece of gear from it." % [nm, kn],
			"how": "Dig to the middle of %s with the Core Siphon: its heart gives %s. The Wisp Forge's Core Arts turn it into a spell and a piece of gear found nowhere else; rarer worlds have rarer cores." % [nm, kn]})
	var sys := Defs.system_of(ch)
	var tg := next_target(sys, ch)
	if tg >= 0:
		var tn := String(Defs.make_planet(tg)["name"])
		var bar := Defs.barrier_of(tg)
		if bar != "" and not game.barrier_ok(tg):
			var bd: Dictionary = Defs.BARRIERS[bar]
			var key := String(bd["key"])
			out.append({"id": "key_" + key, "title": "Forge the %s" % String(bd["key_name"]), "need": [["item", key], ["landed", tg]], "reward": {"coins": 40},
				"say": "%s %s. Forge the %s and the skiff passes every %s, round any world." % [tn, String(bd["tell"]), String(bd["key_name"]), String(bd["name"])],
				"how": "At the Wisp Forge, Travel: the %s. %s" % [String(bd["key_name"]), _recipe_desc(key)]})
		out.append({"id": "voyage_%d" % tg, "title": "Fly to %s" % tn, "need": [["landed", tg]], "reward": {"coins": 60},
			"say": "On to %s. The minimap shows the way." % tn,
			"how": "Fly up out of the sky and head for %s; once it's clearly nearer than where you came from, the journey begins." % tn})
	else:
		out.append_array([
			{"id": "sail", "title": "Forge the Starsail", "need": [["item", "sail"], ["landed_sys", sys]], "reward": {"coins": 40},
				"say": "Every world of this system has seen us. The stars are far apart: forge the Starsail to cross between them.",
				"how": "At the Wisp Forge, Travel: the Starsail (star iron, wisp ingots, crystal and planks). Hold Shift in the skiff out in open space and it runs up to eight times as fast."},
			{"id": "sailcells", "title": "Carry 15 Wisp Cells for the Starsail", "need": [["held", Defs.WISPCELL, 15], ["landed_sys", sys]],
				"say": "The Starsail burns a Wisp Cell every few seconds under sail: carry plenty. A Smelter makes them, outposts sell them.",
				"how": "A Smelter makes 2 Wisp Cells from 2 wisp ore and a coal; outposts sell 10 for 28 coins. Crossing to the next star system burns about a dozen."},
			{"id": "stars", "title": "Reach another star system", "need": [["landed_sys", sys]], "reward": {"coins": 80},
				"say": "Out between the stars, then. The galaxy chart (M, then Tab) shows the systems you've charted.",
				"how": "Fly out into open space, hold Shift to sail, and steer for another system's star; set a waypoint on the galaxy chart (M, Tab). Its worlds are made as you come near one."},
		])
	return out

## the first planet of the round (system 0) with no barrier round it but home: the first voyage's world
func open_target(sys: int) -> int:
	for i in Defs.planets_of(sys):
		if not Defs.is_exotic(int(i)) and int(i) != sys * Defs.SYSTEM.size() and Defs.barrier_of(int(i)) == "":
			return int(i)
	return -1

## the next world of system sys you haven't made landfall on: one you can reach first, else the first in the
## round (its barrier's key the next thing to forge); -1 once you've been to them all
func next_target(sys: int, here := -1) -> int:
	var first := -1
	for i in Defs.planets_of(sys):
		var pi := int(i)
		if Defs.is_exotic(pi) or pi == here or game.landed_on(pi):
			continue
		if game.barrier_ok(pi):
			return pi
		if first < 0:
			first = pi
	return first

func _recipe_desc(id: String) -> String:
	for r in game.recipes:
		if String(r["id"]) == id:
			return String(r["desc"])
	return ""

func _recipe_name(id: String) -> String:
	for r in game.recipes:
		if String(r["id"]) == id:
			return String(r["name"])
	return id.capitalize()

# ----------------------------------------------------------- mysteries ---
## The deep ocean world of the system you're in (its exotic), or -1
func mystery_world() -> int:
	var here := int(game.planet.get("index", 0))
	if Defs.is_exotic(here):
		return here
	var sys := Defs.system_of(int(game.space.home) if game.space.active else here)
	# (the first of the system's exotics whose prize you haven't claimed: the deep ocean world first)
	var any := -1
	for i in Defs.exotics_of(sys):
		if any < 0:
			any = int(i)
		if not bool(((game.items.get("myst", {}) as Dictionary).get(str(int(i)), {}) as Dictionary).get("claimed", false)):
			return int(i)
	return any

## its steps: [{title, how, done}]
func mystery_steps() -> Array:
	var wi := mystery_world()
	if wi < 0:
		return []
	var nm := String(Defs.make_planet(wi)["name"])
	var md: Dictionary = (game.items.get("myst", {}) as Dictionary).get(str(wi), {})
	if Defs.exotic_kind(wi) == "giant":
		var been2 := not md.is_empty() or int(game.planet.get("index", 0)) == wi
		var lit := int(md.get("lit", 0))
		return [
			{"title": "Forge the Storm Lattice", "done": game.items.has("lattice") or been2,
				"how": "A Thunderhead of endless lightning wraps %s. Void essence (from the creatures between the stars, or a monolith's cache), star iron and copper ingots make a Storm Lattice at the Wisp Forge that grounds it." % nm},
			{"title": "Fly to %s" % nm, "done": been2,
				"how": "Through the Thunderhead and down onto its landing isle. There's no ground: isles of rock float over a sea of cloud, and under the clouds the air crushes you (the Depth Seal bears it). Levitation and the skiff get you between the isles."},
			{"title": "Find the Eye of the Storm", "done": bool(md.get("read", false)) or bool(md.get("solved", false)),
				"how": "A domed hall on the highest isle, on the far side from where you land. The inscription over its door says what it wants (F to read it)."},
			{"title": "Light the five beacons as one (%d/5)" % lit, "done": bool(md.get("solved", false)),
				"how": "Five beacons stand on the isles round the Eye, one under it. F lights one for 15 mana, and it burns for 75 seconds: all five must burn at once."},
			{"title": "Claim what the Eye keeps", "done": bool(md.get("claimed", false)),
				"how": "The ward is broken: F at the altar in the Eye's vault."},
		]
	var notes: Array = md.get("notes", [-1, -1, -1, -1, -1])
	var nk := 0
	for nv in notes:
		if int(nv) >= 0:
			nk += 1
	var solved := bool(md.get("solved", false))
	var claimed := bool(md.get("claimed", false))
	var been := not md.is_empty() or int(game.planet.get("index", 0)) == wi
	return [
		{"title": "Forge the Tempest Keel", "done": game.items.has("keel") or been,
			"how": "A maelstrom spins round %s and hurls ships back out. Abyss pearls lie in an ocean world's seabed; with star iron and hull plating (salvage from wrecks) the Wisp Forge makes a Tempest Keel that rides it out." % nm},
		{"title": "Fly to %s" % nm, "done": been,
			"how": "Through the maelstrom (on the minimap) and down onto one of its islands. Its sea is hundreds of cells deep: below 160 the abyss crushes you without the Depth Seal (Wards, from abyss pearls), and it's dark: bring light."},
		{"title": "Read the tide-stones (%d/5)" % nk, "done": nk >= 5 or solved,
			"how": "Standing stones on the islands and the shallow shelves, each carved with a glyph and with dots for its place in a song of five notes. F beside one reads it."},
		{"title": "Sing the Drowned Choir's song", "done": solved,
			"how": "The Temple of the Drowned Choir stands on the deepest floor of the abyss. Its hall is dry: swim into the tunnel in its plinth and come up through the moon pool. F rings a pillar; ring them in the song's order (a wrong note starts it again)."},
		{"title": "Claim what the Choir sealed away", "done": claimed,
			"how": "The ward is broken: F at the altar in the vault."},
	]

## the notes of the song you know, in order ("?" for one you don't)
func mystery_notes() -> String:
	var wi := mystery_world()
	if wi < 0:
		return ""
	var md: Dictionary = (game.items.get("myst", {}) as Dictionary).get(str(wi), {})
	if Defs.exotic_kind(wi) == "giant":
		return "beacons burning: %d of 5" % int(md.get("lit", 0)) if not bool(md.get("solved", false)) else "the Eye is open"
	var notes: Array = md.get("notes", [-1, -1, -1, -1, -1])
	var out := []
	for nv in notes:
		out.append("?" if int(nv) < 0 else String(MysteryArt.GLYPHS[int(nv)]))
	return " · ".join(out)

## the wisp's word as you first come near a maelstrom, and as you first land on a deep ocean world
func _mystery_tick(here: int) -> void:
	var it: Dictionary = game.items
	if Defs.is_exotic(here) and not game.space.active and not it.has("myst_landed_%d" % here):
		it["myst_landed_%d" % here] = true
		if Defs.exotic_kind(here) == "giant":
			say("No ground here, only isles adrift over the clouds, and the air below crushes. On the far side something watches from the highest isle: the Eye of the Storm. L shows what we know.")
		else:
			say("This world sings under its waters. Five tide-stones on its islands and shelves hold a song; on the deepest floor a temple waits to hear it. L shows what we know.")
		return
	if game.space.active and not it.has("myst_heard_giant") and not it.has("lattice"):
		for b2 in game.space.bodies:
			if String(b2.get("exotic", "")) == "giant" and (game.player.pos - (b2["pos"] as Vector2)).length() < float(b2["space"]) + 7000.0:
				it["myst_heard_giant"] = true
				say("A gas giant, %s, wrapped in a Thunderhead: lightning without end. A Storm Lattice would ground it. Something old burns up there." % String(b2["name"]))
				return
	if game.space.active and not it.has("myst_heard") and not it.has("keel"):
		for b in game.space.bodies:
			if String(b.get("exotic", "")) == "abyss" and (game.player.pos - (b["pos"] as Vector2)).length() < float(b["space"]) + 7000.0:
				it["myst_heard"] = true
				say("That storm spins round a deep ocean world, %s. Something old sleeps on its sea floor. A Tempest Keel would ride the maelstrom out." % String(b["name"]))
				return

