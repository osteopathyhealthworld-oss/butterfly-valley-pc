extends SceneTree
# Проверка импортированных GLB, скелетов и анимаций.
const SPECIES := ["Fox", "Bat", "Duck", "Platypus", "Corgi", "Tarsier", "Sheep", "Pig", "Rooster"]
const GOBKIT_PATHS := {
	"Tarsier": "forest/Tarsier", "Sheep": "farm/Sheep",
	"Pig": "farm/Pig", "Rooster": "bird/Rooster"
}

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	for species in SPECIES:
		var path: String = "res://library/prepared/gobkit/%s.glb" % GOBKIT_PATHS[species] if GOBKIT_PATHS.has(species) else "res://fauna_assets/%s.glb" % species
		if not _require(ResourceLoader.exists(path), "Нет GLB: " + path):
			return
		var scene := load(path) as PackedScene
		if not _require(scene != null, "Не импортирован GLB: " + path):
			return
		var animal := scene.instantiate()
		if not _require(animal != null, "Не создано животное: " + species):
			return
		root.add_child(animal)
		var player := _find_player(animal)
		if not _require(player != null, "Нет AnimationPlayer: " + species):
			return
		var names := player.get_animation_list()
		if not _require(not names.is_empty(), "Нет анимаций: " + species):
			return
		if species == "Fox":
			for expected in ["survey", "walk", "run"]:
				var found := false
				for candidate in names:
					if str(candidate).to_lower().ends_with(expected):
						found = true
				if not _require(found, "Лиса: отсутствует " + expected):
					return
		elif GOBKIT_PATHS.has(species):
			for expected in ["idle", "walk"]:
				var found_direct := false
				for candidate in names:
					if str(candidate).to_lower() == expected or str(candidate).to_lower().ends_with("/" + expected):
						found_direct = true
				if not _require(found_direct, "%s: отсутствует %s" % [species, expected]):
					return
		else:
			var found_baked := false
			for candidate in names:
				var animation := player.get_animation(candidate)
				if animation != null and animation.length >= 4.9:
					found_baked = true
			if not _require(found_baked, "Нет idle/walk: " + species):
				return
		animal.queue_free()
	var source := load("res://scripts/fauna.gd")
	if not _require(source != null, "Ошибка компиляции фауны"):
		return
	print("FAUNA_SMOKE_OK: 9 rigged and animated GLB")
	quit(0)

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

