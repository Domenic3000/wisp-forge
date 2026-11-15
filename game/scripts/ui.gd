extends CanvasLayer
## HUD, satchel, hotbar, toasts, forge panel, title / death / loading screens.

var game
var root: Control
var hud: Control
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var br_bar: ProgressBar
var hp_lbl: Label
var mp_lbl: Label
var info: Label
var hotbar: HBoxContainer
var satchel: VBoxContainer
var satchel_panel: PanelContainer
var toasts: VBoxContainer
var boss_box: VBoxContainer
var boss_bar: ProgressBar
var boss_lbl: Label
var dig_warn: Label
var forge: PanelContainer
var forge_list: VBoxContainer
var title: Control
var death: Control
var loading: Control
var loading_lbl: Label
var continue_btn: Button
var settings_panel: Control
var _opt_btns := []       # [button, key, value]
var _hot_key := ""
var _inv_key := ""
var _toast_items: Array = []

const GOLD := Color(1, 0.82, 0.23)
const DIM := Color(0.55, 0.58, 0.72)

func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_hud()
	_build_forge()
	_build_screens()

# ------------------------------------------------------------- builders --
func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_content_margin_all(6)
	return sb

func _bar(col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(240, 16)
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.07, 0.12)
	bg.border_color = Color(0.16, 0.17, 0.27)
	bg.set_border_width_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = col
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

func _button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var n := StyleBoxFlat.new()
	n.bg_color = GOLD
	n.set_content_margin_all(6)
	n.content_margin_left = 14
	n.content_margin_right = 14
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(1, 0.9, 0.45)
	var d: StyleBoxFlat = n.duplicate()
	d.bg_color = Color(0.27, 0.28, 0.38)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_color_override("font_color", Color(0.1, 0.06, 0.12))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.06, 0.12))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.55, 0.65))
	return b

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	var bars := VBoxContainer.new()
	bars.position = Vector2(14, 12)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bars)
	hp_bar = _bar(Color(0.85, 0.25, 0.3))
	mp_bar = _bar(Color(0.3, 0.45, 0.9))
	br_bar = _bar(Color(0.5, 0.85, 0.9))
	br_bar.custom_minimum_size = Vector2(240, 8)
	hp_lbl = _label("", 11, Color.WHITE)
	mp_lbl = _label("", 11, Color.WHITE)
	hp_bar.add_child(hp_lbl)
	mp_bar.add_child(mp_lbl)
	hp_lbl.set_anchors_preset(Control.PRESET_CENTER)
	mp_lbl.set_anchors_preset(Control.PRESET_CENTER)
	bars.add_child(hp_bar)
	bars.add_child(mp_bar)
	bars.add_child(br_bar)
	info = _label("", 13, Color(0.9, 0.92, 1))
	bars.add_child(info)

	hotbar = HBoxContainer.new()
	hotbar.add_theme_constant_override("separation", 6)
	hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotbar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hotbar.position.y -= 12
	hud.add_child(hotbar)

	var sw := PanelContainer.new()
	sw.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.1, 0.85), Color(0.16, 0.17, 0.27)))
	sw.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sw.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sw.position = Vector2(-12, 12)
	sw.custom_minimum_size = Vector2(200, 40)
	hud.add_child(sw)
	satchel_panel = sw
	var sv := VBoxContainer.new()
	sw.add_child(sv)
	sv.add_child(_label("SATCHEL", 13, GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(190, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	satchel = VBoxContainer.new()
	satchel.add_theme_constant_override("separation", 1)
	satchel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(satchel)
	scroll.custom_minimum_size.y = 420

	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.position.y = 12
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(toasts)

	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	boss_box.position.y = 140
	boss_box.visible = false
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(boss_box)
	boss_lbl = _label("Vulkhar, the Ember Golem", 15, Color(1, 0.7, 0.3))
	boss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(boss_lbl)
	boss_bar = _bar(Color(1, 0.55, 0.2))
	boss_bar.custom_minimum_size = Vector2(420, 14)
	boss_box.add_child(boss_bar)

	dig_warn = _label("Too hard for your staff. Forge a stronger focus (C)", 13, Color(1, 0.7, 0.62))
	dig_warn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dig_warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dig_warn.position.y -= 90
	dig_warn.visible = false
	hud.add_child(dig_warn)

	var help := _label("A/D move · W/Space jump, hold to levitate · LMB cast · RMB excavate · 1-6 / wheel spell · Q/E material · F open chest · C forge · M zoom", 11, DIM)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	help.position += Vector2(14, -8)
	hud.add_child(help)

func _build_forge() -> void:
	forge = PanelContainer.new()
	forge.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.055, 0.095, 0.96), Color(0.23, 0.24, 0.38)))
	forge.set_anchors_preset(Control.PRESET_CENTER)
	forge.custom_minimum_size = Vector2(880, 600)
	forge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	forge.grow_vertical = Control.GROW_DIRECTION_BOTH
	forge.visible = false
	root.add_child(forge)
	var v := VBoxContainer.new()
	forge.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label("✦ THE WISP FORGE", 18, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := _button("Close [C]")
	close.pressed.connect(func(): game.toggle_forge())
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	forge_list = VBoxContainer.new()
	forge_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(forge_list)

func _screen() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.03, 0.03, 0.07, 0.94)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	c.add_child(v)
	return c

func _center(node: Control) -> Control:
	var cc := CenterContainer.new()
	cc.add_child(node)
	return cc

func _build_screens() -> void:
	title = _screen()
	var tv: VBoxContainer = title.get_child(0)
	var logo := _label("WISP FORGE", 64, Color(1, 0.92, 0.66))
	logo.add_theme_color_override("font_shadow_color", Color(0.36, 0.25, 0.66))
	logo.add_theme_constant_override("shadow_offset_x", 5)
	logo.add_theme_constant_override("shadow_offset_y", 5)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(logo)
	var sub := _label("A mage. A wisp. A round planet made of every last grain.", 16, Color(0.72, 0.65, 1))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(sub)
	var blurb := _label("Excavate the living world, forge what you find into spells, dig through glowing caverns and the\nmolten mantle, defeat its guardian and harvest the planet core to open a gate to the next world.", 13, DIM)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(blurb)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	tv.add_child(btns)
	var nb := _button("New Journey")
	nb.pressed.connect(func(): game.start_game(false))
	btns.add_child(nb)
	continue_btn = _button("Continue")
	continue_btn.pressed.connect(func(): game.start_game(true))
	btns.add_child(continue_btn)
	var sb := _button("Settings")
	sb.pressed.connect(toggle_settings)
	btns.add_child(sb)
	var controls := _label("A / D move    W / Space jump, hold in the air to levitate    Right mouse excavate (Shift: deconstruct background)    Left mouse cast\n1-6 / wheel choose spell    Q / E choose Conjure material    F open a chest    C open the Wisp Forge    M zoom out    Esc settings    F9 creative stock", 12, DIM)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(controls)

	death = _screen()
	death.visible = false
	var dv: VBoxContainer = death.get_child(0)
	var dl := _label("Your light fades…", 30, Color(1, 0.92, 0.66))
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(dl)
	var ds := _label("The wisp carries you back to the surface. A quarter of your satchel is lost.", 14, Color(0.72, 0.65, 1))
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dv.add_child(ds)
	var rb := _button("Rise again")
	rb.pressed.connect(func(): game.revive())
	dv.add_child(_center(rb))

	_build_settings()

	loading = _screen()
	loading.visible = false
	var lv: VBoxContainer = loading.get_child(0)
	loading_lbl = _label("Forging a planet…", 28, Color(1, 0.92, 0.66))
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(loading_lbl)

## Quality, dithering and pixel size. Opened from the title screen, or with Esc while playing.
func _build_settings() -> void:
	settings_panel = _screen()
	settings_panel.visible = false
	var sv: VBoxContainer = settings_panel.get_child(0)
	var head := _label("Settings", 30, Color(1, 0.92, 0.66))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(head)
	var rows := [
		["Quality", "quality", [["High", "high"], ["Medium", "medium"], ["Low", "low"]],
			"Low simulates and lights the world in fewer passes, with bigger pixels, for weaker graphics."],
		["Dithering", "dither", [["Off", "off"], ["Subtle", "subtle"], ["Retro", "retro"]],
			"Off draws clean colour bands like a SNES. Retro is the old checkerboard look."],
		["Pixel size", "pixel", [["Auto", 0], ["2", 2], ["3", 3], ["4", 4], ["5", 5]],
			"How big each world pixel is on screen. Bigger shows less of the world, closer up."],
	]
	for row in rows:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var h := HBoxContainer.new()
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_theme_constant_override("separation", 8)
		var name_lbl := _label(row[0], 16, Color(0.85, 0.88, 1))
		name_lbl.custom_minimum_size = Vector2(110, 0)
		h.add_child(name_lbl)
		for opt in row[2]:
			var b := _button(opt[0])
			b.pressed.connect(_on_option.bind(row[1], opt[1]))
			h.add_child(b)
			_opt_btns.append([b, row[1], opt[1]])
		box.add_child(h)
		var hint := _label(row[3], 11, DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(hint)
		sv.add_child(box)
	var close := _button("Close")
	close.pressed.connect(toggle_settings)
	sv.add_child(_center(close))
	_refresh_settings()

func _on_option(key: String, value) -> void:
	game.set_setting(key, value)
	_refresh_settings()

func _refresh_settings() -> void:
	for it in _opt_btns:
		var b: Button = it[0]
		var on: bool = str(game.settings.get(it[1], "")) == str(it[2])
		b.modulate = Color(1, 1, 1) if on else Color(0.55, 0.55, 0.7)

func toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	if settings_panel.visible:
		_refresh_settings()

# --------------------------------------------------------------- screens --
func show_title(has_save: bool) -> void:
	title.visible = true
	continue_btn.visible = has_save

func show_error(msg: String) -> void:
	title.visible = true
	var tv: VBoxContainer = title.get_child(0)
	for c in tv.get_children():
		c.queue_free()
	var l := _label("Wisp Forge couldn't start the GPU simulation", 22, Color(1, 0.6, 0.5))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(l)
	var m := _label(msg, 12, Color.WHITE)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.autowrap_mode = TextServer.AUTOWRAP_WORD
	m.custom_minimum_size = Vector2(900, 0)
	tv.add_child(_center(m))

func show_loading(txt: String) -> void:
	title.visible = false
	loading_lbl.text = txt
	loading.visible = true

func hide_loading() -> void:
	loading.visible = false

func show_hud() -> void:
	hud.visible = true

func show_death() -> void:
	death.visible = true

func hide_death() -> void:
	death.visible = false

func show_forge() -> void:
	_render_forge()
	forge.visible = true

func hide_forge() -> void:
	forge.visible = false

# ----------------------------------------------------------------- toasts --
func toast(txt: String, col: Color = Color.WHITE, secs: float = 2.2) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.05, 0.09, 0.8), Color(0.16, 0.17, 0.27)))
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
	br_bar.visible = g.breath < g.max_breath
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
		var tiers := ["", "I · Stone", "II · Copper", "III · Obsidian", "IV · Core Siphon"]
		var extra := ""
		if g.heat_ward:
			extra += " · Heat Ward"
		if g.items.has("heart"):
			extra += " · Ember Heart"
		for rel in [["ring", "Warden's Ring"], ["circlet", "Sage's Circlet"], ["boots", "Featherstep Boots"]]:
			if g.items.has(rel[0]):
				extra += " · " + rel[1]
		info.text = "%s · %s\n%s · %s · %s\nStaff %s%s\n%d FPS" % [g.planet["name"], g.region_name(), depth_txt, g.local_time_text(), wn, tiers[g.tier], extra, Engine.get_frames_per_second()]
	# hotbar
	var hk := ",".join(g.known) + "|" + str(g.sel)
	if hk != _hot_key:
		_hot_key = hk
		for c in hotbar.get_children():
			c.queue_free()
		for k in g.known.size():
			var s: Dictionary = Defs.SPELLS[g.known[k]]
			var p := PanelContainer.new()
			var on: bool = k == g.sel
			var normal := _panel_style(Color(0.07, 0.08, 0.12, 0.88), GOLD if on else Color(0.16, 0.17, 0.27))
			var hover := _panel_style(Color(0.16, 0.17, 0.26, 0.95), GOLD if on else Color(0.55, 0.6, 0.85))
			p.add_theme_stylebox_override("panel", normal)
			p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			p.mouse_entered.connect(_set_panel_style.bind(p, hover))
			p.mouse_exited.connect(_set_panel_style.bind(p, normal))
			p.custom_minimum_size = Vector2(100, 0)
			var v := VBoxContainer.new()
			p.add_child(v)
			v.add_child(_label("%d  %s" % [k + 1, s["name"]], 12, s["color"] if on else Color(0.88, 0.9, 1)))
			v.add_child(_label(("%d mp" % int(s["mana"])) if float(s["mana"]) > 0 else "free", 10, DIM))
			p.gui_input.connect(_on_hot_input.bind(k))
			hotbar.add_child(p)
	# satchel
	var ik := str(g.mat) + "|"
	for m in Defs.NM:
		if g.player.inv[m] > 0:
			ik += "%d:%d," % [m, g.player.inv[m]]
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
			rn.bg_color = Color(1, 0.82, 0.23, 0.13) if m == g.mat else Color(0, 0, 0, 0)
			rn.set_content_margin_all(2)
			var rh: StyleBoxFlat = rn.duplicate()
			rh.bg_color = Color(0.55, 0.6, 0.95, 0.28)
			rh.set_border_width_all(1)
			rh.border_color = Color(0.7, 0.75, 1.0, 0.7)
			rp.add_theme_stylebox_override("panel", rn)
			rp.mouse_filter = Control.MOUSE_FILTER_STOP
			rp.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			rp.tooltip_text = "Click to conjure with %s" % Defs.NAMES[m]
			rp.mouse_entered.connect(_set_panel_style.bind(rp, rh))
			rp.mouse_exited.connect(_set_panel_style.bind(rp, rn))
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rp.add_child(row)
			var sw := ColorRect.new()
			sw.color = Defs.COLOR[m]
			sw.custom_minimum_size = Vector2(10, 10)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(sw)
			var nm := _label(Defs.NAMES[m], 12, GOLD if m == g.mat else Color(0.85, 0.88, 1))
			nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(nm)
			row.add_child(_label(str(g.player.inv[m]), 12, Color(0.8, 0.84, 1)))
			rp.gui_input.connect(_on_mat_input.bind(m))
			satchel.add_child(rp)
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
	for r in Defs.RECIPES:
		if not cats.has(r["cat"]):
			cats[r["cat"]] = []
			order.append(r["cat"])
		cats[r["cat"]].append(r)
	for cat in order:
		forge_list.add_child(_label(cat.to_upper(), 13, Color(0.72, 0.65, 1)))
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
	var border := Color(0.15, 0.16, 0.27)
	if not done and unlocked and aff:
		border = Color(0.29, 0.48, 0.29)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.09, 0.16), border))
	p.custom_minimum_size = Vector2(270, 0)
	if done:
		p.modulate.a = 0.55
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label(r["name"], 14, Color(1, 0.91, 0.66)))
	var desc: String = r.get("desc", "")
	if r.has("spell"):
		desc = Defs.SPELLS[r["spell"]]["desc"]
	var dl := _label(desc, 11, Color(0.66, 0.68, 0.82))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dl.custom_minimum_size = Vector2(250, 0)
	v.add_child(dl)
	var costs := HFlowContainer.new()
	v.add_child(costs)
	for k in r["cost"]:
		var have: int = game.inv[int(k)]
		var need: int = int(r["cost"][k])
		costs.add_child(_label("%s %d/%d" % [Defs.NAMES[int(k)], have, need], 11, Color(0.65, 0.94, 0.65) if have >= need else Color(0.94, 0.65, 0.65)))
	if done:
		v.add_child(_label("Forged", 11, DIM))
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

## True when the pointer is over a clickable HUD element (satchel, spell slots).
func mouse_over_ui() -> bool:
	if settings_panel and settings_panel.visible:
		return true
	if hud == null or not hud.visible:
		return false
	var m := get_viewport().get_mouse_position()
	if satchel_panel and satchel_panel.get_global_rect().has_point(m):
		return true
	if hotbar and hotbar.get_global_rect().has_point(m):
		return true
	return false
