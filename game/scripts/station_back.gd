## The background layer behind a station's or an outpost's halls (user, 27 Nov: "derelicts having their own background
## layer like an abandoned space station taking up the entire background layer so it really feels like your inside
## the space station and outposts"): the station goes on behind its rooms, in three layers that drift with you at
## their own depth (`cam` x 0.25, 0.45, 0.7): far walls of windows, decks and their railings, great bulkheads and
## trusses, pipes, hazed with distance. An outpost's is lit and busy (warm and cool windows, a tram running along a
## deck, signs); a derelict's is dark (most windows dead, a few flickering, red emergency lamps pulsing, sparks, dust
## adrift). Past the side the hangar or the dock opens on (`open_pt`, `open_dir`, in screen pixels) it's space.
## pocket.gd (an outpost's halls) and space.gd (a derelict station's) draw it on a full-screen rect: `apply` sets it.
extends RefCounted

## the scene itself, shared by the game's canvas shader and the offline preview (/home/claude/tools/back_preview.py)
const BODY := """
float bh(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float bn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(bh(i), bh(i + vec2(1.0, 0.0)), f.x), mix(bh(i + vec2(0.0, 1.0)), bh(i + vec2(1.0, 1.0)), f.x), f.y);
}
// one layer of the station: q in its own cells; returns colour (rgb) and how much of the layer is there (a)
vec4 layer(vec2 q, float depth, float seed, float dead, float tt) {
	float DY = 96.0;                       // deck to deck
	float DX = 150.0;                      // bulkhead to bulkhead
	vec2 cell = floor(vec2(q.x / DX, q.y / DY));
	vec2 f = vec2(q.x - cell.x * DX, q.y - cell.y * DY);
	float r = bh(cell + seed);
	float r2 = bh(cell + seed + 17.0);
	vec3 steel = mix(vec3(0.17, 0.2, 0.26), vec3(0.11, 0.105, 0.1), dead);
	vec3 col = vec3(0.0);
	float a = 0.0;
	// the far wall: rows of windows between the decks (each bay its own: offices, homes, dark stores)
	if (depth > 2.5) {
		float ww = 7.0 + floor(r * 3.0) * 2.0;
		float wx = mod(q.x, ww);
		float wy = mod(q.y, 12.0);
		vec2 wid = floor(vec2(q.x / ww, q.y / 12.0));
		col = steel * 0.7;
		a = 1.0;
		if (wx > 2.0 && wy > 3.0 && wy < 9.0 && f.y > 14.0 && f.y < DY - 8.0) {
			float on = bh(wid + seed * 3.1);
			float lit = step(mix(0.35 + r2 * 0.4, 0.94, dead), on);
			// (a derelict's few lights left flicker)
			lit *= mix(1.0, step(0.3, fract(sin(tt * 0.05 + on * 91.0) * 7.0)), dead);
			vec3 wc = mix(vec3(1.0, 0.78, 0.45), vec3(0.55, 0.8, 1.0), step(0.6, bh(wid + 7.0)));
			wc = mix(wc, vec3(0.6, 1.0, 0.7), step(0.93, bh(wid + 9.0)));
			wc = mix(wc, mix(vec3(0.3, 0.6, 0.55), vec3(0.9, 0.25, 0.18), step(0.5, bh(wid + 2.0))), dead);
			col = mix(steel * 0.4, wc * 0.75, lit);
		}
	}
	// decks: a slab (a derelict's broken through in places), its railing above, lamps under it
	float broken = dead * step(0.72, bh(vec2(floor(q.x / 38.0), cell.y + seed)));
	float slab = step(f.y, 6.0) * (1.0 - broken);
	float rail = step(abs(f.y - (DY - 7.0)), 0.6);
	float post = step(mod(q.x, 12.0), 1.0) * step(DY - 8.0, f.y);
	if (slab > 0.5) {
		col = steel * (f.y < 1.0 ? 1.6 : (f.y > 5.0 ? 0.7 : 1.0));
		a = 1.0;
		if (f.y > 4.0 && mod(q.x, 26.0) < 4.0) {
			// lamps under the deck: white, or a derelict's red emergency lamps, pulsing
			vec3 lc = mix(vec3(1.0, 0.95, 0.85), vec3(1.0, 0.2, 0.12) * (0.55 + 0.45 * sin(tt * 0.04 + cell.x)), dead);
			col = mix(col, lc, mix(0.8, step(0.5, bh(vec2(floor(q.x / 26.0), cell.y))) * 0.9, dead));
		}
		// a tram on an outpost's deck, running along it
		if (dead < 0.5 && f.y > 1.0 && f.y < 4.0) {
			float tp = mod(tt * (0.6 + r) + r * 900.0, DX * 6.0);
			float tx = mod(q.x, DX * 6.0);
			if (abs(tx - tp) < 10.0) col = mix(vec3(0.95, 0.85, 0.55), vec3(0.4, 0.75, 1.0), step(0.5, r));
		}
	} else if ((rail > 0.5 || post > 0.5) && depth < 2.5 && broken < 0.5) {
		col = steel * 1.1;
		a = 1.0;
		// planters along an outpost's railings
		if (dead < 0.5 && r2 > 0.5 && f.y > DY - 11.0 && f.y < DY - 7.0 && mod(q.x, 12.0) > 2.0) { col = vec3(0.16, 0.38, 0.18); }
	} else if (dead < 0.5 && r2 > 0.5 && depth < 2.5 && f.y > DY - 11.0 && f.y < DY - 7.0 && mod(q.x, 12.0) > 2.0 && bh(vec2(floor(q.x / 3.0), cell.y)) > 0.4) {
		col = vec3(0.18, 0.42, 0.2);
		a = 1.0;
	}
	// under a derelict's red lamp, the deck's underside glows a little
	if (dead > 0.5 && slab < 0.5 && f.y > 6.0 && f.y < 22.0 && depth < 2.5) {
		float lamp_on = step(0.5, bh(vec2(floor(q.x / 26.0), cell.y)));
		float dx2 = abs(mod(q.x, 26.0) - 2.0);
		float g = lamp_on * exp(-(f.y - 6.0) * 0.18) * exp(-dx2 * 0.12) * (0.55 + 0.45 * sin(tt * 0.04 + cell.x));
		col = mix(col, vec3(0.55, 0.08, 0.05), g * 0.5);
		a = max(a, g * 0.6);
	}
	// bulkheads: great columns, with a lit panel (or a sign on an outpost's), and trusses between some of them
	float bw = 7.0 + r * 5.0;
	float bx = abs(f.x - DX * 0.5);
	if (bx < bw && depth < 2.5) {
		col = steel * (bx < 1.0 ? 1.4 : (bx > bw - 1.5 ? 0.55 : 1.0));
		a = 1.0;
		if (bx < 3.0 && abs(f.y - DY * 0.5) < 8.0) {
			vec3 pc = mix(vec3(0.3, 0.8, 0.9), vec3(0.85, 0.15, 0.1), dead);
			float pulse = mix(1.0, 0.5 + 0.5 * sin(tt * 0.05 + r * 6.0), dead);
			col = mix(col, pc, 0.7 * pulse * step(mix(0.0, 0.5, dead), r));
		}
	} else if (dead < 0.5 && depth < 1.5 && r2 > 0.55 && abs(f.x - DX * 0.5 - bw - 14.0) < 12.0 && abs(f.y - 30.0) < 6.0) {
		// an outpost's sign: a glowing board with its letters
		vec3 sc = mix(vec3(1.0, 0.4, 0.7), vec3(0.3, 0.9, 1.0), step(0.75, r2));
		float letters = step(0.45, bh(floor(q / 2.0))) * step(abs(f.y - 30.0), 3.0) * step(abs(f.x - DX * 0.5 - bw - 14.0), 10.0);
		col = mix(sc * 0.35, sc, letters);
		a = 1.0;
	} else if (depth > 1.5 && depth < 2.5 && r > 0.45) {
		float u = f.x / DX;
		float v = f.y / DY;
		float d1 = abs(u - v);
		float d2 = abs(u - (1.0 - v));
		if ((d1 < 0.012 || d2 < 0.012) && f.y > 6.0) { col = steel * 0.9; a = 1.0; }
	}
	// pipes along the near layer's decks
	if (depth < 1.5 && f.y > 8.0 && f.y < 16.0 && mod(f.y, 4.0) < 2.0 && r > 0.3 && broken < 0.5) {
		col = mix(steel, vec3(0.45, 0.3, 0.2), step(12.0, f.y)) * 1.1;
		a = 1.0;
	}
	// a derelict's cables hanging down from the decks, and a few screens still on
	if (dead > 0.5 && depth < 2.5) {
		float cx = mod(q.x + r * 40.0, 37.0);
		float hang = 10.0 + 30.0 * bh(vec2(floor(q.x / 37.0), seed));
		if (cx < 1.0 && f.y > 6.0 && f.y < hang) { col = vec3(0.04); a = 1.0; }
		if (r2 > 0.8 && abs(f.x - 40.0) < 6.0 && abs(f.y - 40.0) < 4.0) {
			col = vec3(0.15, 0.45, 0.4) * (0.6 + 0.4 * step(0.5, fract(sin(tt * 0.11 + r) * 9.0)));
			a = 1.0;
		}
	}
	return vec4(col, a);
}
vec3 station_back(vec2 px, vec2 size, vec2 cam, float rot, float zoom, float tt, float dead, float hue, vec2 open_pt, vec2 open_dir, float has_open) {
	vec2 d = (px - size * 0.5) / max(zoom, 0.01);
	float cr = cos(-rot);
	float sr = sin(-rot);
	d = vec2(d.x * cr - d.y * sr, d.x * sr + d.y * cr);
	// the haze the station's air holds (deep blue-grey in an outpost, brown-black in a derelict)
	vec3 haze = mix(vec3(0.05, 0.07, 0.11), vec3(0.035, 0.028, 0.025), dead);
	vec3 col = haze;
	// far, middle, near (farther: smaller and slower)
	vec4 l3 = layer(cam * 0.25 + d * 1.7, 3.0, 11.0, dead, tt);
	col = mix(col, l3.rgb * 0.5 + haze * 0.5, l3.a);
	vec4 l2 = layer(cam * 0.45 + d * 1.3 + vec2(60.0, 40.0), 2.0, 23.0, dead, tt);
	col = mix(col, l2.rgb * 0.72 + haze * 0.28, l2.a);
	vec4 l1 = layer(cam * 0.7 + d * 1.06 + vec2(20.0, 70.0), 1.0, 37.0, dead, tt);
	col = mix(col, l1.rgb, l1.a);
	// the air: a soft glow from below in an outpost, dust adrift and the odd spark in a derelict
	vec2 sp = floor(px / 2.0);
	if (dead > 0.5) {
		float dust = bh(floor(px + vec2(tt * 0.13, tt * 0.05)));
		if (dust > 0.997) col += vec3(0.25, 0.22, 0.18);
		float spk = bh(floor(sp / 24.0) + floor(tt / 90.0));
		vec2 sc = fract(sp / 24.0);
		if (spk > 0.985 && length(sc - vec2(0.5)) < 0.08 + 0.04 * sin(tt * 0.9)) col += vec3(1.0, 0.75, 0.3);
		col *= 0.8 + 0.25 * bn(px / 140.0 + vec2(tt * 0.002, 0.0));
	} else {
		col += vec3(0.02, 0.03, 0.05) * (px.y / size.y);
		col *= 0.8;                        // (kept back: the rooms in front are what you're looking at)
	}
	// past the open side: space
	if (has_open > 0.5 && dot(px - open_pt, open_dir) > 0.0) {
		vec3 sky = vec3(0.008, 0.01, 0.03);
		if (bh(floor(px + cam * 0.02)) > 0.997) sky += vec3(0.8, 0.85, 1.0) * (0.5 + 0.5 * sin(tt * 0.04 + bh(floor(px) + 3.0) * 50.0));
		float neb = bn((px + cam * 0.02) / 120.0);
		sky += vec3(0.08, 0.05, 0.14) * smoothstep(0.55, 0.9, neb);
		col = sky;
	}
	return col;
}
"""

const SHADER_HEAD := """
shader_type canvas_item;
uniform vec2 u_size = vec2(480.0, 270.0);
uniform vec2 u_cam = vec2(0.0);
uniform float u_rot = 0.0;
uniform float u_zoom = 2.0;
uniform float u_t = 0.0;
uniform float u_dead = 0.0;
uniform float u_hue = 0.0;
uniform vec2 u_open_pt = vec2(0.0);
uniform vec2 u_open_dir = vec2(1.0, 0.0);
uniform float u_has_open = 0.0;
"""

const SHADER_TAIL := """
void fragment() {
	vec2 px = floor(UV * u_size);
	COLOR = vec4(station_back(px, u_size, u_cam, u_rot, u_zoom, u_t, u_dead, u_hue, u_open_pt, u_open_dir, u_has_open), 1.0);
}
"""

static func shader_code() -> String:
	return SHADER_HEAD + BODY + SHADER_TAIL

static func make_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = shader_code()
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat

## set it for this frame: the station body `st` (a wreck.gd), the screen's size in pixels, the world -> screen
## transform, how many pixels a cell is, the time, and whether it's a derelict's
static func apply(mat: ShaderMaterial, st, size: Vector2, xf: Transform2D, tt: float, dead: bool) -> void:
	# (the body's own frame on screen: where its cells' x axis points, and the screen centre in its cells)
	var bx: Vector2 = xf.basis_xform(st.to_world(Vector2(1, 0)) - st.to_world(Vector2(0, 0)))
	var zoom: float = bx.length()
	var rot: float = bx.angle()
	var centre_w: Vector2 = xf.affine_inverse() * (size * 0.5)
	var cam: Vector2 = st.to_body(centre_w) + st.com
	mat.set_shader_parameter("u_size", size)
	mat.set_shader_parameter("u_cam", cam)
	mat.set_shader_parameter("u_rot", rot)
	mat.set_shader_parameter("u_zoom", zoom)
	mat.set_shader_parameter("u_t", tt)
	mat.set_shader_parameter("u_dead", 1.0 if dead else 0.0)
	mat.set_shader_parameter("u_hue", fposmod(float(st.seed_ % 997) / 997.0, 1.0))
	# the side its hangar or dock opens on: past the outer face of that wall, space
	var side: int = int(st.hangar_side) if st.kind == "outpost" else int(st.dock_side)
	var md: Dictionary = st.mods[int(st.dock)]
	var edge_x: float = float(int(md["x0"]) - 4) if side < 0 else float(int(md["x1"]) + 4)      # (its wall, T thick)
	var e0: Vector2 = xf * st.to_world(Vector2(edge_x, float(int(md["y1"]))) - st.com)
	var e1: Vector2 = xf * st.to_world(Vector2(edge_x + float(side) * 10.0, float(int(md["y1"]))) - st.com)
	mat.set_shader_parameter("u_open_pt", e0)
	mat.set_shader_parameter("u_open_dir", (e1 - e0).normalized())
	mat.set_shader_parameter("u_has_open", 1.0)
