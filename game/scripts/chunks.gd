extends RefCounted
## Rigid chunks: a tree that is cut down, and a piece of a building that breaks loose, come away as
## whole pixel pieces (a trunk with its crown, slabs of wall with their back wall and furniture) that
## fall, topple, spin and tumble as rigid bodies, then settle back into the world as cells. Only the
## edges that hit hard splinter (chips and dust as particles, a little rubble); the rest lands whole.
##
## Finding a piece: every frame the GPU reports, near each mage, one cell of a felled tree (grid.comp
## counts[59] / [60]) and one creaking block about to fall (counts[56] / [57]). detect() reads the world
## around it (gpu.read_rect), works out which cells came loose (a tree: the cells of that plant no longer
## joined to wood on the ground; a building: the loose blocks and the back walls and furniture hanging
## off them), splits a building piece into fragments, takes them out of the world with a stamp and makes
## a Chunk of each. Cells it doesn't take (too many pieces already, far from any mage) fall the old way.
##
## Moving: update() steps each chunk as a rigid body (gravity toward the core, one averaged contact a
## step with an impulse, friction and a little bounce) against the mage's collision grid and the other
## chunks. A chunk that has come to rest is set back down with a raw stamp (gpu_world.gd stamp, mode 1):
## blocks as unanchored built cells, so they obey the physics again; a tree in the background as a
## fallen plant of its own (plants.comp holds it up by its trunk lying on the ground).
##
## Its pixels: the colours are taken from the picture on screen where the cell was drawn (divided by the
## light there), so bricks keep their mortar and bark its grain; the palette fills in for cells hidden or
## off screen. overlay.gd draws each chunk turned by its rotation.

const Build := preload("res://scripts/build.gd")
const Props := preload("res://scripts/props.gd")

const GRAV := 0.17                # as for bodies (cells per frame per frame, times the planet's pull)
const MAX_CHUNKS := 28
const MAX_PTS := 90               # collision points per chunk (its outline, thinned)
const MAX_SOFT := 140             # crown-edge points checked for crushing
const ROCK_HURT_FALL := 8.0       # (as main.gd's: how far a piece must fall before it hurts)
const SMALL_TREE := 25            # felled bits smaller than this just flutter away as leaves
const REST := 0.12                # bounce
const MU := 0.55                  # friction
const BREAK_SPEED := 1.7          # an edge landing faster than this (cells a frame) splinters
const SLEEP_V := 0.07
const SLEEP_FRAMES := 20
const MAX_AGE := 900
const TREE_READ := Vector2i(170, 210)     # how much is read around a felled tree's reported cell
const BLOCK_READ := Vector2i(240, 190)    # and around a creaking block
const FRAG_MIN := 9.0             # fragment size (cells across) for small pieces; big ones break coarser
const MAX_FRAGS := 26
const ST_BUILT := 0x80000000
const ST_ANCHOR := 0x40000000
const BG_WALL := 0x4000
const BG_ANCHOR := 0x8000

class Chunk:
	var pos := Vector2.ZERO        # world position of its centre of mass
	var vel := Vector2.ZERO        # world, cells per frame
	var phi := 0.0                 # how far it has turned since it broke loose (world, anticlockwise)
	var omega := 0.0
	var a0 := 0.0                  # the angle round the planet where it broke loose (its pixels' frame)
	var tree := false
	var px := PackedVector2Array() # each pixel's position in its own frame (x along the surface, y down), from its centre of mass
	var key := {}                  # Vector2i(pixel) -> index, for setting it down
	var fg := PackedInt32Array()   # each pixel's front cell (0: none)
	var bg := PackedInt32Array()   # and its background cell (0: none)
	var cf := PackedColorArray()   # front colour (alpha 0: none)
	var cb := PackedColorArray()   # background colour
	var ip := PackedVector2Array() # integer pixel coordinates (for the key and the pictures)
	var com := Vector2.ZERO        # centre of mass in pixel coordinates
	var pts := PackedVector2Array()  # collision points (outline pixels, from the centre of mass)
	var soft := PackedVector2Array() # a tree's crown edge: leaves that crush (knocked off) where they touch ground
	var soft_k := PackedInt32Array() # (their pixel indices)
	var mass := 1.0
	var inertia := 1.0
	var radius := 1.0
	var rest_t := 0
	var rest_pos := Vector2.ZERO   # where it was when it last moved noticeably
	var rest_phi := 0.0
	var age := 0
	var hit := {}                  # bodies it has already struck
	var tex_f: ImageTexture
	var tex_b: ImageTexture
	var img_origin := Vector2.ZERO # the pictures' top-left corner, in its frame from the centre of mass
	var dirty := true              # pictures need remaking
	var fam := 0                   # pieces broken off together (they don't shove each other apart at first)

var g                              # the game (main.gd)
var list: Array = []
var _recent := []                  # [world position, frame]: places already read (a piece shows for a while)
var _occ := {}                     # world cell -> chunk, for chunks resting on each other
var _fam := 0
var _solid := PackedByteArray()    # per material: does it stop a chunk
var _grid := PackedByteArray()
var _gbase := 0
var _gs := 0
var _pal := []                     # palette colours (material * 4 + variant), and furniture's
var _decor := []

func _init(game) -> void:
	g = game
	for k in Defs.NM * 4:
		_pal.append(Color.hex((Defs.PAL[k] << 8) | 0xff))
	for hx in Props.PALETTE:
		_decor.append(Color.html(hx))
	_solid.resize(64)
	for t in Defs.NM:
		var k: int = Defs.KIND[t]
		_solid[t] = 1 if (k == Defs.K_SOLID or k == Defs.K_POWDER) and t != Defs.TREASURE and t != Defs.SCAFFOLD else 0

func clear() -> void:
	list.clear()
	_recent.clear()

# ------------------------------------------------------------------ frames ---

## the frame of a chunk's pixels: x along the surface (screen right), y toward the core
func _axes(c: Chunk) -> Array:
	return [g.basis_r(c.a0).rotated(c.phi), g.basis_d(c.a0).rotated(c.phi)]

func _to_world(c: Chunk, ax: Array, v: Vector2) -> Vector2:
	return c.pos + (ax[0] as Vector2) * v.x + (ax[1] as Vector2) * v.y

func _to_local(c: Chunk, ax: Array, w: Vector2) -> Vector2:
	var d := w - c.pos
	return Vector2(d.dot(ax[0]), d.dot(ax[1]))

## where a shell-0 cell's centre is
static func cell_pos(col: int, row: int) -> Vector2:
	var a := (float(posmod(col, Defs.SH_N[0])) + 0.5) / Defs.SH_N[0] * TAU
	return Vector2(cos(a), sin(a)) * (Defs.R_TOP - (float(row) + 0.5))

## On screen, a chunk's pixels are turned by this (canvas radians, clockwise): `ref` is the angle round
## the planet whose "up" is up on screen (the chunk's own place in the unrolled view, the camera's on
## the round map).
func screen_angle(c: Chunk, ref: float) -> float:
	return -(c.phi + wrapf(c.a0 - ref, -PI, PI))

## its two pictures (background layer, front layer), remade when pixels have broken off
func textures(c: Chunk) -> void:
	if not c.dirty and c.tex_f != null:
		return
	c.dirty = false
	if c.ip.is_empty():
		return
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	for p in c.ip:
		mn = mn.min(p)
		mx = mx.max(p)
	var w := int(mx.x - mn.x) + 1
	var h := int(mx.y - mn.y) + 1
	var imf := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var imb := Image.create(w, h, false, Image.FORMAT_RGBA8)
	imf.fill(Color(0, 0, 0, 0))
	imb.fill(Color(0, 0, 0, 0))
	for k in c.ip.size():
		var q := Vector2i(c.ip[k] - mn)
		if c.fg[k] != 0:
			imf.set_pixelv(q, c.cf[k])
		if c.bg[k] != 0:
			imb.set_pixelv(q, c.cb[k])
	c.tex_f = ImageTexture.create_from_image(imf)
	c.tex_b = ImageTexture.create_from_image(imb)
	c.img_origin = mn - Vector2(0.5, 0.5) - c.com

# ------------------------------------------------------------------ finding ---

## Called with each mage's counters from the last GPU frame.
func detect(m, cn: PackedInt32Array) -> void:
	if list.size() >= MAX_CHUNKS or cn.size() < 61:
		return
	g._use_grid(m)
	if cn[59] > 0:
		var u: int = cn[60] & 0xFFFFFFFF
		var wp: Vector2 = g.from_grid(Vector2((u & 1023) + 0.5, ((u >> 10) & 1023) + 0.5))
		# (a tree just lifted out is gone from the world by the next frame, so only a short pause here:
		# a long one left the rest of a big tree, or the next tree felled, crumbling meanwhile)
		if not _seen(wp, 20.0, 6):
			_take_tree(m, wp)
	if cn[56] > 0 and list.size() < MAX_CHUNKS:
		var u2: int = cn[57] & 0xFFFFFFFF
		var wp2: Vector2 = g.from_grid(Vector2((u2 & 1023) + 0.5, ((u2 >> 10) & 1023) + 0.5))
		if not _seen(wp2, 20.0, 8):
			_take_block(m, wp2)
	g._use_grid(g.player)

func _seen(p: Vector2, r: float, frames: int) -> bool:
	for k in range(_recent.size() - 1, -1, -1):
		var e: Array = _recent[k]
		if g.frame - int(e[1]) > 90:
			_recent.remove_at(k)
		elif (e[0] as Vector2).distance_to(p) < r and g.frame - int(e[1]) < frames:
			return true
	_recent.append([p, g.frame])
	return false

## reads a block of shell-0 cells around a world point; [col0, row0, w, h, fg, bg] or [] past shell 0
func _read_around(p: Vector2, size: Vector2i, up_frac: float) -> Array:
	var cc: Vector2i = Build.cell_of(p)
	var w := size.x
	var h := size.y
	var c0 := cc.x - w / 2
	var r0 := cc.y - int(h * up_frac)
	r0 = clampi(r0, 0, Defs.SH_Y0[1] - 1)
	h = mini(h, Defs.SH_Y0[1] - r0)
	if h < 8 or cc.y >= Defs.SH_Y0[1]:
		return []
	var rr: Dictionary = g.gpu.read_rect(c0, r0, w, h)
	return [c0, r0, w, h, rr["fg"], rr["bg"]]

## A felled tree: the cells of that plant (its id is in background bits 16-31) no longer joined, through
## each other, to its wood resting on the ground.
func _take_tree(m, wp: Vector2) -> void:
	var tr := Time.get_ticks_usec()
	var R := _read_around(wp, TREE_READ, 0.6)
	g.prof_add("lift: read", Time.get_ticks_usec() - tr)
	tr = Time.get_ticks_usec()
	if R.is_empty():
		return
	var c0: int = R[0]
	var r0: int = R[1]
	var w: int = R[2]
	var h: int = R[3]
	var fgs: PackedInt32Array = R[4]
	var bgs: PackedInt32Array = R[5]
	var cc: Vector2i = Build.cell_of(wp)
	var ii := posmod(cc.x - c0, Defs.SH_N[0])
	var jj := cc.y - r0
	if ii < 0 or ii >= w or jj < 0 or jj >= h:
		return
	var pid := (bgs[jj * w + ii] >> 16) & 0xFFFF
	if (pid & 0x8000) == 0:
		return
	# the plant's cells (all of them in the block: a crown tangled with a neighbour's isn't always joined
	# up through its own cells), and those still standing: joined to wood (or a stem) touching the ground
	# (marks per cell of the block: 1 the plant's, 2 still standing, 3 loose and taken into a piece)
	var mark := PackedByteArray()
	mark.resize(w * h)
	var mine := PackedInt32Array()
	for k in w * h:
		var b: int = bgs[k]
		if ((b >> 16) & 0xFFFF) == pid and (b & 255) != 0:
			mark[k] = 1
			mine.append(k)
	var q := PackedInt32Array()
	var bush := (pid >> 14) == 3          # a bush (or a fallen tree) is held by any of it on the ground
	for k in mine:
		var bm: int = bgs[k] & 255
		if not bush and (bm == Defs.LEAF or bm == Defs.SNOW or bm == Defs.CAP):
			continue
		if _grounded(k, w, h, fgs, bush):
			mark[k] = 2
			q.append(k)
	_spread(q, mark, w, h, 1, 2, null)
	var loose := PackedInt32Array()
	for k in mine:
		if mark[k] == 1:
			loose.append(k)
	g.prof_add("lift: find", Time.get_ticks_usec() - tr)
	if loose.is_empty():
		return
	var tp := Time.get_ticks_usec()
	# what came loose, split into the pieces actually joined together: each falls on its own (a few
	# stray cells must not fall as one object with a gap through it), and scraps flutter away as leaves
	var pieces: Array = []
	for k in loose:
		if mark[k] != 1:
			continue
		mark[k] = 3
		var comp := PackedInt32Array([k])
		_spread(PackedInt32Array([k]), mark, w, h, 1, 3, comp)
		pieces.append(Array(comp))
	var scraps: Array = []
	var cleared: Array = []
	var side := 0.0
	for bit in pieces:
		if bit.size() < SMALL_TREE or list.size() >= MAX_CHUNKS:
			scraps.append_array(bit)
			continue
		_fam += 1
		var c := _make(bit, R, false, true)
		if c == null:
			scraps.append_array(bit)
			continue
		cleared.append_array(bit)
		if g.testing:
			print("[chunks] tree at %s: %d cells" % [str(Build.cell_of(c.pos)), bit.size()])
		# it starts to topple: away from whoever felled it, now and then toward them
		if side == 0.0:
			side = signf((c.pos - m.pos).dot(g.basis_r(atan2(c.pos.y, c.pos.x))))
			if side == 0.0 or randf() < 0.2:
				side = -side if side != 0.0 else 1.0
		c.omega = -side * (0.004 + randf() * 0.003)
		g.audio.play("crack", c.pos, 0.9)
	# a scrap of a crown or a twig flutters away as leaves rather than crumbling into specks
	for k in scraps:
		if randf() < 0.5:
			var lp := cell_pos(c0 + k % w, r0 + k / w)
			g._particle(lp, Vector2(randf() - 0.5, randf() - 0.7) * 0.4, 40 + randi() % 40, _colour_of(0, bgs[k], R, k, false), false, 0.015)
	cleared.append_array(scraps)
	g.prof_add("lift: make", Time.get_ticks_usec() - tp)
	tp = Time.get_ticks_usec()
	_clear(R, [], cleared, [])
	g.prof_add("lift: clear", Time.get_ticks_usec() - tp)

## Flood through the 8 neighbours from the cells in `q`: cells marked `from` become `to` (and are
## added to `got`, if given).
func _spread(q: PackedInt32Array, mark: PackedByteArray, w: int, h: int, from: int, to: int, got) -> void:
	while not q.is_empty():
		var k: int = q[q.size() - 1]
		q.resize(q.size() - 1)
		var i := k % w
		var j := k / w
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, w - 1)
		for nj in range(maxi(j - 1, 0), mini(j + 2, h)):
			var row := nj * w
			for ni in range(i0, i1 + 1):
				var n := row + ni
				if mark[n] == from:
					mark[n] = to
					q.append(n)
					if got != null:
						got.append(n)

## A piece of a building breaking loose: the loose blocks joined to the creaking one, with the back
## walls and furniture that hang off them; broken into fragments along jagged lines.
func _take_block(m, wp: Vector2) -> void:
	var R := _read_around(wp, BLOCK_READ, 0.55)
	if R.is_empty():
		return
	var c0: int = R[0]
	var r0: int = R[1]
	var w: int = R[2]
	var h: int = R[3]
	var fgs: PackedInt32Array = R[4]
	var bgs: PackedInt32Array = R[5]
	var cc: Vector2i = Build.cell_of(wp)
	var ii := posmod(cc.x - c0, Defs.SH_N[0])
	var jj := cc.y - r0
	if ii < 1 or ii >= w - 1 or jj < 1 or jj >= h - 1:
		return
	var start := jj * w + ii
	if not _loose_fg(fgs[start]):
		return
	var seen := {start: true}
	var q: Array = [start]
	var region: Array = []
	var fgk: Array = []
	var bgk: Array = []
	while not q.is_empty() and region.size() < 20000:
		var k: int = q.pop_back()
		region.append(k)
		var lf := _loose_fg(fgs[k])
		var lb := _loose_bg(bgs[k])
		if lf:
			fgk.append(k)
		if lb:
			bgk.append(k)
		var i: int = k % w
		var j: int = k / w
		for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
			var ni: int = i + d.x
			var nj: int = j + d.y
			if ni < 0 or nj < 0 or ni >= w or nj >= h:
				continue
			var k2 := nj * w + ni
			if seen.has(k2):
				continue
			if _loose_fg(fgs[k2]) or _loose_bg(bgs[k2]):
				seen[k2] = true
				q.append(k2)
	if fgk.size() < 4:
		return
	# fragments: a grid of blocks about `frag` across, its lines staggered (like courses of masonry) and
	# jittered so the breaks are jagged; each block split again where it falls apart
	var frag := maxf(FRAG_MIN, sqrt(float(region.size()) / float(MAX_FRAGS) * 1.6))
	var group := {}
	for k in region:
		var x: int = k % w
		var y: int = k / w
		var bx := float(posmod(hash(int(y / 3) * 7919 + _fam * 31), 100)) * 0.01 * frag * 0.6
		var by := float(posmod(hash(int(x / 4) * 104729 + _fam * 17), 100)) * 0.01 * frag * 0.6
		group[k] = Vector2i(int(floor((float(x) + bx) / frag)), int(floor((float(y) + by) / frag)))
	var parts: Array = []
	var done := {}
	for k in region:
		if done.has(k):
			continue
		var comp: Array = []
		var q2: Array = [k]
		done[k] = true
		while not q2.is_empty():
			var k4: int = q2.pop_back()
			comp.append(k4)
			var i4: int = k4 % w
			var j4: int = k4 / w
			for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				var ni4: int = i4 + d.x
				var nj4: int = j4 + d.y
				if ni4 < 0 or nj4 < 0 or ni4 >= w or nj4 >= h:
					continue
				var k5 := nj4 * w + ni4
				if not done.has(k5) and group.has(k5) and group[k5] == group[k]:
					done[k5] = true
					q2.append(k5)
		parts.append(comp)
	parts.sort_custom(func(a, b): return a.size() > b.size())
	_fam += 1
	var taken: Array = []
	var crumbs: Array = []
	for piece in parts:
		if piece.size() < 5 or list.size() >= MAX_CHUNKS:
			crumbs.append_array(piece)
			continue
		var ch := _make(piece, R, true, false)
		if ch == null:
			crumbs.append_array(piece)
			continue
		ch.omega = (randf() - 0.5) * 0.01
		taken.append_array(piece)
	if taken.is_empty():
		return
	# take the fragments out of the world; the crumbs too (as dust and a little rubble)
	var tf: Array = []
	var tb: Array = []
	for k in taken:
		if _loose_fg(fgs[k]):
			tf.append(k)
		if _loose_bg(bgs[k]):
			tb.append(k)
	var rubble: Array = []
	for k in crumbs:
		if _loose_fg(fgs[k]):
			tf.append(k)
			if randf() < 0.5:
				rubble.append([k, int(Defs.DEBRIS[fgs[k] & 255])])
			_dust(cell_pos(c0 + k % w, r0 + k / w), _colour_of(fgs[k], 0, R, k, false))
		if _loose_bg(bgs[k]):
			tb.append(k)
	_clear(R, tf, tb, [])
	if g.testing:
		print("[chunks] piece at %s: %d blocks, %d background cells, %d fragments, %d crumbs" % [str(Build.cell_of(wp)), tf.size(), tb.size(), list.size(), crumbs.size()])
	for rb in rubble:
		if int(rb[1]) != 0 and int(rb[1]) != (fgs[int(rb[0])] & 255):
			_put(c0 + int(rb[0]) % w, r0 + int(rb[0]) / w, int(rb[1]) | (fgs[int(rb[0])] & 0xff00), -1)
	g.audio.play("crack", wp, 0.7)

## Is this plant cell held by what's around it? The same rule as plants.comp, so a tree the GPU holds up
## is never lifted out whole: a tree's wood touching solid ground, or resting on settled powder, or on
## mud or water (a root one cell above the mud still counts); a bush by any block or liquid below.
const N4 := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]

func _grounded(k: int, w: int, h: int, fgs: PackedInt32Array, bush: bool) -> bool:
	var i := k % w
	var j := k / w
	var tD := _fg_at(fgs, i, j + 1, w, h)
	var lD := (_raw_at(fgs, i, j + 1, w, h) >> 16) & 255
	if bush:
		for d in N4:
			var tn := _fg_at(fgs, i + d.x, j + d.y, w, h)
			if tn != 0 and (Defs.KIND[tn] == Defs.K_SOLID or Defs.KIND[tn] == Defs.K_POWDER):
				return true
		return tD != 0 and Defs.KIND[tD] == Defs.K_LIQUID
	for d2 in N4:
		var tn2 := _fg_at(fgs, i + d2.x, j + d2.y, w, h)
		if tn2 != 0 and Defs.KIND[tn2] == Defs.K_SOLID:
			return true
	if _rests_on(tD, lD):
		return true
	if tD == 0:
		return _rests_on(_fg_at(fgs, i, j + 2, w, h), (_raw_at(fgs, i, j + 2, w, h) >> 16) & 255) or Defs.KIND[_fg_at(fgs, i, j + 2, w, h)] == Defs.K_SOLID
	return false

func _rests_on(t: int, life: int) -> bool:
	if t == 0:
		return false
	var kd: int = Defs.KIND[t]
	return (kd == Defs.K_POWDER and t != Defs.LITTER and t != Defs.TIMBER) or (kd == Defs.K_LIQUID and life != 1)

func _fg_at(fgs: PackedInt32Array, i: int, j: int, w: int, h: int) -> int:
	return _raw_at(fgs, i, j, w, h) & 255

func _raw_at(fgs: PackedInt32Array, i: int, j: int, w: int, h: int) -> int:
	if i < 0 or j < 0 or i >= w or j >= h:
		return 0
	return fgs[j * w + i]

func _loose_fg(v: int) -> bool:
	var t := v & 255
	if t == 0 or t == Defs.TREASURE or t == Defs.WOODDOOR:
		return false
	return Defs.KIND[t] == Defs.K_SOLID and (v & ST_ANCHOR) == 0 and ((v >> 24) & 63) > Defs.SPAN[t]

func _loose_bg(a: int) -> bool:
	var bm := a & 255
	if bm == 0 or (a & 0x80000000) != 0 or (a & BG_ANCHOR) != 0:
		return false
	return ((a >> 8) & 63) > Defs.SPAN[bm]

## A chunk of the cells `ks` (indices into the read block R). Front cells only where `with_fg` (a
## tree is all background).
func _make(ks: Array, R: Array, with_fg: bool, tree: bool) -> Chunk:
	var c0: int = R[0]
	var r0: int = R[1]
	var w: int = R[2]
	var fgs: PackedInt32Array = R[4]
	var bgs: PackedInt32Array = R[5]
	var c := Chunk.new()
	c.tree = tree
	c.fam = _fam
	var n := 0
	var sum := Vector2.ZERO
	for k in ks:
		var f: int = fgs[k] if with_fg and _loose_fg(fgs[k]) else 0
		var b: int = bgs[k] if (tree or _loose_bg(bgs[k])) else 0
		if f == 0 and b == 0:
			continue
		# its pixel: x grows to the right on screen (columns grow the other way), y down
		var ip := Vector2i(-(k % w), k / w)
		c.ip.append(Vector2(ip))
		c.key[ip] = n
		c.fg.append(f)
		c.bg.append(b)
		c.cf.append(_colour_of(f, 0, R, k, false) if f != 0 else Color(0, 0, 0, 0))
		c.cb.append(_colour_of(0, b, R, k, f != 0) if b != 0 else Color(0, 0, 0, 0))
		sum += Vector2(ip)
		n += 1
	if n < 4:
		return null
	c.com = sum / float(n)
	# its place: the centre of mass, in the frame at the angle where it broke loose
	var kk: int = ks[0]
	var ref := cell_pos(c0 + kk % w, r0 + kk / w)
	c.a0 = atan2(ref.y, ref.x)
	var ref_ip := Vector2(-(kk % w), kk / w)
	c.pos = ref + g.basis_r(c.a0) * (c.com.x - ref_ip.x) + g.basis_d(c.a0) * (c.com.y - ref_ip.y)
	_rebuild(c)
	list.append(c)
	return c

## mass, turning inertia, outline (collision points) and pictures, from its pixels
func _rebuild(c: Chunk) -> void:
	var n := c.ip.size()
	c.px.resize(n)
	var I := 0.0
	var rmax := 0.0
	for k in n:
		var v: Vector2 = c.ip[k] - c.com
		c.px[k] = v
		I += v.length_squared() + 0.17
		rmax = maxf(rmax, v.length())
	c.mass = float(n)
	c.inertia = maxf(I, 1.0)
	c.radius = rmax + 1.0
	# what it collides with: its outline. A tree's crown is soft (leaves give way and crush against the
	# ground), so a tree collides by its wood alone: the trunk comes to lie on the ground, not propped
	# up on its leaves
	var hard: Dictionary = c.key        # (a building piece: all of it)
	if c.tree:
		hard = {}
		for k in n:
			var bm: int = c.bg[k] & 255
			if c.fg[k] != 0 or (bm != Defs.LEAF and bm != Defs.SNOW and bm != Defs.CAP):
				hard[Vector2i(c.ip[k])] = true
		if hard.is_empty():
			hard = c.key
	var outline := PackedVector2Array()
	for k in n:
		var p: Vector2i = Vector2i(c.ip[k])
		if not hard.has(p):
			continue
		if not hard.has(p + Vector2i(1, 0)) or not hard.has(p - Vector2i(1, 0)) or not hard.has(p + Vector2i(0, 1)) or not hard.has(p - Vector2i(0, 1)):
			outline.append(c.px[k])
	var stride := maxi(1, int(ceil(float(outline.size()) / float(MAX_PTS))))
	c.pts = PackedVector2Array()
	for k in range(0, outline.size(), stride):
		c.pts.append(outline[k])
	# a tree's crown edge: leaves on the outside of the whole piece, checked each step for crushing
	c.soft = PackedVector2Array()
	c.soft_k = PackedInt32Array()
	if c.tree:
		var edge := PackedInt32Array()
		for k in n:
			var p2: Vector2i = Vector2i(c.ip[k])
			if hard.has(p2):
				continue
			if not c.key.has(p2 + Vector2i(1, 0)) or not c.key.has(p2 - Vector2i(1, 0)) or not c.key.has(p2 + Vector2i(0, 1)) or not c.key.has(p2 - Vector2i(0, 1)):
				edge.append(k)
		var st2 := maxi(1, int(ceil(float(edge.size()) / float(MAX_SOFT))))
		for k in range(0, edge.size(), st2):
			c.soft.append(c.px[edge[k]])
			c.soft_k.append(edge[k])
	c.dirty = true

## A cell's colour as it was drawn on screen (divided by the light there), or its palette colour when
## it's hidden, off screen or too dark to tell.
func _colour_of(f: int, b: int, R: Array, k: int, hidden: bool) -> Color:
	var w: int = R[2]
	var col: int = int(R[0]) + k % w
	var row: int = int(R[1]) + k / w
	var t := (f & 255) if f != 0 else (b & 255)
	var v := (f >> 8) & 255 if f != 0 else 0
	var pal: Color = _pal[t * 4 + (v & 3)]
	if f == 0:
		if t == Defs.DECOR:
			pal = _decor[((b >> 16) & 63) % _decor.size()]
		pal = pal * Color(0.72, 0.72, 0.76)             # background layers are drawn darker
		pal.a = 1.0
	if hidden or g.gpu.view_img == null:
		return pal
	# (where the cell is on screen: one step from the block's corner, worked out once per block)
	if R.size() < 7:
		var s0: Vector2 = g.world_to_screen(cell_pos(int(R[0]), int(R[1])))
		R.append([s0, g.world_to_screen(cell_pos(int(R[0]) + 1, int(R[1]))) - s0, g.world_to_screen(cell_pos(int(R[0]), int(R[1]) + 1)) - s0])
		R.append({})                                    # light by light cell (each covers several pixels)
	var lin: Array = R[6]
	var sp: Vector2 = ((lin[0] as Vector2) + (lin[1] as Vector2) * float(k % w) + (lin[2] as Vector2) * float(k / w)).floor()
	var img: Image = g.gpu.view_img
	if sp.x < 0 or sp.y < 0 or sp.x >= img.get_width() or sp.y >= img.get_height():
		return pal
	var ls: int = g.gpu.LS
	var lk: int = int(sp.x) / ls * 65536 + int(sp.y) / ls
	var lc: Dictionary = R[7]
	var lit: Color
	if lc.has(lk):
		lit = lc[lk]
	else:
		lit = g.gpu.light_at(sp)
		lc[lk] = lit
	var lum := (lit.r + lit.g + lit.b) / 3.0
	if lum < 0.25:
		return pal
	var s := img.get_pixel(int(sp.x), int(sp.y))
	var cap := Color(clampf(s.r / maxf(lit.r, 0.2), 0, 1), clampf(s.g / maxf(lit.g, 0.2), 0, 1), clampf(s.b / maxf(lit.b, 0.2), 0, 1), 1.0)
	# what's on screen there may not be this cell (sky through a gap in the leaves, a sprite in front):
	# only trust a colour near the material's own
	if absf(cap.r - pal.r) + absf(cap.g - pal.g) + absf(cap.b - pal.b) > 0.45:
		return pal
	return cap

## a stamp taking cells out of the world: front cells `tf`, background cells `tb` (+ `tb2`)
func _clear(R: Array, tf: Array, tb: Array, tb2: Array) -> void:
	var c0: int = R[0]
	var r0: int = R[1]
	var w: int = R[2]
	# the stamp covers just the box around the cells it clears
	var i0 := w
	var j0 := 1 << 30
	var i1 := -1
	var j1 := -1
	for arr in [tf, tb, tb2]:
		for k in arr:
			var ki: int = k % w
			var kj: int = k / w
			i0 = mini(i0, ki)
			i1 = maxi(i1, ki)
			j0 = mini(j0, kj)
			j1 = maxi(j1, kj)
	if i1 < 0:
		return
	var bw := i1 - i0 + 1
	var bh := j1 - j0 + 1
	var data := PackedInt32Array()
	data.resize(bw * bh)
	data.fill(0xFFFF)
	for k in tf:
		var o: int = (k / w - j0) * bw + (k % w - i0)
		data[o] = data[o] & 0xFF00          # front: air
	for arr2 in [tb, tb2]:
		for k in arr2:
			var o2: int = (k / w - j0) * bw + (k % w - i0)
			data[o2] = data[o2] & 0x00FF    # background: none
	g.stamps.append({"x0": posmod(c0 + i0, Defs.SH_N[0]), "y0": r0 + j0, "w": bw, "h": bh, "data": data})

## one cell set into the world (raw: only where that layer is empty); -1 leaves a layer alone
func _put(col: int, row: int, f: int, b: int) -> void:
	if row < 0 or row >= Defs.SH_Y0[1]:
		return
	var d := PackedInt32Array([f, b])
	g.stamps.append({"x0": posmod(col, Defs.SH_N[0]), "y0": row, "w": 1, "h": 1, "data": d, "raw": true})

# ------------------------------------------------------------------ moving ---

func update() -> void:
	if list.is_empty():
		return
	_occ.clear()
	for c in list:
		var ax := _axes(c)
		for v in c.pts:
			var w := _to_world(c, ax, v)
			_occ[Vector2i(w.floor())] = c
	for ci in range(list.size() - 1, -1, -1):
		var c: Chunk = list[ci]
		c.age += 1
		var m = g._nearest_mage(c.pos)
		g._use_grid(m)
		_grid = g.gpu.grid
		_gs = g.GS
		_gbase = g.gpu.grid_off + m.slot * _gs * _gs
		if not g.in_grid(c.pos, c.radius + 4.0) or c.age > MAX_AGE:
			_settle(c)
			list.remove_at(ci)
			continue
		if c.ip.is_empty():
			list.remove_at(ci)           # all of it broke off
			continue
		var speed := c.vel.length() + absf(c.omega) * c.radius
		var steps := clampi(int(ceil(speed / 1.2)), 1, 6)
		# a crown crushes against the ground once a frame (it rebuilds the whole piece, so not every step)
		if not c.soft.is_empty() and c.age > 2:
			_crush(c, _axes(c))
		var v0 := c.vel
		var p0 := c.pos
		for s in steps:
			_step(c, 1.0 / float(steps))
		_strike(c, v0, c.pos - p0)
		# at rest: it hasn't gone anywhere for a while (a piece resting on two points jiggles a little
		# in place; that counts as resting too)
		var far_end := absf(wrapf(c.phi - c.rest_phi, -PI, PI)) * c.radius
		if c.pos.distance_to(c.rest_pos) < 1.2 and far_end < 1.2:
			c.rest_t += 1
		else:
			c.rest_pos = c.pos
			c.rest_phi = c.phi
			c.rest_t = 0
		if c.rest_t > SLEEP_FRAMES:
			_settle(c)
			list.remove_at(ci)
	g._use_grid(g.player)

func _gsolid(ix: int, iy: int) -> bool:
	if ix < 0 or iy < 0 or ix >= _gs or iy >= _gs:
		return false
	var k := _gbase + iy * _gs + ix
	return k < _grid.size() and _solid[_grid[k] & 63] == 1

func _solid_at(w: Vector2, c: Chunk) -> bool:
	var l: Vector2 = g.to_grid(w)
	var ix := int(floor(l.x))
	var iy := int(floor(l.y))
	if ix < 0 or iy < 0 or ix >= _gs or iy >= _gs:
		return false
	var k := _gbase + iy * _gs + ix
	if k < _grid.size() and _solid[_grid[k] & 63] == 1:
		return true
	var o = _occ.get(Vector2i(w.floor()), c)
	if o == c:
		return false
	# pieces that broke off together fall together for a moment without shoving each other apart
	return not (o.fam == c.fam and c.age < 30)

## the contact points (world) where a chunk overlaps something
func _contacts(c: Chunk, ax: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in c.pts:
		var w := _to_world(c, ax, v)
		if _solid_at(w, c):
			out.append(w)
	return out

func _step(c: Chunk, dt: float) -> void:
	var up := c.pos.normalized()
	c.vel += -up * GRAV * g.gravity_at(c.pos) * dt
	c.vel = c.vel.limit_length(7.0)
	var p0 := c.pos
	var f0 := c.phi
	c.pos += c.vel * dt
	c.phi += c.omega * dt
	var ax := _axes(c)
	var cs := _contacts(c, ax)
	if cs.is_empty():
		return
	# where and which way it was hit: the average contact, and the way out of what it touches (worked
	# out in the collision grid around each contact, then turned into the world's directions)
	var cp := Vector2.ZERO
	var ng := Vector2.ZERO
	var lsum := Vector2.ZERO
	for w in cs:
		cp += w
		var l: Vector2 = g.to_grid(w)
		lsum += l
		var ix := int(floor(l.x))
		var iy := int(floor(l.y))
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if (dx != 0 or dy != 0) and _gsolid(ix + dx, iy + dy):
					ng -= Vector2(dx, dy)
	cp /= float(cs.size())
	var lc: Vector2 = lsum / float(cs.size())
	var nrm: Vector2 = g.from_grid(lc + ng.normalized()) - g.from_grid(lc) if ng.length() > 0.01 else Vector2.ZERO
	if nrm.length() < 0.01:
		nrm = (c.pos - cp) if (c.pos - cp).length() > 0.01 else up
	nrm = nrm.normalized()
	# out of it: along the normal, a little at a time; still stuck, it goes back to where it was
	var freed := false
	for it in 10:
		c.pos += nrm * 0.3
		ax = _axes(c)
		if _contacts(c, ax).size() <= maxi(0, cs.size() / 6):
			freed = true
			break
	if not freed:
		c.pos = p0
		c.phi = f0
		c.vel *= 0.3
		c.omega *= 0.5
		return
	# the knock: an impulse at the contact (with a little bounce), then friction along the surface
	var r := cp - c.pos
	var vc := c.vel + Vector2(-r.y, r.x) * c.omega
	var vn := vc.dot(nrm)
	if vn >= 0.0:
		return
	var rn := r.x * nrm.y - r.y * nrm.x
	var j := -(1.0 + REST) * vn / (1.0 / c.mass + rn * rn / c.inertia)
	c.vel += nrm * (j / c.mass)
	c.omega += rn * j / c.inertia
	var tg := Vector2(-nrm.y, nrm.x)
	var vt := (c.vel + Vector2(-r.y, r.x) * c.omega).dot(tg)
	var rt := r.x * tg.y - r.y * tg.x
	var jt := clampf(-vt / (1.0 / c.mass + rt * rt / c.inertia), -MU * j, MU * j)
	c.vel += tg * (jt / c.mass)
	c.omega += rt * jt / c.inertia
	if -vn > BREAK_SPEED:
		_splinter(c, cp, -vn)
	elif -vn > 0.8 and c.age > 4:
		g.audio.play("thud", cp, clampf(-vn * 0.25, 0.2, 0.8))

## A tree's crown gives way where it meets the ground: the leaves there are knocked off (they flutter
## down as leaves) instead of the crown sinking into the earth.
func _crush(c: Chunk, ax: Array) -> void:
	var gone := {}
	for q in c.soft.size():
		var w := _to_world(c, ax, c.soft[q])
		var l: Vector2 = g.to_grid(w)
		if _gsolid(int(floor(l.x)), int(floor(l.y))):
			gone[c.soft_k[q]] = true
	if not gone.is_empty():
		_remove(c, gone, ax)

## A hard landing knocks pixels off where it hit: chips and dust (and some rubble for stone and brick);
## a tree sheds leaves as it crashes down.
func _splinter(c: Chunk, cp: Vector2, sp: float) -> void:
	if c.ip.is_empty():
		return
	var ax := _axes(c)
	var lc := _to_local(c, ax, cp)
	var n_off := clampi(int((sp - BREAK_SPEED) * 7.0) + 3, 3, maxi(3, c.px.size() / 6))
	var by_d: Array = []
	for k in c.px.size():
		by_d.append([c.px[k].distance_squared_to(lc), k])
	by_d.sort_custom(func(a, b): return a[0] < b[0])
	var gone := {}
	for e in by_d.slice(0, n_off):
		gone[int(e[1])] = true
	if c.tree:
		# leaves shake loose all over the crown
		for k in c.px.size():
			if (c.bg[k] & 255) == Defs.LEAF and randf() < clampf(sp * 0.025, 0.0, 0.12):
				gone[k] = true
	_remove(c, gone, ax)
	g.audio.play("crack" if c.tree else "thud", cp, clampf(sp * 0.3, 0.3, 1.0))
	g.shake = maxf(g.shake, clampf(sqrt(c.mass) * sp * 0.04, 0.0, 5.0))

## takes pixels off a chunk: each flies off as a chip, and some stone and brick lands as rubble
func _remove(c: Chunk, gone: Dictionary, ax: Array) -> void:
	if gone.is_empty():
		return
	for k in gone:
		var w := _to_world(c, ax, c.px[k])
		var col: Color = c.cf[k] if c.fg[k] != 0 else c.cb[k]
		var out := (w - c.pos).normalized()
		if c.fg[k] == 0 and (c.bg[k] & 255) == Defs.LEAF:
			# a leaf: drifts down slowly
			g._particle(w, out * randf_range(0.1, 0.4) + w.normalized() * randf_range(0.1, 0.5), 40 + randi() % 50, col, false, 0.012)
			continue
		g._particle(w, out * randf_range(0.3, 1.0) + c.vel * 0.3 + w.normalized() * randf_range(0.2, 0.8), 25 + randi() % 30, col, false, 0.06)
		var t: int = c.fg[k] & 255
		if t != 0 and randf() < 0.35:
			var deb: int = Defs.DEBRIS[t]
			if deb != 0 and deb != t:
				var cc: Vector2i = Build.cell_of(w)
				_put(cc.x, cc.y, deb | (c.fg[k] & 0xff00), -1)
	var keep_ip := PackedVector2Array()
	var keep_fg := PackedInt32Array()
	var keep_bg := PackedInt32Array()
	var keep_cf := PackedColorArray()
	var keep_cb := PackedColorArray()
	for k in c.ip.size():
		if gone.has(k):
			continue
		keep_ip.append(c.ip[k])
		keep_fg.append(c.fg[k])
		keep_bg.append(c.bg[k])
		keep_cf.append(c.cf[k])
		keep_cb.append(c.cb[k])
	c.ip = keep_ip
	c.fg = keep_fg
	c.bg = keep_bg
	c.cf = keep_cf
	c.cb = keep_cb
	c.key.clear()
	if c.ip.is_empty():
		c.mass = 0.0
		c.px = PackedVector2Array()
		c.pts = PackedVector2Array()
		c.dirty = true
		return
	var sum := Vector2.ZERO
	for k in c.ip.size():
		c.key[Vector2i(c.ip[k])] = k
		sum += c.ip[k]
	# the centre of mass moves: keep the pixels where they are in the world
	var nc := sum / float(c.ip.size())
	c.pos = _to_world(c, ax, nc - c.com)
	c.com = nc
	_rebuild(c)

## a falling chunk that hits a mage or a foe hurts it (heavier and faster hurts more), once
## (`v0`: its velocity coming into this frame, before landing slowed it; `moved`: how far it went)
func _strike(c: Chunk, v0: Vector2, moved: Vector2) -> void:
	# like falling rock (grid.comp): only a piece that has really fallen (ROCK_HURT_FALL cells' worth of
	# speed) and comes down on your upper half hurts, so clods dropping into a pit you dig don't
	var sp := v0.length()
	if sp < sqrt(2.0 * GRAV * ROCK_HURT_FALL) or c.mass <= 0.0:
		return
	var ax := _axes(c)
	var bodies: Array = []
	for m in g.players:
		if not m.dead:
			bodies.append(m)
	bodies.append_array(g.enemies)
	for b in bodies:
		if c.hit.has(b) or b.pos.distance_to(c.pos) > c.radius + maxf(b.w, b.h) + moved.length():
			continue
		var touched := false
		var ba := atan2(b.pos.y, b.pos.x)
		var br: Vector2 = g.basis_r(ba)
		var bd: Vector2 = g.basis_d(ba)
		for back in [0.0, 0.34, 0.67, 1.0]:
			var shift: Vector2 = moved * back        # (and where it was on its way through this frame)
			var oy: float = -b.h * 0.5 + 1.0
			while oy <= 0.0 and not touched:
				var ox: float = -b.w * 0.5 + 1.0
				while ox <= b.w * 0.5 - 1.0:
					var wp: Vector2 = b.pos + br * ox + bd * oy - shift
					if c.key.has(Vector2i((_to_local(c, ax, wp) + c.com).round())):
						touched = true
						break
					ox += 2.0
				oy += 2.0
			if touched:
				break
		if not touched:
			continue
		c.hit[b] = true
		var dmg := clampf(sqrt(c.mass) * sp * 0.55, 3.0, 45.0)
		var kx := signf(v0.dot(br)) * 2.0
		if b in g.players:
			g.hurt(b, dmg, Vector2(kx, -1.5), true)
		else:
			g._hurt_enemy(b, dmg * 1.5, kx, -1.5)

# --------------------------------------------------------------- settling ---

## Set a chunk back into the world where it lies: each cell in its footprint takes the pixel at its
## centre. Blocks go in unanchored (so they obey the physics again); a felled tree goes in front, its
## wood as logs and some of its leaves as litter.
func _settle(c: Chunk) -> void:
	if c.ip.is_empty():
		return
	var ax := _axes(c)
	var cmin := Vector2i(1 << 30, 1 << 30)
	var cmax := Vector2i(-(1 << 30), -(1 << 30))
	var ref: Vector2i = Build.cell_of(c.pos)
	for v in c.px:
		var w := _to_world(c, ax, v)
		var cc: Vector2i = Build.cell_of(w)
		var dc := wrapi(cc.x - ref.x, -Defs.SH_N[0] / 2, Defs.SH_N[0] / 2)
		cmin = Vector2i(mini(cmin.x, dc), mini(cmin.y, cc.y))
		cmax = Vector2i(maxi(cmax.x, dc), maxi(cmax.y, cc.y))
	cmin -= Vector2i(1, 1)
	cmax += Vector2i(1, 1)
	cmin.y = maxi(cmin.y, 0)
	cmax.y = mini(cmax.y, Defs.SH_Y0[1] - 1)
	var w2 := cmax.x - cmin.x + 1
	var h2 := cmax.y - cmin.y + 1
	if w2 <= 0 or h2 <= 0:
		return
	# a felled tree's crown stays a plant of its own in the background, in the bushes' range of ids
	# (0xF000..): plants.comp holds it up by any part of it resting on something
	var pid := (0xF000 | (randi() & 0x0FFF)) << 16
	var data := PackedInt32Array()
	data.resize(w2 * h2 * 2)
	data.fill(-1)
	var any := false
	for j in h2:
		for i in w2:
			var col := ref.x + cmin.x + i
			var row := cmin.y + j
			var lp := (_to_local(c, ax, cell_pos(col, row)) + c.com).round()
			var k = c.key.get(Vector2i(lp), -1)
			if k < 0:
				continue
			var o := 2 * (j * w2 + i)
			var f: int = c.fg[k]
			var b: int = c.bg[k]
			if c.tree:
				# a felled tree: its wood lands in front as logs (solid: you walk on them and chop
				# them; anchored where they lie, so a log over a dip doesn't creak and break up),
				# its crown stays in the background as a fallen plant
				var bm: int = b & 255
				if bm == Defs.LEAF or bm == Defs.SNOW:
					data[o + 1] = bm | pid
				elif bm != 0 and Defs.KIND[bm] == Defs.K_SOLID:
					data[o] = bm | (posmod(hash(col * 13 + row), 4) << 8) | ST_ANCHOR
				any = true
				continue
			if f != 0:
				data[o] = (f & 0xFFFF) | (f & ST_BUILT)      # unanchored; built only if it was built
			if b != 0:
				data[o + 1] = b & ~(0x3F00 | BG_ANCHOR)
			any = true
	if c.tree:
		_prune_crown(data, w2, h2, ax, c, ref, cmin)
	if any:
		g.stamps.append({"x0": posmod(ref.x + cmin.x, Defs.SH_N[0]), "y0": cmin.y, "w": w2, "h": h2, "data": data, "raw": true})

## A felled crown keeps only the leaves joined (through each other) to its logs: plants.comp holds a
## fallen crown up by what it rests on, and a scrap cut off from the rest would only come loose again.
## The scraps flutter away as leaves.
func _prune_crown(data: PackedInt32Array, w2: int, h2: int, ax: Array, c: Chunk, ref: Vector2i, cmin: Vector2i) -> void:
	var keep := {}
	var q: Array = []
	for j in h2:
		for i in w2:
			var o := 2 * (j * w2 + i)
			if data[o + 1] == -1:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				if ni >= 0 and nj >= 0 and ni < w2 and nj < h2 and data[2 * (nj * w2 + ni)] != -1:
					keep[j * w2 + i] = true
					q.append(j * w2 + i)
					break
	while not q.is_empty():
		var k: int = q.pop_back()
		var ki: int = k % w2
		var kj: int = k / w2
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				var ni2: int = ki + di
				var nj2: int = kj + dj
				if ni2 < 0 or nj2 < 0 or ni2 >= w2 or nj2 >= h2:
					continue
				var k2 := nj2 * w2 + ni2
				if not keep.has(k2) and data[2 * k2 + 1] != -1:
					keep[k2] = true
					q.append(k2)
	for k in w2 * h2:
		if data[2 * k + 1] != -1 and not keep.has(k):
			data[2 * k + 1] = -1
			if randf() < 0.3:
				var lp := cell_pos(ref.x + cmin.x + k % w2, cmin.y + k / w2)
				g._particle(lp, Vector2(randf() - 0.5, randf() - 0.7) * 0.3, 40 + randi() % 40, Color(0.25, 0.45, 0.18), false, 0.012)

## everything still moving goes into the world now (before saving, or leaving the planet)
func settle_all() -> void:
	for c in list:
		_settle(c)
	list.clear()

static func _dust_col(c: Color) -> Color:
	return c.lerp(Color(0.62, 0.57, 0.5), 0.4)

func _dust(p: Vector2, col: Color) -> void:
	for k in 2:
		g._particle(p + Vector2(randf() - 0.5, randf() - 0.5) * 2.0, Vector2(randf() - 0.5, randf() - 0.5) * 0.5, 30 + randi() % 30, _dust_col(col), false, 0.03)
