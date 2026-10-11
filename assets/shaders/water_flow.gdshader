// Cursing Gnomes — Wind Waker water + Stardew ground detail
// (GL Compatibility / WebGL2 safe).
//
// Applied to the terrain sprite. The baked water_mask texture carries water
// depth in R (0 = land, 1 = deep center) and the ground-detail biome
// selector in G (0 = grass blades, 1 = granular speckle). flow_tex carries
// the per-tile flow direction (RG) and speed (B) baked from river_flow.
// curl_tex is a 128px tileable Wind Waker spiral-curl tile the shader
// scrolls at large scales for big stylized wave curls.
//
// Water: Wind Waker style — bold cel-banded blues, big spiral curl motifs
// scrolling along the baked flow direction, shaped whitecaps on the curl
// crests, animated lapping shoreline foam, and sparkle glints that swing
// warm by day and cool by moonlight.
// Land: a tiled AI-generated detail overlay (grass blades / granular
// speckle, picked per biome) modulates brightness for Stardew-grade ground
// texture — one extra sample pair, no extra draw calls.

shader_type canvas_item;

uniform sampler2D water_mask : filter_linear, repeat_disable;
uniform sampler2D ripple_tex : filter_linear, repeat_enable;
uniform sampler2D flow_tex : filter_linear, repeat_disable;
uniform sampler2D curl_tex : filter_linear, repeat_enable;
uniform sampler2D detail_grass : filter_linear, repeat_enable;
uniform sampler2D detail_grain : filter_linear, repeat_enable;
uniform float flow_speed = 1.0;
// Moonlight glint: 0 = full day, 1 = deep night. Set per-frame by the world
// from the same day-phase clock the lighting rig uses, so water sparkles
// cool white under the moon and warm under the sun.
uniform float night_factor = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 m = texture(water_mask, UV);
	float depth = m.r;
	float biome = m.g;
	float land_f = 1.0 - smoothstep(0.0, 0.04, depth);

	// --- Stardew ground detail (land only) ---
	if (land_f > 0.001) {
		// One detail repeat per map tile (128 repeats across the map).
		vec2 duv = UV * 128.0;
		float d_grass = texture(detail_grass, duv).r;
		float d_grain = texture(detail_grain, duv + vec2(0.37, 0.61)).r;
		float det = mix(d_grass, d_grain, clamp(biome, 0.0, 1.0));
		// Detail textures are centered on mid-gray: modulate both ways.
		base.rgb *= mix(1.0, 0.80 + 0.40 * det, land_f * 0.55);
	}

	// --- Wind Waker water ---
	// Big stylized spiral curls (baked tileable tile, map_gen) scroll along
	// the baked flow direction; still water drifts slowly on the prevailing
	// wind so lakes feel alive too. Two curl fetches replace the old two
	// ripple fetches — net-zero texture samples, no new draw calls.
	if (depth > 0.003) {
		vec3 flow_v = texture(flow_tex, UV).rgb;
		vec2 flow_dir = flow_v.rg * 2.0 - 1.0;
		float fspd = flow_v.b;
		vec2 cuv1 = UV * vec2(13.0, 10.0)
			- flow_dir * TIME * (0.006 + 0.030 * fspd) * flow_speed;
		vec2 cuv2 = UV * vec2(23.0, 19.0) + vec2(0.31, 0.17)
			- flow_dir * TIME * (0.009 + 0.041 * fspd) * flow_speed;
		float curl = texture(curl_tex, cuv1).r * 0.65
			+ texture(curl_tex, cuv2).r * 0.35;   // 0..1 curl-crest field
		// Cel bands: 3 flat tones for the stylized look.
		float band = min(floor(curl * 3.0 + 0.001), 2.0) / 2.0;  // 0, .5, 1
		vec3 deep_c  = vec3(0.10, 0.32, 0.68);
		vec3 mid_c   = vec3(0.16, 0.48, 0.85);
		vec3 crest_c = vec3(0.42, 0.72, 0.94);
		vec3 cel = mix(deep_c, mid_c, clamp(band * 2.0, 0.0, 1.0));
		cel = mix(cel, crest_c, clamp((band - 0.5) * 2.0, 0.0, 1.0));
		// Shallow water keeps the baked carved-bank color; deep water goes
		// full cel. The bake already grades bed -> deep (carved rule kept).
		vec3 wcol = mix(base.rgb, cel,
			(0.35 + 0.65 * band) * clamp(depth * 1.4, 0.0, 1.0));
		// Whitecaps ride the curl crests — stronger in deep, fast water.
		float cap = smoothstep(0.72, 0.95, curl)
			* (0.30 + 0.70 * depth) * (0.45 + 0.55 * fspd);
		wcol = mix(wcol, vec3(0.96, 0.99, 1.0), cap);
		// Animated lapping foam at the shoreline: the waterline breathes.
		float shore = 1.0 - smoothstep(0.0, 0.14, depth);
		float lap = 0.5 + 0.5 * sin(TIME * 1.6 + (UV.x + UV.y) * 220.0);
		float foam = shore * smoothstep(0.35, 0.80, lap);
		wcol = mix(wcol, vec3(0.97, 0.99, 1.0), foam * 0.85);
		base.rgb = wcol;

		// Curl-crest glints: warm by day, cool by moonlight (night_factor
		// is set per-frame from the same day-phase clock as the lighting).
		float sparkle = smoothstep(0.80, 0.96, curl);
		vec3 sun_glint = vec3(1.0, 0.95, 0.80);
		vec3 moon_glint = vec3(0.62, 0.74, 1.0);
		vec3 glint_col = mix(sun_glint, moon_glint, night_factor);
		float glint_k = sparkle * depth * mix(0.10, 0.34, night_factor);
		base.rgb = mix(base.rgb, glint_col, glint_k);
	}
	COLOR = base;
}
