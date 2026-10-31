extends SceneTree
## A rendered-frame check, complementary to the headless geometry test.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 540)
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for frame in range(16):
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	if screenshot.is_empty():
		push_error("No rendered frame from OpenGL QA")
		quit(2)
		return
	var target := OS.get_environment("CLEAN_PREVIEW_OUTPUT")
	if not target.is_empty():
		if screenshot.save_png(target) != OK:
			push_error("Cannot save the clean demo screenshot")
			quit(3)
			return
	var forest := scene.get_node("StaticForest") as Node3D
	var water := scene.get_node("WindingRiver") as MeshInstance3D
	forest.visible = false
	water.visible = false
	var mesh := scene.get_node("VisibleTexturedTerrain") as MeshInstance3D
	scene.call("_unhandled_input", _pressed_f1())
	for frame in range(7):
		await process_frame
	await RenderingServer.frame_post_draw
	var diagnostic := root.get_texture().get_image()
	var red_pixels := 0
	for y in range(100, diagnostic.get_height(), 4):
		for x in range(0, diagnostic.get_width(), 4):
			var color := diagnostic.get_pixel(x, y)
			if color.r > 0.7 and color.r > color.g * 2.0:
				red_pixels += 1
	if red_pixels < 500:
		push_error("Ground geometry invisible: red diagnostic only in %d samples" % red_pixels)
		quit(4)
		return
	if mesh.material_override.resource_name == "GREEN_BROWN_GROUND_TEXTURE":
		push_error("Diagnostic did not switch the terrain material")
		quit(5)
		return
	print("RENDER PROBE PASS: visible terrain pixels=", red_pixels, ", screenshot=", target)
	quit(0)


func _pressed_f1() -> InputEventKey:
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_F1
	return key
