# Wisp Forge: Spell effects

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Spell effects (scripts/vfx.gd; user, 21 Nov: "epic vfx for the spells")
- main `vfx` (a Node2D in `pix` after the overlay, its child `glow` additive via CanvasItemMaterial): its own
  particles in packed arrays (`spawn(kind, pos, vel, life, c0, c1, s0, s1, add, grav, drag, f)`; kinds DOT, STREAK,
  GLOW (banded halo texture), SMOKE, RING (whole-pixel circles), SHARD, FLARE, BOLT (jagged, re-jittered), BEAM,
  RUNE (a turning magic circle), CHUNK; `MAX` 2200, swap-removed), `light(p, r, col, ticks)` (fading lights into
  `game.lights`), `screen_flash`. Everything in whole game pixels. `tick()` with the game's ticks.
- What a spell looks like is DATA, `Defs.SPELL_FX` (core, glow, glow_r, "trail", "impact", "cast" styles); main
  calls `vfx.cast` (`_cast`), `trail` (each tick a projectile in SPELL_FX flies; the overlay skips drawing those),
  `impact` (`_impact`, then returns), `blast` (every `_explode`: fireball, quake, starfall, meteors, lava bombs),
  `blink`, `mend`. Test: `_test_vfx` ("vfx": each spell cast on fresh ground, pictures `vfx_<spell>_fly/_hit.png`,
  particles die away, the effects' worst frame under 4 ms).
