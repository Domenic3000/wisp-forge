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
	await _test_terrain3()
	await _test_terrain4()
	Defs.world_seed = 0
	g._delete_worlds()
	g.test_god = wd_god0

## Terrain 3 (27 Nov; user: "the ocean isnt nearly deep enough on the water world ... how do we make it really feel
## like a deep dark vast ocean. same thing with other worlds. they feel a bit shallow still i can dig away the
## entire surface very easily ... i want the biomes to feel vast as well ... we need developed cave systems with
## underground foliage and creatures living there"; chose new journeys only, abyssal seas, deeper biome ground,
## wider biomes and a cave layer per biome): a new journey's planet's soil runs deep, its cave layer has the
## biome's own rock and plants; an ocean world's seas fall off a shelf into 500-800 cells of water
func _test_terrain3() -> void:
	var t_keep: int = Defs.terrain
	Defs.terrain = 3
	var bad := []
	# fewer, wider biomes round a grown planet
	var nb := 0.0
	for s3 in range(1, 21):
		for i3 in 5:
			nb += float((Defs.make_planet_for(s3 * 7919, i3)["biomes"] as Array).size())
	nb /= 100.0
	if nb > 5.6:
		bad.append("%.1f biomes a planet (wider biomes want fewer)" % nb)
	# the planet of a new game (seed 424242), made on terrain 3
	Defs.world_seed = 424242
	g._delete_worlds()
	g._enter_planet(0)
	await _frames(20)
	var bs = g.builds
	var pc: Vector2i = Build.cell_of(g.player.pos)
	var soil := []
	for k in 12:
		var c: int = pc.x - 330 + k * 60
		var gr: int = bs.ground_row(c)
		if bs.wet(c):
			continue
		var rr: Dictionary = g.gpu.read_rect(c, gr, 1, 150)
		var n := 0
		for v in rr["fg"]:
			var t: int = int(v) & 255
			if t in [Defs.DIRT, Defs.GRASS, Defs.MUD, Defs.SAND, Defs.SANDSTONE, Defs.SNOW, Defs.ASH, Defs.MYCELIUM, Defs.DRYGRASS, Defs.GRAVEL, Defs.COPPER, Defs.COAL]:
				n += 1
		soil.append(n)
	soil.sort()
	var soil_mid: int = soil[soil.size() / 2] if not soil.is_empty() else 0
	if soil_mid < 45:
		bad.append("the soil runs only %d cells deep (middle of %s)" % [soil_mid, str(soil)])
	# the cave layer: themed rock and its plants, 70-270 cells under the ground round you
	var themed := 0
	var solid := 0
	var plants := 0
	var cave_at := Vector2.ZERO
	for q in 3:
		var c0: int = pc.x - 300 + q * 200
		var r0: int = bs.ground_row(c0) + 70
		var rc: Dictionary = g.gpu.read_rect(c0, r0, 200, 200)
		var fg: PackedInt32Array = rc["fg"]
		var bg: PackedInt32Array = rc["bg"]
		for j in fg.size():
			var t2: int = fg[j] & 255
			if t2 == 0:
				var b2: int = bg[j] & 255
				if b2 in [Defs.SHROOM, Defs.ROOT, Defs.LEAF, Defs.CRYSTAL, Defs.FROST, Defs.EMBER, Defs.ICE, Defs.STALK, Defs.SNOW, Defs.ASH]:
					plants += 1
					if cave_at == Vector2.ZERO:
						cave_at = Build.cell_pos(c0 + j % 200, r0 + j / 200)
			elif Defs.KIND[t2] == Defs.K_SOLID:
				solid += 1
				if t2 in [Defs.MOSSBLOCK, Defs.SANDSTONE, Defs.ICE, Defs.MAGMAROCK, Defs.OBSIDIAN]:
					themed += 1
	var th_f: float = float(themed) / maxf(1.0, float(solid))
	if th_f < 0.05:
		bad.append("the cave layer's rock is plain (%.1f%% themed)" % (th_f * 100.0))
	if plants < 15:
		bad.append("only %d cave plants" % plants)
	if cave_at != Vector2.ZERO:
		g.player.pos = cave_at
		g.player.vx = 0.0
		g.player.vy = 0.0
		g.cam_c = cave_at
		await _frames(40)
		_shot("cave_layer.png")
	# an ocean world: its abyss
	var o_seed := -1
	var o_i := -1
	for s4 in range(1, 60):
		for i4 in range(1, 5):
			if o_seed < 0 and String(Defs.make_planet_for(s4 * 104729, i4)["kind"]) == "ocean":
				o_seed = s4 * 104729
				o_i = i4
	var deepest := 0.0
	var deep_f := 0.0
	var shelf_ok := false
	if o_seed < 0:
		bad.append("no ocean world among 59 seeds")
	else:
		Defs.world_seed = o_seed
		g._delete_worlds()
		g._enter_planet(o_i)
		await _frames(20)
		var bs2 = g.builds
		var wet_n := 0
		var deep_n := 0
		var deep_c := 0
		var shallow_n := 0
		for x in range(0, bs2.N0, 3):
			var dep: float = float(bs2.surf[x * 8 + 5]) - float(bs2.surf[x * 8])
			if dep > 0.5:
				wet_n += 1
				if dep > 300.0:
					deep_n += 1
				if dep > 20.0 and dep < 160.0:
					shallow_n += 1
				if dep > deepest:
					deepest = dep
					deep_c = x
		deep_f = float(deep_n) / maxf(1.0, float(wet_n))
		shelf_ok = shallow_n > 20
		if deepest < 480.0 or deep_f < 0.3 or not shelf_ok:
			bad.append("the sea: deepest %.0f cells, %.0f%% of it past 300, a shelf %s" % [deepest, deep_f * 100.0, shelf_ok])
		# down there: dark, a few lights
		var da: float = (float(deep_c) + 0.5) / float(bs2.N0) * TAU
		g.player.pos = Vector2(cos(da), sin(da)) * (float(bs2.surf[deep_c * 8]) + 30.0)
		g.player.vx = 0.0
		g.player.vy = 0.0
		g.cam_c = g.player.pos
		await _frames(40)
		_shot("abyss.png")
	Defs.terrain = t_keep
	_ok("terrain 3: wider biomes, deep soil, a cave layer of the biome's own rock and plants, abyssal seas", bad.is_empty(),
		("%.1f biomes a planet; soil %d cells deep (middle); cave layer %.0f%% themed rock, %d plants; the sea %.0f deep at most, %.0f%% past 300 (pictures cave_layer.png, abyss.png)" % [nb, soil_mid, th_f * 100.0, plants, deepest, deep_f * 100.0]) if bad.is_empty() else "; ".join(bad))

## Terrain 4 (27 Nov; user: "some mountain areas that go up and down a bit too aggresively ... i wanted more height
## variation in the sense of higher mountains and lower valleys but over a bit larger distances than that, and also if
## we could make it so that trees dont grow on super steep slopes, maybe we could make different foliage for that. also
## i would like to see caves going into the sides of mountains. you might have to raise the upper atmosphere a bit too";
## and "snow and sand and loose solids like that block some doorways and make it so the skeletons get stuck"): the test
## planet made the old way (terrain 3) and the new (4) from the same seed: its mountains' short-scale roughness,
## their height range, the sky's height, no trunks on the steepest slopes but scrub, voids just under steep mountain
## ground (the side caves); then a doorway full of sand swept out with a skeleton about, and a door shut over sand.
func _test_terrain4() -> void:
	var bad := []
	var t4_keep: int = Defs.terrain
	var t4_god: bool = g.test_god
	g.test_god = true
	Defs.terrain = 3
	Defs.world_seed = 0
	var t4_mi: int = (Defs.make_planet_for(0, 0)["biomes"] as Array).find("mountain")
	var t4_m := []
	for t4_way in [3, 4]:
		Defs.t3_worlds = {0: true} if t4_way == 3 else {}
		Defs._planet_cache.clear()
		g._delete_worlds()
		g._enter_planet(0)
		await _frames(20)
		var bs = g.builds
		var sf: PackedFloat32Array = bs.surf
		var n0: int = bs.N0
		var hs := []
		var curv := 0.0
		var cn := 0
		var steep := []
		for x in n0:
			if int(sf[x * 8 + 1]) != t4_mi:
				continue
			var h0: float = sf[x * 8]
			hs.append(h0)
			var hl: float = sf[posmod(x - 12, n0) * 8]
			var hr: float = sf[posmod(x + 12, n0) * 8]
			curv += absf(hl + hr - 2.0 * h0)
			cn += 1
			var sl: float = absf(sf[posmod(x + 4, n0) * 8] - sf[posmod(x - 4, n0) * 8]) / 8.0
			if sl > 1.0:
				steep.append(x)
		hs.sort()
		var rng: float = (float(hs[int(hs.size() * 0.97)]) - float(hs[int(hs.size() * 0.03)])) if hs.size() > 40 else 0.0
		var top: float = float(hs[hs.size() - 1]) - Defs.RS0 if not hs.is_empty() else 0.0
		# trunks and scrub on the steepest columns (the plants are in the back layer), up to 80 of them
		var trunks := 0
		var scrub := 0
		var looked := 0
		var stp: int = maxi(1, steep.size() / 80)
		for k in range(0, steep.size(), stp):
			var c: int = steep[k]
			var gr: int = bs.ground_row(c)
			var rr: Dictionary = g.gpu.read_rect(c, gr - 6, 1, 6)
			var tr := false
			var sc := false
			for v in rr["bg"]:
				var b: int = int(v) & 255
				tr = tr or b == Defs.WOOD
				sc = sc or b == Defs.LEAF or b == Defs.DRYGRASS
			for v2 in rr["fg"]:
				var f: int = int(v2) & 255
				sc = sc or f == Defs.LEAF or f == Defs.DRYGRASS
			trunks += 1 if tr else 0
			scrub += 1 if sc else 0
			looked += 1
		# voids 6-20 under the ground of steep-ish mountain columns (every 3rd)
		var voids := 0
		var void_at := -1
		for x2 in range(0, n0, 3):
			if int(sf[x2 * 8 + 1]) != t4_mi:
				continue
			if absf(sf[posmod(x2 + 4, n0) * 8] - sf[posmod(x2 - 4, n0) * 8]) / 8.0 < 0.3:
				continue
			var gr2: int = bs.ground_row(x2)
			var rv: Dictionary = g.gpu.read_rect(x2, gr2 + 6, 1, 14)
			var air := 0
			for v3 in rv["fg"]:
				if int(v3) & 255 == 0:
					air += 1
			if air >= 4:
				voids += 1
				if void_at < 0:
					void_at = x2
		t4_m.append({"curv": curv / maxf(1.0, float(cn)), "range": rng, "top": top, "steep": steep.size(), "looked": looked,
			"trunks": trunks, "scrub": scrub, "voids": voids, "atmo": Defs.ATMO, "rtop": Defs.R_TOP - Defs.RS0, "terrain": int(g.planet.get("terrain", 0))})
		if t4_way == 4 and void_at >= 0:
			var vp: Vector2 = _cell_pos(void_at, bs.ground_row(void_at) + 12)
			g.player.pos = vp
			g.player.vx = 0.0
			g.player.vy = 0.0
			g.cam_c = vp
			await _frames(40)
			_shot("side_cave.png")
	var a3: Dictionary = t4_m[0]
	var a4: Dictionary = t4_m[1]
	if t4_mi < 0:
		bad.append("the test planet has no mountains")
	if int(a3["terrain"]) != 3 or int(a4["terrain"]) != 4:
		bad.append("the worlds were made on terrain %d and %d (want 3, 4)" % [a3["terrain"], a4["terrain"]])
	if float(a4["curv"]) > float(a3["curv"]) * 0.6:
		bad.append("the mountains are still rough at short scale (%.2f against %.2f)" % [a4["curv"], a3["curv"]])
	if float(a4["range"]) < float(a3["range"]) * 1.05:
		bad.append("the mountains' heights span %.0f (terrain 3: %.0f)" % [a4["range"], a3["range"]])
	if float(a4["top"]) > 300.0:
		bad.append("a peak %.0f over the mean surface (the surface shell ends at 330)" % a4["top"])
	if absf(float(a3["atmo"]) - 496.0) > 0.5 or absf(float(a4["atmo"]) - 640.0) > 0.5 or absf(float(a4["rtop"]) - 640.0) > 0.5:
		bad.append("the sky: %.0f over terrain 3, %.0f (top %.0f) over terrain 4" % [a3["atmo"], a4["atmo"], a4["rtop"]])
	if int(a4["looked"]) > 0 and float(a4["trunks"]) > float(a4["looked"]) * 0.06:
		bad.append("%d of %d of the steepest columns have a tree trunk" % [a4["trunks"], a4["looked"]])
	if int(a4["looked"]) >= 5 and float(a4["scrub"]) < float(a4["looked"]) * 0.15:
		bad.append("scrub on only %d of %d of the steepest columns" % [a4["scrub"], a4["looked"]])
	if int(a4["voids"]) < int(a3["voids"]) + 20:
		bad.append("no caves into the mountainsides (%d hollow columns under steep ground, terrain 3: %d)" % [a4["voids"], a3["voids"]])
	# ---- a doorway full of sand, a skeleton about: swept; a door shut over sand fills its doorway; opened again, it's whole
	var door_note := "no door near"
	var dk: Dictionary = {}
	var dbest := 1e18
	for d in g.doors:
		var dd: float = (d["pos"] as Vector2).distance_squared_to(g.player.pos)
		if dd < dbest:
			dbest = dd
			dk = d
	if not dk.is_empty():
		var dp: Vector2 = dk["pos"]
		_go(dp + dp.normalized() * 40.0)
		await _frames(20)
		g._set_door(dk, true)
		await _frames(6)
		var dw: int = int(dk["w"])
		var dh: int = int(dk["h"])
		var sand := PackedInt32Array()
		sand.resize(dw * dh)
		sand.fill(Defs.SAND | 0xFF00 | 0x10000)
		var dst := {"x0": posmod(int(dk["col"]), Defs.NS), "y0": int(dk["row"]), "w": dw, "h": dh, "data": sand, "ax": g._door_ax(dk), "aw": int(dk.get("aw", 1))}
		var count_in := func(m: int) -> int:
			var rr2: Dictionary = g.gpu.read_rect(int(dk["col"]), int(dk["row"]), dw, dh, g._door_ax(dk), int(dk.get("aw", 1)))
			var n := 0
			for v4 in rr2["fg"]:
				if int(v4) & 255 == m:
					n += 1
			return n
		g.stamps.append(dst.duplicate())
		await _frames(6)
		var sand0: int = count_in.call(Defs.SAND)
		var sk = g.spawn_enemy("skeleton", dp + g.basis_r(atan2(dp.y, dp.x)) * 60.0 + dp.normalized() * 6.0)
		await _frames(80)
		var sand1: int = count_in.call(Defs.SAND)
		g.enemies.erase(sk)
		await _frames(4)
		g.stamps.append(dst.duplicate())
		await _frames(6)
		g._set_door(dk, false)
		await _frames(6)
		var shut_n: int = count_in.call(Defs.WOODDOOR)
		g._set_door(dk, true)
		await _frames(6)
		var still: bool = g.doors.has(dk)
		door_note = "a doorway %dx%d: %d sand in it, %d after a skeleton came by; shut over sand %d of %d door cells, opened again it's %s" % [dw, dh, sand0, sand1, shut_n, dw * dh, "whole" if still else "gone"]
		# (sand that spilled out beside the door slides back in between sweeps: most of it gone is the check)
		if sand0 < dw * dh / 3 or sand1 * 4 > sand0 or shut_n < dw * dh * 9 / 10 or not still:
			bad.append(door_note)
	Defs.terrain = t4_keep
	Defs.t3_worlds = {}
	g.test_god = t4_god
	_ok("terrain 4: broad mountains, a higher sky, scrub not trees on steep slopes, caves into mountainsides; doorways swept of sand", bad.is_empty(),
		("mountains: roughness %.2f (was %.2f), heights span %.0f (was %.0f), top %.0f; sky %.0f (was %.0f); steepest columns: %d trunks, %d scrub of %d; hollow under steep ground %d (was %d); %s (picture side_cave.png)" % [
		a4["curv"], a3["curv"], a4["range"], a3["range"], a4["top"], a4["atmo"], a3["atmo"], a4["trunks"], a4["scrub"], a4["looked"], a4["voids"], a3["voids"], door_note]) + ("" if bad.is_empty() else " -- " + "; ".join(bad)))

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
	var dp_over := -1.0
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
		# (27 Nov: how deep counts the water over you, not how far under the sea's level you are)
		dp_over = g._water_above_now(g.player, g.player)
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
	_ok("Thalassa's deep sea crushes you, but not with the Tide Charm", dp_bare > 1.5 and dp_charm < 0.05 and dp_was == "deep" and dp_over >= 35.0,
		"the deepest sea near you %d cells (at column %d); %.0f cells of water over you there; 2 s near its floor: -%.1f health bare (%s), -%.1f with the charm" % [dp_best, dp_col, dp_over, dp_bare, dp_was, dp_charm])
	var fb_col := -1
	for fb_k in range(0, 3000, 8):
		for fb_sgn in [1, -1]:
			var fb_c: int = fb_c0 + fb_sgn * fb_k
			if fb_col < 0:
				# (a stretch of open sea at least 30 deep, from 100 one way to 30 the other: the swimmers are let go
				# along it, not on the slope of an island)
				var fb_deep := true
				for fb_q in range(-100, 31, 6):
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
