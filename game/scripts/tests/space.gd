extends "res://scripts/tests/player.gd"
## Checks of space and ships: the galaxy, wrecks, pirates, outposts, the cabin, the minimap, stations, fuel, the hull, the ship builder and pocket, cargo, void life, the space benchmark. (Part of the chain of test files: see tests.gd.)

func _test_galaxy() -> void:
	var gx_rows := []
	var gx_ok := true
	var G = load("res://scripts/galaxy.gd")
	# the maths
	var gx_bij := true
	var gx_seen := {}
	for r in 3000:
		var c: Vector2i = Defs.spiral_cell(r)
		if gx_seen.has(c) or Defs.spiral_index(c) != r:
			gx_bij = false
		gx_seen[c] = true
	var gx_first: bool = Defs.system_g(0)[0] == 0.0 and Defs.system_g(0)[1] == 0.0 and Defs.planet_pos(1) - Defs.planet_pos(0) == (Defs.SYSTEM[1] - Defs.SYSTEM[0] if Defs.world_seed == 0 else Defs.planet_pos(1) - Defs.planet_pos(0))
	var gx_far: Vector2 = Defs.g_rel(Defs.planet_g(5 * 2000 + 3), Defs.planet_g(5 * 2000))
	var gx_n := 0
	for sy in 20:
		for sx in 20:
			if not G.sector_content(Vector2i(sx - 300, sy + 170)).is_empty():
				gx_n += 1
	var gx_ok1: bool = gx_bij and gx_first and gx_far.length() > 40000.0 and gx_far.length() < 80000.0 and gx_n > 120 and gx_n < 260
	gx_rows.append("[home %d] %sthe spiral of systems is one to one %s, the first system as it was %s, a planet of system 2000 from its first exactly %.0f away, %d of 400 sectors hold something" % [g.space.home, "" if gx_ok1 else "(!) ", gx_bij, gx_first, gx_far.length(), gx_n])
	gx_ok = gx_ok and gx_ok1
	# the skiff, and up into space
	g.player.dead = false
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var gx_up: Vector2 = sk.pos.normalized()
	sk.pos = gx_up * (Defs.R_SPACE - 11.0)
	sk.vel = gx_up * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	# (well clear of home first: straight out)
	for k1 in 200:
		g.test_aim = sk.pos + sk.pos.normalized() * 1000.0
		await _frames(1)
	var gx_in: bool = g.space.active
	var home0: int = g.space.home
	# out, by the Starsail, the way with no planet in it
	g.items["sail"] = true
	var best_dir := Vector2.RIGHT
	var best_sep := -1.0
	var out_dir: Vector2 = sk.pos.normalized()
	for q in 72:
		var d := Vector2.from_angle(TAU * float(q) / 72.0)
		# (as far as can be from the way to every planet, home too: sail near one and a journey to it
		# begins, as it should)
		var sep := 9.0
		for b in g.space.bodies:
			var o: Vector2 = b["pos"] - sk.pos
			if o.length() < 1.0:
				continue
			sep = minf(sep, absf(angle_difference(o.angle(), d.angle())))
		if sep > best_sep:
			best_sep = sep
			best_dir = d
	print("[galaxy] out_dir %s best_dir %s (sep %.2f), skiff at %s" % [str(out_dir), str(best_dir), best_sep, str(sk.pos)])
	g.test_sail = true
	var gx_top := 0.0
	var gx_rec0: int = g.space.stats["recentred"]
	var gx_maxpos := 0.0
	var gx_shot := false
	for k2 in 720:
		g.test_aim = sk.pos + best_dir * 1000.0
		await _frames(1)
		gx_top = maxf(gx_top, sk.vel.length())
		gx_maxpos = maxf(gx_maxpos, sk.pos.length())
		if not gx_shot and sk.vel.length() > 250.0:
			gx_shot = true
			await _frames(2)
			_shot("galaxy_sail.png")
	var gx_from_home: float = Defs.g_rel(g.space.player_g(), Defs.planet_g(home0)).length()
	g.test_sail = false
	for k3 in 200:
		g.test_aim = sk.pos + best_dir * 1000.0
		await _frames(1)
		if sk.vel.length() < 60.0:
			break
	g.test_cast = false
	var gx_slow: float = sk.vel.length()
	var gx_ok2: bool = gx_in and gx_top > 250.0 and gx_from_home > 100000.0 and g.space.stats["recentred"] > gx_rec0 and gx_maxpos < g.space.RECENTRE + 1000.0 and not g.space.at_home() and gx_slow < 60.0
	gx_rows.append("[home %d] %sout in space %s; the Starsail ran up to %.0f a tick, %.0f out from home, space's origin followed %d times (never more than %.0f from (0, 0)), let go it slowed to %.0f" % [g.space.home, "" if gx_ok2 else "(!) ", gx_in, gx_top, gx_from_home, g.space.stats["recentred"] - gx_rec0, gx_maxpos, gx_slow])
	gx_ok = gx_ok and gx_ok2
	# a field: its rocks stream in; one mined, left behind and come back to, as it was left
	var gp: PackedFloat64Array = g.space.player_g()
	var sc: Vector2i = G.sector_of(gp[0], gp[1])
	var field_s = null
	var comet_s = null
	for rr in range(1, 12):
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if maxi(absi(dx), absi(dy)) != rr:
					continue
				var s2: Vector2i = sc + Vector2i(dx, dy)
				var cont: Array = G.sector_content(s2)
				if cont.is_empty():
					continue
				# (well away from every planet: come near one and a journey to it begins, as it should)
				var s2g: PackedFloat64Array = G.sector_g(s2)
				var s2x: float = s2g[0] + (cont[0]["at"] as Vector2).x
				var s2y: float = s2g[1] + (cont[0]["at"] as Vector2).y
				var by_planet := false
				for pr in G.systems_near(s2x, s2y, 200000.0):
					for pk in Defs.planets_of(pr):
						if Defs.g_rel(Defs.planet_g(pk), PackedFloat64Array([s2x, s2y])).length() < 80000.0:
							by_planet = true
				if by_planet:
					continue
				if field_s == null and cont[0]["type"] == "field":
					field_s = s2
				if comet_s == null and cont[0]["type"] == "comet":
					comet_s = s2
	var gx_ok3 := false
	var f_n := -1
	var f_got := -1
	var f_saved := false
	var f_back := -1
	var f_c1 := -1
	if field_s != null:
		var fc: Dictionary = G.sector_content(field_s)[0]
		var fsg: PackedFloat64Array = G.sector_g(field_s)
		var fat: Vector2 = fc["at"]
		var fkey: String = G.key_of(field_s)
		sk.pos = g.space.local_of(PackedFloat64Array([fsg[0] + fat.x, fsg[1] + fat.y])) + Vector2(0, -1400.0)
		sk.vel = Vector2.ZERO
		await _frames(120)
		var mine = null
		f_n = 0
		for a in g.space.rocks:
			if a.sect == fkey:
				f_n += 1
				mine = a
		_shot("galaxy_field.png")
		if mine != null:
			var c0: int = mine.count()
			var took := 0
			for ci in mine.cells.size():
				if mine.cells[ci] != 0 and took < 40:
					mine.take(ci)
					took += 1
			mine.settle_mass()
			f_c1 = mine.count()
			f_got = c0 - f_c1
			# far off (the sector goes), then back
			sk.pos += best_dir * 90000.0
			await _frames(60)
			f_saved = g.space.sect_state.has(fkey) and not g.space._loaded.has(fkey)
			sk.pos = g.space.local_of(PackedFloat64Array([fsg[0] + fat.x, fsg[1] + fat.y])) + Vector2(0, -1400.0)
			sk.vel = Vector2.ZERO
			await _frames(120)
			for a2 in g.space.rocks:
				if a2.sect == fkey and a2.count() == f_c1:
					f_back = f_c1
		gx_ok3 = f_n == (fc["rocks"] as Array).size() and f_got == 40 and f_saved and f_back == f_c1
	gx_rows.append("[home %d] %sa field's %d rocks streamed in, 40 cells mined (%d), kept when left %s, found again as left %s" % [g.space.home, "" if gx_ok3 else "(!) ", f_n, f_got, f_saved, f_back == f_c1 and f_c1 >= 0])
	gx_ok = gx_ok and gx_ok3
	# a comet on its loop
	var gx_ok4 := false
	var cm_moved := 0.0
	var cm_err := -1.0
	if comet_s != null:
		var cc: Dictionary = G.sector_content(comet_s)[0]
		var csg: PackedFloat64Array = G.sector_g(comet_s)
		var cat: Vector2 = cc["at"]
		var cp: Vector2 = G.comet_at(cc["rocks"][0]["orbit"], g.time)
		sk.pos = g.space.local_of(PackedFloat64Array([csg[0] + cat.x + cp.x, csg[1] + cat.y + cp.y])) + Vector2(0, -260.0)
		sk.vel = Vector2.ZERO
		await _frames(90)
		var cm = null
		var ckey: String = G.key_of(comet_s)
		for a3 in g.space.rocks:
			if not a3.orbit.is_empty() and (cm == null or a3.sect == ckey):
				cm = a3                      # (its own sector's comet: in the full run another one is streamed in too)
		if cm != null:
			sk.pos = cm.pos + Vector2(0, -260.0)
			sk.vel = Vector2.ZERO
			await _frames(8)                 # (space's origin may follow you over first: everything moves with it)
			sk.pos = cm.pos + Vector2(0, -260.0)
			sk.vel = Vector2.ZERO
			var p0: Vector2 = cm.pos
			await _frames(30)
			cm_moved = cm.pos.distance_to(p0)
			var want: Vector2 = g.space.local_of(PackedFloat64Array([csg[0] + cat.x, csg[1] + cat.y])) + G.comet_at(cm.orbit, g.time)
			cm_err = cm.pos.distance_to(want)
			# (close by for its picture, its tail streaming behind it)
			for k6 in 40:
				sk.pos = cm.pos + Vector2(-70.0, -60.0)
				sk.vel = Vector2.ZERO
				await _frames(1)
			_shot("galaxy_comet.png")
		gx_ok4 = cm != null and cm_moved > 20.0 and cm_err >= 0.0 and cm_err < 8.0
	gx_rows.append("[home %d] %sa comet keeps to its loop: moved %.0f in half a second, %.1f off where its loop puts it" % [g.space.home, "" if gx_ok4 else "(!) ", cm_moved, cm_err])
	gx_ok = gx_ok and gx_ok4
	# a nebula
	var nb_at = null
	var gp2: PackedFloat64Array = g.space.player_g()
	for ny in range(-30, 31):
		for nx in range(-30, 31):
			var tx: float = gp2[0] + float(nx) * 100000.0
			var ty: float = gp2[1] + float(ny) * 100000.0
			if float(G.nebula(tx, ty)[0]) > 0.7 and nb_at == null:
				var nb_clear := true
				for pr2 in G.systems_near(tx, ty, 200000.0):
					for pk2 in Defs.planets_of(pr2):
						if Defs.g_rel(Defs.planet_g(pk2), PackedFloat64Array([tx, ty])).length() < 80000.0:
							nb_clear = false
				if nb_clear:
					nb_at = PackedFloat64Array([tx, ty])
	var gx_neb := -1.0
	if nb_at != null:
		sk.pos = g.space.local_of(nb_at)
		sk.vel = Vector2.ZERO
		await _frames(150)
		gx_neb = g.space.neb
		_shot("galaxy_nebula.png")
	var gx_far2: float = Defs.g_rel(g.space.player_g(), Defs.planet_g(home0)).length()
	var gx_ok5: bool = nb_at != null and gx_neb > 0.4 and sk.pos.length() < g.space.RECENTRE + 1000.0
	gx_rows.append("[home %d] %sa nebula %.0fk out: thick %.2f round you, the skiff still %.0f from space's origin" % [g.space.home, "" if gx_ok5 else "(!) ", gx_far2 / 1000.0, gx_neb, sk.pos.length()])
	gx_ok = gx_ok and gx_ok5
	# the map: charted, explored, a waypoint
	var wp_g: PackedFloat64Array = g.space.player_g()
	g.space.waypoint = PackedFloat64Array([wp_g[0] + 30000.0, wp_g[1] - 12000.0])
	g.open_map()
	await _frames(10)
	var map_ok: bool = g.state == "map" and g.map_tab == "space"
	_shot("galaxy_map.png")
	g.map_view.zoom_by(60.0)
	await _frames(10)
	_shot("galaxy_map_far.png")
	g.close_map()
	await _frames(4)
	var ss: Dictionary = g.space.save_state()
	var js = JSON.parse_string(JSON.stringify(ss))
	var seen_n: int = g.space.seen.size()
	var ch_n: int = g.space.charted.size()
	g.space.load_state(js)
	var gx_ok6: bool = map_ok and g.state == "play" and seen_n > 30 and g.space.seen.size() == seen_n and g.space.charted.size() == ch_n and g.space.waypoint != null and (field_s == null or g.space.sect_state.has(G.key_of(field_s)))
	gx_rows.append("[home %d] %sthe galaxy chart opened %s; %d sectors explored and %d systems charted, saved and loaded (%d, %d), the waypoint kept %s" % [g.space.home, "" if gx_ok6 else "(!) ", map_ok, seen_n, ch_n, g.space.seen.size(), g.space.charted.size(), g.space.waypoint != null])
	gx_ok = gx_ok and gx_ok6
	g.space.waypoint = null
	# home: space's origin goes back onto it, and you land
	# (along the way you left: clear of the system's other planets, so no journey to one of them begins)
	sk.pos = g.space.home_at() + best_dir * 30000.0
	sk.vel = Vector2.ZERO
	await _frames(5)
	var gx_home: bool = g.space.at_home() and g.space.home == home0 and g.space.org[0] == Defs.planet_g(home0)[0] and g.space.org[1] == Defs.planet_g(home0)[1]
	sk.pos = sk.pos.normalized() * (Defs.R_SPACE + 150.0)
	sk.vel = -sk.pos.normalized() * 6.0
	g.test_cast = true
	var gx_back := -1
	for k4 in 600:
		g.test_aim = sk.pos * 0.3
		await _frames(1)
		if not g.space.active:
			gx_back = k4
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	var gx_land := -1
	for k5 in 1800:
		await _frames(1)
		if sk.grounded and sk.vel.length() < 0.5:
			gx_land = k5
			break
	g.test_down = false
	g.items.erase("sail")
	await _frames(30)
	# (the chart from home: the home system, close in)
	g.open_map()
	g._map_key(KEY_TAB)
	g.map_view.gz = 300.0
	g.map_view.centre_on_you()
	await _frames(10)
	_shot("galaxy_map_home.png")
	g.close_map()
	await _frames(10)
	var gx_ok7: bool = gx_home and gx_back >= 0 and gx_land >= 0 and g.player.aboard == sk and g.space.live
	gx_rows.append("[home %d] %sback home: space's origin on it exactly %s (home %d, was %d; travelling %s), in its orbit band after %d ticks, landed %d ticks later" % [g.space.home, "" if gx_ok7 else "(!) ", gx_home, g.space.home, home0, g.travelling, gx_back, gx_land])
	gx_ok = gx_ok and gx_ok7
	print("[galaxy] " + "\n[galaxy] ".join(gx_rows))
	_ok("infinite space: the Starsail, space's origin following you, streamed sectors kept as you left them, comets, nebulae, the galaxy chart, and home again", gx_ok, "; ".join(gx_rows))

func _test_wrecks() -> void:
	var wr_rows := []
	var wr_ok := true
	var G = load("res://scripts/galaxy.gd")
	var W = load("res://scripts/wreck.gd")
	# ---- grown from parts: rooms, caches, a bridge, a way in to every cache
	var wr_n := 0
	var wr_bridge := 0
	var wr_caches := 0
	var wr_reach := 0
	var wr_sizes := []
	var wr_shells := 0
	var wr_decks := 0
	for q in 12:
		# (the shell out in space: nothing in it; the wreck you board: about twice the size, three decks; user,
		# 25 Nov: boarded by a button into an instance)
		if W.make_wreck(7001 + q * 313, q == 0).caches.is_empty():
			wr_shells += 1
		var wq = W.make_wreck(7001 + q * 313, q == 0, true)
		if int(wq.meta.get("decks", 1)) == 3 and wq.w > 280:
			wr_decks += 1
		var got := _wreck_reach(wq, 8.0)
		wr_n += 1
		wr_sizes.append("%dx%d" % [wq.w, wq.h])
		var why := []
		var has_b := false
		for c in wq.caches:
			wr_caches += 1
			if c["kind"] == "bridge":
				wr_bridge += 1
				has_b = true
			if _cache_reached(wq, c, got):
				wr_reach += 1
			else:
				why.append("%s at %d,%d" % [c["kind"], int(c["i"]), int(c["j"])])
		if not has_b or not why.is_empty():
			print("[wrecks] seed %d %dx%d %s: bridge %s, not reached: %s" % [7001 + q * 313, wq.w, wq.h, str(wq.meta), has_b, ", ".join(why)])
	var wr_ok1: bool = wr_bridge == wr_n and wr_caches >= wr_n * 6 and float(wr_reach) >= float(wr_caches) * 0.85 and wr_shells == wr_n and wr_decks == wr_n
	wr_rows.append("%s%d wrecks grown to board (%s): three decks %d, %d caches, a bridge cache in %d, %d of them reached by drifting in (a disc 17 across); their shells empty %d" % ["" if wr_ok1 else "(!) ", wr_n, ", ".join(wr_sizes), wr_decks, wr_caches, wr_bridge, wr_reach, wr_shells])
	wr_ok = wr_ok and wr_ok1
	# ---- the skiff, up into space (as the galaxy's check goes)
	g.player.dead = false
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var wr_up: Vector2 = sk.pos.normalized()
	sk.pos = wr_up * (Defs.R_SPACE - 11.0)
	sk.vel = wr_up * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	for k1 in 60:
		g.test_aim = sk.pos + sk.pos.normalized() * 1000.0
		await _frames(1)
	g.test_cast = false
	# ---- the first wreck, near home: streamed in with its sector, the map knows it
	var fw: PackedFloat64Array = G.first_wreck()
	var wl: Vector2 = g.space.local_of(fw)
	var home_d: float = Defs.g_rel(fw, Defs.planet_g(0)).length()
	sk.pos = wl + Vector2.from_angle(0.7) * 400.0
	sk.vel = Vector2.ZERO
	var wk = null
	for k2 in 300:
		await _frames(1)
		sk.vel = Vector2.ZERO
		for a in g.space.rocks:
			if a.kind == "wreck" and a.pos.distance_to(wl) < 3000.0:
				wk = a
		if wk != null:
			break
	var wr_scrap := 0
	for a2 in g.space.rocks:
		if a2.kind == "scrap" and a2.pos.distance_to(wl) < 1200.0:
			wr_scrap += 1
	var wr_ok2: bool = wk != null and wk.first and home_d > 18000.0 and home_d < 26000.0
	wr_rows.append("%sthe first wreck %.0fk from home came in with its sector: %s, %d scrap round it" % ["" if wr_ok2 else "(!) ", home_d / 1000.0, ("the wreck of " + String(wk.wname)) if wk != null else "none", wr_scrap])
	wr_ok = wr_ok and wr_ok2
	if wk == null:
		_ok("derelict wrecks in deep space: found, drifted into, looted, salvaged; the skiff's shield and cannon", false, "; ".join(wr_rows))
		return
	# (26 Nov, user: "a space derelict ship that i went to on the map that wasnt actually there"): the map shows a
	# wreck where it really is, pushed off from where it was made
	var wk_p0: Vector2 = wk.pos
	wk.pos = wk_p0 + Vector2(600.0, -250.0)
	var wsct: Vector2i = g.space._loaded[wk.sect]
	var wmarks: Array = g.map_view._wrecks_of(wsct, G.sector_g(wsct), Vector2.ZERO, "?")
	var wm_ok := false
	for wm in wmarks:
		if Defs.g_rel(wm[0], g.space.galaxy_of(wk.pos)).length() < 2.0:
			wm_ok = true
	wk.pos = wk_p0
	wr_rows.append("%sthe map shows it where it is (pushed 650 off: %d marked, at it %s)" % ["" if wm_ok else "(!) ", wmarks.size(), wm_ok])
	wr_ok = wr_ok and wm_ok
	# beside it in the skiff, a picture
	var side_dir: Vector2 = (sk.pos - wk.pos).normalized()
	sk.pos = wk.pos + side_dir * (wk.reach() + 40.0)
	sk.vel = wk.vel
	await _frames(20)
	_shot("wreck_outside.png")
	# ---- F boards it: the wreck you board grown in a worker, standing where its shell drifted, nothing else
	# out here; your ship holds over its breach, you inside
	var shell = wk
	var ship_at: Vector2 = sk.pos
	var can_board: bool = g.space.dock_target(g.player) == shell
	g._interact()
	var board_t := -1
	for kb in 300:
		await _frames(1)
		if g.space.inst != null:
			board_t = kb
			break
	if g.space.inst == null:
		g.space.dock_station_now(g.player, shell)
	wk = g.space.inst
	await _frames(10)
	var inside_now: bool = wk != null and wk.halls and g.player.aboard == null and g.space.rocks.size() == 1 and not _in_cells(wk, g.player.pos)
	_shot("wreck_boarded.png")
	var wr_okb: bool = can_board and board_t >= 0 and inside_now and wk.first
	wr_rows.append("%sF boarded it %s (in %d ticks): inside %s, alone with it %s, %d caches" % ["" if wr_okb else "(!) ", can_board, board_t, inside_now, g.space.rocks.size() == 1, wk.caches.size() if wk != null else -1])
	wr_ok = wr_ok and wr_okb
	var bc: Dictionary = {}
	for c2 in wk.caches:
		if c2["kind"] == "bridge":
			bc = c2
	var wr_in_ok := false
	var wr_part := false
	if not bc.is_empty():
		g.player.pos = _over_cache(wk, bc)
		g.space.vel = wk.vel
		await _frames(20)
		wr_in_ok = g.space.near_cache == bc and wk.visited and not _in_cells(wk, g.player.pos)
		_shot("wreck_inside.png")
		g._interact()
		await _frames(10)
		wr_part = g.items.has("part_shield") and bc["open"]
	# the rest of its caches
	var hull0: int = g.player.inv[Defs.HULL]
	var opened := 0
	var closed0 := 0
	for c3 in wk.caches:
		if c3["open"]:
			continue
		closed0 += 1
		g.player.pos = _over_cache(wk, c3)
		g.space.vel = wk.vel
		await _frames(6)
		if g.space.wreck_interact(g.player):
			opened += 1
	var wr_ok3: bool = wr_in_ok and wr_part and opened == closed0 and g.space.stats["caches"] >= wk.caches.size()
	wr_rows.append("%saboard (told its fate %s), at the bridge cache %s: a Shield Emitter %s; %d of %d other caches opened (hull plating +%d)" % ["" if wr_ok3 else "(!) ", wk.visited, wr_in_ok, wr_part, opened, closed0, g.player.inv[Defs.HULL] - hull0])
	wr_ok = wr_ok and wr_ok3
	# ---- its walls hold you: the jet toward its bow, from inside
	var start: Vector2 = _over_cache(wk, bc) if not bc.is_empty() else wk.pos
	g.player.pos = start
	g.space.vel = wk.vel
	var stuck := 0
	var b_max := -1e9
	g.test_cast = true
	for k3 in 120:
		g.test_aim = g.player.pos + wk.axis_x() * 200.0
		await _frames(1)
		if _in_cells(wk, g.player.pos):
			stuck += 1
			if stuck <= 4:
				var bb: Vector2 = wk.to_body(g.player.pos) + wk.com
				print("[wrecks] in its cells at frame %d: body %.1f,%.1f of %dx%d, vel %s, wreck ang %.2f" % [k3, bb.x, bb.y, wk.w, wk.h, str(g.space.vel), wk.ang])
		b_max = maxf(b_max, (wk.to_body(g.player.pos) + wk.com).x)
	g.test_cast = false
	var b_end: Vector2 = wk.to_body(g.player.pos) + wk.com
	var still_in: bool = b_end.x > 0.0 and b_end.y > 0.0 and b_end.x < float(wk.w) and b_end.y < float(wk.h) and wk.bg[int(b_end.y) * wk.w + int(b_end.x)] != 0
	var wr_ok4: bool = stuck <= 2 and still_in
	wr_rows.append("%sthe hull holds: jetting at its bow from inside, in its cells %d frames, still inside %s (got to column %.0f of %d)" % ["" if wr_ok4 else "(!) ", stuck, still_in, b_max, wk.w])
	wr_ok = wr_ok and wr_ok4
	# ---- salvage: dig its plating
	var tier0: int = g.player.tier
	g.player.tier = maxi(tier0, 2)
	var hull1: int = g.player.inv[Defs.HULL]
	var dig_at: Vector2 = wk.cell_world(int(wk.w * 0.4), int(wk.h) - 7)
	g.player.pos = dig_at + (dig_at - wk.pos).normalized() * 14.0
	g.space.vel = wk.vel
	# (27 Nov: digging out here as on a planet: mana by hardness, the cells nearest the aim first, "+n Hull
	# Plating" popping up; the test mode's free magic is off for it)
	var dig_c: Vector2 = wk.to_body(dig_at) + wk.com
	var free0: bool = g.free_magic
	g.free_magic = false
	g.player.mana = g.player.max_mana
	var mana_d0: float = g.player.mana
	g.popups.clear()
	var popped := false
	var mana_min: float = mana_d0
	g.test_dig = true
	for k4 in 60:
		g.test_aim = dig_at
		await _frames(1)
		mana_min = minf(mana_min, g.player.mana)
		for pu in g.popups:
			if String(pu[1]).ends_with(Defs.NAMES[Defs.HULL]):
				popped = true
	g.test_dig = false
	await _frames(30)
	for pu2 in g.popups:
		if String(pu2[1]).ends_with(Defs.NAMES[Defs.HULL]):
			popped = true
	var mana_used: bool = mana_min < mana_d0 - 0.5
	g.free_magic = free0
	g.player.tier = tier0
	var mid_gone: bool = wk.at(int(dig_c.x), int(dig_c.y)) == 0
	var wr_ok5: bool = g.player.inv[Defs.HULL] > hull1 and popped and mana_used and mid_gone
	wr_rows.append("%ssalvage: dug %d hull plating from its keel (the middle first %s), \"+n Hull Plating\" popped up %s, mana spent %s (%.1f -> %.1f)" % ["" if wr_ok5 else "(!) ", g.player.inv[Defs.HULL] - hull1, mid_gone, popped, mana_used, mana_d0, mana_min])
	wr_ok = wr_ok and wr_ok5
	# ---- the Wisp Forge out here (C): it comes to you anywhere (27 Nov: "maybe we should be able to craft in space")
	var fg_rec: Dictionary = g.recipe_by_id("plank")
	for fg_c in fg_rec.get("cost", {}):
		g.player.inv[int(fg_c)] += int(fg_rec["cost"][fg_c])
	g.toggle_forge()
	await _frames(12)
	var fg_open: bool = g.state == "forge"
	var fg_made: bool = not fg_rec.is_empty() and g.craft(fg_rec)
	if g.state == "forge":
		g.toggle_forge()
	await _frames(6)
	var wr_ok5f: bool = fg_open and fg_made and g.state == "play"
	wr_rows.append("%sthe Wisp Forge out in space: opened %s, forged planks %s, closed %s" % ["" if wr_ok5f else "(!) ", fg_open, fg_made, g.state == "play"])
	wr_ok = wr_ok and wr_ok5f
	# ---- Mending out in the open (user, 23 Nov: "Healing spell didn't work in space"): chosen, a click heals
	# (it doesn't push the jet), and the healing comes in out here
	var md_known: bool = g.player.known.has("mend")
	if not md_known:
		g.player.known.append("mend")
	var md_sel0: int = g.player.sel
	g.player.sel = g.player.known.find("mend")
	g.test_god = false
	g.player.hp = g.player.max_hp - 40.0
	g.player.heal_left = 0.0
	g.player.mana = g.player.max_mana
	g.player.spell_cd.clear()
	g.player.cast_cd = 0
	var md_hp0: float = g.player.hp
	g.space.vel = wk.vel
	g.test_cast = true
	g.test_aim = g.player.pos + Vector2(200, 0)
	var md_jet := false
	for md_f in 3:
		await _frames(1)
		md_jet = md_jet or g.space.jetting
	g.test_cast = false
	await _frames(90)
	var md_hp1: float = g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	g.player.sel = md_sel0
	if not md_known:
		g.player.known.erase("mend")
	var wr_ok5b: bool = md_hp1 > md_hp0 + 20.0 and not md_jet
	wr_rows.append("%sMending cast out in the open: health %.0f -> %.0f, the jet pushed %s" % ["" if wr_ok5b else "(!) ", md_hp0, md_hp1, md_jet])
	wr_ok = wr_ok and wr_ok5b
	# ---- back aboard: F by your ship over the breach; out by its shell where you were, the wreck you boarded kept
	var halls_open := 0
	for c6 in wk.caches:
		if c6["open"]:
			halls_open += 1
	g.player.pos = sk.pos + (sk.pos - wk.pos).normalized() * 4.0
	g.space.vel = Vector2.ZERO
	await _frames(2)
	var by_it: bool = g.space.by_ship(g.player)
	g._interact()
	await _frames(6)
	var kept_d: Dictionary = g.space.wreck_halls.get(str(shell.seed_), {})
	var kept_w = W.from_save(kept_d) if not kept_d.is_empty() else null
	var kept_open := -1
	if kept_w != null:
		kept_open = 0
		for c7 in kept_w.caches:
			if c7["open"]:
				kept_open += 1
	var wr_okc: bool = by_it and g.space.inst == null and g.player.aboard == sk and sk.pos.distance_to(ship_at) < 1.0 and g.space.rocks.has(shell) and kept_open == halls_open and halls_open > 0
	wr_rows.append("%sF by your ship back aboard %s, out by its shell %s; what you opened kept (%d of %d)" % ["" if wr_okc else "(!) ", by_it, g.space.rocks.has(shell), kept_open, halls_open])
	wr_ok = wr_ok and wr_okc
	wk = shell
	# ---- the Wisp Shield: forged from the emitter, it takes a strike, then charges
	var sh_rec: Dictionary = {}
	var cn_rec: Dictionary = {}
	for r in g.recipes:
		if r["id"] == "shield":
			sh_rec = r
		if r["id"] == "cannon":
			cn_rec = r
	for k5 in sh_rec.get("cost", {}):
		g.player.inv[int(k5)] += int(sh_rec["cost"][k5])
	var sh_ok: bool = g.craft(sh_rec) and g.items.has("shield") and not g.items.has("part_shield")
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	await _frames(4)
	g.test_god = false
	g.space.shield = 1.0
	var hp0: float = g.hp
	g.space._strike(sk.pos, (sk.pos - g.space.centre).normalized(), 0.5, Color.WHITE)
	await _frames(2)
	var hp1: float = g.hp
	g.space._strike(sk.pos, (sk.pos - g.space.centre).normalized(), 0.5, Color.WHITE)
	await _frames(2)
	var hp2: float = g.hp
	g.test_god = true
	g.hp = g.max_hp
	var wr_ok6: bool = sh_ok and hp1 >= hp0 and hp2 < hp1 and g.space.stats["shield_saves"] >= 1
	wr_rows.append("%sthe Wisp Shield forged %s: a strike %.0f -> %.0f (taken by the shield), the next %.0f -> %.0f" % ["" if wr_ok6 else "(!) ", sh_ok, hp0, hp1, hp1, hp2])
	wr_ok = wr_ok and wr_ok6
	# ---- the Wisp Cannon: a Cannon Coil (from a second wreck, here given), forged, fired at the wreck
	g.items["part_cannon"] = 1
	for k6 in cn_rec.get("cost", {}):
		g.player.inv[int(k6)] += int(cn_rec["cost"][k6])
	var cn_ok: bool = g.craft(cn_rec) and g.items.has("cannon")
	var cells0: int = wk.count()
	var shots0: int = g.space.stats["shots"]
	var hits0: int = g.space.stats["shot_hits"]
	sk.pos = wk.pos + side_dir * (wk.reach() + 60.0)
	sk.vel = wk.vel
	var sk_p0: Vector2 = sk.pos
	g.test_cast = true
	for k7 in 70:
		g.test_aim = wk.pos
		sk.vel = wk.vel
		await _frames(1)
		if k7 == 24:
			_shot("wreck_cannon.png")
	g.test_cast = false
	await _frames(20)
	var cells1: int = wk.count()
	var wr_ok7: bool = cn_ok and g.space.stats["shots"] - shots0 >= 3 and g.space.stats["shot_hits"] - hits0 >= 2 and cells1 < cells0 and sk.pos.distance_to(sk_p0) < 60.0
	wr_rows.append("%sthe Wisp Cannon forged %s: %d shots, %d hits, the hull %d -> %d cells, the skiff held its place (moved %.0f: the cast button fires, it doesn't steer)" % ["" if wr_ok7 else "(!) ", cn_ok, g.space.stats["shots"] - shots0, g.space.stats["shot_hits"] - hits0, cells0, cells1, sk.pos.distance_to(sk_p0)])
	wr_ok = wr_ok and wr_ok7
	# ---- kept as you left it: its sector goes and comes back
	var wkey: String = wk.sect
	var ws: Vector2i = g.space._loaded[wkey]
	var opened_n := 0
	for c4 in wk.caches:
		if c4["open"]:
			opened_n += 1
	g.space._unload_sector(wkey)
	var js = JSON.parse_string(JSON.stringify(g.space.save_state()))
	g.space.load_state(js)
	g.space._load_sector(ws, wkey)
	var wk2 = null
	for k8 in 120:
		await _frames(1)
		for a3 in g.space.rocks:
			if a3.kind == "wreck" and a3.sect == wkey:
				wk2 = a3
		if wk2 != null:
			break
	var opened2 := -1
	if wk2 != null:
		opened2 = 0
		for c5 in wk2.caches:
			if c5["open"]:
				opened2 += 1
	var wr_ok8: bool = wk2 != null and opened2 == opened_n and wk2.count() == cells1 and (g.space.wreck_halls as Dictionary).has(str(shell.seed_))
	wr_rows.append("%skept as you left it: its sector unloaded and saved, back with %d of %d caches open, %d cells (was %d)" % ["" if wr_ok8 else "(!) ", opened2, opened_n, wk2.count() if wk2 != null else -1, cells1])
	wr_ok = wr_ok and wr_ok8
	# ---- the map marks it
	g.open_map()
	g.map_view.gz = 60.0
	g.map_view.centre_on_you()
	await _frames(10)
	_shot("wreck_map.png")
	g.close_map()
	await _frames(4)
	# home again, and down
	g.items.erase("cannon")
	g.items.erase("shield")
	sk.pos = g.space.home_at() + (wl - g.space.home_at()).normalized() * (Defs.R_SPACE + 150.0)
	sk.vel = -(sk.pos - g.space.home_at()).normalized() * 6.0
	g.test_cast = true
	for k9 in 600:
		g.test_aim = g.space.home_at() + (sk.pos - g.space.home_at()) * 0.3
		await _frames(1)
		if not g.space.active:
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	for k10 in 1200:
		await _frames(1)
		if sk.grounded and sk.vel.length() < 0.5:
			break
	g.test_down = false
	await _frames(20)
	if g.player.aboard != null:
		g._skiff_interact(g.player)          # (out of the skiff, as the checks after this expect)
		await _frames(10)
	print("[wrecks] " + "\n[wrecks] ".join(wr_rows))
	_ok("derelict wrecks in deep space: found, boarded by F (an instance), looted, salvaged, left and kept; the skiff's shield and cannon", wr_ok, "; ".join(wr_rows))

## Pirates and the skiff's hull (pirate.gd, space.gd, skiff.gd; user, 23 Nov): ships grown from parts
## (each with guns and a strongbox you can drift up to); out in space a cutter comes for the skiff, works
## round it and fires, its bolts carve the hull (the HUD's hull bar, the riders shaken); the Wisp Cannon
## answers until it strikes its colours and becomes a wreck with a strongbox to loot; held R knits the
## hull back from Hull Plating; the shield takes a bolt; ramming rock at speed holes it; and falling out
## there brings you home with the skiff called down beside you. Pictures: pirate_ships.png (a grown
## cutter and brig), pirate_attack.png, pirate_beaten.png, skiff_damaged.png, skiff_mended.png.
func _test_pirates() -> void:
	var pi_rows := []
	var pi_ok := true
	var P = load("res://scripts/pirate.gd")
	# ---- grown from parts
	var pi_n := 0
	var pi_box := 0
	var pi_reach := 0
	var pi_guns := 0
	var pi_sizes := []
	for q in 10:
		var c: String = "brig" if q >= 6 else "cutter"
		var pq = P.make_pirate(9001 + q * 271, c)
		pi_n += 1
		pi_sizes.append("%s %dx%d" % [c[0], pq.w, pq.h])
		if pq.guns.size() == (2 if c == "brig" else 1):
			pi_guns += 1
		if pq.caches.size() == 1:
			pi_box += 1
			if _cache_reached(pq, pq.caches[0], _wreck_reach(pq, 8.0)):
				pi_reach += 1
			else:
				print("[pirates] seed %d (%s): its strongbox can't be reached %s" % [9001 + q * 271, c, str(pq.caches[0])])
		else:
			print("[pirates] seed %d (%s): %d strongboxes %s" % [9001 + q * 271, c, pq.caches.size(), str(pq.meta)])
	var pi_ok1: bool = pi_box == pi_n and pi_reach == pi_n and pi_guns == pi_n
	pi_rows.append("%s%d ships grown (%s): a strongbox on %d (reached by drifting in on %d), their guns on %d" % ["" if pi_ok1 else "(!) ", pi_n, ", ".join(pi_sizes), pi_box, pi_reach, pi_guns])
	pi_ok = pi_ok and pi_ok1
	# ---- up into space in the skiff
	g.player.dead = false
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var pi_up: Vector2 = sk.pos.normalized()
	sk.pos = pi_up * (Defs.R_SPACE - 11.0)
	sk.vel = pi_up * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	g.test_cast = false
	# ---- zooming out by hand (user, 23 Nov: "a zoom in and out feature in space. Not auto zoom"): over the
	# planet, which is still drawn from its cells
	var pi_z0: float = g.zoom
	g.space.zoom_by(4)
	for kz in 40:
		sk.vel = Vector2.ZERO
		await _frames(1)
	var pi_zp: float = g.zoom
	var pi_live: bool = g.space.live
	_shot("space_zoom_planet.png")
	g.space.zoom_by(-10)
	for kz2 in 40:
		sk.vel = Vector2.ZERO
		await _frames(1)
	var pi_zb: float = g.zoom
	var pi_okz: bool = absf(pi_z0 - 1.0) < 0.01 and absf(pi_zp - 4.0) < 0.05 and absf(pi_zb - 1.0) < 0.05
	pi_rows.append("%sthe view zooms by hand out there: %.1f -> %.2f (the planet still live %s) -> back to %.2f" % ["" if pi_okz else "(!) ", pi_z0, pi_zp, pi_live, pi_zb])
	pi_ok = pi_ok and pi_okz
	# well out from home, where nothing else is
	var pi_at: Vector2 = g.space.home_at() + pi_up * (Defs.R_SPACE + 5200.0)
	sk.pos = pi_at
	sk.vel = Vector2.ZERO
	await _frames(30)
	# (two ships side by side, for their picture)
	var pc = P.make_pirate(9001, "cutter")
	var pb = P.make_pirate(9001 + 6 * 271, "brig")
	var pi_r: Vector2 = Vector2(pi_up.y, -pi_up.x)
	for pp in [pc, pb]:
		pp.sect = "pirate"
		pp.ang = pi_r.angle()
		pp.hp = pp.hp_max - 1.0                 # (shown with their hull bars)
		g.space.rocks.append(pp)
	pc.pos = pi_at + pi_r * 90.0 + pi_up * 60.0
	pb.pos = pi_at - pi_r * 110.0 + pi_up * 70.0
	for k1 in 6:
		for pp2 in [pc, pb]:
			pp2.ang = pi_r.angle()
			pp2.facing = 1
		pc.vel = Vector2.ZERO
		pb.vel = Vector2.ZERO
		pc.fire_t = 999
		pb.fire_t = 999
		pc.pos = pi_at + pi_r * 90.0 + pi_up * 60.0
		pb.pos = pi_at - pi_r * 110.0 + pi_up * 70.0
		sk.pos = pi_at
		sk.vel = Vector2.ZERO
		await _frames(1)
	_shot("pirate_ships.png")
	g.space.zoom_by(3)
	for kz3 in 40:
		pc.pos = pi_at + pi_r * 90.0 + pi_up * 60.0
		pb.pos = pi_at - pi_r * 110.0 + pi_up * 70.0
		pc.vel = Vector2.ZERO
		pb.vel = Vector2.ZERO
		sk.pos = pi_at
		sk.vel = Vector2.ZERO
		await _frames(1)
	_shot("space_zoom.png")
	g.space.zoom_by(-10)
	await _frames(40)
	g.space._drop_pirates()
	# ---- a cutter comes for you: it closes, works round you and fires; its bolts hole the hull
	var had_shield: bool = g.items.has("shield")
	g.items.erase("shield")
	g.items.erase("cannon")
	var st0: Dictionary = g.space.stats.duplicate()
	var hull0: float = sk.hull_f
	var made: Array = g.space.spawn_pirates(sk.pos, pi_r, "cutter")
	var pr = made[0] if not made.is_empty() else null
	var pi_close := 1e9
	var pi_hull_t := -1
	var pi_hud := false
	for k2 in 700:
		sk.pos = pi_at
		sk.vel = Vector2.ZERO
		await _frames(1)
		if pr != null:
			pi_close = minf(pi_close, pr.pos.distance_to(sk.pos))
		if pi_hull_t < 0 and sk.hull_f < hull0:
			pi_hull_t = k2
		if k2 == 420:
			_shot("pirate_attack.png")
			pi_hud = g.ui.hull_row.visible
	var pi_fired: int = int(g.space.stats["pirate_shots"]) - int(st0["pirate_shots"])
	var pi_hits: int = int(g.space.stats["pirate_hits"]) - int(st0["pirate_hits"])
	var hull1: float = sk.hull_f
	var pi_ok2: bool = pr != null and pi_close < 400.0 and pi_fired >= 4 and pi_hits >= 1 and hull1 < hull0 and pi_hud
	pi_rows.append("%sa cutter (%s) came out of the dark %s, closed to %.0f, fired %d bolts, %d struck: the hull %.0f%% -> %.0f%% (first holed at tick %d, engine %.0f%%), the HUD's hull bar %s" % ["" if pi_ok2 else "(!) ", pr.wname if pr != null else "none", pr != null, pi_close, pi_fired, pi_hits, hull0 * 100.0, hull1 * 100.0, pi_hull_t, sk.engine_f * 100.0, pi_hud])
	pi_ok = pi_ok and pi_ok2
	_shot("skiff_damaged.png")
	# ---- the cannon answers until it strikes its colours
	g.items["cannon"] = true
	var pi_beaten := false
	var pi_fight := -1
	var pi_hp0: float = pr.hp if pr != null else 0.0
	if pr != null:
		g.test_cast = true
		for k3 in 1500:
			sk.pos = pi_at
			sk.vel = Vector2.ZERO
			g.player.mana = g.player.max_mana
			var dd: float = pr.pos.distance_to(sk.pos)
			g.test_aim = pr.pos + (pr.vel - sk.vel) * (dd / 9.0)
			await _frames(1)
			if pr.kind != "pirate":
				pi_beaten = true
				pi_fight = k3
				break
		g.test_cast = false
	await _frames(30)
	var pi_scrap := 0
	if pr != null:
		for a in g.space.rocks:
			if a.kind == "scrap" and a.sect == pr.sect and a.pos.distance_to(pr.pos) < 400.0:
				pi_scrap += 1
	_shot("pirate_beaten.png")
	var pi_kept: bool = pr != null and pr.sect != "pirate" and g.space._loaded.has(pr.sect)
	var pi_ok3: bool = pi_beaten and pr.kind == "wreck" and pr.caches.size() == 1 and pi_scrap >= 2 and pi_kept and g.space.pirate_count() == 0
	pi_rows.append("%sthe Wisp Cannon answered: %s beaten %s after %d ticks (%d shots, %d hits, hp %.0f -> %.0f), a wreck now %s with %d scrap round it, kept with its sector %s" % ["" if pi_ok3 else "(!) ", pr.wname if pr != null else "-", pi_beaten, pi_fight,
		int(g.space.stats["shots"]) - int(st0["shots"]), int(g.space.stats["shot_hits"]) - int(st0["shot_hits"]), pi_hp0, pr.hp if pr != null else 0.0, pr.kind if pr != null else "-", pi_scrap, pi_kept])
	pi_ok = pi_ok and pi_ok3
	# ---- its strongbox
	var pi_loot := false
	var coins0 := int(g.items.get("coins", 0))
	if pi_beaten and pr.caches.size() == 1:
		pr.vel = Vector2.ZERO
		pr.omega = 0.0
		g._skiff_interact(g.player)
		await _frames(4)
		g.player.pos = _over_cache(pr, pr.caches[0])
		g.space.vel = pr.vel
		await _frames(10)
		g._interact()
		await _frames(10)
		pi_loot = pr.caches[0]["open"] and int(g.items.get("coins", 0)) > coins0
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
		await _frames(4)
	var pi_ok4: bool = pi_loot and g.player.aboard == sk
	pi_rows.append("%sits strongbox opened %s (coins %d -> %d), back aboard %s" % ["" if pi_ok4 else "(!) ", pi_loot, coins0, int(g.items.get("coins", 0)), g.player.aboard == sk])
	pi_ok = pi_ok and pi_ok4
	# ---- mending: hold R aboard, Hull Plating knits it back
	var miss0: int = sk.missing()
	g.player.inv[Defs.HULL] += 80
	var hp_pl0: int = g.player.inv[Defs.HULL]
	var mend0: int = g.stats_mended
	g.test_mend = true
	for k4 in 900:
		sk.vel = Vector2.ZERO
		await _frames(1)
		if sk.missing() == 0:
			break
	g.test_mend = false
	var pi_ok5: bool = miss0 > 0 and sk.missing() == 0 and sk.hull_f > 0.999 and g.player.inv[Defs.HULL] < hp_pl0 and g.stats_mended - mend0 >= miss0
	pi_rows.append("%smended: %d cells missing -> %d (hull %.0f%%), %d Hull Plating used" % ["" if pi_ok5 else "(!) ", miss0, sk.missing(), sk.hull_f * 100.0, hp_pl0 - g.player.inv[Defs.HULL]])
	pi_ok = pi_ok and pi_ok5
	await _frames(4)
	_shot("skiff_mended.png")
	# ---- the shield takes a bolt
	g.items["shield"] = true
	g.space.shield = 1.0
	var sv0: int = int(g.space.stats["shield_saves"])
	sk.pos = pi_at                    # (where it's held while the bolt flies: aimed at anywhere else it can miss)
	sk.vel = Vector2.ZERO
	var fr: Vector2 = sk.pos + pi_r * (float(sk.w) * 0.5 + 14.0)     # (close by: drifting debris can't take it)
	g.space.foe_shots.append([fr, (sk.pos - fr).normalized() * 7.0, 60, null])
	for k5 in 40:
		sk.pos = pi_at
		sk.vel = Vector2.ZERO
		await _frames(1)
	var pi_ok6: bool = int(g.space.stats["shield_saves"]) > sv0 and sk.missing() == 0
	pi_rows.append("%sthe Wisp Shield took a pirate's bolt %s (the hull still whole %s)" % ["" if pi_ok6 else "(!) ", int(g.space.stats["shield_saves"]) > sv0, sk.missing() == 0])
	pi_ok = pi_ok and pi_ok6
	g.items.erase("shield")
	# ---- ramming rock at speed holes it
	var A = load("res://scripts/asteroid.gd")
	var rock = A.make(4242, 24.0, "stony")
	rock.pos = pi_at + pi_r * 160.0
	rock.vel = Vector2.ZERO
	rock.omega = 0.0
	rock.sect = "pirate"
	g.space.rocks.append(rock)
	var cr0: int = int(g.space.stats["crashes"])
	var miss1: int = sk.missing()
	for k6 in 60:
		await _frames(1)
		if k6 < 30:
			sk.vel = pi_r * 14.0
		if int(g.space.stats["crashes"]) > cr0:
			break
	var pi_ok7: bool = int(g.space.stats["crashes"]) > cr0 and sk.missing() > miss1
	pi_rows.append("%sramming rock at 14 a tick: a crash %s, %d cells holed" % ["" if pi_ok7 else "(!) ", int(g.space.stats["crashes"]) > cr0, sk.missing() - miss1])
	pi_ok = pi_ok and pi_ok7
	sk.vel = Vector2.ZERO
	g.space._drop_pirates()
	sk.mend(100000)
	# ---- falling out there: home, the skiff called down beside you
	var inv0: PackedInt32Array = g.player.inv.duplicate()
	g.test_god = false
	g.space.allow_pirates = false
	g.hurt(g.player, 10000.0, Vector2.ZERO, false)
	await _frames(90)
	var pi_dead: bool = g.dead
	g.revive()
	await _frames(60)
	g.player.inv = inv0
	var pi_r2: float = g.player.pos.length()
	var pi_ok8: bool = pi_dead and not g.space.active and g.state == "play" and pi_r2 < Defs.R_TOP and g.player.aboard == null and g.skiff != null and g.skiff.pos.distance_to(g.player.pos) < 150.0 and g.space.at_home()
	pi_rows.append("%sfallen out there %s: back on the planet %s (radius %.0f, the top of the air %.0f), the skiff beside you %s (%.0f away)" % ["" if pi_ok8 else "(!) ", pi_dead, not g.space.active and g.state == "play", pi_r2, Defs.R_TOP, g.skiff != null and g.skiff.pos.distance_to(g.player.pos) < 150.0, g.skiff.pos.distance_to(g.player.pos) if g.skiff != null else -1.0])
	pi_ok = pi_ok and pi_ok8
	g.test_god = true
	if had_shield:
		g.items["shield"] = true
	g.items.erase("cannon")
	print("[pirates] " + "\n[pirates] ".join(pi_rows))
	_ok("pirates: ships grown from parts hunt the skiff and hole its hull; the cannon beats them into wrecks to loot; the hull is mended", pi_ok, "; ".join(pi_rows))

## Trading outposts (outpost.gd, galaxy.gd, space.gd; user, 23 Nov): every system's outpost where it
## should be (clear of planets and the first wreck), grown as a great station of rooms (a hangar the skiff fits
## in, the four shops along one deck of doorways, spacers; user, 25 Nov: docked by a button into an instance, its
## halls grown bigger, the shell out in space sealed); out there it streams in, F docks as you fly by, you stand in
## its hangar beside your ship and walk to the market: a bounty for pirates beaten, salvage
## sold; the shipwright mends the hull and sells a part, the cartographer charts; the cantina's job board (a
## courier run carried and paid, a salvage job); the spacers walk and talk; no spells in its halls; pirates that
## come near are driven off by its guns; the map shows it. Pictures: outpost_layout_0/1.png, outpost.png,
## outpost_hangar.png, outpost_trader.png, outpost_shop.png, outpost_jobs.png, outpost_folk.png, outpost_map.png.
func _test_outposts() -> void:
	var op_rows := []
	var op_ok := true
	var G = load("res://scripts/galaxy.gd")
	var O = load("res://scripts/outpost.gd")
	# ---- where: OUTPOST_D from the first planet, clear of every planet and the first wreck
	var og: PackedFloat64Array = G.system_outpost(0)
	var hg: PackedFloat64Array = Defs.planet_g(0)
	var fw: PackedFloat64Array = G.first_wreck()
	var od: float = Defs.g_rel(og, hg).length()
	var ofw: float = Defs.g_rel(og, fw).length()
	var oclear: bool = not G._near_planet_r(og[0], og[1], G.NEAR_PLANET + 6000.0)
	var osect := false
	for c in G.sector_content(G.sector_of(og[0], og[1])):
		if c["type"] == "outpost":
			osect = true
	var op_ok1: bool = od > 24000.0 and od < 30000.0 and oclear and ofw > 12000.0 and osect
	op_rows.append("%s%s: %.0fk from home, %.0fk from the first wreck, clear of the planets %s, in its sector's content %s" % ["" if op_ok1 else "(!) ", G.outpost_name(0), od / 1000.0, ofw / 1000.0, oclear, osect])
	op_ok = op_ok and op_ok1
	# ---- grown: a big station of rooms; the hangar holds the skiff; the four shops along the lowest deck, one
	# run of doorways from the hangar (no hatch to climb); folk to live there
	var op_fit := 0
	var op_deck := 0
	var op_big := 0
	var op_folk := 0
	var sealed := 0
	var op_ms := []
	var oq0 = null
	# (27 Nov: the halls are a level now, four or five times the cells: three grown, not six)
	for q in 3:
		var shell = O.make_outpost(5003 + q * 977, q)
		var shr: Rect2i = shell.hangar_rect()
		var mx: int = shr.position.x - 2 if shell.hangar_side < 0 else shr.end.x + 1
		var pane := 0
		for mxi in range(mx - 3, mx + 4):
			for mj in range(shr.end.y - 60, shr.end.y - 10):
				if mxi >= 0 and mxi < shell.w and shell.cells[mj * shell.w + mxi] == Defs.GLASS:
					pane += 1
		if pane >= 30 and shell.folk_plan.is_empty():
			sealed += 1
		var oq = O.make_outpost(5003 + q * 977, q, true)
		op_ms.append(int(oq.meta.get("ms", -1)))
		if q == 0:
			oq0 = oq
		var hr: Rect2i = oq.hangar_rect()
		var free := true
		for j in range(hr.end.y - 47, hr.end.y):
			for i in range(66):
				var ii: int = hr.position.x + 4 + i if oq.hangar_side < 0 else hr.end.x - 5 - i
				if oq.cells[j * oq.w + ii] != 0:
					free = false
		if free:
			op_fit += 1
		var deck: Array = oq.meta["deck"]
		var chain: bool = (oq.mods[oq.hangar]["links"] as Array).has(deck[0])
		for d in range(deck.size() - 1):
			chain = chain and (oq.mods[deck[d]]["links"] as Array).has(deck[d + 1])
		var shops := {}
		for kp in oq.keepers:
			shops[kp.shop] = deck.has(kp.room)
		var shops_ok: bool = shops.size() == 4 and not shops.values().has(false) and String(oq.mods[deck[0]]["role"]) == "market"
		if chain and shops_ok:
			op_deck += 1
		if oq.mods.size() >= 24 and oq.w > 900 and oq.rows == 4:
			op_big += 1
		if oq.folk_plan.size() >= 13:
			op_folk += 1
		if q < 2:
			_station_picture(oq, "outpost_layout_%d.png" % q)
	var op_ok2: bool = op_fit == 3 and op_deck == 3 and op_big == 3 and op_folk == 3 and sealed == 3
	op_rows.append("%s3 outposts' halls grown as levels (%d rooms and corridors, %d doors, %dx%d the first; grown in %s ms): 24+ on 4 decks %d; the hangar holds the skiff in %d; the market by the hangar and the shipwright, cantina and cartographer along the lowest deck in %d; 13+ spacers in %d; the shell out in space sealed, nobody in it, %d" % ["" if op_ok2 else "(!) ", oq0.mods.size(), oq0.doors.size(), oq0.w, oq0.h, str(op_ms), op_big, op_fit, op_deck, op_folk, sealed])
	op_ok = op_ok and op_ok2
	# ---- up into space in the skiff, out to the outpost
	g.player.dead = false
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var op_up: Vector2 = sk.pos.normalized()
	sk.pos = op_up * (Defs.R_SPACE - 11.0)
	sk.vel = op_up * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	g.test_cast = false
	var ol: Vector2 = g.space.local_of(og)
	sk.pos = ol + Vector2(-1400.0, 0.0)
	sk.vel = Vector2.ZERO
	var op = null
	for k1 in 400:
		sk.vel = Vector2.ZERO
		await _frames(1)
		op = g.space.nearest_outpost(sk.pos, 5000.0)
		if op != null:
			break
	if op == null:
		_ok("trading outposts: found, docked at, traded with", false, "; ".join(op_rows) + "; (!) no outpost came in with its sector")
		return
	# beside it: F docks (its halls grown in a worker), and you stand in its hangar beside your ship
	var hr0: Rect2i = op.hangar_rect()
	var side: float = float(op.hangar_side)
	var mouth_x: float = float(hr0.position.x) - 70.0 if side < 0.0 else float(hr0.end.x) + 70.0
	var mouth: Vector2 = op.to_world(Vector2(mouth_x, float(hr0.end.y) - 30.0) - op.com)
	sk.pos = mouth
	sk.vel = Vector2.ZERO
	sk.ang = op.axis_x().angle()
	g.space.zoom_i = 3
	await _frames(70)
	_shot("outpost.png")
	g.space.zoom_i = 0
	await _frames(30)
	var pk = g.pocket
	var ship_at: Vector2 = sk.pos
	var can_dock: bool = g.space.dock_target(g.player) == op
	var bumps0: int = int(g.space.stats["crashes"])
	g._interact()
	var dock_t := -1
	for kd in 300:
		await _frames(1)
		if pk.active and pk.place == "outpost":
			dock_t = kd
			break
	if not pk.active:
		pk.dock_now(g.player, op)          # (so the checks below still run, and this one fails)
	var io = pk.op
	await _frames(40)
	_shot("outpost_hangar.png")
	var op_ok3: bool = can_dock and dock_t >= 0 and io != null and io.halls and io.wname == op.wname and g.player.aboard == null and g.player.on_ground and int(g.space.stats["crashes"]) == bumps0
	op_rows.append("%s%s came in with its sector; F docked %s (in %d ticks), in its halls %s, standing in its hangar %s" % ["" if op_ok3 else "(!) ", op.wname, can_dock, dock_t, io != null and io.halls, g.player.on_ground])
	op_ok = op_ok and op_ok3
	# ---- on foot through the hangar's door to the market
	var mk = io.keeper("market")
	var walked := -1
	for k3 in 1500:
		g.test_move = 1 if mk.b.x > pk.b.x else -1
		await _frames(1)
		if pk.near_keeper == mk:
			walked = k3
			break
	g.test_move = 0
	await _frames(10)
	_shot("outpost_trader.png")
	var op_ok3b: bool = walked >= 0
	op_rows.append("%swalked through its door to the market's counter in %d ticks" % ["" if op_ok3b else "(!) ", walked])
	op_ok = op_ok and op_ok3b
	# ---- no spells in its halls
	var sb0: int = g.space.sbolts.size()
	var mana0: float = g.player.mana
	g.test_aim = g.player.pos + Vector2(40.0, 0.0)
	g.test_cast = true
	await _frames(6)
	g.test_cast = false
	await _frames(4)
	var no_spell: bool = g.space.sbolts.size() == sb0 and g.player.mana >= mana0 - 0.01
	# ---- the market: a bounty, then its shop; salvage sold
	var tr = mk
	g.items["bounty_paid"] = int(g.items.get("pirates_beaten", 0))
	g.items["pirates_beaten"] = int(g.items.get("pirates_beaten", 0)) + 2
	var coins0 := int(g.items.get("coins", 0))
	g._interact()
	await _frames(10)
	var op_shop: bool = g.state == "shop" and g.towns.shop_of == tr
	var coins1 := int(g.items.get("coins", 0))
	_shot("outpost_shop.png")
	g.player.inv[Defs.HULL] += 20
	var hull0: int = g.player.inv[Defs.HULL]
	var op_sold: bool = g.towns.sell(tr, Defs.HULL) and g.player.inv[Defs.HULL] == hull0 - 10 and int(g.items.get("coins", 0)) == coins1 + 12
	g.towns.close_shop()
	await _frames(5)
	var op_ok4: bool = op_shop and coins1 - coins0 == 70 and op_sold and no_spell
	op_rows.append("%s%s's market %s: a bounty of %d coins for 2 pirates; sold 10 Hull Plating %s; no spells in its halls %s" % ["" if op_ok4 else "(!) ", tr.name, op_shop, coins1 - coins0, op_sold, no_spell])
	op_ok = op_ok and op_ok4
	# ---- along the deck: the shipwright mends the hull at the dock and sells a part; the cartographer charts
	var go_to := func(kp) -> void:
		pk.b = kp.b + Vector2(float(kp.facing) * 10.0, -9.6)
		pk.v = Vector2.ZERO
		g.player.pos = io.to_world(pk.b)
	g.items["coins"] = int(g.items.get("coins", 0)) + 1200
	var sw = io.keeper("shipwright")
	go_to.call(sw)
	await _frames(20)
	var at_sw: bool = pk.near_keeper == sw
	sk.carve(sk.cell_world(6, sk.h - 4), 4.0)
	var miss0: int = sk.missing()
	var sd: Dictionary = g.towns.shop_def(sw)
	var i_rep := -1
	var i_part := -1
	for i3 in (sd["sell"] as Array).size():
		var it: Dictionary = sd["sell"][i3]
		if it.has("repair"):
			i_rep = i3
		if it.has("part") and i_part < 0 and not g.towns.owned(it):
			i_part = i3
	var op_mended: bool = i_rep >= 0 and miss0 > 0 and g.towns.buy(sw, i_rep) and sk.missing() == 0
	var op_part: bool = i_part < 0 or (g.towns.buy(sw, i_part) and g.towns.owned(sd["sell"][i_part]))
	var ct = io.keeper("charts")
	go_to.call(ct)
	await _frames(20)
	var at_ct: bool = pk.near_keeper == ct
	var sd2: Dictionary = g.towns.shop_def(ct)
	var i_chart := -1
	for i4 in (sd2["sell"] as Array).size():
		if (sd2["sell"][i4] as Dictionary).has("star_chart") and i_chart < 0:
			i_chart = i4
	var ch0: int = g.space.charted.size()
	var op_charts: bool = i_chart >= 0 and g.towns.buy(ct, i_chart) and g.space.charted.size() >= ch0 + 1
	var op_ok5: bool = at_sw and op_mended and op_part and at_ct and op_charts
	op_rows.append("%sat the shipwright's %s: the hull mended at the dock %s (%d cells were missing), a ship's part %s; at the cartographer's %s: star charts %s (%d -> %d systems)" % ["" if op_ok5 else "(!) ", at_sw, op_mended, miss0, op_part, at_ct, op_charts, ch0, g.space.charted.size()])
	op_ok = op_ok and op_ok5
	# ---- the cantina's job board: a courier run taken (its sealed crates into the hold), carried to the other
	# outpost and paid; a salvage job taken and done here
	var cn = io.keeper("cantina")
	go_to.call(cn)
	await _frames(20)
	var at_cn: bool = pk.near_keeper == cn
	var cargo_keep = g.items.get("cargo", {})
	var jobs_keep = g.items.get("jobs", [])
	var done_keep := int(g.items.get("jobs_done", 0))
	g.items["cargo"] = {}
	g.items["jobs"] = []
	var courier := {}
	var salvage := {}
	for jn in 30:
		g.items["jobs_done"] = jn
		for jb in g.space.job_offers(op.seed_, op.wname, op.sys):
			if jb["kind"] == "courier" and courier.is_empty() and int(jb["n"]) <= g.hold_cap():
				courier = jb
			if jb["kind"] == "salvage" and salvage.is_empty():
				salvage = jb
	g.items["jobs_done"] = 0
	g._interact()
	await _frames(10)
	var board_open: bool = g.state == "shop" and g.towns.shop_of == cn
	var n_jobs := 0
	for it2 in g.towns.shop_def(cn)["sell"]:
		if (it2 as Dictionary).has("job"):
			n_jobs += 1
	_shot("outpost_jobs.png")
	g.towns.close_shop()
	await _frames(5)
	var c_took: bool = not courier.is_empty() and g.space.take_job(courier)
	var sealed0 := int((g.items.get("cargo", {}) as Dictionary).get("sealed", 0))
	var hud_txt: String = g.space.job_short(courier) if c_took else ""
	var coins2 := int(g.items.get("coins", 0))
	var dest = O.make_outpost(int(courier.get("to", 0)), -1)
	g.space._settle_jobs(dest)
	var c_paid: bool = c_took and int(g.items.get("coins", 0)) - coins2 == int(courier.get("pay", -1)) and not (g.items.get("cargo", {}) as Dictionary).has("sealed")
	var s_ok := false
	if not salvage.is_empty() and g.space.take_job(salvage):
		g.player.inv[int(salvage["mat"])] += int(salvage["n"])
		var coins3 := int(g.items.get("coins", 0))
		g.space._settle_jobs(io)
		s_ok = int(g.items.get("coins", 0)) - coins3 == int(salvage["pay"]) and g.space.jobs().is_empty()
	var op_ok6j: bool = at_cn and board_open and n_jobs == 3 and c_took and sealed0 == int(courier.get("n", -1)) and c_paid and s_ok and hud_txt != ""
	op_rows.append("%sthe cantina's job board %s (%d jobs): a courier run taken %s (%d sealed crates into the hold; the HUD: %s), paid at %s %s (%d coins); a salvage job done %s" % ["" if op_ok6j else "(!) ", board_open, n_jobs, c_took, sealed0, hud_txt, String(courier.get("to_name", "?")), c_paid, int(courier.get("pay", 0)), s_ok])
	op_ok = op_ok and op_ok6j
	g.items["cargo"] = cargo_keep
	g.items["jobs"] = jobs_keep
	g.items["jobs_done"] = done_keep
	# ---- its spacers walk their decks and talk
	var mine: Array = pk.op_folk
	var at0 := []
	for f2 in mine:
		at0.append(f2.b)
	await _frames(360)
	var moved := 0
	var grounded := 0
	for fk in mine.size():
		if (mine[fk].b as Vector2).distance_to(at0[fk]) > 6.0:
			moved += 1
		if mine[fk].on_ground:
			grounded += 1
	var talk_ok := false
	var said := ""
	var f0 = null
	var f0_d := -1.0
	for fc in mine:
		var dmin := 1e9
		for kq in io.keepers:
			dmin = minf(dmin, (fc.b as Vector2).distance_to(kq.b - Vector2(0.0, 12.0)))
		if dmin > f0_d:
			f0_d = dmin
			f0 = fc
	if f0 != null:
		pk.b = f0.b + Vector2(8.0, 0.0)
		pk.v = Vector2.ZERO
		g.player.pos = io.to_world(pk.b)
		await _frames(2)
		g._interact()
		await _frames(5)
		talk_ok = f0.say_t > 0 and f0.say != ""
		said = f0.say
		await _frames(20)
		_shot("outpost_folk.png")
	var op_ok7: bool = mine.size() >= 13 and moved >= 4 and grounded >= mine.size() - 1 and talk_ok
	op_rows.append("%s%d spacers in its halls: %d walked about in 6 s, %d standing on a floor; talked to one %s (\"%s\"; %.0f from a counter)" % ["" if op_ok7 else "(!) ", mine.size(), moved, grounded, talk_ok, said, f0_d])
	op_ok = op_ok and op_ok7
	# ---- back to your ship: F undocks, aboard, where you were out in space
	pk.b = pk._op_ship_at() + Vector2(0.0, -12.0)
	pk.v = Vector2.ZERO
	await _frames(4)
	var by_ship: bool = pk.near == "ship"
	g._interact()
	await _frames(10)
	var undocked: bool = by_ship and not pk.active and g.space.active and g.player.aboard == sk and sk.pos.distance_to(ship_at) < 1.0 and g.space.visible
	op_rows.append("%sF at your ship undocked %s: aboard, out in space where you were %s" % ["" if undocked else "(!) ", by_ship, undocked])
	op_ok = op_ok and undocked
	# ---- pirates that come near are driven off by its guns
	var made: Array = g.space.spawn_pirates(op.pos, Vector2.RIGHT, "cutter")
	if not made.is_empty():
		made[0].pos = op.pos + Vector2(1800.0, 0.0)
	await _frames(10)
	var op_ok6: bool = not made.is_empty() and g.space.pirate_count() == 0
	op_rows.append("%sa pirate cutter come near was driven off by its guns %s" % ["" if op_ok6 else "(!) ", g.space.pirate_count() == 0])
	op_ok = op_ok and op_ok6
	# ---- the map
	g.open_map()
	g.map_view.gz = 300.0
	g.map_view.centre_on_you()
	await _frames(10)
	_shot("outpost_map.png")
	g.close_map()
	await _frames(4)
	# home again, and down
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	await _frames(4)
	sk.pos = g.space.home_at() + (ol - g.space.home_at()).normalized() * (Defs.R_SPACE + 150.0)
	sk.vel = -(sk.pos - g.space.home_at()).normalized() * 6.0
	g.test_cast = true
	for k9 in 600:
		g.test_aim = g.space.home_at() + (sk.pos - g.space.home_at()) * 0.3
		await _frames(1)
		if not g.space.active:
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	for k10 in 1200:
		await _frames(1)
		if sk.grounded and sk.vel.length() < 0.5:
			break
	g.test_down = false
	await _frames(20)
	if g.player.aboard != null:
		g._skiff_interact(g.player)
		await _frames(10)
	print("[outposts] " + "\n[outposts] ".join(op_rows))
	_ok("trading outposts: great stations of rooms, docked at by F into their halls, walked through, traded with (market, shipwright, cantina's jobs, cartographer), spacers, undocked, pirates kept off", op_ok, "; ".join(op_rows))

## (user, 23 Nov: "Derelict space stations and everything with aliens and such to fight"; "Both, by section")
## The minimap and the view in space (user, 24 Nov: the camera "spinning around on its own especially near a
## derelict"; "the map doesnt show whick way your currently facing"; "get rid of arrows on the hud and just
## use the map ... a mini map ... for planetary things as well. waypoints and such"): on the planet the side
## view, the arrow the way you face (here and on the map), a waypoint set by a click on the map, shown and
## cleared when you get there; out in space the radar, Q / E turning the view in deep space but not near a
## planet, a far station turned to match the view so coming up to it doesn't turn it, the chart's arrow,
## and a planet righting the view as you come down.
func _test_minimap() -> void:
	var rows := []
	var ok := true
	var G = load("res://scripts/galaxy.gd")
	g.player.dead = false
	g.test_god = true
	g.state = "play"
	var mm = g.ui.minimap
	await _frames(10)
	# ---- on the planet: the side view, and the arrow the way you face
	var fa := []
	for fs in [1.0, -1.0]:
		g.test_aim = g.player.pos + g.basis_r(g.view_angle()) * 60.0 * fs
		await _frames(6)
		fa.append([g.player.facing, mm.facing.x])
	g.test_aim = Vector2.ZERO
	var cols: int = int(mm.stats.get("columns", 0))
	var ok1: bool = g.ui.minimap_panel.visible and mm.mode == "planet" and cols == int(mm._size_for("planet").x) and fa[0][0] == 1 and fa[0][1] > 0.9 and fa[1][0] == -1 and fa[1][1] < -0.9
	rows.append("%son the planet: the minimap %s, a side view of %d columns; facing right %s -> its arrow %.2f, left %s -> %.2f" % ["" if ok1 else "(!) ", "shown" if g.ui.minimap_panel.visible else "hidden", cols, fa[0][0], fa[0][1], fa[1][0], fa[1][1]])
	ok = ok and ok1
	# ---- a waypoint: a click on the planet map (the ground under the click), the map's arrow, the minimap
	var p0: Vector2 = g.player.pos
	var a0 := atan2(p0.y, p0.x)
	var wa := a0 + 220.0 / Defs.RS0
	var target: Vector2 = Vector2.from_angle(wa) * (g.gpu.surf_at(wa).x + 60.0)
	g.planet_state.erase("waypoint")
	g.open_map()
	await _frames(30)
	var you_dir: Vector2 = g.map_view.you_dir
	var want_dir: Vector2 = g.world_to_screen(g.player.pos + g.facing_dir(g.player) * 200.0) - g.world_to_screen(g.player.pos)
	var sp: Vector2 = g.world_to_screen(target)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = sp * float(g.scale_px)
	g._map_mouse(ev)
	var ev2: InputEventMouseButton = ev.duplicate()
	ev2.pressed = false
	g._map_mouse(ev2)
	await _frames(20)
	_shot("map_waypoint.png")
	var wp = g.planet_waypoint()
	g.close_map()
	await _frames(30)
	var on_ground: bool = wp != null and absf((wp as Vector2).length() - g.gpu.surf_at(atan2(wp.y, wp.x)).x) < 4.0 and absf(wrapf(atan2(wp.y, wp.x) - wa, -PI, PI)) * Defs.RS0 < 30.0
	var wp_mm: int = int(mm.stats.get("waypoint", 0))
	_shot("minimap_planet.png")
	var cleared := false
	if wp != null:
		_go(wp + (wp as Vector2).normalized() * 8.0)
		for wk in 60:
			await _frames(1)
			if g.planet_waypoint() == null:
				cleared = true
				break
	var ok2: bool = you_dir.dot(want_dir.normalized()) > 0.9 and on_ground and wp_mm == 1 and cleared
	rows.append("%sthe map's arrow points the way you face %s; a click set a waypoint on the ground under it %s; on the minimap %s; cleared when you got there %s" % ["" if ok2 else "(!) ", you_dir.dot(want_dir.normalized()) > 0.9, on_ground, wp_mm == 1, cleared])
	ok = ok and ok2
	# ---- up into space in the skiff
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
	g.call_skiff()
	await _frames(60)
	var sk = g.skiff
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var up0: Vector2 = sk.pos.normalized()
	sk.pos = up0 * (Defs.R_SPACE - 11.0)
	sk.vel = up0 * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	# just out of the air: Q / E do nothing, the planet holds the view (held 600 over the band, or it drops back in)
	var hold_at: Vector2 = sk.pos.normalized() * (Defs.R_SPACE + 600.0)
	for kh in 12:
		sk.pos = hold_at
		sk.vel = Vector2.ZERO
		await _frames(1)
	var v_near: float = g.space.view_ang
	g.test_turn = 1.0
	for kh2 in 30:
		sk.pos = hold_at
		sk.vel = Vector2.ZERO
		await _frames(1)
	g.test_turn = 0.0
	var held_near: bool = absf(wrapf(g.space.view_ang - v_near, -PI, PI)) < 0.05 and g.space.near_best <= g.space.VIEW_NEAR
	# ---- out to the system's derelict: it comes in with its sector
	var sl: Vector2 = g.space.local_of(G.system_station(0))
	var st = null
	for k1 in 300:
		sk.pos = sl + Vector2(-1400.0, 0.0)
		sk.vel = Vector2.ZERO
		await _frames(1)
		for a in g.space.rocks:
			if a.kind == "station":
				st = a
		if st != null:
			break
	if st == null:
		_ok("the minimap, the map's arrow, waypoints, and a view that turns only when you turn it", false, "; ".join(rows) + "; (!) no station came in (in space %s, aboard %s, the skiff %.0f from the middle, the band at %.0f)" % [g.space.active, g.player.aboard == sk, sk.pos.length(), Defs.R_SPACE])
		return
	# well away from it, in deep space: Q turns the view, the station turns to match while you're away
	sk.pos = st.pos + Vector2(7000.0, 2500.0)
	sk.vel = Vector2.ZERO
	await _frames(20)
	var v0: float = g.space.view_ang
	g.test_turn = 1.0
	await _frames(40)
	g.test_turn = 0.0
	var turned: float = absf(wrapf(g.space.view_ang - v0, -PI, PI))
	await _frames(30)
	var upv := Vector2.from_angle(g.space.view_ang)
	var want_st := Vector2(upv.y, -upv.x).angle()
	var st_aligned: bool = absf(wrapf(st.ang - want_st, -PI, PI)) < 0.01
	# the minimap out here: what's round you, you pointing the way the skiff's nose points
	var mm_ok: bool = mm.mode == "space" and int(mm.stats.get("planet", 0)) + int(mm.stats.get("star", 0)) >= 1 and int(mm.stats.get("rock", 0)) >= 1
	var xf: Transform2D = g.screen_xf()
	var face_ok: bool = mm.facing.dot(xf.basis_xform(g.facing_dir(g.player)).normalized()) > 0.95
	# (27 Nov, user: "the waypoint should be easy to see on the mini map when in space": a waypoint set out here, drawn
	# last with its ring, its line from you, and an arrow on the rim when it's past the minimap's reach)
	var wp_was = g.space.waypoint
	var pg: PackedFloat64Array = g.space.player_g()
	g.space.waypoint = PackedFloat64Array([pg[0] + 2500.0, pg[1] - 1500.0])
	g.space.zoom_i = 2
	await _frames(40)
	var wp_drawn: int = int(mm.stats.get("waypoint", 0))
	_shot("minimap_space.png")
	g.space.waypoint = wp_was
	g.space.zoom_i = 0
	rows.append("%sa waypoint out in space on the minimap: drawn %d" % ["" if wp_drawn >= 1 else "(!) ", wp_drawn])
	ok = ok and wp_drawn >= 1
	# the chart's arrow: north up, the way you face in space's own directions
	g.open_map()
	await _frames(20)
	var chart_ok: bool = g.map_tab == "space" and g.map_view.you_dir.dot(g.facing_dir(g.player).normalized()) > 0.95
	_shot("map_space_facing.png")
	g.close_map()
	await _frames(20)
	# up to it: the view doesn't turn (it was already upright for you)
	var fb := Vector2(float(st.w) * 0.5, -12.0)
	sk.pos = st.to_world(fb - st.com)
	sk.vel = Vector2.ZERO
	var va0: float = g.space.view_ang
	var spin := 0.0
	for k2 in 90:
		sk.vel = Vector2.ZERO
		await _frames(1)
		spin = maxf(spin, absf(wrapf(g.space.view_ang - va0, -PI, PI)))
	var framed: bool = g.space.frame_st == st
	var ok3: bool = held_near and turned > 0.9 and st_aligned and mm_ok and face_ok and chart_ok and framed and spin < 0.03
	rows.append("%sin space: Q held near the planet left the view %s; out in deep space it turned it %.2f rad; the derelict turned to match while away %s; the radar (%s) %s; its arrow the skiff's way %s; the chart's arrow %s; came up to the derelict (at it %s) and the view turned %.3f rad" % [
		"" if ok3 else "(!) ", "held" if held_near else "turned", turned, st_aligned, str(mm.stats), mm_ok, face_ok, chart_ok, framed, spin])
	ok = ok and ok3
	# ---- back to the planet, upside down: it rights the view before you get there
	var ha: Vector2 = g.space.home_at()
	var dir: Vector2 = (sk.pos - ha).normalized()
	sk.pos = ha + dir * (Defs.R_SPACE + 9000.0)
	sk.vel = Vector2.ZERO
	await _frames(30)
	g.space.view_ang = wrapf((sk.pos - ha).angle() + 2.6, -PI, PI)
	var off0: float = absf(wrapf(g.space.view_ang - (g.cam_c - ha).angle(), -PI, PI))
	var off1 := 0.0
	for k3 in 400:
		sk.vel = -dir * 18.0
		await _frames(1)
		if not g.space.active:
			break
		if (sk.pos - ha).length() < Defs.R_SPACE + 1200.0:
			off1 = absf(wrapf(g.space.view_ang - (g.cam_c - ha).angle(), -PI, PI))
			break
	var ok4: bool = off0 > 2.0 and off1 < 0.12
	rows.append("%scoming down upside down (%.2f rad off): by 1200 over the orbit band the view was %.3f off upright" % ["" if ok4 else "(!) ", off0, off1])
	ok = ok and ok4
	# down and out of the skiff, as the checks after this expect
	for k4 in 300:
		sk.vel = -sk.pos.normalized() * 8.0
		await _frames(1)
		if not g.space.active:
			break
	sk.pos = sk.pos.normalized() * (g.gpu.surf_at(atan2(sk.pos.y, sk.pos.x)).x + 30.0)
	sk.vel = Vector2.ZERO
	g.test_down = true
	for k5 in 300:
		await _frames(1)
		if sk.grounded:
			break
	g.test_down = false
	await _frames(20)
	if g.player.aboard == sk:
		g._skiff_interact(g.player)
	await _frames(20)
	# (26 Nov, user: "a cursor for the space minimap and a zoom function as well"): the wheel over it zooms each view
	var mmz = g.ui.minimap
	var mz_mode: String = mmz.mode
	mmz.mode = "space"
	var r5a: float = mmz._rad(5000.0)
	mmz.zoom_by(2)
	var r5b: float = mmz._rad(5000.0)
	mmz.zoom_by(-2)
	mmz.mode = "planet"
	var ce0: float = mmz._cells()
	mmz.zoom_by(2)
	var ce1: float = mmz._cells()
	mmz.zoom_by(-2)
	mmz.mode = mz_mode
	var ok_z: bool = r5b > r5a + 4.0 and ce1 < ce0 and absf(mmz.sp_zoom - 1.0) < 0.01 and absf(mmz.pl_zoom - 1.0) < 0.01
	rows.append("%szoomed in: 5k out in space %.0f -> %.0f px from the middle, on a planet %.1f -> %.1f cells a pixel" % ["" if ok_z else "(!) ", r5a, r5b, ce0, ce1])
	ok = ok and ok_z
	_ok("the minimap, the map's arrow, waypoints, and a view that turns only when you turn it", ok, "; ".join(rows))

func _test_stations() -> void:
	var rows := []
	var ok := true
	var G = load("res://scripts/galaxy.gd")
	var S = load("res://scripts/station.gd")
	# ---- where: STATION_D from the first planet, clear of the planets, the outpost and the first wreck
	var sg0: PackedFloat64Array = G.system_station(0)
	var hg: PackedFloat64Array = Defs.planet_g(0)
	var sd0: float = Defs.g_rel(sg0, hg).length()
	var s_op: float = Defs.g_rel(sg0, G.system_outpost(0)).length()
	var s_fw: float = Defs.g_rel(sg0, G.first_wreck()).length()
	var s_in := false
	for c in G.sector_content(G.sector_of(sg0[0], sg0[1])):
		if c["type"] == "station":
			s_in = true
	var ok1: bool = sd0 > 34000.0 and sd0 < 42000.0 and s_op > 15000.0 and s_fw > 13000.0 and s_in and not G._near_planet_r(sg0[0], sg0[1], G.NEAR_PLANET + 6000.0)
	rows.append("%s%s: %.0fk from home, %.0fk from the outpost, %.0fk from the first wreck, in its sector's content %s" % ["" if ok1 else "(!) ", G.station_name(0), sd0 / 1000.0, s_op / 1000.0, s_fw / 1000.0, s_in])
	ok = ok and ok1
	# ---- grown: every room reached from outside (drifting, with the hatches' one-way floors open), the vault
	# only once its seal is broken; powered and dead rooms both; aliens and caches in it
	var n_good := 0
	var lay_txt := []
	var shells_ok := 0
	# (27 Nov: the halls are a level now, four or five times the cells: four grown, not ten)
	for q in 4:
		# (the shell out in space: its bay sealed by a pane, no aliens, no caches; user, 25 Nov: docked into an
		# instance instead)
		var shq = S.make_station(7001 + q * 1543)
		var dmq: Dictionary = shq.mods[shq.dock]
		var pxq: int = (int(dmq["x0"]) - shq.T if shq.dock_side < 0 else int(dmq["x1"])) + shq.T / 2
		var paneq := 0
		for jq in range(int(dmq["y1"]) - shq.MOUTH, int(dmq["y1"])):
			if shq.at(pxq, jq) == Defs.GLASS or shq.at(pxq, jq) == Defs.FROST:
				paneq += 1
		if paneq >= shq.MOUTH - 2 and shq.spawns.is_empty() and shq.caches.is_empty():
			shells_ok += 1
		var sq = S.make_station(7001 + q * 1543, true)
		var reach_shut := _station_rooms_reached(sq)
		# (and every door's doorway clear when it's open: nothing grown into one)
		var doors_clear := 0
		for dq in sq.doors:
			var dcx: float = float(int(dq["x"])) + float(sq.BW) * 0.5
			if dq["sealed"] or sq.box_free(Vector2(dcx, float(int(dq["y1"])) - 9.0), 3.5, 8.5):
				doors_clear += 1
		sq.open_seal()
		var reach_open := _station_rooms_reached(sq)
		var n_pow := 0
		for md in sq.mods:
			if md["powered"]:
				n_pow += 1
		var all_but_vault := true
		for k in sq.mods.size():
			if k != sq.vault and not reach_shut[k]:
				all_but_vault = false
		var vault_shut: bool = not reach_shut[sq.vault]
		var vault_open: bool = reach_open[sq.vault]
		var has_vc := false
		for cc2 in sq.caches:
			if cc2["kind"] == "vault":
				has_vc = true
		var n_brood := 0
		for sp in sq.spawns:
			if sp["kind"] == "brood":
				n_brood += 1
		var n_corr := 0
		var n_shaft := 0
		var tall := 0
		for md2 in sq.mods:
			if String(md2["kind"]) == "corridor":
				n_corr += 1
			elif String(md2["kind"]) == "shaft":
				n_shaft += 1
			elif int(md2["y1"]) - int(md2["y0"]) >= 130:
				tall += 1
		var good: bool = all_but_vault and vault_shut and vault_open and n_pow >= 2 and n_pow < sq.mods.size() and has_vc and n_brood == 1 and sq.caches.size() >= 8 and sq.mods.size() >= 24 \
			and n_corr >= 6 and n_shaft >= sq.rows - 1 and doors_clear == sq.doors.size()
		if good:
			n_good += 1
		lay_txt.append("%s%d decks, %d rooms (%d of them 130+ high), %d corridors, %d shafts (%d powered), %d doors (%d clear), %d aliens, %d caches, %dx%d grown in %s ms; all reached %s, vault shut %s then open %s" % ["" if good else "(!) ", sq.rows, sq.mods.size() - n_corr - n_shaft, tall, n_corr, n_shaft, n_pow, sq.doors.size(), doors_clear, sq.spawns.size(), sq.caches.size(), sq.w, sq.h, str(sq.meta.get("ms", -1)), all_but_vault, vault_shut, vault_open])
		if q < 3:
			_station_picture(sq, "station_layout_%d.png" % q)
	var ok2: bool = n_good == 4 and shells_ok == 4
	rows.append("%s4 stations' halls grown as levels: %d sound; their shells sealed and empty %d. %s" % ["" if ok2 else "(!) ", n_good, shells_ok, " | ".join(lay_txt)])
	ok = ok and ok2
	# ---- up into space in the skiff, out to the station
	g.player.dead = false
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var up0: Vector2 = sk.pos.normalized()
	sk.pos = up0 * (Defs.R_SPACE - 11.0)
	sk.vel = up0 * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	g.test_cast = false
	var sl: Vector2 = g.space.local_of(sg0)
	sk.pos = sl + Vector2(-1400.0, 0.0)
	sk.vel = Vector2.ZERO
	var st = null
	for k1 in 300:
		sk.vel = Vector2.ZERO
		await _frames(1)
		for a in g.space.rocks:
			if a.kind == "station":
				st = a
		if st != null:
			break
	if st == null:
		_ok("derelict stations: grown, boarded, fought through, looted", false, "; ".join(rows) + "; (!) no station came in with its sector")
		return
	# outside it, by the dock (its shell: sealed)
	var shell = st
	var dm: Dictionary = st.mods[st.dock]
	var mouth_b := Vector2(float(int(dm["x0"]) - 60) if st.dock_side < 0 else float(int(dm["x1"]) + 60), float(int(dm["y1"]) - 16))
	sk.pos = st.to_world(mouth_b - st.com) + st.axis_x() * float(st.dock_side) * 40.0
	sk.vel = Vector2.ZERO
	g.space.zoom_i = 3
	await _frames(70)
	_shot("station_outside.png")
	g.space.zoom_i = 0
	await _frames(30)
	# ---- F docks (user, 25 Nov: "press a button to dock and go inside an instanced area"): its halls grown in a
	# worker, standing where the shell stood, nothing else out here while you're in; you on its bay's floor
	var ship_at: Vector2 = sk.pos
	var n_out: int = g.space.rocks.size()
	var can_dock: bool = g.space.dock_target(g.player) == shell
	g._interact()
	var dock_t := -1
	for kd in 300:
		await _frames(1)
		if g.space.inst != null:
			dock_t = kd
			break
	if g.space.inst == null:
		g.space.dock_station_now(g.player, shell)
	st = g.space.inst
	var al_n := 0
	for al in g.space.aliens:
		if al.st == st:
			al_n += 1
	var got_in := false
	for k2 in 120:
		await _frames(1)
		if g.space.in_station == st:
			got_in = true
			break
	await _frames(30)
	_shot("station_docked.png")
	var alone: bool = g.space.rocks.size() == 1 and g.space.rocks[0] == st
	var ok_dock: bool = can_dock and dock_t >= 0 and st.halls and got_in and alone and g.player.aboard == null and n_out > 1
	rows.append("%sF docked %s (in %d ticks): in its halls %s (%d rooms, %d aliens), alone in them %s (%d things out here before)" % ["" if ok_dock else "(!) ", can_dock, dock_t, got_in, st.mods.size(), al_n, alone, n_out])
	ok = ok and ok_dock
	var framed: bool = g.space.frame_st == st and absf(wrapf(g.space.view_ang - (g.cam_c - g.space.centre).angle(), -PI, PI)) < 0.2
	_shot("station_dock.png")
	var ok3: bool = got_in and framed and al_n > 0
	rows.append("%s%s's halls: %d aliens; the view levelled with its floor %s" % ["" if ok3 else "(!) ", st.wname, al_n, framed])
	ok = ok and ok3
	# ---- a powered room: you fall to its floor, walk, jump, land on a ledge and drop through it
	var pr := -1
	var br := -1
	for k3 in st.mods.size():
		var role: String = st.mods[k3]["role"]
		if role == "vault" or role == "nest":
			continue
		# (a level's: a plain room with nothing standing in its middle, no mezzanine or dais to land on)
		var plain: bool = (role == "quarters" or role == "stores" or role == "hall" or role == "dock") and String(st.mods[k3].get("kind", "room")) == "room" \
			and not st.mods[k3].has("mezz") and not st.mods[k3].has("dais")
		if st.mods[k3]["powered"] and String(st.mods[k3].get("kind", "room")) == "room" and not st.mods[k3].has("mezz") and not st.mods[k3].has("dais") \
				and (pr < 0 or plain and not ["quarters", "stores", "hall", "dock"].has(String(st.mods[pr]["role"]))):
			pr = k3
		elif not st.mods[k3]["powered"] and (br < 0 or String(st.mods[br].get("kind", "room")) != "room") and String(st.mods[k3].get("kind", "room")) != "shaft":
			br = k3
	var calm := func() -> void:
		for al2 in g.space.aliens:
			al2.awake = false
			al2.cd = 9999
	var pw_txt := "no powered room"
	var pw_ok := false
	if pr >= 0:
		calm.call()
		var pm: Dictionary = st.mods[pr]
		_st_put(st, st.room_mid(pr))
		await _frames(70)
		var b1: Vector2 = st.to_body(g.player.pos) + st.com
		var feet1: float = b1.y + 8.5
		var on_floor: bool = g.player.on_ground and feet1 < float(int(pm["y1"])) + 0.6 and feet1 > float(int(pm["y1"])) - 7.0
		g.test_move = 1 if b1.x < st.room_mid(pr).x + 10.0 else -1
		await _frames(14)
		g.test_move = 0
		var b2: Vector2 = st.to_body(g.player.pos) + st.com
		var walked: float = absf(b2.x - b1.x)
		await _frames(10)
		g.test_jump = true
		var top := b2.y
		for k4 in 50:
			await _frames(1)
			top = minf(top, (st.to_body(g.player.pos) + st.com).y)
		g.test_jump = false
		await _frames(60)
		var b3: Vector2 = st.to_body(g.player.pos) + st.com
		var rise: float = b2.y - top
		var landed: bool = g.player.on_ground
		_shot("station_powered.png")
		# levitating, held up well past a jump (27 Nov: "room for a full jump and levitation in the rooms")
		var lev0: float = (st.to_body(g.player.pos) + st.com).y
		var lev_top := lev0
		g.test_jump = true
		for k4b in 100:
			await _frames(1)
			lev_top = minf(lev_top, (st.to_body(g.player.pos) + st.com).y)
			if k4b == 70:
				_shot("station_levitate.png")
		g.test_jump = false
		await _frames(100)
		var lev_rise: float = lev0 - lev_top
		pw_ok = on_floor and walked > 12.0 and rise > 20.0 and landed and lev_rise > 50.0
		pw_txt = "%s (%d high): fell to the floor %s, walked %.0f cells, jumped %.0f up and landed %s, levitated %.0f up" % [st.role_name(pr), int(pm["y1"]) - int(pm["y0"]), on_floor, walked, rise, landed, lev_rise]
		# a ledge (a hatch's one-way floor's ledge) in a powered room
		var ledge = null
		for k5 in st.mods.size():
			if not st.mods[k5]["powered"] or ledge != null:
				continue
			var lm: Dictionary = st.mods[k5]
			# (a level's: a shaft's ledges, a catwalk, a mezzanine; looked for only where they are)
			if st.lv and String(lm.get("kind", "room")) != "shaft" and not lm.has("mezz") and not lm.has("catwalks"):
				continue
			for j in range(int(lm["y0"]) + 4, int(lm["y1"]) - 4):
				for i in range(int(lm["x0"]) + 4, int(lm["x1"]) - 4):
					if ledge == null and st.at(i, j) == Defs.SCAFFOLD and st.at(i + 6, j) == Defs.SCAFFOLD and st.at(i + 12, j) == Defs.SCAFFOLD:
						ledge = Vector2i(i + 7, j)
		if ledge != null:
			_st_put(st, Vector2(float(ledge.x), float(ledge.y) - 8.5 - 3.0))
			await _frames(50)
			var b4: Vector2 = st.to_body(g.player.pos) + st.com
			print("[stations] ledge at %s (room %s), mage at %s, on the ground %s, box free there %s" % [ledge, st.role_name(st.module_at(Vector2(ledge))), b4, g.player.on_ground, st.box_free(b4, 3.5, 8.5)])
			var on_ledge: bool = g.player.on_ground and absf(b4.y + 8.5 - float(ledge.y)) < 1.0
			g.test_down = true
			g.test_jump = true
			await _frames(6)
			g.test_jump = false
			await _frames(14)
			g.test_down = false
			var b5: Vector2 = st.to_body(g.player.pos) + st.com
			var dropped: bool = b5.y + 8.5 > float(ledge.y) + 3.0
			pw_ok = pw_ok and on_ledge and dropped
			pw_txt += "; stood on a one-way ledge %s, dropped through it %s" % [on_ledge, dropped]
	rows.append("%s%s" % ["" if pw_ok else "(!) ", pw_txt])
	ok = ok and pw_ok
	# ---- a door (27 Nov, "doors you cant see through"): shut, the room past it dark; walk up and it opens and the room
	# past it comes into sight; step away and it shuts behind you, dark again (the aliens kept out of it)
	var door_ok := false
	var door_txt := "no door"
	if pr >= 0:
		calm.call()
		g.space.doors_for_aliens = false
		var dd = null
		for dq2 in st.doors:
			if not dq2["sealed"] and (int(dq2["a"]) == pr or int(dq2["b"]) == pr) and int(dq2["d"]) == int(st.mods[pr]["d1"]):
				dd = dq2
				break
		if dd != null:
			var other: int = int(dd["b"]) if int(dd["a"]) == pr else int(dd["a"])
			var dcx: float = float(int(dd["x"])) + float(st.BW) * 0.5
			var ps: float = -1.0 if int(dd["a"]) == pr else 1.0
			_st_put(st, Vector2(dcx + ps * 80.0, float(int(dd["y1"])) - 9.5))
			await _frames(50)
			var shut0: bool = float(dd["f"]) == 0.0 and st.vis[other] < 0.3
			g.test_move = -int(ps)
			var opened := -1
			for kd2 in 150:
				await _frames(1)
				if float(dd["f"]) >= 1.0 and opened < 0:
					opened = kd2
				if opened >= 0 and st.vis[other] > 0.6:
					break
			g.test_move = 0
			var seen_past: bool = st.vis[other] > 0.6
			_shot("station_door.png")
			_st_put(st, Vector2(dcx + ps * 100.0, float(int(dd["y1"])) - 9.5))
			await _frames(100)
			var shut1: bool = float(dd["f"]) == 0.0 and st.vis[other] < 0.3
			door_ok = shut0 and opened >= 0 and seen_past and shut1
			door_txt = "a door from the %s to the %s: shut, dark past it %s; walked up, open in %d ticks, the room past it in sight %s; stepped away, shut and dark again %s" % [st.role_name(pr), st.role_name(other), shut0, opened, seen_past, shut1]
		g.space.doors_for_aliens = true
	rows.append("%s%s" % ["" if door_ok else "(!) ", door_txt])
	ok = ok and door_ok
	# ---- a dead room: no gravity; the movement keys push you
	var bk_ok := false
	var bk_txt := "no dead room"
	if br >= 0:
		calm.call()
		_st_put(st, st.room_mid(br))
		await _frames(40)
		var c1: Vector2 = st.to_body(g.player.pos) + st.com
		var drift: float = c1.distance_to(st.room_mid(br))
		var floats: bool = not g.player.on_ground and g.player.floating
		g.test_move = 1
		await _frames(30)
		g.test_move = 0
		var c2: Vector2 = st.to_body(g.player.pos) + st.com
		g.test_jump = true
		await _frames(20)
		g.test_jump = false
		var c3: Vector2 = st.to_body(g.player.pos) + st.com
		_shot("station_dead_room.png")
		bk_ok = drift < 2.0 and floats and c2.x - c1.x > 8.0 and c2.y - c3.y > 3.0
		bk_txt = "%s: hung where it was put (%.1f cells in 40 frames) floating %s; pushed along %.0f and up %.0f by the jet" % [st.role_name(br), drift, floats, c2.x - c1.x, c2.y - c3.y]
		g.space.vel = Vector2.ZERO
	rows.append("%s%s" % ["" if bk_ok else "(!) ", bk_txt])
	ok = ok and bk_ok
	# ---- fighting: a spell kills a skitter; a skitter's bite hurts; a drifter spits
	g.player.known = g.player.known.duplicate()
	if not g.player.known.has("spark"):
		g.player.known.append("spark")
	g.player.sel = g.player.known.find("spark")
	var sk_al = null
	var dr_al = null
	for al3 in g.space.aliens:
		if al3.st != st or al3.dead:
			continue
		if al3.kind == "skitter" and al3.home != st.nest and sk_al == null:
			sk_al = al3
		if al3.kind == "drifter" and al3.home != st.nest and dr_al == null:
			dr_al = al3
	var fight_ok := false
	var fight_txt := "no skitter"
	if sk_al != null:
		var kills0: int = int(g.space.stats.get("aliens_killed", 0))
		var xen0: int = g.player.inv[Defs.XENITE]
		var hp0: float = g.player.hp
		g.test_god = false
		sk_al.awake = true
		sk_al.cd = 9999
		_st_put(st, _st_spot(st, sk_al))
		var bit := false
		for k6 in 150:
			await _frames(1)
			if g.player.hp < hp0:
				bit = true
				break
		g.player.hp = g.player.max_hp
		g.test_god = true
		_st_put(st, _st_spot(st, sk_al))
		var shots := 0
		for k7 in 400:
			g.test_aim = sk_al.world()
			g.test_cast = k7 % 4 < 2
			if g.test_cast and k7 % 4 == 0:
				shots += 1
			await _frames(1)
			if sk_al.dead:
				break
			if k7 == 30:
				_shot("station_fight.png")
		g.test_cast = false
		await _frames(10)
		var killed: bool = sk_al.dead and int(g.space.stats.get("aliens_killed", 0)) > kills0
		var xen_got: int = g.player.inv[Defs.XENITE] - xen0
		fight_ok = bit and killed and xen_got > 0
		fight_txt = "a skitter bit you %s; spark bolts (%d cast, %d hits) killed it %s, %d Xenite" % [bit, shots, int(g.space.stats.get("alien_hits", 0)), killed, xen_got]
	var spat := false
	if dr_al != null:
		calm.call()
		dr_al.awake = true
		dr_al.cd = 10
		_st_put(st, _st_spot(st, dr_al))
		for k8 in 240:
			await _frames(1)
			if not g.space.acid.is_empty():
				spat = true
				break
		if spat:
			await _frames(6)
			_shot("station_drifter.png")
		fight_txt += "; a drifter spat acid %s" % spat
		fight_ok = fight_ok and spat
	rows.append("%s%s" % ["" if fight_ok else "(!) ", fight_txt])
	ok = ok and fight_ok
	# ---- the nest: the Broodmother lays skitters and spits; she falls; the seal on the vault breaks
	var brood = null
	for al4 in g.space.aliens:
		if al4.st == st and al4.kind == "brood":
			brood = al4
	var nest_ok := false
	var nest_txt := "no Broodmother"
	if brood != null:
		calm.call()
		var seal0: bool = st.seal_open
		var nm: Dictionary = st.mods[st.nest]
		_st_put(st, Vector2(float(int(nm["x0"]) + 14), float(int(nm["y1"])) - 10.0))
		brood.awake = true
		brood.cd = 30
		brood.lay_cd = 60
		var laid0: int = int(g.space.stats.get("laid", 0))
		for k9 in 160:
			g.test_aim = brood.world()
			await _frames(1)
			if k9 == 100:
				_shot("station_brood.png")
		var laid: bool = int(g.space.stats.get("laid", 0)) > laid0
		brood.hp = 30.0
		for k10 in 400:
			g.test_aim = brood.world()
			g.test_cast = k10 % 4 < 2
			await _frames(1)
			if brood.dead:
				break
		g.test_cast = false
		await _frames(20)
		var sealed_then_open: bool = not seal0 and st.seal_open
		var cleared := true
		for sc3 in st.seal_cells:
			if st.cells[sc3] == Defs.RUNESTONE or st.cells[sc3] == Defs.WISP:
				cleared = false
		nest_ok = laid and brood.dead and sealed_then_open and cleared
		nest_txt = "the Broodmother laid skitters %s, fell %s; the vault's seal was shut and broke %s (its runestone gone %s)" % [laid, brood.dead, sealed_then_open, cleared]
	rows.append("%s%s" % ["" if nest_ok else "(!) ", nest_txt])
	ok = ok and nest_ok
	# ---- the vault: its cache holds a Scanner Lens; the Wisp Scanner can be forged
	calm.call()
	var vc = null
	for vc4 in st.caches:
		if vc4["kind"] == "vault":
			vc = vc4
	var vault_ok := false
	if vc != null:
		g.items.erase("part_scanner")
		g.items.erase("scanner")
		g.player.pos = st.cache_pos(vc) - st.axis_y() * 6.0 - st.axis_x() * 14.0
		g.space.vel = Vector2.ZERO
		await _frames(12)
		var near_it: bool = g.space.near_cache == vc
		g._interact()
		await _frames(10)
		_shot("station_vault.png")
		var sc_rec: Dictionary = {}
		for r2 in g.recipes:
			if r2["id"] == "scanner":
				sc_rec = r2
		vault_ok = near_it and bool(vc["open"]) and g.items.has("part_scanner") and not sc_rec.is_empty() and g.recipe_unlocked(sc_rec)
		rows.append("%sthe vault's cache in reach %s, opened %s: a Scanner Lens %s, the Wisp Scanner can be forged %s" % ["" if vault_ok else "(!) ", near_it, vc["open"], g.items.has("part_scanner"), not sc_rec.is_empty() and g.recipe_unlocked(sc_rec)])
	else:
		rows.append("(!) no vault cache")
	ok = ok and vault_ok
	# ---- kept: streamed out and in again, it's as you left it
	var key: String = st.state_key()
	var ss: Dictionary = g.space.save_state()
	var saved: bool = (ss.get("stations", {}) as Dictionary).has(key)
	var dead_n: int = (g.space.station_state[key]["dead"] as Array).size()
	var open_n: int = (g.space.station_state[key]["open"] as Array).size()
	var st2 = S.make_station(st.seed_, true)
	st2.pos = st.pos
	st2.ang = st.ang
	var alive_before := 0
	for al5 in g.space.aliens:
		if al5.st == st and not al5.dead and al5.id >= 0:
			alive_before += 1
	g.space._station_out(st)
	g.space.rocks.erase(st)
	st2.sect = st.sect
	g.space.rocks.append(st2)
	g.space.inst = st2
	g.space._station_in(st2)
	var alive_after := 0
	for al6 in g.space.aliens:
		if al6.st == st2:
			alive_after += 1
	var open2 := 0
	for oc5 in st2.caches:
		if oc5["open"]:
			open2 += 1
	var kept_ok: bool = saved and st2.seal_open and open2 == open_n and alive_after == alive_before and dead_n > 0
	rows.append("%skept: in the save %s; grown again with its seal broken %s, %d of its caches open (%d), %d aliens alive (%d before; %d dead kept)" % ["" if kept_ok else "(!) ", saved, st2.seal_open, open2, open_n, alive_after, alive_before, dead_n])
	ok = ok and kept_ok
	# the map
	g.open_map()
	g.map_view.gz = 300.0
	g.map_view.centre_on_you()
	await _frames(10)
	_shot("station_map.png")
	g.close_map()
	await _frames(4)
	# ---- back to your ship in the bay: F undocks; aboard, out by the shell where you were, everything back
	calm.call()
	var dmh: Dictionary = st2.mods[st2.dock]
	var bay_mid := Vector2((float(int(dmh["x0"])) + float(int(dmh["x1"]))) * 0.5, float(int(dmh["y1"])) - 9.6)
	_st_put(st2, bay_mid)
	await _frames(20)
	g.player.pos = sk.pos + st2.axis_y() * 4.0
	g.space.vel = Vector2.ZERO
	await _frames(2)
	var by_it: bool = g.space.by_ship(g.player)
	g._interact()
	await _frames(10)
	var back_out: bool = by_it and g.space.inst == null and g.player.aboard == sk and sk.pos.distance_to(ship_at) < 1.0 and g.space.rocks.has(shell) and g.space.rocks.size() >= n_out - 1
	var halls_gone := true
	for al7 in g.space.aliens:
		if al7.st == st2:
			halls_gone = false
	rows.append("%sF at your ship undocked %s: aboard, by its shell where you were %s, its aliens set aside with its halls %s" % ["" if back_out and halls_gone else "(!) ", by_it, back_out, halls_gone])
	ok = ok and back_out and halls_gone
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g.space.vel = Vector2.ZERO
		g._skiff_interact(g.player)
	await _frames(4)
	sk.pos = g.space.home_at() + (sl - g.space.home_at()).normalized() * (Defs.R_SPACE + 150.0)
	sk.vel = -(sk.pos - g.space.home_at()).normalized() * 6.0
	g.test_cast = true
	for k11 in 600:
		g.test_aim = g.space.home_at() + (sk.pos - g.space.home_at()) * 0.3
		await _frames(1)
		if not g.space.active:
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	for k12 in 1200:
		await _frames(1)
		if sk.grounded and sk.vel.length() < 0.5:
			break
	g.test_down = false
	await _frames(20)
	if g.player.aboard != null:
		g._skiff_interact(g.player)
		await _frames(10)
	print("[stations] " + "\n[stations] ".join(rows))
	_ok("derelict stations: docked into their halls by F, gravity by section, aliens fought, the Broodmother and her vault, kept, undocked", ok, "; ".join(rows))

## (user, 23 Nov: wisp fuel "Only the long hauls": the Starsail and journeys between planets burn Wisp Cells)
func _test_fuel() -> void:
	var rows := []
	var ok := true
	# ---- where it comes from: the smelter (wisp ore and coal), the outposts
	var smelt := false
	for pr in Defs.PROCESS:
		if pr["at"] == "smelter" and (pr.get("give", {}) as Dictionary).has(Defs.WISPCELL):
			smelt = true
	var sold := false
	for it in Defs.SHOPS["shipwright"]["sell"]:
		if (it.get("give", {}) as Dictionary).has(Defs.WISPCELL):
			sold = true
	var ok1: bool = smelt and sold
	rows.append("%sWisp Cells smelted %s, sold at outposts %s" % ["" if ok1 else "(!) ", smelt, sold])
	ok = ok and ok1
	# ---- up in the skiff
	g.player.dead = false
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var up0: Vector2 = sk.pos.normalized()
	sk.pos = up0 * (Defs.R_SPACE - 11.0)
	sk.vel = up0 * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	g.test_cast = false
	var had_sail: bool = g.items.has("sail")
	g.items["sail"] = true
	g.free_fuel = false
	var cells0: int = g.player.inv[Defs.WISPCELL]
	# ---- out in the dark, away from home: no cells, no Starsail
	sk.pos = g.space.home_at() + up0 * (Defs.R_SPACE + 9000.0)
	sk.vel = Vector2.ZERO
	g.player.inv[Defs.WISPCELL] = 0
	g.space._burn = 0.0
	g.test_sail = true
	g.test_move = 1
	for k2 in 60:
		g.test_aim = sk.pos + up0 * 400.0
		await _frames(1)
	var dry_sail: float = g.space.sail
	var dry_speed: float = sk.vel.length()
	g.test_sail = false
	g.test_move = 0
	await _frames(20)
	# ---- three cells: it runs, burning one every few seconds
	sk.vel = Vector2.ZERO
	g.player.inv[Defs.WISPCELL] = 3
	var burned0: int = int(g.space.stats.get("cells_burned", 0))
	var top := 0.0
	g.test_sail = true
	g.test_move = 1
	for k3 in 400:
		g.test_aim = sk.pos + up0 * 400.0
		await _frames(1)
		top = maxf(top, sk.vel.length())
	g.test_sail = false
	g.test_move = 0
	var burned: int = int(g.space.stats.get("cells_burned", 0)) - burned0
	var left: int = g.player.inv[Defs.WISPCELL]
	# (with the last one gone it stops)
	g.player.inv[Defs.WISPCELL] = 0
	g.space._burn = 0.0
	g.test_sail = true
	g.test_move = 1
	for k3b in 40:
		g.test_aim = sk.pos + up0 * 400.0
		await _frames(1)
	var stopped: bool = not g.space.sailing
	g.test_sail = false
	g.test_move = 0
	var ok2: bool = dry_sail < 0.05 and dry_speed < 45.0 and top > 150.0 and burned >= 2 and left <= 1 and stopped
	rows.append("%swith no cells the Starsail stayed furled (%.2f, %.0f a tick); with 3 it ran up to %.0f a tick and burned %d in 400 ticks (%d left); none left, it stopped %s" % ["" if ok2 else "(!) ", dry_sail, dry_speed, top, burned, left, stopped])
	ok = ok and ok2
	sk.vel = Vector2.ZERO
	await _frames(30)
	# ---- a landfall burns no cells (only the Starsail does, since 24 Nov): with none, an open world (no
	# barrier) is still in reach
	g.player.inv[Defs.WISPCELL] = 0
	var open_i := -1
	for oi in range(1, Defs.SYSTEM.size()):
		if Defs.barrier_of(oi) == "":
			open_i = oi
	var ok3: bool = open_i >= 0 and g.space.reachable(open_i) and not g.space.has_method("journey_cost")
	rows.append("%swith no cells, %s (no barrier) is in reach %s; a landfall costs nothing" % ["" if ok3 else "(!) ", Defs.make_planet(maxi(open_i, 0))["name"], open_i >= 0 and g.space.reachable(open_i)])
	ok = ok and ok3
	g.player.inv[Defs.WISPCELL] = cells0
	g.free_fuel = true
	if not had_sail:
		g.items.erase("sail")
	# home again, and down
	sk.pos = g.space.home_at() + up0 * (Defs.R_SPACE + 150.0)
	sk.vel = -up0 * 6.0
	g.test_cast = true
	for k5 in 600:
		g.test_aim = g.space.home_at() + (sk.pos - g.space.home_at()) * 0.3
		await _frames(1)
		if not g.space.active:
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	for k6 in 1200:
		await _frames(1)
		if sk.grounded and sk.vel.length() < 0.5:
			break
	g.test_down = false
	await _frames(20)
	if g.player.aboard != null:
		g._skiff_interact(g.player)
		await _frames(10)
	print("[fuel] " + "\n[fuel] ".join(rows))
	_ok("wisp fuel: the Starsail burns Wisp Cells, none means furled; a landfall costs none", ok, "; ".join(rows))

## Ships as classes (user, 25 Nov: "maybe we have prefab ships instead that you can get recipes for different
## ships", no building on the ship, no seats: you're inside): every class grown whole from its parts (one piece,
## an engine, its look by seed: saves/shots/ships.png), its stats (speed, armour, crates, guns); the first forged
## at the Wisp Forge, another learned and forged and flown, swapped back, another look; no swap aboard; B aboard
## opens no builder; a journey from before keeps its ship (as a Skiff); the quest's step boards it. Then the
## pocket (_test_pocket) from aboard.
func _test_ships() -> void:
	var rows := []
	var ok := true
	var Sk = load("res://scripts/skiff.gd")
	g.player.dead = false
	g.test_god = true
	if g.build_on:
		g._toggle_build()
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	g.player.deck = false
	var keep_items := {}
	for ik in ["skiff", "ships", "ship_class", "ship", "boarded", "drive"]:
		if g.items.has(ik):
			keep_items[ik] = g.items[ik]
	# ---- every class, three seeds each: whole (one piece), an engine, no bigger than a ship may be; a sheet
	var sheet := []
	var bad := []
	for kc in Sk.CLASSES:
		for sq in 3:
			var shp = Sk.make(2000 + sq * 7919, kc)
			shp.rebuild()
			var np: int = shp.pieces().size()
			if np != 1 or shp.engine0 < 4 or shp.w > Sk.MAX_W or shp.h > Sk.MAX_H or shp.hold_cap() != int(Sk.CLASSES[kc]["cargo"]) or absf(shp.drive() - float(Sk.CLASSES[kc]["speed"])) > 0.001:
				bad.append("%s#%d: %d pieces, %d engine cells, %dx%d, hold %d, drive %.2f" % [kc, sq, np, shp.engine0, shp.w, shp.h, shp.hold_cap(), shp.drive()])
			sheet.append(shp.texture().get_image())
	var sw := 8
	var sh := 0
	for im in sheet:
		sh = maxi(sh, (im as Image).get_height() * 3)
	var per := 3
	var colw := 0
	for im0 in sheet:
		colw = maxi(colw, (im0 as Image).get_width() * 3 + 12)
	sw = colw * per + 8
	var out := Image.create(sw, (sh + 12) * Sk.CLASSES.size() + 8, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.07, 0.07, 0.16))
	for si in sheet.size():
		var big: Image = (sheet[si] as Image).duplicate()
		big.convert(Image.FORMAT_RGBA8)
		big.resize(big.get_width() * 3, big.get_height() * 3, Image.INTERPOLATE_NEAREST)
		out.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(4 + (si % per) * colw, 4 + (si / per) * (sh + 12) + sh - big.get_height()))
	out.save_png(g._real_save_dir().path_join("shots").path_join("ships.png"))
	var ok0: bool = bad.is_empty()
	rows.append("%s%d classes x 3 seeds grown whole%s" % ["" if ok0 else "(!) ", Sk.CLASSES.size(), "" if ok0 else ": " + "; ".join(bad)])
	ok = ok and ok0
	# ---- armour: one hit on a Corvette carves less than the same hit on a Cutter
	var cu = Sk.make(77, "cutter")
	var cv = Sk.make(77, "corvette")
	cu.rebuild()
	cv.rebuild()
	cu.pos = Vector2.ZERO
	cv.pos = Vector2.ZERO
	var cu0: int = cu.cells.size() - cu.cells.count(0)
	var cv0: int = cv.cells.size() - cv.cells.count(0)
	# (amidships, a few cells under the deck: inside the hull on every class)
	var cu_at: Vector2i = cu.seat_cells[0]
	var cv_at: Vector2i = cv.seat_cells[0]
	cu.damage(cu.cell_world(cu_at.x - 14, cu_at.y + 5), 7.0)
	cv.damage(cv.cell_world(cv_at.x - 14, cv_at.y + 5), 7.0)
	var cu_lost: int = cu0 - (cu.cells.size() - cu.cells.count(0))
	var cv_lost: int = cv0 - (cv.cells.size() - cv.cells.count(0))
	var ok1: bool = cu_lost > 0 and cv_lost < cu_lost
	rows.append("%sa hit carves %d cells of a Cutter, %d of a Corvette" % ["" if ok1 else "(!) ", cu_lost, cv_lost])
	ok = ok and ok1
	# ---- the first forged at the Wisp Forge: a whole Wisp Skiff, no keel to build out
	var sf_rec: Dictionary = {}
	var cut_rec: Dictionary = {}
	for sr in g.recipes:
		if sr["id"] == "skiff":
			sf_rec = sr
		elif sr["id"] == "ship_cutter":
			cut_rec = sr
	for ik2 in ["skiff", "ships", "ship_class", "ship", "boarded"]:
		g.items.erase(ik2)
	g.items["drive"] = true
	g.learn("skiff")
	for sk_k in sf_rec.get("cost", {}):
		g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
	var keep_sk = g.skiff
	g.skiff = null
	var forged: bool = g.craft(sf_rec)
	var ok2: bool = forged and g.ships().has("skiff") and g.ship_class() == "skiff" and not g.items.has("ship") and g.recipe_done(sf_rec)
	rows.append("%sthe Wisp Skiff forged %s: ships %s, flying %s" % ["" if ok2 else "(!) ", forged, g.ships().keys(), g.ship_class()])
	ok = ok and ok2
	# ---- out on clear ground beside you (for the rest, and the pocket after)
	var hs := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) + 40, 240, 120, 6)
	var ha: float = (float(hs.x) + 160.0) / float(Defs.NS) * TAU
	_go(Vector2(cos(ha), sin(ha)) * (g.gpu.surf_at(ha).x + 12.0))
	await _frames(60)
	g.call_skiff()
	await _frames(120)
	var sk = g.skiff
	var cap0: int = g.hold_cap()
	# ---- another class: locked until learned, then forged and flown (the one out swapped where it stood)
	var unl0: bool = g.recipe_unlocked(cut_rec)
	g.learn("ship_cutter")
	for ck in cut_rec.get("cost", {}):
		g.player.inv[int(ck)] += int(cut_rec["cost"][ck])
	var at0: Vector2 = sk.pos
	var forged2: bool = g.craft(cut_rec)
	var sk2 = g.skiff
	var ok3: bool = unl0 and forged2 and g.ships().size() == 2 and g.ship_class() == "cutter" and sk2 != null and sk2.klass == "cutter" and sk2.pos.distance_to(at0) < 1.0 and g.hold_cap() == 2 and cap0 == 3 and g.recipe_done(cut_rec)
	rows.append("%sthe Cutter learned and forged %s: flying %s (hold %d, the Skiff's %d)" % ["" if ok3 else "(!) ", forged2, g.ship_class(), g.hold_cap(), cap0])
	ok = ok and ok3
	# ---- guns: a Hauler fires none, a Corvette two bolts at once, a Cutter one
	var guns := []
	for gk in ["cutter", "hauler", "corvette"]:
		var gs = Sk.make(5, gk)
		gs.pos = g.player.pos
		g.space._cannon_cd = 0
		g.player.mana = 200.0
		g.player.input.aim = gs.pos + Vector2(80, 0)
		var n0: int = g.space.shots.size()
		g.space._fire_cannon(g.player, gs)
		guns.append(g.space.shots.size() - n0)
	g.space.shots.clear()
	g.space._cannon_cd = 0
	var ok4: bool = guns == [1, 0, 2]
	rows.append("%sbolts a shot: Cutter %d, Hauler %d, Corvette %d" % ["" if ok4 else "(!) ", guns[0], guns[1], guns[2]])
	ok = ok and ok4
	# ---- the satchel's Ships; swapped back to the Skiff; another look; no swap aboard
	g.ui.satchel_open = true
	g.ui._inv_key = ""
	await _frames(5)
	var listed := false
	for sec in g.ui.satchel.get_children():
		if sec is Label and String(sec.text).begins_with("Ships"):
			listed = true
	g.ui.satchel_open = false
	g.ui._inv_key = ""
	var back: bool = g.switch_ship("skiff", true) and g.ship_class() == "skiff" and g.skiff.klass == "skiff"
	var seed0: int = int(g.ships()["cutter"])
	var looked: bool = g.reshape_ship("cutter") and int(g.ships()["cutter"]) != seed0 and g.ship_class() == "skiff"
	await _frames(30)
	sk = g.skiff
	g.player.pos = sk.pos
	g._skiff_interact(g.player)
	await _frames(5)
	var aboard: bool = g.player.aboard == sk
	var no_swap: bool = not g.switch_ship("cutter", true) and g.ship_class() == "skiff"
	var boarded: bool = g.items.has("boarded")
	var qst: Dictionary = {}
	for qs0 in g.quest._first_chapter():
		if String(qs0["id"]) == "hull":
			qst = qs0
	# B aboard: no ship builder any more
	var bk := InputEventKey.new()
	bk.keycode = KEY_B
	bk.pressed = true
	g._unhandled_input(bk)
	await _frames(3)
	var no_yard: bool = not g.shipyard.active and g.state == "play"
	var hud_hold: bool = String(g.ui.info.text).find("hold 0/3") >= 0 or String(g.ui.info.text).find("hold %d/3" % g.cargo_count()) >= 0
	var ok5: bool = listed and back and looked and aboard and no_swap and boarded and String(qst.get("title", "")).begins_with("Call your ship") and no_yard and hud_hold
	rows.append("%sin the satchel %s, back to the Skiff %s, another look %s, aboard %s, no swap aboard %s, the quest's step %s (boarded %s), B opens no builder %s, the HUD's hold %s" % ["" if ok5 else "(!) ", listed, back, looked, aboard, no_swap, qst.get("title", "?"), boarded, no_yard, hud_hold])
	ok = ok and ok5
	# ---- a journey from before: its skiff kept as a Wisp Skiff, a hull built in the old builder let go
	var it0: Dictionary = g.items.duplicate(true)
	g.items.erase("ships")
	g.items.erase("ship_class")
	g.items["skiff"] = 31337
	var old_hull: Dictionary = Sk.make(31337).save_cells()
	old_hull["designed"] = true
	old_hull.erase("klass")
	g.items["ship"] = old_hull
	g._migrate_ships()
	var mig: bool = g.ships() == {"skiff": 31337} and g.ship_class() == "skiff" and not g.items.has("ship")
	var refused: bool = not Sk.make(31337).load_cells(old_hull)
	g.items = it0
	var ok6: bool = mig and refused
	rows.append("%san old journey's ship kept as a Skiff %s, its built hull let go %s" % ["" if ok6 else "(!) ", mig, refused])
	ok = ok and ok6
	print("[ships] " + "\n[ships] ".join(rows))
	_ok("ships as classes: grown whole, stats per class, forged, learned, swapped, another look, no builder, old journeys kept", ok, "; ".join(rows))
	await _test_pocket()
	# (put things back: later checks fly the skiff as it was)
	g.player.deck = false
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	for ik3 in ["skiff", "ships", "ship_class", "ship", "boarded", "drive"]:
		if keep_items.has(ik3):
			g.items[ik3] = keep_items[ik3]
		else:
			g.items.erase(ik3)
	if keep_sk != null:
		for hr2 in keep_sk.riders.size():
			keep_sk.riders[hr2] = null
		g.skiff = keep_sk
		g.call_skiff()
	else:
		g.skiff = null
		if g.items.has("skiff"):
			g.call_skiff()
	await _frames(30)

func _test_pocket() -> void:
	var rows := []
	var ok := true
	var Isle = load("res://scripts/pocket_isle.gd")
	var pk = g.pocket
	var sk = g.skiff
	g.player.dead = false
	g.test_god = true
	if g.build_on:
		g._toggle_build()
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	await _frames(10)
	var keep_known: Array = g.player.known.duplicate()
	var keep_sel: int = g.player.sel
	g.items.erase("pocket_seen")
	g.player.known.erase("recall")
	# (a fresh isle: one kept from a run before would already hold what this one builds)
	if FileAccess.file_exists(pk._path()):
		DirAccess.remove_absolute(pk._path())
	pk.isle = null
	# ---- in from inside the ship (user, 25 Nov: no door on the hull): aboard and parked, G goes below
	for wl in 120:
		if g.shipyard.parked():
			break
		await _frames(1)
	var reach: bool = g.shipyard.parked()
	if g.player.aboard == null and sk.board(g.player):
		g.player.aboard = sk
	# (seated aboard on a planet, a draught heals you and its cooldown runs: user, 27 Nov, "i used a healing draught
	# while inside the whisp skiff seat and i dont think it healed me and then it stayed on 10 seconds for cooldown")
	var dr_hp0: float = g.player.max_hp - 30.0
	g.player.hp = dr_hp0
	g.player.heal_left = 30.0
	g.player.potion_cd = 600
	await _frames(30)
	var dr_ok: bool = g.player.aboard != null and g.player.hp > dr_hp0 + 5.0 and g.player.potion_cd < 600 - 20
	rows.append("%sa draught seated aboard heals you (health %.0f -> %.0f) and its wait runs (600 -> %d)" % ["" if dr_ok else "(!) ", dr_hp0, g.player.hp, g.player.potion_cd])
	ok = ok and dr_ok
	g.player.hp = g.player.max_hp
	g.player.heal_left = 0.0
	g.player.potion_cd = 0
	var door: Vector2 = sk.pos
	var went: bool = g.go_below(g.player) and pk.active
	if not pk.active:
		pk.enter(g.player, "ship")      # (so the checks below still run, and this one fails)
	var in1: bool = went
	await _frames(60)
	if pk.isle == null:
		pk._ensure()                    # (not in: the checks below still run, and fail, without stopping)
	var on_isle: bool = g.player.on_ground
	var learned: bool = g.player.known.has("recall") and g.items.has("pocket_seen")
	_shot("pocket_isle.png")
	var ok0: bool = reach and in1 and on_isle and learned and not g.view_rect.visible
	rows.append("%sin from aboard by G %s (parked %s), standing on the isle %s, Wisp Recall learned %s" % ["" if ok0 else "(!) ", in1, reach, on_isle, learned])
	ok = ok and ok0
	# ---- its look (user, 25 Nov: "it looks a little thrown together still"; chose the isle itself, the arch and
	# heart, a home spot): a paved terrace, a flagstone path, the carved arch's wisp keystone, the floating shard,
	# strata (stone and deepstone), vines and hanging roots, flowers; nothing of the isle's own floats
	var il = pk.isle
	var cxi: int = Isle.W / 2
	var paved := 0
	var path_st := 0
	for ti in range(cxi + Isle.TER_A, cxi + Isle.TER_B):
		for tj in range(Isle.SURF - 14, Isle.SURF + 14):
			if il.cells[tj * Isle.W + ti] == Defs.MASONRY:
				paved += 1
				break
	for pi in range(cxi + Isle.ARCH_DX + 13, cxi - 9):
		for pj in range(Isle.SURF - 8, Isle.SURF + 8):
			if il.cells[pj * Isle.W + pi] == Defs.MASONRY:
				path_st += 1
				break
	var nkey := 0
	var nroot := 0
	var nvine := 0
	var nflow := 0
	var ndeep := 0
	for kk0 in Isle.W * Isle.H:
		var bgm: int = il.bg[kk0]
		if bgm == Defs.WISPBAR and il.guard[kk0] == 1:
			nkey += 1
		elif bgm == Defs.ROOT and il.cells[kk0] == 0:
			nroot += 1
		elif bgm == Defs.LEAF and kk0 / Isle.W > Isle.SURF + 2:
			nvine += 1
		elif bgm == Defs.SUNSTONE or bgm == Defs.FROST or bgm == Defs.CAP:
			nflow += 1
		if il.cells[kk0] == Defs.DEEPSTONE:
			ndeep += 1
	var oklook: bool = paved == Isle.TER_B - Isle.TER_A and path_st >= 12 and nkey >= 3 and nroot >= 20 and nvine >= 20 and nflow >= 2 and ndeep > 500
	rows.append("%sits look: the terrace paved %d of %d, %d flagstones on the path, the keystone %d, %d root cells hanging, %d vine cells, %d flower cells, %d deepstone" % ["" if oklook else "(!) ", paved, Isle.TER_B - Isle.TER_A, path_st, nkey, nroot, nvine, nflow, ndeep])
	ok = ok and oklook
	# (an isle from before its look: dressed again on load, what you built kept)
	var old_i = Isle.new()
	old_i.make()
	var ob_k: int = (Isle.SURF - 20) * Isle.W + cxi - 100
	old_i.place(cxi - 100 + 0, Isle.SURF - 20, Defs.PLANK)
	for kg in Isle.W * Isle.H:
		if old_i.cells[kg] == Defs.DEEPSTONE:
			old_i.cells[kg] = Defs.STONE
	var od: Dictionary = old_i.save_isle()
	od.erase("art")
	var re_i = Isle.new()
	var reloaded: bool = re_i.load_isle(od)
	var re_deep := 0
	for kg2 in Isle.W * Isle.H:
		if re_i.cells[kg2] == Defs.DEEPSTONE:
			re_deep += 1
	var restyled: bool = reloaded and re_deep > 500 and re_i.cells[ob_k] == Defs.PLANK and re_i.made[ob_k] == 1
	rows.append("%san older isle dressed again on load %s (%d deepstone), your block kept %s" % ["" if restyled else "(!) ", reloaded, re_deep, re_i.cells[ob_k] == Defs.PLANK])
	ok = ok and restyled
	# ---- walk
	var bx0: float = pk.b.x
	g.test_move = 1
	await _frames(50)
	g.test_move = 0
	await _frames(20)
	var walked: float = pk.b.x - bx0
	var ok1: bool = walked > 20.0 and g.player.on_ground
	rows.append("%swalked %.0f cells along the isle" % ["" if ok1 else "(!) ", walked])
	ok = ok and ok1
	# ---- build: a plank block, a back wall, then the block taken out again
	var isle = pk.isle
	var bi := int(floor(pk.b.x)) + 8
	var bj := int(floor(isle.top_at(bi, isle.level))) - 6
	var bk: int = bj * Isle.W + bi
	g._toggle_build()
	g.build_thick = 1
	_pick_piece("Planks")
	var pl0: int = g.player.inv[Defs.PLANK]
	g.player.inv[Defs.PLANK] += 20
	pl0 = g.player.inv[Defs.PLANK]
	g.test_cast = true
	for k in 6:
		g.test_aim = isle.cell_world(bi, bj)
		await _frames(1)
	g.test_cast = false
	await _frames(3)
	var built: bool = isle.cells[bk] == Defs.PLANK and g.player.inv[Defs.PLANK] < pl0
	_pick_piece("Plank Wall")
	g.test_cast = true
	for k1 in 6:
		g.test_aim = isle.cell_world(bi + 3, bj)
		await _frames(1)
	g.test_cast = false
	await _frames(3)
	var walled: bool = isle.bg[bj * Isle.W + bi + 3] == Defs.PLANK
	_pick_piece("Remove Blocks")
	g.test_cast = true
	for k2 in 6:
		g.test_aim = isle.cell_world(bi, bj)
		await _frames(1)
	g.test_cast = false
	await _frames(3)
	var taken: bool = isle.cells[bk] == 0
	# (and a block again, kept to check the save)
	_pick_piece("Planks")
	g.test_cast = true
	for k3 in 6:
		g.test_aim = isle.cell_world(bi, bj)
		await _frames(1)
	g.test_cast = false
	await _frames(3)
	# (the heart and the arch can't be taken)
	var hx: int = Isle.W / 2 + Isle.HEART_DX
	var hy := int(floor(isle.top_at(hx, 0))) - 4
	var guarded: bool = not isle.can_take(hy * Isle.W + hx) and isle.remove(hx, hy) == 0
	g._toggle_build()
	var ok2: bool = built and walled and taken and isle.cells[bk] == Defs.PLANK and guarded
	rows.append("%sbuilt in the pocket: a block %s, a back wall %s, taken out %s, laid again %s; the heart kept %s" % ["" if ok2 else "(!) ", built, walled, taken, isle.cells[bk] == Defs.PLANK, guarded])
	ok = ok and ok2
	# ---- the same tools as outside (user, 25 Nov): Unmake takes a block away, a Room plan rises on the isle
	var pk_known0: Array = g.player.known.duplicate()
	if not g.player.known.has("unmake"):
		g.player.known.insert(maxi(0, g.player.known.find("conjure")) + 1, "unmake")
	var ui0 := bi + 10
	var uj := int(floor(isle.top_at(ui0, isle.level))) - 8
	while isle.at(ui0, uj) != 0 and uj > 0:
		uj -= 1
	isle.place(ui0, uj, Defs.PLANK)
	g.player.sel = g.player.known.find("unmake")
	g.unmake_shape = 2
	g.unmake_layer = 0
	g.unmake_thick = 1
	var un_before: int = isle.cells[uj * Isle.W + ui0]
	g.test_cast = true
	var un_live := false
	var un_cc := false
	for k4 in 6:
		g.test_aim = isle.cell_world(ui0, uj)
		await _frames(1)
		un_live = un_live or g.hand_live
		un_cc = un_cc or g.cabin_cast
	g.test_cast = false
	await _frames(3)
	var unmade: bool = un_before == Defs.PLANK and isle.cells[uj * Isle.W + ui0] == 0
	g.player.sel = g.player.known.find("conjure")
	for pm in Defs.NM:
		if Defs.KIND[pm] == Defs.K_SOLID:
			g.player.inv[pm] += 400
	g.player.mana = g.player.max_mana
	g.build_w = 24
	g.build_floors = 1
	g.hold_plan("room")
	# (a clear stretch of the isle for it: nothing built, not the heart or the arch)
	var rx: int = Isle.W / 2 + 40
	for cand in [Isle.W / 2 + 30, Isle.W / 2 + 40, Isle.W / 2 + 50, Isle.W / 2 - 60, Isle.W / 2 + 60]:
		var clear := true
		for ii2 in range(cand - 17, cand + 18):
			var tj := int(floor(isle.top_at(ii2, 0)))
			for jj2 in range(tj - 50, tj):
				var kk: int = jj2 * Isle.W + ii2
				if isle.made[kk] == 1 or isle.guard[kk] == 1:
					clear = false
		if clear:
			rx = cand
			break
	var count_room := func() -> int:
		var nr := 0
		for jj in range(int(isle.top_at(rx, 0)) - 60, int(isle.top_at(rx, 0)) + 1):
			for ii in range(rx - 18, rx + 19):
				if isle.made[jj * Isle.W + ii] == 1:
					nr += 1
		return nr
	var room0: int = count_room.call()
	g.test_aim = isle.cell_world(rx, int(floor(isle.top_at(rx, 0))) - 3)
	await _frames(4)
	var rfit: bool = g.build_prev.get("ok", false)
	var rwhy: String = g.build_why + " " + String(g.build_prev.get("text", ""))
	g.build_click = true
	await _frames(3)
	var rising: bool = not g.raising.is_empty()
	await _frames(150)
	var room1: int = count_room.call()
	g.test_aim = Vector2.ZERO
	g.hand_item = {}
	g.build_w = 40
	_shot("pocket_room.png")
	g.player.known = pk_known0
	var ok2b: bool = unmade and rfit and rising and room1 > room0 + 100 and g.raising.is_empty()
	rows.append("%sthe same tools as outside: Unmake took a block %s; a Room plan fits %s (%s), rose %s, %d -> %d cells" % ["" if ok2b else "(!) ", unmade, rfit, rwhy, rising, room0, room1])
	ok = ok and ok2b
	# ---- the Isle Heart grows the isle (asked, then F again)
	var lv0: int = isle.level
	var cost: Dictionary = pk.expand_cost(lv0 + 1)
	for ck in cost:
		g.player.inv[int(ck)] += int(cost[ck])
	g.player.mana = g.player.max_mana
	var edge: int = Isle.W / 2 + Isle.LEVELS[lv0] + 20
	var had_edge: bool = isle.cells[int(floor(isle.top_at(edge, lv0 + 1)) + 3) * Isle.W + edge] != 0
	pk.b = Vector2(float(hx) + 0.5, isle.top_at(hx, isle.level) - 9.0)
	await _frames(4)
	var near_h: String = pk.near
	g._interact()
	g._interact()
	await _frames(20)
	var grew: bool = isle.level == lv0 + 1 and not had_edge and isle.cells[int(floor(isle.top_at(edge, isle.level)) + 3) * Isle.W + edge] != 0
	_shot("pocket_grown.png")
	var ok3: bool = near_h == "heart" and grew
	rows.append("%sthe Isle Heart (near: %s) grew the isle %d -> %d, ground now %d cells out %s" % ["" if ok3 else "(!) ", near_h, lv0, isle.level, Isle.LEVELS[isle.level], grew])
	ok = ok and ok3
	await _test_pocket_build()
	# ---- out by the arch: back up into the ship, aboard, where you came in
	var ax: int = Isle.W / 2 + Isle.ARCH_DX
	pk.b = Vector2(float(ax) + 0.5, isle.top_at(ax, 0) - 9.0)
	await _frames(4)
	var near_a: String = pk.near
	g._interact()
	await _frames(30)
	var out1: bool = not pk.active and g.player.aboard == sk and g.view_rect.visible
	rows.append("%sout by the arch (near: %s) %s, back aboard %s" % ["" if out1 else "(!) ", near_a, out1, g.player.aboard == sk])
	ok = ok and out1
	if g.player.aboard != null:
		g._skiff_interact(g.player)     # (stepped off for what follows)
		await _frames(10)
	# ---- Wisp Recall from out here, a way off: hurt breaks it; cast again, into the pocket
	var away: Vector2 = g.player.pos + g.basis_r(atan2(g.player.pos.y, g.player.pos.x)) * 120.0
	_go(away + g.player.pos.normalized() * 6.0)
	await _frames(40)
	var at_cast: Vector2 = g.player.pos
	g.player.sel = g.player.known.find("recall")
	g.player.spell_cd.clear()
	g.player.mana = g.player.max_mana
	g.test_god = false
	g.test_cast = true
	await _frames(2)
	g.test_cast = false
	await _frames(5)
	var chan: bool = g.player.recall_t > 0
	g.player.iframes = 0
	g.hurt(g.player, 1.0, Vector2.ZERO, true)
	g.test_god = true
	await _frames(70)
	var broke: bool = chan and not pk.active and g.player.recall_t == 0
	g.player.spell_cd.clear()
	g.player.cast_cd = 0
	g.player.mana = g.player.max_mana
	g.test_cast = true
	await _frames(2)
	g.test_cast = false
	await _frames(70)
	var in2: bool = pk.active
	var ok4: bool = broke and in2
	rows.append("%sWisp Recall: channelled %s, broken by a blow %s; cast again, in the pocket %s" % ["" if ok4 else "(!) ", chan, broke, in2])
	ok = ok and ok4
	# ---- out by the ship (G at the arch): at its door, not where it was cast
	pk.b = Vector2(float(ax) + 0.5, isle.top_at(ax, 0) - 9.0)
	await _frames(4)
	var by_ship: bool = pk.leave_by_ship(g.player)
	await _frames(20)
	var out2: bool = by_ship and not pk.active and g.player.aboard == sk and g.player.pos.distance_to(at_cast) > 60.0
	rows.append("%sout by the ship %s: aboard %s, %.0f from where Recall was cast" % ["" if out2 else "(!) ", by_ship, g.player.aboard == sk, g.player.pos.distance_to(at_cast)])
	ok = ok and out2
	if g.player.aboard != null:
		g._skiff_interact(g.player)
		await _frames(10)
	# ---- kept: the isle read back from its file as it was left
	var lvk: int = isle.level
	pk.isle = null
	pk._ensure()
	var kept: bool = pk.isle.level == lvk and pk.isle.cells[bk] == Defs.PLANK and pk.isle.bg[bj * Isle.W + bi + 3] == Defs.PLANK
	rows.append("%skept: level %d, the block and the wall %s" % ["" if kept else "(!) ", pk.isle.level, kept])
	ok = ok and kept
	# ---- the quest's steps for it
	var Q = load("res://scripts/quest.gd")
	var qs := []
	for st in g.quest._first_chapter():
		qs.append(String(st["id"]))
	var qi: int = qs.find("skiff")
	var ok5: bool = qi >= 0 and qi + 2 < qs.size() and qs[qi + 1] == "hull" and qs[qi + 2] == "pocket"
	rows.append("%sthe quest walks you through it: %s" % ["" if ok5 else "(!) ", ", ".join(qs.slice(maxi(qi, 0), qi + 3))])
	ok = ok and ok5
	# (put the spells back as they were: later checks cast with the one chosen, and Wisp Recall chosen out in
	# space would carry the next check into the pocket)
	g.player.known = keep_known
	g.player.sel = clampi(keep_sel, 0, keep_known.size() - 1)
	g.player.recall_t = 0
	if pk.active:
		pk.leave(g.player)
	print("[pocket] " + "\n[pocket] ".join(rows))
	_ok("the ship's pocket dimension: in from aboard (G) and by Wisp Recall (a blow breaks it), walked, built on with the same tools as outside, grown, out by the arch and by the ship back aboard, kept", ok, "; ".join(rows))

## (user, 23 Nov: a cargo hold "for big things only": trade goods bought and sold at outposts, in the hold)
func _test_cargo() -> void:
	var rows := []
	var ok := true
	var G = load("res://scripts/galaxy.gd")
	var O = load("res://scripts/outpost.gd")
	# ---- every outpost sells three goods and wants three others; somewhere a run pays
	var op0 = O.make_outpost(G.outpost_seed(0))
	var tr0 = op0.trader()
	var t0: Dictionary = Defs.trade_of(G.outpost_seed(0))
	var best := 0
	var best_txt := ""
	for r in range(1, 12):
		var tr := Defs.trade_of(G.outpost_seed(r))
		for gd in t0["sells"]:
			var gain: int = int(tr["pays"][gd]) - int(t0["sells"][gd])
			if gain > best:
				best = gain
				best_txt = "%s bought at %s for %d sells at %s for %d" % [Defs.GOODS[gd]["name"], G.outpost_name(0), t0["sells"][gd], G.outpost_name(r), tr["pays"][gd]]
	var ok1: bool = (t0["sells"] as Dictionary).size() == 3 and (t0["wants"] as Dictionary).size() == 3 and best > 10
	rows.append("%s%s sells %s, wants %s; the best run from it: %s (%d a crate)" % ["" if ok1 else "(!) ", G.outpost_name(0), (t0["sells"] as Dictionary).keys(), (t0["wants"] as Dictionary).keys(), best_txt, best])
	ok = ok and ok1
	# ---- the hold: as many crates as the room the hull closes in (the skiff as forged: a few)
	if not g.items.has("skiff"):
		g.items["skiff"] = 4242
	if g.skiff == null:
		g.call_skiff()
		await _frames(30)
	var cap: int = g.hold_cap()
	var cargo0 = g.items.get("cargo", {})
	g.items["cargo"] = {}
	var coins0 := int(g.items.get("coins", 0))
	g.items["coins"] = 5000
	var sd: Dictionary = g.towns.shop_def(tr0)
	var gi := -1
	for i in (sd["sell"] as Array).size():
		if (sd["sell"][i] as Dictionary).has("good"):
			gi = i
			break
	var bought := 0
	for k in cap + 3:
		if g.towns.buy(tr0, gi):
			bought += 1
	var full_refused: bool = bought == cap and g.cargo_count() == cap
	var gd0: String = sd["sell"][gi]["good"]
	var ok2: bool = gi >= 0 and cap >= 2 and full_refused
	rows.append("%sthe %s's hold takes %d crates: %d bought, then it was full %s" % ["" if ok2 else "(!) ", g.skiff.klass, cap, bought, full_refused])
	ok = ok and ok2
	# ---- the crates stand in the hold (drawn there), away from the helm (a picture)
	var cx_sk = g.skiff
	var slots: Array = cx_sk.crate_slots(g.cargo_count())
	var off_seat := true
	for sl in slots:
		var slv: Vector2i = sl
		for jj in cx_sk.CRATE_H:
			for ii in cx_sk.CRATE_W:
				if cx_sk.in_seat(slv.x + ii, slv.y + jj):
					off_seat = false
	# (and on ships of every class and shape: each finds a place for its crates)
	var Skf = load("res://scripts/skiff.gd")
	var shapes_ok := 0
	var shapes_txt := []
	for sq in 12:
		var sk_q = Skf.make(1000 + sq * 7919, Skf.CLASSES.keys()[sq % Skf.CLASSES.size()])
		sk_q.rebuild()
		var nq: int = sk_q.hold_cap()
		var got_q: int = sk_q.crate_slots(nq).size()
		shapes_txt.append("%d/%d" % [got_q, nq])
		if got_q >= mini(nq, 2):
			shapes_ok += 1
	var ok2b: bool = slots.size() >= mini(cap, 2) and off_seat and shapes_ok == 12
	rows.append("%s%d of %d crates stand in the hold, none in a seat %s; on 12 other ships %s" % ["" if ok2b else "(!) ", slots.size(), g.cargo_count(), off_seat, " ".join(shapes_txt)])
	ok = ok and ok2b
	if not g.space.active:
		var cpos: Vector2 = g.player.pos
		g.player.pos = cx_sk.pos + (cx_sk.pos.normalized() * 2.0)
		g.cam_c = cx_sk.pos
		await _frames(20)
		_shot("cargo_hold.png")
		g.player.pos = cpos
	# ---- sold at another system's outpost, for what it pays
	var rb := 1
	var bp := -1
	for r2 in range(1, 12):
		var p2: int = int(Defs.trade_of(G.outpost_seed(r2))["pays"][gd0])
		if p2 > bp:
			bp = p2
			rb = r2
	var tr1 = O.make_outpost(G.outpost_seed(rb)).trader()
	var c1 := int(g.items.get("coins", 0))
	var sold := 0
	while g.towns.sell_good(tr1, gd0):
		sold += 1
	var earned: int = int(g.items.get("coins", 0)) - c1
	var ok3: bool = sold == cap and g.cargo_count() == 0 and earned == sold * bp
	rows.append("%ssold %d crates of %s at %s for %d coins (%d each)" % ["" if ok3 else "(!) ", sold, Defs.GOODS[gd0]["name"], G.outpost_name(rb), earned, bp])
	ok = ok and ok3
	# ---- the shop panel lists them (a picture)
	g.items["cargo"] = {gd0: 2}
	g.towns.shop_of = tr1
	g.state = "shop"
	g.ui.show_shop(tr1)
	await _frames(15)
	_shot("cargo_shop.png")
	g.towns.close_shop()
	await _frames(5)
	g.items["cargo"] = cargo0
	g.items["coins"] = coins0
	print("[cargo] " + "\n[cargo] ".join(rows))
	_ok("the cargo hold: trade goods bought and sold at outposts, as many as the ship's class carries", ok, "; ".join(rows))

## Busy scenes out in space (user, 23 Nov: the performance pass; "make sure it runs on lower end pc's with decent
## framerates"): a fight in a derelict station, a busy outpost's deck, pirates attacking among asteroids, the
## Starsail streaming sectors in. Each 300 frames with vsync off; prints each part's time ("space: ..."), the
## screen's drawing on the GPU and the planet's simulation. Passes under 16.7 ms on average and 25 at the 95th
## percentile in each.
## Space's own life and its anomalies (voidlife.gd, monolith.gd; user, 23 Nov): the galaxy grows them;
## mantas glide and scatter; eels bite the hull and die to the cannon, leaving essence you gather; jellies
## sting (the shield takes it); a well pulls, spits you out of its heart, flings you on, holds you at its
## edge with the Void Harness, and gives its crystals; a monolith's glyphs wake only root first (the cannon,
## your staff) and its cache tells of a rift; a rift carries you to its twin; the map; the recipes.
## Pictures: void_mantas.png, void_eels.png, void_jellies.png, void_well.png, void_monolith.png,
## void_monolith_open.png, void_rift.png, void_map.png.
func _test_voidlife() -> void:
	var rows := []
	var ok := true
	var G = load("res://scripts/galaxy.gd")
	var vl = g.space.vl
	# ---- 1. the galaxy grows them, and every rift's ends are where its pair says
	var cnt := {}
	for sy in 40:
		for sx in 40:
			for c in G.sector_content(Vector2i(sx - 500, sy + 220)):
				cnt[c["type"]] = int(cnt.get(c["type"], 0)) + 1
	var rp_n := 0
	var rp_ok := true
	var rp_first := -1
	for r in 30:
		var rp: Dictionary = G.rift_pair(r)
		if rp.is_empty():
			continue
		rp_n += 1
		if rp_first < 0 and not G._near_planet_r(rp["a"][0], rp["a"][1], 44000.0) and not G._near_planet_r(rp["b"][0], rp["b"][1], 44000.0):
			rp_first = r
		for e in 2:
			var eg: PackedFloat64Array = rp["a"] if e == 0 else rp["b"]
			var found := false
			for c2 in G.sector_content(G.sector_of(eg[0], eg[1])):
				if c2["type"] == "rift" and int(c2["pair"]) == r and int(c2["end"]) == e:
					found = true
			rp_ok = rp_ok and found
	var have_recipes := 0
	for rc in g.recipes:
		if rc["id"] == "harness" or rc["id"] == "voidmantle":
			have_recipes += 1
	var ok1: bool = int(cnt.get("well", 0)) > 0 and int(cnt.get("monolith", 0)) > 0 and int(cnt.get("eels", 0)) > 0 and rp_n >= 8 and rp_ok and have_recipes == 2 and Defs.NAMES[Defs.VOIDESS] == "Void Essence"
	rows.append("%sin 1600 deep sectors: %s; %d of 30 systems have a rift pair, every end in its sector %s; both recipes %s" % ["" if ok1 else "(!) ", str(cnt), rp_n, rp_ok, have_recipes == 2])
	ok = ok and ok1
	# ---- up in the skiff, out to deep space
	g.player.dead = false
	var god0: bool = g.test_god
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var up0: Vector2 = sk.pos.normalized()
	sk.pos = up0 * (Defs.R_SPACE - 11.0)
	sk.vel = up0 * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	g.test_cast = false
	var keep_items := {}
	for ik in ["cannon", "shield", "harness", "voidmantle"]:
		keep_items[ik] = g.items.get(ik, null)
	var mana0: float = g.max_mana
	var hl: Vector2 = g.space.home_at()
	var spot: Vector2 = hl + Vector2(130000.0, 0.0)
	for t in 24:
		var dir := Vector2.from_angle(float(t) / 24.0 * TAU)
		var gp: PackedFloat64Array = g.space.galaxy_of(hl + dir * 130000.0)
		if not G._near_planet_r(gp[0], gp[1], 70000.0):
			spot = hl + dir * 130000.0
			break
	sk.pos = spot
	sk.vel = Vector2.ZERO
	await _frames(40)
	sk = g.skiff
	# ---- 2. void mantas: a herd glides; hurt one and it scatters; one killed leaves essence, gathered
	var gk: String = vl.add_test("mantas", sk.pos + Vector2(150.0, -40.0), 5, 11)
	await _frames(90)
	_shot("void_mantas.png")
	var herd := []
	for b in vl.beasts:
		if b.gk == gk:
			herd.append(b)
	var hit_at: Vector2 = (herd[0].pos as Vector2) + Vector2(-30.0, 0.0)
	var d0 := 0.0
	for b2 in herd:
		d0 += (b2.pos as Vector2).distance_to(hit_at)
	vl.hurt_beast(herd[0], 5.0, hit_at)
	await _frames(120)
	var d1 := 0.0
	for b3 in herd:
		d1 += (b3.pos as Vector2).distance_to(hit_at)
	var scared: int = int(vl.groups[gk]["scared"])
	var es0: int = g.player.inv[Defs.VOIDESS]
	var motes0: int = vl.motes.size()
	var kill_at: Vector2 = herd[1].pos
	vl.hurt_beast(herd[1], 999.0, kill_at)
	var dropped: int = vl.motes.size() - motes0
	sk.pos = kill_at + Vector2(0.0, 30.0)
	sk.vel = Vector2.ZERO
	for k2 in 200:
		sk.vel = Vector2.ZERO
		await _frames(1)
		if g.player.inv[Defs.VOIDESS] - es0 >= dropped:
			break
	var gathered: int = g.player.inv[Defs.VOIDESS] - es0
	var ok2: bool = scared > 0 and d1 > d0 + 300.0 and dropped >= 6 and gathered >= dropped
	rows.append("%smantas: the herd fled the blow (%.0f -> %.0f from it, scared %d); one killed dropped %d motes, %d gathered" % ["" if ok2 else "(!) ", d0, d1, scared, dropped, gathered])
	ok = ok and ok2
	vl.clear_test()
	# ---- 3. lumen eels: they hunt the skiff and bite its hull; the cannon kills them
	vl.allow_hostile = true
	g.items.erase("shield")
	sk.mend(100000)
	var hull0: float = sk.hull_f
	var bites0: int = int(vl.stats["bites"])
	var hh0: int = int(g.space.stats["hull_hits"])
	var gk2: String = vl.add_test("eels", sk.pos + Vector2(450.0, 0.0), 3, 22)
	var snap := false
	for k3 in 900:
		sk.vel = Vector2.ZERO
		await _frames(1)
		if not snap:
			for b4 in vl.beasts:
				if b4.gk == gk2 and (b4.pos as Vector2).distance_to(sk.pos) < 90.0:
					_shot("void_eels.png")
					snap = true
					break
		if int(vl.stats["bites"]) > bites0:
			break
	var bit: int = int(vl.stats["bites"]) - bites0
	var hull1: float = sk.hull_f
	g.items["cannon"] = true
	var kills0: int = int(vl.stats["kills"])
	g.test_cast = true
	for k4 in 900:
		g.player.mana = g.player.max_mana
		var tgt = null
		var td := 1e9
		for b5 in vl.beasts:
			if b5.gk == gk2 and (b5.pos as Vector2).distance_to(sk.pos) < td:
				td = (b5.pos as Vector2).distance_to(sk.pos)
				tgt = b5
		if tgt == null:
			break
		if td > 500.0:
			sk.pos = (tgt.pos as Vector2) + Vector2(-260.0, 0.0)
		sk.vel = Vector2.ZERO
		g.test_aim = (tgt.pos as Vector2) + (tgt.vel as Vector2) * td / 9.0
		await _frames(1)
	g.test_cast = false
	var by_cannon: int = int(vl.stats["kills"]) - kills0
	for b6 in vl.beasts.duplicate():
		if b6.gk == gk2:
			vl.hurt_beast(b6, 999.0, b6.pos)
	var ok3: bool = bit > 0 and (hull1 < hull0 or int(g.space.stats["hull_hits"]) > hh0) and by_cannon >= 1
	rows.append("%seels: bit %d times (hull %.2f -> %.2f, %d hull hits), %d of 3 killed by the cannon" % ["" if ok3 else "(!) ", bit, hull0, hull1, int(g.space.stats["hull_hits"]) - hh0, by_cannon])
	ok = ok and ok3
	vl.clear_test()
	# ---- 4. star jellies: touch one and it stings (the shield takes it)
	g.items["shield"] = true
	g.space.shield = 1.0
	var saves0: int = int(g.space.stats["shield_saves"])
	var st0: int = int(vl.stats["stings"])
	var gk3: String = vl.add_test("jellies", sk.pos + Vector2(0.0, -120.0), 7, 33)
	var jn := 0
	for bj in vl.beasts:
		if bj.gk == gk3:
			bj.pos = sk.pos + Vector2.from_angle(float(jn) * 0.9 + 0.4) * (90.0 + float(jn % 3) * 30.0)
			bj.vel = Vector2.ZERO
			jn += 1
	await _frames(30)
	_shot("void_jellies.png")
	for b7 in vl.beasts:
		if b7.gk == gk3:
			b7.pos = sk.pos
			b7.cd = 0
			break
	await _frames(4)
	var ok4: bool = int(vl.stats["stings"]) > st0 and int(g.space.stats["shield_saves"]) > saves0
	rows.append("%sjellies: stung %d, the shield took it %s" % ["" if ok4 else "(!) ", int(vl.stats["stings"]) - st0, int(g.space.stats["shield_saves"]) > saves0])
	ok = ok and ok4
	vl.clear_test()
	g.items.erase("shield")
	# ---- 5. a gravity well: it pulls, its heart spits you out, skimming it flings you on, the harness holds you
	sk.mend(100000)
	var wp: Vector2 = sk.pos + Vector2(0.0, -700.0)
	var w: Dictionary = vl.add_test_well(wp)
	sk.vel = Vector2.ZERO
	await _frames(90)
	var pulled: float = 700.0 - sk.pos.distance_to(wp)
	var spat0: int = int(vl.stats["spat"])
	var pic := false
	for k5 in 900:
		await _frames(1)
		if not pic and sk.pos.distance_to(wp) < 150.0:
			_shot("void_well.png")
			pic = true
		if int(vl.stats["spat"]) > spat0:
			break
	var spat: bool = int(vl.stats["spat"]) > spat0
	var hull2: float = sk.hull_f
	await _frames(30)
	sk.mend(100000)
	var sl0: int = int(vl.stats["slings"])
	sk.pos = wp + Vector2(-2500.0, 420.0)
	sk.vel = Vector2(34.0, 0.0)
	var v_in := 0.0
	var v_out := 0.0
	for k6 in 400:
		await _frames(1)
		if int(vl.stats["slings"]) > sl0:
			v_out = sk.vel.length()
			break
		v_in = sk.vel.length()
	var flung: bool = int(vl.stats["slings"]) > sl0 and v_out > v_in * 1.2
	g.items["harness"] = true
	var spat1: int = int(vl.stats["spat"])
	sk.pos = wp + Vector2(0.0, 600.0)
	sk.vel = Vector2.ZERO
	var nearest := 1e9
	for k7 in 400:
		await _frames(1)
		nearest = minf(nearest, sk.pos.distance_to(wp))
	var held: bool = nearest > 260.0 * 0.7 and int(vl.stats["spat"]) == spat1
	# (a crystal orbits through where you are)
	sk.vel = Vector2.ZERO
	var cr: Array = w["crystals"][0]
	var es1: int = g.player.inv[Defs.VOIDESS]
	cr[0] = sk.pos.distance_to(wp)
	cr[1] = (sk.pos - wp).angle() - 0.01
	cr[2] = 0
	await _frames(4)
	var crystal: bool = g.player.inv[Defs.VOIDESS] >= es1 + 3
	var ok5: bool = pulled > 20.0 and spat and hull2 < 1.0 and flung and held and crystal
	rows.append("%sa well: pulled in %.0f in 1.5 s, spat out %s (hull %.2f), flung on %s (%.1f -> %.1f), the harness held you %s (nearest %.0f), a crystal taken %s" % ["" if ok5 else "(!) ", pulled, spat, hull2, flung, v_in, v_out, held, nearest, crystal])
	ok = ok and ok5
	vl.clear_test()
	# ---- 6. an ancient monolith: its glyphs wake root first (the cannon, your staff), then its seal and cache
	var Mono = load("res://scripts/monolith.gd")
	var mo = Mono.make_monolith(4242)
	mo.pos = sk.pos + Vector2(110.0, 0.0)
	mo.ang = 0.0
	mo.sect = "test"
	g.space.rocks.append(mo)
	sk.vel = Vector2.ZERO
	await _frames(10)
	_shot("void_monolith.png")
	g.items["cannon"] = true
	var lit_wrong := false
	for k8 in 90:
		g.player.mana = g.player.max_mana
		sk.vel = Vector2.ZERO
		g.test_cast = true
		g.test_aim = mo.glyph_pos(2)
		await _frames(1)
		if int(mo.glyphs[2]["lit"]) > 0:
			lit_wrong = true
	var lit0 := false
	for k9 in 120:
		g.player.mana = g.player.max_mana
		sk.vel = Vector2.ZERO
		g.test_aim = mo.glyph_pos(0)
		await _frames(1)
		if int(mo.glyphs[0]["lit"]) > 0:
			lit0 = true
			break
	g.test_cast = false
	# (on foot: your staff to the next)
	g._skiff_interact(g.player)
	await _frames(4)
	var m = g.player
	var on_foot: bool = m.aboard == null
	m.pos = mo.glyph_pos(1) + Vector2(-34.0, 0.0)
	g.space.vel = Vector2.ZERO
	var lit1 := false
	g.test_dig = true
	for k10 in 120:
		m.mana = m.max_mana
		m.pos = mo.glyph_pos(1) + Vector2(-34.0, 0.0)
		g.space.vel = Vector2.ZERO
		g.test_aim = mo.glyph_pos(1)
		await _frames(1)
		if int(mo.glyphs[1]["lit"]) > 0:
			lit1 = true
			break
	g.test_dig = false
	var res := ""
	for gk4 in range(2, mo.glyphs.size()):
		res = vl.strike(mo, gk4, mo.glyph_pos(gk4))
	await _frames(20)
	_shot("void_monolith_open.png")
	var known0: int = vl.known.size()
	var es2: int = g.player.inv[Defs.VOIDESS]
	m.pos = mo.cache_pos(mo.caches[0]) - mo.axis_y() * 12.0
	g.space.vel = Vector2.ZERO
	var opened := false
	for k11 in 30:
		m.pos = mo.cache_pos(mo.caches[0]) - mo.axis_y() * 12.0
		g.space.vel = Vector2.ZERO
		await _frames(1)
		if g.space.near_cache != null and g.space.wreck_interact(m):
			opened = true
			break
	var ok6: bool = not lit_wrong and lit0 and on_foot and lit1 and res == "open" and mo.opened and opened and g.player.inv[Defs.VOIDESS] > es2 and vl.known.size() > known0
	rows.append("%sa monolith: out of turn stays dark %s, the cannon lit the root %s, your staff the next %s (on foot %s), the last opened it (%s), its cache opened %s (+%d essence), a rift pair revealed %s" % ["" if ok6 else "(!) ", not lit_wrong, lit0, lit1, on_foot, res, opened, g.player.inv[Defs.VOIDESS] - es2, vl.known.size() > known0])
	ok = ok and ok6
	g.space.rocks.erase(mo)
	# ---- 7. a rift: into it, out by its twin
	m.pos = sk.pos
	g._skiff_interact(g.player)
	await _frames(4)
	var ok7 := false
	if rp_first >= 0:
		var rp2: Dictionary = G.rift_pair(rp_first)
		vl.known.erase(str(rp_first))
		var ra: Vector2 = g.space.local_of(rp2["a"])
		sk.pos = ra + Vector2(0.0, -300.0)
		sk.vel = Vector2.ZERO
		var there = null
		for k12 in 200:
			sk.vel = Vector2.ZERO
			await _frames(1)
			for rr in vl.rifts:
				if int(rr["pair"]) == rp_first and int(rr["end"]) == 0:
					there = rr
			if there != null:
				break
		var thr0: int = int(vl.stats["rifts"])
		if there != null:
			sk.pos = (there["pos"] as Vector2) + Vector2(0.0, -150.0)
			await _frames(30)
			_shot("void_rift.png")
			for k13 in 200:
				sk.vel = ((there["pos"] as Vector2) - sk.pos).normalized() * 5.0
				await _frames(1)
				if int(vl.stats["rifts"]) > thr0:
					break
		var pg: PackedFloat64Array = g.space.player_g()
		var to_b: float = Vector2(pg[0] - rp2["b"][0], pg[1] - rp2["b"][1]).length()
		var kn: Array = vl.known.get(str(rp_first), [false, false])
		ok7 = there != null and int(vl.stats["rifts"]) > thr0 and to_b < 1000.0 and kn[0] and kn[1]
		rows.append("%sa rift (pair %d): streamed in %s, through it %s, out %.0f from its twin, both ends charted %s" % ["" if ok7 else "(!) ", rp_first, there != null, int(vl.stats["rifts"]) > thr0, to_b, kn[0] and kn[1]])
		await _frames(30)
		g.open_map()
		g.map_view.gz = 600.0
		g.map_view.centre_on_you()
		await _frames(10)
		_shot("void_map.png")
		g.close_map()
		await _frames(4)
	else:
		rows.append("(!) no rift pair among the first 30 systems")
	ok = ok and ok7
	# ---- 8. the recipes: the harness, and the mantle (mana back twice as fast out here)
	var made := 0
	for rc2 in g.recipes:
		if rc2["id"] == "harness" or rc2["id"] == "voidmantle":
			for ck in rc2["cost"]:
				g.player.inv[int(ck)] += int(rc2["cost"][ck])
			g.learn(String(rc2["id"]), "test")
			if g.craft(rc2):
				made += 1
	g.player.mana = 0.0
	await _frames(60)
	var regen: float = g.player.mana
	var ok8: bool = made == 2 and g.items.has("harness") and absf(g.gear("space_mana") - 2.0) < 0.001 and regen > g.mana_regen * 60.0 * 1.5
	rows.append("%sforged the Void Harness and the Mantle of the Void (%d of 2): mana back %.1f in a second out here (%.1f without)" % ["" if ok8 else "(!) ", made, regen, g.mana_regen * 60.0])
	ok = ok and ok8
	# ---- solar flares (26 Nov): a warning, then the flare: aboard it holes the hull, not with the Radiation Ward;
	# on foot it scorches you; a planet between you and the star shelters you
	var flr_fl_rows := []
	var flr_sp = g.space
	var flr_rw0 = g.items.get("radward", null)
	g.items.erase("radward")
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var flr_fs0: Dictionary = flr_sp.flare_stats.duplicate()
	flr_sp.start_flare(5)
	var flr_warned: bool = flr_sp.flare_warn > 0
	await _frames(10)
	var flr_flaring: bool = flr_sp.flare > 0
	await _frames(200)
	var flr_hull1: int = int(flr_sp.flare_stats["hull"]) - int(flr_fs0["hull"])
	g.items["radward"] = true
	var flr_fs1: Dictionary = flr_sp.flare_stats.duplicate()
	await _frames(150)
	var flr_hull2: int = int(flr_sp.flare_stats["hull"]) - int(flr_fs1["hull"])
	g._skiff_interact(g.player)          # (out, on foot)
	g.player.pos = sk.pos + Vector2(0.0, -60.0)
	g.test_god = false
	g.player.hp = g.player.max_hp
	await _frames(120)
	var flr_lost: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	var flr_sd := Vector2(cos(flr_sp.sun_ang), sin(flr_sp.sun_ang))
	var flr_shade := false
	var flr_lit := false
	for flr_b in flr_sp.bodies.slice(0, 1):
		if true:
			flr_shade = flr_sp.in_shadow((flr_b["pos"] as Vector2) - flr_sd * (float(flr_b["space"]) + 3000.0), flr_sd)
			flr_lit = not flr_sp.in_shadow((flr_b["pos"] as Vector2) + flr_sd * (float(flr_b["space"]) + 3000.0), flr_sd)
	flr_sp.flare = 0
	flr_sp.flare_warn = 0
	if flr_rw0 == null:
		g.items.erase("radward")
	else:
		g.items["radward"] = flr_rw0
	g.player.pos = sk.pos
	g._skiff_interact(g.player)
	await _frames(10)
	var flr_fl_ok: bool = flr_warned and flr_flaring and flr_hull1 >= 2 and flr_hull2 == 0 and flr_lost > 2.0 and flr_shade and flr_lit
	_ok("solar flares out in space: a warning, the hull holed (not with the Radiation Ward), you scorched on foot, a planet's shadow", flr_fl_ok,
		"warned %s, flaring %s; aboard: %d hull hits in 200 ticks, %d with the ward; on foot: %.1f health in 2 s; behind a planet in shadow %s, before it in the light %s" % [flr_warned, flr_flaring, flr_hull1, flr_hull2, flr_lost, flr_shade, flr_lit])
	sk.mend(100000)
	# ---- tidy up, home again, and down
	vl.allow_hostile = false
	vl.clear_test()
	for ik2 in keep_items:
		if keep_items[ik2] == null:
			g.items.erase(ik2)
		else:
			g.items[ik2] = keep_items[ik2]
	g.max_mana = mana0
	g.player.max_mana = mana0
	g.player.mana = minf(g.player.mana, mana0)
	sk.mend(100000)
	sk.vel = Vector2.ZERO
	sk.pos = g.space.home_at() + Vector2(0.0, -(Defs.R_SPACE + 150.0))
	await _frames(30)
	sk.vel = -(sk.pos - g.space.home_at()).normalized() * 6.0
	g.test_cast = true
	for k14 in 600:
		g.test_aim = g.space.home_at() + (sk.pos - g.space.home_at()) * 0.3
		await _frames(1)
		if not g.space.active:
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	for k15 in 1200:
		await _frames(1)
		if sk.grounded and sk.vel.length() < 0.5:
			break
	g.test_down = false
	await _frames(20)
	if g.player.aboard != null:
		g._skiff_interact(g.player)
		await _frames(10)
	g.test_god = god0
	print("[voidlife] " + "\n[voidlife] ".join(rows))
	_ok("space's own life and anomalies: mantas, eels, jellies, wells, monoliths, rifts, their essence and recipes", ok, "; ".join(rows))

func _test_spacebench() -> void:
	var rows := []
	var ok := true
	var G = load("res://scripts/galaxy.gd")
	g.player.dead = false
	var god0: bool = g.test_god
	g.test_god = true
	if g.skiff == null or not g.items.has("skiff"):
		var sf_rec: Dictionary = {}
		for sr in g.recipes:
			if sr["id"] == "skiff":
				sf_rec = sr
		for sk_k in sf_rec.get("cost", {}):
			g.player.inv[int(sk_k)] += int(sf_rec["cost"][sk_k])
		g.craft(sf_rec)
		g.call_skiff()
		await _frames(60)
	var sk = g.skiff
	sk.mend(100000)
	if g.player.aboard != sk:
		g.player.pos = sk.pos
		g._skiff_interact(g.player)
	var up0: Vector2 = sk.pos.normalized()
	sk.pos = up0 * (Defs.R_SPACE - 11.0)
	sk.vel = up0 * 6.0
	sk.grounded = false
	g.test_cast = true
	for k in 240:
		g.test_aim = sk.pos + sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			break
	g.test_cast = false
	# ---- 1. a fight in a derelict station: every alien awake, sparks cast at the nearest
	var sl: Vector2 = g.space.local_of(G.system_station(0))
	sk.pos = sl + Vector2(-1400.0, 0.0)
	sk.vel = Vector2.ZERO
	var st = null
	for k1 in 400:
		sk.vel = Vector2.ZERO
		await _frames(1)
		for a in g.space.rocks:
			if a.kind == "station":
				st = a
		if st != null:
			break
	if st != null:
		var dm: Dictionary = st.mods[st.dock]
		var mouth_b := Vector2(float(int(dm["x0"]) - 60) if st.dock_side < 0 else float(int(dm["x1"]) + 60), float(int(dm["y1"]) - 16))
		sk.pos = st.to_world(mouth_b - st.com) + st.axis_x() * float(st.dock_side) * 120.0
		sk.vel = Vector2.ZERO
		await _frames(20)
		# (docked into its halls: an instance; user, 25 Nov)
		if g.player.aboard != sk:
			g.player.pos = sk.pos
			g._skiff_interact(g.player)
			await _frames(2)
		g.space.dock_station_now(g.player, st)
		st = g.space.inst
		await _frames(4)
		# (into the powered room with the most aliens)
		var best := -1
		var best_n := -1
		for k2 in st.mods.size():
			if not st.mods[k2]["powered"] or st.mods[k2]["role"] == "vault":
				continue
			var n := 0
			for al in g.space.aliens:
				if al.st == st and al.home == k2:
					n += 1
			if n > best_n:
				best_n = n
				best = k2
		var md: Dictionary = st.mods[maxi(best, 0)]
		_st_put(st, Vector2(float(int(md["x0"]) + 10), float(int(md["y1"]) - 10)))
		for al2 in g.space.aliens:
			if al2.st == st:
				al2.awake = true
		var fight := func(f: int) -> void:
			g.player.hp = g.player.max_hp
			g.player.mana = g.player.max_mana
			var near_a = null
			var nd := 1e9
			for al3 in g.space.aliens:
				if al3.dead or al3.st != st:
					continue
				var d: float = al3.world().distance_to(g.player.pos)
				if d < nd:
					nd = d
					near_a = al3
			g.test_aim = near_a.world() if near_a != null else g.player.pos + st.axis_x() * 40.0
			g.test_cast = f % 20 < 2
		var r1: Dictionary = await _bench_measure(300, fight)
		g.test_cast = false
		var n_al := 0
		for al4 in g.space.aliens:
			if al4.st == st and not al4.dead:
				n_al += 1
		rows.append(_bench_line("a fight in %s (%d aliens left)" % [st.wname, n_al], r1))
		ok = ok and r1["avg"] < 16.7 and r1["p95"] < 25.0
		_shot("bench_station.png")
		g.space.undock_station(g.player)
		await _frames(4)
	else:
		rows.append("(!) no derelict station came in")
		ok = false
	# ---- 2. a busy outpost: docked, walking its deck among its spacers
	var ol: Vector2 = g.space.local_of(G.system_outpost(0))
	sk.pos = ol + Vector2(-1400.0, 0.0)
	sk.vel = Vector2.ZERO
	var op = null
	for k3 in 400:
		sk.vel = Vector2.ZERO
		await _frames(1)
		op = g.space.nearest_outpost(sk.pos, 5000.0)
		if op != null:
			break
	if op != null:
		# (docked: its halls, an instance; user, 25 Nov)
		if g.player.aboard != sk:
			g.player.pos = sk.pos
			g._skiff_interact(g.player)
			await _frames(4)
		g.pocket.dock_now(g.player, op)
		await _frames(40)
		var io = g.pocket.op
		var walk := func(f: int) -> void:
			g.test_move = (1 if (f / 100) % 2 == 0 else -1) * -io.hangar_side
		var r2: Dictionary = await _bench_measure(300, walk)
		g.test_move = 0
		rows.append(_bench_line("docked at %s (%d spacers)" % [io.wname, g.pocket.op_folk.size()], r2))
		ok = ok and r2["avg"] < 16.7 and r2["p95"] < 25.0
		_shot("bench_outpost.png")
		g.pocket.leave(g.player)
		await _frames(4)
	else:
		rows.append("(!) no outpost came in")
		ok = false
	# ---- 3. pirates among home's asteroids: three ships, the cannon firing back
	sk.pos = g.space.home_at() + Vector2(0.0, -(Defs.R_SPACE + 1300.0))
	sk.vel = Vector2.ZERO
	g.space._ensure_rocks(true)
	for k4 in 60:
		sk.vel = Vector2.ZERO
		await _frames(1)
	var rk = g.space.nearest_rock(sk.pos, 1e9)
	if rk != null:
		sk.pos = rk.pos + (sk.pos - rk.pos).normalized() * (rk.reach() + 90.0)
	var cannon0: bool = g.items.has("cannon")
	g.items["cannon"] = true
	g.space.allow_pirates = true
	g.space.spawn_pirates(sk.pos, Vector2.RIGHT, "brig")
	g.space.spawn_pirates(sk.pos, Vector2.LEFT, "cutter")
	var fire := func(f: int) -> void:
		g.player.hp = g.player.max_hp
		g.player.mana = g.player.max_mana
		sk.mend(100000)
		var tp = null
		var td := 1e9
		for pa in g.space.rocks:
			if pa.kind == "pirate":
				var d2: float = pa.pos.distance_to(sk.pos)
				if d2 < td:
					td = d2
					tp = pa
		g.test_aim = tp.pos if tp != null else sk.pos + Vector2(100.0, 0.0)
		g.test_cast = true
	var r3: Dictionary = await _bench_measure(300, fire)
	g.test_cast = false
	rows.append(_bench_line("pirates among the asteroids (%d ships, %d rocks)" % [g.space.pirate_count(), g.space.rocks.size()], r3))
	ok = ok and r3["avg"] < 16.7 and r3["p95"] < 25.0
	_shot("bench_pirates.png")
	g.space._drop_pirates()
	g.space.allow_pirates = false
	if not cannon0:
		g.items.erase("cannon")
	# ---- 4. under the Starsail, sectors streaming in
	var sail0: bool = g.items.has("sail")
	g.items["sail"] = true
	var away: Vector2 = (sk.pos - g.space.home_at()).normalized()
	var sailing := func(_f: int) -> void:
		g.test_sail = true
		g.test_cast = true
		g.test_aim = sk.pos + away * 1000.0
	var r4: Dictionary = await _bench_measure(300, sailing)
	g.test_sail = false
	g.test_cast = false
	rows.append(_bench_line("under the Starsail (%d sectors made so far)" % int(g.space.stats["sectors"]), r4))
	ok = ok and r4["avg"] < 16.7 and r4["p95"] < 25.0
	if not sail0:
		g.items.erase("sail")
	# ---- home again, and down
	sk.vel = Vector2.ZERO
	sk.pos = g.space.home_at() + Vector2(0.0, -(Defs.R_SPACE + 150.0))
	await _frames(30)
	sk.vel = -(sk.pos - g.space.home_at()).normalized() * 6.0
	g.test_cast = true
	for k9 in 600:
		g.test_aim = g.space.home_at() + (sk.pos - g.space.home_at()) * 0.3
		await _frames(1)
		if not g.space.active:
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	for k10 in 1200:
		await _frames(1)
		if sk.grounded and sk.vel.length() < 0.5:
			break
	g.test_down = false
	await _frames(20)
	if g.player.aboard != null:
		g._skiff_interact(g.player)
		await _frames(10)
	g.test_god = god0
	print("[spacebench] " + "\n[spacebench] ".join(rows))
	_ok("busy scenes out in space hold 60 fps with room to spare (a station fight, an outpost, pirates among rocks, the Starsail)", ok, "; ".join(rows))

## Building in the pocket as outside (26 Nov, user: "the pocket dimension inside the ship the building does not work like
## the main world. i can only free hand draw pixels and take them away, and i cant place any workshops or anything"):
## a kiln from the satchel set down on the isle's floor, its panel opened with F there, firing sand into glass while
## you're in, saved with the isle (pocket.dat) and taken up again; a torch standing on the floor, glowing; a line of
## planks laid by pressing, dragging and letting go. A picture: saves/shots/pocket_workshop.png.
func _test_pocket_build() -> void:
	var pb_rows := []
	var pb_ok := true
	var pk = g.pocket
	var isle = pk.isle
	var m = g.player
	var ws = g.workshops
	if g.build_on:
		g._toggle_build()
	# ---- a kiln: where it fits, a little way along the isle from you
	var cx0 := int(floor(pk.b.x))
	var spot := {}
	for off in range(14, 200, 3):
		for sgn in [1, -1]:
			var cxs: int = cx0 + off * int(sgn)
			var top := int(floor(isle.top_at(cxs, isle.level)))
			var f: Dictionary = g._pocket_station_fit(isle, "kiln", cxs, top - 3)
			if f["ok"]:
				spot = f
				spot["cx"] = cxs
				spot["cy"] = top - 3
				break
		if not spot.is_empty():
			break
	var n0: int = ws.pocket_list.size()
	g.items["st_kiln"] = 1
	g.hold_carried("station", -1, "kiln")
	g.build_flip = false
	g.test_aim = isle.cell_world(int(spot.get("cx", cx0)), int(spot.get("cy", 0)))
	await _frames(3)
	g.test_cast = true
	await _frames(4)
	g.test_cast = false
	await _frames(4)
	var placed: bool = not spot.is_empty() and ws.pocket_list.size() == n0 + 1 and not g.items.has("st_kiln")
	var st = ws.pocket_list.back() if placed else null
	var stands := false
	if st != null:
		var bb: Vector2 = isle.to_body(st.pos) + isle.com
		var bot := int(round(bb.y + st.h * 0.5 - 1.0))
		var c0 := int(round(bb.x - st.w * 0.5))
		var held := 0
		for i in int(st.w):
			if isle.solid_cell(c0 + i, bot + 1):
				held += 1
		stands = held * 2 >= int(st.w) and st.pocket
	pb_rows.append("%sa kiln from the satchel set down in the pocket %s, standing on the isle %s" % ["" if placed and stands else "(!) ", placed, stands])
	pb_ok = pb_ok and placed and stands
	if st == null:
		_ok("building in the pocket as outside: workshops, torches, shapes", false, "; ".join(pb_rows))
		return
	# ---- F beside it (not holding Conjure): its panel
	var sel0: int = m.sel
	m.sel = 0 if m.known[0] != "conjure" else 1
	pk.near = ""
	m.pos = st.pos + Vector2(6.0, 0.0)
	g._interact()
	var opened: bool = g.state == "station" and ws.open_st == st
	ws.close()
	m.pos = isle.to_world(pk.b)
	m.sel = sel0
	# ---- it works while you're in: sand fired into glass
	m.inv[Defs.SAND] += 8
	m.inv[Defs.COAL] += 2
	ws.load_mat(st, Defs.SAND, 8)
	ws.add_fuel(st, Defs.COAL, 2)
	var key := "m%d" % Defs.GLASS
	var fired := false
	for fw in 900:
		await _frames(1)
		if fw == 200:
			_shot("pocket_workshop.png")
		if int(st.out.get(key, 0)) > 0:
			fired = true
			break
	pb_rows.append("%sF beside it opens its panel %s; it fired sand into glass in the pocket %s (%s)" % ["" if opened and fired else "(!) ", opened, fired, str(st.out)])
	pb_ok = pb_ok and opened and fired
	# ---- saved with the isle, and read back
	pk.save()
	var saved_ok := false
	var fs := FileAccess.open(pk._path(), FileAccess.READ)
	if fs:
		var dd = fs.get_var()
		if dd is Dictionary:
			var back: Array = ws.unpack(dd.get("stations", []), true)
			saved_ok = back.size() == ws.pocket_list.size() and not back.is_empty() and back.back().kind == "kiln" \
				and back.back().pos.distance_to(st.pos) < 0.01 and back.back().pocket
	# ---- taken up again: back in the satchel, what it made with it
	var gl0: int = m.inv[Defs.GLASS]
	var took: bool = ws.take_at(m, st.pos) and int(g.items.get("st_kiln", 0)) == 1 and ws.pocket_list.size() == n0
	var gl_back: bool = m.inv[Defs.GLASS] > gl0
	pb_rows.append("%ssaved in pocket.dat and read back %s; taken up into the satchel %s, its glass with it %s" % ["" if saved_ok and took and gl_back else "(!) ", saved_ok, took, gl_back])
	pb_ok = pb_ok and saved_ok and took and gl_back
	g.items.erase("st_kiln")
	# ---- a torch where the kiln stood: on the floor, its flame glowing
	var fl0 := 0
	for k0 in isle.deco.size():
		if int(isle.deco[k0]) == 200:
			fl0 += 1
	m.inv[Defs.TORCH] += 2
	var tc0: int = m.inv[Defs.TORCH]
	g.hold_carried("torch")
	g.test_aim = isle.cell_world(int(spot["cx"]), int(spot["cy"]))
	await _frames(3)
	g.test_cast = true
	await _frames(4)
	g.test_cast = false
	await _frames(4)
	var fl1 := 0
	for k1 in isle.deco.size():
		if int(isle.deco[k1]) == 200:
			fl1 += 1
	isle.gather_lights()
	var glow := false
	var tw: Vector2 = isle.to_body(g.test_aim) + isle.com
	for lt in isle.lights:
		var lc: Color = lt[2]
		if (lt[0] as Vector2).distance_to(tw) < 16.0 and lc.r > lc.b:
			glow = true
	var torch_ok: bool = fl1 - fl0 == 5 and m.inv[Defs.TORCH] == tc0 - 1 and glow
	pb_rows.append("%sa torch set down: %d flame cells, a torch used %s, glowing %s" % ["" if torch_ok else "(!) ", fl1 - fl0, m.inv[Defs.TORCH] == tc0 - 1, glow])
	pb_ok = pb_ok and torch_ok
	# ---- a line of planks: press, drag, let go
	g.select_material(Defs.PLANK)
	g.hand_shape = 1
	g.hand_thick = 1
	m.inv[Defs.PLANK] += 40
	var pl0: int = m.inv[Defs.PLANK]
	var lx: int = int(spot["cx"])
	var lj: int = int(floor(isle.top_at(lx, isle.level))) - 30
	var before := 0
	for li in range(lx - 6, lx + 7):
		if isle.at(li, lj) == Defs.PLANK:
			before += 1
	g.test_aim = isle.cell_world(lx - 6, lj)
	await _frames(3)
	g.test_cast = true
	await _frames(3)
	g.test_aim = isle.cell_world(lx + 6, lj)
	await _frames(3)
	g.test_cast = false
	await _frames(4)
	var after := 0
	for li2 in range(lx - 6, lx + 7):
		if isle.at(li2, lj) == Defs.PLANK:
			after += 1
	var line_ok: bool = after - before == 13 and m.inv[Defs.PLANK] == pl0 - 13
	pb_rows.append("%sa line of planks laid by dragging: %d cells, %d planks used" % ["" if line_ok else "(!) ", after - before, pl0 - m.inv[Defs.PLANK]])
	pb_ok = pb_ok and line_ok
	for li3 in range(lx - 6, lx + 7):
		if isle.at(li3, lj) == Defs.PLANK:
			isle.remove(li3, lj)
	g.hand_shape = 0
	# ---- (27 Nov; user: "building in the pocket dimension still works weird. i could only draw by pixels shapes didnt
	# work. also i removed some of the starting island and placed some dirt there and when i expanded the island the
	# dirt stayed there") the brush lays a disc; Unmake takes a rectangle away, "+n" popping up; dirt put back into the
	# isle heals into its ground as it grows
	g.select_material(Defs.DIRT)
	m.inv[Defs.DIRT] += 200
	var bj: int = int(floor(isle.top_at(lx, isle.level))) - 40
	var bc0 := 0
	for bjj in range(bj - 4, bj + 5):
		for bii in range(lx - 4, lx + 5):
			if isle.at(bii, bjj) == Defs.DIRT:
				bc0 += 1
	g.test_aim = isle.cell_world(lx, bj)
	await _frames(2)
	g.test_cast = true
	await _frames(4)
	g.test_cast = false
	await _frames(3)
	var bc1 := 0
	for bjj2 in range(bj - 4, bj + 5):
		for bii2 in range(lx - 4, lx + 5):
			if isle.at(bii2, bjj2) == Defs.DIRT:
				bc1 += 1
	var brush_ok: bool = bc1 - bc0 >= 15
	pb_rows.append("%sthe brush laid a disc: %d dirt cells at once" % ["" if brush_ok else "(!) ", bc1 - bc0])
	pb_ok = pb_ok and brush_ok
	# Unmake, a rectangle over that disc (as the tick would: press there, drag, let go)
	g._pick_acc = {}
	var um0: int = m.inv[Defs.DIRT]
	g.unmake_shape = 2
	g.unmake_thick = 1
	g.cabin_cast = true
	g._pocket_unshape(m, isle, "front", lx - 4, bj - 4)
	g._pocket_unshape(m, isle, "front", lx + 4, bj + 4)
	g.cabin_cast = false
	g._pocket_unshape(m, isle, "front", lx + 4, bj + 4)
	var left := 0
	for bjj3 in range(bj - 4, bj + 5):
		for bii3 in range(lx - 4, lx + 5):
			if isle.at(bii3, bjj3) == Defs.DIRT:
				left += 1
	var popped: bool = int(g._pick_acc.get(Defs.DIRT, 0)) > 0
	await _frames(30)
	popped = popped or not g.popups.is_empty()
	var um_ok: bool = left == 0 and m.inv[Defs.DIRT] - um0 == bc1 - bc0 and popped
	pb_rows.append("%sUnmake took a rectangle away: %d left, %d dirt back, \"+n Dirt\" %s" % ["" if um_ok else "(!) ", left, m.inv[Defs.DIRT] - um0, popped])
	pb_ok = pb_ok and um_ok
	# the isle's own ground dug out and filled again with dirt: as it grows, the dirt becomes its ground (grass on
	# top, its layers under), not a block of dirt left as it was
	var gx: int = lx + 20
	var gtop: int = int(floor(isle.top_at(gx, isle.level)))
	for hj in range(gtop, gtop + 8):
		for hi in range(gx, gx + 6):
			isle.remove(hi, hj)
			isle.place(hi, hj, Defs.DIRT)
	var lvl0: int = isle.level
	var grew: bool = isle.expand()
	var healed := 0
	var still_made := 0
	for hj2 in range(gtop, gtop + 8):
		for hi2 in range(gx, gx + 6):
			if isle.made[hj2 * isle.w + hi2] == 1:
				still_made += 1
			elif isle.at(hi2, hj2) != 0:
				healed += 1
	var top_grass: bool = isle.at(gx + 2, gtop) == Defs.GRASS or isle.at(gx + 2, int(floor(isle.top_at(gx + 2, isle.level)))) == Defs.GRASS
	var heal_ok: bool = not grew or (still_made == 0 and healed >= 40 and top_grass)
	pb_rows.append("%sdirt put back in the isle, then it grew (level %d -> %d): %d cells became its ground, %d left as placed, grass on top %s" % ["" if heal_ok else "(!) ", lvl0, isle.level, healed, still_made, top_grass])
	pb_ok = pb_ok and heal_ok
	g.test_aim = Vector2.ZERO
	print("[pocketbuild] " + "\n[pocketbuild] ".join(pb_rows))
	_ok("building in the pocket as outside: a workshop set down, worked, saved and taken up; a torch; shapes", pb_ok, "; ".join(pb_rows))
