## The minimap in the HUD's top right corner (user, 24 Nov: "get rid of arrows on the hud and just use the
## map, and maybe add a mini map for all of the hud stuff currently in space and use it for planetary things
## as well. waypoints and such"). Drawn in UI pixels (it lives in ui.gd's scaled root); N hides it.
##
## Out in space: a round radar turned the way the screen is (up on it is up on the screen), distance pressed
## toward the rim (`_rad`, logarithmic: near things spread out, a whole star system still fits), rings at 1k, 5k and 25k.
## What used to be an arrow at the screen's edge is on it (space.gd `map_marks`: the system's planets as
## discs, the nearest other systems, the waypoint, your skiff, pirates, the outpost and derelict, wrecks,
## wells, rifts, monoliths), and every rock and hull streamed in round you; you in the middle as an arrow
## the way you face; "N" on the rim is the galaxy chart's north.
##
## On a planet: a side view of the land round you, `CELLS` cells a pixel, turned like the screen: the
## ground's line from the surface table (coloured by its biome's top ground), the sea, and home, the
## skiff, villages you've been to, your workshops and altars, what a tavern charted, the waypoint, others
## of the party; what's past the edge is a pip on the edge pointing the way.
##
## Pointing at it names what's under the cursor; under it the waypoint's distance (and which way).
extends Control

const PixelFont := preload("res://scripts/pixel_font.gd")

const SP_R := 52.0              # the radar's radius (UI pixels)
const SP_K := 1000.0            # the radar's scale grows as log(1 + d / SP_K): 1k at a seventh, 25k at
const SP_FAR := 150000.0        # two thirds, the system's planets toward the rim, SP_FAR on it
const PW := 156.0               # the planet view's size
const PH := 80.0
const CELLS := 12.0             # cells a UI pixel on the planet
const TEXT_H := 11.0            # a line of text under it
const TRIM := Color(0.56, 0.48, 0.88)

var game
var ui
var mode := ""                  # "space" or "planet"
var drawn := []                 # what was drawn this frame: [where (UI px, local), text, colour] (hover, tests)
var stats := {}                 # counts by kind, for the tests
var facing := Vector2.UP        # (which way the "you" arrow pointed, for the tests)
## (user, 26 Nov: "it would be nice if there was a cursor for the space minimap and a zoom function as well"): the
## wheel over it zooms it (main's wheel, ui `mouse_over_minimap`), each view its own; 1 is as it was
var sp_zoom := 1.0
var pl_zoom := 1.0
const SP_ZOOM := [0.25, 16.0]
const PL_ZOOM := [0.5, 4.0]

## the wheel over the minimap: in (+) or out (-), by a step
func zoom_by(steps: int) -> void:
	var f := pow(1.6, float(steps))
	if mode == "space":
		sp_zoom = clampf(sp_zoom * f, SP_ZOOM[0], SP_ZOOM[1])
	else:
		pl_zoom = clampf(pl_zoom * f, PL_ZOOM[0], PL_ZOOM[1])
	queue_redraw()

## cells a UI pixel on the planet, zoomed
func _cells() -> float:
	return CELLS / pl_zoom

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_d: float) -> void:
	if not visible or game == null or game.player == null:
		return
	var want := "space" if game.space.active else "planet"
	if want != mode:
		mode = want
		custom_minimum_size = _size_for(mode)
		size = custom_minimum_size
	queue_redraw()

func _size_for(md: String) -> Vector2:
	if md == "space":
		return Vector2(SP_R * 2.0 + 4.0, SP_R * 2.0 + 4.0 + TEXT_H)
	return Vector2(PW, PH + TEXT_H)

func _draw() -> void:
	drawn.clear()
	stats.clear()
	if game == null or game.player == null:
		return
	if mode == "space":
		_draw_space()
	else:
		_draw_planet()
	_draw_hover()

# ----------------------------------------------------------------- space ---

func _rad(d: float) -> float:
	return (SP_R - 3.0) * minf(1.0, log(1.0 + maxf(d, 0.0) * sp_zoom / SP_K) / log(1.0 + SP_FAR / SP_K))

func _draw_space() -> void:
	var sp = game.space
	var c := Vector2(SP_R + 2.0, SP_R + 2.0)
	draw_circle(c, SP_R, Color(0.03, 0.025, 0.07, 0.9))
	for rd in [1000.0, 5000.0, 25000.0]:
		draw_arc(c, _rad(rd), 0.0, TAU, 48, Color(0.55, 0.5, 0.9, 0.22), 1.0)
	draw_arc(c, SP_R, 0.0, TAU, 64, TRIM, 1.0)
	var xf: Transform2D = game.screen_xf()
	var me: Vector2 = game.player.pos
	# rocks and hulls round you (the nearest of each kind is a mark too, with its name)
	for a in sp.rocks:
		if a.kind == "pirate":
			continue
		var d: Vector2 = a.pos - me
		if d.length() > 30000.0:
			continue
		var p := _sp(c, xf, d)
		var col := Color(0.62, 0.56, 0.5, 0.8)
		var big := 1.0
		match String(a.kind):
			"wreck":
				col = Color(0.75, 0.9, 0.85)
				big = 2.0
			"station":
				col = Color(0.75, 0.55, 1.0)
				big = 3.0
			"outpost":
				col = Color(1.0, 0.82, 0.45)
				big = 3.0
			"monolith":
				col = Color(0.8, 0.65, 1.0)
				big = 2.0
			"scrap":
				col = Color(0.55, 0.6, 0.62, 0.7)
		draw_rect(Rect2((p - Vector2(big, big) * 0.5).floor(), Vector2(big, big)), col)
		_count("rock")
	# the void's beasts that hunt (eels, jellies), in red; mantas in their own colour
	for b in sp.vl.beasts:
		var bd: Vector2 = b.pos - me
		if bd.length() > 20000.0:
			continue
		var bp := _sp(c, xf, bd)
		draw_rect(Rect2(bp.floor() - Vector2(1, 1), Vector2(2, 2)), Color(0.6, 0.85, 1.0, 0.8) if b.kind == "manta" else Color(1.0, 0.4, 0.45))
		_count("beast")
	# what used to have an arrow at the edge
	for mk in sp.map_marks:
		var wp: Vector2 = mk["pos"]
		var d2: Vector2 = wp - me
		var p2 := _sp(c, xf, d2)
		var col2: Color = mk["col"]
		var kind := String(mk["kind"])
		match kind:
			"planet":
				var dd := d2.length()
				var rr: float = float(mk["rad"])
				var rp := clampf((_rad(dd + rr) - _rad(dd - rr)) * 0.5, 2.0, 14.0)
				draw_circle(p2, rp + 1.0, Color(0, 0, 0, 0.6))
				draw_circle(p2, rp, col2.darkened(0.25))
				draw_arc(p2, rp, 0.0, TAU, 20, col2, 1.0)
			"star":
				_diamond(p2, 2.0, col2)
			"waypoint":
				var on := 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.006)
				_diamond(p2, 3.0, Color(1.0, 0.82, 0.3, on))
			"skiff":
				_skiff(p2, col2)
			"pirate":
				draw_rect(Rect2(p2.floor() - Vector2(2, 2), Vector2(4, 4)), Color(0, 0, 0, 0.7))
				draw_rect(Rect2(p2.floor() - Vector2(1, 1), Vector2(3, 3)), col2)
			_:
				draw_rect(Rect2(p2.floor() - Vector2(1, 1), Vector2(3, 3)), Color(0, 0, 0, 0.6))
				draw_rect(Rect2(p2.floor() - Vector2(1, 1), Vector2(2, 2)), col2)
		drawn.append([p2, "%s  %s" % [String(mk["text"]), _km(float(mk["dist"]))], col2])
		_count(kind if kind != "" else "mark")
	# north (the galaxy chart's up) on the rim
	var nd: Vector2 = xf.basis_xform(Vector2(0, -1)).normalized()
	_text(c + nd * (SP_R - 5.0) + Vector2(-2, 3), "N", Color(0.7, 0.72, 0.95, 0.8))
	# you, the way you face
	_you(c, xf.basis_xform(game.facing_dir(game.player)).normalized())
	# the waypoint's distance under it
	var wl := ""
	for mk2 in sp.map_marks:
		if String(mk2["kind"]) == "waypoint":
			wl = "Waypoint %s" % _km(float(mk2["dist"]))
	if absf(sp_zoom - 1.0) > 0.01:
		wl = ("%s  " % wl if wl != "" else "") + _zoom_text(sp_zoom)
	_footer(wl, SP_R * 2.0 + 4.0)

static func _zoom_text(z: float) -> String:
	return "x%s" % (("%.1f" % z) if z < 10.0 else str(int(round(z))))

func _sp(c: Vector2, xf: Transform2D, d: Vector2) -> Vector2:
	var sd: Vector2 = xf.basis_xform(d)
	if sd.length() < 1e-6:
		return c
	return c + sd.normalized() * _rad(d.length())

static func _km(d: float) -> String:
	if d < 1000.0:
		return "%d" % int(d)
	if d < 10000.0:
		return "%.1fk" % (d / 1000.0)
	return "%dk" % int(round(d / 1000.0))

# ---------------------------------------------------------------- planet ---

## the side of the screen the angle round the planet grows toward (+1 right, -1 left)
func _side(me: Vector2) -> float:
	var a0 := atan2(me.y, me.x)
	var t := Vector2(-sin(a0), cos(a0))
	return 1.0 if game.world_to_screen(me + t * 20.0).x >= game.world_to_screen(me).x else -1.0

func _draw_planet() -> void:
	var g = game
	var me: Vector2 = g.player.pos
	var a0 := atan2(me.y, me.x)
	var rp := me.length()
	var s := _side(me)
	var r0: float = Defs.RS0
	var cy := PH * 0.5
	draw_rect(Rect2(Vector2.ZERO, Vector2(PW, PH)), Color(0.16, 0.22, 0.36, 0.92))
	var sea := float(g.planet.get("sea", -1.0))
	var rsea: float = (Defs.RS0 - sea) if sea >= 0.0 else -1.0
	var names: Array = g.planet.get("biomes", ["forest"])
	for x in int(PW):
		var a: float = a0 + s * (float(x) + 0.5 - PW * 0.5) * _cells() / r0
		var sv: Vector4 = g.gpu.surf_at(a)
		var ys := cy - (sv.x - rp) / _cells()
		if rsea > sv.x:
			var yw := cy - (rsea - rp) / _cells()
			if yw < PH and ys > 0.0:
				draw_rect(Rect2(float(x), clampf(yw, 0.0, PH), 1.0, clampf(ys, 0.0, PH) - clampf(yw, 0.0, PH)), Color(0.18, 0.36, 0.7, 0.85))
		if ys < PH:
			var bn := String(names[clampi(int(sv.y), 0, names.size() - 1)])
			var top: Color = Defs.COLOR[int(Defs.BIOMES[bn]["top"])] if Defs.BIOMES.has(bn) else Color(0.4, 0.5, 0.3)
			var y0 := clampf(ys, 0.0, PH)
			draw_rect(Rect2(float(x), y0, 1.0, PH - y0), Color(0.2, 0.15, 0.13, 0.95))
			if ys >= 0.0:
				draw_rect(Rect2(float(x), y0, 1.0, minf(2.0, PH - y0)), top)
	_count("columns", int(PW))
	# Ore Sense (main `sense_pts`): the ore the wisp found round you, a dot each, kept till its next look; a faint
	# sweep from you as it looks
	if not g.sense_pts.is_empty():
		var dots := {}
		var pts: PackedVector2Array = g.sense_pts
		var cols: PackedColorArray = g.sense_cols
		for k in pts.size():
			var q := _pp(me, s, pts[k]).floor()
			if q.x < 1.0 or q.y < 1.0 or q.x >= PW - 1.0 or q.y >= PH - 1.0 or dots.has(q):
				continue
			dots[q] = true
			draw_rect(Rect2(q, Vector2.ONE), cols[k])
		_count("ore", dots.size())
	var since: int = 210 - int(g.sense_t)            # (main SENSE_SHOW)
	if g.sense_t > 0 and since < 40:
		var sr := 3.0 + float(since) * 0.6
		draw_arc(Vector2(PW * 0.5, cy), sr, 0.0, TAU, 24, Color(0.6, 0.9, 1.0, 0.5 * (1.0 - float(since) / 40.0)), 1.0)
	# places
	var home = g.planet_state.get("home", null)
	if home != null:
		_place(_pp(me, s, Vector2(float(home["pos"][0]), float(home["pos"][1]))), "Home", Color(1.0, 0.82, 0.35), "home")
	if g.skiff != null and g.skiff.pos.length() < Defs.R_SPACE and g.player.aboard != g.skiff:
		_place(_pp(me, s, g.skiff.pos), "Your skiff [K]", Color(0.55, 0.9, 1.0), "skiff")
	var seen: Array = g.planet_state.get("towns_seen", [])
	for t in g.builds.towns:
		if bool(t["living"]) and seen.has(int(t["seed"])):
			var tc := float(int(t["x0"]) + int(t["w"]) / 2)
			var tp: Vector2 = g.map_view._cell_world(tc, float(g.builds.ground_row(int(tc))) - 6.0)
			_place(_pp(me, s, tp), String(t["name"]), Color(0.95, 0.85, 0.6), "town")
	for st in g.workshops.list:
		var alt: bool = st.kind == "altar"
		var sname: String = String((Defs.STATIONS.get(st.kind, {}) as Dictionary).get("name", String(st.kind).capitalize()))
		_place(_pp(me, s, st.pos), sname, Color(1.0, 0.5, 0.75) if alt else Color(0.85, 0.7, 0.5), "altar" if alt else "workshop")
	for ch in g.planet_state.get("charted", []):
		_place(_pp(me, s, Vector2(float(ch["pos"][0]), float(ch["pos"][1]))), String(ch["name"]),
			Color(1.0, 0.45, 0.4) if ch["kind"] == "lair" else Color(0.75, 0.6, 1.0), "charted")
	for m in g.players:
		if m != g.player:
			_place(_pp(me, s, m.pos), "Friend", Color(0.6, 1.0, 0.7), "friend")
	var wp = g.planet_waypoint()
	var wl := ""
	if wp != null:
		var wpp := _pp(me, s, wp)
		_place(wpp, "Waypoint", Color(1.0, 0.82, 0.3), "waypoint")
		var along: float = wrapf(atan2(wp.y, wp.x) - a0, -PI, PI) * r0
		var dist: float = Vector2(along, (wp as Vector2).length() - rp).length()
		wl = "Waypoint %s %s" % [_km(dist), "→" if along * s > 0.0 else "←"]
	# you, the way you face
	_you(Vector2(PW * 0.5, cy), Vector2(float(g.player.facing), 0.0))
	draw_rect(Rect2(Vector2.ZERO, Vector2(PW, PH)), TRIM, false, 1.0)
	if absf(pl_zoom - 1.0) > 0.01:
		wl = ("%s  " % wl if wl != "" else "") + _zoom_text(pl_zoom)
	_footer(wl, PW)

## a world point on the planet in the side view (unclamped)
func _pp(me: Vector2, s: float, q: Vector2) -> Vector2:
	var a0 := atan2(me.y, me.x)
	var dx: float = wrapf(atan2(q.y, q.x) - a0, -PI, PI) * Defs.RS0 * s / _cells()
	var dy: float = (q.length() - me.length()) / _cells()
	return Vector2(PW * 0.5 + dx, PH * 0.5 - dy)

## a place in the side view: inside it a dot, past its edge a pip on the edge pointing the way
func _place(p: Vector2, text: String, col: Color, kind: String) -> void:
	var inside := p.x >= 2.0 and p.y >= 2.0 and p.x <= PW - 2.0 and p.y <= PH - 2.0
	var q := Vector2(clampf(p.x, 3.0, PW - 3.0), clampf(p.y, 3.0, PH - 3.0))
	if inside:
		if kind == "waypoint":
			var on := 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) * 0.006)
			_diamond(q, 3.0, Color(col.r, col.g, col.b, on))
		elif kind == "skiff":
			_skiff(q, col)
		else:
			draw_rect(Rect2(q.floor() - Vector2(2, 2), Vector2(4, 4)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(q.floor() - Vector2(1, 1), Vector2(3, 3)) if kind == "home" or kind == "altar" else Rect2(q.floor() - Vector2(1, 1), Vector2(2, 2)), col)
	else:
		var dir := (p - Vector2(PW, PH) * 0.5).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([q + dir * 2.5, q - dir * 1.5 + side * 2.0, q - dir * 1.5 - side * 2.0]), col)
	drawn.append([q, text, col])
	_count(kind)

# ----------------------------------------------------------------- shared ---

func _you(at: Vector2, face: Vector2) -> void:
	var on := 0.8 + 0.2 * sin(float(Time.get_ticks_msec()) * 0.006)
	var d := face.normalized() if face.length() > 0.001 else Vector2.UP
	var side := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([at + d * 4.0, at - d * 2.5 + side * 3.0, at - d * 1.0, at - d * 2.5 - side * 3.0])
	var ink := PackedVector2Array()
	for pt in pts:
		ink.append(pt + (pt - at).normalized() * 1.0)
	draw_colored_polygon(ink, Color(0, 0, 0, 0.75))
	draw_colored_polygon(pts, Color(1, 1, 1, on))
	facing = d

func _diamond(p: Vector2, r: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r - 1), p + Vector2(r + 1, 0), p + Vector2(0, r + 1), p + Vector2(-r - 1, 0)]), Color(0, 0, 0, 0.6 * col.a))
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)

func _skiff(p: Vector2, col: Color) -> void:
	var q := p.floor()
	draw_rect(Rect2(q + Vector2(-3, -1), Vector2(7, 3)), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(q + Vector2(-2, 0), Vector2(5, 1)), col)
	draw_rect(Rect2(q + Vector2(-1, -1), Vector2(2, 1)), col.lightened(0.3))

func _text(at: Vector2, txt: String, col: Color) -> void:
	var f: Font = PixelFont.make()
	draw_string(f, at.round() + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, Color(0, 0, 0, 0.7))
	draw_string(f, at.round(), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE, col)

func _footer(txt: String, w: float) -> void:
	if txt == "":
		return
	var f: Font = PixelFont.make()
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE).x
	_text(Vector2(roundf((w - tw) * 0.5), size.y - 2.0), txt, Color(1.0, 0.85, 0.45))

## what's under the cursor gets its name
func _draw_hover() -> void:
	var mp := get_local_mouse_position()
	if mp.x < 0.0 or mp.y < 0.0 or mp.x > size.x or mp.y > size.y - TEXT_H:
		return
	var best = null
	var bd := 7.0
	for it in drawn:
		var d: float = (it[0] as Vector2).distance_to(mp)
		if d < bd:
			bd = d
			best = it
	if best == null:
		return
	var f: Font = PixelFont.make()
	var txt := String(best[1])
	var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelFont.SIZE).x
	var at := Vector2(clampf((best[0] as Vector2).x - tw * 0.5, -tw + 30.0, size.x - 30.0), (best[0] as Vector2).y - 5.0)
	draw_rect(Rect2(at + Vector2(-2, -9), Vector2(tw + 4, 11)), Color(0.03, 0.02, 0.07, 0.9))
	_text(at, txt, best[2])

func _count(kind: String, n := 1) -> void:
	stats[kind] = int(stats.get(kind, 0)) + n
