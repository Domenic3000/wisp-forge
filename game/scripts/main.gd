extends Node2D
## Wisp Forge (Godot) — main game: frame loop, player, enemies, spells,
## crafting, weather, saving and planet travel. The world itself lives on the
## GPU (gpu_world.gd); this script reads back a collision grid around the
## player every frame and sends "brushes" (dig / explode / place) to the GPU.

const GpuWorld := preload("res://scripts/gpu_world.gd")
const UI := preload("res://scripts/ui.gd")
const Overlay := preload("res://scripts/overlay.gd")
const Space := preload("res://scripts/space.gd")
const BossAI := preload("res://scripts/boss_ai.gd")
const BossArt := preload("res://scripts/boss_art.gd")
const Skiff := preload("res://scripts/skiff.gd")
const Buildings := preload("res://scripts/buildings.gd")
const Build := preload("res://scripts/build.gd")
const FoeAI := preload("res://scripts/foe_ai.gd")
const Chunks := preload("res://scripts/chunks.gd")
# (the test script is loaded only in test mode, at run time: if it fails to load, the game says so
# and quits instead of failing to load itself and leaving a blank window open)
const Audio := preload("res://scripts/audio.gd")
var audio

const DAY_LEN := 60.0 * 7.0 * 60.0   # frames per day (7 minutes)
const REACH := 64.0
const ROCK_HURT_FALL := 8      # a falling block hurts only after falling this many cells
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
	var unsup_t := 0          # frames in a row with nothing found under it
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
	# what it knows and what it's doing (scripts/foe_ai.gd)
	var see := false           # it can see its target right now
	var look_t := 0            # frames until it looks again
	var alert_t := 0           # frames it keeps hunting
	var seen_pos := Vector2.ZERO
	var act := ""              # "", "windup", "strike", "air", "dive", "recover"
	var act_t := 0
	var act_len := 1           # how long this wind-up lasts (for its glow)
	var act_cd := 0            # frames until it may attack again
	var hit_done := false      # this cut already landed
	var aim := Vector2.ZERO    # a bat's dive heading
	var blink_cd := 0
	var door_t := 0            # frames waiting for a door it opened to swing out of the way
	# a biome guardian (scripts/boss_ai.gd)
	var move := ""             # the move under way ("charge", "spit2"...)
	var mi := -1               # (which move came last)
	var moves_done := 0
	var spot := Vector2.ZERO   # where the move aims (the ground under you, for an eruption)
	var raged := false         # below half health
	var raged_burst := false
	var under := false         # a burrower under the ground: unseen, untouchable, not moved by move_body
	var gvel := Vector2.ZERO   # (its flight out of the ground, in world units)
	var trail := PackedVector2Array()   # a serpent's segments, head first
	var summoner = null        # the guardian that called it
	var tether := 0.0          # how far along the ground from its lair's middle it may go (0: anywhere)
	var ceil := 60.0           # how high above where it waits it may fly
	var pace := 0.0            # where round you it's heading (cells along the ground from you)
	var pace_t := 0
	var smash_f := -100        # (the frame it last smashed through something)
	# getting to another level (foe_ai.gd `climb`): a jump up onto a platform or ledge, or a drop
	var climb_t := 0           # frames left for the plan (0: none)
	var climb_cd := 0          # frames before it looks for another
	var climb_up := true       # up (or down)
	var climb_air := false     # it has jumped
	var climb_to := Vector2.ZERO     # where it means to stand (world)
	var climb_from := Vector2.ZERO   # where it jumps or drops from (world)
	var climb_why := ""        # (why its last look about found no way up: for the tests)

var gpu
var ui
var overlay
var space                 # above the orbit band: the space view and the staff-jet flight (space.gd)
var skiff = null          # the Wisp Skiff, when it's out on this planet (skiff.gd; saved in planet_state["skiff"])
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
var settings := {"quality": "high", "dither": "off", "pixel": 0, "music": 60, "sound": 80, "window": "windowed"}
var boss_info := Vector4.ZERO
var boss_clouds := []          # the Mycelord's spore clouds (boss_ai.gd update_clouds)
var scale_px := 4
var VW := 480
var VH := 270

# camera
var cam_c := Vector2(0, 1400)
var cam_a := PI / 2
var zoom := 1.0
var test_move := 0           # test mode: walk the local mage this way (-1, 0, 1)
var test_aim := Vector2.ZERO # test mode: where the local mage points (zero: the mouse)
var test_cast := false       # test mode: hold the left button
var test_dig := false        # test mode: hold the right button
var test_calm := false       # test mode: the biome guardians stay asleep (except while their own test runs)
var test_no_wild := false    # test mode: no wild creatures come by themselves (their own test spawns them)
# build mode (B): see build.gd
var build_on := false
var build_cat := 0
var build_idx := [0, 0, 0, 0, 0, 0, 0]  # the chosen piece in each category (one per Build.CATS)
var build_shape := 2           # how back walls and blocks are laid (Build.SHAPES: brush, line, rectangle, frame)
var build_thick := 2           # how thick a line or frame is
var build_drag := false        # dragging out a shape...
var build_drag_from := Vector2.ZERO    # ...from this point (a cell's middle; cells are looked up near you)
var build_seed := 1           # the furniture design shown (R rolls a new one)
var build_flip := false       # T mirrors it
var build_click := false      # a fresh left click (furniture, doors and platforms go down one per click)
var build_prev := {}          # what the overlay previews: {cells: [[pos, colour]], ok, circle}
var build_pieces: Array = []
var stamps: Array = []        # small blueprints to write into the world before the next GPU frame
var build_why_cell := Vector2i.ZERO
var build_why := ""                # why the last preview didn't fit (for the tests)
var _build_warn_t := 0
var build_last := ""          # what the last click did (for the test report)
var build_last_stamp := {}
var _low_hp_t := 0               # when the low-health reminder may show again    # and where its blueprint went
var build_w := 40             # structures: width ([ and ]), storeys (- and =), style (T)
var build_floors := 1
var build_style := 0
var _struct_key := ""
var _struct := {}             # the planned structure under the cursor (worked out when something changes)
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
## The profiler (F3, and the test report): microseconds per frame spent in each part of the game,
## section -> [average, recent peak, this frame's sum]. prof_add() from anywhere; GPU stages come
## from gpu_world.gd's timestamps.
var prof := {}
var hitch_us := 0          # the longest frame of the game's own work since the tests last reset it
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
	var furn := []             # furniture carried whole: [{name, rows, wall, kind}] (Build.carried_item)
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
	var pending_mat := -1      # what the pending placement uses (-1: the conjure material)
	var heal_left := 0.0       # health still to come from a draught or Mending
	var potion_cd := 0         # frames before another draught
	var decon_pause := 0       # frames of pause after picking a piece up (holding the button carries on after)
	var dig_tap := 0           # a quick right-click still digs for a few frames
	var jump_held := false
	var ground_t := 99         # frames since standing on something
	var jump_buf := 0          # frames a jump press is remembered
	var cast_frame := -100     # when the last spell was cast (for the cast pose)
	var floating := false      # levitating (for the float pose)
	var aboard = null          # the skiff this mage rides in (null: on foot)
	func _init() -> void:
		h = 17.0
		w = 7.0
		step_h = 5

var player := Mage.new()
## every Wisp Forge recipe: the fixed ones and the furniture from build mode's catalogue
var recipes: Array = Defs.RECIPES + Build.furniture_recipes()
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
var chunks = null          # pieces breaking off as rigid bodies (scripts/chunks.gd)
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
	space = Space.new()
	space.game = self
	pix.add_child(space)
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
	_apply_window()
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
		var tests_script = load("res://scripts/tests.gd")
		if tests_script == null or not tests_script.can_instantiate():
			printerr("[Wisp Forge] the test script doesn't load (a parse error?); quitting")
			get_tree().quit(2)
			return
		_tests = tests_script.new()   # kept as a member: a local would be freed before the tests run
		_tests.g = self
		_tests.run.call_deferred()
		return
	_migrate_old_saves()
	ui.show_title(true)

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
	if testing and Time.get_ticks_msec() > 540000:
		# a test run that hasn't finished in 9 minutes has broken somewhere: don't leave the game open
		printerr("[Wisp Forge] test mode timed out after 9 minutes; quitting")
		get_tree().quit(1)
		return
	if gpu == null:
		return
	var tp := Time.get_ticks_usec()
	gpu.flush()
	prof_add("read back", gpu.read_us)
	gpu.read_us = 0
	if gpu.fresh:
		tp = Time.get_ticks_usec()
		_take_gpu_results()
		prof_add("GPU results", Time.get_ticks_usec() - tp)
	var steps := 1
	if state == "play" or state == "dead":
		played += delta
		_tick_acc += minf(delta, 0.1)
		steps = mini(int(floor(_tick_acc * 60.0 + 0.001)), 4)
		_tick_acc = minf(_tick_acc - steps / 60.0, 1.0 / 60.0)
		for k in steps:
			_tick()
	if state == "play" or state == "dead" or state == "forge":
		tp = Time.get_ticks_usec()
		if (space.active and not space.live) or travelling:
			overlay.queue_redraw()          # (out in space the planet's cells rest: nothing for the GPU)
			lights.clear()
		else:
			_gpu_frame(state == "forge", steps)
		prof_add("GPU submit", Time.get_ticks_usec() - tp)
		tp = Time.get_ticks_usec()
		ui.update_hud(self)
		prof_add("HUD", Time.get_ticks_usec() - tp)
	ui.update_toasts()
	# performance readout (F3)
	prof_add("frame (CPU)", Time.get_ticks_usec() - t0 - gpu.wait_us)
	prof_add("waiting for the GPU", gpu.wait_us)
	gpu.wait_us = 0
	for k in gpu.gpu_us:
		prof_add("GPU " + String(k), int(gpu.gpu_us[k]))
	gpu.gpu_us.clear()
	for k in gpu.read_parts:
		prof_add(String(k), int(gpu.read_parts[k]))
	gpu.read_parts.clear()
	_prof_frame()
	hitch_us = maxi(hitch_us, Time.get_ticks_usec() - t0 - gpu.wait_us)
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
	var n: int = Defs.SH_N[Defs.shell_of_row(Defs.row_at(r))]
	var sa := roundf(a / TAU * n) / n * TAU
	return [Vector2(cos(sa), sin(sa)) * roundf(r), sa]

func _anchor_col(p: Vector2) -> int:
	return int(fposmod(atan2(p.y, p.x), TAU) / TAU * float(Defs.NS)) % Defs.NS

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
	if not stamps.is_empty():
		# what was built this frame goes into the world first
		gpu.stamp(stamps, frame)
		stamps.clear()
	# what's stamped, read and looked up near you from now till the next frame is centred on your
	# column (cell for cell at any depth, Build.cell_pos); it only moves once the stamps are in
	Defs.anchor_c = _anchor_col(player.pos if player != null else cam_c)
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
	var tu := Time.get_ticks_usec()
	if view_tex == null or view_tex.get_width() != gpu.VW or view_tex.get_height() != gpu.VH:
		view_tex = ImageTexture.create_from_image(gpu.view_img)
		view_rect.texture = view_tex
		view_rect.size = Vector2(gpu.VW, gpu.VH)
	else:
		view_tex.update(gpu.view_img)
	prof_add("picture upload", Time.get_ticks_usec() - tu)
	overlay.queue_redraw()

func day_len() -> float:
	return DAY_LEN

## where the sun is, as seen from the planet (it turns once a day)
func sun_angle() -> float:
	return spawn_angle - 1.1 + time / DAY_LEN * TAU

## The planet as you leave it, seen whole: one render with the camera at its centre, zoomed out so
## the top of the orbit band fits the picture's height, turned as the view is now (so where the
## space view takes over from the live planet, the two line up). space.gd shows it out in space.
func capture_planet() -> Dictionary:
	gpu.flush()
	if gpu.fresh:
		_take_gpu_results()
	var side := mini(VW, VH)
	var zc := maxf(Space.SWAP_ZOOM, 2.0 * Defs.R_SPACE * 1.03 / float(side))
	var ang := atan2(cam_c.y, cam_c.x)
	_write_frame_params()
	gpu.setp(1, Vector4(0.0, 0.0, ang, zc))
	gpu.setp(2, Vector4(VW, VH, gpu.LS, 0))           # (no torch lights: their places are for the close view)
	var frames := []
	for k in mini(players.size(), gpu.MAXP):
		if players[k].pos.length() < Defs.R_SPACE:
			frames.append(_grid_frame(players[k].pos))
	gpu.step([cam_c], frames, false, false, 0, true)
	gpu.fresh = false                                  # (that picture isn't the view)
	var img: Image = gpu.view_img.get_region(Rect2i((VW - side) / 2, (VH - side) / 2, side, side))
	img.generate_mipmaps()
	return {"tex": ImageTexture.create_from_image(img), "zoom": zc, "angle": ang, "edge": (Defs.R_TOP + 60.0) / zc / float(side)}

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
	if chunks != null and state == "play":
		var td := Time.get_ticks_usec()
		chunks.detect(m, cn)            # a felled tree or a creaking piece: lift it out whole
		prof_add("lifting pieces out", Time.get_ticks_usec() - td)
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
	if cn.size() > 53 and cn[52] > 0 and cn[53] >= ROCK_HURT_FALL and not m.dead:
		# a falling block lands on you: the longer it fell, the harder it hits (a clod that only
		# dropped a few cells, like the rim of a pit you're digging, just bumps you)
		var dmg := clampf(1.0 + float(cn[53] - ROCK_HURT_FALL) * 0.45 + float(cn[52]) * 0.1, 1.0, 35.0)
		var was := m.iframes
		hurt(m, dmg, Vector2(0, 1.2), true)
		if was == 0 and m.iframes > 0 and m.local:
			ui.toast("Falling rock! -%d" % int(dmg), Color(1, 0.6, 0.45), 1.5)
			shake = maxf(shake, 4.0)
	if cn[50] > 0:
		m.dig_blocked = 30
	if m.pending_place > 0:
		var pm := m.pending_mat if m.pending_mat >= 0 else m.mat
		m.inv[pm] = maxi(0, m.inv[pm] - mini(cn[51], m.pending_place))
		m.pending_place = 0
		m.pending_mat = -1

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
				"col": int(e[5]), "row": int(e[6]), "open": bool(e[7]), "swing": int(e[8]) if e.size() > 8 else int(e[4])})
			if e.size() > 9 and typeof(e[9]) == TYPE_ARRAY and (e[9] as Array).size() == int(e[2]) * int(e[3]):
				var dc: Array = []
				for v in e[9]:
					dc.append(int(v))
				doors[doors.size() - 1]["cells"] = dc
			if e.size() > 11:
				doors[doors.size() - 1]["ax"] = int(e[10])
				doors[doors.size() - 1]["aw"] = int(e[11])
	else:
		for e in builds.door_list:
			var d: Dictionary = e.duplicate()
			d["open"] = false
			d["swing"] = int(d["side"])
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
## A door record: its doorway is w x h cells from (col, row), laid out cell for cell as a stamp
## anchored at (ax, aw) puts them (a generated building's own anchor, or the one near you for one
## you set), so a door deep down is the same size as one at the surface. pos is its middle.
func _door_rec(col: int, row: int, w: int, h: int, side: int, ax: int, aw: int) -> Dictionary:
	var c := posmod(col, Defs.NS)
	var rm := row + h / 2
	var a0: Vector2 = Defs.stamp_pos(rm, ax, aw, Defs.k_of(c, ax))
	var a1: Vector2 = Defs.stamp_pos(rm, ax, aw, Defs.k_of(c + w - 1, ax))
	var mid := (a0 + a1).normalized() * (Defs.R_TOP - float(row) - float(h) * 0.5)
	return {"pos": mid, "w": w, "h": h, "side": side, "col": c, "row": row, "ax": posmod(ax, Defs.NS), "aw": aw, "open": false, "swing": side}

## a door's anchor (doors from before anchors were kept lie in the surface shell, where any will do)
func _door_ax(d: Dictionary) -> int:
	return int(d.get("ax", d["col"]))

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

## Opens or shuts a door. A door swings either way: away from whoever opens it (`opener`, their
## position; zero keeps the way it last swung).
func _set_door(d: Dictionary, open: bool, opener := Vector2.ZERO) -> void:
	if bool(d["open"]) == open:
		return
	if open and opener != Vector2.ZERO:
		var dp0: Vector2 = d["pos"]
		var u := (opener - dp0).dot(basis_r(atan2(dp0.y, dp0.x)))
		if absf(u) > 0.01:
			d["swing"] = -1 if u > 0.0 else 1
	if not open and _door_blocked(d):
		return
	var hw := float(d["w"]) * 0.5
	var hh := float(d["h"]) * 0.5
	if open:
		# which parts of it are still there (what was shot, burnt or dug away stays gone)
		_read_door_cells(d)
		if _door_left(d) * 3 < int(d["w"]) * int(d["h"]):
			# most of it was blasted or dug away: what's left falls apart, and the door is gone
			brushes.append([d["pos"], sqrt(hw * hw + hh * hh) + 1.5, 9, 0.0, hw, hh, 0.0, 3])
			doors.erase(d)
			return
	d["open"] = open
	if open or not d.has("cells"):
		# owner slot 3: nobody's satchel (a door brush collects nothing); a door never opened yet
		# closes whole
		brushes.append([d["pos"], sqrt(hw * hw + hh * hh) + 1.5, 9, 0.0 if open else 1.0, hw, hh, 0.0, 3])
	else:
		# shut it as it is: only the parts that are left go back into the doorway
		var w := int(d["w"])
		var data := PackedInt32Array()
		data.resize(w * int(d["h"]))
		data.fill(0xffff)
		var dc: Array = d["cells"]
		for k in dc.size():
			if int(dc[k]) >= 0:
				data[k] = Defs.WOODDOOR | 0xff00 | 0x10000 | 0x20000 | 0x8000000 | ((int(dc[k]) & 255) << 19)
		stamps.append({"x0": posmod(int(d["col"]), Defs.NS), "y0": int(d["row"]), "w": w, "h": int(d["h"]), "data": data, "ax": _door_ax(d), "aw": int(d.get("aw", 1))})
	audio.play("door_open" if open else "door_close", d["pos"])

## A door's parts, cell by cell across its doorway (w x h, row by row): the part each cell is (which
## of its pixels it draws), or -1 where it's gone. Read from the world when it opens.
func _read_door_cells(d: Dictionary) -> void:
	var w := int(d["w"])
	var h := int(d["h"])
	var rr: Dictionary = gpu.read_rect(int(d["col"]), int(d["row"]), w, h, _door_ax(d), int(d.get("aw", 1)))
	var fgs: PackedInt32Array = rr["fg"]
	var dc: Array = []
	for k in w * h:
		var v: int = fgs[k]
		dc.append(((v >> 8) & 255) if (v & 255) == Defs.WOODDOOR else -1)
	d["cells"] = dc

## how many of a door's cells are left (all of them for a door never opened)
func _door_left(d: Dictionary) -> int:
	if not d.has("cells"):
		return int(d["w"]) * int(d["h"])
	var n := 0
	for v in d["cells"]:
		if int(v) >= 0:
			n += 1
	return n

## Damage to an open door's panel: the parts within `r` of `p` go (burnt or splintered). A panel with
## less than a third left falls apart. True if any part went.
func _hurt_open_door(d: Dictionary, p: Vector2, r: float, burnt: bool) -> bool:
	if not d.has("cells"):
		var full: Array = []
		for k in int(d["w"]) * int(d["h"]):
			full.append(((k / int(d["w"])) << 2) | mini(k % int(d["w"]), 3))
		d["cells"] = full
	var w := int(d["w"])
	var h := int(d["h"])
	var pp := door_panel_pos(d)
	var a := atan2(pp.y, pp.x)
	var flip := -1.0 if float(d.get("swing", d["side"])) < 0.0 else 1.0
	var dc: Array = d["cells"]
	var hit := false
	for k in dc.size():
		if int(dc[k]) < 0:
			continue
		var x := ((float(k % w) + 0.5) * DOOR_PANEL_W / float(w) - DOOR_PANEL_W * 0.5) * flip
		var y := float(k / w) - float(h) * 0.5 + 0.5
		var q := pp + basis_r(a) * x + basis_d(a) * y
		if q.distance_to(p) < r:
			dc[k] = -1
			hit = true
			if randf() < 0.3:
				_particle(q, Vector2(randf() - 0.5, -randf()) * 0.6, 20 + randi() % 20, Color(0.3, 0.2, 0.12) if burnt else Color(0.62, 0.42, 0.22), true, 0.02)
	if hit and _door_left(d) * 3 < w * h:
		_door_destroyed(d, burnt)
	return hit

const DOOR_PANEL_W := 10.0    # an open door is drawn face-on, this wide, beside its doorway

## where an open door's panel is (its middle, world)
func door_panel_pos(d: Dictionary) -> Vector2:
	var dp: Vector2 = d["pos"]
	var a := atan2(dp.y, dp.x)
	return dp + basis_r(a) * float(d.get("swing", d["side"])) * (float(d["w"]) * 0.5 + DOOR_PANEL_W * 0.5)

## An open door's panel is wood like any other: fire reaching it burns it (checked a few times a
## second around the mage), a blast breaks it. Either way the door is gone.
func _check_door_fire() -> void:
	if frame % 6 != 0:
		return
	for k in range(doors.size() - 1, -1, -1):
		var d: Dictionary = doors[k]
		if not bool(d["open"]):
			continue
		var pp := door_panel_pos(d)
		if pp.distance_squared_to(player.pos) > 200.0 * 200.0:
			continue
		var a := atan2(pp.y, pp.x)
		# fire eats into the panel where it touches it (a third left and it falls apart)
		for sj in range(-int(d["h"]) / 2, int(d["h"]) / 2 + 1, 3):
			for si in range(-4, 5, 2):
				var q := pp + basis_r(a) * float(si) + basis_d(a) * float(sj)
				var t := type_at(q)
				if t == Defs.FIRE or t == Defs.LAVA:
					_hurt_open_door(d, q, 3.0, true)
					if not doors.has(d):
						break
			if not doors.has(d):
				break

func _door_destroyed(d: Dictionary, burnt: bool) -> void:
	var pp := door_panel_pos(d) if bool(d["open"]) else (d["pos"] as Vector2)
	if not bool(d["open"]):
		var hw := float(d["w"]) * 0.5
		var hh := float(d["h"]) * 0.5
		brushes.append([d["pos"], sqrt(hw * hw + hh * hh) + 1.5, 9, 0.0, hw, hh, 0.0, 3])
	doors.erase(d)
	if burnt:
		brushes.append([pp, 4.0, 3, Defs.FIRE, 0, 0, 0])      # the panel goes up in flames
		audio.play("fire", pp, 0.8)
	for k in 14:
		var col := Color(1.0, 0.55, 0.2) if burnt and k % 2 == 0 else Color(0.55, 0.36, 0.2)
		_particle(pp + Vector2(randf() - 0.5, randf() - 0.5) * Vector2(8.0, 24.0), Vector2(randf() - 0.5, -randf()) * 0.8, 20 + randi() % 20, col, burnt, 0.04)

## the door whose doorway (grown by `pad` cells) contains p, or {}
func _door_at(p: Vector2, pad: float) -> Dictionary:
	for d in doors:
		var dp: Vector2 = d["pos"]
		if dp.distance_squared_to(p) > 1600.0:
			continue
		var a := atan2(dp.y, dp.x)
		var o := p - dp
		var hw := float(d["w"]) * 0.5 + pad
		var hh := float(d["h"]) * 0.5 + pad
		# an open door also reaches out to where its panel is drawn
		var u := o.dot(basis_r(a))
		if bool(d["open"]):
			var reach_out := float(d["w"]) * 0.5 + DOOR_PANEL_W + pad
			var outward := float(d.get("swing", d["side"]))
			if (u * outward > 0.0 and u * outward < reach_out) and absf(o.dot(basis_d(a))) < hh:
				return d
		if absf(u) < hw and absf(o.dot(basis_d(a))) < hh:
			return d
	return {}

## take a door down: its cells go, it goes into the satchel (to be put up again in build mode)
func _take_door(m: Mage, d: Dictionary) -> void:
	if not bool(d["open"]):
		var hw := float(d["w"]) * 0.5
		var hh := float(d["h"]) * 0.5
		brushes.append([d["pos"], sqrt(hw * hw + hh * hh) + 1.5, 9, 0.0, hw, hh, 0.0, 3])
	doors.erase(d)
	m.inv[Defs.WOODDOOR] += 1
	audio.play("door_close", d["pos"], 0.8, 0.7)
	for k in 10:
		_particle(d["pos"] + Vector2(randf() - 0.5, randf() - 0.5) * 8.0, Vector2(randf() - 0.5, randf() - 0.7) * 0.8, 20 + randi() % 15, Color(0.6, 0.4, 0.22), false, 0.05)
	if m.local:
		ui.toast("+1 Door (put it up again in build mode, B)", Color(0.85, 0.65, 0.4), 2.5)

## how many of a closed door's cells are still there (from the collision grid around the mage); a
## door blasted to pieces is gone, it doesn't come back whole when you open and shut it
func _door_cells(d: Dictionary) -> int:
	var n := 0
	var col0: int = d["col"]
	var row0: int = d["row"]
	var dax := _door_ax(d)
	var daw := int(d.get("aw", 1))
	for j in int(d["h"]):
		for i in int(d["w"]):
			if type_at(Defs.stamp_pos(row0 + j, dax, daw, Defs.k_of(col0 + i, dax))) == Defs.WOODDOOR:
				n += 1
	return n

## walking into a closed door opens it (the mage, and foes that know how: Defs.ENEMY ai "doors")
func _door_bump(m: Body) -> void:
	var d := _door_near(m.pos, 24.0)
	if not d.is_empty() and not d["open"]:
		_set_door(d, true, m.pos)

## F: open a chest in reach, otherwise open or close the nearest door
func _interact() -> void:
	if _skiff_interact(player):
		return
	if not _chest_in_reach().is_empty():
		_try_open_chest()
		return
	if _try_home(player, 12):            # a bed right beside you comes before a door
		return
	var d := _door_near(player.pos, 22.0)
	if d.is_empty() and _try_home(player, 26):
		return
	if not d.is_empty():
		_set_door(d, not d["open"], player.pos)

## Chests near a mage obey gravity: one rigid object, so it falls and lands whole. A chest
## resting on something stays exactly where it is: the collision grid is built around the mage and
## tilts with the planet's curve as he walks, so a chest some way off sees its ground shift a cell
## or so. It looks a few cells down for ground and only falls once nothing has been under it for
## CHEST_LET_GO frames in a row.
const CHEST_LET_GO := 12
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
		if c.on_ground:
			var held := box_solid(l.x - c.w * 0.5, l.y - c.h * 0.5 + 1.5, c.w, c.h) \
				or box_solid(l.x - c.w * 0.5 + 1.0, l.y + c.h * 0.5, c.w - 2.0, 3.5)
			c.unsup_t = 0 if held else c.unsup_t + 1
			if c.unsup_t < CHEST_LET_GO:
				c.vy = 0.0           # still something under it: it stays put
				continue
		c.unsup_t = 0
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
	# now and then a Healing Draught (the deeper and grander the place, the likelier)
	if randf() < 0.2 + rare * 0.45:
		items["potion"] = int(items.get("potion", 0)) + 1
		ui.toast("+1 Healing Draught (H to drink)", Color(0.6, 1.0, 0.65), 3.0)
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
	for id in ["scroll_blink", "scroll_starfall", "scroll_mend", "ring", "circlet", "boots"]:
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
		"scroll_mend":
			ui.toast("RARE FIND: Scroll of Mending! Forge it at the Wisp Forge (Spells).", Color(0.55, 1.0, 0.62), 7.0)
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
## you are always one pixel wide. Shells next to each other differ by only a sixteenth or so in
## columns (Defs.set_geometry), and across a seam the scale is the average over the shells within
## UNROLL_EASE rows of the camera (weighted by how many of those rows each has), so it changes
## smoothly and by too little to see; inside a shell, away from its seams, it is exactly its own.
const UNROLL_EASE := 24.0
func unroll_step(r: float) -> float:
	var row := Defs.R_TOP - r
	var a := row - UNROLL_EASE
	var b := row + UNROLL_EASE
	var s: int = Defs.shell_of_row(int(floor(a)))
	var sum := 0.0
	var at := a
	while at < b:
		var end := b
		if s < Defs.NSH - 1:
			end = minf(b, float(Defs.SH_Y1[s]))
		if end > at:
			sum += (end - at) * log(TAU / float(Defs.SH_N[s]))
			at = end
		if s >= Defs.NSH - 1:
			break
		s += 1
	if at < b:
		sum += (b - at) * log(TAU / float(Defs.SH_N[Defs.NSH - 1]))
	return exp(sum / (b - a))

func unrolled() -> bool:
	# (out in space, with the planet shown as its picture, the view is always flat: close by an
	# asteroid it zooms right in, and nothing there needs the planet's curve unrolled)
	if space != null and space.active and not space.live:
		return false
	return zoom < 2.5

func _view() -> Vector2:
	return cam_c if view_c == Vector2.ZERO else view_c

## the view's turn: "up" points away from the planet's centre, and out in space away from the
## nearest planet's (space.view_ang, eased as that changes)
func view_angle() -> float:
	if space.active and not space.live:
		return space.view_ang
	var c := _view()
	return atan2(c.y, c.x)

func world_to_screen(p: Vector2) -> Vector2:
	var c := _view()
	var a := view_angle()
	if unrolled():
		var d := wrapf(atan2(p.y, p.x) - a, -PI, PI)
		return Vector2(-d / ustep, c.length() - p.length()) / zoom + Vector2(VW, VH) * 0.5
	var o := p - c
	return Vector2(o.dot(basis_r(a)), o.dot(basis_d(a))) / zoom + Vector2(VW, VH) * 0.5

func screen_to_world(px: Vector2) -> Vector2:
	var c := _view()
	var a := view_angle()
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
				if box_count(x + st, y, e.w, e.h, Defs.WOODDOOR) > 0:
					if e is Mage:
						_door_bump(e)
					elif e is Enemy and e.d.get("ai", {}).get("doors", false):
						_door_bump(e)       # a skeleton lifts the latch too
						(e as Enemy).door_t = 40
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
	if r > Defs.R_SPACE - 8.0:          # (the top of the orbit band: the space map comes later)
		e.pos = e.pos.normalized() * (Defs.R_SPACE - 8.0)
		e.vy = maxf(e.vy, 0.0)

func gravity_at(p: Vector2) -> float:
	var r := p.length()
	var rs: float = gpu.surf_at(atan2(p.y, p.x)).x
	if r < rs + 150.0:
		return 1.0
	return maxf(0.06, 1.0 - (r - rs - 150.0) / 380.0)

## the name of the biome at an angle ("forest", "tundra"...)
func _biome_name_at(a: float) -> String:
	var names: Array = planet.get("biomes", ["forest"])
	return String(names[clampi(int(gpu.surf_at(a).y), 0, names.size() - 1)])

## a wild creature of a place ("forest", "cave2"...), or "" if none lives there or enough are about
func _wild_pick(where: String, most: int) -> String:
	var ids: Array = Defs.creatures_of(where)
	if ids.is_empty() or test_no_wild:
		return ""
	var wild := 0
	for e in enemies:
		if e.d.get("creature", false):
			wild += 1
	if wild >= most:
		return ""
	return "c_" + String(ids[randi() % ids.size()])

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
	if test_aim != Vector2.ZERO:
		inp.aim = test_aim      # the test mode points the mage
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
	inp.cast = (can_act and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or test_cast
	var rmb := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or m.dig_tap > 0
	var shift := Input.is_key_pressed(KEY_SHIFT)
	inp.dig = (can_act and rmb and not shift) or test_dig
	inp.decon = can_act and rmb and shift

func _tick() -> void:
	frame += 1
	time += 1.0
	if stamps.is_empty() and player != null:
		Defs.anchor_c = _anchor_col(player.pos)      # (nothing waiting to go in under the old one)
	_read_local_input(player)
	var aim: Vector2 = player.input.aim
	if space.active:
		# out in space only the mage moves; the planet below waits as it was
		space.tick()
		_update_particles()
		_update_wisp()
		shake *= 0.88
		hurt_flash *= 0.9
		return
	_update_skiff()
	var tm := Time.get_ticks_usec()
	for m in players:
		if m.cast_cd > 0:
			m.cast_cd -= 1
		if m.dig_blocked > 0:
			m.dig_blocked -= 1
		_use_grid(m)
		_update_player(m)
		m.sel = clampi(m.sel, 0, m.known.size() - 1)
		if not m.dead and state == "play" and m.aboard == null:
			if m.local and build_on:
				_update_build(m)
			elif m.input.cast:
				_cast(m, m.known[m.sel], m.input.aim)
			if m.input.dig:
				_excavate(m, m.input.aim)
			if m.input.decon:
				_deconstruct(m, m.input.aim)
			else:
				m.decon_pause = 0
		if m.dig_tap > 0:
			m.dig_tap -= 1
	prof_add("mages", Time.get_ticks_usec() - tm)
	_use_grid(player)
	var tq := Time.get_ticks_usec()
	_update_enemies()
	BossAI.update_clouds(self)
	if player.items.has("lantern") and not player.dead:
		lights.append([player.pos, 70.0, Color(0.55, 0.95, 0.85)])      # (the Glowcap Lantern)
	_update_chests()
	prof_add("foes and chests", Time.get_ticks_usec() - tq)
	if chunks != null:
		tq = Time.get_ticks_usec()
		chunks.update()
		prof_add("falling pieces", Time.get_ticks_usec() - tq)
	_use_grid(player)
	tq = Time.get_ticks_usec()
	_update_projectiles()
	_use_grid(player)
	_check_door_fire()
	_update_particles()
	prof_add("shots and particles", Time.get_ticks_usec() - tq)
	_update_weather()
	_try_spawn()
	_update_guards()
	_check_chest_hint()
	_update_wisp()
	_cloud_wisps()
	space.planet_tick()
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
	if m.aboard != null:
		_ride(m)
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
	var speed := (0.9 if p.in_liquid else 1.5) * (1.2 if m.items.has("coil") else 1.0)
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
		m.mana -= 0.27 if m.items.has("roc") else 0.55
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
	# risen to the top of the orbit band, still climbing: out into space
	if m == player and m.floating and p.pos.length() >= Defs.R_SPACE - 9.5:
		space.try_enter()
		if space.active:
			return
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
	# under water, or above the air: holding your breath
	if (Defs.KIND[head_t] == Defs.K_LIQUID and not m.items.has("pearl")) or p.pos.length() > Defs.R_TOP + 4.0:
		m.breath -= 1.0
		if m.breath <= 0:
			m.breath = 0
			hurt(m, 0.25, Vector2.ZERO, false)
	else:
		m.breath = minf(m.max_breath, m.breath + 4.0)
	if m.iframes > 0:
		m.iframes -= 1
	m.mana = minf(m.max_mana, m.mana + m.mana_regen)
	# no health comes back by itself: only a draught or Mending, a little each frame
	if m.heal_left > 0.0 and not m.dead:
		var hh := minf(m.heal_left, Defs.HEAL_RATE)
		m.hp = minf(m.max_hp, m.hp + hh)
		m.heal_left -= hh
		if m.hp >= m.max_hp:
			m.heal_left = 0.0
		if frame % 6 == 0:
			_particle(m.pos + Vector2(randf() - 0.5, randf() - 0.5) * 10.0, m.pos.normalized() * 0.4, 24, Color(0.55, 1.0, 0.6), true, -0.01)
	if m.potion_cd > 0:
		m.potion_cd -= 1
	if m.local and m.hp < m.max_hp * 0.3 and m.heal_left <= 0.0 and frame >= _low_hp_t and not m.dead:
		_low_hp_t = frame + 1800
		ui.toast("Low health%s" % (": drink a Healing Draught (H)" if int(items.get("potion", 0)) > 0 else ". Health doesn't come back by itself"), Color(1, 0.55, 0.5), 3.0)

func hurt(m: Mage, dmg: float, knock: Vector2, hit: bool) -> void:
	if m.dead or test_god:
		return
	if m.items.has("ironbark"):
		dmg *= 0.75
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
	if id == "mend":
		if m.hp >= m.max_hp:
			if m.local:
				ui.toast("You're unhurt", Color(0.8, 0.95, 0.8), 1.0)
			m.cast_cd = 20
			return
		m.mana -= float(s["mana"])
		m.cast_cd = s["cd"]
		m.heal_left += Defs.MEND_HEAL
		audio.play("rare", m.pos, 0.6)
		lights.append([m.pos, 26.0, Color(0.5, 1.1, 0.6)])
		for k in 14:
			_particle(m.pos + Vector2(randf() - 0.5, randf() - 0.5) * 14.0, m.pos.normalized() * (0.2 + randf() * 0.4), 30, s["color"], true, -0.01)
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
	# digging at a door (open or shut) takes the whole door down: it goes into the satchel as a Door
	var dd := _door_at(p, m.dig_r * 0.6)
	if not dd.is_empty():
		_take_door(m, dd)
	if m.local and _dig_open_t <= 0 and _dig_hits_chest(p, m.dig_r):
		_dig_open_t = 30
		_try_open_chest()
	brushes.append([p, m.dig_r, 1, 0, m.tier, 0, 0, m.slot])
	lights.append([p, 10.0, Color(0.4, 0.8, 0.5)])

## Shift + right mouse: take background tiles (a building's back walls, furniture, plants). It is how
## you clear a wall on purpose; plain right-click never touches a building's walls.
func _deconstruct(m: Mage, aim: Vector2) -> void:
	var p := _reach(m, aim)
	if m.decon_pause > 0:
		m.decon_pause -= 1
		return
	if _pick_up_furniture(m, p):
		m.decon_pause = 15       # a moment's pause, then harvesting carries on while the button is held
		return
	brushes.append([p, m.dig_r * 0.8, 8, 0, m.tier, 0, 0, m.slot])
	lights.append([p, 10.0, Color(0.9, 0.6, 0.3)])

# ------------------------------------------------------------ furniture --
var _pick_miss := Vector2i(-99999, 0)   # where a look for furniture last found none (and when)
var _pick_miss_t := -9999
const PICK_HALF := 48          # how far from the cursor a piece may reach (it's read as one block)

## The connected piece of furniture around cell `start` in a block read by gpu.read_rect (n x n,
## background layer `bgs`): its cells (indices into the block), joined across diagonals, of the same
## kind as the start cell (so a chair pushed against a table stays a chair); a piece's candles and
## lamps come with it. Empty if it reaches the edge of the block (too big to carry).
func _furniture_piece(bgs: PackedInt32Array, n: int, start: int) -> PackedInt32Array:
	var kid := (bgs[start] >> 24) & 15
	var seen := PackedByteArray()
	seen.resize(n * n)
	var out := PackedInt32Array()
	var todo := PackedInt32Array([start])
	seen[start] = 1
	while not todo.is_empty():
		var k: int = todo[todo.size() - 1]
		todo.remove_at(todo.size() - 1)
		out.append(k)
		var ci := k % n
		var cj := k / n
		if ci == 0 or cj == 0 or ci == n - 1 or cj == n - 1:
			return PackedInt32Array()
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				var q: int = k + dj * n + di
				if seen[q] != 0:
					continue
				var mq := bgs[q] & 255
				if (mq == Defs.DECOR and ((bgs[q] >> 24) & 15) == kid) or mq == Defs.TORCH:
					seen[q] = 1
					todo.append(q)
	return out

## Shift + right-click on a piece of furniture takes it whole: its exact pixels go into the satchel
## (Mage.furn) and it can be set down again from build mode's Satchel tab. If it stood in front of a
## back wall, the wall is made whole behind it. False if there's no furniture at p (then the
## ordinary deconstruct takes background tiles).
func _pick_up_furniture(m: Mage, p: Vector2) -> bool:
	var cc := Build.cell_of(p)
	# the collision grid already marks furniture: only read the world back (which waits for the GPU)
	# when some is actually under the cursor, not every frame the button is held over a plain wall
	var gr := int(ceil(m.dig_r * 0.8))
	var any := false
	for gj in range(-gr, gr + 1):
		for gi in range(-gr, gr + 1):
			var bgk := _bg_at(cc.x + gi, cc.y + gj)
			if bgk == 1 or bgk < 0:          # (outside the grid: can't tell, so look)
				any = true
				break
		if any:
			break
	if not any:
		return false
	# (a torch or an opened chest is marked too: having looked once and found no furniture there,
	# don't look again until the cursor moves on)
	if (cc - _pick_miss).length_squared() < 16 and frame - _pick_miss_t < 120:
		return false
	var n := PICK_HALF * 2 + 1
	var c0 := cc.x - PICK_HALF
	var r0 := cc.y - PICK_HALF
	var rr: Dictionary = gpu.read_rect(c0, r0, n, n)
	var bgs: PackedInt32Array = rr["bg"]
	var reach := int(ceil(m.dig_r * 0.8))
	var start := -1
	var best := 1 << 30
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var k := (PICK_HALF + dj) * n + PICK_HALF + di
			if (bgs[k] & 255) == Defs.DECOR and di * di + dj * dj < best:
				best = di * di + dj * dj
				start = k
	if start < 0:
		_pick_miss = cc
		_pick_miss_t = frame
		return false
	var cells := _furniture_piece(bgs, n, start)
	if cells.is_empty():
		_pick_miss = cc
		_pick_miss_t = frame
		return false
	var kid := (bgs[start] >> 24) & 15
	var i0 := n
	var j0 := n
	var i1 := -1
	var j1 := -1
	var inside := {}
	for k in cells:
		i0 = mini(i0, k % n)
		i1 = maxi(i1, k % n)
		j0 = mini(j0, k / n)
		j1 = maxi(j1, k / n)
		inside[k] = true
	var w := i1 - i0 + 1
	var h := j1 - j0 + 1
	var pix := []
	for y in h:
		var line := PackedStringArray()
		line.resize(w)
		line.fill(".")
		pix.append(line)
	# the wall it hid: if most of what's around its outline is a back wall, the same wall goes back
	var hist := {}
	var around := 0
	var walls := 0
	var anchored := 0
	for k in cells:
		var b := bgs[k]
		var ln: PackedStringArray = pix[k / n - j0]
		ln[k % n - i0] = "t" if (b & 255) == Defs.TORCH else Build.Props.char_of((b >> 16) & 63)
		pix[k / n - j0] = ln
		for q in [k - 1, k + 1, k - n, k + n]:
			if inside.has(q):
				continue
			around += 1
			var bq := bgs[q]
			var mq := bq & 255
			if mq != 0 and mq != Defs.DECOR and mq != Defs.TORCH and (bq & 0x4000) != 0:
				walls += 1
				hist[mq] = int(hist.get(mq, 0)) + 1
				if (bq & 0x8000) != 0:
					anchored += 1
	var wm := 0
	if walls > 0 and walls * 2 >= around:
		for mk in hist:
			if wm == 0 or int(hist[mk]) > int(hist[wm]):
				wm = int(mk)
	var data := PackedInt32Array()
	data.resize(w * h)
	data.fill(0xffff)
	for k in cells:
		var v := 0xff                                  # the front is left as it is
		# the wall each cell stood in front of (furniture remembers it), or the wall around it
		var bk := bgs[k]
		var bmk: int = Defs.BEHIND[((bk >> 22) & 3) | (((bk >> 28) & 7) << 2)] if (bk & 255) == Defs.DECOR else 0
		if bmk != 0:
			v |= (bmk << 8) | 0x40000 | (0x20000 if (bk & 0x8000) != 0 else 0)
		elif wm != 0:
			v |= (wm << 8) | 0x40000 | (0x20000 if anchored * 2 >= walls else 0)
		else:
			v |= 0                                     # nothing behind: the background is left empty
		data[(k / n - j0) * w + (k % n - i0)] = v
	stamps.append({"x0": posmod(c0 + i0, Defs.NS), "y0": r0 + j0, "w": w, "h": h, "data": data})
	var rows := []
	for ln2 in pix:
		rows.append("".join(ln2))
	var item := {"name": Build.Props.KIND_NAMES[kid], "rows": rows, "wall": Build.Props.WALL_KINDS.has(kid), "kind": kid}
	m.furn.append(item)
	var mid := Build.cell_pos(c0 + (i0 + i1) / 2, r0 + (j0 + j1) / 2)
	audio.play("place", mid, 0.7, 0.8)
	for q2 in 12:
		_particle(mid + Vector2(randf() - 0.5, randf() - 0.5) * Vector2(w, h) * 0.8, Vector2(randf() - 0.5, -randf()) * 0.5, 18 + randi() % 14, Color(0.95, 0.8, 0.5), true, -0.01)
	if m.local:
		ui.toast("+ %s (set it down in build mode, B: Satchel tab)" % item["name"], Color(0.95, 0.8, 0.5), 2.5)
	return true

## The nearest bed around `pos` (a piece whose cells are of kind Props.BED): its box of cells
## {c0, r0, c1, r1, n (cells)}, or {} if none within `reach` cells.
func _bed_near(pos: Vector2, reach: int) -> Dictionary:
	var cc := Build.cell_of(pos)
	var n := (reach + PICK_HALF) * 2 + 1
	var half := reach + PICK_HALF
	var rr: Dictionary = gpu.read_rect(cc.x - half, cc.y - half, n, n)
	var bgs: PackedInt32Array = rr["bg"]
	var start := -1
	var best := 1 << 30
	for dj in range(-reach, reach + 1):
		for di in range(-reach, reach + 1):
			var k := (half + dj) * n + half + di
			var b := bgs[k]
			if (b & 255) == Defs.DECOR and ((b >> 24) & 15) == Build.Props.BED and di * di + dj * dj < best:
				best = di * di + dj * dj
				start = k
	if start < 0:
		return {}
	var cells := _furniture_piece(bgs, n, start)
	if cells.is_empty():
		return {}
	var box := {"c0": 1 << 30, "r0": 1 << 30, "c1": -(1 << 30), "r1": -(1 << 30), "n": cells.size()}
	for k in cells:
		var col := cc.x - half + k % n
		var row := cc.y - half + k / n
		box["c0"] = mini(box["c0"], col)
		box["c1"] = maxi(box["c1"], col)
		box["r0"] = mini(box["r0"], row)
		box["r1"] = maxi(box["r1"], row)
	return box

const HOME_ROOF := 70          # how far above a bed its roof may be
## What's missing for a bed to make a home ("" if nothing): a roof over all of it, and a back wall
## behind the room above it (most of it: a window or two is fine).
func _home_check(bed: Dictionary) -> String:
	var c0: int = bed["c0"] - 1
	var w: int = int(bed["c1"]) - c0 + 2
	var top: int = int(bed["r0"]) - HOME_ROOF
	var h: int = int(bed["r0"]) - top
	var rr: Dictionary = gpu.read_rect(c0, top, w, h)
	var fgs: PackedInt32Array = rr["fg"]
	var bgs: PackedInt32Array = rr["bg"]
	for i in [1, w / 2, w - 2]:
		var roofed := false
		for j in range(h - 1, -1, -1):
			var t := fgs[j * w + i] & 255
			if Defs.KIND[t] == Defs.K_SOLID and t != Defs.LEAF:
				roofed = true
				break
		if not roofed:
			return "a roof over it"
	var walled := 0
	var total := 0
	for j in range(h - 14, h):
		for i in range(1, w - 1):
			total += 1
			if (bgs[j * w + i] & 255) != 0:
				walled += 1
	if walled * 10 < total * 7:
		return "walls around it"
	return ""

## F at a bed in a proper room makes it your home: when your light fades, the wisp brings you back
## to it (planet_state["home"], saved with the world) instead of to the surface.
func _try_home(m: Mage, reach: int) -> bool:
	var bed := _bed_near(m.pos, reach)
	if bed.is_empty():
		return false
	var why := _home_check(bed)
	if why != "":
		ui.toast("This bed needs %s to be a home" % why, Color(1, 0.7, 0.55), 2.5)
		return true
	var mid := Build.cell_pos((int(bed["c0"]) + int(bed["c1"])) / 2, int(bed["r1"]) - 9)
	# (the bed's cells as read now: anchored near you, so keep that anchor to find them again)
	planet_state["home"] = {"pos": [mid.x, mid.y], "bed": [bed["c0"], bed["r0"], bed["c1"], bed["r1"]], "n": bed["n"], "ax": Defs.anchor_c}
	audio.play("forge", mid, 0.5)
	for k in 16:
		_particle(mid + Vector2(randf() - 0.5, randf() - 0.5) * 16.0, Vector2(randf() - 0.5, -0.3 - randf() * 0.5), 30 + randi() % 20, Color(0.75, 0.85, 1.0), true, -0.01)
	ui.toast("Home: when your light fades, the wisp brings you back to this bed", Color(0.75, 0.88, 1.0), 3.5)
	return true

## where the wisp brings you back to: home, if its bed is still there (most of it), else nowhere
func _home_pos() -> Variant:
	if not planet_state.has("home"):
		return null
	var hm: Dictionary = planet_state["home"]
	var bx: Array = hm["bed"]
	var rr: Dictionary = gpu.read_rect(int(bx[0]), int(bx[1]), int(bx[2]) - int(bx[0]) + 1, int(bx[3]) - int(bx[1]) + 1, int(hm.get("ax", int(bx[0]))))
	var left := 0
	for b in rr["bg"]:
		if (b & 255) == Defs.DECOR and ((b >> 24) & 15) == Build.Props.BED:
			left += 1
	if left * 2 < int(hm.get("n", 1)):
		planet_state.erase("home")
		ui.toast("Your bed is gone: the wisp brings you to the surface", Color(1, 0.7, 0.55), 3.5)
		return null
	var hp2: Array = hm["pos"]
	return Vector2(float(hp2[0]), float(hp2[1]))

func _conjure(m: Mage, aim: Vector2) -> void:
	if m.mat <= 0 or m.inv[m.mat] <= 0:
		return
	var p := _reach(m, aim)
	# conjuring onto a foe doesn't bury it: the forming stone strikes it and shoves it aside, and
	# nothing is placed there
	var struck := false
	for e in enemies:
		if _overlaps_r(p, e, 3.2):
			struck = true
			if e.flash <= 0:
				var push := signf((e.pos - m.pos).dot(basis_r(atan2(e.pos.y, e.pos.x))))
				_hurt_enemy(e, 3.0, push * 1.6, -1.2)
				for k in 5:
					_particle(e.pos, Vector2(randf() - 0.5, randf() - 0.8), 16 + randi() % 10, Defs.COLOR[m.mat], false, 0.05)
	if struck:
		return
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
		if pd.has("home") and pr["owner"] != "player":
			# (a spore drifts after you)
			var hm := _nearest_mage(pos)
			vel = vel.lerp((hm.pos - pos).normalized() * float(pd["speed"]), float(pd["home"]))
		pr["life"] = int(pr["life"]) - 1
		var steps := maxi(1, int(ceil(vel.length() * 2.0)))
		var hit := false
		var hit_enemy = null
		var hit_m = null
		_use_grid(_nearest_mage(pos))
		for s in steps:
			pos += vel / steps
			if pos.length() >= Defs.R_SPACE - 1.0 or pos.length() < Defs.R_IN:
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
					if not e.dead and not e.under and _overlaps(pos, e):
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
		if pr["type"] == "arrow":
			continue                  # an arrow neither glows nor sparks
		var col: Color = Defs.SPELLS[pr["type"]]["color"] if Defs.SPELLS.has(pr["type"]) else pd.get("col", Color(1, 0.35, 0.12))
		if float(pd["light"]) > 0.0:
			lights.append([pos, float(pd["light"]), col * 0.85])
		if randf() < 0.6:
			_particle(pos, Vector2(randf() - 0.5, randf() - 0.5) * 0.3, 10 + randi() % 8, col, true, 0.0)

## does a circle of radius r around p touch body e?
func _overlaps_r(p: Vector2, e: Body, r: float) -> bool:
	var a := atan2(e.pos.y, e.pos.x)
	var o := p - e.pos
	return absf(o.dot(basis_r(a))) < e.w * 0.5 + r and absf(o.dot(basis_d(a))) < e.h * 0.5 + r

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
				if items.has("rimefang"):
					e.slow = maxi(e.slow, 150)
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
		"arrow":
			if hit_m != null:
				var av: Vector2 = pr["vel"]
				var ha := atan2(hit_m.pos.y, hit_m.pos.x)
				hurt(hit_m, float(pd["dmg"]), Vector2(signf(av.dot(basis_r(ha))) * 1.6, -0.8), true)
			for k in 6:
				_particle(p, Vector2(randf() - 0.5, randf() - 0.9) * 0.9, 12 + randi() % 10, Color(0.62, 0.44, 0.26), false, 0.06)
			return
		"efire":
			if hit_m != null:
				hurt(hit_m, float(pd["dmg"]) * (0.6 if hit_m.heat_ward else 1.0), Vector2(signf(randf() - 0.5) * 1.5, -1.0), true)
			else:
				brushes.append([p, 1.8, 3, Defs.FIRE, 0, 0, 0])
		_:
			# the guardians' shots: they hurt you, or leave their matter where they land
			if hit_m != null:
				var hv: Vector2 = pr["vel"]
				var hha := atan2(hit_m.pos.y, hit_m.pos.x)
				hurt(hit_m, float(pd["dmg"]), Vector2(signf(hv.dot(basis_r(hha))) * 1.8, -1.2), true)
			elif pd.has("splat") and hit:
				brushes.append([p, 2.2, 3, int(pd["splat"]), 0, 0, 0])
	var col: Color = Defs.SPELLS[type]["color"] if Defs.SPELLS.has(type) else pd.get("col", Color(1, 0.35, 0.12))
	for k in 10:
		_particle(p, Vector2(randf() - 0.5, randf() - 0.8) * 1.5, 14 + randi() % 10, col, true, 0.05)

func _explode(p: Vector2, r: float, power: int, kind: int, dmg: float) -> void:
	brushes.append([p, r, 2, kind, power, 0, 0])
	for k in range(doors.size() - 1, -1, -1):
		var dk: Dictionary = doors[k]
		if bool(dk["open"]) and door_panel_pos(dk).distance_to(p) < r + float(dk["h"]) * 0.5:
			_hurt_open_door(dk, p, r + 1.0, kind == 1)
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
	var d: Dictionary = Defs.enemy_def(type)
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
	if items.has("sunidol"):
		dmg *= 1.25
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
	if e.d.has("def"):
		for ck in ["base", "belly", "accent", "dark"]:
			if e.d["def"]["body"].has(ck):
				cols.append(Color(e.d["def"]["body"][ck]))
	for k in (120 if e.boss else 34):
		var c: Color = cols[randi() % cols.size()] if not cols.is_empty() and k % 3 != 0 else Color(1, 0.7, 0.3)
		var off := Vector2(randf() - 0.5, randf() - 0.5) * Vector2(e.w, e.h)
		_particle(e.pos + off, (Vector2(randf() - 0.5, -randf() * 0.9) * 2.4) + off * 0.06, 35 + randi() % 35, c, k % 3 == 0, 0.08)
	for dr in e.d["drops"]:
		if randf() < float(dr[2]):
			var n := 1 + randi() % int(dr[1])
			player.inv[int(dr[0])] += n
			ui.toast("+%d %s" % [n, Defs.NAMES[int(dr[0])]], Defs.COLOR[int(dr[0])])
	if e.boss and e.d.has("def"):
		_guardian_falls(e)
	if e.type == "golem":
		items["heart"] = true
		planet_state["boss_dead"] = true
		player.inv[Defs.EMBER] += 40
		player.inv[Defs.OBSIDIAN] += 20
		ui.toast("Vulkhar falls! You claim the EMBER HEART.", Color(1, 0.7, 0.3), 6.0)
		ui.toast("+40 Ember Crystal, +20 Obsidian. The Core Siphon can now be forged.", Color(1, 0.85, 0.3), 6.0)
		shake = 18.0
		save_game()

## A biome guardian is beaten: its relic is yours, with its hoard; it stays dead on this planet.
func _guardian_falls(e: Enemy) -> void:
	var bd: Dictionary = e.d["def"]
	var biome: String = e.d["biome"]
	var dead_list: Array = planet_state.get("bosses_dead", [])
	if not dead_list.has(biome):
		dead_list.append(biome)
	planet_state["bosses_dead"] = dead_list
	var rid: String = bd["relic"]
	var rel: Dictionary = Defs.RELICS[rid]
	ui.toast("%s falls!" % bd["name"], bd["col"], 6.0)
	if not items.has(rid):
		items[rid] = true
		if rid == "lionheart":
			max_hp += 40
			hp += 40
		ui.toast("RELIC: %s. %s" % [rel["name"], rel["desc"]], Color(1.0, 0.88, 0.45), 8.0)
	var loot: Dictionary = bd["loot"]
	for mt in loot:
		player.inv[int(mt)] += int(loot[mt])
	_roll_loot(4, 1.5)
	shake = 16.0
	audio.play("rare")
	for o in enemies:
		if o.summoner == e:
			o.summoner = null
	save_game()

## the guardians of this planet's biomes, each in its lair (not the ones already beaten)
func _spawn_guardians() -> void:
	var dead_list: Array = planet_state.get("bosses_dead", [])
	for lr in builds.lair_list:
		var biome: String = lr["biome"]
		if dead_list.has(biome) or not Defs.BOSSES.has(biome):
			continue
		var d: Dictionary = Defs.boss_enemy("boss_" + biome)
		var at: Vector2 = lr["pos"]
		var ge = spawn_enemy("boss_" + biome, at + at.normalized() * (float(d["h"]) * 0.5 + 2.0))
		ge.tether = float(lr.get("tether", 60.0))       # (it stays in its lair)
		ge.ceil = float(lr.get("ceil", 60.0))

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
	if e.door_t > 0:
		return e.nav_dir           # it just opened a door: wait for it to swing open, don't turn back
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
					e.act = ""
					e.move = ""
					e.raged = false
					e.under = false
					e.trail.clear()
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
		if e.act == "":
			e.facing = -1 if dx < 0 else 1
		if tgt.dead:
			e.vx *= 0.9
		# what it knows (sees you, heard a spell, was warned) and where it is heading
		var gl := Vector2.ZERO
		if not e.boss:
			FoeAI.think(self, e, tgt, dist)
			gl = FoeAI.goal(self, e, tgt)
		if e.d.has("def"):
			BossAI.tick(self, e, tgt, dist, dx, dy, g, slow_f)
		match e.type:
			"slime", "mimic":
				# hops after you once it knows you're there; close by, a crouch and a leap aimed at you
				var busy := FoeAI.leap(self, e, tgt, dx, dy, g)
				var cjv := 5.4 if e.type == "slime" else 4.6
				var cdir2 := 0.0 if busy or gl == Vector2.ZERO else FoeAI.climb(self, e, gl, cjv, g, 5.0)
				if cdir2 != 0.0:
					# on its way to another level: little hops to the take-off point (climb jumps from there)
					if e.on_ground and e.vy >= 0.0:
						e.vx *= 0.75
						e.t -= 1
						var cgap := FoeAI.climb_gap(self, e)
						if e.t <= 0 and absf(cgap) > 4.0:
							e.vy = -2.4
							e.vx = clampf(cgap / (4.8 / maxf(g, 0.01)), -2.3, 2.3)
							e.t = 18
				elif not busy and e.on_ground:
					e.vx *= 0.75 if e.type == "slime" else 0.7
					e.t -= 1
					if e.t <= 0 and gl != Vector2.ZERO:
						var jv := 5.4 if e.type == "slime" else 4.6
						var sd := _walker_nav(e, gl.x, gl.length(), 0.0, jv, g)
						e.vx = sd * ((1.4 + randf() * 0.9) if e.type == "slime" else (1.9 + randf() * 0.8)) * slow_f
						var hop := (3.8 + randf() * 1.3) if e.type == "slime" else (3.7 + randf() * 0.8)
						var wall := _wall_height(e, sd, 56.0 if e.type == "slime" else 40.0)
						if wall > 0:
							hop = minf(jv, sqrt(2.0 * g * (wall + 5.0)))   # hop up onto the ledge
						elif wall < 0:
							e.nav_dir = -sd
							e.wander_t = 90
						e.vy = -hop
						e.t = (45 + randf() * 50) if e.type == "slime" else (28 + randf() * 25)
					elif e.t <= 0:
						# nothing to chase: the odd idle hop
						e.t = 70 + randf() * 90
						if e.type == "slime" and randf() < 0.4:
							e.vx = (1.0 if randf() < 0.5 else -1.0) * 0.7
							e.vy = -2.4
				e.vy += g * 0.3 if e.in_liquid else g
				if e.in_liquid:
					e.vy *= 0.9
			"skeleton", "archer":
				# walks toward you once it knows you're there (through doors), hops over steps; a
				# swordsman closes in and lunges, an archer keeps its distance and shoots
				var ai: Dictionary = e.d["ai"]
				var busy2 := FoeAI.melee(self, e, tgt, dx, dy) if ai.has("melee") else FoeAI.ranged(self, e, tgt, dist)
				if not busy2:
					if gl != Vector2.ZERO:
						# you're on another level: up onto the platform or ledge, or down through the floor
						# (an archer that can see you would rather shoot)
						var cdir := FoeAI.climb(self, e, gl, 3.9, g, 2.5, ai.has("melee") or not e.see)
						if cdir != 0.0:
							if e.on_ground and e.vy >= 0.0:
								e.vx += (cdir * 0.85 * slow_f - e.vx) * 0.25
						else:
							var want := gl.x
							var keep: Array = ai.get("keep", [])
							if not keep.is_empty() and e.see:
								if dist < float(keep[0]):
									want = -gl.x                  # too close: back off
								elif dist < float(keep[1]):
									want = 0.0                    # a good range: hold here
							if want == 0.0:
								if e.on_ground:
									e.vx *= 0.8
							else:
								var spd := 0.85 if ai.has("melee") else 0.75
								var kd := _walker_nav(e, want, maxf(gl.length(), 40.0) if want != gl.x else gl.length(), spd, 3.9, g)
								if e.on_ground:
									if gl.y < -14.0 and FoeAI.edge_ahead(self, e, kd):
										e.vx *= 0.5          # you're above it: it won't step off its level
									else:
										e.vx += (kd * spd * slow_f - e.vx) * 0.2
					elif e.on_ground:
						e.vx *= 0.8
				e.vy += g * 0.3 if e.in_liquid else g
			"bat":
				e.phase += 0.12
				if not FoeAI.swoop(self, e, tgt, dx, dy, dist):
					if gl != Vector2.ZERO:
						# it circles above you, waiting for its moment to dive
						var bwant := Vector2(gl.x, gl.y - (26.0 if e.see else 0.0) + sin(e.phase) * 14.0)
						var bw := _flier_steer(e, bwant)
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
				# keeps its distance and throws fire that leads you; close in and it blinks away
				e.phase += 0.05
				FoeAI.blink(self, e, tgt, dist)
				FoeAI.ranged(self, e, tgt, dist)
				if gl != Vector2.ZERO:
					var gd := gl.length()
					var ax := signf(gl.x) if gd > 45 else -signf(gl.x)
					var iw := _flier_steer(e, Vector2(ax * maxf(absf(gl.x), 10.0), gl.y - 20.0 + sin(e.phase) * 10.0))
					e.vx += iw.x * 0.05
					e.vy += iw.y * 0.05
				else:
					e.vx += (randf() - 0.5) * 0.04
					e.vy += sin(e.phase) * 0.01
				var sp2 := (0.5 if e.act == "windup" else 1.0) * slow_f
				e.vx = clampf(e.vx, -sp2, sp2)
				e.vy = clampf(e.vy, -sp2, sp2)
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
						FoeAI.shoot(self, e, tgt, "efire", 7 if enraged else 5, 0.18, 0.6)
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
		if e.under or e.move == "breach":
			e.vx = 0.0                     # (under the ground, or flung out of it: boss_ai moves it)
			e.vy = 0.0
		else:
			move_body(e)
		e.anim += absf(e.vx) * 0.2 + 0.02
		if e.stuck > 30:
			# wedged in (sand piled on, a block conjured into it): work it free to the nearest open
			# space; only one buried with no room anywhere near (a cave-in) is lost
			var freed_at := free_spot(e.pos, e.w, e.h, 20)
			if freed_at != e.pos or e.type == "mimic" or e.guard_id >= 0:
				e.pos = freed_at
				e.stuck = 0
		if e.stuck > 30 and not e.boss:
			# wedged in the ground (buried by rubble, a cave-in): it's gone
			if e.guard_id >= 0:
				_guards_alive.erase(e.guard_id)
			enemies.remove_at(k)
			continue
		if e.type != "golem" and e.type != "imp" and not e.boss:
			var l2 := to_grid(e.pos)
			if box_count(l2.x - e.w * 0.5, l2.y - e.h * 0.5, e.w, e.h, Defs.LAVA) > 0:
				_hurt_enemy(e, 0.6, 0, 0)
		if not tgt.dead and not e.under and absf(dx) < (e.w + tgt.w) * 0.5 and absf(dy) < (e.h + tgt.h) * 0.5:
			hurt(tgt, float(e.d["dmg"]), Vector2(signf(dx) * 2.2, -1.6), true)
		if not tgt.dead and not e.under and not e.trail.is_empty() and e.awake:
			# a serpent's body hurts too
			for sk in e.trail.size():
				if e.trail[sk].distance_to(tgt.pos) < BossArt.seg_radius(e.d["def"]["body"], sk) + 4.0:
					hurt(tgt, float(e.d["dmg"]) * 0.6, Vector2(signf(dx) * 2.0, -1.5), true)
					break
		if e.boss and e.d.has("def") and e.awake and not e.under:
			lights.append([e.pos, 26.0, Color(e.d["def"]["col"]) * 0.45])
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
		# the surface is gentle by day, busier at night, when the dead walk too (a swordsman or an
		# archer now and then)
		if night and randf() < 0.22:
			var undead := 0
			for e in enemies:
				if (e.type == "skeleton" or e.type == "archer") and e.guard_id < 0:
					undead += 1
			if undead < 2:
				type = "skeleton" if randf() < 0.55 else "archer"
		if type == "":
			# the biome's own creatures, by day and (more of them) by night
			if randf() < (0.5 if night else 0.32):
				type = _wild_pick(_biome_name_at(a), 4 if night else 3)
		if type == "":
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
		type = "bat" if randf() < 0.55 else _wild_pick("cave1", 3)
	elif r > sa.w:
		if randf() > 0.5:
			return
		var rk := randf()
		type = "bat" if rk < 0.3 else ("imp" if rk < 0.5 else _wild_pick("cave2", 3))
	else:
		if randf() > 0.5:
			return
		type = "imp" if randf() < 0.5 else _wild_pick("cave3", 3)
	if type == "":
		return
	var d: Dictionary = Defs.enemy_def(type)
	var pack: int = int(d["def"].get("pack", 1)) if d.has("def") else 1
	var go: String = d["def"]["go"] if d.has("def") else ""
	# Foes come in from out of sight, never popping up (or dropping in) on screen. How far the
	# view reaches from the mage, in world cells (a screen pixel is ustep * r cells across):
	var reach_x := VW * 0.5 * zoom * maxf(1.0, ustep * r) + float(d["w"]) + 10.0
	var reach_y := VH * 0.5 * zoom + float(d["h"]) + 10.0
	var cv := _view()
	var ca := atan2(cv.y, cv.x)
	if (not d["fly"] or go == "burrow" or go == "slither") and r > sa.x - 14.0:
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
			# (a pack comes together, a few strides apart)
			for pk in pack - 1:
				var pa := ga + side * float(pk + 1) * (float(d["w"]) + 6.0) / maxf(gs.x, 1.0)
				spawn_enemy(type, Vector2(cos(pa), sin(pa)) * (gpu.surf_at(pa).x + float(d["h"]) * 0.5 + 1.0))
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
			var sp := from_grid(Vector2(lx, ly))
			if r > sa.x - 14.0 and sp.length() < gpu.surf_at(atan2(sp.y, sp.x)).x + 4.0:
				continue                      # (a bird of the surface comes in through the air, not a cave)
			spawn_enemy(type, sp)
			# bats often hunt in pairs
			if type == "bat" and randf() < 0.5 and not box_solid(lx + 6.0 - d["w"] * 0.5, ly - 4.0 - d["h"] * 0.5, d["w"], d["h"]):
				spawn_enemy(type, from_grid(Vector2(lx + 6.0, ly - 4.0)))
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
	var wc: Vector2 = space.centre if space.active else Vector2.ZERO
	var a := (player.pos - wc).angle()
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
		"skiff": return items.has("skiff")
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
		"mend": return "Find the Scroll of Mending in a chest"
	return "Locked"

func recipe_affordable(r: Dictionary) -> bool:
	for k in r["cost"]:
		if player.inv[int(k)] < int(r["cost"][k]):
			return false
	return true

## H: drink a Healing Draught (35 health over a moment; one every ten seconds)
func _drink(m: Mage) -> bool:
	var n := int(items.get("potion", 0))
	if n <= 0:
		ui.toast("No Healing Draughts: forge one (C) or find one in a chest", Color(1, 0.7, 0.55), 2.0)
		return false
	if m.potion_cd > 0:
		ui.toast("Not yet: %d s before another draught" % ceili(m.potion_cd / 60.0), Color(1, 0.8, 0.6), 1.2)
		return false
	if m.hp >= m.max_hp:
		ui.toast("You're unhurt", Color(0.8, 0.95, 0.8), 1.0)
		return false
	items["potion"] = n - 1
	m.potion_cd = Defs.POTION_CD
	m.heal_left += Defs.POTION_HEAL
	audio.play("water", m.pos, 0.5)
	ui.toast("Healing Draught: %d left" % (n - 1), Color(0.6, 1.0, 0.65), 1.5)
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
	if r.has("potion"):
		items["potion"] = int(items.get("potion", 0)) + int(r["potion"])
		ui.toast("Healing Draught forged: drink it with H (%d now)" % int(items["potion"]), Color(0.6, 1.0, 0.65), 3.0)
		save_game()
		return true
	if r.has("furniture"):
		var frng := RandomNumberGenerator.new()
		frng.randomize()
		var fd: Dictionary = Build.Props.make(String(r["furniture"]), frng, null)
		player.furn.append(Build.carried_item(String(r["name"]), fd, String(r["furniture"])))
		ui.toast("%s forged: set it down in build mode (B), Satchel tab" % r["name"], Color(1, 0.82, 0.23), 3.0)
		save_game()
		return true
	if r.has("spell"):
		known.append(r["spell"])
		known.sort_custom(func(x, y): return Defs.SPELL_ORDER.find(x) < Defs.SPELL_ORDER.find(y))
		ui.toast("New spell learned: %s" % Defs.SPELLS[r["spell"]]["name"], Color(1, 0.82, 0.23), 4.0)
	match r["id"]:
		"skiff":
			items["skiff"] = randi() % 1000000      # (its seed: the shape of your skiff)
			ui.toast("Wisp Skiff forged: press K to call it to you", Color(1, 0.82, 0.23), 4.0)
			save_game()
			return true
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
		if k == KEY_F11 or (k == KEY_ENTER and ev.alt_pressed):
			set_setting("window", "windowed" if str(settings.get("window", "windowed")) != "windowed" else "fullscreen")
			ui._refresh_settings()
			return
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
		if k == KEY_B:
			_toggle_build()
			return
		if build_on and _build_key(k):
			return
		if k >= KEY_1 and k <= KEY_9:
			var n := k - KEY_1
			if n < known.size():
				sel = n
		elif k == KEY_Q or k == KEY_E:
			_cycle_material(1 if k == KEY_E else -1)
		elif k == KEY_H:
			_drink(player)
		elif k == KEY_F:
			_interact()
		elif k == KEY_K:
			call_skiff()
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
		var wheel: bool = ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if wheel and ui.mouse_over_ui(false):
			return                  # scrolling the satchel (past its end, too) never changes the spell
		if build_on and ev.button_index == MOUSE_BUTTON_LEFT:
			build_click = true
		if build_on and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_build_step(-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			return
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			dig_tap = 10
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			sel = (sel - 1 + known.size()) % known.size()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			sel = (sel + 1) % known.size()

# ------------------------------------------------------------- building --
func _toggle_build() -> void:
	build_on = not build_on
	build_prev = {}
	if build_pieces.is_empty():
		build_pieces = Build.pieces()
		build_seed = randi()
	while build_idx.size() < Build.CATS.size():
		build_idx.append(0)
	if build_on:
		var bn: String = builds.biome(Build.cell_of(player.pos).x) if builds != null else "forest"
		for si in Build.STYLES.size():
			if Build.STYLES[si][1] == bn:
				build_style = si
		_struct_key = ""
		ui.toast("Build mode: click to place · Q/E category · wheel piece · G how walls and blocks are laid · R new design · T mirror · B to leave", Color(0.95, 0.85, 0.55), 4.0)
	else:
		ui.toast("Build mode off", Color(0.8, 0.8, 0.9), 1.0)

## the pieces of the chosen category, and the chosen one
func build_list() -> Array:
	if build_cat == Build.CAT_SATCHEL:
		return Build.carried_pieces(player.furn)
	return Build.in_cat(build_pieces, build_cat)

func build_piece() -> Dictionary:
	var l := build_list()
	if l.is_empty():
		return {}
	return l[clampi(int(build_idx[build_cat]), 0, l.size() - 1)]

func _build_step(dir: int) -> void:
	var n := build_list().size()
	build_idx[build_cat] = posmod(int(build_idx[build_cat]) + dir, n)

## keys in build mode; true if the key was used
func _build_key(k: int) -> bool:
	if k == KEY_Q or k == KEY_E:
		var oi: int = Build.CAT_ORDER.find(build_cat)
		build_cat = Build.CAT_ORDER[posmod(oi + (1 if k == KEY_E else -1), Build.CAT_ORDER.size())]
		build_drag = false
		return true
	var shaped: bool = build_piece().get("kind", "") in ["wall", "block"]
	if shaped and k == KEY_G:
		build_shape = (build_shape + 1) % Build.SHAPES.size()
		if build_piece()["kind"] == "block" and build_shape == 0:
			build_shape = 1                   # blocks aren't painted
		build_drag = false
		ui.toast("Lay: " + Build.SHAPES[build_shape], Color(0.95, 0.85, 0.55), 1.0)
		return true
	if shaped and (k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT):
		build_thick = clampi(build_thick + (1 if k == KEY_BRACKETRIGHT else -1), 1, Build.THICK_MAX)
		return true
	var structure: bool = build_piece().get("kind", "") == "structure"
	if k == KEY_R:
		build_seed = randi()
		return true
	if k == KEY_T:
		if structure:
			build_style = (build_style + 1) % Build.STYLES.size()
			ui.toast("Style: " + Build.STYLES[build_style][0], Color(0.95, 0.85, 0.55), 1.0)
		else:
			build_flip = not build_flip
		return true
	if structure and (k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT):
		build_w = clampi(build_w + (4 if k == KEY_BRACKETRIGHT else -4), Build.STRUCT_W_MIN, Build.STRUCT_W_MAX)
		return true
	if structure and (k == KEY_MINUS or k == KEY_EQUAL):
		build_floors = clampi(build_floors + (1 if k == KEY_EQUAL else -1), 1, Build.STRUCT_FLOORS_MAX)
		return true
	if k >= KEY_1 and k <= KEY_9:
		var n := k - KEY_1
		if n < build_list().size():
			build_idx[build_cat] = n
		return true
	return false

func _solid_at(col: int, row: int) -> bool:
	var t := type_at(Build.cell_pos(col, row))
	var kd: int = Defs.KIND[t]
	return kd == Defs.K_SOLID or kd == Defs.K_POWDER

## room to build: air, or only weather in the way (rain, snow and ash drift through all the time and
## would make a placement flicker; what's built pushes them aside)
func _open_at(col: int, row: int) -> bool:
	var t := type_at(Build.cell_pos(col, row))
	var kd: int = Defs.KIND[t]
	return kd == Defs.K_EMPTY or kd == Defs.K_GAS or kd == Defs.K_LIQUID or t == Defs.SNOW or t == Defs.ASH

## what's in the background at a cell (1 furniture, 2 a built back wall, 3 a tree, 0 nothing
## else, -1 out of view)
func _bg_at(col: int, row: int) -> int:
	var l := to_grid(Build.cell_pos(col, row))
	return gpu.grid_bg(_gslot, int(floor(l.x)), int(floor(l.y)))

## the first row at or below `row` in column `col` that is open with something solid under it
func _floor_below(col: int, row: int, reach: int) -> int:
	for k in reach:
		if _open_at(col, row + k) and _solid_at(col, row + k + 1):
			return row + k
	return -1

## the highest floor row (smallest) among columns c0 .. c0 + w - 1, searching down from `row`; -1 if
## none of them has ground within reach
func _floor_span(c0: int, w: int, row: int, reach: int) -> int:
	var best := -1
	for i in w:
		var f := _floor_below(c0 + i, row, reach)
		if f >= 0 and (best < 0 or f < best):
			best = f
	return best

## Every tick in build mode: work out what would go where (the overlay draws it, green or red),
## and place it on a click (walls: while the button is held).
func _update_build(m: Mage) -> void:
	var piece := build_piece()
	build_prev = {}
	if piece.is_empty():
		return
	var p := _reach(m, m.input.aim)
	var cell := Build.cell_of(p)
	var kind: String = piece["kind"]
	if cell.y < -Defs.ORBIT_ROWS or cell.y >= Defs.ROWS - 40:
		return
	var cost: Dictionary = Build.payable(piece, m.inv)
	var cells := []      # [world pos, colour]
	var ok := true
	var tree_in_way := false
	if kind == "block" or (kind == "wall" and build_shape != 0):
		_update_shape(m, piece)
		return
	build_drag = false
	if kind == "wall":
		build_prev = {"circle": [p, Build.WALL_R], "ok": not cost.is_empty(), "cells": []}
		if m.input.cast and not cost.is_empty():
			var mt: int = piece["mat"]
			var budget := mini(m.inv[mt], 14)
			m.pending_place = budget
			m.pending_mat = mt
			brushes.append([p, Build.WALL_R, 10, mt, 0, budget, 0.0, m.slot])
		elif m.input.cast:
			_build_need(piece)
		build_click = false
		return
	var place := {}
	var kid := 0
	build_why = ""
	if kind == "prop" or kind == "carried":
		var d: Dictionary = Build.design(piece, build_seed) if kind == "prop" else {"rows": piece["rows"], "wall": piece["wall"]}
		kid = Build.Props.kind_id(String(piece["prop"])) if kind == "prop" else int(piece["kid"])
		var rows: Array = d["rows"]
		var wall: bool = d.get("wall", false)
		var bottom := cell.y + rows.size() / 2
		if not wall:
			# it stands on the highest ground under it (a leg may stand on a lower step)
			var pw: int = rows[0].length()
			bottom = _floor_span(cell.x - pw / 2, pw, cell.y - rows.size() / 2, 40)
		if bottom < 0:
			ok = false
			build_why = "no floor under it"
			bottom = cell.y + rows.size() / 2
		var pc := Build.prop_cells(rows, cell.x, bottom, build_flip)
		var feet := 0
		var held := 0
		for c in pc:
			var cc: Vector2i = Vector2i(int(c[0]), int(c[1]))
			# room in front, and no other furniture where it goes (a back wall behind it is fine)
			var bga := _bg_at(cc.x, cc.y)
			if not _open_at(cc.x, cc.y) or bga == 1 or bga == 3 or bga < 0:     # (3: a tree it would cut)
				if ok:
					build_why = "cell %s: %s, background %d" % [str(cc), Defs.NAMES[type_at(Build.cell_pos(cc.x, cc.y))], bga]
					build_why_cell = cc
				ok = false
				if bga == 3:
					tree_in_way = true
			if not wall and cc.y == bottom:
				feet += 1
				if _solid_at(cc.x, cc.y + 1):
					held += 1
			var ch: String = c[2]
			cells.append([Build.cell_pos(cc.x, cc.y), Color(1, 0.85, 0.3) if ch == "t" else Color.html(Build.Props.PALETTE[int(Build.Props.CHARS[ch])])])
		if not wall and held * 2 < feet:
			if ok:
				build_why = "only %d of %d feet held" % [held, feet]
			ok = false
		place = {"stamp": Build.prop_stamp(pc, kid)}
	elif kind == "door":
		var c0 := cell.x - Build.DOOR_W / 2
		var bottom2 := _floor_span(c0, Build.DOOR_W, cell.y - Build.DOOR_H / 2, 50)
		if bottom2 < 0:
			ok = false
			bottom2 = cell.y
		var r0 := bottom2 - Build.DOOR_H + 1
		for j in Build.DOOR_H:
			for i in Build.DOOR_W:
				if not _open_at(c0 + i, r0 + j):
					ok = false
				cells.append([Build.cell_pos(c0 + i, r0 + j), Color(0.6, 0.4, 0.22)])
		var dheld := 0
		for i in Build.DOOR_W:
			if _solid_at(c0 + i, bottom2 + 1):
				dheld += 1
		if dheld == 0:
			ok = false
		var mc := Build.cell_of(m.pos)
		var side := 1 if posmod(mc.x - c0, Defs.NS) < Defs.NS / 2 else -1
		var rec := _door_rec(c0, r0, Build.DOOR_W, Build.DOOR_H, side, Defs.anchor_c, 1)
		rec["open"] = true
		if _door_blocked(rec):
			ok = false
		place = {"door": rec}
	elif kind == "structure":
		var sk: String = piece["struct"]
		var key := "%s|%d|%d|%d|%d|%d|%d" % [sk, build_style, build_seed, build_w, build_floors, cell.x, cell.y]
		if key != _struct_key:
			_struct_key = key
			_struct = _plan_structure(sk, cell)
		piece["cost"] = _struct.get("cost", {})
		cost = Build.payable(piece, m.inv)
		ok = _struct.get("ok", false)
		tree_in_way = _struct.get("tree", false)
		build_prev = {"tex": _struct.get("tex"), "corner": _struct.get("corner", Vector2.ZERO), "ok": ok and not cost.is_empty(), "cells": []}
		place = {"structure": _struct}
	elif kind == "platform":
		for i in Build.PLATFORM_W:
			var cx := cell.x - Build.PLATFORM_W / 2 + i
			if not _open_at(cx, cell.y):
				ok = false
			cells.append([Build.cell_pos(cx, cell.y), Defs.COLOR[Defs.SCAFFOLD]])
		place = {"stamp": Build.platform_stamp(cell.x, cell.y)}
	if kind != "structure":
		build_prev = {"cells": cells, "ok": ok and not cost.is_empty()}
	if not build_click:
		return
	build_click = false
	build_last = "%s: cost %s, fits %s" % [piece["name"], str(cost), ok]
	if cost.is_empty():
		_build_need(piece)
		return
	if not ok:
		if _build_warn_t <= frame:
			ui.toast("A tree is in the way: fell it first" if tree_in_way else "It doesn't fit there", Color(1, 0.6, 0.5), 1.2)
			_build_warn_t = frame + 40
		return
	for mt2 in cost:
		m.inv[int(mt2)] -= int(cost[mt2])
	if place.has("stamp"):
		stamps.append(place["stamp"])
		build_last_stamp = place["stamp"]
	if kind == "carried":
		m.furn.remove_at(int(piece["item"]))      # it's set down: no longer carried
	if place.has("door"):
		var rec2: Dictionary = place["door"]
		doors.append(rec2)
		_set_door(rec2, false)
	if place.has("structure"):
		var sbp = place["structure"]["bp"]
		# (anchored near you, as it was planned and previewed: Build.cell_pos)
		stamps.append({"x0": posmod(sbp.x0, Defs.NS), "y0": sbp.y0, "w": sbp.w, "h": sbp.h, "data": sbp.c, "ax": Defs.anchor_c, "aw": 1})
		for dd in sbp.doors:
			doors.append(_door_rec(sbp.x0 + int(dd[0]), sbp.y0 + int(dd[1]), int(dd[2]), int(dd[3]), int(dd[4]), Defs.anchor_c, 1))
		_struct_key = ""          # it's there now: work out the next one afresh
	audio.play("place", p, 0.9)
	for k in 8:
		_particle(p + Vector2(randf() - 0.5, randf() - 0.5) * 6.0, Vector2(randf() - 0.5, -randf()) * 0.6, 18 + randi() % 12, Color(0.95, 0.85, 0.55), true, 0.02)

## Plans a structure under the cursor: a house or room stands on the highest ground under its
## footprint, with a plinth of its own stone down to the ground under the rest (at most
## Build.FOUND_MAX deep); a roof rests on the first solid row under the cursor (put it on a room's top).
## Everything it would build must land on open space. Returns {ok, cost, tex, corner, bp}.
## Back walls and blocks laid as a shape: press where it starts, drag, let go where it ends (right
## click cancels). Only the cells with room take it (a back wall where there is none yet and no tree
## or furniture; a block where there's open space and nobody standing); one material per cell.
func _update_shape(m: Mage, piece: Dictionary) -> void:
	var mt: int = piece["mat"]
	var back: bool = piece["kind"] == "wall"
	var shape: int = maxi(build_shape, 1)
	var d := m.input.aim - m.pos
	if d.length() > Build.SHAPE_REACH:
		d = d.normalized() * Build.SHAPE_REACH
	var cell := Build.cell_of(m.pos + d)
	if m.input.dig and build_drag:
		build_drag = false
		build_click = false
		return
	if build_click and not build_drag:
		build_drag = true
		build_drag_from = Build.cell_pos(cell.x, cell.y)
	build_click = false
	var from := Build.cell_of(build_drag_from) if build_drag else cell
	var cells: Array = Build.shape_cells(from, cell, shape, build_thick)
	var too_big := cells.size() > Build.SHAPE_MAX_CELLS
	var good := []
	var prev := []
	var col := Color.hex((Defs.PAL[mt * 4] << 8) | 0xff)
	if not too_big:
		for c in cells:
			var bga := _bg_at(c.x, c.y)
			var fits := false
			if back:
				fits = bga == 0
			else:
				fits = bga >= 0 and _open_at(c.x, c.y) and not _body_in(Build.cell_pos(c.x, c.y))
			if fits:
				good.append(c)
				prev.append([Build.cell_pos(c.x, c.y), col])
	var need := good.size()
	var ok: bool = not too_big and need > 0 and need <= m.inv[mt]
	build_prev = {"cells": prev, "ok": ok}
	var what := "%s %s: %d %s" % [Build.SHAPES[shape], piece["name"], need, Defs.NAMES[mt]]
	if too_big:
		what = "Too big to lay in one go (at most %d cells)" % Build.SHAPE_MAX_CELLS
	elif need > m.inv[mt]:
		what += " (you have %d)" % m.inv[mt]
	build_prev["text"] = what
	if build_drag and not m.input.cast:
		build_drag = false
		if ok:
			stamps.append(Build.shape_stamp(good, mt, back))
			build_last_stamp = stamps[stamps.size() - 1]
			m.inv[mt] -= need
			build_last = "%s: %d cells" % [piece["name"], need]
			audio.play("place", m.pos + d, 0.6)
		elif need > m.inv[mt]:
			ui.toast("%s needs %d %s (you have %d)" % [piece["name"], need, Defs.NAMES[mt], m.inv[mt]], Color(1, 0.7, 0.5), 2.0)
		elif need == 0 and not too_big:
			ui.toast("No room there", Color(1, 0.6, 0.5), 1.2)
		build_last = build_last if ok else "%s: not laid (%s)" % [piece["name"], what]

## is a mage or a foe standing at this world position (a block laid there would trap them)?
func _body_in(wp: Vector2) -> bool:
	var bodies: Array = players.duplicate()
	bodies.append_array(enemies)
	for b in bodies:
		var dd: Vector2 = wp - b.pos
		var up: Vector2 = b.pos.normalized()
		var rt := Vector2(-up.y, up.x)
		if absf(dd.dot(rt)) <= b.w * 0.5 + 1.0 and absf(dd.dot(up)) <= b.h * 0.5 + 1.0:
			return true
	return false

func _plan_structure(sk: String, cell: Vector2i) -> Dictionary:
	var w := build_w
	var trees := false
	var floor_row := -1
	if sk == "roof":
		for k in 80:
			if _solid_at(cell.x, cell.y + k):
				floor_row = cell.y + k
				break
	else:
		floor_row = _floor_span(cell.x - w / 2, w, cell.y - 30, 90)
	if floor_row < 0:
		return {"ok": false, "cost": {}}
	var r := Build.structure(builds, sk, build_style, build_seed, w, build_floors, cell.x, floor_row)
	var bp = r["bp"]
	var ox: int = r["ox"]
	var lb: int = r["lb"]
	var st: Dictionary = r["st"]
	var ok := true
	if sk != "roof":
		for i in range(ox, ox + w):
			var col: int = bp.x0 + i
			var k2 := 1
			while k2 <= Build.FOUND_MAX and _open_at(col, floor_row + k2):
				bp.fg(i, lb + k2, st["found"])
				k2 += 1
			if k2 > Build.FOUND_MAX:
				ok = false                      # too far above the ground there
	if ok:
		# everything it builds lands on open space, and it doesn't build over walls or furniture
		# already there (yours or the planet's)
		for j in bp.h:
			for i2 in bp.w:
				var v: int = bp.c[j * bp.w + i2]
				if (v & 255) != 255 and not _open_at(bp.x0 + i2, bp.y0 + j):
					ok = false
					break
				var sbg := _bg_at(bp.x0 + i2, bp.y0 + j)
				if ((v >> 8) & 255) != 255 and sbg != 0:
					ok = false
					trees = sbg == 3
					break
			if not ok:
				break
	var tex := ImageTexture.create_from_image(Build.preview_image(bp, ok))
	return {"ok": ok, "tree": trees, "cost": Build.structure_cost(bp, bp.doors.size()), "tex": tex,
		"corner": Build.cell_pos(bp.x0 + bp.w - 1, bp.y0), "bp": bp}

func _build_need(piece: Dictionary) -> void:
	if _build_warn_t > frame:
		return
	_build_warn_t = frame + 60
	ui.toast("%s needs %s" % [piece["name"], Build.cost_text(piece["cost"]) + ((" (or " + Build.cost_text(piece["alt"]) + ")") if piece.has("alt") else "")], Color(1, 0.7, 0.5), 2.0)

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
## ---- save slots: each its own folder under saves/ (slot_1, slot_2, slot_3) ----
const SLOTS := 3
var slot := 1                 # the slot being played
var played := 0.0             # seconds played in this slot

func _slot_dir(n: int) -> String:
	return _real_save_dir().path_join("slot_%d" % n)

## what the title screen shows for a slot ({} if it's empty)
func slot_info(n: int) -> Dictionary:
	var path := _slot_dir(n).path_join("progress.json")
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var pl: Dictionary = Defs.make_planet(int(d.get("planet", 0)))
	var saved := float(d.get("saved", FileAccess.get_modified_time(path)))
	return {"planet": pl.get("name", "?"), "tier": int(d.get("tier", 1)), "spells": (d.get("known", []) as Array).size(),
		"played": float(d.get("played", 0.0)), "saved": saved}

## Play a slot: carry on with its journey, or start a new one in an empty slot.
func start_slot(n: int) -> void:
	slot = clampi(n, 1, SLOTS)
	start_game(not slot_info(slot).is_empty())

## Erase a slot's journey (its progress and every world in it).
func delete_slot(n: int) -> void:
	var dir := _slot_dir(n)
	var d := DirAccess.open(dir)
	if d == null:
		return
	for fn in d.get_files():
		d.remove(fn)

## Saves from before there were slots (in saves/ itself, or older still in Godot's user folder)
## become slot 1.
func _migrate_old_saves() -> void:
	var root := _real_save_dir()
	var s1 := _slot_dir(1)
	if FileAccess.file_exists(s1.path_join("progress.json")):
		return
	DirAccess.make_dir_recursive_absolute(s1)
	var d := DirAccess.open(root)
	if d != null and FileAccess.file_exists(root.path_join("progress.json")):
		for fn in d.get_files():
			if fn == "progress.json" or (fn.begins_with("world_") and fn.ends_with(".wfw")):
				DirAccess.rename_absolute(root.path_join(fn), s1.path_join(fn))
	elif FileAccess.file_exists(OLD_SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(OLD_SAVE_PATH), s1.path_join("progress.json"))

## Esc menu: save everything and go back to the title (to pick another slot).
func quit_to_title() -> void:
	if not (state == "play" or state == "forge" or state == "dead"):
		return
	if build_on:
		_toggle_build()
	save_game()
	save_world(true)
	state = "title"
	stamps.clear()
	brushes.clear()
	dead = false
	player.dead = false
	player.hp = player.max_hp
	player.heal_left = 0.0
	ui.hide_death()
	ui.hide_forge()
	ui.hud.visible = false
	if ui.settings_panel.visible:
		ui.toggle_settings()
	ui.show_title(true)

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
		items = {"potion": 2}       # two draughts to start with; health doesn't come back by itself
		player.furn = []
		played = 0.0
	_enter_planet(int(s["planet"]) if s != null else 0)
	ui.hide_loading()
	ui.show_hud()
	state = "play"
	if s == null:
		ui.toast("Right-click to excavate. Left-click casts your selected spell.", Color.WHITE, 7.0)
		ui.toast("Press C to open the Wisp Forge. Press M to zoom out and see the whole planet.", Color(1, 0.82, 0.23), 9.0)
	save_game()

func _enter_planet(index: int) -> void:
	_make_world(index, false)
	_respawn()
	if _loaded and planet_state.has("player"):
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
	if not _loaded:
		save_world(false)
	ui.toast("%s: %s" % [planet["name"], planet["desc"]], Color(0.8, 0.95, 0.9), 6.0)

## Flying through space toward another planet: it is made while you fly (`_make_world` spread over
## frames; the GPU has nothing else to do out there), without moving you or the skiff you ride.
## `travelling` is set meanwhile (nothing saves or draws from the GPU), `travel_progress` runs 0..1.
## The planet you left must have been saved first (space.gd does). Await it.
func arrive_planet(index: int) -> void:
	travelling = true
	travel_progress = 0.0
	_phases.clear()
	_phase_t = Time.get_ticks_usec()
	await _make_world(index, true)
	travelling = false
	travel_progress = 1.0
	if testing:
		print("[travel] slowest steps (ms): ", _phases, "; making each shader (ms): ", gpu.create_ms)

var _phases := {}
var _phase_t := 0

## (making a planet in the background: the longest stretch of work between two frames, per step)
func _phase(nm: String) -> void:
	var now := Time.get_ticks_usec()
	_phases[nm] = maxi(int(_phases.get(nm, 0)), (now - _phase_t) / 1000)
	_phase_t = now

## (after a frame's wait: the next step's time starts here)
func _phase_go() -> void:
	_phase_t = Time.get_ticks_usec()

## Waits (a frame at a time) for a world still being written in the background.
func saves_done() -> void:
	while _save_task >= 0 and not WorkerThreadPool.is_task_completed(_save_task):
		await get_tree().process_frame
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1

var travelling := false
var travel_progress := 0.0
var _loaded := false              # (the planet just made came from its save)

## Makes planet `index` the one the GPU holds: its geometry (a planet of another size makes the GPU
## world again: the shaders have the geometry built in), its surface, its saved world or a fresh one
## with its structures settled, then chests, doors, foes. All at once from the title, or a step a
## frame when `arriving` from space.
func _make_world(index: int, arriving: bool) -> void:
	var tree := get_tree()
	planet = Defs.make_planet(index)
	if absf(float(planet["radius"]) - Defs.RS0) > 0.5:
		Defs.set_geometry(float(planet["radius"]))
		gpu.cleanup()
		var ok := false
		if arriving:
			_phase("free the old world")
			ok = await gpu.init_async()
			_phase_go()
		else:
			ok = gpu.init()
		if not ok:
			push_error(gpu.error_text)
	gpu.fresh = false
	travel_progress = 0.2
	if arriving:
		await saves_done()          # (the planet you left may still be being written)
		_phase_go()
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
		var kept := {"boss_dead": planet_state.get("boss_dead", false), "bosses_dead": planet_state.get("bosses_dead", [])}
		loaded = false
		planet_state = kept
		print("[Wisp Forge] regenerating %s with the new structure generator" % planet["name"])
	planet_state["gen"] = GEN_VERSION
	_loaded = loaded
	if arriving:
		_phase("surface and load")
		await tree.process_frame
		_phase_go()
	builds = Buildings.new()
	if arriving:
		# (planning touches no GPU and no nodes: it runs beside the game)
		var task := WorkerThreadPool.add_task(builds.plan.bind(planet, gpu.surface, spawn_angle, boss_a, not loaded))
		_phase("start planning")
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
			_phase_go()
		WorkerThreadPool.wait_for_task_completion(task)
	else:
		builds.plan(planet, gpu.surface, spawn_angle, boss_a, not loaded)
	travel_progress = 0.35
	if not loaded:
		var tg0 := Time.get_ticks_usec()
		var jobs: Array = gpu.generate_prepare(spawn_angle, boss_info, builds.sites)
		for k in jobs.size():
			gpu.generate_band(jobs[k])
			if arriving and k % 2 == 1:
				travel_progress = 0.35 + 0.4 * float(k) / float(jobs.size())
				_phase("generate")
				await tree.process_frame
				_phase_go()
		gpu.stamp(builds.structs, int(planet["seed"]))
		# let the ruins fall into ruin: unsupported pieces drop and break before you arrive
		if arriving:
			for k in 75:
				gpu.settle(builds.settle, 0.0, 2)
				travel_progress = 0.75 + 0.2 * float(k) / 75.0
				_phase("stamp and settle")
				await tree.process_frame
				_phase_go()
		else:
			var tg1 := Time.get_ticks_usec()
			gpu.settle(builds.settle, 0.0, 150)
			if testing:
				print("[gen] cells and stamping %d ms, settling %d ms (%d areas)" % [(tg1 - tg0) / 1000, (Time.get_ticks_usec() - tg1) / 1000, builds.settle.size()])
		print("[Wisp Forge] %s: %d structures" % [planet["name"], builds.structs.size()])
		builds.structs.clear()
	_make_chests(loaded)
	_make_doors(loaded)
	if chunks == null:
		chunks = Chunks.new(self)
	chunks.clear()
	stamps.clear()
	brushes.clear()
	# the skiff, where it was left on this planet (one you arrive in comes with you)
	var riding: bool = arriving and player.aboard != null
	if not riding:
		player.aboard = null
		skiff = null
		if loaded and planet_state.has("skiff") and items.has("skiff"):
			var sk: Dictionary = planet_state["skiff"]
			skiff = Skiff.make(int(sk.get("seed", items["skiff"])))
			var sp: Array = sk["pos"]
			skiff.pos = Vector2(float(sp[0]), float(sp[1]))
			skiff.ang = float(sk.get("ang", 0.0))
			skiff.facing = int(sk.get("facing", 1))
			skiff.look = float(skiff.facing)
			if sk.has("cells"):
				skiff.load_cells(sk["cells"])     # (as it was: whatever was built in it too)
	enemies.clear()
	boss_clouds.clear()
	_guards_alive.clear()
	projs.clear()
	parts.clear()
	var bd := Vector2(cos(boss_a), sin(boss_a))
	if not planet_state.get("boss_dead", false):
		spawn_enemy("golem", bd * (boss_info.y - boss_info.w + float(Defs.ENEMY["golem"]["h"]) * 0.5 + 2.0))
	_spawn_guardians()
	if loaded:
		time = float(planet_state.get("time", time))
	if arriving:
		_phase("chests, doors, foes")

# ================================================================= skiff ===
## The skiff on this planet: flown by whoever sits in its first seat (hold cast: toward the cursor),
## otherwise falling and settling on its keel under its own weight. Away from every collision grid it
## waits where it is. Flown out of the top of the orbit band, it carries its riders into space.
func _update_skiff() -> void:
	if skiff == null:
		return
	_use_grid(player)
	var pl = skiff.pilot()
	if pl == null and not in_grid(skiff.pos, 40.0):
		return
	var g := 0.17 * gravity_at(skiff.pos)
	var want: Vector2 = skiff.steer(pl.input) if pl != null and state == "play" else Vector2.ZERO
	var high: bool = skiff.pos.length() > Defs.R_TOP
	skiff.centre = Vector2.ZERO
	# faster above the air; with nobody at the controls the air drags at it as it falls
	skiff.fly(want, pl != null, g, false, Skiff.CRUISE_HIGH if high else Skiff.CRUISE, 0.999 if high else 0.97)
	skiff.advance(_skiff_solid if in_grid(skiff.pos, 40.0) else Callable())
	var up: Vector2 = skiff.pos.normalized()
	if skiff.pos.length() > Defs.R_SPACE - 9.5:
		if pl != null and skiff.vel.dot(up) > 0.0:
			space.try_enter()
		if not space.active:
			skiff.pos = up * (Defs.R_SPACE - 9.5)
			skiff.vel -= up * maxf(skiff.vel.dot(up), 0.0)
	if skiff.thrusting:
		_skiff_exhaust()
	# coming down fast through the air, it glows where it meets it
	if skiff.pos.length() < Defs.R_TOP and skiff.vel.length() > Skiff.CRUISE + 1.0 and skiff.vel.dot(up) < 0.0:
		var lead: Vector2 = skiff.pos + skiff.vel.normalized() * 14.0
		for k in 2:
			_particle(lead + Vector2(randf() - 0.5, randf() - 0.5) * 16.0, -skiff.vel * (0.3 + randf() * 0.3), 10 + randi() % 8, Color8(255, 170, 90), true, 0.0)

## the wisp engine's glow streaming from the stern
func _skiff_exhaust() -> void:
	var back: Vector2 = -skiff.nose()
	var stern: Vector2 = skiff.to_world(Vector2(-skiff.com.x + 1.0, 0.0))
	for k in 2:
		_particle(stern + Vector2(randf() - 0.5, randf() - 0.5) * 4.0, back * (0.8 + randf() * 1.2) + skiff.vel * 0.7,
			14 + randi() % 10, Color8(150, 170, 255), true, 0.0)
	if not space.active:
		lights.append([stern, 40.0, Color(0.6, 0.7, 1.3)])

## a rider sits in their seat: they go where the skiff goes, breathe its air, and don't fall
func _ride(m: Mage) -> void:
	var k: int = skiff.seat_of(m) if skiff != null else -1
	if k < 0:
		m.aboard = null
		return
	m.pos = skiff.seat_world(k, m.h)
	m.vx = 0.0
	m.vy = 0.0
	m.on_ground = true
	m.floating = false
	m.air_time = 0
	m.facing = skiff.facing
	m.breath = minf(m.max_breath, m.breath + 4.0)
	m.mana = minf(m.max_mana, m.mana + m.mana_regen)
	if m.iframes > 0:
		m.iframes -= 1

## where the skiff's hull meets the world
func _skiff_solid(p: Vector2) -> bool:
	var kd: int = Defs.KIND[type_at(p)]
	return kd == Defs.K_SOLID or kd == Defs.K_POWDER

func _skiff_fits() -> bool:
	for b in skiff.outline:
		if _skiff_solid(skiff.to_world(b)):
			return false
	return true

## K: the skiff answers its maker, set down beside you wherever it was (it's wisp-bound)
func call_skiff() -> bool:
	if not items.has("skiff"):
		ui.toast("You have no skiff yet: forge one at the Wisp Forge (C)", Color(1, 0.7, 0.5), 2.5)
		return false
	if player.aboard != null or space.active:
		return false
	if skiff == null:
		skiff = Skiff.make(int(items["skiff"]))
	for k in Skiff.SEATS:
		if skiff.riders[k] != null:
			skiff.riders[k].aboard = null
			skiff.riders[k] = null
	_use_grid(player)
	var a := atan2(player.pos.y, player.pos.x)
	var right := basis_r(a)
	var up := player.pos.normalized()
	var placed := false
	for side in [player.facing, -player.facing]:
		for rise in range(0, 90, 3):
			skiff.pos = player.pos + right * float(side) * (skiff.w * 0.5 + 8.0) + up * (6.0 + rise)
			skiff.ang = right.angle()
			skiff.facing = 1
			skiff.look = 1.0
			if _skiff_fits():
				placed = true
				break
		if placed:
			break
	if not placed:
		skiff.pos = player.pos + up * (skiff.h + 30.0)
	skiff.vel = Vector2.ZERO
	for n in 30:
		_particle(skiff.pos + Vector2(randf() - 0.5, randf() - 0.5) * Vector2(skiff.w, skiff.h), Vector2(randf() - 0.5, randf() - 0.5) * 0.6, 30 + randi() % 20, Color8(150, 190, 255), true, 0.0)
	audio.play("blink", skiff.pos, 0.7)
	ui.toast("Your skiff answers. F to board", Color(0.7, 0.85, 1.0), 2.5)
	return true

## F by the skiff: board it, or step out of it
func _skiff_interact(m: Mage) -> bool:
	if skiff == null:
		return false
	if m.aboard != null:
		if not space.active and skiff.vel.length() > 3.0:
			ui.toast("Too fast to step out", Color(1, 0.7, 0.5), 1.5)
			return true
		skiff.leave(m)
		m.aboard = null
		# out beside it, behind the cockpit (on top of it if that's blocked)
		var out: Vector2 = skiff.to_world(Vector2(-skiff.com.x - 6.0, float(skiff.h) - skiff.com.y - m.h * 0.5 - 1.0))
		_use_grid(m)
		if box_solid(to_grid(out).x - m.w * 0.5, to_grid(out).y - m.h * 0.5, m.w, m.h):
			out = skiff.to_world(Vector2(0.0, -skiff.com.y - m.h * 0.5 - 2.0))
		m.pos = out
		m.vx = 0.0
		m.vy = 0.0
		if space.active:
			space.vel = skiff.vel
		return true
	if m.pos.distance_to(skiff.pos) < skiff.w * 0.5 + 10.0:
		if skiff.board(m):
			m.aboard = skiff
			ui.toast("Aboard. Fly with WASD (or hold cast toward the cursor); F to step out", Color(0.7, 0.85, 1.0), 3.0)
		else:
			ui.toast("The skiff is full", Color(1, 0.7, 0.5), 1.5)
		return true
	return false

func _respawn() -> void:
	var rs: float = gpu.surf_at(spawn_angle).x
	player.pos = Vector2(cos(spawn_angle), sin(spawn_angle)) * (rs + 30.0)
	var home = _home_pos() if gpu != null else null
	if home != null:
		player.pos = home
	player.vx = 0
	player.vy = 0
	player.grid_g = player.pos
	player.grid_a = atan2(player.pos.y, player.pos.x)
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
const GEN_VERSION := 33            # bump when the structure generator changes; older planets regenerate
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
	if key == "window":
		_apply_window()
	_apply_volumes()

## Windowed, fullscreen (a borderless window covering the screen) or exclusive fullscreen (the game
## takes over the display). F11 switches between windowed and fullscreen. The test mode stays windowed.
func _apply_window() -> void:
	if testing:
		return
	var want := DisplayServer.WINDOW_MODE_WINDOWED
	match str(settings.get("window", "windowed")):
		"fullscreen":
			want = DisplayServer.WINDOW_MODE_FULLSCREEN
		"exclusive":
			want = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)

func _apply_volumes() -> void:
	if audio:
		audio.music_volume = float(settings["music"]) / 100.0
		audio.sfx_volume = float(settings["sound"]) / 100.0

## Saves live in "Wisp Forge/saves" so the whole game stays in one portable folder.
## The test mode uses its own folder inside it, so your real saves are never touched.
func _save_dir() -> String:
	var d := _real_save_dir().path_join("test" if testing else "slot_%d" % slot)
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
		"max_hp": max_hp, "max_mana": max_mana, "mana_regen": mana_regen, "heat_ward": heat_ward, "items": items, "mat": mat,
		"furn": player.furn, "saved": Time.get_unix_time_from_system(), "played": played}
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func _load_save():
	var path := _save_path()
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
	played = float(s.get("played", 0.0))
	player.furn = []
	for it in s.get("furn", []):
		if typeof(it) == TYPE_DICTIONARY and it.has("rows") and not (it["rows"] as Array).is_empty():
			player.furn.append({"name": str(it.get("name", "Furniture")), "rows": Array(it["rows"]), "wall": bool(it.get("wall", false)), "kind": int(it.get("kind", 0))})


# ============================================================ world files ===
## The whole planet (every cell) is saved compressed, so the world you changed is the world you
## come back to. Saving reads the cells back from the GPU, then compresses and writes on a worker
## thread so play doesn't stutter.
func _world_path(i: int) -> String:
	return _save_dir().path_join("world_%d.wfw" % i)

func save_world(blocking: bool, without_skiff := false) -> void:
	if planet.is_empty() or gpu == null or gpu.rd == null or travelling:
		return
	if _save_task >= 0:
		if not WorkerThreadPool.is_task_completed(_save_task):
			if not blocking:
				return
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	# pieces still tumbling go into the world first, so nothing is lost
	if chunks != null and not chunks.list.is_empty():
		chunks.settle_all()
	if not stamps.is_empty():
		gpu.stamp(stamps, frame)
		stamps.clear()
	var raw: PackedByteArray = gpu.read_world()
	var meta := _world_meta(without_skiff)
	var path := _world_path(int(planet["index"]))
	if blocking:
		_write_world_file(path, raw, meta)
	else:
		_save_task = WorkerThreadPool.add_task(_write_world_file.bind(path, raw, meta))

## save_world, with the world read back from the GPU a slice a frame (space travel: the GPU rests
## out there, so the world can't change meanwhile) and written on another thread. Await it.
func save_world_async(without_skiff := false) -> void:
	if planet.is_empty() or gpu == null or gpu.rd == null or travelling:
		return
	await saves_done()
	if chunks != null and not chunks.list.is_empty():
		chunks.settle_all()
	if not stamps.is_empty():
		gpu.stamp(stamps, frame)
		stamps.clear()
	var meta := _world_meta(without_skiff)
	var path := _world_path(int(planet["index"]))
	var raw: PackedByteArray = await gpu.read_world_async()
	_save_task = WorkerThreadPool.add_task(_write_world_file.bind(path, raw, meta))

## the planet's own state as saved with its cells: where you are, the skiff, chests, doors, time
func _world_meta(without_skiff: bool) -> String:
	planet_state["player"] = [player.pos.x, player.pos.y]
	if space.active:
		# (saved while out in space: you, and the skiff, are kept just above where you'd come back down)
		var back: Vector2 = space.safe_return()
		planet_state["player"] = [back.x, back.y]
	if skiff != null and not without_skiff:
		var sp: Vector2 = skiff.pos
		if space.active and (player.aboard == skiff or skiff.pos.length() > Defs.R_SPACE - 9.5):
			sp = space.safe_return()
		planet_state["skiff"] = {"pos": [sp.x, sp.y], "ang": skiff.ang, "facing": skiff.facing, "seed": skiff.design_seed,
			"cells": skiff.save_cells()}
	else:
		planet_state.erase("skiff")
	var cs := []
	for c in chests:
		cs.append([c.pos.x, c.pos.y, c.opened])
	planet_state["chests"] = cs
	var ast = space.rocks_state(int(planet["index"]))
	if ast != null:
		planet_state["asteroids"] = ast
	var ds := []
	for d in doors:
		ds.append([d["pos"].x, d["pos"].y, d["w"], d["h"], d["side"], d["col"], d["row"], d["open"], d.get("swing", d["side"]), d.get("cells", []), _door_ax(d), int(d.get("aw", 1))])
	planet_state["doors"] = ds
	planet_state["time"] = time
	return JSON.stringify(planet_state)

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
	if space.active:
		return "Space"
	var a := atan2(player.pos.y, player.pos.x)
	var r := player.pos.length()
	var sa: Vector4 = gpu.surf_at(a)
	var sb: Vector4 = gpu.surf_b(a)
	var b := _biome_at(a)
	if r > Defs.R_TOP:
		return "Orbit"
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


# ================================================================ profiler ==
func prof_add(sec: String, us: int) -> void:
	var p = prof.get(sec)
	if p == null:
		p = [0.0, 0.0, 0, 0.0]      # average, recent peak, this frame, highest since prof_reset()
		prof[sec] = p
	p[2] += us

func _prof_frame() -> void:
	for k in prof:
		var p: Array = prof[k]
		p[0] = lerpf(p[0], float(p[2]), 0.05)
		p[1] = maxf(p[1] * 0.995, float(p[2]))
		p[3] = maxf(p[3], float(p[2]))
		p[2] = 0

## the biggest costs: "name 1.2 (peak 4.0)" in milliseconds, largest average first
func prof_text(n := 8, sep := " · ") -> String:
	var keys := prof.keys()
	keys.sort_custom(func(a, b): return prof[a][0] > prof[b][0])
	var parts: Array = []
	for k in keys.slice(0, n):
		parts.append("%s %.2f (peak %.1f)" % [k, prof[k][0] / 1000.0, prof[k][1] / 1000.0])
	return sep.join(parts)

func prof_reset() -> void:
	prof.clear()
