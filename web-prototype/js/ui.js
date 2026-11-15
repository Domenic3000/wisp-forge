'use strict';
// HTML overlay: HUD bars, spell hotbar, satchel, toasts, forge panel, boss bar.
const $ = id => document.getElementById(id);

function toast(text, color, ms) {
  const el = document.createElement('div');
  el.className = 'toast'; el.textContent = text;
  if (color) el.style.color = color;
  $('toasts').prepend(el);
  setTimeout(() => el.classList.add('fade'), (ms || 2200));
  setTimeout(() => el.remove(), (ms || 2200) + 600);
  const all = $('toasts').children; if (all.length > 7) all[all.length - 1].remove();
}

function rgbCss(c) { return `rgb(${c[0]},${c[1]},${c[2]})`; }

let lastHotbarKey = '', lastInvKey = '';
function updateHUD(env) {
  const p = player;
  $('hpFill').style.width = (100 * p.hp / p.maxHp) + '%';
  $('hpText').textContent = `${Math.ceil(p.hp)} / ${p.maxHp}`;
  $('mpFill').style.width = (100 * p.mana / p.maxMana) + '%';
  $('mpText').textContent = `${Math.floor(p.mana)} / ${p.maxMana}`;
  const br = $('breathBar');
  if (p.breath < p.maxBreath) { br.style.display = 'block'; $('brFill').style.width = (100 * p.breath / p.maxBreath) + '%'; } else br.style.display = 'none';

  const wx = wrapX(Math.floor(p.x));
  const depth = Math.round(p.y - surf0[wx]);
  const depthTxt = depth < 0 ? `Altitude ${-depth}m` : `Depth ${depth}m`;
  const hour = Math.floor(env.dayT * 24), min = Math.floor((env.dayT * 24 - hour) * 60);
  const tierNames = ['', 'I · Stone', 'II · Copper', 'III · Obsidian', 'IV · Core Siphon'];
  $('info').innerHTML =
    `<b>${planet.name}</b> · ${regionName(p.x, p.y)}<br>` +
    `${depthTxt} · ${String(hour).padStart(2, '0')}:${String(min).padStart(2, '0')} · ${depth > 14 ? 'Underground' : env.weatherName}<br>` +
    `Staff ${tierNames[p.tier]}${p.heatWard ? ' · Heat Ward' : ''}${p.items.heart ? ' · Ember Heart' : ''}`;

  const hk = p.known.join(',') + '|' + p.sel;
  if (hk !== lastHotbarKey) {
    lastHotbarKey = hk;
    $('hotbar').innerHTML = p.known.map((id, k) => {
      const s = SPELLS[id];
      return `<div class="slot ${k === p.sel ? 'sel' : ''}" data-k="${k}"><span class="key">${k + 1}</span><span class="gem" style="background:${rgbCss(s.color)}"></span><span class="nm">${s.name}</span><span class="mc">${s.mana ? s.mana + ' mp' : 'free'}</span></div>`;
    }).join('');
    for (const el of $('hotbar').children) el.onclick = () => { p.sel = +el.dataset.k; };
  }

  let ik = p.mat + '|';
  for (let m = 1; m < NM; m++) if (p.inv[m] > 0) ik += m + ':' + p.inv[m] + ',';
  if (ik !== lastInvKey) {
    lastInvKey = ik;
    let html = '';
    for (let m = 1; m < NM; m++) {
      if (!(p.inv[m] > 0)) continue;
      const mi = MINFO[m];
      html += `<div class="mat ${m === p.mat ? 'sel' : ''}" data-m="${m}" title="${mi.name}${HARD[m] ? ' (tier ' + HARD[m] + ')' : ''}"><span class="sw" style="background:${mi.color}"></span><span class="mn">${mi.name}</span><span class="mq">${p.inv[m]}</span></div>`;
    }
    $('satchel').innerHTML = html || '<div class="empty">Right-click to excavate materials</div>';
    for (const el of $('satchel').children) if (el.dataset.m) el.onclick = () => { p.mat = +el.dataset.m; const ci = p.known.indexOf('conjure'); if (ci >= 0) p.sel = ci; };
  }

  const boss = enemies.find(e => e.d.boss && e.awake && !e.dead && Math.abs(wdx(e.x, p.x)) < 260 && Math.abs(e.y - p.y) < 200);
  if (boss) { $('bossbar').style.display = 'block'; $('bossName').textContent = boss.d.name; $('bossFill').style.width = (100 * boss.hp / boss.maxHp) + '%'; }
  else $('bossbar').style.display = 'none';

  $('digwarn').style.display = digBlocked > 0 ? 'block' : 'none';
}

function renderForge() {
  const cats = {};
  for (const r of RECIPES) (cats[r.cat] = cats[r.cat] || []).push(r);
  let html = '';
  for (const c in cats) {
    html += `<h3>${c}</h3><div class="recipes">`;
    for (const r of cats[c]) {
      const done = recipeDone(r), unlocked = recipeUnlocked(r), aff = recipeAffordable(r);
      const cost = Object.keys(r.cost).map(k => {
        const have = player.inv[k], need = r.cost[k];
        return `<span class="cost ${have >= need ? 'ok' : 'no'}"><span class="sw" style="background:${MINFO[k].color}"></span>${MINFO[k].name} ${have}/${need}</span>`;
      }).join('');
      const state = done ? 'done' : (!unlocked ? 'locked' : (aff ? 'ready' : 'short'));
      const btn = done ? '<span class="tag">Forged</span>' : (!unlocked ? `<span class="tag">${r.reqText || 'Locked'}</span>` : `<button data-id="${r.id}" ${aff ? '' : 'disabled'}>Forge</button>`);
      html += `<div class="recipe ${state}"><div class="rn">${r.name}</div><div class="rd">${r.desc}</div><div class="rc">${cost}</div>${btn}</div>`;
    }
    html += '</div>';
  }
  $('forgeList').innerHTML = html;
  for (const b of $('forgeList').querySelectorAll('button[data-id]')) {
    b.onclick = () => { const r = RECIPES.find(x => x.id === b.dataset.id); if (craft(r)) { renderForge(); lastInvKey = ''; lastHotbarKey = ''; } };
  }
}
