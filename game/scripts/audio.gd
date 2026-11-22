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
## "underground", "deep", "boss", "space", "title" (anything starting with that word counts, so
## "surface_day_2.mp3" joins the day tracks). A track for one kind of planet starts with the kind:
## "volcanic_surface_day.mp3" plays on volcanic worlds by day (kinds: temperate, volcanic, ocean,
## desert, marsh, frozen, wild, realm); a world with no track of its own for the moment plays the
## common one. Tracks crossfade when the situation changes.

var game
const RATE := 22050
var sfx := {}                 # name -> AudioStreamWAV
var _cool := {}               # name -> frames until it may play again
var _players := []
var _next := 0
var sfx_volume := 0.8         # 0..1, from settings
var music_volume := 0.6

var tracks := {}              # mood (or "kind:mood") -> Array of streams
const MOODS := ["surface_day", "surface_night", "underground", "deep", "boss", "space", "title"]
const KINDS := ["temperate", "volcanic", "ocean", "desert", "marsh", "frozen", "wild", "realm"]
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_on_a := true
var _mood := ""
var _fade := 1.0

const COOLDOWN := {"dig": 6, "step": 9, "spark": 4, "hit": 5, "coin": 3, "creak": 50, "rumble": 25, "land": 8,
	"place": 5, "levitate": 14, "splash": 10, "ui_hover": 3, "swing": 8, "bow": 6, "screech": 12, "crack": 6, "thud": 6, "zap": 8, "croak": 18, "chirp": 10}

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
	if _music_task >= 0:
		_take_music()
	for k in _cool.keys():
		_cool[k] = int(_cool[k]) - 1
	_update_music()

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

## which list a music file joins: "mood", or "kind:mood" for a planet kind's own ("" for none)
static func track_key(fn: String) -> String:
	var kind := ""
	var rest := fn
	for k in KINDS:
		if fn.begins_with(k + "_"):
			kind = k
			rest = fn.substr(k.length() + 1)
			break
	for mood in MOODS:
		if rest.begins_with(mood):
			return mood if kind == "" else kind + ":" + mood
	return ""

## what should be playing now
func _want_mood() -> String:
	if game == null or game.state == "title" or game.state == "loading":
		return "title"
	if game.space != null and game.space.active:
		return "space"
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

## a track for the mood: this planet kind's own first, then the common one, then the fallbacks' in turn
func _pick(mood: String) -> AudioStream:
	var fall := {"surface_night": "surface_day", "deep": "underground", "boss": "underground", "title": "surface_day", "underground": "surface_night", "space": "surface_night"}
	var kind := _kind()
	var m := mood
	for k in 4:
		for key in ([kind + ":" + m, m] if kind != "" else [m]):
			if tracks.has(key) and not tracks[key].is_empty():
				return tracks[key][randi() % tracks[key].size()]
		m = fall.get(m, "")
		if m == "":
			break
	return null

func _kind() -> String:
	if game == null or game.state == "title":
		return ""
	return String(game.planet.get("kind", ""))

func _update_music() -> void:
	if tracks.is_empty():
		return
	var mood := _want_mood()
	var mkey := _kind() + ":" + mood                     # (a new kind of planet is a new mood)
	var cur: AudioStreamPlayer = _music_a if _music_on_a else _music_b
	var old: AudioStreamPlayer = _music_b if _music_on_a else _music_a
	if mkey != _mood:
		var st := _pick(mood)
		_mood = mkey
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
		a[i] = lp * exp(-t * decay) * gain * minf(1.0, t * 250.0)
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

## smooths a sound (a one-pole low-pass): smaller k is darker and softer
func _lowpass(a: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var out := a.duplicate()
	var lp := 0.0
	for i in out.size():
		lp += (out[i] - lp) * k
		out[i] = lp
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := a.duplicate() if a.size() >= b.size() else b.duplicate()
	var other := b if a.size() >= b.size() else a
	for i in other.size():
		out[i] += other[i]
	return out

func _build_sfx() -> void:
	seed(4242)
	# a soft, earthy scoop: dark noise with a gentle start and a low thump under it
	sfx["dig"] = _wav(_lowpass(_mix(_noise(0.16, 0.06, 20.0, 0.75), _sweep(0.12, 120.0, 70.0, "sine", 26.0, 0.22)), 0.35))
	sfx["step"] = _wav(_noise(0.06, 0.12, 60.0, 0.5))
	# a frog's croak: a low buzzing saw falling in pitch, softened; a startled bird's chirp
	sfx["croak"] = _wav(_lowpass(_mix(_sweep(0.16, 210.0, 130.0, "saw", 11.0, 0.2), _sweep(0.12, 420.0, 260.0, "saw", 16.0, 0.06)), 0.35))
	sfx["chirp"] = _wav(_mix(_sweep(0.07, 2400.0, 3300.0, "sine", 22.0, 0.09), _sweep(0.06, 3000.0, 2500.0, "sine", 26.0, 0.06)))
	sfx["land"] = _wav(_mix(_noise(0.12, 0.08, 30.0, 0.9), _sweep(0.1, 120.0, 60.0, "sine", 30.0, 0.4)))
	sfx["jump"] = _wav(_sweep(0.12, 260.0, 520.0, "sine", 14.0, 0.28))
	sfx["levitate"] = _wav(_mix(_noise(0.25, 0.05, 6.0, 0.25), _sweep(0.25, 600.0, 640.0, "sine", 8.0, 0.06)))
	# a light magical twinkle: two soft bell notes over a rising sine and a breath of air
	sfx["spark"] = _wav(_mix(_mix(_chime([1318.5, 1975.5], 0.03, 0.2, 0.07), _sweep(0.18, 700.0, 1250.0, "sine", 16.0, 0.07)), _lowpass(_noise(0.14, 0.5, 24.0, 0.05), 0.5)))
	sfx["fire"] = _wav(_mix(_noise(0.4, 0.06, 6.0, 0.8), _sweep(0.3, 300.0, 140.0, "saw", 8.0, 0.12)))
	sfx["water"] = _wav(_noise(0.45, 0.25, 5.0, 0.55))
	sfx["frost"] = _wav(_mix(_chime([1568.0, 2093.0], 0.04, 0.3, 0.12), _noise(0.3, 0.6, 12.0, 0.2)))
	sfx["boom"] = _wav(_mix(_noise(0.9, 0.025, 4.5, 1.6), _sweep(0.5, 90.0, 35.0, "sine", 6.0, 0.7)))
	sfx["blink"] = _wav(_sweep(0.22, 300.0, 1800.0, "sine", 8.0, 0.25))
	sfx["place"] = _wav(_noise(0.07, 0.2, 45.0, 0.6))
	sfx["hurt"] = _wav(_sweep(0.18, 420.0, 140.0, "square", 12.0, 0.25))
	sfx["ui_hover"] = _wav(_sweep(0.05, 900.0, 1100.0, "sine", 40.0, 0.10))
	sfx["ui_click"] = _wav(_mix(_chime([784.0, 1175.0], 0.035, 0.18, 0.12), _noise(0.03, 0.4, 80.0, 0.15)))
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
	# a wooden door: a creak and a soft knock as it opens, a firmer thud as it shuts
	sfx["door_open"] = _wav(_mix(_sweep(0.32, 180.0, 260.0, "saw", 5.0, 0.07), _noise(0.08, 0.3, 40.0, 0.35)))
	sfx["door_close"] = _wav(_mix(_sweep(0.12, 110.0, 70.0, "sine", 20.0, 0.5), _noise(0.1, 0.2, 35.0, 0.55)))
	# foes: a blade's whoosh, a bowstring, a bat's screech
	sfx["swing"] = _wav(_lowpass(_noise(0.16, 0.3, 14.0, 0.5), 0.5))
	sfx["bow"] = _wav(_mix(_sweep(0.14, 220.0, 150.0, "square", 18.0, 0.12), _noise(0.05, 0.5, 60.0, 0.25)))
	sfx["screech"] = _wav(_sweep(0.22, 2400.0, 1500.0, "square", 9.0, 0.07))
	# falling pieces: wood cracking as a trunk goes, and the heavy thud of a piece landing
	sfx["crack"] = _wav(_mix(_noise(0.18, 0.6, 22.0, 0.7), _sweep(0.12, 180.0, 90.0, "saw", 20.0, 0.15)))
	# lightning out of a storm belt: a sharp crackle and a falling buzz
	sfx["zap"] = _wav(_mix(_noise(0.45, 0.85, 9.0, 1.0), _sweep(0.3, 1500.0, 260.0, "saw", 11.0, 0.3)))
	sfx["thud"] = _wav(_mix(_lowpass(_noise(0.35, 0.05, 9.0, 1.1), 0.25), _sweep(0.3, 75.0, 38.0, "sine", 9.0, 0.6)))
	randomize()
