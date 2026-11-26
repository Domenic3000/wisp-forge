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

## A dying star (26 Nov): where it lies, its corona (out of reach without the Heat Shield, burning halfway in), its
## rafts of slag on a molten sea, a flare that sears you under the open sky (not with the Solar Shroud), the Sun
## Relay (the lenses turned until the well's light reaches the eye, the ward's runestone gone), the Sun's Heart
## (lava can't hurt you), and Solarion over the Sanctum
func _test_star() -> void:
	var rows := []
	var ok := true
	var SX: int = Defs.EXOTIC + 2
	var god0: bool = g.test_god
	g.test_god = true
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	g.player.aboard = null
	var dh: float = Defs.g_rel(Defs.planet_g(SX), Defs.planet_g(0)).length()
	var dex := 1e12
	for k in [Defs.EXOTIC, Defs.EXOTIC + 1, Defs.EXOTIC + 3]:
		dex = minf(dex, Defs.g_rel(Defs.planet_g(SX), Defs.planet_g(int(k))).length())
	var pl: Dictionary = Defs.make_planet(SX)
	var ok1: bool = Defs.exotics_of(0).has(SX) and Defs.exotic_kind(SX) == "star" and String(pl["kind"]) == "star" and dh > 90000.0 and dh < 120000.0 and dex > 15000.0
	rows.append("%s%s: %.0fk from home, %.0fk from the nearest other exotic" % ["" if ok1 else "(!) ", pl["name"], dh / 1000.0, dex / 1000.0])
	ok = ok and ok1
	# ---- its corona: out of reach without the Heat Shield; halfway in it burns
	var hs0: bool = g.items.has("heatshield")
	g.items.erase("heatshield")
	g.space._make_bodies(true)
	var sb := {}
	for b in g.space.bodies:
		if int(b["index"]) == SX:
			sb = b
	var reach_no: bool = g.space.reachable(SX)
	var hits0: int = g.space.belt_strikes
	if not sb.is_empty():
		var pp: Vector2 = (sb["pos"] as Vector2) + Vector2(1, 0) * (float(sb["space"]) + 2900.0)
		for q in 400:
			g.space._storm(pp, Vector2.ZERO)
	var burns: int = g.space.belt_strikes - hits0
	g.items["heatshield"] = true
	var reach_yes: bool = g.space.reachable(SX)
	var ok2: bool = not sb.is_empty() and not reach_no and reach_yes and burns > 0 and String(sb.get("barrier", "")) == "corona"
	rows.append("%sits corona: out of reach without the Heat Shield %s, with it %s; %d burns in 400 ticks halfway in" % ["" if ok2 else "(!) ", not reach_no, reach_yes, burns])
	ok = ok and ok2
	if not hs0:
		g.items.erase("heatshield")
	# ---- down onto its landing raft
	g._enter_planet(SX)
	g.ui.title.visible = false
	g.time = g.towns.time_for_hour(g.player.pos, 12.0)
	await _frames(150)
	var md: Dictionary = g.builds.mystery
	var molten := 0
	var wetc := 0
	for q2 in 200:
		var x: int = q2 * g.builds.N0 / 200
		if g.builds.surf[x * 8 + 5] > g.builds.surf[x * 8] + 2.0:
			wetc += 1
			if int(g.builds.surf[x * 8 + 6]) == Defs.LAVA:
				molten += 1
	var ok3: bool = g.player.on_ground and String(md.get("kind", "")) == "lenses" and (md.get("lenses", []) as Array).size() == 6 and md.has("eye") and md.has("ward") and md.has("plaque") and wetc > 60 and molten == wetc and bool(md.get("planned", false))
	rows.append("%s%s made: on the ground %s; %d of 200 columns are sea, %d of them molten; %d lenses, the eye %s, the path planned %s" % ["" if ok3 else "(!) ", g.planet["name"], g.player.on_ground, wetc, molten, (md.get("lenses", []) as Array).size(), md.has("eye"), md.get("planned", false)])
	ok = ok and ok3
	_shot("star_landing.png")
	if not md.has("ward") or not md.has("eye"):
		g.test_god = god0
		g._enter_planet(0)
		g.ui.title.visible = false
		await _frames(60)
		_ok("a dying star: its corona, slag on a molten sea, its flares, the Sun Relay and the Sun's Heart", false, "; ".join(rows))
		return
	var hold := func(p: Vector2, n: int) -> void:
		for f in n:
			g.player.pos = p
			g.player.vx = 0.0
			g.player.vy = 0.0
			await _frames(1)
	# ---- the molten sea is really lava, in the world
	var sea_col := -1
	for q3 in 400:
		var x3: int = q3 * g.builds.N0 / 400
		if g.builds.biome(x3) == "corona" and g.builds.surf[x3 * 8 + 5] > g.builds.surf[x3 * 8] + 30.0:
			sea_col = x3
			break
	var lava_cells := 0
	if sea_col >= 0:
		var wrow: int = g.builds.water_row(sea_col)
		var rl: Dictionary = g.gpu.read_rect(sea_col, wrow + 4, 1, 6, sea_col, 1)
		for c in (rl.get("fg", PackedInt32Array()) as PackedInt32Array):
			if (c & 255) == Defs.LAVA:
				lava_cells += 1
	var ok3b: bool = lava_cells >= 5
	rows.append("%sunder the molten sea's top: %d of 6 cells lava" % ["" if ok3b else "(!) ", lava_cells])
	ok = ok and ok3b
	# ---- a flare sears you under the open sky (the Heat Ward on, so it's the flare alone); not with the Solar Shroud
	var hw0: bool = g.player.heat_ward
	var shroud0: bool = g.player.items.has("solarshroud")
	g.player.heat_ward = true
	g.player.items.erase("solarshroud")
	var open_p: Vector2 = md["lenses"][0]["stand"]
	await hold.call(open_p, 20)
	g.start_sky_event("flare")
	g.sky_dur = 2000
	await hold.call(open_p, 300)
	_shot("star_flare.png")
	g.test_god = false
	g.player.hp = g.player.max_hp
	await hold.call(open_p, 120)
	var lost1: float = g.player.max_hp - g.player.hp
	g.player.items["solarshroud"] = true
	g.player.hp = g.player.max_hp
	await hold.call(open_p, 120)
	var lost2: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	g.end_sky_event()
	if not shroud0:
		g.player.items.erase("solarshroud")
	var ok4: bool = lost1 > 3.0 and lost2 < 0.5
	rows.append("%sa flare under the open sky: %.1f health lost in 2 s, %.1f with the Solar Shroud" % ["" if ok4 else "(!) ", lost1, lost2])
	ok = ok and ok4
	# ---- the Sanctum's inscription and its ward
	await hold.call(md["plaque"], 12)
	g.mystery.tick()
	var said: String = g.mystery.prompt()
	g.mystery.interact(g.player)
	_shot("star_sanctum.png")
	var wr0: Dictionary = md["ward"]
	var rr0: Dictionary = g.gpu.read_rect(int(wr0["x0"]), int(wr0["y0"]), int(wr0["w"]), int(wr0["h"]), int(wr0["ax"]), int(wr0["aw"]))
	var ward0 := 0
	for c0 in (rr0.get("fg", PackedInt32Array()) as PackedInt32Array):
		if (c0 & 255) == Defs.RUNESTONE:
			ward0 += 1
	var ok5: bool = said.contains("inscription") and g.mystery.st.has("read_plaque") and ward0 >= int(wr0["w"]) * int(wr0["h"]) - 4
	rows.append("%sthe Sanctum: prompt \"%s\", read %s; its ward %d runestone cells of %d" % ["" if ok5 else "(!) ", said, g.mystery.st.has("read_plaque"), ward0, int(wr0["w"]) * int(wr0["h"])])
	ok = ok and ok5
	# ---- the relay: the well's lens turned by hand until its light catches the first lens, then the rest set
	var need: Array = md["need"]
	var lens_said := ""
	await hold.call(md["lenses"][0]["stand"], 10)
	g.mystery.tick()
	lens_said = g.mystery.prompt()
	var turns := 0
	for t8 in 8:
		if int(g.mystery.st["face"][0]) == int(need[0]):
			break
		g.mystery.tick()
		g.mystery.interact(g.player)
		turns += 1
		await _frames(2)
	var lit_after_well: int = g.mystery.path.size()
	var early: bool = bool(g.mystery.st["solved"])
	for k5 in range(1, 6):
		while int(g.mystery.st["face"][k5]) != int(need[k5]):
			g.mystery.turn(k5)
	await hold.call(md["lenses"][3]["stand"], 30)
	_shot("star_relay.png")
	await _frames(20)
	var solved: bool = bool(g.mystery.st["solved"])
	var wr: Dictionary = md["ward"]
	var rr: Dictionary = g.gpu.read_rect(int(wr["x0"]), int(wr["y0"]), int(wr["w"]), int(wr["h"]), int(wr["ax"]), int(wr["aw"]))
	var left := 0
	var fgw: PackedInt32Array = rr.get("fg", PackedInt32Array())
	for c2 in fgw:
		if (c2 & 255) == Defs.RUNESTONE:
			left += 1
	var ok6: bool = lens_said.contains("turn") and lit_after_well >= 2 and not early and solved and g.mystery.path_eye and g.mystery.path.size() == 6 and left == 0 and fgw.size() > 0
	rows.append("%sthe relay: prompt \"%s\"; the well turned %d times, then %d lit; all six set: through all %d into the eye %s, solved %s, the ward gone %s (%d left)" % ["" if ok6 else "(!) ", lens_said, turns, lit_after_well, g.mystery.path.size(), g.mystery.path_eye, solved, left == 0, left])
	ok = ok and ok6
	# ---- the vault: the Sun's Heart, and lava can't hurt you
	var coins0 := int(g.items.get("coins", 0))
	var sh0: bool = g.player.items.has("sunheart")
	await hold.call(md["vault"], 12)
	g.mystery.tick()
	_shot("star_vault.png")
	g.mystery.interact(g.player)
	var got: bool = g.player.items.has("sunheart")
	var lost3 := -1.0
	if sea_col >= 0:
		var wrow2: int = g.builds.water_row(sea_col)
		var a9 := (float(sea_col) + 0.5) / float(g.builds.N0) * TAU
		var in_lava: Vector2 = Vector2(cos(a9), sin(a9)) * (Defs.R_TOP - float(wrow2 + 12))
		g.test_god = false
		g.player.heat_ward = true
		g.player.hp = g.player.max_hp
		await hold.call(in_lava, 90)
		lost3 = g.player.max_hp - g.player.hp
		g.test_god = true
		g.player.hp = g.player.max_hp
	var hud: String = g.quest.hud_line() if g.quest != null else ""
	var ok7: bool = got and int(g.items.get("coins", 0)) > coins0 and bool(g.mystery.st["claimed"]) and lost3 >= 0.0 and lost3 < 2.0
	rows.append("%sthe Sun's Heart %s (+%d coins); in the molten sea with it: %.1f lost in 1.5 s; the HUD says \"%s\"" % ["" if ok7 else "(!) ", got, int(g.items.get("coins", 0)) - coins0, lost3, hud])
	ok = ok and ok7
	# ---- Solarion over the Sanctum
	var boss_ok := false
	for e in g.enemies:
		if not e.dead and e.type == "heart_star":
			boss_ok = true
	rows.append("%sSolarion, the Sun Phoenix, flies over the Sanctum: %s" % ["" if boss_ok else "(!) ", boss_ok])
	ok = ok and boss_ok
	g.ui.toggle_journal(g)
	await _frames(5)
	_shot("star_journal.png")
	g.ui.toggle_journal(g)
	if not sh0:
		g.player.items.erase("sunheart")
	g.player.heat_ward = hw0
	g.test_god = god0
	g._enter_planet(0)
	g.ui.title.visible = false
	await _frames(60)
	print("[star] " + "\n[star] ".join(rows))
	_ok("a dying star: its corona, slag on a molten sea, its flares, the Sun Relay and the Sun's Heart", ok, "; ".join(rows))

## A black hole (26 Nov): where it lies, its horizon (pulling you in, out of reach without the Void Anchor), the
## Hollow inside (shards of worlds over rifts that unmake you), an echo woken at a shrine and fading when you go,
## the five echoes beaten for their shards, the Gate opened, the Void Heart, and Nul'Ghora over the Gate
func _test_void() -> void:
	var rows := []
	var ok := true
	var VX: int = Defs.EXOTIC + 3
	var god0: bool = g.test_god
	g.test_god = true
	if g.player.aboard != null:
		g._skiff_interact(g.player)
	g.player.aboard = null
	var dh: float = Defs.g_rel(Defs.planet_g(VX), Defs.planet_g(0)).length()
	var dex := 1e12
	for k in [Defs.EXOTIC, Defs.EXOTIC + 1, Defs.EXOTIC + 2]:
		dex = minf(dex, Defs.g_rel(Defs.planet_g(VX), Defs.planet_g(int(k))).length())
	var pl: Dictionary = Defs.make_planet(VX)
	var ok1: bool = Defs.exotics_of(0).has(VX) and Defs.exotic_kind(VX) == "void" and String(pl["kind"]) == "void" and dh > 90000.0 and dh < 120000.0 and dex > 15000.0
	rows.append("%s%s: %.0fk from home, %.0fk from the nearest other exotic" % ["" if ok1 else "(!) ", pl["name"], dh / 1000.0, dex / 1000.0])
	ok = ok and ok1
	# ---- its horizon pulls you in, and the Void Anchor opens it
	var va0: bool = g.items.has("voidanchor")
	g.items.erase("voidanchor")
	g.space._make_bodies(true)
	var vb := {}
	for b in g.space.bodies:
		if int(b["index"]) == VX:
			vb = b
	var reach_no: bool = g.space.reachable(VX)
	var pull := 0.0
	if not vb.is_empty():
		var n := Vector2(1, 0)
		var pp: Vector2 = (vb["pos"] as Vector2) + n * (float(vb["space"]) + 2900.0)
		var v: Vector2 = g.space._storm(pp, Vector2.ZERO)
		pull = -v.dot(n)
	g.items["voidanchor"] = true
	var reach_yes: bool = g.space.reachable(VX)
	var ok2: bool = not vb.is_empty() and not reach_no and reach_yes and pull > 0.05 and String(vb.get("barrier", "")) == "horizon"
	rows.append("%sits horizon: out of reach without the Void Anchor %s, with it %s; halfway in it pulls you in at %.2f a tick" % ["" if ok2 else "(!) ", not reach_no, reach_yes, pull])
	ok = ok and ok2
	if not va0:
		g.items.erase("voidanchor")
	g.space.bolts.clear()
	# ---- into the Hollow
	g._enter_planet(VX)
	g.ui.title.visible = false
	g.time = g.towns.time_for_hour(g.player.pos, 12.0)
	await _frames(150)
	var md: Dictionary = g.builds.mystery
	var deepest := 0.0
	var rift_a := -1.0
	for q in 144:
		var a := float(q) / 144.0 * TAU
		var dd: float = Defs.RS0 - g.gpu.surf_at(a).x
		if dd > deepest:
			deepest = dd
			rift_a = a
	var ok3: bool = g.player.on_ground and String(md.get("kind", "")) == "echoes" and (md.get("shrines", []) as Array).size() == 5 and md.has("ward") and md.has("plaque") and deepest > 400.0
	rows.append("%s%s made: on the ground %s; %d shrines, the Gate %s; its rifts %.0f deep" % ["" if ok3 else "(!) ", g.planet["name"], g.player.on_ground, (md.get("shrines", []) as Array).size(), md.has("ward"), deepest])
	ok = ok and ok3
	_shot("void_landing.png")
	if not md.has("ward") or (md.get("shrines", []) as Array).size() < 5:
		g.test_god = god0
		g._enter_planet(0)
		g.ui.title.visible = false
		await _frames(60)
		_ok("a black hole: its horizon, the Hollow inside, the echoes and their shards, the Gate and the Void Heart", false, "; ".join(rows))
		return
	var hold := func(p: Vector2, n: int) -> void:
		for f in n:
			g.player.pos = p
			g.player.vx = 0.0
			g.player.vy = 0.0
			await _frames(1)
	# ---- the rifts unmake you, down in them; the Void Heart bears it
	var vh0: bool = g.player.items.has("voidheart")
	var vm0: bool = g.player.items.has("voidmantle")
	g.player.items.erase("voidheart")
	g.player.items.erase("voidmantle")
	var down: Vector2 = Vector2(cos(rift_a), sin(rift_a)) * (Defs.RS0 - 200.0)
	g.test_god = false
	g.player.hp = g.player.max_hp
	await hold.call(down, 120)
	var lost1: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	var ok4: bool = lost1 > 3.0
	rows.append("%sdown a rift, 200 under: %.1f health lost in 2 s" % ["" if ok4 else "(!) ", lost1])
	ok = ok and ok4
	# ---- the Gate's inscription
	await hold.call(md["plaque"], 12)
	g.mystery.tick()
	var said: String = g.mystery.prompt()
	g.mystery.interact(g.player)
	_shot("void_gate.png")
	var ok5: bool = said.contains("inscription") and g.mystery.st.has("read_plaque")
	rows.append("%sthe Gate: prompt \"%s\", read %s" % ["" if ok5 else "(!) ", said, g.mystery.st.has("read_plaque")])
	ok = ok and ok5
	# ---- an echo woken at the first shrine, fading as you walk far off; then all five woken and beaten
	var shs: Array = md["shrines"]
	await hold.call(shs[0]["stand"], 30)
	g.mystery.tick()
	var wake_said: String = g.mystery.prompt()
	g.mystery.interact(g.player)
	await _frames(40)
	var e0 = g.mystery.echo
	var woke: bool = e0 != null and not e0.dead
	var echo_hp: float = e0.max_hp if woke else 0.0
	var full_hp: float = float(Defs.boss_enemy("boss_" + String(shs[0]["biome"]))["hp"])
	_shot("void_echo.png")
	var away: Vector2 = (shs[0]["pos"] as Vector2).rotated(900.0 / Defs.RS0)
	await hold.call(away, 12)
	var faded: bool = g.mystery.echo == null and (e0 == null or e0.dead)
	var beaten := 0
	var names := []
	for k6 in shs.size():
		await hold.call(shs[k6]["stand"], 20)
		g.mystery.wake(k6)
		await _frames(10)
		var ek = g.mystery.echo
		if ek != null:
			names.append(String(Defs.BOSSES[String(shs[k6]["biome"])]["name"]))
			g._hurt_enemy(ek, 99999.0, 0.0, 0.0)
			await _frames(3)
		beaten = (g.mystery.st["won"] as Array).size()
	var ok6: bool = wake_said.contains("wake") and woke and absf(echo_hp - full_hp * 0.7) < 2.0 and faded and beaten == 5
	rows.append("%sechoes: prompt \"%s\"; the first woke %s (%.0f health of its guardian's %.0f), faded far off %s; beaten for their shards: %d (%s)" % ["" if ok6 else "(!) ", wake_said, woke, echo_hp, full_hp, faded, beaten, ", ".join(names)])
	ok = ok and ok6
	# ---- the shards set in the Gate: its ward gone
	await hold.call(md["plaque"], 12)
	g.mystery.tick()
	var set_said: String = g.mystery.prompt()
	g.mystery.interact(g.player)
	await _frames(20)
	var wr: Dictionary = md["ward"]
	var rr: Dictionary = g.gpu.read_rect(int(wr["x0"]), int(wr["y0"]), int(wr["w"]), int(wr["h"]), int(wr["ax"]), int(wr["aw"]))
	var left := 0
	var fgw: PackedInt32Array = rr.get("fg", PackedInt32Array())
	for c2 in fgw:
		if (c2 & 255) == Defs.RUNESTONE:
			left += 1
	var ok7: bool = set_said.contains("set") and bool(g.mystery.st["solved"]) and left == 0 and fgw.size() > 0
	rows.append("%sthe Gate: prompt \"%s\", solved %s, the ward gone %s (%d left)" % ["" if ok7 else "(!) ", set_said, g.mystery.st["solved"], left == 0, left])
	ok = ok and ok7
	# ---- the vault: the Void Heart (+60 mana), and the rifts can't unmake you with it
	var mm0: float = g.player.max_mana
	await hold.call(md["vault"], 12)
	g.mystery.tick()
	_shot("void_vault.png")
	g.mystery.interact(g.player)
	var got: bool = g.player.items.has("voidheart")
	g.test_god = false
	g.player.hp = g.player.max_hp
	await hold.call(down, 90)
	var lost2: float = g.player.max_hp - g.player.hp
	g.test_god = true
	g.player.hp = g.player.max_hp
	var ok8: bool = got and g.player.max_mana >= mm0 + 59.0 and lost2 < 0.5 and bool(g.mystery.st["claimed"])
	rows.append("%sthe Void Heart %s (max mana %.0f -> %.0f); down the rift with it: %.1f lost" % ["" if ok8 else "(!) ", got, mm0, g.player.max_mana, lost2])
	ok = ok and ok8
	if got and not vh0:
		g.player.max_mana -= 60.0
		g.player.items.erase("voidheart")
		g._apply_gear()
	if vm0:
		g.player.items["voidmantle"] = true
	var boss_ok := false
	for e in g.enemies:
		if not e.dead and e.type == "heart_void":
			boss_ok = true
	rows.append("%sNul'Ghora, the Devourer, over the Gate: %s" % ["" if boss_ok else "(!) ", boss_ok])
	ok = ok and boss_ok
	g.ui.toggle_journal(g)
	await _frames(5)
	_shot("void_journal.png")
	g.ui.toggle_journal(g)
	g.test_god = god0
	g._enter_planet(0)
	g.ui.title.visible = false
	await _frames(60)
	print("[void] " + "\n[void] ".join(rows))
	_ok("a black hole: its horizon, the Hollow inside, the echoes and their shards, the Gate and the Void Heart", ok, "; ".join(rows))

## Each kind of world's own biome (26 Nov: Basalt Columns, Kelp Isles, Saltglass Flats, Sunken Mangroves, Crystal
## Fields, Elder Canopy, Flower Meadows): a planet is made whose biomes are the seven (the classic system's planet
## NB_I, its biomes, shares, sea and guardians set by hand), and in each one at midday its plants or scenery stand
## (a picture of each, saves/shots/newbiome_<name>.png), it has creatures of its own and its guardian, which is called
## at an altar there and fought (`_test_guardians`); the planets of a journey saved before keep their old biomes.
const NB_I := 7
func _test_newbiomes() -> void:
	var nb_list := ["basalt", "kelp", "saltflats", "mangrove", "crystalfields", "elder", "meadow"]
	var nb_rows := []
	var nb_ok := true
	# (a planet saved before keeps the biomes it was made with; one made after grows the new ones)
	# (the first planet of a grown system whose biomes come out differently now)
	var nb_leg0: Dictionary = Defs.legacy_biomes.duplicate()
	var nb_found := false
	for nb_i in range(1, 30):
		Defs.legacy_biomes = {nb_i: true}
		var nb_old := Defs.make_planet_for(424242, nb_i)
		Defs.legacy_biomes = {}
		var nb_new := Defs.make_planet_for(424242, nb_i)
		if str(nb_old["biomes"]) == str(nb_new["biomes"]):
			continue
		nb_found = true
		var nb_same := true
		for nb_k in ["radius", "starts", "name", "kind"]:
			nb_same = nb_same and str(nb_old[nb_k]) == str(nb_new[nb_k])
		var nb_oldset := true
		for nb_b0 in nb_old["biomes"]:
			nb_oldset = nb_oldset and not nb_list.has(nb_b0)
		nb_rows.append("%s (%s): saved before, it keeps its old biomes (%s) and all else (%s); made now, %s" % [nb_old["name"], nb_old["kind"], ", ".join(nb_old["biomes"]), nb_same, ", ".join(nb_new["biomes"])])
		nb_ok = nb_ok and nb_same and nb_oldset
		break
	Defs.legacy_biomes = nb_leg0
	if not nb_found:
		nb_rows.append("(!) no planet of 424242's first 30 grows a new biome")
		nb_ok = false
	# the planet of the seven
	var nb_god0: bool = g.test_god
	g.test_god = true
	g._delete_worlds()
	var nb_pl: Dictionary = Defs.make_planet_for(0, NB_I)
	nb_pl["biomes"] = nb_list.duplicate()
	var nb_st := PackedFloat32Array()
	for nb_q in 7:
		nb_st.append(float(nb_q) / 7.0)
	nb_pl["starts"] = nb_st
	nb_pl["guardians"] = nb_list.duplicate()
	nb_pl["sea"] = 26.0
	nb_pl["kind"] = "wild"
	nb_pl["name"] = "Newfold"
	Defs._planet_cache["0:%d:v2" % NB_I] = nb_pl
	g._enter_planet(NB_I)
	g.ui.title.visible = false
	await _frames(60)
	var toff: int = Defs.total_cells() * 4
	for nb_b in nb_list:
		var nb_mid := _biome_mid_col(nb_b)
		if nb_mid < 0:
			nb_rows.append("(!) %s: not on the planet" % nb_b)
			nb_ok = false
			continue
		var nb_gr: int = g.builds.ground_row(nb_mid)
		var nb_pos := _cell_pos(nb_mid, nb_gr - 30)
		_go(nb_pos)
		g.time = g.towns.time_for_hour(nb_pos, 12.5)
		await _frames(150)
		_shot("newbiome_%s.png" % nb_b)
		# what stands in the background round it: plants (_plants) and the stone scenery (basalt, salt, ice)
		var raw: PackedByteArray = g.gpu.read_world()
		var nb_n := 0
		for nb_c in range(nb_mid - 200, nb_mid + 200, 120):
			nb_n += _plants(raw, toff, nb_c, g.builds.ground_row(nb_c + 60))
		var nb_sc := 0
		for j in range(nb_gr - 140, nb_gr + 30):
			for i in range(-200, 200):
				var bm := raw.decode_u32(toff + Defs.raw_idx(j, posmod(nb_mid + i, Defs.NS)) * 4) & 255
				if bm == Defs.DEEPSTONE or bm == Defs.OBSIDIAN or bm == Defs.SANDSTONE or bm == Defs.ICE or bm == Defs.FROST or bm == Defs.MASONRY:
					nb_sc += 1
		var nb_cr: Array = Defs.creatures_of(nb_b)
		var nb_good: bool = nb_n + nb_sc > 60 and not nb_cr.is_empty() and Defs.BOSSES.has(nb_b) and Defs.SIGIL_MATS.has(nb_b)
		nb_ok = nb_ok and nb_good
		nb_rows.append("%s%s (%s): %d plant cells, %d of its stone scenery; creatures %s" % ["" if nb_good else "(!) ", nb_b, Defs.BIOMES[nb_b]["name"], nb_n, nb_sc, ", ".join(nb_cr)])
	g.test_god = nb_god0
	_ok("each kind of world's own biome: made, its plants and scenery stand, its own creatures and guardian", nb_ok, "; ".join(nb_rows))
	# and the seven guardians, each called at an altar in its biome
	await _test_guardians(nb_list)
	Defs._planet_cache.erase("0:%d:v2" % NB_I)
	g._delete_worlds()
	g._enter_planet(0)
	g.ui.title.visible = false
	await _frames(60)
