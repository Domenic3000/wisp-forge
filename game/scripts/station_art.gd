## The insides of stations and outposts (user, 27 Nov: "last time i went there is was a bunch of basic square
## rooms. it would be nice if they were different types of rooms with different shapes and decorations. make it
## feel alive like its being lived in"): a paint palette of their own and the parts rooms are dressed from.
##
## PAINT: a station's back layer (`bg`) holds world materials (< 128) or these paint codes (128 up), each with four
## shades (`bgv`), painted by station.gd's colour table; GLOW codes give off light (an outpost's halos), WINDOW is
## see-through (the station's own interior behind, station_back.gd). Every part paints into a canvas (`Cv`: the
## body's `bg` / `bgv`, shared, not copied) and has a derelict version (`dead`): dark screens, dead lamps, things
## knocked over, grime and rust. `furnish` dresses a room by its role, `wall` paints its back wall in a style.
extends RefCounted

# ---- paint codes ----
const PLATE := 128        # wall panels, light
const PLATE_D := 129      # wall panels, dark
const SEAM := 130
const RIVET := 131
const TRIM_G := 132       # gold trim (an outpost's)
const TRIM_T := 133       # teal trim
const WOOD := 134
const WOOD_D := 135
const TILE := 136         # pale tiles (medbay, mess, hydro)
const GROUT := 137
const HEX := 138
const GRATE := 139
const CARPET_R := 140
const CARPET_B := 141
const RUST := 142
const GRIME := 143
const SCORCH := 144
const GOO := 145
const METAL := 146
const METAL_D := 147
const PIPE := 148
const PIPE_CU := 149
const CABLE := 150
const CABLE_R := 151
const CABLE_Y := 152
const FAB_B := 153        # blankets, cushions
const FAB_R := 154
const FAB_G := 155
const PILLOW := 156
const SCREEN_B := 157     # (glowing)
const SCREEN_G := 158     # (glowing)
const SCREEN_A := 159     # (glowing)
const SCREEN_DEAD := 160
const LAMP_W := 161       # (glowing)
const LAMP_WARM := 162    # (glowing)
const LAMP_R := 163       # (glowing: emergency)
const LAMP_DEAD := 164
const LED_G := 165        # (glowing)
const LED_R := 166        # (glowing)
const LED_Y := 167        # (glowing)
const POSTER_A := 168
const POSTER_B := 169
const POSTER_C := 170
const PAPER := 171
const PLANT := 172
const PLANT_DEAD := 173
const POT := 174
const MUG := 175
const FOOD := 176
const WINDOW := 177       # (see-through)
const RED := 178
const SIGN := 179
const BLACK := 180
const CERAMIC := 181
const BOOK_A := 182
const BOOK_B := 183
const WATER := 184        # (glowing a little: a tank, a fountain)
const CHROME := 185
const HAZARD := 186
const STEEL := 187        # a third wall tone, blue-grey

const PAINT := {
	PLATE: ["#4b5462", "#545d6c", "#444c59", "#5c6575"],
	PLATE_D: ["#323844", "#383f4c", "#2d333e", "#3f4653"],
	SEAM: ["#1c2028", "#20242c", "#181b22", "#262a33"],
	RIVET: ["#6f798a", "#7b8597", "#66707f", "#8a94a6"],
	TRIM_G: ["#8f6c31", "#a07c3b", "#7d5d29", "#b8924d"],
	TRIM_T: ["#2d6b72", "#357a82", "#265d63", "#41909a"],
	WOOD: ["#6e4b2f", "#775335", "#664429", "#80593a"],
	WOOD_D: ["#4a3120", "#523724", "#432c1c", "#5a3d28"],
	TILE: ["#868f96", "#929ba2", "#7c858c", "#9ea7ae"],
	GROUT: ["#5a6268", "#60686e", "#545c62", "#6a7278"],
	HEX: ["#36474f", "#3d4f58", "#314048", "#465962"],
	GRATE: ["#262a2f", "#363b41", "#2d3237", "#41474e"],
	CARPET_R: ["#6b2a30", "#783036", "#5f252a", "#84383e"],
	CARPET_B: ["#2b3868", "#324074", "#26315c", "#3a4a82"],
	RUST: ["#6b3a22", "#5c3120", "#7a4529", "#4c2a1b"],
	GRIME: ["#24221d", "#2c2923", "#1e1c18", "#33302a"],
	SCORCH: ["#121110", "#171513", "#0e0d0c", "#1c1a17"],
	GOO: ["#4a2a68", "#5a3478", "#3e2358", "#6a4290"],
	METAL: ["#6a7078", "#787e86", "#5d636b", "#878d95"],
	METAL_D: ["#3e434a", "#464b53", "#373b42", "#50555d"],
	PIPE: ["#5b6066", "#6a7076", "#4c5157", "#7e848a"],
	PIPE_CU: ["#8a5a36", "#9a6840", "#7a4e2e", "#b07a4c"],
	CABLE: ["#1c1e22", "#26282d", "#16181b", "#303338"],
	CABLE_R: ["#6a2222", "#7a2a2a", "#5a1c1c", "#8a3434"],
	CABLE_Y: ["#8a7820", "#9a8828", "#7a6a1a", "#aa9a34"],
	FAB_B: ["#3a4c7c", "#425688", "#34446e", "#4c6296"],
	FAB_R: ["#7c3a3a", "#884242", "#6e3434", "#964c4c"],
	FAB_G: ["#3a6a4c", "#427656", "#345e44", "#4c8462"],
	PILLOW: ["#b6b2a6", "#c2beb2", "#a8a498", "#ceccc0"],
	SCREEN_B: ["#3aa8d8", "#58c0f0", "#2a90c0", "#8ad8ff"],
	SCREEN_G: ["#3ad88a", "#58f0a0", "#2ac078", "#8affc0"],
	SCREEN_A: ["#e8a83a", "#f0c058", "#d0902a", "#ffd88a"],
	SCREEN_DEAD: ["#10161e", "#161e28", "#0c1016", "#3a4654"],
	LAMP_W: ["#e6ecef", "#f4f8fa", "#d8dee2", "#ffffff"],
	LAMP_WARM: ["#ffc878", "#ffd898", "#f0b460", "#ffe8b8"],
	LAMP_R: ["#e83a2a", "#ff5440", "#c82e20", "#ff7a66"],
	LAMP_DEAD: ["#38383a", "#404044", "#303032", "#4a4a4e"],
	LED_G: ["#5aff8a", "#7affa4", "#48e070", "#a4ffc4"],
	LED_R: ["#ff4a3a", "#ff6a5a", "#e03a2a", "#ff8a7a"],
	LED_Y: ["#ffd84a", "#ffe46a", "#e8c03a", "#fff08a"],
	POSTER_A: ["#c84a3a", "#d8604e", "#b03e30", "#e8c84a"],
	POSTER_B: ["#3a72c0", "#4c86d4", "#3060a8", "#e8e0c8"],
	POSTER_C: ["#3aa070", "#4cb482", "#308a5e", "#f0a04a"],
	PAPER: ["#c4bca4", "#d4ccb4", "#b4ac94", "#e2dac2"],
	PLANT: ["#3a8a3a", "#4a9c48", "#2e7432", "#5cb052"],
	PLANT_DEAD: ["#5a4a2a", "#665432", "#4c3e22", "#72603c"],
	POT: ["#8a5a3a", "#9a6844", "#7a4e32", "#a87650"],
	MUG: ["#e2dccc", "#c8c2b2", "#d84a3a", "#3a7ac8"],
	FOOD: ["#c8783a", "#d8944a", "#9ac04a", "#e8c860"],
	WINDOW: ["#9ac8e8", "#b4dcf4", "#80b4d8", "#d8f0ff"],
	RED: ["#c83a3a", "#d84c4c", "#b03030", "#e86a6a"],
	SIGN: ["#16222e", "#1c2a38", "#121c26", "#24364a"],
	BLACK: ["#0c0d10", "#111216", "#08090b", "#16181c"],
	CERAMIC: ["#c8ccd0", "#d6dade", "#b8bcc0", "#e4e8ec"],
	BOOK_A: ["#8a3a3a", "#3a5a8a", "#4a7a3a", "#8a7a3a"],
	BOOK_B: ["#6a3a7a", "#3a7a7a", "#9a5a2a", "#5a5a5a"],
	WATER: ["#2a6a9a", "#3a80b0", "#245c88", "#5aa0d0"],
	CHROME: ["#9aa2ac", "#aab2bc", "#8a929c", "#c4ccd6"],
	HAZARD: ["#d8b030", "#1a1a1a", "#c8a028", "#222222"],
	STEEL: ["#3d4b5c", "#455467", "#374353", "#4e5e72"],
}
## codes that give off light, and the light's colour (an outpost gathers them into halos)
const GLOW := {SCREEN_B: Color(0.35, 0.7, 1.0), SCREEN_G: Color(0.35, 1.0, 0.6), SCREEN_A: Color(1.0, 0.7, 0.3),
	LAMP_W: Color(0.95, 0.97, 1.0), LAMP_WARM: Color(1.0, 0.8, 0.5), LAMP_R: Color(1.0, 0.25, 0.2), LED_G: Color(0.4, 1.0, 0.55),
	LED_R: Color(1.0, 0.3, 0.25), LED_Y: Color(1.0, 0.85, 0.3), WATER: Color(0.3, 0.6, 0.9)}
const SEE_THROUGH := {WINDOW: 70}       # (alpha out of 255: the station's own interior shows through)

## the colour of a paint code's shade, as the colour table packs it (station.gd `_ensure_lut`)
static func color(code: int, v: int) -> Color:
	var row: Array = PAINT.get(code, ["#ff00ff", "#ff00ff", "#ff00ff", "#ff00ff"])
	var c := Color.html(String(row[v & 3]))
	if SEE_THROUGH.has(code):
		c.a = float(SEE_THROUGH[code]) / 255.0
	return c

static func glows(code: int) -> bool:
	return GLOW.has(code)

# ------------------------------------------------------------------ canvas --
## a room's back layer to paint on: the body's own arrays (shared), its width, and how it's to look
class Cv:
	var bg: PackedByteArray
	var bgv: PackedByteArray
	var w := 0
	var h := 0
	var rng: RandomNumberGenerator
	var noise: FastNoiseLite
	var dead := false              # a derelict's broken rooms: no power, abandoned
	var lived := false             # an outpost's: busy, kept up
	func p(i: int, j: int, c: int, v := 0) -> void:
		if i >= 0 and j >= 0 and i < w and j < h:
			bg[j * w + i] = c
			bgv[j * w + i] = v
	func r(x0: int, y0: int, x1: int, y1: int, c: int, v := 0) -> void:
		for j in range(maxi(y0, 0), mini(y1, h)):
			for i in range(maxi(x0, 0), mini(x1, w)):
				bg[j * w + i] = c
				bgv[j * w + i] = v
	func at(i: int, j: int) -> int:
		if i >= 0 and j >= 0 and i < w and j < h:
			return bg[j * w + i]
		return 0
	func ri(a: int, b: int) -> int:
		return rng.randi_range(a, b)
	func chance(f: float) -> bool:
		return rng.randf() < f
	func n2(i: float, j: float) -> float:
		return noise.get_noise_2d(i, j)

# ------------------------------------------------------------------- walls --
const STYLES := ["plate", "rib", "tile", "wood", "hex", "grate", "lux", "steel"]

## a room's back wall in a style: a cornice and a light strip under the roof, panels, a trim line, a wainscot and
## a kick plate at the floor; a derelict's grimed, rusted, scorched, panels missing, its strip dead or red
static func wall(cv: Cv, x0: int, y0: int, x1: int, y1: int, style: String, drop := PackedInt32Array()) -> void:
	var wain := y1 - maxi(14, (y1 - y0) / 3)        # (the wainscot's top row)
	var up_c := PLATE
	var lo_c := PLATE_D
	var trim := METAL
	match style:
		"wood":
			up_c = WOOD
			lo_c = WOOD_D
			trim = TRIM_G
		"tile":
			up_c = TILE
			lo_c = TRIM_T
			trim = CERAMIC
		"hex":
			up_c = HEX
			lo_c = PLATE_D
			trim = TRIM_T
		"grate":
			up_c = GRATE
			lo_c = METAL_D
			trim = HAZARD
		"lux":
			up_c = PLATE
			lo_c = CARPET_B
			trim = TRIM_G
		"steel":
			up_c = STEEL
			lo_c = PLATE_D
			trim = CHROME
		"rib":
			up_c = PLATE_D
			lo_c = METAL_D
			trim = PIPE
	for j in range(y0, y1):
		var rj := j - y0
		for i in range(x0, x1):
			var ri := i - x0
			var tj := j - y0 - (int(drop[ri]) if ri < drop.size() else 0)      # (rows under the roof here)
			var c := up_c
			var v := 0
			if j >= y1 - 3:
				c = METAL_D if style != "wood" else WOOD_D
				v = 2 if j == y1 - 3 else 0
			elif j >= wain:
				c = lo_c
				match style:
					"wood":
						v = 1 if ri % 6 == 0 else (0 if ri % 6 < 3 else 2)
					"tile":
						v = 0 if (ri / 4 + (j - wain) / 4) % 2 == 0 else 2
						if ri % 4 == 0 or (j - wain) % 4 == 0:
							c = GROUT
					"grate":
						v = 1 if (ri % 3 == 0 or (j - wain) % 3 == 0) else 0
					"lux":
						v = (ri / 2 + (j - wain)) % 2
					_:
						v = 0 if (ri / 16) % 2 == 0 else 2
						if ri % 16 == 0:
							c = SEAM
			elif j == wain - 1:
				c = trim
				v = 1
			elif tj < 2:
				c = METAL_D
				v = 1 if tj == 0 else 3
			else:
				match style:
					"plate", "lux", "steel":
						v = 0 if ((ri / 20) + (rj / 12)) % 2 == 0 else 2
						if ri % 20 == 0 or rj % 12 == 0:
							c = SEAM
						elif (ri % 20 == 2 or ri % 20 == 18) and rj % 12 == 2:
							c = RIVET
					"rib":
						v = 0 if (rj / 6) % 2 == 0 else 1
						if ri % 14 == 0 or ri % 14 == 1:
							c = METAL_D
							v = 2 if ri % 14 == 0 else 3
					"tile":
						v = 0 if ((ri / 5) + (rj / 5)) % 2 == 0 else 1
						if ri % 5 == 0 or rj % 5 == 0:
							c = GROUT
					"wood":
						v = (ri / 4) % 3
						if ri % 4 == 0:
							c = WOOD_D
							v = 1
					"hex":
						var off := 4 if (rj / 5) % 2 == 0 else 0
						v = ((ri + off) / 8) % 2
						if (ri + off) % 8 == 0 or rj % 5 == 0:
							c = SEAM
					"grate":
						v = 2 if (ri % 4 == 0 or rj % 4 == 0) else 0
						if ri % 4 == 0 and rj % 4 == 0:
							c = METAL_D
			cv.bg[j * cv.w + i] = c
			cv.bgv[j * cv.w + i] = v
	# the light strip under the cornice: lamps lit, dead, or now and then a red emergency lamp
	for i2 in range(x0 + 4, x1 - 4):
		if (i2 - x0) % 18 < 10:
			var lc := LAMP_W if style != "wood" and style != "lux" else LAMP_WARM
			if cv.dead:
				lc = LAMP_R if (i2 - x0) / 18 % 4 == 1 else LAMP_DEAD
			cv.p(i2, y0 + 2 + (int(drop[i2 - x0]) if i2 - x0 < drop.size() else 0), lc, 0)
	if cv.dead:
		_decay(cv, x0, y0, x1, y1)

## a derelict's wall: grime and rust in drifts, scorching, a few panels torn away (dark, cables behind)
static func _decay(cv: Cv, x0: int, y0: int, x1: int, y1: int) -> void:
	for j in range(y0, y1):
		for i in range(x0, x1):
			var n := cv.n2(float(i) * 1.6, float(j) * 1.6)
			var n2 := cv.n2(float(i) * 0.7 + 300.0, float(j) * 2.4)
			if n > 0.42:
				cv.bg[j * cv.w + i] = SCORCH if n > 0.55 else GRIME
				cv.bgv[j * cv.w + i] = (i + j) % 4
			elif n2 > 0.5 and j > y0 + 3:
				cv.bg[j * cv.w + i] = RUST
				cv.bgv[j * cv.w + i] = (i * 3 + j) % 4
	for k in cv.ri(1, 3):
		var px := cv.ri(x0 + 6, x1 - 18)
		var py := cv.ri(y0 + 5, y1 - 26)
		cv.r(px, py, px + 12, py + 10, BLACK, 0)
		for q in 4:
			var cx := px + 2 + q * 3
			var col: int = [CABLE, CABLE_R, CABLE_Y, CABLE][q]
			for jj in range(py, py + 10):
				cv.p(cx + (1 if jj % 5 == 2 else 0), jj, col, jj % 4)

# ------------------------------------------------------------------- parts --
# (each takes the left column x and the floor's row fl (its first solid row): a part stands on fl - 1 and up)

static func bunk(cv: Cv, x: int, fl: int) -> void:
	for tier in 2:
		var by := fl - 6 - tier * 13
		cv.r(x, by, x + 20, by + 2, METAL, 1)
		var fab: int = [FAB_B, FAB_R, FAB_G][cv.ri(0, 2)]
		var flat := cv.dead and cv.chance(0.5)
		if not flat:
			cv.r(x + 1, by - 3, x + 19, by, fab, cv.ri(0, 1))
			cv.r(x + 1, by - 3, x + 5, by - 1, PILLOW, 0)
			if cv.lived and cv.chance(0.5):
				cv.r(x + 11, by - 3, x + 19, by - 2, fab, 3)        # (a blanket thrown back)
		elif cv.chance(0.6):
			for q in 6:
				cv.p(x + 19 + q / 3, by + q, fab, 2)                 # (a blanket hanging off)
	for j in range(fl - 20, fl):
		cv.p(x, j, METAL, 2)
		cv.p(x + 19, j, METAL, 2)
	for jl in range(fl - 19, fl - 6, 3):
		cv.p(x + 21, jl, METAL, 0)
		cv.p(x + 22, jl, METAL, 0)

static func locker(cv: Cv, x: int, fl: int) -> void:
	var tilt := cv.dead and cv.chance(0.3)
	if tilt:
		cv.r(x - 6, fl - 6, x + 10, fl, METAL_D, 0)               # (knocked over)
		cv.r(x - 5, fl - 4, x + 9, fl - 3, SEAM, 0)
		return
	cv.r(x, fl - 18, x + 7, fl, METAL_D, 0)
	cv.r(x + 1, fl - 17, x + 6, fl - 1, METAL, 0)
	for vj in [fl - 15, fl - 14, fl - 13]:
		cv.r(x + 2, int(vj), x + 5, int(vj) + 1, SEAM, 0)
	cv.p(x + 5, fl - 9, CHROME, 3)
	if cv.lived and cv.chance(0.4):
		poster(cv, x + 1, fl - 12, 4, 4)

static func desk(cv: Cv, x: int, fl: int) -> void:
	cv.r(x, fl - 9, x + 16, fl - 7, WOOD_D if not cv.dead else METAL_D, 0)
	cv.r(x + 1, fl - 7, x + 2, fl, METAL, 2)
	cv.r(x + 14, fl - 7, x + 15, fl, METAL, 2)
	cv.r(x + 10, fl - 7, x + 15, fl - 2, METAL_D, 1)           # (drawers)
	screen(cv, x + 4, fl - 16, 7, 5)
	cv.p(x + 7, fl - 10, METAL, 0)
	if not cv.dead:
		cv.p(x + 13, fl - 10, MUG, cv.ri(0, 3))
		cv.p(x + 1, fl - 13, METAL, 0)
		cv.p(x + 1, fl - 12, METAL, 0)
		cv.r(x, fl - 14, x + 3, fl - 13, LAMP_WARM, 0)
	else:
		for q in 3:
			cv.p(x + cv.ri(-4, 18), fl - 1, PAPER, q)             # (papers on the floor)

## a screen on the wall (lit with something on it; dead and cracked in a derelict)
static func screen(cv: Cv, x: int, y: int, sw: int, sh: int) -> void:
	cv.r(x - 1, y - 1, x + sw + 1, y + sh + 1, METAL_D, 0)
	if cv.dead:
		cv.r(x, y, x + sw, y + sh, SCREEN_DEAD, 0)
		var cx := x + cv.ri(0, sw - 1)
		for q in mini(sw, sh) + 2:
			cv.p(cx + (q % 3) - 1, y + q % sh, SCREEN_DEAD, 3)      # (a crack)
		return
	var sc: int = [SCREEN_B, SCREEN_G, SCREEN_A][cv.ri(0, 2)]
	cv.r(x, y, x + sw, y + sh, sc, 2)
	for i in range(x, x + sw):
		var lj := y + int(float(sh) * 0.5 + sin(float(i - x) * 0.9 + float(cv.ri(0, 3))) * float(sh) * 0.3)
		cv.p(i, clampi(lj, y, y + sh - 1), sc, 3)               # (a trace on it)
	if sh >= 4:
		for i2 in range(x + 1, x + sw - 1, 2):
			cv.p(i2, y + 1, sc, 0)

static func console(cv: Cv, x: int, fl: int, cw: int) -> void:
	cv.r(x, fl - 8, x + cw, fl, METAL_D, 0)
	cv.r(x, fl - 9, x + cw, fl - 8, METAL, 3)
	for i in range(x + 2, x + cw - 2, 3):
		cv.p(i, fl - 6, [LED_G, LED_Y, LED_R, LED_G][cv.ri(0, 3)] if not cv.dead else SCREEN_DEAD, 0)
	for sx in range(x + 1, x + cw - 6, 8):
		screen(cv, sx, fl - 18, 6, 5)

static func table(cv: Cv, x: int, fl: int, tw: int) -> void:
	var tc := METAL if not cv.lived else WOOD
	var flipped := cv.dead and cv.chance(0.35)
	if flipped:
		cv.r(x + 2, fl - 3, x + tw - 2, fl - 1, tc, 2)
		cv.r(x + tw / 2, fl - 9, x + tw / 2 + 2, fl - 1, tc, 1)
		return
	cv.r(x, fl - 8, x + tw, fl - 7, tc, 3)
	cv.r(x + tw / 2 - 1, fl - 7, x + tw / 2 + 1, fl, METAL_D, 0)
	for sx in [x - 4, x + tw + 1]:
		if cv.dead and cv.chance(0.5):
			cv.r(int(sx) - 1, fl - 2, int(sx) + 4, fl - 1, METAL, 1)     # (a stool on its side)
		else:
			cv.r(int(sx), fl - 5, int(sx) + 3, fl - 4, FAB_R if cv.lived else METAL, 0)
			cv.p(int(sx) + 1, fl - 4, METAL_D, 0)
			cv.p(int(sx) + 1, fl - 3, METAL_D, 0)
			cv.p(int(sx) + 1, fl - 2, METAL_D, 0)
			cv.p(int(sx) + 1, fl - 1, METAL_D, 0)
	if not cv.dead:
		for q in cv.ri(1, 3):
			var ix := x + 2 + cv.ri(0, tw - 4)
			cv.p(ix, fl - 9, MUG if cv.chance(0.5) else FOOD, cv.ri(0, 3))

static func counter(cv: Cv, x: int, fl: int, cw: int) -> void:
	cv.r(x, fl - 11, x + cw, fl - 10, CHROME, 0)
	cv.r(x, fl - 10, x + cw, fl, METAL_D, 0)
	for i in range(x + 2, x + cw - 1, 6):
		cv.r(i, fl - 8, i + 4, fl - 2, METAL, 1)

## a food dispenser or drinks machine on the wall
static func dispenser(cv: Cv, x: int, y: int) -> void:
	cv.r(x, y, x + 10, y + 14, METAL, 0)
	cv.r(x + 1, y + 1, x + 9, y + 5, SCREEN_A if not cv.dead else SCREEN_DEAD, 1)
	cv.r(x + 3, y + 8, x + 7, y + 12, BLACK, 0)
	cv.p(x + 8, y + 9, LED_G if not cv.dead else LAMP_DEAD, 0)

static func medbed(cv: Cv, x: int, fl: int) -> void:
	cv.r(x, fl - 7, x + 22, fl - 5, CHROME, 0)
	if not (cv.dead and cv.chance(0.5)):
		cv.r(x + 1, fl - 9, x + 21, fl - 7, CERAMIC, 1)
		cv.r(x + 1, fl - 10, x + 5, fl - 8, PILLOW, 0)
	cv.r(x + 1, fl - 5, x + 2, fl, METAL, 0)
	cv.r(x + 20, fl - 5, x + 21, fl, METAL, 0)
	# a monitor on an arm over it, with a heartbeat
	cv.r(x + 24, fl - 24, x + 25, fl, METAL_D, 0)
	cv.r(x + 18, fl - 24, x + 25, fl - 23, METAL_D, 0)
	cv.r(x + 14, fl - 30, x + 22, fl - 24, METAL_D, 0)
	if cv.dead:
		cv.r(x + 15, fl - 29, x + 21, fl - 25, SCREEN_DEAD, 0)
	else:
		cv.r(x + 15, fl - 29, x + 21, fl - 25, BLACK, 0)
		var beat := [2, 2, 2, 0, 3, 2, 2]
		for q in 6:
			cv.p(x + 15 + q, fl - 29 + int(beat[q]), SCREEN_G, 3)

static func cabinet(cv: Cv, x: int, fl: int) -> void:
	cv.r(x, fl - 22, x + 12, fl, CERAMIC, 2)
	cv.r(x + 1, fl - 21, x + 11, fl - 12, WINDOW if not cv.dead else SCREEN_DEAD, 0)
	for sy in [fl - 18, fl - 15]:
		cv.r(x + 1, int(sy), x + 11, int(sy) + 1, METAL, 0)
	if not cv.dead:
		for q in 4:
			cv.p(x + 2 + q * 2, fl - 19, [RED, LED_G, PAPER, MUG][q], 0)
	cv.r(x + 5, fl - 9, x + 7, fl - 4, RED, 0)
	cv.r(x + 4, fl - 8, x + 8, fl - 5, RED, 0)
	cv.r(x + 5, fl - 8, x + 7, fl - 5, RED, 0)

static func plant(cv: Cv, x: int, fl: int, tall: bool) -> void:
	cv.r(x, fl - 5, x + 6, fl, POT, 0)
	cv.r(x - 1, fl - 6, x + 7, fl - 5, POT, 3)
	var hgt := 14 if tall else 8
	var leaf := PLANT if not cv.dead else PLANT_DEAD
	for q in hgt * 3:
		var a := float(q) * 2.4
		var rr := float(q % hgt) * 0.5
		var lx := x + 3 + int(cos(a) * rr * 0.9)
		var ly := fl - 6 - (q % hgt)
		if cv.dead and q % 3 != 0:
			continue
		cv.p(lx, ly, leaf, q % 4)
		cv.p(lx + 1, ly, leaf, (q + 1) % 4)

static func shelf(cv: Cv, x: int, y: int, sw: int) -> void:
	cv.r(x, y, x + sw, y + 1, WOOD_D if not cv.dead else METAL_D, 1)
	var i := x + 1
	while i < x + sw - 1:
		var bw := cv.ri(1, 2)
		var bh := cv.ri(3, 5)
		if cv.dead and cv.chance(0.4):
			if cv.chance(0.5):
				cv.r(i, y - 1, i + bh, y, BOOK_A, cv.ri(0, 3))        # (fallen over)
			i += bw + 1
			continue
		cv.r(i, y - bh, i + bw, y, BOOK_A if cv.chance(0.5) else BOOK_B, cv.ri(0, 3))
		i += bw + (1 if cv.chance(0.3) else 0)

static func poster(cv: Cv, x: int, y: int, pw: int, ph: int) -> void:
	var pc: int = [POSTER_A, POSTER_B, POSTER_C][cv.ri(0, 2)]
	cv.r(x, y, x + pw, y + ph, pc, cv.ri(0, 2))
	cv.r(x + 1, y + 1, x + pw - 1, y + ph / 2, pc, 3)
	if cv.dead:
		cv.p(x + pw - 1, y, GRIME, 0)                          # (a torn corner)
		cv.p(x + pw - 2, y, GRIME, 0)
		cv.p(x + pw - 1, y + 1, GRIME, 0)

## pipes along a wall: a run with flanges, dripping a bit of rust where it's a derelict's
static func pipes(cv: Cv, x0: int, x1: int, y: int, n: int) -> void:
	for q in n:
		var py := y + q * 3
		var pc := PIPE if q % 2 == 0 else PIPE_CU
		for i in range(x0, x1):
			cv.p(i, py, pc, 3 if q == 0 else 0)
			cv.p(i, py + 1, pc, 2)
			if (i - x0) % 22 == 0:
				cv.p(i, py - 1, METAL_D, 0)
				cv.p(i, py + 2, METAL_D, 0)
		if cv.dead and cv.chance(0.6):
			var dx := cv.ri(x0 + 4, x1 - 4)
			for dj in cv.ri(3, 9):
				cv.p(dx, py + 2 + dj, RUST, dj % 4)

## cables sagging between two points (a derelict's hang down loose)
static func cables(cv: Cv, x0: int, x1: int, y: int, sag: float) -> void:
	for q in 3:
		var col: int = [CABLE, CABLE_R, CABLE_Y][q]
		for i in range(x0, x1):
			var t := float(i - x0) / maxf(1.0, float(x1 - x0))
			var j := y + q + int(sag * 4.0 * t * (1.0 - t))
			cv.p(i, j, col, q)
	if cv.dead:
		for k in cv.ri(1, 3):
			var hx := cv.ri(x0 + 2, x1 - 2)
			var hl := cv.ri(6, 16)
			for hj in hl:
				cv.p(hx + (1 if hj % 6 > 3 else 0), y + 2 + hj, CABLE_R if k == 1 else CABLE, hj % 4)

static func vent(cv: Cv, x: int, y: int) -> void:
	cv.r(x, y, x + 8, y + 5, METAL_D, 0)
	for vj in range(y + 1, y + 4):
		cv.r(x + 1, vj, x + 7, vj + 1, BLACK if vj % 2 == 1 else METAL, 0)

static func crates(cv: Cv, x: int, fl: int) -> void:
	var cx := x
	for q in cv.ri(2, 4):
		var cw := cv.ri(6, 9)
		var ch := cv.ri(5, 8)
		var cc: int = [WOOD, METAL, FAB_G, PIPE_CU][cv.ri(0, 3)]
		cv.r(cx, fl - ch, cx + cw, fl, cc, 0)
		cv.r(cx, fl - ch, cx + cw, fl - ch + 1, cc, 3)
		cv.r(cx + cw / 2, fl - ch, cx + cw / 2 + 1, fl, cc, 2)
		if q == 0 and cv.chance(0.5):
			var tw := cw - 2
			cv.r(cx + 1, fl - ch - 5, cx + 1 + tw, fl - ch, cc, 1)    # (one stacked on top)
		cx += cw + cv.ri(0, 2)

static func barrel(cv: Cv, x: int, fl: int) -> void:
	cv.r(x, fl - 10, x + 6, fl, HAZARD if cv.chance(0.4) else METAL, 0)
	for bj in [fl - 8, fl - 3]:
		cv.r(x, int(bj), x + 6, int(bj) + 1, METAL_D, 0)

static func machine(cv: Cv, x: int, fl: int) -> void:
	var mw := cv.ri(14, 20)
	var mh := cv.ri(18, 26)
	cv.r(x, fl - mh, x + mw, fl, METAL_D, 0)
	cv.r(x + 1, fl - mh + 1, x + mw - 1, fl - mh + 3, METAL, 3)
	for g in 3:
		var gx := x + 3 + g * 5
		if gx + 3 < x + mw:
			cv.r(gx, fl - mh + 5, gx + 3, fl - mh + 8, BLACK, 0)
			cv.p(gx + 1, fl - mh + 6, LED_G if not cv.dead else LAMP_DEAD, 0)
	for vj in range(fl - mh + 11, fl - 3, 2):
		cv.r(x + 2, vj, x + mw - 2, vj + 1, GRATE, 1)
	cv.r(x + mw, fl - mh + 4, x + mw + 6, fl - mh + 6, PIPE, 0)
	for pj in range(fl - mh + 4, fl):
		cv.p(x + mw + 5, pj, PIPE, 2)

static func signboard(cv: Cv, x: int, y: int, sw: int, lit: int) -> void:
	cv.r(x, y, x + sw, y + 7, SIGN, 0)
	cv.r(x, y, x + sw, y + 1, METAL, 0)
	if cv.dead:
		return
	for q in range(x + 2, x + sw - 2):
		if (q * 7 + y) % 3 != 0:
			cv.p(q, y + 2 + (1 if q % 3 == 0 else 0), lit, 0)
			if q % 2 == 0:
				cv.p(q, y + 4, lit, 1)

## a window in the wall: a frame, and glass you see the station's own interior through
static func window(cv: Cv, x: int, y: int, ww: int, wh: int) -> void:
	cv.r(x - 1, y - 1, x + ww + 1, y + wh + 1, METAL_D, 0)
	cv.r(x, y, x + ww, y + wh, WINDOW, 0)
	for q in mini(ww, wh) / 2:
		cv.p(x + 2 + q, y + 1 + q, WINDOW, 3)                      # (a glint)
	if cv.dead:
		var cx := x + cv.ri(1, ww - 2)
		var cy := y + cv.ri(1, wh - 2)
		for q2 in 10:
			var a := float(q2) * 0.63
			cv.p(cx + int(cos(a) * float(q2 % 4 + 1)), cy + int(sin(a) * float(q2 % 4 + 1)), SCREEN_DEAD, 3)

static func rug(cv: Cv, x0: int, x1: int, fl: int, col: int) -> void:
	for i in range(x0, x1):
		cv.p(i, fl - 1, col, 0 if (i - x0) % 4 < 2 else 2)
	cv.p(x0, fl - 1, TRIM_G, 0)
	cv.p(x1 - 1, fl - 1, TRIM_G, 0)

## a derelict's floor and walls: papers, bits of metal, alien goo in drips
static func debris(cv: Cv, x0: int, x1: int, fl: int) -> void:
	for q in cv.ri(5, 12):
		var dx := cv.ri(x0 + 2, x1 - 3)
		var dc: int = [PAPER, METAL, METAL_D, PIPE, GRIME][cv.ri(0, 4)]
		cv.p(dx, fl - 1, dc, cv.ri(0, 3))
		if cv.chance(0.4):
			cv.p(dx + 1, fl - 1, dc, cv.ri(0, 3))
	if cv.chance(0.5):
		var gx := cv.ri(x0 + 4, x1 - 10)
		var gl := cv.ri(5, 12)
		for gi in gl:
			cv.p(gx + gi, fl - 1, GOO, gi % 4)
			if gi % 3 == 0:
				cv.p(gx + gi, fl - 2, GOO, 3)

## hydroponics: grow racks with lamps over each tier
static func grow_rack(cv: Cv, x: int, y: int, rw: int) -> void:
	cv.r(x, y, x + rw, y + 2, METAL, 1)
	cv.r(x, y - 9, x + rw, y - 8, LAMP_W if not cv.dead else LAMP_DEAD, 0)
	var leaf := PLANT if not cv.dead else PLANT_DEAD
	for i in range(x + 1, x + rw - 1):
		var hgt := 2 + int((cv.n2(float(i) * 3.0, float(y)) + 1.0) * 2.5)
		if cv.dead:
			hgt = hgt / 2
		for q in hgt:
			cv.p(i, y - 1 - q, leaf, (i + q) % 4)

## a long viewscreen (command, comms): stars and a map on it, or dead
static func viewscreen(cv: Cv, x: int, y: int, sw: int, sh: int) -> void:
	cv.r(x - 2, y - 2, x + sw + 2, y + sh + 2, METAL_D, 0)
	if cv.dead:
		cv.r(x, y, x + sw, y + sh, SCREEN_DEAD, 0)
		for q in sw:
			if cv.chance(0.15):
				cv.p(x + q, y + cv.ri(0, sh - 1), SCREEN_DEAD, 3)
		return
	cv.r(x, y, x + sw, y + sh, BLACK, 0)
	for q in sw * sh / 14:
		cv.p(x + cv.ri(0, sw - 1), y + cv.ri(0, sh - 1), SCREEN_B, cv.ri(0, 3))
	var cx := x + sw / 2
	var cy := y + sh / 2
	for a in 40:
		var ang := float(a) / 40.0 * TAU
		cv.p(cx + int(cos(ang) * float(sh) * 0.35 * 1.6), cy + int(sin(ang) * float(sh) * 0.35), SCREEN_G, 0)
	cv.p(cx, cy, LED_Y, 0)

# --------------------------------------------------------------- furnishing --
## each room's wall style by role (with the seed's own pick among those that suit it)
const ROLE_STYLES := {
	"quarters": ["wood", "plate", "lux"], "mess": ["tile", "wood", "plate"], "medbay": ["tile"],
	"engineering": ["grate", "rib"], "command": ["steel", "hex"], "lounge": ["lux", "wood"],
	"comms": ["hex", "steel"], "hydro": ["tile", "hex"], "lab": ["tile", "hex", "steel"], "stores": ["rib", "grate"],
	"hall": ["plate", "steel", "hex"], "reactor": ["rib", "grate"], "dock": ["rib"], "hangar": ["rib"],
	"market": ["lux"], "shipwright": ["rib", "grate"], "cantina": ["wood"], "charts": ["hex", "steel"],
	"promenade": ["lux", "steel"], "observatory": ["steel", "hex"],
	"brig": ["steel", "grate"], "cabins": ["wood", "lux", "plate"], "armory": ["steel", "rib"], "galley": ["tile", "plate"],
	"corridor": ["plate", "rib", "steel", "hex", "grate"], "shaft": ["rib", "grate"],
}

static func style_for(role: String, rng: RandomNumberGenerator) -> String:
	var opts: Array = ROLE_STYLES.get(role, ["plate"])
	return String(opts[rng.randi_range(0, opts.size() - 1)])

## dress a room for its role: furniture and the signs of life (or of its abandonment). x0..x1, y0..y1: the room's
## inside; fl = y1 (the floor's first solid row). `top` is where the roof comes down to at each end (shaped rooms).
static func furnish(cv: Cv, role: String, x0: int, y0: int, x1: int, y1: int) -> void:
	var fl := y1
	var mw := x1 - x0
	match role:
		"quarters":
			var bx := x0 + 4
			while bx + 24 < x1 - 20:
				bunk(cv, bx, fl)
				bx += 28
			locker(cv, x1 - 30, fl)
			locker(cv, x1 - 22, fl)
			if mw > 90:
				desk(cv, x1 - 16, fl)
			for q in 3:
				if cv.chance(0.6):
					poster(cv, x0 + 6 + q * 28, y0 + 8, 6, 8)
			vent(cv, x1 - 20, y0 + 6)
			if cv.lived:
				rug(cv, x0 + 8, x1 - 34, fl, CARPET_R if cv.chance(0.5) else CARPET_B)
		"mess":
			counter(cv, x0 + 3, fl, 26)
			dispenser(cv, x0 + 6, fl - 30)
			dispenser(cv, x0 + 18, fl - 30)
			var tx := x0 + 40
			while tx + 20 < x1 - 4:
				table(cv, tx, fl, 16)
				tx += 26
			signboard(cv, x1 - 30, y0 + 7, 22, LED_Y)
			if cv.lived:
				plant(cv, x1 - 10, fl, false)
		"medbay":
			medbed(cv, x0 + 4, fl)
			medbed(cv, x0 + 34, fl)
			cabinet(cv, x1 - 16, fl)
			if mw > 100:
				cabinet(cv, x1 - 30, fl)
			screen(cv, x0 + 66, y0 + 10, 14, 8)
			if not cv.dead:
				cv.r(x0 + 2, y0 + 4, x1 - 2, y0 + 5, RED, 0)
		"engineering":
			var mx := x0 + 4
			while mx + 26 < x1:
				machine(cv, mx, fl)
				mx += cv.ri(28, 36)
			pipes(cv, x0, x1, y0 + 6, 3)
			barrel(cv, x1 - 10, fl)
			barrel(cv, x1 - 18, fl)
			for q3 in range(x0 + 10, x1 - 10, 30):
				cv.p(q3, y0 + 16, LED_Y if not cv.dead else LAMP_R, 0)
		"command":
			viewscreen(cv, x0 + (mw - 60) / 2, y0 + 8, 60, 22)
			console(cv, x0 + 8, fl, 30)
			console(cv, x1 - 38, fl, 30)
			cv.r(x0 + mw / 2 - 5, fl - 7, x0 + mw / 2 + 5, fl - 5, FAB_B if not cv.dead else METAL_D, 0)   # (the chair)
			cv.r(x0 + mw / 2 - 1, fl - 5, x0 + mw / 2 + 1, fl, METAL, 0)
			cv.r(x0 + mw / 2 + 3, fl - 14, x0 + mw / 2 + 5, fl - 7, FAB_B if not cv.dead else METAL_D, 0)
		"lounge":
			# a sofa, a low table, plants, a shelf of books, a screen; windows onto the station
			cv.r(x0 + 8, fl - 8, x0 + 40, fl - 3, FAB_R if cv.chance(0.5) else FAB_B, 0)
			cv.r(x0 + 8, fl - 12, x0 + 40, fl - 8, FAB_R if cv.chance(0.5) else FAB_B, 2)
			cv.r(x0 + 6, fl - 10, x0 + 9, fl - 3, METAL_D, 0)
			cv.r(x0 + 39, fl - 10, x0 + 42, fl - 3, METAL_D, 0)
			cv.r(x0 + 10, fl - 3, x0 + 12, fl, METAL_D, 0)
			cv.r(x0 + 36, fl - 3, x0 + 38, fl, METAL_D, 0)
			table(cv, x0 + 48, fl, 12)
			plant(cv, x0 + 66, fl, true)
			plant(cv, x1 - 10, fl, true)
			shelf(cv, x1 - 40, y0 + 18, 24)
			shelf(cv, x1 - 40, y0 + 28, 24)
			window(cv, x0 + 12, y0 + 8, 26, 16)
			if cv.lived:
				rug(cv, x0 + 6, x0 + 62, fl, CARPET_B)
		"comms":
			for rx in range(x0 + 4, x1 - 14, 16):
				cv.r(rx, fl - 30, rx + 10, fl, METAL_D, 0)
				for lj in range(fl - 28, fl - 2, 3):
					for li in range(rx + 2, rx + 9, 2):
						cv.p(li, lj, [LED_G, LED_Y, LED_G, LED_R][(li + lj + rx) % 4] if not cv.dead and cv.chance(0.6) else BLACK, 0)
			cables(cv, x0, x1, y0 + 4, 6.0)
			if mw > 80:
				viewscreen(cv, x0 + 20, y0 + 10, 30, 10)
		"hydro":
			for ry in [y0 + 18, y0 + 34, fl - 6]:
				grow_rack(cv, x0 + 4, int(ry), mw - 8)
			pipes(cv, x0, x1, y0 + 5, 1)
			for dx in range(x0 + 10, x1 - 10, 24):
				cv.p(dx, y0 + 8, WATER, 0)
		"lab":
			# glass tanks with something kept in each, a bench of instruments, screens
			var tx2 := x0 + 6
			while tx2 + 14 < x1 - 30:
				cv.r(tx2, fl - 26, tx2 + 12, fl - 2, METAL_D, 0)
				cv.r(tx2 + 1, fl - 25, tx2 + 11, fl - 3, WINDOW if not cv.dead else SCREEN_DEAD, 0)
				var kept := GOO if cv.dead or cv.chance(0.5) else PLANT
				for kq in 30:
					var ka := float(kq) * 0.9
					cv.p(tx2 + 6 + int(cos(ka) * float(kq % 5)), fl - 14 + int(sin(ka) * float(kq % 6)), kept, kq % 4)
				cv.r(tx2, fl - 2, tx2 + 12, fl, METAL, 1)
				tx2 += 18
			console(cv, x1 - 28, fl, 24)
			cv.r(x0 + 4, y0 + 14, x1 - 4, y0 + 15, METAL_D, 0)
			for q4 in range(x0 + 6, x1 - 6, 5):
				if cv.chance(0.6):
					cv.r(q4, y0 + 11, q4 + 2, y0 + 14, [CERAMIC, WINDOW, BOOK_A, CHROME][cv.ri(0, 3)], cv.ri(0, 3))
		"stores":
			for row in [y0 + 16, y0 + 32]:
				cv.r(x0 + 3, int(row), x1 - 3, int(row) + 1, METAL, 1)
				var sx := x0 + 4
				while sx < x1 - 10:
					if cv.chance(0.75):
						var bw := cv.ri(5, 8)
						var bh := cv.ri(4, 7)
						cv.r(sx, int(row) - bh, sx + bw, int(row), [WOOD, METAL, FAB_G, PIPE_CU, HAZARD][cv.ri(0, 4)], cv.ri(0, 2))
						sx += bw + 1
					else:
						sx += 6
			crates(cv, x0 + 6, fl)
			crates(cv, x1 - 36, fl)
			barrel(cv, x0 + mw / 2, fl)
		"hall":
			# pillars with lamps, benches between, a sign and plants
			var px := x0 + 16
			while px < x1 - 8:
				cv.r(px, y0 + 3, px + 5, fl, METAL_D, 0)
				cv.r(px + 1, y0 + 3, px + 2, fl, METAL, 3)
				cv.r(px - 1, y0 + 3, px + 6, y0 + 5, METAL, 1)
				cv.r(px - 1, fl - 3, px + 6, fl, METAL, 1)
				cv.r(px + 1, y0 + 12, px + 4, y0 + 14, LAMP_W if not cv.dead else LAMP_DEAD, 0)
				px += 30
			for bq in range(x0 + 24, x1 - 24, 30):
				cv.r(bq, fl - 5, bq + 12, fl - 4, WOOD if not cv.dead else METAL_D, 0)
				cv.p(bq + 1, fl - 4, METAL_D, 0)
				cv.p(bq + 1, fl - 3, METAL_D, 0)
				cv.p(bq + 1, fl - 2, METAL_D, 0)
				cv.p(bq + 1, fl - 1, METAL_D, 0)
				cv.p(bq + 10, fl - 4, METAL_D, 0)
				cv.p(bq + 10, fl - 3, METAL_D, 0)
				cv.p(bq + 10, fl - 2, METAL_D, 0)
				cv.p(bq + 10, fl - 1, METAL_D, 0)
			signboard(cv, x0 + mw / 2 - 12, y0 + 18, 24, LED_G)
			if cv.lived:
				plant(cv, x0 + 4, fl, true)
				plant(cv, x1 - 10, fl, true)
		"promenade":
			var wx := x0 + 6
			while wx + 20 < x1 - 2:
				window(cv, wx, y0 + 8, 20, y1 - y0 - 26)
				cv.r(wx, fl - 14, wx + 20, fl - 10, PLANT, 0)
				for li in range(wx, wx + 20):
					cv.p(li, fl - 15 - int(cv.n2(float(li) * 4.0, 0.0) * 3.0 + 1.5), PLANT, li % 4)
				cv.r(wx, fl - 10, wx + 20, fl - 9, WOOD, 0)
				wx += 26
		"observatory":
			window(cv, x0 + 8, y0 + 6, mw - 16, 22)
		"brig":
			brig(cv, x0, y0, x1, fl)
		"cabins":
			cabins(cv, x0, y0, x1, fl)
		"armory":
			armory(cv, x0, y0, x1, fl)
		"galley":
			galley(cv, x0, y0, x1, fl)
	if cv.dead and role != "nest" and role != "vault":
		debris(cv, x0, x1, fl)
		if cv.chance(0.6):
			cables(cv, x0 + cv.ri(4, 20), x1 - cv.ri(4, 20), y0 + 4, 8.0)

# ================================================================== levels ===
# (27 Nov; user: "can we make the derelict space staions feel linke they are not just squares and are much larger.
# like whole levels by themselves complete with hallways doors you cant see through destroyed rooms"; "there are
# curently no hallways, doors, and decorative rooms, sleeping areas, mess halls, brig, crew quarters, so on".)
# A level is four or five times the old halls' cells, so its walls are laid by blitting small pattern tiles into
# images (`wall_bulk`, native and quick) and only the details are put cell by cell (`wall_detail`).

static var _tiles := {}

## a wall style's pattern at (ri, rj) from its anchor: zone 0 the upper panels (from the room's corner), zone 1 the
## wainscot (from its top row): [code, variant] (the same patterns `wall` draws cell by cell)
static func _wall_px(style: String, zone: int, ri: int, rj: int) -> Array:
	var c := PLATE
	var v := 0
	if zone == 1:
		match style:
			"wood":
				return [WOOD_D, 1 if ri % 6 == 0 else (0 if ri % 6 < 3 else 2)]
			"tile":
				c = TRIM_T
				v = 0 if (ri / 4 + rj / 4) % 2 == 0 else 2
				if ri % 4 == 0 or rj % 4 == 0:
					c = GROUT
				return [c, v]
			"grate":
				return [METAL_D, 1 if (ri % 3 == 0 or rj % 3 == 0) else 0]
			"lux":
				return [CARPET_B, (ri / 2 + rj) % 2]
			_:
				c = int({"hex": PLATE_D, "rib": METAL_D, "steel": PLATE_D}.get(style, PLATE_D))
				v = 0 if (ri / 16) % 2 == 0 else 2
				if ri % 16 == 0:
					c = SEAM
				return [c, v]
	match style:
		"plate", "lux", "steel":
			c = STEEL if style == "steel" else PLATE
			v = 0 if ((ri / 20) + (rj / 12)) % 2 == 0 else 2
			if ri % 20 == 0 or rj % 12 == 0:
				c = SEAM
			elif (ri % 20 == 2 or ri % 20 == 18) and rj % 12 == 2:
				c = RIVET
		"rib":
			c = PLATE_D
			v = 0 if (rj / 6) % 2 == 0 else 1
			if ri % 14 == 0 or ri % 14 == 1:
				c = METAL_D
				v = 2 if ri % 14 == 0 else 3
		"tile":
			c = TILE
			v = 0 if ((ri / 5) + (rj / 5)) % 2 == 0 else 1
			if ri % 5 == 0 or rj % 5 == 0:
				c = GROUT
		"wood":
			c = WOOD
			v = (ri / 4) % 3
			if ri % 4 == 0:
				c = WOOD_D
				v = 1
		"hex":
			c = HEX
			var off := 4 if (rj / 5) % 2 == 0 else 0
			v = ((ri + off) / 8) % 2
			if (ri + off) % 8 == 0 or rj % 5 == 0:
				c = SEAM
		"grate":
			c = GRATE
			v = 2 if (ri % 4 == 0 or rj % 4 == 0) else 0
			if ri % 4 == 0 and rj % 4 == 0:
				c = METAL_D
	return [c, v]

## a style's tile for a zone: [code image, variant image] (R8), a whole number of its periods, at least 40 x 24
static func _tile(style: String, zone: int) -> Array:
	var key := "%s%d" % [style, zone]
	if _tiles.has(key):
		return _tiles[key]
	var per: Vector2i = {"plate": Vector2i(40, 24), "lux": Vector2i(40, 24), "steel": Vector2i(40, 24), "rib": Vector2i(14, 12),
		"tile": Vector2i(10, 10), "wood": Vector2i(12, 1), "hex": Vector2i(16, 10), "grate": Vector2i(4, 4)}.get(style, Vector2i(40, 24))
	if zone == 1:
		per = {"wood": Vector2i(6, 1), "tile": Vector2i(8, 8), "grate": Vector2i(3, 3), "lux": Vector2i(2, 2)}.get(style, Vector2i(32, 1))
	var tw: int = per.x * int(ceil(40.0 / float(per.x)))
	var th: int = per.y * int(ceil(24.0 / float(per.y)))
	var ic := Image.create(tw, th, false, Image.FORMAT_R8)
	var iv := Image.create(tw, th, false, Image.FORMAT_R8)
	for j in th:
		for i in tw:
			var px: Array = _wall_px(style, zone, i, j)
			ic.set_pixel(i, j, Color(float(px[0]) / 255.0, 0, 0))
			iv.set_pixel(i, j, Color(float(px[1]) / 255.0, 0, 0))
	_tiles[key] = [ic, iv]
	return _tiles[key]

static func r8(code: int) -> Color:
	return Color(float(code) / 255.0, 0.0, 0.0)

## fill a rectangle of the code and variant images with a tile, anchored at its top-left corner
static func _tile_fill(bi: Image, vi: Image, tl: Array, x0: int, y0: int, x1: int, y1: int) -> void:
	var ic: Image = tl[0]
	var iv: Image = tl[1]
	var tw := ic.get_width()
	var th := ic.get_height()
	var ty := y0
	while ty < y1:
		var hh := mini(th, y1 - ty)
		var tx := x0
		while tx < x1:
			var ww := mini(tw, x1 - tx)
			bi.blit_rect(ic, Rect2i(0, 0, ww, hh), Vector2i(tx, ty))
			vi.blit_rect(iv, Rect2i(0, 0, ww, hh), Vector2i(tx, ty))
			tx += tw
		ty += th

## a room's back wall laid in bulk (the panels, the trim line, the wainscot, the kick plate): images of codes and
## variants, R8, the station's size. The cornice, the light strip and a derelict's decay come after (`wall_detail`).
static func wall_bulk(bi: Image, vi: Image, x0: int, y0: int, x1: int, y1: int, style: String) -> void:
	if x1 <= x0 or y1 <= y0:
		return
	var wain := y1 - clampi((y1 - y0) / 3, 14, 40)
	var trim: int = {"wood": TRIM_G, "tile": CERAMIC, "hex": TRIM_T, "grate": HAZARD, "lux": TRIM_G, "steel": CHROME, "rib": PIPE}.get(style, METAL)
	_tile_fill(bi, vi, _tile(style, 0), x0, y0, x1, wain - 1)
	bi.fill_rect(Rect2i(x0, wain - 1, x1 - x0, 1), r8(trim))
	vi.fill_rect(Rect2i(x0, wain - 1, x1 - x0, 1), r8(1))
	_tile_fill(bi, vi, _tile(style, 1), x0, wain, x1, y1 - 3)
	var kick := METAL_D if style != "wood" else WOOD_D
	bi.fill_rect(Rect2i(x0, y1 - 3, x1 - x0, 3), r8(kick))
	vi.fill_rect(Rect2i(x0, y1 - 3, x1 - x0, 1), r8(2))
	vi.fill_rect(Rect2i(x0, y1 - 2, x1 - x0, 2), r8(0))

## a wall's details, cell by cell: the cornice under the roof (where it comes down to: `drop`), the light strip under
## it (dead or red in a derelict's broken rooms), and a derelict's decay in drifts and streaks
static func wall_detail(cv: Cv, x0: int, y0: int, x1: int, y1: int, style: String, drop := PackedInt32Array()) -> void:
	for i in range(x0, x1):
		var dj := y0 + (int(drop[i - x0]) if i - x0 < drop.size() else 0)
		cv.p(i, dj, METAL_D, 1)
		cv.p(i, dj + 1, METAL_D, 3)
	for i2 in range(x0 + 4, x1 - 4):
		if (i2 - x0) % 18 < 10:
			var lc := LAMP_W if style != "wood" and style != "lux" else LAMP_WARM
			if cv.dead:
				lc = LAMP_R if (i2 - x0) / 18 % 4 == 1 else LAMP_DEAD
			cv.p(i2, y0 + 2 + (int(drop[i2 - x0]) if i2 - x0 < drop.size() else 0), lc, 0)
	if cv.dead:
		decay_fast(cv, x0, y0, x1, y1)

## a derelict's decay over a big wall, quickly: drifts of grime and scorching here and there, rust streaking down
## from the cornice, a few panels torn away with the cables behind
static func decay_fast(cv: Cv, x0: int, y0: int, x1: int, y1: int) -> void:
	var area := (x1 - x0) * (y1 - y0)
	for b in maxi(2, area / 1400):
		var cx := cv.ri(x0, x1 - 1)
		var cy := cv.ri(y0, y1 - 1)
		var r := cv.ri(5, 16)
		for j in range(maxi(y0, cy - r), mini(y1, cy + r)):
			for i in range(maxi(x0, cx - r), mini(x1, cx + r)):
				var d := Vector2(i - cx, (j - cy) * 1.3).length() / float(r)
				var n := cv.n2(float(i) * 1.6, float(j) * 1.6)
				if d + n * 0.45 < 0.75:
					cv.bg[j * cv.w + i] = SCORCH if d < 0.35 and n > 0.0 else GRIME
					cv.bgv[j * cv.w + i] = (i + j) % 4
	for s in maxi(2, (x1 - x0) / 24):
		var sx := cv.ri(x0 + 2, x1 - 3)
		var ln := cv.ri(6, mini(46, y1 - y0 - 6))
		for q in ln:
			cv.p(sx + (1 if q % 9 > 6 else 0), y0 + 3 + q, RUST, (sx + q) % 4)
	for k in cv.ri(1, 2 + (x1 - x0) / 120):
		var px := cv.ri(x0 + 6, maxi(x0 + 7, x1 - 18))
		var py := cv.ri(y0 + 5, maxi(y0 + 6, y1 - 26))
		cv.r(px, py, px + 12, py + 10, BLACK, 0)
		for q2 in 4:
			var col: int = [CABLE, CABLE_R, CABLE_Y, CABLE][q2]
			for jj in range(py, py + 10):
				cv.p(px + 2 + q2 * 3 + (1 if jj % 5 == 2 else 0), jj, col, jj % 4)

## claw marks scored across a wall (a derelict: the hive came through here)
static func claws(cv: Cv, x: int, y: int) -> void:
	for q in 4:
		for t in 14:
			cv.p(x + q * 3 + t / 2, y + t, SCORCH, 2 if t % 4 == 0 else 3)

## a smear of the hive's goo across the floor and up the wall
static func smear(cv: Cv, x0: int, fl: int, ln: int) -> void:
	for i in ln:
		cv.p(x0 + i, fl - 1, GOO, i % 4)
		if (i * 7) % 5 == 0:
			for q in cv.ri(1, 6):
				cv.p(x0 + i, fl - 1 - q, GOO, (i + q) % 4)

## a catwalk's railing over a one-way floor at row y, from x0 to x1: posts and a rail in the back layer
static func railing(cv: Cv, x0: int, x1: int, y: int) -> void:
	for i in range(x0, x1):
		cv.p(i, y - 9, METAL, 3)
		cv.p(i, y - 5, METAL_D, 1)
		if (i - x0) % 8 == 0:
			for j in range(y - 9, y):
				cv.p(i, j, METAL_D, 0)
	for i2 in range(x0, x1):
		cv.p(i2, y + 1, METAL_D, 2)
		if (i2 - x0) % 12 == 6:
			for j2 in range(y + 2, y + 5):
				cv.p(i2, j2, METAL_D, 0)

## a door's panel (`w` across, `h` high): plates with a seam down its middle, a window slot, hazard stripes at its
## foot, a light over it (a derelict's grimed and its light red)
static func door_image(w: int, h: int, dead: bool) -> Image:
	var im := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := color(STEEL if not dead else PLATE_D, 0 if (y / 6) % 2 == 0 else 2)
			if x == 0 or x == w - 1:
				c = color(METAL_D, 1)
			elif x == w / 2:
				c = color(METAL_D, 3)
			if y >= h - 5:
				c = color(HAZARD, 0) if ((x + y) / 2) % 2 == 0 else color(BLACK, 0)
			if y >= 8 and y < 18 and x > 1 and x < w - 2 and x != w / 2:
				c = color(WINDOW, 3) if not dead else color(SCREEN_DEAD, 0)
				c.a = 1.0
			if y < 3 and x > 1 and x < w - 2:
				c = color(LED_G if not dead else LED_R, 0)
			if dead and (x * 7 + y * 3) % 11 == 0:
				c = c.darkened(0.3)
			im.set_pixel(x, y, c)
	return im

## a corridor dressed along its length (x0..x1, its floor fl): a grated floor strip, pipes and conduits along the
## upper wall, signs pointing on, consoles, vents, fire boxes, benches in its bays; a derelict's lit only by red
## emergency lamps, goo smeared along it, claws on the walls, a body bag or two
static func corridor(cv: Cv, x0: int, y0: int, x1: int, fl: int, prof: PackedInt32Array) -> void:
	var ln := x1 - x0
	for i in range(x0, x1):
		cv.p(i, fl - 1, GRATE, 1 if (i - x0) % 3 == 0 else 0)
	var py := fl - 40
	pipes(cv, x0, x1, py, 2)
	var x := x0 + cv.ri(14, 30)
	while x < x1 - 20:
		var ch: int = prof[x - x0] if x - x0 < prof.size() else 64
		match cv.ri(0, 6):
			0:
				signboard(cv, x, fl - ch + 8, 16, LED_G if cv.chance(0.5) else LED_Y)
			1:
				vent(cv, x, fl - 30)
			2:
				cv.r(x, fl - 26, x + 6, fl - 16, RED if not cv.dead else RUST, 0)       # (a fire box)
				cv.p(x + 2, fl - 22, CHROME, 0)
			3:
				screen(cv, x, fl - 28, 10, 6)
			4:
				if ch >= 90:
					window(cv, x, fl - ch + 10, 30, 18)
					x += 24
			5:
				poster(cv, x, fl - 30, 6, 9)
			_:
				for q in range(fl - 34, fl - 2, 4):
					cv.p(x, q, PIPE_CU, 2)
		x += cv.ri(26, 52)
	if cv.dead:
		for k in cv.ri(1, 3):
			claws(cv, cv.ri(x0 + 4, maxi(x0 + 5, x1 - 20)), fl - cv.ri(20, 40))
		if cv.chance(0.7):
			smear(cv, cv.ri(x0, maxi(x0 + 1, x1 - 40)), fl, cv.ri(14, 38))
		for q2 in cv.ri(0, 2):
			var bx := cv.ri(x0 + 10, maxi(x0 + 11, x1 - 24))
			cv.r(bx, fl - 4, bx + 14, fl - 1, FAB_G, 1)          # (a body bag)
			cv.r(bx + 1, fl - 5, bx + 13, fl - 4, FAB_G, 3)
		if cv.chance(0.6):
			cables(cv, x0 + cv.ri(4, 20), x0 + mini(ln - 4, cv.ri(60, 140)), py - 4, 10.0)
		debris(cv, x0, x1, fl)

## a brig: barred cells along the floor (a cot and a pan in each), a guard's desk by the door
static func brig(cv: Cv, x0: int, y0: int, x1: int, fl: int) -> void:
	var cw := 38
	var cx := x0 + 30
	desk(cv, x0 + 6, fl)
	signboard(cv, x0 + 4, fl - 40, 20, LED_R)
	while cx + cw < x1 - 4:
		cv.r(cx, fl - 36, cx + cw, fl, STEEL, 2)
		cv.r(cx + 4, fl - 7, cx + 22, fl - 5, METAL, 1)          # (a cot)
		cv.r(cx + 5, fl - 9, cx + 21, fl - 7, FAB_G if not cv.dead else GRIME, 0)
		cv.r(cx + 28, fl - 5, cx + 33, fl, CERAMIC, 0)
		cv.r(cx, fl - 37, cx + cw, fl - 35, METAL_D, 0)
		for b in range(cx, cx + cw + 1, 3):
			if cv.dead and cv.chance(0.15):
				for q in 12:
					cv.p(b + q / 4, fl - 1 - q / 3, METAL, 0)       # (a bar torn out, lying bent)
				continue
			for j in range(fl - 35, fl):
				cv.p(b, j, METAL, 3 if j % 9 == 0 else 0)
		if cv.dead and cv.chance(0.5):
			claws(cv, cx + 8, fl - 30)
		cx += cw + 6

## cabins: a row of small private rooms, each a bed, a nightstand with a lamp, a wardrobe and a porthole
static func cabins(cv: Cv, x0: int, y0: int, x1: int, fl: int) -> void:
	var cw := 46
	var cx := x0 + 4
	while cx + cw <= x1 - 2:
		for j in range(fl - 46, fl):
			cv.p(cx, j, METAL_D, 2)
		cv.r(cx, fl - 47, cx + cw, fl - 46, METAL_D, 0)
		cv.r(cx + 3, fl - 6, cx + 23, fl - 4, WOOD_D, 0)
		var fab: int = [FAB_B, FAB_R, FAB_G][cv.ri(0, 2)]
		if not (cv.dead and cv.chance(0.5)):
			cv.r(cx + 4, fl - 9, cx + 22, fl - 6, fab, 0)
			cv.r(cx + 4, fl - 10, cx + 8, fl - 7, PILLOW, 0)
		cv.r(cx + 25, fl - 7, cx + 31, fl, WOOD, 1)
		cv.r(cx + 26, fl - 10, cx + 29, fl - 7, LAMP_WARM if not cv.dead else LAMP_DEAD, 0)
		locker(cv, cx + 35, fl)
		window(cv, cx + 10, fl - 34, 10, 8)
		if cv.lived and cv.chance(0.6):
			poster(cv, cx + 24, fl - 30, 5, 7)
		if cv.dead and cv.chance(0.4):
			smear(cv, cx + 4, fl, 18)
		cx += cw

## an armory: racks of rifles on the wall, lockers, ammunition crates with hazard stripes, a red alarm lamp
static func armory(cv: Cv, x0: int, y0: int, x1: int, fl: int) -> void:
	var rx := x0 + 6
	while rx + 30 < x1 - 30:
		cv.r(rx, fl - 46, rx + 30, fl - 18, METAL_D, 0)
		for g in 4:
			var gy := fl - 42 + g * 6
			if cv.dead and cv.chance(0.4):
				continue
			cv.r(rx + 3, gy, rx + 24, gy + 2, METAL, 0)
			cv.r(rx + 20, gy, rx + 27, gy + 3, WOOD_D, 0)
			cv.p(rx + 12, gy + 2, METAL, 1)
		rx += 36
	locker(cv, x1 - 26, fl)
	locker(cv, x1 - 18, fl)
	for q in 3:
		var bx := x0 + 10 + q * 14
		cv.r(bx, fl - 7, bx + 11, fl, HAZARD, 0)
		cv.r(bx, fl - 7, bx + 11, fl - 6, METAL_D, 0)
	cv.r(x1 - 12, fl - 60, x1 - 8, fl - 56, LAMP_R, 0)

## a galley: counters and ovens along the floor, pots hung from a rail, shelves of stores, a sink and a cold store
static func galley(cv: Cv, x0: int, y0: int, x1: int, fl: int) -> void:
	counter(cv, x0 + 4, fl, mini(70, x1 - x0 - 50))
	for q in 2:
		var ox := x0 + 8 + q * 22
		cv.r(ox, fl - 30, ox + 16, fl - 14, CHROME, 2)
		cv.r(ox + 2, fl - 27, ox + 14, fl - 19, SCREEN_A if not cv.dead else BLACK, 0)
	cv.r(x0 + 4, fl - 44, x1 - 34, fl - 43, METAL, 1)
	for px in range(x0 + 10, x1 - 40, 9):
		for j in range(fl - 43, fl - 39):
			cv.p(px, j, METAL_D, 0)
		cv.r(px - 2, fl - 39, px + 3, fl - 35, PIPE_CU if px % 2 == 0 else METAL, 2)
	shelf(cv, x0 + 6, fl - 54, 40)
	for q2 in range(x0 + 7, x0 + 45, 3):
		cv.r(q2, fl - 57, q2 + 2, fl - 54, FOOD if not cv.dead else GRIME, cv.ri(0, 3))
	cv.r(x1 - 30, fl - 34, x1 - 14, fl, CHROME, 0)
	cv.r(x1 - 29, fl - 33, x1 - 15, fl - 18, CHROME, 3)
	cv.r(x1 - 46, fl - 12, x1 - 34, fl - 9, CERAMIC, 0)
	cv.p(x1 - 40, fl - 13, WATER if not cv.dead else GRIME, 0)
