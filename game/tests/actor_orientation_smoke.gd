extends SceneTree

const ACTOR_ANIMATION = preload("res://scripts/actor_animation.gd")
## Godot 4.4.1: Godot --headless --path godot/butterfly-valley -s res://tests/actor_orientation_smoke.gd
## Запускать ПОСЛЕ prepare-assets: тест проверяет реальные GLB, скелеты,
## анимации, масштаб и математическое соответствие курса движения взгляду.

const ACTORS := [
	{"id": "Паки", "asset": "paki-hero", "height": 5.1, "front_z": -1.0, "visual_yaw": ACTOR_ANIMATION.PAKI_VISUAL_YAW, "clips": ["Paki_Walking", "Paki_Fast_Run"]},
	{"id": "Бруно", "asset": "bruno-builder", "height": 4.9, "front_z": 1.0, "visual_yaw": ACTOR_ANIMATION.BRUNO_VISUAL_YAW, "clips": ["Bruno_Idle", "Bruno_Walk", "Bruno_Woodcut", "Bruno_Plant"]}
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var errors: Array[String] = []
	for spec in ACTORS:
		var path := "res://assets/%s.glb" % spec["asset"]
		if not ResourceLoader.exists(path):
			errors.append("Нет исходной 3D-модели: " + path)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			errors.append("Не удалось импортировать GLB: " + path)
			continue
		var scene := packed.instantiate() as Node3D
		if scene == null:
			errors.append("Нет Node3D в GLB: " + path)
			continue
		root.add_child(scene)
		var minmax := {"min": INF, "max": -INF}
		_gather_bounds(scene, minmax)
		var raw_height := float(minmax["max"]) - float(minmax["min"])
		if raw_height <= 0.00001 or raw_height > 100000.0:
			errors.append("Неверная высота GLB: " + path)
		else:
			var factor := float(spec["height"]) / raw_height
			if not is_finite(factor) or factor <= 0.0:
				errors.append("Неверный коэффициент масштаба: " + path)
		var anim := _animation_player(scene)
		if anim == null:
			errors.append("Нет AnimationPlayer: " + path)
		else:
			ACTOR_ANIMATION.lock_horizontal_motion(anim, spec["id"] == "Паки")
			for clip in anim.get_animation_list():
				var animation := anim.get_animation(clip)
				for track in range(animation.get_track_count()):
					if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
						continue
					if not str(animation.track_get_path(track)).to_lower().contains("hips"):
						continue
					if animation.track_get_key_count(track) < 2:
						continue
					var start: Vector3 = animation.track_get_key_value(track, 0)
					for key in range(1, animation.track_get_key_count(track)):
						var sample: Vector3 = animation.track_get_key_value(track, key)
						var drift := Vector2(sample.x - start.x, sample.y - start.y).length() if spec["id"] == "Паки" else Vector2(sample.x - start.x, sample.z - start.z).length()
						if drift > 0.0001:
							errors.append("%s: горизонтальный root motion остался в %s" % [spec["id"], clip])
							break
			for required in spec["clips"]:
				var matched := false
				for clip in anim.get_animation_list():
					var name := str(clip)
					if name == required or name.ends_with("/" + required):
						matched = true
						break
				if not matched:
					errors.append("%s: отсутствует клип %s" % [spec["id"], required])
		# Контроллер поворачивается по вектору движения, визуал каждой модели
		# компенсирует СВОЮ исходную ось. Четыре направления должны совпасть.
		for step in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
			var yaw := atan2(-step.x, -step.y)
			var front := Basis(Vector3.UP, yaw) * Basis(Vector3.UP, float(spec["visual_yaw"])) * Vector3(0, 0, float(spec["front_z"]))
			if Vector2(front.x, front.z).dot(step) < 0.999:
				errors.append("%s: модель смотрит против движения %s" % [spec["id"], step])
		scene.queue_free()
	if errors.is_empty():
		print("ACTOR_ORIENTATION_SMOKE_OK: GLB, clips, no double root motion, dimensions, 4 directions, Paki and Bruno")
		quit(0)
	else:
		for failure in errors:
			push_error(failure)
		quit(1)

func _gather_bounds(node: Node, bounds: Dictionary) -> void:
	if node is MeshInstance3D:
		var m := node as MeshInstance3D
		var box := m.get_aabb()
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					var corner := m.global_transform * Vector3(x, y, z)
					bounds["min"] = minf(float(bounds["min"]), corner.y)
					bounds["max"] = maxf(float(bounds["max"]), corner.y)
	for child in node.get_children():
		_gather_bounds(child, bounds)

func _animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var anim := _animation_player(child)
		if anim != null:
			return anim
	return null


