extends RefCounted
## Отдельное сохранение расставленных материалов. Не меняет формат сюжета ValleySave.
## Демонстрационные животные анимируются на месте; самостоятельной логики ещё нет.

const FILE := "user://butterfly_material_placements.json"
const PENDING_FILE := "user://butterfly_material_pending.json"
const MAX_PLACEMENTS := 32
const LIBRARY = preload("res://scripts/asset_library.gd")

static func read_all() -> Array:
	if not FileAccess.file_exists(FILE):
		return []
	var handle := FileAccess.open(FILE, FileAccess.READ)
	if handle == null:
		return []
	var parsed = JSON.parse_string(handle.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		return []
	var result := []
	for item in parsed:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if LIBRARY.find(str(item.get("id", ""))).is_empty():
			continue
		if not item.has("x") or not item.has("z"):
			continue
		result.append(item)
		if result.size() >= MAX_PLACEMENTS:
			break
	return result

static func write_all(items: Array) -> bool:
	var handle := FileAccess.open(FILE, FileAccess.WRITE)
	if handle == null:
		push_warning("Не удалось сохранить расставленные материалы.")
		return false
	handle.store_string(JSON.stringify(items))
	return true

static func add(item: Dictionary) -> bool:
	if LIBRARY.find(str(item.get("id", ""))).is_empty():
		return false
	var placements := read_all()
	if placements.size() >= MAX_PLACEMENTS:
		return false
	placements.append(item)
	return write_all(placements)

static func pop_last() -> String:
	var placements := read_all()
	if placements.is_empty():
		return ""
	var last: Dictionary = placements.pop_back()
	if write_all(placements):
		return str(last.get("id", ""))
	return ""

static func queue_asset(id: String) -> bool:
	if LIBRARY.find(id).is_empty():
		return false
	if read_all().size() >= MAX_PLACEMENTS:
		return false
	var handle := FileAccess.open(PENDING_FILE, FileAccess.WRITE)
	if handle == null:
		return false
	handle.store_string(JSON.stringify({"id": id}))
	return true

static func take_pending() -> String:
	if not FileAccess.file_exists(PENDING_FILE):
		return ""
	var handle := FileAccess.open(PENDING_FILE, FileAccess.READ)
	if handle == null:
		return ""
	var parsed = JSON.parse_string(handle.get_as_text())
	handle = null
	# Сбрасываем команду перед применением, чтобы повторная загрузка её не дублировала.
	var clean := FileAccess.open(PENDING_FILE, FileAccess.WRITE)
	if clean != null:
		clean.store_string("{}")
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var id := str(parsed.get("id", ""))
	return id if not LIBRARY.find(id).is_empty() else ""

