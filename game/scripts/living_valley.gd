extends Node3D
## Игровая глава «Свет над долиной»: жители, поручения, журнал, карта и последствия.
const SIM = preload("res://scripts/valley_chapter_sim.gd")
const GEO = preload("res://scripts/valley_geography.gd")
const FIT = preload("res://scripts/model_fitting.gd")
const MOTION = preload("res://scripts/actor_animation.gd")
const GOALS := {"choose":"выбирает дело","work":"собирает припасы","deliver":"несёт припасы в амбар","repair":"чинит крышу","plant":"высаживает цветы","shelter":"укрывается от ливня","rest":"отдыхает","social":"встречается с соседями"}
const ACTION_SECONDS := {"careful":3.5,"rush":5.0,"resin":3.0,"tea":2.0,"roof":1.0,"restore":4.0,"stone":1.0,"willow":1.0,"light":3.0,"contribute":1.5,"help":5.0}

var game: Node3D
var sim = SIM.new()
var menu_open := false
var vista_mode := false
var _actors: Dictionary = {}
var _sites: Dictionary = {}
var _root: CanvasLayer
var _panel: PanelContainer
var _content: VBoxContainer
var _status: Label
var _objective: Label
var _marker: Node3D
var _waypoint := Vector2(5,3.75)
var _view_tick := 0.0
var _visual_signature := ""
var _trees: Array[Node3D] = []
var _flowers: Array[Node3D] = []
var _quarry_plants: Array[Node3D] = []
var _meadow_life: Array[Dictionary] = []
var _barn: Node3D
var _beacon_light: OmniLight3D
var _beacon_glow: MeshInstance3D
var _arrival: Node3D
var _stone_footings: Node3D
var _willow_vines: Node3D
var _bridge_preview: MeshInstance3D
var _project_visuals: Dictionary = {}
var _builder_blocked := 0.0
var _builder_job_signature := ""
var _bridge_was_open := false
var _accumulator := 0.0
var _focus: String = "bridge"

func setup(owner_game: Node3D) -> void:
	game = owner_game
	sim.setup(game.state["world"].get("chapter",{}), game.state["world"]["bag"])
	if game.state["bridge"] and str(sim.data["bridge"]) == "":
		sim.data["bridge"] = "stone"
		if not sim.projects.projects.has("bridge"): sim.projects.start("bridge","stone",3)
	sim.attach_builder(game.builder_ai.data)
	game.builder_ai.community = self
	_bridge_was_open = str(sim.data["bridge"])!=""

func _ready() -> void:
	_make_sites()
	_make_bridge_variants()
	_make_homes()
	_make_residents()
	_make_project_visuals()
	_make_interface()
	_make_meadow_life()
	_focus=str(sim.data["tracked"])
	if _focus=="bridge" and sim.data["bridge"]!="": _focus="beacon"
	_waypoint=_target_point(_focus)
	_marker = game._glow_orb("Текущая цель",Vector3.ZERO,0.18,Color("#ffe7a5"))
	_sync_world()
	_sync_builder()
	if not sim.data["tutorial"]:
		call_deferred("open_journal")

func _process(delta: float) -> void:
	if game == null or menu_open:
		return
	delta = clampf(delta,0.0,0.25)
	var moving: bool = game._movement_vector().length_squared() > 0.01
	sim.advance(delta,moving,moving and Input.is_key_pressed(KEY_SHIFT) and can_run())
	for definition in SIM.PEOPLE:
		var a: Dictionary = sim.resident(definition["id"])
		_tick_resident(a,definition,delta)
	game.state["night"] = sim.is_night()
	game.weather_mode = "chapter"
	game.raining = sim.weather() == "storm"
	game.fauna.set_night(sim.is_night())
	game.society.set_night(sim.is_night())
	game.society.simulation.bridge_open = bool(game.state["bridge"])
	_accumulator += delta
	_view_tick += delta
	if _view_tick >= 0.25:
		_view_tick = 0.0
		_update_status()
		_sync_world()
		_sync_builder()
		if not sim.notices.is_empty():
			game._toast(sim.notices.pop_front())
	if _marker != null:
		_marker.position = Vector3(_waypoint.x,game.world.ground_height(_waypoint.x,_waypoint.y)+2.5+sin(_accumulator*2.0)*0.18,_waypoint.y)
	_animate_meadow_life(delta)

func can_run() -> bool:
	return float(sim.data["stamina"]) > 3.0

func movement_scale() -> float:
	var speed := 0.87 if sim.weather()=="storm" else 1.0
	if sim.data["bridge"] == "willow" and sim.weather()=="storm" and absf(game.player.position.x-5.0)<2.0 and game.player.position.z>3.0 and game.player.position.z<16.0:
		speed *= 0.6
	return speed

func _make_sites() -> void:
	for place in GEO.PLACES:
		var id := str(place["id"])
		var p: Vector2 = place["pos"]
		var root := Node3D.new()
		root.name = str(place["name"])
		root.position = Vector3(p.x,game.world.ground_height(p.x,p.y),p.y)
		add_child(root)
		_sites[id] = root
		var signpost := _prop("path-stone",root,Vector3.ZERO,0.35)
		signpost.name = "Площадка взаимодействия"
		var label := Label3D.new()
		label.text = str(place["name"])
		label.position.y = 3.2
		label.font_size = 36
		label.pixel_size = 0.015
		label.modulate = Color("#ffefca")
		label.outline_size = 6
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.visibility_range_end = 40.0
		root.add_child(label)
		if id in ["board","stores","craft"]:
			_prop("lantern-glass",root,Vector3(1.5,0,0),1.6)
		if id == "craft":
			_prop("pot-large",root,Vector3(-1.0,0,0),1.3)
		if id == "stores":
			_prop("log-stack",root,Vector3(2.4,0,2.5),1.8)
			_barn=load("res://scripts/construction.gd").new()
			_barn.appearance = "barn"
			_barn.name="Общий амбар · модульная постройка"
			_barn.position=Vector3(0,0,4)
			_barn.rotation.y=PI
			_barn.scale=Vector3.ONE*0.8
			root.add_child(_barn)
			_barn.set_stage(5)
			game.world.chapter_obstacles.append(Rect2(p+Vector2(-2.7,1.5),Vector2(5.4,5.0)))
		if id == "quarry":
			for i in range(12):
				var potted := _prop("plant-bushdetailed",root,Vector3(4+cos(i)*3,0,3+sin(i)*3),0.75)
				_quarry_plants.append(potted)
		if id == "meadow":
			for i in range(46):
				var p2 := Vector2(cos(float(i)*2.4),sin(float(i)*2.4))*(1.2+sqrt(float(i))*0.8)
				var flower := _prop("flower-purpleb" if i%2==0 else "flower-yellowa",root,Vector3(p2.x,0,p2.y),0.7)
				_flowers.append(flower)
		if id == "beacon":
			_prop("rock-talla",root,Vector3(1.4,0,1.0),4.0)
			_prop("campfire-logs",root,Vector3(0,0,0),1.1)
			_beacon_glow = game._glow_orb("Огонь маяка",Vector3(p.x,root.position.y+2.3,p.y),0.75,Color("#ffb464"))
			_beacon_light = OmniLight3D.new()
			_beacon_light.position.y = 3.0
			_beacon_light.light_color = Color("#ffd38a")
			_beacon_light.omni_range = 18.0
			_beacon_light.light_energy = 2.0
			root.add_child(_beacon_light)
			_arrival = Node3D.new()
			_arrival.name = "Прибывший караван"
			add_child(_arrival)
			_arrival.position = Vector3(15,game.world.ground_height(15,43),43)
			_prop("tent-smallopen",_arrival,Vector3(6,0,4),3.5)
			_prop("log-stack",_arrival,Vector3(3,0,1),1.4)
			_prop("lantern-glass",_arrival,Vector3(2,0,2),1.5)

func _prop(id: String, owner_node: Node3D, offset: Vector3, height: float) -> Node3D:
	var prop: Node3D = game._model(id,height,Color("#bdb08d"))
	owner_node.add_child(prop)
	prop.position = offset
	prop.position.y += game.world.ground_height(owner_node.position.x+offset.x,owner_node.position.z+offset.z)-owner_node.position.y
	return prop

func _make_bridge_variants() -> void:
	_stone_footings=Node3D.new()
	_stone_footings.name="Каменные опоры переправы"
	add_child(_stone_footings)
	_willow_vines=Node3D.new()
	_willow_vines.name="Живые побеги ивовой переправы"
	add_child(_willow_vines)
	for side in [-1.0,1.0]:
		for i in range(4):
			var p:=Vector3(5.0+side*1.55,0,4.5+float(i)*3.1)
			_prop("rock-largea",_stone_footings,p,2.0)
			p.y=2.8
			_prop("plant-bushlarge",_willow_vines,p,1.0)
	_bridge_preview = game.bridge_mesh.duplicate() as MeshInstance3D
	_bridge_preview.name = "Незаконченный настил переправы"
	_bridge_preview.scale.z *= 0.5
	_bridge_preview.position.z -= 3.0
	add_child(_bridge_preview)

func _make_project_visuals() -> void:
	for id in sim.PROJECTS.TITLES:
		var point: Vector2 = sim.PROJECTS.POINTS[id]
		var root := Node3D.new()
		root.name = "Стройплощадка · " + str(sim.PROJECTS.TITLES[id])
		root.position = Vector3(point.x,game.world.ground_height(point.x,point.y),point.y)
		add_child(root)
		var label := Label3D.new()
		label.position = Vector3(0,3.4,0)
		label.font_size = 26
		label.pixel_size = 0.01
		label.outline_size = 7
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visibility_range_end = 28.0
		root.add_child(label)
		var materials: Dictionary = {}
		for entry in [["wood","log-stack",Vector3(2,0,-2)], ["stone","rock-largea",Vector3(3.4,0,-2)], ["resin","pot-large",Vector3(4.5,0,-2)]]:
			materials[entry[0]] = _prop(entry[1],root,entry[2],0.8)
		_project_visuals[id] = {"root":root,"label":label,"materials":materials}

func release_worker(owner: String) -> void:
	sim.projects.release(owner)
	if owner=="bruno":
		_builder_job_signature=""
		_builder_blocked=0.0
		game.builder_ai._reset_job()

func drive_builder(builder: Node3D, dt: float, rain: bool, night: bool) -> bool:
	if builder.data["mode"]=="follow" or rain or night:
		release_worker("bruno")
		builder.community_cargo=1 if not sim.projects.cargo("bruno").is_empty() else 0
		return false
	# Груз из прежнего сохранения сначала доходит до общего амбара.
	var old_bag: Dictionary = builder.data["bag"]
	if int(old_bag["wood"])+int(old_bag["stone"])>0:
		builder.data["phase"]="move"
		if builder._move_to(sim.PROJECTS.DEPOT,dt,2.0):
			for good in ["wood","stone"]:
				sim.data["village"][good]=int(sim.data["village"][good])+int(old_bag[good])
				sim.data["ledger"]["npc_delivered"]=int(sim.data["ledger"]["npc_delivered"])+int(old_bag[good])
				old_bag[good]=0
			builder._reset_job()
			builder._notify("Груз доставлен в общий амбар.")
		return true
	var job: Dictionary = sim.projects.claim("bruno")
	builder.community_cargo=1 if not sim.projects.cargo("bruno").is_empty() else 0
	if job.is_empty():
		_builder_job_signature=""
		var unfinished := false
		for id in sim.projects.projects:
			if not sim.projects.is_complete(id): unfinished=true
		if not unfinished:
			# Когда стройки закончены, остаются прежние посадка, полив и отдых.
			return false
		builder.data["phase"]="decide"
		builder.data["target"]={}
		builder._move_to(builder.SHELTER,dt,2.2)
		return true
	var signature := "%s:%s:%s" % [job["kind"],job["project"],job["picked"]]
	if signature!=_builder_job_signature:
		_builder_job_signature=signature
		_builder_blocked=0.0
		builder._nav.clear()
		builder._repath_after=0.0
	var target: Vector2 = sim.projects.target("bruno")
	var at := Vector2(builder.position.x,builder.position.z)
	if at.distance_to(target)<=1.1:
		builder.data["phase"]="build" if job["kind"]=="build" else "deposit"
		if _clear_work_line(at,target):
			sim.project_service("bruno",at,dt)
			_sync_builder()
			_builder_blocked=0.0
		else:
			_builder_blocked+=dt
			if _builder_blocked>3.0:
				sim.projects.release("bruno",true)
				_builder_blocked=0.0
	else:
		builder.data["phase"]="move"
		builder._move_to(target,dt,2.0 if builder.community_cargo>0 else 2.5)
		var now := Vector2(builder.position.x,builder.position.z)
		_builder_blocked = _builder_blocked+dt if now.distance_to(at)<0.001 else 0.0
		if _builder_blocked>10.0:
			sim.projects.release("bruno",true)
			_builder_job_signature=""
			_builder_blocked=0.0
	return true

func builder_status(builder: Node3D) -> String:
	if sim.projects.orders.has("bruno"): return sim.projects.label("bruno",builder._walking)
	if int(builder.data["bag"]["wood"])+int(builder.data["bag"]["stone"])>0: return "Несёт прежний груз в общий амбар"
	if sim.projects.has_active_projects(): return "Ждёт материалы · подробности в журнале"
	for id in sim.projects.projects:
		if not sim.projects.is_complete(id): return "Стройки приостановлены · можно продолжить у площадки"
	return str(builder.LABELS.get(str(builder.data["phase"]),"Осматривает поселение"))

func _sync_builder() -> void:
	if not sim.projects.projects.has("workshop"): return
	var p: Dictionary = sim.projects.projects["workshop"]
	var builder: Node3D = game.builder_ai
	var accounted: Dictionary = p.get("accounted_spent",{})
	var legacy_stage := int(p.get("legacy_paid_stage",0))
	for good in ["wood","stone"]:
		var total := int(p["spent"].get(good,0))
		var amount := total-int(accounted.get(good,0))
		if legacy_stage>0 and int(p["stage"])>=legacy_stage:
			amount-=int(sim.projects.steps("workshop")[legacy_stage-1]["cost"].get(good,0))
		builder.data["spent"][good]=int(builder.data["spent"][good])+maxi(0,amount)
		accounted[good]=total
	p["accounted_spent"]=accounted
	if legacy_stage>0 and int(p["stage"])>=legacy_stage: p["legacy_paid_stage"]=0
	if int(builder.data["stage"])!=int(p["stage"]):
		builder.data["stage"]=int(p["stage"])
		builder.data["phase"]="decide"
		builder.data["target"]={}
		game.workshop.set_stage(int(p["stage"]),true)
		game.world.set_workshop_stage(int(p["stage"]))
		builder._notify("Общими силами завершён этап: " + game.workshop.stage_name(int(p["stage"])))

func _make_meadow_life() -> void:
	for kind in ["Swallowtail","HawkMoth"]:
		var path := "res://library/prepared/gobkit/insect/%s.glb" % kind
		if not ResourceLoader.exists(path): continue
		var packed := load(path) as PackedScene
		if packed==null: continue
		for i in range(4):
			var actor := Node3D.new()
			actor.name="Бабочка цветущего луга · "+kind
			var imported := packed.instantiate() as Node3D
			actor.add_child(FIT.wrap_to_height(imported,0.45))
			add_child(actor)
			var anim: AnimationPlayer=game._animation_player(actor)
			if anim!=null:
				for clip in anim.get_animation_list():
					if str(clip).to_lower().ends_with("fly"):
						anim.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
						anim.play(clip)
			_meadow_life.append({"node":actor,"anim":anim,"night":kind=="HawkMoth","phase":float(i)*1.7})

func _animate_meadow_life(delta: float) -> void:
	var meadow:Vector2=GEO.point("meadow")
	var active:bool=sim.data["meadow"] and float(sim.data["habitat"])>=50.0 and int(sim.data["last_storm"])>=0 and sim.weather()!="storm"
	var nearby:bool=Vector2(game.player.position.x,game.player.position.z).distance_squared_to(meadow)<65.0*65.0
	for entry in _meadow_life:
		var actor:Node3D=entry["node"]
		actor.visible=active and nearby and bool(entry["night"])==sim.is_night()
		var anim:AnimationPlayer=entry["anim"]
		if anim!=null: anim.active=actor.visible
		if not actor.visible: continue
		var t:=_accumulator*0.55+float(entry["phase"])
		var point:=meadow+Vector2(sin(t*1.2)*4.6,cos(t)*3.7)
		var motion:=point-Vector2(actor.position.x,actor.position.z)
		actor.rotation.y=lerp_angle(actor.rotation.y,atan2(motion.x,motion.y),minf(1.0,delta*6.0))
		actor.position=Vector3(point.x,game.world.ground_height(point.x,point.y)+1.7+sin(t*2.5)*0.45,point.y)

func _make_homes() -> void:
	for home_index in range(SIM.PEOPLE.size()):
		var definition: Dictionary = SIM.PEOPLE[home_index]
		var p: Vector2 = definition["home"] + Vector2(0,2.9)
		var home = load("res://scripts/construction.gd").new()
		home.appearance = "cottage"
		home.variant = home_index
		home.name = "Дом: " + str(definition["name"])
		home.position = Vector3(p.x,game.world.ground_height(p.x,p.y),p.y)
		home.scale = Vector3.ONE*0.9
		home.rotation.y=PI
		add_child(home)
		home.set_stage(5)
		game.world.chapter_obstacles.append(Rect2(p-Vector2(3.05,2.6),Vector2(6.1,5.2)))
	game.world.navigation_revision += 1

func _make_residents() -> void:
	for definition in SIM.PEOPLE:
		var a: Dictionary = sim.resident(definition["id"])
		var pivot := Node3D.new()
		pivot.name = "%s · %s" % [definition["name"],definition["role"]]
		add_child(pivot)
		var visual: Node3D = game._model("bruno-builder",2.15,definition["color"])
		pivot.add_child(visual)
		_tint_clothes(visual,definition["color"])
		var anim: AnimationPlayer = game._animation_player(visual)
		if anim != null: MOTION.lock_horizontal_motion(anim,false)
		var label := Label3D.new()
		label.text = str(definition["name"])
		label.font_size = 32
		label.pixel_size = 0.009
		label.position.y = 2.8
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.visibility_range_end = 32.0
		pivot.add_child(label)
		var cargo := Node3D.new()
		var cargo_props: Dictionary = {}
		for item in [["wood","log-stack"],["stone","rock-largea"],["herbs","plant-bushdetailed"],["food","crop-carrot"],["resin","pot-large"],["seeds","pot-large"]]:
			var prop: Node3D = game._model(item[1],0.55,Color("#b7885a"))
			cargo.add_child(prop)
			prop.visible=false
			cargo_props[item[0]]=prop
		cargo.position = Vector3(0,1.1,-0.7)
		pivot.add_child(cargo)
		pivot.position = Vector3(float(a["x"]),game.world.ground_height(float(a["x"]),float(a["z"])),float(a["z"]))
		_actors[a["id"]] = {"node":pivot,"visual":visual,"anim":anim,"label":label,"cargo":cargo,"cargo_props":cargo_props,"path":PackedVector2Array(),"retry":0.0,"clip":"","blocked":0.0}

func _tint_clothes(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var original: Material = mesh_node.get_active_material(surface)
				if original is StandardMaterial3D:
					var material := original.duplicate() as StandardMaterial3D
					material.albedo_color = material.albedo_color.lerp(tint,0.22)
					mesh_node.set_surface_override_material(surface,material)
	for child in node.get_children(): _tint_clothes(child,tint)

func _tick_resident(a: Dictionary, definition: Dictionary, delta: float) -> void:
	delta=clampf(delta,0.0,0.25)
	var info: Dictionary = _actors[a["id"]]
	var node: Node3D = info["node"]
	var pos := Vector2(float(a["x"]),float(a["z"]))
	if not game.world.can_walk(pos.x,pos.y,bool(game.state["bridge"])):
		pos=_safe_point(pos)
		info["path"]=PackedVector2Array()
	a["hunger"] = minf(100.0,float(a["hunger"])+delta*0.075)
	a["energy"] = maxf(0.0,float(a["energy"])-delta*0.035)
	if a["goal"]=="project" and not sim.projects.orders.has(a["id"]): a["goal"]="choose"
	var preferred: String = sim.choose_goal(a,definition)
	if a["goal"]=="choose" or (preferred in ["rest","shelter"] and a["goal"]!=preferred):
		if preferred in ["rest","shelter"]: sim.projects.release(str(a["id"]))
		a["goal"] = preferred
		a["working"] = 0.0
		info["path"] = PackedVector2Array()
		info["retry"] = 0.0
	var target: Vector2 = sim.goal_point(a,definition)
	if a["goal"]!="project": target = _safe_point(target)
	if target.distance_to(info.get("target",Vector2(INF,INF)))>0.1:
		info["path"]=PackedVector2Array()
		info["retry"]=0.0
		info["target"]=target
	var travelled := 0.0
	if pos.distance_to(target)>1.1:
		info["retry"] = maxf(0.0,float(info["retry"])-delta)
		var path: PackedVector2Array = info["path"]
		if path.is_empty() and float(info["retry"])<=0.0:
			path = _find_path(pos,target)
			info["retry"] = 3.0
		var next := target if path.is_empty() else path[0]
		if pos.distance_to(next)<0.45 and not path.is_empty():
			path.remove_at(0)
			next = target if path.is_empty() else path[0]
		var speed := 2.1 if a["goal"]=="shelter" else 1.65
		var candidate := pos.move_toward(next,speed*delta)
		if _walkable(candidate):
			travelled = pos.distance_to(candidate)
			pos = candidate
		else:
			if float(info["blocked"])>0.7:
				path.clear()
				info["retry"] = maxf(float(info["retry"]),1.0)
		info["blocked"] = float(info["blocked"])+delta if travelled<0.0001 else 0.0
		if a["goal"]=="project" and float(info["blocked"])>10.0:
			sim.projects.release(str(a["id"]),true)
			a["goal"]="choose"
			path.clear()
			info["blocked"]=0.0
		info["path"] = path
		a["working"] = 0.0
	elif a["goal"]=="project":
		if _clear_work_line(pos,target):
			sim.project_service(str(a["id"]),pos,delta)
			_sync_builder()
			info["blocked"]=0.0
		else:
			info["blocked"]=float(info["blocked"])+delta
			if float(info["blocked"])>3.0:
				sim.projects.release(str(a["id"]),true)
				a["goal"]="choose"
				info["blocked"]=0.0
		if not sim.projects.orders.has(a["id"]): a["goal"]="choose"
	else:
		# Resources appear only after the resident physically reaches the job.
		a["working"] = float(a["working"])+delta
		var needed := 14.0 if a["goal"] in ["work","repair","plant"] else 5.0
		if float(a["working"])>=needed:
			sim.finish_job(a,definition)
			a["working"] = 0.0
			a["goal"] = "choose"
			info["path"] = PackedVector2Array()
	a["x"] = pos.x
	a["z"] = pos.y
	var old := node.position
	node.position = Vector3(pos.x,game.world.ground_height(pos.x,pos.y),pos.y)
	var displacement := node.position-old
	if travelled>0.0001:
		node.rotation.y = lerp_angle(node.rotation.y,atan2(-displacement.x,-displacement.z),minf(delta*10.0,1.0))
	var close := node.position.distance_squared_to(game.player.position)<70.0*70.0
	node.visible = close
	var carrying: bool = int(a["cargo_count"])>0 or not sim.projects.cargo(str(a["id"])).is_empty()
	(info["cargo"] as Node3D).visible = carrying
	var cargo_good := str(a["cargo"]) if int(a["cargo_count"])>0 else ""
	var project_cargo: Dictionary = sim.projects.cargo(str(a["id"]))
	if not project_cargo.is_empty(): cargo_good=str(project_cargo.keys()[0])
	for good in info["cargo_props"]: (info["cargo_props"][good] as Node3D).visible=good==cargo_good
	if close:
		var action := "HoldingWalk" if carrying else "Walk"
		if travelled<0.0001:
			action = "HoldingIdle" if carrying else "Plant" if a["goal"]=="plant" else "Gather" if a["goal"]=="work" else "Idle"
			if a["goal"]=="project" and sim.projects.orders.get(a["id"],{}).get("kind")=="build": action="Woodcut"
		_play(info,action)
		var moving_goals:Dictionary={"work":"идёт за припасами","deliver":"несёт груз в амбар","repair":"идёт чинить крышу","plant":"идёт сажать цветы","rest":"идёт домой","shelter":"спешит под крышу","social":"идёт на площадь"}
		var activity: String = moving_goals.get(a["goal"],"идёт по тропе") if travelled>0.0001 else str(GOALS.get(a["goal"],"осматривается"))
		if a["goal"]=="project": activity=sim.projects.label(str(a["id"]),travelled>0.0001)
		(info["label"] as Label3D).text = "%s\n%s" % [definition["name"],activity]
	elif info["anim"] != null:
		(info["anim"] as AnimationPlayer).stop()
		info["clip"] = ""

func _clear_work_line(from: Vector2, to: Vector2) -> bool:
	var count := maxi(1,ceili(from.distance_to(to)/0.35))
	for i in range(count+1):
		var point := from.lerp(to,float(i)/float(count))
		if not game.world.can_walk(point.x,point.y,bool(game.state["bridge"])): return false
	return true

func _play(info: Dictionary, action: String) -> void:
	var anim: AnimationPlayer = info["anim"]
	if anim == null: return
	var clip := &""
	for name in anim.get_animation_list():
		if str(name).ends_with("Bruno_"+action): clip=name
	if clip == &"": return
	if str(info["clip"])==str(clip) and anim.is_playing(): return
	info["clip"] = str(clip)
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play(clip,0.18)

func _walkable(p: Vector2) -> bool:
	if p.distance_squared_to(Vector2(game.player.position.x,game.player.position.z))<0.9*0.9: return false
	return game.world.can_walk(p.x,p.y,bool(game.state["bridge"]))

func blocks_player(p: Vector2) -> bool:
	for a in sim.data["residents"]:
		if p.distance_squared_to(Vector2(float(a["x"]),float(a["z"])))<0.72*0.72: return true
	return false

func _safe_point(point: Vector2) -> Vector2:
	if _walkable(point): return point
	for r in [1.5,2.5,4.0]:
		for i in range(12):
			var p: Vector2 = point+Vector2(cos(float(i)*TAU/12.0),sin(float(i)*TAU/12.0))*r
			if _walkable(p): return p
	return point

func _find_path(start: Vector2, finish: Vector2) -> PackedVector2Array:
	var grid := AStarGrid2D.new()
	var a := Vector2i((start/1.5).round())
	var b := Vector2i((finish/1.5).round())
	var lo := Vector2i(mini(a.x,b.x)-7,mini(a.y,b.y)-7)
	var hi := Vector2i(maxi(a.x,b.x)+8,maxi(a.y,b.y)+8)
	if (hi.x-lo.x)*(hi.y-lo.y)>12000:
		return PackedVector2Array()
	grid.region = Rect2i(lo,hi-lo)
	grid.cell_size = Vector2(1.5,1.5)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for z in range(lo.y,hi.y):
		for x in range(lo.x,hi.x):
			grid.set_point_solid(Vector2i(x,z),not _walkable(Vector2(x,z)*1.5))
	grid.set_point_solid(a,false)
	# Do not clear a blocked end cell: that would invite walking through walls.
	if grid.is_point_solid(b):
		var best:=INF
		var replacement:=b
		for dz in range(-2,3):
			for dx in range(-2,3):
				var cell:=b+Vector2i(dx,dz)
				if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell): continue
				var distance:float=(Vector2(cell)*1.5).distance_squared_to(finish)
				if distance<best:
					best=distance
					replacement=cell
		if best==INF: return PackedVector2Array()
		b=replacement
	var points := grid.get_point_path(a,b)
	if not points.is_empty(): points.remove_at(0)
	return points

func nearest(point: Vector2, maximum: float) -> Dictionary:
	var best := {}
	var distance := maximum
	for place in GEO.PLACES:
		var d: float = point.distance_to(place["pos"])
		if d<distance:
			distance=d
			best={"kind":"chapter_site","id":place["id"],"name":place["name"]}
	for definition in SIM.PEOPLE:
		var a: Dictionary = sim.resident(definition["id"])
		var d := point.distance_to(Vector2(float(a["x"]),float(a["z"])))
		if d<distance:
			distance=d
			best={"kind":"resident","id":a["id"],"name":definition["name"]}
	return best

func interact(site: String, person: bool = false) -> void:
	_open_panel()
	if person:
		var resident: Dictionary = sim.resident(site)
		_title(str(_actors[site]["node"].name))
		_paragraph(sim.talk(site))
		_paragraph("Доверие: %d/100 · сил: %d/100 · доставлено припасов: %d" % [int(resident["friendship"]),int(resident["energy"]),int(resident["delivered"])])
		_button("Угостить · 1 порция еды · доверие +5",func() -> void:
			game._toast(sim.talk(site,true))
			close_menu()
			game._save())
		_nearby_project_buttons()
	else:
		var name := "Переправа через Лубью" if site=="bridge" else "Бруно и общая мастерская" if site=="workshop" else site
		for place in GEO.PLACES:
			if place["id"]==site: name=place["name"]
		_title(name)
		_paragraph(_forecast())
		_paragraph("В сумке: "+sim.inventory_text(sim.stock),16)
		var project_id: String = sim.project_id(site)
		if sim.projects.projects.has(project_id): _paragraph(sim.project_status(project_id),18)
		if site in ["board","stores","workshop","bridge"]:
			var warehouse: Dictionary = sim.data["village"]
			_paragraph("Общий амбар: %d веток · %d камней. Материалы в руках носильщиков и на площадках считаются отдельно." % [warehouse["wood"],warehouse["stone"]],16)
		for offer in sim.options(site):
			var label: String = offer["title"]
			if not (offer["cost"] as Dictionary).is_empty(): label += " · "+sim.price_text(offer["cost"])
			var option_id := str(offer["id"])
			var button:=_button(label,func() -> void: _choose(site,option_id))
			button.disabled=not sim.can_pay(offer["cost"]) or not bool(offer.get("enabled",true))
			_paragraph(str(offer["effect"]),16)
		if site=="board":
			_paragraph("Общие проекты",22)
			_paragraph("Выбери, какую стройку обеспечивать первой. Начатые переносы жители закончат.",16)
			_project_cards()
	_button("Вернуться в долину · Esc",close_menu)

func interact_builder() -> void:
	var job: Dictionary = sim.projects.orders.get("bruno",{})
	var id := str(job.get("project",""))
	var at := Vector2(game.player.position.x,game.player.position.z)
	if id in ["bridge","roof"] and at.distance_to(sim.PROJECTS.POINTS[id])<=6.0:
		interact("stores" if id=="roof" else id)
		_button("Позвать Бруно с собой",func() -> void: _choose("workshop","follow"))
		_button("Вернуть Бруно к работе",func() -> void: _choose("workshop","resume"))
	else:
		interact("workshop")
		_nearby_project_buttons("workshop")

func _nearby_project_buttons(exclude: String = "") -> void:
	var at := Vector2(game.player.position.x,game.player.position.z)
	for project_id in sim.PROJECTS.POINTS:
		var id: String = project_id
		if id==exclude: continue
		if at.distance_to(sim.PROJECTS.POINTS[id])>6.0 or not sim.projects.projects.has(id): continue
		var site := "stores" if id=="roof" else id
		_button("Открыть площадку · "+str(sim.PROJECTS.TITLES[id]),func() -> void: interact(site))

func _choose(site: String, option: String) -> void:
	if site=="workshop" and option in ["follow","resume"]:
		close_menu()
		game.builder_ai.command("follow" if option=="follow" else "work")
		game._save()
		return
	var project_id: String = sim.project_id(site)
	var expected_stage := int(sim.projects.projects.get(project_id,{}).get("stage",-1))
	close_menu()
	game._do_action("Паки: "+option_name(site,option),func() -> void:
		var point := Vector2(game.player.position.x,game.player.position.z)
		if option in ["contribute","help"] and not _clear_work_line(point,sim.PROJECTS.POINTS[project_id]):
			game._toast("Между Паки и площадкой препятствие. Подойди со стороны тропы.")
			return
		var result: Dictionary = sim.act(site,option,{"position":point,"stage":expected_stage})
		game._toast(str(result["message"]))
		_sync_world()
		_sync_builder()
		if result["ok"] and game.audio!=null: game.audio.play_cue("build" if option in ["roof","restore","stone","willow","light"] else "pickup")
		game._save(),float(ACTION_SECONDS.get(option,1.2)))

func option_name(site: String, id: String) -> String:
	for offer in sim.options(site):
		if offer["id"]==id: return str(offer["title"])
	return "действие"

func _sync_world() -> void:
	_sync_project_visuals()
	if sim.data["bridge"]!="" and not _bridge_was_open:
		_bridge_was_open=true
		if _focus=="bridge": _track("beacon",false)
	game.state["bridge"] = str(sim.data["bridge"])!=""
	game.bridge_mesh.visible = bool(game.state["bridge"])
	game.bridge_details.visible = bool(game.state["bridge"])
	game.world.bridge_open = bool(game.state["bridge"])
	var bridge_project: Dictionary = sim.projects.projects.get("bridge",{})
	var bridge_stage := int(bridge_project.get("stage",0))
	var roof_stage := int(sim.projects.projects.get("roof",{}).get("stage",0))
	var bridge_variant := str(bridge_project.get("variant",sim.data["bridge"]))
	var signature := "%s:%s:%s:%s:%d:%s:%d:%d" % [sim.data["bridge"],sim.data["roof"],sim.data["meadow"],sim.data["beacon"],int(float(sim.data["habitat"])/10.0),sim.data["finished"],bridge_stage,roof_stage]
	if signature==_visual_signature: return
	_visual_signature=signature
	_stone_footings.visible=bridge_variant=="stone" and (bridge_stage>=1 or sim.data["bridge"]!="")
	_willow_vines.visible=bridge_variant=="willow" and (bridge_stage>=1 or sim.data["bridge"]!="")
	_bridge_preview.visible=bridge_stage==2 and sim.data["bridge"]==""
	var bridge_material:StandardMaterial3D=game.bridge_mesh.material_override.duplicate()
	bridge_material.albedo_color=Color("#94998b") if sim.data["bridge"]=="stone" else Color("#9b9670")
	game.bridge_mesh.material_override=bridge_material
	if _barn!=null: _barn.set_stage(5 if sim.data["roof"] else 3+roof_stage)
	if _beacon_light!=null: _beacon_light.visible=bool(sim.data["beacon"])
	if _beacon_glow!=null: _beacon_glow.visible=bool(sim.data["beacon"])
	if _arrival!=null: _arrival.visible=bool(sim.data["finished"])
	for i in range(_flowers.size()):
		_flowers[i].visible=i<(44 if sim.data["meadow"] else int(float(sim.data["habitat"])*0.18))
	for i in range(_quarry_plants.size()):
		_quarry_plants[i].visible=i<int(float(sim.data["habitat"])/8.0)

func _sync_project_visuals() -> void:
	for id in _project_visuals:
		var entry: Dictionary = _project_visuals[id]
		var exists: bool = sim.projects.projects.has(id)
		(entry["root"] as Node3D).visible=exists and not sim.projects.is_complete(id)
		if not exists: continue
		var p: Dictionary = sim.projects.projects[id]
		(entry["label"] as Label3D).text="%s · этап %d/%d\n%s" % [sim.PROJECTS.TITLES[id],mini(int(p["stage"])+1,sim.projects.steps(id).size()),sim.projects.steps(id).size(),"Работа приостановлена" if p["paused"] else "Материалы на месте" if sim.projects.ready_to_build(id) else "Ждём доставку"]
		for good in entry["materials"]:
			(entry["materials"][good] as Node3D).visible=int(p["delivered"].get(good,0))>0

func _project_cards() -> void:
	for project_id in sim.PROJECTS.TITLES:
		if not sim.projects.projects.has(project_id): continue
		var id: String = project_id
		_paragraph(str(sim.PROJECTS.TITLES[id])+" · "+sim.project_status(id),17)
		var contributions: PackedStringArray = []
		for owner in sim.projects.projects[id]["contributors"]:
			contributions.append(_resident_name(str(owner)))
		if not contributions.is_empty(): _paragraph("Помогали: "+", ".join(contributions)+".",16)
		_button("Показать путь · "+str(sim.PROJECTS.TITLES[id]),func() -> void: _track(id))
		if not sim.projects.is_complete(id):
			_button("Сначала этот проект" + (" · выбран" if sim.projects.focus==id else ""),func() -> void: _choose("stores" if id=="roof" else id,"prioritise"))

func _make_interface() -> void:
	_root=CanvasLayer.new()
	_root.layer=10
	add_child(_root)
	_status=Label.new()
	_status.position=Vector2(18,158)
	_status.add_theme_font_size_override("font_size",16)
	_status.add_theme_color_override("font_shadow_color",Color("#12292b"))
	_status.add_theme_constant_override("shadow_outline_size",5)
	_status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)
	_objective=Label.new()
	_objective.position=Vector2(18,185)
	_objective.add_theme_font_size_override("font_size",17)
	_objective.add_theme_color_override("font_color",Color("#ffe6aa"))
	_objective.add_theme_constant_override("outline_size",5)
	_objective.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_root.add_child(_objective)
	var journal=Button.new()
	journal.text="Журнал и карта · J / M"
	journal.position=Vector2(18,215)
	journal.pressed.connect(open_journal)
	_root.add_child(journal)
	_panel=PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left=140
	_panel.offset_right=-140
	_panel.offset_top=28
	_panel.offset_bottom=-28
	var style=StyleBoxFlat.new()
	style.bg_color=Color("#142d33")
	style.border_color=Color("#8d9775")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left=28
	style.content_margin_right=28
	style.content_margin_top=20
	style.content_margin_bottom=20
	_panel.add_theme_stylebox_override("panel",style)
	_root.add_child(_panel)
	var scroll=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_content=VBoxContainer.new()
	_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation",10)
	scroll.add_child(_content)
	_panel.hide()

func _open_panel() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	menu_open=true
	game.society.process_mode=Node.PROCESS_MODE_DISABLED
	game.fauna.process_mode=Node.PROCESS_MODE_DISABLED
	_panel.show()
	game._animate(false,false)
	for info in _actors.values(): _play(info,"Idle")

func close_menu() -> void:
	menu_open=false
	game.society.process_mode=Node.PROCESS_MODE_INHERIT
	game.fauna.process_mode=Node.PROCESS_MODE_INHERIT
	_panel.hide()

func _title(text: String) -> void:
	_paragraph(text,27)

func _paragraph(text: String, size: int = 19) -> void:
	var label=Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_content.add_child(label)

func _button(text: String, callback: Callable) -> Button:
	var button=Button.new()
	button.text=text
	button.custom_minimum_size.y=39
	button.pressed.connect(callback)
	_content.add_child(button)
	return button

func _forecast() -> String:
	if sim.weather()=="storm": return "Идёт ливень. Жители ищут укрытие; дождь поливает растения."
	if sim.weather()=="mist": return "После ливня над долиной туман. Самое время подать сигнал с маяка."
	var remaining := maxf(0.0,SIM.STORM_BEGIN-sim.phase_time())
	if sim.phase_time()>SIM.STORM_END: remaining=SIM.DAY_SECONDS-sim.phase_time()+SIM.STORM_BEGIN
	return "До следующего ливня: %d мин %02d с. Проверь крышу амбара и выбери приоритет жителей." % [int(remaining)/60,int(remaining)%60]

func _update_status() -> void:
	var names := {"clear":"ясно","overcast":"собираются тучи","storm":"ливень","mist":"туман над долиной"}
	_status.text="День %d · %02d:%02d · %s · силы %d · луг %d/100" % [sim.day()+1,int(sim.hour()),int(fposmod(sim.hour(),1.0)*60.0),names[sim.weather()],int(sim.data["stamina"]),int(sim.data["habitat"])]
	var p := Vector2(game.player.position.x,game.player.position.z)
	var direction:=(_waypoint-p).rotated(-game.yaw)
	var arrows: Array[String]=["→","↗","↑","↖","←","↙","↓","↘"]
	var arrow:=arrows[posmod(roundi(atan2(-direction.y,direction.x)/(PI/4.0)),8)]
	_objective.text="%s %s · %d м · J — журнал" % [arrow,"Свет над долиной" if sim.data["finished"] else _focus_name(),int(p.distance_to(_waypoint))]

func _focus_name() -> String:
	if _focus=="bridge": return "Восстанови переправу"
	if _focus=="roof": return "Крыша общего амбара"
	if _focus=="workshop": return "Мастерская Бруно"
	for place in GEO.PLACES:
		if place["id"]==_focus: return str(place["name"])
	return "Исследуй долину"

func _target_point(id: String) -> Vector2:
	if sim.PROJECTS.POINTS.has(id): return sim.PROJECTS.POINTS[id]
	return GEO.point(id)

func _resident_name(id: String) -> String:
	if id=="paki": return "Паки"
	if id=="bruno": return "Бруно"
	for definition in SIM.PEOPLE:
		if definition["id"]==id: return str(definition["name"])
	return id

func _track(id: String, close: bool = true) -> void:
	_focus=id
	sim.data["tracked"]=id
	_waypoint=_target_point(id)
	if close: close_menu()

func open_journal() -> void:
	_open_panel()
	_title("Долина бабочек · Свет над долиной")
	_paragraph("Паки помогает поселению восстановить связь с большой дорогой. Выбери каменную или ивовую переправу у реки. Жители доставят материалы из общего амбара, Бруно построит её по этапам. Ты можешь принести свои материалы, помочь со стройкой или пока исследовать озёра. Затем подготовь маяк на северном холме и подай сигнал ночью или в тумане после ливня.")
	_paragraph(_forecast())
	_paragraph("WASD — идти · Shift — бежать · ПКМ — повернуть камеру · колесо — масштаб · E — действие · J/M — журнал и карта · Esc — закрыть · F11 — полный экран",16)
	var map=load("res://scripts/valley_map.gd").new()
	map.chapter=self
	map.custom_minimum_size=Vector2(600,310)
	_content.add_child(map)
	var stock: Dictionary=sim.stock
	_paragraph("В сумке: "+sim.inventory_text(stock),17)
	var shared: Dictionary=sim.data["village"]
	_paragraph("Общий амбар: "+sim.inventory_text(shared)+". Из природы доставлено: %d; на стройки: %d." % [sim.data["ledger"]["npc_delivered"],sim.data["ledger"]["project_delivered"]],17)
	_paragraph("Общие проекты",22)
	_paragraph("Материалы переходят из амбара в руки носильщика, затем на площадку. Готовые этапы сохраняются. В разговоре с Бруно можно позвать его с собой или вернуть к работе. Пока он сопровождает Паки, он не строит; Сивер может продолжить ремонт крыши.",16)
	_project_cards()
	var objectives := [
		["bridge","Переправа открыта",str(sim.data["bridge"])!=""],
		["stores","Припасы защищены от ливня",bool(sim.data["roof"])],
		["meadow","Цветущий луг восстановлен",bool(sim.data["meadow"])],
		["beacon","Маяк подготовлен",bool(sim.data["beacon"])],
		["beacon","Караван пришёл в долину",bool(sim.data["finished"])]]
	for item in objectives:
		var id:=str(item[0])
		_button(("✓ " if item[2] else "◇ ")+str(item[1])+" · показать путь",func() -> void: _track(id))
	_paragraph("Нажми точку на карте, чтобы отметить место и вернуться в долину.",16)
	_paragraph("Жители",22)
	for definition in SIM.PEOPLE:
		var a: Dictionary=sim.resident(definition["id"])
		var activity: String = sim.projects.label(str(a["id"])) if a["goal"]=="project" else GOALS.get(a["goal"],"осматривается")
		_paragraph("%s, %s: %s. Доверие %d; доставлено припасов %d; помощь стройке %d." % [definition["name"],definition["role"],activity,a["friendship"],a["delivered"],a["helped"]],17)
	_paragraph("Последствия решений",22)
	if sim.data["log"].is_empty(): _paragraph("Сюда попадут изменения, которые ты увидишь в долине.",17)
	for line in sim.data["log"]: _paragraph("• "+str(line),17)
	_button("Продолжить · Esc",func() -> void:
		sim.data["tutorial"]=true
		close_menu()
		game._save())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F11:
			var window=get_window()
			window.mode=Window.MODE_WINDOWED if window.mode==Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_F8:
			vista_mode=not vista_mode
			game.camera_distance=35.0 if vista_mode else 27.0
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE:
			if menu_open: close_menu()
			else: open_journal()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_J,KEY_M]:
			if menu_open: close_menu()
			else: open_journal()
			get_viewport().set_input_as_handled()

func snapshot() -> Dictionary:
	return sim.snapshot()
