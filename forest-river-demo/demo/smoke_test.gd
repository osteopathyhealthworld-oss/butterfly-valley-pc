extends SceneTree
const RiverTerrainScript = preload("res://demo/RiverTerrain.gd")

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://levels/forest_river_demo.tscn") as PackedScene
	if packed == null:
		push_error("Demo scene could not be loaded")
		quit(1)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	await process_frame
	await process_frame
	var river := instance.get_node_or_null("AnimatedRiver") as MeshInstance3D
	var stones := instance.get_node_or_null("RiverbankStones") as MultiMeshInstance3D
	if river == null or river.mesh == null:
		push_error("River mesh was not generated")
		quit(2)
		return
	if stones == null or stones.multimesh == null or stones.multimesh.instance_count < 100:
		push_error("Riverbank decoration is missing")
		quit(3)
		return
	var terrain := instance.get_node_or_null("Terrain")
	if terrain == null or terrain.get_script() == null:
		push_error("River terrain is missing")
		quit(4)
		return
	var center: float = terrain.call("_sample_height", 0.0, 0.0)
	var outside: float = terrain.call("_sample_height", 70.0, 0.0)
	if center >= RiverTerrainScript.water_height_at(0.0):
		push_error("Riverbed should lie below water surface")
		quit(5)
		return
	for prop_name in ["OldHouse", "OldWell"]:
		var prop: Node3D = instance.get_node_or_null(prop_name)
		if prop == null or absf(prop.position.x - RiverTerrainScript.center_at(prop.position.z)) < RiverTerrainScript.BANK_OUTER:
			push_error("The cottage or well intersects the river: " + prop_name)
			quit(6)
			return
	var trees := instance.get_node("Trees")
	var tree_mask: Image = trees.mask_texture.get_image()
	for location in [Vector2(27.0, -17.0), Vector2(25.0, -4.0), Vector2(RiverTerrainScript.center_at(0.0), 0.0)]:
		var uv: Vector2 = Vector2(location.x / 100.0 + 0.5, location.y / 100.0 + 0.5)
		var px := clampi(int(uv.x * tree_mask.get_width()), 0, tree_mask.get_width() - 1)
		var py := clampi(int(uv.y * tree_mask.get_height()), 0, tree_mask.get_height() - 1)
		if tree_mask.get_pixel(px, py).r < 0.98:
			push_error("Trees were not excluded from river or cottage clearing")
			quit(10)
			return
	# Test the real grass worker function, not just the terrain mesh. The
	# original upstream grass sampler ignored riverbank carving entirely.
	var grass_payload := {
		"request_id": 999,
		"camera_local": Vector3(12.0, 0.0, 0.0),
		"size": Vector2(200.0, 200.0),
		"spacing": 0.7,
		"radius": 3.8,
		"max_instances": 500,
		"height_offset": -0.17,
		"scale_min": 0.56,
		"scale_max": 0.88,
		"height_scale": 18.93,
		"noise": terrain.noise.duplicate(),
		"grass_mask_enabled": false,
		"grass_mask_image": null,
		"grass_mask_area_size": Vector2(100, 100),
		"grass_mask_channel": 1,
		"grass_mask_threshold": 0.03,
		"grass_mask_inverse": true,
		"grass_mask_affects_density": false,
		"grass_mask_affects_scale": true,
		"grass_mask_min_scale_factor": 0.2,
	}
	var grass_thread := Thread.new()
	if grass_thread.start(Callable(terrain, "_build_grass_transforms").bind(grass_payload)) != OK:
		push_error("Could not start grass generation thread")
		quit(9)
		return
	while grass_thread.is_alive():
		await process_frame
	var grass_result: Dictionary = grass_thread.wait_to_finish()
	var grass_transforms: Array[Transform3D] = grass_result["transforms"]
	if grass_transforms.is_empty():
		push_error("Grass worker generated no test samples")
		quit(7)
		return
	for grass_transform in grass_transforms:
		var point: Vector3 = grass_transform.origin
		var expected: float = terrain.call("_sample_height", point.x, point.z) - 0.17
		if absf(point.y - expected) > 0.001:
			push_error("Grass sits above or below the riverbank")
			quit(8)
			return
	print("FOREST_RIVER_SMOKE_OK river_vertices=", river.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), " rocks=", stones.multimesh.instance_count, " center_height=", center, " outer_height=", outside)
	quit(0)
