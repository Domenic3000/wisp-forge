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
- The bolt itself (`_draw_projectiles`) is drawn for `_flying()`: the game's `projs`, and in a derelict station or an
  outpost's halls space.gd's `sbolts` too (27 Nov; user: "inside derelict space station when i shot spells i couldnt
  really see the projectiles": they had only their trail there).

## Starfall, made to look like its name (27 Nov, user: "starfall could us a rework for its graphics and sounds. its
sounds th same as getting an item. also the beam of light thing is kind of cool, but maybe it has a flat box at the
bottom which doesnt look very cohesive with the world. maybe we could make it look more like its name?")
- It no longer leaves the staff: main `_star_from` opens it over where you aim (at most `STAR_REACH`, 240 cells,
  from you), aslant from your side, as high as the open air goes (`STAR_H`, 110 cells; under a cave's roof it opens
  just below it; aimed into the ground it traces out of it first), and it falls from there (`_spawn_proj`, the
  spell's speed x1.15). Out in space it still flies from the staff.
- Looks (Defs.SPELL_FX "starfall"): cast "starcall" (a thread of light leaping up off the staff), vfx `star_gate`
  (a faint turning circle, a ring and a glint where it opens), trail "falling" (stardust: gold, rose and violet
  twinkles that hang in its wake and drift down, so its path stays drawn a moment; the head an eight-pointed glint,
  `_xflare`, with a long tail), impact "starburst" (a big glint, a white flash, rings running out, shards thrown up
  that fall back as stardust). No pillar. `_beam` (still Sunlance's and the Sovereign's "nova") narrows to a point at
  its foot now instead of standing on a flat base.
- Sounds (audio.gd): "starcall" (a rising shimmer, echoed) as it's cast, "star_fall" (a falling whistle) where it
  opens, "star_ring" (glassy chimes and glitter) over the blast's boom; it used to play "rare", the item-found chime.
- Test: the vfx check's starfall run (`vfx_starfall_fly.png`, `vfx_starfall_hit.png`).
