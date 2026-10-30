extends RefCounted
## Преобразует исходные locomotion-клипы в движения на месте.
## Контроллер перемещает Node3D героя; горизонтальный root motion в Hips
## не должен двигать скелет второй раз. Вертикальную работу таза сохраняем.
## Источники: paki.js (локальная X/Y — горизонталь, Z — вертикаль);
## bruno-builder.glb, стандартный Mixamo (X/Z — горизонталь, Y — вертикаль).

static func lock_horizontal_motion(player: AnimationPlayer, paki_axes: bool) -> int:
	if player == null:
		return 0
	var corrected := 0
	for clip in player.get_animation_list():
		var source := player.get_animation(clip)
		if source == null:
			continue
		for track in range(source.get_track_count()):
			if source.track_get_type(track) != Animation.TYPE_POSITION_3D:
				continue
			var path := str(source.track_get_path(track)).to_lower()
			if not path.contains("hips"):
				continue
			var count := source.track_get_key_count(track)
			if count < 2:
				continue
			var baseline: Vector3 = source.track_get_key_value(track, 0)
			var changed := false
			for key in range(count):
				var pos: Vector3 = source.track_get_key_value(track, key)
				if paki_axes:
					if not is_equal_approx(pos.x, baseline.x) or not is_equal_approx(pos.y, baseline.y):
						changed = true
					pos.x = baseline.x
					pos.y = baseline.y
				else:
					if not is_equal_approx(pos.x, baseline.x) or not is_equal_approx(pos.z, baseline.z):
						changed = true
					pos.x = baseline.x
					pos.z = baseline.z
				source.track_set_key_value(track, key, pos)
			if changed:
				corrected += 1
	return corrected


