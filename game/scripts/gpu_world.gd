extends RefCounted
## Owns the planet on the GPU: compiles the compute shaders, generates the
## world, steps the simulation each frame and reads back what the CPU needs
## (the picture, a collision grid around the player, the light grid and
## excavation counts).

var GS := 384            # collision grid size (cells); grows to cover the whole view
const MAXP := 4          # players the simulation can serve at once (co-op)
var LS := 4              # light grid block size (pixels); Low quality uses 6
# quality settings (see apply_quality)
var flow_passes := 4     # extra liquid-spreading passes per frame
var support_iters := 3   # structural support relaxation passes per frame
var plant_iters := 6     # background plant support passes per frame (plants.comp)
# The frame's GPU work is submitted at the end of one _process and collected at the start of the
# next, so the GPU works while Godot draws and waits for the screen (CPU and GPU overlap).
var pending := false     # a submission is in flight
var fresh := false       # results collected that main.gd hasn't taken yet
var sub_frames := []     # the collision grid frames of the last submission
## Rectangles read back WITH a frame instead of stalling it (`request_rect` / `take_rect`): they wait
## in rect_reqs, go out with the next frame's commands (rect_out) and come back in its flush (rect_done)
var rect_reqs := []
var rect_out := []
var rect_done := {}
var _rect_id := 0
var wait_us := 0         # how long the last collect waited for the GPU
var read_us := 0         # and how long reading its results back took
var gpu_us := {}         # GPU time per stage of the last frame (timestamps), for the profiler
var read_parts := {}     # and how long each part of reading it back took
## Everything the CPU reads back each frame (counters, light, picture, collision grids) is copied on the
## GPU into this one buffer and read in a single call: each separate read has a fixed cost.
var rb_buf := RID()
var rb_off := [0, 0, 0, 0]   # where the counters, light, picture and grids start in it
var _rb_slots := 1
var nav_buf := RID()         # each player's coarse nav map (shaders/navmap.comp; scripts/nav.gd)
var NG := 96                 # nav map blocks a side (GS / 4)
var NGP := 96                # bytes to a nav map row (a multiple of 4)
var nav_off := 0             # where the nav maps lie in the read-back buffer (`grid`)
var grid_off := 0            # the collision grids are read where they lie in that buffer (no copy):
var light_off := 0           # grid is the whole buffer, the grids start at grid_off, the light at light_off
var topple_iters := 2    # falling-block passes per frame
var blur_passes := 2     # light blur passes
var sun_step := 2.0      # sunlight march step (cells)
const NPARAM := 1152     # vec4 slots in the params buffer (from ROWT: the cell picture's rows)
const ROWT := 128        # P.p[ROWT + j]: picture row j of the cell picture (its shell's columns N, the column
const ROWMAX := 1024     # under the camera, and how far into it the camera's angle is): main._cell_rows

var rd: RenderingDevice
var error_text := ""
var shaders := {}        # name -> {"shader": RID, "pipeline": RID}
var sets := {}           # name -> uniform set RID

var world_buf: RID
var aux_buf: RID         # background layer (trees, plants, back walls)
var sites_buf: RID       # building sites, so no trees grow inside them
const MAX_SITES := 160
var params_buf: RID
var surf_buf: RID
var counts_buf: RID
var shells_buf: RID     # the shell table (Defs.shell_table), binding 10 in every set
var grid_buf: RID
var light_a: RID
var light_b: RID
var view_buf: RID
var seen_buf: RID        # what you've seen of the planet (fog over the rest underground: inc/seen.comp), binding 12

var VW := 480
var VH := 270
var LW := 121
var LH := 69
# the picture is the screen (VW x VH) with a margin round it (PMX, PMY): the close view draws it a cell a
# pixel and the view's shader lays it onto the screen in true world shape, which reaches past the screen's
# own rectangle (cells narrower than a world unit deep down, the planet's curve at the corners)
var PW := 121
var PH := 69
var PMX := 0
var PMY := 0

var params := PackedFloat32Array()
var surface := PackedFloat32Array()   # 8 floats per shell-0 column
var grid := PackedByteArray()
var light := PackedFloat32Array()
var counts := PackedInt32Array()
var view_img: Image
var frame := 0

var create_ms := {}     # (init_async: how long each shader took to make on the device)
const SHADERS := ["surface", "gen", "react", "move", "boundary", "brush", "grid", "light", "blur", "render", "support", "topple", "stamp", "plants", "rectread", "navmap"]

func init() -> bool:
	if not _alloc():
		return false
	var prefix: String = Defs.glsl_prefix()
	for nm in SHADERS:
		if not _compile(nm, prefix):
			return false
	_make_static_sets()
	resize(VW, VH)
	return true

## init(), spread over frames (a shader compiled a frame), for a planet of another size made while
## the game goes on (space travel: main.arrive_planet).
func init_async() -> bool:
	create_ms.clear()
	# (a frame between freeing the old world and making the new one's buffers: each takes ~100 ms on a
	# planet of 20 M cells, together they were the longest frame of a journey)
	await Engine.get_main_loop().process_frame
	var ta := Time.get_ticks_usec()
	if not _alloc():
		return false
	create_ms["(buffers)"] = (Time.get_ticks_usec() - ta) / 1000
	var prefix: String = Defs.glsl_prefix()
	# every shader to SPIR-V on a worker thread, then made on the device one a frame
	var spirvs := {}
	var task := WorkerThreadPool.add_task(func():
		for sn in SHADERS:
			spirvs[sn] = _spirv(sn, prefix))
	while not WorkerThreadPool.is_task_completed(task):
		await Engine.get_main_loop().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	for nm in SHADERS:
		if spirvs.get(nm) == null:
			return false
		var t0 := Time.get_ticks_usec()
		if not _create(nm, spirvs[nm]):
			return false
		create_ms[nm] = (Time.get_ticks_usec() - t0) / 1000
		await Engine.get_main_loop().process_frame
	ta = Time.get_ticks_usec()
	_make_static_sets()
	resize(VW, VH)
	create_ms["(sets and screen buffers)"] = (Time.get_ticks_usec() - ta) / 1000
	return true

## the device and the world's buffers, sized for the planet's geometry
func _alloc() -> bool:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		error_text = "This PC's graphics driver doesn't support compute shaders (Vulkan or Direct3D 12 needed)."
		return false
	params.resize(NPARAM * 4)
	var cells: int = Defs.total_cells()
	world_buf = rd.storage_buffer_create(cells * 4)
	rd.buffer_clear(world_buf, 0, cells * 4)
	aux_buf = rd.storage_buffer_create(cells * 4)
	rd.buffer_clear(aux_buf, 0, cells * 4)
	sites_buf = rd.storage_buffer_create((MAX_SITES + 1) * 16)
	rd.buffer_clear(sites_buf, 0, (MAX_SITES + 1) * 16)
	params_buf = rd.storage_buffer_create(NPARAM * 16)
	surf_buf = rd.storage_buffer_create(Defs.NS * 32)
	counts_buf = rd.storage_buffer_create(Defs.CNT * MAXP * 4)   # Defs.CNT counters per player
	var tbl: PackedByteArray = Defs.shell_table()
	shells_buf = rd.storage_buffer_create(tbl.size(), tbl)
	seen_buf = rd.storage_buffer_create(seen_bytes())
	rd.buffer_clear(seen_buf, 0, seen_bytes())
	return true

## the seen map's size: 16 bits a block of 2 x 2 cells (inc/seen.comp)
static func seen_bytes() -> int:
	return Defs.total_cells() / 2

func _load_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func _compile(nm: String, prefix: String) -> bool:
	var spirv = _spirv(nm, prefix)
	if spirv == null:
		return false
	return _create(nm, spirv)

## GLSL -> SPIR-V (glslang: CPU work only, so it can run beside the game)
func _spirv(nm: String, prefix: String) -> RDShaderSPIRV:
	var body := _load_text("res://shaders/%s.comp" % nm)
	if body == "":
		error_text = "Missing shader file: shaders/%s.comp" % nm
		return null
	var lines := body.split("\n")
	var out := prefix
	for ln in lines:
		var t := ln.strip_edges()
		if t.begins_with("#include"):
			var inc := t.get_slice("\"", 1)
			out += _load_text("res://shaders/inc/%s.comp" % inc) + "\n"
		else:
			out += ln + "\n"
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, out)
	var spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		error_text = "Shader '%s' failed to compile:\n%s" % [nm, spirv.compile_error_compute]
		printerr(error_text)
		return null
	return spirv

## the shader and its pipeline on the device
func _create(nm: String, spirv: RDShaderSPIRV) -> bool:
	var sh: RID = rd.shader_create_from_spirv(spirv, nm)
	if not sh.is_valid():
		error_text = "Shader '%s' could not be created." % nm
		return false
	shaders[nm] = {"shader": sh, "pipeline": rd.compute_pipeline_create(sh)}
	return true

func _u(binding: int, buf: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buf)
	return u

func _mkset(nm: String, pairs: Array) -> RID:
	var us: Array[RDUniform] = []
	for pr in pairs:
		us.append(_u(pr[0], pr[1]))
	us.append(_u(10, shells_buf))            # (every shader has the shell table: common.comp)
	return rd.uniform_set_create(us, shaders[nm]["shader"], 0)

func _make_static_sets() -> void:
	sets["surface"] = _mkset("surface", [[1, params_buf], [2, surf_buf]])
	sets["gen"] = _mkset("gen", [[0, world_buf], [1, params_buf], [2, surf_buf], [8, aux_buf], [9, sites_buf]])
	sets["react"] = _mkset("react", [[0, world_buf], [1, params_buf], [2, surf_buf], [8, aux_buf]])
	sets["move"] = _mkset("move", [[0, world_buf]])
	sets["boundary"] = _mkset("boundary", [[0, world_buf]])
	sets["support"] = _mkset("support", [[0, world_buf], [8, aux_buf]])
	sets["plants"] = _mkset("plants", [[0, world_buf], [8, aux_buf]])
	sets["topple"] = _mkset("topple", [[0, world_buf]])
	sets["brush"] = _mkset("brush", [[0, world_buf], [1, params_buf], [3, counts_buf], [8, aux_buf]])

## (Re)creates the screen-sized buffers.
func resize(w: int, h: int) -> void:
	flush()
	VW = w
	VH = h
	PMX = int(ceil(VW * 0.11)) + 4
	PMY = 24
	PW = VW + 2 * PMX
	PH = VH + 2 * PMY
	LW = int(ceil(float(PW) / LS)) + 1
	LH = int(ceil(float(PH) / LS)) + 1
	GS = clampi(int(ceil((maxi(w, h) + 96) / 4.0)) * 4, 384, 1024)
	NG = GS / 4
	NGP = int(ceil(NG / 4.0)) * 4
	for key in ["light", "blur_h", "blur_v", "render", "grid", "navmap"]:
		if sets.has(key) and sets[key].is_valid() and rd.uniform_set_is_valid(sets[key]):
			rd.free_rid(sets[key])
	for b in [light_a, light_b, view_buf, grid_buf, rb_buf, nav_buf]:
		if b.is_valid():
			rd.free_rid(b)
	grid_buf = rd.storage_buffer_create(GS * GS * MAXP)    # one collision grid per player
	nav_buf = rd.storage_buffer_create(NG * NGP * MAXP)    # and its nav map
	grid = PackedByteArray()
	sets["grid"] = _mkset("grid", [[0, world_buf], [1, params_buf], [2, surf_buf], [7, grid_buf], [3, counts_buf], [8, aux_buf]])     # (the surface table: the marsh's ground fog)
	sets["navmap"] = _mkset("navmap", [[7, grid_buf], [11, nav_buf]])
	light_a = rd.storage_buffer_create(LW * LH * 16)
	light_b = rd.storage_buffer_create(LW * LH * 16)
	view_buf = rd.storage_buffer_create(PW * PH * 4)
	# read back in one go: the counters, the light, the picture, the nav maps, then the grids
	nav_off = Defs.CNT * MAXP * 4 + LW * LH * 16 + PW * PH * 4
	rb_off = [0, Defs.CNT * MAXP * 4, Defs.CNT * MAXP * 4 + LW * LH * 16, nav_off + NG * NGP * MAXP]
	rb_buf = rd.storage_buffer_create(rb_off[3] + GS * GS * MAXP)
	sets["light"] = _mkset("light", [[0, world_buf], [1, params_buf], [2, surf_buf], [4, light_a], [8, aux_buf], [12, seen_buf]])
	sets["blur_h"] = _mkset("blur", [[4, light_a], [5, light_b]])
	sets["blur_v"] = _mkset("blur", [[4, light_b], [5, light_a]])
	sets["render"] = _mkset("render", [[0, world_buf], [1, params_buf], [2, surf_buf], [4, light_a], [6, view_buf], [8, aux_buf], [12, seen_buf]])

# ------------------------------------------------------------------ helpers --
func setp(slot: int, v: Vector4) -> void:
	params[slot * 4] = v.x
	params[slot * 4 + 1] = v.y
	params[slot * 4 + 2] = v.z
	params[slot * 4 + 3] = v.w

func _upload_params() -> void:
	var bytes := params.to_byte_array()
	rd.buffer_update(params_buf, 0, bytes.size(), bytes)

func _pc(i: Array, f: Array) -> PackedByteArray:
	var ii := PackedInt32Array()
	for k in 8:
		ii.append(int(i[k]) if k < i.size() else 0)
	var ff := PackedFloat32Array()
	for k in 8:
		ff.append(float(f[k]) if k < f.size() else 0.0)
	var out := ii.to_byte_array()
	out.append_array(ff.to_byte_array())
	return out

func _dispatch(cl: int, shader_name: String, set_name: String, ints: Array, floats: Array, gx: int, gy: int) -> void:
	if gx <= 0 or gy <= 0:
		return
	var pcb := _pc(ints, floats)
	rd.compute_list_bind_compute_pipeline(cl, shaders[shader_name]["pipeline"])
	rd.compute_list_bind_uniform_set(cl, sets[set_name], 0)
	rd.compute_list_set_push_constant(cl, pcb, pcb.size())
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_add_barrier(cl)

static func groups(n: int, size: int) -> int:
	return int(ceil(float(n) / float(size)))

# --------------------------------------------------------------- generation --
## Writes biome / planet data to params, builds the surface table and returns it.
func build_surface(planet: Dictionary) -> void:
	flush()
	var bl: Array = planet["biomes"]
	setp(0, Vector4(0, 0, 0, planet["seed"]))
	var sky: Color = planet["sky"]
	setp(4, Vector4(sky.r, sky.g, sky.b, bl.size()))
	setp(7, Vector4(planet["magmaR"], planet["sea"], planet["lava"], planet["rich"]))
	setp(26, Vector4(float(Defs.terrain), 0.0, 0.0, 0.0))          # (the journey's terrain: surface.comp, gen.comp)
	for b in bl.size():
		var bd: Dictionary = Defs.BIOMES[bl[b]]
		# (terrain 3: an ocean is abyssal, flags 32: surface.comp; 27 Nov)
		# (not on the exotic worlds: the deep ocean world's "ocean" is its shallow shelves round its own abyss)
		var bfl: int = int(bd["flags"]) | (32 if Defs.terrain >= 3 and String(bl[b]) == "ocean" and not planet.has("exotic") else 0)
		setp(8 + 2 * b, Vector4(bd["off"], bd["amp"], bd["top"], bfl))
		setp(9 + 2 * b, Vector4(bd["sub"], bd["topD"], bd["subD"], int(bd["ug"]) + int(bd["flora"]) * 16))
	# where each biome starts round the planet (biomes have widths of their own)
	var bst := Defs.biome_starts(planet)
	var st8 := PackedFloat32Array([1, 1, 1, 1, 1, 1, 1, 1])
	for q in mini(bst.size(), 8):
		st8[q] = bst[q]
	setp(24, Vector4(st8[0], st8[1], st8[2], st8[3]))
	setp(25, Vector4(st8[4], st8[5], st8[6], st8[7]))
	# the planet kind's own ore (gen.comp `strata`)
	var ko: Dictionary = Defs.KIND_ORES.get(String(planet.get("kind", "temperate")), {})
	if ko.is_empty():
		setp(126, Vector4.ZERO)
		setp(127, Vector4.ZERO)
	else:
		var hs: Array = ko["hosts"]
		setp(126, Vector4(ko["mat"], hs[0], hs[1], hs[2]))
		# (+0.012: every ore a little rarer, user 21 Nov)
		setp(127, Vector4(ko["depth"][0], ko["depth"][1], float(ko["thr"]) + 0.012, float(hs[3]) + (1000.0 if ko.get("sea", false) else 0.0)))
	setp(120, Vector4(0, 0, 0, 0))
	_upload_params()
	var cl := rd.compute_list_begin()
	_dispatch(cl, "surface", "surface", [Defs.NS], [], groups(Defs.NS, 64), 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	surface = rd.buffer_get_data(surf_buf).to_float32_array()

## Generates every cell, in row bands so no single GPU job runs too long.
func generate(spawn_angle: float, boss: Vector4, sites: Array) -> void:
	for job in generate_prepare(spawn_angle, boss, sites):
		generate_band(job)

## The generation of a whole planet, set up and split into its row bands: each band can run on its
## own (`generate_band`), so a planet can also be made a band a frame while the game goes on.
var chamber_theme := 0.0      # how the heart's chamber is lined (Defs.HEART_CHAMBER; main sets it before a planet is made)

func generate_prepare(spawn_angle: float, boss: Vector4, sites: Array) -> Array:
	flush()
	var sd := PackedFloat32Array()
	sd.resize((MAX_SITES + 1) * 4)
	var nsite := mini(sites.size(), MAX_SITES)
	sd[0] = nsite
	for k in nsite:
		var q: Vector2 = sites[k]
		sd[(k + 1) * 4] = q.x
		sd[(k + 1) * 4 + 1] = q.y
	var sb := sd.to_byte_array()
	rd.buffer_update(sites_buf, 0, sb.size(), sb)
	rd.buffer_clear(seen_buf, 0, seen_bytes())      # (a new planet: none of it seen yet)
	setp(120, boss)
	setp(121, Vector4(spawn_angle, 0, chamber_theme, 0))
	_upload_params()
	var jobs := []
	for s in Defs.NSH:
		var y0: int = Defs.SH_Y0[s]
		var y1: int = Defs.SH_Y1[s]
		var band := 48 if s == Defs.SURF else 96
		var y := y0
		while y < y1:
			var ye := mini(y + band, y1)
			jobs.append([s, y, ye])
			y = ye
	return jobs

func generate_band(job: Array) -> void:
	var s: int = job[0]
	var y: int = job[1]
	var ye: int = job[2]
	var cl := rd.compute_list_begin()
	_dispatch(cl, "gen", "gen", [s, y, ye], [], groups(int(Defs.SH_N[s]), 16), groups(ye - y, 16))
	rd.compute_list_end()
	rd.submit()
	rd.sync()

## Knitting the planet's plants (plants.comp mode 1; user, 22 Nov: "i have also seen normal trees and
## mushrooms fall apart before i touch them"): where trees or mushroom caps overlap, gen.comp gives each
## cell to one of them, which can leave a piece of one cut off from its own wood. Run once as the planet
## is made (after the stamps: a lair's trees too), the passes settle every plant's support and give any
## such piece to the plant it leans on, so nothing is left to break off when you come near.
const KNIT_PASSES := 160
const KNIT_CHUNKS := 24

## the windows the knitting covers: the land round the whole planet, from a little under the ground
## to over the tallest trees, in KNIT_CHUNKS slices each as deep as its own ground needs
func knit_windows() -> Array:
	var wins := []
	var n: int = surface.size() / 8
	if n == 0:
		return wins
	for c in KNIT_CHUNKS:
		var i0 := c * n / KNIT_CHUNKS
		var i1 := maxi((c + 1) * n / KNIT_CHUNKS, i0 + 1)
		var rmin := 1e9
		var rmax := -1e9
		for i in range(i0, i1):
			rmin = minf(rmin, surface[i * 8])
			rmax = maxf(rmax, surface[i * 8])
		var y0 := clampi(Defs.row_at(rmax + 125.0), -Defs.ORBIT_ROWS, Defs.ROWS)
		var y1 := clampi(Defs.row_at(rmin - 30.0) + 1, -Defs.ORBIT_ROWS, Defs.ROWS)
		if y0 >= y1:
			continue
		var span := TAU / float(KNIT_CHUNKS) + 0.004
		var s0 := Defs.shell_of_row(y0)
		wins.append({"y0": y0, "y1": y1, "th0": TAU * float(c) / float(KNIT_CHUNKS) - 0.002, "span": span,
			"s0": s0, "s1": Defs.shell_of_row(y1 - 1), "maxc": win_count(s0, span) + 4})
	return wins

## `passes` knitting passes over `wins` (knit_windows), the passes from `from` on of KNIT_PASSES (the
## last one trims what nothing holds)
func knit_plants(wins: Array, passes: int, from := 0) -> void:
	flush()
	if wins.is_empty():
		return
	var cl := rd.compute_list_begin()
	for it in range(from, from + passes):
		var last := 1 if it == KNIT_PASSES - 1 else 0
		for w in wins:
			_dispatch(cl, "plants", "plants", [0, w.y0, w.y1, 0, 0, it, 1, last], _wf(w), groups(w.maxc, 16), groups(w.y1 - w.y0, 16))
	rd.compute_list_end()
	rd.submit()
	rd.sync()

## Writes generated structures into the planet. Each: {x0, y0, w, h, data: PackedInt32Array}.
func stamp(structs: Array, seed: int) -> void:
	flush()
	if structs.is_empty():
		return
	var all := PackedInt32Array()
	var offs := []
	for st in structs:
		offs.append(all.size())
		all.append_array(st["data"])
	var bytes := all.to_byte_array()
	var buf := rd.storage_buffer_create(bytes.size(), bytes)
	var uset := _mkset("stamp", [[0, world_buf], [8, aux_buf], [9, buf]])
	var cl := rd.compute_list_begin()
	for k in structs.size():
		var st: Dictionary = structs[k]
		var mode := 1 if st.get("raw", false) else 0      # raw: two words a cell (scripts/chunks.gd)
		# (its anchor: a generated structure's own; anything else is placed near you)
		var ax: int = posmod(int(st.get("ax", Defs.anchor_c)), Defs.NS)
		var aw: int = int(st.get("aw", 1))
		_dispatch_set(cl, "stamp", uset, [st["x0"], st["y0"], st["w"], st["h"], offs[k], seed + k, mode, ax], groups(st["w"], 16), groups(st["h"], 16), [float(aw)])
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(uset)
	rd.free_rid(buf)

## Runs the simulation (no rain, no rendering) around the given points so freshly stamped
## structures settle: whatever the generator (or a ruin's decay) left unsupported falls now.
var settle_ms := Vector2i.ZERO     # the last settle: ms recording the passes, ms waiting for the GPU
var settle_wins := 0

func settle(centers: Array, half: float, frames: int) -> void:
	flush()
	if centers.is_empty():
		return
	setp(3, Vector4(0, 0, 0, 0))
	setp(6, Vector4(0, 0, 0, 0))
	_upload_params()
	var wins := []
	for c in centers:
		# each entry: [world position, half size]; half > 0 overrides
		wins.append_array(_window(c[0], half if half > 0.0 else float(c[1])))
	var t_rec := 0
	var t_sync := 0
	# (what settles is loose rubble, sand and water: fewer liquid and plant passes than a game frame)
	var keep_pi := plant_iters
	var keep_fp := flow_passes
	plant_iters = mini(plant_iters, 2)
	flow_passes = mini(flow_passes, 2)
	for f in frames:
		frame += 1
		var ta := Time.get_ticks_usec()
		var cl := rd.compute_list_begin()
		_sim_passes(cl, wins, -1, 0, 0)
		rd.compute_list_end()
		var tb := Time.get_ticks_usec()
		rd.submit()
		rd.sync()
		t_rec += tb - ta
		t_sync += Time.get_ticks_usec() - tb
	plant_iters = keep_pi
	flow_passes = keep_fp
	settle_ms = Vector2i(t_rec / 1000, t_sync / 1000)
	settle_wins = wins.size()

func _dispatch_set(cl: int, shader_name: String, uset: RID, ints: Array, gx: int, gy: int, floats := []) -> void:
	var pcb := _pc(ints, floats)
	rd.compute_list_bind_compute_pipeline(cl, shaders[shader_name]["pipeline"])
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_set_push_constant(cl, pcb, pcb.size())
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_add_barrier(cl)

func surf_at(angle: float) -> Vector4:
	var n: int = surface.size() / 8          # (its own size: a planet being made may not have one yet)
	if n == 0:
		return Vector4.ZERO
	var a := fposmod(angle, TAU)
	var i := mini(int(a / TAU * n), n - 1)
	return Vector4(surface[i * 8], surface[i * 8 + 1], surface[i * 8 + 2], surface[i * 8 + 3])

func surf_b(angle: float) -> Vector4:
	var n: int = surface.size() / 8          # (its own size: a planet being made may not have one yet)
	if n == 0:
		return Vector4.ZERO
	var a := fposmod(angle, TAU)
	var i := mini(int(a / TAU * n), n - 1)
	return Vector4(surface[i * 8 + 4], surface[i * 8 + 5], surface[i * 8 + 6], surface[i * 8 + 7])

# ------------------------------------------------------------- simulation --
## The simulated window: rows y0..y1 and an angular span around the camera.
func _window(center: Vector2, half := -1.0) -> Array:
	var rc := center.length()
	if half < 0.0:
		half = sqrt(float(VW * VW + VH * VH)) * 0.5 + 56.0
	var y0 := clampi(Defs.row_at(rc + half), -Defs.ORBIT_ROWS, Defs.ROWS)
	var y1 := clampi(Defs.row_at(rc - half) + 1, -Defs.ORBIT_ROWS, Defs.ROWS)
	if y0 >= y1:
		return []
	var rmin := maxf(rc - half, Defs.R_IN)
	var dth := half / rmin
	var thc := atan2(center.y, center.x)
	var span := TAU if dth * 2.0 >= TAU else 2.0 * dth
	var s0 := Defs.shell_of_row(y0)
	var s1 := Defs.shell_of_row(y1 - 1)
	# (each pass is one dispatch over the window, as wide as its widest shell, the top one; the
	# shaders work out their own shell per row: common.comp winCount / winX0)
	return [{"y0": y0, "y1": y1, "th0": thc - dth, "span": span, "s0": s0, "s1": s1,
		"maxc": win_count(s0, span) + 4}]

## a window's columns in shell s (as common.comp winCount)
static func win_count(s: int, span: float) -> int:
	var n: int = Defs.SH_N[s]
	if span >= TAU:
		return n
	var c := int(ceil(span / TAU * float(n))) + 2
	c += c & 1
	return mini(c, n)

## the push-constant floats for a pass over window w (`c`: the pass's own, then the window's angles)
static func _wf(w: Dictionary, c := []) -> Array:
	var f := []
	for k in 4:
		f.append(float(c[k]) if k < c.size() else 0.0)
	f.append(float(w["th0"]))
	f.append(float(w["span"]))
	return f

## Simulated areas around every player. Players close together share one area (so no cell is
## ever simulated twice in a frame); players far apart each get their own.
func _windows(centers: Array) -> Array:
	var base := sqrt(float(VW * VW + VH * VH)) * 0.5 + 56.0
	var groups := []    # each: [members]
	for c in centers:
		var placed := false
		for gr in groups:
			for m in gr:
				if (m as Vector2).distance_to(c) < base * 2.2:
					gr.append(c)
					placed = true
					break
			if placed:
				break
		if not placed:
			groups.append([c])
	var out := []
	for gr in groups:
		var mean := Vector2.ZERO
		for m in gr:
			mean += m
		mean /= gr.size()
		var spread := 0.0
		for m in gr:
			spread = maxf(spread, (m as Vector2).distance_to(mean))
		out.append_array(_window(mean, base + spread))
	return out

## One simulation + render step.
## sim_centers: where to simulate (one per player; the local one is the camera).
## grid_frames: [centre, angle] per player slot, for that player's collision grid.
## One frame of GPU work: brushes, `sim_steps` rounds of simulation (more than one when the game
## catches up on a slow frame, none on a very fast screen), then the collision grids, light and the
## picture. With wait = false it returns as soon as the work is submitted; collect() picks up the
## results. sim_only: just simulate (loading), and wait for it.
func step(sim_centers: Array, grid_frames: Array, with_brushes: bool, sim_only: bool, sim_steps := 1, wait := true) -> void:
	flush()
	params[1] = frame + 1
	_upload_params()
	rd.buffer_clear(counts_buf, 0, Defs.CNT * MAXP * 4)
	var win := _windows(sim_centers)
	rd.capture_timestamp("start")
	var cl := rd.compute_list_begin()
	if with_brushes:
		for w in win:
			_dispatch(cl, "brush", "brush", [0, w.y0, w.y1, 0, 0, frame + 1], _wf(w), groups(w.maxc, 16), groups(w.y1 - w.y0, 16))
	var rain_row := clampi(int(Defs.R_TOP - params[121 * 4 + 2]), 0, Defs.ROWS - 1)
	var rain_mat := int(params[3 * 4 + 1])
	for k in sim_steps:
		frame += 1
		_sim_passes(cl, win, rain_row, rain_mat, CREAK_FRAMES)
	if not sim_only:
		rd.compute_list_end()
		rd.capture_timestamp("simulation")
		cl = rd.compute_list_begin()
		for gs in mini(grid_frames.size(), MAXP):
			var gf: Array = grid_frames[gs]
			var gc: Vector2 = gf[0]
			_dispatch(cl, "grid", "grid", [GS, gs], [gc.x, gc.y, gf[1]], groups(GS / 4, 16), groups(GS, 16))
		for gs2 in mini(grid_frames.size(), MAXP):
			_dispatch(cl, "navmap", "navmap", [GS, gs2, NG, NGP], [], groups(NGP / 4, 16), groups(NG, 16))
		rd.compute_list_end()
		rd.capture_timestamp("collision grid")
		cl = rd.compute_list_begin()
		_dispatch(cl, "light", "light", [LW, LH, LS], [], groups(LW, 16), groups(LH, 16))
		for k in blur_passes:
			_dispatch(cl, "blur", "blur_h", [LW, LH, 1], [], groups(LW, 16), groups(LH, 16))
			_dispatch(cl, "blur", "blur_v", [LW, LH, 0], [], groups(LW, 16), groups(LH, 16))
		rd.compute_list_end()
		rd.capture_timestamp("light")
		cl = rd.compute_list_begin()
		_dispatch(cl, "render", "render", [PW, PH, LW, LH], [], groups(PW, 16), groups(PH, 16))
	if not sim_only:
		# rectangles asked for since the last frame are copied out at its end (`request_rect`)
		for rq in rect_reqs:
			var rbuf := rd.storage_buffer_create(int(rq[3]) * int(rq[4]) * 8)
			var rset := _mkset("rectread", [[0, world_buf], [8, aux_buf], [9, rbuf]])
			_dispatch_set(cl, "rectread", rset, [posmod(int(rq[1]), Defs.NS), int(rq[2]), int(rq[3]), int(rq[4]), int(rq[5]), int(rq[6])], groups(int(rq[3]), 16), groups(int(rq[4]), 16))
			rect_out.append([rq[0], rbuf, rset, int(rq[3]) * int(rq[4])])
		rect_reqs.clear()
	rd.compute_list_end()
	rd.capture_timestamp("picture")
	if not sim_only:
		# everything to be read back, into one buffer
		_rb_slots = clampi(grid_frames.size(), 1, MAXP)
		rd.buffer_copy(counts_buf, rb_buf, 0, rb_off[0], Defs.CNT * MAXP * 4)
		rd.buffer_copy(light_a, rb_buf, 0, rb_off[1], LW * LH * 16)
		rd.buffer_copy(view_buf, rb_buf, 0, rb_off[2], PW * PH * 4)
		rd.buffer_copy(nav_buf, rb_buf, 0, nav_off, NG * NGP * _rb_slots)
		rd.buffer_copy(grid_buf, rb_buf, 0, rb_off[3], GS * GS * _rb_slots)
	rd.submit()
	if sim_only:
		rd.sync()
		return
	pending = true
	sub_frames = grid_frames
	if wait:
		flush()

## Wait for the submitted frame (if any) and read its results back.
func flush() -> void:
	if not pending:
		return
	var t0 := Time.get_ticks_usec()
	rd.sync()
	wait_us = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	pending = false
	# GPU time per stage, from the timestamps between the stages
	var nt := rd.get_captured_timestamps_count()
	for k in range(1, nt):
		var dt := rd.get_captured_timestamp_gpu_time(k) - rd.get_captured_timestamp_gpu_time(k - 1)
		gpu_us[rd.get_captured_timestamp_name(k)] = int(dt / 1000)
	var tq := Time.get_ticks_usec()
	var all := rd.buffer_get_data(rb_buf, 0, rb_off[3] + GS * GS * _rb_slots)
	read_parts["read: one copy"] = Time.get_ticks_usec() - tq
	tq = Time.get_ticks_usec()
	counts = all.slice(rb_off[0], rb_off[1]).to_int32_array()
	var vb := all.slice(rb_off[2], rb_off[2] + PW * PH * 4)
	grid = all
	grid_off = rb_off[3]
	light_off = rb_off[1]
	read_parts["read: unpack"] = Time.get_ticks_usec() - tq
	tq = Time.get_ticks_usec()
	view_img = Image.create_from_data(PW, PH, false, Image.FORMAT_RGBA8, vb)
	read_parts["read: picture to image"] = Time.get_ticks_usec() - tq
	for ro in rect_out:
		var both := rd.buffer_get_data(ro[1]).to_int32_array()
		var nn: int = ro[3]
		rect_done[ro[0]] = {"fg": both.slice(0, nn), "bg": both.slice(nn, 2 * nn)}
		rd.free_rid(ro[2])
		rd.free_rid(ro[1])
	rect_out.clear()
	fresh = true
	read_us = Time.get_ticks_usec() - t0

## High / Medium / Low: how much work each frame does. Low is for weaker graphics (and phones later).
func apply_quality(q: String) -> void:
	match q:
		"low":
			plant_iters = 3
			flow_passes = 2
			support_iters = 2
			topple_iters = 1
			blur_passes = 1
			sun_step = 3.0
			LS = 6
		"medium":
			plant_iters = 4
			flow_passes = 3
			support_iters = 2
			topple_iters = 2
			blur_passes = 1
			sun_step = 2.5
			LS = 4
		_:
			plant_iters = 6
			flow_passes = 4
			support_iters = 3
			topple_iters = 2
			blur_passes = 2
			sun_step = 2.0
			LS = 4
	if rd != null:
		resize(VW, VH)

## Reactions, structural support, falling blocks, then falling sand and flowing liquids.
const CREAK_FRAMES := 48    # a loose piece creaks this long (0.8 s) before it drops

func _sim_passes(cl: int, win: Array, rain_row: int, rain_mat: int, creak: int) -> void:
	for w in win:
		_dispatch(cl, "react", "react", [0, w.y0, w.y1, 0, 0, frame, rain_row, rain_mat], _wf(w), groups(w.maxc, 16), groups(w.y1 - w.y0, 16))
	# background plants: several passes, so a cut tree knows it is cut within a few frames
	for it in plant_iters:
		for w in win:
			_dispatch(cl, "plants", "plants", [0, w.y0, w.y1, 0, 0, frame * plant_iters + it], _wf(w), groups(w.maxc, 16), groups(w.y1 - w.y0, 16))
	for it in support_iters:
		for w in win:
			_dispatch(cl, "support", "support", [0, w.y0, w.y1, 0, 0, frame], _wf(w), groups(w.maxc, 16), groups(w.y1 - w.y0, 16))
	for it in topple_iters:
		for w in win:
			# (a thread per column of each shell in the window: shells along y)
			_dispatch(cl, "topple", "topple", [w.s0, w.y0, w.y1, 0, 0, frame * 2 + it, creak * topple_iters], _wf(w), groups(w.maxc, 64), int(w.s1) - int(w.s0) + 1)
	var offs := [[0, 0], [1, 1], [1, 0], [0, 1]]
	for pass_i in 2 + flow_passes:
		var full := pass_i < 2
		var o: Array = offs[(frame * 2 + pass_i) % 4]
		for w in win:
			# 2 x 2 blocks from an even row (every shell starts on an even row, so no block straddles
			# a seam unless it's offset onto it, and then the shader skips it)
			var ybase: int = int(floor(float(w.y0) / 2.0)) * 2
			var ylim: int = mini(w.y1 + 1, Defs.ROWS)
			var brows: int = (ylim - ybase) / 2 + 1
			_dispatch(cl, "move", "move", [0, ybase, ylim, 0, 0, frame * 8 + pass_i, o[0], o[1]], _wf(w, [0.0 if full else 1.0]), groups(w.maxc / 2 + 1, 16), groups(brows, 16))
		if full:
			for w in win:
				# every seam in the window (the shells s0 .. s1 - 1 over them)
				if int(w.s1) > int(w.s0):
					_dispatch(cl, "boundary", "boundary", [w.s0, w.y0, w.y1, 0, 0, frame * 8 + pass_i], _wf(w), groups(w.maxc, 64), int(w.s1) - int(w.s0))

func grid_type(slot: int, i: int, j: int) -> int:
	var k := grid_off + slot * GS * GS + j * GS + i
	if i < 0 or j < 0 or i >= GS or j >= GS or k >= grid.size():
		return 0
	return grid[k] & 0x3F

## what's built in the background of a grid cell: 1 furniture (or a torch), 2 a back wall, 0 nothing;
## -1 outside the grid
func grid_bg(slot: int, i: int, j: int) -> int:
	var k := grid_off + slot * GS * GS + j * GS + i
	if i < 0 or j < 0 or i >= GS or j >= GS or k >= grid.size():
		return -1
	return grid[k] >> 6

## the light at a pixel of the picture (main.world_to_pic, screen_to_pic)
func light_at(px: Vector2) -> Color:
	var i := clampi(int(px.x / LS), 0, LW - 1)
	var j := clampi(int(px.y / LS), 0, LH - 1)
	var k := light_off + (j * LW + i) * 16
	if light_off == 0 or k + 12 > grid.size():
		return Color.WHITE
	# (a: how clear of the fog over the unseen underground it is, 1 clear)
	return Color(minf(sqrt(maxf(grid.decode_float(k), 0.0) + 0.008), 1.3), minf(sqrt(maxf(grid.decode_float(k + 4), 0.0) + 0.008), 1.3), minf(sqrt(maxf(grid.decode_float(k + 8), 0.0) + 0.008), 1.3),
		clampf(grid.decode_float(k + 12), 0.0, 1.0))

## A w x h block of shell-0 cells (column c0.., row r0..; columns wrap around the planet), both
## layers: {"fg": PackedInt32Array, "bg": PackedInt32Array}, row by row. For a one-off look (picking
## up a piece of furniture, checking a bed): it waits for the GPU.
func read_rect(c0: int, r0: int, w: int, h: int, ax := -1, aw := 1) -> Dictionary:
	# a small compute pass copies just the rectangle (both layers) into a buffer of its own; reading
	# that back is far cheaper than whole rows of the planet
	flush()
	var t0 := Time.get_ticks_usec()
	var buf := rd.storage_buffer_create(w * h * 8)
	var uset := _mkset("rectread", [[0, world_buf], [8, aux_buf], [9, buf]])
	var cl := rd.compute_list_begin()
	# (the cells as a stamp anchored at ax, aw wide puts them; by default the anchor near you)
	var rax: int = posmod(Defs.anchor_c if ax < 0 else ax, Defs.NS)
	_dispatch_set(cl, "rectread", uset, [posmod(c0, Defs.NS), r0, w, h, rax, aw], groups(w, 16), groups(h, 16))
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var both := rd.buffer_get_data(buf).to_int32_array()
	rd.free_rid(uset)
	rd.free_rid(buf)
	read_us += Time.get_ticks_usec() - t0
	return {"fg": both.slice(0, w * h), "bg": both.slice(w * h, 2 * w * h)}

## Ask for a rectangle of the world (as `read_rect`) without stalling: it goes out with the next frame
## and comes back when that frame is read, a frame or two later. Returns an id for `take_rect`.
func request_rect(c0: int, r0: int, w: int, h: int, ax := -1, aw := 1) -> int:
	_rect_id += 1
	rect_reqs.append([_rect_id, c0, r0, w, h, posmod(Defs.anchor_c if ax < 0 else ax, Defs.NS), aw])
	return _rect_id

## A requested rectangle ({"fg", "bg"}) once it's back (then forgotten), else {}.
func take_rect(id: int) -> Dictionary:
	if not rect_done.has(id):
		return {}
	var out: Dictionary = rect_done[id]
	rect_done.erase(id)
	return out

## Both layers (and, `with_seen`, the seen map after them: what a save keeps).
func read_world(with_seen := false) -> PackedByteArray:
	flush()
	var out := rd.buffer_get_data(world_buf)
	out.append_array(rd.buffer_get_data(aux_buf))
	if with_seen:
		out.append_array(rd.buffer_get_data(seen_buf))
	return out

## the seen map alone (saved as a block of its own after the world's cells)
func read_seen() -> PackedByteArray:
	flush()
	return rd.buffer_get_data(seen_buf)

func write_seen(data: PackedByteArray) -> void:
	flush()
	if data.size() == seen_bytes():
		rd.buffer_update(seen_buf, 0, seen_bytes(), data)
	else:
		rd.buffer_clear(seen_buf, 0, seen_bytes())

## read_world a slice a frame (8 MB at a time), then the seen map: [cells, seen]. Await it.
func read_world_async() -> Array:
	flush()
	var out := PackedByteArray()
	var n: int = Defs.total_cells() * 4
	var step := 8 << 20
	for buf in [world_buf, aux_buf]:
		var o := 0
		while o < n:
			var sz := mini(step, n - o)
			out.append_array(_read_slice(buf, o, sz))
			o += sz
			await Engine.get_main_loop().process_frame
	return [out, read_seen()]

## An autosave's copy of the world: taken on the GPU in one go (a consistent moment, a millisecond or so),
## then read back a slice a frame (`snapshot_step`) while the game goes on; read in one go, the whole
## planet (175 MB for Verdance) held the frame for a moment every two minutes.
var _snap_buf := RID()        # the snapshot being read (or none)
var _slice_buf := RID()       # a slice at a time is copied here and read from here
var _slice_n := 0
var _snap_keep := RID()       # its buffer, made at the first autosave and kept till the world goes
var _snap_ranges := []        # [offset, size, into "raw" or "seen"] still to read
var snap_raw := []            # the slices read so far (joined on the saving thread: joined here,
var snap_seen := []           # growing one array to 175 MB copied it over and over: a 46 ms frame)

func snapshot_begin() -> void:
	snapshot_cancel()
	flush()
	var n: int = Defs.total_cells() * 4
	var sb: int = seen_bytes()
	# (kept between autosaves: making a buffer this size took most of the 13 ms this step cost)
	if not _snap_keep.is_valid():
		_snap_keep = rd.storage_buffer_create(n * 2 + sb)
	_snap_buf = _snap_keep
	rd.buffer_copy(world_buf, _snap_buf, 0, 0, n)
	rd.buffer_copy(aux_buf, _snap_buf, 0, n, n)
	rd.buffer_copy(seen_buf, _snap_buf, 0, n * 2, sb)
	rd.submit()
	rd.sync()
	snap_raw = []
	snap_seen = []
	_snap_ranges = [[0, n * 2, true], [n * 2, sb, false]]

## Reads the next slice of the snapshot (call with nothing in flight: right after `flush`); true once
## it's all read (snap_raw, snap_seen).
func snapshot_step(step: int) -> bool:
	if not _snap_buf.is_valid():
		return true
	flush()
	var left := step
	while left > 0 and not _snap_ranges.is_empty():
		var rg: Array = _snap_ranges[0]
		var sz: int = mini(left, int(rg[1]))
		var part := _read_slice(_snap_buf, int(rg[0]), sz)
		if bool(rg[2]):
			snap_raw.append(part)
		else:
			snap_seen.append(part)
		rg[0] = int(rg[0]) + sz
		rg[1] = int(rg[1]) - sz
		left -= sz
		if int(rg[1]) <= 0:
			_snap_ranges.pop_front()
	if _snap_ranges.is_empty():
		_snap_buf = RID()
		return true
	return false

## A slice of a big buffer, copied on the GPU into a small one and read from there: read straight out
## of the 175 MB world buffers every slice cost ~13 ms whatever its size; this way 4 MB takes ~1.5 ms.
func _read_slice(buf: RID, off: int, sz: int) -> PackedByteArray:
	flush()                   # (nothing may be in flight when this submits)
	if not _slice_buf.is_valid() or _slice_n < sz:
		if _slice_buf.is_valid():
			rd.free_rid(_slice_buf)
		_slice_buf = rd.storage_buffer_create(sz)
		_slice_n = sz
	rd.buffer_copy(buf, _slice_buf, off, 0, sz)
	rd.submit()
	rd.sync()
	return rd.buffer_get_data(_slice_buf, 0, sz)

func snapshot_busy() -> bool:
	return _snap_buf.is_valid()

func snapshot_cancel() -> void:
	_snap_buf = RID()
	_snap_ranges = []
	snap_raw = []
	snap_seen = []

## A saved world: both layers, then the seen map if the save has one (one from before it: none seen).
func write_world(data: PackedByteArray) -> void:
	flush()
	var n: int = Defs.total_cells() * 4
	rd.buffer_update(world_buf, 0, n, data.slice(0, n))
	rd.buffer_update(aux_buf, 0, n, data.slice(n, n * 2))
	if data.size() >= n * 2 + seen_bytes():
		rd.buffer_update(seen_buf, 0, seen_bytes(), data.slice(n * 2, n * 2 + seen_bytes()))
	else:
		rd.buffer_clear(seen_buf, 0, seen_bytes())

func cleanup() -> void:
	if rd == null:
		return
	flush()
	snapshot_cancel()
	if _snap_keep.is_valid():
		rd.free_rid(_snap_keep)
	_snap_keep = RID()
	if _slice_buf.is_valid():
		rd.free_rid(_slice_buf)
	_slice_buf = RID()
	_slice_n = 0
	rect_reqs.clear()
	rect_done.clear()
	for k in sets:
		if sets[k].is_valid() and rd.uniform_set_is_valid(sets[k]):
			rd.free_rid(sets[k])
	for nm in shaders:
		rd.free_rid(shaders[nm]["pipeline"])
		rd.free_rid(shaders[nm]["shader"])
	for b in [world_buf, aux_buf, sites_buf, params_buf, surf_buf, counts_buf, grid_buf, light_a, light_b, view_buf, rb_buf, shells_buf, nav_buf, seen_buf]:
		if b.is_valid():
			rd.free_rid(b)
	rd.free()
	rd = null
	# (so a fresh init() on another device, for a planet of another size, starts clean)
	sets = {}
	shaders = {}
	world_buf = RID(); aux_buf = RID(); sites_buf = RID(); params_buf = RID(); surf_buf = RID(); counts_buf = RID()
	grid_buf = RID(); light_a = RID(); light_b = RID(); view_buf = RID(); rb_buf = RID(); shells_buf = RID(); nav_buf = RID()
	grid = PackedByteArray()
	grid_off = 0
	light_off = 0
