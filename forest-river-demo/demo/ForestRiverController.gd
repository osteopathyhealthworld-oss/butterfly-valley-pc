extends Node3D

const RiverTerrainScript = preload("res://demo/RiverTerrain.gd")
const WaterShader = preload("res://demo/river_water.gdshader")
const GroundShader = preload("res://demo/ground_stable.gdshader")
const WATER_LENGTH := 196.0
const WATER_SEGMENTS := 240
const WATER_CROSS_SEGMENTS := 8
const HOUSE_SPOT := Vector2(27.0, -17.0)
const WELL_SPOT := Vector2(25.0, -4.0)
const BUILD_TAG := "FR-2026-10-31-R4"

@onready var terrain: Node3D = $Terrain
@onready var fly_camera: Camera3D = $FlyCamera
var _fps_label: Label
var _fps_elapsed := 0.0
var _diagnostics_label: Label
var _diagnostic_ground_enabled := false
var _normal_ground_material: Material
var _diagnostic_ground_material: StandardMaterial3D

func _ready() -> void:
	_configure_stable_rendering()
	_install_river_masks()
	_build_river()
	_build_shore_details()
	_position_props()
	_position_camera()
	_add_hud()
	# All lighting is configured once, without temporal brightness changes.


func _configure_stable_rendering() -> void:
	# The original used strong fog, automatic exposure, volumetric temporal
	# history, SDFGI, bloom and custom sun shafts. These made the surface
	# difficult to see and introduced brightness/temporal instability.
	var world: WorldEnvironment = $WorldEnvironment
	var env: Environment = world.environment.duplicate(true)
	# The upstream layered sky shader fails to compile on OpenGL 4.6
	# (TIME is undeclared in the generated GLES3 shader). Use Godot's
	# built-in, non-animated daytime sky on both renderers.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.28, 0.47, 0.69)
	sky_material.sky_horizon_color = Color(0.72, 0.81, 0.86)
	sky_material.ground_horizon_color = Color(0.63, 0.67, 0.65)
	sky_material.ground_bottom_color = Color(0.33, 0.37, 0.33)
	sky_material.sky_curve = 0.18
	sky_material.sun_angle_max = 15.0
	sky_material.use_debanding = true
	var stable_sky := Sky.new()
	stable_sky.sky_material = sky_material
	env.sky = stable_sky
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_density = 0.004
	env.fog_sky_affect = 0.03
	env.volumetric_fog_enabled = false
	env.sdfgi_enabled = false
	env.ssil_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = true
	env.adjustment_enabled = false
	env.ambient_light_energy = 1.10
	env.background_energy_multiplier = 0.85
	env.tonemap_exposure = 0.85
	world.environment = env
	world.camera_attributes = null
	world.compositor = null
	$SunShaftsController.process_mode = Node.PROCESS_MODE_DISABLED
	$AutoBiomesFog.process_mode = Node.PROCESS_MODE_DISABLED
	var sun: DirectionalLight3D = $DirectionalLight3D
	sun.light_energy = 1.10
	sun.directional_shadow_max_distance = 95.0
	sun.light_angular_distance = 1.0

	# Replace the 32-layer parallax/50x UV ground material with an opaque,
	# stable PBR surface: actual hills plus texturing and sandy banks.
	var ground := ShaderMaterial.new()
	ground.shader = GroundShader
	ground.set_shader_parameter("ground_texture",
		load("res://textures/Ground020_1K-JPG/Ground020_1K_Color.jpg"))
	terrain.set("terrain_material", ground)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if not event.pressed or event.echo:
		return
	var key: int = event.physical_keycode
	match key:
		KEY_F1:
			var river := get_node_or_null("AnimatedRiver") as MeshInstance3D
			if river != null:
				river.visible = not river.visible
		KEY_F2:
			var show_trees: bool = not $Trees.visible
			for biome_name in ["Trees", "Plants", "Plants2"]:
				(get_node(biome_name) as Node3D).visible = show_trees
		KEY_F3:
			_toggle_diagnostic_ground()
		_:
			return
	_update_diagnostics_label()
	get_viewport().set_input_as_handled()


func _toggle_diagnostic_ground() -> void:
	var ground_mesh := terrain.get_node_or_null("__terrain_mesh") as MeshInstance3D
	if ground_mesh == null:
		return
	if _normal_ground_material == null:
		_normal_ground_material = ground_mesh.material_override
	if _diagnostic_ground_material == null:
		_diagnostic_ground_material = StandardMaterial3D.new()
		_diagnostic_ground_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_diagnostic_ground_material.albedo_color = Color(0.94, 0.28, 0.14)
		_diagnostic_ground_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_diagnostic_ground_enabled = not _diagnostic_ground_enabled
	ground_mesh.material_override = _diagnostic_ground_material if _diagnostic_ground_enabled else _normal_ground_material


func _update_diagnostics_label() -> void:
	if _diagnostics_label == null:
		return
	var river := get_node_or_null("AnimatedRiver") as MeshInstance3D
	var water_status := "ВКЛ" if river == null or river.visible else "ВЫКЛ"
	var trees_status := "ВКЛ" if $Trees.visible else "ВЫКЛ"
	var ground_status := "ОТЛАДКА" if _diagnostic_ground_enabled else "ТЕКСТУРА"
	_diagnostics_label.text = "%s  |  F1: вода %s  |  F2: лес %s  |  F3: земля %s" % [BUILD_TAG, water_status, trees_status, ground_status]


func _process(delta: float) -> void:
	_fps_elapsed += delta
	if _fps_label != null and _fps_elapsed > 0.6:
		_fps_elapsed = 0.0
		_fps_label.text = "FPS: %d  |  Высота: %.1f м  |  Forward+ / PBR" % [Engine.get_frames_per_second(), fly_camera.global_position.y]


func _river_distance(x: float, z: float) -> float:
	return absf(x - RiverTerrainScript.center_at(z))


func _is_prop_clearing(x: float, z: float) -> bool:
	var spot := Vector2(x, z)
	return spot.distance_squared_to(HOUSE_SPOT) < 9.0 * 9.0 or spot.distance_squared_to(WELL_SPOT) < 3.8 * 3.8


func _install_river_masks() -> void:
	for biome_name in ["Trees", "Plants", "Plants2"]:
		var biome: Node3D = get_node(biome_name)
		var source: Texture2D = biome.get("mask_texture")
		if source == null:
			continue
		var mask: Image = source.get_image()
		if mask.is_compressed():
			mask.decompress()
		mask.convert(Image.FORMAT_RGBA8)
		var dimensions: Vector2 = biome.get("area_size")
		for py in range(mask.get_height()):
			var z: float = (float(py) / float(mask.get_height() - 1) - 0.5) * dimensions.y
			for px in range(mask.get_width()):
				var x: float = (float(px) / float(mask.get_width() - 1) - 0.5) * dimensions.x
				if _river_distance(x, z) < 8.0 or _is_prop_clearing(x, z):
					var c: Color = mask.get_pixel(px, py)
					c.r = 0.0 if biome_name == "Plants2" else 1.0
					mask.set_pixel(px, py, c)
		biome.set("mask_texture", ImageTexture.create_from_image(mask))

	var grass_source: Texture2D = terrain.get("grass_mask_texture")
	if grass_source == null:
		return
	var grass_mask: Image = grass_source.get_image()
	if grass_mask.is_compressed():
		grass_mask.decompress()
	grass_mask.convert(Image.FORMAT_RGBA8)
	var grass_dimensions: Vector2 = terrain.get("grass_mask_area_size")
	for py in range(grass_mask.get_height()):
		var z: float = (float(py) / float(grass_mask.get_height() - 1) - 0.5) * grass_dimensions.y
		for px in range(grass_mask.get_width()):
			var x: float = (float(px) / float(grass_mask.get_width() - 1) - 0.5) * grass_dimensions.x
			if _river_distance(x, z) < 9.2 or _is_prop_clearing(x, z):
				var c: Color = grass_mask.get_pixel(px, py)
				c.g = 1.0
				grass_mask.set_pixel(px, py, c)
	terrain.set("grass_mask_texture", ImageTexture.create_from_image(grass_mask))
	terrain.regenerate()
	_rebuild_biomes_after_terrain.call_deferred()


func _rebuild_biomes_after_terrain() -> void:
	# Trees are positioned by physics raycasts. Let the new terrain collision
	# enter the physics world before recasting all tree and plant positions.
	await get_tree().physics_frame
	for biome_name in ["Trees", "Plants", "Plants2"]:
		get_node(biome_name).regenerate()


func _build_river() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(WATER_SEGMENTS):
		var z1: float = -WATER_LENGTH * 0.5 + WATER_LENGTH * float(segment) / WATER_SEGMENTS
		var z2: float = -WATER_LENGTH * 0.5 + WATER_LENGTH * float(segment + 1) / WATER_SEGMENTS
		for lane in range(WATER_CROSS_SEGMENTS):
			var u1: float = float(lane) / WATER_CROSS_SEGMENTS
			var u2: float = float(lane + 1) / WATER_CROSS_SEGMENTS
			_add_water_triangle(surface, z1, u1, z2, u1, z2, u2)
			_add_water_triangle(surface, z1, u1, z2, u2, z1, u2)
	surface.generate_normals()
	surface.generate_tangents()
	var river := MeshInstance3D.new()
	river.name = "AnimatedRiver"
	river.mesh = surface.commit()
	var material := ShaderMaterial.new()
	material.shader = WaterShader
	river.material_override = material
	river.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(river)


func _add_water_triangle(tool: SurfaceTool, za: float, ua: float, zb: float, ub: float, zc: float, uc: float) -> void:
	_add_water_vertex(tool, za, ua)
	_add_water_vertex(tool, zb, ub)
	_add_water_vertex(tool, zc, uc)


func _add_water_vertex(tool: SurfaceTool, z: float, u: float) -> void:
	var width: float = RiverTerrainScript.RIVER_HALF_WIDTH - 0.38 + 0.18 * sin(z * 0.11)
	var center: float = RiverTerrainScript.center_at(z)
	var x: float = center + (u * 2.0 - 1.0) * width
	var y: float = RiverTerrainScript.water_height_at(z) + 0.11
	tool.set_uv(Vector2(u, (z + WATER_LENGTH * 0.5) / 5.0))
	tool.add_vertex(Vector3(x, y, z))


func _build_shore_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 83472
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 1.0
	rock_mesh.height = 2.0
	rock_mesh.radial_segments = 10
	rock_mesh.rings = 5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.34, 0.34, 0.29)
	material.roughness = 0.92
	rock_mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = rock_mesh
	multi.instance_count = 440
	for i in range(multi.instance_count):
		var z: float = rng.randf_range(-91.0, 91.0)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var shore_offset: float = rng.randf_range(5.1, 15.0)
		var x: float = RiverTerrainScript.center_at(z) + shore_offset * side
		var y: float = RiverTerrainScript.water_height_at(z) - 0.10
		if shore_offset > 6.0:
			y = terrain.call("_sample_height", x, z)
		var scale: float = rng.randf_range(0.10, 0.42)
		var basis: Basis = Basis.IDENTITY.rotated(Vector3.UP, rng.randf_range(0.0, TAU))
		basis = basis.scaled(Vector3(scale * 1.55, scale * 0.53, scale))
		multi.set_instance_transform(i, Transform3D(basis, Vector3(x, y - scale * 0.28, z)))
	var stones := MultiMeshInstance3D.new()
	stones.name = "RiverbankStones"
	stones.multimesh = multi
	add_child(stones)


func _position_camera() -> void:
	# Start high enough to see the river and canopy, oriented toward
	# the river from the eastern bank. No falling or character physics.
	var x: float = 29.0
	var z: float = 11.0
	var ground: float = terrain.call("_sample_height", x, z)
	fly_camera.call("configure", terrain, Vector3(x, ground + 21.0, z),
			PI * 0.5, deg_to_rad(-27.0))


func _position_props() -> void:
	# Original forest has a cottage and well at x≈1: exactly inside our river.
	# Relocate both to dry ground, retaining their authored models and rotation.
	var placements := {
		"OldHouse": HOUSE_SPOT,
		"OldWell": WELL_SPOT,
	}
	for prop_name in placements:
		var prop: Node3D = get_node_or_null(prop_name)
		if prop == null:
			continue
		var location: Vector2 = placements[prop_name]
		var ground: float = terrain.call("_sample_height", location.x, location.y)
		prop.position = Vector3(location.x, ground, location.y)


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "RiverDemoHUD"
	add_child(layer)
	var label := Label.new()
	label.name = "Controls"
	label.text = "FOREST & RIVER  |  WASD — полёт  |  ПРОБЕЛ — вверх  |  C — вниз  |  SHIFT — быстро  |  ESC — мышь"
	label.position = Vector2(22.0, 18.0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.88, 0.96, 0.88))
	label.add_theme_color_override("font_shadow_color", Color(0.02, 0.06, 0.05, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)
	_fps_label = Label.new()
	_fps_label.position = Vector2(22.0, 45.0)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.80, 0.94, 0.85))
	layer.add_child(_fps_label)
	_diagnostics_label = Label.new()
	_diagnostics_label.name = "Diagnostics"
	_diagnostics_label.position = Vector2(22.0, 72.0)
	_diagnostics_label.add_theme_font_size_override("font_size", 14)
	_diagnostics_label.add_theme_color_override("font_color", Color(0.96, 0.90, 0.67))
	_diagnostics_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.06, 0.05, 0.96))
	_diagnostics_label.add_theme_constant_override("shadow_offset_x", 1)
	_diagnostics_label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_diagnostics_label)
	_update_diagnostics_label()
