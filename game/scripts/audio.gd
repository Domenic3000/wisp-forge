extends Node
## Sound for Wisp Forge.
##
## Sound effects are synthesised here at startup (little waveforms built from noise, sweeps and
## chimes), so the game has sound without any audio files. play(name, world_pos) plays one:
## quieter the further it is from the camera, with a touch of random pitch so repeats don't
## sound mechanical, and never more often than its cooldown allows.
##
## Music is optional: any .mp3 or .ogg files in game/audio/music/ are loaded at runtime (no
## import step). A track's name decides when it plays: "surface_day", "surface_night",
## "underground", "deep", "boss", "title" (anything starting with that word counts, so
## "surface_day_2.mp3" joins the day tracks). Tracks crossfade when the situation changes.

var game
const RATE := 22050
var sfx := {}                 # name -> AudioStreamWAV
var _cool := {}               # name -> frames until it may play again
var _players := []
var _next := 0
var sfx_volume := 0.8         # 0..1, from settings
var music_volume := 0.6

var tracks := {}              # mood -> Array of streams
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_on_a := true
var _mood := ""
var _fade := 1.0

const COOLDOWN := {"dig": 6, "step": 9, "spark": 4, "hit": 5, "coin": 3, "creak": 50, "rumble": 25, "land": 8,
	"place": 5, "levitate": 14, "splash": 10}

func _ready() -> void:
	for k in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	add_child(_music_a)
	add_child(_music_b)
	_music_a.volume_db = -80.0
	_music_b.volume_db = -80.0
	_build_sfx()
	_load_music()

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
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = sfx[sname]
	p.volume_db = linear_to_db(v)
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	p.play()

func _process(_delta: float) -> void:
	for k in _cool.keys():
		_cool[k] = int(_cool[k]) - 1
	_update_music()

# -------------------------------------------------------------------- music ---
func _load_music() -> void:
	var dir := "res://audio/music"
	var d := DirAccess.open(dir)
	if d == null:
		return
	for fn in d.get_files():
		var path := dir.path_join(fn)
		var stream: AudioStream = null
		if fn.ends_with(".mp3"):
			var m := AudioStreamMP3.new()
			m.data = FileAccess.get_file_as_bytes(path)
			m.loop = true
			stream = m
		elif fn.ends_with(".ogg"):
			var o := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(path))
			if o:
				o.loop = true
				stream = o
		if stream == null:
			continue
		for mood in ["surface_day", "surface_night", "underground", "deep", "boss", "title"]:
			if fn.begins_with(mood):
				if not tracks.has(mood):
					tracks[mood] = []
				tracks[mood].append(stream)
	print("[Wisp Forge] music: %s" % str(tracks.keys()))

## what should be playing now
func _want_mood() -> String:
	if game == null or game.state == "title" or game.state == "loading":
		return "title"
	var p: Vector2 = game.player.pos
	var rs: float = game.gpu.surf_at(atan2(p.y, p.x)).x
	var depth := rs - p.length()
	for e in game.enemies:
		if e.boss and e.awake and (e.pos as Vector2).distance_to(p) < 260.0:
			return "boss"
	if depth > 220.0:
		return "deep"
	if depth > 40.0:
		return "underground"
	return "surface_day" if game._local_daylight(p) > 0.3 else "surface_night"

func _pick(mood: String) -> AudioStream:
	var fall := {"surface_night": "surface_day", "deep": "underground", "boss": "underground", "title": "surface_day", "underground": "surface_night"}
	var m := mood
	for k in 3:
		if tracks.has(m) and not tracks[m].is_empty():
			return tracks[m][randi() % tracks[m].size()]
		m = fall.get(m, "")
		if m == "":
			break
	return null

func _update_music() -> void:
	if tracks.is_empty():
		return
	var mood := _want_mood()
	var cur: AudioStreamPlayer = _music_a if _music_on_a else _music_b
	var old: AudioStreamPlayer = _music_b if _music_on_a else _music_a
	if mood != _mood:
		var st := _pick(mood)
		_mood = mood
		if st != null and st != cur.stream:
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

# --------------------------------------------------------------- synthesis ---
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
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
		a[i] = lp * exp(-t * decay) * gain
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

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out

func _build_sfx() -> void:
	seed(4242)
	sfx["dig"] = _wav(_mix(_noise(0.13, 0.35, 28.0, 0.9), _sweep(0.08, 180.0, 90.0, "square", 40.0, 0.12)))
	sfx["step"] = _wav(_noise(0.06, 0.12, 60.0, 0.5))
	sfx["land"] = _wav(_mix(_noise(0.12, 0.08, 30.0, 0.9), _sweep(0.1, 120.0, 60.0, "sine", 30.0, 0.4)))
	sfx["jump"] = _wav(_sweep(0.12, 260.0, 520.0, "sine", 14.0, 0.28))
	sfx["levitate"] = _wav(_mix(_noise(0.25, 0.05, 6.0, 0.25), _sweep(0.25, 600.0, 640.0, "sine", 8.0, 0.06)))
	sfx["spark"] = _wav(_sweep(0.16, 1400.0, 380.0, "square", 18.0, 0.22))
	sfx["fire"] = _wav(_mix(_noise(0.4, 0.06, 6.0, 0.8), _sweep(0.3, 300.0, 140.0, "saw", 8.0, 0.12)))
	sfx["water"] = _wav(_noise(0.45, 0.25, 5.0, 0.55))
	sfx["frost"] = _wav(_mix(_chime([1568.0, 2093.0], 0.04, 0.3, 0.12), _noise(0.3, 0.6, 12.0, 0.2)))
	sfx["boom"] = _wav(_mix(_noise(0.9, 0.025, 4.5, 1.6), _sweep(0.5, 90.0, 35.0, "sine", 6.0, 0.7)))
	sfx["blink"] = _wav(_sweep(0.22, 300.0, 1800.0, "sine", 8.0, 0.25))
	sfx["place"] = _wav(_noise(0.07, 0.2, 45.0, 0.6))
	sfx["hurt"] = _wav(_sweep(0.18, 420.0, 140.0, "square", 12.0, 0.25))
	sfx["hit"] = _wav(_mix(_noise(0.08, 0.5, 40.0, 0.6), _sweep(0.08, 300.0, 150.0, "square", 30.0, 0.15)))
	sfx["foe_die"] = _wav(_mix(_noise(0.3, 0.2, 10.0, 0.7), _sweep(0.25, 500.0, 90.0, "saw", 10.0, 0.18)))
	sfx["chest_open"] = _wav(_mix(_sweep(0.35, 110.0, 160.0, "saw", 6.0, 0.12), _chime([523.25, 659.25, 783.99, 1046.5], 0.08, 0.6, 0.18)))
	sfx["chest_vanish"] = _wav(_chime([1567.98, 2093.0, 2637.0, 3136.0, 2637.0], 0.05, 0.35, 0.1))
	sfx["coin"] = _wav(_chime([1318.5, 1760.0], 0.05, 0.18, 0.18))
	sfx["rare"] = _wav(_chime([523.25, 659.25, 783.99, 1046.5, 1318.5, 1568.0], 0.09, 0.9, 0.2))
	sfx["creak"] = _wav(_sweep(0.55, 70.0, 95.0, "saw", 3.0, 0.16))
	sfx["rumble"] = _wav(_noise(0.8, 0.02, 3.5, 1.2))
	sfx["forge"] = _wav(_mix(_chime([392.0, 523.25, 659.25, 783.99], 0.07, 0.8, 0.2), _noise(0.2, 0.5, 20.0, 0.3)))
	sfx["mimic"] = _wav(_mix(_sweep(0.4, 160.0, 60.0, "saw", 5.0, 0.4), _noise(0.3, 0.3, 8.0, 0.5)))
	sfx["roar"] = _wav(_mix(_sweep(1.2, 90.0, 45.0, "saw", 2.0, 0.6), _noise(1.2, 0.04, 2.0, 0.8)))
	sfx["splash"] = _wav(_noise(0.3, 0.4, 9.0, 0.5))
	randomize()
