extends SceneTree
## Godot 4.4: godot --headless --path godot/butterfly-valley -s res://tests/builder_ai_smoke.gd
## Проверяем правила экономики/сохранения без запуска тяжёлой 3D-сцены.

func _initialize() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	var source := load("res://scripts/builder_ai.gd")
	assert(source != null)
	var site = load("res://scripts/construction.gd").new()
	root.add_child(site)
	var forest = load("res://scripts/world.gd").new()
	root.add_child(forest)
	var hero := Node3D.new()
	root.add_child(hero)
	var builder = source.new()
	builder.setup(forest, site, hero, {"stage": 0}, Callable())
	assert(builder.stage() == 0)
	assert(builder.data["trees"].size() == 3)
	assert(builder.data["stones"].size() == 2)
	assert(not forest.can_walk(22.0, -27.0, false))
	forest.set_builder_trees([{"cut": true}, {"cut": false}, {"cut": false}])
	assert(forest.can_walk(22.0, -27.0, false))
	forest.set_builder_trees(builder.data["trees"])

	# Первому этапу нужен камень: Бруно отправляется за ним.
	builder._choose_next()
	assert(builder.data["target"]["then"] == "gather")
	builder.data["stock"]["stone"] = 1
	builder._reset_job()
	builder._choose_next()
	assert(builder.data["target"]["then"] == "build")
	builder._begin_action()
	assert(builder.data["phase"] == "build")
	assert(int(builder.data["paidStage"]) == 1)
	assert(int(builder.data["stock"]["stone"]) == 0)
	assert(int(builder.data["spent"]["stone"]) == 1)
	builder._complete_action()
	assert(builder.stage() == 1)
	assert(int(builder.data["paidStage"]) == 0)
	assert(site.current_stage == 1)

	# Если Паки достроил этап, за который Бруно уже заплатил,
	# собственный склад Бруно должен получить материалы обратно.
	builder.data["stock"]["wood"] = 1
	builder._choose_next()
	assert(builder.data["target"]["then"] == "build")
	builder._begin_action()
	assert(int(builder.data["paidStage"]) == 2)
	assert(int(builder.data["stock"]["wood"]) == 0)
	builder.player_completed_stage(2)
	assert(builder.stage() == 2)
	assert(int(builder.data["stock"]["wood"]) == 1)
	assert(int(builder.data["paidStage"]) == 0)

	assert(builder.donate("wood"))
	assert(int(builder.data["stock"]["wood"]) == 2)
	builder.command("follow")
	assert(builder.data["mode"] == "follow")
	var stored: Dictionary = builder.snapshot()
	var restored = source.new()
	restored.setup(forest, site, hero, stored, Callable())
	assert(restored.stage() == 2)
	assert(restored.data["mode"] == "follow")
	assert(int(restored.data["stock"]["wood"]) == 2)
	assert(restored.data["log"].size() > 0)
	assert(not restored.donate("iron"))
	assert(int(restored.data["stock"]["wood"]) == 2)

	# Навигация ограничена небольшой сеткой: дальний маршрут
	# разбивается на участки, без расчёта огромного A* за кадр.
	var route: Array[Vector2] = builder._find_route(Vector2(24.0, -28.0), Vector2(26.0, -28.0))
	assert(not route.is_empty())
	builder.free()
	restored.free()
	print("BUILDER_AI_SMOKE_OK: jobs, stage costs, refund, donation, save, navigation")
	quit(0)

