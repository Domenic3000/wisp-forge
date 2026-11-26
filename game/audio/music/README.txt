Music for Wisp Forge (made with Suno). Drop .mp3 or .ogg files in this folder (in a built game, the "music"
folder beside Wisp Forge.exe). A track's name decides when it plays; nothing else needs setting up.

WHEN A TRACK PLAYS (name it by the moment; add _2, _3 ... for more than one, and they take turns)
  title*            the title screen
  surface_day*      on a planet's surface by day
  surface_night*    on a planet's surface by night
  village*          in a living village by day                      (none yet: plays surface_day)
  underground*      in the caves                                    (from 40 cells down)
  deep*             in the deep, near the heart                     (from 220 cells down)
  boss*             a guardian, warden or Vulkhar awake near you
  space*            out in space                                    (none yet: plays surface_night)
  pocket*           in your ship's pocket dimension                 (none yet: plays surface_night)
  outpost*          docked in a trading outpost's halls             (none yet: plays space)
  derelict*         in a derelict station's or wreck's halls        (none yet: plays deep)

ONE KIND OF PLANET: the kind first, then the moment
  volcanic_surface_day.mp3, frozen_surface_night.mp3, ocean_underground_2.mp3 ...
  kinds: temperate, volcanic, ocean, desert, marsh, frozen, wild, realm, abyss (the deep ocean world), giant (the gas giant)

ONE BIOME (on any planet): "biome_", the biome, then the moment
  biome_desert_surface_day.mp3, biome_forest_underground.mp3, biome_tundra_surface_night.mp3 ...
  biomes: forest, jungle, marsh, tundra, mountain, savanna, desert, grove (mushroom grove), ashland, ocean

The most particular track there is plays: the biome's own, then the planet kind's, then the common one,
then the moment's fallback (shown above). Walking into a biome with no track of its own keeps what's playing.

HAVE NOW: title, surface_day, surface_night, underground, deep, boss.

SUNO PROMPTS for what's missing (instrumental, loopable; name the file as shown). Most wanted first.

  space.mp3                   slow cosmic 16-bit ambient, shimmering arpeggios, deep sub pads, weightless and vast, sparse melody
  pocket.mp3                  dreamy 16-bit ambient lullaby, music box and soft glass bells, warm pads, a safe floating home in a violet nebula, gentle and slow
  village.mp3                 cozy 16-bit village theme, plucked lute and recorder, light hand drum, warm and friendly, market morning
  outpost.mp3                 16-bit space cantina, laid-back synth bass groove, muted trumpet-like lead, soft hum of a busy station, relaxed
  derelict.mp3                tense 16-bit sci-fi horror ambient, low metallic drones, distant clanks, sparse eerie bleeps, dread building slowly
  volcanic_surface_day.mp3    ominous 16-bit chiptune, rumbling low synth drones, slow taiko hits, crackling fire texture
  ocean_surface_day.mp3       airy 16-bit chiptune, rolling arpeggios like waves, soft flute lead, open sea, calm
  desert_surface_day.mp3      16-bit desert chiptune, plucked oud-like synth, hand percussion, heat-haze pads, sparse
  marsh_surface_day.mp3       murky 16-bit ambient, bubbling synth, low clarinet, frog-like plucks, foggy and mysterious
  frozen_surface_day.mp3      icy 16-bit ambient, glassy bells, slow choir pads, howling wind, lonely and vast
  wild_surface_day.mp3        primal 16-bit adventure, tribal drums, bold horn melody, lush jungle texture, energetic
  realm_surface_day.mp3       regal 16-bit medieval chiptune, lute and recorder melody, light marching snare, warm villages
  abyss_surface_day.mp3       vast 16-bit underwater ambient, slow whale-song synth, deep pulsing bass, glimmering bioluminescent arps, crushing depth and wonder
  giant_surface_day.mp3       soaring 16-bit sky theme, wind-swept pads, distant thunder, airy pan flute, floating isles above an endless storm
  biome_desert_surface_day.mp3     sun-bleached 16-bit desert, slow plucked strings, shaker, shimmering heat, lonely dunes
  biome_jungle_surface_day.mp3     humid 16-bit jungle, marimba-like plucks, layered hand drums, bird-call synth, lush
  biome_tundra_surface_day.mp3     quiet 16-bit snowfield, celesta and soft pads, crisp and cold, slow
  biome_mountain_surface_day.mp3   heroic 16-bit highlands, open fifths, horn-like lead, wind, wide vistas
  biome_grove_surface_day.mp3      whimsical 16-bit mushroom forest, bubbly synth plucks, music box, glowing and strange
  biome_marsh_surface_day.mp3      damp 16-bit bog, slow bass clarinet, dripping plucks, mist
  biome_forest_underground.mp3     glowing 16-bit cavern, soft bell arpeggios, gentle drip percussion, roots and crystals, curious
  biome_desert_underground.mp3     buried 16-bit tomb ambient, low drones, sparse plucked strings, ancient and dusty

Night versions (kind_surface_night.mp3, biome_<biome>_surface_night.mp3) work the same way: the day prompt,
slower and quieter. Under water every track is muffled by itself; no track is needed for it.
