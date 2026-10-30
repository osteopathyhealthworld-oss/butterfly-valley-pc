extends Node3D
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

func _part(step: int, title: String, size: Vector3, at: Vector3, tint: Color, angle: float = 0.0) -> void:
	var piece := MeshInstance3D.new()
	piece.name = title
	var shape := BoxMesh.new()
	shape.size = size
	piece.mesh = shape
	piece.material_override = _material(tint)
	piece.position = at
	piece.rotation.z = angle
	stage_groups[step].add_child(piece)

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
	_part(1, "Утрамбованная площадка", Vector3(7.0, 0.16, 6.0), Vector3(0, 0.04, 0), mortar)
	for z in [-2.95, 2.95]:
		_part(1, "Каменный цоколь", Vector3(7.4, 0.57, 0.56), Vector3(0, 0.31, z), stone)
	for x in [-3.4, 3.4]:
		_part(1, "Каменный цоколь", Vector3(0.52, 0.57, 5.4), Vector3(x, 0.31, 0), stone)

func _make_frame() -> void:
	# На каркас укладываются девять секций пола Quaternius размером 2 x 2 м.
	if _has_module("Floor_WoodDark"):
		for x in [-2.0, 0.0, 2.0]:
			for z in [-2.0, 0.0, 2.0]:
				_module(2, "Floor_WoodDark", Vector3(x, 0.66, z))
	var oak := Color("#80603e")
	for x in [-3.23, 3.23]:
		for z in [-2.75, 2.75]:
			_part(2, "Угловой столб", Vector3(0.36, 3.45, 0.36), Vector3(x, 2.02, z), oak)
	for z in [-2.75, 2.75]:
		_part(2, "Верхняя обвязка", Vector3(6.8, 0.30, 0.32), Vector3(0, 3.69, z), oak)
	for x in [-3.23, 3.23]:
		_part(2, "Поперечная балка", Vector3(0.31, 0.30, 5.75), Vector3(x, 3.69, 0), oak)
	_part(2, "Коньковая балка", Vector3(0.24, 0.24, 6.4), Vector3(0, 5.22, 0), oak)

func _make_walls() -> void:
	# Фасад состоит из двух оконных секций и дверного проёма.
	# Модули Quaternius имеют ширину 2 м и высоту 3.12 м.
	if _has_module("Wall_Plaster_Straight") and _has_module("Wall_Plaster_Door_Flat") and _has_module("Wall_Plaster_Window_Wide_Flat"):
		for x in [-2.0, 0.0, 2.0]:
			_module(3, "Wall_Plaster_Straight", Vector3(x, 0.66, -2.82), PI)
		for x in [-2.0, 2.0]:
			_module(3, "Wall_Plaster_Window_Wide_Flat", Vector3(x, 0.66, 2.82))
		_module(3, "Wall_Plaster_Door_Flat", Vector3(0, 0.66, 2.82))
		for z in [-2.0, 0.0, 2.0]:
			_module(3, "Wall_Plaster_Straight", Vector3(-3.02, 0.66, z), -PI * 0.5)
			_module(3, "Wall_Plaster_Straight", Vector3(3.02, 0.66, z), PI * 0.5)
		return
	var plaster := Color("#d8c7a4")
	var oak := Color("#80563b")
	_part(3, "Задняя стена", Vector3(6.45, 2.85, 0.20), Vector3(0, 2.12, -2.72), plaster)
	for x in [-3.11, 3.11]:
		_part(3, "Боковая стена", Vector3(0.21, 2.85, 5.15), Vector3(x, 2.12, 0), plaster)
	for x in [-2.15, 2.15]:
		_part(3, "Стена у входа", Vector3(2.05, 2.85, 0.23), Vector3(x, 2.12, 2.72), plaster)
	_part(3, "Перемычка над дверью", Vector3(2.24, 0.49, 0.25), Vector3(0, 3.31, 2.72), oak)
	for x in [-1.8, 1.8]:
		_part(3, "Наружная стойка", Vector3(0.18, 2.85, 0.27), Vector3(x, 2.12, 2.88), oak)
	_part(3, "Горизонтальная балка фасада", Vector3(6.5, 0.22, 0.28), Vector3(0, 2.72, 2.89), oak)

func _make_roof() -> void:
	# Единая скатная крыша Quaternius; масштаб подогнан под площадь 6 x 6 м.
	if _module(4, "Roof_RoundTiles_6x6", Vector3(0, 3.75, 0), 0.0, Vector3(0.76, 0.60, 0.76)):
		return
	var shingle := Color("#97534a")
	var trim := Color("#6b4838")
	_part(4, "Левый скат черепицы", Vector3(4.07, 0.24, 6.55), Vector3(-1.69, 4.61, 0), shingle, 0.42)
	_part(4, "Правый скат черепицы", Vector3(4.07, 0.24, 6.55), Vector3(1.69, 4.61, 0), shingle, -0.42)
	_part(4, "Конёк", Vector3(0.34, 0.28, 6.68), Vector3(0, 5.38, 0), trim)

func _make_finishing() -> void:
	var oak := Color("#6e4930")
	var brass := Color("#c9a665")
	var glass := Color("#84b5ba")
	if not _module(5, "Door_1_Flat", Vector3(-0.51, 0.66, 3.03)):
		_part(5, "Входная дверь", Vector3(1.68, 2.48, 0.14), Vector3(0, 1.73, 2.93), oak)
		_part(5, "Дверная ручка", Vector3(0.14, 0.14, 0.12), Vector3(0.61, 1.67, 3.06), brass)
	for x in [-2.0, 2.0]:
		if not _module(5, "Window_Wide_Flat1", Vector3(x, 0.66, 3.03)):
			_part(5, "Окно мастерской", Vector3(0.84, 0.93, 0.15), Vector3(x, 2.14, 2.96), glass)
			_part(5, "Подоконник", Vector3(1.02, 0.12, 0.27), Vector3(x, 1.63, 3.0), oak)
	_part(5, "Вывеска", Vector3(2.72, 0.42, 0.20), Vector3(0, 3.59, 3.06), brass)
	_part(5, "Ящик с инструментами", Vector3(1.04, 0.65, 0.73), Vector3(4.13, 0.46, 1.8), oak)
	_part(5, "Фонарь у двери", Vector3(0.32, 0.49, 0.29), Vector3(-1.25, 3.03, 3.07), brass)
	_part(5, "Дымоход", Vector3(0.66, 1.26, 0.68), Vector3(1.9, 5.19, -1.3), Color("#a1917d"))

