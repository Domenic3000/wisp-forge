# Wisp Forge: Building the game to share, music and sound, saves

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
- Tracks in game/audio/music/ by name: mood (surface_day, surface_night, village, underground, deep, boss, space,
  title, pocket, outpost, derelict), kind + "_" + mood ("volcanic_surface_day.mp3"), or "biome_" + biome + "_" + mood
  ("biome_desert_surface_day.mp3"); `track_key` files each under "mood", "kind:mood" or "biome:<b>:mood". `_list_for`
  tries the biome's list, the kind's, the common one, then `FALLBACK` (village -> surface_day, pocket ->
  surface_night, outpost -> space, derelict -> deep, ...). Only a different list changes the track (`_list`), so
  crossing into a biome with no music of its own keeps what's playing. The user makes tracks with Suno; the folder's
  README lists every moment, what exists, and prompts for the missing ones (26 Nov, user: "some areas dont have
  their own music").
- Where you are (`here`, worked out every 6 frames by `_place_now`): title, pocket, outpost, derelict (a station's
  or wreck's halls, `space.inst`), space, or surface / underground (40+) / deep (220+); under water (the head in a
  liquid), under the open sky (`exposed`), the biome, a living village round you, the sea near, a lit workshop near.

## Sound (scripts/audio.gd; the audio pass, 26 Nov, user: "some of the basic sound effects are left from the early versions")
- Three buses made at start (`_make_buses`): "WF Sound" (a reverb that eases toward the place's: dry under the open
  sky, ringing in caves and the deep, bright in a station's metal halls, soft and far-off in the pocket; then a
  low-pass), "WF Ambience" and "WF Music" (a low-pass each). Under water the low-passes close (`_muffle`).
- Ambience: twelve loops made on a worker thread at start (`_build_ambience`, its own random numbers; the low ones
  at 11025 Hz; each loop's end blended into its start, `_loop`): wind (gusting with a whistle), rain (hiss and
  patter), crickets (warm nights), the sea (a wave every five seconds), caves (rumble and drips with echoes), the deep
  (lava's slow blorps), under water (bubbles), space (a slow beating drone), a station's hum and metal groans, an
  outpost's hum and crowd murmur, the pocket's far bells, a workshop's fire. `_amb_targets` sets each one's loudness
  for where you are; they ease in and out, and a silent one stops. Loudness follows the sound setting.
- Effects are built from parts: `_band` (band-passed noise), `_drop` (a falling-pitch thump), `_fm` (bells and
  metal), `_voice` (a saw through two formants: grunts, groans, roars), `_grains` (crunch and crackle), `_creak`
  (stick-slip wood), `_bubbles`, `_late`, `_mixn`. Footsteps hear what's underfoot (`step(pos, h, vol, kind)`, a
  table from the materials' names: soft, stone, sand, snow, wood, metal; the pocket's isle soft, an outpost's and a
  station's halls metal). New: fizzle (it was played but never made), thunder with the lightning, dock, cannon,
  shield. Remade: jump, land, hurt, place, hit, foe_die, fire, water, splash, boom, blink, roar, mimic, creak,
  rumble, crack, coin, chest_open, forge, the doors, the UI.

## Crackling (26 Nov, user playtesting on another PC: "im getting crackling in the audio engine. the main menu when i
hover over options and during the game occasional snaps that sound like audio crackling")
- `_wav` rounds loud peaks off softly (`SOFT_KNEE` 0.7 bending toward `SOFT_CEIL` 0.97; boom, zap and the roar had
  been cut flat at the limit) and fades a one-shot's last 4 ms (`TAIL_FADE`) to silence; loops (`_loop`) keep
  their ends. The hover blip lost its burst of white noise.
- `play` takes a free player first (`VOICES` 16), and only cuts off the oldest when all are sounding.
- A hard limiter on the Master bus (`_make_buses`) so everything stacked never clips the output.
- project.godot `audio/driver/output_latency` 40 ms. On Windows this does nothing: Godot's WASAPI driver takes
  IAudioClient3 and clamps the period to the engine's own (10 ms here: min = max = 441 frames at 44100 Hz) with a
  buffer of one period; the laptop reports 10.7 ms. Kept for other platforms.
- What was left (26 Nov, on the user's desktop with a USB audio interface, 44100 Hz; the laptop doesn't crackle):
  the mix itself is clean (test "mixrec" records the Master bus to saves/mix.wav: 20 s of title music and wind,
  then effects; no clicks but the effects' own), so the crackle is delivery: Godot's one-period WASAPI buffer
  on a normal-priority thread, a known Godot 4 trouble with USB interfaces (godotengine/godot #75109). No project
  setting switches IAudioClient3 off; a real fix is a custom export template (WASAPI on plain IAudioClient).
  `Audio check.bat` (beside the built game on that PC) runs it with `--verbose --log-file audio_log.txt`.
- The fix being tried (26 Nov, user: "is it possible to do the real fix here?"): a 3-byte patch to Godot's
  Windows runtime so `audio_device_init` never takes IAudioClient3 (`using_audio_client_3 = !p_input` compiles
  to `mov eax,r12d; xor eax,1; mov [rsi+0x104],al`; `xor eax,1` (83 f0 01) becomes `xor eax,eax; nop`
  (31 c0 90), found by the unique bytes 44 89 e0 83 f0 01 88 86 04 01 00 00). That is the path Godot already
  falls back to; it keeps the 2024 buffer fix (#89283, in the shared writer loop). On the laptop the patched
  build passes its audio check with a 2090-frame buffer (47 ms) instead of 512 (10.7 ms). Test copy:
  build\Wisp Forge\Wisp Forge (audio fix).exe.
- IN EVERY BUILD (26 Nov, user: "that is better i think"): engine\windows_release_x86_64_wasapi.exe is Godot's
  4.7.2 windows_release_x86_64.exe with that patch (tools/wasapi_patch.py, 0 = Windows' own buffer: a 100 ms
  one was tried and didn't help further); game/export_presets.cfg's custom_template/release points at it
  (relative to game/), and Build game.bat stops with how to make it if it's missing. The engine folder isn't in
  git: on another machine, run the tool on the installed template once.
- What's left is the desktop's own (26 Nov, LatencyMon there): nvlddmkm.sys DPCs up to 1.5 ms, Wdf01000.sys (the
  USB interface's driver framework) the most DPC time, nearly all on CPU 1; NVIDIA "Prefer maximum performance"
  made it better. The onboard output, YouTube and other games are clean.
- Test "audio": no sample at the limit, every one-shot ends in silence, the limiter and the 16 players there.

## Saves and window
- Save slots: saves/slot_1..3 (`SLOTS`, `slot`, `_save_dir`), each with its progress.json and worlds; the title
  lists them (title_screen.gd `refresh_slots`: continue a saved one, start in an empty one, Delete twice);
  `quit_to_title` (Esc menu) saves and returns there. Saves from before slots move into slot 1
  (`_migrate_old_saves`). settings.json stays in saves/; the test mode uses saves/test.
- Window: setting "window" (windowed, fullscreen, exclusive), F11 / Alt+Enter switch; the test mode stays windowed.
