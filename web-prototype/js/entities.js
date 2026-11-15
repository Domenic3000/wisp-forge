'use strict';
// ---------------------------------------------------------------------------
// Player, enemies, bodies vs. the pixel world, particles.
// ---------------------------------------------------------------------------

function solidAt(x, y) {
  if (y < 0) return false;
  if (y >= H) return true;
  const t = T[y * W + wrapX(x)];
  return BLOCK[t] === 1;
}
function boxSolid(x, y, w, h) {
  const x0 = Math.floor(x), x1 = Math.floor(x + w - 0.001), y0 = Math.floor(y), y1 = Math.floor(y + h - 0.001);
  for (let yy = y0; yy <= y1; yy++) for (let xx = x0; xx <= x1; xx++) if (solidAt(xx, yy)) return true;
  return false;
}
function boxCount(x, y, w, h, mat) {
  const x0 = Math.floor(x), x1 = Math.floor(x + w - 0.001), y0 = Math.floor(y), y1 = Math.floor(y + h - 0.001);
  let n = 0;
  for (let yy = y0; yy <= y1; yy++) for (let xx = x0; xx <= x1; xx++) if (getT(xx, yy) === mat) n++;
  return n;
}

// Moves a body through the world with sub-stepping and small-step climbing.
function moveBody(e) {
  e.hitWall = false;
  let dx = e.vx;
  while (dx !== 0) {
    const st = Math.abs(dx) > 0.5 ? 0.5 * Math.sign(dx) : dx;
    if (!boxSolid(e.x + st, e.y, e.w, e.h)) e.x += st;
    else {
      let climbed = false;
      if (e.stepH && (e.onGround || e.inLiquid)) {
        for (let up = 1; up <= e.stepH; up++) {
          if (!boxSolid(e.x + st, e.y - up, e.w, e.h)) { e.x += st; e.y -= up; climbed = true; break; }
        }
      }
      if (!climbed) { e.vx = 0; e.hitWall = true; break; }
    }
    dx -= st;
    if (Math.abs(dx) < 1e-6) dx = 0;
  }
  e.onGround = false;
  let dy = e.vy;
  while (dy !== 0) {
    const st = Math.abs(dy) > 0.5 ? 0.5 * Math.sign(dy) : dy;
    if (!boxSolid(e.x, e.y + st, e.w, e.h)) e.y += st;
    else { if (st > 0) e.onGround = true; e.vy = 0; break; }
    dy -= st;
    if (Math.abs(dy) < 1e-6) dy = 0;
  }
  if (!e.onGround && e.vy >= 0 && boxSolid(e.x, e.y + 0.6, e.w, e.h)) e.onGround = true;
  e.x = ((e.x % W) + W) % W;
  if (e.y < 1) { e.y = 1; if (e.vy < 0) e.vy = 0; }
  if (e.y > H - e.h - 1) e.y = H - e.h - 1;
}

// push an entity out of terrain that fell/was placed into it
function unstick(e) {
  if (!boxSolid(e.x, e.y, e.w, e.h)) return;
  for (let up = 1; up <= 6; up++) if (!boxSolid(e.x, e.y - up, e.w, e.h)) { e.y -= up; return; }
}

function gravityAt(y) { return y > 200 ? 1 : Math.max(0.06, (y - 30) / 170); }

// ---------------------------------------------------------------- player ----
const player = {
  x: 0, y: 0, w: 5, h: 12, vx: 0, vy: 0, stepH: 3, onGround: false, inLiquid: false, hitWall: false,
  facing: 1, hp: 100, maxHp: 100, mana: 100, maxMana: 100, manaRegen: 0.22, breath: 600, maxBreath: 600,
  inv: new Int32Array(NM), items: {}, known: ['spark', 'conjure'], tier: 1, digR: 2.5, heatWard: false,
  iframes: 0, airTime: 0, dead: false, sel: 0, mat: M.DIRT, castCd: 0, hurtFlash: 0, walkAnim: 0,
};

function playerCenter() { return [player.x + player.w / 2, player.y + player.h / 2]; }

function hurtPlayer(d, kx, ky) {
  if (player.dead) return;
  if (kx !== undefined) {
    if (player.iframes > 0) return;
    player.iframes = 40; player.vx += kx; player.vy += ky;
  }
  player.hp -= d; player.hurtFlash = Math.min(1, player.hurtFlash + (kx !== undefined ? 0.6 : 0.05));
  if (player.hp <= 0) { player.hp = 0; onPlayerDeath(); }
}

function updatePlayer(input) {
  const p = player;
  if (p.dead) return;
  const midT = getT(p.x + p.w / 2, p.y + p.h * 0.6), headT = getT(p.x + p.w / 2, p.y + 2);
  p.inLiquid = KIND[midT] === K_LIQUID;
  const g = 0.17 * gravityAt(p.y);

  let move = 0;
  if (input.left) move -= 1;
  if (input.right) move += 1;
  if (move) p.facing = move;
  const speed = p.inLiquid ? 0.6 : 1.05;
  p.vx += (move * speed - p.vx) * (p.onGround ? 0.35 : 0.12);

  if (p.onGround) p.airTime = 0; else p.airTime++;
  if (input.jumpPressed && (p.onGround || p.inLiquid)) { p.vy = p.inLiquid ? -1.8 : -3.0; }
  // levitation: hold jump in the air to float on mana
  if (input.jump && !p.onGround && !p.inLiquid && p.airTime > 10 && p.mana > 0.5) {
    p.vy -= g + 0.2; if (p.vy < -1.9) p.vy = -1.9; p.mana -= 0.55;
    if (Math.random() < 0.6) spawnParticle(p.x + 1 + Math.random() * 3, p.y + p.h, (Math.random() - 0.5) * 0.4, 0.4 + Math.random() * 0.4, 18, 140, 220, 255, true, 0);
  }
  if (p.inLiquid) {
    if (input.jump) p.vy -= 0.26;
    p.vy += g * 0.3; p.vx *= midT === M.MUD ? 0.7 : 0.9; p.vy *= midT === M.MUD ? 0.75 : 0.9;
  } else {
    p.vy += g;
  }
  if (p.vy > 4.5) p.vy = 4.5;
  moveBody(p);
  unstick(p);
  if (move && p.onGround) p.walkAnim += 0.25;

  // hazards
  const lava = boxCount(p.x, p.y, p.w, p.h, M.LAVA), fire = boxCount(p.x, p.y, p.w, p.h, M.FIRE);
  if (lava) hurtPlayer((p.heatWard ? 0.08 : 0.55) * Math.min(lava, 6));
  if (fire) hurtPlayer((p.heatWard ? 0.02 : 0.08) * Math.min(fire, 6));
  const wx = wrapX(Math.floor(p.x));
  if (p.y > magmaY[wx] - 20 && !p.heatWard) hurtPlayer(0.05);
  if (KIND[headT] === K_LIQUID) { p.breath--; if (p.breath <= 0) { p.breath = 0; hurtPlayer(0.25); } }
  else p.breath = Math.min(p.maxBreath, p.breath + 4);

  if (p.iframes > 0) p.iframes--;
  p.hurtFlash *= 0.9;
  if (p.castCd > 0) p.castCd--;
  p.mana = Math.min(p.maxMana, p.mana + p.manaRegen);
  if (p.hp < p.maxHp) p.hp = Math.min(p.maxHp, p.hp + 0.02);
}

// ---------------------------------------------------------------- enemies ---
const ENEMY = {
  slime: { w: 8, h: 6, hp: 26, dmg: 9, fly: false, spr: 'slime', drops: [[M.WISP, 1, 0.35], [M.WATER, 4, 1]], light: [0.1, 0.3, 0.1] },
  bat: { w: 7, h: 4, hp: 16, dmg: 7, fly: true, spr: 'bat1', drops: [[M.COAL, 2, 0.8], [M.SHROOM, 2, 0.5]] },
  imp: { w: 6, h: 8, hp: 34, dmg: 11, fly: true, spr: 'imp', drops: [[M.EMBER, 3, 1], [M.OBSIDIAN, 2, 0.4]], light: [0.6, 0.2, 0.05] },
  golem: { w: 14, h: 18, hp: 900, dmg: 18, fly: false, spr: 'golem', boss: true, name: 'Vulkhar, the Ember Golem', light: [1.0, 0.4, 0.1] },
};
const enemies = [];

function spawnEnemy(type, x, y) {
  const d = ENEMY[type];
  const e = { type, d, x, y, w: d.w, h: d.h, vx: 0, vy: 0, hp: d.hp, maxHp: d.hp, t: 30 + Math.random() * 60, shootT: 120, flash: 0, onGround: false, inLiquid: false, stepH: d.fly ? 0 : (d.boss ? 4 : 1), facing: 1, phase: Math.random() * 6, awake: !d.boss, slow: 0 };
  enemies.push(e);
  return e;
}

function hurtEnemy(e, dmg, kx, ky) {
  e.hp -= dmg; e.flash = 6;
  if (!e.d.boss) { e.vx += kx || 0; e.vy += ky || 0; }
  e.awake = true;
  if (e.hp <= 0 && !e.dead) killEnemy(e);
}

function killEnemy(e) {
  e.dead = true;
  for (let k = 0; k < (e.d.boss ? 120 : 16); k++) spawnParticle(e.x + Math.random() * e.w, e.y + Math.random() * e.h, (Math.random() - 0.5) * 2, -Math.random() * 2, 30 + Math.random() * 30, 255, 180, 80, true, 0.05);
  if (e.d.drops) for (const [m, n, ch] of e.d.drops) if (Math.random() < ch) { const c = 1 + Math.floor(Math.random() * n); player.inv[m] += c; toast(`+${c} ${MINFO[m].name}`, MINFO[m].color); }
  if (e.d.boss) {
    player.items.heart = true;
    player.inv[M.EMBER] += 40; player.inv[M.OBSIDIAN] += 20;
    toast('Vulkhar falls! You claim the EMBER HEART.', '#ffb14a', 6000);
    toast('+40 Ember Crystal, +20 Obsidian. The Core Siphon can now be forged.', '#ffd23a', 6000);
    shake = 18;
    saveGame();
  }
}

function enemyLiquidCheck(e) {
  const t = getT(e.x + e.w / 2, e.y + e.h / 2);
  e.inLiquid = KIND[t] === K_LIQUID;
  return t;
}

function updateEnemies() {
  const [pcx, pcy] = playerCenter();
  for (let k = enemies.length - 1; k >= 0; k--) {
    const e = enemies[k];
    if (e.dead) { enemies.splice(k, 1); continue; }
    const ecx = e.x + e.w / 2, ecy = e.y + e.h / 2;
    const dx = wdx(pcx, ecx), dy = pcy - ecy, dist = Math.hypot(dx, dy);
    if (!e.d.boss && dist > 420) { enemies.splice(k, 1); continue; }
    if (e.flash > 0) e.flash--;
    const slowF = e.slow > 0 ? 0.4 : 1; if (e.slow > 0) e.slow--;
    const lt = enemyLiquidCheck(e);
    const g = 0.17 * gravityAt(e.y);
    e.facing = dx < 0 ? -1 : 1;
    if (player.dead) { e.vx *= 0.9; }

    if (e.type === 'slime') {
      if (e.onGround) {
        e.vx *= 0.75; e.t--;
        if (e.t <= 0 && dist < 160) { e.vx = Math.sign(dx) * (1.0 + Math.random() * 0.6) * slowF; e.vy = -2.3 - Math.random() * 0.8; e.t = 45 + Math.random() * 50; }
      }
      e.vy += e.inLiquid ? g * 0.3 : g; if (e.inLiquid) e.vy *= 0.9;
    } else if (e.type === 'bat') {
      e.phase += 0.12;
      const tx = Math.sign(dx) * 0.09, ty = Math.sign(dy + Math.sin(e.phase) * 14) * 0.08;
      if (dist < 200) { e.vx += tx; e.vy += ty; } else { e.vx += (Math.random() - 0.5) * 0.1; e.vy += (Math.random() - 0.5) * 0.1; }
      const sp = 1.25 * slowF; e.vx = Math.max(-sp, Math.min(sp, e.vx)); e.vy = Math.max(-sp, Math.min(sp, e.vy));
      if (e.hitWall) e.vy -= 0.3;
    } else if (e.type === 'imp') {
      e.phase += 0.05;
      const want = 45, ax = dist > want ? Math.sign(dx) : -Math.sign(dx);
      e.vx += ax * 0.04; e.vy += (Math.sign(dy - 20 + Math.sin(e.phase) * 10)) * 0.04;
      const sp = 0.75 * slowF; e.vx = Math.max(-sp, Math.min(sp, e.vx)); e.vy = Math.max(-sp, Math.min(sp, e.vy));
      e.shootT--;
      if (e.shootT <= 0 && dist < 150 && !player.dead) { const a = Math.atan2(dy, dx); spawnProj('efire', ecx, ecy, Math.cos(a) * 1.7, Math.sin(a) * 1.7, 'enemy'); e.shootT = 140 + Math.random() * 60; }
    } else if (e.type === 'golem') {
      if (!e.awake && dist < 110) { e.awake = true; toast('VULKHAR, THE EMBER GOLEM awakens!', '#ff7a2a', 4000); shake = 10; }
      if (e.awake && !player.dead) {
        const enraged = e.hp < e.maxHp * 0.4;
        if (e.onGround) e.vx += (Math.sign(dx) * (enraged ? 0.75 : 0.5) * slowF - e.vx) * 0.1;
        e.t--; e.shootT--;
        if (e.shootT <= 0) {
          const n = enraged ? 7 : 5, a0 = Math.atan2(dy, dx);
          for (let s = 0; s < n; s++) { const a = a0 + (s - (n - 1) / 2) * 0.18; spawnProj('efire', ecx, e.y + 4, Math.cos(a) * 1.9, Math.sin(a) * 1.9, 'enemy'); }
          e.shootT = enraged ? 110 : 170;
        }
        if (e.t <= 0 && e.onGround) { e.vy = -4.2; e.vx = Math.sign(dx) * 1.6; e.t = enraged ? 160 : 260; e.leaping = true; }
        if (e.leaping && e.onGround && e.vy === 0) { e.leaping = false; shake = 12; explodeAt(ecx, e.y + e.h + 1, 6, 1, { noDamageEnemies: true, dmg: 0 }); if (Math.abs(dx) < 26 && Math.abs(dy) < 20) hurtPlayer(18, Math.sign(dx) * 3, -2); }
      }
      e.vy += g;
    }
    if (e.d.fly) { e.vy *= 0.98; } else if (e.vy > 4.5) e.vy = 4.5;
    moveBody(e);
    unstick(e);
    // environmental damage
    if (e.type !== 'golem' && e.type !== 'imp') { const lv = boxCount(e.x, e.y, e.w, e.h, M.LAVA); if (lv) hurtEnemy(e, 0.6, 0, 0); }
    // contact damage
    if (!player.dead && Math.abs(wdx(pcx, ecx)) < (e.w + player.w) / 2 && Math.abs(pcy - ecy) < (e.h + player.h) / 2) {
      hurtPlayer(e.d.dmg, Math.sign(dx) * 2.2, -1.6);
    }
    if (e.d.light) addLight(ecx, ecy, e.d.boss ? 40 : 14, e.d.light[0], e.d.light[1], e.d.light[2]);
  }
}

let spawnTimer = 0;
function trySpawnEnemies(night) {
  if (--spawnTimer > 0) return;
  spawnTimer = 90;
  const count = enemies.filter(e => !e.d.boss).length;
  if (count >= 7 || player.dead) return;
  const px = player.x, py = player.y, wx = wrapX(Math.floor(px));
  let type;
  if (py < surf0[wx] + 14) { if (Math.random() > (night ? 0.7 : 0.25)) return; type = 'slime'; }
  else if (py < deepY[wx]) { if (Math.random() > 0.45) return; type = 'bat'; }
  else if (py < magmaY[wx]) { if (Math.random() > 0.5) return; type = Math.random() < 0.6 ? 'bat' : 'imp'; }
  else { if (Math.random() > 0.5) return; type = 'imp'; }
  const d = ENEMY[type];
  for (let tries = 0; tries < 12; tries++) {
    const side = Math.random() < 0.5 ? -1 : 1;
    const x = wrapX(Math.floor(px + side * (VW / 2 + 10 + Math.random() * 40)));
    const y = Math.floor(py + (Math.random() - 0.5) * VH * 0.8);
    if (y < 5 || y > H - 30) continue;
    if (!boxSolid(x, y, d.w, d.h) && KIND[getT(x, y)] !== K_LIQUID) { spawnEnemy(type, x, y); return; }
  }
}

// -------------------------------------------------------------- particles ---
const parts = [];
function spawnParticle(x, y, vx, vy, life, r, g, b, self, grav) {
  if (parts.length > 1500) return;
  parts.push({ x, y, vx, vy, life, r, g, b, self, grav: grav ?? 0.08, tx: null });
}
function updateParticles() {
  const [pcx, pcy] = playerCenter();
  for (let k = parts.length - 1; k >= 0; k--) {
    const p = parts[k];
    if (p.homing) { // collected material flying to the mage
      const dx = wdx(pcx, p.x), dy = pcy - p.y, d = Math.hypot(dx, dy) || 1;
      p.vx += dx / d * 0.35; p.vy += dy / d * 0.35; p.vx *= 0.9; p.vy *= 0.9;
      if (d < 3) p.life = 0;
    } else p.vy += p.grav;
    p.x += p.vx; p.y += p.vy; p.life--;
    if (p.life <= 0) parts.splice(k, 1);
  }
}

// ---------------------------------------------------------------- drawing ---
function drawSprite(spr, wx, wy, flip, white) {
  const rows = spr.rows, pl = spr.pal, sx0 = scrX(wx), sy0 = Math.floor(wy) - camY;
  const w = rows[0].length;
  for (let r = 0; r < rows.length; r++) {
    const row = rows[r];
    for (let c = 0; c < w; c++) {
      const ch = row[flip ? w - 1 - c : c];
      if (ch === '.') continue;
      const col = pl[ch];
      if (white) putPx(sx0 + c, sy0 + r, 255, 255, 255, true);
      else putPx(sx0 + c, sy0 + r, col[0], col[1], col[2], col[3]);
    }
  }
}

const wisp = { x: 0, y: 0, t: 0 };
function drawPlayerAndWisp(aimX, aimY, spellColor) {
  const p = player;
  if (!p.dead) {
    const blink = p.iframes > 0 && (p.iframes >> 2) % 2 === 0;
    if (!blink) drawSprite(SPR.mage, p.x - 1, p.y, p.facing < 0, false);
    // staff from the hand toward the aim point
    const hx = p.x + p.w / 2 + p.facing * 2, hy = p.y + 7;
    const dx = wdx(aimX, hx), dy = aimY - hy, d = Math.hypot(dx, dy) || 1;
    for (let s = 0; s <= 6; s++) putPx(scrX(hx + dx / d * s), Math.floor(hy + dy / d * s) - camY, 120, 82, 44, false);
    const tx = hx + dx / d * 7, ty = hy + dy / d * 7;
    putPx(scrX(tx), Math.floor(ty) - camY, spellColor[0], spellColor[1], spellColor[2], true);
    addLight(tx, ty, 10, spellColor[0] / 400, spellColor[1] / 400, spellColor[2] / 400);
  }
  // the wisp companion — your light in the dark
  wisp.t += 0.05;
  const tgx = p.x + p.w / 2 - p.facing * 7, tgy = p.y - 4 + Math.sin(wisp.t * 2) * 2;
  wisp.x += wdx(tgx, wisp.x) * 0.08; wisp.y += (tgy - wisp.y) * 0.08;
  wisp.x = wrapX(wisp.x);
  const wsx = scrX(wisp.x), wsy = Math.floor(wisp.y) - camY;
  putPx(wsx, wsy, 230, 250, 255, true); putPx(wsx + 1, wsy, 160, 220, 255, true);
  putPx(wsx, wsy + 1, 160, 220, 255, true); putPx(wsx + 1, wsy + 1, 120, 190, 255, true);
  if (Math.random() < 0.3) spawnParticle(wisp.x + Math.random() * 2, wisp.y + Math.random() * 2, (Math.random() - 0.5) * 0.2, 0.05, 20, 120, 200, 255, true, -0.005);
  addLight(wisp.x, wisp.y, 46, 0.95, 1.0, 1.1);
}

function drawEnemies() {
  for (const e of enemies) {
    let spr = SPR[e.d.spr];
    if (e.type === 'bat') spr = ((e.phase * 2) | 0) % 2 ? SPR.bat1 : SPR.bat2;
    drawSprite(spr, e.x, e.y, e.facing < 0, e.flash > 0);
  }
}

function drawParticles() {
  for (const p of parts) {
    const sx = scrX(p.x), sy = Math.floor(p.y) - camY;
    if (p.streak) { blendPx(sx, sy, p.r, p.g, p.b, 0.55, false); blendPx(sx, sy - 1, p.r, p.g, p.b, 0.35, false); blendPx(sx + 1, sy - 2, p.r, p.g, p.b, 0.2, false); }
    else putPx(sx, sy, p.r, p.g, p.b, p.self);
  }
}
