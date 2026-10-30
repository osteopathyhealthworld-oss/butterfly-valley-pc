extends Node3D
const ACTOR_ANIMATION = preload("res://scripts/actor_animation.gd")
const MODEL_FITTING = preload("res://scripts/model_fitting.gd")
const VALLEY_AUDIO = preload("res://scripts/valley_audio.gd")
## Долина бабочек / Godot 4.4, первая игровая сборка переноса.
## WASD — ходьба; Shift — бег; E — взаимодействие; Q — поставить ящик;
## мышь (правая кнопка) — камера; колесо — масштаб; N — вечер; P — погода.

const MaterialLibrary = preload("res://scripts/asset_library.gd")
const MaterialPlacements = preload("res://scripts/material_placements.gd")

const LEAVES := [Vector2(-0.6, -15.1), Vector2(3.0, -8.0), Vector2(7.1, -0.1)]
const QUESTS := [
	"Собери три светолиста",
	"Пробуди лабораторию",
	"Восстанови старый мост",
	"Исследуй дальний берег",
	"Первая арка найдена"
]
const SOURCES := [
	["wood", 3, -25], ["wood", -4, -36], ["wood", -28, -25],
	["wood", 16, -18], ["wood", 27, 31], ["wood", 16, 49],
	["stone", -4, -27], ["stone", 0, -37],
	["stone", 22, 24], ["stone", 22, 41]
]

var state: Dictionary
var world
var fauna
var society
var chapter
var workshop
var builder_ai: Node3D
var audio
var builder_menu: PopupMenu
var ui_builder: Label
var player: Node3D
var player_model: Node3D
var player_anim: AnimationPlayer
var camera: Camera3D
var sun: DirectionalLight3D
var environment: WorldEnvironment
var ui_quest: Label
var ui_region: Label
var ui_inventory: Label
var ui_interact: Label
var ui_message: Label
var ui_weather: Label
var bridge_mesh: MeshInstance3D
var bridge_details: Node3D
var butterflies: Array[Dictionary] = []
var fireflies: MultiMeshInstance3D
var rain_particles: CPUParticles3D
var quality_button: Button
var portal_node: Node3D
var feeder_node: Node3D
var crate_node: Node3D
var chest_node: Node3D
var apple_node: Node3D
var interactive: Array[Dictionary] = []
var plots: Array[Dictionary] = []
var actor_templates: Dictionary = {}
var _box_mesh_cache: Dictionary = {}
var _box_material_cache: Dictionary = {}
var _sphere_mesh_cache: Dictionary = {}
var _sphere_material_cache: Dictionary = {}
var library_placed: Array[Node3D] = []
var _touch_axis := Vector2.ZERO
var _touch_move_id := -1
var _touch_look_id := -1
var _touch_origin := Vector2.ZERO
var _touch_running := false
var _touch_knob: Control
var elapsed := 0.0
var saved_elapsed := 0.0
var secret_elapsed := 0.0
var night_mix := 0.0
var yaw := 0.0
var camera_distance := 27.0
var weather_mode := "auto"
var raining := false
var weather_elapsed := 0.0
var action_time := 0.0
var action_finish: Callable
var action_label := ""
var message_time := 0.0
var _last_anim := ""
var _distance_since_step := 0.0
var _blocked_movement_time := 0.0
var _current: Dictionary = {}
var save_path: String = ValleySave.FILE_PATH

func _ready() -> void:
	state = ValleySave.read(save_path)
	weather_mode = str(state.get("weather", "auto"))
	world = load("res://scripts/world_pbr.gd").new()
	world.name = "Процедурный мир"
	add_child(world)
	_make_lighting()
	_make_player()
	_make_camera()
	_make_landmarks()
	_make_workshop()
	_make_bruno()
	_make_world_details()
	_make_garden()
	_make_items()
	_make_atmosphere()
	_make_audio()
	_make_fauna()
	_make_society()
	_make_ui()
	if _is_desktop_release():
		chapter = load("res://scripts/living_valley.gd").new()
		chapter.setup(self)
		chapter.name = "Свет над долиной"
		add_child(chapter)
	_make_touch_ui()
	_configure_starting_quality()
	_apply_state()
	_restore_library_placements()
	_consume_pending_material()
	world.update_stream(player.position)
	_update_ui()
	_toast("Долина бабочек. Добро пожаловать, Паки!")
	get_viewport().get_window().title = "Долина бабочек — Свет над долиной" if chapter!=null else "Долина бабочек — Godot"

func _is_desktop_release() -> bool:
	return not OS.has_feature("web") and (OS.has_feature("pc") or OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos"))

func _is_forward_plus() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

func _make_lighting() -> void:
	environment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#a8c7c4")
	if _is_desktop_release():
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("#6c9dbb")
		sky_material.sky_horizon_color = Color("#d9d8b9")
		sky_material.ground_horizon_color = Color("#c4c4a6")
		var sky := Sky.new()
		sky.sky_material = sky_material
		environment.environment.sky = sky
		environment.environment.background_mode = Environment.BG_SKY
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#c8cfb7")
	environment.environment.ambient_light_energy = 0.65
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment.fog_enabled = true
	environment.environment.fog_light_color = Color("#a7bbaa")
	environment.environment.fog_density = 0.004
	# Forward+ desktop post-processing. The WebGL2 renderer never enters here.
	if _is_forward_plus():
		environment.environment.ssao_enabled = true
		environment.environment.ssao_intensity = 0.85
		environment.environment.ssao_radius = 1.1
		environment.environment.glow_enabled = true
		environment.environment.glow_intensity = 0.42
		environment.environment.volumetric_fog_enabled = true
		environment.environment.volumetric_fog_density = 0.006
		environment.environment.volumetric_fog_length = 95.0
	add_child(environment)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("#ffe3ad")
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-51.0, -32.0, 0.0)
	sun.shadow_enabled = false # Enabled after selecting the desktop quality profile.
	add_child(sun)

func _make_audio() -> void:
	audio = VALLEY_AUDIO.new()
	audio.name = "Звуковая среда"
	add_child(audio)
	# Native Windows can start music immediately. Browsers need a user gesture.
	if not OS.has_feature("web"):
		audio.begin()

func _make_player() -> void:
	player = Node3D.new()
	player.name = "Паки"
	add_child(player)
	var saved_pos: Dictionary = state.get("position", {})
	player.position = Vector3(float(saved_pos.get("x", -4.2)), 0.0, float(saved_pos.get("z", -18.3)))
	player.position.y = world.ground_height(player.position.x, player.position.z) + 0.12
	player_model = _model("paki-hero", 2.4, Color("#dfbba0"))
	player.add_child(player_model)
	player_model.rotation.y = PI
	player_anim = _animation_player(player_model)
	if player_anim != null:
		ACTOR_ANIMATION.lock_horizontal_motion(player_anim, true)

func _make_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if _is_desktop_release():
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 55.0
	camera.size = 29.0
	camera.near = 0.1
	camera.far = 450.0
	camera.current = true
	add_child(camera)
	_update_camera(1.0)

func _update_camera(delta: float) -> void:
	if camera == null or player == null:
		return
	var ahead := Vector3(sin(yaw), 0, cos(yaw))
	var target := player.position + Vector3(0.0, 1.8, 0.0)
	var offset := Vector3(0.0, camera_distance * 0.68, camera_distance * 0.75)
	if chapter != null and chapter.vista_mode:
		offset = Vector3(0.0, camera_distance * 0.35, camera_distance * 1.1)
	offset = offset.rotated(Vector3.UP, yaw)
	camera.position = camera.position.lerp(target + offset, clampf(delta * 8.0, 0.0, 1.0))
	camera.look_at(target, Vector3.UP)

func _mesh_box(label: String, size: Vector3, color: Color, pos: Vector3, owner: Node3D = null) -> MeshInstance3D:
	if owner == null:
		owner = self
	var box := MeshInstance3D.new()
	box.name = label
	var mesh: BoxMesh = _box_mesh_cache.get(size)
	if mesh == null:
		mesh = BoxMesh.new()
		mesh.size = size
		_box_mesh_cache[size] = mesh
	box.mesh = mesh
	var color_key := color.to_html(true)
	var material: StandardMaterial3D = _box_material_cache.get(color_key)
	if material == null:
		material = StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.88
		_box_material_cache[color_key] = material
	box.material_override = material
	box.position = pos
	owner.add_child(box)
	return box

func _mesh_sphere(label: String, size: float, color: Color, pos: Vector3, owner: Node3D = null) -> MeshInstance3D:
	if owner == null:
		owner = self
	var mesh: SphereMesh = _sphere_mesh_cache.get(size)
	if mesh == null:
		mesh = SphereMesh.new()
		mesh.radius = size
		mesh.height = size * 2.0
		_sphere_mesh_cache[size] = mesh
	var sphere := MeshInstance3D.new()
	sphere.name = label
	sphere.mesh = mesh
	sphere.position = pos
	var color_key := color.to_html(true)
	var mat: StandardMaterial3D = _sphere_material_cache.get(color_key)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = color
		_sphere_material_cache[color_key] = mat
	sphere.material_override = mat
	owner.add_child(sphere)
	return sphere

func _model(name: String, height: float, fallback: Color) -> Node3D:
	var node := Node3D.new()
	node.name = name
	var path := "res://assets/%s.glb" % name
	if not ResourceLoader.exists(path):
		_mesh_sphere("Временная форма", height * 0.26, fallback, Vector3(0, height * 0.48, 0), node)
		return node
	var scene: PackedScene = actor_templates.get(name)
	if scene == null:
		scene = load(path) as PackedScene
		actor_templates[name] = scene
	if scene == null:
		return node
	var root := scene.instantiate() as Node3D
	if root != null:
		node.add_child(MODEL_FITTING.wrap_to_height(root, height))
	return node

func _collect_bounds(node: Node, bounds: Dictionary, parent_transform: Transform3D = Transform3D.IDENTITY) -> void:
	var relative := parent_transform
	if node is Node3D:
		relative = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var aabb := mesh_node.get_aabb()
		# Godot импортирует glTF со своей локальной системой координат.
		for y in [aabb.position.y, aabb.end.y]:
			for x in [aabb.position.x, aabb.end.x]:
				for z in [aabb.position.z, aabb.end.z]:
					var p := relative * Vector3(x, y, z)
					bounds["min"] = minf(float(bounds["min"]), p.y)
					bounds["max"] = maxf(float(bounds["max"]), p.y)
					bounds["min_x"] = minf(float(bounds["min_x"]), p.x)
					bounds["max_x"] = maxf(float(bounds["max_x"]), p.x)
					bounds["min_z"] = minf(float(bounds["min_z"]), p.z)
					bounds["max_z"] = maxf(float(bounds["max_z"]), p.z)
	for child in node.get_children():
		_collect_bounds(child, bounds, relative)

func _animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _animation_player(child)
		if found != null:
			return found
	return null

func _add_prop(name: String, x: float, z: float, height: float, color: Color) -> Node3D:
	var item := _model(name, height, color)
	item.position = Vector3(x, world.ground_height(x, z), z)
	add_child(item)
	return item

func _add_library_prop(id: String, x: float, z: float, height: float) -> Node3D:
	var model: Node3D = MaterialLibrary.create(id)
	if model == null:
		return _add_prop("log-stack", x, z, height, Color("#a48059"))
	var pivot := Node3D.new()
	pivot.name = "Материал мира · " + id
	pivot.position = Vector3(x, world.ground_height(x, z), z)
	add_child(pivot)
	pivot.add_child(model)
	MaterialLibrary.fit_visual(model, height)
	return pivot

func _register(kind: String, pos: Vector2, extra: Dictionary = {}) -> void:
	var entry := extra.duplicate()
	entry["kind"] = kind
	entry["pos"] = pos
	interactive.append(entry)

func _make_workshop() -> void:
	workshop = load("res://scripts/construction.gd").new()
	workshop.name = "Строительная площадка Бруно"
	var origin := Vector2(32.0, -28.0)
	workshop.position = Vector3(origin.x, world.ground_height(origin.x, origin.y), origin.y)
	add_child(workshop)
	var saved_stage := int(state["world"]["builder"].get("stage", 0))
	workshop.set_stage(saved_stage)
	world.set_workshop_stage(saved_stage)

func _make_bruno() -> void:
	builder_ai = load("res://scripts/builder_ai.gd").new()
	builder_ai.name = "Бруно — самостоятельный строитель"
	builder_ai.setup(world, workshop, player, state["world"]["builder"], Callable(self, "_on_builder_event"))
	add_child(builder_ai)

func _village_modules_ready() -> bool:
	for asset in ["Wall_Plaster_Straight", "Wall_Plaster_Door_Flat", "Wall_Plaster_Window_Wide_Flat", "Roof_RoundTiles_6x6"]:
		if not ResourceLoader.exists("res://assets/buildings/village/%s.gltf" % asset):
			return false
	return true

func _make_landmarks() -> void:
	# Keep the original quest coordinates, but build the visible laboratory
	# from the same textured village kit as Bruno's workshop.
	if _village_modules_ready():
		var house = load("res://scripts/construction.gd").new()
		house.name = "Лаборатория алхимика · Quaternius"
		house.position = Vector3(-12.0, world.ground_height(-12.0, -17.5), -17.5)
		house.rotation.y = PI
		house.scale = Vector3(1.28, 1.10, 1.28)
		add_child(house)
		house.set_stage(5)
	else:
		_mesh_box("Временная лаборатория", Vector3(9.3, 5.4, 8.4), Color("#e1c99f"), Vector3(-12.0, 2.45, -17.5))
		_mesh_box("Временная крыша", Vector3(10.3, 1.0, 9.5), Color("#a9584c"), Vector3(-12.0, 5.3, -17.5))
	_add_prop("lantern-glass", -17.0, -20.0, 1.4, Color.GOLD)
	_register("lab", Vector2(-12.0, -21.0))
	bridge_mesh = _mesh_box("Мост", Vector3(3.5, 0.4, 14.2), Color("#a5744b"), Vector3(5.0, 0.54, 9.5))
	_register("bridge", Vector2(5.0, 3.75))
	portal_node = Node3D.new()
	portal_node.position = Vector3(10.0, world.ground_height(10.0, 26.0) + 2.2, 26.0)
	add_child(portal_node)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.45
	torus.outer_radius = 1.78
	ring.mesh = torus
	ring.rotation.x = PI * 0.5
	var portal_mat := StandardMaterial3D.new()
	portal_mat.albedo_color = Color("#59caca")
	portal_mat.emission_enabled = true
	portal_mat.emission = Color("#51d4d2")
	ring.material_override = portal_mat
	portal_node.add_child(ring)
	_register("portal", Vector2(10, 26))
	_add_prop("campfire-logs", 15.0, 43.0, 1.5, Color("#c99568"))
	_add_prop("tent-smallopen", 19.4, 46.1, 3.6, Color("#b7a576"))
	_add_prop("mouse-cute", -20.0, -28.0, 2.1, Color("#d0a4a5"))
	_add_prop("mouse-cute", 15.5, 43.8, 2.1, Color("#bda393"))
	_register("friend", Vector2(-20, -28), {"id": "mira", "name": "Мира"})
	_register("friend", Vector2(15.5, 43.8), {"id": "tim", "name": "Тим"})
	_register("builder", Vector2(24.0, -28.0))
	feeder_node = _mesh_box("Кормушка", Vector3(1.8, 2.4, 1.1), Color("#bc8859"), Vector3(-4.5, 1.2, -30.0))
	_register("feeder", Vector2(-4.5, -30))
	chest_node = _mesh_box("Сундук", Vector3(1.8, 0.85, 1.2), Color("#704c36"), Vector3(19.0, 0.55, 44.0))
	_register("chest", Vector2(19, 44))
	crate_node = _mesh_box("Ящик с овощами", Vector3(1.55, 0.88, 1.05), Color("#b9885b"), Vector3(-6.0, 0.45, -35.5))
	_register("crate", Vector2(-6.0, -35.5))
	_add_prop("tree-oak", 3.0, -39.0, 7.2, Color.FOREST_GREEN)
	apple_node = Node3D.new()
	apple_node.position = Vector3(3.0, world.ground_height(3, -39), -39.0)
	add_child(apple_node)
	for i in range(6):
		_mesh_sphere("Яблоко", 0.23, Color("#d86f66"), Vector3(sin(i * 2.4) * 1.15, 3.9 + (i % 3) * 0.4, cos(i * 2.4) * 0.9), apple_node)
	_register("orchard", Vector2(3, -39))

func _make_world_details() -> void:
	# The legacy cuboid trim is only used if the textured modules are absent.
	if not _village_modules_ready():
		_mesh_box("Дубовая дверь алхимика", Vector3(1.65, 2.9, 0.28), Color("#76523b"), Vector3(-12.0, 1.55, -21.78))
		_mesh_box("Медная дверная ручка", Vector3(0.15, 0.14, 0.16), Color("#dfbc74"), Vector3(-11.45, 1.25, -21.98))
		for x in [-15.8, -8.2]:
			_mesh_box("Светящееся окно", Vector3(1.55, 1.3, 0.16), Color("#e5c994"), Vector3(x, 2.8, -21.78))
			_glow_orb("Алхимический свет", Vector3(x, 2.8, -21.97), 0.22, Color("#f8c777"))
		_mesh_box("Старый дымоход", Vector3(1.0, 3.0, 1.0), Color("#8a8d80"), Vector3(-15.3, 6.0, -18.4))
		for x in range(-16, -6, 2):
			for z in [-21.3, -13.6]:
				_mesh_box("Черепица", Vector3(1.75, 0.12, 0.9), Color("#b96b52"), Vector3(float(x), 5.84, z))
	else:
		_add_prop("lantern-glass", -15.5, -21.1, 1.2, Color("#f6db96"))
		_add_library_prop("kenney.furniture-kit.books", -9.1, -20.4, 0.45)
	for i in range(4):
		_add_prop("path-stone", -12.0 + sin(i * 1.2) * 0.25, -23.0 - i * 1.3, 0.36, Color("#aaa38c"))
	# Огород: невысокая деревянная ограда, фонарики и стол с инструментами.
	for i in range(8):
		_mesh_box("Колья ограды", Vector3(0.15, 1.2, 0.15), Color("#9c7350"), Vector3(-23.4 + i * 1.67, 0.65, -37.7))
		if i < 7:
			_mesh_box("Ограда огорода", Vector3(1.65, 0.12, 0.12), Color("#ad855b"), Vector3(-22.58 + i * 1.67, 0.88, -37.7))
	_mesh_box("Рабочий стол", Vector3(2.6, 0.35, 1.4), Color("#987049"), Vector3(-24.0, 1.0, -28.4))
	_add_prop("pot-large", -24.0, -28.4, 0.85, Color("#aa8763"))
	_add_prop("lantern-glass", -22.6, -28.2, 0.9, Color("#ffdf8e"))
	_glow_orb("Лампа у огорода", Vector3(-22.6, 1.5, -28.2), 0.14, Color("#ffd88d"))
	# У восстановленного моста появляются балки, настил и ограждения.
	bridge_details = Node3D.new()
	bridge_details.name = "Детали восстановленной переправы"
	add_child(bridge_details)
	for i in range(9):
		var z := 3.45 + i * 1.52
		_mesh_box("Мостовая доска", Vector3(3.35, 0.2, 1.25), Color("#b08554"), Vector3(5.0, 0.84, z), bridge_details)
	for side in [-1.0, 1.0]:
		_mesh_box("Поручень моста", Vector3(0.18, 0.18, 13.4), Color("#866144"), Vector3(5.0 + side * 1.63, 2.15, 9.4), bridge_details)
		for i in range(6):
			_mesh_box("Стойка моста", Vector3(0.27, 1.75, 0.27), Color("#6f553e"), Vector3(5.0 + side * 1.65, 1.35, 3.9 + i * 2.25), bridge_details)
	# Лунные камни и кристаллы делают портал заметным с дальнего берега.
	for i in range(8):
		var a := TAU * i / 8.0
		var px := 10.0 + cos(a) * 4.2
		var pz := 26.0 + sin(a) * 3.5
		_add_prop("rock-largea", px, pz, 1.15 + float(i % 3) * 0.3, Color("#94a19a"))
		if i % 2 == 0:
			_glow_orb("Кристалл портала", Vector3(px, world.ground_height(px, pz) + 1.35, pz), 0.27, Color("#72e4d8"))
	# На стоянке странников: очаг с камнями, скамьи и походные вещи.
	for i in range(10):
		var a := TAU * i / 10.0
		_add_prop("rock-smalla", 15.0 + sin(a) * 1.15, 43.0 + cos(a) * 1.15, 0.48, Color("#8e9683"))
	_add_library_prop("kenney.nature-kit.campfire-logs", 15.0, 43.0, 0.68)
	_glow_orb("Угли походного костра", Vector3(15.0, 0.49, 43.0), 0.35, Color("#ffd08d"))
	_mesh_box("Лавка странников", Vector3(2.5, 0.35, 0.8), Color("#97704a"), Vector3(12.3, 0.65, 43.2))
	_add_prop("log-stack", 20.0, 42.0, 1.1, Color("#a48059"))
	_add_prop("lantern-glass", 17.2, 42.0, 1.0, Color("#eec577"))
	# Кувшинки рядом с переправой, чуть выше уровня воды.
	for i in range(14):
		var x := -18.0 + i * 3.3
		var z: float = world.river_center(x) + (2.4 if i % 2 == 0 else -2.7)
		var lily := _model("lily-small" if i % 3 else "lily-large", 0.65, Color("#9abf8a"))
		lily.position = Vector3(x, -0.49, z)
		add_child(lily)

func _glow_orb(label: String, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var orb := _mesh_sphere(label, radius, color, pos)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	mat.roughness = 0.38
	orb.material_override = mat
	return orb

func _make_garden() -> void:
	for i in range(6):
		var coord: Vector2 = ValleySave.GARDEN_POSITIONS[i]
		var pos := Vector3(coord.x, world.ground_height(coord.x, coord.y), coord.y)
		_mesh_box("Грядка", Vector3(2.95, 0.32, 2.88), Color("#6e4f3b"), pos + Vector3(0, 0.2, 0))
		_mesh_box("Плодородная почва", Vector3(2.7, 0.18, 2.64), Color("#654b3a"), pos + Vector3(0, 0.45, 0))
		var kind: Dictionary = ValleySave.GARDEN_TYPES[i]
		var crop := _model(str(kind["model"]), 1.4, Color("#84b669"))
		crop.position = pos + Vector3(0, 0.5, 0)
		add_child(crop)
		plots.append({"crop": crop, "index": i})
		_register("garden", coord, {"index": i})

func _make_items() -> void:
	for i in range(LEAVES.size()):
		var coord: Vector2 = LEAVES[i]
		var marker := Node3D.new()
		marker.position = Vector3(coord.x, world.ground_height(coord.x, coord.y), coord.y)
		add_child(marker)
		_mesh_sphere("Светолист", 0.3, Color("#b0f3a0"), Vector3(0, 0.75, 0), marker)
		_register("leaf", coord, {"index": i, "marker": marker})
	for i in range(SOURCES.size()):
		var source: Array = SOURCES[i]
		var kind: String = source[0]
		var pos := Vector2(float(source[1]), float(source[2]))
		var item: Node3D
		if kind == "wood":
			item = _add_library_prop("kenney.nature-kit.log", pos.x, pos.y, 0.95)
		else:
			item = _add_prop("rock-smalla", pos.x, pos.y, 0.9, Color("#a79a88"))
		_register("resource", pos, {"index": i, "resource": kind, "marker": item})

func _make_atmosphere() -> void:
	# Несколько живых бабочек на полянах. Геометрия мала, а движение
	# рассчитывается только у видимых персонажей, без сложной физики.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2011989
	var places := [Vector2(-18, -32), Vector2(-8, -24), Vector2(2, -15), Vector2(12, 25), Vector2(15, 43)]
	for i in range(18):
		var home: Vector2 = places[i % places.size()]
		var x := home.x + rng.randf_range(-4.5, 4.5)
		var z := home.y + rng.randf_range(-4.5, 4.5)
		var center := Vector3(x, world.ground_height(x, z) + rng.randf_range(1.1, 2.7), z)
		var butterfly := Node3D.new()
		butterfly.name = "Бабочка_%d" % i
		butterfly.position = center
		add_child(butterfly)
		_mesh_sphere("Туловище", 0.055, Color("#4a5341"), Vector3.ZERO, butterfly)
		var wings: Array[MeshInstance3D] = []
		var wing_color: Color = [Color("#eebf73"), Color("#d8a3ce"), Color("#a9d8dc"), Color("#f0dcaa")][i % 4]
		for direction in [-1.0, 1.0]:
			var wing := _mesh_sphere("Крыло", 0.2, wing_color, Vector3(direction * 0.19, 0.02, 0), butterfly)
			wing.scale = Vector3(1.0, 0.11, 0.75)
			wings.append(wing)
		butterflies.append({"actor": butterfly, "home": center, "phase": rng.randf_range(0.0, TAU), "wings": wings})
	# Мерцающие светлячки появляются только вечером.
	fireflies = MultiMeshInstance3D.new()
	fireflies.name = "Лесные светлячки"
	var sparkle := SphereMesh.new()
	sparkle.radius = 0.075
	sparkle.height = 0.15
	var sparkle_material := StandardMaterial3D.new()
	sparkle_material.albedo_color = Color("#dceca0")
	sparkle_material.emission_enabled = true
	sparkle_material.emission = Color("#c1e58a")
	sparkle_material.emission_energy_multiplier = 2.0
	sparkle.material = sparkle_material
	var cloud := MultiMesh.new()
	cloud.transform_format = MultiMesh.TRANSFORM_3D
	cloud.mesh = sparkle
	cloud.instance_count = 65
	for i in range(65):
		var cluster: Vector2 = places[i % places.size()]
		var x := cluster.x + rng.randf_range(-11.0, 11.0)
		var z := cluster.y + rng.randf_range(-9.0, 9.0)
		var y: float = world.ground_height(x, z) + rng.randf_range(0.9, 3.5)
		cloud.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
	fireflies.multimesh = cloud
	fireflies.visible = false
	add_child(fireflies)
	# Частицы осадков работают на CPU, а не требуют мощной видеокарты.
	rain_particles = CPUParticles3D.new()
	rain_particles.name = "Лесной дождь"
	rain_particles.amount = 100
	rain_particles.lifetime = 1.35
	rain_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_particles.emission_box_extents = Vector3(22, 0.5, 22)
	rain_particles.direction = Vector3(-0.12, -1.0, 0.03)
	rain_particles.spread = 5.0
	rain_particles.gravity = Vector3(0, -21, 0)
	rain_particles.initial_velocity_min = 8.0
	rain_particles.initial_velocity_max = 12.0
	rain_particles.local_coords = true
	var raindrop := QuadMesh.new()
	raindrop.size = Vector2(0.048, 0.68)
	var rain_material := StandardMaterial3D.new()
	rain_material.albedo_color = Color(0.77, 0.88, 0.95, 0.48)
	rain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rain_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	raindrop.material = rain_material
	rain_particles.mesh = raindrop
	rain_particles.emitting = false
	add_child(rain_particles)

func _animate_atmosphere(delta: float) -> void:
	for butterfly in butterflies:
		var actor: Node3D = butterfly["actor"]
		actor.visible = not raining
		if not actor.visible:
			continue
		var home: Vector3 = butterfly["home"]
		var phase: float = float(butterfly["phase"])
		var t := elapsed * 0.65 + phase
		actor.position = home + Vector3(sin(t * 1.4) * 1.25, sin(t * 2.1) * 0.32, cos(t * 1.1) * 1.05)
		actor.rotation.y = t * 0.7
		var wing_motion := sin(elapsed * 13.0 + phase) * 0.63
		var wings: Array = butterfly["wings"]
		wings[0].rotation.z = -wing_motion
		wings[1].rotation.z = wing_motion
	if fireflies != null:
		fireflies.visible = night_mix > 0.35 and not raining
	if rain_particles != null:
		rain_particles.position = player.position + Vector3(0, 13, 0)
		rain_particles.emitting = raining

func _make_fauna() -> void:
	fauna = load("res://scripts/fauna.gd").new()
	fauna.setup(world, player)
	add_child(fauna)
	fauna.set_night(bool(state["night"]))

func _make_society() -> void:
	society = load("res://scripts/society.gd").new()
	society.setup(world, player, state["world"].get("society", {}))
	add_child(society)
	society.set_night(bool(state["night"]))

func _make_ui() -> void:
	if _is_desktop_release():
		_make_desktop_ui()
		return
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	ui_quest = _label(hud, Vector2(16, 16), 700, 24)
	ui_region = _label(hud, Vector2(16, 52), 650, 16)
	ui_inventory = _label(hud, Vector2(16, 78), 750, 17)
	ui_weather = _label(hud, Vector2(16, 105), 600, 17)
	ui_builder = _label(hud, Vector2(16, 128), 960, 16)
	ui_interact = _label(hud, Vector2(16, 157), 770, 21)
	ui_message = _label(hud, Vector2(16, 192), 950, 20)
	var button := Button.new()
	button.text = "E · Действие"
	button.position = Vector2(16, 225)
	button.size = Vector2(155, 44)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(_interact)
	hud.add_child(button)
	var day_button := Button.new()
	day_button.text = "День / ночь"
	day_button.position = Vector2(185, 225)
	day_button.size = Vector2(130, 44)
	day_button.mouse_filter = Control.MOUSE_FILTER_STOP
	day_button.pressed.connect(_toggle_night)
	hud.add_child(day_button)
	var weather_button := Button.new()
	weather_button.text = "Погода"
	weather_button.position = Vector2(329, 225)
	weather_button.size = Vector2(110, 44)
	weather_button.mouse_filter = Control.MOUSE_FILTER_STOP
	weather_button.pressed.connect(_cycle_weather)
	hud.add_child(weather_button)
	quality_button = Button.new()
	quality_button.text = "Графика: экономная"
	quality_button.position = Vector2(453, 225)
	quality_button.size = Vector2(195, 44)
	quality_button.mouse_filter = Control.MOUSE_FILTER_STOP
	quality_button.pressed.connect(_toggle_quality)
	hud.add_child(quality_button)
	var credits_dialog := AcceptDialog.new()
	credits_dialog.title = "Авторы моделей животных"
	credits_dialog.dialog_text = "Лиса: PixelMannen — модель и текстура (CC0); tomkranis — скелет и анимации (CC BY 4.0); AsoboStudio и scurest — glTF (CC BY 4.0). Источник: github.com/KhronosGroup/glTF-Sample-Assets/Models/Fox.\nУтка, летучая мышь, утконос и корги: Gobkit / Alsomind Tech Co., Ltd. (CC0 1.0). Источник: github.com/Ariescar/gobkit-free-assets."
	add_child(credits_dialog)
	var credits_button := Button.new()
	credits_button.text = "Авторы животных"
	credits_button.position = Vector2(660, 225)
	credits_button.size = Vector2(160, 44)
	credits_button.mouse_filter = Control.MOUSE_FILTER_STOP
	credits_button.pressed.connect(credits_dialog.popup_centered)
	hud.add_child(credits_button)
	var materials_button := Button.new()
	materials_button.text = "Материалы · F7"
	materials_button.position = Vector2(834, 225)
	materials_button.size = Vector2(172, 44)
	materials_button.mouse_filter = Control.MOUSE_FILTER_STOP
	materials_button.pressed.connect(_open_material_library)
	hud.add_child(materials_button)
	var helper := _label(hud, Vector2(16, 290), 1160, 15)
	helper.text = "WASD — идти · Shift — бежать · E — действие · Q — ящик · F7 — материалы · ПКМ — камера · колесо — масштаб"
	builder_menu = PopupMenu.new()
	builder_menu.name = "Разговор с Бруно"
	builder_menu.add_item("Иди за мной", 0)
	builder_menu.add_item("Продолжай работу", 1)
	builder_menu.add_item("Передать одну ветку", 2)
	builder_menu.add_item("Передать один камень", 3)
	builder_menu.add_item("Помочь построить этап", 4)
	builder_menu.add_item("Осмотреть склад", 5)
	builder_menu.id_pressed.connect(_on_builder_option)
	builder_menu.popup_hide.connect(func() -> void: builder_ai.set_paused(false))
	add_child(builder_menu)

func _make_desktop_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	ui_quest = _label(hud,Vector2(18,14),960,24)
	ui_region = _label(hud,Vector2(18,48),850,16)
	ui_inventory = _label(hud,Vector2(18,76),1000,17)
	ui_builder = _label(hud,Vector2(18,106),1000,15)
	ui_weather = _label(hud,Vector2(18,132),900,16)
	ui_interact = _label(hud,Vector2.ZERO,1000,20)
	ui_interact.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ui_interact.offset_top = -64
	ui_interact.offset_bottom = -30
	ui_interact.offset_left = 18
	ui_interact.offset_right = 1100
	ui_message = _label(hud,Vector2.ZERO,1050,18)
	ui_message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ui_message.offset_top = -130
	ui_message.offset_bottom = -70
	ui_message.offset_left = 18
	ui_message.offset_right = 1100
	ui_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quality_button = Button.new()
	quality_button.text = "Графика: детальная"
	quality_button.position = Vector2(1030,16)
	quality_button.pressed.connect(_toggle_quality)
	hud.add_child(quality_button)
	var helper := _label(hud,Vector2.ZERO,1150,14)
	helper.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	helper.offset_top = -27
	helper.offset_bottom = -3
	helper.offset_left = 18
	helper.offset_right = 1200
	helper.text = "WASD — идти · Shift — бежать · E — действие · J/M — журнал и карта · F8 — вид на долину · F11 — полный экран"
	builder_menu = PopupMenu.new()
	builder_menu.add_item("Иди за мной",0)
	builder_menu.add_item("Продолжай работу",1)
	builder_menu.add_item("Передать одну ветку",2)
	builder_menu.add_item("Передать один камень",3)
	builder_menu.add_item("Помочь построить этап",4)
	builder_menu.add_item("Осмотреть склад",5)
	builder_menu.id_pressed.connect(_on_builder_option)
	builder_menu.popup_hide.connect(func() -> void: builder_ai.set_paused(false))
	add_child(builder_menu)

func _make_touch_ui() -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	var canvas := CanvasLayer.new()
	canvas.layer = 2
	add_child(canvas)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	var stick := Panel.new()
	stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stick.offset_left = 26.0
	stick.offset_right = 172.0
	stick.offset_top = -186.0
	stick.offset_bottom = -40.0
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := StyleBoxFlat.new()
	circle.bg_color = Color(0.12, 0.22, 0.24, 0.40)
	circle.set_corner_radius_all(90)
	circle.set_border_width_all(2)
	circle.border_color = Color(0.84, 0.93, 0.84, 0.55)
	stick.add_theme_stylebox_override("panel", circle)
	overlay.add_child(stick)
	_touch_knob = Panel.new()
	_touch_knob.position = Vector2(46, 46)
	_touch_knob.size = Vector2(54, 54)
	_touch_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = Color(0.91, 0.95, 0.83, 0.65)
	knob_style.set_corner_radius_all(36)
	_touch_knob.add_theme_stylebox_override("panel", knob_style)
	stick.add_child(_touch_knob)
	var action := Button.new()
	action.text = "Действие"
	action.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	action.offset_left = -180
	action.offset_right = -24
	action.offset_top = -178
	action.offset_bottom = -112
	action.pressed.connect(_interact)
	overlay.add_child(action)
	var run := Button.new()
	run.text = "Бег"
	run.toggle_mode = true
	run.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	run.offset_left = -180
	run.offset_right = -102
	run.offset_top = -101
	run.offset_bottom = -40
	run.toggled.connect(func(active: bool) -> void: _touch_running = active)
	overlay.add_child(run)
	var crate := Button.new()
	crate.text = "Ящик"
	crate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	crate.offset_left = -95
	crate.offset_right = -24
	crate.offset_top = -101
	crate.offset_bottom = -40
	crate.pressed.connect(_put_down_crate)
	overlay.add_child(crate)

func _label(parent: Control, pos: Vector2, width: float, font_size: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = Vector2(width, 55)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#f3f0dc"))
	label.add_theme_color_override("font_shadow_color", Color("#283c34"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label

func _apply_state() -> void:
	world.bridge_open = bool(state["bridge"])
	var saved_stage := int(state["world"]["builder"].get("stage", 0))
	if workshop != null:
		workshop.set_stage(saved_stage)
	world.set_workshop_stage(saved_stage)
	bridge_mesh.visible = bool(state["bridge"])
	bridge_details.visible = bool(state["bridge"])
	feeder_node.visible = bool(state["world"]["feederBuilt"])
	chest_node.visible = bool(state["bridge"])
	apple_node.visible = not bool(state["world"]["orchardPicked"])
	_sync_crate()
	for entry in interactive:
		if entry["kind"] == "leaf":
			entry["marker"].visible = not state["collected"].has(int(entry["index"]))
		if entry["kind"] == "resource":
			entry["marker"].visible = not state["world"]["picked"].has("%s-%d" % [entry["resource"], entry["index"]])
	for plot in plots:
		var index: int = plot["index"]
		var phase := ValleySave.garden_phase(state["garden"][index], Time.get_unix_time_from_system())
		plot["crop"].visible = phase > 0
		plot["crop"].scale = Vector3.ONE * ([0.0, 0.25, 0.40, 0.65, 1.0][phase])

func _sync_crate() -> void:
	var world_state: Dictionary = state["world"]
	crate_node.visible = not bool(world_state["carryingCrate"]) and not bool(world_state["crateDelivered"])
	var pos: Dictionary = world_state["cratePosition"]
	crate_node.position = Vector3(float(pos["x"]), world.ground_height(float(pos["x"]), float(pos["z"])) + 0.45, float(pos["z"]))

func _physics_process(delta: float) -> void:
	if chapter != null and chapter.menu_open:
		# Loading continues while the player reads the opening journal.
		world.update_stream(player.position)
		_update_camera(delta)
		return
	elapsed += delta
	saved_elapsed += delta
	secret_elapsed += delta
	weather_elapsed += delta
	if action_time > 0.0:
		action_time -= delta
		if _movement_vector().length() > 0.1:
			action_time = 0.0
			action_finish = Callable()
			_toast("Действие отменено.")
		elif action_time <= 0.0 and action_finish.is_valid():
			action_finish.call()
			action_finish = Callable()
			_save()
	else:
		_move(delta)
	world.update_stream(player.position)
	if secret_elapsed >= 0.75:
		secret_elapsed = 0.0
		_check_secret()
	_update_camera(delta)
	_update_weather(delta)
	if audio != null:
		audio.set_ambience(bool(state["night"]), raining)
	if society != null:
		society.simulation.bridge_open = bool(state["bridge"])
	if builder_ai != null:
		builder_ai.tick(delta, raining, bool(state["night"]))
	_animate_atmosphere(delta)
	_update_ui()
	if saved_elapsed >= 12.0:
		saved_elapsed = 0.0
		_save()
	if message_time > 0.0:
		message_time -= delta
		if message_time <= 0.0:
			ui_message.text = ""

func _movement_vector() -> Vector2:
	var dir := _touch_axis
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1.0
	return dir.normalized()

func _move(delta: float) -> void:
	var axis := _movement_vector()
	var moving := axis.length_squared() > 0.01
	var running := (Input.is_key_pressed(KEY_SHIFT) or _touch_running) and not bool(state["world"]["carryingCrate"])
	if chapter != null:
		running = running and chapter.can_run()
	var before_position := player.position
	if moving:
		var wish := Vector3(axis.x, 0, axis.y).rotated(Vector3.UP, yaw)
		var speed := 3.5 if bool(state["world"]["carryingCrate"]) else (8.5 if running else 5.3)
		if chapter != null:
			speed *= chapter.movement_scale()
		var steps := maxi(1, ceili(speed * delta / 0.25))
		for i in range(steps):
			var step := wish * speed * delta / steps
			var next := player.position + step
			if _player_can_walk(next.x, next.z):
				player.position.x = next.x
				player.position.z = next.z
			elif _player_can_walk(next.x, player.position.z):
				player.position.x = next.x
			elif _player_can_walk(player.position.x, next.z):
				player.position.z = next.z
			else:
				# Try a short tangent around a trunk instead of becoming wedged
				# against its circular collision boundary.
				for turn in [-35.0, 35.0, -65.0, 65.0]:
					var detour := wish.rotated(Vector3.UP, deg_to_rad(turn)) * speed * delta / steps
					var candidate := player.position + detour
					if _player_can_walk(candidate.x, candidate.z):
						player.position.x = candidate.x
						player.position.z = candidate.z
						break
	if moving and player.position.distance_squared_to(before_position) < 0.000001:
		_blocked_movement_time += delta
		# Streaming may place a tree collision around a previously valid save.
		# Relocate only if the hero's *current* position became invalid.
		if _blocked_movement_time > 0.7 and not _player_can_walk(player.position.x, player.position.z):
			_recover_player_from_obstacle()
			_blocked_movement_time = 0.0
	else:
		_blocked_movement_time = 0.0
	var travelled := Vector2(player.position.x - before_position.x, player.position.z - before_position.z)
	var actually_moving := travelled.length_squared() > 0.000001
	if actually_moving:
		var heading := atan2(-travelled.x, -travelled.y)
		player.rotation.y = lerp_angle(player.rotation.y, heading, minf(1.0, delta * 10.0))
	var on_bridge := bool(state["bridge"]) and absf(player.position.x - 5.0) < 1.85 and player.position.z > 3.5 and player.position.z < 15.5
	var y: float = 0.65 if on_bridge else world.ground_height(player.position.x, player.position.z) + 0.12
	player.position.y = lerpf(player.position.y, y, minf(1.0, delta * 13.0))
	_animate(running, actually_moving)
	if audio != null:
		if actually_moving:
			_distance_since_step += travelled.length()
			var step_length := 1.65 if running else 1.18
			if _distance_since_step >= step_length:
				_distance_since_step = fmod(_distance_since_step, step_length)
				audio.play_cue("step")
		else:
			_distance_since_step = 0.0

func _recover_player_from_obstacle() -> void:
	var center := Vector2(player.position.x, player.position.z)
	for radius in [0.45, 0.85, 1.25, 1.65, 2.05, 2.45]:
		for i in range(16):
			var a := TAU * float(i) / 16.0
			var candidate: Vector2 = center + Vector2(cos(a), sin(a)) * radius
			if _player_can_walk(candidate.x, candidate.y):
				player.position.x = candidate.x
				player.position.z = candidate.y
				return

func _player_can_walk(x: float, z: float) -> bool:
	if not world.can_walk(x, z, bool(state["bridge"])):
		return false
	if builder_ai != null and Vector2(x, z).distance_squared_to(Vector2(builder_ai.position.x, builder_ai.position.z)) < 1.1 * 1.1:
		return false
	if chapter != null and chapter.blocks_player(Vector2(x,z)):
		return false
	return true

func _player_clip(wanted: String) -> StringName:
	if player_anim == null:
		return &""
	for clip in player_anim.get_animation_list():
		var name := str(clip)
		if name == wanted or name.ends_with("/" + wanted):
			return clip
	return &""

func _animate(running: bool, moving: bool) -> void:
	if player_anim == null:
		return
	var wanted := "Paki_Fast_Run" if running and moving else ("Paki_Walking" if moving else "Paki_Shared_Idle")
	var clip := _player_clip(wanted)
	if clip == &"" and running and moving:
		clip = _player_clip("Paki_Walking")
	if clip == &"":
		# Do not cache a missing animation as active: a model can otherwise
		# keep translating forever without the corresponding foot movement.
		if moving and _last_anim != "missing:" + wanted:
			push_warning("Не найдена анимация Паки: " + wanted)
		_last_anim = "missing:" + wanted
		player_anim.stop()
		return
	var sequence: Animation = player_anim.get_animation(clip)
	if sequence != null:
		sequence.loop_mode = Animation.LOOP_LINEAR
	# Imported GLB clips may finish after one cycle. Restart the clip if
	# Godot stopped it while the hero is still moving.
	if _last_anim == str(clip) and player_anim.is_playing() and player_anim.current_animation == str(clip):
		return
	player_anim.play(clip, 0.14 if moving else 0.16)
	_last_anim = str(clip)

func _input(event: InputEvent) -> void:
	# Web browsers permit sound after a real click, key or screen touch.
	if audio != null:
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			audio.begin()
	if not DisplayServer.is_touchscreen_available():
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var screen := get_viewport().get_visible_rect().size
		if touch.pressed:
			if _touch_move_id == -1 and touch.position.x < minf(235.0, screen.x * 0.40) and touch.position.y > screen.y * 0.50:
				_touch_move_id = touch.index
				_touch_origin = touch.position
			elif _touch_look_id == -1 and touch.position.x > screen.x * 0.43 and touch.position.y > screen.y * 0.38:
				var button_area := touch.position.x > screen.x - 210.0 and touch.position.y > screen.y - 205.0
				if not button_area:
					_touch_look_id = touch.index
		elif touch.index == _touch_move_id:
			_touch_move_id = -1
			_touch_axis = Vector2.ZERO
			if _touch_knob != null:
				_touch_knob.position = Vector2(46, 46)
		elif touch.index == _touch_look_id:
			_touch_look_id = -1
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _touch_move_id:
			var displacement := (drag.position - _touch_origin).limit_length(70.0)
			_touch_axis = displacement / 70.0
			if _touch_knob != null:
				_touch_knob.position = Vector2(46, 46) + displacement * (54.0 / 70.0)
		elif drag.index == _touch_look_id:
			yaw -= drag.relative.x * 0.006

func _unhandled_input(event: InputEvent) -> void:
	if chapter != null and chapter.menu_open:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * 0.006
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(14.0, camera_distance - 2.0)
			camera.size = maxf(18.0, camera.size - 1.7)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(49.0, camera_distance + 2.0)
			camera.size = minf(50.0, camera.size + 1.7)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E, KEY_SPACE: _interact()
			KEY_Q: _put_down_crate()
			KEY_N:
				if chapter == null: _toggle_night()
			KEY_P:
				if chapter == null: _cycle_weather()
			KEY_F7:
				if chapter == null: _open_material_library()

func _nearest() -> Dictionary:
	var best := {}
	var dist := 3.1
	for entry in interactive:
		var kind: String = entry["kind"]
		if kind == "leaf" and state["collected"].has(int(entry["index"])): continue
		if kind == "resource" and state["world"]["picked"].has("%s-%d" % [entry["resource"], entry["index"]]): continue
		if kind == "chest" and not bool(state["bridge"]): continue
		if kind == "portal" and not bool(state["bridge"]): continue
		if kind == "crate" and (bool(state["world"]["carryingCrate"]) or bool(state["world"]["crateDelivered"])): continue
		if kind == "orchard" and bool(state["world"]["orchardPicked"]): continue
		var p: Vector2 = entry["pos"]
		if kind == "crate":
			var location: Dictionary = state["world"]["cratePosition"]
			p = Vector2(float(location["x"]), float(location["z"]))
		elif kind == "builder" and builder_ai != null:
			p = Vector2(builder_ai.position.x, builder_ai.position.z)
		var d := Vector2(player.position.x, player.position.z).distance_to(p)
		if d < dist:
			dist = d
			best = entry
	if society != null:
		var visitor: Dictionary = society.nearest_interactable(Vector2(player.position.x, player.position.z), dist)
		if not visitor.is_empty():
			best = visitor
	if chapter != null:
		var contact: Dictionary = chapter.nearest(Vector2(player.position.x,player.position.z),dist)
		if not contact.is_empty():
			return contact
	return best

func _interact() -> void:
	if chapter != null and chapter.menu_open:
		return
	if action_time > 0.0:
		action_time = 0.0
		action_finish = Callable()
		_toast("Действие прервано.")
		return
	var t := _nearest()
	if t.is_empty():
		_toast("Рядом нет предметов. Ищи светящиеся растения у тропы.")
		return
	var kind: String = t["kind"]
	var i: int = int(t.get("index", 0))
	if chapter != null:
		if kind in ["chapter_site","resident"]:
			chapter.interact(str(t["id"]),kind=="resident")
			return
		if kind == "bridge":
			chapter.interact("bridge")
			return
		if kind == "lab":
			chapter.interact("craft")
			return
	match kind:
		"leaf":
			_do_action("Собираем светолист", func() -> void:
				state["collected"].append(i)
				_toast("Светолист собран! %d / 3" % mini(3, _herb_count()))
				if chapter != null:
					chapter.sim._give("herbs",1)
					_toast("Светолист собран: +1 пучок трав для алхимии.")
				if audio != null: audio.play_cue("pickup")
				_apply_state()
			)
		"lab":
			if bool(state["brewed"]):
				_toast("Алхимия пробудилась. Состав готов, пора к мосту.")
			elif _herb_count() < 3:
				_toast("Лаборатории нужны три светолиста.")
			else:
				state["brewed"] = true
				_toast("Древесный состав готов! Отправляйся восстанавливать мост.")
				_save()
		"bridge":
			if bool(state["bridge"]):
				_toast("Мост восстановлен. Дальний берег открыт!")
			elif not bool(state["brewed"]):
				_toast("Мост разрушен. Сначала приготовь состав в лаборатории.")
			else:
				state["bridge"] = true
				state["coins"] = int(state["coins"]) + 8
				_toast("Мост восстановлен! +8 сырликов.")
				if audio != null: audio.play_cue("build")
				_apply_state()
				_save()
		"portal":
			if not bool(state["portal"]):
				state["portal"] = true
				state["coins"] = int(state["coins"]) + 20
				_save()
			_toast("Загадка девяти миров: арка открыта! Впереди новые земли.")
		"resource":
			var item_kind: String = t["resource"]
			_do_action("Собираем материал", func() -> void:
				state["world"]["picked"].append("%s-%d" % [item_kind, i])
				state["world"]["bag"][item_kind] = int(state["world"]["bag"][item_kind]) + 1
				_toast("Материал получен: %s" % ("ветка" if item_kind == "wood" else "камень"))
				if audio != null: audio.play_cue("pickup")
				_apply_state()
			)
		"garden":
			_work_garden(i)
		"friend":
			if t["id"] == "mira":
				state["world"]["feederQuest"] = true
				_toast("Мира: Собери три ветки и два камня для кормушки.")
			elif bool(state["world"]["carryingCrate"]) and not bool(state["world"]["crateDelivered"]):
				state["world"]["carryingCrate"] = false
				state["world"]["crateDelivered"] = true
				state["coins"] = int(state["coins"]) + 10
				_toast("Тим: Спасибо за овощи! +10 сырликов.")
				_apply_state()
			else:
				_toast("Тим: Ищи записку в сундуке справа от костра.")
			_save()
		"feeder":
			var bag: Dictionary = state["world"]["bag"]
			if bool(state["world"]["feederBuilt"]):
				_toast("Птицы вернулись к кормушке!")
			elif int(bag["wood"]) < 3 or int(bag["stone"]) < 2:
				_toast("Для кормушки: веток %d/3, камней %d/2." % [int(bag["wood"]), int(bag["stone"])])
			else:
				bag["wood"] = int(bag["wood"]) - 3
				bag["stone"] = int(bag["stone"]) - 2
				state["world"]["feederBuilt"] = true
				state["coins"] = int(state["coins"]) + 8
				_toast("Кормушка построена! +8 сырликов.")
				_apply_state()
			_save()
		"chest":
			if not bool(state["world"]["chestOpened"]):
				state["world"]["chestOpened"] = true
				state["coins"] = int(state["coins"]) + 6
				_save()
			_toast("Записка Тима: ищи на севере каменный круг и башню. +6 при первом открытии.")
		"crate":
			_do_action("Поднимаем ящик", func() -> void:
				state["world"]["carryingCrate"] = true
				_toast("Доставь ящик Тиму. Нажми Q, чтобы поставить.")
				_apply_state()
			)
		"orchard":
			_do_action("Собираем яблоки", func() -> void:
				state["world"]["orchardPicked"] = true
				state["coins"] = int(state["coins"]) + 2
				_toast("Яблоки собраны. +2 сырлика.")
				_apply_state()
			)
		"builder":
			_show_builder_menu()
		"society":
			_toast(society.interact(str(t["id"])))
			_save()

func _show_builder_menu() -> void:
	if builder_ai == null or builder_menu == null:
		return
	if chapter != null:
		chapter.interact_builder()
		return
	builder_ai.set_paused(true)
	builder_menu.set_item_disabled(2, int(state["world"]["bag"]["wood"]) <= 0)
	builder_menu.set_item_disabled(3, int(state["world"]["bag"]["stone"]) <= 0)
	builder_menu.set_item_disabled(4, builder_ai.stage() >= workshop.total_stages())
	builder_menu.popup_centered()

func _on_builder_option(id: int) -> void:
	if builder_ai == null:
		return
	match id:
		0: builder_ai.command("follow")
		1: builder_ai.command("work")
		2, 3:
			var kind := "wood" if id == 2 else "stone"
			var bag: Dictionary = state["world"]["bag"]
			if int(bag[kind]) > 0:
				bag[kind] = int(bag[kind]) - 1
				if not builder_ai.donate(kind):
					bag[kind] = int(bag[kind]) + 1
			else:
				_toast("В сумке нет нужного материала.")
		4:
			if Vector2(player.position.x, player.position.z).distance_to(Vector2(workshop.position.x, workshop.position.z)) < 9.0:
				_build_workshop()
			else:
				_toast("Для стройки подойди к мастерской.")
		5:
			var stock: Dictionary = builder_ai.data["stock"]
			_toast("Склад Бруно: %d веток, %d камней. Он добывает их самостоятельно." % [int(stock["wood"]), int(stock["stone"])])
	builder_ai.set_paused(false)
	_save()

func _on_builder_event(note: String, stage: int) -> void:
	var previous := int(state["world"]["builder"].get("stage", 0))
	if stage > previous:
		if audio != null: audio.play_cue("build")
		workshop.set_stage(stage, true)
		world.set_workshop_stage(stage)
		if stage >= workshop.total_stages() and not bool(builder_ai.data["rewarded"]):
			state["coins"] = int(state["coins"]) + 8
			builder_ai.data["rewarded"] = true
	state["world"]["builder"] = builder_ai.snapshot()
	_toast("Бруно: " + note)
	_save()

func _build_workshop() -> void:
	if chapter != null:
		chapter.interact("workshop")
		return
	var stage := int(state["world"]["builder"].get("stage", 0))
	if stage >= workshop.total_stages():
		_toast("Бруно: Мастерская готова! Можно заниматься новыми заказами.")
		return
	var next_stage := stage + 1
	var cost: Dictionary = workshop.cost_for(next_stage)
	var bag: Dictionary = state["world"]["bag"]
	if int(bag["wood"]) < int(cost["wood"]) or int(bag["stone"]) < int(cost["stone"]):
		_toast("Бруно: %s. В сумке %d веток и %d камней." % [
			workshop.next_description(), int(bag["wood"]), int(bag["stone"])
		])
		return
	var title := str(workshop.stage_name(next_stage))
	_do_action("Строим: " + title, func() -> void:
		# Если Бруно закончил этап за это время, ничего не списываем дважды.
		if int(state["world"]["builder"].get("stage", 0)) != stage:
			_toast("Бруно уже закончил этот этап.")
			return
		# Расход происходит после окончания действия; отмена ничего не списывает.
		bag["wood"] = int(bag["wood"]) - int(cost["wood"])
		bag["stone"] = int(bag["stone"]) - int(cost["stone"])
		state["world"]["builder"]["stage"] = next_stage
		if builder_ai != null:
			builder_ai.player_completed_stage(next_stage)
		workshop.set_stage(next_stage, true)
		world.set_workshop_stage(next_stage)
		if next_stage == workshop.total_stages():
			if builder_ai != null:
				builder_ai.data["rewarded"] = true
			state["coins"] = int(state["coins"]) + 8
			_toast("Мастерская Бруно готова! +8 сырликов.")
		else:
			_toast("Бруно: %s готово. Следующий шаг: %s." % [title, workshop.next_description()])
		_apply_state()
	)

func _do_action(label: String, finished: Callable, duration: float = 1.25) -> void:
	if bool(state["world"]["carryingCrate"]):
		_toast("Сначала поставь ящик (Q).")
		return
	action_label = label
	action_time = duration
	action_finish = finished
	_toast("%s… (движение отменяет действие)" % label)

func _work_garden(index: int) -> void:
	var plot: Dictionary = state["garden"][index]
	var crop: Dictionary = ValleySave.GARDEN_TYPES[index]
	var phase := ValleySave.garden_phase(plot, Time.get_unix_time_from_system())
	var name: String = crop["name"]
	match phase:
		0:
			_do_action("Сажаем " + name, func() -> void:
				plot["plantedAt"] = int(Time.get_unix_time_from_system())
				plot["wateredAt"] = 0
				_toast("Посажено: %s. Теперь полей." % name)
				_apply_state()
			)
		1:
			_do_action("Поливаем " + name, func() -> void:
				plot["wateredAt"] = int(Time.get_unix_time_from_system())
				_toast("Ростки политы. Созреют через 45 секунд.")
				_apply_state()
			)
		4:
			_do_action("Собираем " + name, func() -> void:
				plot["plantedAt"] = 0
				plot["wateredAt"] = 0
				plot["harvested"] = int(plot["harvested"]) + 1
				state["harvests"] = int(state["harvests"]) + 1
				state["coins"] = int(state["coins"]) + int(crop["reward"])
				if index == 0:
					state["grownLeaves"] = int(state["grownLeaves"]) + 1
				_toast("Урожай: %s · +%d сырликов!" % [name, int(crop["reward"])])
				if chapter != null:
					chapter.sim._give("herbs" if index==0 else "food",1)
					_toast("Урожай: %s · +1 %s." % [name,"пучок трав" if index==0 else "порция еды"])
				_apply_state()
			)
		_:
			var remaining := maxi(1, 45 - int(Time.get_unix_time_from_system()) + int(plot["wateredAt"]))
			_toast("%s растёт. Осталось около %d секунд." % [name, remaining])

func _put_down_crate() -> void:
	if not bool(state["world"]["carryingCrate"]):
		return
	state["world"]["carryingCrate"] = false
	state["world"]["cratePosition"] = {"x": player.position.x, "z": player.position.z}
	_sync_crate()
	_toast("Ящик поставлен.")
	_save()

func _check_secret() -> void:
	var found: Dictionary = world.nearby_secret(player.position.x, player.position.z)
	if found.is_empty():
		return
	var secret_id: String = found["id"]
	if state["discoveries"].has(secret_id):
		return
	state["discoveries"].append(secret_id)
	state["coins"] = int(state["coins"]) + 2
	_toast("Открытие: %s! +2 сырлика." % str(found["name"]))
	if audio != null: audio.play_cue("discovery")
	_save()

func _herb_count() -> int:
	return state["collected"].size() + int(state["grownLeaves"])

func _update_ui() -> void:
	if ui_quest == null:
		return
	ui_quest.text = "ДОЛИНА БАБОЧЕК · " + QUESTS[ValleySave.quest_stage(state)]
	if chapter != null:
		ui_quest.text = "ДОЛИНА БАБОЧЕК · Свет над долиной"
	var climate_names := {
		"old_forest": "старый лес", "meadow": "цветущая поляна",
		"riverbank": "речной берег", "pine": "хвойный лес", "highland": "каменистые холмы",
		"wind_ridge": "скальные врата", "violet_heath": "цветы и вереск",
		"amber_wood": "золотистый древолес", "mosswood": "древние мхи",
		"bloom_garden": "поля диких цветов"
	}
	var local_biome: String = world.biome_at(player.position.x, player.position.z)
	ui_region.text = "%s · %s" % [world.region_name(player.position.x, player.position.z), climate_names.get(local_biome, "лес")]
	var bag: Dictionary = state["world"]["bag"]
	ui_inventory.text = "✦ %d сырликов   ✿ %d светолиста   🌱 %d урожаев   🪵 %d веток   ◈ %d камней" % [int(state["coins"]), _herb_count(), int(state["harvests"]), int(bag["wood"]), int(bag["stone"])]
	ui_weather.text = "Погода: %s · %s" % [("Дождь" if raining else "Ясно"), ("ночь" if bool(state["night"]) else "день")]
	if chapter != null:
		ui_inventory.text = "Сумка: "+chapter.sim.inventory_text(bag)
		ui_inventory.text += " · ✦ %d" % int(state["coins"])
		ui_weather.text = chapter._forecast()
	if builder_ai != null:
		var stock: Dictionary = builder_ai.data["stock"]
		ui_builder.text = "Бруно: %s · мастерская %d/%d · %s %d веток / %d камней" % [builder_ai.status(raining, bool(state["night"])), builder_ai.stage(), workshop.total_stages(), "общий амбар:" if chapter!=null else "склад:", int(stock["wood"]), int(stock["stone"]) ]
	_current = _nearest()
	if action_time > 0.0:
		ui_interact.text = "%s… %.1f с" % [action_label, action_time]
	elif _current.is_empty():
		ui_interact.text = "Исследуй долину · E — взаимодействовать рядом с объектами"
	else:
		var label := str(_current["kind"])
		match label:
			"leaf": label = "Собрать светолист"
			"lab": label = "Лаборатория алхимика"
			"bridge": label = "Восстановить мост" if not bool(state["bridge"]) else "Осмотреть мост"
			"portal": label = "Исследовать древнюю арку"
			"garden": label = "Ухаживать за грядкой"
			"resource": label = "Подобрать материал"
			"friend": label = "Поговорить: " + str(_current["name"])
			"feeder": label = "Собрать кормушку"
			"chest": label = "Открыть сундук"
			"crate": label = "Поднять ящик"
			"orchard": label = "Собрать яблоки"
			"builder": label = "Поговорить с Бруно · " + workshop.next_description()
			"society": label = "Познакомиться: " + str(_current["name"])
			"chapter_site": label = str(_current["name"])
			"resident": label = "Поговорить: " + str(_current["name"])
		ui_interact.text = "E · " + label

func _update_weather(delta: float) -> void:
	if weather_mode == "auto" and weather_elapsed > 120.0:
		weather_elapsed = 0.0
		raining = not raining
	elif weather_mode != "auto" and weather_mode != "chapter":
		raining = weather_mode == "rain"
	var night := bool(state["night"])
	night_mix = move_toward(night_mix, 1.0 if night else 0.0, delta * 0.7)
	sun.light_energy = lerpf(1.35, 0.2, night_mix) * (0.7 if raining else 1.0)
	environment.environment.ambient_light_energy = lerpf(0.65, 0.26, night_mix)
	environment.environment.background_color = Color("#a8c7c4").lerp(Color("#18283a"), night_mix)
	if chapter == null:
		environment.environment.fog_density = lerpf(0.004, 0.008, 1.0 if raining else 0.0)
	environment.environment.fog_light_color = Color("#a7bbaa").lerp(Color("#738a95"), 0.55 if raining else night_mix * 0.5)
	if chapter != null:
		var mist: bool = chapter.sim.weather()=="mist"
		var cloudy: bool = chapter.sim.weather() in ["overcast","storm"]
		environment.environment.fog_density = lerpf(environment.environment.fog_density,0.018 if mist else (0.009 if raining else 0.003),minf(1.0,delta*0.4))
		sun.light_color = Color("#afc5ea") if night else (Color("#e3dbc8") if cloudy else Color("#ffe3ad"))
		sun.rotation_degrees.x = -28.0 if night else -25.0-35.0*maxf(0.0,sin((chapter.sim.hour()-6.0)/12.0*PI))
		if environment.environment.sky != null:
			var sky_material := environment.environment.sky.sky_material as ProceduralSkyMaterial
			if sky_material != null:
				sky_material.sky_top_color = Color("#748794") if cloudy else Color("#6c9dbb").lerp(Color("#111c33"),night_mix)
				sky_material.sky_horizon_color = Color("#abb8af").lerp(Color("#273648"),night_mix)
		if _is_forward_plus():
			environment.environment.volumetric_fog_density = 0.022 if mist else (0.011 if raining else 0.006)
		world.set_weather_wetness(1.0 if raining else 0.0)
		if raining:
			for plot in state["garden"]:
				if int(plot.get("plantedAt",0))>0 and int(plot.get("wateredAt",0))<=0:
					plot["wateredAt"] = Time.get_unix_time_from_system()

func _configure_starting_quality() -> void:
	# Windows desktop builds start with a full forest, animated wildlife and shadows.
	# Lower-end machines retain the manual "экономная" option in the HUD.
	if not _is_desktop_release():
		return
	if OS.get_cmdline_user_args().has("--safe-graphics"):
		quality_button.text = "Графика: экономная"
		return
	world.set_quality(true)
	fauna.set_detailed(true)
	society.set_detailed(true)
	sun.shadow_enabled = true
	quality_button.text = "Графика: детальная"

func _toggle_quality() -> void:
	world.set_quality(not world.high_quality)
	quality_button.text = "Графика: детальная" if world.high_quality else "Графика: экономная"
	if fauna != null:
		fauna.set_detailed(world.high_quality)
	if society != null:
		society.set_detailed(world.high_quality)
	sun.shadow_enabled = world.high_quality
	if _is_forward_plus():
		environment.environment.ssao_enabled = world.high_quality
		environment.environment.volumetric_fog_enabled = world.high_quality
	if rain_particles != null:
		rain_particles.amount = 220 if world.high_quality else 100
	_toast("Режим графики изменён. Лес подгрузится заново.")

func _toggle_night() -> void:
	state["night"] = not bool(state["night"])
	if fauna != null:
		fauna.set_night(bool(state["night"]))
	if society != null:
		society.set_night(bool(state["night"]))
	_save()

func _cycle_weather() -> void:
	match weather_mode:
		"auto": weather_mode = "clear"
		"clear": weather_mode = "rain"
		_: weather_mode = "auto"
	state["weather"] = weather_mode
	weather_elapsed = 0
	_toast("Погода: %s" % weather_mode)
	_save()

func _toast(message: String) -> void:
	if ui_message != null:
		ui_message.text = message
	message_time = 6.5

func _open_material_library() -> void:
	# Витрина отделена от мира: прогресс сохраняем до смены сцены.
	_save()
	get_tree().change_scene_to_file("res://scenes/material_library.tscn")

func _restore_library_placements() -> void:
	for item in MaterialPlacements.read_all():
		_spawn_library_placement(item)

func _spawn_library_placement(item: Dictionary) -> void:
	var id := str(item.get("id", ""))
	var model: Node3D = MaterialLibrary.create(id)
	if model == null:
		return
	var x := float(item.get("x", 0.0))
	var z := float(item.get("z", 0.0))
	var pivot := Node3D.new()
	pivot.name = "Размещённый материал · " + id
	pivot.position = Vector3(x, world.ground_height(x, z), z)
	pivot.rotation.y = float(item.get("rotation", 0.0))
	add_child(pivot)
	pivot.add_child(model)
	MaterialLibrary.fit_visual(model, MaterialLibrary.desired_height(id))
	if bool(MaterialLibrary.find(id).get("rigged", false)):
		MaterialLibrary.play_idle(model)
	library_placed.append(pivot)

func _consume_pending_material() -> void:
	var id := MaterialPlacements.take_pending()
	if id == "":
		return
	var placed: Array = MaterialPlacements.read_all()
	var choice := Vector2.ZERO
	var found := false
	# Несколько колец вокруг Паки, без пересечения с другими пользовательскими объектами.
	for radius in [3.2, 4.6, 6.0, 7.4, 8.8]:
		if found:
			break
		for index in range(16):
			var angle := player.rotation.y + TAU * float(index) / 16.0
			var candidate: Vector2 = Vector2(player.position.x, player.position.z) + Vector2(cos(angle), sin(angle)) * radius
			if not world.can_walk(candidate.x, candidate.y, bool(state["bridge"])):
				continue
			var occupied := false
			for other in placed:
				if Vector2(float(other["x"]), float(other["z"])).distance_to(candidate) < 1.65:
					occupied = true
					break
			if occupied:
				continue
			choice = candidate
			found = true
			break
	if not found:
		_toast("Рядом недостаточно свободного места для нового материала.")
		return
	var record := {"id": id, "x": choice.x, "z": choice.y, "rotation": player.rotation.y}
	if MaterialPlacements.add(record):
		_spawn_library_placement(record)
		_toast("Размещено: " + str(MaterialLibrary.find(id).get("title", id)))
	else:
		_toast("Достигнут предел 32 объектов или не удалось сохранить материал.")

func _save() -> void:
	state["position"] = {"x": player.position.x, "z": player.position.z}
	if builder_ai != null:
		state["world"]["builder"] = builder_ai.snapshot()
	if society != null:
		state["world"]["society"] = society.snapshot()
	if chapter != null:
		state["world"]["chapter"] = chapter.snapshot()
	if not ValleySave.write(state,save_path):
		_toast("Не удалось сохранить игру. Проверь свободное место на диске и доступ к папке сохранений.")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and player != null:
		_save()

