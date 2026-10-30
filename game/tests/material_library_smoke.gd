extends SceneTree
## Запуск после первого импорта ресурсов:
## godot --headless --path godot/butterfly-valley --script res://tests/material_library_smoke.gd

const LIBRARY = preload("res://scripts/asset_library.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures := PackedStringArray()
	var seen: Dictionary = {}
	var rigged := 0
	var imported := 0
	for entry in LIBRARY.all():
		var id: String = str(entry["id"])
		if seen.has(id):
			failures.append("Повторяющийся ID: " + id)
			continue
		seen[id] = true
		var path: String = str(entry["path"])
		if not ResourceLoader.exists(path):
			failures.append("Не импортирован файл: " + path)
			continue
		var model := LIBRARY.create(id)
		if model == null:
			failures.append("Нельзя создать экземпляр: " + id)
			continue
		root.add_child(model)
		LIBRARY.fit_visual(model, LIBRARY.desired_height(id))
		if bool(entry["rigged"]):
			rigged += 1
			var animation := LIBRARY.first_animation(model)
			if animation == null or animation.get_animation_list().is_empty():
				failures.append("Отсутствуют клипы скелетной модели: " + id)
			else:
				LIBRARY.play_idle(model)
		imported += 1
		model.free()
	if LIBRARY.all().size() != 45:
		failures.append("Ожидалось 45 моделей, найдено " + str(LIBRARY.all().size()))
	print("AssetLibrary: моделей %d; импортировано %d; скелетных %d; ошибок %d" % [
		LIBRARY.all().size(), imported, rigged, failures.size()
	])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)

