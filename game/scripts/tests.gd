extends "res://scripts/tests/perf.gd"
## Automated checks. "Run tests.bat" starts the game with --test: it builds a fresh planet in
## saves/test (your real saves are untouched), plays it for a while, checks that the important
## things still work, writes saves/test_report.txt and quits.
##
## The checks are split over a chain of scripts in scripts/tests/, each extending the one before, so
## every check and helper lives on this one object: base.gd (shared state and helpers), creatures,
## world, building, towns, player, space, exotic, perf, then this file with run(), which runs them
## in order (and the checks written straight into it). A file may only call into files before it.

func run() -> void:
	var t_all := Time.get_ticks_msec()
	g.test_calm = true          # (the guardians sleep through the checks that aren't about them)
	g.test_no_wild = true       # (and no wild creature wanders into checks that aren't about them)
	lines.append("Wisp Forge test report  %s" % Time.get_datetime_string_from_system())
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("")
	g.test_god = true
	g.free_magic = true         # (digging and building cost no mana, but in the check about it)

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
	g.items["levitate"] = true        # (forged in a real game: the checks fly as they always have)
	g.items["drive"] = true           # (the skiff is built round a Core Drive: the checks forge skiffs as they always have)
	g.free_fuel = true                # (the Starsail and journeys burn no Wisp Cells, but in _test_fuel)
	g.learn_all()                     # (every recipe known: learning them is _test_recipes's)
	var t0 := Time.get_ticks_msec()
	g._enter_planet(0)
	var gen_ms := Time.get_ticks_msec() - t0
	g.ui.show_hud()
	g.state = "play"
	var b = g.builds
	start_pos = g.player.pos
	await _trace_frames("startup", 300)
	# (saves/test_only.txt naming a section runs just that one, to try a change quickly)
	# (an empty file runs everything)
	var only_f: String = g._real_save_dir().path_join("test_only.txt")
	var only := FileAccess.get_file_as_string(only_f).strip_edges() if FileAccess.file_exists(only_f) else ""
	if only != "":
		only_now = only
		g.ui.title.visible = false      # (the full run puts the title away in its early checks)
		if only == "climb":
			_go(g.player.pos)
			await _frames(60)
			await _test_climb()
		elif only == "nav":
			_go(g.player.pos)
			await _frames(60)
			await _test_nav()
		elif only == "pursuit":
			_go(g.player.pos)
			await _frames(60)
			await _test_pursuit()
		elif only == "guardians":
			_go(g.player.pos)
			await _frames(60)
			await _test_guardians()
		elif only == "hearts":
			_go(g.player.pos)
			await _frames(60)
			await _test_hearts()
		elif only == "stairs":
			_go(g.player.pos)
			await _frames(60)
			await _test_stairs()
		elif only == "crafting":
			_go(g.player.pos)
			await _frames(60)
			await _test_crafting()
		elif only == "workshops":
			_go(g.player.pos)
			await _frames(60)
			await _test_workshops()
		elif only == "remove":
			_go(g.player.pos)
			await _frames(60)
			await _test_remove()
		elif only == "harvest":
			_go(g.player.pos)
			await _frames(60)
			await _test_harvest()
		elif only == "hand":
			_go(g.player.pos)
			await _frames(60)
			await _test_hand()
		elif only == "audio":
			_go(g.player.pos)
			await _frames(60)
			await _test_audio()
		elif only == "inworld":
			_go(g.player.pos)
			await _frames(60)
			await _test_inworld()
		elif only == "backdrop":
			await _test_backdrop()
		elif only == "indoors":
			await _test_indoors()
		elif only == "newgame":
			await _test_newgame()
		elif only == "spawns":
			_go(g.player.pos)
			await _frames(60)
			await _test_spawns()
		elif only == "wrecks":
			_go(g.player.pos)
			await _frames(60)
			await _test_wrecks()
		elif only == "pirates":
			_go(g.player.pos)
			await _frames(60)
			await _test_pirates()
		elif only == "outposts":
			_go(g.player.pos)
			await _frames(60)
			await _test_outposts()
		elif only == "stations":
			_go(g.player.pos)
			await _frames(60)
			await _test_stations()
		elif only == "fuel":
			_go(g.player.pos)
			await _frames(60)
			await _test_fuel()
		elif only == "ships" or only == "shipyard" or only == "pocket":
			_go(g.player.pos)
			await _frames(60)
			await _test_ships()
		elif only == "cargo":
			await _test_cargo()
		elif only == "voidlife":
			_go(g.player.pos)
			await _frames(60)
			await _test_voidlife()
		elif only == "minimap":
			_go(g.player.pos)
			await _frames(60)
			await _test_minimap()
		elif only == "spacebench":
			_go(g.player.pos)
			await _frames(60)
			await _test_spacebench()
		elif only == "galaxy":
			_go(g.player.pos)
			await _frames(60)
			await _test_galaxy()
		elif only == "wardens":
			_go(g.player.pos)
			await _frames(60)
			await _test_wardens()
		elif only == "biomes":
			await _test_far_biomes()
		elif only == "abyss":
			await _test_abyss()
		elif only == "giant":
			await _test_giant()
		elif only == "star":
			await _test_star()
		elif only == "void":
			await _test_void()
		elif only == "newbiomes":
			await _test_newbiomes()
		elif only == "cores":
			_go(g.player.pos)
			await _frames(60)
			await _test_cores()
		elif only == "worlds":
			await _test_worlds()
		elif only == "stampdiag":
			await _test_stampdiag()
		elif only == "creatures":
			_go(g.player.pos)
			await _frames(60)
			await _test_creatures()
		elif only == "ecology":
			_go(g.player.pos)
			await _frames(60)
			await _test_ecology()
		elif only == "fog":
			_go(g.player.pos)
			await _frames(60)
			await _test_fog()
		elif only == "sky":
			_go(g.player.pos)
			await _frames(60)
			await _test_sky()
		elif only == "gear":
			_go(g.player.pos)
			await _frames(60)
			await _test_gear()
		elif only == "towns":
			_go(g.player.pos)
			await _frames(60)
			await _test_towns()
		elif only == "vfx":
			_go(g.player.pos)
			await _frames(60)
			await _test_vfx()
		elif only == "start":
			_go(g.player.pos)
			await _frames(60)
			await _test_start()
		elif only == "quest":
			_go(g.player.pos)
			await _frames(60)
			await _test_quest()
		elif only == "bench":
			_go(g.player.pos)
			await _frames(60)
			await _test_bench()
		elif only == "recipes":
			_go(g.player.pos)
			await _frames(60)
			await _test_recipes()
		elif only == "hazards":
			# (where the full run tries it: the open ground beside the frozen basin)
			var hzo_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 160, 80, 60, 4, 30)
			var hzo_a: float = (float(hzo_st.x) + 66.5) / float(Defs.NS) * TAU
			_go(Vector2(cos(hzo_a), sin(hzo_a)) * (g.gpu.surf_at(hzo_a).x + 12.0))
			await _frames(60)
			await _test_hazards()
		elif only == "ui" or only == "speech":
			_go(g.player.pos)
			await _frames(60)
			if only == "ui":
				await _test_ui()
			await _test_speech()
		elif only == "mines":
			for mi_info in g.builds.infos:
				if mi_info["meta"].has("mine") and int(mi_info.get("unsound", 0)) > 0:
					print("[mines] %s unsound %d cuts %s at %s" % [str(mi_info["meta"]["mine"]), mi_info["unsound"], str(mi_info["meta"].get("cuts", {})), str(mi_info["meta"].get("cut_at", []))])
		lines.append("")
		lines.append("%d passed, %d failed, %.1f s (only %s)" % [passed, failed, (Time.get_ticks_msec() - t_all) / 1000.0, only])
		var only_txt := "\n".join(lines)
		print(only_txt)
		var only_rf := FileAccess.open(g._real_save_dir().path_join("test_report.txt"), FileAccess.WRITE)
		if only_rf:
			only_rf.store_string(only_txt + "\n")
			only_rf.close()
		g._delete_worlds()
		g.get_tree().quit(0 if failed == 0 else 1)
		return
	_ok("planet generates", g.planet.size() > 0, "%d ms including structures and settling" % gen_ms)
	_ok("structures are placed", b.infos.size() >= 15, "%d structures, %d labels" % [b.infos.size(), b.labels.size()])
	# ---- a building is the same at any depth: it goes in cell for cell in every shell, centred on
	# its anchor, so its width never changes and its sides stay straight across a seam ----
	var an_rng := RandomNumberGenerator.new()
	an_rng.seed = 77
	var an_jog := {24: 0.0, 48: 0.0, 96: 0.0}       # the biggest step of a side at a seam, in cells
	var an_where := ""
	for an_s in Defs.NSH - 1:
		var an_rs: float = Defs.R_TOP - float(Defs.SH_Y1[an_s])     # the seam's radius
		if an_rs < 320.0:
			break
		var an_no: int = Defs.SH_N[an_s]
		var an_ni: int = Defs.SH_N[an_s + 1]
		for an_t in 6:
			var an_ax := an_rng.randi_range(0, Defs.NS - 1)
			for an_w in an_jog.keys():
				var an_lo: int = Defs.stamp_left(an_no, an_ax, an_w)
				var an_li: int = Defs.stamp_left(an_ni, an_ax, an_w)
				var an_cell := TAU * an_rs / float(an_ni)
				# the left and right sides' places along the seam, above it and below it
				var an_dl := wrapf(float(an_lo) / an_no - float(an_li) / an_ni, -0.5, 0.5) * TAU * an_rs / an_cell
				var an_dr := wrapf(float(an_lo + an_w) / an_no - float(an_li + an_w) / an_ni, -0.5, 0.5) * TAU * an_rs / an_cell
				var an_m := maxf(absf(an_dl), absf(an_dr))
				if an_m > float(an_jog[an_w]):
					an_jog[an_w] = an_m
					if an_w == 48:
						an_where = "seam at row %d (%d / %d columns)" % [Defs.SH_Y1[an_s], an_no, an_ni]
	# (the cells either side of a seam never line up, so a side can step up to a cell, plus how much
	# narrower half the building's cells are below it: a ~2% seam)
	_ok("a building's sides stay straight across every seam (within about a cell)", float(an_jog[24]) <= 1.35 and float(an_jog[48]) <= 1.75,
		"a side steps at most %.2f cells for a building 24 wide, %.2f for 48 (%s), %.2f for 96" % [an_jog[24], an_jog[48], an_where, an_jog[96]])
	# stamped deep, through several seams, it reads back exactly as it was written, cell for cell
	var an_c := int(fposmod(g.spawn_angle + 1.3, TAU) / TAU * Defs.NS)
	var an_y0: int = int(Defs.SH_Y1[Defs.SURF]) + 60
	var an_w2 := 40
	var an_h2 := 140
	var an_bp := PackedInt32Array()
	for an_j in an_h2:
		for an_i in an_w2:
			var an_mt := 0
			if an_i < 3 or an_i >= an_w2 - 3 or an_j < 3 or an_j >= an_h2 - 3 or (an_i * 7 + an_j * 3) % 11 == 0:
				an_mt = Defs.BRICK
			an_bp.append(an_mt)
	g.gpu.stamp([{"x0": an_c, "y0": an_y0, "w": an_w2, "h": an_h2, "data": an_bp, "ax": an_c, "aw": an_w2}], 5)
	var an_rr: Dictionary = g.gpu.read_rect(an_c, an_y0, an_w2, an_h2, an_c, an_w2)
	var an_fg: PackedInt32Array = an_rr["fg"]
	var an_bad := 0
	for an_k in an_w2 * an_h2:
		if (an_fg[an_k] & 255) != an_bp[an_k]:
			an_bad += 1
	var an_seams := Defs.shell_of_row(an_y0 + an_h2 - 1) - Defs.shell_of_row(an_y0)
	# and build mode's cells near you (anchored on your column) map to a place and back, at any depth
	var an_keep: int = Defs.anchor_c
	Defs.anchor_c = an_c
	var an_rt := 0
	for an_q in 600:
		var an_col := an_c + an_rng.randi_range(-60, 60)
		var an_row := an_rng.randi_range(-Defs.ORBIT_ROWS + 2, Defs.ROWS - 40)
		var an_back: Vector2i = Build.cell_of(Build.cell_pos(an_col, an_row))
		if an_back != Vector2i(posmod(an_col, Defs.NS), an_row):
			an_rt += 1
	Defs.anchor_c = an_keep
	_ok("a building stamped deep is the same cell for cell (no column lost or doubled)", an_bad == 0 and an_seams >= 3 and an_rt == 0,
		"%d x %d from row %d, through %d seams (shells of %d to %d columns): %d cells differ; %d of 600 cells near you don't map back to themselves" % [an_w2, an_h2, an_y0, an_seams,
			Defs.SH_N[Defs.shell_of_row(an_y0)], Defs.SH_N[Defs.shell_of_row(an_y0 + an_h2 - 1)], an_bad, an_rt])
	_ok("guards are planned", b.guards.size() >= 5, "%d guards" % b.guards.size())
	var nchest := 0
	for info in b.infos:
		nchest += info["chests"].size()
	_ok("chests are placed", nchest >= 10, "%d chests" % nchest)
	await _frames(10)
	await _test_stampdiag()

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
					if row3 < 0 or row3 >= Defs.ROWS:
						continue
					var kw: int = Defs.raw_idx(row3, col3) * 4
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
			var nm: String = b.label_at(_cell_pos(int(info["x0"]) + a0.x, int(info["y0"]) + a0.y, int(info["ax"]), int(info["aw"])))
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
	# (where a frame's time goes, early on: a slow run still shows it)
	g.prof_reset()
	await _frames(90)
	print("[perf] early: ", g.prof_text(14, "; "))
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
				if rowv < 0 or rowv >= Defs.ROWS:
					continue
				for ii in int(info["w"]):
					var colv := posmod(int(info["x0"]) + ii, Nv)
					var kv := Defs.raw_idx(rowv, colv, int(info["ax"]), int(info["aw"])) * 4
					var a0 := raw_v0.decode_u32(boffv + kv)
					if (a0 & 255) == Defs.WOOD and (raw_v1.decode_u32(boffv + kv) & 255) == 0 and rowv > lowrow:
						lowrow = rowv
						var colm := []
						for dr in range(-1, 10):
							colm.append(str(raw_v0.decode_u32(Defs.raw_idx(rowv + dr, colv) * 4) & 255))
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
			if fe.pos.distance_to(dp) < 300.0 and not fe.boss:      # (a guardian in a lair nearby stays)
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
				var kd: int = Defs.raw_idx(int(door_t["row"]) + jd, posmod(int(door_t["col"]) + id2, Defs.NS), int(door_t.get("ax", door_t["col"])), int(door_t.get("aw", 1))) * 4
				if (rawd.decode_u32(kd) & 255) == Defs.WOODDOOR:
					nd2 += 1
		var want: int = int(door_t["w"]) * int(door_t["h"])
		_ok("a door opens when you walk into it, and closes again", was_open and not bool(door_t["open"]) and nd2 == want,
			"opened by walking: %s, closed again: %d of %d door cells (still open: %s; nearest foe: %s)" % [was_open, nd2, want, door_t["open"], foe_near.call()])
		# a door shot through keeps its hole: open it and shut it again, the hole is still there
		var count_door := func() -> int:
			var rr: Dictionary = g.gpu.read_rect(int(door_t["col"]), int(door_t["row"]), int(door_t["w"]), int(door_t["h"]), int(door_t.get("ax", door_t["col"])), int(door_t.get("aw", 1)))
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
	var cobj = null
	for info in b.infos:
		# (one near the surface, where its cells are where the surface columns say: a deep vault's
		# or dungeon's go in on their own anchor)
		if not info["ruined"] and info["chests"].size() > 0:
			for ch_q in info["chests"]:
				var ch_o = _chest_obj(ch_q)
				var ch_place: String = b.label_at(ch_o.pos) if ch_o != null else ""
				var ch_odd := "Halls" in ch_place or "Crypts" in ch_place or "Tomb" in ch_place or "Mine" in ch_place or "Vault" in ch_place
				if ch_o != null and not ch_odd and ch_q.y <= b.ground_row(ch_q.x) + 6:
					chest = ch_q
					cobj = ch_o
					break
		if cobj != null:
			break
	if cobj != null:
		# (right beside it, on its floor, whichever side is open: looked at from its own grid)
		_go(cobj.pos + cobj.pos.normalized() * 14.0)
		await _frames(8)
		var ch_side: Vector2 = g.basis_r(atan2(cobj.pos.y, cobj.pos.x))
		var ch_at: Vector2 = cobj.pos + ch_side * (float(Defs.CHEST_W) * 0.5 + 6.0) + cobj.pos.normalized() * 5.0
		if g.box_solid(g.to_grid(ch_at).x - 3.5, g.to_grid(ch_at).y - 8.5, 7.0, 17.0):
			ch_at = cobj.pos - ch_side * (float(Defs.CHEST_W) * 0.5 + 6.0) + cobj.pos.normalized() * 5.0
		_go(ch_at)
		await _frames(40)
		var before := 0
		for m in Defs.NM:
			before += g.player.inv[m]
		var ch_reach: int = g._chest_in_reach().size()
		var ch_d: float = g.player.pos.distance_to(cobj.pos)
		g._try_open_chest()
		await _frames(45)
		var after := 0
		for m in Defs.NM:
			after += g.player.inv[m]
		_ok("F opens a chest and gives loot", cobj.opened and after > before, "opened %s, satchel %d -> %d (%.0f cells from it, in reach %s, at %s)" % [cobj.opened, before, after, ch_d, ch_reach > 0, b.label_at(cobj.pos)])
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
				var k2 := Defs.raw_idx(row2, col2) * 4
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
			var kk := Defs.raw_idx(wall.y, wall.x) * 4
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
	# (another surface building's chest, not the one opened: same rules as for that one)
	var chest2 := Vector2i(-1, -1)
	var c2obj = null
	# (a standing building's first; the lairs' sure chests were the only others near the start, so a ruin's will do)
	var c2_infos: Array = []
	for info0 in b.infos:
		if not info0["ruined"]:
			c2_infos.append(info0)
	for info1 in b.infos:
		if info1["ruined"]:
			c2_infos.append(info1)
	for info in c2_infos:
		if info["chests"].size() > 0:
			for c2_q in info["chests"]:
				var c2_o = _chest_obj(c2_q)
				if c2_o == null or c2_o == cobj or c2_q.y > b.ground_row(c2_q.x) + 6:
					continue
				var c2_place: String = b.label_at(c2_o.pos)
				if "Halls" in c2_place or "Crypts" in c2_place or "Tomb" in c2_place or "Mine" in c2_place or "Vault" in c2_place:
					continue
				chest2 = c2_q
				c2obj = c2_o
				break
		if c2obj != null:
			break
	# (else any closed chest at the surface that isn't in a crypt or mine)
	var c2_why := {"opened": 0, "deep": 0, "under": 0}
	if c2obj == null:
		for c2_ch in g.chests:
			if c2_ch.opened or c2_ch == cobj:
				c2_why["opened"] += 1
				continue
			var c2_cell: Vector2i = Build.cell_of(c2_ch.pos)
			var c2_spot := Vector2i(c2_cell.x - Defs.CHEST_W / 2, c2_cell.y + 5)
			if c2_cell.y < Defs.SURF_Y0 or c2_spot.y > b.ground_row(c2_spot.x) + 6 or c2_spot.y < b.ground_row(c2_spot.x) - 60:
				c2_why["deep"] += 1
				continue
			var c2_lab: String = b.label_at(c2_ch.pos)
			if "Halls" in c2_lab or "Crypts" in c2_lab or "Tomb" in c2_lab or "Mine" in c2_lab or "Vault" in c2_lab:
				c2_why["under"] += 1
				continue
			chest2 = c2_spot
			c2obj = c2_ch
			break
	if c2obj == null:
		# (none at the surface: set one down on open, level ground with solid ground under it)
		var c2_st := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) + 60, Defs.CHEST_W + 8, 30, 1, 16, true)
		if _cs_found:
			chest2 = Vector2i(c2_st.x + 4, b.ground_row(c2_st.x + 4 + Defs.CHEST_W / 2))
			c2obj = g.new_chest()
			c2obj.pos = _cell_pos(chest2.x + Defs.CHEST_W / 2, chest2.y - 5)
			g.chests.append(c2obj)
			_go(_cell_pos(chest2.x - 14, chest2.y - 10))
			await _frames(60)
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
		_ok("a chest falls when its floor is dug out", false, "no second intact chest found (%d chests: %s)" % [g.chests.size(), str(c2_why)])

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
			if (raw_m.decode_u32(Defs.raw_idx(j, cm) * 4) & 255) == Defs.MUD:
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
			if b.biome(c0 + 60) != bname or b.biome(c0) != bname or _near_lair(c0) or _near_lair(c0 + 120):
				continue                  # (the planet's own plants: a lair's great trees are lairs.gd's)
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
		if after_t < int(best_n * 0.99):           # (knitted as the planet is made: nothing should drop)
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
			if _near_lair(col):
				continue                  # (a lair's great trees are living plants too, but grown by lairs.gd)
			for j in range(grc - 40, grc):
				var a := rw.decode_u32(toff + Defs.raw_idx(j, col) * 4)
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
						if (raw.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4) >> 16) == tid:
							n += 1
				return n
			_go(_cell_pos(tcol - 30, grt - 10))
			await _frames(30)
			var zone := func(raw: PackedByteArray) -> String:
				var nwz := 0
				var nfg := 0
				for j in range(grt - 10, grt - 3):
					for i in range(-5, 6):
						var kk := Defs.raw_idx(j, posmod(tcol + i, N0)) * 4
						if (raw.decode_u32(toff + kk) & 255) == Defs.WOOD:
							nwz += 1
						if (raw.decode_u32(kk) & 255) != 0:
							nfg += 1
				# support of the tree's wood well above the cut
				var sup := []
				for j in [grt - 14, grt - 20, grt - 30]:
					var a2 := raw.decode_u32(toff + Defs.raw_idx(j, tcol) * 4)
					sup.append("%d:%d" % [a2 & 255, (a2 >> 8) & 63])
				# the best-held cell of that tree above the cut, and what is around it
				var best := 99
				var where := ""
				for j in range(grt - 110, grt - 9):
					for i in range(-40, 41):
						var cc := posmod(tcol + i, N0)
						var a3 := raw.decode_u32(toff + Defs.raw_idx(j, cc) * 4)
						if (a3 >> 16) != tid:
							continue
						var sv := (a3 >> 8) & 63
						if sv < best:
							best = sv
							var nb := []
							for o in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
								nb.append(str(raw.decode_u32(Defs.raw_idx(j + o[1], posmod(cc + o[0], N0)) * 4) & 255))
							where = "S%d mat %d at %d,%d fg %s" % [sv, a3 & 255, i, grt - j, "/".join(nb)]
				return "wood in cut %d, front cells %d, sup %s, best %s" % [nwz, nfg, ",".join(sup), where]
			var before_n: int = count_tree.call(g.gpu.read_world())
			var z0: String = zone.call(g.gpu.read_world())
			# wood in the background all around (this tree and its neighbours): a felled tree should
			# still be wood afterwards, lying where it fell, not a heap of timber grains
			# (wide and deep enough for a trunk that rolls down a slope: 26 Nov one rolled ~180 columns off and its
			# wood counted as lost)
			var wood_round := func(raw: PackedByteArray) -> int:
				var n := 0
				for j in range(grt - 150, grt + 40):
					for i in range(-320, 321):
						var kw := Defs.raw_idx(j, posmod(tcol + i, N0)) * 4
						if (raw.decode_u32(toff + kw) & 255) == Defs.WOOD or (raw.decode_u32(kw) & 255) == Defs.WOOD:
							n += 1
				return n
			var own_wood := 0
			var rw0: PackedByteArray = g.gpu.read_world()
			for j in range(grt - 110, grt - 9):
				for i in range(-40, 41):
					var a5 := rw0.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4)
					if (a5 >> 16) == tid and (a5 & 255) == Defs.WOOD:
						own_wood += 1
			var wood0: int = wood_round.call(rw0)
			# loose specks (timber grains, leaf litter) and leaves around, before and after
			var bits_round := func(raw: PackedByteArray) -> Vector2i:
				var specks := 0
				var leaves := 0
				for j in range(grt - 150, grt + 6):
					for i in range(-170, 171):
						var kbits := Defs.raw_idx(j, posmod(tcol + i, N0)) * 4
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
					var a6 := rw0.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4)
					if (a6 >> 16) == tid and (a6 & 255) == Defs.LEAF:
						own_leaves += 1
			# its roots: its own wood below the ground line, in the background behind the earth
			var own_roots := 0
			for j in range(grt, grt + 19):
				for i in range(-40, 41):
					var a7 := rw0.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4)
					if (a7 >> 16) == tid and (a7 & 255) == Defs.ROOT:
						own_roots += 1
			# and across the land around: no trunk ends in the air above a slope (a flat, bare bottom):
			# the lowest wood of a tree in a column near the ground rests on earth (or its own roots)
			var bare := 0
			var feet := 0
			for i in range(-600, 601):
				var cb: int = posmod(tcol + i, N0)
				if _near_lair(cb):
					continue
				var grb: int = b.ground_row(cb)
				var foot := -1
				var lid := 0
				for j in range(grb - 8, grb + 3):
					var abf := rw0.decode_u32(toff + Defs.raw_idx(j, cb) * 4)
					if ((abf & 255) == Defs.WOOD or (abf & 255) == Defs.ROOT) and (abf >> 30) == 2:
						foot = j
						lid = abf >> 16
				if foot < 0:
					continue
				feet += 1
				var below_f := rw0.decode_u32(Defs.raw_idx(foot + 1, cb) * 4) & 255
				var below_b := rw0.decode_u32(toff + Defs.raw_idx(foot + 1, cb) * 4)
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
			# (one still rocking where it leans after that is set down where it lies, as saving would)
			var still_moving: int = g.chunks.list.size()
			if still_moving > 0:
				g.chunks.settle_all()
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
				("(still moving after 400 frames: %d, set down) " % still_moving if still_moving > 0 else "") + "it came away as %d piece(s); wood around: %d before, %d after (the tree had %d); loose specks %d -> %d; leaves %d -> %d (its own %d); the game's longest frame %.1f ms (%s [%s, %s, %s, %s], %s, %s)" % [max_chunks, wood0, wood1, own_wood, bits0.x, bits1.x, bits0.y, bits1.y, own_leaves, g.hitch_us / 1000.0, _peak("lifting pieces out"), _peak("lift: read"), _peak("lift: find"), _peak("lift: make"), _peak("lift: clear"), _peak("falling pieces"), _peak("read back")])
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
			var kf: int = Defs.raw_idx(cqf.y + djf, posmod(cqf.x + dif, Defs.NS)) * 4
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
				var kt: int = Defs.raw_idx(int(tstamp["y0"]) + tj, posmod(int(tstamp["x0"]) + ti, Defs.NS)) * 4
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
				var kt2: int = Defs.raw_idx(int(tstamp["y0"]) + tj2, posmod(int(tstamp["x0"]) + ti2, Defs.NS)) * 4
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
	var house_why := []
	var house_at := Vector2.ZERO
	var doors_mid: int = g.doors.size()
	var hb_ang: float = atan2(g.player.pos.y, g.player.pos.x)
	var at_ang := func(k: float, up: float) -> Vector2:
		var aa: float = hb_ang + k / Defs.RS0
		return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + up)
	# (both ways along the ground, a good way out: structures and a guardian's levelled lair may lie
	# across the near spots, so spots inside any named structure are passed over)
	var hks := []
	for hd in range(150, 1210, 40):
		hks.append(-float(hd))
		hks.append(float(hd))
	for hk in hks:
		if b.label_at(at_ang.call(hk, 8.0)) != "" or b.label_at(at_ang.call(hk - 20.0, 8.0)) != "" or b.label_at(at_ang.call(hk + 20.0, 8.0)) != "":
			continue
		# stand next to the spot (you can only build within reach), well away from the pieces above
		_go(at_ang.call(hk + 30.0, 14.0))
		await _frames(25)
		house_at = at_ang.call(hk, 8.0)
		g.test_aim = house_at
		await _frames(3)
		house_ok = g.build_prev.get("ok", false)
		if house_ok:
			break
		if house_why.size() < 6:
			house_why.append("%d: plan %s tree %s cost %s at %s" % [int(hk), g._struct.get("ok", "-"), g._struct.get("tree", "-"), str(g._struct.get("cost", {})), b.label_at(house_at)])
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
				var kb: int = Defs.raw_idx(cq.y + dj, posmod(cq.x + di, Defs.NS)) * 4
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
				var kd3: int = Defs.raw_idx(int(nd3["row"]) + dj3, posmod(int(nd3["col"]) + di3, Defs.NS)) * 4
				if (rawb.decode_u32(kd3) & 255) == Defs.WOODDOOR:
					n_door += 1
	_ok("build mode puts up a whole house", house_ok and house_doors == 2, "fits somewhere: %s, its doors: %d; last click: %s; %s" % [house_ok, house_doors, g.build_last, "; ".join(house_why)])
	_ok("build mode puts up walls, furniture and doors", n_wall >= 8 and n_decor >= 20 and n_door >= 60 and doors_mid == doors_before + 1,
		"wall cells %d (%d when painted), table cells %d (fit %s; %s; in its blueprint's box: %d at once, %d a second later, %d at the end; box %s, holds %s), door cells %d (fit %s), doors %d -> %d" % [n_wall, wall_first, n_decor, table_ok, table_last, table_now, table_later, count_decor.call(rawb), str([tstamp.get("x0"), tstamp.get("y0"), tstamp.get("w"), tstamp.get("h")]), str(box_mats), n_door, door_ok, doors_before, doors_mid])

	await _test_stairs()
	await _test_workshops()
	await _test_crafting()
	await _test_indoors()
	await _test_remove()
	await _test_harvest()
	await _test_hand()
	await _test_audio()
	await _test_inworld()
	await _test_spawns()

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
		g.select_carried(g.player.furn.size() - 1)
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
		g.select_carried(g.player.furn.size() - 1)
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
	# (the best of three rounds: one hiccup of the laptop's own isn't the game's cost)
	var pick_us := 1e9
	for qr in 3:
		var tq := Time.get_ticks_usec()
		for qk in 30:
			g._pick_up_furniture(g.player, wall_at)
		pick_us = minf(pick_us, float(Time.get_ticks_usec() - tq) / 30.0)
		await _frames(2)
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
	# (out in the open: level ground with nothing standing over it, so a bat has a clear dive)
	var fo_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) - 160, 110, 80)
	var fo_a: float = (float(fo_st.x) + 55.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(fo_a), sin(fo_a)) * (g.gpu.surf_at(fo_a).x + 12.0))
	await _frames(40)
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
		if not bool(dd["open"]) and not dd.has("cells") and int(dd["row"]) < Defs.ROWS:
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
		if e.type == "golem":
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
		# (since 24 Nov a boss gives up only after main GIVE_UP_T frames that far off)
		for f9 in 700:
			await _frames(1)
			if boss_e.hp >= boss_e.max_hp and not boss_e.awake:
				break
		_ok("a boss left alone recovers to full health", boss_e.hp >= boss_e.max_hp and not boss_e.awake,
			"health %d of %d, %s" % [int(boss_e.hp), int(boss_e.max_hp), "asleep" if not boss_e.awake else "awake"])
	else:
		_ok("a boss left alone recovers to full health", false, "no boss in the world")
	# ---- the close view is the world as it is (the "view" setting's default): a world unit is the
	# same size on screen at any height, and the camera sits on a cell's corner (no shimmer) ----
	var wv_unrolled: bool = g.unrolled()
	var wv_c: Vector2 = g.view_c
	var wv_r := wv_c.length()
	var wv_s: int = Defs.shell_of_row(int(Defs.R_TOP - roundf(wv_r)))
	var wv_k := atan2(wv_c.y, wv_c.x) / (TAU / float(Defs.SH_N[wv_s]))
	var wv_corner: bool = absf(wv_r - roundf(wv_r)) < 0.01 and absf(wv_k - roundf(wv_k)) < 0.02
	var wv_sizes := []
	var wv_same := true
	for wv_h in [-300.0, -60.0, 0.0, 60.0, 300.0]:
		var wv_p: Vector2 = wv_c.normalized() * (wv_r + wv_h)
		var wv_a: Vector2 = g.world_to_screen(wv_p)
		var wv_b: Vector2 = g.world_to_screen(wv_p + g.basis_r(atan2(wv_p.y, wv_p.x)) * 10.0)
		var wv_px: float = wv_a.distance_to(wv_b) * g.zoom / 10.0
		wv_sizes.append("%+d: %.3f" % [int(wv_h), wv_px])
		wv_same = wv_same and absf(wv_px - 1.0) < 0.002
	_ok("the close view is the world as it is: nothing stretches going up or down, the camera sits on a cell's corner",
		not wv_unrolled and wv_corner and wv_same, "unrolled %s; camera at radius %.2f, column %.3f; a world unit across on screen at %s" % [wv_unrolled, wv_r, wv_k, ", ".join(wv_sizes)])
	# ---- ... and its picture is drawn a cell a pixel, each cell once: the cell at a point on screen is the
	# one the picture holds where the view's shader looks for it (so no column is drawn twice, or dropped,
	# which showed as bands that stayed put as you walked) ----
	var cp_ok := int(g.pic.get("mode", 0)) == 1
	var cp_bad := []
	if cp_ok:
		var cp_rows: PackedFloat32Array = g.pic["rows"]
		for cp_k in 25:
			var cp_sp := Vector2(float(g.VW) * (0.06 + 0.22 * float(cp_k % 5)), float(g.VH) * (0.06 + 0.22 * float(cp_k / 5)))
			var cp_w0: Vector2 = g.screen_to_world(cp_sp)
			var cp_row := int(floor(Defs.R_TOP - cp_w0.length()))
			var cp_n: int = Defs.SH_N[Defs.shell_of_row(cp_row)]
			var cp_col := int(floor(fposmod(atan2(cp_w0.y, cp_w0.x), TAU) / TAU * cp_n))
			# (the middle of that cell)
			var cp_a := (float(cp_col) + 0.5) / float(cp_n) * TAU
			var cp_w := Vector2(cos(cp_a), sin(cp_a)) * (Defs.R_TOP - float(cp_row) - 0.5)
			var cp_p: Vector2 = g.world_to_pic(cp_w)
			var cp_i := int(floor(cp_p.x))
			var cp_j := int(floor(cp_p.y))
			if cp_j < 0 or cp_j >= g.gpu.PH or cp_i < 0 or cp_i >= g.gpu.PW:
				cp_bad.append("%d off the picture (%d, %d)" % [cp_k, cp_i, cp_j])
				continue
			var cp_xa := int(floor(float(g.pic["a"]) / TAU * float(int(cp_rows[cp_j * 2]))))
			var cp_x := posmod(cp_xa + int(floor(g.gpu.PW * 0.5)) - 1 - cp_i, int(cp_rows[cp_j * 2]))
			if int(g.pic["y0"]) + cp_j != cp_row or cp_x != cp_col:
				cp_bad.append("%d: cell %d,%d drawn as %d,%d" % [cp_k, cp_col, cp_row, cp_x, int(g.pic["y0"]) + cp_j])
	_ok("the close view's picture holds each cell once, where the view's shader looks for it", cp_ok and cp_bad.is_empty(),
		"cell picture %s (%d x %d, margin %d, %d); %s" % [cp_ok, g.gpu.PW, g.gpu.PH, g.gpu.PMX, g.gpu.PMY, "all 25 points agree" if cp_bad.is_empty() else "; ".join(cp_bad)])
	# ---- the unrolled view (the other setting) keeps the cells around you one pixel wide at any depth ----
	var widths := []
	var view_ok := true
	for rr in [1300.0, 900.0, 500.0, 250.0, 120.0]:
		var st: float = g.unroll_step(rr)
		var cell_w: float = st * rr                  # world units per pixel across
		widths.append("%d: %.2f" % [int(rr), cell_w])
		view_ok = view_ok and cell_w > 0.45 and cell_w < 1.6
	_ok("the view isn't stretched deep down", view_ok, "world units per pixel across at radius " + ", ".join(widths))
	# ---- the view's scale never jumps: what a pixel covers changes smoothly, a seam never squeezes it
	var vw_step := 1.0           # the biggest change between rows 2 apart (world units per pixel across)
	var vw_48 := 1.0             # ... and over 48 rows (about a quarter of the screen)
	var vw_seam := 1.0           # the biggest ratio of columns across a seam
	var vw_wmin := 9.0
	var vw_wmax := 0.0
	var vw_prev := -1.0
	var vw_hist := []
	for vw_row in range(-Defs.ORBIT_ROWS, Defs.ROWS, 2):
		var vw_r := Defs.R_TOP - float(vw_row)
		if vw_r < 320.0:
			break                 # (near the heart the planet's own curve changes the scale fast)
		var vw_px: float = g.unroll_step(vw_r) * vw_r
		if vw_prev > 0.0:
			vw_step = maxf(vw_step, maxf(vw_px / vw_prev, vw_prev / vw_px))
		vw_hist.append(vw_px)
		if vw_hist.size() > 24:
			var vw_old: float = vw_hist[vw_hist.size() - 25]
			vw_48 = maxf(vw_48, maxf(vw_px / vw_old, vw_old / vw_px))
		vw_prev = vw_px
		vw_wmin = minf(vw_wmin, vw_px)
		vw_wmax = maxf(vw_wmax, vw_px)
	for vw_k in Defs.NSH - 1:
		if Defs.R_TOP - float(Defs.SH_Y1[vw_k]) >= 320.0:     # (near the heart the steps grow)
			vw_seam = maxf(vw_seam, float(Defs.SH_N[vw_k]) / float(Defs.SH_N[vw_k + 1]))
	_ok("the view never visibly changes size going up or down (no seam squeezes it)",
		vw_step < 1.01 and vw_48 < 1.12 and vw_seam < 1.05 and vw_wmin > 0.7 and vw_wmax < 1.3,
		"%d shells; biggest seam %.3f; a pixel covers %.2f - %.2f world units across, changing at most %.4f per 2 rows, %.3f per 48 rows" % [Defs.NSH, vw_seam, vw_wmin, vw_wmax, vw_step, vw_48])
	# ---- deep down, sand and a loose block fall straight through a seam, none lost or doubled ----
	var sm_s: int = mini(Defs.SURF + 4, Defs.NSH - 2)
	var sm_seam: int = Defs.SH_Y1[sm_s]              # the first row of the shell below it
	var sm_y0: int = sm_seam - 34
	var sm_w := 24
	var sm_h := 64
	# a spot in solid rock (a cave would let the sand pour out of the pocket)
	var sm_a: float = fposmod(g.spawn_angle + 0.35, TAU)
	for sm_try in 60:
		var sm_ta: float = fposmod(g.spawn_angle + 0.35 + 0.05 * sm_try, TAU)
		var sm_tc: int = int(sm_ta / TAU * Defs.NS)
		var sm_probe: Dictionary = g.gpu.read_rect(sm_tc - 6, sm_y0 - 6, sm_w + 12, sm_h + 12, sm_tc - 6, sm_w + 12)
		var sm_solid := true
		for sm_v in sm_probe["fg"]:
			if Defs.KIND[sm_v & 255] != Defs.K_SOLID:
				sm_solid = false
				break
		if sm_solid:
			sm_a = sm_ta
			break
	var sm_c: int = int(sm_a / TAU * Defs.NS)
	var sm_data := PackedInt32Array()
	for sm_j in sm_h:
		for sm_i in sm_w:
			var sm_m := 0                       # an open pocket around the seam (background cleared too)
			if sm_j < 6 and sm_i >= 12 and sm_i < 22:
				sm_m = Defs.SAND
			elif sm_j >= 2 and sm_j < 6 and sm_i >= 3 and sm_i < 7:        # (clear of the ceiling)
				sm_m = Defs.BRICK                # a loose built block (not anchored)
			sm_data.append(sm_m | (0 << 8))
	g.gpu.stamp([{"x0": sm_c, "y0": sm_y0, "w": sm_w, "h": sm_h, "data": sm_data, "ax": sm_c, "aw": sm_w}], 7)
	var sm_count := func(sm_raw: PackedByteArray, sm_mat: int, sm_above: bool) -> int:
		var sm_n := 0
		for sm_row in range(sm_y0, sm_y0 + sm_h):
			if sm_above != (sm_row < sm_seam):
				continue
			# the pocket's cells (it went in cell for cell, anchored on itself)
			for sm_i2 in sm_w:
				var sm_k: int = Defs.raw_idx(sm_row, posmod(sm_c + sm_i2, Defs.NS), sm_c, sm_w)
				var sm_t := sm_raw.decode_u32(sm_k * 4) & 255
				if sm_t == sm_mat or (sm_mat == Defs.BRICK and sm_t == Defs.DEBRIS[Defs.BRICK]):
					sm_n += 1
		return sm_n
	var sm_r0: PackedByteArray = g.gpu.read_world()
	var sm_sand0: int = sm_count.call(sm_r0, Defs.SAND, true) + sm_count.call(sm_r0, Defs.SAND, false)
	var sm_stone0: int = sm_count.call(sm_r0, Defs.BRICK, true)
	var sm_mid: float = Defs.R_TOP - float(sm_seam)
	g.gpu.settle([[Vector2(cos(sm_a), sin(sm_a)) * sm_mid, 90.0]], 0.0, 400)
	var sm_r1: PackedByteArray = g.gpu.read_world()
	var sm_sand_up: int = sm_count.call(sm_r1, Defs.SAND, true)
	var sm_sand_dn: int = sm_count.call(sm_r1, Defs.SAND, false)
	var sm_stone_up: int = sm_count.call(sm_r1, Defs.BRICK, true)
	var sm_stone_dn: int = sm_count.call(sm_r1, Defs.BRICK, false)
	# (a look at the seam and the shells around it, from inside the pocket)
	var sm_back: Vector2 = g.player.pos
	_go(Vector2(cos(sm_a), sin(sm_a)) * (sm_mid - 24.0))
	await _frames(40)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("deep_seam.png"))
	_go(sm_back)
	await _frames(10)
	_ok("deep down, sand and a loose block fall straight through a seam (none lost or doubled)",
		sm_sand0 > 40 and sm_sand_up == 0 and sm_sand_dn == sm_sand0 and sm_stone0 >= 8 and sm_stone_up == 0 and sm_stone_dn > 0,
		"seam at row %d (shells of %d and %d columns); sand %d -> %d above, %d below; brick %d above -> %d above, %d below (some may have broken into rubble)" % [sm_seam, Defs.SH_N[sm_s], Defs.SH_N[sm_s + 1], sm_sand0, sm_sand_up, sm_sand_dn, sm_stone0, sm_stone_up, sm_stone_dn])

	# ---- one-way platforms: land on one, drop through it (down + jump), jump up through it ----
	# (a level stretch near where you arrive with nothing standing on it: trees, logs from the felled
	# tree, a building)
	var pst := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 24, 40, 70)
	var pcol := pst.x + 16
	var pg: int = pst.y
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
		("(at column %d) " % pcol) + "strip at row %d (%d of 21 cells there, pillar %d of %d): stood at row %d (on it %s), after down + jump row %d (through %s), after a jump on it again %s" % [prow, strip_n, pillar_n, pil_g - prow - 1, row_on, landed, row_down, dropped, back_up])

	# ---- unsupported blocks fall, and falling rock hurts (on a clear stretch: nothing over you) ----
	var fst := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 90, 50, 70)
	var fa: float = (float(fst.x) + 10.5) / float(Defs.NS) * TAU
	var sp := Vector2(cos(fa), sin(fa))
	var rs: float = g.gpu.surf_at(fa).x
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
		max_creak = maxi(max_creak, g.gpu.counts[Defs.C_CREAK_N])
		if here and g.gpu.counts[Defs.C_CREAK_N] > 0:
			creaking = true
		if not here and gone_at < 0:
			gone_at = f
	var still: bool = stone_near.call()
	_ok("a loose block creaks first, then falls", placed and creaking and not still, "placed %s, creaked %s (max %d cells), left its spot at frame %d" % [placed, creaking, max_creak, gone_at])
	g.test_god = false
	g.hp = g.max_hp
	g.iframes = 0
	var hp0: float = g.hp
	# (a block big enough that, lifted out as a rigid piece, it can't slip past him between the
	# points a falling piece is checked against: a 3-cell one once fell by without a scratch)
	g.brushes.append([g.player.pos + up * 40.0, 2.6, 5, Defs.STONE, 0, 8, 0])
	await _frames(150)
	_ok("falling rock hurts the mage", g.hp < hp0, "health %.0f -> %.0f" % [hp0, g.hp])
	# digging a pit right under your feet, again and again, costs nothing: you drop in with the rim
	# (on clear ground: nothing standing over you that the digging could bring down, and no cave under
	# it: breaking into one brings its roof down after you, and that does hurt)
	var pit_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) - 120, 30, 70, 6, 64, false, 40)
	var pit_a: float = (float(pit_st.x) + 15.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(pit_a), sin(pit_a)) * (g.gpu.surf_at(pit_a).x + 14.0))
	await _frames(60)
	# (and nothing about to bite: a foe walking by once took 3 off and failed it)
	for pt_e in g.enemies.duplicate():
		if not pt_e.boss and pt_e.guard_id < 0:
			g.enemies.erase(pt_e)
	g.projs.clear()
	g.spawn_timer = 600
	g.hp = g.max_hp
	g.iframes = 0
	var hp1: float = g.hp
	var pit_log := []
	var pit_hp: float = g.hp
	var pit_r0: float = g.player.pos.length()
	for pk in 4:
		var upk: Vector2 = g.player.pos.normalized()
		g.brushes.append([g.player.pos - upk * 12.0, g.player.dig_r, 1, 0, g.player.tier, 0, 0, 0])
		for pf in 25:
			await _frames(1)
			if g.hp < pit_hp - 0.01:
				# (what hurt: falling cells this frame, rigid pieces about, lava, fire, how far you'd dropped)
				pit_log.append("f%d -%.0f (fall n %d max %d, pieces %d, lava %d, fire %d, dropped %.0f, %s)" % [pk * 25 + pf, pit_hp - g.hp, g.gpu.counts[Defs.C_FALL_N], g.gpu.counts[Defs.C_FALL_MAX],
					g.chunks.list.size(), g.gpu.counts[Defs.LAVA], g.gpu.counts[Defs.FIRE], pit_r0 - g.player.pos.length(), g.hazard])
				pit_hp = g.hp
	for pf2 in 60:
		await _frames(1)
		if g.hp < pit_hp - 0.01:
			pit_log.append("after f%d -%.0f (fall n %d max %d, pieces %d)" % [pf2, pit_hp - g.hp, g.gpu.counts[Defs.C_FALL_N], g.gpu.counts[Defs.C_FALL_MAX], g.chunks.list.size()])
			pit_hp = g.hp
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("pit.png"))
	_ok("digging a pit under yourself doesn't hurt", g.hp >= hp1, "health %.0f -> %.0f at column %d; %s" % [hp1, g.hp, pit_st.x, "; ".join(pit_log)])
	# ---- a frozen world's open water ices over from the top (tried here with the planet's frost turned
	# on: a basin dug and filled, then left out in the cold) ----
	# (you stand on the same clear stretch, well to the side of the basin, and can't come to harm: a
	# spot picked blind once left you somewhere you died, and the checks after it ran with you dead)
	var fz_god0: bool = g.test_god
	g.test_god = true
	var fz_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 160, 80, 60, 4, 30)
	var fz_c: int = fz_st.x + 20
	var fz_a: float = (float(fz_c) + 0.5) / float(Defs.NS) * TAU
	var fz_up := Vector2(cos(fz_a), sin(fz_a))
	var fz_g: float = g.gpu.surf_at(fz_a).x
	var fz_ya: float = (float(fz_st.x) + 66.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(fz_ya), sin(fz_ya)) * (g.gpu.surf_at(fz_ya).x + 12.0))
	await _frames(30)
	g.brushes.append([fz_up * (fz_g - 5.0), 9.0, 1, 0, 9, 0, 0, 0])
	await _frames(20)
	g.brushes.append([fz_up * (fz_g - 6.0), 7.5, 5, Defs.WATER, 0, 400, 0])
	await _frames(90)
	var fz_count := func() -> Vector2i:
		var fz_rr: Dictionary = g.gpu.read_rect(fz_c - 14, fz_st.y - 20, 28, 40)
		var fz_w := 0
		var fz_i := 0
		for fz_v in fz_rr["fg"]:
			if (fz_v & 255) == Defs.WATER:
				fz_w += 1
			elif (fz_v & 255) == Defs.ICE:
				fz_i += 1
		return Vector2i(fz_w, fz_i)
	var fz0: Vector2i = fz_count.call()
	var fz_was: float = float(g.clim.get("freeze", 0.0))
	g.clim["freeze"] = 5.0
	await _frames(600)
	g.clim["freeze"] = fz_was
	g.test_god = fz_god0
	var fz1: Vector2i = fz_count.call()
	_ok("on a frozen world, open water ices over from the top", fz0.x >= 20 and fz0.y == 0 and fz1.y >= 8 and fz1.x > 0,
		"the basin: water %d, ice %d; 10 s in the frost: water %d, ice %d (the ice on top, the water under it); you: health %.0f, %s" % [fz0.x, fz0.y, fz1.x, fz1.y, g.hp, g.state])
	await _test_hazards()
	await _test_sky()
	# ---- health doesn't come back by itself; a draught and Mending bring it back over a moment ----
	# (nothing about to bite: a wild creature wandering by would muddle the sums)
	for hl_e in g.enemies.duplicate():
		if not hl_e.boss and hl_e.guard_id < 0:
			g.enemies.erase(hl_e)
	g.spawn_timer = 600
	var hl_god0: bool = g.test_god
	g.test_god = true                         # (nothing may hurt you while it counts the healing)
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
	g.player.spell_cd.clear()
	g._cast(g.player, "mend", g.player.pos)
	var mana_after: float = g.mana
	await _frames(90)
	var hp_mended: float = g.hp
	g.known.erase("mend")
	g.test_god = hl_god0
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
	# (the busy-scene benchmark runs last: its fires, pits and poured sand spoiled the checks after it)
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
	var shown := 0
	for r2 in g.recipes:
		if not g.recipe_hidden(r2):
			shown += 1
	for pr2 in Defs.PROCESS:
		if String(pr2["at"]) in ["kiln", "smelter", "still"]:
			shown += 1               # (the workshops' mixes are pages of the book too: one card or secret page each)
	await _test_gear()
	await _test_towns()
	await _test_vfx()
	await _test_start()
	await _test_quest()
	await _test_recipes()
	await _test_ui()
	await _test_speech()
	_ok("the Wisp Forge lists recipes and crafts", cards == shown and crafted, "%d of %d recipe cards (%d hidden until their ore is found), crafting %s" % [cards, shown, g.recipes.size() - shown, "works" if crafted else "failed"])

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
		"ledge %d of 72 stone cells at row %d (radius %.0f, the air ends at %.0f); %d shells, the top one %d columns" % [ob_stone, ob_c.y, Defs.R_TOP - ob_c.y, Defs.R_TOP, Defs.NSH, Defs.SH_N[0]])
	_ok("vacuum: water freezes, fire goes out, sand falls out of the band, you hold your breath",
		int(ob_m.get("Ice", 0)) > 0 and int(ob_m.get("Water", 0)) == 0 and ob_fires2 == 0 and ob_sand_up == 0 and ob_sand_air > 0 and ob_b1 < ob_b0,
		"above the ledge %s; fire %d -> %d; sand left up there %d, fallen into the air %d; breath %.0f -> %.0f (%s)" % [str(ob_m), ob_fires, ob_fires2, ob_sand_up, ob_sand_air, ob_b0, ob_b1, ob_st])
	g.player.breath = g.player.max_breath
	g.chunks.clear()

	await _test_guardians()
	await _test_hearts()
	await _test_wardens()

	await _test_creatures()
	await _test_ecology()
	await _test_fog()

	await _test_climb()
	await _test_nav()
	await _test_pursuit()

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
	# jet outward: the camera stays on you; once the planet is out of sight the GPU rests
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

	# ---- an asteroid: out by one, the view comes in close, you mine it, bump it, cut it in two ----
	g.player.dead = false
	g.test_god = true
	_go(sx_up * (Defs.R_SPACE - 40.0))
	g.test_jump = true
	for as_k in 240:
		g.player.mana = g.player.max_mana
		await _frames(1)
		if g.space.active:
			break
	g.test_jump = false
	g.space._ensure_rocks(true)
	var as_n0: int = g.space.home_rocks().size()
	var as_kinds := {}
	for as_a in g.space.home_rocks():
		as_kinds[as_a.kind] = int(as_kinds.get(as_a.kind, 0)) + 1
	var as_r = null                          # (the biggest stony one)
	for as_a2 in g.space.home_rocks():
		if as_a2.kind == "stony" and (as_r == null or as_a2.mass > as_r.mass):
			as_r = as_a2
	if as_r == null:
		as_r = g.space.home_rocks()[0]
	as_r.omega = 0.0                          # (held still, so the spot you dig at stays put)
	as_r.vel = Vector2.ZERO
	# its surface on the side facing the planet, and you a little off it
	var as_dir: Vector2 = (-as_r.pos).normalized()
	var as_s: Vector2 = as_r.pos
	for as_st in 400:
		if not as_r.solid_at(as_s) and as_st > 3:
			break
		as_s += as_dir * 0.5
	g.player.pos = as_s + as_dir * 14.0
	g.cam_c = g.player.pos
	g.space.vel = Vector2.ZERO
	for as_k2 in 150:
		g.space.vel = Vector2.ZERO
		await _frames(1)
	var as_zoom: float = g.zoom
	var as_live: bool = g.space.live
	# mine toward its middle
	var as_inv0 := 0
	for as_v in g.player.inv:
		as_inv0 += int(as_v)
	var as_c0: int = as_r.count()
	g.test_dig = true
	for as_k3 in 180:
		g.test_aim = as_s - as_dir * (3.0 + float(as_k3) / 180.0 * 18.0)
		g.space.vel = Vector2.ZERO
		await _frames(1)
	g.test_dig = false
	g.test_aim = Vector2.ZERO
	await _frames(12)
	var as_inv1 := 0
	for as_v2 in g.player.inv:
		as_inv1 += int(as_v2)
	var as_c1: int = as_r.count()
	await _frames(2)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("asteroid.png"))
	# fly into it: you never end up inside it
	var as_in := 0
	for as_k4 in 60:
		g.space.vel = (as_r.pos - g.player.pos).normalized() * 3.0
		await _frames(1)
		if as_r.solid_at(g.player.pos):
			as_in += 1
	g.space.vel = Vector2.ZERO
	# cut it through the middle (a band three cells wide across its grid): it drifts apart in two
	var as_cnt0: int = g.space.home_rocks().size()
	var as_mid: int = as_r.h / 2
	for as_j in range(as_mid - 1, as_mid + 2):
		for as_i in as_r.w:
			if as_r.cells[as_j * as_r.w + as_i] != 0:
				as_r.take(as_j * as_r.w + as_i)
	await _frames(20)
	var as_cnt1: int = g.space.home_rocks().size()
	var as_d0 := 0.0
	var as_other = null
	for as_a3 in g.space.home_rocks():
		if as_a3 != as_r and (as_other == null or (as_a3.pos - as_r.pos).length() < (as_other.pos - as_r.pos).length()):
			as_other = as_a3
	if as_other != null:
		as_d0 = (as_other.pos - as_r.pos).length()
	await _frames(120)
	var as_d1: float = 0.0 if as_other == null else (as_other.pos - as_r.pos).length()
	var as_saved = g.space.rocks_state(int(g.planet["index"]))
	var as_nsave: int = (as_saved as Array).size() if as_saved != null else -1
	# and back down
	g.player.pos = sx_up * (Defs.R_SPACE - 4.0)
	g.cam_c = g.player.pos
	var as_back := -1
	for as_k5 in 200:
		g.space.vel = -sx_up * 3.0
		await _frames(1)
		if not g.space.active:
			as_back = as_k5
			break
	await _frames(60)
	_ok("an asteroid: the view comes in close, you mine it, bump it and cut it in two",
		as_n0 >= 6 and as_kinds.size() >= 2 and as_zoom < 1.6 and not as_live and as_inv1 - as_inv0 >= 20 and as_c0 - as_c1 >= as_inv1 - as_inv0
			and as_in == 0 and as_cnt1 > as_cnt0 and as_d1 > as_d0 + 1.0 and as_nsave == g.space.home_rocks().size() and as_back >= 0,
		"%d rocks (%s); zoom by it %.2f (live planet %s); mined %d cells into the satchel (%d -> %d cells); inside it %d of 60 frames flying at it; cut through: %d -> %d rocks, the pieces %.1f -> %.1f apart; %d saved; back down after %d ticks" % [as_n0, str(as_kinds), as_zoom, as_live, as_inv1 - as_inv0, as_c0, as_c1, as_in, as_cnt0, as_cnt1, as_d0, as_d1, as_nsave, as_back])
	g.test_god = true

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
	# (on a clear, level stretch: set down on a slope or loose ground, it once slid on after settling)
	var sf_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 40, 200, 70, 4)
	var sf_ang: float = (float(sf_st.x) + 100.5) / float(Defs.NS) * TAU
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
	# ---- sails, not a glass bubble (user, 26 Nov: "Can we just have sails since the player is not gonna show up
	# anymore"): no glass on any class, cloth and masts above the deck, still one piece; saved and loaded back
	var sr_txt := []
	var sr_ok := true
	var Skc = load("res://scripts/skiff.gd")
	for sr_kc in Skc.CLASSES:
		var sr_sh = Skc.make(4242, sr_kc)
		var sr_glass := 0
		var sr_cloth := 0
		var sr_mast := 0
		for sr_k in sr_sh.w * sr_sh.h:
			var sr_m: int = sr_sh.cells[sr_k]
			if sr_m == Defs.GLASS or sr_sh.bg[sr_k] == Defs.GLASS:
				sr_glass += 1
			elif sr_m == Defs.SNOW or sr_m == Defs.SAND or sr_m == Defs.TILE:
				sr_cloth += 1
			elif (sr_m == Defs.TIMBER or sr_m == Defs.STARIRON) and sr_k / sr_sh.w < int((sr_sh.seat_cells[0] as Vector2i).y) - 10:
				sr_mast += 1
		var sr_one: bool = sr_sh.pieces().size() == 1
		sr_ok = sr_ok and sr_glass == 0 and sr_cloth > 150 and sr_mast > 20 and sr_one
		sr_txt.append("%s: glass %d, sail %d, mast %d, one piece %s" % [sr_kc, sr_glass, sr_cloth, sr_mast, sr_one])
	g.save_world(true)
	var sr_saved: bool = g.planet_state.has("skiff") and g.planet_state["skiff"].has("cells")
	var sr_copy = Skiff.make(sf_sk.design_seed, sf_sk.klass)
	var sr_loaded: bool = sr_copy.load_cells(sf_sk.save_cells()) and sr_copy.cells == sf_sk.cells
	_ok("ships carry sails, not a glass bubble (you're inside, never drawn), and are saved cell by cell",
		sr_ok and sr_saved and sr_loaded, "%s; saved with the world %s; loaded back %s" % ["; ".join(sr_txt), sr_saved, sr_loaded])
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
			sf_scale.append(snappedf(g.overlay._skiff_xf(sf_sk).y.length() * g.zoom, 0.01))
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
	g.test_down = true          # (hands off it would hover: hold down to come in and land)
	var sf_land := -1
	var sf_vmax := 0.0
	for sfk4 in 1800:
		await _frames(1)
		if sf_sk.pos.length() < Defs.R_TOP:
			sf_vmax = maxf(sf_vmax, sf_sk.vel.length())
		if sf_sk.grounded and sf_sk.vel.length() < 0.5:
			sf_land = sfk4
			break
	g.test_down = false
	var sf_la: float = atan2(sf_sk.pos.y, sf_sk.pos.x)
	var sf_above: float = sf_sk.pos.length() - g.gpu.surf_at(sf_la).x
	var sf_with: bool = g.player.aboard == sf_sk and g.player.pos.distance_to(sf_sk.pos) < 30.0
	await _frames(20)
	var sf_out: bool = g._skiff_interact(g.player) and g.player.aboard == null
	await _frames(30)
	_ok("the Wisp Skiff: forged, called, boarded, flown into space and back, landed and left",
		sf_forged and sf_called and sf_settle >= 0 and sf_drift < 1.5 and sf_board and sf_up >= 0 and sf_back >= 0 and sf_land >= 0 and sf_with and sf_out and absf(sf_above) < 200.0 and sf_vmax < float(Skiff.CRUISE_HIGH) + 0.5 and sf_land > 40 and sf_scale.min() > 0.99 and sf_scale.max() < 1.01,
		"forged %s, called %s (%d x %d cells, %.0f mass); settled after %d ticks (then moved %.1f); aboard %s; out in space after %d ticks of flying up (from radius %.0f), %.0f past the band after 1.5 s more; back in the band after %d ticks; landed %d ticks later (fastest through the air %.1f a tick), %.0f above the ground line, you still aboard %s; stepped out %s; drawn cells per pixel while climbing %s" % [sf_forged, sf_called, sf_sk.w, sf_sk.h, sf_sk.mass, sf_settle, sf_drift, sf_board, sf_up, sf_r0, sf_far, sf_back, sf_land, sf_vmax, sf_above, sf_with, sf_out, str(sf_scale)])

	await _test_minimap()
	await _test_wrecks()
	await _test_pirates()
	await _test_outposts()
	await _test_stations()
	await _test_fuel()
	await _test_ships()
	await _test_cargo()
	await _test_voidlife()
	await _test_spacebench()

	# ---- to another planet in the skiff: Cindrel is made while you fly, then you land on it ----
	g.player.pos = sf_sk.pos
	var tv_board: bool = g._skiff_interact(g.player) and g.player.aboard == sf_sk
	var tv_up: Vector2 = sf_sk.pos.normalized()
	sf_sk.pos = tv_up * (Defs.R_SPACE - 11.0)
	sf_sk.vel = tv_up * 6.0
	sf_sk.grounded = false
	g.test_cast = true
	var tv_in := -1
	for tvk1 in 200:
		g.test_aim = sf_sk.pos + sf_sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			tv_in = tvk1
			break
	# ---- the Prospector's Beam: the pilot mines an asteroid from aboard ----
	g.space._ensure_rocks(true)
	var bm_r = g.space.nearest_rock(sf_sk.pos, 1e9)
	var bm_got := -1
	var bm_inv0 := 0
	var bm_inv1 := 0
	if bm_r != null:
		bm_r.omega = 0.0
		bm_r.vel = Vector2.ZERO
		var bm_dir: Vector2 = (sf_sk.pos - bm_r.pos).normalized()
		var bm_at: Vector2 = bm_r.pos + bm_dir * (bm_r.reach() + 70.0)
		g.items["beam"] = true
		var bm_c0: int = bm_r.count()
		for bm_v in g.player.inv:
			bm_inv0 += int(bm_v)
		g.test_cast = false
		g.test_dig = true
		for bm_f in 150:
			sf_sk.pos = bm_at
			sf_sk.vel = Vector2.ZERO
			bm_r.vel = Vector2.ZERO
			g.test_aim = bm_r.pos + bm_dir * (bm_r.reach() * 0.4)
			await _frames(1)
			if bm_f == 100:
				g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("beam.png"))
		g.test_dig = false
		g.test_cast = true
		g.items.erase("beam")
		bm_got = bm_c0 - bm_r.count()
		for bm_v2 in g.player.inv:
			bm_inv1 += int(bm_v2)
	_ok("the Prospector's Beam mines an asteroid from the skiff", bm_got >= 30 and bm_inv1 - bm_inv0 >= 30,
		"%d cells taken from the rock, %d into the satchel" % [bm_got, bm_inv1 - bm_inv0])
	var tv_to: Vector2 = Defs.planet_pos(1) - Defs.planet_pos(0)
	# ---- first with no Radiation Ward: Cindrel (a volcanic world) is wrapped in a radiation belt that
	# throws you back and burns (no invisible wall: you see it); then the ward is forged, and every radiation
	# belt lets you through (barriers by kind, 24 Nov) ----
	var tv_had: bool = g.items.has("radward")
	g.items.erase("radward")
	var tv_bar: String = Defs.barrier_of(1)
	var tv_space: float = float(Defs.make_planet(1)["radius"]) + Defs.ATMO + Defs.ORBIT_ROWS
	var tv_lim: float = tv_space + g.space.BELT_IN
	sf_sk.pos = tv_to - tv_to.normalized() * (tv_space + g.space.BELT_OUT + 300.0)
	sf_sk.vel = tv_to.normalized() * 30.0
	g.cam_c = sf_sk.pos
	var tv_lk_travel := false
	var tv_lk_min := 1e12
	g.space.belt_max = 0.0
	g.space.belt_hits = 0
	var tv_god0: bool = g.test_god
	g.test_god = true
	var tv_bk := 0.0
	var tv_bshot := false
	for tvl in 420:
		g.test_aim = Defs.planet_pos(1) - Defs.planet_pos(g.space.home) + Vector2(0.5, 0.5)
		await _frames(1)
		tv_lk_travel = tv_lk_travel or g.travelling or g.space.home != 0
		tv_lk_min = minf(tv_lk_min, (sf_sk.pos - tv_to).length())
		if not tv_bshot and g.space.belt > 0.35:
			tv_bshot = true
			await _frames(2)
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("belt_radiation.png"))
		if tvl > 360:
			tv_bk = maxf(tv_bk, -sf_sk.vel.dot(tv_to.normalized()))
	g.test_god = tv_god0
	# (the belt's lightning holed the hull: mended, as the journey's checks expect a whole skiff)
	var tv_hull: float = sf_sk.hull_f
	sf_sk.mend(100000)
	print("[travel] the storm belt left the hull at %.0f%%; mended" % (tv_hull * 100.0))
	var tv_locked: bool = not tv_lk_travel and tv_lk_min > tv_lim and g.space.belt_max > 0.2 and g.space.belt_hits > 0
	var tv_rec: Dictionary = {}
	for tv_r in g.recipes:
		if tv_r["id"] == "radward":
			tv_rec = tv_r
	for tv_k in tv_rec.get("cost", {}):
		g.player.inv[int(tv_k)] += int(tv_rec["cost"][tv_k])
	var tv_drive: bool = not tv_rec.is_empty() and g.craft(tv_rec) and g.space.reachable(1) and g.space.reachable(3)
	if not tv_had and not tv_drive:
		g.items["radward"] = true          # (so the journey's checks below still run)
	_ok("Cindrel's radiation belt keeps the skiff out; the Radiation Ward opens every radiation belt", tv_locked and tv_drive and tv_bar == "radiation",
		"Cindrel's barrier: %s; held off %s (closest %.0f from its centre, the belt's inner edge %.0f, deepest in it %.2f, %d burns, thrown back at up to %.1f a tick near the end, travel started %s); the Radiation Ward forged %s (Cindrel and Sere in reach)" % [tv_bar, not tv_lk_travel, tv_lk_min, tv_lim, g.space.belt_max, g.space.belt_hits, tv_bk, tv_lk_travel, tv_drive])
	# (most of the way there at once: the planet is made as you cover the rest)
	sf_sk.pos = tv_to * 0.7
	sf_sk.vel = tv_to.normalized() * 35.0
	g.cam_c = sf_sk.pos
	var tv_gap := 0
	var tv_gap_at := ""
	var tv_t0 := Time.get_ticks_usec()
	g.hitch_us = 0
	var tv_held := false
	var tv_shot := false
	var tv_arrive := -1
	var tv_back := -1
	var tv_draw := {"pre": 0, "draw": 0}
	var tv_pre := func() -> void:
		tv_draw["pre"] = Time.get_ticks_usec()
	var tv_post := func() -> void:
		tv_draw["draw"] = Time.get_ticks_usec() - int(tv_draw["pre"])
	RenderingServer.frame_pre_draw.connect(tv_pre)
	RenderingServer.frame_post_draw.connect(tv_post)
	for tvk2 in 2400:
		# (Cindrel's centre; nudged off zero, which would mean "follow the mouse")
		g.test_aim = Defs.planet_pos(1) - Defs.planet_pos(g.space.home) + Vector2(0.5, 0.5)
		await _frames(1)
		var tv_now := Time.get_ticks_usec()
		if tv_now - tv_t0 > 150000:
			var tv_big := []
			for tv_sec in g.prof:
				if float(g.prof[tv_sec][3]) > 30000.0:
					tv_big.append("%s %.0f" % [tv_sec, float(g.prof[tv_sec][3]) / 1000.0])
			print("[travel] a %.0f ms frame at tick %d (%s): %s; process %.0f ms, physics %.0f ms, GPU wait %.0f ms, game's own %.0f ms, drawing %.0f ms, live %s, space %s" % [(tv_now - tv_t0) / 1000.0, tvk2,
				"arrived" if tv_arrive >= 0 else "on the way", ", ".join(tv_big), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, g.gpu.wait_us / 1000.0, g.hitch_us / 1000.0, float(tv_draw["draw"]) / 1000.0, str(g.space.live), str(g.space.active)])
			g.hitch_us = 0
		g.prof_reset()
		if tv_now - tv_t0 > tv_gap:
			tv_gap = tv_now - tv_t0
			tv_gap_at = "tick %d, %s, made %.2f" % [tvk2, "travelling" if g.travelling else ("arrived %d ticks before" % (tvk2 - tv_arrive) if tv_arrive >= 0 else "before arriving"), g.travel_progress]
		tv_t0 = tv_now
		if g.travelling and sf_sk.vel.length() < 1.0:
			tv_held = true
		if tv_arrive < 0 and g.space.home == 1:
			tv_arrive = tvk2
		if not tv_shot and tv_arrive >= 0 and g.zoom < 12.0:
			tv_shot = true
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("arrival.png"))
			tv_t0 = Time.get_ticks_usec()       # (the picture's own saving isn't the game's frame)
		if tv_arrive >= 0 and not g.space.active:
			tv_back = tvk2
			break
	RenderingServer.frame_pre_draw.disconnect(tv_pre)
	RenderingServer.frame_post_draw.disconnect(tv_post)
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	var tv_land := -1
	for tvk3 in 1800:
		await _frames(1)
		if sf_sk.grounded and sf_sk.vel.length() < 0.5:
			tv_land = tvk3
			break
	g.test_down = false
	await _frames(30)
	var tv_la: float = atan2(sf_sk.pos.y, sf_sk.pos.x)
	var tv_above: float = sf_sk.pos.length() - g.gpu.surf_at(tv_la).x
	var tv_with: bool = g.player.aboard == sf_sk and g.player.pos.distance_to(sf_sk.pos) < 30.0
	var tv_saved: bool = FileAccess.file_exists(g._world_path(0)) and FileAccess.file_exists(g._world_path(1))
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("new_planet.png"))
	_ok("the skiff carries you to another planet, made while you fly, and you land on it",
		tv_board and tv_in >= 0 and tv_arrive >= 0 and tv_back >= 0 and tv_land >= 0 and int(g.planet["index"]) == 1 and absf(Defs.RS0 - float(g.planet["radius"])) < 0.5 and tv_with and absf(tv_above) < 200.0 and tv_saved and tv_gap < 250000,
		"aboard %s; out after %d ticks; %s made and moved over to after %d ticks (held off while it was made: %s; longest frame %.0f ms at %s); in its orbit band %d ticks later, landed %d ticks after that, %.0f above its ground line (radius %.0f), you aboard %s; both worlds saved %s" % [tv_board, tv_in, g.planet["name"], tv_arrive, tv_held, tv_gap / 1000.0, tv_gap_at, tv_back - tv_arrive, tv_land, tv_above, Defs.RS0, tv_with, tv_saved])

	await _test_galaxy()

	# ---- a planet of another size: Fenhollow is laid out and generated to fit ----
	var sp_t := Time.get_ticks_msec()
	g._enter_planet(4)
	var sp_ms := Time.get_ticks_msec() - sp_t
	await _frames(60)
	var sp_a: float = atan2(g.player.pos.y, g.player.pos.x)
	var sp_off: float = g.player.pos.length() - g.gpu.surf_at(sp_a).x
	_ok("a planet of another size is laid out and generated to fit", absf(Defs.RS0 - float(g.planet["radius"])) < 0.5 and Defs.RS0 < float(Defs.make_planet(0)["radius"]) and absf(sp_off) < 40.0 and g.builds.infos.size() >= 5,
		"%s: radius %.0f, %d surface columns, %d shells (%.1f M cells); generated in %d ms; you stand %.1f from the surface; %d structures" % [g.planet["name"], Defs.RS0, Defs.NS, Defs.NSH, Defs.total_cells() / 1000000.0, sp_ms, sp_off, g.builds.infos.size()])
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("small_planet.png"))

	await _test_far_biomes()
	await _test_abyss()
	await _test_giant()
	await _test_star()
	await _test_void()
	await _test_cores()
	await _test_newbiomes()
	await _test_worlds()
	await _test_bench()

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
