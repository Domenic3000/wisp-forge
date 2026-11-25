extends "res://scripts/tests/exotic.gd"
## The busy-scene benchmark and the new-game start-up trace. (Part of the chain of test files: see tests.gd.)

func _test_bench() -> void:
	var bn_god0: bool = g.test_god
	var bn_wild0: bool = g.test_no_wild
	var bn_pos0: Vector2 = g.player.pos
	g.test_god = true
	g.test_no_wild = true
	# (well away from where you arrived: its fires, pit and sand would spoil the wild-life checks set up there)
	var bn_st := _clear_stretch(Build.cell_of(start_pos).x + 1400, 200, 60)
	var bn_a: float = (float(bn_st.x) + 100.5) / float(Defs.NS) * TAU
	var bn_up := Vector2(cos(bn_a), sin(bn_a))
	var bn_side: Vector2 = g.basis_r(bn_a)
	var bn_ground: float = g.gpu.surf_at(bn_a).x
	_go(bn_up * (bn_ground + 14.0))
	await _frames(40)
	var bn_kinds := ["c_frostwolf", "c_boar", "c_hyena", "c_jackal", "c_ram", "c_deer", "skeleton", "skeleton", "slime", "bat"]
	var bn_foes := []
	for bn_k in 24:
		var bn_t: String = bn_kinds[bn_k % bn_kinds.size()]
		var bn_off := (40.0 + 7.0 * float(bn_k)) * (1.0 if bn_k % 2 == 0 else -1.0)
		var bn_p: Vector2 = g.player.pos + bn_side * bn_off + bn_up * (30.0 if bn_t == "bat" else 6.0)
		var bn_e = g.spawn_enemy(bn_t, g.free_spot(bn_p, 14.0, 14.0, 20))
		bn_e.provoked = true
		bn_e.alert_t = 600
		bn_e.seen_pos = g.player.pos
		bn_foes.append(bn_e)
	var bn_rain0: float = g.rain
	g.rain = 1.0
	g.rain_target = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(g.get_viewport().get_viewport_rid(), true)
	await _frames(20)
	g.prof_reset()
	g.hitch_us = 0
	var bn_times := []
	var bn_prev := {}
	var bn_shown := 0
	var bn_t0 := Time.get_ticks_usec()
	var bn_gdraw := 0.0
	var bn_gsim := 0.0
	for bn_f in 600:
		g.player.hp = g.player.max_hp
		if bn_f % 20 == 0:
			var bn_dir: Vector2 = (bn_side * (1.0 if (bn_f / 20) % 2 == 0 else -1.0) + bn_up * 0.15).normalized()
			g._spawn_proj("fireball", g.player.pos + bn_up * 4.0, bn_dir * 3.9, "player")
		# digging beside you all the while
		g.brushes.append([g.player.pos + bn_side * 18.0 * (1.0 if (bn_f / 90) % 2 == 0 else -1.0) - bn_up * 6.0, 7.5, 1, 0, 2, 0.0, 0, 0])
		if bn_f % 150 == 0:
			# sand poured from above
			var bn_c: Vector2i = Build.cell_of(g.player.pos + bn_up * 60.0 + bn_side * 30.0)
			var bn_d := PackedInt32Array()
			bn_d.resize(30 * 14)
			bn_d.fill(Defs.SAND | 0xFF00)
			g.stamps.append({"x0": bn_c.x, "y0": bn_c.y, "w": 30, "h": 14, "data": bn_d})
		await _frames(1)
		var bn_now := Time.get_ticks_usec()
		bn_times.append(bn_now - bn_t0)
		bn_gdraw += RenderingServer.viewport_get_measured_render_time_gpu(g.get_viewport().get_viewport_rid())
		for bn_gk in g.gpu.gpu_us:
			bn_gsim += float(g.gpu.gpu_us[bn_gk]) / 1000.0
		if bn_now - bn_t0 > 50000 and bn_shown < 14:
			# a slow frame: the parts whose worst grew in it
			bn_shown += 1
			var bn_grew := []
			for bn_s2 in g.prof:
				var bn_m := float(g.prof[bn_s2][4])
				if bn_m > 3000.0:
					bn_grew.append("%s %.1f" % [bn_s2, bn_m / 1000.0])
			var bn_vp: RID = g.get_viewport().get_viewport_rid()
			print("[bench] frame %d: %.0f ms (%s; process %.1f ms, the screen's drawing: CPU %.1f ms, GPU %.1f ms, set-up %.1f ms)" % [bn_f, (bn_now - bn_t0) / 1000.0, ", ".join(bn_grew),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(bn_vp),
				RenderingServer.viewport_get_measured_render_time_gpu(bn_vp), RenderingServer.get_frame_setup_time_cpu()])
		for bn_s3 in g.prof:
			bn_prev[bn_s3] = float(g.prof[bn_s3][3])
		bn_t0 = bn_now
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	bn_times.sort()
	var bn_sum := 0
	for bn_v in bn_times:
		bn_sum += int(bn_v)
	var bn_avg := float(bn_sum) / bn_times.size() / 1000.0
	var bn_p95 := float(bn_times[int(bn_times.size() * 0.95)]) / 1000.0
	var bn_worst := float(bn_times[-1]) / 1000.0
	var bn_alive := 0
	for bn_e2 in bn_foes:
		if not bn_e2.dead and g.enemies.has(bn_e2):
			bn_alive += 1
	var bn_txt: String = g.prof_text(20, "; ")
	# (and the worst single frame of each part)
	var bn_mx := []
	for bn_s in g.prof:
		bn_mx.append([float(g.prof[bn_s][3]), bn_s])
	bn_mx.sort()
	bn_mx.reverse()
	var bn_mxt := []
	for bn_i in mini(12, bn_mx.size()):
		bn_mxt.append("%s %.1f" % [bn_mx[bn_i][1], float(bn_mx[bn_i][0]) / 1000.0])
	print("[bench] the worst frame of each part (ms): " + "; ".join(bn_mxt))
	var bn_hist := [0, 0, 0, 0, 0]
	for bn_v2 in bn_times:
		var bn_ms := float(bn_v2) / 1000.0
		bn_hist[0 if bn_ms < 8.0 else (1 if bn_ms < 16.7 else (2 if bn_ms < 33.0 else (3 if bn_ms < 66.0 else 4)))] += 1
	print("[bench] frames under 8 ms %d, 8-16.7 %d, 16.7-33 %d, 33-66 %d, over 66 %d" % bn_hist)
	print("[bench] %.2f ms a frame on average, 95%% under %.2f, the worst %.1f (the game's own %.1f); foes %d, particles %d, vfx %d; %s" % [bn_avg, bn_p95, bn_worst,
		g.hitch_us / 1000.0, g.enemies.size(), g.parts.size(), g.vfx.count(), bn_txt])
	_ok("a busy scene holds 60 fps with room to spare", bn_avg < 16.7 and bn_p95 < 25.0,
		"%.2f ms on average, 95%% of frames under %.2f ms, the worst %.1f ms (GPU: drawing %.2f, simulation %.2f a frame); %d of 24 foes left; %s" % [bn_avg, bn_p95, bn_worst, bn_gdraw / 600.0, bn_gsim / 600.0, bn_alive, bn_txt])
	# the same busy scene at low quality (bigger pixels, fewer passes): what a weaker PC would choose
	var bn_q0: String = g.settings["quality"]
	var bn_low := func(f: int) -> void:
		g.player.hp = g.player.max_hp
		if f % 20 == 0:
			var bn_dir2: Vector2 = (bn_side * (1.0 if (f / 20) % 2 == 0 else -1.0) + bn_up * 0.15).normalized()
			g._spawn_proj("fireball", g.player.pos + bn_up * 4.0, bn_dir2 * 3.9, "player")
		g.brushes.append([g.player.pos + bn_side * 18.0 * (1.0 if (f / 90) % 2 == 0 else -1.0) - bn_up * 6.0, 7.5, 1, 0, 2, 0.0, 0, 0])
	var bn_hr: Dictionary = await _bench_measure(300, bn_low)
	print("[bench] " + _bench_line("again at high quality", bn_hr))
	g.set_setting("quality", "low")
	await _frames(20)
	var bn_lr: Dictionary = await _bench_measure(300, bn_low)
	g.set_setting("quality", bn_q0)
	await _frames(20)
	print("[bench] " + _bench_line("the same at low quality", bn_lr))
	_ok("the busy scene at low quality costs less", bn_lr["avg"] < bn_hr["avg"], _bench_line("high quality", bn_hr) + " | " + _bench_line("low quality", bn_lr))
	# Auto quality: frames slower than 50 a second for its window step it down a level, remembered; a fast
	# machine stays where it is
	var aq_keep: Dictionary = g.settings.duplicate()
	g.settings["quality"] = "auto"
	g.settings["auto_q"] = "high"
	g.auto_test = true
	g._aq_wait = 0
	g._aq_t = 0.0
	g._aq_n = 0
	for aq_k in 300:
		g._auto_quality(1.0 / 60.0)
	var aq_fast: String = g.quality()
	for aq_k2 in 160:
		g._auto_quality(0.03)
	var aq_one: String = g.quality()
	g._aq_wait = 0
	for aq_k3 in 160:
		g._auto_quality(0.03)
	var aq_two: String = g.quality()
	g._aq_wait = 0
	for aq_k4 in 160:
		g._auto_quality(0.03)
	var aq_floor: String = g.quality()
	g.auto_test = false
	g.settings = aq_keep
	g.gpu.apply_quality(g.quality())
	g._fxb = g.fx_budget()
	g._layout()
	g._save_settings()
	await _frames(20)
	_ok("Auto quality steps down on a slow machine (high, medium, low) and stays put on a fast one", aq_fast == "high" and aq_one == "medium" and aq_two == "low" and aq_floor == "low",
		"at 60 fps: %s; at 33 fps: %s, then %s, then %s" % [aq_fast, aq_one, aq_two, aq_floor])
	for bn_e3 in bn_foes:
		g.enemies.erase(bn_e3)
	g.projs.clear()
	RenderingServer.viewport_set_measure_render_time(g.get_viewport().get_viewport_rid(), false)
	g.rain = bn_rain0
	g.rain_target = bn_rain0
	_go(bn_pos0)
	await _frames(60)
	g.test_god = bn_god0
	g.test_no_wild = bn_wild0

## A new journey as the player starts one (user, 22 Nov: "there is a small hitch when starting a new
## game"): the title, then Play on an empty slot (a grown system, not the classic one), then the first
## ten seconds traced frame by frame, every frame over 20 ms printed with its parts over 3 ms.
func _test_newgame() -> void:
	g.ui.show_title(true)
	g.state = "title"
	await _frames(90)
	g.test_seed = 4242
	var ng_t0 := Time.get_ticks_msec()
	await g.start_game(false)
	var ng_ms := Time.get_ticks_msec() - ng_t0
	print("[newgame] made %s in %d ms" % [String(g.planet.get("name", "?")), ng_ms])
	g.prof_reset()
	g.hitch_us = 0
	# (as in a real game: creatures come by, the first of them a few seconds in)
	g.test_no_wild = false
	await _trace_frames("newgame", 900, 20.0, 3.0)
	g.test_no_wild = true
	var ng_foes := 0
	for e in g.enemies:
		if not e.boss:
			ng_foes += 1
	print("[newgame] %d foes came by; draw calls %d, objects %d" % [ng_foes, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
	_ok("a new journey starts without a hitch", g.hitch_us < 50000, "the game's longest frame of its own work %.0f ms (made in %d ms)" % [g.hitch_us / 1000.0, ng_ms])
	# the two-minute autosave: copied on the GPU, read back a slice a frame, written on a thread
	await g.saves_done()
	var ng_path: String = g._world_path(int(g.planet["index"]))
	var ng_m0 := FileAccess.get_modified_time(ng_path)
	await _frames(70)                    # (file times are whole seconds)
	g.hitch_us = 0
	g.prof_reset()
	g.autosave_log.clear()
	g._autosave_begin()
	var ng_frames := 0
	while not g._autosave.is_empty() and ng_frames < 900:
		await _frames(1)
		ng_frames += 1
	var ng_parts := []
	for ng_s in g.prof:
		if float(g.prof[ng_s][3]) > 3000.0:
			ng_parts.append("%s %.1f" % [ng_s, float(g.prof[ng_s][3]) / 1000.0])
	print("[autosave] the worst of each part (ms): %s; slices %d, the slowest %d us" % [", ".join(ng_parts), g.autosave_log.size(), g.autosave_log.max() if not g.autosave_log.is_empty() else 0])
	var ng_hitch: int = g.hitch_us
	await g.saves_done()
	var ng_m1 := FileAccess.get_modified_time(ng_path)
	_ok("the autosave goes on while you play", g._autosave.is_empty() and ng_m1 > ng_m0 and ng_hitch < 20000,
		"read back over %d frames, the longest frame %.0f ms, the file written: %s" % [ng_frames, ng_hitch / 1000.0, ng_m1 > ng_m0])
	g.test_seed = 0
