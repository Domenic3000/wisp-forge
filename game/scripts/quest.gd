## The main quest (user, 23 Nov: "Maybe we just add a main quest system to guide the player through the main
## progressions?"; chose: the wisp companion speaks it, a line on the HUD and a journal (L), and special rewards:
## the wisp's own powers, found nowhere else).
##
## A chapter is a list of steps, each with what to do (`title`, the HUD's line), what the wisp says when it
## comes up (`say`), how to do it (`how`, the journal), and when it's done (`need`: any of its conditions holds,
## so a step already done by another way ticks at once). Chapter 0 is the first planet (about 16 steps, from
## digging in to the first voyage); each later planet you land on gets a chapter of its own (its ore, its
## hazard's ward, its core, its Drive, the cells, the voyage on). Progress is `items["quest"]` {"ch", "at"};
## the powers are `items["wisp_lantern"]`, `["wisp_sense"]`, `["wisp_ward"]`, `["wisp_hands"]` (main reads them).
## A journey from before the quest catches up silently the first time, with the powers it has earned.
extends RefCounted

const Vfx := preload("res://scripts/vfx.gd")
const MysteryArt := preload("res://scripts/mystery.gd")

const SAY_TICKS := 60 * 8
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
	var ch := int(q.get("ch", 0))
	# (a world further on than the chapter: its own chapter begins)
	var here := int(game.planet.get("index", 0))
	_mystery_tick(here)
	if Defs.is_exotic(here):
		here = ch                    # (an exotic world has no chapter of its own: its mystery is its quest)
	if here > ch:
		ch = here
		q = {"ch": ch, "at": 0}
	if ch != chapter:
		chapter = ch
		steps = chapter_steps(ch)
		at = int(q.get("at", 0))
		if not first:
			_announce()
	var moved := false
	while at < steps.size() and _met(steps[at]):
		_complete(steps[at], first)
		at += 1
		moved = true
	game.items["quest"] = {"ch": chapter, "at": at}
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

func _complete(st: Dictionary, quiet: bool) -> void:
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
		"found": return game.ore_found(int(c[1]))
		"spell": return game.known.has(String(c[1]))
		"tier": return int(game.tier) >= int(c[1])
		"item": return game.items.has(String(c[1]))
		"reach": return game.skiff_reach() >= int(c[1])
		"landed":
			var li := int(game.planet.get("index", 0))
			return not Defs.is_exotic(li) and li >= int(c[1])
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
	var nxt := String(Defs.make_planet(1)["name"])
	return [
		{"id": "dig", "title": "Dig in: gather some stone", "need": [["held", Defs.STONE, 15], ["tier", 2]],
			"say": "Let's begin: hold right-click on the ground to dig, and gather some stone.",
			"how": "Hold the right mouse button on the ground to dig. What you dig goes into your satchel (I). Digging costs a little mana, harder rock more."},
		{"id": "spark", "title": "Forge Spark Bolt at the Wisp Forge", "need": [["spell", "spark"]], "reward": {"potion": 1},
			"say": "Open the Wisp Forge (C) and forge Spark Bolt: stone, coal and a little copper ore. Copper glints orange in the rock.",
			"how": "C opens the Wisp Forge. Spark Bolt is under Spells: stone, coal and a little copper ore. Coal is black, copper ore orange, both near the surface."},
		{"id": "kiln", "title": "Set down a Kiln", "need": [["station", "kiln"], ["tier", 2]], "reward": {"coins": 10},
			"say": "Workshops refine what you gather. Build a Kiln: build mode (B), the Workshops tab. It fires sand into glass.",
			"how": "Press B for build mode, Q or E to the Workshops tab, and click to set a Kiln down on level ground. F beside it opens it: load sand, feed its fire with coal or wood."},
		{"id": "smelt", "title": "Smelt copper ingots", "need": [["held", Defs.COPPERBAR, 1], ["tier", 2]], "reward": {"coins": 10},
			"say": "Now a Smelter: stone, copper ore and twelve bricks (fire mud in the kiln). Load it with copper ore, feed its fire, and it makes Copper Ingots.",
			"how": "The Smelter (B, Workshops) costs 30 stone, 12 bricks and 4 copper ore; the Kiln fires 3 mud into 4 bricks. Keep it off plank floors: its sparks catch. F beside it: click copper ore in your satchel to load it, click coal, wood or planks to feed the fire. It warms up, then works batch after batch; take the ingots out when they're made."},
		{"id": "copper", "title": "Forge the Copper Focus", "need": [["tier", 2]], "power": "lantern",
			"say": "Six copper ingots and some stone make the Copper Focus: harder rock, and faster digging.",
			"how": "At the Wisp Forge (C), Staff & Body: the Copper Focus. It digs deepstone, ember, wisp ore and brick, and digs faster."},
		{"id": "levitate", "title": "Forge Levitation", "need": [["item", "levitate"]], "reward": {"potion": 1},
			"say": "Deeper down, wisp ore glows blue: the Copper Focus cuts it. Three copper ingots, four wisp ore and ten leaves forge Levitation.",
			"how": "Wisp ore lies deep, glowing blue; only the Copper Focus cuts it. Levitation is at the Wisp Forge (C, Staff & Body). Hold jump in the air to float on your mana. Smelt wisp ore too (3 to an ingot): the skiff needs Wisp Ingots."},
		{"id": "skiff_recipe", "title": "Learn the Wisp Skiff's recipe", "need": [["learned", "skiff"], ["item", "skiff"]], "reward": {"coins": 25},
			"say": "A village smith sells the Wisp Skiff's recipe for 90 coins. Find a village: sell them what you gather, or help its folk.",
			"how": "Villages are on the surface; a smithy is one of their shops (F beside the smith). Coins come from chests, from selling ore and goods to the keepers, and from villagers' requests (the gold \"!\"). A recipe scroll in a better chest can teach it too."},
		{"id": "skiff", "title": "Forge the Wisp Skiff", "need": [["item", "skiff"]], "power": "sense",
			"say": "Forty planks, twelve glass from the kiln, four wisp ingots and three copper ingots: the Wisp Skiff. K calls it to you, F boards.",
			"how": "At the Wisp Forge, Travel: the Wisp Skiff. K calls it beside you, F boards or steps out. Steer with the movement keys (W up), or hold cast toward the cursor."},
		{"id": "star", "title": "Mine Star Iron from an asteroid", "need": [["found", Defs.STARIRON]], "reward": {"potion": 1},
			"say": "Fly the skiff up out of the sky. The metallic asteroids above hold Star Iron at their hearts: step out (F) and dig.",
			"how": "Fly straight up out of the atmosphere. Asteroids hang above the planet (a marker points to the nearest). Step out with F, push yourself with the staff's jet (hold cast) and dig the dark metallic rock; Star Iron glints blue-white inside. You need the Copper Focus for it."},
		{"id": "obsidian", "title": "Forge the Obsidian Focus", "need": [["tier", 3]], "reward": {"coins": 20},
			"say": "Deeper still you'll need the Obsidian Focus: obsidian (or ash and sand fired in a kiln), ember crystals and two wisp ingots.",
			"how": "Obsidian forms where lava meets water deep down, or fire ash and sand together in a Kiln. Ember crystals glow red in the deep. Forge the Obsidian Focus (C, Staff & Body): it cuts obsidian and magma rock."},
		{"id": "heat", "title": "Forge the Heat Ward", "need": [["heat"], ["item", "heart"]], "reward": {"potion": 1},
			"say": "The deep mantle's heat would cook you. Forge the Heat Ward: ember crystals, frost and obsidian.",
			"how": "The Heat Ward (C, Staff & Body) lets you bear the mantle's heat near the planet's heart. Frost crystals lie in cold caves, ember crystals glow red in the deep."},
		{"id": "vulkhar", "title": "Defeat Vulkhar at the planet's heart", "need": [["item", "heart"]], "power": "ward",
			"say": "Now down to the heart of the world. Vulkhar the Ember Golem guards it: beat him for the Ember Heart. Bring draughts.",
			"how": "Dig down and down, through magma rock, to the heart of the planet. Vulkhar wakes when you come near. Healing Draughts (H) help; so does fighting him where he can reach you, or he calls the heart's fire up after you."},
		{"id": "siphon", "title": "Forge the Core Siphon", "need": [["tier", 4]], "reward": {"coins": 30},
			"say": "With the Ember Heart, forge the Core Siphon: it cuts the planet's core itself.",
			"how": "At the Wisp Forge, Staff & Body: the Core Siphon (obsidian and wisp ingots, and the Ember Heart). It cuts warded stone and the Planet Core."},
		{"id": "core", "title": "Harvest 30 Planet Core", "need": [["held", Defs.CORE, 30], ["reach", 1]],
			"say": "Harvest the core: thirty pieces of it. It burns bright at the very middle of the world.",
			"how": "The Planet Core is the glowing heart below the magma. Dig it with the Core Siphon: thirty pieces for a Core Drive."},
		{"id": "drive", "title": "Forge a Core Drive", "need": [["reach", 1]], "power": "hands", "reward": {"coins": 30},
			"say": "A Core Drive: thirty core, twelve star iron and ten wisp ore. Fitted to the skiff, it carries you through the storm belt to %s." % nxt,
			"how": "At the Wisp Forge, Travel: the Core Drive. Each one lets the skiff through one more planet's storm belt: the next world in the system, %s." % nxt},
		{"id": "cells", "title": "Carry 3 Wisp Cells for the landfall", "need": [["held", Defs.WISPCELL, 3], ["landed", 1]],
			"say": "Landing on another world burns 3 Wisp Cells. A Smelter makes 2 from 2 wisp ore and a coal.",
			"how": "Load a Smelter with wisp ore and coal (2 and 1 for every 2 cells). Trading outposts sell them too. Ordinary flying and going home cost nothing."},
		{"id": "voyage", "title": "Fly to %s" % nxt, "need": [["landed", 1]], "reward": {"coins": 50},
			"say": "Fly up, and on to %s. The marker shows the way. I'll be with you." % nxt,
			"how": "Fly up out of the sky and head for %s (its marker at the edge of the screen). Once it's clearly nearer than home the journey begins, and you come down into its sky." % nxt},
	]

## a later world's chapter: its ore, its hazard's ward, its core, its Drive, the cells and the voyage on
func _world_chapter(ch: int) -> Array:
	var pl: Dictionary = Defs.make_planet(ch)
	var nm := String(pl["name"])
	var nxt := String(Defs.make_planet(ch + 1)["name"])
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
	var cells := 3 if (ch + 1) / Defs.SYSTEM.size() == ch / Defs.SYSTEM.size() else 6
	out.append_array([
		{"id": "core", "title": "Harvest 30 of %s's core" % nm, "need": [["held", Defs.CORE, 30], ["reach", ch + 1]], "reward": {"coins": 30},
			"say": "Down to the heart of %s, then: thirty pieces of its core." % nm,
			"how": "Dig to the middle of %s with the Core Siphon and harvest thirty Planet Core." % nm},
		{"id": "drive", "title": "Forge %s's Core Drive" % nm, "need": [["reach", ch + 1]], "reward": {"coins": 40},
			"say": "Bind the core in star iron: a Core Drive, and the storm belt round %s opens to us." % nxt,
			"how": "At the Wisp Forge, Travel: the Core Drive (its cost asks for this world's own ore too, if it has one)."},
		{"id": "cells", "title": "Carry %d Wisp Cells for the landfall" % cells, "need": [["held", Defs.WISPCELL, cells], ["landed", ch + 1]],
			"say": "The landfall on %s burns %d Wisp Cells: smelt them, or buy them at an outpost." % [nxt, cells],
			"how": "A Smelter makes 2 Wisp Cells from 2 wisp ore and a coal; outposts sell 10 for 28 coins. Into another star system the landfall burns 6."},
		{"id": "voyage", "title": "Fly to %s" % nxt, "need": [["landed", ch + 1]], "reward": {"coins": 60},
			"say": "On to %s. The marker shows the way." % nxt,
			"how": "Fly up out of the sky and head for %s; once it's clearly nearer than where you came from, the journey begins." % nxt},
	])
	return out

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
			"how": "Through the maelstrom (its marker at the screen's edge) and down onto one of its islands. Its sea is hundreds of cells deep: below 160 the abyss crushes you without the Depth Seal (Wards, from abyss pearls), and it's dark: bring light."},
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

