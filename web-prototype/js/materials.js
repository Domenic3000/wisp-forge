'use strict';
// ---------------------------------------------------------------------------
// Wisp Forge — material definitions
// Every pixel of the world is one cell holding one material id (0..NM-1).
// Behaviour comes from its KIND (solid / powder / liquid / gas / fire) plus the
// per-material property tables below. Tables are flat typed arrays for speed.
// ---------------------------------------------------------------------------
const K_EMPTY = 0, K_SOLID = 1, K_POWDER = 2, K_LIQUID = 3, K_GAS = 4, K_FIRE = 5;
const NM = 40;

const M = {
  AIR: 0, STONE: 1, DIRT: 2, GRASS: 3, SAND: 4, WATER: 5, LAVA: 6, WOOD: 7, LEAF: 8,
  FIRE: 9, SMOKE: 10, STEAM: 11, OBSIDIAN: 12, DEEPSTONE: 13, COPPER: 14, COAL: 15,
  EMBER: 16, FROST: 17, WISP: 18, MUD: 19, ICE: 20, MAGMAROCK: 21, CORE: 22,
  SHROOM: 23, GRAVEL: 24, BRICK: 25, GLASS: 26, SNOW: 27, CRYSTAL: 28, ASH: 29,
  PLANK: 30, CACTUS: 31,
};

const KIND = new Uint8Array(NM);
const DENS = new Uint8Array(NM);      // relative density for powders / liquids
const HARD = new Uint8Array(NM);      // staff tier needed to excavate (0..4)
const FUEL = new Uint8Array(NM);      // burn duration in frames when ignited
const IGN = new Float32Array(NM);     // chance per frame to catch from adjacent fire
const BLOCK = new Uint8Array(NM);     // blocks movement + sunlight
const SELF = new Uint8Array(NM);      // self-lit (ignores darkness)
const REACT = new Uint8Array(NM);     // solid with a slow reaction rule
const ALPHA = new Float32Array(NM).fill(1); // <1 => see-through
const DISPERSE = new Uint8Array(NM);  // liquid sideways spread per frame
const GLR = new Float32Array(NM), GLG = new Float32Array(NM), GLB = new Float32Array(NM); // emitted light
const PAL = new Uint8Array(NM * 12);  // 4 colour variants * rgb
const MINFO = [];

function hexRGB(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }

function defMat(id, name, kind, cols, o = {}) {
  KIND[id] = kind; DENS[id] = o.dens || 0; HARD[id] = o.hard ?? 0;
  FUEL[id] = o.fuel || 0; IGN[id] = o.ign || 0;
  BLOCK[id] = (kind === K_SOLID || kind === K_POWDER) ? 1 : 0;
  SELF[id] = o.self ? 1 : 0; REACT[id] = o.react ? 1 : 0;
  ALPHA[id] = o.alpha ?? 1; DISPERSE[id] = o.disp || 0;
  if (o.glow) { GLR[id] = o.glow[0]; GLG[id] = o.glow[1]; GLB[id] = o.glow[2]; }
  for (let k = 0; k < 4; k++) {
    const c = hexRGB(cols[k % cols.length]);
    PAL[id * 12 + k * 3] = c[0]; PAL[id * 12 + k * 3 + 1] = c[1]; PAL[id * 12 + k * 3 + 2] = c[2];
  }
  const collect = o.collect ?? (kind !== K_EMPTY && kind !== K_GAS && kind !== K_FIRE);
  MINFO[id] = { id, name, kind, collect, place: o.place ?? collect, desc: o.desc || '', color: cols[0] };
}

defMat(M.AIR, 'Air', K_EMPTY, ['#000000']);
defMat(M.STONE, 'Stone', K_SOLID, ['#6b6f7a', '#626672', '#737786', '#5b5f6a'], { hard: 1 });
defMat(M.DIRT, 'Dirt', K_SOLID, ['#7a5234', '#6e4a2f', '#845a39', '#704c30']);
defMat(M.GRASS, 'Grass', K_SOLID, ['#4f9a3a', '#5aa842', '#478f34', '#62b04a'], { fuel: 18, ign: 0.25, react: true });
defMat(M.SAND, 'Sand', K_POWDER, ['#e0c27a', '#d6b66c', '#e8cc88', '#d0ad62'], { dens: 5 });
defMat(M.WATER, 'Water', K_LIQUID, ['#2d6fd1', '#3478dc', '#2a68c6', '#3a80e0'], { dens: 2, disp: 6, alpha: 0.72 });
defMat(M.LAVA, 'Lava', K_LIQUID, ['#ff6a1a', '#ff8c22', '#f2501a', '#ffa531'], { dens: 3, disp: 2, hard: 2, self: true, glow: [1.0, 0.42, 0.1] });
defMat(M.WOOD, 'Wood', K_SOLID, ['#6b4423', '#5f3c1f', '#774b27', '#633f20'], { fuel: 130, ign: 0.035 });
defMat(M.LEAF, 'Leaves', K_SOLID, ['#2f7a32', '#37883a', '#29702c', '#3f9442'], { fuel: 28, ign: 0.22 });
defMat(M.FIRE, 'Fire', K_FIRE, ['#ffd23a', '#ff9a1f', '#ff6a12', '#fff07a'], { self: true, glow: [1.0, 0.55, 0.18] });
defMat(M.SMOKE, 'Smoke', K_GAS, ['#555555', '#4a4a4a', '#606060', '#525252'], { alpha: 0.55 });
defMat(M.STEAM, 'Steam', K_GAS, ['#d8e4ee', '#c8d6e2', '#e6eef4', '#bfcfdc'], { alpha: 0.45 });
defMat(M.OBSIDIAN, 'Obsidian', K_SOLID, ['#2a1f3d', '#231a33', '#33264a', '#1e1630'], { hard: 3 });
defMat(M.DEEPSTONE, 'Deepstone', K_SOLID, ['#474258', '#3f3a50', '#4f4962', '#3a3549'], { hard: 2 });
defMat(M.COPPER, 'Copper Ore', K_SOLID, ['#c8743a', '#e09a5a', '#6b6f7a', '#b8652e'], { hard: 1 });
defMat(M.COAL, 'Coal', K_SOLID, ['#2b2b2e', '#38383c', '#222224', '#55575e'], { hard: 1, fuel: 250, ign: 0.015 });
defMat(M.EMBER, 'Ember Crystal', K_SOLID, ['#ff3d2e', '#ff7a3d', '#c22a20', '#ffb14a'], { hard: 2, self: true, glow: [0.9, 0.22, 0.12] });
defMat(M.FROST, 'Frost Shard', K_SOLID, ['#8fe8ff', '#c4f4ff', '#5ccfee', '#e6fcff'], { hard: 1, self: true, react: true, glow: [0.3, 0.7, 0.95] });
defMat(M.WISP, 'Wisp Ore', K_SOLID, ['#7a8cff', '#a9b6ff', '#5c66e8', '#d4dbff'], { hard: 2, self: true, glow: [0.4, 0.45, 1.0] });
defMat(M.MUD, 'Mud', K_LIQUID, ['#4b3a26', '#56432c', '#423320', '#5c4830'], { dens: 4, disp: 1 });
defMat(M.ICE, 'Ice', K_SOLID, ['#a8d8f0', '#bfe4f6', '#96cce8', '#cfeefa'], { hard: 1, react: true, alpha: 0.85 });
defMat(M.MAGMAROCK, 'Magma Rock', K_SOLID, ['#3a1e1a', '#44211a', '#331a16', '#55261a'], { hard: 3, glow: [0.07, 0.015, 0.005] });
defMat(M.CORE, 'Planet Core', K_SOLID, ['#fff2b0', '#ffe066', '#ffd23a', '#ffffff'], { hard: 4, self: true, glow: [1.0, 0.85, 0.45] });
defMat(M.SHROOM, 'Glowshroom', K_SOLID, ['#3fe0c8', '#6ff5dc', '#2bb8a6', '#a0fff0'], { self: true, fuel: 40, ign: 0.08, glow: [0.15, 0.85, 0.75] });
defMat(M.GRAVEL, 'Gravel', K_POWDER, ['#7d7a78', '#6a6866', '#8a8784', '#5e5c5a'], { dens: 6 });
defMat(M.BRICK, 'Brick', K_SOLID, ['#9c4a3a', '#a85440', '#8e4234', '#6d625a'], { hard: 2 });
defMat(M.GLASS, 'Glass', K_SOLID, ['#bfe6f0', '#d2f0f8', '#aee0ec', '#e4f8ff'], { alpha: 0.4 });
defMat(M.SNOW, 'Snow', K_POWDER, ['#f0f6ff', '#e4eefa', '#ffffff', '#dae6f4'], { dens: 3 });
defMat(M.CRYSTAL, 'Prism Crystal', K_SOLID, ['#e070ff', '#f2a6ff', '#b84cf0', '#ffd6ff'], { hard: 1, self: true, glow: [0.75, 0.3, 0.95] });
defMat(M.ASH, 'Ash', K_POWDER, ['#5a5552', '#4e4a48', '#686260', '#454240'], { dens: 3 });
defMat(M.PLANK, 'Planks', K_SOLID, ['#b07a44', '#a06c3a', '#bc864e', '#966434'], { fuel: 110, ign: 0.05 });
defMat(M.CACTUS, 'Cactus', K_SOLID, ['#4e8a3a', '#5a9a44', '#447c32', '#66a64e'], { fuel: 40, ign: 0.05 });

// DISP[a*NM+b] = 1 if a falling/flowing cell of material a may swap into b
const DISP = new Uint8Array(NM * NM);
(function buildDisp() {
  for (let a = 0; a < NM; a++) for (let b = 0; b < NM; b++) {
    const ka = KIND[a], kb = KIND[b];
    let ok = 0;
    if (ka === K_POWDER || ka === K_LIQUID) {
      if (b === 0 || kb === K_GAS || kb === K_FIRE) ok = 1;
      else if (kb === K_LIQUID && DENS[b] < DENS[a]) ok = 1;
    }
    DISP[a * NM + b] = ok;
  }
})();
