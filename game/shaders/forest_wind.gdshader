shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_texture = false;
uniform float wind_strength = 0.45;

void vertex() {
	// Cached tree meshes are normalized to one metre before instance scaling.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	float weight = smoothstep(0.2,1.0,VERTEX.y);
	float wave = sin(TIME*1.1+world.x*0.13+world.z*0.19);
	wave += sin(TIME*2.3+world.z*0.37)*0.28;
	VERTEX.x += wave * weight * wind_strength * 0.022;
	VERTEX.z += wave * weight * wind_strength * 0.010;
}

void fragment() {
	vec4 color = tint;
	if (use_texture) color *= texture(albedo_texture,UV);
	ALBEDO = color.rgb;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	ALPHA = color.a;
	ROUGHNESS = 0.88;
}
