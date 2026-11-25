## Guardians are summoned, not met in lairs (user, 22 Nov: the guardian he found was stuck in the ground;
## "maybe we move away from gaurdian lairs and go to a summoning them mechanic?"; chose an altar you build
## and an offering you forge). Build a Summoning Altar (forged at the Wisp Forge, Workshops; set down from the satchel) in a biome that has a guardian,
## forge that guardian's sigil at the Wisp Forge (`Defs.sigil_recipes`: the land's own matter, a little
## copper and crystal), and press F at the altar: the sigil is laid on it, the altar wakes (a ritual of
## `RITUAL` ticks: runes turning, motes drawn in, the ground shaking) and the guardian comes at a clear spot
## beside it, already roused, to fight where the altar stands (its home, `ARENA` either side, `LEASH` past).
## A swimmer needs open water near the altar, a burrower soft ground. Walk away and it goes back where it
## came from after a while (the sigil comes back to you); beaten, it gives up its relic and hoard as before,
## and never comes again. One guardian at a time.
extends RefCounted

const BossAI := preload("res://scripts/boss_ai.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Ecology := preload("res://scripts/ecology.gd")

const RITUAL := 180          # ticks from the sigil laid to the guardian's coming
const ARENA := 170.0         # how far either side of where it came it fights
const LEASH := 520.0         # and how far it follows you out (230 till 24 Nov: "chase aggressively")
const CEIL := 110.0          # how high a flier goes
const NEAR_ALTAR := 60.0     # (how far from the altar it comes: room for both of you)

var game

func _init(g) -> void:
	game = g

static func sigil_key(biome: String) -> String:
	return "sigil_" + biome

## the biomes of this planet whose guardian can be called (and isn't beaten yet)
func callable_biomes() -> Array:
	var out := []
	if game.builds == null:
		return out
	var dead: Array = game.planet_state.get("bosses_dead", [])
	for b in game.builds.guardian_biomes:
		if Defs.BOSSES.has(b) and not dead.has(b) and not out.has(b):
			out.append(b)
	return out

## the guardian called from this planet's altars that's about now, or null
func active_guardian(biome := ""):
	for e in game.enemies:
		if e.boss and not e.dead and e.summoned != "" and (biome == "" or e.summoned == biome):
			return e
	return null

func _biome_title(b: String) -> String:
	return String(Defs.BIOMES[b]["name"]) if Defs.BIOMES.has(b) else b

## F at an altar: lay the sigil on it, if all is well; otherwise say what's wrong
func try_summon(m, st) -> String:
	var a := atan2(st.pos.y, st.pos.x)
	var biome: String = game._biome_name_at(a)
	var msg := ""
	if st.ritual > 0:
		msg = "The altar is already calling"
	elif not Defs.BOSSES.has(biome) or not game.builds.guardian_biomes.has(biome):
		msg = "No guardian answers in the %s" % _biome_title(biome)
	elif (game.planet_state.get("bosses_dead", []) as Array).has(biome):
		msg = "%s has already fallen" % Defs.BOSSES[biome]["name"]
	elif active_guardian() != null:
		msg = "%s is already here" % Defs.BOSSES[active_guardian().summoned]["name"]
	elif int(m.items.get(sigil_key(biome), 0)) <= 0:
		msg = "Lay a %s on the altar to call %s (forge it at the Wisp Forge)" % [Defs.sigil_name(biome), Defs.BOSSES[biome]["name"]]
	var spot := Vector2.INF
	if msg == "":
		spot = find_spot(st, biome, m)
		if spot == Vector2.INF:
			var bd: Dictionary = Defs.BOSSES[biome]
			if bd.get("swim", false) or bd.get("wet", false):
				msg = "%s needs open water near the altar" % bd["name"]
			elif String(bd.get("go", "")) == "burrow":
				msg = "%s needs soft ground near the altar" % bd["name"]
			else:
				msg = "There's no room for %s to come here" % bd["name"]
	if msg != "":
		game.ui.toast(msg, Color(1, 0.75, 0.55), 3.0)
		game.vfx.fizzle(st.pos)
		return msg
	m.items[sigil_key(biome)] = int(m.items[sigil_key(biome)]) - 1
	st.ritual = RITUAL
	st.summon = biome
	st.summon_at = spot
	var bd2: Dictionary = Defs.BOSSES[biome]
	game.ui.toast("You lay the %s on the altar. The ground trembles..." % Defs.sigil_name(biome), bd2["col"], 4.0)
	game.audio.play("rare", st.pos, 0.8)
	return ""

## Where the guardian of `biome` would come, near the altar and away from you: a clear box its size on the
## ground (a flier over it, a swimmer in open water, a burrower over soft ground). INF if nowhere.
func find_spot(st, biome: String, m) -> Vector2:
	var d: Dictionary = Defs.boss_enemy("boss_" + biome)
	var bd: Dictionary = Defs.BOSSES[biome]
	var w: float = float(d["w"]) + 2.0
	var h: float = float(d["h"]) + 2.0
	var go: String = bd.get("go", "walk")
	var swim: bool = bd.get("swim", false) or bd.get("wet", false)
	var a := atan2(st.pos.y, st.pos.x)
	var R: Vector2 = game.basis_r(a)
	var up: Vector2 = (st.pos as Vector2).normalized()
	var side: float = 1.0 if (st.pos - m.pos).dot(R) >= 0.0 else -1.0      # (the far side of the altar from you)
	game._use_grid(m)
	if swim:
		for dist in range(30, 260, 10):
			for s in [side, -side]:
				for dn in range(-120, 60, 8):
					var c: Vector2 = st.pos + R * s * float(dist) - up * float(dn)
					var l: Vector2 = game.to_grid(c)
					if not game.in_grid(c, w):
						continue
					if game.box_count(l.x - w * 0.5, l.y - h * 0.5, w, h, Defs.WATER) >= int(w * h * 0.85):
						return c
		return Vector2.INF
	for dist2 in [NEAR_ALTAR, NEAR_ALTAR + 30.0, NEAR_ALTAR - 20.0, NEAR_ALTAR + 60.0, NEAR_ALTAR + 90.0]:
		for s2 in [side, -side]:
			var p: Vector2 = st.pos + R * s2 * float(dist2)
			if go == "fly":
				var fc: Vector2 = p + up * (h + 30.0)
				var fl: Vector2 = game.to_grid(fc)
				if game.in_grid(fc, w) and not game.box_solid(fl.x - w * 0.5, fl.y - h * 0.5, w, h):
					return fc
				continue
			var gs := _stand_spot(p, w, h, up)
			if gs == Vector2.INF:
				continue
			if gs.distance_to(m.pos) < w * 0.5 + 12.0:
				continue
			if go == "burrow" and not Ecology.diggable_under(game, gs + (-up) * (h * 0.5 + 2.0)):
				continue
			return gs
	return Vector2.INF

## the highest spot near p (from a little above it down) where a w x h box stands clear on solid ground
func _stand_spot(p: Vector2, w: float, h: float, up: Vector2) -> Vector2:
	for dn in range(-30, 70):
		var c: Vector2 = p - up * float(dn)
		if not game.in_grid(c, w):
			continue
		var l: Vector2 = game.to_grid(c)
		if game.box_solid(l.x - w * 0.5, l.y - h * 0.5, w, h):
			continue
		if game.box_solid(l.x - w * 0.5 + 1.0, l.y + h * 0.5, w - 2.0, 2.0):
			return c
	return Vector2.INF

## every tick: the altars calling, and a called guardian left alone going back
func tick() -> void:
	for st in game.workshops.list:
		if st.kind == "altar" and st.ritual > 0:
			_ritual(st)

func _ritual(st) -> void:
	st.ritual -= 1
	var bd: Dictionary = Defs.BOSSES[st.summon]
	var col: Color = bd["col"]
	var k := 1.0 - float(st.ritual) / float(RITUAL)
	var top: Vector2 = st.pos + st.pos.normalized() * (st.h * 0.5 + 2.0)
	var clear := Color(col.r, col.g, col.b, 0.0)
	if st.ritual % 20 == 0:
		game.vfx.spawn(Vfx.RUNE, top, Vector2.ZERO, 26, col * Color(1, 1, 1, 0.8), clear, 6.0 + 6.0 * k, 9.0 + 8.0 * k, true, 0.0, 1.0, 0.07)
		game.vfx.spawn(Vfx.RUNE, st.summon_at, Vector2.ZERO, 26, col * Color(1, 1, 1, 0.6), clear, 8.0 + 14.0 * k, 12.0 + 20.0 * k, true, 0.0, 1.0, -0.05)
	if st.ritual % 3 == 0:
		# motes drawn in from all round to the altar, and rising where it will come
		var o: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(18.0, 34.0)
		game.vfx.spawn(Vfx.DOT, top + o, -o / 14.0, 14, col.lightened(0.4), clear, 1.0, 1.0, true, 0.0, 1.0)
		var o2: Vector2 = Vector2.from_angle(randf() * TAU) * randf() * (6.0 + 12.0 * k)
		game.vfx.spawn(Vfx.DOT, st.summon_at + o2, st.summon_at.normalized() * randf_range(0.2, 0.6), 30, col, clear, 1.0, 1.0, true, -0.01, 0.99)
	game.lights.append([top, 20.0 + 30.0 * k, col * (0.6 + 0.6 * k)])
	game.shake = maxf(game.shake, 2.0 + 5.0 * k)
	if st.ritual == 0:
		_arrive(st)

func _arrive(st) -> void:
	var biome: String = st.summon
	var bd: Dictionary = Defs.BOSSES[biome]
	var ge = game.spawn_enemy("boss_" + biome, st.summon_at)
	ge.home = st.summon_at
	ge.tether = LEASH
	ge.ceil = CEIL
	ge.arena = ARENA
	ge.summoned = biome
	ge.awake = true
	ge.act_cd = 60
	st.summon = ""
	var col: Color = bd["col"]
	for kk in 40:
		var dv: Vector2 = Vector2.from_angle(randf() * TAU) * randf_range(0.6, 2.2)
		game.vfx.spawn(Vfx.STREAK, st.summon_at, dv, 18 + randi() % 14, col.lightened(0.5), Color(col.r, col.g, col.b, 0.0), 1.5, 1.0, true, 0.02, 0.9)
	game.vfx.spawn(Vfx.RING, st.summon_at, Vector2.ZERO, 16, col, Color(col.r, col.g, col.b, 0.0), 2.0, 36.0)
	game.vfx.screen_flash(col, 0.5)
	game.vfx.light(st.summon_at, 80.0, col, 40)
	game.shake = 14.0
	game.ui.toast("%s, %s, answers your call!" % [String(bd["name"]).to_upper(), String(bd["title"]).to_upper()], col, 5.0)
	game.audio.play("roar", st.summon_at, 1.2)

## a called guardian nobody's fighting goes back (main `_update_enemies`): the sigil comes back to you
func dismiss(e) -> void:
	var bd: Dictionary = Defs.BOSSES[e.summoned]
	var key := sigil_key(e.summoned)
	game.player.items[key] = int(game.player.items.get(key, 0)) + 1
	game.vfx.screen_flash(bd["col"], 0.2)
	game.ui.toast("%s goes back to the wild. The sigil is yours again." % bd["name"], bd["col"], 4.0)
	e.dead = true

## saving: a guardian called and still about (or an altar still calling) isn't kept; its sigil is, so
## nothing is lost by saving mid-fight
func on_save(ps: Dictionary) -> void:
	var back := []
	var ge = active_guardian()
	if ge != null:
		back.append(ge.summoned)
	for st in game.workshops.list:
		if st.kind == "altar" and st.ritual > 0 and st.summon != "":
			back.append(st.summon)
	ps["summoned"] = back

func on_load(ps: Dictionary) -> void:
	for b in ps.get("summoned", []):
		var key := sigil_key(String(b))
		game.player.items[key] = int(game.player.items.get(key, 0)) + 1
	ps["summoned"] = []
