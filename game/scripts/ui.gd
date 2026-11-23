extends CanvasLayer
## HUD, satchel, spell bar, toasts, the Wisp Forge, shops, the map's banner, settings, title / death /
## loading screens.
##
## A pixel-art UI (user, 21 Nov): everything is laid out in UI pixels, and the whole UI is drawn at a whole
## number of screen pixels each (`U`, from the screen's height: 2 at 1080p and 1440p, 4 at 2160p), so frames,
## icons and text all share one pixel grid. Text is the game's own bitmap font (pixel_font.gd: regular for
## text and buttons, bold for headings) at a whole multiple of its size (`fsize`). Frames are small 9-slice
## pixel textures made in code (dark ink outline, a trim, a darker inner trim, studs at the corners); icons
## come from icons.gd (every material, spell and item). Sizes in this file are UI pixels.

const TitleScreen := preload("res://scripts/title_screen.gd")
const Build := preload("res://scripts/build.gd")
const PixelFont := preload("res://scripts/pixel_font.gd")
const Galaxy := preload("res://scripts/galaxy.gd")
const Icons := preload("res://scripts/icons.gd")

var _book_head: Control = null   # the recipe book's heading in the forge (J scrolls there)
var game
var root: Control
var U := 2                    # screen pixels per UI pixel
var font: FontFile
var font_b: FontFile
var hud: Control
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var br_bar: ProgressBar
var br_row: Control
var hp_lbl: Label
var mp_lbl: Label
var info: Label
var hotbar: HBoxContainer
var hot_name: Label            # the chosen spell's name and cost, over the spell bar
var _hot_slots := []           # the slots' controls (their cooldown shading is drawn each frame)
var build_bar: PanelContainer      # build mode: categories, pieces and what the chosen one costs
var build_box: VBoxContainer
var _build_key := ""
var satchel: GridContainer
var satchel_panel: PanelContainer
var satchel_open := false          # (I or Tab) the whole satchel; closed, a pouch
var pouch: HBoxContainer
var pouch_hint: Label
var _satchel_full := []            # the open satchel's parts (hidden while it's a pouch)
var mp_glow: Control
var _satchel_scroll: ScrollContainer
var death_txt: Label
var _to_title_btn: Button
var toasts: VBoxContainer
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_lbl: Label
var dig_warn: Label
var forge: PanelContainer
var forge_tabs: HFlowContainer
var _forge_cols := 3
var _forge_scroll: ScrollContainer
var map_bar: PanelContainer
var map_title: Label
var map_hint: Label
var forge_list: VBoxContainer
var shop: PanelContainer         # a village keeper's shop (towns.gd)
var shop_list: VBoxContainer
var shop_buys: VBoxContainer
var shop_title: Label
var shop_coins: Label
var _shop_v = null
var station: PanelContainer      # a workshop station's panel (workshops.gd)
var _st = null                   # the station shown
var _st_key := ""                # what the panel was last drawn from (redrawn when it changes)
var _st_title: Label
var _st_body: VBoxContainer
var _st_status: Label
var _st_heat: ProgressBar
var _st_prog: ProgressBar
var _st_fuel: Label
var title
var death: Control
var loading: Control
var loading_lbl: Label
var settings_panel: Control
var _opt_btns := []       # [button, key, value]
var _hot_key := ""
var _inv_key := ""
var _toast_items: Array = []
var _frames := {}         # cached frame styles
var _loading_base := ""
var _t := 0.0

## (user, 22 Nov: "the ui for everything needs a re-work again"; chose arcane and decluttered: a
## spellbook look, runed frames with a mana-blue inner line and gem corners, gold for what you choose)
const GOLD := Color(1, 0.84, 0.36)
const CREAM := Color(0.98, 0.94, 0.82)
const DIM := Color(0.6, 0.62, 0.8)
const TEXT := Color(0.88, 0.9, 1)
const PANEL_BG := Color(0.045, 0.04, 0.1, 0.93)
const TRIM := Color(0.56, 0.48, 0.88)          # astral violet
const TRIM_DIM := Color(0.3, 0.27, 0.5)
const OUTLINE := Color(0.02, 0.015, 0.05)
const MANA := Color(0.45, 0.85, 1.0)           # the inner line, gems, the mana bar's glow
const GOOD := Color(0.6, 0.95, 0.55)
const BAD := Color(0.98, 0.55, 0.5)

func _ready() -> void:
	layer = 10
	font = PixelFont.make()
	font_b = PixelFont.make(true)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.theme = _make_theme()
	add_child(root)
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	_build_hud()
	_build_forge()
	_build_shop()
	_build_station()
	_build_map_bar()
	_build_screens()

## the UI's pixel size from the screen, and the root sized to the screen in UI pixels
func _relayout() -> void:
	var vs := get_viewport().get_visible_rect().size
	U = maxi(1, int(floor(vs.y / 540.0)))
	root.scale = Vector2(U, U)
	root.position = Vector2.ZERO
	root.size = (vs / float(U)).ceil()
	# tooltips pop up outside the scaled root: their frame and text are scaled to match
	var th: Theme = root.theme
	th.set_stylebox("panel", "TooltipPanel", _frame(Color(0.06, 0.05, 0.11, 0.97), TRIM, 4, -1, U))
	th.set_font_size("font_size", "TooltipLabel", PixelFont.SIZE * U)
	th.set_constant("shadow_offset_x", "TooltipLabel", U)
	th.set_constant("shadow_offset_y", "TooltipLabel", U)

func _process(delta: float) -> void:
	_t += delta
	if loading and loading.visible:
		loading_lbl.text = _loading_base + ".".repeat(int(_t * 3.0) % 4)

## a font size for a size asked for in the old design sizes: the pixel font at 1x, 2x or 3x
static func fsize(size: int) -> int:
	return PixelFont.SIZE * (1 if size < 19 else (2 if size < 28 else 3))

# ---------------------------------------------------------------- style --
## A pixel frame as a 9-slice. Panels (pad 4 and up) are runed: an ink outline, the trim, a dark gap, a
## faint mana-blue inner line, and a cut gem in each corner; small frames (slots) are plainer: ink, trim,
## a glint at each corner. `pad`: the content's margin (UI pixels).
func _frame(bg: Color, trim: Color, pad := 4, pad_x := -1, k := 1) -> StyleBoxTexture:
	if pad_x < 0:
		pad_x = pad
	var key := "%s|%s|%d|%d|%d" % [bg.to_html(), trim.to_html(), pad, pad_x, k]
	if _frames.has(key):
		return _frames[key]
	var ornate := pad >= 4
	var n := 24 if ornate else 8
	var mg := 6 if ornate else 3
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var gap := bg.darkened(0.35)
	var line := Color(MANA.r, MANA.g, MANA.b, 0.42 * bg.a)
	var gem_lit := trim.lightened(0.6)
	for y in n:
		for x in n:
			var ring := mini(mini(x, y), mini(n - 1 - x, n - 1 - y))
			var corner := (x == 0 or x == n - 1) and (y == 0 or y == n - 1)
			var c := bg
			if corner:
				c = Color(0, 0, 0, 0)
			elif ring == 0:
				c = OUTLINE
			elif ring == 1:
				c = trim
			elif ornate and ring == 2:
				c = gap
			elif ornate and ring == 3:
				c = line
			elif not ornate and ring == 2:
				c = trim.darkened(0.6)
			if ornate:
				# a gem in each corner: a diamond of trim round a mana-blue heart with a white glint
				var cx := 2 if x < n / 2 else n - 3
				var cy := 2 if y < n / 2 else n - 3
				var dd := absi(x - cx) + absi(y - cy)
				if dd <= 2:
					c = OUTLINE if dd == 2 else (gem_lit if dd == 1 else MANA)
					if dd == 0:
						c = Color(0.9, 1, 1)
			elif (x == 1 or x == n - 2) and (y == 1 or y == n - 2):
				c = trim.lightened(0.55)
			# inside a runed panel, a faint field of stars (the middle tiles, so it never stretches)
			if ornate and ring >= mg and c == bg:
				var u := (x - mg) % 12
				var v := (y - mg) % 12
				if (u == 2 and v == 3) or (u == 8 and v == 9) or (u == 9 and v == 2):
					c = Color(bg.lightened(0.16), bg.a)
				elif u == 5 and v == 7:
					c = Color(bg.lerp(MANA, 0.12), bg.a)
			img.set_pixel(x, y, c)
	if k > 1:
		img.resize(n * k, n * k, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(mg * k)
	if ornate:
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	sb.content_margin_left = pad_x * k
	sb.content_margin_right = pad_x * k
	sb.content_margin_top = pad * k
	sb.content_margin_bottom = pad * k
	_frames[key] = sb
	return sb

func _panel(bg := PANEL_BG, trim := TRIM, pad := 5) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(bg, trim, pad))
	return p

## Kept for callers that want a plain frame style.
func _panel_style(bg: Color, border: Color) -> StyleBox:
	return _frame(bg, border, 3)

## A bar's fill: a light top row, the colour, a shade, a dark bottom row (a glass tube, in pixels)
func _fill(col: Color) -> StyleBoxTexture:
	var img := Image.create(1, 5, false, Image.FORMAT_RGBA8)
	var rows := [col.lightened(0.5), col.lightened(0.15), col, col.darkened(0.2), col.darkened(0.45)]
	for y in 5:
		img.set_pixel(0, y, rows[y])
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_top = 1
	sb.texture_margin_bottom = 1
	return sb

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = PixelFont.SIZE
	var grab := StyleBoxFlat.new()
	grab.bg_color = TRIM
	grab.content_margin_left = 2
	grab.content_margin_right = 1
	var grab_h: StyleBoxFlat = grab.duplicate()
	grab_h.bg_color = GOLD
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.03, 0.02, 0.06, 0.6)
	track.content_margin_left = 2
	track.content_margin_right = 1
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	th.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	th.set_stylebox("scroll", "VScrollBar", track)
	th.set_stylebox("panel", "TooltipPanel", _frame(Color(0.06, 0.05, 0.11, 0.97), TRIM, 4))
	th.set_color("font_color", "TooltipLabel", TEXT)
	th.set_font("font", "TooltipLabel", font)
	th.set_font_size("font_size", "TooltipLabel", PixelFont.SIZE)
	th.set_color("font_shadow_color", "TooltipLabel", OUTLINE)
	th.set_constant("shadow_offset_x", "TooltipLabel", 1)
	th.set_constant("shadow_offset_y", "TooltipLabel", 1)
	return th

## an icon (icons.gd ITEM_ART) at `zoom` UI pixels per art pixel; `col` is kept for older callers
func _icon(key: String, _col := Color.WHITE, zoom := 1) -> TextureRect:
	return _tex(Icons.item(key), zoom)

func _tex(t: Texture2D, zoom := 1) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = t
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = t.get_size() * zoom
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

# ------------------------------------------------------------- builders --
func _bar(col: Color, h := 9) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(100, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.025, 0.06)
	bg.border_color = OUTLINE
	bg.set_border_width_all(1)
	bg.set_content_margin_all(1)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", _fill(col))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# a notch every tenth, so it reads as a pixel gauge
	var notches := Control.new()
	notches.set_anchors_preset(Control.PRESET_FULL_RECT)
	notches.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notches.draw.connect(func():
		var w := notches.size.x - 2.0
		for k in range(1, 10):
			var x := floorf(1.0 + w * k / 10.0)
			notches.draw_rect(Rect2(x, notches.size.y - 3.0, 1, 2), Color(0, 0, 0, 0.35)))
	b.add_child(notches)
	return b

## text in the pixel font (sizes from the old design: under 19 is 1x, under 28 2x, else 3x), with a
## one-pixel shadow
func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize(size))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(OUTLINE, 0.95))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("line_spacing", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A heading: its shadow violet; the bold face only at 2x and up (at 1x it read too heavy)
func _head(txt: String, size: int, col := CREAM) -> Label:
	var l := _label(txt, size, col)
	if fsize(size) > PixelFont.SIZE:
		l.add_theme_font_override("font", font_b)
	l.add_theme_color_override("font_shadow_color", Color(0.22, 0.1, 0.36, 1))
	return l

## A divider: a gold rule with a diamond in the middle
func _rule(w := 130) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 5)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var mid := (c.size * 0.5).floor()
		c.draw_rect(Rect2(0, mid.y, c.size.x, 1), Color(TRIM, 0.7))
		c.draw_rect(Rect2(mid.x - 2, mid.y - 1, 5, 3), GOLD)
		c.draw_rect(Rect2(mid.x - 1, mid.y - 2, 3, 5), GOLD)
		c.draw_rect(Rect2(mid.x, mid.y, 1, 1), Color(1, 0.97, 0.8)))
	return c

func _button(txt: String, big := false) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var py := 5 if big else 3
	var px := 10 if big else 5
	b.add_theme_stylebox_override("normal", _frame(Color(0.11, 0.08, 0.18, 0.95), TRIM, py, px))
	b.add_theme_stylebox_override("hover", _frame(Color(0.24, 0.17, 0.36, 0.97), GOLD, py, px))
	b.add_theme_stylebox_override("pressed", _frame(Color(0.07, 0.05, 0.12, 0.97), GOLD, py + 1, px))
	b.add_theme_stylebox_override("disabled", _frame(Color(0.07, 0.07, 0.1, 0.9), Color(0.3, 0.3, 0.36), py, px))
	b.add_theme_font_override("font", font)      # (the regular face: the bold one read too heavy on buttons)
	b.add_theme_font_size_override("font_size", PixelFont.SIZE)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 0.98, 0.88))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.52))
	if big:
		b.custom_minimum_size = Vector2(150, 0)
	b.mouse_entered.connect(func():
		if not b.disabled:
			_sfx("ui_hover"))
	b.pressed.connect(func(): _sfx("ui_click"))
	return b

## Shows a settings option as chosen (filled gold) or not.
func _set_chosen(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", _frame(Color(0.5, 0.36, 0.1, 0.97), Color(1, 0.88, 0.5), 3, 5))
		b.add_theme_stylebox_override("hover", _frame(Color(0.58, 0.42, 0.14, 0.97), Color(1, 0.94, 0.66), 3, 5))
		b.add_theme_color_override("font_color", Color(1, 0.98, 0.9))
	else:
		b.add_theme_stylebox_override("normal", _frame(Color(0.11, 0.08, 0.18, 0.95), TRIM_DIM, 3, 5))
		b.add_theme_stylebox_override("hover", _frame(Color(0.24, 0.17, 0.36, 0.97), GOLD, 3, 5))
		b.add_theme_color_override("font_color", Color(0.72, 0.7, 0.84))

func _sfx(n: String) -> void:
	if game != null and game.get("audio") != null:
		game.audio.play(n)

func _box(vertical: bool, sep: int) -> BoxContainer:
	var b: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

## an inventory slot: a small frame with an icon at 2x and a count in the corner
func _slot(t: Texture2D, count: String, chosen: bool, tip: String) -> PanelContainer:
	var p := PanelContainer.new()
	var normal := _frame(Color(0.2, 0.14, 0.05, 0.95) if chosen else Color(0.07, 0.055, 0.12, 0.9), GOLD if chosen else TRIM_DIM, 1)
	var hover := _frame(Color(0.24, 0.17, 0.34, 0.95), GOLD, 1)
	p.add_theme_stylebox_override("panel", normal)
	p.mouse_entered.connect(_set_panel_style.bind(p, hover))
	p.mouse_exited.connect(_set_panel_style.bind(p, normal))
	p.custom_minimum_size = Vector2(26, 26)
	p.tooltip_text = tip
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ic := _tex(t, 2)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.add_child(ic)
	if count != "":
		var cl := _label(count, 12, Color(1, 1, 1))
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		cl.size_flags_horizontal = Control.SIZE_SHRINK_END
		cl.size_flags_vertical = Control.SIZE_SHRINK_END
		p.add_child(cl)
	return p

static func _count(n: int) -> String:
	if n >= 10000:
		return "%dk" % (n / 1000)
	if n >= 1000:
		return "%.1fk" % (n / 1000.0)
	return str(n)

## a cost: the material's icon and "have/need", green when there's enough
func _cost_chip(m: int, need: int) -> Control:
	var have: int = game.inv[m]
	var row := _box(false, 2)
	row.tooltip_text = Defs.NAMES[m]
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_tex(Icons.mat(m)))
	row.add_child(_label("%s/%d" % [_count(have), need], 12, GOOD if have >= need else BAD))
	return row

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	# the character plate: health, mana, breath and where you are
	var plate := _panel(Color(0.045, 0.04, 0.1, 0.82), TRIM, 4)
	plate.position = Vector2(5, 4)
	plate.custom_minimum_size = Vector2(130, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(plate)
	var bars := _box(true, 2)
	plate.add_child(bars)
	hp_bar = _bar(Color(0.86, 0.2, 0.26), 9)
	mp_bar = _bar(Color(0.3, 0.6, 1.0), 9)
	br_bar = _bar(Color(0.5, 0.85, 0.92), 5)
	hp_lbl = _label("", 12, Color.WHITE)
	mp_lbl = _label("", 12, Color.WHITE)
	hp_bar.add_child(hp_lbl)
	mp_bar.add_child(mp_lbl)
	# the numbers sit in the middle of their bar
	for l in [hp_lbl, mp_lbl]:
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.offset_top = 1
	for pair in [["heart", hp_bar], ["drop", mp_bar], ["bubble", br_bar]]:
		var row := _box(false, 3)
		var ic := _icon(pair[0])
		ic.custom_minimum_size.x = 11
		row.add_child(ic)
		row.add_child(pair[1])
		bars.add_child(row)
		if pair[0] == "bubble":
			br_row = row
	bars.add_child(_rule(120))
	info = _label("", 12, Color(0.86, 0.87, 1))
	bars.add_child(info)
	# the mana bar shines while mana goes on shaping the world (digging, taking away, building)
	mp_glow = Control.new()
	mp_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_glow.draw.connect(func():
		var gk: float = clampf(float(game.player.mana_spent_t) / 20.0, 0.0, 1.0) if game != null and game.player != null else 0.0
		if gk > 0.0:
			var a := 0.35 + 0.25 * sin(_t * 18.0)
			mp_glow.draw_rect(Rect2(Vector2(-1, -1), mp_glow.size + Vector2(2, 2)), Color(MANA.r, MANA.g, MANA.b, a * gk), false, 1.0)
		if game != null and game.player != null and game.player.mana < 1.0:
			mp_glow.draw_rect(Rect2(Vector2.ZERO, mp_glow.size), Color(0.6, 0.1, 0.2, 0.3 + 0.15 * sin(_t * 6.0))))
	mp_bar.add_child(mp_glow)

	# the spell bar: a slot per spell (its glyph, its number, the cooldown shading it), the chosen one's
	# name and cost over it
	var hb := _box(true, 1)
	hb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hb.position.y -= 5
	hb.alignment = BoxContainer.ALIGNMENT_END
	hud.add_child(hb)
	hot_name = _head("", 12, CREAM)
	hot_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(hot_name)
	var hpan := _panel(Color(0.045, 0.04, 0.1, 0.78), TRIM, 4)
	hpan.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hpan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(hpan)
	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 2)
	hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	hpan.add_child(hotbar)

	build_bar = _panel(Color(0.05, 0.04, 0.09, 0.9), TRIM, 4)
	build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_bar.position.y -= 5
	build_bar.visible = false
	hud.add_child(build_bar)
	build_box = _box(true, 2)
	build_bar.add_child(build_box)

	# the satchel: a grid of slots
	var sw := _panel(Color(0.05, 0.04, 0.09, 0.86), TRIM, 4)
	sw.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sw.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sw.position = Vector2(-5, 4)
	hud.add_child(sw)
	satchel_panel = sw
	var sv := _box(true, 2)
	sv.mouse_filter = Control.MOUSE_FILTER_PASS
	sw.add_child(sv)
	var sh := _head("Satchel", 12)
	sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(sh)
	var srule := _rule(136)
	sv.add_child(srule)
	_satchel_full = [sh, srule]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(140, 0)
	sv.add_child(scroll)
	_satchel_scroll = scroll
	satchel = GridContainer.new()
	satchel.columns = 5
	satchel.add_theme_constant_override("h_separation", 1)
	satchel.add_theme_constant_override("v_separation", 1)
	scroll.add_child(satchel)
	_satchel_full.append(scroll)
	# closed (the usual), the satchel is a pouch: what Conjure places, your draughts and coins
	pouch = _box(false, 3)
	pouch.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(pouch)
	pouch_hint = _label("I  satchel", 11, DIM)

	# what's just happened: a few short notes at the left, above the bottom, out of the way of play
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	toasts.position = Vector2(5, -8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.add_theme_constant_override("separation", 1)
	root.add_child(toasts)

	boss_box = _box(true, 0)
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_box.position.y = 70
	boss_box.visible = false
	hud.add_child(boss_box)
	var bp := _panel(Color(0.08, 0.03, 0.04, 0.85), Color(0.85, 0.42, 0.2), 4)
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_child(bp)
	var bv := _box(true, 2)
	bp.add_child(bv)
	var bh := _box(false, 4)
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(bh)
	bh.add_child(_icon("skull"))
	boss_lbl = _head("Vulkhar, the Ember Golem", 12, Color(1, 0.72, 0.36))
	bh.add_child(boss_lbl)
	bh.add_child(_icon("skull"))
	boss_bar = _bar(Color(1, 0.5, 0.18), 7)
	boss_bar.custom_minimum_size = Vector2(220, 7)
	bv.add_child(boss_bar)

	dig_warn = _label("Too hard for your staff. Forge a stronger focus (C)", 13, Color(1, 0.72, 0.62))
	dig_warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dig_warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dig_warn.position.y -= 56
	dig_warn.visible = false
	hud.add_child(dig_warn)


func _build_forge() -> void:
	forge = _panel(Color(0.05, 0.04, 0.09, 0.97), TRIM, 7)
	forge.set_anchors_preset(Control.PRESET_CENTER)
	forge.custom_minimum_size = Vector2(470, 316)
	forge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	forge.grow_vertical = Control.GROW_DIRECTION_BOTH
	forge.visible = false
	root.add_child(forge)
	var v := _box(true, 4)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	forge.add_child(v)
	var head := _box(false, 4)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(head)
	head.add_child(_tex(Icons.spell("conjure"), 2))
	var tv := _box(true, 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	tv.add_child(_head("The Wisp Forge", 24, CREAM))
	tv.add_child(_label("Gather from the world, then bind it here into spells, foci, gear and relics.", 12, DIM))
	var close := _button("Close  [C]")
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): game.toggle_forge())
	head.add_child(close)
	# a tab per kind of recipe: jumps the list there
	forge_tabs = HFlowContainer.new()
	forge_tabs.add_theme_constant_override("h_separation", 2)
	forge_tabs.add_theme_constant_override("v_separation", 2)
	v.add_child(forge_tabs)
	var r := _rule(456)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_forge_scroll = scroll
	forge_list = VBoxContainer.new()
	forge_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_list.add_theme_constant_override("separation", 3)
	scroll.add_child(forge_list)

## A village keeper's shop: what they sell (for coins) on the left, what they'll buy on the right, by
## their trade (towns.gd `shop_def`); towns.gd does the trading.
func _build_shop() -> void:
	shop = _panel(Color(0.05, 0.04, 0.09, 0.97), TRIM, 7)
	shop.set_anchors_preset(Control.PRESET_CENTER)
	shop.custom_minimum_size = Vector2(420, 280)
	shop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	shop.grow_vertical = Control.GROW_DIRECTION_BOTH
	shop.visible = false
	root.add_child(shop)
	var v := _box(true, 4)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	shop.add_child(v)
	var head := _box(false, 4)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(head)
	shop_title = _head("Shop", 12, CREAM)
	shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(shop_title)
	var coin_row := _box(false, 2)
	coin_row.add_child(_icon("coin"))
	shop_coins = _label("", 12, GOLD)
	coin_row.add_child(shop_coins)
	head.add_child(coin_row)
	var close := _button("Leave  [F]")
	close.pressed.connect(func(): game.towns.close_shop())
	head.add_child(close)
	var r := _rule(400)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	var cols := _box(false, 8)
	cols.mouse_filter = Control.MOUSE_FILTER_PASS
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	for side in 2:
		var sv := _box(true, 2)
		sv.mouse_filter = Control.MOUSE_FILTER_PASS
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(sv)
		sv.add_child(_head("For sale" if side == 0 else "They'll buy", 12, Color(0.95, 0.8, 0.5)))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sv.add_child(scroll)
		var lst := VBoxContainer.new()
		lst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lst.add_theme_constant_override("separation", 2)
		scroll.add_child(lst)
		if side == 0:
			shop_list = lst
		else:
			shop_buys = lst

func show_shop(vk) -> void:
	_shop_v = vk
	_render_shop()
	shop.visible = true

func hide_shop() -> void:
	shop.visible = false
	_shop_v = null

## an icon for a thing a shop sells (from what it gives)
func _sale_icon(it: Dictionary) -> Texture2D:
	if it.has("give"):
		for m in it["give"]:
			return Icons.mat(int(m))
	if it.has("potion"):
		return Icons.item("potion")
	if it.has("spell"):
		return Icons.spell(String(it["spell"]))
	if it.has("chart"):
		return Icons.item("letter")
	if it.has("recipe"):
		return Icons.thing("recipe")
	if it.has("heat_ward"):
		return Icons.thing("heat_ward")
	if it.has("item"):
		var own: Texture2D = Icons.thing(String(it["item"]))
		return own if own != null else Icons.mat(Defs.CRYSTAL)
	if it.has("meal") or it.has("rest"):
		return Icons.item("heart")
	return Icons.item("coin")

func _render_shop() -> void:
	if _shop_v == null:
		return
	var tw = game.towns
	var sd: Dictionary = tw.shop_def(_shop_v)
	shop_title.text = "%s's %s · %s" % [_shop_v.name, sd.get("title", "Shop"), _shop_v.town["name"]]
	shop_coins.text = "%d" % tw.coins()
	for c in shop_list.get_children():
		c.queue_free()
	for c2 in shop_buys.get_children():
		c2.queue_free()
	var sell: Array = sd.get("sell", [])
	for i in sell.size():
		var it: Dictionary = sell[i]
		var row := _box(false, 3)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(_tex(_sale_icon(it)))
		var l := _label(String(it["name"]), 12, CREAM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.custom_minimum_size.x = 100
		row.add_child(l)
		var have_it: bool = tw.owned(it)
		var price: int = tw.price_of(_shop_v, it)
		var ptxt := "%d" % price if price >= int(it["price"]) else "%d (%d)" % [price, int(it["price"])]
		row.add_child(_label("yours" if have_it else ptxt, 12, DIM if have_it else GOLD))
		var b := _button("Buy")
		b.disabled = have_it or tw.coins() < price
		b.pressed.connect(func():
			tw.buy(_shop_v, i)
			_render_shop())
		row.add_child(b)
		shop_list.add_child(row)
	for bb in tw.buys(_shop_v):
		var mat: int = bb[0]
		var have: int = game.inv[mat]
		if mat >= Defs.FIREOPAL and have <= 0 and mat != Defs.kind_ore(game.planet):
			continue                              # (a far world's ore: only shown once you have some)
		var row2 := _box(false, 3)
		row2.mouse_filter = Control.MOUSE_FILTER_PASS
		row2.add_child(_tex(Icons.mat(mat)))
		var l2 := _label("%d %s" % [int(bb[1]), Defs.NAMES[mat]], 12, CREAM if have >= int(bb[1]) else DIM)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l2.tooltip_text = "You have %d" % have
		l2.mouse_filter = Control.MOUSE_FILTER_PASS
		row2.add_child(l2)
		row2.add_child(_label("%d" % int(bb[2]), 12, GOLD))
		var b2 := _button("Sell")
		b2.disabled = have < int(bb[1])
		b2.pressed.connect(func():
			tw.sell(_shop_v, mat)
			_render_shop())
		row2.add_child(b2)
		shop_buys.add_child(row2)

## A workshop station's panel (workshops.gd): your satchel to load it from (left click one, right click
## ten), its fire to feed, what's in it (click to take it back out), what it made, and what it knows how to
## make, its secrets as riddles you've heard or question marks.
func _build_station() -> void:
	station = _panel(Color(0.05, 0.04, 0.09, 0.97), TRIM, 7)
	station.set_anchors_preset(Control.PRESET_CENTER)
	station.custom_minimum_size = Vector2(470, 300)
	station.grow_horizontal = Control.GROW_DIRECTION_BOTH
	station.grow_vertical = Control.GROW_DIRECTION_BOTH
	station.visible = false
	root.add_child(station)
	var v := _box(true, 4)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	station.add_child(v)
	var head := _box(false, 4)
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(head)
	_st_title = _head("Workshop", 12, CREAM)
	_st_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_st_title)
	var close := _button("Leave  [F]")
	close.pressed.connect(func(): game.workshops.close())
	head.add_child(close)
	var r := _rule(450)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	_st_status = _label("", 12, CREAM)
	_st_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_st_status.custom_minimum_size.x = 450
	v.add_child(_st_status)
	var bars := _box(false, 6)
	v.add_child(bars)
	bars.add_child(_label("Heat", 12, DIM))
	_st_heat = _bar(Color(1.0, 0.45, 0.15))
	bars.add_child(_st_heat)
	bars.add_child(_label("Batch", 12, DIM))
	_st_prog = _bar(GOLD)
	bars.add_child(_st_prog)
	_st_fuel = _label("", 12, DIM)
	bars.add_child(_st_fuel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 210
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_st_body = VBoxContainer.new()
	_st_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_st_body.add_theme_constant_override("separation", 3)
	scroll.add_child(_st_body)

func show_station(st) -> void:
	_st = st
	_st_key = ""
	update_station()
	station.visible = true

func hide_station() -> void:
	station.visible = false
	_st = null

## each frame the panel is open: the bars and the status; the rest is redrawn when what's in it changes
func update_station() -> void:
	if _st == null or not station.visible and game.state != "station":
		return
	var ws = game.workshops
	var st = _st
	var sd: Dictionary = Defs.STATIONS[st.kind]
	var pr: Dictionary = ws.match_process(st)
	_st_heat.value = st.heat * 100.0
	_st_prog.value = 0.0 if pr.is_empty() else clampf(st.prog / float(pr["ticks"]) * 100.0, 0.0, 100.0)
	var burn := float(sd["burn"])
	_st_fuel.text = "" if burn <= 0.0 else "Fuel: %d s" % int(st.fuel / burn / 60.0)
	_st_heat.visible = burn > 0.0
	_st_prog.visible = burn > 0.0
	var txt := ""
	if burn <= 0.0:
		txt = String(sd["desc"])
	elif not ws.loaded(st):
		txt = "Load something to work (click your satchel below), and feed the fire."
	elif pr.is_empty():
		txt = "It doesn't know what to make of this mix. (Every kind loaded must belong to one thing it makes.)"
	else:
		var known: bool = not pr.get("secret", false) or ws.is_secret_known(String(pr["id"]))
		var what := String(Defs.process_out(pr)[0]) if known else "something new..."
		match ws.waiting(st):
			"fuel": txt = "Ready to make %s: feed the fire." % what
			"night": txt = "It will make %s, but only after dark." % what
			"wet": txt = "The water's put its fire out."
			_:
				txt = ("Working: %s" % what) if st.heat > 0.95 else ("Warming up to make %s" % what)
	_st_status.text = txt
	var key := "%s|%s|%s|%s|%d" % [str(st.store), str(st.out), _inv_key_now(), st.cur, int(st.fuel > 0.0)]
	if key != _st_key:
		_st_key = key
		_render_station()

func _inv_key_now() -> String:
	var k := ""
	for m in Defs.NM:
		if game.player.inv[m] > 0:
			k += "%d:%d," % [m, game.player.inv[m]]
	return k

func _st_section(txt: String) -> void:
	_st_body.add_child(_head(txt, 12, Color(0.95, 0.8, 0.5)))

func _st_grid() -> GridContainer:
	var gr := GridContainer.new()
	gr.columns = 14
	gr.add_theme_constant_override("h_separation", 2)
	gr.add_theme_constant_override("v_separation", 2)
	_st_body.add_child(gr)
	return gr

func _out_name(key: String) -> String:
	if key.begins_with("m"):
		return Defs.NAMES[int(key.substr(1))]
	if key == "potion":
		return "Healing Draught"
	if Defs.DRAUGHTS.has(key):
		return String(Defs.DRAUGHTS[key]["name"])
	if key.begins_with("gear:"):
		return String(Defs.WORK_GEAR[key.substr(5)]["name"])
	return key

## an icon for a process's output
func _out_icon(key: String) -> Texture2D:
	if key.begins_with("m"):
		return Icons.mat(int(key.substr(1)))
	if key == "potion":
		return Icons.item("potion")
	if Defs.DRAUGHTS.has(key):
		return Icons.draught(key)
	var own: Texture2D = Icons.thing(key)
	return own if own != null else Icons.thing("recipe")

func _render_station() -> void:
	for c in _st_body.get_children():
		c.queue_free()
	var st = _st
	var ws = game.workshops
	var sd: Dictionary = Defs.STATIONS[st.kind]
	_st_title.text = String(sd["name"])
	var burn := float(sd["burn"])
	if burn <= 0.0:
		_st_section("At the anvil")
		var al := _label("Forge ore gear or alloys (C) while you stand within reach of this anvil and the piece comes out masterwork: each of its effects a quarter bigger.", 12, CREAM)
		al.autowrap_mode = TextServer.AUTOWRAP_WORD
		al.custom_minimum_size.x = 440
		_st_body.add_child(al)
		return
	# what it made
	if not st.out.is_empty():
		var orow := _box(false, 4)
		orow.add_child(_head("Made", 12, GOLD))
		for k in st.out:
			orow.add_child(_slot(_out_icon(String(k)), str(st.out[k]), true, _out_name(String(k))))
		var tb := _button("Take it all")
		tb.pressed.connect(func():
			ws.take_out(st)
			_st_key = "")
		orow.add_child(tb)
		_st_body.add_child(orow)
	# what's in it
	_st_section("Loaded (click to take back out)")
	var ing := _st_grid()
	if st.store.is_empty():
		ing.add_child(_label("nothing", 12, DIM))
	for m in st.store:
		var sl := _slot(Icons.mat(int(m)), _count(int(st.store[m])), false, "%s ×%d\nClick: take it back" % [Defs.NAMES[int(m)], int(st.store[m])])
		sl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				ws.unload(st, int(m))
				_st_key = "")
		ing.add_child(sl)
	# the fire
	_st_section("Feed the fire (left 1, right 5)")
	var fg := _st_grid()
	var any_fuel := false
	for fm in Defs.FUEL_TICKS:
		var have: int = game.player.inv[int(fm)]
		if have <= 0:
			continue
		any_fuel = true
		var fs := _slot(Icons.mat(int(fm)), _count(have), false, "%s: %d s of burning each" % [Defs.NAMES[int(fm)], int(float(Defs.FUEL_TICKS[fm]) / burn / 60.0)])
		fs.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				ws.add_fuel(st, int(fm), 5 if ev.button_index == MOUSE_BUTTON_RIGHT else 1)
				game.audio.play("fire", st.pos, 0.4)
				_st_key = "")
		fg.add_child(fs)
	if not any_fuel:
		fg.add_child(_label("no coal, wood or planks in your satchel", 12, DIM))
	# the satchel
	_st_section("Your satchel (left 1, right 10)")
	var sg := _st_grid()
	for m2 in Defs.NM:
		var n2: int = game.player.inv[m2]
		if n2 <= 0 or Defs.KIND[m2] == Defs.K_EMPTY:
			continue
		var ss := _slot(Icons.mat(m2), _count(n2), false, "%s ×%d\nLeft: load 1, right: load 10" % [Defs.NAMES[m2], n2])
		ss.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				ws.load_mat(st, m2, 10 if ev.button_index == MOUSE_BUTTON_RIGHT else 1)
				_st_key = "")
		sg.add_child(ss)
	# what it knows how to make
	_st_section("It makes")
	for pr in Defs.PROCESS:
		if pr["at"] != st.kind:
			continue
		var secret: bool = pr.get("secret", false)
		var found: bool = not secret or ws.is_secret_known(String(pr["id"]))
		var row := _box(false, 3)
		if found:
			for im in pr["in"]:
				row.add_child(_tex(Icons.mat(int(im))))
				row.add_child(_label("%d" % int(pr["in"][im]), 12, CREAM))
			row.add_child(_label("→", 12, DIM))
			var po: Array = Defs.process_out(pr)
			var ok_key: String = "m%d" % int((pr["give"] as Dictionary).keys()[0]) if pr.has("give") else String(pr["item"])
			if not ok_key.begins_with("gear:"):
				row.add_child(_tex(_out_icon(ok_key)))
			var ol := _label("%d %s%s%s" % [int(po[2]), po[0], "  (secret)" if secret else "", "  (after dark)" if pr.get("night", false) else ""], 12, Color(1, 0.8, 1) if secret else CREAM)
			row.add_child(ol)
		else:
			var heard: bool = game.items.has("hint_" + String(pr["id"]))
			var sl2 := _label("?  " + (String(pr["hint"]) if heard else "A secret, yet to be found. Try a mix..."), 12, Color(0.85, 0.7, 1.0) if heard else DIM)
			sl2.autowrap_mode = TextServer.AUTOWRAP_WORD
			sl2.custom_minimum_size.x = 430
			row.add_child(sl2)
		_st_body.add_child(row)

## A full-screen overlay with a framed panel in the middle; the panel's VBox is in meta "box".
func _screen(dim := Color(0.02, 0.015, 0.05, 0.86), trim := TRIM) -> Control:
	var c := ColorRect.new()
	c.color = dim
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(cc)
	var p := _panel(Color(0.05, 0.04, 0.09, 0.97), trim, 10)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	c.set_meta("box", v)
	return c

func _center(node: Control) -> Control:
	var cc := CenterContainer.new()
	cc.add_child(node)
	return cc

func _build_screens() -> void:
	title = TitleScreen.new()
	title.ui = self
	title.game = game
	root.add_child(title)

	death = _screen(Color(0.12, 0.01, 0.03, 0.72), Color(0.75, 0.3, 0.3))
	death.visible = false
	var dv: VBoxContainer = death.get_meta("box")
	var dl := _head("Your light fades…", 34, Color(1, 0.86, 0.7))
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(dl)
	dv.add_child(_center(_rule(160)))
	var ds := _label("The wisp carries you back to the surface. A quarter of your satchel is lost.", 14, Color(0.82, 0.76, 1))
	death_txt = ds
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(ds)
	var rb := _button("Rise again", true)
	rb.pressed.connect(func(): game.revive())
	dv.add_child(_center(rb))

	_build_settings()

	loading = _screen(Color(0.02, 0.015, 0.05, 0.55))
	loading.visible = false
	var lv: VBoxContainer = loading.get_meta("box")
	loading_lbl = _head("Forging a planet", 24, CREAM)
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	loading_lbl.custom_minimum_size = Vector2(230, 0)
	lv.add_child(loading_lbl)
	lv.add_child(_center(_rule(190)))
	var lh := _label("Every grain of the world is being laid down. This takes a moment.", 12, DIM)
	lh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(lh)

## Quality, dithering, pixel size, sound; the controls beside them. Opened from the title screen, or
## with Esc while playing.
func _build_settings() -> void:
	settings_panel = _screen()
	settings_panel.visible = false
	var sv: VBoxContainer = settings_panel.get_meta("box")
	sv.add_theme_constant_override("separation", 4)
	var head := _head("Settings", 24, CREAM)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(head)
	sv.add_child(_center(_rule(300)))
	var cols := _box(false, 14)
	cols.mouse_filter = Control.MOUSE_FILTER_PASS
	sv.add_child(cols)
	var left := _box(true, 4)
	left.mouse_filter = Control.MOUSE_FILTER_PASS
	cols.add_child(left)
	var rows := [
		["Quality", "quality", [["High", "high"], ["Medium", "medium"], ["Low", "low"]],
			"Low simulates and lights the world in fewer passes, with bigger pixels."],
		["Dithering", "dither", [["Off", "off"], ["Subtle", "subtle"], ["Retro", "retro"]],
			"Off draws clean colour bands like a SNES; Retro the old checkerboard."],
		["View", "view", [["World", "world"], ["Unrolled", "unrolled"]],
			"World shows the planet as it is; Unrolled lays the ground out flat."],
		["Window", "window", [["Windowed", "windowed"], ["Fullscreen", "fullscreen"], ["Exclusive", "exclusive"]],
			"F11 or Alt + Enter switches. Exclusive can run smoother."],
		["Pixel size", "pixel", [["Auto", 0], ["3", 3], ["4", 4], ["5", 5], ["6", 6]],
			"How big each world pixel is on screen."],
		["Music", "music", [["Off", 0], ["25%", 25], ["50%", 50], ["75%", 75], ["100%", 100]],
			"Music volume (tracks go in game/audio/music)."],
		["Sound", "sound", [["Off", 0], ["25%", 25], ["50%", 50], ["75%", 75], ["100%", 100]],
			"Sound effects volume."],
	]
	for row in rows:
		var box := _box(true, 1)
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		var h := _box(false, 2)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		var name_lbl := _head(row[0], 12, CREAM)
		name_lbl.custom_minimum_size = Vector2(56, 0)
		h.add_child(name_lbl)
		for opt in row[2]:
			var b := _button(opt[0])
			b.custom_minimum_size = Vector2(30, 0)
			b.pressed.connect(_on_option.bind(row[1], opt[1]))
			h.add_child(b)
			_opt_btns.append([b, row[1], opt[1]])
		box.add_child(h)
		var hint := _label(row[3], 11, DIM)
		box.add_child(hint)
		left.add_child(box)
	# the controls
	var right := _box(true, 2)
	cols.add_child(right)
	right.add_child(_head("Controls", 12, CREAM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	for pair in [["A / D", "Walk"], ["W / Space", "Jump; hold to levitate (once forged)"],
			["Left mouse", "Cast the chosen spell"], ["Right mouse", "Excavate: mana by how hard"],
			["Shift + right", "Take back walls, furniture"], ["F", "Talk, open, board; a bed: home; a workshop: load it"],
			["1-9 / wheel", "Choose a spell"], ["Q / E", "Choose what Conjure places"],
			["C", "The Wisp Forge"], ["J", "Recipe book"], ["I / Tab", "Open or close the satchel"], ["M", "Map (Tab: the galaxy)"],
			["H", "Drink a Healing Draught"], ["B", "Build mode (G: shapes)"],
			["K", "Call the skiff"], ["Shift", "Starsail (skiff, in space)"], ["Esc", "Settings"], ["F11", "Fullscreen"], ["F9", "Creative stock (developer)"]]:
		grid.add_child(_label(pair[0], 12, GOLD))
		grid.add_child(_label(pair[1], 12, TEXT))
	right.add_child(grid)
	var close := _button("Close", true)
	close.custom_minimum_size = Vector2(100, 0)
	close.pressed.connect(toggle_settings)
	# while playing: save everything and go back to the title, to pick another save slot
	_to_title_btn = _button("Save and return to title", true)
	_to_title_btn.custom_minimum_size = Vector2(100, 0)
	_to_title_btn.pressed.connect(func(): game.quit_to_title())
	var brow := _box(false, 6)
	brow.mouse_filter = Control.MOUSE_FILTER_PASS
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_child(_to_title_btn)
	brow.add_child(close)
	sv.add_child(brow)
	_refresh_settings()

func _on_option(key: String, value) -> void:
	game.set_setting(key, value)
	_refresh_settings()

func _refresh_settings() -> void:
	for it in _opt_btns:
		var b: Button = it[0]
		var on: bool = str(game.settings.get(it[1], "")) == str(it[2])
		_set_chosen(b, on)

func toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		_refresh_settings()
		_to_title_btn.visible = game.state == "play" or game.state == "forge" or game.state == "dead"

# --------------------------------------------------------------- screens --
func show_title(_has_save := true) -> void:
	title.visible = true
	title.set_menu_visible(true)
	title.refresh_slots()

func show_error(msg: String) -> void:
	title.visible = true
	title.show_message("Wisp Forge couldn't start the GPU simulation", msg)

func show_loading(txt: String) -> void:
	# the title scene keeps playing behind the loading panel
	title.visible = true
	title.set_menu_visible(false)
	_loading_base = txt.trim_suffix("…").trim_suffix("...")
	loading_lbl.text = _loading_base
	loading.visible = true

func hide_loading() -> void:
	loading.visible = false
	title.visible = false

func show_hud() -> void:
	hud.visible = true

func show_death() -> void:
	death_txt.text = "The wisp carries you back %s. A quarter of your satchel is lost." % ("home" if game.planet_state.has("home") else "to the surface")
	death.visible = true

func hide_death() -> void:
	death.visible = false

## the map's banner: which map, and its keys
func _build_map_bar() -> void:
	map_bar = _panel(Color(0.05, 0.04, 0.09, 0.9), TRIM, 5)
	map_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	map_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	map_bar.offset_top = 5
	map_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_bar.visible = false
	root.add_child(map_bar)
	var v := _box(true, 1)
	map_bar.add_child(v)
	map_title = _head("", 24, CREAM)
	map_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(map_title)
	map_hint = _label("", 12, DIM)
	map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(map_hint)

func show_map(g) -> void:
	if g.map_tab == "space":
		map_title.text = "The galaxy"
		map_hint.text = "WASD or drag: move    wheel or + / -: zoom    click: waypoint (right click clears)    H: you    Tab: the planet    M: close"
	else:
		map_title.text = "Map of %s" % String(g.planet.get("name", ""))
		map_hint.text = "A / D or drag: turn    W / S or wheel: zoom    Tab: the galaxy    M or Esc: close"
	map_bar.visible = true

func hide_map() -> void:
	map_bar.visible = false

func show_forge(to_book := false) -> void:
	# as big as the screen allows (a card is 152 UI pixels wide: 3 to 5 across)
	var cols := clampi(int((root.size.x - 60.0) / 152.0), 3, 5)
	forge.custom_minimum_size = Vector2(cols * 152 + 14, clampf(root.size.y - 70.0, 300.0, 520.0))
	_forge_cols = cols
	_render_forge()
	forge.visible = true
	if to_book and _book_head != null:
		# (J: opened at the recipe book's pages)
		await get_tree().process_frame
		if is_instance_valid(_book_head):
			_forge_scroll.scroll_vertical = int(_book_head.position.y)

func hide_forge() -> void:
	forge.visible = false

# ----------------------------------------------------------------- toasts --
## The building bar: the categories (Q/E), the pieces of the chosen one (wheel or 1-9; dimmed
## when the satchel can't pay), and the chosen piece's cost.
func _update_build_bar(g) -> void:
	var piece: Dictionary = g.build_piece()
	var key := "%d|%d|%s|%d|%d|%d|%s|%d|%d|%s|%d" % [g.build_cat, int(g.build_idx[g.build_cat]), _inv_key, g.build_w, g.build_floors, g.build_style, str(piece.get("cost", {})), g.build_shape, g.build_thick, str(g.build_prev.get("text", "")) + str(int(ceil(float(g.build_prev.get("mana", 0.0))))), g.build_rise]
	if key == _build_key:
		return
	_build_key = key
	for c in build_box.get_children():
		c.queue_free()
	var tabs := _box(false, 7)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	build_box.add_child(tabs)
	tabs.add_child(_label("Q", 11, DIM))
	for k in Build.CAT_ORDER:
		var tl := _head(Build.CATS[k], 12, GOLD) if k == g.build_cat else _label(Build.CATS[k], 12, DIM)
		tabs.add_child(tl)
	tabs.add_child(_label("E", 11, DIM))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.custom_minimum_size.x = 320
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.add_child(row)
	var lst: Array = g.build_list()
	for k in lst.size():
		var pc: Dictionary = lst[k]
		var afford: bool = not Build.payable(pc, g.player.inv).is_empty()
		var on: bool = pc == piece
		var col := GOLD if on else (TEXT if afford else Color(0.55, 0.42, 0.45))
		var txt: String = ("%d %s" % [k + 1, pc["name"]]) if k < 9 else String(pc["name"])
		row.add_child(_head(txt, 12, col) if on else _label(txt, 12, col))
	if lst.is_empty() and g.build_cat == Build.CAT_SATCHEL:
		var el := _label("Nothing carried. Shift + right-click a piece of furniture to take it whole, or forge some (C).", 12, CREAM)
		el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		build_box.add_child(el)
	if not piece.is_empty():
		var cost_txt: String = Build.cost_text(piece["cost"])
		if piece.has("alt"):
			cost_txt += "  or  " + Build.cost_text(piece["alt"])
		var hint := "%s: %s" % [piece["name"], cost_txt]
		if piece["kind"] == "structure":
			if cost_txt == "":
				hint = "%s: point at open ground" % piece["name"]
			hint = "%s %s, %d wide%s" % [Build.STYLES[g.build_style][0], hint, g.build_w, (", %d storeys" % g.build_floors) if piece["struct"] != "roof" and g.build_floors > 1 else ""]
			hint += "\n[ ] width  ·  %sT style  ·  R variation  ·  B leaves" % ("- = storeys  ·  " if piece["struct"] != "roof" else "")
		elif piece["kind"] == "block" or (piece["kind"] == "wall" and g.build_shape != 0):
			var shp: String = Build.SHAPES[maxi(g.build_shape, 1)]
			hint = "%s, %s%s\npress, drag, let go to lay it (right-click cancels)  ·  G shape  ·  %s  ·  B leaves" % [piece["name"], shp,
				(", %d thick" % g.build_thick) if shp != "Rectangle" else "", "[ ] thickness" if shp != "Rectangle" else "[ ] thickness of lines and frames"]
			var ptxt: String = g.build_prev.get("text", "")
			if ptxt != "":
				hint += "\n" + ptxt
		elif piece["kind"] == "remove":
			var shp2: String = Build.SHAPES[maxi(g.build_shape, 1)]
			var what: String = {"front": "blocks and ground only", "back": "back walls and plants only", "furn": "furniture and torches only (the wall behind stays)", "all": "everything"}[String(piece["layer"])]
			hint = "%s (%s), %s%s\nclick for one cell, or press, drag, let go  ·  G shape  ·  [ ] thickness  ·  B leaves" % [piece["name"], what, shp2,
				(", %d thick" % g.build_thick) if shp2 != "Rectangle" else ""]
			var ptxt2: String = g.build_prev.get("text", "")
			if ptxt2 != "":
				hint += "\n" + ptxt2
		elif piece["kind"] == "flatten":
			hint = "%s: press where the ground should be, drag along, let go\ncut above the line, dips filled from your satchel  ·  B leaves" % piece["name"]
			var ptxt3: String = g.build_prev.get("text", "")
			if ptxt3 != "":
				hint += "\n" + ptxt3
		elif piece["kind"] == "torch":
			hint = "Torch: %s\nclick to place: near a floor it stands, on a wall it hangs  ·  or choose torches and cast Conjure  ·  B leaves" % cost_txt
		elif piece["kind"] == "stairs":
			hint = "%s, %d high (%d steps): %s" % [piece["name"], g.build_rise, (g.build_rise + Build.STAIR_STEP - 1) / Build.STAIR_STEP, cost_txt if cost_txt != "" else "point at the floor where it starts"]
			hint += "\nclick to build  ·  [ ] a step higher or lower  ·  - = a storey  ·  T turn it  ·  B leaves"
		elif piece["kind"] == "carried":
			hint = "%s: yours, carried in the satchel\nclick to set it down  ·  T mirror  ·  B leaves" % piece["name"]
		else:
			hint += "\nclick to place%s  ·  B leaves" % ("  ·  R new design  ·  T mirror" if piece["kind"] == "prop" else ("  ·  hold to paint  ·  G shape" if piece["kind"] == "wall" else ""))
		var pmn: float = float(g.build_prev.get("mana", 0.0))
		if pmn > 0.0 and piece["kind"] != "remove" and piece["kind"] != "flatten":
			var hls := hint.split("\n")
			hls[0] += "  ·  %d mana" % int(ceil(pmn))
			hint = "\n".join(hls)
		var hl := _label(hint, 12, CREAM)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		build_box.add_child(hl)

func toast(txt: String, col: Color = Color.WHITE, secs: float = 2.2) -> void:
	# (the same note again only freshens the one showing)
	for it in _toast_items:
		if is_instance_valid(it[0]) and String(it[2]) == txt:
			it[1] = Time.get_ticks_msec() + int(secs * 1000.0)
			(it[0] as Control).modulate.a = 1.0
			return
	var p := _panel(Color(0.045, 0.04, 0.1, 0.84), TRIM_DIM, 3)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _box(false, 3)
	p.add_child(row)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(2, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var l := _label(txt, 13, col.lerp(CREAM, 0.35))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = minf(240.0, 7.0 + float(txt.length()) * 5.0)
	row.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toasts.add_child(p)
	_toast_items.append([p, Time.get_ticks_msec() + int(secs * 1000.0), txt])
	while toasts.get_child_count() > 4:
		var first := toasts.get_child(0)
		toasts.remove_child(first)
		first.queue_free()

func update_toasts() -> void:
	var now := Time.get_ticks_msec()
	for k in range(_toast_items.size() - 1, -1, -1):
		var it: Array = _toast_items[k]
		var p = it[0]
		if not is_instance_valid(p):
			_toast_items.remove_at(k)
			continue
		var left: int = it[1] - now
		if left < 0:
			p.modulate.a = clampf(1.0 + left / 600.0, 0.0, 1.0)
			if left < -600:
				p.queue_free()
				_toast_items.remove_at(k)

# -------------------------------------------------------------------- HUD --
func update_hud(g) -> void:
	if not hud.visible:
		return
	hp_bar.max_value = g.max_hp
	hp_bar.value = g.hp
	hp_lbl.text = "%d / %d" % [int(ceil(g.hp)), int(g.max_hp)]
	mp_bar.max_value = g.max_mana
	mp_bar.value = g.mana
	mp_lbl.text = "%d / %d" % [int(g.mana), int(g.max_mana)]
	br_row.visible = g.breath < g.max_breath
	br_bar.max_value = g.max_breath
	br_bar.value = g.breath
	if g.frame % 6 == 0:
		var a := atan2(g.player.pos.y, g.player.pos.x)
		var rs: float = g.gpu.surf_at(a).x
		var depth := int(round(rs - g.player.pos.length()))
		var depth_txt := ("Altitude %dm" % -depth) if depth < 0 else ("Depth %dm" % depth)
		var b: Dictionary = g._biome_at(a)
		var wn := "Clear"
		if depth > 14:
			wn = "Clear"                      # (no weather down here)
		elif g.rain > 0.15 and b["weather"] != "clear":
			wn = {"rain": "Rain", "snow": "Snowfall", "ash": "Ashfall"}[b["weather"]]
		if g.sky_ev != "" and depth <= 14:
			wn = String(Defs.SKY_EVENTS[g.sky_ev]["name"])
		if g.hazard != "":
			wn += " · " + String(Defs.HAZARDS[g.hazard]["name"]) + "!"
		var where: String = "%s · %s" % [g.planet["name"], g.region_name()]
		if g.space.active and not g.space.at_home():
			# (far out: where you are is the galaxy, not the planet's ground)
			var nr: Dictionary = g.space.near
			if nr.is_empty():
				where = "Deep space"
				depth_txt = "Between the stars"
			else:
				where = "Deep space · the %s system" % Galaxy.star_name(int(nr["sys"]))
				var dk: float = maxf(0.0, (g.space.centre - g.space.galaxy_focus_local()).length() - float(nr["top"]))
				depth_txt = "%s %.0fk away" % [nr["name"], dk / 1000.0]
			wn = "Nebula" if g.space.neb > 0.3 else "Clear"
			if g.space.sailing:
				wn += " · Starsail"
		# (only what matters now: where you are, the time, the weather when there is any, how deep
		# underground; the staff, relics and coins are in the satchel)
		var lines := PackedStringArray([where, g.local_time_text() + ("" if wn == "Clear" else " · " + wn)])
		if depth > 14 or depth < -60 or g.space.active:
			lines[1] = depth_txt + " · " + lines[1]
		info.text = "\n".join(lines)
		if g.show_perf:
			# F3: where the time goes (game logic on the CPU, waiting for the GPU, ticks per frame)
			info.text += "\n%d FPS · game %.1f ms · GPU wait %.1f ms · %.1f ticks/frame · %s quality\n%s" % [Engine.get_frames_per_second(), g.perf_cpu_ms, g.perf_wait_ms, g.perf_steps, g.settings["quality"], g.prof_text(6, "\n")]
		# the villagers' requests you've taken (towns.gd)
		var rqs: Array = g.towns.requests() if g.towns != null else []
		for rq in rqs:
			info.text += "\n· " + g.towns.short(rq)
	# build mode replaces the spell bar with the building bar
	hot_name.get_parent().visible = not g.build_on
	build_bar.visible = g.build_on
	if g.build_on:
		_update_build_bar(g)
	_update_hotbar(g)
	_update_satchel(g)
	if mp_glow != null:
		mp_glow.queue_redraw()
	# boss
	var boss = null
	for e in g.enemies:
		if e.boss and e.awake and not e.dead and e.pos.distance_to(g.player.pos) < 260.0:
			boss = e
	boss_box.visible = boss != null
	if boss != null:
		boss_bar.max_value = boss.max_hp
		boss_bar.value = boss.hp
		# (a biome guardian's own name and colour)
		var bname := "Vulkhar, the Ember Golem"
		var bcol := Color(1, 0.72, 0.36)
		if boss.d.has("def"):
			bname = "%s, %s" % [boss.d["def"]["name"], boss.d["def"]["title"]]
			bcol = boss.d["def"]["col"]
		if boss_lbl.text != bname:
			boss_lbl.text = bname
			boss_lbl.add_theme_color_override("font_color", bcol)
	dig_warn.visible = g.dig_blocked > 0
	var want := Input.MOUSE_MODE_HIDDEN if g.state == "play" and not mouse_over_ui() else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want:
		Input.mouse_mode = want

## the spell bar: a slot per spell known, its glyph at 2x, its number, the cooldown shading it from the top
func _update_hotbar(g) -> void:
	var hk := ",".join(g.known) + "|" + str(g.sel)
	if hk != _hot_key:
		_hot_key = hk
		for c in hotbar.get_children():
			c.queue_free()
		_hot_slots.clear()
		for k in g.known.size():
			var id: String = g.known[k]
			var s: Dictionary = Defs.SPELLS[id]
			var on: bool = k == g.sel
			var p := PanelContainer.new()
			var normal := _frame(Color(0.22, 0.15, 0.06, 0.95) if on else Color(0.05, 0.04, 0.09, 0.88), GOLD if on else TRIM_DIM, 2)
			var hover := _frame(Color(0.24, 0.17, 0.34, 0.95), GOLD, 2)
			p.add_theme_stylebox_override("panel", normal)
			p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			p.mouse_entered.connect(_set_panel_style.bind(p, hover))
			p.mouse_exited.connect(_set_panel_style.bind(p, normal))
			p.tooltip_text = "%s  (%s)\n%s" % [s["name"], ("%d mana" % int(s["mana"])) if float(s["mana"]) > 0 else "free", s["desc"]]
			var ic := _tex(Icons.spell(id), 2)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			p.add_child(ic)
			# the slot's number, and the cooldown drawn over it
			var over := Control.new()
			over.mouse_filter = Control.MOUSE_FILTER_IGNORE
			over.draw.connect(_draw_slot_over.bind(over, k, id))
			p.add_child(over)
			p.gui_input.connect(_on_hot_input.bind(k))
			hotbar.add_child(p)
			_hot_slots.append(over)
			if on:
				hot_name.text = "%s · %s" % [s["name"], ("%d mana" % int(s["mana"])) if float(s["mana"]) > 0 else "free"]
				hot_name.add_theme_color_override("font_color", (s["color"] as Color).lerp(CREAM, 0.4))
	for o in _hot_slots:
		if is_instance_valid(o):
			o.queue_redraw()

func _draw_slot_over(c: Control, k: int, id: String) -> void:
	# the cooldown: darkness falling away from the top
	var m = game.player
	if k == game.sel and m.cast_cd > 0:
		var cd: float = float(Defs.SPELLS[id]["cd"])
		var f := clampf(float(m.cast_cd) / maxf(1.0, cd), 0.0, 1.0)
		c.draw_rect(Rect2(0, 0, c.size.x, floorf(c.size.y * f)), Color(0.02, 0.01, 0.05, 0.6))
	# too little mana: a red wash
	var cost := float(Defs.SPELLS[id]["mana"])
	if cost > 0.0 and m.mana < cost:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.5, 0.05, 0.1, 0.35))
	c.draw_string(font, Vector2(1, 8), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, Color(OUTLINE, 0.9))
	c.draw_string(font, Vector2(0, 7), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, GOLD if k == game.sel else DIM)

## the satchel: a slot for each material held (click: Conjure places it), the draughts, and the furniture
## carried whole
func toggle_satchel() -> void:
	satchel_open = not satchel_open
	_inv_key = ""
	_sfx("ui_click")

func _update_satchel(g) -> void:
	var ik := str(g.mat) + "|" + str(satchel_open) + "|" + str(g.tier) + "|" + str(int(g.items.get("coins", 0))) + "|"
	for m in Defs.NM:
		if g.player.inv[m] > 0:
			ik += "%d:%d," % [m, g.player.inv[m]]
	for it in g.player.furn:
		ik += String(it["name"]) + ";"
	ik += "p%d" % int(g.items.get("potion", 0))
	for did0 in Defs.DRAUGHTS:
		ik += "%s%d%s" % [did0, int(g.items.get(did0, 0)), "*" if g.player.buffs.has(did0) else ""]
	for sk0 in g.items.keys():
		if String(sk0).begins_with("sigil_"):
			ik += "%s%d" % [sk0, int(g.items[sk0])]
	if ik == _inv_key:
		return
	_inv_key = ik
	for c in satchel.get_children():
		c.queue_free()
	for c2 in pouch.get_children():
		pouch.remove_child(c2)
		if c2 != pouch_hint:
			c2.queue_free()
	for part in _satchel_full:
		part.visible = satchel_open
	pouch.visible = not satchel_open
	var tiers := ["", "Stone", "Copper", "Obsidian", "Core Siphon"]
	var nrel := 0
	for rid in Defs.RELICS:
		if g.items.has(rid):
			nrel += 1
	(_satchel_full[0] as Label).text = "Satchel · %s staff%s" % [tiers[clampi(g.tier, 0, 4)], (" · %d relic%s" % [nrel, "" if nrel == 1 else "s"]) if nrel > 0 else ""]
	if not satchel_open:
		# the pouch: what Conjure places, the draughts, the coins
		if g.mat > 0 and g.player.inv[g.mat] > 0:
			pouch.add_child(_slot(Icons.mat(g.mat), _count(g.player.inv[g.mat]), true, "%s  ×%d: what Conjure places (I opens the satchel to choose)" % [Defs.NAMES[g.mat], g.player.inv[g.mat]]))
		var np0 := int(g.items.get("potion", 0))
		if np0 > 0:
			pouch.add_child(_slot(Icons.item("potion"), str(np0), false, "Healing Draught  ×%d\nH to drink" % np0))
		var coins := _box(false, 2)
		coins.add_child(_tex(Icons.item("coin")))
		coins.add_child(_label(_count(int(g.items.get("coins", 0))), 12, GOLD))
		coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pouch.add_child(coins)
		pouch_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pouch.add_child(pouch_hint)
		return
	var n := 0
	for m in Defs.NM:
		if g.player.inv[m] <= 0:
			continue
		var sl := _slot(Icons.mat(m), _count(g.player.inv[m]), m == g.mat, "%s  ×%d\nClick: Conjure places it" % [Defs.NAMES[m], g.player.inv[m]])
		sl.gui_input.connect(_on_mat_input.bind(m))
		satchel.add_child(sl)
		n += 1
	var np := int(g.items.get("potion", 0))
	if np > 0:
		satchel.add_child(_slot(Icons.item("potion"), str(np), false, "Healing Draught  ×%d\nH to drink" % np))
		n += 1
	for did in Defs.DRAUGHTS:
		var nd := int(g.items.get(did, 0))
		if nd <= 0:
			continue
		var dsl := _slot(Icons.draught(did), str(nd), g.player.buffs.has(did), "%s  ×%d\n%s\nClick to drink" % [Defs.DRAUGHTS[did]["name"], nd, Defs.DRAUGHTS[did]["desc"]])
		dsl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				game.drink_draught(game.player, did)
				_inv_key = "")
		satchel.add_child(dsl)
		n += 1
	# guardians' sigils (summoning.gd): lay one on a Summoning Altar in its biome
	for sk in g.items.keys():
		if String(sk).begins_with("sigil_") and int(g.items[sk]) > 0 and Defs.BOSSES.has(String(sk).substr(6)):
			var sb2: String = String(sk).substr(6)
			satchel.add_child(_slot(Icons.thing(String(sk)), str(int(g.items[sk])), false, "%s  ×%d\nLay it on a Summoning Altar in the %s (F) to call %s" % [Defs.sigil_name(sb2), int(g.items[sk]), String(Defs.BIOMES[sb2]["name"]) if Defs.BIOMES.has(sb2) else sb2, Defs.BOSSES[sb2]["name"]]))
			n += 1
	# furniture carried whole, one slot per kind
	var fc := {}
	var frows := {}
	var forder := []
	for it in g.player.furn:
		var fn: String = it["name"]
		if not fc.has(fn):
			fc[fn] = 0
			forder.append(fn)
			frows[fn] = it.get("rows", [])
		fc[fn] = int(fc[fn]) + 1
	for fn2 in forder:
		var fic: Texture2D = Icons.prop_rows(frows[fn2]) if not (frows[fn2] as Array).is_empty() else Icons.item("chair")
		satchel.add_child(_slot(fic, str(fc[fn2]), false, "%s  ×%d\nB, the Satchel tab, to set it down" % [fn2, fc[fn2]]))
		n += 1
	if n == 0:
		var e := _label("Right-click\nto dig", 11, DIM)
		satchel.add_child(e)
	var rows := int(ceil(float(maxi(n, 1)) / 5.0))
	_satchel_scroll.custom_minimum_size.y = minf(float(rows) * 27.0, maxf(80.0, root.size.y - 120.0))

# ------------------------------------------------------------------ forge --
func _render_forge() -> void:
	for c in forge_list.get_children():
		c.queue_free()
	for t in forge_tabs.get_children():
		t.queue_free()
	var cats := {}
	var order := []
	var book := []                 # recipes not yet learned (shown as the recipe book's locked pages)
	var n_known := 0
	for r in game.recipes:
		if game.recipe_hidden(r):
			continue
		if not game.knows(r):
			book.append(r)
			continue
		n_known += 1
		if not cats.has(r["cat"]):
			cats[r["cat"]] = []
			order.append(r["cat"])
		cats[r["cat"]].append(r)
	for cat in order:
		var ch := _box(false, 4)
		var cl := _head(cat, 12, Color(0.78, 0.7, 1))
		ch.add_child(cl)
		var rr := _rule(50)
		rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.add_child(rr)
		forge_list.add_child(ch)
		var grid := GridContainer.new()
		grid.columns = _forge_cols
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		forge_list.add_child(grid)
		for r in cats[cat]:
			grid.add_child(_recipe_card(r))
		# its tab: how many of its recipes you could forge now
		var n_ready := 0
		for r2 in cats[cat]:
			if not game.recipe_done(r2) and game.recipe_unlocked(r2) and game.recipe_affordable(r2):
				n_ready += 1
		var tb := _button(cat + (" ·%d" % n_ready if n_ready > 0 else ""))
		if n_ready > 0:
			tb.add_theme_color_override("font_color", GOOD)
		tb.pressed.connect(func():
			_forge_scroll.scroll_vertical = int(ch.position.y))
		forge_tabs.add_child(tb)
	# the recipe book: what you know, and the rest as locked pages saying where each is learned
	_book_head = _box(false, 4)
	_book_head.add_child(_head("Recipe Book: %d known, %d to learn" % [n_known, book.size()], 12, Color(0.72, 0.9, 1.0)))
	var br := _rule(50)
	br.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	br.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_book_head.add_child(br)
	forge_list.add_child(_book_head)
	if book.is_empty():
		forge_list.add_child(_label("Every recipe there is to find here is yours.", 11, DIM))
	else:
		var bg := GridContainer.new()
		bg.columns = _forge_cols
		bg.add_theme_constant_override("h_separation", 4)
		bg.add_theme_constant_override("v_separation", 4)
		forge_list.add_child(bg)
		for r3 in book:
			bg.add_child(_book_page(r3))
	var bh: Control = _book_head
	var bt := _button("Recipe Book")
	bt.pressed.connect(func():
		_forge_scroll.scroll_vertical = int(bh.position.y))
	forge_tabs.add_child(bt)

## a recipe's icon: the spell's glyph, what it makes, its own picture (Icons.THINGS), the piece of
## furniture itself, its ore, or a scroll
func _recipe_icon(r: Dictionary) -> Texture2D:
	if r.has("spell"):
		return Icons.spell(String(r["spell"]))
	if r.has("give") and not (r["give"] as Dictionary).is_empty():
		return Icons.mat(int((r["give"] as Dictionary).keys()[0]))
	var own: Texture2D = Icons.thing(String(r.get("id", "")))
	if own != null:
		return own
	if r.has("furniture"):
		return Icons.prop(String(r["furniture"]))
	if r.has("ore") and int(r["ore"]) >= 0:
		return Icons.mat(int(r["ore"]))
	if r.has("potion") or String(r.get("cat", "")) == "Potions":
		return Icons.item("potion")
	return Icons.thing("recipe")

## a recipe not yet learned: its name, and where it's learned
func _book_page(r: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(Color(0.06, 0.05, 0.1, 0.97), TRIM_DIM, 3))
	p.custom_minimum_size = Vector2(148, 0)
	var v := _box(true, 2)
	p.add_child(v)
	var top := _box(false, 3)
	v.add_child(top)
	var ic := _tex(_recipe_icon(r))
	ic.modulate = Color(0.45, 0.45, 0.55)
	top.add_child(ic)
	var nm := _label(String(r["name"]), 12, Color(0.62, 0.6, 0.72))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.custom_minimum_size.x = 120
	top.add_child(nm)
	var hl := _label(Defs.learn_hint(r), 11, DIM)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD
	hl.custom_minimum_size = Vector2(138, 0)
	v.add_child(hl)
	return p

func _recipe_card(r: Dictionary) -> Control:
	var done: bool = game.recipe_done(r)
	var unlocked: bool = game.recipe_unlocked(r)
	var aff: bool = game.recipe_affordable(r)
	var trim := TRIM_DIM
	if not done and unlocked and aff:
		trim = MANA
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(Color(0.08, 0.065, 0.14, 0.97), trim, 3))
	p.custom_minimum_size = Vector2(148, 0)
	if done:
		p.modulate.a = 0.55
	var v := _box(true, 2)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(v)
	var top := _box(false, 3)
	v.add_child(top)
	top.add_child(_tex(_recipe_icon(r)))
	var nm := _head(r["name"], 12, CREAM)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.custom_minimum_size.x = 120
	top.add_child(nm)
	var desc: String = r.get("desc", "")
	if r.has("spell"):
		desc = Defs.SPELLS[r["spell"]]["desc"]
	var dl := _label(desc, 11, Color(0.7, 0.71, 0.86))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dl.custom_minimum_size = Vector2(138, 0)
	v.add_child(dl)
	# (the cards of a row are as tall as its tallest: everything below the description sits at the
	# bottom, so the costs and the button line up across the row whatever the text above them)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)
	if not done and not unlocked:
		var ll := _label(game.recipe_lock_text(r), 11, DIM)
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD
		ll.custom_minimum_size = Vector2(138, 0)
		v.add_child(ll)
	var costs := HFlowContainer.new()
	costs.add_theme_constant_override("h_separation", 5)
	costs.add_theme_constant_override("v_separation", 1)
	v.add_child(costs)
	for k in r["cost"]:
		costs.add_child(_cost_chip(int(k), int(r["cost"][k])))
	# every card ends in a button of the same size: Forge, or greyed out saying why not
	var b := _button("Forged" if done else ("Locked" if not unlocked else "Forge"))
	b.disabled = done or not unlocked or not aff
	if not done and unlocked:
		b.pressed.connect(_on_craft.bind(r))
	v.add_child(b)
	return p

func _on_hot_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		game.sel = idx

func _on_mat_input(ev: InputEvent, m: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		game.select_material(m)

func _on_craft(r: Dictionary) -> void:
	var ok: bool = game.craft(r)
	_inv_key = ""
	_hot_key = ""
	if ok and game.state == "forge":
		var sv := _forge_scroll.scroll_vertical
		_render_forge()
		await get_tree().process_frame
		_forge_scroll.scroll_vertical = sv

func _set_panel_style(p: PanelContainer, sb: StyleBox) -> void:
	if is_instance_valid(p):
		p.add_theme_stylebox_override("panel", sb)

## a control's rectangle on the screen (the UI is scaled, so get_global_rect alone isn't)
static func _on_screen(c: Control) -> Rect2:
	return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)

## True when the pointer is over a clickable HUD element (satchel, spell slots; with
## `slots` false, only the panels: the wheel still picks a spell over the slots).
func mouse_over_ui(slots := true) -> bool:
	if settings_panel and settings_panel.visible:
		return true
	if hud == null or not hud.visible:
		return false
	var m := get_viewport().get_mouse_position()
	if satchel_panel and _on_screen(satchel_panel).has_point(m):
		return true
	if slots and hotbar and hotbar.is_visible_in_tree() and _on_screen(hotbar).has_point(m):
		return true
	if build_bar and build_bar.visible and _on_screen(build_bar).has_point(m):
		return true
	return false
