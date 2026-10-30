extends RefCounted
## Correctly fits imported GLB models without discarding their root transforms.
## Skin vertices may have a tiny rest-pose AABB: use the animated skeleton's
## global rest positions for characters, mesh AABBs only for static props.

static func wrap_to_height(imported: Node3D, target_height: float) -> Node3D:
	var frame := Node3D.new()
	frame.name = "Масштаб модели"
	var bounds := {"min": Vector3(INF, INF, INF), "max": Vector3(-INF, -INF, -INF)}
	var skinned := _has_skeleton(imported)
	_collect(imported, Transform3D.IDENTITY, bounds, skinned)
	frame.add_child(imported)
	var low: Vector3 = bounds["min"]
	var high: Vector3 = bounds["max"]
	var span := high.y - low.y
	if span > 0.000001 and span < 100000.0:
		var factor := target_height / span
		# Scale the wrapper, never replace the GLB's original root scale.
		frame.scale = Vector3.ONE * factor
		frame.position = Vector3(
			-(low.x + high.x) * 0.5 * factor,
			-low.y * factor,
			-(low.z + high.z) * 0.5 * factor
		)
	else:
		push_warning("Не удалось измерить модель %s; оставлен исходный размер" % imported.name)
	return frame

static func _has_skeleton(node: Node) -> bool:
	if node is Skeleton3D and (node as Skeleton3D).get_bone_count() > 0:
		return true
	for child in node.get_children():
		if _has_skeleton(child):
			return true
	return false

static func _collect(node: Node, parent_transform: Transform3D, bounds: Dictionary, bones_only: bool) -> void:
	var t := parent_transform
	if node is Node3D:
		t = parent_transform * (node as Node3D).transform
	if bones_only and node is Skeleton3D:
		var skeleton := node as Skeleton3D
		for i in range(skeleton.get_bone_count()):
			_expand(bounds, t * skeleton.get_bone_global_rest(i).origin)
	elif not bones_only and node is MeshInstance3D:
		var box := (node as MeshInstance3D).get_aabb()
		for x in [box.position.x, box.end.x]:
			for y in [box.position.y, box.end.y]:
				for z in [box.position.z, box.end.z]:
					_expand(bounds, t * Vector3(x, y, z))
	for child in node.get_children():
		_collect(child, t, bounds, bones_only)

static func _expand(bounds: Dictionary, point: Vector3) -> void:
	bounds["min"] = (bounds["min"] as Vector3).min(point)
	bounds["max"] = (bounds["max"] as Vector3).max(point)

