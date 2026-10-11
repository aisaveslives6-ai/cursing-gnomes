// Cursing Gnomes — subtle screen vignette (GL Compatibility / WebGL2 safe).
//
// Drawn on a full-rect ColorRect in a CanvasLayer above the weather tint
// and below the HUD, so only the world gets the vignette. Cheap: one
// full-screen quad, no textures.

shader_type canvas_item;

uniform float strength = 0.30;
uniform vec3 tint = vec3(0.01, 0.015, 0.04);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.35, 1.0));
	float v = smoothstep(0.52, 1.02, d);
	COLOR = vec4(tint, v * strength);
}
