# Wisp Forge: Climate, weather and sky events

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Settlement and climate per kind
- Settlement: `Defs.CLIMATES[kind]` "settle" scales buildings.gd's structure count (26 per 8192 columns x settle:
  Verdance 0.5, a "realm" world of kingdoms 1.35), "towns" multiplies town and castle weights in `_try_place` (and
  gives a realm towns in biomes that had none), "ruin" shifts how many lie in ruins. `Defs.climate(pl)` fills every
  key (buildings `_clim`, main `clim`). Planet kinds: `PLANET_ORDER` (volcanic, ocean, desert, marsh, frozen,
  wild, realm); the classic five are temperate, volcanic, ocean, desert, marsh.
- Climate per kind (`CLIMATES`): "storm" (how often it rains, lightning), "wind" (main `wind`, gusting with the
  storm, turning with each spell of weather; pushes you while `exposed`, i.e. `_open_sky`: nothing solid 6-72
  cells over you, above the ground), "heat" (volcanic: the open air hurts 0.012 a tick without the Heat Ward or the
  Cinderheart), "freeze" (frozen: P.p[125].x, react.comp ices open water over from the top near the surface),
  "fog" (marsh: P.p[125].w, clouds.comp `groundFog` in the lowlands), "dust" (desert: dust storms in clear-weather
  biomes), "wild" (wild: creatures spawn more often). `_update_climate` blows snow (a blizzard), sand or embers
  across the view as particles. Prism Crystal is rarer (gen.comp thresholds, chest loot), and so are draughts in
  chests (0.1 + rare x 0.3).

## Weather you can tell apart (scripts/weather.gd; user, 22 Nov: "a hail storm that looked the same as rain ... weather patterns need distinct art")
- main `weather` (a Node2D in `pix` after vfx): its own particles in packed arrays, whole game pixels, lit by
  `gpu.light_at` (embers unlit), each kind with its own look and landing: RAIN thin slanting streaks + SPLASH,
  HAIL 2-3 px stones (white core, pale-blue edge, dark rim) that bounce twice (CHIP), then lie melting, SNOW
  swaying dots and crosses that rest a moment, ASH dark tumbling flakes, EMBER flickering sparks rising, DUST
  streaks along the wind. `emit(kind, n, br, bd, wind)` brings them in at the top edge (and the windward side);
  `_hit` steps a cell at a time against the collision grid (solid, powder or liquid), so a roof keeps them off.
  `CAP` per kind, `stats` (hail_bounces, rain_splashes, landed) for the tests.
- main `_weather_fx` (from `_update_climate`, near the surface only, not in space or on the map) says what
  falls: the biome's "weather" while `sky_rain` is up (the GPU's rain, snow and ash cells still fall too:
  real matter), a blizzard in wind, dust storms, embers on a hot world, the sandstorm and hail events.
  A hail storm drops NO rain cells (P.p[3].x 0: render.comp draws a falling drop pale, just like a hailstone),
  only weather.gd's stones, with a cold haze (`sky_tint`); a sting cracks a stone on your hat.
- Test: in `_test_sky` (hail: stones bounced and lay, no rain cells; rain: splashes; `sky_rain.png`).

## Sky events (main.gd `_update_sky_events`; user, 20 Nov: "weather and sky events for each kind of planet")
- `Defs.SKY_EVENTS`: meteors, eruption, squall, sandstorm, wisps, aurora, hail, bloodmoon, fireworks, each with a
  weight per planet kind ("kinds"), "when" (night/day/any), "dur" and a message. Every `SKY_EVENT_EVERY` ticks a
  `SKY_EVENT_CHANCE` roll picks one (`_pick_sky_event`; never in test mode); `start_sky_event(id)` /
  `end_sky_event()` (also in `_make_world`); `sky_ramp()` fades it in and out over 5 s; `sky_level(id)` is the
  GPU's share (P.p[125].y aurora, .z blood moon: render.comp `skyColor` draws the aurora's curtains by screen row
  and reddens the night and the moon). State: `sky_ev`, `sky_t`, `sky_dur`, `_sky_next` (ticks to its next
  meteor, bomb, strike, rocket, hail sting), `sky_wind` (added to the climate's wind target), `sky_tint` (overlay
  draws it over the view), `sky_fx` (overlay `_draw_sky`: "streak" shooting stars, "bolt" lightning, "rocket"),
  `sky_wisps`, `sky_vent`, `sky_stats` (counts for the tests).
- Doings: meteors (streaks; `meteor_fall(cells)`: PROJ "meteor" from high up, `_meteorite`: a blast, fire, a lump
  of MAGMAROCK round a few cells of STARIRON at the crater's bottom (so it rests on ground and no chunk carries it off; about 4: asteroids stay the real source), hurts anyone close), eruption (`_eruption_vent`: the highest of a few spots
  110-220 cells off; smoke, glow, rumbles, PROJ "lavabomb" (splat lava) every 22-45 ticks), squall (gale, rain,
  `lightning_strike(cells)`: a drawn bolt, fire, hurts within 12), sandstorm (gale, haze, blown sand), wisps (5
  drifting lights, shy of you; touching one gives 4 Wisp Ore and 30 mana), aurora (mana regen x2 under the open
  sky), hail (weather.gd stones; a sting every 35-70 ticks in the open), bloodmoon (`spawn_mult` 2.5, up to 12 foes),
  fireworks (rockets that burst into coloured particles). The HUD's weather shows the event, then " · <hazard>!".
  Test: `_test_sky` ("sky").
