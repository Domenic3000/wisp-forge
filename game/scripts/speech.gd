## Speech bubbles (user, 25 Nov: "make the text boxes for speech look a little nicer with an animation and
## talking sound effects"). One drawer for every bubble in the game: villagers, keepers, the wisp, spacers,
## and prompts ("[F] ..."). main `speech`; overlay `_bubble` and space.gd's folk call `draw`.
##
## Each bubble is remembered by a key (who's speaking) while it's drawn: it POPS in (the box grows out of
## its tail with a little overshoot, then the words come), the words are TYPED out a letter at a time with
## short pauses after commas and full stops, and each few letters a soft BLIP plays at the speaker's own
## pitch (villagers and spacers by their seed, the wisp a little chime). A bubble not drawn for a few frames
## is forgotten, so the next time it speaks it pops in again; new words under the same key start over.
## Prompts pop in but show their words at once, silently. Styles: SPEECH (a parchment bubble), WISP
## (deep blue with a pale glowing edge and twinkles), PROMPT (dark ink with a gold edge). Words in
## [brackets] (the keys: "[F]") are picked out in the style's accent. All in whole game pixels.
extends RefCounted

const PixelFont := preload("res://scripts/pixel_font.gd")

enum { SPEECH, WISP, PROMPT, EMBER }    # (EMBER: the old keepers and Vulkhar in the story's scenes, cutscene.gd)

const POP := 7            # frames the box takes to open
const TYPE_AT := 4        # the words start once the box is this far open
const CPS := 1.15         # letters a frame (about 70 a second)
const BLIP_EVERY := 2     # a blip every this many letters
const FORGET := 12        # frames unseen before a bubble is forgotten

var game
var st := {}              # key -> {text, shown, age, seen, pause, said}
var stats := {"blips": 0, "popped": 0}

## voice pitch for a speaker's seed: 0.78..1.3
static func pitch_of(sd: int) -> float:
	return lerpf(0.78, 1.3, fposmod(float(sd) * 0.6180339, 1.0))

## the state of a bubble this frame (advanced at most once a frame)
func _tick(key: String, text: String, style: int, wpos, pitch: float, alpha: float) -> Dictionary:
	var now := Engine.get_process_frames()
	if now % 60 == 0:
		for k in st.keys():
			if now - int(st[k]["seen"]) > FORGET:
				st.erase(k)
	var s: Dictionary = st.get(key, {})
	if s.is_empty() or String(s["text"]) != text or now - int(s["seen"]) > FORGET:
		s = {"text": text, "shown": 0.0 if style != PROMPT else float(text.length()), "age": 0, "seen": now,
			"pause": 0, "said": 0, "frame": now}
		st[key] = s
		stats["popped"] += 1
	if int(s["frame"]) == now and int(s["age"]) > 0:
		s["seen"] = now
		return s
	s["frame"] = now
	s["seen"] = now
	s["age"] = int(s["age"]) + 1
	if int(s["age"]) >= TYPE_AT and float(s["shown"]) < float(text.length()):
		if int(s["pause"]) > 0:
			s["pause"] = int(s["pause"]) - 1
		else:
			var before := int(s["shown"])
			s["shown"] = minf(float(text.length()), float(s["shown"]) + CPS)
			for i in range(before, int(s["shown"])):
				var ch := text[i]
				if ch == "." or ch == "!" or ch == "?":
					s["pause"] = 7 if i + 1 < text.length() and text[i + 1] == " " else 0
				elif ch == "," or ch == ";" or ch == ":":
					s["pause"] = 3
				if ch != " " and ch != "." and ch != "," and alpha > 0.5:
					s["said"] = int(s["said"]) + 1
					if int(s["said"]) % BLIP_EVERY == 1 and game != null:
						var snd := "talk_wisp" if style == WISP else "talk"
						game.audio.play(snd, wpos, 0.55 if style == WISP else 0.5, pitch)
						stats["blips"] += 1
				if int(s["pause"]) > 0:
					s["shown"] = float(i + 1)
					break
	return s

## is the bubble under this key still typing? (tests)
func typing(key: String) -> bool:
	return st.has(key) and float(st[key]["shown"]) < float(String(st[key]["text"]).length())

## a bubble on `ci` pointing down at `head` (game pixels on its canvas)
func draw(ci: CanvasItem, head: Vector2, text: String, alpha: float, key: String, style: int = SPEECH, wpos = null, pitch := 1.0) -> void:
	if text == "" or alpha <= 0.01:
		return
	text = game.keys_in(text)              # (the keys as you've bound them: settings, 27 Nov)
	if key == "":
		key = "t:" + text
	var s := _tick(key, text, style, wpos, pitch, alpha)
	var px: float = float(game.scale_px)
	var f: Font = PixelFont.make()
	var u: int = game.ui.U
	var sz := PixelFont.SIZE * u
	var maxw := 150.0 * u
	# the whole text is laid out first, so the box never changes size while it types
	var lines := []
	var cur := ""
	for word in text.split(" "):
		var tryl: String = word if cur == "" else cur + " " + word
		if f.get_string_size(tryl, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > maxw and cur != "":
			lines.append(cur)
			cur = word
		else:
			cur = tryl
	if cur != "":
		lines.append(cur)
	var wmax := 0.0
	for ln in lines:
		wmax = maxf(wmax, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x)
	var lh := float(sz + u)
	var padx := 4.0                 # (game pixels: room round the words)
	var pady := 3.0
	var bw := ceilf(wmax / px + padx * 2.0)
	var bh := ceilf((lh * lines.size() - u) / px + pady * 2.0)
	# the pop: the box grows out of the tail, overshoots a touch, settles
	var age := int(s["age"])
	var k := clampf(float(age) / float(POP), 0.0, 1.0)
	var grow := 1.0 - pow(1.0 - k, 3.0) + sin(k * PI) * 0.12
	var bob := 0.0
	if style == WISP:
		bob = roundf(sin(float(Engine.get_process_frames()) * 0.07) * 0.6)
	var tail_h := 3.0
	var full_x0 := clampf(roundf(head.x - bw * 0.5), 2.0, float(game.VW) - bw - 2.0)
	var full_y0 := roundf(head.y - bh - tail_h - 1.0 + bob)
	var w := maxf(4.0, roundf(bw * grow))
	var h := maxf(3.0, roundf(bh * grow))
	var cx := clampf(head.x, full_x0 + 3.0, full_x0 + bw - 3.0)
	var x0 := roundf(lerpf(cx, full_x0 + bw * 0.5, minf(1.0, grow)) - w * 0.5)
	x0 = clampf(x0, 1.0, float(game.VW) - w - 1.0)
	var y0 := roundf(full_y0 + bh - h)
	if k >= 1.0:
		x0 = full_x0
		y0 = full_y0
		w = bw
		h = bh
	var a := alpha * clampf(k * 2.0, 0.0, 1.0)
	var fill: Color
	var edge: Color
	var ink: Color
	var accent: Color
	var shine: Color
	match style:
		WISP:
			fill = Color(0.09, 0.11, 0.24, 0.94)
			edge = Color(0.55, 0.86, 1.0)
			ink = Color(0.88, 0.95, 1.0)
			accent = Color(0.62, 0.9, 1.0)
			shine = Color(0.4, 0.6, 1.0, 0.35)
		EMBER:
			fill = Color(0.07, 0.04, 0.04, 0.95)
			edge = Color(1.0, 0.45, 0.16)
			ink = Color(1.0, 0.86, 0.7)
			accent = Color(1.0, 0.6, 0.25)
			shine = Color(0.9, 0.3, 0.1, 0.3)
		PROMPT:
			fill = Color(0.07, 0.05, 0.13, 0.9)
			edge = Color(0.93, 0.76, 0.36)
			ink = Color(0.97, 0.92, 0.8)
			accent = Color(1.0, 0.82, 0.32)
			shine = Color(0.5, 0.42, 0.75, 0.3)
		_:
			fill = Color(0.98, 0.95, 0.86, 0.96)
			edge = Color(0.22, 0.15, 0.1)
			ink = Color(0.18, 0.12, 0.08)
			accent = Color(0.62, 0.28, 0.12)
			shine = Color(1.0, 1.0, 1.0, 0.55)
	fill.a *= a
	edge.a *= a
	shine.a *= a
	# shadow, a WISP's glow, the box with cut corners and a one-pixel edge, a shine along the top
	var shadow := Color(0.0, 0.0, 0.0, 0.28 * a)
	_rounded(ci, Rect2(x0 + 1.0, y0 + 1.0, w, h), shadow)
	if style == WISP:
		_rounded(ci, Rect2(x0 - 1.0, y0 - 1.0, w + 2.0, h + 2.0), Color(0.45, 0.75, 1.0, 0.22 * a))
	_rounded(ci, Rect2(x0, y0, w, h), edge)
	_rounded(ci, Rect2(x0 + 1.0, y0 + 1.0, w - 2.0, h - 2.0), fill)
	if w > 6.0:
		ci.draw_rect(Rect2(x0 + 2.0, y0 + 1.0, w - 4.0, 1.0), shine)
	# the tail: a little stepped point, edged, from the box's foot toward the speaker
	var tx := clampf(roundf(head.x), x0 + 3.0, x0 + w - 4.0)
	var ty := y0 + h - 1.0
	for r in int(tail_h):
		var half := float(int(tail_h) - 1 - r)
		ci.draw_rect(Rect2(tx - half - 1.0, ty + float(r), half * 2.0 + 3.0, 1.0), edge)
		if half > 0.0 or r == 0:
			ci.draw_rect(Rect2(tx - half, ty + float(r), half * 2.0 + 1.0, 1.0), fill)
	ci.draw_rect(Rect2(tx, ty + tail_h, 1.0, 1.0), edge)
	if style == WISP and k >= 1.0:
		# (twinkles at the corners)
		var tw := Engine.get_process_frames()
		for c in 2:
			var ph := fposmod(float(tw) * 0.05 + float(c) * 0.5, 1.0)
			if ph < 0.35:
				var sp := Vector2(x0 - 1.0, y0 - 1.0) if c == 0 else Vector2(x0 + w, y0 + h - 2.0)
				var ta := sin(ph / 0.35 * PI) * a
				ci.draw_rect(Rect2(sp, Vector2.ONE), Color(1, 1, 1, ta))
				ci.draw_rect(Rect2(sp - Vector2(1, 0), Vector2(3, 1)), Color(0.6, 0.9, 1.0, ta * 0.5))
				ci.draw_rect(Rect2(sp - Vector2(0, 1), Vector2(1, 3)), Color(0.6, 0.9, 1.0, ta * 0.5))
	if age < TYPE_AT or k < 0.6:
		return
	# the words, as far as they're typed; [keys] in the accent
	var shown := int(s["shown"])
	var ta2 := alpha
	ci.draw_set_transform(Vector2(full_x0 + padx, full_y0 + pady), 0.0, Vector2.ONE / px)
	var used := 0
	for li in lines.size():
		var ln: String = lines[li]
		var x := 0.0
		var y := float(PixelFont.ASCENT * u) + li * lh
		var words := ln.split(" ")
		for wi in words.size():
			var word: String = words[wi] + (" " if wi < words.size() - 1 else "")
			var left := shown - used
			if left <= 0:
				break
			var part := word.substr(0, mini(left, word.length()))
			var col := accent if word.begins_with("[") else ink
			col.a *= ta2
			ci.draw_string(f, Vector2(x, y), part, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
			x += f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
			used += word.length()
		used += 1          # (the space the line broke at)
		if used >= shown:
			break
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## a box with its corner pixels cut
func _rounded(ci: CanvasItem, r: Rect2, c: Color) -> void:
	if r.size.x < 3.0 or r.size.y < 3.0:
		ci.draw_rect(r, c)
		return
	ci.draw_rect(Rect2(r.position.x + 1.0, r.position.y, r.size.x - 2.0, r.size.y), c)
	ci.draw_rect(Rect2(r.position.x, r.position.y + 1.0, 1.0, r.size.y - 2.0), c)
	ci.draw_rect(Rect2(r.position.x + r.size.x - 1.0, r.position.y + 1.0, 1.0, r.size.y - 2.0), c)
