shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Color textures are tiled in world space, so their size remains consistent
// across streamed chunks and there are no visible UV seams.
uniform sampler2D grass_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness : hint_range(0.0,1.0) = 0.0;

varying vec2 ground_uv;

float patch_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(127.1, 311.7))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(127.1, 311.7))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	ground_uv = UV * 4.0;
}

void fragment() {
	vec2 uv = ground_uv;
	float meadow_amount = clamp(COLOR.a * 0.8, 0.0, 0.78);
	float large_patch = patch_noise(uv * 0.08);
	float soil_amount = smoothstep(0.65, 0.88, large_patch) * 0.34;
	vec3 grass = texture(grass_color, uv).rgb;
	vec3 meadow = texture(meadow_color, uv * 0.83).rgb;
	vec3 soil = texture(soil_color, uv * 1.12).rgb;
	vec3 surface_color = mix(grass, meadow, meadow_amount);
	surface_color = mix(surface_color, soil, soil_amount);
	ALBEDO = surface_color * mix(vec3(1.0), COLOR.rgb, 0.45) * mix(1.0,0.76,wetness);
	NORMAL_MAP = texture(grass_normal, uv).rgb;
	NORMAL_MAP_DEPTH = 0.45;
	ROUGHNESS = mix(0.93,0.47,wetness);
	METALLIC = 0.0;
}

