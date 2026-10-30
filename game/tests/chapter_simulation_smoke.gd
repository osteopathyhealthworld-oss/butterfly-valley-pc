extends SceneTree
const SIM=preload("res://scripts/valley_chapter_sim.gd")
const GEO=preload("res://scripts/valley_geography.gd")
var failures:=0

func finish_bridge(sim) -> void:
	for i in range(3):
		sim.act("bridge","contribute",{"position":sim.PROJECTS.POINTS["bridge"]})
	for i in range(200):
		sim.projects.claim("bruno")
		sim.project_service("bruno",sim.projects.target("bruno"),0.25)
		if sim.projects.is_complete("bridge"): return

func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	var bag: Dictionary={}
	var sim=SIM.new()
	sim.setup({},bag)
	check(bag["wood"]==6 and bag["stone"]==4,"Incorrect starting stock")
	var before=bag.duplicate(true)
	check(not sim.pay({"wood":1,"stone":99}),"Partial payment should fail")
	check(bag==before,"A failed payment must leave every resource untouched")
	check(not sim.act("beacon","signal")["ok"],"Do not unlock the ending prematurely")
	check(sim.act("bridge","stone")["ok"],"Stone route must be available from starter supplies")
	check(sim.data["bridge"]=="","Project choice must wait for actual construction")
	finish_bridge(sim)
	check(sim.data["bridge"]=="stone","Stone route must be completed by the builder")
	before=bag.duplicate(true)
	check(not sim.act("bridge","willow")["ok"] and bag==before,"Bridge must not charge twice")
	check(sim.act("craft","resin")["ok"],"Resin recipe must be executable")
	check(sim.act("beacon","light")["ok"],"A complete critical path must be affordable")
	check(not sim.act("beacon","signal")["ok"],"Daytime signal should explain timing")
	check(sim.act("board","rest")["ok"],"Allow waiting for evening without real idle time")
	check(sim.is_night(),"Rest must reach evening")
	check(sim.act("beacon","signal")["ok"],"Stone route must reach the ending")
	before=bag.duplicate(true)
	check(not sim.act("beacon","signal")["ok"] and bag==before,"Ending reward must be idempotent")
	var restored=SIM.new()
	restored.setup(JSON.parse_string(JSON.stringify(sim.snapshot())),bag)
	check(bag==before,"Reload must not grant starter supplies again")
	check(restored.data["finished"],"Ending state must survive reload")
	check(restored.data["residents"].size()==4,"Named residents must survive reload")

	var willow=SIM.new()
	var willow_bag: Dictionary={}
	willow.setup({},willow_bag)
	check(willow.act("craft","resin")["ok"],"Prepare willow resin")
	check(willow.act("bridge","willow")["ok"],"Alternate bridge route must be affordable")
	finish_bridge(willow)
	check(float(willow.data["habitat"])==73.0,"Willow route should change habitat")
	var habitat_before:=float(willow.data["habitat"])
	check(willow.act("quarry","rush")["ok"],"Allow the resource-intensive choice")
	check(float(willow.data["habitat"])==habitat_before-15.0,"Quarry choice needs an actual consequence")
	before=willow_bag.duplicate(true)
	check(not willow.act("quarry","rush")["ok"] and willow_bag==before,"Daily quarry limit must prevent repeated reward")
	check(willow.act("garden","plant")["ok"],"Damage must be repairable by planting")
	check(float(willow.data["habitat"])>habitat_before-15.0,"Planting must restore habitat")
	willow.talk("iris",true)
	var after_gift:=int(willow_bag["food"])
	willow.talk("iris",true)
	check(willow_bag["food"]==after_gift,"Repeated gift must not consume resources or farm friendship")

	var storm=SIM.new()
	storm.setup({}, {})
	storm.data["time"]=SIM.STORM_END-0.5
	storm.advance(0.5)
	check(storm.data["village"]["food"]==4,"Unprotected store should lose two food")
	var after_storm=storm.snapshot()
	storm.advance(0.5)
	check(storm.data["outcomes"].size()==1,"Storm outcome must apply once")
	check(storm.data["village"]["food"]==after_storm["village"]["food"],"No repeated storm deduction")
	var safe=SIM.new()
	safe.setup({}, {})
	safe.data["roof"]=true
	safe.data["meadow"]=true
	safe.data["time"]=SIM.STORM_END-0.5
	safe.advance(0.5)
	check(safe.data["village"]["food"]==6,"Roof must protect food")
	check(safe.data["village"]["herbs"]==5,"Restored meadow must have a concrete yield")

	var workers=SIM.new()
	workers.setup({}, {})
	workers.data["priority"]="safety"
	workers.act("board","safety")
	var a: Dictionary=workers.resident("siver")
	check(workers.choose_goal(a,SIM.PEOPLE[2])=="project","Safety priority should select a shared repair project")
	check(not workers.data["roof"],"Selecting safety must not repair the roof without delivery")
	workers.projects.release("siver")
	a["goal"]="work"
	workers.finish_job(a,SIM.PEOPLE[2])
	var stone_before:=int(workers.data["village"]["stone"])
	check(int(a["cargo_count"])>0 and workers.data["village"]["stone"]==stone_before,"Gathering puts goods in cargo, not straight in the warehouse")
	a["hunger"]=100.0
	check(workers.choose_goal(a,SIM.PEOPLE[2])=="deliver","Do not abandon cargo when hungry")
	a["goal"]="deliver"
	workers.finish_job(a,SIM.PEOPLE[2])
	check(workers.data["village"]["stone"]>stone_before and a["cargo_count"]==0,"Delivery must transfer, not duplicate cargo")
	workers.data["village"]["food"]=0
	var gardener: Dictionary=workers.resident("nara")
	gardener["hunger"]=100.0
	check(workers.choose_goal(gardener,SIM.PEOPLE[1])=="work","A food shortage must not deadlock the gardener")

	for lake in GEO.LAKES:
		var p: Vector2=lake["center"]
		check(not GEO.lake_at(p.x,p.y).is_empty(),"Lake center should be water")
		check(GEO.shape_height(p.x,p.y,0.0)<float(lake["level"]),"Water must cover a depression")
	for place in GEO.PLACES:
		var p:Vector2=place["pos"]
		check(GEO.lake_at(p.x,p.y,0.6).is_empty(),"Do not place an interaction in water: "+str(place["id"]))
	check(GEO.dry_height(-24,125)>8.0,"Northern hill should be distinguishable from the river valley")
	check(absf(GEO.dry_height(5,9))<0.01,"Preserve the original river crossing height")
	print("CHAPTER SIMULATION: %s" % ("PASS" if failures==0 else "%d FAILURES"%failures))
	quit(0 if failures==0 else 1)
