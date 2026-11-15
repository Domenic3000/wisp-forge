'use strict';
// ---------------------------------------------------------------------------
// Renderer: one canvas pixel per world cell, CSS-scaled with nearest-neighbour.
// Pass 1 writes base colours + accumulates emitted light into a coarse
// light grid; entities draw into the same buffers; pass 2 applies blurred,
// bilinearly-filtered lighting (sun, glowing materials, the wisp, spells).
// ---------------------------------------------------------------------------
let canvas, ctx2d, imgData, px32;
let VW = 320, VH = 180, SCALE = 4;
let baseR, baseG, baseB, flag;          // flag: 0 = lit by lightmap, 1 = self-lit, 2 = sky
const LS = 4;
let LW, LH, lmR, lmG, lmB, tmR, tmG, tmB;
let lx0, lx1, ltx, ly0, ly1, lty;
let skyR, skyG, skyB;
let camX = 0, camY = 0;                 // integer top-left world cell of the view
const pointLights = [];
let cloudTex;

function initRenderer() {
  canvas = document.getElementById('game');
  ctx2d = canvas.getContext('2d', { alpha: false });
  // periodic cloud texture: 256 texels wide, each texel = 2 world cells, so it tiles 3x around the planet
  cloudTex = new Float32Array(256 * 48);
  for (let x = 0; x < 256; x++) {
    const a = x / 256 * Math.PI * 2, r = 256 / (Math.PI * 2);
    for (let y = 0; y < 48; y++) {
      const f = 1 / 14;
      let n = fbm3(Math.cos(a) * r * f, Math.sin(a) * r * f, y * f * 2.2, 4242, 3);
      const band = 1 - Math.abs(y - 24) / 24;
      cloudTex[y * 256 + x] = n * (0.55 + 0.45 * band);
    }
  }
  resizeView();
  window.addEventListener('resize', resizeView);
}

function resizeView() {
  SCALE = Math.max(2, Math.round(window.innerHeight / 230));
  VW = Math.ceil(window.innerWidth / SCALE);
  VH = Math.ceil(window.innerHeight / SCALE);
  canvas.width = VW; canvas.height = VH;
  canvas.style.width = (VW * SCALE) + 'px';
  canvas.style.height = (VH * SCALE) + 'px';
  imgData = ctx2d.createImageData(VW, VH);
  px32 = new Uint32Array(imgData.data.buffer);
  const n = VW * VH;
  baseR = new Uint8Array(n); baseG = new Uint8Array(n); baseB = new Uint8Array(n); flag = new Uint8Array(n);
  LW = Math.ceil(VW / LS) + 1; LH = Math.ceil(VH / LS) + 1;
  const ln = LW * LH;
  lmR = new Float32Array(ln); lmG = new Float32Array(ln); lmB = new Float32Array(ln);
  tmR = new Float32Array(ln); tmG = new Float32Array(ln); tmB = new Float32Array(ln);
  lx0 = new Int32Array(VW); lx1 = new Int32Array(VW); ltx = new Float32Array(VW);
  ly0 = new Int32Array(VH); ly1 = new Int32Array(VH); lty = new Float32Array(VH);
  for (let x = 0; x < VW; x++) { const f = (x + 0.5) / LS - 0.5; const a = Math.max(0, Math.floor(f)); lx0[x] = a; lx1[x] = Math.min(LW - 1, a + 1); ltx[x] = Math.min(1, Math.max(0, f - a)); }
  for (let y = 0; y < VH; y++) { const f = (y + 0.5) / LS - 0.5; const a = Math.max(0, Math.floor(f)); ly0[y] = a; ly1[y] = Math.min(LH - 1, a + 1); lty[y] = Math.min(1, Math.max(0, f - a)); }
  skyR = new Uint8Array(VH); skyG = new Uint8Array(VH); skyB = new Uint8Array(VH);
}

function addLight(wx, wy, radius, r, g, b) { pointLights.push(wx, wy, radius, r, g, b); }

// world x -> screen x (handles wrap)
function scrX(wx) {
  let d = Math.floor(wx) - camX;
  d = ((d % W) + W) % W;
  if (d > W - 96) d -= W;
  return d;
}

function putPx(sx, sy, r, g, b, self) {
  if (sx < 0 || sy < 0 || sx >= VW || sy >= VH) return;
  const p = sy * VW + sx;
  baseR[p] = r; baseG[p] = g; baseB[p] = b; flag[p] = self ? 1 : 0;
}
function blendPx(sx, sy, r, g, b, a, self) {
  if (sx < 0 || sy < 0 || sx >= VW || sy >= VH) return;
  const p = sy * VW + sx;
  baseR[p] = baseR[p] + (r - baseR[p]) * a; baseG[p] = baseG[p] + (g - baseG[p]) * a; baseB[p] = baseB[p] + (b - baseB[p]) * a;
  if (self) flag[p] = 1;
}

const WALL = [
  [52, 37, 27],  // soil
  [36, 37, 45],  // stone
  [29, 26, 40],  // deep
  [46, 20, 15],  // mantle
  [70, 58, 26],  // core
];

function lerp(a, b, t) { return a + (b - a) * t; }

// env: { sun (0..1), sunCol [r,g,b], dayT, starA, cloudOff, cloudCover, rain, flash }
function renderWorld(env) {
  const tint = planet.sky;
  // ---- sky gradient per screen row ----
  for (let sy = 0; sy < VH; sy++) {
    const y = camY + sy;
    const alt = Math.min(1, Math.max(0, y / SURF));        // 0 at edge of space, 1 at surface
    const space = Math.min(1, Math.max(0, 1 - (y - 20) / 170)); // fade to black above ~y 190
    const d = env.sun;
    let r = lerp(lerp(12, 70, d), lerp(28, 160, d), alt);
    let g = lerp(lerp(14, 120, d), lerp(34, 205, d), alt);
    let b = lerp(lerp(34, 210, d), lerp(64, 245, d), alt);
    // dusk glow near horizon
    const dusk = env.dusk * alt * alt;
    r = lerp(r, 240, dusk * 0.55); g = lerp(g, 120, dusk * 0.45); b = lerp(b, 90, dusk * 0.4);
    if (env.rain > 0) { const k = env.rain * 0.45; const grey = (r + g + b) / 3 * 0.8; r = lerp(r, grey, k); g = lerp(g, grey, k); b = lerp(b, grey, k); }
    r *= tint[0]; g *= tint[1]; b *= tint[2];
    r = lerp(r, 2, space); g = lerp(g, 2, space); b = lerp(b, 8, space);
    skyR[sy] = Math.min(255, r); skyG[sy] = Math.min(255, g); skyB[sy] = Math.min(255, b);
  }
  const starA = Math.max(env.starA, 0);
  const sunX = env.sunSX, sunY = env.sunSY, moonX = env.moonSX, moonY = env.moonSY;

  lmR.fill(0); lmG.fill(0); lmB.fill(0);

  // ---- pass 1: base colours + emission ----
  const wx0 = wrapX(camX);
  for (let sy = 0; sy < VH; sy++) {
    const y = camY + sy;
    if (y < 0 || y >= H) { for (let sx = 0; sx < VW; sx++) { const p = sy * VW + sx; baseR[p] = 0; baseG[p] = 0; baseB[p] = 0; flag[p] = 2; } continue; }
    const row = y * W, srow = sy * VW, lrow = (sy >> 2) * LW;
    const sr = skyR[sy], sg = skyG[sy], sb = skyB[sy];
    const inCloud = y >= 120 && y < 216;
    const cty = (y - 120) >> 1;
    let wx = wx0;
    for (let sx = 0; sx < VW; sx++, wx++) {
      if (wx >= W) wx = 0;
      const i = row + wx, t = T[i], p = srow + sx;
      let r, g, b, f;
      // background (sky or cave wall) — needed for empty and translucent cells
      if (t === 0 || ALPHA[t] < 1) {
        if (y < surf0[wx]) {
          r = sr; g = sg; b = sb; f = 2;
          if (starA > 0.02) {
            let h = Math.imul(wx, 0x9E3779B1) ^ Math.imul(y, 0x85EBCA6B); h ^= h >>> 13; h = Math.imul(h, 0xC2B2AE35); h ^= h >>> 16;
            if ((h & 1023) < 3) { const tw = 0.6 + 0.4 * Math.sin(env.time * 0.05 + (h & 63)); const s = 230 * starA * tw; r = Math.max(r, s); g = Math.max(g, s); b = Math.max(b, s * 1.05); }
          }
          if (env.sunUp) { const dx = sx - sunX, dy = sy - sunY, d2 = dx * dx + dy * dy; if (d2 < 30) { r = 255; g = 245; b = 200; } else if (d2 < 80) { const k = (80 - d2) / 50 * 0.5; r = lerp(r, 255, k); g = lerp(g, 230, k); b = lerp(b, 170, k); } }
          if (env.moonUp) { const dx = sx - moonX, dy = sy - moonY, d2 = dx * dx + dy * dy; if (d2 < 17) { const c = (dx + dy > 2) ? 170 : 225; r = c; g = c; b = c + 10; } }
          if (inCloud) {
            const c = cloudTex[cty * 256 + (((wx + env.cloudOff) >> 1) & 255)];
            const a = Math.min(0.92, Math.max(0, (c - (0.66 - env.cloudCover * 0.2)) * 5));
            if (a > 0) {
              const cl = 60 + 190 * Math.max(0.15, env.sun) * (1 - env.rain * 0.45);
              r = lerp(r, cl * tint[0], a); g = lerp(g, cl * tint[1], a); b = lerp(b, cl * 1.04 * tint[2], a);
            }
          }
        } else {
          const layer = y < surf0[wx] + 22 ? 0 : (y < deepY[wx] ? 1 : (y < magmaY[wx] ? 2 : (y < coreY[wx] ? 3 : 4)));
          const c = WALL[layer];
          const tv = ((wx * 7 + (y >> 1) * 13) ^ (y * 3 + (wx >> 2) * 5)) & 7;
          const k = 0.86 + tv * 0.03;
          r = c[0] * k; g = c[1] * k; b = c[2] * k; f = 0;
        }
        if (t !== 0) {
          const o = t * 12 + (V[i] & 3) * 3, a = ALPHA[t];
          r = r + (PAL[o] - r) * a; g = g + (PAL[o + 1] - g) * a; b = b + (PAL[o + 2] - b) * a;
          f = SELF[t] ? 1 : (f === 2 ? 2 : 0);
        }
      } else {
        const o = t * 12 + (V[i] & 3) * 3;
        r = PAL[o]; g = PAL[o + 1]; b = PAL[o + 2]; f = SELF[t];
        if (t === M.LAVA || t === M.FIRE) { const fl = 0.85 + 0.15 * Math.sin(env.time * 0.15 + wx * 0.7 + y * 0.3); r *= fl; g *= fl; }
      }
      baseR[p] = r; baseG[p] = g; baseB[p] = b; flag[p] = f;
      if (GLR[t] !== 0) { const li = lrow + (sx >> 2); lmR[li] += GLR[t]; lmG[li] += GLG[t]; lmB[li] += GLB[t]; }
    }
  }
}

function buildLighting(env) {
  // emission accumulated per 4x4 block -> normalise, then add sunlight
  const sun = env.sun * (1 - env.rain * 0.3) + env.flash;
  const sc = env.sunCol;
  for (let by = 0; by < LH; by++) {
    const y = camY + by * LS + 2;
    for (let bx = 0; bx < LW; bx++) {
      const li = by * LW + bx;
      const wx = wrapX(camX + bx * LS + 2);
      const st = skyTop[wx];
      let s = y < st ? 1 : Math.max(0, 1 - (y - st) / 26);
      s *= sun;
      lmR[li] = lmR[li] * 0.16 + s * sc[0];
      lmG[li] = lmG[li] * 0.16 + s * sc[1];
      lmB[li] = lmB[li] * 0.16 + s * sc[2];
    }
  }
  // point lights (wisp, spells, enemies)
  for (let k = 0; k < pointLights.length; k += 6) {
    const lx = scrX(pointLights[k]) / LS, ly = (pointLights[k + 1] - camY) / LS, rad = pointLights[k + 2] / LS;
    const cr = pointLights[k + 3], cg = pointLights[k + 4], cb = pointLights[k + 5];
    const bx0 = Math.max(0, Math.floor(lx - rad)), bx1 = Math.min(LW - 1, Math.ceil(lx + rad));
    const by0 = Math.max(0, Math.floor(ly - rad)), by1 = Math.min(LH - 1, Math.ceil(ly + rad));
    for (let by = by0; by <= by1; by++) for (let bx = bx0; bx <= bx1; bx++) {
      const dx = bx - lx, dy = by - ly, d = Math.sqrt(dx * dx + dy * dy) / rad;
      if (d >= 1) continue;
      const f = (1 - d) * (1 - d);
      const li = by * LW + bx;
      lmR[li] += cr * f; lmG[li] += cg * f; lmB[li] += cb * f;
    }
  }
  pointLights.length = 0;
  // separable blur (2 passes) so light bleeds softly through caves
  for (let pass = 0; pass < 2; pass++) {
    for (let by = 0; by < LH; by++) for (let bx = 0; bx < LW; bx++) {
      const li = by * LW + bx, l = bx > 0 ? li - 1 : li, r = bx < LW - 1 ? li + 1 : li;
      tmR[li] = (lmR[l] + lmR[li] * 2 + lmR[r]) * 0.25; tmG[li] = (lmG[l] + lmG[li] * 2 + lmG[r]) * 0.25; tmB[li] = (lmB[l] + lmB[li] * 2 + lmB[r]) * 0.25;
    }
    for (let by = 0; by < LH; by++) for (let bx = 0; bx < LW; bx++) {
      const li = by * LW + bx, u = by > 0 ? li - LW : li, d = by < LH - 1 ? li + LW : li;
      lmR[li] = (tmR[u] + tmR[li] * 2 + tmR[d]) * 0.25; lmG[li] = (tmG[u] + tmG[li] * 2 + tmG[d]) * 0.25; lmB[li] = (tmB[u] + tmB[li] * 2 + tmB[d]) * 0.25;
    }
  }
}

function composite(env) {
  const amb = 0.008;
  for (let sy = 0; sy < VH; sy++) {
    const a0 = ly0[sy] * LW, a1 = ly1[sy] * LW, ty = lty[sy], srow = sy * VW;
    for (let sx = 0; sx < VW; sx++) {
      const p = srow + sx;
      let r = baseR[p], g = baseG[p], b = baseB[p];
      if (flag[p] === 0) {
        const x0 = lx0[sx], x1 = lx1[sx], tx = ltx[sx];
        const i00 = a0 + x0, i01 = a0 + x1, i10 = a1 + x0, i11 = a1 + x1;
        let lr = (lmR[i00] * (1 - tx) + lmR[i01] * tx) * (1 - ty) + (lmR[i10] * (1 - tx) + lmR[i11] * tx) * ty;
        let lg = (lmG[i00] * (1 - tx) + lmG[i01] * tx) * (1 - ty) + (lmG[i10] * (1 - tx) + lmG[i11] * tx) * ty;
        let lb = (lmB[i00] * (1 - tx) + lmB[i01] * tx) * (1 - ty) + (lmB[i10] * (1 - tx) + lmB[i11] * tx) * ty;
        // perceptual curve: lifts dim light so dark caves stay readable
        lr = Math.sqrt(lr + amb); lg = Math.sqrt(lg + amb); lb = Math.sqrt(lb + amb);
        if (lr > 1.3) lr = 1.3; if (lg > 1.3) lg = 1.3; if (lb > 1.3) lb = 1.3;
        r *= lr; g *= lg; b *= lb;
      }
      if (env.hurt > 0) { r += env.hurt * 90; }
      px32[p] = 0xff000000 | ((b > 255 ? 255 : b) << 16) | ((g > 255 ? 255 : g) << 8) | (r > 255 ? 255 : r);
    }
  }
}

function presentFrame() { ctx2d.putImageData(imgData, 0, 0); }

// unlit overlay pixel (UI reticle etc.), written after composite
function overlayPx(sx, sy, r, g, b, a) {
  if (sx < 0 || sy < 0 || sx >= VW || sy >= VH) return;
  const p = sy * VW + sx, c = px32[p];
  const or = c & 255, og = (c >> 8) & 255, ob = (c >> 16) & 255;
  px32[p] = 0xff000000 | ((ob + (b - ob) * a) << 16) | ((og + (g - og) * a) << 8) | (or + (r - or) * a);
}
