extends SceneTree

const SOURCES := [
	"res://assets/paki-hero.glb",
	"res://assets/bruno-builder.glb",
	"res://assets/mouse-cute.glb",
	"res://library/prepared/gobkit/forest/Tarsier.glb",
	"res://library/prepared/gobkit/farm/Sheep.glb",
	"res://library/prepared/gobkit/farm/Pig.glb",
	"res://library/prepared/gobkit/bird/Rooster.glb",
]

func _initialize() -> void:
	call_deferred("_inspect")

func _inspect() -> void:
	for path in SOURCES:
		if not ResourceLoader.exists(path):
			print("ACTOR_INVENTORY_MISSING ", path)
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			print("ACTOR_INVENTORY_INVALID ", path)
			continue
		var obj := scene.instantiate()
		root.add_child(obj)
		var stats := {"skins": 0, "bones": 0, "clips": []}
		_walk(obj, stats)
		print("ACTOR_INVENTORY ", path, " bones=", stats["bones"], " skins=", stats["skins"], " heads=", stats.get("heads", []), " clips=", stats["clips"])
		obj.queue_free()
	quit(0)

func _walk(node: Node, stats: Dictionary) -> void:
	if node is Skeleton3D:
		var skeleton := node as Skeleton3D
		stats["skins"] += 1
		stats["bones"] += skeleton.get_bone_count()
		var head_bones: Array[String] = []
		for index in range(skeleton.get_bone_count()):
			var bone: String = str(skeleton.get_bone_name(index))
			if bone.to_lower().contains("head") or bone.to_lower().contains("face"):
				head_bones.append("%s=%s" % [bone, skeleton.get_bone_global_rest(index).origin])
		stats["heads"] = head_bones
	if node is AnimationPlayer:
		for clip in node.get_animation_list():
			stats["clips"].append(str(clip))
	for child in node.get_children():
		_walk(child, stats)

