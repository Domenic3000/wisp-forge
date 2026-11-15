extends RefCounted
## Automated checks. "Run tests.bat" starts the game with --test: it builds a fresh planet in
## saves/test (your real saves are untouched), plays it for a while, checks that the important
## things still work, writes saves/test_report.txt and quits.

var g                       # the game (main.gd)
var lines := []
var passed := 0
var failed := 0

func _ok(name: String, cond: bool, detail := "") -> void:
	lines.append(("PASS  " if cond else "FAIL  ") + name + ("   [" + detail + "]" if detail != "" else ""))
	if cond:
		passed += 1
	else:
		failed += 1

func _frames(n: int) -> void:
	for k in n:
		await g.get_tree().process_frame

func _cell_pos(col: int, row: int) -> Vector2:
	var a := (float(posmod(col, Defs.SH_N[0])) + 0.5) / Defs.SH_N[0] * TAU
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
func _scan(raw: PackedByteArray, info: Dictionary) -> Dictionary:
	var solid := 0
	var loose := 0
	var tre := 0
	var mats := {}
	var below := {}
	var N: int = Defs.SH_N[0]
	for j in int(info["h"]):
		var row: int = int(info["y0"]) + j
		if row < 0 or row >= Defs.SH_Y0[1]:
			continue
		for i in int(info["w"]):
			var col := posmod(int(info["x0"]) + i, N)
			var c := raw.decode_u32((row * N + col) * 4)
			var t := c & 255
			if Defs.KIND[t] == Defs.K_SOLID and (c & 0x40000000) == 0:
				solid += 1
				# unsupported AND over open space (so it should have fallen); an unsupported block
				# resting on something solid simply can't fall, which is fine
				if ((c >> 24) & 63) > Defs.SPAN[t] and row + 1 < Defs.SH_Y0[1]:
					var cb := raw.decode_u32(((row + 1) * N + col) * 4)
					var tb := cb & 255
					var kb: int = Defs.KIND[tb]
					if tb == 0 or kb == Defs.K_GAS or kb == Defs.K_FIRE or kb == Defs.K_LIQUID:
						loose += 1
						mats[Defs.NAMES[t]] = int(mats.get(Defs.NAMES[t], 0)) + 1
						var key := Defs.NAMES[tb] if tb > 0 else "air"
						below[key] = int(below.get(key, 0)) + 1
			if t == Defs.TREASURE:
				tre += 1
	return {"solid": solid, "loose": loose, "treasure": tre, "mats": mats, "below": below}

func run() -> void:
	var t_all := Time.get_ticks_msec()
	lines.append("Wisp Forge test report  %s" % Time.get_datetime_string_from_system())
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("")
	g.test_god = true

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

	# ---- buildings stand and ruins have settled ----
	var raw: PackedByteArray = g.gpu.read_world()
	var intact := 0
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
			loose_where.append("%d in a %s structure %dx%d" % [sc["loose"], "ruined" if info["ruined"] else "intact", info["w"], info["h"]])
			for k in sc["mats"]:
				loose_mats[k] = int(loose_mats.get(k, 0)) + int(sc["mats"][k])
			for k in sc["below"]:
				loose_below[k] = int(loose_below.get(k, 0)) + int(sc["below"][k])
		if not info["ruined"] and int(info["solid"]) > 0:
			intact += 1
			var ratio := float(sc["solid"]) / float(info["solid"])
			worst = minf(worst, ratio)
			if ratio >= 0.97:
				intact_ok += 1
			treasure_missing += maxi(0, info["chests"].size() * 24 - int(sc["treasure"]))
	_ok("intact buildings stand after settling", intact_ok == intact, "%d of %d keep at least 97%% of their blocks, worst %.1f%%" % [intact_ok, intact, worst * 100.0])
	_ok("intact buildings keep their chests", treasure_missing == 0, "%d chest cells missing" % treasure_missing)
	_ok("nothing is left hanging after settling", loose_total == 0, "%d unsupported blocks over open space" % loose_total)
	if loose_total > 0:
		lines.append("      where: " + "; ".join(loose_where))
		lines.append("      materials: " + str(loose_mats))
		lines.append("      resting on: " + str(loose_below))

	# ---- open a chest ----
	var chest := Vector2i(-1, -1)
	for info in b.infos:
		if not info["ruined"] and info["chests"].size() > 0:
			chest = info["chests"][0]
			break
	if chest.x >= 0:
		_go(_cell_pos(chest.x - 4, chest.y - 7))
		await _frames(40)
		var before := 0
		for m in Defs.NM:
			before += g.player.inv[m]
		g._try_open_chest()
		await _frames(45)
		var after := 0
		for m in Defs.NM:
			after += g.player.inv[m]
		var raw2: PackedByteArray = g.gpu.read_world()
		var left := 0
		var opened := 0
		for cj in 4:
			for ci in 6:
				var row := chest.y - 4 + cj
				var col := posmod(chest.x + ci, Defs.SH_N[0])
				var idx := (row * Defs.SH_N[0] + col) * 4
				if (raw2.decode_u32(idx) & 255) == Defs.TREASURE:
					left += 1
				var off: int = Defs.total_cells() * 4
				if (raw2.decode_u32(off + idx) & 255) == Defs.OPENCHEST:
					opened += 1
		_ok("F opens a chest and gives loot", left == 0 and after > before, "%d chest cells left, satchel %d -> %d" % [left, before, after])
		_ok("an opened chest stays behind", opened >= 20, "%d opened-chest cells" % opened)
	else:
		_ok("F opens a chest and gives loot", false, "no intact chest found")

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
			e.dead = true
		await _frames(2)

	# ---- unsupported blocks fall, and falling rock hurts ----
	var sp := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
	var rs: float = g.gpu.surf_at(g.spawn_angle).x
	_go(sp * (rs + 30.0))
	await _frames(60)
	var up: Vector2 = g.player.pos.normalized()
	var side := Vector2(-up.y, up.x)
	var mid: Vector2 = g.player.pos + side * 30.0 + up * 26.0
	g.brushes.append([mid, 1.8, 5, Defs.STONE, 0, 9, 0])
	await _frames(2)
	var placed: bool = g.type_at(mid) == Defs.STONE
	await _frames(60)
	var still: bool = g.type_at(mid) == Defs.STONE
	_ok("a block conjured in mid-air falls", placed and not still, "placed %s, still there after 1 s %s" % [placed, still])
	g.test_god = false
	g.hp = g.max_hp
	g.iframes = 0
	var hp0: float = g.hp
	g.brushes.append([g.player.pos + up * 20.0, 1.8, 5, Defs.STONE, 0, 8, 0])
	await _frames(90)
	_ok("falling rock hurts the mage", g.hp < hp0, "health %.0f -> %.0f" % [hp0, g.hp])
	g.test_god = true
	g.hp = g.max_hp

	# ---- co-op groundwork: a second mage far away gets its own simulation, collisions and loot ----
	var a2: float = g.spawn_angle + 0.6
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
	await _frames(60)
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
	var step_ms := float(g.perf_us) / maxf(1.0, float(g.perf_n)) / 1000.0
	_ok("holds 60 fps at the surface", wall < 18.5, "%.1f ms per frame, simulation + render %.1f ms" % [wall, step_ms])

	# ---- save and load give back the same world ----
	var a: PackedByteArray = g.gpu.read_world()
	g.save_world(true)
	var loaded: bool = g._load_world(0)
	var bb: PackedByteArray = g.gpu.read_world()
	_ok("saving and loading the world round-trips", loaded and _sha(a) == _sha(bb), "%.1f MB raw" % (a.size() / 1048576.0))

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
