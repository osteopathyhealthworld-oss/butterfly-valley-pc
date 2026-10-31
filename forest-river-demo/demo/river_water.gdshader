shader_type spatial;
// Opaque water writes depth. The old transparent/no-depth surface caused
// sorting artifacts; high spatial wave frequencies caused severe moire.
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform vec4 shallow_color : source_color = vec4(0.13, 0.35, 0.32, 1.0);
uniform vec4 deep_color : source_color = vec4(0.055, 0.23, 0.27, 1.0);
uniform float flow_speed : hint_range(0.0, 3.0) = 0.40;

void vertex() {
	float swell = sin(UV.y * 2.5 - TIME * 0.9 + UV.x * 2.1);
	VERTEX.y += 0.012 * swell;
}

void fragment() {
	float drift = UV.y - TIME * flow_speed;
	float a = sin(drift * 2.4 + UV.x * 3.2);
	float b = cos(drift * 5.1 - UV.x * 2.5);
	float motion = 0.5 * a + 0.5 * b;
	float bank = smoothstep(0.10, 0.46, abs(UV.x - 0.5));
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, clamp(bank * 0.8 + motion * 0.055, 0.0, 1.0));
	ROUGHNESS = 0.46;
	METALLIC = 0.0;
	SPECULAR = 0.32;
}
