extends Node3D
## Clean-room terrain and vegetation demo. One-time scene construction only.
## No inherited forest controllers, shader wind, runtime LOD, terrain streaming,
## camera-following grass jobs or animated compositor passes.

const BUILD_TAG := "CLEAN-R0-2026-10-31"
const HALF_SIZE := 142.0
const TERRAIN_STEPS := 180
const WATER_LEVEL := 0.15
const RIVER_STEPS := 240
const TREE_COUNT := 330
const GRASS_COUNT := 4600

const TREE_FILES := [
	"res://objects/pine-tree-1/scene.gltf",
	"res://objects/pine-tree-3/scene.gltf",
	"res://objects/birch-tree-1/scene.gltf",
]

var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _texture_noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _foliage_materials: Dictionary = {}

var terrain_mesh: MeshInstance3D
var river_mesh: MeshInstance3D
var forest_root: Node3D
var grass_mesh: MultiMeshInstance3D
var camera: Camera3D
var sun: DirectionalLight3D
var _hud: Label
var _terrain_normal: StandardMaterial3D
var _terrain_checker: StandardMaterial3D
var _diagnostic := false
var _elapsed := 0.0


func _ready() -> void:
	_rng.seed = 76031
	_hills.seed = 501
	_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_hills.frequency = 0.017
	_detail.seed = 1705
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail.frequency = 0.072
	_texture_noise.seed = 309
	_texture_noise.frequency = 0.055
	_create_daylight()
	_build_terrain()
	_build_river()
	_build_shore_stones()
	_build_forest()
	_build_grass()
	_create_camera()
	_create_hud()


static func river_center(z: float) -> float:
	return 19.0 * sin(z * 0.016) + 6.5 * sin(z * 0.042 + 0.8)


static func river_half_width(z: float) -> float:
	return 5.7 + 1.3 * sin(z * 0.021 + 0.5)


static func river_distance(x: float, z: float) -> float:
	return absf(x - river_center(z))


func upland_height(x: float, z: float) -> float:
	var h := 5.8 + 5.8 * _hills.get_noise_2d(x, z)
	h += 1.9 * _detail.get_noise_2d(x, z)
	h += 2.3 * sin(x * 0.024 + z * 0.009)
	h += 1.6 * cos(z * 0.033 - x * 0.011)
	return maxf(2.9, h)


func height_at(x: float, z: float) -> float:
	var d := river_distance(x, z)
	var width := river_half_width(z)
	if d <= width:
		var t := d / width
		return -2.55 + 1.95 * t * t
	if d <= width + 3.0:
		return lerpf(-0.60, 0.75, smoothstep(width, width + 3.0, d))
	return lerpf(0.75, upland_height(x, z), smoothstep(width + 3.0, width + 19.0, d))


func _create_daylight() -> void:
	var env := Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.24, 0.44, 0.68)
	sky_material.sky_horizon_color = Color(0.75, 0.84, 0.87)
	sky_material.ground_horizon_color = Color(0.62, 0.68, 0.61)
	sky_material.ground_bottom_color = Color(0.25, 0.35, 0.30)
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.87, 0.93, 0.85)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.glow_enabled = false
	var world := WorldEnvironment.new()
	world.environment = env
	world.name = "StableDaylight"
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.83)
	sun.light_energy = 1.4
	sun.shadow_enabled = false
	add_child(sun)


func _make_ground_texture() -> Texture2D:
	# This texture has distinct green/brown detail, unlike the grey upstream JPG.
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	for row in range(256):
		for col in range(256):
			var low := _texture_noise.get_noise_2d(col * 0.8, row * 0.8)
			var speck := _detail.get_noise_2d(col * 2.3 + 810.0, row * 2.3)
			var grain := _rng.randf_range(-0.075, 0.075)
			var green := clampf(0.50 + low * 0.18 + speck * 0.12 + grain, 0.20, 0.81)
			var earth := smoothstep(-0.12, -0.57, low)
			var colour := Color(0.30, green, 0.22).lerp(Color(0.40, 0.34, 0.23), earth * 0.65)
			img.set_pixel(col, row, colour)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_terrain() -> void:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var triangles := PackedInt32Array()
	var spacing := (2.0 * HALF_SIZE) / float(TERRAIN_STEPS)
	for zi in range(TERRAIN_STEPS + 1):
		var z := -HALF_SIZE + zi * spacing
		for xi in range(TERRAIN_STEPS + 1):
			var x := -HALF_SIZE + xi * spacing
			var y := height_at(x, z)
			points.append(Vector3(x, y, z))
			normals.append(Vector3(height_at(x - 0.4, z) - height_at(x + 0.4, z), 0.8, height_at(x, z - 0.4) - height_at(x, z + 0.4)).normalized())
			uvs.append(Vector2(x / 5.6, z / 5.6))
			var dry := smoothstep(0.0, 11.0, y)
			var mud := 1.0 - smoothstep(river_half_width(z) + 2.0, river_half_width(z) + 20.0, river_distance(x, z))
			var green := Color(0.92, 1.0, 0.87).lerp(Color(0.67, 0.78, 0.55), dry * 0.38)
			colors.append(green.lerp(Color(1.0, 0.82, 0.66), mud * 0.7))
	for zi in range(TERRAIN_STEPS):
		for xi in range(TERRAIN_STEPS):
			var a := zi * (TERRAIN_STEPS + 1) + xi
			var b := a + 1
			var c := a + TERRAIN_STEPS + 1
			var d := c + 1
			triangles.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_terrain_normal = StandardMaterial3D.new()
	_terrain_normal.resource_name = "GREEN_BROWN_GROUND_TEXTURE"
	_terrain_normal.albedo_texture = _make_ground_texture()
	_terrain_normal.vertex_color_use_as_albedo = true
	_terrain_normal.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_terrain_normal.texture_repeat = true
	_terrain_normal.roughness = 0.98
	_terrain_normal.cull_mode = BaseMaterial3D.CULL_DISABLED
	_terrain_checker = StandardMaterial3D.new()
	_terrain_checker.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_terrain_checker.albedo_color = Color(1.0, 0.30, 0.13)
	_terrain_checker.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain_mesh = MeshInstance3D.new()
	terrain_mesh.name = "VisibleTexturedTerrain"
	terrain_mesh.mesh = mesh
	terrain_mesh.material_override = _terrain_normal
	add_child(terrain_mesh)


func _make_water_texture() -> Texture2D:
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	for row in range(128):
		for col in range(128):
			# Low-contrast texture: the previous regular zigzags looked artificial.
			var ripples := sin(row * 0.24 + sin(col * 0.07) * 1.3)
			var tones := 0.91 + 0.026 * ripples + _rng.randf_range(-0.012, 0.012)
			img.set_pixel(col, row, Color(0.29 * tones, 0.55 * tones, 0.57 * tones))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_river() -> void:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var triangles := PackedInt32Array()
	const CROSSES := 10
	for zi in range(RIVER_STEPS + 1):
		var z := -HALF_SIZE + float(zi) / RIVER_STEPS * 2.0 * HALF_SIZE
		var center := river_center(z)
		var width := river_half_width(z) + 1.35
		for xi in range(CROSSES + 1):
			var u := float(xi) / CROSSES
			points.append(Vector3(center + (u * 2.0 - 1.0) * width, WATER_LEVEL, z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(u * 2.0, z * 0.10))
	for zi in range(RIVER_STEPS):
		for xi in range(CROSSES):
			var a := zi * (CROSSES + 1) + xi
			var b := a + 1
			var c := a + CROSSES + 1
			var d := c + 1
			triangles.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.resource_name = "OPAQUE_CURVING_WATER_NO_SHADER"
	material.albedo_texture = _make_water_texture()
	material.texture_repeat = true
	material.roughness = 0.28
	material.metallic = 0.04
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	river_mesh = MeshInstance3D.new()
	river_mesh.name = "WindingRiver"
	river_mesh.mesh = mesh
	river_mesh.material_override = material
	add_child(river_mesh)


func _build_shore_stones() -> void:
	var pebble := SphereMesh.new()
	pebble.radius = 0.35
	pebble.height = 0.45
	pebble.radial_segments = 6
	pebble.rings = 3
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color(0.43, 0.45, 0.40)
	stone_material.roughness = 1.0
	pebble.material = stone_material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = pebble
	mm.instance_count = 320
	for i in range(mm.instance_count):
		var z := _rng.randf_range(-HALF_SIZE + 4.0, HALF_SIZE - 4.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := river_center(z) + side * (river_half_width(z) + _rng.randf_range(2.9, 13.0))
		var scale := _rng.randf_range(0.4, 1.8)
		var basis := Basis().scaled(Vector3(scale * 1.4, scale * 0.5, scale))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, height_at(x, z) + 0.05, z)))
	var inst := MultiMeshInstance3D.new()
	inst.name = "StaticRiverbankStones"
	inst.multimesh = mm
	add_child(inst)


func _stable_material(original: Material) -> Material:
	if original == null:
		return null
	var key := original.get_instance_id()
	if _foliage_materials.has(key):
		return _foliage_materials[key]
	var replacement := StandardMaterial3D.new()
	if original is BaseMaterial3D:
		var source := original as BaseMaterial3D
		replacement.albedo_texture = source.albedo_texture
		replacement.albedo_color = source.albedo_color
		replacement.roughness = source.roughness
		replacement.metallic = 0.0
		if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			replacement.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			replacement.alpha_scissor_threshold = 0.42
			replacement.alpha_antialiasing_edge = 0.28
			replacement.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	elif original is ShaderMaterial:
		var source := original as ShaderMaterial
		replacement.albedo_texture = source.get_shader_parameter("albedo_texture") as Texture2D
		replacement.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		replacement.alpha_scissor_threshold = 0.42
		replacement.alpha_antialiasing_edge = 0.28
		replacement.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	replacement.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	replacement.cull_mode = BaseMaterial3D.CULL_DISABLED
	_foliage_materials[key] = replacement
	return replacement


func _clean_tree_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if instance.mesh != null:
			for surface in range(instance.mesh.get_surface_count()):
				var stable := _stable_material(instance.get_active_material(surface))
				if stable != null:
					instance.set_surface_override_material(surface, stable)
	for child in node.get_children():
		_clean_tree_meshes(child)


func _build_forest() -> void:
	forest_root = Node3D.new()
	forest_root.name = "StaticForest"
	add_child(forest_root)
	var sources: Array[PackedScene] = []
	for path in TREE_FILES:
		var packed := load(path) as PackedScene
		if packed != null:
			sources.append(packed)
	if sources.is_empty():
		push_error("Tree assets failed to import")
		return
	var attempts := 0
	while forest_root.get_child_count() < TREE_COUNT and attempts < TREE_COUNT * 10:
		attempts += 1
		var x := _rng.randf_range(-HALF_SIZE + 7.0, HALF_SIZE - 7.0)
		var z := _rng.randf_range(-HALF_SIZE + 7.0, HALF_SIZE - 7.0)
		if river_distance(x, z) < river_half_width(z) + 12.0:
			continue
		if Vector2(x - 28.0, z - 48.0).length() < 12.0:
			continue
		var kind := _rng.randi_range(0, 9)
		var index := 0 if kind < 4 else (1 if kind < 8 else 2)
		index = mini(index, sources.size() - 1)
		var tree := sources[index].instantiate() as Node3D
		if tree == null:
			continue
		var scale := _rng.randf_range(1.9, 2.9) if index == 0 else (_rng.randf_range(0.55, 0.9) if index == 1 else _rng.randf_range(2.0, 3.1))
		tree.scale = Vector3.ONE * scale
		tree.rotation.y = _rng.randf_range(-PI, PI)
		tree.position = Vector3(x, height_at(x, z) - 0.16, z)
		_clean_tree_meshes(tree)
		forest_root.add_child(tree)


func _make_grass_blade() -> Mesh:
	var vertices := PackedVector3Array([
		Vector3(-0.13, 0.0, 0.0), Vector3(0.13, 0.0, 0.0), Vector3(0.015, 0.67, 0.0),
		Vector3(0.0, 0.0, -0.13), Vector3(0.0, 0.0, 0.13), Vector3(0.0, 0.58, 0.015),
	])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.47, 0.65, 0.30)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


func _build_grass() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _make_grass_blade()
	mm.instance_count = GRASS_COUNT
	for i in range(GRASS_COUNT):
		var x := _rng.randf_range(-HALF_SIZE + 4.0, HALF_SIZE - 4.0)
		var z := _rng.randf_range(-HALF_SIZE + 4.0, HALF_SIZE - 4.0)
		var y := height_at(x, z)
		if river_distance(x, z) < river_half_width(z) + 5.0:
			# Invisible under the dry bank: never rebuild or move these instances.
			y -= 50.0
		var scale := _rng.randf_range(0.55, 1.3)
		var basis := Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))
	grass_mesh = MultiMeshInstance3D.new()
	grass_mesh.name = "OneTimeStaticGrass"
	grass_mesh.multimesh = mm
	add_child(grass_mesh)


func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "FreeFlyCamera"
	camera.fov = 73.0
	camera.far = 450.0
	camera.current = true
	camera.set_script(load("res://FlyCamera.gd"))
	add_child(camera)
	camera.call("configure", Vector3(34.0, 31.0, 103.0), 0.32, -0.29)


func _create_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Information"
	add_child(layer)
	_hud = Label.new()
	_hud.name = "Status"
	_hud.position = Vector2(16.0, 10.0)
	_hud.add_theme_font_size_override("font_size", 17)
	_hud.add_theme_color_override("font_color", Color(1.0, 1.0, 0.96))
	_hud.add_theme_color_override("font_outline_color", Color(0.02, 0.08, 0.09))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)
	_update_hud()


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.text = "%s | FPS %d | %.1f м | %s\nWASD полёт | ПРОБЕЛ вверх | C вниз | SHIFT быстро | R вернуть камеру | ESC мышь\nF1 земля: %s | F2 лес: %s | F3 трава: %s | F4 река: %s | F5 тени: %s" % [
		BUILD_TAG, Engine.get_frames_per_second(), camera.global_position.y,
		RenderingServer.get_current_rendering_method(),
		"КРАСНАЯ" if _diagnostic else "ТЕКСТУРА",
		"ВКЛ" if forest_root.visible else "ВЫКЛ",
		"ВКЛ" if grass_mesh.visible else "ВЫКЛ",
		"ВКЛ" if river_mesh.visible else "ВЫКЛ",
		"ВКЛ" if sun.shadow_enabled else "ВЫКЛ",
	]


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > 0.5:
		_elapsed = 0.0
		_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F1:
			_diagnostic = not _diagnostic
			terrain_mesh.material_override = _terrain_checker if _diagnostic else _terrain_normal
		KEY_F2:
			forest_root.visible = not forest_root.visible
		KEY_F3:
			grass_mesh.visible = not grass_mesh.visible
		KEY_F4:
			river_mesh.visible = not river_mesh.visible
		KEY_F5:
			sun.shadow_enabled = not sun.shadow_enabled
		_:
			return
	_update_hud()
	get_viewport().set_input_as_handled()
