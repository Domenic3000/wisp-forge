extends Node
## Sound for Wisp Forge.
##
## Sound effects are synthesised here at startup (little waveforms built from noise, sweeps, bells, FM
## and resonators), so the game has sound without any audio files. play(name, world_pos) plays one:
## quieter the further it is from the camera, with a touch of random pitch so repeats don't sound
## mechanical, and never more often than its cooldown allows. Footsteps go through `step(pos)`, which
## hears what's underfoot (grass, stone, sand, snow, wood, metal).
##
## Ambience (26 Nov; user: "can we do an audio pass"): looping beds synthesised on a worker thread at
## startup (wind, rain, crickets at night, the sea, caves, the deep's lava, under water, space, a station's
## hum, an outpost's murmur, the pocket's chimes, a workshop's fire), each faded in and out by where you are.
## Three audio buses (made here): sound effects with a reverb that follows the place (dry under the open sky,
## ringing in caves and halls, dreamy in the pocket), ambience, and music; under water all three are muffled.
##
## Music is optional: any .mp3 or .ogg files in game/audio/music/ are loaded at runtime (no import step).
## A track's name decides when it plays: a mood ("surface_day", "surface_night", "underground", "deep",
## "boss", "space", "title", "village", "pocket", "outpost", "derelict"; anything starting with that word
## counts, so "surface_day_2.mp3" joins the day tracks). A track for one kind of planet starts with the kind
## ("volcanic_surface_day.mp3"), and one for a biome with "biome_" and the biome ("biome_desert_surface_day.mp3",
## "biome_forest_underground.mp3"). The most particular track there is plays: the biome's, then the planet
## kind's, then the common one, then the mood's fallbacks. Tracks crossfade when the situation changes.

var game
const RATE := 22050
var sfx := {}                 # name -> AudioStreamWAV
var _cool := {}               # name -> frames until it may play again
var _players := []
var _next := 0
var sfx_volume := 0.8         # 0..1, from settings
var music_volume := 0.6

var tracks := {}              # mood, "kind:mood" or "biome:<biome>:mood" -> Array of streams
const MOODS := ["surface_day", "surface_night", "underground", "deep", "boss", "space", "title", "village", "pocket", "outpost", "derelict"]
const KINDS := ["temperate", "volcanic", "ocean", "desert", "marsh", "frozen", "wild", "realm", "abyss", "giant", "star", "void"]
## when a mood has no track of its own (nor its kind's or biome's), the next one along is tried
const FALLBACK := {"surface_night": "surface_day", "deep": "underground", "boss": "underground", "title": "surface_day",
	"underground": "surface_night", "space": "surface_night", "village": "surface_day", "pocket": "surface_night",
	"outpost": "space", "derelict": "deep"}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_on_a := true
var _mood := ""
var _list := ""               # the track list now playing from (biome, kind or common)
var _fade := 1.0

const COOLDOWN := {"dig": 6, "step": 9, "spark": 4, "hit": 5, "coin": 3, "creak": 50, "rumble": 25, "land": 8,
	"place": 5, "levitate": 14, "splash": 10, "ui_hover": 3, "swing": 8, "bow": 6, "screech": 12, "crack": 6, "thud": 6, "zap": 8, "croak": 18, "chirp": 10, "song": 90, "glyph": 6, "talk": 3, "talk_wisp": 3, "page": 10,
	"fizzle": 8, "thunder": 40, "hurt": 10, "foe_die": 4, "dock": 30, "cannon": 5, "shield": 12,
	"step_soft": 9, "step_stone": 9, "step_sand": 9, "step_snow": 9, "step_wood": 9, "step_metal": 9}

## (26 Nov, user on another PC: "crackling in the audio engine... occasional snaps"): a free player is taken
## before one still sounding is cut off, and there are more of them
const VOICES := 16
const BUS_SFX := "WF Sound"
const BUS_AMB := "WF Ambience"
const BUS_MUSIC := "WF Music"

func _ready() -> void:
	_make_buses()
	for k in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		add_child(p)
		_players.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_music_a.bus = BUS_MUSIC
	_music_b.bus = BUS_MUSIC
	add_child(_music_a)
	add_child(_music_b)
	_music_a.volume_db = -80.0
	_music_b.volume_db = -80.0
	_build_sfx()
	_step_table()
	_load_music()
	_amb_task = WorkerThreadPool.add_task(_build_ambience)

# ------------------------------------------------------------------ playing ---
func play(sname: String, wpos = null, vol := 1.0, pitch := 1.0) -> void:
	if not sfx.has(sname) or sfx_volume <= 0.001:
		return
	if int(_cool.get(sname, 0)) > 0:
		return
	_cool[sname] = int(COOLDOWN.get(sname, 2))
	var v := vol * sfx_volume
	if wpos != null and game != null:
		# fade with distance from the middle of the screen (in world cells)
		var d: float = (wpos as Vector2).distance_to(game.cam_c)
		v *= clampf(1.0 - (d - 60.0) / 220.0, 0.0, 1.0)
	if v <= 0.01:
		return
	# a free player if there is one; else the one started longest ago (cutting a sound off mid-way snaps)
	var p: AudioStreamPlayer = null
	for k in _players.size():
		var q: AudioStreamPlayer = _players[(_next + k) % _players.size()]
		if not q.playing:
			p = q
			_next = (_next + k + 1) % _players.size()
			break
	if p == null:
		p = _players[_next]
		_next = (_next + 1) % _players.size()
	p.stream = sfx[sname]
	p.volume_db = linear_to_db(v)
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	p.play()

## A footstep at a body's feet (pos its middle, h its height), by what's underfoot: `kind` names it outright
## ("metal" in a station's halls, "soft" on the pocket's grass), else the ground under it is looked up.
func step(pos: Vector2, h: float, vol := 0.35, kind := "") -> void:
	var k := kind
	if k == "" and game != null and not game.space.active and not game.pocket.active:
		var a := atan2(pos.y, pos.x)
		var t: int = game.type_at(pos + game.basis_d(a) * (h * 0.5 + 1.5))
		k = String(_step_of[t]) if t >= 0 and t < _step_of.size() else "soft"
	if k == "":
		k = "soft"
	play("step_" + k, pos, vol)

var _step_of := []            # material -> "soft", "stone", "sand", "snow", "wood", "metal"

func _step_table() -> void:
	_step_of.resize(Defs.NAMES.size())
	for i in Defs.NAMES.size():
		var n := String(Defs.NAMES[i]).to_lower()
		var k := "stone"
		for w in ["plank", "wood", "log", "scaffold", "door", "root", "timber", "bark"]:
			if n.contains(w):
				k = "wood"
		for w in ["sand", "ash", "gravel", "dust", "salt"]:
			if n.contains(w):
				k = "sand"
		for w in ["snow", "frost", "rime"]:
			if n.contains(w):
				k = "snow"
		for w in ["grass", "dirt", "mud", "moss", "leaf", "clay", "soil", "peat", "mycel", "turf", "shroom"]:
			if n.contains(w):
				k = "soft"
		for w in ["plating", "iron", "copper", "metal", "hull", "steel", "silver", "gold"]:
			if n.contains(w):
				k = "metal"
		_step_of[i] = k

func _process(_delta: float) -> void:
	if _music_task >= 0:
		_take_music()
	if _amb_task >= 0 and WorkerThreadPool.is_task_completed(_amb_task):
		WorkerThreadPool.wait_for_task_completion(_amb_task)
		_amb_task = -1
		_start_ambience()
	for k in _cool.keys():
		_cool[k] = int(_cool[k]) - 1
	_frame += 1
	if _frame % 6 == 0:
		_place_now()
	_update_buses()
	_update_ambience()
	_update_music()

var _frame := 0

# -------------------------------------------------------------- where you are ---
## What kind of place you're in, worked out a few times a second: "title", "pocket", "outpost", "derelict",
## "space", or on a planet "surface" / "underground" / "deep"; with whether you're under water, under the open
## sky, the biome, how far down, whether a village is round you, and whether the sea is near.
var here := {"place": "title", "under_water": false, "open": true, "biome": "", "depth": 0.0, "village": false, "sea": 0.0, "fire": 0.0}

func _place_now() -> void:
	var h := {"place": "title", "under_water": false, "open": true, "biome": "", "depth": 0.0, "village": false, "sea": 0.0, "fire": 0.0}
	if game == null or game.state == "title" or game.state == "loading" or game.player == null:
		here = h
		return
	var m = game.player
	if game.pocket != null and game.pocket.active:
		h["place"] = "outpost" if String(game.pocket.place) == "outpost" else "pocket"
		here = h
		return
	if game.space != null and game.space.active:
		h["place"] = "derelict" if game.space.inst != null else "space"
		here = h
		return
	var p: Vector2 = m.pos
	var a := atan2(p.y, p.x)
	var rs: float = game.gpu.surf_at(a).x
	var depth := rs - p.length()
	h["depth"] = depth
	h["place"] = "deep" if depth > 220.0 else ("underground" if depth > 40.0 else "surface")
	h["open"] = game.exposed
	var names: Array = game.planet.get("biomes", ["forest"])
	h["biome"] = String(names[clampi(int(game.gpu.surf_at(a).y), 0, names.size() - 1)])
	var head: int = game.type_at(p - game.basis_d(a) * (m.h * 0.3))
	h["under_water"] = head >= 0 and head < Defs.KIND.size() and Defs.KIND[head] == Defs.K_LIQUID
	# a living village round you (its houses' span and a little either side)
	if game.builds != null and depth < 60.0:
		var col := fposmod(a, TAU) / TAU * float(Defs.NS)
		for t in game.builds.towns:
			if not bool(t.get("living", false)):
				continue
			var mid := float(int(t["x0"])) + float(int(t["w"])) * 0.5
			var dc := absf(wrapf(col - mid, -float(Defs.NS) * 0.5, float(Defs.NS) * 0.5))
			if dc < float(int(t["w"])) * 0.5 + 40.0:
				h["village"] = true
				break
	# the sea: open water at the surface within about 200 cells either way (the shore's waves)
	if depth < 80.0:
		var sea := 0.0
		for k in [-3, -2, -1, 0, 1, 2, 3]:
			var ak := a + float(k) * 70.0 / maxf(rs, 1.0)
			var sb: Vector4 = game.gpu.surf_b(ak)
			if sb.y > 0.0 and int(sb.z) == Defs.WATER and game.gpu.surf_at(ak).x < sb.y - 3.0:
				sea = maxf(sea, 1.0 - absf(float(k)) / 4.0)
		var sb0: Vector4 = game.gpu.surf_b(a)
		if sb0.y > 0.0:
			sea *= clampf(1.0 - (p.length() - sb0.y - 40.0) / 200.0, 0.0, 1.0)     # (fades as you climb away)
		h["sea"] = sea
	# a lit workshop's fire nearby
	if game.workshops != null:
		for st in game.workshops.list:
			if st.lit:
				var d: float = (st.pos as Vector2).distance_to(p)
				h["fire"] = maxf(float(h["fire"]), clampf(1.0 - d / 110.0, 0.0, 1.0))
	here = h

# --------------------------------------------------------------------- buses ---
var _rv: AudioEffectReverb
var _lp_sfx: AudioEffectLowPassFilter
var _lp_amb: AudioEffectLowPassFilter
var _lp_music: AudioEffectLowPassFilter
var _rv_now := Vector4(0.3, 0.5, 0.04, 0.0)       # room size, damping, wet, (unused)
var _muffle := 0.0

func _make_buses() -> void:
	for nm in [BUS_SFX, BUS_AMB, BUS_MUSIC]:
		if AudioServer.get_bus_index(nm) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nm)
		AudioServer.set_bus_send(i, "Master")
	# a limiter on the master bus: sounds, ambience and music stacked up never clip the output (clipping is heard
	# as crackling)
	var has_lim := false
	for e in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, e) is AudioEffectHardLimiter:
			has_lim = true
	if not has_lim:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)
	var si := AudioServer.get_bus_index(BUS_SFX)
	_rv = AudioEffectReverb.new()
	_rv.room_size = 0.3
	_rv.damping = 0.5
	_rv.wet = 0.04
	_rv.dry = 1.0
	_rv.spread = 0.6
	_rv.hipass = 0.1
	AudioServer.add_bus_effect(si, _rv)
	_lp_sfx = AudioEffectLowPassFilter.new()
	_lp_sfx.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(si, _lp_sfx)
	_lp_amb = AudioEffectLowPassFilter.new()
	_lp_amb.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_AMB), _lp_amb)
	_lp_music = AudioEffectLowPassFilter.new()
	_lp_music.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_MUSIC), _lp_music)

## the reverb eases toward the place's (room size, damping, wet); under water everything is muffled
func _update_buses() -> void:
	if _rv == null:
		return
	var want := Vector4(0.3, 0.5, 0.04, 0.0)
	match String(here["place"]):
		"surface":
			want = Vector4(0.3, 0.5, 0.04, 0.0) if here["open"] else Vector4(0.42, 0.55, 0.12, 0.0)
		"underground":
			want = Vector4(0.72, 0.45, 0.24, 0.0)
		"deep":
			want = Vector4(0.86, 0.4, 0.32, 0.0)
		"derelict":
			want = Vector4(0.66, 0.25, 0.28, 0.0)          # (bare metal halls: a bright, ringing tail)
		"outpost":
			want = Vector4(0.55, 0.35, 0.16, 0.0)
		"pocket":
			want = Vector4(0.88, 0.7, 0.22, 0.0)           # (soft and far-off, like a dream)
		"space":
			want = Vector4(0.2, 0.8, 0.0, 0.0)
	_rv_now = _rv_now.lerp(want, 0.04)
	_rv.room_size = _rv_now.x
	_rv.damping = _rv_now.y
	_rv.wet = _rv_now.z
	_muffle += ((1.0 if here["under_water"] else 0.0) - _muffle) * 0.08
	var cut := lerpf(20000.0, 650.0, pow(_muffle, 0.5))
	_lp_sfx.cutoff_hz = cut
	_lp_amb.cutoff_hz = cut
	_lp_music.cutoff_hz = lerpf(20000.0, 900.0, pow(_muffle, 0.5))

# -------------------------------------------------------------------- music ---
## Where the music is: game/audio/music, or in an exported game the "music" folder beside the .exe
## (kept out of the game's pack, so its files stay plain and a track can be swapped by hand).
static func music_dir() -> String:
	if OS.has_feature("template"):
		var outside := OS.get_executable_path().get_base_dir().path_join("music")
		if DirAccess.dir_exists_absolute(outside):
			return outside
	return "res://audio/music"

var _music_task := -1
var _music_loaded := {}

## The tracks are read on a worker thread (some 40 MB: read at start-up it held the window blank for a
## moment); `_process` takes them in when they're ready.
func _load_music() -> void:
	var dir := music_dir()
	_music_task = WorkerThreadPool.add_task(_read_music.bind(dir))

func _read_music(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	var got := {}
	for fn in d.get_files():
		var path := dir.path_join(fn)
		var stream: AudioStream = null
		if fn.ends_with(".mp3"):
			var m := AudioStreamMP3.new()
			m.data = FileAccess.get_file_as_bytes(path)
			m.loop = true
			stream = m
		elif fn.ends_with(".ogg"):
			var o := AudioStreamOggVorbis.load_from_file(path if path.is_absolute_path() and not path.begins_with("res://") else ProjectSettings.globalize_path(path))
			if o:
				o.loop = true
				stream = o
		if stream != null:
			got[fn] = stream
	_music_loaded = got

func _take_music() -> void:
	if _music_task < 0 or not WorkerThreadPool.is_task_completed(_music_task):
		return
	WorkerThreadPool.wait_for_task_completion(_music_task)
	_music_task = -1
	var names := _music_loaded.keys()
	names.sort()
	for fn in names:
		var key := track_key(String(fn))
		if key != "":
			if not tracks.has(key):
				tracks[key] = []
			tracks[key].append(_music_loaded[fn])
	_music_loaded = {}
	print("[Wisp Forge] music: %s" % str(tracks.keys()))

## which list a music file joins: "mood", "kind:mood" for a planet kind's own, "biome:<biome>:mood" for a
## biome's own ("" for none)
static func track_key(fn: String) -> String:
	var pre := ""
	var rest := fn
	if fn.begins_with("biome_"):
		var r2 := fn.substr(6)
		for b in Defs.BIOMES:
			if r2.begins_with(String(b) + "_"):
				pre = "biome:" + String(b) + ":"
				rest = r2.substr(String(b).length() + 1)
				break
		if pre == "":
			return ""
	else:
		for k in KINDS:
			if fn.begins_with(k + "_"):
				pre = k + ":"
				rest = fn.substr(k.length() + 1)
				break
	for mood in MOODS:
		if rest.begins_with(mood):
			return pre + mood
	return ""

## what should be playing now
func _want_mood() -> String:
	var pl := String(here["place"])
	match pl:
		"title", "pocket", "outpost", "derelict", "space":
			return pl
	var p: Vector2 = game.player.pos
	for e in game.enemies:
		if e.boss and e.awake and (e.pos as Vector2).distance_to(p) < 260.0:
			return "boss"
	if pl == "deep" or pl == "underground":
		return pl
	if game._local_daylight(p) > 0.3:
		return "village" if here["village"] else "surface_day"
	return "surface_night"

## the track list for the mood: this biome's own first (on the surface and under it), then this planet kind's,
## then the common one, then the fallbacks' in turn ("" if there's no music at all)
func _list_for(mood: String) -> String:
	var kind := _kind()
	var biome := String(here["biome"])
	var m := mood
	for k in 5:
		var keys := []
		if biome != "" and m in ["surface_day", "surface_night", "underground", "deep", "village"]:
			keys.append("biome:%s:%s" % [biome, m])
		if kind != "":
			keys.append(kind + ":" + m)
		keys.append(m)
		for key in keys:
			if tracks.has(key) and not tracks[key].is_empty():
				return key
		m = String(FALLBACK.get(m, ""))
		if m == "":
			break
	return ""

func _kind() -> String:
	if game == null or game.state == "title":
		return ""
	return String(game.planet.get("kind", ""))

func _update_music() -> void:
	if tracks.is_empty():
		return
	var mood := _want_mood()
	var mkey := _kind() + ":" + String(here["biome"]) + ":" + mood
	var cur: AudioStreamPlayer = _music_a if _music_on_a else _music_b
	var old: AudioStreamPlayer = _music_b if _music_on_a else _music_a
	if mkey != _mood:
		_mood = mkey
		var lk := _list_for(mood)
		# (only a different list changes the track: walking into a biome with no music of its own keeps
		# the one that's playing)
		if lk != "" and lk != _list:
			_list = lk
			var arr: Array = tracks[lk]
			var st: AudioStream = arr[randi() % arr.size()]
			if st != cur.stream:
				# swap: the new track fades in while the old one fades out
				_music_on_a = not _music_on_a
				old = cur
				cur = _music_a if _music_on_a else _music_b
				cur.stream = st
				cur.play()
				_fade = 0.0
	_fade = minf(1.0, _fade + 1.0 / 180.0)
	var target := music_volume
	cur.volume_db = linear_to_db(maxf(0.0001, target * _fade))
	old.volume_db = linear_to_db(maxf(0.0001, target * (1.0 - _fade)))
	if _fade >= 1.0 and old.playing:
		old.stop()

# ----------------------------------------------------------------- ambience ---
var _amb_task := -1
var _amb_streams := {}        # name -> AudioStreamWAV (made on the worker thread)
var _amb := {}                # name -> [AudioStreamPlayer, volume now]
const AMB_GAIN := 0.75

## every bed's loudness for where you are now (0 = silent)
func _amb_targets() -> Dictionary:
	var t := {}
	var pl := String(here["place"])
	if game == null:
		return t
	match pl:
		"title":
			t["wind"] = 0.22
		"pocket":
			t["pocket"] = 0.55
		"outpost":
			t["outpost"] = 0.5
		"derelict":
			t["station"] = 0.55
		"space":
			t["space"] = 0.5
		_:
			var depth := float(here["depth"])
			var surf := clampf(1.0 - (depth - 10.0) / 40.0, 0.0, 1.0)            # (fades out going down)
			var open := 1.0 if here["open"] else 0.35
			var wk := ""
			if Defs.BIOMES.has(here["biome"]):
				wk = String(Defs.BIOMES[here["biome"]]["weather"])
			t["wind"] = (0.14 + clampf(absf(game.wind) * 0.55, 0.0, 0.55)) * open * surf
			if wk == "rain" or game.sky_ev == "hail":
				t["rain"] = clampf(game.sky_rain * 1.1, 0.0, 0.8) * (open * 0.6 + 0.4) * surf
			var kind := _kind()
			var warm := wk != "snow" and wk != "ash" and not kind in ["frozen", "volcanic", "giant", "star", "void"]
			if warm and game._local_daylight(game.player.pos) < 0.3:
				t["crickets"] = 0.3 * (1.0 - clampf(game.sky_rain * 1.5, 0.0, 1.0)) * surf
			t["sea"] = 0.5 * float(here["sea"])
			if kind == "star":
				# (a dying star's sea is molten: it roars like the deep's lava, not waves)
				t["deep"] = maxf(float(t.get("deep", 0.0)), 0.45 * float(here["sea"]) + 0.15 * surf)
				t["sea"] = 0.0
			if kind == "void":
				t["wind"] = 0.0          # (no air moves in the Hollow; the far drone of space instead)
				t["space"] = 0.35 * surf
			if pl == "underground":
				t["cave"] = 0.5
			elif pl == "deep":
				t["deep"] = clampf(0.35 + (depth - 220.0) / 600.0, 0.35, 0.65)
				t["cave"] = 0.2
			elif depth > 20.0:
				t["cave"] = 0.5 * clampf((depth - 20.0) / 20.0, 0.0, 1.0)
			t["fire"] = 0.45 * float(here["fire"])
			if here["under_water"]:
				t["water"] = 0.6
				t["wind"] = 0.0
				t["rain"] = float(t.get("rain", 0.0)) * 0.3
	return t

func _start_ambience() -> void:
	for nm in _amb_streams:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_AMB
		p.stream = _amb_streams[nm]
		p.volume_db = -80.0
		add_child(p)
		_amb[nm] = [p, 0.0]

func _update_ambience() -> void:
	if _amb.is_empty():
		return
	var t := _amb_targets()
	for nm in _amb:
		var e: Array = _amb[nm]
		var p: AudioStreamPlayer = e[0]
		var want: float = float(t.get(nm, 0.0)) * sfx_volume * AMB_GAIN
		var v: float = e[1]
		v += (want - v) * (0.02 if want > v else 0.03)
		e[1] = v
		if v < 0.003:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play(randf() * maxf(0.0, p.stream.get_length() - 0.1))
		p.volume_db = linear_to_db(v)

## The beds, made once on a worker thread (with their own random numbers): each is a loop whose end is
## blended into its start, so it never clicks as it comes round.
func _build_ambience() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 7171
	var out := {}
	out["wind"] = _amb_wind(r)
	out["rain"] = _amb_rain(r)
	out["crickets"] = _amb_crickets(r)
	out["sea"] = _amb_sea(r)
	out["cave"] = _amb_cave(r)
	out["deep"] = _amb_deep(r)
	out["water"] = _amb_water(r)
	out["space"] = _amb_space(r)
	out["station"] = _amb_station(r)
	out["outpost"] = _amb_outpost(r)
	out["pocket"] = _amb_pocket(r)
	out["fire"] = _amb_fire(r)
	_amb_streams = out

const LR := 11025             # (the low beds are made at half the rate: half the work, nothing lost)

## a loop of n samples from a buffer of n + f: its last f samples blended into its first f
func _loop(a: PackedFloat32Array, f: int, rate: int) -> AudioStreamWAV:
	var n := a.size() - f
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = a[i]
	for i in f:
		var w := float(i) / float(f)
		b[i] = a[i] * w + a[n + i] * (1.0 - w)
	var st := _wav(b, rate, false)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	return st

## a resonant band-pass (two-pole), one sample at a time: state in s (y1, y2)
static func _reso(x: float, f: float, q: float, rate: float, s: Array) -> float:
	var w := TAU * f / rate
	var rr := 1.0 - w / (2.0 * q)
	var y: float = x * (1.0 - rr) + 2.0 * rr * cos(w) * float(s[0]) - rr * rr * float(s[1])
	s[1] = s[0]
	s[0] = y
	return y

func _amb_wind(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 9.0
	var f := int(1.5 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	var rs := [0.0, 0.0]
	for i in n:
		var t := float(i) / LR
		var gust := 0.55 + 0.3 * sin(t * TAU / 4.5) + 0.15 * sin(t * TAU / 1.7 + 1.0)
		var k := 0.012 + 0.03 * gust
		l1 += (r.randf_range(-1.0, 1.0) - l1) * k
		l2 += (l1 - l2) * k
		var whistle := _reso(r.randf_range(-1.0, 1.0), 380.0 + 160.0 * gust, 18.0, float(LR), rs)
		a[i] = (l2 * 3.2 + whistle * 0.05) * gust
	return _loop(a, f, LR)

func _amb_rain(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 5.0
	var f := int(0.8 * RATE)
	var n := int(sec * RATE) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var lo := 0.0
	var hi := 0.0
	for i in n:
		var x := r.randf_range(-1.0, 1.0)
		lo += (x - lo) * 0.06
		hi += ((x - lo) - hi) * 0.5
		a[i] = hi * 0.22
	# drops pattering: tiny bright ticks
	for d in int(sec * 70.0):
		var s0 := r.randi_range(0, n - 200)
		var fq := r.randf_range(1800.0, 4800.0)
		var g := r.randf_range(0.02, 0.09)
		for j in 160:
			var tt := float(j) / RATE
			a[s0 + j] += sin(tt * fq * TAU) * exp(-tt * 900.0) * g
	return _loop(a, f, RATE)

func _amb_crickets(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 6.0
	var f := int(0.5 * RATE)
	var n := int(sec * RATE) + f
	var a := PackedFloat32Array()
	a.resize(n)
	for c in 4:
		var fq := r.randf_range(3900.0, 5200.0)
		var g := r.randf_range(0.025, 0.05)
		var period := r.randf_range(0.45, 0.8)
		var t0 := r.randf_range(0.0, period)
		while t0 < float(n) / RATE - 0.2:
			for pz in 3:
				var s0 := int((t0 + float(pz) * 0.035) * RATE)
				for j in int(0.018 * RATE):
					if s0 + j < n:
						var tt := float(j) / RATE
						a[s0 + j] += sin(tt * fq * TAU) * sin(PI * tt / 0.018) * g
			t0 += period * r.randf_range(0.85, 1.15)
	return _loop(a, f, RATE)

func _amb_sea(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 10.0
	var f := int(2.0 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		var t := float(i) / LR
		var sw := pow(0.5 + 0.5 * sin(t * TAU / 5.0 - PI * 0.5), 2.0)          # (a wave every five seconds)
		var k := 0.01 + 0.09 * sw
		l1 += (r.randf_range(-1.0, 1.0) - l1) * k
		l2 += (l1 - l2) * 0.3
		a[i] = l2 * (0.25 + 1.6 * sw)
	return _loop(a, f, LR)

func _amb_cave(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 12.0
	var f := int(1.5 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		l1 += (r.randf_range(-1.0, 1.0) - l1) * 0.006
		l2 += (l1 - l2) * 0.02
		a[i] = l2 * 9.0
	# drips, each with a cave's echoes after it
	for d in 7:
		var s0 := r.randi_range(0, n - LR)
		var f0 := r.randf_range(900.0, 1500.0)
		var g := r.randf_range(0.08, 0.16)
		for echo in 4:
			var e0 := s0 + int(float(echo) * 0.21 * LR)
			var eg := g * pow(0.42, echo)
			for j in int(0.09 * LR):
				if e0 + j < n:
					var tt := float(j) / LR
					a[e0 + j] += sin(TAU * (f0 * tt - 2600.0 * tt * tt)) * exp(-tt * 55.0) * eg
	return _loop(a, f, LR)

func _amb_deep(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 10.0
	var f := int(1.5 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		var t := float(i) / LR
		l1 += (r.randf_range(-1.0, 1.0) - l1) * 0.01
		l2 += (l1 - l2) * 0.03
		a[i] = l2 * 10.0 * (0.8 + 0.2 * sin(t * TAU / 2.5))
	# the lava's slow bubbling: low swelling blorps
	for d in 16:
		var s0 := r.randi_range(0, n - LR)
		var f0 := r.randf_range(55.0, 95.0)
		var g := r.randf_range(0.12, 0.25)
		var ln := r.randf_range(0.12, 0.25)
		var ph := 0.0
		for j in int(ln * LR):
			var tt := float(j) / LR
			ph += (f0 * (1.0 + 1.4 * tt / ln)) / LR
			a[s0 + j] += sin(ph * TAU) * sin(PI * tt / ln) * g
	return _loop(a, f, LR)

func _amb_water(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 8.0
	var f := int(1.0 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	for i in n:
		l1 += (r.randf_range(-1.0, 1.0) - l1) * 0.012
		a[i] = l1 * 2.5
	for d in 30:
		var s0 := r.randi_range(0, n - LR / 4)
		var f0 := r.randf_range(260.0, 520.0)
		var g := r.randf_range(0.05, 0.12)
		var ph := 0.0
		for j in int(0.05 * LR):
			var tt := float(j) / LR
			ph += f0 * (1.0 + tt * 30.0) / LR
			a[s0 + j] += sin(ph * TAU) * exp(-tt * 60.0) * g
	return _loop(a, f, LR)

func _amb_space(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 12.0
	var f := int(2.0 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	for i in n:
		var t := float(i) / LR
		l1 += (r.randf_range(-1.0, 1.0) - l1) * 0.004
		var dr := sin(t * 55.0 * TAU) * 0.5 + sin(t * 55.4 * TAU) * 0.5 + sin(t * 82.5 * TAU) * 0.3 * (0.5 + 0.5 * sin(t * TAU / 6.0))
		dr += sin(t * 110.2 * TAU) * 0.12 * (0.5 + 0.5 * sin(t * TAU / 4.0 + 1.0))
		a[i] = dr * 0.16 + l1 * 3.0
	return _loop(a, f, LR)

func _amb_station(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 10.0
	var f := int(1.5 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	for i in n:
		var t := float(i) / LR
		l1 += (r.randf_range(-1.0, 1.0) - l1) * 0.05
		var hum := sin(t * 50.0 * TAU) * 0.5 + sin(t * 100.0 * TAU) * 0.22 + sin(t * 150.0 * TAU) * 0.1
		a[i] = hum * 0.12 + l1 * 0.5
	# a far-off groan of metal, twice a loop
	for d in 2:
		var s0 := r.randi_range(0, n - int(2.0 * LR))
		var rs := [0.0, 0.0]
		var ph := 0.0
		var ln := r.randf_range(1.0, 1.7)
		for j in int(ln * LR):
			var tt := float(j) / LR
			ph += (70.0 + 25.0 * sin(tt * 3.0) + r.randf_range(-6.0, 6.0)) / LR
			var saw := fmod(ph, 1.0) * 2.0 - 1.0
			a[s0 + j] += _reso(saw, 420.0, 6.0, float(LR), rs) * sin(PI * tt / ln) * 0.12
	return _loop(a, f, LR)

func _amb_outpost(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 8.0
	var f := int(1.0 * LR)
	var n := int(sec * LR) + f
	var a := PackedFloat32Array()
	a.resize(n)
	for i in n:
		var t := float(i) / LR
		a[i] = (sin(t * 60.0 * TAU) * 0.5 + sin(t * 120.0 * TAU) * 0.2) * 0.06
	# a crowd's murmur: voices of band-passed noise, each talking in syllables
	for v in 6:
		var rs := [0.0, 0.0]
		var fq := r.randf_range(380.0, 900.0)
		var g := r.randf_range(0.6, 1.1)
		var gate := 0.0
		var talk := r.randf() < 0.5
		var next := 0
		for i in n:
			if i >= next:
				next = i + int(r.randf_range(0.12, 0.3) * LR)
				if r.randf() < 0.05:
					talk = not talk
				gate = r.randf_range(0.3, 1.0) if talk else 0.0
			var x := _reso(r.randf_range(-1.0, 1.0), fq, 4.0, float(LR), rs)
			a[i] += x * gate * g * 0.09
	var l := 0.0
	for i in n:
		l += (a[i] - l) * 0.4
		a[i] = l
	return _loop(a, f, LR)

func _amb_pocket(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 14.0
	var f := int(3.0 * RATE)
	var n := int(sec * RATE) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	for i in n:
		l1 += (r.randf_range(-1.0, 1.0) - l1) * 0.02
		a[i] = l1 * 0.35
	# soft bells on a pentatonic scale, far off, each ringing a long while
	var notes := [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.5]
	var t0 := 0.2
	while t0 < sec + 1.0:
		var fq: float = notes[r.randi_range(0, notes.size() - 1)]
		var g := r.randf_range(0.03, 0.07)
		var s0 := int(t0 * RATE)
		for j in int(3.0 * RATE):
			if s0 + j >= n:
				break
			var tt := float(j) / RATE
			var env := exp(-tt * 1.6) * minf(1.0, tt * 60.0)
			a[s0 + j] += (sin(tt * fq * TAU) + 0.25 * sin(tt * fq * 2.0 * TAU) + 0.08 * sin(tt * fq * 3.0 * TAU)) * env * g
		t0 += r.randf_range(0.6, 1.5)
	return _loop(a, f, RATE)

func _amb_fire(r: RandomNumberGenerator) -> AudioStreamWAV:
	var sec := 5.0
	var f := int(0.6 * RATE)
	var n := int(sec * RATE) + f
	var a := PackedFloat32Array()
	a.resize(n)
	var l1 := 0.0
	var l2 := 0.0
	for i in n:
		var t := float(i) / RATE
		l1 += (r.randf_range(-1.0, 1.0) - l1) * 0.03
		l2 += (l1 - l2) * 0.1
		a[i] = l2 * 1.6 * (0.8 + 0.2 * sin(t * TAU * 1.3))
	# crackles and pops
	for d in int(sec * 14.0):
		var s0 := r.randi_range(0, n - 300)
		var g := r.randf_range(0.05, 0.3) * (2.0 if r.randf() < 0.1 else 1.0)
		var ln := r.randi_range(25, 180)
		var hp := 0.0
		for j in ln:
			var x := r.randf_range(-1.0, 1.0)
			hp += (x - hp) * 0.3
			a[s0 + j] += (x - hp) * g * exp(-float(j) / float(ln) * 4.0)
	return _loop(a, f, RATE)

# --------------------------------------------------------------- synthesis ---
## Into a 16-bit wav. Loud peaks are rounded off softly (above SOFT_KNEE they bend toward SOFT_CEIL) instead
## of being cut flat at the limit, and a one-shot's last few milliseconds fade to silence, so it never ends on
## a step (26 Nov: both were heard as crackles and snaps). A loop keeps its ends as they are (`tail` false).
const SOFT_KNEE := 0.7
const SOFT_CEIL := 0.97
const TAIL_FADE := 0.004
func _wav(samples: PackedFloat32Array, rate := RATE, tail := true) -> AudioStreamWAV:
	var data := PackedByteArray()
	var n := samples.size()
	data.resize(n * 2)
	var fade := int(TAIL_FADE * rate) if tail else 0
	for i in n:
		var x: float = samples[i]
		var ax := absf(x)
		if ax > SOFT_KNEE:
			x = signf(x) * (SOFT_KNEE + (SOFT_CEIL - SOFT_KNEE) * tanh((ax - SOFT_KNEE) / (SOFT_CEIL - SOFT_KNEE)))
		if i >= n - fade:
			x *= float(n - 1 - i) / float(fade)
		data.encode_s16(i * 2, int(x * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

func _buf(sec: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(sec * RATE))
	return a

## filtered noise burst: crunchy (dig), soft (steps) or deep (booms)
func _noise(sec: float, cutoff: float, decay: float, gain: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var lp := 0.0
	var k := clampf(cutoff, 0.001, 1.0)
	for i in a.size():
		var t := float(i) / RATE
		lp += (randf() * 2.0 - 1.0 - lp) * k
		a[i] = lp * exp(-t * decay) * gain * minf(1.0, t * 250.0)
	return a

## band-passed noise burst (between two one-pole low-passes): the "body" of a hit, a rustle, a hiss
func _band(sec: float, lo_k: float, hi_k: float, decay: float, gain: float, attack := 250.0) -> PackedFloat32Array:
	var a := _buf(sec)
	var l1 := 0.0
	var l2 := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var x := randf() * 2.0 - 1.0
		l1 += (x - l1) * hi_k
		l2 += (x - l2) * lo_k
		a[i] = (l1 - l2) * exp(-t * decay) * gain * minf(1.0, t * attack)
	return a

## a tone that slides from f0 to f1 (sine, square or saw)
func _sweep(sec: float, f0: float, f1: float, shape: String, decay: float, gain: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / sec)
		ph += f / RATE
		var x := sin(ph * TAU)
		if shape == "square":
			x = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
		elif shape == "saw":
			x = fmod(ph, 1.0) * 2.0 - 1.0
		var att := minf(1.0, t * 400.0)
		a[i] = x * exp(-t * decay) * gain * att
	return a

## a tone whose pitch falls (or rises) exponentially from f0 toward f1: drums, thumps, knocks
func _drop(sec: float, f0: float, f1: float, speed: float, decay: float, gain: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var f := f1 + (f0 - f1) * exp(-t * speed)
		ph += f / RATE
		a[i] = sin(ph * TAU) * exp(-t * decay) * gain * minf(1.0, t * 800.0)
	return a

## FM: a carrier modulated at `ratio` times its pitch, the brightness (index) dying away: bells, metal, glass
func _fm(sec: float, fc: float, ratio: float, index: float, decay: float, gain: float, idx_decay := 6.0) -> PackedFloat32Array:
	var a := _buf(sec)
	for i in a.size():
		var t := float(i) / RATE
		var md := sin(t * fc * ratio * TAU) * index * exp(-t * idx_decay)
		a[i] = sin(t * fc * TAU + md) * exp(-t * decay) * gain * minf(1.0, t * 900.0)
	return a

## a voice-like groan: a saw through two formants, its pitch sliding from f0 to f1
func _voice(sec: float, f0: float, f1: float, form1: float, form2: float, decay: float, gain: float, vib := 0.0) -> PackedFloat32Array:
	var a := _buf(sec)
	var ph := 0.0
	var s1 := [0.0, 0.0]
	var s2 := [0.0, 0.0]
	for i in a.size():
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / sec) * (1.0 + vib * sin(t * 34.0))
		ph += f / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		var y := _reso(saw, form1, 5.0, float(RATE), s1) + 0.6 * _reso(saw, form2, 7.0, float(RATE), s2)
		a[i] = y * exp(-t * decay) * gain * minf(1.0, t * 120.0) * minf(1.0, (sec - t) * 30.0)
	return a

## grains: many tiny bursts of noise scattered over `sec` (crunching, crackling, scattering)
func _grains(sec: float, count: int, glen: float, bright: float, gain: float, decay: float) -> PackedFloat32Array:
	var a := _buf(sec)
	for g in count:
		var t0 := randf() * sec * 0.7
		var s0 := int(t0 * RATE)
		var n := int(glen * RATE * randf_range(0.5, 1.5))
		var gg := gain * randf_range(0.4, 1.0) * exp(-t0 * decay)
		var lp := 0.0
		for j in n:
			if s0 + j >= a.size():
				break
			var x := randf() * 2.0 - 1.0
			lp += (x - lp) * bright
			a[s0 + j] += lp * gg * (1.0 - float(j) / float(n))
	return a

## a little chime: the notes one after another, each ringing out
func _chime(notes: Array, gap: float, ring: float, gain: float) -> PackedFloat32Array:
	var a := _buf(gap * notes.size() + ring)
	for n in notes.size():
		var f: float = notes[n]
		var s0 := int(n * gap * RATE)
		for i in range(s0, a.size()):
			var t := float(i - s0) / RATE
			var env := exp(-t * (5.0 / ring)) * minf(1.0, t * 600.0)
			a[i] += (sin(t * f * TAU) + 0.35 * sin(t * f * 2.0 * TAU) + 0.12 * sin(t * f * 3.01 * TAU)) * env * gain
	return a

## smooths a sound (a one-pole low-pass): smaller k is darker and softer
func _lowpass(a: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var out := a.duplicate()
	var lp := 0.0
	for i in out.size():
		lp += (out[i] - lp) * k
		out[i] = lp
	return out

## echoes: the sound again after `delay` seconds, each `fb` as loud (the tail added on)
func _echo(a: PackedFloat32Array, delay: float, fb: float, times: int) -> PackedFloat32Array:
	var d := int(delay * RATE)
	var out := a.duplicate()
	out.resize(a.size() + d * times)
	for i in range(a.size(), out.size()):
		out[i] = 0.0
	for e in range(1, times + 1):
		var g := pow(fb, e)
		for i in a.size():
			out[i + d * e] += a[i] * g
	return out

## delays a sound by `sec` (to layer one part after another)
func _late(a: PackedFloat32Array, sec: float) -> PackedFloat32Array:
	var d := int(sec * RATE)
	var out := PackedFloat32Array()
	out.resize(a.size() + d)
	for i in a.size():
		out[i + d] = a[i]
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out

func _mixn(parts: Array) -> PackedFloat32Array:
	var out: PackedFloat32Array = parts[0]
	for k in range(1, parts.size()):
		out = _mix(out, parts[k])
	return out

func _build_sfx() -> void:
	seed(4242)
	# ---- the mage's own: footsteps by what's underfoot, jumping and landing, getting hurt ----
	sfx["step_soft"] = _wav(_mix(_drop(0.08, 140.0, 70.0, 40.0, 45.0, 0.35), _band(0.07, 0.05, 0.4, 50.0, 0.25)))
	sfx["step_stone"] = _wav(_mixn([_drop(0.05, 320.0, 180.0, 60.0, 80.0, 0.22), _band(0.03, 0.2, 0.9, 120.0, 0.35, 900.0), _drop(0.06, 110.0, 80.0, 30.0, 60.0, 0.2)]))
	sfx["step_sand"] = _wav(_mix(_grains(0.11, 26, 0.006, 0.6, 0.22, 10.0), _band(0.1, 0.1, 0.7, 30.0, 0.12)))
	sfx["step_snow"] = _wav(_mix(_grains(0.13, 34, 0.008, 0.35, 0.3, 8.0), _drop(0.06, 120.0, 80.0, 30.0, 50.0, 0.15)))
	sfx["step_wood"] = _wav(_mixn([_drop(0.12, 230.0, 160.0, 35.0, 32.0, 0.35), _drop(0.09, 510.0, 420.0, 30.0, 45.0, 0.1), _band(0.03, 0.15, 0.7, 110.0, 0.2, 900.0)]))
	sfx["step_metal"] = _wav(_mixn([_fm(0.18, 420.0, 2.76, 3.0, 26.0, 0.12, 30.0), _drop(0.06, 160.0, 90.0, 40.0, 60.0, 0.25), _band(0.02, 0.3, 0.95, 150.0, 0.2, 900.0)]))
	sfx["step"] = sfx["step_soft"]
	# a jump: cloth and air, a soft lift
	sfx["jump"] = _wav(_mix(_band(0.16, 0.04, 0.35, 16.0, 0.35, 60.0), _sweep(0.12, 300.0, 460.0, "sine", 22.0, 0.05)))
	# landing: a thump of boots and a puff of grit
	sfx["land"] = _wav(_mixn([_drop(0.16, 150.0, 55.0, 30.0, 22.0, 0.6), _band(0.14, 0.04, 0.5, 26.0, 0.35), _grains(0.12, 10, 0.006, 0.5, 0.08, 14.0)]))
	# hurt: a blow and a short grunt
	sfx["hurt"] = _wav(_mixn([_drop(0.12, 180.0, 70.0, 30.0, 26.0, 0.45), _band(0.06, 0.08, 0.6, 50.0, 0.4), _late(_voice(0.17, 190.0, 140.0, 600.0, 1300.0, 9.0, 0.35), 0.02)]))
	sfx["levitate"] = _wav(_mix(_band(0.4, 0.02, 0.2, 5.0, 0.4, 20.0), _fm(0.4, 720.0, 1.5, 0.6, 6.0, 0.03, 2.0)))
	# ---- digging and building ----
	# a soft, earthy scoop: dark noise with a gentle start and a low thump under it
	sfx["dig"] = _wav(_lowpass(_mix(_noise(0.16, 0.06, 20.0, 0.75), _sweep(0.12, 120.0, 70.0, "sine", 26.0, 0.22)), 0.35))
	# setting something in place by magic: a solid "tock" and a glint of light
	sfx["place"] = _wav(_mixn([_drop(0.1, 260.0, 150.0, 45.0, 40.0, 0.4), _band(0.04, 0.15, 0.8, 90.0, 0.25, 900.0), _late(_fm(0.25, 1568.0, 2.0, 1.2, 18.0, 0.035, 10.0), 0.02)]))
	sfx["creak"] = _wav(_creak(0.6, 85.0, 0.16))
	sfx["rumble"] = _wav(_mix(_lowpass(_noise(1.2, 0.03, 2.2, 1.3), 0.3), _drop(1.0, 55.0, 32.0, 2.0, 2.6, 0.35)))
	sfx["crack"] = _wav(_mixn([_band(0.05, 0.2, 0.95, 70.0, 0.7, 2000.0), _grains(0.25, 14, 0.01, 0.7, 0.3, 10.0), _creak(0.2, 140.0, 0.08)]))
	sfx["thud"] = _wav(_mix(_lowpass(_noise(0.35, 0.05, 9.0, 1.1), 0.25), _sweep(0.3, 75.0, 38.0, "sine", 9.0, 0.6)))
	# ---- creatures ----
	# a frog's croak: a low buzzing saw falling in pitch, softened; a startled bird's chirp
	sfx["croak"] = _wav(_lowpass(_mix(_sweep(0.16, 210.0, 130.0, "saw", 11.0, 0.2), _sweep(0.12, 420.0, 260.0, "saw", 16.0, 0.06)), 0.35))
	sfx["chirp"] = _wav(_mix(_sweep(0.07, 2400.0, 3300.0, "sine", 22.0, 0.09), _sweep(0.06, 3000.0, 2500.0, "sine", 26.0, 0.06)))
	# a big beast's roar: a growling throat (two formants, a tremor) over a rasp of breath
	sfx["roar"] = _wav(_mixn([_voice(1.3, 95.0, 60.0, 420.0, 900.0, 1.6, 0.45, 0.05), _band(1.3, 0.02, 0.3, 2.2, 0.35, 15.0), _drop(1.0, 70.0, 40.0, 2.0, 2.5, 0.22)]))
	# a mimic's wooden snap
	sfx["mimic"] = _wav(_mixn([_drop(0.18, 260.0, 120.0, 40.0, 20.0, 0.5), _band(0.06, 0.15, 0.8, 60.0, 0.5, 2000.0), _late(_drop(0.15, 220.0, 100.0, 40.0, 24.0, 0.4), 0.11), _creak(0.25, 110.0, 0.06)]))
	# foes: a blade's whoosh, a bowstring, a bat's screech
	sfx["swing"] = _wav(_lowpass(_noise(0.16, 0.3, 14.0, 0.5), 0.5))
	sfx["bow"] = _wav(_mix(_sweep(0.14, 220.0, 150.0, "square", 18.0, 0.12), _noise(0.05, 0.5, 60.0, 0.25)))
	sfx["screech"] = _wav(_sweep(0.22, 2400.0, 1500.0, "square", 9.0, 0.07))
	sfx["hiss"] = _wav(_mix(_noise(0.45, 0.8, 6.0, 0.45), _sweep(0.4, 900.0, 520.0, "square", 7.0, 0.035)))
	sfx["chitter"] = _wav(_mix(_sweep(0.11, 1800.0, 2700.0, "square", 26.0, 0.06), _noise(0.09, 0.7, 36.0, 0.25)))
	# a level's doors and the dark round them (27 Nov: "creepy abandonded ambience"): a pneumatic hiss and a clunk, a
	# door shutting, metal struck somewhere far off, something scuttling through the ducts, the hull groaning
	sfx["door"] = _wav(_mixn([_noise(0.35, 0.7, 7.0, 0.32), _sweep(0.3, 600.0, 300.0, "sine", 8.0, 0.05), _late(_drop(0.12, 140.0, 70.0, 30.0, 30.0, 0.4), 0.18)]))
	sfx["door_shut"] = _wav(_mixn([_noise(0.25, 0.6, 9.0, 0.28), _late(_drop(0.18, 110.0, 50.0, 25.0, 24.0, 0.6), 0.12), _late(_band(0.05, 0.2, 0.9, 80.0, 0.3, 2000.0), 0.12)]))
	sfx["clank"] = _wav(_lowpass(_mixn([_fm(0.9, 310.0, 2.76, 3.0, 4.0, 0.18, 6.0), _drop(0.25, 120.0, 60.0, 12.0, 14.0, 0.35), _noise(0.6, 0.05, 5.0, 0.3)]), 0.4))
	sfx["scuttle"] = _wav(_lowpass(_mixn([_grains(0.9, 46, 0.004, 0.8, 0.32, 2.5), _late(_sweep(0.08, 1600.0, 2300.0, "square", 30.0, 0.025), 0.5)]), 0.5))
	sfx["groan"] = _wav(_lowpass(_creak(1.4, 52.0, 0.22), 0.35))
	sfx["spit"] = _wav(_mix(_noise(0.2, 0.35, 15.0, 0.5), _sweep(0.16, 520.0, 190.0, "sine", 13.0, 0.22)))
	# a hit landing: a sharp smack, a body under it, a flick of grit
	sfx["hit"] = _wav(_mixn([_band(0.04, 0.2, 0.95, 90.0, 0.6, 3000.0), _drop(0.12, 210.0, 80.0, 35.0, 30.0, 0.45), _grains(0.08, 6, 0.005, 0.6, 0.12, 20.0)]))
	# a foe falling: a dying groan that thins into a puff of dust and a last glint
	sfx["foe_die"] = _wav(_mixn([_voice(0.35, 230.0, 90.0, 500.0, 1100.0, 6.0, 0.35), _band(0.45, 0.03, 0.35, 7.0, 0.4, 40.0), _late(_fm(0.4, 1046.5, 3.0, 1.0, 9.0, 0.025, 8.0), 0.18)]))
	# ---- spells ----
	# a light magical twinkle: two soft bell notes over a rising sine and a breath of air
	sfx["spark"] = _wav(_mix(_mix(_chime([1318.5, 1975.5], 0.03, 0.2, 0.07), _sweep(0.18, 700.0, 1250.0, "sine", 16.0, 0.07)), _lowpass(_noise(0.14, 0.5, 24.0, 0.05), 0.5)))
	# a fireball let go: a roaring whoosh with crackles in it
	sfx["fire"] = _wav(_mixn([_band(0.55, 0.02, 0.25, 4.5, 0.9, 25.0), _grains(0.5, 30, 0.004, 0.7, 0.18, 4.0), _drop(0.3, 160.0, 70.0, 8.0, 7.0, 0.3)]))
	# a wave let go: a rushing gush with bubbles in it
	sfx["water"] = _wav(_mixn([_band(0.6, 0.03, 0.3, 4.0, 0.7, 30.0), _bubbles(0.5, 16, 0.1)]))
	sfx["splash"] = _wav(_mixn([_band(0.35, 0.05, 0.6, 9.0, 0.6, 600.0), _bubbles(0.3, 10, 0.08)]))
	sfx["frost"] = _wav(_mix(_chime([1568.0, 2093.0], 0.04, 0.3, 0.12), _noise(0.3, 0.6, 12.0, 0.2)))
	# a blast: a sharp crack, a deep body, and a rolling tail of rubble
	sfx["boom"] = _wav(_mixn([_band(0.06, 0.1, 0.9, 50.0, 0.9, 3000.0), _drop(0.9, 120.0, 32.0, 6.0, 4.0, 0.9), _lowpass(_noise(1.3, 0.03, 3.2, 1.6), 0.4), _grains(1.0, 24, 0.012, 0.4, 0.25, 3.0)]))
	# a blink: air drawn in and a shimmer rising
	sfx["blink"] = _wav(_mixn([_fm(0.3, 600.0, 1.5, 2.5, 9.0, 0.12, 5.0), _sweep(0.22, 500.0, 1900.0, "sine", 9.0, 0.1), _band(0.22, 0.05, 0.5, 12.0, 0.18, 40.0)]))
	# a spell sputtering out (not enough mana): little failing pops and a falling fizz
	sfx["fizzle"] = _wav(_mixn([_grains(0.25, 10, 0.008, 0.8, 0.25, 8.0), _sweep(0.22, 900.0, 260.0, "sine", 12.0, 0.06), _band(0.2, 0.2, 0.9, 14.0, 0.12)]))
	sfx["zap"] = _wav(_mix(_noise(0.45, 0.85, 9.0, 1.0), _sweep(0.3, 1500.0, 260.0, "saw", 11.0, 0.3)))
	# thunder: a crack overhead and a long roll
	sfx["thunder"] = _wav(_mixn([_band(0.08, 0.15, 0.9, 30.0, 0.8, 3000.0), _late(_lowpass(_noise(2.8, 0.02, 1.1, 2.2), 0.25), 0.05), _grains(2.0, 30, 0.03, 0.08, 0.5, 1.4)]))
	# ---- the interface ----
	# (26 Nov: a soft rounded blip; it had a tiny burst of white noise in it that read as a crackle)
	sfx["ui_hover"] = _wav(_lowpass(_fm(0.06, 1568.0, 2.0, 0.35, 55.0, 0.05, 40.0), 0.45))
	sfx["ui_click"] = _wav(_mixn([_chime([784.0, 1175.0], 0.035, 0.18, 0.1), _drop(0.05, 300.0, 200.0, 60.0, 70.0, 0.2), _band(0.02, 0.2, 0.9, 150.0, 0.12, 3000.0)]))
	# speech blips (speech.gd): a soft, rounded "bup" under a breath of square, and the wisp's little chime;
	# played at each speaker's own pitch
	sfx["talk"] = _wav(_lowpass(_mix(_sweep(0.055, 420.0, 380.0, "square", 38.0, 0.07), _sweep(0.05, 840.0, 760.0, "sine", 44.0, 0.08)), 0.3))
	sfx["talk_wisp"] = _wav(_mix(_chime([1567.98], 0.0, 0.09, 0.05), _sweep(0.05, 2350.0, 2600.0, "sine", 50.0, 0.035)))
	# a page turning and settling into the book (25 Nov): a soft papery rustle, a little chime
	sfx["page"] = _wav(_mix(_noise(0.16, 0.35, 18.0, 0.07), _chime([1046.5, 1568.0], 0.08, 0.22, 0.035)))
	# ---- treasure ----
	sfx["chest_open"] = _wav(_mixn([_creak(0.35, 120.0, 0.08), _drop(0.1, 200.0, 120.0, 40.0, 30.0, 0.3), _late(_chime([523.25, 659.25, 783.99, 1046.5], 0.08, 0.6, 0.16), 0.12)]))
	sfx["chest_vanish"] = _wav(_chime([1567.98, 2093.0, 2637.0, 3136.0, 2637.0], 0.05, 0.35, 0.1))
	# a coin: two bright metal pings
	sfx["coin"] = _wav(_mix(_fm(0.25, 1975.5, 1.41, 2.0, 14.0, 0.09, 18.0), _late(_fm(0.25, 2637.0, 1.41, 1.6, 16.0, 0.07, 18.0), 0.05)))
	sfx["rare"] = _wav(_chime([523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0], 0.09, 0.9, 0.2))
	sfx["forge"] = _wav(_mixn([_fm(0.7, 392.0, 3.5, 4.0, 5.0, 0.12, 8.0), _chime([523.25, 659.25, 783.99], 0.07, 0.7, 0.14), _band(0.2, 0.1, 0.8, 20.0, 0.25)]))
	# a wooden door: a creak and a soft knock as it opens, a firmer thud as it shuts
	sfx["door_open"] = _wav(_mix(_creak(0.34, 150.0, 0.07), _drop(0.08, 200.0, 140.0, 40.0, 40.0, 0.25)))
	sfx["door_close"] = _wav(_mixn([_drop(0.16, 140.0, 70.0, 30.0, 20.0, 0.55), _band(0.08, 0.1, 0.7, 40.0, 0.4, 1500.0), _late(_drop(0.08, 300.0, 200.0, 40.0, 50.0, 0.12), 0.03)]))
	# ---- space and ships ----
	# lightning out of a storm belt: a sharp crackle and a falling buzz (zap, above); docking: a clunk of
	# clamps and a hiss of air; the ship's cannon: a deep thump and a rising wisp-whine; the shield taking a hit
	sfx["dock"] = _wav(_mixn([_drop(0.25, 120.0, 60.0, 20.0, 14.0, 0.6), _fm(0.4, 220.0, 2.76, 2.5, 10.0, 0.12, 12.0), _late(_band(0.7, 0.1, 0.8, 4.5, 0.35, 30.0), 0.12)]))
	sfx["cannon"] = _wav(_mixn([_drop(0.25, 160.0, 50.0, 25.0, 14.0, 0.6), _sweep(0.22, 600.0, 1500.0, "sine", 12.0, 0.08), _band(0.18, 0.08, 0.7, 18.0, 0.35, 1000.0)]))
	sfx["shield"] = _wav(_mixn([_fm(0.5, 330.0, 1.5, 3.0, 7.0, 0.16, 6.0), _band(0.3, 0.1, 0.9, 10.0, 0.25, 800.0), _sweep(0.4, 900.0, 600.0, "sine", 8.0, 0.05)]))
	# space's own life (voidlife.gd): a manta's low song, a glyph waking, a rift's roar
	sfx["song"] = _wav(_mix(_sweep(1.6, 150.0, 96.0, "sine", 1.6, 0.32), _sweep(1.2, 300.0, 210.0, "sine", 2.4, 0.08)))
	sfx["glyph"] = _wav(_chime([392.0, 587.33, 783.99], 0.07, 0.7, 0.18))
	sfx["rift"] = _wav(_mix(_lowpass(_noise(1.1, 0.4, 2.4, 0.6), 0.3), _sweep(1.1, 70.0, 880.0, "sine", 2.2, 0.35)))
	randomize()

## wood creaking: a slow saw catching and slipping (stick-slip), through the wood's own ring
func _creak(sec: float, f0: float, gain: float) -> PackedFloat32Array:
	var a := _buf(sec)
	var ph := 0.0
	var rs := [0.0, 0.0]
	for i in a.size():
		var t := float(i) / RATE
		ph += (f0 * (1.0 + 0.3 * t / sec) + randf_range(-f0 * 0.25, f0 * 0.25)) / RATE
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		var env := sin(PI * clampf(t / sec, 0.0, 1.0))
		a[i] = (_reso(saw, f0 * 6.0, 4.0, float(RATE), rs) * 0.8 + saw * 0.2) * env * gain
	return a

## bubbles: little rising blips
func _bubbles(sec: float, count: int, gain: float) -> PackedFloat32Array:
	var a := _buf(sec)
	for b in count:
		var s0 := int(randf() * sec * 0.8 * RATE)
		var f0 := randf_range(350.0, 900.0)
		var ph := 0.0
		for j in int(0.04 * RATE):
			if s0 + j >= a.size():
				break
			var tt := float(j) / RATE
			ph += f0 * (1.0 + tt * 25.0) / RATE
			a[s0 + j] += sin(ph * TAU) * exp(-tt * 70.0) * gain * randf_range(0.6, 1.0)
	return a
