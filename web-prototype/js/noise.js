'use strict';
// Seeded hashing / value noise. Terrain noise is sampled on a cylinder so the
// planet wraps seamlessly east-west.

function hash3i(x, y, z, s) {
  let h = Math.imul(x | 0, 0x27d4eb2d) ^ Math.imul(y | 0, 0x165667b1) ^ Math.imul(z | 0, 0x2c1b3c6d) ^ Math.imul(s | 0, 0x9e3779b1);
  h = Math.imul(h ^ (h >>> 15), 0x85ebca6b);
  h = Math.imul(h ^ (h >>> 13), 0xc2b2ae35);
  h ^= h >>> 16;
  return (h >>> 0) * 2.3283064365386963e-10;
}

function noise3(x, y, z, s) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
  const xf = x - xi, yf = y - yi, zf = z - zi;
  const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf), w = zf * zf * (3 - 2 * zf);
  const a = hash3i(xi, yi, zi, s), b = hash3i(xi + 1, yi, zi, s);
  const c = hash3i(xi, yi + 1, zi, s), d = hash3i(xi + 1, yi + 1, zi, s);
  const e = hash3i(xi, yi, zi + 1, s), f = hash3i(xi + 1, yi, zi + 1, s);
  const g = hash3i(xi, yi + 1, zi + 1, s), h = hash3i(xi + 1, yi + 1, zi + 1, s);
  const x1 = a + (b - a) * u, x2 = c + (d - c) * u, x3 = e + (f - e) * u, x4 = g + (h - g) * u;
  const y1 = x1 + (x2 - x1) * v, y2 = x3 + (x4 - x3) * v;
  return y1 + (y2 - y1) * w;
}

function fbm3(x, y, z, s, oct) {
  let sum = 0, amp = 1, norm = 0, f = 1;
  for (let o = 0; o < oct; o++) {
    sum += noise3(x * f, y * f, z * f, s + o * 101) * amp;
    norm += amp; amp *= 0.5; f *= 2.03;
  }
  return sum / norm;
}

function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

function hash2(x, y) { return hash3i(x, y, 7, 99); }
