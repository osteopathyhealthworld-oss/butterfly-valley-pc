shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D ripple_normal : hint_normal, repeat_enable;
uniform vec4 water_color : source_color = vec4(0.18, 0.52, 0.57, 0.82);
uniform float flow_speed = 0.028;
uniform float ripple_strength = 0.42;

void fragment() {
	vec2 flow_a = UV * 1.45 + vec2(TIME * flow_speed, TIME * flow_speed * 0.44);
	vec2 flow_b = UV * 1.83 + vec2(-TIME * flow_speed * 0.51, TIME * flow_speed * 0.78);
	vec3 n_a = texture(ripple_normal, flow_a).rgb;
	vec3 n_b = texture(ripple_normal, flow_b).rgb;
	NORMAL_MAP = mix(n_a, n_b, 0.48);
	NORMAL_MAP_DEPTH = ripple_strength;
	float glimmer = sin(UV.x * 11.0 + TIME * 0.6) * 0.025
		+ sin(UV.y * 9.0 - TIME * 0.47) * 0.025;
	ALBEDO = water_color.rgb + vec3(glimmer * 0.42, glimmer * 0.8, glimmer);
	METALLIC = 0.04;
	ROUGHNESS = 0.23;
	SPECULAR = 0.55;
	ALPHA = water_color.a;
}

