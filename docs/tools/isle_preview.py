import json, math, sys
from PIL import Image, ImageFilter
P = json.load(open('/home/claude/isleprev/pal.json'))
ID = P['ids']
def col(m, v):
    name = [k for k, x in ID.items() if x == m][0]
    h = P['pal'][name][v & 3]
    return [int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255]
G = lambda n: ID[n]
STONE, DIRT, GRASS, WOOD, LEAF, GRAVEL, CRYSTAL, MASONRY, RUNESTONE, WISP, WISPBAR, ROOT, DEEPSTONE, MOSSBLOCK, SUNSTONE, FROST, CAP, TORCH, PLANK, SHROOM = [G(n) for n in "STONE DIRT GRASS WOOD LEAF GRAVEL CRYSTAL MASONRY RUNESTONE WISP WISPBAR ROOT DEEPSTONE MOSSBLOCK SUNSTONE FROST CAP TORCH PLANK SHROOM".split()]

W, H, SURF = 640, 380, 236
LEVELS = [70, 100, 132, 168, 208, 252, 296]
ARCH_DX, ARCH_W, ARCH_H, HEART_DX = -44, 16, 30, 0
TER_A, TER_B = 12, 54      # the home terrace, from the heart (cells)

def fract(x): return x - math.floor(x)
def _h(n): return fract(math.sin(n * 12.9898) * 43758.5453)

class Isle:
    def __init__(s, level=0):
        s.level = level
        n = W * H
        s.cells = [0] * n; s.vars = [0] * n; s.bg = [0] * n; s.bgv = [0] * n
        s.natural = [0] * n; s.guard = [0] * n; s.made = [0] * n
        s.grow(level)
        s.features()

    def top_at(s, i, lv):
        hw = LEVELS[lv]
        ax = abs(i - W // 2) / hw
        t = SURF + 2.6 * math.sin(i * 0.061 + 1.3) + 1.4 * math.sin(i * 0.173)
        t += (max(0.0, ax - 0.74) / 0.3) ** 2 * 16.0
        return t

    def depth_at(s, i, lv):
        hw = LEVELS[lv]
        ax = abs(i - W // 2) / hw
        if ax >= 1.0: return 0.0
        d = (30.0 + hw * 0.36) * (1.0 - ax * ax) ** 0.62
        d += 5.0 * math.sin(i * 0.11) + 3.0 * math.sin(i * 0.37 + 2.0)
        return max(d, 3.0)

    # stalactites under the isle: (extra length, crystal tip?) at column i
    def drip_at(s, i, lv):
        hw = LEVELS[lv]
        ax = abs(i - W // 2) / hw
        if ax >= 0.92: return 0.0, False
        best, tip = 0.0, False
        c0 = (i // 7) * 7
        for c in (c0 - 7, c0, c0 + 7):
            if _h(c * 0.913 + 5.1) < 0.35: continue
            cc = c + int(_h(c * 1.37) * 5.0)
            wd = 2.5 + _h(c * 2.11) * 3.0
            ln = (5.0 + _h(c * 3.7) * 18.0) * (1.0 - ax) ** 0.6
            d = abs(i - cc)
            if d >= wd: continue
            e = ln * (1.0 - d / wd) ** 1.3
            if e > best:
                best, tip = e, _h(c * 4.3) > 0.62
        return best, tip

    def ground_at(s, i, j, lv):
        dep = s.depth_at(i, lv)
        if dep <= 0.0: return 0
        top = s.top_at(i, lv)
        fj = float(j)
        bottom = top + dep
        drip, tip = s.drip_at(i, lv)
        if fj < math.floor(top) or fj > bottom + drip: return 0
        if fj > bottom:
            if tip and fj > bottom + drip - 3.0: return CRYSTAL
            return DEEPSTONE if _h(i * 0.7 + j * 0.3) > 0.4 else STONE
        d = fj - math.floor(top)
        if d < 2.0: return GRASS
        soil = 7.0 + 2.5 * math.sin(i * 0.29) + 1.5 * math.sin(i * 0.07)
        if d < soil:
            # roots threading the soil
            if _h(math.floor(i / 3.0) * 1.9) > 0.72 and abs(fract(i / 3.0) * 3.0 - 1.0 - math.sin(j * 0.6) * 0.8) < 0.6:
                return ROOT
            return DIRT
        if d < soil + 1.5 + _h(i * 1.3):
            return GRAVEL
        # crystal geodes: a few, in the rock
        gx, gy = math.floor(i / 22.0), math.floor(j / 16.0)
        if _h(gx * 7.7 + gy * 3.3) > 0.72:
            cxg = gx * 22.0 + 5.0 + _h(gx * 1.1 + gy) * 12.0
            cyg = gy * 16.0 + 4.0 + _h(gx + gy * 2.3) * 8.0
            r = 1.6 + _h(gx * 5.0 + gy * 9.0) * 1.6
            dd = math.hypot((i - cxg), (j - cyg) * 1.2)
            if dd < r and fj > top + soil + 3.0 and fj < bottom - 2.0:
                return CRYSTAL
            if dd < r + 1.2 and fj > top + soil + 2.0 and fj < bottom - 1.0:
                return DEEPSTONE
        # strata: wavy bands of stone and deepstone, deeper ever darker
        sj = fj + 3.0 * math.sin(i * 0.045 + 0.7) + 1.5 * math.sin(i * 0.13)
        band = math.floor(sj / 6.0)
        fr = (fj - top) / max(dep, 1.0)
        if _h(band * 3.17) < 0.25 + fr * 0.55:
            return DEEPSTONE
        if fj > bottom - 2.0:
            return GRAVEL
        return STONE

    def grow(s, lv):
        hw = LEVELS[lv]
        for i in range(max(0, W // 2 - hw - 2), min(W, W // 2 + hw + 3)):
            for j in range(max(0, SURF - 30), H):
                k = j * W + i
                if s.guard[k] == 1 or s.natural[k] == 2 or (s.cells[k] != 0 and s.natural[k] == 0): continue
                m = s.ground_at(i, j, lv)
                if m == 0 or m == s.cells[k]: continue
                s.cells[k] = m
                s.vars[k] = int(_h(k * 0.37) * 4.0) & 3
                s.natural[k] = 1
                s.made[k] = 0

    # ---------------------------------------------------------- helpers
    def put(s, i, j, m, v, guard=False):
        if 0 <= i < W and 0 <= j < H:
            k = j * W + i
            s.cells[k] = m; s.vars[k] = v & 3; s.natural[k] = 0; s.made[k] = 0
            if guard: s.guard[k] = 1
    def gbg(s, i, j, m, v):
        if 0 <= i < W and 0 <= j < H:
            k = j * W + i
            s.bg[k] = m; s.bgv[k] = v & 3; s.guard[k] = 1
    def bgp(s, i, j, m, v=-1, over=True):
        if 0 <= i < W and 0 <= j < H:
            k = j * W + i
            if s.guard[k] == 1: return
            if not over and s.bg[k] != 0: return
            s.bg[k] = m; s.bgv[k] = (int(_h(k * 0.71) * 4.0) & 3) if v < 0 else v
    def ground_row(s, i, frm):
        if i < 0 or i >= W: return frm
        for j in range(max(0, frm - 6), min(H, frm + 30)):
            if s.cells[j * W + i] != 0: return j
        return frm

    # ---------------------------------------------------------- features
    def features(s):
        cx = W // 2
        s.path(cx)
        s.terrace(cx)
        s.heart(cx + HEART_DX)
        s.arch(cx + ARCH_DX)
        s.tree(cx + 63, 24, 12, 1)
        s.tree(cx - 63, 17, 9, 2)
        for bx in [cx - 56, cx + 8 + TER_B]:
            s.bush(bx)
        s.dress(0)

    # (a cobbled path from the arch to the heart: the grass's top worn to stones)
    def path(s, cx):
        a, b = cx + ARCH_DX + ARCH_W // 2 + 5, cx + HEART_DX - 9
        for i in range(a - 3, b + 3):
            t = s.ground_row(i, math.floor(s.top_at(i, 0)))
            fade = 1.0 if a <= i < b else 0.45
            for dj in range(2):
                k = (t + dj) * W + i
                if s.natural[k] != 1: continue
                # flagstones 3-5 cells long, dark joints between, a few worn away to grass at the ends
                st = int(_h(math.floor((i + dj * 2) / 4.0) * 3.1 + dj) * 3.0)
                joint = (i + dj * 2) % 4 == 0
                if _h(i * 1.7 + dj * 5.0) > fade:
                    continue
                if joint:
                    s.put(i, t + dj, GRAVEL, 3)
                else:
                    s.put(i, t + dj, MASONRY, [2, 0, 1][st] if dj == 0 else 1)
            if a <= i < b and _h(i * 3.3) > 0.7:
                s.put(i, t + 2, GRAVEL, 0)

    # the home terrace: level paving to build a home on, a lamp at each end
    def terrace(s, cx):
        a, b = cx + TER_A, cx + TER_B
        fl = min(s.ground_row(i, math.floor(s.top_at(i, 0))) for i in range(a, b))
        fl = max(fl, round(sum(s.ground_row(i, math.floor(s.top_at(i, 0))) for i in range(a, b)) / (b - a)))
        for i in range(a - 1, b + 1):
            g0 = s.ground_row(i, math.floor(s.top_at(i, 0)))
            for j in range(fl - 12, fl):           # (ground over the floor: cut away)
                k = j * W + i
                if s.natural[k] == 1:
                    s.cells[k] = 0; s.natural[k] = 2
            for j2 in range(fl, max(g0, fl) + 4):  # (under it: filled to the ground)
                k2 = j2 * W + i
                if s.cells[k2] == 0 or s.natural[k2] == 1:
                    edge = i == a - 1 or i == b
                    if j2 < fl + 2:
                        s.put(i, j2, MASONRY, 3 if (edge or (i - a) % 6 == 5 or j2 == fl + 1) else (2 if j2 == fl else (i // 6) % 2))
                    elif s.cells[k2] == 0:
                        s.put(i, j2, DIRT if j2 < fl + 5 else STONE, (i + j2) & 3)
        # lamps: a timber post, a wisp-glass lantern (back layer)
        for lx in (a + 1, b - 2):
            for dj in range(1, 9):
                s.bgp(lx, fl - dj, WOOD, 1)
            for di in (-1, 0, 1):
                for dj2 in (9, 10, 11):
                    s.bgp(lx + di, fl - dj2, WISPBAR if di == 0 and dj2 == 10 else WOOD, 3 if di == 0 else 0)
            s.bgp(lx, fl - 12, WOOD, 1)

    # the Isle Heart: a tiered plinth (you walk up it), a faceted crystal obelisk with a wisp seam, a shard above
    def heart(s, hx):
        ht = math.floor(s.top_at(hx, 0))
        ht = s.ground_row(hx, ht)
        for tier, (hw, rows) in enumerate([(8, 2), (5, 2)]):
            base = ht - 1 - tier * 2
            for dj in range(rows):
                for di in range(-hw, hw + 1):
                    j = base - dj
                    trim = dj == rows - 1
                    m = RUNESTONE if trim else MASONRY
                    v = (2 if di < 0 else 0) if not trim else (2 if abs(di) % 3 == 0 else 1)
                    if not trim and abs(di) == hw: v = 3
                    s.put(hx + di, j, m, v, True)
            # (down to the ground under each tier's edge)
            for di in range(-hw, hw + 1):
                j3 = base + 1
                while j3 < H and j3 < base + 20 and s.cells[j3 * W + hx + di] == 0:
                    s.put(hx + di, j3, MASONRY, 3, True); j3 += 1
        for di in (-6, 6):
            s.put(hx + di, ht - 2, WISPBAR, 2, True)       # (rune lights in the lower tier)
        top = ht - 5
        hgt = 24
        for dj in range(hgt):
            f = dj / hgt
            half = 3.8 * (1.0 - f) ** 0.8 + (0.7 if dj < 2 else 0.0)
            hi = int(round(half))
            for di in range(-hi, hi + 1):
                if dj == hgt - 1 and di != 0: continue
                if di == 0 and dj < hgt - 4: m, v = WISP, (3 if dj % 5 == 2 else 0)
                elif di < 0: m, v = CRYSTAL, (3 if di == -hi else 1)
                else: m, v = CRYSTAL, (2 if di == hi else 0)
                s.gbg(hx + di, top - dj, m, v)
        # the floating shard over its tip
        for dj in range(7):
            w2 = 2 - abs(dj - 3) * 2 // 3
            for di in range(-w2, w2 + 1):
                s.gbg(hx + di, top - hgt - 3 - dj, CRYSTAL, 3 if di <= 0 else 2)
        # crystal clusters at its foot
        for sx, sgn in ((hx - 4, -1), (hx + 4, 1)):
            for q, ln in ((0, 4), (1, 6), (2, 3)):
                for dj in range(ln):
                    s.gbg(sx + sgn * q, top - dj, CRYSTAL, 3 if sgn < 0 else 2)

    # the arch: a stepped base, pillars of dressed stone with rune lights, a ring of voussoirs, a wisp keystone
    def arch(s, ax):
        at = s.ground_row(ax, math.floor(s.top_at(ax, 0)))
        r_in = ARCH_W * 0.5
        r_out = r_in + 4.0
        spring = ARCH_H - ARCH_W // 2          # (rows up from the ground where the round top begins)
        for dj in range(ARCH_H + 7):
            for di in range(-ARCH_W // 2 - 6, ARCH_W // 2 + 7):
                y = at - 1 - dj
                oy = dj - spring
                inside = abs(di) < r_in and (oy < 0 or math.hypot(di, oy) < r_in)
                outer = abs(di) < r_out and (oy < 0 or math.hypot(di, oy) < r_out)
                if inside:
                    s.guard[y * W + ax + di] = 1
                    continue
                if dj < 2 and abs(di) < r_out + 2:      # the base, wider
                    s.gbg(ax + di, y, MASONRY, 3 if dj == 1 else 1)
                    continue
                if not outer: continue
                if oy < 0:
                    # pillars: courses of blocks, joints dark, a light edge, rune lights up the middle
                    face = abs(di) - r_in        # 0 .. 4 across the pillar
                    course = (dj - 2) // 5
                    if oy >= -2:
                        s.gbg(ax + di, y, RUNESTONE, 2)         # the capital
                    elif face >= 3.0:
                        s.gbg(ax + di, y, RUNESTONE, 1)         # its outer edge
                    elif (dj - 2) % 5 == 4:
                        s.gbg(ax + di, y, RUNESTONE, 0)         # a joint between courses
                    elif face < 1.0:
                        s.gbg(ax + di, y, MASONRY, 2)           # the lit inner edge
                    else:
                        s.gbg(ax + di, y, MASONRY, 0 if course % 2 else 1)
                    if int(face) == 2 and (dj - 2) % 10 == 7 and oy < -4:
                        s.gbg(ax + di, y, WISP, 3)
                else:
                    ang = math.atan2(oy, di)
                    rr = math.hypot(di, oy)
                    seg = int(math.floor((ang / math.pi) * 9.0))
                    jn = abs(fract((ang / math.pi) * 9.0) - 0.5) > 0.42
                    if rr >= r_out - 1.0:
                        s.gbg(ax + di, y, RUNESTONE, 1)
                    elif jn:
                        s.gbg(ax + di, y, RUNESTONE, 2)
                    else:
                        s.gbg(ax + di, y, MASONRY, 2 if seg % 2 else 0)
        # the keystone
        ky = at - 1 - spring - int(r_in)
        for dj in range(-1, 4):
            for di in range(-1, 2):
                s.gbg(ax + di, ky - dj, WISPBAR if abs(di) + abs(dj - 1) < 2 else RUNESTONE, 3 if (di, dj) == (0, 1) else 0)
        # its feet down to the ground where the isle dips
        for di in range(-ARCH_W // 2 - 6, ARCH_W // 2 + 7):
            if abs(di) >= r_in:
                gj = s.ground_row(ax + di, at)
                for y2 in range(at, gj):
                    s.gbg(ax + di, y2, MASONRY, 3)

    # a tree: a flared, tapering trunk, two boughs, a crown of lit blobs
    def tree(s, tx, trunk, crown, seed):
        tt = s.ground_row(tx, math.floor(s.top_at(tx, s.level)))
        for dj in range(trunk):
            hw = 2 if dj < trunk * 0.45 else 1
            for di in range(-hw, hw + (1 if dj < 3 else 0)):
                v = 3 if di == -hw else (1 if di >= hw - 1 else 0)
                s.bgp(tx + di, tt - 1 - dj, WOOD, v)
        for di2 in (-4, -3, 3, 4):              # root flare
            s.bgp(tx + di2, tt - 1, ROOT, 1)
        s.bgp(tx - 3, tt - 2, ROOT, 0); s.bgp(tx + 3, tt - 2, ROOT, 0)
        cy = tt - trunk
        for sg in (-1, 1):                      # boughs
            for q in range(int(crown * 0.7)):
                s.bgp(tx + sg * (q + 1), cy + 4 - q // 2, WOOD, 0)
        blobs = [(0, -2, 1.0), (-crown * 0.62, 2, 0.72), (crown * 0.62, 2, 0.75), (-crown * 0.3, -crown * 0.5, 0.7), (crown * 0.35, -crown * 0.45, 0.68)]
        for bi, (bx, by, br) in enumerate(blobs):
            rx = (crown + 4) * br
            ry = crown * br * 0.85
            for dj2 in range(-int(ry) - 1, int(ry) + 2):
                for di2 in range(-int(rx) - 1, int(rx) + 2):
                    e = (di2 / rx) ** 2 + (dj2 / ry) ** 2
                    jit = _h((tx + bx + di2) * 31.0 + (cy + by + dj2) * 7.0 + seed) * 0.16
                    if e >= 1.0 - jit: continue
                    lit = -di2 / rx * 0.6 - dj2 / ry * 0.9      # light from the upper left
                    v = 3 if lit > 0.45 else (1 if lit > -0.1 else (0 if lit > -0.6 else 2))
                    if e > 0.8 and lit < 0.2: v = 2
                    s.bgp(int(tx + bx + di2), int(cy + by + dj2), LEAF, v)

    def bush(s, bx):
        bt = s.ground_row(bx, math.floor(s.top_at(bx, s.level)))
        for dj in range(6):
            for di in range(-6, 7):
                e = (di / 6.5) ** 2 + (dj / 5.0) ** 2
                if e < 1.0 - _h(di * 13.0 + dj * 5.0 + bx) * 0.15:
                    lit = -di / 6.5 * 0.5 + dj / 5.0 * 0.9
                    v = 3 if lit > 0.5 else (1 if lit > 0.0 else 0)
                    s.bgp(bx + di, bt - 1 - dj, LEAF, v)
        if _h(bx * 1.3) > 0.4:
            for q in range(3):
                s.bgp(bx - 3 + q * 3, bt - 3 - (q % 2) * 2, CAP if _h(bx + q) > 0.5 else CRYSTAL, 1)

    # grass tufts, flowers and stones on the top; vines down the rim; roots hanging under it (back layer, only
    # where nothing is)
    def dress(s, lv):
        hw = LEVELS[lv]
        cx = W // 2
        flowers = [CRYSTAL, SUNSTONE, FROST, CAP]
        for i in range(cx - hw, cx + hw + 1):
            t = s.ground_row(i, math.floor(s.top_at(i, lv)))
            k = t * W + i
            if s.cells[k] != GRASS: continue
            h1 = _h(i * 2.31 + 0.7)
            if h1 > 0.55:
                ln = 1 + int(_h(i * 5.1) * 2.5)
                for dj in range(ln):
                    s.bgp(i, t - 1 - dj, GRASS, 3 if dj == ln - 1 else 1, False)
            if h1 > 0.93:
                fm = flowers[int(_h(i * 8.3) * 4) % 4]
                s.bgp(i, t - 1, LEAF, 1, False); s.bgp(i, t - 2, LEAF, 3, False)
                s.bgp(i, t - 3, fm, 1, False)
                s.bgp(i - 1, t - 3, fm, 0, False); s.bgp(i + 1, t - 3, fm, 2, False); s.bgp(i, t - 4, fm, 3, False)
            if 0.18 < h1 < 0.2:
                for di in range(-2, 3):
                    for dj in range(2 if abs(di) < 2 else 1):
                        s.bgp(i + di, t - 1 - dj, MOSSBLOCK if dj == 1 or di < 0 else STONE, 2 if dj == 1 else 0, False)
        # vines down the rim, roots under the soil's edge
        for i in range(cx - hw, cx + hw + 1):
            ax = abs(i - cx) / hw
            t = s.ground_row(i, math.floor(s.top_at(i, lv)))
            dep = s.depth_at(i, lv)
            if ax > 0.72 and _h(i * 3.9 + 1.0) > 0.45:
                ln = int(6 + _h(i * 4.7) * 18 * ax)
                x = i
                for dj in range(ln):
                    y = t + 2 + dj
                    if _h(i * 9.1 + dj) > 0.8: x += 1 if i > cx else -1
                    k = y * W + x
                    if 0 <= x < W and y < H and s.cells[k] == 0:
                        leaf = dj % 3 != 1 or _h(x + dj * 3.3) > 0.5
                        s.bgp(x, y, LEAF if leaf else WOOD, 3 if dj % 4 == 0 else 1, False)
                        if dj == ln - 1 and _h(i * 1.1) > 0.6:
                            s.bgp(x, y + 1, CRYSTAL, 3, False)
            # roots hanging from under the isle
            if ax < 0.9 and _h(i * 6.3 + 2.0) > 0.86:
                b = int(t + dep) + 1
                drip, _ = s.drip_at(i, lv)
                ln = int(4 + _h(i * 2.9) * 14)
                x = i
                for dj in range(ln):
                    y = b + dj
                    while y < H and s.cells[y * W + x] != 0 and dj == 0:
                        y += 1; b += 1
                    if _h(i * 7.7 + dj) > 0.75: x += 1 if _h(i + dj) > 0.5 else -1
                    if 0 <= x < W and y < H and s.cells[y * W + x] == 0:
                        s.bgp(x, y, ROOT, 1 if dj % 3 else 0, False)

def render(s, scale=3, x0=None, x1=None, y0=None, y1=None):
    hw = LEVELS[s.level] + 44
    x0 = x0 if x0 is not None else W // 2 - hw
    x1 = x1 if x1 is not None else W // 2 + hw
    y0 = y0 if y0 is not None else SURF - 70
    y1 = y1 if y1 is not None else min(H, SURF + 150)
    img = Image.new('RGB', (x1 - x0, y1 - y0), (24, 14, 44))
    px = img.load()
    for j in range(y0, y1):
        for i in range(x0, x1):
            k = j * W + i
            c = None
            m = s.cells[k]
            if m:
                c = col(m, s.vars[k])
                if s.natural[k] == 1 and m != CRYSTAL:
                    d = j - s.top_at(i, s.level)
                    f = 1 - min(max(d / 70.0, 0), 0.5)
                    c = [x * f for x in c]
            elif s.bg[k]:
                bm = s.bg[k]
                c = col(bm, s.bgv[k])
                if s.guard[k] == 1: f = 0.95
                elif bm in (LEAF, WOOD, GRASS, ROOT, CRYSTAL, SUNSTONE, FROST, CAP, WISPBAR): f = 0.84
                else: f = 0.68
                c = [x * f for x in c]
            if c:
                px[i - x0, j - y0] = tuple(int(x * 255) for x in c)
    return img.resize(((x1 - x0) * scale, (y1 - y0) * scale), Image.NEAREST)

if __name__ == '__main__':
    lv = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    s = Isle(0)
    for l in range(1, lv + 1):
        s.level = l; s.grow(l)
    render(s).save('/home/claude/isleprev/isle%d.png' % lv)
