extends RefCounted
const Props := preload("res://scripts/props.gd")
const Build := preload("res://scripts/build.gd")
const FoeAI := preload("res://scripts/foe_ai.gd")
const Ecology := preload("res://scripts/ecology.gd")
const Skiff := preload("res://scripts/skiff.gd")
## Automated checks. "Run tests.bat" starts the game with --test: it builds a fresh planet in
## saves/test (your real saves are untouched), plays it for a while, checks that the important
## things still work, writes saves/test_report.txt and quits.

var g                       # the game (main.gd)
var lines := []
var passed := 0
var failed := 0
var start_pos := Vector2.ZERO  # where you arrived on the planet (the wild-life checks are set up near it, as
                               # when run alone: the full run's earlier checks leave you somewhere else each time)
var worst_us := 0           # the longest frame since this was last reset (a hitch shows here)
var _last_us := 0

func _ok(name: String, cond: bool, detail := "") -> void:
	lines.append(("PASS  " if cond else "FAIL  ") + name + ("   [" + detail + "]" if detail != "" else ""))
	# (straight to the log as well, with the time: a run that runs out of time still shows how far
	# it got and how long each part took)
	print("[test %.0fs] " % (Time.get_ticks_msec() / 1000.0), lines[lines.size() - 1].left(400))
	if cond:
		passed += 1
	else:
		failed += 1

func _frames(n: int) -> void:
	for k in n:
		await g.get_tree().process_frame
		var now := Time.get_ticks_usec()
		if _last_us > 0:
			worst_us = maxi(worst_us, now - _last_us)
		_last_us = now

## a profiler section's recent peak, in ms ("lifting pieces out: 3.2")
func _peak(sec: String) -> String:
	var p = g.prof.get(sec)
	return "%s %.1f ms" % [sec, (p[3] / 1000.0) if p != null else 0.0]

## a cell's middle; with a structure's anchor (its x0, w) as its stamp put it, cell for cell
func _cell_pos(col: int, row: int, ax := -1, aw := 1) -> Vector2:
	if ax < 0:
		var a := (float(posmod(col, Defs.NS)) + 0.5) / Defs.NS * TAU
		return Vector2(cos(a), sin(a)) * (Defs.R_TOP - (float(row) + 0.5))
	return Defs.stamp_pos(row, ax, aw, Defs.k_of(col, ax))

## Ore gear (Defs.GEAR): each piece is hidden at the forge until its ore is found (but for the first of
## each ore, shown locked), then forged with its cost and does what its "mods" say (main `gear`); and a few
## of them tried for real: the Silver Sigil's cheaper spells, the Bog Iron Spade's reach, the Amber Totem's
## calm creatures. Everything is put back as it was afterwards.
func _test_gear() -> void:
	var ge_items0: Dictionary = g.items.duplicate(true)
	var ge_vals0 := [g.max_hp, g.max_mana, g.mana_regen, g.dig_r, g.hp]
	var ge_inv0: PackedInt32Array = g.player.inv.duplicate()
	for ge_k in g.items.keys():
		if String(ge_k).begins_with("found_"):
			g.items.erase(ge_k)
	for ge_om in range(Defs.FIREOPAL, Defs.SILVER + 1):
		g.player.inv[ge_om] = 0
	# hidden: all but the first piece of each ore, until it's found
	var ge_hid := 0
	var ge_first := 0
	for ge_r in g.recipes:
		if ge_r.has("gear"):
			if g.recipe_hidden(ge_r):
				ge_hid += 1
			elif not g.recipe_unlocked(ge_r):
				ge_first += 1
	var ge_hide_ok := ge_first == Defs.KIND_ORES.size() and ge_hid == Defs.GEAR.size() - Defs.KIND_ORES.size()
	# forge each, and check its stats
	g.dig_r = maxf(g.dig_r, 11.0)                 # (the Rime Lens builds on Wide Excavation)
	var ge_bad := []
	for ge_id in Defs.GEAR:
		var ge_d: Dictionary = Defs.GEAR[ge_id]
		var ge_rec: Dictionary = {}
		for ge_r2 in g.recipes:
			if ge_r2["id"] == ge_id:
				ge_rec = ge_r2
		var ge_mods: Dictionary = ge_d["mods"]
		var ge_before := {}
		for ge_st in ge_mods:
			ge_before[ge_st] = g.gear(ge_st)
		var ge_hp0: float = g.max_hp
		var ge_mana0: float = g.max_mana
		for ge_c in ge_d["cost"]:
			g.player.inv[int(ge_c)] += int(ge_d["cost"][ge_c])
		var ge_made: bool = g.craft(ge_rec) and g.recipe_done(ge_rec)
		var ge_good := ge_made
		for ge_st2 in ge_mods:
			var ge_v := float(ge_mods[ge_st2])
			match String(ge_st2):
				"max_hp": ge_good = ge_good and absf(g.max_hp - ge_hp0 - ge_v) < 0.01
				"max_mana": ge_good = ge_good and absf(g.max_mana - ge_mana0 - ge_v) < 0.01
				"mana_regen": pass
				"dig_r": ge_good = ge_good and g.dig_r >= ge_v
				_:
					var ge_want: float = float(ge_before[ge_st2]) + ge_v if Defs.GEAR_ADD.has(ge_st2) else float(ge_before[ge_st2]) * ge_v
					ge_good = ge_good and absf(g.gear(ge_st2) - ge_want) < 0.001
		if not ge_good:
			ge_bad.append(ge_id)
	var ge_breath: float = g.max_breath
	var ge_cost_k: float = g.gear("mana_cost")
	var ge_reach_k: float = g.gear("reach")
	# the Silver Sigil (and the alloys' cheaper spells): a Spark Bolt costs less
	g.player.mana = g.player.max_mana
	g.player.cast_cd = 0
	var ge_m0: float = g.player.mana
	g._cast(g.player, "spark", g.player.pos + g.player.pos.normalized() * 40.0)
	var ge_spent: float = ge_m0 - g.player.mana
	# the Bog Iron Spade: digging reaches further
	var ge_reach: float = g._reach(g.player, g.player.pos + g.player.pos.normalized().orthogonal() * 500.0).distance_to(g.player.pos)
	# the Amber Totem: a wild creature beside you leaves you be, until you strike it
	var ge_st := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) + 30, 70, 50, 4)
	var ge_a: float = (float(ge_st.x) + 10.5) / float(Defs.NS) * TAU
	var ge_b: float = (float(ge_st.x) + 40.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(ge_a), sin(ge_a)) * (g.gpu.surf_at(ge_a).x + 10.0))
	await _frames(30)
	for ge_e in g.enemies.duplicate():
		if not ge_e.boss and ge_e.guard_id < 0:
			g.enemies.erase(ge_e)
	var ge_god0: bool = g.test_god
	g.test_god = false
	g.spawn_timer = 999999
	g.player.hp = g.player.max_hp
	var ge_cr = g.spawn_enemy("c_boar", Vector2(cos(ge_b), sin(ge_b)) * (g.gpu.surf_at(ge_b).x + 9.0))
	var ge_calm := true
	for ge_f in 120:
		await _frames(1)
		if ge_cr.see or ge_cr.alert_t > 0:
			ge_calm = false
	var ge_hp1: float = g.player.hp
	g._hurt_enemy(ge_cr, 1.0, 0.0, 0.0)
	var ge_roused := false
	for ge_f2 in 60:
		await _frames(1)
		if ge_cr.see or ge_cr.alert_t > 0:
			ge_roused = true
	g.enemies.erase(ge_cr)
	g.test_god = ge_god0
	g.spawn_timer = 600
	# (everything back as it was)
	g.items.clear()
	for ge_k2 in ge_items0:
		g.items[ge_k2] = ge_items0[ge_k2]
	g.max_hp = ge_vals0[0]
	g.max_mana = ge_vals0[1]
	g.mana_regen = ge_vals0[2]
	g.dig_r = ge_vals0[3]
	g.player.hp = minf(float(ge_vals0[4]), g.max_hp)
	for ge_i in ge_inv0.size():
		g.player.inv[ge_i] = ge_inv0[ge_i]
	g._apply_gear()
	_ok("ore gear: hidden until its ore is found, forged, and each piece does what it says", ge_hide_ok and ge_bad.is_empty() and absf(ge_spent - float(Defs.SPELLS["spark"]["mana"]) * ge_cost_k) < 0.01 and ge_cost_k < 0.76 and absf(ge_reach - g.REACH * ge_reach_k) < 0.5 and ge_reach_k > 1.39 and ge_calm and ge_hp1 >= g.player.max_hp - 0.01 and ge_roused and ge_breath > 1700.0,
		"%d first pieces shown locked, %d hidden (of %d); forged all but %s; a Spark Bolt cost %.2f mana with the Silver Sigil and the alloys; the spade reaches %.1f; breath %.0f; the boar beside you with the Amber Totem: calm %s (your health %.0f of %.0f), struck: it hunts %s" % [ge_first, ge_hid, Defs.GEAR.size(), str(ge_bad), ge_spent, ge_reach, ge_breath, ge_calm, ge_hp1, g.max_hp, ge_roused])

## Living towns: a village that stands fills with its folk as you come; they walk its street by day and
## keep to it, one stops to talk when you press F, and a keeper trades: buying for coins, selling for coins.
## (A picture: saves/shots/town.png.)
func _test_towns() -> void:
	var tn_god0: bool = g.test_god
	g.test_god = true
	g.spawn_timer = 999999
	var tn_t = null
	for tn_c in g.builds.towns:
		if not bool(tn_c["living"]):
			continue
		for tn_h in tn_c["houses"]:
			if Defs.SHOPS.has(tn_h["role"]) and not bool(tn_h["ruined"]) and tn_t == null:
				tn_t = tn_c
	if tn_t == null:
		_ok("living towns: folk walk the village, talk, and keepers trade", false, "no living village with a shop on this planet (%d villages)" % g.builds.towns.size())
		g.test_god = tn_god0
		g.spawn_timer = 600
		return
	var tn_mid := int(tn_t["x0"]) + int(tn_t["w"]) / 2
	var tn_a: float = (float(tn_mid) + 0.5) / float(Defs.NS) * TAU
	var tn_time0: float = g.time
	g.time = fposmod((tn_a - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)      # (midday there)
	for tn_e in g.enemies.duplicate():
		if not tn_e.boss and tn_e.guard_id < 0:
			g.enemies.erase(tn_e)
	_go(_cell_pos(tn_mid, g.builds.ground_row(tn_mid) - 14))
	await _frames(60)
	var tn_walk := []
	var tn_keep := []
	for tn_v in g.towns.folk:
		if tn_v.town["seed"] == tn_t["seed"]:
			(tn_keep if tn_v.keeper else tn_walk).append(tn_v)
	# they keep to the village and to the ground for a few seconds
	var tn_out := 0
	var tn_moved := 0.0
	var tn_p0 := {}
	for tn_v2 in tn_walk:
		tn_p0[tn_v2] = tn_v2.pos
	for tn_f in 240:
		await _frames(1)
		if tn_f == 150:
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("town.png"))
		for tn_v3 in tn_walk:
			if tn_v3.gone:
				continue
			var tn_c3 := int(fposmod(atan2(tn_v3.pos.y, tn_v3.pos.x), TAU) / TAU * Defs.NS)
			var tn_off := posmod(tn_c3 - int(tn_t["x0"]) + 30, Defs.NS)
			var tn_gr: float = g.gpu.surf_at(atan2(tn_v3.pos.y, tn_v3.pos.x)).x
			if tn_off > int(tn_t["w"]) + 60 or tn_v3.pos.length() < tn_gr - 40.0 or tn_v3.pos.length() > tn_gr + 80.0:
				tn_out += 1
	for tn_v4 in tn_walk:
		tn_moved = maxf(tn_moved, (tn_v4.pos as Vector2).distance_to(tn_p0[tn_v4]))
	# talk to one
	var tn_said := ""
	if not tn_walk.is_empty():
		g.player.pos = tn_walk[0].pos + tn_walk[0].pos.normalized() * 2.0
		if g.towns.talk(g.player):
			# (whoever was nearest answered: not always the one you stood by, with folk walking past)
			for tn_v in tn_walk + tn_keep:
				if tn_said == "" and String(tn_v.say) != "":
					tn_said = tn_v.say
	# trade with a keeper
	var tn_shop := false
	var tn_buy := false
	var tn_sold := false
	var tn_c0: int = int(g.items.get("coins", 0))
	if not tn_keep.is_empty():
		var tn_k = tn_keep[0]
		g.player.pos = tn_k.pos
		tn_shop = g.towns.talk(g.player) and g.state == "shop"
		g.items["coins"] = 100
		var tn_first: Dictionary = g.towns.shop_def(tn_k)["sell"][0]
		var tn_price: int = g.towns.price_of(tn_k, tn_first)
		tn_buy = g.towns.buy(tn_k, 0) and int(g.items["coins"]) == 100 - tn_price
		var tn_b: Array = g.towns.buys(tn_k)[0]
		g.player.inv[int(tn_b[0])] += int(tn_b[1])
		var tn_cb: int = int(g.items["coins"])
		tn_sold = g.towns.sell(tn_k, int(tn_b[0])) and int(g.items["coins"]) == tn_cb + int(tn_b[2])
		await _frames(10)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("shop.png"))
		g.towns.close_shop()
	g.items["coins"] = tn_c0
	await _test_town_days(tn_t, tn_mid)
	_test_requests(tn_t)
	_test_kind_trade()
	g.time = tn_time0
	g.test_god = tn_god0
	g.spawn_timer = 600
	_ok("living towns: folk walk the village, talk, and keepers trade", tn_walk.size() >= 2 and not tn_keep.is_empty() and tn_out == 0 and tn_moved > 4.0 and tn_said != "" and tn_shop and tn_buy and tn_sold and g.state == "play",
		"%s: %d walking, %d keepers (%s); none strayed from the village or the ground (%d strays), furthest one walked %.0f cells; one said \"%s\"; the shop opened %s, bought %s, sold %s" % [tn_t["name"], tn_walk.size(), tn_keep.size(), ", ".join(tn_keep.map(func(kk): return "%s the %s" % [kk.name, kk.role])), tn_out, tn_moved, tn_said, tn_shop, tn_buy, tn_sold])

## Sky events: each started on its own for a few seconds (they never start by themselves in test mode),
## at night for the night ones, on a clear stretch of open ground, with a picture of each
## (saves/shots/sky_<id>.png). main's `sky_stats` counts what each did.

## a village's day: at night its folk go home and sleep, in the morning they come out again; who'd be where
## at each hour (towns.gd `want_place`)

## every spell's effects (vfx.gd): it casts, flies and lands with its own look, the particles die away, and it
## costs the frame little. Pictures of each in flight and landing (saves/shots/vfx_<spell>_fly.png, _hit.png),
## by night (where glow shows) and the fireball by day too.

## the pixel-art UI: its font has every character the game writes, it's drawn at a whole pixel scale, the
## satchel and the spell bar are where the mouse finds them; pictures of the HUD, the forge, a shop, the
## settings and the title (saves/shots/ui_*.png)
func _test_ui() -> void:
	var ui = g.ui
	var dir: String = g._real_save_dir().path_join("shots")
	var bad := []
	var f: FontFile = ui.font
	for ch in "AZaz09·…✦✓—'\"()[]%:,.!?":
		if not f.has_char(ch.unicode_at(0)):
			bad.append("no glyph for %s" % ch)
	if ui.root.scale.x != float(ui.U) or ui.U < 1:
		bad.append("the UI isn't at a whole pixel scale")
	# give the satchel and spell bar something to show
	var inv0: Array = Array(g.player.inv).duplicate()
	var known0: Array = g.known.duplicate()
	for m in [Defs.STONE, Defs.DIRT, Defs.SAND, Defs.WOOD, Defs.COPPER, Defs.COAL, Defs.WISP, Defs.CRYSTAL, Defs.GLASS, Defs.BRICK, Defs.WATER, Defs.STARIRON, Defs.FIREOPAL, Defs.AMBER]:
		g.player.inv[m] += 25
	for sp in Defs.SPELL_ORDER:
		if not g.known.has(sp):
			g.known.append(sp)
	g.ui._inv_key = ""
	g.ui._hot_key = ""
	g.ui.toast("Spark Bolt learned", Color(0.6, 0.9, 1.0), 4.0)
	g.ui.toast("+ 12 Stone, 4 Copper", Color(0.95, 0.85, 0.55), 4.0)
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_hud_pouch.png"))
	g.ui.satchel_open = true
	g.ui._inv_key = ""
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_hud.png"))
	var sr: Rect2 = ui._on_screen(ui.satchel_panel)
	var hr: Rect2 = ui._on_screen(ui.hotbar)
	var vs: Vector2 = g.get_viewport().get_visible_rect().size
	if sr.size.x < 50 or not Rect2(Vector2.ZERO, vs).encloses(sr):
		bad.append("the satchel is off the screen (%s)" % sr)
	if hr.size.x < 50 or not Rect2(Vector2.ZERO, vs).encloses(hr):
		bad.append("the spell bar is off the screen (%s)" % hr)
	var slots: int = ui.satchel.get_child_count()
	g.ui.satchel_open = false
	g.ui._inv_key = ""
	g.ui.show_forge()
	await _frames(10)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_forge.png"))
	var fr: Rect2 = ui._on_screen(ui.forge)
	if not Rect2(Vector2.ZERO, vs).encloses(fr):
		bad.append("the forge doesn't fit the screen (%s)" % fr)
	g.ui.hide_forge()
	ui.settings_panel.visible = true
	ui._refresh_settings()
	await _frames(10)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_settings.png"))
	ui.settings_panel.visible = false
	# a shop, if a keeper is about
	var shop_shot := false
	for v in g.towns.folk:
		if v.keeper:
			g.towns.open_shop(v)
			await _frames(10)
			g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_shop.png"))
			g.towns.close_shop()
			shop_shot = true
			break
	ui.show_title(true)
	await _frames(30)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_title.png"))
	# the main menu's buttons share one width; Play opens the journeys, whose rows line up
	var mw := {}
	for mb in ui.title.box.get_children():
		mw[int(ui._on_screen(mb).size.x)] = true
	if mw.size() != 1:
		bad.append("the main menu's buttons differ in width (%s)" % str(mw.keys()))
	ui.title.show_slots()
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_slots.png"))
	var xs := {}
	var ws := {}
	for sbn in ui.title.slot_btns:
		var r: Rect2 = ui._on_screen(sbn)
		var rr: Rect2 = ui._on_screen(sbn.get_parent().get_child(sbn.get_parent().get_child_count() - 1))
		xs[int(r.position.x)] = true
		ws[int(rr.end.x)] = true
	if xs.size() != 1 or ws.size() != 1 or ui.title.box.visible:
		bad.append("the journeys don't line up (lefts %s, rights %s)" % [str(xs.keys()), str(ws.keys())])
	ui.title.show_main()
	ui.title.visible = false
	# every beast's frames have a clear edge: nothing (a tail) cut off by the picture's border
	var BA = load("res://scripts/boss_art.gd")
	var beasts := {}
	var sheet := []
	for cid in Defs.CREATURES:
		beasts["c_" + cid] = Defs.CREATURES[cid]["body"]
	for bid in Defs.BOSSES:
		beasts["boss_" + bid] = Defs.BOSSES[bid]["body"]
	for bk in beasts:
		var bd: Dictionary = beasts[bk]
		if String(bd["plan"]) != "beast":
			continue
		var frs: Dictionary = BA.frames(bk, bd)
		sheet.append(frs[bk + "_walk1"])
		for fk in frs:
			var im: Image = frs[fk]
			for y in im.get_height():
				if im.get_pixel(0, y).a > 0.5 or im.get_pixel(im.get_width() - 1, y).a > 0.5:
					bad.append("%s is cut off at its picture's edge" % fk)
					break
	# a sheet of every beast (walking), 4x, on the sky's colour: saves/shots/beasts.png
	var sw := 0
	var sh := 0
	for im2 in sheet:
		sw += (im2 as Image).get_width() * 4 + 8
		sh = maxi(sh, (im2 as Image).get_height() * 4)
	var out := Image.create(maxi(sw, 1), sh + 8, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.35, 0.5, 0.62))
	var ox := 4
	for im3 in sheet:
		var big: Image = (im3 as Image).duplicate()
		big.resize(big.get_width() * 4, big.get_height() * 4, Image.INTERPOLATE_NEAREST)
		out.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), Vector2i(ox, 4 + sh - big.get_height()))
		ox += big.get_width() + 8
	out.save_png(dir.path_join("beasts.png"))
	# every creature's daily-life poses (ecology.gd), 3x, in rows: saves/shots/poses.png
	var pz := []
	for pc in Defs.CREATURES:
		var pfr: Dictionary = BA.frames("c_" + pc, Defs.CREATURES[pc]["body"])
		for suf in ["", "_graze", "_sleep", "_croak", "_crouch", "_perch"]:
			if pfr.has("c_" + pc + suf):
				pz.append(pfr["c_" + pc + suf])
	var prow_w := 1800
	var pimg := Image.create(prow_w, 900, false, Image.FORMAT_RGBA8)
	pimg.fill(Color(0.35, 0.5, 0.62))
	var px0 := 4
	var py0 := 4
	var prow_h := 0
	for im4 in pz:
		var big2: Image = (im4 as Image).duplicate()
		big2.resize(big2.get_width() * 3, big2.get_height() * 3, Image.INTERPOLATE_NEAREST)
		if px0 + big2.get_width() > prow_w:
			px0 = 4
			py0 += prow_h + 6
			prow_h = 0
		if py0 + big2.get_height() < 900:
			pimg.blend_rect(big2, Rect2i(Vector2i.ZERO, big2.get_size()), Vector2i(px0, py0))
		px0 += big2.get_width() + 6
		prow_h = maxi(prow_h, big2.get_height())
	pimg.save_png(dir.path_join("poses.png"))
	# every creature standing beside the mage, 4x, feet on one line: saves/shots/lineup.png (sizes true to life)
	var lu := [Defs.sprite_texture("mage").get_image()]
	for lc in Defs.CREATURES:
		var lfr: Dictionary = BA.frames("c_" + lc, Defs.CREATURES[lc]["body"])
		var lkey: String = "c_" + lc + ("_head" if String(Defs.CREATURES[lc]["body"]["plan"]) == "serpent" else "")
		if lfr.has(lkey):
			lu.append(lfr[lkey])
	var lw := 4
	var lh := 0
	for im5 in lu:
		lw += (im5 as Image).get_width() * 4 + 4
		lh = maxi(lh, (im5 as Image).get_height() * 4)
	var limg := Image.create(lw, lh + 12, false, Image.FORMAT_RGBA8)
	limg.fill(Color(0.35, 0.5, 0.62))
	var lx := 4
	for im6 in lu:
		var big3: Image = (im6 as Image).duplicate()
		big3.convert(Image.FORMAT_RGBA8)
		# (as the game draws them: the lowest opaque row on the line, overlay `_gap_under`)
		var lgap := 0
		for lyy in range(big3.get_height() - 1, -1, -1):
			var lany := false
			for lxx in big3.get_width():
				if big3.get_pixel(lxx, lyy).a > 0.5:
					lany = true
					break
			if lany:
				lgap = big3.get_height() - 1 - lyy
				break
		big3.resize(big3.get_width() * 4, big3.get_height() * 4, Image.INTERPOLATE_NEAREST)
		limg.blend_rect(big3, Rect2i(Vector2i.ZERO, big3.get_size()), Vector2i(lx, 4 + lh - big3.get_height() + lgap * 4))
		lx += big3.get_width() + 4
	limg.save_png(dir.path_join("lineup.png"))
	for k in g.player.inv.size():
		g.player.inv[k] = int(inv0[k])
	g.known = known0
	g.ui._inv_key = ""
	g.ui._hot_key = ""
	_ok("the pixel-art UI: its own font, whole pixels, everything on screen", bad.is_empty(),
		("UI pixel %d screen pixels; %d satchel slots; satchel at %s, spells at %s%s" % [ui.U, slots, sr, hr, "; a shop too" if shop_shot else ""]) if bad.is_empty() else "; ".join(bad))


## a planet kind's hazards (tried with Verdance's climate turned to them): the cold under the open sky and the
## sun at midday hurt you slowly, unless their ward bears them ("hazards" runs it alone)
func _test_hazards() -> void:
	# ---- a planet kind's hazards (tried here with Verdance's climate turned to them): the cold under the
	# open sky and the sun at midday hurt you slowly, unless their ward (or a guardian's relic) bears them ----
	for hz_e in g.enemies.duplicate():
		if not hz_e.boss and hz_e.guard_id < 0:
			g.enemies.erase(hz_e)
	var hz_god0: bool = g.test_god
	var hz_time0: float = g.time
	g.spawn_timer = 999999                     # (no foe wanders in and muddles the sums)
	# (out on a clear stretch under the open sky: where the earlier checks left you there may be a roof or
	# a tree over you)
	var hz_pos0: Vector2 = g.player.pos
	var hz_st := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) - 20, 40, 80, 6)
	var hz_a: float = (float(hz_st.x) + 20.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(hz_a), sin(hz_a)) * (g.gpu.surf_at(hz_a).x + 12.0))
	await _frames(40)
	g.test_god = false
	await _frames(8)
	var hz_open: bool = g.exposed
	var hz_res := {}
	var hz_why := []
	for hz_k in ["cold", "sun"]:
		var hz_d: Dictionary = Defs.HAZARDS[hz_k]
		if hz_k == "sun":
			# (the sun straight overhead)
			var hz_pa: float = atan2(g.player.pos.y, g.player.pos.x)
			g.time = fposmod((hz_pa - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)
		g.clim[hz_k] = 1.0
		g.player.hp = g.player.max_hp
		await _hz_watch(150, hz_k + " bare", hz_why)
		var hz_bare: float = g.player.max_hp - g.player.hp
		var hz_was: String = g.hazard
		g.items[String(hz_d["ward"])] = true
		g.player.hp = g.player.max_hp
		await _hz_watch(120, hz_k + " warded", hz_why)
		var hz_ward: float = g.player.max_hp - g.player.hp
		g.items.erase(String(hz_d["ward"]))
		g.clim[hz_k] = 0.0
		hz_res[hz_k] = [hz_bare, hz_ward, hz_was]
	g.time = hz_time0
	g.spawn_timer = 600
	# (and digging what the staff can't cut no longer counts as star iron: the GPU's counters moved)
	var hz_si0: int = g.player.inv[Defs.STARIRON]
	var hz_up: Vector2 = g.player.pos.normalized()
	g.brushes.append([hz_up * (g.gpu.surf_at(atan2(hz_up.y, hz_up.x)).x - 110.0), 6.0, 1, 0, 0, 0, 0, 0])
	var hz_blk := false
	for hz_f in 8:
		await _frames(1)
		hz_blk = hz_blk or g.dig_blocked > 0
	var hz_si1: int = g.player.inv[Defs.STARIRON]
	g.test_god = hz_god0
	g.player.hp = g.player.max_hp
	_go(hz_pos0)
	await _frames(20)
	var hz_ok := hz_open and hz_blk and hz_si1 == hz_si0
	for hz_k2 in hz_res:
		hz_ok = hz_ok and float(hz_res[hz_k2][0]) > 0.8 and float(hz_res[hz_k2][1]) < 0.05 and String(hz_res[hz_k2][2]) == hz_k2
	_ok("a planet's cold and midday sun hurt you in the open, but not with their wards; too-hard digging gives no star iron", hz_ok,
		"in the open %s; the cold: -%.1f health in 2.5 s bare (%s), -%.1f with the Hearth Charm; the sun overhead: -%.1f bare (%s), -%.1f with the Sun Veil; digging stone with no power: blocked %s, star iron %d -> %d" % [hz_open,
		float(hz_res["cold"][0]), hz_res["cold"][2], float(hz_res["cold"][1]), float(hz_res["sun"][0]), hz_res["sun"][2], float(hz_res["sun"][1]), hz_blk, hz_si0, hz_si1] + ("" if hz_ok else "; what hurt: " + "; ".join(hz_why.slice(0, 12))))

## wait n frames noting every hurt: when, how much, and what was about (the hazard, fire or lava near, foes)
func _hz_watch(n: int, phase: String, why: Array) -> void:
	var hp: float = g.player.hp
	for k in n:
		await _frames(1)
		var d: float = hp - g.player.hp
		hp = g.player.hp
		if d > 0.3 and why.size() < 40:
			var hot := 0
			var l: Vector2 = g.to_grid(g.player.pos)
			for y in range(int(l.y) - 10, int(l.y) + 11):
				for x in range(int(l.x) - 10, int(l.x) + 11):
					var t: int = g.gtype(x, y)
					if t == Defs.FIRE or t == Defs.LAVA:
						hot += 1
			var foes := 0
			for e in g.enemies:
				if not e.dead and (e.pos as Vector2).distance_to(g.player.pos) < 40.0:
					foes += 1
			why.append("%s f%d -%.1f (hazard '%s', fire/lava %d, foes %d, liquid %s, breath %.0f, warm %s)" % [phase, k, d, g.hazard, hot, foes, g.player.in_liquid, g.player.breath, g._warm])

func _test_vfx() -> void:
	var vx_god0: bool = g.test_god
	var vx_from: Vector2 = g.player.pos
	var vx_time0: float = g.time
	g.test_god = true
	g.spawn_timer = 999999
	var vx_base := int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) + 60
	var vx_ri := 0
	var vx_dir: String = g._real_save_dir().path_join("shots")
	var vx_txt := []
	var vx_bad := []
	var vx_peak := 0
	var vx_cost := 0.0
	for vx_e in g.enemies.duplicate():
		if not vx_e.boss and vx_e.guard_id < 0:
			g.enemies.erase(vx_e)
	# Spark Bolt is one bolt a click: holding the button fires it once, a new click again
	var sp_sel0: int = g.sel
	if not g.known.has("spark"):
		g.known.append("spark")
	g.sel = g.known.find("spark")
	g.player.mana = g.player.max_mana
	g.player.cast_cd = 0
	var sp_c0: int = int(g.vfx.stats.get("casts", 0))
	var sp_m0: float = g.player.mana
	g.test_aim = g.player.pos + g.player.pos.normalized().orthogonal() * 60.0
	g.test_cast = true
	await _frames(2)
	var sp_spent: float = sp_m0 - g.player.mana            # (before the mana comes back)
	await _frames(88)
	var sp_held: int = int(g.vfx.stats.get("casts", 0)) - sp_c0
	g.test_cast = false
	await _frames(3)
	g.test_cast = true
	await _frames(3)
	g.test_cast = false
	var sp_again: int = int(g.vfx.stats.get("casts", 0)) - sp_c0
	g.test_aim = Vector2.ZERO
	g.sel = sp_sel0
	_ok("Spark Bolt fires once a click, not while the button is held, and costs more mana", sp_held == 1 and sp_again == 2 and sp_spent >= 11.0,
		"held 1.5 s: %d bolt, %.1f mana; clicked again: %d in all" % [sp_held, sp_spent, sp_again])
	var vx_runs := [["spark", "night"], ["fireball", "night"], ["frost", "night"], ["tide", "night"], ["quake", "night"], ["starfall", "night"], ["fireball", "day"], ["blink", "night"], ["mend", "night"]]
	for vx_run in vx_runs:
		var vx_id: String = vx_run[0]
		var vx_when: String = vx_run[1]
		# (each on fresh ground: the last one's crater would be in the way)
		var vx_st := _clear_stretch(vx_base + 150 * vx_ri, 80, 90, 6)
		vx_ri += 1
		var vx_col := vx_st.x + 10
		var vx_a: float = (float(vx_col) + 0.5) / float(Defs.NS) * TAU
		g.time = fposmod((vx_a + (PI if vx_when == "night" else 0.0) - g.spawn_angle + 1.1) / TAU * g.DAY_LEN, g.DAY_LEN)
		_go(_cell_pos(vx_col, g.builds.ground_row(vx_col) - 12))
		await _frames(20)
		g.vfx.clear()
		g.prof_reset()
		g.player.mana = g.player.max_mana
		g.player.cast_cd = 0
		if vx_id == "mend":
			g.player.hp = g.player.max_hp - 40.0
		var vx_tc := vx_col + (30 if vx_id == "blink" else 52)
		var vx_aim: Vector2 = _cell_pos(vx_tc, g.builds.ground_row(vx_tc) + (-10 if vx_id == "blink" else 1))
		var vx_i0: int = int(g.vfx.stats.get("impacts", 0)) + int(g.vfx.stats.get("blasts", 0))
		var vx_b0: int = int(g.vfx.stats.get("blinks", 0)) + int(g.vfx.stats.get("mends", 0))
		g._cast(g.player, vx_id, vx_aim)
		var vx_tag := vx_id + ("_day" if vx_when == "day" else "")
		var vx_hit_f := -1
		var vx_shot := false
		for vx_f in 150:
			await _frames(1)
			vx_peak = maxi(vx_peak, g.vfx.count())
			if vx_f == 4 and vx_id != "blink" and vx_id != "mend":
				g.get_viewport().get_texture().get_image().save_png(vx_dir.path_join("vfx_%s_fly.png" % vx_tag))
			var vx_landed: bool = int(g.vfx.stats.get("impacts", 0)) + int(g.vfx.stats.get("blasts", 0)) > vx_i0 or int(g.vfx.stats.get("blinks", 0)) + int(g.vfx.stats.get("mends", 0)) > vx_b0
			if vx_landed and vx_hit_f < 0:
				vx_hit_f = vx_f
			if vx_hit_f >= 0 and vx_f == vx_hit_f + (3 if vx_id == "spark" or vx_id == "blink" else 6):
				g.get_viewport().get_texture().get_image().save_png(vx_dir.path_join("vfx_%s_hit.png" % vx_tag))
				vx_shot = true
			if vx_shot and vx_f > vx_hit_f + 20:
				break
		for vx_k in g.prof:
			if vx_k == "spell effects":
				vx_cost = maxf(vx_cost, float(g.prof[vx_k][3]))
		vx_txt.append("%s%s %s" % [vx_id, " (day)" if vx_when == "day" else "", ("landed at frame %d" % vx_hit_f) if vx_hit_f >= 0 else "NEVER LANDED"])
		if vx_hit_f < 0:
			vx_bad.append(vx_id)
	# and they die away
	await _frames(400)
	var vx_left: int = g.vfx.count()
	g.time = vx_time0
	_go(vx_from)
	await _frames(20)
	g.test_god = vx_god0
	g.spawn_timer = 600
	g.player.hp = g.player.max_hp
	_ok("spell effects: every spell casts, flies and lands with its own look, then fades away, cheaply", vx_bad.is_empty() and vx_peak > 100 and vx_left < 40 and vx_cost < 4000.0,
		"%s; at most %d particles at once, %d left 7 s after; the effects' worst frame %.2f ms (pictures: saves/shots/vfx_*.png)" % [", ".join(vx_txt), vx_peak, vx_left, vx_cost / 1000.0])

func _test_town_days(t: Dictionary, mid: int) -> void:
	var tw = g.towns
	var mid_p: Vector2 = _cell_pos(mid, g.builds.ground_row(mid) - 14)
	var res := []
	for v in tw.folk:
		if not v.keeper and int(v.town["seed"]) == int(t["seed"]):
			res.append(v)
	# the schedule itself
	var sched_ok := true
	var sched_bad := ""
	for v1 in res:
		if v1.house.is_empty() or tw.want_place(v1, 23.5) != v1.house or tw.want_place(v1, 3.0) != v1.house:
			sched_ok = false
			sched_bad = "%s isn't home at night" % v1.name
		var noon: Dictionary = tw.want_place(v1, 12.0)
		if not noon.is_empty() and noon != v1.job:
			sched_ok = false
			sched_bad = "%s is somewhere odd at noon" % v1.name
	# a chest stood in front of someone's bed: they sleep on the floor, not over it
	var tc_v = null
	for v8 in res:
		if not v8.bed.is_empty():
			tc_v = v8
			break
	var tc_chest = null
	if tc_v != null:
		var b8: Dictionary = tc_v.bed
		tc_chest = g.new_chest()
		tc_chest.pos = tw._at(float(int(b8["c"])) + float(int(b8["w"])) * 0.5, float(int(b8["row"]) - 4), 0.0)
		g.chests.append(tc_chest)
	# night: everyone in reach of the simulation walks home and goes in
	_go(mid_p)
	g.time = tw.time_for_hour(mid_p, 22.6)
	await _frames(2)
	var watch := res
	var at_dusk := []
	for v2 in res:
		at_dusk.append("%s %s%s" % [v2.name, "in" if not v2.inside.is_empty() else "out", "" if g.in_grid(v2.pos, 14.0) else " (far)"])
	var home := 0
	var slept := 0
	var lying := 0
	var in_bed := 0
	var waited := 0
	for k in 40:
		await _frames(30)
		waited += 30
		home = 0
		slept = 0
		lying = 0
		in_bed = 0
		for v3 in watch:
			if v3.inside == v3.house:
				home += 1
			if v3.asleep:
				slept += 1
			if v3.lying:
				lying += 1
				if not v3.bedroll:
					in_bed += 1
		if home == watch.size() and lying == watch.size():
			break
	var with_bed := watch.filter(func(wb): return not wb.bed.is_empty()).size()
	# no two asleep in one spot, none lying over a chest
	var piled := 0
	var over_chest := 0
	for va in watch:
		if not va.lying:
			continue
		if tw._chest_near(va.pos, 10.0):
			over_chest += 1
		for vb in watch:
			if vb != va and vb.lying and vb.inside == va.inside and absf(vb.pos.length() - va.pos.length()) < 10.0 and absf(tw._dc(float(tw._col(va.pos)), vb.pos)) < 10.0:
				piled += 1
	var tc_ok: bool = tc_v == null or (tc_v.lying and tc_v.bedroll)
	if tc_chest != null:
		g.chests.erase(tc_chest)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("town_night.png"))
	# (they walk there: "stuck", stepping in after pushing on a wall for 90 ticks, is the exception)
	var night_ok: bool = not watch.is_empty() and home == watch.size() and slept > 0 and int(tw.stats.get("stuck", 0)) * 2 <= int(tw.stats.get("went_in", 0)) \
		and lying == watch.size() and (with_bed == 0 or in_bed > 0) and piled == 0 and over_chest == 0 and tc_ok
	var late := []
	for v6 in watch:
		if v6.inside != v6.house:
			late.append("%s (%s, fade %d, blocked %d, %.0f cells from home)" % [v6.name, "in grid" if g.in_grid(v6.pos, 12.0) else "far",
				v6.fade, v6.block_t, absf(tw._dc(float(int(v6.house["x0"]) + int(v6.house["w"]) / 2), v6.pos))])
	# morning: out into the street again
	g.time = tw.time_for_hour(mid_p, 8.2)
	var out := 0
	var want_out := 0
	for k2 in 24:
		await _frames(30)
		out = 0
		want_out = 0
		for v4 in watch:
			if tw.want_place(v4, tw.hour_at(v4.pos)).is_empty():
				want_out += 1
				if v4.inside.is_empty():
					out += 1
		if want_out > 0 and out == want_out:
			break
	var morn_ok: bool = want_out > 0 and out == want_out
	# two put in the very same spot step apart
	var ap_a = null
	var ap_b = null
	for v9 in watch:
		if not v9.lying and v9.fade == 0 and tw.want_place(v9, 8.2).is_empty():
			if ap_a == null:
				ap_a = v9
			elif ap_b == null:
				ap_b = v9
	var apart := -1.0
	var ap_stacked := 0
	if ap_a != null and ap_b != null:
		# (both out in the street, on the very same spot by the middle of the village, beside you)
		var ap_at: Vector2 = tw._street_at(float(mid) + 20.0)
		_go(tw._street_at(float(mid)))
		ap_a.inside = {}
		ap_b.inside = {}
		ap_a.vx = 0.0
		ap_b.vx = 0.0
		ap_a.pos = ap_at
		ap_b.pos = ap_at
		ap_a.idle_t = 400
		ap_b.idle_t = 400
		await _frames(90)
		apart = absf(tw._dc(float(tw._col(ap_a.pos)), ap_b.pos))
		# then for four seconds: how long are they both standing still in one spot? (passing is fine)
		for k3 in 240:
			await _frames(1)
			if absf(ap_a.vx) < 0.05 and absf(ap_b.vx) < 0.05 and absf(ap_a.pos.length() - ap_b.pos.length()) < 10.0 \
					and absf(tw._dc(float(tw._col(ap_a.pos)), ap_b.pos)) < 5.0:
				ap_stacked += 1
	var apart_ok: bool = ap_a == null or ap_b == null or (apart >= 6.0 and ap_stacked < 20)
	morn_ok = morn_ok and apart_ok
	late.append("two put on one spot were %.0f cells apart 1.5 s later, then stood in one spot %d frames of 240" % [apart, ap_stacked])
	for v7 in watch:
		if tw.want_place(v7, tw.hour_at(v7.pos)).is_empty() and not v7.inside.is_empty():
			late.append("%s still in at %.1f h (%s, fade %d, talk %d)" % [v7.name, tw.hour_at(v7.pos), "in grid" if g.in_grid(v7.pos, 12.0) else "far", v7.fade, v7.talk_t])
	_ok("living towns: folk keep the hours (home asleep at night, out in the morning)", sched_ok and night_ok and morn_ok,
		"schedule %s%s; at dusk %s; at night %d of %d went home within %.1f s (%d asleep, %d lying down, %d of them in their beds; %d have beds; %d in one spot, %d over a chest; with a chest before %s's bed: %s); in the morning %d of the %d who'd be out came out; %s%s" % [
		sched_ok, "" if sched_ok else " (" + sched_bad + ")", ", ".join(at_dusk), home, watch.size(), waited / 60.0, slept, lying, in_bed, with_bed, piled / 2, over_chest, tc_v.name if tc_v != null else "nobody", ("on the floor" if tc_v.bedroll else "in it") if tc_v != null else "-",
		out, want_out, JSON.stringify(tw.stats), "" if late.is_empty() else "; " + ", ".join(late)])
	g.time = tw.time_for_hour(mid_p, 12.0)

## a villager's requests: each kind taken, done and rewarded (a hunt counted by a real kill)
func _test_requests(t: Dictionary) -> void:
	var tw = g.towns
	var rq0: Array = (g.planet_state.get("requests", []) as Array).duplicate(true)
	var rn0: Dictionary = (g.planet_state.get("req_n", {}) as Dictionary).duplicate(true)
	var fk0: Dictionary = (g.planet_state.get("folk_known", {}) as Dictionary).duplicate(true)
	var tr0: Dictionary = (g.planet_state.get("town_rep", {}) as Dictionary).duplicate(true)
	var c0: int = int(g.items.get("coins", 0))
	var pot0: int = int(g.items.get("potion", 0))
	g.planet_state["requests"] = []
	var asker = null
	for v in tw.folk:
		if v.asker and int(v.town["seed"]) == int(t["seed"]):
			asker = v
	var lines := []
	var ok := asker != null
	if asker != null:
		asker.asleep = false
		asker.fade = 0
		asker.offer = {}
		var mark0: String = tw.mark_of(asker)
		# fetch: offered, taken, then handed in once you've the goods
		var rf: Dictionary = tw.make_request(asker, "fetch")
		var mat := int(rf["mat"])
		var inv0: int = g.player.inv[mat]
		g.player.inv[mat] = 0                    # (earlier checks may have left some in the satchel)
		asker.offer = rf
		tw.take(asker)
		var mark1: String = tw.mark_of(asker)
		g.player.inv[mat] = int(rf["n"]) + 3
		var mark2: String = tw.mark_of(asker)
		var cf: int = int(g.items.get("coins", 0))
		tw._request_talk(asker)
		var fetch_ok: bool = mark0 == "offer" and mark1 == "wait" and mark2 == "ready" and tw.requests().is_empty() and g.player.inv[mat] == 3 \
			and int(g.items["coins"]) == cf + int(rf["reward"])
		g.player.inv[mat] = inv0
		lines.append("fetch %s (marks %s/%s/%s): %s" % [tw.short(rf), mark0, mark1, mark2, fetch_ok])
		ok = ok and fetch_ok
		# whoever asks next in the village (the asker moves on)
		var nxt = null
		for v2 in tw.folk:
			if v2.asker and int(v2.town["seed"]) == int(t["seed"]):
				nxt = v2
		ok = ok and nxt != null
		if nxt != null:
			nxt.fade = 0
			nxt.asleep = false
			# hunt: a creature of the village's biome, killed for real
			var rh: Dictionary = tw.make_request(nxt, "hunt")
			if String(rh["kind"]) == "hunt":
				nxt.offer = rh
				tw.take(nxt)
				var hunt_rq: Dictionary = tw.requests()[0]
				var kills := 0
				for kk in int(rh["n"]):
					var e = g.spawn_enemy(String(rh["foe"]), g.player.pos + g.player.pos.normalized() * 30.0)
					if e != null:
						g._kill_enemy(e)
						g.enemies.erase(e)
						kills += 1
				var ch: int = int(g.items.get("coins", 0))
				var ready: bool = tw.mark_of(nxt) == "ready"
				tw._request_talk(nxt)
				var hunt_ok: bool = kills == int(rh["n"]) and int(hunt_rq["got"]) == int(rh["n"]) and ready and tw.requests().is_empty() and int(g.items["coins"]) == ch + int(rh["reward"])
				lines.append("hunt %s: %s" % [tw.short(hunt_rq), hunt_ok])
				ok = ok and hunt_ok
			else:
				lines.append("(no creatures in %s to hunt)" % t.get("biome", "?"))
			# deliver: a letter to a keeper in another village
			var rd: Dictionary = tw.make_request(nxt, "deliver")
			if String(rd["kind"]) == "deliver":
				nxt.offer = rd
				tw.take(nxt)
				var dest := {}
				for t2 in g.builds.towns:
					if int(t2["seed"]) == int(rd["to"]):
						dest = t2
				var kp = g.new_villager()
				kp.keeper = true
				kp.role = String(rd["to_role"])
				kp.town = dest
				kp.name = "Test"
				var wrong = g.new_villager()
				wrong.keeper = true
				wrong.role = "inn" if kp.role != "inn" else "smithy"
				wrong.town = dest
				var cd: int = int(g.items.get("coins", 0))
				var not_wrong: bool = not tw._deliver_to(wrong)
				var given: bool = tw._deliver_to(kp)
				var del_ok: bool = not_wrong and given and tw.requests().is_empty() and int(g.items["coins"]) == cd + int(rd["reward"])
				lines.append("deliver %s: %s" % [tw.short(rd), del_ok])
				ok = ok and del_ok
			else:
				lines.append("(no other village to send a letter to)")
		# no more than MAX_REQUESTS at once
		for k in Defs.MAX_REQUESTS:
			tw.requests().append({"kind": "fetch", "from": -1 - k, "mat": Defs.WOOD, "n": 1, "who": "x", "town_name": "x", "town": 0, "reward": 0})
		var cur = null
		for v5 in tw.folk:
			if v5.asker and int(v5.town["seed"]) == int(t["seed"]):
				cur = v5
		var full_ok: bool = cur != null and tw.mark_of(cur) == "" and not tw._request_talk(cur)
		lines.append("full hands (%d at once): %s" % [Defs.MAX_REQUESTS, full_ok])
		ok = ok and full_ok
	# remembered: the one helped greets you as a friend, the village's shops give a better price
	if asker != null:
		var fr_line: String = tw._hello(asker, RandomNumberGenerator.new(), 12.0)
		var fr_keep = null
		for kv in tw.folk:
			if kv.keeper and int(kv.town["seed"]) == int(t["seed"]):
				fr_keep = kv
		var cheaper: bool = fr_keep != null and tw.price_of(fr_keep, {"price": 100}) < 100
		var friend_ok: bool = int(tw.memory(asker).get("helped", 0)) > 0 and fr_line.find("I'm") < 0 and cheaper
		lines.append("remembered: \"%s\", a keeper's 100 coins now %d: %s" % [fr_line, tw.price_of(fr_keep, {"price": 100}) if fr_keep != null else -1, friend_ok])
		ok = ok and friend_ok
	g.planet_state["requests"] = rq0
	g.planet_state["req_n"] = rn0
	g.planet_state["folk_known"] = fk0
	g.planet_state["town_rep"] = tr0
	for f in tw.folk:
		if int(f.town["seed"]) == int(t["seed"]) and not f.keeper:
			f.asker = f.idx == tw.asker_index(f.town)
	g.items["coins"] = c0
	g.items["potion"] = pot0
	_ok("living towns: villagers' requests (bring, hunt, deliver) are taken, done and paid", ok, ("no asker in %s" % t["name"]) if asker == null else "; ".join(lines))

## each kind of planet's shops: the ward its danger needs, its fare, an imported ore, a better price for its own
func _test_kind_trade() -> void:
	var tw = g.towns
	var bad := []
	var seen := 0
	for kind in Defs.PLANET_ORDER:
		for role in Defs.SHOPS:
			var sd: Dictionary = tw.shop_def_for(role, kind, 4242)
			var base: int = (Defs.SHOPS[role]["sell"] as Array).size()
			var extra: Array = (Defs.KIND_TRADE.get(kind, {}) as Dictionary).get(role, [])
			var want: int = base + extra.size() + (1 if role == "smithy" and Defs.KIND_ORES.has(kind) else 0)
			if (sd["sell"] as Array).size() != want:
				bad.append("%s %s sells %d, not %d" % [kind, role, (sd["sell"] as Array).size(), want])
			if (Defs.SHOPS[role]["sell"] as Array).size() != base:
				bad.append("SHOPS changed")
			for it in sd["sell"]:
				seen += 1
				if it.has("item") and Defs.RECIPES.filter(func(r): return r["id"] == it["item"]).is_empty():
					bad.append("%s: no such item %s" % [kind, it["item"]])
				if it.has("spell") and not Defs.SPELLS.has(it["spell"]):
					bad.append("%s: no such spell %s" % [kind, it["spell"]])
				if it.has("give"):
					for m in it["give"]:
						if int(m) >= Defs.NM:
							bad.append("%s: no such material %d" % [kind, int(m)])
			if role == "smithy" and Defs.KIND_ORES.has(kind):
				var own := int(Defs.KIND_ORES[kind]["mat"])
				var imp: Dictionary = (sd["sell"] as Array).back()
				if (imp["give"] as Dictionary).has(own) or int(sd["own_ore"][0]) != own or int(sd["own_ore"][2]) <= int(Defs.SHOPS["smithy"]["ores"][1]):
					bad.append("%s smithy: import or own ore wrong" % kind)
		# a world with a danger sells the ward for it
		for hz in Defs.HAZARDS:
			if float((Defs.CLIMATES.get(kind, {}) as Dictionary).get(hz, 0.0)) > 0.0:
				var ward := String(Defs.HAZARDS[hz]["ward"])
				var sold := false
				for role2 in Defs.SHOPS:
					for it2 in tw.shop_def_for(role2, kind, 1)["sell"]:
						if String(it2.get("item", "")) == ward:
							sold = true
				if not sold:
					bad.append("%s doesn't sell the %s" % [kind, ward])
	# a bought ward is yours (and shows as yours)
	var had: bool = g.items.has("sunveil")
	tw.grant({"item": "sunveil"})
	var got: bool = tw.owned({"item": "sunveil"})
	if not had:
		g.items.erase("sunveil")
	if not got:
		bad.append("a bought Sun Veil isn't yours")
	_ok("living towns: each kind of planet's shops sell its own wares", bad.is_empty(), ("%d things for sale across %d kinds, all real" % [seen, Defs.PLANET_ORDER.size()]) if bad.is_empty() else "; ".join(bad))

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

## is surface column c within a lair (its arena, gate and backdrop, with a margin)?
func _near_lair(c: int) -> bool:
	for l in g.builds.lair_list:
		var lp: Vector2 = l["pos"]
		var lc := int(fposmod(atan2(lp.y, lp.x), TAU) / TAU * Defs.NS)
		var d := posmod(c - lc, Defs.NS)
		if mini(d, Defs.NS - d) < 420:
			return true
	return false

func _go(p: Vector2) -> void:
	# (a check that left you dead would leave every check after it running on the death screen: say so
	# in the log, and carry on alive)
	if g.state == "dead" or g.player.dead:
		print("[test] you were dead (health %.0f) on the way to the next check: carrying on alive" % g.hp)
		g.ui.hide_death()
		g.player.dead = false
		g.player.hp = g.player.max_hp
		g.state = "play"
	g.player.pos = p
	g.player.vx = 0.0
	g.player.vy = 0.0
	g.cam_c = p
	g.player.grid_g = p
	g.player.grid_a = atan2(p.y, p.x)

## a clear stretch (as `_clear_stretch`) whose ground is soft right through its top cells (dirt, sand,
## snow...: ecology.gd `soft`), so a burrower can live under it; the nearest found, else any clear one
func _soft_stretch(from: int, w: int, h: int, level := 3) -> Vector2i:
	# (hilly ground may have no stretch that level: then a little rougher, rather than wherever it fell)
	for lv in [level, level * 2, level * 3]:
		var at0 := from
		for k0 in 14:
			var st0 := _clear_stretch(at0, w, h, lv, 0, true)
			if not _cs_found:
				break
			if _soft_at(st0, w):
				return st0
			at0 = st0.x + w + 60
	var at := from
	for k in 14:
		var st := _clear_stretch(at, w, h, level)
		var soft_ok := true
		for c in [st.x + 4, st.x + w / 4, st.x + w / 2, st.x + 3 * w / 4, st.x + w - 4]:
			var gr: int = g.builds.ground_row(c)
			var rr: Dictionary = g.gpu.read_rect(c, gr, 1, 10)
			for v in rr["fg"]:
				if not Ecology.soft(int(v) & 255):
					soft_ok = false
					break
			if not soft_ok:
				break
		if soft_ok:
			return st
		at = st.x + w + 60
	return _clear_stretch(from, w, h, level)

## counts inside a structure's box: solid built blocks, loose (unsupported) blocks, treasure
## background plant cells (leaves, wood, cactus, coal from charred trees, snow on pines) in a
## 120-column window from 100 rows above the ground at the middle down to 10 below
func _plants(raw: PackedByteArray, toff: int, c0: int, gr: int) -> int:
	var N: int = Defs.NS
	var n := 0
	for j in range(maxi(0, gr - 112), gr + 10):
		for i in 120:
			var bm := raw.decode_u32(toff + Defs.raw_idx(j, posmod(c0 + i, N)) * 4) & 255
			if bm == Defs.LEAF or bm == Defs.WOOD or bm == Defs.CACTUS or bm == Defs.COAL or bm == Defs.SNOW \
					or bm == Defs.CAP or bm == Defs.STALK or bm == Defs.DRYGRASS:
				n += 1
	return n

## positions of powder cells (sand, gravel, snow, ash) in a 150-column window around the ground
func _powders(raw: PackedByteArray, c0: int, gr: int) -> Dictionary:
	var N: int = Defs.NS
	var out := {}
	for j in range(maxi(0, gr - 40), gr + 40):
		for i in 150:
			var col := posmod(c0 + i, N)
			var t := raw.decode_u32(Defs.raw_idx(j, col) * 4) & 255
			if Defs.KIND[t] == Defs.K_POWDER:
				out[j * N + col] = true
	return out

## the chest object standing at a planned chest spot (left column, floor row), or null
## a column near `from` (looking outward from it) where the ground is level across `w` columns (within
## `level` rows), outside any named structure, with nothing standing in the `h` rows over it (no log, wall,
## sand or water; trees are background and don't count) and, given `below`, solid ground that many rows
## under it: (first column, the highest ground row there)
var _cs_found := false            # (whether the last `_clear_stretch` found one)

## is the ground soft through its top cells at five points along a stretch?
func _soft_at(st: Vector2i, w: int) -> bool:
	for c in [st.x + 4, st.x + w / 4, st.x + w / 2, st.x + 3 * w / 4, st.x + w - 4]:
		var gr: int = g.builds.ground_row(c)
		var rr: Dictionary = g.gpu.read_rect(c, gr, 1, 10)
		for v in rr["fg"]:
			if not Ecology.soft(int(v) & 255):
				return false
	return true

func _clear_stretch(from: int, w: int, h: int, level := 3, below := 0, quiet := false) -> Vector2i:
	_cs_found = true
	var b = g.builds
	var why := {"level": 0, "label": 0, "wet": 0, "standing": 0, "hollow": 0}
	for cs_d in range(0, 2400, 12):
		for cs_s in [1, -1]:
			var c0: int = from + cs_d * cs_s
			var gmin := 1 << 30
			var gmax := -(1 << 30)
			for c in range(c0, c0 + w):
				var gr: int = b.ground_row(c)
				gmin = mini(gmin, gr)
				gmax = maxi(gmax, gr)
			if gmax - gmin > level:
				why["level"] += 1
				continue
			if b.label_at(_cell_pos(c0 + w / 2, gmin - 5)) != "":
				why["label"] += 1
				continue
			if b.wet(c0 + w / 2):
				why["wet"] += 1
				continue
			var rr: Dictionary = g.gpu.read_rect(c0, gmin - h, w, h - 1)
			var clear := true
			for v in rr["fg"]:
				var kd: int = Defs.KIND[v & 255]
				if kd == Defs.K_SOLID or kd == Defs.K_POWDER or kd == Defs.K_LIQUID:
					clear = false
					break
			if not clear:
				why["standing"] += 1
				continue
			if below > 0:
				# (and solid ground under it, `below` rows down from its lowest point: no cave to break into)
				var rb: Dictionary = g.gpu.read_rect(c0, gmax + 1, w, below)
				for v2 in rb["fg"]:
					var kd2: int = Defs.KIND[v2 & 255]
					if kd2 != Defs.K_SOLID and kd2 != Defs.K_POWDER:
						clear = false
						break
				if not clear:
					why["hollow"] += 1
					continue
			return Vector2i(c0, gmin)
	_cs_found = false
	if not quiet:
		print("[clear] no clear stretch %d x %d (level %d) near column %d: %s" % [w, h, level, from, str(why)])
	return Vector2i(from, b.ground_row(from))

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
	var N: int = Defs.NS
	var boff: int = Defs.total_cells() * 4      # the background layer follows the cells
	var w: int = int(info["w"])
	for k in info.get("cells", PackedInt32Array()):
		var j: int = k / w
		var i: int = k % w
		var row: int = int(info["y0"]) + j
		if row < 0 or row >= Defs.ROWS:
			continue
		var col := posmod(int(info["x0"]) + i, N)
		var c := raw.decode_u32(Defs.raw_idx(row, col, int(info["ax"]), int(info["aw"])) * 4)
		var t := c & 255
		if Defs.KIND[t] != Defs.K_SOLID:
			continue
		solid += 1
		allm[Defs.NAMES[t]] = int(allm.get(Defs.NAMES[t], 0)) + 1
		# unsupported AND over open space (so it should have fallen); anchored cells are part
		# of the planet until you dig nearby
		var lf := (c >> 16) & 255
		if (c & 0x40000000) == 0 and ((c >> 24) & 63) > Defs.SPAN[t] and row + 1 < Defs.ROWS and not (lf > 0 and lf < 128):
			var cb := raw.decode_u32(Defs.raw_idx(row + 1, col, int(info["ax"]), int(info["aw"])) * 4)
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
		if row2 < 0 or row2 >= Defs.ROWS:
			continue
		for i in w:
			var col2 := posmod(int(info["x0"]) + i, N)
			var t2 := raw.decode_u32(Defs.raw_idx(row2, col2, int(info["ax"]), int(info["aw"])) * 4) & 255
			var bgm := raw.decode_u32(boff + Defs.raw_idx(row2, col2, int(info["ax"]), int(info["aw"])) * 4) & 255
			if bgm != 0:
				bgn += 1
				var bk := "bg " + Defs.NAMES[bgm]
				allm[bk] = int(allm.get(bk, 0)) + 1
			if t2 == Defs.TREASURE or bgm == Defs.TREASURE:
				tre += 1
	return {"solid": solid, "loose": loose, "treasure": tre, "mats": mats, "below": below, "at": at, "all": allm, "bg": bgn}

## a picture of a blueprint as generated: built blocks in their colour, back walls darker, props in
## their palette colour, untouched cells grey, air sky blue (3 pixels per cell)
func _bp_image(info: Dictionary) -> Image:
	var w: int = info["w"]
	var h: int = info["h"]
	var dat: PackedInt32Array = info["data"]
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for j in h:
		for i in w:
			var v: int = dat[j * w + i]
			var f: int = v & 255
			var gb: int = (v >> 8) & 255
			var col := Color(0.55, 0.55, 0.55)
			if f != 255 and f != 0:
				col = Defs.COLOR[f]
			elif gb == Defs.DECOR:
				col = Color.html(Props.PALETTE[((v >> 19) & 255) % Props.PALETTE.size()])
			elif gb != 255 and gb != 0:
				col = Defs.COLOR[gb].darkened(0.45)
			elif f == 0 or gb == 0:
				col = Color(0.45, 0.65, 0.95)
			img.set_pixel(i, j, col)
	img.resize(w * 3, h * 3, Image.INTERPOLATE_NEAREST)
	return img

## a cell's colour for the diagnostic pictures: the front material, else the back one darker, else
## air (sky blue) or untouched (grey); src tints by which blueprint wrote it
func _cell_col(f: int, gb: int, src: int) -> Color:
	var col := Color(0.55, 0.55, 0.55)
	if f != 255 and f != 0:
		col = Defs.COLOR[f]
	elif gb == Defs.DECOR:
		col = Color(0.9, 0.3, 0.9)
	elif gb != 255 and gb != 0:
		col = Defs.COLOR[gb].darkened(0.45)
	elif f == 0 or gb == 0:
		col = Color(0.45, 0.65, 0.95)
	if src >= 0:
		col = col.lerp(Color.from_hsv(fmod(float(src) * 0.37, 1.0), 0.9, 0.9), 0.25)
	return col

func run() -> void:
	var t_all := Time.get_ticks_msec()
	g.test_calm = true          # (the guardians sleep through the checks that aren't about them)
	g.test_no_wild = true       # (and no wild creature wanders into checks that aren't about them)
	lines.append("Wisp Forge test report  %s" % Time.get_datetime_string_from_system())
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("")
	g.test_god = true
	g.free_magic = true         # (digging and building cost no mana, but in the check about it)

	# ---- a picture of the animated title screen (saves/shots/title.png) ----
	var tdir: String = g._real_save_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(tdir)
	g.ui.show_title(true)
	await _frames(150)
	g.get_viewport().get_texture().get_image().save_png(tdir.path_join("title.png"))
	_ok("title screen draws, with a button per save slot", g.ui.title.visible and g.ui.title.slot_btns.size() == g.SLOTS, "%d slot buttons" % g.ui.title.slot_btns.size())

	# ---- a fresh planet ----
	g._delete_worlds()
	g.player.inv.fill(0)
	g.known = ["spark", "conjure"]
	g.items["levitate"] = true        # (forged in a real game: the checks fly as they always have)
	g.learn_all()                     # (every recipe known: learning them is _test_recipes's)
	var t0 := Time.get_ticks_msec()
	g._enter_planet(0)
	var gen_ms := Time.get_ticks_msec() - t0
	g.ui.show_hud()
	g.state = "play"
	var b = g.builds
	start_pos = g.player.pos
	await _trace_frames("startup", 300)
	# (saves/test_only.txt naming a section runs just that one, to try a change quickly)
	# (an empty file runs everything)
	var only_f: String = g._real_save_dir().path_join("test_only.txt")
	var only := FileAccess.get_file_as_string(only_f).strip_edges() if FileAccess.file_exists(only_f) else ""
	if only != "":
		only_now = only
		g.ui.title.visible = false      # (the full run puts the title away in its early checks)
		if only == "climb":
			_go(g.player.pos)
			await _frames(60)
			await _test_climb()
		elif only == "nav":
			_go(g.player.pos)
			await _frames(60)
			await _test_nav()
		elif only == "guardians":
			_go(g.player.pos)
			await _frames(60)
			await _test_guardians()
		elif only == "stairs":
			_go(g.player.pos)
			await _frames(60)
			await _test_stairs()
		elif only == "workshops":
			_go(g.player.pos)
			await _frames(60)
			await _test_workshops()
		elif only == "remove":
			_go(g.player.pos)
			await _frames(60)
			await _test_remove()
		elif only == "galaxy":
			_go(g.player.pos)
			await _frames(60)
			await _test_galaxy()
		elif only == "lairs":
			_go(g.player.pos)
			await _frames(60)
			await _test_lairs()
		elif only == "wardens":
			_go(g.player.pos)
			await _frames(60)
			await _test_wardens()
		elif only == "biomes":
			await _test_far_biomes()
		elif only == "worlds":
			await _test_worlds()
		elif only == "stampdiag":
			await _test_stampdiag()
		elif only == "creatures":
			_go(g.player.pos)
			await _frames(60)
			await _test_creatures()
		elif only == "ecology":
			_go(g.player.pos)
			await _frames(60)
			await _test_ecology()
		elif only == "fog":
			_go(g.player.pos)
			await _frames(60)
			await _test_fog()
		elif only == "sky":
			_go(g.player.pos)
			await _frames(60)
			await _test_sky()
		elif only == "gear":
			_go(g.player.pos)
			await _frames(60)
			await _test_gear()
		elif only == "towns":
			_go(g.player.pos)
			await _frames(60)
			await _test_towns()
		elif only == "vfx":
			_go(g.player.pos)
			await _frames(60)
			await _test_vfx()
		elif only == "start":
			_go(g.player.pos)
			await _frames(60)
			await _test_start()
		elif only == "bench":
			_go(g.player.pos)
			await _frames(60)
			await _test_bench()
		elif only == "recipes":
			_go(g.player.pos)
			await _frames(60)
			await _test_recipes()
		elif only == "hazards":
			# (where the full run tries it: the open ground beside the frozen basin)
			var hzo_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 160, 80, 60, 4, 30)
			var hzo_a: float = (float(hzo_st.x) + 66.5) / float(Defs.NS) * TAU
			_go(Vector2(cos(hzo_a), sin(hzo_a)) * (g.gpu.surf_at(hzo_a).x + 12.0))
			await _frames(60)
			await _test_hazards()
		elif only == "ui":
			_go(g.player.pos)
			await _frames(60)
			await _test_ui()
		elif only == "mines":
			for mi_info in g.builds.infos:
				if mi_info["meta"].has("mine") and int(mi_info.get("unsound", 0)) > 0:
					print("[mines] %s unsound %d cuts %s at %s" % [str(mi_info["meta"]["mine"]), mi_info["unsound"], str(mi_info["meta"].get("cuts", {})), str(mi_info["meta"].get("cut_at", []))])
		lines.append("")
		lines.append("%d passed, %d failed, %.1f s (only %s)" % [passed, failed, (Time.get_ticks_msec() - t_all) / 1000.0, only])
		var only_txt := "\n".join(lines)
		print(only_txt)
		var only_rf := FileAccess.open(g._real_save_dir().path_join("test_report.txt"), FileAccess.WRITE)
		if only_rf:
			only_rf.store_string(only_txt + "\n")
			only_rf.close()
		g._delete_worlds()
		g.get_tree().quit(0 if failed == 0 else 1)
		return
	_ok("planet generates", g.planet.size() > 0, "%d ms including structures and settling" % gen_ms)
	_ok("structures are placed", b.infos.size() >= 15, "%d structures, %d labels" % [b.infos.size(), b.labels.size()])
	# ---- a building is the same at any depth: it goes in cell for cell in every shell, centred on
	# its anchor, so its width never changes and its sides stay straight across a seam ----
	var an_rng := RandomNumberGenerator.new()
	an_rng.seed = 77
	var an_jog := {24: 0.0, 48: 0.0, 96: 0.0}       # the biggest step of a side at a seam, in cells
	var an_where := ""
	for an_s in Defs.NSH - 1:
		var an_rs: float = Defs.R_TOP - float(Defs.SH_Y1[an_s])     # the seam's radius
		if an_rs < 320.0:
			break
		var an_no: int = Defs.SH_N[an_s]
		var an_ni: int = Defs.SH_N[an_s + 1]
		for an_t in 6:
			var an_ax := an_rng.randi_range(0, Defs.NS - 1)
			for an_w in an_jog.keys():
				var an_lo: int = Defs.stamp_left(an_no, an_ax, an_w)
				var an_li: int = Defs.stamp_left(an_ni, an_ax, an_w)
				var an_cell := TAU * an_rs / float(an_ni)
				# the left and right sides' places along the seam, above it and below it
				var an_dl := wrapf(float(an_lo) / an_no - float(an_li) / an_ni, -0.5, 0.5) * TAU * an_rs / an_cell
				var an_dr := wrapf(float(an_lo + an_w) / an_no - float(an_li + an_w) / an_ni, -0.5, 0.5) * TAU * an_rs / an_cell
				var an_m := maxf(absf(an_dl), absf(an_dr))
				if an_m > float(an_jog[an_w]):
					an_jog[an_w] = an_m
					if an_w == 48:
						an_where = "seam at row %d (%d / %d columns)" % [Defs.SH_Y1[an_s], an_no, an_ni]
	# (the cells either side of a seam never line up, so a side can step up to a cell, plus how much
	# narrower half the building's cells are below it: a ~2% seam)
	_ok("a building's sides stay straight across every seam (within about a cell)", float(an_jog[24]) <= 1.35 and float(an_jog[48]) <= 1.75,
		"a side steps at most %.2f cells for a building 24 wide, %.2f for 48 (%s), %.2f for 96" % [an_jog[24], an_jog[48], an_where, an_jog[96]])
	# stamped deep, through several seams, it reads back exactly as it was written, cell for cell
	var an_c := int(fposmod(g.spawn_angle + 1.3, TAU) / TAU * Defs.NS)
	var an_y0: int = int(Defs.SH_Y1[Defs.SURF]) + 60
	var an_w2 := 40
	var an_h2 := 140
	var an_bp := PackedInt32Array()
	for an_j in an_h2:
		for an_i in an_w2:
			var an_mt := 0
			if an_i < 3 or an_i >= an_w2 - 3 or an_j < 3 or an_j >= an_h2 - 3 or (an_i * 7 + an_j * 3) % 11 == 0:
				an_mt = Defs.BRICK
			an_bp.append(an_mt)
	g.gpu.stamp([{"x0": an_c, "y0": an_y0, "w": an_w2, "h": an_h2, "data": an_bp, "ax": an_c, "aw": an_w2}], 5)
	var an_rr: Dictionary = g.gpu.read_rect(an_c, an_y0, an_w2, an_h2, an_c, an_w2)
	var an_fg: PackedInt32Array = an_rr["fg"]
	var an_bad := 0
	for an_k in an_w2 * an_h2:
		if (an_fg[an_k] & 255) != an_bp[an_k]:
			an_bad += 1
	var an_seams := Defs.shell_of_row(an_y0 + an_h2 - 1) - Defs.shell_of_row(an_y0)
	# and build mode's cells near you (anchored on your column) map to a place and back, at any depth
	var an_keep: int = Defs.anchor_c
	Defs.anchor_c = an_c
	var an_rt := 0
	for an_q in 600:
		var an_col := an_c + an_rng.randi_range(-60, 60)
		var an_row := an_rng.randi_range(-Defs.ORBIT_ROWS + 2, Defs.ROWS - 40)
		var an_back: Vector2i = Build.cell_of(Build.cell_pos(an_col, an_row))
		if an_back != Vector2i(posmod(an_col, Defs.NS), an_row):
			an_rt += 1
	Defs.anchor_c = an_keep
	_ok("a building stamped deep is the same cell for cell (no column lost or doubled)", an_bad == 0 and an_seams >= 3 and an_rt == 0,
		"%d x %d from row %d, through %d seams (shells of %d to %d columns): %d cells differ; %d of 600 cells near you don't map back to themselves" % [an_w2, an_h2, an_y0, an_seams,
			Defs.SH_N[Defs.shell_of_row(an_y0)], Defs.SH_N[Defs.shell_of_row(an_y0 + an_h2 - 1)], an_bad, an_rt])
	_ok("guards are planned", b.guards.size() >= 5, "%d guards" % b.guards.size())
	var nchest := 0
	for info in b.infos:
		nchest += info["chests"].size()
	_ok("chests are placed", nchest >= 10, "%d chests" % nchest)
	await _frames(10)
	await _test_stampdiag()

	# ---- diagnostics: the blueprints of the most furnished buildings, and how they look straight
	# after generating (saves/shots/bp_N.png, early_N.png) ----
	var by_decor := []
	for info in b.infos:
		if not info["ruined"] and int(info.get("decor", 0)) > 0 and info.get("data", PackedInt32Array()).size() > 0:
			by_decor.append(info)
	by_decor.sort_custom(func(p, q): return int(p["decor"]) > int(q["decor"]))
	var sdir: String = g._real_save_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(sdir)
	for bn in mini(3, by_decor.size()):
		var bi: Dictionary = by_decor[bn]
		_bp_image(bi).save_png(sdir.path_join("bp_%d.png" % bn))
		var ecx := int(bi["x0"]) + int(bi["w"]) / 2
		var epos := _cell_pos(ecx, b.ground_row(ecx) - 30)
		_go(epos)
		g.ui.title.visible = false
		g.time = fposmod(atan2(epos.y, epos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(sdir.path_join("early_%d.png" % bn))

	# the first village: every blueprint over it combined in stamping order (vill_bp.png), and the
	# world's cells there right after generating (vill_world.png)
	for lab0 in b.labels:
		if "Village" in str(lab0["name"]):
			var vx0 := int(lab0["x0"])
			var vw := int(lab0["w"])
			var vg: int = b.ground_row(vx0 + vw / 2)
			var vy0: int = vg - 140
			var vh := 160
			var comp := PackedInt32Array()
			comp.resize(vw * vh)
			comp.fill(0xffff)
			var src := PackedInt32Array()
			src.resize(vw * vh)
			src.fill(-1)
			for si in b.infos.size():
				var inf: Dictionary = b.infos[si]
				var dat2: PackedInt32Array = inf.get("data", PackedInt32Array())
				if dat2.is_empty():
					continue
				var iw: int = inf["w"]
				for jj in int(inf["h"]):
					var yy: int = int(inf["y0"]) + jj - vy0
					if yy < 0 or yy >= vh:
						continue
					for ii in iw:
						var xx := posmod(int(inf["x0"]) + ii - vx0, Defs.NS)
						if xx >= vw:
							continue
						var v2: int = dat2[jj * iw + ii]
						var k3 := yy * vw + xx
						if (v2 & 255) != 255:
							comp[k3] = (comp[k3] & ~255) | (v2 & 255)
							src[k3] = si
						if ((v2 >> 8) & 255) != 255:
							comp[k3] = (comp[k3] & ~0xff00) | (v2 & 0xff00)
			var cimg := Image.create(vw, vh, false, Image.FORMAT_RGB8)
			var wimg := Image.create(vw, vh, false, Image.FORMAT_RGB8)
			var rawv: PackedByteArray = g.gpu.read_world()
			var boffv2: int = Defs.total_cells() * 4
			for yy2 in vh:
				for xx2 in vw:
					var cv: int = comp[yy2 * vw + xx2]
					cimg.set_pixel(xx2, yy2, _cell_col(cv & 255, (cv >> 8) & 255, src[yy2 * vw + xx2]))
					var row3: int = vy0 + yy2
					var col3 := posmod(vx0 + xx2, Defs.NS)
					if row3 < 0 or row3 >= Defs.ROWS:
						continue
					var kw: int = Defs.raw_idx(row3, col3) * 4
					wimg.set_pixel(xx2, yy2, _cell_col(rawv.decode_u32(kw) & 255, rawv.decode_u32(boffv2 + kw) & 255, -1))
			cimg.resize(vw * 2, vh * 2, Image.INTERPOLATE_NEAREST)
			wimg.resize(vw * 2, vh * 2, Image.INTERPOLATE_NEAREST)
			cimg.save_png(sdir.path_join("vill_bp.png"))
			wimg.save_png(sdir.path_join("vill_world.png"))
			break

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
			var nm: String = b.label_at(_cell_pos(int(info["x0"]) + a0.x, int(info["y0"]) + a0.y, int(info["ax"]), int(info["aw"])))
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
	# (where a frame's time goes, early on: a slow run still shows it)
	g.prof_reset()
	await _frames(90)
	print("[perf] early: ", g.prof_text(14, "; "))
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
		var raw_v0: PackedByteArray = g.gpu.read_world()
		var sc0 := _scan(raw_v0, info)
		_go(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) - 6))
		await _frames(200)
		var sc1 := _scan(g.gpu.read_world(), info)
		var n0 := int(sc0["solid"]) + int(sc0["bg"])
		var n1 := int(sc1["solid"]) + int(sc1["bg"])
		var ratio := float(n1) / float(n0) if n0 > 0 else 1.0
		if ratio < worst_v:
			worst_v = ratio
			var lost := []
			for k in sc0["all"]:
				var dn := int(sc0["all"][k]) - int(sc1["all"].get(k, 0))
				if dn > 3:
					lost.append("%s -%d" % [k, dn])
			# where the lost tree stood: its lowest wood cell that is gone now, and what was under it
			var raw_v1: PackedByteArray = g.gpu.read_world()
			var boffv: int = Defs.total_cells() * 4
			var Nv: int = Defs.NS
			var low := ""
			var lowrow := -1
			for jj in int(info["h"]):
				var rowv: int = int(info["y0"]) + jj
				if rowv < 0 or rowv >= Defs.ROWS:
					continue
				for ii in int(info["w"]):
					var colv := posmod(int(info["x0"]) + ii, Nv)
					var kv := Defs.raw_idx(rowv, colv, int(info["ax"]), int(info["aw"])) * 4
					var a0 := raw_v0.decode_u32(boffv + kv)
					if (a0 & 255) == Defs.WOOD and (raw_v1.decode_u32(boffv + kv) & 255) == 0 and rowv > lowrow:
						lowrow = rowv
						var colm := []
						for dr in range(-1, 10):
							colm.append(str(raw_v0.decode_u32(Defs.raw_idx(rowv + dr, colv) * 4) & 255))
						var nsites := []
						for st2 in b.sites:
							if absf(float(colv) - st2.x) < 300 or absf(float(colv) - st2.y) < 300:
								nsites.append("%d-%d" % [int(st2.x), int(st2.y)])
						low = "lowest lost wood at column +%d (abs %d) row +%d (ground row +%d), id %x, S%d, fg column from just above: %s, box x0 %d, sites %s" % [ii, colv, jj, b.ground_row(colv) - int(info["y0"]), a0 >> 16, (a0 >> 8) & 63, "/".join(colm), int(info["x0"]), ",".join(nsites)]
			worst_txt = low + "; %s %s %dx%d lost %s" % ["ruined" if info["ruined"] else "intact", b.label_at(_cell_pos(int(info["x0"]) + 2, int(info["y0"]) + int(info["h"]) - 4)), info["w"], info["h"], ", ".join(lost)]
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
	# the Forge panel, for looking at the UI
	g.ui.show_forge()
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(shot_dir.path_join("forge.png"))
	g.ui.hide_forge()
	g.ui.settings_panel.visible = true
	g.ui._refresh_settings()
	await _frames(10)
	g.get_viewport().get_texture().get_image().save_png(shot_dir.path_join("settings.png"))
	g.ui.settings_panel.visible = false

	# ---- you can walk in through a cottage door (no lip, nothing in the way) ----
	var walked := "no intact cottage found"
	var walk_ok := false
	var door_t := {}
	for info in b.infos:
		if info["ruined"]:
			continue
		var nm2: String = b.label_at(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) + int(info["h"]) - 45))
		if not ("Cottage" in nm2 or "Dwelling" in nm2):
			continue
		var ox := 14                                  # YARD + 2
		var base_row := int(info["y0"]) + int(info["h"]) - 40
		var start_col := int(info["x0"]) + ox - 8
		_go(_cell_pos(start_col, base_row - 12))
		await _frames(30)
		door_t = g._door_near(_cell_pos(int(info["x0"]) + ox + 1, base_row - 15), 30.0)
		g.test_move = -1     # on screen, left is toward higher columns (where the house is)
		await _frames(150)
		g.test_move = 0
		var a_now: float = fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU)
		var col_now := int(a_now / TAU * Defs.NS)
		# it must get through the doorway: past the wall into (or through) the house
		var moved := posmod(col_now - start_col, Defs.NS)
		walk_ok = moved > 16 and moved < Defs.NS / 2
		walked = "%s: walked from column %d to %d (the inside starts at %d)" % [nm2, start_col, col_now, int(info["x0"]) + ox + 6]
		break
	_ok("you can walk into a cottage through its door", walk_ok, walked)

	# ---- doors: walking into one opens it; F (here: _set_door) closes it again ----
	if door_t.is_empty():
		_ok("a door opens when you walk into it, and closes again", false, "no door at that cottage")
	else:
		var was_open: bool = door_t["open"]
		var dp: Vector2 = door_t["pos"]
		var dang := atan2(dp.y, dp.x)
		# (the cottage's guards and any foe wandering by are cleared away first: a foe standing in the
		# doorway rightly keeps it from shutting, and a skeleton walking into it opens it again)
		for fe in g.enemies.duplicate():
			if fe.pos.distance_to(dp) < 300.0 and not fe.boss:      # (a guardian in a lair nearby stays)
				g._kill_enemy(fe)
		var foe_near := func() -> String:
			var nf_best := "none"
			var nf_bd := 1e9
			for fe2 in g.enemies:
				if fe2.dead:
					continue
				var dd2: float = fe2.pos.distance_to(dp)
				if dd2 < nf_bd:
					nf_bd = dd2
					nf_best = "%s %.0f cells off" % [fe2.type, dd2]
			return nf_best
		# stand inside, clear of the doorway, and look at the open door (saves/shots/door.png)
		var inside: Vector2 = -g.basis_r(dang) * float(door_t["side"])
		_go(dp + inside * 14.0 - dp.normalized() * 5.0)
		g.time = fposmod(dang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("door.png"))
		g._set_door(door_t, false)
		await _frames(20)
		var rawd: PackedByteArray = g.gpu.read_world()
		var nd2 := 0
		for jd in int(door_t["h"]):
			for id2 in int(door_t["w"]):
				var kd: int = Defs.raw_idx(int(door_t["row"]) + jd, posmod(int(door_t["col"]) + id2, Defs.NS), int(door_t.get("ax", door_t["col"])), int(door_t.get("aw", 1))) * 4
				if (rawd.decode_u32(kd) & 255) == Defs.WOODDOOR:
					nd2 += 1
		var want: int = int(door_t["w"]) * int(door_t["h"])
		_ok("a door opens when you walk into it, and closes again", was_open and not bool(door_t["open"]) and nd2 == want,
			"opened by walking: %s, closed again: %d of %d door cells (still open: %s; nearest foe: %s)" % [was_open, nd2, want, door_t["open"], foe_near.call()])
		# a door shot through keeps its hole: open it and shut it again, the hole is still there
		var count_door := func() -> int:
			var rr: Dictionary = g.gpu.read_rect(int(door_t["col"]), int(door_t["row"]), int(door_t["w"]), int(door_t["h"]), int(door_t.get("ax", door_t["col"])), int(door_t.get("aw", 1)))
			var nn := 0
			for v in rr["fg"]:
				if (v & 255) == Defs.WOODDOOR:
					nn += 1
			return nn
		var dmid: Vector2 = _cell_pos(int(door_t["col"]) + int(door_t["w"]) / 2, int(door_t["row"]) + int(door_t["h"]) / 3)
		g.brushes.append([dmid, 4.5, 1, 0, 9, 0, 0, 3])
		g.brushes.append([dmid + dp.normalized() * -9.0, 3.5, 1, 0, 9, 0, 0, 3])
		await _frames(6)
		var n_shot: int = count_door.call()
		g._set_door(door_t, true, g.player.pos)
		await _frames(10)
		var gone_open := 0
		for v in door_t.get("cells", []):
			if int(v) < 0:
				gone_open += 1
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("door_damaged.png"))
		g._set_door(door_t, false)
		await _frames(10)
		var n_shut: int = count_door.call()
		_ok("a damaged door keeps its damage when opened and shut", n_shot < want and n_shot > want / 2 and gone_open == want - n_shot and n_shut == n_shot and g.doors.has(door_t),
			"%d of %d cells left after the shot; open: %d parts missing from its panel; shut again: %d cells (still open: %s; nearest foe: %s)" % [n_shot, want, gone_open, n_shut, door_t["open"], foe_near.call()])
		# fire reaching an open door's panel burns it where it reaches
		g._set_door(door_t, true, g.player.pos)
		await _frames(5)
		var left0: int = g._door_left(door_t)
		var panel: Vector2 = g.door_panel_pos(door_t)
		for fk in 6:
			g.brushes.append([panel, 3.0, 3, Defs.FIRE, 0, 0, 0])
			await _frames(2)
		await _frames(20)
		var left1: int = g._door_left(door_t) if g.doors.has(door_t) else 0
		_ok("fire burns an open door where its panel is", left1 < left0, "%d parts before the fire, %d after%s" % [left0, left1, "" if g.doors.has(door_t) else " (the door is gone)"])

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
	var cobj = null
	for info in b.infos:
		# (one near the surface, where its cells are where the surface columns say: a deep vault's
		# or dungeon's go in on their own anchor)
		if not info["ruined"] and info["chests"].size() > 0:
			for ch_q in info["chests"]:
				var ch_o = _chest_obj(ch_q)
				var ch_place: String = b.label_at(ch_o.pos) if ch_o != null else ""
				var ch_odd := "Halls" in ch_place or "Crypts" in ch_place or "Tomb" in ch_place or "Mine" in ch_place or "Vault" in ch_place
				if ch_o != null and not ch_odd and ch_q.y <= b.ground_row(ch_q.x) + 6:
					chest = ch_q
					cobj = ch_o
					break
		if cobj != null:
			break
	if cobj != null:
		# (right beside it, on its floor, whichever side is open: looked at from its own grid)
		_go(cobj.pos + cobj.pos.normalized() * 14.0)
		await _frames(8)
		var ch_side: Vector2 = g.basis_r(atan2(cobj.pos.y, cobj.pos.x))
		var ch_at: Vector2 = cobj.pos + ch_side * (float(Defs.CHEST_W) * 0.5 + 6.0) + cobj.pos.normalized() * 5.0
		if g.box_solid(g.to_grid(ch_at).x - 3.5, g.to_grid(ch_at).y - 8.5, 7.0, 17.0):
			ch_at = cobj.pos - ch_side * (float(Defs.CHEST_W) * 0.5 + 6.0) + cobj.pos.normalized() * 5.0
		_go(ch_at)
		await _frames(40)
		var before := 0
		for m in Defs.NM:
			before += g.player.inv[m]
		var ch_reach: int = g._chest_in_reach().size()
		var ch_d: float = g.player.pos.distance_to(cobj.pos)
		g._try_open_chest()
		await _frames(45)
		var after := 0
		for m in Defs.NM:
			after += g.player.inv[m]
		_ok("F opens a chest and gives loot", cobj.opened and after > before, "opened %s, satchel %d -> %d (%.0f cells from it, in reach %s, at %s)" % [cobj.opened, before, after, ch_d, ch_reach > 0, b.label_at(cobj.pos)])
		var shown: bool = g.chests.has(cobj)
		await _frames(90)
		_ok("an opened chest shows its inside, then vanishes", shown and not g.chests.has(cobj), "")

		# right-click leaves a building's back wall alone; Shift + right-click (deconstruct) takes it
		var raw2: PackedByteArray = g.gpu.read_world()
		var boff: int = Defs.total_cells() * 4
		var wall := Vector2i(-1, -1)
		for dj in range(12, 26):
			for di in range(-8, 20):
				var col2 := posmod(chest.x + di, Defs.NS)
				var row2 := chest.y - dj
				var k2 := Defs.raw_idx(row2, col2) * 4
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
			var kk := Defs.raw_idx(wall.y, wall.x) * 4
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

	# ---- a chest lying on the ground stays still while you walk about (it used to jiggle) ----
	var still_c = null
	for ch in g.chests:
		if not ch.opened:
			still_c = ch
			break
	if still_c == null:
		_ok("a chest stays still while you walk about", false, "no closed chest")
	else:
		var ca0 := atan2(still_c.pos.y, still_c.pos.x)
		var walk_at := func(k: float) -> Vector2:
			var aa: float = ca0 + k / Defs.RS0
			return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + 14.0)
		_go(walk_at.call(-60.0))
		await _frames(60)
		var cp0: Vector2 = still_c.pos
		var dev := 0.0
		for walk_k in 150:
			_go(walk_at.call(-60.0 - float(walk_k) * 0.8 + (40.0 if walk_k > 75 else 0.0)))
			await _frames(1)
			dev = maxf(dev, still_c.pos.distance_to(cp0))
		_ok("a chest stays still while you walk about", dev < 0.01, "moved %.3f cells as you walked" % dev)

	# ---- a chest whose floor is dug out falls, whole (it doesn't float or come apart) ----
	# (another surface building's chest, not the one opened: same rules as for that one)
	var chest2 := Vector2i(-1, -1)
	var c2obj = null
	for info in b.infos:
		if not info["ruined"] and info["chests"].size() > 0:
			for c2_q in info["chests"]:
				var c2_o = _chest_obj(c2_q)
				if c2_o == null or c2_o == cobj or c2_q.y > b.ground_row(c2_q.x) + 6:
					continue
				var c2_place: String = b.label_at(c2_o.pos)
				if "Halls" in c2_place or "Crypts" in c2_place or "Tomb" in c2_place or "Mine" in c2_place or "Vault" in c2_place:
					continue
				chest2 = c2_q
				c2obj = c2_o
				break
		if c2obj != null:
			break
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
			if not e.boss:
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

	# ---- mud is only liquid in bogs: under the jungle's and marsh's grass the ground is solid,
	# so you (and the rain) don't sink through a slope that looks like dirt ----
	var N_m: int = Defs.NS
	var raw_m: PackedByteArray = g.gpu.read_world()
	var mud_cols := 0
	var mud_seen := 0
	var mud_deep := 0
	var firm_col := -1
	for cm in range(0, N_m, 3):
		var bnm: String = b.biome(cm)
		if bnm != "jungle" and bnm != "marsh":
			continue
		mud_cols += 1
		var grm: int = b.ground_row(cm)
		var has := false
		for j in range(grm - 2, grm + 18):
			if (raw_m.decode_u32(Defs.raw_idx(j, cm) * 4) & 255) == Defs.MUD:
				has = true
				mud_deep = maxi(mud_deep, j - grm)
		if has:
			mud_seen += 1
		elif firm_col < 0 and bnm == "jungle" and not b.wet(cm) and b.biome(cm - 8) == "jungle" and b.biome(cm + 8) == "jungle" \
				and b.free_span(cm - 15, 30, 12):
			firm_col = cm
	var firm_ok := true
	var firm_txt := "no firm jungle column"
	if firm_col >= 0:
		var grf: int = b.ground_row(firm_col)
		_go(_cell_pos(firm_col, grf - 30))
		await _frames(150)
		var pr: float = g.player.pos.length()
		var top_r: float = Defs.R_TOP - float(grf) + 0.5
		firm_ok = pr > top_r - 4.0 and pr < top_r + 20.0 and g.player.on_ground and not g.player.in_liquid
		firm_txt = "mage stands %.1f cells from the jungle surface" % (pr - top_r)
	_ok("jungle and marsh ground is solid, mud only in bogs", mud_cols > 0 and mud_seen * 100 < mud_cols * 40 and mud_deep <= 8 and firm_ok,
		"%d of %d columns have mud (deepest %d below the surface); %s" % [mud_seen, mud_cols, mud_deep, firm_txt])

	# ---- water soaks loose dirt into mud (a stone basin set into the ground: loose dirt under
	# water; set down by hand it isn't anchored, so it has to rest on the ground) ----
	var mb_a: float = g.spawn_angle - 0.13
	var mb_s: float = g.gpu.surf_at(mb_a).x
	var MBW := 20
	var MBH := 16
	var mb_x: int = Build.cell_of(Vector2(cos(mb_a), sin(mb_a)) * mb_s).x
	var mb_c := Vector2i(mb_x, b.ground_row(mb_x + MBW / 2) - MBH + 3)
	var mbd := PackedInt32Array()
	mbd.resize(MBW * MBH)
	for mj in MBH:
		for mi in MBW:
			var mb_wall := mi < 3 or mi >= MBW - 3 or mj >= MBH - 3
			var cell := 0
			if mb_wall:
				cell = Defs.STONE | 0x20000
			elif mj >= MBH - 7:
				cell = Defs.DIRT
			elif mj >= 3:
				cell = Defs.WATER
			mbd[mj * MBW + mi] = cell | (255 << 8)      # (the background is left as it is: no tree is cut)
	g.stamps.append({"x0": mb_c.x, "y0": mb_c.y, "w": MBW, "h": MBH, "data": mbd})
	_go(Vector2(cos(mb_a), sin(mb_a)) * (mb_s + 14.0))
	var mb_count := func() -> String:
		var mb_rr: Dictionary = g.gpu.read_rect(mb_c.x, mb_c.y, MBW, MBH)
		var tally := {}
		for mb_v in mb_rr["fg"]:
			var mb_nm: String = Defs.MAT_NAMES.get(mb_v & 255, str(mb_v & 255))
			tally[mb_nm] = int(tally.get(mb_nm, 0)) + 1
		return str(tally)
	await _frames(3)
	var mb_t0: String = mb_count.call()
	await _frames(600)
	var mb_r: Dictionary = g.gpu.read_rect(mb_c.x, mb_c.y, MBW, MBH)
	var n_mud := 0
	var n_dirt := 0
	for v in mb_r["fg"]:
		if (v & 255) == Defs.MUD:
			n_mud += 1
		elif (v & 255) == Defs.DIRT:
			n_dirt += 1
	_ok("water soaks loose dirt into mud", n_mud >= 10, "%d mud, %d dirt left in the basin; at first %s, then %s" % [n_mud, n_dirt, mb_t0, mb_count.call()])

	# ---- trees stand when you walk up to them, in every biome (tall ones, and ones rooted in
	# marsh mud, used to fall apart) ----
	var N0: int = Defs.NS
	var toff: int = Defs.total_cells() * 4
	var raw_t: PackedByteArray = g.gpu.read_world()
	var tree_lines := []
	var tree_ok := true
	var biomes_seen := 0
	var forest_col := -1
	for bname in ["forest", "jungle", "marsh", "mountain", "tundra", "savanna", "desert", "grove", "ashland", "ocean"]:
		var best_col := -1
		var best_n := 0
		for k in 64:
			var c0 := k * N0 / 64
			if b.biome(c0 + 60) != bname or b.biome(c0) != bname or _near_lair(c0) or _near_lair(c0 + 120):
				continue                  # (the planet's own plants: a lair's great trees are lairs.gd's)
			var n_t := _plants(raw_t, toff, c0, b.ground_row(c0 + 60))
			if n_t > best_n:
				best_n = n_t
				best_col = c0
		if best_col < 0 or best_n < 40:
			continue
		biomes_seen += 1
		if bname == "forest":
			forest_col = best_col
		var gr2: int = b.ground_row(best_col + 60)
		var bpos := _cell_pos(best_col + 60, gr2 - 30)
		_go(bpos)
		g.ui.title.visible = false
		g.time = fposmod(atan2(bpos.y, bpos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(200)
		# a picture of each biome's plants at midday (saves/shots/biome_<name>.png)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("biome_%s.png" % bname))
		var after_t := _plants(g.gpu.read_world(), toff, best_col, gr2)
		tree_lines.append("%s %d->%d" % [bname, best_n, after_t])
		if after_t < int(best_n * 0.99):           # (knitted as the planet is made: nothing should drop)
			tree_ok = false
	_ok("trees stand when you come near, in every biome", tree_ok and biomes_seen > 0, ", ".join(tree_lines))

	# ---- a tree whose trunk is cut comes down quickly, even where its crown touches another ----
	var cut_txt := "no forest found"
	var cut_ok := false
	if forest_col >= 0:
		var rw: PackedByteArray = g.gpu.read_world()
		var tcol := -1
		var tid := 0
		var most := 0
		for i in 120:
			var col := posmod(forest_col + i, N0)
			var grc: int = b.ground_row(col)
			var nw := 0
			var idc := 0
			if _near_lair(col):
				continue                  # (a lair's great trees are living plants too, but grown by lairs.gd)
			for j in range(grc - 40, grc):
				var a := rw.decode_u32(toff + Defs.raw_idx(j, col) * 4)
				if (a & 255) == Defs.WOOD and (a & 0x80000000) != 0:
					nw += 1
					idc = a >> 16
			if nw > most:
				most = nw
				tcol = col
				tid = idc
		if tcol >= 0 and most >= 15:
			var grt: int = b.ground_row(tcol)
			var count_tree := func(raw: PackedByteArray) -> int:
				var n := 0
				for j in range(grt - 110, grt - 9):
					for i in range(-40, 41):
						if (raw.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4) >> 16) == tid:
							n += 1
				return n
			_go(_cell_pos(tcol - 30, grt - 10))
			await _frames(30)
			var zone := func(raw: PackedByteArray) -> String:
				var nwz := 0
				var nfg := 0
				for j in range(grt - 10, grt - 3):
					for i in range(-5, 6):
						var kk := Defs.raw_idx(j, posmod(tcol + i, N0)) * 4
						if (raw.decode_u32(toff + kk) & 255) == Defs.WOOD:
							nwz += 1
						if (raw.decode_u32(kk) & 255) != 0:
							nfg += 1
				# support of the tree's wood well above the cut
				var sup := []
				for j in [grt - 14, grt - 20, grt - 30]:
					var a2 := raw.decode_u32(toff + Defs.raw_idx(j, tcol) * 4)
					sup.append("%d:%d" % [a2 & 255, (a2 >> 8) & 63])
				# the best-held cell of that tree above the cut, and what is around it
				var best := 99
				var where := ""
				for j in range(grt - 110, grt - 9):
					for i in range(-40, 41):
						var cc := posmod(tcol + i, N0)
						var a3 := raw.decode_u32(toff + Defs.raw_idx(j, cc) * 4)
						if (a3 >> 16) != tid:
							continue
						var sv := (a3 >> 8) & 63
						if sv < best:
							best = sv
							var nb := []
							for o in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
								nb.append(str(raw.decode_u32(Defs.raw_idx(j + o[1], posmod(cc + o[0], N0)) * 4) & 255))
							where = "S%d mat %d at %d,%d fg %s" % [sv, a3 & 255, i, grt - j, "/".join(nb)]
				return "wood in cut %d, front cells %d, sup %s, best %s" % [nwz, nfg, ",".join(sup), where]
			var before_n: int = count_tree.call(g.gpu.read_world())
			var z0: String = zone.call(g.gpu.read_world())
			# wood in the background all around (this tree and its neighbours): a felled tree should
			# still be wood afterwards, lying where it fell, not a heap of timber grains
			var wood_round := func(raw: PackedByteArray) -> int:
				var n := 0
				for j in range(grt - 150, grt + 6):
					for i in range(-170, 171):
						var kw := Defs.raw_idx(j, posmod(tcol + i, N0)) * 4
						if (raw.decode_u32(toff + kw) & 255) == Defs.WOOD or (raw.decode_u32(kw) & 255) == Defs.WOOD:
							n += 1
				return n
			var own_wood := 0
			var rw0: PackedByteArray = g.gpu.read_world()
			for j in range(grt - 110, grt - 9):
				for i in range(-40, 41):
					var a5 := rw0.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4)
					if (a5 >> 16) == tid and (a5 & 255) == Defs.WOOD:
						own_wood += 1
			var wood0: int = wood_round.call(rw0)
			# loose specks (timber grains, leaf litter) and leaves around, before and after
			var bits_round := func(raw: PackedByteArray) -> Vector2i:
				var specks := 0
				var leaves := 0
				for j in range(grt - 150, grt + 6):
					for i in range(-170, 171):
						var kbits := Defs.raw_idx(j, posmod(tcol + i, N0)) * 4
						var tfg := raw.decode_u32(kbits) & 255
						if tfg == Defs.TIMBER or tfg == Defs.LITTER:
							specks += 1
						if (raw.decode_u32(toff + kbits) & 255) == Defs.LEAF:
							leaves += 1
				return Vector2i(specks, leaves)
			var bits0: Vector2i = bits_round.call(rw0)
			var own_leaves := 0
			for j in range(grt - 110, grt - 9):
				for i in range(-40, 41):
					var a6 := rw0.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4)
					if (a6 >> 16) == tid and (a6 & 255) == Defs.LEAF:
						own_leaves += 1
			# its roots: its own wood below the ground line, in the background behind the earth
			var own_roots := 0
			for j in range(grt, grt + 19):
				for i in range(-40, 41):
					var a7 := rw0.decode_u32(toff + Defs.raw_idx(j, posmod(tcol + i, N0)) * 4)
					if (a7 >> 16) == tid and (a7 & 255) == Defs.ROOT:
						own_roots += 1
			# and across the land around: no trunk ends in the air above a slope (a flat, bare bottom):
			# the lowest wood of a tree in a column near the ground rests on earth (or its own roots)
			var bare := 0
			var feet := 0
			for i in range(-600, 601):
				var cb: int = posmod(tcol + i, N0)
				if _near_lair(cb):
					continue
				var grb: int = b.ground_row(cb)
				var foot := -1
				var lid := 0
				for j in range(grb - 8, grb + 3):
					var abf := rw0.decode_u32(toff + Defs.raw_idx(j, cb) * 4)
					if ((abf & 255) == Defs.WOOD or (abf & 255) == Defs.ROOT) and (abf >> 30) == 2:
						foot = j
						lid = abf >> 16
				if foot < 0:
					continue
				feet += 1
				var below_f := rw0.decode_u32(Defs.raw_idx(foot + 1, cb) * 4) & 255
				var below_b := rw0.decode_u32(toff + Defs.raw_idx(foot + 1, cb) * 4)
				if below_f == 0 and (below_b >> 16) != lid:
					bare += 1
			_ok("trees have roots, and trunks reach the ground on slopes", own_roots > 8 and feet > 20 and bare * 20 < feet,
				"the felled tree has %d root cells; %d of %d trunk-foot columns end over open air" % [own_roots, bare, feet])
			var max_chunks := 0
			g.hitch_us = 0
			g.prof_reset()
			# hold the dig on the trunk for a moment (each frame harvests about a third of it)
			for fk in 15:
				for dc in [-2, 0, 2]:
					g.brushes.append([_cell_pos(tcol + dc, grt - 7), 2.5, 1, 0, 4, 0, 0, 0])
				await _frames(1)
			_go(_cell_pos(tcol - 30, grt - 10))
			for fall_k in 40:
				max_chunks = maxi(max_chunks, g.chunks.list.size())
				await _frames(1)
			var mid_n: int = count_tree.call(g.gpu.read_world())
			var z1: String = zone.call(g.gpu.read_world())
			for fk3 in 50:
				max_chunks = maxi(max_chunks, g.chunks.list.size())
				await _frames(1)
			var after_n: int = count_tree.call(g.gpu.read_world())
			cut_ok = before_n > 50 and after_n < before_n / 10
			cut_txt = "column %d: %d cells of that tree above the cut, %d after 0.7 s, %d after 1.5 s" % [tcol, before_n, mid_n, after_n]
			# then it lies where it fell, still wood (it toppled as one piece)
			for fk4 in 400:
				if g.chunks.list.is_empty():
					break
				await _frames(1)
			# (one still rocking where it leans after that is set down where it lies, as saving would)
			var still_moving: int = g.chunks.list.size()
			if still_moving > 0:
				g.chunks.settle_all()
			await _frames(30)
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("felled_tree.png"))
			var rw1: PackedByteArray = g.gpu.read_world()
			var wood1: int = wood_round.call(rw1)
			var bits1: Vector2i = bits_round.call(rw1)
			var whole := max_chunks > 0 and wood0 - wood1 < own_wood * 2 / 5
			# it leaves no scatter of loose specks (how much of its crown survives depends on what it
			# lands on: a cottage wall crushes more of it than open ground; reported, not judged)
			var tidy := bits1.x - bits0.x < 40
			_ok("a felled tree topples whole and lies where it fell", whole and tidy,
				("(still moving after 400 frames: %d, set down) " % still_moving if still_moving > 0 else "") + "it came away as %d piece(s); wood around: %d before, %d after (the tree had %d); loose specks %d -> %d; leaves %d -> %d (its own %d); the game's longest frame %.1f ms (%s [%s, %s, %s, %s], %s, %s)" % [max_chunks, wood0, wood1, own_wood, bits0.x, bits1.x, bits0.y, bits1.y, own_leaves, g.hitch_us / 1000.0, _peak("lifting pieces out"), _peak("lift: read"), _peak("lift: find"), _peak("lift: make"), _peak("lift: clear"), _peak("falling pieces"), _peak("read back")])
			if not (before_n > 50 and after_n < before_n / 10):
				cut_txt += " (before: %s; after: %s)" % [z0, z1]
		else:
			cut_txt = "no tall trunk found"
	_ok("a cut tree falls quickly, even when its crown touches a neighbour", cut_ok, cut_txt)

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

	# ---- dungeons: every room reachable from the gatehouse, the reliquary sealed ----
	var dun_n := 0
	var dun_ok := true
	var dun_lines := []
	var dun_shot := Vector2i(-1, -1)
	for info in b.infos:
		var meta: Dictionary = info.get("meta", {})
		if not meta.get("dungeon", false):
			continue
		dun_n += 1
		dun_lines.append("%d of %d rooms reached%s" % [meta["reached"], meta["rooms"], ", reliquary OPEN" if meta["vault_open"] else ""])
		dun_ok = dun_ok and meta["reached"] == meta["rooms"] and meta["rooms"] >= 2 and not meta["vault_open"]
		if dun_shot.x < 0:
			dun_shot = meta["shot"]
	_ok("dungeons are built, connected, with a sealed reliquary", dun_n >= 2 and dun_ok, "%d dungeons: %s" % [dun_n, "; ".join(dun_lines)])
	if dun_shot.x >= 0:
		# a picture of a dungeon's entrance hall (saves/shots/dungeon.png)
		_go(_cell_pos(dun_shot.x, dun_shot.y - 14))
		await _frames(70)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("dungeon.png"))

	# ---- furniture and town details: background pixels only, so nothing blocks the way ----
	var decor_n := 0
	var decor_solid := 0
	var best_dec := -1
	var best_info := {}
	for info in b.infos:
		var nd: int = info.get("decor", 0)
		decor_n += nd
		decor_solid += int(info.get("decor_hid", 0))
		if nd > best_dec:
			best_dec = nd
			best_info = info
	# an intact building comes out of the generator whole: nothing of it hangs unsupported (the
	# generator's soundness pass used to cut the wall and roof away above wide furniture)
	var unsound_n := 0
	var unsound_txt := []
	for info in b.infos:
		if not info["ruined"] and int(info.get("unsound", 0)) > 12:
			unsound_n += 1
			if unsound_txt.size() < 4:
				unsound_txt.append("%s: %d cells %s" % [b.label_at(_cell_pos(int(info["x0"]) + int(info["w"]) / 2, int(info["y0"]) + int(info["h"]) - 45)), info["unsound"], str(info["meta"].get("cuts", {}))])
	_ok("intact buildings are generated whole (nothing big cut away as unsupported)", unsound_n == 0, "%d buildings lost cells%s" % [unsound_n, (": " + ", ".join(unsound_txt)) if unsound_n > 0 else ""])
	_ok("buildings are furnished, and props never block", decor_n > 400 and decor_solid == 0, "%d prop pixels, %d in front of something solid" % [decor_n, decor_solid])
	if best_dec > 0:
		# the most furnished place, at midday (saves/shots/town.png)
		var tcx := int(best_info["x0"]) + int(best_info["w"]) / 2
		var tpos := _cell_pos(tcx, b.ground_row(tcx) - 24)
		_go(tpos)
		g.ui.title.visible = false
		g.time = fposmod(atan2(tpos.y, tpos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(60)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("town.png"))
	for lab in b.labels:
		if "Village" in str(lab["name"]):
			var vcx := int(lab["x0"]) + int(lab["w"]) / 3
			var vpos := _cell_pos(vcx, b.ground_row(vcx) - 24)
			_go(vpos)
			g.time = fposmod(atan2(vpos.y, vpos.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
			await _frames(60)
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("village.png"))
			break

	# ---- clouds you can fly into ----
	var fog_best := 0.0
	var fog_at := -1.0
	for k in 48:
		var ang: float = g.spawn_angle + float(k) * 0.05
		g.test_god = true
		_go(Vector2(cos(ang), sin(ang)) * (Defs.RS0 + 150.0))
		await _frames(6)
		if g.player.fog > fog_best:
			fog_best = g.player.fog
			fog_at = ang
		if fog_best > 0.6:
			break
	if fog_at >= 0.0:
		_go(Vector2(cos(fog_at), sin(fog_at)) * (Defs.RS0 + 150.0))
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("cloud.png"))
	_ok("you can fly into a cloud", fog_best > 0.3, "deepest cloud found: %.2f" % fog_best)

	# ---- build mode: a back wall, a table and a door go up where the mage points ----
	var bg_ang: float = g.spawn_angle - 0.06      # away from where the platform test builds
	var bsurf: float = g.gpu.surf_at(bg_ang).x
	_go(Vector2(cos(bg_ang), sin(bg_ang)) * (bsurf + 12.0))
	await _frames(40)
	g.player.inv[Defs.PLANK] += 200
	g.player.inv[Defs.WOODDOOR] += 1
	if not g.build_on:
		g._toggle_build()
	var spot := func(k: float, up: float) -> Vector2:
		var aa: float = atan2(g.player.pos.y, g.player.pos.x) + k / Defs.RS0
		return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + up)
	# a patch of plank wall, painted against the ground
	g.build_cat = 0
	g.build_idx[0] = 0
	g.build_shape = 0                # painted with the brush
	var wall_at: Vector2 = spot.call(10.0, 2.0)
	g.test_aim = wall_at
	g.test_cast = true
	await _frames(12)
	g.test_cast = false
	await _frames(6)
	var wall_first := 0
	var rawf: PackedByteArray = g.gpu.read_world()
	var cqf: Vector2i = Build.cell_of(wall_at)
	for djf in range(-34, 70):
		for dif in range(-16, 17):
			var kf: int = Defs.raw_idx(cqf.y + djf, posmod(cqf.x + dif, Defs.NS)) * 4
			var af: int = rawf.decode_u32(Defs.total_cells() * 4 + kf)
			if (af & 255) == Defs.PLANK and (af & 0x4000) != 0:
				wall_first += 1
	# a table
	g.build_cat = 2
	g.build_idx[2] = 0
	# (try a few places along the ground until it fits)
	var table_at: Vector2 = spot.call(-14.0, 5.0)
	var table_ok := false
	# (try a few places along the ground until it fits; trees, and the one felled above, may fill this
	# stretch: then walk on and try again further along)
	var table_why := []
	for tk in 16:
		table_at = spot.call((-14.0 - tk * 4.0) if tk < 8 else (14.0 + (tk - 8) * 4.0), 5.0)
		g.test_aim = table_at
		await _frames(3)
		table_ok = g.build_prev.get("ok", false)
		if table_ok:
			break
		table_why.append(g.build_why)
	if not table_ok:
		for base in [-90.0, 90.0, -140.0, 140.0, -190.0, 190.0, -240.0, 240.0]:
			_go(spot.call(base, 14.0))
			await _frames(25)
			for tk2 in 9:
				table_at = spot.call(-16.0 + tk2 * 4.0, 5.0)
				g.test_aim = table_at
				await _frames(3)
				table_ok = g.build_prev.get("ok", false)
				if table_ok:
					break
			if table_ok:
				break
	if not table_ok:
		print("[tests] no spot for the table: ", table_why)
	g.build_click = true
	await _frames(6)
	var table_last: String = g.build_last
	var tstamp: Dictionary = g.build_last_stamp
	var count_decor := func(raw: PackedByteArray) -> int:
		var n := 0
		if tstamp.is_empty():
			return -1
		var boff3: int = Defs.total_cells() * 4
		for tj in int(tstamp["h"]):
			for ti in int(tstamp["w"]):
				var kt: int = Defs.raw_idx(int(tstamp["y0"]) + tj, posmod(int(tstamp["x0"]) + ti, Defs.NS)) * 4
				if (raw.decode_u32(boff3 + kt) & 255) == Defs.DECOR:
					n += 1
		return n
	var table_now: int = count_decor.call(g.gpu.read_world())
	await _frames(60)
	var table_later: int = count_decor.call(g.gpu.read_world())
	# what the table's box holds now, front and back
	var box_mats := {}
	var rawt: PackedByteArray = g.gpu.read_world()
	if not tstamp.is_empty():
		for tj2 in int(tstamp["h"]):
			for ti2 in int(tstamp["w"]):
				var kt2: int = Defs.raw_idx(int(tstamp["y0"]) + tj2, posmod(int(tstamp["x0"]) + ti2, Defs.NS)) * 4
				var fn: String = Defs.NAMES[rawt.decode_u32(kt2) & 255]
				var bn2: String = "bg " + Defs.NAMES[rawt.decode_u32(Defs.total_cells() * 4 + kt2) & 255]
				box_mats[fn] = int(box_mats.get(fn, 0)) + 1
				box_mats[bn2] = int(box_mats.get(bn2, 0)) + 1
	# a door
	g.build_cat = 1
	g.build_idx[1] = 0
	var doors_before: int = g.doors.size()
	# (well clear of the table, which is set down again where it stood later on)
	var t_ang: float = atan2(table_at.y, table_at.x)
	var by_table := func(k: float, up: float) -> Vector2:
		var aa: float = t_ang + k / Defs.RS0
		return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + up)
	_go(by_table.call(-30.0, 14.0))
	await _frames(25)
	var door_at: Vector2 = by_table.call(-30.0, 6.0)
	var door_ok := false
	for dk2 in 6:
		door_at = by_table.call(-30.0 - dk2 * 5.0, 6.0)
		g.test_aim = door_at
		await _frames(3)
		door_ok = g.build_prev.get("ok", false)
		if door_ok:
			break
	g.build_click = true
	await _frames(20)
	# a whole house (Timber style, 36 wide), wherever along the ground it fits
	for mt in [Defs.PLANK, Defs.WOOD, Defs.MASONRY, Defs.TILE, Defs.BRICK, Defs.SANDSTONE, Defs.DRYGRASS, Defs.TORCH, Defs.GLASS]:
		g.player.inv[mt] += 3000
	g.build_cat = 4
	g.build_idx[4] = 0
	g.build_style = 0
	g.build_w = 36
	g.build_floors = 1
	var house_ok := false
	var house_why := []
	var house_at := Vector2.ZERO
	var doors_mid: int = g.doors.size()
	var hb_ang: float = atan2(g.player.pos.y, g.player.pos.x)
	var at_ang := func(k: float, up: float) -> Vector2:
		var aa: float = hb_ang + k / Defs.RS0
		return Vector2(cos(aa), sin(aa)) * (g.gpu.surf_at(aa).x + up)
	# (both ways along the ground, a good way out: structures and a guardian's levelled lair may lie
	# across the near spots, so spots inside any named structure are passed over)
	var hks := []
	for hd in range(150, 1210, 40):
		hks.append(-float(hd))
		hks.append(float(hd))
	for hk in hks:
		if b.label_at(at_ang.call(hk, 8.0)) != "" or b.label_at(at_ang.call(hk - 20.0, 8.0)) != "" or b.label_at(at_ang.call(hk + 20.0, 8.0)) != "":
			continue
		# stand next to the spot (you can only build within reach), well away from the pieces above
		_go(at_ang.call(hk + 30.0, 14.0))
		await _frames(25)
		house_at = at_ang.call(hk, 8.0)
		g.test_aim = house_at
		await _frames(3)
		house_ok = g.build_prev.get("ok", false)
		if house_ok:
			break
		if house_why.size() < 6:
			house_why.append("%d: plan %s tree %s cost %s at %s" % [int(hk), g._struct.get("ok", "-"), g._struct.get("tree", "-"), str(g._struct.get("cost", {})), b.label_at(house_at)])
	if house_ok:
		g.build_click = true
		await _frames(30)
		g.test_aim = Vector2.ZERO
		# a picture of it (saves/shots/built_house.png)
		var hsave: Vector2 = g.player.pos
		_go(house_at)
		g.time = fposmod(atan2(house_at.y, house_at.x) - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
		await _frames(40)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("built_house.png"))
		_go(hsave)
		await _frames(5)
	var house_doors: int = g.doors.size() - doors_mid
	g.test_aim = Vector2.ZERO
	g._toggle_build()
	var rawb: PackedByteArray = g.gpu.read_world()
	var boffb: int = Defs.total_cells() * 4
	var n_wall := 0
	var n_decor := 0
	var n_door := 0
	for bq in [[wall_at, 0], [table_at, 1]]:
		var cq: Vector2i = Build.cell_of(bq[0])
		for dj in range(-34, 70):
			for di in range(-16, 17):
				var kb: int = Defs.raw_idx(cq.y + dj, posmod(cq.x + di, Defs.NS)) * 4
				var fb: int = rawb.decode_u32(kb) & 255
				var ab: int = rawb.decode_u32(boffb + kb)
				if bq[1] == 0 and (ab & 255) == Defs.PLANK and (ab & 0x4000) != 0:
					n_wall += 1
				elif bq[1] == 1 and (ab & 255) == Defs.DECOR:
					n_decor += 1
	# the door built: its own cells, where its record says they are
	if doors_mid > doors_before:
		var nd3: Dictionary = g.doors[doors_mid - 1]
		for dj3 in int(nd3["h"]):
			for di3 in int(nd3["w"]):
				var kd3: int = Defs.raw_idx(int(nd3["row"]) + dj3, posmod(int(nd3["col"]) + di3, Defs.NS)) * 4
				if (rawb.decode_u32(kd3) & 255) == Defs.WOODDOOR:
					n_door += 1
	_ok("build mode puts up a whole house", house_ok and house_doors == 2, "fits somewhere: %s, its doors: %d; last click: %s; %s" % [house_ok, house_doors, g.build_last, "; ".join(house_why)])
	_ok("build mode puts up walls, furniture and doors", n_wall >= 8 and n_decor >= 20 and n_door >= 60 and doors_mid == doors_before + 1,
		"wall cells %d (%d when painted), table cells %d (fit %s; %s; in its blueprint's box: %d at once, %d a second later, %d at the end; box %s, holds %s), door cells %d (fit %s), doors %d -> %d" % [n_wall, wall_first, n_decor, table_ok, table_last, table_now, table_later, count_decor.call(rawb), str([tstamp.get("x0"), tstamp.get("y0"), tstamp.get("w"), tstamp.get("h")]), str(box_mats), n_door, door_ok, doors_before, doors_mid])

	await _test_stairs()
	await _test_workshops()
	await _test_remove()

	# ---- furniture: taken whole, set down again, forged; a bed in a room makes a home ----
	var furn0: int = g.player.furn.size()
	var picked := false
	var t_item: Dictionary = {}
	var t_px := 0
	var t_left := -1
	var t_back := -1
	var back_ok := false
	var t_why := ""
	if not tstamp.is_empty():
		var t_mid: Vector2 = Build.cell_pos(int(tstamp["x0"]) + int(tstamp["w"]) / 2, int(tstamp["y0"]) + 3)
		picked = g._pick_up_furniture(g.player, t_mid)
		await _frames(4)
		t_left = count_decor.call(g.gpu.read_world())
		if g.player.furn.size() > furn0:
			t_item = g.player.furn[g.player.furn.size() - 1]
		for tr in t_item.get("rows", []):
			for tch in String(tr):
				if tch != "." and tch != "t":
					t_px += 1
		# set it down again from the Satchel tab, where it stood (from a little way off)
		_go(by_table.call(24.0, 14.0))
		await _frames(30)
		if not g.build_on:
			g._toggle_build()
		g.build_cat = Build.CAT_SATCHEL
		g.build_idx[Build.CAT_SATCHEL] = maxi(0, g.player.furn.size() - 1)
		# (loose litter or grit that blew onto its old spot meanwhile is swept off first)
		var sw: Dictionary = g.gpu.read_rect(int(tstamp["x0"]), int(tstamp["y0"]), int(tstamp["w"]), int(tstamp["h"]))
		var swd := PackedInt32Array()
		swd.resize(int(tstamp["w"]) * int(tstamp["h"]))
		swd.fill(0xFFFF)
		var swept := 0
		for swk in swd.size():
			var swm: int = sw["fg"][swk] & 255
			if swm != 0 and Defs.KIND[swm] == Defs.K_POWDER:
				swd[swk] = 0xFF00
				swept += 1
		if swept > 0:
			g.stamps.append({"x0": int(tstamp["x0"]), "y0": int(tstamp["y0"]), "w": int(tstamp["w"]), "h": int(tstamp["h"]), "data": swd})
			await _frames(2)
		g.test_aim = table_at
		await _frames(3)
		back_ok = g.build_prev.get("ok", false)
		# (something may have tumbled into that spot meanwhile: then a little way along)
		for try_k in 16:
			if back_ok:
				break
			if t_why == "":
				var wr: Dictionary = g.gpu.read_rect(int(tstamp["x0"]), int(tstamp["y0"]), int(tstamp["w"]), int(tstamp["h"]))
				var wm := {}
				for wv in wr["fg"]:
					var wn: String = Defs.NAMES[wv & 255]
					wm[wn] = int(wm.get(wn, 0)) + 1
				t_why = "its old spot holds %s; " % str(wm)
			g.test_aim = by_table.call((-4.0 - try_k * 4.0) if try_k < 8 else (4.0 + (try_k - 8) * 4.0), 5.0)
			await _frames(3)
			back_ok = g.build_prev.get("ok", false)
		g.build_click = true
		await _frames(8)
		t_back = 0
		var st3: Dictionary = g.build_last_stamp
		if not st3.is_empty():
			var rb3: Dictionary = g.gpu.read_rect(int(st3["x0"]), int(st3["y0"]), int(st3["w"]), int(st3["h"]))
			for bv in rb3["bg"]:
				if (bv & 255) == Defs.DECOR:
					t_back += 1
	_ok("furniture is picked up whole and set down again", picked and t_item.get("name", "") == "Table" and t_left == 0 and t_px == table_now and back_ok and t_back >= table_now - 2 and g.player.furn.size() == furn0,
		"picked %s as %s (%d pixels, %d were placed), left behind %d; set down again: %sfits %s, %d cells; carried %d -> %d" % [picked, t_item.get("name", "-"), t_px, table_now, t_left, t_why, back_ok, t_back, furn0, g.player.furn.size()])
	# a bed from the Wisp Forge
	var bed_r: Dictionary = {}
	for r in g.recipes:
		if String(r.get("furniture", "")) == "bed":
			bed_r = r
	var forged := false
	var bed_item: Dictionary = {}
	if not bed_r.is_empty():
		for k in bed_r["cost"]:
			g.player.inv[int(k)] += int(bed_r["cost"][k])
		var nf: int = g.player.furn.size()
		forged = g.craft(bed_r) and g.player.furn.size() == nf + 1
		if forged:
			bed_item = g.player.furn[g.player.furn.size() - 1]
	_ok("furniture is forged into the satchel", forged and bed_item.get("name", "") == "Bed" and int(bed_item.get("kind", 0)) == Build.Props.BED,
		"recipe %s, forged %s: %s" % [bed_r.get("id", "none"), forged, str(bed_item.get("name", "-"))])
	# a bed out in the open is no home; one inside the house built above is
	var sky_c: Vector2i = Build.cell_of(g.player.pos)
	var open_why: String = g._home_check({"c0": sky_c.x, "r0": sky_c.y - 150, "c1": sky_c.x + 20, "r1": sky_c.y - 140})
	var home_set := false
	var bed_placed := false
	var woke_at := -1.0
	if house_ok and forged:
		_go(house_at)
		await _frames(30)
		g.build_cat = Build.CAT_SATCHEL
		g.build_idx[Build.CAT_SATCHEL] = g.player.furn.size() - 1
		var nb0: int = g.player.furn.size()
		for bk in 7:
			g.test_aim = house_at + (house_at - g.player.pos).normalized() * 0.0 + Vector2(-house_at.y, house_at.x).normalized() * float(bk % 2 * 2 - 1) * float(bk / 2) * 5.0
			await _frames(3)
			if g.build_prev.get("ok", false):
				g.build_click = true
				await _frames(8)
				break
		bed_placed = g.player.furn.size() == nb0 - 1
		g.test_aim = Vector2.ZERO
		if g.build_on:
			g._toggle_build()
		await _frames(10)
		g.planet_state.erase("home")
		g._interact()
		home_set = g.planet_state.has("home")
		if home_set:
			var hp3: Array = g.planet_state["home"]["pos"]
			var hpos := Vector2(float(hp3[0]), float(hp3[1]))
			_go(Vector2(cos(g.spawn_angle), sin(g.spawn_angle)) * (Defs.RS0 + 40.0))
			await _frames(5)
			g._respawn()
			woke_at = g.player.pos.distance_to(hpos)
			await _frames(20)
		g.planet_state.erase("home")
	if g.build_on:
		g._toggle_build()
	_ok("a bed in a room makes a home you wake up in", open_why != "" and bed_placed and home_set and woke_at >= 0.0 and woke_at < 4.0,
		"a bed in the open needs %s; the bed set down in the house: %s, home set: %s, woke %.1f from it" % [open_why if open_why != "" else "nothing (wrong)", bed_placed, home_set, woke_at])

	# ---- holding background harvest over a wall (no furniture there) costs next to nothing ----
	_go(wall_at + wall_at.normalized() * 10.0)
	await _frames(30)
	g._pick_up_furniture(g.player, wall_at)
	await _frames(2)
	# (the best of three rounds: one hiccup of the laptop's own isn't the game's cost)
	var pick_us := 1e9
	for qr in 3:
		var tq := Time.get_ticks_usec()
		for qk in 30:
			g._pick_up_furniture(g.player, wall_at)
		pick_us = minf(pick_us, float(Time.get_ticks_usec() - tq) / 30.0)
		await _frames(2)
	_ok("background harvest over a plain wall stays cheap", pick_us < 400.0, "%.0f us a frame looking for furniture to pick up" % pick_us)

	# ---- straight walls: a block wall dragged up from the ground, a back wall rectangle beside it ----
	_go(Vector2(cos(bg_ang), sin(bg_ang)) * (bsurf + 12.0))
	await _frames(40)
	if not g.build_on:
		g._toggle_build()
	g.player.inv[Defs.MASONRY] += 400
	var shape_res := []
	var shape_ok := true
	for sh in [[Build.CAT_BLOCKS, 0, 1, Defs.MASONRY, false, 30.0, 0.0, 30.0, 26.0], [0, 0, 2, Defs.PLANK, true, -40.0, 0.0, -22.0, 14.0]]:
		g.build_cat = int(sh[0])
		g.build_idx[g.build_cat] = int(sh[1])
		g.build_shape = int(sh[2])
		g.build_thick = 2
		var mt: int = sh[3]
		# from the ground at one spot to a point above another (a straight wall snaps upright)
		var a_pos: Vector2 = spot.call(float(sh[5]), 1.5 + float(sh[6]))
		var b_pos: Vector2 = spot.call(float(sh[7]), float(sh[8]))
		var inv0: int = g.player.inv[mt]
		g.test_aim = a_pos
		await _frames(3)
		g.test_cast = true
		g.build_click = true
		await _frames(3)
		g.test_aim = b_pos
		await _frames(4)
		var laid_prev: int = g.build_prev.get("cells", []).size()
		var prev_ok: bool = g.build_prev.get("ok", false)
		g.test_cast = false
		await _frames(4)
		var used: int = inv0 - g.player.inv[mt]
		var st: Dictionary = g.build_last_stamp
		var n_in := 0
		if not st.is_empty():
			var rr: Dictionary = g.gpu.read_rect(int(st["x0"]), int(st["y0"]), int(st["w"]), int(st["h"]))
			for v in (rr["bg"] if sh[4] else rr["fg"]):
				if (v & 255) == mt and (not sh[4] or (v & 0x4000) != 0):
					n_in += 1
		var straight := false
		if not st.is_empty():
			# a block wall comes out 2 cells wide; the back wall fills its whole box
			straight = (int(st["w"]) <= 3) if not sh[4] else (n_in >= int(st["w"]) * int(st["h"]) * 0.5)
		shape_res.append("%s %s: preview %d cells (ok %s), %d used, %d in the world, box %s" % [Build.SHAPES[int(sh[2])], Defs.NAMES[mt], laid_prev, prev_ok, used, n_in, str([st.get("w"), st.get("h")])])
		if not (prev_ok and used > 20 and n_in >= used * 0.9 and straight):
			shape_ok = false
	g.test_aim = Vector2.ZERO
	g.build_shape = 2
	if g.build_on:
		g._toggle_build()
	_ok("build mode lays straight walls and back walls by dragging", shape_ok, "; ".join(shape_res))

	# ---- furniture is a layer in front of the wall: burnt or taken, the wall behind it stays ----
	var fw_at: Vector2 = spot.call(-95.0, 0.0)
	var fw_c: Vector2i = Build.cell_of(fw_at)
	var FWW := 44
	var FWH := 22
	var fwd := PackedInt32Array()
	fwd.resize(FWW * FWH)
	fwd.fill(0xff | (Defs.MASONRY << 8) | 0x40000 | 0x20000)     # an anchored stone back wall, standing on the ground
	var fw_x0: int = fw_c.x - FWW / 2
	var fw_y0: int = fw_c.y - FWH - 1
	g.stamps.append({"x0": posmod(fw_x0, Defs.NS), "y0": fw_y0, "w": FWW, "h": FWH, "data": fwd})
	await _frames(3)
	var trng := RandomNumberGenerator.new()
	trng.seed = 77
	var tdes: Dictionary = Build.Props.make("table", trng, null)
	var trows: Array = tdes["rows"]
	var t_boxes := []
	for tk2 in 2:
		var tcol: int = fw_x0 + 6 + tk2 * 22
		var tpc: Array = Build.prop_cells(trows, tcol, fw_y0 + FWH - 8, false)    # (clear of the ground: in open air)
		var tst: Dictionary = Build.prop_stamp(tpc, Build.Props.kind_id("table"))
		g.stamps.append(tst)
		t_boxes.append(tst)
	await _frames(4)
	var box_bg := func(st2: Dictionary) -> Dictionary:
		var rr: Dictionary = g.gpu.read_rect(int(st2["x0"]), int(st2["y0"]), int(st2["w"]), int(st2["h"]))
		var out := {"decor": 0, "stone": 0, "empty": 0}
		for v in rr["bg"]:
			var m2: int = v & 255
			if m2 == Defs.DECOR:
				out["decor"] += 1
			elif m2 == Defs.MASONRY:
				out["stone"] += 1
			elif m2 == 0:
				out["empty"] += 1
		return out
	var before_a: Dictionary = box_bg.call(t_boxes[0])
	_go(spot.call(-95.0, 14.0))
	await _frames(20)
	# the first is taken whole
	var tmid0: Dictionary = t_boxes[0]
	var nfurn0: int = g.player.furn.size()
	g.player.decon_pause = 0
	g._deconstruct(g.player, _cell_pos(int(tmid0["x0"]) + int(tmid0["w"]) / 2, int(tmid0["y0"]) + int(tmid0["h"]) / 2))
	var took: bool = g.player.furn.size() == nfurn0 + 1
	var paused0: int = g.player.decon_pause    # (letting go of the button clears it, so read it now)
	await _frames(4)
	var taken_now: Dictionary = box_bg.call(t_boxes[0])
	# holding harvest carries on after a moment (no need to let go and press again)
	var paused: int = paused0
	g.player.decon_pause = paused0             # still holding the button
	var nb0: int = g.brushes.size()
	for hk in paused + 1:
		g._deconstruct(g.player, fw_at + fw_at.normalized() * 30.0)
	var resumed: bool = g.brushes.size() > nb0
	g.brushes.resize(nb0)
	# the second burns
	var tmid1: Dictionary = t_boxes[1]
	var tfire: Vector2 = _cell_pos(int(tmid1["x0"]) + int(tmid1["w"]) / 2, int(tmid1["y0"]) + int(tmid1["h"]) / 2)
	# (a fireball's blast: it sets what burns alight where it reaches)
	for fk2 in 4:
		g._explode(tfire, 7.0, 1, 1, 0.0)
		await _frames(12)
	await _frames(150)
	var after_a: Dictionary = box_bg.call(t_boxes[0])
	var after_b: Dictionary = box_bg.call(t_boxes[1])
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("furniture_wall.png"))
	var burnt_pick: bool = g._pick_up_furniture(g.player, tfire)
	_ok("burnt or taken, furniture leaves the wall behind it whole", before_a["decor"] > 20 and took and taken_now["decor"] == 0 and taken_now["empty"] == 0 and after_b["decor"] < before_a["decor"] / 4 and after_b["empty"] == 0 and (after_b["decor"] > 0 or not burnt_pick) and paused > 0 and resumed,
		"before: %s; taken whole (%s): %s (after the fire next to it: %s); burnt: %s; anything left to pick up where it burnt: %s; harvest carries on after a pickup (%d frames' pause): %s" % [str(before_a), took, str(taken_now), str(after_a), str(after_b), burnt_pick, paused, resumed])

	# ---- conjuring onto a foe strikes it instead of burying it ----
	var foe = g.spawn_enemy("slime", spot.call(18.0, 8.0))
	var foe_hp: float = foe.hp
	g.sel = maxi(0, g.known.find("conjure"))
	g.mat = Defs.DIRT
	g.player.inv[Defs.DIRT] += 100
	g.test_cast = true
	for f in 20:
		g.test_aim = foe.pos
		await _frames(1)
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	await _frames(60)
	_ok("conjuring onto a foe hurts it and doesn't bury it", (g.enemies.has(foe) and foe.hp < foe_hp) or foe.hp <= 0.0, "still there: %s, health %.0f -> %.0f" % [g.enemies.has(foe), foe_hp, foe.hp])
	g.enemies.erase(foe)      # out of the way of the tests that conjure next
	g.sel = 0

	# ---- foes are dangerous: they see you, wind up (glowing) and then lunge, shoot, swoop or blink ----
	# (out in the open: level ground with nothing standing over it, so a bat has a clear dive)
	var fo_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) - 160, 110, 80)
	var fo_a: float = (float(fo_st.x) + 55.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(fo_a), sin(fo_a)) * (g.gpu.surf_at(fo_a).x + 12.0))
	await _frames(40)
	var keep_foes: Array = g.enemies.duplicate()
	g.enemies.clear()
	var foe_lines := []
	var foe_ok := true
	g.player.hp = g.max_hp
	g.iframes = 0
	# a swordsman beside you winds up, then lunges and cuts
	g.test_god = false
	var sk = g.spawn_enemy("skeleton", spot.call(16.0, 9.5))
	var saw_wind := false
	var hp_sk: float = g.player.hp
	var cut := false
	for fr2 in 200:
		if sk.act == "windup":
			saw_wind = true
		if g.player.hp < hp_sk:
			cut = true                    # (then healed straight away: a run of cuts mustn't kill him
			g.player.hp = g.max_hp        # and leave the tests after this with a dead mage)
		await _frames(1)
	g.test_god = true
	g.player.hp = g.max_hp
	foe_lines.append("skeleton: wound up %s, cut you %s" % [saw_wind, cut])
	foe_ok = foe_ok and saw_wind and cut
	g.enemies.clear()
	g.player.hp = g.max_hp
	# an archer with a clear line to you looses arrows
	var arc_at := Vector2.ZERO
	for arc_side in [-1.0, 1.0]:
		for arc_dk in [90.0, 70.0, 110.0]:
			var ap: Vector2 = spot.call(arc_side * arc_dk, 9.5)
			if FoeAI.clear_line(g, ap - ap.normalized() * 5.0, g.player.pos):
				arc_at = ap
				break
		if arc_at != Vector2.ZERO:
			break
	if arc_at != Vector2.ZERO:
		var arc = g.spawn_enemy("archer", arc_at)
		var arrows := 0
		for fr3 in 260:
			for arc_pr in g.projs:
				if arc_pr["type"] == "arrow" and arc_pr["life"] == int(Defs.PROJ["arrow"]["life"]) - 1:
					arrows += 1
			await _frames(1)
		foe_lines.append("archer %.0f cells off: %d arrows" % [arc_at.distance_to(g.player.pos), arrows])
		foe_ok = foe_ok and arrows > 0
	else:
		foe_lines.append("archer: no clear line nearby (skipped)")
	g.enemies.clear()
	g.projs.clear()
	g.player.hp = g.max_hp
	# a bat above you hangs a moment, then dives
	var bat = g.spawn_enemy("bat", spot.call(30.0, 45.0))
	var dived := false
	for fr4 in 240:
		if bat.act == "dive":
			dived = true
			break
		await _frames(1)
	foe_lines.append("bat dived: %s" % dived)
	foe_ok = foe_ok and dived
	g.enemies.clear()
	# an imp you close in on vanishes and appears again some way off
	var imp = g.spawn_enemy("imp", spot.call(14.0, 22.0))
	var imp0: Vector2 = imp.pos
	var blinked := false
	for fr5 in 120:
		if imp.blink_cd > 0:
			blinked = true
			break
		await _frames(1)
	foe_lines.append("imp blinked away: %s (%.0f cells)" % [blinked, imp.pos.distance_to(imp0)])
	foe_ok = foe_ok and blinked
	g.enemies.clear()
	g.projs.clear()
	g.player.hp = g.max_hp
	_ok("foes wind up, then lunge, shoot, swoop or blink", foe_ok, "; ".join(foe_lines))

	# ---- a skeleton opens a door to get at you (a slime can't) ----
	var door_f := {}
	for dd in g.doors:
		if not bool(dd["open"]) and not dd.has("cells") and int(dd["row"]) < Defs.ROWS:
			door_f = dd
			break
	if door_f.is_empty():
		_ok("a skeleton opens a door to get at you", false, "no shut door left")
	else:
		var dpf: Vector2 = door_f["pos"]
		var daf := atan2(dpf.y, dpf.x)
		var outw: Vector2 = g.basis_r(daf) * float(door_f["side"])
		var bottom: Vector2 = dpf + g.basis_d(daf) * (float(door_f["h"]) * 0.5)
		var up_f: Vector2 = -g.basis_d(daf)
		_go(bottom + up_f * 10.0 - outw * 24.0)
		await _frames(30)
		var sl = g.spawn_enemy("slime", bottom + up_f * 6.0 + outw * 22.0)
		sl.alert_t = 9999
		sl.seen_pos = g.player.pos
		await _frames(150)
		var slime_opened: bool = door_f["open"]
		g.enemies.clear()
		var sk2 = g.spawn_enemy("skeleton", bottom + up_f * 10.0 + outw * 26.0)
		var opened_t := -1
		for fr6 in 360:
			sk2.alert_t = 200
			sk2.seen_pos = g.player.pos
			if bool(door_f["open"]):
				opened_t = fr6
				break
			await _frames(1)
		_ok("a skeleton opens a door to get at you", opened_t >= 0 and not slime_opened,
			"a slime pushing at it for 2.5 s opened it: %s; the skeleton opened it after %d frames" % [slime_opened, opened_t])
		g.enemies.clear()
	g.enemies.append_array(keep_foes)

	# ---- foes come in from out of sight: none appears on screen ----
	var spv := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
	_go(spv * (g.gpu.surf_at(g.spawn_angle).x + 25.0))
	await _frames(40)
	var seen := 0
	var made := 0
	for depth_k in [0.0, 60.0]:
		if depth_k > 0.0:
			# and underground, in a cave
			_go(spv * (g.gpu.surf_at(g.spawn_angle).x - depth_k))
			await _frames(30)
		for k in 300:
			for e in g.enemies:
				if not e.boss:
					e.dead = true
			await _frames(1)
			g.spawn_timer = 0
			var before_n: int = g.enemies.size()
			g._try_spawn()
			if g.enemies.size() > before_n:
				made += 1
				var sp: Vector2 = g.world_to_screen(g.enemies[g.enemies.size() - 1].pos)
				if sp.x > -4 and sp.y > -4 and sp.x < g.VW + 4 and sp.y < g.VH + 4:
					seen += 1
	for e in g.enemies:
		if not e.boss:
			e.dead = true
	_ok("foes appear out of sight", made > 0 and seen == 0, "%d spawned, %d of them on screen" % [made, seen])

	# ---- a boss nobody is fighting recovers ----
	var boss_e = null
	for e in g.enemies:
		if e.type == "golem":
			boss_e = e
	if boss_e != null:
		# a picture of Vulkhar in his arena (saves/shots/boss.png)
		var bup: Vector2 = (boss_e.pos as Vector2).normalized()
		_go(boss_e.pos + Vector2(-bup.y, bup.x) * 70.0)
		await _frames(60)
		g.ui.title.visible = false
		await _frames(2)
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("boss.png"))
		# then leave him hurt and walk away
		var sp9 := Vector2(cos(g.spawn_angle), sin(g.spawn_angle))
		_go(sp9 * (g.gpu.surf_at(g.spawn_angle).x + 25.0))
		boss_e.hp = boss_e.max_hp * 0.3
		boss_e.awake = true
		await _frames(260)
		_ok("a boss left alone recovers to full health", boss_e.hp >= boss_e.max_hp and not boss_e.awake,
			"health %d of %d, %s" % [int(boss_e.hp), int(boss_e.max_hp), "asleep" if not boss_e.awake else "awake"])
	else:
		_ok("a boss left alone recovers to full health", false, "no boss in the world")
	# ---- the close view is the world as it is (the "view" setting's default): a world unit is the
	# same size on screen at any height, and the camera sits on a cell's corner (no shimmer) ----
	var wv_unrolled: bool = g.unrolled()
	var wv_c: Vector2 = g.view_c
	var wv_r := wv_c.length()
	var wv_s: int = Defs.shell_of_row(int(Defs.R_TOP - roundf(wv_r)))
	var wv_k := atan2(wv_c.y, wv_c.x) / (TAU / float(Defs.SH_N[wv_s]))
	var wv_corner: bool = absf(wv_r - roundf(wv_r)) < 0.01 and absf(wv_k - roundf(wv_k)) < 0.02
	var wv_sizes := []
	var wv_same := true
	for wv_h in [-300.0, -60.0, 0.0, 60.0, 300.0]:
		var wv_p: Vector2 = wv_c.normalized() * (wv_r + wv_h)
		var wv_a: Vector2 = g.world_to_screen(wv_p)
		var wv_b: Vector2 = g.world_to_screen(wv_p + g.basis_r(atan2(wv_p.y, wv_p.x)) * 10.0)
		var wv_px: float = wv_a.distance_to(wv_b) * g.zoom / 10.0
		wv_sizes.append("%+d: %.3f" % [int(wv_h), wv_px])
		wv_same = wv_same and absf(wv_px - 1.0) < 0.002
	_ok("the close view is the world as it is: nothing stretches going up or down, the camera sits on a cell's corner",
		not wv_unrolled and wv_corner and wv_same, "unrolled %s; camera at radius %.2f, column %.3f; a world unit across on screen at %s" % [wv_unrolled, wv_r, wv_k, ", ".join(wv_sizes)])
	# ---- ... and its picture is drawn a cell a pixel, each cell once: the cell at a point on screen is the
	# one the picture holds where the view's shader looks for it (so no column is drawn twice, or dropped,
	# which showed as bands that stayed put as you walked) ----
	var cp_ok := int(g.pic.get("mode", 0)) == 1
	var cp_bad := []
	if cp_ok:
		var cp_rows: PackedFloat32Array = g.pic["rows"]
		for cp_k in 25:
			var cp_sp := Vector2(float(g.VW) * (0.06 + 0.22 * float(cp_k % 5)), float(g.VH) * (0.06 + 0.22 * float(cp_k / 5)))
			var cp_w0: Vector2 = g.screen_to_world(cp_sp)
			var cp_row := int(floor(Defs.R_TOP - cp_w0.length()))
			var cp_n: int = Defs.SH_N[Defs.shell_of_row(cp_row)]
			var cp_col := int(floor(fposmod(atan2(cp_w0.y, cp_w0.x), TAU) / TAU * cp_n))
			# (the middle of that cell)
			var cp_a := (float(cp_col) + 0.5) / float(cp_n) * TAU
			var cp_w := Vector2(cos(cp_a), sin(cp_a)) * (Defs.R_TOP - float(cp_row) - 0.5)
			var cp_p: Vector2 = g.world_to_pic(cp_w)
			var cp_i := int(floor(cp_p.x))
			var cp_j := int(floor(cp_p.y))
			if cp_j < 0 or cp_j >= g.gpu.PH or cp_i < 0 or cp_i >= g.gpu.PW:
				cp_bad.append("%d off the picture (%d, %d)" % [cp_k, cp_i, cp_j])
				continue
			var cp_xa := int(floor(float(g.pic["a"]) / TAU * float(int(cp_rows[cp_j * 2]))))
			var cp_x := posmod(cp_xa + int(floor(g.gpu.PW * 0.5)) - 1 - cp_i, int(cp_rows[cp_j * 2]))
			if int(g.pic["y0"]) + cp_j != cp_row or cp_x != cp_col:
				cp_bad.append("%d: cell %d,%d drawn as %d,%d" % [cp_k, cp_col, cp_row, cp_x, int(g.pic["y0"]) + cp_j])
	_ok("the close view's picture holds each cell once, where the view's shader looks for it", cp_ok and cp_bad.is_empty(),
		"cell picture %s (%d x %d, margin %d, %d); %s" % [cp_ok, g.gpu.PW, g.gpu.PH, g.gpu.PMX, g.gpu.PMY, "all 25 points agree" if cp_bad.is_empty() else "; ".join(cp_bad)])
	# ---- the unrolled view (the other setting) keeps the cells around you one pixel wide at any depth ----
	var widths := []
	var view_ok := true
	for rr in [1300.0, 900.0, 500.0, 250.0, 120.0]:
		var st: float = g.unroll_step(rr)
		var cell_w: float = st * rr                  # world units per pixel across
		widths.append("%d: %.2f" % [int(rr), cell_w])
		view_ok = view_ok and cell_w > 0.45 and cell_w < 1.6
	_ok("the view isn't stretched deep down", view_ok, "world units per pixel across at radius " + ", ".join(widths))
	# ---- the view's scale never jumps: what a pixel covers changes smoothly, a seam never squeezes it
	var vw_step := 1.0           # the biggest change between rows 2 apart (world units per pixel across)
	var vw_48 := 1.0             # ... and over 48 rows (about a quarter of the screen)
	var vw_seam := 1.0           # the biggest ratio of columns across a seam
	var vw_wmin := 9.0
	var vw_wmax := 0.0
	var vw_prev := -1.0
	var vw_hist := []
	for vw_row in range(-Defs.ORBIT_ROWS, Defs.ROWS, 2):
		var vw_r := Defs.R_TOP - float(vw_row)
		if vw_r < 320.0:
			break                 # (near the heart the planet's own curve changes the scale fast)
		var vw_px: float = g.unroll_step(vw_r) * vw_r
		if vw_prev > 0.0:
			vw_step = maxf(vw_step, maxf(vw_px / vw_prev, vw_prev / vw_px))
		vw_hist.append(vw_px)
		if vw_hist.size() > 24:
			var vw_old: float = vw_hist[vw_hist.size() - 25]
			vw_48 = maxf(vw_48, maxf(vw_px / vw_old, vw_old / vw_px))
		vw_prev = vw_px
		vw_wmin = minf(vw_wmin, vw_px)
		vw_wmax = maxf(vw_wmax, vw_px)
	for vw_k in Defs.NSH - 1:
		if Defs.R_TOP - float(Defs.SH_Y1[vw_k]) >= 320.0:     # (near the heart the steps grow)
			vw_seam = maxf(vw_seam, float(Defs.SH_N[vw_k]) / float(Defs.SH_N[vw_k + 1]))
	_ok("the view never visibly changes size going up or down (no seam squeezes it)",
		vw_step < 1.01 and vw_48 < 1.12 and vw_seam < 1.05 and vw_wmin > 0.7 and vw_wmax < 1.3,
		"%d shells; biggest seam %.3f; a pixel covers %.2f - %.2f world units across, changing at most %.4f per 2 rows, %.3f per 48 rows" % [Defs.NSH, vw_seam, vw_wmin, vw_wmax, vw_step, vw_48])
	# ---- deep down, sand and a loose block fall straight through a seam, none lost or doubled ----
	var sm_s: int = mini(Defs.SURF + 4, Defs.NSH - 2)
	var sm_seam: int = Defs.SH_Y1[sm_s]              # the first row of the shell below it
	var sm_y0: int = sm_seam - 34
	var sm_w := 24
	var sm_h := 64
	# a spot in solid rock (a cave would let the sand pour out of the pocket)
	var sm_a: float = fposmod(g.spawn_angle + 0.35, TAU)
	for sm_try in 60:
		var sm_ta: float = fposmod(g.spawn_angle + 0.35 + 0.05 * sm_try, TAU)
		var sm_tc: int = int(sm_ta / TAU * Defs.NS)
		var sm_probe: Dictionary = g.gpu.read_rect(sm_tc - 6, sm_y0 - 6, sm_w + 12, sm_h + 12, sm_tc - 6, sm_w + 12)
		var sm_solid := true
		for sm_v in sm_probe["fg"]:
			if Defs.KIND[sm_v & 255] != Defs.K_SOLID:
				sm_solid = false
				break
		if sm_solid:
			sm_a = sm_ta
			break
	var sm_c: int = int(sm_a / TAU * Defs.NS)
	var sm_data := PackedInt32Array()
	for sm_j in sm_h:
		for sm_i in sm_w:
			var sm_m := 0                       # an open pocket around the seam (background cleared too)
			if sm_j < 6 and sm_i >= 12 and sm_i < 22:
				sm_m = Defs.SAND
			elif sm_j >= 2 and sm_j < 6 and sm_i >= 3 and sm_i < 7:        # (clear of the ceiling)
				sm_m = Defs.BRICK                # a loose built block (not anchored)
			sm_data.append(sm_m | (0 << 8))
	g.gpu.stamp([{"x0": sm_c, "y0": sm_y0, "w": sm_w, "h": sm_h, "data": sm_data, "ax": sm_c, "aw": sm_w}], 7)
	var sm_count := func(sm_raw: PackedByteArray, sm_mat: int, sm_above: bool) -> int:
		var sm_n := 0
		for sm_row in range(sm_y0, sm_y0 + sm_h):
			if sm_above != (sm_row < sm_seam):
				continue
			# the pocket's cells (it went in cell for cell, anchored on itself)
			for sm_i2 in sm_w:
				var sm_k: int = Defs.raw_idx(sm_row, posmod(sm_c + sm_i2, Defs.NS), sm_c, sm_w)
				var sm_t := sm_raw.decode_u32(sm_k * 4) & 255
				if sm_t == sm_mat or (sm_mat == Defs.BRICK and sm_t == Defs.DEBRIS[Defs.BRICK]):
					sm_n += 1
		return sm_n
	var sm_r0: PackedByteArray = g.gpu.read_world()
	var sm_sand0: int = sm_count.call(sm_r0, Defs.SAND, true) + sm_count.call(sm_r0, Defs.SAND, false)
	var sm_stone0: int = sm_count.call(sm_r0, Defs.BRICK, true)
	var sm_mid: float = Defs.R_TOP - float(sm_seam)
	g.gpu.settle([[Vector2(cos(sm_a), sin(sm_a)) * sm_mid, 90.0]], 0.0, 400)
	var sm_r1: PackedByteArray = g.gpu.read_world()
	var sm_sand_up: int = sm_count.call(sm_r1, Defs.SAND, true)
	var sm_sand_dn: int = sm_count.call(sm_r1, Defs.SAND, false)
	var sm_stone_up: int = sm_count.call(sm_r1, Defs.BRICK, true)
	var sm_stone_dn: int = sm_count.call(sm_r1, Defs.BRICK, false)
	# (a look at the seam and the shells around it, from inside the pocket)
	var sm_back: Vector2 = g.player.pos
	_go(Vector2(cos(sm_a), sin(sm_a)) * (sm_mid - 24.0))
	await _frames(40)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("deep_seam.png"))
	_go(sm_back)
	await _frames(10)
	_ok("deep down, sand and a loose block fall straight through a seam (none lost or doubled)",
		sm_sand0 > 40 and sm_sand_up == 0 and sm_sand_dn == sm_sand0 and sm_stone0 >= 8 and sm_stone_up == 0 and sm_stone_dn > 0,
		"seam at row %d (shells of %d and %d columns); sand %d -> %d above, %d below; brick %d above -> %d above, %d below (some may have broken into rubble)" % [sm_seam, Defs.SH_N[sm_s], Defs.SH_N[sm_s + 1], sm_sand0, sm_sand_up, sm_sand_dn, sm_stone0, sm_stone_up, sm_stone_dn])

	# ---- one-way platforms: land on one, drop through it (down + jump), jump up through it ----
	# (a level stretch near where you arrive with nothing standing on it: trees, logs from the felled
	# tree, a building)
	var pst := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 24, 40, 70)
	var pcol := pst.x + 16
	var pg: int = pst.y
	var prow := pg - 16
	_go(_cell_pos(pcol, pg - 40))
	await _frames(10)
	# a stone pillar from the ground up to the strip (conjuring places at most 9 cells a frame)
	var pil_g: int = maxi(b.ground_row(pcol + 14), b.ground_row(pcol + 15)) + 1
	for jr in range(pil_g, prow, -1):
		for dc2 in [13, 14, 15]:
			g.brushes.append([_cell_pos(pcol + dc2, jr), 0.6, 5, Defs.STONE, 0, 9, 0])
		await _frames(1)
	# from the pillar outward, so every new piece is already held by the last
	for k in range(15, -6, -1):
		g.brushes.append([_cell_pos(pcol + k, prow), 0.6, 5, Defs.SCAFFOLD, 0, 9, 0])
		g.brushes.append([_cell_pos(pcol + k, prow + 1), 0.6, 5, Defs.SCAFFOLD, 0, 9, 0])
		await _frames(1)
	await _frames(3)
	_go(_cell_pos(pcol, prow - 30))
	await _frames(80)
	var strip_n := 0
	for k in range(-5, 16):
		if g.type_at(_cell_pos(pcol + k, prow)) == Defs.SCAFFOLD:
			strip_n += 1
	var pillar_n := 0
	for jr2 in range(prow + 1, pil_g):
		if g.type_at(_cell_pos(pcol + 14, jr2)) == Defs.STONE:
			pillar_n += 1
	var landed: bool = g.player.on_platform
	var row_on := int(Defs.R_TOP - (g.player.pos.length() - g.player.h * 0.5))
	g.test_down = true
	g.test_jump = true
	await _frames(3)
	g.test_jump = false
	g.test_down = false
	await _frames(60)
	var row_down := int(Defs.R_TOP - (g.player.pos.length() - g.player.h * 0.5))
	var dropped: bool = row_down > prow + 4 and g.player.on_ground and not g.player.on_platform
	g.test_jump = true
	await _frames(3)
	g.test_jump = false
	await _frames(90)
	var back_up: bool = g.player.on_platform
	_ok("platforms: land on one, drop through it, jump up through it", landed and dropped and back_up,
		("(at column %d) " % pcol) + "strip at row %d (%d of 21 cells there, pillar %d of %d): stood at row %d (on it %s), after down + jump row %d (through %s), after a jump on it again %s" % [prow, strip_n, pillar_n, pil_g - prow - 1, row_on, landed, row_down, dropped, back_up])

	# ---- unsupported blocks fall, and falling rock hurts (on a clear stretch: nothing over you) ----
	var fst := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 90, 50, 70)
	var fa: float = (float(fst.x) + 10.5) / float(Defs.NS) * TAU
	var sp := Vector2(cos(fa), sin(fa))
	var rs: float = g.gpu.surf_at(fa).x
	_go(sp * (rs + 30.0))
	await _frames(60)
	var up: Vector2 = g.player.pos.normalized()
	var side := Vector2(-up.y, up.x)
	var mid: Vector2 = g.player.pos + side * 30.0 + up * 26.0
	# the conjured stone, anywhere in the cells around the spot (the grid samples the world a
	# fraction of a cell off, so the blob's edge can land on either side of one cell)
	var stone_near := func() -> bool:
		for oj in [-1.0, 0.0, 1.0]:
			for oi in [-1.0, 0.0, 1.0]:
				if g.type_at(mid + side * oi + up * oj) == Defs.STONE:
					return true
		return false
	g.brushes.append([mid, 1.8, 5, Defs.STONE, 0, 9, 0])
	await _frames(2)
	var placed: bool = stone_near.call()
	# watch it frame by frame: it should creak while it is still in place, then drop
	var creaking := false
	var gone_at := -1
	var max_creak := 0
	for f in 120:
		await _frames(1)
		var here: bool = stone_near.call()
		max_creak = maxi(max_creak, g.gpu.counts[Defs.C_CREAK_N])
		if here and g.gpu.counts[Defs.C_CREAK_N] > 0:
			creaking = true
		if not here and gone_at < 0:
			gone_at = f
	var still: bool = stone_near.call()
	_ok("a loose block creaks first, then falls", placed and creaking and not still, "placed %s, creaked %s (max %d cells), left its spot at frame %d" % [placed, creaking, max_creak, gone_at])
	g.test_god = false
	g.hp = g.max_hp
	g.iframes = 0
	var hp0: float = g.hp
	# (a block big enough that, lifted out as a rigid piece, it can't slip past him between the
	# points a falling piece is checked against: a 3-cell one once fell by without a scratch)
	g.brushes.append([g.player.pos + up * 40.0, 2.6, 5, Defs.STONE, 0, 8, 0])
	await _frames(150)
	_ok("falling rock hurts the mage", g.hp < hp0, "health %.0f -> %.0f" % [hp0, g.hp])
	# digging a pit right under your feet, again and again, costs nothing: you drop in with the rim
	# (on clear ground: nothing standing over you that the digging could bring down, and no cave under
	# it: breaking into one brings its roof down after you, and that does hurt)
	var pit_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) - 120, 30, 70, 6, 64)
	var pit_a: float = (float(pit_st.x) + 15.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(pit_a), sin(pit_a)) * (g.gpu.surf_at(pit_a).x + 14.0))
	await _frames(60)
	# (and nothing about to bite: a foe walking by once took 3 off and failed it)
	for pt_e in g.enemies.duplicate():
		if not pt_e.boss and pt_e.guard_id < 0:
			g.enemies.erase(pt_e)
	g.projs.clear()
	g.spawn_timer = 600
	g.hp = g.max_hp
	g.iframes = 0
	var hp1: float = g.hp
	for pk in 4:
		var upk: Vector2 = g.player.pos.normalized()
		g.brushes.append([g.player.pos - upk * 12.0, g.player.dig_r, 1, 0, g.player.tier, 0, 0, 0])
		await _frames(25)
	await _frames(60)
	_ok("digging a pit under yourself doesn't hurt", g.hp >= hp1, "health %.0f -> %.0f" % [hp1, g.hp])
	# ---- a frozen world's open water ices over from the top (tried here with the planet's frost turned
	# on: a basin dug and filled, then left out in the cold) ----
	# (you stand on the same clear stretch, well to the side of the basin, and can't come to harm: a
	# spot picked blind once left you somewhere you died, and the checks after it ran with you dead)
	var fz_god0: bool = g.test_god
	g.test_god = true
	var fz_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 160, 80, 60, 4, 30)
	var fz_c: int = fz_st.x + 20
	var fz_a: float = (float(fz_c) + 0.5) / float(Defs.NS) * TAU
	var fz_up := Vector2(cos(fz_a), sin(fz_a))
	var fz_g: float = g.gpu.surf_at(fz_a).x
	var fz_ya: float = (float(fz_st.x) + 66.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(fz_ya), sin(fz_ya)) * (g.gpu.surf_at(fz_ya).x + 12.0))
	await _frames(30)
	g.brushes.append([fz_up * (fz_g - 5.0), 9.0, 1, 0, 9, 0, 0, 0])
	await _frames(20)
	g.brushes.append([fz_up * (fz_g - 6.0), 7.5, 5, Defs.WATER, 0, 400, 0])
	await _frames(90)
	var fz_count := func() -> Vector2i:
		var fz_rr: Dictionary = g.gpu.read_rect(fz_c - 14, fz_st.y - 20, 28, 40)
		var fz_w := 0
		var fz_i := 0
		for fz_v in fz_rr["fg"]:
			if (fz_v & 255) == Defs.WATER:
				fz_w += 1
			elif (fz_v & 255) == Defs.ICE:
				fz_i += 1
		return Vector2i(fz_w, fz_i)
	var fz0: Vector2i = fz_count.call()
	var fz_was: float = float(g.clim.get("freeze", 0.0))
	g.clim["freeze"] = 5.0
	await _frames(600)
	g.clim["freeze"] = fz_was
	g.test_god = fz_god0
	var fz1: Vector2i = fz_count.call()
	_ok("on a frozen world, open water ices over from the top", fz0.x >= 20 and fz0.y == 0 and fz1.y >= 8 and fz1.x > 0,
		"the basin: water %d, ice %d; 10 s in the frost: water %d, ice %d (the ice on top, the water under it); you: health %.0f, %s" % [fz0.x, fz0.y, fz1.x, fz1.y, g.hp, g.state])
	await _test_hazards()
	await _test_sky()
	# ---- health doesn't come back by itself; a draught and Mending bring it back over a moment ----
	# (nothing about to bite: a wild creature wandering by would muddle the sums)
	for hl_e in g.enemies.duplicate():
		if not hl_e.boss and hl_e.guard_id < 0:
			g.enemies.erase(hl_e)
	g.spawn_timer = 600
	var hl_god0: bool = g.test_god
	g.test_god = true                         # (nothing may hurt you while it counts the healing)
	g.hp = 40.0
	g.player.heal_left = 0.0
	await _frames(120)
	var hp_idle: float = g.hp
	g.items["potion"] = 1
	g.player.potion_cd = 0
	var drank: bool = g._drink(g.player)
	await _frames(100)
	var hp_drunk: float = g.hp
	var again: bool = g._drink(g.player)             # none left (and too soon)
	g.hp = 40.0
	if not g.known.has("mend"):
		g.known.append("mend")
	g.mana = g.max_mana
	g.player.cast_cd = 0
	g._cast(g.player, "mend", g.player.pos)
	var mana_after: float = g.mana
	await _frames(90)
	var hp_mended: float = g.hp
	g.known.erase("mend")
	g.test_god = hl_god0
	_ok("health only comes back from a draught or Mending", hp_idle == 40.0 and drank and absf(hp_drunk - 40.0 - Defs.POTION_HEAL) < 1.0 and not again and int(g.items.get("potion", 0)) == 0 and absf(hp_mended - 40.0 - Defs.MEND_HEAL) < 1.0 and mana_after < g.max_mana - 50.0,
		"idle 2 s: %.1f; drank %s: %.1f; another: %s; Mending: %.1f (mana %.0f of %.0f)" % [hp_idle, drank, hp_drunk, again, hp_mended, mana_after, g.max_mana])
	g.hp = g.max_hp
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
	_ok("holds 60 fps at the surface", wall < 18.5, "%.1f ms per frame, game %.1f ms, waiting for the GPU %.1f ms" % [wall, g.perf_cpu_ms, g.perf_wait_ms])
	# the same with no frame cap: how much room there is, and where the time goes
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await _frames(30)
	g.prof_reset()
	worst_us = 0
	g.hitch_us = 0
	var tu0 := Time.get_ticks_usec()
	await _frames(300)
	var uncapped := float(Time.get_ticks_usec() - tu0) / 300.0 / 1000.0
	var ptxt: String = g.prof_text(14, "; ")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	_ok("frame time with no cap", uncapped < 16.7, "%.2f ms a frame (%.0f fps), longest %.1f ms (the game's own %.1f); average ms (peak): %s" % [uncapped, 1000.0 / uncapped, worst_us / 1000.0, g.hitch_us / 1000.0, ptxt])
	# (the busy-scene benchmark runs last: its fires, pits and poured sand spoiled the checks after it)
	# ---- the world keeps its pace when frames are slow (a laptop on battery) ----
	var t_before: float = g.time
	Engine.max_fps = 30
	var tw := Time.get_ticks_usec()
	await _frames(60)
	var secs := float(Time.get_ticks_usec() - tw) / 1000000.0
	Engine.max_fps = 60
	var rate: float = (g.time - t_before) / maxf(secs, 0.001)
	_ok("the game keeps full speed at 30 fps", absf(rate - 60.0) < 8.0, "%.1f ticks per second over %.1f s at 30 fps" % [rate, secs])

	# ---- the Wisp Forge lists its recipes and crafts ----
	g.ui.show_forge()
	await _frames(2)
	var cards := 0
	for c in g.ui.forge_list.get_children():
		if c is GridContainer:
			cards += c.get_child_count()
	g.ui.hide_forge()
	var wide: Dictionary = {}
	for r in g.recipes:
		if r["id"] == "wide":
			wide = r
	var crafted := false
	if not wide.is_empty():
		g.dig_r = 7.5
		for k in wide["cost"]:
			g.player.inv[int(k)] += int(wide["cost"][k])
		crafted = g.craft(wide) and g.dig_r >= 11.0
	var shown := 0
	for r2 in g.recipes:
		if not g.recipe_hidden(r2):
			shown += 1
	await _test_gear()
	await _test_towns()
	await _test_vfx()
	await _test_start()
	await _test_recipes()
	await _test_ui()
	_ok("the Wisp Forge lists recipes and crafts", cards == shown and crafted, "%d of %d recipe cards (%d hidden until their ore is found), crafting %s" % [cards, shown, g.recipes.size() - shown, "works" if crafted else "failed"])

	# ---- a building left hanging comes down as a whole once you dig at any part of it ----
	# (a stone box with a plank back wall, stamped in the air the way the generator stamps buildings:
	# anchored and built; digging at one corner must wake all of it, and with nothing under it, it falls)
	var hang_a: float = g.spawn_angle + 0.09
	var hang_s: float = g.gpu.surf_at(hang_a).x
	var hang_c: Vector2i = Build.cell_of(Vector2(cos(hang_a), sin(hang_a)) * (hang_s + 130.0))   # above the treetops
	var HW := 30
	var hd := PackedInt32Array()
	hd.resize(HW * HW)
	for hj in HW:
		for hi in HW:
			var edge := mini(mini(hi, HW - 1 - hi), mini(hj, HW - 1 - hj)) < 3
			hd[hj * HW + hi] = (Defs.MASONRY if edge else 0) | (Defs.PLANK << 8) | 0x40000 | 0x20000
	g.stamps.append({"x0": hang_c.x, "y0": hang_c.y, "w": HW, "h": HW, "data": hd})
	_go(Vector2(cos(hang_a + 0.04), sin(hang_a + 0.04)) * (hang_s + 14.0))
	await _frames(60)
	var hang_tally := func() -> Array:
		var rr: Dictionary = g.gpu.read_rect(hang_c.x, hang_c.y, HW, HW)
		var nf := 0
		var anch := 0
		for v in rr["fg"]:
			if (v & 255) == Defs.MASONRY:
				nf += 1
				if (v & 0x40000000) != 0:
					anch += 1
		var nb := 0
		for v in rr["bg"]:
			if (v & 255) == Defs.PLANK:
				nb += 1
		var st_lo := 99
		var st_hi := -1
		var life := 0
		var n_still := 0
		var near := {}
		var fgs: PackedInt32Array = rr["fg"]
		for k in fgs.size():
			var v: int = fgs[k]
			if (v & 255) == Defs.MASONRY:
				st_lo = mini(st_lo, (v >> 24) & 63)
				st_hi = maxi(st_hi, (v >> 24) & 63)
				if ((v >> 16) & 255) > 0:
					life += 1
				else:
					n_still += 1
			elif (v & 255) != 0:
				var nm: String = Defs.NAMES[v & 255]
				near[nm] = int(near.get(nm, 0)) + 1
		return [nf, anch, nb, "support %d-%d, %d moving or creaking, inside also %s" % [st_lo, st_hi, life, str(near)], n_still]
	var hang0: Array = hang_tally.call()
	await _frames(120)
	var hang_still: Array = hang_tally.call()     # left alone, it stays as built
	hang_still.resize(3)
	g.brushes.append([_cell_pos(hang_c.x + 1, hang_c.y + 1), 3.0, 1, 0, 9, 0, 0, 0])
	var hang_chunks := 0
	var hang_shot := false
	g.hitch_us = 0
	g.prof_reset()
	for hang_k in 560:
		hang_chunks = maxi(hang_chunks, g.chunks.list.size())
		if not hang_shot and g.chunks.list.size() > 3 and hang_k > 60:
			hang_shot = true
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("collapse.png"))
		await _frames(1)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("hanging.png"))
	var hang1: Array = hang_tally.call()
	hang0.resize(3)
	# it came down in pieces that stayed stone, not in a shower of gravel
	var gr_h: int = b.ground_row(hang_c.x + HW / 2)
	var hang_wide: Dictionary = g.gpu.read_rect(hang_c.x - 90, hang_c.y, HW + 180, gr_h - hang_c.y + 8)
	var n_mas := 0
	var n_grav := 0
	for v in hang_wide["fg"]:
		if (v & 255) == Defs.MASONRY:
			n_mas += 1
		elif (v & 255) == Defs.GRAVEL:
			n_grav += 1
	_ok("a collapsing building falls in pieces, not to dust", hang_chunks >= 3 and n_mas > int(hang0[0]) / 2,
		"%d pieces at once; afterwards %d stone blocks and %d gravel (it had %d stone); the game's longest frame %.1f ms (%s, %s, %s)" % [hang_chunks, n_mas, n_grav, hang0[0], g.hitch_us / 1000.0, _peak("lifting pieces out"), _peak("falling pieces"), _peak("read back")])
	_ok("a building left hanging comes down once you dig at any part of it", int(hang0[0]) > 250 and hang_still == hang0 and int(hang1[1]) == 0 and int(hang1[4]) < int(hang0[0]) / 3 and int(hang1[2]) < int(hang0[2]) / 5,
		"stone %d (anchored %d), back wall %d; left alone 2 s: %s; 9 s after digging one corner: stone %d (anchored %d), back wall %d; %s" % [hang0[0], hang0[1], hang0[2], str(hang_still), hang1[0], hang1[1], hang1[2], hang1[3]])

	# ---- the orbit band: cells above the air that can be built into, and vacuum ----
	var ob_ang: float = atan2(g.player.pos.y, g.player.pos.x) + 0.05
	var ob_up := Vector2(cos(ob_ang), sin(ob_ang))
	g.time = fposmod(ob_ang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
	# (alive and well: a mage killed by an earlier test isn't updated, breath included)
	g.player.dead = false
	g.player.hp = g.player.max_hp
	g.test_god = true
	_go(ob_up * (Defs.R_TOP + 70.0))
	await _frames(10)
	# a stone ledge stamped into the band (a blueprint is laid out in surface columns; up there each of
	# its cells covers two), a patch of fire beside it
	var ob_c: Vector2i = Build.cell_of(ob_up * (Defs.R_TOP + 40.0))
	var ob_led := PackedInt32Array()
	ob_led.resize(24 * 3)
	ob_led.fill(Defs.STONE | 0xFF00 | 0x20000)        # anchored stone, background left alone
	g.stamps.append({"x0": ob_c.x - 12, "y0": ob_c.y, "w": 24, "h": 3, "data": ob_led})
	var ob_fire := PackedInt32Array()
	ob_fire.resize(16)
	ob_fire.fill(Defs.FIRE | 0xFF00)
	g.stamps.append({"x0": ob_c.x + 16, "y0": ob_c.y - 6, "w": 4, "h": 4, "data": ob_fire})
	await _frames(3)
	var ob_rr: Dictionary = g.gpu.read_rect(ob_c.x - 12, ob_c.y, 24, 3)
	var ob_stone := 0
	for v in ob_rr["fg"]:
		if (v & 255) == Defs.STONE:
			ob_stone += 1
	var ob_raw: PackedByteArray = g.gpu.read_world()
	var ob_fires := 0
	for v2 in g.gpu.read_rect(ob_c.x + 14, ob_c.y - 8, 8, 8)["fg"]:
		if (v2 & 255) == Defs.FIRE:
			ob_fires += 1
	# water poured on the ledge freezes; sand dropped beside it falls out of the band into the air below
	g.brushes.append([ob_up * (Defs.R_TOP + 47.0), 2.5, 5, Defs.WATER, 0, 18, 0])
	var ob_side: Vector2 = Vector2(-ob_up.y, ob_up.x)
	await _frames(2)          # (conjuring brushes in one frame share one count of cells placed)
	g.brushes.append([ob_up * (Defs.R_TOP + 24.0) + ob_side * 30.0, 2.0, 5, Defs.SAND, 0, 12, 0])
	g.player.inv[Defs.SAND] += 60
	g.player.inv[Defs.WATER] += 60
	var ob_inv0: int = g.player.inv[Defs.SAND]
	var ob_b0: float = g.player.breath
	var ob_st := "%s, dead %s" % [g.state, g.player.dead]
	var ob_f0: int = g.frame
	for obk in 90:
		_go(ob_up * (Defs.R_TOP + 70.0))
		await _frames(1)
	var ob_b1: float = g.player.breath
	ob_st += ", %d ticks, at radius %.0f; sand in the satchel %d -> %d" % [g.frame - ob_f0, g.player.pos.length(), ob_inv0, g.player.inv[Defs.SAND]]
	var ob_above: Dictionary = g.gpu.read_rect(ob_c.x - 14, ob_c.y - 10, 28, 10)
	var ob_m := {}
	for v3 in ob_above["fg"]:
		var nm3: String = Defs.NAMES[v3 & 255]
		ob_m[nm3] = int(ob_m.get(nm3, 0)) + 1
	var ob_sc: Vector2i = Build.cell_of(ob_up * (Defs.R_TOP + 24.0) + ob_side * 30.0)
	var ob_sand_up := 0
	for v4 in g.gpu.read_rect(ob_sc.x - 16, -Defs.ORBIT_ROWS, 32, Defs.ORBIT_ROWS)["fg"]:
		if (v4 & 255) == Defs.SAND:
			ob_sand_up += 1
	var ob_sand_air := 0
	for v5 in g.gpu.read_rect(ob_sc.x - 20, 0, 40, 520)["fg"]:
		if (v5 & 255) == Defs.SAND:
			ob_sand_air += 1
	var ob_fires2 := 0
	for v6 in g.gpu.read_rect(ob_c.x + 14, ob_c.y - 8, 8, 8)["fg"]:
		if (v6 & 255) == Defs.FIRE:
			ob_fires2 += 1
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("orbit.png"))
	_ok("the orbit band above the air takes building", ob_stone == 72 and ob_raw.size() == Defs.total_cells() * 8,
		"ledge %d of 72 stone cells at row %d (radius %.0f, the air ends at %.0f); %d shells, the top one %d columns" % [ob_stone, ob_c.y, Defs.R_TOP - ob_c.y, Defs.R_TOP, Defs.NSH, Defs.SH_N[0]])
	_ok("vacuum: water freezes, fire goes out, sand falls out of the band, you hold your breath",
		int(ob_m.get("Ice", 0)) > 0 and int(ob_m.get("Water", 0)) == 0 and ob_fires2 == 0 and ob_sand_up == 0 and ob_sand_air > 0 and ob_b1 < ob_b0,
		"above the ledge %s; fire %d -> %d; sand left up there %d, fallen into the air %d; breath %.0f -> %.0f (%s)" % [str(ob_m), ob_fires, ob_fires2, ob_sand_up, ob_sand_air, ob_b0, ob_b1, ob_st])
	g.player.breath = g.player.max_breath
	g.chunks.clear()

	await _test_lairs()
	await _test_guardians()
	await _test_wardens()

	await _test_creatures()
	await _test_ecology()
	await _test_fog()

	await _test_climb()
	await _test_nav()

	# ---- save and load give back the same world ----
	# (pieces still tumbling are set down first: saving would set them down anyway)
	g.chunks.settle_all()
	if not g.stamps.is_empty():
		g.gpu.stamp(g.stamps, g.frame)
		g.stamps.clear()
	var a: PackedByteArray = g.gpu.read_world()
	g.save_world(true)
	var loaded: bool = g._load_world(0)
	var bb: PackedByteArray = g.gpu.read_world()
	_ok("saving and loading the world round-trips", loaded and _sha(a) == _sha(bb), "%.1f MB raw" % (a.size() / 1048576.0))

	# ---- space: up out of the orbit band, the planet shown as its picture, the staff jet, and back ----
	var sx_ang: float = atan2(g.player.pos.y, g.player.pos.x)
	var sx_up := Vector2(cos(sx_ang), sin(sx_ang))
	g.player.dead = false
	g.test_god = true
	g.time = fposmod(sx_ang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
	_go(sx_up * (Defs.R_SPACE - 40.0))
	g.test_jump = true
	var sx_in := -1
	for sxk in 240:
		g.player.mana = g.player.max_mana
		await _frames(1)
		if g.space.active:
			sx_in = sxk
			break
	g.test_jump = false
	var sx_pic: bool = not g.space.pictures.get(int(g.planet["index"]), {}).is_empty()
	# jet outward: the camera stays on you; once the planet is out of sight the GPU rests
	g.test_cast = true
	var sx_gf0: int = g.gpu.frame
	var sx_off := -1
	for sxk2 in 260:
		g.test_aim = g.player.pos * 2.0
		g.player.mana = g.player.max_mana
		await _frames(1)
		if not g.space.live and sx_off < 0:
			sx_off = sxk2
			sx_gf0 = g.gpu.frame
	g.test_cast = false
	var sx_far: float = g.player.pos.length() - Defs.R_SPACE
	var sx_gf1: int = g.gpu.frame
	var sx_zoom: float = g.zoom
	await _frames(3)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("space.png"))
	# and back: aim at the planet until you're in the orbit band again
	g.test_cast = true
	var sx_back := -1
	for sxk3 in 1800:
		g.test_aim = g.player.pos * 0.5
		g.player.mana = g.player.max_mana
		await _frames(1)
		if not g.space.active:
			sx_back = sxk3
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	var sx_gf2: int = g.gpu.frame
	await _frames(150)
	var sx_r: float = g.player.pos.length()
	_ok("you fly out into space and back down without a loading screen",
		sx_in >= 0 and sx_pic and sx_off >= 0 and sx_gf1 == sx_gf0 and sx_far > 800.0 and sx_back >= 0 and g.gpu.frame > sx_gf2 + 60 and absf(g.zoom - float(g.zoom_levels[g.zoom_i])) < 0.05 and sx_r < Defs.R_SPACE,
		"out after %d ticks of levitating (picture taken: %s); the picture took over after %d ticks of the jet (GPU frames while it showed: %d); %.0f past the orbit band at zoom %.1f; back in the band after %d ticks; then the planet ran again (%d GPU frames in 150 ticks), zoom %.2f, you at radius %.0f" % [sx_in, sx_pic, sx_off, sx_gf1 - sx_gf0, sx_far, sx_zoom, sx_back, g.gpu.frame - sx_gf2, g.zoom, sx_r])

	# ---- an asteroid: out by one, the view comes in close, you mine it, bump it, cut it in two ----
	g.player.dead = false
	g.test_god = true
	_go(sx_up * (Defs.R_SPACE - 40.0))
	g.test_jump = true
	for as_k in 240:
		g.player.mana = g.player.max_mana
		await _frames(1)
		if g.space.active:
			break
	g.test_jump = false
	g.space._ensure_rocks(true)
	var as_n0: int = g.space.home_rocks().size()
	var as_kinds := {}
	for as_a in g.space.home_rocks():
		as_kinds[as_a.kind] = int(as_kinds.get(as_a.kind, 0)) + 1
	var as_r = null                          # (the biggest stony one)
	for as_a2 in g.space.home_rocks():
		if as_a2.kind == "stony" and (as_r == null or as_a2.mass > as_r.mass):
			as_r = as_a2
	if as_r == null:
		as_r = g.space.home_rocks()[0]
	as_r.omega = 0.0                          # (held still, so the spot you dig at stays put)
	as_r.vel = Vector2.ZERO
	# its surface on the side facing the planet, and you a little off it
	var as_dir: Vector2 = (-as_r.pos).normalized()
	var as_s: Vector2 = as_r.pos
	for as_st in 400:
		if not as_r.solid_at(as_s) and as_st > 3:
			break
		as_s += as_dir * 0.5
	g.player.pos = as_s + as_dir * 14.0
	g.cam_c = g.player.pos
	g.space.vel = Vector2.ZERO
	for as_k2 in 150:
		g.space.vel = Vector2.ZERO
		await _frames(1)
	var as_zoom: float = g.zoom
	var as_live: bool = g.space.live
	# mine toward its middle
	var as_inv0 := 0
	for as_v in g.player.inv:
		as_inv0 += int(as_v)
	var as_c0: int = as_r.count()
	g.test_dig = true
	for as_k3 in 180:
		g.test_aim = as_s - as_dir * (3.0 + float(as_k3) / 180.0 * 18.0)
		g.space.vel = Vector2.ZERO
		await _frames(1)
	g.test_dig = false
	g.test_aim = Vector2.ZERO
	await _frames(12)
	var as_inv1 := 0
	for as_v2 in g.player.inv:
		as_inv1 += int(as_v2)
	var as_c1: int = as_r.count()
	await _frames(2)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("asteroid.png"))
	# fly into it: you never end up inside it
	var as_in := 0
	for as_k4 in 60:
		g.space.vel = (as_r.pos - g.player.pos).normalized() * 3.0
		await _frames(1)
		if as_r.solid_at(g.player.pos):
			as_in += 1
	g.space.vel = Vector2.ZERO
	# cut it through the middle (a band three cells wide across its grid): it drifts apart in two
	var as_cnt0: int = g.space.home_rocks().size()
	var as_mid: int = as_r.h / 2
	for as_j in range(as_mid - 1, as_mid + 2):
		for as_i in as_r.w:
			if as_r.cells[as_j * as_r.w + as_i] != 0:
				as_r.take(as_j * as_r.w + as_i)
	await _frames(20)
	var as_cnt1: int = g.space.home_rocks().size()
	var as_d0 := 0.0
	var as_other = null
	for as_a3 in g.space.home_rocks():
		if as_a3 != as_r and (as_other == null or (as_a3.pos - as_r.pos).length() < (as_other.pos - as_r.pos).length()):
			as_other = as_a3
	if as_other != null:
		as_d0 = (as_other.pos - as_r.pos).length()
	await _frames(120)
	var as_d1: float = 0.0 if as_other == null else (as_other.pos - as_r.pos).length()
	var as_saved = g.space.rocks_state(int(g.planet["index"]))
	var as_nsave: int = (as_saved as Array).size() if as_saved != null else -1
	# and back down
	g.player.pos = sx_up * (Defs.R_SPACE - 4.0)
	g.cam_c = g.player.pos
	var as_back := -1
	for as_k5 in 200:
		g.space.vel = -sx_up * 3.0
		await _frames(1)
		if not g.space.active:
			as_back = as_k5
			break
	await _frames(60)
	_ok("an asteroid: the view comes in close, you mine it, bump it and cut it in two",
		as_n0 >= 6 and as_kinds.size() >= 2 and as_zoom < 1.6 and not as_live and as_inv1 - as_inv0 >= 20 and as_c0 - as_c1 >= as_inv1 - as_inv0
			and as_in == 0 and as_cnt1 > as_cnt0 and as_d1 > as_d0 + 1.0 and as_nsave == g.space.home_rocks().size() and as_back >= 0,
		"%d rocks (%s); zoom by it %.2f (live planet %s); mined %d cells into the satchel (%d -> %d cells); inside it %d of 60 frames flying at it; cut through: %d -> %d rocks, the pieces %.1f -> %.1f apart; %d saved; back down after %d ticks" % [as_n0, str(as_kinds), as_zoom, as_live, as_inv1 - as_inv0, as_c0, as_c1, as_in, as_cnt0, as_cnt1, as_d0, as_d1, as_nsave, as_back])
	g.test_god = true

	# ---- the Wisp Skiff: forged, called, boarded, flown up into space and back, landed, left ----
	g.player.dead = false
	g.test_god = true
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	var sf_rec: Dictionary = {}
	for sf_r in g.recipes:
		if sf_r["id"] == "skiff":
			sf_rec = sf_r
	for sf_k in sf_rec.get("cost", {}):
		g.player.inv[int(sf_k)] += int(sf_rec["cost"][sf_k])
	var sf_forged: bool = not sf_rec.is_empty() and g.craft(sf_rec) and g.items.has("skiff")
	# (on a clear, level stretch: set down on a slope or loose ground, it once slid on after settling)
	var sf_st := _clear_stretch(int(fposmod(g.spawn_angle, TAU) / TAU * Defs.NS) + 40, 200, 70, 4)
	var sf_ang: float = (float(sf_st.x) + 100.5) / float(Defs.NS) * TAU
	_go(Vector2(cos(sf_ang), sin(sf_ang)) * (g.gpu.surf_at(sf_ang).x + 12.0))
	g.time = fposmod(sf_ang - g.spawn_angle + 1.1, TAU) / TAU * 25200.0
	await _frames(40)
	var sf_called: bool = g.call_skiff()
	var sf_sk = g.skiff
	var sf_settle := -1
	for sfk1 in 300:
		await _frames(1)
		if sf_sk.grounded and sf_sk.vel.length() < 0.5:
			sf_settle = sfk1
			break
	var sf_rest: Vector2 = sf_sk.pos
	await _frames(40)
	var sf_drift: float = sf_sk.pos.distance_to(sf_rest)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("skiff.png"))
	# ---- the cabin is a room: open air the riders sit in, that can be built in ----
	var sr_room := 0
	for sr_k in sf_sk.w * sf_sk.h:
		sr_room += sf_sk.room[sr_k]
	var sr_head := true             # (a mage's height of room over each seat)
	for sr_s in sf_sk.seat_cells:
		for sr_dy in 18:
			sr_head = sr_head and sf_sk.in_room(sr_s.x, sr_s.y - sr_dy) and sf_sk.at(sr_s.x, sr_s.y - sr_dy) == 0
	var sr_outline: int = sf_sk.outline.size()
	var sr_mass: float = sf_sk.mass
	var sr_c: Vector2i = sf_sk.seat_cells[0] + Vector2i(-2, -12)
	var sr_block: bool = sf_sk.place(sr_c.x, sr_c.y, Defs.PLANK)
	var sr_back: bool = sf_sk.place(sr_c.x + 1, sr_c.y, Defs.BRICK, true)
	var sr_hull: bool = sf_sk.place(sf_sk.w / 2, sf_sk.h - 3, Defs.PLANK)      # (into the hull: refused)
	var sr_same: bool = sf_sk.outline.size() == sr_outline and sf_sk.mass > sr_mass
	g.save_world(true)
	var sr_saved: bool = g.planet_state.has("skiff") and g.planet_state["skiff"].has("cells")
	var sr_copy = Skiff.make(sf_sk.design_seed)
	var sr_loaded: bool = sr_copy.load_cells(sf_sk.save_cells()) and sr_copy.at(sr_c.x, sr_c.y) == Defs.PLANK and sr_copy.bg[sr_c.y * sr_copy.w + sr_c.x + 1] == Defs.BRICK and sr_copy.made[sr_c.y * sr_copy.w + sr_c.x] == 1
	var sr_took: bool = sf_sk.remove(sr_c.x, sr_c.y) == Defs.PLANK and sf_sk.remove(sr_c.x + 1, sr_c.y, true) == Defs.BRICK
	_ok("the skiff's cabin is a room that can be built in (and is saved cell by cell)",
		sr_room > 300 and sr_head and sr_block and sr_back and not sr_hull and sr_same and sr_saved and sr_loaded and sr_took and sf_sk.outline.size() == sr_outline,
		"%d cells of room; headroom over the seats %s; a block built inside %s, a back wall %s, into the hull %s; outline the same (%d) %s; saved with the world %s; loaded back into a fresh skiff %s; taken out again %s" % [sr_room, sr_head, sr_block, sr_back, sr_hull, sr_outline, sr_same, sr_saved, sr_loaded, sr_took])
	# aboard
	g.player.pos = sf_sk.pos
	var sf_board: bool = g._skiff_interact(g.player) and g.player.aboard == sf_sk
	# up, holding cast with the cursor straight overhead, until out in space
	var sf_r0: float = sf_sk.pos.length()
	g.test_cast = true
	var sf_up := -1
	var sf_shot := false
	var sf_scale := []
	for sfk2 in 1500:
		# (a little to one side at first, so it climbs at a slant)
		g.test_aim = sf_sk.pos * 1.5 + g.basis_r(atan2(sf_sk.pos.y, sf_sk.pos.x)) * (300.0 if sfk2 < 120 else 0.0)
		await _frames(1)
		if not sf_shot and sf_sk.pos.length() > sf_r0 + 120.0:
			sf_shot = true
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("skiff_climb.png"))
		# drawn one cell to a pixel at every height (the ground's columns widen with height; the ship mustn't)
		if sfk2 % 40 == 0 and not g.space.active:
			sf_scale.append(snappedf(g.overlay._skiff_xf(sf_sk).y.length() * g.zoom, 0.01))
		if g.space.active:
			sf_up = sfk2
			break
	await _frames(90)
	var sf_far: float = sf_sk.pos.length() - Defs.R_SPACE
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("skiff_space.png"))
	# back: cursor on the planet until in the orbit band again, then let go and come down
	var sf_back := -1
	for sfk3 in 1500:
		g.test_aim = sf_sk.pos * 0.3
		await _frames(1)
		if not g.space.active:
			sf_back = sfk3
			break
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true          # (hands off it would hover: hold down to come in and land)
	var sf_land := -1
	var sf_vmax := 0.0
	for sfk4 in 1800:
		await _frames(1)
		if sf_sk.pos.length() < Defs.R_TOP:
			sf_vmax = maxf(sf_vmax, sf_sk.vel.length())
		if sf_sk.grounded and sf_sk.vel.length() < 0.5:
			sf_land = sfk4
			break
	g.test_down = false
	var sf_la: float = atan2(sf_sk.pos.y, sf_sk.pos.x)
	var sf_above: float = sf_sk.pos.length() - g.gpu.surf_at(sf_la).x
	var sf_with: bool = g.player.aboard == sf_sk and g.player.pos.distance_to(sf_sk.pos) < 30.0
	await _frames(20)
	var sf_out: bool = g._skiff_interact(g.player) and g.player.aboard == null
	await _frames(30)
	_ok("the Wisp Skiff: forged, called, boarded, flown into space and back, landed and left",
		sf_forged and sf_called and sf_settle >= 0 and sf_drift < 1.5 and sf_board and sf_up >= 0 and sf_back >= 0 and sf_land >= 0 and sf_with and sf_out and absf(sf_above) < 200.0 and sf_vmax < float(Skiff.CRUISE_HIGH) + 0.5 and sf_land > 40 and sf_scale.min() > 0.99 and sf_scale.max() < 1.01,
		"forged %s, called %s (%d x %d cells, %.0f mass); settled after %d ticks (then moved %.1f); aboard %s; out in space after %d ticks of flying up (from radius %.0f), %.0f past the band after 1.5 s more; back in the band after %d ticks; landed %d ticks later (fastest through the air %.1f a tick), %.0f above the ground line, you still aboard %s; stepped out %s; drawn cells per pixel while climbing %s" % [sf_forged, sf_called, sf_sk.w, sf_sk.h, sf_sk.mass, sf_settle, sf_drift, sf_board, sf_up, sf_r0, sf_far, sf_back, sf_land, sf_vmax, sf_above, sf_with, sf_out, str(sf_scale)])

	# ---- to another planet in the skiff: Cindrel is made while you fly, then you land on it ----
	g.player.pos = sf_sk.pos
	var tv_board: bool = g._skiff_interact(g.player) and g.player.aboard == sf_sk
	var tv_up: Vector2 = sf_sk.pos.normalized()
	sf_sk.pos = tv_up * (Defs.R_SPACE - 11.0)
	sf_sk.vel = tv_up * 6.0
	sf_sk.grounded = false
	g.test_cast = true
	var tv_in := -1
	for tvk1 in 200:
		g.test_aim = sf_sk.pos + sf_sk.pos.normalized() * 400.0
		await _frames(1)
		if g.space.active:
			tv_in = tvk1
			break
	# ---- the Prospector's Beam: the pilot mines an asteroid from aboard ----
	g.space._ensure_rocks(true)
	var bm_r = g.space.nearest_rock(sf_sk.pos, 1e9)
	var bm_got := -1
	var bm_inv0 := 0
	var bm_inv1 := 0
	if bm_r != null:
		bm_r.omega = 0.0
		bm_r.vel = Vector2.ZERO
		var bm_dir: Vector2 = (sf_sk.pos - bm_r.pos).normalized()
		var bm_at: Vector2 = bm_r.pos + bm_dir * (bm_r.reach() + 70.0)
		g.items["beam"] = true
		var bm_c0: int = bm_r.count()
		for bm_v in g.player.inv:
			bm_inv0 += int(bm_v)
		g.test_cast = false
		g.test_dig = true
		for bm_f in 150:
			sf_sk.pos = bm_at
			sf_sk.vel = Vector2.ZERO
			bm_r.vel = Vector2.ZERO
			g.test_aim = bm_r.pos + bm_dir * (bm_r.reach() * 0.4)
			await _frames(1)
			if bm_f == 100:
				g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("beam.png"))
		g.test_dig = false
		g.test_cast = true
		g.items.erase("beam")
		bm_got = bm_c0 - bm_r.count()
		for bm_v2 in g.player.inv:
			bm_inv1 += int(bm_v2)
	_ok("the Prospector's Beam mines an asteroid from the skiff", bm_got >= 30 and bm_inv1 - bm_inv0 >= 30,
		"%d cells taken from the rock, %d into the satchel" % [bm_got, bm_inv1 - bm_inv0])
	var tv_to: Vector2 = Defs.planet_pos(1) - Defs.planet_pos(0)
	# ---- first with no Core Drive: Cindrel is beyond the skiff's reach, wrapped in a storm belt that
	# throws you back (no invisible wall: the wind and lightning you see); then the drive is forged (a
	# Planet Core bound in star iron), and the belt lets you through ----
	var tv_reach0: int = g.skiff_reach()
	g.items["reach"] = 0
	var tv_space: float = float(Defs.make_planet(1)["radius"]) + Defs.ATMO + Defs.ORBIT_ROWS
	var tv_lim: float = tv_space + g.space.BELT_IN
	sf_sk.pos = tv_to - tv_to.normalized() * (tv_space + g.space.BELT_OUT + 300.0)
	sf_sk.vel = tv_to.normalized() * 30.0
	g.cam_c = sf_sk.pos
	var tv_lk_travel := false
	var tv_lk_min := 1e12
	g.space.belt_max = 0.0
	g.space.belt_hits = 0
	var tv_god0: bool = g.test_god
	g.test_god = true
	var tv_bk := 0.0
	var tv_bshot := false
	for tvl in 420:
		g.test_aim = Defs.planet_pos(1) - Defs.planet_pos(g.space.home) + Vector2(0.5, 0.5)
		await _frames(1)
		tv_lk_travel = tv_lk_travel or g.travelling or g.space.home != 0
		tv_lk_min = minf(tv_lk_min, (sf_sk.pos - tv_to).length())
		if not tv_bshot and g.space.belt > 0.35:
			tv_bshot = true
			await _frames(2)
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("storm_belt.png"))
		if tvl > 360:
			tv_bk = maxf(tv_bk, -sf_sk.vel.dot(tv_to.normalized()))
	g.test_god = tv_god0
	var tv_locked: bool = not tv_lk_travel and tv_lk_min > tv_lim and g.space.belt_max > 0.2
	g.tier = 4
	g.items["heart"] = true
	var tv_rec: Dictionary = {}
	for tv_r in g.recipes:
		if tv_r["id"] == "drive":
			tv_rec = tv_r
	for tv_k in tv_rec.get("cost", {}):
		g.player.inv[int(tv_k)] += int(tv_rec["cost"][tv_k])
	var tv_drive: bool = not tv_rec.is_empty() and g.craft(tv_rec) and g.skiff_reach() == 1
	_ok("without a Core Drive the skiff can't reach the next planet; with one it can", tv_locked and tv_drive,
		"held off Cindrel by its storm belt %s (closest %.0f from its centre, the belt's inner edge %.0f, deepest in it %.2f, %d lightning strikes, thrown back at up to %.1f a tick near the end, travel started %s); Core Drive forged %s (reach %d, was %d)" % [not tv_lk_travel, tv_lk_min, tv_lim, g.space.belt_max, g.space.belt_hits, tv_bk, tv_lk_travel, tv_drive, g.skiff_reach(), tv_reach0])
	# (most of the way there at once: the planet is made as you cover the rest)
	sf_sk.pos = tv_to * 0.7
	sf_sk.vel = tv_to.normalized() * 35.0
	g.cam_c = sf_sk.pos
	var tv_gap := 0
	var tv_gap_at := ""
	var tv_t0 := Time.get_ticks_usec()
	g.hitch_us = 0
	var tv_held := false
	var tv_shot := false
	var tv_arrive := -1
	var tv_back := -1
	var tv_draw := {"pre": 0, "draw": 0}
	var tv_pre := func() -> void:
		tv_draw["pre"] = Time.get_ticks_usec()
	var tv_post := func() -> void:
		tv_draw["draw"] = Time.get_ticks_usec() - int(tv_draw["pre"])
	RenderingServer.frame_pre_draw.connect(tv_pre)
	RenderingServer.frame_post_draw.connect(tv_post)
	for tvk2 in 2400:
		# (Cindrel's centre; nudged off zero, which would mean "follow the mouse")
		g.test_aim = Defs.planet_pos(1) - Defs.planet_pos(g.space.home) + Vector2(0.5, 0.5)
		await _frames(1)
		var tv_now := Time.get_ticks_usec()
		if tv_now - tv_t0 > 150000:
			var tv_big := []
			for tv_sec in g.prof:
				if float(g.prof[tv_sec][3]) > 30000.0:
					tv_big.append("%s %.0f" % [tv_sec, float(g.prof[tv_sec][3]) / 1000.0])
			print("[travel] a %.0f ms frame at tick %d (%s): %s; process %.0f ms, physics %.0f ms, GPU wait %.0f ms, game's own %.0f ms, drawing %.0f ms, live %s, space %s" % [(tv_now - tv_t0) / 1000.0, tvk2,
				"arrived" if tv_arrive >= 0 else "on the way", ", ".join(tv_big), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, g.gpu.wait_us / 1000.0, g.hitch_us / 1000.0, float(tv_draw["draw"]) / 1000.0, str(g.space.live), str(g.space.active)])
			g.hitch_us = 0
		g.prof_reset()
		if tv_now - tv_t0 > tv_gap:
			tv_gap = tv_now - tv_t0
			tv_gap_at = "tick %d, %s, made %.2f" % [tvk2, "travelling" if g.travelling else ("arrived %d ticks before" % (tvk2 - tv_arrive) if tv_arrive >= 0 else "before arriving"), g.travel_progress]
		tv_t0 = tv_now
		if g.travelling and sf_sk.vel.length() < 1.0:
			tv_held = true
		if tv_arrive < 0 and g.space.home == 1:
			tv_arrive = tvk2
		if not tv_shot and tv_arrive >= 0 and g.zoom < 12.0:
			tv_shot = true
			g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("arrival.png"))
			tv_t0 = Time.get_ticks_usec()       # (the picture's own saving isn't the game's frame)
		if tv_arrive >= 0 and not g.space.active:
			tv_back = tvk2
			break
	RenderingServer.frame_pre_draw.disconnect(tv_pre)
	RenderingServer.frame_post_draw.disconnect(tv_post)
	g.test_cast = false
	g.test_aim = Vector2.ZERO
	g.test_down = true
	var tv_land := -1
	for tvk3 in 1800:
		await _frames(1)
		if sf_sk.grounded and sf_sk.vel.length() < 0.5:
			tv_land = tvk3
			break
	g.test_down = false
	await _frames(30)
	var tv_la: float = atan2(sf_sk.pos.y, sf_sk.pos.x)
	var tv_above: float = sf_sk.pos.length() - g.gpu.surf_at(tv_la).x
	var tv_with: bool = g.player.aboard == sf_sk and g.player.pos.distance_to(sf_sk.pos) < 30.0
	var tv_saved: bool = FileAccess.file_exists(g._world_path(0)) and FileAccess.file_exists(g._world_path(1))
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("new_planet.png"))
	_ok("the skiff carries you to another planet, made while you fly, and you land on it",
		tv_board and tv_in >= 0 and tv_arrive >= 0 and tv_back >= 0 and tv_land >= 0 and int(g.planet["index"]) == 1 and absf(Defs.RS0 - float(g.planet["radius"])) < 0.5 and tv_with and absf(tv_above) < 200.0 and tv_saved and tv_gap < 250000,
		"aboard %s; out after %d ticks; %s made and moved over to after %d ticks (held off while it was made: %s; longest frame %.0f ms at %s); in its orbit band %d ticks later, landed %d ticks after that, %.0f above its ground line (radius %.0f), you aboard %s; both worlds saved %s" % [tv_board, tv_in, g.planet["name"], tv_arrive, tv_held, tv_gap / 1000.0, tv_gap_at, tv_back - tv_arrive, tv_land, tv_above, Defs.RS0, tv_with, tv_saved])

	await _test_galaxy()

	# ---- a planet of another size: Fenhollow is laid out and generated to fit ----
	var sp_t := Time.get_ticks_msec()
	g._enter_planet(4)
	var sp_ms := Time.get_ticks_msec() - sp_t
	await _frames(60)
	var sp_a: float = atan2(g.player.pos.y, g.player.pos.x)
	var sp_off: float = g.player.pos.length() - g.gpu.surf_at(sp_a).x
	_ok("a planet of another size is laid out and generated to fit", absf(Defs.RS0 - float(g.planet["radius"])) < 0.5 and Defs.RS0 < float(Defs.make_planet(0)["radius"]) and absf(sp_off) < 40.0 and g.builds.infos.size() >= 5,
		"%s: radius %.0f, %d surface columns, %d shells (%.1f M cells); generated in %d ms; you stand %.1f from the surface; %d structures" % [g.planet["name"], Defs.RS0, Defs.NS, Defs.NSH, Defs.total_cells() / 1000000.0, sp_ms, sp_off, g.builds.infos.size()])
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("small_planet.png"))

	await _test_far_biomes()
	await _test_worlds()
	await _test_bench()

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
		for cr_f in 170:
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
		cr_none.is_empty() and cr_bad.is_empty(), "%d creatures; places without any: %s; %s" % [cr_ids.size(), str(cr_none), "; ".join(cr_rows)])

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
	for ec_f9 in 300:
		await _frames(1)
		if ec_rf.dead:
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
	ec_stand.call(-120.0)
	await _frames(20)
	var ec_rain0: float = g.rain
	var ec_rt0: float = g.rain_target
	g.rain = 1.0
	g.rain_target = 1.0
	var ec_deer2 = ec_spawn.call("c_deer", 10.0)
	var ec_shelter := false
	for ec_f11 in 60:
		await _frames(1)
		ec_shelter = ec_shelter or (ec_deer2.storm and ec_deer2.doing == "shelter")
	g.rain = ec_rain0
	g.rain_target = ec_rt0
	ec_rows.append("%sa deer in the rain went for shelter %s" % ["" if ec_shelter else "(!) ", ec_shelter])
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
	var fg_far: Vector2 = fg_up * (fg_surf - 90.0) + fg_side * 70.0
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

## A busy scene, uncapped (user, 21 Nov: the performance pass): two dozen foes hunting you, a fireball every
## 20 frames, digging all the while, sand poured from above, rain; where the frame's time goes.
func _test_bench() -> void:
	var bn_god0: bool = g.test_god
	var bn_wild0: bool = g.test_no_wild
	var bn_pos0: Vector2 = g.player.pos
	g.test_god = true
	g.test_no_wild = true
	# (well away from where you arrived: its fires, pit and sand would spoil the wild-life checks set up there)
	var bn_st := _clear_stretch(Build.cell_of(start_pos).x + 1400, 200, 60)
	var bn_a: float = (float(bn_st.x) + 100.5) / float(Defs.NS) * TAU
	var bn_up := Vector2(cos(bn_a), sin(bn_a))
	var bn_side: Vector2 = g.basis_r(bn_a)
	var bn_ground: float = g.gpu.surf_at(bn_a).x
	_go(bn_up * (bn_ground + 14.0))
	await _frames(40)
	var bn_kinds := ["c_frostwolf", "c_boar", "c_hyena", "c_jackal", "c_ram", "c_deer", "skeleton", "skeleton", "slime", "bat"]
	var bn_foes := []
	for bn_k in 24:
		var bn_t: String = bn_kinds[bn_k % bn_kinds.size()]
		var bn_off := (40.0 + 7.0 * float(bn_k)) * (1.0 if bn_k % 2 == 0 else -1.0)
		var bn_p: Vector2 = g.player.pos + bn_side * bn_off + bn_up * (30.0 if bn_t == "bat" else 6.0)
		var bn_e = g.spawn_enemy(bn_t, g.free_spot(bn_p, 14.0, 14.0, 20))
		bn_e.provoked = true
		bn_e.alert_t = 600
		bn_e.seen_pos = g.player.pos
		bn_foes.append(bn_e)
	var bn_rain0: float = g.rain
	g.rain = 1.0
	g.rain_target = 1.0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(g.get_viewport().get_viewport_rid(), true)
	await _frames(20)
	g.prof_reset()
	g.hitch_us = 0
	var bn_times := []
	var bn_prev := {}
	var bn_shown := 0
	var bn_t0 := Time.get_ticks_usec()
	for bn_f in 600:
		g.player.hp = g.player.max_hp
		if bn_f % 20 == 0:
			var bn_dir: Vector2 = (bn_side * (1.0 if (bn_f / 20) % 2 == 0 else -1.0) + bn_up * 0.15).normalized()
			g._spawn_proj("fireball", g.player.pos + bn_up * 4.0, bn_dir * 3.9, "player")
		# digging beside you all the while
		g.brushes.append([g.player.pos + bn_side * 18.0 * (1.0 if (bn_f / 90) % 2 == 0 else -1.0) - bn_up * 6.0, 7.5, 1, 0, 2, 0.0, 0, 0])
		if bn_f % 150 == 0:
			# sand poured from above
			var bn_c: Vector2i = Build.cell_of(g.player.pos + bn_up * 60.0 + bn_side * 30.0)
			var bn_d := PackedInt32Array()
			bn_d.resize(30 * 14)
			bn_d.fill(Defs.SAND | 0xFF00)
			g.stamps.append({"x0": bn_c.x, "y0": bn_c.y, "w": 30, "h": 14, "data": bn_d})
		await _frames(1)
		var bn_now := Time.get_ticks_usec()
		bn_times.append(bn_now - bn_t0)
		if bn_now - bn_t0 > 50000 and bn_shown < 14:
			# a slow frame: the parts whose worst grew in it
			bn_shown += 1
			var bn_grew := []
			for bn_s2 in g.prof:
				var bn_m := float(g.prof[bn_s2][4])
				if bn_m > 3000.0:
					bn_grew.append("%s %.1f" % [bn_s2, bn_m / 1000.0])
			var bn_vp: RID = g.get_viewport().get_viewport_rid()
			print("[bench] frame %d: %.0f ms (%s; process %.1f ms, the screen's drawing: CPU %.1f ms, GPU %.1f ms, set-up %.1f ms)" % [bn_f, (bn_now - bn_t0) / 1000.0, ", ".join(bn_grew),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, RenderingServer.viewport_get_measured_render_time_cpu(bn_vp),
				RenderingServer.viewport_get_measured_render_time_gpu(bn_vp), RenderingServer.get_frame_setup_time_cpu()])
		for bn_s3 in g.prof:
			bn_prev[bn_s3] = float(g.prof[bn_s3][3])
		bn_t0 = bn_now
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	bn_times.sort()
	var bn_sum := 0
	for bn_v in bn_times:
		bn_sum += int(bn_v)
	var bn_avg := float(bn_sum) / bn_times.size() / 1000.0
	var bn_p95 := float(bn_times[int(bn_times.size() * 0.95)]) / 1000.0
	var bn_worst := float(bn_times[-1]) / 1000.0
	var bn_alive := 0
	for bn_e2 in bn_foes:
		if not bn_e2.dead and g.enemies.has(bn_e2):
			bn_alive += 1
	var bn_txt: String = g.prof_text(20, "; ")
	# (and the worst single frame of each part)
	var bn_mx := []
	for bn_s in g.prof:
		bn_mx.append([float(g.prof[bn_s][3]), bn_s])
	bn_mx.sort()
	bn_mx.reverse()
	var bn_mxt := []
	for bn_i in mini(12, bn_mx.size()):
		bn_mxt.append("%s %.1f" % [bn_mx[bn_i][1], float(bn_mx[bn_i][0]) / 1000.0])
	print("[bench] the worst frame of each part (ms): " + "; ".join(bn_mxt))
	var bn_hist := [0, 0, 0, 0, 0]
	for bn_v2 in bn_times:
		var bn_ms := float(bn_v2) / 1000.0
		bn_hist[0 if bn_ms < 8.0 else (1 if bn_ms < 16.7 else (2 if bn_ms < 33.0 else (3 if bn_ms < 66.0 else 4)))] += 1
	print("[bench] frames under 8 ms %d, 8-16.7 %d, 16.7-33 %d, 33-66 %d, over 66 %d" % bn_hist)
	print("[bench] %.2f ms a frame on average, 95%% under %.2f, the worst %.1f (the game's own %.1f); foes %d, particles %d, vfx %d; %s" % [bn_avg, bn_p95, bn_worst,
		g.hitch_us / 1000.0, g.enemies.size(), g.parts.size(), g.vfx.count(), bn_txt])
	_ok("a busy scene holds 60 fps with room to spare", bn_avg < 16.7 and bn_p95 < 25.0,
		"%.2f ms on average, 95%% of frames under %.2f ms, the worst %.1f ms; %d of 24 foes left; %s" % [bn_avg, bn_p95, bn_worst, bn_alive, bn_txt])
	for bn_e3 in bn_foes:
		g.enemies.erase(bn_e3)
	g.projs.clear()
	RenderingServer.viewport_set_measure_render_time(g.get_viewport().get_viewport_rid(), false)
	g.rain = bn_rain0
	g.rain_target = bn_rain0
	_go(bn_pos0)
	await _frames(60)
	g.test_god = bn_god0
	g.test_no_wild = bn_wild0

## The first frames after a planet is entered (user, 21 Nov: "a hitch on start up"): any frame over 40 ms is
## printed as `[<label>] frame N: T ms` with what took the time (the game's sections over 8 ms, the game's
## process, the drawing).
func _trace_frames(label: String, n: int) -> void:
	var tf_draw := {"pre": 0, "draw": 0}
	var tf_pre := func() -> void:
		tf_draw["pre"] = Time.get_ticks_usec()
	var tf_post := func() -> void:
		tf_draw["draw"] = Time.get_ticks_usec() - int(tf_draw["pre"])
	RenderingServer.frame_pre_draw.connect(tf_pre)
	RenderingServer.frame_post_draw.connect(tf_post)
	g.prof_reset()
	var tf_t0 := Time.get_ticks_usec()
	var tf_worst := 0
	var tf_big := 0
	for tf_k in n:
		await _frames(1)
		var tf_now := Time.get_ticks_usec()
		var tf_dt := tf_now - tf_t0
		tf_t0 = tf_now
		tf_worst = maxi(tf_worst, tf_dt)
		if tf_dt > 40000:
			tf_big += 1
			var tf_secs := []
			for tf_s in g.prof:
				if float(g.prof[tf_s][3]) > 8000.0:
					tf_secs.append("%s %.0f" % [tf_s, float(g.prof[tf_s][3]) / 1000.0])
			print("[%s] frame %d: %.0f ms (%s; process %.0f ms, drawing %.0f ms)" % [label, tf_k, tf_dt / 1000.0, ", ".join(tf_secs),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, float(tf_draw["draw"]) / 1000.0])
		g.prof_reset()
	RenderingServer.frame_pre_draw.disconnect(tf_pre)
	RenderingServer.frame_post_draw.disconnect(tf_post)
	print("[%s] %d frames: the slowest %.0f ms, %d over 40 ms" % [label, n, tf_worst / 1000.0, tf_big])

## A modest start (user, 21 Nov): no levitation until it's forged (holding jump in the air you fall), then
## you float; the first spell is the Wisp Mote, and Spark Bolt and Levitation are forged.
func _test_start() -> void:
	var st_god0: bool = g.test_god
	g.test_god = true
	var st_orig: Vector2 = g.player.pos
	var st_up: Vector2 = st_orig.normalized()
	# (high in open sky over the ground here: nothing to land on in the second or so it takes)
	var st_sky: Vector2 = st_up * (g.gpu.surf_at(atan2(st_up.y, st_up.x)).x + 110.0)
	var st_lev0: bool = g.items.has("levitate")
	g.items.erase("levitate")
	g.state = "play"
	# (open air: the full run's earlier checks leave ledges and courses up in the sky round here)
	for st_h in [110.0, 70.0, 150.0, 90.0, 130.0, 60.0]:
		st_sky = st_up * (g.gpu.surf_at(atan2(st_up.y, st_up.x)).x + st_h)
		_go(st_sky)
		await _frames(3)
		if not g.player.on_ground and g.player.pos.length() < st_sky.length() - 0.2:
			break
	_go(st_sky)
	g.test_jump = true
	var st_floated := 0
	for st_f in 50:
		g.player.mana = g.player.max_mana
		await _frames(1)
		if g.player.floating:
			st_floated += 1
	var st_fell: float = (st_sky).length() - g.player.pos.length()
	g.test_jump = false
	g.items["levitate"] = true
	_go(st_sky)
	g.test_jump = true
	var st_floated2 := 0
	for st_f2 in 50:
		g.player.mana = g.player.max_mana
		await _frames(1)
		if g.player.floating:
			st_floated2 += 1
	var st_rose: float = g.player.pos.length() - (st_sky).length()
	g.test_jump = false
	if not st_lev0:
		g.items.erase("levitate")
	var st_recipes := {}
	for st_r in g.recipes:
		st_recipes[String(st_r["id"])] = st_r
	var st_ok: bool = st_floated == 0 and st_fell > 8.0 and st_floated2 > 20 and st_rose > -8.0 and Defs.SPELLS.has("mote") \
		and st_recipes.has("spark") and st_recipes.has("levitate") and Defs.SPELL_ORDER[0] == "mote"
	_ok("a modest start: no levitating until it's forged, a Wisp Mote first, Spark Bolt and Levitation at the forge", st_ok,
		"without it: floated %d frames, fell %.0f cells; with it: floated %d frames, rose %.0f; recipes spark %s, levitate %s" % [
		st_floated, st_fell, st_floated2, st_rose, str(st_recipes.has("spark")), str(st_recipes.has("levitate"))])
	g.test_god = st_god0
	_go(st_orig)
	await _frames(20)

## Recipes you discover (user, 21 Nov): a journey knows a handful; an unknown one can't be forged and shows in
## the recipe book with where it's learned; a first find teaches its plain uses; chests, keepers and hoards teach
## the rest; what you know is saved (a picture of the book: saves/shots/forge_book.png).
func _test_recipes() -> void:
	var rc_inv: PackedInt32Array = g.player.inv.duplicate()
	var rc_learned: Dictionary = g.learned.duplicate()
	var rc_items: Dictionary = g.items.duplicate(true)
	var rc_rows := []
	var rc_ok := true
	g.player.inv.fill(0)
	g.learned = {}
	await _frames(70)
	var rc_plank: bool = g.knows(g.recipe_by_id("plank"))
	var rc_glass0: bool = g.knows(g.recipe_by_id("sandstone"))
	# an unknown recipe can't be forged, even with all it costs (sandstone: glass is fired in a kiln now)
	var rc_glass_r: Dictionary = g.recipe_by_id("sandstone")
	for rk in rc_glass_r["cost"]:
		g.player.inv[int(rk)] = int(rc_glass_r["cost"][rk]) + 5
	var rc_cant: bool = not g.craft(rc_glass_r)
	var rc_ok1: bool = rc_plank and not rc_glass0 and rc_cant
	rc_rows.append("%sstart: planks known %s, sandstone known %s, sandstone forged while unknown %s" % ["" if rc_ok1 else "(!) ", rc_plank, rc_glass0, not rc_cant])
	rc_ok = rc_ok and rc_ok1
	# a first find: sand teaches sandstone
	g.player.inv[Defs.SAND] = 6
	await _frames(70)
	var rc_ok2: bool = g.knows(rc_glass_r)
	rc_rows.append("%sfirst sand taught sandstone %s" % ["" if rc_ok2 else "(!) ", g.knows(rc_glass_r)])
	rc_ok = rc_ok and rc_ok2
	# a chest's recipe scroll, a boss's hoard, a keeper's sale
	var rc_n0: int = g.learned.size()
	var rc_chest: bool = g._chest_recipe(1)
	var rc_hoard: bool = g._hoard_recipe()
	var rc_shop: Array = g.shop_recipes("smithy")
	var rc_skiff := false
	for rr in rc_shop:
		if String(rr["id"]) == "skiff":
			rc_skiff = true
	g.towns.grant({"recipe": "skiff"})
	var rc_ok3: bool = rc_chest and rc_hoard and rc_skiff and g.knows(g.recipe_by_id("skiff")) and g.learned.size() >= rc_n0 + 3
	rc_rows.append("%sa chest's scroll %s, a hoard's %s, the skiff sold at a smithy %s and bought %s" % ["" if rc_ok3 else "(!) ", rc_chest, rc_hoard, rc_skiff, g.knows(g.recipe_by_id("skiff"))])
	rc_ok = rc_ok and rc_ok3
	# every recipe has a way to be learned, and the book says where
	var rc_noway := []
	for rr2 in g.recipes:
		var rl: Dictionary = Defs.learn_of(rr2)
		if not (rl.get("start", false) or rl.has("find") or rl.has("scroll") or rl.has("shop") or rl.get("hoard", false)):
			rc_noway.append(String(rr2["id"]))
		elif not rl.get("start", false) and Defs.learn_hint(rr2) == "":
			rc_noway.append(String(rr2["id"]))
	rc_rows.append("%severy recipe has a way to be learned (%s)" % ["" if rc_noway.is_empty() else "(!) ", ", ".join(rc_noway) if not rc_noway.is_empty() else "all"])
	rc_ok = rc_ok and rc_noway.is_empty()
	# the recipe book
	g.state = "forge"
	g.ui.show_forge(true)
	await _frames(8)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("forge_book.png"))
	var rc_book: bool = g.ui._book_head != null and is_instance_valid(g.ui._book_head)
	g.ui.hide_forge()
	g.state = "play"
	# saved with the journey
	g.save_game()
	var rc_saved = JSON.parse_string(FileAccess.get_file_as_string(g._save_path()))
	var rc_sl: Array = rc_saved.get("learned", []) if typeof(rc_saved) == TYPE_DICTIONARY else []
	var rc_ok4: bool = rc_book and rc_sl.has("sandstone") and rc_sl.has("skiff") and not rc_sl.has("plank")
	rc_rows.append("%sthe book shows %s; saved: %d learned (sandstone %s, skiff %s)" % ["" if rc_ok4 else "(!) ", rc_book, rc_sl.size(), rc_sl.has("sandstone"), rc_sl.has("skiff")])
	rc_ok = rc_ok and rc_ok4
	g.player.inv = rc_inv
	g.learned = rc_learned
	g.items = rc_items
	g.save_game()
	_ok("recipes are learned: a handful at first, then first finds, chest scrolls, keepers and hoards; the book shows the rest", rc_ok, "; ".join(rc_rows))

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
	for wd_l in g.builds.lair_list:
		wd_lb.append(wd_l["biome"])
	var wd_want: Array = wd_pl.get("guardians", [])
	var wd_match := true
	for wd_b3 in wd_lb:
		wd_match = wd_match and wd_want.has(wd_b3)
	var wd_made_ok: bool = g.builds.infos.size() >= 12 and wd_match and wd_lb.size() >= wd_want.size() - 1 and wd_lb.size() >= 1
	_ok("a new game's planet is made from its own seed, with guardians only where it says", wd_made_ok,
		"%s (%s, radius %.0f): %s; %d structures; guardians wanted %s, lairs %s (no room: %s); made in %d ms (%s)" % [wd_pl["name"], wd_pl["kind"], float(wd_pl["radius"]),
		wd_pl["desc"], g.builds.infos.size(), str(wd_want), str(wd_lb), str(g.builds.lair_why), wd_ms, str(g.gen_times)])
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
	var fo_cost: Dictionary = {}
	for fo_rec in g.recipes:
		if fo_rec["id"] == "drive":
			fo_cost = fo_rec["cost"]
	_ok("each kind of planet has its own ore: Fire Opal in Cindrel's ground, wanted by its Core Drive", fo_n >= 20 and int(fo_cost.get(Defs.FIREOPAL, 0)) == Defs.DRIVE_ORE,
		"%d Fire Opal cells in %d read under you; the Core Drive here costs %s" % [fo_n, fo_cells, str(fo_cost)])
	g._enter_planet(2)
	g.ui.title.visible = false
	await _frames(60)
	# the sanctum is under the water
	var fb_wet := "no lair"
	for fb_l in g.builds.lair_list:
		if fb_l["biome"] == "ocean":
			var fb_p: Vector2 = fb_l["pos"]
			_go(fb_p + fb_p.normalized() * 30.0)
			await _frames(20)
			fb_wet = "water over its floor: %s" % (Defs.KIND[g.type_at(fb_p + fb_p.normalized() * 12.0)] == Defs.K_LIQUID)
	await _test_guardians(["ocean"])
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
				dp_col = dp_c
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

## The guardians' lairs dressed as places (lairs.gd; user, 21 Nov: "make the boss arenas feel waaay more
## epic"): each has banners, a background of colonnade, set and statue, and its sure chest; pictures of
## each, the whole blueprint (lair_<biome>_bp.png) and in the game at midday from the gate, the middle and
## the dais (lair_<biome>_gate/_mid/_dais.png)
func _test_lairs() -> void:
	var lr_rows := []
	var lr_ok := 0
	var lr_n := 0
	var lr_dir: String = g._real_save_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(lr_dir)
	var lr_back: Vector2 = g.player.pos
	var lr_god0: bool = g.test_god
	var lr_time0: float = g.time
	g.test_god = true
	for lr_l in g.builds.lair_list:
		var lr_bio: String = lr_l["biome"]
		lr_n += 1
		var lr_info: Dictionary = {}
		for lr_in in g.builds.infos:
			if int(lr_in["x0"]) == int(lr_l.get("bx0", -1)) and (lr_info.is_empty() or int(lr_in["w"]) > int(lr_info["w"])):
				lr_info = lr_in
		if lr_info.is_empty() or (lr_info.get("data", PackedInt32Array()) as PackedInt32Array).is_empty():
			lr_rows.append("%s: no blueprint" % lr_bio)
			continue
		var lr_dat: PackedInt32Array = lr_info["data"]
		var lr_ban := 0
		var lr_back_cells := 0
		var lr_natural := 0
		var lr_plant := 0
		for lr_v in lr_dat:
			if (lr_v & 0x8000000) == 0 and (lr_v & 0x100000) != 0 and ((lr_v >> 8) & 255) != 0:
				lr_plant += 1
			var lr_f: int = lr_v & 255
			var lr_g: int = (lr_v >> 8) & 255
			if lr_g == Defs.DECOR:
				lr_ban += 1
			elif lr_g != 0 and lr_g != 255 and (lr_f == 0 or lr_f == Defs.WATER) and (lr_v & 0x40000) != 0:
				lr_back_cells += 1
			if lr_f != 255 and (lr_v & 0x8000000) == 0 and (lr_v & 0x80000) != 0:
				lr_natural += 1
		var lr_chests: int = (lr_info.get("chests", []) as Array).size()
		_bp_image(lr_info).save_png(lr_dir.path_join("lair_%s_bp.png" % lr_bio))
		# in the game: from the middle, and either end
		var lr_at: Vector2 = lr_l["pos"]
		var lr_a := atan2(lr_at.y, lr_at.x)
		var lr_side: Vector2 = g.basis_r(lr_a)
		g.time = g.towns.time_for_hour(lr_at, 12.5)
		g.rain = 0.0
		g.rain_target = 0.0
		var lr_made := 0
		if lr_plant > 0:
			# (as it was made, before anyone came near: plant cells, how many are at the edge of falling,
			# and how many of the blueprint's plant cells went in without their plant id)
			var lr_r0: Dictionary = g.gpu.read_rect(int(lr_info["x0"]), int(lr_info["y0"]), int(lr_info["w"]), int(lr_info["h"]),
				int(lr_info.get("ax", lr_info["x0"])), int(lr_info.get("aw", lr_info["w"])))
			var lr_bg0: PackedInt32Array = lr_r0["bg"]
			var lr_fg0: PackedInt32Array = lr_r0["fg"]
			var lr_n0 := 0
			var lr_hi := 0
			var lr_mx := 0
			var lr_lost := 0
			var lr_cov := 0
			for lr_q in mini(lr_bg0.size(), lr_dat.size()):
				var lr_bq: int = lr_bg0[lr_q]
				var lr_dq: int = lr_dat[lr_q]
				var lr_isp: bool = (lr_dq & 0x8000000) == 0 and (lr_dq & 0x100000) != 0 and ((lr_dq >> 8) & 255) != 0
				if lr_isp and (lr_bq & 0x80000000) == 0:
					lr_lost += 1
				if (lr_bq & 0x80000000) != 0 and (lr_bq & 255) != 0:
					lr_n0 += 1
					var lr_sq := (lr_bq >> 8) & 63
					lr_mx = maxi(lr_mx, lr_sq)
					if lr_sq >= 62:
						lr_hi += 1
					if lr_isp and (lr_fg0[lr_q] & 255) != 0:
						lr_cov += 1
			lr_made = lr_n0
			print("[lairplants] %s: %d plant cells, %d at 62, support up to %d, %d lost their id, %d behind something in front" % [lr_bio, lr_n0, lr_hi, lr_mx, lr_lost, lr_cov])
		for lr_k in 3:
			var lr_off: float = [0.0, -1.0, 1.0][lr_k] * (float(lr_l["arena"]) + (10.0 if lr_l.get("deep", false) else 70.0))
			var lr_p: Vector2 = lr_at + lr_side * lr_off
			_go(lr_p.normalized() * (lr_at.length() + 30.0))
			await _frames(45)
			g.get_viewport().get_texture().get_image().save_png(lr_dir.path_join("lair_%s_%s.png" % [lr_bio, ["mid", "a", "b"][lr_k]]))
		# its trees and giant mushrooms are living plants: still standing after you've been about (they
		# were built back walls once, and broke apart)
		var lr_live := -1
		if lr_plant > 0:
			_go(lr_at.normalized() * (lr_at.length() + 30.0))
			await _frames(240)
			var lr_rr: Dictionary = g.gpu.read_rect(int(lr_info["x0"]), int(lr_info["y0"]), int(lr_info["w"]), int(lr_info["h"]),
				int(lr_info.get("ax", lr_info["x0"])), int(lr_info.get("aw", lr_info["w"])))
			lr_live = 0
			for lr_bv in lr_rr["bg"]:
				if (int(lr_bv) & 0x80000000) != 0 and (int(lr_bv) & 255) != 0:
					lr_live += 1
		var lr_good := lr_ban >= 40 and lr_back_cells >= 1500 and lr_chests >= 1 and (lr_plant == 0 or (lr_made >= int(lr_plant * 0.85) and lr_live >= int(lr_made * 0.98)))
		if lr_good:
			lr_ok += 1
		lr_rows.append("%s%s: %d banner cells, %d background cells, %d natural rock, %d chests, %dx%d, plants %d, %d made -> %d standing" % [lr_bio, " (underground)" if lr_l.get("deep", false) else "",
			lr_ban, lr_back_cells, lr_natural, lr_chests, int(lr_info["w"]), int(lr_info["h"]), lr_plant, lr_made, lr_live])
	g.time = lr_time0
	g.test_god = lr_god0
	_go(lr_back)
	await _frames(20)
	_ok("every guardian's lair is dressed: a gate, banners, its set, a statue, its chest", lr_n > 0 and lr_ok == lr_n,
		"%d lairs; %s; no room: %s" % [lr_n, "; ".join(lr_rows), str(g.builds.lair_why)])


## the biome guardians (its own function so it can run alone: see `only`)
var only_now := ""
func _test_guardians(only_biomes := []) -> void:
	# ---- the biome guardians: each waits in its lair, wakes, fights with its moves, falls, gives its relic ----
	var gd_items0: Dictionary = g.items.duplicate()
	var gd_hp0: float = g.max_hp
	var gd_god0: bool = g.test_god
	var gd_back: Vector2 = g.player.pos
	g.test_god = true
	g.test_calm = false
	var gd_rows := []
	var gd_ok := 0
	var gd_lairs: Array = []
	for gd_l0 in g.builds.lair_list:
		if only_biomes.is_empty() or only_biomes.has(gd_l0["biome"]):
			gd_lairs.append(gd_l0)
	for gd_l in gd_lairs:
		var gd_bio: String = gd_l["biome"]
		var gd_e = null
		for gd_en in g.enemies:
			if gd_en.boss and gd_en.d.has("def") and gd_en.d["biome"] == gd_bio and not gd_en.dead:
				gd_e = gd_en
		if gd_e == null:
			gd_rows.append("%s: no guardian" % gd_bio)
			continue
		var gd_at: Vector2 = gd_l["pos"]
		var gd_side: Vector2 = g.basis_r(atan2(gd_at.y, gd_at.x))
		_go(gd_at + gd_side * 50.0 + gd_at.normalized() * 12.0)
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
		if gd_awake and gd_moves >= 1 and gd_got and gd_dead and gd_up < (95.0 if gd_flies else 70.0) and gd_out < 14.0 and gd_walk > 40.0:
			gd_ok += 1
		gd_rows.append("%s%s: awake %s, %d moves, relic %s, highest %.0f, past its lair %.0f, moved %.0f" % [gd_bio, " (underground)" if gd_l.get("deep", false) else "", gd_awake, gd_moves, gd_got,
			gd_up, gd_out, gd_walk])
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
		_ok("each biome has a guardian in its lair that wakes, fights and gives up its relic", gd_lairs.size() >= 8 and gd_ok == gd_lairs.size(),
			"%d lairs; %s; no room: %s" % [gd_lairs.size(), "; ".join(gd_rows), str(g.builds.lair_why)])
	else:
		_ok("%s: the %s guardian waits in its lair, wakes, fights and gives up its relic" % [g.planet["name"], " and ".join(only_biomes)],
			gd_lairs.size() == only_biomes.size() and gd_ok == gd_lairs.size(),
			"%s; no room: %s" % ["; ".join(gd_rows), str(g.builds.lair_why)])

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

func _sha(d: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(d)
	return h.finish().hex_encode()

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

## Infinite space (galaxy.gd, space.gd; user, 22 Nov): the galaxy's maths (the spiral of systems, the
## first system where it always was), then out in the skiff: the Starsail runs it up to speed away from
## every planet, space's origin follows (`_shift`) so you stay near (0, 0) however far out, the sectors
## round you stream in with their asteroid fields; a rock mined in one is kept as it was when you leave
## and come back; a comet keeps to its loop; a nebula tints the view; the map charts it all and holds a
## waypoint; what you've charted is saved; and back home, space's origin is home again and you land.
## Pictures: galaxy_sail.png, galaxy_field.png, galaxy_comet.png, galaxy_nebula.png, galaxy_map.png,
## galaxy_map_far.png.
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
					for pk in Defs.SYSTEM.size():
						if Defs.g_rel(Defs.planet_g(pr * Defs.SYSTEM.size() + pk), PackedFloat64Array([s2x, s2y])).length() < 80000.0:
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
		for a3 in g.space.rocks:
			if not a3.orbit.is_empty():
				cm = a3
		if cm != null:
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
					for pk2 in Defs.SYSTEM.size():
						if Defs.g_rel(Defs.planet_g(pr2 * Defs.SYSTEM.size() + pk2), PackedFloat64Array([tx, ty])).length() < 80000.0:
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

func _shot(fname: String) -> void:
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join(fname))

