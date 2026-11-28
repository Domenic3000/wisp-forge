## The story (28 Nov; user: "I would like maybe some kind of story and build up with a big bad to drive the player
## through the game. a reason to go forward ... maybe there is something consuming the universe ... that you find hints
## and some feeling for the characters"; then chose the darkness for the big bad, and to keep the twist).
##
## THE HUSH: a living dark at the heart of the galaxy that eats the light of stars and the songs of worlds. Where it
## has been, stars go quiet. Long ago the CHOIR, mages who sang worlds whole (the Worldsong that mends the land is
## their magic, still faintly running), bound a SEAL into the heart of every world to hold it back; each world's
## keepers guarded its seal, and VULKHAR, a forge-golem the Choir made, kept Verdance's. The keepers died holding the
## door; their tombs are the crypts. The WISP is the last spark of the Choir, its memory broken. (The twist, for
## later: the wisp once answered the Hush's voice and helped open a seal.) The Hush is seen in the night sky, larger
## with each chapter (`hush_level`, render.comp's skyColor, P.p[124].z).
##
## What plays when (cutscene.gd; only in a journey begun from now on gets the opening; the rest come as they happen):
## the opening on a new journey; a verse of the wisp's memory each time a crypt's warden (a fallen keeper) falls;
## Vulkhar's words as he wakes and as he falls. Kept in items["story"] {opening, verses, vulkhar_met, vulkhar_fell}.
extends RefCounted

var game
var enabled := true           # (off in the test mode, but in its own check)

func _init(g) -> void:
	game = g

func _st() -> Dictionary:
	var s = game.items.get("story", null)
	if not (s is Dictionary):
		s = {}
		game.items["story"] = s
	return s

func seen(what: String) -> bool:
	return bool(_st().get(what, false))

## how much of the night sky the Hush has taken: a little on the first world, more with each chapter
func hush_level() -> float:
	var ch: int = maxi(0, int(game.quest.chapter)) if game.quest != null else 0
	return clampf(0.3 + 0.1 * float(ch), 0.0, 0.9)

# ---------------------------------------------------------------- the opening ---
const OPENING := [
	{"panel": "hush", "text": "Far out across the sky, the stars are going out, one by one. The old songs had a name for the dark that takes them: the Hush."},
	{"panel": "fall", "text": "On the night the last star over Verdance's north went dark, a light fell out of the sky."},
	{"panel": "camp", "text": "It came down beside a young mage's fire: a wisp, a spark of something very old, flickering and afraid."},
	{"panel": "wisp", "text": "\"The stars are going quiet. I don't remember why... or what I was. But I remember this: it must not reach this world. I need your hands.\""},
]

## a new journey's opening, then `after` (the first hints)
func opening(after = null) -> void:
	if not enabled or seen("opening"):
		if after != null:
			(after as Callable).call()
		return
	_st()["opening"] = true
	game.cutscene.play("opening", OPENING, after)

# --------------------------------------------------- the keepers' tombs (crypts) ---
## a verse of the wisp's memory for each keeper's tomb, the first world's four in order, then one for any after
const VERSES := [
	["This keeper... I knew her. Isel. She kept the seal under these hills and sang to it every night, so it would never sleep.",
		"There were many of us, once. A Choir. We sang worlds whole. I think... I was one of the voices."],
	["Another keeper. Toman, who laughed too loudly at his own jokes. The dark got into his sleep first. We told him they were only dreams.",
		"The Choir bound a seal into the heart of every world, to hold the Hush where it lay. The keepers watched over them."],
	["I remember the last night. The keepers holding the seal, going quiet one by one... and a voice in the dark, so gentle, asking to be let in.",
		"Someone answered it. I can't see who."],
	["Four keepers, four tombs. They died holding the door shut.",
		"Vulkhar still holds it, at the world's heart. The Choir made him to keep the seal. But the Hush has had a thousand years to whisper to him through the stone."],
]
const VERSE_AFTER := [
	["Another keeper's tomb. Their seal still holds... barely. I can feel it straining, like a held breath.",
		"Every world we save is one the Hush can't eat. Keep going."],
]

func warden_fell(at: Vector2) -> void:
	if not enabled:
		return
	var n: int = int(_st().get("verses", 0))
	_st()["verses"] = n + 1
	var lines: Array = VERSES[n] if n < VERSES.size() else VERSE_AFTER[0]
	var list := [{"wait": 40, "cam": at}]
	for ln in lines:
		list.append({"say": "wisp", "text": ln})
	game.cutscene.play("verse%d" % (n + 1), list)

# ------------------------------------------------------------------- Vulkhar ---
func vulkhar_wakes(e) -> void:
	if not enabled or seen("vulkhar_met"):
		return
	_st()["vulkhar_met"] = true
	var vp: Vector2 = e.pos
	var lift: float = float(e.h) * 0.5 - 4.0
	game.cutscene.play("vulkhar", [
		{"wait": 50, "cam": vp},
		{"say": "vulkhar", "at": vp, "lift": lift, "style": "ember", "pitch": 0.55, "text": "LITTLE SPARK. YOU CAME BACK."},
		{"say": "wisp", "text": "Vulkhar? You... know me?"},
		{"say": "vulkhar", "at": vp, "lift": lift, "style": "ember", "pitch": 0.55, "text": "A THOUSAND YEARS I HAVE KEPT THE DOOR. AND STILL IT SINGS TO ME THROUGH THE STONE. SO GENTLE. SO TIRED."},
		{"say": "vulkhar", "at": vp, "lift": lift, "style": "ember", "pitch": 0.55, "text": "GO. OR BE UNMADE WITH THE REST."},
	])

func vulkhar_falls(e) -> void:
	if not enabled or seen("vulkhar_fell"):
		return
	_st()["vulkhar_fell"] = true
	var vp: Vector2 = e.pos
	var lift: float = float(e.h) * 0.5 - 4.0
	game.cutscene.play("vulkhar_falls", [
		{"wait": 40, "cam": vp},
		{"say": "vulkhar", "at": vp, "lift": lift, "style": "ember", "pitch": 0.5, "text": "IT IS QUIET... FOR THE FIRST TIME IN SO LONG... QUIET."},
		{"say": "vulkhar", "at": vp, "lift": lift, "style": "ember", "pitch": 0.5, "text": "SPARK. THEY WILL COME TO OPEN THE WAY. AS BEFORE. YOU REMEMBER... YOU WERE THERE."},
		{"say": "wisp", "text": "I... don't understand. I was there?"},
		{"say": "wisp", "text": "The heart of this world is open now. We have to carry its seal out with us, before the Hush finds it. Then we follow the dark, star by star, to where it began."},
	])
