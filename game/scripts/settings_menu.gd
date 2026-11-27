extends Node
## The pause menu and the settings (27 Nov; user: "ok do you want to create a real setting menu now"; chose
## rebindable keys, more sound sliders, display extras, comfort and gameplay, and a pause menu first on Esc).
## Everything is drawn into ui.gd's `settings_panel` (a full screen dim with a runed panel), so the game's checks
## that the world waits while it's open (main `menu_paused`) and that the pointer is over the UI hold as before.
## Two pages: the pause page (Resume, Settings, Journal, Save and return to title, Save and quit) and the settings
## page, with tabs: Display, Sound, Controls, Gameplay. From the title screen it opens on the settings page.
## Settings are kept in main `settings` (saves/settings.json); keys in main `keymap` (keys.gd).

const Keys := preload("res://scripts/keys.gd")

var ui = null
var game = null
var page := "pause"                 # "pause" or "settings"
var tab := "Display"
var from_pause := false             # (the settings page was opened from the pause page: Back goes there)
var capture := []                   # [action, slot] while waiting for a key to bind
var _box: VBoxContainer
var _opt := []                      # [button, setting, value]
var _key_btns := []                 # [button, action, slot]

const TABS := ["Display", "Sound", "Controls", "Gameplay"]
const ROW_W := 430
const LBL_W := 92

func setup(u, g) -> void:
	ui = u
	game = g

func is_open() -> bool:
	return ui.settings_panel != null and ui.settings_panel.visible

## Esc in play: opens the pause page; with it open, steps back (settings -> pause -> closed)
func open_pause() -> void:
	page = "pause"
	capture = []
	ui.settings_panel.visible = true
	build()

## the title screen's Settings button: straight to the settings page
func open_settings(from_pause_page := false) -> void:
	page = "settings"
	from_pause = from_pause_page
	capture = []
	ui.settings_panel.visible = true
	build()

func close() -> void:
	capture = []
	ui.settings_panel.visible = false

func escape() -> void:
	if not capture.is_empty():
		capture = []
		build()
	elif page == "settings" and from_pause:
		page = "pause"
		build()
	else:
		close()

func _in_game() -> bool:
	return game.state == "play" or game.state == "forge" or game.state == "dead"

## (re)builds the open page from the settings as they are now
func build() -> void:
	var sv: VBoxContainer = ui.settings_panel.get_meta("box")
	for ch in sv.get_children():
		sv.remove_child(ch)
		ch.queue_free()
	_opt = []
	_key_btns = []
	sv.add_theme_constant_override("separation", 4)
	if page == "pause":
		_build_pause(sv)
	else:
		_build_settings(sv)

# ------------------------------------------------------------------ the pause page --
func _build_pause(sv: VBoxContainer) -> void:
	var head: Label = ui._head("Paused", 24, ui.CREAM)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(head)
	sv.add_child(ui._center(ui._rule(200)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	for nm in ["Resume", "Settings", "Journal", "Save and return to title", "Save and quit"]:
		var b: Button = ui._button(nm, true)
		b.custom_minimum_size = Vector2(170, 20)
		b.pressed.connect(_pause_pick.bind(nm))
		if nm == "Journal" and game.state != "play":
			b.disabled = true
		col.add_child(b)
	sv.add_child(ui._center(col))
	var ft: Label = ui._label("Esc to go on playing", 11, ui.DIM)
	ft.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(ft)

func _pause_pick(nm: String) -> void:
	match nm:
		"Resume":
			close()
		"Settings":
			open_settings(true)
		"Journal":
			close()
			ui.toggle_journal(game)
		"Save and return to title":
			close()
			game.quit_to_title()
		"Save and quit":
			game.quit_game()

# ------------------------------------------------------------------ the settings page --
func _build_settings(sv: VBoxContainer) -> void:
	var head: Label = ui._head("Settings", 24, ui.CREAM)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	for t in TABS:
		var tb: Button = ui._button(t)
		tb.custom_minimum_size = Vector2(76, 0)
		ui._set_chosen(tb, t == tab)
		tb.pressed.connect(func():
			tab = t
			capture = []
			build())
		tabs.add_child(tb)
	sv.add_child(tabs)
	sv.add_child(ui._center(ui._rule(320)))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(ROW_W + 14, mini(300, int(ui.root.size.y) - 130))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(sc)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_box)
	match tab:
		"Display": _tab_display()
		"Sound": _tab_sound()
		"Controls": _tab_controls()
		"Gameplay": _tab_gameplay()
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 6)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	if tab == "Controls":
		var rk: Button = ui._button("Reset keys")
		rk.custom_minimum_size = Vector2(90, 0)
		rk.pressed.connect(func():
			game.reset_keys()
			ui.toast("Keys back to how they came", Color(0.8, 0.9, 1.0), 1.5)
			build())
		brow.add_child(rk)
	var back: Button = ui._button("Back" if from_pause else "Close", true)
	back.custom_minimum_size = Vector2(110, 0)
	back.pressed.connect(func():
		if from_pause:
			page = "pause"
			build()
		else:
			close())
	brow.add_child(back)
	sv.add_child(brow)
	refresh()

func _tab_display() -> void:
	_choice("Window", "window", [["Windowed", "windowed"], ["Fullscreen", "fullscreen"], ["Exclusive", "exclusive"]],
		"F11 or Alt + Enter switches. Exclusive can run smoother.")
	_choice("VSync", "vsync", [["On", true], ["Off", false]], "On keeps frames in step with the screen (no tearing).")
	_choice("Frame cap", "fps_cap", [["30", 30], ["60", 60], ["120", 120], ["144", 144], ["None", 0]],
		"The most frames a second to draw. With VSync on, the screen's rate caps it too.")
	_choice("Quality", "quality", [["Auto", "auto"], ["High", "high"], ["Medium", "medium"], ["Low", "low"]],
		"Auto starts high and steps down if the game runs under 50 frames a second.")
	_choice("Pixel size", "pixel", [["Auto", 0], ["3", 3], ["4", 4], ["5", 5], ["6", 6]], "How big each world pixel is on screen.")
	_choice("Interface", "ui_scale", [["Smaller", -1], ["Auto", 0], ["Larger", 1]],
		"The size of the menus and the HUD. Larger needs a tall enough screen.")
	_slider("Brightness", "bright", 70, 130, 5, "%")
	_choice("Dithering", "dither", [["Off", "off"], ["Subtle", "subtle"], ["Retro", "retro"]],
		"Off draws clean colour bands like a SNES; Retro the old checkerboard.")
	_choice("View", "view", [["World", "world"], ["Unrolled", "unrolled"]], "World shows the planet as it is; Unrolled lays the ground out flat.")
	_choice("Frame counter", "show_fps", [["Off", false], ["On", true]], "Frames a second in the corner (F3 for the full breakdown).")

func _tab_sound() -> void:
	_slider("Master", "master", 0, 100, 5, "%")
	_slider("Music", "music", 0, 100, 5, "%")
	_slider("Effects", "sound", 0, 100, 5, "%")
	_slider("Ambience", "ambience", 0, 100, 5, "%")
	_slider("Interface", "ui_vol", 0, 100, 5, "%")
	_hint("Music tracks go in the music folder beside the game.")

func _tab_gameplay() -> void:
	_slider("Screen shake", "shake", 0, 100, 10, "%")
	_slider("Screen flashes", "flash", 0, 100, 10, "%")
	_choice("Wisp's reminders", "wisp_notes", [["On", true], ["Off", false]], "The wisp's little notes beside you: out of planks, too far.")
	_choice("Pickup popups", "popups", [["On", true], ["Off", false]], "\"+3 Sand\" rising where you dig.")
	_choice("F's highlight", "f_hint", [["On", true], ["Off", false]], "Brackets round what F will use, and its name.")
	_choice("Minimap", "minimap", [["On", true], ["Off", false]], "N switches it too.")
	_choice("World autosave", "autosave", [["2 min", 2], ["5 min", 5], ["10 min", 10]],
		"How often the whole world is saved while you play (your progress is saved every minute).")

func _tab_controls() -> void:
	var group := ""
	for a in Keys.ACTIONS:
		if String(a[2]) != group:
			group = String(a[2])
			var gh: Label = ui._head(group, 12, ui.GOLD)
			_box.add_child(gh)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		var nl: Label = ui._label(String(a[1]), 11, ui.TEXT)
		nl.custom_minimum_size = Vector2(190, 0)
		nl.clip_text = true
		row.add_child(nl)
		var ks: Array = game.keymap.get(a[0], [])
		for slot in 2:
			var txt := "-"
			if not capture.is_empty() and capture[0] == a[0] and int(capture[1]) == slot:
				txt = "press a key"
			elif slot < ks.size():
				txt = Keys.key_name(int(ks[slot]))
			var kb: Button = ui._button(txt)
			kb.custom_minimum_size = Vector2(68, 0)
			var aid := String(a[0])
			var sl: int = slot
			kb.pressed.connect(func():
				capture = [aid, sl]
				build())
			ui._set_chosen(kb, not capture.is_empty() and capture[0] == a[0] and int(capture[1]) == slot)
			row.add_child(kb)
			_key_btns.append([kb, aid, sl])
		# (a key that does something else too: fine where they never meet, but said, so it's no surprise)
		var also := []
		for kc in ks:
			for b in Keys.ACTIONS:
				if b[0] != a[0] and (game.keymap.get(b[0], []) as Array).has(kc):
					also.append(String(b[1]).split(",")[0].split(" (")[0])
		if not also.is_empty():
			var al: Label = ui._label("also " + ", ".join(also), 11, ui.DIM)
			al.clip_text = true
			al.custom_minimum_size = Vector2(70, 0)
			al.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(al)
		_box.add_child(row)
	_box.add_child(ui._head("Fixed", 12, ui.GOLD))
	for pair in [["Left mouse", "Cast the chosen spell (Conjure: place)"], ["Right mouse", "Dig, or Unmake"],
			["Shift + right", "Take furniture, workshops, torches whole"], ["1-9 / wheel", "Choose a spell"],
			["Arrow keys", "Move too, unless bound to something else"], ["Esc", "Pause"], ["F11", "Fullscreen"],
			["Shift + right (satchel)", "Discard"]]:
		var r2 := HBoxContainer.new()
		var kl: Label = ui._label(String(pair[0]), 11, ui.GOLD)
		kl.custom_minimum_size = Vector2(110, 0)
		r2.add_child(kl)
		r2.add_child(ui._label(String(pair[1]), 11, ui.TEXT))
		_box.add_child(r2)
	_hint("Click a key, then press the new one. Esc cancels, Backspace clears it.")

# ------------------------------------------------------------------ parts --
func _row_label(txt: String) -> Label:
	var l: Label = ui._head(txt, 12, ui.CREAM)
	l.custom_minimum_size = Vector2(LBL_W, 0)
	return l

func _hint(txt: String) -> void:
	var h: Label = ui._label(txt, 11, ui.DIM)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD
	h.custom_minimum_size = Vector2(ROW_W, 0)
	_box.add_child(h)

## a row of choices (one lit)
func _choice(title: String, key: String, opts: Array, hint := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.add_child(_row_label(title))
	for o in opts:
		var b: Button = ui._button(String(o[0]))
		b.custom_minimum_size = Vector2(36, 0)
		var val = o[1]
		b.pressed.connect(func():
			game.set_setting(key, val)
			if key == "ui_scale":
				build.call_deferred()       # (the panel is laid out again at its new size)
			refresh())
		h.add_child(b)
		_opt.append([b, key, val])
	_box.add_child(h)
	if hint != "":
		_hint(hint)

## a slider: drag or click along it, the wheel steps it; the value saved when you let go
func _slider(title: String, key: String, lo: int, hi: int, step: int, unit: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.add_child(_row_label(title))
	var val_lbl: Label = ui._label("", 12, ui.TEXT)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(190, 11)
	bar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var redraw_v := func():
		val_lbl.text = "%d%s" % [int(game.settings.get(key, lo)), unit]
		bar.queue_redraw()
	bar.draw.connect(func():
		var v := float(int(game.settings.get(key, lo)) - lo) / float(hi - lo)
		var w := bar.size.x
		bar.draw_rect(Rect2(0, 3, w, 5), Color(0.03, 0.02, 0.06))
		bar.draw_rect(Rect2(0, 3, w, 5), ui.TRIM_DIM, false, 1.0)
		var fw := floorf((w - 2.0) * v)
		bar.draw_rect(Rect2(1, 4, fw, 3), Color(0.85, 0.66, 0.25))
		bar.draw_rect(Rect2(1, 4, fw, 1), Color(1.0, 0.9, 0.55))
		var kx := floorf(1.0 + (w - 6.0) * v)
		bar.draw_rect(Rect2(kx, 0, 5, 11), ui.OUTLINE)
		bar.draw_rect(Rect2(kx + 1, 1, 3, 9), ui.CREAM)
		bar.draw_rect(Rect2(kx + 1, 1, 3, 1), Color(1, 1, 1)))
	var set_v := func(nv: int, save: bool):
		nv = clampi(int(roundf(float(nv) / float(step))) * step, lo, hi)
		if nv != int(game.settings.get(key, lo)) or save:
			game.set_setting(key, nv, save)
		redraw_v.call()
	bar.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			set_v.call(int(game.settings.get(key, lo)) + (step if ev.button_index == MOUSE_BUTTON_WHEEL_UP else -step), true)
			bar.accept_event()
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			set_v.call(lo + int(roundf(clampf(ev.position.x / bar.size.x, 0.0, 1.0) * float(hi - lo))), not ev.pressed)
			if ev.pressed:
				ui._sfx("ui_click")
		elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			set_v.call(lo + int(roundf(clampf(ev.position.x / bar.size.x, 0.0, 1.0) * float(hi - lo))), false))
	h.add_child(bar)
	h.add_child(val_lbl)
	_box.add_child(h)
	redraw_v.call()

func refresh() -> void:
	for it in _opt:
		var b: Button = it[0]
		ui._set_chosen(b, str(game.settings.get(it[1], "")) == str(it[2]))

# ------------------------------------------------------------------ binding a key --
func _input(ev: InputEvent) -> void:
	if capture.is_empty() or not is_open():
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		get_viewport().set_input_as_handled()
		var kc: int = (ev as InputEventKey).keycode
		if kc == KEY_ESCAPE:
			capture = []
		elif kc == KEY_BACKSPACE or kc == KEY_DELETE:
			_bind(String(capture[0]), int(capture[1]), 0)
			capture = []
		elif Keys.FIXED.has(kc):
			ui.toast("%s is kept for itself" % Keys.key_name(kc), Color(1.0, 0.75, 0.6), 1.5)
			return
		else:
			_bind(String(capture[0]), int(capture[1]), kc)
			capture = []
		build()

func _bind(id: String, slot: int, kc: int) -> void:
	var ks: Array = (game.keymap.get(id, []) as Array).duplicate()
	if kc == 0:
		if slot < ks.size():
			ks.remove_at(slot)
		game.keymap[id] = ks
		game.settings["keys"] = game.keymap
		game._save_settings()
		return
	game.set_key(id, mini(slot, ks.size()), kc)
