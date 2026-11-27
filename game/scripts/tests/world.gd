extends "res://scripts/tests/creatures.gd"
## Checks of the planet: sky and weather, fog, the backdrop into space, grown worlds, stamps, far biomes. (Part of the chain of test files: see tests.gd.)

func _test_sky() -> void:
	var sk_god0: bool = g.test_god
	var sk_from: Vector2 = g.player.pos
	g.test_god = true
	g.spawn_timer = 999999
	var sk_st := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) + 40, 60, 80, 6)
	var sk_a: float = (float(sk_st.x) + 8.5) / float(Defs.NS) * TAU
	var sk_at: Vector2 = Vector2(cos(sk_a), sin(sk_a)) * (g.gpu.surf_at(sk_a).x + 12.0)
	var sk_time0: float = g.time
	var sk_day: float = fposmod((sk_a - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)
	var sk_night: float = fposmod((sk_a + PI - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)
	var sk_dir: String = g._real_save_dir().path_join("shots")
	g.sky_stats = {}
	var sk_ok := {}
	var sk_txt := []
	for sk_id in ["meteors", "eruption", "squall", "sandstorm", "wisps", "aurora", "hail", "bloodmoon", "fireworks"]:
		for sk_e in g.enemies.duplicate():
			if not sk_e.boss and sk_e.guard_id < 0:
				g.enemies.erase(sk_e)
		g.time = sk_night if String(Defs.SKY_EVENTS[sk_id]["when"]) == "night" else sk_day
		_go(sk_at)
		await _frames(10)
		g.start_sky_event(sk_id)
		g.sky_t = 300                     # (straight to its full strength)
		g._sky_next = 10
		var sk_frames := {"meteors": 170, "eruption": 260, "squall": 200, "sandstorm": 150, "wisps": 30, "aurora": 120, "hail": 200, "bloodmoon": 60, "fireworks": 220}
		var sk_n: int = sk_frames[sk_id]
		var sk_hp0: float = g.player.hp
		var sk_w0: int = g.player.inv[Defs.WISP]
		var sk_wind := 0.0
		var sk_tint := 0.0
		if sk_id == "meteors":
			g._sky_next = 9999
			g.meteor_fall(44.0, 0.0)          # (straight down: on a slant it can meet a building first)
		if sk_id == "hail":
			g.test_god = false
			g.player.hp = g.player.max_hp
			sk_hp0 = g.player.hp
		if sk_id == "aurora":
			g.player.mana = 0.0
		for sk_f in sk_n:
			if sk_id == "wisps" and not g.sky_wisps.is_empty():
				g.player.pos = g.sky_wisps[0]["pos"]
			await _frames(1)
			sk_wind = maxf(sk_wind, absf(g.wind))
			sk_tint = maxf(sk_tint, g.sky_tint.a)
			if sk_f == int(sk_n * 0.6):
				g.get_viewport().get_texture().get_image().save_png(sk_dir.path_join("sky_%s.png" % sk_id))
		var st: Dictionary = g.sky_stats
		match sk_id:
			"meteors":
				var sk_si := 0
				var sk_mr := 0
				if st.has("meteor_at"):
					await _frames(12)
					var sk_p: Vector2 = st["meteor_at"]
					var sk_c := int(fposmod(atan2(sk_p.y, sk_p.x), TAU) / TAU * Defs.NS)
					var sk_r: int = Defs.row_at(sk_p.length())
					var sk_rr: Dictionary = g.gpu.read_rect(sk_c - 16, sk_r - 16, 32, 32, sk_c - 16, 32)
					for sk_v in sk_rr["fg"]:
						if (sk_v & 255) == Defs.STARIRON:
							sk_si += 1
						elif (sk_v & 255) == Defs.MAGMAROCK:
							sk_mr += 1
				sk_ok[sk_id] = int(st.get("meteorites", 0)) >= 1 and sk_si >= 1 and sk_mr >= 6
				sk_txt.append("meteors: %d fell, %d landed, star iron %d and seared rock %d where it hit" % [int(st.get("meteor_falls", 0)), int(st.get("meteorites", 0)), sk_si, sk_mr])
			"eruption":
				sk_ok[sk_id] = int(st.get("bombs", 0)) >= 3 and int(st.get("bomb_hits", 0)) >= 1 and sk_tint > 0.05
				sk_txt.append("eruption: %d lava bombs, %d landed, glow %.2f" % [int(st.get("bombs", 0)), int(st.get("bomb_hits", 0)), sk_tint])
			"squall":
				sk_ok[sk_id] = int(st.get("strikes", 0)) >= 1 and sk_wind > 0.1
				sk_txt.append("squall: %d lightning strikes, wind up to %.2f" % [int(st.get("strikes", 0)), sk_wind])
			"sandstorm":
				sk_ok[sk_id] = sk_tint > 0.2 and sk_wind > 0.1
				sk_txt.append("sandstorm: haze %.2f, wind up to %.2f" % [sk_tint, sk_wind])
			"wisps":
				sk_ok[sk_id] = int(st.get("caught", 0)) >= 1 and g.player.inv[Defs.WISP] > sk_w0
				sk_txt.append("wisps: caught %d, wisp ore %d -> %d" % [int(st.get("caught", 0)), sk_w0, g.player.inv[Defs.WISP]])
			"aurora":
				sk_ok[sk_id] = float(st.get("aurora_mana", 0.0)) > 1.0 and g.sky_level("aurora") > 0.5
				sk_txt.append("aurora: %.1f extra mana under it (open sky %s)" % [float(st.get("aurora_mana", 0.0)), g.exposed])
			"hail":
				# (its own stones, bouncing and lying on the ground: not rain cells, which it doesn't drop)
				var sk_ws: Dictionary = g.weather.stats
				sk_ok[sk_id] = int(st.get("hail_hits", 0)) >= 1 and g.player.hp < sk_hp0 and int(sk_ws["hail_bounces"]) >= 5 and int(sk_ws["landed"]) >= 3 and float(g.gpu.params[12]) == 0.0
				sk_txt.append("hail: %d stings, health %.0f -> %.0f, %d stones bounced, %d lay on the ground, rain cells %.4f" % [int(st.get("hail_hits", 0)), sk_hp0, g.player.hp, int(sk_ws["hail_bounces"]), int(sk_ws["landed"]), float(g.gpu.params[12])])
				g.test_god = true
				g.player.hp = g.player.max_hp
			"bloodmoon":
				sk_ok[sk_id] = g.spawn_mult() > 2.0 and g.sky_level("bloodmoon") > 0.5
				sk_txt.append("blood moon: creatures x%.1f" % g.spawn_mult())
			"fireworks":
				sk_ok[sk_id] = int(st.get("bursts", 0)) >= 2
				sk_txt.append("fireworks: %d bursts" % int(st.get("bursts", 0)))
		g.end_sky_event()
	g.time = sk_time0
	# rain: streaks over the falling drops, splashing where they land (only where it rains here)
	if String(g._biome_at(sk_a)["weather"]) == "rain":
		_go(sk_at)
		g.time = sk_day
		var sk_r0: int = int(g.weather.stats["rain_splashes"])
		g.rain_target = 1.0
		g.rain = 1.0
		g.sky_rain = 1.0
		g.weather_timer = 99999
		await _frames(120)
		g.get_viewport().get_texture().get_image().save_png(sk_dir.path_join("sky_rain.png"))
		var sk_sp: int = int(g.weather.stats["rain_splashes"]) - sk_r0
		sk_ok["rain"] = sk_sp >= 10
		sk_txt.append("rain: %d splashes" % sk_sp)
		g.rain_target = 0.0
		g.rain = 0.0
		g.sky_rain = 0.0
		g.weather_timer = 1800
	g.time = sk_time0
	_go(sk_from)                              # (back where it found you: its lava and fires stay there)
	await _frames(20)
	g.test_god = sk_god0
	g.spawn_timer = 600
	var sk_all := true
	var sk_bad := []
	for sk_k in sk_ok:
		if not bool(sk_ok[sk_k]):
			sk_all = false
			sk_bad.append(sk_k)
	_ok("sky events: each kind of planet's meteors, eruptions, squalls, sandstorms, wisps, auroras, hail, blood moons and fireworks", sk_all and sk_ok.size() >= 9,
		"; ".join(sk_txt) + ("" if sk_all else " (not working: %s)" % ", ".join(sk_bad)))

## Fog over the underground you haven't seen (user, 21 Nov): ground far under you is fogged on screen, a
## pocket you've stood in is clear once you've gone, the fog's edge falls off over several cells, and the
## seen map goes with the save (a picture: saves/shots/fog.png).
func _test_fog() -> void:
	var fg_god0: bool = g.test_god
	g.test_god = true
	var fg_orig: Vector2 = g.player.pos
	var fg_a := atan2(fg_orig.y, fg_orig.x)
	var fg_surf: float = g.gpu.surf_at(fg_a).x
	var fg_up := Vector2(cos(fg_a), sin(fg_a))
	var fg_side: Vector2 = g.basis_r(fg_a)
	var fg_top: Vector2 = fg_up * (fg_surf + 14.0)
	# (from a clean slate: the checks before this one went about underground round here)
	g.gpu.flush()
	g.gpu.rd.buffer_clear(g.gpu.seen_buf, 0, g.gpu.seen_bytes())
	_go(fg_top)
	await _frames(30)
	# (90 under the lower of the ground here and the ground over it: on a slope the far side may lie well below)
	var fg_fa: float = atan2((fg_up * fg_surf + fg_side * 70.0).y, (fg_up * fg_surf + fg_side * 70.0).x)
	var fg_low: float = minf(fg_surf, g.gpu.surf_at(fg_fa).x)
	var fg_far: Vector2 = fg_up * (fg_low - 90.0) + fg_side * 70.0
	var fg_clear := func(p: Vector2) -> float:
		return g.gpu.light_at(g.world_to_pic(p)).a
	var fg_a0: float = fg_clear.call(fg_far)
	# a pocket down there to stand in
	var fg_c: Vector2i = Build.cell_of(fg_far)
	var fg_d := PackedInt32Array()
	fg_d.resize(24 * 30)
	fg_d.fill(Defs.AIR | 0xFF00)
	g.stamps.append({"x0": fg_c.x - 12, "y0": fg_c.y - 15, "w": 24, "h": 30, "data": fg_d, "ax": fg_c.x - 12, "aw": 24})
	await _frames(3)
	_go(fg_far)
	await _frames(40)
	_go(fg_top)
	await _frames(20)
	var fg_a1: float = fg_clear.call(fg_far)
	var fg_a2: float = fg_clear.call(fg_far + fg_side * 110.0)
	# the edge: from the pocket outward, along and down
	var fg_mid := 0
	var fg_jump := 0.0
	var fg_prev: float = fg_a1
	var fg_line := []
	for fg_k in range(1, 31):
		var fg_v: float = fg_clear.call(fg_far + (fg_side * 0.8 - fg_up * 0.6) * float(fg_k) * 3.0)
		if fg_v > 0.15 and fg_v < 0.85:
			fg_mid += 1
		fg_jump = maxf(fg_jump, absf(fg_v - fg_prev))
		fg_prev = fg_v
		if fg_k % 3 == 0:
			fg_line.append("%.2f" % fg_v)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("fog.png"))
	# kept with the world: without the seen map the pocket is fogged again, with it clear
	var fg_raw: PackedByteArray = g.gpu.read_world(true)
	var fg_n: int = Defs.total_cells() * 8
	var fg_seen: PackedByteArray = fg_raw.slice(fg_n)
	var fg_any: bool = fg_seen.size() == g.gpu.seen_bytes() and fg_seen.count(0) < fg_seen.size()
	g.gpu.write_world(fg_raw.slice(0, fg_n))
	await _frames(6)
	var fg_a3: float = fg_clear.call(fg_far)
	g.gpu.write_world(fg_raw)
	await _frames(6)
	var fg_a4: float = fg_clear.call(fg_far)
	var fg_ok: bool = fg_a0 < 0.25 and fg_a1 > 0.8 and fg_a2 < 0.25 and fg_mid >= 3 and fg_jump < 0.45 and fg_any and fg_a3 < 0.25 and fg_a4 > 0.8
	_ok("fog lies over the underground you haven't seen, lifts where you've been, falls off softly and is saved",
		fg_ok, "unseen ground %.2f clear; the pocket you stood in %.2f after; 110 cells on %.2f; edge %s (%d between, steepest step %.2f); seen map kept %s, without it %.2f, with it %.2f" % [
		fg_a0, fg_a1, fg_a2, ", ".join(fg_line), fg_mid, fg_jump, str(fg_any), fg_a3, fg_a4])
	g.test_god = fg_god0
	_go(fg_orig)
	await _frames(20)

## The background and the way into space (user, 22 Nov: "the retro pixel filter seems to end at the space
## border, and the transition to space is still jaring. There are also still sharp borders in the
## background"): pictures with the retro filter on of a biome border by day and night, high in the sky, and
## just out in space; the sky's top is clear over space's own stars there.
func _test_backdrop() -> void:
	var bd_back: Vector2 = g.player.pos
	var bd_t0: float = g.time
	var bd_d0: String = g.settings["dither"]
	g.settings["dither"] = "retro"
	g.rain = 0.0
	g.rain_target = 0.0
	g.weather_timer = 999999
	var bd_dir: String = g._real_save_dir().path_join("shots")
	# a biome border near where you arrived
	var a0: float = atan2(g.player.pos.y, g.player.pos.x)
	var b0 := int(g.gpu.surf_at(a0).y)
	var ab := a0
	for k in 2000:
		ab = a0 + float(k) * 6.0 / Defs.RS0
		if int(g.gpu.surf_at(ab).y) != b0:
			break
	var up := Vector2(cos(ab), sin(ab))
	_go(up * (g.gpu.surf_at(ab).x + 14.0))
	for bd_h in [12.0, 23.0]:
		g.time = g.towns.time_for_hour(g.player.pos, bd_h)
		await _frames(45)
		g.get_viewport().get_texture().get_image().save_png(bd_dir.path_join("bg_border_%s.png" % ("day" if bd_h < 20.0 else "night")))
	# high in the sky, then just out in space
	g.time = g.towns.time_for_hour(g.player.pos, 12.0)
	g.test_god = true
	_go(up * (Defs.R_TOP - 30.0))
	g.test_jump = true
	await _frames(30)
	var bd_back_on: bool = g.space.backdrop() and g.space.visible
	g.get_viewport().get_texture().get_image().save_png(bd_dir.path_join("bg_high.png"))
	_go(up * (Defs.R_SPACE - 40.0))
	var bd_in := false
	for k2 in 240:
		g.player.mana = g.player.max_mana
		await _frames(1)
		if g.space.active:
			bd_in = true
			break
	g.test_jump = false
	await _frames(8)
	g.get_viewport().get_texture().get_image().save_png(bd_dir.path_join("bg_orbit.png"))
	# (is the sky's top clear over space's stars: the picture's top row, above the atmosphere)
	var bd_clear := false
	if g.gpu.view_img != null:
		var bd_px: Color = g.gpu.view_img.get_pixel(g.gpu.PMX + g.VW / 2, g.gpu.PMY + 2)
		bd_clear = bd_px.a < 0.5
	# back down
	g.test_cast = true
	for k3 in 1800:
		g.test_aim = g.player.pos * 0.5
		g.player.mana = g.player.max_mana
		await _frames(1)
		if not g.space.active:
			break
	g.test_cast = false
	g.settings["dither"] = bd_d0
	g.time = bd_t0
	_go(bd_back)
	await _frames(40)
	_ok("high up, the sky thins into space's own stars, the pixel filter over all of it", bd_back_on and bd_in and bd_clear,
		"stars behind the sky's top %s; out in space %s; the picture clear over them %s (pictures bg_border_day/night, bg_high, bg_orbit)" % [bd_back_on, bd_in, bd_clear])

## every game grows a system of its own: the rules for many seeds, and one random planet made for real
func _test_worlds() -> void:
	# ---- every game grows a system of its own (Defs.world_seed): the rules hold for many seeds ----
	var wd_bad := []
	var wd_names := {}
	var wd_g0 := 0
	var wd_gl := 0.0
	var wd_kinds := {}
	var wd_rmin := 1e9
	var wd_rmax := 0.0
	for wd_s in range(1, 41):
		var wd_seen := []
		var wd_pos := []
		for wd_i in 5:
			var wd_p: Dictionary = Defs.make_planet_for(wd_s * 7919, wd_i)
			var wd_bl: Array = wd_p["biomes"]
			var wd_gs: Array = wd_p.get("guardians", [])
			wd_kinds[wd_p["kind"]] = int(wd_kinds.get(wd_p["kind"], 0)) + 1
			wd_rmin = minf(wd_rmin, float(wd_p["radius"]))
			wd_rmax = maxf(wd_rmax, float(wd_p["radius"]))
			if wd_i == 0:
				wd_g0 += wd_gs.size()
				var wd_friendly := false
				for wd_b in wd_bl:
					wd_friendly = wd_friendly or (int(Defs.BIOMES[wd_b]["flags"]) & 8) != 0
				if wd_p["kind"] != "temperate" or not wd_friendly:
					wd_bad.append("seed %d: the first planet isn't a temperate one to start on" % wd_s)
			else:
				wd_gl += wd_gs.size()
			if wd_bl.size() < 3 or wd_bl.size() > 8:
				wd_bad.append("seed %d planet %d: %d biomes" % [wd_s, wd_i, wd_bl.size()])
			for wd_b2 in wd_bl:
				if not Defs.BIOMES.has(wd_b2) or not Defs.BOSSES.has(wd_b2):
					wd_bad.append("seed %d planet %d: biome %s" % [wd_s, wd_i, wd_b2])
			if wd_bl.has("ocean") and float(wd_p["sea"]) <= 0.0:
				wd_bad.append("seed %d planet %d: ocean but no sea" % [wd_s, wd_i])
			if wd_gs.is_empty() or wd_gs.size() > wd_bl.size():
				wd_bad.append("seed %d planet %d: %d guardians" % [wd_s, wd_i, wd_gs.size()])
			if wd_seen.has(wd_p["name"]):
				wd_bad.append("seed %d: two planets called %s" % [wd_s, wd_p["name"]])
			wd_seen.append(wd_p["name"])
			wd_names[wd_p["name"]] = true
			var wd_st := Defs.biome_starts(wd_p)
			if wd_st.size() != wd_bl.size() or wd_st[0] != 0.0:
				wd_bad.append("seed %d planet %d: biome starts %s" % [wd_s, wd_i, str(wd_st)])
		# where they hang: apart from each other, none on top of home
		var wd_keep: int = Defs.world_seed
		Defs.world_seed = wd_s * 7919
		for wd_k in 5:
			wd_pos.append(Defs.planet_pos(wd_k))
		Defs.world_seed = wd_keep
		for wd_k1 in 5:
			for wd_k2 in range(wd_k1 + 1, 5):
				if (wd_pos[wd_k1] as Vector2).distance_to(wd_pos[wd_k2]) < 25000.0:
					wd_bad.append("seed %d: planets %d and %d %.0f apart" % [wd_s, wd_k1, wd_k2, (wd_pos[wd_k1] as Vector2).distance_to(wd_pos[wd_k2])])
	var wd_rules_ok := wd_bad.is_empty() and wd_names.size() > 120 and wd_kinds.size() >= 7 and wd_kinds.has("realm")
	_ok("every game grows a system of its own (40 seeds: a temperate world first, sound biomes, seas, names, places)", wd_rules_ok,
		"%d names among 200 planets; kinds %s; radius %.0f-%.0f; guardians on the first planet %.1f, on the others %.1f; %s" % [wd_names.size(), str(wd_kinds),
		wd_rmin, wd_rmax, float(wd_g0) / 40.0, wd_gl / 160.0, "; ".join(wd_bad.slice(0, 6)) if not wd_bad.is_empty() else "all sound"])
	# ---- and one of them made for real: the planet of a new game, guardians where it says ----
	var wd_god0: bool = g.test_god
	g.test_god = true
	Defs.world_seed = 424242
	g._delete_worlds()
	var wd_t0 := Time.get_ticks_msec()
	g._enter_planet(0)
	var wd_ms := Time.get_ticks_msec() - wd_t0
	var wd_pl: Dictionary = g.planet
	var wd_lb := []
	for wd_l in g.summoning.callable_biomes():
		wd_lb.append(wd_l)
	var wd_want: Array = wd_pl.get("guardians", [])
	var wd_match := true
	for wd_b3 in wd_lb:
		wd_match = wd_match and wd_want.has(wd_b3)
	var wd_made_ok: bool = g.builds.infos.size() >= 12 and wd_match and wd_lb.size() >= wd_want.size() - 1 and wd_lb.size() >= 1
	_ok("a new game's planet is made from its own seed, with guardians only where it says", wd_made_ok,
		"%s (%s, radius %.0f): %s; %d structures; guardians wanted %s, callable %s; made in %d ms (%s)" % [wd_pl["name"], wd_pl["kind"], float(wd_pl["radius"]),
		wd_pl["desc"], g.builds.infos.size(), str(wd_want), str(wd_lb), wd_ms, str(g.gen_times)])
	Defs.world_seed = 0
	g._delete_worlds()
	g.test_god = wd_god0

## Stamps land where they're meant, whatever their anchor (a default one near you, one given, of any
## width): `wrapc` once took % of negative numbers, which only came out right on a planet a power of
## two columns round.
func _test_stampdiag() -> void:
	var sd_a: float = g.spawn_angle - 0.13
	var sd_s: float = g.gpu.surf_at(sd_a).x
	var b = g.builds
	var sd_x: int = Build.cell_of(Vector2(cos(sd_a), sin(sd_a)) * sd_s).x
	var sd_y: int = b.ground_row(sd_x + 5) - 40
	var sd_d := PackedInt32Array()
	sd_d.resize(100)
	sd_d.fill(Defs.OBSIDIAN | 0x20000 | (255 << 8))
	# (variants: [anchor column or -1 for the default, anchor width or -1 for none given, rows up])
	var sd_cases := [[-1, -1, 0], [sd_x, 1, 12], [-2, 10, 24], [sd_x, 10, 36], [-1, -1, 48]]
	var sd_lines := []
	var sd_good := true
	for sd_k in sd_cases.size():
		var sc: Array = sd_cases[sd_k]
		var sy: int = sd_y - int(sc[2])
		var st := {"x0": sd_x, "y0": sy, "w": 10, "h": 10, "data": sd_d}
		if int(sc[0]) >= 0:
			st["ax"] = int(sc[0])
		elif int(sc[0]) == -2:
			st["ax"] = Defs.anchor_c
		if int(sc[1]) >= 0:
			st["aw"] = int(sc[1])
		g.stamps.append(st)
		var anc0: int = Defs.anchor_c
		await _frames(3)
		var raw: PackedByteArray = g.gpu.read_world()
		var n2 := 0
		var found := {}
		for j in 10:
			for i in range(-400, 400):
				if (raw.decode_u32(Defs.raw_idx(sy + j, posmod(sd_x + i, Defs.NS)) * 4) & 255) == Defs.OBSIDIAN:
					if i >= 0 and i < 10:
						n2 += 1
					found[i] = true
		var ks: Array = found.keys()
		ks.sort()
		sd_lines.append("%s: %d of 100%s" % [str(sc), n2, "" if n2 == 100 else " (!) (anchor %d; found at %s)" % [anc0, str(ks.slice(0, 3))]])
		sd_good = sd_good and n2 == 100
	# (and the blocks cleared again)
	var sd_air := PackedInt32Array()
	sd_air.resize(100)
	sd_air.fill(Defs.AIR | 0xFF00)
	for sd_k2 in sd_cases.size():
		g.stamps.append({"x0": sd_x, "y0": sd_y - int(sd_cases[sd_k2][2]), "w": 10, "h": 10, "data": sd_air, "ax": sd_x, "aw": 10})
	await _frames(3)
	_ok("stamps land where they're meant, whatever their anchor", sd_good, "[anchor, width, rows up]: " + "; ".join(sd_lines))

## The other planets' own biomes: Cindrel's ashlands (Kragmor in his caldera) and Thalassa's drowned
## shelves (Thalassor in a sanctum on the seabed, under the water), and the sea's swimmers, which
## come after you through the water and keep to it.
func _test_far_biomes() -> void:
	var fb_god0: bool = g.test_god
	g.test_god = true
	# (on foot, and the far planets made fresh: the skiff's journey left you aboard, and Cindrel saved
	# with the skiff in it, which would carry you back to your seat whenever the test moved you)
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	g.player.aboard = null
	g._delete_worlds()
	g._enter_planet(1)
	g.ui.title.visible = false
	await _frames(60)
	await _test_guardians(["ashland"])
	# its air scorches you under the open sky, unless you have the Heat Ward (or the Cinderheart, which
	# the guardian's test has just given you: put aside for this)
	var fh_cind: bool = g.player.items.has("cinderheart")
	g.player.items.erase("cinderheart")
	var fh_ward0: bool = g.player.heat_ward
	g.player.heat_ward = false
	var fh_st := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) - 20, 40, 80, 6)
	var fh_a: float = (float(fh_st.x) + 20.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(fh_a), sin(fh_a)) * (g.gpu.surf_at(fh_a).x + 12.0))
	await _frames(40)
	# (only the air may hurt you here: the guardian's fight can leave a minion or a shot about, and one hit
	# of 10 once spoiled the warded half)
	var fh_calm := func() -> void:
		for fh_e in g.enemies.duplicate():
			if not fh_e.boss and fh_e.pos.distance_to(g.player.pos) < 250.0:
				g.enemies.erase(fh_e)
		for fh_pr in g.projs.duplicate():
			if String(fh_pr["owner"]) != "player":
				g.projs.erase(fh_pr)
	fh_calm.call()
	g.test_god = false
	g.player.hp = g.player.max_hp
	await _frames(150)
	var fh_burnt: float = g.player.max_hp - g.player.hp
	var fh_open: bool = g.exposed
	g.player.heat_ward = true
	fh_calm.call()
	g.player.hp = g.player.max_hp
	await _frames(150)
	var fh_warded: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.heat_ward = fh_ward0
	if fh_cind:
		g.player.items["cinderheart"] = true
	_ok("Cindrel's air scorches you under the open sky, but not with the Heat Ward", fh_open and fh_burnt > 0.8 and fh_warded < 0.05,
		"out in the open %s; 2.5 s without the ward: -%.1f health, with it: -%.1f" % [fh_open, fh_burnt, fh_warded])
	# its own ore, Fire Opal, lies in its ground (a block of rock under you, read back), and the Core Drive
	# that leaves it wants some
	var fo_c := int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS)
	var fo_r: int = Defs.row_at(g.gpu.surf_at(atan2(g.player.pos.y, g.player.pos.x)).x) + 30
	var fo_n := 0
	var fo_cells := 0
	for fo_q in 3:
		var fo_rr: Dictionary = g.gpu.read_rect(fo_c - 300 + fo_q * 200, fo_r, 200, 260, fo_c - 300 + fo_q * 200, 200)
		for fo_v in fo_rr["fg"]:
			fo_cells += 1
			if (fo_v & 255) == Defs.FIREOPAL:
				fo_n += 1
	_ok("each kind of planet has its own ore: Fire Opal in Cindrel's ground", fo_n >= 20,
		"%d Fire Opal cells in %d read under you" % [fo_n, fo_cells])
	g._enter_planet(2)
	g.ui.title.visible = false
	await _frames(60)
	# (Thalassor is called at an altar on the seabed and comes up in the water)
	await _test_guardians(["ocean"])
	var fb_wet := "Thalassor came in the water: %s" % bool(guard_info.get("ocean", {}).get("wet", false))
	# the swimmers: somewhere the sea is deep near you, each comes after you and keeps to the water
	g.test_god = true
	var fb_c0 := int(floor(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS))
	# the deep sea crushes you, unless the Tide Charm (or the Tidefin, from its guardian) bears it
	# (the deepest stretch of sea within reach: 9 columns together at least that deep)
	var dp_col := -1
	var dp_best := 0
	for dp_k in range(0, 6000, 8):
		for dp_sgn in [1, -1]:
			var dp_c: int = fb_c0 + dp_sgn * dp_k
			var dp_d := 9999
			for dp_q in range(-8, 9, 4):
				dp_d = mini(dp_d, g.builds.ground_row(dp_c + dp_q) - g.builds.water_row(dp_c + dp_q))
			if dp_d > dp_best:
				dp_best = dp_d
				dp_col = posmod(dp_c, Defs.NS)      # (columns wrap: a negative one is a real place, not "none")
	if dp_best < 46:
		dp_col = -1
	var dp_bare := -1.0
	var dp_charm := -1.0
	var dp_was := ""
	if dp_col >= 0:
		var dp_fin: bool = g.player.items.has("tidefin")
		g.player.items.erase("tidefin")
		for dp_e in g.enemies.duplicate():
			if not dp_e.boss and dp_e.guard_id < 0:
				g.enemies.erase(dp_e)
		var dp_at: Vector2 = _cell_pos(dp_col, g.builds.water_row(dp_col) + mini(dp_best - 6, 60))
		_go(dp_at)
		await _frames(10)
		g.test_god = false
		g.player.hp = g.player.max_hp
		g.player.breath = g.player.max_breath
		for dp_f in 120:
			g.player.pos = dp_at
			await _frames(1)
		dp_bare = g.player.max_hp - g.player.hp
		dp_was = g.hazard
		g.items["tidecharm"] = true
		g.player.hp = g.player.max_hp
		g.player.breath = g.player.max_breath
		for dp_f2 in 120:
			g.player.pos = dp_at
			await _frames(1)
		dp_charm = g.player.max_hp - g.player.hp
		g.items.erase("tidecharm")
		g.test_god = true
		if dp_fin:
			g.player.items["tidefin"] = true
		g.player.hp = g.player.max_hp
	_ok("Thalassa's deep sea crushes you, but not with the Tide Charm", dp_bare > 1.5 and dp_charm < 0.05 and dp_was == "deep",
		"the deepest sea near you %d cells (at column %d); 2 s near its floor: -%.1f health bare (%s), -%.1f with the charm" % [dp_best, dp_col, dp_bare, dp_was, dp_charm])
	var fb_col := -1
	for fb_k in range(0, 3000, 8):
		for fb_sgn in [1, -1]:
			var fb_c: int = fb_c0 + fb_sgn * fb_k
			if fb_col < 0:
				# (a stretch of open sea at least 30 deep, 60 across: not the slope of an island)
				var fb_deep := true
				for fb_q in range(-30, 31, 6):
					if g.builds.ground_row(fb_c + fb_q) - g.builds.water_row(fb_c + fb_q) < 30:
						fb_deep = false
						break
				if fb_deep:
					fb_col = fb_c
	var fb_rows := []
	var fb_good := fb_col >= 0 and fb_wet.ends_with("true")
	if fb_col >= 0:
		var fb_wr: int = g.builds.water_row(fb_col)
		_go(_cell_pos(fb_col + 20, fb_wr + 16))
		await _frames(20)
		var fb_ids := []
		for fb_id in Defs.CREATURES:
			if Defs.CREATURES[fb_id].get("swim", false):
				fb_ids.append(fb_id)
		var fb_foes := []
		for fb_n in fb_ids.size():
			var fb_e = g.spawn_enemy("c_" + String(fb_ids[fb_n]), _cell_pos(fb_col - 6 - fb_n * 14, fb_wr + 20))
			fb_e.alert_t = 9999
			fb_e.seen_pos = g.player.pos
			fb_e.provoked = true
			fb_foes.append([fb_ids[fb_n], fb_e, 0, 0.0, 9999.0, fb_e.pos, {}])
		for fb_f in 300:
			await _frames(1)
			if fb_f == 200:
				g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("swimmers.png"))
			for fb_r in fb_foes:
				var fb_e2 = fb_r[1]
				if fb_e2.dead:
					continue
				if fb_f % 30 == 0:
					fb_e2.alert_t = 9999
					fb_e2.seen_pos = g.player.pos
				var fb_t: int = g.type_at(fb_e2.pos)
				if Defs.KIND[fb_t] == Defs.K_LIQUID:
					fb_r[2] = int(fb_r[2]) + 1
				else:
					var fb_out: Dictionary = fb_r[6]
					fb_out[Defs.NAMES[fb_t]] = int(fb_out.get(Defs.NAMES[fb_t], 0)) + 1
				fb_r[3] = float(fb_r[3]) + fb_e2.pos.distance_to(Vector2(fb_r[5]))
				fb_r[4] = minf(float(fb_r[4]), fb_e2.pos.distance_to(g.player.pos))
				fb_r[5] = fb_e2.pos
		for fb_r2 in fb_foes:
			var fb_e3 = fb_r2[1]
			var fb_in: float = float(fb_r2[2]) / 300.0
			var fb_fine: bool = fb_in > 0.85 and float(fb_r2[3]) > 6.0 and (fb_e3.moves_done >= 1 or float(fb_r2[4]) < 30.0)
			if not fb_fine:
				fb_good = false
			fb_rows.append("%s%s: in the water %.0f%% (else %s), %d moves, moved %.0f, nearest %.0f" % ["" if fb_fine else "(!) ", fb_r2[0], fb_in * 100.0, str(fb_r2[6]), fb_e3.moves_done, fb_r2[3], fb_r2[4]])
			fb_e3.dead = true
	g.test_god = fb_god0
	_ok("Thalassa: the sanctum lies under the sea, and its swimmers come after you and keep to the water", fb_good and fb_rows.size() >= 2,
		"%s; sea found %s; %s" % [fb_wet, fb_col >= 0, "; ".join(fb_rows)])
