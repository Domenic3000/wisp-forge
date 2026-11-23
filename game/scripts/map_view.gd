## The map (M), a menu of its own: the game waits while it's open.
##
## "planet": the GPU draws the planet zoomed out (main sets the camera from `map_zoom_i` and
## `map_ang`; past the orbit band the picture is clear), and this draws the markers over it: you,
## the rest of the party, your home, the skiff.
## "space" (Tab; user, 22 Nov: "there is no space map"): a chart of the galaxy, north up, from a few
## sectors across out to hundreds of systems (`gz`, cells a pixel; wheel or + / - zoom, WASD or a drag
## pans, H back to you). Space you haven't seen lies under a fog (space.gd `seen`, its sectors); the
## nebulae show through it faintly. Every system's star is on it; a charted one (you've been near it)
## shows its name and its planets (discs grown from their biomes, a storm belt's dashed ring round those
## out of reach), and close in, what lies in the explored sectors (asteroid fields, comets, wrecks). A click sets
## a waypoint (space.gd shows it out there, a marker at the edge when it's off screen); a right click
## clears it.
extends Node2D

const PixelFont := preload("res://scripts/pixel_font.gd")
const Galaxy := preload("res://scripts/galaxy.gd")
const Z_MIN := 25.0
const Z_MAX := 60000.0
var game
var gc := PackedFloat64Array([0.0, 0.0])     # the chart's middle (galaxy cells)
var gz := 300.0                              # cells a pixel
var _bg: ImageTexture = null                 # the fog and the nebulae, drawn small and scaled up
var _bg_key := ""
const BG_STEP := 4                           # (screen pixels per pixel of that picture)

func _draw() -> void:
	if game == null or game.state != "map":
		return
	if game.map_tab == "space":
		_draw_space()
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
	var f: Font = PixelFont.make()
	var px: float = float(game.scale_px)
	var u: int = game.ui.U
	draw_set_transform(at.round(), 0.0, Vector2.ONE / px)
	var sz := PixelFont.SIZE * u
	var wd := roundf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x / u) * u
	draw_string(f, Vector2(-roundf(wd * 0.5 / u) * u + u, u), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.7))
	draw_string(f, Vector2(-roundf(wd * 0.5 / u) * u, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(col.r, col.g, col.b, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------- the galaxy ---

## open on you
func centre_on_you() -> void:
	gc = game.space.player_g()

func to_screen(g: PackedFloat64Array) -> Vector2:
	return Vector2(game.VW, game.VH) * 0.5 + Vector2(g[0] - gc[0], g[1] - gc[1]) / gz

func to_galaxy(sp: Vector2) -> PackedFloat64Array:
	var d: Vector2 = (sp - Vector2(game.VW, game.VH) * 0.5) * gz
	return PackedFloat64Array([gc[0] + d.x, gc[1] + d.y])

func zoom_by(f: float) -> void:
	gz = clampf(gz * f, Z_MIN, Z_MAX)

func pan(d: Vector2) -> void:
	gc[0] += d.x * gz
	gc[1] += d.y * gz

## the fog of unexplored space and the nebulae, as a small picture (made again when the view moves)
func _background() -> void:
	var w: int = int(game.VW) / BG_STEP + 1
	var h: int = int(game.VH) / BG_STEP + 1
	var key := "%d_%d_%.0f_%.0f_%.2f_%d" % [w, h, gc[0], gc[1], gz, game.space.seen.size()]
	if key == _bg_key and _bg != null:
		return
	_bg_key = key
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var seen: Dictionary = game.space.seen
	var cell := gz * BG_STEP
	for y in h:
		for x in w:
			var gx: float = gc[0] + (float(x * BG_STEP) - float(game.VW) * 0.5) * gz
			var gy: float = gc[1] + (float(y * BG_STEP) - float(game.VH) * 0.5) * gz
			var nb: Array = Galaxy.nebula(gx, gy)
			var nd: float = nb[0]
			var ncol: Color = nb[1]
			# explored: any sector under this pixel seen (zoomed far out, a pixel covers many)
			var ex := false
			if cell <= Galaxy.SECTOR * 2.0:
				ex = seen.has(Galaxy.key_of(Galaxy.sector_of(gx, gy)))
			else:
				ex = seen.has(Galaxy.key_of(Galaxy.sector_of(gx, gy))) or seen.has(Galaxy.key_of(Galaxy.sector_of(gx + cell * 0.5, gy + cell * 0.5)))
			# (the fog: a grey murk over what you haven't seen; the nebulae show through it faintly)
			var c := Color(0.01, 0.01, 0.03) if ex else Color(0.05, 0.048, 0.07)
			c = c.lerp(Color(ncol.r, ncol.g, ncol.b), nd * (0.3 if ex else 0.12))
			img.set_pixel(x, y, c)
	_bg = ImageTexture.create_from_image(img)

func _draw_space() -> void:
	var g = game
	var w := float(g.VW)
	var h := float(g.VH)
	_background()
	draw_texture_rect(_bg, Rect2(Vector2.ZERO, Vector2(_bg.get_width(), _bg.get_height()) * BG_STEP), false)
	var tt := float(Time.get_ticks_msec()) * 0.001
	var g0 := to_galaxy(Vector2(-40, -40))
	var g1 := to_galaxy(Vector2(w + 40, h + 40))
	# the sector grid, close in
	if gz < 160.0:
		var s0 := Galaxy.sector_of(g0[0], g0[1])
		var s1 := Galaxy.sector_of(g1[0], g1[1])
		for sx in range(s0.x, s1.x + 2):
			var x0 := to_screen(Galaxy.sector_g(Vector2i(sx, 0))).x
			draw_line(Vector2(x0, 0), Vector2(x0, h), Color(0.4, 0.5, 0.8, 0.07), 1.0)
		for sy in range(s0.y, s1.y + 2):
			var y0 := to_screen(Galaxy.sector_g(Vector2i(0, sy))).y
			draw_line(Vector2(0, y0), Vector2(w, y0), Color(0.4, 0.5, 0.8, 0.07), 1.0)
	# what lies in the explored sectors, close in
	if gz < 420.0:
		var t0 := Galaxy.sector_of(g0[0], g0[1])
		var t1 := Galaxy.sector_of(g1[0], g1[1])
		for sy2 in range(t0.y, t1.y + 1):
			for sx2 in range(t0.x, t1.x + 1):
				var sct := Vector2i(sx2, sy2)
				if not g.space.seen.has(Galaxy.key_of(sct)):
					continue
				var sg := Galaxy.sector_g(sct)
				for c in Galaxy.sector_content(sct):
					var at: Vector2 = c["at"]
					var sp := to_screen(PackedFloat64Array([sg[0] + at.x, sg[1] + at.y]))
					if c["type"] == "comet":
						var cp: Vector2 = Galaxy.comet_at(c["rocks"][0]["orbit"], g.time)
						var csp := to_screen(PackedFloat64Array([sg[0] + at.x + cp.x, sg[1] + at.y + cp.y]))
						draw_line(csp, csp + (csp - sp).normalized() * 6.0, Color(0.6, 0.85, 1.0, 0.5), 1.0)
						draw_rect(Rect2(csp.floor() - Vector2(1, 1), Vector2(3, 3)), Color(0.85, 0.95, 1.0))
						if gz < 140.0:
							_label(csp + Vector2(0, -5), "Comet", Color(0.75, 0.9, 1.0))
					elif c["type"] == "wreck":
						# (a little broken hull)
						var wsp := sp.floor()
						draw_rect(Rect2(wsp + Vector2(-3, -1), Vector2(6, 2)), Color(0.62, 0.68, 0.74))
						draw_rect(Rect2(wsp + Vector2(0, -2), Vector2(2, 1)), Color(0.62, 0.68, 0.74))
						draw_rect(Rect2(wsp + Vector2(1, -1), Vector2(1, 1)), Color(0.05, 0.06, 0.1))
						draw_rect(Rect2(wsp + Vector2(-4, 0), Vector2(1, 1)), Color(0.5, 0.85, 1.0))
						if gz < 140.0:
							_label(wsp + Vector2(0, -6), String(c["name"]), Color(0.75, 0.9, 0.85))
					else:
						var big: bool = c.get("big", false)
						for q in (7 if big else 4):
							var o := Vector2(float((q * 37) % 7) - 3.0, float((q * 53) % 5) - 2.0) * (1.6 if big else 1.0)
							draw_rect(Rect2((sp + o).floor(), Vector2.ONE * (2 if q == 0 else 1)), Color(0.85, 0.75, 0.6))
						if gz < 140.0:
							_label(sp + Vector2(0, -6), String(c["name"]), Color(0.9, 0.8, 0.65))
	# the star systems: every star; a charted one named, with its planets close in
	var c0 := Vector2i(int(floor(g0[0] / Defs.SYS_GAP)) - 1, int(floor(g0[1] / Defs.SYS_GAP)) - 1)
	var c1 := Vector2i(int(ceil(g1[0] / Defs.SYS_GAP)) + 1, int(ceil(g1[1] / Defs.SYS_GAP)) + 1)
	var here_sys: int = int(g.space.home) / Defs.SYSTEM.size() if g.space.active else int(g.planet.get("index", 0)) / Defs.SYSTEM.size()
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var r: int = Defs.spiral_index(Vector2i(cx, cy))
			var sgp: PackedFloat64Array = Defs.system_g(r)
			var ssp := to_screen(sgp)
			if ssp.x < -60.0 or ssp.y < -60.0 or ssp.x > w + 60.0 or ssp.y > h + 60.0:
				continue
			var known: bool = g.space.charted.has(r)
			var scol: Color = Galaxy.star_col(r)
			if gz > 2500.0 or not known:
				# a star: a cross of light (brighter once charted)
				var a := 0.95 if known else 0.5
				draw_circle(ssp, 3.0, Color(scol.r, scol.g, scol.b, 0.15 * a))
				draw_rect(Rect2(ssp.floor() - Vector2(1, 0), Vector2(3, 1)), Color(scol.r, scol.g, scol.b, a))
				draw_rect(Rect2(ssp.floor() - Vector2(0, 1), Vector2(1, 3)), Color(scol.r, scol.g, scol.b, a))
				if known and gz < 20000.0:
					_label(ssp + Vector2(0, -6), Galaxy.star_name(r) + (" · you are here" if r == here_sys else ""), scol)
				elif not known and gz < 6000.0:
					_label(ssp + Vector2(0, -6), "Unknown star", Color(0.55, 0.55, 0.65))
				continue
			# a charted system close in: its planets
			if gz < 2500.0:
				_label(ssp + Vector2(0, -16), "The %s system" % Galaxy.star_name(r), scol)
			for k in Defs.SYSTEM.size():
				var i := r * Defs.SYSTEM.size() + k
				var psp := to_screen(Defs.planet_g(i))
				var pl: Dictionary = Defs.make_planet(i)
				var rad := clampf((float(pl["radius"]) + Defs.ATMO) / gz, 2.5, 14.0)
				var tex: Texture2D = g.space.disc_texture(i)
				var dr := rad * 1.25
				draw_texture_rect(tex, Rect2(psp - Vector2(dr, dr), Vector2(dr, dr) * 2.0), false)
				var here: bool = i == int(g.planet.get("index", -1)) and not g.space.active
				var visited: bool = i == int(g.planet.get("index", -1)) or FileAccess.file_exists(g._world_path(i))
				var tc := Color(0.6, 1.0, 0.7) if here else (Color(0.9, 0.9, 1.0) if visited else Color(0.6, 0.62, 0.75))
				if here:
					draw_arc(psp, dr + 3.0, 0.0, TAU, 32, tc, 1.0)
				var walled: bool = i > g.skiff_reach() and i != int(g.planet.get("index", -1))
				if walled:
					var bc: Color = Defs.climate(pl)["belt"]
					for q2 in 16:
						var a0 := TAU * float(q2) / 16.0 + tt * 0.4
						draw_arc(psp, dr + 5.0, a0, a0 + TAU / 32.0, 4, Color(bc.r, bc.g, bc.b, 0.75), 1.0)
				if gz < 900.0:
					_label(psp + Vector2(0, dr + 9.0), String(pl["name"]), tc)
					_label(psp + Vector2(0, dr + 15.0), ("you are here" if here else String(pl.get("kind", "")) + ("" if visited else " · unexplored") + (" · storm belt: needs a Core Drive" if walled else "")), Color(tc.r, tc.g, tc.b, 0.7))
	# the waypoint, and a line to it from you
	var on := 0.75 + 0.25 * sin(tt * 6.0)
	var you := to_screen(g.space.player_g())
	var wp = g.space.waypoint
	if wp != null:
		var wsp := to_screen(wp)
		draw_dashed_line(you, wsp, Color(1.0, 0.82, 0.3, 0.45), 1.0, 3.0)
		var d: float = Defs.g_rel(wp, g.space.player_g()).length()
		if wsp.x < 0.0 or wsp.y < 0.0 or wsp.x > w or wsp.y > h:
			_edge_arrow(wsp, "Waypoint %s" % _dist(d), Color(1.0, 0.82, 0.3, on))
		else:
			draw_colored_polygon(PackedVector2Array([wsp + Vector2(0, -5), wsp + Vector2(4, 0), wsp + Vector2(0, 5), wsp + Vector2(-4, 0)]), Color(1.0, 0.82, 0.3, on))
			_label(wsp + Vector2(0, -8), "Waypoint · %s" % _dist(d), Color(1.0, 0.85, 0.45))
	# the skiff left out there, and you
	if g.space.active and g.skiff != null and g.player.aboard == null:
		_glyph_skiff(to_screen(g.space.galaxy_of(g.skiff.pos)), Color(0.7, 0.9, 1.0))
	if you.x < 0.0 or you.y < 0.0 or you.x > w or you.y > h:
		_edge_arrow(you, "You", Color(1, 1, 1, on))
	else:
		_dot(you, Color(1.0, 1.0, 1.0, on), "You")
	# a scale bar
	var units := [1000.0, 5000.0, 25000.0, 100000.0, 500000.0, 2000000.0, 10000000.0]
	var bar: float = units[0]
	for u in units:
		if u / gz < w * 0.22:
			bar = u
	var bl: float = bar / gz
	var by := h - 12.0
	draw_line(Vector2(10, by), Vector2(10 + bl, by), Color(0.85, 0.9, 1.0, 0.8), 1.0)
	draw_line(Vector2(10, by - 2), Vector2(10, by + 2), Color(0.85, 0.9, 1.0, 0.8), 1.0)
	draw_line(Vector2(10 + bl, by - 2), Vector2(10 + bl, by + 2), Color(0.85, 0.9, 1.0, 0.8), 1.0)
	_label(Vector2(10 + bl * 0.5, by - 4), _dist(bar), Color(0.85, 0.9, 1.0))

static func _dist(d: float) -> String:
	if d >= 1000000.0:
		return "%.1fM" % (d / 1000000.0)
	if d >= 1000.0:
		return "%.0fk" % (d / 1000.0)
	return "%.0f" % d
