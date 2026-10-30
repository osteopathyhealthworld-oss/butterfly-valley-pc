extends Node3D
## Visualizes a small, nearby subset of the persistent society simulation.
## Distant animals keep working but have no animated nodes or draw calls.

const Sim = preload("res://scripts/society_simulation.gd")
const Fitting = preload("res://scripts/model_fitting.gd")
const FILES := {
	"HolsteinCow": "farm/HolsteinCow", "HighlandCow": "farm/HighlandCow",
	"Lamb": "farm/Lamb", "Hummingbird": "bird/Hummingbird",
	"LeafcutterAnt": "insect/LeafcutterAnt", "HawkMoth": "insect/HawkMoth",
	"Swallowtail": "insect/Swallowtail"
}
const HEIGHTS := {"HolsteinCow": 1.7, "HighlandCow": 1.7, "Lamb": 1.1, "Hummingbird": 0.48, "LeafcutterAnt": 0.38, "HawkMoth": 0.55, "Swallowtail": 0.62}
const FLYERS := ["Hummingbird", "HawkMoth", "Swallowtail"]
const FAR_DISTANCE := 39.0

var world: Node3D
var player: Node3D
var simulation = Sim.new()
var detailed := false
var night := false
var _templates: Dictionary = {}
var _actors: Dictionary = {}
var _update_wait := 0.0
var _view_wait := 10.0
var _time := 0.0

func setup(world_ref: Node3D, hero_ref: Node3D, saved: Dictionary) -> void:
	world = world_ref
	player = hero_ref
	simulation.setup(saved)
	simulation.walk_world = world_ref

func _ready() -> void:
	for kind in FILES:
		var path: String = "res://library/prepared/gobkit/%s.glb" % FILES[kind]
		if ResourceLoader.exists(path):
			var scene := load(path) as PackedScene
			if scene != null:
				_templates[kind] = scene
		else:
			push_warning("Анимированная модель ещё не загружена: " + path)

func _process(delta: float) -> void:
	if world == null or player == null:
		return
	_time += delta
	simulation.focus = Vector2(player.position.x, player.position.z)
	_update_wait += delta
	_view_wait += delta
	if _update_wait >= 0.35:
		simulation.advance(_update_wait, night)
		_update_wait = 0.0
	if _view_wait >= 1.0:
		_view_wait = 0.0
		_refresh_visible()
	for id in _actors:
		var info: Dictionary = _actors[id]
		var animal: Dictionary = _find_agent(str(id))
		if animal.is_empty():
			continue
		_update_visible(info, animal, delta)

func _find_agent(id: String) -> Dictionary:
	for a in simulation.agents:
		if str(a["id"]) == id:
			return a
	return {}

func _refresh_visible() -> void:
	var center := Vector2(player.position.x, player.position.z)
	var candidates: Array[Dictionary] = []
	for agent in simulation.agents:
		if not _templates.has(str(agent["kind"])):
			continue
		var distance: float = center.distance_squared_to(Vector2(float(agent["x"]), float(agent["z"])))
		if distance <= FAR_DISTANCE * FAR_DISTANCE:
			candidates.append({"agent": agent, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	var count := mini(candidates.size(), 12 if detailed else 7)
	var wanted := {}
	for i in range(count):
		var agent: Dictionary = candidates[i]["agent"]
		var id: String = agent["id"]
		wanted[id] = true
		if not _actors.has(id):
			_spawn(agent)
	for id in _actors.keys():
		if not wanted.has(id):
			_actors[id]["node"].queue_free()
			_actors.erase(id)

func _spawn(agent: Dictionary) -> void:
	var kind: String = agent["kind"]
	var imported := (_templates[kind] as PackedScene).instantiate() as Node3D
	if imported == null:
		return
	var pivot := Node3D.new()
	pivot.name = "Живой житель · " + kind
	pivot.position = Vector3(float(agent["x"]), world.ground_height(float(agent["x"]), float(agent["z"])), float(agent["z"]))
	add_child(pivot)
	pivot.add_child(Fitting.wrap_to_height(imported, float(HEIGHTS[kind])))
	var animation := _animation_player(imported)
	var clips := {}
	if animation != null:
		for clip in animation.get_animation_list():
			var name := str(clip).to_lower()
			for wanted in ["idle", "walk", "fly", "eat", "crawl", "groom"]:
				if name == wanted or name.ends_with("/" + wanted):
					clips[wanted] = clip
	_actors[agent["id"]] = {"node": pivot, "kind": kind, "animation": animation, "clips": clips, "playing": ""}
	_play(_actors[agent["id"]], "idle")

func _animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _animation_player(child)
		if result != null:
			return result
	return null

func _update_visible(info: Dictionary, agent: Dictionary, delta: float) -> void:
	var pivot: Node3D = info["node"]
	var kind: String = info["kind"]
	var x := float(agent["x"])
	var z := float(agent["z"])
	var height: float = world.ground_height(x, z)
	if FLYERS.has(kind):
		height += 1.3 + sin(_time * 3.1 + float(x) * 0.8) * 0.14
	var target := Vector3(x, height, z)
	var motion := Vector2(target.x - pivot.position.x, target.z - pivot.position.z)
	var moving := motion.length_squared() > 0.005
	if moving:
		# Gobkit animals face local +Z; the agent's motion is also in world X/Z.
		pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(motion.x, motion.y), minf(1.0, delta * 7.0))
	pivot.position = pivot.position.lerp(target, minf(1.0, delta * 6.0))
	var goal: String = agent["goal"]
	if goal == "socialize":
		var partner := _find_agent(str(agent.get("partner_id", "")))
		if not partner.is_empty():
			var toward := Vector2(float(partner["x"]) - pivot.position.x, float(partner["z"]) - pivot.position.z)
			if toward.length_squared() > 0.05:
				pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(toward.x, toward.y), minf(1.0, delta * 7.0))
		_play(info, "groom")
	elif FLYERS.has(kind) and moving:
		_play(info, "fly")
	elif moving:
		_play(info, "walk")
	elif goal == "work":
		_play(info, "eat")
	else:
		_play(info, "idle")

func _play(info: Dictionary, action: String) -> void:
	var anim: AnimationPlayer = info["animation"]
	if anim == null:
		return
	var clips: Dictionary = info["clips"]
	var clip = clips.get(action, clips.get("walk" if action == "fly" else "idle", &""))
	if clip == &"":
		return
	# Imported locomotion clips may be one-shot. Keep the animated animal
	# walking as long as the persistent agent actually changes position.
	var sequence: Animation = anim.get_animation(clip)
	if sequence != null:
		sequence.loop_mode = Animation.LOOP_LINEAR
	if str(info["playing"]) == str(clip) and anim.is_playing():
		return
	info["playing"] = str(clip)
	anim.play(clip, 0.18)

func nearest_interactable(point: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_sq := radius * radius
	for id in _actors:
		var pivot: Node3D = _actors[id]["node"]
		var d := point.distance_squared_to(Vector2(pivot.position.x, pivot.position.z))
		if d < best_sq:
			var a: Dictionary = _find_agent(str(id))
			best_sq = d
			best = {"kind": "society", "id": id, "name": Sim.TITLES[a["kind"]]}
	return best

func interact(id: String) -> String:
	return simulation.interact(id)

func snapshot() -> Dictionary:
	return simulation.snapshot()

func set_detailed(enabled: bool) -> void:
	detailed = enabled
	_view_wait = 10.0

func set_night(enabled: bool) -> void:
	night = enabled

