extends Node2D
## Wisp Forge (Godot) — main game: frame loop, player, enemies, spells,
## crafting, weather, saving and planet travel. The world itself lives on the
## GPU (gpu_world.gd); this script reads back a collision grid around the
## player every frame and sends "brushes" (dig / explode / place) to the GPU.

const GpuWorld := preload("res://scripts/gpu_world.gd")
const UI := preload("res://scripts/ui.gd")
const Overlay := preload("res://scripts/overlay.gd")
const Buildings := preload("res://scripts/buildings.gd")
const Tests := preload("res://scripts/tests.gd")

const DAY_LEN := 60.0 * 7.0 * 60.0   # frames per day (7 minutes)
const REACH := 42.0
var GS := 384
var HALF := 192.0

class Body:
	var pos := Vector2.ZERO   # world-space centre
	var vx := 0.0             # velocity in the local frame (x along the surface, y toward the core)
	var vy := 0.0
	var w := 5.0
	var h := 12.0
	var step_h := 3
	var on_ground := false
	var in_liquid := false
	var hit_wall := false
	var facing := 1

class Enemy extends Body:
	var type := ""
	var d: Dictionary
	var hp := 10.0
	var max_hp := 10.0
	var t := 0.0
	var shoot_t := 120.0
	var flash := 0
	var awake := true
	var slow := 0
	var phase := 0.0
	var dead := false
	var leaping := false
	var boss := false
	var guard_id := -1     # which structure guard this is (-1 = a wandering foe)

var gpu
var ui
var overlay
var view_tex: ImageTexture
var view_rect: TextureRect
var pix: Node2D

var state := "title"      # title, loading, play, forge, dead, error
var planet: Dictionary = {}
var frame := 0
var time := 0.0
var spawn_angle := 0.0
var builds = null          # the planet's planned structures (ruins, castles, towns...)
var testing := false       # started by "Run tests.bat" (--test): uses saves/test, reports, quits
var test_god := false      # the test mode keeps the mage alive except when it checks damage
var perf_us := 0           # time spent in the GPU step (for the test report)
var perf_n := 0
var _tests = null
var boss_info := Vector4.ZERO
var scale_px := 4
var VW := 480
var VH := 270

# camera
var cam_c := Vector2(0, 1400)
var cam_a := PI / 2
var zoom := 1.0
var zoom_levels := [1.0, 2.0, 4.0, 8.0, 14.0]
var zoom_i := 0
var shake := 0.0

# collision grid frame (from the last GPU step)
var grid_g := Vector2.ZERO
var grid_a := 0.0
var _gslot := 0            # whose collision grid the physics helpers are reading

# players: every mage in the world. players[0] is the one played on this computer; co-op adds more.
class PlayerInput:
	var move := 0              # -1 left, 1 right
	var jump := false          # held
	var cast := false          # casting the selected spell
	var dig := false           # excavating (held, or a quick tap)
	var aim := Vector2.ZERO    # world position of the cursor

class Mage extends Body:
	var id := 0
	var slot := 0              # which simulation counters and collision grid are this mage's
	var local := true          # played on this computer (others come from the network)
	var input := PlayerInput.new()
	var grid_g := Vector2.ZERO # where this mage's collision grid was centred
	var grid_a := 0.0
	var hp := 100.0
	var max_hp := 100.0
	var mana := 100.0
	var max_mana := 100.0
	var mana_regen := 0.22
	var breath := 600.0
	var max_breath := 600.0
	var inv := PackedInt32Array()
	var items := {}
	var known := ["spark", "conjure"]
	var tier := 1
	var dig_r := 4.5
	var heat_ward := false
	var iframes := 0
	var air_time := 0
	var dead := false
	var sel := 0
	var mat := 2               # Defs.DIRT
	var cast_cd := 0
	var dig_blocked := 0
	var pending_place := 0
	var dig_tap := 0           # a quick right-click still digs for a few frames
	var jump_held := false
	var ground_t := 99         # frames since standing on something
	var jump_buf := 0          # frames a jump press is remembered
	func _init() -> void:
		h = 10.0
		w = 5.0

var player := Mage.new()
var players: Array = [player]

# the local mage's state, by its old names (so the rest of the game reads naturally)
var hp: float:
	get: return player.hp
	set(v): player.hp = v
var max_hp: float:
	get: return player.max_hp
	set(v): player.max_hp = v
var mana: float:
	get: return player.mana
	set(v): player.mana = v
var max_mana: float:
	get: return player.max_mana
	set(v): player.max_mana = v
var mana_regen: float:
	get: return player.mana_regen
	set(v): player.mana_regen = v
var breath: float:
	get: return player.breath
	set(v): player.breath = v
var max_breath: float:
	get: return player.max_breath
	set(v): player.max_breath = v
var items: Dictionary:
	get: return player.items
	set(v): player.items = v
var known: Array:
	get: return player.known
	set(v): player.known = v
var tier: int:
	get: return player.tier
	set(v): player.tier = v
var dig_r: float:
	get: return player.dig_r
	set(v): player.dig_r = v
var heat_ward: bool:
	get: return player.heat_ward
	set(v): player.heat_ward = v
var iframes: int:
	get: return player.iframes
	set(v): player.iframes = v
var dead: bool:
	get: return player.dead
	set(v): player.dead = v
var sel: int:
	get: return player.sel
	set(v): player.sel = v
var mat: int:
	get: return player.mat
	set(v): player.mat = v
var dig_tap: int:
	get: return player.dig_tap
	set(v): player.dig_tap = v
var jump_buf: int:
	get: return player.jump_buf
	set(v): player.jump_buf = v
var hurt_flash := 0.0
var dig_blocked: int:
	get: return player.dig_blocked
	set(v): player.dig_blocked = v

var enemies: Array = []
var projs: Array = []
var parts: Array = []
var brushes: Array = []
var lights: Array = []
var pending_place: int:
	get: return player.pending_place
	set(v): player.pending_place = v
var wisp := Vector2.ZERO
var wisp_t := 0.0
var spawn_timer := 0

# weather
var rain := 0.0
var rain_target := 0.0
var weather_timer := 1800
var flash := 0.0

func _ready() -> void:
	player.inv.resize(Defs.NM)
	get_tree().set_auto_accept_quit(false)   # we save first, then quit (see quit_game)
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	pix = Node2D.new()
	add_child(pix)
	view_rect = TextureRect.new()
	view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pix.add_child(view_rect)
	overlay = Overlay.new()
	overlay.game = self
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pix.add_child(overlay)
	ui = UI.new()
	ui.game = self
	add_child(ui)
	gpu = GpuWorld.new()
	_layout()
	get_viewport().size_changed.connect(_layout)
	if not gpu.init():
		state = "error"
		ui.show_error(gpu.error_text)
		return
	gpu.resize(VW, VH)
	GS = gpu.GS
	HALF = GS / 2.0
	if "--test" in OS.get_cmdline_user_args():
		testing = true
		_tests = Tests.new()   # kept as a member: a local would be freed before the tests run
		_tests.g = self
		_tests.run.call_deferred()
		return
	ui.show_title(_load_save() != null)

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	scale_px = maxi(2, int(round(s.y / 250.0)))
	VW = int(ceil(s.x / scale_px))
	VH = int(ceil(s.y / scale_px))
	pix.scale = Vector2(scale_px, scale_px)
	if gpu and gpu.rd:
		gpu.resize(VW, VH)
		GS = gpu.GS
		HALF = GS / 2.0

func _exit_tree() -> void:
	if gpu:
		gpu.cleanup()

# ================================================================= frames ==
func _process(_delta: float) -> void:
	if state == "play" or state == "dead":
		_tick()
	if state == "play" or state == "dead" or state == "forge":
		_gpu_frame(state == "forge")
		ui.update_hud(self)
	ui.update_toasts()

func _gpu_frame(paused: bool) -> void:
	_write_frame_params()
	# simulate around every mage (the local one around the camera) and build each one's grid
	var centers := [cam_c]
	var frames := []
	for k in mini(players.size(), gpu.MAXP):
		var m: Mage = players[k]
		m.slot = k
		if m != player:
			centers.append(m.pos)
		frames.append([m.pos, atan2(m.pos.y, m.pos.x)])
	var t0 := Time.get_ticks_usec()
	gpu.step(centers, frames, brushes.size() > 0 and not paused, false)
	perf_us += Time.get_ticks_usec() - t0
	perf_n += 1
	brushes.clear()
	for k in frames.size():
		players[k].grid_g = frames[k][0]
		players[k].grid_a = frames[k][1]
	for m in players:
		_apply_counts(m)
	_use_grid(player)
	_flush_loot()
	if view_tex == null or view_tex.get_width() != gpu.VW or view_tex.get_height() != gpu.VH:
		view_tex = ImageTexture.create_from_image(gpu.view_img)
		view_rect.texture = view_tex
		view_rect.size = Vector2(gpu.VW, gpu.VH)
	else:
		view_tex.update(gpu.view_img)
	overlay.queue_redraw()

func _write_frame_params() -> void:
	var sun_a := spawn_angle - 1.1 + time / DAY_LEN * TAU
	gpu.setp(0, Vector4(time, gpu.frame, sun_a, planet.get("seed", 1)))
	var sh := Vector2(randf() - 0.5, randf() - 0.5) * shake
	var c := cam_c + sh
	gpu.setp(1, Vector4(c.x, c.y, atan2(c.y, c.x), zoom))
	gpu.setp(2, Vector4(VW, VH, gpu.LS, mini(lights.size(), 32)))
	var b := _biome_at(atan2(player.pos.y, player.pos.x))
	var wmat := Defs.WATER
	if b["weather"] == "snow":
		wmat = Defs.SNOW
	elif b["weather"] == "ash":
		wmat = Defs.ASH
	var rr := rain if b["weather"] != "clear" else 0.0
	gpu.setp(3, Vector4(rr * 0.0015 if rr > 0.05 else 0.0, wmat, rr, flash))
	gpu.setp(5, Vector4(player.pos.x, player.pos.y, atan2(player.pos.y, player.pos.x), GS))
	gpu.setp(6, Vector4(brushes.size(), hurt_flash, player.pos.x, player.pos.y))
	var cr := c.length()
	gpu.setp(121, Vector4(spawn_angle, time * 0.00004, minf(Defs.R_TOP - 2.0, cr + VH * 0.55 * zoom), 0))
	for k in mini(lights.size(), 32):
		var L: Array = lights[k]
		var sp := world_to_screen(L[0])
		gpu.setp(24 + 2 * k, Vector4(sp.x, sp.y, L[1], 0))
		var col: Color = L[2]
		gpu.setp(25 + 2 * k, Vector4(col.r, col.g, col.b, 0))
	lights.clear()
	for k in mini(brushes.size(), 16):
		var B: Array = brushes[k]
		var bp: Vector2 = B[0]
		var owner: int = int(B[7]) if B.size() > 7 else 0
		gpu.setp(88 + 2 * k, Vector4(bp.x, bp.y, B[1], int(B[2]) + 16 * owner))
		gpu.setp(89 + 2 * k, Vector4(B[3], B[4], B[5], B[6]))
	if brushes.size() > 16:
		brushes.resize(16)

func _apply_counts(m: Mage) -> void:
	var all: PackedInt32Array = gpu.counts
	var o := m.slot * 64
	if all.size() < o + 64:
		return
	var cn := all.slice(o, o + 64)
	var total := 0
	for t in Defs.NM:
		if cn[t] > 0:
			m.inv[t] += cn[t]
			total += cn[t]
			if randf() < 0.6 and m.local:
				_spawn_suck_particles(t, mini(cn[t], 3))
	if cn[Defs.TREASURE] > 0 and m.local:
		_open_treasure(cn[Defs.TREASURE])
		m.inv[Defs.TREASURE] = 0
	if cn.size() > 54 and cn[54] > 0 and _chest_pending:
		_chest_pending = false
		_open_chest_loot()
	if cn.size() > 53 and cn[52] > 0 and not m.dead:
		# a falling block lands on you: the longer it fell, the harder it hits
		var dmg := clampf(2.0 + float(cn[53]) * 0.45 + float(cn[52]) * 0.12, 2.0, 35.0)
		var was := m.iframes
		hurt(m, dmg, Vector2(0, 1.2), true)
		if was == 0 and m.iframes > 0 and m.local:
			ui.toast("Falling rock! -%d" % int(dmg), Color(1, 0.6, 0.45), 1.5)
			shake = maxf(shake, 4.0)
	if cn[50] > 0:
		m.dig_blocked = 30
	if m.pending_place > 0:
		m.inv[m.mat] = maxi(0, m.inv[m.mat] - mini(cn[51], m.pending_place))
		m.pending_place = 0

## Treasure. Opening a chest (F) gives its full loot and may hold a rare find; digging a chest
## out smashes it and some of the loot is lost. In ruins, some chests are mimics.
var _loot_acc := {}
var _loot_t := 0
var _chest_pending := false
var _chest_rare := 0.15
var _hint_t := 0
var _smash_warned := false

func _loot_table() -> Array:
	var deep: float = clampf((gpu.surf_at(atan2(player.pos.y, player.pos.x)).x - player.pos.length()) / 300.0, 0.0, 1.0)
	return [[Defs.COPPER, 6.0, 4], [Defs.COAL, 5.0, 4], [Defs.CRYSTAL, 3.0, 3], [Defs.FROST, 2.0 + deep * 2.0, 3],
		[Defs.EMBER, 1.0 + deep * 3.0, 3], [Defs.WISP, 1.0 + deep * 3.0, 2], [Defs.OBSIDIAN, 0.5 + deep * 2.0, 2],
		[Defs.GLASS, 2.0, 4], [Defs.TORCH, 2.0, 3], [Defs.MASONRY, 1.5, 6]]

func _roll_loot(rolls: int, mult: float) -> void:
	var table := _loot_table()
	var rich: float = float(planet.get("rich", 1.0))
	var tot := 0.0
	for e in table:
		tot += float(e[1])
	for k in rolls:
		var r := randf() * tot
		for e in table:
			r -= float(e[1])
			if r <= 0.0:
				var amt := maxi(1, int(ceil(randi_range(1, int(e[2])) * rich * mult)))
				player.inv[int(e[0])] += amt
				_loot_acc[int(e[0])] = int(_loot_acc.get(int(e[0]), 0)) + amt
				break
	_loot_t = 30

## digging a chest out: each cell rolls, at half value
func _open_treasure(n: int) -> void:
	_roll_loot(n, 0.5)
	if not _smash_warned:
		_smash_warned = true
		ui.toast("Digging out a chest smashes it. Stand next to one and press F to open it properly.", Color(1, 0.85, 0.5), 5.0)
	_spawn_suck_particles(Defs.TREASURE, 6)

func _flush_loot() -> void:
	if _loot_t <= 0 or _loot_acc.is_empty():
		return
	_loot_t -= 1
	if _loot_t > 0:
		return
	var parts_txt := []
	for m in _loot_acc:
		parts_txt.append("+%d %s" % [_loot_acc[m], Defs.NAMES[m]])
	ui.toast("Treasure! " + ", ".join(parts_txt), Color(1.0, 0.85, 0.3), 5.0)
	_loot_acc.clear()

## the treasure cells nearest the mage (in the collision grid), as one connected chest
func _find_chest(radius: int) -> Array:
	var pl := to_grid(player.pos)
	var cx := int(pl.x)
	var cy := int(pl.y)
	var best := Vector2i(-1, -1)
	var bd := 1e9
	for j in range(cy - radius, cy + radius + 1):
		for i in range(cx - radius, cx + radius + 1):
			if gtype(i, j) == Defs.TREASURE:
				var d := Vector2(i - pl.x, j - pl.y).length_squared()
				if d < bd:
					bd = d
					best = Vector2i(i, j)
	if best.x < 0:
		return []
	var cells := [best]
	var seen := {best: true}
	var k := 0
	while k < cells.size() and cells.size() < 40:
		var c: Vector2i = cells[k]
		k += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + o
			if not seen.has(q) and gtype(q.x, q.y) == Defs.TREASURE:
				seen[q] = true
				cells.append(q)
	return cells

func _try_open_chest() -> void:
	var cells := _find_chest(12)
	if cells.is_empty():
		return
	var sum := Vector2.ZERO
	for c in cells:
		sum += Vector2(c.x + 0.5, c.y + 0.5)
	var centre: Vector2 = from_grid(sum / cells.size())
	var place := region_name()
	var ruin := place.begins_with("Ruin") or place.begins_with("Forgotten") or place.begins_with("Buried") \
		or place.begins_with("Collapsed") or place.begins_with("Sunken")
	if ruin and randf() < 0.15:
		# not a chest at all
		brushes.append([centre, 4.8, 7, 0, 0, 0, 0])
		var m: Enemy = spawn_enemy("mimic", centre)
		m.vy = -2.5
		m.t = 20
		shake = maxf(shake, 6.0)
		ui.toast("The chest bares its teeth: a MIMIC!", Color(1, 0.4, 0.35), 4.0)
		return
	_chest_rare = 0.15
	if "Castle" in place or "Vault" in place:
		_chest_rare = 0.55
	elif "Temple" in place or "Catacombs" in place:
		_chest_rare = 0.4
	elif "Watchtower" in place or "Mine" in place:
		_chest_rare = 0.25
	brushes.append([centre, 4.8, 7, 1, 0, 0, 0])
	_chest_pending = true
	for k in 14:
		_particle(centre, Vector2(randf() - 0.5, -randf() * 1.2), 30 + randi() % 20, Color(1, 0.85, 0.35), true, 0.02)
	lights.append([centre, 30.0, Color(1.2, 0.9, 0.4)])

func _open_chest_loot() -> void:
	_roll_loot(7, 1.6)
	_rare_find(_chest_rare)

## scrolls that unlock spells at the Forge, and relics that make you stronger: only found in chests
func _rare_find(p: float) -> void:
	if randf() > p:
		return
	var pool := []
	for id in ["scroll_blink", "scroll_starfall", "ring", "circlet", "boots"]:
		if not items.has(id):
			pool.append(id)
	if pool.is_empty():
		_roll_loot(5, 2.0)
		return
	var id: String = pool[randi() % pool.size()]
	items[id] = true
	match id:
		"scroll_blink":
			ui.toast("RARE FIND: Scroll of Blink! Forge it at the Wisp Forge (Spells).", Color(0.55, 0.95, 1.0), 7.0)
		"scroll_starfall":
			ui.toast("RARE FIND: Scroll of Starfall! Forge it at the Wisp Forge (Spells).", Color(1.0, 0.82, 0.45), 7.0)
		"ring":
			max_hp += 25
			hp += 25
			ui.toast("RARE FIND: Warden's Ring. +25 max health.", Color(1.0, 0.5, 0.5), 7.0)
		"circlet":
			max_mana += 40
			mana += 40
			ui.toast("RARE FIND: Sage's Circlet. +40 max mana.", Color(0.6, 0.7, 1.0), 7.0)
		"boots":
			ui.toast("RARE FIND: Featherstep Boots. You jump higher.", Color(0.7, 1.0, 0.7), 7.0)
	shake = maxf(shake, 3.0)
	save_game()

func _check_chest_hint() -> void:
	_hint_t -= 1
	if _hint_t > 0 or frame % 20 != 0:
		return
	if not _find_chest(9).is_empty():
		ui.toast("Press F to open the chest", Color(1.0, 0.9, 0.55), 2.5)
		_hint_t = 900

# ------------------------------------------------------------- guardians ---
## Foes placed by the structure generator wait inside castles, catacombs, temples and mines.
## They appear when you come near, and stay dead once killed.
var _guards_alive := {}
func _update_guards() -> void:
	if builds == null or frame % 30 != 0 or dead:
		return
	var slain: Array = planet_state.get("slain", [])
	for gi in builds.guards.size():
		if _guards_alive.has(gi) or slain.has(gi):
			continue
		var gd: Dictionary = builds.guards[gi]
		var gp: Vector2 = gd["pos"]
		var near := _nearest_mage(gp)
		_use_grid(near)
		if gp.distance_to(near.pos) > 190.0 or not in_grid(gp, 24.0):
			_use_grid(player)
			continue
		_use_grid(player)
		var e: Enemy = spawn_enemy(gd["type"], gp)
		e.guard_id = gi
		_guards_alive[gi] = true

# ============================================================ coordinates ==
func basis_r(a: float) -> Vector2:
	return Vector2(sin(a), -cos(a))

func basis_d(a: float) -> Vector2:
	return Vector2(-cos(a), -sin(a))

func world_to_screen(p: Vector2) -> Vector2:
	var o := p - cam_c
	var a := atan2(cam_c.y, cam_c.x)
	return Vector2(o.dot(basis_r(a)), o.dot(basis_d(a))) / zoom + Vector2(VW, VH) * 0.5

func screen_to_world(px: Vector2) -> Vector2:
	var a := atan2(cam_c.y, cam_c.x)
	var o := (px - Vector2(VW, VH) * 0.5) * zoom
	return cam_c + basis_r(a) * o.x + basis_d(a) * o.y

func to_grid(p: Vector2) -> Vector2:
	var o := p - grid_g
	return Vector2(o.dot(basis_r(grid_a)), o.dot(basis_d(grid_a))) + Vector2(HALF, HALF)

func from_grid(l: Vector2) -> Vector2:
	return grid_g + basis_r(grid_a) * (l.x - HALF) + basis_d(grid_a) * (l.y - HALF)

func in_grid(p: Vector2, margin: float) -> bool:
	var l := to_grid(p)
	return l.x > margin and l.y > margin and l.x < GS - margin and l.y < GS - margin

func gtype(ix: int, iy: int) -> int:
	return gpu.grid_type(_gslot, ix, iy)

## point the physics helpers (to_grid, gtype, box_solid...) at a mage's collision grid
func _use_grid(m: Mage) -> void:
	grid_g = m.grid_g
	grid_a = m.grid_a
	_gslot = m.slot

## another mage joins this world (a co-op player; for now only the test mode uses it)
func add_mage() -> Mage:
	var m := Mage.new()
	m.local = false
	m.id = players.size()
	m.inv.resize(Defs.NM)
	players.append(m)
	return m

## the living mage nearest to a point (enemies chase it, its grid is used for physics there)
func _nearest_mage(p: Vector2) -> Mage:
	var best: Mage = player
	var bd := 1e18
	for m in players:
		if m.dead:
			continue
		var d := (m.pos as Vector2).distance_squared_to(p)
		if d < bd:
			bd = d
			best = m
	return best

func gsolid(ix: int, iy: int) -> bool:
	var k: int = Defs.KIND[gtype(ix, iy)]
	return k == Defs.K_SOLID or k == Defs.K_POWDER

func type_at(p: Vector2) -> int:
	var l := to_grid(p)
	return gtype(int(floor(l.x)), int(floor(l.y)))

func box_solid(x: float, y: float, w: float, h: float) -> bool:
	var x0 := int(floor(x))
	var x1 := int(floor(x + w - 0.001))
	var y0 := int(floor(y))
	var y1 := int(floor(y + h - 0.001))
	for yy in range(y0, y1 + 1):
		for xx in range(x0, x1 + 1):
			if gsolid(xx, yy):
				return true
	return false

func box_count(x: float, y: float, w: float, h: float, m: int) -> int:
	var n := 0
	for yy in range(int(floor(y)), int(floor(y + h - 0.001)) + 1):
		for xx in range(int(floor(x)), int(floor(x + w - 0.001)) + 1):
			if gtype(xx, yy) == m:
				n += 1
	return n

func move_body(e: Body) -> void:
	var l := to_grid(e.pos)
	var x := l.x - e.w * 0.5
	var y := l.y - e.h * 0.5
	e.hit_wall = false
	var walker := e.step_h > 0
	# horizontal: climb small steps (bigger on the ground, a little in the air)
	var dx := e.vx
	while absf(dx) > 0.000001:
		var st := 0.5 * signf(dx) if absf(dx) > 0.5 else dx
		if not box_solid(x + st, y, e.w, e.h):
			x += st
		else:
			var climbed := false
			if walker:
				var max_up := e.step_h if (e.on_ground or e.in_liquid) else 2
				for up in range(1, max_up + 1):
					if not box_solid(x + st, y - up, e.w, e.h):
						x += st
						y -= up
						climbed = true
						break
			if not climbed:
				e.vx = 0.0
				e.hit_wall = true
				break
		dx -= st
	e.on_ground = false
	# vertical: when the head clips a corner, slide around it instead of stopping
	var dy := e.vy
	while absf(dy) > 0.000001:
		var st2 := 0.5 * signf(dy) if absf(dy) > 0.5 else dy
		if not box_solid(x, y + st2, e.w, e.h):
			y += st2
		else:
			var nudged := false
			if walker and st2 < 0:
				for o in [1.0, -1.0, 2.0, -2.0]:
					if not box_solid(x + o, y + st2, e.w, e.h) and not box_solid(x + o, y, e.w, e.h):
						x += o
						y += st2
						nudged = true
						break
			if not nudged:
				if st2 > 0:
					e.on_ground = true
				e.vy = 0.0
				break
		dy -= st2
	if not e.on_ground and e.vy >= 0 and box_solid(x, y + 0.6, e.w, e.h):
		e.on_ground = true
	# pushed into terrain (sand piled on, something placed): find the nearest free spot
	if box_solid(x, y, e.w, e.h):
		var freed := false
		for off in [Vector2(0, -1), Vector2(0, -2), Vector2(1, 0), Vector2(-1, 0), Vector2(0, -3), Vector2(2, 0), Vector2(-2, 0),
				Vector2(1, -1), Vector2(-1, -1), Vector2(0, -4), Vector2(3, 0), Vector2(-3, 0), Vector2(0, -5), Vector2(0, -6), Vector2(0, 1)]:
			if not box_solid(x + off.x, y + off.y, e.w, e.h):
				x += off.x
				y += off.y
				freed = true
				if off.y < 0:
					e.on_ground = true
					e.vy = minf(e.vy, 0.0)
				break
		if not freed:
			y -= 1.0
	e.pos = from_grid(Vector2(x + e.w * 0.5, y + e.h * 0.5))
	var r := e.pos.length()
	if r > Defs.R_TOP - 8.0:
		e.pos = e.pos.normalized() * (Defs.R_TOP - 8.0)
		e.vy = maxf(e.vy, 0.0)

func gravity_at(p: Vector2) -> float:
	var r := p.length()
	var rs: float = gpu.surf_at(atan2(p.y, p.x)).x
	if r < rs + 150.0:
		return 1.0
	return maxf(0.06, 1.0 - (r - rs - 150.0) / 380.0)

func _biome_at(a: float) -> Dictionary:
	var bi := int(gpu.surf_at(a).y)
	var names: Array = planet.get("biomes", ["forest"])
	return Defs.BIOMES[names[clampi(bi, 0, names.size() - 1)]]

# ================================================================== tick ===
## this computer's keyboard and mouse become the local mage's intentions for this frame
## (a remote mage's come from the network instead)
func _read_local_input(m: Mage) -> void:
	var inp := m.input
	inp.aim = screen_to_world(get_viewport().get_mouse_position() / scale_px)
	inp.move = 0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		inp.move -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		inp.move += 1
	inp.jump = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	var can_act: bool = not ui.mouse_over_ui() and state == "play"
	inp.cast = can_act and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	inp.dig = can_act and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or m.dig_tap > 0)

func _tick() -> void:
	frame += 1
	time += 1.0
	_read_local_input(player)
	var aim: Vector2 = player.input.aim
	for m in players:
		if m.cast_cd > 0:
			m.cast_cd -= 1
		if m.dig_blocked > 0:
			m.dig_blocked -= 1
		_use_grid(m)
		_update_player(m)
		m.sel = clampi(m.sel, 0, m.known.size() - 1)
		if not m.dead and state == "play":
			if m.input.cast:
				_cast(m, m.known[m.sel], m.input.aim)
			if m.input.dig:
				_excavate(m, m.input.aim)
		if m.dig_tap > 0:
			m.dig_tap -= 1
	_use_grid(player)
	_update_enemies()
	_use_grid(player)
	_update_projectiles()
	_use_grid(player)
	_update_particles()
	_update_weather()
	_try_spawn()
	_update_guards()
	_check_chest_hint()
	_update_wisp()
	_update_camera(aim)
	shake *= 0.88
	hurt_flash *= 0.9
	if frame % 3600 == 0:
		save_game()
	if frame % 7200 == 0:
		save_world(false)

func _update_camera(aim: Vector2) -> void:
	var a := atan2(player.pos.y, player.pos.x)
	var up := player.pos.normalized()
	var look := (aim - player.pos) * 0.12 if zoom_i == 0 else Vector2.ZERO
	var target := player.pos + up * 4.0 + look
	# zoomed far out: slide the view toward the planet's centre so the whole globe fits
	if zoom >= 8.0:
		target = up * maxf(Defs.R_IN + 20.0, player.pos.length() * (0.35 if zoom < 10.0 else 0.02))
	elif zoom >= 4.0:
		target = up * player.pos.length() * 0.8
	cam_c = cam_c.lerp(target, 0.12)
	if cam_c.length() < Defs.R_IN + 10.0:
		cam_c = up * (Defs.R_IN + 10.0)

func _update_player(m: Mage) -> void:
	var p := m
	var aim: Vector2 = m.input.aim
	if m.dead:
		return
	var a := atan2(p.pos.y, p.pos.x)
	var R := basis_r(a)
	var mid_t := type_at(p.pos + basis_d(a) * (p.h * 0.1))
	var head_t := type_at(p.pos - basis_d(a) * (p.h * 0.5 - 2.0))
	p.in_liquid = Defs.KIND[mid_t] == Defs.K_LIQUID
	var g := 0.17 * gravity_at(p.pos)
	var move: int = m.input.move
	var face := (aim - p.pos).dot(R)
	if absf(face) > 1.0:
		p.facing = 1 if face > 0 else -1
	var speed := 0.6 if p.in_liquid else 1.05
	p.vx += (move * speed - p.vx) * (0.35 if p.on_ground else 0.12)
	var jump: bool = m.input.jump
	if p.on_ground:
		m.air_time = 0
		m.ground_t = 0
	else:
		m.air_time += 1
		m.ground_t += 1
	# forgiving jumps: remember the press for a few frames, and allow it shortly after leaving
	# the ground (loose sand / snow can shift under your feet for a frame)
	if jump and not m.jump_held:
		m.jump_buf = 8
	if m.jump_buf > 0:
		m.jump_buf -= 1
		if (m.ground_t <= 6 or p.in_liquid) and p.vy > -1.0:
			p.vy = -1.8 if p.in_liquid else (-3.55 if m.items.has("boots") else -3.0)
			m.jump_buf = 0
			m.ground_t = 99
			m.air_time = 0
	m.jump_held = jump
	if jump and not p.on_ground and not p.in_liquid and m.air_time > 10 and m.mana > 0.5:
		p.vy -= g + 0.2
		p.vy = maxf(p.vy, -1.9)
		m.mana -= 0.55
		if randf() < 0.6:
			_particle(p.pos - basis_d(a) * (-p.h * 0.5) + R * (randf() * 3.0 - 1.5), Vector2((randf() - 0.5) * 0.4, 0.4 + randf() * 0.4), 18, Color8(140, 220, 255), true, 0.0)
	if p.in_liquid:
		if jump:
			p.vy -= 0.26
		p.vy += g * 0.3
		var visc := mid_t == Defs.MUD
		p.vx *= 0.7 if visc else 0.9
		p.vy *= 0.75 if visc else 0.9
	else:
		p.vy += g
	p.vy = minf(p.vy, 4.5)
	move_body(p)
	# hazards
	var l := to_grid(p.pos)
	var bx := l.x - p.w * 0.5
	var by := l.y - p.h * 0.5
	var lava := box_count(bx, by, p.w, p.h, Defs.LAVA)
	var fire := box_count(bx, by, p.w, p.h, Defs.FIRE)
	if lava > 0:
		hurt(m, (0.08 if m.heat_ward else 0.55) * mini(lava, 6), Vector2.ZERO, false)
	if fire > 0:
		hurt(m, (0.02 if m.heat_ward else 0.08) * mini(fire, 6), Vector2.ZERO, false)
	var sa: Vector4 = gpu.surf_at(a)
	if p.pos.length() < sa.w + 20.0 and not m.heat_ward:
		hurt(m, 0.05, Vector2.ZERO, false)
	if Defs.KIND[head_t] == Defs.K_LIQUID:
		m.breath -= 1.0
		if m.breath <= 0:
			m.breath = 0
			hurt(m, 0.25, Vector2.ZERO, false)
	else:
		m.breath = minf(m.max_breath, m.breath + 4.0)
	if m.iframes > 0:
		m.iframes -= 1
	m.mana = minf(m.max_mana, m.mana + m.mana_regen)
	if m.hp < m.max_hp:
		m.hp = minf(m.max_hp, m.hp + 0.02)

func hurt(m: Mage, dmg: float, knock: Vector2, hit: bool) -> void:
	if m.dead or test_god:
		return
	if hit:
		if m.iframes > 0:
			return
		m.iframes = 40
		m.vx += knock.x
		m.vy += knock.y
	m.hp -= dmg
	if m.local:
		hurt_flash = minf(1.0, hurt_flash + (0.6 if hit else 0.05))
	if m.hp <= 0:
		m.hp = 0
		if m.local:
			_on_death()
		else:
			m.dead = true

func _on_death() -> void:
	dead = true
	for k in 40:
		_particle(player.pos, Vector2(randf() - 0.5, randf() - 0.5) * 2.0, 40, Color8(140, 200, 255), true, 0.0)
	get_tree().create_timer(1.2).timeout.connect(_show_death_screen)

func _show_death_screen() -> void:
	if dead:
		state = "dead"
		ui.show_death()

func revive() -> void:
	for m in Defs.NM:
		player.inv[m] = int(player.inv[m] * 0.75)
	ui.hide_death()
	_respawn()
	state = "play"
	save_game()

# =============================================================== spells ===
func _staff(m: Mage, aim: Vector2) -> Array:
	var a := atan2(m.pos.y, m.pos.x)
	var hand := m.pos + basis_r(a) * (m.facing * 2.0) + basis_d(a) * 1.0
	var dir := (aim - hand).normalized()
	if dir == Vector2.ZERO:
		dir = basis_r(a)
	return [hand + dir * 7.0, dir, hand]

func _cast(m: Mage, id: String, aim: Vector2) -> void:
	var s: Dictionary = Defs.SPELLS[id]
	if m.cast_cd > 0 or m.mana < float(s["mana"]):
		return
	if id == "conjure":
		_conjure(m, aim)
		m.cast_cd = s["cd"]
		return
	if id == "blink":
		if _blink(m, aim):
			m.mana -= float(s["mana"])
			m.cast_cd = s["cd"]
		return
	m.mana -= float(s["mana"])
	m.cast_cd = s["cd"]
	var st := _staff(m, aim)
	var pd: Dictionary = Defs.PROJ[id]
	_spawn_proj(id, st[0], st[1] * float(pd["speed"]), "player")
	var col: Color = s["color"]
	for k in 6:
		_particle(st[0], Vector2(randf() - 0.5, randf() - 0.5), 12, col, true, 0.0)

## step through space to the cursor (up to 48 cells), stopping at the last free spot along the way
func _blink(m: Mage, aim: Vector2) -> bool:
	var from := m.pos
	var d := aim - from
	if d.length() > 48.0:
		d = d.normalized() * 48.0
	var steps := int(d.length())
	for s2 in range(steps, 3, -1):
		var p := from + d * (float(s2) / steps)
		if not in_grid(p, 8.0):
			continue
		var l := to_grid(p)
		if not box_solid(l.x - m.w * 0.5, l.y - m.h * 0.5, m.w, m.h):
			for k in 16:
				_particle(from, Vector2(randf() - 0.5, randf() - 0.5) * 1.5, 20, Color(0.55, 0.95, 1.0), true, 0.0)
				_particle(p, Vector2(randf() - 0.5, randf() - 0.5) * 1.5, 20, Color(0.55, 0.95, 1.0), true, 0.0)
			m.pos = p
			m.vx = 0
			m.vy = 0
			lights.append([p, 24.0, Color(0.5, 0.9, 1.2)])
			return true
	return false

func _spawn_proj(type: String, p: Vector2, v: Vector2, owner: String) -> void:
	var pd: Dictionary = Defs.PROJ[type]
	projs.append({"type": type, "pos": p, "vel": v, "life": int(pd["life"]), "owner": owner})

func _reach(m: Mage, aim: Vector2) -> Vector2:
	var c := m.pos
	var d := aim - c
	if d.length() > REACH:
		d = d.normalized() * REACH
	return c + d

func _excavate(m: Mage, aim: Vector2) -> void:
	var p := _reach(m, aim)
	brushes.append([p, m.dig_r, 1, 0, m.tier, 0, 0, m.slot])
	lights.append([p, 10.0, Color(0.4, 0.8, 0.5)])

func _conjure(m: Mage, aim: Vector2) -> void:
	if m.mat <= 0 or m.inv[m.mat] <= 0:
		return
	var p := _reach(m, aim)
	var budget := mini(m.inv[m.mat], 6)
	m.pending_place = budget
	brushes.append([p, 1.6, 5, m.mat, 0, budget, 4.5, m.slot])

func _update_projectiles() -> void:
	for k in range(projs.size() - 1, -1, -1):
		var pr: Dictionary = projs[k]
		var pd: Dictionary = Defs.PROJ[pr["type"]]
		var pos: Vector2 = pr["pos"]
		var vel: Vector2 = pr["vel"]
		vel += -pos.normalized() * float(pd["g"]) * gravity_at(pos)
		pr["life"] = int(pr["life"]) - 1
		var steps := maxi(1, int(ceil(vel.length() * 2.0)))
		var hit := false
		var hit_enemy = null
		var hit_m = null
		_use_grid(_nearest_mage(pos))
		for s in steps:
			pos += vel / steps
			if pos.length() >= Defs.R_TOP - 1.0 or pos.length() < Defs.R_IN:
				hit = true
				break
			if in_grid(pos, 2.0):
				var t := type_at(pos)
				if Defs.KIND[t] == Defs.K_SOLID or Defs.KIND[t] == Defs.K_POWDER:
					hit = true
					break
				if (pr["type"] == "fireball" or pr["type"] == "efire") and t == Defs.WATER:
					brushes.append([pos, 1.0, 3, Defs.STEAM, 0, 0, 0])
					pr["life"] = 0
					break
			if pr["owner"] == "player":
				for e in enemies:
					if not e.dead and _overlaps(pos, e):
						hit = true
						hit_enemy = e
						break
				if hit:
					break
			else:
				for pm in players:
					if not pm.dead and _overlaps(pos, pm):
						hit = true
						hit_m = pm
						break
				if hit:
					break
		pr["pos"] = pos
		pr["vel"] = vel
		if hit or int(pr["life"]) <= 0:
			_impact(pr, hit, hit_enemy, hit_m)
			projs.remove_at(k)
			continue
		var col: Color = Defs.SPELLS[pr["type"]]["color"] if Defs.SPELLS.has(pr["type"]) else Color(1, 0.35, 0.12)
		lights.append([pos, float(pd["light"]), col * 0.85])
		if randf() < 0.6:
			_particle(pos, Vector2(randf() - 0.5, randf() - 0.5) * 0.3, 10 + randi() % 8, col, true, 0.0)

func _overlaps(p: Vector2, e: Body) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var o := p - e.pos
	return absf(o.dot(basis_r(a))) < e.w * 0.5 + 1.0 and absf(o.dot(basis_d(a))) < e.h * 0.5 + 1.0

func _impact(pr: Dictionary, hit: bool, e, hit_m) -> void:
	var p: Vector2 = pr["pos"]
	var type: String = pr["type"]
	var pd: Dictionary = Defs.PROJ[type]
	var kb := 1.2
	match type:
		"spark":
			if e != null:
				_hurt_enemy(e, pd["dmg"], kb, -0.6)
			elif hit:
				brushes.append([p, 1.6, 6, 0, tier, 0, 0])
		"fireball":
			_explode(p, 7.0, maxi(1, tier), 1, 38.0)
		"quake":
			_explode(p, 15.0, mini(3, tier + 1), 2, 70.0)
		"starfall":
			_explode(p, 12.0, maxi(2, tier), 1, 80.0)
		"tide":
			brushes.append([p, 5.5, 3, Defs.WATER, 0, 0, 0])
			if e != null:
				_hurt_enemy(e, pd["dmg"], kb * 2.0, -1.0)
		"frost":
			brushes.append([p, 7.0, 4, 0, 0, 0, 0])
			for en in enemies:
				if en.pos.distance_to(p) < 13.0:
					en.slow = 200
			if e != null:
				_hurt_enemy(e, pd["dmg"], kb, 0.0)
		"efire":
			if hit_m != null:
				hurt(hit_m, float(pd["dmg"]) * (0.6 if hit_m.heat_ward else 1.0), Vector2(signf(randf() - 0.5) * 1.5, -1.0), true)
			else:
				brushes.append([p, 1.2, 3, Defs.FIRE, 0, 0, 0])
	var col: Color = Defs.SPELLS[type]["color"] if Defs.SPELLS.has(type) else Color(1, 0.35, 0.12)
	for k in 10:
		_particle(p, Vector2(randf() - 0.5, randf() - 0.8) * 1.5, 14 + randi() % 10, col, true, 0.05)

func _explode(p: Vector2, r: float, power: int, kind: int, dmg: float) -> void:
	brushes.append([p, r, 2, kind, power, 0, 0])
	for k in int(r * 4):
		_particle(p, Vector2(randf() - 0.5, randf() - 0.5) * 3.0, 15 + randi() % 20, Color(1, 0.6 + randf() * 0.3, 0.25), true, 0.03)
	lights.append([p, r * 4.0, Color(1.5, 0.8, 0.3)])
	shake = maxf(shake, r * 0.6)
	if dmg > 0:
		for e in enemies:
			var d: float = e.pos.distance_to(p)
			if d < r + 4.0 + e.w * 0.5:
				_hurt_enemy(e, dmg * (1.0 - d / (r + 4.0 + e.w)), signf((e.pos - p).dot(basis_r(grid_a))) * 2.0, -2.0)

# =============================================================== enemies ===
func spawn_enemy(type: String, p: Vector2) -> Enemy:
	var d: Dictionary = Defs.ENEMY[type]
	var e := Enemy.new()
	e.type = type
	e.d = d
	e.pos = p
	e.w = d["w"]
	e.h = d["h"]
	e.hp = d["hp"]
	e.max_hp = d["hp"]
	e.boss = d.get("boss", false)
	e.awake = not e.boss
	e.step_h = 0 if d["fly"] else (4 if e.boss else int(d.get("step", 1)))
	e.t = 30.0 + randf() * 60.0
	e.phase = randf() * 6.0
	enemies.append(e)
	return e

func _hurt_enemy(e: Enemy, dmg: float, kx: float, ky: float) -> void:
	e.hp -= dmg
	e.flash = 6
	if not e.boss:
		e.vx += kx
		e.vy += ky
	e.awake = true
	if e.hp <= 0 and not e.dead:
		_kill_enemy(e)

func _kill_enemy(e: Enemy) -> void:
	e.dead = true
	if e.guard_id >= 0:
		var slain: Array = planet_state.get("slain", [])
		if not slain.has(e.guard_id):
			slain.append(e.guard_id)
		planet_state["slain"] = slain
	if e.type == "mimic":
		_rare_find(0.6)
	for k in (120 if e.boss else 16):
		_particle(e.pos, Vector2(randf() - 0.5, -randf()) * 2.0, 30 + randi() % 30, Color(1, 0.7, 0.3), true, 0.05)
	for dr in e.d["drops"]:
		if randf() < float(dr[2]):
			var n := 1 + randi() % int(dr[1])
			player.inv[int(dr[0])] += n
			ui.toast("+%d %s" % [n, Defs.NAMES[int(dr[0])]], Defs.COLOR[int(dr[0])])
	if e.boss:
		items["heart"] = true
		planet_state["boss_dead"] = true
		player.inv[Defs.EMBER] += 40
		player.inv[Defs.OBSIDIAN] += 20
		ui.toast("Vulkhar falls! You claim the EMBER HEART.", Color(1, 0.7, 0.3), 6.0)
		ui.toast("+40 Ember Crystal, +20 Obsidian. The Core Siphon can now be forged.", Color(1, 0.85, 0.3), 6.0)
		shake = 18.0
		save_game()

func _update_enemies() -> void:
	for k in range(enemies.size() - 1, -1, -1):
		var e: Enemy = enemies[k]
		if e.dead:
			enemies.remove_at(k)
			continue
		var tgt := _nearest_mage(e.pos)
		_use_grid(tgt)
		var dist := e.pos.distance_to(tgt.pos)
		if not e.boss and dist > (300.0 if e.guard_id >= 0 else 420.0):
			if e.guard_id >= 0:
				_guards_alive.erase(e.guard_id)
			enemies.remove_at(k)
			continue
		if not in_grid(e.pos, 12.0):
			continue   # outside the simulated neighbourhood: frozen
		if e.flash > 0:
			e.flash -= 1
		var slow_f := 0.4 if e.slow > 0 else 1.0
		if e.slow > 0:
			e.slow -= 1
		var lt := to_grid(e.pos)
		var pl := to_grid(tgt.pos)
		var dx := pl.x - lt.x
		var dy := pl.y - lt.y
		e.in_liquid = Defs.KIND[type_at(e.pos)] == Defs.K_LIQUID
		var g := 0.17 * gravity_at(e.pos)
		e.facing = -1 if dx < 0 else 1
		if tgt.dead:
			e.vx *= 0.9
		match e.type:
			"slime":
				if e.on_ground:
					e.vx *= 0.75
					e.t -= 1
					if e.t <= 0 and dist < 160:
						e.vx = signf(dx) * (1.0 + randf() * 0.6) * slow_f
						e.vy = -2.3 - randf() * 0.8
						e.t = 45 + randf() * 50
				e.vy += g * 0.3 if e.in_liquid else g
				if e.in_liquid:
					e.vy *= 0.9
			"skeleton":
				# walks toward you once it notices you, hops over steps and rubble
				if dist < 170 and not tgt.dead:
					if e.on_ground:
						e.vx += (signf(dx) * 0.62 * slow_f - e.vx) * 0.2
						if e.hit_wall:
							e.vy = -2.7
				elif e.on_ground:
					e.vx *= 0.8
				e.vy += g * 0.3 if e.in_liquid else g
			"mimic":
				if e.on_ground:
					e.vx *= 0.7
					e.t -= 1
					if e.t <= 0 and not tgt.dead:
						e.vx = signf(dx) * (1.5 + randf() * 0.6) * slow_f
						e.vy = -2.9 - randf() * 0.6
						e.t = 28 + randf() * 25
				e.vy += g
			"bat":
				e.phase += 0.12
				if dist < 200:
					e.vx += signf(dx) * 0.09
					e.vy += signf(dy + sin(e.phase) * 14.0) * 0.08
				else:
					e.vx += (randf() - 0.5) * 0.1
					e.vy += (randf() - 0.5) * 0.1
				var sp := 1.25 * slow_f
				e.vx = clampf(e.vx, -sp, sp)
				e.vy = clampf(e.vy, -sp, sp)
				if e.hit_wall:
					e.vy -= 0.3
			"imp":
				e.phase += 0.05
				var ax := signf(dx) if dist > 45 else -signf(dx)
				e.vx += ax * 0.04
				e.vy += signf(dy - 20.0 + sin(e.phase) * 10.0) * 0.04
				var sp2 := 0.75 * slow_f
				e.vx = clampf(e.vx, -sp2, sp2)
				e.vy = clampf(e.vy, -sp2, sp2)
				e.shoot_t -= 1
				if e.shoot_t <= 0 and dist < 150 and not tgt.dead:
					_spawn_proj("efire", e.pos, (player.pos - e.pos).normalized() * 1.7, "enemy")
					e.shoot_t = 140 + randf() * 60
			"golem":
				if not e.awake and dist < 110:
					e.awake = true
					ui.toast("VULKHAR, THE EMBER GOLEM awakens!", Color(1, 0.48, 0.16), 4.0)
					shake = 10.0
				if e.awake and not tgt.dead:
					var enraged := e.hp < e.max_hp * 0.4
					if e.on_ground:
						e.vx += (signf(dx) * (0.75 if enraged else 0.5) * slow_f - e.vx) * 0.1
					e.t -= 1
					e.shoot_t -= 1
					if e.shoot_t <= 0:
						var n := 7 if enraged else 5
						var to := (player.pos - e.pos).normalized()
						for s in n:
							var ang := (s - (n - 1) / 2.0) * 0.18
							_spawn_proj("efire", e.pos, to.rotated(ang) * 1.9, "enemy")
						e.shoot_t = 110 if enraged else 170
					if e.t <= 0 and e.on_ground:
						e.vy = -4.2
						e.vx = signf(dx) * 1.6
						e.t = 160 if enraged else 260
						e.leaping = true
					if e.leaping and e.on_ground and e.vy == 0:
						e.leaping = false
						shake = 12.0
						_explode(e.pos - basis_d(atan2(e.pos.y, e.pos.x)) * (-e.h * 0.5 - 1.0), 6.0, 1, 0, 0.0)
						if absf(dx) < 26 and absf(dy) < 20:
							hurt(tgt, 18.0, Vector2(signf(dx) * 3.0, -2.0), true)
				e.vy += g
		if e.d["fly"]:
			e.vy *= 0.98
		elif e.vy > 4.5:
			e.vy = 4.5
		move_body(e)
		if e.type != "golem" and e.type != "imp":
			var l2 := to_grid(e.pos)
			if box_count(l2.x - e.w * 0.5, l2.y - e.h * 0.5, e.w, e.h, Defs.LAVA) > 0:
				_hurt_enemy(e, 0.6, 0, 0)
		if not tgt.dead and absf(dx) < (e.w + tgt.w) * 0.5 and absf(dy) < (e.h + tgt.h) * 0.5:
			hurt(tgt, float(e.d["dmg"]), Vector2(signf(dx) * 2.2, -1.6), true)
		if e.type == "golem":
			lights.append([e.pos, 40.0, Color(1.0, 0.4, 0.1)])
		elif e.type == "skeleton":
			lights.append([e.pos - basis_d(atan2(e.pos.y, e.pos.x)) * 4.0, 7.0, Color(0.7, 0.18, 0.1)])
		elif e.type == "imp":
			lights.append([e.pos, 14.0, Color(0.6, 0.2, 0.05)])

func _try_spawn() -> void:
	spawn_timer -= 1
	if spawn_timer > 0 or dead:
		return
	spawn_timer = 90
	var count := 0
	for e in enemies:
		if not e.boss:
			count += 1
	if count >= 7:
		return
	var a := atan2(player.pos.y, player.pos.x)
	var sa: Vector4 = gpu.surf_at(a)
	var r := player.pos.length()
	var night := _local_daylight(player.pos) < 0.3
	var type := ""
	if r > sa.x - 14.0:
		# the surface is gentle by day, busier at night
		var slimes := 0
		for e in enemies:
			if e.type == "slime":
				slimes += 1
		if slimes >= (5 if night else 2) or randf() > (0.5 if night else 0.12):
			return
		type = "slime"
	elif r > sa.z:
		if randf() > 0.45:
			return
		type = "bat"
	elif r > sa.w:
		if randf() > 0.5:
			return
		type = "bat" if randf() < 0.6 else "imp"
	else:
		if randf() > 0.5:
			return
		type = "imp"
	var d: Dictionary = Defs.ENEMY[type]
	for tries in 12:
		# just beyond the edge of the screen, but inside the simulated area
		var side := -1.0 if randf() < 0.5 else 1.0
		var near := minf(VW * 0.5 + 8.0, HALF - 30.0)
		var lx := HALF + side * randf_range(near, HALF - 14.0)
		var ly := HALF + (randf() - 0.5) * minf(VH * 1.2, GS - 40.0)
		if not box_solid(lx - d["w"] * 0.5, ly - d["h"] * 0.5, d["w"], d["h"]) and Defs.KIND[gtype(int(lx), int(ly))] != Defs.K_LIQUID:
			spawn_enemy(type, from_grid(Vector2(lx, ly)))
			return

func _local_daylight(p: Vector2) -> float:
	var sun_a := spawn_angle - 1.1 + time / DAY_LEN * TAU
	return clampf(p.normalized().dot(Vector2(cos(sun_a), sin(sun_a))) * 1.6 + 0.15, 0.025, 1.0)

# ============================================================= particles ===
func _particle(p: Vector2, v: Vector2, life: int, col: Color, self_lit: bool, grav: float) -> void:
	if parts.size() > 1500:
		return
	parts.append({"pos": p, "vel": v, "life": life, "col": col, "self": self_lit, "grav": grav, "home": false})

func _spawn_suck_particles(t: int, n: int) -> void:
	if brushes.size() == 0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return
	var aim := _reach(player, screen_to_world(get_viewport().get_mouse_position() / scale_px))
	for k in n:
		var c: Color = Defs.COLOR[t]
		parts.append({"pos": aim + Vector2(randf() - 0.5, randf() - 0.5) * dig_r * 2.0, "vel": Vector2(randf() - 0.5, randf() - 0.5), "life": 60, "col": c, "self": true, "grav": 0.0, "home": true})

func _update_particles() -> void:
	var a := atan2(player.pos.y, player.pos.x)
	var down := basis_d(a)
	for k in range(parts.size() - 1, -1, -1):
		var p: Dictionary = parts[k]
		var v: Vector2 = p["vel"]
		var pos: Vector2 = p["pos"]
		if p["home"]:
			var d := player.pos - pos
			var dl := maxf(d.length(), 0.001)
			v += d / dl * 0.35
			v *= 0.9
			if dl < 3.0:
				p["life"] = 0
		else:
			v += down * float(p["grav"])
		pos += v
		p["pos"] = pos
		p["vel"] = v
		p["life"] = int(p["life"]) - 1
		if int(p["life"]) <= 0:
			parts.remove_at(k)

func _update_wisp() -> void:
	wisp_t += 0.05
	var a := atan2(player.pos.y, player.pos.x)
	var target := player.pos + basis_r(a) * (-player.facing * 7.0) - basis_d(a) * (10.0 + sin(wisp_t * 2.0) * 2.0)
	wisp = wisp.lerp(target, 0.08)
	if randf() < 0.3:
		_particle(wisp + Vector2(randf(), randf()) * 2.0, Vector2(randf() - 0.5, randf() - 0.5) * 0.2, 20, Color8(120, 200, 255), true, -0.005)
	lights.append([wisp, 46.0, Color(0.95, 1.0, 1.1)])

# =============================================================== weather ===
func _update_weather() -> void:
	weather_timer -= 1
	if weather_timer <= 0:
		var raining := rain_target > 0
		rain_target = 0.0 if raining else (0.4 + randf() * 0.6 if randf() < 0.55 else 0.0)
		weather_timer = int(60 * (40 + randf() * 70))
	rain += (rain_target - rain) * 0.002
	flash *= 0.85
	var b := _biome_at(atan2(player.pos.y, player.pos.x))
	if b["weather"] == "rain" and rain > 0.6 and randf() < 0.0012:
		flash = 1.2
		shake = 5.0

# ============================================================= crafting ====
func recipe_done(r: Dictionary) -> bool:
	if r.has("spell"):
		return known.has(r["spell"])
	match r["id"]:
		"tier2": return tier >= 2
		"tier3": return tier >= 3
		"tier4": return tier >= 4
		"wide": return dig_r >= 7.0
		"vital": return items.has("vital") or (max_hp >= 150 and not items.has("ring"))
		"mana": return items.has("mana_crystal") or (max_mana >= 170 and not items.has("circlet"))
		"ward": return heat_ward
	return false

func recipe_unlocked(r: Dictionary) -> bool:
	if r.has("scroll") and not items.has(r["scroll"]):
		return false
	match r["id"]:
		"tier2": return tier == 1
		"tier3": return tier == 2
		"tier4": return tier == 3 and items.has("heart")
		"gate": return tier >= 4
	return true

func recipe_lock_text(r: Dictionary) -> String:
	match r["id"]:
		"tier3": return "Needs Copper Focus"
		"tier4": return "Needs Obsidian Focus + the Ember Heart"
		"gate": return "Needs the Core Siphon"
		"blink": return "Find the Scroll of Blink in a chest"
		"starfall": return "Find the Scroll of Starfall in a chest"
	return "Locked"

func recipe_affordable(r: Dictionary) -> bool:
	for k in r["cost"]:
		if player.inv[int(k)] < int(r["cost"][k]):
			return false
	return true

func craft(r: Dictionary) -> bool:
	if recipe_done(r) or not recipe_unlocked(r) or not recipe_affordable(r):
		return false
	for k in r["cost"]:
		player.inv[int(k)] -= int(r["cost"][k])
	if r.has("give"):
		for k in r["give"]:
			player.inv[int(k)] += int(r["give"][k])
	if r.has("spell"):
		known.append(r["spell"])
		known.sort_custom(func(x, y): return Defs.SPELL_ORDER.find(x) < Defs.SPELL_ORDER.find(y))
		ui.toast("New spell learned: %s" % Defs.SPELLS[r["spell"]]["name"], Color(1, 0.82, 0.23), 4.0)
	match r["id"]:
		"tier2": tier = 2
		"tier3": tier = 3
		"tier4": tier = 4
		"wide": dig_r = 7.0
		"vital":
			max_hp += 50
			hp = max_hp
			items["vital"] = true
		"mana":
			max_mana += 70
			mana_regen = 0.32
			items["mana_crystal"] = true
		"ward": heat_ward = true
		"gate":
			travel_next()
			return true
	if not r.has("spell") and not r.has("give"):
		ui.toast("%s forged!" % r["name"], Color(1, 0.82, 0.23), 4.0)
	save_game()
	return true

# ================================================================ input ====
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k: int = ev.keycode
		if state == "play" or state == "forge":
			if k == KEY_C or (k == KEY_ESCAPE and state == "forge"):
				toggle_forge()
				return
		if state != "play":
			return
		if k == KEY_SPACE or k == KEY_W or k == KEY_UP:
			jump_buf = 8   # catch even the quickest tap
		if k >= KEY_1 and k <= KEY_9:
			var n := k - KEY_1
			if n < known.size():
				sel = n
		elif k == KEY_Q or k == KEY_E:
			_cycle_material(1 if k == KEY_E else -1)
		elif k == KEY_F:
			_try_open_chest()
		elif k == KEY_M or k == KEY_Z:
			zoom_i = (zoom_i + 1) % zoom_levels.size()
			zoom = zoom_levels[zoom_i]
			ui.toast("View: %s" % ("close" if zoom_i == 0 else "x%d" % int(zoom)), Color(0.8, 0.9, 1.0), 1.0)
		elif k == KEY_F8 or k == KEY_F7:
			# developer shortcut: jump 120 cells down (F8) or up (F7)
			var up2 := player.pos.normalized()
			player.pos += up2 * (120.0 if k == KEY_F7 else -120.0)
			player.vx = 0
			player.vy = 0
			cam_c = player.pos
			ui.toast("Dev: moved %s" % ("up" if k == KEY_F7 else "down"), Color(0.6, 1, 0.6), 1.0)
		elif k == KEY_F9:
			for m in Defs.NM:
				if Defs.COLLECT[m] == 1 and Defs.PLACE[m] == 1:
					player.inv[m] += 200
			ui.toast("Creative stock: +200 of every material", Color(0.6, 1, 0.6))
	elif ev is InputEventMouseButton and ev.pressed and state == "play":
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			dig_tap = 10
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			sel = (sel - 1 + known.size()) % known.size()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			sel = (sel + 1) % known.size()

func _cycle_material(dir: int) -> void:
	var owned := []
	for m in Defs.NM:
		if player.inv[m] > 0 and Defs.PLACE[m] == 1:
			owned.append(m)
	if owned.is_empty():
		return
	var k := owned.find(mat)
	k = (k + dir + owned.size()) % owned.size()
	mat = owned[k]
	ui.toast("Conjure material: %s" % Defs.NAMES[mat], Defs.COLOR[mat], 1.0)

func select_material(m: int) -> void:
	mat = m
	var ci := known.find("conjure")
	if ci >= 0:
		sel = ci

func toggle_forge() -> void:
	if state == "play":
		state = "forge"
		ui.show_forge()
	elif state == "forge":
		state = "play"
		ui.hide_forge()

# ========================================================== planet setup ===
func start_game(use_save: bool) -> void:
	state = "loading"
	ui.show_loading("Forging a round planet…")
	await get_tree().process_frame
	await get_tree().process_frame
	var s = _load_save() if use_save else null
	if s != null:
		_apply_save(s)
	else:
		_delete_worlds()
		player.inv.fill(0)
		known = ["spark", "conjure"]
		tier = 1
		dig_r = 4.5
		max_hp = 100
		max_mana = 100
		mana_regen = 0.22
		heat_ward = false
		items = {}
	_enter_planet(int(s["planet"]) if s != null else 0)
	ui.hide_loading()
	ui.show_hud()
	state = "play"
	if s == null:
		ui.toast("Right-click to excavate. Left-click casts your selected spell.", Color.WHITE, 7.0)
		ui.toast("Press C to open the Wisp Forge. Press M to zoom out and see the whole planet.", Color(1, 0.82, 0.23), 9.0)
	save_game()

func _enter_planet(index: int) -> void:
	planet = Defs.make_planet(index)
	gpu.build_surface(planet)
	# spawn in the middle of the first friendly biome
	var bl: Array = planet["biomes"]
	var sb := 0
	for i in bl.size():
		if int(Defs.BIOMES[bl[i]]["flags"]) & 8:
			sb = i
			break
	spawn_angle = (sb + 0.5) / bl.size() * TAU
	var best := spawn_angle
	for k in range(-20, 21):
		var a := spawn_angle + k * 0.002
		if gpu.surf_at(a).x > gpu.surf_at(best).x:
			best = a
	spawn_angle = fposmod(best, TAU)
	var boss_a := fposmod(spawn_angle + PI, TAU)
	var mag: float = gpu.surf_at(boss_a).w
	boss_info = Vector4(boss_a, mag - 4.0, 48.0, 20.0)
	planet_state = {}
	var loaded := _load_world(index)
	if loaded and int(planet_state.get("gen", 1)) != GEN_VERSION:
		# saved by an older structure generator: build the planet again (your progress is kept)
		var kept := {"boss_dead": planet_state.get("boss_dead", false)}
		loaded = false
		planet_state = kept
		print("[Wisp Forge] regenerating %s with the new structure generator" % planet["name"])
	planet_state["gen"] = GEN_VERSION
	builds = Buildings.new()
	builds.plan(planet, gpu.surface, spawn_angle, boss_a, not loaded)
	if not loaded:
		gpu.generate(spawn_angle, boss_info, builds.sites)
		gpu.stamp(builds.structs, int(planet["seed"]))
		# let the ruins fall into ruin: unsupported pieces drop and break before you arrive
		gpu.settle(builds.settle, 0.0, 110)
		print("[Wisp Forge] %s: %d structures" % [planet["name"], builds.structs.size()])
		builds.structs.clear()
	enemies.clear()
	_guards_alive.clear()
	projs.clear()
	parts.clear()
	var bd := Vector2(cos(boss_a), sin(boss_a))
	if not planet_state.get("boss_dead", false):
		spawn_enemy("golem", bd * (boss_info.y - boss_info.w + 10.0))
	_respawn()
	if loaded and planet_state.has("player"):
		var pp: Array = planet_state["player"]
		player.pos = Vector2(float(pp[0]), float(pp[1]))
		player.grid_g = player.pos
		player.grid_a = atan2(player.pos.y, player.pos.x)
		_use_grid(player)
		time = float(planet_state.get("time", time))
	cam_c = player.pos
	wisp = player.pos
	# let fresh liquids settle around the spawn
	_write_frame_params()
	for k in 60:
		gpu.step([player.pos], [], false, true)
	_gpu_frame(false)
	if not loaded:
		save_world(false)
	ui.toast("%s: %s" % [planet["name"], planet["desc"]], Color(0.8, 0.95, 0.9), 6.0)

func _respawn() -> void:
	var rs: float = gpu.surf_at(spawn_angle).x
	player.pos = Vector2(cos(spawn_angle), sin(spawn_angle)) * (rs + 30.0)
	player.vx = 0
	player.vy = 0
	player.grid_g = player.pos
	player.grid_a = spawn_angle
	_use_grid(player)
	hp = max_hp
	mana = max_mana
	breath = max_breath
	dead = false
	iframes = 90

func travel_next() -> void:
	toggle_forge()
	state = "loading"
	ui.show_loading("The World Gate folds space…")
	save_world(true)
	await get_tree().process_frame
	await get_tree().process_frame
	player.inv[Defs.CORE] = 0
	_enter_planet(int(planet["index"]) + 1)
	ui.hide_loading()
	state = "play"
	save_game()

# ================================================================== save ===
const OLD_SAVE_PATH := "user://wispforge_save.json"
const GEN_VERSION := 4            # bump when the structure generator changes; older planets regenerate
const WORLD_MAGIC := 0x57465732   # "WFW2": foreground cells, then the background layer
var planet_state := {}            # per-planet facts saved with the world (boss defeated, where you were)
var _save_task := -1

## Saves live in "Wisp Forge/saves" so the whole game stays in one portable folder.
## The test mode uses its own folder inside it, so your real saves are never touched.
func _save_dir() -> String:
	var d := _real_save_dir()
	if testing:
		d = d.path_join("test")
		if not DirAccess.dir_exists_absolute(d):
			DirAccess.make_dir_recursive_absolute(d)
	return d

func _real_save_dir() -> String:
	var d := ProjectSettings.globalize_path("res://").path_join("../saves").simplify_path()
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d

func _save_path() -> String:
	return _save_dir().path_join("progress.json")

func save_game() -> void:
	var d := {"planet": planet.get("index", 0), "inv": Array(player.inv), "known": known, "tier": tier, "dig_r": dig_r,
		"max_hp": max_hp, "max_mana": max_mana, "mana_regen": mana_regen, "heat_ward": heat_ward, "items": items, "mat": mat}
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func _load_save():
	var path := _save_path()
	if not FileAccess.file_exists(path):
		path = OLD_SAVE_PATH   # progress saved by earlier versions
	if not FileAccess.file_exists(path):
		return null
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return null
	return d

func _apply_save(s: Dictionary) -> void:
	var a: Array = s.get("inv", [])
	for i in mini(a.size(), Defs.NM):
		player.inv[i] = int(a[i])
	known = []
	for k in s.get("known", ["spark", "conjure"]):
		known.append(str(k))
	tier = int(s.get("tier", 1))
	dig_r = maxf(4.5, float(s.get("dig_r", 4.5)))
	max_hp = float(s.get("max_hp", 100))
	max_mana = float(s.get("max_mana", 100))
	mana_regen = float(s.get("mana_regen", 0.22))
	heat_ward = bool(s.get("heat_ward", false))
	items = s.get("items", {})
	mat = int(s.get("mat", Defs.DIRT))


# ============================================================ world files ===
## The whole planet (every cell) is saved compressed, so the world you changed is the world you
## come back to. Saving reads the cells back from the GPU, then compresses and writes on a worker
## thread so play doesn't stutter.
func _world_path(i: int) -> String:
	return _save_dir().path_join("world_%d.wfw" % i)

func save_world(blocking: bool) -> void:
	if planet.is_empty() or gpu == null or gpu.rd == null:
		return
	if _save_task >= 0:
		if not WorkerThreadPool.is_task_completed(_save_task):
			if not blocking:
				return
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	var raw: PackedByteArray = gpu.read_world()
	planet_state["player"] = [player.pos.x, player.pos.y]
	planet_state["time"] = time
	var meta := JSON.stringify(planet_state)
	var path := _world_path(int(planet["index"]))
	if blocking:
		_write_world_file(path, raw, meta)
	else:
		_save_task = WorkerThreadPool.add_task(_write_world_file.bind(path, raw, meta))

func _write_world_file(path: String, raw: PackedByteArray, meta: String) -> void:
	var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	var mb := meta.to_utf8_buffer()
	f.store_32(WORLD_MAGIC)
	f.store_32(raw.size())
	f.store_32(mb.size())
	f.store_buffer(mb)
	f.store_32(comp.size())
	f.store_buffer(comp)
	f.close()
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)
	print("[Wisp Forge] world saved: %s (%.1f MB)" % [path.get_file(), comp.size() / 1048576.0])

## Loads a saved planet into the GPU. Returns false if there is no usable save.
func _load_world(i: int) -> bool:
	var path := _world_path(i)
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != WORLD_MAGIC:
		return false
	var size := f.get_32()
	if size != Defs.total_cells() * 8:
		return false
	var meta_txt := f.get_buffer(f.get_32()).get_string_from_utf8()
	var comp := f.get_buffer(f.get_32())
	var raw := comp.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return false
	gpu.write_world(raw)
	var m = JSON.parse_string(meta_txt)
	planet_state = m if typeof(m) == TYPE_DICTIONARY else {}
	return true

func _delete_worlds() -> void:
	var d := DirAccess.open(_save_dir())
	if d == null:
		return
	for fn in d.get_files():
		if fn.begins_with("world_") and (fn.ends_with(".wfw") or fn.ends_with(".tmp")):
			d.remove(fn)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()

## Closing the window saves your progress and the whole world, then quits.
func quit_game() -> void:
	if state == "play" or state == "forge" or state == "dead":
		print("[Wisp Forge] saving before quitting...")
		save_game()
		save_world(true)
	get_tree().quit()

# ================================================================== info ===
func region_name() -> String:
	var a := atan2(player.pos.y, player.pos.x)
	var r := player.pos.length()
	var sa: Vector4 = gpu.surf_at(a)
	var sb: Vector4 = gpu.surf_b(a)
	var b := _biome_at(a)
	if r > Defs.R_TOP - 60.0:
		return "Edge of Space"
	if r > sa.x + 160.0:
		return "Upper Sky"
	if builds != null:
		var nm: String = builds.label_at(player.pos)
		if nm != "":
			return nm
	if r > sa.x - 14.0:
		return b["name"]
	if r > sa.z:
		return b["under"]
	if r > sa.w:
		return "The Umbral Deep"
	if r > sb.x:
		return "Molten Mantle"
	return "Planet Core"

func local_time_text() -> String:
	var sun_a := spawn_angle - 1.1 + time / DAY_LEN * TAU
	var d := wrapf(atan2(player.pos.y, player.pos.x) - sun_a, -PI, PI)
	var hours := fposmod(12.0 - d / TAU * 24.0, 24.0)
	return "%02d:%02d" % [int(hours), int(fposmod(hours * 60.0, 60.0))]
