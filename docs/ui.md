# Wisp Forge: The UI, speech bubbles, satchel and minimap

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## The UI (scripts/ui.gd, pixel_font.gd, icons.gd; user, 21 Nov: a pixel-art UI; 22 Nov: arcane and decluttered)
- Arcane style, all through `_frame`: panels (pad 4 and up) are runed 24 x 24 nine-slices tiled in the middle (an
  ink outline, the astral-violet `TRIM`, a dark gap, a faint `MANA`-blue inner line, a cut gem in each corner, a
  faint field of stars inside); smaller frames (slots, small buttons, recipe cards) are plain 8 x 8. Gold is for
  what's chosen, `MANA` blue trims a recipe you can forge now.
- Decluttered HUD: the plate shows health, mana (shining while mana goes on shaping, a red wash under 1), breath
  when it matters, the place and the time (weather only when there is some, depth only underground; FPS and the
  profile only on F3; requests under it). The satchel is a POUCH (what Conjure places, draughts, coins, "I
  satchel") until I or Tab (`toggle_satchel`, `satchel_open`) opens the grid; its heading names the staff and the
  relics. Toasts are short notes at the bottom left (four at most, the same note freshens the one showing). The
  spell bar sits in a runed panel. `_test_ui` saves `ui_hud_pouch.png` and `ui_hud.png` (open).
- ui.gd's `root` is scaled by `U` (screen pixels per UI pixel: floor(screen height / 540), so 2 at 1080p and
  1440p) and sized to the screen in UI pixels (`_relayout` on resize): every size in ui.gd is UI pixels. Screen
  rectangles of controls: `_on_screen(c)` (get_global_rect ignores the scale). Tooltips pop up outside the root,
  so their frame and font are scaled by U in `_relayout`. title_screen.gd draws by its own `size` (UI pixels).
- pixel_font.gd: the game's bitmap font (`GLYPHS`: char -> [top row, rows]; caps 7, x-height 5, descent 2;
  `SIZE` 10), built at start-up into a FontFile (`make()`, `make(true)` bold), integer scaling only. Always use
  it at a multiple of SIZE (ui `fsize`; the old design sizes map to 1x/2x/3x). Bitmap fonts take no outline:
  labels get a one-pixel shadow. The overlay's bubbles, name tags and marks, map_view and space labels use it at
  SIZE * ui.U through a 1/scale_px transform. A new character is one line in GLYPHS.
- icons.gd: `mat(m)` (style by `MAT_STYLE` or the material's kind: block with its pattern, pile, drop, ore,
  gem, pearl/orb, ingot, log, leaf, shroom, cactus, torch, door, pane, rune), `spell(id)` (`SPELL_ART`, 11 x 11),
  `item(key)` (`ITEM_ART`/`ITEM_COL`: potion, coin, letter, chair, heart, drop, bubble, skull, book); outlined
  and cached.
- Weights (user, 21 Nov: "the new font is a little thick"): buttons and 1x headings use the regular face; the bold
  face only for headings at 2x and up (`_head`). The title (title_screen.gd): a main menu of Play / Settings / Quit
  (`MENU_W`, one width), Play opens the journeys panel (`show_slots`; Back or Esc `show_main`): a card per save slot
  (`CARD_W`) and its Delete (`DEL_W`), an empty slot's card the whole row, so every row lines up. Test: `_test_ui` checks both and saves
  `ui_slots.png`.
- Forge cards line up (user, 22 Nov: "the forge buttons are moving based on how much text is in the box"): a
  row's cards are as tall as its tallest (GridContainer), and `_recipe_card` puts an expanding gap under the
  description, then the lock text, the cost chips and ALWAYS a button (Forge, or greyed "Locked"/"Forged"), so
  costs and buttons sit at the bottom of every card. Icons (missing artwork: wards, travel, staff and body
  recipes all showed a red book): `Icons.thing(id)` (`THING_ART` shapes + `THINGS` id -> [shape, colours]: the
  foci as staves by tier, feather, rings, bloom, crystal, the wards (shield, amulets, veil, mask), skiff, Core
  Drive, engine, sail, beam, the smelter's band and edge, a recipe scroll), `Icons.prop(kind)` (a furniture
  recipe drawn from the piece itself, seed 7, shrunk to 13 px) and `Icons.prop_rows(rows)` (a carried piece in
  the satchel). ui `_recipe_icon(r)` picks; locked book pages show it dimmed; shops and stations use them too.
  Shop and station panels are violet like the rest. Speech bubbles and keepers' "[F]" go on after the mages
  (overlay `bubbles`), so the mage never hides the words.
- The satchel is a grid of `_slot`s (icon at 2x, count), the spell bar slots with glyphs, their number, the
  cooldown and a red wash when mana is short (`_draw_slot_over`), the chosen spell's name over it; the forge
  fills the screen (`show_forge`: 3-5 columns), with a tab per category (jumps the list) and cost chips
  (`_cost_chip`); shops in two columns. Test: `_test_ui` ("ui": the font has every character the game writes,
  whole-pixel scale, satchel and spell bar on screen; pictures `ui_hud/forge/settings/shop/title.png`).

## Speech bubbles (scripts/speech.gd; user, 25 Nov: "make the text boxes for speech look a little nicer with an animation and talking sound effects")
- main `speech` draws every bubble: overlay `_bubble(wpos, text, alpha, key, style, pitch)` (villagers "f<seed>",
  keepers' and the door's prompts, the mystery's prompt, the wisp "wisp"; `test_bubbles` for the tests), the
  pocket's prompts and space.gd's spacers ("s<seed>") and their prompts. Kept by `key` while drawn (forgotten after
  `FORGET` frames unseen, or when the words change): it POPS open out of its tail (`POP` frames, a small overshoot),
  then TYPES `CPS` letters a frame (pauses after . ! ? and , ; :), with a BLIP (audio "talk", the wisp's "talk_wisp")
  every `BLIP_EVERY` letters at the speaker's pitch (`pitch_of(seed)` 0.78..1.3). The box is laid out for the
  whole text first, so it never resizes while typing. Styles SPEECH (parchment), WISP (deep blue, glowing edge,
  corner twinkles, a slight bob), PROMPT (dark ink, gold edge; words shown at once, silent); words in [brackets]
  take the accent colour. Test: `_test_speech` ("speech"; in the full run after `_test_ui`; pictures
  `speech_typing.png`, `speech_wisp.png`, `speech_kinds.png`).

## Satchel, minimap, pause
- One satchel for everything carried (user, 23 Nov: "its a little convoluted ... i can have a bed in my
  inventory, but not a kiln and i cant place a bed from my inventory"): ui.gd `_update_satchel`, open, is
  sections (`satchel` a VBox; `_sat_section`, `_sat_slot`, `SAT_COLS` 8, `satchel_slots` for the tests): Blocks,
  Nature, Ores & ingots (`_sat_group`; click a placeable one: Conjure places it), To set down (torches, doors,
  furniture, workshops taken up (`items["st_<kind>"]`, `Icons.station`): click = main `hold_carried(what, idx,
  sk)`: build mode opens on that piece), Draughts & sigils; the name of what you point at under it (`_sat_name`).
  Build's Satchel tab lists carried workshops too (`Build.carried_pieces(furn, items)`). Checked in
  `_test_workshops`.
- The MINIMAP replaces the edge arrows (user, 24 Nov: "get rid of arrows on the hud and just use the map, and maybe
  add a mini map for all of the hud stuff currently in space and use it for planetary things as well. waypoints
  and such"; chose the side view on a planet): scripts/minimap.gd, a Control in ui.gd's `minimap_panel` (top
  right, pinned by its offsets; the satchel's pouch under it; hidden while the satchel grid is open, on the map
  and in menus; N toggles setting "minimap"). In space a radar turned like the screen, logarithmic
  (`_rad`: 1k, 5k, 25k rings, `SP_FAR` on the rim): space.gd's `_marker` now only gathers everything that had an
  arrow (on screen or not; with a "kind": planet, star, waypoint, skiff, pirate, outpost, station, wreck, rock,
  well, rift, monolith) and `_flush_marks` hands them over as `map_marks`; plus every rock and hull streamed in and
  the void's beasts; "N" the chart's north. On a planet a side view (`CELLS` 12 a pixel, turned like the screen,
  `_side`): the ground's line from `gpu.surf_at` in its biome's top colour, the sea, home, the skiff, villages
  seen, workshops and altars, charted lairs and crypts, the party, the waypoint; past the edge a pip pointing the
  way. You are an arrow the way you face (main `facing_dir(m)`: a ship's nose, or the screen side you look to);
  pointing at it names a thing; under it the waypoint's distance. The map's "You" is that arrow too
  (map_view `_you`, `you_dir`). PLANET WAYPOINTS: a click on the planet map (`set_planet_waypoint`: put on the
  ground under a point in the air), a right click or Backspace clears; `planet_state["waypoint"]`, shown on the
  map with a line and on the minimap, cleared within `WAYPOINT_REACH` (`_check_planet_waypoint`). Test:
  `_test_minimap` ("minimap"; in the full run right after the skiff's own check; pictures `minimap_planet.png`,
  `map_waypoint.png`, `minimap_space.png`, `map_space_facing.png`).
- The Esc menu pauses (user, 23 Nov: "escape menu doesnt pause"): main `menu_paused()` (state play/dead with
  ui.settings_panel showing): `_process` runs no ticks and the GPU frame as paused, keys and clicks do nothing
  but Esc. Checked in `_test_ui` (the game's `time` stands still while it's open).

## The staff's gem shows your mana (user, 25 Nov: "the staff's gem shows your mana, dimming as it drains and flaring when full")
- overlay `_gem_now(m, gem)` (from `_draw_mage`, the colour handed to `MageRig.front_pixels`): the selected spell's
  colour dims toward dark glass as `m.mana / m.max_mana` falls (by the square of what's spent), and flashes white
  for 24 frames as it fills up again (`_gem_was` per mage; `stats_gem_flares`). The HUD's mana bar stays.
- The forge panel is on the right of the screen now (crafting.md, "The forge, the book and the workshops in the
  world"); the quick bar is under the hand bar (building.md).

