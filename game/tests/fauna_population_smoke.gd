extends SceneTree
## Проверяет реальное появление, анимацию и обновление движений лагерной фауны.

func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var world = load("res://scripts/world.gd").new()
	root.add_child(world)
	var hero := Node3D.new()
	hero.position = Vector3(18.0, 0.0, 46.0)
	root.add_child(hero)
	var fauna = load("res://scripts/fauna.gd").new()
	fauna.setup(world, hero)
	root.add_child(fauna)
	fauna._refresh()
	if not fauna._animals.has("camp-rooster") or not fauna._animals.has("camp-corgi"):
		push_error("Нет постоянных обитателей лагеря")
		quit(1)
		return
	var rooster: Dictionary = fauna._animals["camp-rooster"]
	if rooster["animation"] == null or not rooster["clips"].has("idle") or not rooster["clips"].has("walk"):
		push_error("Петух не имеет скелетных анимаций idle/walk")
		quit(1)
		return
	fauna._play(rooster, "walk")
	if rooster["active_clip"] == &"":
		push_error("Не запущена анимация ходьбы")
		quit(1)
		return
	fauna._advance_animation(rooster, 0.25)
	if float(rooster["motion_time"]) < 0.20:
		push_error("Анимация не продвигается")
		quit(1)
		return
	print("FAUNA_POPULATION_OK: rooster/corgi camp, real skeleton, animated walk")
	quit(0)

