# Wisp Forge: Pixel bodies, the skiff and your own ship

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Pixel bodies and the skiff
- Pixel bodies (`scripts/pixel_body.gd`, RefCounted): the general flying/drifting object made of cells (material
  + variant per cell in a w x h grid, body coords x along the nose, y down; `pos` = centre of mass, `ang` the +x
  axis's world angle, `facing` -1 mirrors). `rebuild` (mass, `com`, `outline`), `to_world`/`to_body`, `texture()`
  (palette colours, glass see-through), `carve` (damage), `pieces` (joined-up parts). The skiff uses it; asteroids,
  enemy ships and wrecks are meant to. Room inside: `rebuild` floods from the grid's edges through everything that
  isn't hull (`outside`); what the hull closes in is `room`, a place to build: `place(i, j, m, back)` (front blocks
  only into empty room cells, marked `made`; back layer `bg`/`bgv` anywhere in the room) and `remove` (only what was
  built; the hull comes away by `carve`). The `outline` it collides by is only cells touching the outside, so
  building inside never changes how it collides; `keel` is its lowest outline point. `save_cells`/`load_cells`
  pack all five layers (saved in `planet_state["skiff"]["cells"]`). `back_texture()` is drawn behind the riders.
- The Wisp Skiff (`scripts/skiff.gd`, extends pixel_body.gd; `Skiff.make(seed)`): grown from parts (`_hull`, `_trim`,
  `_engine`, `_fin`, then `_canopy`: a timber frame and glass shell around an open cabin with a glass back pane, the
  body's room), two seats on the cabin floor (`seat_cells`, `riders`, pilot first). `steer(input)`: the movement keys
  (over the planet below: left/right, W/space up, S down) plus, holding cast, toward the cursor. `fly(want, piloted,
  g, in_space, cruise, drag)`: piloted in the air it eases to `want * cruise` (`ACCEL`) or, hands off, to a hover
  (`BRAKE`; within 10 cells of the ground it settles onto it; coming down near the ground it slows); `CRUISE` in the
  air, `CRUISE_HIGH` above it, extra speed shed quickly in the air; nobody at the controls it falls with drag; in
  space thrust adds to its speed. The hull stays level over `centre`'s ground, tilted into climbs and dives on a
  spring (`omega`); `facing` flips when steered the other way and `look` eases through it (overlay squashes the
  picture by `look * facing`). `advance` (moves in sub-steps, colliding its outline through main's collision
  grid via `collide`, which slides with friction; then `clear_below`, the air under the keel). Forged at the Wisp Forge (recipe "skiff": `items["skiff"]` is its seed); K `call_skiff`
  sets it down beside you; F (`_skiff_interact`, before chests and doors) boards or steps out; riders follow their
  seat (`_ride`: no casting or digging aboard, its air to breathe). main `_update_skiff` flies it on the planet;
  flown out of the top of the orbit band it takes everyone into space (`space.try_enter` needs the whole party
  aboard), and space.gd flies it out there. Saved per planet in `planet_state["skiff"]`; overlay `_draw_skiff`.
  Drawn by `_skiff_xf`: turned with the ship but one body cell to one pixel (never a map taken straight from the
  world: the close view's columns widen with height and would stretch it); its riders are drawn inside that
  transform (`_draw_mage(..., place)`), so they sit and turn with it. Air drag 0.97 a tick below `R_TOP` (none above);
  coming back from space it sheds its speed to 8 a tick, and glows coming down fast through the air.

## Ship classes (25 Nov)
- The user, 25 Nov: "If we have a pocket dimension i dont think we need to be able to build on the ship anymore.
  i would rather have the pocket dimension be the safe haven for crafting a home and workstations. Also i dont know
  if we need seats or anything if we can just go inside the ship. the ship builder also could use refining. maybe
  we have prefab ships instead that you can get recipes for different ships." Chosen: classes from recipes, each
  with its own stats and a look grown from parts; keep damage, cargo as a stat.
- `Skiff.CLASSES` (skiff.gd): skiff (speed 1.0, armour 1.0, 3 crates, 1 gun), cutter (1.35, 0.8, 2, 1: long and
  slim on a swept `_wing`), hauler (0.75, 1.3, 12, 0: deep with `_pods` slung under it and a second engine),
  corvette (1.1, 1.7, 5, 2: HULL plating, STARIRON bands, WISPBAR trim and a `_turret`). `Skiff.make(seed, klass)`
  grows it from the same parts (`_hull`/`_trim` take materials, `_engine(n)`, `_fin(more)`); the seed picks its
  look. `cls()` is its class's row: `drive()` gives its speed (thrust and cruise), `hold_cap()` its crates,
  `damage` carves `r / sqrt(armour)`, space `_fire_cannon` fires `guns` bolts (none: a toast). Seats stay inside
  (four, never drawn, forward by the helm at 0.8 of its length); X no longer walks the deck.
- SAILS, not a glass bubble (user, 26 Nov: "You still have the bubble where the player goes. Can we just have sails
  since the player is not gonna show up anymore"): `_sails` grows masts (timber; star iron on the Corvette) with a
  glowing wisp pennant, and by class: the Skiff one square sail of white canvas (SNOW) with the wisp's sigil and a
  jib on a stay to the bow (`_square`, `_jib`), the Cutter a long fore-and-aft sail on a boom swept aft
  (`_fore_aft`) and a jib, the Hauler two square sails of tan canvas (SAND), the Corvette two of red war-canvas
  (TILE). Every sail's foot is 8 rows above the deck so crates stand under it (there's no enclosed room now: they
  go on the open deck). `_canopy` is left for the old keel only. Icons match. Test: the skiff check "ships carry
  sails" (no glass on any class, cloth and masts, one piece, saved and loaded back).
- Owned ships (main.gd): `items["ships"]` class -> seed, `items["ship_class"]` the one you fly, `items["skiff"]` its
  seed. Recipes: "skiff" (the Wisp Skiff, round the Core Drive: forged whole, no keel), "ship_cutter" (an outpost
  shipwright, 140 coins; plans in a chest from level 2), "ship_hauler" (shipwright, 180), "ship_corvette" (a
  hoard); each needs the first ship and has `"ship"`: forging it adds it and flies it (`switch_ship`, the one out
  replaced where it stood). The satchel's Ships section lists them (click: fly it, off the ship); a forged ship's
  forge card says "Another look" (`reshape_ship`: a new seed). `make_ship()` builds the one you fly. `_migrate_ships`
  (on load) keeps an old journey's skiff as a Wisp Skiff and lets a hull built in the old builder go
  (`load_cells` refuses one that's `designed` or of another class). The HUD shows "hold n/cap crates" aboard or in
  space. B aboard says ships come whole; the cabin builder no longer runs (its code, the Ship tab and shipyard.gd's
  panel are left but unreachable; `shipyard.parked()` is still how G knows you're landed). The quest's "hull" step is
  now "Call your ship and board it" (`items["boarded"]`). Test: "ships" (`_test_ships`, then the pocket); the sheet
  `saves/shots/ships.png`.

## Parts, damage, fuel, hull, builder, pocket, cargo
(The hull builder, cabin building and the keel below are from before the ship classes and no longer reachable.)
- SHIP PARTS (recipes with "part": unlocked by the salvaged part, used up in forging, `recipe_hidden` until you
  have a skiff): the Wisp Shield (`items["shield"]`: space `_strike` on a mage aboard is taken by it when
  `shield` is 1, then it charges over `SHIELD_RECHARGE` ticks; a ring flash, a faint shimmer while ready) and
  the Wisp Cannon (`items["cannon"]`: aboard in space the cast button fires instead of steering, `_fire_cannon`,
  `CANNON_MANA` 6, `CANNON_CD` 16; `shots` step 2 cells at a time against `_rock_solid`, `_blast_rocks` blows
  cells away (not caches), `vfx.blast` kind 2). Test: `_test_wrecks` ("wrecks"; in the full run on Verdance
  right before the journey to Cindrel: 12 grown wrecks (a bridge cache each, every cache reached by a disc 17
  across: `_wreck_reach`), the first wreck streamed in, aboard, every cache opened, the hull holds from inside,
  salvage dug, the shield takes a strike, the cannon hits without steering, its sector saved and back as left,
  the map; pictures `wreck_outside/inside/cannon/map.png`).
- SKIFF DAMAGE AND MENDING (skiff.gd): `design`/`design_v` are the cells as forged (`hull0`, `engine0` WISP cells);
  `rebuild` recounts `hull_f`/`engine_f`; `thrust()` (0.4 + 0.6 sqrt(engine_f)) scales thrust in space and cruise in
  the air. `damage(p, r)` carves (nothing below `HULL_FLOOR` 0.25). space.gd `skiff_hit(sk, p, r, through)`: the
  shield takes it if charged (in space), else the hull is carved, riders shaken (`PIRATE_SHOCK`, no iframes) or,
  at the floor, hurt by `through`; sparks, "crack", `_hull_warning` at 75/50/25%. Used by pirate bolts (r 3.5),
  storm lightning (`_strike`, at the first hull cell on the bolt's line: `_first_cell`) and crashes: `advance`
  records `bump` (speed into what it hit) and `bump_at`; over `CRASH_SPACE` 7 (space) / main `CRASH_PLANET` 9
  `skiff_crash`. Mending: hold R (`PlayerInput.mend`, not in build mode) aboard or within w/2 + 24: main
  `_mend_skiff` mends `MEND_CELLS` every other tick (`mend(n)`: missing design cells beside ones still there
  first) for `MEND_MANA` a cell and matter (`_mend_bank`: a Hull Plating = `MEND_HULL` 6 cells, a plank 3). HUD:
  a hull bar (icon "hull") while aboard and hurt or in space. Falling out in space: main `_respawn` calls
  `space.reset_after_death` (home back at the origin, pirates gone, nobody aboard, out of space) then `call_skiff`.
  Test: `_test_pirates` ("pirates"; in the full run right after `_test_wrecks`): 10 grown ships, a cutter's
  attack holes the hull, the cannon beats it, its strongbox, mending, the shield, a crash, death out there;
  pictures `pirate_ships/attack/beaten.png`, `skiff_damaged/mended.png`. The storm-belt check mends the skiff.
- BUILDING IN THE CABIN (user, 23 Nov): B while aboard (main `_update_cabin`, from the tick's riders and space.gd's
  tick; `cabin_cast` takes the cast button from steering and the cannon while building). The cursor's cell is
  `sk.to_body(aim) + sk.com`. Blocks ("block") and back walls ("wall") paint `build_thick` squares every 3 ticks
  into `in_room` cells (blocks never in `in_seat`: a rider's box), paid a cell a material; furniture ("prop",
  `Build.design`) goes into pixel_body's `deco` layer (Props.PALETTE index + 1; drawn by `back_texture` in front of
  the back wall, behind the riders), let down onto the cabin floor and slid sideways until it fits
  (`_cabin_prop_cells`), one a click; the Remove tab ("remove" layers) takes built blocks, back walls (the forged
  glass pane, `design_bg`, comes back, nothing given for it) and furniture (planks back). `save_cells` packs six
  layers now (`load_cells` takes five or six). `cabin_stats`. Test: `_test_cabin` ("cabin"; `_pick_piece(name)`;
  picture `cabin_built.png`). The cabin is small (about 30 x 25 cells): bigger hulls later.
- WISP FUEL (user, 23 Nov: "Only the long hauls"): WISPCELL (material 62, NM 63, "Wisp Cell"): smelter `s_cell`
  (3 wisp ore + 1 coal -> 2 since 27 Nov), outposts sell 10 for 28. space.gd: the Starsail burns one every `SAIL_BURN` (150) ticks
  under sail with a heading (`_burn`; none left, it won't unfurl, `_fuel_note` says why). A landfall costs nothing
  (user, 24 Nov: fuel only for the fast crossing between star systems; the journey cost and its hold at the planet's
  edge are gone). HUD in space: "N wisp cells". main `free_fuel` (the test mode; tests.gd sets it). Test: `_test_fuel` ("fuel").
- YOUR OWN HULL (user, 23 Nov: "Design your own hull"): build mode's Ship tab (`Build.CAT_SHIP` 9, `HULL_KINDS`
  hull/cut/helm/seat), used aboard (main `_update_cabin` -> `_update_hull`; on foot it says to board): paint hull
  cells (Hull Plating, Planking, Log Frame, Glass Hull, Copper Trim, Rune Deck (RUNESTONE, paid in masonry), One-way
  Deck (SCAFFOLD), Wisp Engine (WISP)) where they touch the ship (`can_hull`, a stroke's cells joining through each
  other), up to `MAX_W` 200 x `MAX_H` 110: `grow_for` grows the grid with a margin (every layer, the design layers,
  seats, `seat_marks`, `com`, and crew on deck move over), `add_hull` writes it into `design` (what mending puts
  back), `finish_edit(old_com)` rebuilds and keeps the ship where it was in the world. Cut Away (`cut`, any cell,
  seats' space too: the canopy over the second seat once shut the way aft) gives the material back. Helm
  (`set_helm`: seat 0) and Seat (`add_seat`, up to `MAX_SEATS` 8; a Seat click on one takes it out), placed where
  `seat_ok` (a floor, a 7 x 17 room over it); drawn on the back layer (`_seat_marks`: a chair, the helm's console).
  `riders` is as long as `seat_cells`. `designed`: `drive()` = sqrt(engine cells / mass against a skiff as forged,
  `_ratio0`), 0.35..1.5, in `thrust()`. `save_cells`/`load_cells` carry size, design layers, seats, marks;
  `items["ship"]` keeps the hull you built, so `call_skiff` makes it again on any planet.
  WALKING THE DECK: X (`deck_toggle`): up out of your seat onto the deck (`Mage.deck`, still `aboard`), or into the
  free seat you're by; F still steps off the ship. `_deck_move` (from `_ride`, and space.gd's tick for crew): in the
  ship's own cells (`deck_b`, `deck_v`), its pull 0.17 down through the keel always, walk, jump, step up, land on
  and (down + jump) drop through one-way decks (pixel_body's `move_box` / `box_free` / `platform_under`, moved
  there from station.gd); past its ends or below it you're off (`_off_deck`, with its speed). With anyone on deck
  and nobody at the helm it holds (`crew_on_deck`: fly's "piloted", hands off). Overlay `_draw_skiff` draws crew on
  deck with the riders. Test: `_test_hull` ("hull": a deck grown 64 aft, the cabin's back cut through, a seat on
  it, stand, walk, jump, sit, the helm, a climb, it holds with you on deck, walk off its end, save/load; pictures
  `hull_built.png`, `hull_deck.png`; the skiff as forged is put back after).
- THE SHIP BUILDER AND THE POCKET DIMENSION (user, 24 Nov: "create a ship builder instead ... when your not in the
  ship builder you just repair ... the inside of the ship be like a pocket dimension that you can enter ... a return
  to ship function ... as a spell ... the main quest can walk you through building your first ship"; chose: the
  builder wherever it's parked, an isle in a nebula, the pocket is home, forge a keel then build).
  THE KEEL: recipe "skiff" is the Wisp Keel now (planks, wood, wisp ore: what its cells give back, plus ingots);
  `craft` puts `Skiff.make_keel(seed).save_cells()` in `items["ship"]` (a deck 36 long, a bow, a WISP engine, the
  helm, `door_cell`), unless main `classic_skiff` (the test mode sets it: older checks fly the skiff as it was).
  THE BUILDER (scripts/shipyard.gd, main `shipyard`, state "shipyard": the world waits, no GPU frame; ui.gd
  `show_shipyard`/`update_shipyard` the parts panel and figures): B aboard opens it when `parked()` (on the
  ground, or `space.docked`/`docked_st`), else a toast; build mode's Ship tab (CAT 9) is out of `CAT_ORDER` (its
  code stays for `_test_hull`). The ship drawn big (`anchor` = where cell (0, 0) is, kept steady as the grid grows,
  `_hold_helm` after an undo or a new keel), left lays the chosen part (brush, Shift-drag a rectangle; `_stroke`:
  only cells `can_hull` joins, grown out from the ship, paid a cell), right cuts (refunded; the helm's floor
  `keep_cells` stays; `prune_loose` drops and refunds whatever no longer joins it; a seat with no floor goes), Helm /
  Seat (4 planks) / Pocket Door (an outer hull cell) by click, Z undo (ship, position and satchel), New keel twice,
  B/Esc closes (`_settle_ship` lifts it clear, `items["ship"]`, `hull_cells` kept as the highest). Out of it you only
  mend (R).
  THE POCKET (scripts/pocket.gd, pocket_isle.gd; main `pocket`, a pix child after space): F by the ship's door
  (`door_in_reach`, `Skiff.door_world`; a violet seam drawn on the hull, a bubble) or WISP RECALL (`Defs.SPELLS`
  "recall": a `RECALL_CHANNEL` 45-tick channel, `recall_tick` from the planet's and space's ticks, `hurt` breaks
  it, `_recall_now` enters at the next tick's start; cast in space through `_mend_cast` / `_space_cast`, even in an
  outpost) puts you on `PocketIsle`, a pixel body (ang PI, so `to_world(b) = (-b.x, b.y)`; the view angle is -PI/2
  there: `view_angle`, `close_view`, `unrolled`, overlay `_feet`/`_draw_mage`/`_lit`/`_draw_in_pocket`). The world
  outside waits (`_tick` hands over to `pocket.tick`, `_process` skips the GPU). The isle (its look of 25 Nov, the
  user: "the pocket dimension still needs work. it looks a little thrown together still"; chose the isle itself, the
  arch and heart, a home spot): grass, soil threaded with roots, a gravel seam, rock in wavy strata of stone and
  deepstone, a few crystal geodes, stalactites with crystal tips (`ground_at`, `drip_at`); a flagstone path from the
  arch to the heart (`_path`); the home terrace (`_terrace`, `TER_A`..`TER_B` right of the heart: level paving to
  build a home on, a wisp lantern at each end that glows); the Isle Heart (`_heart`: a tiered plinth you walk up,
  front `guard` cells, a faceted obelisk with a wisp seam, a floating shard, crystal clusters) and the arch (`_arch`:
  a stepped base, pillars in courses with rune lights, warded capitals, voussoirs, a wisp keystone) on the back layer
  (`guard`: never taken or built over; you walk in front of them); trees (`_tree`: flared trunk, boughs, a crown of
  blobs lit from the upper left), bushes, and `_dress` (tufts, flowers, stones, vines down the rim, roots hanging
  under it; again at each new level). An isle saved before (no "art" or under `ART`) is dressed again on load
  (`_restyle`: its own ground re-laid in strata, the heart and arch carved afresh, the path, the terrace only where
  nothing's built, nothing you built touched). A Python preview of the isle's art (needs Pillow and a pal.json of the palette): docs/tools/isle_preview.py; a nebula shader behind
  (`NEBULA`), far isles, light halos (`gather_lights`). Build there with build mode (blocks, back walls,
  furniture, Remove: main `_cabin_edit(m, body)`, the cabin's code made general with `can_take`/`touch`). F at the
  heart twice grows the isle (`expand`, `expand_cost` levels 1-6, 40 mana; LEVELS half widths 70..296). F at the
  arch: back where you came in (`back`); G there: out at the ship's door if it's in the same place (planet or
  space). Saved in the slot's `pocket.dat` (`save_isle` "v" 2); a save made inside keeps you where you came in
  (`_world_meta`). First time in: Wisp Recall learned, `items["pocket_seen"]`. A ship from before gets a door at
  its stern's lowest cell (`Skiff.ensure_door`, from `_update_skiff` and the builder).
  Quest: "skiff" (forge the Wisp Skiff), "hull" (call it and board it), "pocket". Test: `_test_ships` ("ships",
  "shipyard" or "pocket"; then `_test_pocket`, which checks the look and an old isle's restyle; pictures
  `ships.png`, `pocket_isle.png`, `pocket_grown.png`, `pocket_room.png`).
- THE CARGO HOLD (user, 23 Nov: "Hold for big things only"): `Defs.GOODS` (8 trade goods with a base price) ride
  as crates in `items["cargo"]` (good -> crates; "sealed" is a courier job's), never the satchel; drawn where they
  stand (skiff `crate_slots`: in its room away from the helm, else lashed on its open deck; overlay `_crate_tex`); `Defs.trade_of(outpost seed)`: three goods an
  outpost sells cheap (0.55-0.72 x base), three it wants (1.5-1.9 x), what it pays for each. towns.gd: an outpost's
  `shop_def` adds its goods ("good"), `buy` refuses past `main.hold_cap()` (the ship class's crates, `Skiff.CLASSES`), `sell_good`, `good_pays`, `good_wants`; ui.gd's shop
  shows "hold n/cap" and a Sell row per crate held or good wanted; the HUD in space "hold n/cap". Icon "crate".
  Test: `_test_cargo` ("cargo": a profitable run between systems, the hold fills and refuses, sold for what the
  other outpost pays; picture `cargo_shop.png`).
- In space a skiff nobody pilots holds where it was left (skiff `fly`: vel x0.93 a tick; user, 23 Nov: it floated
  away while he mined), and a "Your skiff" marker points to it while you're off it. A quick right-click's
  `dig_tap` counts down in `_read_local_input` (it counted down only on the planet, so in space one click kept
  mining).

## Ships float (27 Nov; user: "the ship can fly underwater just like above the water. i think we should resolve this somehow")
- main `_skiff_water` (each tick on a planet, under the air's top): how much of the hull is in water (`skiff_wet`, five
  points along the keel and up the middle). As much as is, it's borne up (`SKIFF_LIFT`), can't be driven down under
  it (its downward speed is taken off), and the water drags at it; so it rides on the top. Going in hard it splashes
  (vfx `splash_in`, size 2.6); under way along the top it leaves a wake; deep in, bubbles. Test: in `_test_water`
  (ui section), a ship let fall into a tank rides on the top (ship_float.png).
