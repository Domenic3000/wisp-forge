# Wisp Forge: Performance: making planets quickly, profiling, quality, no stalls

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Making a planet quickly
- `_make_world` times its steps (`gen_times`, printed by the test mode with `builds.plan_times` and the settle split).
  Verdance at 1.5x is made in about 3.7 s on the RTX 3070 laptop (12.3 s at the old size before this work).
- buildings.gd `_finish` only queues a blueprint (with the `rng.randi()` its roughening used, so layouts don't
  change); `finish_all` / `finish_start` + `finish_collect` finish every queued blueprint on WorkerThreadPool
  (`_finish_bp` through a helper copy of the planner per job, `_take_terrain`), results gathered in order.
- In the editor-build engine every call on an object (and every `bp.c[k]` read) goes through a shared lock: the hot
  loops (`_roughen_underground`, `_weather_ground_line`, `_stabilize_pass` with flat-array buckets, `_anchor_and_tidy`,
  `_place_chests`, BP.rect/rect_bg) work on a local copy of the cells and plain tables (`_kind`, `_span`, `_gmf`) and
  write it back once. Keep new per-cell code that way, or threads slow each other down tenfold.
- Settling (`gpu.settle`) covers only windows round each blueprint's loose matter (unanchored powder or liquid; none
  for a structure without any), with fewer plant and liquid passes than a game frame.
- Structures, vaults and the lair spacing scale with the planet's columns (per 8192); dungeons stay at `DUNGEONS` (4).

## Profiling, benchmarks, quality, stalls
- Profiler: `main.prof_add(section, usec)` anywhere; `prof` holds [average, recent peak, this frame, max since
  `prof_reset`, last frame]. GPU stages are timed with RenderingDevice timestamps in `gpu.step` (simulation, collision grid,
  light, picture). F3 shows the top sections; `main.hitch_us` is the longest frame of the game's own work (tests
  reset and read it). The test "frame time with no cap" turns vsync off and logs the breakdown. Foes are timed by
  part ("foes: think", "foes: creatures", "foes: <type>", "foes: moving", "foes: ecology"), drawing by overlay `_part`.
- The busy-scene benchmark (`_test_bench`, "bench"; the full run's LAST check, its fires and pits spoiled the checks
  after it; user, 21 Nov: the
  performance pass): 24 provoked foes, rain, a fireball every 20 frames, digging every frame, sand poured, vsync
  off, 600 frames; prints every frame over 50 ms with the parts over 3 ms, each part's worst, a histogram. Passes
  under 16.7 ms on average and 25 at the 95th percentile (27 ms average / 115 worst before; 7.6 / 14.7 after).
- Space is profiled too: `space: tick` (all of it) and its parts via `_pmark` ("galaxy", "near", "streaming",
  "rocks", "aliens and folk", "pirates", "skiff"), `space: drawing` / `drawing marks` / `drawing figures`. The
  space benchmark `_test_spacebench` ("spacebench"; in the full run after `_test_cargo`): a fight in the system's
  derelict, the outpost's deck, pirates among home's rocks with the cannon, the Starsail streaming sectors; 300
  frames each through `_bench_measure(n, each)` (vsync off; avg, p95, worst, the engine's drawing on the CPU,
  the GPU's drawing and simulation, a histogram, and every frame over 25 ms with the parts over 1.5 ms in it;
  `_bench_line`); about 2.5 ms a frame in each on the RTX 3070 laptop (23 Nov). The skiff out there collides only
  with the rocks its whole path this tick could touch (`_rocks_near` over the sweep, `_solid_among` bound to
  them): checking every rock at every outline point of every sub-step cost 50 ms a tick under the Starsail.
- LOWER-END PCs (user, 23 Nov: "make sure it runs on lower end pc's with decent framerates"): setting "quality"
  is "auto" by default (also high/medium/low). main `quality()` is the level in use ("auto" -> `settings["auto_q"]`,
  starting "high"); `_auto_quality(delta)` (each `_process`, only in play, not travelling, not in tests unless
  `auto_test`, `_aq_wait` frames after a start or a journey): if the frames over `AUTO_WINDOW` (4 s) average
  slower than `AUTO_SLOW_MS` (20 ms, under 50 fps) it steps down a level (high, medium, low), remembered in
  settings.json, with a toast. Choosing Auto again starts from high. `fx_budget()` (1 / 0.6 / 0.35, kept in
  `_fxb`): vfx.gd `spawn` keeps that share of the small particles (DOT, STREAK, SMOKE, SHARD, CHUNK; never the
  halos, rings, runes, bolts, beams) and caps at MAX x budget; weather.gd `emit` and main `_particle` too
  (drawing particles one rect at a time is the dearest drawing on a slow CPU, ~0.8 us each). Low quality also has
  bigger pixels and fewer simulation and light passes (`gpu.apply_quality`). The planet benchmark runs the busy
  scene again at high and at low (`_bench_measure`) and checks Auto quality steps down at 33 fps and stays at
  60 (23 Nov on the 3070 laptop: 7.5 ms high, 5.8 ms low; the game's own work ~3.8 ms, effects drawing ~1.7,
  particles ~1.4, the read-back ~1.6, the GPU only ~1 ms: a weaker CPU matters more than a weaker GPU). Still
  read back and uploaded again every frame: the picture (`view_buf`), because the simulation runs on a local
  RenderingDevice; moving it onto Godot's own device (roadmap step 10, for mobile) removes that.
- Hot paths: `box_solid` / `box_count` read the collision grid bytes straight from `gpu.grid` through a 64-entry
  table (`_solid_table`), falling back on `gsolid` only off the grid's edge (cell by cell through `gsolid` they
  took 55 ms a frame with 24 foes). Loops over many points (vfx particles, overlay particles) use
  `main.screen_xf()` (world_to_screen as one Transform2D) when `screen_xf_ok()` (not the unrolled view), and
  particles read the light straight from `gpu.light_at`. Chunks no longer stall (23 Nov): `detect` asks
  (`_ask`: `gpu.request_rect` with the anchor of the moment) and `_poll` lifts the piece out a frame or two later
  when the read is back (`_pend`; R carries the anchor at R[6], the screen mapping at R[7]/R[8]; `_clear`'s stamp
  uses that anchor); a tree bigger than its block asks again for twice the block.
- No stalls (user, 22 Nov: "a small hitch when starting a new game"; a performance pass): `gpu.read_rect` waits
  for the frame in flight (flush + its own submit and sync), so code that reads now and then while you play
  asks instead: `gpu.request_rect(c0, r0, w, h)` goes out with the next frame's commands (dispatched at the end
  of `step`, read in its `flush`) and `take_rect(id)` has it a frame or two later. Spawning uses it
  (`_spawn_req`, `_spawn_ask`, `_spawn_finish`: the first creature a few seconds into a new game stalled the
  frame and then searched the block cell by cell; now open runs per column, `run`). The AUTOSAVE (every 7200
  ticks) no longer reads the planet back in one go (about 175 MB at ~0.75 GB/s: a quarter-second freeze every
  two minutes): `_autosave_begin` copies the world, back layer and seen map into a kept buffer on the GPU
  (`gpu.snapshot_begin`, `_snap_keep`, made at the first autosave), `_autosave_step` (right after the frame's
  flush) reads 8 MB a frame (`snapshot_step`), and `_write_world_parts` joins the slices and writes on a thread.
  Reading a slice straight out of a big buffer costs ~13 ms a call whatever its size (Godot's path for a buffer
  that size); `gpu._read_slice` copies it on the GPU into a small buffer (`_slice_buf`) and reads that: 4 MB in
  ~1.5 ms. `read_world_async` (leaving a planet) uses it too.
  A save of the world as it is now (`save_world`, `save_world_async`) cancels one on its way. Music is read on a
  worker thread (audio.gd `_read_music`, taken in by `_take_music`). Off-screen foes aren't drawn (overlay: most
  of them wait 160+ cells off), and `_sprite` reads the light once. Test: `_test_newgame` ("newgame": the title,
  Play on an empty slot with a grown seed (`test_seed`), 900 frames traced with creatures coming by, then an
  autosave; not in the full run).
- Readback: `gpu.step` copies counts, light, the picture and the collision grids into one buffer (`rb_buf`, offsets
  `rb_off`) read in one call; `grid` is that whole buffer, so index it from `grid_off` (grids) and `light_off`
  (light), never from 0.
- Boss art is grown on a worker thread (overlay `_boss_art`, `_art_jobs`): a foe isn't drawn until its frames are
  ready. (Grown on the main thread the first time the planet's guardians and wardens were drawn, the first frame
  took 750 ms: the user's start-up hitch.) The tests print `[startup]` frames over 40 ms (`_trace_frames`), and
  F3 shows the overlay's parts ("draw: foes", "draw: mages"...).
