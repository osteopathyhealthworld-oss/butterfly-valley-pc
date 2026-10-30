extends RefCounted
## Deterministic lightweight society. Every agent lives independently of
## whether its 3D model is visible. The ledger transfers actual goods.

const KINDS := ["HolsteinCow", "HighlandCow", "Lamb", "Hummingbird", "LeafcutterAnt", "HawkMoth", "Swallowtail"]
const PRODUCE := {"HolsteinCow": "milk", "HighlandCow": "milk", "Lamb": "wool", "Hummingbird": "nectar", "LeafcutterAnt": "leaves", "HawkMoth": "pollen", "Swallowtail": "pollen"}
const TITLES := {"HolsteinCow": "пятнистая корова", "HighlandCow": "горная корова", "Lamb": "ягнёнок", "Hummingbird": "колибри", "LeafcutterAnt": "муравей-сборщик", "HawkMoth": "бражник", "Swallowtail": "махаон"}
const STEP_SPEED := {"HolsteinCow": 0.9, "HighlandCow": 0.8, "Lamb": 1.1, "Hummingbird": 2.0, "LeafcutterAnt": 0.72, "HawkMoth": 1.65, "Swallowtail": 1.7}

var agents: Array[Dictionary] = []
var warehouse := {"milk": 0, "wool": 0, "nectar": 0, "leaves": 0, "pollen": 0}
var player_goods := {"milk": 0, "wool": 0, "nectar": 0, "leaves": 0, "pollen": 0}
var ledger := {"produced": 0, "delivered": 0, "gifted": 0, "meetings": 0}
var ticks := 0
var walk_world: Node3D
var focus := Vector2.ZERO
var bridge_open := false

func setup(saved: Dictionary = {}) -> void:
	if saved.get("version", 0) == 1 and saved.get("agents") is Array:
		var list: Array = saved["agents"]
		if list.size() >= 10 and list.size() <= 250:
			for item in list:
				if item is Dictionary and KINDS.has(str(item.get("kind", ""))):
					agents.append(item.duplicate(true))
			for kind in warehouse:
				warehouse[kind] = maxi(0, int(saved.get("warehouse", {}).get(kind, 0)))
				player_goods[kind] = maxi(0, int(saved.get("player_goods", {}).get(kind, 0)))
			for kind in ledger:
				ledger[kind] = maxi(0, int(saved.get("ledger", {}).get(kind, 0)))
			ticks = maxi(0, int(saved.get("ticks", 0)))
			if agents.size() >= 10:
				return
	_make_population()

func _make_population() -> void:
	# First homes are near the starting village so life is visible immediately.
	for i in range(84):
		var kind: String = KINDS[i % KINDS.size()]
		var home: Vector2
		if i < 21:
			home = Vector2(-15.0 + float(i % 7) * 5.1, -42.0 + float(i / 7) * 10.5)
		else:
			var ring := i - 21
			home = Vector2(-190.0 + float(ring % 9) * 48.0, -135.0 + float(ring / 9) * 50.0)
		var work := home + Vector2(sin(float(i) * 2.9) * 5.4, cos(float(i) * 1.67) * 5.8)
		var market := home + Vector2(8.0 if i % 2 == 0 else -7.0, 5.0)
		agents.append({
			"id": "resident-%03d" % i, "kind": kind, "x": home.x, "z": home.y,
			"home_x": home.x, "home_z": home.y, "work_x": work.x, "work_z": work.y,
			"market_x": market.x, "market_z": market.y, "goal": "work", "cargo": 0,
			"hunger": float(i % 5) * 0.1, "energy": 0.9, "friendship": 0,
			"work_wait": float(i % 4) * 0.4, "meetings": 0, "rested": false
		})

func advance(seconds: float, night: bool = false) -> void:
	var dt := clampf(seconds, 0.0, 5.0)
	if dt <= 0.0:
		return
	ticks += 1
	for i in range(agents.size()):
		var a: Dictionary = agents[i]
		var kind: String = str(a["kind"])
		var hunger := minf(1.0, float(a["hunger"]) + dt * 0.003)
		var energy := maxf(0.0, float(a["energy"]) - dt * 0.0025)
		if float(a.get("social_wait", 0.0)) > 0.0:
			a["social_wait"] = maxf(0.0, float(a["social_wait"]) - dt)
			a["goal"] = "socialize"
			a["hunger"] = hunger
			a["energy"] = energy
			continue
		var goal := "work"
		if hunger > 0.88 or energy < 0.17 or (night and i % 3 == 0):
			goal = "rest"
		elif int(a["cargo"]) >= 3:
			goal = "deliver"
		a["goal"] = goal
		var site := "market" if goal == "deliver" else ("home" if goal == "rest" else "work")
		var target := Vector2(float(a[site + "_x"]), float(a[site + "_z"]))
		# Distant agents still simulate cheaply; nearby visible residents avoid
		# trees, buildings and the river using the current streaming world.
		var position := Vector2(float(a["x"]), float(a["z"]))
		if walk_world != null and position.distance_squared_to(focus) < 55.0 * 55.0:
			target = _reachable_target(target)
		var remaining := position.distance_to(target)
		if remaining > 0.35:
			var speed: float = STEP_SPEED[kind]
			position = _walk_step(position, target, speed * dt)
			a["x"] = position.x
			a["z"] = position.y
		else:
			if goal == "deliver":
				var amount := int(a["cargo"])
				warehouse[PRODUCE[kind]] = int(warehouse[PRODUCE[kind]]) + amount
				ledger["delivered"] = int(ledger["delivered"]) + amount
				a["cargo"] = 0
			elif goal == "rest":
				hunger = maxf(0.0, hunger - dt * 0.13)
				energy = minf(1.0, energy + dt * 0.13)
			elif goal == "work":
				a["work_wait"] = float(a["work_wait"]) - dt
				if float(a["work_wait"]) <= 0.0:
					a["cargo"] = int(a["cargo"]) + 1
					ledger["produced"] = int(ledger["produced"]) + 1
					a["work_wait"] = 3.0 + float(i % 4)
			hunger = maxf(0.0, hunger - dt * 0.012) if goal == "work" and kind.contains("Cow") else hunger
		a["hunger"] = hunger
		a["energy"] = energy
	# Real social pauses: close neighbours stop, face each other, and can
	# visibly groom or idle before resuming their normal work.
	if ticks % 7 == 0:
		for i in range(agents.size() - 1):
			var a: Dictionary = agents[i]
			var b: Dictionary = agents[i + 1]
			if float(a.get("social_wait", 0.0)) > 0.0 or float(b.get("social_wait", 0.0)) > 0.0:
				continue
			if Vector2(float(a["x"]), float(a["z"])).distance_squared_to(Vector2(float(b["x"]), float(b["z"]))) < 16.0:
				a["social_wait"] = 1.1 + float(i % 3) * 0.3
				b["social_wait"] = a["social_wait"]
				a["partner_id"] = str(b["id"])
				b["partner_id"] = str(a["id"])
				a["meetings"] = int(a["meetings"]) + 1
				b["meetings"] = int(b["meetings"]) + 1
				ledger["meetings"] = int(ledger["meetings"]) + 1


func _reachable_target(target: Vector2) -> Vector2:
	if walk_world.can_walk(target.x, target.y, bridge_open):
		return target
	for radius in [1.6, 2.8, 4.0]:
		for index in range(8):
			var angle := TAU * float(index) / 8.0
			var alternative: Vector2 = target + Vector2(cos(angle), sin(angle)) * radius
			if walk_world.can_walk(alternative.x, alternative.y, bridge_open):
				return alternative
	return target


func _walk_step(position: Vector2, target: Vector2, distance: float) -> Vector2:
	var direct := position.move_toward(target, distance)
	if walk_world == null or position.distance_squared_to(focus) > 55.0 * 55.0:
		return direct
	var accessible := target
	if not walk_world.can_walk(target.x, target.y, bridge_open):
		# Fixed search order keeps the destination stable across simulation ticks.
		for radius in [1.6, 2.8, 4.0]:
			var found := false
			for index in range(8):
				var angle := TAU * float(index) / 8.0
				var alternative: Vector2 = target + Vector2(cos(angle), sin(angle)) * radius
				if walk_world.can_walk(alternative.x, alternative.y, bridge_open):
					accessible = alternative
					found = true
					break
			if found:
				break
	var delta := accessible - position
	if delta.length_squared() < 0.001:
		return position
	var step := minf(distance, delta.length())
	if not walk_world.can_walk(position.x, position.y, bridge_open):
		for radius in [1.6, 2.6, 3.8]:
			for index in range(8):
				var angle := TAU * float(index) / 8.0
				var escape: Vector2 = position + Vector2(cos(angle), sin(angle)) * radius
				if walk_world.can_walk(escape.x, escape.y, bridge_open):
					return escape
	if walk_world.can_walk(direct.x, direct.y, bridge_open) and accessible == target:
		return direct
	for turn in [0.0, 0.6, -0.6, 1.15, -1.15, PI]:
		var direction := delta.normalized().rotated(turn)
		var probe := position + direction * step
		if walk_world.can_walk(probe.x, probe.y, bridge_open):
			return probe
	return position

func nearest(point: Vector2, max_distance: float = 3.1) -> Dictionary:
	var closest := {}
	var best_distance_sq := max_distance * max_distance
	for a in agents:
		var d := point.distance_squared_to(Vector2(float(a["x"]), float(a["z"])))
		if d < best_distance_sq:
			best_distance_sq = d
			closest = {"kind": "society", "id": a["id"], "name": TITLES[a["kind"]], "distance": sqrt(d)}
	return closest

func interact(id: String) -> String:
	for a in agents:
		if str(a["id"]) != id:
			continue
		a["friendship"] = int(a["friendship"]) + 1
		var kind: String = str(a["kind"])
		if int(a["cargo"]) > 0 and int(a["friendship"]) % 2 == 0:
			a["cargo"] = int(a["cargo"]) - 1
			var good: String = PRODUCE[kind]
			player_goods[good] = int(player_goods[good]) + 1
			ledger["gifted"] = int(ledger["gifted"]) + 1
			return "%s поделился добычей: +1 %s. Подарок учтён в запасах." % [TITLES[kind].capitalize(), good]
		return "Вы познакомились: %s. Занятие: %s. Отношения: %d." % [TITLES[kind], str(a["goal"]), int(a["friendship"])]
	return "Житель уже ушёл дальше."

func snapshot() -> Dictionary:
	return {"version": 1, "agents": agents.duplicate(true), "warehouse": warehouse.duplicate(true), "player_goods": player_goods.duplicate(true), "ledger": ledger.duplicate(true), "ticks": ticks}

func count_active_near(point: Vector2, radius: float) -> int:
	var count := 0
	for a in agents:
		if point.distance_squared_to(Vector2(float(a["x"]), float(a["z"]))) <= radius * radius:
			count += 1
	return count

