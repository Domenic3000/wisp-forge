# Wisp Forge: Physics: rigid chunks, standing on the curved world, platforms

Notes for development sessions on this part of the game. The rules that apply everywhere are in
`CLAUDE.md` at the top of the repo; read it first.

## Chunks, standing, platforms
- Rigid chunks (`scripts/chunks.gd`): grid.comp reports one felled-tree cell (counts[59]/[60]: a plant cell whose
  support reached 62) and one creaking block (counts[56]/[57]) per mage; `detect` reads the world around it
  (`gpu.read_rect`: `shaders/rectread.comp` copies just the rectangle into a small buffer, read back in one go), takes the loose cells out with a stamp and makes
  rigid bodies: a tree's detached cells (CPU flood from wood on the ground), or a building piece (loose blocks +
  the loose back walls and furniture joined to them) split along staggered, jittered lines. `update` steps them
  against the collision grid and each other (one averaged contact, impulse, friction); hard landings knock pixels
  off as chips and rubble (`_splinter`; a tree loses at most 1/40 of its pixels a landing, a building piece 1/6:
  26 Nov, a felled tree splintered away too much of its wood); hits on mages/foes hurt (`_strike`). A tree collides by its wood only; its crown
  edge (`soft`) crushes: leaves that touch ground are knocked off as drifting leaf particles (`_crush`, once a
  frame), so the crown flattens instead of sinking. At rest (it hasn't moved or turned more than ~1 cell for 20
  frames) `_settle` writes it back with a raw stamp (stamp.comp mode 1: two words a cell, each layer only where
  it is empty): blocks unanchored (keeping their own built flag); a tree's wood in FRONT as ANCHORED logs (no
  creaking apart), its crown in the background as a fallen plant (id 0xF000.., bush rules: held by any part
  resting on something), pruned to the leaves joined to the logs (`_prune_crown`). Felled scraps under
  SMALL_TREE cells just flutter away. A piece only hurts after a ROCK_HURT_FALL-cell fall, through the upper
  half (as falling rock). plants.comp lets felled trees wait (0.002 a pass) for the CPU; pieces nobody lifts out
  still crumble the old way. In test mode each lift-out prints a `[chunks]` line. Pixel colours come from the picture on screen divided by the light.
  `save_world` settles everything still moving first.
  A tree's still-standing cells are found the way plants.comp grounds them (`_grounded`: wood on solid, on
  settled powder or liquid), and what came loose is split into its joined-up pieces (`_spread` floods a byte
  mark array); each piece falls on its own, scraps under SMALL_TREE flutter off as leaves.
- Chests at rest only fall after CHEST_LET_GO frames with nothing found up to 3.5 cells under them (the
  collision grid tilts with the planet's curve as the mage walks, so a single check flickered).
- Standing on the curved world through the flat grid (user, 21 Nov: foes bobbed as you walked): far from you the
  grid's rows sit up to half a cell off the world's, and that drifts as you walk, so a body resting on the grid is
  up to half a cell into or over the ground's top. `move_body`: `_unsink` first takes a body out of a sliver it sank
  into (it used to be lifted a whole cell, by a step "up" or the unstick, then fell back for frames), a fall ends
  right on the row it met (`_rest_on`), and a body standing last frame is put straight down on ground up to 1.05
  below (`was_ground`). Drawing: overlay `_feet` puts a grounded body's feet on the top of the world cell the grid
  has under it (`main.ground_top`), and `_sprite` hangs a frame by its lowest opaque row (`_gap_under`, not doors
  or chests), so frames with empty rows under the feet don't float; birds on the ground are drawn by their feet.
  The gap is worked out from the Image as a texture is made (`_make_tex`, `_image_gap`; Defs sprites from their
  rows): never `get_image()` on a texture while drawing, it stalls the renderer.
- `SCAFFOLD` is a one-way platform: `gsolid` ignores it, `move_body` lands on it from above
  (`platform_below`), and down + jump drops through (`drop_t`).

## Fire (react.comp, move.comp; tamed 27 Nov)
- How it works: a burning cell is FIRE with its life in bits 16-23 (the material's `fuel`, in ticks). Each tick a
  burnable cell beside fire catches with its material's `ign` chance (defs.gd); a background plant or wall behind
  open air catches at 0.6x that (a room's back wall is one sheet of fuel), from lava at 2x / 1.2x. A flame rises
  (and drifts sideways) like a gas only in its last 12 ticks (move.comp `riser`); it was 24, and climbing ~40 cells
  it lit every crown and back wall it passed.
- Why (user, 27 Nov: "fire is a little crazy. it will burn whole houses and forest down from one fireball"; then
  "i like the forests dont take away from the fullness"): with the old numbers each burnable cell passed fire on
  99%+ of the time, so any fire crossed every connected house and forest. Now `fuel` x `ign` is kept low enough
  that fire burns what it hits and some way round it, then dies down: wood 70 / 0.02, planks 50 / 0.012, leaves
  14 / 0.09, grass 12 / 0.15 (the others in defs.gd's material list, with a note). Forests keep their density;
  only fire changed.
- Measured offline with /home/claude/tools/fire_sim.py (a model of these rules on a forest and a house), then in
  the game by `_test_fire` (tests/building.gd, section "fire"): one fire blast in a 64x44 plank house on level
  ground and one at a forest tree. With the old fire: the whole house in 8 s and 77% of the forest round the tree;
  now about a fifth of the house (its roof and a patch of back wall) and about 5% of the forest.

## Steady feet (27 Nov)
- overlay `_steady_feet`: each creature and villager remembers its world column and the ground it was drawn on; a
  cell's flicker of the grid (sampled at your exact place) under one standing still no longer moves it (user: "the
  lizards in the desert move up and down a few pixels as the player moves").
