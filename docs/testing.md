# Wisp Forge: The test mode

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## The test mode
- Where the checks live (25 Nov): `scripts/tests.gd` holds `run()` (it runs every section in order, and many
  checks are written straight into it); the sections and helpers are in `scripts/tests/`, a chain of scripts each
  extending the one before (`base.gd`: shared state and helpers; then `creatures`, `world`, `building`, `towns`,
  `player`, `space`, `exotic`, `perf`), so every check is still a method of the one test object. A new section
  goes in the file for its area; a file may only call functions in itself or files before it in the chain (an
  earlier file can't see a later one's functions). `Check scripts.bat` checks each of them.
- Test mode quits by itself after 27 minutes (a full run takes about 23; 26 Nov), so a broken run never leaves the game open;
  `scripts/watchdog.gd` (an autoload ahead of Defs, kept tiny) also quits a `--test` run whose main scene never came
  up (a parse error in main.gd used to leave a blank window), whose main.gd `_ready` stopped before `booted` (a
  script it preloads failed to compile: 25 s), or that passes 28 minutes. tests.gd is loaded at run
  time (not preloaded), so a parse error in it quits the game instead of leaving a blank window. `Check scripts.bat`
  stops at the first error per file (the expected Defs one), so it can't catch later parse errors in tests.gd:
  watch for a local that reuses a name already declared in the same function (lambdas included).
- Running one test section: a non-empty `saves/test_only.txt` naming it ("climb", "nav", "guardians", "hearts", "newbiomes", "wardens", "biomes",
  "worlds", "creatures", "ecology", "fog", "start", "recipes", "sky", "gear", "towns", "vfx", "ui", "speech", "bench", "stairs", "workshops", "crafting", "harvest", "hand", "audio", "inworld", "galaxy", "remove", "spawns", "newgame", "indoors", "backdrop", "wrecks", "pirates", "outposts", "stations", "fuel", "ships" (also "shipyard" or "pocket"), "cargo", "voidlife", "spacebench", "quest", "abyss", "giant", "star", "void", "lights", "guards", "pursuit", "cores", "fire", "loop", "terrain4", "stampdiag" or "mines": a print of each mine the soundness pass cut, with where) runs just that
  section after the planet is made (25-50 s; "guardians" also prints a `[guardian]` trace every 15 frames); empty runs
  everything. Leave it empty when done. A section that can run alone is its own function (`_test_climb`,
  `_test_guardians`) called from `run()` in its usual place.
- Checks that failed now and then in the full run but not alone (22 Nov), and what was done (26 Nov, user: "fix
  the three flaky tests"): the felled tree lost too much wood as chips on landing (chunks.gd `_splinter` now knocks
  off at most 1/40 of a tree's pixels, 1/6 of other pieces'); digging a pit was hit by a tree whose roots it
  cut (`_clear_stretch(..., trees)` now also refuses a stretch with tree wood, roots or leaves in the back layer
  within `trees` columns); the frog's hops are watched up to 720 frames (it sits and croaks between hops at random);
  the deer in the storm is watched 240 frames, 120 cells from you (at 220 it was outside the simulated
  neighbourhood, 192 cells each way, and stood frozen: `main.in_grid`); every creature gets 260 frames for its first
  attack, and the report names any that failed ("(!) failed: ..."). Later the same day: the felled tree's wood is
  counted 320 columns either way and 40 rows down (a trunk rolled ~180 columns down a slope and counted as lost), and
  the hazards check's too-hard dig tries 110, 140, 170 and 200 cells down (a cave or soft ground at 110 had nothing
  hard to be blocked by). A test that sets something up in the air takes it away again (`_test_indoors` clears its
  slab and house).
- The wild-life checks (`_test_creatures`, `_test_ecology`) are set up near `start_pos` (where you arrived), in clear
  weather (rain off, `weather_timer` held), as when run alone. The skiff-travel check prints `[travel] a N ms
  frame ...` for any frame over 150 ms (the game's process, drawing, GPU wait).
- (25 Nov) The pocket check's first Wisp Recall cast failed once in a full run (the channel never started; the
  second cast worked) and passed alone: likely a knock from landing after `_go` breaking the channel. Run
  "pocket" alone before chasing it.
- (25 Nov) "trees stand when you come near" failed once in a full run: in the marsh one tree came down as a log
  (2668 -> 2616 plant cells). It runs early, before the building checks; not yet looked into.
- (25 Nov) The pirates check failed once in a full run on the scrap count round a beaten ship (1, wanting 2: how
  it breaks up is physics); it passed run alone.
- (27 Nov, after terrain 2 reshaped the test planet) In two full runs a group of fliers (skyray, stormkite,
  stormgull, flarewisp) and the glow worm rose 70-120 cells in "every biome and depth has creatures" (it wants under
  70) while still reaching you (nearest 1); run alone ("creatures") they rise about 10 and it passes. Something an
  earlier check leaves behind; not yet found. In one full run two villagers put on one spot moved 17 apart and then
  stood together 78 frames of 240 (wanting under 20); "towns" alone passes.
- (27 Nov) Terrain 2 made several checks trust the layout less: the build-mode wall, the furniture wall, the fog,
  the heart bosses, the workshops' slab (now never over a building: its embers burnt a village house's floor) and the
  wild-life creatures (set down over the ground at their own column, away from buildings) look for their spot first.
- (27 Nov, later) The furniture pick-up check failed in full runs (the table gone before it was picked up): the
  fire check, which ran just before it, burnt the table the build-mode check had set down. `_test_fire` now runs
  after the pick-up check, and it passed. The same full run failed four checks that passed run alone: the deer chased
  into a wall ("ecology": it rose 0, alone 4), Vulkhar through the slot ("pursuit": came 0, 208 from you), the
  skiff ramming rock ("pirates": 0 cells holed, alone 4), and, in the run before, open water icing over on a
  frozen world. Run them alone before chasing them.

- (27 Nov) Derelict stations' and outposts' halls are levels now (docs/space-places.md LEVELS), four or five times the
  cells: "stations" grows 4 (not 10) and "outposts" 3 (not 6), about 0.3-0.45 s each on the laptop (their `meta["ms"]`
  is in the report). What's reachable in a level is worked out room by room through its doors
  (`_level_rooms_reached`), not by flooding its cells (seconds a level). The door check turns `space.doors_for_aliens`
  off while it runs, so a woken alien by the door can't hold it open.

- (26 Nov) Village guards stand by in the test mode (towns.gd `test_guards` false: `_guard_target` finds nothing),
  so they don't spear the foes other checks set up near a village; `_test_guards` turns them on. A done request
  doesn't grow the village during `_test_requests` (`no_grow`). "foes appear out of sight" clears `quiet_until`
  first (an area an earlier check cleared stays quiet 90 s, and the later checks shifted that check into it).
- Terrain 4 (27 Nov): the test planet (world 0 of the classic system) is made on terrain 4 now, like every new world.
  Its layout changed, so "F opens a chest" takes any intact chest away from the deep places when none is near the
  ground (and says what it looked at when none is found); "trees stand" allows 2% of a biome's plant cells to go in
  200 frames (marsh and savanna lose ~1.2% as the weather and the wild go on; the old bug of trees falling apart was far
  more); Thalassa's swimmers are let go along 130 columns of open sea, all checked deep. Seen failing now and then on
  full runs: build-mode walls (also before), the solar flare's planet shadow (the orbits' timing).
