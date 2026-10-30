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
	assert(site._frame_visual != null)
	assert(not site._frame_visual.visible, "Грубый деревянный каркас не должен торчать из готовых стен")
	site.set_stage(5)
	assert(site.stage_groups[5].visible)
	assert(site.next_description() == "Мастерская готова")
	if site._has_module("Wall_Plaster_Straight"):
		var imported_walls := 0
		for child in site.stage_groups[3].get_children():
			if str(child.name).begins_with("Quaternius_"):
				imported_walls += 1
		if imported_walls != 12:
			var actual_names := PackedStringArray()
			for child in site.stage_groups[3].get_children():
				actual_names.append(str(child.name))
			push_error("Ожидалось 12 модульных стен, загружено %d; сцена содержит: %s" % [imported_walls, ", ".join(actual_names)])
			quit(1)
			return
	if site._has_module("Roof_RoundTiles_6x6"):
		assert(site.stage_groups[4].get_child_count() == 1, "Должна загружаться готовая черепичная крыша")
	for style in ["cottage", "barn", "alchemist"]:
		var house = source.new()
		house.appearance = style
		root.add_child(house)
		house.set_stage(5)
		assert(house.stage_groups[3].visible and house.stage_groups[4].visible)
		assert(not house._frame_visual.visible)
		if style == "cottage" and house._has_module("Roof_RoundTiles_4x4"):
			assert(house.stage_groups[5].get_child_count() >= 1)
		if style == "barn" and house._has_module("Roof_RoundTiles_6x4"):
			assert((house.stage_groups[4].get_child(0) as Node3D).name == "Quaternius_Roof_RoundTiles_6x4")
		if style == "alchemist" and house._has_module("Roof_RoundTiles_8x8"):
			assert((house.stage_groups[4].get_child(0) as Node3D).name == "Quaternius_Roof_RoundTiles_8x8")
		house.queue_free()

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

