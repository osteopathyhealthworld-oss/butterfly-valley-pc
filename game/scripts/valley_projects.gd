extends RefCounted
## Общая очередь. Склад, груз в поручении и материалы на площадке —
## разные места хранения. Резерв до погрузки не списывает материал.
const CONSTRUCTION = preload("res://scripts/construction.gd")
const OWNERS := ["iris", "nara", "siver", "grom", "bruno"]
const GOODS := ["wood", "stone", "herbs", "seeds", "food", "resin"]
const TITLES := {"bridge":"Переправа", "roof":"Крыша амбара", "workshop":"Мастерская Бруно"}
const POINTS := {"bridge":Vector2(5, 1), "roof":Vector2(13, -20.5), "workshop":Vector2(28, -23)}
const DEPOT := Vector2(14, -21)
const DWELL := 1.2
const CARGO_NAMES := {"wood":"древесину","stone":"камни","herbs":"травы","seeds":"семена","food":"провизию","resin":"смолу"}

var projects: Dictionary
var orders: Dictionary
var stock: Dictionary
var focus := "workshop"
var clock := 0.0
var _retry: Dictionary = {}

func setup(saved_projects: Dictionary, saved_orders: Dictionary, warehouse: Dictionary) -> void:
	projects = saved_projects
	orders = saved_orders
	stock = warehouse
	for good in GOODS:
		stock[good] = maxi(0, int(stock.get(good, 0)))
	for id in projects.keys():
		if not TITLES.has(id) or not projects[id] is Dictionary:
			projects.erase(id)
			continue
		var p: Dictionary = projects[id]
		p["variant"] = "willow" if p.get("variant") == "willow" else "stone"
		p["stage"] = clampi(int(p.get("stage", 0)), 0, steps(id).size())
		p["work"] = maxf(0.0, float(p.get("work", 0.0)))
		p["paused"] = bool(p.get("paused", false))
		for field in ["delivered", "spent", "contributors"]:
			if not p.get(field) is Dictionary: p[field] = {}
		p["blocked"] = ""
	# После загрузки незагруженные резервы выбираются заново. Груз в руках
	# остаётся в единственном поручении, даже если стройка уже закончена.
	for owner in orders.keys():
		var job: Dictionary = orders[owner] if orders[owner] is Dictionary else {}
		if not OWNERS.has(owner) or not bool(job.get("picked", false)):
			orders.erase(owner)
			continue
		job["kind"] = "haul" if job.get("kind") == "haul" else "return"
		job["count"] = maxi(0, int(job.get("count", 0)))
		job["timer"] = 0.0
		if not GOODS.has(job.get("good")) or int(job["count"]) == 0:
			orders.erase(owner)
			continue
		if not is_active(str(job.get("project", ""))): job["kind"] = "return"

func steps(id: String) -> Array:
	if id == "workshop":
		var result: Array = []
		for i in range(1, CONSTRUCTION.COSTS.size()):
			result.append({"cost":CONSTRUCTION.COSTS[i], "seconds":4.0 + i, "name":CONSTRUCTION.STAGE_NAMES[i]})
		return result
	if id == "roof": return [
		{"cost":{"wood":2,"stone":2},"seconds":8.0,"name":"Опоры крыши"},
		{"cost":{"wood":2},"seconds":8.0,"name":"Покрытие и отделка"}]
	if str(projects.get(id, {}).get("variant", "stone")) == "willow": return [
		{"cost":{"wood":2},"seconds":6.0,"name":"Опоры из ивы"},
		{"cost":{"wood":3},"seconds":7.0,"name":"Плетёный настил"},
		{"cost":{"resin":1},"seconds":5.0,"name":"Защита настила смолой"}]
	return [
		{"cost":{"stone":2},"seconds":6.0,"name":"Каменные опоры"},
		{"cost":{"wood":3},"seconds":7.0,"name":"Деревянный настил"},
		{"cost":{"stone":2},"seconds":5.0,"name":"Укрепление берегов"}]

func start(id: String, variant: String = "stone", stage: int = 0) -> bool:
	if not TITLES.has(id) or projects.has(id): return false
	projects[id] = {"variant":variant,"stage":stage,"work":0.0,"paused":false,
		"delivered":{},"spent":{},"contributors":{},"blocked":""}
	focus = id
	return true

func is_complete(id: String) -> bool:
	return projects.has(id) and int(projects[id]["stage"]) >= steps(id).size()

func is_active(id: String) -> bool:
	return projects.has(id) and not is_complete(id) and not bool(projects[id]["paused"])

func pending_cost(id: String) -> Dictionary:
	var result: Dictionary = {}
	if not projects.has(id): return result
	var recipe := steps(id)
	for i in range(int(projects[id]["stage"]), recipe.size()):
		for good in recipe[i]["cost"]:
			result[good] = int(result.get(good, 0)) + int(recipe[i]["cost"][good])
	return result

func reserved(id: String, good: String, picked_only: bool = false) -> int:
	var result := 0
	for job in orders.values():
		if job["kind"] == "haul" and job["project"] == id and job["good"] == good:
			if not picked_only or job["picked"]: result += int(job["count"])
	return result

func free_stock(good: String) -> int:
	var available := int(stock.get(good, 0))
	for job in orders.values():
		if job["kind"] == "haul" and not job["picked"] and job["good"] == good:
			available -= int(job["count"])
	return maxi(0, available)

func needed(id: String, include_reserved: bool = true) -> Dictionary:
	var result := pending_cost(id)
	if not projects.has(id): return result
	for good in result:
		result[good] = maxi(0, int(result[good]) - int(projects[id]["delivered"].get(good, 0))
			- reserved(id, good, not include_reserved))
	return result

func ready_to_build(id: String) -> bool:
	if not is_active(id): return false
	var p: Dictionary = projects[id]
	var cost: Dictionary = steps(id)[int(p["stage"])]["cost"]
	for good in cost:
		if int(p["delivered"].get(good, 0)) < int(cost[good]): return false
	return true

func _ordered_projects() -> Array[String]:
	var result: Array[String] = []
	if is_active(focus): result.append(focus)
	for id in TITLES:
		if id != focus and is_active(id): result.append(id)
	return result

func claim(owner: String) -> Dictionary:
	if orders.has(owner): return orders[owner]
	if not OWNERS.has(owner): return {}
	var ordered := _ordered_projects()
	if owner in ["bruno", "siver"]:
		for id in ordered:
			if owner == "siver" and id != "roof": continue
			if _cooling(owner, id) or not ready_to_build(id): continue
			var occupied := false
			for job in orders.values():
				if job["kind"] == "build" and job["project"] == id: occupied = true
			if occupied: continue
			orders[owner] = {"kind":"build","project":id,"good":"","count":0,"picked":false,"timer":0.0}
			return orders[owner]
	for id in ordered:
		if _cooling(owner, id): continue
		var remaining := needed(id)
		for good in remaining:
			if int(remaining[good]) == 0 or free_stock(good) == 0: continue
			orders[owner] = {"kind":"haul","project":id,"good":good,"count":1,"picked":false,"timer":0.0}
			return orders[owner]
	return {}

func _cooling(owner: String, id: String) -> bool:
	return float(_retry.get(owner + ":" + id, 0.0)) > clock

func target(owner: String) -> Vector2:
	if not orders.has(owner): return DEPOT
	var job: Dictionary = orders[owner]
	var base: Vector2 = DEPOT
	if job["kind"] == "build" or (job["kind"] == "haul" and job["picked"]):
		base = POINTS.get(job["project"], DEPOT)
	if job["kind"] == "build": return base
	var index := OWNERS.find(owner)
	return base + Vector2(float(index % 3) - 1.0, -float(index / 3)) * 0.8

func cargo(owner: String) -> Dictionary:
	var job: Dictionary = orders.get(owner, {})
	if not job.is_empty() and job["picked"]:
		return {str(job["good"]):int(job["count"])}
	return {}

func release(owner: String, blocked: bool = false) -> void:
	if not orders.has(owner): return
	var job: Dictionary = orders[owner]
	var id := str(job["project"])
	if blocked:
		_retry[owner + ":" + id] = clock + 15.0
		if projects.has(id): projects[id]["blocked"] = "Путь перекрыт. Проверь дорогу или доставь материал сам."
	if job["picked"]:
		job["kind"] = "return"
		job["timer"] = 0.0
	else:
		orders.erase(owner)

func pause(id: String) -> void:
	if not projects.has(id) or is_complete(id): return
	projects[id]["paused"] = not bool(projects[id]["paused"])
	if projects[id]["paused"]:
		for owner in orders.keys():
			if orders[owner]["project"] == id: release(owner)

func contribute(id: String, bag: Dictionary, at: Vector2) -> Dictionary:
	if not projects.has(id) or is_complete(id) or at.distance_to(POINTS[id]) > 6.0: return {}
	# Личная доставка заменяет ещё не погруженные резервы. Уже идущий груз
	# учитывается, поэтому после помощи игрока носильщику не нужен лишний рейс.
	var remaining := needed(id, false)
	var moved: Dictionary = {}
	for good in remaining:
		var amount := mini(2, mini(int(bag.get(good, 0)), int(remaining[good])))
		if amount <= 0: continue
		for owner in orders.keys():
			var job: Dictionary = orders[owner]
			if job["project"] == id and job["kind"] == "haul" and job["good"] == good and not job["picked"]:
				orders.erase(owner)
		bag[good] = int(bag[good]) - amount
		projects[id]["delivered"][good] = int(projects[id]["delivered"].get(good, 0)) + amount
		moved[good] = amount
		_count_contribution(id,"paki",amount)
	return moved

func service(owner: String, at: Vector2, seconds: float) -> Dictionary:
	if not orders.has(owner) or at.distance_to(target(owner)) > 1.15: return {}
	var job: Dictionary = orders[owner]
	var id := str(job["project"])
	if job["kind"] == "build":
		return work(id, owner, at, seconds, 1.15)
	job["timer"] = float(job["timer"]) + clampf(seconds, 0.0, 0.25)
	if float(job["timer"]) < DWELL: return {}
	job["timer"] = 0.0
	var good := str(job["good"])
	var amount := int(job["count"])
	if job["kind"] == "return":
		stock[good] = int(stock.get(good, 0)) + amount
		orders.erase(owner)
		return {"event":"returned","owner":owner,"good":good,"amount":amount}
	if not is_active(id):
		release(owner)
		return {}
	if not job["picked"]:
		if int(stock.get(good, 0)) < amount:
			orders.erase(owner)
			return {}
		stock[good] = int(stock[good]) - amount
		job["picked"] = true
		return {"event":"picked","owner":owner}
	projects[id]["delivered"][good] = int(projects[id]["delivered"].get(good, 0)) + amount
	projects[id]["blocked"] = ""
	_count_contribution(id, owner, amount)
	orders.erase(owner)
	return {"event":"delivered","owner":owner,"project":id,"good":good,"amount":amount}

func work(id: String, owner: String, at: Vector2, seconds: float, reach: float = 6.0) -> Dictionary:
	if not ready_to_build(id) or at.distance_to(POINTS[id]) > reach: return {}
	var p: Dictionary = projects[id]
	var step: Dictionary = steps(id)[int(p["stage"])]
	var dt := clampf(seconds, 0.0, 5.0 if owner == "paki" else 0.25)
	p["work"] = float(p["work"]) + dt
	if float(p["work"]) < float(step["seconds"]): return {"event":"working"}
	for good in step["cost"]:
		var amount := int(step["cost"][good])
		p["delivered"][good] = int(p["delivered"][good]) - amount
		p["spent"][good] = int(p["spent"].get(good, 0)) + amount
	p["stage"] = int(p["stage"]) + 1
	p["work"] = 0.0
	p["blocked"] = ""
	_count_contribution(id, owner, 1)
	for worker in orders.keys():
		if orders[worker]["kind"] == "build" and orders[worker]["project"] == id: orders.erase(worker)
	return {"event":"complete" if is_complete(id) else "stage","owner":owner,"project":id,
		"stage":p["stage"],"name":step["name"],"cost":step["cost"].duplicate()}

func _count_contribution(id: String, owner: String, amount: int) -> void:
	var contributions: Dictionary = projects[id]["contributors"]
	contributions[owner] = int(contributions.get(owner, 0)) + amount

func has_active_projects() -> bool:
	return not _ordered_projects().is_empty()

func label(owner: String, moving: bool = false) -> String:
	if not orders.has(owner): return "выбирает дело"
	var job: Dictionary = orders[owner]
	if job["kind"] == "return": return "возвращает груз в амбар"
	var title := str(TITLES.get(job["project"], "стройка")).to_lower()
	if job["kind"] == "build": return ("идёт к стройке: " if moving else "строит: ") + title
	return ("несёт %s: " % CARGO_NAMES.get(job["good"],"груз") + title) if job["picked"] else "идёт за материалом: " + title
