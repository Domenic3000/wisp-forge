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
const Audio := preload("res://scripts/audio.gd")
var audio

const DAY_LEN := 60.0 * 7.0 * 60.0   # frames per day (7 minutes)
const REACH := 64.0
var GS := 384
var HALF := 192.0

class Body:
	var pos := Vector2.ZERO   # world-space centre
	var vx := 0.0             # velocity in the local frame (x along the surface, y toward the core)
	var vy := 0.0
	var w := 5.0
	var h := 12.0
	var step_h := 3
	var anim := 0.0            # walk / animation phase
	var stuck := 0             # frames spent wedged inside terrain
	var on_ground := false
	var in_liquid := false
	var hit_wall := false
	var facing := 1
	var drop_t := 0           # frames left falling through one-way platforms (down + jump)
	var on_platform := false  # standing on a one-way platform

## A treasure chest: one solid object (not a pile of cells), so it can only ever fall, land and
## open whole. You walk through it; F (or digging at it) opens it.
class Chest extends Body:
	var opened := false
	var open_t := -1          # frames since it was opened (-1: closed); it vanishes after a moment
	func _init() -> void:
		w = float(Defs.CHEST_W)
		h = float(Defs.CHEST_H)
		step_h = 0

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
	var home := Vector2.ZERO   # where it was spawned (a boss goes back there to recover)
	var leash_t := 0           # frames with nobody fighting it
	# getting around: the way it is heading, how long it wanders off after a dead end,
	# where it was a second ago (to notice it is stuck), and a detour for fliers
	var nav_dir := 1.0
	var wander_t := 0
	var prog_pos := Vector2.ZERO
	var prog_t := 0
	var avoid := Vector2.ZERO
	var avoid_t := 0

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
var sky_rain := 0.0        # rain as seen in the sky, eased between biomes
var cam_unwrap := 0.0      # camera angle without the jump at a full turn (for parallax)
var _cam_prev := 0.0
# player settings (saves/settings.json): quality, dithering, pixel size (0 = automatic)
var settings := {"quality": "high", "dither": "off", "pixel": 0, "music": 60, "sound": 80}
var boss_info := Vector4.ZERO
var scale_px := 4
var VW := 480
var VH := 270

# camera
var cam_c := Vector2(0, 1400)
var cam_a := PI / 2
var zoom := 1.0
var test_move := 0           # test mode: walk the local mage this way (-1, 0, 1)
var test_jump := false     # the test mode presses jump
var test_down := false     # ... and down
var view_c := Vector2.ZERO    # the camera as drawn this frame (cam_c with shake, snapped to whole cells)
var ustep := TAU / 8192.0     # unrolled view: radians per screen pixel (one column of the camera's shell)
var view_c_next := Vector2.ZERO   # the camera for the GPU frame being prepared (view_c is the one on screen)
var ustep_next := TAU / 8192.0
var _sub_view_c := Vector2.ZERO
var _sub_ustep := TAU / 8192.0
var _tick_acc := 0.0
var perf_cpu_ms := 0.0      # F3 readout: the game's own time per frame, time waiting for the GPU,
var perf_wait_ms := 0.0     # and ticks run per frame (1 at 60 fps)
var perf_steps := 1.0
var show_perf := false
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
	var down := false          # held: with a jump, drop through the platform you stand on
	var cast := false          # casting the selected spell
	var dig := false           # excavating (held, or a quick tap)
	var decon := false         # deconstructing background tiles (Shift + right mouse)
	var aim := Vector2.ZERO    # world position of the cursor

class Mage extends Body:
	var rig = null             # the simulated hat tip, beard, scarf and staff (overlay.gd, mage_rig.gd)
	var fog := 0.0             # how deep in cloud the mage is (0-1, from the GPU)
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
	var dig_r := 7.5
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
	var cast_frame := -100     # when the last spell was cast (for the cast pose)
	var floating := false      # levitating (for the float pose)
	func _init() -> void:
		h = 17.0
		w = 7.0
		step_h = 5

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
var inv: PackedInt32Array:   # the local mage's satchel (the Forge and HUD read it)
	get: return player.inv
	set(v): player.inv = v
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
var chests: Array = []        # Chest objects on this planet
var doors: Array = []         # {pos, w, h, side, col, row, open}: the doors of this planet's buildings
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
	audio = Audio.new()
	audio.game = self
	add_child(audio)
	gpu = GpuWorld.new()
	_load_settings()
	gpu.apply_quality(settings["quality"])
	_apply_volumes()
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
	# a closer camera since the scale-up: ~216 world rows on a 1080p screen
	scale_px = maxi(2, int(round(s.y / 220.0)))
	if int(settings["pixel"]) > 0:
		scale_px = int(settings["pixel"])
	elif settings["quality"] == "low":
		scale_px += 1   # bigger pixels: fewer of them to simulate light for and draw
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
## The game runs at a fixed 60 ticks a second whatever the frame rate: on a slow frame (a laptop
## on battery, say) it runs two or three ticks before drawing, so the world never slows down; on
## a very fast screen some frames run none. The GPU's work for a frame is collected at the start
## of the next one (see gpu_world.step), so it runs while Godot draws.
func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if gpu == null:
		return
	gpu.flush()
	if gpu.fresh:
		_take_gpu_results()
	var steps := 1
	if state == "play" or state == "dead":
		_tick_acc += minf(delta, 0.1)
		steps = mini(int(floor(_tick_acc * 60.0 + 0.001)), 4)
		_tick_acc = minf(_tick_acc - steps / 60.0, 1.0 / 60.0)
		for k in steps:
			_tick()
	if state == "play" or state == "dead" or state == "forge":
		_gpu_frame(state == "forge", steps)
		ui.update_hud(self)
	ui.update_toasts()
	# performance readout (F3)
	perf_cpu_ms = lerpf(perf_cpu_ms, (Time.get_ticks_usec() - t0 - gpu.wait_us) / 1000.0, 0.1)
	perf_wait_ms = lerpf(perf_wait_ms, gpu.wait_us / 1000.0, 0.1)
	perf_steps = lerpf(perf_steps, float(steps), 0.1)

## Where a mage's collision grid goes: near the mage, but locked to the planet's cell lattice
## (a whole number of radius, a column edge). A grid centred exactly on the mage resampled the
## ground at a slightly different place every time the mage moved a fraction of a cell, so a
## body standing still kept being pushed up and dropping back: the landing jiggle.
func _grid_frame(p: Vector2) -> Array:
	var r := p.length()
	var a := atan2(p.y, p.x)
	var row := int(Defs.R_TOP - r)
	var n: int = Defs.SH_N[0]
	for s in 4:
		if row >= Defs.SH_Y0[s] and row < Defs.SH_Y0[s + 1]:
			n = Defs.SH_N[s]
	var sa := roundf(a / TAU * n) / n * TAU
	return [Vector2(cos(sa), sin(sa)) * roundf(r), sa]

func _gpu_frame(paused: bool, sim_steps := 1) -> void:
	_write_frame_params()
	# simulate around every mage (the local one around the camera) and build each one's grid
	var centers := [cam_c]
	var frames := []
	for k in mini(players.size(), gpu.MAXP):
		var m: Mage = players[k]
		m.slot = k
		if m != player:
			centers.append(m.pos)
		frames.append(_grid_frame(m.pos))
	var t0 := Time.get_ticks_usec()
	_sub_view_c = view_c_next
	_sub_ustep = ustep_next
	gpu.step(centers, frames, brushes.size() > 0 and not paused, false, sim_steps if not paused else 1, false)
	perf_us += Time.get_ticks_usec() - t0
	perf_n += 1
	brushes.clear()
	overlay.queue_redraw()

## The results of the last GPU frame: each mage's collision grid, what the digging collected, and
## the picture (with the camera it was drawn from, so sprites line up with it).
func _take_gpu_results() -> void:
	gpu.fresh = false
	var frames: Array = gpu.sub_frames
	for k in mini(frames.size(), players.size()):
		players[k].grid_g = frames[k][0]
		players[k].grid_a = frames[k][1]
	for m in players:
		_apply_counts(m)
	_use_grid(player)
	_flush_loot()
	view_c = _sub_view_c
	ustep = _sub_ustep
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
	ustep_next = unroll_step(c.length())
	if unrolled():
		# lock the drawn camera to whole cells, so the terrain never shimmers between pixels
		var step := ustep_next
		var ca := roundf(atan2(c.y, c.x) / step) * step
		c = Vector2(cos(ca), sin(ca)) * roundf(c.length())
	view_c_next = c
	if view_c == Vector2.ZERO:
		view_c = c
		ustep = ustep_next
	gpu.setp(1, Vector4(c.x, c.y, atan2(c.y, c.x), zoom))
	gpu.setp(2, Vector4(VW, VH, gpu.LS, mini(lights.size(), 32)))
	var b := _biome_at(atan2(player.pos.y, player.pos.x))
	var wmat := Defs.WATER
	if b["weather"] == "snow":
		wmat = Defs.SNOW
	elif b["weather"] == "ash":
		wmat = Defs.ASH
	# rain fades in and out as you cross between rainy and dry biomes (no sudden grey sky)
	var rr_target := rain if b["weather"] != "clear" else 0.0
	sky_rain += (rr_target - sky_rain) * 0.012
	var rr := sky_rain
	gpu.setp(3, Vector4(rr * 0.0015 if rr > 0.05 else 0.0, wmat, rr, flash))
	gpu.setp(5, Vector4(player.pos.x, player.pos.y, atan2(player.pos.y, player.pos.x), GS))
	gpu.setp(122, Vector4({"off": 0, "subtle": 1, "retro": 2}.get(settings["dither"], 0), gpu.sun_step, ustep_next, 0))
	gpu.setp(6, Vector4(brushes.size(), hurt_flash, player.pos.x, player.pos.y))
	var cr := c.length()
	# the camera's angle, unwrapped (it keeps counting past a full turn) so parallax never jumps
	var ca := atan2(c.y, c.x)
	cam_unwrap += wrapf(ca - _cam_prev, -PI, PI)
	_cam_prev = ca
	gpu.setp(121, Vector4(spawn_angle, time * 0.00004, minf(Defs.R_TOP - 2.0, cr + VH * 0.55 * zoom), cam_unwrap))
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
	m.fog = lerpf(m.fog, cn[58] / 1000.0, 0.25)
	_use_grid(m)
	if m.local and cn[56] > 0:
		# something loose is about to fall: dust trickles from it and the ground rumbles
		var u: int = cn[57] & 0xFFFFFFFF
		var dp := from_grid(Vector2((u & 1023) + 0.5, ((u >> 10) & 1023) + 0.5))
		for k in mini(4, 1 + cn[56] / 15):
			_particle(dp + Vector2(randf() - 0.5, randf() - 0.5) * 5.0, Vector2(randf() - 0.5, randf() - 0.5) * 0.15, 40 + randi() % 30, Color(0.62, 0.57, 0.5), false, 0.04)
		if cn[56] > 20:
			shake = maxf(shake, 1.2)
			if _creak_t <= 0 and dp.distance_to(m.pos) < 70.0:
				ui.toast("Something nearby creaks and shifts…", Color(0.85, 0.75, 0.6), 2.0)
				audio.play("creak", dp)
				_creak_t = 900
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
var _creak_t := 0
var _dig_open_t := 0
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
	audio.play("coin")
	_loot_acc.clear()

## The chests: made when the planet is generated (from the structure plans), saved with the world.
func _make_chests(loaded: bool) -> void:
	chests.clear()
	if loaded and planet_state.has("chests"):
		for e in planet_state["chests"]:
			var c := Chest.new()
			c.pos = Vector2(float(e[0]), float(e[1]))
			c.opened = bool(e[2])
			chests.append(c)
	else:
		for e in builds.chest_list:
			var c2 := Chest.new()
			c2.pos = e["pos"]
			chests.append(c2)

# ------------------------------------------------------------------ doors --
## The doors: planned with the buildings, saved with the world. A closed door is cells (it blocks
## like a wall); an open one is drawn by the overlay, swung into the house.
func _make_doors(loaded: bool) -> void:
	doors.clear()
	if loaded and planet_state.has("doors"):
		for e in planet_state["doors"]:
			doors.append({"pos": Vector2(float(e[0]), float(e[1])), "w": int(e[2]), "h": int(e[3]), "side": int(e[4]),
				"col": int(e[5]), "row": int(e[6]), "open": bool(e[7])})
	else:
		for e in builds.door_list:
			var d: Dictionary = e.duplicate()
			d["open"] = false
			doors.append(d)

## the nearest door to a point, within reach cells of its middle ([] if none)
func _door_near(p: Vector2, reach: float) -> Dictionary:
	var best := {}
	var bd := reach * reach
	for d in doors:
		var dd: float = (d["pos"] as Vector2).distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = d
	return best

## is anyone standing in a door's doorway (closing it would wall them in)?
func _door_blocked(d: Dictionary) -> bool:
	var dp: Vector2 = d["pos"]
	var a := atan2(dp.y, dp.x)
	var bodies: Array = players.duplicate()
	bodies.append_array(enemies)
	for e in bodies:
		if e is Mage and e.dead:
			continue
		var o: Vector2 = e.pos - dp
		if absf(o.dot(basis_r(a))) < float(d["w"]) * 0.5 + e.w * 0.5 + 0.5 and absf(o.dot(basis_d(a))) < float(d["h"]) * 0.5 + e.h * 0.5:
			return true
	return false

func _set_door(d: Dictionary, open: bool) -> void:
	if bool(d["open"]) == open:
		return
	if not open and _door_blocked(d):
		return
	d["open"] = open
	var hw := float(d["w"]) * 0.5
	var hh := float(d["h"]) * 0.5
	# owner slot 3: nobody's satchel (a door brush collects nothing)
	brushes.append([d["pos"], sqrt(hw * hw + hh * hh) + 1.5, 9, 0.0 if open else 1.0, hw, hh, 0.0, 3])
	audio.play("door_open" if open else "door_close", d["pos"])

## walking into a closed door opens it
func _door_bump(m: Mage) -> void:
	var d := _door_near(m.pos, 24.0)
	if not d.is_empty() and not d["open"]:
		_set_door(d, true)

## F: open a chest in reach, otherwise open or close the nearest door
func _interact() -> void:
	if not _chest_in_reach().is_empty():
		_try_open_chest()
		return
	var d := _door_near(player.pos, 22.0)
	if not d.is_empty():
		_set_door(d, not d["open"])

## Chests near a mage obey gravity: one rigid object, so it falls and lands whole. A chest
## resting on something stays exactly where it is (the collision grid is built around the mage,
## so re-checking a resting chest every frame made it bob as you walked); it only moves again
## once nothing is under it.
const CHEST_VANISH := 110      # an opened chest shows its empty inside, then fades away in sparkles
func _update_chests() -> void:
	for k in range(chests.size() - 1, -1, -1):
		var c: Chest = chests[k]
		if c.open_t >= 0:
			c.open_t += 1
			if c.open_t > 50 and c.open_t % 3 == 0:
				var sp := Vector2(randf() - 0.5, randf() - 0.5) * Vector2(c.w, c.h)
				_particle(c.pos + sp, Vector2((randf() - 0.5) * 0.4, -0.4 - randf() * 0.8), 40 + randi() % 30, Color(1.0, 0.85, 0.4), true, -0.005)
			if c.open_t >= CHEST_VANISH:
				for n in 24:
					_particle(c.pos, Vector2(randf() - 0.5, randf() - 0.5).normalized() * (0.6 + randf() * 1.2), 30 + randi() % 30, Color(1.0, 0.9, 0.5), true, 0.0)
				lights.append([c.pos, 24.0, Color(1.2, 0.95, 0.5)])
				audio.play("chest_vanish", c.pos)
				chests.remove_at(k)
				continue
		var near := _nearest_mage(c.pos)
		if c.pos.distance_squared_to(near.pos) > 250.0 * 250.0:
			continue
		_use_grid(near)
		if not in_grid(c.pos, 16.0):
			continue
		var l := to_grid(c.pos)
		if c.on_ground and box_solid(l.x - c.w * 0.5, l.y - c.h * 0.5 + 1.5, c.w, c.h):
			c.vy = 0.0           # still something under it: it stays put
			continue
		c.vx *= 0.8
		c.vy = minf(c.vy + 0.17 * gravity_at(c.pos), 6.0)
		move_body(c)
	_use_grid(player)

## The nearest closed chest to the local mage. Returns [chest, distance squared] or [].
func _nearest_chest() -> Array:
	var best = null
	var bd := 1e18
	for c in chests:
		if c.opened:
			continue
		var d2: float = (c.pos as Vector2).distance_squared_to(player.pos)
		if d2 < bd:
			bd = d2
			best = c
	return [] if best == null else [best, bd]

## A chest you can open: close by (within CHEST_REACH cells of the mage's middle) and in plain
## sight, with nothing solid in between (so not through a wall you can't dig yet).
const CHEST_REACH := 20
func _chest_in_reach() -> Array:
	var nc := _nearest_chest()
	if nc.is_empty() or float(nc[1]) > CHEST_REACH * CHEST_REACH:
		return []
	_use_grid(player)
	var a := to_grid(player.pos)
	var b := to_grid(nc[0].pos)
	var n := int(ceil(a.distance_to(b) * 2.0))
	for k in range(1, n):
		var q := a.lerp(b, float(k) / n)
		if gsolid(int(floor(q.x)), int(floor(q.y))):
			return []
	return nc

func _try_open_chest() -> void:
	var nc := _chest_in_reach()
	if nc.is_empty():
		return
	var c: Chest = nc[0]
	var centre: Vector2 = c.pos
	var place := region_name()
	var dungeon := "Halls" in place or "Crypts" in place or "Tomb" in place
	var ruin := place.begins_with("Ruin") or place.begins_with("Forgotten") or place.begins_with("Buried") \
		or place.begins_with("Collapsed") or place.begins_with("Sunken") or dungeon
	if ruin and randf() < 0.15:
		# not a chest at all
		chests.erase(c)
		audio.play("mimic", centre)
		# a mimic is wider than its chest: make room for it right where the chest was
		var m: Enemy = spawn_enemy("mimic", free_spot(centre, 16.0, 9.0, 14))
		m.vy = -2.5
		m.t = 20
		shake = maxf(shake, 6.0)
		ui.toast("The chest bares its teeth: a MIMIC!", Color(1, 0.4, 0.35), 4.0)
		return
	var rare := 0.15
	if "Reliquary" in place:
		rare = 0.7
	elif "Castle" in place or "Vault" in place:
		rare = 0.55
	elif dungeon:
		rare = 0.4
	elif "Temple" in place or "Catacombs" in place:
		rare = 0.4
	elif "Watchtower" in place or "Mine" in place:
		rare = 0.25
	c.opened = true
	c.open_t = 0
	audio.play("chest_open", centre)
	_roll_loot(7, 1.6)
	_rare_find(rare)
	for k in 14:
		_particle(centre, Vector2(randf() - 0.5, -randf() * 1.2), 30 + randi() % 20, Color(1, 0.85, 0.35), true, 0.02)
	lights.append([centre, 30.0, Color(1.2, 0.9, 0.4)])

## Digging at a chest opens it (the same as pressing F): is this dig point on a closed chest?
func _dig_hits_chest(p: Vector2, rad: float) -> bool:
	for c in chests:
		if c.opened:
			continue
		var d: Vector2 = (c.pos as Vector2) - p
		if absf(d.x) < c.w * 0.5 + rad and absf(d.y) < c.w * 0.5 + rad and d.length() < c.w * 0.5 + rad:
			return true
	return false

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
	audio.play("rare")
	save_game()

func _check_chest_hint() -> void:
	_creak_t -= 1
	_dig_open_t -= 1
	_hint_t -= 1
	if _hint_t > 0 or frame % 20 != 0:
		return
	var nc := _chest_in_reach()
	if not nc.is_empty():
		ui.toast("Press F to open the chest", Color(1.0, 0.9, 0.55), 2.5)
		_hint_t = 900

# ------------------------------------------------------------- guardians ---
## Foes placed by the structure generator wait inside castles, catacombs, temples and mines.
## They appear when you come near, and stay dead once killed.
var _guards_alive := {}
func _update_guards() -> void:
	if builds == null or frame % 8 != 0 or dead:
		return
	var slain: Array = planet_state.get("slain", [])
	for gi in builds.guards.size():
		if _guards_alive.has(gi) or slain.has(gi):
			continue
		var gd: Dictionary = builds.guards[gi]
		var gp: Vector2 = gd["pos"]
		var near := _nearest_mage(gp)
		_use_grid(near)
		# they come out while still out of sight (the view reaches about 192 cells to each side;
		# the collision grid a little further), so nobody pops up on screen
		if gp.distance_to(near.pos) > 232.0 or not in_grid(gp, 8.0):
			_use_grid(player)
			continue
		# its post may be buried under rubble or a fallen floor: stand on top of whatever is
		# there now, or don't come out at all (never inside the rock)
		var d: Dictionary = Defs.ENEMY[gd["type"]]
		var l := to_grid(gp)
		var spot := Vector2(-1.0, -1.0)
		for up in 40:
			if not box_solid(l.x - float(d["w"]) * 0.5, l.y - up - float(d["h"]) * 0.5, d["w"], d["h"]):
				spot = Vector2(l.x, l.y - up)
				break
		if spot.x < 0.0:
			_use_grid(player)
			continue
		gp = from_grid(spot)
		_use_grid(player)
		var e: Enemy = spawn_enemy(gd["type"], gp)
		e.guard_id = gi
		_guards_alive[gi] = true

# ============================================================ coordinates ==
func basis_r(a: float) -> Vector2:
	return Vector2(sin(a), -cos(a))

func basis_d(a: float) -> Vector2:
	return Vector2(-cos(a), -sin(a))

## The view near the surface is unrolled (see screenToWorld in shaders/inc/params.comp): x follows
## the angle (one pixel = one surface column), y the height, so buildings stand straight anywhere
## on screen. Zoomed out to the map, the planet is drawn round.
## The unrolled view draws one column of the camera's own shell per pixel, so the cells around
## you are always one pixel wide (deep down the shells have fewer, wider columns: drawing surface
## columns there stretched every cell and made you seem to run faster and faster toward the core).
## Near a shell boundary the scale eases from one shell's to the next over 48 rows.
func unroll_step(r: float) -> float:
	var row := Defs.R_TOP - r
	var s := 0
	for k in 4:
		if row >= Defs.SH_Y0[k]:
			s = k
	var st := TAU / float(Defs.SH_N[s])
	# blend toward the neighbouring shell near its boundary
	if s < 3:
		var dn: float = float(Defs.SH_Y0[s + 1]) - row
		if dn < 24.0:
			var t := smoothstep(24.0, -24.0, dn)
			st = exp(lerpf(log(st), log(TAU / float(Defs.SH_N[s + 1])), t))
	if s > 0:
		var up: float = row - float(Defs.SH_Y0[s])
		if up < 24.0:
			var t2 := smoothstep(24.0, -24.0, up)
			st = exp(lerpf(log(st), log(TAU / float(Defs.SH_N[s - 1])), t2))
	return st

func unrolled() -> bool:
	return zoom < 2.5

func _view() -> Vector2:
	return cam_c if view_c == Vector2.ZERO else view_c

func world_to_screen(p: Vector2) -> Vector2:
	var c := _view()
	var a := atan2(c.y, c.x)
	if unrolled():
		var d := wrapf(atan2(p.y, p.x) - a, -PI, PI)
		return Vector2(-d / ustep, c.length() - p.length()) / zoom + Vector2(VW, VH) * 0.5
	var o := p - c
	return Vector2(o.dot(basis_r(a)), o.dot(basis_d(a))) / zoom + Vector2(VW, VH) * 0.5

func screen_to_world(px: Vector2) -> Vector2:
	var c := _view()
	var a := atan2(c.y, c.x)
	var o := (px - Vector2(VW, VH) * 0.5) * zoom
	if unrolled():
		var th := a - o.x * ustep
		return Vector2(cos(th), sin(th)) * (c.length() - o.y)
	return c + basis_r(a) * o.x + basis_d(a) * o.y

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
	var t := gtype(ix, iy)
	if t == Defs.TREASURE or t == Defs.SCAFFOLD:
		return false      # chests are furniture: you walk (and enemies walk) through them;
		                  # platforms only hold you from above (see platform_below)
	var k: int = Defs.KIND[t]
	return k == Defs.K_SOLID or k == Defs.K_POWDER

func type_at(p: Vector2) -> int:
	var l := to_grid(p)
	return gtype(int(floor(l.x)), int(floor(l.y)))

## The nearest spot (searching outward, upward first) where a w x h body centred at p fits, in
## world coordinates; p itself if nothing within `reach` cells is free.
func free_spot(p: Vector2, w: float, h: float, reach: int) -> Vector2:
	var l := to_grid(p)
	if not box_solid(l.x - w * 0.5, l.y - h * 0.5, w, h):
		return p
	for rr in range(1, reach + 1):
		for dy in range(-rr, rr + 1):
			for sx in [1, -1]:
				var dx: int = (rr - absi(dy)) * sx
				# upward offsets first (dy negative is up)
				var q := Vector2(l.x + dx, l.y + dy)
				if not box_solid(q.x - w * 0.5, q.y - h * 0.5, w, h):
					return from_grid(q)
	return p

## Does a body w wide whose bottom edge moves down from y_from to y_to cross the top of a
## one-way platform cell (a scaffold row it wasn't already in)?
func platform_below(x: float, y_from: float, y_to: float, w: float) -> bool:
	var r := int(floor(y_to - 0.0001))
	if float(r) < y_from - 0.0001:
		return false          # the bottom was already inside that row: it came from below
	var x0 := int(floor(x))
	var x1 := int(floor(x + w - 0.001))
	for xx in range(x0, x1 + 1):
		if gtype(xx, r) == Defs.SCAFFOLD:
			return true
	return false

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
				if e is Mage and box_count(x + st, y, e.w, e.h, Defs.WOODDOOR) > 0:
					_door_bump(e as Mage)
				break
		dx -= st
	e.on_ground = false
	e.on_platform = false
	if e.drop_t > 0:
		e.drop_t -= 1
	# vertical: when the head clips a corner, slide around it instead of stopping
	var dy := e.vy
	while absf(dy) > 0.000001:
		var st2 := 0.5 * signf(dy) if absf(dy) > 0.5 else dy
		if st2 > 0 and e.drop_t <= 0 and platform_below(x, y + e.h, y + e.h + st2, e.w):
			# landing on a one-way platform from above
			y = floorf(y + e.h + st2 - 0.0001) - e.h
			e.on_ground = true
			e.on_platform = true
			e.vy = 0.0
			break
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
	if not e.on_ground and e.vy >= 0 and e.drop_t <= 0 and platform_below(x, y + e.h - 0.05, y + e.h + 0.6, e.w):
		e.on_ground = true
		e.on_platform = true
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
			if e is Mage:
				y -= 1.0          # the mage always works its way out
			else:
				e.stuck += 1      # a foe stays put (it used to rise up through the rock)
	else:
		e.stuck = 0
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
	if test_move != 0:
		inp.move = test_move    # the test mode walks the mage
	inp.jump = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)
	inp.down = Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)
	if test_jump:
		inp.jump = true
	if test_down:
		inp.down = true
	var can_act: bool = not ui.mouse_over_ui() and state == "play"
	inp.cast = can_act and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or m.dig_tap > 0
	var shift := Input.is_key_pressed(KEY_SHIFT)
	inp.dig = can_act and rmb and not shift
	inp.decon = can_act and rmb and shift

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
			if m.input.decon:
				_deconstruct(m, m.input.aim)
		if m.dig_tap > 0:
			m.dig_tap -= 1
	_use_grid(player)
	_update_enemies()
	_update_chests()
	_use_grid(player)
	_update_projectiles()
	_use_grid(player)
	_update_particles()
	_update_weather()
	_try_spawn()
	_update_guards()
	_check_chest_hint()
	_update_wisp()
	_cloud_wisps()
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
	var speed := 0.9 if p.in_liquid else 1.5
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
	if m.jump_buf > 0 and m.input.down and p.on_platform:
		# down + jump on a platform: drop through it
		m.jump_buf = 0
		p.drop_t = 12
		p.on_ground = false
		p.vy = maxf(p.vy, 1.0)
	if m.jump_buf > 0:
		m.jump_buf -= 1
		if (m.ground_t <= 6 or p.in_liquid) and p.vy > -1.0:
			p.vy = -2.3 if p.in_liquid else (-4.6 if m.items.has("boots") else -3.9)
			m.jump_buf = 0
			audio.play("jump", m.pos, 0.6)
			m.ground_t = 99
			m.air_time = 0
	m.jump_held = jump
	m.floating = jump and not p.on_ground and not p.in_liquid and m.air_time > 10 and m.mana > 0.5
	if m.floating:
		audio.play("levitate", p.pos, 0.35)
		p.vy -= g + 0.28
		p.vy = maxf(p.vy, -2.5)
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
	p.vy = minf(p.vy, 6.0)
	var was_air := m.air_time
	var a0 := p.anim
	move_body(p)
	if p.on_ground:
		p.anim += absf(p.vx) * 0.13
		if int(p.anim * 0.5) != int(a0 * 0.5):
			audio.play("step", p.pos, 0.35)
		if was_air > 18:
			audio.play("land", p.pos, clampf(was_air / 60.0, 0.3, 1.0))
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
		if hit:
			audio.play("hurt", m.pos)
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
	var hand := m.pos + basis_r(a) * (m.facing * 6.0) + basis_d(a) * (-0.5)   # the hand in the sprite
	var dir := (aim - hand).normalized()
	if dir == Vector2.ZERO:
		dir = basis_r(a)
	return [hand + dir * 10.0, dir, hand]

func _cast(m: Mage, id: String, aim: Vector2) -> void:
	var s: Dictionary = Defs.SPELLS[id]
	if m.cast_cd > 0 or m.mana < float(s["mana"]):
		return
	m.cast_frame = frame
	if id == "conjure":
		_conjure(m, aim)
		m.cast_cd = s["cd"]
		return
	if id == "blink":
		if _blink(m, aim):
			audio.play("blink", m.pos)
			m.mana -= float(s["mana"])
			m.cast_cd = s["cd"]
		return
	m.mana -= float(s["mana"])
	m.cast_cd = s["cd"]
	var snd := {"spark": "spark", "fireball": "fire", "tide": "water", "frost": "frost", "quake": "boom", "starfall": "rare"}
	audio.play(snd.get(id, "spark"), m.pos, 0.8)
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
	audio.play("dig", p, 0.7)
	if m.local and _dig_open_t <= 0 and _dig_hits_chest(p, m.dig_r):
		_dig_open_t = 30
		_try_open_chest()
	brushes.append([p, m.dig_r, 1, 0, m.tier, 0, 0, m.slot])
	lights.append([p, 10.0, Color(0.4, 0.8, 0.5)])

## Shift + right mouse: take background tiles (a building's back walls, furniture, plants). It is how
## you clear a wall on purpose; plain right-click never touches a building's walls.
func _deconstruct(m: Mage, aim: Vector2) -> void:
	var p := _reach(m, aim)
	brushes.append([p, m.dig_r * 0.8, 8, 0, m.tier, 0, 0, m.slot])
	lights.append([p, 10.0, Color(0.9, 0.6, 0.3)])

func _conjure(m: Mage, aim: Vector2) -> void:
	if m.mat <= 0 or m.inv[m.mat] <= 0:
		return
	var p := _reach(m, aim)
	var budget := mini(m.inv[m.mat], 14)
	m.pending_place = budget
	brushes.append([p, 2.6, 5, m.mat, 0, budget, 9.0, m.slot])
	audio.play("place", p, 0.6)

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
				if (Defs.KIND[t] == Defs.K_SOLID or Defs.KIND[t] == Defs.K_POWDER) and t != Defs.TREASURE:
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
				brushes.append([p, 2.4, 6, 0, tier, 0, 0])
		"fireball":
			_explode(p, 10.0, maxi(1, tier), 1, 38.0)
		"quake":
			_explode(p, 22.0, mini(3, tier + 1), 2, 70.0)
		"starfall":
			_explode(p, 17.0, maxi(2, tier), 1, 80.0)
		"tide":
			brushes.append([p, 8.0, 3, Defs.WATER, 0, 0, 0])
			if e != null:
				_hurt_enemy(e, pd["dmg"], kb * 2.0, -1.0)
		"frost":
			brushes.append([p, 10.0, 4, 0, 0, 0, 0])
			for en in enemies:
				if en.pos.distance_to(p) < 13.0:
					en.slow = 200
			if e != null:
				_hurt_enemy(e, pd["dmg"], kb, 0.0)
		"efire":
			if hit_m != null:
				hurt(hit_m, float(pd["dmg"]) * (0.6 if hit_m.heat_ward else 1.0), Vector2(signf(randf() - 0.5) * 1.5, -1.0), true)
			else:
				brushes.append([p, 1.8, 3, Defs.FIRE, 0, 0, 0])
	var col: Color = Defs.SPELLS[type]["color"] if Defs.SPELLS.has(type) else Color(1, 0.35, 0.12)
	for k in 10:
		_particle(p, Vector2(randf() - 0.5, randf() - 0.8) * 1.5, 14 + randi() % 10, col, true, 0.05)

func _explode(p: Vector2, r: float, power: int, kind: int, dmg: float) -> void:
	brushes.append([p, r, 2, kind, power, 0, 0])
	audio.play("boom", p, clampf(r / 14.0, 0.4, 1.2), 1.3 - clampf(r / 40.0, 0.0, 0.5))
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
	e.home = p
	enemies.append(e)
	return e

func _hurt_enemy(e: Enemy, dmg: float, kx: float, ky: float) -> void:
	e.hp -= dmg
	e.flash = 6
	audio.play("hit", e.pos, 0.7)
	if not e.boss:
		e.vx += kx
		e.vy += ky
	e.awake = true
	if e.hp <= 0 and not e.dead:
		_kill_enemy(e)

func _kill_enemy(e: Enemy) -> void:
	e.dead = true
	audio.play("foe_die", e.pos)
	if e.guard_id >= 0:
		var slain: Array = planet_state.get("slain", [])
		if not slain.has(e.guard_id):
			slain.append(e.guard_id)
		planet_state["slain"] = slain
	if e.type == "mimic":
		_rare_find(0.6)
	# it bursts apart in its own colours (bones, slime, embers...), with a puff of sparks
	var spr: Dictionary = Defs.SPRITES.get(e.d["spr"], {})
	var cols := []
	if spr.has("pal"):
		for ck in spr["pal"]:
			cols.append(Color(spr["pal"][ck]))
	for k in (120 if e.boss else 34):
		var c: Color = cols[randi() % cols.size()] if not cols.is_empty() and k % 3 != 0 else Color(1, 0.7, 0.3)
		var off := Vector2(randf() - 0.5, randf() - 0.5) * Vector2(e.w, e.h)
		_particle(e.pos + off, (Vector2(randf() - 0.5, -randf() * 0.9) * 2.4) + off * 0.06, 35 + randi() % 35, c, k % 3 == 0, 0.08)
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

## How high a walker must climb to get past the wall in front of it (cells), or -1 if it is
## taller than `reach`. Uses the collision grid currently in use.
func _wall_height(e: Enemy, dir: float, reach: float) -> int:
	var l := to_grid(e.pos)
	var x := l.x - e.w * 0.5 + dir * 2.0
	for up in range(0, int(reach) + 1):
		if not box_solid(x, l.y - e.h * 0.5 - up, e.w, e.h):
			return up
	return -1

## Walk toward the target (dx > 0: to the right). Jumps exactly as high as a wall needs when it
## can clear it; turns round and wanders for a while when it can't, or when it stops making
## progress. jump_v: its strongest jump. Returns the direction it is heading.
func _walker_nav(e: Enemy, dx: float, dist: float, speed: float, jump_v: float, g: float) -> float:
	if e.wander_t > 0:
		e.wander_t -= 1
	else:
		e.nav_dir = signf(dx) if absf(dx) > 1.0 else e.nav_dir
	# a second without getting any closer while chasing: try another way for a bit
	e.prog_t += 1
	if e.prog_t >= 60:
		if e.wander_t <= 0 and dist > 30.0 and e.prog_pos.distance_to(e.pos) < 4.0:
			e.nav_dir = -e.nav_dir
			e.wander_t = 80 + randi() % 80
		e.prog_pos = e.pos
		e.prog_t = 0
	if e.hit_wall and e.on_ground:
		var reach := jump_v * jump_v / (2.0 * maxf(g, 0.01)) - 2.0
		var need := _wall_height(e, e.nav_dir, reach)
		if need >= 0:
			e.vy = -minf(jump_v, sqrt(2.0 * g * (need + 4.0)))
		else:
			e.nav_dir = -e.nav_dir
			e.wander_t = 90 + randi() % 90
	return e.nav_dir

## Steer a flier toward `want` (local frame, x right, y down), around anything solid ahead:
## it looks ~12 cells along its way and, if that's blocked, takes the nearest open heading
## (over the top first) for a short while.
func _flier_steer(e: Enemy, want: Vector2) -> Vector2:
	if e.avoid_t > 0:
		e.avoid_t -= 1
		return e.avoid
	var w := want.normalized() if want.length() > 0.001 else Vector2(e.nav_dir, 0.0)
	var l := to_grid(e.pos)
	if not box_solid(l.x - e.w * 0.5 + w.x * 12.0, l.y - e.h * 0.5 + w.y * 12.0, e.w, e.h):
		return w
	for ang in [-0.8, 0.8, -1.6, 1.6, -2.4, 2.4]:
		var tw := w.rotated(ang)
		if not box_solid(l.x - e.w * 0.5 + tw.x * 12.0, l.y - e.h * 0.5 + tw.y * 12.0, e.w, e.h):
			e.avoid = tw
			e.avoid_t = 25
			return tw
	e.avoid = -w
	e.avoid_t = 30
	return -w

func _update_enemies() -> void:
	for k in range(enemies.size() - 1, -1, -1):
		var e: Enemy = enemies[k]
		if e.dead:
			enemies.remove_at(k)
			continue
		var tgt := _nearest_mage(e.pos)
		_use_grid(tgt)
		var dist := e.pos.distance_to(tgt.pos)
		if e.boss:
			# a boss nobody is fighting recovers: after a few seconds alone it is back at full
			# health, asleep where it started, so it has to be beaten in one fight
			if dist > 230.0 or tgt.dead:
				e.leash_t += 1
				if e.leash_t > 150 and (e.hp < e.max_hp or e.awake):
					e.hp = e.max_hp
					e.awake = false
					e.leaping = false
					e.pos = e.home
					e.vx = 0.0
					e.vy = 0.0
			else:
				e.leash_t = 0
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
					if e.t <= 0 and dist < 200:
						var sd := _walker_nav(e, dx, dist, 0.0, 5.4, g)
						e.vx = sd * (1.4 + randf() * 0.9) * slow_f
						var hop := 3.8 + randf() * 1.3
						var wall := _wall_height(e, sd, 56.0)
						if wall > 0:
							hop = minf(5.4, sqrt(2.0 * g * (wall + 5.0)))   # hop up onto the ledge
						elif wall < 0:
							e.nav_dir = -sd
							e.wander_t = 90
						e.vy = -hop
						e.t = 45 + randf() * 50
				e.vy += g * 0.3 if e.in_liquid else g
				if e.in_liquid:
					e.vy *= 0.9
			"skeleton":
				# walks toward you once it notices you, hops over steps and rubble
				if dist < 210 and not tgt.dead:
					var kd := _walker_nav(e, dx, dist, 0.85, 3.9, g)
					if e.on_ground:
						e.vx += (kd * 0.85 * slow_f - e.vx) * 0.2
				elif e.on_ground:
					e.vx *= 0.8
				e.vy += g * 0.3 if e.in_liquid else g
			"mimic":
				if e.on_ground:
					e.vx *= 0.7
					e.t -= 1
					if e.t <= 0 and not tgt.dead:
						var md := _walker_nav(e, dx, dist, 0.0, 4.6, g)
						e.vx = md * (1.9 + randf() * 0.8) * slow_f
						var mw := _wall_height(e, md, 40.0)
						e.vy = -(minf(4.6, sqrt(2.0 * g * (mw + 5.0))) if mw > 0 else 3.7 + randf() * 0.8)
						e.t = 28 + randf() * 25
				e.vy += g
			"bat":
				e.phase += 0.12
				if dist < 200:
					var bw := _flier_steer(e, Vector2(dx, dy + sin(e.phase) * 14.0))
					e.vx += bw.x * 0.12
					e.vy += bw.y * 0.11
				else:
					e.vx += (randf() - 0.5) * 0.1
					e.vy += (randf() - 0.5) * 0.1
				var sp := 1.6 * slow_f
				e.vx = clampf(e.vx, -sp, sp)
				e.vy = clampf(e.vy, -sp, sp)
				if e.hit_wall:
					e.vy -= 0.3
			"imp":
				e.phase += 0.05
				var ax := signf(dx) if dist > 45 else -signf(dx)
				var iw := _flier_steer(e, Vector2(ax * maxf(absf(dx), 10.0), dy - 20.0 + sin(e.phase) * 10.0))
				e.vx += iw.x * 0.05
				e.vy += iw.y * 0.05
				var sp2 := 1.0 * slow_f
				e.vx = clampf(e.vx, -sp2, sp2)
				e.vy = clampf(e.vy, -sp2, sp2)
				e.shoot_t -= 1
				if e.shoot_t <= 0 and dist < 190 and not tgt.dead:
					_spawn_proj("efire", e.pos, (player.pos - e.pos).normalized() * 1.7, "enemy")
					e.shoot_t = 140 + randf() * 60
			"golem":
				if not e.awake and dist < 150:
					e.awake = true
					ui.toast("VULKHAR, THE EMBER GOLEM awakens!", Color(1, 0.48, 0.16), 4.0)
					audio.play("roar", e.pos, 1.2)
					shake = 10.0
				if e.awake and not tgt.dead:
					var enraged := e.hp < e.max_hp * 0.4
					var gd2 := _walker_nav(e, dx, dist, 0.5, 5.2, g)
					if e.on_ground:
						e.vx += (gd2 * (0.75 if enraged else 0.5) * slow_f - e.vx) * 0.1
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
						e.vy = -5.2
						e.vx = signf(dx) * 2.0
						e.t = 160 if enraged else 260
						e.leaping = true
					if e.leaping and e.on_ground and e.vy == 0:
						e.leaping = false
						shake = 12.0
						_explode(e.pos - basis_d(atan2(e.pos.y, e.pos.x)) * (-e.h * 0.5 - 1.0), 8.0, 1, 0, 0.0)
						if absf(dx) < 38 and absf(dy) < 28:
							hurt(tgt, 18.0, Vector2(signf(dx) * 3.0, -2.0), true)
				e.vy += g
		if e.d["fly"]:
			e.vy *= 0.98
		elif e.vy > 6.0:
			e.vy = 6.0
		move_body(e)
		e.anim += absf(e.vx) * 0.2 + 0.02
		if e.stuck > 30 and (e.type == "mimic" or e.guard_id >= 0):
			# mimics and guards are placed on purpose: work them free instead of losing them
			e.pos = free_spot(e.pos, e.w, e.h, 16)
			e.stuck = 0
		if e.stuck > 30 and not e.boss:
			# wedged in the ground (buried by rubble, a cave-in): it's gone
			if e.guard_id >= 0:
				_guards_alive.erase(e.guard_id)
			enemies.remove_at(k)
			continue
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
	# Foes come in from out of sight, never popping up (or dropping in) on screen. How far the
	# view reaches from the mage, in world cells (a screen pixel is ustep * r cells across):
	var reach_x := VW * 0.5 * zoom * maxf(1.0, ustep * r) + float(d["w"]) + 10.0
	var reach_y := VH * 0.5 * zoom + float(d["h"]) + 10.0
	var cv := _view()
	var ca := atan2(cv.y, cv.x)
	if type == "slime":
		# on the ground just past the edge of the view (it waits, still, until you come near)
		for tries in 6:
			var side := -1.0 if randf() < 0.5 else 1.0
			var dist := reach_x + randf_range(4.0, 60.0)
			var ga := ca + side * dist / maxf(sa.x, 1.0)
			var gs: Vector4 = gpu.surf_at(ga)
			if gpu.surf_b(ga).y > gs.x:
				continue                      # under the sea
			var gp := Vector2(cos(ga), sin(ga)) * (gs.x + float(d["h"]) * 0.5 + 1.0)
			if absf((gp - player.pos).dot(basis_d(a))) > 80.0:
				continue                      # a cliff far above or below: not where you'd meet it
			spawn_enemy(type, gp)
			return
		return
	# underground: in open cave space inside the simulated area, but outside the view
	_use_grid(player)
	var l0 := to_grid(cv)
	for tries in 16:
		var lx := HALF + (randf() * 2.0 - 1.0) * (HALF - 14.0)
		var ly := HALF + (randf() * 2.0 - 1.0) * (HALF - 14.0)
		if absf(lx - l0.x) < reach_x and absf(ly - l0.y) < reach_y:
			continue                          # it would appear on screen
		if not box_solid(lx - d["w"] * 0.5, ly - d["h"] * 0.5, d["w"], d["h"]) and Defs.KIND[gtype(int(lx), int(ly))] != Defs.K_LIQUID:
			spawn_enemy(type, from_grid(Vector2(lx, ly)))
			return

## Inside a cloud: wisps of vapour stream past you with the wind, in front of everything.
func _cloud_wisps() -> void:
	if player.fog < 0.08:
		return
	var a := atan2(player.pos.y, player.pos.x)
	var R := basis_r(a)
	var D := basis_d(a)
	for k in int(1 + player.fog * 4.0):
		var off := R * randf_range(-VW * 0.6, VW * 0.6) + D * randf_range(-VH * 0.6, VH * 0.6)
		var shade := randf_range(0.82, 1.0)
		_particle(player.pos + off, -R * randf_range(0.25, 0.7) + D * randf_range(-0.05, 0.05), 50 + randi() % 50,
			Color(shade, shade, shade * 1.04, 0.35 + player.fog * 0.3), true, 0.0)

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
	var target := player.pos + basis_r(a) * (-player.facing * 11.0) - basis_d(a) * (17.0 + sin(wisp_t * 2.0) * 3.0)
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
		"wide": return dig_r >= 11.0
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
	audio.play("forge")
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
		"wide": dig_r = 11.0
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
		if k == KEY_ESCAPE and state == "play":
			ui.toggle_settings()
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
			_interact()
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
		elif k == KEY_F3:
			show_perf = not show_perf
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
		dig_r = 7.5
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
	boss_info = Vector4(boss_a, mag - 6.0, 100.0, 42.0)
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
		gpu.settle(builds.settle, 0.0, 150)
		print("[Wisp Forge] %s: %d structures" % [planet["name"], builds.structs.size()])
		builds.structs.clear()
	_make_chests(loaded)
	_make_doors(loaded)
	enemies.clear()
	_guards_alive.clear()
	projs.clear()
	parts.clear()
	var bd := Vector2(cos(boss_a), sin(boss_a))
	if not planet_state.get("boss_dead", false):
		spawn_enemy("golem", bd * (boss_info.y - boss_info.w + float(Defs.ENEMY["golem"]["h"]) * 0.5 + 2.0))
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
const GEN_VERSION := 22            # bump when the structure generator changes; older planets regenerate
const WORLD_MAGIC := 0x57465732   # "WFW2": foreground cells, then the background layer
var planet_state := {}            # per-planet facts saved with the world (boss defeated, where you were)
var _save_task := -1

## ---- settings ----
func _load_settings() -> void:
	var path := _real_save_dir().path_join("settings.json")
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(d) == TYPE_DICTIONARY:
			for k in settings:
				if d.has(k):
					settings[k] = d[k]
	settings["pixel"] = int(settings["pixel"])   # JSON numbers come back as floats
	settings["music"] = int(settings["music"])
	settings["sound"] = int(settings["sound"])

func set_setting(key: String, value) -> void:
	settings[key] = value
	var f := FileAccess.open(_real_save_dir().path_join("settings.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	if key == "quality":
		gpu.apply_quality(value)
	if key == "quality" or key == "pixel":
		_layout()
	_apply_volumes()

func _apply_volumes() -> void:
	if audio:
		audio.music_volume = float(settings["music"]) / 100.0
		audio.sfx_volume = float(settings["sound"]) / 100.0

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
	# saves from before the scale-up stored 4.5 / 7.0; the mage is bigger now (7.5 / 11)
	var sd := float(s.get("dig_r", 7.5))
	dig_r = 11.0 if sd >= 7.0 else 7.5
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
	var cs := []
	for c in chests:
		cs.append([c.pos.x, c.pos.y, c.opened])
	planet_state["chests"] = cs
	var ds := []
	for d in doors:
		ds.append([d["pos"].x, d["pos"].y, d["w"], d["h"], d["side"], d["col"], d["row"], d["open"]])
	planet_state["doors"] = ds
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
