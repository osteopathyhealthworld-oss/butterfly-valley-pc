extends Node3D
## Долина бабочек: потоковая генерация ландшафта. Сид одинаков для Windows и Web.
## В исходной версии Babylon.js карта 224 x 246, здесь соседние чанки можно
## создавать за прежней границей мира без ручной прорисовки.

const CHUNK_SIZE := 28
const GRID := 14
const VIEW_RADIUS_LOW := 2
const VIEW_RADIUS_HIGH := 3
const TREE_TYPES := ["tree-oak", "tree-detailed", "tree-pinerounda", "tree-pinesmalla", "tree-fat", "tree-pinetalla"]
const FOLIAGE_TYPES := ["grass", "grass-large", "flower-purplea", "flower-yellowa", "flower-reda", "mushroom-redgroup", "plant-bushlarge", "plant-flattall"]
const ROCK_TYPES := ["rock-largea", "rock-largeb", "rock-smalla", "rock-talla"]
const WATER_TYPES := ["lily-small", "lily-large"]
const GLADES_TYPES := ["stump-rounddetailed", "log-stack", "mushroom-tangroup"]
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

var _loaded: Dictionary = {}
var _pending: Array[Vector2i] = []
var _active_build: Dictionary = {}
var _mesh_library: Dictionary = {}
var _colliders: Dictionary = {}
var navigation_revision := 0
var _glades: Dictionary = {}
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
	var terrain_tex := ["grass-ground-color.jpg", "meadow-color.jpg", "soil-color.jpg", "grass-ground-normal.jpg"]
	var has_terrain_textures := true
	for texture_name in terrain_tex:
		if not ResourceLoader.exists("res://assets/environment/" + texture_name):
			has_terrain_textures = false
	if ResourceLoader.exists(terrain_shader_path) and has_terrain_textures:
		_grass_detailed = ShaderMaterial.new()
		_grass_detailed.shader = load(terrain_shader_path)
		_grass_detailed.set_shader_parameter("grass_color", load("res://assets/environment/grass-ground-color.jpg"))
		_grass_detailed.set_shader_parameter("meadow_color", load("res://assets/environment/meadow-color.jpg"))
		_grass_detailed.set_shader_parameter("soil_color", load("res://assets/environment/soil-color.jpg"))
		_grass_detailed.set_shader_parameter("grass_normal", load("res://assets/environment/grass-ground-normal.jpg"))
	_grass_material = _grass_basic
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
	return 0.06 + (ripples + hills + wild_hills) * bank - (1.0 - bank) * 1.12

func set_quality(enabled: bool) -> void:
	if high_quality == enabled:
		return
	high_quality = enabled
	_grass_material = _grass_detailed if enabled and _grass_detailed != null else _grass_basic
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
				_colliders.erase(key)
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
	var next_phase: int = int(_active_build["phase"]) + 1
	if next_phase >= 6:
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
	return {
		"moisture": moisture, "cool": cool, "openness": openness,
		"stone": stone, "groves": groves
	}

func biome_at(x: float, z: float) -> String:
	var climate := climate_at(x, z)
	if float(climate["moisture"]) > 0.65:
		return "riverbank"
	if float(climate["stone"]) > 0.58:
		return "highland"
	if float(climate["cool"]) > 0.61:
		return "pine"
	if float(climate["openness"]) > 0.56:
		return "meadow"
	return "old_forest"

func _terrain_tint(x: float, z: float) -> Color:
	var climate := climate_at(x, z)
	var result := Color("#789764")
	result = result.lerp(Color("#5f8769"), float(climate["moisture"]) * 0.52)
	result = result.lerp(Color("#708e79"), float(climate["cool"]) * 0.38)
	result = result.lerp(Color("#8c8975"), float(climate["stone"]) * 0.40)
	result = result.lerp(Color("#a6ba79"), float(climate["openness"]) * (1.0 - float(climate["moisture"])) * 0.42)
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
	for route in PATH_ROUTES:
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
	for iz in range(GRID):
		for ix in range(GRID):
			var x := start_x + ix * step
			var z := start_z + iz * step
			var a := Vector3(x, ground_height(x, z), z)
			var b := Vector3(x + step, ground_height(x + step, z), z)
			var c := Vector3(x, ground_height(x, z + step), z + step)
			var d := Vector3(x + step, ground_height(x + step, z + step), z + step)
			_add_vertex(st, a)
			_add_vertex(st, c)
			_add_vertex(st, b)
			_add_vertex(st, b)
			_add_vertex(st, c)
			_add_vertex(st, d)
	st.generate_normals()
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	terrain.name = "Земля"
	parent.add_child(terrain)

func _add_vertex(st: SurfaceTool, pos: Vector3) -> void:
	st.set_uv(Vector2(pos.x * 0.1, pos.z * 0.1))
	st.set_color(_terrain_tint(pos.x, pos.z))
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
	for route in PATH_ROUTES:
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
			if absf(z - river_center(x)) < river_half_width(x) + 4.1:
				continue
			if path_distance(x, z) < 3.3 or _landmark_clearance(x, z):
				continue
			if not glade.is_empty() and Vector2(x, z).distance_squared_to(glade["pos"]) < 5.2 * 5.2:
				continue
			var climate := climate_at(x, z)
			var groves: float = climate["groves"]
			var openness: float = climate["openness"]
			var stone: float = climate["stone"]
			var density := (0.50 if high_quality else 0.32) * (0.55 + groves * 1.0) * (1.0 - openness * 0.62) * (1.0 - stone * 0.28)
			if _hash01(gx, gz, 3) > clampf(density, 0.04, 0.75):
				continue
			var species := _choose_tree(climate, _hash01(gx, gz, 4))
			var height := lerpf(4.6, 9.5, _hash01(gx, gz, 5))
			_append_entry(collection, species, x, z, height, _hash01(gx, gz, 6) * TAU)
			obstacles.append(Vector3(x, 0.65, z))
	# Подлесок тоже имеет пятна: грибы под кронами, цветы на полянах,
	# осока у ручья, валуны на сухих возвышенностях.
	for iz in range(UNDERGROWTH_CELLS):
		for ix in range(UNDERGROWTH_CELLS):
			var gx := cell.x * UNDERGROWTH_CELLS + ix
			var gz := cell.y * UNDERGROWTH_CELLS + iz
			var x := float(gx * UNDERGROWTH_GRID) + 1.0 + (_hash01(gx, gz, 11) - 0.5) * 0.9
			var z := float(gz * UNDERGROWTH_GRID) + 1.0 + (_hash01(gx, gz, 12) - 0.5) * 0.9
			var river_distance := absf(z - river_center(x)) - river_half_width(x)
			if river_distance < 0.35 or path_distance(x, z) < 1.45:
				continue
			if not glade.is_empty() and Vector2(x, z).distance_squared_to(glade["pos"]) < 2.8 * 2.8:
				continue
			var climate := climate_at(x, z)
			var groves: float = climate["groves"]
			var openness: float = climate["openness"]
			var stone: float = climate["stone"]
			var density := (0.69 if high_quality else 0.43) * (0.56 + groves * 0.70 + openness * 0.45) * (1.0 - stone * 0.16)
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
			_append_entry(collection, species, x, z, height, _hash01(gx, gz, 17) * TAU)
	_colliders[cell] = obstacles
	navigation_revision += 1
	_flush_instances(parent, collection)

func _choose_tree(climate: Dictionary, roll: float) -> String:
	var stone: float = climate["stone"]
	var cool: float = climate["cool"]
	var wetness: float = climate["moisture"]
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
		parent.add_child(displayed)

func nearby_secret(x: float, z: float) -> Dictionary:
	var here := Vector2(x, z)
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
	var next_stage := clampi(value, 0, 5)
	if workshop_stage != next_stage:
		workshop_stage = next_stage
		navigation_revision += 1

func set_builder_trees(trees: Array) -> void:
	for i in range(mini(BUILDER_TREES.size(), trees.size())):
		var cut: bool = bool(trees[i].get("cut", false)) if trees[i] is Dictionary else false
		if _builder_trees_cut[i] != cut:
			_builder_trees_cut[i] = cut
			navigation_revision += 1

func can_walk(x: float, z: float, bridge_open: bool) -> bool:
	var across := bridge_open and absf(x - 5.0) < 1.85 and z > 3.35 and z < 15.65
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
	if z > 135.0 or absf(x) > 100.0:
		return "Неизведанные земли"
	if z > 89.0:
		return "Хвойное нагорье"
	if z > 36.0:
		return "Лес странников"
	if z > river_center(x) + 5.5:
		return "Дальний берег"
	return "Долина алхимика"

