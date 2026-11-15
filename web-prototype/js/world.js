'use strict';
// ---------------------------------------------------------------------------
// World storage + planet generation.
// The planet is a W x H grid that wraps east-west. Row 0 is the edge of space,
// the last rows are the planet core.
// ---------------------------------------------------------------------------
const W = 1536, H = 1024, SURF = 270;

const T = new Uint8Array(W * H);   // material id
const V = new Uint8Array(W * H);   // colour variant / random byte
const L = new Uint8Array(W * H);   // life (fire fuel, gas lifetime)
const S = new Uint8Array(W * H);   // sim stamp (already moved this frame)

const skyTop = new Int16Array(W);  // first sun-blocking row per column
const surf0 = new Int16Array(W);   // original surface height (for backgrounds)
const deepY = new Int16Array(W), magmaY = new Int16Array(W), coreY = new Int16Array(W);
const colBiome = new Uint8Array(W); // index into planet.biomes
const colCos = new Float32Array(W), colSin = new Float32Array(W);

const skyDirty = new Uint8Array(W);
const skyDirtyList = [];

let planet = null;
let spawnX = 0, spawnY = 0, bossSpawn = null;

function wrapX(x) { x %= W; return x < 0 ? x + W : x; }
function wdx(a, b) { let d = a - b; d -= Math.round(d / W) * W; return d; }

function getT(x, y) {
  if (y < 0) return 0;
  if (y >= H) return M.CORE;
  return T[y * W + wrapX(Math.floor(x))];
}

function skyUpd(wx, y, t) {
  if (BLOCK[t]) { if (y < skyTop[wx]) skyTop[wx] = y; }
  else if (y === skyTop[wx] && !skyDirty[wx]) { skyDirty[wx] = 1; skyDirtyList.push(wx); }
}
function fixSky() {
  while (skyDirtyList.length) {
    const wx = skyDirtyList.pop(); skyDirty[wx] = 0;
    let y = skyTop[wx];
    while (y < H && !BLOCK[T[y * W + wx]]) y++;
    skyTop[wx] = y;
  }
}

function setCell(x, y, t, l) {
  if (y < 0 || y >= H) return;
  const wx = wrapX(Math.floor(x)), i = y * W + wx;
  T[i] = t; L[i] = l || 0;
  skyUpd(wx, y, t);
}

function biomeAt(x) { return BIOMES[planet.biomes[colBiome[wrapX(Math.floor(x))]]]; }

// periodic (cylindrical) noise sample for a world column
function pn(wx, y, freq, s, oct) { return fbm3(colCos[wx] * freq, colSin[wx] * freq, y * freq, s, oct); }

function generateWorld(pi) {
  planet = makePlanet(pi);
  const seed = planet.seed;
  const rng = mulberry32(seed);
  const R = W / (Math.PI * 2);
  for (let x = 0; x < W; x++) { const a = x / W * Math.PI * 2; colCos[x] = Math.cos(a) * R; colSin[x] = Math.sin(a) * R; }

  T.fill(0); L.fill(0); S.fill(0);
  let r32 = seed | 1;
  for (let i = 0; i < V.length; i++) { r32 ^= r32 << 13; r32 ^= r32 >>> 17; r32 ^= r32 << 5; V[i] = r32 & 255; }

  const bl = planet.biomes.map(k => BIOMES[k]);
  const nb = bl.length, seg = W / nb, EDGE = 50;

  // ---- column profile -----------------------------------------------------
  for (let x = 0; x < W; x++) {
    const p = x / seg, bi = Math.floor(p) % nb, local = x - Math.floor(p) * seg;
    let b0 = bi, b1 = bi, t = 0;
    if (local > seg - EDGE) { b1 = (bi + 1) % nb; t = (local - (seg - EDGE)) / (2 * EDGE); }
    else if (local < EDGE) { b0 = (bi - 1 + nb) % nb; t = 0.5 + local / (2 * EDGE); }
    t = t * t * (3 - 2 * t);
    const A = bl[b0], B = bl[b1];
    const off = A.off + (B.off - A.off) * t, amp = A.amp + (B.amp - A.amp) * t;
    colBiome[x] = t < 0.5 ? b0 : b1;
    const n1 = pn(x, 0, 1 / 110, seed + 1, 3) - 0.5, n2 = pn(x, 0, 1 / 26, seed + 2, 2) - 0.5;
    surf0[x] = Math.round(SURF + off + n1 * amp * 3.4 + n2 * amp * 0.7);
    deepY[x] = Math.round(SURF + 300 + (pn(x, 0, 1 / 60, seed + 3, 2) - 0.5) * 40);
    magmaY[x] = Math.round(SURF + planet.magma + (pn(x, 0, 1 / 50, seed + 4, 2) - 0.5) * 50);
    if (magmaY[x] < deepY[x] + 20) deepY[x] = magmaY[x] - 20;
    coreY[x] = Math.round(H - 48 + (pn(x, 0, 1 / 40, seed + 5, 2) - 0.5) * 24);
  }

  // ---- strata --------------------------------------------------------------
  for (let x = 0; x < W; x++) {
    const b = bl[colBiome[x]], s = surf0[x];
    const subD = b.subD + ((hash2(x, 3) * 6) | 0);
    const snowy = b.snowcap && s < SURF - 48;
    for (let y = Math.max(0, s); y < H; y++) {
      const d = y - s; let m;
      if (snowy && d < 3) m = M.SNOW;
      else if (d < b.topD) m = b.top;
      else if (d < b.topD + subD) m = b.sub;
      else if (y < deepY[x]) m = M.STONE;
      else if (y < magmaY[x]) m = M.DEEPSTONE;
      else if (y < coreY[x]) m = M.MAGMAROCK;
      else m = M.CORE;
      T[y * W + x] = m;
    }
  }

  // ---- caves ---------------------------------------------------------------
  // Noise is evaluated on a coarse 4x4 lattice and bilinearly interpolated:
  // ~16x cheaper than per-cell sampling and visually identical at this scale.
  const GS = 4, GW = W / GS, GH = Math.ceil(H / GS) + 1;
  const g1 = new Float32Array(GW * GH), g2 = new Float32Array(GW * GH);
  for (let gx = 0; gx < GW; gx++) {
    const x = gx * GS, cx = colCos[x], sx = colSin[x];
    for (let gy = 0; gy < GH; gy++) {
      const y = gy * GS, f1 = 1 / 46, f2 = 1 / 85;
      g1[gy * GW + gx] = fbm3(cx * f1, sx * f1, y * f1, seed + 10, 2);
      g2[gy * GW + gx] = fbm3(cx * f2, sx * f2, y * f2 * 1.7, seed + 12, 2);
    }
  }
  for (let x = 0; x < W; x++) {
    const s = surf0[x], c = coreY[x];
    const entrance = pn(x, 0, 1 / 34, seed + 11, 1) > 0.66;
    const gx0 = (x / GS) | 0, gx1 = (gx0 + 1) % GW, tx = (x % GS) / GS;
    for (let y = s + 2; y < c - 3; y++) {
      const d = y - s;
      if (d < 12 && !entrance) continue;
      const df = (y - s) / (c - s);
      const gy = (y / GS) | 0, ty = (y % GS) / GS;
      const a0 = gy * GW, a1 = a0 + GW;
      const n1 = (g1[a0 + gx0] * (1 - tx) + g1[a0 + gx1] * tx) * (1 - ty) + (g1[a1 + gx0] * (1 - tx) + g1[a1 + gx1] * tx) * ty;
      let carve = Math.abs(n1 - 0.5) < 0.019 + 0.015 * df;
      if (!carve && d > 30) {
        const n2 = (g2[a0 + gx0] * (1 - tx) + g2[a0 + gx1] * tx) * (1 - ty) + (g2[a1 + gx0] * (1 - tx) + g2[a1 + gx1] * tx) * ty;
        carve = n2 > 0.665 - 0.07 * df;
      }
      if (carve) T[y * W + x] = 0;
    }
  }

  // ---- ore veins -----------------------------------------------------------
  const rich = planet.rich;
  function vein(x, y, mat, host, size) {
    let cx = x, cy = y;
    for (let k = 0; k < size; k++) {
      const r = 1 + rng() * 1.6, ri = Math.ceil(r);
      for (let dy = -ri; dy <= ri; dy++) for (let dx = -ri; dx <= ri; dx++) {
        if (dx * dx + dy * dy > r * r) continue;
        const yy = Math.round(cy) + dy; if (yy < 0 || yy >= H) continue;
        const i = yy * W + wrapX(Math.round(cx) + dx);
        if (host(T[i])) T[i] = mat;
      }
      cx += rng() * 3 - 1.5; cy += rng() * 2.4 - 1.2;
    }
  }
  const isStone = t => t === M.STONE, isDeep = t => t === M.DEEPSTONE, isMag = t => t === M.MAGMAROCK;
  const isRock = t => t === M.STONE || t === M.DEEPSTONE;
  function scatter(n, mat, host, yFn, size, colOk) {
    n = Math.round(n * rich);
    for (let k = 0; k < n; k++) {
      const x = (rng() * W) | 0;
      if (colOk && !colOk(x)) { continue; }
      vein(x, yFn(x), mat, host, size + ((rng() * size) | 0));
    }
  }
  const ug = x => bl[colBiome[x]].ug;
  scatter(320, M.COPPER, isStone, x => surf0[x] + 15 + rng() * (deepY[x] - surf0[x] - 15), 6);
  scatter(260, M.COAL, isStone, x => surf0[x] + 10 + rng() * (deepY[x] - surf0[x] - 10), 7);
  scatter(420, M.CRYSTAL, isRock, x => surf0[x] + 30 + rng() * (magmaY[x] - surf0[x] - 30), 4, x => ug(x) === 'crystal');
  scatter(80, M.CRYSTAL, isDeep, x => deepY[x] + rng() * (magmaY[x] - deepY[x]), 3);
  scatter(420, M.FROST, isStone, x => surf0[x] + 8 + rng() * 200, 5, x => ug(x) === 'ice');
  scatter(60, M.FROST, isDeep, x => deepY[x] + rng() * (magmaY[x] - deepY[x]), 3);
  scatter(150, M.EMBER, isDeep, x => deepY[x] + (0.4 + rng() * 0.6) * (magmaY[x] - deepY[x]), 4);
  scatter(190, M.EMBER, isMag, x => magmaY[x] + rng() * (coreY[x] - magmaY[x]), 5);
  scatter(200, M.EMBER, isStone, x => surf0[x] + 10 + rng() * 150, 4, x => ug(x) === 'ember');
  scatter(240, M.WISP, isDeep, x => deepY[x] + rng() * (magmaY[x] - deepY[x]), 4);
  scatter(150, M.OBSIDIAN, isMag, x => magmaY[x] + rng() * (coreY[x] - magmaY[x]), 6);
  scatter(140, M.DEEPSTONE, isMag, x => magmaY[x] + rng() * (coreY[x] - magmaY[x]), 8);
  scatter(160, M.GRAVEL, isStone, x => surf0[x] + 12 + rng() * (deepY[x] - surf0[x]), 5);
  scatter(120, M.DIRT, isStone, x => surf0[x] + 14 + rng() * 80, 6);

  // ---- liquid pools resting on cave floors ------------------------------
  function pools(n, mat, yFn, colOk) {
    for (let k = 0; k < n; k++) {
      const x = (rng() * W) | 0;
      if (colOk && !colOk(x)) continue;
      let y = Math.round(yFn(x));
      if (y <= 0 || y >= H - 2 || T[y * W + x] !== 0) continue;
      while (y < H - 2 && T[(y + 1) * W + x] === 0) y++;
      const rx = 4 + rng() * 12, ry = 2 + rng() * 5;
      for (let dy = -Math.ceil(ry); dy <= 0; dy++) for (let dx = -Math.ceil(rx); dx <= Math.ceil(rx); dx++) {
        if ((dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) > 1) continue;
        const i = (y + dy) * W + wrapX(x + dx);
        if (T[i] === 0) T[i] = mat;
      }
    }
  }
  const notIce = x => ug(x) !== 'ice', isIce = x => ug(x) === 'ice';
  pools(260, M.WATER, x => surf0[x] + 20 + rng() * (deepY[x] - surf0[x] - 20), notIce);
  pools(160, M.ICE, x => surf0[x] + 20 + rng() * (deepY[x] - surf0[x] - 20), isIce);
  pools(90, M.WATER, x => deepY[x] + rng() * (magmaY[x] - deepY[x]) * 0.5);
  pools(Math.round(70 * planet.lava), M.LAVA, x => deepY[x] + (0.5 + rng() * 0.5) * (magmaY[x] - deepY[x]));
  pools(Math.round(300 * planet.lava), M.LAVA, x => magmaY[x] + rng() * (coreY[x] - magmaY[x]));
  pools(50, M.MUD, x => surf0[x] + 10 + rng() * 60, x => bl[colBiome[x]].pond);

  // ---- surface water / lava -------------------------------------------------
  for (let x = 0; x < W; x++) {
    const b = bl[colBiome[x]], s = surf0[x];
    let line = -1, mat = M.WATER;
    if (planet.sea != null) line = SURF + planet.sea;
    if (b.pond) line = Math.max(line, SURF + b.off + 2);
    if (b.lavaLake && line < 0) { line = SURF + b.off + 6; mat = M.LAVA; }
    if (line < 0) continue;
    for (let y = line; y < s; y++) if (T[y * W + x] === 0) T[y * W + x] = mat;
  }

  // ---- cave flora: glowshrooms, crystals, icicles -----------------------
  for (let x = 0; x < W; x++) {
    const u = ug(x);
    for (let y = surf0[x] + 10; y < coreY[x] - 1; y++) {
      const i = y * W + x;
      if (T[i] !== 0) continue;
      const below = T[i + W], above = T[i - W];
      const h = hash2(x, y);
      if (BLOCK[below] && KIND[below] === K_SOLID) {
        const shallow = y < deepY[x];
        let mat = 0, hgt = 0;
        if (u === 'fungal' && shallow && h < 0.11) { mat = M.SHROOM; hgt = 1 + ((h * 40) | 0) % 3; }
        else if (u === 'crystal' && h < 0.06) { mat = M.CRYSTAL; hgt = 1 + ((h * 90) | 0) % 4; }
        else if (u === 'ice' && shallow && h < 0.05) { mat = M.ICE; hgt = 1 + ((h * 90) | 0) % 3; }
        else if (u === 'ember' && h < 0.04) { mat = M.EMBER; hgt = 1 + ((h * 90) | 0) % 2; }
        else if (!shallow && y < magmaY[x] && h < 0.018) { mat = M.SHROOM; hgt = 1 + ((h * 300) | 0) % 2; }
        for (let k = 0; k < hgt; k++) { const j = i - k * W; if (T[j] === 0) T[j] = mat; else break; }
      } else if (BLOCK[above] && KIND[above] === K_SOLID && h > 0.975) {
        const mat = u === 'ice' ? M.ICE : (u === 'crystal' ? M.CRYSTAL : 0);
        if (mat) { const hgt = 1 + ((h * 1000) | 0) % 3; for (let k = 0; k < hgt; k++) { const j = i + k * W; if (T[j] === 0) T[j] = mat; else break; } }
      }
    }
  }

  // ---- spawn point --------------------------------------------------------
  let sb = bl.findIndex(b => b.spawnOK);
  if (sb < 0) sb = 0;
  spawnX = Math.floor((sb + 0.5) * seg);
  // nudge to the highest land nearby so the mage doesn't start underwater
  let bestX = spawnX;
  for (let dx = -60; dx <= 60; dx += 3) { const xx = wrapX(spawnX + dx); if (surf0[xx] < surf0[bestX]) bestX = xx; }
  spawnX = bestX;

  // ---- surface flora --------------------------------------------------------
  let last = -99;
  for (let x = 0; x < W; x++) {
    if (Math.abs(wdx(x, spawnX)) < 10) continue;
    const b = bl[colBiome[x]], s = surf0[x];
    if (s < 4) continue;
    const topCell = T[s * W + x], aboveCell = T[(s - 1) * W + x];
    const h = hash2(x, 77);
    const dry = aboveCell === 0;
    switch (b.flora) {
      case 'trees': if (dry && topCell === M.GRASS && h < 0.12 && x - last > 7) { tree(x, s - 1, 12 + ((h * 400) | 0) % 12); last = x; } break;
      case 'pines': if (dry && h < 0.07 && x - last > 6) { pine(x, s - 1, 9 + ((h * 400) | 0) % 10, b.top === M.SNOW || s < SURF - 48); last = x; } break;
      case 'cactus': if (dry && h < 0.025 && x - last > 10) { cactus(x, s - 1, 5 + ((h * 900) | 0) % 6); last = x; } break;
      case 'reeds': if (h < 0.3) { const hh = 2 + ((h * 50) | 0) % 4; for (let k = 0; k < hh; k++) { const j = (s - 1 - k) * W + x; if (T[j] === 0 || T[j] === M.WATER) T[j] = M.LEAF; } }
        if (dry && h > 0.97 && x - last > 12) { deadTree(x, s - 1, 8 + ((h * 900) | 0) % 6); last = x; } break;
      case 'dead': if (dry && h < 0.03 && x - last > 9) { deadTree(x, s - 1, 7 + ((h * 900) | 0) % 8); last = x; } break;
      case 'kelp': if (aboveCell === M.WATER && h < 0.2) { const hh = 4 + ((h * 400) | 0) % 10; for (let k = 0; k < hh; k++) { const xx = wrapX(x + (k % 4 === 3 ? 1 : 0)); const j = (s - 1 - k) * W + xx; if (T[j] === M.WATER) T[j] = M.LEAF; else break; } } break;
    }
  }
  function put(x, y, m, onlyAir) { if (y < 0 || y >= H) return; const i = y * W + wrapX(x); if (!onlyAir || T[i] === 0) T[i] = m; }
  function tree(x, y, h) {
    for (let k = 0; k < h; k++) { put(x, y - k, M.WOOD); if (k < h - 3) put(x + 1, y - k, M.WOOD); }
    put(x - 1, y, M.WOOD); put(x + 2, y, M.WOOD);
    const cy = y - h, r = 5 + (h > 18 ? 2 : 0);
    for (let dy = -r; dy <= r; dy++) for (let dx = -r - 1; dx <= r + 1; dx++) {
      const e = (dx * dx) / ((r + 1) * (r + 1)) + (dy * dy) / (r * r);
      if (e < 1 - hash2(x + dx, cy + dy) * 0.35) put(x + dx, cy + dy, M.LEAF, true);
    }
    const by = y - Math.floor(h * 0.55);
    for (let k = 1; k < 4; k++) { put(x - k, by - (k >> 1), M.WOOD, true); put(x + 1 + k, by - 2 - (k >> 1), M.WOOD, true); }
  }
  function pine(x, y, h, snowy) {
    for (let k = 0; k < h; k++) put(x, y - k, M.WOOD);
    for (let k = 2; k <= h + 1; k++) {
      const w = Math.floor((h + 2 - k) * 0.45) + ((k & 1) ? 1 : 0);
      for (let dx = -w; dx <= w; dx++) put(x + dx, y - k, (snowy && (k & 1) === 0 && Math.abs(dx) === w) ? M.SNOW : M.LEAF, true);
    }
  }
  function cactus(x, y, h) {
    for (let k = 0; k < h; k++) put(x, y - k, M.CACTUS);
    const a = Math.floor(h / 2);
    put(x - 1, y - a, M.CACTUS); put(x - 2, y - a, M.CACTUS); put(x - 2, y - a - 1, M.CACTUS); put(x - 2, y - a - 2, M.CACTUS);
    put(x + 1, y - a - 1, M.CACTUS); put(x + 2, y - a - 1, M.CACTUS); put(x + 2, y - a - 2, M.CACTUS);
  }
  function deadTree(x, y, h) {
    for (let k = 0; k < h; k++) put(x, y - k, M.WOOD);
    for (let k = 1; k < 4; k++) { put(x - k, y - h + 2 - k, M.WOOD, true); put(x + k, y - h + 4 - k, M.WOOD, true); }
  }

  // ---- boss arena: the Ember Golem guards the mantle -------------------------
  const bx = wrapX(spawnX + (W >> 1));
  const by = magmaY[bx] + 4;
  const rx = 48, ry = 20;
  for (let dy = -ry - 3; dy <= ry + 3; dy++) for (let dx = -rx - 3; dx <= rx + 3; dx++) {
    const e = (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry);
    const i = (by + dy) * W + wrapX(bx + dx);
    if (e < 1) T[i] = 0;
    else if (e < 1.22 && dy > 0) T[i] = M.OBSIDIAN;
    else if (e < 1.22 && hash2(bx + dx, by + dy) < 0.12) T[i] = M.EMBER;
  }
  bossSpawn = { x: bx - 7, y: by + ry - 22 };

  // ---- sunlight heightmap ---------------------------------------------------
  for (let x = 0; x < W; x++) { let y = 0; while (y < H && !BLOCK[T[y * W + x]]) y++; skyTop[x] = y; }
  skyDirtyList.length = 0; skyDirty.fill(0);

  spawnY = Math.min(surf0[spawnX], skyTop[spawnX]) - 16;
}

// Name of the region at a world position, for the HUD.
function regionName(x, y) {
  const wx = wrapX(Math.floor(x));
  if (y < 60) return 'Edge of Space';
  if (y < 170) return 'Upper Sky';
  const b = biomeAt(wx);
  if (y < surf0[wx] + 14) return b.name;
  if (y < deepY[wx]) return b.under;
  if (y < magmaY[wx]) return 'The Umbral Deep';
  if (y < coreY[wx]) return 'Molten Mantle';
  return 'Planet Core';
}
