shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.08, 0.38, 0.31, 1.0);
uniform vec4 deep_color : source_color = vec4(0.025, 0.19, 0.22, 1.0);
uniform vec4 sun_glint : source_color = vec4(0.76, 0.90, 0.81, 1.0);
uniform float flow_speed : hint_range(0.0, 3.0) = 0.41;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.13;
uniform float opacity : hint_range(0.0, 1.0) = 0.83;

void vertex() {
	float r1 = sin(UV.y * 63.0 - TIME * 1.9 + UV.x * 12.0);
	float r2 = sin(UV.y * 109.0 - TIME * 2.5 - UV.x * 21.0);
	VERTEX.y += (r1 + r2 * 0.52) * 0.023;
}

void fragment() {
	vec2 flow_uv = vec2(UV.x, UV.y - TIME * flow_speed);
	float wave_a = sin(flow_uv.y * 83.0 + sin(flow_uv.x * 29.0) * 1.5);
	float wave_b = cos(flow_uv.y * 137.0 + flow_uv.x * 37.0);
	float wave_c = sin(flow_uv.y * 51.0 - flow_uv.x * 73.0);
	float wave = wave_a * 0.49 + wave_b * 0.31 + wave_c * 0.20;
	float bank = smoothstep(0.06, 0.40, abs(UV.x - 0.5));
	float glint = pow(max(0.0, wave * 0.5 + 0.5), 6.0);
	vec3 color = mix(deep_color.rgb, shallow_color.rgb, bank * 0.70 + wave * 0.10);
	color = mix(color, sun_glint.rgb, glint * 0.15);
	ALBEDO = color;
	METALLIC = 0.08;
	SPECULAR = 0.94;
	ROUGHNESS = roughness_value + 0.07 * (1.0 - glint);
	NORMAL_MAP = vec3(wave_a * 0.14 + wave_c * 0.05, wave_b * 0.14, 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
	ALPHA = opacity - bank * 0.14;
}
