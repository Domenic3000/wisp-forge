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

## The hand (user, 25 Nov: "currently the conjure spell and the build menu sort of do the same things. when
## i select something from the inventory i want a unified system"): what's picked in the satchel goes in your
## hand and Conjure places it: planks painted by the brush and laid in a line, raised as a back wall, sand
## poured, a chair and a kiln set down, a torch; out of reach and out of stock the wisp says so; what's dug
## pops up where it was dug. On a natural slab in the air, taken away after.
func _test_hand() -> void:
	var hd_back: Vector2 = g.player.pos
	var m = g.player
	var sel0: int = g.sel
	var mat0: int = g.mat
	var inv0: PackedInt32Array = m.inv.duplicate()      # (put back after: later checks count on their stock)
	var furn0: Array = m.furn.duplicate(true)
	var ha := atan2(m.pos.y, m.pos.x) + 0.2
	var hup := Vector2(cos(ha), sin(ha))
	var c0: Vector2i = Build.cell_of(hup * (g.gpu.surf_at(ha).x + 150.0))
	var cx: int = c0.x
	var top: int = c0.y
	var fl := top - 1
	var SW := 120
	var SH := 22
	var sd := PackedInt32Array()
	sd.resize(SW * SH)
	sd.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top, "w": SW, "h": SH, "data": sd})
	await _frames(4)
	_go(_cell_pos(cx + 60, fl - 12))
	await _frames(40)
	var ok := {}
	var txt := []
	var count := func(mt: int, back: bool, c_from: int, w: int) -> int:
		var rr: Dictionary = g.gpu.read_rect(posmod(cx + c_from, Defs.NS), fl - 30, w, 31)
		var nn := 0
		for v in rr["bg" if back else "fg"]:
			if (int(v) & 255) == mt:
				nn += 1
		return nn
	g.hand_item = {}
	g.hand_back = false
	g.hand_shape = 0
	g.hand_thick = 1
	# ---- planks painted by Conjure's own brush, in front
	m.inv[Defs.PLANK] = 300
	g.select_material(Defs.PLANK)
	var brush_none: bool = g.hand_piece().is_empty() and g.conjuring(m) and g.hand_bar_on()
	var pl0: int = count.call(Defs.PLANK, false, 30, 60)
	g.test_aim = _cell_pos(cx + 50, fl - 1)        # (resting on the slab: its bottom row on the open row over it)
	g.test_cast = true
	await _frames(20)
	g.test_cast = false
	await _frames(20)
	var pl1: int = count.call(Defs.PLANK, false, 30, 60)
	ok["brush"] = brush_none and pl1 > pl0 + 5
	txt.append("planks by the brush: %d -> %d (hand bar %s)" % [pl0, pl1, g.hand_bar_on()])
	# ---- G: a line, laid by pressing, dragging and letting go
	var g_used: bool = g._hand_key(KEY_G)
	var line_piece: Dictionary = g.hand_piece()
	g.test_aim = _cell_pos(cx + 66, fl)
	await _frames(2)
	g.build_click = true
	g.test_cast = true
	await _frames(3)
	g.test_aim = _cell_pos(cx + 86, fl)
	await _frames(6)
	_shot("hand_line.png")
	g.test_cast = false
	await _frames(20)
	var pl2: int = count.call(Defs.PLANK, false, 30, 60)
	ok["line"] = g_used and String(line_piece.get("kind", "")) == "block" and pl2 >= pl1 + 15
	txt.append("G: %s, laid as %s; a line 20 across: planks %d -> %d" % [g_used, String(Build.SHAPES[g.hand_shape]), pl1, pl2])
	g.hand_shape = 0
	# ---- V: a back wall of masonry (sand can't be one)
	m.inv[Defs.MASONRY] = 200
	g.select_material(Defs.MASONRY)
	var v_used: bool = g._hand_key(KEY_V)
	var wall_piece: Dictionary = g.hand_piece()
	var mw0: int = count.call(Defs.MASONRY, true, 30, 60)
	g.test_aim = _cell_pos(cx + 40, fl - 2)
	await _frames(2)
	g.test_cast = true
	await _frames(20)
	g.test_cast = false
	await _frames(20)
	var mw1: int = count.call(Defs.MASONRY, true, 30, 60)
	g.hand_back = false
	m.inv[Defs.SAND] = 100
	g.select_material(Defs.SAND)
	var v_sand: bool = g._hand_key(KEY_V)
	ok["back"] = v_used and String(wall_piece.get("kind", "")) == "wall" and mw1 > mw0 + 5 and not v_sand and not g.hand_back
	txt.append("V: %s, %s; back wall cells %d -> %d; sand can't be a back wall %s" % [v_used, String(wall_piece.get("name", "-")), mw0, mw1, not v_sand])
	# ---- sand poured where you point
	var sa0: int = count.call(Defs.SAND, false, 0, 120)
	g.test_aim = _cell_pos(cx + 20, fl - 8)
	g.test_cast = true
	await _frames(15)
	g.test_cast = false
	await _frames(30)
	var sa1: int = count.call(Defs.SAND, false, 0, 120)
	ok["pour"] = g.hand_piece().is_empty() and sa1 > sa0 + 5
	txt.append("sand poured: %d -> %d" % [sa0, sa1])
	# ---- a chair from the satchel, set down where you point (a ghost first)
	var chair: Dictionary = Build.carried_item("Chair", Build.design({"prop": "chair"}, 5), "chair")
	m.furn.append(chair)
	var nf0: int = m.furn.size()
	g.hold_carried("furn", nf0 - 1)
	var ch_piece: Dictionary = g.hand_piece()
	g.test_aim = _cell_pos(cx + 95, fl - 3)
	await _frames(6)
	var ghost: bool = g.hand_live and not (g.build_prev.get("cells", []) as Array).is_empty()
	_shot("hand_ghost.png")
	g.build_click = true
	await _frames(20)
	var ch_set: bool = m.furn.size() == nf0 - 1
	ok["chair"] = String(ch_piece.get("kind", "")) == "carried" and ghost and ch_set and g.conjuring(m)
	txt.append("a chair in hand: %s, its ghost %s, set down %s" % [String(ch_piece.get("name", "-")), ghost, ch_set])
	# ---- a kiln taken from the satchel
	var k0 := int(g.items.get("st_kiln", 0))
	g.items["st_kiln"] = k0 + 1
	var nst0: int = g.workshops.list.size()
	g.hold_carried("station", -1, "kiln")
	g.test_aim = _cell_pos(cx + 75, fl - 6)
	await _frames(6)
	g.build_click = true
	await _frames(20)
	var kiln_set: bool = g.workshops.list.size() == nst0 + 1 and int(g.items.get("st_kiln", 0)) == k0
	ok["kiln"] = kiln_set and g.hand_item.is_empty()
	txt.append("a kiln set down %s (the hand empty after: %s)" % [kiln_set, g.hand_item.is_empty()])
	for st in g.workshops.list.duplicate():
		if (st.pos as Vector2).distance_to(_cell_pos(cx + 75, fl - 6)) < 30.0:
			g.workshops.list.erase(st)
	if k0 == 0:
		g.items.erase("st_kiln")
	else:
		g.items["st_kiln"] = k0
	# ---- a torch
	m.inv[Defs.TORCH] = 2
	g.select_material(Defs.TORCH)
	var nt0: int = (g.planet_state.get("torches", []) as Array).size()
	g.test_aim = _cell_pos(cx + 10, fl - 4)
	await _frames(6)
	g.build_click = true
	await _frames(15)
	var nt1: int = (g.planet_state.get("torches", []) as Array).size()
	ok["torch"] = String(g.hand_piece().get("kind", "torch")) == "torch" and nt1 == nt0 + 1 and m.inv[Defs.TORCH] == 1
	txt.append("a torch: torches %d -> %d, left %d" % [nt0, nt1, m.inv[Defs.TORCH]])
	# ---- out of reach, and out of stock: the wisp says so
	m.furn.append(Build.carried_item("Chair", Build.design({"prop": "chair"}, 6), "chair"))
	g.hold_carried("furn", m.furn.size() - 1)
	g._wisp_said = {}
	g.test_aim = m.pos + hup.rotated(PI / 2.0) * 150.0
	await _frames(3)
	g.build_click = true
	await _frames(3)
	var far_said: bool = g.wisp_say.find("reach") >= 0
	var far_kept: bool = not m.furn.is_empty() and String(m.furn[m.furn.size() - 1]["name"]) == "Chair"
	if far_kept:
		m.furn.pop_back()
	g.hand_item = {}
	m.inv[Defs.BRICK] = 0
	g.select_material(Defs.BRICK)
	g.test_aim = _cell_pos(cx + 50, fl - 3)
	g.test_cast = true
	await _frames(4)
	g.test_cast = false
	var out_said: bool = g.wisp_say.find("out of") >= 0
	ok["wisp"] = far_said and far_kept and out_said
	txt.append("the wisp: out of reach %s (nothing set down %s), out of brick %s ('%s')" % [far_said, far_kept, out_said, g.wisp_say])
	# ---- dug matter pops up where it was dug
	g.popups.clear()
	g.test_aim = _cell_pos(cx + 50, top + 2)
	g.test_dig = true
	await _frames(40)
	g.test_dig = false
	await _frames(30)
	var popped := false
	for pu in g.popups:
		if String(pu[1]).begins_with("+"):
			popped = true
	ok["popups"] = popped
	txt.append("popups after digging: %d %s" % [g.popups.size(), str(g.popups.map(func(p): return p[1]).slice(0, 3))])
	g.test_aim = Vector2.ZERO
	g.hand_item = {}
	g.hand_back = false
	g.hand_shape = 0
	g.sel = sel0
	g.mat = mat0
	m.inv = inv0
	m.furn = furn0
	# take the slab and what's on it away again
	var clr := PackedInt32Array()
	clr.resize(SW * (SH + 40))
	clr.fill(0xFF00 | 0x40000)
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top - 40, "w": SW, "h": SH + 40, "data": clr})
	_go(hd_back)
	await _frames(30)
	var all_ok := true
	var bad := []
	for k in ok:
		if not ok[k]:
			all_ok = false
			bad.append(k)
	_ok("the hand: what's picked in the satchel, Conjure places (brush, line, back wall, poured, furniture, a workshop, a torch), the wisp's notes, pickups pop up", all_ok,
		"; ".join(txt) + ("" if all_ok else " (not working: %s)" % ", ".join(bad)))

## The in-world interface, second pass (user, 25 Nov: "C summons the forge into the world", the recipe book a
## grimoire, workshops that show what they're doing, the staff's gem showing your mana, "Send to the Kiln", a
## quick bar, then the item belt): the forge rises beside you and fades when shut, and what's forged flies from it; a recipe
## learned sends a page flying into your book and inks in as the book next opens; a locked page's sketch; a
## kiln on a slab in the air shows its glass on a tray, F takes it (no panel), F with sand in hand drops it
## in, then F opens the panel; a process sent to the kiln from the book; the gem dims and flares; the item
## belt (pinned things keep their slot, what you held lately fills the rest, Q / E step along it). A picture
## of the forge (`forge.png`). The slab taken away after.
func _test_inworld() -> void:
	var m = g.player
	var iw_back: Vector2 = m.pos
	var sel0: int = g.sel
	var mat0: int = g.mat
	var inv0: PackedInt32Array = m.inv.duplicate()
	var items0: Dictionary = g.items.duplicate(true)
	var furn0: Array = m.furn.duplicate(true)
	var mana0: float = m.mana
	var ws = g.workshops
	var ws_n0: int = ws.list.size()
	var wk_w0 := [g.rain, g.rain_target, g.weather_timer]
	g.rain = 0.0
	g.rain_target = 0.0
	g.weather_timer = 999999
	var ok := {}
	var txt := []
	# the slab, up in the air
	var ia := atan2(m.pos.y, m.pos.x) - 0.25
	var iup := Vector2(cos(ia), sin(ia))
	var c0: Vector2i = Build.cell_of(iup * (g.gpu.surf_at(ia).x + 150.0))
	var cx: int = c0.x
	var top: int = c0.y
	var SW := 100
	var SH := 6
	var sd := PackedInt32Array()
	sd.resize(SW * SH)
	sd.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top, "w": SW, "h": SH, "data": sd})
	await _frames(4)
	_go(_cell_pos(cx + 50, top - 12))
	await _frames(40)
	var t0: float = g.time
	g.time = g.towns.time_for_hour(m.pos, 12.0)
	# ---- the forge summoned beside you, forging from it, and gone when shut
	g.toggle_forge()
	await _frames(30)
	var f_vis: float = g.forge_vis
	var f_sent0: int = g.stats_forge_sent
	g._forge_send({"name": "test", "give": {Defs.GLASS: 1}})
	await _frames(12)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("forge.png"))
	var f_state: String = g.state
	g.toggle_forge()
	await _frames(45)
	ok["forge"] = f_state == "forge" and f_vis > 0.9 and g.stats_forge_sent == f_sent0 + 1 and g.state == "play" and g.forge_vis == 0.0
	txt.append("forge: risen %.2f, sent %d, shut -> %s %.2f" % [f_vis, g.stats_forge_sent - f_sent0, g.state, g.forge_vis])
	# ---- a page into the book, inked in as it next opens
	var r_id := ""
	for r in g.recipes:
		if not r.has("scroll") and g.learned.has(String(r["id"])) and not bool(Defs.learn_of(r).get("start", false)):
			r_id = String(r["id"])
			break
	var pg0: int = g.stats_pages
	g.learned.erase(r_id)
	g.items.erase("book_new")
	var learned_ok: bool = r_id != "" and g.learn(r_id, "for the test")
	var flying: bool = not g.pages.is_empty()
	var noted: bool = (g.items.get("book_new", []) as Array).has(r_id)
	await _frames(70)
	var landed: bool = g.stats_pages == pg0 + 1 and g.pages.is_empty()
	g.toggle_forge(true)
	await _frames(10)
	var inking: bool = g.ui._inking.has(r_id) and not g.items.has("book_new")
	g.toggle_forge()
	await _frames(10)
	ok["pages"] = learned_ok and flying and noted and landed and inking
	txt.append("a page: learned %s, flying %s, noted %s, landed %s, inked %s" % [learned_ok, flying, noted, landed, inking])
	var sk = Icons.sketch(Icons.mat(Defs.STONE))
	ok["sketch"] = sk != null and sk.get_width() == Icons.mat(Defs.STONE).get_width() + 1
	# ---- a kiln: its tray taken with F, sand dropped in with F, then its panel
	m.inv[Defs.SAND] += 40
	m.inv[Defs.COAL] += 10
	var kiln = ws.add("kiln", _cell_pos(cx + 40, top - 9))
	await _frames(60)
	ws.load_mat(kiln, Defs.SAND, 4)
	ws.add_fuel(kiln, Defs.COAL, 2)
	for wt in 900:
		ws.work_all()
		if ws.has_out(kiln):
			break
	var tray: bool = ws.has_out(kiln)
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("tray.png"))
	_go(kiln.pos + kiln.pos.normalized() * 2.0)
	await _frames(10)
	var gl0: int = m.inv[Defs.GLASS]
	var tr0: int = int(ws.stats.get("trays", 0))
	var took: bool = ws.interact(m) and g.state == "play" and m.inv[Defs.GLASS] > gl0 and not ws.has_out(kiln) and int(ws.stats.get("trays", 0)) == tr0 + 1
	ws.unload(kiln, Defs.SAND)
	g.select_material(Defs.SAND)
	var sd0: int = m.inv[Defs.SAND]
	var dropped: bool = ws.interact(m) and g.state == "play" and int(kiln.store.get(Defs.SAND, 0)) > 0 and m.inv[Defs.SAND] == sd0 - int(kiln.store.get(Defs.SAND, 0))
	var panel: bool = ws.interact(m) and g.state == "station"
	ws.close()
	await _frames(4)
	ok["tray"] = tray and took and dropped and panel
	txt.append("kiln: tray %s, taken by F %s (%d glass), sand dropped in %s (%s), then the panel %s" % [tray, took, m.inv[Defs.GLASS] - gl0, dropped, str(kiln.store), panel])
	# ---- sent to the kiln from the book
	ws.unload(kiln, Defs.SAND)
	var sent: int = ws.send(Defs.process_by_id("k_glass"), 2)
	ok["send"] = sent == 2 and int(kiln.store.get(Defs.SAND, 0)) == 8
	txt.append("sent to the kiln: %d batches (%s)" % [sent, str(kiln.store)])
	ws.unload(kiln, Defs.SAND)
	# ---- (25 Nov, "forging large amounts in the wisp forge like 10 or more the game gets very sluggish"): how long
	# forging 20 at once takes, by kind, with the forge open, and the frames after
	var fg_rows := []
	var fg_ok := true
	# (one forged first: the run's first toast and sounds take a while to warm up, once)
	var fg_warm: Dictionary = g.recipe_by_id("plank")
	for fg_c0 in fg_warm["cost"]:
		m.inv[int(fg_c0)] += int(fg_warm["cost"][fg_c0])
	g.craft_many(fg_warm, 1)
	await _frames(2)
	for fg_id in ["plank", "furn_chair", "st_kiln", "potion"]:
		var fg_r: Dictionary = g.recipe_by_id(fg_id)
		if fg_r.is_empty():
			continue
		for fg_c in fg_r["cost"]:
			m.inv[int(fg_c)] += int(fg_r["cost"][fg_c]) * 25
		g.toggle_forge()
		await _frames(5)
		g.ui.craft_amount = 20
		var fg_t0 := Time.get_ticks_usec()
		var fg_made: int = g.craft_many(fg_r, 20)
		var fg_t1 := Time.get_ticks_usec()
		g.ui._refresh_forge()
		var fg_t2 := Time.get_ticks_usec()
		fg_ok = fg_ok and fg_made == 20 and float(fg_t2 - fg_t0) / 1000.0 < 50.0
		var fg_worst := 0.0
		for fg_f in 30:
			var fg_ft := Time.get_ticks_usec()
			await _frames(1)
			fg_worst = maxf(fg_worst, float(Time.get_ticks_usec() - fg_ft) / 1000.0)
		g.ui.craft_amount = 1
		g.toggle_forge()
		await _frames(5)
		fg_rows.append("%s x%d: %.1f ms forging, %.1f ms the cards updated, worst frame after %.1f ms" % [fg_id, fg_made, float(fg_t1 - fg_t0) / 1000.0, float(fg_t2 - fg_t1) / 1000.0, fg_worst])
	print("[forge20] " + "; ".join(fg_rows))
	ok["forge20"] = fg_ok
	txt.append("forging 20: " + "; ".join(fg_rows))
	# ---- the gem: dim when drained, a flare as it fills
	var gem := Color(0.3, 0.9, 1.0)
	m.mana = m.max_mana * 0.15
	var dim: Color = g.overlay._gem_now(m, gem)
	var fl0: int = g.overlay.stats_gem_flares
	m.mana = m.max_mana
	var flare: Color = g.overlay._gem_now(m, gem)
	ok["gem"] = dim.get_luminance() < gem.get_luminance() * 0.6 and g.overlay.stats_gem_flares == fl0 + 1 and flare.get_luminance() > gem.get_luminance()
	txt.append("gem: %.2f drained, %.2f lit, %.2f flaring" % [dim.get_luminance(), gem.get_luminance(), flare.get_luminance()])
	# ---- the item belt: pinned things keep their slot, what you held lately fills the rest, Q / E step along it
	g.items.erase("belt")
	var recent0: Array = g.hand_recent.duplicate()
	g.hand_recent = []
	m.inv[Defs.DIRT] += 10
	m.inv[Defs.STONE] += 10
	g.select_material(Defs.SAND)
	g._note_hand()
	g.select_material(Defs.DIRT)
	g._note_hand()
	var ql: Array = g.quick_list()
	var has_sand: bool = ql.has("m%d" % Defs.SAND) and not ql.has("m%d" % Defs.DIRT)
	g.belt_pin("m%d" % Defs.STONE)
	var bl: Array = g.belt()
	var pinned_first: bool = bl[0][0] == "m%d" % Defs.STONE and bl[0][1]
	var recent_in: bool = bl[1][0] == "m%d" % Defs.DIRT and bl[2][0] == "m%d" % Defs.SAND and not bl[1][1]
	# (holding dirt, the slot after the stone: E goes on to sand, Q back to dirt, Q again to the stone)
	var st0: int = g.stats_belt_steps
	g.belt_step(1)
	var e_sand: bool = g.mat == Defs.SAND
	g.belt_step(-1)
	g.belt_step(-1)
	var q_stone: bool = g.mat == Defs.STONE and g.stats_belt_steps == st0 + 3
	g.belt_pin("m%d" % Defs.STONE)
	var unpinned: bool = not (g.belt()[0][1] as bool)
	# (stepping along it left its slots where they were)
	var still: bool = g.belt()[1][0] == "m%d" % Defs.DIRT and g.belt()[2][0] == "m%d" % Defs.SAND
	g.hand_recent = recent0
	ok["belt"] = still and has_sand and pinned_first and recent_in and e_sand and q_stone and unpinned and g.items.has("belt")
	txt.append("belt %s; recent %s; E -> sand %s, Q Q -> stone %s (%s), slots kept %s, unpinned %s" % [str(bl.slice(0, 3)), str(ql), e_sand, q_stone, Defs.NAMES[g.mat], still, unpinned])
	# ---- plans: a Room raised from your hand course by course, a right-drag cutting a shape, B opening the plans
	ws.list.erase(kiln)
	var doors0: int = g.doors.size()
	for pm in Defs.NM:
		if Defs.KIND[pm] == Defs.K_SOLID:
			m.inv[pm] += 600
	m.mana = m.max_mana
	_go(_cell_pos(cx + 22, top - 12))
	await _frames(30)
	var bw0 := [g.build_w, g.build_floors]
	g.build_w = 40
	g.build_floors = 1
	var known_room: bool = g.knows_plan("room")
	g.hold_plan("room")
	var plan_piece: Dictionary = g.hand_piece()
	var plan_hint: String = g.hand_hint()
	g.test_aim = _cell_pos(cx + 62, top - 2)
	await _frames(6)
	var room_fit: bool = g.build_prev.get("ok", false)
	var room_why: String = g.build_why + " " + String(g.build_prev.get("text", ""))
	var raised0: int = g.stats_raised
	g.build_click = true
	await _frames(3)
	var rising: bool = not g.raising.is_empty()
	var posing: bool = g.frame - g.player.cast_frame < 14
	var count_built := func() -> int:
		var rr: Dictionary = g.gpu.read_rect(posmod(cx + 20, Defs.NS), top - 80, 80, 80)
		var nb := 0
		for v in rr["fg"]:
			var t: int = int(v) & 255
			if t != 0 and Defs.KIND[t] == Defs.K_SOLID:
				nb += 1
		return nb
	await _frames(8)
	var mid_n: int = count_built.call()
	await _frames(140)
	var end_n: int = count_built.call()
	g.test_aim = Vector2.ZERO
	var room_ok: bool = known_room and String(plan_piece.get("kind", "")) == "structure" and plan_hint.contains("plan") and room_fit and rising and posing and g.raising.is_empty() and g.stats_raised == raised0 + 1 and end_n > mid_n + 50
	ok["plans"] = room_ok
	txt.append("a room plan: known %s, fits %s (%s), rising %s, casting %s, %d cells a few ticks in, %d at the end, raised %d, doors %d -> %d" % [known_room, room_fit, room_why, rising, posing, mid_n, end_n, g.stats_raised - raised0, doors0, g.doors.size()])
	await _frames(20)
	_shot("plan_room.png")
	# Unmake (user, 25 Nov: removal as its own spell beside Conjure): a rectangle of the slab taken away by a
	# press, drag and let go; G and V change its shape and what it takes
	if not g.known.has("unmake"):
		g.known.insert(g.known.find("conjure") + 1, "unmake")
	var un_sel0: int = g.sel
	g.sel = g.known.find("unmake")
	g.unmake_shape = 2
	g.unmake_layer = 0
	g.unmake_thick = 1
	var un0: int = g.stats_unmade
	g.test_aim = _cell_pos(cx + 6, top)
	await _frames(2)
	var un_live: bool = g.hand_live and g.hand_bar_on() and g.hand_hint().begins_with("Unmake")
	g.build_click = true
	g.test_cast = true
	await _frames(3)
	g.test_aim = _cell_pos(cx + 10, top + 1)
	await _frames(3)
	g.test_cast = false
	await _frames(3)
	g.test_aim = Vector2.ZERO
	var cut_n: int = g.stats_unmade - un0
	var un_g: bool = g._unmake_key(KEY_G) and g.unmake_shape == 3
	var un_v: bool = g._unmake_key(KEY_V) and g.unmake_layer == 1
	g.unmake_shape = 2
	g.unmake_layer = 0
	g.sel = un_sel0
	ok["unmake"] = un_live and cut_n >= 6 and un_g and un_v
	txt.append("Unmake: live %s, a rectangle took %d cells, G %s, V %s" % [un_live, cut_n, un_g, un_v])
	# F between two rooms side by side: the first room's door open beside you, the second's shut just past it;
	# facing it, F picks the shut one (user, 25 Nov: it couldn't be opened from that side)
	var dr_keep: Array = g.doors
	var dr_right: Vector2 = g.basis_r(atan2(m.pos.y, m.pos.x))
	var dr_open := {"pos": m.pos + dr_right * 5.0, "open": true}
	var dr_shut := {"pos": m.pos + dr_right * 13.0, "open": false}
	g.doors = [dr_open, dr_shut]
	var dr_face0: int = m.facing
	m.facing = 1
	var dr_pick_r: Dictionary = g._door_for_f(m)
	m.facing = -1
	var dr_pick_l: Dictionary = g._door_for_f(m)
	m.facing = dr_face0
	g.doors = dr_keep
	ok["doors"] = dr_pick_r == dr_shut and dr_pick_l == dr_open
	txt.append("F between two rooms: facing the shut door %s, facing away the open one %s" % [dr_pick_r == dr_shut, dr_pick_l == dr_open])
	# wedged deep in rock (user, 25 Nov: levitating into a gap clipped him into the ground, then he rose through
	# it to the surface): a block of stone too big to step out of, the mage in its middle, and he goes back to
	# where he last stood clear
	var wb := PackedInt32Array()
	wb.resize(30 * 50)
	wb.fill(Defs.STONE | 0xFF00 | 0x20000)
	g.stamps.append({"x0": posmod(cx + 5, Defs.NS), "y0": top - 50, "w": 30, "h": 50, "data": wb})
	await _frames(4)
	var wb_mid: Vector2 = _cell_pos(cx + 20, top - 26)
	var wb_clear: Vector2 = _cell_pos(cx + 20, top - 66)
	_go(wb_mid)
	m.free_pos = wb_clear
	await _frames(2)
	var wb_d: float = m.pos.distance_to(wb_clear)
	var wb_rose: float = m.pos.length() - wb_mid.length()
	ok["wedged"] = wb_d < 10.0
	txt.append("wedged in rock: back where he stood clear %s (%.0f cells from it, %.0f above where he was wedged)" % [wb_d < 10.0, wb_d, wb_rose])
	_go(_cell_pos(cx + 22, top - 12))
	await _frames(10)
	# B on the planet opens the satchel at its plans
	var sat0: bool = g.ui.satchel_open
	if sat0:
		g.ui.toggle_satchel()
	g.ui.open_plans()
	var b_ok: bool = g.ui.satchel_open and not g.build_on
	g.ui.toggle_satchel()
	ok["b"] = b_ok
	# ---- put back
	g.doors.resize(doors0)
	g.build_w = bw0[0]
	g.build_floors = bw0[1]
	while ws.list.size() > ws_n0:
		ws.list.pop_back()
	g.time = t0
	g.rain = wk_w0[0]
	g.rain_target = wk_w0[1]
	g.weather_timer = wk_w0[2]
	m.mana = mana0
	g.sel = sel0
	g.mat = mat0
	g.hand_item = {}
	m.inv = inv0
	m.furn = furn0
	g.items = items0
	g.learned[r_id] = true
	var clr := PackedInt32Array()
	clr.resize(SW * (SH + 90))
	clr.fill(0xFF00 | 0x40000)
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top - 90, "w": SW, "h": SH + 90, "data": clr})
	_go(iw_back)
	await _frames(30)
	var all_ok := true
	var bad := []
	for k in ok:
		if not ok[k]:
			all_ok = false
			bad.append(k)
	_ok("in the world: the summoned forge, pages into the book, a kiln's tray and F, Send to the Kiln, the staff's gem, the item belt, plans raised by a spell, the Unmake spell, doors between rooms, getting unwedged", all_ok,
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
	# (F takes what it made off its tray first, and drops in what's in your hand: neither here)
	var wk_selp: int = g.sel
	for wk_si in g.known.size():
		if g.known[wk_si] != "conjure":
			g.sel = wk_si
			break
	if ws.has_out(kiln):
		ws.take_out(kiln, true)
	var wk_opened: bool = ws.interact(g.player) and g.state == "station"
	g.sel = wk_selp
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
	var wk_sel0: int = g.sel
	g.hold_carried("station", -1, "kiln")
	var wk_pc: Dictionary = g.hand_piece()
	wk_listed = not g.build_on and g.conjuring(g.player) and String(wk_pc.get("kind", "")) == "station" and String(wk_pc.get("station", "")) == "kiln"
	if wk_was_build and not g.build_on:
		g._toggle_build()
	g.hand_item = {}
	g.sel = wk_sel0
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
	var cr_sel0: int = g.sel
	g.hold_carried("station", -1, "kiln")
	var held: Dictionary = g.hand_piece()
	var cr_conj: bool = g.conjuring(g.player)
	g.hand_item = {}
	g.sel = cr_sel0
	var ok1: bool = made_k == 1 and in_sat and cr_conj and String(held.get("station", "")) == "kiln"
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

## More kinds of light and more workshop secrets (26 Nov): up in open air a floor of stone and a ceiling over it;
## a torch pointed just under the ceiling hangs from it as a lantern (its flame real torch cells, a wider light
## than a torch's, and it comes back as a torch when taken up); Wisplight hangs a light where you point, a second
## cast there puts it out, and no more than ten are kept; and every workshop mix is its station's only one of those
## kinds, every secret's draught or gear is real. A picture at night: saves/shots/lights_night.png.
func _test_lights() -> void:
	var lt_rows := []
	var lt_ok := true
	var m = g.player
	var lt_back: Vector2 = m.pos
	var lt_time0: float = g.time
	var lt_a := atan2(m.pos.y, m.pos.x) - 0.12
	var lt_up := Vector2(cos(lt_a), sin(lt_a))
	var c0: Vector2i = Build.cell_of(lt_up * (g.gpu.surf_at(lt_a).x + 160.0))
	var cx: int = c0.x
	var top: int = c0.y                    # (the floor's top row)
	var SW := 90
	var GAP := 34                          # (open rows between the floor and the ceiling)
	var slab := PackedInt32Array()
	slab.resize(SW * 10)
	slab.fill(Defs.STONE | 0xFF00 | 0x20000 | 0x80000)
	var ceil_top: int = top - GAP - 10
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": top, "w": SW, "h": 10, "data": slab})
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": ceil_top, "w": SW, "h": 10, "data": slab})
	_go(_cell_pos(cx + 45, top - 12))
	await _frames(30)
	# a lantern, hung from the ceiling
	var ceil_under: int = ceil_top + 10       # (the first open row under the ceiling)
	m.inv[Defs.TORCH] = 4
	var lp: Dictionary = g.torch_plan(Vector2i(cx + 30, ceil_under + 2))
	var placed: bool = g.place_torch(m, _cell_pos(cx + 30, ceil_under + 2))
	var placed2: bool = g.place_torch(m, _cell_pos(cx + 60, top - 3))       # (and a standing torch, for comparison)
	await _frames(20)
	var tl: Array = g.planet_state.get("torches", [])
	var lantern_k := -1
	for k in tl.size():
		if (tl[k] as Array).size() > 3 and int(tl[k][3]) == 1:
			lantern_k = k
	var rr: Dictionary = g.gpu.read_rect(posmod(cx + 24, Defs.NS), ceil_under, 12, 12)
	var flames := 0
	var glass := 0
	for b in rr["bg"]:
		if (int(b) & 255) == Defs.TORCH:
			flames += 1
		elif (int(b) & 255) == Defs.DECOR:
			glass += 1
	# (what's there, row by row: f a flame, d furniture, # solid in front, . open)
	for jr in 12:
		var ln := ""
		for ir in 12:
			var kk := jr * 12 + ir
			var bq: int = int(rr["bg"][kk]) & 255
			var fq: int = int(rr["fg"][kk]) & 255
			ln += "f" if bq == Defs.TORCH else ("d" if bq == Defs.DECOR else ("#" if fq != 0 else ("~" if fq != 0 else ".")))
			if fq != 0 and bq == 0:
				ln[ln.length() - 1] = "#" if Defs.KIND[fq] == Defs.K_SOLID else "*"
		print("[lights] %s" % ln)
	g.lights.clear()
	g._torch_lights()
	var wide := 0
	var narrow := 0
	for L in g.lights:
		if absf(float(L[1]) - Build.LANTERN_R) < 6.0:
			wide += 1
		elif absf(float(L[1]) - Build.TORCH_R) < 6.0:
			narrow += 1
	var ok1: bool = bool(lp.get("lantern", false)) and placed and placed2 and lantern_k >= 0 and flames >= 3 and glass >= 16 and wide >= 1
	lt_rows.append("%sa lantern under the ceiling: planned as one %s, hung %s (a torch stood %s), remembered %s, %d flame and %d frame cells, its light %s (a torch's %s)" % [
		"" if ok1 else "(!) ", lp.get("lantern", false), placed, placed2, lantern_k >= 0, flames, glass, wide >= 1, narrow >= 1])
	lt_ok = lt_ok and ok1
	# Wisplight: hung where you point, put out by a second cast there, ten at most
	if not m.known.has("wisplight"):
		m.known.append("wisplight")
	g.planet_state["wisplights"] = []
	var wp: Vector2 = _cell_pos(cx + 12, top - 20)
	m.mana = m.max_mana
	m.spell_cd.clear()
	g._wisplight(m, wp, 10.0)
	var n1: int = (g.planet_state["wisplights"] as Array).size()
	g.lights.clear()
	g._wisp_lights()
	var wl_light := 0
	for L2 in g.lights:
		if absf(float(L2[1]) - g.WISPLIGHT_R) < 8.0:
			wl_light += 1
	g._wisplight(m, wp + Vector2(2, 0), 10.0)
	var n2: int = (g.planet_state["wisplights"] as Array).size()
	for k2 in 12:
		m.mana = m.max_mana
		g._wisplight(m, m.pos + lt_up * 24.0 + lt_up.orthogonal() * float(16 * (k2 - 6)), 10.0)
	var n3: int = (g.planet_state["wisplights"] as Array).size()
	var ok2: bool = n1 == 1 and wl_light == 1 and n2 == 0 and n3 == g.WISPLIGHT_MAX
	lt_rows.append("%sWisplight: hung %d, its light %d, cast there again: %d left; twelve cast: %d kept" % ["" if ok2 else "(!) ", n1, wl_light, n2, n3])
	lt_ok = lt_ok and ok2
	# a picture at night between the slabs
	var na: float = atan2(m.pos.y, m.pos.x)
	g.time = fposmod((na + PI - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)
	_go(_cell_pos(cx + 30, top - 12))
	await _frames(40)
	_shot("lights_night.png")
	# the lantern taken up is a torch again
	var tor0: int = m.inv[Defs.TORCH]
	var took: bool = g._pick_up_furniture(m, _cell_pos(cx + 30, ceil_under + 2))
	await _frames(10)
	var ok3: bool = took and m.inv[Defs.TORCH] == tor0 + 1
	lt_rows.append("%sthe lantern taken up: %s, torches %d -> %d" % ["" if ok3 else "(!) ", took, tor0, m.inv[Defs.TORCH]])
	lt_ok = lt_ok and ok3
	# every workshop mix its station's only one of those kinds; every secret's draught or gear real
	var seen := {}
	var bad := []
	var n_secret := 0
	for pr in Defs.PROCESS:
		var ks: Array = (pr["in"] as Dictionary).keys()
		ks.sort()
		var key := String(pr["at"]) + ":" + str(ks)
		if seen.has(key):
			bad.append("%s and %s share a mix" % [seen[key], pr["id"]])
		seen[key] = pr["id"]
		if bool(pr.get("secret", false)):
			n_secret += 1
			var it := String(pr.get("item", ""))
			if it.begins_with("d_") and not Defs.DRAUGHTS.has(it):
				bad.append("%s's draught %s" % [pr["id"], it])
			if it.begins_with("gear:") and not Defs.WORK_GEAR.has(it.substr(5)):
				bad.append("%s's gear %s" % [pr["id"], it])
	var ok4: bool = bad.is_empty() and n_secret >= 12
	lt_rows.append("%sworkshop mixes: %d, %d of them secrets; %s" % ["" if ok4 else "(!) ", Defs.PROCESS.size(), n_secret, "all their own" if bad.is_empty() else "; ".join(bad)])
	lt_ok = lt_ok and ok4
	# put things back: the slabs, the torches, the wisplights
	var air := PackedInt32Array()
	air.resize(SW * (GAP + 20))
	air.fill(Defs.AIR | 0xFF00)
	g.stamps.append({"x0": posmod(cx, Defs.NS), "y0": ceil_top, "w": SW, "h": GAP + 20, "data": air})
	g.planet_state["wisplights"] = []
	g.planet_state["torches"] = []
	g.time = lt_time0
	_go(lt_back)
	await _frames(30)
	print("[lights] " + "\n[lights] ".join(lt_rows))
	_ok("more kinds of light (a lantern hung from a ceiling, Wisplight) and more workshop secrets", lt_ok, "; ".join(lt_rows))
