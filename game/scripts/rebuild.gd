## Villages rebuild what was knocked down (user, 23 Nov: "if the village gets destroyed i thing the villagers
## should be able to build their houses back. not build infinite houses but enought o live in again").
##
## Every house of a living village keeps what it is, cell for cell (buildings.gd puts its finished blueprint in
## the house's "struct", on loading too). Now and then one house of a village near you is read back
## (`gpu.request_rect`, no stall) and set against it: a house with more than `DAMAGED` of its built cells gone
## (front or back wall) is rebuilt by its folk, a course at a time from the bottom up, only into empty cells
## (front cells go in fill-only, so nothing you put there is overwritten), never anything it didn't have:
## furniture, doors and torches stay as you left them, and a village never gains a house. A house put right
## rests `RESTS` before it's looked at again. Read again every few seconds while the work goes on, so what
## changes meanwhile (you building, a fire) is taken into account.
extends RefCounted

const CHECK_EVERY := 240      # ticks between looks at a house of a village near you
const DAMAGED := 0.08         # share of its built cells gone before its folk set about it
const STEP_EVERY := 8         # ticks between courses laid
const STEP_CELLS := 18        # cells laid a course
const REREAD_EVERY := 240     # ticks between reads of what's still missing
const RESTS := 60 * 60 * 5    # ticks a house put right is left before it's looked at again
const F_FILL := 0x10000
const F_WALL := 0x40000

var game
var towns
var job := {}         # {house, town, missing (blueprint cell * 2 + layer, bottom row first), i, rid, rid_at}
var _look := {}       # {id, house, town, at}: a house read on its way back, to see whether it needs work
var _turn := 0
var stats := {"checked": 0, "started": 0, "laid": 0, "done": 0}

func _init(g, t) -> void:
	game = g
	towns = t

func tick() -> void:
	if game.space.active or game.travelling:
		return
	if not job.is_empty():
		_work()
		return
	if not _look.is_empty():
		var r: Dictionary = game.gpu.take_rect(int(_look["id"]))
		if r.is_empty():
			if game.frame - int(_look["at"]) > 180:
				_look = {}                    # (lost: try again later)
			return
		var h: Dictionary = _look["house"]
		var miss := _missing(h, r)
		stats["checked"] = int(stats["checked"]) + 1
		var built := int(h.get("built_n", 0))
		if built > 0 and float(miss.size()) >= float(built) * DAMAGED:
			_start(h, _look["town"], miss)
		else:
			h["rest_until"] = game.frame + CHECK_EVERY * 4
		_look = {}
		return
	if game.frame % CHECK_EVERY != 7:
		return
	var t := _near_town()
	if t.is_empty():
		return
	var hs: Array = t.get("houses", [])
	for n in hs.size():
		_turn += 1
		var h2: Dictionary = hs[_turn % hs.size()]
		if not h2.has("struct") or int(h2.get("rest_until", 0)) > game.frame:
			continue
		look_at(h2, t)
		return

## read a house back to see whether it needs rebuilding (also the tests' way in)
func look_at(h: Dictionary, t: Dictionary) -> void:
	var st: Dictionary = h["struct"]
	_look = {"id": game.gpu.request_rect(int(st["x0"]), int(st["y0"]), int(st["w"]), int(st["h"]), int(st["ax"]), int(st["aw"])),
		"house": h, "town": t, "at": game.frame}

## the nearest living village within towns.gd's NEAR of you, or {}
func _near_town() -> Dictionary:
	var pc: float = fposmod(atan2(game.player.pos.y, game.player.pos.x), TAU) / TAU * float(Defs.NS)
	var best := {}
	var bd := 520.0                     # (towns.gd NEAR)
	for t in game.builds.towns:
		if not t.get("living", false):
			continue
		var mid: float = float(t["x0"]) + float(t["w"]) * 0.5
		var d: float = absf(fposmod(mid - pc + float(Defs.NS) * 0.5, float(Defs.NS)) - float(Defs.NS) * 0.5)
		if d < bd:
			bd = d
			best = t
	return best

## what a blueprint cell holds that its folk would put back, in front (0 = nothing)
static func _want_front(v: int) -> int:
	var f := v & 255
	if f == 255 or f == 0 or (v & F_FILL) != 0 or Defs.KIND[f] != Defs.K_SOLID:
		return 0
	if f == Defs.WOODDOOR or f == Defs.TORCH or f == Defs.DECOR or f == Defs.OPENCHEST:
		return 0
	return f

## ... and behind (back walls; never furniture or torches: they're yours to take)
static func _want_back(v: int) -> int:
	var b := (v >> 8) & 255
	if b == 255 or b == 0 or b == Defs.DECOR or b == Defs.TORCH or b == Defs.OPENCHEST:
		return 0
	return b

## the cells of house h missing in the read r (blueprint cell * 2, + 1 for the back layer), bottom row first
func _missing(h: Dictionary, r: Dictionary) -> PackedInt32Array:
	var st: Dictionary = h["struct"]
	var data: PackedInt32Array = st["data"]
	var w: int = st["w"]
	var hh: int = st["h"]
	var fg: PackedInt32Array = r["fg"]
	var bg: PackedInt32Array = r["bg"]
	var out := PackedInt32Array()
	var n_built := 0
	for j in range(hh - 1, -1, -1):
		var row := j * w
		for i in w:
			var k := row + i
			var v: int = data[k]
			if _want_front(v) != 0:
				n_built += 1
				var wf: int = fg[k] & 255
				if wf == Defs.AIR or wf == Defs.FIRE or wf == Defs.SMOKE or wf == Defs.STEAM:
					out.append(k * 2)
			if _want_back(v) != 0:
				n_built += 1
				if (bg[k] & 255) == 0:
					out.append(k * 2 + 1)
	h["built_n"] = n_built
	return out

func _start(h: Dictionary, t: Dictionary, miss: PackedInt32Array) -> void:
	job = {"house": h, "town": t, "missing": miss, "i": 0, "rid": -1, "rid_at": game.frame, "reads": 0}
	stats["started"] = int(stats["started"]) + 1
	game.ui.toast("The folk of %s set about rebuilding a house" % String(t.get("name", "the village")), Color(0.95, 0.85, 0.55), 3.5)

func _work() -> void:
	var h: Dictionary = job["house"]
	var st: Dictionary = h["struct"]
	# (what's still missing, read again now and then)
	if int(job["rid"]) >= 0:
		var r: Dictionary = game.gpu.take_rect(int(job["rid"]))
		if not r.is_empty():
			job["reads"] = int(job["reads"]) + 1
			# (a whole pass laid nothing: what's left is where someone stands, or can't be filled; as whole as it gets)
			var stuck: bool = int(job["i"]) >= (job["missing"] as PackedInt32Array).size() and int(job.get("pass_laid", 1)) == 0
			job["missing"] = _missing(h, r)
			job["i"] = 0
			job["pass_laid"] = 0
			job["rid"] = -1
			if (job["missing"] as PackedInt32Array).is_empty() or stuck or int(job["reads"]) > 60:
				_done()                        # (whole again; or as whole as it gets)
				return
	elif game.frame - int(job["rid_at"]) >= REREAD_EVERY:
		job["rid"] = game.gpu.request_rect(int(st["x0"]), int(st["y0"]), int(st["w"]), int(st["h"]), int(st["ax"]), int(st["aw"]))
		job["rid_at"] = game.frame
	if game.frame % STEP_EVERY != 0:
		return
	var miss: PackedInt32Array = job["missing"]
	var i0: int = job["i"]
	if i0 >= miss.size():
		if int(job["rid"]) < 0:
			job["rid_at"] = -REREAD_EVERY          # (all laid: read it once more to be sure)
		return
	var w: int = st["w"]
	var data: PackedInt32Array = st["data"]
	var ax: int = st["ax"]
	var aw: int = st["aw"]
	# the next course: up to STEP_CELLS cells, none where someone stands
	var put := {}
	var bi0 := w
	var bi1 := -1
	var bj0 := int(st["h"])
	var bj1 := -1
	var mid := Vector2.ZERO
	var n := 0
	var at := i0
	while at < miss.size() and n < STEP_CELLS:
		var e: int = miss[at]
		at += 1
		var k := e >> 1
		var i := k % w
		var j := k / w
		var wp: Vector2 = Defs.stamp_pos(int(st["y0"]) + j, ax, aw, Defs.k_of(int(st["x0"]) + i, ax))
		if _someone_at(wp):
			continue
		var v: int = data[k]
		var cur: int = int(put.get(k, 0xffff))
		if (e & 1) == 0:
			cur = (cur & 0xff00) | (v & 255) | F_FILL | (v & ~0xffff & ~F_WALL)
		else:
			cur = (cur & ~0xff00) | (v & 0xff00) | (v & F_WALL) | (v & 0x20000) | (v & 0xff80000 if (v & 0x8000000) != 0 else 0)
		put[k] = cur
		bi0 = mini(bi0, i)
		bi1 = maxi(bi1, i)
		bj0 = mini(bj0, j)
		bj1 = maxi(bj1, j)
		mid += wp
		n += 1
	job["i"] = at
	job["pass_laid"] = int(job.get("pass_laid", 0)) + n
	if n == 0:
		return
	var sw := bi1 - bi0 + 1
	var sh := bj1 - bj0 + 1
	var sub := PackedInt32Array()
	sub.resize(sw * sh)
	sub.fill(0xffff)
	for k2 in put:
		var i2: int = int(k2) % w - bi0
		var j2: int = int(k2) / w - bj0
		sub[j2 * sw + i2] = int(put[k2])
	game.stamps.append({"x0": posmod(int(st["x0"]) + bi0, Defs.NS), "y0": int(st["y0"]) + bj0, "w": sw, "h": sh, "data": sub, "ax": ax, "aw": aw})
	stats["laid"] = int(stats["laid"]) + n
	mid /= float(n)
	if game.frame % (STEP_EVERY * 3) == 0:
		game.audio.play("place", mid, 0.35)
	game.vfx.place_flash(mid, 4.0)

## a mage, a villager or a foe standing on world point p
func _someone_at(p: Vector2) -> bool:
	for m in game.players:
		if m.pos.distance_to(p) < 11.0:
			return true
	for v in towns.folk:
		if v.pos.distance_to(p) < 10.0:
			return true
	return false

func _done() -> void:
	var h: Dictionary = job["house"]
	h["rest_until"] = game.frame + RESTS
	stats["done"] = int(stats["done"]) + 1
	game.ui.toast("%s's house stands again" % String(job["town"].get("name", "The village")), Color(0.95, 0.85, 0.55), 3.0)
	job = {}
