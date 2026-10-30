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
	print("FOREST_RIVER_SMOKE_OK river_vertices=", river.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), " rocks=", stones.multimesh.instance_count, " center_height=", center, " outer_height=", outside)
	quit(0)
