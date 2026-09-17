// Per-player recolouring of the original's sprites.
//
// Every actor sprite on the disc is authored in ONE colour — the ANI sequence
// names say so: "bomb regular green", "flame center green", "die green 5". The
// game recolours them per player. There are two ways to do it here and the
// shader carries both, because which one is available depends on the pack.
//
// ---------------------------------------------------------------------------
// THE EXACT PATH: the disc's own tables
// ---------------------------------------------------------------------------
// `0.RMP`-`9.RMP` are 256-entry palette remaps and `COLOR.PAL` is 768 bytes of
// palette plus a 32768-byte RGB555 -> index lookup. Together they ARE the
// original's recolour:
//
//      i      = lut[rgb555(pixel)]        the nearest palette entry
//      mapped = remap[player][i]          0 means "this index is not recoloured"
//      S      = palette[i]                what the disc thought the pixel was
//      T      = palette[mapped]           what it turns that into
//
// and then, deliberately, NOT `out = T`.
//
// WHY NOT. The `.ANI` art is not palettised: WALK.ANI uses 978 distinct
// colours and 24 of them are palette entries. So the lookup is a nearest-match
// QUANTISER — the original reduced its 15-bit art to 256 colours for an 8-bit
// display and remapped the indices afterwards. Writing T would reproduce that
// quantisation and throw away colour the port already has, for no gain anybody
// would call fidelity.
//
// So the tables decide the CHANGE and the pixel keeps its detail:
//
//      out = pixel * (T / S)
//
// multiplicative, because the remap is a hue-and-brightness shift along a ramp
// and a ratio preserves the ramp's shape; additive where a source channel is
// near zero and a ratio would explode.
//
// Measured by tools/remap.py, mean absolute per-channel difference over the
// 54,385 recoloured pixels of WALK.ANI:
//
//      player           heuristic vs disc     this vs disc
//      0  white                      11.6             10.8
//      1  grey                       20.4              5.1
//      2  red                         9.3              6.6
//      3  blue                       30.0              7.6
//      4  green                       7.6              7.5
//      6  cyan                       25.6              9.6
//
// and on the 17,551 of those pixels whose colour IS a palette entry — where
// the disc's transform is exactly defined — this sits 0.03 to 2.61 away, which
// is 6-bit rounding.
//
// ---------------------------------------------------------------------------
// THE FALLBACK: fpc_atomic's heuristic
// ---------------------------------------------------------------------------
// Used when the pack carries no tables, which is the case for any replacement
// art pack (docs/PLAN.md track B). It decomposes a green pixel into a neutral
// base plus a green tint and re-tints by the target colour:
//
//      n = (r + b) / 2 ; k = g - n ; out = n + k * target
//
// A pixel is only touched when green DOMINATES. That predicate is an
// approximation of the remapped block, and a good one: the two agree on 95.6%
// of actor pixels, and on SHADOW.ANI both leave 100% of pixels alone.
//
// docs/BUGS.md Q6 has the whole story.
shader_type canvas_item;
render_mode unshaded;

// The player colour to recolour to, 0..1, for the fallback path. Set per node
// from Const.player_colour_f().
uniform vec3 target_colour = vec3(0.0, 1.0, 0.0);
uniform bool tinted = true;

// The disc's tables. filter_nearest is not optional: every one of these is a
// lookup table whose texels are values, not samples, and interpolating between
// two palette indices produces a third index that means nothing.
uniform bool exact_remap = false;
uniform int player_slot = 0;
uniform sampler2D remap_palette : filter_nearest, repeat_disable;
uniform sampler2D remap_lut : filter_nearest, repeat_disable;
uniform sampler2D remap_table : filter_nearest, repeat_disable;

const float LUT_W = 256.0;
const float LUT_H = 128.0;
const float PAL_W = 256.0;
const float PLAYERS = 10.0;


// An 8-bit channel back to the top five bits the .ANI stored. tools/anifile.py
// expands 5 bits to 8 with (v << 3) | (v >> 2), so this is exact.
int five_bits(float c) {
	return int(floor(c * 255.0 + 0.5)) >> 3;
}


int table_byte(sampler2D tex, vec2 uv) {
	return int(floor(texture(tex, uv).r * 255.0 + 0.5));
}


vec3 palette_colour(int index) {
	return texture(remap_palette,
		vec2((float(index) + 0.5) / PAL_W, 0.5)).rgb;
}


void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	// Godot's shading language forbids `return` inside fragment(), so this is
	// a single nested if/else rather than a series of early exits.
	if (tex.a < 0.5) {
		// Alpha is 0 or 1 — a hard colour key, nothing to blend. Writing a
		// fully transparent pixel keeps the sprite edge as authored.
		COLOR = vec4(0.0);
	} else if (!tinted) {
		COLOR = vec4(tex.rgb, 1.0);
	} else if (exact_remap) {
		int idx15 = (five_bits(tex.r) << 10) | (five_bits(tex.g) << 5)
			| five_bits(tex.b);
		vec2 lut_uv = vec2(
			(float(idx15 & 255) + 0.5) / LUT_W,
			(float(idx15 >> 8) + 0.5) / LUT_H);
		int index = table_byte(remap_lut, lut_uv);
		int mapped = table_byte(remap_table, vec2(
			(float(index) + 0.5) / PAL_W,
			(float(player_slot) + 0.5) / PLAYERS));
		if (mapped == 0) {
			// Not one of the 73 recoloured indices. Exactly as authored — this
			// is what keeps the helmet, the visor and the outline put.
			COLOR = vec4(tex.rgb, 1.0);
		} else {
			vec3 src = palette_colour(index);
			vec3 dst = palette_colour(mapped);
			// Ratio where the source channel has something to scale, additive
			// where it is near zero.
			vec3 out_rgb = mix(
				tex.rgb + (dst - src),
				tex.rgb * (dst / max(src, vec3(1.0 / 255.0))),
				step(vec3(8.0 / 255.0), src));
			float m = max(out_rgb.r, max(out_rgb.g, out_rgb.b));
			if (m > 1.0) {
				out_rgb /= m;
			}
			COLOR = vec4(clamp(out_rgb, vec3(0.0), vec3(1.0)), 1.0);
		}
	} else if (!(tex.g > tex.r && tex.g > tex.b)) {
		// Untinted, or a grey / non-green accent: exactly as authored.
		COLOR = vec4(tex.rgb, 1.0);
	} else {
		float n = (tex.r + tex.b) * 0.5;
		float k = tex.g - n;
		vec3 out_rgb = vec3(n) + k * target_colour;
		// fpc_atomic scales by 255/max on overflow; in normalised floats that
		// is a divide by the max.
		float m = max(out_rgb.r, max(out_rgb.g, out_rgb.b));
		if (m > 1.0) {
			out_rgb /= m;
		}
		COLOR = vec4(clamp(out_rgb, vec3(0.0), vec3(1.0)), 1.0);
	}
}
