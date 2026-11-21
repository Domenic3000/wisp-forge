## The map (M), a menu of its own: the game waits while it's open.
##
## "planet": the GPU draws the planet zoomed out (main sets the camera from `map_zoom_i` and
## `map_ang`; past the orbit band the picture is clear), and this draws the markers over it: you,
## the rest of the party, your home, the skiff.
## "system": the round of planets you're in, laid out as they are round each other (their discs
## grown from their biomes, as in space), the one you're on (or near) marked.
extends Node2D

var game

func _draw() -> void:
	if game == null or game.state != "map":
		return
	if game.map_tab == "system":
		_draw_system()
	else:
		_draw_planet()

# ------------------------------------------------------------- the planet ---

func _draw_planet() -> void:
	var g = game
	var home = g.planet_state.get("home", null)
	if home != null:
		var bx: Array = home["bed"]
		_house(g.world_to_screen(_cell_world(0.5 * (float(bx[0]) + float(bx[2])), float(bx[3]))), Color(1.0, 0.82, 0.35))
	if g.skiff != null and g.skiff.pos.length() < Defs.R_SPACE:
		_glyph_skiff(g.world_to_screen(g.skiff.pos), Color(0.7, 0.9, 1.0))
	# villages you've been to, and the lairs and dungeons a tavern's rumours charted (towns.gd)
	var seen: Array = g.planet_state.get("towns_seen", [])
	for t in g.builds.towns:
		if bool(t["living"]) and seen.has(int(t["seed"])):
			var tc := float(int(t["x0"]) + int(t["w"]) / 2)
			_dot(g.world_to_screen(_cell_world(tc, float(g.builds.ground_row(int(tc))) - 6.0)), Color(0.95, 0.85, 0.6), String(t["name"]))
	for ch in g.planet_state.get("charted", []):
		var cp := Vector2(float(ch["pos"][0]), float(ch["pos"][1]))
		_dot(g.world_to_screen(cp), Color(1.0, 0.45, 0.4) if ch["kind"] == "lair" else Color(0.75, 0.6, 1.0), String(ch["name"]))
	for m in g.players:
		if m == g.player:
			continue
		_dot(g.world_to_screen(m.pos), Color(0.6, 1.0, 0.7), "")
	# you, last (on top), blinking gently
	var you: Vector2 = g.world_to_screen(g.player.pos)
	var on := 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.006)
	if you.x < 0.0 or you.y < 0.0 or you.x > g.VW or you.y > g.VH:
		_edge_arrow(you, "You", Color(1, 1, 1, on))
	else:
		_dot(you, Color(1.0, 1.0, 1.0, on), "You")

## a cell's middle (surface column, row), for markers: exact in the surface shell, near enough below
static func _cell_world(col: float, row: float) -> Vector2:
	var a := (col + 0.5) / float(Defs.NS) * TAU
	return Vector2(cos(a), sin(a)) * (Defs.R_TOP - row - 0.5)

func _dot(at: Vector2, col: Color, text: String) -> void:
	var p := at.round()
	draw_rect(Rect2(p - Vector2(2, 2), Vector2(5, 5)), Color(0, 0, 0, col.a * 0.8))
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(3, 3)), col)
	if text != "":
		_label(p + Vector2(0, -6), text, col)

func _house(at: Vector2, col: Color) -> void:
	var p := at.round()
	var dark := Color(0, 0, 0, 0.8)
	draw_rect(Rect2(p + Vector2(-3, -2), Vector2(7, 5)), dark)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-4, -2), p + Vector2(0.5, -6), p + Vector2(5, -2)]), dark)
	draw_rect(Rect2(p + Vector2(-2, -2), Vector2(5, 4)), col)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-3, -2), p + Vector2(0.5, -5), p + Vector2(4, -2)]), col.darkened(0.2))
	_label(p + Vector2(0, -9), "Home", col)

func _glyph_skiff(at: Vector2, col: Color) -> void:
	var p := at.round()
	draw_rect(Rect2(p + Vector2(-4, -1), Vector2(9, 3)), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(p + Vector2(-3, 0), Vector2(7, 1)), col)
	draw_rect(Rect2(p + Vector2(-1, -1), Vector2(3, 1)), col.lightened(0.3))
	_label(p + Vector2(0, -5), "Skiff", col)

## (a marker off the edge of the map: an arrow at the edge pointing to it)
func _edge_arrow(sp: Vector2, text: String, col: Color) -> void:
	var w := float(game.VW)
	var h := float(game.VH)
	var ctr := Vector2(w, h) * 0.5
	var dir := (sp - ctr).normalized()
	var t := minf((w * 0.5 - 10.0) / maxf(absf(dir.x), 0.001), (h * 0.5 - 10.0) / maxf(absf(dir.y), 0.001))
	var at := ctr + dir * t
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([at + dir * 4.0, at - dir * 2.0 + side * 3.0, at - dir * 2.0 - side * 3.0]), col)
	_label(at - dir * 9.0, text, col)

func _label(at: Vector2, text: String, col := Color(0.9, 0.92, 1.0)) -> void:
	var f := ThemeDB.fallback_font
	var px: float = float(game.scale_px)
	draw_set_transform(at, 0.0, Vector2.ONE / px)
	var sz := 15
	var wd := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(f, Vector2(-wd * 0.5 + 1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.7))
	draw_string(f, Vector2(-wd * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(col.r, col.g, col.b, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------- the system ---

func _draw_system() -> void:
	var g = game
	var w := float(g.VW)
	var h := float(g.VH)
	draw_rect(Rect2(0, 0, w, h), Color(0.006, 0.006, 0.02))
	# a few stars (fixed: this is a chart, not a view)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for k in 160:
		var b := 0.25 + 0.5 * rng.randf()
		draw_rect(Rect2(Vector2(rng.randf() * w, rng.randf() * h).floor(), Vector2.ONE), Color(b, b, b * 1.1))
	var here := int(g.planet.get("index", 0))
	var n: int = Defs.SYSTEM.size()
	var base := (here / n) * n
	# laid out round the middle of the round, scaled to fit the screen
	var mid := Vector2.ZERO
	for i in range(base, base + n):
		mid += Defs.planet_pos(i)
	mid /= float(n)
	var far := 1.0
	for i2 in range(base, base + n):
		far = maxf(far, (Defs.planet_pos(i2) - mid).length())
	var sc := minf(w, h) * 0.36 / far
	var ctr := Vector2(w, h) * 0.5
	for i3 in range(base, base + n):
		var pl: Dictionary = Defs.make_planet(i3)
		var at := ctr + (Defs.planet_pos(i3) - mid) * sc
		var rad := 5.0 + 7.0 * clampf((float(pl["radius"]) - 1300.0) / 1300.0, 0.0, 1.0)
		var tex: Texture2D = g.space.disc_texture(i3)
		var dr := rad * 1.25                        # (the disc picture has its air round it)
		draw_texture_rect(tex, Rect2(at - Vector2(dr, dr), Vector2(dr, dr) * 2.0), false)
		var visited: bool = i3 == here or FileAccess.file_exists(g._world_path(i3))
		var tc := Color(0.6, 1.0, 0.7) if i3 == here else (Color(0.9, 0.9, 1.0) if visited else Color(0.6, 0.62, 0.75))
		if i3 == here:
			draw_arc(at, dr + 3.0, 0.0, TAU, 32, tc, 1.0)
		var walled: bool = i3 != here and i3 > g.skiff_reach()
		if walled:
			# beyond the skiff's reach: its storm belt, a dashed ring in its colour
			var bc: Color = Defs.climate(pl)["belt"]
			for q in 16:
				var a0 := TAU * float(q) / 16.0 + float(Time.get_ticks_msec()) * 0.0004
				draw_arc(at, dr + 5.0, a0, a0 + TAU / 32.0, 4, Color(bc.r, bc.g, bc.b, 0.75), 1.0)
		_label(at + Vector2(0, dr + 9.0), String(pl["name"]), tc)
		_label(at + Vector2(0, dr + 15.0), "you are here" if i3 == here and not g.space.active else String(pl.get("kind", "")) + ("" if visited else " · unexplored") + (" · storm belt: needs a Core Drive" if walled else ""), Color(tc.r, tc.g, tc.b, 0.7))
	# out in space: where you are between them
	if g.space.active:
		var me: Vector2 = ctr + (g.player.pos + Defs.planet_pos(g.space.home) - mid) * sc
		var on := 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.006)
		_dot(me, Color(1, 1, 1, on), "You")
