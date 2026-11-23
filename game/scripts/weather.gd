## Weather you can tell apart at a glance (user, 22 Nov: "I saw a hail storm that looked the same as rain
## and it started hurting me. weather patterns need distinct art"). Its own particles, drawn in whole game
## pixels over the world and lit by it, each kind with its own look and its own way of meeting the ground
## (main.gd `_update_weather` says what's falling; they stop on whatever is solid in the collision grid, so
## a roof keeps them off and you see them land on it):
## - RAIN: thin slanting streaks, pale and fast, in the wind; a little splash where each lands.
## - HAIL: chunky ice stones, two or three pixels, white with a pale-blue edge and a dark rim so they read
##   as hard against any sky; they fall fast, clack and bounce (twice at most), chip, and lie a moment
##   on the ground shrinking as they melt.
## - SNOW: slow flakes, dots and little crosses, swaying as they fall; they rest a moment where they land.
## - ASH: dark grey flakes tumbling slowly, now and then a pale one.
## - EMBER: sparks drifting up off a volcanic world, flickering (unlit: they glow).
## - DUST: sand streaking along in the wind.
## SPLASH and CHIP are what rain and hail throw up where they land.
extends Node2D

enum {RAIN, HAIL, SNOW, ASH, EMBER, DUST, SPLASH, CHIP}
const MAX := 1100
const CAP := {RAIN: 320, HAIL: 340, SNOW: 360, ASH: 260, EMBER: 120, DUST: 260}

var game
var P := PackedVector2Array()       # where (world)
var V := PackedVector2Array()       # its velocity a tick
var L := PackedInt32Array()         # ticks left
var K := PackedByteArray()          # kind
var B := PackedByteArray()          # bounces so far (hail), 1 = resting (snow, hail)
var S := PackedFloat32Array()       # its size (hail), sway phase (snow, ash)
var count := {}                     # kind -> how many alive
var stats := {"hail_bounces": 0, "rain_splashes": 0, "landed": 0}    # (for the tests)
var _t := 0

func spawn(kind: int, pos: Vector2, vel: Vector2, life: int, size := 1.0) -> void:
	if P.size() >= MAX or int(count.get(kind, 0)) >= int(CAP.get(kind, MAX)):
		return
	P.append(pos)
	V.append(vel)
	L.append(life)
	K.append(kind)
	B.append(0)
	S.append(size)
	count[kind] = int(count.get(kind, 0)) + 1

func clear() -> void:
	P.clear()
	V.clear()
	L.clear()
	K.clear()
	B.clear()
	S.clear()
	count.clear()

func _kill(i: int) -> void:
	count[int(K[i])] = int(count.get(int(K[i]), 1)) - 1
	var last := P.size() - 1
	P[i] = P[last]
	V[i] = V[last]
	L[i] = L[last]
	K[i] = K[last]
	B[i] = B[last]
	S[i] = S[last]
	P.resize(last)
	V.resize(last)
	L.resize(last)
	K.resize(last)
	B.resize(last)
	S.resize(last)

## n of a kind coming in from the top of the screen (and its windward side), falling "down" (bd) with
## the wind along br
func emit(kind: int, n: float, br: Vector2, bd: Vector2, wind: float) -> void:
	var w := float(game.VW)
	var h := float(game.VH)
	n *= game._fxb                   # (fewer drops and flakes at a lower quality: main.fx_budget)
	var k := int(n) + (1 if randf() < n - floorf(n) else 0)
	for q in k:
		# (from the top edge, or from the side the wind blows from when it blows hard)
		var sp := Vector2(randf_range(-30.0, w + 30.0), randf_range(-12.0, -2.0))
		if absf(wind) > 0.4 and randf() < 0.35:
			sp = Vector2(-6.0 if wind > 0.0 else w + 6.0, randf() * h)
		var wp: Vector2 = game.screen_to_world(sp)
		match kind:
			RAIN:
				spawn(RAIN, wp, bd * randf_range(5.0, 6.5) + br * wind * 3.0, 110)
			HAIL:
				spawn(HAIL, wp, bd * randf_range(3.2, 4.4) + br * wind * 1.6, 160, 2.0 if randf() < 0.6 else 3.0)
			SNOW:
				spawn(SNOW, wp, bd * randf_range(0.35, 0.7) + br * wind * 2.2, 420, randf() * TAU)
			ASH:
				spawn(ASH, wp, bd * randf_range(0.25, 0.5) + br * wind * 1.8, 460, randf() * TAU)
			DUST:
				var dp: Vector2 = game.screen_to_world(Vector2(-6.0 if wind >= 0.0 else w + 6.0, randf() * h))
				spawn(DUST, dp, br * (wind * 4.0 + signf(wind) * randf_range(1.5, 3.0)) + bd * randf_range(-0.1, 0.25), 150)
			EMBER:
				var ep: Vector2 = game.screen_to_world(Vector2(randf() * w, h + 4.0))
				spawn(EMBER, ep, -bd * randf_range(0.3, 0.7) + br * wind * 1.5, 200 + randi() % 120, randf() * TAU)

func _solid(p: Vector2) -> bool:
	var t: int = game.type_at(p)
	return t > 0 and (Defs.KIND[t] == Defs.K_SOLID or Defs.KIND[t] == Defs.K_LIQUID or Defs.KIND[t] == Defs.K_POWDER)

## where along p -> p + v it first meets something (0..1), or -1: in steps of a cell or so, so a fast
## drop never passes through a thin roof
func _hit(p: Vector2, v: Vector2) -> float:
	var n := maxi(1, int(ceil(v.length() / 1.2)))
	for q in range(1, n + 1):
		var f := float(q) / float(n)
		if _solid(p + v * f):
			return float(q - 1) / float(n)
	return -1.0

func tick() -> void:
	_t += 1
	var i := 0
	while i < P.size():
		L[i] -= 1
		if L[i] <= 0:
			_kill(i)
			continue
		var k := int(K[i])
		var p: Vector2 = P[i]
		var v: Vector2 = V[i]
		match k:
			RAIN:
				var hr := _hit(p, v)
				if hr >= 0.0:
					p += v * hr
					# a splash: a couple of drops thrown up and out
					var up: Vector2 = -v.normalized()
					for q in 2:
						spawn(SPLASH, p, up.rotated(randf_range(-1.0, 1.0)) * randf_range(0.4, 0.9), 8 + randi() % 6)
					stats["rain_splashes"] += 1
					_kill(i)
					continue
				P[i] = p + v
			HAIL:
				if B[i] >= 3:
					# lying on the ground, melting
					S[i] = maxf(S[i] - 0.012, 1.0)
				else:
					var g: Vector2 = game.basis_d(atan2(p.y, p.x)) * 0.12
					v += g
					var hh := _hit(p, v)
					if hh >= 0.0:
						p += v * hh
						P[i] = p
						var sp := v.length()
						if sp > 1.2 and B[i] < 2:
							# it bounces: back up off the ground, a little sideways, and chips
							var n: Vector2 = -game.basis_d(atan2(p.y, p.x))
							v = (v - 2.0 * v.dot(n) * n) * 0.32 + n.orthogonal() * randf_range(-0.4, 0.4)
							B[i] += 1
							stats["hail_bounces"] += 1
							if randf() < 0.5:
								spawn(CHIP, p, n.rotated(randf_range(-1.2, 1.2)) * randf_range(0.5, 1.2), 10 + randi() % 8)
							if B[i] == 1 and randf() < 0.08:
								game.audio.play("hit", p, 0.12, 2.2)
						else:
							v = Vector2.ZERO
							B[i] = 3
							L[i] = mini(L[i], 50 + randi() % 70)
							stats["landed"] += 1
					else:
						P[i] = p + v
					V[i] = v
			SNOW, ASH:
				if B[i] == 1:
					pass                       # (resting where it landed)
				else:
					S[i] += 0.05
					var a := atan2(p.y, p.x)
					var sway: Vector2 = game.basis_r(a) * sin(S[i]) * (0.25 if k == SNOW else 0.18)
					var np3 := p + v + sway
					if _solid(np3):
						B[i] = 1
						L[i] = mini(L[i], 60 + randi() % 80)
						stats["landed"] += 1
					else:
						P[i] = np3
			EMBER:
				S[i] += 0.2
				P[i] = p + v + game.basis_r(atan2(p.y, p.x)) * sin(S[i] * 0.3) * 0.15
			DUST:
				P[i] = p + v
			SPLASH, CHIP:
				v += game.basis_d(atan2(p.y, p.x)) * 0.1
				V[i] = v
				P[i] = p + v
		i += 1
	queue_redraw()

func _draw() -> void:
	if P.is_empty():
		return
	if game.space.active and not game.space.live:
		return
	var xf_ok: bool = game.screen_xf_ok()
	var xf: Transform2D = game.screen_xf() if xf_ok else Transform2D.IDENTITY
	var w := float(game.VW)
	var h := float(game.VH)
	for i in P.size():
		var sp: Vector2 = (xf * P[i]) if xf_ok else game.world_to_screen(P[i])
		if sp.x < -8.0 or sp.y < -8.0 or sp.x > w + 8.0 or sp.y > h + 8.0:
			continue
		var k := int(K[i])
		var lc := Color(1, 1, 1)
		if k != EMBER:
			var lt: Color = game.gpu.light_at(game.screen_to_pic(sp))
			var f := 0.06 + 0.94 * lt.a
			lc = Color(clampf(lt.r, 0.2, 1.0) * f, clampf(lt.g, 0.2, 1.0) * f, clampf(lt.b, 0.2, 1.0) * f)
		var fp := sp.floor()
		var life := float(L[i])
		match k:
			RAIN:
				# a thin streak along its fall, its head brightest
				var d: Vector2 = (xf.basis_xform(V[i]) if xf_ok else (game.world_to_screen(P[i] + V[i]) - sp)).normalized()
				var c := Color(0.68, 0.78, 0.98, 0.55) * Color(lc.r, lc.g, lc.b, 1.0)
				for q in 4:
					var qp := (sp - d * float(q)).floor()
					draw_rect(Rect2(qp, Vector2.ONE), Color(c.r, c.g, c.b, c.a * (1.0 - float(q) * 0.2)))
			HAIL:
				var sz := int(round(S[i]))
				var rim := Color(0.22, 0.28, 0.4, 0.85)
				var edge := Color(0.66, 0.8, 0.94) * Color(lc.r, lc.g, lc.b, 1.0)
				var core := Color(0.97, 0.99, 1.0) * Color(lc.r, lc.g, lc.b, 1.0)
				var fade := clampf(life / 40.0, 0.0, 1.0) if B[i] >= 3 else 1.0
				rim.a *= fade
				edge.a = fade
				core.a = fade
				if sz >= 3:
					draw_rect(Rect2(fp + Vector2(-1, 0), Vector2(5, 3)), rim)
					draw_rect(Rect2(fp + Vector2(0, -1), Vector2(3, 5)), rim)
					draw_rect(Rect2(fp, Vector2(3, 3)), edge)
					draw_rect(Rect2(fp, Vector2(2, 2)), core)
					draw_rect(Rect2(fp, Vector2.ONE), Color(1, 1, 1, fade))
				elif sz == 2:
					draw_rect(Rect2(fp + Vector2(-1, 0), Vector2(4, 2)), rim)
					draw_rect(Rect2(fp + Vector2(0, -1), Vector2(2, 4)), rim)
					draw_rect(Rect2(fp, Vector2(2, 2)), edge)
					draw_rect(Rect2(fp, Vector2.ONE), core)
				else:
					draw_rect(Rect2(fp, Vector2.ONE), core)
			SNOW:
				var sc := Color(0.97, 0.98, 1.0, 0.9) * Color(lc.r, lc.g, lc.b, 1.0)
				if B[i] == 1:
					sc.a *= clampf(life / 50.0, 0.0, 1.0)
				if i % 4 == 0:
					# a little cross of a flake
					draw_rect(Rect2(fp + Vector2(-1, 0), Vector2(3, 1)), sc)
					draw_rect(Rect2(fp + Vector2(0, -1), Vector2(1, 3)), sc)
				else:
					draw_rect(Rect2(fp, Vector2.ONE), sc)
			ASH:
				var ac := (Color(0.62, 0.6, 0.58, 0.85) if i % 7 == 0 else Color(0.3, 0.28, 0.27, 0.85)) * Color(lc.r, lc.g, lc.b, 1.0)
				if B[i] == 1:
					ac.a *= clampf(life / 50.0, 0.0, 1.0)
				# (tumbling: wide, then tall)
				draw_rect(Rect2(fp, Vector2(2, 1) if sin(S[i] * 2.0) > 0.0 else Vector2(1, 2)), ac)
			EMBER:
				var fl := 0.6 + 0.4 * sin(S[i] * 1.7 + float(i))
				draw_rect(Rect2(fp, Vector2.ONE), Color(1.0, 0.55 + 0.3 * fl, 0.2, minf(1.0, life / 40.0) * fl))
			DUST:
				var dc := Color(0.88, 0.74, 0.5, 0.6) * Color(lc.r, lc.g, lc.b, 1.0)
				var dd: Vector2 = (xf.basis_xform(V[i]) if xf_ok else Vector2.RIGHT).normalized()
				draw_rect(Rect2(fp, Vector2.ONE), dc)
				draw_rect(Rect2((sp - dd * 2.0).floor(), Vector2.ONE), Color(dc.r, dc.g, dc.b, dc.a * 0.5))
			SPLASH:
				draw_rect(Rect2(fp, Vector2.ONE), Color(0.75, 0.85, 1.0, 0.7) * Color(lc.r, lc.g, lc.b, 1.0))
			CHIP:
				draw_rect(Rect2(fp, Vector2.ONE), Color(0.95, 0.98, 1.0, 0.9) * Color(lc.r, lc.g, lc.b, 1.0))
