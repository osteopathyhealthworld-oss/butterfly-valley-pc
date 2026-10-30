extends SceneTree
## Диагностика скачков времени создания чанков при продвижении по большому миру.
## Только измерения CPU: браузерный FPS и GPU проверяются отдельно.

const CHUNK_SIZE := 28.0
const PROBE_CELLS := [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
	Vector2i(2, 1), Vector2i(2, 2), Vector2i(3, 2),
	Vector2i(12, 12), Vector2i(13, 12)
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source = load("res://scripts/world.gd")
	if source == null:
		push_error("Нет генератора мира")
		quit(1)
		return
	var world = source.new()
	root.add_child(world)
	for quality in [false, true]:
		world.set_quality(quality)
		var total_microseconds: int = 0
		var calls: int = 0
		var max_microseconds: int = 0
		var spike_count: int = 0
		var max_loaded: int = 0
		for cell in PROBE_CELLS:
			var location := Vector3((float(cell.x) + 0.5) * CHUNK_SIZE, 0.0, (float(cell.y) + 0.5) * CHUNK_SIZE)
			var radius := 3 if quality else 2
			var iterations: int = (radius * 2 + 1) * (radius * 2 + 1) * 6 + 1
			for i in range(iterations):
				var started: int = Time.get_ticks_usec()
				world.update_stream(location)
				var elapsed: int = Time.get_ticks_usec() - started
				total_microseconds += elapsed
				max_microseconds = maxi(max_microseconds, elapsed)
				if elapsed > 16000:
					spike_count += 1
				calls += 1
				max_loaded = maxi(max_loaded, world.get("_loaded").size())
			# Освобождаем предыдущие участки между переходами, как в игровом цикле.
			await process_frame
		print("STREAM_PROFILE mode=%s mean_ms=%.2f worst_ms=%.2f over_16ms=%d/%d max_chunks=%d" % [
			"high" if quality else "low",
			float(total_microseconds) / float(calls) / 1000.0,
			float(max_microseconds) / 1000.0,
			spike_count, calls, max_loaded
		])
	world.queue_free()
	print("STREAM_PROFILE_OK: world boundaries and faraway streaming exercised")
	quit(0)

