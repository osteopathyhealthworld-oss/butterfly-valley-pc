extends SceneTree
# Небольшая проверка целостности мира без графического окна.
# Команда: godot --headless --path . -s res://tests/world_smoke.gd

func _initialize() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	var source = load("res://scripts/world.gd")
	assert(source != null, "Не найден генератор мира")
	var world = source.new()
	root.add_child(world)
	assert(world.river_half_width(0.0) > 3.0)
	assert(world.river_center(0.0) > 7.0)
	assert(world.path_distance(5.0, 4.0) < 2.0)
	assert(world.biome_at(0.0, world.river_center(0.0) + 6.0) == "riverbank")
	var climate: Dictionary = world.climate_at(38.0, 84.0)
	for value in climate.values():
		assert(float(value) >= 0.0 and float(value) <= 1.0)
	assert(world._hash01(7, 13, 2) == world._hash01(7, 13, 2))
	assert(world._hash01(7, 13, 2) != world._hash01(8, 13, 2))
	assert(not world.can_walk(5.0, 9.0, false), "Река до ремонта моста должна быть закрыта")
	assert(world.can_walk(5.0, 9.0, true), "По восстановленному мосту должно быть можно пройти")
	assert(is_equal_approx(world.ground_height(23.0, 60.0), world.ground_height(23.0, 60.0)))
	for i in range(25 * 6):
		world.update_stream(Vector3(-4.2, 0.0, -18.3))
	assert(world.get("_loaded").size() == 25, "Экономный режим должен держать 25 чанков")
	var saved_glades: Dictionary = world.get("_glades").duplicate(true)
	if not saved_glades.is_empty():
		var first_site: Dictionary = saved_glades.values()[0]
		var first_pos: Vector2 = first_site["pos"]
		assert(world.nearby_secret(first_pos.x, first_pos.y)["id"] == first_site["id"])
	var cell := Vector2i(0, 0)
	var saved_colliders: Array = world.get("_colliders").get(cell, []).duplicate(true)
	world.set_quality(true)
	assert(world.high_quality)
	assert(world.get("_loaded").is_empty())
	for i in range(49 * 6):
		world.update_stream(Vector3(-4.2, 0.0, -18.3))
	assert(world.get("_loaded").size() == 49, "Подробный режим должен держать 49 чанков")
	assert(world.get("_colliders").get(cell, []).size() >= saved_colliders.size())
	world.set_quality(false)
	for i in range(25 * 6):
		world.update_stream(Vector3(-4.2, 0.0, -18.3))
	assert(world.get("_loaded").size() == 25)
	assert(world.get("_glades") == saved_glades, "Секретные поляны должны повторяться после возвращения")
	assert(world.get("_colliders").get(cell, []) == saved_colliders, "Деревья не должны менять положение")
	print("WORLD_SMOKE_OK: climate, river, paths, deterministic biome, secrets and quality")
	quit(0)

