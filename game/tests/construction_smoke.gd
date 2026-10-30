extends SceneTree
## Godot --headless --path . -s res://tests/construction_smoke.gd

func _initialize() -> void:
	call_deferred("_run_checks")

func _run_checks() -> void:
	var source := load("res://scripts/construction.gd")
	assert(source != null)
	var site = source.new()
	root.add_child(site)
	assert(site.stage_groups.size() == 6)
	assert(site.total_stages() == 5)
	assert(int(site.cost_for(1)["stone"]) == 1)
	assert(int(site.cost_for(2)["wood"]) == 1)
	assert(int(site.cost_for(3)["wood"]) == 1)
	assert(int(site.cost_for(4)["wood"]) == 1)
	assert(int(site.cost_for(5)["stone"]) == 1)
	assert(site.next_description().contains("Каменный фундамент"))
	assert(site.stage_groups[0].visible)
	site.set_stage(1)
	assert(not site.stage_groups[0].visible)
	assert(site.stage_groups[1].visible)
	assert(not site.stage_groups[2].visible)
	site.set_stage(3)
	assert(site.stage_groups[3].visible)
	assert(not site.stage_groups[4].visible)
	site.set_stage(5)
	assert(site.stage_groups[5].visible)
	assert(site.next_description() == "Мастерская готова")
	if site._has_module("Wall_Plaster_Straight"):
		var imported_walls := 0
		for child in site.stage_groups[3].get_children():
			if str(child.name).begins_with("Quaternius_"):
				imported_walls += 1
		assert(imported_walls == 12, "Должны загружаться 12 модульных стен")
	if site._has_module("Roof_RoundTiles_6x6"):
		assert(site.stage_groups[4].get_child_count() == 1, "Должна загружаться готовая черепичная крыша")

	var world = load("res://scripts/world.gd").new()
	root.add_child(world)
	assert(world.can_walk(32.0, -28.0, false))
	world.set_workshop_stage(3)
	assert(not world.can_walk(32.0, -28.0, false))
	assert(world.can_walk(24.0, -28.0, false))

	var fresh := ValleySave.fresh()
	assert(int(fresh["world"]["builder"]["stage"]) == 0)
	print("CONSTRUCTION_SMOKE_OK: stages, resources, visibility, collision, save schema")
	quit(0)

