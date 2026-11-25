extends "res://scripts/tests/world.gd"
## Checks of building and crafting: indoors, precise removal, harvest fixes, stairs, workshops, crafting. (Part of the chain of test files: see tests.gd.)

## Setting things down indoors (user, 22 Nov: "i wasnt able to build decorations or the forging equipment on
## the ground inside a building. it kept saying there was no space, but i could build them on ledges"): in the
## villages' houses, a kiln and a table aimed along each ground floor; how many spots fit, and why the others don't.
func _test_indoors() -> void:
	var in_back: Vector2 = g.player.pos
	for in_m in [Defs.STONE, Defs.BRICK, Defs.PLANK, Defs.SAND, Defs.DIRT]:
		g.player.inv[in_m] += 200
	var in_rows := []
	var in_fit := {"kiln": 0, "table": 0}
	var in_tried := {"kiln": 0, "table": 0}
	var in_houses := 0
	var in_bad := 0
	var in_built := {"kiln": 0, "table": 0}
	var in_built_n := {"kiln": 0, "table": 0}
	for in_t in g.builds.towns:
		if not bool(in_t.get("living", false)) or in_houses >= 5:
			continue
		for in_h in in_t["houses"]:
			if bool(in_h.get("ruined", false)) or in_houses >= 5:
				continue
			in_houses += 1
			var hx0: int = int(in_h["x0"])
			var hw: int = int(in_h["w"])
			var hf: int = int(in_h["floor"])
			_go(_cell_pos(hx0 + hw / 2, hf - 10))
			await _frames(30)
			if not g.build_on:
				g._toggle_build()
			for in_kind in ["kiln", "table"]:
				g.build_cat = Build.CAT_WORKSHOPS if in_kind == "kiln" else 2
				var in_list: Array = g.build_list()
				for in_k in in_list.size():
					if String(in_list[in_k]["name"]) == ("Kiln" if in_kind == "kiln" else "Table"):
						g.build_idx[g.build_cat] = in_k
				var in_whys := {}
				var cc := hx0 + 8
				while cc < hx0 + hw - 8:
					g.test_aim = _cell_pos(cc, hf - 6)
					await _frames(5)               # (a piece is slid into place once the cursor rests)
					in_tried[in_kind] += 1
					if g.build_prev.get("ok", false):
						in_fit[in_kind] += 1
					else:
						var wy: String = g.build_why
						in_whys[wy] = int(in_whys.get(wy, 0)) + 1
						# (a house's rooms are furnished: furniture or a door in the way is a fair "no"; no
						# floor found on a house's floor is the old bug)
						if not (wy.contains("furniture") or wy.contains("door") or wy.contains("workshop")):
							in_bad += 1
					cc += 7
				in_rows.append("house %s %d..%d floor %d, %s: %s" % [String(in_h.get("role", "?")), hx0, hx0 + hw, hf, in_kind, str(in_whys)])
			g.test_aim = Vector2.ZERO
			if g.build_on:
				g._toggle_build()
	# a house you build yourself (on a slab of natural stone up in open air), then the same inside it
	for in_mt in [Defs.PLANK, Defs.WOOD, Defs.MASONRY, Defs.TILE, Defs.BRICK, Defs.SANDSTONE, Defs.DRYGRASS, Defs.TORCH, Defs.GLASS]:
		g.player.inv[in_mt] += 3000
	var in_a := atan2(g.player.pos.y, g.player.pos.x) - 0.5
	var in_up := Vector2(cos(in_a), sin(in_a))
	var in_c: Vector2i = Build.cell_of(in_up * (g.gpu.surf_at(in_a).x + 160.0))
	var IW := 120
	var in_d := PackedInt32Array()
	in_d.resize(IW * 20)
	in_d.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)
	g.stamps.append({"x0": posmod(in_c.x, Defs.NS), "y0": in_c.y, "w": IW, "h": 20, "data": in_d, "ax": in_c.x, "aw": IW})
	await _frames(4)
	var in_mid := in_c.x + IW / 2
	_go(_cell_pos(in_mid + 40, in_c.y - 12, in_c.x, IW))
	await _frames(30)
	if not g.build_on:
		g._toggle_build()
	g.build_cat = 4
	g.build_idx[4] = 0
	g.build_style = 0
	g.build_w = 40
	g.build_floors = 1
	g.test_aim = _cell_pos(in_mid, in_c.y - 3, in_c.x, IW)
	await _frames(4)
	var in_house_ok: bool = g.build_prev.get("ok", false)
	g.build_click = true
	await _frames(30)
	for in_kind2 in ["kiln", "table"]:
		g.build_cat = Build.CAT_WORKSHOPS if in_kind2 == "kiln" else 2
		var in_list2: Array = g.build_list()
		for in_k2 in in_list2.size():
			if String(in_list2[in_k2]["name"]) == ("Kiln" if in_kind2 == "kiln" else "Table"):
				g.build_idx[g.build_cat] = in_k2
		var in_whys2 := {}
		for dx in [-12, -6, 0, 6, 12]:
			for dy in [-2, -6, 0]:
				g.test_aim = _cell_pos(in_mid + dx, in_c.y + dy, in_c.x, IW)
				await _frames(5)
				in_built_n[in_kind2] += 1
				if g.build_prev.get("ok", false):
					in_built[in_kind2] += 1
				else:
					var wy2: String = g.build_why
					in_whys2[wy2] = int(in_whys2.get(wy2, 0)) + 1
		in_rows.append("a house you build (made %s) floor %d, %s: %s" % [in_house_ok, in_c.y, in_kind2, str(in_whys2)])
	g.test_aim = Vector2.ZERO
	if g.build_on:
		g._toggle_build()
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("indoors_built.png"))
	for r in in_rows:
		print("[indoors] " + r)
	# (the slab and the house on it are taken away again: nothing left hanging over the checks after this)
	var in_clr := PackedInt32Array()
	in_clr.resize((IW + 40) * 90)
	in_clr.fill(Defs.AIR | (Defs.AIR << 8))
	g.stamps.append({"x0": posmod(in_c.x - 20, Defs.NS), "y0": in_c.y - 70, "w": IW + 40, "h": 90, "data": in_clr, "ax": in_c.x, "aw": IW})
	for in_dr in g.doors.duplicate():
		if (in_dr["pos"] as Vector2).distance_to(_cell_pos(in_mid, in_c.y - 20, in_c.x, IW)) < 90.0:
			g.doors.erase(in_dr)
	_go(in_back)
	await _frames(20)
	# (since 23 Nov a workshop never stands over furniture, nor furniture behind a workshop: in a village's
	# furnished rooms most spots are rightly refused, so they're judged by the reasons given)
	_ok("indoors, workshops and furniture go down on a house's floor", in_houses > 0 and in_bad == 0 and in_fit["kiln"] + in_fit["table"] > 0 and in_built["kiln"] * 2 >= in_built_n["kiln"] and in_built["table"] * 2 >= in_built_n["table"],
		"%d village houses: kiln fits %d of %d spots, table %d of %d, %d refused for a wrong reason; a house you build: kiln %d of %d, table %d of %d" % [in_houses, in_fit["kiln"], in_tried["kiln"], in_fit["table"], in_tried["table"], in_bad, in_built["kiln"], in_built_n["kiln"], in_built["table"], in_built_n["table"]])

## Taking away precisely and torches as one piece (user, 22 Nov): on a slab of natural stone up in open
## air, a back wall with planks and a table in front of it; the Remove tab takes the furniture only (the
## wall comes back behind it), then the blocks only, then one cell of wall; a cell taken from an anchored
## building wakes what's round it; torches go down one at a time (standing on a floor, on a wall, by
## Conjure), light the place and come back whole; Flatten cuts a mound and fills a dip.
func _test_remove() -> void:
	var rm_back: Vector2 = g.player.pos
	var rm_time0: float = g.time
	var m = g.player
	m.inv[Defs.DIRT] += 60
	var rm_a := atan2(m.pos.y, m.pos.x) + 0.14
	var rm_up := Vector2(cos(rm_a), sin(rm_a))
	var c0: Vector2i = Build.cell_of(rm_up * (g.gpu.surf_at(rm_a).x + 150.0))
	var cx: int = c0.x
	var top: int = c0.y                   # the slab's top row
	var fl := top - 1                     # the open row on it
	# (20 thick: what's taken wakes the rock within 15 of it, and a thin slab hanging in the air, woken,
	# would give way under what's built on it; the planet's ground is held by the rest of the planet)
	var SW := 120
	var SH := 20
	var sd := PackedInt32Array()
	sd.resize(SW * SH)
	sd.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top, "w": SW, "h": SH, "data": sd})
	# an anchored built block hanging under its far end (as a generated building is)
	var hd := PackedInt32Array()
	hd.resize(8 * 8)
	hd.fill(Defs.MASONRY | 0xFF00 | 0x20000)
	g.stamps.append({"x0": posmod(cx + 104, Defs.NS), "y0": top + SH, "w": 8, "h": 8, "data": hd})
	await _frames(4)
	_go(_cell_pos(cx + 40, fl - 12))
	await _frames(30)
	var txt := []
	var ok := {}
	# a wall, planks in front of it, a table in front of it
	g.stamps.append(Build.shape_stamp(Build.shape_cells(Vector2i(cx + 10, fl - 15), Vector2i(cx + 33, fl), 2, 1), Defs.MASONRY, true))
	g.stamps.append(Build.shape_stamp(Build.shape_cells(Vector2i(cx + 12, fl - 3), Vector2i(cx + 17, fl), 2, 1), Defs.PLANK, false))
	var tab: Dictionary = Build.design({"prop": "table"}, 7)
	g.stamps.append(Build.prop_stamp(Build.prop_cells(tab["rows"], cx + 26, fl, false), Build.Props.kind_id("table")))
	await _frames(12)
	var count := func() -> Vector3i:
		var rr: Dictionary = g.gpu.read_rect(posmod(cx + 8, Defs.NS), fl - 18, 28, 20)
		var pl := 0
		var wl := 0
		var dc := 0
		for v in rr["fg"]:
			if (int(v) & 255) == Defs.PLANK:
				pl += 1
		for b in rr["bg"]:
			if (int(b) & 255) == Defs.MASONRY:
				wl += 1
			elif (int(b) & 255) == Defs.DECOR:
				dc += 1
		return Vector3i(pl, wl, dc)
	var n0: Vector3i = count.call()
	var area: Array = Build.shape_cells(Vector2i(cx + 8, fl - 17), Vector2i(cx + 35, fl), 2, 1)
	var pl0: int = m.inv[Defs.PLANK]
	g.remove_cells(m, area, "furn")
	await _frames(12)
	var n1: Vector3i = count.call()
	g.remove_cells(m, area, "front")
	await _frames(12)
	var n2: Vector3i = count.call()
	g.remove_cells(m, [Vector2i(cx + 20, fl - 8)], "back")
	await _frames(12)
	var n3: Vector3i = count.call()
	ok["layers"] = n0.x >= 20 and n0.z > 10 and n1.z == 0 and n1.x == n0.x and n1.y >= n0.y + n0.z - 4 \
		and n2.x == 0 and n2.y == n1.y and n3.y == n2.y - 1 and m.inv[Defs.PLANK] >= pl0 + n0.x
	txt.append("planks/wall/furniture %s, furniture taken %s, blocks taken %s, a cell of wall %s" % [str(n0), str(n1), str(n2), str(n3)])
	# a cell taken from an anchored building wakes what's round it
	var anch := func() -> int:
		var rr2: Dictionary = g.gpu.read_rect(posmod(cx + 104, Defs.NS), top + SH, 8, 8)
		var na := 0
		for v2 in rr2["fg"]:
			if (int(v2) & 255) == Defs.MASONRY and (int(v2) & 0x40000000) != 0:
				na += 1
		return na
	_go(_cell_pos(cx + 100, top + SH + 14))
	await _frames(20)
	var an0: int = anch.call()
	g.remove_cells(m, [Vector2i(cx + 108, top + SH + 7)], "front")
	await _frames(12)
	var an1: int = anch.call()
	ok["wake"] = an0 >= 60 and an1 <= 10
	txt.append("anchored block: %d anchored cells, %d after taking one" % [an0, an1])
	# torches: standing on the floor, on the wall, by Conjure; light; taken up whole
	_go(_cell_pos(cx + 40, fl - 12))
	await _frames(20)
	m.inv[Defs.TORCH] = 6
	var t_stand: bool = g.place_torch(m, _cell_pos(cx + 45, fl - 4))
	var t_wall: bool = g.place_torch(m, _cell_pos(cx + 22, fl - 10))
	var tk: Dictionary = g.torch_plan(Vector2i(cx + 22, fl - 10))
	m.mat = Defs.TORCH
	m.cast_latch = false
	g._conjure(m, _cell_pos(cx + 55, fl - 3))
	var inv_after: int = m.inv[Defs.TORCH]
	await _frames(20)
	var rr3: Dictionary = g.gpu.read_rect(posmod(cx + 8, Defs.NS), fl - 18, 60, 20)
	var flames := 0
	for b3 in rr3["bg"]:
		if (int(b3) & 255) == Defs.TORCH:
			flames += 1
	g.lights.clear()
	g._torch_lights()
	var lit := 0
	for L in g.lights:
		if absf(float(L[1]) - Build.TORCH_R) < 10.0:
			lit += 1
	var nt: int = (g.planet_state.get("torches", []) as Array).size()
	for tq in g.planet_state.get("torches", []):
		var tfc: Vector2i = Build.cell_of(Vector2(float(tq[0]), float(tq[1])))
		print("[torch] flame at %s from the slab's corner, background %d" % [str(tfc - Vector2i(cx, fl)), g._bg_at(tfc.x, tfc.y)])
	ok["torches"] = t_stand and t_wall and inv_after == 3 and flames >= 15 and lit >= 3 and nt >= 3 and not bool(tk["standing"])
	txt.append("placed standing %s, on the wall %s, by Conjure (torches 6 -> %d), flame cells %d, lights %d, remembered %d" % [t_stand, t_wall, inv_after, flames, lit, nt])
	# a picture at night
	var na_a: float = atan2(m.pos.y, m.pos.x)
	g.time = fposmod((na_a + PI - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)
	await _frames(30)
	_shot("torches_night.png")
	g.time = rm_time0
	var inv_t: int = m.inv[Defs.TORCH]
	var up_ok: bool = g._pick_up_furniture(m, _cell_pos(cx + 45, fl - 4))
	await _frames(70)
	g._check_torches()
	var nt2: int = (g.planet_state.get("torches", []) as Array).size()
	ok["take"] = up_ok and m.inv[Defs.TORCH] == inv_t + 1 and nt2 == nt - 1
	txt.append("taken up: %s, torches %d -> %d, remembered %d -> %d" % [up_ok, inv_t, m.inv[Defs.TORCH], nt, nt2])
	# flatten: a mound cut, a dip filled
	g.stamps.append(Build.shape_stamp(Build.shape_cells(Vector2i(cx + 70, fl - 3), Vector2i(cx + 80, fl), 2, 1), Defs.DIRT, false))
	var dip := PackedInt32Array()
	dip.resize(6 * 2)
	dip.fill(0xFF00)
	g.stamps.append({"x0": posmod(cx + 86, Defs.NS), "y0": top, "w": 6, "h": 2, "data": dip})
	_go(_cell_pos(cx + 80, fl - 14))
	await _frames(20)
	var plan: Dictionary = g.flatten_plan(Vector2i(cx + 66, top), Vector2i(cx + 96, top))
	var fr: Dictionary = g.flatten_apply(m, plan, Defs.DIRT)
	await _frames(20)
	var rr4: Dictionary = g.gpu.read_rect(posmod(cx + 66, Defs.NS), fl - 4, 31, 7)
	var above := 0
	var holes := 0
	for j in 7:
		for i in 31:
			var t4: int = int(rr4["fg"][j * 31 + i]) & 255
			# (ground left standing; rain or snow falling through doesn't count)
			if j < 5 and t4 != 0 and Defs.KIND[t4] == Defs.K_SOLID and t4 != Defs.SNOW:
				above += 1
			if j >= 5 and t4 == 0:
				holes += 1
	ok["flatten"] = int(fr["cut"]) >= 40 and int(fr["fill"]) >= 10 and above == 0 and holes == 0
	txt.append("flatten: cut %d, filled %d; left above the line %d, holes in the ground %d" % [int(fr["cut"]), int(fr["fill"]), above, holes])
	# shaping is magic: taking costs mana by hardness, with none left nothing happens, digging drains it
	g.free_magic = false
	m.mana = m.max_mana
	var mn0: float = m.mana
	var rs: Dictionary = g.remove_cells(m, Build.shape_cells(Vector2i(cx + 100, top), Vector2i(cx + 109, top + 3), 2, 1), "front")
	var mn_spent: float = mn0 - m.mana
	var want: float = 40.0 * g.dig_mana(Defs.STONE)
	m.mana = 0.0
	var rs0: Dictionary = g.remove_cells(m, [Vector2i(cx + 100, top + 6)], "front")
	var nb0: int = g.brushes.size()
	g._excavate(m, _cell_pos(cx + 102, top + 6))
	var nb1: int = g.brushes.size()
	m.mana = m.max_mana
	_go(_cell_pos(cx + 60, top - 10))
	await _frames(10)
	g.test_aim = _cell_pos(cx + 60, top + 2)
	g.test_dig = true
	await _frames(30)
	_shot("dig_magic.png")
	await _frames(10)
	g.test_dig = false
	g.test_aim = Vector2.ZERO
	var dug_spent: float = m.max_mana - m.mana
	g.free_magic = true
	ok["mana"] = int(rs["n"]) == 40 and absf(mn_spent - want) < 0.5 and int(rs0["n"]) == 0 and nb1 == nb0 and dug_spent > 2.0
	txt.append("mana: taking 40 stone cost %.1f (%.1f), with none left took %d, dug with none: %d brushes; digging 40 frames spent %.1f" % [mn_spent, want, int(rs0["n"]), nb1 - nb0, dug_spent])
	_go(rm_back)
	await _frames(20)
	var all_ok := true
	var bad := []
	for k in ok:
		if not ok[k]:
			all_ok = false
			bad.append(k)
	_ok("precise removal (a layer at a time, physics wakes), flatten, and torches as one piece with their own light", all_ok,
		"; ".join(txt) + ("" if all_ok else " (not working: %s)" % ", ".join(bad)))

## (user, 25 Nov) four things he met: standing on a tower top he slowly slid in the wind; digging the sand
## a burrower was in made it vanish; carried pieces of one name were separate entries in the Satchel tab;
## taking a torch's flame on its own left its cup as a put-out "decoration". On a natural slab in the air.
func _test_harvest() -> void:
	var hv_back: Vector2 = g.player.pos
	var m = g.player
	# (clear weather: rain puts a torch's flame out)
	var hv_w0 := [g.rain, g.rain_target, g.weather_timer]
	g.rain = 0.0
	g.rain_target = 0.0
	g.weather_timer = 999999
	var ha := atan2(m.pos.y, m.pos.x) - 0.16
	var hup := Vector2(cos(ha), sin(ha))
	var c0: Vector2i = Build.cell_of(hup * (g.gpu.surf_at(ha).x + 150.0))
	var cx: int = c0.x
	var top: int = c0.y
	var fl := top - 1
	var SW := 110
	var SH := 26
	var sd := PackedInt32Array()
	sd.resize(SW * SH)
	sd.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)
	# a bed of sand in the slab's top for the burrower (columns 62..99, 16 deep), stone under it
	for j in 16:
		for i in range(62, 100):
			sd[j * SW + i] = Defs.SAND | 0xFF00 | 0x20000 | 0x80000
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top, "w": SW, "h": SH, "data": sd})
	await _frames(4)
	_go(_cell_pos(cx + 10, fl - 12))
	await _frames(40)
	var ok := {}
	var txt := []
	# ---- the wind: standing still in a gale on the open slab, he stays where he stands ----
	var a0: float = atan2(m.pos.y, m.pos.x)
	var stood := 0
	for f in 150:
		g.wind = 1.6
		await _frames(1)
		if m.on_ground:
			stood += 1
	var drift: float = absf(angle_difference(a0, atan2(m.pos.y, m.pos.x))) * m.pos.length()
	ok["wind"] = g.exposed and stood > 120 and drift < 1.0
	txt.append("in a %.1f wind, out in the open %s, standing %d of 150 frames, drifted %.2f cells" % [g.wind, g.exposed, stood, drift])
	g.wind = 0.0
	# ---- torches: picked up by the flame, by the cup, and a put-out stump is a torch again ----
	m.inv[Defs.TORCH] = 4
	var t_ok: bool = g.place_torch(m, _cell_pos(cx + 22, fl - 4))
	# (a sconce hangs on a back wall, as in the game: one hanging in the air comes down as a loose piece)
	g.stamps.append(Build.shape_stamp(Build.shape_cells(Vector2i(cx + 28, fl - 12), Vector2i(cx + 36, fl), 2, 1), Defs.MASONRY, true))
	await _frames(2)
	g.stamps.append(Build.prop_stamp(Build.prop_cells(Build.SCONCE, cx + 32, fl - 2, false), 0))
	g.stamps.append(Build.prop_stamp(Build.prop_cells(Build.SCONCE.slice(3), cx + 42, fl, false), 0))
	await _frames(12)
	var torch_cells := func() -> int:
		var rr: Dictionary = g.gpu.read_rect(posmod(cx + 14, Defs.NS), fl - 16, 36, 17)
		var nn := 0
		for b in rr["bg"]:
			var mb := int(b) & 255
			if mb == Defs.DECOR or mb == Defs.TORCH:
				nn += 1
		return nn
	var tc0: int = torch_cells.call()
	var inv0: int = m.inv[Defs.TORCH]
	var furn0: int = m.furn.size()
	# the standing torch by the cell over its flame's top, the sconce by its flame's top cell
	var flame_c: Vector2i = Build.cell_of(Vector2(float(g.planet_state["torches"][-1][0]), float(g.planet_state["torches"][-1][1])))
	g._pick_miss_t = -9999
	var p1: bool = g._pick_up_furniture(m, _cell_pos(flame_c.x, flame_c.y - 2))
	await _frames(6)
	# (the sconce hangs in the open air with nothing behind it, and a cell or two of its flame can go out:
	# point at its highest flame cell still burning)
	var sc_aim := Vector2i(cx + 32, fl - 8)
	var rs: Dictionary = g.gpu.read_rect(posmod(cx + 29, Defs.NS), fl - 9, 7, 9)
	for sj in 9:
		var hit := false
		for si in 7:
			if (int(rs["bg"][sj * 7 + si]) & 255) == Defs.TORCH:
				sc_aim = Vector2i(cx + 29 + si, fl - 9 + sj)
				hit = true
				break
		if hit:
			break
	g._pick_miss_t = -9999
	var p2: bool = g._pick_up_furniture(m, _cell_pos(sc_aim.x, sc_aim.y))
	await _frames(6)
	g._pick_miss_t = -9999
	var p3: bool = g._pick_up_furniture(m, _cell_pos(cx + 42, fl - 2))
	await _frames(12)
	for fi in range(furn0, m.furn.size()):
		print("[harvest] carried instead of a torch: %s %s kind %d" % [m.furn[fi]["name"], str(m.furn[fi]["rows"]), int(m.furn[fi].get("kind", -1))])
	var tc1: int = torch_cells.call()
	ok["torch"] = t_ok and tc0 >= 25 and p1 and p2 and p3 and m.inv[Defs.TORCH] == inv0 + 3 and m.furn.size() == furn0 and tc1 == 0
	txt.append("torch cells %d -> %d; taken by the flame %s, the sconce's flame %s, the stump %s; torches %d -> %d, carried pieces %d -> %d" % [tc0, tc1, p1, p2, p3, inv0, m.inv[Defs.TORCH], furn0, m.furn.size()])
	# ---- carried pieces of one name stack in the Satchel tab; R shows the next design ----
	var furn_keep: Array = m.furn.duplicate(true)
	var chair_a: Dictionary = Build.carried_item("Chair", Build.design({"prop": "chair"}, 3), "chair")
	var chair_b: Dictionary = Build.carried_item("Chair", Build.design({"prop": "chair"}, 9), "chair")
	var table_a: Dictionary = Build.carried_item("Table", Build.design({"prop": "table"}, 5), "table")
	m.furn = [chair_a, table_a, chair_b, chair_a.duplicate(true)]
	var lst: Array = Build.carried_pieces(m.furn, {}, PackedInt32Array())
	var chairs: Dictionary = lst[0] if lst.size() > 0 else {}
	if not g.build_on:
		g._toggle_build()
	g.build_cat = Build.CAT_SATCHEL
	g.select_carried(2)
	var held: Dictionary = g.build_piece()
	g._build_key(KEY_R)
	var held2: Dictionary = g.build_piece()
	g._toggle_build()
	ok["stack"] = lst.size() == 2 and int(chairs.get("carried", 0)) == 3 and String(chairs.get("name", "")) == "Chair" \
		and int(held.get("item", -1)) == 2 and int(held2.get("item", -1)) != 2 and String(held2.get("name", "")) == "Chair"
	txt.append("4 carried (3 chairs, a table): %d entries, chairs x%d; picked the 2nd chair (item %d), R -> item %d" % [lst.size(), int(chairs.get("carried", 0)), int(held.get("item", -1)), int(held2.get("item", -1))])
	m.furn = furn_keep
	g.carried_pick = {}
	# ---- a burrower in sand, dug round: it's thrown out onto the ground, then digs back in ----
	var bc := cx + 80
	var bp: Vector2 = _cell_pos(bc, fl + 7)
	var wasnt_wild: bool = g.test_no_wild
	var e = g.spawn_enemy("c_sandviper", bp)
	e.under = true
	e.asleep = true
	await _frames(10)
	var in0: bool = e.was_in and e.under and not e.dead
	var ec: Vector2i = Build.cell_of(e.pos)
	var hole := PackedInt32Array()
	hole.resize(12 * 12)
	hole.fill(0xFF00)
	g.stamps.append({"x0": posmod(ec.x - 6, Defs.NS), "y0": ec.y - 6, "w": 12, "h": 12, "data": hole})
	var out_seen := false
	var back_in := false
	for f2 in 600:
		await _frames(1)
		if e.dead:
			break
		if f2 % 40 == 0:
			var eo: Vector2i = Build.cell_of(e.pos) - Vector2i(cx, fl)
			print("[harvest] burrower f%d at %s from the slab, under %s, stranded %d, ground %s, goal %s, act '%s', asleep %s" % [f2, str(eo),
				e.under, e.stranded_t, e.on_ground, str(Build.cell_of(e.goal_p) - Vector2i(cx, fl)) if e.goal_p != Vector2.ZERO else "-", e.act, e.asleep])
		if not e.under and e.stranded_t > 0:
			out_seen = true
		elif out_seen and e.under:
			back_in = true
			break
	# again with a pit too deep to dig into at its bottom (3 rows of sand left over the stone): it tunnels
	# into the pit's side
	var back2 := false
	var out2 := false
	if back_in and not e.dead:
		await _frames(20)
		var ec2: Vector2i = Build.cell_of(e.pos)
		var pit_top := fl - 2
		var pit_h := maxi(top + 13, ec2.y + 2) - pit_top     # (down past the worm, wherever it dug back in)
		var pit := PackedInt32Array()
		pit.resize(12 * pit_h)
		pit.fill(0xFF00)
		g.stamps.append({"x0": posmod(ec2.x - 6, Defs.NS), "y0": pit_top, "w": 12, "h": pit_h, "data": pit})
		for f3 in 600:
			await _frames(1)
			if e.dead:
				break
			if f3 % 60 == 0:
				var eo2: Vector2i = Build.cell_of(e.pos) - Vector2i(cx, fl)
				print("[harvest] in the pit f%d at %s, under %s, stranded %d, ground %s, goal %s" % [f3, str(eo2), e.under, e.stranded_t, e.on_ground,
					str(Build.cell_of(e.goal_p) - Vector2i(cx, fl)) if e.goal_p != Vector2.ZERO else "-"])
			if not e.under and e.stranded_t > 0:
				out2 = true
			elif out2 and e.under:
				back2 = true
				break
	ok["burrower"] = in0 and out_seen and back_in and out2 and back2 and not e.dead
	txt.append("in its sand %s; dug round: thrown out %s, dug back in %s; a pit too deep: out %s, into its side %s; alive %s" % [in0, out_seen, back_in, out2, back2, not e.dead])
	e.dead = true
	g.enemies.erase(e)
	g.test_no_wild = wasnt_wild
	# take the slab away again
	var clr := PackedInt32Array()
	clr.resize(SW * (SH + 20))
	clr.fill(0xFF00 | 0x40000)
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top - 20, "w": SW, "h": SH + 20, "data": clr})
	g.rain = float(hv_w0[0])
	g.rain_target = float(hv_w0[1])
	g.weather_timer = int(hv_w0[2])
	_go(hv_back)
	await _frames(30)
	var all_ok := true
	var bad := []
	for k in ok:
		if not ok[k]:
			all_ok = false
			bad.append(k)
	_ok("harvest fixes: no sliding in the wind standing still, a torch taken whole by any part, carried pieces stack, a dug-out burrower comes out", all_ok,
		"; ".join(txt) + ("" if all_ok else " (not working: %s)" % ", ".join(bad)))

func _test_stairs() -> void:
	var sr_back: Vector2 = g.player.pos
	g.player.inv[Defs.PLANK] += 400
	g.player.inv[Defs.WOOD] += 200
	var sr_foot := 0
	var sr_gr := 0
	var sr_fit := false
	var sr_why := ""
	if not g.build_on:
		g._toggle_build()
	g.build_cat = 1
	var sr_list: Array = g.build_list()
	for sr_k in sr_list.size():
		if String(sr_list[sr_k]["name"]) == "Wooden Stairs":
			g.build_idx[1] = sr_k
	g.build_flip = false
	g.build_rise = 40
	# (on a slab of stone up in open air, so no tree or house is in its way, wherever you arrived)
	var sr_a := atan2(g.player.pos.y, g.player.pos.x) - 0.12
	var sr_up := Vector2(cos(sr_a), sin(sr_a))
	var sr_c: Vector2i = Build.cell_of(sr_up * (g.gpu.surf_at(sr_a).x + 150.0))
	var SRW := 110
	var sr_d := PackedInt32Array()
	sr_d.resize(SRW * 4)
	sr_d.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)     # (natural rock: a built slab would wake with the stairs on it and fall)
	g.stamps.append({"x0": posmod(sr_c.x, Defs.NS), "y0": sr_c.y, "w": SRW, "h": 4, "data": sr_d, "ax": sr_c.x, "aw": SRW})
	await _frames(4)
	sr_foot = sr_c.x + 70                         # it climbs toward lower columns (right on screen)
	sr_gr = sr_c.y
	_go(_cell_pos(sr_foot + 18, sr_gr - 12, sr_c.x, SRW))
	await _frames(30)
	g.test_aim = _cell_pos(sr_foot, sr_gr - 3, sr_c.x, SRW)
	await _frames(4)
	sr_fit = g.build_prev.get("ok", false)
	sr_why = g.build_why
	var sr_cost: String = str(g.build_piece().get("cost", {}))
	g.build_click = true
	await _frames(20)
	g.test_aim = Vector2.ZERO
	if g.build_on:
		g._toggle_build()
	var sr_count := func() -> int:
		var rr: Dictionary = g.gpu.read_rect(sr_foot - 44, sr_gr - 50, 48, 60)
		var n := 0
		for v in rr["fg"]:
			if (int(v) & 255) == Defs.PLANK:
				n += 1
		return n
	await _frames(10)
	var sr_n0: int = sr_count.call()
	await _frames(240)
	var sr_n1: int = sr_count.call()
	# walk up it
	_go(_cell_pos(sr_foot + 10, sr_gr - 12, sr_c.x, SRW))
	await _frames(40)
	var sr_r0: float = g.player.pos.length()
	var sr_best := 0.0
	g.test_move = 1
	for sr_f in 300:
		await _frames(1)
		sr_best = maxf(sr_best, g.player.pos.length() - sr_r0)
		if sr_best >= 38.0:
			break
	g.test_move = 0
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("stairs.png"))
	# (cleared away again: the slab, the flight, its posts and rail)
	var sr_clear := PackedInt32Array()
	sr_clear.resize(SRW * 64)
	sr_clear.fill(Defs.AIR)
	g.stamps.append({"x0": posmod(sr_c.x, Defs.NS), "y0": sr_c.y - 60, "w": SRW, "h": 64, "data": sr_clear, "ax": sr_c.x, "aw": SRW})
	_go(sr_back)
	await _frames(10)
	_ok("build mode: a staircase stands on its posts and you walk up it", sr_fit and sr_n0 >= 120 and sr_n1 >= sr_n0 * 0.95 and sr_best >= 32.0,
		"fits %s (%s), cost %s; %d plank cells placed, %d four seconds later; walking up it you rose %.0f of its 40" % [sr_fit, sr_why, sr_cost, sr_n0, sr_n1, sr_best])

## Workshops (workshops.gd; user, 22 Nov: real kilns and smelters, a quarter better at an anvil, secrets
## found by experimenting): on a slab of rock up in open air, a Kiln set down from build mode; it fires
## sand into glass batch after batch (fuel burns), a mix it doesn't know does nothing, a secret mix is a
## discovery; a Smelter makes copper ingots; a Still's secret draught works through gear(); ore gear
## forged at an anvil is masterwork; sparks set planks beside a lit kiln alight; saved and loaded, taken
## up again; a picture of the four lit (`workshops.png`) and of a panel (`workshop_panel.png`).
func _test_workshops() -> void:
	var ws = g.workshops
	var wk_back: Vector2 = g.player.pos
	var wk_items0: Dictionary = g.items.duplicate(true)
	var wk_n0: int = ws.list.size()
	var wk_w0 := [g.rain, g.rain_target, g.weather_timer]     # (clear weather: rain pooling round a station puts its fire out)
	g.rain = 0.0
	g.rain_target = 0.0
	g.weather_timer = 999999
	var wk_rows := []
	var wk_ok := true
	for wk_m in [Defs.STONE, Defs.DIRT, Defs.SAND, Defs.COAL, Defs.COPPER, Defs.ASH, Defs.SHROOM, Defs.EMBER, Defs.WATER, Defs.BRICK, Defs.GLASS, Defs.PLANK, Defs.LEAF]:
		g.player.inv[wk_m] += 60
	# the slab
	# (well away from where you arrived: the wild-life checks are set up there, and the burning cage's ash falls)
	var wk_a := atan2(g.player.pos.y, g.player.pos.x) + 0.45
	var wk_up := Vector2(cos(wk_a), sin(wk_a))
	var wk_c: Vector2i = Build.cell_of(wk_up * (g.gpu.surf_at(wk_a).x + 150.0))
	var WKW := 150
	var wk_d := PackedInt32Array()
	wk_d.resize(WKW * 4)
	wk_d.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)
	g.stamps.append({"x0": posmod(wk_c.x, Defs.NS), "y0": wk_c.y, "w": WKW, "h": 4, "data": wk_d, "ax": wk_c.x, "aw": WKW})
	await _frames(4)
	var wk_gr := wk_c.y
	var wk_mid := wk_c.x + WKW / 2
	_go(_cell_pos(wk_mid + 30, wk_gr - 12, wk_c.x, WKW))
	await _frames(30)
	# a kiln from build mode
	if not g.build_on:
		g._toggle_build()
	g.build_cat = Build.CAT_WORKSHOPS
	var wk_list: Array = g.build_list()
	for wk_k in wk_list.size():
		if String(wk_list[wk_k]["name"]) == "Kiln":
			g.build_idx[Build.CAT_WORKSHOPS] = wk_k
	g.build_flip = false
	var wk_stone0: int = g.player.inv[Defs.STONE]
	g.test_aim = _cell_pos(wk_mid, wk_gr - 9, wk_c.x, WKW)
	await _frames(4)
	var wk_fit: bool = g.build_prev.get("ok", false)
	var wk_why: String = g.build_why
	g.build_click = true
	await _frames(10)
	g.test_aim = Vector2.ZERO
	if g.build_on:
		g._toggle_build()
	var kiln = ws.list[ws.list.size() - 1] if ws.list.size() > wk_n0 else null
	var wk_ok1: bool = wk_fit and kiln != null and kiln.kind == "kiln" and g.player.inv[Defs.STONE] == wk_stone0 - 24
	wk_rows.append("%sa kiln set down from build mode: fits %s (%s), %d stations, stone paid %d" % ["" if wk_ok1 else "(!) ", wk_fit, wk_why, ws.list.size(), wk_stone0 - g.player.inv[Defs.STONE]])
	wk_ok = wk_ok and wk_ok1
	if kiln == null:
		kiln = ws.add("kiln", _cell_pos(wk_mid, wk_gr - 9, wk_c.x, WKW))
	await _frames(60)
	var wk_sat: bool = kiln.on_ground
	# the other three, along the slab
	var smelter = ws.add("smelter", _cell_pos(wk_mid - 30, wk_gr - 13, wk_c.x, WKW))
	var still = ws.add("still", _cell_pos(wk_mid + 26, wk_gr - 9, wk_c.x, WKW))
	var anvil = ws.add("anvil", _cell_pos(wk_mid + 48, wk_gr - 6, wk_c.x, WKW))
	await _frames(60)
	# furniture can't be set down where a workshop stands, nor a workshop over furniture (user, 23 Nov: part
	# of a bed went behind the kiln)
	var wk_bed: Array = Build.design({"prop": "bed"}, 3)["rows"]
	var wk_pf: Dictionary = g._prop_fit(wk_bed, false, wk_mid, wk_gr - 6)
	var wk_ok0: bool = not wk_pf["ok"] and String(wk_pf["why"]).contains("workshop")
	wk_rows.append("%sa bed where the kiln stands: fits %s (%s)" % ["" if wk_ok0 else "(!) ", wk_pf["ok"], wk_pf["why"]])
	wk_ok = wk_ok and wk_ok0
	# glass, batch after batch
	ws.load_mat(kiln, Defs.SAND, 8)
	ws.add_fuel(kiln, Defs.COAL, 2)
	var wk_f0: float = kiln.fuel
	for wk_t in 1200:
		ws.work_all()
	var wk_glass := int(kiln.out.get("m%d" % Defs.GLASS, 0))
	var wk_ok2: bool = wk_glass == 8 and kiln.store.is_empty() and kiln.fuel < wk_f0 and kiln.fuel > 0.0
	wk_rows.append("%ssand fired into glass: %d glass, %s left in, fuel %.0f -> %.0f" % ["" if wk_ok2 else "(!) ", wk_glass, str(kiln.store), wk_f0, kiln.fuel])
	wk_ok = wk_ok and wk_ok2
	var wk_g0: int = g.player.inv[Defs.GLASS]
	ws.take_out(kiln)
	var wk_ok3: bool = g.player.inv[Defs.GLASS] == wk_g0 + 8 and kiln.out.is_empty()
	# a mix it doesn't know: nothing
	ws.load_mat(kiln, Defs.SAND, 4)
	ws.load_mat(kiln, Defs.DIRT, 3)
	for wk_t2 in 600:
		ws.work_all()
	wk_ok3 = wk_ok3 and kiln.out.is_empty() and ws.match_process(kiln).is_empty() and not kiln.lit
	ws.unload(kiln, Defs.SAND)
	ws.unload(kiln, Defs.DIRT)
	wk_rows.append("%staken out (%d glass now), and sand with dirt makes nothing: %s" % ["" if wk_ok3 else "(!) ", g.player.inv[Defs.GLASS], str(kiln.out)])
	wk_ok = wk_ok and wk_ok3
	# a secret: ash and sand
	g.items.erase("secret_k_obsidian")
	ws.load_mat(kiln, Defs.ASH, 3)
	ws.load_mat(kiln, Defs.SAND, 2)
	for wk_t3 in 800:
		ws.work_all()
	var wk_ok4: bool = g.items.has("secret_k_obsidian") and int(kiln.out.get("m%d" % Defs.OBSIDIAN, 0)) == 2
	wk_rows.append("%sa secret mix (ash + sand) found: %s, %s" % ["" if wk_ok4 else "(!) ", g.items.has("secret_k_obsidian"), str(kiln.out)])
	wk_ok = wk_ok and wk_ok4
	ws.take_out(kiln)
	# copper ingots
	ws.load_mat(smelter, Defs.COPPER, 6)
	ws.add_fuel(smelter, Defs.COAL, 2)
	for wk_t4 in 900:
		ws.work_all()
	var wk_bar0: int = g.player.inv[Defs.COPPERBAR]
	ws.take_out(smelter)
	var wk_ok5: bool = g.player.inv[Defs.COPPERBAR] == wk_bar0 + 2
	wk_rows.append("%sthe smelter made %d copper ingots" % ["" if wk_ok5 else "(!) ", g.player.inv[Defs.COPPERBAR] - wk_bar0])
	wk_ok = wk_ok and wk_ok5
	# a secret draught, drunk
	ws.load_mat(still, Defs.SHROOM, 2)
	ws.load_mat(still, Defs.EMBER, 2)
	ws.load_mat(still, Defs.WATER, 4)
	ws.add_fuel(still, Defs.PLANK, 4)
	for wk_t5 in 900:
		ws.work_all()
	ws.take_out(still)
	var wk_had: int = int(g.items.get("d_ember", 0))
	var wk_lava0: float = g.gear("lava_dmg")
	var wk_drank: bool = g.drink_draught(g.player, "d_ember")
	var wk_lava1: float = g.gear("lava_dmg")
	var wk_ok6: bool = wk_had >= 1 and wk_drank and absf(wk_lava1 - wk_lava0 * 0.2) < 0.001 and g.player.buffs.has("d_ember")
	wk_rows.append("%sthe Ember Draught: made %d, drunk %s, lava harm x%.2f -> x%.2f" % ["" if wk_ok6 else "(!) ", wk_had, wk_drank, wk_lava0, wk_lava1])
	wk_ok = wk_ok and wk_ok6
	g.player.buffs.clear()
	# a night-only mix waits for the dark
	g.player.inv[Defs.CRYSTAL] += 2
	g.player.inv[Defs.SNOW] += 8
	ws.load_mat(still, Defs.CRYSTAL, 1)
	ws.load_mat(still, Defs.SNOW, 4)
	var wk_night: bool = ws._night(still)
	var wk_wait: String = ws.waiting(still)
	var wk_ok7: bool = (wk_wait == "night") != wk_night
	wk_rows.append("%sthe Moonlit Draught: night %s, waiting for '%s'" % ["" if wk_ok7 else "(!) ", wk_night, wk_wait])
	wk_ok = wk_ok and wk_ok7
	ws.unload(still, Defs.CRYSTAL)
	ws.unload(still, Defs.SNOW)
	# masterwork at the anvil
	var wk_gear_ok := true
	var wk_dr0: float = g.gear("dig_rate")
	var wk_had_opal: bool = g.items.has("opal")
	var wk_rec: Dictionary = g.recipe_by_id("opal")
	if not wk_had_opal and not wk_rec.is_empty():
		_go(anvil.pos + (anvil.pos.normalized() * 6.0))
		await _frames(10)
		g.items["found_%d" % Defs.FIREOPAL] = true
		for wk_gc in wk_rec["cost"]:
			g.player.inv[int(wk_gc)] += int(wk_rec["cost"][wk_gc])
		var wk_near: bool = g.anvil_near()
		var wk_made: bool = g.craft(wk_rec)
		var wk_dr1: float = g.gear("dig_rate")
		wk_gear_ok = wk_near and wk_made and absf(float(g.items.get("q_opal", 0.0)) - Defs.MASTERWORK) < 0.001 and absf(wk_dr1 - wk_dr0 * (1.0 + 0.5 * Defs.MASTERWORK)) < 0.01
		wk_rows.append("%sthe Fire Opal Focus forged at the anvil (near %s, made %s): dig rate x%.3f -> x%.3f" % ["" if wk_gear_ok else "(!) ", wk_near, wk_made, wk_dr0, wk_dr1])
		g.items.erase("opal")
		g.items.erase("q_opal")
	wk_ok = wk_ok and wk_gear_ok
	# a lit kiln's sparks catch the planks beside it
	_go(_cell_pos(wk_mid + 30, wk_gr - 12, wk_c.x, WKW))
	await _frames(20)
	var wk_kc: Vector2i = Build.cell_of(kiln.pos)
	var wk_pw := PackedInt32Array()
	var PW := 30
	var PH := 22
	wk_pw.resize(PW * PH)
	wk_pw.fill(Defs.AIR)
	for wy in PH:
		for wx in PW:
			if wx < 6 or wx >= PW - 6 or wy < 4:
				wk_pw[wy * PW + wx] = Defs.PLANK | 0x20000
	var wk_px0 := wk_kc.x - PW / 2
	var wk_py0 := wk_gr - PH
	g.stamps.append({"x0": posmod(wk_px0, Defs.NS), "y0": wk_py0, "w": PW, "h": PH, "data": wk_pw, "ax": wk_c.x, "aw": WKW})
	await _frames(6)
	var wk_planks := func() -> int:
		var rr: Dictionary = g.gpu.read_rect(wk_px0, wk_py0, PW, PH, wk_c.x, WKW)
		var n := 0
		for v in rr["fg"]:
			if (int(v) & 255) == Defs.PLANK:
				n += 1
		return n
	var wk_p0: int = wk_planks.call()
	ws.load_mat(kiln, Defs.SAND, 40)
	ws.add_fuel(kiln, Defs.COAL, 4)
	kiln.heat = 1.0
	await _frames(10)
	var wk_caught := 0
	for wk_s in 40:
		if ws._spark(kiln):
			wk_caught += 1
	await _frames(150)
	var wk_p1: int = wk_planks.call()
	var wk_ok8: bool = kiln.lit and wk_caught > 0 and wk_p1 < wk_p0
	wk_rows.append("%sa lit kiln's sparks: %d of 40 caught the planks round it, %d plank cells -> %d" % ["" if wk_ok8 else "(!) ", wk_caught, wk_p0, wk_p1])
	wk_ok = wk_ok and wk_ok8
	# (the fire out: the cage cleared)
	var wk_clr := PackedInt32Array()
	wk_clr.resize(PW * PH)
	wk_clr.fill(Defs.AIR)
	g.stamps.append({"x0": posmod(wk_px0, Defs.NS), "y0": wk_py0, "w": PW, "h": PH, "data": wk_clr, "ax": wk_c.x, "aw": WKW})
	# all four at work, for the picture (midday)
	var wk_time0: float = g.time
	g.time = g.towns.time_for_hour(kiln.pos, 12.0)
	ws.load_mat(smelter, Defs.COPPER, 30)
	ws.add_fuel(smelter, Defs.COAL, 4)
	ws.load_mat(still, Defs.SHROOM, 8)
	ws.load_mat(still, Defs.LEAF, 8)
	ws.load_mat(still, Defs.WATER, 8)
	ws.add_fuel(still, Defs.PLANK, 4)
	_go(_cell_pos(wk_mid + 14, wk_gr - 12, wk_c.x, WKW))      # (between the kiln and the still: not in front of either)
	await _frames(260)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("workshops.png"))
	var wk_lit: bool = kiln.lit and smelter.lit and still.lit
	# the panel
	_go(kiln.pos + kiln.pos.normalized() * 2.0)
	await _frames(10)
	var wk_opened: bool = ws.interact(g.player) and g.state == "station"
	await _frames(12)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("workshop_panel.png"))
	ws.close()
	await _frames(4)
	var wk_ok9: bool = wk_sat and wk_lit and wk_opened and g.state == "play"
	wk_rows.append("%sthe kiln rests on the slab %s; all three fires lit %s (%s %s %s); the panel opened %s and closed" % ["" if wk_ok9 else "(!) ", wk_sat, wk_lit, kiln.lit, smelter.lit, still.lit, wk_opened])
	wk_ok = wk_ok and wk_ok9
	# saved and loaded (through JSON, as a world file keeps it)
	var wk_sd := {}
	ws.save_to(wk_sd)
	var wk_js = JSON.parse_string(JSON.stringify(wk_sd))
	var wk_before: int = ws.list.size()
	var wk_store := str(kiln.store)
	ws.load_from(wk_js)
	var wk_k2 = null
	for wk_st in ws.list:
		if wk_st.kind == "kiln" and wk_st.pos.distance_to(kiln.pos) < 1.0:
			wk_k2 = wk_st
	var wk_ok10: bool = ws.list.size() == wk_before and wk_k2 != null and str(wk_k2.store) == wk_store and absf(wk_k2.fuel - kiln.fuel) < 1.0
	wk_rows.append("%ssaved and loaded: %d stations -> %d, the kiln's load %s -> %s" % ["" if wk_ok10 else "(!) ", wk_before, ws.list.size(), wk_store, str(wk_k2.store) if wk_k2 != null else "-"])
	wk_ok = wk_ok and wk_ok10
	# taken up again (what's in it comes back), and its hint heard from a note
	var wk_sand0: int = g.player.inv[Defs.SAND]
	var wk_took: bool = wk_k2 != null and ws.take_at(g.player, wk_k2.pos)
	var wk_ok11: bool = wk_took and int(g.items.get("st_kiln", 0)) >= 1 and g.player.inv[Defs.SAND] > wk_sand0
	wk_rows.append("%staken up: %s, kilns carried %d, sand back %d" % ["" if wk_ok11 else "(!) ", wk_took, int(g.items.get("st_kiln", 0)), g.player.inv[Defs.SAND] - wk_sand0])
	wk_ok = wk_ok and wk_ok11
	# it's in the satchel with the furniture, and a click there puts it in your hand (user, 23 Nov)
	var wk_listed := false
	var wk_was_build: bool = g.build_on
	g.hold_carried("station", -1, "kiln")
	var wk_pc: Dictionary = g.build_piece()
	wk_listed = g.build_on and g.build_cat == 5 and String(wk_pc.get("kind", "")) == "station" and String(wk_pc.get("station", "")) == "kiln"
	if g.build_on and not wk_was_build:
		g._toggle_build()
	wk_rows.append("%sthe kiln taken up is in the satchel and goes in your hand from it: %s" % ["" if wk_listed else "(!) ", wk_listed])
	wk_ok = wk_ok and wk_listed
	var wk_h0 := 0
	for wk_k3 in g.items:
		if String(wk_k3).begins_with("hint_"):
			wk_h0 += 1
	var wk_noted: bool = ws.hint_note()
	var wk_h1 := 0
	for wk_k4 in g.items:
		if String(wk_k4).begins_with("hint_"):
			wk_h1 += 1
	var wk_ok12: bool = wk_noted and wk_h1 == wk_h0 + 1
	wk_rows.append("%sa note in a chest gave a hint: %s (%d -> %d heard)" % ["" if wk_ok12 else "(!) ", wk_noted, wk_h0, wk_h1])
	wk_ok = wk_ok and wk_ok12
	# (cleared away: the stations, the slab, what was learned and given)
	ws.list.clear()
	var wk_clear := PackedInt32Array()
	wk_clear.resize(WKW * 50)
	wk_clear.fill(Defs.AIR)
	g.stamps.append({"x0": posmod(wk_c.x, Defs.NS), "y0": wk_c.y - 46, "w": WKW, "h": 50, "data": wk_clear, "ax": wk_c.x, "aw": WKW})
	g.items = wk_items0
	g.player.buffs.clear()
	g.time = wk_time0
	g.rain = float(wk_w0[0])
	g.rain_target = float(wk_w0[1])
	g.weather_timer = int(wk_w0[2])
	_go(wk_back)
	await _frames(20)
	print("[workshops] " + "\n[workshops] ".join(wk_rows))
	_ok("workshops: kilns, smelters and stills work their loads with real fire, secrets are found by trying mixes", wk_ok, "; ".join(wk_rows))

## (user, 25 Nov: "All the crafting systems feel a little stuck together"; chose: the forge stays anywhere,
## workshops load by hand or by clicking a known recipe, the book covers what goes in the satchel, workshops and
## furniture are forged into the satchel, an amount to craft many at once)
func _test_crafting() -> void:
	var rows := []
	var ok := true
	var Bd = load("res://scripts/build.gd")
	g.player.dead = false
	if g.build_on:
		g._toggle_build()
	var rec := func(id: String) -> Dictionary:
		for r in g.recipes:
			if String(r["id"]) == id:
				return r
		return {}
	# ---- build mode has only building pieces; the rest is forged
	var tabs_ok: bool = not Bd.CAT_ORDER.has(2) and not Bd.CAT_ORDER.has(3) and not Bd.CAT_ORDER.has(Bd.CAT_WORKSHOPS)
	var r_kiln: Dictionary = rec.call("st_kiln")
	var r_well: Dictionary = rec.call("furn_well")
	var ok0: bool = tabs_ok and not r_kiln.is_empty() and not r_well.is_empty() and not rec.call("st_altar").is_empty()
	rows.append("%sbuild tabs %s; the forge has workshops %s and outdoor pieces %s" % ["" if ok0 else "(!) ", str(Bd.CAT_ORDER), not r_kiln.is_empty(), not r_well.is_empty()])
	ok = ok and ok0
	# ---- a kiln forged goes into the satchel and is set down from it
	var k0 := int(g.items.get("st_kiln", 0))
	for c in r_kiln["cost"]:
		g.player.inv[int(c)] += int(r_kiln["cost"][c])
	var made_k: int = g.craft_many(r_kiln, 1)
	var in_sat := int(g.items.get("st_kiln", 0)) == k0 + 1
	g.hold_carried("station", -1, "kiln")
	var held: Dictionary = g.build_piece()
	var ok1: bool = made_k == 1 and in_sat and g.build_cat == Bd.CAT_SATCHEL and String(held.get("station", "")) == "kiln"
	rows.append("%sa Kiln forged into the satchel %s, in hand to set down %s" % ["" if ok1 else "(!) ", in_sat, String(held.get("name", "-"))])
	ok = ok and ok1
	if g.build_on:
		g._toggle_build()
	g.items["st_kiln"] = k0
	if k0 == 0:
		g.items.erase("st_kiln")
	# ---- torches in the satchel are a piece of the Satchel tab
	g.player.inv[Defs.TORCH] += 3
	var lt: Array = Bd.carried_pieces(g.player.furn, g.items, g.player.inv)
	var has_torch := false
	for pc in lt:
		if String(pc["kind"]) == "torch":
			has_torch = true
	rows.append("%storches set down from the Satchel tab %s" % ["" if has_torch else "(!) ", has_torch])
	ok = ok and has_torch
	# ---- an amount: ten planks at a click, and as many as the satchel pays when it runs short
	var r_plank: Dictionary = rec.call("plank")
	g.player.inv[Defs.WOOD] = 50
	var p0: int = g.player.inv[Defs.PLANK]
	var n10: int = g.craft_many(r_plank, 10)
	var got10: int = g.player.inv[Defs.PLANK] - p0
	g.player.inv[Defs.WOOD] = 7
	var n_short: int = g.craft_many(r_plank, 10)
	var furn0: int = g.player.furn.size()
	var r_chair: Dictionary = rec.call("furn_chair")
	g.player.inv[Defs.PLANK] += 30
	var n_ch: int = g.craft_many(r_chair, 4)
	var once: Dictionary = rec.call("tier2")
	var ok2: bool = n10 == 10 and got10 == 40 and n_short == 3 and g.player.inv[Defs.WOOD] == 1 and n_ch == 4 and g.player.furn.size() == furn0 + 4 and not g.recipe_repeatable(once)
	rows.append("%s×10 planks: %d forged (+%d planks); short of wood: %d of 10; ×4 chairs: %d into the satchel; a focus forged once %s" % ["" if ok2 else "(!) ", n10, got10, n_short, n_ch, not g.recipe_repeatable(once)])
	ok = ok and ok2
	for k in 4:
		g.player.furn.pop_back()
	# ---- the forge's book shows the workshops' mixes, the amount on its buttons
	g.ui.set_craft_amount(10)
	g.toggle_forge()
	await _frames(6)
	var heads := []
	var amt_btn := 0
	var stack := [g.ui.forge_list]
	while not stack.is_empty():
		var n = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
			if ch is Label and String(ch.text).ends_with("(workshop)"):
				heads.append(String(ch.text))
			if ch is Button and String(ch.text) == "Forge ×10":
				amt_btn += 1
	var at_kiln := 0
	for hc in g.ui.forge_tabs.get_children():
		if hc is Button and String(hc.text) == "Kiln":
			g.ui._forge_scroll.scroll_vertical = 0
			hc.emit_signal("pressed")
			at_kiln += 1
	await _frames(4)
	_shot("forge_workshops.png")
	g.toggle_forge()
	var ok3: bool = heads.size() >= 3 and amt_btn > 3 and at_kiln == 1
	rows.append("%sthe forge's book: %s; %d buttons say Forge ×10" % ["" if ok3 else "(!) ", ", ".join(heads), amt_btn])
	ok = ok and ok3
	# ---- a workshop: click a known recipe and it loads itself (Amount batches; anything else goes back)
	var st = g.workshops.add("kiln", g.player.pos + g.basis_r(atan2(g.player.pos.y, g.player.pos.x)) * 30.0)
	g.player.inv[Defs.SAND] = 25
	g.player.inv[Defs.DIRT] += 5
	g.workshops.load_mat(st, Defs.DIRT, 5)
	var pr_glass: Dictionary = {}
	for pr in g.workshops.known_recipes("kiln"):
		if String(pr["id"]) == "k_glass":
			pr_glass = pr
	var nb: int = g.workshops.load_recipe(st, pr_glass, 10)
	var loaded_ok: bool = nb == 6 and int(st.store.get(Defs.SAND, 0)) == 24 and not st.store.has(Defs.DIRT) and g.player.inv[Defs.SAND] == 1
	var mp: Dictionary = g.workshops.match_process(st)
	g.state = "station"
	g.ui.show_station(st)
	await _frames(6)
	_shot("workshop_recipes.png")
	g.workshops.close()
	g.workshops.list.erase(st)
	var ok4: bool = loaded_ok and String(mp.get("id", "")) == "k_glass"
	rows.append("%sglass ×10 asked, %d batches loaded (24 sand), the dirt given back %s, the kiln knows the mix %s" % ["" if ok4 else "(!) ", nb, not st.store.has(Defs.DIRT), String(mp.get("id", ""))])
	ok = ok and ok4
	g.ui.set_craft_amount(1)
	print("[crafting] " + "\n[crafting] ".join(rows))
	_ok("crafting together: workshops and furniture forged into the satchel, build mode for building, the book shows the workshops' mixes, a known mix loads itself, an amount to forge many", ok, "; ".join(rows))
