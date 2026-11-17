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
var wait_us := 0         # how long the last collect waited for the GPU
var topple_iters := 2    # falling-block passes per frame
var blur_passes := 2     # light blur passes
var sun_step := 2.0      # sunlight march step (cells)
const NPARAM := 128      # vec4 slots in the params buffer

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
var grid_buf: RID
var light_a: RID
var light_b: RID
var view_buf: RID

var VW := 480
var VH := 270
var LW := 121
var LH := 69

var params := PackedFloat32Array()
var surface := PackedFloat32Array()   # 8 floats per shell-0 column
var grid := PackedByteArray()
var light := PackedFloat32Array()
var counts := PackedInt32Array()
var view_img: Image
var frame := 0

func init() -> bool:
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
	surf_buf = rd.storage_buffer_create(Defs.SH_N[0] * 32)
	counts_buf = rd.storage_buffer_create(64 * MAXP * 4)   # 64 counters per player
	var prefix: String = Defs.glsl_prefix()
	for nm in ["surface", "gen", "react", "move", "boundary", "brush", "grid", "light", "blur", "render", "support", "topple", "stamp", "plants"]:
		if not _compile(nm, prefix):
			return false
	_make_static_sets()
	resize(VW, VH)
	return true

func _load_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()

func _compile(nm: String, prefix: String) -> bool:
	var body := _load_text("res://shaders/%s.comp" % nm)
	if body == "":
		error_text = "Missing shader file: shaders/%s.comp" % nm
		return false
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
		return false
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
	LW = int(ceil(float(VW) / LS)) + 1
	LH = int(ceil(float(VH) / LS)) + 1
	GS = clampi(int(ceil((maxi(w, h) + 96) / 4.0)) * 4, 384, 1024)
	for key in ["light", "blur_h", "blur_v", "render", "grid"]:
		if sets.has(key) and sets[key].is_valid() and rd.uniform_set_is_valid(sets[key]):
			rd.free_rid(sets[key])
	for b in [light_a, light_b, view_buf, grid_buf]:
		if b.is_valid():
			rd.free_rid(b)
	grid_buf = rd.storage_buffer_create(GS * GS * MAXP)    # one collision grid per player
	grid = PackedByteArray()
	sets["grid"] = _mkset("grid", [[0, world_buf], [1, params_buf], [7, grid_buf], [3, counts_buf], [8, aux_buf]])
	light_a = rd.storage_buffer_create(LW * LH * 16)
	light_b = rd.storage_buffer_create(LW * LH * 16)
	view_buf = rd.storage_buffer_create(VW * VH * 4)
	sets["light"] = _mkset("light", [[0, world_buf], [1, params_buf], [2, surf_buf], [4, light_a], [8, aux_buf]])
	sets["blur_h"] = _mkset("blur", [[4, light_a], [5, light_b]])
	sets["blur_v"] = _mkset("blur", [[4, light_b], [5, light_a]])
	sets["render"] = _mkset("render", [[0, world_buf], [1, params_buf], [2, surf_buf], [4, light_a], [6, view_buf], [8, aux_buf]])

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
	for b in bl.size():
		var bd: Dictionary = Defs.BIOMES[bl[b]]
		setp(8 + 2 * b, Vector4(bd["off"], bd["amp"], bd["top"], bd["flags"]))
		setp(9 + 2 * b, Vector4(bd["sub"], bd["topD"], bd["subD"], int(bd["ug"]) + int(bd["flora"]) * 16))
	setp(120, Vector4(0, 0, 0, 0))
	_upload_params()
	var cl := rd.compute_list_begin()
	_dispatch(cl, "surface", "surface", [Defs.SH_N[0]], [], groups(Defs.SH_N[0], 64), 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	surface = rd.buffer_get_data(surf_buf).to_float32_array()

## Generates every cell, in row bands so no single GPU job runs too long.
func generate(spawn_angle: float, boss: Vector4, sites: Array) -> void:
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
	setp(120, boss)
	setp(121, Vector4(spawn_angle, 0, 0, 0))
	_upload_params()
	for s in 4:
		var y0: int = Defs.SH_Y0[s]
		var y1: int = Defs.SH_Y0[s + 1]
		var n: int = Defs.SH_N[s]
		var band := 48 if s == 0 else 96
		var y := y0
		while y < y1:
			var ye := mini(y + band, y1)
			var cl := rd.compute_list_begin()
			_dispatch(cl, "gen", "gen", [s, y, ye], [], groups(n, 16), groups(ye - y, 16))
			rd.compute_list_end()
			rd.submit()
			rd.sync()
			y = ye

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
		_dispatch_set(cl, "stamp", uset, [st["x0"], st["y0"], st["w"], st["h"], offs[k], seed + k], groups(st["w"], 16), groups(st["h"], 16))
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	rd.free_rid(uset)
	rd.free_rid(buf)

## Runs the simulation (no rain, no rendering) around the given points so freshly stamped
## structures settle: whatever the generator (or a ruin's decay) left unsupported falls now.
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
	for f in frames:
		frame += 1
		var cl := rd.compute_list_begin()
		_sim_passes(cl, wins, -1, 0, 0)
		rd.compute_list_end()
		rd.submit()
		rd.sync()

func _dispatch_set(cl: int, shader_name: String, uset: RID, ints: Array, gx: int, gy: int) -> void:
	var pcb := _pc(ints, [])
	rd.compute_list_bind_compute_pipeline(cl, shaders[shader_name]["pipeline"])
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	rd.compute_list_set_push_constant(cl, pcb, pcb.size())
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_add_barrier(cl)

func surf_at(angle: float) -> Vector4:
	var n: int = Defs.SH_N[0]
	var a := fposmod(angle, TAU)
	var i := mini(int(a / TAU * n), n - 1)
	return Vector4(surface[i * 8], surface[i * 8 + 1], surface[i * 8 + 2], surface[i * 8 + 3])

func surf_b(angle: float) -> Vector4:
	var n: int = Defs.SH_N[0]
	var a := fposmod(angle, TAU)
	var i := mini(int(a / TAU * n), n - 1)
	return Vector4(surface[i * 8 + 4], surface[i * 8 + 5], surface[i * 8 + 6], surface[i * 8 + 7])

# ------------------------------------------------------------- simulation --
## The simulated window: rows y0..y1 and an angular span around the camera.
func _window(center: Vector2, half := -1.0) -> Array:
	var rc := center.length()
	if half < 0.0:
		half = sqrt(float(VW * VW + VH * VH)) * 0.5 + 56.0
	var y0 := clampi(int(Defs.R_TOP - (rc + half)), 0, Defs.ROWS)
	var y1 := clampi(int(Defs.R_TOP - (rc - half)) + 1, 0, Defs.ROWS)
	var rmin := maxf(rc - half, Defs.R_IN)
	var dth := half / rmin
	var thc := atan2(center.y, center.x)
	var out := []
	for s in 4:
		var sy0 := maxi(y0, Defs.SH_Y0[s])
		var sy1 := mini(y1, Defs.SH_Y0[s + 1])
		if sy0 >= sy1:
			continue
		var n: int = Defs.SH_N[s]
		var x0 := 0
		var count := n
		if dth * 2.0 < TAU:
			x0 = int(floor((thc - dth) / TAU * n))
			count = int(ceil(2.0 * dth / TAU * n)) + 2
			count += count % 2
			count = mini(count, n)
		out.append({"s": s, "y0": sy0, "y1": sy1, "x0": x0, "count": count})
	return out

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
	rd.buffer_clear(counts_buf, 0, 64 * MAXP * 4)
	var win := _windows(sim_centers)
	var cl := rd.compute_list_begin()
	if with_brushes:
		for w in win:
			_dispatch(cl, "brush", "brush", [w.s, w.y0, w.y1, w.x0, w.count, frame + 1], [], groups(w.count, 16), groups(w.y1 - w.y0, 16))
	var rain_row := clampi(int(Defs.R_TOP - params[121 * 4 + 2]), 0, Defs.ROWS - 1)
	var rain_mat := int(params[3 * 4 + 1])
	for k in sim_steps:
		frame += 1
		_sim_passes(cl, win, rain_row, rain_mat, CREAK_FRAMES)
	if not sim_only:
		for gs in mini(grid_frames.size(), MAXP):
			var gf: Array = grid_frames[gs]
			var gc: Vector2 = gf[0]
			_dispatch(cl, "grid", "grid", [GS, gs], [gc.x, gc.y, gf[1]], groups(GS / 4, 16), groups(GS, 16))
		_dispatch(cl, "light", "light", [LW, LH, LS], [], groups(LW, 16), groups(LH, 16))
		for k in blur_passes:
			_dispatch(cl, "blur", "blur_h", [LW, LH, 1], [], groups(LW, 16), groups(LH, 16))
			_dispatch(cl, "blur", "blur_v", [LW, LH, 0], [], groups(LW, 16), groups(LH, 16))
		_dispatch(cl, "render", "render", [VW, VH, LW, LH], [], groups(VW, 16), groups(VH, 16))
	rd.compute_list_end()
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
	pending = false
	counts = rd.buffer_get_data(counts_buf).to_int32_array()
	grid = rd.buffer_get_data(grid_buf, 0, GS * GS * clampi(sub_frames.size(), 1, MAXP))   # only the slots in use
	light = rd.buffer_get_data(light_a).to_float32_array()
	var vb := rd.buffer_get_data(view_buf)
	view_img = Image.create_from_data(VW, VH, false, Image.FORMAT_RGBA8, vb)
	fresh = true

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
		_dispatch(cl, "react", "react", [w.s, w.y0, w.y1, w.x0, w.count, frame, rain_row, rain_mat], [], groups(w.count, 16), groups(w.y1 - w.y0, 16))
	# background plants: several passes, so a cut tree knows it is cut within a few frames
	for it in plant_iters:
		for w in win:
			_dispatch(cl, "plants", "plants", [w.s, w.y0, w.y1, w.x0, w.count, frame * plant_iters + it], [], groups(w.count, 16), groups(w.y1 - w.y0, 16))
	for it in support_iters:
		for w in win:
			_dispatch(cl, "support", "support", [w.s, w.y0, w.y1, w.x0, w.count, frame], [], groups(w.count, 16), groups(w.y1 - w.y0, 16))
	for it in topple_iters:
		for w in win:
			_dispatch(cl, "topple", "topple", [w.s, w.y0, w.y1, w.x0, w.count, frame * 2 + it, creak * topple_iters], [], groups(w.count, 64), 1)
	var offs := [[0, 0], [1, 1], [1, 0], [0, 1]]
	for pass_i in 2 + flow_passes:
		var full := pass_i < 2
		var o: Array = offs[(frame * 2 + pass_i) % 4]
		for w in win:
			var s: int = w.s
			var ybase: int = Defs.SH_Y0[s] + ((w.y0 - Defs.SH_Y0[s]) / 2) * 2
			var ylim: int = mini(w.y1 + 1, Defs.SH_Y0[s + 1])
			var brows: int = (ylim - ybase) / 2 + 1
			_dispatch(cl, "move", "move", [s, ybase, ylim, w.x0, w.count, frame * 8 + pass_i, o[0], o[1]], [0.0 if full else 1.0], groups(w.count / 2 + 1, 16), groups(brows, 16))
		if full:
			for w in win:
				var s2: int = w.s
				if s2 >= 3:
					continue
				var seam: int = Defs.SH_Y0[s2 + 1]
				if w.y0 <= seam - 1 and w.y1 >= seam:
					var c2: int = w.count / 2 + 2
					_dispatch(cl, "boundary", "boundary", [s2, int(floor(w.x0 / 2.0)), c2, 0, frame * 8 + pass_i], [], groups(c2, 64), 1)

func grid_type(slot: int, i: int, j: int) -> int:
	var k := slot * GS * GS + j * GS + i
	if i < 0 or j < 0 or i >= GS or j >= GS or k >= grid.size():
		return 0
	return grid[k] & 0x3F

## what's built in the background of a grid cell: 1 furniture (or a torch), 2 a back wall, 0 nothing;
## -1 outside the grid
func grid_bg(slot: int, i: int, j: int) -> int:
	var k := slot * GS * GS + j * GS + i
	if i < 0 or j < 0 or i >= GS or j >= GS or k >= grid.size():
		return -1
	return grid[k] >> 6

func light_at(px: Vector2) -> Color:
	var i := clampi(int(px.x / LS), 0, LW - 1)
	var j := clampi(int(px.y / LS), 0, LH - 1)
	var k := (j * LW + i) * 4
	if k + 2 >= light.size():
		return Color.WHITE
	return Color(minf(sqrt(maxf(light[k], 0.0) + 0.008), 1.3), minf(sqrt(maxf(light[k + 1], 0.0) + 0.008), 1.3), minf(sqrt(maxf(light[k + 2], 0.0) + 0.008), 1.3))

## A w x h block of shell-0 cells (column c0.., row r0..; columns wrap around the planet), both
## layers: {"fg": PackedInt32Array, "bg": PackedInt32Array}, row by row. For a one-off look (picking
## up a piece of furniture, checking a bed): it waits for the GPU.
func read_rect(c0: int, r0: int, w: int, h: int) -> Dictionary:
	flush()
	var n0: int = Defs.SH_N[0]
	var fg := PackedInt32Array()
	var bg := PackedInt32Array()
	fg.resize(w * h)
	bg.resize(w * h)
	for j in h:
		var row := r0 + j
		if row < 0 or row >= Defs.SH_Y0[1]:
			continue
		var i := 0
		while i < w:
			var col := posmod(c0 + i, n0)
			var run := mini(w - i, n0 - col)          # up to the seam, then around
			var off: int = (Defs.SH_OFF[0] + (row - Defs.SH_Y0[0]) * n0 + col) * 4
			var fa := rd.buffer_get_data(world_buf, off, run * 4).to_int32_array()
			var ba := rd.buffer_get_data(aux_buf, off, run * 4).to_int32_array()
			for q in run:
				fg[j * w + i + q] = fa[q]
				bg[j * w + i + q] = ba[q]
			i += run
	return {"fg": fg, "bg": bg}

## Both layers, foreground cells first then the background layer.
func read_world() -> PackedByteArray:
	flush()
	var out := rd.buffer_get_data(world_buf)
	out.append_array(rd.buffer_get_data(aux_buf))
	return out

func write_world(data: PackedByteArray) -> void:
	flush()
	var n: int = Defs.total_cells() * 4
	rd.buffer_update(world_buf, 0, n, data.slice(0, n))
	rd.buffer_update(aux_buf, 0, n, data.slice(n, n * 2))

func cleanup() -> void:
	if rd == null:
		return
	flush()
	for k in sets:
		if sets[k].is_valid() and rd.uniform_set_is_valid(sets[k]):
			rd.free_rid(sets[k])
	for nm in shaders:
		rd.free_rid(shaders[nm]["pipeline"])
		rd.free_rid(shaders[nm]["shader"])
	for b in [world_buf, aux_buf, sites_buf, params_buf, surf_buf, counts_buf, grid_buf, light_a, light_b, view_buf]:
		if b.is_valid():
			rd.free_rid(b)
	rd.free()
	rd = null
