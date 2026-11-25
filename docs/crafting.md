# Wisp Forge: Crafting: the Wisp Forge, workshops, recipes, mana

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Workshops (scripts/workshops.gd, workshop_art.gd; user, 22 Nov: real kilns and smelters, a small bonus for forging in a proper workshop, "some secrets that can be discovered through experimenting")
- A station is an OBJECT (main `Station`, a Body like `Chest`; `new_station(kind)`), not cells: `Defs.STATIONS`
  (kiln, smelter, still, anvil: size, "burn" fuel a tick, "spark" chance, build cost). Set down from build mode's
  Workshops tab (`Build.CAT_WORKSHOPS` 7, kind "station": on level ground, not on another; one taken up,
  `items["st_<kind>"]`, sets down free); Shift + right-click takes it up with what's in it (`take_at`). Saved in
  `planet_state["stations"]` (`save_to` in `_world_meta`, `load_from` after `_make_chests`). Drawn by overlay
  `_draw_stations`: body lit by the world, fire layer unlit and flickering (`_sprite(..., glow)`), a Still's jar
  tinted by what it brews.
- F beside one (`interact`, after the villagers) opens its panel: main state "station" (the world waits, but
  `work_all` keeps running so you watch it), ui.gd `show_station`/`update_station`/`_render_station`: load from
  the satchel (left 1, right 10), feed the fire (`Defs.FUEL_TICKS`: coal, wood, planks...), take back, take out,
  and "It makes" (secrets as riddles heard, or "?").
- Working (`_work`): what's loaded must be EXACTLY the kinds of a `Defs.PROCESS` entry (enough of each); a mix it
  doesn't know does nothing. Then it burns fuel, warms (`heat`, 4 s from cold) and works batch after batch at
  its heat into `out` ("m<mat>", "potion", "d_<draught>", "gear:<id>"). "night": only after dark. A secret's
  first batch is a discovery (`items["secret_<id>"]`, toast, burst); hints (`items["hint_<id>"]`) come from
  villagers (towns.gd `line_for` topic "secret") and torn notes in chests (`hint_note`).
- Real fire (`_fire`, near a mage): smoke, embers, a light, and every `SPARK_EVERY` ticks a chance (`_spark`)
  that a spark lights anything that burns just beside it (FIRE brushes). In water it goes out ("wet").
  Sparks fly only out of its sides and top, never into the floor it stands on (user, 23 Nov: a smelter on a
  plank floor set the house on fire; the smelter's chance 0.55 -> 0.35), and setting one down beside something
  that burns says so (`burnable_near`).
- Refined materials: COPPERBAR 58 and WISPBAR 59 (Smelter only, `PLACE` 0; NM 60). Glass and roof tiles are
  fired in the Kiln now (no forge recipe); many recipes take ingots (Copper Focus, Levitation, Fireball,
  the skiff, wards...).
- Secrets: kiln obsidian (ash + sand) and grown prism (glass + glowcap); smelter Wispsteel Band and Starsteel
  Edge (`Defs.WORK_GEAR`, "once", read by `gear()`, `own_work_gear`); still draughts (`Defs.DRAUGHTS`: Ember,
  Swiftfoot, Mana, Moonlit at night), drunk from the satchel (`drink_draught`), working through `gear()` while in
  `Mage.buffs` (new stat "fire_dmg" in the hazards).
- Masterwork: ore gear forged within `ANVIL_REACH` of an anvil station (`anvil_near`) keeps `items["q_<id>"]`
  (`MASTERWORK` 1.25): `gear()` scales its mods ((mod - 1) x q + 1, an added stat x q), the once-applied ones too.
- Test: `_test_workshops` ("workshops": on a natural slab in the air; pictures `workshops.png`,
  `workshop_panel.png`).

## Crafting as one system (user, 25 Nov: "some recipes are in the smelter and other workshops but not in the recipe book ... All the crafting systems feel a little stuck together"; chose: the forge stays anywhere, workshops load by hand or by clicking a known recipe, the book covers what goes in the satchel, everything placed as an object comes from the satchel, workshops in the forge, an amount to craft many)
- The Wisp Forge (C, anywhere) forges WORKSHOPS (`Build.workshop_recipes`, category "Workshops": kiln, smelter, still,
  anvil, altar; `r["station"]` -> `items["st_<kind>"]`) and FURNITURE and OUTDOOR pieces (`Build.furniture_recipes`,
  cats 2 and 3, "arg" passed to `Props.make`) into the satchel; they're set down from the satchel (ui "To set down",
  build mode's Satchel tab, `hold_carried`). Build mode's `CAT_ORDER` is [Back Walls, Blocks, Remove, Doors & Stairs,
  Structures, Satchel]: the Furniture (2), Outdoors (3) and Workshops (7) tabs' pieces and code stay (tests set
  `build_cat` to them), out of the player's reach. Torches are a Satchel-tab piece (`Build.carried_pieces(furn,
  items, inv)`). The cabin/pocket builder (`_cabin_edit`) sets carried furniture down too ("carried").
- AMOUNT: ui `craft_amount` (1..99, `_amount_box`: − n +, Shift by 10; `set_craft_amount`), in the forge's tab row
  and the workshop panel. main `recipe_repeatable(r)` (give, potion, sigil, furniture, station) and
  `craft_many(r, n)` (as many as the satchel pays, `craft_quiet` holds the per-item toasts and saves, one toast and
  save after); ui `_on_craft` uses it ("Forge ×N" on repeatable cards).
- THE BOOK holds the workshops' mixes: after the forge's own categories a section per workshop ("Kiln (workshop)",
  ..., a tab each) of `_process_card`s (`workshops.known_recipes(kind)`: the plain ones and the secrets found), and
  the unfound secrets as `_secret_page`s among the Recipe Book's pages (their riddle once heard).
- THE WORKSHOP PANEL: under "It makes", a Load button on each known mix: `workshops.load_recipe(st, pr, n)` (what
  else is loaded goes back first; as many batches as the satchel and what's in already hold). Loading by hand
  (click the satchel) is as before, and still how secrets are found.
- Test: `_test_crafting` ("crafting"; in the full run after `_test_workshops`; pictures `forge_workshops.png`,
  `workshop_recipes.png`).

## The forge, the book and the workshops in the world (user, 25 Nov, second pass of "make it feel more inside the world": "C summons the forge into the world", "the recipe book is a grimoire", "workshops show what they're doing", "Send to the Kiln")
- THE SUMMONED FORGE: `toggle_forge` calls `_summon_forge()`: a ghostly anvil and violet flame (workshop_art
  `spirit_forge()`, 17x24: "body", "fire0", "fire1") rise beside you (`forge_at`, a little to the left on screen,
  under `view_up()`), with a rune ring and motes. The world waits while the forge is open, so it runs its own
  clock: `_process`'s "forge" branch calls `_forge_tick()` (`forge_t`, `forge_vis` up over `FORGE_RISE` ticks,
  violet sparks, `vfx.tick()`, a redraw). Each thing forged (`craft_many` -> `_forge_send(r)`) rings on the anvil
  and flies to you as motes (`vfx.fly(from, to, col, n)`; `stats_forge_sent`). Shut, `_dismiss_forge()` and
  `forge_vis` fades over `FORGE_FADE` ticks in `_tick`. overlay `_draw_forge()` (risen with a smoothstep,
  bobbing). The forge panel sits on the right of the screen (ui `_build_forge`: `PRESET_CENTER_RIGHT`, 2 or 3
  cards across from half the screen) so the anvil stays in sight.
- THE GRIMOIRE: `learn(id)` adds the id to `items["book_new"]` and a page to `pages` ([start point, ticks;
  negative waits, so several learned at once go one after another]): overlay `_draw_pages()` flies a little
  parchment page, turning, from above you down to a book at your side, which shows a moment (`PAGE_FLY`,
  `PAGE_BOOK`; audio "page"; `stats_pages`). The next time the forge opens (ui `show_forge`) those ids go into
  `_inking` and `book_new` is cleared: their cards start faded sepia and tween to full ink one after another with
  a "New page" tag. Pages not yet learned (`_book_page`) are parchment (`PAGE`, `PAGE_INK`) with the thing sketched
  in ink (`Icons.sketch(tex)`: sepia strokes by shading, gaps where the ink didn't take, a smudge; cached).
- WORKSHOPS AT WORK (overlay `_draw_stations`): what's loaded (`_working_mat`) glows in the station's mouth (an
  "_ore" lump made under its fire's lowest row, in the material's colour, hotter as it heats) and tints the flame;
  the still's jar fills over the batch (four "_fill<n>" levels cut from its fill image, by `prog / ticks`); what
  it made sits on a little plank tray at its side (`_draw_tray`: ingots in the material's colour, stoppered
  bottles for draughts, up to eight, a glint).
- F AT A WORKSHOP (`workshops.interact`): what's on its tray first (`has_out`, `take_out(st, true)`: flies to you
  and pops up beside it, no panel; `stats["trays"]`); then, holding Conjure with a material in hand that it works
  (an input of one of its mixes) and doesn't hold yet, `drop_in` puts in four batches' worth of a known mix (ten
  for a mix still to try), or feeds the fire with a fuel when it's low (`stats["dropped"]`); otherwise the panel
  (fuel, details, Load buttons).
- SEND TO THE KILN: each workshop mix card in the book (`_process_card`) ends in "Send to the <workshop>" when one
  of its kind is within `workshops.SEND_REACH` (160) of you (`nearest_kind`), else greyed "No <workshop> near";
  `workshops.send(pr, craft_amount)` loads it there (`load_recipe`) with motes flying to it (`stats["sent"]`).
- Test: `_test_inworld` ("inworld", tests/building.gd).

## Shaping the world is magic (user, 22 Nov: "tie excavating and removing blocks to mana ... everything ideally would be tied into the fact that we are using magic including vfx")
- Mana per cell, harder costs more: main `dig_mana(t)` = `DIG_MANA` (0.068) x (1 + 1.5 x HARD) x `DIG_TIER_COST` by
  staff tier (1, 1, 0.78, 0.62, 0.48) x gear("mana_cost"); mana comes back `mana_regen_of(m)` a tick = `m.mana_regen`
  (0.22; the Mana Crystal +0.1, gear) + `TIER_REGEN` (0.05) per focus past the plain staff (user, 24 Nov: a better
  staff dug faster and drained faster; less waiting, but spamming still runs dry; never read `m.mana_regen` directly);
  `_apply_counts` spends it for everything the GPU brushes collected this frame (dig, deconstruct, plants) and
  `place_mana(cells)` (`PLACE_MANA` 0.04) for what conjuring / back-wall painting placed (C_PLACED), and lights
  the HUD's mana bar (`Mage.mana_spent_t`). `has_mana(m, need, p, what)`: below `MANA_FLOOR` (1) digging,
  deconstructing and conjuring don't start (a toast, `vfx.fizzle`). Precise removal and Flatten work out their cost
  from what they read back and `pay_mana` it first (nothing happens without it; previews say "about N mana");
  build pieces pay `_place_mana_of(place)` (cells stamped, a door's doorway, a structure's blueprint; a torch
  `TORCH_MANA` 2, a workshop `STATION_MANA` 8), shapes `place_mana(cells)`. `free_magic` (the test mode, but in
  `_test_remove`'s mana check) makes it all free.
- vfx.gd: `dig(m, p, r, take)` every frame of digging / deconstructing (motes along a tether from the staff's
  tip, a turning rune circle where it bites, loosened sparks drawn home), `conjure(p, col)`, `shape_burst(cells,
  place)` (remove/flatten: mana-blue sparks rising; laying blocks: gold motes gathering; a rune circle over the
  middle), `place_flash(p, size)` (a piece put up), `fizzle(p)`. `MANA_COL` / `SHAPE_COL`.

## Recipes you discover
- Recipes you discover (user, 21 Nov; roadmap step 13): `Defs.LEARN` / `learn_of(r)` says how each recipe is
  learned ("start"; "find" [materials]: the first time you hold one; "scroll" 1-3: a recipe scroll in a chest of
  that grade; "shop" role + "kind" + "price": sold by village keepers, and taught as a request's thanks; "hoard":
  a guardian's hoard or a warden's reliquary). Ore gear: an ore's first piece on finding it, its second at a smithy
  on that ore's world, its third and every alloy in a hoard; furniture and anything unlisted is known from the
  start. main: `learned` (ids, saved as "learned"; a save without it learns all), `knows(r)`, `learn(id, why)`
  (a spell with its own "scroll" item gets that item too), `learn_all` (old saves, the test mode, F9),
  `_learn_from_finds` (every second), `_chest_recipe(level)` (in `_try_open_chest`: 0.3 + rare x 0.4, level 3 in
  dungeons and temples, 2 in ruins, keeps, mines or 150 below the surface), `_hoard_recipe` (this world's own
  first), `shop_recipes(role)`. `craft` refuses an unknown recipe. towns.gd `shop_def` lists a keeper's recipes
  ("recipe" sale items; `owned` = known, `grant` learns), `_finish` teaches one as thanks (one request in three).
  ui.gd: the forge lists what you know, then the Recipe Book (`_book_page`: locked pages with `Defs.learn_hint`;
  J opens the forge there, `show_forge(true)`). Test: `_test_recipes` ("recipes", picture `forge_book.png`).
