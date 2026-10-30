extends SceneTree
## Настоящая сцена, реальные маршруты и JSON-файл отдельного тестового слота.
const SAVE = preload("res://scripts/save.gd")
const PATH := "user://projects_scene_smoke.json"
var failures := 0
var scene: Node3D
var chapter: Node3D

func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func mount() -> void:
	scene=load("res://scenes/main.tscn").instantiate()
	scene.save_path=PATH
	root.add_child(scene)
	chapter=scene.chapter
	check(chapter!=null,"Desktop chapter must be active")
	chapter.close_menu()
	chapter.sim.data["tutorial"]=true
	chapter.set_process(false)
	scene.set_physics_process(false)
	for i in range(240): scene.world.update_stream(scene.player.position)

func tick() -> void:
	chapter._process(0.1)
	scene.builder_ai.tick(0.1,chapter.sim.weather()=="storm",chapter.sim.is_night())

func physical_total(good: String) -> int:
	var sim=chapter.sim
	var result:=int(sim.stock[good])+int(sim.data["village"].get(good,0))
	for a in sim.data["residents"]:
		if a["cargo"]==good: result+=int(a["cargo_count"])
	result+=int(scene.builder_ai.data["bag"].get(good,0))
	for job in sim.projects.orders.values():
		if job["picked"] and job["good"]==good: result+=int(job["count"])
	for p in sim.projects.projects.values():
		result+=int(p["delivered"].get(good,0))+int(p["spent"].get(good,0))
	return result

func run() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	mount()
	# Закрываем отложенный приветственный журнал до ручных шагов.
	await process_frame
	chapter.close_menu()
	var sim=chapter.sim
	check(sim.act("bridge","stone")["ok"],"Order the shared bridge")
	check(sim.act("stores","roof")["ok"],"Order the shared roof")
	sim.act("bridge","prioritise")
	var bag_before: Dictionary=sim.stock.duplicate()
	for i in range(100): tick()
	var old_stage:=int(sim.projects.projects["bridge"]["stage"])
	var old_work:=float(sim.projects.projects["bridge"]["work"])
	scene.builder_ai.command("follow")
	for i in range(160): tick()
	check(int(sim.projects.projects["bridge"]["stage"])==old_stage and float(sim.projects.projects["bridge"]["work"])==old_work,"Bruno must stop building while accompanying the hero")
	# Перекрываем настоящий рабочий подход. Поиск ближайшей клетки не должен
	# позволить строить с другой стороны препятствия или потерять груз.
	var barrier:=Rect2(Vector2(1,-3),Vector2(8,7))
	scene.world.chapter_obstacles.append(barrier)
	scene.world.navigation_revision+=1
	scene.builder_ai.command("work")
	var interrupted_stage:=int(sim.projects.projects["bridge"]["stage"])
	for i in range(300): tick()
	check(int(sim.projects.projects["bridge"]["stage"])==interrupted_stage,"Workers must not build through a blocked approach")
	check(str(sim.projects.projects["bridge"]["blocked"])!="","An unreachable approach must produce a visible reason")
	scene.world.chapter_obstacles.erase(barrier)
	scene.world.navigation_revision+=1
	var loaded_owner:=""
	for i in range(500):
		tick()
		for owner in sim.projects.orders:
			if sim.projects.orders[owner]["picked"]:
				loaded_owner=str(owner)
				break
		if loaded_owner!="": break
	check(loaded_owner!="","A resident must physically pick up a project load")
	var wood_before:=physical_total("wood")
	var stone_before:=physical_total("stone")
	var carried: Dictionary=sim.projects.cargo(loaded_owner)
	scene._save()
	check(FileAccess.file_exists(PATH),"Actual scene must write the isolated save slot")
	scene.queue_free()
	await process_frame
	mount()
	# Не даём отложенному приветствию или реальным кадрам менять ручную симуляцию.
	await process_frame
	chapter.close_menu()
	sim=chapter.sim
	check(physical_total("wood")==wood_before and physical_total("stone")==stone_before,"Reload must conserve warehouse, carried, delivered and consumed materials")
	check(sim.projects.cargo(loaded_owner)==carried,"The same carrier must retain the saved load")
	check(sim.stock==bag_before,"Ordering and reloading must not spend the hero's bag or reissue starter resources")
	var ticks:=0
	for i in range(5000):
		tick()
		ticks=i+1
		if sim.projects.is_complete("bridge") and sim.projects.is_complete("roof") and sim.projects.is_complete("workshop"): break
	chapter._sync_world()
	chapter._sync_builder()
	for id in ["bridge","roof","workshop"]:
		print("PROJECT %s: %s; contributors=%s" % [id,sim.project_status(id),str(sim.projects.projects[id]["contributors"])])
		check(sim.projects.is_complete(id),"Real workers did not finish "+id+" after deliveries")
	check(sim.data["bridge"]=="stone" and scene.world.bridge_open,"Only the complete bridge must open the crossing")
	check(scene.bridge_mesh.visible and chapter._stone_footings.visible and not chapter._bridge_preview.visible,"Complete bridge must replace temporary construction visuals")
	check(sim.data["roof"] and chapter._barn.current_stage==5,"Roof visuals must match the completed protection")
	check(scene.builder_ai.stage()==5 and scene.workshop.current_stage==5,"Shared queue must synchronize Bruno and the real workshop")
	check(sim.projects.projects["bridge"]["contributors"].size()>=2,"Several residents must cooperate on the real bridge")
	check(int(sim.data["ledger"]["project_delivered"])>0,"Actual arrivals must count project deliveries")
	check(sim.stock==bag_before,"Autonomous construction must use the warehouse, not silently spend the hero's bag")
	chapter.interact("bridge")
	check(chapter.menu_open,"Completed project interaction must still explain its state")
	chapter.close_menu()
	chapter._track("workshop")
	check(chapter._waypoint==sim.PROJECTS.POINTS["workshop"],"Workshop tracking must use the real project point")
	chapter._track("roof")
	check(chapter._waypoint==sim.PROJECTS.POINTS["roof"],"Roof tracking must use the real project point")
	chapter.open_journal()
	check(chapter.menu_open and chapter._content.get_child_count()>25,"Journal must include shared projects and participants")
	chapter.close_menu()
	print("PROJECTS SCENE: %.1f simulated seconds after reload" % (float(ticks)*0.1))
	scene.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	print("PROJECTS SCENE: %s" % ("PASS" if failures==0 else "%d FAILURES" % failures))
	quit(0 if failures==0 else 1)
