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
- Test mode quits by itself after 22 minutes (a full run takes about 18), so a broken run never leaves the game open;
  `scripts/watchdog.gd` (an autoload ahead of Defs, kept tiny) also quits a `--test` run whose main scene never came
  up (a parse error in main.gd used to leave a blank window), whose main.gd `_ready` stopped before `booted` (a
  script it preloads failed to compile: 25 s), or that passes 23 minutes. tests.gd is loaded at run
  time (not preloaded), so a parse error in it quits the game instead of leaving a blank window. `Check scripts.bat`
  stops at the first error per file (the expected Defs one), so it can't catch later parse errors in tests.gd:
  watch for a local that reuses a name already declared in the same function (lambdas included).
- Running one test section: a non-empty `saves/test_only.txt` naming it ("climb", "nav", "guardians", "wardens", "biomes",
  "worlds", "creatures", "ecology", "fog", "start", "recipes", "sky", "gear", "towns", "vfx", "ui", "speech", "bench", "stairs", "workshops", "crafting", "harvest", "hand", "audio", "inworld", "galaxy", "remove", "spawns", "newgame", "indoors", "backdrop", "wrecks", "pirates", "outposts", "stations", "fuel", "ships" (also "shipyard" or "pocket"), "cargo", "voidlife", "spacebench", "quest", "abyss", "giant", "pursuit", "cores", "stampdiag" or "mines": a print of each mine the soundness pass cut, with where) runs just that
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
