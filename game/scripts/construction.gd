extends Node3D
const Fitting = preload("res://scripts/model_fitting.gd")
## Строительная площадка Бруно: пять видимых стадий из повторно используемых деталей.
## Стены, пол, двери, окна и крыша используют модули Quaternius, если они
## импортированы. ПК-сборка проверяет их наличие до выпуска.

const STAGE_NAMES := [
	"Размеченный участок",
	"Каменный фундамент",
	"Деревянный каркас",
	"Стены и проёмы",
	"Крыша",
	"Готовая мастерская"
]
const COSTS := [
	{"wood": 0, "stone": 0},
	{"wood": 0, "stone": 1},
	{"wood": 1, "stone": 0},
	{"wood": 1, "stone": 0},
	{"wood": 1, "stone": 0},
	{"wood": 0, "stone": 1}
]
const STAGE_COUNT := 5

var appearance := "workshop" # workshop, cottage, barn, alchemist
var variant := 0
var _frame_visual: Node3D
var current_stage := 0
var stage_groups: Array[Node3D] = []
var _materials: Dictionary = {}

func _ready() -> void:
	for i in range(STAGE_COUNT + 1):
		var group := Node3D.new()
		group.name = STAGE_NAMES[i]
		add_child(group)
		stage_groups.append(group)
	_make_site()
	_make_foundation()
	_make_frame()
	_make_walls()
	_make_roof()
	_make_finishing()
	set_stage(current_stage)

func total_stages() -> int:
	return STAGE_COUNT

func stage_name(value: int) -> String:
	return STAGE_NAMES[clampi(value, 0, STAGE_COUNT)]

func cost_for(next_stage: int) -> Dictionary:
	if next_stage < 1 or next_stage > STAGE_COUNT:
		return {"wood": 0, "stone": 0}
	return COSTS[next_stage].duplicate()

func next_description() -> String:
	if current_stage >= STAGE_COUNT:
		return "Мастерская готова"
	var target := current_stage + 1
	var cost := cost_for(target)
	var supplies := PackedStringArray()
	if int(cost["wood"]) > 0:
		supplies.append("ветки %d" % int(cost["wood"]))
	if int(cost["stone"]) > 0:
		supplies.append("камни %d" % int(cost["stone"]))
	return "%s (%s)" % [STAGE_NAMES[target], ", ".join(supplies)]

func set_stage(value: int, animate: bool = false) -> void:
	var previous := current_stage
	current_stage = clampi(value, 0, STAGE_COUNT)
	if stage_groups.is_empty():
		return
	for i in range(stage_groups.size()):
		stage_groups[i].visible = (i == 0 and current_stage == 0) or (i > 0 and i <= current_stage)
	# Temporary structural beams belong to the framing stage. Finished homes
	# show the imported plaster walls rather than protruding box-shaped poles.
	if _frame_visual != null:
		_frame_visual.visible = current_stage == 2
	if animate and current_stage > previous:
		var fresh: Node3D = stage_groups[current_stage]
		fresh.scale = Vector3(1.0, 0.03, 1.0)
		var tween := create_tween()
		tween.tween_property(fresh, "scale", Vector3.ONE, 0.65).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.86
		_materials[key] = mat
	return _materials[key]

func _part(step: int, title: String, size: Vector3, at: Vector3, tint: Color, angle: float = 0.0, owner: Node3D = null) -> void:
	var piece := MeshInstance3D.new()
	piece.name = title
	var shape := BoxMesh.new()
	shape.size = size
	piece.mesh = shape
	piece.material_override = _material(tint)
	piece.position = at
	piece.rotation.z = angle
	(owner if owner != null else stage_groups[step]).add_child(piece)

func _has_module(model_name: String) -> bool:
	return ResourceLoader.exists("res://assets/buildings/village/%s.gltf" % model_name)

func _module(step: int, model_name: String, at: Vector3, yaw: float = 0.0, scale_factor: Vector3 = Vector3.ONE) -> bool:
	var path := "res://assets/buildings/village/%s.gltf" % model_name
	if not ResourceLoader.exists(path):
		return false
	var scene := load(path) as PackedScene
	if scene == null:
		return false
	var model := scene.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Quaternius_" + model_name
	model.position = at
	model.rotation.y = yaw
	model.scale = scale_factor
	stage_groups[step].add_child(model)
	return true

func _make_site() -> void:
	var stake := Color("#9d7449")
	var twine := Color("#d2ba77")
	for x in [-3.65, 3.65]:
		for z in [-3.15, 3.15]:
			_part(0, "Разметочный колышек", Vector3(0.13, 0.82, 0.13), Vector3(x, 0.4, z), stake)
	for z in [-3.15, 3.15]:
		_part(0, "Шнур вдоль стены", Vector3(7.3, 0.035, 0.035), Vector3(0, 0.57, z), twine)
	for x in [-3.65, 3.65]:
		_part(0, "Шнур поперёк", Vector3(0.035, 0.035, 6.3), Vector3(x, 0.57, 0), twine)

func _make_foundation() -> void:
	var stone := Color("#8f938c")
	var mortar := Color("#beb8a5")
	# The stone trim texture from the same village kit makes the plinth
	# read as masonry, even while the building is still being assembled.
	var masonry := _material(stone)
	if ResourceLoader.exists("res://assets/buildings/village/T_RockTrim_BaseColor.png"):
		masonry.albedo_texture = load("res://assets/buildings/village/T_RockTrim_BaseColor.png")
		masonry.uv1_triplanar = true
	_part(1, "Утрамбованная площадка", Vector3(7.0, 0.16, 6.0), Vector3(0, 0.04, 0), mortar)
	for z in [-2.95, 2.95]:
		_part(1, "Каменный цоколь", Vector3(7.4, 0.57, 0.56), Vector3(0, 0.31, z), stone)
	for x in [-3.4, 3.4]:
		_part(1, "Каменный цоколь", Vector3(0.52, 0.57, 5.4), Vector3(x, 0.31, 0), stone)

func _make_frame() -> void:
	# Genuine timber floor modules remain visible after the walls are finished.
	if _has_module("Floor_WoodDark"):
		for x in [-2.0, 0.0, 2.0]:
			for z in [-2.0, 0.0, 2.0]:
				_module(2, "Floor_WoodDark", Vector3(x, 0.66, z))
	_frame_visual = Node3D.new()
	_frame_visual.name = "Временные балки каркаса"
	stage_groups[2].add_child(_frame_visual)
	var oak := Color("#80603e")
	for x in [-3.23, 3.23]:
		for z in [-2.75, 2.75]:
			_part(2, "Угловой столб", Vector3(0.36, 3.45, 0.36), Vector3(x, 2.02, z), oak, 0.0, _frame_visual)
	for z in [-2.75, 2.75]:
		_part(2, "Верхняя обвязка", Vector3(6.8, 0.30, 0.32), Vector3(0, 3.69, z), oak, 0.0, _frame_visual)
	for x in [-3.23, 3.23]:
		_part(2, "Поперечная балка", Vector3(0.31, 0.30, 5.75), Vector3(x, 3.69, 0), oak, 0.0, _frame_visual)
	_part(2, "Коньковая балка", Vector3(0.24, 0.24, 6.4), Vector3(0, 5.22, 0), oak, 0.0, _frame_visual)

func _front_has_window(x: float) -> bool:
	if appearance == "barn":
		return false
	if appearance != "cottage" or variant % 3 == 0:
		return true
	return x > 0.0 if variant % 3 == 1 else x < 0.0


func _make_walls() -> void:
	# Windows, doors and wall sections are real textured 2-metre Quaternius
	# modules. The four building types have different facades.
	if _has_module("Wall_Plaster_Straight") and _has_module("Wall_Plaster_Door_Flat") and _has_module("Wall_Plaster_Window_Wide_Flat"):
		for x in [-2.0, 0.0, 2.0]:
			var rear := "Wall_Plaster_Window_Wide_Flat" if appearance == "alchemist" and is_zero_approx(x) else "Wall_Plaster_Straight"
			_module(3, rear, Vector3(x, 0.66, -2.82), PI)
		for x in [-2.0, 0.0, 2.0]:
			var front := "Wall_Plaster_Door_Flat" if is_zero_approx(x) else ("Wall_Plaster_Window_Wide_Flat" if _front_has_window(x) else "Wall_Plaster_Straight")
			_module(3, front, Vector3(x, 0.66, 2.82))
		for z in [-2.0, 0.0, 2.0]:
			var side := "Wall_Plaster_Window_Wide_Flat" if is_zero_approx(z) and appearance in ["cottage", "alchemist"] else "Wall_Plaster_Straight"
			_module(3, side, Vector3(-3.02, 0.66, z), -PI * 0.5)
			_module(3, side, Vector3(3.02, 0.66, z), PI * 0.5)
		return
	# Fallback for environments without downloaded village models.
	var plaster := Color("#d8c7a4")
	var oak := Color("#80563b")
	_part(3, "Задняя стена", Vector3(6.45, 2.85, 0.20), Vector3(0, 2.12, -2.72), plaster)
	for x in [-3.11, 3.11]:
		_part(3, "Боковая стена", Vector3(0.21, 2.85, 5.15), Vector3(x, 2.12, 0), plaster)
	for x in [-2.15, 2.15]:
		_part(3, "Стена у входа", Vector3(2.05, 2.85, 0.23), Vector3(x, 2.12, 2.72), plaster)
	_part(3, "Перемычка над дверью", Vector3(2.24, 0.49, 0.25), Vector3(0, 3.31, 2.72), oak)

func _make_roof() -> void:
	# Slight overhangs and different roof profiles keep the buildings legible
	# from the third-person camera without adding hundreds of unique meshes.
	if appearance == "alchemist" and _module(4, "Roof_RoundTiles_8x8", Vector3(0, 3.90, 0), 0.0, Vector3(0.74, 0.56, 0.74)):
		return
	if appearance == "barn" and _module(4, "Roof_RoundTiles_6x4", Vector3(0, 3.84, -3.17), 0.0, Vector3(0.90, 0.58, 1.35)):
		return
	if _module(4, "Roof_RoundTiles_6x6", Vector3(0, 3.80, 0), 0.0, Vector3(0.88, 0.60, 0.88)):
		return
	var shingle := Color("#97534a")
	_part(4, "Крыша (резервная геометрия)", Vector3(7.2, 0.28, 7.0), Vector3(0, 4.6, 0), shingle)



func _detail_asset(id: String, at: Vector3, height: float) -> void:
	var path := "res://assets/%s.glb" % id
	if not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var imported := packed.instantiate() as Node3D
	if imported == null:
		return
	var anchor := Node3D.new()
	anchor.name = "Деталь окружения · " + id
	anchor.position = at
	anchor.add_child(Fitting.wrap_to_height(imported, height))
	stage_groups[5].add_child(anchor)


func _make_finishing() -> void:
	var oak := Color("#6e4930")
	var brass := Color("#c9a665")
	var glass := Color("#84b5ba")
	# Doors and window frames from the kit, rather than flat tinted boxes.
	if not _module(5, "Door_1_Flat", Vector3(-0.51, 0.66, 3.03)):
		_part(5, "Входная дверь", Vector3(1.68, 2.48, 0.14), Vector3(0, 1.73, 2.93), oak)
	if appearance != "barn":
		for x in [-2.0, 2.0]:
			if not _front_has_window(x):
				continue
			if not _module(5, "Window_Wide_Flat1", Vector3(x, 0.66, 3.03)):
				_part(5, "Окно", Vector3(0.84, 0.93, 0.15), Vector3(x, 2.14, 2.96), glass)
	if appearance in ["cottage", "alchemist"]:
		_module(5, "Window_Wide_Flat1", Vector3(-3.22, 0.66, 0), -PI * 0.5)
		_module(5, "Window_Wide_Flat1", Vector3(3.22, 0.66, 0), PI * 0.5)
	if appearance == "alchemist":
		_module(5, "Window_Wide_Flat1", Vector3(0, 0.66, -3.03), PI)
	# A timber doorstep visually connects the door with the footpath.
	_module(5, "Floor_WoodDark", Vector3(0, 0.68, 3.65), 0.0, Vector3(1.05, 1.0, 0.82))
	if appearance in ["cottage", "alchemist"]:
		# A small tiled porch projects from the main roof.
		_module(5, "Roof_RoundTiles_4x4", Vector3(0, 3.11, 3.23), 0.0, Vector3(0.43, 0.20, 0.38))
	_detail_asset("lantern-glass", Vector3(-1.22, 2.45, 3.08), 0.52)
	if appearance == "workshop":
		_detail_asset("log-stack", Vector3(4.20, 0.10, 1.65), 1.1)
		_detail_asset("pot-large", Vector3(4.0, 0.09, -1.0), 0.68)
	elif appearance == "barn":
		_detail_asset("log-stack", Vector3(4.1, 0.09, 2.1), 1.7)
		_detail_asset("log-stack", Vector3(-4.2, 0.09, 1.4), 1.0)
	elif appearance == "alchemist":
		_detail_asset("pot-large", Vector3(4.2, 0.06, 2.5), 1.15)
		_detail_asset("mushroom-redgroup", Vector3(-4.2, 0.06, 1.8), 0.70)
	else:
		var flower := "flower-purpleb" if variant % 2 == 0 else "flower-yellowa"
		for x in [-4.0, 4.0]:
			_detail_asset(flower, Vector3(x, 0.02, 2.2), 0.78)
		_detail_asset("plant-bushdetailed", Vector3(-4.0, 0.03, -1.9), 1.1)
	if appearance in ["workshop", "barn", "alchemist"]:
		var label := Label3D.new()
		label.text = "МАСТЕРСКАЯ" if appearance == "workshop" else ("ОБЩИЙ АМБАР" if appearance == "barn" else "ЛАБОРАТОРИЯ")
		label.name = "Вывеска на фасаде"
		label.font_size = 38
		label.pixel_size = 0.007
		label.outline_size = 5
		label.modulate = Color("#f6dfae")
		label.position = Vector3(0, 3.45, 3.09)
		stage_groups[5].add_child(label)
	# A narrow stone chimney remains useful for identifying a lived-in house.
	if appearance in ["alchemist", "cottage"]:
		_part(5, "Каменный дымоход", Vector3(0.58, 1.55, 0.58), Vector3(2.10, 5.12, -1.0), Color("#a1917d"))
