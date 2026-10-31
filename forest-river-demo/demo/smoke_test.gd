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
	var camera := instance.get_node_or_null("FlyCamera") as Camera3D
	if camera == null or not camera.current or instance.get_node_or_null("UP_FPSController_Prefab") != null:
		push_error("Demo must use only the free-fly camera, not the gravity-based player")
		quit(13)
		return
	var start: Vector3 = camera.global_position
	var land: float = terrain.call("_sample_height", start.x, start.z)
	if start.y < land + 5.0 or start.y < 25.0:
		push_error("Free-fly camera spawned too low or under terrain")
		quit(14)
		return
	await create_timer(0.25).timeout
	if absf(camera.global_position.y - start.y) > 0.01:
		push_error("Camera drifts vertically without movement input")
		quit(15)
		return
	camera.call("_move_from_axes", 0.0, 0.0, 1.0, 0.25, false)
	if camera.global_position.y <= start.y + 2.0:
		push_error("Upward fly control does not increase altitude")
		quit(16)
		return
	camera.call("_move_from_axes", 0.0, 0.0, -1.0, 0.25, false)
	if absf(camera.global_position.y - start.y) > 0.01:
		push_error("Downward fly control does not decrease altitude")
		quit(17)
		return
	camera.call("_move_from_axes", 0.0, 1.0, 0.0, 0.25, false)
	if camera.global_position.distance_to(start) < 2.0:
		push_error("Forward camera movement is inactive")
		quit(18)
		return
	camera.call("reset_view")
	# The old smoke test checked terrain sampling but never checked whether
	# an actual visible ground mesh and opaque material existed.
	var ground_mesh := terrain.get_node_or_null("__terrain_mesh") as MeshInstance3D
	if ground_mesh == null or ground_mesh.mesh == null or ground_mesh.mesh.get_surface_count() == 0:
		push_error("No visible terrain mesh exists")
		quit(19)
		return
	if not ground_mesh.visible:
		push_error("Terrain mesh is invisible")
		quit(20)
		return
	var ground_material := ground_mesh.material_override as ShaderMaterial
	if ground_material == null or ground_material.shader == null:
		push_error("Stable opaque terrain material is missing")
		quit(21)
		return
	var diagnostics := instance.get_node_or_null("RiverDemoHUD/Diagnostics") as Label
	if diagnostics == null or not diagnostics.text.contains("FR-2026-10-31-R3"):
		push_error("Demo lacks visible build identification; old executable cannot be distinguished")
		quit(30)
		return
	instance.call("_toggle_diagnostic_ground")
	if ground_mesh.material_override == ground_material:
		push_error("Diagnostic terrain material does not replace the textured ground")
		quit(31)
		return
	instance.call("_toggle_diagnostic_ground")
	if ground_mesh.material_override != ground_material:
		push_error("Diagnostic terrain material cannot be restored")
		quit(32)
		return
	var vertex_data: PackedVector3Array = ground_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertex_data.size() < 10000:
		push_error("Terrain does not contain the expected 3D topology")
		quit(22)
		return
	var low := INF
	var high := -INF
	for point in vertex_data:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	if high - low < 6.0:
		push_error("Terrain relief is nearly flat")
		quit(23)
		return
	for z in [-72.0, -36.0, 0.0, 36.0, 72.0]:
		var cx: float = RiverTerrainScript.center_at(z)
		var level: float = RiverTerrainScript.water_height_at(z)
		var bed: float = terrain.call("_sample_height", cx, z)
		var dry_bank: float = terrain.call("_sample_height", cx + RiverTerrainScript.BANK_OUTER + 3.0, z)
		if bed > level - 0.4 or dry_bank < level + 1.5:
			push_error("River bed/banks violate water-level geometry")
			quit(24)
			return
	var world := instance.get_node("WorldEnvironment") as WorldEnvironment
	if world.camera_attributes != null or world.compositor != null:
		push_error("Adaptive exposure or temporal compositor is still active")
		quit(25)
		return
	if world.environment.volumetric_fog_enabled or world.environment.glow_enabled or world.environment.sdfgi_enabled:
		push_error("High-cost unstable rendering effects are still enabled")
		quit(26)
		return
	var water := river.material_override as ShaderMaterial
	if water == null or water.shader == null or "ALPHA =" in water.shader.code or "depth_draw_never" in water.shader.code.split("//")[0]:
		push_error("River must be opaque and write depth")
		quit(27)
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
	if trees.density_lod_enabled:
		push_error("Trees must not change density with the camera")
		quit(28)
		return
	for entry in trees.entries:
		if entry.billboard_scene != null or entry.billboard_mesh != null:
			push_error("Tree billboard switching has not been disabled")
			quit(29)
			return
	var tree_mesh_instances := _count_multimesh_instances(trees)
	if tree_mesh_instances < 100:
		push_error("Forest vegetation failed to populate: only %d mesh instances" % tree_mesh_instances)
		quit(11)
		return
	var tree_mask: Image = trees.mask_texture.get_image()
	for location in [Vector2(27.0, -17.0), Vector2(25.0, -4.0), Vector2(RiverTerrainScript.center_at(0.0), 0.0)]:
		var uv: Vector2 = Vector2(location.x / trees.area_size.x + 0.5, location.y / trees.area_size.y + 0.5)
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
	var visible_grass := 0
	for attempt in range(120):
		var grass_node := terrain.get_node_or_null("__terrain_grass") as MultiMeshInstance3D
		if grass_node != null and grass_node.multimesh != null:
			visible_grass = grass_node.multimesh.instance_count
			if visible_grass > 0:
				break
		await process_frame
	if visible_grass == 0:
		push_error("No runtime grass mesh was generated near the player")
		quit(12)
		return
	print("FOREST_RIVER_SMOKE_OK river_vertices=", river.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), " rocks=", stones.multimesh.instance_count, " forest_meshes=", tree_mesh_instances, " grass_blades=", visible_grass, " center_height=", center, " outer_height=", outside)
	quit(0)


func _count_multimesh_instances(node: Node) -> int:
	var count := 0
	if node is MultiMeshInstance3D:
		var mesh_node: MultiMeshInstance3D = node
		if mesh_node.multimesh != null:
			count += mesh_node.multimesh.instance_count
	for child in node.get_children(true):
		count += _count_multimesh_instances(child)
	return count
