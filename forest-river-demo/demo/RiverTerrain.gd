@tool
extends "res://scenery/TerrainPatch3D.gd"
## One height function drives the visible mesh, collision, trees and grass.
## Upland stays above water; the channel is carved below it.
const BANK_OUTER: float = 21.0
const RIVER_HALF_WIDTH: float = 5.2

static func center_at(z: float) -> float:
	return 11.0 * sin(z * 0.030) + 3.5 * sin(z * 0.085 + 0.65)

static func water_height_at(z: float) -> float:
	return -6.4 - z * 0.002

static func upland_height(x: float, z: float, original_noise_height: float) -> float:
	var hills: float = 8.0 + original_noise_height * 0.38
	hills += 2.2 * sin(x * 0.023) + 3.0 * cos(z * 0.031 + x * 0.008)
	return maxf(hills, water_height_at(z) + 2.0)

func _sample_height(local_x: float, local_z: float) -> float:
	var original: float = super._sample_height(local_x, local_z)
	return carve_height(local_x, local_z, original)

static func carve_height(x: float, z: float, original_noise_height: float) -> float:
	var distance: float = absf(x - center_at(z))
	var dry_land: float = upland_height(x, z, original_noise_height)
	if distance >= BANK_OUTER:
		return dry_land
	var level: float = water_height_at(z)
	if distance <= RIVER_HALF_WIDTH:
		var r: float = distance / RIVER_HALF_WIDTH
		return level - 1.40 + 1.96 * r * r
	var t: float = smoothstep(RIVER_HALF_WIDTH, BANK_OUTER, distance)
	return lerpf(level + 0.56, dry_land, t) + 0.25 * sin(t * PI)


func _generate() -> void:
	# Preserve the upstream terrain mesh and collision generation, then add
	# stable shoreline colours for Godot's native StandardMaterial3D.
	super._generate()
	var terrain_mesh := get_node_or_null("__terrain_mesh") as MeshInstance3D
	if terrain_mesh == null or terrain_mesh.mesh == null:
		return
	var arrays: Array = terrain_mesh.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	for i in range(vertices.size()):
		var vertex: Vector3 = vertices[i]
		var distance: float = absf(vertex.x - center_at(vertex.z))
		var bank: float = 1.0 - smoothstep(6.0, 16.0, distance)
		colors[i] = Color(0.58, 0.65, 0.51).lerp(Color(0.86, 0.76, 0.59), bank)
	arrays[Mesh.ARRAY_COLOR] = colors
	var colored_mesh := ArrayMesh.new()
	colored_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	colored_mesh.regen_normal_maps()
	terrain_mesh.mesh = colored_mesh

func _build_grass_transforms(payload: Dictionary) -> Dictionary:
	# The upstream grass worker samples base noise, not the carved terrain.
	# Apply the same height function as visible geometry and collision.
	var built: Dictionary = super._build_grass_transforms(payload)
	var transforms: Array[Transform3D] = built["transforms"]
	var offset: float = payload["height_offset"]
	for i in range(transforms.size()):
		var pose: Transform3D = transforms[i]
		var original_noise: float = pose.origin.y - offset
		pose.origin.y = carve_height(pose.origin.x, pose.origin.z, original_noise) + offset
		transforms[i] = pose
	built["transforms"] = transforms
	return built
