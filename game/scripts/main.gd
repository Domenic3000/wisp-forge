extends Node2D
## Wisp Forge (Godot) — main game: frame loop, player, enemies, spells,
## crafting, weather, saving and planet travel. The world itself lives on the
## GPU (gpu_world.gd); this script reads back a collision grid around the
## player every frame and sends "brushes" (dig / explode / place) to the GPU.

const GpuWorld := preload("res://scripts/gpu_world.gd")
const UI := preload("res://scripts/ui.gd")
const Overlay := preload("res://scripts/overlay.gd")
const MapView := preload("res://scripts/map_view.gd")
const Space := preload("res://scripts/space.gd")
const BossAI := preload("res://scripts/boss_ai.gd")
const Ecology := preload("res://scripts/ecology.gd")
const BossArt := preload("res://scripts/boss_art.gd")
const Skiff := preload("res://scripts/skiff.gd")
const Buildings := preload("res://scripts/buildings.gd")
const Build := preload("res://scripts/build.gd")
const FoeAI := preload("res://scripts/foe_ai.gd")
const Nav := preload("res://scripts/nav.gd")
const Chunks := preload("res://scripts/chunks.gd")
const Towns := preload("res://scripts/towns.gd")
const Workshops := preload("res://scripts/workshops.gd")
const Summoning := preload("res://scripts/summoning.gd")
const WorkshopArt := preload("res://scripts/workshop_art.gd")
const Vfx := preload("res://scripts/vfx.gd")
const Weather := preload("res://scripts/weather.gd")
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

## A workshop station (workshops.gd, Defs.STATIONS): one object standing in the world, like a chest.
## It falls and lands whole; what it's loaded with, its fire and what it made travel with it.
class Station extends Body:
	var kind := "kiln"
	var store := {}           # material -> how many are loaded (what it works)
	var out := {}             # what it made: "m<material>" or an items key -> how many
	var fuel := 0.0           # ticks of fire left
	var heat := 0.0           # 0 cold .. 1 at full heat
	var prog := 0.0           # the batch under way (ticks at full heat)
	var cur := ""             # the process it's working (Defs.PROCESS id)
	var lit := false
	var unsup_t := 0
	var ritual := 0           # an altar calling a guardian: ticks left (summoning.gd)
	var summon := ""          # whose
	var summon_at := Vector2.ZERO
	func _init() -> void:
		step_h = 0

func new_station(kind: String) -> Station:
	var st := Station.new()
	st.kind = kind
	st.w = float(Defs.STATIONS[kind]["w"])
	st.h = float(Defs.STATIONS[kind]["h"])
	return st

## A villager (towns.gd): walks the street, or keeps a shop (`keeper`, its `role` a Defs.SHOPS key)
class Villager extends Body:
	var fseed := 0
	var name := ""
	var role := "folk"
	var keeper := false
	var town: Dictionary
	var house: Dictionary
	var goal_c := 0.0
	var idle_t := 0
	var talk_t := 0
	var talks := 0
	var say := ""
	var say_t := 0
	var gone := false
	var job: Dictionary          # (the house they work in, or {})
	var inside: Dictionary       # (the house they're in now, or {}: the street)
	var idx := 0                 # (which resident of the village)
	var asker := false           # (the one with a request for you: towns.gd `mark_of`)
	var offer: Dictionary        # (a request said out loud, waiting for a second F)
	var offer_t := 0
	var asleep := false
	var fade := 0                # (stepping through a house's side: towns.gd `_step`)
	var fade_to := Vector2.ZERO
	var fade_in: Dictionary
	var block_t := 0
	var bed: Dictionary          # (their bed in their house, from buildings.gd `_beds`, or {})
	var lying := false           # (asleep lying down: in bed, or on a bedroll)
	var lie_next := false        # (lying down once the fade's halfway)
	var bedroll := false
	var lie_head := Vector2.ZERO # (where their head is, lying)
	var lie_ok := false          # (lying put down on the floor or mattress the world really has there)
	var wake_at := Vector2.ZERO  # (where they stand up again)

func new_chest():
	return Chest.new()

func new_villager() -> Villager:
	return Villager.new()

class Enemy extends Body:
	var type := ""
	var provoked := false        # it has been hurt (the Amber Totem keeps only unprovoked creatures calm)
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
	var summoned := ""         # a guardian called at an altar: its biome (summoning.gd)
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
	# its way about (nav.gd; foe_ai.gd nav_walk / nav_fly)
	var path := PackedVector2Array()   # feet points (walkers) or middles (fliers) along its way, world
	var path_i := 1            # the next point of it
	var path_t := 0            # frames till it looks for a way again
	var path_goal := Vector2.ZERO
	var path_key := ""
	var path_ok := false       # the way gets all the way there
	var fly_open := false      # (a flier: nothing in the way, it flies straight)
	var wall_t := 0            # frames in a row it has been pressed against a wall
	var hold_t := 0            # frames it stands still before looking for another way
	var lost_t := 0            # frames standing where its way-finding graph has no room for it
	var nav_air := false       # in the air on a jump of its way
	var nav_gap := false       # (that jump is across a gap)
	var unreach_t := 0         # frames you've been out of its reach (a guardian then smashes in)
	var reach_ok := true       # (it can get to you: looked at now and then)
	var surge_t := 0           # Vulkhar out of reach: frames to his next surge (a stream of fire, imps called up)
	var surge_n := 0           # (the surge's shots still to come)
	var roam := 0.0            # (a creature out of reach: where it roams to, cells along the ground from itself)
	var breach := false        # this charge smashes through walls
	var breach_hits := 0       # (how many holes this breach has blasted)
	var nav_dx := 0.0          # (grid cells across to the next point of its way)
	var arena := 0.0           # a guardian's arena: how far either side of its middle (it wakes when you come in)
	# its life in the world (scripts/ecology.gd)
	var pose := ""             # a frame of its daily life ("graze", "sleep", "croak", "perch", "wind")
	var asleep := false
	var doing := ""            # what it's doing with itself ("wander", "graze", "drink", "perch"...)
	var doing_t := 0
	var goal_p := Vector2.ZERO # where that takes it (world; ZERO: nowhere in particular)
	var fear_t := 0            # frames it keeps running from `fear_from`
	var fear_from := Vector2.ZERO
	var flee_dir := 0          # cornered while fleeing: the way it doubled back, kept `flee_lock` frames
	var flee_lock := 0
	var flee_cd := 0
	var flee_chk := Vector2.ZERO  # where it was when headway was last checked (`flee_chk_t` frames ago)
	var flee_chk_t := 0
	var prey = null            # the creature it's hunting
	var chase_t := 0
	var hunger_t := 0          # frames before it hunts (or scavenges) again
	var eat_t := 0             # frames eating at a kill
	var bite_t := 0
	var leader = null          # (a pack's or a herd's: followers keep to it)
	var follow_off := 0.0
	var warn_t := 0            # (territorial: frames you've stood too close)
	var was_prov := false
	var sense_t := 0
	var storm := false         # (in the open in a storm: it goes for shelter)
	var den := Vector2.ZERO    # where it sleeps (where it was first met)
	var den_t := 0
	var off_t := 0             # frames off the ground (never one frame's on_ground: it flickers on a slope)
	var air_on := false        # (showing its leaping pose: a jump, or a fall of more than a few frames)
	var air_n := 0
	var land_t := 0            # frames since it landed (a frog's squash)
	var crouch_t := 0          # a frog crouching to hop, and the hop it's about to make
	var hop_v := Vector2.ZERO
	var tongue := 0.0          # a frog's tongue, out this far (cells) along `aim`

var gpu
var ui
var overlay
var space                 # above the orbit band: the space view and the staff-jet flight (space.gd)
var towns                 # the living villages' folk, talk and trade (towns.gd)
var workshops             # the workshop stations on this planet (workshops.gd)
var summoning             # guardians called at altars (summoning.gd)
var vfx                   # the spells' effects (vfx.gd): its own particles, glow, flashes
var weather               # rain, hail, snow, ash, embers, dust as you see them (weather.gd)
var skiff = null          # the Wisp Skiff, when it's out on this planet (skiff.gd; saved in planet_state["skiff"])
var view_tex: ImageTexture
var view_rect: TextureRect
## The view's shader: lays the GPU's picture onto the screen. In the close view the picture is drawn a
## cell a pixel (each row in its own shell's columns, lined up under the camera: shaders/inc/params.comp
## cellPicToWorld); here every screen pixel finds its world point, the cell there, and that cell's pixel,
## so the cells keep their true shape and size on screen (6 or 7 screen pixels where the picture's pixel
## is 6.6) and none is ever drawn twice or dropped. Otherwise ("mode" 0: the map, the unrolled setting,
## deep near the heart) it shows the screen's part of the picture as it is.
const VIEW_SHADER := "shader_type canvas_item;
uniform sampler2D rows : filter_nearest;
uniform vec2 cam;
uniform float cam_a;
uniform float row_a;
uniform float zoom = 1.0;
uniform vec2 vsize = vec2(320.0, 180.0);
uniform vec4 pic = vec4(320.0, 180.0, 0.0, 0.0);
uniform float y0;
uniform float r_top;
uniform int mode = 0;
uniform float alpha = 1.0;
void fragment() {
	vec2 sp = UV * vsize;
	vec4 c = vec4(0.0);
	if (mode == 0) {
		c = texelFetch(TEXTURE, ivec2(floor(sp + pic.zw)), 0);
	} else {
		vec2 o = (sp - vsize * 0.5) * zoom + vec2(0.0007, 0.0011);
		vec2 R = vec2(sin(cam_a), -cos(cam_a));
		vec2 D = vec2(-cos(cam_a), -sin(cam_a));
		vec2 w = cam + R * o.x + D * o.y;
		float j = floor(r_top - length(w)) - y0;
		if (j >= 0.0 && j < pic.y) {
			vec4 rw = texelFetch(rows, ivec2(int(j), 0), 0);
			vec2 u = vec2(cos(row_a), sin(row_a));
			float dth = atan(u.x * w.y - u.y * w.x, dot(u, w));
			float i = floor(pic.x * 0.5) - 1.0 - floor(rw.y + dth / 6.283185307 * rw.x);
			if (i >= 0.0 && i < pic.x) {
				c = texelFetch(TEXTURE, ivec2(int(i), int(j)), 0);
			}
		}
	}
	COLOR = vec4(c.rgb, c.a * alpha);
}"
## The retro pixel filter over the whole game view (user, 22 Nov: "the retro pixel filter seems to end at
## the space border"): the Dithering setting's ordered dither and 5-bit colour, applied on the game's own
## pixel grid to everything drawn under the UI (the world's picture is already quantized: those pixels
## are kept as they are), so space, sprites and spell effects get it too.
const POST_SHADER := "shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float amp = 1.0;
uniform float px = 4.0;
const float B[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 v = c * 31.0;
	vec3 k = round(v);
	ivec2 g = ivec2(floor(FRAGCOORD.xy / px));
	float d = 0.5 + ((B[(g.y & 3) * 4 + (g.x & 3)] + 0.5) / 16.0 - 0.5) * amp;
	vec3 q = floor(v + d);
	// (a channel already on one of the 32 levels, give or take its 8 bits, stays put)
	vec3 on = step(abs(v - k), vec3(0.08));
	COLOR = vec4(mix(q, k, on) / 31.0, 1.0);
}"
var post_rect: ColorRect
var _post_key := ""
var view_mat: ShaderMaterial
var _rows := PackedFloat32Array()      # this frame's cell picture rows (N, frac), for the view's shader
var _rows_tex: ImageTexture
var _pic_next := {}                    # the picture being drawn now (mode, rows, row angle, top row)
var _pic_sub := {}                     # the one submitted to the GPU
var pic := {"mode": 0}                 # the one on screen (from the last GPU frame)
var map_view: Node2D
var pix: Node2D

var state := "title"      # title, loading, play, forge, dead, error
var planet: Dictionary = {}
var frame := 0
var time := 0.0
var spawn_angle := 0.0
var builds = null          # the planet's planned structures (ruins, castles, towns...)
var testing := false       # started by "Run tests.bat" (--test): uses saves/test, reports, quits
var test_god := false      # the test mode keeps the mage alive except when it checks damage
var free_fuel := false     # the test mode flies the long hauls without Wisp Cells, except in the check about it
var free_magic := false    # the test mode digs and builds without mana, except in the check about it
var perf_us := 0           # time spent in the GPU step (for the test report)
var perf_n := 0
var _tests = null
var sky_rain := 0.0        # rain as seen in the sky, eased between biomes
var cam_unwrap := 0.0      # camera angle without the jump at a full turn (for parallax)
var _cam_prev := 0.0
# player settings (saves/settings.json): quality, dithering, pixel size (0 = automatic)
var settings := {"settings_v": 2, "quality": "auto", "auto_q": "high", "dither": "off", "pixel": 0, "music": 60, "sound": 80, "window": "windowed", "view": "world"}
var boss_info := Vector4.ZERO
var boss_clouds := []          # the Mycelord's spore clouds (boss_ai.gd update_clouds)
var eco_carcasses := []        # creatures killed by others, lying a while (ecology.gd): {pos, type, facing, t, h}
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
var test_sail := false       # test mode: hold Shift (the Starsail)
var test_mend := false       # test mode: hold R (mend the skiff)
var test_calm := false       # test mode: the biome guardians stay asleep (except while their own test runs)
## (the test mode's world seed for a new journey: 0, the classic system, but in the "newgame" check)
var test_seed := 0
var test_no_wild := false    # test mode: no wild creatures come by themselves (their own test spawns them)
# build mode (B): see build.gd
var build_on := false
var build_cat := 0
var build_idx := [0, 0, 0, 0, 0, 0, 0, 0]  # the chosen piece in each category (one per Build.CATS)
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
# (the build preview's fit, kept a few frames for the same piece at the same cell: worked out every frame, a
# piece that didn't fit slid along the floor cell by cell and dropped the frame rate where it didn't)
var _fit_key := ""
var _fit_frame := -100
var _fit_val := {}
var _floor_memo := {}
var _floor_memo_frame := -100
var _cur_cell := Vector2i(-99999, 0)  # (the cell the cursor's been on, and since when: a piece that
var _cur_since := 0                   # doesn't fit is only slid along the floor once the cursor rests)
var _design_key := ""
var _design_val := {}
var _build_warn_t := 0
var _mana_warn_t := 0
var _flat_key := ""          # (the flatten preview: worked out again only when the drag moves)
var _flat_plan := {}
var build_last := ""          # what the last click did (for the test report)
var build_last_stamp := {}
var _low_hp_t := 0               # when the low-health reminder may show again    # and where its blueprint went
var build_w := 40             # structures: width ([ and ]), storeys (- and =), style (T)
var build_floors := 1
var build_rise := 40          # a staircase's height (one storey: Buildings.STOREY)
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
	var sail := false          # Shift held: the skiff's Starsail, out in space
	var mend := false          # R held: mend the skiff's hull (beside it or aboard)
	var aim := Vector2.ZERO    # world position of the cursor

class Mage extends Body:
	var rig = null             # the simulated hat tip, beard, scarf and staff (overlay.gd, mage_rig.gd)
	var fog := 0.0             # how deep in cloud the mage is (0-1, from the GPU)
	var id := 0
	var slot := 0              # which simulation counters and collision grid are this mage's
	var local := true          # played on this computer (others come from the network)
	var input := PlayerInput.new()
	var cast_latch := false    # (a "single" spell was cast and the button hasn't been let go since)
	var grid_g := Vector2.ZERO # where this mage's collision grid was centred
	var grid_a := 0.0
	var hp := 100.0
	var max_hp := 100.0
	var mana := 100.0
	var max_mana := 100.0
	var mana_regen := 0.22
	var mana_spent_t := 0      # (frames since mana went on shaping the world: the HUD's bar glows)
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
	var spell_cd := {}           # each spell's own cooldown (id -> ticks): Mending's long one never holds the others
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
	var deck := false          # aboard, but up out of a seat, walking the ship's deck (`_deck_move`; X stands, X sits)
	var deck_b := Vector2.ZERO # (on deck: the middle of the body in the ship's own cells, and its speed there)
	var deck_v := Vector2.ZERO
	var buffs := {}            # a draught working now (Defs.DRAUGHTS id -> ticks left), read through gear()
	func _init() -> void:
		h = 17.0
		w = 7.0
		step_h = 5

var player := Mage.new()
## every Wisp Forge recipe: the fixed ones and the furniture from build mode's catalogue
var recipes: Array = Defs.RECIPES + Defs.gear_recipes() + Defs.sigil_recipes() + Build.furniture_recipes()
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
var clim := {}                 # the planet's climate (Defs.climate): storms, wind, fog, heat, frost, dust, creatures
var wind := 0.0                # the wind now (+ blows toward screen right), gusting harder in a storm
var _wind_dir := 1.0
var exposed := false           # you're out under the open sky (the wind reaches you; a volcanic world's air scorches)
var _heat_t := 0
var hazard := ""               # the planet's hazard hurting you right now (Defs.HAZARDS), "" for none
var _hz_t := {}                # (hazard -> ticks until its warning is shown again)
var _warm := false             # a fire, torch or lava close by (it keeps a frozen world's cold off)
var sky_ev := ""               # the sky event going on (Defs.SKY_EVENTS), "" for none
var sky_t := 0                 # (ticks since it began)
var sky_dur := 0
var sky_stats := {}            # (what each sky event has done: the tests read it)
var sky_wind := 0.0            # a squall's or sandstorm's gale, on top of the climate's wind
var sky_tint := Color(0, 0, 0, 0)   # over the whole view (overlay.gd): a sandstorm's haze, an eruption's glow
var sky_wisps := []            # will-o'-wisps: {"pos", "vel", "home", "ph"}
var sky_fx := []               # what the overlay draws for them: {"kind": "streak"/"bolt"/"rocket", ...}
var sky_vent := Vector2.ZERO   # an eruption's vent
var _sky_roll := 0
var _sky_next := 0             # (ticks to the event's next meteor, bomb, strike, rocket...)
var weather_timer := 1800
var flash := 0.0
var booted := false

func _ready() -> void:
	player.inv.resize(Defs.NM)
	get_tree().set_auto_accept_quit(false)   # we save first, then quit (see quit_game)
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.05))
	pix = Node2D.new()
	add_child(pix)
	# (space first: out there it draws the stars under the planet's picture, which is clear past the
	# orbit band)
	space = Space.new()
	space.game = self
	towns = Towns.new(self)
	workshops = Workshops.new(self)
	summoning = Summoning.new(self)
	pix.add_child(space)
	view_rect = TextureRect.new()
	view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var vsh := Shader.new()
	vsh.code = VIEW_SHADER
	view_mat = ShaderMaterial.new()
	view_mat.shader = vsh
	view_rect.material = view_mat
	pix.add_child(view_rect)
	overlay = Overlay.new()
	overlay.game = self
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pix.add_child(overlay)
	vfx = Vfx.new()
	vfx.game = self
	vfx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pix.add_child(vfx)
	weather = Weather.new()
	weather.game = self
	pix.add_child(weather)
	map_view = MapView.new()
	map_view.game = self
	map_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pix.add_child(map_view)
	post_rect = ColorRect.new()
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var psh := Shader.new()
	psh.code = POST_SHADER
	var pmat := ShaderMaterial.new()
	pmat.shader = psh
	post_rect.material = pmat
	post_rect.visible = false
	pix.add_child(post_rect)
	ui = UI.new()
	ui.game = self
	add_child(ui)
	audio = Audio.new()
	audio.game = self
	add_child(audio)
	gpu = GpuWorld.new()
	_load_settings()
	gpu.apply_quality(quality())
	_fxb = fx_budget()
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
	booted = true                 # (watchdog.gd: _ready got this far, so every preloaded script compiled)
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
	elif quality() == "low":
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
## the quality the world is simulated and drawn at: the setting, or (Auto, the default) the level it has
## stepped down to (`_auto_quality`)
func quality() -> String:
	var q := String(settings.get("quality", "auto"))
	return String(settings.get("auto_q", "high")) if q == "auto" else q

## how many of the small particles (sparks, dust, smoke puffs, rain streaks) a quality level keeps: drawing
## them one by one is the game's dearest drawing on a slow CPU (the big shapes, halos, rings, runes and
## bolts, are always drawn)
func fx_budget() -> float:
	match quality():
		"low":
			return 0.35
		"medium":
			return 0.6
	return 1.0

var _fxb := 1.0                 # (fx_budget(), kept: read for every particle)

## Auto quality (user, 23 Nov: "make sure it runs on lower end pc's with decent framerates"): while you play,
## if the frames come slower than 50 a second on average over AUTO_WINDOW seconds, the quality steps down a
## level (high, medium, low), and that's remembered (settings "auto_q"). Never while loading, travelling, in
## a menu, on the map, or in the test mode (unless a test asks: `auto_test`).
const AUTO_WINDOW := 4.0
const AUTO_SLOW_MS := 20.0
var _aq_t := 0.0                # (seconds of play timed in this window)
var _aq_n := 0                  # (frames in it)
var _aq_wait := 300             # (frames to let pass first: after a start, a journey, a step down)
var auto_test := false
func _auto_quality(delta: float) -> void:
	if String(settings.get("quality", "auto")) != "auto" or (testing and not auto_test):
		return
	if state != "play" or travelling:
		_aq_t = 0.0
		_aq_n = 0
		return
	if _aq_wait > 0:
		_aq_wait -= 1
		return
	if delta > 0.25:
		return                     # (a stall: a save, the window dragged; not the game's pace)
	_aq_t += delta
	_aq_n += 1
	if _aq_t < AUTO_WINDOW:
		return
	var avg_ms: float = _aq_t * 1000.0 / float(_aq_n)
	_aq_t = 0.0
	_aq_n = 0
	if avg_ms <= AUTO_SLOW_MS:
		return
	var cur := String(settings.get("auto_q", "high"))
	var nxt: String = {"high": "medium", "medium": "low"}.get(cur, "")
	if nxt == "":
		return
	settings["auto_q"] = nxt
	gpu.apply_quality(quality())
	_fxb = fx_budget()
	_layout()
	_save_settings()
	_aq_wait = 300
	ui.toast("Running at %.0f frames a second: quality lowered to %s to keep it smooth (Settings)" % [1000.0 / avg_ms, nxt.capitalize()], Color(0.8, 0.9, 1.0), 4.0)

func _save_settings() -> void:
	var f := FileAccess.open(_real_save_dir().path_join("settings.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if testing and Time.get_ticks_msec() > 1080000:
		# a test run that hasn't finished in 18 minutes has broken somewhere: don't leave the game open
		printerr("[Wisp Forge] test mode timed out after 18 minutes; quitting")
		get_tree().quit(1)
		return
	if gpu == null:
		return
	_auto_quality(delta)
	var tp := Time.get_ticks_usec()
	gpu.flush()
	prof_add("read back", gpu.read_us)
	gpu.read_us = 0
	if not _autosave.is_empty():
		tp = Time.get_ticks_usec()
		_autosave_step()
		prof_add("autosave", Time.get_ticks_usec() - tp)
	if gpu.fresh:
		tp = Time.get_ticks_usec()
		_take_gpu_results()
		prof_add("GPU results", Time.get_ticks_usec() - tp)
	var steps := 1
	var menu_up := menu_paused()
	if (state == "play" or state == "dead") and not menu_up:
		played += delta
		_tick_acc += minf(delta, 0.1)
		steps = mini(int(floor(_tick_acc * 60.0 + 0.001)), 4)
		_tick_acc = minf(_tick_acc - steps / 60.0, 1.0 / 60.0)
		for k in steps:
			_tick()
	elif state == "station":
		# (the world waits while a station's panel is open, but the stations keep working: you watch it)
		_tick_acc += minf(delta, 0.1)
		var wsteps := mini(int(floor(_tick_acc * 60.0 + 0.001)), 4)
		_tick_acc = minf(_tick_acc - wsteps / 60.0, 1.0 / 60.0)
		for k2 in wsteps:
			workshops.work_all()
		ui.update_station()
	if state == "map":
		_map_tick(delta)
		if map_tab == "planet" and not travelling:
			_gpu_frame(true, 1)
		ui.update_hud(self)
		map_view.queue_redraw()
	if state == "play" or state == "dead" or state == "forge" or state == "shop" or state == "station":
		tp = Time.get_ticks_usec()
		if (space.active and not space.live) or travelling:
			overlay.queue_redraw()          # (out in space the planet's cells rest: nothing for the GPU)
			lights.clear()
		else:
			_gpu_frame(state == "forge" or state == "shop" or state == "station" or menu_up, steps)
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
	_pic_sub = _pic_next
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
	# (each mage's nav graphs are rebuilt from the grid just read, now and then, on a worker thread)
	for m2 in players:
		nav_of_slot(m2.slot).tick(m2)
	_use_grid(player)
	_flush_loot()
	view_c = _sub_view_c
	ustep = _sub_ustep
	if _map_shown > 0:
		_map_shown -= 1
		if _map_shown == 0:
			view_mat.set_shader_parameter("alpha", 1.0)
	var tu := Time.get_ticks_usec()
	if view_tex == null or view_tex.get_width() != gpu.PW or view_tex.get_height() != gpu.PH:
		view_tex = ImageTexture.create_from_image(gpu.view_img)
		view_rect.texture = view_tex
	else:
		view_tex.update(gpu.view_img)
	view_rect.size = Vector2(gpu.VW, gpu.VH)
	_show_pic(_pic_sub)
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
	gpu.setp(122, Vector4(_p122.x, _p122.y, _p122.z, 0.0))   # (the whole planet, round)
	gpu.setp(123, Vector4(gpu.PW, gpu.PH, gpu.PMX, gpu.PMY))
	gpu.setp(2, Vector4(VW, VH, gpu.LS, 0))           # (no torch lights: their places are for the close view)
	var frames := []
	for k in mini(players.size(), gpu.MAXP):
		if players[k].pos.length() < Defs.R_SPACE:
			frames.append(_grid_frame(players[k].pos))
	gpu.step([cam_c], frames, false, false, 0, true)
	gpu.fresh = false                                  # (that picture isn't the view)
	var img: Image = gpu.view_img.get_region(Rect2i((VW - side) / 2 + gpu.PMX, (VH - side) / 2 + gpu.PMY, side, side))
	img.generate_mipmaps()
	return {"tex": ImageTexture.create_from_image(img), "zoom": zc, "angle": ang, "edge": (Defs.R_TOP + 60.0) / zc / float(side)}

var _p122 := Vector4.ZERO

## The cell picture's rows for a camera at c: picture row j is cell row y0 + j, in its shell's own columns,
## counted from the one under the camera's angle (main.gd and both shaders agree on these exactly: the
## column and how far into it the angle is are worked out here, in doubles, once).
func _cell_rows(c: Vector2) -> void:
	var ph: int = gpu.PH
	var y0 := int(floor(Defs.R_TOP - c.length())) - ph / 2
	var ca := fposmod(atan2(c.y, c.x), TAU)
	_rows.resize(ph * 2)
	var s_prev := -999
	var n := 1.0
	var xa := 0.0
	var fr := 0.0
	for j in ph:
		var s: int = Defs.shell_of_row(y0 + j)
		if s != s_prev:
			s_prev = s
			n = float(Defs.SH_N[s])
			var u := ca / TAU * n
			xa = floor(u)
			fr = u - xa
		gpu.setp(gpu.ROWT + j, Vector4(n, xa, fr, 0.0))
		_rows[j * 2] = n
		_rows[j * 2 + 1] = fr
	gpu.setp(124, Vector4(ca, y0, 0.0, 0.0))
	_pic_next = {"mode": 1, "rows": _rows.duplicate(), "a": ca, "y0": y0, "zoom": zoom}

## Hands the view's shader the picture now on screen: how it was drawn, and from where.
func _show_pic(p: Dictionary) -> void:
	pic = p if not p.is_empty() else {"mode": 0}
	var mode: int = int(pic.get("mode", 0))
	view_mat.set_shader_parameter("mode", mode)
	view_mat.set_shader_parameter("vsize", Vector2(gpu.VW, gpu.VH))
	view_mat.set_shader_parameter("pic", Vector4(gpu.PW, gpu.PH, gpu.PMX, gpu.PMY))
	if mode != 1:
		return
	var rows: PackedFloat32Array = pic["rows"]
	var img := Image.create_from_data(rows.size() / 2, 1, false, Image.FORMAT_RGF, rows.to_byte_array())
	if _rows_tex == null or _rows_tex.get_width() != img.get_width():
		_rows_tex = ImageTexture.create_from_image(img)
		view_mat.set_shader_parameter("rows", _rows_tex)
	else:
		_rows_tex.update(img)
	view_mat.set_shader_parameter("cam", view_c)
	view_mat.set_shader_parameter("cam_a", atan2(view_c.y, view_c.x))
	view_mat.set_shader_parameter("row_a", float(pic["a"]))
	view_mat.set_shader_parameter("zoom", float(pic["zoom"]))
	view_mat.set_shader_parameter("y0", float(pic["y0"]))
	view_mat.set_shader_parameter("r_top", Defs.R_TOP)

## Where a world point is in the GPU's picture (its pixels: for the light, and colours read back from it).
func world_to_pic(p: Vector2) -> Vector2:
	if int(pic.get("mode", 0)) != 1:
		return world_to_screen(p) + Vector2(gpu.PMX, gpu.PMY)
	var rows: PackedFloat32Array = pic["rows"]
	var jf := Defs.R_TOP - p.length() - float(pic["y0"])
	var j := clampi(int(floor(jf)), 0, rows.size() / 2 - 1)
	var u := Vector2(cos(float(pic["a"])), sin(float(pic["a"])))
	var dth := atan2(u.x * p.y - u.y * p.x, u.dot(p))
	var dd: float = rows[j * 2 + 1] + dth / TAU * rows[j * 2]
	return Vector2(floorf(gpu.PW * 0.5) - dd, jf)

## a point on screen (in the picture's pixel units, as world_to_screen gives) in the GPU's picture
func screen_to_pic(sp: Vector2) -> Vector2:
	return world_to_pic(screen_to_world(sp))

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
	elif close_view():
		# the world as it is, locked to the cells of the shell you're in: the camera sits on a corner of
		# a cell and the view is turned to that cell's column, so the cells round you are square on
		# screen, and moving a cell moves the picture exactly a cell (the terrain never shimmers)
		var cr0 := roundf(c.length())
		var cs: int = Defs.shell_of_row(int(Defs.R_TOP - cr0))
		var cstep: float = TAU / float(Defs.SH_N[cs])
		var ca0 := roundf(atan2(c.y, c.x) / cstep) * cstep
		c = Vector2(cos(ca0), sin(ca0)) * cr0
	# drawn a cell a pixel and laid on the screen by the view's shader (see VIEW_SHADER), except deep
	# near the heart, where the planet's curve bends the screen's corners past the picture's margin
	var cellpic: bool = close_view() and not unrolled() and c.length() > 900.0 and gpu.PH <= gpu.ROWMAX
	if cellpic:
		_cell_rows(c)
	else:
		_pic_next = {"mode": 0}
	view_c_next = c
	if view_c == Vector2.ZERO:
		view_c = c
		ustep = ustep_next
	gpu.setp(1, Vector4(c.x, c.y, atan2(c.y, c.x), zoom))
	_torch_lights()                          # (before the count of lights goes in)
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
	# (a hail storm drops no rain cells: weather.gd's stones are the hail, and a falling drop drawn
	# pale would look just like them)
	var fall_rate := rr * 0.0015 if rr > 0.05 and sky_ev != "hail" else 0.0
	gpu.setp(3, Vector4(fall_rate, wmat, maxf(rr, 0.5 * sky_ramp()) if sky_ev == "hail" else rr, flash))
	gpu.setp(5, Vector4(player.pos.x, player.pos.y, atan2(player.pos.y, player.pos.x), GS))
	# (w, flags: 1 the close view drawn in strips (see screenToWorld), 2 out in space: clear past the
	# orbit band, where space.gd draws the stars under the picture)
	var vflags := (1 if unrolled() else 0) | (2 if space.active or state == "map" else 0) | (4 if cellpic else 0) | (8 if space.backdrop() and state != "map" else 0)
	gpu.setp(123, Vector4(gpu.PW, gpu.PH, gpu.PMX, gpu.PMY))
	# the climate the shaders need: open water icing over (react.comp), ground fog (inc/clouds.comp)
	gpu.setp(125, Vector4(0.0008 * float(clim.get("freeze", 0.0)), sky_level("aurora"), sky_level("bloodmoon"), float(clim.get("fog", 0.0))))
	_p122 = Vector4({"off": 0, "subtle": 1, "retro": 2}.get(settings["dither"], 0), gpu.sun_step, ustep_next, float(vflags))
	var pk := "%s|%d|%d|%d" % [settings["dither"], scale_px, VW, VH]
	if pk != _post_key:
		_post_key = pk
		post_rect.visible = settings["dither"] != "off"
		post_rect.position = Vector2.ZERO
		post_rect.size = Vector2(VW, VH)
		(post_rect.material as ShaderMaterial).set_shader_parameter("amp", 1.0 if settings["dither"] == "retro" else 0.35)
		(post_rect.material as ShaderMaterial).set_shader_parameter("px", float(scale_px))
	gpu.setp(122, _p122)
	gpu.setp(6, Vector4(brushes.size(), hurt_flash, player.pos.x, player.pos.y))
	var cr := c.length()
	# the camera's angle, unwrapped (it keeps counting past a full turn) so parallax never jumps
	var ca := atan2(c.y, c.x)
	cam_unwrap += wrapf(ca - _cam_prev, -PI, PI)
	_cam_prev = ca
	gpu.setp(121, Vector4(spawn_angle, time * 0.00004, minf(Defs.R_TOP - 2.0, cr + VH * 0.55 * zoom), cam_unwrap))
	for k in mini(lights.size(), 32):
		var L: Array = lights[k]
		# (in the picture's pixels, as light.comp counts them: the screen's plus its margin. Given in the
		# screen's, every light shone a margin up and to the left of where it was, so underground the
		# wisp lit the rock beside you and not you)
		var sp := world_to_screen(L[0]) + Vector2(gpu.PMX, gpu.PMY)
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
	var o := m.slot * Defs.CNT
	if all.size() < o + Defs.CNT:
		return
	var cn := all.slice(o, o + Defs.CNT)
	m.fog = lerpf(m.fog, cn[Defs.C_FOG] / 1000.0, 0.25)
	if chunks != null and state == "play":
		var td := Time.get_ticks_usec()
		chunks.detect(m, cn)            # a felled tree or a creaking piece: lift it out whole
		prof_add("lifting pieces out", Time.get_ticks_usec() - td)
	_use_grid(m)
	if m.local and cn[Defs.C_CREAK_N] > 0:
		# something loose is about to fall: dust trickles from it and the ground rumbles
		var u: int = cn[Defs.C_CREAK] & 0xFFFFFFFF
		var dp := from_grid(Vector2((u & 1023) + 0.5, ((u >> 10) & 1023) + 0.5))
		for k in mini(4, 1 + cn[Defs.C_CREAK_N] / 15):
			_particle(dp + Vector2(randf() - 0.5, randf() - 0.5) * 5.0, Vector2(randf() - 0.5, randf() - 0.5) * 0.15, 40 + randi() % 30, Color(0.62, 0.57, 0.5), false, 0.04)
		if cn[Defs.C_CREAK_N] > 20:
			shake = maxf(shake, 1.2)
			if _creak_t <= 0 and dp.distance_to(m.pos) < 70.0:
				ui.toast("Something nearby creaks and shifts…", Color(0.85, 0.75, 0.6), 2.0)
				audio.play("creak", dp)
				_creak_t = 900
	var total := 0
	var spent := 0.0
	for t in Defs.NM:
		if cn[t] > 0:
			m.inv[t] += cn[t]
			total += cn[t]
			if t != Defs.TREASURE:
				spent += float(cn[t]) * dig_mana(t)
			if t >= Defs.FIREOPAL and t <= Defs.SILVER and not m.items.has("found_%d" % t):
				m.items["found_%d" % t] = true
				if m.local:
					ui.toast("%s: this world's own ore. The Wisp Forge (C) has gear for it, and the Core Drive wants some." % Defs.NAMES[t], Color(1.0, 0.85, 0.5), 5.0)
			if randf() < 0.6 and m.local:
				_spawn_suck_particles(t, mini(cn[t], 3))
	if cn[Defs.TREASURE] > 0 and m.local:
		_open_treasure(cn[Defs.TREASURE])
		m.inv[Defs.TREASURE] = 0
	if cn[Defs.C_FALL_N] > 0 and cn[Defs.C_FALL_MAX] >= ROCK_HURT_FALL and not m.dead:
		# a falling block lands on you: the longer it fell, the harder it hits (a clod that only
		# dropped a few cells, like the rim of a pit you're digging, just bumps you)
		var dmg := clampf(1.0 + float(cn[Defs.C_FALL_MAX] - ROCK_HURT_FALL) * 0.45 + float(cn[Defs.C_FALL_N]) * 0.1, 1.0, 35.0)
		var was := m.iframes
		hurt(m, dmg, Vector2(0, 1.2), true)
		if was == 0 and m.iframes > 0 and m.local:
			ui.toast("Falling rock! -%d" % int(dmg), Color(1, 0.6, 0.45), 1.5)
			shake = maxf(shake, 4.0)
	if cn[Defs.C_HARD] > 0:
		m.dig_blocked = 30
	# (shaping is magic: what was dug and placed this frame is paid for in mana)
	if m.pending_place > 0:
		spent += place_mana(mini(cn[Defs.C_PLACED], m.pending_place))
	if spent > 0.0 and not free_magic:
		m.mana = maxf(0.0, m.mana - spent)
		m.mana_spent_t = 20
	if m.pending_place > 0:
		var pm := m.pending_mat if m.pending_mat >= 0 else m.mat
		m.inv[pm] = maxi(0, m.inv[pm] - mini(cn[Defs.C_PLACED], m.pending_place))
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
	return [[Defs.COPPER, 6.0, 4], [Defs.COAL, 5.0, 4], [Defs.CRYSTAL, 1.5, 2], [Defs.FROST, 2.0 + deep * 2.0, 3],
		[Defs.EMBER, 1.0 + deep * 3.0, 3], [Defs.WISP, 1.0 + deep * 3.0, 2], [Defs.OBSIDIAN, 0.5 + deep * 2.0, 2],
		[Defs.GLASS, 2.0, 4], [Defs.TORCH, 2.0, 3], [Defs.MASONRY, 1.5, 6]] + ([[Defs.kind_ore(planet), 1.2, 3]] if Defs.kind_ore(planet) >= 0 else [])

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

const DOOR_PANEL_W := 6.0     # an open door is drawn at a slant, this wide, beside its doorway (10 till 23 Nov)

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
			for si in range(-2, 3, 2):
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
	if space.wreck_interact(player):      # (out in space: a wreck's cache within reach)
		return
	if not _chest_in_reach().is_empty():
		_try_open_chest()
		return
	if towns.talk(player):                # (a villager: a word, or a keeper's shop)
		return
	if workshops.interact(player):        # (a workshop station: its panel)
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
	var cn := int(randi_range(4, 14) * float(planet.get("rich", 1.0)) * (1.0 + rare))
	items["coins"] = int(items.get("coins", 0)) + cn
	ui.toast("+%d coins" % cn, Color(1, 0.85, 0.4), 2.5)
	# now and then a Healing Draught (the deeper and grander the place, the likelier)
	if randf() < 0.1 + rare * 0.3:
		items["potion"] = int(items.get("potion", 0)) + 1
		ui.toast("+1 Healing Draught (H to drink)", Color(0.6, 1.0, 0.65), 3.0)
	_rare_find(rare)
	# a recipe scroll, now and then (more in grander and deeper places)
	var lvl := 3 if rare >= 0.4 else (2 if rare >= 0.25 else 1)
	if centre.length() < gpu.surf_at(atan2(centre.y, centre.x)).x - 150.0:
		lvl = maxi(lvl, 2)
	if randf() < 0.3 + rare * 0.4 and _chest_recipe(lvl):
		save_game()
	elif randf() < 0.18 + rare * 0.3 and workshops.hint_note():
		save_game()
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
	for id in ["ring", "circlet", "boots"]:      # (spell scrolls are recipe scrolls now: _chest_recipe)
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

## The close view is the world as it is (the "view" setting "world", the default): turned so that up
## is away from the planet's centre, a pixel always the same size, so nothing squeezes or stretches
## going up or down; the horizon curves a little. Set to "unrolled" it is drawn in strips instead (see
## screenToWorld in shaders/inc/params.comp): x follows the angle, y the height, so the ground reads
## flat and buildings stand straight anywhere on screen, but what's above or below you is stretched.
## Zoomed out to the map, the planet is always drawn round.
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

## zoomed in on the planet (not the round map, not out in space): sprites stand upright on whole pixels
func close_view() -> bool:
	# (out in space, with the planet shown as its picture, the view is always flat: close by an
	# asteroid it zooms right in, and nothing there needs the planet's curve unrolled)
	if space != null and space.active and (not space.live or zoom > 1.01):
		return false                 # (zoomed out in space with the planet in sight: drawn as on the map)
	return zoom < 2.5

## the close view drawn in strips (the "view" setting), rather than as the world is
func unrolled() -> bool:
	return close_view() and settings.get("view", "world") == "unrolled"

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

## world_to_screen as one affine transform (xf * p), for loops over many points (particles, spell effects);
## the unrolled view isn't affine: there `screen_xf_ok()` is false and callers use world_to_screen.
func screen_xf() -> Transform2D:
	var c := _view()
	var a := view_angle()
	var r := basis_r(a) / zoom
	var d := basis_d(a) / zoom
	return Transform2D(Vector2(r.x, d.x), Vector2(r.y, d.y), Vector2(-c.dot(r) + VW * 0.5, -c.dot(d) + VH * 0.5))

func screen_xf_ok() -> bool:
	return not unrolled()

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

## The foes' pathfinding (nav.gd), one per mage: built from that mage's collision grid.
var navs := []

func nav_of_slot(k: int):
	while navs.size() <= k:
		navs.append(Nav.new(self, navs.size()))
	return navs[k]

## the nav of the collision grid in use (_use_grid)
func nav_of_grid():
	return nav_of_slot(_gslot)

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

## The top of the ground a body stands on (its feet at `feet`, `w` wide): the radius of the top of the
## world cell the collision grid has under it (drawn feet go there), or -1 if there's none right there.
func ground_top(feet: Vector2, w: float) -> float:
	var l := to_grid(feet)
	var x0 := int(floor(l.x - w * 0.5 + 0.01))
	var x1 := int(floor(l.x + w * 0.5 - 0.01))
	for yy in range(int(floor(l.y - 0.5)), int(floor(l.y + 0.6)) + 1):
		for xx in range(x0, x1 + 1):
			if gsolid(xx, yy) or gtype(xx, yy) == Defs.SCAFFOLD:
				var c := from_grid(Vector2(float(xx) + 0.5, float(yy) + 0.5))
				return float(Defs.R_TOP) - floorf(float(Defs.R_TOP) - c.length())
	return -1.0

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

## (gsolid per grid type, 0..63: built once; read straight from the grid's bytes below)
var _solid_t := PackedByteArray()
func _solid_table() -> PackedByteArray:
	if _solid_t.is_empty():
		_solid_t.resize(64)
		for t in 64:
			var k: int = Defs.KIND[t] if t < Defs.KIND.size() else 0
			_solid_t[t] = 1 if (t != Defs.TREASURE and t != Defs.SCAFFOLD and (k == Defs.K_SOLID or k == Defs.K_POWDER)) else 0
	return _solid_t

## Is any cell of a box solid (gsolid)? Read straight from the collision grid's bytes: the foes' moves try
## many boxes a frame (a creature pressed against a wall tried 13 x 14 cells for each step it might climb),
## and a call per cell cost a busy scene 55 ms a frame (the performance pass, 21 Nov).
func box_solid(x: float, y: float, w: float, h: float) -> bool:
	var x0 := int(floor(x))
	var x1 := int(floor(x + w - 0.001))
	var y0 := int(floor(y))
	var y1 := int(floor(y + h - 0.001))
	var gs: int = gpu.GS
	var base: int = gpu.grid_off + _gslot * gs * gs
	var buf: PackedByteArray = gpu.grid
	if x0 < 0 or y0 < 0 or x1 >= gs or y1 >= gs or base + (y1 + 1) * gs > buf.size():
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				if gsolid(xx, yy):
					return true
		return false
	var st := _solid_table()
	for yy2 in range(y0, y1 + 1):
		var row := base + yy2 * gs
		for xx2 in range(row + x0, row + x1 + 1):
			if st[buf[xx2] & 0x3F] == 1:
				return true
	return false

## Sunk into the ground by a fraction of a cell: the grid is laid out round you, so as you walk the ground
## under a body far off shifts against it by a hair. It comes out just that much (up, or off a wall).
## Lifted a whole cell, it dropped back over the next frames, and every foe bobbed as you walked
## (user, 21 Nov). Returns where it goes (x, y), the same if it isn't a sliver.
func _unsink(e: Body, x: float, y: float) -> Vector2:
	var bot := y + e.h
	var pen := bot - floorf(bot - 0.001)
	if pen > 0.001 and pen < 0.5 and not box_solid(x, y - pen, e.w, e.h):
		e.on_ground = true
		e.vy = minf(e.vy, 0.0)
		return Vector2(x, y - pen)
	var pr := (x + e.w) - floorf(x + e.w - 0.001)
	if pr > 0.001 and pr < 0.5 and not box_solid(x - pr, y, e.w, e.h):
		return Vector2(x - pr, y)
	var pl := ceilf(x) - x
	if pl > 0.001 and pl < 0.5 and not box_solid(x + pl, y, e.w, e.h):
		return Vector2(x + pl, y)
	return Vector2(x, y)

## Settling onto what stopped a fall: the body's bottom put right on the top of the cell row it met
## (stopped a step short, it hung up to half a cell over the ground, more or less as the grid shifted).
func _rest_on(x: float, y: float, st: float, w: float, h: float) -> float:
	var top := floorf(y + st + h - 0.001) - h
	if top > y and top < y + st + 0.001 and not box_solid(x, top, w, h):
		return top
	return y

func box_count(x: float, y: float, w: float, h: float, m: int) -> int:
	var n := 0
	var x0 := int(floor(x))
	var x1 := int(floor(x + w - 0.001))
	var y0 := int(floor(y))
	var y1 := int(floor(y + h - 0.001))
	var gs: int = gpu.GS
	var base: int = gpu.grid_off + _gslot * gs * gs
	var buf: PackedByteArray = gpu.grid
	if x0 < 0 or y0 < 0 or x1 >= gs or y1 >= gs or base + (y1 + 1) * gs > buf.size():
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				if gtype(xx, yy) == m:
					n += 1
		return n
	for yy2 in range(y0, y1 + 1):
		var row := base + yy2 * gs
		for xx2 in range(row + x0, row + x1 + 1):
			if (buf[xx2] & 0x3F) == m:
				n += 1
	return n

func move_body(e: Body) -> void:
	var l := to_grid(e.pos)
	var x := l.x - e.w * 0.5
	var y := l.y - e.h * 0.5
	e.hit_wall = false
	# (first out of a sliver of ground it sank into as the grid moved under it, or a step "up" would
	# lift it a whole cell before the rest of this saw it)
	if box_solid(x, y, e.w, e.h):
		var un0 := _unsink(e, x, y)
		x = un0.x
		y = un0.y
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
	var was_ground := e.on_ground and not e.on_platform
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
					y = _rest_on(x, y, st2, e.w, e.h)
				e.vy = 0.0
				break
		dy -= st2
	# standing, it stays standing: when the grid under it moves a row down (the grid is laid out round
	# you, so far off its rows sit up to half a cell above or below the world's, and that changes as you
	# walk), or it walks off a one-cell step, it's put straight down on it instead of falling for frames
	var reach := 1.05 if was_ground else 0.6
	if not e.on_ground and e.vy >= 0 and box_solid(x, y + reach, e.w, e.h):
		e.on_ground = true
		y = _rest_on(x, y, reach, e.w, e.h)
	if not e.on_ground and e.vy >= 0 and e.drop_t <= 0 and platform_below(x, y + e.h - 0.05, y + e.h + 0.6, e.w):
		e.on_ground = true
		e.on_platform = true
	# pushed into terrain (sand piled on, something placed): find the nearest free spot
	if box_solid(x, y, e.w, e.h):
		var freed := false
		var un := _unsink(e, x, y)
		if un != Vector2(x, y):
			x = un.x
			y = un.y
			freed = true
		for off in ([] if freed else [Vector2(0, -1), Vector2(0, -2), Vector2(1, 0), Vector2(-1, 0), Vector2(0, -3), Vector2(2, 0), Vector2(-2, 0),
				Vector2(1, -1), Vector2(-1, -1), Vector2(0, -4), Vector2(3, 0), Vector2(-3, 0), Vector2(0, -5), Vector2(0, -6), Vector2(0, 1)]):
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

## A wild creature of a place ("forest", "cave2"...), or "" if none lives there or enough are about.
## Each is weighed by where it lives and when it's out (ecology.gd `spawn_weight`: frogs only near water,
## the creatures of the night more rarely by day, met asleep); prey has its own count, so the hunters
## and the hunted are both about.
func _wild_pick(where: String, most: int) -> String:
	var ids: Array = Defs.creatures_of(where)
	if ids.is_empty() or test_no_wild:
		return ""
	var wild := 0
	var prey := 0
	for e in enemies:
		if e.d.get("creature", false):
			if Ecology.temper(e) == "prey":
				prey += 1
			else:
				wild += 1
	var a := atan2(player.pos.y, player.pos.x)
	var ws := []
	var tot := 0.0
	for id in ids:
		var w := Ecology.spawn_weight(self, id, a, player.pos)
		if Defs.CREATURES[id].get("temper", "") == "prey":
			if prey >= 3:
				w = 0.0
		elif wild >= most:
			w = 0.0
		ws.append(w)
		tot += w
	if tot <= 0.0:
		return ""
	var r := randf() * tot
	for k in ids.size():
		r -= float(ws[k])
		if r <= 0.0 and float(ws[k]) > 0.0:
			return "c_" + String(ids[k])
	return ""

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
	# (a quick right-click's few frames of digging count down here, every tick: they used to count down only on
	# the planet, so out in space one click kept mining an asteroid for good; user, 23 Nov)
	if m.dig_tap > 0:
		m.dig_tap -= 1
	inp.decon = can_act and rmb and shift
	inp.sail = (shift and state == "play") or test_sail
	inp.mend = (can_act and Input.is_key_pressed(KEY_R) and not build_on) or test_mend
	# (building inside the skiff: the cast button builds, it doesn't steer or fire)
	cabin_cast = false
	if build_on and m.aboard != null:
		cabin_cast = inp.cast
		inp.cast = false

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
		vfx.tick()
		_update_wisp()
		shake *= 0.88
		hurt_flash *= 0.9
		return
	_update_skiff()
	_mend_skiff(player)
	var tm := Time.get_ticks_usec()
	for m in players:
		if m.cast_cd > 0:
			m.cast_cd -= 1
		tick_spell_cds(m)
		if m.dig_blocked > 0:
			m.dig_blocked -= 1
		_use_grid(m)
		_update_player(m)
		m.sel = clampi(m.sel, 0, m.known.size() - 1)
		if not m.dead and state == "play" and m.aboard == null:
			if not m.input.cast:
				m.cast_latch = false
			if m.local and build_on:
				_update_build(m)
			elif m.input.cast and not m.cast_latch:
				_cast(m, m.known[m.sel], m.input.aim)
			if m.input.dig:
				_excavate(m, m.input.aim)
			if m.input.decon:
				_deconstruct(m, m.input.aim)
			else:
				m.decon_pause = 0
		if not m.dead and state == "play" and m.aboard != null and m.local and build_on:
			_update_cabin(m)
	prof_add("mages", Time.get_ticks_usec() - tm)
	_use_grid(player)
	var tq := Time.get_ticks_usec()
	_update_enemies()
	BossAI.update_clouds(self)
	Ecology.update_world(self)
	if player.items.has("lantern") and not player.dead:
		lights.append([player.pos, 70.0, Color(0.55, 0.95, 0.85)])      # (the Glowcap Lantern)
	var gl := gear("light")
	if gl > 0.0 and not player.dead:
		lights.append([player.pos, gl, Color(1.15, 0.9, 0.55)])          # (the Sun Lantern)
	_update_chests()
	workshops.tick()
	summoning.tick()
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
	vfx.tick()
	weather.tick()
	prof_add("shots and particles", Time.get_ticks_usec() - tq)
	if frame % 60 == 7:
		_check_torches()
	_update_weather()
	_update_climate()
	_update_sky_events()
	if not space.active:
		towns.tick()
	_try_spawn()
	_update_guards()
	_check_chest_hint()
	_update_wisp()
	_cloud_wisps()
	space.planet_tick()
	_update_camera(aim)
	shake *= 0.88
	hurt_flash *= 0.9
	if frame % 60 == 30 and not testing_no_learn():
		_learn_from_finds()
	if frame % 3600 == 0:
		save_game()
	if frame % 7200 == 0:
		_autosave_begin()

func _update_camera(aim: Vector2) -> void:
	var a := atan2(player.pos.y, player.pos.x)
	var up := player.pos.normalized()
	var look := ((aim - player.pos) * 0.12).limit_length(24.0) if zoom_i == 0 else Vector2.ZERO
	var target := player.pos + up * 4.0 + look
	# zoomed far out: slide the view toward the planet's centre so the whole globe fits
	if zoom >= 8.0:
		target = up * maxf(Defs.R_IN + 20.0, player.pos.length() * (0.35 if zoom < 10.0 else 0.02))
	elif zoom >= 4.0:
		target = up * player.pos.length() * 0.8
	cam_c = cam_c.lerp(target, 0.12)
	# (never far behind you: flying the skiff up, or a long fall, you stay near the middle of the view)
	var lag := cam_c - target
	if zoom < 2.5 and lag.length() > 14.0:
		cam_c = target + lag.normalized() * 14.0
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
	var fin: bool = m.items.has("tidefin")       # (Thalassor's relic: you swim as fast as you walk)
	var speed := ((1.5 if fin else 0.9) * gear("swim", m)) if p.in_liquid else 1.5 * gear("speed", m)
	speed *= 1.2 if m.items.has("coil") else 1.0
	p.vx += (move * speed - p.vx) * (0.35 if p.on_ground else 0.12)
	if m.local and exposed and not p.in_liquid and absf(wind) > 0.02:
		p.vx += wind * (0.02 if p.on_ground else 0.04)      # (the wind, out in the open)
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
			p.vy = -2.3 if p.in_liquid else (-4.6 if m.items.has("boots") else -3.9) * sqrt(gear("jump", m))
			m.jump_buf = 0
			audio.play("jump", m.pos, 0.6)
			m.ground_t = 99
			m.air_time = 0
	m.jump_held = jump
	# (levitation is forged: the Levitation recipe; a party member uses the host's items, as for every gear piece)
	m.floating = jump and not p.on_ground and not p.in_liquid and m.air_time > 10 and m.mana > 0.5 and (items.has("levitate") or items.has("roc"))
	if m.floating:
		audio.play("levitate", p.pos, 0.35)
		p.vy -= g + 0.28
		p.vy = maxf(p.vy, -2.5)
		m.mana -= (0.27 if m.items.has("roc") else 0.55) * gear("levitate", m)
		if randf() < 0.6:
			_particle(p.pos - basis_d(a) * (-p.h * 0.5) + R * (randf() * 3.0 - 1.5), Vector2((randf() - 0.5) * 0.4, 0.4 + randf() * 0.4), 18, Color8(140, 220, 255), true, 0.0)
	if p.in_liquid:
		if jump:
			p.vy -= 0.4 if fin else 0.26
		p.vy += g * 0.3
		var visc := mid_t == Defs.MUD
		p.vx *= 0.7 if visc else (0.96 if fin else 0.9)
		p.vy *= 0.75 if visc else (0.94 if fin else 0.9)
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
	# (Kragmor's relic, the Cinderheart: fire can't burn you, lava hurts far less, the deep heat none)
	var cinder: bool = m.items.has("cinderheart")
	if lava > 0:
		hurt(m, (0.08 if m.heat_ward else 0.55) * (0.3 if cinder else 1.0) * gear("lava_dmg", m) * mini(lava, 6), Vector2.ZERO, false)
	if fire > 0 and not cinder:
		hurt(m, (0.02 if m.heat_ward else 0.08) * gear("fire_dmg", m) * mini(fire, 6), Vector2.ZERO, false)
	var sa: Vector4 = gpu.surf_at(a)
	if p.pos.length() < sa.w + 20.0 and not m.heat_ward and not cinder:
		hurt(m, 0.05, Vector2.ZERO, false)
	# a volcanic world's air scorches you under the open sky (the Heat Ward or the Cinderheart bear it)
	if m.local and exposed and float(clim.get("heat", 0.0)) > 0.0 and not m.heat_ward and not cinder and not p.in_liquid:
		hurt(m, 0.012 * float(clim["heat"]), Vector2.ZERO, false)
		_heat_t -= 1
		if _heat_t <= 0:
			_heat_t = 1200
			ui.toast("The air of %s scorches you under the open sky: forge the Heat Ward, or keep to the caves" % planet.get("name", ""), Color(1.0, 0.6, 0.4), 4.0)
	# the other kinds' hazards: cold, sun, miasma, the deep (Defs.HAZARDS)
	if m.local:
		_hazards(m, p)
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
	var regen: float = m.mana_regen
	if sky_ev == "aurora" and m.local and exposed and m.mana < m.max_mana:
		regen *= 2.0                                   # (under the aurora)
		sky_stats["aurora_mana"] = float(sky_stats.get("aurora_mana", 0.0)) + m.mana_regen
	m.mana = minf(m.max_mana, m.mana + regen)
	if m.mana_spent_t > 0:
		m.mana_spent_t -= 1
	heal_tick(m)
	if m.local and m.hp < m.max_hp * 0.3 and m.heal_left <= 0.0 and frame >= _low_hp_t and not m.dead:
		_low_hp_t = frame + 1800
		ui.toast("Low health%s" % (": drink a Healing Draught (H)" if int(items.get("potion", 0)) > 0 else ". Health doesn't come back by itself"), Color(1, 0.55, 0.5), 3.0)

func hurt(m: Mage, dmg: float, knock: Vector2, hit: bool) -> void:
	if m.dead or test_god:
		return
	if m.items.has("ironbark"):
		dmg *= 0.75
	dmg *= gear("dmg_taken", m)
	if hit:
		if m.iframes > 0:
			return
		m.iframes = 40
		var kk := gear("knock", m)
		m.vx += knock.x * kk
		m.vy += knock.y * kk
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

## Cooldowns are each spell's own (user, 23 Nov: "healing cooldown locks other spells"): a spell cast waits
## its "cd" before it's cast again, and holds the others only a moment (`SPELL_GAP`), so you can heal and
## fight on.
const SPELL_GAP := 10
func spell_ready(m: Mage, id: String) -> bool:
	return m.cast_cd <= 0 and int(m.spell_cd.get(id, 0)) <= 0

func spell_used(m: Mage, id: String, cd: int) -> void:
	m.spell_cd[id] = cd
	m.cast_cd = mini(cd, SPELL_GAP)

func tick_spell_cds(m: Mage) -> void:
	if m.spell_cd.is_empty():
		return
	for k in m.spell_cd.keys():
		var v := int(m.spell_cd[k]) - 1
		if v <= 0:
			m.spell_cd.erase(k)
		else:
			m.spell_cd[k] = v

func _cast(m: Mage, id: String, aim: Vector2) -> void:
	var s: Dictionary = Defs.SPELLS[id]
	var cost := float(s["mana"]) * gear("mana_cost", m)     # (the Silver Sigil)
	if not spell_ready(m, id) or m.mana < cost:
		return
	m.cast_frame = frame
	m.cast_latch = bool(s.get("single", false))
	if id == "conjure":
		_conjure(m, aim)
		spell_used(m, id, int(s["cd"]))
		return
	if id == "mend":
		if m.hp >= m.max_hp:
			if m.local:
				ui.toast("You're unhurt", Color(0.8, 0.95, 0.8), 1.0)
			spell_used(m, id, 20)
			return
		m.mana -= cost
		spell_used(m, id, int(s["cd"]))
		m.heal_left += Defs.MEND_HEAL
		audio.play("rare", m.pos, 0.6)
		vfx.mend(m)
		return
	if id == "blink":
		if _blink(m, aim):
			audio.play("blink", m.pos)
			m.mana -= cost
			spell_used(m, id, int(s["cd"]))
		return
	m.mana -= cost
	spell_used(m, id, int(s["cd"]))
	var snd := {"mote": "spark", "spark": "spark", "fireball": "fire", "tide": "water", "frost": "frost", "quake": "boom", "starfall": "rare"}
	audio.play(snd.get(id, "spark"), m.pos, 0.8)
	var st := _staff(m, aim)
	var pd: Dictionary = Defs.PROJ[id]
	_spawn_proj(id, st[0], st[1] * float(pd["speed"]), "player")
	vfx.cast(id, st[0], st[1], m)

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
			vfx.blink(from, p)
			m.pos = p
			m.vx = 0
			m.vy = 0
			return true
	return false

func _spawn_proj(type: String, p: Vector2, v: Vector2, owner: String) -> void:
	var pd: Dictionary = Defs.PROJ[type]
	projs.append({"type": type, "pos": p, "vel": v, "life": int(pd["life"]), "owner": owner})

func _reach(m: Mage, aim: Vector2) -> Vector2:
	var c := m.pos
	var d := aim - c
	var rl := REACH * gear("reach", m)
	if d.length() > rl:
		d = d.normalized() * rl
	return c + d

# ----------------------------------------------------------- shaping is magic --
## (user, 22 Nov: "tie excavating and removing blocks to mana ... everything ideally would be tied into the
## fact that we are using magic"; chose mana per cell, harder costs more, and a little to place things)
const DIG_MANA := 0.08         # mana a cell of soft ground costs to take; each step of hardness adds 1.5x that
const PLACE_MANA := 0.04       # mana a cell put in place costs (conjured, laid, built), on top of the material
const TORCH_MANA := 2.0
const STATION_MANA := 8.0
const MANA_FLOOR := 1.0        # below this you can't dig, take away or conjure

## the mana a cell of material t costs to take away
func dig_mana(t: int) -> float:
	return DIG_MANA * (1.0 + 1.5 * float(Defs.HARD[t])) * gear("mana_cost", player)

func place_mana(cells: int) -> float:
	return PLACE_MANA * float(cells) * gear("mana_cost", player)

## is there mana enough to begin (digging, conjuring...)? If not, the staff fizzles and you're told
func has_mana(m: Mage, need: float, p: Vector2, what: String) -> bool:
	if free_magic or m.mana >= need:
		return true
	if m.local and _mana_warn_t <= frame:
		_mana_warn_t = frame + 50
		ui.toast("Not enough mana to %s (%d of %d): wait for it to come back" % [what, int(m.mana), int(ceil(need))], Color(0.55, 0.75, 1.0), 1.6)
		vfx.fizzle(p)
		audio.play("fizzle" if audio.sfx.has("fizzle") else "hit", p, 0.35, 1.8)
	return false

## spends mana if there is enough (true), else says so (false)
func pay_mana(m: Mage, amount: float, p: Vector2, what: String) -> bool:
	if not has_mana(m, amount, p, what):
		return false
	if not free_magic:
		m.mana = maxf(0.0, m.mana - amount)
	return true

func _excavate(m: Mage, aim: Vector2) -> void:
	var p := _reach(m, aim)
	if not has_mana(m, MANA_FLOOR, p, "dig"):
		return
	audio.play("dig", p, 0.7)
	# digging at a door (open or shut) takes the whole door down: it goes into the satchel as a Door
	var dd := _door_at(p, m.dig_r * 0.6)
	if not dd.is_empty():
		_take_door(m, dd)
	if m.local and _dig_open_t <= 0 and _dig_hits_chest(p, m.dig_r):
		_dig_open_t = 30
		_try_open_chest()
	brushes.append([p, m.dig_r, 1, 0, m.tier, dig_speed(m) - 1.0, 0, m.slot])
	vfx.dig(m, p, m.dig_r)

## Shift + right mouse: take background tiles (a building's back walls, furniture, plants). It is how
## you clear a wall on purpose; plain right-click never touches a building's walls.
func _deconstruct(m: Mage, aim: Vector2) -> void:
	var p := _reach(m, aim)
	if m.decon_pause > 0:
		m.decon_pause -= 1
		return
	if not has_mana(m, MANA_FLOOR, p, "take that away"):
		return
	if m.local and workshops.take_at(m, p):
		m.decon_pause = 20
		return
	if _pick_up_furniture(m, p):
		m.decon_pause = 15       # a moment's pause, then harvesting carries on while the button is held
		return
	brushes.append([p, m.dig_r * 0.8, 8, 0, m.tier, 0, 0, m.slot])
	vfx.dig(m, p, m.dig_r * 0.8, true)

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
	# a torch (a small piece with a flame) is a torch again, not a carried decoration
	var n_flame := 0
	for kf in cells:
		if (bgs[kf] & 255) == Defs.TORCH:
			n_flame += 1
	if kid == 0 and n_flame >= 3 and cells.size() <= Build.TORCH_CELLS_MAX:
		m.inv[Defs.TORCH] += 1
		audio.play("place", Build.cell_pos(c0 + (i0 + i1) / 2, r0 + (j0 + j1) / 2), 0.6, 1.2)
		if m.local:
			ui.toast("+ 1 Torch", Color(1, 0.85, 0.5), 1.4)
		return true
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
		ui.toast("+ %s (in your satchel: click it there, I, to set it down)" % item["name"], Color(0.95, 0.8, 0.5), 2.5)
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
	if m.mat == Defs.TORCH:
		# torches go down one a click, as a whole torch (a sconce, or standing on a floor)
		m.cast_latch = true
		place_torch(m, p)
		return
	if not has_mana(m, MANA_FLOOR, p, "conjure"):
		return
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
	vfx.conjure(p, Defs.COLOR[m.mat])
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
			lights.append([pos, float(pd["light"]), pd["col"] * 0.85])
			continue                  # an arrow glows faintly (spectral green) but doesn't spark
		var col: Color = Defs.SPELLS[pr["type"]]["color"] if Defs.SPELLS.has(pr["type"]) else pd.get("col", Color(1, 0.35, 0.12))
		if float(pd["light"]) > 0.0:
			lights.append([pos, float(pd["light"]), col * 0.85])
		if Defs.SPELL_FX.has(pr["type"]):
			vfx.trail(pr)                   # (the spells' own trails: vfx.gd)
		elif randf() < 0.6:
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
		"mote":
			# (the first spell: it stings, and moves nothing; stone and earth shrug it off)
			if e != null:
				_hurt_enemy(e, float(pd["dmg"]), kb * 0.6, -0.4)
		"spark":
			if e != null:
				_hurt_enemy(e, float(pd["dmg"]) * gear("spell_spark"), kb, -0.6)
				if items.has("rimefang"):
					e.slow = maxi(e.slow, 150)
			elif hit:
				brushes.append([p, 2.4, 6, 0, tier, 0, 0])
		"fireball":
			var fk := gear("spell_fireball")
			_explode(p, 10.0 * fk, maxi(1, tier), 1, 38.0 * fk)
		"quake":
			_explode(p, 22.0, mini(3, tier + 1), 2, 70.0)
		"starfall":
			_explode(p, 17.0, maxi(2, tier), 1, 80.0)
		"tide":
			brushes.append([p, 8.0, 3, Defs.WATER, 0, 0, 0])
			if e != null:
				_hurt_enemy(e, pd["dmg"], kb * 2.0, -1.0)
		"frost":
			var rk := gear("spell_frost")
			brushes.append([p, 10.0 * rk, 4, 0, 0, 0, 0])
			for en in enemies:
				if en.pos.distance_to(p) < 13.0 * rk:
					en.slow = int(200 * rk)
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
		"meteor":
			_meteorite(p)
		_:
			# the guardians' shots: they hurt you, or leave their matter where they land
			if hit_m != null:
				var hv: Vector2 = pr["vel"]
				var hha := atan2(hit_m.pos.y, hit_m.pos.x)
				hurt(hit_m, float(pd["dmg"]), Vector2(signf(hv.dot(basis_r(hha))) * 1.8, -1.2), true)
			elif pd.has("splat") and hit:
				brushes.append([p, 2.2, 3, int(pd["splat"]), 0, 0, 0])
			if type == "lavabomb":
				sky_stats["bomb_hits"] = int(sky_stats.get("bomb_hits", 0)) + 1
	if Defs.SPELL_FX.has(type):
		vfx.impact(type, p, hit)
		return
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
	vfx.blast(p, r, kind)
	shake = maxf(shake, r * 0.6)
	Ecology.scare(self, p, r)            # (the wild runs from a blast)
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
	e.den = p
	e.sense_t = 1 + randi() % 12
	enemies.append(e)
	return e

## A bat with nothing to hunt: up to the cave roof over it and hanging there, asleep (true while it's
## roosting or on its way; false with no roof near).
func _bat_roost(e: Enemy) -> bool:
	if e.goal_p == Vector2.ZERO:
		if e.doing_t > 0:
			e.doing_t -= 1
			return false
		e.goal_p = Ecology.find_ceiling(self, e)
		if e.goal_p == Vector2.ZERO:
			e.doing_t = 120                   # (no roof over it: it looks again in a while)
			return false
	if e.pos.distance_to(e.goal_p) < 2.5 or e.pose == "hang":
		e.pos = e.goal_p
		e.vx = 0.0
		e.vy = 0.0
		e.pose = "hang"
		e.asleep = true
		return true
	e.phase += 0.12
	Ecology.fly_to(self, e, e.goal_p, 1.0, 0.1)
	return true

## a wild creature the Amber Totem keeps calm toward m (until something hurts it)
func calm_foe(e: Enemy, m: Mage) -> bool:
	return not e.boss and not e.provoked and e.type.begins_with("c_") and gear("calm_wild", m) > 1.5

func _hurt_enemy(e: Enemy, dmg: float, kx: float, ky: float) -> void:
	if items.has("sunidol"):
		dmg *= 1.25
	if e.type == "skeleton" or e.type == "archer" or e.d.get("warden", false):
		dmg *= gear("undead_dmg")                       # (the Silverbane Charm)
	e.provoked = true
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
	if not e.boss:
		_check_cleared()
	towns.on_kill(e.type)                # (a villager's hunt may want it)
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
	if e.d.get("warden", false):
		_warden_falls(e)
		return
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
	_hoard_ore(16)
	_hoard_recipe()
	items["coins"] = int(items.get("coins", 0)) + 60
	_roll_loot(4, 1.5)
	shake = 16.0
	audio.play("rare")
	for o in enemies:
		if o.summoner == e:
			o.summoner = null
	save_game()

## A boss's hoard holds some of this world's own ore (Defs.KIND_ORES): a guardian's most of what a Core
## Drive wants, so beating one is a step on the way to the next planet.
func _hoard_ore(n: int) -> void:
	var ko := Defs.kind_ore(planet)
	if ko < 0:
		return
	player.inv[ko] += n
	items["found_%d" % ko] = true
	ui.toast("+%d %s" % [n, Defs.NAMES[ko]], Color(1.0, 0.85, 0.5), 4.0)

## A dungeon's warden is beaten: its loot (and a Healing Draught), it stays dead, and the ward on
## its reliquary's door breaks (a stamp clears the runestone; the world keeps it open from then on).
func _warden_falls(e: Enemy) -> void:
	var bd: Dictionary = e.d["def"]
	var key: String = e.d["key"]
	var dead_list: Array = planet_state.get("bosses_dead", [])
	if not dead_list.has(key):
		dead_list.append(key)
	planet_state["bosses_dead"] = dead_list
	ui.toast("%s falls!" % bd["name"], bd["col"], 6.0)
	var loot: Dictionary = bd["loot"]
	for mt in loot:
		player.inv[int(mt)] += int(loot[mt])
	items["potion"] = int(items.get("potion", 0)) + 1
	_hoard_ore(6)
	_hoard_recipe()
	items["coins"] = int(items.get("coins", 0)) + 30
	_roll_loot(3, 1.4)
	for wl in builds.warden_list:
		if wl["key"] != key:
			continue
		var wr: Dictionary = wl["ward"]
		var air := PackedInt32Array()
		air.resize(int(wr["w"]) * int(wr["h"]))
		air.fill(Defs.AIR | 0xFF00)
		stamps.append({"x0": wr["x0"], "y0": wr["y0"], "w": wr["w"], "h": wr["h"], "data": air, "ax": wr["ax"], "aw": wr["aw"]})
		var mid: Vector2 = Defs.stamp_pos(int(wr["y0"]) + int(wr["h"]) / 2, int(wr["ax"]), int(wr["aw"]), Defs.k_of(int(wr["x0"]) + int(wr["w"]) / 2, int(wr["ax"])))
		for k in 50:
			var dirv := Vector2.from_angle(randf() * TAU)
			_particle(mid + dirv * randf() * 8.0, dirv * (0.8 + randf() * 1.6), 30 + randi() % 30, Color(0.6, 0.9, 1.0), true, 0.0)
		ui.toast("The ward on the Sealed Reliquary breaks!", Color(0.6, 0.9, 1.0), 6.0)
	shake = 14.0
	audio.play("rare")
	for o in enemies:
		if o.summoner == e:
			o.summoner = null
	save_game()

## the guardians of this planet's biomes, each in its lair (not the ones already beaten), and
## the wardens of its dungeons, each in its hall
func _spawn_guardians() -> void:
	summoning.on_load(planet_state)          # (a guardian called when the world was saved: its sigil back)
	var dead_list: Array = planet_state.get("bosses_dead", [])
	for lr in builds.lair_list:
		var biome: String = lr["biome"]
		if dead_list.has(biome) or not Defs.BOSSES.has(biome):
			continue
		var d: Dictionary = Defs.boss_enemy("boss_" + biome)
		var at: Vector2 = lr["pos"]
		var ge = spawn_enemy("boss_" + biome, at + at.normalized() * (float(d["h"]) * 0.5 + 2.0))
		ge.tether = float(lr.get("tether", 60.0))       # (its lair, and as far as it follows you out of it)
		ge.ceil = float(lr.get("ceil", 60.0))
		ge.arena = float(lr.get("arena", 0.0))
	for wl in builds.warden_list:
		var key: String = wl["key"]
		if dead_list.has(key):
			continue
		Defs.register_warden(key, wl["def"])
		var wd: Dictionary = Defs.warden_enemy(key)
		var wat: Vector2 = wl["pos"]
		var we = spawn_enemy(key, wat + wat.normalized() * (float(wd["h"]) * 0.5 + 2.0))
		we.tether = float(wl["tether"])                 # (it stays in its hall)
		we.ceil = float(wl["ceil"])

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
	# by its way about (nav.gd): straight at the point when nothing's in the way, else round what is
	# (a swimmer through the water only); the old probe below until its graph is built
	var nav = nav_of_grid()
	var swim: bool = e.d.get("def", {}).get("swim", false)
	var key := Nav.key_for("swim" if swim else "fly", e.w, e.h)
	if nav.has(key):
		var a := atan2(e.pos.y, e.pos.x)
		var to := e.pos + basis_r(a) * want.x + basis_d(a) * want.y
		return FoeAI.nav_fly(self, e, to, swim)
	nav.ask(key)
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
			# health, asleep where it started, so it has to be beaten in one fight (one called at an altar
			# goes back where it came from, and you have its sigil again)
			if dist > 300.0 or tgt.dead:
				e.leash_t += 1
				if e.leash_t > 200 and e.summoned != "":
					summoning.dismiss(e)
					enemies.remove_at(k)
					continue
				if e.leash_t > 200 and (e.hp < e.max_hp or e.awake):
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
		var tf0 := Time.get_ticks_usec()
		if not e.boss:
			FoeAI.think(self, e, tgt, dist)
			gl = FoeAI.goal(self, e, tgt)
		var tf1 := Time.get_ticks_usec()
		prof_add("foes: think", tf1 - tf0)
		if e.d.has("def"):
			BossAI.tick(self, e, tgt, dist, dx, dy, g, slow_f)
			prof_add("foes: creatures", Time.get_ticks_usec() - tf1)
		tf1 = Time.get_ticks_usec()
		match e.type:
			"slime", "mimic":
				# hops after you once it knows you're there; close by, a crouch and a leap aimed at you
				var busy := FoeAI.leap(self, e, tgt, dx, dy, g)
				var cjv := 5.4 if e.type == "slime" else 4.6
				# by its way about (nav.gd): little hops along it, the big jumps nav_walk makes itself
				# (NAN: no graph yet, so the old way below)
				var nd2 := NAN
				if not busy and gl != Vector2.ZERO:
					nd2 = FoeAI.nav_walk(self, e, from_grid(to_grid(e.pos) + gl + Vector2(0.0, 8.5)), cjv, g, 5.0)
				var cdir2 := 0.0 if busy or gl == Vector2.ZERO or not is_nan(nd2) else FoeAI.climb(self, e, gl, cjv, g, 5.0)
				if not is_nan(nd2):
					if not e.nav_air and e.on_ground and e.vy >= 0.0:
						e.vx *= 0.75 if e.type == "slime" else 0.7
						e.t -= 1
						if e.t <= 0 and nd2 != 0.0:
							# a hop sized to land at the next point of its way (not past it, off a ledge)
							var hv := 2.6 + randf() * 0.6
							var hair := 2.0 * hv / maxf(g, 0.01)
							var top_v: float = (1.4 + randf() * 0.6) if e.type == "slime" else (1.8 + randf() * 0.6)
							e.vx = nd2 * clampf((absf(e.nav_dx) + 2.0) / hair, 0.3, top_v) * slow_f
							e.vy = -hv
							e.t = (24 + randf() * 20) if e.type == "slime" else (16 + randf() * 14)
				elif cdir2 != 0.0:
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
					# by its way about (nav.gd), unless an archer that sees you is backing off or holding
					# its range; NAN: no graph yet, so the old way below
					var nd := NAN
					var keep0: Array = ai.get("keep", [])
					if gl != Vector2.ZERO and (keep0.is_empty() or not e.see or dist > float(keep0[1])):
						nd = FoeAI.nav_walk(self, e, from_grid(to_grid(e.pos) + gl + Vector2(0.0, 8.5)), 3.9, g, 2.5, ai.get("doors", false))
					if not is_nan(nd):
						if not e.nav_air and e.on_ground:
							e.vx += (nd * (0.85 if ai.has("melee") else 0.75) * slow_f - e.vx) * 0.25
					elif gl != Vector2.ZERO:
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
				# with nothing to hunt it hangs from the cave roof, asleep, till something comes by
				if gl == Vector2.ZERO and e.act == "" and _bat_roost(e):
					pass
				else:
					e.pose = ""
					e.asleep = false
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
						if e.hit_wall and e.path_key == "":
							e.vy -= 0.3              # (no way about yet: up over what it hit)
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
					_golem_reach(e, tgt, dist, g, enraged)
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
		if not e.d.has("def"):
			prof_add("foes: " + e.type, Time.get_ticks_usec() - tf1)
		tf1 = Time.get_ticks_usec()
		if e.d["fly"]:
			e.vy *= 0.98
		elif e.vy > 6.0:
			e.vy = 6.0
		if e.under or e.move == "breach":
			e.vx = 0.0                     # (under the ground, or flung out of it: boss_ai moves it)
			e.vy = 0.0
		else:
			Ecology.guard_lava(self, e)
			move_body(e)
			# (frames off the ground: a pose reads this, so a frog sitting on a curved slope doesn't
			# flicker into its leap)
			if e.on_ground or (e.pose == "perch") or (e.doing == "roost" and e.vx == 0.0 and e.vy == 0.0):
				if e.off_t > 4:
					e.land_t = 6
				e.off_t = 0
				# (the leaping pose, once shown, stays at least 3 frames: no one-frame flicker)
				if e.air_on:
					e.air_n += 1
					if e.air_n >= 3:
						e.air_on = false
			else:
				e.off_t += 1
				if not e.air_on and ((e.off_t > 1 and e.vy < -0.3) or e.off_t > 8):
					e.air_on = true             # a jump, or a real fall (not a step down a slope)
					e.air_n = 0
				elif e.air_on:
					e.air_n += 1
			if e.land_t > 0:
				e.land_t -= 1
			# (how long it has been pressed against a wall: its way about gives up on that way)
			e.wall_t = e.wall_t + 1 if e.hit_wall and (e.on_ground or e.d["fly"]) else 0
		prof_add("foes: moving", Time.get_ticks_usec() - tf1)
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
		var calm := calm_foe(e, tgt) or not Ecology.harmful(e)
		if not tgt.dead and not e.under and not calm and absf(dx) < (e.w + tgt.w) * 0.5 and absf(dy) < (e.h + tgt.h) * 0.5:
			hurt(tgt, float(e.d["dmg"]), Vector2(signf(dx) * 2.2, -1.6), true)
		if not tgt.dead and not e.under and not calm and not e.trail.is_empty() and e.awake:
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

## Vulkhar out of reach (user, 23 Nov: "i was able to cheese the boss near the core pretty easily by fighting
## him through a hole in the ground"): every half second he looks for a way to you (the nav graph, as the
## guardians do). Kept from you for two seconds, he SURGES every three: a tight stream of fire straight up at
## you (his spread volleys missed down a narrow hole) and two imps called up from the heart's fire to come after
## you (at most 4 about him); kept from you for five seconds the heart mends him (9 health a second), so
## striking from where he can't follow gains nothing.
const GOLEM_SURGE_AFTER := 120
const GOLEM_SURGE_EVERY := 180
const GOLEM_MEND_AFTER := 300
func _golem_reach(e: Enemy, tgt: Mage, dist: float, g: float, enraged: bool) -> void:
	if frame % 30 == 0:
		var ta := atan2(tgt.pos.y, tgt.pos.x)
		e.reach_ok = FoeAI.can_reach(self, e, tgt.pos + basis_d(ta) * (tgt.h * 0.5), 5.2, g)
	e.unreach_t = 0 if e.reach_ok or dist > 260.0 else e.unreach_t + 1
	if e.surge_n > 0:
		if frame % 5 == 0:
			FoeAI.shoot(self, e, tgt, "efire", 1, 0.0, 0.3)
			e.surge_n -= 1
		return
	if e.unreach_t < GOLEM_SURGE_AFTER:
		e.surge_t = 30
		return
	if e.unreach_t == GOLEM_SURGE_AFTER:
		ui.toast("Vulkhar can't reach you: the heart's fire answers for him", Color(1, 0.55, 0.25), 3.0)
	if e.unreach_t > GOLEM_MEND_AFTER and e.hp < e.max_hp:
		e.hp = minf(e.max_hp, e.hp + 0.15)
	e.surge_t -= 1
	if e.surge_t > 0:
		return
	e.surge_t = GOLEM_SURGE_EVERY - (60 if enraged else 0)
	e.surge_n = 8 if enraged else 6
	shake = maxf(shake, 6.0)
	audio.play("roar", e.pos, 0.8)
	vfx.blast(e.pos, 14.0, 0)
	var imps := 0
	for o in enemies:
		if o.type == "imp" and o.pos.distance_to(e.pos) < 300.0:
			imps += 1
	var ea := atan2(e.pos.y, e.pos.x)
	for k in mini(2, 4 - imps):
		var ip: Vector2 = e.pos - basis_d(ea) * (e.h * 0.5 + 8.0) + basis_r(ea) * (float(k) * 2.0 - 1.0) * 14.0
		var im := spawn_enemy("imp", ip)
		if im != null:
			im.awake = true
			im.provoked = true

## no health comes back by itself: only a draught or Mending, a little each tick (from `_update_player`, and
## space.gd's tick out there: user, 23 Nov, "Healing spell didn't work in space")
func heal_tick(m: Mage) -> void:
	if m.heal_left > 0.0 and not m.dead:
		var hh := minf(m.heal_left, Defs.HEAL_RATE)
		m.hp = minf(m.max_hp, m.hp + hh)
		m.heal_left -= hh
		if m.hp >= m.max_hp:
			m.heal_left = 0.0
		if frame % 6 == 0:
			_particle(m.pos + Vector2(randf() - 0.5, randf() - 0.5) * 10.0, m.pos.normalized() * 0.4, 24, Color(0.55, 1.0, 0.6), true, -0.01)
	# (and a draught's cooldown, and the draughts working on you, wear off as time goes by)
	if m.potion_cd > 0:
		m.potion_cd -= 1
	for bk in m.buffs.keys():
		m.buffs[bk] = int(m.buffs[bk]) - 1
		if int(m.buffs[bk]) <= 0:
			m.buffs.erase(bk)
			if m.local:
				ui.toast("The %s wears off" % Defs.DRAUGHTS[bk]["name"], Color(0.8, 0.8, 0.9), 2.0)

## (user, 22 Nov: "a bit too many enemies and spawn rate are a bit too aggressive on the starting planet ...
## give the player some breathing room if they kill all the enemies in an area. maybe we only spawn enemies
## farther away from the player")
const SPAWN_EVERY := 150          # ticks between tries (the first planet: FIRST_CALM times that)
const FIRST_CALM := 1.7
const SPAWN_MIN_DIST := 160.0     # nothing comes in nearer than this, and never in view
const QUIET_TICKS := 60 * 90      # an area you've cleared stays quiet this long...
const QUIET_R := 450.0            # ...this far round where you cleared it
var quiet_until := -1
var quiet_at := Vector2.ZERO

## how many foes (not guardians) may be about at once: fewer on the first planet, more at night
func spawn_cap(night: bool) -> int:
	if sky_ev == "bloodmoon":
		return 12
	if int(planet.get("index", 0)) == 0:
		return 5 if night else 3
	return 7 if night else 5

## every foe near you is gone (prey and sleepers aren't foes): the area falls quiet for a while
func _check_cleared() -> void:
	for e in enemies:
		if e.dead or e.boss or e.asleep:
			continue
		if e.d.has("def") and String(e.d["def"].get("temper", "")) == "prey":
			continue
		if e.pos.distance_to(player.pos) < 320.0:
			return
	var was_quiet := frame < quiet_until and player.pos.distance_to(quiet_at) < QUIET_R
	quiet_until = frame + QUIET_TICKS
	quiet_at = player.pos
	if not was_quiet:
		ui.toast("The area falls quiet", Color(0.7, 0.9, 1.0), 2.5)

func _try_spawn() -> void:
	if not _spawn_req.is_empty():
		_spawn_finish()
		return
	spawn_timer -= 1
	if spawn_timer > 0 or dead:
		return
	var first_world := int(planet.get("index", 0)) == 0
	spawn_timer = int(float(SPAWN_EVERY) * (FIRST_CALM if first_world else 1.0) / (maxf(float(clim.get("wild", 1.0)), 0.3) * spawn_mult()))
	if frame < quiet_until and player.pos.distance_to(quiet_at) < QUIET_R and sky_ev != "bloodmoon":
		return
	var night := _local_daylight(player.pos) < 0.3
	if _spawn_room() <= 0:
		return
	var a := atan2(player.pos.y, player.pos.x)
	var sa: Vector4 = gpu.surf_at(a)
	var r := player.pos.length()
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
	var swim: bool = d["def"].get("swim", false) if d.has("def") else false
	# Foes come in from out of sight, never popping up (or dropping in) on screen. How far the
	# view reaches from the mage, in world cells (a screen pixel is ustep * r cells across):
	var reach_x := VW * 0.5 * zoom * maxf(1.0, ustep * r) + float(d["w"]) + 10.0
	var cv := _view()
	var ca := atan2(cv.y, cv.x)
	if (not d["fly"] or go == "burrow" or go == "slither") and r > sa.x - 14.0 and not swim:
		# on the ground just past the edge of the view (it waits, still, until you come near)
		for tries in 6:
			var side := -1.0 if randf() < 0.5 else 1.0
			var dist := maxf(reach_x, SPAWN_MIN_DIST) + randf_range(10.0, 80.0)
			var ga := ca + side * dist / maxf(sa.x, 1.0)
			var gs: Vector4 = gpu.surf_at(ga)
			if gpu.surf_b(ga).y > gs.x:
				continue                      # under the sea
			var gp := Vector2(cos(ga), sin(ga)) * (gs.x + float(d["h"]) * 0.5 + 1.0)
			if absf((gp - player.pos).dot(basis_d(a))) > 80.0:
				continue                      # a cliff far above or below: not where you'd meet it
			if go == "burrow" and in_grid(gp, 8.0) and not Ecology.diggable_under(self, gp):
				continue                      # (a burrower lives in soft ground: not under rock or a floor)
			var first := spawn_enemy(type, gp)
			if d.has("def"):
				Ecology.on_spawn(self, first)
			# (a pack or a herd comes together, a few strides apart, following the first: as many as the
			# cap leaves room for)
			for pk in mini(pack - 1, _spawn_room()):
				var pa := ga + side * float(pk + 1) * (float(d["w"]) + 6.0) / maxf(gs.x, 1.0)
				var mate := spawn_enemy(type, Vector2(cos(pa), sin(pa)) * (gpu.surf_at(pa).x + float(d["h"]) * 0.5 + 1.0))
				mate.leader = first
				mate.asleep = first.asleep
			return
		return
	# underground (and anything that flies or swims): off to the side of the view, past it and never
	# nearer than SPAWN_MIN_DIST, read straight from the world there (the collision grid is little wider
	# than the view, and a walker put in over the screen fell into it: user, 22 Nov). A walker stands on a
	# floor, a flier is in open air, a swimmer in water; it waits there, still, until you come near.
	# The read goes out with the next GPU frame (`gpu.request_rect`) and `_spawn_finish` places it when
	# it's back: read at once, it stalled the frame (user, 22 Nov: a hitch).
	_spawn_req = {"type": type, "reach": reach_x, "surf_flier": r > sa.x - 14.0 and not swim, "tries": 0}
	_spawn_ask()

## a waiting spawn's next look: a rectangle off to one side of you
func _spawn_ask() -> void:
	var pc := Build.cell_of(player.pos)
	var side := -1 if randf() < 0.5 else 1
	var dc := side * int(maxf(float(_spawn_req["reach"]), SPAWN_MIN_DIST) + randf_range(10.0, 70.0))
	var c0 := pc.x + dc - SPAWN_RW / 2
	var r0 := pc.y - (70 if bool(_spawn_req["surf_flier"]) else 45)
	_spawn_req["c0"] = c0
	_spawn_req["r0"] = r0
	_spawn_req["id"] = gpu.request_rect(posmod(c0, Defs.NS), r0, SPAWN_RW, SPAWN_RH)
	_spawn_req["t"] = frame
	_spawn_req["tries"] = int(_spawn_req["tries"]) + 1

## how many more foes the cap (`spawn_cap`, by the local time of day) has room for
func _spawn_room() -> int:
	var count := 0
	for e in enemies:
		if not e.boss:
			count += 1
	return spawn_cap(_local_daylight(player.pos) < 0.3) - count

const SPAWN_RW := 40
const SPAWN_RH := 90
var _spawn_req := {}

## A waiting spawn's rectangle is back: find an open box the foe's size in it (a walker on a floor);
## no room, another look (three at most).
func _spawn_finish() -> void:
	var rr: Dictionary = gpu.take_rect(int(_spawn_req["id"]))
	if rr.is_empty():
		if frame - int(_spawn_req["t"]) > 20:
			_spawn_req = {}              # (lost: a planet made meanwhile, say)
		return
	var type: String = _spawn_req["type"]
	var d: Dictionary = Defs.enemy_def(type)
	var swim: bool = d["def"].get("swim", false) if d.has("def") else false
	var walker: bool = not d["fly"] and not swim
	var surf_flier: bool = _spawn_req["surf_flier"]
	var bw := int(ceil(float(d["w"]))) + 2
	var bh := int(ceil(float(d["h"]))) + 2
	var c0: int = _spawn_req["c0"]
	var fgs: PackedInt32Array = rr["fg"]
	var RW := SPAWN_RW
	var RH := SPAWN_RH
	# open[x + y * RW], then run[...]: how many open cells end at that one, counting down from above
	var run := PackedInt32Array()
	run.resize(RW * RH)
	for yy in RH:
		for xx in RW:
			var kd: int = Defs.KIND[fgs[yy * RW + xx] & 255]
			var op: bool = (kd == Defs.K_LIQUID) if swim else (kd == Defs.K_EMPTY or kd == Defs.K_GAS)
			run[yy * RW + xx] = ((run[(yy - 1) * RW + xx] if yy > 0 else 0) + 1) if op else 0
	var i0 := randi() % RW
	for q in 12:
		var ic := (i0 + q * 7) % RW
		if ic - bw / 2 < 0 or ic + bw / 2 >= RW:
			continue
		for jb in range(bh, RH - 1):
			if walker:
				var ft: int = Defs.KIND[fgs[jb * RW + ic] & 255]
				if ft != Defs.K_SOLID and ft != Defs.K_POWDER:
					continue
			var fits := true
			for xx2 in range(ic - bw / 2, ic + bw / 2 + 1):
				if run[(jb - 1) * RW + xx2] < bh:
					fits = false
					break
			if not fits:
				continue
			var sp := Build.cell_pos(c0 + ic, jb - bh / 2)
			if surf_flier and sp.length() < gpu.surf_at(atan2(sp.y, sp.x)).x + 4.0:
				continue                  # (a bird of the surface comes in through the air, not a cave)
			if sp.distance_to(player.pos) < SPAWN_MIN_DIST - 2.0:
				continue                  # (you came this way while it was read)
			if _spawn_room() <= 0:
				_spawn_req = {}               # (the cap filled up while this was read back)
				return
			var cfirst := spawn_enemy(type, sp)
			if d.has("def"):
				Ecology.on_spawn(self, cfirst)
			if type == "bat" and randf() < 0.5 and _spawn_room() > 0:
				spawn_enemy(type, sp + basis_r(atan2(sp.y, sp.x)) * 6.0 - basis_d(atan2(sp.y, sp.x)) * 4.0)
			_spawn_req = {}
			return
	if int(_spawn_req["tries"]) < 3:
		_spawn_ask()
	else:
		_spawn_req = {}

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
	if parts.size() > int(1500.0 * _fxb) or (_fxb < 1.0 and randf() > _fxb):
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
		rain_target = 0.0 if raining else (0.4 + randf() * 0.6 if randf() < minf(0.92, 0.55 * float(clim.get("storm", 1.0))) else 0.0)
		weather_timer = int(60 * (40 + randf() * 70))
		_wind_dir = 1.0 if randf() < 0.5 else -1.0        # (each spell of weather blows its own way)
	rain += (rain_target - rain) * 0.002
	flash *= 0.85
	var b := _biome_at(atan2(player.pos.y, player.pos.x))
	if b["weather"] == "rain" and rain > 0.6 and randf() < 0.0012 * float(clim.get("storm", 1.0)):
		flash = 1.2
		shake = 5.0

## The planet's climate (Defs.climate): a wind that gusts harder in a storm and turns with each spell of
## weather, pushing you about in the open air; what it blows across the view (snow on a frozen world, sand in
## a dust storm, embers rising off a volcanic one); and whether you're out under the open sky.
func _update_climate() -> void:
	var cw: float = float(clim.get("wind", 0.0))
	var gust := 0.6 + 0.4 * sin(time * 0.0031) * sin(time * 0.00071 + 1.3)
	wind += (cw * (0.3 + 0.7 * rain) * gust * _wind_dir + sky_wind * gust - wind) * 0.01
	if frame % 4 == 0:
		exposed = _open_sky(player.pos)
	_weather_fx()

## What's falling or blowing, drawn by weather.gd, each with its own look (user, 22 Nov: hail looked the
## same as rain): rain streaks and splashes over the simulated drops, hail stones that bounce and melt
## (no rain cells fall in a hail storm: render.comp draws a falling drop pale, like a hailstone), swaying
## snowflakes, tumbling ash, embers rising off a volcanic world, dust and sand blown along. They come in
## at the edges of the screen and stop on anything solid, so a roof keeps them off. Only near the
## surface: underground, in space or on the map nothing falls.
func _weather_fx() -> void:
	if weather == null or player.dead or space.active or state == "map":
		return
	var a := atan2(player.pos.y, player.pos.x)
	if player.pos.length() < gpu.surf_at(a).x - 60.0:
		return
	var br := basis_r(a)
	var bd := basis_d(a)
	var b := _biome_at(a)
	var wk: String = b["weather"]
	var hail := sky_ev == "hail"
	if hail:
		weather.emit(weather.HAIL, 4.5 * sky_ramp(), br, bd, wind)
	elif wk == "rain" and sky_rain > 0.08:
		weather.emit(weather.RAIN, sky_rain * 5.0, br, bd, wind)
	elif wk == "snow" and sky_rain > 0.08:
		weather.emit(weather.SNOW, sky_rain * 2.4, br, bd, wind)
	elif wk == "ash" and sky_rain > 0.08:
		weather.emit(weather.ASH, sky_rain * 2.0, br, bd, wind)
	if wk == "snow" and absf(wind) > 0.25:
		weather.emit(weather.SNOW, absf(wind) * 2.6, br, bd, wind)     # a blizzard
	if float(clim.get("dust", 0.0)) > 0.0 and wk == "clear" and rain > 0.2:
		weather.emit(weather.DUST, rain * float(clim["dust"]) * 3.0, br, bd, wind)     # a dust storm
	if sky_ev == "sandstorm":
		weather.emit(weather.DUST, 5.0 * sky_ramp(), br, bd, wind)
	if float(clim.get("heat", 0.0)) > 0.0:
		weather.emit(weather.EMBER, 0.35 * float(clim["heat"]), br, bd, wind)     # embers drifting up

# ============================================================ sky events ====
## Now and then something happens in the sky (Defs.SKY_EVENTS), picked by the planet's kind and the
## time of day: a meteor shower, an eruption, a squall, a great sandstorm, will-o'-wisps, an aurora, hail,
## a blood moon, fireworks. Each runs for a while (fading in and out) and has its own doings below.
func _update_sky_events() -> void:
	sky_tint = Color(0, 0, 0, 0)
	sky_wind = 0.0
	for k in range(sky_fx.size() - 1, -1, -1):
		var fx: Dictionary = sky_fx[k]
		fx["life"] = int(fx["life"]) - 1
		if fx.has("vel"):
			fx["pos"] = (fx["pos"] as Vector2) + (fx["vel"] as Vector2)
		if fx["kind"] == "rocket" and int(fx["life"]) <= 0:
			_firework_burst(fx["pos"], fx["col"])
		if int(fx["life"]) <= 0:
			sky_fx.remove_at(k)
	if space.active or player == null or state != "play":
		return
	if sky_ev == "":
		_sky_roll += 1
		if _sky_roll >= Defs.SKY_EVENT_EVERY:
			_sky_roll = 0
			if randf() < Defs.SKY_EVENT_CHANCE and not testing:
				var id := _pick_sky_event()
				if id != "":
					start_sky_event(id)
		return
	sky_t += 1
	_sky_next -= 1
	var ramp := sky_ramp()
	match sky_ev:
		"meteors": _sky_meteors()
		"eruption": _sky_eruption(ramp)
		"squall": _sky_squall(ramp)
		"sandstorm": _sky_sandstorm(ramp)
		"wisps": _sky_wisps()
		"hail": _sky_hail(ramp)
		"bloodmoon": sky_tint = Color(0.5, 0.02, 0.02, 0.07 * ramp)
		"fireworks": _sky_fireworks()
	if sky_t >= sky_dur:
		end_sky_event()

## how far in it is: rising from 0 to 1 over its first 5 s, falling back over its last 5 s
func sky_ramp() -> float:
	if sky_ev == "":
		return 0.0
	return clampf(minf(float(sky_t), float(sky_dur - sky_t)) / 300.0, 0.0, 1.0)

## (the GPU's share of it: P.p[125].y the aurora, .z the blood moon)
func sky_level(id: String) -> float:
	return sky_ramp() if sky_ev == id else 0.0

func spawn_mult() -> float:
	return 2.5 if sky_ev == "bloodmoon" else 1.0

func _pick_sky_event() -> String:
	var kind := String(planet.get("kind", "temperate"))
	var day := _local_daylight(player.pos)
	var tot := 0.0
	var opts := []
	for id in Defs.SKY_EVENTS:
		var ev: Dictionary = Defs.SKY_EVENTS[id]
		var w := float((ev["kinds"] as Dictionary).get(kind, 0.0))
		var when := String(ev["when"])
		if w <= 0.0 or (when == "night" and day > 0.3) or (when == "day" and day < 0.6):
			continue
		opts.append([id, w])
		tot += w
	var r := randf() * tot
	for o in opts:
		r -= float(o[1])
		if r <= 0.0:
			return String(o[0])
	return ""

func start_sky_event(id: String) -> void:
	end_sky_event()
	var ev: Dictionary = Defs.SKY_EVENTS[id]
	sky_ev = id
	sky_t = 0
	sky_dur = randi_range(int(ev["dur"][0]), int(ev["dur"][1]))
	_sky_next = 120
	ui.toast("%s. %s" % [ev["name"], ev["msg"]], Color(0.85, 0.85, 1.0), 6.0)
	match id:
		"eruption":
			sky_vent = _eruption_vent()
			audio.play("rumble", sky_vent, 1.0)
			shake = maxf(shake, 6.0)
		"wisps":
			_spawn_sky_wisps(5)
	sky_stats[id] = int(sky_stats.get(id, 0)) + 1

func end_sky_event() -> void:
	sky_ev = ""
	sky_t = 0
	sky_wisps.clear()

## a point on the ground about `cells` along the surface from where you are (either side)
func _ground_off(cells: float) -> Vector2:
	var a := atan2(player.pos.y, player.pos.x) + cells / Defs.RS0
	return Vector2(cos(a), sin(a)) * gpu.surf_at(a).x

## meteors: shooting stars streak across the sky, and every so often one comes down not far off
func _sky_meteors() -> void:
	var up: Vector2 = player.pos.normalized()
	var high: bool = player.pos.length() > gpu.surf_at(atan2(player.pos.y, player.pos.x)).x - 10.0
	if high and randf() < 0.12:
		var sp := Vector2(randf() * float(VW), randf() * float(VH) * 0.4)
		var wp: Vector2 = screen_to_world(sp)
		if wp.length() > gpu.surf_at(atan2(wp.y, wp.x)).x + 50.0:
			var dir: Vector2 = (basis_r(atan2(up.y, up.x)) * (1.0 if randf() < 0.5 else -1.0) - up * randf_range(0.2, 0.6)).normalized()
			sky_fx.append({"kind": "streak", "pos": wp, "vel": dir * randf_range(5.0, 9.0), "life": 14 + randi() % 10, "col": Color(0.85, 0.92, 1.0)})
	if _sky_next <= 0:
		_sky_next = randi_range(500, 900)
		meteor_fall(randf_range(60.0, 200.0) * (1.0 if randf() < 0.5 else -1.0))

## a meteorite comes down `cells` along the ground from you: a fiery rock from high up, `slant` cells
## to one side of straight above
func meteor_fall(cells: float, slant := 110.0) -> void:
	var to := _ground_off(cells)
	var upn := to.normalized()
	var side := Vector2(upn.y, -upn.x) * (1.0 if randf() < 0.5 else -1.0)
	var from := to + upn * 230.0 + side * slant
	_spawn_proj("meteor", from, (to - from).normalized() * float(Defs.PROJ["meteor"]["speed"]), "sky")
	sky_stats["meteor_falls"] = int(sky_stats.get("meteor_falls", 0)) + 1

## where it lands: a blast, fire, and a lump of seared rock round a heart of star iron
func _meteorite(p: Vector2) -> void:
	_explode(p, 7.0, 2, 1, 30.0)
	# the lump lies at the bottom of its crater (resting on the ground, not hanging in the blast's middle)
	var lump := p - p.normalized() * 4.0
	brushes.append([lump, 1.15, 3, Defs.STARIRON, 0, 0, 0])      # (a few cells: asteroids stay the real source)
	brushes.append([lump, 3.3, 3, Defs.MAGMAROCK, 0, 0, 0])
	shake = maxf(shake, 9.0)
	for m in players:
		var d: float = m.pos.distance_to(p)
		if not m.dead and d < 14.0:
			hurt(m, 18.0 * (1.0 - d / 14.0) + 4.0, (m.pos - p).normalized() * 2.0, true)
	sky_stats["meteorites"] = int(sky_stats.get("meteorites", 0)) + 1
	sky_stats["meteor_at"] = p
	if int(sky_stats["meteorites"]) == 1 or randf() < 0.3:
		var side := "east" if (p - player.pos).dot(basis_r(atan2(player.pos.y, player.pos.x))) > 0.0 else "west"
		ui.toast("A meteorite came down to the %s: there's star iron in its heart" % side, Color(1.0, 0.85, 0.6), 4.0)

## an eruption's vent: the highest ground of a few spots a little way off
func _eruption_vent() -> Vector2:
	var best := Vector2.ZERO
	for k in 8:
		var q := _ground_off(randf_range(110.0, 220.0) * (1.0 if k % 2 == 0 else -1.0))
		if best == Vector2.ZERO or q.length() > best.length():
			best = q
	return best

func _sky_eruption(ramp: float) -> void:
	var up: Vector2 = sky_vent.normalized()
	var r := basis_r(atan2(up.y, up.x))
	sky_tint = Color(0.9, 0.25, 0.05, 0.10 * ramp)
	lights.append([sky_vent + up * 10.0, 90.0 * ramp, Color(1.6, 0.6, 0.2)])
	for k in 3:
		_particle(sky_vent + up * randf_range(2.0, 10.0) + r * randf_range(-5.0, 5.0), up * randf_range(0.6, 1.6) + r * (randf() - 0.5) * 0.5,
			60 + randi() % 60, Color(0.25, 0.22, 0.22) if k > 0 else Color(1.0, 0.5, 0.15), k == 0, -0.004)
	if sky_t % 90 == 0:
		audio.play("rumble", sky_vent, 0.8)
		shake = maxf(shake, 3.0)
	if _sky_next <= 0 and ramp > 0.3:
		_sky_next = randi_range(22, 45)
		var v: Vector2 = up * randf_range(3.6, 5.2) + r * randf_range(-1.4, 1.4)
		_spawn_proj("lavabomb", sky_vent + up * 6.0, v, "sky")
		sky_stats["bombs"] = int(sky_stats.get("bombs", 0)) + 1

## is surface column c within `pad` columns of a generated structure?
func _near_structure(c: int, pad: int) -> bool:
	for inf in builds.infos:
		var d := posmod(c - int(inf["x0"]) + pad, Defs.NS)
		if d < int(inf["w"]) + 2 * pad:
			return true
	return false

## a squall: a gale, rain, and lightning striking the ground near you
func _sky_squall(ramp: float) -> void:
	sky_wind = 0.9 * _wind_dir * ramp
	rain_target = maxf(rain_target, 0.95)
	rain = minf(1.0, rain + 0.004)
	if _sky_next <= 0:
		_sky_next = randi_range(150, 330)
		lightning_strike(randf_range(30.0, 160.0) * (1.0 if randf() < 0.5 else -1.0))

## lightning out of the sky onto the ground `cells` along from you: a jagged bolt, fire where it lands,
## and it hurts anyone close
func lightning_strike(cells: float) -> void:
	# (never into a town: it picks open ground away from any structure when it can)
	var pc := cells
	for k in 6:
		var ca := atan2(player.pos.y, player.pos.x) + pc / Defs.RS0
		if not _near_structure(int(fposmod(ca, TAU) / TAU * Defs.NS), 30):
			break
		pc = randf_range(30.0, 200.0) * (1.0 if randf() < 0.5 else -1.0)
	var to := _ground_off(pc)
	var up := to.normalized()
	var side := Vector2(up.y, -up.x)
	var pts := PackedVector2Array()
	var from := to + up * 200.0 + side * randf_range(-30.0, 30.0)
	for k in 12:
		var q := from.lerp(to, float(k) / 11.0)
		pts.append(q + side * (randf_range(-7.0, 7.0) if k > 0 and k < 11 else 0.0))
	sky_fx.append({"kind": "bolt", "pts": pts, "life": 9})
	flash = 1.2
	shake = maxf(shake, 6.0)
	audio.play("boom", to, 1.0, 0.8)
	brushes.append([to + up * 1.5, 1.8, 3, Defs.FIRE, 0, 0, 0])     # (a scorch: fire in the air where it hit)
	lights.append([to, 80.0, Color(1.3, 1.4, 1.8)])
	Ecology.scare(self, to, 10.0)
	for m in players:
		if not m.dead and m.pos.distance_to(to) < 12.0:
			hurt(m, 14.0, (m.pos - to).normalized() * 2.0, true)
	sky_stats["strikes"] = int(sky_stats.get("strikes", 0)) + 1

## a great sandstorm: a gale, the view hazed with blowing sand
func _sky_sandstorm(ramp: float) -> void:
	sky_wind = 1.0 * _wind_dir * ramp
	var under: bool = player.pos.length() < gpu.surf_at(atan2(player.pos.y, player.pos.x)).x - 14.0
	sky_tint = Color(0.78, 0.6, 0.36, (0.08 if under else 0.3) * ramp)
	if under:
		return
	# (the sand itself is blown along by weather.gd, `_weather_fx`)

## will-o'-wisps: lights drifting a little above the ground, shy of you; catch one for its wisp ore
func _spawn_sky_wisps(n: int) -> void:
	for k in n:
		var g := _ground_off(randf_range(50.0, 190.0) * (1.0 if k % 2 == 0 else -1.0))
		var hp: Vector2 = g + g.normalized() * randf_range(8.0, 24.0)
		sky_wisps.append({"pos": hp, "vel": Vector2.ZERO, "home": hp, "ph": randf() * TAU})

func _sky_wisps() -> void:
	for k in range(sky_wisps.size() - 1, -1, -1):
		var w: Dictionary = sky_wisps[k]
		var p: Vector2 = w["pos"]
		var v: Vector2 = w["vel"]
		v += Vector2(randf() - 0.5, randf() - 0.5) * 0.06 + ((w["home"] as Vector2) - p) * 0.0006
		var away: Vector2 = p - player.pos
		if away.length() < 45.0:
			v += away.normalized() * 0.02
		var gr: float = gpu.surf_at(atan2(p.y, p.x)).x
		if p.length() < gr + 5.0:
			v += p.normalized() * 0.05                   # (never into the ground)
		v = v.limit_length(0.75)
		p += v
		w["pos"] = p
		w["vel"] = v
		w["ph"] = float(w["ph"]) + 0.05
		lights.append([p, 22.0 + 4.0 * sin(float(w["ph"]) * 3.0), Color(0.45, 0.8, 1.5)])
		if randf() < 0.3:
			_particle(p + Vector2(randf() - 0.5, randf() - 0.5) * 2.0, -v * 0.3, 20 + randi() % 15, Color(0.6, 0.9, 1.0), true, -0.002)
		if p.distance_to(player.pos) < 9.0 and not player.dead:
			player.inv[Defs.WISP] += 4
			player.mana = minf(player.max_mana, player.mana + 30.0)
			audio.play("rare", p, 0.7)
			for q in 16:
				_particle(p, Vector2(randf() - 0.5, randf() - 0.5) * 1.6, 20 + randi() % 20, Color(0.6, 0.9, 1.0), true, 0.0)
			ui.toast("You caught a will-o'-wisp: +4 Wisp Ore, and your mana", Color(0.6, 0.9, 1.0), 3.0)
			sky_stats["caught"] = int(sky_stats.get("caught", 0)) + 1
			sky_wisps.remove_at(k)

## hail: pellets of ice racing down; out in the open now and then one stings
func _sky_hail(ramp: float) -> void:
	sky_wind = 0.3 * _wind_dir * ramp
	# (the stones themselves are weather.gd's, `_weather_fx`: chunky, bouncing, melting; a cold grey haze)
	sky_tint = Color(0.62, 0.7, 0.82, 0.12 * ramp)
	if not exposed:
		return
	if _sky_next <= 0:
		_sky_next = randi_range(35, 70)
		hurt(player, 1.5, Vector2.ZERO, true)
		audio.play("hit", player.pos, 0.35, 1.6)
		# (a stone cracks on your hat)
		var up: Vector2 = -basis_d(atan2(player.pos.y, player.pos.x))
		for q in 4:
			weather.spawn(weather.CHIP, player.pos + up * 9.0, up.rotated(randf_range(-1.3, 1.3)) * randf_range(0.5, 1.3), 12 + randi() % 8)
		sky_stats["hail_hits"] = int(sky_stats.get("hail_hits", 0)) + 1
		if int(sky_stats["hail_hits"]) == 1:
			ui.toast("Hail stings you: get under a roof", Color(0.8, 0.9, 1.0), 2.5)

## fireworks: rockets rise from the land round you and burst in colour
func _sky_fireworks() -> void:
	if _sky_next <= 0:
		_sky_next = randi_range(25, 60)
		var g := _ground_off(randf_range(-150.0, 150.0))
		var up := g.normalized()
		var cols := [Color(1.0, 0.35, 0.3), Color(0.4, 0.8, 1.0), Color(1.0, 0.85, 0.3), Color(0.6, 1.0, 0.5), Color(0.9, 0.5, 1.0), Color(1.0, 1.0, 1.0)]
		var rv: Vector2 = up * randf_range(2.0, 2.6) + Vector2(up.y, -up.x) * randf_range(-0.3, 0.3)
		sky_fx.append({"kind": "rocket", "pos": g + up * 2.0, "vel": rv, "life": 30 + randi() % 16, "col": cols[randi() % cols.size()]})
	for fx in sky_fx:
		if fx["kind"] == "rocket" and randf() < 0.7:
			_particle(fx["pos"], Vector2.ZERO, 12 + randi() % 8, Color(1.0, 0.8, 0.5), true, 0.004)

func _firework_burst(p: Vector2, col: Color) -> void:
	for k in 72:
		var d := Vector2.from_angle(TAU * float(k) / 72.0 + randf() * 0.08)
		var c2: Color = col if k % 4 != 0 else Color(1, 1, 1)
		_particle(p, d * randf_range(0.75, 1.2), 34 + randi() % 22, c2, true, 0.006)
	lights.append([p, 90.0, Color(col.r * 1.6, col.g * 1.6, col.b * 1.6)])
	audio.play("boom", p, 0.45, 1.8)
	sky_stats["bursts"] = int(sky_stats.get("bursts", 0)) + 1

## nothing over this point up to 70 cells (a roof, a cave's ceiling, an overhang: leaves don't count)
func _open_sky(p: Vector2) -> bool:
	if p.length() < gpu.surf_at(atan2(p.y, p.x)).x - 8.0:
		return false
	var up := p.normalized()
	for k in range(6, 72, 3):
		var t := type_at(p + up * float(k))
		if t != Defs.AIR and Defs.KIND[t] == Defs.K_SOLID and t != Defs.LEAF:
			return false
	return true

## A planet kind's slow hazards (Defs.HAZARDS), unless a ward or a relic bears them. `hazard` is the one
## hurting you now; each warns you now and then what would help.
func _hazards(m: Mage, p: Body) -> void:
	hazard = ""
	if m.dead:
		return
	for hz in Defs.HAZARDS:
		var lvl := float(clim.get(hz, 0.0))
		if lvl <= 0.0:
			continue
		var hd: Dictionary = Defs.HAZARDS[hz]
		if m.items.has(String(hd["ward"])) or m.items.has(String(hd["relic"])):
			continue
		var k := _hazard_level(String(hz), m, p) * lvl
		if k <= 0.0:
			continue
		hurt(m, float(hd["dmg"]) * k, Vector2.ZERO, false)
		hazard = String(hz)
		_hz_t[hz] = int(_hz_t.get(hz, 0)) - 1
		if int(_hz_t[hz]) <= 0:
			_hz_t[hz] = 1200
			ui.toast(String(hd["msg"]) % planet.get("name", ""), Color(1.0, 0.7, 0.5), 4.5)

## how hard a hazard bites where you are (0: not here)
func _hazard_level(hz: String, m: Mage, p: Body) -> float:
	match hz:
		"cold":
			if frame % 15 == 0:
				_warm = _near_warmth(p.pos)
			if not exposed or _warm or p.in_liquid:
				return 0.0
			var k := 1.0
			if _local_daylight(p.pos) < 0.3:
				k *= 1.6                                  # (night)
			if absf(wind) > 0.25:
				k *= 1.6                                  # (a blizzard)
			return k
		"sun":
			return 1.0 if exposed and not p.in_liquid and sun_overhead(p.pos) > 0.72 else 0.0
		"miasma":
			if m.fog < 0.25 or p.pos.length() > gpu.surf_at(atan2(p.pos.y, p.pos.x)).x + 70.0:
				return 0.0
			return clampf(m.fog * 1.6, 0.4, 1.5)
		"deep":
			var sea := float(planet.get("sea", -1.0))
			if sea < 0.0 or not p.in_liquid:
				return 0.0
			var under: float = (Defs.RS0 - sea) - p.pos.length()
			return 0.0 if under < 35.0 else 1.0 + (under - 35.0) / 60.0
	return 0.0

## a fire, a torch or lava within about 14 cells (the collision grid round you)
func _near_warmth(wp: Vector2) -> bool:
	var l := to_grid(wp)
	for y in range(int(l.y) - 14, int(l.y) + 15, 2):
		for x in range(int(l.x) - 14, int(l.x) + 15, 2):
			var t := gtype(x, y)
			if t == Defs.FIRE or t == Defs.TORCH or t == Defs.LAVA:
				return true
	return false

## how straight overhead the sun is at p (1: straight up, 0 on the horizon, below 0 at night)
func sun_overhead(wp: Vector2) -> float:
	var sun_a := spawn_angle - 1.1 + time / DAY_LEN * TAU
	return wp.normalized().dot(Vector2(cos(sun_a), sin(sun_a)))

## a night's rest at an inn: the clock runs on to the next morning where you are
func sleep_till_morning() -> void:
	var pa := atan2(player.pos.y, player.pos.x)
	var want := fposmod((pa - 1.2 - spawn_angle + 1.1) / TAU * DAY_LEN, DAY_LEN)
	var now := fposmod(time, DAY_LEN)
	time += fposmod(want - now, DAY_LEN)
	ui.toast("You sleep soundly, and wake with the sun.", Color(1, 0.9, 0.6), 3.0)

## The Core Drive that leaves this planet wants some of its own ore (if it has one): its recipe is
## rewritten for each planet.
func _refresh_recipes() -> void:
	var ko := Defs.kind_ore(planet)
	for i in recipes.size():
		if String(recipes[i]["id"]) != "drive":
			continue
		var r: Dictionary = (recipes[i] as Dictionary).duplicate(true)
		var cost := {Defs.CORE: 30, Defs.STARIRON: 12, Defs.WISP: 10}
		if ko >= 0:
			cost[ko] = Defs.DRIVE_ORE
		r["cost"] = cost
		recipes[i] = r

# ============================================================= crafting ====
## How fast you dig (the ground, and asteroids out in space; not the Remove tool), 1 = the old Stone staff's
## full rate (user, 23 Nov: "slow is fine in the beggining but should get more powerful through progression"):
## each focus digs faster (a plain staff 0.55, the Copper Focus 0.9, the Obsidian 1.3, the Core Siphon 1.8),
## each Delver's Rune forged 30% faster again (`items["delve"]` 0..3), and the Fire Opal gear on top.
const DIG_TIER := [0.55, 0.55, 0.9, 1.3, 1.8]
const DELVE := 1.3
func dig_speed(m: Mage) -> float:
	return float(DIG_TIER[clampi(m.tier, 0, 4)]) * pow(DELVE, float(int(m.items.get("delve", 0)))) * gear("dig_rate", m)

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
		"drive": return skiff_reach() > int(planet.get("index", 0))
		"rimelens": return items.has("rimelens") or dig_r >= 14.0
		"levitate": return items.has("levitate")
		"delve1": return int(items.get("delve", 0)) >= 1
		"delve2": return int(items.get("delve", 0)) >= 2
		"delve3": return int(items.get("delve", 0)) >= 3
	if r.has("gear") or r["cat"] == "Wards" or r["id"] in ["engine", "beam", "sail", "shield", "cannon"]:
		return items.has(String(r["id"]))
	return false

## the furthest planet (by index) the skiff can fly to: one more for every Core Drive fitted (a planet's
## heart, harvested with the Core Siphon, bound in star iron from the asteroids)
func skiff_reach() -> int:
	return int(items.get("reach", 0))

func recipe_unlocked(r: Dictionary) -> bool:
	if r.has("scroll") and not items.has(r["scroll"]):
		return false
	if r.has("part") and not items.has(r["part"]):
		return false
	match r["id"]:
		"tier2": return tier == 1
		"tier3": return tier == 2
		"tier4": return tier == 3 and items.has("heart")
		"delve2": return int(items.get("delve", 0)) >= 1
		"delve3": return int(items.get("delve", 0)) >= 2
		"drive": return tier >= 4 and items.has("skiff")
		"engine", "beam", "sail", "shield", "cannon", "scanner": return items.has("skiff")
	if r.has("gear"):
		# (gear from a planet kind's own ore: once you've found some, and what it builds on)
		var need := String(Defs.GEAR[r["id"]].get("needs", ""))
		if need == "wide" and dig_r < 11.0:
			return false
		for om in r["ores"]:
			if not ore_found(int(om)):
				return false
		return true
	return true

# ------------------------------------------------------ recipes you learn ---
## A journey knows only a handful of recipes at first; the rest are learned (Defs.LEARN: a first find,
## a recipe scroll in a chest, a village keeper, a boss's hoard). `learned` holds the ids learned (saved).
var learned := {}

func knows(r: Dictionary) -> bool:
	return learned.has(String(r["id"])) or bool(Defs.learn_of(r).get("start", false))

## (the test mode knows every recipe already: nothing to learn but in its own check)
func testing_no_learn() -> bool:
	return learned.size() >= recipes.size()

func recipe_by_id(id: String) -> Dictionary:
	for r in recipes:
		if String(r["id"]) == id:
			return r
	return {}

## learn a recipe; `why` is said with it. True if it was new.
func learn(id: String, why := "") -> bool:
	var r := recipe_by_id(id)
	if r.is_empty() or knows(r):
		return false
	learned[id] = true
	if r.has("scroll"):
		items[String(r["scroll"])] = true      # (a spell that had its own scroll: that's what opens it at the forge)
	# (where to find it is said the first few times)
	var tail := " (C: the Wisp Forge, J: the recipe book)" if learned.size() <= 3 else ""
	ui.toast("New recipe: %s%s.%s" % [r["name"], (", " + why) if why != "" else "", tail], Color(0.72, 0.9, 1.0), 6.0)
	audio.play("rare")
	return true

## every recipe known (a journey from before recipes were learned, and the test mode)
func learn_all() -> void:
	for r in recipes:
		learned[String(r["id"])] = true

## first finds teach a material's plain uses: checked every second
func _learn_from_finds() -> void:
	var any := false
	for r in recipes:
		if knows(r):
			continue
		var L: Dictionary = Defs.learn_of(r)
		if not L.has("find"):
			continue
		for m in L["find"]:
			if ore_found(int(m)):
				any = learn(String(r["id"]), "from your first %s" % Defs.NAMES[int(m)]) or any
				break
	if any:
		save_game()

## a recipe scroll in a chest: one not yet known from this place's depth or shallower (1 anywhere, 2 deep
## down or in ruins, keeps and mines, 3 in dungeons and temples). True if one was found.
func _chest_recipe(level: int) -> bool:
	var pool := []
	for r in recipes:
		var L: Dictionary = Defs.learn_of(r)
		if L.has("scroll") and int(L["scroll"]) <= level and not knows(r):
			pool.append(String(r["id"]))
	if pool.is_empty():
		return false
	return learn(String(pool[randi() % pool.size()]), "from a recipe scroll in the chest")

## a boss's hoard holds a recipe found nowhere else: this world's own first (its ore's gear, its ward),
## then an alloy of an ore you've found, then any
func _hoard_recipe() -> bool:
	var ko := Defs.kind_ore(planet)
	var kind := String(planet.get("kind", "temperate"))
	var best := []
	var good := []
	var rest := []
	for r in recipes:
		var L: Dictionary = Defs.learn_of(r)
		if not L.get("hoard", false) or knows(r):
			continue
		var id := String(r["id"])
		if (r.has("gear") and (r["ores"] as Array).has(ko) and ko >= 0) or String(L.get("kind", "")) == kind:
			best.append(id)
		elif r.has("gear") and (ore_found(int(r["ores"][0])) or ore_found(int(r["ores"][-1]))):
			good.append(id)
		else:
			rest.append(id)
	for pool in [best, good, rest]:
		if not pool.is_empty():
			return learn(String(pool[randi() % pool.size()]), "from the hoard")
	return false

## the recipes a village keeper (`role`, or any) sells on this planet
func shop_recipes(role := "") -> Array:
	var kind := String(planet.get("kind", "temperate"))
	var out := []
	for r in recipes:
		var L: Dictionary = Defs.learn_of(r)
		if L.has("shop") and (role == "" or String(L["shop"]) == role) and (String(L.get("kind", "")) == "" or String(L["kind"]) == kind):
			out.append(r)
	return out

func ore_found(om: int) -> bool:
	return player.inv[om] > 0 or items.has("found_%d" % om)

## Ore gear stays out of the forge's list until you've found its ore, but for the first piece of each
## ore, which shows (locked) where that ore is found.
## (An alloy shows, locked, once you've found either of its ores.)
func recipe_hidden(r: Dictionary) -> bool:
	if r.has("part"):
		# (ship parts: once you have a skiff to fit them to)
		return not items.has("skiff") and not items.has(String(r["part"]))
	if r.has("sigil"):
		# (only the guardians this planet has, and not yet beaten)
		return not summoning.callable_biomes().has(String(r["sigil"]))
	if not r.has("gear"):
		return false
	var ores: Array = r["ores"]
	if ores.size() > 1:
		return not (ore_found(int(ores[0])) or ore_found(int(ores[1])))
	if ore_found(int(r["ore"])):
		return false
	for id in Defs.GEAR:
		if Defs.gear_ores(id).size() == 1 and int(Defs.gear_ores(id)[0]) == int(r["ore"]):
			return id != r["id"]
	return false

## What the gear you own does to a stat (Defs.GEAR "mods"): multipliers multiply, the GEAR_ADD stats add
## up. 1.0 (or 0.0 for an added one) with none.
func gear(stat: String, m: Mage = null) -> float:
	var who: Mage = m if m != null else player
	var add: bool = Defs.GEAR_ADD.has(stat)
	var v := 0.0 if add else 1.0
	for id in Defs.GEAR:
		var mods: Dictionary = Defs.GEAR[id]["mods"]
		if mods.has(stat) and who.items.has(id):
			# (forged at an anvil: masterwork, its effect a quarter bigger)
			var q := float(who.items.get("q_" + id, 1.0))
			v = v + float(mods[stat]) * q if add else v * (1.0 + (float(mods[stat]) - 1.0) * q)
	for id2 in Defs.WORK_GEAR:
		var mods2: Dictionary = Defs.WORK_GEAR[id2]["mods"]
		if mods2.has(stat) and who.items.has(id2):
			v = v + float(mods2[stat]) if add else v * float(mods2[stat])
	for bid in who.buffs:
		var mods3: Dictionary = Defs.DRAUGHTS[bid]["mods"]
		if mods3.has(stat):
			v = v + float(mods3[stat]) if add else v * float(mods3[stat])
	return v

## gear a workshop made (Defs.WORK_GEAR): owned from now on, its saved numbers raised once
func own_work_gear(id: String) -> void:
	if items.has(id):
		return
	items[id] = true
	var mods: Dictionary = Defs.WORK_GEAR[id]["mods"]
	max_hp += float(mods.get("max_hp", 0.0))
	hp += float(mods.get("max_hp", 0.0))
	max_mana += float(mods.get("max_mana", 0.0))
	mana_regen += float(mods.get("mana_regen", 0.0))
	_apply_gear()
	ui.toast("%s: %s" % [Defs.WORK_GEAR[id]["name"], Defs.WORK_GEAR[id]["desc"]], Color(1, 0.82, 0.23), 5.0)

## drink a draught from the Still (the satchel: click it): it works for a while through gear()
func drink_draught(m: Mage, id: String) -> bool:
	var n := int(m.items.get(id, 0))
	if n <= 0 or not Defs.DRAUGHTS.has(id):
		return false
	m.items[id] = n - 1
	if int(m.items[id]) <= 0:
		m.items.erase(id)
	var dd: Dictionary = Defs.DRAUGHTS[id]
	m.buffs[id] = int(dd["dur"])
	audio.play("water", m.pos, 0.5)
	var col: Color = dd["col"]
	for k in 16:
		_particle(m.pos + Vector2(randf() - 0.5, randf() - 0.5) * 8.0, m.pos.normalized() * (0.2 + randf() * 0.4), 30 + randi() % 20, col, true, -0.01)
	if m.local:
		ui.toast("%s: %s" % [dd["name"], dd["desc"]], col.lightened(0.3), 3.5)
	return true

## is there an anvil (a workshop station) within reach of the mage? (masterwork ore gear)
func anvil_near(m: Mage = null) -> bool:
	var who: Mage = m if m != null else player
	for st in workshops.list:
		if st.kind == "anvil" and st.pos.distance_to(who.pos) < Defs.ANVIL_REACH:
			return true
	return false

## what owning gear sets once (on forging and on loading): your breath
func _apply_gear() -> void:
	max_breath = 600.0 * gear("breath")

func recipe_lock_text(r: Dictionary) -> String:
	match r["id"]:
		"tier3": return "Needs Copper Focus"
		"tier4": return "Needs Obsidian Focus + the Ember Heart"
		"drive": return "Needs the Core Siphon and the Wisp Skiff"
		"engine", "beam", "sail": return "Needs the Wisp Skiff"
		"shield", "cannon":
			if not items.has(String(r["part"])):
				return "Salvage a %s from a derelict wreck in deep space" % ("Shield Emitter" if r["id"] == "shield" else "Cannon Coil")
			return "Needs the Wisp Skiff"
		"scanner":
			if not items.has("part_scanner"):
				return "Take a Scanner Lens from the vault of a derelict station"
			return "Needs the Wisp Skiff"
		"blink": return "Find the Scroll of Blink in a chest"
		"starfall": return "Find the Scroll of Starfall in a chest"
		"mend": return "Find the Scroll of Mending in a chest"
	if r.has("gear") and String(Defs.GEAR[r["id"]].get("needs", "")) == "wide" and dig_r < 11.0 and ore_found(int(r["ore"])):
		return "Needs Wide Excavation"
	if r.has("ores"):
		var parts := []
		for om in r["ores"]:
			if not ore_found(int(om)):
				var okd := Defs.ore_kind(int(om))
				parts.append("%s (%s)" % [Defs.NAMES[int(om)], (okd + " worlds") if okd != "" else "deep space"])
		if not parts.is_empty():
			return "Needs " + " and ".join(parts)
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
	m.heal_left += Defs.POTION_HEAL * gear("draught_heal", m)
	audio.play("water", m.pos, 0.5)
	ui.toast("Healing Draught: %d left" % (n - 1), Color(0.6, 1.0, 0.65), 1.5)
	return true

func craft(r: Dictionary) -> bool:
	if not knows(r) or recipe_done(r) or not recipe_unlocked(r) or not recipe_affordable(r):
		return false
	audio.play("forge")
	for k in r["cost"]:
		player.inv[int(k)] -= int(r["cost"][k])
	if r.has("give"):
		for k in r["give"]:
			player.inv[int(k)] += int(r["give"][k])
		# (what it made may teach recipes at once: the forge's panel keeps the world waiting, and first finds
		# are otherwise looked for as it ticks; user, 23 Nov: crafted obsidian, no Obsidian Focus)
		if not testing_no_learn():
			_learn_from_finds()
	if r.has("potion"):
		items["potion"] = int(items.get("potion", 0)) + int(r["potion"])
		ui.toast("Healing Draught forged: drink it with H (%d now)" % int(items["potion"]), Color(0.6, 1.0, 0.65), 3.0)
		save_game()
		return true
	if r.has("sigil"):
		var sk := "sigil_" + String(r["sigil"])
		items[sk] = int(items.get(sk, 0)) + 1
		ui.toast("%s forged: lay it on a Summoning Altar in the %s (build mode, Workshops)" % [r["name"], String(Defs.BIOMES[r["sigil"]]["name"]) if Defs.BIOMES.has(r["sigil"]) else r["sigil"]], Color(1, 0.82, 0.23), 4.0)
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
		"delve1", "delve2", "delve3":
			items["delve"] = maxi(int(items.get("delve", 0)), int(String(r["id"]).substr(5)))
			ui.toast("Your staff bites deeper: you dig %d%% as fast as you started" % int(round(dig_speed(player) / 0.55 * 100.0)), Color(1, 0.82, 0.23), 4.0)
		"vital":
			max_hp += 50
			hp = max_hp
			items["vital"] = true
		"mana":
			max_mana += 70
			mana_regen = 0.32
			items["mana_crystal"] = true
		"ward": heat_ward = true
		"hearth", "sunveil", "fenmask", "tidecharm", "engine", "beam", "levitate", "sail", "harness":
			items[String(r["id"])] = true
		"shield", "cannon":
			# (a part salvaged from a wreck, fitted to the skiff: the part is used up)
			items[String(r["id"])] = true
			items.erase(String(r["part"]))
			ui.toast("Fitted to your skiff: %s" % ("the Wisp Shield takes a lightning strike out there, then charges again" if r["id"] == "shield" else "the Wisp Cannon fires with the cast button while you fly in space (the keys steer)"), Color(1, 0.85, 0.4), 5.0)
			save_game()
			return true
		"drive":
			items["reach"] = maxi(skiff_reach(), int(planet.get("index", 0)) + 1)
			var nxt := String(Defs.make_planet(int(items["reach"]))["name"])
			ui.toast("Core Drive fitted: your skiff can reach %s now. Fly up out of the sky and head for it." % nxt, Color(1, 0.85, 0.4), 6.0)
			save_game()
			return true
	if r.has("gear"):
		# ore gear: owned from now on; the saved numbers it raises are raised once, here. Forged within
		# reach of an anvil it's masterwork (items["q_<id>"]): every effect a quarter bigger.
		items[String(r["id"])] = true
		var qm := 1.0
		if anvil_near():
			qm = Defs.MASTERWORK
			items["q_" + String(r["id"])] = qm
			ui.toast("Masterwork! Hammered out at the anvil: %s works a quarter better" % r["name"], Color(1, 0.9, 0.5), 4.0)
			audio.play("rare", player.pos, 0.6)
		var mods: Dictionary = Defs.GEAR[r["id"]]["mods"]
		max_hp += float(mods.get("max_hp", 0.0)) * qm
		hp += float(mods.get("max_hp", 0.0)) * qm
		max_mana += float(mods.get("max_mana", 0.0)) * qm
		mana_regen += float(mods.get("mana_regen", 0.0)) * qm
		if mods.has("dig_r"):
			dig_r = maxf(dig_r, float(mods["dig_r"]))
		_apply_gear()
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
			if k == KEY_J:
				# the recipe book: the forge, opened at its unlearned pages
				if state == "play":
					state = "forge"
					ui.show_forge(true)
				else:
					toggle_forge()
				return
		if state == "map":
			_map_key(k)
			return
		if state == "shop":
			if k == KEY_ESCAPE or k == KEY_F:
				towns.close_shop()
			return
		if state == "station":
			if k == KEY_ESCAPE or k == KEY_F:
				workshops.close()
			return
		if k == KEY_ESCAPE and state == "play":
			ui.toggle_settings()
			return
		if state != "play" or menu_paused():
			return
		if k == KEY_SPACE or k == KEY_W or k == KEY_UP:
			jump_buf = 8   # catch even the quickest tap
		if k == KEY_B:
			_toggle_build()
			return
		if build_on and _build_key(k):
			return
		if space.active and (k == KEY_MINUS or k == KEY_KP_SUBTRACT or k == KEY_EQUAL or k == KEY_KP_ADD):
			space.zoom_by(1 if k == KEY_MINUS or k == KEY_KP_SUBTRACT else -1)     # (- out, + in)
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
		elif k == KEY_X:
			deck_toggle(player)
		elif k == KEY_K:
			call_skiff()
		elif k == KEY_I or k == KEY_TAB:
			ui.toggle_satchel()
		elif k == KEY_M:
			open_map()
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
			learn_all()
			ui.toast("Creative stock: +200 of every material, and every recipe", Color(0.6, 1, 0.6))
	elif state == "map" and (ev is InputEventMouseButton or ev is InputEventMouseMotion):
		_map_mouse(ev)
	elif ev is InputEventMouseButton and ev.pressed and state == "play" and not menu_paused():
		var wheel: bool = ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if wheel and ui.mouse_over_ui(false):
			return                  # scrolling the satchel (past its end, too) never changes the spell
		if build_on and ev.button_index == MOUSE_BUTTON_LEFT:
			build_click = true
		if build_on and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_build_step(-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			return
		if wheel and space.active:
			# (out in space the wheel zooms the view: spells aren't cast out there)
			space.zoom_by(-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
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
		if player.aboard != null:
			ui.toast("Building in the skiff's cabin: Blocks, Back Walls and Furniture go in, the Remove tab takes them out · [ ] size · R new design · T mirror · B to leave", Color(0.95, 0.85, 0.55), 4.5)
		else:
			ui.toast("Build mode: click to place · Q/E category · wheel piece · G how walls and blocks are laid · R new design · T mirror · B to leave", Color(0.95, 0.85, 0.55), 4.0)
	else:
		ui.toast("Build mode off", Color(0.8, 0.8, 0.9), 1.0)

## the pieces of the chosen category, and the chosen one
func build_list() -> Array:
	if build_cat == Build.CAT_SATCHEL:
		return Build.carried_pieces(player.furn, items)
	return Build.in_cat(build_pieces, build_cat)

func build_piece() -> Dictionary:
	var l := build_list()
	if l.is_empty():
		return {}
	return l[clampi(int(build_idx[build_cat]), 0, l.size() - 1)]

## Something carried, put in your hand from the satchel (user, 23 Nov: a bed went in the satchel but
## couldn't be set down from it, and a kiln taken up went nowhere you could see): build mode opens on it,
## ready to set down. what: "furn" (Mage.furn index `idx`), "station" (a kind taken up), "torch", "door".
func hold_carried(what: String, idx := -1, sk := "") -> void:
	if player.aboard != null:
		ui.toast("Step off the ship to set that down", Color(1, 0.8, 0.6), 2.0)
		return
	if not build_on:
		_toggle_build()
	while build_idx.size() < Build.CATS.size():
		build_idx.append(0)
	var want := ""
	match what:
		"furn", "station":
			build_cat = Build.CAT_SATCHEL
			var l := build_list()
			for k in l.size():
				var pc: Dictionary = l[k]
				if (what == "furn" and String(pc["kind"]) == "carried" and int(pc["item"]) == idx) \
						or (what == "station" and String(pc["kind"]) == "station" and String(pc["station"]) == sk):
					build_idx[build_cat] = k
					want = String(pc["name"])
		"torch", "door":
			var pname := "Torch" if what == "torch" else "Wooden Door"
			for pc2 in build_pieces:
				if String(pc2["name"]) == pname:
					build_cat = int(pc2["cat"])
					build_idx[build_cat] = Build.in_cat(build_pieces, build_cat).find(pc2)
					want = pname
	build_prev = {}
	build_drag = false
	if want != "":
		ui.toast("%s in hand: click to set it down · B puts it away" % want, Color(0.95, 0.85, 0.55), 2.5)

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
	var shaped: bool = build_piece().get("kind", "") in ["wall", "block", "remove"]
	if shaped and k == KEY_G:
		build_shape = (build_shape + 1) % Build.SHAPES.size()
		if build_piece()["kind"] != "wall" and build_shape == 0:
			build_shape = 1                   # blocks aren't painted
		build_drag = false
		ui.toast("Lay: " + Build.SHAPES[build_shape], Color(0.95, 0.85, 0.55), 1.0)
		return true
	if shaped and (k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT):
		build_thick = clampi(build_thick + (1 if k == KEY_BRACKETRIGHT else -1), 1, Build.THICK_MAX)
		return true
	var structure: bool = build_piece().get("kind", "") == "structure"
	var stairs: bool = build_piece().get("kind", "") == "stairs"
	if stairs and (k == KEY_BRACKETLEFT or k == KEY_BRACKETRIGHT):
		build_rise = clampi(build_rise + (Build.STAIR_STEP if k == KEY_BRACKETRIGHT else -Build.STAIR_STEP), Build.STAIR_RISE_MIN, Build.STAIR_RISE_MAX)
		return true
	if stairs and (k == KEY_MINUS or k == KEY_EQUAL):
		build_rise = clampi(build_rise + (40 if k == KEY_EQUAL else -40), Build.STAIR_RISE_MIN, Build.STAIR_RISE_MAX)
		return true
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

## a block someone built (a structure's, or yours) at a cell, not the planet's own ground
func _built_at(col: int, row: int) -> bool:
	return type_at(Build.cell_pos(col, row)) in [Defs.BRICK, Defs.MASONRY, Defs.PLANK, Defs.TILE, Defs.GLASS, Defs.MOSSBLOCK, Defs.RUNESTONE, Defs.WOODDOOR]

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
	# (each column's floor is kept a few frames: the build preview asks for the same columns again and
	# again as a piece slides along, and each look down is up to `reach` cells read through the grid)
	if frame - _floor_memo_frame > 8:
		_floor_memo.clear()
		_floor_memo_frame = frame
	for i in w:
		var mk := Vector3i(c0 + i, row, reach)
		var f: int
		if _floor_memo.has(mk):
			f = _floor_memo[mk]
		else:
			f = _floor_below(c0 + i, row, reach)
			_floor_memo[mk] = f
		if f >= 0 and (best < 0 or f < best):
			best = f
	return best

## offsets to try, nearest first, when a piece doesn't fit where you point: 2, -2, 4, -4 ... up to `reach`
func _slide_offsets(reach: int) -> Array:
	var out := []
	var k := 2
	while k <= reach:
		out.append(k)
		out.append(-k)
		k += 2
	return out

## has the cursor rested on this cell a few frames? (and the preview not settled there yet: it's worked out
## again once it has, so a piece slides into place as soon as you stop)
func _rested(cell: Vector2i) -> bool:
	if cell != _cur_cell:
		_cur_cell = cell
		_cur_since = frame
		_fit_key = ""
	if frame - _cur_since == 2:
		_fit_key = ""
	return frame - _cur_since >= 2

## the workshops within `pad` of p (for a piece being placed there)
func _stations_near(p: Vector2, pad: float) -> Array:
	var out := []
	for st in workshops.list:
		if st.pos.distance_to(p) < pad + maxf(st.w, st.h):
			out.append(st)
	return out

## is world point p inside one of these workshops?
func _station_over(list: Array, p: Vector2) -> bool:
	for st in list:
		var l: Vector2 = workshops._local(st, p)
		if absf(l.x) < st.w * 0.5 and absf(l.y) < st.h * 0.5:
			return true
	return false

## what's in front at a cell, in words, for "it doesn't fit" (a door, a wall, the ground...)
func _what_blocks(col: int, row: int) -> String:
	var t := type_at(Build.cell_pos(col, row))
	if t == Defs.WOODDOOR:
		return "a door is in the way"
	if Defs.KIND[t] == Defs.K_POWDER:
		return "%s is in the way" % Defs.NAMES[t].to_lower()
	return "a wall or the ground is in the way"

## Would a piece of furniture (its pixel rows) go down centred on column cx, standing on the floor under
## row cy (or, a wall piece, hung there)? {ok, why, pc (its cells), bottom, tree}
func _prop_fit(rows: Array, wall: bool, cx: int, cy: int, quick := false) -> Dictionary:
	var bottom := cy + rows.size() / 2
	var why := ""
	var ok := true
	if not wall:
		# it stands on the highest ground under it (a leg may stand on a lower step)
		var pw: int = rows[0].length()
		bottom = _floor_span(cx - pw / 2, pw, cy - rows.size() / 2, 40)
	if bottom < 0:
		ok = false
		why = "no floor under it"
		bottom = cy + rows.size() / 2
	if quick and not ok:
		return {"ok": false}
	var pc := Build.prop_cells(rows, cx, bottom, build_flip)
	var feet := 0
	var held := 0
	var tree := false
	# (a workshop standing there: furniture would go behind it, half hidden)
	var near_st := _stations_near(Build.cell_pos(cx, bottom - rows.size() / 2), float(maxi(rows.size(), rows[0].length())))
	for c in pc:
		var cc: Vector2i = Vector2i(int(c[0]), int(c[1]))
		if quick and not ok:
			return {"ok": false}
		if not near_st.is_empty() and _station_over(near_st, Build.cell_pos(cc.x, cc.y)):
			if ok:
				why = "a workshop is standing there"
				build_why_cell = cc
			ok = false
			continue
		# room in front, and no other furniture where it goes (a back wall behind it is fine)
		var bga := _bg_at(cc.x, cc.y)
		if not _open_at(cc.x, cc.y):
			if ok:
				why = _what_blocks(cc.x, cc.y)
				build_why_cell = cc
			ok = false
		elif bga == 1 or bga == 3 or bga < 0:
			if ok:
				why = "furniture is already there (Shift + right-click takes a piece)" if bga == 1 else ("a tree is in the way" if bga == 3 else "too far away")
				build_why_cell = cc
			ok = false
			if bga == 3:
				tree = true
		if not wall and cc.y == bottom:
			feet += 1
			if _solid_at(cc.x, cc.y + 1):
				held += 1
	if not wall and held * 2 < feet:
		if ok:
			why = "it needs level floor under it"
		ok = false
	return {"ok": ok, "why": why, "pc": pc, "bottom": bottom, "tree": tree}

## Would a workshop of kind sk stand centred on column cx, on the floor under row cy?
## {ok, why, c0, bottom, pos}
func _station_fit(sk: String, cx: int, cy: int) -> Dictionary:
	var sw: int = int(Defs.STATIONS[sk]["w"])
	var sh: int = int(Defs.STATIONS[sk]["h"])
	var c0s := cx - sw / 2
	var ok := true
	var why := ""
	var sbot := _floor_span(c0s, sw, cy - sh / 2, 40)
	if sbot < 0:
		ok = false
		why = "no floor under it"
		sbot = cy + sh / 2
	if ok:
		for j in sh:
			for i in sw:
				var sc2 := Vector2i(c0s + i, sbot - sh + 1 + j)
				if not _open_at(sc2.x, sc2.y):
					if ok:
						why = _what_blocks(sc2.x, sc2.y)
					ok = false
					break
				# (furniture there would end up behind it, half hidden)
				if _bg_at(sc2.x, sc2.y) == 1:
					if ok:
						why = "furniture is in the way (Shift + right-click takes a piece)"
					ok = false
					break
			if not ok:
				break
	var stheld := 0
	for i2 in sw:
		if _solid_at(c0s + i2, sbot + 1):
			stheld += 1
	if stheld * 2 < sw:
		if ok:
			why = "it needs level ground under it"
		ok = false
	var spos := (Build.cell_pos(c0s, sbot) + Build.cell_pos(c0s + sw - 1, sbot - sh + 1)) * 0.5
	for ost in workshops.list:
		if ost.pos.distance_to(spos) < (sw + ost.w) * 0.5:
			if ok:
				why = "another workshop is there"
			ok = false
	return {"ok": ok, "why": why, "c0": c0s, "bottom": sbot, "pos": spos}

## Every tick in build mode: work out what would go where (the overlay draws it, green or red),
## and place it on a click (walls: while the button is held).
func _update_build(m: Mage) -> void:
	var piece := build_piece()
	build_prev = {}
	if piece.is_empty():
		return
	if Build.HULL_KINDS.has(String(piece["kind"])):
		# (the Ship tab builds the skiff's own hull: from aboard it)
		if m.input.cast and not _cabin_latch:
			_cabin_latch = true
			ui.toast("The Ship tab builds your skiff's hull: board it first (F), then build from inside", Color(1, 0.7, 0.5), 2.5)
		elif not m.input.cast:
			_cabin_latch = false
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
	if kind == "remove":
		_update_remove(m, piece)
		return
	if kind == "flatten":
		_update_flatten(m, piece)
		return
	build_drag = false
	if kind == "wall":
		build_prev = {"circle": [p, Build.WALL_R], "ok": not cost.is_empty(), "cells": []}
		if m.input.cast and not cost.is_empty() and has_mana(m, MANA_FLOOR, p, "build that"):
			var mt: int = piece["mat"]
			var budget := mini(m.inv[mt], 14)
			m.pending_place = budget
			m.pending_mat = mt
			brushes.append([p, Build.WALL_R, 10, mt, 0, budget, 0.0, m.slot])
			vfx.conjure(p, Defs.COLOR[mt])
		elif m.input.cast:
			_build_need(piece)
		build_click = false
		return
	var place := {}
	var kid := 0
	build_why = ""
	if kind == "prop" or kind == "carried":
		var dkey := "%s|%d" % [String(piece.get("prop", "")), build_seed]
		if kind == "prop" and dkey != _design_key:
			_design_key = dkey
			_design_val = Build.design(piece, build_seed)
		var d: Dictionary = _design_val if kind == "prop" else {"rows": piece["rows"], "wall": piece["wall"]}
		kid = Build.Props.kind_id(String(piece["prop"])) if kind == "prop" else int(piece["kid"])
		var rows: Array = d["rows"]
		var wall: bool = d.get("wall", false)
		# where you point, or (user, 22 Nov: indoors it kept saying there was no room) slid along the floor
		# to the nearest spot where it fits: a piece is centred on the cursor, so near a wall it ran into
		# the doorway
		var rest := _rested(cell)
		var fkey := "p|%s|%s|%d|%s|%d,%d" % [kind, dkey, int(piece.get("item", -1)), build_flip, cell.x, cell.y]
		var fit: Dictionary
		if not build_click and fkey == _fit_key and frame - _fit_frame < 12:
			fit = _fit_val
		else:
			fit = _prop_fit(rows, wall, cell.x, cell.y)
			if not fit["ok"] and (build_click or rest):
				var pw0: int = rows[0].length()
				for off in _slide_offsets(pw0 / 2 + 6):
					var f2 := _prop_fit(rows, wall, cell.x + off, cell.y, true)
					if f2["ok"]:
						fit = f2
						break
			_fit_key = fkey
			_fit_frame = frame
			_fit_val = fit
		ok = fit["ok"]
		build_why = fit["why"]
		tree_in_way = fit["tree"]
		for c in fit["pc"]:
			var ch: String = c[2]
			cells.append([Build.cell_pos(int(c[0]), int(c[1])), Color(1, 0.85, 0.3) if ch == "t" else Color.html(Build.Props.PALETTE[int(Build.Props.CHARS[ch])])])
		place = {"stamp": Build.prop_stamp(fit["pc"], kid)}
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
	elif kind == "stairs":
		# its foot where you point, on the highest ground under its first step; it climbs away from you
		# (T turns it), a post down to the floor every few columns
		var sdir := 1 if build_flip else -1
		var sbottom := _floor_span(cell.x if sdir > 0 else cell.x - Build.STAIR_STEP + 1, Build.STAIR_STEP, cell.y - 6, 40)
		if sbottom < 0:
			ok = false
			build_why = "no floor under its foot"
			sbottom = cell.y
		var sc := Build.stair_cells(cell.x, sbottom, build_rise, sdir)
		var post_to := {}
		var free_bg := {}
		var fcol := Color.hex((Defs.PAL[int(piece["mat"]) * 4] << 8) | 0xff)
		var bcol := Color.hex((Defs.PAL[int(piece["post"]) * 4] << 8) | 0xff).darkened(0.35)
		# the treads need open space; under them the flight merges into a hillside it meets (ground
		# there is left as it is), but never into anything built
		var kept := []
		for f in sc["front"]:
			var fc := Vector2i(int(f[0]), int(f[1]))
			if not _open_at(fc.x, fc.y):
				var ft := type_at(Build.cell_pos(fc.x, fc.y))
				if not f[2] and _solid_at(fc.x, fc.y) and ft != Defs.WOODDOOR and not _built_at(fc.x, fc.y):
					continue
				if ok:
					build_why = "cell %s: %s" % [str(fc), Defs.NAMES[ft]]
				ok = false
			kept.append(f)
			cells.append([Build.cell_pos(fc.x, fc.y), fcol])
		sc["front"] = kept
		var sheld := 0
		for q in Build.STAIR_STEP:
			if _solid_at(cell.x + sdir * q, sbottom + 1):
				sheld += 1
		if sheld * 2 < Build.STAIR_STEP:
			ok = false
			build_why = "its foot isn't on the ground"
		# (a post goes down to the floor; one that would cut through a tree means the tree is in the way:
		# left out, the flight there would have nothing to hold it and give way)
		for pp in sc["posts"]:
			var fr := _floor_below(int(pp[0]), int(pp[1]) + 1, 120)
			if fr >= 0:
				post_to[int(pp[0])] = fr
				for r in range(int(pp[1]), fr + 1):
					var pbg := _bg_at(int(pp[0]), r)
					if pbg == 0:
						free_bg[Vector2i(int(pp[0]), r)] = true
					elif pbg == 3:
						tree_in_way = true
						if ok:
							build_why = "a tree where a post goes"
						ok = false
		for rl in sc["rail"]:
			if _bg_at(int(rl[0]), int(rl[1])) == 0:
				free_bg[Vector2i(int(rl[0]), int(rl[1]))] = true
		var st2 := Build.stair_stamp(sc, post_to, free_bg, int(piece["mat"]), int(piece["post"]), int(piece["rail"]))
		var front_at := {}
		for f2 in sc["front"]:
			front_at[Vector2i(int(f2[0]), int(f2[1]))] = true
		for kb in free_bg:
			if not front_at.has(kb):
				cells.append([Build.cell_pos(kb.x, kb.y), bcol])
		piece["cost"] = Build.stair_cost(int(piece["mat"]), int(piece["post"]), int(st2["front"]), int(st2["back"]))
		cost = Build.payable(piece, m.inv)
		place = {"stamp": st2["stamp"]}
	elif kind == "station":
		# a workshop: an object standing on the ground where you point (most of its width on ground), or
		# slid along the floor to the nearest spot where it fits
		var sk: String = piece["station"]
		var rest2 := _rested(cell)
		var skey := "s|%s|%s|%d,%d" % [sk, build_flip, cell.x, cell.y]
		var sfit: Dictionary
		if not build_click and skey == _fit_key and frame - _fit_frame < 12:
			sfit = _fit_val
		else:
			sfit = _station_fit(sk, cell.x, cell.y)
			if not sfit["ok"] and (build_click or rest2):
				for off2 in _slide_offsets(int(Defs.STATIONS[sk]["w"]) / 2 + 8):
					var sf2 := _station_fit(sk, cell.x + off2, cell.y)
					if sf2["ok"]:
						sfit = sf2
						break
			_fit_key = skey
			_fit_frame = frame
			_fit_val = sfit
		ok = sfit["ok"]
		build_why = sfit["why"]
		var sw: int = int(Defs.STATIONS[sk]["w"])
		var sh: int = int(Defs.STATIONS[sk]["h"])
		var c0s: int = sfit["c0"]
		var sbot: int = sfit["bottom"]
		var simg: Image = WorkshopArt.frames(sk)["body"]
		for j in sh:
			for i in sw:
				var px := simg.get_pixel(sw - 1 - i if build_flip else i, j)
				if px.a > 0.5:
					cells.append([Build.cell_pos(c0s + i, sbot - sh + 1 + j), px])
		if int(m.items.get("st_" + sk, 0)) > 0:
			cost = {Defs.AIR: 0}              # (one you took up: set down again for free)
		place = {"station": sk, "pos": sfit["pos"]}
	elif kind == "torch":
		var tp := torch_plan(cell)
		ok = tp["ok"]
		build_why = tp["why"]
		for c in tp["cells"]:
			var ch2: String = c[2]
			cells.append([Build.cell_pos(int(c[0]), int(c[1])), Color(1, 0.75, 0.3) if ch2 == "t" else Color.html(Build.Props.PALETTE[int(Build.Props.CHARS[ch2])])])
		place = {"stamp": Build.prop_stamp(tp["cells"], 0), "torch": tp["flame"]}
	elif kind == "platform":
		for i in Build.PLATFORM_W:
			var cx := cell.x - Build.PLATFORM_W / 2 + i
			if not _open_at(cx, cell.y):
				ok = false
			cells.append([Build.cell_pos(cx, cell.y), Defs.COLOR[Defs.SCAFFOLD]])
		place = {"stamp": Build.platform_stamp(cell.x, cell.y)}
	if kind != "structure":
		build_prev = {"cells": cells, "ok": ok and not cost.is_empty()}
	if not place.is_empty() and frame % 10 == 0 or not build_prev.has("mana"):
		build_prev["mana"] = _place_mana_of(place) if not place.is_empty() else 0.0
	if not build_click:
		return
	build_click = false
	build_last = "%s: cost %s, fits %s" % [piece["name"], str(cost), ok]
	if cost.is_empty():
		_build_need(piece)
		return
	if not ok:
		if _build_warn_t <= frame:
			ui.toast("A tree is in the way: fell it first" if tree_in_way else (("Torch: " if kind == "torch" else "It doesn't fit: ") + (build_why if build_why != "" else "no room there")), Color(1, 0.6, 0.5), 1.4)
			_build_warn_t = frame + 40
		return
	if not pay_mana(m, _place_mana_of(place), p, "build that"):
		return
	for mt2 in cost:
		m.inv[int(mt2)] -= int(cost[mt2])
	if place.has("stamp"):
		stamps.append(place["stamp"])
		build_last_stamp = place["stamp"]
	if place.has("torch"):
		add_torch(place["torch"])
	if kind == "carried":
		m.furn.remove_at(int(piece["item"]))      # it's set down: no longer carried
	if place.has("station"):
		var nst = workshops.add(String(place["station"]), place["pos"])
		nst.facing = -1 if build_flip else 1
		var stk := "st_" + String(place["station"])
		if cost.has(Defs.AIR) and int(m.items.get(stk, 0)) > 0:
			m.items[stk] = int(m.items[stk]) - 1
			if int(m.items[stk]) <= 0:
				m.items.erase(stk)
		audio.play("place", nst.pos, 0.7)
		# (sparks fly from its fire: say so if it's set down beside something that burns)
		if float(Defs.STATIONS[nst.kind]["spark"]) > 0.0:
			var bt: int = workshops.burnable_near(nst)
			if bt > 0:
				ui.toast("Careful: the %s's sparks can catch the %s beside it" % [String(Defs.STATIONS[nst.kind]["name"]).to_lower(), Defs.NAMES[bt].to_lower()], Color(1, 0.65, 0.4), 4.0)
		if not m.items.has("tip_station"):
			m.items["tip_station"] = true
			ui.toast("%s set down: press F beside it to load it and light its fire" % Defs.STATIONS[place["station"]]["name"], Color(1, 0.85, 0.5), 4.0)
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
	_fit_key = ""                 # (something's there now: work the fit out afresh)
	audio.play("place", p, 0.9)
	var psize := 8.0
	if place.has("stamp"):
		psize = float(maxi(int(place["stamp"]["w"]), int(place["stamp"]["h"])))
	elif place.has("structure"):
		psize = 40.0
	elif place.has("door"):
		psize = 30.0
	vfx.place_flash(p, psize)

## what putting a piece up costs in mana: its cells (a stamp's written cells, a door's doorway, a
## structure's blueprint), a torch or a workshop as one
func _place_mana_of(place: Dictionary) -> float:
	if place.has("torch"):
		return TORCH_MANA * gear("mana_cost", player)
	if place.has("station"):
		return STATION_MANA * gear("mana_cost", player)
	var n := 0
	if place.has("stamp"):
		for v in place["stamp"]["data"]:
			if (int(v) & 0xffff) != 0xffff:
				n += 1
	if place.has("door"):
		n += Build.DOOR_W * Build.DOOR_H
	if place.has("structure"):
		for v2 in place["structure"]["bp"].c:
			if (int(v2) & 0xffff) != 0xffff:
				n += 1
	return maxf(1.0, place_mana(n))

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
	var mn := place_mana(need)
	build_prev["text"] = String(build_prev["text"]) + "  ·  %d mana" % int(ceil(mn))
	if build_drag and not m.input.cast:
		build_drag = false
		if ok and not pay_mana(m, mn, m.pos + d, "lay that"):
			return
		if ok:
			stamps.append(Build.shape_stamp(good, mt, back))
			vfx.shape_burst(good, true)
			build_last_stamp = stamps[stamps.size() - 1]
			m.inv[mt] -= need
			build_last = "%s: %d cells" % [piece["name"], need]
			audio.play("place", m.pos + d, 0.6)
		elif need > m.inv[mt]:
			ui.toast("%s needs %d %s (you have %d)" % [piece["name"], need, Defs.NAMES[mt], m.inv[mt]], Color(1, 0.7, 0.5), 2.0)
		elif need == 0 and not too_big:
			ui.toast("No room there", Color(1, 0.6, 0.5), 1.2)
		build_last = build_last if ok else "%s: not laid (%s)" % [piece["name"], what]

# ------------------------------------------------------- taking away, precisely --
## (user, 22 Nov: "a precise way to be able to remove materials, flatten the ground, remove background
## decorations without remove the entire background"; physics applies: what's taken away wakes what's
## round it, as digging does, so a building held only by what you took comes down)

## the material a removed cell gives (as the dig's collectAs), or -1 if it gives nothing
static func _collect_as(t: int) -> int:
	if t == Defs.TIMBER or t == Defs.ROOT:
		return Defs.WOOD
	if t == Defs.LITTER:
		return Defs.LEAF
	if t == Defs.OPENCHEST or t == Defs.DECOR or t == Defs.WOODDOOR:
		return Defs.PLANK
	if t == Defs.TORCH:
		return -1
	return t if Defs.COLLECT[t] == 1 else -1

## the cells of `cells` ([Vector2i], columns near you) as a block: [c0 (the short way round), r0, w, h, rel]
static func _cells_box(cells: Array) -> Array:
	var n0: int = Defs.NS
	var base: int = cells[0].x
	var rel := []
	var c0 := 1 << 30
	var c1 := -(1 << 30)
	var r0 := 1 << 30
	var r1 := -(1 << 30)
	for c in cells:
		var rc := Vector2i(base + posmod(c.x - base + n0 / 2, n0) - n0 / 2, c.y)
		rel.append(rc)
		c0 = mini(c0, rc.x)
		c1 = maxi(c1, rc.x)
		r0 = mini(r0, rc.y)
		r1 = maxi(r1, rc.y)
	return [c0, r0, c1 - c0 + 1, r1 - r0 + 1, rel]

## does this cell look like it has something of `layer` to take (from the collision grid: exact for
## blocks and furniture; a back wall the planet made itself, a cave's, doesn't show there)
func _removable_guess(c: Vector2i, layer: String) -> bool:
	var t := type_at(Build.cell_pos(c.x, c.y))
	var kd: int = Defs.KIND[t]
	var front := t != Defs.TREASURE and t != Defs.WOODDOOR and (kd == Defs.K_SOLID or kd == Defs.K_POWDER or kd == Defs.K_LIQUID)
	var bga := _bg_at(c.x, c.y)
	match layer:
		"front":
			return front
		"furn":
			return bga == 1
		"back":
			return bga == 2 or bga == 3
	return front or bga > 0

## Remove tab: press, drag and let go as with blocks (a click with no drag takes a square as thick as
## [ ] sets: one cell at 1); only the chosen layer is taken
func _update_remove(m: Mage, piece: Dictionary) -> void:
	var layer: String = piece["layer"]
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
	var prev := []
	var n := 0
	var est := 0.0
	if not too_big:
		for c in cells:
			if _removable_guess(c, layer):
				n += 1
				var gt := type_at(Build.cell_pos(c.x, c.y))
				est += dig_mana(gt) if (layer == "front" or layer == "all") and gt != 0 else DIG_MANA * 1.5
				prev.append([Build.cell_pos(c.x, c.y), Color(1.0, 0.3, 0.25)])
			else:
				prev.append([Build.cell_pos(c.x, c.y), Color(0.75, 0.75, 0.8, 0.5)])
	build_prev = {"cells": prev, "ok": not too_big}
	build_prev["text"] = ("Too big to take in one go (at most %d cells)" % Build.SHAPE_MAX_CELLS) if too_big else \
		("%s %s: %d cells%s  ·  about %d mana" % [Build.SHAPES[shape], piece["name"], n, " or so" if layer == "back" or layer == "all" else "", int(ceil(est))])
	if build_drag and not m.input.cast:
		build_drag = false
		if too_big:
			return
		var r := remove_cells(m, cells, layer)
		var got: int = r["n"]
		if got > 0:
			audio.play("dig", m.pos + d, 0.6)
			build_last = "%s: %d cells" % [piece["name"], got]
		elif not r.has("mana"):
			ui.toast("Nothing there to take" if not r["hard"] else "Too hard for your staff", Color(1, 0.7, 0.5), 1.2)

## Takes away `layer` ("front" blocks, "back" walls and plants, "furn" furniture and torches, "all") from
## these cells: reads them (exactly), stamps them out, puts what they give into the satchel and wakes
## what's round them. Returns {n: cells taken, hard: something was too hard for the staff}.
func remove_cells(m: Mage, cells: Array, layer: String) -> Dictionary:
	var box := _cells_box(cells)
	var c0: int = box[0]
	var r0: int = box[1]
	var w: int = box[2]
	var h: int = box[3]
	var rr: Dictionary = gpu.read_rect(posmod(c0, Defs.NS), r0, w, h)
	var fgs: PackedInt32Array = rr["fg"]
	var bgs: PackedInt32Array = rr["bg"]
	var data := PackedInt32Array()
	data.resize(w * h)
	data.fill(0xffff)
	var got := {}
	var flames := 0
	var n := 0
	var hard := false
	var taken := []
	var mana := 0.0
	for rc: Vector2i in box[4]:
		var k := (rc.y - r0) * w + (rc.x - c0)
		var t: int = fgs[k] & 255
		var b: int = bgs[k]
		var bm: int = b & 255
		var v := 0xffff
		var kd: int = Defs.KIND[t]
		if (layer == "front" or layer == "all") and t != 0 and t != Defs.TREASURE and t != Defs.WOODDOOR \
				and (kd == Defs.K_SOLID or kd == Defs.K_POWDER or kd == Defs.K_LIQUID):
			if Defs.HARD[t] <= m.tier:
				v = (v & ~0xff)
				mana += dig_mana(t)
				var gm := _collect_as(t)
				if gm > 0:
					got[gm] = int(got.get(gm, 0)) + 1
			else:
				hard = true
		if bm != 0 and bm != Defs.TREASURE and bm != Defs.OPENCHEST:
			var furn := bm == Defs.DECOR or bm == Defs.TORCH
			var take_bg := (layer == "furn" and furn) or (layer == "back" and not furn) or layer == "all"
			if take_bg and Defs.HARD[bm] > m.tier and not furn:
				hard = true
				take_bg = false
			if take_bg:
				var nb := 0
				if layer == "furn" and bm == Defs.DECOR:
					# the wall it stood in front of comes back (furniture remembers it)
					var bmk: int = Defs.BEHIND[((b >> 22) & 3) | (((b >> 28) & 7) << 2)]
					if bmk != 0:
						nb = (bmk << 8) | 0x40000 | (0x20000 if (b & 0x8000) != 0 else 0)
				v = (v & 0xff) | nb
				mana += dig_mana(bm)
				if bm == Defs.TORCH:
					flames += 1
				else:
					var gb := _collect_as(bm)
					if gb > 0:
						got[gb] = int(got.get(gb, 0)) + 1
		if v != 0xffff:
			data[k] = v
			n += 1
			taken.append(rc)
	if n == 0:
		return {"n": 0, "hard": hard}
	var at0: Vector2i = taken[taken.size() / 2]
	if not pay_mana(m, mana, Build.cell_pos(at0.x, at0.y), "take that away"):
		return {"n": 0, "hard": hard, "mana": true}
	stamps.append({"x0": posmod(c0, Defs.NS), "y0": r0, "w": w, "h": h, "data": data})
	vfx.shape_burst(taken, false)
	for gm2 in got:
		m.inv[int(gm2)] += int(got[gm2])
	if flames > 0:
		m.inv[Defs.TORCH] += maxi(1, int(round(flames / 5.0)))     # (a torch's flame is five cells)
	_wake_round(m, taken)
	var mid: Vector2 = Build.cell_pos(taken[taken.size() / 2].x, taken[taken.size() / 2].y)
	for q in mini(10, n):
		var tc: Vector2i = taken[randi() % taken.size()]
		_particle(Build.cell_pos(tc.x, tc.y), Vector2(randf() - 0.5, randf() - 0.8) * 0.5, 14 + randi() % 10, Color(0.9, 0.8, 0.6), false, 0.03)
	if m.local and not got.is_empty():
		var parts := []
		for gm3 in got:
			parts.append("%d %s" % [int(got[gm3]), Defs.NAMES[int(gm3)]])
		ui.toast("+ " + ", ".join(parts.slice(0, 3)), Color(0.95, 0.85, 0.55), 1.4)
	audio.play("dig", mid, 0.4)
	return {"n": n, "hard": hard}

## physics applies: what was round the taken cells is woken (brush mode 11, as digging wakes the
## ground and buildings round a hole), so whatever held on only by them comes down
func _wake_round(m: Mage, taken: Array) -> void:
	if taken.is_empty():
		return
	var step := maxi(1, taken.size() / 10)
	var k := 0
	while k < taken.size():
		var tc: Vector2i = taken[k]
		brushes.append([Build.cell_pos(tc.x, tc.y), 3.0, 11, 0, m.tier, 0, 0, m.slot])
		k += step

## Flatten: press where the ground should be (that row is its new top), drag along, let go. Over the
## line everything solid is cut away (up to FLAT_CUT rows), under it dips are filled from the satchel
## (down to ground at most FLAT_FILL rows below). Returns the plan {cut: [cells], fill: [cells, deepest
## first]} for the columns from a to b.
func flatten_plan(a: Vector2i, b: Vector2i) -> Dictionary:
	var n0: int = Defs.NS
	var dx := posmod(b.x - a.x + n0 / 2, n0) - n0 / 2
	dx = clampi(dx, -Build.FLAT_W, Build.FLAT_W)
	var level := a.y
	var cut := []
	var fill := []
	for q in absi(dx) + 1:
		var col := posmod(a.x + signi(dx) * q, n0)
		for j in range(level - Build.FLAT_CUT, level):
			var t := type_at(Build.cell_pos(col, j))
			var kd: int = Defs.KIND[t]
			if (kd == Defs.K_SOLID or kd == Defs.K_POWDER) and t != Defs.TREASURE and t != Defs.WOODDOOR:
				cut.append(Vector2i(col, j))
		var ground := -1
		for j2 in range(level, level + Build.FLAT_FILL + 1):
			if _solid_at(col, j2):
				ground = j2
				break
		if ground > level:
			for j3 in range(ground - 1, level - 1, -1):
				fill.append(Vector2i(col, j3))
	fill.sort_custom(func(p1, p2): return p1.y > p2.y)
	return {"cut": cut, "fill": fill, "level": level}

func _update_flatten(m: Mage, piece: Dictionary) -> void:
	var mt: int = piece["mat"]
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
	var key := "%s|%s|%d" % [str(from), str(cell), frame / 10]
	if key != _flat_key:
		_flat_key = key
		_flat_plan = flatten_plan(from, Vector2i(cell.x, from.y))
	var cut: Array = _flat_plan["cut"]
	var fill: Array = _flat_plan["fill"]
	var prev := []
	var fcol := Color.hex((Defs.PAL[mt * 4] << 8) | 0xff)
	for c in cut:
		prev.append([Build.cell_pos(c.x, c.y), Color(1.0, 0.3, 0.25)])
	for c2 in fill:
		prev.append([Build.cell_pos(c2.x, c2.y), fcol])
	# the line itself
	var dx := posmod(cell.x - from.x + Defs.NS / 2, Defs.NS) - Defs.NS / 2
	for q in absi(clampi(dx, -Build.FLAT_W, Build.FLAT_W)) + 1:
		prev.append([Build.cell_pos(from.x + signi(dx) * q, from.y - 1), Color(1.0, 0.95, 0.6)])
	build_prev = {"cells": prev, "ok": true}
	var have: int = m.inv[mt]
	var fest := place_mana(mini(fill.size(), have))
	for c3 in cut:
		fest += dig_mana(type_at(Build.cell_pos(c3.x, c3.y)))
	build_prev["text"] = "Flatten: cut %d, fill %d %s%s  ·  about %d mana" % [cut.size(), fill.size(), Defs.NAMES[mt],
		(" (you have %d: the deepest dips first)" % have) if fill.size() > have else "", int(ceil(fest))]
	if build_drag and not m.input.cast:
		build_drag = false
		var r := flatten_apply(m, _flat_plan, mt)
		_flat_key = ""
		if r.has("mana"):
			return
		if r["cut"] + r["fill"] == 0:
			ui.toast("Already level there" if not r["hard"] else "Too hard for your staff", Color(1, 0.7, 0.5), 1.2)
		else:
			build_last = "Flatten: cut %d, filled %d" % [r["cut"], r["fill"]]
			audio.play("dig", m.pos + d, 0.6)

## carries out a flatten plan: the cut cells read back exactly (what's too hard stays), the dips filled
## with `mt` as far as the satchel goes, deepest first; returns {cut, fill, hard}
func flatten_apply(m: Mage, plan: Dictionary, mt: int) -> Dictionary:
	var cut: Array = plan["cut"]
	var fill: Array = plan["fill"]
	var all := cut + fill
	if all.is_empty():
		return {"cut": 0, "fill": 0, "hard": false}
	var box := _cells_box(all)
	var c0: int = box[0]
	var r0: int = box[1]
	var w: int = box[2]
	var h: int = box[3]
	var rel: Array = box[4]
	var rr: Dictionary = gpu.read_rect(posmod(c0, Defs.NS), r0, w, h)
	var fgs: PackedInt32Array = rr["fg"]
	var data := PackedInt32Array()
	data.resize(w * h)
	data.fill(0xffff)
	var got := {}
	var n_cut := 0
	var hard := false
	var taken := []
	for q in cut.size():
		var rc: Vector2i = rel[q]
		var k := (rc.y - r0) * w + (rc.x - c0)
		var t: int = fgs[k] & 255
		var kd: int = Defs.KIND[t]
		if t == 0 or t == Defs.TREASURE or t == Defs.WOODDOOR or not (kd == Defs.K_SOLID or kd == Defs.K_POWDER):
			continue
		if Defs.HARD[t] > m.tier:
			hard = true
			continue
		data[k] = 0xff00
		n_cut += 1
		taken.append(rc)
		var gm := _collect_as(t)
		if gm > 0:
			got[gm] = int(got.get(gm, 0)) + 1
	for gm2 in got:
		m.inv[int(gm2)] += int(got[gm2])
	var n_fill := 0
	for q2 in fill.size():
		if m.inv[mt] <= 0:
			break
		var rc2: Vector2i = rel[cut.size() + q2]
		var k2 := (rc2.y - r0) * w + (rc2.x - c0)
		var t2: int = fgs[k2] & 255
		var kd2: int = Defs.KIND[t2]
		if not (kd2 == Defs.K_EMPTY or kd2 == Defs.K_GAS or kd2 == Defs.K_LIQUID or t2 == Defs.SNOW or t2 == Defs.ASH):
			continue
		if _body_in(Build.cell_pos(rc2.x, rc2.y)):
			continue
		data[k2] = 0xff00 | mt
		m.inv[mt] -= 1
		n_fill += 1
	if n_cut + n_fill > 0:
		var cost := place_mana(n_fill)
		for tk in taken:
			cost += dig_mana(fgs[(tk.y - r0) * w + (tk.x - c0)] & 255)
		var at1: Vector2i = taken[0] if not taken.is_empty() else rel[cut.size()]
		if not pay_mana(m, cost, Build.cell_pos(at1.x, at1.y), "flatten that"):
			# (nothing happens: the satchel gets back what it gave, and what was cut isn't taken)
			for gm3 in got:
				m.inv[int(gm3)] -= int(got[gm3])
			m.inv[mt] += n_fill
			return {"cut": 0, "fill": 0, "hard": hard, "mana": true}
		stamps.append({"x0": posmod(c0, Defs.NS), "y0": r0, "w": w, "h": h, "data": data})
		_wake_round(m, taken)
		vfx.shape_burst(taken, false)
		var filled := []
		for q3 in fill.size():
			var rc3: Vector2i = rel[cut.size() + q3]
			if data[(rc3.y - r0) * w + (rc3.x - c0)] != 0xffff:
				filled.append(rc3)
		vfx.shape_burst(filled, true)
	return {"cut": n_cut, "fill": n_fill, "hard": hard}

# ------------------------------------------------------------------ torches --
## A torch is one piece (user, 22 Nov: placing torches laid a whole brush of them): pointed at with a
## floor close under it (and no built back wall there), a standing torch on that floor; otherwise a sconce
## on the wall where you point.
## Its flame is real torch cells (it burns, it's dug and fallen with what holds it); its light is a
## point light TORCH_R across (`_torch_lights`), remembered in planet_state["torches"].
## Returns {ok, why, cells (prop cells), flame (world point)}.
func torch_plan(cell: Vector2i) -> Dictionary:
	var rows: Array = Build.SCONCE
	var bottom := cell.y + 3
	# (pointed at a built back wall it hangs there; otherwise near a floor it stands on it)
	var fl := -1 if _bg_at(cell.x, cell.y) == 2 else _floor_below(cell.x, cell.y, Build.STANDING.size())
	if fl >= 0:
		rows = Build.STANDING
		bottom = fl
	var pc := Build.prop_cells(rows, cell.x, bottom, false)
	var ok := true
	var why := ""
	var held := rows == Build.STANDING
	var cp := Build.cell_pos(cell.x, cell.y)
	var under: bool = cp.length() < gpu.surf_at(atan2(cp.y, cp.x)).x - 6.0     # (a cave: its wall is behind)
	for c in pc:
		var cc := Vector2i(int(c[0]), int(c[1]))
		var bga := _bg_at(cc.x, cc.y)
		if not _open_at(cc.x, cc.y) or bga == 1 or bga == 3 or bga < 0:
			ok = false
			why = "no room for it there"
		if bga == 2:
			held = true
		for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
			if _solid_at(cc.x + o.x, cc.y + o.y):
				held = true
	if not held and not under:
		if ok:
			why = "nothing to hang it on: point at a wall, or near a floor"
		ok = false
	var top := bottom - rows.size() + 1
	return {"ok": ok, "why": why, "cells": pc, "flame": Build.cell_pos(cell.x, top + Build.TORCH_FLAME), "standing": rows == Build.STANDING}

## puts a torch down where `p` is (Conjure with torches chosen, or build mode); true if it went down
func place_torch(m: Mage, p: Vector2) -> bool:
	if m.inv[Defs.TORCH] <= 0:
		return false
	var tp := torch_plan(Build.cell_of(p))
	if not tp["ok"]:
		if m.local and _build_warn_t <= frame:
			ui.toast("Torch: " + String(tp["why"]), Color(1, 0.7, 0.5), 1.4)
			_build_warn_t = frame + 40
		return false
	if not pay_mana(m, TORCH_MANA * gear("mana_cost", m), p, "light a torch"):
		return false
	stamps.append(Build.prop_stamp(tp["cells"], 0))
	m.inv[Defs.TORCH] -= 1
	add_torch(tp["flame"])
	vfx.place_flash(tp["flame"], 8.0)
	audio.play("place", p, 0.6, 1.2)
	return true

func add_torch(flame: Vector2) -> void:
	var tl: Array = planet_state.get("torches", [])
	tl.append([flame.x, flame.y, frame])
	planet_state["torches"] = tl

## every so often: a torch whose flame is gone (burnt, dug, taken up, fallen) is forgotten
func _check_torches() -> void:
	var tl: Array = planet_state.get("torches", [])
	if tl.is_empty():
		return
	for k in range(tl.size() - 1, -1, -1):
		var t: Array = tl[k]
		if frame - int(t[2]) < 45 and frame >= int(t[2]):
			continue                              # (its cells go in at the next GPU frame)
		var fp := Vector2(float(t[0]), float(t[1]))
		if fp.distance_to(player.pos) > 220.0:
			continue
		var bga := _bg_at(Build.cell_of(fp).x, Build.cell_of(fp).y)
		if bga == 0 or bga == 2:
			tl.remove_at(k)

## the torches near the view as point lights, nearest first, into whatever of the 32 is left
func _torch_lights() -> void:
	var tl: Array = planet_state.get("torches", [])
	if tl.is_empty() or space.active:
		return
	var room := 32 - lights.size()
	if room <= 0:
		return
	var reach := float(VW + VH) * 0.5 * maxf(zoom, 0.01) + Build.TORCH_R
	var near := []
	for k in tl.size():
		var t: Array = tl[k]
		var fp := Vector2(float(t[0]), float(t[1]))
		var dd := fp.distance_to(cam_c)
		if dd < reach:
			near.append([dd, fp, k])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for q in mini(room, near.size()):
		var fp2: Vector2 = near[q][1]
		var ph := float(near[q][2]) * 1.7
		var fl := 0.93 + 0.04 * sin(time * 0.31 + ph) + 0.03 * sin(time * 0.77 + ph * 2.3)
		lights.append([fp2, Build.TORCH_R * fl, Color(1.8, 1.2, 0.58) * fl])

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
		if anvil_near():
			ui.toast("An anvil is at hand: ore gear forged here comes out masterwork", Color(1, 0.9, 0.55), 3.0)
	elif state == "forge":
		state = "play"
		ui.hide_forge()

# ==================================================================== map ===
## The map (M) is a menu of its own: the game waits while it's open (the play camera never zooms
## out). "planet": the GPU draws the planet zoomed out, turned to `map_ang` (A/D or a drag turn it;
## W/S or the wheel zoom, the last level fits the whole planet); map_view.gd draws the markers.
## "space" (Tab): the galaxy chart (map_view.gd). Out in space it opens on that.
var map_tab := "planet"
var map_zoom_i := 1
var map_ang := 0.0
var _map_back := {}
var _map_drag := false
var _map_moved := 0.0          # (how far the mouse went while held: a click sets a waypoint, a drag pans)

func map_zooms() -> Array:
	# (the last fits the whole planet with its orbit band, whatever its size)
	return [4.0, 10.0, 2.0 * (Defs.R_SPACE + 30.0) / float(mini(VW, VH))]

func open_map() -> void:
	if state != "play" or travelling or player == null:
		return
	state = "map"
	_map_back = {"cam": cam_c, "zoom": zoom, "view": view_rect.visible}
	map_ang = atan2(player.pos.y, player.pos.x)
	map_tab = "space" if space.active and not space.live else "planet"
	map_view.centre_on_you()
	_map_drag = false
	_map_moved = 0.0
	space.visible = false                    # (out there: the map is drawn on its own)
	overlay.queue_redraw()
	ui.show_map(self)
	_map_camera()

func close_map() -> void:
	if state != "map":
		return
	state = "play"
	zoom = float(_map_back.get("zoom", 1.0))
	cam_c = _map_back.get("cam", cam_c)
	view_c = Vector2.ZERO
	view_rect.visible = bool(_map_back.get("view", true))
	# (the picture still to come was drawn for the map: hidden until one from the play camera)
	view_mat.set_shader_parameter("alpha", 0.0)
	_map_shown = 2
	space.visible = space.active
	ui.hide_map()
	map_view.queue_redraw()
	overlay.queue_redraw()

var _map_shown := 0

func _map_camera() -> void:
	var zs: Array = map_zooms()
	map_zoom_i = clampi(map_zoom_i, 0, zs.size() - 1)
	zoom = float(zs[map_zoom_i])
	var up := Vector2(cos(map_ang), sin(map_ang))
	var r: float = clampf(player.pos.length(), Defs.R_IN + 20.0, Defs.R_TOP)
	if map_zoom_i == zs.size() - 1:
		cam_c = up                               # (the whole planet: its middle, turned to map_ang)
	elif zoom >= 8.0:
		cam_c = up * maxf(Defs.R_IN + 20.0, r * 0.55)
	else:
		cam_c = up * r * 0.85
	view_rect.visible = map_tab == "planet"

func _map_tick(_delta: float) -> void:
	if map_tab == "space":
		# the galaxy chart: WASD or the arrows pan
		var pv := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			pv.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			pv.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			pv.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			pv.y += 1.0
		if pv != Vector2.ZERO:
			map_view.pan(pv * 6.0)
		return
	var turn := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn -= 1.0
	if turn != 0.0:
		map_ang += turn * 4.0 * zoom / maxf(player.pos.length(), 200.0)
	_map_camera()

func _map_key(k: int) -> void:
	if k == KEY_M or k == KEY_ESCAPE:
		close_map()
	elif k == KEY_TAB:
		map_tab = "space" if map_tab == "planet" else "planet"
		if map_tab == "space":
			map_view.centre_on_you()
		_map_camera()
		ui.show_map(self)
	elif map_tab == "space":
		if k == KEY_EQUAL or k == KEY_KP_ADD:
			map_view.zoom_by(1.0 / 1.6)
		elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
			map_view.zoom_by(1.6)
		elif k == KEY_H:
			map_view.centre_on_you()
		elif k == KEY_BACKSPACE or k == KEY_DELETE:
			space.waypoint = null
	elif k == KEY_W or k == KEY_UP or k == KEY_EQUAL or k == KEY_KP_ADD:
		map_zoom_i -= 1
		_map_camera()
	elif k == KEY_S or k == KEY_DOWN or k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		map_zoom_i += 1
		_map_camera()

func _map_mouse(ev: InputEvent) -> void:
	if map_tab == "space":
		_space_chart_mouse(ev)
		return
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_LEFT:
			_map_drag = ev.pressed
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			map_zoom_i -= 1
			_map_camera()
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			map_zoom_i += 1
			_map_camera()
	elif ev is InputEventMouseMotion and _map_drag and map_tab == "planet":
		# (the planet follows the mouse: dragging right turns it so what was on the left comes over)
		map_ang += ev.relative.x / float(scale_px) * zoom / maxf(player.pos.length(), 200.0)
		_map_camera()

## the galaxy chart: the wheel zooms about the cursor, a drag pans, a click marks a waypoint (it shows
## out in space), a right click clears it
func _space_chart_mouse(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mp: Vector2 = ev.position / float(scale_px)
		if ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_map_drag = true
				_map_moved = 0.0
			else:
				if _map_drag and _map_moved < 3.0:
					space.waypoint = map_view.to_galaxy(mp)
					audio.play("ui_click", null, 0.5)
				_map_drag = false
		elif ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			space.waypoint = null
		elif ev.pressed and (ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			# (about the cursor: what's under it stays under it)
			var before: PackedFloat64Array = map_view.to_galaxy(mp)
			map_view.zoom_by(1.0 / 1.25 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1.25)
			var after: PackedFloat64Array = map_view.to_galaxy(mp)
			map_view.gc[0] += before[0] - after[0]
			map_view.gc[1] += before[1] - after[1]
	elif ev is InputEventMouseMotion and _map_drag:
		var rel: Vector2 = ev.relative / float(scale_px)
		_map_moved += rel.length()
		if _map_moved >= 3.0:
			map_view.pan(-rel)

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
	var pl: Dictionary = Defs.make_planet_for(int(d.get("world_seed", 0)), int(d.get("planet", 0)))
	var saved := float(d.get("saved", FileAccess.get_modified_time(path)))
	return {"planet": pl.get("name", "?"), "seed": int(d.get("world_seed", 0)), "tier": int(d.get("tier", 1)), "spells": (d.get("known", []) as Array).size(),
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
	if state == "shop":
		towns.close_shop()
	if state == "station":
		workshops.close()
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

## The Esc menu (settings) is open over play: the world waits (user, 23 Nov: "escape menu doesnt pause")
func menu_paused() -> bool:
	return (state == "play" or state == "dead") and ui != null and ui.settings_panel != null \
		and ui.settings_panel.visible

func start_game(use_save: bool) -> void:
	state = "loading"
	ui.show_loading("Forging a round planet…")
	await get_tree().process_frame
	await get_tree().process_frame
	space.reset_for_load()                 # (nothing of space kept from the game before: user, 23 Nov)
	var s = _load_save() if use_save else null
	if s != null:
		_apply_save(s)
	else:
		_delete_worlds()
		# a new journey: a system of planets of its own (the test mode keeps the classic one)
		Defs.world_seed = test_seed if testing else 1 + randi() % 0xFFFFFE
		space.load_state({})
		player.inv.fill(0)
		# (a modest start: a little Wisp Mote, no Spark Bolt and no levitation until they're forged)
		known = ["mote", "conjure"]
		tier = 1
		dig_r = 7.5
		max_hp = 100
		max_mana = 100
		mana_regen = 0.22
		heat_ward = false
		items = {"potion": 2}       # two draughts to start with; health doesn't come back by itself
		learned = {}
		if testing:
			known = ["mote", "spark", "conjure"]
			items["levitate"] = true  # (the checks fly and cast sparks as they always have)
			learn_all()
		player.furn = []
		played = 0.0
	_enter_planet(int(s["planet"]) if s != null else 0)
	ui.hide_loading()
	ui.show_hud()
	state = "play"
	if s == null:
		ui.toast("Right-click to excavate. Left-click casts your selected spell.", Color.WHITE, 7.0)
		ui.toast("Press C to open the Wisp Forge. Press M for the map.", Color(1, 0.82, 0.23), 9.0)
	save_game()

func _enter_planet(index: int) -> void:
	_make_world(index, false)
	_respawn()
	_gt("respawn")
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
	_gt("liquids round you")
	if not _loaded:
		save_world(false)
	_gt("save")
	if testing:
		print("[gen] %s: steps (ms) %s; planning %s; settling: %d windows, recording %d ms, GPU %d ms" % [planet["name"], gen_times, builds.plan_times, gpu.settle_wins, gpu.settle_ms.x, gpu.settle_ms.y])
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
## how long each step of making a planet took (ms; the test mode prints it)
var gen_times := {}
var _gt0 := 0

func _gt(nm: String) -> void:
	var now := Time.get_ticks_usec()
	gen_times[nm] = int(gen_times.get(nm, 0)) + (now - _gt0) / 1000
	_gt0 = now

func _make_world(index: int, arriving: bool) -> void:
	var tree := get_tree()
	_aq_wait = 300                 # (Auto quality lets the new planet's first frames settle)
	_aq_t = 0.0
	_aq_n = 0
	for nv in navs:
		nv.clear()
	gen_times.clear()
	_gt0 = Time.get_ticks_usec()
	planet = Defs.make_planet(index)
	clim = Defs.climate(planet)
	_refresh_recipes()
	end_sky_event()
	sky_fx.clear()
	if towns != null:
		towns.clear()
	if vfx != null:
		vfx.clear()
	if weather != null:
		weather.clear()
	wind = 0.0
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
	_gt("geometry and shaders")
	gpu.fresh = false
	travel_progress = 0.2
	if arriving:
		await saves_done()          # (the planet you left may still be being written)
		_phase_go()
	gpu.build_surface(planet)
	_gt("surface")
	# spawn in the middle of the first friendly biome
	var bl: Array = planet["biomes"]
	var sb := 0
	for i in bl.size():
		if int(Defs.BIOMES[bl[i]]["flags"]) & 8:
			sb = i
			break
	spawn_angle = Defs.biome_mid(planet, sb)
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
	_gt("load")
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
		_gt("plan buildings")
		# (and every blueprint finished at once, one per core)
		var gid: int = builds.finish_start()
		if gid >= 0:
			_phase("finish blueprints")
			while not WorkerThreadPool.is_group_task_completed(gid):
				await tree.process_frame
				_phase_go()
			WorkerThreadPool.wait_for_group_task_completion(gid)
		builds.finish_collect()
		_gt("finish blueprints")
	else:
		builds.plan(planet, gpu.surface, spawn_angle, boss_a, not loaded)
		_gt("plan buildings")
		builds.finish_all()
		_gt("finish blueprints")
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
		_gt("generate cells")
		gpu.stamp(builds.structs, int(planet["seed"]))
		gpu.flush()
		_gt("stamp")
		# every plant's support settled, and pieces of overlapping crowns given to the tree they lean on
		var kw: Array = gpu.knit_windows()
		if arriving:
			var kp := 0
			while kp < gpu.KNIT_PASSES:
				gpu.knit_plants(kw, 10, kp)
				kp += 10
				_phase("knit plants")
				await tree.process_frame
				_phase_go()
		else:
			gpu.knit_plants(kw, gpu.KNIT_PASSES)
		_gt("knit plants")
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
			_gt("settle")
			if testing:
				print("[gen] cells and stamping %d ms, settling %d ms (%d areas)" % [(tg1 - tg0) / 1000, (Time.get_ticks_usec() - tg1) / 1000, builds.settle.size()])
		print("[Wisp Forge] %s: %d structures" % [planet["name"], builds.structs.size()])
		builds.structs.clear()
	_make_chests(loaded)
	workshops.load_from(planet_state)
	_make_doors(loaded)
	_gt("chests and doors")
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
	eco_carcasses.clear()
	_guards_alive.clear()
	projs.clear()
	parts.clear()
	var bd := Vector2(cos(boss_a), sin(boss_a))
	if not planet_state.get("boss_dead", false):
		spawn_enemy("golem", bd * (boss_info.y - boss_info.w + float(Defs.ENEMY["golem"]["h"]) * 0.5 + 2.0))
	_spawn_guardians()
	_gt("foes")
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
	skiff.power = 1.5 if items.has("engine") else 1.0              # (the Star-Iron Engine)
	skiff.fly(want, pl != null or crew_on_deck(), g, false, (Skiff.CRUISE_HIGH if high else Skiff.CRUISE) * skiff.power, 0.999 if high else 0.97)
	skiff.advance(_skiff_solid if in_grid(skiff.pos, 40.0) else Callable())
	if skiff.bump > CRASH_PLANET:
		space.skiff_crash(skiff)
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
	if skiff.pos.length() < Defs.R_TOP and skiff.vel.length() > Skiff.CRUISE * skiff.power + 1.0 and skiff.vel.dot(up) < 0.0:
		var lead: Vector2 = skiff.pos + skiff.vel.normalized() * 14.0
		for k in 2:
			_particle(lead + Vector2(randf() - 0.5, randf() - 0.5) * 16.0, -skiff.vel * (0.3 + randf() * 0.3), 10 + randi() % 8, Color8(255, 170, 90), true, 0.0)

## Holding R by the skiff (or aboard): its hull is knit back as it was forged, a few cells a tick, from
## what's left outward. It's shaping magic (mana a cell, `MEND_MANA`) and takes matter: a piece of Hull
## Plating mends `MEND_HULL` cells, a plank `MEND_PLANK`.
const MEND_CELLS := 3
const MEND_MANA := 0.12
const MEND_HULL := 6
const MEND_PLANK := 3
const CRASH_PLANET := 9.0       # a crash on a planet hurts the skiff above this speed into the ground
var _mend_bank := 0             # (cells paid for and not yet mended)
var stats_mended := 0           # (cells mended: the tests read it)
var _mend_msg := 0

func _mend_skiff(m: Mage) -> void:
	if skiff == null or not m.input.mend or m.dead:
		return
	var by: bool = m.aboard == skiff or m.pos.distance_to(skiff.pos) < float(skiff.w) * 0.5 + 24.0
	if not by:
		return
	if skiff.missing() == 0:
		if frame >= _mend_msg:
			_mend_msg = frame + 90
			ui.toast("The skiff's hull is whole", Color(0.7, 0.85, 1.0), 1.5)
		return
	if frame % 2 != 0:
		return
	if _mend_bank < MEND_CELLS:
		if m.inv[Defs.HULL] > 0:
			m.inv[Defs.HULL] -= 1
			_mend_bank += MEND_HULL
		elif m.inv[Defs.PLANK] > 0:
			m.inv[Defs.PLANK] -= 1
			_mend_bank += MEND_PLANK
		elif _mend_bank <= 0:
			if frame >= _mend_msg:
				_mend_msg = frame + 120
				ui.toast("Mending the hull takes Hull Plating (salvage from wrecks) or planks", Color(1, 0.7, 0.5), 2.5)
			return
	var need := MEND_MANA * float(mini(MEND_CELLS, _mend_bank)) * (0.0 if free_magic else 1.0)
	if not has_mana(m, need, skiff.pos, "mend the hull"):
		return
	var got: Array = skiff.mend(mini(MEND_CELLS, _mend_bank))
	_mend_bank -= got.size()
	m.mana -= MEND_MANA * float(got.size()) * (0.0 if free_magic else 1.0)
	m.mana_spent_t = 0
	stats_mended += got.size()
	var from: Vector2 = _staff(m, skiff.pos)[0] if m.aboard == null else m.pos
	for p in got:
		vfx.spawn(Vfx.DOT, from.lerp(p, 0.7), (p - from).normalized() * 0.4, 14, Vfx.MANA_COL, Color(0.7, 0.9, 1.0, 0.0), 1.5, 0.5, true, 0.0, 0.9)
		vfx.spawn(Vfx.GLOW, p, Vector2.ZERO, 10, Color(0.75, 0.95, 1.0, 0.7), Color(0.4, 0.6, 1.0, 0.0), 3.0, 1.0)
	if frame % 10 == 0:
		audio.play("place", skiff.pos, 0.5)
	if skiff.missing() == 0:
		ui.toast("The hull is whole again", Color(0.7, 0.9, 1.0), 2.0)
		audio.play("blink", skiff.pos, 0.6)

## Building inside the skiff's cabin (B while aboard; user, 23 Nov: "building inside the cabin"): the cursor's
## cell in the skiff's own body. Blocks and back walls are painted cell by cell while the button is held (only
## into the room its hull closes in, never over a seat); furniture (Build.design, as in the world) goes into
## the body's `deco` layer, in front of the back wall and behind whoever sits there, resting on the cabin's
## floor, one a click; the Remove tab takes back what was built. Paid from the satchel, as in the world.
var cabin_cast := false         # (the cast button, while building in the cabin)
var _cabin_latch := false
var cabin_stats := {"blocks": 0, "walls": 0, "furniture": 0, "removed": 0}   # (the tests read it)

func _update_cabin(m: Mage) -> void:
	var sk = skiff
	build_prev = {}
	if sk == null or m.aboard != sk:
		return
	if not cabin_cast:
		_cabin_latch = false
	var piece := build_piece()
	if piece.is_empty():
		return
	if Build.HULL_KINDS.has(String(piece["kind"])):
		_update_hull(m, sk, piece)
		return
	var kind: String = piece["kind"]
	var b: Vector2 = sk.to_body(m.input.aim) + sk.com
	var ci := int(floor(b.x))
	var cj := int(floor(b.y))
	var t: int = clampi(build_thick, 1, 4)
	var cells := []       # [i, j]
	var prev := []        # [world point, colour]
	var ok := true
	match kind:
		"block", "wall":
			var mat: int = piece["mat"]
			for dj in t:
				for di in t:
					var i := ci - t / 2 + di
					var j := cj - t / 2 + dj
					if not sk.in_room(i, j):
						continue
					if kind == "block" and (sk.at(i, j) != 0 or sk.in_seat(i, j)):
						continue
					if kind == "wall" and int(sk.bg[j * sk.w + i]) == mat:
						continue
					cells.append(Vector2i(i, j))
					prev.append([sk.cell_world(i, j), Defs.COLOR[mat]])
			ok = not cells.is_empty() and m.inv[mat] >= cells.size()
			build_prev = {"cells": prev, "ok": ok}
			if cabin_cast and ok and frame % 3 == 0:
				for c in cells:
					var cc: Vector2i = c
					if sk.place(cc.x, cc.y, mat, kind == "wall"):
						m.inv[mat] -= 1
						cabin_stats["blocks" if kind == "block" else "walls"] += 1
				vfx.conjure(sk.cell_world(ci, cj), Defs.COLOR[mat])
				audio.play("place", sk.pos, 0.4)
			elif cabin_cast and not ok and not cells.is_empty():
				_build_need(piece)
		"prop":
			var d: Dictionary = Build.design(piece, build_seed)
			var rows: Array = d["rows"]
			var on_wall: bool = d.get("wall", false)
			var pw: int = String(rows[0]).length()
			var ph: int = rows.size()
			# where you point, or slid sideways to the nearest spot where it fits (the cabin's sides curve in)
			var best := []
			for off in [0, 1, -1, 2, -2, 3, -3, 4, -4, 6, -6, 8, -8, 10, -10]:
				var tri := _cabin_prop_cells(sk, rows, on_wall, ci - pw / 2 + int(off), cj)
				if best.is_empty():
					best = tri
				if bool(tri[1]):
					best = tri
					break
			cells = best[0]
			ok = bool(best[1])
			for c0 in cells:
				prev.append([sk.cell_world(int(c0[0]), int(c0[1])), Color.html(String(Build.Props.PALETTE[int(c0[2])]))])
			var cost: Dictionary = Build.payable(piece, m.inv)
			ok = ok and not cost.is_empty() and not cells.is_empty()
			build_prev = {"cells": prev, "ok": ok}
			if cabin_cast and not _cabin_latch:
				_cabin_latch = true
				if ok:
					for c2 in cells:
						sk.deco[int(c2[1]) * sk.w + int(c2[0])] = int(c2[2]) + 1
					for cm in cost:
						m.inv[int(cm)] -= int(cost[cm])
					sk.dirty = true
					cabin_stats["furniture"] += 1
					build_seed = randi()
					vfx.place_flash(sk.cell_world(ci, cj), float(maxi(pw, ph)))
					audio.play("place", sk.pos, 0.6)
				elif cost.is_empty():
					_build_need(piece)
				else:
					ui.toast("It doesn't fit in the cabin there", Color(1, 0.7, 0.5), 1.5)
		"remove":
			var layer: String = piece.get("layer", "all")
			var tr := maxi(t, 2)
			for dj2 in tr:
				for di2 in tr:
					var i3 := ci - tr / 2 + di2
					var j3 := cj - tr / 2 + dj2
					if not sk.in_room(i3, j3):
						continue
					var k3: int = j3 * sk.w + i3
					var has_front: bool = sk.made[k3] == 1 and sk.cells[k3] != 0
					var has_back: bool = sk.bg[k3] != 0 and sk.bg[k3] != sk.design_bg[k3]
					var has_furn: bool = sk.deco[k3] != 0
					if (layer in ["front", "all"] and has_front) or (layer in ["back", "all"] and has_back) or (layer in ["furn", "all"] and has_furn):
						cells.append(Vector2i(i3, j3))
						prev.append([sk.cell_world(i3, j3), Color(1.0, 0.5, 0.4)])
			ok = not cells.is_empty()
			build_prev = {"cells": prev, "ok": ok}
			if cabin_cast and ok and frame % 3 == 0:
				var furn := 0
				for c3 in cells:
					var cv: Vector2i = c3
					var k4: int = cv.y * sk.w + cv.x
					if layer in ["front", "all"] and sk.made[k4] == 1:
						var got: int = sk.remove(cv.x, cv.y, false)
						if got != 0:
							m.inv[got] += 1
					if layer in ["back", "all"] and sk.bg[k4] != 0 and sk.bg[k4] != sk.design_bg[k4]:
						var gb: int = sk.bg[k4]
						sk.bg[k4] = sk.design_bg[k4]          # (what was there as forged comes back: the glass pane)
						m.inv[gb] += 1
					if layer in ["furn", "all"] and sk.deco[k4] != 0:
						sk.deco[k4] = 0
						furn += 1
					cabin_stats["removed"] += 1
				if furn > 0:
					m.inv[Defs.PLANK] += maxi(1, furn / 10)
				sk.dirty = true
				sk.rebuild()
				vfx.shape_burst(prev.map(func(e): return e[0]), false)
		_:
			if cabin_cast and not _cabin_latch:
				_cabin_latch = true
				ui.toast("Inside the skiff: blocks, back walls and furniture (the Remove tab takes them out)", Color(1, 0.7, 0.5), 2.0)

## a piece of furniture's cells in the cabin with its left at x0 (resting on the floor under row cj, unless
## it hangs on a wall): [[[i, j, palette index]...], whether every one is free room]
func _cabin_prop_cells(sk, rows: Array, on_wall: bool, x0: int, cj: int) -> Array:
	var pw: int = String(rows[0]).length()
	var ph: int = rows.size()
	var y1 := cj
	if not on_wall:
		for drop in 30:
			var free := true
			for dx in pw:
				if not sk.in_room(x0 + dx, y1 + 1) or sk.at(x0 + dx, y1 + 1) != 0:
					free = false
					break
			if not free:
				break
			y1 += 1
	var y0 := y1 - ph + 1
	var out := []
	var fits := true
	for rj in ph:
		var row: String = rows[rj]
		for ri in pw:
			var ch := row[pw - 1 - ri] if build_flip else row[ri]
			if ch == ".":
				continue
			var i2 := x0 + ri
			var j2 := y0 + rj
			if not sk.in_room(i2, j2) or sk.at(i2, j2) != 0 or int(sk.deco[j2 * sk.w + i2]) != 0:
				fits = false
			out.append([i2, j2, int(Build.Props.CHARS.get(ch, 0))])
	return [out, fits]

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
	if m.deck:
		_deck_move(m)
		return
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
		if items.get("ship") is Dictionary:
			skiff.load_cells(items["ship"])       # (the hull you built: it answers as you left it)
	for k in skiff.riders.size():
		if skiff.riders[k] != null:
			skiff.riders[k].aboard = null
			skiff.riders[k] = null
	for pm in players:
		if pm.aboard == skiff:
			pm.aboard = null
			pm.deck = false
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
		m.deck = false
		# out beside it, behind the cockpit (on top of it if that's blocked)
		var out: Vector2 = skiff.to_world(Vector2(-skiff.com.x - 6.0, float(skiff.h) - skiff.com.y - m.h * 0.5 - 1.0))
		if space.active:
			# (out there: clear of every hull and rock: behind, on top, in front, under it)
			out = space.clear_spot(m, [out, skiff.to_world(Vector2(0.0, -skiff.com.y - m.h * 0.5 - 2.0)),
				skiff.to_world(Vector2(float(skiff.w) - skiff.com.x + 6.0, 0.0)), skiff.to_world(Vector2(-skiff.com.x - 8.0, 0.0)),
				skiff.to_world(Vector2(0.0, float(skiff.h) - skiff.com.y + m.h * 0.5 + 2.0))])
		else:
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
	# (fallen out in space: back to the planet's own frame first; the skiff answers you down there)
	var from_space: bool = space.active
	if from_space:
		space.reset_after_death()
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
	if from_space and skiff != null:
		call_skiff()

# ================================================================== save ===
const OLD_SAVE_PATH := "user://wispforge_save.json"
const GEN_VERSION := 38            # bump when the structure generator changes; older planets regenerate
const WORLD_MAGIC := 0x57465732   # "WFW2": foreground cells, then the background layer
const SEEN_MAGIC := 0x5345454e    # "SEEN": then the seen map (gpu_world.seen_bytes), compressed on its own
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
			if int(d.get("settings_v", 0)) < 2 and String(d.get("quality", "")) == "high":
				settings["quality"] = "auto"   # (high was only the old default: Auto is the new one)
	settings["settings_v"] = 2
	settings["pixel"] = int(settings["pixel"])   # JSON numbers come back as floats
	settings["music"] = int(settings["music"])
	settings["sound"] = int(settings["sound"])

func set_setting(key: String, value) -> void:
	settings[key] = value
	var f := FileAccess.open(_real_save_dir().path_join("settings.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(settings))
	if key == "quality":
		if value == "auto":
			settings["auto_q"] = "high"        # (Auto starts again from the top, and steps down if it must)
			_aq_t = 0.0
			_aq_n = 0
			_aq_wait = 300
		gpu.apply_quality(quality())
		_fxb = fx_budget()
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
	# beside the game folder while developing; an exported game (Build game.bat) keeps its saves in the
	# player's own data folder (%APPDATA%\Wisp Forge\saves), never beside the .exe (Program Files can't be written)
	var d := ProjectSettings.globalize_path("res://").path_join("../saves").simplify_path()
	if OS.has_feature("template"):
		d = OS.get_data_dir().path_join("Wisp Forge").path_join("saves")
		if "--test" in OS.get_cmdline_user_args():
			# (a built game's test run, `Wisp Forge.exe -- --test`, reports beside the .exe)
			d = OS.get_executable_path().get_base_dir().path_join("saves")
	if not DirAccess.dir_exists_absolute(d):
		DirAccess.make_dir_recursive_absolute(d)
	return d

func _save_path() -> String:
	return _save_dir().path_join("progress.json")

func save_game() -> void:
	var d := {"planet": planet.get("index", 0), "world_seed": Defs.world_seed, "inv": Array(player.inv), "known": known, "tier": tier, "dig_r": dig_r,
		"max_hp": max_hp, "max_mana": max_mana, "mana_regen": mana_regen, "heat_ward": heat_ward, "items": items, "mat": mat, "cnt": 2, "start": 1, "learned": learned.keys(),
		"furn": player.furn, "saved": Time.get_unix_time_from_system(), "played": played, "space": space.save_state()}
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
	Defs.world_seed = int(s.get("world_seed", 0))      # (journeys from before every game had its own: the classic system)
	var sps = s.get("space", {})
	space.load_state(sps if sps is Dictionary else {})
	var a: Array = s.get("inv", [])
	for i in mini(a.size(), Defs.NM):
		player.inv[i] = int(a[i])
	known = []
	for k in s.get("known", ["spark", "conjure"]):
		known.append(str(k))
	tier = int(s.get("tier", 1))
	# saves from before the scale-up stored 4.5 / 7.0; the mage is bigger now (7.5 / 11)
	var sd := float(s.get("dig_r", 7.5))
	dig_r = 14.0 if sd >= 13.0 else (11.0 if sd >= 7.0 else 7.5)
	max_hp = float(s.get("max_hp", 100))
	max_mana = float(s.get("max_mana", 100))
	mana_regen = float(s.get("mana_regen", 0.22))
	heat_ward = bool(s.get("heat_ward", false))
	items = s.get("items", {})
	if int(s.get("start", 0)) < 1:
		items["levitate"] = true    # (a journey from before levitation had to be forged keeps it)
	learned = {}
	if s.has("learned"):
		for lid in s["learned"]:
			learned[String(lid)] = true
	else:
		learn_all()                 # (a journey from before recipes were learned keeps every one)
	_apply_gear()
	if int(s.get("cnt", 0)) < 2:
		# (before the GPU's counters moved, digging what the staff couldn't cut counted as star iron)
		player.inv[Defs.STARIRON] = 0
	# (how far the skiff reaches: a journey from before the Core Drive keeps every planet it had been to)
	var rch := maxi(int(items.get("reach", 0)), int(s.get("planet", 0)))
	for wi in 25:
		if FileAccess.file_exists(_world_path(wi)):
			rch = maxi(rch, wi)
	items["reach"] = rch
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

## The autosave (every two minutes): the world copied on the GPU at once, read back a slice a frame
## (`gpu.snapshot_step`, 8 MB a frame, about 3 ms) and written on a thread, so play never stops for it.
var _autosave := {}
var autosave_log := []        # (each slice's time, for the tests)

func _autosave_begin() -> void:
	if planet.is_empty() or gpu == null or gpu.rd == null or travelling or not _autosave.is_empty():
		return
	if _save_task >= 0 and not WorkerThreadPool.is_task_completed(_save_task):
		return
	if chunks != null and not chunks.list.is_empty():
		chunks.settle_all()
	if not stamps.is_empty():
		gpu.stamp(stamps, frame)
		stamps.clear()
	var ta := Time.get_ticks_usec()
	_autosave = {"meta": _world_meta(false), "path": _world_path(int(planet["index"])), "index": int(planet["index"])}
	prof_add("autosave: meta", Time.get_ticks_usec() - ta)
	ta = Time.get_ticks_usec()
	gpu.snapshot_begin()
	prof_add("autosave: copy", Time.get_ticks_usec() - ta)

func _autosave_step() -> void:
	if travelling or planet.is_empty() or int(planet.get("index", -1)) != int(_autosave["index"]):
		gpu.snapshot_cancel()
		_autosave = {}
		return
	var ts := Time.get_ticks_usec()
	var done: bool = gpu.snapshot_step(8 << 20)
	autosave_log.append(Time.get_ticks_usec() - ts)
	if not done:
		return
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
	_save_task = WorkerThreadPool.add_task(_write_world_parts.bind(String(_autosave["path"]), gpu.snap_raw, String(_autosave["meta"]), gpu.snap_seen))
	gpu.snap_raw = []
	gpu.snap_seen = []
	_autosave = {}

## (on the saving thread) the autosave's slices joined, then written as any save
func _write_world_parts(path: String, raw_parts: Array, meta: String, seen_parts: Array) -> void:
	var raw := PackedByteArray()
	for part in raw_parts:
		raw.append_array(part)
	var seen := PackedByteArray()
	for part2 in seen_parts:
		seen.append_array(part2)
	_write_world_file(path, raw, meta, seen)

func save_world(blocking: bool, without_skiff := false) -> void:
	if planet.is_empty() or gpu == null or gpu.rd == null or travelling:
		return
	if not _autosave.is_empty():
		# (a save of the world as it is now: the autosave on its way would only write an older one over it)
		gpu.snapshot_cancel()
		_autosave = {}
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
	var seen: PackedByteArray = gpu.read_seen()
	var meta := _world_meta(without_skiff)
	var path := _world_path(int(planet["index"]))
	if blocking:
		_write_world_file(path, raw, meta, seen)
	else:
		_save_task = WorkerThreadPool.add_task(_write_world_file.bind(path, raw, meta, seen))

## save_world, with the world read back from the GPU a slice a frame (space travel: the GPU rests
## out there, so the world can't change meanwhile) and written on another thread. Await it.
func save_world_async(without_skiff := false) -> void:
	if planet.is_empty() or gpu == null or gpu.rd == null or travelling:
		return
	if not _autosave.is_empty():
		gpu.snapshot_cancel()
		_autosave = {}
	await saves_done()
	if chunks != null and not chunks.list.is_empty():
		chunks.settle_all()
	if not stamps.is_empty():
		gpu.stamp(stamps, frame)
		stamps.clear()
	var meta := _world_meta(without_skiff)
	var path := _world_path(int(planet["index"]))
	var both: Array = await gpu.read_world_async()
	_save_task = WorkerThreadPool.add_task(_write_world_file.bind(path, both[0], meta, both[1]))

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
	workshops.save_to(planet_state)
	summoning.on_save(planet_state)
	var ast = space.rocks_state(int(planet["index"]))
	if ast != null:
		planet_state["asteroids"] = ast
	var ds := []
	for d in doors:
		ds.append([d["pos"].x, d["pos"].y, d["w"], d["h"], d["side"], d["col"], d["row"], d["open"], d.get("swing", d["side"]), d.get("cells", []), _door_ax(d), int(d.get("aw", 1))])
	planet_state["doors"] = ds
	planet_state["time"] = time
	return JSON.stringify(planet_state)

func _write_world_file(path: String, raw: PackedByteArray, meta: String, seen := PackedByteArray()) -> void:
	var comp := raw.compress(FileAccess.COMPRESSION_ZSTD)
	var seen_comp := seen.compress(FileAccess.COMPRESSION_ZSTD) if not seen.is_empty() else PackedByteArray()
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
	if not seen.is_empty():
		# what you've seen of it (the fog over the rest underground), a block of its own after the cells
		f.store_32(SEEN_MAGIC)
		f.store_32(seen.size())
		f.store_32(seen_comp.size())
		f.store_buffer(seen_comp)
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
	# the seen map, if it was saved with one (a world from before it: none of it seen yet)
	var seen := PackedByteArray()
	if f.get_position() + 12 <= f.get_length() and f.get_32() == SEEN_MAGIC:
		var ssize := f.get_32()
		var scomp := f.get_buffer(f.get_32())
		seen = scomp.decompress(ssize, FileAccess.COMPRESSION_ZSTD)
	gpu.write_seen(seen)
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
	if state == "play" or state == "forge" or state == "dead" or state == "shop" or state == "station":
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
		p = [0.0, 0.0, 0, 0.0, 0]   # average, recent peak, this frame, highest since prof_reset(), the last frame
		prof[sec] = p
	p[2] += us

func _prof_frame() -> void:
	for k in prof:
		var p: Array = prof[k]
		p[0] = lerpf(p[0], float(p[2]), 0.05)
		p[1] = maxf(p[1] * 0.995, float(p[2]))
		p[3] = maxf(p[3], float(p[2]))
		p[4] = p[2]
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

# ======================================================== the ship's deck ===
# (user, 23 Nov: "Design your own hull": a ship you lay out yourself and walk about inside. X stands up out of
# a seat onto the deck, and sits down again by a free seat; F still steps off the ship. On deck you walk, jump
# and drop through one-way decks in the ship's own cells, its pull always "down" through its keel; while
# nobody's at the helm it holds where it is.)

## anyone up and about on the skiff's deck?
func crew_on_deck() -> bool:
	if skiff == null:
		return false
	for pm in players:
		if pm.aboard == skiff and pm.deck and not pm.dead:
			return true
	return false

## X aboard: stand up out of your seat onto the deck, or sit down in the free seat you're by
func deck_toggle(m: Mage) -> bool:
	var sk = skiff
	if sk == null or m.aboard != sk or m.dead or state != "play":
		return false
	var hw := float(m.w) * 0.5
	var hh := float(m.h) * 0.5
	if not m.deck:
		var k: int = sk.seat_of(m)
		if k < 0:
			return false
		var sc: Vector2i = sk.seat_cells[k]
		var b := Vector2(float(sc.x) + 0.5, float(sc.y) + 1.0 - hh)
		if not sk.box_free(b, hw - 0.5, hh - 0.5):
			ui.toast("No room to stand up here", Color(1, 0.7, 0.5), 1.5)
			return true
		sk.leave(m)
		m.deck = true
		m.deck_b = b
		m.deck_v = Vector2.ZERO
		m.on_ground = true
		ui.toast("On deck: walk about (WASD, jump); X by a free seat sits down, F steps off the ship", Color(0.7, 0.85, 1.0), 3.0)
		return true
	var best := -1
	var bd := 14.0
	for k2 in sk.seat_cells.size():
		if sk.riders[k2] != null:
			continue
		var c: Vector2i = sk.seat_cells[k2]
		var d := Vector2(float(c.x) + 0.5, float(c.y) + 1.0 - hh).distance_to(m.deck_b)
		if d < bd:
			bd = d
			best = k2
	if best < 0:
		ui.toast("No free seat here: walk to one (X), or F to step off the ship", Color(1, 0.7, 0.5), 2.0)
		return true
	sk.riders[best] = m
	m.deck = false
	m.deck_v = Vector2.ZERO
	if best == 0:
		ui.toast("At the helm", Color(0.7, 0.85, 1.0), 1.5)
	return true

## on deck: moved in the ship's own cells (they go with it as it flies and turns)
func _deck_move(m: Mage) -> void:
	var sk = skiff
	if sk == null:
		m.aboard = null
		m.deck = false
		return
	var hw := float(m.w) * 0.5
	var hh := float(m.h) * 0.5
	var b: Vector2 = m.deck_b
	var bv: Vector2 = m.deck_v
	var fwd := float(sk.facing)                      # (the ship's cells run the other way when it faces left)
	var right_w := Vector2(cos(sk.ang), sin(sk.ang))
	var face: float = (m.input.aim - m.pos).dot(right_w)
	if absf(face) > 1.0:
		m.facing = 1 if face > 0.0 else -1
	var speed: float = 1.5 * gear("speed", m) * (1.2 if m.items.has("coil") else 1.0)
	bv.x += (float(m.input.move) * fwd * speed - bv.x) * (0.35 if m.on_ground else 0.12)
	if m.on_ground:
		m.ground_t = 0
	else:
		m.ground_t += 1
	var jump: bool = m.input.jump and state == "play" and not build_on
	if jump and not m.jump_held:
		var on_plat := false
		var fy := int(round(b.y + hh))
		for i in range(int(floor(b.x - hw)), int(ceil(b.x + hw))):
			if sk.scaffold_cell(i, fy):
				on_plat = true
		if m.input.down and on_plat:
			m.drop_t = 12
			bv.y = maxf(bv.y, 1.0)
		elif m.ground_t <= 6:
			bv.y = (-4.6 if m.items.has("boots") else -3.9) * sqrt(gear("jump", m))
			audio.play("jump", m.pos, 0.6)
			m.ground_t = 99
	m.jump_held = jump
	bv.y = minf(bv.y + 0.17, 6.0)
	var was_ground: bool = m.on_ground
	var r: Array = sk.move_box(b, bv, hw, hh, true, 5 if m.on_ground else 0, m.drop_t > 0)
	if m.drop_t > 0:
		m.drop_t -= 1
	b = r[0]
	bv = r[1]
	m.on_ground = bool(r[2])
	if m.on_ground and not was_ground and m.air_time > 18:
		audio.play("land", m.pos, 0.5)
	m.air_time = 0 if m.on_ground else m.air_time + 1
	if m.on_ground:
		var a0: float = m.anim
		m.anim += absf(bv.x) * 0.13
		if int(m.anim * 0.5) != int(a0 * 0.5):
			audio.play("step", m.pos, 0.3)
	m.deck_b = b
	m.deck_v = bv
	m.pos = sk.to_world(b - sk.com)
	m.vx = bv.x * fwd
	m.vy = bv.y
	m.floating = false
	m.in_liquid = false
	m.breath = minf(m.max_breath, m.breath + 4.0)
	m.mana = minf(m.max_mana, m.mana + m.mana_regen)
	if m.iframes > 0:
		m.iframes -= 1
	# walked out of an opening in the hull, or off an open deck: off the ship, with its speed
	# (a jump high over an open deck isn't leaving it: only past its ends, or falling out under it)
	if b.x < -2.0 or b.x > float(sk.w) + 2.0 or b.y > float(sk.h) + 6.0 or b.y < -80.0:
		_off_deck(m)

func _off_deck(m: Mage) -> void:
	var sk = skiff
	var wv: Vector2 = sk.vel + sk.axis_x() * m.deck_v.x + sk.axis_y() * m.deck_v.y
	m.deck = false
	m.aboard = null
	if space.active:
		space.vel = wv
	else:
		var a := atan2(m.pos.y, m.pos.x)
		m.vx = wv.dot(basis_r(a))
		m.vy = wv.dot(basis_d(a))
		m.grid_g = m.pos

# ===================================================== building the hull ===
## The Ship tab, aboard (user, 23 Nov: "Design your own hull"): paint hull cells (plating, planking, frame,
## glass, trim, a rune deck, a one-way deck, wisp engine) onto the ship where they touch it, growing it up to
## Skiff.MAX_W x MAX_H; set the helm where the pilot sits; add or take away seats; cut cells away. Paid from
## the satchel a cell a material (and a little mana); what you cut comes back. The hull as built is what
## mending puts back, and `items["ship"]` keeps it, so the skiff answers K as you built it on any planet.
var hull_stats := {"added": 0, "cut": 0, "seats": 0, "helm": 0}   # (the tests read it)

func _update_hull(m: Mage, sk, piece: Dictionary) -> void:
	var kind: String = piece["kind"]
	var b: Vector2 = sk.to_body(m.input.aim) + sk.com
	var ci := int(floor(b.x))
	var cj := int(floor(b.y))
	var t: int = clampi(build_thick, 1, 4)
	var prev := []
	var ok := true
	match kind:
		"hull":
			var mat: int = piece["mat"]
			var cost_mat: int = (piece["cost"] as Dictionary).keys()[0]
			var sq := {}
			for dj in t:
				for di in t:
					sq[Vector2i(ci - t / 2 + di, cj - t / 2 + dj)] = true
			# (cells that touch the ship, and those touching them within the stroke)
			var take := []
			var got := {}
			var grew := true
			while grew:
				grew = false
				for c in sq:
					var cv: Vector2i = c
					if got.has(cv) or sk.at(cv.x, cv.y) != 0 or sk.in_seat(cv.x, cv.y) or _crew_at(sk, cv):
						continue
					var joins: bool = sk.can_hull(cv.x, cv.y)
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if got.has(cv + d):
							joins = true
					if joins:
						got[cv] = true
						take.append(cv)
						grew = true
			for c2 in take:
				prev.append([sk.cell_world((c2 as Vector2i).x, (c2 as Vector2i).y), Defs.COLOR[mat]])
			ok = not take.is_empty() and m.inv[cost_mat] >= take.size()
			build_prev = {"cells": prev, "ok": ok}
			if cabin_cast and frame % 3 == 0:
				if not ok:
					if not take.is_empty():
						_build_need(piece)
					return
				if not pay_mana(m, place_mana(take.size()), sk.pos, "build the hull"):
					return
				var old_com: Vector2 = sk.com
				var acc := Vector2i.ZERO
				for c3 in take:
					var cc: Vector2i = (c3 as Vector2i) + acc
					var off: Vector2i = sk.grow_for(cc.x, cc.y)
					if off != Vector2i.ZERO:
						acc += off
						cc += off
						old_com += Vector2(off)
						for pm in players:
							if pm.aboard == sk and pm.deck:
								pm.deck_b += Vector2(off)
					sk.add_hull(cc.x, cc.y, mat, _hull_variant(mat, cc.x, cc.y))
					m.inv[cost_mat] -= 1
					hull_stats["added"] += 1
				sk.finish_edit(old_com)
				items["ship"] = sk.save_cells()
				vfx.conjure(sk.cell_world(ci + acc.x, cj + acc.y), Defs.COLOR[mat])
				audio.play("place", sk.pos, 0.4)
		"cut":
			var tr := maxi(t, 1)
			var cut := []
			for dj2 in tr:
				for di2 in tr:
					var i2 := ci - tr / 2 + di2
					var j2 := cj - tr / 2 + dj2
					if sk.at(i2, j2) != 0:
						cut.append(Vector2i(i2, j2))
						prev.append([sk.cell_world(i2, j2), Color(1.0, 0.5, 0.4)])
			ok = not cut.is_empty()
			build_prev = {"cells": prev, "ok": ok}
			if cabin_cast and ok and frame % 3 == 0:
				var old_com2: Vector2 = sk.com
				for c4 in cut:
					var cv2: Vector2i = c4
					var gm: int = sk.cut(cv2.x, cv2.y)
					if gm == Defs.RUNESTONE:
						gm = Defs.MASONRY
					elif gm == Defs.SCAFFOLD:
						gm = Defs.PLANK
					if gm != 0:
						m.inv[gm] += 1
						hull_stats["cut"] += 1
				sk.finish_edit(old_com2)
				items["ship"] = sk.save_cells()
				vfx.shape_burst(prev.map(func(e): return e[0]), false)
		"helm", "seat":
			# (where someone would sit: the floor under the cursor, room for them over it)
			var skip: int = 0 if kind == "helm" else -1
			var at_j := -1
			for jj in range(cj, cj + 24):
				if sk.seat_ok(ci, jj, skip):
					at_j = jj
					break
			var existing: int = sk.seat_near(ci, cj) if kind == "seat" else -1
			if existing >= 0:
				var ec: Vector2i = sk.seat_cells[existing]
				for dj3 in range(-16, 1):
					prev.append([sk.cell_world(ec.x, ec.y + dj3), Color(1.0, 0.5, 0.4)])
				build_prev = {"cells": prev, "ok": true}
			else:
				if at_j >= 0:
					for dj4 in range(-16, 1):
						for di4 in range(-3, 4):
							if absi(di4) == 3 or dj4 == -16 or dj4 == 0:
								prev.append([sk.cell_world(ci + di4, at_j + dj4), Color(0.6, 0.9, 1.0)])
				var cost: Dictionary = Build.payable(piece, m.inv)
				ok = at_j >= 0 and not cost.is_empty() and (kind == "helm" or sk.seat_cells.size() < 8)
				build_prev = {"cells": prev, "ok": ok}
			if cabin_cast and not _cabin_latch:
				_cabin_latch = true
				if existing >= 0:
					if sk.riders[existing] != null:
						ui.toast("Someone's sitting there", Color(1, 0.7, 0.5), 1.5)
					else:
						sk.remove_seat(existing)
						m.inv[Defs.PLANK] += 4
						hull_stats["seats"] -= 1
						items["ship"] = sk.save_cells()
						ui.toast("Seat taken out (%d seats)" % sk.seat_cells.size(), Color(0.8, 0.9, 1.0), 1.5)
				elif ok:
					var cost2: Dictionary = Build.payable(piece, m.inv)
					for cm in cost2:
						m.inv[int(cm)] -= int(cost2[cm])
					if kind == "helm":
						sk.set_helm(ci, at_j)
						hull_stats["helm"] += 1
						ui.toast("The helm stands here now", Color(0.8, 0.9, 1.0), 1.5)
					else:
						sk.add_seat(ci, at_j)
						hull_stats["seats"] += 1
						ui.toast("A seat (%d in all)" % sk.seat_cells.size(), Color(0.8, 0.9, 1.0), 1.5)
					sk.designed = true
					items["ship"] = sk.save_cells()
					vfx.place_flash(sk.cell_world(ci, at_j - 8), 10.0)
					audio.play("place", sk.pos, 0.6)
				elif at_j < 0:
					ui.toast("No room to sit there: a seat needs a floor and room over it", Color(1, 0.7, 0.5), 2.0)
				elif kind == "seat" and sk.seat_cells.size() >= 8:
					ui.toast("Eight seats at most", Color(1, 0.7, 0.5), 1.5)
				else:
					_build_need(piece)

## someone on deck stands in cell c of the ship
func _crew_at(sk, c: Vector2i) -> bool:
	for pm in players:
		if pm.aboard == sk and pm.deck:
			var d: Vector2 = Vector2(float(c.x) + 0.5, float(c.y) + 0.5) - pm.deck_b
			if absf(d.x) < float(pm.w) * 0.5 + 0.6 and absf(d.y) < float(pm.h) * 0.5 + 0.6:
				return true
	return false

## the look of a hull cell: plating in courses with seams, planks in strakes, the rest by place
func _hull_variant(mat: int, i: int, j: int) -> int:
	match mat:
		Defs.HULL:
			return 0 if i % 10 == 0 else (1 if (j / 4) % 2 == 0 else 2)
		Defs.PLANK:
			return (j / 3 + i / 9) % 3
		Defs.RUNESTONE:
			return 3 if i % 6 == 0 else (i / 3 + j) % 3
	return (i + j) % 4

# ============================================================ the hold ===
## Trade goods ride as crates in your ship's hold (user, 23 Nov: a hold "for big things only"): `items["cargo"]`
## (good -> crates), bought and sold at outposts (towns.gd), as many as `hold_cap` (the room your hull closes in).
func cargo_count() -> int:
	var n := 0
	var cargo: Dictionary = items.get("cargo", {})
	for gd in cargo:
		n += int(cargo[gd])
	return n

func hold_cap() -> int:
	if skiff == null or not items.has("skiff"):
		return 0
	return skiff.hold_cap()
