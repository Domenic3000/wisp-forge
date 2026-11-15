'use strict';
// Hand-made pixel sprites. '.' = transparent. Palette entries: [r,g,b,selfLit]

function pal(o) { const r = {}; for (const k in o) { const c = hexRGB(o[k][0]); r[k] = [c[0], c[1], c[2], o[k][1] ? 1 : 0]; } return r; }

const SPR = {
  mage: {
    rows: [
      '....h..',
      '...hh..',
      '..hhh..',
      '.hhhhh.',
      'HHHHHHH',
      '.sssess',
      '.rrrrr.',
      'rrtrrrr',
      'rrbbbrr',
      '.rrrrr.',
      '.rRrRr.',
      '.kk.kk.',
    ],
    pal: pal({ h: ['#5b3fa8'], H: ['#f2c94c'], s: ['#f1c7a0'], e: ['#1a1a2e'], r: ['#2f4fa8'], R: ['#24408a'], t: ['#8ab4ff'], b: ['#c9a43a'], k: ['#3a2a20'] }),
  },
  slime: {
    rows: [
      '..gggg..',
      '.gGGGGg.',
      'gGwgGwgg',
      'ggkggkgg',
      'gggggggg',
      '.gggggg.',
    ],
    pal: pal({ g: ['#5fd16a'], G: ['#9af5a0'], w: ['#ffffff'], k: ['#1d3a20'] }),
  },
  bat1: {
    rows: ['b.....b', 'bb.e.bb', '.bbbbb.', '...b...'],
    pal: pal({ b: ['#4a3a5c'], e: ['#ff4a4a', 1] }),
  },
  bat2: {
    rows: ['...e...', '.bbbbb.', 'bb...bb', 'b.....b'],
    pal: pal({ b: ['#4a3a5c'], e: ['#ff4a4a', 1] }),
  },
  imp: {
    rows: ['r....r', 'rrrrrr', 'ryrryr', '.rrrr.', 'rrffrr', '.rrrr.', '.r..r.', 'rr..rr'],
    pal: pal({ r: ['#c23a2a'], y: ['#ffe14a', 1], f: ['#ff9a3a', 1] }),
  },
  golem: {
    rows: [
      '....oooooo....',
      '...oOooooOo...',
      '...oyyooyyo...',
      '...oooccooo...',
      '....oOooOo....',
      '.oooooooooooo.',
      'ooOoooccoooOoo',
      'ooocoocccooooo',
      'oOooocccccooOo',
      'ooo.ooccccoooo',
      'oo..oooccoo.oo',
      'oo..ooooooo.oo',
      'cc..oOoooOo.cc',
      '....ooo..ooo..',
      '....ooo..ooo..',
      '....oOo..oOo..',
      '...oooo..oooo.',
      '...cccc..cccc.',
    ],
    pal: pal({ o: ['#5a4640'], O: ['#3a2c28'], c: ['#ff7a2a', 1], y: ['#ffd23a', 1] }),
  },
};
