extends SceneTree
## Integrates the actual main scene, animated residents, navigation and UI.
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func run() -> void:
	var scene=load("res://scenes/main.tscn").instantiate()
	scene.save_path="user://chapter_scene_smoke.json"
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(scene.save_path+suffix): DirAccess.remove_absolute(scene.save_path+suffix)
	root.add_child(scene)
	await process_frame
	check(scene.chapter!=null,"Desktop chapter was not mounted")
	var chapter=scene.chapter
	chapter.close_menu()
	chapter.set_process(false)
	scene.set_physics_process(false)
	var starts:Dictionary={}
	for a in chapter.sim.data["residents"]: starts[a["id"]]=Vector2(float(a["x"]),float(a["z"]))
	# Stream the initial neighbourhood so actual tree and building obstacles exist.
	for i in range(240): scene.world.update_stream(scene.player.position)
	for i in range(1800):
		scene.builder_ai.tick(0.1,false,false)
		for definition in chapter.SIM.PEOPLE:
			var resident:Dictionary=chapter.sim.resident(definition["id"])
			chapter._tick_resident(resident,definition,0.1)
	for a in chapter.sim.data["residents"]:
		check(Vector2(float(a["x"]),float(a["z"])).distance_to(starts[a["id"]])>0.1 or int(a["delivered"])>0,"Resident never moved: "+str(a["id"]))
		print("RESIDENT %s: delivered=%d position=(%.1f, %.1f) goal=%s" % [a["id"],a["delivered"],float(a["x"]),float(a["z"]),a["goal"]])
		check(int(a["delivered"])>0,"Resident failed to deliver within three simulated minutes: "+str(a["id"]))
		var info:Dictionary=chapter._actors[a["id"]]
		check(info["anim"]!=null,"Resident lacks real animation: "+str(a["id"]))
	check(int(chapter.sim.data["ledger"]["npc_delivered"])>0,"Residents did not physically deliver any resources")
	print("BRUNO: workshop stage=%d" % scene.builder_ai.stage())
	check(scene.builder_ai.stage()>=1,"New village homes should not block Bruno's building materials")
	for lake in chapter.GEO.LAKES:
		var p:Vector2=lake["center"]
		check(not scene.world.can_walk(p.x,p.y,true),"Player could walk across a lake")
	var herbs_before:=int(chapter.sim.stock["herbs"])
	var leaf:Vector2=scene.LEAVES[0]
	scene.player.position=Vector3(leaf.x,scene.world.ground_height(leaf.x,leaf.y),leaf.y)
	scene._interact()
	scene._physics_process(2.0)
	check(int(chapter.sim.stock["herbs"])==herbs_before+1,"Existing lightleaf should supply the chapter's herb stock")
	chapter.sim.data["bridge"]="stone"
	chapter._sync_world()
	check(chapter._stone_footings.visible and not chapter._willow_vines.visible,"Stone bridge lacks its visible consequence")
	chapter.sim.data["bridge"]="willow"
	chapter._sync_world()
	check(chapter._willow_vines.visible and not chapter._stone_footings.visible,"Willow bridge lacks its visible consequence")
	chapter.open_journal()
	check(chapter.menu_open and chapter._content.get_child_count()>15,"Journal and map did not open")
	chapter.close_menu()
	check(not chapter.menu_open,"Journal did not close")
	var test_path: String=scene.save_path
	scene.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(test_path+suffix): DirAccess.remove_absolute(test_path+suffix)
	print("CHAPTER SCENE: %s" % ("PASS" if failures==0 else "%d FAILURES"%failures))
	quit(0 if failures==0 else 1)
