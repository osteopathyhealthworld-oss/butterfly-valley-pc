extends Node3D
## Долина бабочек — лёгкая живая фауна.
## GLB уже имеют скелеты и анимации; при удалении чанков экземпляры освобождаются.

const Fitting = preload("res://scripts/model_fitting.gd")

const CELL := 36
const SCAN_RADIUS := 1
const MAX_LOW := 9
const MAX_HIGH := 15
const FOX := "Fox"
const BAT := "Bat"
const DUCK := "Duck"
const PLATYPUS := "Platypus"
const CORGI := "Corgi"
const TARSIER := "Tarsier"
const SHEEP := "Sheep"
const PIG := "Pig"
const ROOSTER := "Rooster"
const DIRECT_CLIPS := [TARSIER, SHEEP, PIG, ROOSTER]
const HEIGHTS := {
	"Fox": 1.8, "Bat": 0.75, "Duck": 0.9, "Platypus": 0.76, "Corgi": 1.1,
	"Tarsier": 1.55, "Sheep": 1.5, "Pig": 1.2, "Rooster": 0.9
}
const GOBKIT_PATHS := {
	"Tarsier": "forest/Tarsier", "Sheep": "farm/Sheep",
	"Pig": "farm/Pig", "Rooster": "bird/Rooster"
}
const BAKED_CLIPS := {
	"idle": Vector2(0.0, 29.0 / 24.0),
	"walk": Vector2(90.0 / 24.0, 119.0 / 24.0),
	"attack": Vector2(30.0 / 24.0, 59.0 / 24.0)
}

var world
var player: Node3D
var night := false
var detailed := false
var _animals: Dictionary = {}
var _templates: Dictionary = {}
var _refresh_timer := 0.0
var _elapsed := 0.0

func setup(world_ref, hero: Node3D) -> void:
	world = world_ref
	player = hero

func set_night(enabled: bool) -> void:
	if night == enabled:
		return
	night = enabled
	_refresh_timer = 100.0

func set_detailed(enabled: bool) -> void:
	detailed = enabled
	_refresh_timer = 100.0

func _ready() -> void:
	for kind in [FOX, BAT, DUCK, PLATYPUS, CORGI, TARSIER, SHEEP, PIG, ROOSTER]:
		var path: String = "res://library/prepared/gobkit/%s.glb" % GOBKIT_PATHS[kind] if GOBKIT_PATHS.has(kind) else "res://fauna_assets/%s.glb" % kind
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				_templates[kind] = scene
		else:
			push_warning("Нет модели животного: " + path)

func _process(delta: float) -> void:
	if player == null or world == null:
		return
	_elapsed += delta
	_refresh_timer += delta
	if _refresh_timer >= 1.1:
		_refresh_timer = 0.0
		_refresh()
	for id in _animals.keys():
		_step_animal(_animals[id], delta)

func _refresh() -> void:
	var wanted: Array[Dictionary] = []
	var pc := Vector2i(floori(player.position.x / CELL), floori(player.position.z / CELL))
	# Постоянного жителя лагеря добавляем первым, чтобы лимит качества его не вытеснил.
	if Vector2(player.position.x, player.position.z).distance_to(Vector2(18.0, 46.0)) < 55.0:
		wanted.append({"id": "camp-corgi", "kind": CORGI, "home": Vector2(18.0, 46.0), "side": 1.0})
		wanted.append({"id": "camp-rooster", "kind": ROOSTER, "home": Vector2(27.0, 43.0), "side": 1.0})
	# Лиса — в лесу, утки и утконосы — у воды, мышиный лагерь охраняет корги.
	for cz in range(pc.y - SCAN_RADIUS, pc.y + SCAN_RADIUS + 1):
		for cx in range(pc.x - SCAN_RADIUS, pc.x + SCAN_RADIUS + 1):
			var seed: float = world._hash01(cx, cz, 115)
			if seed > (0.80 if detailed else 0.62):
				continue
			var x: float = (float(cx) + 0.5) * CELL + (world._hash01(cx, cz, 116) - 0.5) * 16.0
			var z: float = (float(cz) + 0.5) * CELL + (world._hash01(cx, cz, 117) - 0.5) * 16.0
			var bank_distance: float = absf(z - world.river_center(x)) - world.river_half_width(x)
			var kind := FOX
			var side: float = -1.0 if world._hash01(cx, cz, 118) < 0.5 else 1.0
			if bank_distance < 15.0:
				kind = DUCK if world._hash01(cx, cz, 119) < 0.53 else PLATYPUS
				z = world.river_center(x) + side * (world.river_half_width(x) * 0.52 if kind == DUCK else world.river_half_width(x) + 1.8)
			elif night and world._hash01(cx, cz, 120) > 0.52:
				kind = BAT
			elif world.biome_at(x, z) == "meadow":
				kind = SHEEP if world._hash01(cx, cz, 131) < 0.58 else PIG
			elif world.biome_at(x, z) == "old_forest" and world._hash01(cx, cz, 132) > 0.36:
				kind = TARSIER
			elif world._landmark_clearance(x, z) or world.path_distance(x, z) < 2.8:
				continue
			if Vector2(player.position.x, player.position.z).distance_squared_to(Vector2(x, z)) > 57.0 * 57.0:
				continue
			wanted.append({"id": "%s:%d:%d" % [kind, cx, cz], "kind": kind, "home": Vector2(x, z), "side": side})

	var selected: Dictionary = {}
	var cap := MAX_HIGH if detailed else MAX_LOW
	for item in wanted:
		if selected.size() >= cap:
			break
		selected[item["id"]] = item
	for id in _animals.keys():
		if not selected.has(id):
			_animals[id]["pivot"].queue_free()
			_animals.erase(id)
	for id in selected:
		if not _animals.has(id):
			_spawn(selected[id])

func _spawn(spec: Dictionary) -> void:
	var kind: String = spec["kind"]
	if not _templates.has(kind):
		return
	var pivot := Node3D.new()
	pivot.name = "Животное_" + kind
	add_child(pivot)
	var visual: Node3D = _templates[kind].instantiate() as Node3D
	if visual == null:
		pivot.queue_free()
		return
	# Use the same skeleton-aware fitting as the hero and society NPCs.
	# Mesh AABBs of imported skinned animals may be tiny; the former fitter
	# accidentally enlarged sheep and pigs to dozens of world metres.
	pivot.add_child(Fitting.wrap_to_height(visual, float(HEIGHTS[kind])))
	var animation := _find_player(visual)
	var clip_names: Dictionary = {}
	if animation != null:
		for key in animation.get_animation_list():
			var label := str(key).to_lower()
			if kind == FOX:
				for target in ["survey", "walk", "run"]:
					if label.ends_with(target):
						clip_names[target] = key
			elif DIRECT_CLIPS.has(kind):
				if label == "idle" or label.ends_with("/idle"):
					clip_names["idle"] = key
				elif label == "walk" or label.ends_with("/walk"):
					clip_names["walk"] = key
			else:
				if label.ends_with("clip"):
					clip_names["baked"] = key
				elif label != "reset" and not clip_names.has("baked"):
					clip_names["baked"] = key
	var home: Vector2 = spec["home"]
	var side: float = spec["side"]
	if kind not in [DUCK, PLATYPUS, BAT] and not world.can_walk(home.x, home.y, bool(world.get("bridge_open"))):
		for radius in [1.8, 3.0, 4.5, 6.0]:
			var found := false
			for i in range(8):
				var candidate: Vector2 = home + Vector2(cos(TAU * i / 8.0), sin(TAU * i / 8.0)) * radius
				if world.can_walk(candidate.x, candidate.y, bool(world.get("bridge_open"))):
					home = candidate
					found = true
					break
			if found:
				break
	var height: float = _height(kind, home.x, home.y, side)
	pivot.position = Vector3(home.x, height, home.y)
	var seed: float = world._hash01(floori(home.x), floori(home.y), 123)
	var entry := {
		"id": spec["id"], "kind": kind, "pivot": pivot, "home": home,
		"side": side, "phase": seed * TAU, "heading": seed * TAU,
		"timer": seed * 2.0, "moving": false, "motion": "",
		"motion_time": 0.0, "animation": animation, "clips": clip_names
	}
	_animals[spec["id"]] = entry
	_play(entry, "idle")

func _height(kind: String, x: float, z: float, _side: float) -> float:
	if kind == DUCK:
		return -0.49
	if kind == BAT:
		return world.ground_height(x, z) + 2.5
	return world.ground_height(x, z) + 0.08

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null

func _step_animal(entry: Dictionary, delta: float) -> void:
	var kind: String = entry["kind"]
	var pivot: Node3D = entry["pivot"]
	var home: Vector2 = entry["home"]
	var side: float = entry["side"]
	var current := Vector2(pivot.position.x, pivot.position.z)
	var elapsed: float = float(entry["timer"]) + delta
	var moving: bool = entry["moving"]
	var duration := (2.4 if moving else 2.0) + float(entry["phase"]) * 0.3
	if elapsed > duration:
		moving = not moving
		elapsed = 0.0
		entry["heading"] = float(entry["heading"]) + PI * (world._hash01(floori(_elapsed), floori(home.x), 170) - 0.5) * 0.7
	entry["timer"] = elapsed

	var heading: float = entry["heading"]
	var flee := false
	var player_point := Vector2(player.position.x, player.position.z)
	var player_distance := current.distance_to(player_point)
	if kind in [FOX, TARSIER, SHEEP, ROOSTER, BAT] and player_distance < (7.0 if kind == FOX else 4.5):
		var away := current - player_point
		if away.length_squared() > 0.05:
			heading = atan2(away.x, away.y)
			moving = true
			flee = true
	elif kind == CORGI and player_distance > 3.0 and player_distance < 10.0 and player_point.distance_to(home) < 13.0:
		var toward := player_point - current
		heading = atan2(toward.x, toward.y)
		moving = true
	elif kind in [SHEEP, PIG, CORGI]:
		# Small herds respond to one another; avoid overlapping and occasionally
		# move toward a nearby companion instead of wandering in isolation.
		var closest := _nearest_companion(entry, current, 8.0)
		if not closest.is_empty():
			var offset: Vector2 = closest["position"] - current
			if offset.length_squared() < 2.0 * 2.0:
				heading = atan2(-offset.x, -offset.y)
				moving = true
			elif offset.length_squared() > 3.5 * 3.5 and moving:
				heading = atan2(offset.x, offset.y)

	var moved := false
	if moving:
		var direction := Vector2(sin(heading), cos(heading))
		var leash := (10.0 if flee else (8.0 if kind == CORGI else 6.5))
		if current.distance_to(home) > leash:
			direction = (home - current).normalized()
			heading = atan2(direction.x, direction.y)
		var speed := (2.1 if flee else 1.25) if kind == FOX else (1.4 if flee else (0.9 if kind == CORGI or DIRECT_CLIPS.has(kind) else 0.68))
		var step := speed * delta
		if kind in [DUCK, PLATYPUS]:
			var next := current + direction * step
			var river_z: float = world.river_center(next.x) + side * (world.river_half_width(next.x) * 0.52 if kind == DUCK else world.river_half_width(next.x) + 1.8)
			next.y = lerpf(next.y, river_z, minf(1.0, delta * 2.6))
			pivot.position.x = next.x
			pivot.position.z = next.y
			moved = current.distance_squared_to(next) > 0.00001
		elif kind == BAT:
			var next := current + direction * step
			pivot.position.x = next.x
			pivot.position.z = next.y
			moved = true
		else:
			# Probe both sides when a tree, a house or another animal blocks
			# the route; never move the model while keeping its legs idle.
			for turn in [0.0, 0.55, -0.55, 1.1, -1.1, PI]:
				var probe_direction := direction.rotated(turn)
				var probe := current + probe_direction * step
				if not world.can_walk(probe.x, probe.y, bool(world.get("bridge_open"))):
					continue
				if _is_occupied(entry, probe, 0.9):
					continue
				pivot.position.x = probe.x
				pivot.position.z = probe.y
				heading = atan2(probe_direction.x, probe_direction.y)
				moved = true
				break
			if not moved:
				# A streamed tree can appear over an old spawn point. Find
				# a clear nearby point once, then resume normal stepping.
				if not world.can_walk(current.x, current.y, bool(world.get("bridge_open"))):
					for radius in [1.5, 2.6, 3.8]:
						for i in range(8):
							var escape: Vector2 = current + Vector2(cos(TAU * i / 8.0), sin(TAU * i / 8.0)) * radius
							if world.can_walk(escape.x, escape.y, bool(world.get("bridge_open"))) and not _is_occupied(entry, escape, 0.9):
								pivot.position.x = escape.x
								pivot.position.z = escape.y
								moved = true
								break
						if moved:
							break
				if not moved:
					entry["timer"] = maxf(float(entry["timer"]), duration - 0.35)
	if moved:
		entry["heading"] = heading
		pivot.rotation.y = lerp_angle(pivot.rotation.y, heading, minf(1.0, delta * 7.0))
	entry["moving"] = moved
	var motion := "run" if moved and flee and kind == FOX else ("walk" if moved else "idle")
	if str(entry["motion"]) != motion:
		_play(entry, motion)
	var y := _height(kind, pivot.position.x, pivot.position.z, side)
	if kind == BAT:
		y += sin(_elapsed * 3.0 + float(entry["phase"])) * 0.35
	pivot.position.y = lerpf(pivot.position.y, y, minf(1.0, delta * 5.0))
	_advance_animation(entry, delta)


func _nearest_companion(entry: Dictionary, point: Vector2, radius: float) -> Dictionary:
	var result := {}
	var best := radius * radius
	for other in _animals.values():
		if other["id"] == entry["id"] or other["kind"] != entry["kind"]:
			continue
		var pivot: Node3D = other["pivot"]
		var location := Vector2(pivot.position.x, pivot.position.z)
		var distance := point.distance_squared_to(location)
		if distance < best:
			best = distance
			result = {"position": location}
	return result


func _is_occupied(entry: Dictionary, point: Vector2, radius: float) -> bool:
	for other in _animals.values():
		if other["id"] == entry["id"] or other["kind"] == BAT:
			continue
		var pivot: Node3D = other["pivot"]
		if point.distance_squared_to(Vector2(pivot.position.x, pivot.position.z)) < radius * radius:
			return true
	return false

func _play(entry: Dictionary, motion: String) -> void:
	entry["motion"] = motion
	entry["motion_time"] = 0.0
	var anim: AnimationPlayer = entry["animation"]
	if anim == null:
		return
	var clips: Dictionary = entry["clips"]
	var clip: StringName = &""
	if entry["kind"] == FOX:
		clip = clips.get("run" if motion == "run" else ("walk" if motion == "walk" else "survey"), clips.get("walk", &""))
	elif DIRECT_CLIPS.has(entry["kind"]):
		clip = clips.get("walk" if motion == "walk" else "idle", &"")
	else:
		clip = clips.get("baked", &"")
	if clip == &"":
		return
	anim.play(clip)
	anim.pause()
	entry["active_clip"] = clip

func _advance_animation(entry: Dictionary, delta: float) -> void:
	var anim: AnimationPlayer = entry["animation"]
	if anim == null or not entry.has("active_clip"):
		return
	var clip: StringName = entry["active_clip"]
	var source: Animation = anim.get_animation(clip)
	if source == null:
		return
	var speed := 1.0
	var time := float(entry["motion_time"]) + delta * speed
	entry["motion_time"] = time
	var start := 0.0
	var duration := source.length
	if entry["kind"] != FOX and not DIRECT_CLIPS.has(entry["kind"]):
		var segment: Vector2 = BAKED_CLIPS.get(entry["motion"], BAKED_CLIPS["idle"])
		start = segment.x
		duration = segment.y - segment.x
	else:
		duration = maxf(0.15, source.length - 0.04)
	anim.seek(start + fposmod(time, maxf(0.12, duration)), true)

