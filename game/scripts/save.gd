extends RefCounted
class_name ValleySave
## Эквиваленты основных полей сохранения Babylon-версии.
## Godot хранит их в user://; localStorage браузерной игры сюда сам не импортируется.

const FILE_PATH := "user://butterfly_valley_v1.json"
const GARDEN_TYPES := [
	{"name": "Светолист", "model": "plant-bushdetailed", "reward": 3},
	{"name": "Солнечный колос", "model": "crops-wheatstageb", "reward": 4},
	{"name": "Янтарная тыква", "model": "crop-pumpkin", "reward": 5},
	{"name": "Лунная репа", "model": "crop-turnip", "reward": 3},
	{"name": "Лесная морковь", "model": "crop-carrot", "reward": 3},
	{"name": "Золотая кукуруза", "model": "crops-cornstaged", "reward": 5}
]
const GARDEN_POSITIONS := [
	Vector2(-20.6, -30.5), Vector2(-17.0, -30.5), Vector2(-13.4, -30.5),
	Vector2(-20.6, -34.1), Vector2(-17.0, -34.1), Vector2(-13.4, -34.1)
]
const GROW_SECONDS := 45.0

static func fresh() -> Dictionary:
	var garden: Array = []
	for i in range(6):
		garden.append({"plantedAt": 0, "wateredAt": 0, "harvested": 0})
	return {
		"collected": [], "brewed": false, "bridge": false, "portal": false,
		"coins": 12, "discoveries": [], "position": {"x": -4.2, "z": -18.3},
		"garden": garden, "harvests": 0, "grownLeaves": 0,
		"world": {
			"bag": {"wood": 0, "stone": 0}, "picked": [], "feederQuest": false,
			"feederBuilt": false, "chestOpened": false, "carryingCrate": false,
			"crateDelivered": false, "cratePosition": {"x": -6.0, "z": -35.5},
			"orchardPicked": false, "builder": {"stage": 0}, "society": {}
		},
		"weather": "auto", "night": false
	}

static func _read_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text())!=OK: return {}
	var parsed = parser.data
	return parsed if parsed is Dictionary else {}

static func _fill_defaults(data: Dictionary, defaults: Dictionary) -> void:
	for key in defaults:
		# JSON читает числа как float. Проверка только typeof сбрасывала
		# сохранённые монеты и счётчики к начальным значениям.
		if typeof(defaults[key])==TYPE_INT and (data.get(key) is int or data.get(key) is float):
			data[key]=int(data[key]) if is_finite(float(data[key])) else defaults[key]
		elif not data.has(key) or typeof(data[key])!=typeof(defaults[key]):
			data[key]=defaults[key]

static func read(path: String = FILE_PATH) -> Dictionary:
	var defaults := fresh()
	var data := _read_dictionary(path)
	if data.is_empty(): data = _read_dictionary(path+".tmp")
	if data.is_empty(): data = _read_dictionary(path+".bak")
	if data.is_empty(): return defaults
	_fill_defaults(data,defaults)
	var world: Dictionary = data["world"]
	_fill_defaults(world,defaults["world"])
	var garden: Array = data["garden"]
	while garden.size() < 6:
		garden.append({"plantedAt": 0, "wateredAt": 0, "harvested": 0})
	return data

static func write(state: Dictionary, path: String = FILE_PATH) -> bool:
	# Сначала полностью записываем новый файл. Действующий JSON сохраняется
	# в .bak; загрузка умеет восстановиться после прерванной замены.
	var pending := path+".tmp"
	var backup := path+".bak"
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось сохранить игру: %d" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(state, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK: return false
	if FileAccess.file_exists(path):
		if not _read_dictionary(path).is_empty():
			if DirAccess.copy_absolute(path,backup)!=OK: return false
		if DirAccess.remove_absolute(path)!=OK: return false
	if DirAccess.rename_absolute(pending,path)!=OK:
		if FileAccess.file_exists(backup): DirAccess.copy_absolute(backup,path)
		return false
	return true

static func garden_phase(plot: Dictionary, now_unix: float) -> int:
	if int(plot.get("plantedAt", 0)) <= 0:
		return 0
	if int(plot.get("wateredAt", 0)) <= 0:
		return 1
	var passed: float = maxf(0.0, now_unix - float(plot["wateredAt"]))
	if passed >= GROW_SECONDS:
		return 4
	if passed >= GROW_SECONDS * 0.48:
		return 3
	return 2

static func quest_stage(state: Dictionary) -> int:
	if bool(state["portal"]):
		return 4
	if bool(state["bridge"]):
		return 3
	if bool(state["brewed"]):
		return 2
	if state["collected"].size() + int(state["grownLeaves"]) >= 3:
		return 1
	return 0

