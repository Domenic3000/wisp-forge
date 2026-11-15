'use strict';
// ---------------------------------------------------------------------------
// The Wisp Forge: recipes for building materials, spells and staff upgrades.
// Costs are material ids -> counts pulled from the satchel.
// ---------------------------------------------------------------------------
const RECIPES = [
  // building materials
  { id: 'plank', cat: 'Materials', name: 'Planks ×4', cost: { [M.WOOD]: 2 }, give: { [M.PLANK]: 4 }, desc: 'Flammable building boards.' },
  { id: 'brick', cat: 'Materials', name: 'Bricks ×4', cost: { [M.STONE]: 3, [M.DIRT]: 1 }, give: { [M.BRICK]: 4 }, desc: 'Tough blocks. Need a Copper Focus to carve again.' },
  { id: 'glass', cat: 'Materials', name: 'Glass ×4', cost: { [M.SAND]: 4, [M.COAL]: 1 }, give: { [M.GLASS]: 4 }, desc: 'See-through blocks for windows and tanks.' },
  { id: 'obsid', cat: 'Materials', name: 'Obsidian ×4', cost: { [M.LAVA]: 4, [M.WATER]: 4 }, give: { [M.OBSIDIAN]: 4 }, desc: 'Quench lava in water. Very hard.' },
  // spells
  { id: 'fireball', cat: 'Spells', name: 'Fireball', cost: { [M.COAL]: 12, [M.COPPER]: 6 }, spell: 'fireball', desc: SPELLS.fireball.desc },
  { id: 'tide', cat: 'Spells', name: 'Tidecall', cost: { [M.WATER]: 40, [M.COPPER]: 4 }, spell: 'tide', desc: SPELLS.tide.desc },
  { id: 'frost', cat: 'Spells', name: 'Frostbite', cost: { [M.FROST]: 10, [M.SNOW]: 10 }, spell: 'frost', desc: SPELLS.frost.desc },
  { id: 'quake', cat: 'Spells', name: 'Quake Orb', cost: { [M.WISP]: 10, [M.STONE]: 40, [M.COAL]: 10 }, spell: 'quake', desc: SPELLS.quake.desc },
  // upgrades
  { id: 'tier2', cat: 'Staff & Body', name: 'Copper Focus', cost: { [M.COPPER]: 20, [M.STONE]: 20 }, req: () => player.tier === 1, apply: () => { player.tier = 2; }, done: () => player.tier >= 2, desc: 'Staff tier 2: carve Deepstone, Ember, Wisp ore, Brick and Lava.' },
  { id: 'wide', cat: 'Staff & Body', name: 'Wide Excavation', cost: { [M.COPPER]: 10, [M.CRYSTAL]: 10 }, apply: () => { player.digR = 4; }, done: () => player.digR >= 4, desc: 'Bigger excavation radius.' },
  { id: 'vital', cat: 'Staff & Body', name: 'Vital Bloom', cost: { [M.SHROOM]: 16, [M.LEAF]: 12 }, apply: () => { player.maxHp = 150; player.hp = 150; }, done: () => player.maxHp >= 150, desc: '+50 max health.' },
  { id: 'mana', cat: 'Staff & Body', name: 'Mana Crystal', cost: { [M.WISP]: 8, [M.CRYSTAL]: 8 }, apply: () => { player.maxMana = 170; player.manaRegen = 0.32; }, done: () => player.maxMana >= 170, desc: '+70 max mana and faster regeneration.' },
  { id: 'ward', cat: 'Staff & Body', name: 'Heat Ward', cost: { [M.EMBER]: 15, [M.FROST]: 10, [M.OBSIDIAN]: 6 }, apply: () => { player.heatWard = true; }, done: () => player.heatWard, desc: 'Survive the mantle heat. Lava burns far less.' },
  { id: 'tier3', cat: 'Staff & Body', name: 'Obsidian Focus', cost: { [M.OBSIDIAN]: 15, [M.EMBER]: 12, [M.WISP]: 6 }, req: () => player.tier === 2, apply: () => { player.tier = 3; }, done: () => player.tier >= 3, desc: 'Staff tier 3: carve Obsidian and Magma Rock.' },
  { id: 'tier4', cat: 'Staff & Body', name: 'Core Siphon', cost: { [M.OBSIDIAN]: 20, [M.WISP]: 15 }, req: () => player.tier === 3 && player.items.heart, reqText: 'Needs Obsidian Focus + the Ember Heart (defeat the mantle guardian)', apply: () => { player.tier = 4; }, done: () => player.tier >= 4, desc: 'Staff tier 4: harvest the Planet Core itself.' },
  // endgame
  { id: 'gate', cat: 'World Gate', name: 'Forge the World Gate', cost: { [M.CORE]: 40, [M.WISP]: 20 }, req: () => player.tier >= 4, reqText: 'Needs the Core Siphon', gate: true, desc: 'Fold space and travel to the next planet. Your satchel, spells and staff come with you.' },
];

function recipeDone(r) {
  if (r.spell) return player.known.includes(r.spell);
  if (r.done) return r.done();
  return false;
}
function recipeAffordable(r) {
  for (const k in r.cost) if (player.inv[k] < r.cost[k]) return false;
  return true;
}
function recipeUnlocked(r) { return !r.req || r.req(); }

function craft(r) {
  if (recipeDone(r) || !recipeUnlocked(r) || !recipeAffordable(r)) return false;
  for (const k in r.cost) player.inv[k] -= r.cost[k];
  if (r.give) for (const k in r.give) player.inv[k] += r.give[k];
  if (r.spell) { player.known.push(r.spell); player.known.sort((a, b) => SPELL_ORDER.indexOf(a) - SPELL_ORDER.indexOf(b)); toast(`New spell learned: ${SPELLS[r.spell].name}`, '#ffd23a', 4000); }
  if (r.apply) { r.apply(); toast(`${r.name} forged!`, '#ffd23a', 4000); }
  if (r.gate) { travelToNextPlanet(); }
  saveGame();
  return true;
}
