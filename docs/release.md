# Wisp Forge: Building the game to share, music, saves

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Building the game to share (Build game.bat; user, 22 Nov: "build the game into an easily distributable .exe")
- `Build game.bat` (repo root): finds the console Godot in engine/, works out the template version from
  `--version` (4.7.2.stable -> templates "4.7.2.stable", release "4.7.2-stable"), and if Godot's export templates
  aren't in %APPDATA%\Godot\export_templates\<version> asks (Y/N, No after 30 s) before downloading them (~1 GB,
  from the godotengine GitHub release; unpacked with tar). Then `--headless --export-release "Windows Desktop"`
  (game/export_presets.cfg: one .exe with the pack embedded, `*.comp` shaders included as plain files, audio/
  left out) into build\Wisp Forge\, the music copied beside it into "music", a README, and build\Wisp Forge.zip.
  Its steps go to build\build_log.txt ("BUILD OK" at the end). build/ is git-ignored.
- An exported game (`OS.has_feature("template")`): saves in %APPDATA%\Wisp Forge\saves (`_real_save_dir`; never
  beside the .exe), music from the "music" folder beside the .exe (audio.gd `music_dir`). A built game's own test
  run (`"Wisp Forge.exe" -- --test`, e.g. with saves\test_only.txt "newgame" beside it) reports into a saves
  folder beside the .exe instead (run Build game.bat again afterwards: it wipes build\Wisp Forge first). Checked
  22 Nov: the built game starts, compiles its shaders, plays its music, makes and saves a new world.

## Music (scripts/audio.gd)
- Tracks in game/audio/music/ by name: mood (surface_day, surface_night, underground, deep, boss, space, title) or
  kind + "_" + mood (`track_key`: "volcanic_surface_day.mp3"); `_pick` tries this planet kind's own, then the common
  one, then the fallbacks. A new kind of planet counts as a new mood (crossfade). The user makes tracks with Suno.

## Saves and window
- Save slots: saves/slot_1..3 (`SLOTS`, `slot`, `_save_dir`), each with its progress.json and worlds; the title
  lists them (title_screen.gd `refresh_slots`: continue a saved one, start in an empty one, Delete twice);
  `quit_to_title` (Esc menu) saves and returns there. Saves from before slots move into slot 1
  (`_migrate_old_saves`). settings.json stays in saves/; the test mode uses saves/test.
- Window: setting "window" (windowed, fullscreen, exclusive), F11 / Alt+Enter switch; the test mode stays windowed.
