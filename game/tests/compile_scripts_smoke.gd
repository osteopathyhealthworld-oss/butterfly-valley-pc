extends SceneTree

func _initialize() -> void:
	var count := 0
	var failures := 0
	for directory in ["res://scripts/","res://tests/"]:
		var dir := DirAccess.open(directory)
		if dir == null:
			quit(1)
			return
		for filename in dir.get_files():
			if not str(filename).ends_with(".gd"): continue
			var script := load(directory+filename) as GDScript
			if script==null or not script.can_instantiate():
				push_error("Invalid script: "+directory+filename)
				failures+=1
			count+=1
	print("SCRIPT COMPILE: %d scripts; %d failures" % [count,failures])
	quit(0 if failures==0 else 1)
