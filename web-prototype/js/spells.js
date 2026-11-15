'use strict';
// ---------------------------------------------------------------------------
// Spells, projectiles and the terrain-shaping magic (excavate / conjure).
// ---------------------------------------------------------------------------
const SPELLS = {
  spark: { name: 'Spark Bolt', mana: 4, cd: 9, color: [255, 230, 128], desc: 'A quick bolt. Chips terrain, stings foes.' },
  conjure: { name: 'Conjure', mana: 0, cd: 2, color: [190, 255, 190], desc: 'Place the selected material from your satchel. Q/E to choose.' },
  fireball: { name: 'Fireball', mana: 18, cd: 28, color: [255, 120, 40], desc: 'Explodes and ignites anything that burns.' },
  tide: { name: 'Tidecall', mana: 14, cd: 22, color: [90, 160, 255], desc: 'Bursts into a wave of water. Cools lava into obsidian.' },
  frost: { name: 'Frostbite', mana: 12, cd: 18, color: [170, 240, 255], desc: 'Freezes water to ice and lava to obsidian. Slows foes.' },
  quake: { name: 'Quake Orb', mana: 40, cd: 60, color: [200, 140, 255], desc: 'A heavy orb that shatters a huge cavity.' },
};
const SPELL_ORDER = ['spark', 'conjure', 'fireball', 'tide', 'frost', 'quake'];

const PROJ = {
  spark: { speed: 4.2, g: 0, life: 55, dmg: 11, col: [255, 230, 128], light: 14 },
  fireball: { speed: 3.0, g: 0.035, life: 140, dmg: 0, col: [255, 120, 40], light: 26 },
  tide: { speed: 2.7, g: 0.07, life: 120, dmg: 6, col: [90, 160, 255], light: 12 },
  frost: { speed: 3.6, g: 0, life: 80, dmg: 14, col: [170, 240, 255], light: 16 },
  quake: { speed: 2.3, g: 0.09, life: 160, dmg: 0, col: [200, 140, 255], light: 22 },
  efire: { speed: 1.7, g: 0, life: 200, dmg: 12, col: [255, 90, 30], light: 14 },
};
const projs = [];

function spawnProj(type, x, y, vx, vy, owner) { projs.push({ type, d: PROJ[type], x, y, vx, vy, life: PROJ[type].life, owner }); }

function staffTip(aimX, aimY) {
  const hx = player.x + player.w / 2 + player.facing * 2, hy = player.y + 7;
  const dx = wdx(aimX, hx), dy = aimY - hy, d = Math.hypot(dx, dy) || 1;
  return [hx + dx / d * 7, hy + dy / d * 7, dx / d, dy / d];
}

function castSpell(id, aimX, aimY) {
  const s = SPELLS[id], p = player;
  if (p.castCd > 0 || p.mana < s.mana || p.dead) return;
  const [tx, ty, nx, ny] = staffTip(aimX, aimY);
  if (id === 'conjure') { conjure(aimX, aimY); p.castCd = s.cd; return; }
  p.mana -= s.mana; p.castCd = s.cd;
  const sp = PROJ[id].speed;
  spawnProj(id, tx, ty, nx * sp, ny * sp, 'player');
  for (let k = 0; k < 6; k++) spawnParticle(tx, ty, nx * 0.8 + (Math.random() - 0.5), ny * 0.8 + (Math.random() - 0.5), 12, s.color[0], s.color[1], s.color[2], true, 0);
}

function updateProjectiles() {
  for (let k = projs.length - 1; k >= 0; k--) {
    const pr = projs[k], d = pr.d;
    pr.vy += d.g; pr.life--;
    const steps = Math.ceil(Math.max(Math.abs(pr.vx), Math.abs(pr.vy)) * 2) || 1;
    let hit = false;
    for (let s = 0; s < steps && !hit; s++) {
      pr.x = wrapX(pr.x + pr.vx / steps); pr.y += pr.vy / steps;
      if (pr.y < 1 || pr.y >= H - 1) { hit = true; break; }
      const t = getT(pr.x, pr.y);
      if (BLOCK[t]) { hit = true; break; }
      if ((pr.type === 'fireball' || pr.type === 'efire') && t === M.WATER) { setCell(pr.x, Math.floor(pr.y), M.STEAM, 60); pr.life = 0; break; }
      if (pr.owner === 'player') {
        for (const e of enemies) if (!e.dead && Math.abs(wdx(pr.x, e.x + e.w / 2)) < e.w / 2 + 1 && Math.abs(pr.y - (e.y + e.h / 2)) < e.h / 2 + 1) { hit = true; pr.hitEnemy = e; break; }
      } else if (!player.dead) {
        if (Math.abs(wdx(pr.x, player.x + player.w / 2)) < 3 && Math.abs(pr.y - (player.y + player.h / 2)) < 6) { hit = true; pr.hitPlayer = true; }
      }
    }
    if (hit || pr.life <= 0) { impact(pr, hit); projs.splice(k, 1); continue; }
    addLight(pr.x, pr.y, d.light, d.col[0] / 300, d.col[1] / 300, d.col[2] / 300);
    if (Math.random() < 0.6) spawnParticle(pr.x, pr.y, (Math.random() - 0.5) * 0.3, (Math.random() - 0.5) * 0.3, 10 + Math.random() * 8, d.col[0], d.col[1], d.col[2], true, 0);
  }
}

function impact(pr, hit) {
  const x = pr.x, y = pr.y, e = pr.hitEnemy;
  const kb = Math.sign(pr.vx) * 1.2;
  switch (pr.type) {
    case 'spark':
      if (e) hurtEnemy(e, pr.d.dmg, kb, -0.6);
      else if (hit) breakCells(x, y, 1.6, player.tier);
      break;
    case 'fireball': explodeAt(x, y, 7, Math.max(1, player.tier), { fire: true, dmg: 38 }); break;
    case 'quake': explodeAt(x, y, 15, Math.min(3, player.tier + 1), { gravel: true, dmg: 70 }); break;
    case 'tide': fillCircle(x, y, 5.5, M.WATER); if (e) hurtEnemy(e, pr.d.dmg, kb * 2, -1); break;
    case 'frost': freezeAt(x, y, 7); if (e) { hurtEnemy(e, pr.d.dmg, kb, 0); e.slow = 240; } break;
    case 'efire':
      if (pr.hitPlayer) hurtPlayer(pr.d.dmg * (player.heatWard ? 0.6 : 1), Math.sign(pr.vx) * 1.5, -1);
      else { const t = getT(x, y - 1); if (t === 0) setCell(x, Math.floor(y) - 1, M.FIRE, 20); }
      break;
  }
  const c = pr.d.col;
  for (let k = 0; k < 10; k++) spawnParticle(x, y, (Math.random() - 0.5) * 1.6, (Math.random() - 0.8) * 1.4, 14 + Math.random() * 10, c[0], c[1], c[2], true, 0.05);
}

// ---------------------------------------------------------------- terrain ---
function canBreak(t, power) { return t !== 0 && BLOCK[t] && HARD[t] <= power; }

function breakCells(x, y, r, power) {
  const ri = Math.ceil(r), cx = Math.floor(x), cy = Math.floor(y);
  for (let dy = -ri; dy <= ri; dy++) for (let dx = -ri; dx <= ri; dx++) {
    if (dx * dx + dy * dy > r * r) continue;
    const yy = cy + dy; if (yy < 0 || yy >= H) continue;
    const t = getT(cx + dx, yy);
    if (canBreak(t, power) && Math.random() < 0.7) {
      setCell(cx + dx, yy, KIND[t] === K_SOLID && Math.random() < 0.25 && HARD[t] >= 1 ? M.GRAVEL : 0);
      debris(cx + dx, yy, t);
    }
  }
}

function debris(x, y, t) {
  if (Math.random() > 0.35) return;
  const o = t * 12;
  spawnParticle(x + 0.5, y + 0.5, (Math.random() - 0.5) * 1.5, -Math.random() * 1.5, 20 + Math.random() * 20, PAL[o], PAL[o + 1], PAL[o + 2], SELF[t] === 1, 0.12);
}

let shake = 0;
function explodeAt(x, y, r, power, o) {
  const ri = Math.ceil(r), cx = Math.floor(x), cy = Math.floor(y);
  for (let dy = -ri - 2; dy <= ri + 2; dy++) for (let dx = -ri - 2; dx <= ri + 2; dx++) {
    const d2 = dx * dx + dy * dy, yy = cy + dy;
    if (yy < 1 || yy >= H - 1) continue;
    const xx = cx + dx;
    const t = getT(xx, yy);
    if (d2 <= r * r) {
      if (t === 0 || KIND[t] === K_LIQUID || KIND[t] === K_GAS) { if (o.fire && t === 0 && Math.random() < 0.18) setCell(xx, yy, M.FIRE, 12 + Math.random() * 20); continue; }
      if (!canBreak(t, power)) continue;
      const edge = Math.sqrt(d2) / r;
      if (o.gravel && edge > 0.75 && (t === M.STONE || t === M.DEEPSTONE) && Math.random() < 0.5) setCell(xx, yy, M.GRAVEL);
      else if (o.fire && Math.random() < 0.12) setCell(xx, yy, M.FIRE, 10 + Math.random() * 25);
      else setCell(xx, yy, 0);
      debris(xx, yy, t);
    } else if (o.fire && FUEL[t] && d2 <= (r + 2) * (r + 2) && Math.random() < 0.5) {
      setCell(xx, yy, M.FIRE, FUEL[t]);
    }
  }
  for (let k = 0; k < r * 4; k++) spawnParticle(x, y, (Math.random() - 0.5) * 3, (Math.random() - 0.5) * 3, 15 + Math.random() * 20, 255, 160 + Math.random() * 80, 60, true, 0.03);
  addLight(x, y, r * 4, 1.5, 0.8, 0.3);
  shake = Math.max(shake, r * 0.6);
  if (o.dmg) {
    for (const e of enemies) {
      const d = Math.hypot(wdx(e.x + e.w / 2, x), e.y + e.h / 2 - y);
      if (d < r + 4 + e.w / 2) hurtEnemy(e, o.dmg * (1 - d / (r + 4 + e.w)), Math.sign(wdx(e.x, x)) * 2, -2);
    }
  }
}

function fillCircle(x, y, r, mat) {
  const ri = Math.ceil(r), cx = Math.floor(x), cy = Math.floor(y);
  for (let dy = -ri; dy <= ri; dy++) for (let dx = -ri; dx <= ri; dx++) {
    if (dx * dx + dy * dy > r * r) continue;
    const t = getT(cx + dx, cy + dy);
    if (t === 0 || KIND[t] === K_GAS || KIND[t] === K_FIRE) setCell(cx + dx, cy + dy, mat);
  }
}

function freezeAt(x, y, r) {
  const ri = Math.ceil(r), cx = Math.floor(x), cy = Math.floor(y);
  for (let dy = -ri; dy <= ri; dy++) for (let dx = -ri; dx <= ri; dx++) {
    if (dx * dx + dy * dy > r * r) continue;
    const yy = cy + dy, t = getT(cx + dx, yy);
    if (t === M.WATER) setCell(cx + dx, yy, M.ICE);
    else if (t === M.LAVA) setCell(cx + dx, yy, M.OBSIDIAN);
    else if (t === M.FIRE) setCell(cx + dx, yy, 0);
    else if (t === M.STEAM) setCell(cx + dx, yy, M.SNOW);
    else if (t === M.MUD) setCell(cx + dx, yy, M.DIRT);
  }
  for (const e of enemies) if (Math.hypot(wdx(e.x, x), e.y - y) < r + 6) e.slow = 200;
}

// clamp a target point to the mage's reach
const REACH = 42;
function reachPoint(aimX, aimY) {
  const [pcx, pcy] = playerCenter();
  let dx = wdx(aimX, pcx), dy = aimY - pcy;
  const d = Math.hypot(dx, dy);
  if (d > REACH) { dx *= REACH / d; dy *= REACH / d; }
  return [wrapX(pcx + dx), pcy + dy];
}

// Excavate: pull material out of the world into the satchel
let digBlocked = 0;
function excavate(aimX, aimY) {
  const [x, y] = reachPoint(aimX, aimY);
  const r = player.digR, ri = Math.ceil(r), cx = Math.floor(x), cy = Math.floor(y);
  let taken = 0;
  for (let dy = -ri; dy <= ri; dy++) for (let dx = -ri; dx <= ri; dx++) {
    if (dx * dx + dy * dy > r * r || taken > 14) continue;
    const yy = cy + dy; if (yy < 1 || yy >= H) continue;
    const t = getT(cx + dx, yy);
    if (t === 0 || KIND[t] === K_GAS || KIND[t] === K_FIRE || !MINFO[t].collect) continue;
    if (HARD[t] > player.tier) { digBlocked = 30; continue; }
    const rate = KIND[t] === K_LIQUID ? 0.25 : 0.32 / (1 + HARD[t] * 1.2);
    if (Math.random() > rate) continue;
    setCell(cx + dx, yy, 0);
    player.inv[t]++; taken++;
    if (Math.random() < 0.5) {
      const o = t * 12;
      parts.push({ x: cx + dx + 0.5, y: yy + 0.5, vx: (Math.random() - 0.5), vy: (Math.random() - 0.5), life: 60, r: PAL[o], g: PAL[o + 1], b: PAL[o + 2], self: true, grav: 0, homing: true });
    }
  }
  addLight(x, y, 10, 0.4, 0.8, 0.5);
}

function conjure(aimX, aimY) {
  const m = player.mat;
  if (!m || player.inv[m] <= 0) return;
  const [x, y] = reachPoint(aimX, aimY);
  const cx = Math.floor(x), cy = Math.floor(y), r = 1.6, ri = 2;
  for (let dy = -ri; dy <= ri; dy++) for (let dx = -ri; dx <= ri; dx++) {
    if (dx * dx + dy * dy > r * r || player.inv[m] <= 0) continue;
    const xx = cx + dx, yy = cy + dy;
    const t = getT(xx, yy);
    if (!(t === 0 || KIND[t] === K_GAS || KIND[t] === K_FIRE)) continue;
    if (BLOCK[m]) {
      const px = player.x, py = player.y;
      if (Math.abs(wdx(xx + 0.5, px + player.w / 2)) < player.w / 2 + 0.5 && yy >= py && yy < py + player.h) continue;
    }
    setCell(xx, yy, m, m === M.FIRE ? 30 : 0);
    player.inv[m]--;
  }
}
