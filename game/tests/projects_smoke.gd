extends SceneTree
## Проверки сохранности ресурсов, смены поручений и миграции первой главы.
const SIM = preload("res://scripts/valley_chapter_sim.gd")
const QUEUE = preload("res://scripts/valley_projects.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func total(sim, good: String) -> int:
	var count := int(sim.stock.get(good,0)) + int(sim.data["village"].get(good,0))
	for p in sim.data["projects"].values():
		count += int(p["delivered"].get(good,0)) + int(p["spent"].get(good,0))
	for job in sim.data["work_orders"].values():
		if job["picked"] and job["good"]==good: count += int(job["count"])
	return count

func arrive(sim, owner: String) -> void:
	for i in range(6): sim.project_service(owner,sim.projects.target(owner),0.25)

func _initialize() -> void:
	var sim = SIM.new()
	sim.setup({}, {})
	sim.data["village"]["wood"]=1
	sim.data["village"]["stone"]=0
	check(sim.act("bridge","stone")["ok"],"Select a shared bridge project")
	check(sim.data["bridge"]=="","Ordering must not create a completed bridge")
	var wood := total(sim,"wood")
	var q = sim.projects
	var job: Dictionary = q.claim("grom")
	check(not job.is_empty() and q.claim("grom")==job,"One worker must keep one reservation")
	check(q.claim("iris").is_empty(),"One warehouse item must not have two carriers")
	check(sim.data["village"]["wood"]==1,"Reservation must not spend the warehouse item")
	sim.project_service("grom",Vector2(120,120),100.0)
	check(sim.data["village"]["wood"]==1,"A far-away worker must not pick up material")
	arrive(sim,"grom")
	check(sim.data["village"]["wood"]==0 and q.cargo("grom").get("wood",0)==1,"Pickup must move stock into physical cargo")
	check(total(sim,"wood")==wood,"Pickup must conserve material")
	var reload = SIM.new()
	reload.setup(JSON.parse_string(JSON.stringify(sim.snapshot())),sim.stock.duplicate(true))
	check(reload.projects.cargo("grom").get("wood",0)==1,"Reload mid-haul must preserve the only copy of cargo")
	check(total(reload,"wood")==wood,"Reload mid-haul must not mint or lose material")
	arrive(reload,"grom")
	check(reload.data["projects"]["bridge"]["delivered"].get("wood",0)==1,"Delivery must reach the chosen site")
	check(reload.projects.cargo("grom").is_empty() and total(reload,"wood")==wood,"Delivery must remove cargo exactly once")
	arrive(reload,"grom")
	check(total(reload,"wood")==wood,"A repeated delivery call must not create another item")
	check(reload.projects.work("bridge","paki",QUEUE.POINTS["bridge"],5.0).is_empty(),"Warehouse or incomplete site stock cannot substitute for a stage's materials")

	var returning = SIM.new()
	returning.setup({}, {})
	returning.act("stores","roof")
	returning.projects.claim("grom")
	arrive(returning,"grom")
	var before_pause := total(returning,"wood")
	returning.projects.pause("roof")
	check(returning.projects.orders["grom"]["kind"]=="return","Pausing a project must send loaded cargo back")
	check(returning.projects.claim("iris").is_empty(),"Paused projects must not create new work")
	arrive(returning,"grom")
	check(returning.projects.cargo("grom").is_empty() and total(returning,"wood")==before_pause,"Returning cargo must restore stock without duplication")
	check(returning.data["projects"]["roof"]["delivered"].is_empty(),"Returning cargo must not also arrive at the site")

	var help = SIM.new()
	help.setup({}, {})
	help.act("bridge","stone")
	help.projects.claim("grom")
	var warehouse_before: Dictionary = help.data["village"].duplicate()
	check(not help.act("bridge","contribute",{"position":Vector2(100,100)})["ok"],"Player cannot deliver remotely")
	help.act("bridge","contribute",{"position":QUEUE.POINTS["bridge"]})
	check(not help.projects.orders.has("grom"),"Personal delivery must release superseded unloaded reservations")
	check(help.data["village"]==warehouse_before,"Superseded reservation must not spend warehouse stock")
	check(not help.act("bridge","willow")["ok"],"Selecting a second bridge must not replace the paid project")
	help.projects.claim("bruno")
	for i in range(8): help.project_service("bruno",QUEUE.POINTS["bridge"],0.25)
	var work_before := float(help.data["projects"]["bridge"]["work"])
	check(work_before>0.0,"Builder must make progress with delivered stage materials")
	help.projects.release("bruno",true)
	check(float(help.data["projects"]["bridge"]["work"])==work_before,"Blocked or interrupted work must preserve progress")
	check(help.projects.claim("bruno").is_empty() or help.projects.orders["bruno"]["kind"]!="build","Blocked builder must not immediately reserve the same work")
	help.projects.release("bruno")
	var partial = SIM.new()
	partial.setup(JSON.parse_string(JSON.stringify(help.snapshot())),help.stock.duplicate())
	check(float(partial.data["projects"]["bridge"]["work"])==work_before,"Reload must preserve partial construction")
	partial.projects.pause("bridge")
	check(partial.projects.work("bridge","paki",QUEUE.POINTS["bridge"],5.0).is_empty(),"A paused project must not advance through player help")
	partial.projects.pause("bridge")
	var stale: Dictionary = partial.act("bridge","help",{"position":QUEUE.POINTS["bridge"],"stage":1})
	check(not stale["ok"],"Help begun for an old stage must not advance a different stage")

	var team = SIM.new()
	team.setup({}, {})
	team.data["village"]["wood"]=30
	team.data["village"]["stone"]=30
	team.act("bridge","stone")
	team.act("stores","roof")
	team.act("bridge","prioritise")
	check(team.projects.claim("grom")["project"]=="bridge","New work should follow the chosen project")
	team.act("stores","prioritise")
	check(team.projects.claim("grom")["project"]=="bridge","Changing priority must preserve a current delivery")
	check(team.projects.claim("iris")["project"]=="roof","Free workers should use the new priority")
	var totals: Dictionary = {}
	for good in QUEUE.GOODS: totals[good]=total(team,good)
	for tick in range(1800):
		for owner in ["grom","iris","siver","bruno"]:
			team.projects.claim(owner)
			team.project_service(owner,team.projects.target(owner),0.25)
		if team.projects.is_complete("roof") and team.projects.is_complete("bridge"): break
	check(team.data["roof"] and team.data["bridge"]=="stone","A real crew must finish both chosen projects")
	check(team.data["projects"]["bridge"]["contributors"].size()>=3,"Bridge must record several cooperating participants")
	for good in QUEUE.GOODS:
		check(total(team,good)==totals[good],"Construction must conserve material across stock, cargo, site and consumed materials: "+good)
	var done: Dictionary = team.snapshot()
	for owner in QUEUE.OWNERS: team.project_service(owner,QUEUE.POINTS["bridge"],5.0)
	check(team.data["projects"]==done["projects"],"Completed projects must not consume or advance again")

	var legacy = SIM.new()
	legacy.setup({"version":1,"village":{"wood":8,"stone":3},"bridge":"willow","roof":true,"habitat":73.0}, {"wood":7,"stone":2})
	var old_builder: Dictionary = {"stock":{"wood":4,"stone":2},"bag":{"wood":1,"stone":1},"stage":1,"paidStage":2,"phase":"build","timer":2.0}
	legacy.attach_builder(old_builder)
	check(legacy.data["village"]["wood"]==12 and legacy.data["village"]["stone"]==5,"Migration must merge Bruno's old stock exactly once")
	check(old_builder["bag"]=={"wood":1,"stone":1},"Migration must not lose or silently unload Bruno's carried goods")
	check(legacy.projects.is_complete("bridge") and legacy.projects.is_complete("roof"),"Migration must keep completed buildings")
	check(legacy.data["habitat"]==73.0,"A completed willow bridge must not grant habitat twice")
	check(legacy.data["projects"]["workshop"]["delivered"].get("wood")==1 and old_builder["paidStage"]==0,"Prepaid legacy work must be credited to its site exactly once")
	check(float(legacy.data["projects"]["workshop"]["work"])==4.0,"Prepaid legacy work must keep elapsed construction time")
	var legacy_bag: Dictionary = legacy.stock.duplicate(true)
	var migrated = SIM.new()
	migrated.setup(JSON.parse_string(JSON.stringify(legacy.snapshot())),legacy_bag)
	var builder_copy: Dictionary = JSON.parse_string(JSON.stringify(old_builder))
	migrated.attach_builder(builder_copy)
	check(legacy_bag==legacy.stock and migrated.data["village"]["wood"]==12,"Second load must not repeat migration or starter rewards")
	check(migrated.data["projects"]["workshop"]["delivered"].get("wood")==1,"Second load must not repeat prepaid material credit")
	old_builder["stock"]["wood"]=11
	check(legacy.data["village"]["wood"]==11,"Bruno and residents must use the same warehouse after migration")

	print("SHARED PROJECTS: %s" % ("PASS" if failures==0 else "%d FAILURES" % failures))
	quit(0 if failures==0 else 1)
