'use strict';
// ---------------------------------------------------------------------------
// Boot, input, main loop, day/night + weather, camera, saving, planet travel.
// ---------------------------------------------------------------------------
const DAY_LEN = 60 * 60 * 7; // 7 minute day
const game = { state: 'title', time: 0, dayT: 0.3, rain: 0, rainTarget: 0, weatherTimer: 1800, flash: 0, saveTimer: 0, frame: 0 };
const input = { left: false, right: false, jump: false, jumpPressed: false, lmb: false, rmb: false, mx: 0, my: 0 };
let camXf = 0, camYf = 0;
let lastEnv = null;

// ------------------------------------------------------------------ input --
const keys = {};
window.addEventListener('keydown', e => {
  if (e.repeat && keys[e.code]) return;
  keys[e.code] = true;
  if (game.state === 'title' || game.state === 'loading') return;
  if (e.code === 'KeyC' || (e.code === 'Escape' && game.state === 'forge')) { toggleForge(); e.preventDefault(); return; }
  if (game.state !== 'play') return;
  if (e.code === 'Space' || e.code === 'KeyW' || e.code === 'ArrowUp') input.jumpPressed = true;
  if (e.code.startsWith('Digit')) { const n = +e.code.slice(5) - 1; if (n >= 0 && n < player.known.length) player.sel = n; }
  if (e.code === 'KeyQ' || e.code === 'KeyE') cycleMaterial(e.code === 'KeyE' ? 1 : -1);
  if (e.code === 'F9') { for (let m = 1; m < NM; m++) if (MINFO[m] && MINFO[m].collect) player.inv[m] += 200; toast('Creative stock: +200 of every material', '#9f9'); }
  if (e.code === 'Space' || e.code.startsWith('Arrow')) e.preventDefault();
});
window.addEventListener('keyup', e => { keys[e.code] = false; });
window.addEventListener('blur', () => { for (const k in keys) keys[k] = false; input.lmb = input.rmb = false; });

function cycleMaterial(dir) {
  const owned = [];
  for (let m = 1; m < NM; m++) if (player.inv[m] > 0 && MINFO[m].place) owned.push(m);
  if (!owned.length) return;
  let k = owned.indexOf(player.mat);
  k = (k + dir + owned.length) % owned.length;
  player.mat = owned[k];
  toast(`Conjure material: ${MINFO[player.mat].name}`, MINFO[player.mat].color, 900);
}

function initInput() {
  canvas.addEventListener('mousemove', e => { const r = canvas.getBoundingClientRect(); input.mx = (e.clientX - r.left) / SCALE; input.my = (e.clientY - r.top) / SCALE; });
  canvas.addEventListener('mousedown', e => { if (e.button === 0) input.lmb = true; if (e.button === 2) input.rmb = true; e.preventDefault(); });
  window.addEventListener('mouseup', e => { if (e.button === 0) input.lmb = false; if (e.button === 2) input.rmb = false; });
  canvas.addEventListener('contextmenu', e => e.preventDefault());
  canvas.addEventListener('wheel', e => {
    if (game.state !== 'play' || !player.known.length) return;
    player.sel = (player.sel + (e.deltaY > 0 ? 1 : -1) + player.known.length) % player.known.length;
    e.preventDefault();
  }, { passive: false });
}

function aimWorld() { return [wrapX(camX + input.mx), camY + input.my]; }

// ------------------------------------------------------------ save / load --
const SAVE_KEY = 'wispforge_save_v1';
function saveGame() {
  try {
    const p = player;
    localStorage.setItem(SAVE_KEY, JSON.stringify({
      planet: planet ? planet.index : 0, inv: Array.from(p.inv), known: p.known, tier: p.tier, digR: p.digR,
      maxHp: p.maxHp, maxMana: p.maxMana, manaRegen: p.manaRegen, heatWard: p.heatWard, items: p.items, mat: p.mat,
    }));
  } catch (e) { /* storage unavailable: progress just isn't kept */ }
}
function loadSave() {
  try { const s = localStorage.getItem(SAVE_KEY); return s ? JSON.parse(s) : null; } catch (e) { return null; }
}
function applySave(s) {
  const p = player;
  p.inv.set(s.inv.slice(0, NM)); p.known = s.known; p.tier = s.tier; p.digR = s.digR;
  p.maxHp = s.maxHp; p.maxMana = s.maxMana; p.manaRegen = s.manaRegen; p.heatWard = s.heatWard; p.items = s.items || {}; p.mat = s.mat || M.DIRT;
}

// ------------------------------------------------------------ world setup --
function enterPlanet(index) {
  generateWorld(index);
  enemies.length = 0; projs.length = 0; parts.length = 0;
  spawnEnemy('golem', bossSpawn.x, bossSpawn.y);
  respawnPlayer();
  camXf = player.x - VW / 2; camYf = player.y - VH / 2;
  wisp.x = player.x; wisp.y = player.y - 6;
  // let the freshly generated liquids settle around the spawn before play
  for (let k = 0; k < 90; k++) simulate(Math.floor(player.x) - 260, Math.floor(player.x) + 260, Math.floor(player.y) - 160, Math.floor(player.y) + 200);
  fixSky();
  toast(`${planet.name}: ${planet.desc}`, '#cfe', 6000);
}

function respawnPlayer() {
  const p = player;
  p.x = spawnX; p.y = spawnY; p.vx = p.vy = 0;
  // drop onto the ground
  while (p.y < H - 20 && !boxSolid(p.x, p.y + 1, p.w, p.h)) p.y++;
  while (boxSolid(p.x, p.y, p.w, p.h) && p.y > 2) p.y--;
  p.hp = p.maxHp; p.mana = p.maxMana; p.breath = p.maxBreath; p.dead = false; p.iframes = 90;
}

function onPlayerDeath() {
  player.dead = true;
  for (let k = 0; k < 40; k++) spawnParticle(player.x + 2, player.y + 6, (Math.random() - 0.5) * 2, -Math.random() * 2, 40, 140, 200, 255, true, 0.02);
  setTimeout(() => { game.state = 'dead'; $('death').classList.remove('hidden'); }, 1200);
}
function revive() {
  for (let m = 1; m < NM; m++) player.inv[m] = Math.floor(player.inv[m] * 0.75);
  $('death').classList.add('hidden');
  respawnPlayer();
  game.state = 'play';
  lastInvKey = '';
  saveGame();
}

function travelToNextPlanet() {
  toggleForge(false);
  game.state = 'loading';
  $('loadingText').textContent = 'The World Gate folds space…';
  $('loading').classList.remove('hidden');
  setTimeout(() => {
    player.inv[M.CORE] = 0;
    enterPlanet(planet.index + 1);
    $('loading').classList.add('hidden');
    game.state = 'play';
    saveGame();
  }, 80);
}

function toggleForge(force) {
  const open = force !== undefined ? force : game.state !== 'forge';
  if (open && game.state === 'play') { game.state = 'forge'; renderForge(); $('forge').classList.remove('hidden'); input.lmb = input.rmb = false; }
  else if (!open && game.state === 'forge') { game.state = 'play'; $('forge').classList.add('hidden'); }
}

// ------------------------------------------------------- time and weather --
function environment() {
  const dayT = game.dayT;
  const a = (dayT - 0.25) * Math.PI * 2, s = Math.sin(a);
  const sun = Math.min(1, Math.max(0.025, s * 1.6 + 0.15));
  const dusk = Math.max(0, 1 - Math.abs(s) * 4);
  const midY = camY + VH / 2;
  const space = Math.min(1, Math.max(0, 1 - (midY - 20) / 170));
  const wx = wrapX(Math.floor(player.x));
  const b = biomeAt(wx);
  const wname = { rain: 'Rain', snow: 'Snowfall', ash: 'Ashfall', clear: 'Clear' }[b.weather];
  return {
    time: game.time, dayT, sun, dusk, starA: Math.max(Math.min(1, 1 - sun * 2.2), space),
    sunCol: [1, 0.97 - dusk * 0.25, 0.9 - dusk * 0.45],
    sunSX: VW / 2 - Math.cos(a) * VW * 0.42, sunSY: VH * 0.9 - s * VH * 0.75, sunUp: s > -0.08,
    moonSX: VW / 2 + Math.cos(a) * VW * 0.42, moonSY: VH * 0.9 + s * VH * 0.75, moonUp: s < 0.08,
    cloudOff: Math.floor(game.time * 0.05), cloudCover: game.rain, rain: b.weather === 'clear' ? 0 : game.rain,
    flash: game.flash, hurt: player.hurtFlash * 0.6,
    weatherName: game.rain > 0.15 && b.weather !== 'clear' ? wname : (b.weather === 'clear' && game.rain > 0.15 ? 'Dry wind' : 'Clear'),
    weather: b.weather,
  };
}

function updateWeather(env) {
  if (--game.weatherTimer <= 0) {
    const raining = game.rainTarget > 0;
    game.rainTarget = raining ? 0 : (Math.random() < 0.55 ? 0.4 + Math.random() * 0.6 : 0);
    game.weatherTimer = 60 * (40 + Math.random() * 70);
  }
  game.rain += (game.rainTarget - game.rain) * 0.002;
  game.flash *= 0.85;
  const r = env.rain;
  if (r < 0.05) return;
  const mat = env.weather === 'snow' ? M.SNOW : (env.weather === 'ash' ? M.ASH : M.WATER);
  const n = r * VW / (mat === M.WATER ? 260 : 180);
  const count = Math.floor(n) + (Math.random() < n % 1 ? 1 : 0);
  for (let k = 0; k < count; k++) {
    const x = wrapX(camX - 40 + Math.floor(Math.random() * (VW + 80)));
    const y = Math.max(camY - 30, 150);
    if (y >= skyTop[x] - 2 || y < 2) continue;
    if (T[y * W + x] === 0) { T[y * W + x] = mat; }
  }
  // purely visual streaks for a fuller look
  if (mat === M.WATER) for (let k = 0; k < r * 6; k++) {
    const x = camX + Math.random() * VW, wx = wrapX(Math.floor(x)), y = camY + Math.random() * VH * 0.3;
    if (y < skyTop[wx] - 4) parts.push({ x, y, vx: -0.3, vy: 3.2, life: Math.max(1, (skyTop[wx] - y) / 3.2), r: 170, g: 195, b: 235, self: false, grav: 0, streak: true });
  }
  if (env.weather === 'rain' && r > 0.6 && Math.random() < 0.0012) {
    game.flash = 1.2; shake = 5;
    const x = wrapX(camX + Math.floor(Math.random() * VW)), y = skyTop[x];
    for (let dy = 0; dy < 3; dy++) for (let dx = -1; dx <= 1; dx++) { const t = getT(x + dx, y + dy); if (FUEL[t]) setCell(x + dx, y + dy, M.FIRE, FUEL[t]); }
  }
}

// ------------------------------------------------------------------- loop --
function update() {
  game.time++; game.frame++;
  game.dayT = (game.dayT + 1 / DAY_LEN) % 1;
  const env = environment();
  sim.daylight = env.sun;

  input.left = keys.KeyA || keys.ArrowLeft;
  input.right = keys.KeyD || keys.ArrowRight;
  input.jump = keys.Space || keys.KeyW || keys.ArrowUp;
  updatePlayer(input);
  input.jumpPressed = false;

  const [ax, ay] = aimWorld();
  if (!player.dead) {
    if (Math.abs(wdx(ax, player.x + player.w / 2)) > 1) player.facing = wdx(ax, player.x + player.w / 2) < 0 ? -1 : 1;
    if (input.lmb) castSpell(player.known[player.sel], ax, ay);
    if (input.rmb) excavate(ax, ay);
  }
  if (digBlocked > 0) digBlocked--;

  updateEnemies();
  updateProjectiles();
  updateParticles();
  updateWeather(env);
  trySpawnEnemies(env.sun < 0.3);

  // the simulated region follows the camera
  const M_ = 56;
  simulate(camX - M_, camX + VW + M_, camY - M_, camY + VH + M_);
  fixSky();

  // camera
  const lookX = (input.mx - VW / 2) * 0.12, lookY = (input.my - VH / 2) * 0.12;
  const tx = player.x + player.w / 2 - VW / 2 + lookX, ty = player.y + player.h / 2 - VH / 2 + lookY;
  camXf = ((camXf + wdx(tx, camXf) * 0.12) % W + W) % W;
  camYf += (ty - camYf) * 0.12;
  camYf = Math.max(0, Math.min(H - VH, camYf));

  if (++game.saveTimer > 3600) { game.saveTimer = 0; saveGame(); }
}

function render() {
  const env = environment(); lastEnv = env;
  const sh = shake > 0.3 ? shake : 0;
  camX = Math.floor(camXf + (Math.random() - 0.5) * sh);
  camY = Math.floor(camYf + (Math.random() - 0.5) * sh);
  shake *= 0.88;

  renderWorld(env);
  drawEnemies();
  for (const pr of projs) {
    const sx = scrX(pr.x), sy = Math.floor(pr.y) - camY, c = pr.d.col;
    const big = pr.type === 'fireball' || pr.type === 'quake' ? 1 : 0;
    for (let dy = -big; dy <= big; dy++) for (let dx = -big; dx <= big; dx++) putPx(sx + dx, sy + dy, c[0], c[1], c[2], true);
    putPx(sx, sy, 255, 255, 230, true);
  }
  const [ax, ay] = aimWorld();
  const sc = SPELLS[player.known[player.sel]].color;
  drawPlayerAndWisp(ax, ay, sc);
  drawParticles();
  buildLighting(env);
  composite(env);

  // reticle + reach indicator
  const mx = Math.floor(input.mx), my = Math.floor(input.my);
  for (let k = 2; k <= 4; k++) { overlayPx(mx + k, my, 255, 255, 255, 0.7); overlayPx(mx - k, my, 255, 255, 255, 0.7); overlayPx(mx, my + k, 255, 255, 255, 0.7); overlayPx(mx, my - k, 255, 255, 255, 0.7); }
  if (input.rmb || player.known[player.sel] === 'conjure') {
    const [rx, ry] = reachPoint(ax, ay);
    const sx = scrX(rx), sy = Math.floor(ry) - camY, r = input.rmb ? player.digR : 1.6;
    const col = input.rmb ? [140, 255, 170] : [255, 240, 160];
    for (let a = 0; a < 24; a++) { const t = a / 24 * Math.PI * 2; overlayPx(Math.round(sx + Math.cos(t) * (r + 0.5)), Math.round(sy + Math.sin(t) * (r + 0.5)), col[0], col[1], col[2], 0.55); }
  }
  presentFrame();
  if (game.frame % 6 === 0 || game.state !== 'play') updateHUD(env);
}

let acc = 0, lastT = 0;
function frame(t) {
  requestAnimationFrame(frame);
  if (!lastT) lastT = t;
  acc += Math.min(100, t - lastT); lastT = t;
  if (game.state === 'play' || game.state === 'dead') {
    let n = 0;
    while (acc >= 1000 / 60 && n < 3) { update(); acc -= 1000 / 60; n++; }
    if (n === 3) acc = 0;
  } else acc = 0;
  if (game.state !== 'title' && game.state !== 'loading' && planet) render();
}

// ------------------------------------------------------------------- boot --
function startGame(useSave) {
  $('title').classList.add('hidden');
  $('loadingText').textContent = 'Forging a planet…';
  $('loading').classList.remove('hidden');
  game.state = 'loading';
  setTimeout(() => {
    const s = useSave ? loadSave() : null;
    if (s) applySave(s);
    else { player.inv.fill(0); player.known = ['spark', 'conjure']; player.tier = 1; player.digR = 2.5; player.maxHp = 100; player.maxMana = 100; player.manaRegen = 0.22; player.heatWard = false; player.items = {}; }
    enterPlanet(s ? s.planet : 0);
    $('loading').classList.add('hidden');
    $('hud').classList.remove('hidden');
    game.state = 'play';
    if (!s) {
      toast('Right-click to excavate. Left-click casts your selected spell.', '#fff', 7000);
      toast('Press C to open the Wisp Forge and craft spells and upgrades.', '#ffd23a', 9000);
    }
    saveGame();
  }, 60);
}

window.addEventListener('load', () => {
  initRenderer();
  initInput();
  const s = loadSave();
  if (s) { $('continueBtn').style.display = 'inline-block'; $('continueBtn').textContent = `Continue (${makePlanet(s.planet).name})`; }
  $('newBtn').onclick = () => startGame(false);
  $('continueBtn').onclick = () => startGame(true);
  $('reviveBtn').onclick = revive;
  $('forgeClose').onclick = () => toggleForge(false);
  requestAnimationFrame(frame);
});
