# Wisp Forge: Living towns

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Living towns (scripts/towns.gd, folk_art.gd; user, 20 Nov: "towns with people walking around and shops"; then their days, requests, trades per kind)
- buildings.gd `_town` records each village in `towns` ({x0, w, name, ruined, living (not ruined), seed, biome,
  houses: [{role, x0, w, floor (the ground floor's row), ruined}]}; `_cottage` leaves its house in `_house`); a
  standing village gets a name from parts (`town_name`, its own seed: nothing else moves) instead of "Deserted".
- towns.gd (main `towns`, ticked on the planet): `_people` every 30 ticks fills a living village within `NEAR` columns
  (`_fill`) and drops it past `FAR`: a keeper per shop/smithy/tavern/inn (in the middle of its ground floor, always
  there; the smith throws sparks by day) and its residents (two per home, one living over each other house, that
  house their `job`; `MAX_FOLK`), each put where `want_place(v, hour)` says: home asleep 22-6, some still in bed
  before 7, the job 9-16 (three in four), the tavern of an evening if there is one, else the street. `hour_at(p)`
  is the local hour (noon = sun overhead; `time_for_hour` for tests). main `Villager` (a Body): seed -> look
  (folk_art.gd `frames`: a 19 x 21 figure from parts, the same draws from the seed as the old 13-wide one; every
  frame is the same parts in a pose from `POSES`, overlay caches "folk_<seed>_<frame>" and `_folk_frame` picks:
  user, 26 Nov, "villagers are still basic animations": a four-step walk with the body down a pixel at each
  stride, running from a foe with both arms up, talking with a hand out then at the chest, a keeper waving as you
  come within 60 cells (`greet_t`), the smith's hammer raised and struck in time with towns.gd's sparks by day,
  standing with a slow breath and a blink, eyes shut lying asleep ("sleep")) and name
  (`name_for`); `inside` (a house dict or {} = `STREET`), `job`, `asleep`, `fade` (`_step`: they fade out at a
  house's side and in at `fade_to`, going in, out, or PAST a house in the way: houses block the street; stuck for
  90 ticks they step to where they're going). `_walk`: keepers face you; in the street residents wander the
  village, turn at walls and drops, run from foes; indoors they potter about the room; overlay draws a sleeper's
  drifting "z"s. F (main `_interact`, after chests): `talk` — a keeper takes a letter that's for them
  (`_deliver_to`) or opens the shop (state "shop", the game waits; ui.gd `show_shop`, F/Esc leave), the asker deals
  with their request, anyone else says `line_for` (a greeting and a rumour: the nearest living guardian and its
  lair, a crypt, this world's ore, its hazard and ward, the village's shops, or village talk; sleepers grumble),
  drawn as a speech bubble (overlay `_bubble`).
- Requests: one resident per village is the asker (`asker_index`: from the village's seed and `planet_state["req_n"]`
  (done there), so it moves on), marked by overlay `_folk_mark` from `mark_of` (gold "!" offer, grey "?" under way,
  gold "?" done). `make_request` (seeded the same way): "fetch" (`Defs.FETCH` material and count), "hunt" (2-4 of
  a `Defs.creatures_of(village biome)`, counted by `on_kill` from main `_kill_enemy`), "deliver" (a letter to the
  shop or tavern keeper of another living village). F shows it, a second F `take`s it (into
  `planet_state["requests"]`, `Defs.MAX_REQUESTS` at once; the HUD lists them by `short`), talking to them again
  hands it in (`_finish`: coins, a Healing Draught one time in three). Test: `_test_requests`.
- Trade: `shop_def` = `shop_def_for(role, planet kind, planet seed)`: `Defs.SHOPS[role]` ("sell": give/potion/meal/
  rest/chart/item (an `items` key, a ward)/heat_ward/spell; "buy": material -> [how many, coins]; the smithy also
  buys every world's ore) plus `Defs.KIND_TRADE[kind][role]` (each world's ward for its danger, its fare, the Heat
  Ward on volcanic, Silver and the Scroll of Mending in a realm) and, at the smithy of a world with its own ore, an
  imported ore (`Defs.IMPORT`, picked by the seed) and a better price for its own (`Defs.OWN_ORE`, "own_ore").
  `buy`/`grant`/`owned` (a ward you have shows "yours")/`sell`; coins in `items["coins"]` (from chests, guardians
  60, wardens 30, requests, selling). "chart" puts the lairs and crypts in `planet_state["charted"]`, which the map
  draws; villages you've been to (`planet_state["towns_seen"]`) are on the map too.
- Sleep: buildings.gd `_furnish` records each bed it places (`_beds`: {c, w, row, flip}, from `_place_prop`'s
  `_last_flip`) into its house's "beds" (no rng drawn, so layouts don't move); towns.gd gives each resident one
  (`v.bed`). Asleep at home they `_lie_down` (in their bed if the collision grid still has furniture there, the
  head at the pillow end; else on a bedroll on the floor), `lying` (no physics), `_get_up` at `wake_at` in the
  morning; overlay `_lying` draws them turned a quarter (whole pixels) under a quilt, "z"s from the head.
- Lying on what's there (user, 23 Nov: "villagers are floating in their sleeping bags, one was like inside the roof
  triangle"): `_settle_sleeper` (towns.gd `tick`, once a sleeper is within the collision grid; `Villager.lie_ok`)
  puts someone in bed on the top of the furniture over the bed's middle (3.5 over it) and a bedroll on the floor
  `_floor_below` finds (4.5 over the floor's top; overlay `_lying` draws the roll's underside there), each only
  where `_headroom` has open rows over it, else the floor further down. Checked in `_test_town_days`.
- Keeping apart (user, 21 Nov: "villagers standing on top of each other"): `_spot_in`, the street placement and
  `_new_goal` pick spots clear of others (`_taken` / `_clearance`, which counts where someone stepping through a
  door is about to come out, `_spot_of`, and chests); someone standing still on top of another steps aside
  (`_crowd_side`, checked every 12 ticks). A sleeper never lies over a chest: a bed with one in front of it
  (`_chest_near`), or already taken, means the floor, and a bedroll goes on the roomiest bit of floor. The overlay
  draws the folk before the chests (`_draw_folk`), so a chest is never hidden behind one.
- Memory: `planet_state["folk_known"][seed]` = {met, helped}, `["town_rep"][town seed]` = {n, last}: `_hello`
  (a stranger introduces themselves, a friend you helped greets you so, a village talks of what you did),
  `knows` (overlay name tags of folk you've met), `price_of` (5% off a village's shops per request done there,
  a quarter at most; the shop shows it).
- Tests ("towns"): `_test_towns` (walk, talk, trade), `_test_town_days` (home, in bed and asleep at night, out in
  the morning; a picture `town_night.png`), `_test_requests` (and being remembered), `_test_kind_trade` (every
  kind's stock is real, and its danger's ward is sold).

## Rebuilding and reloading
- Villages rebuild (scripts/rebuild.gd, towns.gd `rebuild`; user, 23 Nov: "if the village gets destroyed ... the
  villagers should be able to build their houses back. not build infinite houses"): every living village's house
  keeps its finished blueprint (buildings.gd `_finish(bp, build, house)` -> `house["struct"]`; on loading too: a
  "home_only" job finishes just those). Every `CHECK_EVERY` a house of the nearest village is read back
  (`request_rect`), and with more than `DAMAGED` (8%) of its built cells gone (`_missing`: front solids but doors,
  torches, furniture, fills; back walls but furniture and torches) its folk put them back a course at a time,
  bottom first (`_work`: front cells fill-only, never where someone stands), reading again every 4 s, until whole
  (or a pass lays nothing); then it rests `RESTS`. Never furniture, never a new house. Test: `_test_rebuild`
  (in "towns"; picture `town_rebuilt.png`).
- A plan made again (on loading) is the plan that was built: `_finish` draws the roughening's seed whether or
  not it builds. (It drew only when building, so a loaded world's towns, guards, wardens and labels drifted from
  the first structure on: villagers set out for houses that weren't there.) Checked in `_test_rebuild`.

## Town guards (26 Nov, the roadmap's "town guards", built while the user was away)
- towns.gd `_fill` puts out `guard_count(t)` guards (`GUARDS_MIN` 1, +1 for four houses or more, +1 for each house
  grown, at most `GUARDS_MAX` 4): villagers with role "guard" (folk_art.gd: an iron kettle helmet, a tabard from
  `TABARD` with a pale cross, mail, a spear upright; "jab" thrusts it level), idx negative (never the asker).
  `_walk` hands them to `_guard`: they never sleep; they walk the village end to end (a while at each end), through
  a house in the way as residents do, carrying a light after dark; `_guard_target` (the nearest foe within
  `GUARD_SIGHT` inside the village or `GUARD_ROAM` past its ends: never a boss, nor prey or the neutral unless
  provoked) draws them to it, and in reach the spear strikes for `GUARD_HIT` every `GUARD_EVERY` ticks
  (`strike_t` on main's Villager; overlay shows "jab"). They can't be hurt. `line_for` gives a guard's lines
  (`GUARD_LINES`). Test: `_test_guards` (tests/towns.gd, section "guards"; after `_test_towns`).
- (26 Nov, user: "the town gaurds get stuck rapidly flipping left and right when im near them") a guard ignores a
  foe more than `GUARD_HIGH` (30) above or below it (in a cave under the street, up in the sky: it can't get at
  it, and standing over it its side flickered every frame), only turns once a foe is `GUARD_TURN` (3) to one side,
  and stands still under one it can't reach. The test also puts a foe in a cave right under a guard.
- (26 Nov, user: "villagers rotate with the player up and down direction instead of the world") overlay
  `_draw_folk` draws them with `_sprite`'s `turn` (with the world under them, like the open doors), and `_lying`
  turns a sleeper and the bedroll the same way.

## Villages that grow (26 Nov, the roadmap's "a village that grows as you help it")
- `_finish` (a request done) calls `_maybe_grow`: at `GROW_AT` (2, 5, 9) requests done in a village
  (`planet_state["town_rep"]`) its next house is planned: buildings.gd `grow_house(t, k)` (its own rng from the
  village's seed and k; a home `_cottage` at one end, alternating, a few tries outward; planned and finished for
  its cells only, `finish_all`, so the house has its "struct"; the village's x0/w widened over it). It's marked
  "new" and rebuild.gd builds it as it rebuilds a house (`look_at` -> `_start`): first `_clear_site` stamps away the
  trees, roots and undergrowth where it will stand (from the read), then course by course, its furniture too
  (`_want_back(v, furnish)`), and at `_done` a family moves in (`move_in`: two residents, and a guard if one's due).
  `planet_state["grown"]` (village seed -> houses grown) is planned again on loading (`replay_growth`, from main
  `_spawn_guardians`), in order, so the houses come out where they were. Test `_test_guards`: grown, built (~2300
  ticks), furnished, moved into, widened, and planned again the same.
