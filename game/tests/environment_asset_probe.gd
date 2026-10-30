extends SceneTree

const NAMES := ["tree-oak", "tree-detailed", "tree-fat", "tree-pinetalla", "grass", "flower-purplea", "plant-bushlarge", "rock-largea", "lily-small"]

func _initialize() -> void:
	call_deferred("_inspect")

func _inspect() -> void:
	for id in NAMES:
		var packed := load("res://assets/%s.glb" % id) as PackedScene
		if packed == null:
			print("ENV_ASSET_MISSING ", id)
			continue
		var obj := packed.instantiate()
		root.add_child(obj)
		var meshes: Array[String] = []
		_collect(obj, meshes)
		print("ENV_ASSET ", id, " meshes=", meshes)
		obj.queue_free()
	quit(0)

func _collect(node: Node, out: Array[String]) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		out.append("%s surfaces=%d materials=%s" % [part.name, part.mesh.get_surface_count() if part.mesh else 0, str(part.mesh.surface_get_material(0)) if part.mesh != null and part.mesh.get_surface_count() > 0 else "none"])
	for child in node.get_children():
		_collect(child, out)

