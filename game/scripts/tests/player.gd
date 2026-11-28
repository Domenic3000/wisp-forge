extends "res://scripts/tests/towns.gd"
## Checks of the mage and the interface: gear, hazards, spell effects, the UI, speech, the start, recipes, the quest, cores. (Part of the chain of test files: see tests.gd.)

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
	g.player.inv[Defs.VOIDESS] = 0
	# hidden: all but the first piece of each ore, until it's found
	var ge_hid := 0
	var ge_first := 0
	for ge_r in g.recipes:
		if ge_r.has("gear"):
			if g.recipe_hidden(ge_r):
				ge_hid += 1
			elif not g.recipe_unlocked(ge_r):
				ge_first += 1
	var ge_ores := {}
	for ge_gid in Defs.GEAR:
		if Defs.gear_ores(ge_gid).size() == 1:
			ge_ores[int(Defs.gear_ores(ge_gid)[0])] = true
	var ge_hide_ok := ge_first == ge_ores.size() and ge_hid == Defs.GEAR.size() - ge_ores.size()
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
		for ge_c in ge_rec["cost"]:
			g.player.inv[int(ge_c)] += int(ge_rec["cost"][ge_c])
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
	g.player.spell_cd.clear()
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
	for hz_k in ["cold", "sun", "miasma"]:
		var hz_d: Dictionary = Defs.HAZARDS[hz_k]
		if hz_k == "miasma":
			# (26 Nov, the marsh's fog over all the land: it lies on the ground you stand on, and chokes you)
			g.time = hz_time0
			g.clim["fog"] = 1.0
			await _frames(40)
			_shot("marsh_fog.png")
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
		if hz_k == "miasma":
			hz_res[hz_k] = [hz_bare, hz_ward, hz_was, g.player.fog]
			g.clim["fog"] = 0.0
		else:
			hz_res[hz_k] = [hz_bare, hz_ward, hz_was]
	g.time = hz_time0
	g.spawn_timer = 600
	# (and digging what the staff can't cut no longer counts as star iron: the GPU's counters moved)
	var hz_si0: int = g.player.inv[Defs.STARIRON]
	var hz_up: Vector2 = g.player.pos.normalized()
	# (a few depths: one spot 110 down was a cave or soft ground now and then, with nothing hard to be blocked by)
	var hz_blk := false
	for hz_dd in [110.0, 140.0, 170.0, 200.0]:
		g.brushes.append([hz_up * (g.gpu.surf_at(atan2(hz_up.y, hz_up.x)).x - hz_dd), 6.0, 1, 0, 0, 0, 0, 0])
		for hz_f in 8:
			await _frames(1)
			hz_blk = hz_blk or g.dig_blocked > 0
		if hz_blk:
			break
	var hz_si1: int = g.player.inv[Defs.STARIRON]
	g.test_god = hz_god0
	g.player.hp = g.player.max_hp
	_go(hz_pos0)
	await _frames(20)
	var hz_ok := hz_open and hz_blk and hz_si1 == hz_si0
	for hz_k2 in hz_res:
		hz_ok = hz_ok and float(hz_res[hz_k2][0]) > 0.8 and float(hz_res[hz_k2][1]) < 0.05 and String(hz_res[hz_k2][2]) == hz_k2
	_ok("a planet's cold, midday sun and marsh fog hurt you in the open, but not with their wards; too-hard digging gives no star iron", hz_ok,
		"in the open %s; the cold: -%.1f health in 2.5 s bare (%s), -%.1f with the Hearth Charm; the sun overhead: -%.1f bare (%s), -%.1f with the Sun Veil; the marsh fog over the land (%.2f deep): -%.1f bare (%s), -%.1f with the Fen Mask; digging stone with no power: blocked %s, star iron %d -> %d" % [hz_open,
		float(hz_res["cold"][0]), hz_res["cold"][2], float(hz_res["cold"][1]), float(hz_res["sun"][0]), hz_res["sun"][2], float(hz_res["sun"][1]),
		float(hz_res["miasma"][3]), float(hz_res["miasma"][0]), hz_res["miasma"][2], float(hz_res["miasma"][1]), hz_blk, hz_si0, hz_si1] + ("" if hz_ok else "; what hurt: " + "; ".join(hz_why.slice(0, 12))))

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
	g.player.spell_cd.clear()
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
	# each spell keeps its own cooldown: Mending's long one doesn't hold Spark Bolt (user, 23 Nov)
	g.player.cast_cd = 0
	g.player.spell_cd.clear()
	g.player.mana = g.player.max_mana
	g.player.hp = g.player.max_hp - 40.0
	g._cast(g.player, "mend", g.player.pos)
	var cd_mend: int = int(g.player.spell_cd.get("mend", 0))
	await _frames(12)
	var cd_spark_ok: bool = g.spell_ready(g.player, "spark") and not g.spell_ready(g.player, "mend")
	g.player.hp = g.player.max_hp
	g.player.heal_left = 0.0
	g.player.spell_cd.clear()
	_ok("each spell has its own cooldown: casting Mending leaves Spark Bolt ready a moment later", cd_mend > 100 and cd_spark_ok,
		"Mending's cooldown %d ticks; %d ticks on, Spark Bolt ready and Mending not: %s" % [cd_mend, 12, cd_spark_ok])
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
		g.player.spell_cd.clear()
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
	# (something of each section: a carried kiln and a door for the "To set down" row)
	var ui_st0: int = int(g.items.get("st_kiln", 0))
	var ui_dr0: int = g.player.inv[Defs.WOODDOOR]
	g.items["st_kiln"] = 1
	g.player.inv[Defs.WOODDOOR] = maxi(ui_dr0, 2)
	await _frames(20)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_hud.png"))
	if ui_st0 > 0:
		g.items["st_kiln"] = ui_st0
	else:
		g.items.erase("st_kiln")
	g.player.inv[Defs.WOODDOOR] = ui_dr0
	var sr: Rect2 = ui._on_screen(ui.satchel_panel)
	var hr: Rect2 = ui._on_screen(ui.hotbar)
	var vs: Vector2 = g.get_viewport().get_visible_rect().size
	if sr.size.x < 50 or not Rect2(Vector2.ZERO, vs).encloses(sr):
		bad.append("the satchel is off the screen (%s)" % sr)
	if hr.size.x < 50 or not Rect2(Vector2.ZERO, vs).encloses(hr):
		bad.append("the spell bar is off the screen (%s)" % hr)
	var slots: int = ui.satchel_slots
	g.ui.satchel_open = false
	g.ui._inv_key = ""
	g.ui.show_forge()
	await _frames(10)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_forge.png"))
	var fr: Rect2 = ui._on_screen(ui.forge)
	if not Rect2(Vector2.ZERO, vs).encloses(fr):
		bad.append("the forge doesn't fit the screen (%s)" % fr)
	g.ui.hide_forge()
	ui.settings_menu.open_pause()
	var t_menu: float = g.time
	await _frames(10)
	g.get_viewport().get_texture().get_image().save_png(dir.path_join("ui_settings.png"))
	if g.state == "play" and absf(g.time - t_menu) > 0.0001:
		bad.append("the Esc menu doesn't pause the game (time went on %.3f)" % (g.time - t_menu))
	ui.settings_menu.close()
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
	# and a few beasts' whole walk, then breathing and blinking, one row each (6x): saves/shots/beasts_walk.png
	var rows_w := []
	for bk2 in beasts:
		if String(beasts[bk2]["plan"]) == "beast" and rows_w.size() < 5 and (rows_w.size() < 4 or bk2.begins_with("boss_")):
			var fr2: Dictionary = BA.frames(bk2, beasts[bk2])
			var row := []
			for k6 in 6:
				row.append(fr2["%s_walk%d" % [bk2, k6]])
			row.append(fr2[bk2])
			row.append(fr2[bk2 + "_breathe"])
			row.append(fr2[bk2 + "_blink"])
			rows_w.append(row)
	var cw := 0
	var chh := 0
	for rw in rows_w:
		for im4 in rw:
			cw = maxi(cw, (im4 as Image).get_width() * 6)
			chh = maxi(chh, (im4 as Image).get_height() * 6)
	var sheet_w := Image.create((cw + 6) * 9 + 6, (chh + 6) * rows_w.size() + 6, false, Image.FORMAT_RGBA8)
	sheet_w.fill(Color(0.35, 0.5, 0.62))
	for ri in rows_w.size():
		for ci in rows_w[ri].size():
			var big2: Image = (rows_w[ri][ci] as Image).duplicate()
			big2.resize(big2.get_width() * 6, big2.get_height() * 6, Image.INTERPOLATE_NEAREST)
			sheet_w.blend_rect(big2, Rect2i(Vector2i.ZERO, big2.get_size()), Vector2i(6 + ci * (cw + 6), 6 + ri * (chh + 6) + chh - big2.get_height()))
	sheet_w.save_png(dir.path_join("beasts_walk.png"))
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
	await _test_settings()
	await _test_breath()
	await _test_water()

## (27 Nov; user: "the water is a bit too viscous, and i would like a more fleshed out water with proper vfx") a block
## of water let go over level ground runs out along it (it keeps the way it's flowing: move.comp), and a mage
## dropping into it splashes and breathes out bubbles
func _test_water() -> void:
	var pc: Vector2i = Build.cell_of(g.player.pos)
	var st := _clear_stretch(pc.x + 120, 180, 40, 4)
	var bad := []
	var width := 0
	var splashes0: int = int(g.vfx.stats.get("splashes", 0))
	var bub := 0
	var float_ok := false
	var float_txt := ""
	if not _cs_found:
		bad.append("no level ground near")
	else:
		var gr: int = g.builds.ground_row(st.x + 90)
		var w_home: Vector2 = g.player.pos
		_go(Build.cell_pos(st.x + 20, gr - 14))          # (beside it: the world is simulated round you)
		await _frames(20)
		var blk := PackedInt32Array()
		blk.resize(10 * 24)
		blk.fill(Defs.WATER | 0xFF00)
		g.stamps.append({"x0": posmod(st.x + 85, Defs.NS), "y0": gr - 34, "w": 10, "h": 24, "data": blk})
		await _frames(150)
		var rr: Dictionary = g.gpu.read_rect(st.x, gr - 14, 180, 18)
		var fg: PackedInt32Array = rr["fg"]
		for x in 180:
			for y in 18:
				if (fg[y * 180 + x] & 255) == Defs.WATER:
					width += 1
					break
		if width < 70:
			bad.append("the water spread only %d cells wide in 2.5 s" % width)
		# a mage dropping in: a splash, and bubbles under water
		var back: Vector2 = Build.cell_pos(st.x + 20, gr - 14)
		var god0: bool = g.test_god
		g.test_god = true
		var blk2 := PackedInt32Array()
		blk2.resize(16 * 30)
		blk2.fill(Defs.WATER | 0xFF00)
		g.stamps.append({"x0": posmod(st.x + 82, Defs.NS), "y0": gr - 75, "w": 16, "h": 30, "data": blk2})
		await _frames(2)
		var wa: Vector2 = Build.cell_pos(st.x + 90, gr - 58)
		g.player.pos = wa
		g.player.vx = 0.0
		g.player.vy = 1.5
		g.cam_c = wa
		for q in 40:
			await _frames(1)
			for k in g.vfx.K.size():
				if g.vfx.K[k] == g.Vfx.BUBBLE:
					bub += 1
					break
		_shot("water.png")
		g.player.pos = back
		g.cam_c = back
		g.test_god = god0
		var clr := PackedInt32Array()
		clr.resize(180 * 80)
		clr.fill(0xFF00 | 0x10000)
		g.stamps.append({"x0": posmod(st.x, Defs.NS), "y0": gr - 80, "w": 180, "h": 80, "data": clr})
		await _frames(10)
		# (27 Nov; user: "the ship can fly underwater just like above the water. i think we should resolve this
		# somehow") a ship let fall into a tank of water rides on its top
		var TW := 100
		var TH := 64
		var tank := PackedInt32Array()
		tank.resize(TW * TH)
		for ty in TH:
			for tx in TW:
				var wall: bool = tx < 3 or tx >= TW - 3 or ty >= TH - 3
				tank[ty * TW + tx] = ((Defs.STONE | 0x20000) if wall else Defs.WATER) | 0xFF00      # (the walls anchored)
		var t_r0: int = gr - 6 - TH
		g.stamps.append({"x0": posmod(st.x + 40, Defs.NS), "y0": t_r0, "w": TW, "h": TH, "data": tank})
		await _frames(3)
		var had_skiff: bool = g.items.has("skiff")
		var sk0 = g.skiff
		g.items["skiff"] = true
		g.call_skiff()
		var sk = g.skiff
		var tup: Vector2 = Build.cell_pos(st.x + 90, t_r0).normalized()
		sk.pos = Build.cell_pos(st.x + 90, t_r0 - 40)
		sk.vel = -tup * 2.0
		g.cam_c = sk.pos
		var splashed0: int = int(g.vfx.stats.get("splashes", 0))
		for q2 in 180:
			g.cam_c = sk.pos
			await _frames(1)
		_shot("ship_float.png")
		var top_r: float = Build.cell_pos(st.x + 90, t_r0 + 1).length()          # (the water's top)
		var keel_r: float = sk.pos.length() - float(sk.h) * 0.35
		float_ok = g.skiff_wet > 0.0 and g.skiff_wet < 0.8 and keel_r > top_r - float(TH) * 0.5 and sk.vel.length() < 0.6
		float_txt = "the ship rides with %.0f%% of it in the water, its keel %.0f under the top, still %s; splashed %s" % [g.skiff_wet * 100.0, top_r - keel_r, sk.vel.length() < 0.6, int(g.vfx.stats.get("splashes", 0)) > splashed0]
		if not float_ok:
			bad.append(float_txt)
		if not had_skiff:
			g.items.erase("skiff")
		g.skiff = sk0
		var tclr := PackedInt32Array()
		tclr.resize(TW * (TH + 50))
		tclr.fill(0xFF00)
		g.stamps.append({"x0": posmod(st.x + 40, Defs.NS), "y0": t_r0 - 50, "w": TW, "h": TH + 50, "data": tclr})
		await _frames(10)
		_go(w_home)
		await _frames(10)
	var spl: int = int(g.vfx.stats.get("splashes", 0)) - splashes0
	if spl < 1:
		bad.append("no splash going in")
	_ok("water: a spill runs out along the ground; going in splashes, bubbles rise; a ship floats", bad.is_empty(),
		("spread %d cells wide in 2.5 s; %d splash(es); bubbles about for %d ticks; %s (pictures water.png, ship_float.png)" % [width, spl, bub, float_txt]) if bad.is_empty() else "; ".join(bad))

## (27 Nov; user: "i don't see my breath level underwater. can we make a graphical meter that feels part of the
## world") bubbles over the mage's head: as many as the eighths of breath left, one popping as it runs out, gone
## a moment after it's full again
func _test_breath() -> void:
	var ov = g.overlay
	var m = g.player
	var b0: float = m.breath
	m.breath = m.max_breath * 0.45        # (on dry ground it comes back 4 a tick: a few frames' worth is allowed for)
	await _frames(4)
	var n_a: int = ov._br_shown
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("breath.png"))
	m.breath = m.max_breath * 0.2
	await _frames(3)
	var n_b: int = ov._br_shown
	m.breath = m.max_breath
	await _frames(80)
	var n_c: int = ov._br_shown
	m.breath = b0
	_ok("breath: bubbles over the mage's head, one popping as each eighth runs out, gone once it's back", n_a >= 4 and n_a <= 5 and n_b >= 2 and n_b <= 3 and n_c == -1,
		"at 45%%: %d bubbles; at 20%%: %d; full again: %s (picture breath.png)" % [n_a, n_b, "gone" if n_c == -1 else str(n_c)])

## (27 Nov; user: "ok do you want to create a real setting menu now"; chose rebindable keys, more sound sliders,
## display extras, comfort and gameplay, and a pause menu on Esc) Esc opens the pause page and pauses; every tab of
## the settings builds and fits the screen; a key rebound works and the old one doesn't; the arrows still move;
## the volumes, the interface size and the comfort settings take effect; Esc steps back out
func _test_settings() -> void:
	var ui = g.ui
	var sm = ui.settings_menu
	var dir: String = g._real_save_dir().path_join("shots")
	var vs: Vector2 = g.get_viewport().get_visible_rect().size
	var bad := []
	var keep: Dictionary = g.settings.duplicate(true)
	var keys0: Dictionary = g.keymap.duplicate(true)
	# Esc: the pause page
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	g._unhandled_input(esc)
	await _frames(3)
	if not (sm.is_open() and sm.page == "pause"):
		bad.append("Esc didn't open the pause page")
	if not g.menu_paused():
		bad.append("the pause page doesn't pause")
	# every tab
	sm.open_settings(true)
	for t in sm.TABS:
		sm.tab = t
		sm.build()
		await _frames(3)
		var pr: Rect2 = ui._on_screen(ui.settings_panel.get_child(0).get_child(0))
		if not Rect2(Vector2.ZERO, vs).encloses(pr):
			bad.append("the %s tab doesn't fit the screen (%s)" % [t, pr])
		g.get_viewport().get_texture().get_image().save_png(dir.path_join("settings_%s.png" % t.to_lower()))
	# Esc steps back: settings -> pause -> closed
	g._unhandled_input(esc)
	var back_pause: bool = sm.is_open() and sm.page == "pause"
	g._unhandled_input(esc)
	if not back_pause or sm.is_open():
		bad.append("Esc didn't step back out (to the pause page %s, closed %s)" % [back_pause, not sm.is_open()])
	# a key rebound: F to U for Use, through the capture as a player would
	sm.open_settings(false)
	sm.tab = "Controls"
	sm.capture = ["interact", 0]
	sm.build()
	var ku := InputEventKey.new()
	ku.keycode = KEY_U
	ku.pressed = true
	sm._input(ku)
	var rebound: bool = g.key_is(KEY_U, "interact") and not g.key_is(KEY_F, "interact")
	if not rebound:
		bad.append("rebinding Use to U didn't take (%s)" % str(g.keymap.get("interact")))
	var arrows: bool = g.key_is(KEY_LEFT, "left") and g.key_is(KEY_UP, "jump")
	if not arrows:
		bad.append("the arrow keys don't move")
	var saved_ok := false
	var sf := FileAccess.get_file_as_string(g._real_save_dir().path_join("settings.json"))
	var sd = JSON.parse_string(sf)
	if typeof(sd) == TYPE_DICTIONARY and typeof(sd.get("keys")) == TYPE_DICTIONARY:
		saved_ok = (sd["keys"]["interact"] as Array).has(float(KEY_U)) or (sd["keys"]["interact"] as Array).has(KEY_U)
	if not saved_ok:
		bad.append("the new key wasn't saved")
	g.reset_keys()
	if not g.key_is(KEY_F, "interact"):
		bad.append("Reset keys didn't bring F back")
	sm.close()
	# volumes, the interface's size, comfort
	g.set_setting("ambience", 40)
	g.set_setting("ui_vol", 30)
	g.set_setting("master", 50)
	var vol_ok: bool = absf(g.audio.amb_volume - 0.4) < 0.01 and absf(g.audio.ui_volume - 0.3) < 0.01 and absf(db_to_linear(AudioServer.get_bus_volume_db(0)) - 0.5) < 0.02
	if not vol_ok:
		bad.append("the volumes didn't take (ambience %.2f, interface %.2f, master %.2f)" % [g.audio.amb_volume, g.audio.ui_volume, db_to_linear(AudioServer.get_bus_volume_db(0))])
	var u0: int = ui.U
	g.set_setting("ui_scale", -1)
	var u_small: int = ui.U
	g.set_setting("ui_scale", 0)
	if u0 > 1 and u_small != u0 - 1:
		bad.append("Interface: Smaller didn't shrink it (%d to %d)" % [u0, u_small])
	g.set_setting("bright", 120)
	await _frames(3)
	var post_on: bool = g.post_rect.visible
	g.set_setting("bright", 100)
	if not post_on:
		bad.append("brightness didn't turn the last pass on")
	# restore
	for k in keep:
		g.settings[k] = keep[k]
	g.keymap = keys0
	g.settings["keys"] = g.keymap
	g._save_settings()
	g._apply_volumes()
	g._apply_window()
	ui._relayout()
	g._post_key = ""
	_ok("the settings: a pause page on Esc, four tabs that fit, keys rebound and saved, volumes, size and brightness", bad.is_empty(),
		("tabs %s; a key rebound, the arrows still move, Esc steps back (pictures settings_*.png)" % ", ".join(sm.TABS)) if bad.is_empty() else "; ".join(bad))

## (user, 25 Nov: "make the text boxes for speech look a little nicer with an animation and talking sound
## effects"): the wisp's words pop in and type out with blips, a villager's in their own voice
func _test_speech() -> void:
	var rows := []
	var ok := true
	var sp = g.speech
	var Sp = load("res://scripts/speech.gd")
	g.player.dead = false
	_go(g.player.pos)
	await _frames(20)
	var b0: int = int(sp.stats["blips"])
	var line := "Well met, mage. The stones remember a song; listen, and they'll teach it to you."
	g.quest.say_text = line
	g.quest.say_t = 600
	await _frames(3)
	var popping: bool = sp.st.has("wisp") and int(sp.st["wisp"]["age"]) < 6
	await _frames(14)
	var typing: bool = sp.typing("wisp")
	var part: int = int(sp.st["wisp"]["shown"]) if sp.st.has("wisp") else -1
	_shot("speech_typing.png")
	for w in 240:
		if not sp.typing("wisp"):
			break
		await _frames(1)
	var done: bool = sp.st.has("wisp") and not sp.typing("wisp")
	var blips: int = int(sp.stats["blips"]) - b0
	await _frames(10)
	_shot("speech_wisp.png")
	var ok0: bool = popping and typing and part > 0 and part < line.length() and done and blips >= 15 and blips <= 50
	rows.append("%sthe wisp: popped in %s, typing %s (%d of %d letters), all said %s, %d blips" % ["" if ok0 else "(!) ", popping, typing, part, line.length(), done, blips])
	ok = ok and ok0
	g.quest.say_t = 0
	await _frames(20)
	var forgot: bool = not sp.st.has("wisp") or Engine.get_process_frames() - int(sp.st["wisp"]["seen"]) > 10
	# a villager speaking (one stood beside you), in their own voice
	var ok1 := true
	var vtxt := ""
	if not g.towns.folk.is_empty():
		var v = g.towns.folk[0]
		v.fade = 0
		v.say = "Fine weather for digging, isn't it? Mind the caves past the old well."
		v.say_t = 400
		var keep_pos: Vector2 = v.pos
		v.pos = g.player.pos + g.basis_r(atan2(g.player.pos.y, g.player.pos.x)) * 30.0
		await _frames(90)
		var vk := "f%d" % v.fseed
		ok1 = sp.st.has(vk)
		vtxt = "a villager speaking %s (pitch %.2f)" % [ok1, Sp.pitch_of(v.fseed)]
		_shot("speech_villager.png")
		v.say_t = 0
		v.pos = keep_pos
	else:
		vtxt = "no villager about to speak"
	# a villager's parchment bubble and a prompt, side by side
	var r: Vector2 = g.basis_r(atan2(g.player.pos.y, g.player.pos.x))
	g.test_bubbles = [[g.player.pos - r * 40.0, "Fine weather for digging, isn't it? Mind the caves past the old well.", 1.0, "tv", Sp.SPEECH, 0.9],
		[g.player.pos + r * 45.0, "[F] Step into the pocket", 1.0, "tp", Sp.PROMPT, 1.0]]
	await _frames(100)
	var both: bool = sp.st.has("tv") and sp.st.has("tp") and not sp.typing("tv") and not sp.typing("tp")
	_shot("speech_kinds.png")
	g.test_bubbles = []
	ok1 = ok1 and both
	rows.append("%s%s; forgotten once it stops %s; a parchment bubble and a prompt %s" % ["" if ok1 and forgot else "(!) ", vtxt, forgot, both])
	ok = ok and ok1 and forgot
	print("[speech] " + "\n[speech] ".join(rows))
	_ok("speech bubbles pop in, type out with a voice, and are forgotten when they stop", ok, "; ".join(rows))

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
	# digging grows with the staff's tier and the Delver's Runes (user, 23 Nov: slow at first, faster later)
	var st_tier0: int = g.player.tier
	var st_delve0 = g.items.get("delve", null)
	var st_speeds := []
	for st_t in [1, 2, 3, 4]:
		g.player.tier = st_t
		g.items.erase("delve")
		st_speeds.append(g.dig_speed(g.player))
	g.player.tier = 2
	var st_d_ok := true
	var st_last: float = g.dig_speed(g.player)
	for st_dr in ["delve1", "delve2", "delve3"]:
		var st_rec: Dictionary = st_recipes.get(st_dr, {})
		var st_un: bool = not st_rec.is_empty() and g.recipe_unlocked(st_rec) and not g.recipe_done(st_rec)
		for st_cm in st_rec.get("cost", {}):
			g.player.inv[int(st_cm)] += int(st_rec["cost"][st_cm])
		g.learn(st_dr, "test")
		var st_made: bool = st_un and g.craft(st_rec)
		var st_now: float = g.dig_speed(g.player)
		st_d_ok = st_d_ok and st_made and st_now > st_last * 1.25 and g.recipe_done(st_rec)
		st_last = st_now
	var st_mono: bool = st_speeds[0] < st_speeds[1] and st_speeds[1] < st_speeds[2] and st_speeds[2] < st_speeds[3]
	_ok("digging speeds up with each focus and each Delver's Rune", st_mono and st_d_ok,
		"by tier %s; with the Copper Focus and three runes %.2f" % [str(st_speeds), st_last])
	# (user, 24 Nov): a better focus makes a cell cheaper and brings mana back faster, so the drain a second
	# grows far less than the speed; the Mana Crystal adds to regeneration (it used to set it, losing gear's)
	var st_cost := []
	var st_regen := []
	var st_drain := []
	g.items.erase("delve")
	for st_t2 in [1, 2, 3, 4]:
		g.player.tier = st_t2
		st_cost.append(g.dig_mana(Defs.STONE))
		st_regen.append(g.mana_regen_of(g.player))
		st_drain.append(g.dig_speed(g.player) * g.dig_mana(Defs.STONE) / g.mana_regen_of(g.player))
	var st_r0: float = g.player.mana_regen
	var st_mx0: float = g.player.max_mana
	var st_cr0: bool = g.items.has("mana_crystal")
	var st_mrec: Dictionary = st_recipes.get("mana", {})
	g.items.erase("mana_crystal")
	g.player.max_mana = 100.0
	g.player.mana_regen = st_r0 + 0.08                   # (as if a Sunstone Circlet were forged first)
	for st_cm2 in st_mrec.get("cost", {}):
		g.player.inv[int(st_cm2)] += int(st_mrec["cost"][st_cm2])
	g.learn("mana", "test")
	g.craft(st_mrec)
	var st_cr_ok: bool = absf(g.player.mana_regen - (st_r0 + 0.18)) < 0.001
	g.player.mana_regen = st_r0
	g.player.max_mana = st_mx0
	if not st_cr0:
		g.items.erase("mana_crystal")
	var st_m_ok: bool = st_cost[3] < st_cost[0] * 0.55 and st_regen[3] > st_regen[0] * 1.5 and st_drain[3] < st_drain[0] * 1.3 \
		and g.dig_speed(g.player, false) > g.dig_speed(g.player) * 1.3 and st_cr_ok and Defs.learn_of({"id": "mana"}).has("find")
	_ok("each focus makes digging cheaper and mana quicker to come back; the Mana Crystal adds to it", st_m_ok,
		"a stone cell %s mana, regen %s a tick, digging's pull on mana (x regen) %s by tier; asteroids at %.2f; the crystal on a circlet: %s" % [
		str(st_cost.map(func(v): return snappedf(v, 0.001))), str(st_regen.map(func(v): return snappedf(v, 0.001))),
		str(st_drain.map(func(v): return snappedf(v, 0.01))), g.dig_speed(g.player, false), st_cr_ok])
	g.player.tier = st_tier0
	if st_delve0 == null:
		g.items.erase("delve")
	else:
		g.items["delve"] = st_delve0
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
	# (the skiff isn't sold any more: two guardians' halves of its plans teach it, 24 Nov)
	var rc_skiff := true
	for rr in rc_shop:
		if String(rr["id"]) == "skiff":
			rc_skiff = false
	g.towns.grant({"recipe": "hearth"})
	var rc_ok3: bool = rc_chest and rc_hoard and rc_skiff and g.knows(g.recipe_by_id("hearth")) and g.learned.size() >= rc_n0 + 3
	rc_rows.append("%sa chest's scroll %s, a hoard's %s, a keeper's Hearth Charm bought %s; the skiff not sold %s" % ["" if rc_ok3 else "(!) ", rc_chest, rc_hoard, g.knows(g.recipe_by_id("hearth")), rc_skiff])
	rc_ok = rc_ok and rc_ok3
	# every recipe has a way to be learned, and the book says where
	var rc_noway := []
	for rr2 in g.recipes:
		var rl: Dictionary = Defs.learn_of(rr2)
		if not (rl.get("start", false) or rl.has("find") or rl.has("scroll") or rl.has("shop") or rl.get("hoard", false) or rl.has("guardians")):
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
	var rc_ok4: bool = rc_book and rc_sl.has("sandstone") and rc_sl.has("hearth") and not rc_sl.has("plank")
	rc_rows.append("%sthe book shows %s; saved: %d learned (sandstone %s, hearth %s)" % ["" if rc_ok4 else "(!) ", rc_book, rc_sl.size(), rc_sl.has("sandstone"), rc_sl.has("hearth")])
	rc_ok = rc_ok and rc_ok4
	g.player.inv = rc_inv
	g.learned = rc_learned
	g.items = rc_items
	g.save_game()
	_ok("recipes are learned: a handful at first, then first finds, chest scrolls, keepers and hoards; the book shows the rest", rc_ok, "; ".join(rc_rows))

## The main quest (user, 23 Nov: guidance through the main progression, spoken by the wisp, a HUD line and a
## journal, and the wisp's own powers as rewards): from a bare start every step of the first chapter ticks off
## in order as its condition comes true, with its rewards and the four powers; each power does what it says; the
## journal opens and the world waits; a journey from before the quest catches up quietly; every later chapter
## is well formed.
func _test_quest() -> void:
	var rows := []
	var ok := true
	var q = g.quest
	var items0: Dictionary = g.items.duplicate(true)
	var inv0: PackedInt32Array = g.player.inv.duplicate()
	var tier0: int = g.tier
	var known0: Array = g.known.duplicate()
	var hw0: bool = g.heat_ward
	var st0: Array = g.workshops.list
	g.workshops.list = []
	g.quest_test = true
	# ---- a bare start
	for key in ["skiff", "drive", "skiff_plans", "st_altar", "levitate", "mana_crystal", "heart", "quest", "qdone", "qfin", "st_kiln", "wisp_lantern", "wisp_sense", "wisp_ward", "wisp_hands", "cinderheart"]:
		g.items.erase(key)
	g.items["landed"] = {"0": true}
	for key2 in g.items.keys():
		if String(key2).begins_with("found_"):
			g.items.erase(key2)
	for mt in [Defs.STONE, Defs.COPPERBAR, Defs.STARIRON, Defs.CORE, Defs.WISPCELL, Defs.COPPER]:
		g.player.inv[mt] = 0
	g.tier = 1
	g.known.erase("spark")
	g.heat_ward = false
	g.items["quest"] = {"ch": 0, "at": 0, "v": 5}
	g.items["coins"] = 0
	q.reset()
	await _frames(31)
	var steps: Array = q.steps
	var hud0: String = q.hud_line()
	var ok0: bool = steps.size() >= 15 and q.at == 0 and hud0 == String(steps[0]["title"]) and q.say_t > 0
	rows.append("%sa bare start: %d steps, at step %d, the HUD says \"%s\", the wisp speaking %s" % ["" if ok0 else "(!) ", steps.size(), q.at, hud0, q.say_t > 0])
	ok = ok and ok0
	await _frames(20)
	_shot("quest_wisp.png")
	# ---- every step, made true in turn (the voyage can't be: it needs another planet)
	var order_ok := true
	var stuck := ""
	for i in steps.size():
		var st: Dictionary = steps[i]
		if String(st["id"]) == "voyage":
			break
		var c: Array = st["need"][0]
		match String(c[0]):
			"held": g.player.inv[int(c[1])] = maxi(g.player.inv[int(c[1])], int(c[2]))
			"found": g.player.inv[int(c[1])] += 1
			"spell":
				if not g.known.has(String(c[1])):
					g.known.append(String(c[1]))
			"tier": g.tier = maxi(g.tier, int(c[1]))
			"item": g.items[String(c[1])] = true
			"station": g.workshops.add(String(c[1]), g.player.pos + g.player.pos.normalized() * 30.0)
			"count": g.items[String(c[1])] = int(c[2])
			"learned": g.learn(String(c[1]))
			"heat": g.heat_ward = true
		for w in 40:
			await _frames(1)
			if q.at > i:
				break
		if q.at <= i:
			order_ok = false
			stuck = String(st["id"])
			break
	var powers := []
	for pw in ["lantern", "sense", "ward", "hands"]:
		if g.items.has("wisp_" + pw):
			powers.append(pw)
	var at_voyage: bool = q.at < steps.size() and String(steps[q.at]["id"]) == "voyage"
	var coins: int = int(g.items.get("coins", 0))
	# (the first voyage is to the round's world with no barrier: Fenhollow, a marsh world, in the classic system)
	var ok1: bool = order_ok and at_voyage and powers.size() == 4 and coins > 0 and q.hud_line() == "Fly to %s" % Defs.make_planet(q.open_target(0))["name"] and Defs.barrier_of(q.open_target(0)) == ""
	rows.append("%severy step ticked off in order %s%s, now at \"%s\"; powers %s; %d coins in rewards; %d steps done, %d rewards, said %d times" % ["" if ok1 else "(!) ", order_ok, (" (stuck at " + stuck + ")") if stuck != "" else "", q.hud_line(), ",".join(powers), coins, int(q.stats["done"]), int(q.stats["rewards"]), int(q.stats["said"])])
	ok = ok and ok1
	var ql: bool = g.ui.quest_lbl.visible and String(g.ui.quest_lbl.text).contains(q.hud_line())
	rows.append("%sthe HUD's quest line shows it %s" % ["" if ql else "(!) ", ql])
	ok = ok and ql
	# ---- the powers
	var far: Vector2 = g.player.pos + Vector2(900.0, 0.0)
	var r_with: float = (g._reach(g.player, far) - g.player.pos).length()
	g.items.erase("wisp_hands")
	var r_without: float = (g._reach(g.player, far) - g.player.pos).length()
	g.items["wisp_hands"] = true
	var ok2: bool = absf(r_with / maxf(r_without, 0.01) - 1.5) < 0.01
	rows.append("%sWisp Hands: reach %.0f (%.0f without)" % ["" if ok2 else "(!) ", r_with, r_without])
	ok = ok and ok2
	var god0: bool = g.test_god
	g.test_god = false
	g.wisp_ward_t = 0
	g.player.iframes = 0
	var hp0: float = g.hp
	g.hurt(g.player, 10.0, Vector2.ZERO, true)
	var hp1: float = g.hp
	var charging: int = g.wisp_ward_t
	g.player.iframes = 0
	g.hurt(g.player, 10.0, Vector2.ZERO, true)
	var hp2: float = g.hp
	g.hp = hp0
	g.player.iframes = 0
	g.test_god = god0
	var ok3: bool = absf(hp1 - hp0) < 0.01 and charging > 1000 and hp2 < hp1 - 5.0
	rows.append("%sWisp Ward: the first blow taken (%.0f -> %.0f), recharging %d ticks, the next one hurts (-> %.0f)" % ["" if ok3 else "(!) ", hp0, hp1, charging, hp2])
	ok = ok and ok3
	g.lights.clear()
	g._update_wisp()
	var lantern := false
	for lt in g.lights:
		if absf(float(lt[1]) - 92.0) < 0.1:
			lantern = true
	rows.append("%sWisp Lantern: the wisp's light reaches 92 %s" % ["" if lantern else "(!) ", lantern])
	ok = ok and lantern
	g.sense_t = 0
	g._sense_next = 1
	var pulsed := false
	for w2 in 30:
		await _frames(1)
		if g.sense_t > 0:
			pulsed = true
			break
	var n_ore: int = g.sense_pts.size()
	await _frames(40)
	_shot("quest_sense.png")
	# (shown on the minimap now, not in the world: user, 25 Nov; its stats are the last frame's)
	var mm_ore: bool = n_ore == 0 or int(g.ui.minimap.stats.get("ore", 0)) > 0
	rows.append("%sOre Sense: pulsed %s, %d ore cells marked round you, on the minimap %s" % ["" if pulsed and mm_ore else "(!) ", pulsed, n_ore, mm_ore])
	# (how much ore there is: every ore cell in a 600 x 300 block under where you start; user, 25 Nov: "ore is much
	# too abundant")
	var oc_a: float = g.spawn_angle
	var oc_c: Vector2i = Build.cell_of(Vector2(cos(oc_a), sin(oc_a)) * g.gpu.surf_at(oc_a).x)
	var oc_r: Dictionary = g.gpu.read_rect(posmod(oc_c.x - 300, Defs.NS), oc_c.y + 20, 600, 300)
	var oc_n := {}
	for ocv in oc_r["fg"]:
		var oct: int = int(ocv) & 255
		if oct in [Defs.COPPER, Defs.COAL, Defs.CRYSTAL, Defs.FROST, Defs.EMBER, Defs.WISP]:
			oc_n[Defs.NAMES[oct]] = int(oc_n.get(Defs.NAMES[oct], 0)) + 1
	print("[ore] %s" % str(oc_n))
	rows.append("ore under the start: %s" % str(oc_n))
	ok = ok and pulsed and mm_ore
	# ---- the skiff's plans: a half from each guardian beaten, the second teaches the recipe
	var pl_learned: bool = g.learned.has("skiff")
	g.learned.erase("skiff")
	g.items.erase("skiff_plans")
	g.skiff_plan_found()
	var pl_half: bool = int(g.items.get("skiff_plans", 0)) == 1 and not g.learned.has("skiff")
	g.skiff_plan_found()
	var pl_whole: bool = g.learned.has("skiff")
	var pl_hint: String = Defs.learn_hint(g.recipe_by_id("skiff"))
	if pl_learned:
		g.learned["skiff"] = true
	var ok_pl: bool = pl_half and pl_whole and pl_hint.contains("guardians")
	rows.append("%sthe skiff's plans: one guardian gave half %s, the second made them whole %s; the book says \"%s\"" % ["" if ok_pl else "(!) ", pl_half, pl_whole, pl_hint])
	ok = ok and ok_pl
	# ---- the journal: opens, the world waits, closes
	g.ui.toggle_journal(g)
	await _frames(5)
	var t0: float = g.time
	await _frames(20)
	var waited: bool = g.menu_paused() and absf(g.time - t0) < 0.5
	_shot("quest_journal.png")
	g.ui.toggle_journal(g)
	await _frames(5)
	var ok4: bool = waited and not g.ui.journal_open() and not g.menu_paused()
	rows.append("%sthe journal opened, the world waited %s, it closed %s" % ["" if ok4 else "(!) ", waited, not g.ui.journal_open()])
	ok = ok and ok4
	# ---- a journey from before the quest: caught up quietly, with the powers it earned and no rewards
	# (and one from before the barriers: its "quest" has no "v", so it catches up from the top, quietly too)
	for key3 in ["quest", "qdone", "qfin", "wisp_lantern", "wisp_sense", "wisp_ward", "wisp_hands", "heart", "drive"]:
		g.items.erase(key3)
	g.items["skiff"] = true
	g.tier = 3
	g.items["coins"] = 0
	g.items["quest"] = {"ch": 0, "at": 9}
	q.reset()
	await _frames(31)
	var cid: String = String(q.steps[q.at]["id"]) if q.at < q.steps.size() else "-"
	var ok5: bool = g.items.has("wisp_lantern") and not g.items.has("wisp_ward") and int(g.items.get("coins", 0)) == 0 and (cid == "heat" or cid == "vulkhar") and int((g.items["quest"] as Dictionary).get("v", 0)) == 5
	rows.append("%san old journey (skiff, Obsidian Focus, a quest from before the barriers) caught up to \"%s\", lantern %s, ward %s, %d coins given" % ["" if ok5 else "(!) ", cid, g.items.has("wisp_lantern"), g.items.has("wisp_ward"), int(g.items.get("coins", 0))])
	ok = ok and ok5
	# ---- a later world's chapter leads to the next world of the round, and the key to its barrier first
	var land0: Dictionary = (g.items.get("landed", {}) as Dictionary).duplicate()
	var keys0 := {}
	for kk in ["lattice", "radward", "rimeprow", "keel"]:
		keys0[kk] = g.items.has(kk)
		g.items.erase(kk)
	g.items["landed"] = {"0": true, "4": true}
	var cs4: Array = q.chapter_steps(4)
	var ids4 := []
	for st4 in cs4:
		ids4.append(String(st4["id"]))
	g.items["radward"] = true
	var cs4b: Array = q.chapter_steps(4)
	var ids4b := []
	for st4b in cs4b:
		ids4b.append(String(st4b["id"]))
	g.items["landed"] = {"0": true, "1": true, "2": true, "3": true, "4": true}
	var cs4c: Array = q.chapter_steps(4)
	var last4c := String(cs4c[cs4c.size() - 1]["id"])
	g.items["landed"] = land0
	for kk2 in keys0:
		if bool(keys0[kk2]):
			g.items[kk2] = true
		else:
			g.items.erase(kk2)
	var ok5b: bool = ids4.has("key_radward") and ids4.has("voyage_1") and not ids4b.has("key_radward") and ids4b.has("voyage_1") and last4c == "stars"
	rows.append("%son Fenhollow: %s; with the Radiation Ward: %s; with every world seen it ends at \"%s\"" % ["" if ok5b else "(!) ", ",".join(ids4), ",".join(ids4b), last4c])
	ok = ok and ok5b
	# ---- the later chapters
	var bad := []
	var sizes := []
	for ch in range(1, 8):
		var cs: Array = q.chapter_steps(ch)
		sizes.append(cs.size())
		var last_id := String(cs[cs.size() - 1]["id"]) if not cs.is_empty() else ""
		if cs.size() < 1 or not (last_id.begins_with("voyage") or last_id == "stars"):
			bad.append(ch)
		for st2 in cs:
			if String(st2.get("title", "")) == "" or String(st2.get("say", "")) == "" or String(st2.get("how", "")) == "" or (st2.get("need", []) as Array).is_empty():
				bad.append(ch)
	var ok6: bool = bad.is_empty()
	rows.append("%schapters 2-8 well formed (steps %s)%s" % ["" if ok6 else "(!) ", str(sizes), (" bad: " + str(bad)) if not bad.is_empty() else ""])
	ok = ok and ok6
	# ---- put everything back
	g.items = items0
	g.player.inv = inv0
	g.tier = tier0
	g.known = known0
	g.heat_ward = hw0
	g.workshops.list = st0
	g.quest_test = false
	q.reset()
	print("[quest] " + "\n[quest] ".join(rows))
	_ok("the main quest: the wisp's guidance step by step, the HUD line, the journal, the four powers", ok, "; ".join(rows))

## A deep ocean world (user, 23 Nov: "are there super deep ocean worlds? also different types of planets ... with
## different mysteries to solve, along with different hazards to traverse to get to" them; chose the deep ocean
## first, clues and puzzles, optional with big rewards): where it lies, its maelstrom (spins you; the Tempest Keel
## lets you through), its sea hundreds of cells deep and dark, the crushing deep and the Depth Seal, the tide-stones
## read, the temple's dry hall over its flooded moon pool, a wrong note and the right song, the ward broken and the
## Tide Heart claimed.
## A gas giant (user, 24 Nov): where it lies (system 0's second exotic, clear of the deep ocean world), its
## Thunderhead (strikes far more than a storm belt; out of reach without the Storm Lattice), down onto its
## landing isle (you stand there; no ground within 450 under the mean surface), the crushing air under the
## cloud deck and the Depth Seal, the Eye's inscription, beacons lit (one left to go out), all five as one
## breaking the ward, the Storm Crown (the air under the clouds can't crush you with it). Pictures
## `giant_landing.png`, `giant_beacon.png`, `giant_eye.png`, `giant_vault.png`, `giant_journal.png`.
## Each kind of world's own core (user, 24 Nov: "Different types of cores for different types of planet allow
## crafting powerful spells and gear ... Rare planet types have rarer core materials"): every kind's core, this
## world's; the first one held teaches its spell and gear; each core spell flies (a fan where it should) and
## lands; the Sunlance hurts what it strikes; the gear forged does what it says.
func _test_cores() -> void:
	var rows := []
	var ok := true
	var kinds_ok := true
	var seen := {}
	for kd in ["temperate", "volcanic", "ocean", "desert", "marsh", "frozen", "wild", "realm", "abyss", "giant", "star", "void"]:
		var kc: int = Defs.kind_core({"kind": kd})
		if (kd in ["temperate", "giant", "star", "void"]) != (kc == Defs.CORE):
			kinds_ok = false
		if kc != Defs.CORE:
			if seen.has(kc):
				kinds_ok = false
			seen[kc] = true
	var ok1: bool = kinds_ok and seen.size() == 8 and g.core_mat == Defs.kind_core(g.planet) and Defs.kind_core(Defs.make_planet(1)) == Defs.EMBERCORE
	rows.append("%s8 kinds of core, each its own %s; here (%s) the heart gives %s; Cindrel's %s" % ["" if ok1 else "(!) ", kinds_ok, g.planet["name"], Defs.NAMES[g.core_mat], Defs.NAMES[Defs.kind_core(Defs.make_planet(1))]])
	ok = ok and ok1
	# ---- a first core teaches its spell and its gear
	var inv0: PackedInt32Array = g.player.inv.duplicate()
	var known0: Array = g.known.duplicate()
	var learned0: Dictionary = g.learned.duplicate()
	var items0: Dictionary = g.items.duplicate(true)
	for lid in ["cinder", "cindercrown", "leviathan", "abyssheart"]:
		g.learned.erase(lid)
	g.player.inv[Defs.EMBERCORE] = 1
	g.player.inv[Defs.ABYSSCORE] = 0
	g._learn_from_finds()
	# (its gear is studied from an artifact since 27 Nov: Defs.learn_of "study")
	var ok2: bool = g.learned.has("cinder") and not g.learned.has("cindercrown") and Defs.learn_of(g.recipe_by_id("cindercrown")).has("study") and not g.learned.has("leviathan")
	rows.append("%san Ember Core taught Cinderstorm %s, and the Cinder Crown is studied from a volcanic artifact %s (not the Abyss Core's: %s)" % ["" if ok2 else "(!) ", g.learned.has("cinder"), not g.learned.has("cindercrown"), not g.learned.has("leviathan")])
	ok = ok and ok2
	# ---- every core spell flies and lands
	var god0: bool = g.test_god
	g.test_god = true
	var side: Vector2 = g.player.pos.normalized().orthogonal()
	var flew := []
	var bad := []
	for sid in ["cinder", "tidal", "sunlance", "mire", "glacier", "thorns", "sovereign", "leviathan"]:
		if not g.known.has(sid):
			g.known.append(sid)
		g.player.mana = g.player.max_mana
		g.player.cast_cd = 0
		g.player.spell_cd.clear()
		var n0 := 0
		for pr in g.projs:
			if String(pr["type"]) == sid:
				n0 += 1
		g._cast(g.player, sid, g.player.pos + side * 80.0 + g.player.pos.normalized() * 10.0)
		var n1 := 0
		for pr2 in g.projs:
			if String(pr2["type"]) == sid:
				n1 += 1
		var want := int(Defs.PROJ[sid].get("multi", 1))
		flew.append("%s %d" % [sid, n1 - n0])
		if n1 - n0 != want:
			bad.append(sid)
		for w in 170:
			await _frames(1)
			var left := 0
			for pr3 in g.projs:
				if String(pr3["type"]) == sid:
					left += 1
			if left == 0:
				break
		for pr4 in g.projs:
			if String(pr4["type"]) == sid:
				bad.append(sid + " (still flying)")
				break
	var ok3: bool = bad.is_empty()
	rows.append("%severy core spell flew and landed: %s%s" % ["" if ok3 else "(!) ", ", ".join(flew), (" bad: " + str(bad)) if not bad.is_empty() else ""])
	ok = ok and ok3
	_shot("core_spells.png")
	# ---- the Sunlance strikes hard, and the Sovereign Bolt heals you as it strikes
	var foe = g.spawn_enemy("slime", g.player.pos + side * 46.0 + g.player.pos.normalized() * 4.0)
	foe.max_hp = 500.0
	foe.hp = 500.0
	await _frames(20)
	g.player.mana = g.player.max_mana
	g.player.spell_cd.clear()
	g.player.cast_cd = 0
	g._cast(g.player, "sunlance", foe.pos)
	for w2 in 40:
		await _frames(1)
	var lost: float = 500.0 - foe.hp
	g.player.heal_left = 0.0
	g.hp = g.max_hp - 40.0
	var hp_before: float = g.hp
	g.player.mana = g.player.max_mana
	g.player.spell_cd.clear()
	g.player.cast_cd = 0
	g._cast(g.player, "sovereign", foe.pos)
	for w3 in 60:
		await _frames(1)
	var healed: float = g.hp - hp_before
	g.hp = g.max_hp
	if not foe.dead:
		g.enemies.erase(foe)
	var ok4: bool = lost >= 50.0 and healed > 0.0
	rows.append("%sthe Sunlance took %.0f health off a foe; the Sovereign Bolt struck and healed you %.0f" % ["" if ok4 else "(!) ", lost, healed])
	ok = ok and ok4
	# ---- the gear: the Cinder Crown makes Fireball half again as strong
	var fb0: float = g.gear("spell_fireball")
	g.items["cindercrown"] = true
	var fb1: float = g.gear("spell_fireball")
	var ok5: bool = absf(fb1 / maxf(fb0, 0.01) - 1.5) < 0.01
	rows.append("%sthe Cinder Crown: Fireball x%.2f" % ["" if ok5 else "(!) ", fb1 / maxf(fb0, 0.01)])
	ok = ok and ok5
	g.player.inv = inv0
	g.known = known0
	g.learned = learned0
	g.items = items0
	g.test_god = god0
	_ok("each kind of world's core: its own material, its spell and gear taught on finding it, the core spells fly and strike", ok, "; ".join(rows))

## The audio pass (26 Nov, user: "can we do an audio pass"; audio.gd): every sound the scripts play exists (the
## staff's fizzle had been played but never made); no effect or ambience loop clips (more than a few samples at
## the limit) or is too quiet to hear; the twelve ambience loops are made on their thread and loop; the three buses
## are there with their effects; and where you are is worked out (on the surface here, with some wind playing).
func _test_audio() -> void:
	var au = g.audio
	var rows := []
	var ok := true
	# every name in audio.play("...") across the scripts
	var re := RegEx.new()
	re.compile("audio\\.play\\(\"([a-z_0-9]+)\"")
	var missing := []
	var used := {}
	for fn in DirAccess.get_files_at("res://scripts"):
		if not fn.ends_with(".gd"):
			continue
		var src := FileAccess.get_file_as_string("res://scripts/" + fn)
		for mt in re.search_all(src):
			var nm := mt.get_string(1)
			used[nm] = true
			if not au.sfx.has(nm) and not missing.has(nm):
				missing.append(nm)
	for st in ["soft", "stone", "sand", "snow", "wood", "metal"]:
		if not au.sfx.has("step_" + st):
			missing.append("step_" + st)
	ok = ok and missing.is_empty()
	rows.append("%d sounds played in the scripts, missing: %s" % [used.size(), str(missing)])
	# loud enough and never clipping
	# (26 Nov, crackling on another PC: no sample at the limit at all now, and every one-shot ends in silence)
	var clipped := []
	var quiet := []
	var abrupt := []
	for nm in au.sfx:
		var pk := _au_peak(au.sfx[nm])
		if pk[1] > 0.0:
			clipped.append("%s (%.1f%%)" % [nm, pk[1] * 100.0])
		if pk[2] > 0.002:
			abrupt.append("%s (%.3f)" % [nm, pk[2]])
		if pk[0] < 0.02:
			quiet.append("%s (%.3f)" % [nm, pk[0]])
	# the ambience: made on its thread, then started
	for k in 600:
		if not au._amb.is_empty():
			break
		await _frames(1)
	var amb_names: Array = au._amb.keys()
	var amb_loops := 0
	for nm2 in au._amb:
		var st2: AudioStreamWAV = au._amb[nm2][0].stream
		if st2.loop_mode == AudioStreamWAV.LOOP_FORWARD and st2.loop_end > 0:
			amb_loops += 1
		var pk2 := _au_peak(st2)
		if pk2[1] > 0.0:
			clipped.append("amb %s (%.1f%%)" % [nm2, pk2[1] * 100.0])
		if pk2[0] < 0.02:
			quiet.append("amb %s (%.3f)" % [nm2, pk2[0]])
	ok = ok and clipped.is_empty() and quiet.is_empty() and abrupt.is_empty() and amb_names.size() == 12 and amb_loops == 12
	rows.append("clipping: %s; too quiet: %s; ending on a step: %s" % [str(clipped), str(quiet), str(abrupt)])
	rows.append("ambience %d made (%d loop): %s" % [amb_names.size(), amb_loops, ", ".join(amb_names)])
	# buses and where you are
	var buses_ok := true
	for bn in [au.BUS_SFX, au.BUS_AMB, au.BUS_MUSIC]:
		var bi := AudioServer.get_bus_index(bn)
		buses_ok = buses_ok and bi >= 0 and AudioServer.get_bus_effect_count(bi) >= 1
	var limited := false
	for e in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, e) is AudioEffectHardLimiter:
			limited = true
	buses_ok = buses_ok and limited and au._players.size() == au.VOICES
	await _frames(240)
	var place := String(au.here["place"])
	var wind_v: float = float(au._amb["wind"][1]) if au._amb.has("wind") else 0.0
	ok = ok and buses_ok and place == "surface" and (g.audio.sfx_volume <= 0.0 or wind_v > 0.0)
	rows.append("buses %s; here: %s (biome %s, open %s, village %s, sea %.2f); wind %.3f; music list '%s'" % [buses_ok, place,
		au.here["biome"], au.here["open"], au.here["village"], float(au.here["sea"]), wind_v, au._list])
	_ok("the audio pass: every sound there, none clipping or too quiet, ambience loops, buses, where you are", ok, "; ".join(rows))

## Not in the full run: "mixrec" records what the game sends out (the Master bus, after its limiter) to
## saves/mix.wav, 20 s on the title (its music and wind) then 12 s in play with effects going off, to hunt
## crackling in the mix itself (26 Nov, user: "it happens a few seconds after opening menu maybe its the wind").
func _test_mixrec() -> void:
	var rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(0, rec)
	var ri := AudioServer.get_bus_effect_count(0) - 1
	var st0 := String(g.state)
	g.state = "title"
	g.ui.show_title(true)
	await _frames(30)
	rec.set_recording_active(true)
	await _frames(1200)
	g.ui.title.visible = false
	g.state = st0
	var names := ["boom", "zap", "hit", "step_stone", "dig", "spark", "fire", "land", "coin", "roar", "crack", "thunder"]
	for k in 720:
		if k % 20 == 0:
			g.audio.play(String(names[(k / 20) % names.size()]))
		await _frames(1)
	rec.set_recording_active(false)
	var w: AudioStreamWAV = rec.get_recording()
	var path: String = g._real_save_dir().path_join("mix.wav")
	var err := w.save_to_wav(path)
	AudioServer.remove_bus_effect(0, ri)
	_ok("mix recorded to saves/mix.wav", err == OK and w.data.size() > 0, "%d bytes at %d Hz, stereo %s, mix rate %d, latency %.1f ms" % [w.data.size(), w.mix_rate, w.stereo, int(AudioServer.get_mix_rate()), AudioServer.get_output_latency() * 1000.0])

## [the loudest sample (0..1), the share of samples at the limit, the last sample (0..1)] of a 16-bit wav
func _au_peak(w: AudioStreamWAV) -> Array:
	var d: PackedByteArray = w.data
	var n := d.size() / 2
	var mx := 0
	var at := 0
	for i in n:
		var v := absi(d.decode_s16(i * 2))
		mx = maxi(mx, v)
		if v >= 31990:
			at += 1
	var last := absi(d.decode_s16((n - 1) * 2)) if n > 0 else 0
	return [float(mx) / 32000.0, float(at) / float(maxi(1, n)), float(last) / 32000.0]

## The exploration loop (27 Nov; places.gd, docs/exploration.md): world-bound finds and workshop parts in every
## better piece's cost, the places to discover planned on a new world (archive, sanctum, fallen starship), found as
## you come near and marked, a sanctum's braziers kindled in their order opening its runestone wall, a place's
## chest holding an artifact, a Lectern's study teaching a recipe, rolled traits read by gear(), reforging at an
## anvil, and two drawing fixes: the skiff's sweep turn and creatures' steady feet.
func _test_loop() -> void:
	var lp_items0: Dictionary = g.items.duplicate(true)
	var lp_inv0: PackedInt32Array = g.player.inv.duplicate()
	var lp_pos0: Vector2 = g.player.pos
	var lp_vals0 := [g.max_hp, g.max_mana, g.mana_regen, g.hp]
	# costs: every piece wants its part, the better ones its world's finds (a heart's gear a Star Setting)
	var lp_bad := []
	for lp_id in Defs.GEAR:
		var lp_c: Dictionary = Defs.gear_cost(lp_id)
		var lp_t := Defs.gear_tier(lp_id)
		var lp_ok: bool = lp_c.has(Defs.gear_part(lp_id))
		var lp_rg := 0
		for lp_m in lp_c:
			if Defs.is_reagent(int(lp_m)):
				lp_rg += int(lp_c[lp_m])
		if lp_t >= 1 and int(Defs.gear_ores(lp_id)[0]) != Defs.VOIDESS:
			lp_ok = lp_ok and lp_rg >= 2
		if lp_t == 3:
			lp_ok = lp_ok and lp_c.has(Defs.SETTING)
		if lp_t >= 1 and not Defs.learn_of(g.recipe_by_id(lp_id)).has("study") and int(Defs.gear_ores(lp_id)[0]) != Defs.VOIDESS:
			lp_ok = false
		if not lp_ok:
			lp_bad.append(lp_id)
	var lp_mats := true
	for lp_mm in range(Defs.PHOENIXASH, Defs.SETTING + 1):
		lp_mats = lp_mats and String(Defs.NAMES[lp_mm]) != "" and Defs.PLACE[lp_mm] == 0 and Icons.mat(lp_mm) != null
	_ok("gear is a project: each piece wants a workshop part, the better ones their world's own finds", lp_bad.is_empty() and lp_mats and Defs.NM < 112,
		"bad %s; NM %d" % [str(lp_bad), Defs.NM])
	# places on this world (made new for the tests)
	var lp_pl: Array = g.places.list()
	var lp_kinds := {}
	for lp_p in lp_pl:
		lp_kinds[String(lp_p["kind"])] = true
	_ok("a new world hides places to discover: an archive, a sanctum and a fallen starship", lp_kinds.size() == 3 and g.planet_state.has("places"),
		"%d places: %s" % [lp_pl.size(), str(lp_kinds.keys())])
	if lp_kinds.size() < 3:
		return
	var lp_arch: Dictionary = {}
	var lp_sanc: Dictionary = {}
	var lp_wreck: Dictionary = {}
	for lp_p2 in lp_pl:
		match String(lp_p2["kind"]):
			"archive": lp_arch = lp_p2
			"sanctum": lp_sanc = lp_p2
			"wreck": lp_wreck = lp_p2
	# the archive: found as you come in, on the minimap, and pictured
	var lp_am: Vector2 = lp_arch["mid"]
	_go(lp_am - lp_am.normalized() * 20.0)
	await _frames(90)
	var lp_found: bool = g.places.found.has(String(lp_arch["id"]))
	var lp_mark := false
	for lp_mk in g.places.marks():
		lp_mark = lp_mark or String(lp_mk[1]) == String(lp_arch["name"])
	var lp_in: bool = not g.places.place_at(g.player.pos, "archive").is_empty()
	var lp_q: int = int(g.forge_quality("amber")[0])
	_shot("place_archive.png")
	_ok("coming into a Wisp Archive finds it: named, on the map, and forging in it is better", lp_found and lp_mark and lp_in and lp_q >= 1,
		"found %s, marked %s, inside %s, quality %d" % [str(lp_found), str(lp_mark), str(lp_in), lp_q])
	# its chest: an artifact
	var lp_a0: int = (g.items.get("artifacts", []) as Array).size()
	g.place_loot(lp_arch)
	var lp_a1: int = (g.items.get("artifacts", []) as Array).size()
	_ok("a place's chest holds an artifact to study", lp_a1 == lp_a0 + 1, "%d -> %d" % [lp_a0, lp_a1])
	# the sanctum: a wrong brazier puts them out, the right order opens the wall
	var lp_sm: Vector2 = lp_sanc["mid"]
	_go(lp_sm)
	await _frames(60)
	_shot("place_sanctum.png")
	var lp_sid := String(lp_sanc["id"])
	var lp_bz: Array = lp_sanc["braziers"]
	var lp_order: Array = lp_sanc["order"]
	var lp_by_g := {}
	for lp_k in lp_bz.size():
		lp_by_g[int(lp_bz[lp_k]["glyph"])] = lp_k
	var lp_w0 := int(g.places.stats["wrong"])
	g.places.kindle(lp_sid, int(lp_by_g[int(lp_order[1])]), g.player)
	var lp_wrong: bool = int(g.places.stats["wrong"]) == lp_w0 + 1 and (g.places.lit.get(lp_sid, []) as Array).is_empty()
	for lp_g in lp_order:
		g.places.kindle(lp_sid, int(lp_by_g[int(lp_g)]), g.player)
	await _frames(30)
	var lp_wr: Dictionary = lp_sanc["ward"]
	var lp_wmid: Vector2 = Defs.stamp_pos(int(lp_wr["y0"]) + int(lp_wr["h"]) / 2, int(lp_wr["ax"]), int(lp_wr["aw"]), Defs.k_of(int(lp_wr["x0"]) + int(lp_wr["w"]) / 2, int(lp_wr["ax"])))
	var lp_open_t: int = g.type_at(lp_wmid)
	_shot("place_sanctum_open.png")
	_ok("a sanctum's braziers: the wrong one puts them out, all three in their order break its runestone wall",
		lp_wrong and g.places.opened.has(lp_sid) and lp_open_t != Defs.RUNESTONE,
		"wrong %s, opened %s, the wall now %s" % [str(lp_wrong), str(g.places.opened.has(lp_sid)), Defs.NAMES[lp_open_t] if lp_open_t >= 0 and lp_open_t < Defs.NM else str(lp_open_t)])
	# the fallen starship, pictured from beside it
	var lp_wm: Vector2 = lp_wreck["mid"]
	_go(lp_wm + lp_wm.normalized() * 30.0)
	await _frames(60)
	_shot("place_wreck.png")
	_ok("a fallen starship lies half buried on the surface", g.places.found.has(String(lp_wreck["id"])), "found %s" % str(g.places.found.has(String(lp_wreck["id"]))))
	# a Lectern: an ocean artifact studied teaches an ocean piece not known yet
	_go(lp_pos0)
	await _frames(30)
	var lp_lect = g.workshops.add("lectern", g.player.pos + g.basis_r(g.view_angle()) * 14.0)
	g.learned.erase("pearlfins")
	var lp_arts: Array = g.items.get("artifacts", [])
	lp_arts.append(Defs.make_artifact("ocean", 4242))
	g.items["artifacts"] = lp_arts
	var lp_study: bool = g.workshops.study(lp_lect, lp_arts.size() - 1)
	lp_lect.prog = float(Defs.STUDY_TICKS) - 2.0
	for lp_t2 in 4:
		g.workshops.work_all()
	var lp_learned: bool = g.learned.has("pearlfins")
	g.workshops.open_st = lp_lect
	g.state = "station"
	g.ui.show_station(lp_lect)
	await _frames(10)
	_shot("lectern_panel.png")
	g.workshops.close()
	g.ui.hide_station()
	g.state = "play"
	g.workshops.list.erase(lp_lect)
	_ok("an artifact studied at a Lectern teaches a recipe of its world", lp_study and lp_learned and not g.workshops.studying(lp_lect),
		"laid %s, learned Pearl Fins %s" % [str(lp_study), str(lp_learned)])
	# (28 Nov; user: "i cant walk past the lectern like other workshops") you walk past a Lectern as past a kiln:
	# on level ground, each set down ahead, the mage walks right for 3 s
	var lw_rows := []
	var lw_ok := true
	var lw_st := _clear_stretch(int(fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * Defs.NS) + 40, 110, 50, 3)
	for lw_kind in ["kiln", "lectern"]:
		var lw_a0: float = (float(lw_st.x) + 8.5) / float(Defs.NS) * TAU
		var lw_as: float = (float(lw_st.x) + 50.5) / float(Defs.NS) * TAU
		_go(Vector2.from_angle(lw_a0) * (g.gpu.surf_at(lw_a0).x + 12.0))
		await _frames(20)
		var lw_s = g.workshops.add(lw_kind, Vector2.from_angle(lw_as) * (g.gpu.surf_at(lw_as).x + float(Defs.STATIONS[lw_kind]["h"]) * 0.5 + 1.0))
		await _frames(20)
		var lw_c0: float = fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * float(Defs.NS)
		g.test_move = 1 if g.basis_r(g.view_angle()).dot(Vector2.from_angle(lw_as) - Vector2.from_angle(lw_a0)) > 0.0 else -1
		await _frames(180)
		g.test_move = 0
		var lw_c1: float = fposmod(atan2(g.player.pos.y, g.player.pos.x), TAU) / TAU * float(Defs.NS)
		var lw_go: float = absf(wrapf(lw_c1 - lw_c0, -float(Defs.NS) * 0.5, float(Defs.NS) * 0.5))
		var lw_past: bool = lw_go > 60.0
		lw_ok = lw_ok and lw_past
		lw_rows.append("%s%s: walked %.0f columns (it stood 42 on), state %s" % ["" if lw_past else "(!) ", lw_kind, lw_go, g.state])
		g.workshops.list.erase(lw_s)
		g.state = "play"
	_ok("you walk past a Lectern as past any workshop", lw_ok, "; ".join(lw_rows))
	# rolled traits: read by gear(), the once-given ones given once; reforging at an anvil rolls them again
	g.roll_traits = true
	var lp_anv = g.workshops.add("anvil", g.player.pos + g.basis_r(g.view_angle()) * 10.0)
	g.items["amber"] = true
	g._trait_once(g.player, g.items.get("t_amber", []), -1.0)
	g.items["t_amber"] = [["swift", 1.0]]
	var lp_sp1: float = g.gear("speed")
	g.items["t_amber"] = []
	var lp_sp0: float = g.gear("speed")
	var lp_swift: bool = absf(lp_sp1 / lp_sp0 - Defs.trait_value("swift", 1.0)) < 0.001
	var lp_hp0: float = g.max_hp
	g.items["t_amber"] = [["hardy", 1.0]]
	g._trait_once(g.player, g.items["t_amber"], 1.0)
	var lp_rc: Dictionary = Defs.reforge_cost("amber")
	for lp_rm in lp_rc:
		g.player.inv[int(lp_rm)] += int(lp_rc[lp_rm])
	var lp_wc0: int = g.player.inv[Defs.WISPCELL]
	var lp_ref: bool = g.reforge_gear("amber")
	var lp_hard := 0.0
	for lp_tr in g.items.get("t_amber", []):
		if String(lp_tr[0]) == "hardy":
			lp_hard += Defs.trait_value("hardy", float(lp_tr[1]))
	var lp_hp_ok: bool = absf(g.max_hp - (lp_hp0 + lp_hard)) < 0.01
	var lp_q2: int = int(g.forge_quality("amber")[0])
	g.workshops.list.erase(lp_anv)
	g.roll_traits = false
	_ok("gear's rolled traits count in gear(), and reforging at an anvil rolls them again (paid, health given once)",
		lp_swift and lp_ref and g.player.inv[Defs.WISPCELL] == lp_wc0 - 1 and lp_hp_ok and lp_q2 >= 1,
		"swift %.3f/%.3f, reforged %s, health ok %s, quality at the anvil %d, now: %s" % [lp_sp1, lp_sp0, str(lp_ref), str(lp_hp_ok), lp_q2, g.gear_traits_text("amber")])
	# the skiff's turn: a sweep, never squeezed
	var lp_sk_ok := true
	if g.skiff != null:
		var lp_look0: float = g.skiff.look
		g.skiff.look = -float(g.skiff.facing)
		var lp_u0: float = g.skiff.sweep_u()
		g.skiff.look = 0.0
		var lp_um: float = g.skiff.sweep_u()
		g.skiff.look = float(g.skiff.facing)
		var lp_u1: float = g.skiff.sweep_u()
		g.skiff.look = lp_look0
		lp_sk_ok = lp_u0 < 0.01 and absf(lp_um - 0.5) < 0.01 and lp_u1 > 0.99 and absf(g.overlay._skiff_xf(g.skiff).x.length() * g.zoom - 1.0) < 0.05
	# steady feet: a cell's flicker under a creature standing in one column doesn't move it; a real fall does
	var lp_obj := RefCounted.new()
	var lp_ft: Vector2 = g.player.pos
	var lp_r := roundf(lp_ft.length())
	var lp_f0: float = g.overlay._steady_feet(lp_obj, Vector2.from_angle(atan2(lp_ft.y, lp_ft.x)) * lp_r, lp_r)
	var lp_f1: float = g.overlay._steady_feet(lp_obj, Vector2.from_angle(atan2(lp_ft.y, lp_ft.x)) * (lp_r - 0.5), lp_r - 1.0)
	var lp_f2: float = g.overlay._steady_feet(lp_obj, Vector2.from_angle(atan2(lp_ft.y, lp_ft.x)) * (lp_r - 3.0), lp_r - 3.0)
	_ok("the skiff turns by a sweep (never narrowed), and creatures' feet hold steady over the grid's flicker",
		lp_sk_ok and lp_f0 == lp_r and lp_f1 == lp_r and lp_f2 == lp_r - 3.0, "skiff %s, feet %.0f %.0f %.0f (from %.0f)" % [str(lp_sk_ok), lp_f0 - lp_r, lp_f1 - lp_r, lp_f2 - lp_r, lp_r])
	# a world made today is half as big again round (Defs.WORLD_GROWTH), and the wisp marks its heart on your map
	var lp_rad_ok: bool = absf(float(g.planet["radius"]) - 1304.0 * Defs.PLANET_SCALE * Defs.WORLD_GROWTH) < 1.0
	g.planet_state.erase("guided")
	g.places.guide()
	var lp_heart := false
	for lp_gu in g.planet_state.get("guided", []):
		lp_heart = lp_heart or String(lp_gu["kind"]) == "heart"
	g.places.guide()
	_ok("worlds are bigger (x%.1f), and the wisp marks the heart and the nearest dungeon or village" % Defs.WORLD_GROWTH, lp_rad_ok and lp_heart,
		"radius %.0f, %d columns; marked: %s" % [float(g.planet["radius"]), Defs.NS, str((g.planet_state.get("guided", []) as Array).map(func(e): return e["name"]))])
	# roots under the small plants, in the soil's first rows, near where you arrived
	var lp_sc := int(floor(fposmod(atan2(lp_pos0.y, lp_pos0.x), TAU) / TAU * Defs.NS))
	var lp_roots := 0
	for lp_off in [-400, -200, 200, 400]:
		var lp_c0: int = lp_sc + lp_off - 100
		var lp_gr: int = g.builds.ground_row(lp_c0 + 100)
		var lp_rr: Dictionary = g.gpu.read_rect(posmod(lp_c0, Defs.NS), lp_gr - 30, 200, 50)
		for lp_v in lp_rr["fg"]:
			if (lp_v & 255) == Defs.ROOT:
				lp_roots += 1
	_ok("plants root into the ground: threads of root under bushes and tufts", lp_roots > 20, "%d root cells in the soil" % lp_roots)
	# the Worldsong: a pit dug in open ground fills back in from its walls; a brick laid comes back with a plain staff
	var lp_st: Vector2i = _clear_stretch(lp_sc + 300, 40, 20, 3, 30)
	var lp_mend_ok := false
	var lp_brick_ok := false
	var lp_air0 := 0
	var lp_air1 := 0
	if _cs_found:
		var lp_pit := []
		for lp_pi in range(lp_st.x + 10, lp_st.x + 26):
			for lp_pj in range(lp_st.y + 4, lp_st.y + 16):
				lp_pit.append(Vector2i(lp_pi, lp_pj))
		g.stamps.append(Build.shape_stamp(lp_pit, Defs.AIR, false))
		await _frames(6)
		var lp_r0: Dictionary = g.gpu.read_rect(posmod(lp_st.x + 10, Defs.NS), lp_st.y + 4, 16, 12)
		for lp_v0 in lp_r0["fg"]:
			if (lp_v0 & 255) == Defs.AIR:
				lp_air0 += 1
		var lp_w := [lp_st.x + 18, lp_st.y + 10, 0.0, 0]
		for lp_k3 in 14:
			g.mending.run(lp_w, 1000)
			await _frames(2)
		var lp_r1: Dictionary = g.gpu.read_rect(posmod(lp_st.x + 10, Defs.NS), lp_st.y + 4, 16, 12)
		for lp_v1 in lp_r1["fg"]:
			if (lp_v1 & 255) == Defs.AIR:
				lp_air1 += 1
		lp_mend_ok = lp_air0 > 150 and lp_air1 < lp_air0 / 2
		_go(_cell_pos(lp_st.x + 18, lp_st.y - 12))
		await _frames(20)
		_shot("worldsong.png")
		# a brick laid with a plain staff (hardness 2 over its 1) still comes back to the satchel
		var lp_tier0: int = g.tier
		g.tier = 1
		var lp_bc := [Vector2i(lp_st.x + 30, lp_st.y - 2), Vector2i(lp_st.x + 31, lp_st.y - 2), Vector2i(lp_st.x + 30, lp_st.y - 3), Vector2i(lp_st.x + 31, lp_st.y - 3)]
		g.stamps.append(Build.shape_stamp(lp_bc, Defs.BRICK, false))
		await _frames(6)
		var lp_b0: int = g.player.inv[Defs.BRICK]
		var lp_rm: Dictionary = g.remove_cells(g.player, lp_bc, "front")
		await _frames(6)
		lp_brick_ok = int(lp_rm["n"]) == 4 and g.player.inv[Defs.BRICK] == lp_b0 + 4
		g.tier = lp_tier0
	_ok("the Worldsong mends a dug pit from its walls in, and what you laid comes back whatever your staff", lp_mend_ok and lp_brick_ok,
		"pit %d empty cells -> %d after 14 passes; brick taken back with a plain staff: %s" % [lp_air0, lp_air1, str(lp_brick_ok)])
	# the wisp's first words stay up long enough to read, and its asides wait their turn (user, 27 Nov: "the first
	# message from the wisp went away too quickly when i started a new game")
	var lp_wq = g.quest
	lp_wq.said_later.clear()
	var lp_long := "I'm your wisp. I'll guide you from here. " + "Dig down a little way first, and see what the ground holds. ".repeat(2)
	lp_wq.say(lp_long)
	var lp_t0: int = lp_wq.say_t
	lp_wq.say_later("An aside.")
	var lp_kept: bool = lp_wq.say_text == lp_long and lp_wq.said_later.size() == 1
	lp_wq.say_t = 1
	lp_wq.tick()
	lp_wq.tick()
	var lp_next: bool = lp_wq.say_text == "An aside."
	lp_wq.say_t = 0
	lp_wq.said_later.clear()
	_ok("the wisp's long lines stay up to be read, and its asides wait till it's done", lp_t0 > lp_wq.SAY_TICKS and lp_kept and lp_next,
		"%d letters up %.1f s (at least %.1f); the aside waited %s, then said %s" % [lp_long.length(), lp_t0 / 60.0, lp_wq.SAY_TICKS / 60.0, str(lp_kept), str(lp_next)])
	# (back as it was)
	g.items = lp_items0
	g.player.inv = lp_inv0
	g.max_hp = float(lp_vals0[0])
	g.max_mana = float(lp_vals0[1])
	g.mana_regen = float(lp_vals0[2])
	g.hp = float(lp_vals0[3])
	g.learn_all()
	_go(lp_pos0)
	await _frames(20)
