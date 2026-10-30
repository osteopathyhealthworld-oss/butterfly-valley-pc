extends SceneTree
## Regression check: actual PBR ground textures, UV2 biome blend and CC0 tree atlas.
## Must run after the Godot editor imports the project's .glb files.

const WORLD = preload("res://scripts/world_pbr.gd")

func _initialize() -> void:
	call_deferred("_verify")


func _fail(message: String) -> void:
	push_error("TERRAIN_CANOPY: " + message)
	quit(1)


func _verify() -> void:
	var world = WORLD.new()
	root.add_child(world)
	world.set_quality(true)
	if not world.high_quality:
		_fail("Detailed vegetation mode did not activate")
		return
	for id in ["q-birch-1", "q-common-tree", "q-pine-1", "q-oak-wide", "q-twisted-1"]:
		if not world._atlas_batched.has(id):
			_fail("Detailed CC0 tree mesh is unavailable: " + id)
			return
	var holder := Node3D.new()
	root.add_child(holder)
	world._make_terrain(holder, Vector2i(0, 0))
	var terrain := holder.get_node_or_null("Земля") as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		_fail("Terrain chunk was not generated")
		return
	var surfaces := terrain.mesh.surface_get_arrays(0)
	var weights: PackedVector2Array = surfaces[Mesh.ARRAY_TEX_UV2]
	if weights.is_empty():
		_fail("Biome weights were not encoded in terrain UV2")
		return
	var shader_material := terrain.mesh.surface_get_material(0) as ShaderMaterial
	if shader_material == null:
		_fail("Detailed ground shader is missing")
		return
	for name in ["grass_color", "meadow_color", "forest_color", "soil_color", "rock_color"]:
		if not (shader_material.get_shader_parameter(name) is Texture2D):
			_fail("Ground texture is absent: " + name)
			return
	print("TERRAIN_CANOPY_SMOKE_PASS: 5 textures, biome UV2, detailed Quaternius tree atlas")
	quit(0)
