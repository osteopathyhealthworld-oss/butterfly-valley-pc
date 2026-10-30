@tool
extends "res://scenery/TerrainPatch3D.gd"

## Meandering, walkable riverbed; the base terrain script also uses this for collision.
const BANK_OUTER: float = 17.0
const RIVER_HALF_WIDTH: float = 4.4

static func center_at(z: float) -> float:
	return 6.5 * sin(z * 0.037) + 2.7 * sin(z * 0.091 + 0.7)

static func water_height_at(z: float) -> float:
	return -2.55 - z * 0.0025

func _sample_height(local_x: float, local_z: float) -> float:
	var original: float = super._sample_height(local_x, local_z)
	return carve_height(local_x, local_z, original)


static func carve_height(local_x: float, local_z: float, original: float) -> float:
	var distance: float = absf(local_x - center_at(local_z))
	if distance >= BANK_OUTER:
		return original
	var level: float = water_height_at(local_z)
	if distance <= RIVER_HALF_WIDTH:
		var bed_ratio: float = distance / RIVER_HALF_WIDTH
		return level - 1.15 + 1.22 * bed_ratio * bed_ratio
	var t: float = smoothstep(RIVER_HALF_WIDTH, BANK_OUTER, distance)
	return lerpf(level + 0.07, original, t) + 1.15 * sin(t * PI) * (1.0 - 0.25 * t)


func _build_grass_transforms(payload: Dictionary) -> Dictionary:
	# The upstream grass worker samples the ORIGINAL noise independently of the
	# terrain mesh. Apply the same carving to every generated grass transform;
	# otherwise vegetation floats or sinks along the raised riverbanks.
	# Uses payload values only: safe for the background grass-generation thread.
	var built: Dictionary = super._build_grass_transforms(payload)
	var transforms: Array[Transform3D] = built["transforms"]
	var offset: float = payload["height_offset"]
	for i in range(transforms.size()):
		var pose: Transform3D = transforms[i]
		var base_y: float = pose.origin.y - offset
		pose.origin.y = carve_height(pose.origin.x, pose.origin.z, base_y) + offset
		transforms[i] = pose
	built["transforms"] = transforms
	return built
