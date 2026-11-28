## Cutscenes (28 Nov; user: "maybe we can start working in cutscenes and a story ... some kind of story and build up
## with a big bad to drive the player through the game"; chose both kinds, short and skippable). A scene is a list of
## steps, played while the world waits (main state "scene"):
##   {"panel": name, "text": caption}           an illustrated panel (story_art.gd) over black, its caption typed out
##   {"say": who, "text": words, "at": pos}     in the world, letterboxed: a speech bubble over the speaker ("wisp",
##                                              "you", or a world point "at"), the camera easing to "cam" (or the
##                                              speaker); style "ember" for the keepers and Vulkhar
##   {"wait": frames, "cam": pos}               a held shot
## Any click, Space, Enter or F finishes the words or goes on; Esc skips the whole scene. A step also goes on by
## itself once its words have been up long enough to read. story.gd says what plays when.
extends CanvasLayer

const PixelFont := preload("res://scripts/pixel_font.gd")
const StoryArt := preload("res://scripts/story_art.gd")
const Speech := preload("res://scripts/speech.gd")

var game
var view: Control
var steps: Array = []
var at := 0
var t := 0
var active := false
var name_now := ""
var bars := 0.0               # the letterbox, 0..1
var shown := 0.0              # a panel's caption: letters typed
var on_done = null            # a Callable, or null
var _tex := {}                # panel name -> ImageTexture
var _cam0 := Vector2.ZERO
var _was_hud := true
var stats := {"played": [], "skipped": 0, "steps": 0}

func _init(g) -> void:
	game = g
	layer = 40
	view = Control.new()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.draw.connect(_draw_view)
	add_child(view)
	visible = false

## start a scene (another already playing is ended first, its on_done run)
func play(scene_name: String, list: Array, done = null) -> void:
	if active:
		_finish()
	if list.is_empty():
		if done != null:
			(done as Callable).call()
		return
	steps = list
	name_now = scene_name
	at = 0
	t = 0
	shown = 0.0
	bars = 0.0
	on_done = done
	active = true
	visible = true
	_cam0 = game.cam_c
	stats["played"].append(scene_name)
	if game.state != "scene":
		game.state = "scene"
	_was_hud = game.ui.hud.visible
	game.ui.hud.visible = false
	_begin_step()

func step() -> Dictionary:
	return steps[at] if active and at < steps.size() else {}

func is_panel() -> bool:
	return step().has("panel")

func _begin_step() -> void:
	t = 0
	shown = 0.0
	stats["steps"] += 1
	var s := step()
	if s.has("panel") and not _tex.has(String(s["panel"])):
		_tex[String(s["panel"])] = ImageTexture.create_from_image(StoryArt.panel(String(s["panel"])))
	if s.has("say"):
		game.audio.play("ui_click", null, 0.25)

## where a speaker is in the world
func _speaker_pos(s: Dictionary) -> Vector2:
	if s.has("at"):
		return s["at"]
	match String(s.get("say", "")):
		"wisp": return game.wisp
		"you": return game.player.pos
	return game.player.pos

func _text_len(s: Dictionary) -> int:
	return String(s.get("text", "")).length()

## is this step's text all out?
func _typed(s: Dictionary) -> bool:
	if s.has("panel"):
		return shown >= float(_text_len(s))
	if s.has("say"):
		return not game.speech.typing(_key())
	return true

func _key() -> String:
	return "scene:%s:%d" % [name_now, at]

## how long a step stays up once its words are out (frames): long enough to read them
func _hold(s: Dictionary) -> int:
	if s.has("wait"):
		return int(s["wait"])
	return 90 + int(float(_text_len(s)) * 2.4)

## every frame while a scene plays (main _process, state "scene")
func tick() -> void:
	if not active:
		return
	t += 1
	var s := step()
	bars = minf(1.0, bars + 0.08)
	if s.has("panel"):
		if t > 18:
			shown = minf(float(_text_len(s)), shown + 0.9)
	else:
		# the camera eases to the shot: the speaker, or the step's own "cam"
		var target: Vector2 = s.get("cam", _speaker_pos(s) if s.has("say") else game.cam_c)
		game.cam_c = game.cam_c.lerp(target, 0.07)
		# the wisp drifts to beside you while it speaks
		if String(s.get("say", "")) == "wisp" and not s.has("at"):
			var want: Vector2 = game.player.pos + game.basis_r(atan2(game.player.pos.y, game.player.pos.x)) * 14.0 - game.basis_d(atan2(game.player.pos.y, game.player.pos.x)) * 18.0
			game.wisp = game.wisp.lerp(want, 0.06)
	if _typed(s):
		if t > _hold(s) + (0 if s.has("wait") else 30):
			_next()
	view.queue_redraw()

func _next() -> void:
	at += 1
	if at >= steps.size():
		_finish()
		return
	_begin_step()

func _finish() -> void:
	active = false
	visible = false
	steps = []
	game.ui.hud.visible = _was_hud
	if game.state == "scene":
		game.state = "play"
	var done = on_done
	on_done = null
	if done != null:
		(done as Callable).call()

## the bubbles to draw in the world now (overlay.gd): [world point, text, alpha, key, style, pitch]
func bubbles() -> Array:
	var s := step()
	if not s.has("say"):
		return []
	var style: int = Speech.WISP if String(s["say"]) == "wisp" else (Speech.EMBER if String(s.get("style", "")) == "ember" else Speech.SPEECH)
	var p := _speaker_pos(s)
	var lift: float = float(s.get("lift", 0.0))
	return [[p - game.basis_d(atan2(p.y, p.x)) * lift, String(s["text"]), 1.0, _key(), style, float(s.get("pitch", 1.0))]]

## a click, Space, Enter or F: the words all at once, or on; Esc: the whole scene skipped
func key(k: int) -> void:
	if not active:
		return
	if k == KEY_ESCAPE:
		stats["skipped"] += 1
		_finish()
		return
	if k == KEY_SPACE or k == KEY_ENTER or k == KEY_KP_ENTER or game.key_is(k, "interact") or game.key_is(k, "jump"):
		advance()

func advance() -> void:
	if not active:
		return
	var s := step()
	if not _typed(s):
		if s.has("panel"):
			shown = float(_text_len(s))
		elif game.speech.st.has(_key()):
			game.speech.st[_key()]["shown"] = float(_text_len(s))
		return
	_next()

# ---------------------------------------------------------------- drawing ---
func _draw_view() -> void:
	if not active:
		return
	var vs: Vector2 = view.get_viewport_rect().size
	var u: float = float(game.ui.U) * maxf(1.0, float(game.scale_px) / 2.0)
	var f: Font = PixelFont.make()
	var fs := int(PixelFont.SIZE * u)
	var s := step()
	if s.has("panel"):
		view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.0))
		var tex: Texture2D = _tex.get(String(s["panel"]))
		if tex != null:
			# the picture as big as fits above its caption, in whole pixels; it fades in
			var k := floorf(minf(vs.x * 0.86 / float(StoryArt.W), vs.y * 0.7 / float(StoryArt.H)))
			k = maxf(k, 1.0)
			var sz := Vector2(StoryArt.W, StoryArt.H) * k
			var pos := ((vs - sz) * 0.5 - Vector2(0, vs.y * 0.06)).round()
			var a := clampf(float(t) / 18.0, 0.0, 1.0)
			view.draw_texture_rect(tex, Rect2(pos, sz), false, Color(1, 1, 1, a))
			# a thin frame
			var fr := Color(0.55, 0.6, 0.85, 0.5 * a)
			view.draw_rect(Rect2(pos - Vector2(k, k), sz + Vector2(k, k) * 2.0), fr, false, k)
			_caption(f, fs, String(s["text"]).substr(0, int(shown)), Vector2(vs.x * 0.5, pos.y + sz.y + 14.0 * u), vs.x * 0.72, a)
	else:
		var bh := roundf(vs.y * 0.11 * bars)
		view.draw_rect(Rect2(0, 0, vs.x, bh), Color(0, 0, 0))
		view.draw_rect(Rect2(0, vs.y - bh, vs.x, bh), Color(0, 0, 0))
	var hint := "%s: next    Esc: skip" % game.key_label("interact")
	var hs := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	view.draw_string(f, Vector2(vs.x - hs.x - 10.0 * u, vs.y - 8.0 * u), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.6, 0.62, 0.75, 0.7))

## a caption, centred, wrapped to `maxw`, its first line's top at `top`
func _caption(f: Font, fs: int, text: String, top: Vector2, maxw: float, a: float) -> void:
	var full := String(step().get("text", ""))
	# (laid out from the whole text, so lines don't jump as it types)
	var lines := []
	var cur := ""
	for word in full.split(" "):
		var tryl: String = word if cur == "" else cur + " " + word
		if f.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > maxw and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = tryl
	if cur != "":
		lines.append(cur)
	var left := text.length()
	var y := top.y
	for ln in lines:
		var part: String = ln.substr(0, maxi(0, left))
		left -= ln.length() + 1
		var w := f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := roundf(top.x - w * 0.5)
		view.draw_string(f, Vector2(x + 1, y + fs + 1), part, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, a))
		view.draw_string(f, Vector2(x, y + fs), part, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.86, 0.9, 1.0, a))
		y += float(fs) * 1.5
