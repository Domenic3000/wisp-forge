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
## background plant cells (leaves, wood, cactus, coal from charred trees, snow on pines) in a
## 120-column window from 100 rows above the ground at the middle down to 10 below
func _plants(raw: PackedByteArray, toff: int, c0: int, gr: int) -> int:
	var N: int = Defs.SH_N[0]
	var n := 0
	for j in range(maxi(0, gr - 100), gr + 10):
		for i in 120:
			var bm := raw.decode_u32(toff + (j * N + posmod(c0 + i, N)) * 4) & 255
			if bm == Defs.LEAF or bm == Defs.WOOD or bm == Defs.CACTUS or bm == Defs.COAL or bm == Defs.SNOW:
				n += 1
	return n

## positions of powder cells (sand, gravel, snow, ash) in a 150-column window around the ground
func _powders(raw: PackedByteArray, c0: int, gr: int) -> Dictionary:
	var N: int = Defs.SH_N[0]
	var out := {}
	for j in range(maxi(0, gr - 40), gr + 40):
		for i in 150:
			var col := posmod(c0 + i, N)
			var t := raw.decode_u32((j * N + col) * 4) & 255
			if Defs.KIND[t] == Defs.K_POWDER:
				out[j * N + col] = true
	return out

## the chest object standing at a planned chest spot (left column, floor row), or null
func _chest_obj(spot: Vector2i):
	if spot.x < 0:
		return null
	var want := _cell_pos(spot.x + Defs.CHEST_W / 2, spot.y - 5)
	for c in g.chests:
		if (c.pos as Vector2).distance_to(want) < 4.0:
			return c
	return null

func _scan(raw: PackedByteArray, info: Dictionary) -> Dictionary:
	# the structure's own built cells (recorded when it was generated): how many still hold a
	# solid, and which of them hang unsupported over open space
	var solid := 0
	var loose := 0
	var tre := 0
	var mats := {}
	var below := {}
	var at := []
	var allm := {}
	var bgn := 0
	var N: int = Defs.SH_N[0]
	var boff: int = Defs.total_cells() * 4      # the background layer follows the cells
	var w: int = int(info["w"])
	for k in info.get("cells", PackedInt32Array()):
		var j: int = k / w
		var i: int = k % w
		var row: int = int(info["y0"]) + j
		if row < 0 or row >= Defs.SH_Y0[1]:
			continue
		var col := posmod(int(info["x0"]) + i, N)
		var c := raw.decode_u32((row * N + col) * 4)
		var t := c & 255
		if Defs.KIND[t] != Defs.K_SOLID:
			continue
		solid += 1
		allm[Defs.NAMES[t]] = int(allm.get(Defs.NAMES[t], 0)) + 1
		# unsupported AND over open space (so it should have fallen); anchored cells are part
		# of the planet until you dig nearby
		var lf := (c >> 16) & 255
		if (c & 0x40000000) == 0 and ((c >> 24) & 63) > Defs.SPAN[t] and row + 1 < Defs.SH_Y0[1] and not (lf > 0 and lf < 128):
			var cb := raw.decode_u32(((row + 1) * N + col) * 4)
			var tb := cb & 255
			var kb: int = Defs.KIND[tb]
			if tb == 0 or kb == Defs.K_GAS or kb == Defs.K_FIRE or kb == Defs.K_LIQUID:
				loose += 1
				if at.size() < 4:
					at.append(Vector2i(i, j))
				mats[Defs.NAMES[t]] = int(mats.get(Defs.NAMES[t], 0)) + 1
				var key := Defs.NAMES[tb] if tb > 0 else "air"
				below[key] = int(below.get(key, 0)) + 1
	for j in int(info["h"]):
		var row2: int = int(info["y0"]) + j
		if row2 < 0 or row2 >= Defs.SH_Y0[1]:
			continue
		for i in w:
			var col2 := posmod(int(info["x0"]) + i, N)
			var t2 := raw.decode_u32((row2 * N + col2) * 4) & 255
			var bgm := raw.decode_u32(boff + (row2 * N + col2) * 4) & 255
			if bgm != 0:
				bgn += 1
				var bk := "bg " + Defs.NAMES[bgm]
				allm[bk] = int(allm.get(bk, 0)) + 1
			if t2 == Defs.TREASURE or bgm == Defs.TREASURE:
				tre += 1
	return {"solid": solid, "loose": loose, "treasure": tre, "mats": mats, "below": below, "at": at, "all": allm, "bg": bgn}

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
	var worst_built := ""
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
			var a0: Vector2i = sc["at"][0]
			var nm: String = b.label_at(_cell_pos(int(info["x0"]) + a0.x, int(info["y0"]) + a0.y))
			loose_where.append("%d in a %s structure %dx%d (%s) at local %s" % [sc["loose"], "ruined" if info["ruined"] else "intact", info["w"], info["h"], nm, str(sc["at"])])
			for k in sc["mats"]:
				loose_mats[k] = int(loose_mats.get(k, 0)) + int(sc["mats"][k])
			for k in sc["below"]:
				loose_below[k] = int(loose_below.get(k, 0)) + int(sc["below"][k])
		if int(info["solid"]) > 0:
			intact += 1
			var ratio := float(sc["solid"]) / float(info["solid"])
			if ratio < worst:
				worst_built = "%s %s %dx%d: %d of %d built cells left, now %s" % ["ruined" if info["ruined"] else "intact", b.label_at(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) + int(info["h"]) - 3)), info["w"], info["h"], sc["solid"], info["solid"], str(sc["all"])]
			worst = minf(worst, ratio)
			if ratio >= 0.97:
				intact_ok += 1

	_ok("every structure (ruins too) stands as built after generating", intact_ok == intact, "%d of %d keep at least 97%% of their blocks, worst %.1f%%" % [intact_ok, intact, worst * 100.0])
	if intact_ok != intact:
		lines.append("      worst: " + worst_built)
	_ok("every planned chest is in the world", g.chests.size() == b.chest_list.size() and g.chests.size() > 0, "%d chests, %d planned" % [g.chests.size(), b.chest_list.size()])
	_ok("nothing is left hanging after settling", loose_total == 0, "%d unsupported blocks over open space" % loose_total)
	if loose_total > 0:
		lines.append("      where: " + "; ".join(loose_where))
		lines.append("      materials: " + str(loose_mats))
		lines.append("      resting on: " + str(loose_below))

	# ---- structures stay put when you walk up to them (ruins used to fall apart on arrival) ----
	var visits := []
	for info in b.infos:
		if info["ruined"] and visits.size() < 12:
			visits.append(info)
	for info in b.infos:
		if not info["ruined"] and visits.size() < 15:
			visits.append(info)
	var worst_v := 1.0
	var worst_txt := ""
	for info in visits:
		var sc0 := _scan(g.gpu.read_world(), info)
		_go(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) - 6))
		await _frames(200)
		var sc1 := _scan(g.gpu.read_world(), info)
		var n0 := int(sc0["solid"]) + int(sc0["bg"])
		var n1 := int(sc1["solid"]) + int(sc1["bg"])
		var ratio := float(n1) / maxf(1.0, float(n0))
		if ratio < worst_v:
			worst_v = ratio
			var lost := []
			for k in sc0["all"]:
				var dn := int(sc0["all"][k]) - int(sc1["all"].get(k, 0))
				if dn > 3:
					lost.append("%s -%d" % [k, dn])
			worst_txt = "%s %s %dx%d lost %s" % ["ruined" if info["ruined"] else "intact", b.label_at(_cell_pos(int(info["x0"]) + 2, int(info["y0"]) + int(info["h"]) - 4)), info["w"], info["h"], ", ".join(lost)]
	_ok("structures stay put when you arrive", worst_v >= 0.97, "%d visited, worst keeps %.1f%%" % [visits.size(), worst_v * 100.0])
	if worst_v < 0.97:
		lines.append("      " + worst_txt)

	# ---- pictures of a few ruins and buildings, for looking at the art (saves/shots/) ----
	var shot_dir: String = g._real_save_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var nshot := 0
	var kinds_shot := {}
	for info in b.infos:
		if nshot >= 6:
			break
		var key: String = ("ruin " if info["ruined"] else "intact ") + str(int(info["w"]) / 20)
		if kinds_shot.has(key):
			continue
		kinds_shot[key] = true
		var cx := int(info["x0"]) + int(info["w"]) / 2
		var spos := _cell_pos(cx, b.ground_row(cx) - 30)
		_go(spos)
		# midday over it, and nothing drawn on top
		g.ui.title.visible = false
		g.time = fposmod(atan2(spos.y, spos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0   # DAY_LEN
		await _frames(45)
		var img: Image = g.get_viewport().get_texture().get_image()
		img.save_png(shot_dir.path_join("shot_%d_%s.png" % [nshot, ("ruin" if info["ruined"] else "intact")]))
		nshot += 1

	# ---- you can walk in through a cottage door (no lip, nothing in the way) ----
	var walked := "no intact cottage found"
	var walk_ok := false
	for info in b.infos:
		if info["ruined"]:
			continue
		var nm2: String = b.label_at(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) + int(info["h"]) - 45))
		if not ("Cottage" in nm2 or "Dwelling" in nm2):
			continue
		var ox := 10                                  # YARD + 2
		var base_row := int(info["y0"]) + int(info["h"]) - 40
		var start_col := int(info["x0"]) + ox - 8
		_go(_cell_pos(start_col, base_row - 12))
		await _frames(30)
		g.test_move = -1     # on screen, left is toward higher columns (where the house is)
		await _frames(150)
		g.test_move = 0
		var a_now: float = fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU)
		var col_now := int(a_now / TAU * Defs.SH_N[0])
		# it must get through the doorway: past the wall into (or through) the house
		var moved := posmod(col_now - start_col, Defs.SH_N[0])
		walk_ok = moved > 16 and moved < Defs.SH_N[0] / 2
		walked = "%s: walked from column %d to %d (the inside starts at %d)" % [nm2, start_col, col_now, int(info["x0"]) + ox + 6]
		break
	_ok("you can walk into a cottage through its door", walk_ok, walked)

	# ---- digging next to a ruin takes only what you dig: the rest stands ----
	var dug_ok := true
	var dug_lines := []
	var nr := 0
	for info in b.infos:
		if not info["ruined"] or nr >= 3:
			continue
		var cells2: PackedInt32Array = info["cells"]
		if cells2.size() < 40:
			continue
		nr += 1
		var sc0b := _scan(g.gpu.read_world(), info)
		var kmid: int = cells2[cells2.size() / 2]
		var wi: int = int(info["w"])
		var dpos := _cell_pos(int(info["x0"]) + kmid % wi, int(info["y0"]) + kmid / wi)
		_go(dpos + dpos.normalized() * 30.0)
		await _frames(20)
		for f in 10:
			g.brushes.append([dpos, 3.0, 1, 0, 4, 0, 0, 3])
			await _frames(1)
		await _frames(240)
		var sc1b := _scan(g.gpu.read_world(), info)
		var lost := int(sc0b["solid"]) - int(sc1b["solid"])
		dug_lines.append("%d -> %d" % [sc0b["solid"], sc1b["solid"]])
		# the hole itself is ~30 cells; allow what that brings down nearby, not the building
		if lost > 60 + int(sc0b["solid"]) / 20:
			dug_ok = false
	_ok("digging next to a ruin doesn't bring it down", dug_ok and nr > 0, "built cells before -> after: " + ", ".join(dug_lines))

	# ---- open a chest ----
	var chest := Vector2i(-1, -1)
	for info in b.infos:
		if not info["ruined"] and info["chests"].size() > 0:
			chest = info["chests"][0]
			break
	var cobj = _chest_obj(chest)
	if cobj != null:
		_go(_cell_pos(chest.x - 6, chest.y - 10))
		await _frames(40)
		var before := 0
		for m in Defs.NM:
			before += g.player.inv[m]
		g._try_open_chest()
		await _frames(45)
		var after := 0
		for m in Defs.NM:
			after += g.player.inv[m]
		_ok("F opens a chest and gives loot", cobj.opened and after > before, "opened %s, satchel %d -> %d" % [cobj.opened, before, after])
		_ok("an opened chest stays behind", g.chests.has(cobj) and cobj.opened, "")
		# right-click leaves a building's back wall alone; Shift + right-click (deconstruct) takes it
		var raw2: PackedByteArray = g.gpu.read_world()
		var boff: int = Defs.total_cells() * 4
		var wall := Vector2i(-1, -1)
		for dj in range(12, 26):
			for di in range(-8, 20):
				var col2 := posmod(chest.x + di, Defs.SH_N[0])
				var row2 := chest.y - dj
				var k2 := (row2 * Defs.SH_N[0] + col2) * 4
				if (raw2.decode_u32(k2) & 255) == 0 and (raw2.decode_u32(boff + k2) & 0x4000) != 0:
					wall = Vector2i(col2, row2)
					break
			if wall.x >= 0:
				break
		if wall.x >= 0:
			var wp := _cell_pos(wall.x, wall.y)
			for f in 20:
				g.brushes.append([wp, 2.5, 1, 0, 4, 0, 0, 0])
				await _frames(1)
			var r3: PackedByteArray = g.gpu.read_world()
			var kk := (wall.y * Defs.SH_N[0] + wall.x) * 4
			var still_wall := (r3.decode_u32(boff + kk) & 0x4000) != 0
			for f in 30:
				g.brushes.append([wp, 2.5, 8, 0, 4, 0, 0, 0])
				await _frames(1)
			var r4: PackedByteArray = g.gpu.read_world()
			var gone := (r4.decode_u32(boff + kk) & 255) == 0
			_ok("right-click leaves a building's back wall alone", still_wall, "")
			_ok("Shift + right-click deconstructs it", gone, "")
		else:
			_ok("right-click leaves a building's back wall alone", false, "no back wall found near the chest")
	else:
		_ok("F opens a chest and gives loot", false, "no intact chest found")

	# ---- a chest whose floor is dug out falls, whole (it doesn't float or come apart) ----
	var chest2 := Vector2i(-1, -1)
	var nfound := 0
	for info in b.infos:
		if not info["ruined"] and info["chests"].size() > 0:
			nfound += 1
			if nfound == 2:
				chest2 = info["chests"][0]
				break
	var c2obj = _chest_obj(chest2)
	if c2obj != null:
		var r_before: float = c2obj.pos.length()
		_go(_cell_pos(chest2.x - 14, chest2.y - 10))
		await _frames(30)
		for f in 70:
			for dx in range(-2, Defs.CHEST_W + 3, 2):
				# owner slot 3 (nobody): digging next to a chest would otherwise open it
				g.brushes.append([_cell_pos(chest2.x + dx, chest2.y + 2), 3.2, 1, 0, 4, 0, 0, 3])
			await _frames(1)
		await _frames(150)
		var dropped: float = r_before - c2obj.pos.length()
		_ok("a chest falls when its floor is dug out", dropped > 2.0 and not c2obj.opened, "it dropped %.1f cells, in one piece" % dropped)
	else:
		_ok("a chest falls when its floor is dug out", false, "no second intact chest found")

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

	# ---- a mage standing still stays still (no jiggling up and down after landing) ----
	var sp0 := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
	_go(sp0 * (g.gpu.surf_at(g.spawn_angle).x + 25.0))
	await _frames(90)
	var r_min := 1e9
	var r_max := -1e9
	var grounded := 0
	for f in 120:
		await _frames(1)
		var rr: float = g.player.pos.length()
		r_min = minf(r_min, rr)
		r_max = maxf(r_max, rr)
		if g.player.on_ground:
			grounded += 1
	_ok("a mage standing still doesn't jiggle", r_max - r_min < 0.3 and grounded == 120, "moved %.2f cells up and down, on the ground %d of 120 frames" % [r_max - r_min, grounded])

	# ---- trees stand when you walk up to them, in every biome (tall ones, and ones rooted in
	# marsh mud, used to fall apart) ----
	var N0: int = Defs.SH_N[0]
	var toff: int = Defs.total_cells() * 4
	var raw_t: PackedByteArray = g.gpu.read_world()
	var tree_lines := []
	var tree_ok := true
	var biomes_seen := 0
	for bname in ["forest", "marsh", "mountain", "tundra", "desert", "ashland", "ocean"]:
		var best_col := -1
		var best_n := 0
		for k in 64:
			var c0 := k * N0 / 64
			if b.biome(c0 + 60) != bname or b.biome(c0) != bname:
				continue
			var n_t := _plants(raw_t, toff, c0, b.ground_row(c0 + 60))
			if n_t > best_n:
				best_n = n_t
				best_col = c0
		if best_col < 0 or best_n < 40:
			continue
		biomes_seen += 1
		var gr2: int = b.ground_row(best_col + 60)
		_go(_cell_pos(best_col + 60, gr2 - 30))
		await _frames(200)
		var after_t := _plants(g.gpu.read_world(), toff, best_col, gr2)
		tree_lines.append("%s %d->%d" % [bname, best_n, after_t])
		if after_t < int(best_n * 0.97):
			tree_ok = false
	_ok("trees stand when you come near, in every biome", tree_ok and biomes_seen > 0, ", ".join(tree_lines))

	# ---- sand (and other powders) is generated resting: nothing pours when you arrive ----
	var sand_col := -1
	for k in 64:
		var c1 := k * N0 / 64
		if b.biome(c1) == "desert" and b.biome(c1 + 150) == "desert":
			sand_col = c1
			break
	if sand_col >= 0:
		var sg: int = b.ground_row(sand_col + 75)
		var before_p := _powders(g.gpu.read_world(), sand_col, sg)
		_go(_cell_pos(sand_col + 75, sg - 30))
		await _frames(150)
		var after_p := _powders(g.gpu.read_world(), sand_col, sg)
		var moved := 0
		for key in before_p:
			if not after_p.has(key):
				moved += 1
		_ok("generated sand stays put when you arrive", moved <= maxi(4, before_p.size() / 100), "%d of %d powder cells moved" % [moved, before_p.size()])
	else:
		_ok("generated sand stays put when you arrive", true, "no desert on this planet")

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
	# watch it frame by frame: it should creak while it is still in place, then drop
	var creaking := false
	var gone_at := -1
	var max_creak := 0
	for f in 120:
		await _frames(1)
		var here: bool = g.type_at(mid) == Defs.STONE
		max_creak = maxi(max_creak, g.gpu.counts[56])
		if here and g.gpu.counts[56] > 0:
			creaking = true
		if not here and gone_at < 0:
			gone_at = f
	var still: bool = g.type_at(mid) == Defs.STONE
	_ok("a loose block creaks first, then falls", placed and creaking and not still, "placed %s, creaked %s (max %d cells), left its spot at frame %d" % [placed, creaking, max_creak, gone_at])
	g.test_god = false
	g.hp = g.max_hp
	g.iframes = 0
	var hp0: float = g.hp
	g.brushes.append([g.player.pos + up * 20.0, 1.8, 5, Defs.STONE, 0, 8, 0])
	await _frames(150)
	_ok("falling rock hurts the mage", g.hp < hp0, "health %.0f -> %.0f" % [hp0, g.hp])
	g.test_god = true
	g.hp = g.max_hp

	# ---- co-op groundwork: a second mage far away gets its own simulation, collisions and loot ----
	# somewhere far away on open ground (not on a building, where it would stand on the roof)
	var a2: float = g.spawn_angle + 0.6
	for k in 40:
		var at: float = g.spawn_angle + 0.6 + k * 0.03
		var probe: Vector2 = Vector2(cos(at), sin(at)) * (g.gpu.surf_at(at).x + 10.0)
		var clear := true
		for dk in [-60.0, 0.0, 60.0]:
			var q: Vector2 = Vector2(cos(at + dk / Defs.RS0), sin(at + dk / Defs.RS0)) * probe.length()
			if b.label_at(q) != "":
				clear = false
		if clear:
			a2 = at
			break
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
	await _frames(120)
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

	# ---- the Wisp Forge lists its recipes and crafts ----
	g.ui.show_forge()
	await _frames(2)
	var cards := 0
	for c in g.ui.forge_list.get_children():
		if c is GridContainer:
			cards += c.get_child_count()
	g.ui.hide_forge()
	var wide: Dictionary = {}
	for r in Defs.RECIPES:
		if r["id"] == "wide":
			wide = r
	var crafted := false
	if not wide.is_empty():
		g.dig_r = 7.5
		for k in wide["cost"]:
			g.player.inv[int(k)] += int(wide["cost"][k])
		crafted = g.craft(wide) and g.dig_r >= 11.0
	_ok("the Wisp Forge lists recipes and crafts", cards == Defs.RECIPES.size() and crafted, "%d of %d recipe cards, crafting %s" % [cards, Defs.RECIPES.size(), "works" if crafted else "failed"])

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
