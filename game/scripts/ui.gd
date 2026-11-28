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
const Skiff := preload("res://scripts/skiff.gd")

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
var hull_bar: ProgressBar
var hull_row: Control
var hull_lbl: Label
var hp_lbl: Label
var mp_lbl: Label
var info: Label
const QuestScript := preload("res://scripts/quest.gd")
var quest_lbl: Label        # the main quest's step now (quest.gd), gold, under the bars
var journal: Control        # L: the main quest's journal
var hotbar: HBoxContainer
var hot_name: Label            # the chosen spell's name and cost, over the spell bar
var _hot_slots := []           # the slots' controls (their cooldown shading is drawn each frame)
var build_bar: PanelContainer      # build mode: categories, pieces and what the chosen one costs
var build_box: VBoxContainer
var hand_bar: PanelContainer        # what's in your hand and how it goes down (Conjure held)
var hand_box: VBoxContainer
var _hand_key := ""
var belt_pan: PanelContainer = null     # the item belt (main `belt()`)
var belt_row: BoxContainer = null
var _belt_key := ""
var _build_key := ""
var satchel: VBoxContainer         # the open satchel: a heading and a grid per section
var satchel_slots := 0             # (slots in it, for the tests)
var _sat_name: Label               # the name of what the pointer's over
var satchel_panel: PanelContainer
var minimap_panel: PanelContainer
var shipyard_panel: PanelContainer   # the ship builder's parts, tools and figures (shipyard.gd draws the ship)
var _sy_parts: VBoxContainer
var _sy_figs: Label
var _sy_note: Label
var _sy_key := ""
var _sy_tick := 0
var minimap: Control            # minimap.gd: the radar out in space, the land round you on a planet (N hides it)
const SAT_COLS := 8                # the open satchel's columns
var satchel_open := false          # (I or Tab) the whole satchel; closed, a pouch
var pouch: HBoxContainer
var pouch_hint: Label
var _satchel_full := []            # the open satchel's parts (hidden while it's a pouch)
var _discard := {}                 # (Shift + right-click on a slot: what the discard bar at the satchel's top offers to let go of)
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
## how many to make at a click (user, 25 Nov: "a + and - where it shows how many your going to craft"): the
## forge's repeatable recipes forge this many, a workshop's recipe loads this many batches
## how many to make, per item (user, 26 Nov: "the whisp forge has a global setting. i wanted it a per item for the
## number selection"): a forge recipe's by its id, a workshop mix's by "p:<id>"; 1..99, kept while the game runs
var amounts := {}
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
var _st_heat_l: Label
var _st_prog_l: Label
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
	# (27 Nov, settings: the interface a size smaller or larger; larger only while the screen keeps 400 UI pixels)
	var off: int = int(game.settings.get("ui_scale", 0)) if game != null else 0
	if off != 0:
		U = clampi(U + off, 1, maxi(U, int(floor(vs.y / 400.0))))
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
	hull_bar = _bar(Color(0.85, 0.55, 0.3), 9)
	hull_lbl = _label("", 12, Color.WHITE)
	hull_bar.add_child(hull_lbl)
	hull_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hull_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hull_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hull_lbl.offset_top = 1
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
	for pair in [["heart", hp_bar], ["drop", mp_bar], ["bubble", br_bar], ["hull", hull_bar]]:
		var row := _box(false, 3)
		var ic := _icon(pair[0])
		ic.custom_minimum_size.x = 11
		row.add_child(ic)
		row.add_child(pair[1])
		bars.add_child(row)
		if pair[0] == "bubble":
			br_row = row
		if pair[0] == "hull":
			hull_row = row
			row.visible = false
	bars.add_child(_rule(120))
	quest_lbl = _label("", 12, GOLD)
	quest_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	quest_lbl.custom_minimum_size = Vector2(150, 0)
	quest_lbl.visible = false
	bars.add_child(quest_lbl)
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
	# (what's in your hand, over the spell bar while Conjure is held: `_update_hand_bar`)
	hand_bar = _panel(Color(0.05, 0.04, 0.09, 0.85), TRIM, 3)
	hand_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hand_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_bar.visible = false
	hb.add_child(hand_bar)
	hand_box = _box(true, 1)
	hand_bar.add_child(hand_box)
	# (the item belt over the spell bar: what you pinned and what you held lately, Q / E: `_update_belt`)
	belt_pan = _panel(Color(0.045, 0.04, 0.1, 0.72), TRIM_DIM, 3)
	belt_pan.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	belt_pan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	belt_pan.visible = false
	hb.add_child(belt_pan)
	belt_row = _box(false, 2)
	belt_row.alignment = BoxContainer.ALIGNMENT_CENTER
	belt_pan.add_child(belt_row)
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

	# the minimap, top right (the satchel's pouch goes under it)
	minimap_panel = _panel(Color(0.045, 0.04, 0.1, 0.82), TRIM, 4)
	minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	minimap_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(minimap_panel)
	minimap = preload("res://scripts/minimap.gd").new()
	minimap.ui = self
	minimap_panel.add_child(minimap)
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
	var srule := _rule(SAT_COLS * 27 + 2)
	sv.add_child(srule)
	_satchel_full = [sh, srule]
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(SAT_COLS * 27 + 6, 0)
	sv.add_child(scroll)
	_satchel_scroll = scroll
	satchel = VBoxContainer.new()
	satchel.add_theme_constant_override("separation", 2)
	scroll.add_child(satchel)
	_satchel_full.append(scroll)
	_sat_name = _label(" ", 11, CREAM)
	_sat_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sat_name.custom_minimum_size.x = SAT_COLS * 27
	sv.add_child(_sat_name)
	_satchel_full.append(_sat_name)
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
	# (on the right of the screen, so the forge it summons beside you stays in sight: user, 25 Nov,
	# "C summons the forge into the world")
	forge = _panel(Color(0.05, 0.04, 0.09, 0.97), TRIM, 7)
	forge.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	forge.custom_minimum_size = Vector2(470, 316)
	forge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	forge.grow_vertical = Control.GROW_DIRECTION_BOTH
	forge.offset_right = -10
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
	tv.add_child(_label("Bind what you gather into spells, foci, gear, workshops and furniture. The book holds the workshops' mixes too.", 12, DIM))
	var close := _button("Close  [C]")
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): game.toggle_forge())
	head.add_child(close)
	# a tab per kind of recipe: jumps the list there (how many to forge is on each card)
	var trow := _box(false, 6)
	trow.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(trow)
	forge_tabs = HFlowContainer.new()
	forge_tabs.add_theme_constant_override("h_separation", 2)
	forge_tabs.add_theme_constant_override("v_separation", 2)
	forge_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(forge_tabs)
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

func amount_of(key: String) -> int:
	return int(amounts.get(key, 1))

func set_amount(key: String, n: int) -> void:
	amounts[key] = clampi(n, 1, 99)

## How many of one item to make: − n + (Shift: by 10), 1..99, its own (`amounts`). `changed` runs after.
func _amount_box(key: String, changed: Callable) -> Control:
	var hb := _box(false, 1)
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var minus := _button("-")
	var lbl := _head("%d" % amount_of(key), 12, GOLD)
	lbl.custom_minimum_size.x = 16
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var plus := _button("+")
	minus.tooltip_text = "One fewer (Shift: ten fewer)"
	plus.tooltip_text = "One more (Shift: ten more)"
	minus.pressed.connect(func():
		set_amount(key, amount_of(key) - (10 if Input.is_key_pressed(KEY_SHIFT) else 1))
		lbl.text = "%d" % amount_of(key)
		changed.call())
	plus.pressed.connect(func():
		var cur := amount_of(key)
		set_amount(key, cur + (10 if Input.is_key_pressed(KEY_SHIFT) and cur > 1 else (9 if Input.is_key_pressed(KEY_SHIFT) else 1)))
		lbl.text = "%d" % amount_of(key)
		changed.call())
	hb.add_child(minus)
	hb.add_child(lbl)
	hb.add_child(plus)
	return hb

## a forge card's button: "Forge ×n" with its own amount, for what can be forged many times
func _forge_text(r: Dictionary) -> String:
	var n := amount_of(String(r.get("id", "")))
	return "Forge ×%d" % n if game.recipe_repeatable(r) and n > 1 else "Forge"

## the forge drawn again where it was scrolled to
func _rerender_forge() -> void:
	if not forge.visible:
		return
	var sv := _forge_scroll.scroll_vertical
	_render_forge()
	await get_tree().process_frame
	_forge_scroll.scroll_vertical = sv

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
	var close := _button(game.keys_in("Leave  [F]"))
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
	if it.has("chart") or it.has("star_chart") or it.has("job"):
		return Icons.item("letter")
	if it.has("repair"):
		return Icons.item("hull")
	if it.has("part"):
		var pt: Texture2D = Icons.thing(String(it["part"]))
		if pt != null:
			return pt
	if it.has("recipe"):
		return Icons.thing("recipe")
	if it.has("good"):
		return Icons.item("crate")
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
	if String(_shop_v.role) == "outpost" or String(_shop_v.role) == "cantina":
		shop_title.text += " · hold %d/%d crates" % [game.cargo_count(), game.hold_cap()]
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
		var own_txt := "yours"
		if it.has("repair"):
			own_txt = "whole" if game.skiff != null and game.skiff.missing() == 0 else "not here"
		if it.has("job"):
			ptxt = "+%d" % int(it["job"]["pay"])
			own_txt = "taken"
		row.add_child(_label(own_txt if have_it else ptxt, 12, DIM if have_it else GOLD))
		var b := _button("Take" if it.has("job") else "Buy")
		b.disabled = have_it or (tw.coins() < price and not it.has("job")) or (it.has("good") and game.cargo_count() >= game.hold_cap())
		b.pressed.connect(func():
			tw.buy(_shop_v, i)
			_render_shop())
		row.add_child(b)
		shop_list.add_child(row)
	for bb in tw.buys(_shop_v):
		var mat: int = bb[0]
		var have: int = game.inv[mat]
		if mat >= Defs.FIREOPAL and mat <= Defs.SILVER and have <= 0 and mat != Defs.kind_ore(game.planet):
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
	# crates in your hold, and what this outpost pays for each (gold: what it wants most)
	var pays: Dictionary = tw.good_pays(_shop_v)
	var wants: Dictionary = tw.good_wants(_shop_v)
	var cargo: Dictionary = game.items.get("cargo", {})
	for gd in pays:
		var nc := int(cargo.get(gd, 0))
		if nc <= 0 and not wants.has(gd):
			continue
		var row3 := _box(false, 3)
		row3.mouse_filter = Control.MOUSE_FILTER_PASS
		row3.add_child(_tex(Icons.item("crate")))
		var l3 := _label("%s%s (%d in the hold)" % [Defs.GOODS[gd]["name"], " · wanted" if wants.has(gd) else "", nc], 12, CREAM if nc > 0 else DIM)
		l3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row3.add_child(l3)
		row3.add_child(_label("%d" % int(pays[gd]), 12, GOLD))
		var b3 := _button("Sell")
		b3.disabled = nc <= 0
		var gsel: String = gd
		b3.pressed.connect(func():
			tw.sell_good(_shop_v, gsel)
			_render_shop())
		row3.add_child(b3)
		shop_buys.add_child(row3)

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
	var close := _button(game.keys_in("Leave  [F]"))
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
	_st_heat_l = _label("Heat", 12, DIM)
	bars.add_child(_st_heat_l)
	_st_heat = _bar(Color(1.0, 0.45, 0.15))
	bars.add_child(_st_heat)
	_st_prog_l = _label("Batch", 12, DIM)
	bars.add_child(_st_prog_l)
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
	_st_heat_l.visible = burn > 0.0
	_st_prog_l.visible = burn > 0.0 or st.kind == "lectern"
	_st_prog_l.text = "Study" if st.kind == "lectern" else "Batch"
	var txt := ""
	if st.kind == "lectern":
		_st_prog.visible = true
		_st_prog.value = clampf(st.prog / float(Defs.STUDY_TICKS) * 100.0, 0.0, 100.0) if ws.studying(st) else 0.0
		txt = ("Studying the %s..." % String(ws.study_of(st).get("n", "artifact"))) if ws.studying(st) else "Lay an artifact on it to study it."
	elif burn <= 0.0:
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
	var key := "%s|%s|%s|%s|%d|%d" % [str(st.store), str(st.out), _inv_key_now(), st.cur, int(st.fuel > 0.0), (game.items.get("artifacts", []) as Array).size()]
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

## the Lectern's panel (27 Nov): what's being studied, and the artifacts in your satchel to lay on it
func _render_lectern(st) -> void:
	var ws = game.workshops
	if ws.studying(st):
		var a: Dictionary = ws.study_of(st)
		var row := _box(false, 4)
		row.add_child(_tex(Icons.artifact(a)))
		row.add_child(_label("On the lectern: %s" % String(a["n"]), 12, CREAM))
		var tb := _button("Take it back")
		tb.tooltip_text = "Its study so far is lost"
		tb.pressed.connect(func():
			ws.unstudy(st)
			_st_key = "")
		row.add_child(tb)
		_st_body.add_child(row)
	_st_section("Your artifacts (study one: it takes a while, while you're on this world)")
	var arts: Array = game.items.get("artifacts", [])
	if arts.is_empty():
		var al := _label("No artifacts yet. They're found in the places to discover on far worlds (archives, sanctums, fallen ships) and in guardians' hoards.", 12, CREAM)
		al.autowrap_mode = TextServer.AUTOWRAP_WORD
		al.custom_minimum_size.x = 440
		_st_body.add_child(al)
		return
	for k in arts.size():
		var a2: Dictionary = arts[k]
		var r2 := _box(false, 4)
		r2.add_child(_tex(Icons.artifact(a2)))
		var kd := String(a2["k"])
		var left: int = game.study_pool(kd).size()
		r2.add_child(_label("%s · from a %s world · %s" % [String(a2["n"]), "deep ocean" if kd == "abyss" else kd, ("%d recipe%s it could teach" % [left, "" if left == 1 else "s"]) if left > 0 else "nothing new to teach"], 12, CREAM))
		var sb := _button("Study")
		var kk := k
		sb.pressed.connect(func():
			ws.study(st, kk)
			_st_key = "")
		r2.add_child(sb)
		_st_body.add_child(r2)

func _render_station() -> void:
	for c in _st_body.get_children():
		c.queue_free()
	var st = _st
	var ws = game.workshops
	var sd: Dictionary = Defs.STATIONS[st.kind]
	_st_title.text = String(sd["name"])
	var burn := float(sd["burn"])
	if st.kind == "lectern":
		_render_lectern(st)
		return
	if burn <= 0.0:
		# the anvil: the gear you've forged, upgraded a level at a time (27 Nov; main `upgrade_gear`, Defs.UPGRADES)
		_st_section("Upgrade your gear: each level makes every effect of it stronger")
		var any := false
		for gid in Defs.GEAR:
			if not game.player.items.has(gid):
				continue
			any = true
			var glv: int = game.gear_level(String(gid))
			var grow := _box(false, 4)
			var gic: Texture2D = Icons.thing(String(gid))
			grow.add_child(_tex(gic if gic != null else Icons.thing("recipe")))
			var gnm := _label("%s · %s" % [game.gear_name(String(gid)), "as forged" if glv == 0 else String(Defs.UPGRADES[glv - 1]["name"])], 12, CREAM)
			gnm.tooltip_text = String(Defs.GEAR[gid].get("desc", ""))
			gnm.mouse_filter = Control.MOUSE_FILTER_PASS
			grow.add_child(gnm)
			_st_body.add_child(grow)
			# (a second line: what the next level costs, and the button)
			var gline := _box(false, 4)
			var gpad := Control.new()
			gpad.custom_minimum_size.x = 20
			gline.add_child(gpad)
			if glv < Defs.UPGRADES.size():
				var gup: Dictionary = Defs.UPGRADES[glv]
				gline.add_child(_label("-> %s, +%d%%" % [String(gup["name"]), int(round((float(gup["q"]) - 1.0) * 100.0))], 12, GOLD))
				var gcost: Dictionary = gup["cost"]
				for gcm in gcost:
					gline.add_child(_cost_chip(int(gcm), int(gcost[gcm])))
				var gub := _button("Upgrade")
				var gwhy: String = game.upgrade_block(String(gid))
				gub.disabled = gwhy != ""
				if gwhy != "":
					gub.tooltip_text = gwhy
				var gid_s := String(gid)
				gub.pressed.connect(func():
					game.upgrade_gear(gid_s)
					_st_key = "")
				gline.add_child(gub)
			else:
				gline.add_child(_label("fully upgraded", 12, DIM))
			_st_body.add_child(gline)
			# (27 Nov) its traits, and reforging them: a roll again, as good as the forging here
			var tline := _box(false, 4)
			var tpad := Control.new()
			tpad.custom_minimum_size.x = 20
			tline.add_child(tpad)
			var ttx: String = game.gear_traits_text(String(gid))
			tline.add_child(_label(ttx if ttx != "" else "no traits", 11, MANA if ttx != "" else DIM))
			var rcost: Dictionary = Defs.reforge_cost(String(gid))
			for rcm in rcost:
				tline.add_child(_cost_chip(int(rcm), int(rcost[rcm])))
			var rfb := _button("Reforge")
			var rwhy: String = game.reforge_block(String(gid))
			rfb.disabled = rwhy != ""
			rfb.tooltip_text = rwhy if rwhy != "" else "Roll its traits again. %s" % game.forge_quality_text(String(gid))
			var rgid := String(gid)
			rfb.pressed.connect(func():
				game.reforge_gear(rgid)
				_st_key = "")
			tline.add_child(rfb)
			_st_body.add_child(tline)
		if not any:
			var al := _label("Forge ore gear, an alloy or a core's gear (C), then bring it here: each piece can be upgraded five times as the journey goes on (ingots and coal, then wisp ingots and obsidian, star iron and crystal, a world's core, the void's essence).", 12, CREAM)
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
	# what it knows how to make: click one and its mix is loaded from the satchel (Amount batches of it)
	var mh := _box(false, 6)
	mh.add_child(_head("It makes: click one to load it", 12, Color(0.95, 0.8, 0.5)))
	_st_body.add_child(mh)
	for pr in Defs.PROCESS:
		if pr["at"] != st.kind:
			continue
		var secret: bool = pr.get("secret", false)
		var found: bool = not secret or ws.is_secret_known(String(pr["id"]))
		var row := _box(false, 3)
		if found:
			var lkey := "p:" + String(pr["id"])
			var ln := amount_of(lkey)
			row.add_child(_amount_box(lkey, func(): _st_key = ""))
			var lb := _button("Load ×%d" % ln if ln > 1 else "Load")
			# (loading adds to what's in: one batch's worth must be in the satchel)
			var can := true
			for nm2 in pr["in"]:
				if game.player.inv[int(nm2)] < int(pr["in"][nm2]):
					can = false
			lb.disabled = not can
			lb.tooltip_text = "Load %d more batch%s of this mix from your satchel, on top of what's in (anything else loaded goes back)" % [ln, "" if ln == 1 else "es"]
			var prr: Dictionary = pr
			lb.pressed.connect(func():
				var want_n := amount_of(lkey)
				var nb: int = ws.load_recipe(st, prr, want_n)
				if nb > 0:
					game.audio.play("place", st.pos, 0.4)
					if nb < want_n:
						toast("Loaded %d of %d: the satchel ran short" % [nb, want_n], Color(1, 0.8, 0.55), 2.0)
				_st_key = "")
			row.add_child(lb)
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
## The pause menu and the settings (27 Nov): settings_menu.gd draws them into this panel
const SettingsMenu := preload("res://scripts/settings_menu.gd")
var settings_menu = null

func _build_settings() -> void:
	settings_panel = _screen()
	settings_panel.visible = false
	settings_menu = SettingsMenu.new()
	settings_menu.setup(self, game)
	add_child(settings_menu)

func _refresh_settings() -> void:
	if settings_panel != null and settings_panel.visible:
		settings_menu.build()

## The journal (L): the main quest's chapter, every step (done, now with how to do it, still to come), and the
## wisp's gifts. The world waits while it's open (main `menu_paused`).
func journal_open() -> bool:
	return journal != null and journal.visible

func toggle_journal(g) -> void:
	if journal_open():
		journal.queue_free()
		journal = null
		_sfx("ui_click")
		return
	journal = _screen()
	var v: VBoxContainer = journal.get_meta("box")
	v.add_theme_constant_override("separation", 3)
	var q = g.quest
	q.ensure()
	var hd := _head("Journal", 24, CREAM)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hd)
	var ct := _label(q.chapter_title(q.chapter), 12, GOLD)
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ct)
	v.add_child(_center(_rule(300)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(400, mini(330, int(root.size.y) - 150))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := _box(true, 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var steps: Array = q.steps
	for k in steps.size():
		var st: Dictionary = steps[k]
		if k < q.at:
			list.add_child(_label("✓ " + String(st["title"]), 12, Color(0.55, 0.6, 0.72)))
		elif k == q.at:
			list.add_child(_label("✦ " + String(st["title"]), 12, GOLD))
			var how := _label(String(st["how"]), 12, CREAM)
			how.autowrap_mode = TextServer.AUTOWRAP_WORD
			how.custom_minimum_size = Vector2(380, 0)
			list.add_child(how)
		else:
			list.add_child(_label("· " + String(st["title"]), 12, Color(0.62, 0.6, 0.8)))
	if q.at >= steps.size():
		list.add_child(_label("✦ This chapter is done. Land on the next world and the wisp will speak again.", 12, GOLD))
	# a mystery heard of (a deep ocean world in this system): its steps and the song so far
	var mw: int = q.mystery_world()
	if mw >= 0 and (g.items.has("myst_heard") or g.items.has("myst_heard_giant") or g.items.has("myst_heard_star") or g.items.has("myst_heard_void") or g.items.has("keel") or g.items.has("lattice") or g.items.has("heatshield") or g.items.has("voidanchor") or (g.items.get("myst", {}) as Dictionary).has(str(mw)) or Defs.is_exotic(int(g.planet.get("index", 0)))):
		list.add_child(_rule(200))
		list.add_child(_label("A mystery: %s" % String(Defs.make_planet(mw)["name"]), 12, CREAM))
		var mfirst := true
		for ms in q.mystery_steps():
			if bool(ms["done"]):
				list.add_child(_label("✓ " + String(ms["title"]), 12, Color(0.55, 0.6, 0.72)))
			elif mfirst:
				mfirst = false
				list.add_child(_label("✦ " + String(ms["title"]), 12, MANA))
				var mh := _label(String(ms["how"]), 12, CREAM)
				mh.autowrap_mode = TextServer.AUTOWRAP_WORD
				mh.custom_minimum_size = Vector2(380, 0)
				list.add_child(mh)
			else:
				list.add_child(_label("· " + String(ms["title"]), 12, Color(0.62, 0.6, 0.8)))
		list.add_child(_label(({"abyss": "The song: ", "giant": "The beacons: ", "star": "The relay: ", "void": "The Gate: "}.get(Defs.exotic_kind(mw), "")) + q.mystery_notes(), 12, Color(0.7, 0.85, 1.0)))
	# places to discover on this world (places.gd)
	if g.places != null and not g.places.list().is_empty() and not g.space.active:
		list.add_child(_rule(200))
		var ps: Array = g.places.summary()
		var nf := 0
		for e in ps:
			if String(e[1]) == "":
				nf += 1
		list.add_child(_label("Places to discover on %s: %d of %d found" % [String(g.planet.get("name", "this world")), ps.size() - nf - _revealed_n(ps), ps.size()], 12, CREAM))
		for e2 in ps:
			if String(e2[1]) == "found":
				list.add_child(_label("✓ " + String(e2[0]), 12, Color(0.55, 0.6, 0.72)))
			elif String(e2[1]) == "revealed":
				list.add_child(_label("✦ %s: an artifact's markings showed where (on your map)" % String(e2[0]), 12, MANA))
		if nf > 0:
			list.add_child(_label("· %d still hidden: the wisp feels them when you come near" % nf, 12, Color(0.62, 0.6, 0.8)))
	list.add_child(_rule(200))
	list.add_child(_label("The wisp's gifts", 12, CREAM))
	for pw in QuestScript.POWERS:
		var have: bool = g.items.has("wisp_" + String(pw))
		var pl := _label(("✦ %s: %s" % [QuestScript.POWERS[pw]["name"], QuestScript.POWERS[pw]["desc"]]) if have else "· ? (a gift still to come)", 12, MANA if have else Color(0.5, 0.5, 0.66))
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD
		pl.custom_minimum_size = Vector2(380, 0)
		list.add_child(pl)
	var ft := _label("L or Esc to close", 12, Color(0.6, 0.6, 0.78))
	ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ft)
	_sfx("ui_click")

func _revealed_n(ps: Array) -> int:
	var n := 0
	for e in ps:
		if String(e[1]) == "revealed":
			n += 1
	return n

## Esc in play (the pause page, or a step back out of it), the title screen's Settings (straight to the settings)
func toggle_settings() -> void:
	if settings_menu.is_open():
		settings_menu.escape()
	elif game.state == "play" or game.state == "forge" or game.state == "dead":
		settings_menu.open_pause()
	else:
		settings_menu.open_settings(false)

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

# ------------------------------------------------------------ ship builder --
## The ship builder's panel (shipyard.gd): the parts with what you hold of each (click one, or 1-9), the
## tools, Undo / New keel / Done, the ship's figures and a word on what just happened.
func show_shipyard(g) -> void:
	if shipyard_panel == null:
		shipyard_panel = _panel(Color(0.045, 0.04, 0.1, 0.92), TRIM, 4)
		shipyard_panel.position = Vector2(5, 4)
		root.add_child(shipyard_panel)
		var v := _box(true, 3)
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		shipyard_panel.add_child(v)
		v.add_child(_head("Ship builder", 20))
		v.add_child(_rule(150))
		_sy_parts = VBoxContainer.new()
		_sy_parts.add_theme_constant_override("separation", 1)
		v.add_child(_sy_parts)
		v.add_child(_rule(150))
		var tips := _label("Left: lay · Right: cut · Shift-drag: a rectangle\n[ ] brush size · wheel zoom · WASD pan", 10, DIM)
		v.add_child(tips)
		var hb := _box(false, 3)
		hb.mouse_filter = Control.MOUSE_FILTER_PASS
		var bu := _button("Undo (Z)")
		bu.pressed.connect(func(): g.shipyard.do_undo())
		var bk := _button("New keel")
		bk.pressed.connect(func(): g.shipyard.new_keel())
		var bd := _button("Done (B)")
		bd.pressed.connect(func(): g.shipyard.close())
		hb.add_child(bu)
		hb.add_child(bk)
		hb.add_child(bd)
		v.add_child(hb)
		v.add_child(_rule(150))
		_sy_figs = _label("", 10, Color(0.86, 0.87, 1))
		v.add_child(_sy_figs)
		_sy_note = _label("", 10, GOLD)
		_sy_note.autowrap_mode = TextServer.AUTOWRAP_WORD
		_sy_note.custom_minimum_size = Vector2(160, 0)
		v.add_child(_sy_note)
	hud.visible = false
	_sy_key = ""
	shipyard_panel.visible = true
	update_shipyard(g)

func hide_shipyard() -> void:
	if shipyard_panel != null:
		shipyard_panel.visible = false
	hud.visible = true

func update_shipyard(g) -> void:
	if shipyard_panel == null or not shipyard_panel.visible:
		return
	var sy = g.shipyard
	var key := "%d|%s" % [sy.sel, str(g.player.inv)]
	if key != _sy_key:
		_sy_key = key
		for c in _sy_parts.get_children():
			c.queue_free()
		for pi in sy.parts.size():
			var p: Dictionary = sy.parts[pi]
			var kind := String(p["kind"])
			var row := _button("")
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var held := ""
			var icon: Texture2D = null
			match kind:
				"hull":
					var pay: int = int((p["cost"] as Dictionary).keys()[0])
					held = "%d" % int(g.player.inv[pay])
					icon = Icons.mat(int(p["mat"]))
				"helm":
					held = "move it"
					icon = Icons.mat(Defs.COPPERBAR)
				"seat":
					held = "4 planks"
					icon = Icons.item("chair")
				"door":
					held = "place it"
					icon = Icons.mat(Defs.CRYSTAL)
			row.text = "%d  %s   %s" % [pi + 1, String(p["name"]), held]
			row.icon = icon
			row.expand_icon = false
			_set_chosen(row, pi == sy.sel)
			var idx: int = pi
			row.pressed.connect(func(): sy.sel = idx)
			_sy_parts.add_child(row)
	_sy_tick += 1
	if _sy_tick % 6 == 1:                 # (the world waits in the builder: `frame` doesn't move)
		var f: Dictionary = sy.figures()
		_sy_figs.text = "Hull %d cells (%s) · mass %d\nEngines %d cells · thrust %d%%\nHold %d crates · %d seats · brush %d" % [
			int(f["cells"]), String(f["size"]), int(f["mass"]), int(f["engines"]), int(f["drive"]), int(f["hold"]), int(f["seats"]), sy.brush]
		_sy_note.text = sy.note

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
		map_hint.text = "A / D or drag: turn    W / S or wheel: zoom    click: waypoint (right click clears)    Tab: the galaxy    M or Esc: close"
	map_bar.visible = true

func hide_map() -> void:
	map_bar.visible = false

var _inking := {}       # recipes learned since the book was last open: they ink in as it opens
var _inked := {}

func show_forge(to_book := false) -> void:
	_inking = {}
	_inked = {}
	for nid in game.items.get("book_new", []):
		_inking[String(nid)] = true
	game.items.erase("book_new")
	# within the right half of the screen, clear of you at its middle (a card is 152 UI pixels wide: 2 or 3
	# across; at 4 the panel reached over the mage)
	var cols := clampi(int((root.size.x * 0.5 - 80.0) / 152.0), 2, 3)
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
## The hand's bar (25 Nov): while Conjure is held with something in hand, what it is and how it goes down
## (main `hand_hint`), just over the spell bar
func _update_hand_bar(g) -> void:
	var txt: String = g.hand_hint()
	if txt == _hand_key:
		return
	_hand_key = txt
	for c in hand_box.get_children():
		c.queue_free()
	var ls := txt.split("\n")
	for i in ls.size():
		var hl := _label(ls[i], 12, GOLD if i == 0 else CREAM)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hand_box.add_child(hl)

## The item belt (main `belt()`): a slot each, pinned ones with a gold pin, the one in your hand chosen, what
## you've run out of dimmed; click to hold it, right-click to pin or unpin; Q and E at its ends
func _belt_icon(g, sid: String) -> Array:
	if sid.begins_with("m"):
		var mt := int(sid.substr(1))
		return [Icons.mat(mt), String(Defs.NAMES[mt]), g.player.inv[mt]]
	if sid.begins_with("f:"):
		var nm := sid.substr(2)
		var fi: int = g._furn_index(nm)
		var n := 0
		for it in g.player.furn:
			if String(it["name"]) == nm:
				n += 1
		var rows: Array = g.player.furn[fi].get("rows", []) if fi >= 0 else []
		return [Icons.prop_rows(rows) if not rows.is_empty() else Icons.item("chair"), nm, n]
	if sid.begins_with("p:"):
		return [Icons.plan(sid.substr(2)), Build.plan_name(sid.substr(2)) + " plan", 1]
	var sk := sid.substr(2)
	return [Icons.station(sk), String(Defs.STATIONS[sk]["name"]) if Defs.STATIONS.has(sk) else sk, int(g.items.get("st_" + sk, 0))]

func _update_belt(g) -> void:
	var b: Array = g.belt()
	var hid: String = g.hand_id() if g.conjuring(g.player) else ""
	var key := hid
	for e in b:
		key += "|" + String(e[0]) + ("*" if e[1] else "") + (str(_belt_icon(g, String(e[0]))[2]) if String(e[0]) != "" else "")
	if key == _belt_key:
		return
	_belt_key = key
	for c in belt_row.get_children():
		belt_row.remove_child(c)
		c.queue_free()
	belt_row.add_child(_label("Q", 11, DIM))
	for e2 in b:
		var sid := String(e2[0])
		if sid == "":
			var empty := _slot(Icons.item("coin"), "", false, "An empty slot: right-click something in the satchel (I) to pin it here")
			empty.get_child(0).modulate.a = 0.0
			empty.modulate.a = 0.45
			belt_row.add_child(empty)
			continue
		var info := _belt_icon(g, sid)
		var pinned: bool = e2[1]
		var sl := _slot(info[0], "" if sid.begins_with("p:") else _count(int(info[2])), sid == hid, "%s  ×%d\nClick or Q / E: in your hand\nRight-click: %s" % [info[1], int(info[2]), "unpin" if pinned else "pin it here"])
		if int(info[2]) <= 0:
			sl.modulate = Color(1, 1, 1, 0.4)
		if pinned:
			var pin := ColorRect.new()
			pin.color = GOLD
			pin.custom_minimum_size = Vector2(2, 2)
			pin.size = Vector2(2, 2)
			pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN     # (a gold dot in its top left corner)
			pin.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			sl.add_child(pin)
		sl.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed:
				if ev.button_index == MOUSE_BUTTON_LEFT and game.belt_has(sid):
					game.quick_take(sid)
				elif ev.button_index == MOUSE_BUTTON_RIGHT:
					game.belt_pin(sid))
		belt_row.add_child(sl)
	belt_row.add_child(_label("E", 11, DIM))

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
		var pname: String = String(pc["name"]) + ((" ×%d" % int(pc["carried"])) if int(pc.get("carried", 1)) > 1 else "")
		var txt: String = ("%d %s" % [k + 1, pname]) if k < 9 else pname
		row.add_child(_head(txt, 12, col) if on else _label(txt, 12, col))
	if lst.is_empty() and g.build_cat == Build.CAT_SATCHEL:
		var el := _label("Nothing carried. Shift + right-click furniture or a workshop to take it whole, or forge furniture (C).", 12, CREAM)
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
			var nc := int(piece.get("carried", 1))
			if nc > 1:
				hint = "%s: %d carried in the satchel\nclick to set one down  ·  R the next of them  ·  T mirror  ·  B leaves" % [piece["name"], nc]
			else:
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
	if game != null:
		txt = game.keys_in(txt)
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
	# the minimap (hidden while the satchel's grid is open: that goes to the top)
	minimap.game = g
	var mm_on: bool = bool(g.settings.get("minimap", true)) and not satchel_open and (g.state == "play" or g.state == "dead") and not g.pocket.active
	minimap_panel.visible = mm_on
	# (kept 5 in from the right edge whatever size it is: the radar and the side view differ)
	var mms: Vector2 = minimap_panel.get_combined_minimum_size()
	minimap_panel.offset_right = -5.0
	minimap_panel.offset_left = -5.0 - mms.x
	minimap_panel.offset_top = 4.0
	minimap_panel.offset_bottom = 4.0 + mms.y
	# (the satchel too, sized to what it holds each frame: a container never shrinks by itself, so closed
	# after being open the pouch kept the open satchel's size; user, 25 Nov: "when i close the satchel its
	# very big")
	var sat_y: float = (4.0 + mms.y + 3.0) if mm_on else 4.0
	var sms: Vector2 = satchel_panel.get_combined_minimum_size()
	satchel_panel.offset_right = -5.0
	satchel_panel.offset_left = -5.0 - sms.x
	satchel_panel.offset_top = sat_y
	satchel_panel.offset_bottom = sat_y + sms.y
	hp_bar.max_value = g.max_hp
	hp_bar.value = g.hp
	hp_lbl.text = "%d / %d" % [int(ceil(g.hp)), int(g.max_hp)]
	mp_bar.max_value = g.max_mana
	mp_bar.value = g.mana
	mp_lbl.text = "%d / %d" % [int(g.mana), int(g.max_mana)]
	br_row.visible = g.breath < g.max_breath
	br_bar.max_value = g.max_breath
	br_bar.value = g.breath
	# the skiff's hull, while you ride it and it's hurt (or out in space, where things shoot at it)
	var sk = g.skiff
	hull_row.visible = sk != null and g.player.aboard == sk and (sk.hull_f < 0.995 or g.space.active)
	if hull_row.visible:
		hull_bar.max_value = 100.0
		hull_bar.value = sk.hull_f * 100.0
		hull_lbl.text = "Hull %d%%" % int(round(sk.hull_f * 100.0))
	if g.frame % 6 == 0 and g.pocket.active and g.pocket.place == "outpost":
		# (docked: the outpost's halls, and what F does here)
		var po := PackedStringArray([String(g.pocket.op.wname), "Docked · its shops along the deck"])
		match String(g.pocket.near):
			"ship":
				po.append("[F] undock")
			"keeper":
				po.append("[F] trade")
			"folk":
				po.append("[F] talk")
		if g.cargo_count() > 0 or g.items.has("skiff"):
			po[1] += " · hold %d/%d crates" % [g.cargo_count(), g.hold_cap()]
		info.text = g.keys_in("\n".join(po))
	elif g.frame % 6 == 0 and g.pocket.active:
		# (inside the ship: its pocket, how far the isle has grown, what F does here)
		var pl := PackedStringArray(["Your ship's pocket", "An isle in a nebula · level %d of %d" % [g.pocket.isle.level, g.pocket.Isle.LEVELS.size() - 1]])
		match String(g.pocket.near):
			"arch":
				pl.append("[F] step out where you came in · [G] out by your ship")
			"heart":
				pl.append("[F] the Isle Heart: grow the isle")
		info.text = g.keys_in("\n".join(pl))
		var qp: String = g.quest.hud_line() if g.quest != null else ""
		quest_lbl.visible = qp != ""
		if qp != "" and quest_lbl.text != "✦ " + qp:
			quest_lbl.text = "✦ " + qp
	elif g.frame % 6 == 0:
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
		if g.space.active and g.space.pirate_count() > 0:
			wn = ("" if wn == "Clear" else wn + " · ") + "Pirates!"
		if g.space.active and (g.space.flare > 0 or g.space.flare_warn > 0):
			wn = ("" if wn == "Clear" else wn + " · ") + ("Solar flare!" if g.space.flare > 0 else "The star stirs")
		if g.space.active and g.space.vl.hunting() > 0:
			wn = ("" if wn == "Clear" else wn + " · ") + "Lumen eels!"
		if g.space.active and g.space.vl.nearest_well(g.space.galaxy_focus_local(), 2400.0) != null:
			wn = ("" if wn == "Clear" else wn + " · ") + "Gravity well"
		if g.space.active and g.space.in_station != null:
			# (aboard a derelict station: its name, the room, and whether its gravity holds; an outpost: its
			# name and the room)
			var dst = g.space.in_station
			var rk: int = dst.module_at(dst.to_body(g.player.pos) + dst.com)
			if dst.kind == "outpost":
				where = String(dst.wname)
				depth_txt = dst.role_name(rk)
			else:
				where = "Derelict %s" % dst.wname
				depth_txt = "%s · %s" % [dst.role_name(rk), "gravity" if rk >= 0 and dst.mods[rk]["powered"] else "no gravity"]
		# (only what matters now: where you are, the time, the weather when there is any, how deep
		# underground; the staff, relics and coins are in the satchel)
		var lines := PackedStringArray([where, g.local_time_text() + ("" if wn == "Clear" else " · " + wn)])
		if depth > 14 or depth < -60 or g.space.active:
			lines[1] = depth_txt + " · " + lines[1]
		if g.space.active and g.items.has("skiff"):
			lines[1] += " · %d wisp cells" % g.player.inv[Defs.WISPCELL]
		if g.items.has("skiff") and (g.space.active or g.player.aboard != null or g.cargo_count() > 0):
			lines[1] += " · hold %d/%d crates" % [g.cargo_count(), g.hold_cap()]       # (cargo: a stat of your ship's class)
		info.text = "\n".join(lines)
		var ql: String = g.quest.hud_line() if g.quest != null else ""
		quest_lbl.visible = ql != ""
		if ql != "" and quest_lbl.text != "✦ " + ql:
			quest_lbl.text = "✦ " + ql
		if g.show_perf:
			# F3: where the time goes (game logic on the CPU, waiting for the GPU, ticks per frame)
			info.text += "\n%d FPS · game %.1f ms · GPU wait %.1f ms · %.1f ticks/frame · %s quality\n%s" % [Engine.get_frames_per_second(), g.perf_cpu_ms, g.perf_wait_ms, g.perf_steps, g.quality() + (" (auto)" if g.settings["quality"] == "auto" else ""), g.prof_text(6, "\n")]
		elif bool(g.settings.get("show_fps", false)):
			info.text += "\n%d FPS" % Engine.get_frames_per_second()      # (settings: the frame counter)
		# the villagers' requests you've taken (towns.gd)
		var rqs: Array = g.towns.requests() if g.towns != null else []
		for rq in rqs:
			info.text += "\n· " + g.towns.short(rq)
		# (and the outposts' jobs you've taken: space.gd)
		for jb in g.space.jobs():
			info.text += "\n· " + g.space.job_short(jb)
	# build mode replaces the spell bar with the building bar
	hot_name.get_parent().visible = not g.build_on
	var hand_on: bool = g.hand_bar_on()
	build_bar.visible = g.build_on
	hand_bar.visible = hand_on
	var belt_any := false
	for be in g.belt():
		if String(be[0]) != "":
			belt_any = true
	belt_pan.visible = belt_any and not g.build_on and g.state == "play" and g.player.aboard == null
	if belt_pan.visible:
		_update_belt(g)
	if g.build_on:
		_update_build_bar(g)
	elif hand_on:
		_update_hand_bar(g)
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
	# (each spell its own: a long one, Mending's, never darkens the others)
	var left := int(m.spell_cd.get(id, 0))
	if left > 0:
		var cd: float = float(Defs.SPELLS[id]["cd"])
		var f := clampf(float(left) / maxf(1.0, cd), 0.0, 1.0)
		c.draw_rect(Rect2(0, 0, c.size.x, floorf(c.size.y * f)), Color(0.02, 0.01, 0.05, 0.6))
	# too little mana: a red wash
	var cost := float(Defs.SPELLS[id]["mana"])
	if cost > 0.0 and m.mana < cost:
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.5, 0.05, 0.1, 0.35))
	c.draw_string(font, Vector2(1, 8), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, Color(OUTLINE, 0.9))
	c.draw_string(font, Vector2(0, 7), str(k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, GOLD if k == game.sel else DIM)

## the satchel: a slot for each material held (click: Conjure places it), the draughts, and the furniture
## carried whole
## B on the planet: the satchel open, with a word on where building went
func open_plans() -> void:
	if not satchel_open:
		toggle_satchel()
	toast("Build from your hand: click a plan in the satchel (Plans) and Conjure raises it. Taking away is the Unmake spell; Shift + right-click takes furniture whole.", Color(0.95, 0.85, 0.55), 5.0)

func toggle_satchel() -> void:
	satchel_open = not satchel_open
	_discard = {}
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
	ik += "d" + str(_discard)
	ik += "s%s%s" % [str(g.ships().keys()), g.ship_class()]
	for did0 in Defs.DRAUGHTS:
		ik += "%s%d%s" % [did0, int(g.items.get(did0, 0)), "*" if g.player.buffs.has(did0) else ""]
	for sk0 in g.items.keys():
		if String(sk0).begins_with("sigil_") or String(sk0).begins_with("st_"):
			ik += "%s%d" % [sk0, int(g.items[sk0])]
	if ik == _inv_key:
		return
	_inv_key = ik
	for c in satchel.get_children():
		satchel.remove_child(c)
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
	# open: sections, each sorted by name (user, 23 Nov: "its a little convoluted with everything"): what
	# Conjure lays, what grows, ores and ingots, what you set down whole (click: in your hand, build mode on
	# it), draughts and sigils. The name of what the pointer's over shows under it.
	if not _discard.is_empty():
		_discard_bar(g)
	var groups := [[], [], [], [], []]
	for m in Defs.NM:
		if g.player.inv[m] <= 0 or Defs.KIND[m] == Defs.K_EMPTY or m == Defs.TORCH or m == Defs.WOODDOOR:
			continue                     # (torches and doors are set down whole: below)
		groups[_sat_group(m)].append(m)
	for gi in 4:
		(groups[gi] as Array).sort_custom(func(x, y): return String(Defs.NAMES[x]) < String(Defs.NAMES[y]))
	var n := 0
	for gi2 in 4:
		if (groups[gi2] as Array).is_empty():
			continue
		var gr := _sat_section(["Blocks", "Nature", "Ores & ingots", "Rare finds & parts"][gi2])
		for m2 in groups[gi2]:
			var can: bool = Defs.PLACE[m2] != 0
			var use_t := "Click: Conjure places it\nRight-click: pin it to the belt" if can else "Kept for forging and trade"
			if Defs.is_reagent(m2):
				use_t = Defs.reagent_where(m2) + "\nFor the better gear, and reforging it at an anvil"
			elif Defs.is_part(m2):
				use_t = "A part made at a workshop: gear is built from it"
			var tip := "%s  ×%d\n%s\nShift + right-click: discard" % [Defs.NAMES[m2], g.player.inv[m2], use_t]
			var sl := _sat_slot(gr, Icons.mat(m2), _count(g.player.inv[m2]), m2 == g.mat, tip, String(Defs.NAMES[m2]))
			if can:
				sl.gui_input.connect(_on_mat_input.bind(m2))
			else:
				var m3: int = m2
				sl.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and ev.shift_pressed:
						_ask_discard({"what": "mat", "m": m3}))
			n += 1
	# plans you know (Build.plans): never used up, raised by Conjure from your materials
	var gpl: GridContainer = null
	for plx in Build.plans():
		var pid := String(plx[0])
		if not g.knows_plan(pid):
			continue
		if gpl == null:
			gpl = _sat_section("Plans")
		var held: bool = String(g.hand_item.get("what", "")) == "plan" and String(g.hand_item.get("id", "")) == pid
		var psl0 := _sat_slot(gpl, Icons.plan(pid), "", held, "%s plan\n%s\nClick: in your hand, Conjure raises it\nRight-click: pin it to the belt" % [plx[1], plx[3]], String(plx[1]))
		psl0.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				game.hold_plan(pid)
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				game.belt_pin("p:" + pid))
		n += 1
	# your ships (user, 25 Nov: classes forged at the Wisp Forge, "you keep the ones you've forged and swap
	# between them"): click one to fly it
	if g.ships().size() > 0:
		var gsh := _sat_section("Ships")
		for shk in Skiff.CLASSES:
			if not g.ships().has(shk):
				continue
			var cd: Dictionary = Skiff.CLASSES[shk]
			var on: bool = g.ship_class() == shk
			var stip := "%s%s\nspeed x%.2f · armour x%.1f · %d crates · %d gun%s\n%s%s" % [cd["name"], "  (flying)" if on else "",
				float(cd["speed"]), float(cd["armour"]), int(cd["cargo"]), int(cd["guns"]), "" if int(cd["guns"]) == 1 else "s",
				cd["desc"], "" if on else "\nClick: fly this one (off the ship)"]
			var ssl := _sat_slot(gsh, Icons.thing("ship_" + shk), "", on, stip, String(cd["name"]))
			ssl.gui_input.connect(_on_ship_input.bind(shk))
			n += 1
	# set down whole: torches, doors, furniture, workshops
	var placing := []
	if g.player.inv[Defs.TORCH] > 0:
		placing.append(["torch", -1, "", Icons.mat(Defs.TORCH), g.player.inv[Defs.TORCH], "Torch"])
	if g.player.inv[Defs.WOODDOOR] > 0:
		placing.append(["door", -1, "", Icons.mat(Defs.WOODDOOR), g.player.inv[Defs.WOODDOOR], "Door"])
	var fc := {}
	var ffirst := {}
	var frows := {}
	var forder := []
	for fk in g.player.furn.size():
		var it: Dictionary = g.player.furn[fk]
		var fn: String = it["name"]
		if not fc.has(fn):
			fc[fn] = 0
			ffirst[fn] = fk
			forder.append(fn)
			frows[fn] = it.get("rows", [])
		fc[fn] = int(fc[fn]) + 1
	forder.sort()
	for fn2 in forder:
		var fic: Texture2D = Icons.prop_rows(frows[fn2]) if not (frows[fn2] as Array).is_empty() else Icons.item("chair")
		placing.append(["furn", int(ffirst[fn2]), "", fic, int(fc[fn2]), fn2])
	for sk0 in Defs.STATIONS:
		var ns := int(g.items.get("st_" + String(sk0), 0))
		if ns > 0:
			placing.append(["station", -1, String(sk0), Icons.station(String(sk0)), ns, String(Defs.STATIONS[sk0]["name"])])
	if not placing.is_empty():
		var gp := _sat_section("To set down")
		for pl in placing:
			var psl := _sat_slot(gp, pl[3], str(pl[4]), false, "%s  ×%d\nClick: in your hand, to set down\nRight-click: pin it to the belt\nShift + right-click: discard" % [pl[5], pl[4]], String(pl[5]))
			psl.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					game.hold_carried(String(pl[0]), int(pl[1]), String(pl[2]))
				elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT and ev.shift_pressed:
					match String(pl[0]):
						"torch": _ask_discard({"what": "mat", "m": Defs.TORCH})
						"door": _ask_discard({"what": "mat", "m": Defs.WOODDOOR})
						"furn": _ask_discard({"what": "furn", "name": String(pl[5])})
						"station": _ask_discard({"what": "station", "sk": String(pl[2])})
				elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					game.belt_pin(_place_id(pl)))
			n += 1
	# draughts and sigils
	var used := []
	var np := int(g.items.get("potion", 0))
	if np > 0:
		used.append([Icons.item("potion"), np, "Healing Draught  ×%d\nH to drink" % np, "Healing Draught", ""])
	for did in Defs.DRAUGHTS:
		var nd := int(g.items.get(did, 0))
		if nd > 0:
			used.append([Icons.draught(did), nd, "%s  ×%d\n%s\nClick to drink" % [Defs.DRAUGHTS[did]["name"], nd, Defs.DRAUGHTS[did]["desc"]], String(Defs.DRAUGHTS[did]["name"]), String(did)])
	for sk in g.items.keys():
		if String(sk).begins_with("sigil_") and int(g.items[sk]) > 0 and Defs.BOSSES.has(String(sk).substr(6)):
			var sb2: String = String(sk).substr(6)
			used.append([Icons.thing(String(sk)), int(g.items[sk]), "%s  ×%d\nLay it on a Summoning Altar in the %s (F) to call %s" % [Defs.sigil_name(sb2), int(g.items[sk]), String(Defs.BIOMES[sb2]["name"]) if Defs.BIOMES.has(sb2) else sb2, Defs.BOSSES[sb2]["name"]], Defs.sigil_name(sb2), ""])
	# artifacts to study (27 Nov): at a Lectern
	var arts: Array = g.items.get("artifacts", [])
	if not arts.is_empty():
		var ga := _sat_section("Artifacts")
		for ak in arts.size():
			var a: Dictionary = arts[ak]
			_sat_slot(ga, Icons.artifact(a), "", false, "%s\nFrom a %s world. Lay it on a Lectern (F) and study it to learn what its makers knew" % [String(a["n"]), "deep ocean" if String(a["k"]) == "abyss" else String(a["k"])], String(a["n"]))
			n += 1
	if not used.is_empty():
		var gu := _sat_section("Draughts & sigils")
		for u in used:
			var usl := _sat_slot(gu, u[0], str(u[1]), String(u[4]) != "" and g.player.buffs.has(String(u[4])), u[2], String(u[3]))
			if String(u[4]) != "":
				usl.gui_input.connect(func(ev: InputEvent):
					if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
						game.drink_draught(game.player, String(u[4]))
						_inv_key = "")
			n += 1
	satchel_slots = n
	if n == 0:
		satchel.add_child(_label("Right-click to dig", 11, DIM))
	var hh := 0.0
	for ch in satchel.get_children():
		if ch is GridContainer:
			hh += ceilf(float((ch as GridContainer).get_child_count()) / float(SAT_COLS)) * 27.0 + 2.0
		else:
			hh += 13.0
	_satchel_scroll.custom_minimum_size.y = minf(maxf(hh, 20.0), maxf(80.0, root.size.y - 140.0))

## which section of the open satchel a material goes in: 0 blocks, 1 nature, 2 ores and ingots
func _sat_group(m: int) -> int:
	if Defs.is_reagent(m) or Defs.is_part(m):
		return 3
	if m in [Defs.WOOD, Defs.LEAF, Defs.SHROOM, Defs.CACTUS, Defs.TIMBER, Defs.LITTER, Defs.CAP, Defs.STALK,
			Defs.DRYGRASS, Defs.ROOT, Defs.GRASS]:
		return 1
	if m in [Defs.COPPER, Defs.COAL, Defs.WISP, Defs.EMBER, Defs.FROST, Defs.CRYSTAL, Defs.STARIRON, Defs.CORE,
			Defs.COPPERBAR, Defs.WISPBAR, Defs.XENITE, Defs.WISPCELL, Defs.VOIDESS, Defs.TREASURE] \
			or (m >= Defs.FIREOPAL and m <= Defs.SILVER) or Defs.is_kind_core(m):
		return 2
	return 0

## a section of the open satchel: its heading and its grid
func _sat_section(title: String) -> GridContainer:
	var h := _label(title, 11, Color(0.95, 0.8, 0.5))
	satchel.add_child(h)
	var gr := GridContainer.new()
	gr.columns = SAT_COLS
	gr.add_theme_constant_override("h_separation", 1)
	gr.add_theme_constant_override("v_separation", 1)
	satchel.add_child(gr)
	return gr

## a slot in the open satchel: its name shows under the satchel while the pointer's over it
func _sat_slot(gr: GridContainer, t: Texture2D, count: String, chosen: bool, tip: String, nm: String) -> PanelContainer:
	var sl := _slot(t, count, chosen, tip)
	sl.mouse_entered.connect(func(): _sat_name.text = nm)
	sl.mouse_exited.connect(func():
		if _sat_name.text == nm:
			_sat_name.text = " ")
	gr.add_child(sl)
	return sl

# ------------------------------------------------------------------ forge --
## (user, 25 Nov: "When forging large amounts in the wisp forge like 10 or more the game gets very sluggish": every
## Forge click built all ~150 cards again, about a fifth of a second with the layout after; now a click updates the
## cards in place, `_refresh_forge`, and they're built again only when what's listed changes, `_forge_key`)
var _cards := []          # the forge's cards: {r, b (its button), p (its panel), chips [[label, material, need]], live}
var _forge_key := ""

func _forge_shape() -> String:
	var parts := PackedStringArray()
	for r in game.recipes:
		if game.recipe_hidden(r) or not game.knows(r):
			continue
		parts.append("%s%s%s" % [r["id"], "d" if game.recipe_done(r) else "", "u" if game.recipe_unlocked(r) else ""])
	for wk in ["kiln", "smelter", "still"]:
		parts.append(str(game.workshops.known_recipes(wk).size()))
	return ",".join(parts)

## after forging: the cards' costs, buttons and frames as they are now (all of it built again if what's listed
## changed: a recipe learned, one forged for good)
func _refresh_forge() -> void:
	if not forge.visible:
		return
	if _forge_shape() != _forge_key:
		_rerender_forge()
		return
	for cd in _cards:
		for ch in cd["chips"]:
			var lbl: Label = ch[0]
			if not is_instance_valid(lbl):
				continue
			var have: int = game.inv[int(ch[1])]
			lbl.text = "%s/%d" % [_count(have), int(ch[2])]
			lbl.add_theme_color_override("font_color", GOOD if have >= int(ch[2]) else BAD)
		if not cd.has("b") or not bool(cd["live"]) or not is_instance_valid(cd["b"]):
			continue
		var r: Dictionary = cd["r"]
		var aff: bool = game.recipe_affordable(r)
		var bt: Button = cd["b"]
		bt.disabled = not aff
		bt.text = _forge_text(r)
		(cd["p"] as PanelContainer).add_theme_stylebox_override("panel", _frame(Color(0.08, 0.065, 0.14, 0.97), MANA if aff else TRIM_DIM, 3))

func _render_forge() -> void:
	_cards = []
	_forge_key = _forge_shape()
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
			grid.add_child(_plan_card(r) if r.has("plan") else _recipe_card(r))
		# its tab: how many of its recipes you could forge now
		var n_ready := 0
		for r2 in cats[cat]:
			if not r2.has("plan") and not game.recipe_done(r2) and game.recipe_unlocked(r2) and game.recipe_affordable(r2):
				n_ready += 1
		var tb := _button(cat + (" ·%d" % n_ready if n_ready > 0 else ""))
		if n_ready > 0:
			tb.add_theme_color_override("font_color", GOOD)
		tb.pressed.connect(func():
			_forge_scroll.scroll_vertical = int(ch.position.y))
		forge_tabs.add_child(tb)
	# what the workshops make (user, 25 Nov: "some recipes are in the smelter and other workshops but not in
	# the recipe book"): a section per workshop, a card per mix it knows; secrets not yet found are pages below
	var ws = game.workshops
	for wk in ["kiln", "smelter", "still"]:
		var known_pr: Array = ws.known_recipes(wk)
		for prs in Defs.PROCESS:
			if prs["at"] == wk and prs.get("secret", false) and not ws.is_secret_known(String(prs["id"])):
				book.append({"process": prs})
		if known_pr.is_empty():
			continue
		var wname := "%s (workshop)" % String(Defs.STATIONS[wk]["name"])
		var wh := _box(false, 4)
		wh.add_child(_head(wname, 12, Color(0.95, 0.75, 0.5)))
		var wr := _rule(50)
		wr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wh.add_child(wr)
		forge_list.add_child(wh)
		var wg := GridContainer.new()
		wg.columns = _forge_cols
		wg.add_theme_constant_override("h_separation", 4)
		wg.add_theme_constant_override("v_separation", 4)
		forge_list.add_child(wg)
		for prk in known_pr:
			wg.add_child(_process_card(prk))
			n_known += 1
		var wt := _button(String(Defs.STATIONS[wk]["name"]))
		wt.add_theme_color_override("font_color", Color(0.95, 0.75, 0.5))
		wt.pressed.connect(func():
			_forge_scroll.scroll_vertical = int(wh.position.y))
		forge_tabs.add_child(wt)
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
			bg.add_child(_secret_page(r3["process"]) if (r3 as Dictionary).has("process") else _book_page(r3))
	var bh: Control = _book_head
	var bt := _button("Recipe Book")
	bt.pressed.connect(func():
		_forge_scroll.scroll_vertical = int(bh.position.y))
	forge_tabs.add_child(bt)

## a recipe's icon: the spell's glyph, what it makes, its own picture (Icons.THINGS), the piece of
## furniture itself, its ore, or a scroll
func _recipe_icon(r: Dictionary) -> Texture2D:
	if r.has("plan"):
		return Icons.plan(String(r["plan"]))
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

## what a workshop makes, as a page of the forge's book: what goes in, what comes out, where and how
func _process_card(pr: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(Color(0.08, 0.06, 0.1, 0.97), Color(0.55, 0.38, 0.25), 3))
	p.custom_minimum_size = Vector2(148, 0)
	var v := _box(true, 2)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(v)
	var top := _box(false, 3)
	v.add_child(top)
	var po: Array = Defs.process_out(pr)
	var ok_key: String = "m%d" % int((pr["give"] as Dictionary).keys()[0]) if pr.has("give") else String(pr["item"])
	top.add_child(_tex(_out_icon(ok_key.substr(5) if ok_key.begins_with("gear:") else ok_key)))
	var nm := _head("%s%s" % [String(po[0]), (" ×%d" % int(po[2])) if int(po[2]) > 1 else ""], 12, CREAM)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.custom_minimum_size.x = 120
	top.add_child(nm)
	var sname := String(Defs.STATIONS[pr["at"]]["name"])
	var how := "Made at a %s: load what goes in (or click it in the %s's list), feed its fire, and it works over %d s." % [sname, sname.to_lower(), int(ceil(float(pr["ticks"]) / 60.0))]
	if pr.get("night", false):
		how += " Only after dark."
	if pr.get("secret", false):
		how = "A secret you found. " + how
	var dl := _label(how, 11, Color(0.75, 0.7, 0.62))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dl.custom_minimum_size = Vector2(138, 0)
	v.add_child(dl)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)
	var costs := HFlowContainer.new()
	costs.add_theme_constant_override("h_separation", 5)
	costs.add_theme_constant_override("v_separation", 1)
	v.add_child(costs)
	for k in pr["in"]:
		var pchip := _cost_chip(int(k), int(pr["in"][k]))
		costs.add_child(pchip)
		_cards.append({"chips": [[pchip.get_child(1), int(k), int(pr["in"][k])]]})
	var at := _label("at the %s" % sname, 11, Color(0.95, 0.75, 0.5))
	v.add_child(at)
	# (user, 25 Nov: "Send to the Kiln"): loads the nearest one in reach from your satchel
	var near_st = game.workshops.nearest_kind(String(pr["at"]), game.player)
	var pkey := "p:" + String(pr["id"])
	var send_text := func() -> String:
		return ("Send to the %s" % sname) + (" ×%d" % amount_of(pkey) if amount_of(pkey) > 1 else "")
	var sb := _button(send_text.call() if near_st != null else "No %s near" % sname)
	sb.disabled = near_st == null
	if near_st != null:
		sb.pressed.connect(_on_send.bind(pr))
		var srow := _box(false, 3)
		srow.mouse_filter = Control.MOUSE_FILTER_PASS
		srow.add_child(_amount_box(pkey, func(): sb.text = send_text.call()))
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		srow.add_child(sb)
		v.add_child(srow)
	else:
		v.add_child(sb)
	return p

func _on_send(pr: Dictionary) -> void:
	if game.workshops.send(pr, amount_of("p:" + String(pr["id"]))) > 0:
		_inv_key = ""
		_hot_key = ""
		if game.state == "forge":
			_refresh_forge()

## a workshop's secret not yet found: a page with its riddle once you've heard it
func _secret_page(pr: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(Color(0.06, 0.05, 0.1, 0.97), TRIM_DIM, 3))
	p.custom_minimum_size = Vector2(148, 0)
	var v := _box(true, 2)
	p.add_child(v)
	var sname := String(Defs.STATIONS[pr["at"]]["name"])
	v.add_child(_label("A secret of the %s" % sname, 12, Color(0.62, 0.6, 0.72)))
	var heard: bool = game.items.has("hint_" + String(pr["id"]))
	var hl := _label(("\"%s\"" % String(pr["hint"])) if heard else "Found by trying mixes at a %s. Villagers and torn notes tell riddles of it." % sname.to_lower(), 11, Color(0.85, 0.7, 1.0) if heard else DIM)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD
	hl.custom_minimum_size = Vector2(138, 0)
	v.add_child(hl)
	return p

## A page of the book not yet learned (user, 25 Nov: "locked pages show smudged sketches"): a parchment page
## with the thing sketched in ink (`Icons.sketch`), its name in faded ink and where it's found
const PAGE := Color(0.74, 0.66, 0.49, 0.96)
const PAGE_INK := Color(0.3, 0.21, 0.13)

func _book_page(r: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(PAGE, Color(0.45, 0.33, 0.2), 3))
	p.custom_minimum_size = Vector2(148, 0)
	var v := _box(true, 2)
	p.add_child(v)
	var top := _box(false, 3)
	v.add_child(top)
	var ic := _tex(Icons.sketch(_recipe_icon(r)))
	top.add_child(ic)
	var nm := _label(String(r["name"]), 12, PAGE_INK)
	nm.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.custom_minimum_size.x = 120
	top.add_child(nm)
	var hl := _label(Defs.learn_hint(r), 11, Color(PAGE_INK.r, PAGE_INK.g, PAGE_INK.b, 0.75))
	hl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD
	hl.custom_minimum_size = Vector2(138, 0)
	v.add_child(hl)
	return p

## a plan you know, as a page of the book: what it raises, and a button that puts it in your hand
func _plan_card(r: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(Color(0.06, 0.08, 0.15, 0.97), Color(0.35, 0.55, 0.85), 3))
	p.custom_minimum_size = Vector2(148, 0)
	var v := _box(true, 2)
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	p.add_child(v)
	var top := _box(false, 3)
	v.add_child(top)
	top.add_child(_tex(_recipe_icon(r)))
	var nm := _head(String(r["name"]) + " plan", 12, CREAM)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD
	nm.custom_minimum_size.x = 120
	top.add_child(nm)
	var dl := _label(String(r.get("desc", "")), 11, Color(0.7, 0.8, 0.95))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dl.custom_minimum_size = Vector2(138, 0)
	v.add_child(dl)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)
	v.add_child(_label("Known: in your satchel's Plans", 11, Color(0.6, 0.75, 1.0)))
	var b := _button("Hold it")
	var pid := String(r["plan"])
	b.pressed.connect(func():
		if game.state == "forge":
			game.toggle_forge()
		game.hold_plan(pid))
	v.add_child(b)
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
	# a page learned since the book was last opened inks itself in (once), and says so
	var rid := String(r.get("id", ""))
	if _inking.has(rid):
		var tag := _label("New page", 11, GOLD)
		v.add_child(tag)
		v.move_child(tag, 0)
		if not _inked.has(rid):
			_inked[rid] = true
			p.modulate = Color(0.55, 0.45, 0.3, 0.25)
			var tw := p.create_tween()
			tw.tween_interval(0.15 + 0.12 * float(_inked.size() - 1))
			tw.tween_property(p, "modulate", Color(1, 1, 1, 0.55 if done else 1.0), 1.2)
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
	if r.has("gear") and not done and unlocked:
		# (27 Nov: rolled traits, better where it's forged better)
		var ql := _label(game.forge_quality_text(String(r["id"])), 10, MANA)
		ql.autowrap_mode = TextServer.AUTOWRAP_WORD
		ql.custom_minimum_size = Vector2(138, 0)
		v.add_child(ql)
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
	var chips := []
	for k in r["cost"]:
		var chip := _cost_chip(int(k), int(r["cost"][k]))
		costs.add_child(chip)
		chips.append([chip.get_child(1), int(k), int(r["cost"][k])])
	# every card ends in a button of the same size: Forge, or greyed out saying why not
	var b := _button("Forged" if done else ("Locked" if not unlocked else _forge_text(r)))
	b.disabled = done or not unlocked or not aff
	if not done and unlocked:
		b.pressed.connect(_on_craft.bind(r))
	# (a ship you've forged: the forge grows it another look from its parts, free)
	var shk := String(r.get("ship", "skiff" if rid == "skiff" else ""))
	if done and shk != "" and game.ships().has(shk):
		p.modulate.a = 1.0
		b.text = "Another look"
		b.disabled = false
		b.tooltip_text = "Grow this ship another look from its parts (its class and stats stay)"
		b.pressed.connect(_on_reshape.bind(shk))
	if not done and unlocked and game.recipe_repeatable(r):
		# its own amount beside its button
		var brow := _box(false, 3)
		brow.mouse_filter = Control.MOUSE_FILTER_PASS
		brow.add_child(_amount_box(rid, func(): b.text = _forge_text(r)))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		brow.add_child(b)
		v.add_child(brow)
	else:
		v.add_child(b)
	_cards.append({"r": r, "b": b, "p": p, "chips": chips, "live": not done and unlocked})
	return p

func _on_hot_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		game.sel = idx

## the belt's id for a "To set down" entry [what, idx, sk, ...]
func _place_id(pl: Array) -> String:
	match String(pl[0]):
		"torch":
			return "m%d" % Defs.TORCH
		"door":
			return "m%d" % Defs.WOODDOOR
		"furn":
			return "f:" + String(game.player.furn[int(pl[1])]["name"])
	return "s:" + String(pl[2])

func _on_ship_input(ev: InputEvent, shk: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if game.switch_ship(shk):
			_inv_key = ""

func _on_mat_input(ev: InputEvent, m: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		game.select_material(m)
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
		if ev.shift_pressed:
			_ask_discard({"what": "mat", "m": m})
		else:
			game.belt_pin("m%d" % m)             # (pinned to the item belt)

## Shift + right-click on a slot: the bar at the top of the satchel asks how many to let go of
func _ask_discard(d: Dictionary) -> void:
	_discard = d
	_inv_key = ""
	_sfx("ui_click")

## what the discard bar is about: [name, how many you have, icon]
func _discard_info(g) -> Array:
	match String(_discard.get("what", "")):
		"mat":
			var m: int = _discard["m"]
			return [String(Defs.NAMES[m]), g.player.inv[m], Icons.mat(m)]
		"furn":
			var fname := String(_discard["name"])
			var nf := 0
			for it in g.player.furn:
				if String(it["name"]) == fname:
					nf += 1
			return [fname, nf, Icons.item("chair")]
		"station":
			var sk := String(_discard["sk"])
			return [String(Defs.STATIONS[sk]["name"]) if Defs.STATIONS.has(sk) else sk, int(g.items.get("st_" + sk, 0)), Icons.station(sk)]
	return ["", 0, null]

## the discard bar (27 Nov; user: "no way to destroy unwanted inventory items ... or just drop them"): what, how
## many you have, and how many to let go of (1, 10, 100, half, all), or keep them
func _discard_bar(g) -> void:
	var info := _discard_info(g)
	var have: int = info[1]
	if have <= 0:
		_discard = {}
		return
	var bar := _box(false, 3)
	if info[2] != null:
		bar.add_child(_tex(info[2]))
	bar.add_child(_label("Discard %s (%s):" % [info[0], _count(have)], 11, Color(1.0, 0.72, 0.6)))
	var opts := []
	for q in [1, 10, 100]:
		if q < have:
			opts.append([str(q), q])
	if have >= 4:
		opts.append(["half", have / 2])
	opts.append(["all", have])
	for o in opts:
		var b := _button(String(o[0]))
		var cnt: int = o[1]
		b.pressed.connect(func():
			var d := _discard
			game.discard(String(d.get("what", "")), int(d.get("m", -1)), String(d.get("name", "")), String(d.get("sk", "")), cnt)
			if String(o[0]) == "all":
				_discard = {}
			_inv_key = "")
		bar.add_child(b)
	var keep := _button("keep")
	keep.pressed.connect(func():
		_discard = {}
		_inv_key = "")
	bar.add_child(keep)
	satchel.add_child(bar)

func _on_reshape(shk: String) -> void:
	game.reshape_ship(shk)
	_render_forge()

func _on_craft(r: Dictionary) -> void:
	var ok: bool = game.craft_many(r, amount_of(String(r.get("id", "")))) > 0
	_inv_key = ""
	_hot_key = ""
	if ok and game.state == "forge":
		_refresh_forge()

func _set_panel_style(p: PanelContainer, sb: StyleBox) -> void:
	if is_instance_valid(p):
		p.add_theme_stylebox_override("panel", sb)

## a control's rectangle on the screen (the UI is scaled, so get_global_rect alone isn't)
static func _on_screen(c: Control) -> Rect2:
	return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)

## the pointer over the minimap? (user, 26 Nov: in space "the cursor doesnt change when hovering over the minimap it
## goes behind it"): the pointer shows there instead of the reticle, and the wheel zooms it
func mouse_over_minimap() -> bool:
	return minimap_panel != null and minimap_panel.is_visible_in_tree() and _on_screen(minimap_panel).has_point(get_viewport().get_mouse_position())

## True when the pointer is over a clickable HUD element (satchel, spell slots; with
## `slots` false, only the panels: the wheel still picks a spell over the slots).
func mouse_over_ui(slots := true) -> bool:
	if settings_panel and settings_panel.visible:
		return true
	if shipyard_panel and shipyard_panel.visible and _on_screen(shipyard_panel).has_point(get_viewport().get_mouse_position()):
		return true
	if hud == null or not hud.visible:
		return false
	var m := get_viewport().get_mouse_position()
	if satchel_panel and _on_screen(satchel_panel).has_point(m):
		return true
	if mouse_over_minimap():
		return true                         # (the pointer shows over it, and a click there never casts)
	if slots and hotbar and hotbar.is_visible_in_tree() and _on_screen(hotbar).has_point(m):
		return true
	if build_bar and build_bar.visible and _on_screen(build_bar).has_point(m):
		return true
	if belt_pan and belt_pan.is_visible_in_tree() and _on_screen(belt_pan).has_point(m):
		return true                         # (the item belt over the spell bar)
	return false
