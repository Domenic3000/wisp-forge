# Wisp Forge: Rendering: the sky, the view, the map, fog and light

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Sky, background and the view
- Render: above `R_TOP` the sky is drawn unless the orbit band has something there (`orbitEmpty`).
- Into space without a seam (user, 22 Nov: "the retro pixel filter seems to end at the space border, and the
  transition to space is still jaring"): `space.backdrop()` is on while you're within 320 of `R_TOP` (or out
  there); then space.gd draws its stars and nebula (only those) UNDER the picture, P.p[122].w bit 8 tells
  render.comp, and the sky's alpha fades 1 -> 0 from `R_TOP - 40` to `R_TOP + 110` (Bayer-stippled under the
  retro filter), so the stars come through as the air thins. The retro filter is now a POST pass over
  everything (main `POST_SHADER` on `post_rect`, the last child of `pix`: Bayer dither + 5-bit colour on
  game-pixel blocks, setting "dither" off / subtle 0.35 / retro 1), so it covers space, sprites and the
  overlay alike. Test: `_test_backdrop` ("backdrop", pictures `bg_border_day/night.png`, `bg_high.png`,
  `bg_orbit.png`).
- The parallax background (render.comp `skyColor`; user, 22 Nov: "make the background look higher detail and
  fade into each other better"): far mountains (ridged noise at 0.12 of your speed, crests lit on the sun's
  side by their slope, rock strata, snow over a ragged snowline, a pale crest line), far hills (0.25) and near
  hills (0.5) with the tree line (each tree shaded by height and sun side, leaves speckled, pines in tiers,
  ragged crowns). Hills take the colour of the biome's top ground (`palColor` of P.p[8 + 2b].z) mixed with
  the haze; each layer is mottled in its own coordinates (so its detail drifts with it) and misted toward
  its foot where a nearer layer rises in front (`mist`, 26-40 rows), so layers fade into each other.
  A layer's biome (its trees' kinds, its land colour: `layerBiome`, `layerLand`) is read in the LAYER'S OWN
  coordinates (2 x uN for the near hills, 4 x uF for the far ones), never at the world column under the pixel:
  that slid under the layer as you walked, so trees changed kind or vanished at a biome border (user, 22 Nov:
  "parts that pop in and out"). The scale puts a border on the hills over the real one as you cross it.
- The view (user, 20 Nov: "switch from bent strips to world coordinates"): the close view is the world as it is
  (setting "view": "world", the default), turned so up points away from the planet's centre, a pixel always
  `zoom` world units, so nothing squeezes going up or down; the horizon curves a little. `_write_frame_params`
  locks the camera to a corner of a cell of the shell it's in and turns the view to that cell's column, so moving
  a cell moves the picture exactly a cell (no shimmer). `main.close_view()` (zoomed in, not out in space with the
  planet out of sight): sprites upright, snapped to whole SCREEN pixels (overlay `_snap`; user, 21 Nov: snapped
  to whole game pixels a standing foe hopped a cell against the ground as you walked); open doors are turned
  with the world under them (`_sprite(..., turn)`), so they lean with their house. `main.unrolled()` = close view AND the "unrolled" setting:
  the old strips (screenToWorld branch on P.p[122].w bit 1; `unroll_step`). P.p[122].w bit 2: past `R_SPACE` the
  picture is clear (out in space and on the map), so what's under it shows (space.gd's stars, the clear colour).
  The picture is drawn a CELL a pixel (bit 4, `cellPicToWorld`: picture row j = cell row y0 + j in its own shell's
  columns counted from the one under the camera; `main._cell_rows` fills P.p[ROWT + j] = (N, that column, how far
  into it the angle is) in doubles, once) and the view's shader (`main.VIEW_SHADER` on `view_rect`, uniforms set
  by `_show_pic` from the picture actually on screen) finds for every SCREEN pixel its world point, its cell and
  that cell's picture pixel: cells keep their true shape (6 or 7 screen pixels for 6.6), none drawn twice or
  dropped. (Sampling the world a unit a pixel did that wherever cells aren't exactly a unit wide: the surface
  shell's are up to 17% off at +-330 rows, and the doubled columns showed as bands that stayed put as you
  walked; the user saw them.) The picture is the screen plus a margin (`gpu.PW/PH/PMX/PMY`, P.p[123]); light,
  readback and chunk colours index it by `main.world_to_pic` / `screen_to_pic`. Below radius 900 (the curve
  bends the corners past the margin), on the map and in the unrolled setting it is drawn as before ("mode" 0).

## The map
- The map (M, `main.open_map`; state "map", the game waits): "planet" renders the planet zoomed out. Where it looks is a
  point, `map_ang` round the planet and `map_r` from its middle (the view's up always outward), at `map_z` cells a pixel
  easing to `map_zt` (28 Nov; user: "I cannot pan the map. it would be nice if i could smoothly zoom in and out and pan
  around on the world map"): a drag holds what you grabbed under the mouse (`_map_hold`), WASD move it, the wheel or +
  / - zoom smoothly about the cursor (`_map_zoom`, `_map_anchor`), from MAP_Z_MIN (1.5) out to `map_z_max()` (the whole
  planet with its band); past MAP_WHOLE_FROM of that the view is drawn in to the middle (`_map_r_lim`) and a drag turns
  the planet instead; H back to you (MAP_Z_START 6). Test: in `_test_minimap` (dragged, zoomed about the cursor, the
  whole planet, opened at 24 places and left alone it holds still); `scripts/map_view.gd` draws the markers (you, the party, home, the skiff) and, on Tab, "system": the round
  of planets laid out round their middle (`space.disc_texture`), the one you're on marked. The play camera never
  zooms out any more (zoom_levels[0] = 1); closing hides the picture until one from the play camera is back.

## Fog, lights and clouds
- Fog over the unseen underground (user, 21 Nov: "fog to underground areas the player has not illuminated yet ...
  soft fall off"): `shaders/inc/seen.comp`, binding 12, `gpu.seen_buf` (`seen_bytes()` = total cells / 2): a level
  0..16 per block of 2 x 2 cells as a 16-bit thermometer, two blocks a word (`seenWord`, `seenAt`, `markSeen` =
  one atomicOr, levels only go up). render.comp marks what's lit now (`visNow`: the light less a lightning flash,
  smoothstep 0.02..0.25; never from the map or space, P.p[122].w bit 2); light.comp puts how clear each light
  point is in the light's w (4 samples of the seen map, or what's lit now, times `fogUnder`: none in the top 5
  rows under the surface, all of it from 26 down), blurred with the light, so the edge falls off softly; render
  mixes in a drifting dark mist by 1 - w, over lava and glowing ore too. Sprites: `gpu.light_at(...).a`, overlay
  `_lit` darkens them to match and returns the fog as alpha (clear 0.12..0.47), so foes, creatures, villagers,
  sleep marks and carcasses fade out under the fog (user, 22 Nov: "I can see enemies under the fog of war");
  the mage, the skiff and glowing sprites stay opaque; chunks.gd takes no colour from a fogged spot. Saved in the world file as a block
  of its own after the cells (`SEEN_MAGIC`, compressed apart; `gpu.read_seen`/`write_seen`, `read_world_async`
  returns [cells, seen]; a world without it loads all unseen); cleared for a new planet (`generate_prepare`).
  (`read_world(true)` / `write_world` with the seen map appended are for the tests.) Test: `_test_fog` ("fog",
  picture `fog.png`).
- Point lights are given to light.comp in the PICTURE's pixels (`world_to_screen` + `PMX/PMY`): in the screen's
  they shone a margin up and left of where they were (since the picture got its margin), so underground the wisp
  lit the rock beside you.
- Clouds live in world space (`shaders/inc/clouds.comp`: `cloudLow` near the ground, `cloudHigh` the weather
  layer above the mountains; `cloudDensity` is both): render.comp draws them over everything
  at their height (fog when you fly in), react.comp spawns rain/snow/ash only under the high layer's undersides, and
  grid.comp writes each mage's cloud depth to counts[58] (`Mage.fog`: misted sprite, wisps in overlay).

## Water's look (27 Nov, user: "in large bodies of water the water texture looks very tiled")
- render.comp `fgColor`, M_WATER: was two sine waves (one a diagonal stripe every few cells), a lattice over a whole
  sea. Now two sizes of slowly drifting value noise (`vnoise` seeds 63, 64; stretched sideways into streaks) cut into
  the ramp's bands, darkest to lightest 2, 0, 1, 3 (pixel art, no smooth gradient), a little per-cell dither where
  bands meet, and the odd cell glinting. The open top row is unchanged.

## Water, fleshed out (27 Nov; user: "the water is a bit too viscous, and i would like a more fleshed out water with proper vfx")
- Flow (move.comp): water keeps the way it's flowing in bit 8 of its cell (the low bit of its shade, unused for water:
  render.comp shades it by noise): it steps that way at 0.995 and back at 0.3, and turns round against anything, so
  a spill runs along instead of jostling to and fro and a pool levels several times as fast. Mud and lava keep their
  slow `flowP`.
- Swimming (main, the mage in liquid): about half again as fast (speed 1.05, drag 0.945 sideways and 0.93 up and
  down), and the down key swims you down.
- The look (render.comp): the top row glints and foams, drifting (vnoise); shafts of light slant down from a sea's
  top, swaying, gone by 90 cells down (added before the lighting, so dark at night and in the deep).
- Effects (vfx.gd `splash_in`, `splash_out`, `bubble`, `drip`, `wake`; main `_water_fx`, `_water_fx_e`): going in, a
  crown of droplets thrown up and falling back, spray, a ring of foam, bubbles under it (by how fast, and by size for
  creatures); coming out, a smaller one and drips off you for a while; under water, bubbles from your mouth every
  second or so (more swimming hard), rising and wobbling (a BUBBLE particle) and popping in droplets at the top;
  swimming along the top, foam behind you. Test: `_test_water` (ui section: a spill's spread, a splash, bubbles;
  water.png).
