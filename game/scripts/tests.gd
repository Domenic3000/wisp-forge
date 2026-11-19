extends RefCounted
const Props := preload("res://scripts/props.gd")
const Build := preload("res://scripts/build.gd")
const FoeAI := preload("res://scripts/foe_ai.gd")
## Automated checks. "Run tests.bat" starts the game with --test: it builds a fresh planet in
## saves/test (your real saves are untouched), plays it for a while, checks that the important
## things still work, writes saves/test_report.txt and quits.

var g                       # the game (main.gd)
var lines := []
var passed := 0
var failed := 0
var worst_us := 0           # the longest frame since this was last reset (a hitch shows here)
var _last_us := 0

func _ok(name: String, cond: bool, detail := "") -> void:
	lines.append(("PASS  " if cond else "FAIL  ") + name + ("   [" + detail + "]" if detail != "" else ""))
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

func _cell_pos(col: int, row: int) -> Vector2:
	var a := (float(posmod(col, Defs.NS)) + 0.5) / Defs.NS * TAU
	var r := Defs.R_TOP - (float(row) + 0.5)
	return Vector2(cos(a), sin(a)) * r

func _go(p: Vector2) -> void:
	g.player.pos = p
	g.player.vx = 0.0
	g.player.vy = 0.0
	g.cam_c = p
	g.player.grid_g = p
	g.player.grid_a = atan2(p.y, p.x)

## counts inside a structure's box: solid built blocks, loose (unsupported) blocks, treasure
## background plant cells (leaves, wood, cactus, coal from charred trees, snow on pines) in a
## 120-column window from 100 rows above the ground at the middle down to 10 below
func _plants(raw: PackedByteArray, toff: int, c0: int, gr: int) -> int:
	var N: int = Defs.NS
	var n := 0
	for j in range(maxi(0, gr - 112), gr + 10):
		for i in 120:
			var bm := raw.decode_u32(toff + (j * N + posmod(c0 + i, N)) * 4) & 255
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
			var t := raw.decode_u32((j * N + col) * 4) & 255
			if Defs.KIND[t] == Defs.K_POWDER:
				out[j * N + col] = true
	return out

## the chest object standing at a planned chest spot (left column, floor row), or null
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
		if row < 0 or row >= Defs.SH_Y0[1]:
			continue
		var col := posmod(int(info["x0"]) + i, N)
		var c := raw.decode_u32((row * N + col) * 4)
		var t := c & 255
		if Defs.KIND[t] != Defs.K_SOLID:
			continue
		solid += 1
		allm[Defs.NAMES[t]] = int(allm.get(Defs.NAMES[t], 0)) + 1
		# unsupported AND over open space (so it should have fallen); anchored cells are part
		# of the planet until you dig nearby
		var lf := (c >> 16) & 255
		if (c & 0x40000000) == 0 and ((c >> 24) & 63) > Defs.SPAN[t] and row + 1 < Defs.SH_Y0[1] and not (lf > 0 and lf < 128):
			var cb := raw.decode_u32(((row + 1) * N + col) * 4)
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
		if row2 < 0 or row2 >= Defs.SH_Y0[1]:
			continue
		for i in w:
			var col2 := posmod(int(info["x0"]) + i, N)
			var t2 := raw.decode_u32((row2 * N + col2) * 4) & 255
			var bgm := raw.decode_u32(boff + (row2 * N + col2) * 4) & 255
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

func run() -> void:
	var t_all := Time.get_ticks_msec()
	lines.append("Wisp Forge test report  %s" % Time.get_datetime_string_from_system())
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("")
	g.test_god = true

	# ---- a picture of the animated title screen (saves/shots/title.png) ----
	var tdir: String = g._real_save_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(tdir)
	g.ui.show_title(true)
	await _frames(150)
	g.get_viewport().get_texture().get_image().save_png(tdir.path_join("title.png"))
	_ok("title screen draws, with a button per save slot", g.ui.title.visible and g.ui.title.slot_btns.size() == g.SLOTS, "%d slot buttons" % g.ui.title.slot_btns.size())

	# ---- a fresh planet ----
	g._delete_worlds()
	g.player.inv.fill(0)
	g.known = ["spark", "conjure"]
	var t0 := Time.get_ticks_msec()
	g._enter_planet(0)
	var gen_ms := Time.get_ticks_msec() - t0
	g.ui.show_hud()
	g.state = "play"
	var b = g.builds
	_ok("planet generates", g.planet.size() > 0, "%d ms including structures and settling" % gen_ms)
	_ok("structures are placed", b.infos.size() >= 15, "%d structures, %d labels" % [b.infos.size(), b.labels.size()])
	_ok("guards are planned", b.guards.size() >= 5, "%d guards" % b.guards.size())
	var nchest := 0
	for info in b.infos:
		nchest += info["chests"].size()
	_ok("chests are placed", nchest >= 10, "%d chests" % nchest)
	await _frames(10)

	# ---- diagnostics: the blueprints of the most furnished buildings, and how they look straight
	# after generating (saves/shots/bp_N.png, early_N.png) ----
	var by_decor := []
	for info in b.infos:
		if not info["ruined"] and int(info.get("decor", 0)) > 0 and info.get("data", PackedInt32Array()).size() > 0:
			by_decor.append(info)
	by_decor.sort_custom(func(p, q): return int(p["decor"]) > int(q["decor"]))
	var sdir: String = g._real_save_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(sdir)
	for bn in mini(3, by_decor.size()):
		var bi: Dictionary = by_decor[bn]
		_bp_image(bi).save_png(sdir.path_join("bp_%d.png" % bn))
		var ecx := int(bi["x0"]) + int(bi["w"]) / 2
		var epos := _cell_pos(ecx, b.ground_row(ecx) - 30)
		_go(epos)
		g.ui.title.visible = false
		g.time = fposmod(atan2(epos.y, epos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(sdir.path_join("early_%d.png" % bn))

	# the first village: every blueprint over it combined in stamping order (vill_bp.png), and the
	# world's cells there right after generating (vill_world.png)
	for lab0 in b.labels:
		if "Village" in str(lab0["name"]):
			var vx0 := int(lab0["x0"])
			var vw := int(lab0["w"])
			var vg: int = b.ground_row(vx0 + vw / 2)
			var vy0: int = vg - 140
			var vh := 160
			var comp := PackedInt32Array()
			comp.resize(vw * vh)
			comp.fill(0xffff)
			var src := PackedInt32Array()
			src.resize(vw * vh)
			src.fill(-1)
			for si in b.infos.size():
				var inf: Dictionary = b.infos[si]
				var dat2: PackedInt32Array = inf.get("data", PackedInt32Array())
				if dat2.is_empty():
					continue
				var iw: int = inf["w"]
				for jj in int(inf["h"]):
					var yy: int = int(inf["y0"]) + jj - vy0
					if yy < 0 or yy >= vh:
						continue
					for ii in iw:
						var xx := posmod(int(inf["x0"]) + ii - vx0, Defs.NS)
						if xx >= vw:
							continue
						var v2: int = dat2[jj * iw + ii]
						var k3 := yy * vw + xx
						if (v2 & 255) != 255:
							comp[k3] = (comp[k3] & ~255) | (v2 & 255)
							src[k3] = si
						if ((v2 >> 8) & 255) != 255:
							comp[k3] = (comp[k3] & ~0xff00) | (v2 & 0xff00)
			var cimg := Image.create(vw, vh, false, Image.FORMAT_RGB8)
			var wimg := Image.create(vw, vh, false, Image.FORMAT_RGB8)
			var rawv: PackedByteArray = g.gpu.read_world()
			var boffv2: int = Defs.total_cells() * 4
			for yy2 in vh:
				for xx2 in vw:
					var cv: int = comp[yy2 * vw + xx2]
					cimg.set_pixel(xx2, yy2, _cell_col(cv & 255, (cv >> 8) & 255, src[yy2 * vw + xx2]))
					var row3: int = vy0 + yy2
					var col3 := posmod(vx0 + xx2, Defs.NS)
					if row3 < 0 or row3 >= Defs.SH_Y0[1]:
						continue
					var kw: int = (row3 * int(Defs.NS) + col3) * 4
					wimg.set_pixel(xx2, yy2, _cell_col(rawv.decode_u32(kw) & 255, rawv.decode_u32(boffv2 + kw) & 255, -1))
			cimg.resize(vw * 2, vh * 2, Image.INTERPOLATE_NEAREST)
			wimg.resize(vw * 2, vh * 2, Image.INTERPOLATE_NEAREST)
			cimg.save_png(sdir.path_join("vill_bp.png"))
			wimg.save_png(sdir.path_join("vill_world.png"))
			break

	# ---- buildings stand and ruins have settled ----
	var raw: PackedByteArray = g.gpu.read_world()
	var intact := 0
	var worst_built := ""
	var intact_ok := 0
	var worst := 1.0
	var loose_total := 0
	var treasure_missing := 0
	var loose_where := []
	var loose_mats := {}
	var loose_below := {}
	for info in b.infos:
		var sc := _scan(raw, info)
		loose_total += int(sc["loose"])
		if int(sc["loose"]) > 0:
			var a0: Vector2i = sc["at"][0]
			var nm: String = b.label_at(_cell_pos(int(info["x0"]) + a0.x, int(info["y0"]) + a0.y))
			loose_where.append("%d in a %s structure %dx%d (%s) at local %s" % [sc["loose"], "ruined" if info["ruined"] else "intact", info["w"], info["h"], nm, str(sc["at"])])
			for k in sc["mats"]:
				loose_mats[k] = int(loose_mats.get(k, 0)) + int(sc["mats"][k])
			for k in sc["below"]:
				loose_below[k] = int(loose_below.get(k, 0)) + int(sc["below"][k])
		if int(info["solid"]) > 0:
			intact += 1
			var ratio := float(sc["solid"]) / float(info["solid"])
			if ratio < worst:
				worst_built = "%s %s %dx%d: %d of %d built cells left, now %s" % ["ruined" if info["ruined"] else "intact", b.label_at(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) + int(info["h"]) - 3)), info["w"], info["h"], sc["solid"], info["solid"], str(sc["all"])]
			worst = minf(worst, ratio)
			if ratio >= 0.97:
				intact_ok += 1

	_ok("every structure (ruins too) stands as built after generating", intact_ok == intact, "%d of %d keep at least 97%% of their blocks, worst %.1f%%" % [intact_ok, intact, worst * 100.0])
	if intact_ok != intact:
		lines.append("      worst: " + worst_built)
	_ok("every planned chest is in the world", g.chests.size() == b.chest_list.size() and g.chests.size() > 0, "%d chests, %d planned" % [g.chests.size(), b.chest_list.size()])
	_ok("nothing is left hanging after settling", loose_total == 0, "%d unsupported blocks over open space" % loose_total)
	if loose_total > 0:
		lines.append("      where: " + "; ".join(loose_where))
		lines.append("      materials: " + str(loose_mats))
		lines.append("      resting on: " + str(loose_below))

	# ---- structures stay put when you walk up to them (ruins used to fall apart on arrival) ----
	var visits := []
	for info in b.infos:
		if info["ruined"] and visits.size() < 12:
			visits.append(info)
	for info in b.infos:
		if not info["ruined"] and visits.size() < 15:
			visits.append(info)
	var worst_v := 1.0
	var worst_txt := ""
	for info in visits:
		var raw_v0: PackedByteArray = g.gpu.read_world()
		var sc0 := _scan(raw_v0, info)
		_go(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) - 6))
		await _frames(200)
		var sc1 := _scan(g.gpu.read_world(), info)
		var n0 := int(sc0["solid"]) + int(sc0["bg"])
		var n1 := int(sc1["solid"]) + int(sc1["bg"])
		var ratio := float(n1) / float(n0) if n0 > 0 else 1.0
		if ratio < worst_v:
			worst_v = ratio
			var lost := []
			for k in sc0["all"]:
				var dn := int(sc0["all"][k]) - int(sc1["all"].get(k, 0))
				if dn > 3:
					lost.append("%s -%d" % [k, dn])
			# where the lost tree stood: its lowest wood cell that is gone now, and what was under it
			var raw_v1: PackedByteArray = g.gpu.read_world()
			var boffv: int = Defs.total_cells() * 4
			var Nv: int = Defs.NS
			var low := ""
			var lowrow := -1
			for jj in int(info["h"]):
				var rowv: int = int(info["y0"]) + jj
				if rowv < 0 or rowv >= Defs.SH_Y0[1]:
					continue
				for ii in int(info["w"]):
					var colv := posmod(int(info["x0"]) + ii, Nv)
					var kv := (rowv * Nv + colv) * 4
					var a0 := raw_v0.decode_u32(boffv + kv)
					if (a0 & 255) == Defs.WOOD and (raw_v1.decode_u32(boffv + kv) & 255) == 0 and rowv > lowrow:
						lowrow = rowv
						var colm := []
						for dr in range(-1, 10):
							colm.append(str(raw_v0.decode_u32(((rowv + dr) * Nv + colv) * 4) & 255))
						var nsites := []
						for st2 in b.sites:
							if absf(float(colv) - st2.x) < 300 or absf(float(colv) - st2.y) < 300:
								nsites.append("%d-%d" % [int(st2.x), int(st2.y)])
						low = "lowest lost wood at column +%d (abs %d) row +%d (ground row +%d), id %x, S%d, fg column from just above: %s, box x0 %d, sites %s" % [ii, colv, jj, b.ground_row(colv) - int(info["y0"]), a0 >> 16, (a0 >> 8) & 63, "/".join(colm), int(info["x0"]), ",".join(nsites)]
			worst_txt = low + "; %s %s %dx%d lost %s" % ["ruined" if info["ruined"] else "intact", b.label_at(_cell_pos(int(info["x0"]) + 2, int(info["y0"]) + int(info["h"]) - 4)), info["w"], info["h"], ", ".join(lost)]
	_ok("structures stay put when you arrive", worst_v >= 0.97, "%d visited, worst keeps %.1f%%" % [visits.size(), worst_v * 100.0])
	if worst_v < 0.97:
		lines.append("      " + worst_txt)

	# ---- pictures of a few ruins and buildings, for looking at the art (saves/shots/) ----
	var shot_dir: String = g._real_save_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var nshot := 0
	var kinds_shot := {}
	for info in b.infos:
		if nshot >= 6:
			break
		var key: String = ("ruin " if info["ruined"] else "intact ") + str(int(info["w"]) / 20)
		if kinds_shot.has(key):
			continue
		kinds_shot[key] = true
		var cx := int(info["x0"]) + int(info["w"]) / 2
		var spos := _cell_pos(cx, b.ground_row(cx) - 30)
		_go(spos)
		# midday over it, and nothing drawn on top
		g.ui.title.visible = false
		g.time = fposmod(atan2(spos.y, spos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0   # DAY_LEN
		await _frames(45)
		var img: Image = g.get_viewport().get_texture().get_image()
		img.save_png(shot_dir.path_join("shot_%d_%s.png" % [nshot, ("ruin" if info["ruined"] else "intact")]))
		nshot += 1
	# the Forge panel, for looking at the UI
	g.ui.show_forge()
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(shot_dir.path_join("forge.png"))
	g.ui.hide_forge()
	g.ui.settings_panel.visible = true
	g.ui._refresh_settings()
	await _frames(10)
	g.get_viewport().get_texture().get_image().save_png(shot_dir.path_join("settings.png"))
	g.ui.settings_panel.visible = false

	# ---- you can walk in through a cottage door (no lip, nothing in the way) ----
	var walked := "no intact cottage found"
	var walk_ok := false
	var door_t := {}
	for info in b.infos:
		if info["ruined"]:
			continue
		var nm2: String = b.label_at(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) + int(info["h"]) - 45))
		if not ("Cottage" in nm2 or "Dwelling" in nm2):
			continue
		var ox := 14                                  # YARD + 2
		var base_row := int(info["y0"]) + int(info["h"]) - 40
		var start_col := int(info["x0"]) + ox - 8
		_go(_cell_pos(start_col, base_row - 12))
		await _frames(30)
		door_t = g._door_near(_cell_pos(int(info["x0"]) + ox + 1, base_row - 15), 30.0)
		g.test_move = -1     # on screen, left is toward higher columns (where the house is)
		await _frames(150)
		g.test_move = 0
		var a_now: float = fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU)
		var col_now := int(a_now / TAU * Defs.NS)
		# it must get through the doorway: past the wall into (or through) the house
		var moved := posmod(col_now - start_col, Defs.NS)
		walk_ok = moved > 16 and moved < Defs.NS / 2
		walked = "%s: walked from column %d to %d (the inside starts at %d)" % [nm2, start_col, col_now, int(info["x0"]) + ox + 6]
		break
	_ok("you can walk into a cottage through its door", walk_ok, walked)

	# ---- doors: walking into one opens it; F (here: _set_door) closes it again ----
	if door_t.is_empty():
		_ok("a door opens when you walk into it, and closes again", false, "no door at that cottage")
	else:
		var was_open: bool = door_t["open"]
		var dp: Vector2 = door_t["pos"]
		var dang := atan2(dp.y, dp.x)
		# (the cottage's guards and any foe wandering by are cleared away first: a foe standing in the
		# doorway rightly keeps it from shutting, and a skeleton walking into it opens it again)
		for fe in g.enemies.duplicate():
			if fe.pos.distance_to(dp) < 300.0:
				g._kill_enemy(fe)
		var foe_near := func() -> String:
			var nf_best := "none"
			var nf_bd := 1e9
			for fe2 in g.enemies:
				if fe2.dead:
					continue
				var dd2: float = fe2.pos.distance_to(dp)
				if dd2 < nf_bd:
					nf_bd = dd2
					nf_best = "%s %.0f cells off" % [fe2.type, dd2]
			return nf_best
		# stand inside, clear of the doorway, and look at the open door (saves/shots/door.png)
		var inside: Vector2 = -g.basis_r(dang) * float(door_t["side"])
		_go(dp + inside * 14.0 - dp.normalized() * 5.0)
		g.time = fposmod(dang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("door.png"))
		g._set_door(door_t, false)
		await _frames(20)
		var rawd: PackedByteArray = g.gpu.read_world()
		var nd2 := 0
		for jd in int(door_t["h"]):
			for id2 in int(door_t["w"]):
				var kd: int = ((int(door_t["row"]) + jd) * int(Defs.NS) + posmod(int(door_t["col"]) + id2, Defs.NS)) * 4
				if (rawd.decode_u32(kd) & 255) == Defs.WOODDOOR:
					nd2 += 1
		var want: int = int(door_t["w"]) * int(door_t["h"])
		_ok("a door opens when you walk into it, and closes again", was_open and not bool(door_t["open"]) and nd2 == want,
			"opened by walking: %s, closed again: %d of %d door cells (still open: %s; nearest foe: %s)" % [was_open, nd2, want, door_t["open"], foe_near.call()])
		# a door shot through keeps its hole: open it and shut it again, the hole is still there
		var count_door := func() -> int:
			var rr: Dictionary = g.gpu.read_rect(int(door_t["col"]), int(door_t["row"]), int(door_t["w"]), int(door_t["h"]))
			var nn := 0
			for v in rr["fg"]:
				if (v & 255) == Defs.WOODDOOR:
					nn += 1
			return nn
		var dmid: Vector2 = _cell_pos(int(door_t["col"]) + int(door_t["w"]) / 2, int(door_t["row"]) + int(door_t["h"]) / 3)
		g.brushes.append([dmid, 4.5, 1, 0, 9, 0, 0, 3])
		g.brushes.append([dmid + dp.normalized() * -9.0, 3.5, 1, 0, 9, 0, 0, 3])
		await _frames(6)
		var n_shot: int = count_door.call()
		g._set_door(door_t, true, g.player.pos)
		await _frames(10)
		var gone_open := 0
		for v in door_t.get("cells", []):
			if int(v) < 0:
				gone_open += 1
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("door_damaged.png"))
		g._set_door(door_t, false)
		await _frames(10)
		var n_shut: int = count_door.call()
		_ok("a damaged door keeps its damage when opened and shut", n_shot < want and n_shot > want / 2 and gone_open == want - n_shot and n_shut == n_shot and g.doors.has(door_t),
			"%d of %d cells left after the shot; open: %d parts missing from its panel; shut again: %d cells (still open: %s; nearest foe: %s)" % [n_shot, want, gone_open, n_shut, door_t["open"], foe_near.call()])
		# fire reaching an open door's panel burns it where it reaches
		g._set_door(door_t, true, g.player.pos)
		await _frames(5)
		var left0: int = g._door_left(door_t)
		var panel: Vector2 = g.door_panel_pos(door_t)
		for fk in 6:
			g.brushes.append([panel, 3.0, 3, Defs.FIRE, 0, 0, 0])
			await _frames(2)
		await _frames(20)
		var left1: int = g._door_left(door_t) if g.doors.has(door_t) else 0
		_ok("fire burns an open door where its panel is", left1 < left0, "%d parts before the fire, %d after%s" % [left0, left1, "" if g.doors.has(door_t) else " (the door is gone)"])

	# ---- digging next to a ruin takes only what you dig: the rest stands ----
	var dug_ok := true
	var dug_lines := []
	var nr := 0
	for info in b.infos:
		if not info["ruined"] or nr >= 3:
			continue
		var cells2: PackedInt32Array = info["cells"]
		if cells2.size() < 40:
			continue
		nr += 1
		var sc0b := _scan(g.gpu.read_world(), info)
		var kmid: int = cells2[cells2.size() / 2]
		var wi: int = int(info["w"])
		var dpos := _cell_pos(int(info["x0"]) + kmid % wi, int(info["y0"]) + kmid / wi)
		_go(dpos + dpos.normalized() * 30.0)
		await _frames(20)
		for f in 10:
			g.brushes.append([dpos, 3.0, 1, 0, 4, 0, 0, 3])
			await _frames(1)
		await _frames(240)
		var sc1b := _scan(g.gpu.read_world(), info)
		var lost := int(sc0b["solid"]) - int(sc1b["solid"])
		dug_lines.append("%d -> %d" % [sc0b["solid"], sc1b["solid"]])
		# the hole itself is ~30 cells; allow what that brings down nearby, not the building
		if lost > 60 + int(sc0b["solid"]) / 20:
			dug_ok = false
	_ok("digging next to a ruin doesn't bring it down", dug_ok and nr > 0, "built cells before -> after: " + ", ".join(dug_lines))

	# ---- open a chest ----
	var chest := Vector2i(-1, -1)
	for info in b.infos:
		if not info["ruined"] and info["chests"].size() > 0:
			chest = info["chests"][0]
			break
	var cobj = _chest_obj(chest)
	if cobj != null:
		_go(_cell_pos(chest.x - 6, chest.y - 10))
		await _frames(40)
		var before := 0
		for m in Defs.NM:
			before += g.player.inv[m]
		g._try_open_chest()
		await _frames(45)
		var after := 0
		for m in Defs.NM:
			after += g.player.inv[m]
		_ok("F opens a chest and gives loot", cobj.opened and after > before, "opened %s, satchel %d -> %d" % [cobj.opened, before, after])
		var shown: bool = g.chests.has(cobj)
		await _frames(90)
		_ok("an opened chest shows its inside, then vanishes", shown and not g.chests.has(cobj), "")

		# right-click leaves a building's back wall alone; Shift + right-click (deconstruct) takes it
		var raw2: PackedByteArray = g.gpu.read_world()
		var boff: int = Defs.total_cells() * 4
		var wall := Vector2i(-1, -1)
		for dj in range(12, 26):
			for di in range(-8, 20):
				var col2 := posmod(chest.x + di, Defs.NS)
				var row2 := chest.y - dj
				var k2 := (row2 * Defs.NS + col2) * 4
				if (raw2.decode_u32(k2) & 255) == 0 and (raw2.decode_u32(boff + k2) & 0x4000) != 0:
					wall = Vector2i(col2, row2)
					break
			if wall.x >= 0:
				break
		if wall.x >= 0:
			var wp := _cell_pos(wall.x, wall.y)
			for f in 20:
				g.brushes.append([wp, 2.5, 1, 0, 4, 0, 0, 0])
				await _frames(1)
			var r3: PackedByteArray = g.gpu.read_world()
			var kk := (wall.y * Defs.NS + wall.x) * 4
			var still_wall := (r3.decode_u32(boff + kk) & 0x4000) != 0
			for f in 30:
				g.brushes.append([wp, 2.5, 8, 0, 4, 0, 0, 0])
				await _frames(1)
			var r4: PackedByteArray = g.gpu.read_world()
			var gone := (r4.decode_u32(boff + kk) & 255) == 0
			_ok("right-click leaves a building's back wall alone", still_wall, "")
			_ok("Shift + right-click deconstructs it", gone, "")
		else:
			_ok("right-click leaves a building's back wall alone", false, "no back wall found near the chest")
	else:
		_ok("F opens a chest and gives loot", false, "no intact chest found")

	# ---- a chest lying on the ground stays still while you walk about (it used to jiggle) ----
	var still_c = null
	for ch in g.chests:
		if not ch.opened:
			still_c = ch
			break
	if still_c == null:
		_ok("a chest stays still while you walk about", false, "no closed chest")
	else:
		var ca0 := atan2(still_c.pos.y, still_c.pos.x)
		var walk_at := func(k: float) -> Vector2:
			var aa: float = ca0 + k / Defs.RS0
			return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + 14.0)
		_go(walk_at.call(-60.0))
		await _frames(60)
		var cp0: Vector2 = still_c.pos
		var dev := 0.0
		for walk_k in 150:
			_go(walk_at.call(-60.0 - float(walk_k) * 0.8 + (40.0 if walk_k > 75 else 0.0)))
			await _frames(1)
			dev = maxf(dev, still_c.pos.distance_to(cp0))
		_ok("a chest stays still while you walk about", dev < 0.01, "moved %.3f cells as you walked" % dev)

	# ---- a chest whose floor is dug out falls, whole (it doesn't float or come apart) ----
	var chest2 := Vector2i(-1, -1)
	var nfound := 0
	for info in b.infos:
		if not info["ruined"] and info["chests"].size() > 0:
			nfound += 1
			if nfound == 2:
				chest2 = info["chests"][0]
				break
	var c2obj = _chest_obj(chest2)
	if c2obj != null:
		var r_before: float = c2obj.pos.length()
		_go(_cell_pos(chest2.x - 14, chest2.y - 10))
		await _frames(30)
		for f in 70:
			for dx in range(-2, Defs.CHEST_W + 3, 2):
				# owner slot 3 (nobody): digging next to a chest would otherwise open it
				g.brushes.append([_cell_pos(chest2.x + dx, chest2.y + 2), 3.2, 1, 0, 4, 0, 0, 3])
			await _frames(1)
		await _frames(150)
		var dropped: float = r_before - c2obj.pos.length()
		_ok("a chest falls when its floor is dug out", dropped > 2.0 and not c2obj.opened, "it dropped %.1f cells, in one piece" % dropped)
	else:
		_ok("a chest falls when its floor is dug out", false, "no second intact chest found")

	# ---- guards wake up when you come near ----
	if b.guards.size() > 0:
		var gd: Dictionary = b.guards[0]
		_go(gd["pos"] + (gd["pos"] as Vector2).normalized() * 4.0)
		await _frames(70)
		var n := 0
		for e in g.enemies:
			if e.guard_id >= 0:
				n += 1
		_ok("guards appear when you come near", n > 0, "%d guards active" % n)
		for e in g.enemies:
			if not e.boss:
				e.dead = true
		await _frames(2)

	# ---- a mage standing still stays still (no jiggling up and down after landing) ----
	var sp0 := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
	_go(sp0 * (g.gpu.surf_at(g.spawn_angle).x + 25.0))
	await _frames(90)
	var r_min := 1e9
	var r_max := -1e9
	var grounded := 0
	for f in 120:
		await _frames(1)
		var rr: float = g.player.pos.length()
		r_min = minf(r_min, rr)
		r_max = maxf(r_max, rr)
		if g.player.on_ground:
			grounded += 1
	_ok("a mage standing still doesn't jiggle", r_max - r_min < 0.3 and grounded == 120, "moved %.2f cells up and down, on the ground %d of 120 frames" % [r_max - r_min, grounded])

	# ---- mud is only liquid in bogs: under the jungle's and marsh's grass the ground is solid,
	# so you (and the rain) don't sink through a slope that looks like dirt ----
	var N_m: int = Defs.NS
	var raw_m: PackedByteArray = g.gpu.read_world()
	var mud_cols := 0
	var mud_seen := 0
	var mud_deep := 0
	var firm_col := -1
	for cm in range(0, N_m, 3):
		var bnm: String = b.biome(cm)
		if bnm != "jungle" and bnm != "marsh":
			continue
		mud_cols += 1
		var grm: int = b.ground_row(cm)
		var has := false
		for j in range(grm - 2, grm + 18):
			if (raw_m.decode_u32((j * N_m + cm) * 4) & 255) == Defs.MUD:
				has = true
				mud_deep = maxi(mud_deep, j - grm)
		if has:
			mud_seen += 1
		elif firm_col < 0 and bnm == "jungle" and not b.wet(cm) and b.biome(cm - 8) == "jungle" and b.biome(cm + 8) == "jungle" \
				and b.free_span(cm - 15, 30, 12):
			firm_col = cm
	var firm_ok := true
	var firm_txt := "no firm jungle column"
	if firm_col >= 0:
		var grf: int = b.ground_row(firm_col)
		_go(_cell_pos(firm_col, grf - 30))
		await _frames(150)
		var pr: float = g.player.pos.length()
		var top_r: float = Defs.R_TOP - float(grf) + 0.5
		firm_ok = pr > top_r - 4.0 and pr < top_r + 20.0 and g.player.on_ground and not g.player.in_liquid
		firm_txt = "mage stands %.1f cells from the jungle surface" % (pr - top_r)
	_ok("jungle and marsh ground is solid, mud only in bogs", mud_cols > 0 and mud_seen * 100 < mud_cols * 40 and mud_deep <= 8 and firm_ok,
		"%d of %d columns have mud (deepest %d below the surface); %s" % [mud_seen, mud_cols, mud_deep, firm_txt])

	# ---- water soaks loose dirt into mud (a stone basin set into the ground: loose dirt under
	# water; set down by hand it isn't anchored, so it has to rest on the ground) ----
	var mb_a: float = g.spawn_angle - 0.13
	var mb_s: float = g.gpu.surf_at(mb_a).x
	var MBW := 20
	var MBH := 16
	var mb_x: int = Build.cell_of(Vector2(cos(mb_a), sin(mb_a)) * mb_s).x
	var mb_c := Vector2i(mb_x, b.ground_row(mb_x + MBW / 2) - MBH + 3)
	var mbd := PackedInt32Array()
	mbd.resize(MBW * MBH)
	for mj in MBH:
		for mi in MBW:
			var mb_wall := mi < 3 or mi >= MBW - 3 or mj >= MBH - 3
			var cell := 0
			if mb_wall:
				cell = Defs.STONE | 0x20000
			elif mj >= MBH - 7:
				cell = Defs.DIRT
			elif mj >= 3:
				cell = Defs.WATER
			mbd[mj * MBW + mi] = cell | (255 << 8)      # (the background is left as it is: no tree is cut)
	g.stamps.append({"x0": mb_c.x, "y0": mb_c.y, "w": MBW, "h": MBH, "data": mbd})
	_go(Vector2(cos(mb_a), sin(mb_a)) * (mb_s + 14.0))
	var mb_count := func() -> String:
		var mb_rr: Dictionary = g.gpu.read_rect(mb_c.x, mb_c.y, MBW, MBH)
		var tally := {}
		for mb_v in mb_rr["fg"]:
			var mb_nm: String = Defs.MAT_NAMES.get(mb_v & 255, str(mb_v & 255))
			tally[mb_nm] = int(tally.get(mb_nm, 0)) + 1
		return str(tally)
	await _frames(3)
	var mb_t0: String = mb_count.call()
	await _frames(600)
	var mb_r: Dictionary = g.gpu.read_rect(mb_c.x, mb_c.y, MBW, MBH)
	var n_mud := 0
	var n_dirt := 0
	for v in mb_r["fg"]:
		if (v & 255) == Defs.MUD:
			n_mud += 1
		elif (v & 255) == Defs.DIRT:
			n_dirt += 1
	_ok("water soaks loose dirt into mud", n_mud >= 10, "%d mud, %d dirt left in the basin; at first %s, then %s" % [n_mud, n_dirt, mb_t0, mb_count.call()])

	# ---- trees stand when you walk up to them, in every biome (tall ones, and ones rooted in
	# marsh mud, used to fall apart) ----
	var N0: int = Defs.NS
	var toff: int = Defs.total_cells() * 4
	var raw_t: PackedByteArray = g.gpu.read_world()
	var tree_lines := []
	var tree_ok := true
	var biomes_seen := 0
	var forest_col := -1
	for bname in ["forest", "jungle", "marsh", "mountain", "tundra", "savanna", "desert", "grove", "ashland", "ocean"]:
		var best_col := -1
		var best_n := 0
		for k in 64:
			var c0 := k * N0 / 64
			if b.biome(c0 + 60) != bname or b.biome(c0) != bname:
				continue
			var n_t := _plants(raw_t, toff, c0, b.ground_row(c0 + 60))
			if n_t > best_n:
				best_n = n_t
				best_col = c0
		if best_col < 0 or best_n < 40:
			continue
		biomes_seen += 1
		if bname == "forest":
			forest_col = best_col
		var gr2: int = b.ground_row(best_col + 60)
		var bpos := _cell_pos(best_col + 60, gr2 - 30)
		_go(bpos)
		g.ui.title.visible = false
		g.time = fposmod(atan2(bpos.y, bpos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(200)
		# a picture of each biome's plants at midday (saves/shots/biome_<name>.png)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("biome_%s.png" % bname))
		var after_t := _plants(g.gpu.read_world(), toff, best_col, gr2)
		tree_lines.append("%s %d->%d" % [bname, best_n, after_t])
		if after_t < int(best_n * 0.97):
			tree_ok = false
	_ok("trees stand when you come near, in every biome", tree_ok and biomes_seen > 0, ", ".join(tree_lines))

	# ---- a tree whose trunk is cut comes down quickly, even where its crown touches another ----
	var cut_txt := "no forest found"
	var cut_ok := false
	if forest_col >= 0:
		var rw: PackedByteArray = g.gpu.read_world()
		var tcol := -1
		var tid := 0
		var most := 0
		for i in 120:
			var col := posmod(forest_col + i, N0)
			var grc: int = b.ground_row(col)
			var nw := 0
			var idc := 0
			for j in range(grc - 40, grc):
				var a := rw.decode_u32(toff + (j * N0 + col) * 4)
				if (a & 255) == Defs.WOOD and (a & 0x80000000) != 0:
					nw += 1
					idc = a >> 16
			if nw > most:
				most = nw
				tcol = col
				tid = idc
		if tcol >= 0 and most >= 15:
			var grt: int = b.ground_row(tcol)
			var count_tree := func(raw: PackedByteArray) -> int:
				var n := 0
				for j in range(grt - 110, grt - 9):
					for i in range(-40, 41):
						if (raw.decode_u32(toff + (j * N0 + posmod(tcol + i, N0)) * 4) >> 16) == tid:
							n += 1
				return n
			_go(_cell_pos(tcol - 30, grt - 10))
			await _frames(30)
			var zone := func(raw: PackedByteArray) -> String:
				var nwz := 0
				var nfg := 0
				for j in range(grt - 10, grt - 3):
					for i in range(-5, 6):
						var kk := (j * N0 + posmod(tcol + i, N0)) * 4
						if (raw.decode_u32(toff + kk) & 255) == Defs.WOOD:
							nwz += 1
						if (raw.decode_u32(kk) & 255) != 0:
							nfg += 1
				# support of the tree's wood well above the cut
				var sup := []
				for j in [grt - 14, grt - 20, grt - 30]:
					var a2 := raw.decode_u32(toff + (j * N0 + tcol) * 4)
					sup.append("%d:%d" % [a2 & 255, (a2 >> 8) & 63])
				# the best-held cell of that tree above the cut, and what is around it
				var best := 99
				var where := ""
				for j in range(grt - 110, grt - 9):
					for i in range(-40, 41):
						var cc := posmod(tcol + i, N0)
						var a3 := raw.decode_u32(toff + (j * N0 + cc) * 4)
						if (a3 >> 16) != tid:
							continue
						var sv := (a3 >> 8) & 63
						if sv < best:
							best = sv
							var nb := []
							for o in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
								nb.append(str(raw.decode_u32(((j + o[1]) * N0 + posmod(cc + o[0], N0)) * 4) & 255))
							where = "S%d mat %d at %d,%d fg %s" % [sv, a3 & 255, i, grt - j, "/".join(nb)]
				return "wood in cut %d, front cells %d, sup %s, best %s" % [nwz, nfg, ",".join(sup), where]
			var before_n: int = count_tree.call(g.gpu.read_world())
			var z0: String = zone.call(g.gpu.read_world())
			# wood in the background all around (this tree and its neighbours): a felled tree should
			# still be wood afterwards, lying where it fell, not a heap of timber grains
			var wood_round := func(raw: PackedByteArray) -> int:
				var n := 0
				for j in range(grt - 150, grt + 6):
					for i in range(-170, 171):
						var kw := (j * N0 + posmod(tcol + i, N0)) * 4
						if (raw.decode_u32(toff + kw) & 255) == Defs.WOOD or (raw.decode_u32(kw) & 255) == Defs.WOOD:
							n += 1
				return n
			var own_wood := 0
			var rw0: PackedByteArray = g.gpu.read_world()
			for j in range(grt - 110, grt - 9):
				for i in range(-40, 41):
					var a5 := rw0.decode_u32(toff + (j * N0 + posmod(tcol + i, N0)) * 4)
					if (a5 >> 16) == tid and (a5 & 255) == Defs.WOOD:
						own_wood += 1
			var wood0: int = wood_round.call(rw0)
			# loose specks (timber grains, leaf litter) and leaves around, before and after
			var bits_round := func(raw: PackedByteArray) -> Vector2i:
				var specks := 0
				var leaves := 0
				for j in range(grt - 150, grt + 6):
					for i in range(-170, 171):
						var kbits := (j * N0 + posmod(tcol + i, N0)) * 4
						var tfg := raw.decode_u32(kbits) & 255
						if tfg == Defs.TIMBER or tfg == Defs.LITTER:
							specks += 1
						if (raw.decode_u32(toff + kbits) & 255) == Defs.LEAF:
							leaves += 1
				return Vector2i(specks, leaves)
			var bits0: Vector2i = bits_round.call(rw0)
			var own_leaves := 0
			for j in range(grt - 110, grt - 9):
				for i in range(-40, 41):
					var a6 := rw0.decode_u32(toff + (j * N0 + posmod(tcol + i, N0)) * 4)
					if (a6 >> 16) == tid and (a6 & 255) == Defs.LEAF:
						own_leaves += 1
			# its roots: its own wood below the ground line, in the background behind the earth
			var own_roots := 0
			for j in range(grt, grt + 19):
				for i in range(-40, 41):
					var a7 := rw0.decode_u32(toff + (j * N0 + posmod(tcol + i, N0)) * 4)
					if (a7 >> 16) == tid and (a7 & 255) == Defs.ROOT:
						own_roots += 1
			# and across the land around: no trunk ends in the air above a slope (a flat, bare bottom):
			# the lowest wood of a tree in a column near the ground rests on earth (or its own roots)
			var bare := 0
			var feet := 0
			for i in range(-600, 601):
				var cb: int = posmod(tcol + i, N0)
				var grb: int = b.ground_row(cb)
				var foot := -1
				var lid := 0
				for j in range(grb - 8, grb + 3):
					var abf := rw0.decode_u32(toff + (j * N0 + cb) * 4)
					if ((abf & 255) == Defs.WOOD or (abf & 255) == Defs.ROOT) and (abf >> 30) == 2:
						foot = j
						lid = abf >> 16
				if foot < 0:
					continue
				feet += 1
				var below_f := rw0.decode_u32((foot + 1) * N0 * 4 + cb * 4) & 255
				var below_b := rw0.decode_u32(toff + ((foot + 1) * N0 + cb) * 4)
				if below_f == 0 and (below_b >> 16) != lid:
					bare += 1
			_ok("trees have roots, and trunks reach the ground on slopes", own_roots > 8 and feet > 20 and bare * 20 < feet,
				"the felled tree has %d root cells; %d of %d trunk-foot columns end over open air" % [own_roots, bare, feet])
			var max_chunks := 0
			g.hitch_us = 0
			g.prof_reset()
			# hold the dig on the trunk for a moment (each frame harvests about a third of it)
			for fk in 15:
				for dc in [-2, 0, 2]:
					g.brushes.append([_cell_pos(tcol + dc, grt - 7), 2.5, 1, 0, 4, 0, 0, 0])
				await _frames(1)
			_go(_cell_pos(tcol - 30, grt - 10))
			for fall_k in 40:
				max_chunks = maxi(max_chunks, g.chunks.list.size())
				await _frames(1)
			var mid_n: int = count_tree.call(g.gpu.read_world())
			var z1: String = zone.call(g.gpu.read_world())
			for fk3 in 50:
				max_chunks = maxi(max_chunks, g.chunks.list.size())
				await _frames(1)
			var after_n: int = count_tree.call(g.gpu.read_world())
			cut_ok = before_n > 50 and after_n < before_n / 10
			cut_txt = "column %d: %d cells of that tree above the cut, %d after 0.7 s, %d after 1.5 s" % [tcol, before_n, mid_n, after_n]
			# then it lies where it fell, still wood (it toppled as one piece)
			for fk4 in 400:
				if g.chunks.list.is_empty():
					break
				await _frames(1)
			await _frames(30)
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("felled_tree.png"))
			var rw1: PackedByteArray = g.gpu.read_world()
			var wood1: int = wood_round.call(rw1)
			var bits1: Vector2i = bits_round.call(rw1)
			var whole := max_chunks > 0 and wood0 - wood1 < own_wood * 2 / 5
			# it leaves no scatter of loose specks (how much of its crown survives depends on what it
			# lands on: a cottage wall crushes more of it than open ground; reported, not judged)
			var tidy := bits1.x - bits0.x < 40
			_ok("a felled tree topples whole and lies where it fell", whole and tidy,
				"it came away as %d piece(s); wood around: %d before, %d after (the tree had %d); loose specks %d -> %d; leaves %d -> %d (its own %d); the game's longest frame %.1f ms (%s [%s, %s, %s, %s], %s, %s)" % [max_chunks, wood0, wood1, own_wood, bits0.x, bits1.x, bits0.y, bits1.y, own_leaves, g.hitch_us / 1000.0, _peak("lifting pieces out"), _peak("lift: read"), _peak("lift: find"), _peak("lift: make"), _peak("lift: clear"), _peak("falling pieces"), _peak("read back")])
			if not (before_n > 50 and after_n < before_n / 10):
				cut_txt += " (before: %s; after: %s)" % [z0, z1]
		else:
			cut_txt = "no tall trunk found"
	_ok("a cut tree falls quickly, even when its crown touches a neighbour", cut_ok, cut_txt)

	# ---- sand (and other powders) is generated resting: nothing pours when you arrive ----
	var sand_col := -1
	for k in 64:
		var c1 := k * N0 / 64
		if b.biome(c1) == "desert" and b.biome(c1 + 150) == "desert":
			sand_col = c1
			break
	if sand_col >= 0:
		var sg: int = b.ground_row(sand_col + 75)
		var before_p := _powders(g.gpu.read_world(), sand_col, sg)
		_go(_cell_pos(sand_col + 75, sg - 30))
		await _frames(150)
		var after_p := _powders(g.gpu.read_world(), sand_col, sg)
		var moved := 0
		for key in before_p:
			if not after_p.has(key):
				moved += 1
		_ok("generated sand stays put when you arrive", moved <= maxi(4, before_p.size() / 100), "%d of %d powder cells moved" % [moved, before_p.size()])
	else:
		_ok("generated sand stays put when you arrive", true, "no desert on this planet")

	# ---- dungeons: every room reachable from the gatehouse, the reliquary sealed ----
	var dun_n := 0
	var dun_ok := true
	var dun_lines := []
	var dun_shot := Vector2i(-1, -1)
	for info in b.infos:
		var meta: Dictionary = info.get("meta", {})
		if not meta.get("dungeon", false):
			continue
		dun_n += 1
		dun_lines.append("%d of %d rooms reached%s" % [meta["reached"], meta["rooms"], ", reliquary OPEN" if meta["vault_open"] else ""])
		dun_ok = dun_ok and meta["reached"] == meta["rooms"] and meta["rooms"] >= 2 and not meta["vault_open"]
		if dun_shot.x < 0:
			dun_shot = meta["shot"]
	_ok("dungeons are built, connected, with a sealed reliquary", dun_n >= 2 and dun_ok, "%d dungeons: %s" % [dun_n, "; ".join(dun_lines)])
	if dun_shot.x >= 0:
		# a picture of a dungeon's entrance hall (saves/shots/dungeon.png)
		_go(_cell_pos(dun_shot.x, dun_shot.y - 14))
		await _frames(70)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("dungeon.png"))

	# ---- furniture and town details: background pixels only, so nothing blocks the way ----
	var decor_n := 0
	var decor_solid := 0
	var best_dec := -1
	var best_info := {}
	for info in b.infos:
		var nd: int = info.get("decor", 0)
		decor_n += nd
		decor_solid += int(info.get("decor_hid", 0))
		if nd > best_dec:
			best_dec = nd
			best_info = info
	# an intact building comes out of the generator whole: nothing of it hangs unsupported (the
	# generator's soundness pass used to cut the wall and roof away above wide furniture)
	var unsound_n := 0
	var unsound_txt := []
	for info in b.infos:
		if not info["ruined"] and int(info.get("unsound", 0)) > 12:
			unsound_n += 1
			if unsound_txt.size() < 4:
				unsound_txt.append("%s: %d cells %s" % [b.label_at(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) + int(info["h"]) - 45)), info["unsound"], str(info["meta"].get("cuts", {}))])
	_ok("intact buildings are generated whole (nothing big cut away as unsupported)", unsound_n == 0, "%d buildings lost cells%s" % [unsound_n, (": " + ", ".join(unsound_txt)) if unsound_n > 0 else ""])
	_ok("buildings are furnished, and props never block", decor_n > 400 and decor_solid == 0, "%d prop pixels, %d in front of something solid" % [decor_n, decor_solid])
	if best_dec > 0:
		# the most furnished place, at midday (saves/shots/town.png)
		var tcx := int(best_info["x0"]) + int(best_info["w"]) / 2
		var tpos := _cell_pos(tcx, b.ground_row(tcx) - 24)
		_go(tpos)
		g.ui.title.visible = false
		g.time = fposmod(atan2(tpos.y, tpos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(60)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("town.png"))
	for lab in b.labels:
		if "Village" in str(lab["name"]):
			var vcx := int(lab["x0"]) + int(lab["w"]) / 3
			var vpos := _cell_pos(vcx, b.ground_row(vcx) - 24)
			_go(vpos)
			g.time = fposmod(atan2(vpos.y, vpos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
			await _frames(60)
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("village.png"))
			break

	# ---- clouds you can fly into ----
	var fog_best := 0.0
	var fog_at := -1.0
	for k in 48:
		var ang: float = g.spawn_angle + float(k) * 0.05
		g.test_god = true
		_go(Vector2(cos(ang), sin(ang)) * (Defs.RS0 + 150.0))
		await _frames(6)
		if g.player.fog > fog_best:
			fog_best = g.player.fog
			fog_at = ang
		if fog_best > 0.6:
			break
	if fog_at >= 0.0:
		_go(Vector2(cos(fog_at), sin(fog_at)) * (Defs.RS0 + 150.0))
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("cloud.png"))
	_ok("you can fly into a cloud", fog_best > 0.3, "deepest cloud found: %.2f" % fog_best)

	# ---- build mode: a back wall, a table and a door go up where the mage points ----
	var bg_ang: float = g.spawn_angle - 0.06      # away from where the platform test builds
	var bsurf: float = g.gpu.surf_at(bg_ang).x
	_go(Vector2(cos(bg_ang), sin(bg_ang)) * (bsurf + 12.0))
	await _frames(40)
	g.player.inv[Defs.PLANK] += 200
	g.player.inv[Defs.WOODDOOR] += 1
	if not g.build_on:
		g._toggle_build()
	var spot := func(k: float, up: float) -> Vector2:
		var aa: float = atan2(g.player.pos.y, g.player.pos.x) + k / Defs.RS0
		return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + up)
	# a patch of plank wall, painted against the ground
	g.build_cat = 0
	g.build_idx[0] = 0
	g.build_shape = 0                # painted with the brush
	var wall_at: Vector2 = spot.call(10.0, 2.0)
	g.test_aim = wall_at
	g.test_cast = true
	await _frames(12)
	g.test_cast = false
	await _frames(6)
	var wall_first := 0
	var rawf: PackedByteArray = g.gpu.read_world()
	var cqf: Vector2i = Build.cell_of(wall_at)
	for djf in range(-34, 70):
		for dif in range(-16, 17):
			var kf: int = ((cqf.y + djf) * int(Defs.NS) + posmod(cqf.x + dif, Defs.NS)) * 4
			var af: int = rawf.decode_u32(Defs.total_cells() * 4 + kf)
			if (af & 255) == Defs.PLANK and (af & 0x4000) != 0:
				wall_first += 1
	# a table
	g.build_cat = 2
	g.build_idx[2] = 0
	# (try a few places along the ground until it fits)
	var table_at: Vector2 = spot.call(-14.0, 5.0)
	var table_ok := false
	# (try a few places along the ground until it fits; trees, and the one felled above, may fill this
	# stretch: then walk on and try again further along)
	var table_why := []
	for tk in 16:
		table_at = spot.call((-14.0 - tk * 4.0) if tk < 8 else (14.0 + (tk - 8) * 4.0), 5.0)
		g.test_aim = table_at
		await _frames(3)
		table_ok = g.build_prev.get("ok", false)
		if table_ok:
			break
		table_why.append(g.build_why)
	if not table_ok:
		for base in [-90.0, 90.0, -140.0, 140.0, -190.0, 190.0, -240.0, 240.0]:
			_go(spot.call(base, 14.0))
			await _frames(25)
			for tk2 in 9:
				table_at = spot.call(-16.0 + tk2 * 4.0, 5.0)
				g.test_aim = table_at
				await _frames(3)
				table_ok = g.build_prev.get("ok", false)
				if table_ok:
					break
			if table_ok:
				break
	if not table_ok:
		print("[tests] no spot for the table: ", table_why)
	g.build_click = true
	await _frames(6)
	var table_last: String = g.build_last
	var tstamp: Dictionary = g.build_last_stamp
	var count_decor := func(raw: PackedByteArray) -> int:
		var n := 0
		if tstamp.is_empty():
			return -1
		var boff3: int = Defs.total_cells() * 4
		for tj in int(tstamp["h"]):
			for ti in int(tstamp["w"]):
				var kt: int = ((int(tstamp["y0"]) + tj) * int(Defs.NS) + posmod(int(tstamp["x0"]) + ti, Defs.NS)) * 4
				if (raw.decode_u32(boff3 + kt) & 255) == Defs.DECOR:
					n += 1
		return n
	var table_now: int = count_decor.call(g.gpu.read_world())
	await _frames(60)
	var table_later: int = count_decor.call(g.gpu.read_world())
	# what the table's box holds now, front and back
	var box_mats := {}
	var rawt: PackedByteArray = g.gpu.read_world()
	if not tstamp.is_empty():
		for tj2 in int(tstamp["h"]):
			for ti2 in int(tstamp["w"]):
				var kt2: int = ((int(tstamp["y0"]) + tj2) * int(Defs.NS) + posmod(int(tstamp["x0"]) + ti2, Defs.NS)) * 4
				var fn: String = Defs.NAMES[rawt.decode_u32(kt2) & 255]
				var bn2: String = "bg " + Defs.NAMES[rawt.decode_u32(Defs.total_cells() * 4 + kt2) & 255]
				box_mats[fn] = int(box_mats.get(fn, 0)) + 1
				box_mats[bn2] = int(box_mats.get(bn2, 0)) + 1
	# a door
	g.build_cat = 1
	g.build_idx[1] = 0
	var doors_before: int = g.doors.size()
	# (well clear of the table, which is set down again where it stood later on)
	var t_ang: float = atan2(table_at.y, table_at.x)
	var by_table := func(k: float, up: float) -> Vector2:
		var aa: float = t_ang + k / Defs.RS0
		return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + up)
	_go(by_table.call(-30.0, 14.0))
	await _frames(25)
	var door_at: Vector2 = by_table.call(-30.0, 6.0)
	var door_ok := false
	for dk2 in 6:
		door_at = by_table.call(-30.0 - dk2 * 5.0, 6.0)
		g.test_aim = door_at
		await _frames(3)
		door_ok = g.build_prev.get("ok", false)
		if door_ok:
			break
	g.build_click = true
	await _frames(20)
	# a whole house (Timber style, 36 wide), wherever along the ground it fits
	for mt in [Defs.PLANK, Defs.WOOD, Defs.MASONRY, Defs.TILE, Defs.BRICK, Defs.SANDSTONE, Defs.DRYGRASS, Defs.TORCH, Defs.GLASS]:
		g.player.inv[mt] += 3000
	g.build_cat = 4
	g.build_idx[4] = 0
	g.build_style = 0
	g.build_w = 36
	g.build_floors = 1
	var house_ok := false
	var house_at := Vector2.ZERO
	var doors_mid: int = g.doors.size()
	var hb_ang: float = atan2(g.player.pos.y, g.player.pos.x)
	var at_ang := func(k: float, up: float) -> Vector2:
		var aa: float = hb_ang + k / Defs.RS0
		return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + up)
	for hk in [-150.0, -190.0, -230.0, -270.0, -310.0, -350.0, -390.0, -430.0, -470.0, -510.0, -550.0, -590.0, -630.0, -670.0]:
		# stand next to the spot (you can only build within reach), well away from the pieces above
		_go(at_ang.call(hk + 30.0, 14.0))
		await _frames(25)
		house_at = at_ang.call(hk, 8.0)
		g.test_aim = house_at
		await _frames(3)
		house_ok = g.build_prev.get("ok", false)
		if house_ok:
			break
	if house_ok:
		g.build_click = true
		await _frames(30)
		g.test_aim = Vector2.ZERO
		# a picture of it (saves/shots/built_house.png)
		var hsave: Vector2 = g.player.pos
		_go(house_at)
		g.time = fposmod(atan2(house_at.y, house_at.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("built_house.png"))
		_go(hsave)
		await _frames(5)
	var house_doors: int = g.doors.size() - doors_mid
	g.test_aim = Vector2.ZERO
	g._toggle_build()
	var rawb: PackedByteArray = g.gpu.read_world()
	var boffb: int = Defs.total_cells() * 4
	var n_wall := 0
	var n_decor := 0
	var n_door := 0
	for bq in [[wall_at, 0], [table_at, 1]]:
		var cq: Vector2i = Build.cell_of(bq[0])
		for dj in range(-34, 70):
			for di in range(-16, 17):
				var kb: int = ((cq.y + dj) * int(Defs.NS) + posmod(cq.x + di, Defs.NS)) * 4
				var fb: int = rawb.decode_u32(kb) & 255
				var ab: int = rawb.decode_u32(boffb + kb)
				if bq[1] == 0 and (ab & 255) == Defs.PLANK and (ab & 0x4000) != 0:
					n_wall += 1
				elif bq[1] == 1 and (ab & 255) == Defs.DECOR:
					n_decor += 1
	# the door built: its own cells, where its record says they are
	if doors_mid > doors_before:
		var nd3: Dictionary = g.doors[doors_mid - 1]
		for dj3 in int(nd3["h"]):
			for di3 in int(nd3["w"]):
				var kd3: int = ((int(nd3["row"]) + dj3) * int(Defs.NS) + posmod(int(nd3["col"]) + di3, Defs.NS)) * 4
				if (rawb.decode_u32(kd3) & 255) == Defs.WOODDOOR:
					n_door += 1
	_ok("build mode puts up a whole house", house_ok and house_doors == 2, "fits somewhere: %s, its doors: %d; last click: %s" % [house_ok, house_doors, g.build_last])
	_ok("build mode puts up walls, furniture and doors", n_wall >= 8 and n_decor >= 20 and n_door >= 60 and doors_mid == doors_before + 1,
		"wall cells %d (%d when painted), table cells %d (fit %s; %s; in its blueprint's box: %d at once, %d a second later, %d at the end; box %s, holds %s), door cells %d (fit %s), doors %d -> %d" % [n_wall, wall_first, n_decor, table_ok, table_last, table_now, table_later, count_decor.call(rawb), str([tstamp.get("x0"), tstamp.get("y0"), tstamp.get("w"), tstamp.get("h")]), str(box_mats), n_door, door_ok, doors_before, doors_mid])

	# ---- furniture: taken whole, set down again, forged; a bed in a room makes a home ----
	var furn0: int = g.player.furn.size()
	var picked := false
	var t_item: Dictionary = {}
	var t_px := 0
	var t_left := -1
	var t_back := -1
	var back_ok := false
	var t_why := ""
	if not tstamp.is_empty():
		var t_mid: Vector2 = Build.cell_pos(int(tstamp["x0"]) + int(tstamp["w"]) / 2, int(tstamp["y0"]) + 3)
		picked = g._pick_up_furniture(g.player, t_mid)
		await _frames(4)
		t_left = count_decor.call(g.gpu.read_world())
		if g.player.furn.size() > furn0:
			t_item = g.player.furn[g.player.furn.size() - 1]
		for tr in t_item.get("rows", []):
			for tch in String(tr):
				if tch != "." and tch != "t":
					t_px += 1
		# set it down again from the Satchel tab, where it stood (from a little way off)
		_go(by_table.call(24.0, 14.0))
		await _frames(30)
		if not g.build_on:
			g._toggle_build()
		g.build_cat = Build.CAT_SATCHEL
		g.build_idx[Build.CAT_SATCHEL] = maxi(0, g.player.furn.size() - 1)
		# (loose litter or grit that blew onto its old spot meanwhile is swept off first)
		var sw: Dictionary = g.gpu.read_rect(int(tstamp["x0"]), int(tstamp["y0"]), int(tstamp["w"]), int(tstamp["h"]))
		var swd := PackedInt32Array()
		swd.resize(int(tstamp["w"]) * int(tstamp["h"]))
		swd.fill(0xFFFF)
		var swept := 0
		for swk in swd.size():
			var swm: int = sw["fg"][swk] & 255
			if swm != 0 and Defs.KIND[swm] == Defs.K_POWDER:
				swd[swk] = 0xFF00
				swept += 1
		if swept > 0:
			g.stamps.append({"x0": int(tstamp["x0"]), "y0": int(tstamp["y0"]), "w": int(tstamp["w"]), "h": int(tstamp["h"]), "data": swd})
			await _frames(2)
		g.test_aim = table_at
		await _frames(3)
		back_ok = g.build_prev.get("ok", false)
		# (something may have tumbled into that spot meanwhile: then a little way along)
		for try_k in 16:
			if back_ok:
				break
			if t_why == "":
				var wr: Dictionary = g.gpu.read_rect(int(tstamp["x0"]), int(tstamp["y0"]), int(tstamp["w"]), int(tstamp["h"]))
				var wm := {}
				for wv in wr["fg"]:
					var wn: String = Defs.NAMES[wv & 255]
					wm[wn] = int(wm.get(wn, 0)) + 1
				t_why = "its old spot holds %s; " % str(wm)
			g.test_aim = by_table.call((-4.0 - try_k * 4.0) if try_k < 8 else (4.0 + (try_k - 8) * 4.0), 5.0)
			await _frames(3)
			back_ok = g.build_prev.get("ok", false)
		g.build_click = true
		await _frames(8)
		t_back = 0
		var st3: Dictionary = g.build_last_stamp
		if not st3.is_empty():
			var rb3: Dictionary = g.gpu.read_rect(int(st3["x0"]), int(st3["y0"]), int(st3["w"]), int(st3["h"]))
			for bv in rb3["bg"]:
				if (bv & 255) == Defs.DECOR:
					t_back += 1
	_ok("furniture is picked up whole and set down again", picked and t_item.get("name", "") == "Table" and t_left == 0 and t_px == table_now and back_ok and t_back >= table_now - 2 and g.player.furn.size() == furn0,
		"picked %s as %s (%d pixels, %d were placed), left behind %d; set down again: %sfits %s, %d cells; carried %d -> %d" % [picked, t_item.get("name", "-"), t_px, table_now, t_left, t_why, back_ok, t_back, furn0, g.player.furn.size()])
	# a bed from the Wisp Forge
	var bed_r: Dictionary = {}
	for r in g.recipes:
		if String(r.get("furniture", "")) == "bed":
			bed_r = r
	var forged := false
	var bed_item: Dictionary = {}
	if not bed_r.is_empty():
		for k in bed_r["cost"]:
			g.player.inv[int(k)] += int(bed_r["cost"][k])
		var nf: int = g.player.furn.size()
		forged = g.craft(bed_r) and g.player.furn.size() == nf + 1
		if forged:
			bed_item = g.player.furn[g.player.furn.size() - 1]
	_ok("furniture is forged into the satchel", forged and bed_item.get("name", "") == "Bed" and int(bed_item.get("kind", 0)) == Build.Props.BED,
		"recipe %s, forged %s: %s" % [bed_r.get("id", "none"), forged, str(bed_item.get("name", "-"))])
	# a bed out in the open is no home; one inside the house built above is
	var sky_c: Vector2i = Build.cell_of(g.player.pos)
	var open_why: String = g._home_check({"c0": sky_c.x, "r0": sky_c.y - 150, "c1": sky_c.x + 20, "r1": sky_c.y - 140})
	var home_set := false
	var bed_placed := false
	var woke_at := -1.0
	if house_ok and forged:
		_go(house_at)
		await _frames(30)
		g.build_cat = Build.CAT_SATCHEL
		g.build_idx[Build.CAT_SATCHEL] = g.player.furn.size() - 1
		var nb0: int = g.player.furn.size()
		for bk in 7:
			g.test_aim = house_at + (house_at - g.player.pos).normalized() * 0.0 + Vector2(-house_at.y, house_at.x).normalized() * float(bk % 2 * 2 - 1) * float(bk / 2) * 5.0
			await _frames(3)
			if g.build_prev.get("ok", false):
				g.build_click = true
				await _frames(8)
				break
		bed_placed = g.player.furn.size() == nb0 - 1
		g.test_aim = Vector2.ZERO
		if g.build_on:
			g._toggle_build()
		await _frames(10)
		g.planet_state.erase("home")
		g._interact()
		home_set = g.planet_state.has("home")
		if home_set:
			var hp3: Array = g.planet_state["home"]["pos"]
			var hpos := Vector2(float(hp3[0]), float(hp3[1]))
			_go(Vector2(cos(g.spawn_angle), sin(g.spawn_angle)) * (Defs.RS0 + 40.0))
			await _frames(5)
			g._respawn()
			woke_at = g.player.pos.distance_to(hpos)
			await _frames(20)
		g.planet_state.erase("home")
	if g.build_on:
		g._toggle_build()
	_ok("a bed in a room makes a home you wake up in", open_why != "" and bed_placed and home_set and woke_at >= 0.0 and woke_at < 4.0,
		"a bed in the open needs %s; the bed set down in the house: %s, home set: %s, woke %.1f from it" % [open_why if open_why != "" else "nothing (wrong)", bed_placed, home_set, woke_at])

	# ---- holding background harvest over a wall (no furniture there) costs next to nothing ----
	_go(wall_at + wall_at.normalized() * 10.0)
	await _frames(30)
	g._pick_up_furniture(g.player, wall_at)
	await _frames(2)
	var tq := Time.get_ticks_usec()
	for qk in 30:
		g._pick_up_furniture(g.player, wall_at)
	var pick_us := float(Time.get_ticks_usec() - tq) / 30.0
	_ok("background harvest over a plain wall stays cheap", pick_us < 400.0, "%.0f us a frame looking for furniture to pick up" % pick_us)

	# ---- straight walls: a block wall dragged up from the ground, a back wall rectangle beside it ----
	_go(Vector2(cos(bg_ang), sin(bg_ang)) * (bsurf + 12.0))
	await _frames(40)
	if not g.build_on:
		g._toggle_build()
	g.player.inv[Defs.MASONRY] += 400
	var shape_res := []
	var shape_ok := true
	for sh in [[Build.CAT_BLOCKS, 0, 1, Defs.MASONRY, false, 30.0, 0.0, 30.0, 26.0], [0, 0, 2, Defs.PLANK, true, -40.0, 0.0, -22.0, 14.0]]:
		g.build_cat = int(sh[0])
		g.build_idx[g.build_cat] = int(sh[1])
		g.build_shape = int(sh[2])
		g.build_thick = 2
		var mt: int = sh[3]
		# from the ground at one spot to a point above another (a straight wall snaps upright)
		var a_pos: Vector2 = spot.call(float(sh[5]), 1.5 + float(sh[6]))
		var b_pos: Vector2 = spot.call(float(sh[7]), float(sh[8]))
		var inv0: int = g.player.inv[mt]
		g.test_aim = a_pos
		await _frames(3)
		g.test_cast = true
		g.build_click = true
		await _frames(3)
		g.test_aim = b_pos
		await _frames(4)
		var laid_prev: int = g.build_prev.get("cells", []).size()
		var prev_ok: bool = g.build_prev.get("ok", false)
		g.test_cast = false
		await _frames(4)
		var used: int = inv0 - g.player.inv[mt]
		var st: Dictionary = g.build_last_stamp
		var n_in := 0
		if not st.is_empty():
			var rr: Dictionary = g.gpu.read_rect(int(st["x0"]), int(st["y0"]), int(st["w"]), int(st["h"]))
			for v in (rr["bg"] if sh[4] else rr["fg"]):
				if (v & 255) == mt and (not sh[4] or (v & 0x4000) != 0):
					n_in += 1
		var straight := false
		if not st.is_empty():
			# a block wall comes out 2 cells wide; the back wall fills its whole box
			straight = (int(st["w"]) <= 3) if not sh[4] else (n_in >= int(st["w"]) * int(st["h"]) * 0.5)
		shape_res.append("%s %s: preview %d cells (ok %s), %d used, %d in the world, box %s" % [Build.SHAPES[int(sh[2])], Defs.NAMES[mt], laid_prev, prev_ok, used, n_in, str([st.get("w"), st.get("h")])])
		if not (prev_ok and used > 20 and n_in >= used * 0.9 and straight):
			shape_ok = false
	g.test_aim = Vector2.ZERO
	g.build_shape = 2
	if g.build_on:
		g._toggle_build()
	_ok("build mode lays straight walls and back walls by dragging", shape_ok, "; ".join(shape_res))

	# ---- furniture is a layer in front of the wall: burnt or taken, the wall behind it stays ----
	var fw_at: Vector2 = spot.call(-95.0, 0.0)
	var fw_c: Vector2i = Build.cell_of(fw_at)
	var FWW := 44
	var FWH := 22
	var fwd := PackedInt32Array()
	fwd.resize(FWW * FWH)
	fwd.fill(0xff | (Defs.MASONRY << 8) | 0x40000 | 0x20000)     # an anchored stone back wall, standing on the ground
	var fw_x0: int = fw_c.x - FWW / 2
	var fw_y0: int = fw_c.y - FWH - 1
	g.stamps.append({"x0": posmod(fw_x0, Defs.NS), "y0": fw_y0, "w": FWW, "h": FWH, "data": fwd})
	await _frames(3)
	var trng := RandomNumberGenerator.new()
	trng.seed = 77
	var tdes: Dictionary = Build.Props.make("table", trng, null)
	var trows: Array = tdes["rows"]
	var t_boxes := []
	for tk2 in 2:
		var tcol: int = fw_x0 + 6 + tk2 * 22
		var tpc: Array = Build.prop_cells(trows, tcol, fw_y0 + FWH - 8, false)    # (clear of the ground: in open air)
		var tst: Dictionary = Build.prop_stamp(tpc, Build.Props.kind_id("table"))
		g.stamps.append(tst)
		t_boxes.append(tst)
	await _frames(4)
	var box_bg := func(st2: Dictionary) -> Dictionary:
		var rr: Dictionary = g.gpu.read_rect(int(st2["x0"]), int(st2["y0"]), int(st2["w"]), int(st2["h"]))
		var out := {"decor": 0, "stone": 0, "empty": 0}
		for v in rr["bg"]:
			var m2: int = v & 255
			if m2 == Defs.DECOR:
				out["decor"] += 1
			elif m2 == Defs.MASONRY:
				out["stone"] += 1
			elif m2 == 0:
				out["empty"] += 1
		return out
	var before_a: Dictionary = box_bg.call(t_boxes[0])
	_go(spot.call(-95.0, 14.0))
	await _frames(20)
	# the first is taken whole
	var tmid0: Dictionary = t_boxes[0]
	var nfurn0: int = g.player.furn.size()
	g.player.decon_pause = 0
	g._deconstruct(g.player, _cell_pos(int(tmid0["x0"]) + int(tmid0["w"]) / 2, int(tmid0["y0"]) + int(tmid0["h"]) / 2))
	var took: bool = g.player.furn.size() == nfurn0 + 1
	var paused0: int = g.player.decon_pause    # (letting go of the button clears it, so read it now)
	await _frames(4)
	var taken_now: Dictionary = box_bg.call(t_boxes[0])
	# holding harvest carries on after a moment (no need to let go and press again)
	var paused: int = paused0
	g.player.decon_pause = paused0             # still holding the button
	var nb0: int = g.brushes.size()
	for hk in paused + 1:
		g._deconstruct(g.player, fw_at + fw_at.normalized() * 30.0)
	var resumed: bool = g.brushes.size() > nb0
	g.brushes.resize(nb0)
	# the second burns
	var tmid1: Dictionary = t_boxes[1]
	var tfire: Vector2 = _cell_pos(int(tmid1["x0"]) + int(tmid1["w"]) / 2, int(tmid1["y0"]) + int(tmid1["h"]) / 2)
	# (a fireball's blast: it sets what burns alight where it reaches)
	for fk2 in 4:
		g._explode(tfire, 7.0, 1, 1, 0.0)
		await _frames(12)
	await _frames(150)
	var after_a: Dictionary = box_bg.call(t_boxes[0])
	var after_b: Dictionary = box_bg.call(t_boxes[1])
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("furniture_wall.png"))
	var burnt_pick: bool = g._pick_up_furniture(g.player, tfire)
	_ok("burnt or taken, furniture leaves the wall behind it whole", before_a["decor"] > 20 and took and taken_now["decor"] == 0 and taken_now["empty"] == 0 and after_b["decor"] < before_a["decor"] / 4 and after_b["empty"] == 0 and (after_b["decor"] > 0 or not burnt_pick) and paused > 0 and resumed,
		"before: %s; taken whole (%s): %s (after the fire next to it: %s); burnt: %s; anything left to pick up where it burnt: %s; harvest carries on after a pickup (%d frames' pause): %s" % [str(before_a), took, str(taken_now), str(after_a), str(after_b), burnt_pick, paused, resumed])

	# ---- conjuring onto a foe strikes it instead of burying it ----
	var foe = g.spawn_enemy("slime", spot.call(18.0, 8.0))
	var foe_hp: float = foe.hp
	g.sel = maxi(0, g.known.find("conjure"))
	g.mat = Defs.DIRT
	g.player.inv[Defs.DIRT] += 100
	g.test_cast = true
	for f in 20:
		g.test_aim = foe.pos
		await _frames(1)
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	await _frames(60)
	_ok("conjuring onto a foe hurts it and doesn't bury it", (g.enemies.has(foe) and foe.hp < foe_hp) or foe.hp <= 0.0, "still there: %s, health %.0f -> %.0f" % [g.enemies.has(foe), foe_hp, foe.hp])
	g.enemies.erase(foe)      # out of the way of the tests that conjure next
	g.sel = 0

	# ---- foes are dangerous: they see you, wind up (glowing) and then lunge, shoot, swoop or blink ----
	var keep_foes: Array = g.enemies.duplicate()
	g.enemies.clear()
	var foe_lines := []
	var foe_ok := true
	g.player.hp = g.max_hp
	g.iframes = 0
	# a swordsman beside you winds up, then lunges and cuts
	g.test_god = false
	var sk = g.spawn_enemy("skeleton", spot.call(16.0, 9.5))
	var saw_wind := false
	var hp_sk: float = g.player.hp
	var cut := false
	for fr2 in 200:
		if sk.act == "windup":
			saw_wind = true
		if g.player.hp < hp_sk:
			cut = true                    # (then healed straight away: a run of cuts mustn't kill him
			g.player.hp = g.max_hp        # and leave the tests after this with a dead mage)
		await _frames(1)
	g.test_god = true
	g.player.hp = g.max_hp
	foe_lines.append("skeleton: wound up %s, cut you %s" % [saw_wind, cut])
	foe_ok = foe_ok and saw_wind and cut
	g.enemies.clear()
	g.player.hp = g.max_hp
	# an archer with a clear line to you looses arrows
	var arc_at := Vector2.ZERO
	for arc_side in [-1.0, 1.0]:
		for arc_dk in [90.0, 70.0, 110.0]:
			var ap: Vector2 = spot.call(arc_side * arc_dk, 9.5)
			if FoeAI.clear_line(g, ap - ap.normalized() * 5.0, g.player.pos):
				arc_at = ap
				break
		if arc_at != Vector2.ZERO:
			break
	if arc_at != Vector2.ZERO:
		var arc = g.spawn_enemy("archer", arc_at)
		var arrows := 0
		for fr3 in 260:
			for arc_pr in g.projs:
				if arc_pr["type"] == "arrow" and arc_pr["life"] == int(Defs.PROJ["arrow"]["life"]) - 1:
					arrows += 1
			await _frames(1)
		foe_lines.append("archer %.0f cells off: %d arrows" % [arc_at.distance_to(g.player.pos), arrows])
		foe_ok = foe_ok and arrows > 0
	else:
		foe_lines.append("archer: no clear line nearby (skipped)")
	g.enemies.clear()
	g.projs.clear()
	g.player.hp = g.max_hp
	# a bat above you hangs a moment, then dives
	var bat = g.spawn_enemy("bat", spot.call(30.0, 45.0))
	var dived := false
	for fr4 in 240:
		if bat.act == "dive":
			dived = true
			break
		await _frames(1)
	foe_lines.append("bat dived: %s" % dived)
	foe_ok = foe_ok and dived
	g.enemies.clear()
	# an imp you close in on vanishes and appears again some way off
	var imp = g.spawn_enemy("imp", spot.call(14.0, 22.0))
	var imp0: Vector2 = imp.pos
	var blinked := false
	for fr5 in 120:
		if imp.blink_cd > 0:
			blinked = true
			break
		await _frames(1)
	foe_lines.append("imp blinked away: %s (%.0f cells)" % [blinked, imp.pos.distance_to(imp0)])
	foe_ok = foe_ok and blinked
	g.enemies.clear()
	g.projs.clear()
	g.player.hp = g.max_hp
	_ok("foes wind up, then lunge, shoot, swoop or blink", foe_ok, "; ".join(foe_lines))

	# ---- a skeleton opens a door to get at you (a slime can't) ----
	var door_f := {}
	for dd in g.doors:
		if not bool(dd["open"]) and not dd.has("cells") and int(dd["row"]) < Defs.SH_Y0[1]:
			door_f = dd
			break
	if door_f.is_empty():
		_ok("a skeleton opens a door to get at you", false, "no shut door left")
	else:
		var dpf: Vector2 = door_f["pos"]
		var daf := atan2(dpf.y, dpf.x)
		var outw: Vector2 = g.basis_r(daf) * float(door_f["side"])
		var bottom: Vector2 = dpf + g.basis_d(daf) * (float(door_f["h"]) * 0.5)
		var up_f: Vector2 = -g.basis_d(daf)
		_go(bottom + up_f * 10.0 - outw * 24.0)
		await _frames(30)
		var sl = g.spawn_enemy("slime", bottom + up_f * 6.0 + outw * 22.0)
		sl.alert_t = 9999
		sl.seen_pos = g.player.pos
		await _frames(150)
		var slime_opened: bool = door_f["open"]
		g.enemies.clear()
		var sk2 = g.spawn_enemy("skeleton", bottom + up_f * 10.0 + outw * 26.0)
		var opened_t := -1
		for fr6 in 360:
			sk2.alert_t = 200
			sk2.seen_pos = g.player.pos
			if bool(door_f["open"]):
				opened_t = fr6
				break
			await _frames(1)
		_ok("a skeleton opens a door to get at you", opened_t >= 0 and not slime_opened,
			"a slime pushing at it for 2.5 s opened it: %s; the skeleton opened it after %d frames" % [slime_opened, opened_t])
		g.enemies.clear()
	g.enemies.append_array(keep_foes)

	# ---- foes come in from out of sight: none appears on screen ----
	var spv := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
	_go(spv * (g.gpu.surf_at(g.spawn_angle).x + 25.0))
	await _frames(40)
	var seen := 0
	var made := 0
	for depth_k in [0.0, 60.0]:
		if depth_k > 0.0:
			# and underground, in a cave
			_go(spv * (g.gpu.surf_at(g.spawn_angle).x - depth_k))
			await _frames(30)
		for k in 300:
			for e in g.enemies:
				if not e.boss:
					e.dead = true
			await _frames(1)
			g.spawn_timer = 0
			var before_n: int = g.enemies.size()
			g._try_spawn()
			if g.enemies.size() > before_n:
				made += 1
				var sp: Vector2 = g.world_to_screen(g.enemies[g.enemies.size() - 1].pos)
				if sp.x > -4 and sp.y > -4 and sp.x < g.VW + 4 and sp.y < g.VH + 4:
					seen += 1
	for e in g.enemies:
		if not e.boss:
			e.dead = true
	_ok("foes appear out of sight", made > 0 and seen == 0, "%d spawned, %d of them on screen" % [made, seen])

	# ---- a boss nobody is fighting recovers ----
	var boss_e = null
	for e in g.enemies:
		if e.boss:
			boss_e = e
	if boss_e != null:
		# a picture of Vulkhar in his arena (saves/shots/boss.png)
		var bup: Vector2 = (boss_e.pos as Vector2).normalized()
		_go(boss_e.pos + Vector2(-bup.y, bup.x) * 70.0)
		await _frames(60)
		g.ui.title.visible = false
		await _frames(2)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("boss.png"))
		# then leave him hurt and walk away
		var sp9 := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
		_go(sp9 * (g.gpu.surf_at(g.spawn_angle).x + 25.0))
		boss_e.hp = boss_e.max_hp * 0.3
		boss_e.awake = true
		await _frames(200)
		_ok("a boss left alone recovers to full health", boss_e.hp >= boss_e.max_hp and not boss_e.awake,
			"health %d of %d, %s" % [int(boss_e.hp), int(boss_e.max_hp), "asleep" if not boss_e.awake else "awake"])
	else:
		_ok("a boss left alone recovers to full health", false, "no boss in the world")
	# ---- the unrolled view keeps the cells around you one pixel wide at any depth ----
	var widths := []
	var view_ok := true
	for rr in [1300.0, 900.0, 500.0, 250.0, 120.0]:
		var st: float = g.unroll_step(rr)
		var cell_w: float = st * rr                  # world units per pixel across
		widths.append("%d: %.2f" % [int(rr), cell_w])
		view_ok = view_ok and cell_w > 0.45 and cell_w < 1.6
	_ok("the view isn't stretched deep down", view_ok, "world units per pixel across at radius " + ", ".join(widths))

	# ---- one-way platforms: land on one, drop through it (down + jump), jump up through it ----
	var pcol := int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 40
	var pg: int = b.ground_row(pcol)
	for pc2 in range(pcol - 16, pcol + 17):
		pg = mini(pg, b.ground_row(pc2))
	var prow := pg - 16
	_go(_cell_pos(pcol, pg - 40))
	await _frames(10)
	# a stone pillar from the ground up to the strip (conjuring places at most 9 cells a frame)
	var pil_g: int = maxi(b.ground_row(pcol + 14), b.ground_row(pcol + 15)) + 1
	for jr in range(pil_g, prow, -1):
		for dc2 in [13, 14, 15]:
			g.brushes.append([_cell_pos(pcol + dc2, jr), 0.6, 5, Defs.STONE, 0, 9, 0])
		await _frames(1)
	# from the pillar outward, so every new piece is already held by the last
	for k in range(15, -6, -1):
		g.brushes.append([_cell_pos(pcol + k, prow), 0.6, 5, Defs.SCAFFOLD, 0, 9, 0])
		g.brushes.append([_cell_pos(pcol + k, prow + 1), 0.6, 5, Defs.SCAFFOLD, 0, 9, 0])
		await _frames(1)
	await _frames(3)
	_go(_cell_pos(pcol, prow - 30))
	await _frames(80)
	var strip_n := 0
	for k in range(-5, 16):
		if g.type_at(_cell_pos(pcol + k, prow)) == Defs.SCAFFOLD:
			strip_n += 1
	var pillar_n := 0
	for jr2 in range(prow + 1, pil_g):
		if g.type_at(_cell_pos(pcol + 14, jr2)) == Defs.STONE:
			pillar_n += 1
	var landed: bool = g.player.on_platform
	var row_on := int(Defs.R_TOP - (g.player.pos.length() - g.player.h * 0.5))
	g.test_down = true
	g.test_jump = true
	await _frames(3)
	g.test_jump = false
	g.test_down = false
	await _frames(60)
	var row_down := int(Defs.R_TOP - (g.player.pos.length() - g.player.h * 0.5))
	var dropped: bool = row_down > prow + 4 and g.player.on_ground and not g.player.on_platform
	g.test_jump = true
	await _frames(3)
	g.test_jump = false
	await _frames(90)
	var back_up: bool = g.player.on_platform
	_ok("platforms: land on one, drop through it, jump up through it", landed and dropped and back_up,
		"strip at row %d (%d of 21 cells there, pillar %d of %d): stood at row %d (on it %s), after down + jump row %d (through %s), after a jump on it again %s" % [prow, strip_n, pillar_n, pil_g - prow - 1, row_on, landed, row_down, dropped, back_up])

	# ---- unsupported blocks fall, and falling rock hurts ----
	var sp := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
	var rs: float = g.gpu.surf_at(g.spawn_angle).x
	_go(sp * (rs + 30.0))
	await _frames(60)
	var up: Vector2 = g.player.pos.normalized()
	var side := Vector2(-up.y, up.x)
	var mid: Vector2 = g.player.pos + side * 30.0 + up * 26.0
	# the conjured stone, anywhere in the cells around the spot (the grid samples the world a
	# fraction of a cell off, so the blob's edge can land on either side of one cell)
	var stone_near := func() -> bool:
		for oj in [-1.0, 0.0, 1.0]:
			for oi in [-1.0, 0.0, 1.0]:
				if g.type_at(mid + side * oi + up * oj) == Defs.STONE:
					return true
		return false
	g.brushes.append([mid, 1.8, 5, Defs.STONE, 0, 9, 0])
	await _frames(2)
	var placed: bool = stone_near.call()
	# watch it frame by frame: it should creak while it is still in place, then drop
	var creaking := false
	var gone_at := -1
	var max_creak := 0
	for f in 120:
		await _frames(1)
		var here: bool = stone_near.call()
		max_creak = maxi(max_creak, g.gpu.counts[56])
		if here and g.gpu.counts[56] > 0:
			creaking = true
		if not here and gone_at < 0:
			gone_at = f
	var still: bool = stone_near.call()
	_ok("a loose block creaks first, then falls", placed and creaking and not still, "placed %s, creaked %s (max %d cells), left its spot at frame %d" % [placed, creaking, max_creak, gone_at])
	g.test_god = false
	g.hp = g.max_hp
	g.iframes = 0
	var hp0: float = g.hp
	g.brushes.append([g.player.pos + up * 40.0, 1.8, 5, Defs.STONE, 0, 8, 0])
	await _frames(150)
	_ok("falling rock hurts the mage", g.hp < hp0, "health %.0f -> %.0f" % [hp0, g.hp])
	# digging a pit right under your feet, again and again, costs nothing: you drop in with the rim
	_go(Vector2(cos(g.spawn_angle + 0.03), sin(g.spawn_angle + 0.03)) * (g.gpu.surf_at(g.spawn_angle + 0.03).x + 14.0))
	await _frames(60)
	g.hp = g.max_hp
	g.iframes = 0
	var hp1: float = g.hp
	for pk in 6:
		var upk: Vector2 = g.player.pos.normalized()
		g.brushes.append([g.player.pos - upk * 12.0, g.player.dig_r, 1, 0, g.player.tier, 0, 0, 0])
		await _frames(25)
	await _frames(60)
	_ok("digging a pit under yourself doesn't hurt", g.hp >= hp1, "health %.0f -> %.0f" % [hp1, g.hp])
	# ---- health doesn't come back by itself; a draught and Mending bring it back over a moment ----
	g.hp = 40.0
	g.player.heal_left = 0.0
	await _frames(120)
	var hp_idle: float = g.hp
	g.items["potion"] = 1
	g.player.potion_cd = 0
	var drank: bool = g._drink(g.player)
	await _frames(100)
	var hp_drunk: float = g.hp
	var again: bool = g._drink(g.player)             # none left (and too soon)
	g.hp = 40.0
	if not g.known.has("mend"):
		g.known.append("mend")
	g.mana = g.max_mana
	g.player.cast_cd = 0
	g._cast(g.player, "mend", g.player.pos)
	var mana_after: float = g.mana
	await _frames(90)
	var hp_mended: float = g.hp
	g.known.erase("mend")
	_ok("health only comes back from a draught or Mending", hp_idle == 40.0 and drank and absf(hp_drunk - 40.0 - Defs.POTION_HEAL) < 1.0 and not again and int(g.items.get("potion", 0)) == 0 and absf(hp_mended - 40.0 - Defs.MEND_HEAL) < 1.0 and mana_after < g.max_mana - 50.0,
		"idle 2 s: %.1f; drank %s: %.1f; another: %s; Mending: %.1f (mana %.0f of %.0f)" % [hp_idle, drank, hp_drunk, again, hp_mended, mana_after, g.max_mana])
	g.hp = g.max_hp
	g.test_god = true
	g.hp = g.max_hp

	# ---- co-op groundwork: a second mage far away gets its own simulation, collisions and loot ----
	# somewhere far away on open ground (not on a building, where it would stand on the roof)
	var a2: float = g.spawn_angle + 0.6
	for k in 40:
		var at: float = g.spawn_angle + 0.6 + k * 0.03
		var probe: Vector2 = Vector2(cos(at), sin(at)) * (g.gpu.surf_at(at).x + 10.0)
		var clear := true
		for dk in [-60.0, 0.0, 60.0]:
			var q: Vector2 = Vector2(cos(at + dk / Defs.RS0), sin(at + dk / Defs.RS0)) * probe.length()
			if b.label_at(q) != "":
				clear = false
		if clear:
			a2 = at
			break
	var rs2: float = g.gpu.surf_at(a2).x
	var m2 = g.add_mage()
	m2.pos = Vector2(cos(a2), sin(a2)) * (rs2 + 25.0)
	await _frames(120)
	var h2: float = m2.pos.length() - rs2
	_ok("a second mage far away stands on its own ground", m2.on_ground and h2 > -3.0 and h2 < 20.0, "%.1f cells above the surface" % h2)
	var up2: Vector2 = m2.pos.normalized()
	var sp2: Vector2 = m2.pos + up2 * 22.0 + Vector2(-up2.y, up2.x) * 15.0
	g.brushes.append([sp2, 1.8, 5, Defs.STONE, 0, 9, 0, 1])
	await _frames(2)
	g._use_grid(m2)
	var placed2: bool = g.type_at(sp2) == Defs.STONE
	g._use_grid(g.player)
	await _frames(120)
	g._use_grid(m2)
	var still2: bool = g.type_at(sp2) == Defs.STONE
	g._use_grid(g.player)
	_ok("the far mage's area is simulated too", placed2 and not still2, "placed %s, still there after 1 s %s" % [placed2, still2])
	var mine0 := 0
	for k in Defs.NM:
		mine0 += g.player.inv[k]
	var theirs0 := 0
	for k in Defs.NM:
		theirs0 += m2.inv[k]
	for f in 12:
		g.brushes.append([m2.pos - up2 * 10.0, 4.5, 1, 0, 1, 0, 0, 1])
		await _frames(1)
	await _frames(2)
	var mine1 := 0
	for k in Defs.NM:
		mine1 += g.player.inv[k]
	var theirs1 := 0
	for k in Defs.NM:
		theirs1 += m2.inv[k]
	_ok("what a mage digs goes to that mage's satchel", theirs1 > theirs0 and mine1 == mine0, "theirs %d -> %d, yours %d -> %d" % [theirs0, theirs1, mine0, mine1])
	g.players.erase(m2)
	await _frames(2)

	# ---- performance ----
	g.perf_us = 0
	g.perf_n = 0
	var tf := Time.get_ticks_usec()
	await _frames(240)
	var wall := float(Time.get_ticks_usec() - tf) / 240.0 / 1000.0
	_ok("holds 60 fps at the surface", wall < 18.5, "%.1f ms per frame, game %.1f ms, waiting for the GPU %.1f ms" % [wall, g.perf_cpu_ms, g.perf_wait_ms])
	# the same with no frame cap: how much room there is, and where the time goes
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _frames(30)
	g.prof_reset()
	worst_us = 0
	g.hitch_us = 0
	var tu0 := Time.get_ticks_usec()
	await _frames(300)
	var uncapped := float(Time.get_ticks_usec() - tu0) / 300.0 / 1000.0
	var ptxt: String = g.prof_text(14, "; ")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	_ok("frame time with no cap", uncapped < 16.7, "%.2f ms a frame (%.0f fps), longest %.1f ms (the game's own %.1f); average ms (peak): %s" % [uncapped, 1000.0 / uncapped, worst_us / 1000.0, g.hitch_us / 1000.0, ptxt])
	# ---- the world keeps its pace when frames are slow (a laptop on battery) ----
	var t_before: float = g.time
	Engine.max_fps = 30
	var tw := Time.get_ticks_usec()
	await _frames(60)
	var secs := float(Time.get_ticks_usec() - tw) / 1000000.0
	Engine.max_fps = 60
	var rate: float = (g.time - t_before) / maxf(secs, 0.001)
	_ok("the game keeps full speed at 30 fps", absf(rate - 60.0) < 8.0, "%.1f ticks per second over %.1f s at 30 fps" % [rate, secs])

	# ---- the Wisp Forge lists its recipes and crafts ----
	g.ui.show_forge()
	await _frames(2)
	var cards := 0
	for c in g.ui.forge_list.get_children():
		if c is GridContainer:
			cards += c.get_child_count()
	g.ui.hide_forge()
	var wide: Dictionary = {}
	for r in g.recipes:
		if r["id"] == "wide":
			wide = r
	var crafted := false
	if not wide.is_empty():
		g.dig_r = 7.5
		for k in wide["cost"]:
			g.player.inv[int(k)] += int(wide["cost"][k])
		crafted = g.craft(wide) and g.dig_r >= 11.0
	_ok("the Wisp Forge lists recipes and crafts", cards == g.recipes.size() and crafted, "%d of %d recipe cards, crafting %s" % [cards, g.recipes.size(), "works" if crafted else "failed"])

	# ---- a building left hanging comes down as a whole once you dig at any part of it ----
	# (a stone box with a plank back wall, stamped in the air the way the generator stamps buildings:
	# anchored and built; digging at one corner must wake all of it, and with nothing under it, it falls)
	var hang_a: float = g.spawn_angle + 0.09
	var hang_s: float = g.gpu.surf_at(hang_a).x
	var hang_c: Vector2i = Build.cell_of(Vector2(cos(hang_a), sin(hang_a)) * (hang_s + 130.0))   # above the treetops
	var HW := 30
	var hd := PackedInt32Array()
	hd.resize(HW * HW)
	for hj in HW:
		for hi in HW:
			var edge := mini(mini(hi, HW - 1 - hi), mini(hj, HW - 1 - hj)) < 3
			hd[hj * HW + hi] = (Defs.MASONRY if edge else 0) | (Defs.PLANK << 8) | 0x40000 | 0x20000
	g.stamps.append({"x0": hang_c.x, "y0": hang_c.y, "w": HW, "h": HW, "data": hd})
	_go(Vector2(cos(hang_a + 0.04), sin(hang_a + 0.04)) * (hang_s + 14.0))
	await _frames(60)
	var hang_tally := func() -> Array:
		var rr: Dictionary = g.gpu.read_rect(hang_c.x, hang_c.y, HW, HW)
		var nf := 0
		var anch := 0
		for v in rr["fg"]:
			if (v & 255) == Defs.MASONRY:
				nf += 1
				if (v & 0x40000000) != 0:
					anch += 1
		var nb := 0
		for v in rr["bg"]:
			if (v & 255) == Defs.PLANK:
				nb += 1
		var st_lo := 99
		var st_hi := -1
		var life := 0
		var n_still := 0
		var near := {}
		var fgs: PackedInt32Array = rr["fg"]
		for k in fgs.size():
			var v: int = fgs[k]
			if (v & 255) == Defs.MASONRY:
				st_lo = mini(st_lo, (v >> 24) & 63)
				st_hi = maxi(st_hi, (v >> 24) & 63)
				if ((v >> 16) & 255) > 0:
					life += 1
				else:
					n_still += 1
			elif (v & 255) != 0:
				var nm: String = Defs.NAMES[v & 255]
				near[nm] = int(near.get(nm, 0)) + 1
		return [nf, anch, nb, "support %d-%d, %d moving or creaking, inside also %s" % [st_lo, st_hi, life, str(near)], n_still]
	var hang0: Array = hang_tally.call()
	await _frames(120)
	var hang_still: Array = hang_tally.call()     # left alone, it stays as built
	hang_still.resize(3)
	g.brushes.append([_cell_pos(hang_c.x + 1, hang_c.y + 1), 3.0, 1, 0, 9, 0, 0, 0])
	var hang_chunks := 0
	var hang_shot := false
	g.hitch_us = 0
	g.prof_reset()
	for hang_k in 560:
		hang_chunks = maxi(hang_chunks, g.chunks.list.size())
		if not hang_shot and g.chunks.list.size() > 3 and hang_k > 60:
			hang_shot = true
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("collapse.png"))
		await _frames(1)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("hanging.png"))
	var hang1: Array = hang_tally.call()
	hang0.resize(3)
	# it came down in pieces that stayed stone, not in a shower of gravel
	var gr_h: int = b.ground_row(hang_c.x + HW / 2)
	var hang_wide: Dictionary = g.gpu.read_rect(hang_c.x - 90, hang_c.y, HW + 180, gr_h - hang_c.y + 8)
	var n_mas := 0
	var n_grav := 0
	for v in hang_wide["fg"]:
		if (v & 255) == Defs.MASONRY:
			n_mas += 1
		elif (v & 255) == Defs.GRAVEL:
			n_grav += 1
	_ok("a collapsing building falls in pieces, not to dust", hang_chunks >= 3 and n_mas > int(hang0[0]) / 2,
		"%d pieces at once; afterwards %d stone blocks and %d gravel (it had %d stone); the game's longest frame %.1f ms (%s, %s, %s)" % [hang_chunks, n_mas, n_grav, hang0[0], g.hitch_us / 1000.0, _peak("lifting pieces out"), _peak("falling pieces"), _peak("read back")])
	_ok("a building left hanging comes down once you dig at any part of it", int(hang0[0]) > 250 and hang_still == hang0 and int(hang1[1]) == 0 and int(hang1[4]) < int(hang0[0]) / 3 and int(hang1[2]) < int(hang0[2]) / 5,
		"stone %d (anchored %d), back wall %d; left alone 2 s: %s; 9 s after digging one corner: stone %d (anchored %d), back wall %d; %s" % [hang0[0], hang0[1], hang0[2], str(hang_still), hang1[0], hang1[1], hang1[2], hang1[3]])

	# ---- the orbit band: cells above the air that can be built into, and vacuum ----
	var ob_ang: float = atan2(g.player.pos.y, g.player.pos.x) + 0.05
	var ob_up := Vector2(cos(ob_ang), sin(ob_ang))
	g.time = fposmod(ob_ang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
	# (alive and well: a mage killed by an earlier test isn't updated, breath included)
	g.player.dead = false
	g.player.hp = g.player.max_hp
	g.test_god = true
	_go(ob_up * (Defs.R_TOP + 70.0))
	await _frames(10)
	# a stone ledge stamped into the band (a blueprint is laid out in surface columns; up there each of
	# its cells covers two), a patch of fire beside it
	var ob_c: Vector2i = Build.cell_of(ob_up * (Defs.R_TOP + 40.0))
	var ob_led := PackedInt32Array()
	ob_led.resize(24 * 3)
	ob_led.fill(Defs.STONE | 0xFF00 | 0x20000)        # anchored stone, background left alone
	g.stamps.append({"x0": ob_c.x - 12, "y0": ob_c.y, "w": 24, "h": 3, "data": ob_led})
	var ob_fire := PackedInt32Array()
	ob_fire.resize(16)
	ob_fire.fill(Defs.FIRE | 0xFF00)
	g.stamps.append({"x0": ob_c.x + 16, "y0": ob_c.y - 6, "w": 4, "h": 4, "data": ob_fire})
	await _frames(3)
	var ob_rr: Dictionary = g.gpu.read_rect(ob_c.x - 12, ob_c.y, 24, 3)
	var ob_stone := 0
	for v in ob_rr["fg"]:
		if (v & 255) == Defs.STONE:
			ob_stone += 1
	var ob_raw: PackedByteArray = g.gpu.read_world()
	var ob_fires := 0
	for v2 in g.gpu.read_rect(ob_c.x + 14, ob_c.y - 8, 8, 8)["fg"]:
		if (v2 & 255) == Defs.FIRE:
			ob_fires += 1
	# water poured on the ledge freezes; sand dropped beside it falls out of the band into the air below
	g.brushes.append([ob_up * (Defs.R_TOP + 47.0), 2.5, 5, Defs.WATER, 0, 18, 0])
	var ob_side: Vector2 = Vector2(-ob_up.y, ob_up.x)
	await _frames(2)          # (conjuring brushes in one frame share one count of cells placed)
	g.brushes.append([ob_up * (Defs.R_TOP + 24.0) + ob_side * 30.0, 2.0, 5, Defs.SAND, 0, 12, 0])
	g.player.inv[Defs.SAND] += 60
	g.player.inv[Defs.WATER] += 60
	var ob_inv0: int = g.player.inv[Defs.SAND]
	var ob_b0: float = g.player.breath
	var ob_st := "%s, dead %s" % [g.state, g.player.dead]
	var ob_f0: int = g.frame
	for obk in 90:
		_go(ob_up * (Defs.R_TOP + 70.0))
		await _frames(1)
	var ob_b1: float = g.player.breath
	ob_st += ", %d ticks, at radius %.0f; sand in the satchel %d -> %d" % [g.frame - ob_f0, g.player.pos.length(), ob_inv0, g.player.inv[Defs.SAND]]
	var ob_above: Dictionary = g.gpu.read_rect(ob_c.x - 14, ob_c.y - 10, 28, 10)
	var ob_m := {}
	for v3 in ob_above["fg"]:
		var nm3: String = Defs.NAMES[v3 & 255]
		ob_m[nm3] = int(ob_m.get(nm3, 0)) + 1
	var ob_sc: Vector2i = Build.cell_of(ob_up * (Defs.R_TOP + 24.0) + ob_side * 30.0)
	var ob_sand_up := 0
	for v4 in g.gpu.read_rect(ob_sc.x - 16, -Defs.ORBIT_ROWS, 32, Defs.ORBIT_ROWS)["fg"]:
		if (v4 & 255) == Defs.SAND:
			ob_sand_up += 1
	var ob_sand_air := 0
	for v5 in g.gpu.read_rect(ob_sc.x - 20, 0, 40, 520)["fg"]:
		if (v5 & 255) == Defs.SAND:
			ob_sand_air += 1
	var ob_fires2 := 0
	for v6 in g.gpu.read_rect(ob_c.x + 14, ob_c.y - 8, 8, 8)["fg"]:
		if (v6 & 255) == Defs.FIRE:
			ob_fires2 += 1
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("orbit.png"))
	_ok("the orbit band above the air takes building", ob_stone == 72 and ob_raw.size() == Defs.total_cells() * 8,
		"ledge %d of 72 stone cells at row %d (radius %.0f, the air ends at %.0f); %d shells, the band %d columns" % [ob_stone, ob_c.y, Defs.R_TOP - ob_c.y, Defs.R_TOP, Defs.NSH, Defs.SH_N[Defs.ORB]])
	_ok("vacuum: water freezes, fire goes out, sand falls out of the band, you hold your breath",
		int(ob_m.get("Ice", 0)) > 0 and int(ob_m.get("Water", 0)) == 0 and ob_fires2 == 0 and ob_sand_up == 0 and ob_sand_air > 0 and ob_b1 < ob_b0,
		"above the ledge %s; fire %d -> %d; sand left up there %d, fallen into the air %d; breath %.0f -> %.0f (%s)" % [str(ob_m), ob_fires, ob_fires2, ob_sand_up, ob_sand_air, ob_b0, ob_b1, ob_st])
	g.player.breath = g.player.max_breath
	g.chunks.clear()

	# ---- save and load give back the same world ----
	# (pieces still tumbling are set down first: saving would set them down anyway)
	g.chunks.settle_all()
	if not g.stamps.is_empty():
		g.gpu.stamp(g.stamps, g.frame)
		g.stamps.clear()
	var a: PackedByteArray = g.gpu.read_world()
	g.save_world(true)
	var loaded: bool = g._load_world(0)
	var bb: PackedByteArray = g.gpu.read_world()
	_ok("saving and loading the world round-trips", loaded and _sha(a) == _sha(bb), "%.1f MB raw" % (a.size() / 1048576.0))

	# ---- space: up out of the orbit band, the planet shown as its picture, the staff jet, and back ----
	var sx_ang: float = atan2(g.player.pos.y, g.player.pos.x)
	var sx_up := Vector2(cos(sx_ang), sin(sx_ang))
	g.player.dead = false
	g.test_god = true
	g.time = fposmod(sx_ang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
	_go(sx_up * (Defs.R_SPACE - 40.0))
	g.test_jump = true
	var sx_in := -1
	for sxk in 240:
		g.player.mana = g.player.max_mana
		await _frames(1)
		if g.space.active:
			sx_in = sxk
			break
	g.test_jump = false
	var sx_pic: bool = not g.space.pictures.get(int(g.planet["index"]), {}).is_empty()
	# jet outward: the view zooms out, the picture takes over and the GPU rests
	g.test_cast = true
	var sx_gf0: int = g.gpu.frame
	var sx_off := -1
	for sxk2 in 260:
		g.test_aim = g.player.pos * 2.0
		g.player.mana = g.player.max_mana
		await _frames(1)
		if not g.space.live and sx_off < 0:
			sx_off = sxk2
			sx_gf0 = g.gpu.frame
	g.test_cast = false
	var sx_far: float = g.player.pos.length() - Defs.R_SPACE
	var sx_gf1: int = g.gpu.frame
	var sx_zoom: float = g.zoom
	await _frames(3)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("space.png"))
	# and back: aim at the planet until you're in the orbit band again
	g.test_cast = true
	var sx_back := -1
	for sxk3 in 1800:
		g.test_aim = g.player.pos * 0.5
		g.player.mana = g.player.max_mana
		await _frames(1)
		if not g.space.active:
			sx_back = sxk3
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	var sx_gf2: int = g.gpu.frame
	await _frames(150)
	var sx_r: float = g.player.pos.length()
	_ok("you fly out into space and back down without a loading screen",
		sx_in >= 0 and sx_pic and sx_off >= 0 and sx_gf1 == sx_gf0 and sx_far > 800.0 and sx_back >= 0 and g.gpu.frame > sx_gf2 + 60 and absf(g.zoom - float(g.zoom_levels[g.zoom_i])) < 0.05 and sx_r < Defs.R_SPACE,
		"out after %d ticks of levitating (picture taken: %s); the picture took over after %d ticks of the jet (GPU frames while it showed: %d); %.0f past the orbit band at zoom %.1f; back in the band after %d ticks; then the planet ran again (%d GPU frames in 150 ticks), zoom %.2f, you at radius %.0f" % [sx_in, sx_pic, sx_off, sx_gf1 - sx_gf0, sx_far, sx_zoom, sx_back, g.gpu.frame - sx_gf2, g.zoom, sx_r])

	# ---- the Wisp Skiff: forged, called, boarded, flown up into space and back, landed, left ----
	g.player.dead = false
	g.test_god = true
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	var sf_rec: Dictionary = {}
	for sf_r in g.recipes:
		if sf_r["id"] == "skiff":
			sf_rec = sf_r
	for sf_k in sf_rec.get("cost", {}):
		g.player.inv[int(sf_k)] += int(sf_rec["cost"][sf_k])
	var sf_forged: bool = not sf_rec.is_empty() and g.craft(sf_rec) and g.items.has("skiff")
	var sf_ang: float = g.spawn_angle + 0.03
	_go(Vector2(cos(sf_ang), sin(sf_ang)) * (g.gpu.surf_at(sf_ang).x + 12.0))
	g.time = fposmod(sf_ang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
	await _frames(40)
	var sf_called: bool = g.call_skiff()
	var sf_sk = g.skiff
	var sf_settle := -1
	for sfk1 in 300:
		await _frames(1)
		if sf_sk.grounded and sf_sk.vel.length() < 0.5:
			sf_settle = sfk1
			break
	var sf_rest: Vector2 = sf_sk.pos
	await _frames(40)
	var sf_drift: float = sf_sk.pos.distance_to(sf_rest)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("skiff.png"))
	# aboard
	g.player.pos = sf_sk.pos
	var sf_board: bool = g._skiff_interact(g.player) and g.player.aboard == sf_sk
	# up, holding cast with the cursor straight overhead, until out in space
	var sf_r0: float = sf_sk.pos.length()
	g.test_cast = true
	var sf_up := -1
	var sf_shot := false
	var sf_scale := []
	for sfk2 in 1500:
		# (a little to one side at first, so it climbs at a slant)
		g.test_aim = sf_sk.pos * 1.5 + g.basis_r(atan2(sf_sk.pos.y, sf_sk.pos.x)) * (300.0 if sfk2 < 120 else 0.0)
		await _frames(1)
		if not sf_shot and sf_sk.pos.length() > sf_r0 + 120.0:
			sf_shot = true
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("skiff_climb.png"))
		# drawn one cell to a pixel at every height (the ground's columns widen with height; the ship mustn't)
		if sfk2 % 40 == 0 and not g.space.active:
			sf_scale.append(snappedf(g.overlay._skiff_xf(sf_sk).x.length() * g.zoom, 0.01))
		if g.space.active:
			sf_up = sfk2
			break
	await _frames(90)
	var sf_far: float = sf_sk.pos.length() - Defs.R_SPACE
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("skiff_space.png"))
	# back: cursor on the planet until in the orbit band again, then let go and come down
	var sf_back := -1
	for sfk3 in 1500:
		g.test_aim = sf_sk.pos * 0.3
		await _frames(1)
		if not g.space.active:
			sf_back = sfk3
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	var sf_land := -1
	var sf_vmax := 0.0
	for sfk4 in 1800:
		await _frames(1)
		if sf_sk.pos.length() < Defs.R_TOP:
			sf_vmax = maxf(sf_vmax, sf_sk.vel.length())
		if sf_sk.grounded and sf_sk.vel.length() < 0.5:
			sf_land = sfk4
			break
	var sf_la: float = atan2(sf_sk.pos.y, sf_sk.pos.x)
	var sf_above: float = sf_sk.pos.length() - g.gpu.surf_at(sf_la).x
	var sf_with: bool = g.player.aboard == sf_sk and g.player.pos.distance_to(sf_sk.pos) < 30.0
	await _frames(20)
	var sf_out: bool = g._skiff_interact(g.player) and g.player.aboard == null
	await _frames(30)
	_ok("the Wisp Skiff: forged, called, boarded, flown into space and back, landed and left",
		sf_forged and sf_called and sf_settle >= 0 and sf_drift < 1.5 and sf_board and sf_up >= 0 and sf_back >= 0 and sf_land >= 0 and sf_with and sf_out and absf(sf_above) < 200.0 and sf_vmax < 9.0 and sf_land > 90 and sf_scale.min() > 0.99 and sf_scale.max() < 1.01,
		"forged %s, called %s (%d x %d cells, %.0f mass); settled after %d ticks (then moved %.1f); aboard %s; out in space after %d ticks of flying up (from radius %.0f), %.0f past the band after 1.5 s more; back in the band after %d ticks; landed %d ticks later (fastest through the air %.1f a tick), %.0f above the ground line, you still aboard %s; stepped out %s; drawn cells per pixel while climbing %s" % [sf_forged, sf_called, sf_sk.w, sf_sk.h, sf_sk.mass, sf_settle, sf_drift, sf_board, sf_up, sf_r0, sf_far, sf_back, sf_land, sf_vmax, sf_above, sf_with, sf_out, str(sf_scale)])

	# ---- a planet of another size: Fenhollow is laid out and generated to fit ----
	var sp_t := Time.get_ticks_msec()
	g._enter_planet(4)
	var sp_ms := Time.get_ticks_msec() - sp_t
	await _frames(60)
	var sp_a: float = atan2(g.player.pos.y, g.player.pos.x)
	var sp_off: float = g.player.pos.length() - g.gpu.surf_at(sp_a).x
	_ok("a planet of another size is laid out and generated to fit", absf(Defs.RS0 - float(g.planet["radius"])) < 0.5 and Defs.RS0 < 1304.0 and int(Defs.NS) < 8192 and absf(sp_off) < 40.0 and g.builds.infos.size() >= 5,
		"%s: radius %.0f, %d surface columns, %d shells (%.1f M cells); generated in %d ms; you stand %.1f from the surface; %d structures" % [g.planet["name"], Defs.RS0, Defs.NS, Defs.NSH, Defs.total_cells() / 1000000.0, sp_ms, sp_off, g.builds.infos.size()])
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("small_planet.png"))

	lines.append("")
	lines.append("%d passed, %d failed, %.1f s" % [passed, failed, (Time.get_ticks_msec() - t_all) / 1000.0])
	var txt := "\n".join(lines)
	print(txt)
	var f := FileAccess.open(g._real_save_dir().path_join("test_report.txt"), FileAccess.WRITE)
	if f:
		f.store_string(txt + "\n")
		f.close()
	g._delete_worlds()
	g.get_tree().quit(0 if failed == 0 else 1)

func _sha(d: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(d)
	return h.finish().hex_encode()
