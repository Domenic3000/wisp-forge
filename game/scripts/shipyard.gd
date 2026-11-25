## The ship builder (user, 24 Nov: "can we create a ship builder instead ... and then when your not in the ship
## builder you just repair"; chose: opens wherever the ship is parked: landed on a planet or docked at a station
## or outpost). main state "shipyard": the world waits, the HUD steps aside, ui.gd's builder panel lists the
## parts (`Build` CAT_SHIP pieces: the hull materials, Helm, Seat) and a Door, with what you hold of each, the
## tools, Undo / New keel / Done and the ship's figures; this draws the ship big on a blueprint grid.
##
## Left button lays the chosen part (a brush `brush` cells across; Shift + drag a rectangle), right button cuts
## away (the same). A hull cell only goes where it joins the ship (`sk.can_hull`, a stroke's cells joining
## through each other); it costs its material (and a little mana) and cutting gives it back. The helm's floor
## (`sk.keep_cells`) can't be cut, and whatever no longer joins it falls away, refunded (`sk.prune_loose`).
## Helm: click where it should stand (a floor with room over it). Seat: click to add one (4 planks), click one
## to take it out. Door: click an outer hull cell: F there steps into the ship's pocket dimension (pocket.gd).
## Z (or Ctrl + Z) undoes a stroke, materials and all. New keel (clicked twice) gives back the whole hull and
## starts again from a keel. WASD or a middle drag pans, the wheel zooms. B or Esc closes: the ship is kept
## (items["ship"]) and set clear of the ground or the bay it's in.
extends Node2D

const PixelFont := preload("res://scripts/pixel_font.gd")
const Build := preload("res://scripts/build.gd")
const Skiff := preload("res://scripts/skiff.gd")

var game
var sk = null
var active := false
var cz := 5.0                   # game pixels per cell
var anchor := Vector2.ZERO      # (game pixels) where cell (0, 0) of the ship's grid is drawn
var parts: Array = []           # the palette: Build's ship pieces (no Cut Away) and the Door
var sel := 1                    # (Planking)
var brush := 1
var _drag := 0                  # 1 laying, 2 cutting
var _rect_from := Vector2i(-9999, -9999)
var _pan_drag := false
var _last := Vector2i(-9999, -9999)
var undo: Array = []            # [{ship, inv}] before each stroke
var spent := {}                 # material -> net cells laid this visit (what the panel shows as cost)
var keel_t := 0                 # (New keel asked once: a second click within this many frames does it)
var hover := Vector2i(-1, -1)
var stats := {"laid": 0, "cut": 0, "fell": 0, "undone": 0}
var note := ""                  # a word for the panel (why something didn't go)

func _ready() -> void:
	visible = false
	z_index = 5
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## the ship is parked: landed on a planet, or in a station's bay or an outpost's hangar out in space
func parked() -> bool:
	var s = game.skiff
	if s == null:
		return false
	if game.space.active:
		return game.space.docked != null or game.space.docked_st != null
	return s.grounded and s.vel.length() < 1.0

func open() -> bool:
	if game.skiff == null or not game.items.has("skiff"):
		game.ui.toast("You have no ship yet: forge its keel at the Wisp Forge", Color(1, 0.7, 0.5), 2.5)
		return false
	if not parked():
		game.ui.toast("Land, or dock at a station or outpost, to open the ship builder", Color(1, 0.75, 0.55), 3.0)
		return false
	sk = game.skiff
	sk.ensure_door()
	parts = []
	for p in Build.in_cat(Build.pieces(), Build.CAT_SHIP):
		if String(p["kind"]) != "cut":
			parts.append(p)
	parts.append({"cat": 9, "name": "Pocket Door", "kind": "door", "cost": {}})
	sel = clampi(sel, 0, parts.size() - 1)
	active = true
	visible = true
	game.state = "shipyard"
	game.build_on = false
	cz = clampf(floor(minf(float(game.VW) * 0.55 / float(sk.w), float(game.VH) * 0.7 / float(sk.h))), 2.0, 8.0)
	anchor = (Vector2(float(game.VW) * 0.5 + 40.0, float(game.VH) * 0.5) - Vector2(sk.w, sk.h) * 0.5 * cz).round()
	undo.clear()
	spent.clear()
	note = ""
	game.ui.show_shipyard(game)
	return true

func close() -> void:
	if not active:
		return
	active = false
	visible = false
	game.state = "play"
	game.ui.hide_shipyard()
	_settle_ship()
	game.items["ship"] = sk.save_cells()
	game.items["hull_cells"] = maxi(int(game.items.get("hull_cells", 0)), sk.hull_count())
	game.save_game()

## after building: the ship set clear of the ground (on a planet) or of the bay's walls (out there)
func _settle_ship() -> void:
	if game.space.active:
		var st = game.space.docked_st if game.space.docked_st != null else game.space.docked
		if st == null:
			return
		var up: Vector2 = -st.axis_y()
		for k in 60:
			var clear := true
			for o in sk.outline:
				if game.space._rock_solid(sk.to_world(o)):
					clear = false
					break
			if clear:
				return
			sk.pos += up * 2.0
		return
	game._use_grid(game.player)
	var up2: Vector2 = sk.pos.normalized()
	for k2 in 60:
		if game._skiff_fits():
			return
		sk.pos += up2 * 2.0

# ------------------------------------------------------------- the canvas ---

func _origin() -> Vector2:
	return anchor

## the helm's cell where it was on the canvas, after the grid changed under it (an undo, a new keel)
func _hold_helm(before: Vector2) -> void:
	if not sk.seat_cells.is_empty():
		anchor = before - Vector2(sk.seat_cells[0]) * cz

func cell_at(sp: Vector2) -> Vector2i:
	var c := (sp - _origin()) / cz
	return Vector2i(int(floor(c.x)), int(floor(c.y)))

func screen_of(i: int, j: int) -> Vector2:
	return _origin() + Vector2(i, j) * cz

func process(_delta: float) -> void:
	if not active:
		return
	var pv := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pv.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pv.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pv.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pv.y += 1.0
	anchor -= pv * 6.0
	if keel_t > 0:
		keel_t -= 1
	var mp: Vector2 = get_viewport().get_mouse_position() / float(game.scale_px)
	hover = cell_at(mp)
	if _drag != 0 and not Input.is_key_pressed(KEY_SHIFT):
		var h2 := hover
		if h2 != _last:
			_stroke(_brush_cells(h2), _drag == 2)
			_last = h2
	queue_redraw()

func key(k: int, ctrl: bool) -> void:
	if k == KEY_ESCAPE or k == KEY_B:
		close()
	elif k == KEY_Z:
		do_undo()
	elif k == KEY_BRACKETLEFT:
		brush = maxi(1, brush - 1)
	elif k == KEY_BRACKETRIGHT:
		brush = mini(6, brush + 1)
	elif k >= KEY_1 and k <= KEY_9 and k - KEY_1 < parts.size():
		sel = k - KEY_1
	elif k == KEY_0 and parts.size() >= 10:
		sel = 9
	elif ctrl and k == KEY_Z:
		do_undo()

func mouse(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mp: Vector2 = ev.position / float(game.scale_px)
		if ev.pressed and game.ui.mouse_over_ui(false):
			return
		var c := cell_at(mp)
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if ev.pressed:
					_zoom(1.25, mp)
			MOUSE_BUTTON_WHEEL_DOWN:
				if ev.pressed:
					_zoom(0.8, mp)
			MOUSE_BUTTON_MIDDLE:
				_pan_drag = ev.pressed
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				var cut: bool = ev.button_index == MOUSE_BUTTON_RIGHT
				if ev.pressed:
					var kind := String(parts[sel]["kind"])
					if not cut and kind in ["helm", "seat", "door"]:
						click_part(c)
						return
					_push_undo()
					if Input.is_key_pressed(KEY_SHIFT):
						_rect_from = c
						_drag = 2 if cut else 1
					else:
						_drag = 2 if cut else 1
						_last = c
						_stroke(_brush_cells(c), cut)
				else:
					if _drag != 0 and _rect_from.x > -9999:
						_stroke(_rect_cells(_rect_from, c), _drag == 2)
					_drag = 0
					_rect_from = Vector2i(-9999, -9999)
	elif ev is InputEventMouseMotion and _pan_drag:
		anchor += ev.relative / float(game.scale_px)

func _zoom(f: float, at: Vector2) -> void:
	var nz := clampf(cz * f, 1.5, 14.0)
	anchor = at - (at - anchor) * (nz / cz)
	cz = nz

func _brush_cells(c: Vector2i) -> Array:
	var out := []
	for dj in brush:
		for di in brush:
			out.append(Vector2i(c.x - brush / 2 + di, c.y - brush / 2 + dj))
	return out

func _rect_cells(a: Vector2i, c: Vector2i) -> Array:
	var out := []
	for j in range(mini(a.y, c.y), maxi(a.y, c.y) + 1):
		for i in range(mini(a.x, c.x), maxi(a.x, c.x) + 1):
			out.append(Vector2i(i, j))
	return out

# ---------------------------------------------------------------- editing ---

func _push_undo() -> void:
	undo.append({"ship": sk.save_cells(), "pos": sk.pos, "inv": game.player.inv.duplicate(), "spent": spent.duplicate()})
	if undo.size() > 30:
		undo.pop_front()

func do_undo() -> void:
	if undo.is_empty():
		note = "Nothing to undo"
		return
	var u: Dictionary = undo.pop_back()
	var helm_at: Vector2 = anchor + Vector2(sk.seat_cells[0]) * cz if not sk.seat_cells.is_empty() else anchor
	_load_keep(u["ship"])
	sk.pos = u["pos"]
	_hold_helm(helm_at)
	game.player.inv = u["inv"]
	spent = u["spent"]
	stats["undone"] += 1
	note = "Undone"

## what a hull part costs per cell: [material paid, how many]
func _pay_of(p: Dictionary) -> int:
	return int((p["cost"] as Dictionary).keys()[0])

## lay (or, `cut`, take away) the cells: laid only where they join the ship (in an order that lets a stroke
## grow out from it); cut ones refunded, and anything left loose falls away (refunded too)
func _stroke(cells: Array, cut: bool) -> void:
	var m = game.player
	var p: Dictionary = parts[sel]
	if cut:
		var keep := {}
		for kc in sk.keep_cells():
			keep[kc] = true
		var old_com: Vector2 = sk.com
		var n := 0
		for c in cells:
			var cv: Vector2i = c
			if keep.has(cv) or sk.at(cv.x, cv.y) == 0:
				continue
			var gm: int = sk.cut(cv.x, cv.y)
			if gm != 0:
				_refund(gm, 1)
				n += 1
		if n == 0:
			if keep.size() > 0 and cells.any(func(e): return keep.has(e)):
				note = "The helm stands on that: it stays"
			return
		var fell: Dictionary = sk.prune_loose()
		var nf := 0
		for fm in fell:
			_refund(int(fm), int(fell[fm]))
			nf += int(fell[fm])
		stats["cut"] += n
		stats["fell"] += nf
		_check_seats()
		sk.finish_edit(old_com)
		note = "Cut %d" % n + (" · %d came loose and fell away" % nf if nf > 0 else "")
		game.audio.play("dig", sk.pos, 0.4)
		return
	if String(p["kind"]) != "hull":
		return
	var mat: int = int(p["mat"])
	var pay := _pay_of(p)
	var want := {}
	for c2 in cells:
		var cv2: Vector2i = c2
		if sk.at(cv2.x, cv2.y) == 0 and not sk.in_seat(cv2.x, cv2.y):
			want[cv2] = true
	if want.is_empty():
		return
	var old_com2: Vector2 = sk.com
	var acc := Vector2i.ZERO
	var laid := 0
	var short := false
	var grew := true
	while grew and not want.is_empty():
		grew = false
		for c3 in want.keys():
			var cv3: Vector2i = (c3 as Vector2i) + acc
			if not sk.can_hull(cv3.x, cv3.y):
				continue
			if m.inv[pay] < 1:
				short = true
				break
			var off: Vector2i = sk.grow_for(cv3.x, cv3.y)
			if off != Vector2i.ZERO:
				acc += off
				cv3 += off
				old_com2 += Vector2(off)
				anchor -= Vector2(off) * cz      # (the grid grew round it: the ship stays put on the canvas)
			sk.add_hull(cv3.x, cv3.y, mat, game._hull_variant(mat, cv3.x, cv3.y))
			m.inv[pay] -= 1
			spent[pay] = int(spent.get(pay, 0)) + 1
			want.erase(c3)
			laid += 1
			grew = true
		if short:
			break
	if laid > 0:
		sk.finish_edit(old_com2)
		stats["laid"] += laid
		note = ""
		game.audio.play("place", sk.pos, 0.35)
	if short:
		note = "Out of %s" % Defs.NAMES[pay]
	elif laid == 0:
		note = "A new cell has to join the ship"

func _refund(gm: int, n: int) -> void:
	var r := gm
	if r == Defs.RUNESTONE:
		r = Defs.MASONRY
	elif r == Defs.SCAFFOLD:
		r = Defs.PLANK
	game.player.inv[r] += n
	spent[r] = int(spent.get(r, 0)) - n

## a seat left with no floor under it is taken out (4 planks back)
func _check_seats() -> void:
	for k in range(sk.seat_cells.size() - 1, 0, -1):
		var c: Vector2i = sk.seat_cells[k]
		if sk.at(c.x, c.y + 1) == 0 and sk.riders[k] == null:
			sk.remove_seat(k)
			game.player.inv[Defs.PLANK] += 4

## the helm, a seat or the door: a click
func click_part(c: Vector2i) -> void:
	var p: Dictionary = parts[sel]
	match String(p["kind"]):
		"helm", "seat":
			var helm: bool = String(p["kind"]) == "helm"
			if not helm:
				var ex: int = sk.seat_near(c.x, c.y)
				if ex >= 0:
					if sk.riders[ex] != null:
						note = "Someone's sitting there"
						return
					_push_undo()
					sk.remove_seat(ex)
					game.player.inv[Defs.PLANK] += 4
					note = "Seat taken out"
					return
			var at_j := -1
			for jj in range(c.y, c.y + 24):
				if sk.seat_ok(c.x, jj, 0 if helm else -1):
					at_j = jj
					break
			if at_j < 0:
				note = "It needs a floor with room over it (7 across, 17 up)"
				return
			if not helm:
				if sk.seat_cells.size() >= Skiff.MAX_SEATS:
					note = "Eight seats at most"
					return
				if game.player.inv[Defs.PLANK] < 4:
					note = "A seat needs 4 planks"
					return
				_push_undo()
				sk.add_seat(c.x, at_j)
				game.player.inv[Defs.PLANK] -= 4
				note = "Seat added"
			else:
				_push_undo()
				sk.set_helm(c.x, at_j)
				# (whatever no longer joins the helm's new floor falls away)
				var old_com: Vector2 = sk.com
				var fell: Dictionary = sk.prune_loose()
				for fm in fell:
					_refund(int(fm), int(fell[fm]))
				sk.finish_edit(old_com)
				note = "The helm moved"
			game.audio.play("place", sk.pos, 0.5)
		"door":
			if sk.at(c.x, c.y) == 0:
				note = "The door goes on a hull cell"
				return
			var open := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if sk.at(c.x + (d as Vector2i).x, c.y + (d as Vector2i).y) == 0:
					open = true
			if not open:
				note = "The door goes on an outer edge of the hull"
				return
			_push_undo()
			sk.door_cell = c
			note = "The pocket's door is here"
			game.audio.play("blink", sk.pos, 0.5)

## New keel (asked twice): every hull cell given back, then a fresh keel paid for as forged
func new_keel() -> void:
	if keel_t <= 0:
		keel_t = 180
		note = "Click New keel again to give back the whole hull and start from a keel"
		return
	keel_t = 0
	var fresh = Skiff.make_keel(sk.design_seed)
	var back := {}
	for k in sk.design.size():
		var dm: int = sk.design[k]
		if dm != 0 and sk.cells[k] != 0:
			back[dm] = int(back.get(dm, 0)) + 1
	var need := {}
	for k2 in fresh.design.size():
		var fm: int = fresh.design[k2]
		if fm != 0:
			need[fm] = int(need.get(fm, 0)) + 1
	for s in range(1, sk.seat_cells.size()):
		back[Defs.PLANK] = int(back.get(Defs.PLANK, 0)) + 4
	var inv: PackedInt32Array = game.player.inv.duplicate()
	for bm in back:
		inv[_paid(int(bm))] += int(back[bm])
	for nm in need:
		inv[_paid(int(nm))] -= int(need[nm])
		if inv[_paid(int(nm))] < 0:
			note = "A keel needs %s you don't have" % Defs.NAMES[_paid(int(nm))]
			return
	if sk.riders.size() > 1:
		for r in range(1, sk.riders.size()):
			if sk.riders[r] != null:
				note = "Someone's aboard in a seat: they have to step off first"
				return
	_push_undo()
	var old_pos: Vector2 = sk.pos
	var old_com: Vector2 = sk.com
	var old_helm: Vector2 = Vector2(sk.seat_cells[0]) if not sk.seat_cells.is_empty() else Vector2.ZERO
	var helm_at: Vector2 = anchor + old_helm * cz
	_load_keep(fresh.save_cells())
	# (the new keel's helm where the old one was in the world)
	sk.pos = old_pos + sk.axis_x() * ((old_helm.x - old_com.x) - (float(sk.seat_cells[0].x) - sk.com.x)) \
		+ sk.axis_y() * ((old_helm.y - old_com.y) - (float(sk.seat_cells[0].y) - sk.com.y))
	_hold_helm(helm_at)
	game.player.inv = inv
	spent.clear()
	note = "A fresh keel: build out from the helm"

## a ship's cells loaded in its place, whoever was aboard kept in their seats (the helm's rider at the helm)
func _load_keep(data: Dictionary) -> void:
	var was: Array = sk.riders.duplicate()
	sk.load_cells(data)
	for k in was.size():
		var r = was[k]
		if r == null:
			continue
		var at: int = k if k < sk.riders.size() and sk.riders[k] == null else sk.riders.find(null)
		if at >= 0:
			sk.riders[at] = r
		else:
			r.aboard = null
			r.deck = false

func _paid(m: int) -> int:
	if m == Defs.RUNESTONE:
		return Defs.MASONRY
	if m == Defs.SCAFFOLD:
		return Defs.PLANK
	return m

## the ship's figures for the panel
func figures() -> Dictionary:
	var eng := 0
	for k in sk.design.size():
		if sk.design[k] == Defs.WISP and sk.cells[k] != 0:
			eng += 1
	return {"cells": sk.hull_count(), "size": "%d x %d" % [sk.w, sk.h], "mass": int(sk.mass), "engines": eng,
		"drive": int(round(sk.drive() * 100.0)), "hold": sk.hold_cap(), "seats": sk.seat_cells.size()}

# ---------------------------------------------------------------- drawing ---

func _draw() -> void:
	if not active or sk == null:
		return
	var vw := float(game.VW)
	var vh := float(game.VH)
	draw_rect(Rect2(0, 0, vw, vh), Color(0.05, 0.06, 0.13))
	var o := _origin()
	# the blueprint grid: every cell faint when close, every ten stronger
	var i0 := int(floor(-o.x / cz)) - 1
	var i1 := int(ceil((vw - o.x) / cz)) + 1
	var j0 := int(floor(-o.y / cz)) - 1
	var j1 := int(ceil((vh - o.y) / cz)) + 1
	for i in range(i0, i1):
		var x := o.x + float(i) * cz
		if i % 10 == 0:
			draw_line(Vector2(x, 0), Vector2(x, vh), Color(0.25, 0.35, 0.6, 0.35), 1.0)
		elif cz >= 5.0:
			draw_line(Vector2(x, 0), Vector2(x, vh), Color(0.2, 0.28, 0.5, 0.12), 1.0)
	for j in range(j0, j1):
		var y := o.y + float(j) * cz
		if j % 10 == 0:
			draw_line(Vector2(0, y), Vector2(vw, y), Color(0.25, 0.35, 0.6, 0.35), 1.0)
		elif cz >= 5.0:
			draw_line(Vector2(0, y), Vector2(vw, y), Color(0.2, 0.28, 0.5, 0.12), 1.0)
	# the largest the ship can grow (round its middle)
	var lim := Rect2(o + (Vector2(sk.w, sk.h) - Vector2(Skiff.MAX_W, Skiff.MAX_H)) * 0.5 * cz, Vector2(Skiff.MAX_W, Skiff.MAX_H) * cz)
	draw_rect(lim, Color(0.5, 0.4, 0.9, 0.25), false, 1.0)
	# its back layer (faint), then the hull: one picture, made again when it changes
	draw_texture_rect(_picture(), Rect2(o, Vector2(sk.w, sk.h) * cz), false)
	# the helm's floor (kept), the seats' spaces, the door
	for kc in sk.keep_cells():
		var cv: Vector2i = kc
		draw_rect(Rect2(o + Vector2(cv) * cz, Vector2(cz, cz)), Color(1.0, 0.85, 0.3, 0.9), false, 1.0)
	for s in sk.seat_cells.size():
		var sc: Vector2i = sk.seat_cells[s]
		var sr := Rect2(o + Vector2(sc.x - 3, sc.y - 16) * cz, Vector2(7, 17) * cz)
		draw_rect(sr, Color(0.55, 0.9, 1.0, 0.12) if s > 0 else Color(1.0, 0.85, 0.35, 0.14))
		draw_rect(sr, Color(0.55, 0.9, 1.0, 0.7) if s > 0 else Color(1.0, 0.85, 0.35, 0.8), false, 1.0)
	var dc: Vector2i = sk.door()
	var dr := Rect2(o + Vector2(dc) * cz - Vector2(1, 1), Vector2(cz + 2, cz + 2))
	var pul := 0.6 + 0.4 * sin(float(Engine.get_process_frames()) * 0.1)
	draw_rect(dr, Color(0.8, 0.55, 1.0, pul), false, 2.0)
	# what the cursor would do
	if not game.ui.mouse_over_ui(false):
		var kind := String(parts[sel]["kind"])
		var pc := Color(1.0, 1.0, 1.0, 0.35)
		var cells := []
		if _rect_from.x > -9999:
			cells = _rect_cells(_rect_from, hover)
			pc = Color(1.0, 0.45, 0.4, 0.4) if _drag == 2 else Color(0.6, 1.0, 0.7, 0.35)
		elif kind == "hull":
			cells = _brush_cells(hover)
			pc = Color.hex((Defs.PAL[int(parts[sel]["mat"]) * 4] << 8) | 0x99)
		else:
			cells = [hover]
		for c2 in cells:
			draw_rect(Rect2(o + Vector2(c2) * cz, Vector2(cz, cz)), pc)
	# which way is forward
	_label(Vector2(o.x + float(sk.w) * cz + 14.0, o.y + float(sk.h) * cz * 0.5), "Bow →", Color(0.7, 0.78, 1.0))

var _pic: ImageTexture
var _pic_key := ""
func _picture() -> ImageTexture:
	var key := "%d|%d|%d|%d|%d" % [sk.w, sk.h, hash(sk.cells), hash(sk.bg), hash(sk.vars)]
	if key == _pic_key and _pic != null:
		return _pic
	_pic_key = key
	var img := Image.create(sk.w, sk.h, false, Image.FORMAT_RGBA8)
	for jj in sk.h:
		for ii in sk.w:
			var k: int = jj * sk.w + ii
			var m := int(sk.cells[k])
			if m != 0:
				var c := Color.hex((Defs.PAL[m * 4 + (int(sk.vars[k]) & 3)] << 8) | 0xff)
				if m == Defs.GLASS:
					c.a = 0.5
				img.set_pixel(ii, jj, c)
			elif int(sk.bg[k]) != 0:
				var bc := Color.hex((Defs.PAL[int(sk.bg[k]) * 4 + (int(sk.bgv[k]) & 3)] << 8) | 0xff).darkened(0.5)
				bc.a = 0.5
				img.set_pixel(ii, jj, bc)
	if _pic == null or _pic.get_width() != sk.w or _pic.get_height() != sk.h:
		_pic = ImageTexture.create_from_image(img)
	else:
		_pic.update(img)
	return _pic

func _label(at: Vector2, text: String, col: Color) -> void:
	var f: Font = PixelFont.make()
	var px: float = float(game.scale_px)
	var u: int = game.ui.U
	draw_set_transform(at.round(), 0.0, Vector2.ONE / px)
	var sz := PixelFont.SIZE * u
	var wd := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(f, Vector2(-wd * 0.5 + u, u), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.7))
	draw_string(f, Vector2(-wd * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
