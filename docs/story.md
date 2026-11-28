# Wisp Forge: The story and its scenes

## The story (28 Nov)
User, 28 Nov: "I would like maybe some kind of story and build up with a big bad to drive the player through the
game. a reason to go forward. I think maybe we need a reason. maybe there is something consuming the universe. or
something deep at the center of the universe that is waiting for you. that you find hints and some feeling for the
characters." Cutscenes: "Both" (illustrated panels and moments in the world), "Short and skippable". The story of the
planets "should be part of a greater story of exploring the universe". Then: "the darkness" for the big bad, and keep
the twist.

- **The Hush**: a living dark at the heart of the galaxy that eats the light of stars and the songs of worlds. Where
  it has been, stars go quiet. It's seen in the night sky, a dark patch ringed with violet, larger each chapter.
- **The Choir**: mages who sang worlds whole (the Worldsong that mends the land is their magic, still faintly
  running). They bound a **seal** into the heart of every world to hold the Hush back. Each world's **keepers** guarded
  its seal; their tombs are the crypts (a dungeon's warden is a fallen keeper). **Vulkhar** is the forge-golem the
  Choir made to keep Verdance's seal; a thousand years of the Hush whispering through the stone have turned him.
- **The wisp**: the last spark of the Choir, its memory broken. Each keeper's tomb gives back a verse of it.
- **The twist** (kept for later chapters): the wisp once answered the Hush's voice and helped open a seal. Vulkhar's
  last words hint at it ("YOU REMEMBER... YOU WERE THERE").
- Why you go on: the cores you harvest are the seals; carried away, the Hush can't feed on them. Then the dark is
  followed star by star to where it began.
- Still to come: each world's heart boss as another corrupted guardian with a piece of the story; the exotic worlds
  as the Choir's four great works; dreams in your bed; villagers' rumours of dark stars; the twist revealed.

## How the code does it
- `scripts/story.gd` (main `story`): what plays when, and the words. `opening(after)` on a new journey (main `start`,
  before the first hints, `_first_hints`); `warden_fell(at)` from main `_warden_falls` (VERSES, the first world's four
  in order, then VERSE_AFTER); `vulkhar_wakes(e)` as he wakes (the golem's AI), `vulkhar_falls(e)` as he falls.
  Kept in items["story"] {opening, verses, vulkhar_met, vulkhar_fell}. `hush_level()` = 0.3 + 0.1 a chapter (to 0.9)
  goes to the sky in P.p[124].z (render.comp `skyColor`: the patch is a way round from the sun, near the moon, so it
  rises and sets through the night). `enabled` is off in the test mode but in its own check.
- `scripts/cutscene.gd` (main `cutscene`, a CanvasLayer): plays a list of steps while main's state is "scene" (the
  world waits: `_gpu_frame` paused, no ticks; the HUD hidden). Steps: {"panel", "text"} a picture from
  `story_art.gd` with its caption typed; {"say", "text", "at", "lift", "style", "pitch", "cam"} a bubble in the
  world (overlay draws `cutscene.bubbles()`; the quest's own wisp bubble is held back) with letterbox bars and the
  camera easing to the speaker; {"wait", "cam"} a held shot. A click, Space, Enter or F finishes the words or goes on
  (`advance`); Esc skips the scene (`key`); a step goes on by itself when its words have been up long enough
  (`_hold`). speech.gd's EMBER style (dark with an ember edge) is for the keepers and Vulkhar.
- `scripts/story_art.gd`: the panels, grown in code at 320 x 180 from parts (banded skies, stars, the Hush, ridges,
  pines, a campfire, the mage, the wisp's glow): "hush", "fall", "camp", "wisp".
- The wisp's lines give reasons now: places.gd's guidance names the heart's seal and calls a dungeon a keeper's tomb
  with something of the wisp's inside; quest.gd's Vulkhar and core steps speak of the seal.
- Test: `_test_story` ("story"; in the full run after "loop"): the opening's four panels (pictures
  story_panel_1..4.png), the world waiting, the hints after; it plays once; a verse in the world going on by itself
  (story_verse.png); Vulkhar's ember words, Esc skipping, his last words (story_vulkhar.png); kept in the save; the
  Hush in a midnight sky (story_hush_sky.png).
