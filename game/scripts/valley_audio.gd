extends Node
## «Долина бабочек»: layered CC0 soundscape with soft fades.
## Long recordings are loaded only when they become audible. The release builder
## verifies and installs the curated sounds from audio-selection.json.

const ROOT := "res://assets/audio/"
const SILENCE_DB := -64.0
const MUSIC_MOODS := {
	"forest": ["music/oga-cathedral-forest.ogg", "music/ludum-dare-30-03.ogg"],
	"meadow": ["music/ludum-dare-38-08.ogg", "music/oga-cathedral-forest.ogg"],
	"highland": ["music/ludum-dare-32-05.ogg", "music/ludum-dare-38-10.ogg"],
	"night": ["music/patreon-challenge-04.ogg", "music/ludum-dare-30-02.ogg"]
}
const NATURE_BY_BIOME := {
	"old_forest": "sfx/amb-birds-01.ogg",
	"meadow": "sfx/amb-outside-01.ogg",
	"riverbank": "sfx/amb-morning-01.ogg",
	"pine": "sfx/amb-forest-02.mp3",
	"highland": "sfx/amb-wind-06.ogg",
	"wind_ridge": "sfx/amb-wind-06.ogg",
	"violet_heath": "sfx/amb-outside-01.ogg",
	"amber_wood": "sfx/amb-forest-01.mp3",
	"mosswood": "sfx/amb-swamp-01.ogg",
	"bloom_garden": "sfx/amb-morning-01.ogg"
}
const FOOTSTEPS := [
	"sfx/step-grass-01.ogg", "sfx/step-grass-02.ogg",
	"sfx/step-grass-03.ogg", "sfx/step-grass-04.ogg",
	"sfx/step-grass-05.ogg"
]
const CUES := {
	"pickup": ["sfx/item-pickup-01.ogg", "sfx/gem-pickup-01.ogg", "sfx/gem-pickup-02.ogg"],
	"build": ["sfx/impact-wood-medium-01.ogg", "sfx/impact-plank-medium-01.ogg", "sfx/impact-plank-medium-02.ogg"],
	"discovery": ["sfx/magic-twinkle-01.ogg", "sfx/magic-twinkle-02.ogg", "sfx/chime-levelup-01.mp3"],
	"reward": ["sfx/coins-jingle-01.ogg", "sfx/coins-jingle-02.ogg"],
	"water": ["sfx/water-splash-01.ogg", "sfx/water-splash-02.ogg"],
	"chop": ["sfx/chop-01.ogg", "sfx/impact-wood-medium-02.ogg"],
	"hammer": ["sfx/impact-plank-medium-03.ogg", "sfx/impact-plank-medium-04.ogg"],
	"door": ["sfx/door-open-01.ogg", "sfx/door-open-02.ogg"],
	"dialog": ["sfx/ui-click-01.ogg", "sfx/ui-click-02.ogg"],
	"animal": ["sfx/creature-cute-01.ogg", "sfx/creature-cute-02.ogg"],
	"magic": ["sfx/magic-spell-01.ogg", "sfx/magic-sparkle-01.mp3"]
}

var _players: Dictionary = {}
var _targets: Dictionary = {}
var _paths: Dictionary = {}
var _effects: Array[AudioStreamPlayer] = []
var _started := false
var _nature_slot := "nature_a"
var _music_slot := "music_a"
var _nature_path := ""
var _music_mood := "forest"
var _requested_mood := "forest"
var _candidate_mood := "forest"
var _candidate_time := 0.0
var _music_elapsed := 0.0
var _music_index: Dictionary = {}
var _music_volume := -26.0
var _cue_index: Dictionary = {}
var _footstep_index := 0
var _effect_index := 0


func _ready() -> void:
	for slot in ["music_a", "music_b", "nature_a", "nature_b", "rain", "water", "wind", "insects"]:
		var layer := AudioStreamPlayer.new()
		layer.name = "Аудиослой · " + slot
		layer.volume_db = SILENCE_DB
		add_child(layer)
		_players[slot] = layer
		_targets[slot] = SILENCE_DB
		_paths[slot] = ""
	for i in range(5):
		var effect := AudioStreamPlayer.new()
		effect.name = "Короткий эффект %d" % i
		add_child(effect)
		_effects.append(effect)


func begin() -> void:
	if _started:
		return
	_started = true
	_switch_music("music/oga-cathedral-forest.ogg")
	_switch_nature("sfx/amb-birds-01.ogg")


func _load_stream(relative: String) -> AudioStream:
	var path := ROOT + relative
	if not ResourceLoader.exists(path):
		push_warning("Нет звука: " + path)
		return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	return stream


func _start_loop(slot: String, relative: String, target: float) -> bool:
	var player: AudioStreamPlayer = _players[slot] as AudioStreamPlayer
	if str(_paths[slot]) == relative:
		_targets[slot] = target
		return true
	var stream := _load_stream(relative)
	if stream == null:
		return false
	player.stop()
	player.stream = stream
	player.volume_db = SILENCE_DB
	player.play()
	_paths[slot] = relative
	_targets[slot] = target
	return true


func _switch_nature(relative: String) -> void:
	if relative == _nature_path:
		return
	var next_slot := "nature_b" if _nature_slot == "nature_a" else "nature_a"
	if _nature_path.is_empty():
		next_slot = "nature_a"
	if _start_loop(next_slot, relative, -30.0):
		_targets[_nature_slot] = SILENCE_DB
		_nature_slot = next_slot
		_nature_path = relative


func _switch_music(relative: String) -> void:
	var next_slot := "music_b" if _music_slot == "music_a" else "music_a"
	if str(_paths[_music_slot]).is_empty():
		next_slot = "music_a"
	if _start_loop(next_slot, relative, _music_volume):
		_targets[_music_slot] = SILENCE_DB
		_music_slot = next_slot
		_music_elapsed = 0.0


func _ensure_layer(slot: String, relative: String, volume: float) -> void:
	if volume > -58.0 and str(_paths[slot]).is_empty():
		_start_loop(slot, relative, volume)
	_targets[slot] = volume


func set_soundscape(night: bool, rain: bool, biome: String, water_distance: float, weather: String = "clear") -> void:
	if not _started:
		return
	var raining_now := rain or weather == "storm"
	var nature: String = "sfx/amb-crickets-03.ogg" if night else str(NATURE_BY_BIOME.get(biome, "sfx/amb-birds-01.ogg"))
	if night and biome == "mosswood":
		nature = "sfx/amb-swamp-02.ogg"
	_switch_nature(nature)
	_targets[_nature_slot] = -35.0 if raining_now else -29.0
	_ensure_layer("rain", "sfx/loop-rain-01.ogg", -25.0 if raining_now else SILENCE_DB)
	var distance := maxf(0.0, water_distance)
	var water_volume := clampf(-25.0 - distance * 2.0, SILENCE_DB, -25.0)
	_ensure_layer("water", "sfx/loop-water-01.ogg", water_volume)
	var windy := raining_now or biome in ["highland", "wind_ridge"]
	_ensure_layer("wind", "sfx/loop-wind-01.ogg", -33.0 if windy else SILENCE_DB)
	var insects := not night and not raining_now and biome in ["meadow", "violet_heath", "bloom_garden"]
	_ensure_layer("insects", "sfx/amb-cicada-01.ogg", -39.0 if insects else SILENCE_DB)
	_music_volume = -31.0 if raining_now else -26.0
	_targets[_music_slot] = _music_volume
	_requested_mood = "night" if night else (
		"highland" if biome in ["highland", "wind_ridge"] else (
		"meadow" if biome in ["meadow", "riverbank", "violet_heath", "bloom_garden"] else "forest"
		)
	)


func set_ambience(night: bool, rain: bool) -> void:
	# Compatibility with the earlier two-parameter API.
	set_soundscape(night, rain, "old_forest", 100.0)


func _process(delta: float) -> void:
	if not _started:
		return
	for slot in _players.keys():
		var player: AudioStreamPlayer = _players[slot] as AudioStreamPlayer
		var target: float = float(_targets[slot])
		player.volume_db = move_toward(player.volume_db, target, delta * 12.0)
		if target <= -60.0 and player.volume_db <= -60.0 and player.playing:
			player.stop()
		elif target > -60.0 and not player.playing and player.stream != null:
			player.play()
	if _candidate_mood != _requested_mood:
		_candidate_mood = _requested_mood
		_candidate_time = 0.0
	else:
		_candidate_time += delta
	if _candidate_mood != _music_mood and _candidate_time >= 16.0:
		_music_mood = _candidate_mood
		_music_index[_music_mood] = 0
		var playlist: Array = MUSIC_MOODS[_music_mood]
		_switch_music(str(playlist[0]))
	_music_elapsed += delta
	if _music_elapsed >= 225.0:
		var playlist: Array = MUSIC_MOODS[_music_mood]
		var choice := (int(_music_index.get(_music_mood, 0)) + 1) % playlist.size()
		_music_index[_music_mood] = choice
		_switch_music(str(playlist[choice]))


func play_cue(cue: String) -> void:
	if not _started or _effects.is_empty():
		return
	var relative := ""
	if cue == "step":
		relative = FOOTSTEPS[_footstep_index % FOOTSTEPS.size()]
		_footstep_index += 1
	else:
		if not CUES.has(cue):
			return
		var clips: Array = CUES[cue]
		var index := int(_cue_index.get(cue, 0))
		relative = str(clips[index % clips.size()])
		_cue_index[cue] = index + 1
	var stream_path := ROOT + relative
	if not ResourceLoader.exists(stream_path):
		return
	var stream := load(stream_path) as AudioStream
	if stream == null:
		return
	var effect := _effects[_effect_index % _effects.size()]
	_effect_index += 1
	effect.stop()
	effect.stream = stream
	effect.volume_db = -18.0 if cue == "step" else -13.0
	effect.play()
