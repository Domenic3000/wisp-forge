extends RefCounted
## The dungeon wardens: each dungeon's boss, waiting in the hall before its sealed reliquary.
## Nothing is drawn by hand: a warden is grown from the dungeon's own seed out of the same body
## plans (scripts/boss_art.gd) and moves (scripts/boss_ai.gd) as the biome guardians, in a crypt's
## colours (bone, shade, rot or ember) with an accent from the biome above, and named from parts.
## `make` returns a guardian-style definition (see Defs.BOSSES), with "warden": true. Beaten, it
## breaks the ward on the reliquary's door (main.gd `_warden_falls`).

const FIRST := ["Grave", "Gloom", "Crypt", "Bone", "Rot", "Hollow", "Dread", "Murk", "Pale", "Dusk", "Ash", "Mourn"]
const SECOND := {
	"beast": ["maw", "fang", "hound", "stalker", "jaw"],
	"serpent": ["coil", "wyrm", "spine", "tongue"],
	"toad": ["belly", "croak", "gullet", "toad"],
	"fungus": ["bloom", "cap", "spore", "rot"],
	"bird": ["wing", "talon", "raven", "beak"],
}
## crypt colours: base, belly, dark, eye, skin
const PALETTES := [
	["#cfc6ae", "#ece4cc", "#4a4236", "#7affd0", "scales"],     # bone
	["#3e3a52", "#77708e", "#18161f", "#d4a0ff", "fur"],        # shade
	["#5d6a48", "#a3a878", "#232a1a", "#ffd23a", "moss"],       # rot
	["#5a2a20", "#a0583a", "#1e0c08", "#ffb03a", "scales"],     # ember
]
## the biome above: its accent colour and what the warden spits
const BIOME := {
	"forest": ["#6ac84a", "venom"], "jungle": ["#3ad86a", "venom"], "marsh": ["#9a7a3a", "mudball"],
	"tundra": ["#8fe8ff", "ice"], "mountain": ["#c8b89a", "rock"], "savanna": ["#e8b03a", "sandball"],
	"desert": ["#f0c060", "sandball"], "grove": ["#c07aff", "spore"], "ashland": ["#ff7a2a", "efire"],
	"ocean": ["#3ac8e8", "surge"],
}

static func make(seed: int, biome: String, dungeon: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var plans := ["beast", "beast", "serpent", "toad", "fungus", "bird"]
	var plan: String = plans[rng.randi_range(0, plans.size() - 1)]
	var pal: Array = PALETTES[rng.randi_range(0, PALETTES.size() - 1)]
	if biome == "ashland" and rng.randf() < 0.6:
		pal = PALETTES[3]
	var bio: Array = BIOME.get(biome, ["#b0a0ff", "venom"])
	var accent: String = bio[0]
	var proj: String = bio[1]
	var name: String = FIRST[rng.randi_range(0, FIRST.size() - 1)] + SECOND[plan][rng.randi_range(0, SECOND[plan].size() - 1)]
	var body := {"plan": plan, "base": pal[0], "belly": pal[1], "accent": accent, "dark": pal[2], "eye": pal[3], "skin": pal[4]}
	var minions := {"type": "skeleton", "n": 2, "max": 3}
	var d := {"name": name, "title": "Warden of the " + dungeon, "col": Color(accent).lightened(0.15), "warden": true,
		"hp": 380.0 + float(rng.randi_range(0, 4)) * 10.0, "dmg": 11.0,
		"loot": {Defs.CRYSTAL: 6, Defs.COPPER: 14, Defs.COAL: 10}}
	match plan:
		"beast":
			body.merge({"len": 30, "tall": 13, "leg": 12, "head": 9, "neck": 4, "spikes": rng.randi_range(3, 6),
				"tail": ["long", "short", "tuft"][rng.randi_range(0, 2)], "ears": rng.randf() < 0.5, "horns": rng.randf() < 0.4})
			d.merge({"w": 24.0, "h": 22.0, "go": "walk", "speed": 1.1,
				"moves": {"charge": {"v": 3.8}, "slam": {}, "summon": minions}, "rage": {"roar": {}}})
		"serpent":
			body.merge({"segs": rng.randi_range(9, 11), "rad": 5.0, "teeth": rng.randf() < 0.6})
			d.merge({"w": 11.0, "h": 10.0, "go": "slither", "speed": 2.0, "fly": true,
				"moves": {"spit": {"proj": proj, "n": 3, "spread": 0.2}, "dive": {}, "summon": minions},
				"rage": {"spit2": {"proj": proj, "n": 5, "spread": 0.18}}})
		"toad":
			body.merge({"len": 28, "tall": 18})
			d.merge({"w": 24.0, "h": 18.0, "go": "hop", "speed": 0.9,
				"moves": {"slam": {}, "spit": {"proj": proj, "n": 3, "spread": 0.2}, "summon": minions},
				"rage": {"summon2": {"type": "skeleton", "n": 3, "max": 4}}})
		"fungus":
			body.merge({"len": 22, "tall": 26})
			body["skin"] = "spots"
			d.merge({"w": 19.0, "h": 25.0, "go": "walk", "speed": 0.7,
				"moves": {"cloud": {"r": 16.0, "t": 240}, "spit": {"proj": "spore", "n": 3, "spread": 0.4}, "summon": minions},
				"rage": {"cloud2": {"r": 20.0, "t": 260}}})
		"bird":
			body.merge({"len": 22, "span": 30})
			body["skin"] = "fur"
			d.merge({"w": 19.0, "h": 15.0, "go": "fly", "speed": 2.2, "fly": true,
				"moves": {"dive": {}, "rain": {"proj": "rock", "n": 4}, "summon": {"type": "bat", "n": 2, "max": 4}},
				"rage": {"dive2": {}}})
	d["body"] = body
	return d
