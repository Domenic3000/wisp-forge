## Space's own life and its anomalies (user, 23 Nov: "space creatures and anomalies"; the plan: creatures
## that live out between the stars, and anomalies each with a secret). Owned by space.gd (`vl`), streamed in
## and out with the sectors that hold them (galaxy.gd `_void_content`), in space's coordinates (`shift`).
##
## CREATURES (`beasts`, grouped in `groups`), all drawn in code as pixel art:
## - void mantas: great rays gliding in herds deep in nebulae. Peaceful; now and then a mote of Void
##   Essence drifts off a wingtip. Hurt one and its herd scatters.
## - lumen eels: glowing predators among deep fields' rocks. They patrol round their field, dart at you
##   (your skiff, or you on foot) and bite: the Wisp Shield takes a bite, else the hull is torn a little.
##   After a few bites, or badly hurt, they flee. The cannon (or your staff, on foot) kills them.
## - star jellies: drift along with a comet, pulsing with light; touch one and it stings.
## Killed, each leaves Void Essence (`motes`, drawn to you as you come near).
##
## ANOMALIES:
## - gravity wells (`wells`): a dark heart in a ring of fire, bending the starlight round it. It pulls you
##   in (harder the nearer); fall into its heart and it spits you out, battered. Skim past it fast and it
##   flings you on (a slingshot: `sling_t`, the Starsail's shedding waits). Essence crystals orbit close to
##   its edge. The Void Harness (`items["harness"]`): no well drags you past its edge, and the slingshot
##   is stronger.
## - rifts (`rifts`): paired tears in space (galaxy.gd `rift_pair`): fly into one, come out by its twin,
##   systems away. Both ends go on the map (`known`).
## - ancient monoliths (monolith.gd, rocks of kind "monolith"): strike their glyphs, root first, until all
##   burn; the seal crumbles, and its cache tells of a rift pair you haven't found.
extends RefCounted

const Galaxy := preload("res://scripts/galaxy.gd")
const Vfx := preload("res://scripts/vfx.gd")

const WELL_G := 20000.0         # a well's pull: WELL_G / d^2 a tick (d in cells), at most WELL_MAX
const WELL_MAX := 1.6
const WELL_R := 4500.0          # (felt this far out)
const CORE_R := 34.0            # its heart: fall in and you're spat out
const EDGE_R := 260.0           # with the Void Harness, nothing is dragged past this
const SLING_R := 900.0          # skim past within this, faster than SLING_V, and you're flung on
const SLING_V := 8.0
const SLING_K := 1.35           # (x the speed; the harness: SLING_KH)
const SLING_KH := 1.8
const SLING_MAX := 180.0
const SLING_MAXH := 260.0
const SLING_T := 420            # ticks the Starsail's shedding waits after a slingshot
const RIFT_IN := 36.0           # how near a rift's middle takes you through
const RIFT_OUT := 150.0         # you come out this far past its twin
const MOTE_REACH := 90.0        # essence drifts to you from this far
const CRYSTALS := 6

class Beast:
	var kind := ""             # "manta", "eel", "jelly"
	var gk := ""               # its group's key
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var ang := 0.0
	var hp := 10.0
	var hp_max := 10.0
	var state := ""            # eel: patrol / hunt / recoil / flee
	var t := 0
	var phase := 0.0           # (flap, undulation, pulse)
	var slot := Vector2.ZERO   # (a manta's place behind its leader; a jelly's angle and radius round its comet)
	var orb := 0.0             # (an eel's angle round its field)
	var orb_r := 400.0
	var bites := 0
	var cd := 0
	var hit_t := 0
	var trail := PackedVector2Array()   # (an eel's head, where it's been: its body follows)
	var dead := false
	var flash := 0

var sp                          # space.gd
var game
var beasts := []
var groups := {}                # key -> {"kind", "sect", "g" (galaxy point of its home), "col", "scared", "from", "goal", "orbit", "sg", "at", "prev"}
var wells := []                 # {"sect", "pos", "seed", "crystals": [[r, angle, ticks until back (0: there)]], "in": {}, "min": {}, "tilt"}
var rifts := []                 # {"sect", "pos", "pair", "end", "to" (galaxy), "ang"}
var motes := []                 # Void Essence drifting: [pos, vel, ticks left]
var known := {}                 # rift pair (String) -> [end 0 known, end 1 known]
var mono_state := {}            # a monolith's seed (String) -> its state (monolith.gd state())
var sling_t := 0
var allow_hostile := false      # (the test mode: eels and jellies leave you be unless a check asks)
var stats := {"kills": 0, "bites": 0, "stings": 0, "slings": 0, "spat": 0, "rifts": 0, "motes": 0, "crystals": 0, "glyphs": 0, "opened": 0}
var _rift_cd := 0
var _sear_cd := 0
var _early_note := 0
var _tex := {}

func _init(space) -> void:
	sp = space
	game = space.game

func hostile_ok() -> bool:
	return allow_hostile or not game.testing

# ------------------------------------------------------------- streaming ---

## a sector comes in: its wells, rift ends and creatures
func sector_in(s: Vector2i, key: String) -> void:
	var sg := Galaxy.sector_g(s)
	var cont: Array = Galaxy.sector_content(s)
	for ci in cont.size():
		var c: Dictionary = cont[ci]
		var at: Vector2 = c["at"]
		var g := PackedFloat64Array([sg[0] + at.x, sg[1] + at.y])
		var gk := "%s:%d" % [key, ci]
		match String(c["type"]):
			"well":
				var rng := RandomNumberGenerator.new()
				rng.seed = int(c["seed"])
				var cr := []
				for k in CRYSTALS:
					cr.append([rng.randf_range(150.0, 330.0), rng.randf() * TAU, 0])
				wells.append({"sect": key, "pos": sp.local_of(g), "seed": int(c["seed"]), "crystals": cr, "in": {}, "min": {},
					"tilt": rng.randf() * TAU, "spin": 1.0 if rng.randf() < 0.5 else -1.0})
			"rift":
				var rr := RandomNumberGenerator.new()
				rr.seed = hash([int(c["pair"]), int(c["end"]), 3])
				var to: PackedFloat64Array = Galaxy.rift_pair(int(c["pair"]))["b" if int(c["end"]) == 0 else "a"]
				rifts.append({"sect": key, "pos": sp.local_of(g), "pair": int(c["pair"]), "end": int(c["end"]), "to": to, "ang": rr.randf() * PI})
			"mantas", "eels", "jellies":
				_make_group(c, gk, key, g, sg)

func sector_out(key: String) -> void:
	for k in range(beasts.size() - 1, -1, -1):
		if String(groups.get(beasts[k].gk, {}).get("sect", "")) == key:
			beasts.remove_at(k)
	for gk in groups.keys():
		if String(groups[gk]["sect"]) == key:
			groups.erase(gk)
	for k2 in range(wells.size() - 1, -1, -1):
		if wells[k2]["sect"] == key:
			wells.remove_at(k2)
	for k3 in range(rifts.size() - 1, -1, -1):
		if rifts[k3]["sect"] == key:
			rifts.remove_at(k3)

func _make_group(c: Dictionary, gk: String, key: String, g: PackedFloat64Array, sg: PackedFloat64Array) -> void:
	var kind := {"mantas": "manta", "eels": "eel", "jellies": "jelly"}[String(c["type"])] as String
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["seed"])
	var gr := {"kind": kind, "sect": key, "g": g, "col": c.get("col", Color(0.6, 0.4, 1.0)), "scared": 0, "from": Vector2.ZERO,
		"goal": null, "sg": sg, "at": c["at"], "orbit": c.get("orbit", {}), "prev": Vector2.INF}
	groups[gk] = gr
	var home := _home(gr)
	for k in int(c["n"]):
		var b := Beast.new()
		b.kind = kind
		b.gk = gk
		b.phase = rng.randf() * TAU
		match kind:
			"manta":
				b.hp_max = 60.0
				b.slot = Vector2(-float(k + 1) * 46.0 * 0.5 - 20.0, (1.0 if k % 2 == 0 else -1.0) * float((k + 2) / 2) * 52.0) if k > 0 else Vector2.ZERO
				b.pos = home + Vector2(rng.randf_range(-200.0, 200.0), rng.randf_range(-200.0, 200.0))
				b.ang = rng.randf() * TAU
			"eel":
				b.hp_max = 36.0
				b.state = "patrol"
				b.orb = rng.randf() * TAU
				b.orb_r = rng.randf_range(320.0, 680.0)
				b.pos = home + Vector2.from_angle(b.orb) * b.orb_r
			"jelly":
				b.hp_max = 18.0
				b.slot = Vector2(rng.randf() * TAU, rng.randf_range(220.0, 640.0))
				b.pos = home + Vector2.from_angle(b.slot.x) * b.slot.y
				b.ang = rng.randf() * TAU
		b.hp = b.hp_max
		beasts.append(b)

## where a group lives now (a jelly swarm's comet moves on its loop)
func _home(gr: Dictionary) -> Vector2:
	var sg: PackedFloat64Array = gr["sg"]
	var at: Vector2 = gr["at"]
	if not (gr["orbit"] as Dictionary).is_empty():
		at += Galaxy.comet_at(gr["orbit"], game.time)
	return sp.local_of(PackedFloat64Array([sg[0] + at.x, sg[1] + at.y]))

func shift(d: Vector2) -> void:
	for b in beasts:
		b.pos += d
		for q in b.trail.size():
			b.trail[q] += d
	for gr in groups.values():
		if gr["goal"] != null:
			gr["goal"] = (gr["goal"] as Vector2) + d
		gr["from"] = (gr["from"] as Vector2) + d
		if gr["prev"] != Vector2.INF:
			gr["prev"] = (gr["prev"] as Vector2) + d
	for w in wells:
		w["pos"] = (w["pos"] as Vector2) + d
	for r in rifts:
		r["pos"] = (r["pos"] as Vector2) + d
	for mo in motes:
		mo[0] = (mo[0] as Vector2) + d

## (out of space, or fallen out there: nothing goes on hunting you)
func calm() -> void:
	for b in beasts:
		if b.kind == "eel":
			b.state = "patrol"
			b.bites = 0
	sling_t = 0

# ------------------------------------------------------------------ ticks ---

func tick(focus: Vector2) -> void:
	if _rift_cd > 0:
		_rift_cd -= 1
	if _sear_cd > 0:
		_sear_cd -= 1
	if sling_t > 0:
		sling_t -= 1
	_update_beasts(focus)
	_update_motes()
	_update_crystals()
	for a in sp.rocks:
		if a.kind == "monolith":
			a.tick_glyphs()
	_rifts_check(focus)
	_meet(focus)
	# the Mantle of the Void: out here your mana comes back faster
	for m in game.players:
		if not m.dead:
			var k: float = game.gear("space_mana", m)
			if k > 1.0:
				m.mana = minf(m.max_mana, m.mana + m.mana_regen * (k - 1.0))

## the first time you come upon each kind of thing: a word about it
func _meet(focus: Vector2) -> void:
	if game.frame % 20 != 7:
		return
	for w in wells:
		if (w["pos"] as Vector2).distance_to(focus) < 2600.0:
			_first("well", "A gravity well: the light bends round it. It pulls you in; skim past it fast and it flings you on", Color(1.0, 0.75, 0.45))
	for r in rifts:
		if (r["pos"] as Vector2).distance_to(focus) < 2000.0:
			var pk := str(r["pair"])
			var kn: Array = known.get(pk, [false, false])
			if not kn[int(r["end"])]:
				kn[int(r["end"])] = true
				known[pk] = kn
				game.ui.toast("A rift, torn in space: fly into it and come out by its twin, far off (it's on your map)", Color(0.85, 0.6, 1.0), 5.0)
	for a in sp.rocks:
		if a.kind == "monolith" and a.pos.distance_to(focus) < 1500.0:
			_first("monolith", "An ancient monolith, carved with glyphs. Strike them (the cannon, or your staff on foot) and see what wakes", Color(0.8, 0.65, 1.0))
	for b in beasts:
		if b.pos.distance_to(focus) < 1400.0:
			match b.kind:
				"manta": _first("manta", "Void mantas, gliding through the nebula. Essence drifts from their wings", Color(0.7, 0.6, 1.0))
				"eel": _first("eel", "Lumen eels among the rocks. They bite hulls", Color(0.5, 1.0, 0.85))
				"jelly": _first("jelly", "Star jellies, drifting with the comet. Don't touch", Color(1.0, 0.7, 0.95))

func _first(what: String, txt: String, col: Color) -> void:
	if game.items.has("met_" + what):
		return
	game.items["met_" + what] = true
	game.ui.toast(txt, col, 5.0)

## who it would go for: the skiff (with you aboard) or you, out in the open; null if neither
func _prey() -> Variant:
	var m = game.player
	if m.dead or sp.in_station != null or not sp.active:
		return null
	if m.aboard != null:
		return game.skiff
	return m

func _update_beasts(focus: Vector2) -> void:
	var prey = _prey()
	var tgt: Vector2 = prey.pos if prey != null else Vector2.INF
	for gr in groups.values():
		if int(gr["scared"]) > 0:
			gr["scared"] = int(gr["scared"]) - 1
	var leaders := {}
	for k in range(beasts.size() - 1, -1, -1):
		var b: Beast = beasts[k]
		if b.dead:
			beasts.remove_at(k)
			continue
		if b.hit_t > 0:
			b.hit_t -= 1
		if b.cd > 0:
			b.cd -= 1
		if b.flash > 0:
			b.flash -= 1
		if b.pos.distance_to(focus) > 9000.0 and b.kind != "jelly":
			continue                                # (far off: it waits)
		var gr: Dictionary = groups.get(b.gk, {})
		if gr.is_empty():
			continue
		match b.kind:
			"manta":
				if not leaders.has(b.gk):
					leaders[b.gk] = b
				_manta(b, gr, leaders[b.gk])
			"eel": _eel(b, gr, prey, tgt)
			"jelly": _jelly(b, gr, prey, tgt)
	# (a jelly swarm's comet: how far it moved this tick)
	for gr2 in groups.values():
		if gr2["kind"] == "jelly":
			gr2["prev"] = _home(gr2)

func _steer(b: Beast, want: Vector2, acc: float) -> void:
	b.vel += (want - b.vel).limit_length(acc)

## away from the wells round p
func _shy(p: Vector2) -> Vector2:
	var out := Vector2.ZERO
	for w in wells:
		var o: Vector2 = p - (w["pos"] as Vector2)
		var d := o.length()
		if d < 1800.0 and d > 1.0:
			out += o / d * (1800.0 - d) / 1800.0 * 2.5
	return out

func _manta(b: Beast, gr: Dictionary, lead: Beast) -> void:
	var want := Vector2.ZERO
	var spd := 1.6
	if int(gr["scared"]) > 0:
		var away: Vector2 = b.pos - (gr["from"] as Vector2)
		want = away.normalized() * 4.2 + Vector2.from_angle(b.phase * 0.3) * 0.6
		spd = 4.2
	elif b == lead:
		var home := _home(gr)
		if gr["goal"] == null or (gr["goal"] as Vector2).distance_to(b.pos) < 300.0 or (gr["goal"] as Vector2).distance_to(home) > 3200.0:
			gr["goal"] = home + Vector2.from_angle(randf() * TAU) * randf_range(600.0, 2600.0)
		want = ((gr["goal"] as Vector2) - b.pos).normalized() * spd
	else:
		var at: Vector2 = lead.pos + b.slot.rotated(lead.ang)
		want = lead.vel + (at - b.pos) * 0.02
		spd = 3.0
	want += _shy(b.pos)
	_steer(b, want.limit_length(spd * 1.2), 0.035)
	b.pos += b.vel
	if b.vel.length() > 0.2:
		b.ang = lerp_angle(b.ang, b.vel.angle(), 0.04)
	b.phase += 0.045 + b.vel.length() * 0.012
	# now and then a mote of essence drifts off a wingtip
	if randf() < 1.0 / 800.0:
		var tip := b.pos + Vector2(-8.0, (1.0 if randf() < 0.5 else -1.0) * 24.0).rotated(b.ang)
		_drop(tip, b.vel * 0.3, 1)
	if randf() < 1.0 / 2400.0 and b.pos.distance_to(game.player.pos) < 1600.0:
		game.audio.play("song", b.pos, 0.5)

func _eel(b: Beast, gr: Dictionary, prey, tgt: Vector2) -> void:
	var home := _home(gr)
	b.t += 1
	var want := Vector2.ZERO
	var dist: float = b.pos.distance_to(tgt) if prey != null else 1e9
	match b.state:
		"patrol":
			b.orb += 0.004 * (1.0 if b.orb_r < 500.0 else -1.0)
			var at := home + Vector2.from_angle(b.orb) * b.orb_r
			want = (at - b.pos).limit_length(2.4)
			if hostile_ok() and prey != null and dist < 1000.0 and tgt.distance_to(home) < 2200.0 and b.cd == 0:
				b.state = "hunt"
				b.t = 0
				game.audio.play("hiss", b.pos, 0.6)
		"hunt":
			if prey == null or tgt.distance_to(home) > 2600.0 or b.t > 900:
				b.state = "patrol"
				b.cd = 240
			else:
				var pv: Vector2 = game.skiff.vel if prey == game.skiff else sp.vel
				var lead: Vector2 = tgt + pv * clampf(dist / 5.0, 0.0, 30.0)
				var d := (lead - b.pos).normalized()
				want = d * 4.8 + d.orthogonal() * sin(float(b.t) * 0.18) * 1.4
				if _bites(b, prey, tgt):
					b.state = "recoil"
					b.t = 0
		"recoil":
			want = (b.pos - tgt).normalized() * 3.5 if prey != null else (home - b.pos).limit_length(2.0)
			if b.t > 80:
				b.state = "hunt" if b.bites < 3 else "flee"
				b.t = 0
		"flee":
			var out := (b.pos - home).normalized() if b.pos.distance_to(home) > 5.0 else Vector2.RIGHT
			want = (out * 1500.0 + home - b.pos).limit_length(4.0)
			if b.t > 1500:
				b.state = "patrol"
				b.bites = 0
				b.t = 0
	want += _shy(b.pos)
	_steer(b, want, 0.14)
	b.pos += b.vel
	if b.vel.length() > 0.1:
		b.ang = b.vel.angle()
	b.phase += 0.12 + b.vel.length() * 0.05
	if b.trail.is_empty() or b.trail[0].distance_to(b.pos) > 1.5:
		b.trail.insert(0, b.pos)
		if b.trail.size() > 44:
			b.trail.resize(44)

## an eel at its prey: a bite (true if it bit)
func _bites(b: Beast, prey, tgt: Vector2) -> bool:
	var head := b.pos + Vector2.from_angle(b.ang) * 4.0
	var sk = game.skiff
	var bit := false
	if prey == sk:
		bit = sk.solid_at(head) or head.distance_to(sk.pos) < float(mini(sk.w, sk.h)) * 0.45
		if bit:
			# (its jaws close on the hull where it meets it)
			sp.skiff_hit(sk, sp._first_cell(sk, head - Vector2.from_angle(b.ang) * 8.0, sk.pos), 2.2, 5.0)
	else:
		bit = head.distance_to(tgt) < 9.0
		if bit:
			game.hurt(prey, 7.0, Vector2.from_angle(b.ang) * 3.0, true)
	if bit:
		b.bites += 1
		stats["bites"] += 1
		game.audio.play("chitter", head, 0.8)
		for k in 6:
			game.vfx.spawn(Vfx.DOT, head, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.2), 18, Color(0.6, 1.0, 0.9), Color(0.2, 0.6, 0.6, 0.0), 1.5, 0.5, true, 0.0, 0.93)
	return bit

func _jelly(b: Beast, gr: Dictionary, prey, tgt: Vector2) -> void:
	var home := _home(gr)
	# (carried along in its comet's wake)
	if gr["prev"] != Vector2.INF:
		b.pos += home - (gr["prev"] as Vector2)
	b.slot.x += 0.0009
	var at := home + Vector2.from_angle(b.slot.x) * b.slot.y
	var ph0 := fposmod(b.phase, TAU)
	b.phase += TAU / 95.0
	if fposmod(b.phase, TAU) < ph0:
		# a pulse: a push toward where it drifts, the bell first
		var to := at - b.pos
		var dir := to.normalized() if to.length() > 1.0 else Vector2.from_angle(b.ang)
		b.vel += dir * 1.5 * clampf(to.length() / 300.0, 0.3, 2.5)
		b.flash = 14
	b.vel *= 0.975
	b.vel += _shy(b.pos) * 0.02
	b.pos += b.vel
	if b.vel.length() > 0.05:
		b.ang = lerp_angle(b.ang, b.vel.angle(), 0.05)
	# touch it and it stings
	if prey != null and b.cd == 0 and hostile_ok():
		var sk = game.skiff
		var hit := false
		if prey == sk:
			hit = sk.solid_at(b.pos) or b.pos.distance_to(sk.pos) < float(mini(sk.w, sk.h)) * 0.45 + 6.0
			if hit:
				sp.skiff_hit(sk, b.pos, 1.4, 3.0)
		elif b.pos.distance_to(tgt) < 13.0:
			hit = true
			game.hurt(prey, 6.0, (tgt - b.pos).normalized() * 3.0, true)
		if hit:
			b.cd = 90
			b.flash = 20
			stats["stings"] += 1
			game.audio.play("zap", b.pos, 0.5)
			game.vfx.spawn(Vfx.RING, b.pos, Vector2.ZERO, 12, Color(1.0, 0.75, 1.0), Color(0.8, 0.4, 1.0, 0.0), 4.0, 20.0)

# ------------------------------------------------------------- hurting ---

## a cannon bolt at p: true if it hit a creature (and hurt it)
func shot_hit(p: Vector2, dmg: float) -> bool:
	var b = beast_at(p, 0.0)
	if b == null:
		return false
	hurt_beast(b, dmg, p)
	return true

## the creature at p (within `pad`), or null
func beast_at(p: Vector2, pad: float) -> Variant:
	for b in beasts:
		if b.dead or b.pos.distance_to(p) > 70.0 + pad:
			continue
		match b.kind:
			"manta":
				var l: Vector2 = (p - b.pos).rotated(-b.ang)
				if (l.x / 20.0) * (l.x / 20.0) + (l.y / 26.0) * (l.y / 26.0) < 1.0 + pad * 0.08:
					return b
			"eel":
				for sg in _segments(b):
					if (sg[0] as Vector2).distance_to(p) < float(sg[1]) + 1.5 + pad:
						return b
			"jelly":
				if b.pos.distance_to(p) < 9.0 + pad:
					return b
	return null

func hurt_beast(b: Beast, dmg: float, from: Vector2) -> void:
	if b.dead:
		return
	b.hp -= dmg
	b.hit_t = 8
	var gr: Dictionary = groups.get(b.gk, {})
	match b.kind:
		"manta":
			if not gr.is_empty():
				gr["scared"] = 420
				gr["from"] = from
		"eel":
			if b.hp < b.hp_max * 0.5:
				b.state = "flee"
				b.t = 0
			elif hostile_ok() and b.state == "patrol":
				b.state = "hunt"
				b.t = 0
	if b.hp <= 0.0:
		_kill(b)

func _kill(b: Beast) -> void:
	b.dead = true
	stats["kills"] += 1
	var n: int = {"manta": 6, "eel": 3, "jelly": 2}[b.kind]
	for k in n:
		_drop(b.pos + Vector2.from_angle(randf() * TAU) * randf_range(2.0, 10.0), b.vel * 0.4 + Vector2.from_angle(randf() * TAU) * randf_range(0.1, 0.6), 1)
	var col: Color = {"manta": Color(0.7, 0.55, 1.0), "eel": Color(0.5, 1.0, 0.85), "jelly": Color(1.0, 0.7, 0.95)}[b.kind]
	for k2 in 24:
		game.vfx.spawn(Vfx.DOT, b.pos, b.vel + Vector2.from_angle(randf() * TAU) * randf_range(0.3, 1.8), 30 + randi() % 30, col, Color(col.r, col.g, col.b, 0.0), 2.0, 0.5, true, 0.0, 0.95)
	game.vfx.spawn(Vfx.GLOW, b.pos, b.vel, 20, Color(col.r, col.g, col.b, 0.8), Color(col.r, col.g, col.b, 0.0), 8.0, 26.0)
	game.audio.play("song" if b.kind == "manta" else "hiss", b.pos, 0.6)
	if b.kind == "manta":
		game.ui.toast("The manta's light goes out, and its herd scatters", Color(0.7, 0.6, 1.0), 3.0)

## Your staff on foot, out here (hold dig: space.gd `_mine_at`): it sears a creature where it reaches,
## and wakes a monolith's glyph. Mana a tick while it sears.
func sear(m, p: Vector2, r: float) -> void:
	var b = beast_at(p, r)
	if b != null and m.mana > 0.5:
		hurt_beast(b, 0.5, p)
		m.mana -= 0.15
		if game.frame % 3 == 0:
			game.vfx.spawn(Vfx.DOT, p, Vector2.from_angle(randf() * TAU) * 0.6, 16, Color(0.75, 0.9, 1.0), Color(0.5, 0.6, 1.0, 0.0), 1.5, 0.5, true, 0.0, 0.92)
	if _sear_cd == 0:
		for a in sp._rocks_near(p, r + 4.0):
			if a.kind == "monolith":
				var k: int = a.glyph_at(p, r + 10.0)
				if k >= 0 and m.mana >= 6.0:
					var res := strike(a, k, p)
					if res != "" and res != "burning":
						m.mana -= 6.0
					_sear_cd = 24

## a cannon bolt at a monolith (flying along v): the glyph it was heading for, if any, is struck (the glyphs
## lie about 17 cells in from the face it hit: a bolt coming in at a slant still finds the one it was aimed at)
func strike_at(a, p: Vector2, v: Vector2) -> void:
	var q := p + v.normalized() * 18.0 if v.length() > 0.01 else p
	strike(a, a.glyph_at(q, 24.0), p)

func strike(a, k: int, p: Vector2) -> String:
	var res: String = a.strike(k)
	match res:
		"lit":
			stats["glyphs"] += 1
			var gp: Vector2 = a.glyph_pos(k)
			game.audio.play("glyph", gp, 0.8)
			game.vfx.spawn(Vfx.RING, gp, Vector2.ZERO, 20, Color(0.85, 0.65, 1.0), Color(0.5, 0.3, 1.0, 0.0), 4.0, 22.0)
			game.vfx.spawn(Vfx.GLOW, gp, Vector2.ZERO, 26, Color(0.75, 0.5, 1.0, 0.8), Color(0.5, 0.3, 1.0, 0.0), 6.0, 14.0)
		"early":
			game.vfx.fizzle(p)
			if game.frame - _early_note > 600:
				_early_note = game.frame
				game.ui.toast("The glyph sputters and stays dark. They seem to wake from the root up", Color(0.8, 0.65, 1.0), 3.5)
		"open":
			stats["glyphs"] += 1
			stats["opened"] += 1
			mono_state[str(a.seed_)] = a.state()
			game.audio.play("rift", a.pos, 0.9)
			game.audio.play("rare", null, 0.8)
			game.shake = maxf(game.shake, 6.0)
			var sc: Vector2 = a.cache_pos(a.caches[0]) if not a.caches.is_empty() else a.pos
			for q in 40:
				game.vfx.spawn(Vfx.DOT, sc, Vector2.from_angle(randf() * TAU) * randf_range(0.3, 2.0), 40 + randi() % 30, Color(0.5, 0.45, 0.6), Color(0.2, 0.15, 0.3, 0.0), 2.0, 1.0, false, 0.0, 0.96)
			game.vfx.spawn(Vfx.RUNE, sc, Vector2.ZERO, 60, Color(0.8, 0.6, 1.0), Color(0.5, 0.3, 1.0, 0.0), 10.0, 40.0)
			game.ui.toast("Every glyph burns. The seal crumbles: \"%s\"" % a.lore, Color(0.85, 0.7, 1.0), 6.0)
	return res

## a monolith comes in: as you left it
func mono_in(a) -> void:
	var st: Dictionary = mono_state.get(str(a.seed_), {})
	if not st.is_empty():
		a.apply_state(st)

func mono_out(a) -> void:
	var st: Dictionary = a.state()
	if bool(st["open"]) or bool(st["looted"]):
		mono_state[str(a.seed_)] = st

## a monolith's cache: what it holds (space.gd `_loot` calls this for kind "monolith")
func mono_loot(_m, a, give: Callable, got: Array) -> void:
	give.call(Defs.VOIDESS, randi_range(8, 14))
	give.call(Defs.STARIRON, randi_range(3, 6))
	var c := randi_range(30, 70)
	game.items["coins"] = int(game.items.get("coins", 0)) + c
	got.append("%d ancient coins" % c)
	if randf() < 0.5:
		game._chest_recipe(3)
	mono_state[str(a.seed_)] = a.state()
	reveal_rift()

## the place of the nearest rift pair you haven't found: both its ends go on your map
func reveal_rift() -> bool:
	var g: PackedFloat64Array = sp.player_g()
	var best := -1
	var bd := 1e30
	for r in Galaxy.systems_near(g[0], g[1], Defs.SYS_GAP * 4.0):
		var rp := Galaxy.rift_pair(int(r))
		if rp.is_empty():
			continue
		var kn: Array = known.get(str(r), [false, false])
		if kn[0] and kn[1]:
			continue
		var a: PackedFloat64Array = rp["a"]
		var d := (a[0] - g[0]) * (a[0] - g[0]) + (a[1] - g[1]) * (a[1] - g[1])
		if d < bd:
			bd = d
			best = int(r)
	if best < 0:
		return false
	known[str(best)] = [true, true]
	var rp2 := Galaxy.rift_pair(best)
	game.ui.toast("Carved inside: a map of the stars. A rift near the %s system, its twin by %s (on your map)" % [Galaxy.star_name(best), Galaxy.star_name(int(rp2["twin"]))], Color(0.85, 0.65, 1.0), 6.0)
	return true

# ------------------------------------------------------------- essence ---

func _drop(p: Vector2, v: Vector2, _n: int) -> void:
	motes.append([p, v, 3600])

func _update_motes() -> void:
	var m = game.player
	var at: Vector2 = game.skiff.pos if m.aboard != null and game.skiff != null else m.pos
	var reach: float = MOTE_REACH * (2.0 if m.items.has("wisp_hands") else 1.0) + (float(maxi(game.skiff.w, game.skiff.h)) * 0.5 if m.aboard != null and game.skiff != null else 0.0)
	for k in range(motes.size() - 1, -1, -1):
		var mo: Array = motes[k]
		var p: Vector2 = mo[0]
		var v: Vector2 = mo[1]
		var o := at - p
		var d := o.length()
		if not m.dead and d < reach:
			v += o / maxf(d, 1.0) * 0.35          # (drawn to you)
		v *= 0.97
		p += v
		mo[0] = p
		mo[1] = v
		mo[2] = int(mo[2]) - 1
		if not m.dead and d < (12.0 if m.aboard == null else reach * 0.35):
			m.inv[Defs.VOIDESS] += 1
			stats["motes"] += 1
			game.audio.play("coin", p, 0.35)
			motes.remove_at(k)
		elif int(mo[2]) <= 0:
			motes.remove_at(k)

# --------------------------------------------------------------- wells ---

## A body at p moving at v near the wells (who: "skiff" or "mage"): their pull, the harness's edge, the
## slingshot, the heart that spits you out. The velocity it moves on with.
func well_force(p: Vector2, v: Vector2, who: String) -> Vector2:
	var harness: bool = game.items.has("harness")
	for w in wells:
		var o: Vector2 = (w["pos"] as Vector2) - p
		var d := o.length()
		if d > WELL_R:
			w["in"].erase(who)
			w["min"].erase(who)
			continue
		var dir := o / maxf(d, 0.001)
		var a := minf(WELL_G / maxf(d * d, 1.0), WELL_MAX)
		if harness and d < EDGE_R * 1.6:
			# (the Void Harness: the pull dies away toward the edge, and inside it pushes you out)
			a *= clampf((d - EDGE_R) / (EDGE_R * 0.6), 0.0, 1.0)
			if d < EDGE_R:
				v -= dir * 0.5 * (EDGE_R - d) / EDGE_R + dir * maxf(0.0, v.dot(dir)) * 0.2
		v += dir * a
		# the slingshot: you went in fast and came round; at your nearest it flings you on
		var inward := v.dot(dir) > 0.0
		var was_in: bool = w["in"].get(who, false)
		w["min"][who] = minf(float(w["min"].get(who, 1e9)), d)
		if was_in and not inward and float(w["min"][who]) < SLING_R and v.length() > SLING_V:
			var cap := SLING_MAXH if harness else SLING_MAX
			var nv := minf(v.length() * (SLING_KH if harness else SLING_K), maxf(cap, v.length()))
			v = v.normalized() * nv
			sling_t = SLING_T
			stats["slings"] += 1
			game.audio.play("rift", p, 0.4)
			game.ui.toast("Slingshot! The well flings you on", Color(1.0, 0.8, 0.5), 2.0)
			game.vfx.spawn(Vfx.RING, p, v * 0.5, 16, Color(1.0, 0.85, 0.6), Color(1.0, 0.5, 0.3, 0.0), 6.0, 40.0)
			w["min"][who] = 1e9
		if inward and not was_in:
			w["min"][who] = d
		w["in"][who] = inward
		# its heart: you're spat out, battered (the harness never lets you in)
		var close := _seg_dist(w["pos"], p, p + v)
		if close < CORE_R and not harness:
			v = -dir * 26.0 + dir.orthogonal() * 8.0
			stats["spat"] += 1
			game.shake = maxf(game.shake, 8.0)
			game.audio.play("boom", p, 0.8)
			game.vfx.spawn(Vfx.RING, w["pos"], Vector2.ZERO, 22, Color(1.0, 0.7, 0.4), Color(0.6, 0.2, 1.0, 0.0), 10.0, 70.0)
			if who == "skiff":
				sp.skiff_hit(game.skiff, p - dir * 4.0, 4.0, 12.0)
			else:
				game.hurt(game.player, 18.0, -dir * 4.0, true)
			game.ui.toast("The well's heart spat you out" + ("" if harness else ". (A Void Harness would hold you at its edge)"), Color(1.0, 0.65, 0.45), 3.5)
	return v

static func _seg_dist(c: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 0.0001 else clampf((c - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return c.distance_to(a + ab * t)

## the essence crystals round each well: they orbit, and you take one by flying through it
func _update_crystals() -> void:
	var m = game.player
	var aboard: bool = m.aboard != null and game.skiff != null
	var at: Vector2 = game.skiff.pos if aboard else m.pos
	var reach: float = float(maxi(game.skiff.w, game.skiff.h)) * 0.5 if aboard else 12.0
	for w in wells:
		var c0: Vector2 = w["pos"]
		for cr in w["crystals"]:
			var r: float = cr[0]
			cr[1] = float(cr[1]) + float(w["spin"]) * 0.5 * sqrt(WELL_G / (r * r * r))
			if int(cr[2]) > 0:
				cr[2] = int(cr[2]) - 1
				continue
			var cp: Vector2 = c0 + Vector2.from_angle(float(cr[1])) * r
			if not m.dead and cp.distance_to(at) < reach:
				m.inv[Defs.VOIDESS] += 3
				cr[2] = 4000
				stats["crystals"] += 1
				game.audio.play("rare", cp, 0.5)
				game.ui.toast("An essence crystal: 3 Void Essence", Color(0.8, 0.6, 1.0), 2.0)
				game.vfx.spawn(Vfx.RING, cp, Vector2.ZERO, 14, Color(0.85, 0.7, 1.0), Color(0.5, 0.3, 1.0, 0.0), 2.0, 16.0)

## for the Starsail's way ahead (space.gd `_clearance`): the wells near the line from p along d
func clearance(p: Vector2, d: Vector2) -> float:
	var best := 1e9
	for w in wells:
		var o: Vector2 = (w["pos"] as Vector2) - p
		var t := o.dot(d)
		if t > 0.0 and (o - d * t).length() < 1400.0:
			best = minf(best, maxf(t - 1200.0, 0.0))
	return best

func nearest_well(p: Vector2, within: float) -> Variant:
	var best = null
	var bd := within
	for w in wells:
		var d: float = (w["pos"] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = w
	return best

# --------------------------------------------------------------- rifts ---

func _rifts_check(focus: Vector2) -> void:
	if _rift_cd > 0 or sp.in_station != null:
		return
	for r in rifts:
		if (r["pos"] as Vector2).distance_to(focus) < RIFT_IN:
			_through(r, focus)
			return

## through a rift: you (and the skiff, with whoever rides it) come out by its twin; the world out here is
## put round you there (space's origin follows, the sectors there stream in)
func _through(r: Dictionary, focus: Vector2) -> void:
	var m = game.player
	var aboard: bool = m.aboard != null and game.skiff != null
	var v: Vector2 = game.skiff.vel if aboard else sp.vel
	var to_l: Vector2 = sp.local_of(r["to"])
	var dir: Vector2 = v.normalized() if v.length() > 0.5 else Vector2.from_angle(float(r["ang"])).orthogonal()
	var d: Vector2 = to_l + dir * RIFT_OUT - focus
	game.vfx.spawn(Vfx.RING, focus, Vector2.ZERO, 26, Color(0.85, 0.6, 1.0), Color(0.5, 0.2, 1.0, 0.0), 6.0, 80.0)
	sp.carry(d)
	# (and the world out here put round you there)
	var here: Vector2 = game.skiff.pos if aboard else m.pos
	sp._shift(-here.round())
	sp._make_bodies(true)
	_rift_cd = 300
	stats["rifts"] += 1
	var pk := str(r["pair"])
	known[pk] = [true, true]
	var rp := Galaxy.rift_pair(int(r["pair"]))
	var sys: int = int(rp["twin"]) if int(r["end"]) == 0 else int(r["pair"])
	game.audio.play("rift", null, 1.0)
	game.vfx.screen_flash(Color(0.8, 0.6, 1.0), 0.8)
	game.shake = maxf(game.shake, 6.0)
	var at2: Vector2 = game.skiff.pos if aboard else m.pos
	game.vfx.spawn(Vfx.RING, at2, Vector2.ZERO, 30, Color(0.85, 0.6, 1.0), Color(0.5, 0.2, 1.0, 0.0), 80.0, 6.0)
	game.ui.toast("Through the rift: out by the %s system" % Galaxy.star_name(sys), Color(0.85, 0.65, 1.0), 4.5)

func nearest_rift(p: Vector2, within: float) -> Variant:
	var best = null
	var bd := within
	for r in rifts:
		var d: float = (r["pos"] as Vector2).distance_to(p)
		if d < bd:
			bd = d
			best = r
	return best

## where a rift leads, as its marker says it
func rift_name(r: Dictionary) -> String:
	var kn: Array = known.get(str(r["pair"]), [false, false])
	if not kn[1 - int(r["end"])]:
		return "Rift"
	var rp := Galaxy.rift_pair(int(r["pair"]))
	return "Rift to the %s system" % Galaxy.star_name(int(rp["twin"]) if int(r["end"]) == 0 else int(r["pair"]))

## eels after you now
func hunting() -> int:
	var n := 0
	for b in beasts:
		if b.kind == "eel" and (b.state == "hunt" or b.state == "recoil"):
			n += 1
	return n

# --------------------------------------------------------------- saving ---

func save_state() -> Dictionary:
	for a in sp.rocks:
		if a.kind == "monolith":
			mono_out(a)
	return {"rifts": known, "mono": mono_state}

func load_state(d: Dictionary) -> void:
	known = {}
	mono_state = {}
	var kr = d.get("rifts", {})
	if kr is Dictionary:
		for k in kr:
			var v = kr[k]
			if v is Array and v.size() == 2:
				known[String(k)] = [bool(v[0]), bool(v[1])]
	var ms = d.get("mono", {})
	if ms is Dictionary:
		mono_state = ms

# -------------------------------------------------------------- drawing ---

## under the rocks (space.gd `_draw_space`): the wells and their fire, the rifts
func draw_under(cv: CanvasItem, xf: Transform2D) -> void:
	var scr := Vector2(game.VW, game.VH)
	var z: float = game.zoom
	var t := float(game.frame)
	for w in wells:
		var c: Vector2 = xf * (w["pos"] as Vector2)
		if c.distance_to(scr * 0.5) > scr.length() * 0.5 + 500.0 / z:
			continue
		_draw_well(cv, xf, w, c, z, t)
	for r in rifts:
		var c2: Vector2 = xf * (r["pos"] as Vector2)
		if c2.distance_to(scr * 0.5) > scr.length() * 0.5 + 200.0 / z:
			continue
		_draw_rift(cv, xf, r, c2, z, t)

func _draw_well(cv: CanvasItem, xf: Transform2D, w: Dictionary, c: Vector2, z: float, t: float) -> void:
	# the bent light round it: faint rings
	for k in 14:
		var rr := (560.0 - float(k) * 36.0) / z
		cv.draw_circle(c, rr, Color(0.3, 0.22, 0.6, 0.012 + 0.002 * float(k)))
	# lensed starlight: short arcs turning slowly round the heart
	var rng := RandomNumberGenerator.new()
	rng.seed = int(w["seed"])
	for k2 in 9:
		var rr2 := rng.randf_range(54.0, 96.0) / z
		var a0 := rng.randf() * TAU + t * 0.002 * (1.0 + float(k2 % 3))
		cv.draw_arc(c, rr2, a0, a0 + rng.randf_range(0.3, 0.9), 10, Color(0.9, 0.9, 1.0, 0.35), 1.0)
	# the ring of fire, tilted: its far half, the heart, its near half
	var rot: float = xf.x.angle() + float(w["tilt"])
	var ax := Vector2.from_angle(rot)
	var ay := ax.orthogonal() * 0.32
	var spin: float = float(w["spin"])
	var front := []
	for k3 in 220:
		var r := rng.randf_range(44.0, 170.0)
		var a := rng.randf() * TAU + t * spin * 0.6 * sqrt(1.0 / (r * r * r)) * 60.0
		var f := (r - 44.0) / 126.0
		var col := Color(1.0, 0.95, 0.8).lerp(Color(1.0, 0.55, 0.25), clampf(f * 1.6, 0.0, 1.0)).lerp(Color(0.55, 0.3, 0.95), clampf(f * 1.4 - 0.5, 0.0, 1.0))
		col.a = 0.9 - f * 0.5
		var lp := ax * cos(a) * r + ay * sin(a) * r
		var pp := (c + lp / z).floor()
		if sin(a) > 0.0:
			front.append([pp, col, 1.0 if f > 0.4 else 2.0])
		else:
			cv.draw_rect(Rect2(pp, Vector2.ONE * (1.0 if f > 0.4 else 2.0)), col)
	cv.draw_circle(c, 46.0 / z, Color(1.0, 0.85, 0.55, 0.85))
	cv.draw_circle(c, 40.0 / z, Color(0.0, 0.0, 0.0))
	for fr in front:
		cv.draw_rect(Rect2(fr[0], Vector2.ONE * float(fr[2])), fr[1])
	# its crystals, orbiting close to its edge
	for cr in w["crystals"]:
		if int(cr[2]) > 0:
			continue
		var cp: Vector2 = xf * ((w["pos"] as Vector2) + Vector2.from_angle(float(cr[1])) * float(cr[0]))
		var q := cp.floor()
		cv.draw_circle(q, 6.0 / minf(z, 4.0), Color(0.7, 0.45, 1.0, 0.18))
		cv.draw_colored_polygon(PackedVector2Array([q + Vector2(0, -3), q + Vector2(2, 0), q + Vector2(0, 3), q + Vector2(-2, 0)]), Color(0.75, 0.5, 1.0))
		cv.draw_rect(Rect2(q, Vector2.ONE), Color(1, 0.95, 1))

func _draw_rift(cv: CanvasItem, xf: Transform2D, r: Dictionary, c: Vector2, z: float, t: float) -> void:
	var axis: Vector2 = xf.basis_xform(Vector2.from_angle(float(r["ang"]))).normalized()
	var perp := axis.orthogonal()
	var L := 120.0 / z
	var W := 20.0 / z
	var layers := [[1.9, Color(0.55, 0.3, 1.0, 0.14)], [1.35, Color(0.85, 0.4, 1.0, 0.4)], [1.0, Color(0.03, 0.0, 0.07, 1.0)]]
	for ly in layers:
		var pts := PackedVector2Array()
		for q in 33:
			var u := float(q) / 32.0 * 2.0 - 1.0
			var jag := 0.75 + 0.35 * sin(u * 13.0 + t * 0.21 + float(r["pair"])) * sin(u * 5.0 - t * 0.13)
			pts.append(c + axis * u * L * 0.5 * float(ly[0]) * 0.85 + perp * W * pow(maxf(0.0, 1.0 - u * u), 0.8) * jag * float(ly[0]))
		for q2 in range(32, -1, -1):
			var u2 := float(q2) / 32.0 * 2.0 - 1.0
			var jag2 := 0.75 + 0.35 * sin(u2 * 11.0 - t * 0.19 + float(r["end"])) * sin(u2 * 7.0 + t * 0.11)
			pts.append(c + axis * u2 * L * 0.5 * float(ly[0]) * 0.85 - perp * W * pow(maxf(0.0, 1.0 - u2 * u2), 0.8) * jag2 * float(ly[0]))
		cv.draw_colored_polygon(pts, ly[1])
		if float(ly[0]) == 1.0:
			var ed := pts.duplicate()
			ed.append(pts[0])
			cv.draw_polyline(ed, Color(0.95, 0.85, 1.0, 0.9), 1.0)
	# the other sky, through it: stars turning inside
	var rng := RandomNumberGenerator.new()
	rng.seed = int(r["pair"]) * 7 + int(r["end"])
	for k in 14:
		var u3 := rng.randf_range(-0.8, 0.8)
		var v3 := rng.randf_range(-0.6, 0.6) * pow(1.0 - u3 * u3, 0.8)
		var tw := 0.5 + 0.5 * sin(t * 0.07 + float(k))
		cv.draw_rect(Rect2((c + axis * u3 * L * 0.42 + perp * v3 * W).floor(), Vector2.ONE), Color(0.9, 0.85, 1.0, tw))
	# matter drawn into it
	for k2 in 20:
		var f := fposmod(t * 0.006 + float(k2) * 0.37, 1.0)
		var a := float(k2) * 2.4 + f * 3.0
		var d := (1.0 - f) * 160.0 / z
		cv.draw_rect(Rect2((c + Vector2.from_angle(a) * d).floor(), Vector2.ONE), Color(0.8, 0.6, 1.0, f))

## over the rocks, under the mage (space.gd `_mid`): the creatures, essence, the glyphs' light
func draw_mid(cv: CanvasItem, xf: Transform2D) -> void:
	var scr := Vector2(game.VW, game.VH)
	var zs: float = minf(float(game.zoom), 4.0)
	var t := float(game.frame)
	for b in beasts:
		var s: Vector2 = xf * b.pos
		if s.x < -120.0 or s.y < -120.0 or s.x > scr.x + 120.0 or s.y > scr.y + 120.0:
			continue
		var mod := Color(2.0, 2.0, 2.0) if b.hit_t > 0 else Color.WHITE
		var rot: float = xf.basis_xform(Vector2.from_angle(b.ang)).angle()
		match b.kind:
			"manta":
				var col: Color = groups.get(b.gk, {}).get("col", Color(0.6, 0.4, 1.0))
				cv.draw_circle(s.floor(), 30.0 / zs, Color(col.r, col.g, col.b, 0.05))
				var fr: Array = _frames("manta")
				var tx: ImageTexture = fr[int(fposmod(b.phase / TAU * fr.size(), fr.size()))]
				cv.draw_set_transform(s.floor(), rot, Vector2.ONE / zs)
				cv.draw_texture(tx, -Vector2(36, 32), mod * Color(1, 1, 1).lerp(col.lightened(0.3), 0.3))
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"eel":
				var segs := _segments(b)
				var segt: Array = _frames("eelseg")
				for q in range(segs.size() - 1, -1, -1):
					var sg: Array = segs[q]
					var ss: Vector2 = (xf * (sg[0] as Vector2)).floor()
					var st: ImageTexture = segt[clampi(int(round(float(sg[1]))) - 1, 0, 3)]
					cv.draw_set_transform(ss, 0.0, Vector2.ONE / zs)
					cv.draw_texture(st, -Vector2(st.get_width(), st.get_height()) * 0.5, mod)
					if q % 2 == 1 and sin(t * 0.1 + float(q)) > -0.2:
						cv.draw_rect(Rect2(Vector2(0, -1), Vector2.ONE), Color(0.7, 1.0, 0.9))
					cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var ht: Array = _frames("eelhead")
				var open: bool = b.state == "hunt" and fposmod(b.phase, 3.0) < 1.5
				cv.draw_set_transform(s.floor(), rot, Vector2.ONE / zs)
				cv.draw_texture(ht[1 if open else 0], Vector2(-4, -4), mod)
				# (its lure, a light ahead of its head)
				cv.draw_circle(Vector2(9, 0), 3.0, Color(0.5, 1.0, 0.85, 0.2))
				cv.draw_rect(Rect2(Vector2(8, -1), Vector2(1, 1)), Color(0.85, 1.0, 0.95))
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"jelly":
				var pf := fposmod(b.phase, TAU) / TAU
				var glow := 0.5 + 0.5 * cos(pf * TAU) + float(b.flash) / 20.0
				cv.draw_circle(s.floor(), 16.0 / zs, Color(1.0, 0.6, 0.95, 0.05 + 0.06 * glow))
				cv.draw_circle(s.floor(), 9.0 / zs, Color(1.0, 0.7, 0.95, 0.06 + 0.08 * glow))
				# tentacles trailing behind its bell
				var dir := Vector2.from_angle(b.ang)
				var pd := dir.orthogonal()
				for k in 5:
					var off := (float(k) - 2.0) * 2.4
					for j in 16:
						var wp: Vector2 = b.pos - dir * (5.0 + float(j) * 1.5) + pd * (off + sin(b.phase * 1.3 + float(j) * 0.45 + float(k)) * float(j) * 0.14)
						var tp: Vector2 = (xf * wp).floor()
						cv.draw_rect(Rect2(tp, Vector2.ONE), Color(1.0, 0.7, 0.95, 0.75 - float(j) * 0.04))
				var bf: Array = _frames("jelly")
				var bi := 0 if pf < 0.12 else (1 if pf < 0.25 else (2 if pf < 0.7 else 3))
				cv.draw_set_transform(s.floor(), rot + PI * 0.5, Vector2.ONE / zs)
				var bt: ImageTexture = bf[bi]
				cv.draw_texture(bt, -Vector2(bt.get_width(), bt.get_height()) * 0.5, mod * Color(1, 1, 1, 1).lerp(Color(1.3, 1.2, 1.3), clampf(glow - 0.5, 0.0, 1.0)))
				cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# essence drifting
	for mo in motes:
		var mp: Vector2 = (xf * (mo[0] as Vector2)).floor()
		if mp.x < -10.0 or mp.y < -10.0 or mp.x > scr.x + 10.0 or mp.y > scr.y + 10.0:
			continue
		var tw := 0.6 + 0.4 * sin(t * 0.2 + mp.x)
		cv.draw_circle(mp, 4.0, Color(0.7, 0.45, 1.0, 0.12 * tw))
		cv.draw_colored_polygon(PackedVector2Array([mp + Vector2(0, -2), mp + Vector2(2, 0), mp + Vector2(0, 2), mp + Vector2(-2, 0)]), Color(0.7, 0.45, 1.0, 0.85))
		cv.draw_rect(Rect2(mp, Vector2.ONE), Color(1, 0.95, 1, tw))
	# a monolith's glyphs: the lit ones glow, the next to wake pulses faintly
	for a in sp.rocks:
		if a.kind != "monolith" or a.pos.distance_to(game.cam_c) > 2500.0:
			continue
		var nx: int = a.next_glyph()
		for k2 in a.glyphs.size():
			var gp: Vector2 = (xf * a.glyph_pos(k2)).floor()
			var lit: int = int(a.glyphs[k2]["lit"])
			if lit > 0:
				var f2 := clampf(float(lit) / 300.0, 0.25, 1.0)
				cv.draw_circle(gp, 12.0 / zs, Color(0.7, 0.45, 1.0, 0.12 * f2))
				cv.draw_circle(gp, 7.0 / zs, Color(0.8, 0.6, 1.0, 0.14 * f2))
			elif k2 == nx:
				var pu := 0.5 + 0.5 * sin(t * 0.08)
				cv.draw_circle(gp, 9.0 / zs, Color(0.6, 0.45, 1.0, 0.05 + 0.06 * pu))

## health bars over hurt creatures (space.gd `_top`)
func draw_top(cv: CanvasItem, xf: Transform2D) -> void:
	var zs: float = minf(float(game.zoom), 4.0)
	for b in beasts:
		if b.dead or b.hp >= b.hp_max:
			continue
		var s: Vector2 = xf * b.pos
		var up: float = {"manta": 30.0, "eel": 10.0, "jelly": 14.0}[b.kind]
		var at := (s + Vector2(0, -up / zs - 6.0)).floor()
		var bw := 24.0 if b.kind == "manta" else 14.0
		cv.draw_rect(Rect2(at - Vector2(bw * 0.5 + 1.0, 1.0), Vector2(bw + 2.0, 4.0)), Color(0.05, 0.02, 0.06, 0.8))
		cv.draw_rect(Rect2(at - Vector2(bw * 0.5, 0.0), Vector2(bw * clampf(b.hp / b.hp_max, 0.0, 1.0), 2.0)), Color(0.75, 0.55, 1.0))

## the markers at the screen's edge: the nearest well, rift and monolith
func draw_markers(xf: Transform2D) -> void:
	var at: Vector2 = game.player.pos
	var w = nearest_well(at, 30000.0)
	if w != null:
		sp._marker(xf, w["pos"], 180.0, "Gravity well", Color(1.0, 0.7, 0.45))
	var r = nearest_rift(at, 30000.0)
	if r != null:
		sp._marker(xf, r["pos"], 60.0, rift_name(r), Color(0.85, 0.6, 1.0))
	var best = null
	var bd := 30000.0
	for a in sp.rocks:
		if a.kind == "monolith":
			var d: float = a.pos.distance_to(at)
			if d < bd:
				bd = d
				best = a
	if best != null:
		sp._marker(xf, best.pos, best.reach(), "Ancient monolith" + (" (open)" if best.opened else ""), Color(0.8, 0.65, 1.0))

## an eel's body: [world point, radius] from its head back, along where its head has been
func _segments(b: Beast) -> Array:
	var out := [[b.pos, 3.5]]
	if b.trail.size() < 2:
		return out
	var n := 12
	var gap := 3.2
	var acc := 0.0
	var want := gap
	var q := 0
	var prev: Vector2 = b.trail[0]
	var k := 1
	while k < b.trail.size() and q < n:
		var cur: Vector2 = b.trail[k]
		var sl := prev.distance_to(cur)
		if acc + sl >= want:
			var f := (want - acc) / maxf(sl, 0.0001)
			var pt := prev.lerp(cur, f)
			q += 1
			var r := lerpf(3.4, 1.1, float(q) / float(n))
			var wig := sin(b.phase - float(q) * 0.7) * 0.6 * float(q) / float(n)
			out.append([pt + (cur - prev).normalized().orthogonal() * wig, r])
			want += gap
		else:
			acc += sl
			prev = cur
			k += 1
	return out

# -------------------------------------------------------------- the art ---

func _frames(what: String) -> Array:
	if _tex.has(what):
		return _tex[what]
	var out := []
	match what:
		"manta":
			for f in 6:
				out.append(ImageTexture.create_from_image(_manta_img(float(f) / 6.0)))
		"eelhead":
			for f2 in 2:
				out.append(ImageTexture.create_from_image(_eel_head(f2 == 1)))
		"eelseg":
			for r in range(1, 5):
				out.append(ImageTexture.create_from_image(_eel_seg(float(r))))
		"jelly":
			for f3 in 4:
				out.append(ImageTexture.create_from_image(_jelly_img(f3)))
	_tex[what] = out
	return out

## a void manta from above, its nose along +x: wide wings (their span with the flap), horns, a whip tail;
## its back dark, the wing edges lit, spots that glow along them
static func _manta_img(ph: float) -> Image:
	var W := 64
	var H := 64
	var cx := 36.0
	var cy := 32.0
	var flap := cos(ph * TAU)
	var S := 22.0 + 7.0 * flap
	var mask := PackedByteArray()
	mask.resize(W * H)
	for y in H:
		for x in W:
			var u := float(x) + 0.5 - cx
			var v := absf(float(y) + 0.5 - cy)
			var on := 0
			if (u - 1.5) * (u - 1.5) / (16.5 * 16.5) + v * v / 36.0 <= 1.0:
				on = 2                                       # its body
			elif v >= 3.0 and v <= S:
				var f := (v - 3.0) / maxf(S - 3.0, 1.0)
				var lead := lerpf(12.0, -9.0, pow(f, 1.7))
				var trail := lerpf(-15.0, -9.0, pow(f, 0.55))
				if u <= lead and u >= trail:
					on = 1
			if u >= 14.0 and u <= 21.0 and v >= 2.5 and v <= 5.5 - (u - 14.0) * 0.3:
				on = 2                                       # its horns
			if u >= -36.0 and u < -14.0 and v < 0.9:
				on = 3                                       # its tail
			mask[y * W + x] = on
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var back := Color(0.18, 0.12, 0.36)
	var wing := Color(0.27, 0.19, 0.52)
	var rim := Color(0.62, 0.52, 1.0)
	var glow := Color(0.6, 1.0, 1.0)
	var ink := Color(0.04, 0.02, 0.09)
	for y in H:
		for x in W:
			var mk := mask[y * W + x]
			if mk == 0:
				# (a dark outline round it)
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var xx: int = x + o.x
					var yy: int = y + o.y
					if xx >= 0 and yy >= 0 and xx < W and yy < H and mask[yy * W + xx] != 0:
						img.set_pixel(x, y, ink)
						break
				continue
			var u := float(x) + 0.5 - cx
			var v := absf(float(y) + 0.5 - cy)
			var edge := false
			for o2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x2: int = x + o2.x
				var y2: int = y + o2.y
				if x2 < 0 or y2 < 0 or x2 >= W or y2 >= H or mask[y2 * W + x2] == 0:
					edge = true
			var c := back
			if mk == 1:
				c = back.lerp(wing, clampf(v / maxf(S, 1.0) + 0.2, 0.0, 1.0))
				if edge:
					c = rim
				# glowing spots along the wing, and a lit line inside its leading edge
				var f := (v - 3.0) / maxf(S - 3.0, 1.0)
				for sp_f in [0.32, 0.55, 0.78]:
					var su := lerpf(lerpf(12.0, -9.0, pow(sp_f, 1.7)), lerpf(-15.0, -9.0, pow(sp_f, 0.55)), 0.5)
					var sv: float = 3.0 + sp_f * (S - 3.0)
					if absf(u - su) < 1.1 and absf(v - sv) < 1.1:
						c = glow
				if not edge and absf(u - (lerpf(12.0, -9.0, pow(f, 1.7)) - 1.5)) < 0.6 and f > 0.1:
					c = wing.lerp(rim, 0.55)
			elif mk == 2:
				c = back.lerp(Color(0.32, 0.22, 0.56), 1.0 - v / 6.0)
				if edge:
					c = rim.darkened(0.25)
				if absf(u - 13.0) < 0.6 and absf(v - 4.0) < 0.6:
					c = Color(0.9, 1.0, 1.0)              # its eyes
			elif mk == 3:
				c = rim.darkened(0.35).lerp(back, clampf((-u - 14.0) / 22.0, 0.0, 1.0))
			img.set_pixel(x, y, c)
	return img

## an eel's head, along +x (8 x 8; the jaw open or shut)
static func _eel_head(open: bool) -> Image:
	var rows := ["..####..", ".#tttt#.", "#tttTTt#", "#ttTTTe#", "#tttTTT#", "#tttTT#.", ".#ttt#..", "..###..."]
	if open:
		rows = ["..####..", ".#tttt#.", "#tttTTt#", "#ttTTTe#", "#tttT#..", "#ttt#.##", ".#tt##..", "..##...."]
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var pal := {"#": Color(0.03, 0.1, 0.12), "t": Color(0.1, 0.32, 0.36), "T": Color(0.3, 0.75, 0.7), "e": Color(0.85, 1.0, 0.9)}
	for y in 8:
		for x in 8:
			var ch: String = rows[y][x]
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	return img

## a round of an eel's body, radius r: dark at its edge, glowing in its middle
static func _eel_seg(r: float) -> Image:
	var n := int(ceil(r)) * 2 + 1
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := float(n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length()
			if d > r + 0.35:
				continue
			var col := Color(0.03, 0.1, 0.12)
			if d < r - 0.6:
				col = Color(0.1, 0.32, 0.36).lerp(Color(0.3, 0.8, 0.72), clampf(1.0 - d / maxf(r, 1.0), 0.0, 1.0))
			img.set_pixel(x, y, col)
	return img

## a star jelly's bell, its top toward -y (frame 0 open wide, 1 closing, 2 shut and long, 3 opening): a
## dome, a lit rim, light on its crown, four glowing knots inside, a fringe under its margin
static func _jelly_img(f: int) -> Image:
	var wide: float = [1.0, 0.85, 0.72, 0.9][f]
	var tall: float = [1.0, 1.12, 1.25, 1.06][f]
	var W := 19
	var H := 15
	var R := 8.2 * wide
	var hh := 8.0 * tall
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var cx := float(W) * 0.5
	var base := 12.5
	for y in H:
		for x in W:
			var u := float(x) + 0.5 - cx
			var v := base - (float(y) + 0.5)          # height over the margin
			if v < -1.5 or v > hh:
				continue
			var half := R * sqrt(maxf(0.0, 1.0 - pow(v / hh, 2.0))) if v >= 0.0 else R * 0.9
			if absf(u) > half:
				continue
			var e := absf(u) > half - 1.1 or v > hh - 1.1
			var col := Color(0.62, 0.3, 0.78, 0.55)
			if v < 0.0:
				if fposmod(u + 20.0, 2.4) >= 1.2:
					continue
				col = Color(1.0, 0.6, 0.95, 0.85)        # (the fringe)
			elif e:
				col = Color(1.0, 0.62, 0.97, 0.95)
			if u > -R * 0.6 and u < -R * 0.15 and v > hh * 0.55 and v < hh * 0.85 and not e:
				col = Color(1.0, 0.88, 1.0, 0.85)         # (light on its crown)
			for uk in [-3.4, -1.15, 1.15, 3.4]:
				var vk: float = hh * 0.3 + (0.9 if absf(uk) < 2.0 else 0.0)
				if absf(u - uk * wide) < 0.9 and absf(v - vk) < 0.9:
					col = Color(1.0, 0.9, 0.6, 0.95)      # (the glowing knots inside)
			img.set_pixel(x, y, col)
	return img

# ------------------------------------------------------------ for tests ---

## a group of creatures (type "mantas", "eels", "jellies") set down at p, in a sector of their own ("test")
func add_test(type: String, p: Vector2, n: int, sd: int) -> String:
	var gk := "test:%d" % sd
	var g: PackedFloat64Array = sp.galaxy_of(p)
	_make_group({"type": type, "n": n, "seed": sd, "at": Vector2.ZERO, "col": Color(0.6, 0.4, 1.0)}, gk, "test", g, g)
	return gk

func add_test_well(p: Vector2, sd := 7) -> Dictionary:
	var cr := []
	for k in CRYSTALS:
		cr.append([180.0 + float(k) * 25.0, float(k), 0])
	var w := {"sect": "test", "pos": p, "seed": sd, "crystals": cr, "in": {}, "min": {}, "tilt": 0.4, "spin": 1.0}
	wells.append(w)
	return w

func clear_test() -> void:
	sector_out("test")
	motes.clear()
