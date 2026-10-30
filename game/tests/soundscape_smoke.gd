extends SceneTree
## Headless check of the real audio files and the Godot soundscape controller.

func _initialize() -> void:
	call_deferred("_run_checks")


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _run_checks() -> void:
	var required := [
		"music/oga-cathedral-forest.ogg",
		"music/ludum-dare-30-02.ogg",
		"music/ludum-dare-32-05.ogg",
		"sfx/amb-birds-01.ogg",
		"sfx/amb-crickets-03.ogg",
		"sfx/amb-morning-01.ogg",
		"sfx/loop-rain-01.ogg",
		"sfx/loop-water-01.ogg",
		"sfx/loop-wind-01.ogg",
		"sfx/amb-cicada-01.ogg"
	]
	for path in required:
		if not ResourceLoader.exists("res://assets/audio/" + path):
			_fail("Missing selected CC0 audio: " + path)
			return
	var script = load("res://scripts/valley_audio.gd")
	if script == null:
		_fail("The soundscape controller failed to compile")
		return
	var sound = script.new()
	root.add_child(sound)
	sound.begin()
	if not sound._started or sound._nature_path.is_empty():
		_fail("Forest ambience failed to start")
		return
	sound.set_soundscape(false, false, "riverbank", 0.0, "clear")
	if str(sound._paths["water"]) != "sfx/loop-water-01.ogg":
		_fail("River approach did not activate flowing water")
		return
	sound.set_soundscape(true, true, "mosswood", 50.0, "storm")
	if sound._requested_mood != "night":
		_fail("Night must select the night soundtrack")
		return
	if float(sound._targets["rain"]) > -23.0 or float(sound._targets["water"]) > -60.0:
		_fail("Rain and distant water mix levels are incorrect")
		return
	sound.play_cue("step")
	sound.play_cue("water")
	print("SOUNDSCAPE_SMOKE_PASS: CC0 files, river, rain, night, cue playback")
	quit(0)
