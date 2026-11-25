# Wisp Forge: The mage: art, power, health, spells, digging

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## The mage
- Frames (16 x 24) come from `/home/claude/tools/art/mage3.py` via `tools/sprites.py`, which also writes
  `Defs.MAGE_ANCHORS` (where the hat tip, beard, scarf and staff attach in each frame).
- `scripts/mage_rig.gd` simulates the hat tip, beard end and scarf (Verlet chains: rest shape, gravity,
  the body's inertia, air drag) and the staff (an angular spring that points where he casts). overlay.gd
  and title_screen.gd draw them as crisp pixels in the sprite's own transform, with the sprite outline.

## Power, health, spells and digging
- A modest start (user, 21 Nov: "make the starting power of the player lower"): a new journey knows only the
  Wisp Mote (`Defs.SPELLS` "mote": single, 8 mana, slow, short, 6 damage, never touches terrain) and Conjure;
  Spark Bolt is forged (recipe "spark": stone, coal, a little copper). Levitation is forged too (recipe
  "levitate", `items["levitate"]`; needs Wisp, so the Copper Focus first) or comes with the Roc Feather;
  `_update_player`'s `floating` checks it. A save from before ("start" < 1 in progress.json) keeps levitation.
  The test mode starts with spark and levitation (tests.gd sets them), and `_test_start` ("start") checks the gate.
  Digging: the excavation brush's rate is scaled by the staff's tier (`tier_rate` 0.55, 0.8, 1.0, 1.2), so a plain
  staff digs about half as fast. Ores are a little rarer (gen.comp `strata` thresholds +0.015, each planet
  kind's own ore +0.012 in `gpu.build_surface`).
- Spells with "single" in `Defs.SPELLS` cast once a click (user, 21 Nov: the start was too strong): `Mage.cast_latch`
  is set by `_cast` and cleared when the button is let go. Spark Bolt is single, 12 mana, 30 ticks, reaches 220
  cells (it was 4 mana every 9 ticks while held). Test: in `_test_vfx`.
- Each spell has its own cooldown (user, 23 Nov: "healing cooldown locks other spells"): `Mage.spell_cd` (id ->
  ticks), main `spell_ready(m, id)` / `spell_used(m, id, cd)` / `tick_spell_cds(m)` (space.gd's tick too); `cast_cd`
  is now only the short gap after any cast (`SPELL_GAP` 10). The spell bar darkens each slot by its own.
- Digging speed grows (user, 23 Nov: "Mining is a little slow and i dont see anyway to upgrade it"): main
  `dig_speed(m)` = `DIG_TIER` by staff tier (0.55, 0.55, 0.9, 1.3, 1.8) x `DIG_PACE` (0.7 on a planet; asteroids,
  which cost no mana, `dig_speed(m, false)`) x `DELVE` (1.3) per Delver's Rune
  (`items["delve"]`, recipes delve1-3: copper ingots, then wisp ingots and obsidian, then star iron and core;
  each learned on first finding its ingot / star iron) x gear "dig_rate". Used by the excavation brush and
  asteroid mining (space `_mine_at`), not the Remove tool. Test: in `_test_start`.
- Health doesn't regenerate. Healing Draughts (`items["potion"]`, H to drink, `_drink`; forged or found in chests,
  two at the start) and the Mending spell (its scroll is a rare find) heal over a moment (`Mage.heal_left`).
- Falling rock hurts only after falling `ROCK_HURT_FALL` cells and only through your upper half (grid.comp), so
  digging a pit under yourself doesn't.
- The wind (`_update_player`) no longer pushes you while you stand still on the ground; it still slows you
  walking into it and carries you in the air.
