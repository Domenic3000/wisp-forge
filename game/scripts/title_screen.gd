extends Control
## The title screen: a fully animated pixel-art scene (drawn by a shader at low resolution so
## every pixel is chunky), the mage on a floating rock above Verdance with his wisp, a pixel-art
## logo with a shimmer, and the menu.

var ui                       # the UI layer (for buttons and styles)
var game
var box: VBoxContainer       # the menu (New Journey, Continue, Settings, Quit)
var _col: VBoxContainer
var _sub: Label
var continue_btn: Button
var _bg: ColorRect
var _mat: ShaderMaterial
var _mage: TextureRect
var _fx: Control             # the wisp, the staff's glow and the logo, drawn each frame
var _px := 4.0               # screen pixels per scene pixel
var _t := 0.0

const SCENE := """
shader_type canvas_item;
uniform float px_size = 4.0;
uniform vec2 view_size = vec2(1280.0, 720.0);
uniform float t = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.0; a *= 0.5; } return v; }
// the cliff the mage stands on (its top edge, in scene pixels); flat right under the mage
float rockTop(float x, float W, float H) {
	float u = x / W;
	float base = H * 0.70 + pow(max(0.0, u - 0.08), 2.0) * H * 1.6 - (u < 0.08 ? (0.08 - u) * H * 0.6 : 0.0);
	float rough = (noise(vec2(x / 5.0, 7.0)) - 0.5) * 4.0 + (noise(vec2(x / 17.0, 3.0)) - 0.5) * 5.0;
	return floor(base + rough * smoothstep(0.02, 0.06, abs(u - 0.24)));
}
float rockBottom(float x, float W, float H) {
	return H * 1.05 - pow(abs(x / W - 0.18) * 2.2, 1.5) * H * 0.5 + (noise(vec2(x / 4.0, 1.0)) - 0.5) * 6.0;
}
bool isRock(vec2 p, float W, float H) {
	return p.x < W * 0.5 && p.y >= rockTop(p.x, W, H) && p.y < rockBottom(p.x, W, H);
}
// a shaded pixel pine. Returns colour and coverage (a = 0 where it doesn't cover p).
// Tiers of boughs, each lit on top and shadowed underneath, with ragged drooping tips, a rim of
// cool planet light on the right, a trunk showing between the lower tiers and a sway in the wind.
vec4 pine(vec2 p, float tx, float ty, float hgt, float seed, float fade) {
	float dyt = ty - p.y;
	if (dyt < 0.0 || dyt > hgt + 2.0) return vec4(0.0);
	float sway = floor(sin(t * 0.9 + seed) * (dyt / hgt) * (dyt / hgt) * 1.6 + 0.5);
	float dx = p.x - tx - sway;
	float trunkW = max(1.0, floor(hgt * 0.035));
	float base = max(3.0, floor(hgt * 0.12));
	float P = max(5.0, floor(hgt * 0.16));
	vec3 dark = vec3(0.02, 0.07, 0.08), mid = vec3(0.04, 0.16, 0.15), lit = vec3(0.10, 0.29, 0.23), tip = vec3(0.22, 0.45, 0.32);
	if (dyt >= base) {
		float tp = fract((dyt - base) / P);                 // 0 at the bottom of a tier, 1 at its top
		float taper = (hgt + 1.0 - dyt) / hgt;
		float w = taper * hgt * 0.30 * (0.40 + 0.60 * (1.0 - tp)) + 0.5;
		w += (hash(vec2(floor(dyt), seed)) - 0.5) * 1.4 * taper;  // ragged needles
		if (abs(dx) < w) {
			float e = abs(dx) / max(w, 1.0);
			// four tones: the tier above shades the top of each tier, the drooping tips catch the light
			float li = 0.55 - tp * 0.55 + (dx < 0.0 ? 0.2 : -0.05) + e * 0.25 + (hash(floor(p) + seed) - 0.5) * 0.3;
			if (tp > 0.78 && dyt < hgt - 2.0) li -= 0.45;
			vec3 c = li < 0.2 ? dark : (li < 0.5 ? mid : (li < 0.8 ? lit : tip));
			if (dx > 0.0 && w - abs(dx) < 1.0 && tp < 0.75) c = mix(c, vec3(0.32, 0.44, 0.64), 0.6);  // planet rim light
			c = mix(c, vec3(0.10, 0.08, 0.18), fade);
			return vec4(c, 1.0);
		}
	}
	if (abs(dx + 0.25) < trunkW && dyt < hgt * 0.8) {
		vec3 c = dx < 0.0 ? vec3(0.17, 0.10, 0.08) : vec3(0.26, 0.16, 0.11);
		return vec4(mix(c, vec3(0.10, 0.08, 0.18), fade), 1.0);
	}
	return vec4(0.0);
}
// a round broadleaf tree: a lumpy crown of three blobs with light from the upper left
vec4 broadleaf(vec2 p, float tx, float ty, float hgt, float seed) {
	float dyt = ty - p.y;
	float sway = floor(sin(t * 0.7 + seed) * 1.2 * clamp(dyt / hgt, 0.0, 1.0) + 0.5);
	vec2 q = vec2(p.x - tx - sway, dyt);
	float R = hgt * 0.42;
	vec2 c0 = vec2(0.0, hgt - R * 0.9), c1 = vec2(-R * 0.62, hgt - R * 1.25), c2 = vec2(R * 0.6, hgt - R * 1.15);
	float n = (noise(p / 2.5 + seed) - 0.5) * 0.25;
	float e0 = length((q - c0) / vec2(R, R * 0.85)), e1 = length((q - c1) / vec2(R * 0.7, R * 0.6)), e2 = length((q - c2) / vec2(R * 0.7, R * 0.6));
	float e = min(e0, min(e1, e2));
	if (e < 1.0 + n) {
		vec2 lc = q - (e == e0 ? c0 : (e == e1 ? c1 : c2));
		// clumps of leaves, each lit from the upper left, in four tones
		float clump = noise(p / 3.2 + seed * 3.0);
		float li = 0.5 - lc.x / R * 0.35 + lc.y / R * 0.45 + (clump - 0.5) * 0.9 - e * 0.25;
		li += (hash(floor(p) + seed) - 0.5) * 0.15;
		vec3 c = li < 0.15 ? vec3(0.07, 0.10, 0.06) : (li < 0.42 ? vec3(0.15, 0.24, 0.10) : (li < 0.68 ? vec3(0.28, 0.40, 0.15) : vec3(0.46, 0.57, 0.24)));
		return vec4(c, 1.0);
	}
	float tw = max(1.5, hgt * 0.05) + max(0.0, 3.0 - dyt) * 0.6;
	if (dyt >= 0.0 && dyt < hgt - R && abs(q.x) < tw) return vec4(q.x < 0.0 ? vec3(0.16, 0.10, 0.08) : vec3(0.27, 0.17, 0.11), 1.0);
	// a branch to each side blob
	if (dyt > 0.0 && (abs(q.y - (hgt - R * 1.4) - (q.x) * 0.6) < 0.8 && q.x > 0.0 && q.x < R * 0.5)) return vec4(0.24, 0.15, 0.10, 1.0);
	return vec4(0.0);
}

void fragment() {
	vec2 res = floor(view_size / px_size);
	vec2 p = floor(UV * res);
	float W = res.x;
	float H = res.y;
	// sky: deep indigo above, a violet-rose glow toward the planet
	float gy = p.y / H;
	vec3 col = mix(vec3(0.03, 0.025, 0.09), vec3(0.20, 0.10, 0.30), smoothstep(0.0, 0.9, gy));
	// nebula
	float nb = fbm(p / 55.0 + vec2(t * 0.004, 0.0));
	col += vec3(0.30, 0.10, 0.45) * smoothstep(0.55, 0.85, nb) * 0.45;
	col += vec3(0.05, 0.25, 0.35) * smoothstep(0.62, 0.9, fbm(p / 38.0 + 11.0)) * 0.35;
	// stars, twinkling
	float hs = hash(p);
	if (hs > 0.988) {
		float tw = 0.45 + 0.55 * sin(t * (1.5 + hs * 3.0) + hs * 60.0);
		col += vec3(0.9, 0.9, 1.0) * tw * (hs > 0.997 ? 1.0 : 0.6);
	}
	// a shooting star now and then
	float ph = fract(t / 9.0);
	if (ph < 0.12) {
		vec2 a0 = vec2(W * 0.95, H * 0.05) + vec2(-W * 0.9, H * 0.35) * (ph / 0.12);
		vec2 dd = p - a0;
		vec2 dir = normalize(vec2(-W * 0.9, H * 0.35));
		float along = dot(dd, -dir);
		float side = abs(dd.x * dir.y - dd.y * dir.x);
		if (along > 0.0 && along < 14.0 && side < 0.8) col += vec3(1.0, 0.95, 0.8) * (1.0 - along / 14.0);
	}
	// a little moon
	vec2 mc = vec2(W * 0.84, H * 0.18);
	float mr = H * 0.065;
	float md = length(p - mc) / mr;
	if (md < 1.0) {
		vec3 n = vec3((p - mc) / mr, sqrt(1.0 - md * md));
		float li = clamp(dot(n, normalize(vec3(-0.7, -0.4, 0.6))), 0.0, 1.0);
		float cr = fbm((p - mc) / 3.0 + 4.0);
		col = vec3(0.75, 0.72, 0.85) * (0.12 + 0.95 * li) * (cr > 0.6 ? 0.75 : 1.0);
	}
	// Verdance, turning slowly
	vec2 pc = vec2(W * 0.56, H * 1.18);
	float pr = H * 0.78;
	vec2 d = (p - pc) / pr;
	float l = length(d);
	if (l < 1.0) {
		vec3 n = vec3(d.x, d.y, sqrt(1.0 - l * l));
		float tl = 0.5;
		vec3 q = vec3(n.x, n.y * cos(tl) + n.z * sin(tl), -n.y * sin(tl) + n.z * cos(tl));
		float ang = t * 0.025;
		float x2 = q.x * cos(ang) + q.z * sin(ang);
		float z2 = -q.x * sin(ang) + q.z * cos(ang);
		float lon = atan(x2, z2);
		vec2 tc = vec2(lon * 1.6, q.y * 2.4);
		float h = fbm(tc * 1.3 + 3.0);
		float m = fbm(tc * 2.6 + 9.0);
		float lat = abs(q.y);
		vec3 c;
		if (h < 0.5) c = mix(vec3(0.05, 0.13, 0.36), vec3(0.12, 0.30, 0.56), smoothstep(0.3, 0.5, h));
		else if (h < 0.515) c = vec3(0.80, 0.72, 0.48);
		else if (h > 0.72) c = h > 0.77 ? vec3(0.90, 0.92, 0.97) : vec3(0.44, 0.40, 0.44);
		else if (lat < 0.35 && m > 0.56) c = vec3(0.80, 0.66, 0.38);
		else if (lat > 0.6) c = m > 0.5 ? vec3(0.30, 0.40, 0.32) : vec3(0.22, 0.34, 0.26);
		else c = m < 0.42 ? vec3(0.14, 0.34, 0.19) : vec3(0.24, 0.48, 0.23);
		if (lat > 0.84 + (fbm(tc * 4.0) - 0.5) * 0.16) c = vec3(0.90, 0.93, 0.98);
		float cl = fbm(vec2(lon * 2.0 + t * 0.012, q.y * 3.0) * 2.2 + 1.0);
		if (cl > 0.67) c = mix(c, vec3(0.96), 0.8);
		else if (cl > 0.63) c = mix(c, vec3(0.9), 0.35);
		float li = clamp(dot(n, normalize(vec3(-0.65, -0.55, 0.55))), 0.0, 1.0);
		c *= 0.1 + 1.0 * li;
		c += vec3(0.25, 0.45, 0.9) * pow(1.0 - n.z, 3.0) * 0.8;   // atmosphere at the rim
		col = c;
	} else if (l < 1.06) {
		col += vec3(0.25, 0.45, 0.95) * (1.06 - l) / 0.06 * 0.6;    // its glow
	}
	// a sea of slow clouds below, lit lilac from above
	if (p.y > H * 0.83) {
		float cn = fbm(vec2(p.x / 40.0 + t * 0.018, p.y / 9.0));
		float edge = smoothstep(H * 0.83, H * 0.96, p.y);
		if (cn + edge * 0.35 > 0.62) {
			float shade = fbm(vec2(p.x / 40.0 + t * 0.018, (p.y - 2.0) / 9.0));
			col = mix(vec3(0.42, 0.34, 0.58), vec3(0.72, 0.62, 0.86), clamp((cn - shade) * 6.0 + 0.5, 0.0, 1.0));
			col *= 0.75 + 0.25 * (1.0 - edge);
		}
	}
	// wisps drifting up
	for (int i = 0; i < 22; i++) {
		float fi = float(i);
		float h1 = hash(vec2(fi, 1.0));
		float h2 = hash(vec2(fi, 2.0));
		float h3 = hash(vec2(fi, 3.0));
		float y = H * 1.1 - mod(t * (4.0 + 8.0 * h2) + h3 * H * 1.3, H * 1.3);
		float x = W * (0.03 + 0.94 * h1) + sin(t * 0.7 + fi) * 5.0;
		float dw = length(p - vec2(floor(x), floor(y)));
		float tw = 0.6 + 0.4 * sin(t * 3.0 + fi);
		if (dw < 0.5) col = mix(col, vec3(0.75, 0.95, 1.0), tw);
		else if (dw < 2.5) col += vec3(0.25, 0.55, 0.85) * (2.5 - dw) / 2.5 * 0.35 * tw;
	}
	// the cliff: layered stone, a grass lip with blades and flowers, a cool rim light from the planet
	if (isRock(p, W, H)) {
		float top = rockTop(p.x, W, H);
		float dpt = p.y - top;
		float band = fbm(vec2(p.x / 30.0, (p.y - top * 0.6) / 3.0));
		vec3 rock = mix(vec3(0.09, 0.07, 0.13), vec3(0.19, 0.15, 0.24), band);
		if (hash(floor(p / 3.0)) > 0.96) rock = mix(rock, vec3(0.30, 0.25, 0.36), 0.6);
		if (dpt > 8.0 && hash(floor(p / 2.0) + 5.0) > 0.996) rock = vec3(0.45, 0.85, 0.95) * (0.6 + 0.4 * sin(t * 2.0 + p.x));
		rock *= 0.65 + 0.45 * clamp(1.0 - dpt / (H * 0.35), 0.0, 1.0);
		if (!isRock(p + vec2(1.0, 0.0), W, H) || !isRock(p + vec2(0.0, 1.0), W, H)) rock = vec3(0.30, 0.34, 0.58);
		float gdep = 2.0 + floor(noise(vec2(p.x / 3.0, 2.0)) * 2.0);
		if (dpt < gdep) rock = dpt < 1.0 ? vec3(0.36, 0.64, 0.32) : vec3(0.20, 0.44, 0.24);
		else if (dpt < gdep + 1.0) rock = vec3(0.10, 0.24, 0.15);
		col = rock;
	} else if (p.x < W * 0.5) {
		float top = rockTop(p.x, W, H);
		float hb = hash(vec2(p.x, 9.0));
		if (p.y == top - 1.0 && hb > 0.55) col = vec3(0.28, 0.56, 0.28);
		if (p.y == top - 2.0 && hb > 0.9) col = vec3(0.28, 0.56, 0.28);
		if (p.y == top - 2.0 && hb > 0.965 && abs(p.x / W - 0.24) > 0.03) col = hb > 0.985 ? vec3(1.0, 0.82, 0.4) : vec3(0.95, 0.55, 0.75);
		// roots hanging under the cliff
		float bot = rockBottom(p.x, W, H);
		float hr = hash(vec2(floor(p.x), 4.0));
		if (rockTop(p.x, W, H) < bot - 3.0 && p.y >= bot && p.y < bot + hr * 10.0 && hr > 0.8) col = vec3(0.16, 0.12, 0.14);
	}
	// trees on the cliff: a broad tree framing the left edge, pines in front of it
	vec4 tr = broadleaf(p, floor(W * 0.025), rockTop(floor(W * 0.025), W, H) + 1.0, H * 0.46, 3.0);
	if (tr.a > 0.0) col = tr.rgb;
	tr = pine(p, floor(W * 0.115), rockTop(floor(W * 0.115), W, H) + 1.0, floor(H * 0.24), 7.0, 0.25);
	if (tr.a > 0.0) col = tr.rgb;
	tr = pine(p, floor(W * 0.075), rockTop(floor(W * 0.075), W, H) + 1.0, floor(H * 0.36), 1.0, 0.0);
	if (tr.a > 0.0) col = tr.rgb;
	tr = pine(p, floor(W * 0.16), rockTop(floor(W * 0.16), W, H) + 1.0, floor(H * 0.15), 5.0, 0.0);
	if (tr.a > 0.0) col = tr.rgb;
	// bushes at the trees' feet
	for (int bi = 0; bi < 4; bi++) {
		float bx = floor(W * (0.04 + 0.045 * float(bi)));
		float by = rockTop(bx, W, H);
		vec2 bq = (p - vec2(bx, by - 1.0)) / vec2(4.0 + float(bi % 2) * 2.0, 3.0);
		if (bq.y < 0.2 && length(bq) < 1.0 + (noise(p / 1.5) - 0.5) * 0.4) {
			col = mix(vec3(0.06, 0.16, 0.10), vec3(0.22, 0.44, 0.22), clamp(-bq.y - bq.x * 0.4, 0.0, 1.0));
			if (hash(p + 2.0) > 0.93) col = vec3(0.95, 0.60, 0.75);
		}
	}
	// soft vignette and a gentle colour step (pixel-art palette feel)
	vec2 uv = UV - 0.5;
	col *= 1.0 - 0.45 * pow(length(uv) * 1.25, 2.2);
	col = floor(col * 28.0 + 0.5) / 28.0;
	COLOR = vec4(col, 1.0);
}
"""

# a chunky 5 x 7 pixel font for the logo
const GLYPHS := {
	"W": ["X...X", "X...X", "X...X", "X.X.X", "X.X.X", "XX.XX", "X...X"],
	"I": ["XXX", ".X.", ".X.", ".X.", ".X.", ".X.", "XXX"],
	"S": [".XXXX", "X....", "X....", ".XXX.", "....X", "....X", "XXXX."],
	"P": ["XXXX.", "X...X", "X...X", "XXXX.", "X....", "X....", "X...."],
	"F": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "X...."],
	"O": [".XXX.", "X...X", "X...X", "X...X", "X...X", "X...X", ".XXX."],
	"R": ["XXXX.", "X...X", "X...X", "XXXX.", "X.X..", "X..X.", "X...X"],
	"G": [".XXXX", "X....", "X....", "X..XX", "X...X", "X...X", ".XXX."],
	"E": ["XXXXX", "X....", "X....", "XXXX.", "X....", "X....", "XXXXX"],
	" ": ["...", "...", "...", "...", "...", "...", "..."],
}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SCENE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_bg.material = _mat
	add_child(_bg)
	_mage = TextureRect.new()
	_mage.texture = Defs.sprite_texture("mage_cast")
	_mage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mage.stretch_mode = TextureRect.STRETCH_SCALE
	_mage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mage)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	# the menu, under the logo
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	_col = col
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 150)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var sub: Label = ui._label("A mage. A wisp. A round planet made of every last grain.", 17, Color(0.86, 0.80, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.08))
	sub.add_theme_constant_override("outline_size", 5)
	col.add_child(sub)
	_sub = sub
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	col.add_child(gap)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(box)
	var nb: Button = ui._button("New Journey", true)
	nb.pressed.connect(func(): game.start_game(false))
	box.add_child(nb)
	continue_btn = ui._button("Continue", true)
	continue_btn.pressed.connect(func(): game.start_game(true))
	box.add_child(continue_btn)
	var sb: Button = ui._button("Settings", true)
	sb.pressed.connect(func(): ui.toggle_settings())
	box.add_child(sb)
	var qb: Button = ui._button("Quit", true)
	qb.pressed.connect(func(): game.quit_game())
	box.add_child(qb)
	var foot: Label = ui._label("Controls are in Settings (Esc while playing)   ·   Wisp Forge, early build", 12, Color(0.62, 0.6, 0.78))
	foot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	foot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position.y -= 14
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.08))
	foot.add_theme_constant_override("outline_size", 4)
	add_child(foot)

## Hides the menu (while a planet loads, the scene keeps playing behind the loading panel).
func set_menu_visible(on: bool) -> void:
	box.visible = on
	_sub.visible = on

## Replaces the menu with a message (used when the GPU simulation can't start).
func show_message(head: String, msg: String) -> void:
	box.visible = false
	var h: Label = ui._head(head, 24, Color(1, 0.62, 0.52))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(h)
	var m: Label = ui._label(msg, 12, Color.WHITE)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.autowrap_mode = TextServer.AUTOWRAP_WORD
	m.custom_minimum_size = Vector2(900, 0)
	_col.add_child(m)

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var vs := get_viewport_rect().size
	_px = maxf(2.0, floorf(vs.y / 170.0))
	_mat.set_shader_parameter("px_size", _px)
	_mat.set_shader_parameter("view_size", vs)
	_mat.set_shader_parameter("t", _t)
	# the mage stands on the rock (same curve as the shader), bobbing a touch as he channels
	var W := floorf(vs.x / _px)
	var H := floorf(vs.y / _px)
	var mx := W * 0.24
	var u := mx / W
	var top := floorf(H * 0.70 + pow(maxf(0.0, u - 0.08), 2.0) * H * 1.6)
	var ts := _mage.texture.get_size()
	_mage.size = ts * _px
	_mage.position = Vector2(floorf(mx - ts.x * 0.5) * _px, floorf(top - ts.y + 1.0) * _px)
	_fx.queue_redraw()

func _draw_fx() -> void:
	var px := _px
	var vs := get_viewport_rect().size
	# a spell glowing in the mage's outstretched hand, pulsing
	var hand := _mage.position + Vector2(16.5, 14.5) * px
	var pulse := 0.6 + 0.4 * sin(_t * 4.0)
	_fx.draw_circle(hand, px * (3.0 + pulse * 1.5), Color(1.0, 0.85, 0.4, 0.18))
	_fx.draw_rect(Rect2((hand / px).floor() * px, Vector2(px, px)), Color(1.0, 0.95, 0.7))
	# the wisp, circling him
	var c := _mage.position + Vector2(8, 6) * px
	var wp := c + Vector2(cos(_t * 1.3) * 16.0, sin(_t * 2.1) * 6.0 - 4.0) * px
	wp = (wp / px).floor() * px
	_fx.draw_circle(wp + Vector2(px, px) * 0.5, px * 3.0, Color(0.5, 0.85, 1.0, 0.22))
	_fx.draw_rect(Rect2(wp - Vector2(px, 0), Vector2(px * 3, px)), Color(0.55, 0.85, 1.0))
	_fx.draw_rect(Rect2(wp - Vector2(0, px), Vector2(px, px * 3)), Color(0.55, 0.85, 1.0))
	_fx.draw_rect(Rect2(wp, Vector2(px, px)), Color(0.96, 1.0, 1.0))
	# the logo: chunky gold letters with a dark outline, a violet drop shadow and a shimmer
	var text := "WISP FORGE"
	var s := maxf(6.0, floorf(vs.y / 75.0))
	var total := 0.0
	for ch in text:
		total += (GLYPHS[ch][0].length() + 1) * s
	var x0 := floorf((vs.x - total) * 0.5)
	var y0 := floorf(vs.y * 0.14)
	var shimmer := fmod(_t * 0.35, 1.6) - 0.3
	for pass_i in 3:
		var x := x0
		for ch in text:
			var g: Array = GLYPHS[ch]
			for r in g.size():
				var row: String = g[r]
				for k in row.length():
					if row[k] != "X":
						continue
					var cell := Rect2(x + k * s, y0 + r * s, s, s)
					if pass_i == 0:
						_fx.draw_rect(Rect2(cell.position + Vector2(s, s) * 0.6, cell.size), Color(0.30, 0.16, 0.55))
					elif pass_i == 1:
						_fx.draw_rect(cell.grow(s * 0.25), Color(0.10, 0.06, 0.16))
					else:
						var top_c := Color(1.0, 0.96, 0.72)
						var bot_c := Color(0.93, 0.58, 0.20)
						var c2 := top_c.lerp(bot_c, float(r) / 6.0)
						var sx := (cell.position.x - x0) / total
						var glow := clampf(1.0 - absf(sx - shimmer) * 8.0, 0.0, 1.0)
						_fx.draw_rect(cell, c2.lerp(Color(1, 1, 1), glow * 0.7))
			x += (g[0].length() + 1) * s
