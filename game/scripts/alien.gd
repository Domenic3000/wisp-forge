## The aliens of the derelict stations (user, 23 Nov: "Derelict space stations and everything with aliens and
## such to fight"). Each lives in its station's own cell coordinates (`b`, the middle of its body; +y is the
## station's floor-ward "down"), so a powered room's gravity is simply +y and a broken room has none. space.gd
## keeps them (`aliens`), ticks them (`tick`) while you're near their station, draws them (`frame`), and fights
## them with your spells; what they spit is space.gd's `acid`.
##   skitter   a low, six-legged crawler: runs at you along the floor and leaps (in a dead room it kicks off
##             the walls after you); a bite.
##   drifter   a floating bell with a glowing core and trailing feelers, at home in the dark rooms: it keeps
##             its distance and spits acid.
##   brute     a hunched, plated walker of the powered halls: it plods after you, rears up (its tell) and
##             charges.
##   brood     the Broodmother, in the nest before the vault: a bloated, many-legged queen that hovers over
##             you, spits volleys of acid and lays skitters; when she falls, the vault's seal breaks.
## Art is grown in code (`frames`), facing +x, outlined, cached per kind.
extends RefCounted

const KINDS := {
	"skitter": {"name": "Skitter", "w": 10, "h": 6, "hp": 22.0, "dmg": 7.0, "speed": 1.35, "xen": [1, 2]},
	"drifter": {"name": "Drifter", "w": 11, "h": 13, "hp": 30.0, "dmg": 5.0, "speed": 0.9, "xen": [2, 3]},
	"brute": {"name": "Brute", "w": 14, "h": 20, "hp": 85.0, "dmg": 16.0, "speed": 0.75, "xen": [4, 6]},
	"brood": {"name": "the Broodmother", "w": 38, "h": 26, "hp": 420.0, "dmg": 14.0, "speed": 0.8, "xen": [18, 24]},
}
const G := 0.17            # a powered room's pull (as on a planet's surface)

var id := 0
var kind := "skitter"
var st                     # its station
var b := Vector2.ZERO      # middle of its body (station cells)
var v := Vector2.ZERO
var hw := 5.0
var hh := 3.0
var hp := 20.0
var hp_max := 20.0
var facing := 1
var on_ground := false
var awake := false
var dead := false
var act := ""              # "", "windup", "leap", "charge", "spit", "recover"
var act_t := 0
var cd := 60               # (ticks to its next attack)
var bite_cd := 0
var hit_t := 0             # (frames since it was hurt: drawn as a flash)
var slow := 0
var anim := 0.0
var home := -1             # its room
var mother = null          # (a skitter the Broodmother laid)
var lay_cd := 300
var stuck := 0
var wob := 0.0

static var _frames := {}

static func make(kd: String, station, at: Vector2, aid: int, room: int):
	var a = load("res://scripts/alien.gd").new()
	var k: Dictionary = KINDS[kd]
	a.kind = kd
	a.st = station
	a.b = at
	a.id = aid
	a.home = room
	a.hw = float(k["w"]) * 0.5
	a.hh = float(k["h"]) * 0.5
	a.hp = float(k["hp"])
	a.hp_max = a.hp
	a.wob = randf() * TAU
	a.cd = randi_range(40, 120)
	return a

func spec() -> Dictionary:
	return KINDS[kind]

func world() -> Vector2:
	return st.to_world(b - st.com)

func flies() -> bool:
	return kind == "drifter" or kind == "brood"

## One tick. `mb`: where the mage's middle is in the station's cells (or null when you're not inside: it
## goes back to its room). `space` is space.gd (acid, hurting you, laying young). Returns nothing; space.gd
## checks contact.
func tick(mb, space) -> void:
	anim += 0.15
	wob += 0.05
	if hit_t > 0:
		hit_t -= 1
	if bite_cd > 0:
		bite_cd -= 1
	var sp := float(spec()["speed"]) * (0.5 if slow > 0 else 1.0)
	if slow > 0:
		slow -= 1
	var grav: bool = st.powered_at(b) and not flies()
	var tgt = mb
	if tgt != null and not awake:
		var near := (tgt as Vector2).distance_to(b) < (110.0 if kind != "brood" else 70.0)
		if near or st.module_at(tgt) == home and kind != "brood":
			awake = true
			space.alien_wake(self)
	if not awake:
		tgt = null
	if tgt == null:
		# (nobody to hunt: back to its room, idling there)
		tgt = st.room_mid(home) if home >= 0 else b
		if kind == "brood":
			tgt = tgt + Vector2(sin(wob) * 10.0, cos(wob * 0.7) * 4.0)
		act = ""
		if (tgt as Vector2).distance_to(b) < 20.0 and not flies():
			v.x *= 0.8
			_move(grav)
			return
	var to: Vector2 = (tgt as Vector2) - b
	var dir := 1 if to.x > 0.0 else -1
	if act == "" and absf(to.x) > 2.0:
		facing = dir
	if cd > 0:
		cd -= 1
	match kind:
		"skitter":
			_skitter(to, dir, sp, grav, mb != null and awake)
		"drifter":
			_drifter(to, sp, mb != null and awake, space)
		"brute":
			_brute(to, dir, sp, grav, mb != null and awake)
		"brood":
			_brood(to, sp, mb != null and awake, space)
	_move(grav)

func _skitter(to: Vector2, dir: int, sp: float, grav: bool, hunting: bool) -> void:
	if act == "windup":
		act_t -= 1
		v.x *= 0.6
		if not grav:
			v *= 0.85
		if act_t <= 0:
			act = "leap"
			act_t = 40
			if grav:
				v = Vector2(float(facing) * 2.7, -2.5)
			else:
				v = to.normalized() * 3.2
		return
	if act == "leap":
		act_t -= 1
		if act_t <= 0 or (grav and on_ground and act_t < 34):
			act = ""
			cd = randi_range(60, 100)
		return
	if grav:
		v.x += (float(dir) * sp - v.x) * 0.3
		if hunting and on_ground and cd <= 0 and absf(to.x) < 70.0 and absf(to.y) < 24.0:
			act = "windup"
			act_t = 14
			facing = dir
		elif on_ground and stuck > 8:
			v.y = -3.2
			stuck = 0
	else:
		# (no gravity: it kicks off whatever it touches toward you, legs flailing)
		var want := to.normalized() * sp * 1.1 + Vector2(sin(wob * 3.0), cos(wob * 2.3)) * 0.35
		v += (want - v) * 0.06
		if hunting and cd <= 0 and to.length() < 55.0:
			act = "windup"
			act_t = 14

func _drifter(to: Vector2, sp: float, hunting: bool, space) -> void:
	var d := to.length()
	var keep := 80.0 if hunting else 0.0
	var want := Vector2.ZERO
	if d > 1.0:
		want = to / d * clampf((d - keep) * 0.05, -1.0, 1.0) * sp
	want += Vector2(sin(wob * 1.3) * 0.25, sin(wob * 2.1) * 0.35)
	v += (want - v) * 0.04
	v *= 0.98
	if act == "spit":
		act_t -= 1
		if act_t <= 0:
			act = ""
			space.alien_spit(self, 0, 1, 2.3)
			cd = randi_range(110, 150)
	elif hunting and cd <= 0 and d < 240.0 and space.alien_sees(self):
		act = "spit"
		act_t = 22

func _brute(to: Vector2, dir: int, sp: float, grav: bool, hunting: bool) -> void:
	if not grav:
		# (it flounders in a dead room)
		v += (to.normalized() * sp * 0.9 - v) * 0.03
		act = ""
		return
	match act:
		"windup":
			act_t -= 1
			v.x *= 0.7
			if act_t <= 0:
				act = "charge"
				act_t = 46
		"charge":
			act_t -= 1
			v.x = float(facing) * 3.3
			if act_t <= 0 or (stuck > 2 and act_t < 40):
				act = "recover"
				act_t = 40
				v.x *= 0.2
		"recover":
			act_t -= 1
			v.x *= 0.85
			if act_t <= 0:
				act = ""
				cd = randi_range(90, 140)
		_:
			v.x += (float(dir) * sp - v.x) * 0.2
			if hunting and on_ground and cd <= 0 and absf(to.x) < 100.0 and absf(to.y) < 26.0:
				act = "windup"
				act_t = 36
				facing = dir
			elif on_ground and stuck > 20:
				v.y = -3.4
				stuck = 0

func _brood(to: Vector2, sp: float, hunting: bool, space) -> void:
	var rage := hp < hp_max * 0.5
	# (she hangs over you, inside her nest)
	var md: Dictionary = st.mods[home] if home >= 0 else {}
	var goal := b + to
	if hunting:
		goal = b + to + Vector2(sin(wob * 0.6) * 30.0, -34.0)
	if not md.is_empty():
		goal.x = clampf(goal.x, float(int(md["x0"])) + hw + 2.0, float(int(md["x1"])) - hw - 2.0)
		goal.y = clampf(goal.y, float(int(md["y0"])) + hh + 2.0, float(int(md["y1"])) - hh - 2.0)
	var want := (goal - b).limit_length(1.0) * sp * (1.3 if rage else 1.0)
	v += (want - v) * 0.05
	if not hunting:
		return
	if act == "spit":
		act_t -= 1
		if act_t <= 0:
			act = ""
			space.alien_spit(self, 0.26, 5 if rage else 3, 2.6)
			cd = randi_range(60, 80) if rage else randi_range(100, 130)
	elif cd <= 0:
		act = "spit"
		act_t = 28
	lay_cd -= 1
	if lay_cd <= 0:
		lay_cd = 240 if rage else 360
		space.alien_lay(self)

## move through the station's cells (walkers step up 5 like you; fliers slide along walls)
func _move(grav: bool) -> void:
	if grav:
		v.y = minf(v.y + G, 6.0)
	var was := b
	var r: Array = st.move_box(b, v, hw, hh, grav, 5 if (grav and on_ground) else 0, false)
	b = r[0]
	v = r[1]
	on_ground = r[2]
	if absf(v.x) < 0.05 and absf(b.x - was.x) < 0.05 and not flies() and act != "windup":
		stuck += 1
	else:
		stuck = 0

## overlap with a box (station cells: middle, half sizes)
func touches(c: Vector2, ohw: float, ohh: float) -> bool:
	return absf(c.x - b.x) < hw + ohw and absf(c.y - b.y) < hh + ohh

## its frame now
func frame() -> ImageTexture:
	var fr: Array = frames(kind)
	match kind:
		"skitter":
			if act == "windup":
				return fr[3]
			if act == "leap" or not on_ground and st.powered_at(b):
				return fr[2]
			return fr[int(anim * (1.5 if absf(v.x) > 0.2 or not st.powered_at(b) else 0.2)) % 2]
		"drifter":
			if act == "spit":
				return fr[3]
			return fr[int(anim * 0.6) % 3]
		"brute":
			if act == "windup":
				return fr[2]
			if act == "charge":
				return fr[3]
			return fr[int(anim * absf(v.x) * 0.9) % 2]
		"brood":
			if act == "spit":
				return fr[2]
			return fr[int(anim * 0.4) % 2]
	return fr[0]

# ------------------------------------------------------------------- art ---

const OUT := Color(0.07, 0.03, 0.1)
const C_DARK := Color(0.2, 0.08, 0.36)
const C_MID := Color(0.4, 0.2, 0.68)
const C_HI := Color(0.62, 0.42, 0.9)
const C_GLOW := Color(0.68, 1.0, 0.42)
const C_GLOW2 := Color(0.88, 1.0, 0.72)
const C_LEG := Color(0.14, 0.06, 0.24)

static func frames(kd: String) -> Array:
	if _frames.has(kd):
		return _frames[kd]
	var imgs := []
	match kd:
		"skitter":
			for f in 4:
				imgs.append(_skitter_img(f))
		"drifter":
			for f in 4:
				imgs.append(_drifter_img(f))
		"brute":
			for f in 4:
				imgs.append(_brute_img(f))
		"brood":
			for f in 3:
				imgs.append(_brood_img(f))
	var out := []
	for im in imgs:
		out.append(ImageTexture.create_from_image(_outline(im)))
	_frames[kd] = out
	return out

static func _blank(w: int, h: int) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	return im

static func _px(im: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height():
		im.set_pixel(x, y, c)

static func _ell(im: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry - 1), int(cy + ry + 2)):
		for x in range(int(cx - rx - 1), int(cx + rx + 2)):
			var dx := (float(x) + 0.5 - cx) / rx
			var dy := (float(y) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(im, x, y, c)

static func _line(im: Image, a: Vector2, z: Vector2, c: Color) -> void:
	var n := int(maxf(absf(z.x - a.x), absf(z.y - a.y))) + 1
	for k in n + 1:
		var p := a.lerp(z, float(k) / float(n))
		_px(im, int(floor(p.x)), int(floor(p.y)), c)

## shading of a carapace: lit from the top left, darker underneath
static func _shell(im: Image, cx: float, cy: float, rx: float, ry: float) -> void:
	_ell(im, cx, cy, rx, ry, C_DARK)
	_ell(im, cx - rx * 0.12, cy - ry * 0.18, rx * 0.82, ry * 0.7, C_MID)
	_ell(im, cx - rx * 0.3, cy - ry * 0.42, rx * 0.36, ry * 0.24, C_HI)

## a dark outline round everything opaque
static func _outline(im: Image) -> Image:
	var w := im.get_width()
	var h := im.get_height()
	var o := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	o.fill(Color(0, 0, 0, 0))
	o.blit_rect(im, Rect2i(0, 0, w, h), Vector2i(1, 1))
	var src := o.duplicate()
	for y in h + 2:
		for x in w + 2:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w + 2 and q.y < h + 2 and src.get_pixel(q.x, q.y).a > 0.5:
					o.set_pixel(x, y, OUT)
					break
	return o

## 14 x 9: a low carapace on six legs, two green eyes and mandibles at the front (+x)
static func _skitter_img(f: int) -> Image:
	var im := _blank(14, 9)
	# legs: three pairs, alternating step (frame 0/1), tucked (2: leaping), splayed (3: crouched to leap)
	for k in 3:
		var hx := 4.0 + float(k) * 2.6
		var up := (k + f) % 2 == 0
		var reach := 2.0 if f != 3 else 3.0
		if f == 2:
			_line(im, Vector2(hx, 5), Vector2(hx - 2.5, 6), C_LEG)
		else:
			var kx := hx + (reach if up else -reach) * 0.5
			_line(im, Vector2(hx, 5), Vector2(kx, 3.0 if f == 3 else 4.0), C_LEG)
			_line(im, Vector2(kx, 3.0 if f == 3 else 4.0), Vector2(kx + (1.0 if up else -1.0), 8.0), C_LEG)
	_shell(im, 7.0, 4.2 if f != 3 else 4.8, 5.2, 2.6)
	# a ridge of plates
	for x in range(3, 10, 2):
		_px(im, x, 2 if f != 3 else 3, C_HI)
	# head, eyes, mandibles
	_ell(im, 11.6, 5.0, 1.8, 1.6, C_DARK)
	_px(im, 12, 4, C_GLOW)
	_px(im, 11, 4, C_GLOW2)
	_px(im, 13, 6, C_HI)
	_px(im, 13, 5, C_LEG)
	# a glowing sac at the tail
	_px(im, 2, 4, C_GLOW)
	_px(im, 2, 5, C_GLOW.darkened(0.3))
	return im

## 15 x 20: a bell with a glowing core and an eye, feelers trailing below that sway (frames 0-2); spitting (3)
static func _drifter_img(f: int) -> Image:
	var im := _blank(15, 20)
	# feelers first (under the bell)
	for k in 5:
		var x0 := 3.0 + float(k) * 2.2
		var ph := float(f) * 2.1 + float(k) * 1.3
		var prev := Vector2(x0, 8.0)
		for s in range(1, 11):
			var p := Vector2(x0 + sin(ph + float(s) * 0.55) * (0.4 + float(s) * 0.12), 8.0 + float(s))
			_line(im, prev, p, C_DARK if s < 7 else C_MID)
			prev = p
		_px(im, int(prev.x), int(prev.y), C_GLOW.darkened(0.2))
	# the bell
	_ell(im, 7.5, 5.5, 6.6, 5.0, C_DARK)
	_ell(im, 7.0, 4.6, 5.6, 3.8, C_MID)
	_ell(im, 5.5, 3.0, 2.4, 1.4, C_HI)
	# its rim, scalloped
	for x in range(1, 15, 2):
		_px(im, x, 9, C_MID)
	# the core: brighter while it spits
	var cc := C_GLOW2 if f == 3 else C_GLOW
	_ell(im, 7.5, 6.5, 2.4 if f == 3 else 1.9, 1.8, cc)
	_px(im, 8, 6, Color(1, 1, 1) if f == 3 else C_GLOW2)
	# the eye at the front
	_px(im, 12, 4, Color(0.95, 1.0, 0.85))
	_px(im, 12, 5, OUT)
	return im

## 20 x 24: hunched, plated, on two thick legs, a great claw forward; walking (0/1), rearing up (2: its tell),
## charging head down (3)
static func _brute_img(f: int) -> Image:
	var im := _blank(20, 24)
	var lean := 0.0 if f < 2 else (-2.0 if f == 2 else 2.5)
	var yb := 2.0 if f == 2 else 0.0
	# legs
	var stp := 1.5 if f == 0 else -1.5
	if f >= 2:
		stp = 0.0
	_line(im, Vector2(8, 15), Vector2(7 - stp, 23), C_LEG)
	_line(im, Vector2(9, 15), Vector2(8 - stp, 23), C_LEG)
	_line(im, Vector2(11, 15), Vector2(12 + stp, 23), C_LEG)
	_line(im, Vector2(12, 15), Vector2(13 + stp, 23), C_LEG)
	_px(im, int(6 - stp), 23, C_DARK)
	_px(im, int(14 + stp), 23, C_DARK)
	# the body: a heavy hunched back of plates
	_shell(im, 9.5 + lean * 0.5, 10.0 - yb, 7.4, 7.0)
	for k in 4:
		_line(im, Vector2(4.0 + lean * 0.5 + float(k) * 2.4, 5.0 - yb + float(k % 2)), Vector2(5.0 + lean * 0.5 + float(k) * 2.4, 3.0 - yb), C_HI)
	# spikes along the spine
	for k2 in 3:
		_px(im, 5 + k2 * 3 + int(lean * 0.5), int(2.0 - yb), C_GLOW.darkened(0.4))
	# head, low and forward, eyes
	var hx := 16.0 + lean
	var hy := 11.0 - yb * 1.5 + (2.0 if f == 3 else 0.0)
	_ell(im, hx, hy, 2.6, 2.2, C_DARK)
	_px(im, int(hx) + 1, int(hy) - 1, C_GLOW)
	_px(im, int(hx), int(hy) - 1, C_GLOW2)
	# the claw: forward at the chest, raised over the head when rearing
	var ca := Vector2(14.0 + lean, 13.0 - yb)
	var cb := Vector2(18.0 + lean, 15.0) if f != 2 else Vector2(17.0, 3.0)
	_line(im, ca, cb, C_DARK)
	_line(im, ca + Vector2(0, 1), cb + Vector2(0, 1), C_MID)
	_px(im, int(cb.x) + 1, int(cb.y), C_HI)
	_px(im, int(cb.x) + 1, int(cb.y) + 2, C_HI)
	# a glowing gland on its side
	_ell(im, 8.0 + lean * 0.5, 12.0 - yb, 1.4, 1.2, C_GLOW)
	return im

## 44 x 32: the Broodmother: a bloated, glowing abdomen behind, a plated thorax on many legs, a crested head
## with a cluster of eyes and a maw (open while she spits, frame 2); 0/1 pulse
static func _brood_img(f: int) -> Image:
	var im := _blank(44, 32)
	var pulse := 0.6 if f == 1 else 0.0
	# legs: five pairs reaching down and out
	for k in 5:
		var hx := 16.0 + float(k) * 3.6
		var sw := sin(float(f) * 1.7 + float(k) * 1.1) * 1.5
		_line(im, Vector2(hx, 18), Vector2(hx - 4.0 + sw, 24.0), C_LEG)
		_line(im, Vector2(hx - 4.0 + sw, 24.0), Vector2(hx - 6.0 + sw, 31.0), C_LEG)
		_line(im, Vector2(hx + 1.0, 18), Vector2(hx + 4.0 - sw, 23.0), C_LEG)
		_line(im, Vector2(hx + 4.0 - sw, 23.0), Vector2(hx + 5.0 - sw, 30.0), C_LEG)
	# the abdomen: bloated, veined with light, egg sacs showing through
	_ell(im, 11.0, 14.0, 10.5 + pulse, 10.0 + pulse, C_DARK)
	_ell(im, 10.0, 12.6, 9.0 + pulse, 8.2 + pulse, C_MID)
	_ell(im, 7.0, 8.5, 3.6, 2.4, C_HI)
	for k2 in 6:
		var a := float(k2) * 1.05 + 0.4
		var c := Vector2(11.0, 14.0) + Vector2(cos(a), sin(a)) * Vector2(5.5, 5.0)
		_ell(im, c.x, c.y, 1.8, 1.5, C_GLOW if (k2 + f) % 2 == 0 else C_GLOW.darkened(0.35))
	_line(im, Vector2(3, 14), Vector2(19, 13), C_GLOW.darkened(0.45))
	# the thorax: plated
	_shell(im, 25.0, 15.0, 8.0, 6.0)
	for k3 in 3:
		_line(im, Vector2(20.0 + float(k3) * 3.5, 10.0), Vector2(21.5 + float(k3) * 3.5, 9.0), C_HI)
	# the head: a crest swept back, eyes in a cluster, a maw
	_ell(im, 35.0, 14.0, 5.4, 4.6, C_DARK)
	_ell(im, 34.5, 13.0, 4.4, 3.4, C_MID)
	for k4 in 4:
		_line(im, Vector2(32.0 + float(k4), 10.0), Vector2(27.0 + float(k4) * 1.5, 3.0 + float(k4)), C_DARK if k4 % 2 == 0 else C_MID)
	for e in [Vector2i(36, 12), Vector2i(38, 12), Vector2i(37, 11), Vector2i(35, 11), Vector2i(39, 13)]:
		_px(im, e.x, e.y, C_GLOW2)
	if f == 2:
		_ell(im, 40.0, 16.5, 2.4, 2.6, OUT)
		_px(im, 40, 16, C_GLOW)
		_px(im, 41, 18, C_GLOW2)
		_line(im, Vector2(39, 14), Vector2(42, 14), C_HI)
		_line(im, Vector2(39, 19), Vector2(42, 20), C_HI)
	else:
		_line(im, Vector2(38, 16), Vector2(41, 17), C_HI)
	return im
