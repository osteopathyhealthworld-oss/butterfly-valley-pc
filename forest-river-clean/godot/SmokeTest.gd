extends SceneTree
## Tests the actual self-contained scene and rejects regressions to old systems.


func _initialize() -> void:
	_run.call_deferred()


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _run() -> void:
	var source := load("res://main.tscn") as PackedScene
	if source == null:
		_fail("Main scene is missing")
		return
	var scene := source.instantiate()
	root.add_child(scene)
	await process_frame
	var ground := scene.get_node_or_null("VisibleTexturedTerrain") as MeshInstance3D
	var water := scene.get_node_or_null("WindingRiver") as MeshInstance3D
	var forest := scene.get_node_or_null("StaticForest") as Node3D
	var grass := scene.get_node_or_null("OneTimeStaticGrass") as MultiMeshInstance3D
	var camera := scene.get_node_or_null("FreeFlyCamera") as Camera3D
	if ground == null or ground.mesh == null or water == null or water.mesh == null:
		_fail("Visible terrain or river is missing")
		return
	var ground_material := ground.material_override as StandardMaterial3D
	if ground_material == null or ground_material.albedo_texture == null or not ground_material.vertex_color_use_as_albedo:
		_fail("Terrain needs an opaque textured standard material")
		return
	if forest == null or forest.get_child_count() < 250:
		_fail("Static tree assets did not instantiate")
		return
	if grass == null or grass.multimesh == null or grass.multimesh.instance_count != 4600:
		_fail("Static grass is missing")
		return
	if camera == null or not camera.current or camera.position.y < 25.0:
		_fail("Free flight camera spawn is invalid")
		return
	var before := camera.position
	await create_timer(0.12).timeout
	if camera.position.distance_to(before) > 0.001:
		_fail("Camera falls without keyboard input")
		return
	camera.call("move_by_axes", 0.0, 0.0, 1.0, 0.3, false)
	if camera.position.y < before.y + 3.0:
		_fail("Camera Space climb failed")
		return
	camera.call("move_by_axes", 0.0, 0.0, -1.0, 0.3, false)
	if absf(camera.position.y - before.y) > 0.01:
		_fail("Camera C descend failed")
		return
	var land_values: Array[float] = []
	for x in [-118.0, -45.0, 45.0, 118.0]:
		land_values.append(scene.call("height_at", x, 40.0))
	if land_values.max() - land_values.min() < 3.5:
		_fail("Terrain elevation is flat")
		return
	var centers: Array[float] = []
	for z in [-125.0, -40.0, 40.0, 125.0]:
		centers.append(scene.call("river_center", z))
	if centers.max() - centers.min() < 12.0:
		_fail("River does not meander")
		return
	for z in [-105.0, 0.0, 105.0]:
		var center: float = scene.call("river_center", z)
		var bed: float = scene.call("height_at", center, z)
		var bank: float = scene.call("height_at", center + 26.0, z)
		if bed >= 0.0 or bank <= 1.2:
			_fail("Riverbed or banks have broken elevation")
			return
	if scene.get_node_or_null("Trees") != null or scene.get_node_or_null("Terrain") != null:
		_fail("Imported legacy scene is still present")
		return
	print("PASS CLEAN-R0: ground texture, meanders, relief, stable camera, trees, static grass")
	quit(0)
