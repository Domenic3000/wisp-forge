extends "res://scripts/tests/building.gd"
## Checks of living towns: walking, talking, trade, their days, requests, rebuilding, trade per kind. (Part of the chain of test files: see tests.gd.)

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
	await _test_rebuild(tn_t)
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

func _test_town_days(t: Dictionary, mid: int) -> void:
	var tw = g.towns
	var mid_p: Vector2 = _cell_pos(mid, g.builds.ground_row(mid) - 14)
	var res := []
	for v in tw.folk:
		if not v.keeper and v.role != "guard" and int(v.town["seed"]) == int(t["seed"]):
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
	# (the one whose bed the test blocks with a chest sleeps on the floor, so isn't counted)
	var with_bed := watch.filter(func(wb): return not wb.bed.is_empty() and wb != tc_v).size()
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
	# lying on what's really there (user, 23 Nov: floating bedrolls, one up in a roof): a bedroll 4.5 over the
	# floor's top, anyone lying with room over them
	var floating := 0
	var boxed := 0
	var settled := 0
	for vs in watch:
		if not vs.lying or not g.in_grid(vs.pos, 24.0):
			continue
		await _frames(1)
		if vs.lie_ok:
			settled += 1
		var scol := int(round(fposmod(atan2(vs.pos.y, vs.pos.x), TAU) / TAU * float(Defs.NS) - 0.5))
		var srow := int(floor(float(Defs.R_TOP) - vs.pos.length()))
		if not tw._headroom(scol, srow, 3):
			boxed += 1
		if vs.bedroll:
			var sfr: int = g._floor_below(scol, srow, 12)
			var over: float = vs.pos.length() - (float(Defs.R_TOP) - float(sfr) - 1.0)
			if sfr < 0 or absf(over - 4.5) > 0.75:
				floating += 1
	print("[towns] asleep: %d settled on the world, %d floating, %d with no room over them" % [settled, floating, boxed])
	# (26 Nov, user: "a villager house got burned down while he was in it and he just stayed floating in the air
	# sleeping"): a sleeper with nothing under them any more wakes where they are and falls
	var woke_ok := true
	var wk_txt := "nobody asleep in sight"
	for vw in watch:
		if not vw.lying or not vw.lie_ok or not g.in_grid(vw.pos, 24.0):
			continue
		var wk_pos: Vector2 = vw.pos
		vw.pos = wk_pos + wk_pos.normalized() * 200.0          # (as if the house were gone from under them)
		var wk_up: float = vw.pos.length()
		for wf in 45:
			await _frames(1)
			if not vw.lying:
				break
		var woke: bool = not vw.lying
		for wf2 in 20:
			await _frames(1)
		var fell: bool = vw.pos.length() < wk_up - 2.0
		woke_ok = woke and fell
		wk_txt = "%s woke %s and fell %s" % [vw.name, woke, fell]
		vw.pos = wk_pos
		vw.vx = 0.0
		vw.vy = 0.0
		tw._lie_down(vw, true)
		break
	var tc_ok: bool = tc_v == null or (tc_v.lying and tc_v.bedroll)
	if tc_chest != null:
		g.chests.erase(tc_chest)
	g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("town_night.png"))
	# (they walk there: "stuck", stepping in after pushing on a wall for 90 ticks, is the exception)
	var night_ok: bool = not watch.is_empty() and home == watch.size() and slept > 0 and int(tw.stats.get("stuck", 0)) * 2 <= int(tw.stats.get("went_in", 0)) \
		and lying == watch.size() and (with_bed == 0 or in_bed > 0) and piled == 0 and over_chest == 0 and tc_ok and floating == 0 and boxed == 0 and woke_ok
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
			apart = maxf(apart, absf(tw._dc(float(tw._col(ap_a.pos)), ap_b.pos)))      # (on a slope it takes a moment more)
			if absf(ap_a.vx) < 0.05 and absf(ap_b.vx) < 0.05 and absf(ap_a.pos.length() - ap_b.pos.length()) < 10.0 \
					and absf(tw._dc(float(tw._col(ap_a.pos)), ap_b.pos)) < 5.0:
				ap_stacked += 1
	var apart_ok: bool = ap_a == null or ap_b == null or (apart >= 6.0 and ap_stacked < 20)
	morn_ok = morn_ok and apart_ok
	late.append("two put on one spot were %.0f cells apart within 5.5 s, then stood in one spot %d frames of 240" % [apart, ap_stacked])
	for v7 in watch:
		if tw.want_place(v7, tw.hour_at(v7.pos)).is_empty() and not v7.inside.is_empty():
			late.append("%s still in at %.1f h (%s, fade %d, talk %d)" % [v7.name, tw.hour_at(v7.pos), "in grid" if g.in_grid(v7.pos, 12.0) else "far", v7.fade, v7.talk_t])
	_ok("living towns: folk keep the hours (home asleep at night, out in the morning)", sched_ok and night_ok and morn_ok,
		"schedule %s%s; at dusk %s; at night %d of %d went home within %.1f s (%d asleep, %d lying down, %d of them in their beds; %d have beds; %d in one spot, %d over a chest; with a chest before %s's bed: %s; %d settled on the world, %d floating, %d with no room over them; with nothing under them: %s); in the morning %d of the %d who'd be out came out; %s%s" % [
		sched_ok, "" if sched_ok else " (" + sched_bad + ")", ", ".join(at_dusk), home, watch.size(), waited / 60.0, slept, lying, in_bed, with_bed, piled / 2, over_chest, tc_v.name if tc_v != null else "nobody", ("on the floor" if tc_v.bedroll else "in it") if tc_v != null else "-", settled, floating, boxed, wk_txt,
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
	tw.no_grow = true                     # (growing the village is `_test_guards`'s to check)
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
	tw.no_grow = false
	_ok("living towns: villagers' requests (bring, hunt, deliver) are taken, done and paid", ok, ("no asker in %s" % t["name"]) if asker == null else "; ".join(lines))

## each kind of planet's shops: the ward its danger needs, its fare, an imported ore, a better price for its own
## Villages rebuild what was knocked down (rebuild.gd; user, 23 Nov), and a planet planned again as on loading
## is the planet that was built (its villages where they stand, each house the same cell for cell: a plan made
## again used to drift from the first structure on, so villagers were set out for houses that weren't there).
func _test_rebuild(t: Dictionary) -> void:
	var rows := []
	var Bd = load("res://scripts/buildings.gd")
	var b2 = Bd.new()
	b2.plan(g.planet, g.gpu.surface, g.spawn_angle, fposmod(g.spawn_angle + PI, TAU), false)
	b2.finish_all()
	var grn: Dictionary = g.planet_state.get("grown", {})
	for tg in b2.towns:
		for q in int(grn.get(str(tg["seed"]), 0)):
			b2.grow_house(tg, q)            # (as towns.gd `replay_growth` does on loading)
	var same: bool = b2.towns.size() == g.builds.towns.size() and b2.labels.size() == g.builds.labels.size()
	var with_struct := 0
	var same_cells := true
	for k in mini(b2.towns.size(), g.builds.towns.size()):
		same = same and int(b2.towns[k]["x0"]) == int(g.builds.towns[k]["x0"]) and int(b2.towns[k]["seed"]) == int(g.builds.towns[k]["seed"])
		var hs2: Array = b2.towns[k]["houses"]
		var hs1: Array = g.builds.towns[k]["houses"]
		for q in mini(hs2.size(), hs1.size()):
			if (hs2[q] as Dictionary).has("struct"):
				with_struct += 1
				if (hs1[q] as Dictionary).has("struct"):
					same_cells = same_cells and (hs2[q]["struct"]["data"] as PackedInt32Array) == (hs1[q]["struct"]["data"] as PackedInt32Array)
	var ok1: bool = same and same_cells and with_struct > 0
	rows.append("%splanned again as on loading: %d villages, the same places %s, %d houses known cell for cell, the same cells %s" % [
		"" if ok1 else "(!) ", b2.towns.size(), same, with_struct, same_cells])
	# a house knocked about (its top half cleared), then its folk put it back
	var rb = g.towns.rebuild
	var h := {}
	for hh2 in t.get("houses", []):
		if (hh2 as Dictionary).has("struct"):
			h = hh2
			break
	var ok2 := false
	if h.is_empty():
		rows.append("(!) no house of %s knows its cells" % String(t.get("name", "?")))
	else:
		var st: Dictionary = h["struct"]
		var data: PackedInt32Array = st["data"]
		var w: int = st["w"]
		var hgt: int = st["h"]
		var r0: Dictionary = g.gpu.read_rect(int(st["x0"]), int(st["y0"]), w, hgt, int(st["ax"]), int(st["aw"]))
		var miss0: int = rb._missing(h, r0).size()
		var built: int = int(h.get("built_n", 0))
		var air := PackedInt32Array()
		air.resize(w * hgt)
		air.fill(0xffff)
		var cut := 0
		for j in hgt / 2:
			for i in w:
				var v: int = data[j * w + i]
				var fv: int = 0 if rb._want_front(v) != 0 else 255
				var bv: int = 0 if rb._want_back(v) != 0 else 255
				if fv == 0 or bv == 0:
					air[j * w + i] = fv | (bv << 8)
					cut += 1
		g.stamps.append({"x0": int(st["x0"]), "y0": int(st["y0"]), "w": w, "h": hgt, "data": air, "ax": int(st["ax"]), "aw": int(st["aw"])})
		await _frames(6)
		h.erase("rest_until")
		rb.job = {}
		rb.look_at(h, t)
		var started := false
		for f in 30:
			await _frames(1)
			if not rb.job.is_empty():
				started = true
				break
		var laid0: int = int(rb.stats["laid"])
		var waited := 0
		while not rb.job.is_empty() and waited < 3600:
			await _frames(30)
			waited += 30
		var r1: Dictionary = g.gpu.read_rect(int(st["x0"]), int(st["y0"]), w, hgt, int(st["ax"]), int(st["aw"]))
		var miss1: int = rb._missing(h, r1).size()
		ok2 = started and rb.job.is_empty() and miss1 <= miss0 + maxi(8, built / 50)
		rows.append("%sa house of %s knocked about (%d cells of %d cleared; %d missing before): rebuilding began %s, %d laid in %d ticks, %d missing after" % [
			"" if ok2 else "(!) ", String(t.get("name", "?")), cut, built, miss0, started, int(rb.stats["laid"]) - laid0, waited, miss1])
		g.get_viewport().get_texture().get_image().save_png(g._real_save_dir().path_join("shots").path_join("town_rebuilt.png"))
	print("[rebuild] " + "\n[rebuild] ".join(rows))
	_ok("villages rebuild the houses knocked down, and a planet planned again is the one that was built", ok1 and ok2, "; ".join(rows))

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

## Town guards and villages that grow (26 Nov): a living village's guards are out (as many as `guard_count`),
## and one goes for a foe that comes into the village and strikes it; then, with enough requests done there, the
## village grows: a new house planned at one end (planned again the same on loading), its folk build it course by
## course, furniture and all, a family moves in and another guard comes. A picture: saves/shots/town_grown.png.
func _test_guards() -> void:
	var gd_rows := []
	var gd_ok := true
	g.towns.test_guards = true
	var god0: bool = g.test_god
	g.test_god = true
	g.spawn_timer = 999999
	var t = null
	for tc in g.builds.towns:
		if bool(tc["living"]) and t == null:
			t = tc
	if t == null:
		_ok("town guards: out walking the village, after foes; a village grows as you help it", false, "no living village")
		g.test_god = god0
		return
	var mid := int(t["x0"]) + int(t["w"]) / 2
	var back: Vector2 = g.player.pos
	var time0: float = g.time
	g.time = g.towns.time_for_hour(_cell_pos(mid, 0), 12.0)
	for e0 in g.enemies.duplicate():
		if not e0.boss and e0.guard_id < 0:
			g.enemies.erase(e0)
	_go(_cell_pos(mid, g.builds.ground_row(mid) - 14))
	await _frames(90)
	var guards := []
	for v in g.towns.folk:
		if int(v.town["seed"]) == int(t["seed"]) and v.role == "guard" and not v.gone:
			guards.append(v)
	var want: int = g.towns.guard_count(t)
	var ok1: bool = guards.size() == want and want >= 1
	gd_rows.append("%s%s: %d guards out (%d wanted)" % ["" if ok1 else "(!) ", t["name"], guards.size(), want])
	gd_ok = gd_ok and ok1
	# a foe comes into the village: a guard goes for it and strikes it
	var hits0: int = int(g.towns.stats.get("guard_hits", 0))
	var foe = null
	var dealt := 0.0
	if not guards.is_empty():
		var gv = guards[0]
		for gq in guards:
			if gq.pos.distance_to(g.player.pos) < gv.pos.distance_to(g.player.pos):
				gv = gq
		_go(gv.pos + gv.pos.normalized() * 2.0)
		await _frames(20)
		# (out in the street a little way along, never inside a house)
		var fp: Vector2 = gv.pos
		var gcol: int = g.towns._col(gv.pos)
		for off in [36, -36, 50, -50, 64, -64, 24, -24]:
			if g.towns._house_at(t, float(gcol + int(off))).is_empty():
				fp = g.towns._street_at(float(gcol + int(off)))
				break
		foe = g.spawn_enemy("skeleton", g.free_spot(fp, 9.0, 18.0, 30))
		foe.awake = true
		var hp0: float = foe.hp
		for f in 360:
			await _frames(1)
			if foe.dead:
				break
		dealt = hp0 - foe.hp if not foe.dead else hp0
		_shot("town_guard.png")
		if not foe.dead:
			g.enemies.erase(foe)
	var hits: int = int(g.towns.stats.get("guard_hits", 0)) - hits0
	var ok2: bool = hits >= 1 and dealt > 0.0
	gd_rows.append("%sa skeleton in the village: struck %d times by the guards, %.0f health taken" % ["" if ok2 else "(!) ", hits, dealt])
	gd_ok = gd_ok and ok2
	# (26 Nov, user: "the town gaurds get stuck rapidly flipping left and right when im near them") a foe right
	# under a guard, in a cave below the street, is out of reach: not taken as a target, and the guard doesn't
	# spin on the spot over it
	if not guards.is_empty():
		var gu = guards[0]
		var below = g.spawn_enemy("skeleton", gu.pos - gu.pos.normalized() * 60.0)
		below.awake = true
		var tgt = g.towns._guard_target(gu)
		var flips := 0
		var f0: int = gu.facing
		for f3 in 90:
			await _frames(1)
			below.pos = gu.pos - gu.pos.normalized() * 60.0 + g.basis_r(atan2(gu.pos.y, gu.pos.x)) * (0.6 if f3 % 2 == 0 else -0.6)
			if gu.facing != f0:
				flips += 1
				f0 = gu.facing
		g.enemies.erase(below)
		var ok_b: bool = tgt != below and flips <= 1
		gd_rows.append("%sa foe in a cave right under a guard: %s, the guard turned %d times in 90 frames" % ["" if ok_b else "(!) ",
			"ignored" if tgt != below else "taken as a target", flips])
		gd_ok = gd_ok and ok_b
	# requests done: the village grows a house, its folk build it
	var rep: Dictionary = g.planet_state.get("town_rep", {})
	var grown0: Dictionary = (g.planet_state.get("grown", {}) as Dictionary).duplicate()
	var gk0: int = int(grown0.get(str(t["seed"]), 0))
	rep[str(t["seed"])] = {"n": int(g.towns.GROW_AT[mini(gk0, g.towns.GROW_AT.size() - 1)]), "last": "a test"}
	g.planet_state["town_rep"] = rep
	var nh0: int = (t["houses"] as Array).size()
	var w0: int = int(t["w"])
	var rb = g.towns.rebuild
	rb.job = {}
	rb._look = {}
	var grew: bool = g.towns._maybe_grow(int(t["seed"]))
	var nh: Dictionary = (t["houses"] as Array).back() if grew else {}
	var started := false
	for f2 in 60:
		await _frames(1)
		if not rb.job.is_empty():
			started = true
			break
	var waited := 0
	while not rb.job.is_empty() and waited < 6000:
		await _frames(30)
		waited += 30
	var built: bool = grew and started and rb.job.is_empty() and not nh.has("new")
	var furn := 0
	if not nh.is_empty():
		var st: Dictionary = nh["struct"]
		var r2: Dictionary = g.gpu.read_rect(int(st["x0"]), int(st["y0"]), int(st["w"]), int(st["h"]), int(st["ax"]), int(st["aw"]))
		for b in r2.get("bg", PackedInt32Array()):
			if (int(b) & 255) == Defs.DECOR:
				furn += 1
	var movers := 0
	var guards2 := 0
	for v2 in g.towns.folk:
		if int(v2.town["seed"]) == int(t["seed"]) and not v2.gone:
			if v2.house == nh and not nh.is_empty():
				movers += 1
			if v2.role == "guard":
				guards2 += 1
	var ok3: bool = built and (t["houses"] as Array).size() == nh0 + 1 and int(t["w"]) > w0 and furn > 10 and movers >= 1 and guards2 == mini(guards.size() + 1, g.towns.GUARDS_MAX)
	gd_rows.append("%sgrowing: planned %s, built %s in %d ticks (%d cells laid), %d furniture cells, houses %d -> %d, the village %d -> %d wide, %d moved in, guards %d -> %d" % [
		"" if ok3 else "(!) ", grew, built, waited, int(rb.stats["laid"]), furn, nh0, (t["houses"] as Array).size(), w0, int(t["w"]), movers, guards.size(), guards2])
	gd_ok = gd_ok and ok3
	if not nh.is_empty():
		var st2: Dictionary = nh["struct"]
		var hm: int = int(st2["x0"]) + int(st2["w"]) / 2
		_go(_cell_pos(hm, g.builds.ground_row(hm) - 14))
		await _frames(30)
		_shot("town_grown.png")
	# planned again as on loading: the grown house comes out the same
	var Bd = load("res://scripts/buildings.gd")
	var b2 = Bd.new()
	b2.plan(g.planet, g.gpu.surface, g.spawn_angle, fposmod(g.spawn_angle + PI, TAU), false)
	b2.finish_all()
	var same := false
	for t2 in b2.towns:
		if int(t2["seed"]) == int(t["seed"]) and not nh.is_empty():
			for q2 in gk0:
				b2.grow_house(t2, q2)
			var h2: Dictionary = b2.grow_house(t2, gk0)
			same = not h2.is_empty() and int(h2["struct"]["x0"]) == int(nh["struct"]["x0"]) and (h2["struct"]["data"] as PackedInt32Array) == (nh["struct"]["data"] as PackedInt32Array)
	gd_rows.append("%splanned again as on loading: the same house %s" % ["" if same else "(!) ", same])
	gd_ok = gd_ok and same
	# (the grown house stays, and so does its count: planned again on loading it comes back where it is)
	g.time = time0
	g.test_god = god0
	g.spawn_timer = 600
	_go(back)
	await _frames(30)
	g.towns.test_guards = false
	print("[guards] " + "\n[guards] ".join(gd_rows))
	_ok("town guards: out walking the village, after foes; a village grows as you help it", gd_ok, "; ".join(gd_rows))
