extends CanvasLayer
## HUD, satchel, hotbar, toasts, forge panel, title / death / loading screens.
##
## Everything shares one look: dark indigo panels inside a gold pixel frame (a small 9-slice
## texture drawn in code, so the trim stays crisp at any size), serif headings, gold text.

const TitleScreen := preload("res://scripts/title_screen.gd")
const Build := preload("res://scripts/build.gd")

var game
var root: Control
var hud: Control
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var br_bar: ProgressBar
var br_row: Control
var hp_lbl: Label
var mp_lbl: Label
var info: Label
var hotbar: HBoxContainer
var build_bar: PanelContainer      # build mode: categories, pieces and what the chosen one costs
var build_box: VBoxContainer
var _build_key := ""
var satchel: VBoxContainer
var satchel_panel: PanelContainer
var death_txt: Label
var _to_title_btn: Button
var toasts: VBoxContainer
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_lbl: Label
var dig_warn: Label
var forge: PanelContainer
var map_bar: PanelContainer
var map_title: Label
var map_hint: Label
var forge_list: VBoxContainer
var shop: PanelContainer         # a village keeper's shop (towns.gd)
var shop_list: VBoxContainer
var shop_title: Label
var shop_coins: Label
var _shop_v = null
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
var _serif: SystemFont
var _loading_base := ""
var _t := 0.0

const GOLD := Color(1, 0.82, 0.23)
const CREAM := Color(1, 0.93, 0.7)
const DIM := Color(0.62, 0.62, 0.78)
const TEXT := Color(0.88, 0.89, 1)
const PANEL_BG := Color(0.055, 0.045, 0.1, 0.93)
const TRIM := Color(0.8, 0.6, 0.24)
const TRIM_DIM := Color(0.36, 0.31, 0.5)
const OUTLINE := Color(0.03, 0.02, 0.06)

const ICONS := {
	"heart": [".XX.XX.", "XoXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."],
	"drop": ["..X..", "..X..", ".XXX.", "XoXXX", "XoXXX", "XXXXX", ".XXX."],
	"bubble": [".XXX.", "Xo..X", "X...X", "X...X", ".XXX."],
	"skull": [".XXX.", "XXXXX", "X.X.X", "XXXXX", ".X.X."],
}

func _ready() -> void:
	layer = 10
	_serif = SystemFont.new()
	_serif.font_names = PackedStringArray(["Constantia", "Palatino Linotype", "Book Antiqua", "Georgia", "Cambria", "DejaVu Serif", "serif"])
	_serif.font_weight = 600
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_hud()
	_build_forge()
	_build_shop()
	_build_map_bar()
	_build_screens()

func _process(delta: float) -> void:
	_t += delta
	if loading and loading.visible:
		loading_lbl.text = _loading_base + ".".repeat(int(_t * 3.0) % 4)

# ---------------------------------------------------------------- style --
## A pixel frame: dark outline, gold trim, a darker inner trim and little studs at the corners,
## drawn at 2 screen pixels per art pixel and used as a 9-slice.
func _frame(bg: Color, trim: Color, pad := 8, pad_x := -1) -> StyleBoxTexture:
	if pad_x < 0:
		pad_x = pad
	var key := "%s|%s|%d|%d" % [bg.to_html(), trim.to_html(), pad, pad_x]
	if _frames.has(key):
		return _frames[key]
	var n := 12
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var inner := trim.darkened(0.55)
	var stud := trim.lightened(0.55)
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
			elif ring == 2:
				c = inner
			if (x == 2 or x == n - 3) and (y == 2 or y == n - 3):
				c = stud
			img.set_pixel(x, y, c)
	img.resize(n * 2, n * 2, Image.INTERPOLATE_NEAREST)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.set_texture_margin_all(6)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	_frames[key] = sb
	return sb

func _panel(bg := PANEL_BG, trim := TRIM, pad := 10) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(bg, trim, pad))
	return p

## Kept for callers that want a plain frame style.
func _panel_style(bg: Color, border: Color) -> StyleBox:
	return _frame(bg, border, 6)

## Bar fill: a base colour with a bright top edge and a shaded bottom, so bars read as glass tubes.
func _fill(col: Color) -> StyleBoxTexture:
	var img := Image.create(2, 6, false, Image.FORMAT_RGBA8)
	var rows := [col.lightened(0.45), col.lightened(0.15), col, col.darkened(0.15), col.darkened(0.3), col.darkened(0.45)]
	for y in 6:
		for x in 2:
			img.set_pixel(x, y, rows[y])
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_top = 2
	sb.texture_margin_bottom = 3
	return sb

func _make_theme() -> Theme:
	var th := Theme.new()
	var grab := StyleBoxFlat.new()
	grab.bg_color = TRIM
	grab.content_margin_left = 4
	grab.content_margin_right = 4
	var grab_h: StyleBoxFlat = grab.duplicate()
	grab_h.bg_color = GOLD
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.03, 0.02, 0.06, 0.6)
	track.content_margin_left = 4
	track.content_margin_right = 4
	th.set_stylebox("grabber", "VScrollBar", grab)
	th.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	th.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	th.set_stylebox("scroll", "VScrollBar", track)
	th.set_stylebox("panel", "TooltipPanel", _frame(Color(0.06, 0.05, 0.11, 0.97), TRIM, 6))
	th.set_color("font_color", "TooltipLabel", TEXT)
	return th

func _icon(key: String, col: Color, zoom := 2) -> TextureRect:
	var rows: Array = ICONS[key]
	var w: int = rows[0].length()
	var h: int = rows.size()
	var img := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		var row: String = rows[y]
		for x in w:
			if row[x] == "X":
				img.set_pixel(x + 1, y + 1, col)
			elif row[x] == "o":
				img.set_pixel(x + 1, y + 1, col.lightened(0.6))
	# outline
	var src: Image = img.duplicate()
	for y in h + 2:
		for x in w + 2:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < w + 2 and q.y < h + 2 and src.get_pixel(q.x, q.y).a > 0.0:
					img.set_pixel(x, y, OUTLINE)
					break
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.custom_minimum_size = Vector2(w + 2, h + 2) * zoom
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

# ------------------------------------------------------------- builders --
func _bar(col: Color, h := 16) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(220, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.025, 0.06)
	bg.border_color = OUTLINE
	bg.set_border_width_all(2)
	bg.set_content_margin_all(2)
	var fg := _fill(col)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

func _label(txt: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A heading in the serif face, with a deeper shadow.
func _head(txt: String, size: int, col := CREAM) -> Label:
	var l := _label(txt, size, col)
	l.add_theme_font_override("font", _serif)
	l.add_theme_color_override("font_shadow_color", Color(0.18, 0.08, 0.3, 1))
	var off := 2 if size >= 20 else 1
	l.add_theme_constant_override("shadow_offset_x", off)
	l.add_theme_constant_override("shadow_offset_y", off)
	return l

## A divider: a thin gold rule with a diamond in the middle.
func _rule(w := 260) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 10)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var mid := c.size * 0.5
		c.draw_rect(Rect2(0, mid.y - 1, c.size.x, 2), Color(TRIM, 0.7))
		c.draw_rect(Rect2(mid.x - 3, mid.y - 3, 6, 6), GOLD)
		c.draw_rect(Rect2(mid.x - 1, mid.y - 1, 2, 2), Color(1, 0.97, 0.8)))
	return c

func _button(txt: String, big := false) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var py := 10 if big else 7
	var px := 22 if big else 12
	b.add_theme_stylebox_override("normal", _frame(Color(0.11, 0.08, 0.18, 0.95), TRIM, py, px))
	b.add_theme_stylebox_override("hover", _frame(Color(0.24, 0.17, 0.36, 0.97), GOLD, py, px))
	b.add_theme_stylebox_override("pressed", _frame(Color(0.07, 0.05, 0.12, 0.97), GOLD, py, px))
	b.add_theme_stylebox_override("disabled", _frame(Color(0.07, 0.07, 0.1, 0.9), Color(0.3, 0.3, 0.36), py, px))
	b.add_theme_font_override("font", _serif)
	b.add_theme_font_size_override("font_size", 22 if big else 14)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 0.98, 0.88))
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.52))
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", 4 if big else 3)
	if big:
		b.custom_minimum_size = Vector2(300, 0)
	b.mouse_entered.connect(func():
		if not b.disabled:
			_sfx("ui_hover")
			b.pivot_offset = b.size * 0.5
			b.create_tween().tween_property(b, "scale", Vector2(1.04, 1.04), 0.08))
	b.mouse_exited.connect(func():
		b.pivot_offset = b.size * 0.5
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.1))
	b.pressed.connect(func(): _sfx("ui_click"))
	return b

## Shows a settings option as chosen (filled gold) or not.
func _set_chosen(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", _frame(Color(0.5, 0.36, 0.1, 0.97), Color(1, 0.88, 0.5), 7, 12))
		b.add_theme_stylebox_override("hover", _frame(Color(0.58, 0.42, 0.14, 0.97), Color(1, 0.94, 0.66), 7, 12))
		b.add_theme_color_override("font_color", Color(1, 0.98, 0.9))
	else:
		b.add_theme_stylebox_override("normal", _frame(Color(0.11, 0.08, 0.18, 0.95), TRIM_DIM, 7, 12))
		b.add_theme_stylebox_override("hover", _frame(Color(0.24, 0.17, 0.36, 0.97), GOLD, 7, 12))
		b.add_theme_color_override("font_color", Color(0.72, 0.7, 0.84))

func _sfx(n: String) -> void:
	if game != null and game.get("audio") != null:
		game.audio.play(n)

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	# the character plate: health, mana, breath and where you are
	var plate := _panel(Color(0.05, 0.04, 0.09, 0.82), TRIM, 9)
	plate.position = Vector2(12, 10)
	plate.custom_minimum_size = Vector2(290, 0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(plate)
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 5)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(bars)
	hp_bar = _bar(Color(0.86, 0.2, 0.26), 18)
	mp_bar = _bar(Color(0.26, 0.42, 0.95), 18)
	br_bar = _bar(Color(0.5, 0.85, 0.92), 10)
	hp_lbl = _label("", 12, Color.WHITE)
	mp_lbl = _label("", 12, Color.WHITE)
	hp_bar.add_child(hp_lbl)
	mp_bar.add_child(mp_lbl)
	# the numbers fill their bar and sit centred in it
	for l in [hp_lbl, mp_lbl]:
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", OUTLINE)
		l.add_theme_constant_override("outline_size", 3)
	for pair in [["heart", Color(0.95, 0.3, 0.35), hp_bar], ["drop", Color(0.4, 0.58, 1.0), mp_bar], ["bubble", Color(0.6, 0.9, 0.95), br_bar]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := _icon(pair[0], pair[1])
		ic.custom_minimum_size.x = 18
		row.add_child(ic)
		row.add_child(pair[2])
		bars.add_child(row)
		if pair[0] == "bubble":
			br_row = row
	bars.add_child(_rule(270))
	info = _label("", 12, Color(0.86, 0.87, 1))
	bars.add_child(info)

	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 4)
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hotbar.position.y -= 12
	hud.add_child(hotbar)

	build_bar = _panel(Color(0.05, 0.04, 0.09, 0.9), TRIM, 8)
	build_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_bar.position.y -= 12
	build_bar.visible = false
	hud.add_child(build_bar)
	build_box = VBoxContainer.new()
	build_box.add_theme_constant_override("separation", 4)
	build_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_bar.add_child(build_box)

	var sw := _panel(Color(0.05, 0.04, 0.09, 0.85), TRIM, 9)
	sw.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sw.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sw.position = Vector2(-12, 10)
	sw.custom_minimum_size = Vector2(210, 40)
	hud.add_child(sw)
	satchel_panel = sw
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 4)
	sw.add_child(sv)
	var sh := _head("Satchel", 17)
	sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(sh)
	sv.add_child(_rule(190))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(192, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	satchel = VBoxContainer.new()
	satchel.add_theme_constant_override("separation", 1)
	satchel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(satchel)
	scroll.custom_minimum_size.y = 400

	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.position.y = 12
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	toasts.add_theme_constant_override("separation", 3)
	root.add_child(toasts)

	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_box.position.y = 140
	boss_box.visible = false
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(boss_box)
	var bp := _panel(Color(0.08, 0.03, 0.04, 0.85), Color(0.85, 0.42, 0.2), 8)
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_child(bp)
	var bv := VBoxContainer.new()
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.add_child(bv)
	var bh := HBoxContainer.new()
	bh.alignment = BoxContainer.ALIGNMENT_CENTER
	bh.add_theme_constant_override("separation", 8)
	bv.add_child(bh)
	bh.add_child(_icon("skull", Color(0.95, 0.85, 0.7)))
	boss_lbl = _head("Vulkhar, the Ember Golem", 18, Color(1, 0.72, 0.36))
	bh.add_child(boss_lbl)
	bh.add_child(_icon("skull", Color(0.95, 0.85, 0.7)))
	boss_bar = _bar(Color(1, 0.5, 0.18), 14)
	boss_bar.custom_minimum_size = Vector2(440, 14)
	bv.add_child(boss_bar)

	dig_warn = _label("Too hard for your staff. Forge a stronger focus (C)", 13, Color(1, 0.72, 0.62))
	dig_warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dig_warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dig_warn.position.y -= 96
	dig_warn.visible = false
	dig_warn.add_theme_color_override("font_outline_color", OUTLINE)
	dig_warn.add_theme_constant_override("outline_size", 4)
	hud.add_child(dig_warn)


func _build_forge() -> void:
	forge = _panel(Color(0.05, 0.04, 0.09, 0.97), TRIM, 14)
	forge.set_anchors_preset(Control.PRESET_CENTER)
	forge.custom_minimum_size = Vector2(900, 610)
	forge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	forge.grow_vertical = Control.GROW_DIRECTION_BOTH
	forge.visible = false
	root.add_child(forge)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	forge.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _head("✦ The Wisp Forge", 26, CREAM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := _button("Close  [C]")
	close.pressed.connect(func(): game.toggle_forge())
	head.add_child(close)
	var sub := _label("Gather materials from the world, then bind them here into spells, foci and relics.", 12, DIM)
	v.add_child(sub)
	var r := _rule(860)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	forge_list = VBoxContainer.new()
	forge_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_list.add_theme_constant_override("separation", 6)
	scroll.add_child(forge_list)

## A village keeper's shop: what they sell (for coins) and what they buy (for coins), by their trade
## (Defs.SHOPS); towns.gd does the trading.
func _build_shop() -> void:
	shop = _panel(Color(0.06, 0.045, 0.03, 0.97), TRIM, 14)
	shop.set_anchors_preset(Control.PRESET_CENTER)
	shop.custom_minimum_size = Vector2(760, 540)
	shop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	shop.grow_vertical = Control.GROW_DIRECTION_BOTH
	shop.visible = false
	root.add_child(shop)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	shop.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	shop_title = _head("Shop", 24, CREAM)
	shop_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(shop_title)
	var close := _button("Leave  [F]")
	close.pressed.connect(func(): game.towns.close_shop())
	head.add_child(close)
	shop_coins = _label("", 14, Color(1, 0.85, 0.4))
	v.add_child(shop_coins)
	var r := _rule(720)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(r)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	shop_list = VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 6)
	scroll.add_child(shop_list)

func show_shop(vk) -> void:
	_shop_v = vk
	_render_shop()
	shop.visible = true

func hide_shop() -> void:
	shop.visible = false
	_shop_v = null

func _render_shop() -> void:
	if _shop_v == null:
		return
	var tw = game.towns
	var sd: Dictionary = tw.shop_def(_shop_v)
	shop_title.text = "%s's %s · %s" % [_shop_v.name, sd.get("title", "Shop"), _shop_v.town["name"]]
	shop_coins.text = "Your coins: %d" % tw.coins()
	for c in shop_list.get_children():
		c.queue_free()
	shop_list.add_child(_head("For sale", 17, Color(0.95, 0.8, 0.5)))
	var sell: Array = sd.get("sell", [])
	for i in sell.size():
		var it: Dictionary = sell[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := _label(String(it["name"]), 14, CREAM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_label("%d coins" % int(it["price"]), 14, Color(1, 0.85, 0.4)))
		var b := _button("Buy")
		b.disabled = tw.coins() < int(it["price"])
		b.pressed.connect(func():
			tw.buy(_shop_v, i)
			_render_shop())
		row.add_child(b)
		shop_list.add_child(row)
	shop_list.add_child(_head("They'll buy", 17, Color(0.95, 0.8, 0.5)))
	for bb in tw.buys(_shop_v):
		var mat: int = bb[0]
		var have: int = game.inv[mat]
		if mat >= Defs.FIREOPAL and have <= 0:
			continue                              # (a far world's ore: only shown once you have some)
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 10)
		var sw := ColorRect.new()
		sw.color = Defs.COLOR[mat]
		sw.custom_minimum_size = Vector2(10, 10)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row2.add_child(sw)
		var l2 := _label("%d %s for %d coins   (you have %d)" % [int(bb[1]), Defs.NAMES[mat], int(bb[2]), have], 14, CREAM if have >= int(bb[1]) else DIM)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(l2)
		var b2 := _button("Sell")
		b2.disabled = have < int(bb[1])
		b2.pressed.connect(func():
			tw.sell(_shop_v, mat)
			_render_shop())
		row2.add_child(b2)
		shop_list.add_child(row2)

## A full-screen overlay with a framed panel in the middle; the panel's VBox is in meta "box".
func _screen(dim := Color(0.02, 0.015, 0.05, 0.86), trim := TRIM) -> Control:
	var c := ColorRect.new()
	c.color = dim
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(cc)
	var p := _panel(Color(0.05, 0.04, 0.09, 0.97), trim, 22)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
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
	dv.add_child(_center(_rule(320)))
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
	loading_lbl = _head("Forging a planet", 28, CREAM)
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	loading_lbl.custom_minimum_size = Vector2(420, 0)
	lv.add_child(loading_lbl)
	lv.add_child(_center(_rule(380)))
	var lh := _label("Every grain of the world is being laid down. This takes a moment.", 12, DIM)
	lh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(lh)

## Quality, dithering and pixel size. Opened from the title screen, or with Esc while playing.
func _build_settings() -> void:
	settings_panel = _screen()
	settings_panel.visible = false
	var sv: VBoxContainer = settings_panel.get_meta("box")
	sv.add_theme_constant_override("separation", 8)
	var head := _head("Settings", 32, CREAM)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(head)
	sv.add_child(_center(_rule(420)))
	var rows := [
		["Quality", "quality", [["High", "high"], ["Medium", "medium"], ["Low", "low"]],
			"Low simulates and lights the world in fewer passes, with bigger pixels, for weaker graphics."],
		["Dithering", "dither", [["Off", "off"], ["Subtle", "subtle"], ["Retro", "retro"]],
			"Off draws clean colour bands like a SNES. Retro is the old checkerboard look."],
		["View", "view", [["World", "world"], ["Unrolled", "unrolled"]],
			"World shows the planet as it is (the horizon curves a little). Unrolled lays the ground out flat, but stretches what's above and below you."],
		["Window", "window", [["Windowed", "windowed"], ["Fullscreen", "fullscreen"], ["Exclusive", "exclusive"]],
			"Fullscreen covers the whole screen (F11 or Alt + Enter switches). Exclusive takes over the display, which can run smoother."],
		["Pixel size", "pixel", [["Auto", 0], ["3", 3], ["4", 4], ["5", 5], ["6", 6]],
			"How big each world pixel is on screen. Bigger shows less of the world, closer up."],
		["Music", "music", [["Off", 0], ["25%", 25], ["50%", 50], ["75%", 75], ["100%", 100]],
			"Music volume (tracks go in game/audio/music)."],
		["Sound", "sound", [["Off", 0], ["25%", 25], ["50%", 50], ["75%", 75], ["100%", 100]],
			"Sound effects volume."],
	]
	for row in rows:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 6)
		var name_lbl := _head(row[0], 17, CREAM)
		name_lbl.custom_minimum_size = Vector2(120, 0)
		h.add_child(name_lbl)
		for opt in row[2]:
			var b := _button(opt[0])
			b.custom_minimum_size = Vector2(64, 0)
			b.pressed.connect(_on_option.bind(row[1], opt[1]))
			h.add_child(b)
			_opt_btns.append([b, row[1], opt[1]])
		box.add_child(h)
		var hint := _label(row[3], 11, DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint)
		sv.add_child(box)
	# the controls, in two columns
	sv.add_child(_center(_rule(420)))
	var ch := _head("Controls", 20, CREAM)
	ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(ch)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 3)
	for pair in [["A / D", "Walk"], ["W / Space", "Jump; hold in the air to levitate"],
			["Left mouse", "Cast the selected spell"], ["Right mouse", "Excavate (dig at a chest to open it)"],
			["Shift + right mouse", "Deconstruct background tiles; take furniture whole"], ["F", "Open a chest or door; at a bed, make it home"],
			["1-9 / wheel", "Choose a spell"], ["Q / E", "Choose what Conjure places"],
			["C", "Wisp Forge (crafting)"], ["M", "Map (Tab: the system)"],
			["H", "Drink a Healing Draught"], ["B", "Build mode (G: how walls and blocks are laid)"],
			["Esc", "Settings and controls"], ["F11", "Fullscreen"], ["F9", "Creative stock (developer)"]]:
		grid.add_child(_label(pair[0], 13, GOLD))
		grid.add_child(_label(pair[1], 13, TEXT))
	sv.add_child(_center(grid))
	var close := _button("Close", true)
	close.custom_minimum_size = Vector2(200, 0)
	close.pressed.connect(toggle_settings)
	# while playing: save everything and go back to the title, to pick another save slot
	_to_title_btn = _button("Save and return to title", true)
	_to_title_btn.custom_minimum_size = Vector2(200, 0)
	_to_title_btn.pressed.connect(func(): game.quit_to_title())
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 12)
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
	map_bar = _panel(Color(0.05, 0.04, 0.09, 0.9), TRIM, 10)
	map_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	map_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	map_bar.offset_top = 12
	map_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_bar.visible = false
	root.add_child(map_bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_bar.add_child(v)
	map_title = _head("", 24, CREAM)
	map_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(map_title)
	map_hint = _label("", 12, DIM)
	map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(map_hint)

func show_map(g) -> void:
	if g.map_tab == "system":
		map_title.text = "The system"
		map_hint.text = "Tab: the planet    M or Esc: close"
	else:
		map_title.text = "Map of %s" % String(g.planet.get("name", ""))
		map_hint.text = "A / D or drag: turn    W / S or wheel: zoom    Tab: the system    M or Esc: close"
	map_bar.visible = true

func hide_map() -> void:
	map_bar.visible = false

func show_forge() -> void:
	_render_forge()
	forge.visible = true

func hide_forge() -> void:
	forge.visible = false

# ----------------------------------------------------------------- toasts --
## The building bar: the categories (Q/E), the pieces of the chosen one (wheel or 1-9; dimmed
## when the satchel can't pay), and the chosen piece's cost.
func _update_build_bar(g) -> void:
	var piece: Dictionary = g.build_piece()
	var key := "%d|%d|%s|%d|%d|%d|%s|%d|%d|%s" % [g.build_cat, int(g.build_idx[g.build_cat]), _inv_key, g.build_w, g.build_floors, g.build_style, str(piece.get("cost", {})), g.build_shape, g.build_thick, str(g.build_prev.get("text", ""))]
	if key == _build_key:
		return
	_build_key = key
	for c in build_box.get_children():
		c.queue_free()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 14)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.add_child(tabs)
	tabs.add_child(_label("Q", 11, DIM))
	for k in Build.CAT_ORDER:
		tabs.add_child(_label(Build.CATS[k], 14 if k == g.build_cat else 12, GOLD if k == g.build_cat else DIM))
	tabs.add_child(_label("E", 11, DIM))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.custom_minimum_size.x = 640
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.add_child(row)
	var lst: Array = g.build_list()
	for k in lst.size():
		var pc: Dictionary = lst[k]
		var afford: bool = not Build.payable(pc, g.player.inv).is_empty()
		var on: bool = pc == piece
		var col := GOLD if on else (TEXT if afford else Color(0.55, 0.42, 0.45))
		row.add_child(_label(("%d %s" % [k + 1, pc["name"]]) if k < 9 else pc["name"], 13 if on else 12, col))
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
			hint += "  ·  [ ] width  ·  %sT style  ·  R variation  ·  B leaves" % ("- = storeys  ·  " if piece["struct"] != "roof" else "")
		elif piece["kind"] == "block" or (piece["kind"] == "wall" and g.build_shape != 0):
			var shp: String = Build.SHAPES[maxi(g.build_shape, 1)]
			hint = "%s, %s%s  ·  press, drag, let go to lay it (right-click cancels)  ·  G shape  ·  %s  ·  B leaves" % [piece["name"], shp,
				(", %d thick" % g.build_thick) if shp != "Rectangle" else "", "[ ] thickness" if shp != "Rectangle" else "[ ] thickness of lines and frames"]
			var ptxt: String = g.build_prev.get("text", "")
			if ptxt != "":
				hint += "\n" + ptxt
		elif piece["kind"] == "carried":
			hint = "%s: yours, carried in the satchel  ·  click to set it down  ·  T mirror  ·  B leaves" % piece["name"]
		else:
			hint += "  ·  click to place%s  ·  B leaves" % ("  ·  R new design  ·  T mirror" if piece["kind"] == "prop" else ("  ·  hold to paint  ·  G shape" if piece["kind"] == "wall" else ""))
		var hl := _label(hint, 12, CREAM)
		hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		build_box.add_child(hl)

func toast(txt: String, col: Color = Color.WHITE, secs: float = 2.2) -> void:
	var p := _panel(Color(0.05, 0.04, 0.09, 0.86), TRIM_DIM, 5)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(txt, 13, col)
	p.add_child(l)
	toasts.add_child(p)
	toasts.move_child(p, 0)
	_toast_items.append([p, Time.get_ticks_msec() + int(secs * 1000.0)])
	while toasts.get_child_count() > 7:
		var last := toasts.get_child(toasts.get_child_count() - 1)
		toasts.remove_child(last)
		last.queue_free()

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
			wn = "Underground"
		elif g.rain > 0.15 and b["weather"] != "clear":
			wn = {"rain": "Rain", "snow": "Snowfall", "ash": "Ashfall"}[b["weather"]]
		if g.sky_ev != "" and depth <= 14:
			wn = String(Defs.SKY_EVENTS[g.sky_ev]["name"])
		if g.hazard != "":
			wn += " · " + String(Defs.HAZARDS[g.hazard]["name"]) + "!"
		var tiers := ["", "I · Stone", "II · Copper", "III · Obsidian", "IV · Core Siphon"]
		var extra := ""
		if g.heat_ward:
			extra += " · Heat Ward"
		if g.items.has("heart"):
			extra += " · Ember Heart"
		for rel in [["ring", "Warden's Ring"], ["circlet", "Sage's Circlet"], ["boots", "Featherstep Boots"]]:
			if g.items.has(rel[0]):
				extra += " · " + rel[1]
		var nrel := 0
		for rid in Defs.RELICS:
			if g.items.has(rid):
				nrel += 1
		if nrel > 0:
			extra += " · %d guardian relic%s" % [nrel, "" if nrel == 1 else "s"]
		info.text = "%s · %s\n%s · %s · %s\nStaff %s%s\n%d coins · %d FPS" % [g.planet["name"], g.region_name(), depth_txt, g.local_time_text(), wn, tiers[g.tier], extra, int(g.items.get("coins", 0)), Engine.get_frames_per_second()]
		if g.show_perf:
			# F3: where the time goes (game logic on the CPU, waiting for the GPU, ticks per frame)
			info.text += " · game %.1f ms · GPU wait %.1f ms · %.1f ticks/frame · %s quality\n%s" % [g.perf_cpu_ms, g.perf_wait_ms, g.perf_steps, g.settings["quality"], g.prof_text(6, "\n")]
	# build mode replaces the spell bar with the building bar
	hotbar.visible = not g.build_on
	build_bar.visible = g.build_on
	if g.build_on:
		_update_build_bar(g)
	# hotbar
	var hk := ",".join(g.known) + "|" + str(g.sel)
	if hk != _hot_key:
		_hot_key = hk
		for c in hotbar.get_children():
			c.queue_free()
		for k in g.known.size():
			var s: Dictionary = Defs.SPELLS[g.known[k]]
			var on: bool = k == g.sel
			var p := PanelContainer.new()
			var normal := _frame(Color(0.2, 0.14, 0.06, 0.94) if on else Color(0.05, 0.04, 0.09, 0.88), GOLD if on else TRIM_DIM, 6, 9)
			var hover := _frame(Color(0.24, 0.17, 0.34, 0.95), GOLD, 6, 9)
			p.add_theme_stylebox_override("panel", normal)
			p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			p.mouse_entered.connect(_set_panel_style.bind(p, hover))
			p.mouse_exited.connect(_set_panel_style.bind(p, normal))
			p.custom_minimum_size = Vector2(108, 0)
			var v := VBoxContainer.new()
			v.add_theme_constant_override("separation", 0)
			v.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(v)
			var top := HBoxContainer.new()
			top.add_theme_constant_override("separation", 5)
			top.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(top)
			var sw := ColorRect.new()
			sw.color = s["color"]
			sw.custom_minimum_size = Vector2(8, 8)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			top.add_child(sw)
			top.add_child(_label(s["name"], 13, CREAM if on else TEXT))
			var bot := HBoxContainer.new()
			bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(bot)
			var kl := _label("[%d]" % (k + 1), 10, GOLD if on else DIM)
			kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bot.add_child(kl)
			bot.add_child(_label(("%d mp" % int(s["mana"])) if float(s["mana"]) > 0 else "free", 10, Color(0.55, 0.7, 1.0) if float(s["mana"]) > 0 else DIM))
			p.gui_input.connect(_on_hot_input.bind(k))
			hotbar.add_child(p)
	# satchel
	var ik := str(g.mat) + "|"
	for m in Defs.NM:
		if g.player.inv[m] > 0:
			ik += "%d:%d," % [m, g.player.inv[m]]
	for it in g.player.furn:
		ik += String(it["name"]) + ";"
	ik += "p%d" % int(g.items.get("potion", 0))
	if ik != _inv_key:
		_inv_key = ik
		for c in satchel.get_children():
			c.queue_free()
		var any := false
		for m in Defs.NM:
			if g.player.inv[m] <= 0:
				continue
			any = true
			var rp := PanelContainer.new()
			var rn := StyleBoxFlat.new()
			rn.bg_color = Color(1, 0.82, 0.23, 0.14) if m == g.mat else Color(0, 0, 0, 0)
			rn.set_content_margin_all(2)
			rn.content_margin_left = 4
			if m == g.mat:
				rn.border_width_left = 2
				rn.border_color = GOLD
			var rh: StyleBoxFlat = rn.duplicate()
			rh.bg_color = Color(0.55, 0.45, 0.95, 0.24)
			rp.add_theme_stylebox_override("panel", rn)
			rp.mouse_filter = Control.MOUSE_FILTER_STOP
			rp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			rp.tooltip_text = "Click to conjure with %s" % Defs.NAMES[m]
			rp.mouse_entered.connect(_set_panel_style.bind(rp, rh))
			rp.mouse_exited.connect(_set_panel_style.bind(rp, rn))
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rp.add_child(row)
			var swp := PanelContainer.new()
			var swb := StyleBoxFlat.new()
			swb.bg_color = Defs.COLOR[m]
			swb.border_color = OUTLINE
			swb.set_border_width_all(1)
			swp.add_theme_stylebox_override("panel", swb)
			swp.custom_minimum_size = Vector2(11, 11)
			swp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			swp.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(swp)
			var nm := _label(Defs.NAMES[m], 12, GOLD if m == g.mat else TEXT)
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			row.add_child(_label(str(g.player.inv[m]), 12, CREAM))
			rp.gui_input.connect(_on_mat_input.bind(m))
			satchel.add_child(rp)
		var np := int(g.items.get("potion", 0))
		if np > 0:
			any = true
			var prow := HBoxContainer.new()
			prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var psw := PanelContainer.new()
			var psb := StyleBoxFlat.new()
			psb.bg_color = Color(0.85, 0.2, 0.3)
			psb.border_color = OUTLINE
			psb.set_border_width_all(1)
			psb.set_corner_radius_all(5)
			psw.add_theme_stylebox_override("panel", psb)
			psw.custom_minimum_size = Vector2(11, 11)
			psw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			psw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			prow.add_child(psw)
			var pl := _label("Healing Draught (H)", 12, TEXT)
			pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			prow.add_child(pl)
			prow.add_child(_label(str(np), 12, CREAM))
			satchel.add_child(prow)
		# furniture carried whole, one line per kind
		var fc := {}
		var forder := []
		for it in g.player.furn:
			var fn: String = it["name"]
			if not fc.has(fn):
				fc[fn] = 0
				forder.append(fn)
			fc[fn] = int(fc[fn]) + 1
		if not forder.is_empty():
			any = true
			var fh := _label("Furniture  (B, Satchel tab)", 11, DIM)
			satchel.add_child(fh)
			for fn2 in forder:
				var frow := HBoxContainer.new()
				frow.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var fsw := PanelContainer.new()
				var fsb := StyleBoxFlat.new()
				fsb.bg_color = Color(0.56, 0.37, 0.2)
				fsb.border_color = OUTLINE
				fsb.set_border_width_all(1)
				fsw.add_theme_stylebox_override("panel", fsb)
				fsw.custom_minimum_size = Vector2(11, 11)
				fsw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				fsw.mouse_filter = Control.MOUSE_FILTER_IGNORE
				frow.add_child(fsw)
				var fl := _label(fn2, 12, TEXT)
				fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				frow.add_child(fl)
				frow.add_child(_label(str(fc[fn2]), 12, CREAM))
				satchel.add_child(frow)
		if not any:
			satchel.add_child(_label("Right-click to excavate", 11, DIM))
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

# ------------------------------------------------------------------ forge --
func _render_forge() -> void:
	for c in forge_list.get_children():
		c.queue_free()
	var cats := {}
	var order := []
	for r in game.recipes:
		if game.recipe_hidden(r):
			continue
		if not cats.has(r["cat"]):
			cats[r["cat"]] = []
			order.append(r["cat"])
		cats[r["cat"]].append(r)
	for cat in order:
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 8)
		var cl := _head(cat, 17, Color(0.78, 0.7, 1))
		ch.add_child(cl)
		var rr := _rule(100)
		rr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ch.add_child(rr)
		forge_list.add_child(ch)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		forge_list.add_child(grid)
		for r in cats[cat]:
			grid.add_child(_recipe_card(r))

func _recipe_card(r: Dictionary) -> Control:
	var done: bool = game.recipe_done(r)
	var unlocked: bool = game.recipe_unlocked(r)
	var aff: bool = game.recipe_affordable(r)
	var trim := TRIM_DIM
	if not done and unlocked and aff:
		trim = Color(0.45, 0.8, 0.42)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _frame(Color(0.08, 0.065, 0.14, 0.97), trim, 8))
	p.custom_minimum_size = Vector2(280, 0)
	if done:
		p.modulate.a = 0.55
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	v.add_child(_head(r["name"], 15, CREAM))
	var desc: String = r.get("desc", "")
	if r.has("spell"):
		desc = Defs.SPELLS[r["spell"]]["desc"]
	var dl := _label(desc, 11, Color(0.7, 0.71, 0.86))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dl.custom_minimum_size = Vector2(256, 0)
	v.add_child(dl)
	var costs := HFlowContainer.new()
	costs.add_theme_constant_override("h_separation", 10)
	v.add_child(costs)
	for k in r["cost"]:
		var have: int = game.inv[int(k)]
		var need: int = int(r["cost"][k])
		var cr := HBoxContainer.new()
		cr.add_theme_constant_override("separation", 3)
		var sw := ColorRect.new()
		sw.color = Defs.COLOR[int(k)]
		sw.custom_minimum_size = Vector2(8, 8)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cr.add_child(sw)
		cr.add_child(_label("%s %d/%d" % [Defs.NAMES[int(k)], have, need], 11, Color(0.62, 0.95, 0.62) if have >= need else Color(0.95, 0.62, 0.62)))
		costs.add_child(cr)
	if done:
		v.add_child(_label("✓ Forged", 11, DIM))
	elif not unlocked:
		v.add_child(_label(game.recipe_lock_text(r), 11, DIM))
	else:
		var b := _button("Forge")
		b.disabled = not aff
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
		_render_forge()

func _set_panel_style(p: PanelContainer, sb: StyleBox) -> void:
	if is_instance_valid(p):
		p.add_theme_stylebox_override("panel", sb)

## True when the pointer is over a clickable HUD element (satchel, spell slots; with
## `slots` false, only the panels: the wheel still picks a spell over the slots).
func mouse_over_ui(slots := true) -> bool:
	if settings_panel and settings_panel.visible:
		return true
	if hud == null or not hud.visible:
		return false
	var m := get_viewport().get_mouse_position()
	if satchel_panel and satchel_panel.get_global_rect().has_point(m):
		return true
	if slots and hotbar and hotbar.get_global_rect().has_point(m):
		return true
	if build_bar and build_bar.visible and build_bar.get_global_rect().has_point(m):
		return true
	return false
