extends SceneTree
# Быстрая проверка при каждом экспорте. Полный тест: tests/world_smoke.gd.

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var source := load("res://scripts/world.gd")
	if not _require(source != null, "Не найден скрипт генератора"):
		return
	var world = source.new()
	root.add_child(world)
	if not _require(world.river_half_width(0.0) > 3.0, "Неверная ширина реки"):
		return
	if not _require(world._hash01(5, 7, 11) == world._hash01(5, 7, 11), "Сид мира неустойчив"):
		return
	if not _require(world._hash01(5, 7, 11) != world._hash01(6, 7, 11), "Мировая сетка не меняется"):
		return
	if not _require(not world.can_walk(5.0, 9.0, false), "Река проходима до постройки моста"):
		return
	world.update_stream(Vector3(-4.2, 0.0, -18.3))
	if not _require(world.get("_loaded").size() == 1 and not world.get("_active_build").is_empty(), "Первый чанк не запущен поэтапно"):
		return
	var first_biome: String = world.biome_at(12.0, 42.0)
	var first_height: float = world.ground_height(12.0, 42.0)
	world.set_quality(true)
	if not _require(world.get("_loaded").is_empty(), "При смене режима чанки не освобождаются"):
		return
	world.update_stream(Vector3(-4.2, 0.0, -18.3))
	if not _require(world.get("_loaded").size() == 1 and world.high_quality, "Подробный режим не создаёт чанки"):
		return
	if not _require(first_biome == world.biome_at(12.0, 42.0) and is_equal_approx(first_height, world.ground_height(12.0, 42.0)), "Биом меняется от настроек качества"):
		return
	print("WORLD_QUICK_SMOKE_OK: deterministic biomes, river, streaming and quality")
	quit(0)

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

