extends SceneTree
const SAVE = preload("res://scripts/save.gd")
const PATH := "user://save_recovery_smoke.json"
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	var state: Dictionary=SAVE.fresh()
	state["coins"]=31
	check(SAVE.write(state,PATH),"Write first save")
	state["coins"]=42
	state["harvests"]=7
	state["grownLeaves"]=9
	check(SAVE.write(state,PATH),"Replace save after writing a complete pending file")
	check(SAVE.read(PATH)["coins"]==42,"Read the new complete save")
	check(SAVE.read(PATH)["harvests"]==7 and SAVE.read(PATH)["grownLeaves"]==9,"JSON numeric fields must retain counters rather than reset to integer defaults")
	check(SAVE.read(PATH+".bak")["coins"]==31,"Keep previous valid state as backup")
	var broken:=FileAccess.open(PATH,FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	check(SAVE.read(PATH)["coins"]==31,"Recover from an interrupted or corrupted primary save")
	check(SAVE.write(state,PATH),"Save successfully after recovery")
	check(SAVE.read(PATH+".bak")["coins"]==31,"Do not replace a valid backup with corrupt primary data")
	DirAccess.remove_absolute(PATH)
	check(SAVE.read(PATH)["coins"]==31,"Recover when the primary filename is missing during replacement")
	DirAccess.remove_absolute(PATH+".bak")
	var pending:=FileAccess.open(PATH+".tmp",FileAccess.WRITE)
	pending.store_string(JSON.stringify(state))
	pending.close()
	check(SAVE.read(PATH)["coins"]==42,"Recover a complete pending file if the first rename was interrupted")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(PATH+suffix): DirAccess.remove_absolute(PATH+suffix)
	print("SAVE RECOVERY: %s" % ("PASS" if failures==0 else "%d FAILURES" % failures))
	quit(0 if failures==0 else 1)
