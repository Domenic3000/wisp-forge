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
  "worlds", "creatures", "ecology", "fog", "start", "recipes", "sky", "gear", "towns", "vfx", "ui", "speech", "bench", "stairs", "workshops", "crafting", "harvest", "hand", "galaxy", "remove", "spawns", "newgame", "indoors", "backdrop", "wrecks", "pirates", "outposts", "cabin", "stations", "fuel", "hull", "shipyard", "cargo", "voidlife", "spacebench", "quest", "abyss", "giant", "pursuit", "cores", "stampdiag" or "mines": a print of each mine the soundness pass cut, with where) runs just that
  section after the planet is made (25-50 s; "guardians" also prints a `[guardian]` trace every 15 frames); empty runs
  everything. Leave it empty when done. A section that can run alone is its own function (`_test_climb`,
  `_test_guardians`) called from `run()` in its usual place.
- Checks that fail now and then in the full run but not alone (22 Nov): the wild-life checks, the felled tree
  (it lies whole but the wood counted round it can drop just past its bar), digging a pit (prints each hurt
  with what fell). A test that sets something up in the air takes it away again (`_test_indoors` clears its
  slab and house).
- The wild-life checks (`_test_creatures`, `_test_ecology`) are set up near `start_pos` (where you arrived), in clear
  weather (rain off, `weather_timer` held), as when run alone. The skiff-travel check prints `[travel] a N ms
  frame ...` for any frame over 150 ms (the game's process, drawing, GPU wait).
