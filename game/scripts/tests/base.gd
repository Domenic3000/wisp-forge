extends RefCounted
const Props := preload("res://scripts/props.gd")
const Build := preload("res://scripts/build.gd")
const FoeAI := preload("res://scripts/foe_ai.gd")
const Ecology := preload("res://scripts/ecology.gd")
const Skiff := preload("res://scripts/skiff.gd")
const Icons := preload("res://scripts/icons.gd")
const BossAI := preload("res://scripts/boss_ai.gd")
## Automated checks. "Run tests.bat" starts the game with --test: it builds a fresh planet in
## saves/test (your real saves are untouched), plays it for a while, checks that the important
## things still work, writes saves/test_report.txt and quits.

var g                       # the game (main.gd)
var lines := []
var passed := 0
var failed := 0
var start_pos := Vector2.ZERO  # where you arrived on the planet (the wild-life checks are set up near it, as
                               # when run alone: the full run's earlier checks leave you somewhere else each time)
var worst_us := 0           # the longest frame since this was last reset (a hitch shows here)
var _last_us := 0

var _cs_found := false            # (whether the last `_clear_stretch` found one)
var only_now := ""         # the one section being run alone ("" = the full run)
var guard_info := {}       # biome -> what the guardians' check saw (`_test_far_biomes` reads the ocean's)

## Shared state and helpers for the checks: reporting, waiting frames, positions, clear spots, pictures, benchmarks.

func _ok(name: String, cond: bool, detail := "") -> void:
	lines.append(("PASS  " if cond else "FAIL  ") + name + ("   [" + detail + "]" if detail != "" else ""))
	# (straight to the log as well, with the time: a run that runs out of time still shows how far
	# it got and how long each part took)
	print("[test %.0fs] " % (Time.get_ticks_msec() / 1000.0), lines[lines.size() - 1].left(400))
	if cond:
		passed += 1
	else:
		failed += 1

func _frames(n: int) -> void:
	for k in n:
		await g.get_tree().process_frame
		var now := Time.get_ticks_usec()
		if _last_us > 0:
			worst_us = maxi(worst_us, now - _last_us)
		_last_us = now

## a profiler section's recent peak, in ms ("lifting pieces out: 3.2")
func _peak(sec: String) -> String:
	var p = g.prof.get(sec)
	return "%s %.1f ms" % [sec, (p[3] / 1000.0) if p != null else 0.0]

## a cell's middle; with a structure's anchor (its x0, w) as its stamp put it, cell for cell
func _cell_pos(col: int, row: int, ax := -1, aw := 1) -> Vector2:
	if ax < 0:
		var a := (float(posmod(col, Defs.NS)) + 0.5) / Defs.NS * TAU
		return Vector2(cos(a), sin(a)) * (Defs.R_TOP - (float(row) + 0.5))
	return Defs.stamp_pos(row, ax, aw, Defs.k_of(col, ax))

## is surface column c within a lair (its arena, gate and backdrop, with a margin)?
func _near_lair(c: int) -> bool:
	for l in g.builds.lair_list:
		var lp: Vector2 = l["pos"]
		var lc := int(fposmod(atan2(lp.y, lp.x), TAU) / TAU * Defs.NS)
		var d := posmod(c - lc, Defs.NS)
		if mini(d, Defs.NS - d) < 420:
			return true
	return false

func _go(p: Vector2) -> void:
	# (a check that left you dead would leave every check after it running on the death screen: say so
	# in the log, and carry on alive)
	if g.state == "dead" or g.player.dead:
		print("[test] you were dead (health %.0f) on the way to the next check: carrying on alive" % g.hp)
		g.ui.hide_death()
		g.player.dead = false
		g.player.hp = g.player.max_hp
		g.state = "play"
	g.player.pos = p
	g.player.vx = 0.0
	g.player.vy = 0.0
	g.cam_c = p
	g.player.grid_g = p
	g.player.grid_a = atan2(p.y, p.x)

## a clear stretch (as `_clear_stretch`) whose ground is soft right through its top cells (dirt, sand,
## snow...: ecology.gd `soft`), so a burrower can live under it; the nearest found, else any clear one
func _soft_stretch(from: int, w: int, h: int, level := 3) -> Vector2i:
	# (hilly ground may have no stretch that level: then a little rougher, rather than wherever it fell)
	for lv in [level, level * 2, level * 3]:
		var at0 := from
		for k0 in 14:
			var st0 := _clear_stretch(at0, w, h, lv, 0, true)
			if not _cs_found:
				break
			if _soft_at(st0, w):
				return st0
			at0 = st0.x + w + 60
	var at := from
	for k in 14:
		var st := _clear_stretch(at, w, h, level)
		var soft_ok := true
		for c in [st.x + 4, st.x + w / 4, st.x + w / 2, st.x + 3 * w / 4, st.x + w - 4]:
			var gr: int = g.builds.ground_row(c)
			var rr: Dictionary = g.gpu.read_rect(c, gr, 1, 10)
			for v in rr["fg"]:
				if not Ecology.soft(int(v) & 255):
					soft_ok = false
					break
			if not soft_ok:
				break
		if soft_ok:
			return st
		at = st.x + w + 60
	return _clear_stretch(from, w, h, level)

## counts inside a structure's box: solid built blocks, loose (unsupported) blocks, treasure
## background plant cells (leaves, wood, cactus, coal from charred trees, snow on pines) in a
## 120-column window from 100 rows above the ground at the middle down to 10 below
func _plants(raw: PackedByteArray, toff: int, c0: int, gr: int) -> int:
	var N: int = Defs.NS
	var n := 0
	for j in range(maxi(0, gr - 112), gr + 10):
		for i in 120:
			var bm := raw.decode_u32(toff + Defs.raw_idx(j, posmod(c0 + i, N)) * 4) & 255
			if bm == Defs.LEAF or bm == Defs.WOOD or bm == Defs.CACTUS or bm == Defs.COAL or bm == Defs.SNOW \
					or bm == Defs.CAP or bm == Defs.STALK or bm == Defs.DRYGRASS:
				n += 1
	return n

## positions of powder cells (sand, gravel, snow, ash) in a 150-column window around the ground
func _powders(raw: PackedByteArray, c0: int, gr: int) -> Dictionary:
	var N: int = Defs.NS
	var out := {}
	for j in range(maxi(0, gr - 40), gr + 40):
		for i in 150:
			var col := posmod(c0 + i, N)
			var t := raw.decode_u32(Defs.raw_idx(j, col) * 4) & 255
			if Defs.KIND[t] == Defs.K_POWDER:
				out[j * N + col] = true
	return out

## the chest object standing at a planned chest spot (left column, floor row), or null
## a column near `from` (looking outward from it) where the ground is level across `w` columns (within
## `level` rows), outside any named structure, with nothing standing in the `h` rows over it (no log, wall,
## sand or water; trees are background and don't count) and, given `below`, solid ground that many rows
## under it: (first column, the highest ground row there)

## is the ground soft through its top cells at five points along a stretch?
func _soft_at(st: Vector2i, w: int) -> bool:
	for c in [st.x + 4, st.x + w / 4, st.x + w / 2, st.x + 3 * w / 4, st.x + w - 4]:
		var gr: int = g.builds.ground_row(c)
		var rr: Dictionary = g.gpu.read_rect(c, gr, 1, 10)
		for v in rr["fg"]:
			if not Ecology.soft(int(v) & 255):
				return false
	return true

## `trees`: no tree within that many columns either side (trees stand in the back layer, which the check for
## something standing doesn't see: digging the pit's test into a tree's roots felled it onto the mage)
func _clear_stretch(from: int, w: int, h: int, level := 3, below := 0, quiet := false, trees := 0) -> Vector2i:
	_cs_found = true
	var b = g.builds
	var why := {"level": 0, "label": 0, "wet": 0, "standing": 0, "hollow": 0, "trees": 0}
	for cs_d in range(0, 2400, 12):
		for cs_s in [1, -1]:
			var c0: int = from + cs_d * cs_s
			var gmin := 1 << 30
			var gmax := -(1 << 30)
			for c in range(c0, c0 + w):
				var gr: int = b.ground_row(c)
				gmin = mini(gmin, gr)
				gmax = maxi(gmax, gr)
			if gmax - gmin > level:
				why["level"] += 1
				continue
			if b.label_at(_cell_pos(c0 + w / 2, gmin - 5)) != "":
				why["label"] += 1
				continue
			if b.wet(c0 + w / 2):
				why["wet"] += 1
				continue
			var rr: Dictionary = g.gpu.read_rect(c0, gmin - h, w, h - 1)
			var clear := true
			for v in rr["fg"]:
				var kd: int = Defs.KIND[v & 255]
				if kd == Defs.K_SOLID or kd == Defs.K_POWDER or kd == Defs.K_LIQUID:
					clear = false
					break
			if not clear:
				why["standing"] += 1
				continue
			if trees > 0:
				var rt: Dictionary = g.gpu.read_rect(c0 - trees, gmin - h, w + trees * 2, h + 24)
				for v3 in rt["bg"]:
					var bm3: int = v3 & 255
					if bm3 == Defs.WOOD or bm3 == Defs.ROOT or bm3 == Defs.LEAF:
						clear = false
						break
				if not clear:
					why["trees"] += 1
					continue
			if below > 0:
				# (and solid ground under it, `below` rows down from its lowest point: no cave to break into)
				var rb: Dictionary = g.gpu.read_rect(c0, gmax + 1, w, below)
				for v2 in rb["fg"]:
					var kd2: int = Defs.KIND[v2 & 255]
					if kd2 != Defs.K_SOLID and kd2 != Defs.K_POWDER:
						clear = false
						break
				if not clear:
					why["hollow"] += 1
					continue
			return Vector2i(c0, gmin)
	_cs_found = false
	if not quiet:
		print("[clear] no clear stretch %d x %d (level %d) near column %d: %s" % [w, h, level, from, str(why)])
	return Vector2i(from, b.ground_row(from))

func _chest_obj(spot: Vector2i):
	if spot.x < 0:
		return null
	var want := _cell_pos(spot.x + Defs.CHEST_W / 2, spot.y - 5)
	for c in g.chests:
		if (c.pos as Vector2).distance_to(want) < 4.0:
			return c
	return null

func _scan(raw: PackedByteArray, info: Dictionary) -> Dictionary:
	# the structure's own built cells (recorded when it was generated): how many still hold a
	# solid, and which of them hang unsupported over open space
	var solid := 0
	var loose := 0
	var tre := 0
	var mats := {}
	var below := {}
	var at := []
	var allm := {}
	var bgn := 0
	var N: int = Defs.NS
	var boff: int = Defs.total_cells() * 4      # the background layer follows the cells
	var w: int = int(info["w"])
	for k in info.get("cells", PackedInt32Array()):
		var j: int = k / w
		var i: int = k % w
		var row: int = int(info["y0"]) + j
		if row < 0 or row >= Defs.ROWS:
			continue
		var col := posmod(int(info["x0"]) + i, N)
		var c := raw.decode_u32(Defs.raw_idx(row, col, int(info["ax"]), int(info["aw"])) * 4)
		var t := c & 255
		if Defs.KIND[t] != Defs.K_SOLID:
			continue
		solid += 1
		allm[Defs.NAMES[t]] = int(allm.get(Defs.NAMES[t], 0)) + 1
		# unsupported AND over open space (so it should have fallen); anchored cells are part
		# of the planet until you dig nearby
		var lf := (c >> 16) & 255
		if (c & 0x40000000) == 0 and ((c >> 24) & 63) > Defs.SPAN[t] and row + 1 < Defs.ROWS and not (lf > 0 and lf < 128):
			var cb := raw.decode_u32(Defs.raw_idx(row + 1, col, int(info["ax"]), int(info["aw"])) * 4)
			var tb := cb & 255
			var kb: int = Defs.KIND[tb]
			if tb == 0 or kb == Defs.K_GAS or kb == Defs.K_FIRE or kb == Defs.K_LIQUID:
				loose += 1
				if at.size() < 4:
					at.append(Vector2i(i, j))
				mats[Defs.NAMES[t]] = int(mats.get(Defs.NAMES[t], 0)) + 1
				var key := Defs.NAMES[tb] if tb > 0 else "air"
				below[key] = int(below.get(key, 0)) + 1
	for j in int(info["h"]):
		var row2: int = int(info["y0"]) + j
		if row2 < 0 or row2 >= Defs.ROWS:
			continue
		for i in w:
			var col2 := posmod(int(info["x0"]) + i, N)
			var t2 := raw.decode_u32(Defs.raw_idx(row2, col2, int(info["ax"]), int(info["aw"])) * 4) & 255
			var bgm := raw.decode_u32(boff + Defs.raw_idx(row2, col2, int(info["ax"]), int(info["aw"])) * 4) & 255
			if bgm != 0:
				bgn += 1
				var bk := "bg " + Defs.NAMES[bgm]
				allm[bk] = int(allm.get(bk, 0)) + 1
			if t2 == Defs.TREASURE or bgm == Defs.TREASURE:
				tre += 1
	return {"solid": solid, "loose": loose, "treasure": tre, "mats": mats, "below": below, "at": at, "all": allm, "bg": bgn}

## a picture of a blueprint as generated: built blocks in their colour, back walls darker, props in
## their palette colour, untouched cells grey, air sky blue (3 pixels per cell)
func _bp_image(info: Dictionary) -> Image:
	var w: int = info["w"]
	var h: int = info["h"]
	var dat: PackedInt32Array = info["data"]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		for i in w:
			var v: int = dat[j * w + i]
			var f: int = v & 255
			var gb: int = (v >> 8) & 255
			var col := Color(0.55, 0.55, 0.55)
			if f != 255 and f != 0:
				col = Defs.COLOR[f]
			elif gb == Defs.DECOR:
				col = Color.html(Props.PALETTE[((v >> 19) & 255) % Props.PALETTE.size()])
			elif gb != 255 and gb != 0:
				col = Defs.COLOR[gb].darkened(0.45)
			elif f == 0 or gb == 0:
				col = Color(0.45, 0.65, 0.95)
			img.set_pixel(i, j, col)
	img.resize(w * 3, h * 3, Image.INTERPOLATE_NEAREST)
	return img

## a cell's colour for the diagnostic pictures: the front material, else the back one darker, else
## air (sky blue) or untouched (grey); src tints by which blueprint wrote it
func _cell_col(f: int, gb: int, src: int) -> Color:
	var col := Color(0.55, 0.55, 0.55)
	if f != 255 and f != 0:
		col = Defs.COLOR[f]
	elif gb == Defs.DECOR:
		col = Color(0.9, 0.3, 0.9)
	elif gb != 255 and gb != 0:
		col = Defs.COLOR[gb].darkened(0.45)
	elif f == 0 or gb == 0:
		col = Color(0.45, 0.65, 0.95)
	if src >= 0:
		col = col.lerp(Color.from_hsv(fmod(float(src) * 0.37, 1.0), 0.9, 0.9), 0.25)
	return col

func _shot(fname: String) -> void:
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join(fname))

## choose a build piece by its name (its category and place in it)
func _pick_piece(pname: String) -> bool:
	var Bd = load("res://scripts/build.gd")
	if g.build_pieces.is_empty():
		g.build_pieces = Bd.pieces()
	for pc in g.build_pieces:
		if String(pc["name"]) == pname:
			var cat: int = pc["cat"]
			g.build_cat = cat
			while g.build_idx.size() <= cat:
				g.build_idx.append(0)
			g.build_idx[cat] = Bd.in_cat(g.build_pieces, cat).find(pc)
			return true
	return false

func _sha(d: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(d)
	return h.finish().hex_encode()

## The first frames after a planet is entered (user, 21 Nov: "a hitch on start up"): any frame over 40 ms is
## printed as `[<label>] frame N: T ms` with what took the time (the game's sections over 8 ms, the game's
## process, the drawing).
func _trace_frames(label: String, n: int, over_ms := 40.0, part_ms := 8.0) -> void:
	var tf_draw := {"pre": 0, "draw": 0}
	var tf_pre := func() -> void:
		tf_draw["pre"] = Time.get_ticks_usec()
	var tf_post := func() -> void:
		tf_draw["draw"] = Time.get_ticks_usec() - int(tf_draw["pre"])
	RenderingServer.frame_pre_draw.connect(tf_pre)
	RenderingServer.frame_post_draw.connect(tf_post)
	g.prof_reset()
	var tf_t0 := Time.get_ticks_usec()
	var tf_worst := 0
	var tf_big := 0
	for tf_k in n:
		await _frames(1)
		var tf_now := Time.get_ticks_usec()
		var tf_dt := tf_now - tf_t0
		tf_t0 = tf_now
		tf_worst = maxi(tf_worst, tf_dt)
		if tf_dt > int(over_ms * 1000.0):
			tf_big += 1
			var tf_secs := []
			for tf_s in g.prof:
				if float(g.prof[tf_s][3]) > part_ms * 1000.0:
					tf_secs.append("%s %.0f" % [tf_s, float(g.prof[tf_s][3]) / 1000.0])
			print("[%s] frame %d: %.0f ms (%s; process %.0f ms, drawing %.0f ms)" % [label, tf_k, tf_dt / 1000.0, ", ".join(tf_secs),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, float(tf_draw["draw"]) / 1000.0])
		g.prof_reset()
	RenderingServer.frame_pre_draw.disconnect(tf_pre)
	RenderingServer.frame_post_draw.disconnect(tf_post)
	print("[%s] %d frames: the slowest %.0f ms, %d over %.0f ms" % [label, n, tf_worst / 1000.0, tf_big, over_ms])

## A busy scene, uncapped (user, 21 Nov: the performance pass): two dozen foes hunting you, a fireball every
## 20 frames, digging all the while, sand poured from above, rain; where the frame's time goes.
## frames timed with vsync off: `each` is called before every frame with its number. Returns {avg, p95, worst
## (ms), gpu (the screen's drawing on the GPU, ms a frame), parts (the profiler's top parts), hist}.
func _bench_measure(n: int, each: Callable) -> Dictionary:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp: RID = g.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _frames(10)
	g.prof_reset()
	var times := []
	var gpu_draw := 0.0
	var gpu_sim := 0.0
	var eng_cpu := 0.0
	var t0 := Time.get_ticks_usec()
	var shown := 0
	var draw_us := {"pre": 0, "took": 0}
	var on_pre := func() -> void:
		draw_us["pre"] = Time.get_ticks_usec()
	var on_post := func() -> void:
		draw_us["took"] = Time.get_ticks_usec() - int(draw_us["pre"])
	RenderingServer.frame_pre_draw.connect(on_pre)
	RenderingServer.frame_post_draw.connect(on_post)
	for f in n:
		each.call(f)
		await _frames(1)
		var now := Time.get_ticks_usec()
		times.append(now - t0)
		if now - t0 > 25000 and shown < 8:
			# a slow frame: what took the time in it
			shown += 1
			var grew := []
			for sec in g.prof:
				if float(g.prof[sec][4]) > 1500.0:
					grew.append("%s %.1f" % [sec, float(g.prof[sec][4]) / 1000.0])
			print("[bench] slow frame %d: %.1f ms (%s; process %.1f ms, the engine's drawing %.1f ms)" % [f, (now - t0) / 1000.0, ", ".join(grew),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, float(draw_us["took"]) / 1000.0])
		t0 = now
		gpu_draw += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		eng_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		for gk in g.prof:
			if String(gk).begins_with("GPU ") and gk != "GPU submit" and gk != "GPU results":
				gpu_sim += float(g.prof[gk][4]) / 1000.0
	RenderingServer.frame_pre_draw.disconnect(on_pre)
	RenderingServer.frame_post_draw.disconnect(on_post)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	RenderingServer.viewport_set_measure_render_time(vp, false)
	times.sort()
	var sum := 0
	for v in times:
		sum += int(v)
	var hist := [0, 0, 0, 0]
	for v2 in times:
		var ms := float(v2) / 1000.0
		hist[0 if ms < 8.0 else (1 if ms < 16.7 else (2 if ms < 33.0 else 3))] += 1
	return {"avg": float(sum) / times.size() / 1000.0, "p95": float(times[int(times.size() * 0.95)]) / 1000.0, "worst": float(times[-1]) / 1000.0,
		"gpu": gpu_draw / float(n), "sim": gpu_sim / float(n), "eng": eng_cpu / float(n), "parts": g.prof_text(10, "; "), "hist": hist}

func _bench_line(label: String, r: Dictionary) -> String:
	return "%s: %.2f ms on average, 95%% under %.2f, the worst %.1f (the engine's drawing on the CPU %.2f; GPU: drawing %.2f, simulation %.2f a frame; frames <8 / 8-16.7 / 16.7-33 / >33 ms: %s); %s" % [label, r["avg"], r["p95"], r["worst"], r["eng"], r["gpu"], r["sim"], str(r["hist"]), r["parts"]]

## a column near the middle of the planet's longest stretch of a biome (-1 if it has none)
func _biome_mid_col(bio: String) -> int:
	var best_len := 0
	var best_mid := -1
	var run0 := -1
	var n: int = Defs.NS
	var stepc := 16
	for k in range(0, n + stepc, stepc):
		var c := k % n
		var here: bool = g.builds.biome(c) == bio and k < n
		if here and run0 < 0:
			run0 = k
		elif not here and run0 >= 0:
			if k - run0 > best_len:
				best_len = k - run0
				best_mid = (run0 + k) / 2
			run0 = -1
	return best_mid % n if best_mid >= 0 else -1

## paints (or cuts) from cell a to b of the ship as it was (`at` says where such a cell is now), a little at a
## time as you would by hand
func _hull_paint(sk, at: Callable, a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b) / 1.5) + 1
	for k in n + 1:
		var p := a.lerp(b, float(k) / float(n))
		var q: Vector2 = at.call(p.x, p.y)
		g.test_aim = sk.cell_world(int(floor(q.x)), int(floor(q.y)))
		g.test_cast = true
		await _frames(3)
	g.test_cast = false
	await _frames(2)

## Infinite space (galaxy.gd, space.gd; user, 22 Nov): the galaxy's maths (the spiral of systems, the
## first system where it always was), then out in the skiff: the Starsail runs it up to speed away from
## every planet, space's origin follows (`_shift`) so you stay near (0, 0) however far out, the sectors
## round you stream in with their asteroid fields; a rock mined in one is kept as it was when you leave
## and come back; a comet keeps to its loop; a nebula tints the view; the map charts it all and holds a
## waypoint; what you've charted is saved; and back home, space's origin is home again and you land.
## Pictures: galaxy_sail.png, galaxy_field.png, galaxy_comet.png, galaxy_nebula.png, galaxy_map.png,
## galaxy_map_far.png.
## Where a wreck can be drifted through: cells at least `r` from any of its cells (a disc that holds the
## mage however the wreck lies), flooded from its grid's edge. 1 = reached.
func _wreck_reach(wq, r: float) -> PackedByteArray:
	var ww: int = wq.w
	var hh: int = wq.h
	var dist := PackedFloat32Array()
	dist.resize(ww * hh)
	for k in ww * hh:
		dist[k] = 0.0 if wq.cells[k] != 0 else 1e6
	# (two passes of a chamfer distance: 1 across, 1.41 diagonally)
	for j in hh:
		for i in ww:
			var k := j * ww + i
			if i > 0: dist[k] = minf(dist[k], dist[k - 1] + 1.0)
			if j > 0: dist[k] = minf(dist[k], dist[k - ww] + 1.0)
			if i > 0 and j > 0: dist[k] = minf(dist[k], dist[k - ww - 1] + 1.41)
			if i < ww - 1 and j > 0: dist[k] = minf(dist[k], dist[k - ww + 1] + 1.41)
	for j in range(hh - 1, -1, -1):
		for i in range(ww - 1, -1, -1):
			var k := j * ww + i
			if i < ww - 1: dist[k] = minf(dist[k], dist[k + 1] + 1.0)
			if j < hh - 1: dist[k] = minf(dist[k], dist[k + ww] + 1.0)
			if i < ww - 1 and j < hh - 1: dist[k] = minf(dist[k], dist[k + ww + 1] + 1.41)
			if i > 0 and j < hh - 1: dist[k] = minf(dist[k], dist[k + ww - 1] + 1.41)
	var got := PackedByteArray()
	got.resize(ww * hh)
	var q := PackedInt32Array()
	for k in ww * hh:
		var bi := k % ww
		var bj := k / ww
		if (bi == 0 or bj == 0 or bi == ww - 1 or bj == hh - 1) and dist[k] >= r:
			got[k] = 1
			q.append(k)
	while not q.is_empty():
		var c: int = q[q.size() - 1]
		q.resize(q.size() - 1)
		for d in [1, -1, ww, -ww]:
			var nk: int = c + int(d)
			if nk < 0 or nk >= ww * hh or (absi(int(d)) == 1 and nk / ww != c / ww):
				continue
			if got[nk] == 0 and dist[nk] >= r:
				got[nk] = 1
				q.append(nk)
	return got

## can you drift up to a wreck's cache? (a reached cell within 15 of its middle: it opens within 18)
func _cache_reached(wq, c: Dictionary, got: PackedByteArray) -> bool:
	var cm := Vector2(float(c["i"]) + float(c["w"]) * 0.5, float(c["j"]) + float(c["h"]) * 0.5)
	for j in range(int(cm.y) - 16, int(cm.y) + 17):
		for i in range(int(cm.x) - 16, int(cm.x) + 17):
			if i >= 0 and j >= 0 and i < wq.w and j < wq.h and got[j * wq.w + i] == 1 and Vector2(i + 0.5, j + 0.5).distance_to(cm) <= 15.0:
				return true
	return false

## a body point of a wreck, in the open over a cache (where you float to open it)
func _over_cache(wq, c: Dictionary) -> Vector2:
	return wq.to_world(Vector2(float(c["i"]) + float(c["w"]) * 0.5, float(c["j"]) - 9.0) - wq.com)

## is the mage's box in a body's cells?
func _in_cells(a, p: Vector2) -> bool:
	var ua: float = (p - g.space.centre).angle()
	var rr: Vector2 = g.basis_r(ua)
	var dd: Vector2 = g.basis_d(ua)
	for q in g.space.box_pts(g.player, 1.0):
		if a.solid_at(p + rr * q.x + dd * q.y):
			return true
	return false

## a spot in an alien's room, on the side of the room away from it (on its floor if it has power)
func _st_spot(st, al) -> Vector2:
	var rk: int = st.module_at(al.b)
	if rk < 0:
		rk = al.home
	var rm: Vector2 = st.room_mid(rk)
	var side := -1.0 if al.b.x > rm.x else 1.0
	var md: Dictionary = st.mods[rk]
	var y: float = float(int(md["y1"])) - 9.5 if md["powered"] else rm.y
	return Vector2(rm.x + side * 28.0, y)

## puts the mage at a point of a station (its cells), still
func _st_put(st, b: Vector2) -> void:
	g.player.pos = st.to_world(b - st.com)
	g.space.vel = Vector2.ZERO

## which of a station's rooms a body the mage's size can drift to from outside (hatches' one-way floors
## open, as they are with no gravity)
func _station_rooms_reached(st) -> Array:
	if st.lv:
		return _level_rooms_reached(st)
	var saved: PackedByteArray = st.cells.duplicate()
	for k in st.cells.size():
		if st.cells[k] == Defs.SCAFFOLD:
			st.cells[k] = 0
	var got := _wreck_reach(st, 8.0)
	st.cells = saved
	var out := []
	for md in st.mods:
		var hit := false
		for j in range(int(md["y0"]) + 8, int(md["y1"]) - 8, 3):
			for i in range(int(md["x0"]) + 8, int(md["x1"]) - 8, 3):
				if got[j * st.w + i] == 1:
					hit = true
					break
			if hit:
				break
		out.append(hit)
	return out

## (a level, 27 Nov: four or five times the old halls' cells, too many to flood cell by cell) which rooms you can get
## to from its bay, room by room through its doors (each opened): a door that's sealed stops you, and so does one whose
## way through isn't clear for a body the mage's size, in its doorway and a step either side of it
func _level_rooms_reached(st) -> Array:
	var got := []
	got.resize(st.mods.size())
	got.fill(false)
	st.open_all_doors()
	got[st.dock] = true
	var q := [st.dock]
	while not q.is_empty():
		var k: int = q.pop_back()
		for dr in st.doors:
			if dr["sealed"] or (int(dr["a"]) != k and int(dr["b"]) != k):
				continue
			var o: int = int(dr["b"]) if int(dr["a"]) == k else int(dr["a"])
			if got[o]:
				continue
			var cx: float = float(int(dr["x"])) + float(st.BW) * 0.5
			var cy: float = float(int(dr["y1"])) - 9.0
			var clear: bool = st.box_free(Vector2(cx, cy), 3.5, 8.5) and st.box_free(Vector2(cx - 12.0, cy), 3.5, 8.5) and st.box_free(Vector2(cx + 12.0, cy), 3.5, 8.5)
			if clear:
				got[o] = true
				q.append(o)
	return got

## a picture of a grown station (back layer under its cells), twice size
func _station_picture(st, file: String) -> void:
	var img: Image = st.back_texture().get_image().duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var front: Image = st.texture().get_image()
	front.convert(Image.FORMAT_RGBA8)
	var bgc := Image.create(st.w, st.h, false, Image.FORMAT_RGBA8)
	bgc.fill(Color(0.02, 0.02, 0.05))
	bgc.blend_rect(img, Rect2i(0, 0, st.w, st.h), Vector2i.ZERO)
	bgc.blend_rect(front, Rect2i(0, 0, st.w, st.h), Vector2i.ZERO)
	for sp in st.spawns:
		var p: Vector2 = sp["b"]
		var col := Color(0.6, 1.0, 0.4) if sp["kind"] != "brood" else Color(1.0, 0.3, 0.6)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < st.w and y < st.h:
					bgc.set_pixel(x, y, col)
	bgc.resize(st.w * 2, st.h * 2, Image.INTERPOLATE_NEAREST)
	bgc.save_png(g._real_save_dir().path_join("shots").path_join(file))

## wait n frames noting every hurt: when, how much, and what was about (the hazard, fire or lava near, foes)
func _hz_watch(n: int, phase: String, why: Array) -> void:
	var hp: float = g.player.hp
	for k in n:
		await _frames(1)
		var d: float = hp - g.player.hp
		hp = g.player.hp
		if d > 0.3 and why.size() < 40:
			var hot := 0
			var l: Vector2 = g.to_grid(g.player.pos)
			for y in range(int(l.y) - 10, int(l.y) + 11):
				for x in range(int(l.x) - 10, int(l.x) + 11):
					var t: int = g.gtype(x, y)
					if t == Defs.FIRE or t == Defs.LAVA:
						hot += 1
			var foes := 0
			for e in g.enemies:
				if not e.dead and (e.pos as Vector2).distance_to(g.player.pos) < 40.0:
					foes += 1
			why.append("%s f%d -%.1f (hazard '%s', fire/lava %d, foes %d, liquid %s, breath %.0f, warm %s)" % [phase, k, d, g.hazard, hot, foes, g.player.in_liquid, g.player.breath, g._warm])
