'use strict';
// Biomes (surface + the cave biome beneath them) and planet archetypes.

const BIOMES = {
  forest: {
    name: 'Whisperwood', under: 'Glowroot Caverns', off: 0, amp: 14,
    top: M.GRASS, topD: 1, sub: M.DIRT, subD: 12, weather: 'rain', flora: 'trees', ug: 'fungal', spawnOK: true,
  },
  desert: {
    name: 'Sunscar Dunes', under: 'Prism Hollows', off: 14, amp: 9,
    top: M.SAND, topD: 5, sub: M.SAND, subD: 14, weather: 'clear', flora: 'cactus', ug: 'crystal', spawnOK: true,
  },
  marsh: {
    name: 'Murkfen Bog', under: 'Glowroot Caverns', off: 22, amp: 4,
    top: M.MUD, topD: 3, sub: M.DIRT, subD: 8, weather: 'rain', flora: 'reeds', ug: 'fungal', pond: true, spawnOK: true,
  },
  mountain: {
    name: 'Greyspire Peaks', under: 'Frostvein Grottos', off: -75, amp: 48,
    top: M.STONE, topD: 0, sub: M.STONE, subD: 0, weather: 'snow', flora: 'pines', ug: 'ice', snowcap: true,
  },
  tundra: {
    name: 'Rimefrost Steppe', under: 'Frostvein Grottos', off: -6, amp: 8,
    top: M.SNOW, topD: 3, sub: M.DIRT, subD: 8, weather: 'snow', flora: 'pines', ug: 'ice', spawnOK: true,
  },
  ashland: {
    name: 'Cinderwaste', under: 'Smoldering Vaults', off: 6, amp: 20,
    top: M.ASH, topD: 4, sub: M.STONE, subD: 0, weather: 'ash', flora: 'dead', ug: 'ember', lavaLake: true,
  },
  ocean: {
    name: 'Drowned Shelf', under: 'Abyssal Grottos', off: 62, amp: 18,
    top: M.SAND, topD: 3, sub: M.SAND, subD: 8, weather: 'rain', flora: 'kelp', ug: 'fungal',
  },
};

const PLANETS = [
  {
    name: 'Verdance', desc: 'A temperate cradle world of woods, bogs and peaks.',
    biomes: ['forest', 'marsh', 'tundra', 'mountain', 'desert', 'forest', 'mountain'],
    magma: 560, sea: null, rich: 1, lava: 1, sky: [1, 1, 1],
  },
  {
    name: 'Cindrel', desc: 'A volcanic world. The mantle is close to the surface.',
    biomes: ['ashland', 'mountain', 'desert', 'ashland', 'ashland'],
    magma: 430, sea: null, rich: 1.4, lava: 2.6, sky: [1.25, 0.78, 0.7],
  },
  {
    name: 'Thalassa', desc: 'A water world: scattered islands over drowned shelves.',
    biomes: ['ocean', 'forest', 'ocean', 'marsh', 'ocean', 'tundra', 'ocean'],
    magma: 580, sea: 26, rich: 1.2, lava: 0.8, sky: [0.85, 1.05, 1.15],
  },
  {
    name: 'Sere', desc: 'An endless desert world baked under twin suns.',
    biomes: ['desert', 'mountain', 'desert', 'desert', 'ashland'],
    magma: 520, sea: null, rich: 1.5, lava: 1.5, sky: [1.15, 1.0, 0.8],
  },
  {
    name: 'Fenhollow', desc: 'A drowned marsh world with deep black lakes.',
    biomes: ['marsh', 'forest', 'marsh', 'tundra', 'marsh'],
    magma: 560, sea: 18, rich: 1.6, lava: 1, sky: [0.85, 1.0, 0.85],
  },
];

const ROMAN = ['', ' II', ' III', ' IV', ' V', ' VI', ' VII', ' VIII', ' IX', ' X'];
function makePlanet(i) {
  const base = PLANETS[i % PLANETS.length];
  const cycle = Math.floor(i / PLANETS.length);
  return Object.assign({}, base, {
    index: i,
    seed: 1337 + i * 7919,
    name: base.name + (ROMAN[cycle] ?? ' ' + (cycle + 1)),
    rich: base.rich * (1 + cycle * 0.25),
  });
}
