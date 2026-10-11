shader_type canvas_item;
// Cursing Gnomes — hurt flash (HTML chibiWhite parity, fix79 index.html:39034).
// Renders the sprite's texture as a pure-white silhouette whose alpha is
// driven per-unit by flash_alpha (HTML: min(0.75, _hurtT * 2.2)).
uniform float flash_alpha : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(1.0, 1.0, 1.0, t.a * flash_alpha);
}
