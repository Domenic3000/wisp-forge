extends "res://scripts/tests/space.gd"
## Checks of the exotic worlds: the deep ocean world and the gas giant. (Part of the chain of test files: see tests.gd.)

func _test_abyss() -> void:
	var rows := []
	var ok := true
	var EX: int = Defs.EXOTIC
	var god0: bool = g.test_god
	g.test_god = true
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	g.player.aboard = null
	# ---- where it lies
	var ex0: Array = Defs.exotics_of(0)
	var dh: float = Defs.g_rel(Defs.planet_g(EX), Defs.planet_g(0)).length()
	var dmin := 1e12
	for k in range(1, Defs.SYSTEM.size()):
		dmin = minf(dmin, Defs.g_rel(Defs.planet_g(EX), Defs.planet_g(k)).length())
	var pl: Dictionary = Defs.make_planet(EX)
	var ok1: bool = ex0.has(EX) and dh > 90000.0 and dh < 120000.0 and dmin > 20000.0 and String(pl["kind"]) == "abyss" and Defs.system_of(EX) == 0 and Defs.planets_of(0).has(EX)
	rows.append("%s%s: %.0fk from home, %.0fk from the nearest other planet; a %s world of %s" % ["" if ok1 else "(!) ", pl["name"], dh / 1000.0, dmin / 1000.0, pl["kind"], str(pl["biomes"])])
	ok = ok and ok1
	# ---- its maelstrom: spins you round more than it throws you out; the Tempest Keel lets you through
	var keel0: bool = g.items.has("keel")
	g.items.erase("keel")
	g.space._make_bodies(true)
	var eb := {}
	for b in g.space.bodies:
		if int(b["index"]) == EX:
			eb = b
	var spin := 0.0
	var outw := 0.0
	var reach_no: bool = g.space.reachable(EX)
	if not eb.is_empty():
		var n := Vector2(1, 0)
		var pp: Vector2 = (eb["pos"] as Vector2) + n * (float(eb["space"]) + 2900.0)      # (halfway into the belt: space BELT_IN..BELT_OUT)
		var vv: Vector2 = g.space._storm(pp, Vector2.ZERO)
		spin = absf(vv.dot(Vector2(-n.y, n.x)))
		outw = vv.dot(n)
	g.items["keel"] = true
	var reach_yes: bool = g.space.reachable(EX)
	var ok2: bool = not eb.is_empty() and not reach_no and reach_yes and spin > 0.3 and spin > outw
	rows.append("%sits maelstrom: out of reach without the keel %s, with it %s; halfway in it spins you %.2f a tick round and %.2f out" % ["" if ok2 else "(!) ", not reach_no, reach_yes, spin, outw])
	ok = ok and ok2
	if not keel0:
		g.items.erase("keel")
	# ---- down onto it
	g._enter_planet(EX)
	g.ui.title.visible = false
	await _frames(60)
	var md: Dictionary = g.builds.mystery
	var sea: float = float(g.planet["sea"])
	var deepest := 0.0
	var deep_a := 0.0
	for q in 720:
		var a := float(q) / 720.0 * TAU
		var dd: float = (Defs.RS0 - sea) - g.gpu.surf_at(a).x
		if dd > deepest:
			deepest = dd
			deep_a = a
	var ok3: bool = deepest > 380.0 and not md.is_empty() and (md["stones"] as Array).size() == 5 and (md["pillars"] as Array).size() == 5 and md.has("vault")
	rows.append("%s%s made: its sea %.0f deep at the deepest; %d tide-stones, %d pillars, the temple %s" % ["" if ok3 else "(!) ", g.planet["name"], deepest, (md.get("stones", []) as Array).size(), (md.get("pillars", []) as Array).size(), md.has("vault")])
	ok = ok and ok3
	if md.is_empty():
		_ok("a deep ocean world: its maelstrom, its depths, its sunken mystery", false, "; ".join(rows))
		g.test_god = god0
		return
	# ---- light fades with depth (midday over the deepest place)
	var hold := func(p: Vector2, n: int) -> void:
		for f in n:
			g.player.pos = p
			g.player.vx = 0.0
			g.player.vy = 0.0
			await _frames(1)
	var dir := Vector2(cos(deep_a), sin(deep_a))
	g.time = fposmod((deep_a - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)
	var top_p: Vector2 = dir * (Defs.RS0 - sea - 20.0)
	await hold.call(top_p, 40)
	var l_top: Color = g.gpu.light_at(g.world_to_pic(top_p + g.basis_r(deep_a) * 90.0))
	var deep_p: Vector2 = dir * (g.gpu.surf_at(deep_a).x + 40.0)
	await hold.call(deep_p, 40)
	# (measured to the side, out of the wisp's own light)
	var l_deep: Color = g.gpu.light_at(g.world_to_pic(deep_p + g.basis_r(deep_a) * 90.0))
	var lt := (l_top.r + l_top.g + l_top.b) / 3.0
	var ld := (l_deep.r + l_deep.g + l_deep.b) / 3.0
	var ok4: bool = ld < lt * 0.35
	rows.append("%sthe light 20 under the sea %.2f, %.0f down %.2f" % ["" if ok4 else "(!) ", lt, (Defs.RS0 - sea) - deep_p.length(), ld])
	ok = ok and ok4
	g.player.items["wisp_lantern"] = true
	await hold.call(deep_p, 30)
	_shot("abyss_deep.png")
	# ---- the crushing deep: hurts with only the Tide Charm; the Depth Seal bears it
	var wards := {}
	for wk in ["tidecharm", "depthseal", "tideheart", "pearl", "tidefin"]:
		wards[wk] = g.player.items.has(wk)
		g.player.items.erase(wk)
	g.player.items["tidecharm"] = true
	g.test_god = false
	g.player.hp = g.player.max_hp
	g.player.breath = g.player.max_breath
	await hold.call(deep_p, 120)
	var lost1: float = g.player.max_hp - g.player.hp
	g.player.items["depthseal"] = true
	g.player.hp = g.player.max_hp
	g.player.breath = g.player.max_breath
	await hold.call(deep_p, 120)
	var lost2: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	var ok5: bool = lost1 > 3.0 and lost2 < 0.5
	rows.append("%sthe crushing deep: %.1f health lost in 2 s with only the Tide Charm, %.1f with the Depth Seal too" % ["" if ok5 else "(!) ", lost1, lost2])
	ok = ok and ok5
	# ---- the tide-stones read
	var stones: Array = md["stones"]
	var shot_stone := false
	for k2 in stones.size():
		var sp: Vector2 = stones[k2]["pos"]
		await hold.call(sp + g.basis_r(atan2(sp.y, sp.x)) * 13.0, 14)
		g.mystery.interact(g.player)
		if not shot_stone:
			await _frames(10)
			_shot("abyss_stone.png")
			shot_stone = true
	var known: Dictionary = g.mystery.st["known"]
	var ok6: bool = known.size() == 5
	rows.append("%sthe tide-stones read: %d of 5 notes known (%s)" % ["" if ok6 else "(!) ", known.size(), g.quest.mystery_notes()])
	ok = ok and ok6
	var hud_myst: String = g.quest.hud_line()
	# ---- the temple: its hall dry, its moon pool flooded
	var hall: Vector2 = md["hall"]
	await hold.call(hall, 1)
	await _frames(40)
	var dry: bool = not g.player.in_liquid
	g.player.breath = 100.0
	await _frames(30)
	var breathes: bool = g.player.breath > 100.0
	await hold.call(md["pool"], 20)
	var pool_wet: bool = g.player.in_liquid
	var ok7: bool = dry and breathes and pool_wet
	rows.append("%sthe Temple of the Drowned Choir: its hall dry %s (you breathe there %s), its moon pool's tunnel flooded %s" % ["" if ok7 else "(!) ", dry, breathes, pool_wet])
	ok = ok and ok7
	# ---- a wrong note, then the song
	var order: Array = md["order"]
	var pil: Array = md["pillars"]
	var find := func(gl: int) -> int:
		for k3 in pil.size():
			if int(pil[k3]["glyph"]) == gl:
				return k3
		return -1
	var wrong: int = find.call(int(order[1]))
	await hold.call(pil[wrong]["pos"], 10)
	g.mystery.interact(g.player)
	var w_ok: bool = int(g.mystery.stats["wrong"]) == 1 and (g.mystery.st["rung"] as Array).is_empty()
	for k4 in 5:
		await hold.call(pil[find.call(int(order[k4]))]["pos"], 10)
		g.mystery.interact(g.player)
		if k4 == 3:
			await _frames(4)
			_shot("abyss_temple.png")
	await _frames(20)
	var solved: bool = bool(g.mystery.st["solved"])
	var wr: Dictionary = md["ward"]
	var rr: Dictionary = g.gpu.read_rect(int(wr["x0"]), int(wr["y0"]), int(wr["w"]), int(wr["h"]), int(wr["ax"]), int(wr["aw"]))
	var left := 0
	var fgw: PackedInt32Array = rr.get("fg", PackedInt32Array())
	for c in fgw:
		if (c & 255) == Defs.RUNESTONE or (c & 255) == Defs.WISP:
			left += 1
	var ok8: bool = w_ok and solved and left == 0 and fgw.size() > 0
	rows.append("%sa wrong note silenced them %s; the song sung, solved %s, the ward's stone gone %s (%d cells left)" % ["" if ok8 else "(!) ", w_ok, solved, left == 0, left])
	ok = ok and ok8
	# ---- the vault: the Tide Heart
	var coins0 := int(g.items.get("coins", 0))
	await hold.call(md["vault"], 12)
	_shot("abyss_vault.png")
	g.mystery.interact(g.player)
	var ok9: bool = g.player.items.has("tideheart") and int(g.items.get("coins", 0)) > coins0 and bool(g.mystery.st["claimed"]) and hud_myst.begins_with("Sing")
	rows.append("%sthe Tide Heart claimed %s (+%d coins); on this world the HUD said \"%s\"" % ["" if ok9 else "(!) ", g.player.items.has("tideheart"), int(g.items.get("coins", 0)) - coins0, hud_myst])
	ok = ok and ok9
	g.ui.toggle_journal(g)
	await _frames(5)
	_shot("abyss_journal.png")
	g.ui.toggle_journal(g)
	# ---- put things back, and home again
	for wk2 in wards:
		if wards[wk2]:
			g.player.items[wk2] = true
		else:
			g.player.items.erase(wk2)
	g.player.items.erase("depthseal")
	if wards["depthseal"]:
		g.player.items["depthseal"] = true
	g.player.items.erase("wisp_lantern")
	g.test_god = god0
	g._enter_planet(0)
	g.ui.title.visible = false
	await _frames(60)
	print("[abyss] " + "\n[abyss] ".join(rows))
	_ok("a deep ocean world: its maelstrom, its dark depths, the crushing deep, its sunken mystery and the Tide Heart", ok, "; ".join(rows))

func _test_giant() -> void:
	var rows := []
	var ok := true
	var GX: int = Defs.EXOTIC + 1
	var god0: bool = g.test_god
	g.test_god = true
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	g.player.aboard = null
	# ---- where it lies
	var dh: float = Defs.g_rel(Defs.planet_g(GX), Defs.planet_g(0)).length()
	var dmin := 1e12
	for k in range(1, Defs.SYSTEM.size()):
		dmin = minf(dmin, Defs.g_rel(Defs.planet_g(GX), Defs.planet_g(k)).length())
	var dab: float = Defs.g_rel(Defs.planet_g(GX), Defs.planet_g(Defs.EXOTIC)).length()
	var pl: Dictionary = Defs.make_planet(GX)
	var ok1: bool = Defs.exotics_of(0).has(GX) and Defs.planets_of(0).has(GX) and Defs.exotic_kind(GX) == "giant" and String(pl["kind"]) == "giant" and dh > 90000.0 and dh < 120000.0 and dmin > 20000.0 and dab > 20000.0
	rows.append("%s%s: %.0fk from home, %.0fk from the nearest round planet, %.0fk from the deep ocean world" % ["" if ok1 else "(!) ", pl["name"], dh / 1000.0, dmin / 1000.0, dab / 1000.0])
	ok = ok and ok1
	# ---- its Thunderhead: strikes far more than a storm belt, and the Storm Lattice grounds it
	var lat0: bool = g.items.has("lattice")
	g.items.erase("lattice")
	g.space._make_bodies(true)
	var gb := {}
	var ob := {}
	for b in g.space.bodies:
		var bi := int(b["index"])
		if bi == GX:
			gb = b
		elif not Defs.is_exotic(bi) and bi != g.space.home and not g.space.reachable(bi) and ob.is_empty() and String(b.get("barrier", "")) == "storm":
			ob = b
	var reach_no: bool = g.space.reachable(GX)
	var hits := func(hb: Dictionary) -> int:
		if hb.is_empty():
			return 0
		var hn := Vector2(1, 0)
		var pp: Vector2 = (hb["pos"] as Vector2) + hn * (float(hb["space"]) + 2900.0)
		var n0: int = g.space.bolts.size()
		for q7 in 500:
			g.space._storm(pp, Vector2.ZERO)
		var n1: int = g.space.bolts.size() - n0
		g.space.bolts.clear()
		return n1
	var hg: int = hits.call(gb)
	var ho: int = hits.call(ob)
	g.items["lattice"] = true
	var reach_yes: bool = g.space.reachable(GX)
	var ok2: bool = not gb.is_empty() and not reach_no and reach_yes and hg > 2 * maxi(ho, 4) and g.space.barrier_name(GX) == "thunderhead"
	rows.append("%sits Thunderhead: out of reach without the lattice %s, with it %s; %d strikes in 500 ticks halfway in (a storm belt %d)" % ["" if ok2 else "(!) ", not reach_no, reach_yes, hg, ho])
	ok = ok and ok2
	if not lat0:
		g.items.erase("lattice")
	# ---- down onto its landing isle
	g._enter_planet(GX)
	g.ui.title.visible = false
	g.time = g.towns.time_for_hour(g.player.pos, 12.0)       # (midday, so the pictures show the isles)
	await _frames(150)
	var md: Dictionary = g.builds.mystery
	var hgt: float = g.player.pos.length() - Defs.RS0
	var deepest := 1e9
	for q72 in 72:
		deepest = minf(deepest, Defs.RS0 - g.gpu.surf_at(float(q72) / 72.0 * TAU).x)
	var ok3: bool = g.player.on_ground and hgt > 20.0 and hgt < 90.0 and deepest > 450.0 and String(md.get("kind", "")) == "beacons" and (md.get("beacons", []) as Array).size() == 5 and (md.get("echoes", []) as Array).size() == 5 and md.has("ward") and md.has("plaque")
	rows.append("%s%s made: you stand on its landing isle %s, %.0f over the mean surface; its ground lies %.0f+ under it; %d beacons, the Eye %s" % ["" if ok3 else "(!) ", g.planet["name"], g.player.on_ground, hgt, deepest, (md.get("beacons", []) as Array).size(), md.has("ward")])
	ok = ok and ok3
	_shot("giant_landing.png")
	if md.is_empty() or not md.has("ward"):
		g.test_god = god0
		g._enter_planet(0)
		g.ui.title.visible = false
		await _frames(60)
		_ok("a gas giant: its Thunderhead, isles over the clouds, the crushing air, the beacons and the Storm Crown", false, "; ".join(rows))
		return
	var hold := func(p: Vector2, n: int) -> void:
		for f in n:
			g.player.pos = p
			g.player.vx = 0.0
			g.player.vy = 0.0
			await _frames(1)
	# ---- the crushing air under the clouds; the Depth Seal bears it
	var seal0: bool = g.player.items.has("depthseal")
	var crown0: bool = g.player.items.has("stormcrown")
	g.player.items.erase("depthseal")
	g.player.items.erase("stormcrown")
	var down: Vector2 = g.player.pos.normalized() * (Defs.RS0 - 170.0)
	g.test_god = false
	g.player.hp = g.player.max_hp
	await hold.call(down, 120)
	var lost1: float = g.player.max_hp - g.player.hp
	g.player.items["depthseal"] = true
	g.player.hp = g.player.max_hp
	await hold.call(down, 120)
	var lost2: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	if not seal0:
		g.player.items.erase("depthseal")
	var ok4: bool = lost1 > 3.0 and lost2 < 0.5
	rows.append("%sthe crushing air 170 under: %.1f health lost in 2 s, %.1f with the Depth Seal" % ["" if ok4 else "(!) ", lost1, lost2])
	ok = ok and ok4
	# ---- the Eye's inscription
	g.time = g.towns.time_for_hour(md["plaque"], 11.0)      # (late morning at the Eye: the beacons round it stay in daylight)
	await hold.call(md["plaque"], 12)
	g.mystery.tick()
	var said: String = g.mystery.prompt()
	g.mystery.interact(g.player)
	_shot("giant_eye.png")
	var ok5: bool = said.contains("inscription") and g.mystery.st.has("read_plaque")
	rows.append("%sthe Eye's inscription: prompt \"%s\", read %s" % ["" if ok5 else "(!) ", said, g.mystery.st.has("read_plaque")])
	ok = ok and ok5
	# ---- the Eye's hall and its ward are really there (stone, not just places in the plan)
	var wr0: Dictionary = md["ward"]
	var rr0: Dictionary = g.gpu.read_rect(int(wr0["x0"]), int(wr0["y0"]), int(wr0["w"]), int(wr0["h"]), int(wr0["ax"]), int(wr0["aw"]))
	var ward0 := 0
	for c0 in (rr0.get("fg", PackedInt32Array()) as PackedInt32Array):
		if (c0 & 255) == Defs.RUNESTONE:
			ward0 += 1
	var ok5b: bool = ward0 >= int(wr0["w"]) * int(wr0["h"]) - 4
	rows.append("%sthe Eye's ward stands: %d runestone cells of %d" % ["" if ok5b else "(!) ", ward0, int(wr0["w"]) * int(wr0["h"])])
	ok = ok and ok5b
	# ---- the beacons: lit one by one, one let go out, then all five as one
	var bcs: Array = md["beacons"]
	var hud := ""
	for k2 in 4:
		await hold.call(bcs[k2]["stand"], 8)
		g.mystery.tick()
		g.player.mana = g.player.max_mana
		g.mystery.interact(g.player)
		if k2 == 0:
			await _frames(10)
			_shot("giant_beacon.png")
			hud = g.quest.hud_line() if g.quest != null else ""
	var lit4: int = g.mystery.burn.size()
	g.mystery.burn[0] = g.frame + 20                 # (the first burns down)
	await _frames(30)
	var out1: int = int(g.mystery.stats["out"])
	var solved_early: bool = bool(g.mystery.st["solved"])
	g.player.mana = g.player.max_mana
	g.mystery.light(0)
	g.player.mana = g.player.max_mana
	g.mystery.light(4)
	await _frames(20)
	var solved: bool = bool(g.mystery.st["solved"])
	var wr: Dictionary = md["ward"]
	var rr: Dictionary = g.gpu.read_rect(int(wr["x0"]), int(wr["y0"]), int(wr["w"]), int(wr["h"]), int(wr["ax"]), int(wr["aw"]))
	var left := 0
	var fgw: PackedInt32Array = rr.get("fg", PackedInt32Array())
	for c in fgw:
		if (c & 255) == Defs.RUNESTONE:
			left += 1
	var ok6: bool = lit4 == 4 and out1 >= 1 and not solved_early and solved and left == 0 and fgw.size() > 0
	rows.append("%sbeacons: %d lit by hand, %d went out (not solved yet %s), all five as one: solved %s, the ward gone %s (%d left)" % ["" if ok6 else "(!) ", lit4, out1, not solved_early, solved, left == 0, left])
	ok = ok and ok6
	# ---- the vault: the Storm Crown, and what it bears
	var coins0 := int(g.items.get("coins", 0))
	await hold.call(md["vault"], 12)
	g.mystery.tick()
	_shot("giant_vault.png")
	g.mystery.interact(g.player)
	var crown: bool = g.player.items.has("stormcrown")
	g.test_god = false
	g.player.hp = g.player.max_hp
	await hold.call(down, 90)
	var lost3: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	var ok7: bool = crown and int(g.items.get("coins", 0)) > coins0 and bool(g.mystery.st["claimed"]) and lost3 < 0.5 and hud.begins_with("Light")
	rows.append("%sthe Storm Crown %s (+%d coins); under the clouds with it: %.1f lost; on this world the HUD said \"%s\"" % ["" if ok7 else "(!) ", crown, int(g.items.get("coins", 0)) - coins0, lost3, hud])
	ok = ok and ok7
	g.ui.toggle_journal(g)
	await _frames(5)
	_shot("giant_journal.png")
	g.ui.toggle_journal(g)
	# ---- put things back, and home again
	if not crown0:
		g.player.items.erase("stormcrown")
	g.test_god = god0
	g._enter_planet(0)
	g.ui.title.visible = false
	await _frames(60)
	print("[giant] " + "\n[giant] ".join(rows))
	_ok("a gas giant: its Thunderhead, isles over the clouds, the crushing air, the beacons and the Storm Crown", ok, "; ".join(rows))
