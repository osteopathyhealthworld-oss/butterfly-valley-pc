extends SceneTree

const Society = preload("res://scripts/society_simulation.gd")

func _initialize() -> void:
	var sim = Society.new()
	sim.setup()
	if sim.agents.size() < 70:
		push_error("Insufficient population")
		quit(1)
		return
	for tick in range(2200):
		sim.advance(0.5, tick % 400 > 270)
	var carried := 0
	for agent in sim.agents:
		carried += int(agent["cargo"])
	var stored := 0
	for good in sim.warehouse:
		stored += int(sim.warehouse[good])
	if stored + carried + int(sim.ledger["gifted"]) != int(sim.ledger["produced"]):
		push_error("Resource conservation violated")
		quit(1)
		return
	if stored < 10 or int(sim.ledger["meetings"]) == 0:
		push_error("Work, deliveries, or meetings did not occur")
		quit(1)
		return
	var snap: Dictionary = sim.snapshot()
	var resumed = Society.new()
	resumed.setup(snap)
	if resumed.agents.size() != sim.agents.size() or resumed.warehouse != sim.warehouse:
		push_error("Save / restore mismatch")
		quit(1)
		return
	var nearby: Dictionary = resumed.nearest(Vector2(float(resumed.agents[0]["x"]), float(resumed.agents[0]["z"])))
	if nearby.is_empty() or not resumed.interact(str(nearby["id"])).contains("познакомились"):
		push_error("Player interaction failed")
		quit(1)
		return
	print("SOCIETY_OK: agents=", sim.agents.size(), " produced=", sim.ledger["produced"], " delivered=", stored, " meetings=", sim.ledger["meetings"])
	quit()

