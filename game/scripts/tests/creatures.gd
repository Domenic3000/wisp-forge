extends "res://scripts/tests/base.gd"
## Checks of creatures and foes: wild life, ecology, climbing, pathfinding, pursuit, guardians, wardens, spawning. (Part of the chain of test files: see tests.gd.)

## the wild creatures: every biome (and each depth underground) has its own; they notice you, come after
## you with their moves, stay on screen and keep moving
func _test_creatures() -> void:
	var cr_god0: bool = g.test_god
	g.test_god = true
	var cr_w0 := [g.rain, g.rain_target, g.weather_timer, g.time]     # (clear weather at midday: see _test_ecology)
	g.rain = 0.0
	g.rain_target = 0.0
	g.weather_timer = 999999
	var cr_rows := []
	var cr_bad := []
	var cr_places := []
	for cr_b in g.planet.get("biomes", []):
		if not cr_places.has(cr_b):
			cr_places.append(cr_b)
	cr_places.append_array(["cave1", "cave2", "cave3"])
	var cr_none := []
	for cr_w in cr_places:
		if Defs.creatures_of(cr_w).is_empty():
			cr_none.append(cr_w)
	var cr_ids := []
	for cr_k0 in Defs.CREATURES:
		if not Defs.CREATURES[cr_k0].get("swim", false) and Defs.CREATURES[cr_k0].get("temper", "") != "prey":
			cr_ids.append(cr_k0)            # (swimmers are tried in the sea: _test_far_biomes; prey never
			                                # fights: _test_ecology)
	# (on the ground: the test before this one leaves you up in the orbit band)
	var cr_orig: Vector2 = g.player.pos
	# (on a clear, level stretch: spawned inside a tower, a creature can't come after you at all)
	var cr_st := _soft_stretch(Build.cell_of(start_pos).x - 85, 170, 50, 30)    # (soft ground: a burrower lives in it)
	var cr_a0: float = (float(cr_st.x) + 85.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(cr_a0), sin(cr_a0)) * (g.gpu.surf_at(cr_a0).x + 14.0))
	await _frames(60)
	var cr_home: Vector2 = g.player.pos
	g.time = g.towns.time_for_hour(cr_home, 13.0)       # (midday, as the wild-life check: none asleep out of its hours)
	var cr_ang := atan2(cr_home.y, cr_home.x)
	var cr_side: Vector2 = g.basis_r(cr_ang)
	var cr_up: Vector2 = cr_home.normalized()
	for cr_g0 in range(0, cr_ids.size(), 4):
		_go(cr_home)
		await _frames(20)
		var cr_group := []
		for cr_k in range(cr_g0, mini(cr_g0 + 4, cr_ids.size())):
			var cr_id: String = cr_ids[cr_k]
			var cr_d: Dictionary = Defs.creature_enemy("c_" + cr_id)
			var cr_off := (30.0 + 14.0 * float(cr_k - cr_g0)) * (1.0 if (cr_k - cr_g0) % 2 == 0 else -1.0)
			if cr_d["def"]["go"] == "burrow":
				# (a burrower waits at the edge of soft ground: start it where the ground is soft all the way
				# to you, or a buried stone between can keep it off you for the whole check)
				for cr_try in [30.0, -30.0, 22.0, -22.0, 40.0, -40.0, 50.0, -50.0]:
					var cr_soft := true
					for cr_s in range(0, int(absf(cr_try)) + 1, 3):
						var cr_p: Vector2 = cr_home + cr_side * (float(cr_s) * signf(cr_try)) + cr_up * 4.0
						var cr_sf: Vector2 = Ecology.surface_under(g, cr_p, 10.0, 60.0)
						if not cr_sf.is_finite() or not Ecology.diggable(g, cr_sf, 9.0):
							cr_soft = false
							break
					if cr_soft:
						cr_off = cr_try
						break
			var cr_at: Vector2 = cr_home + cr_side * cr_off + cr_up * (20.0 if cr_d["fly"] and cr_d["def"]["go"] != "burrow" else 4.0)
			cr_at = g.free_spot(cr_at, float(cr_d["w"]), float(cr_d["h"]), 20)
			var cr_e = g.spawn_enemy("c_" + cr_id, cr_at)
			cr_e.alert_t = 240             # (it has heard you: a wall between mustn't fail the test)
			cr_e.seen_pos = cr_home
			cr_e.provoked = true           # (the neutral and the territorial fight once roused)
			cr_group.append([cr_id, cr_e, cr_at, 0.0, 0.0, 9999.0, cr_e.pos])
		# (a little longer than it was: now and then one creature hadn't got its first attack in by 170 frames)
		for cr_f in 260:
			await _frames(1)
			if cr_f == 110:
				g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("creatures_%d.png" % int(cr_g0 / 4.0)))
			for cr_row in cr_group:
				var cr_e2 = cr_row[1]
				if cr_e2.dead:
					continue
				cr_row[3] = maxf(float(cr_row[3]), (cr_e2.pos - Vector2(cr_row[2])).dot(cr_up))
				cr_row[4] = float(cr_row[4]) + cr_e2.pos.distance_to(Vector2(cr_row[6]))
				cr_row[5] = minf(float(cr_row[5]), cr_e2.pos.distance_to(g.player.pos))
				cr_row[6] = cr_e2.pos
		for cr_row2 in cr_group:
			var cr_e3 = cr_row2[1]
			var cr_hunt: bool = cr_e3.moves_done >= 1 or float(cr_row2[5]) < 26.0
			var cr_fine: bool = cr_hunt and float(cr_row2[3]) < 70.0 and float(cr_row2[4]) > 6.0
			cr_rows.append("%s %s%d moves, up %.0f, moved %.0f, nearest %.0f" % [cr_row2[0], "" if cr_fine else "(!) ", cr_e3.moves_done, cr_row2[3], cr_row2[4], cr_row2[5]])
			if not cr_fine:
				cr_bad.append(cr_row2[0])
			if not cr_e3.dead:
				g._kill_enemy(cr_e3)
	g.test_god = cr_god0
	g.rain = float(cr_w0[0])
	g.rain_target = float(cr_w0[1])
	g.weather_timer = int(cr_w0[2])
	g.time = float(cr_w0[3])
	g.boss_clouds.clear()
	_go(cr_orig)
	await _frames(30)
	_ok("every biome and depth has creatures that come after you, attack, stay on screen and keep moving",
		cr_none.is_empty() and cr_bad.is_empty(), "%s%d creatures; places without any: %s; %s" % [("(!) failed: %s; " % ", ".join(cr_bad)) if not cr_bad.is_empty() else "", cr_ids.size(), str(cr_none), "; ".join(cr_rows)])

## The wild's own lives (ecology.gd): prey runs, a hunter runs prey down and eats, sleepers sleep in
## their off hours and wake to you, the territorial warn first, the neutral only fight back, fire and
## blasts scare them, frogs hop without flickering, burrowers never leave the ground, a storm sends
## them to shelter, water-dwellers are only met near water.
func _test_ecology() -> void:
	var ec_god0: bool = g.test_god
	var ec_time0: float = g.time
	g.test_god = true
	# (in clear weather, as when run alone: in the full run it was sometimes raining by now, and in a
	# storm creatures go for shelter and huddle, and the rain puts out the fire meant to scare them)
	var ec_w0 := [g.rain, g.rain_target, g.weather_timer]
	g.rain = 0.0
	g.rain_target = 0.0
	g.weather_timer = 999999
	for ec_e0 in g.enemies.duplicate():
		if not ec_e0.boss:
			g.enemies.erase(ec_e0)
	g.spawn_timer = 999999
	var ec_orig: Vector2 = g.player.pos
	var ec_st := _soft_stretch(Build.cell_of(start_pos).x - 130, 260, 50, 8)
	var ec_a0: float = (float(ec_st.x) + 130.5) / float(Defs.NS) * TAU
	var ec_r0: float = g.gpu.surf_at(ec_a0).x
	var ec_br: Vector2 = g.basis_r(ec_a0)
	_go(Vector2(cos(ec_a0), sin(ec_a0)) * (ec_r0 + 14.0))
	await _frames(40)
	g.time = g.towns.time_for_hour(g.player.pos, 13.0)          # (midday)
	var ec_ground := func(off: float) -> Vector2:
		var aa: float = ec_a0 + off / ec_r0
		var p0: Vector2 = Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + 12.0)
		var sf: Vector2 = Ecology.surface_under(g, p0, 30.0, 60.0)
		return sf if sf.is_finite() else Vector2(cos(aa), sin(aa)) * g.gpu.surf_at(aa).x
	var ec_spawn := func(t: String, off: float):
		var gp: Vector2 = ec_ground.call(off)
		var dd: Dictionary = Defs.enemy_def(t)
		return g.spawn_enemy(t, gp + gp.normalized() * (float(dd["h"]) * 0.5 + 1.0))
	var ec_stand := func(off: float) -> void:
		var gp2: Vector2 = ec_ground.call(off)
		_go(gp2 + gp2.normalized() * 12.0)
	var ec_along := func(p: Vector2) -> float:
		return (p - ec_ground.call(0.0)).dot(ec_br)
	var ec_rows := []
	var ec_good := true

	# ---- prey runs from you ----
	ec_stand.call(-60.0)
	await _frames(20)
	var ec_deer = ec_spawn.call("c_deer", -20.0)
	var ec_d0: float = absf(ec_along.call(ec_deer.pos) - ec_along.call(g.player.pos))
	var ec_feared := false
	for ec_f in 150:
		await _frames(1)
		ec_feared = ec_feared or ec_deer.fear_t > 0
	var ec_d1: float = absf(ec_along.call(ec_deer.pos) - ec_along.call(g.player.pos))
	var ec_ok1: bool = ec_feared and ec_d1 > ec_d0 + 20.0 and ec_deer.moves_done == 0
	ec_rows.append("%sa deer ran from you: %.0f -> %.0f cells off" % ["" if ec_ok1 else "(!) ", ec_d0, ec_d1])
	ec_good = ec_good and ec_ok1
	ec_deer.dead = true

	# ---- a hunter runs its prey down and eats it ----
	ec_stand.call(-110.0)
	await _frames(20)
	var ec_wolf = ec_spawn.call("c_frostwolf", 0.0)
	var ec_hare = ec_spawn.call("c_snowhare", 36.0)
	ec_wolf.prey = ec_hare
	var ec_ran := false
	var ec_ate := false
	var ec_hunt_f := 0
	for ec_f2 in 700:
		# (you keep a little way behind the hunt: far enough that the wolf keeps to its prey, near enough
		# that both stay in the simulated ground round you)
		if ec_f2 % 10 == 0:
			ec_stand.call(-ec_along.call(ec_wolf.pos) - 80.0)      # (along runs the other way to the offsets)
		await _frames(1)
		ec_ran = ec_ran or ec_hare.fear_t > 0
		ec_ate = ec_ate or ec_wolf.eat_t > 0
		ec_hunt_f = ec_f2
		if ec_ate:
			await _frames(20)
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("eco_hunt.png"))
			break
	var ec_ok2: bool = ec_hare.dead and ec_ate and ec_ran and not g.eco_carcasses.is_empty()
	ec_rows.append("%sa wolf ran a hare down%s in %.1f s and ate (carcasses %d)" % ["" if ec_ok2 else "(!) ", "" if ec_ran else " (it never ran)", ec_hunt_f / 60.0, g.eco_carcasses.size()])
	ec_good = ec_good and ec_ok2
	ec_wolf.dead = true
	ec_hare.dead = true

	# ---- a creature of the night sleeps by day, and wakes to you beside it ----
	ec_stand.call(-90.0)
	await _frames(20)
	var ec_hy = ec_spawn.call("c_hyena", 30.0)
	Ecology.on_spawn(g, ec_hy)
	var ec_slept: bool = ec_hy.asleep
	for ec_f3 in 60:
		await _frames(1)
		ec_slept = ec_slept and ec_hy.asleep
	ec_stand.call(-12.0)
	await _frames(20)          # (the ground round you is read back afresh after a jump like that)
	ec_slept = ec_slept and ec_hy.asleep
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("eco_sleep.png"))
	ec_stand.call(26.0)
	var ec_woke := -1
	for ec_f4 in 60:
		await _frames(1)
		if not ec_hy.asleep and ec_woke < 0:
			ec_woke = ec_f4
	var ec_ok3: bool = ec_slept and ec_woke >= 0
	ec_rows.append("%sa hyena asleep by day %s, woke %d frames after you came by" % ["" if ec_ok3 else "(!) ", ec_slept, ec_woke])
	ec_good = ec_good and ec_ok3
	ec_hy.dead = true
	# (prey asleep, then woken: pictures of how they lie and how they get up: user, 22 Nov, deer and hares
	# seemed upside down until startled)
	ec_stand.call(-90.0)
	await _frames(20)
	var ec_dr = ec_spawn.call("c_deer", 24.0)
	var ec_hr = ec_spawn.call("c_hare", 44.0)
	for ec_q in [ec_dr, ec_hr]:
		ec_q.asleep = true
		ec_q.act = ""
	await _frames(40)
	print("[prey] asleep: deer pose '%s' frame %s air %s; hare pose '%s' frame %s air %s" % [ec_dr.pose, g.overlay._boss_frame(ec_dr), ec_dr.air_on, ec_hr.pose, g.overlay._boss_frame(ec_hr), ec_hr.air_on])
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("eco_prey_sleep.png"))
	ec_stand.call(2.0)
	for ec_pw in 40:
		await _frames(1)
		if ec_pw % 8 == 0:
			print("[prey] f%d deer asleep %s pose '%s' frame %s; hare asleep %s pose '%s' frame %s" % [ec_pw, ec_dr.asleep, ec_dr.pose, g.overlay._boss_frame(ec_dr), ec_hr.asleep, ec_hr.pose, g.overlay._boss_frame(ec_hr)])
		if ec_pw == 6:
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("eco_prey_woke.png"))
	ec_dr.dead = true
	ec_hr.dead = true

	# ---- the territorial warn you off first, then charge ----
	ec_stand.call(-30.0)
	await _frames(20)
	var ec_ram = ec_spawn.call("c_ram", -4.0)
	var ec_warned := false
	var ec_charge := -1
	for ec_f5 in 240:
		await _frames(1)
		ec_stand.call(-30.0)
		if ec_ram.warn_t > 0 and not ec_ram.provoked:
			ec_warned = true
		if ec_ram.provoked and ec_charge < 0:
			ec_charge = ec_f5
	var ec_ok4: bool = ec_warned and ec_charge >= 50
	ec_rows.append("%sa ram warned you (%s), then charged after %d frames" % ["" if ec_ok4 else "(!) ", ec_warned, ec_charge])
	ec_good = ec_good and ec_ok4
	ec_ram.dead = true

	# ---- the neutral leave you be until struck ----
	ec_stand.call(-30.0)
	await _frames(20)
	var ec_frog = ec_spawn.call("c_redfrog", -8.0)
	var ec_calm := true
	for ec_f6 in 120:
		await _frames(1)
		ec_calm = ec_calm and ec_frog.moves_done == 0
		if ec_f6 == 100:
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("eco_frog.png"))
	g._hurt_enemy(ec_frog, 1.0, 0.0, 0.0)
	for ec_f7 in 240:
		await _frames(1)
		ec_stand.call(-30.0)
		if ec_frog.moves_done >= 1:
			break
	var ec_ok5: bool = ec_calm and ec_frog.moves_done >= 1
	ec_rows.append("%san ember frog calm %s, %d moves once struck" % ["" if ec_ok5 else "(!) ", ec_calm, ec_frog.moves_done])
	ec_good = ec_good and ec_ok5
	ec_frog.dead = true

	# ---- fire and blasts scare them ----
	ec_stand.call(-120.0)
	await _frames(20)
	var ec_ram2 = ec_spawn.call("c_ram", 20.0)
	await _frames(20)
	var ec_burnt := false
	for ec_f8 in 90:
		if ec_f8 < 8:
			g.brushes.append([ec_ram2.pos + ec_br * 8.0, 2.5, 3, Defs.FIRE, 0, 0, 0])
		await _frames(1)
		ec_burnt = ec_burnt or ec_ram2.fear_t > 0
	var ec_puff = ec_spawn.call("c_sporepuff", -60.0)
	await _frames(10)
	var ec_pa0: float = ec_along.call(ec_puff.pos)
	Ecology.scare(g, ec_puff.pos + ec_br * 8.0, 5.0)
	var ec_blasted: bool = ec_puff.fear_t > 0
	await _frames(90)
	var ec_pa1: float = ec_along.call(ec_puff.pos)
	var ec_ok6: bool = ec_burnt and ec_blasted and ec_pa1 < ec_pa0 - 3.0
	ec_rows.append("%sfire scared a ram %s; a blast sent a spore puff %.0f cells off" % ["" if ec_ok6 else "(!) ", ec_burnt, ec_pa0 - ec_pa1])
	ec_good = ec_good and ec_ok6
	ec_ram2.dead = true
	ec_puff.dead = true
	await _frames(60)

	# ---- frogs hop without flickering into their leap ----
	ec_stand.call(-70.0)
	await _frames(20)
	var ec_rf = ec_spawn.call("c_reedfrog", -10.0)
	var ec_runs := 0
	var ec_short := 0
	var ec_run := 0
	# (a frog sits and croaks between hops, at random: 300 frames sometimes held only one hop)
	for ec_f9 in 720:
		await _frames(1)
		if ec_rf.dead or (ec_runs >= 3 and ec_run == 0):
			break
		var ec_air: bool = String(g.overlay._boss_frame(ec_rf)).ends_with("_air")
		if ec_air:
			ec_run += 1
		elif ec_run > 0:
			ec_runs += 1
			if ec_run < 3:
				ec_short += 1
			ec_run = 0
	var ec_ok7: bool = ec_runs >= 2 and ec_short == 0
	ec_rows.append("%sa reed frog hopped %d times, %d flickers" % ["" if ec_ok7 else "(!) ", ec_runs, ec_short])
	ec_good = ec_good and ec_ok7
	ec_rf.dead = true

	# ---- a burrower never leaves the ground, even with you up in the air ----
	# (where both it and you are over soft ground: a stretch of the full run's start had rock or water in it)
	var ec_wo := 20.0
	for ec_try in range(-100, 101, 10):
		var ec_ty := float(ec_try)
		var ec_gw: Vector2 = ec_ground.call(ec_ty)
		var ec_gy: Vector2 = ec_ground.call(ec_ty - 60.0)
		if Ecology.diggable_under(g, ec_gw + ec_gw.normalized() * 4.0) and Ecology.diggable_under(g, ec_gy + ec_gy.normalized() * 4.0) \
				and Ecology.diggable(g, ec_gw, 10.0):
			ec_wo = ec_ty
			break
	ec_stand.call(ec_wo - 60.0)
	await _frames(20)
	var ec_worm = ec_spawn.call("c_sandviper", ec_wo)
	ec_worm.provoked = true
	var ec_in_air := 0
	var ec_bad_hole := 0
	var ec_holes := 0
	var ec_last_act := ""
	for ec_f10 in 420:
		if ec_f10 < 200:
			var ec_hover: Vector2 = ec_ground.call(ec_wo - 60.0)
			_go(ec_hover + ec_hover.normalized() * 40.0)
		await _frames(1)
		if ec_worm.dead:
			break
		var ec_wk: int = Defs.KIND[g.type_at(ec_worm.pos)]
		if ec_f10 >= 4 and ec_worm.under and ec_wk != Defs.K_SOLID and ec_wk != Defs.K_POWDER:
			ec_in_air += 1
		if ec_worm.move.begins_with("breach") and ec_worm.act == "go" and ec_last_act != "go":
			ec_holes += 1
			var ec_sk: int = Defs.KIND[g.type_at(ec_worm.spot - ec_worm.spot.normalized() * 1.5)]
			if ec_sk != Defs.K_SOLID and ec_sk != Defs.K_POWDER:
				ec_bad_hole += 1
		ec_last_act = ec_worm.act
	var ec_ok8: bool = ec_in_air == 0 and ec_bad_hole == 0 and ec_holes >= 1 and not ec_worm.dead
	ec_rows.append("%sa sand viper: %d frames in the open while under, %d of %d holes not on the ground" % ["" if ec_ok8 else "(!) ", ec_in_air, ec_bad_hole, ec_holes])
	ec_good = ec_good and ec_ok8
	ec_worm.dead = true

	# ---- a storm sends them to shelter ----
	# (you well away, so it isn't running from you, but inside the simulated neighbourhood (192 cells
	# each way), or it stands frozen; a few seconds, as it may be grazing when the rain comes)
	ec_stand.call(-120.0)
	await _frames(20)
	var ec_rain0: float = g.rain
	var ec_rt0: float = g.rain_target
	g.rain = 1.0
	g.rain_target = 1.0
	var ec_deer2 = ec_spawn.call("c_deer", 10.0)
	var ec_shelter := false
	var ec_why := ""
	for ec_f11 in 240:
		await _frames(1)
		ec_shelter = ec_shelter or (ec_deer2.storm and ec_deer2.doing == "shelter")
		if ec_shelter:
			break
	if not ec_shelter:
		ec_why = " (storm %s, doing %s, afraid %d, asleep %s, eating %d)" % [ec_deer2.storm, ec_deer2.doing, ec_deer2.fear_t, ec_deer2.asleep, ec_deer2.eat_t]
	g.rain = ec_rain0
	g.rain_target = ec_rt0
	ec_rows.append("%sa deer in the rain went for shelter %s%s" % ["" if ec_shelter else "(!) ", ec_shelter, ec_why])
	ec_good = ec_good and ec_shelter
	ec_deer2.dead = true

	# ---- water-dwellers only where there's water ----
	var ec_wet := NAN
	var ec_dry := NAN
	for ec_k in 720:
		var ec_aa: float = float(ec_k) / 720.0 * TAU
		var ec_sb: Vector4 = g.gpu.surf_b(ec_aa)
		if is_nan(ec_wet) and ec_sb.y > g.gpu.surf_at(ec_aa).x and int(ec_sb.z) == Defs.WATER:
			ec_wet = ec_aa
		if is_nan(ec_dry) and not Ecology.habitat_ok(g, "reedfrog", ec_aa):
			ec_dry = ec_aa
	var ec_ok9: bool = not is_nan(ec_dry) and (is_nan(ec_wet) or Ecology.habitat_ok(g, "reedfrog", ec_wet))
	ec_rows.append("%sreed frogs near water only (wet at %s, dry at %s)" % ["" if ec_ok9 else "(!) ", str(ec_wet), str(ec_dry)])
	ec_good = ec_good and ec_ok9

	var ec_cn: Array = await _test_corner()
	ec_rows.append_array(ec_cn[1])
	ec_good = ec_good and bool(ec_cn[0])

	g.time = ec_time0
	g.test_god = ec_god0
	g.rain = float(ec_w0[0])
	g.rain_target = float(ec_w0[1])
	g.weather_timer = int(ec_w0[2])
	g.spawn_timer = 600
	g.eco_carcasses.clear()
	for ec_e1 in g.enemies.duplicate():
		if not ec_e1.boss:
			g.enemies.erase(ec_e1)
	_go(ec_orig)
	await _frames(30)
	_ok("creatures live in the world: prey runs, hunters hunt, sleepers sleep, the territorial warn, fire and blasts scare, frogs hop cleanly, burrowers stay in the ground",
		ec_good, "; ".join(ec_rows))

## On a course in open air (a floor 200 long, a wall 56 high at its left end): a creature standing still
## stays on the ground's top as you walk to and fro far off (it used to bob a cell: user, 21 Nov), and a
## deer chased into the wall doubles back past you instead of running at it or up it. [ok, rows]
func _test_corner() -> Array:
	var cn_rows := []
	var cn_ok := true
	var cn_a := atan2(g.player.pos.y, g.player.pos.x) - 0.18
	var cn_up := Vector2(cos(cn_a), sin(cn_a))
	var cn_c: Vector2i = Build.cell_of(cn_up * (g.gpu.surf_at(cn_a).x + 200.0))
	var CNW := 200
	var CNH := 60
	var cn_d := PackedInt32Array()
	cn_d.resize(CNW * CNH)
	cn_d.fill(0xFFFF)
	var cn_clear := PackedInt32Array()
	cn_clear.resize(CNW * CNH)
	cn_clear.fill(0xFFFF)
	for cn_j in CNH:
		for cn_i in CNW:
			if cn_j >= 56 or cn_i < 4:
				cn_d[cn_j * CNW + cn_i] = Defs.STONE | 0xFF00 | 0x20000
				cn_clear[cn_j * CNW + cn_i] = Defs.AIR | 0xFF00
	g.stamps.append({"x0": cn_c.x, "y0": cn_c.y, "w": CNW, "h": CNH, "data": cn_d, "ax": cn_c.x, "aw": CNW})
	var cn_floor: float = Defs.R_TOP - float(cn_c.y + 56)
	var cn_at := func(ati: int) -> Vector2:
		var q: Vector2 = _cell_pos(cn_c.x + ati, cn_c.y + 55, cn_c.x, CNW)
		return q.normalized() * (cn_floor + 0.01)
	var cn_side: Vector2 = (cn_at.call(10) - cn_at.call(0)).normalized()     # (from the wall out)
	var cn_col := func(p: Vector2) -> float:
		return (p - cn_at.call(0)).dot(cn_side)
	var cn_stand := func(sti: float) -> void:
		var q2: Vector2 = cn_at.call(int(sti))
		g.player.pos = q2 + q2.normalized() * (g.player.h * 0.5 + 0.2)
		g.player.vx = 0.0
		g.player.vy = 0.0
	_go(cn_at.call(30) + cn_up * 12.0)
	await _frames(30)

	# ---- standing still while you walk to and fro 80 cells off ----
	var cn_dd: Dictionary = Defs.enemy_def("c_deer")
	var cn_sl = g.spawn_enemy("c_deer", cn_at.call(120) + cn_up * (float(cn_dd["h"]) * 0.5 + 1.0))
	cn_sl.asleep = true
	cn_sl.den = cn_sl.pos
	await _frames(40)
	var cn_lo := 1e9
	var cn_hi := -1e9
	var cn_tops := {}
	var cn_gr := 0
	for cn_f in 240:
		cn_stand.call(10.0 + 20.0 * (0.5 - 0.5 * cos(float(cn_f) / 240.0 * TAU * 2.0)))
		await _frames(1)
		cn_sl.asleep = true
		if cn_f < 20:
			continue
		var cn_fr: float = cn_sl.pos.length() - float(cn_sl.h) * 0.5
		cn_lo = minf(cn_lo, cn_fr)
		cn_hi = maxf(cn_hi, cn_fr)
		var cn_gt: float = g.ground_top(cn_sl.pos - cn_sl.pos.normalized() * (float(cn_sl.h) * 0.5), float(cn_sl.w))
		cn_tops[cn_gt] = true
		if cn_sl.on_ground:
			cn_gr += 1
	# (its body may sit up to half a cell off the ground's top as the grid moves round you: what counts is
	# that it never leaves the ground and is always drawn on the same row)
	var cn_ok1: bool = cn_tops.size() == 1 and cn_gr >= 219 and not cn_tops.has(-1.0)
	cn_rows.append("%sstill on the ground as you walk to and fro: body %.2f..%.2f over the floor, drawn on %d row(s), grounded %d/220" % [
		"" if cn_ok1 else "(!) ", cn_lo - cn_floor, cn_hi - cn_floor, cn_tops.size(), cn_gr])
	cn_ok = cn_ok and cn_ok1
	cn_sl.dead = true

	# ---- cornered against the wall ----
	cn_stand.call(90.0)
	await _frames(10)
	var cn_dr = g.spawn_enemy("c_deer", cn_at.call(45) + cn_up * (float(cn_dd["h"]) * 0.5 + 1.0))
	await _frames(10)
	var cn_you := 90.0
	var cn_past := false
	var cn_top := 0.0
	var cn_atw := false
	for cn_f2 in 600:
		cn_you = maxf(cn_you - 0.5, 16.0)           # (you walk on at it, toward the wall)
		cn_stand.call(cn_you)
		await _frames(1)
		var cn_dc: float = cn_col.call(cn_dr.pos)
		cn_top = maxf(cn_top, cn_dr.pos.length() - float(cn_dr.h) * 0.5 - cn_floor)
		cn_atw = cn_atw or cn_dc < 22.0
		if cn_atw and cn_dc > cn_col.call(g.player.pos) + 10.0:
			cn_past = true
			break
	var cn_ok2: bool = cn_past and cn_top < 26.0
	cn_rows.append("%sa deer chased into a wall %sdoubled back past you (it rose at most %.0f cells; the wall is 56)" % [
		"" if cn_ok2 else "(!) ", "" if cn_past else "never ", cn_top])
	cn_ok = cn_ok and cn_ok2
	cn_dr.dead = true
	g.stamps.append({"x0": cn_c.x, "y0": cn_c.y, "w": CNW, "h": CNH, "data": cn_clear, "ax": cn_c.x, "aw": CNW})
	await _frames(5)
	return [cn_ok, cn_rows]

## foes follow you to another level (its own function so it can run alone: see `only`)
func _test_climb() -> void:
	# ---- foes follow you to another level: up through a one-way platform and on up a stone ledge
	# beside it, and back down through the platform (skeleton, slime and a wild creature), on a
	# course set up in open air: a floor, a platform 22 cells up, a ledge 22 above that ----
	var cl_god0: bool = g.test_god
	g.test_god = true
	var cl_orig: Vector2 = g.player.pos
	var cl_a := atan2(cl_orig.y, cl_orig.x) + 0.15
	var cl_up := Vector2(cos(cl_a), sin(cl_a))
	var cl_c: Vector2i = Build.cell_of(cl_up * (g.gpu.surf_at(cl_a).x + 200.0))
	var CLW := 130
	var CLH := 56
	var cl_d := PackedInt32Array()
	cl_d.resize(CLW * CLH)
	cl_d.fill(0xFFFF)
	var cl_clear := PackedInt32Array()
	cl_clear.resize(CLW * CLH)
	cl_clear.fill(0xFFFF)
	for cl_j in CLH:
		for cl_i in CLW:
			var cl_m := -1
			if cl_j >= 52:
				cl_m = Defs.STONE                                   # the floor
			elif cl_i < 3 or cl_i >= CLW - 3:
				cl_m = Defs.STONE                                   # walls at its ends, too high to jump
			elif cl_j >= 30 and cl_j <= 31 and cl_i >= 44 and cl_i < 74:
				cl_m = Defs.SCAFFOLD                                # the platform
			elif cl_j >= 8 and cl_j <= 11 and cl_i >= 74:
				cl_m = Defs.STONE                                   # the ledge
			if cl_m >= 0:
				cl_d[cl_j * CLW + cl_i] = cl_m | 0xFF00 | 0x20000
				cl_clear[cl_j * CLW + cl_i] = Defs.AIR | 0xFF00
	g.stamps.append({"x0": cl_c.x, "y0": cl_c.y, "w": CLW, "h": CLH, "data": cl_d, "ax": cl_c.x, "aw": CLW})
	var cl_floor_r: float = Defs.R_TOP - float(cl_c.y + 52)
	var cl_at := func(ci: int, cj: int) -> Vector2:
		return _cell_pos(cl_c.x + ci, cl_c.y + cj, cl_c.x, CLW)
	var cl_feet := func(ce) -> float:
		return ce.pos.length() - float(ce.h) * 0.5 - cl_floor_r
	var cl_o0: Vector2 = cl_at.call(0, 52)
	var cl_side: Vector2 = g.basis_r(atan2(cl_o0.y, cl_o0.x))
	var cl_col := func(p: Vector2) -> float:
		return (p - cl_o0).dot(cl_side)
	var cl_state := func(ce) -> String:
		return "at column %.0f, %s%s%s, act '%s', climb %s %d (cd %d) from col %.0f h %.0f to col %.0f h %.0f" % [
			cl_col.call(ce.pos), "ground" if ce.on_ground else "air", " platform" if ce.on_platform else "",
			" sees" if ce.see else "", ce.act, "up" if ce.climb_up else "down", ce.climb_t, ce.climb_cd,
			cl_col.call(ce.climb_from), ce.climb_from.length() - cl_floor_r, cl_col.call(ce.climb_to), ce.climb_to.length() - cl_floor_r] + " [" + String(ce.climb_why) + "]"
	var cl_lines := []
	var cl_good := true
	for cl_way in ["up", "down"]:
		_go(cl_at.call(110, -2) if cl_way == "up" else cl_at.call(58, 42))
		await _frames(20)
		var cl_foes := []
		var cl_starts: Array = [["skeleton", 14, 38], ["slime", 30, 40], ["c_crawler", 22, 40]] if cl_way == "up" \
			else [["skeleton", 108, -6], ["slime", 120, -4], ["c_crawler", 96, -4]]
		for cl_s in cl_starts:
			var cl_e = g.spawn_enemy(String(cl_s[0]), cl_at.call(int(cl_s[1]), int(cl_s[2])))
			cl_e.alert_t = 9999
			cl_e.seen_pos = g.player.pos
			cl_foes.append([cl_s[0], cl_e, -1])
		for cl_f in 900:
			await _frames(1)
			var cl_all := true
			for cl_row in cl_foes:
				var cl_e2 = cl_row[1]
				if cl_f % 30 == 0:
					cl_e2.alert_t = 9999
					cl_e2.seen_pos = g.player.pos
				var cl_h: float = cl_feet.call(cl_e2)
				if int(cl_row[2]) < 0 and cl_f % 15 == 0 and cl_f < 600:
					print("[climb] %s %s f%d h %.1f vy %.2f vx %.2f %s" % [cl_way, cl_row[0], cl_f, cl_h, cl_e2.vy, cl_e2.vx, cl_state.call(cl_e2)])
				if int(cl_row[2]) < 0 and ((cl_way == "up" and cl_h > 40.0) or (cl_way == "down" and cl_h < 4.0)):
					cl_row[2] = cl_f
				if int(cl_row[2]) < 0:
					cl_all = false
			if cl_all:
				break
		for cl_row2 in cl_foes:
			var cl_e3 = cl_row2[1]
			var cl_fine: bool = int(cl_row2[2]) >= 0
			cl_lines.append("%s %s: %s (now %.0f cells up%s)" % [cl_way, cl_row2[0],
				("in %.1f s" % (float(cl_row2[2]) / 60.0)) if cl_fine else "(!) never", cl_feet.call(cl_e3),
				"" if cl_fine else ", " + String(cl_state.call(cl_e3))])
			if not cl_fine:
				cl_good = false
			cl_e3.dead = true
		await _frames(2)
	g.stamps.append({"x0": cl_c.x, "y0": cl_c.y, "w": CLW, "h": CLH, "data": cl_clear, "ax": cl_c.x, "aw": CLW})
	g.test_god = cl_god0
	_go(cl_orig)
	await _frames(20)
	_ok("foes follow you up through a platform and onto a ledge, and down through the platform", cl_good, "; ".join(cl_lines))

func _test_nav() -> void:
	# ---- pathfinding (nav.gd): on a course in open air (a floor; stone slabs stepping up to the left;
	# a long walkway at the top reaching back to the right), foes find their way round to you ----
	var nv_god0: bool = g.test_god
	g.test_god = true
	var nv_orig: Vector2 = g.player.pos
	var nv_a := atan2(nv_orig.y, nv_orig.x) - 0.12
	var nv_up := Vector2(cos(nv_a), sin(nv_a))
	var nv_c: Vector2i = Build.cell_of(nv_up * (g.gpu.surf_at(nv_a).x + 200.0))
	var NW := 220
	var NH := 100
	var nv_box := Rect2i(150, 66, 31, 30)             # (a closed box on the floor, for 3 and 4)
	var nv_inner := Rect2i(153, 69, 25, 27)
	var nv_mk := func(box_mat: int, clear: bool) -> PackedInt32Array:
		var dd := PackedInt32Array()
		dd.resize(NW * NH)
		dd.fill(0xFFFF)
		for nj in NH:
			for ni in NW:
				var m := Defs.AIR                                      # (open air, whatever was there)
				if nj >= 96 or ni < 3 or ni >= NW - 3:
					m = Defs.OBSIDIAN                                  # floor, end walls (nothing breaks them)
				elif nj >= 78 and nj <= 79 and ni >= 30 and ni <= 60:
					m = Defs.STONE                                     # slab 1, 18 up
				elif nj >= 60 and nj <= 61 and ni >= 3 and ni <= 22:
					m = Defs.STONE                                     # slab 2, 36 up
				elif nj >= 42 and nj <= 45 and ni >= 40:
					m = Defs.STONE                                     # the walkway, 54 up
				elif box_mat >= 0 and nv_box.has_point(Vector2i(ni, nj)) and not nv_inner.has_point(Vector2i(ni, nj)):
					m = box_mat
				if clear:
					dd[nj * NW + ni] = Defs.AIR | 0xFF00
				else:
					dd[nj * NW + ni] = m | 0xFF00 | (0x20000 if m != Defs.AIR else 0)
		return dd
	g.stamps.append({"x0": nv_c.x, "y0": nv_c.y, "w": NW, "h": NH, "data": nv_mk.call(-1, false), "ax": nv_c.x, "aw": NW})
	var nv_floor_r: float = Defs.R_TOP - float(nv_c.y + 96)
	var nv_at := func(ci: int, cj: int) -> Vector2:
		return _cell_pos(nv_c.x + ci, nv_c.y + cj, nv_c.x, NW)
	var nv_o0: Vector2 = nv_at.call(0, 96)
	var nv_side: Vector2 = g.basis_r(atan2(nv_o0.y, nv_o0.x))
	var nv_col := func(p: Vector2) -> float:
		return (p - nv_o0).dot(nv_side)
	var nv_feet := func(ne) -> float:
		return ne.pos.length() - float(ne.h) * 0.5 - nv_floor_r
	var nv_lines := []
	var nv_good := true
	var nv_keep := func(foes: Array) -> void:
		# (they hunt where you are as if they'd just heard you; whether they see you is their own affair)
		for ne in foes:
			ne.alert_t = 9999
			ne.seen_pos = g.player.pos
	# 1. walkers: you up on the walkway, they on the floor under you; the way up is the other way
	_go(nv_at.call(190, 30))
	await _frames(30)
	var nv_walk := []
	for nv_s in [["skeleton", 186, 86], ["slime", 172, 88], ["c_crawler", 202, 88]]:
		var nv_e = g.spawn_enemy(String(nv_s[0]), nv_at.call(int(nv_s[1]), int(nv_s[2])))
		nv_walk.append([nv_s[0], nv_e, -1, 0])
	for nv_f in 1500:
		await _frames(1)
		var nv_all := true
		for nv_row in nv_walk:
			var nv_e2 = nv_row[1]
			nv_keep.call([nv_e2])
			nv_row[3] = maxi(int(nv_row[3]), int(nv_e2.wall_t))
			if nv_f % 60 == 0 and int(nv_row[2]) < 0:
				print("[nav] %s f%d col %.0f h %.0f path %d/%d ok %s air %s wall %d" % [nv_row[0], nv_f, nv_col.call(nv_e2.pos), nv_feet.call(nv_e2), nv_e2.path_i, nv_e2.path.size(), nv_e2.path_ok, nv_e2.nav_air, nv_e2.wall_t])
			if int(nv_row[2]) < 0 and nv_feet.call(nv_e2) > 48.0 and nv_e2.pos.distance_to(g.player.pos) < 36.0:
				nv_row[2] = nv_f
			if int(nv_row[2]) < 0:
				nv_all = false
		if nv_all:
			break
	for nv_row2 in nv_walk:
		var nv_ok: bool = int(nv_row2[2]) >= 0
		nv_good = nv_good and nv_ok
		nv_lines.append("%s up the stairs to you: %s (longest at a wall %d frames%s)" % [nv_row2[0], ("in %.1f s" % (float(nv_row2[2]) / 60.0)) if nv_ok else "(!) never",
			int(nv_row2[3]), "" if nv_ok else ", now at column %.0f, %.0f up" % [nv_col.call(nv_row2[1].pos), nv_feet.call(nv_row2[1])]])
		nv_row2[1].dead = true
	await _frames(2)
	# 2. a bat under the walkway flies round its end to you (it used to bump along underneath)
	var nv_bat = g.spawn_enemy("bat", nv_at.call(190, 70))
	var nv_bat_t := -1
	var nv_bat_wall := 0
	for nv_f2 in 900:
		await _frames(1)
		nv_keep.call([nv_bat])
		nv_bat_wall = maxi(nv_bat_wall, nv_bat.wall_t)
		if nv_f2 % 60 == 0:
			print("[nav] bat f%d col %.0f h %.0f path %d/%d open %s key %s wall %d act '%s'" % [nv_f2, nv_col.call(nv_bat.pos), nv_feet.call(nv_bat), nv_bat.path_i, nv_bat.path.size(), nv_bat.fly_open, nv_bat.path_key, nv_bat.wall_t, nv_bat.act])
		if nv_bat.pos.distance_to(g.player.pos) < 30.0 and nv_feet.call(nv_bat) > 46.0:
			nv_bat_t = nv_f2
			break
	nv_good = nv_good and nv_bat_t >= 0
	nv_lines.append("bat round the walkway: %s (longest at a wall %d frames)" % [("in %.1f s" % (float(nv_bat_t) / 60.0)) if nv_bat_t >= 0 else "(!) never (at column %.0f, %.0f up)" % [nv_col.call(nv_bat.pos), nv_feet.call(nv_bat)], nv_bat_wall])
	nv_bat.dead = true
	# 3. you shut in a box on the floor: a skeleton outside waits, it doesn't keep pushing at it
	g.stamps.append({"x0": nv_c.x, "y0": nv_c.y, "w": NW, "h": NH, "data": nv_mk.call(Defs.OBSIDIAN, false), "ax": nv_c.x, "aw": NW})
	_go(nv_at.call(165, 84))
	await _frames(20)
	var nv_sk = g.spawn_enemy("skeleton", nv_at.call(105, 86))
	var nv_push := 0
	for nv_f3 in 420:
		await _frames(1)
		nv_keep.call([nv_sk])
		if nv_f3 >= 240 and nv_sk.hit_wall:
			nv_push += 1
	var nv_wait_ok: bool = nv_push < 40
	nv_good = nv_good and nv_wait_ok
	nv_lines.append("shut in: the skeleton pressed at the wall %d of its last 180 frames%s (column %.0f, way ok %s)" % [nv_push, "" if nv_wait_ok else " (!)", nv_col.call(nv_sk.pos), nv_sk.path_ok])
	nv_sk.dead = true
	# 4. the same box in brick, a guardian outside: it smashes its way in, all at once
	g.stamps.append({"x0": nv_c.x, "y0": nv_c.y, "w": NW, "h": NH, "data": nv_mk.call(Defs.BRICK, false), "ax": nv_c.x, "aw": NW})
	await _frames(10)
	var nv_boss = g.spawn_enemy("boss_forest", nv_at.call(100, 76))
	nv_boss.awake = true
	nv_boss.act_cd = 30
	var nv_in := -1
	var nv_hits := 0
	for nv_f4 in 1200:
		await _frames(1)
		nv_hits = maxi(nv_hits, nv_boss.breach_hits)
		if nv_f4 % 60 == 0 and nv_in < 0:
			print("[nav] guardian f%d col %.0f h %.0f unreach %d act '%s' move '%s' hits %d path %d ok %s" % [nv_f4, nv_col.call(nv_boss.pos), nv_feet.call(nv_boss), nv_boss.unreach_t, nv_boss.act, nv_boss.move, nv_boss.breach_hits, nv_boss.path.size(), nv_boss.path_ok])
		if nv_boss.pos.distance_to(g.player.pos) < 20.0:
			nv_in = nv_f4
			break
	var nv_breach_ok: bool = nv_in >= 0 and nv_hits > 0
	nv_good = nv_good and nv_breach_ok
	nv_lines.append("guardian at a brick hut: %s, %d blasts%s" % [("in to you in %.1f s" % (float(nv_in) / 60.0)) if nv_in >= 0 else "(!) never got in",
		nv_hits, "" if nv_breach_ok else " (column %.0f, unreachable %d, act '%s' move '%s')" % [nv_col.call(nv_boss.pos), nv_boss.unreach_t, nv_boss.act, nv_boss.move]])
	g.enemies.erase(nv_boss)
	var nv_nav = g.nav_of_slot(0)
	nv_lines.append("graphs built %d (last %.1f ms on its thread)" % [nv_nav.builds, float(nv_nav.build_us) / 1000.0])
	g.stamps.append({"x0": nv_c.x, "y0": nv_c.y, "w": NW, "h": NH, "data": nv_mk.call(-1, true), "ax": nv_c.x, "aw": NW})
	g.test_god = nv_god0
	_go(nv_orig)
	await _frames(20)
	_ok("foes find their way round to you: up stairs the other way, round a walkway, never pushing at a wall; a guardian breaks in", nv_good, "; ".join(nv_lines))

## A boss struck from where it can't follow comes to you (pursuit.gd; user, 24 Nov: shot Vulkhar through a
## hole and stepped back, again and again). On a course in open air (an obsidian floor; a stone ledge 62 up
## with nothing leading to it; a stone bunker with a tunnel too low for a boss and a slot down into the
## arena): hit from where it can reach you, it doesn't come; hit from the ledge, it comes out on the ledge
## (a spot of its own graph with a way to you); hit through the slot from the tunnel and stepped back, it
## blasts a pocket beside you and comes out in it; Vulkhar the same, and his surge now answers too (his
## reach was never really looked at: no graph was built for his size). Pictures `pursuit_tell.png`,
## `pursuit_came.png`.
func _test_pursuit() -> void:
	var pu_god0: bool = g.test_god
	g.test_god = true
	var pu_orig: Vector2 = g.player.pos
	var pu_a := atan2(pu_orig.y, pu_orig.x) + 0.12
	var pu_up := Vector2(cos(pu_a), sin(pu_a))
	var pu_c: Vector2i = Build.cell_of(pu_up * (g.gpu.surf_at(pu_a).x + 200.0))
	var PW := 230
	var PH := 100
	var pu_mk := func(clear: bool) -> PackedInt32Array:
		var dd := PackedInt32Array()
		dd.resize(PW * PH)
		dd.fill(0xFFFF)
		for nj in PH:
			for ni in PW:
				var m := Defs.AIR
				if nj >= 96 or ni < 3 or ni >= PW - 3:
					m = Defs.OBSIDIAN                                  # floor and end walls
				elif nj >= 30 and nj <= 33 and ni >= 3 and ni <= 100:
					m = Defs.STONE                                     # the ledge, 62 up, reached by nothing
				elif nj >= 16 and nj <= 66 and ni >= 130 and ni < PW - 3:
					m = Defs.STONE                                     # the bunker
					if nj >= 36 and nj <= 54 and ni >= 140 and ni <= 215:
						m = Defs.AIR                                   # its tunnel, 19 high
					elif nj >= 55 and ni >= 160 and ni <= 165:
						m = Defs.AIR                                   # the slot down into the arena
				if clear:
					dd[nj * PW + ni] = Defs.AIR | 0xFF00
				else:
					dd[nj * PW + ni] = m | 0xFF00 | (0x20000 if m != Defs.AIR else 0)
		return dd
	var pu_course := func() -> void:
		g.stamps.append({"x0": pu_c.x, "y0": pu_c.y, "w": PW, "h": PH, "data": pu_mk.call(false), "ax": pu_c.x, "aw": PW})
	pu_course.call()
	var pu_floor_r: float = Defs.R_TOP - float(pu_c.y + 96)
	var pu_at := func(ci: int, cj: int) -> Vector2:
		return _cell_pos(pu_c.x + ci, pu_c.y + cj, pu_c.x, PW)
	var pu_feet := func(pe) -> float:
		return pe.pos.length() - float(pe.h) * 0.5 - pu_floor_r
	var pu_free := func(pe) -> bool:
		var pl: Vector2 = g.to_grid(pe.pos)
		return not g.box_solid(pl.x - pe.w * 0.5, pl.y - pe.h * 0.5, pe.w, pe.h)
	var pu_lines := []
	var pu_good := true
	# one boss in the arena, struck twice from `stand` (stepping back to `back` between), then watched
	var pu_run := func(kind: String, stand: Vector2, back: Vector2, frames: int, shot: String) -> Dictionary:
		_go(stand)
		await _frames(30)
		var pe = g.spawn_enemy(kind, pu_at.call(60, 80))
		pe.awake = true
		pe.act_cd = 9999
		var pr := {"e": pe, "surge": false, "tell": false, "came_f": -1}
		await _frames(50)                       # (its graph is built)
		for k in 2:
			_go(stand)
			await _frames(4)
			g._hurt_enemy(pe, 4.0, 0.0, 0.0)
			await _frames(6)
			_go(back)
			await _frames(40)
		for f in frames:
			await _frames(1)
			pe.act_cd = maxi(pe.act_cd, 40)     # (no moves of its own: what it does is come or not)
			if f % 30 == 0:
				var pc: Vector2i = Build.cell_of(pe.pos)
				var tc: Vector2i = Build.cell_of(pe.come_to)
				var pl: Vector2 = g.to_grid(pe.come_to)
				print("[pursuit] %s f%d at %d,%d come_t %d why '%s' carve %s to %d,%d to-blocked %s grudge %d struck %d reach %s unreach %d surges %d dist %.0f" % [kind, f, pc.x - pu_c.x, pc.y - pu_c.y, pe.come_t, pe.come_why, pe.come_carve,
					tc.x - pu_c.x, tc.y - pu_c.y, g.box_solid(pl.x - pe.w * 0.5, pl.y - pe.h * 0.5, pe.w, pe.h), pe.grudge, pe.struck_n, pe.reach_ok, pe.unreach_t, pe.surges, pe.pos.distance_to(g.player.pos)])
			if pe.surge_n > 0:
				pr["surge"] = true
			if pe.come_t > 0 and not pr["tell"]:
				pr["tell"] = true
				if shot != "":
					await _frames(30)
					_shot(shot)
			if pe.came_n > 0 and int(pr["came_f"]) < 0:
				pr["came_f"] = f
				await _frames(20)
				break
		pr["d"] = pe.pos.distance_to(g.player.pos)
		pr["up"] = pu_feet.call(pe)
		pr["free"] = pu_free.call(pe)
		return pr
	# 1. struck from where it can reach you: nothing
	var r1: Dictionary = await pu_run.call("boss_forest", pu_at.call(90, 86), pu_at.call(100, 86), 200, "")
	var ok1: bool = r1["e"].came_n == 0 and r1["e"].grudge == 0
	pu_good = pu_good and ok1
	pu_lines.append("hit where it can reach you: %s" % ("it stays (grudge 0)" if ok1 else "(!) it came anyway (grudge %d, %s)" % [r1["e"].grudge, r1["e"].come_why]))
	g.enemies.erase(r1["e"])
	# 2. struck from the ledge: it comes out on the ledge
	var r2: Dictionary = await pu_run.call("boss_forest", pu_at.call(40, 20), pu_at.call(20, 20), 240, "")
	var e2 = r2["e"]
	var ok2: bool = e2.came_n == 1 and e2.come_why == "spot" and float(r2["up"]) > 55.0 and float(r2["d"]) < 140.0 and bool(r2["free"])
	pu_good = pu_good and ok2
	pu_lines.append("hit from the ledge: %s" % (("it came out on the ledge after %.1f s, %.0f from you" % [float(r2["came_f"]) / 60.0, r2["d"]]) if ok2 else "(!) came %d (%s), %.0f up, %.0f from you, clear %s, grudge %d" % [e2.came_n, e2.come_why, r2["up"], r2["d"], r2["free"], e2.grudge]))
	g.enemies.erase(e2)
	# 3. struck through the slot from the tunnel, stepping back each time: it blasts a pocket by you
	var r3: Dictionary = await pu_run.call("boss_forest", pu_at.call(169, 46), pu_at.call(200, 46), 260, "pursuit_tell.png")
	var e3 = r3["e"]
	var ok3: bool = e3.came_n == 1 and float(r3["d"]) < 70.0 and bool(r3["free"]) and bool(r3["tell"])
	if ok3:
		_shot("pursuit_came.png")
	pu_good = pu_good and ok3
	pu_lines.append("hit through a slot, stepping back: %s" % (("it came in beside you after %.1f s (%s), %.0f from you" % [float(r3["came_f"]) / 60.0, e3.come_why, r3["d"]]) if ok3 else "(!) came %d (%s), %.0f from you, clear %s, grudge %d, tell %s" % [e3.came_n, e3.come_why, r3["d"], r3["free"], e3.grudge, r3["tell"]]))
	g.enemies.erase(e3)
	# 4. Vulkhar kept from you (in the tunnel, not struck): his surge answers (his reach was never really
	# looked at before: no graph was built for his size)
	pu_course.call()
	_go(pu_at.call(200, 46))
	await _frames(30)
	var e5 = g.spawn_enemy("golem", pu_at.call(60, 80))
	e5.awake = true
	var near5 := 1e9
	var smash5 := false
	for f5 in 420:
		await _frames(1)
		near5 = minf(near5, e5.pos.distance_to(g.player.pos))
		smash5 = smash5 or e5.smash_f > 0
		if e5.surges > 0 or near5 < 50.0:
			break
	# (since 24 Nov he smashes through what's between you, so he may break in before his surge)
	var ok5: bool = e5.surges > 0 or near5 < 50.0
	pu_good = pu_good and ok5
	pu_lines.append("Vulkhar kept from you: %s" % (("his surge answers" if e5.surges > 0 else "he smashed his way in to you") if ok5 else "(!) no surge and not in (reach %s, unreachable %d, nearest %.0f)" % [e5.reach_ok, e5.unreach_t, near5]))
	g.enemies.erase(e5)
	for o5 in g.enemies.duplicate():
		if o5.type == "imp":
			g.enemies.erase(o5)
	# 5. Vulkhar struck through the slot: he comes (the bunker whole again first)
	pu_course.call()
	await _frames(10)
	var r4: Dictionary = await pu_run.call("golem", pu_at.call(169, 46), pu_at.call(200, 46), 300, "")
	var e4 = r4["e"]
	# (he may smash his way in before the second hit is weighed: either way he gets to you)
	var ok4: bool = (e4.came_n == 1 and float(r4["d"]) < 80.0 and bool(r4["free"])) or float(r4["d"]) < 40.0
	pu_good = pu_good and ok4
	pu_lines.append("Vulkhar through the slot: %s" % (("he got to you (%s), %.0f from you" % [("came, " + e4.come_why) if e4.came_n > 0 else "smashed in", r4["d"]]) if ok4 else "(!) came %d (%s), %.0f from you, clear %s, grudge %d" % [e4.came_n, e4.come_why, r4["d"], r4["free"], e4.grudge]))
	for o in g.enemies.duplicate():
		if o == e4 or o.type == "imp":
			g.enemies.erase(o)
	# ---- 24 Nov (user: "make them break walls chase and summon enemies aggresively") ----
	# 6. hidden in the tunnel and never struck: it comes anyway once it has had no way to you a while
	pu_course.call()
	_go(pu_at.call(200, 46))
	await _frames(30)
	var e6 = g.spawn_enemy("boss_forest", pu_at.call(60, 80))
	e6.awake = true
	var f6 := -1
	var near6 := 1e9
	for k6 in 700:
		await _frames(1)
		e6.act_cd = maxi(e6.act_cd, 40)
		near6 = minf(near6, e6.pos.distance_to(g.player.pos))
		if e6.came_n > 0 or near6 < 40.0:
			f6 = k6
			await _frames(20)
			break
	# (it comes for you, or smashes its way in first: either way it gets to you)
	var ok6: bool = f6 >= 0 and e6.pos.distance_to(g.player.pos) < 90.0
	pu_good = pu_good and ok6
	pu_lines.append("hidden, never struck: %s" % (("it got to you after %.1f s (%s, %d holes smashed)" % [float(f6) / 60.0, e6.come_why if e6.came_n > 0 else "broke in", e6.breach_hits]) if ok6 else "(!) it never came (came %d, kept %d, why '%s', nearest %.0f)" % [e6.came_n, e6.kept_t, e6.come_why, near6]))
	g.enemies.erase(e6)
	# 7. a walking guardian with no charge of its own (the Mycelord) at a brick hut: it smashes its way in
	pu_course.call()
	var HW := 33
	var HH := 30
	var hd := PackedInt32Array()
	hd.resize(HW * HH)
	for hj in HH:
		for hi in HW:
			var wall: bool = hi < 3 or hi >= HW - 3 or hj < 3
			hd[hj * HW + hi] = (Defs.BRICK | 0xFF00 | 0x20000) if wall else (Defs.AIR | 0xFF00)
	g.stamps.append({"x0": pu_c.x + 20, "y0": pu_c.y + 66, "w": HW, "h": HH, "data": hd, "ax": pu_c.x, "aw": PW})
	_go(pu_at.call(36, 86))
	await _frames(30)
	var e7 = g.spawn_enemy("boss_grove", pu_at.call(100, 80))
	e7.awake = true
	var in7 := -1
	var holes7 := 0
	for k7 in 900:
		await _frames(1)
		holes7 = maxi(holes7, e7.breach_hits)
		if e7.pos.distance_to(g.player.pos) < 26.0:
			in7 = k7
			break
	var ok7: bool = in7 >= 0 and holes7 > 0
	pu_good = pu_good and ok7
	pu_lines.append("the Mycelord at a brick hut: %s" % (("smashed in to you in %.1f s, %d holes" % [float(in7) / 60.0, holes7]) if ok7 else "(!) in %d, holes %d, came %d (%s), unreachable %d" % [in7, holes7, e7.came_n, e7.come_why, e7.unreach_t]))
	g.enemies.erase(e7)
	# 8. a guardian with no summoning of its own calls its biome's fighters, roused
	var calls := []
	for cb in ["forest", "jungle", "marsh", "tundra", "mountain", "savanna", "desert", "grove", "ashland", "ocean"]:
		var ce = g.spawn_enemy("boss_" + cb, pu_at.call(60, 40))
		calls.append("%s %s" % [cb, BossAI._call_type(ce) if BossAI._call_type(ce) != "" else "(its own)"])
		g.enemies.erase(ce)
	print("[pursuit] calls: " + ", ".join(calls))
	pu_course.call()
	_go(pu_at.call(90, 86))
	await _frames(20)
	var e8 = g.spawn_enemy("boss_forest", pu_at.call(60, 80))
	e8.awake = true
	var called := []
	for k8 in 1500:
		await _frames(1)
		for o8 in g.enemies:
			if o8.summoner == e8 and not called.has(o8):
				called.append(o8)
		if called.size() > 0:
			break
	var roused := true
	for o8b in called:
		roused = roused and o8b.provoked and o8b.awake
	var ok8: bool = called.size() > 0 and roused and BossAI._call_type(e8) != ""
	pu_good = pu_good and ok8
	pu_lines.append("Bramblehorn calls %s: %s" % [BossAI._call_type(e8), ("%d came, roused" % called.size()) if ok8 else "(!) %d came, roused %s" % [called.size(), roused]])
	for o8c in g.enemies.duplicate():
		if o8c == e8 or called.has(o8c):
			g.enemies.erase(o8c)
	# 9. Vulkhar calls imps while he fights, not only when he's kept from you
	var e9 = g.spawn_enemy("golem", pu_at.call(60, 80))
	e9.awake = true
	var imps9 := 0
	for k9 in 120:
		await _frames(1)
	for o9 in g.enemies:
		if o9.type == "imp":
			imps9 += 1
	pu_good = pu_good and imps9 > 0
	pu_lines.append("Vulkhar in reach: %s" % (("%d imps called" % imps9) if imps9 > 0 else "(!) no imps"))
	for o9b in g.enemies.duplicate():
		if o9b == e9 or o9b.type == "imp":
			g.enemies.erase(o9b)
	g.stamps.append({"x0": pu_c.x, "y0": pu_c.y, "w": PW, "h": PH, "data": pu_mk.call(true), "ax": pu_c.x, "aw": PW})
	g.test_god = pu_god0
	_go(pu_orig)
	await _frames(20)
	_ok("a boss struck from where it can't follow comes to you: onto a ledge, or blasting in beside you; Vulkhar too; and they hunt you down, smash in and call help", pu_good, "; ".join(pu_lines))

## The heart bosses (Defs.HEARTS; user, 26 Nov: "different bosses at the heart of different kinds of worlds"):
## each kind's comes to the right world (`heart_type`: Vulkhar on temperate worlds), its frames grow from its body,
## and each one that fights on land is set down on clear ground here, kept to a chamber's bounds round it: it
## wakes only with you inside, fights with its moves, stays clear of the ground and in bounds, falls and gives up its
## relic (whose powers then count in `gear`). (The deep ocean world's swims, so it's only grown and mapped here.)
func _test_hearts() -> void:
	var hb_items0: Dictionary = g.items.duplicate()
	var hb_hp0: float = g.max_hp
	var hb_mana0: float = g.max_mana
	var hb_regen0: float = g.mana_regen
	var hb_dead0 = g.planet_state.get("boss_dead", false)
	var hb_god0: bool = g.test_god
	var hb_back: Vector2 = g.player.pos
	g.test_god = true
	g.test_calm = false
	var hb_rows := []
	var hb_ok := true
	# who waits where
	var hb_map_ok: bool = Defs.heart_type("temperate") == "golem" and Defs.heart_type("giant") == "heart_giant"
	for hk0 in ["volcanic", "ocean", "desert", "marsh", "frozen", "wild", "realm", "abyss"]:
		hb_map_ok = hb_map_ok and Defs.heart_type(hk0) == "heart_" + hk0
	hb_rows.append("each kind's own at its heart, Vulkhar on temperate worlds: %s" % hb_map_ok)
	hb_ok = hb_ok and hb_map_ok
	var BA = load("res://scripts/boss_art.gd")
	var hb_st := _clear_stretch(Build.cell_of(start_pos).x + 60, 200, 110, 6)
	var hb_mid := hb_st.x + 100
	for hk in Defs.HEARTS:
		var hd: Dictionary = Defs.HEARTS[hk]
		var hb_fr: Dictionary = BA.frames("heart_" + hk, hd["body"])
		if hb_fr.is_empty():
			hb_rows.append("(!) %s: no frames" % hk)
			hb_ok = false
			continue
		if hd.get("swim", false):
			hb_rows.append("%s (%s): %d frames, a swimmer (fought in its flooded chamber)" % [hk, hd["name"], hb_fr.size()])
			continue
		# set down as in its chamber (main `_spawn_heart_boss`): on the floor, kept to 88 either way and 76 up
		var hb_row: int = g.builds.ground_row(hb_mid)
		var hb_floor: Vector2 = _cell_pos(hb_mid, hb_row - 1)
		var hb_up: Vector2 = hb_floor.normalized()
		var hb_e = g.spawn_enemy("heart_" + hk, hb_floor + hb_up * (float(hd["h"]) * 0.5 + 2.0))
		hb_e.tether = 88.0
		hb_e.ceil = 76.0
		hb_e.home = hb_e.pos
		# (it stays asleep while you're outside its chamber)
		_go(_cell_pos(hb_mid + 160, g.builds.ground_row(hb_mid + 160) - 12))
		g.player.dead = false
		await _frames(30)
		var hb_slept: bool = not hb_e.awake
		_go(_cell_pos(hb_mid - 40, g.builds.ground_row(hb_mid - 40) - 12))
		g.player.dead = false
		var hb_lg0: Vector2 = g.to_grid(hb_e.pos)
		var hb_stuck: bool = g.box_solid(hb_lg0.x - hb_e.w * 0.5 + 1.0, hb_lg0.y - hb_e.h * 0.5 + 1.0, hb_e.w - 2.0, hb_e.h - 3.0)
		var hb_walk := 0.0
		var hb_out := 0.0
		var hb_last: Vector2 = hb_e.pos
		var hb_br: Vector2 = g.basis_r(atan2(hb_e.home.y, hb_e.home.x))
		for hb_f in 240:
			await _frames(1)
			if hb_f == 150:
				g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("heart_%s.png" % hk))
			if hb_e.dead:
				break
			hb_walk += hb_e.pos.distance_to(hb_last)
			hb_last = hb_e.pos
			hb_out = maxf(hb_out, absf((hb_e.pos - hb_e.home).dot(hb_br)) - hb_e.tether)
			g.player.hp = g.player.max_hp
		var hb_awake: bool = hb_e.awake
		var hb_moves: int = hb_e.moves_done
		var hb_rel: String = hd["relic"]
		g._hurt_enemy(hb_e, 99999.0, 0.0, 0.0)
		await _frames(2)
		var hb_got: bool = g.items.has(hb_rel)
		var hb_dead: bool = bool(g.planet_state.get("boss_dead", false))
		g.planet_state["boss_dead"] = hb_dead0
		var hb_good: bool = hb_slept and hb_awake and hb_moves >= 1 and hb_got and hb_dead and not hb_stuck and hb_walk > 20.0 and hb_out < 20.0
		hb_ok = hb_ok and hb_good
		hb_rows.append("%s%s (%s): asleep outside %s, woke %s, %d moves, moved %.0f, past its bounds %.0f, clear %s, relic %s" % ["" if hb_good else "(!) ", hk, hd["name"],
			hb_slept, hb_awake, hb_moves, hb_walk, hb_out, not hb_stuck, hb_got])
		for o in g.enemies.duplicate():
			if o.summoner == null and not o.boss and o.pos.distance_to(hb_floor) < 300.0:
				g.enemies.erase(o)          # (what it called, so the next has a clear field)
	# a relic's powers count in gear: the Sunscale Ankh digs two fifths faster
	g.items["sunankh"] = true
	var hb_dig: float = g.gear("dig_rate")
	g.items.erase("sunankh")
	var hb_dig0: float = g.gear("dig_rate")
	var hb_gear_ok: bool = absf(hb_dig / maxf(hb_dig0, 0.001) - 1.4) < 0.01
	hb_ok = hb_ok and hb_gear_ok
	hb_rows.append("a relic's powers in gear: dig %.2f with the ankh, %.2f without" % [hb_dig, hb_dig0])
	for hb_r in Defs.RELICS:
		if not hb_items0.has(hb_r):
			g.items.erase(hb_r)
	g.max_hp = hb_hp0
	g.hp = minf(g.hp, hb_hp0)
	g.max_mana = hb_mana0
	g.mana_regen = hb_regen0
	g._apply_gear()
	g.planet_state["boss_dead"] = hb_dead0
	g.test_god = hb_god0
	g.test_calm = true
	g.boss_clouds.clear()
	_go(hb_back)
	await _frames(60)
	_ok("each kind of world's heart boss: the right one at each heart, grown, asleep till you come in, fights, falls, gives its relic", hb_ok, "; ".join(hb_rows))

func _test_guardians(only_biomes := []) -> void:
	# ---- the biome guardians: each called at a Summoning Altar built in its biome with its sigil; it comes
	# at a clear spot (never in the ground), fights with its moves, falls, gives its relic ----
	var gd_items0: Dictionary = g.items.duplicate()
	var gd_hp0: float = g.max_hp
	var gd_god0: bool = g.test_god
	var gd_back: Vector2 = g.player.pos
	g.test_god = true
	g.test_calm = false
	var gd_rows := []
	var gd_ok := 0
	var gd_lairs: Array = []
	for gd_b0 in g.summoning.callable_biomes():
		if only_biomes.is_empty() or only_biomes.has(gd_b0):
			gd_lairs.append({"biome": gd_b0})
	for gd_l in gd_lairs:
		var gd_bio: String = gd_l["biome"]
		var gd_wet: bool = Defs.BOSSES[gd_bio].get("swim", false) or Defs.BOSSES[gd_bio].get("wet", false)
		var gd_mid := _biome_mid_col(gd_bio)
		if gd_mid < 0:
			gd_rows.append("%s: no stretch of it found" % gd_bio)
			continue
		# the altar: on level, clear ground in the biome (in a sea, on the seabed)
		var gd_col := gd_mid
		var gd_row: int = g.builds.ground_row(gd_mid)
		if gd_wet:
			# (a swimmer's altar on the seabed where the water's deepest near the middle: the kelp isles' middle
			# can be a dry sand bar or a shallow pool)
			var gd_deep := -1.0
			for gd_dw in range(-1500, 1501, 8):
				var gcw: int = gd_mid + gd_dw
				if g.builds.biome(gcw) != gd_bio:
					continue
				var gxw := posmod(gcw, g.builds.N0)
				var gdep: float = g.builds.surf[gxw * 8 + 5] - g.builds.surf[gxw * 8]
				if gdep > gd_deep + 2.0:
					gd_deep = gdep
					gd_col = gcw
			gd_row = g.builds.ground_row(gd_col)
		if not gd_wet:
			# (open, fairly level ground in the biome, with no building within 80 columns: a guardian boxed
			# in between houses, you on a roof, can't get at you)
			var gd_found := false
			for gd_d in range(0, 3000, 16):
				for gd_sg in [1, -1]:
					var gc: int = gd_mid + gd_d * gd_sg
					if gd_found or g.builds.biome(gc) != gd_bio or g.builds.wet(gc):
						continue
					var gmn := 1 << 30
					var gmx := -(1 << 30)
					var gd_clear := true
					for gq in range(-80, 81, 8):
						var gr2: int = g.builds.ground_row(gc + gq)
						if absi(gq) <= 24:
							gmn = mini(gmn, gr2)
							gmx = maxi(gmx, gr2)
						if g.builds.label_at(_cell_pos(gc + gq, gr2 - 6)) != "" or g.builds.label_at(_cell_pos(gc + gq, gr2 - 30)) != "":
							gd_clear = false
							break
					if gd_clear and gmx - gmn <= 6:
						gd_col = gc
						gd_row = g.builds.ground_row(gc)
						gd_found = true
				if gd_found:
					break
		var gd_alt = g.workshops.add("altar", _cell_pos(gd_col, gd_row - 8))
		var gd_up0: Vector2 = gd_alt.pos.normalized()
		_go(gd_alt.pos + g.basis_r(atan2(gd_alt.pos.y, gd_alt.pos.x)) * -16.0 + gd_up0 * 4.0)
		g.player.dead = false
		await _frames(40)
		g.items["sigil_" + gd_bio] = 1
		var gd_why: String = g.summoning.try_summon(g.player, gd_alt)
		var gd_e = null
		for gd_w in 240:
			await _frames(1)
			gd_e = g.summoning.active_guardian(gd_bio)
			if gd_e != null:
				break
		if gd_e == null:
			gd_rows.append("(!) %s: not called (%s)" % [gd_bio, gd_why if gd_why != "" else "nothing came"])
			g.workshops.list.erase(gd_alt)
			continue
		# (it came clear of the ground: not stuck in it, as one waiting in its lair was)
		var gd_lg0: Vector2 = g.to_grid(gd_e.pos)
		var gd_stuck: bool = g.box_solid(gd_lg0.x - gd_e.w * 0.5 + 1.0, gd_lg0.y - gd_e.h * 0.5 + 1.0, gd_e.w - 2.0, gd_e.h - 3.0) and gd_e.d["def"]["go"] != "burrow"
		var gd_in_water: bool = Defs.KIND[g.type_at(gd_e.pos)] == Defs.K_LIQUID
		guard_info[gd_bio] = {"wet": gd_in_water}
		g.player.dead = false
		# how it moves while it fights: how high it gets, how far it strays, how much it gets around
		var gd_up := 0.0
		var gd_out := 0.0
		var gd_walk := 0.0
		var gd_last: Vector2 = gd_e.pos
		var gd_home: Vector2 = gd_e.home
		var gd_br: Vector2 = g.basis_r(atan2(gd_home.y, gd_home.x))
		for gd_f in 240:
			await _frames(1)
			if gd_f == 150:
				g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("boss_%s.png" % gd_bio))
			if gd_e.dead:
				break
			var gd_o: Vector2 = gd_e.pos - gd_home
			gd_up = maxf(gd_up, gd_o.dot(gd_home.normalized()))
			gd_out = maxf(gd_out, absf(gd_o.dot(gd_br)) - gd_e.tether)
			gd_walk += gd_e.pos.distance_to(gd_last)
			gd_last = gd_e.pos
			if gd_f % 15 == 0 and only_now == "guardians":
				var gd_lg: Vector2 = g.to_grid(gd_e.pos)
				print("[guardian] %s f%d along %.1f up %.1f vx %.2f vy %.2f %s%s act '%s' move '%s' cd %d pace %.0f wall %s under: %s" % [gd_bio, gd_f, gd_o.dot(gd_br), gd_o.dot(gd_home.normalized()),
					gd_e.vx, gd_e.vy, "ground" if gd_e.on_ground else "air", " platform" if gd_e.on_platform else "", gd_e.act, gd_e.move, gd_e.act_cd, gd_e.pace,
					gd_e.hit_wall, str([g.gtype(int(gd_lg.x), int(gd_lg.y + gd_e.h * 0.5)), g.gtype(int(gd_lg.x), int(gd_lg.y + gd_e.h * 0.5) + 1), Defs.NAMES[g.gtype(int(gd_lg.x), int(gd_lg.y + gd_e.h * 0.5))]])])
		var gd_moves: int = gd_e.moves_done
		var gd_awake: bool = gd_e.awake
		var gd_rel: String = gd_e.d["def"]["relic"]
		g._hurt_enemy(gd_e, 99999.0, 0.0, 0.0)
		await _frames(2)
		var gd_got: bool = g.items.has(gd_rel)
		var gd_dead: bool = (g.planet_state.get("bosses_dead", []) as Array).has(gd_bio)
		# (it stays on screen: never more than about 80 cells up; in its lair; and on the move)
		var gd_flies: bool = gd_e.d["def"]["go"] == "fly" or gd_e.d["def"]["go"] == "slither"
		var gd_good: bool = gd_awake and gd_moves >= 1 and gd_got and gd_dead and not gd_stuck and gd_up < (95.0 if gd_flies else 70.0) and gd_out < 14.0 and gd_walk > 30.0
		if gd_good:
			gd_ok += 1
		gd_rows.append("%s%s: called, came clear %s%s, awake %s, %d moves, relic %s, highest %.0f, past its ground %.0f, moved %.0f" % ["" if gd_good else "(!) ", gd_bio, not gd_stuck,
			" in the water" if gd_in_water else "", gd_awake, gd_moves, gd_got, gd_up, gd_out, gd_walk])
		g.workshops.list.erase(gd_alt)
	# (the relics are given back, so the checks after this aren't changed by them)
	for gd_r in Defs.RELICS:
		if not gd_items0.has(gd_r):
			g.items.erase(gd_r)
	g.max_hp = gd_hp0
	g.hp = minf(g.hp, gd_hp0)
	g.test_god = gd_god0
	g.test_calm = true
	g.boss_clouds.clear()
	_go(gd_back)                   # (back where the checks after this one expect you)
	await _frames(60)
	if only_biomes.is_empty():
		_ok("each biome's guardian comes to its sigil at an altar, clear of the ground, fights and gives up its relic", gd_lairs.size() >= 8 and gd_ok == gd_lairs.size(),
			"%d guardians; %s" % [gd_lairs.size(), "; ".join(gd_rows)])
	else:
		_ok("%s: the %s guardian comes to its sigil at an altar, fights and gives up its relic" % [g.planet["name"], " and ".join(only_biomes)],
			gd_lairs.size() == only_biomes.size() and gd_ok == gd_lairs.size(),
			"; ".join(gd_rows))

## the dungeon wardens: each waits in the hall before its reliquary (asleep until you come into the
## hall), fights with its moves, and its fall breaks the runestone ward on the reliquary's door
func _test_wardens() -> void:
	var wn_items0: Dictionary = g.items.duplicate()
	var wn_god0: bool = g.test_god
	var wn_back: Vector2 = g.player.pos
	g.test_god = true
	var wn_rows := []
	var wn_ok := 0
	var wn_list: Array = g.builds.warden_list
	for wn_i in wn_list.size():
		var wn_l: Dictionary = wn_list[wn_i]
		var wn_key: String = wn_l["key"]
		var wn_e = null
		for wn_en in g.enemies:
			if wn_en.type == wn_key and not wn_en.dead:
				wn_e = wn_en
		if wn_e == null:
			wn_rows.append("%s: no warden" % wn_l["name"])
			continue
		var wn_wd: Dictionary = wn_e.d["def"]
		var wr: Dictionary = wn_l["ward"]
		var wn_at: Vector2 = wn_l["pos"]
		var wn_side: Vector2 = g.basis_r(atan2(wn_at.y, wn_at.x))
		# from the room next door (beyond its hall) it stays asleep
		g.test_calm = false
		_go(wn_at + wn_side * (float(wn_e.tether) + 60.0) + wn_at.normalized() * 10.0)
		await _frames(30)
		var wn_slept: bool = not wn_e.awake
		# in its hall it wakes and fights
		_go(wn_at + wn_side * 26.0 + wn_at.normalized() * 10.0)
		g.player.dead = false
		var wn_walk := 0.0
		var wn_last: Vector2 = wn_e.pos
		var wn_out := 0.0
		var wn_br: Vector2 = g.basis_r(atan2(wn_e.home.y, wn_e.home.x))
		for wn_f in 240:
			await _frames(1)
			if wn_f == 150:
				g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("warden_%d.png" % wn_i))
			if wn_e.dead:
				break
			wn_walk += wn_e.pos.distance_to(wn_last)
			wn_last = wn_e.pos
			wn_out = maxf(wn_out, absf((wn_e.pos - wn_e.home).dot(wn_br)) - wn_e.tether)
		var wn_moves: int = wn_e.moves_done
		var wn_awake: bool = wn_e.awake
		# the ward before (runestone), and after it falls (open)
		var wn_before := 0
		for v in g.gpu.read_rect(int(wr["x0"]), int(wr["y0"]), int(wr["w"]), int(wr["h"]), int(wr["ax"]), int(wr["aw"]))["fg"]:
			if (v & 255) == Defs.RUNESTONE:
				wn_before += 1
		g._hurt_enemy(wn_e, 99999.0, 0.0, 0.0)
		await _frames(4)
		var wn_after := 0
		for v2 in g.gpu.read_rect(int(wr["x0"]), int(wr["y0"]), int(wr["w"]), int(wr["h"]), int(wr["ax"]), int(wr["aw"]))["fg"]:
			if (v2 & 255) != Defs.AIR:
				wn_after += 1
		var wn_dead: bool = (g.planet_state.get("bosses_dead", []) as Array).has(wn_key)
		var wn_n: int = int(wr["w"]) * int(wr["h"])
		var wn_fine: bool = wn_slept and wn_awake and wn_moves >= 1 and wn_dead and wn_before == wn_n and wn_after == 0 and wn_out < 14.0
		if wn_fine:
			wn_ok += 1
		wn_rows.append("%s%s, %s (%s): asleep from next door %s, awake %s, %d moves, moved %.0f, past its hall %.0f, ward %d/%d runestone then %d left" % [
			"" if wn_fine else "(!) ", wn_wd["name"], wn_wd["title"], wn_wd["body"]["plan"], wn_slept, wn_awake, wn_moves, wn_walk, wn_out, wn_before, wn_n, wn_after])
		# (its minions go too, so they don't follow you into the checks after this)
		for wn_m in g.enemies:
			if wn_m.summoner == wn_e or (wn_m.summoner == null and not wn_m.boss and wn_m.pos.distance_to(wn_at) < 150.0 and wn_m.guard_id < 0):
				wn_m.dead = true
	for wn_r in g.items.keys():
		if not wn_items0.has(wn_r):
			g.items.erase(wn_r)
	g.items["potion"] = wn_items0.get("potion", 0)
	g.test_god = wn_god0
	g.test_calm = true
	g.boss_clouds.clear()
	_go(wn_back)
	await _frames(60)
	_ok("each dungeon's warden waits in its hall, fights, and its fall breaks the reliquary's ward", wn_list.size() >= 2 and wn_ok == wn_list.size(),
		"%d wardens: %s" % [wn_list.size(), "; ".join(wn_rows)])

## Staircases (build mode, roadmap step 8): a flight one storey high set down on clear ground still
## stands a few seconds later (its posts hold it up), and the mage walks up it to the top
## Foes come in fewer and farther (user, 22 Nov: too many, too aggressive on the starting planet; one fell in
## from the top of the screen; "give the player some breathing room if they kill all the enemies in an area"):
## on the first planet by day no more than its cap are about, each comes in out of view and no nearer than
## SPAWN_MIN_DIST, and once you've cleared the area nothing more comes for a while.
func _test_spawns() -> void:
	var sw_back: Vector2 = g.player.pos
	var sw_time0: float = g.time
	g.test_no_wild = false
	for e0 in g.enemies.duplicate():
		if not e0.boss:
			g.enemies.erase(e0)
	var sw_st := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) + 30, 60, 60, 6)
	_go(_cell_pos(sw_st.x + 30, sw_st.y - 12))
	await _frames(30)
	g.time = g.towns.time_for_hour(g.player.pos, 12.0)
	g.quiet_until = -1
	var known := {}
	var made := 0
	var near := 0
	var seen := 0
	var most := 0
	var vrect := Rect2(0, 0, g.VW, g.VH)
	for k in 160:
		g.spawn_timer = 0
		g._try_spawn()
		var cnt := 0
		for e in g.enemies:
			if e.boss:
				continue
			cnt += 1
			var key: int = e.get_instance_id()
			if known.has(key):
				continue
			known[key] = true
			made += 1
			if e.pos.distance_to(g.player.pos) < g.SPAWN_MIN_DIST - 2.0:
				near += 1
			if vrect.has_point(g.world_to_screen(e.pos)):
				seen += 1
		most = maxi(most, cnt)
		await _frames(1)
	var cap: int = g.spawn_cap(false)
	# clear them all: the area falls quiet, and nothing more comes
	for e2 in g.enemies.duplicate():
		if not e2.boss and not e2.dead:
			g._kill_enemy(e2)
	await _frames(5)
	var quiet: bool = g.quiet_until > g.frame
	var after := 0
	for k2 in 60:
		g.spawn_timer = 0
		g._try_spawn()
		for e3 in g.enemies:
			if not e3.boss and not e3.dead and not known.has(e3.get_instance_id()):
				known[e3.get_instance_id()] = true
				after += 1
	for e4 in g.enemies.duplicate():
		if not e4.boss:
			g.enemies.erase(e4)
	g.test_no_wild = true
	g.quiet_until = -1
	g.time = sw_time0
	_go(sw_back)
	await _frames(20)
	_ok("foes come in fewer and farther: out of view, never near, and a cleared area stays quiet", made >= 2 and most <= cap and near == 0 and seen == 0 and quiet and after == 0,
		"%d came in (at most %d at once, the cap %d), %d nearer than %d, %d in view; cleared: quiet %s, %d came after" % [made, most, cap, near, int(g.SPAWN_MIN_DIST), seen, quiet, after])
