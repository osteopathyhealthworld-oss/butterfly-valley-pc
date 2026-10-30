extends Node3D
## Долина бабочек: потоковая генерация ландшафта. Сид одинаков для Windows и Web.
## В исходной версии Babylon.js карта 224 x 246, здесь соседние чанки можно
## создавать за прежней границей мира без ручной прорисовки.

const CHUNK_SIZE := 28
const GRID := 14
const VIEW_RADIUS_LOW := 2
const VIEW_RADIUS_HIGH := 3
const Fitting = preload("res://scripts/model_fitting.gd")
const GEO = preload("res://scripts/valley_geography.gd")
# The full Quaternius models are already in the source assets; desktop builds
# use individual children of three shared GLB atlases near the camera.
const ATLAS_CANOPY := ["q-birch-1", "q-birch-2", "q-common-tree", "q-pine-1", "q-pine-2", "q-oak-wide", "q-oak-tall", "q-twisted-1", "q-twisted-2"]
const ATLAS_UNDERGROWTH := ["q-fern", "q-clover", "q-flowering-bush", "q-blue-flowers", "q-white-flowers", "q-bush", "q-tall-grass", "q-short-grass", "q-wispy-grass"]
const ATLAS_STONES := ["q-rock-1", "q-rock-2", "q-pebble-1", "q-stepping-stone"]
const ATLAS_FILES := {"canopy": ATLAS_CANOPY, "undergrowth": ATLAS_UNDERGROWTH, "river-stones": ATLAS_STONES}
# A testable PBR tree from the CC BY 4.0 procedural forest demo. Downloaded
# with a pinned manifest; the current Quaternius trees remain safe fallbacks.
const EXTERNAL_TREES := {"pbr-pine": "res://assets/forest/pine-tree-1/scene.gltf"}
const TREE_TYPES := ["tree-oak", "tree-detailed", "tree-pinerounda", "tree-pinesmalla", "tree-fat", "tree-pinetalla", "tree-oak-dark", "tree-detailed-dark", "tree-pinetallb", "tree-tall", "tree-small", "tree-default"]
const FOLIAGE_TYPES := ["grass", "grass-large", "grass-leafs", "flower-purplea", "flower-purpleb", "flower-yellowa", "flower-yellowb", "flower-reda", "flower-redb", "mushroom-redgroup", "mushroom-tangroup", "plant-bushlarge", "plant-bushdetailed", "plant-flattall", "plant-flatshort", "hanging-moss"]
const ROCK_TYPES := ["rock-largea", "rock-largeb", "rock-smalla", "rock-smallb", "rock-talla"]
const WATER_TYPES := ["lily-small", "lily-large"]
const GLADES_TYPES := ["stump-rounddetailed", "log-stack", "path-stone", "lantern-glass", "tent-smallopen"]
const TREE_GRID := 4
const UNDERGROWTH_GRID := 2
const TREE_CELLS := 7
const UNDERGROWTH_CELLS := 14
const WATER_CELLS := 7
# Ключевые маршруты прежней главы: огород → лаборатория → мост → лагерь → север.
const PATH_ROUTES := [
	[Vector2(-19, -40), Vector2(-19, -33), Vector2(-15, -28), Vector2(-9, -25), Vector2(-4, -18), Vector2(1, -8), Vector2(5, 3.5)],
	[Vector2(5, 3.5), Vector2(5, 15.5), Vector2(8, 24), Vector2(12, 32), Vector2(15, 43), Vector2(25, 58), Vector2(28, 94), Vector2(31, 135)]
]
# Авторские места собираются из готовых CC0-моделей. Их силуэты и группы
# объектов различимы с дорожек, а центральные сюжетные точки не перекрыты.
const WORLD_PLACES := [
	{"pos": Vector2(-47, -56), "radius": 10.0, "kind": "amber", "name": "Янтарный древолес"},
	{"pos": Vector2(-58, 30), "radius": 9.5, "kind": "moss", "name": "Моховая обитель"},
	{"pos": Vector2(-49, 97), "radius": 10.5, "kind": "violet", "name": "Лиловый сад"},
	{"pos": Vector2(60, -15), "radius": 11.0, "kind": "hamlet", "name": "Корневая слобода"},
	{"pos": Vector2(64, 114), "radius": 11.5, "kind": "ridge", "name": "Врата ветров"},
	{"pos": Vector2(7, 105), "radius": 11.0, "kind": "elder", "name": "Роща старого хранителя"},
]

var _loaded: Dictionary = {}
var _pending: Array[Vector2i] = []
var _active_build: Dictionary = {}
var _mesh_library: Dictionary = {}
var _scene_library: Dictionary = {}
var _atlas_sources: Dictionary = {}
var _atlas_batched: Dictionary = {}
var _wind_materials: Array[ShaderMaterial] = []
var _atlas_roots: Array[Node3D] = []
var _colliders: Dictionary = {}
var _glades: Dictionary = {}
var navigation_revision := 0
var chapter_obstacles: Array[Rect2] = []
var bridge_open := false
var _wetness := 0.0
var _grass_material: Material
var _grass_basic: StandardMaterial3D
var _grass_detailed: ShaderMaterial
var _water_material: Material
var _path_material: StandardMaterial3D
var _bank_material: StandardMaterial3D
var high_quality := false
var workshop_stage := 0
var _builder_trees_cut: Array = [false, false, false]
const BUILDER_TREES := [Vector2(22.0, -27.0), Vector2(33.0, -37.0), Vector2(40.0, -29.0)]
var _noise := FastNoiseLite.new()
var _canopy_noise := FastNoiseLite.new()
var _soil_noise := FastNoiseLite.new()
var _center_cell := Vector2i(999999, 999999)
var _mote_mesh: Mesh

func _exit_tree() -> void:
	# Prototypes were instantiated outside the SceneTree and need explicit release.
	for prototype in _atlas_roots:
		if is_instance_valid(prototype): prototype.free()
	_atlas_roots.clear()
	_atlas_sources.clear()
	_wind_materials.clear()

func _ready() -> void:
	_noise.seed = 1947
	_noise.frequency = 0.012
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 3
	_canopy_noise.seed = 7071
	_canopy_noise.frequency = 0.042
	_canopy_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_canopy_noise.fractal_octaves = 3
	_soil_noise.seed = 442
	_soil_noise.frequency = 0.023
	_soil_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_soil_noise.fractal_octaves = 2
	_grass_basic = StandardMaterial3D.new()
	_grass_basic.albedo_color = Color("#c1d4ad")
	_grass_basic.vertex_color_use_as_albedo = true
	_grass_basic.roughness = 0.96
	_grass_basic.uv1_scale = Vector3(4.0, 4.0, 4.0)
	if ResourceLoader.exists("res://assets/environment/grass-ground-color.jpg"):
		_grass_basic.albedo_texture = load("res://assets/environment/grass-ground-color.jpg")
	if ResourceLoader.exists("res://assets/environment/grass-ground-normal.jpg"):
		_grass_basic.normal_enabled = true
		_grass_basic.normal_texture = load("res://assets/environment/grass-ground-normal.jpg")
		_grass_basic.normal_scale = 0.45
	var terrain_shader_path := "res://shaders/terrain_blend.gdshader"
	var terrain_tex := ["grass-ground-color.jpg", "meadow-color.jpg", "forest-color.jpg", "soil-color.jpg", "rock-color.jpg", "grass-ground-normal.jpg"]
	var has_terrain_textures := true
	for texture_name in terrain_tex:
		if not ResourceLoader.exists("res://assets/environment/" + texture_name):
			has_terrain_textures = false
	if ResourceLoader.exists(terrain_shader_path) and has_terrain_textures:
		_grass_detailed = ShaderMaterial.new()
		_grass_detailed.shader = load(terrain_shader_path)
		_grass_detailed.set_shader_parameter("grass_color", load("res://assets/environment/grass-ground-color.jpg"))
		_grass_detailed.set_shader_parameter("meadow_color", load("res://assets/environment/meadow-color.jpg"))
		_grass_detailed.set_shader_parameter("forest_color", load("res://assets/environment/forest-color.jpg"))
		_grass_detailed.set_shader_parameter("rock_color", load("res://assets/environment/rock-color.jpg"))
		_grass_detailed.set_shader_parameter("soil_color", load("res://assets/environment/soil-color.jpg"))
		_grass_detailed.set_shader_parameter("grass_normal", load("res://assets/environment/grass-ground-normal.jpg"))
	# The economical graphics mode still needs textured, varied ground.
	# Its performance savings come from streaming fewer terrain chunks.
	_grass_material = _grass_detailed if _grass_detailed != null else _grass_basic
	var river_shader := load("res://shaders/river_water.gdshader") as Shader
	if river_shader != null and ResourceLoader.exists("res://assets/environment/water-normal.png"):
		var ripples := ShaderMaterial.new()
		ripples.shader = river_shader
		ripples.set_shader_parameter("ripple_normal", load("res://assets/environment/water-normal.png"))
		_water_material = ripples
	else:
		var simple_water := StandardMaterial3D.new()
		simple_water.albedo_color = Color(0.18, 0.52, 0.58, 0.78)
		simple_water.metallic = 0.12
		simple_water.roughness = 0.17
		simple_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_material = simple_water
	_path_material = StandardMaterial3D.new()
	_path_material.albedo_color = Color("#c9b295")
	_path_material.roughness = 1.0
	if ResourceLoader.exists("res://assets/environment/gravel-color.jpg"):
		_path_material.albedo_texture = load("res://assets/environment/gravel-color.jpg")
	if ResourceLoader.exists("res://assets/environment/gravel-normal.jpg"):
		_path_material.normal_enabled = true
		_path_material.normal_texture = load("res://assets/environment/gravel-normal.jpg")
	_bank_material = StandardMaterial3D.new()
	_bank_material.albedo_color = Color("#9f9e83")
	_bank_material.roughness = 0.95
	if ResourceLoader.exists("res://assets/environment/rock-color.jpg"):
		_bank_material.albedo_texture = load("res://assets/environment/rock-color.jpg")
	if ResourceLoader.exists("res://assets/environment/rock-normal.jpg"):
		_bank_material.normal_enabled = true
		_bank_material.normal_texture = load("res://assets/environment/rock-normal.jpg")
	var mote := SphereMesh.new()
	mote.radius = 0.085
	mote.height = 0.17
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color("#e9ffc8")
	glow.emission_enabled = true
	glow.emission = Color("#b7edba")
	glow.emission_energy_multiplier = 2.5
	mote.material = glow
	_mote_mesh = mote
	for id in TREE_TYPES + FOLIAGE_TYPES + ROCK_TYPES + WATER_TYPES + GLADES_TYPES:
		var asset_path := "res://assets/%s.glb" % id
		if not ResourceLoader.exists(asset_path):
			continue
		var packed := load(asset_path) as PackedScene
		if packed == null:
			continue
		var instance := packed.instantiate()
		var found := _find_mesh(instance)
		if found != null:
			_mesh_library[id] = found.mesh
		instance.free()
	for id in ["tent-smallopen", "lantern-glass", "fence-simple", "fence-gate"]:
		var path := "res://assets/%s.glb" % id
		if ResourceLoader.exists(path):
			_scene_library[id] = load(path)
	if not OS.has_feature("web"):
		_make_regional_water()

func _load_stylized_atlases() -> void:
	if not _atlas_roots.is_empty():
		return
	for atlas_name in ATLAS_FILES:
		var path := "res://assets/environment/%s.glb" % atlas_name
		if not ResourceLoader.exists(path):
			push_warning("Нет Quaternius atlas: " + path)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var root := packed.instantiate() as Node3D
		if root == null:
			continue
		_atlas_roots.append(root) # Retain prototypes; each placement duplicates one model, not the whole atlas.
		for id in ATLAS_FILES[atlas_name]:
			var source := root.find_child(id, true, false) as Node3D
			if source != null:
				_atlas_sources[id] = {"prototype": source, "root_transform": root.transform}
				_bake_atlas_model(id)
	if not _atlas_sources.has("q-oak-wide") or not _atlas_sources.has("q-fern"):
		push_warning("Quaternius atlas models were imported without their named children.")
	_load_external_forest_models()

func _load_external_forest_models() -> void:
	# Preserve the original glTF PBR materials, including normal maps, alpha
	# cutouts and double-sided foliage. Our Quaternius wind shader discards some
	# of these channels, so it must not replace the new tree's materials.
	if OS.has_feature("web"):
		return
	for id in EXTERNAL_TREES:
		var path: String = EXTERNAL_TREES[id]
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("Failed to import CC BY forest model: " + path)
			continue
		var imported := packed.instantiate() as Node3D
		if imported == null:
			continue
		var fitted := Fitting.wrap_to_height(imported, 1.0)
		var surfaces: Dictionary = {}
		_collect_atlas_surfaces(fitted, Transform3D.IDENTITY, surfaces, false)
		var combined := ArrayMesh.new()
		for builder in surfaces.values():
			(builder as SurfaceTool).commit(combined)
		fitted.free()
		if combined.get_surface_count() >= 2:
			_mesh_library[id] = combined
		else:
			push_warning("Incomplete CC BY forest model (trunk/leaves): " + path)

func _bake_atlas_model(id: String) -> void:
	var source: Dictionary = _atlas_sources[id]
	var imported := Node3D.new()
	imported.transform = source["root_transform"]
	imported.add_child((source["prototype"] as Node3D).duplicate(7))
	var normalized := Fitting.wrap_to_height(imported,1.0)
	var surfaces: Dictionary = {}
	_collect_atlas_surfaces(normalized,Transform3D.IDENTITY,surfaces)
	var result := ArrayMesh.new()
	for tool in surfaces.values():
		(tool as SurfaceTool).commit(result)
	normalized.free()
	if result.get_surface_count()>0:
		_mesh_library[id] = result
		_atlas_batched[id] = true

func _collect_atlas_surfaces(node: Node, parent_transform: Transform3D, tools: Dictionary, apply_wind: bool = true) -> void:
	var relative := parent_transform
	if node is Node3D: relative = parent_transform*(node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var original: Material = mesh_node.get_active_material(surface)
				var key := 0 if original==null else original.get_instance_id()
				if not tools.has(key):
					var tool := SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					var material: Material = original
					if apply_wind and original is StandardMaterial3D:
						var wind := ShaderMaterial.new()
						wind.shader = load("res://shaders/forest_wind.gdshader")
						wind.set_shader_parameter("tint",(original as StandardMaterial3D).albedo_color)
						wind.set_shader_parameter("use_texture",(original as StandardMaterial3D).albedo_texture!=null)
						if (original as StandardMaterial3D).albedo_texture!=null:
							wind.set_shader_parameter("albedo_texture",(original as StandardMaterial3D).albedo_texture)
						material = wind
						_wind_materials.append(wind)
					tool.set_material(material)
					tools[key] = tool
				(tools[key] as SurfaceTool).append_from(mesh_node.mesh,surface,relative)
	for child in node.get_children(): _collect_atlas_surfaces(child,relative,tools,apply_wind)


func _place_atlas_model(parent: Node3D, id: String, x: float, z: float, height: float, angle: float) -> bool:
	if not _atlas_sources.has(id):
		return false
	var source: Dictionary = _atlas_sources[id]
	var imported := Node3D.new()
	imported.name = id
	imported.transform = source["root_transform"]
	# Duplicate only the named model subtree; GLB mesh/material resources are shared.
	imported.add_child((source["prototype"] as Node3D).duplicate(7))
	var visual: Node3D = Fitting.wrap_to_height(imported, height)
	var pivot := Node3D.new()
	pivot.name = id
	pivot.position = Vector3(x, ground_height(x, z), z)
	pivot.rotation.y = angle
	pivot.add_child(visual)
	parent.add_child(pivot)
	return true


func _atlas_tree(climate: Dictionary, roll: float) -> String:
	if float(climate["ridge"]) > 0.45 or float(climate["cool"]) > 0.62:
		return "q-pine-1" if roll < 0.50 else "q-pine-2"
	if float(climate["moss"]) > 0.50 or float(climate["elder"]) > 0.50:
		return "q-twisted-1" if roll < 0.46 else "q-twisted-2"
	if float(climate["amber"]) > 0.47:
		return "q-oak-wide" if roll < 0.57 else "q-oak-tall"
	return "q-birch-1" if roll < 0.34 else ("q-common-tree" if roll < 0.70 else "q-birch-2")


func _atlas_undergrowth(climate: Dictionary, roll: float) -> String:
	if float(climate["violet"]) > 0.48:
		return "q-blue-flowers" if roll < 0.58 else "q-white-flowers"
	if float(climate["moss"]) > 0.52 or float(climate["elder"]) > 0.56:
		return "q-fern" if roll < 0.67 else "q-bush"
	if float(climate["openness"]) > 0.55:
		return "q-clover" if roll < 0.48 else "q-flowering-bush"
	return "q-short-grass" if roll < 0.4 else ("q-wispy-grass" if roll < 0.76 else "q-tall-grass")


func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh(child)
		if result != null:
			return result
	return null

func river_center(x: float) -> float:
	return 9.0 + sin(x * 0.035) * 1.25 + sin(x * 0.095) * 0.34

func river_half_width(x: float) -> float:
	return 4.25 + sin(x * 0.021 + 0.8) * 0.36

func ground_height(x: float, z: float) -> float:
	var d := absf(z - river_center(x))
	var bank := smoothstep(river_half_width(x) - 0.72, river_half_width(x) + 2.05, d)
	var ripples := sin(x * 0.35 + z * 0.23) * 0.10 + sin(x * 0.69 - z * 0.45) * 0.048
	var distance := Vector2(x, z - 18.0).length()
	var hills := (sin(x * 0.019 + z * 0.026) * 0.21 + sin(x * 0.040 - z * 0.022) * 0.12) * smoothstep(30.0, 95.0, distance)
	# За границей первой главы рельеф становится разнообразнее.
	var frontier := smoothstep(95.0, 250.0, distance)
	var wild_hills := _noise.get_noise_2d(x, z) * frontier * 8.0
	# Каменные увалы и мягкие моховые ложбины образуют дальний горизонт.
	# Вдоль первой главы прежняя высота земли и работа моста сохраняются.
	var ridge := _region_weight(x, z, 70.0, 114.0, 59.0, 58.0)
	var moss := _region_weight(x, z, -65.0, 29.0, 47.0, 43.0)
	var relief := ridge * (2.6 + _noise.get_noise_2d(x + 187.0, z - 43.0) * 3.3) - moss * 0.30
	var original := 0.06 + (ripples + hills + wild_hills + relief) * bank - (1.0 - bank) * 1.12
	return original if OS.has_feature("web") else GEO.shape_height(x,z,original)

func _make_regional_water() -> void:
	for lake in GEO.LAKES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(_water_material)
		var center: Vector2 = lake["center"]
		var radius: Vector2 = lake["radii"]
		for i in range(72):
			var a := TAU*float(i)/72.0
			var b := TAU*float(i+1)/72.0
			for p in [center,center+Vector2(cos(b),sin(b))*radius,center+Vector2(cos(a),sin(a))*radius]:
				st.set_uv(p*0.12)
				st.add_vertex(Vector3(p.x,float(lake["level"])+0.02,p.y))
		st.generate_normals()
		st.generate_tangents()
		var water := MeshInstance3D.new()
		water.name = str(lake["name"])
		water.mesh = st.commit()
		water.visibility_range_end = 230.0
		add_child(water)
	# Дальняя большая вода — ориентир горизонта, за пределом игровой карты.
	var horizon := MeshInstance3D.new()
	var sea := PlaneMesh.new()
	sea.size = Vector2(250,420)
	horizon.mesh = sea
	horizon.position = Vector3(340,-0.6,30)
	horizon.material_override = _water_material
	horizon.name = "Дальняя большая вода · Ладога"
	add_child(horizon)

func set_weather_wetness(value: float, delta: float = 0.016667) -> void:
	var next_wetness := move_toward(_wetness, clampf(value, 0.0, 1.0), maxf(delta, 0.0) * 0.42)
	if is_equal_approx(next_wetness, _wetness):
		return
	_wetness = next_wetness
	if _grass_detailed != null:
		_grass_detailed.set_shader_parameter("wetness", _wetness)
	for material in _wind_materials:
		material.set_shader_parameter("wind_strength", lerpf(0.45, 1.7, _wetness))

func set_quality(enabled: bool) -> void:
	if enabled and _atlas_roots.is_empty():
		_load_stylized_atlases()
	if high_quality == enabled:
		return
	high_quality = enabled
	# Keep the original textured ground in both modes. Quality controls
	# chunk radius and plant density, so switching never erases textures.
	_grass_material = _grass_detailed if _grass_detailed != null else _grass_basic
	for chunk in _loaded.values():
		chunk.queue_free()
	_loaded.clear()
	_colliders.clear()
	navigation_revision += 1
	_glades.clear()
	_pending.clear()
	_active_build.clear()
	_center_cell = Vector2i(999999, 999999)

func update_stream(player_position: Vector3) -> void:
	var radius: int = VIEW_RADIUS_HIGH if high_quality else VIEW_RADIUS_LOW
	var cell := Vector2i(floori(player_position.x / CHUNK_SIZE), floori(player_position.z / CHUNK_SIZE))
	if cell != _center_cell:
		_center_cell = cell
		var wanted: Dictionary = {}
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var pos := cell + Vector2i(dx, dz)
				wanted[pos] = true
				if not _loaded.has(pos) and not _pending.has(pos):
					_pending.append(pos)
		_pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - cell).length_squared() < (b - cell).length_squared()
		)
		for key in _loaded.keys():
			if not wanted.has(key):
				_loaded[key].queue_free()
				_loaded.erase(key)
				if _colliders.erase(key):
					navigation_revision += 1
				_glades.erase(key)
		for key in _pending.duplicate():
			if not wanted.has(key):
				_pending.erase(key)
		if not _active_build.is_empty() and not wanted.has(_active_build["cell"]):
			_active_build.clear()
	# Каждая операция (рельеф, река, тропы, растения) проходит в отдельном кадре.
	# В браузере это уменьшает задержку при переходе между участками карты.
	if _active_build.is_empty() and not _pending.is_empty():
		_begin_chunk(_pending.pop_front())
	if not _active_build.is_empty():
		_step_chunk()

func _begin_chunk(cell: Vector2i) -> void:
	var parent := Node3D.new()
	parent.name = "Чанк_%d_%d" % [cell.x, cell.y]
	add_child(parent)
	_loaded[cell] = parent
	_active_build = {"cell": cell, "parent": parent, "phase": 0}

func _step_chunk() -> void:
	var cell: Vector2i = _active_build["cell"]
	var parent: Node3D = _active_build["parent"]
	if not is_instance_valid(parent):
		_active_build.clear()
		return
	match int(_active_build["phase"]):
		0: _make_terrain(parent, cell)
		1: _make_river(parent, cell)
		2: _make_paths(parent, cell)
		3: _make_vegetation(parent, cell)
		4: _make_water_plants(parent, cell)
		5: _make_micro_glade(parent, cell)
		6: _make_biome_details(parent, cell)
		7: _make_world_places(parent, cell)
	var next_phase: int = int(_active_build["phase"]) + 1
	if next_phase >= 8:
		_active_build.clear()
	else:
		_active_build["phase"] = next_phase

func climate_at(x: float, z: float) -> Dictionary:
	# Плавные климатические величины (0..1), а не жёсткие границы зон.
	var distance := Vector2(x, z - 18.0).length()
	var river_distance := absf(z - river_center(x)) - river_half_width(x)
	var moisture := 1.0 - smoothstep(3.0, 21.0, river_distance)
	var cool := smoothstep(43.0, 125.0, z + _canopy_noise.get_noise_2d(x, z) * 21.0 - minf(0.0, x + 70.0) * 0.25)
	var openness := smoothstep(-0.08, 0.42, _soil_noise.get_noise_2d(x + 241.0, z + 317.0)) * (1.0 - moisture * 0.55)
	var stone := smoothstep(115.0, 245.0, distance) * smoothstep(-0.30, 0.55, _soil_noise.get_noise_2d(x + 50.0, z - 150.0))
	var groves := clampf((_canopy_noise.get_noise_2d(x, z) + 1.0) * 0.5, 0.0, 1.0)
	var amber := _region_weight(x, z, -52.0, -66.0, 55.0, 47.0)
	var moss := _region_weight(x, z, -65.0, 29.0, 47.0, 43.0)
	var violet := _region_weight(x, z, -53.0, 97.0, 61.0, 55.0)
	var bloom := _region_weight(x, z, 59.0, -10.0, 54.0, 50.0)
	var ridge := _region_weight(x, z, 70.0, 114.0, 59.0, 58.0)
	var elder := _region_weight(x, z, 8.0, 104.0, 47.0, 54.0)
	return {
		"moisture": moisture, "cool": cool, "openness": openness,
		"stone": stone, "groves": groves, "amber": amber,
		"moss": moss, "violet": violet, "bloom": bloom,
		"ridge": ridge, "elder": elder
	}

func _region_weight(x: float, z: float, cx: float, cz: float, rx: float, rz: float) -> float:
	# Плавная эллиптическая маска: соседние биомы не имеют видимых швов.
	# За пределами эллипса сразу возвращаем ноль. Большинство точек мира
	# лежит далеко от этих мест; шесть дорогих smoothstep им не нужны.
	var dx := x - cx
	var dz := z - cz
	if absf(dx) > rx * 1.075 or absf(dz) > rz * 1.075:
		return 0.0
	var nx := dx / rx
	var nz := dz / rz
	return 1.0 - smoothstep(0.18, 1.15, nx * nx + nz * nz)

func biome_at(x: float, z: float) -> String:
	var climate := climate_at(x, z)
	if float(climate["ridge"]) > 0.55:
		return "wind_ridge"
	if float(climate["violet"]) > 0.58:
		return "violet_heath"
	if float(climate["amber"]) > 0.55:
		return "amber_wood"
	if float(climate["moss"]) > 0.55:
		return "mosswood"
	if float(climate["bloom"]) > 0.68:
		return "bloom_garden"
	if float(climate["moisture"]) > 0.65:
		return "riverbank"
	if float(climate["stone"]) > 0.58:
		return "highland"
	if float(climate["cool"]) > 0.61:
		return "pine"
	if float(climate["openness"]) > 0.56:
		return "meadow"
	return "old_forest"

func _terrain_tint(x: float, z: float, climate: Dictionary = {}) -> Color:
	if climate.is_empty():
		climate = climate_at(x, z)
	var result := Color("#789764")
	result = result.lerp(Color("#5f8769"), float(climate["moisture"]) * 0.52)
	result = result.lerp(Color("#708e79"), float(climate["cool"]) * 0.38)
	result = result.lerp(Color("#8c8975"), float(climate["stone"]) * 0.40)
	result = result.lerp(Color("#a6ba79"), float(climate["openness"]) * (1.0 - float(climate["moisture"])) * 0.42)
	result = result.lerp(Color("#b0a363"), float(climate["amber"]) * 0.61)
	result = result.lerp(Color("#51846b"), float(climate["moss"]) * 0.68)
	result = result.lerp(Color("#9e96af"), float(climate["violet"]) * 0.59)
	result = result.lerp(Color("#b3bc80"), float(climate["bloom"]) * 0.52)
	result = result.lerp(Color("#90928e"), float(climate["ridge"]) * 0.62)
	result = result.lerp(Color("#487a62"), float(climate["elder"]) * 0.57)
	var flecks := _soil_noise.get_noise_2d(x * 1.8, z * 1.8) * 0.045
	var colored := result.darkened(maxf(0.0, -flecks)).lightened(maxf(0.0, flecks))
	colored.a = clampf(float(climate["openness"]) * 0.75 + 0.14, 0.0, 1.0)
	return colored

func _hash01(ix: int, iz: int, salt: int) -> float:
	# Все кандидаты привязаны к мировой сетке. При загрузке соседних чанков
	# их положение не зависит от порядка создания этих чанков.
	var value: int = (ix * 73856093) ^ (iz * 19349663) ^ (salt * 83492791)
	value = value & 0x7fffffff
	value = (value * 1103515245 + 12345) & 0x7fffffff
	value = value ^ (value >> 13)
	return float(value & 0x7fffffff) / 2147483647.0

func path_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var closest := 99999.0
	for route in PATH_ROUTES + ([] if OS.has_feature("web") else GEO.ROUTES):
		for i in range(route.size() - 1):
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(0.01, ab.length_squared()), 0.0, 1.0)
			closest = minf(closest, p.distance_to(a + ab * t))
	return closest

func _make_terrain(parent: Node3D, cell: Vector2i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_grass_material)
	var start_x := float(cell.x * CHUNK_SIZE)
	var start_z := float(cell.y * CHUNK_SIZE)
	var step := float(CHUNK_SIZE) / GRID
	# The original triangles deliberately have separate vertices, preserving
	# their normals. Only the expensive height/noise/color calculations are
	# shared between adjacent triangles.
	var stride := GRID + 1
	var positions: Array[Vector3] = []
	var colors: Array[Color] = []
	var biome_weights: Array[Vector2] = []
	positions.resize(stride * stride)
	colors.resize(stride * stride)
	biome_weights.resize(stride * stride)
	for iz in range(stride):
		for ix in range(stride):
			var x := start_x + ix * step
			var z := start_z + iz * step
			var index := iz * stride + ix
			positions[index] = Vector3(x, ground_height(x, z), z)
			var climate := climate_at(x, z)
			colors[index] = _terrain_tint(x, z, climate)
			# Encode forest-floor and stone exposure in UV2; the shader uses
			# them to blend distinct CC0 materials without a second terrain mesh.
			var forest_weight := clampf(float(climate["groves"]) * 0.75 + float(climate["moss"]) * 0.30 + float(climate["elder"]) * 0.25 + float(climate["amber"]) * 0.18 - float(climate["openness"]) * 0.36, 0.0, 1.0)
			var stone_weight := clampf(float(climate["stone"]) * 0.82 + float(climate["ridge"]) * 0.49, 0.0, 1.0)
			biome_weights[index] = Vector2(forest_weight, stone_weight)
	for iz in range(GRID):
		for ix in range(GRID):
			var a := iz * stride + ix
			var b := a + 1
			var c := a + stride
			var d := c + 1
			_add_cached_vertex(st, positions[a], colors[a], biome_weights[a])
			_add_cached_vertex(st, positions[c], colors[c], biome_weights[c])
			_add_cached_vertex(st, positions[b], colors[b], biome_weights[b])
			_add_cached_vertex(st, positions[b], colors[b], biome_weights[b])
			_add_cached_vertex(st, positions[c], colors[c], biome_weights[c])
			_add_cached_vertex(st, positions[d], colors[d], biome_weights[d])
	st.generate_normals()
	st.generate_tangents() # Required by the PBR grass normal map.
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	terrain.name = "Земля"
	parent.add_child(terrain)

func _add_cached_vertex(st: SurfaceTool, pos: Vector3, tint: Color, biome: Vector2) -> void:
	st.set_uv(Vector2(pos.x * 0.1, pos.z * 0.1))
	st.set_uv2(biome)
	st.set_color(tint)
	st.add_vertex(pos)

func _make_river(parent: Node3D, cell: Vector2i) -> void:
	var middle_x := (float(cell.x) + 0.5) * CHUNK_SIZE
	var z0 := float(cell.y * CHUNK_SIZE)
	var z1 := z0 + CHUNK_SIZE
	var center := river_center(middle_x)
	if center + 8.0 < z0 or center - 8.0 > z1:
		return
	var water_surface := SurfaceTool.new()
	water_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	water_surface.set_material(_water_material)
	var left_bank := SurfaceTool.new()
	left_bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	left_bank.set_material(_bank_material)
	var right_bank := SurfaceTool.new()
	right_bank.begin(Mesh.PRIMITIVE_TRIANGLES)
	right_bank.set_material(_bank_material)
	var subdivisions := 20
	var interval := float(CHUNK_SIZE) / float(subdivisions)
	for i in range(subdivisions):
		var x0 := float(cell.x * CHUNK_SIZE) + float(i) * interval
		var x1 := x0 + interval
		_river_segment(water_surface, x0, x1, 0.0, -0.55)
		_river_segment(left_bank, x0, x1, -1.0, 0.015)
		_river_segment(right_bank, x0, x1, 1.0, 0.015)
	for st in [water_surface, left_bank, right_bank]:
		st.generate_normals()
		st.generate_tangents()
		var item := MeshInstance3D.new()
		item.name = "Вода" if st == water_surface else "Природный берег"
		item.mesh = st.commit()
		parent.add_child(item)

func _river_segment(st: SurfaceTool, x0: float, x1: float, side: float, y_offset: float) -> void:
	var positions: Array[Vector3] = []
	for x in [x0, x1]:
		var z := river_center(x)
		var half := river_half_width(x)
		var left := z - half
		var right := z + half
		if side < 0.0:
			left = z - half - 1.25
			right = z - half + 0.10
		elif side > 0.0:
			left = z + half - 0.10
			right = z + half + 1.25
		for z_edge in [left, right]:
			var y := -0.55 if is_zero_approx(side) else ground_height(x, z_edge) + y_offset
			positions.append(Vector3(x, y, z_edge))
	# Верхняя сторона поверхности ориентирована к солнцу.
	for index in [0, 1, 2, 2, 1, 3]:
		var v: Vector3 = positions[index]
		st.set_uv(Vector2(v.x * 0.12, v.z * 0.12))
		st.add_vertex(v)

func _make_paths(parent: Node3D, cell: Vector2i) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_path_material)
	var created := 0
	var min_x := float(cell.x * CHUNK_SIZE) - 2.0
	var max_x := min_x + CHUNK_SIZE + 4.0
	var min_z := float(cell.y * CHUNK_SIZE) - 2.0
	var max_z := min_z + CHUNK_SIZE + 4.0
	for route in PATH_ROUTES + ([] if OS.has_feature("web") else GEO.ROUTES):
		for i in range(route.size() - 1):
			var a: Vector2 = route[i]
			var b: Vector2 = route[i + 1]
			var length := a.distance_to(b)
			var parts := maxi(2, ceili(length / 1.25))
			for j in range(parts):
				var start := a.lerp(b, float(j) / parts)
				var finish := a.lerp(b, float(j + 1) / parts)
				var center := (start + finish) * 0.5
				if center.x < min_x or center.x > max_x or center.y < min_z or center.y > max_z:
					continue
				var dir := (finish - start).normalized()
				var across := Vector2(-dir.y, dir.x)
				var width := 1.38 + sin(float(j) * 0.73 + float(i) * 2.1) * 0.17
				var p0 := start + across * width
				var p1 := start - across * width
				var p2 := finish + across * width
				var p3 := finish - across * width
				var corners := [p0, p1, p2, p3]
				for index in [0, 2, 1, 2, 3, 1]:
					var v: Vector2 = corners[index]
					var height := ground_height(v.x, v.y) + 0.08
					st.set_uv(Vector2(v.x * 0.22, v.y * 0.22))
					st.add_vertex(Vector3(v.x, height, v.y))
				created += 1
	if created > 0:
		st.generate_normals()
		st.generate_tangents() # Gravel normal map needs UV tangents as well.
		var path_mesh := MeshInstance3D.new()
		path_mesh.name = "Лесные тропы"
		path_mesh.mesh = st.commit()
		parent.add_child(path_mesh)

func _make_vegetation(parent: Node3D, cell: Vector2i) -> void:
	var collection: Dictionary = {}
	var obstacles: Array[Vector3] = []
	var glade := _glade_site(cell)
	# Деревья не рассыпаются случайными точками: мировая сетка задаёт
	# минимальный шаг, а шум формирует рощи и открытые солнечные поляны.
	for iz in range(TREE_CELLS):
		for ix in range(TREE_CELLS):
			var gx := cell.x * TREE_CELLS + ix
			var gz := cell.y * TREE_CELLS + iz
			var x := float(gx * TREE_GRID) + 2.0 + (_hash01(gx, gz, 1) - 0.5) * 1.5
			var z := float(gz * TREE_GRID) + 2.0 + (_hash01(gx, gz, 2) - 0.5) * 1.5
			if not OS.has_feature("web") and (not GEO.lake_at(x,z,2.5).is_empty() or GEO.clearance(x,z)):
				continue
			if absf(z - river_center(x)) < river_half_width(x) + 4.1:
				continue
			if path_distance(x, z) < 3.3 or _landmark_clearance(x, z) or _world_place_clearance(x, z):
				continue
			if not glade.is_empty() and Vector2(x, z).distance_squared_to(glade["pos"]) < 5.2 * 5.2:
				continue
			var climate := climate_at(x, z)
			var groves: float = climate["groves"]
			var openness: float = climate["openness"]
			var stone: float = climate["stone"]
			var density := (0.43 if high_quality else 0.32) * (0.55 + groves * 1.0) * (1.0 - openness * 0.62) * (1.0 - stone * 0.28)
			if _hash01(gx, gz, 3) > clampf(density, 0.04, 0.75):
				continue
			var species := _choose_tree(climate, _hash01(gx, gz, 4))
			var height := lerpf(4.5, 7.6, _hash01(gx, gz, 5))
			var angle := _hash01(gx, gz, 6) * TAU
			# Detailed mode uses batched Quaternius trees throughout the forest.
			# Keep the old low-poly tree meshes only as a safe fallback for
			# economy mode or a missing external atlas.
			if high_quality:
				var atlas_id := _atlas_tree(climate, _hash01(gx, gz, 72))
				if _atlas_batched.has(atlas_id):
					species = atlas_id
				# One in five canopy candidates gets the richer, independently
				# licensed PBR tree when the verified files were imported.
				# All choices remain seeded and deterministic across chunk loads.
				if _mesh_library.has("pbr-pine") and _hash01(gx, gz, 76) < 0.20 and stone < 0.58:
					species = "pbr-pine"
			_append_entry(collection, species, x, z, height, angle)
			obstacles.append(Vector3(x, 0.65, z))
	# Подлесок тоже имеет пятна: грибы под кронами, цветы на полянах,
	# осока у ручья, валуны на сухих возвышенностях.
	for iz in range(UNDERGROWTH_CELLS):
		for ix in range(UNDERGROWTH_CELLS):
			var gx := cell.x * UNDERGROWTH_CELLS + ix
			var gz := cell.y * UNDERGROWTH_CELLS + iz
			var x := float(gx * UNDERGROWTH_GRID) + 1.0 + (_hash01(gx, gz, 11) - 0.5) * 0.9
			var z := float(gz * UNDERGROWTH_GRID) + 1.0 + (_hash01(gx, gz, 12) - 0.5) * 0.9
			if not OS.has_feature("web") and (not GEO.lake_at(x,z,0.6).is_empty() or GEO.clearance(x,z)):
				continue
			var river_distance := absf(z - river_center(x)) - river_half_width(x)
			if river_distance < 0.35 or path_distance(x, z) < 1.45 or _world_place_core(x, z):
				continue
			if not glade.is_empty() and Vector2(x, z).distance_squared_to(glade["pos"]) < 2.8 * 2.8:
				continue
			var climate := climate_at(x, z)
			var groves: float = climate["groves"]
			var openness: float = climate["openness"]
			var stone: float = climate["stone"]
			var density := (0.69 if high_quality else 0.43) * (0.56 + groves * 0.70 + openness * 0.45) * (1.0 - stone * 0.16)
			density += 0.18 * maxf(float(climate["violet"]), maxf(float(climate["moss"]), float(climate["bloom"])))
			if _hash01(gx, gz, 13) > clampf(density, 0.10, 0.90):
				continue
			var species := _choose_understory(climate, river_distance, _hash01(gx, gz, 14))
			var height := lerpf(0.33, 1.22, _hash01(gx, gz, 15))
			if ROCK_TYPES.has(species):
				if _landmark_clearance(x, z):
					continue
				height = lerpf(0.55, 2.0, _hash01(gx, gz, 16))
				if height > 1.4:
					obstacles.append(Vector3(x, 0.85, z))
			elif species == "plant-flattall" or species == "grass-large":
				height *= 1.35
			var angle := _hash01(gx, gz, 17) * TAU
			if high_quality and not ROCK_TYPES.has(species) and _hash01(gx, gz, 73) < 0.58:
				var atlas_id := _atlas_undergrowth(climate, _hash01(gx, gz, 74))
				if _atlas_batched.has(atlas_id): species = atlas_id
			_append_entry(collection, species, x, z, height, angle)
	_colliders[cell] = obstacles
	navigation_revision += 1
	_flush_instances(parent, collection)

func _choose_tree(climate: Dictionary, roll: float) -> String:
	var stone: float = climate["stone"]
	var cool: float = climate["cool"]
	var wetness: float = climate["moisture"]
	if float(climate["elder"]) > 0.52:
		return "tree-detailed-dark" if roll < 0.71 else "tree-oak-dark"
	if float(climate["moss"]) > 0.50:
		return "tree-detailed-dark" if roll < 0.57 else "tree-fat"
	if float(climate["amber"]) > 0.51:
		return "tree-oak-dark" if roll < 0.46 else ("tree-tall" if roll < 0.73 else "tree-oak")
	if float(climate["ridge"]) > 0.49:
		return "tree-pinetallb" if roll < 0.54 else "tree-pinesmalla"
	if float(climate["violet"]) > 0.51:
		return "tree-pinerounda" if roll < 0.42 else "tree-detailed"
	if float(climate["bloom"]) > 0.53:
		return "tree-small" if roll < 0.44 else "tree-fat"
	if roll < stone * 0.33:
		return "tree-pinetalla"
	if roll < stone * 0.33 + cool * 0.51:
		return "tree-pinesmalla" if roll < 0.42 else "tree-pinerounda"
	if roll < stone * 0.33 + cool * 0.51 + wetness * 0.32:
		return "tree-detailed"
	return "tree-oak" if roll < 0.78 else "tree-fat"

func _choose_understory(climate: Dictionary, river_distance: float, roll: float) -> String:
	var moisture: float = climate["moisture"]
	var cool: float = climate["cool"]
	var openness: float = climate["openness"]
	var stone: float = climate["stone"]
	if float(climate["violet"]) > 0.53:
		return "flower-purpleb" if roll < 0.54 else ("flower-purplea" if roll < 0.81 else "plant-flatshort")
	if float(climate["amber"]) > 0.56:
		return "flower-yellowb" if roll < 0.41 else ("grass-leafs" if roll < 0.69 else "mushroom-tangroup")
	if float(climate["moss"]) > 0.55 or float(climate["elder"]) > 0.62:
		return "mushroom-redgroup" if roll < 0.29 else ("plant-bushdetailed" if roll < 0.65 else "hanging-moss")
	if float(climate["ridge"]) > 0.51:
		return "rock-smallb" if roll < 0.55 else ("grass-large" if roll < 0.83 else "rock-talla")
	if float(climate["bloom"]) > 0.60:
		return "flower-redb" if roll < 0.32 else ("flower-yellowa" if roll < 0.66 else "flower-purplea")
	if river_distance < 4.7 and roll < 0.83:
		return "plant-flattall" if roll < 0.42 else "grass-large"
	if roll < stone * 0.44:
		return ROCK_TYPES[int(roll * 27.0) % ROCK_TYPES.size()]
	if roll < stone * 0.44 + openness * 0.55:
		return ["flower-purplea", "flower-yellowa", "flower-reda"][int(roll * 41.0) % 3]
	if roll < stone * 0.44 + openness * 0.55 + cool * 0.27:
		return "mushroom-tangroup" if roll < 0.23 else "mushroom-redgroup"
	if moisture > 0.5 and roll < 0.82:
		return "plant-bushlarge"
	return "grass" if roll < 0.60 else "plant-bushlarge"

func _make_water_plants(parent: Node3D, cell: Vector2i) -> void:
	var collection: Dictionary = {}
	var z_min := float(cell.y * CHUNK_SIZE)
	var z_max := z_min + CHUNK_SIZE
	for i in range(WATER_CELLS):
		var gx := cell.x * WATER_CELLS + i
		var x := float(gx * 4) + 2.0
		var center := river_center(x)
		var width := river_half_width(x)
		var side := -1.0 if _hash01(gx, 0, 41) < 0.5 else 1.0
		var z := center + side * width * lerpf(0.27, 0.77, _hash01(gx, 0, 42))
		if z >= z_min and z < z_max and _hash01(gx, 0, 43) < 0.65:
			_append_entry(collection, "lily-small" if _hash01(gx, 0, 44) < 0.75 else "lily-large", x, z, 0.48, _hash01(gx, 0, 45) * TAU, true)
		# Отдельные камни лежат на берегах, а не по центру реки.
		for bank_side in [-1.0, 1.0]:
			var bank_z: float = center + bank_side * (width + 1.7)
			if bank_z >= z_min and bank_z < z_max and _hash01(gx, int(bank_side), 46) < 0.32:
				_append_entry(collection, "rock-smalla", x, bank_z, 0.65, _hash01(gx, int(bank_side), 47) * TAU)
	_flush_instances(parent, collection)

func _glade_site(cell: Vector2i) -> Dictionary:
	# Одна и та же расчистка используется при посадке леса и создании
	# декоративного уголка. Роща не зарастает сквозь каменный круг.
	if _hash01(cell.x, cell.y, 61) > 0.17:
		return {}
	var x := (float(cell.x) + 0.5) * CHUNK_SIZE + (_hash01(cell.x, cell.y, 62) - 0.5) * 13.0
	var z := (float(cell.y) + 0.5) * CHUNK_SIZE + (_hash01(cell.x, cell.y, 63) - 0.5) * 13.0
	if _landmark_clearance(x, z) or path_distance(x, z) < 5.0:
		return {}
	if absf(z - river_center(x)) < river_half_width(x) + 8.0:
		return {}
	var stones := _hash01(cell.x, cell.y, 64) < 0.40
	return {
		"id": "forest-secret-%d-%d" % [cell.x, cell.y],
		"pos": Vector2(x, z),
		"name": "Древний круг камней" if stones else "Тихая грибная поляна",
		"stones": stones
	}

func _make_micro_glade(parent: Node3D, cell: Vector2i) -> void:
	var site := _glade_site(cell)
	if site.is_empty():
		return
	var center: Vector2 = site["pos"]
	var x := center.x
	var z := center.y
	var stones: bool = site["stones"]
	_glades[cell] = site
	var collection: Dictionary = {}
	_append_entry(collection, "rock-largea" if stones else "stump-rounddetailed", x, z, 1.1, _hash01(cell.x, cell.y, 65) * TAU)
	for i in range(7):
		var angle := TAU * i / 7.0
		var radius := 1.7 + _hash01(cell.x, cell.y, 70 + i) * 1.5
		var px := x + cos(angle) * radius
		var pz := z + sin(angle) * radius
		var name := "rock-smalla" if stones and i % 2 == 0 else ("mushroom-tangroup" if i % 3 == 0 else "flower-purplea")
		_append_entry(collection, name, px, pz, 0.45 + _hash01(cell.x, cell.y, 80 + i) * 0.4, angle)
	_flush_instances(parent, collection)

func _world_place_clearance(x: float, z: float) -> bool:
	for place in WORLD_PLACES:
		var center: Vector2 = place["pos"]
		var radius: float = place["radius"]
		if Vector2(x, z).distance_squared_to(center) < radius * radius:
			return true
	return false

func _world_place_core(x: float, z: float) -> bool:
	for place in WORLD_PLACES:
		var center: Vector2 = place["pos"]
		if Vector2(x, z).distance_squared_to(center) < 3.6 * 3.6:
			return true
	return false

func _make_biome_details(parent: Node3D, cell: Vector2i) -> void:
	# Цветовые поля, папоротниковые низины и каменные россыпи.
	# Одна разновидность = один MultiMesh; детализация одинакова в обоих режимах.
	var collection: Dictionary = {}
	for iz in range(7):
		for ix in range(7):
			var gx := cell.x * 7 + ix
			var gz := cell.y * 7 + iz
			var x := float(cell.x * CHUNK_SIZE + ix * 4) + 1.2 + _hash01(gx, gz, 91) * 1.9
			var z := float(cell.y * CHUNK_SIZE + iz * 4) + 1.2 + _hash01(gx, gz, 92) * 1.9
			if path_distance(x, z) < 2.7 or _landmark_clearance(x, z) or _world_place_core(x, z):
				continue
			if absf(z - river_center(x)) < river_half_width(x) + 1.1:
				continue
			var climate := climate_at(x, z)
			var intensity := maxf(float(climate["amber"]), float(climate["violet"]))
			intensity = maxf(intensity, maxf(float(climate["moss"]), float(climate["bloom"])))
			intensity = maxf(intensity, maxf(float(climate["ridge"]), float(climate["elder"])))
			if _hash01(gx, gz, 93) > intensity * 0.77:
				continue
			var species := _choose_understory(climate, 12.0, _hash01(gx, gz, 94))
			var height := 0.38 + _hash01(gx, gz, 95) * 0.85
			if ROCK_TYPES.has(species):
				height *= 1.25
			_append_entry(collection, species, x, z, height, _hash01(gx, gz, 96) * TAU)
	_flush_instances(parent, collection)

func _make_world_places(parent: Node3D, cell: Vector2i) -> void:
	for place in WORLD_PLACES:
		var center: Vector2 = place["pos"]
		var owner_cell := Vector2i(floori(center.x / CHUNK_SIZE), floori(center.y / CHUNK_SIZE))
		if owner_cell != cell:
			continue
		var kind: String = place["kind"]
		var collection: Dictionary = {}
		match kind:
			"amber":
				if not high_quality or not _atlas_sources.has("q-oak-wide"):
					_append_entry(collection, "tree-oak-dark", center.x, center.y, 19.0, 0.3)
				_append_scenic_ring(collection, center, "tree-tall", 5, 8.6, 11.0, 0.7)
				_append_scenic_ring(collection, center, "flower-yellowb", 22, 5.3, 1.1, 0.1)
				_append_scenic_ring(collection, center, "mushroom-tangroup", 9, 3.2, 1.25, 0.4)
			"moss":
				if not high_quality or not _atlas_sources.has("q-twisted-2"):
					_append_entry(collection, "tree-detailed-dark", center.x + 0.9, center.y, 18.0, 0.8)
				_append_scenic_ring(collection, center, "rock-largeb", 9, 5.9, 2.4, 0.1)
				_append_scenic_ring(collection, center, "hanging-moss", 17, 7.5, 1.55, 0.3)
				_append_scenic_ring(collection, center, "mushroom-redgroup", 12, 3.7, 1.2, 0.2)
			"violet":
				if not high_quality or not _atlas_sources.has("q-birch-2"):
					_append_entry(collection, "tree-detailed", center.x - 1.4, center.y + 0.8, 13.0, 1.5)
				_append_scenic_ring(collection, center, "tree-pinerounda", 5, 9.4, 8.5, 0.8)
				_append_scenic_ring(collection, center, "flower-purpleb", 37, 6.0, 1.2, 0.1)
				_append_scenic_ring(collection, center, "flower-redb", 18, 3.8, 0.72, 0.6)
			"hamlet":
				_append_entry(collection, "tree-oak-dark", center.x, center.y + 1.1, 18.0, 1.2)
				_append_scenic_ring(collection, center, "path-stone", 14, 4.0, 0.25, 0.2)
				_append_scenic_ring(collection, center, "flower-yellowa", 16, 8.4, 0.8, 0.5)
				_append_scenic_ring(collection, center, "log-stack", 4, 7.2, 1.1, 0.6)
				# Two real houses anchor the hamlet; the other shelters remain tents.
				var has_houses := true
				for module_name in ["Wall_Plaster_Straight", "Wall_Plaster_Door_Flat", "Wall_Plaster_Window_Wide_Flat", "Roof_RoundTiles_6x6"]:
					if not ResourceLoader.exists("res://assets/buildings/village/%s.gltf" % module_name):
						has_houses = false
				for i in range(4):
					var angle := (float(i) + 0.23) * TAU / 4.0
					var px := center.x + cos(angle) * 6.5
					var pz := center.y + sin(angle) * 6.5
					if has_houses and i % 2 == 0:
						var cottage = load("res://scripts/construction.gd").new()
						cottage.appearance = "cottage"
						cottage.variant = i + 8
						cottage.name = "Домик Корневой слободы"
						cottage.position = Vector3(px, ground_height(px, pz), pz)
						cottage.rotation.y = angle + PI
						cottage.scale = Vector3.ONE * (0.77 if i == 0 else 0.88)
						parent.add_child(cottage)
						cottage.set_stage(5)
						_add_place_obstacle(cell, px, pz, 2.8)
					else:
						_place_scenic_scene(parent, "tent-smallopen", px, pz, angle + PI, 2.4)
						_add_place_obstacle(cell, px, pz, 1.7)
			"ridge":
				_append_scenic_ring(collection, center, "rock-talla", 6, 9.1, 6.8, 0.25)
				_append_scenic_ring(collection, center, "grass-large", 16, 6.5, 0.77, 0.5)
				_append_entry(collection, "rock-largea", center.x - 4.0, center.y, 7.0, 0.1)
				_append_entry(collection, "rock-largeb", center.x + 4.0, center.y, 7.5, 0.6)
				_add_place_obstacle(cell, center.x - 4.0, center.y, 2.4)
				_add_place_obstacle(cell, center.x + 4.0, center.y, 2.4)
				_place_rock_arch(parent, center)
			"elder":
				if not high_quality or not _atlas_sources.has("q-oak-tall"):
					_append_entry(collection, "tree-detailed-dark", center.x, center.y, 23.0, 0.45)
				_append_scenic_ring(collection, center, "rock-smalla", 11, 6.5, 1.2, 0.1)
				_append_scenic_ring(collection, center, "mushroom-redgroup", 13, 4.2, 1.65, 0.4)
				_append_scenic_ring(collection, center, "plant-bushdetailed", 10, 8.9, 1.7, 0.6)
		_flush_instances(parent, collection)
		# Named Quaternius hero trees make six landmarks distinguishable;
		# they share the imported atlas rather than reloading its 5 MB GLB.
		if high_quality and kind in ["amber", "moss", "violet", "elder"]:
			var centerpiece := "q-oak-wide" if kind == "amber" else ("q-twisted-2" if kind == "moss" else ("q-birch-2" if kind == "violet" else "q-oak-tall"))
			_place_atlas_model(parent, centerpiece, center.x, center.y, 13.0 if kind == "violet" else 19.0, 0.45)
		if kind != "ridge":
			for i in range(3):
				var angle := (float(i) + 0.3) * TAU / 3.0
				_place_scenic_scene(parent, "lantern-glass", center.x + cos(angle) * 4.3, center.y + sin(angle) * 4.3, angle, 1.6)
		if kind == "amber" or kind == "moss" or kind == "violet" or kind == "elder":
			_add_place_obstacle(cell, center.x, center.y, 2.1)
		if kind != "ridge":
			_make_firefly_motes(parent, cell, center, 17 if kind == "elder" else 11)
		navigation_revision += 1

func _append_scenic_ring(collection: Dictionary, center: Vector2, species: String, amount: int, radius: float, height: float, phase: float) -> void:
	for i in range(amount):
		var angle := TAU * (float(i) + phase) / float(amount)
		var variation := 0.84 + _hash01(i, amount, 174) * 0.33
		_append_entry(collection, species, center.x + cos(angle) * radius * variation, center.y + sin(angle) * radius * variation, height * (0.85 + _hash01(i, amount, 175) * 0.3), angle)

func _place_scenic_scene(parent: Node3D, id: String, x: float, z: float, rotation_y: float, scale_factor: float) -> void:
	var packed: PackedScene = _scene_library.get(id)
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return
	instance.position = Vector3(x, ground_height(x, z), z)
	instance.rotation.y = rotation_y
	instance.scale = Vector3.ONE * scale_factor
	parent.add_child(instance)

func _place_rock_arch(parent: Node3D, center: Vector2) -> void:
	var rock_mesh: Mesh = _mesh_library.get("rock-largeb")
	if rock_mesh == null:
		return
	var lintel := MeshInstance3D.new()
	lintel.name = "Каменная перемычка древних врат"
	lintel.mesh = rock_mesh
	lintel.position = Vector3(center.x, ground_height(center.x, center.y) + 7.0, center.y)
	lintel.rotation.z = PI * 0.5
	lintel.scale = Vector3(1.65, 9.6 / maxf(0.1, rock_mesh.get_aabb().size.y), 1.7)
	parent.add_child(lintel)

func _make_firefly_motes(parent: Node3D, cell: Vector2i, center: Vector2, amount: int) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _mote_mesh
	multi.instance_count = amount
	for i in range(amount):
		var angle := TAU * _hash01(cell.x + i, cell.y, 153)
		var radius := 1.5 + _hash01(cell.x, i, 154) * 7.5
		var x := center.x + cos(angle) * radius
		var z := center.y + sin(angle) * radius
		var height := 0.9 + _hash01(cell.y, i, 155) * 3.3
		var size := 0.6 + _hash01(cell.x, i, 156) * 0.9
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), Vector3(x, ground_height(x, z) + height, z)))
	var motes := MultiMeshInstance3D.new()
	motes.name = "Светящиеся лесные огоньки"
	motes.multimesh = multi
	parent.add_child(motes)

func _add_place_obstacle(cell: Vector2i, x: float, z: float, radius: float) -> void:
	var obstacles: Array = _colliders.get(cell, [])
	obstacles.append(Vector3(x, radius - 0.53, z))
	_colliders[cell] = obstacles

func _append_entry(collection: Dictionary, kind: String, x: float, z: float, height: float, angle: float, water := false) -> void:
	if not collection.has(kind):
		collection[kind] = []
	collection[kind].append({"x": x, "z": z, "height": height, "rotation": angle, "water": water})

func _flush_instances(parent: Node3D, collection: Dictionary) -> void:
	# По одному MultiMesh на разновидность: сотни растений без сотен draw calls.
	for kind in collection:
		var entries: Array = collection[kind]
		if entries.is_empty():
			continue
		var model: Mesh = _mesh_library.get(kind)
		if model == null:
			model = _fallback_mesh(TREE_TYPES.has(kind))
		var bounds := model.get_aabb()
		var base_height := maxf(0.1, bounds.size.y)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = model
		multi.instance_count = entries.size()
		for i in range(entries.size()):
			var entry: Dictionary = entries[i]
			var scale_factor := float(entry["height"]) / base_height
			var direction := Basis(Vector3.UP, float(entry["rotation"]))
			var x: float = entry["x"]
			var z: float = entry["z"]
			var base_y := -0.50 if bool(entry["water"]) else ground_height(x, z)
			var y := base_y - bounds.position.y * scale_factor
			multi.set_instance_transform(i, Transform3D(direction.scaled(Vector3.ONE * scale_factor), Vector3(x, y, z)))
		var displayed := MultiMeshInstance3D.new()
		displayed.name = kind
		displayed.multimesh = multi
		displayed.visibility_range_end = 155.0 if high_quality else 100.0
		parent.add_child(displayed)

func nearby_secret(x: float, z: float) -> Dictionary:
	var here := Vector2(x, z)
	for place in WORLD_PLACES:
		if here.distance_squared_to(place["pos"]) < 5.2 * 5.2:
			return {"id": "world-place-" + str(place["kind"]), "name": place["name"], "pos": place["pos"]}
	for secret in _glades.values():
		if here.distance_squared_to(secret["pos"]) < 4.3 * 4.3:
			return secret
	return {}

func _landmark_clearance(x: float, z: float) -> bool:
	var pos := Vector2(x, z)
	for site in BUILDER_TREES:
		if pos.distance_squared_to(site) < 3.5 * 3.5:
			return true
	return (
		pos.distance_squared_to(Vector2(-12.0, -18.0)) < 11.5 * 11.5
		or pos.distance_squared_to(Vector2(-17.0, -33.0)) < 12.0 * 12.0
		or pos.distance_squared_to(Vector2(10.0, 26.0)) < 6.5 * 6.5
		or pos.distance_squared_to(Vector2(15.0, 44.0)) < 9.0 * 9.0
		or pos.distance_squared_to(Vector2(5.0, 9.5)) < 6.5 * 6.5
		or pos.distance_squared_to(Vector2(32.0, -28.0)) < 9.0 * 9.0
		or pos.distance_squared_to(Vector2(24.0, -28.0)) < 5.5 * 5.5
	)

func _fallback_mesh(tree: bool) -> Mesh:
	var primitive := SphereMesh.new()
	primitive.radius = 0.55 if tree else 0.12
	primitive.height = 1.8 if tree else 0.2
	return primitive

func set_workshop_stage(value: int) -> void:
	var new_stage := clampi(value, 0, 5)
	if new_stage != workshop_stage:
		workshop_stage = new_stage
		navigation_revision += 1

func set_builder_trees(trees: Array) -> void:
	var changed := false
	for i in range(mini(BUILDER_TREES.size(), trees.size())):
		var cut := bool(trees[i].get("cut", false)) if trees[i] is Dictionary else false
		if _builder_trees_cut[i] != cut:
			_builder_trees_cut[i] = cut
			changed = true
	if changed:
		navigation_revision += 1

func can_walk(x: float, z: float, crossing_open: bool) -> bool:
	if not OS.has_feature("web"):
		if not GEO.BOUNDS.has_point(Vector2(x,z)) or not GEO.lake_at(x,z,0.6).is_empty():
			return false
		for rect in chapter_obstacles:
			if rect.has_point(Vector2(x,z)): return false
	var across := crossing_open and absf(x - 5.0) < 1.85 and z > 3.35 and z < 15.65
	if not across and absf(z - river_center(x)) < river_half_width(x) + 0.58:
		return false
	# Выделенные рабочие деревья рубятся Бруно и исчезают из препятствий.
	for i in range(BUILDER_TREES.size()):
		if not bool(_builder_trees_cut[i]) and Vector2(x, z).distance_squared_to(BUILDER_TREES[i]) < 1.30 * 1.30:
			return false
	# С третьего этапа стены мастерской препятствуют проходу сквозь здание.
	if workshop_stage >= 3 and x > 28.45 and x < 35.55 and z > -31.05 and z < -24.95:
		return false
	if x > -17.25 and x < -6.75 and z > -22.35 and z < -13.65:
		return false
	var cell := Vector2i(floori(x / CHUNK_SIZE), floori(z / CHUNK_SIZE))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for tree in _colliders.get(cell + Vector2i(dx, dz), []):
				if Vector2(x - tree.x, z - tree.z).length_squared() < pow(tree.y + 0.53, 2.0):
					return false
	return true

func region_name(x: float, z: float) -> String:
	if not OS.has_feature("web"):
		var geographic := GEO.region(x,z)
		if geographic!="": return geographic
	for place in WORLD_PLACES:
		var center: Vector2 = place["pos"]
		if Vector2(x, z).distance_squared_to(center) < pow(float(place["radius"]) + 5.0, 2.0):
			return str(place["name"])
	var biome := biome_at(x, z)
	match biome:
		"wind_ridge": return "Каменное нагорье"
		"violet_heath": return "Лиловые пустоши"
		"amber_wood": return "Янтарные рощи"
		"mosswood": return "Моховые заводи"
		"bloom_garden": return "Цветущие сады"
	if z > 135.0 or absf(x) > 100.0:
		return "Неизведанные земли"
	if z > 89.0:
		return "Хвойное нагорье"
	if z > 36.0:
		return "Лес странников"
	if z > river_center(x) + 5.5:
		return "Дальний берег"
	return "Долина алхимика"

