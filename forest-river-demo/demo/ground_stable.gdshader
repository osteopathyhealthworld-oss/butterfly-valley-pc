shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform sampler2D ground_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying float shore_amount;
varying float elevation;

void vertex() {
	float center_x = 11.0 * sin(VERTEX.z * 0.030) + 3.5 * sin(VERTEX.z * 0.085 + 0.65);
	float river_distance = abs(VERTEX.x - center_x);
	shore_amount = 1.0 - smoothstep(5.2, 13.0, river_distance);
	elevation = VERTEX.y;
}

void fragment() {
	vec3 ground = texture(ground_texture, UV * 18.0).rgb;
	vec3 earth = mix(vec3(0.26, 0.30, 0.20), ground * vec3(1.04, 1.13, 0.91), 0.65);
	float upland = smoothstep(8.0, 19.0, elevation);
	earth = mix(earth, earth * vec3(0.79, 0.82, 0.75), upland * 0.42);
	vec3 sand = mix(vec3(0.48, 0.41, 0.30), ground * vec3(1.28, 1.15, 0.89), 0.22);
	ALBEDO = mix(earth, sand, 0.92 * shore_amount);
	ROUGHNESS = 0.93;
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
