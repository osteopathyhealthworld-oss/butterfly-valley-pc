shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Art V2 prototype: colour covers and normals are independently blended.
// World-space coordinates keep texture scale and boundaries continuous
// across the existing streamed 28 m chunks. All source maps are CC0.
uniform sampler2D grass_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D meadow_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

varying vec2 terrain_uv;
varying vec2 coverage;
varying float face_slope;

float hash_cell(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash_cell(cell);
    float b = hash_cell(cell + vec2(1.0, 0.0));
    float c = hash_cell(cell + vec2(0.0, 1.0));
    float d = hash_cell(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    // The terrain generator already stores world X/Z in UV * 10.
    terrain_uv = UV * 2.7;
    coverage = UV2;
    face_slope = 1.0 - abs(NORMAL.y);
}

void fragment() {
    vec2 uv = terrain_uv;
    float macro = smooth_noise(uv * 0.085);
    float mid = smooth_noise(uv * 0.30 + vec2(43.7, 18.2));
    float micro = smooth_noise(uv * 0.77 + vec2(11.3, 35.8));

    // UV2 comes from the biome's forest and rocky exposure fields.
    // COLOR.a carries meadow openness; slope adds exposed stone.
    float woods = smoothstep(0.17, 0.68, coverage.x + (macro - 0.5) * 0.26);
    float rock = smoothstep(0.27, 0.76, coverage.y + face_slope * 1.4
        + (mid - 0.5) * 0.24);
    float meadow = clamp(COLOR.a * 0.78 + (macro - 0.5) * 0.25, 0.0, 0.93)
        * (1.0 - woods * 0.75);
    float bare_soil = smoothstep(0.40, 0.79, mid * 0.68 + micro * 0.32
        + woods * 0.27) * (0.16 + woods * 0.48);

    vec3 grass = texture(grass_color, uv).rgb;
    vec3 meadow_rgb = texture(meadow_color, uv * 0.90).rgb;
    vec3 forest = texture(forest_color, uv * 0.85).rgb;
    vec3 soil = texture(soil_color, uv * 0.97).rgb;
    vec3 stone = texture(rock_color, uv * 0.70).rgb;

    vec3 surface_rgb = mix(grass, meadow_rgb, meadow);
    surface_rgb = mix(surface_rgb, forest, woods * 0.88);
    surface_rgb = mix(surface_rgb, soil, bare_soil);
    surface_rgb = mix(surface_rgb, stone, rock * 0.93);

    // Limit the color overlay so the actual forest-floor material remains
    // visible; the legacy shader's strong green tint hid the differences.
    vec3 biome_tint = mix(vec3(1.0), COLOR.rgb, 0.20);
    float wet_dimming = mix(1.0, 0.79, wetness);
    ALBEDO = surface_rgb * biome_tint * wet_dimming;

    vec3 n = mix(texture(grass_normal, uv).rgb,
        texture(forest_normal, uv * 0.85).rgb, woods);
    n = mix(n, texture(rock_normal, uv * 0.70).rgb, rock);
    NORMAL_MAP = n;
    NORMAL_MAP_DEPTH = 0.48;
    ROUGHNESS = mix(0.96, 0.57, wetness);
    METALLIC = 0.0;
}
