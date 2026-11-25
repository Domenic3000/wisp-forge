# Wisp Forge: Building: build mode, furniture, doors, stairs, torches, removal

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Build mode, furniture, doors, stairs, torches, removal
- Build mode (B, `scripts/build.gd`): a catalogue of pieces (back walls painted with brush mode 10, doors,
  scaffold platforms, and props.gd furniture with a seeded design: R rerolls, T mirrors). main.gd's
  `_update_build` previews (overlay draws `build_prev`) and places: furniture and platforms become small
  blueprints in `stamps`, written by `gpu.stamp` just before the next GPU frame. Placed pieces are not anchored,
  so they obey the physics. Digging a door (open or shut) takes it whole into the satchel as a Door item.
  Structures (House, Room, Roof) are put together by buildings.gd's own parts (`Build.structure`, seeded, with
  `builds.rng` saved and restored); [ ] width, - = storeys, T style, R variation; cost from `structure_cost`.
- Furniture is a layer in front of the back wall: each DECOR cell remembers the wall behind it (an index into
  `Defs.BEHIND`, in background bits 22-23 and 28-30; bglayer.comp `behindIdx`/`withBehind`/`decorGone`). stamp.comp
  fills it in as furniture is written (the wall already there, or the nearest wall beside it in the blueprint
  row); burning (react.comp, brush ignition), breaking up (deconstruct) and taking a piece whole give the wall
  back instead of a hole.
- Furniture kinds: a prop's kind (props.gd `KINDS`, 15 at most: table, chair, bed...) travels in blueprint bits 28-31
  and lives in background bits 24-27 of its DECOR cells (`bp.bgv(..., kid)`, `Build.prop_stamp(cells, kid)`), so
  a picked-up piece keeps its name and a bed is known for a bed (`Props.BED`).
- Carried furniture (`Mage.furn`, saved in progress.json): Shift + right-click on furniture takes the whole piece
  (`_pick_up_furniture`: `gpu.read_rect` reads the block, `_furniture_piece` flood-fills cells of the same kind plus
  its torches, a stamp clears them and puts back the back wall it hid). The Wisp Forge forges the indoor pieces
  (`Build.furniture_recipes`, in main's `recipes`); build mode's Satchel tab (`Build.CAT_SATCHEL`) sets them down free.
- Home: F at a bed (`_try_home`; a bed right beside you comes before a door) with a roof over it and back wall
  behind the room above it (`_home_check`) sets `planet_state["home"]`; `_respawn` brings you back there while
  most of the bed is still there (`_home_pos`).
- Collision grid background bits: 0x40 furniture, 0x80 built back wall, 0xC0 a tree (building over one would
  fell it, so build mode refuses; bushes are just covered).
- Doors are 24 tall (buildings `DOOR`, build.gd `DOOR_H`; 30 till 23 Nov, user: "doors are actually a little big and
  take up a lot of space"; GEN_VERSION not bumped, so a world already made keeps its 30-tall doors: door records
  carry their own "h"). An open door's panel is drawn at a slant, `DOOR_PANEL_W` 6 wide (10 before), keyed by
  height (`door_open_<h>`), and BEFORE the villagers (overlay `_draw_all`), so they walk past in front of it.
- Doors (`WOODDOOR`): `_door` in buildings.gd fills a doorway with door cells whose colour variant is their
  part (row << 2 | column) and records it in `door_list`; main.gd keeps `doors` (saved in
  `planet_state["doors"]`). Walking into one opens it (`_door_bump` from `move_body`), F toggles the nearest
  (`_interact`), and a door won't close on someone standing in it. Opening and closing is brush mode 9
  (brush.comp clears or refills the doorway rectangle); the open door is drawn by overlay.gd, swung outward.
- Doors swing either way (away from whoever opens them, `swing`). A door keeps its damage: opening it reads which
  parts are left (`_read_door_cells` -> `d["cells"]`, the part per doorway cell or -1, saved with the doors);
  shutting it stamps back only those parts; fire and blasts take parts off the open panel where they reach
  (`_hurt_open_door`), and overlay.gd draws the panel with those holes, charred at the edges. Less than a third
  left and the door falls apart.
- Staircases (build.gd "stairs" pieces in "Doors & Stairs": Wooden, Stone, Brick; roadmap step 8): steps
  `STAIR_STEP` (4) up and along, so the mage (step_h 5) walks up; a flight `STAIR_BAND` thick under the treads;
  a post of back wall down to the floor every `STAIR_POST` columns and under the last step (support reaches only
  12 cells sideways through planks: a flight held at its foot alone gave way); balusters and a two-thick handrail
  (a one-cell diagonal touches only at corners and fell). `Build.stair_cells` / `stair_stamp` / `stair_cost` (a
  quarter of the flight, a tenth of posts and rail); main `_update_build` "stairs": its foot on the highest ground
  under its first step, it climbs away from you (`build_flip`, T), `build_rise` ([ ] a step, - = a storey,
  8..160); the treads need open space, under them it merges into a hillside (never into anything built,
  `_built_at`); a post through a tree refuses it ("a tree is in the way"). Test: `_test_stairs` ("stairs": on a
  NATURAL slab in open air (a built one woke with the stairs on it and fell), stands, and you walk up it;
  `stairs.png`).
- Taking away precisely (user, 22 Nov: "a precise way to be able to remove materials, flatten the ground, remove
  background decorations without remove the entire background"; physics applies): build mode's Remove tab
  (`Build.CAT_REMOVE` 8, kinds "remove" with "layer" front / back / furn / all, and "flatten" with a fill "mat").
  Remove drags the block shapes (a click is a thick x thick square, one cell at 1): main `_update_remove` previews
  from the collision grid (`_removable_guess`; a cave's natural back wall doesn't show there), and on release
  `remove_cells(m, cells, layer)` reads the block back (`_cells_box`, `gpu.read_rect`), stamps out exactly that
  layer where the staff's tier can (HARD), furniture giving back the wall it hid (`Defs.BEHIND`), and puts what it
  gives in the satchel (`_collect_as`, as the dig's collectAs; five flame cells are a torch). `_wake_round` then
  adds brushes of mode 11 (brush.comp: only the anchor-clearing of digging, within rad + 12) over what was taken,
  so what held on only by it comes down. Flatten (`flatten_plan(a, b)`: the row you press is the new top; solid
  and powder up to `FLAT_CUT` over it cut, open cells down to ground within `FLAT_FILL` under it filled, deepest
  first; `flatten_apply` reads back, cuts what the staff can, fills from the satchel, wakes). Test: `_test_remove`
  ("remove": on a 20-thick natural slab in the air, as a thin slab woken would give way; picture
  `torches_night.png`).
- Torches are one piece (user, 22 Nov: placing torches laid a whole brush of them; "a torch model that placed as one
  piece and gave a nice range of lighting"): `Build.SCONCE` (3 x 7) / `STANDING` (3 x 12) prop rows, flame 't'
  cells (real TORCH) over an iron cup and a wooden handle. main `torch_plan(cell)`: pointed at a built back wall, a
  sconce; else with a floor within 12 under the cursor, standing on it; else a sconce, if a wall, solid beside it
  or a cave (6+ under the surface) holds it. `place_torch(m, p)` (build mode's Furniture tab "Torch", or Conjure
  with torches chosen: one a click, `cast_latch`), `add_torch` -> `planet_state["torches"]` ([x, y, frame] of the
  flame). `_torch_lights` (in `_write_frame_params` BEFORE the light count is set) puts the nearest in view into
  what's left of the 32 point lights, `TORCH_R` 60 across, warm, flickering; `_check_torches` (every 60 ticks)
  forgets one whose flame cell isn't furniture any more in the collision grid. Digging leaves torch cells
  (brush.comp keepBg), deconstruct puts a flame out without giving anything, and Shift + right-click on a torch
  piece (kind 0, 3+ flame cells, at most `TORCH_CELLS_MAX` cells) gives back one torch (`_pick_up_furniture`).
- The build preview is kept (user, 23 Nov: "when i was trying to place furniture depending on where i was placing it
  the fps drops dramatically"): a prop's design (`_design_key`) and its fit (`_fit_key`, `_fit_val`, 12 frames for
  the same piece at the same cell; worked out afresh on a click and after placing), each column's floor in
  `_floor_span` for 8 frames (`_floor_memo`), and a piece that doesn't fit is slid along the floor only once the
  cursor has rested 2 frames (`_rested`) and with `_prop_fit(..., quick)` stopping at its first bad cell: sliding a
  bed through the air, every offset read 40 rows a column.
- Furniture and workshops never overlap (user, 23 Nov: "part of the bed can go behind the kiln"): `_prop_fit`
  refuses cells inside a workshop (`_stations_near`, `_station_over`: "a workshop is standing there") and
  `_station_fit` refuses furniture under it. A village's rooms are mostly furnished, so a workshop goes in few
  spots there; `_test_indoors` judges them by the reasons given.
- Placing a piece where you point (user, 22 Nov: furniture and workshops "said there was no space" on a house's
  floor but went on ledges): `_update_build` tries the cursor spot, then slides along the floor
  (`_slide_offsets`: 2, -2, 4, -4 ... columns) until `_prop_fit` / `_station_fit` say it fits, and when nothing
  does it says why ("It doesn't fit: a door is in the way", "furniture is already there", "no floor under it",
  "it needs level floor"...; `_what_blocks`). Generated rooms are mostly furnished already: take a piece
  (Shift + right-click) to make room. Test: `_test_indoors` ("indoors": village houses and a house built on a slab).
- Straight building (build.gd `SHAPES`, main's `_update_shape`): back walls (Back Walls tab) and solid blocks
  (Blocks tab, `CAT_BLOCKS`) are laid by pressing, dragging and letting go: a line snapped across, up or at 45
  degrees, a filled rectangle, or a frame; G cycles the shape (back walls can also be brushed), [ ] the
  thickness. `Build.shape_cells` / `shape_stamp`; one material per cell; blocks skip cells where someone stands.
- Holding Shift + right mouse keeps harvesting: after a piece is taken whole there is a short pause
  (`Mage.decon_pause`), not a need to let go.
- Background harvest (`_pick_up_furniture`) checks the collision grid for furniture before reading the world back;
  a read that finds none isn't repeated at the same spot (`_pick_miss`).

## Fixes from play (25 Nov): stacks and torches
- Carried furniture of one name is ONE entry in build mode's Satchel tab (`Build.carried_pieces(..., pick)`:
  "items" the Mage.furn indices, "carried" the count, "item" the design shown); R shows the next design
  (main `carried_pick`), `select_carried(idx)` picks a stack showing that item (the tests use it).
- A torch is taken whole by any part: `_pick_up_furniture` starts from the nearest DECOR or flame cell
  (reach at least 3), a flame goes to the piece it burns on (`_flame_holder`); a kind-0 piece whose cup and
  handle are a torch's (`Build.is_torch_stump`, by palette colour) gives a Torch even with its flame partly
  or wholly gone, and a stump carried from before turns back into a torch on load.
- Test: `_test_harvest` ("harvest"; in the full run after `_test_remove`).

## The hand: one way to place what you carry (user, 25 Nov: "currently the conjure spell and the build menu sort of do the same things. when i select something from the inventory i want a unified system somehow? i do like being able to conjur water and sand"; agreed: Conjure places whatever is in your hand, build mode keeps what isn't carried)
- main "the hand": whatever you click in the satchel goes in your hand (`select_material(m)` for a material,
  `hold_carried(what, idx, sk)` for furniture, workshops, torches and doors) and `_to_conjure` picks Conjure.
  `hand_item` ({"what": "furn", "name"} / {"what": "station", "sk"}; {} = the material `mat`), `hand_back` (V),
  `hand_shape` (G: 0 the brush, then Build.SHAPES), `hand_thick` ([ ]). `hand_piece(body)` is the piece the
  building code places, or {} when Conjure's own brush does it: sand, water and other loose stuff, and a solid
  painted with the brush in front. A solid as back wall (only `hand_walls`: planks, logs, stone, brick,
  sandstone, glass) is a "wall" piece (brush mode 10, or a shape); in a shape a "block"; a torch the Satchel
  tab's torch piece; a door the Wooden Door piece; a carried stack its `Build.carried_pieces` entry (R the next
  design, `carried_pick`); a workshop its station piece.
- `_hand_update(m)` (from the tick, before casting) runs `_update_build(m)` with `_hand_over` as the piece
  (`build_piece()` returns it), so the ghost, fitting, sliding along the floor, paying and setting down are
  build mode's. `hand_live` (set each tick) makes left clicks build clicks (never over the UI: a click on the
  satchel only picks). The pieces carry their own "shape" and "thick" (`_update_shape`, `_update_build`'s wall
  branch). Only within the staff's reach (`_reach_len`): shapes are clamped to it, and a click on a piece
  beyond it sets nothing down and the wisp says so. In the pocket, pocket.gd's tick calls `hand_body(m, isle)`
  (`_cabin_edit` with the piece: a solid is always a block there; loose stuff, workshops, torches and doors
  can't go in, the wisp says why); `cabin_cast` takes the cast button there.
- Keys (`_hand_key`, while Conjure is held with something in hand, not in build mode): G, [ ], V for solids;
  R a stack's next design (R doesn't mend then); T mirrors a piece. ui.gd's hand bar (`hand_bar` over the spell
  bar, `_update_hand_bar` from main `hand_hint()`) says what's held and how it goes down, with a shape's cost.
- Build mode's `CAT_ORDER` is [Remove, Doors & Stairs, Structures]: Back Walls, Blocks and the Satchel tab are
  gone (their pieces and code stay: the cabin and tests use them); toggling build mode on leaves a removed tab.
- It looks like magic (user, 25 Nov, "inside the world"): the hand's ghost is drawn in the staff's mana-blue
  light with a faint line of light from the staff tip (overlay `_draw_build_preview`); matter streams out of the
  satchel along the staff to where it goes (`vfx.stream(m, to, col, n)`, from `_conjure`, the wall brush,
  `_update_shape` and `_update_build` as a piece goes down); what's held floats at your shoulder as a little
  block of its colours (overlay `_draw_hand`). Reminders come from the wisp (`wisp_note(text)`: out of
  something, out of reach, too little for a shape, the last of a stack; the same words wait 5 s; overlay draws
  them in the wisp's bubble, over you in the pocket). Dug matter pops up where it was dug (`_pick_acc` from
  `_apply_counts`, flushed every 24 ticks by `_pick_flush` into `popups` [world point, "+3 Sand", colour,
  ticks]; overlay `_draw_popups`, rising and fading over `POPUP_TICKS`).
- Test: `_test_hand` ("hand"; in the full run after `_test_harvest`; pictures `hand_line.png`, `hand_ghost.png`).

## The in-world interface, second pass (user, 25 Nov: "can you think of any other ways to make it feel more inside the world", then "yes all of that sounds pretty great", "alright lets do it")
- The item belt (user, 25 Nov: "is there an easy way to select the recent materials that i conjured other than
  clicking them? and maybe we add a quickbar for satchel items for when we add controller support and to make it
  faster to select the things i use the most"; chose an item belt beside the spells): main `BELT_N` (8) slots over
  the spell bar. `belt_pins()` (saved as `items["belt"]`, "" for a free slot) keep their slot; `belt()` gives
  [id, pinned] per slot, the free ones filled from `hand_recent` (ids "m<material>", "f:<furniture name>",
  "s:<workshop kind>", newest first, `QUICK_N` 12; `_note_hand()` each tick while Conjure is held; a thing already listed keeps its place, so stepping never shuffles the slots) with what you
  still have (`belt_has`). `belt_pin(id)` pins to the first free slot (or over the last) or unpins; right-click
  in the satchel (ui `_on_mat_input`, `_place_id` for the "To set down" ones) or on the belt. Q / E call
  `belt_step(dir)` (from what's in your hand, along the slots you still have; `quick_take(id)` puts it in your
  hand), falling back to `_cycle_material` with nothing on the belt; out in space Q / E still turn the view.
  ui `belt_pan` / `_update_belt` (hidden in build mode, aboard, or when empty; pinned slots have a gold dot, what
  you've run out of is dimmed; `mouse_over_ui` counts it). For a controller later: the D-pad for the belt.
- The satchel's pouch (closed) is sized to what it holds each frame (ui `update_hud`, as the minimap): a
  container never shrinks by itself, so it kept the open satchel's size (user, 25 Nov: "when i close the
  satchel its very big").
- The summoned forge, the grimoire, workshops that show their work, the gem: see crafting.md and ui.md.
- Test: `_test_inworld` ("inworld"; in the full run after `_test_hand`; pictures `forge.png`, `tray.png`).

