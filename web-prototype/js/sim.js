'use strict';
// ---------------------------------------------------------------------------
// Cellular simulation. Only the region around the camera is stepped each frame
// (everything else is "asleep" until you come back). Rows are processed bottom
// to top with alternating horizontal direction to avoid drift bias.
// ---------------------------------------------------------------------------
let simFrame = 0;
let rs = 0x2545F491;
function rand() { rs ^= rs << 13; rs ^= rs >>> 17; rs ^= rs << 5; return (rs >>> 0) * 2.3283064365386963e-10; }

const sim = { daylight: 1 };

function chg(i, wx, y, t, l) { T[i] = t; L[i] = l || 0; skyUpd(wx, y, t); }

function mv(i, j, wxi, yi, wxj, yj, st) {
  const ti = T[i], tj = T[j];
  T[i] = tj; T[j] = ti;
  let v = V[i]; V[i] = V[j]; V[j] = v;
  v = L[i]; L[i] = L[j]; L[j] = v;
  S[i] = st; S[j] = st;
  if (BLOCK[ti] || BLOCK[tj]) { skyUpd(wxj, yj, ti); skyUpd(wxi, yi, tj); }
}

function simulate(x0, x1, y0, y1) {
  simFrame++;
  const st = (simFrame % 250) + 1;
  if (y0 < 2) y0 = 2;
  if (y1 > H - 2) y1 = H - 2;
  const span = x1 - x0;
  for (let y = y1; y >= y0; y--) {
    const dir = (simFrame + y) & 1, row = y * W;
    for (let k = 0; k <= span; k++) {
      let wx = dir ? x0 + k : x1 - k;
      if (wx < 0) wx += W; else if (wx >= W) wx -= W;
      const i = row + wx, t = T[i];
      if (t === 0) continue;
      const kd = KIND[t];
      if (kd === K_SOLID) { if (REACT[t] && rand() < 0.06) reactSolid(i, wx, y, t); continue; }
      if (S[i] === st) continue;
      if (kd === K_POWDER) stepPowder(i, wx, y, t, st);
      else if (kd === K_LIQUID) stepLiquid(i, wx, y, t, st);
      else if (kd === K_GAS) stepGas(i, wx, y, t, st);
      else if (kd === K_FIRE) stepFire(i, wx, y, t, st);
    }
  }
}

function isHot(t) { return t === M.LAVA || t === M.FIRE; }
function nearHeat(i, wx, y) {
  const xl = wx === 0 ? W - 1 : wx - 1, xr = wx === W - 1 ? 0 : wx + 1, row = y * W;
  return isHot(T[i - W]) || isHot(T[i + W]) || isHot(T[row + xl]) || isHot(T[row + xr]);
}

function tryMv(t, i, j, wx, y, nx, ny, st) {
  if (DISP[t * NM + T[j]]) { mv(i, j, wx, y, nx, ny, st); return true; }
  return false;
}

function stepPowder(i, wx, y, t, st) {
  if (t === M.SNOW && rand() < 0.03 && nearHeat(i, wx, y)) { chg(i, wx, y, M.WATER); return; }
  const b = i + W, tb = T[b];
  if (DISP[t * NM + tb]) {
    if (KIND[tb] === K_LIQUID && rand() < 0.55) return; // sinking through liquid is slower
    mv(i, b, wx, y, wx, y + 1, st); return;
  }
  const slide = (t === M.SNOW || t === M.ASH) ? 0.3 : (t === M.GRAVEL ? 0.65 : 1);
  if (rand() > slide) return;
  const xl = wx === 0 ? W - 1 : wx - 1, xr = wx === W - 1 ? 0 : wx + 1, by = (y + 1) * W;
  if (rand() < 0.5) {
    if (tryMv(t, i, by + xl, wx, y, xl, y + 1, st)) return;
    tryMv(t, i, by + xr, wx, y, xr, y + 1, st);
  } else {
    if (tryMv(t, i, by + xr, wx, y, xr, y + 1, st)) return;
    tryMv(t, i, by + xl, wx, y, xl, y + 1, st);
  }
}

function lavaTouch(i, wx, y, n, nx, ny) {
  const nt = T[n];
  if (nt === 0) return false;
  if (nt === M.WATER) {
    chg(i, wx, y, M.OBSIDIAN);
    T[n] = M.STEAM; L[n] = 50 + ((rand() * 60) | 0);
    return true;
  }
  if (FUEL[nt]) { if (rand() < IGN[nt] * 2) chg(n, nx, ny, M.FIRE, FUEL[nt]); }
  else if ((nt === M.SNOW || nt === M.ICE) && rand() < 0.05) chg(n, nx, ny, M.WATER);
  else if (nt === M.SAND && rand() < 0.003) T[n] = M.GLASS;
  return false;
}
function lavaReact(i, wx, y) {
  const xl = wx === 0 ? W - 1 : wx - 1, xr = wx === W - 1 ? 0 : wx + 1, row = y * W;
  if (lavaTouch(i, wx, y, i - W, wx, y - 1)) return true;
  if (lavaTouch(i, wx, y, i + W, wx, y + 1)) return true;
  if (lavaTouch(i, wx, y, row + xl, xl, y)) return true;
  if (lavaTouch(i, wx, y, row + xr, xr, y)) return true;
  if (T[i - W] === 0 && rand() < 0.0012) { T[i - W] = M.FIRE; L[i - W] = 6 + ((rand() * 12) | 0); }
  return false;
}

function flow(i, wx, y, t, d, n, row, st) {
  let best = -1, nx = wx;
  for (let s = 0; s < n; s++) {
    nx += d; if (nx < 0) nx += W; else if (nx >= W) nx -= W;
    const j = row + nx;
    if (!DISP[t * NM + T[j]]) break;
    best = nx;
    if (DISP[t * NM + T[j + W]]) break;
  }
  if (best < 0) return false;
  mv(i, row + best, wx, y, best, y, st);
  return true;
}

function stepLiquid(i, wx, y, t, st) {
  if (t === M.LAVA) { if (lavaReact(i, wx, y)) return; if (rand() < 0.5) return; }
  else if (t === M.MUD) { if (rand() < 0.7) return; }
  else if (t === M.WATER) {
    if (T[i - W] === 0) {
      // thin puddles soak into soil; sunlit surface water slowly evaporates
      const tb = T[i + W];
      if ((tb === M.DIRT || tb === M.GRASS || tb === M.SAND) && rand() < 0.002) { chg(i, wx, y, 0); return; }
      if (sim.daylight > 0.75 && rand() < 0.00003 && y <= skyTop[wx]) { chg(i, wx, y, 0); return; }
    }
  }
  const b = i + W;
  if (DISP[t * NM + T[b]]) { mv(i, b, wx, y, wx, y + 1, st); return; }
  const xl = wx === 0 ? W - 1 : wx - 1, xr = wx === W - 1 ? 0 : wx + 1, by = (y + 1) * W;
  const d = rand() < 0.5 ? -1 : 1;
  const a = d < 0 ? xl : xr, c = d < 0 ? xr : xl;
  if (DISP[t * NM + T[by + a]]) { mv(i, by + a, wx, y, a, y + 1, st); return; }
  if (DISP[t * NM + T[by + c]]) { mv(i, by + c, wx, y, c, y + 1, st); return; }
  const n = DISPERSE[t], row = y * W;
  if (flow(i, wx, y, t, d, n, row, st)) return;
  flow(i, wx, y, t, -d, n, row, st);
}

function stepGas(i, wx, y, t, st) {
  let l = L[i];
  if (l > 0) L[i] = --l;
  if (l === 0 || y <= 2) {
    if (t === M.STEAM && rand() < 0.3) chg(i, wx, y, M.WATER); else chg(i, wx, y, 0);
    return;
  }
  if (rand() < 0.2) return;
  const u = i - W;
  if (T[u] === 0) { mv(i, u, wx, y, wx, y - 1, st); return; }
  const xl = wx === 0 ? W - 1 : wx - 1, xr = wx === W - 1 ? 0 : wx + 1, uy = (y - 1) * W;
  const left = rand() < 0.5;
  const a = left ? xl : xr, c = left ? xr : xl;
  if (T[uy + a] === 0) { mv(i, uy + a, wx, y, a, y - 1, st); return; }
  if (T[uy + c] === 0) { mv(i, uy + c, wx, y, c, y - 1, st); return; }
  const sIdx = y * W + a;
  if (T[sIdx] === 0) mv(i, sIdx, wx, y, a, y, st);
}

function ignite(n, nx, ny) {
  const nt = T[n];
  if (FUEL[nt] && rand() < IGN[nt]) chg(n, nx, ny, M.FIRE, FUEL[nt]);
}

function stepFire(i, wx, y, t, st) {
  const xl = wx === 0 ? W - 1 : wx - 1, xr = wx === W - 1 ? 0 : wx + 1, row = y * W;
  const up = i - W, dn = i + W, lf = row + xl, rt = row + xr;
  if (T[up] === M.WATER || T[dn] === M.WATER || T[lf] === M.WATER || T[rt] === M.WATER) {
    T[i] = M.STEAM; L[i] = 30; return;
  }
  ignite(up, wx, y - 1); ignite(dn, wx, y + 1); ignite(lf, xl, y); ignite(rt, xr, y);
  const l = L[i];
  if (l <= 1) {
    const r = rand();
    if (r < 0.3) { T[i] = M.SMOKE; L[i] = 40 + ((rand() * 50) | 0); }
    else if (r < 0.34) chg(i, wx, y, M.ASH);
    else { T[i] = 0; L[i] = 0; }
    return;
  }
  L[i] = l - 1;
  if (T[up] === 0) {
    if (rand() < 0.03) { T[up] = M.SMOKE; L[up] = 40 + ((rand() * 40) | 0); S[up] = st; }
    else if (l < 24 && rand() < 0.45) mv(i, up, wx, y, wx, y - 1, st);
  }
}

function reactSolid(i, wx, y, t) {
  if (t === M.ICE) { if (nearHeat(i, wx, y)) chg(i, wx, y, M.WATER); }
  else if (t === M.FROST) {
    const xl = wx === 0 ? W - 1 : wx - 1, xr = wx === W - 1 ? 0 : wx + 1, row = y * W;
    const ns = [i - W, i + W, row + xl, row + xr];
    const n = ns[(rand() * 4) | 0];
    if (T[n] === M.WATER) T[n] = M.ICE;
  } else if (t === M.GRASS) {
    const u = T[i - W];
    if (u !== 0 && BLOCK[u] && u !== M.LEAF && u !== M.WOOD) chg(i, wx, y, M.DIRT);
  }
}
