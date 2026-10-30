extends Node3D
class_name ValleyBuilderAI
const ACTOR_ANIMATION = preload("res://scripts/actor_animation.gd")
const MODEL_FITTING = preload("res://scripts/model_fitting.gd")
## Бруно: автономная добыча, доставка, стройка, отдых и восстановление леса.
## Работает в той же координатной системе, что и Паки; ресурсы поселения
## отделены от сумки игрока. Действия и оплаченные этапы сохраняются.
const TREE_SITES := [Vector2(22.0, -27.0), Vector2(33.0, -37.0), Vector2(40.0, -29.0)]
const STONE_SITES := [Vector2(20.0, -35.0), Vector2(41.0, -22.0)]
const DEPOT := Vector2(24.0, -27.0)
const WORK_POINT := Vector2(28.0, -23.0)
const SHELTER := Vector2(22.0, -24.0)
const WELL := Vector2(13.0, 1.0)
const PATROL := [Vector2(24.0, -28.0), Vector2(38.0, -24.0), Vector2(26.0, -35.0)]
const CELL_SIZE := 2.0
const BRUNO_HEIGHT := 2.6
const BRUNO_MODEL_YAW := ACTOR_ANIMATION.BRUNO_VISUAL_YAW
const ACTION_TIME := {
	"chop": 4.4, "gather": 2.4, "deposit": 1.1,
	"rest": 8.0, "plant": 5.5, "water": 3.5, "refill": 2.0
}
const LABELS := {
	"decide": "Выбирает работу", "move": "Идёт к месту работы",
	"chop": "Рубит рабочее дерево", "gather": "Добывает камни",
	"deposit": "Разгружает материалы", "build": "Строит мастерскую",
	"rest": "Отдыхает", "plant": "Сажает дерево",
	"water": "Поливает саженец", "refill": "Набирает воду"
}

var world: Node3D
var workshop: Node3D
var hero: Node3D
var data: Dictionary = {}
var animation: AnimationPlayer
var visual: Node3D
var on_event: Callable
var paused := false
var _walking := false
var _motion := ""
var _nav: Array[Vector2] = []
var _nav_destination := Vector2(INF, INF)
var _repath_after := 0.0
var _walkability_cache: Dictionary = {}
var _cached_navigation_revision := -1
var _patrol_index := 0
var _scenery_trees: Array[Node3D] = []
var _scenery_saplings: Array[Node3D] = []
var _scenery_stones: Array[Node3D] = []
var _carry: Node3D
var _axe: Node3D
var community: Node
var community_cargo := 0

func setup(world_ref: Node3D, workshop_ref: Node3D, hero_ref: Node3D, saved: Dictionary, callback: Callable) -> void:
	world = world_ref
	workshop = workshop_ref
	hero = hero_ref
	on_event = callback
	data = {
		"version": 2,
		"stage": clampi(int(saved.get("stage", 0)), 0, 5),
		"position": {"x": float(saved.get("position", {}).get("x", 24.0)), "z": float(saved.get("position", {}).get("z", -28.0))},
		"phase": str(saved.get("phase", "decide")),
		"timer": clampf(float(saved.get("timer", 0.0)), 0.0, 30.0),
		"stock": _supplies(saved.get("stock", {})),
		"stock_shared": bool(saved.get("stock_shared", false)),
		"bag": _supplies(saved.get("bag", {})),
		"trees": [], "stones": [],
		"generated": _supplies(saved.get("generated", {})),
		"spent": _supplies(saved.get("spent", {})),
		"donated": _supplies(saved.get("donated", {})),
		"paidStage": clampi(int(saved.get("paidStage", 0)), 0, 5),
		"seeds": clampi(int(saved.get("seeds", 3)), 0, 3),
		"water": clampi(int(saved.get("water", 3)), 0, 3),
		"food": clampi(int(saved.get("food", 2)), 0, 2),
		"energy": clampf(float(saved.get("energy", 100.0)), 0.0, 100.0),
		"mode": "follow" if saved.get("mode") == "follow" else "work",
		"target": saved.get("target", {}).duplicate(true) if saved.get("target") is Dictionary else {},
		"log": saved.get("log", []).duplicate() if saved.get("log") is Array else [],
		"rewarded": bool(saved.get("rewarded", int(saved.get("stage", 0)) >= 5))
	}
	var old_trees: Array = saved.get("trees", []) if saved.get("trees", []) is Array else []
	for i in range(TREE_SITES.size()):
		var t: Dictionary = old_trees[i] if i < old_trees.size() and old_trees[i] is Dictionary else {}
		data["trees"].append({"cut": bool(t.get("cut", false)), "planted": bool(t.get("planted", false)), "watered": bool(t.get("watered", false))})
	var old_stones: Array = saved.get("stones", []) if saved.get("stones", []) is Array else []
	for i in range(STONE_SITES.size()):
		data["stones"].append(clampi(int(old_stones[i]) if i < old_stones.size() else 0, 0, 2))
	if not ["decide", "move", "chop", "gather", "deposit", "build", "rest", "plant", "water", "refill"].has(data["phase"]):
		data["phase"] = "decide"
	if data["phase"] != "decide" and data["target"].is_empty():
		data["phase"] = "decide"
	if data["phase"] == "build" and int(data["paidStage"]) != int(data["stage"]) + 1:
		data["phase"] = "decide"
	data["log"] = data["log"].slice(maxi(0, data["log"].size() - 8))

func _supplies(value: Variant) -> Dictionary:
	var source: Dictionary = value if value is Dictionary else {}
	return {"wood": clampi(int(source.get("wood", 0)), 0, 999), "stone": clampi(int(source.get("stone", 0)), 0, 999)}

func _ready() -> void:
	var pos: Dictionary = data.get("position", {"x": 24.0, "z": -28.0})
	position = Vector3(float(pos["x"]), 0.0, float(pos["z"]))
	_update_height()
	visual = _create_model("bruno-builder", BRUNO_HEIGHT)
	visual.rotation.y = BRUNO_MODEL_YAW # Bruno's imported +Z faces forward after this offset.
	add_child(visual)
	animation = _find_animation(visual)
	if animation != null:
		ACTOR_ANIMATION.lock_horizontal_motion(animation, false)
	_make_working_tools()
	_create_work_sites()
	_refresh_work_sites()
	_play_animation("Idle")

func _create_model(asset_name: String, target_height: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Внешность Бруно"
	var path := "res://assets/%s.glb" % asset_name
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var imported := packed.instantiate() as Node3D
			if imported != null:
				root.add_child(MODEL_FITTING.wrap_to_height(imported, target_height))
			return root
	var marker := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.65
	mesh.height = target_height
	marker.mesh = mesh
	marker.position.y = target_height * 0.5
	root.add_child(marker)
	return root

func _collect_bounds(node: Node, bounds: Dictionary, parent_transform: Transform3D = Transform3D.IDENTITY) -> void:
	var relative := parent_transform
	if node is Node3D:
		relative = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var box := mesh_node.get_aabb()
		for y in [box.position.y, box.end.y]:
			for x in [box.position.x, box.end.x]:
				for z in [box.position.z, box.end.z]:
					var corner := relative * Vector3(x, y, z)
					bounds["min"] = minf(float(bounds["min"]), corner.y)
					bounds["max"] = maxf(float(bounds["max"]), corner.y)
					bounds["min_x"] = minf(float(bounds["min_x"]), corner.x)
					bounds["max_x"] = maxf(float(bounds["max_x"]), corner.x)
					bounds["min_z"] = minf(float(bounds["min_z"]), corner.z)
					bounds["max_z"] = maxf(float(bounds["max_z"]), corner.z)
	for child in node.get_children():
		_collect_bounds(child, bounds, relative)

func _find_animation(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_animation(child)
		if result != null:
			return result
	return null

func _simple_box(size: Vector3, tint: Color, parent: Node3D) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.92
	item.material_override = mat
	parent.add_child(item)
	return item

func _make_working_tools() -> void:
	_carry = Node3D.new()
	_carry.name = "Переносимые материалы"
	add_child(_carry)
	_carry.position = Vector3(0.0, 2.0, -0.8)
	var box := _simple_box(Vector3(0.8, 0.5, 0.6), Color("#a47f50"), _carry)
	box.position.y = 0.0
	_axe = Node3D.new()
	_axe.name = "Рабочий топор"
	visual.add_child(_axe)
	var hand_attached := false
	var skeleton := _find_skeleton(visual)
	if skeleton != null:
		var bone := skeleton.find_bone("mixamorigRightHand")
		if bone == -1:
			bone = skeleton.find_bone("mixamorig:RightHand")
		if bone >= 0:
			var attach := BoneAttachment3D.new()
			attach.bone_name = skeleton.get_bone_name(bone)
			skeleton.add_child(attach)
			_axe.reparent(attach, false)
			hand_attached = true
	if not hand_attached:
		_axe.position = Vector3(0.65, 2.1, -0.25)
	var haft := _simple_box(Vector3(0.12, 1.0, 0.12), Color("#8e6646"), _axe)
	haft.position.y = 0.25
	var blade := _simple_box(Vector3(0.45, 0.26, 0.12), Color("#9aa7a9"), _axe)
	blade.position = Vector3(0.23, 0.65, 0.0)
	_axe.visible = false
	_carry.visible = false

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result != null:
			return result
	return null

func _create_work_sites() -> void:
	for p in TREE_SITES:
		var tree := _create_model("tree-oak", 6.4)
		tree.position = Vector3(p.x, world.ground_height(p.x, p.y), p.y)
		get_parent().add_child(tree)
		_scenery_trees.append(tree)
		var sapling := Node3D.new()
		sapling.position = tree.position
		get_parent().add_child(sapling)
		var trunk := _simple_box(Vector3(0.14, 0.65, 0.14), Color("#94764b"), sapling)
		trunk.position.y = 0.3
		var crown := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.38
		mesh.height = 0.75
		crown.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#74ac64")
		crown.material_override = mat
		crown.position.y = 0.82
		sapling.add_child(crown)
		_scenery_saplings.append(sapling)
	for p in STONE_SITES:
		var stone := _create_model("rock-largea", 1.4)
		stone.position = Vector3(p.x, world.ground_height(p.x, p.y), p.y)
		get_parent().add_child(stone)
		_scenery_stones.append(stone)

func _refresh_work_sites() -> void:
	if _scenery_trees.size() != TREE_SITES.size() or _scenery_stones.size() != STONE_SITES.size():
		return
	for i in range(TREE_SITES.size()):
		var t: Dictionary = data["trees"][i]
		_scenery_trees[i].visible = not bool(t["cut"])
		_scenery_saplings[i].visible = bool(t["planted"])
		var scale := 0.9 if bool(t["watered"]) else 0.55
		_scenery_saplings[i].scale = Vector3.ONE * scale
	world.set_builder_trees(data["trees"])
	for i in range(STONE_SITES.size()):
		_scenery_stones[i].visible = int(data["stones"][i]) < 2

func tick(delta: float, rain: bool, night: bool) -> void:
	if paused or world == null or hero == null:
		return
	var dt := clampf(delta, 0.0, 0.1)
	_walking = false
	_repath_after -= dt
	if community != null and community.drive_builder(self, dt, rain, night):
		_update_height()
		data["position"] = {"x":position.x,"z":position.z}
		_update_animation()
		return
	var location := Vector2(position.x, position.z)
	if data["mode"] == "follow":
		var behind := hero.global_transform.basis.z
		var follow_goal := Vector2(hero.position.x + behind.x * 2.5, hero.position.z + behind.z * 2.5)
		if location.distance_to(follow_goal) > 2.0:
			_move_to(follow_goal, dt, 2.8)
	elif rain or night:
		if location.distance_to(SHELTER) > 1.1:
			_move_to(SHELTER, dt, 2.6)
		else:
			data["energy"] = minf(100.0, float(data["energy"]) + dt * 1.5)
	else:
		match str(data["phase"]):
			"decide":
				_choose_next()
			"move":
				var target: Dictionary = data["target"]
				var goal := Vector2(float(target.get("x", DEPOT.x)), float(target.get("z", DEPOT.y)))
				var pace := 2.0 if int(data["bag"]["wood"]) + int(data["bag"]["stone"]) > 0 else 2.5
				if _move_to(goal, dt, pace):
					_begin_action()
			_:
				# После режима сопровождения или непогоды сначала возвращаемся
				# на рабочее место. Оплаченная работа не завершается издалека.
				var target: Dictionary = data["target"]
				var work_point := Vector2(float(target.get("x", DEPOT.x)), float(target.get("z", DEPOT.y)))
				if location.distance_to(work_point) > 1.1:
					_move_to(work_point, dt, 2.3)
				else:
					data["timer"] = maxf(0.0, float(data["timer"]) - dt)
					if float(data["timer"]) <= 0.0:
						_complete_action()
	_update_height()
	data["position"] = {"x": position.x, "z": position.z}
	_update_animation()

func _choose_next() -> void:
	var stage := int(data["stage"])
	var bag: Dictionary = data["bag"]
	var stock: Dictionary = data["stock"]
	if int(bag["wood"]) + int(bag["stone"]) > 0:
		_start_trip(DEPOT, "deposit")
		return
	if float(data["energy"]) < 25.0:
		_start_trip(SHELTER, "rest")
		return
	if stage < workshop.total_stages():
		var cost: Dictionary = workshop.cost_for(stage + 1)
		if int(stock["wood"]) >= int(cost["wood"]) and int(stock["stone"]) >= int(cost["stone"]):
			_start_trip(WORK_POINT, "build")
			return
		if int(stock["wood"]) < int(cost["wood"]):
			for i in range(TREE_SITES.size()):
				if not bool(data["trees"][i]["cut"]):
					_start_trip(TREE_SITES[i] + Vector2(-2.0, 0.0), "chop", i)
					return
		if int(stock["stone"]) < int(cost["stone"]):
			for i in range(STONE_SITES.size()):
				if int(data["stones"][i]) < 2:
					_start_trip(STONE_SITES[i] + Vector2(-1.8, -0.4), "gather", i)
					return
		_start_trip(SHELTER, "rest")
		return
	for i in range(TREE_SITES.size()):
		if bool(data["trees"][i]["cut"]) and not bool(data["trees"][i]["planted"]) and int(data["seeds"]) > 0:
			_start_trip(TREE_SITES[i] + Vector2(-2.0, 0.0), "plant", i)
			return
	for i in range(TREE_SITES.size()):
		if bool(data["trees"][i]["planted"]) and not bool(data["trees"][i]["watered"]):
			if int(data["water"]) > 0:
				_start_trip(TREE_SITES[i] + Vector2(-2.0, 0.0), "water", i)
			else:
				_start_trip(WELL, "refill")
			return
	_patrol_index = (_patrol_index + 1) % PATROL.size()
	_start_trip(PATROL[_patrol_index], "rest")

func _start_trip(point: Vector2, task: String, index: int = -1) -> void:
	data["target"] = {"x": point.x, "z": point.y, "then": task, "index": index}
	data["phase"] = "move"
	data["timer"] = 0.0
	_nav.clear()
	_nav_destination = Vector2(INF, INF)
	_repath_after = 0.0

func _begin_action() -> void:
	var target: Dictionary = data["target"]
	var task := str(target.get("then", "rest"))
	if task == "build":
		var current := int(data["stage"])
		var next := current + 1
		if next > workshop.total_stages():
			_reset_job()
			return
		var required: Dictionary = workshop.cost_for(next)
		var stock: Dictionary = data["stock"]
		if int(stock["wood"]) < int(required["wood"]) or int(stock["stone"]) < int(required["stone"]):
			_reset_job()
			return
		stock["wood"] = int(stock["wood"]) - int(required["wood"])
		stock["stone"] = int(stock["stone"]) - int(required["stone"])
		data["spent"]["wood"] = int(data["spent"]["wood"]) + int(required["wood"])
		data["spent"]["stone"] = int(data["spent"]["stone"]) + int(required["stone"])
		data["paidStage"] = next
		data["timer"] = 4.0 + float(next)
		_notify("Бруно начал этап: %s." % workshop.stage_name(next))
	else:
		data["timer"] = float(ACTION_TIME.get(task, 2.0))
	data["phase"] = task

func _complete_action() -> void:
	var target: Dictionary = data["target"]
	var task := str(data["phase"])
	var i := int(target.get("index", -1))
	var message := ""
	match task:
		"chop":
			if i >= 0 and i < TREE_SITES.size() and not bool(data["trees"][i]["cut"]):
				data["trees"][i]["cut"] = true
				data["bag"]["wood"] = int(data["bag"]["wood"]) + 2
				data["generated"]["wood"] = int(data["generated"]["wood"]) + 2
				message = "Бруно срубил рабочее дерево и заготовил две ветки."
		"gather":
			if i >= 0 and i < STONE_SITES.size() and int(data["stones"][i]) < 2:
				var amount := 2 - int(data["stones"][i])
				data["stones"][i] = 2
				data["bag"]["stone"] = int(data["bag"]["stone"]) + amount
				data["generated"]["stone"] = int(data["generated"]["stone"]) + amount
				message = "Бруно добыл %d камня." % amount
		"deposit":
			for key in ["wood", "stone"]:
				data["stock"][key] = int(data["stock"][key]) + int(data["bag"][key])
				data["bag"][key] = 0
			message = "Бруно доставил материалы на склад."
		"build":
			var next := int(data["stage"]) + 1
			if int(data["paidStage"]) == next:
				data["stage"] = next
				data["paidStage"] = 0
				workshop.set_stage(next, true)
				world.set_workshop_stage(next)
				message = "Бруно закончил этап: %s." % workshop.stage_name(next)
		"plant":
			if i >= 0 and i < TREE_SITES.size() and int(data["seeds"]) > 0 and not bool(data["trees"][i]["planted"]):
				data["seeds"] = int(data["seeds"]) - 1
				data["trees"][i]["planted"] = true
				message = "Бруно посадил саженец на вырубке."
		"water":
			if i >= 0 and i < TREE_SITES.size() and int(data["water"]) > 0 and not bool(data["trees"][i]["watered"]):
				data["water"] = int(data["water"]) - 1
				data["trees"][i]["watered"] = true
				message = "Бруно полил молодое дерево."
		"refill":
			data["water"] = 3
			message = "Бруно набрал воду у реки."
		"rest":
			data["energy"] = minf(100.0, float(data["energy"]) + 24.0)
			if float(data["energy"]) < 60.0 and int(data["food"]) > 0:
				data["food"] = int(data["food"]) - 1
				data["energy"] = minf(100.0, float(data["energy"]) + 20.0)
	data["energy"] = maxf(0.0, float(data["energy"]) - 1.5)
	_refresh_work_sites()
	_reset_job()
	if message != "":
		_notify(message)

func _reset_job() -> void:
	data["phase"] = "decide"
	data["timer"] = 0.0
	data["target"] = {}
	_nav.clear()
	_nav_destination = Vector2(INF, INF)

func _update_height() -> void:
	if world != null:
		position.y = world.ground_height(position.x, position.z)

func _move_to(goal: Vector2, dt: float, speed: float) -> bool:
	var current := Vector2(position.x, position.z)
	if current.distance_to(goal) < 0.65:
		return true
	if _nav.is_empty() or _nav_destination.distance_to(goal) > 1.7:
		if _repath_after <= 0.0:
			_nav = _find_route(current, goal)
			_nav_destination = goal
			_repath_after = 1.2
		if _nav.is_empty():
			return false
	var waypoint: Vector2 = _nav.front()
	if current.distance_to(waypoint) < 0.45:
		_nav.pop_front()
		return false
	var direction: Vector2 = (waypoint - current).normalized()
	var step: Vector2 = direction * minf(speed * dt, current.distance_to(waypoint))
	var next: Vector2 = current + step
	var player_pos := Vector2(hero.position.x, hero.position.z)
	if next.distance_to(player_pos) < 1.35 and next.distance_to(player_pos) <= current.distance_to(player_pos):
		return false
	if not world.can_walk(next.x, next.y, false):
		_nav.clear()
		_repath_after = 0.15
		return false
	position.x = next.x
	position.z = next.y
	_walking = true
	data["energy"] = maxf(0.0, float(data["energy"]) - dt * 0.05)
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.y), minf(1.0, dt * 9.0))
	return Vector2(position.x, position.z).distance_to(goal) < 0.65

func _find_route(start: Vector2, destination: Vector2) -> Array[Vector2]:
	var goal := destination
	if start.distance_to(goal) > 35.0:
		goal = start + (goal - start).normalized() * 35.0
	var result: Array[Vector2] = []
	for padding in [7, 13]:
		result = _grid_route(start, goal, padding)
		if not result.is_empty():
			break
	return result

func _grid_route(start: Vector2, goal: Vector2, padding: int) -> Array[Vector2]:
	var x0 := floori(minf(start.x, goal.x) / CELL_SIZE) - padding
	var x1 := ceili(maxf(start.x, goal.x) / CELL_SIZE) + padding
	var y0 := floori(minf(start.y, goal.y) / CELL_SIZE) - padding
	var y1 := ceili(maxf(start.y, goal.y) / CELL_SIZE) + padding
	if (x1 - x0 + 1) * (y1 - y0 + 1) > 1600:
		return []
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	grid.cell_size = Vector2.ONE * CELL_SIZE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	grid.update()
	# A route can revisit the same terrain grid points many times. Keep the
	# collision result until the world reports a change in its obstacles.
	if _cached_navigation_revision != world.navigation_revision:
		_walkability_cache.clear()
		_cached_navigation_revision = world.navigation_revision
	if _walkability_cache.size() > 4096:
		_walkability_cache.clear()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var index := Vector2i(x, y)
			if not _walkability_cache.has(index):
				_walkability_cache[index] = world.can_walk(x * CELL_SIZE, y * CELL_SIZE, false)
			if not _walkability_cache[index]:
				grid.set_point_solid(index, true)
	var first := _nearest_open(grid, Vector2i(roundi(start.x / CELL_SIZE), roundi(start.y / CELL_SIZE)))
	var last := _nearest_open(grid, Vector2i(roundi(goal.x / CELL_SIZE), roundi(goal.y / CELL_SIZE)))
	var route: Array[Vector2] = []
	if not grid.is_in_boundsv(first) or not grid.is_in_boundsv(last):
		return route
	for point in grid.get_id_path(first, last):
		route.append(Vector2(point.x * CELL_SIZE, point.y * CELL_SIZE))
	if not route.is_empty() and world.can_walk(goal.x, goal.y, false):
		route.append(goal)
	return route

func _nearest_open(grid: AStarGrid2D, candidate: Vector2i) -> Vector2i:
	if grid.is_in_boundsv(candidate) and not grid.is_point_solid(candidate):
		return candidate
	var best := Vector2i(2147483647, 2147483647)
	var best_dist := INF
	for radius in range(1, 4):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var point := candidate + Vector2i(dx, dy)
				if not grid.is_in_boundsv(point) or grid.is_point_solid(point):
					continue
				var d := float(dx * dx + dy * dy)
				if d < best_dist:
					best = point
					best_dist = d
		if best_dist < INF:
			return best
	return best

func _update_animation() -> void:
	var carrying := int(data["bag"]["wood"]) + int(data["bag"]["stone"]) + community_cargo > 0
	_carry.visible = carrying
	_axe.visible = str(data["phase"]) in ["chop", "build"] and data["mode"] != "follow"
	if animation == null:
		return
	var desired := "Walk" if _walking else "Idle"
	if _walking and carrying:
		desired = "HoldingWalk"
	elif not _walking and carrying:
		desired = "HoldingIdle"
	elif not _walking and data["mode"] != "follow":
		match str(data["phase"]):
			"chop", "build": desired = "Woodcut"
			"gather": desired = "Gather"
			"plant": desired = "Plant"
			"water": desired = "Water"
			"deposit": desired = "HoldingIdle"
	var motion := _choose_clip(desired)
	if motion == "":
		return
	if motion != _motion or not animation.is_playing():
		_motion = motion
		animation.play(motion, 0.18)

func _choose_clip(name: String) -> String:
	for clip in animation.get_animation_list():
		var value := str(clip)
		if value == name or value == "Bruno_" + name or value.ends_with("/Bruno_" + name) or value.ends_with("/" + name):
			return value
	return ""

func _play_animation(name: String) -> void:
	if animation == null:
		return
	var clip := _choose_clip(name)
	if clip != "":
		animation.play(clip)
		_motion = clip

func command(mode: String) -> void:
	if community != null: community.release_worker("bruno")
	data["mode"] = "follow" if mode == "follow" else "work"
	_nav.clear()
	_repath_after = 0.0
	_nav_destination = Vector2(INF, INF)
	_notify("Бруно следует за Паки." if data["mode"] == "follow" else "Бруно возвращается к работе.")

func donate(kind: String) -> bool:
	if kind != "wood" and kind != "stone":
		return false
	data["stock"][kind] = int(data["stock"][kind]) + 1
	data["donated"][kind] = int(data["donated"][kind]) + 1
	_notify("Бруно принял %s." % ("ветку" if kind == "wood" else "камень"))
	return true

func player_completed_stage(next_stage: int) -> void:
	if next_stage <= int(data["stage"]):
		return
	# Если Бруно уже оплатил этот этап, возвращаем его материалы на склад.
	if int(data["paidStage"]) == next_stage:
		var cost: Dictionary = workshop.cost_for(next_stage)
		for kind in ["wood", "stone"]:
			data["stock"][kind] = int(data["stock"][kind]) + int(cost[kind])
			data["spent"][kind] = maxi(0, int(data["spent"][kind]) - int(cost[kind]))
	data["stage"] = clampi(next_stage, 0, workshop.total_stages())
	data["paidStage"] = 0
	_reset_job()
	_notify("Паки помог завершить этап мастерской.")

func set_paused(value: bool) -> void:
	paused = value

func stage() -> int:
	return int(data.get("stage", 0))

func status(rain: bool, night: bool) -> String:
	if paused:
		return "Разговаривает с Паки"
	if data["mode"] == "follow":
		return "Следует за Паки"
	if rain or night:
		return "Пережидает непогоду"
	if community != null:
		return community.builder_status(self)
	return str(LABELS.get(str(data["phase"]), "Ищет дело"))

func snapshot() -> Dictionary:
	return data.duplicate(true)

func _notify(message: String) -> void:
	data["log"].append(message)
	if data["log"].size() > 8:
		data["log"].pop_front()
	if on_event.is_valid():
		on_event.call(message, int(data["stage"]))

