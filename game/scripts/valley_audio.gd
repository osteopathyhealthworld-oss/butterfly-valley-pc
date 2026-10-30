extends Node
## Browser-safe soundtrack: playback starts only after the first user input.
## The selected CC0 sounds are copied by prepare-assets.ps1.

const ROOT := "res://assets/audio/"
const FOOTSTEPS := [
	"sfx/step-grass-01.ogg", "sfx/step-grass-02.ogg", "sfx/step-grass-03.ogg"
]
const CUES := {
	"pickup": "sfx/item-pickup-01.ogg",
	"build": "sfx/impact-wood-medium-01.ogg",
	"discovery": "sfx/magic-twinkle-01.ogg",
	"reward": "sfx/coins-jingle-01.ogg"
}

var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _effects: Array[AudioStreamPlayer] = []
var _started := false
var _ambience_kind := ""
var _footstep_index := 0
var _effect_index := 0

func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.name = "Музыка долины"
	add_child(_music)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Природное окружение"
	add_child(_ambience)
	for i in range(3):
		var sfx := AudioStreamPlayer.new()
		sfx.name = "Звуки действий %d" % i
		add_child(sfx)
		_effects.append(sfx)

func begin() -> void:
	if _started:
		return
	_started = true
	_play_loop(_music, "music/oga-cathedral-forest.ogg", -18.0)
	set_ambience(false, false)

func set_ambience(night: bool, rain: bool) -> void:
	if not _started:
		return
	var kind := "rain" if rain else ("night" if night else "day")
	if kind == _ambience_kind:
		return
	_ambience_kind = kind
	var filename := "sfx/loop-rain-01.ogg" if rain else ("sfx/amb-crickets-03.ogg" if night else "sfx/amb-birds-01.ogg")
	_play_loop(_ambience, filename, -25.0 if rain else -27.0)

func _play_loop(player: AudioStreamPlayer, path: String, volume: float) -> void:
	player.stop()
	var stream_path := ROOT + path
	if not ResourceLoader.exists(stream_path):
		push_warning("Не найден звук долины: " + stream_path)
		return
	var stream := load(stream_path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	player.stream = stream
	player.volume_db = volume
	player.play()

func play_cue(cue: String) -> void:
	if not _started or _effects.is_empty():
		return
	var path := ""
	if cue == "step":
		path = FOOTSTEPS[_footstep_index % FOOTSTEPS.size()]
		_footstep_index += 1
	else:
		path = str(CUES.get(cue, ""))
	if path.is_empty() or not ResourceLoader.exists(ROOT + path):
		return
	var stream := load(ROOT + path) as AudioStream
	if stream == null:
		return
	var output := _effects[_effect_index % _effects.size()]
	_effect_index += 1
	output.stop()
	output.stream = stream
	output.volume_db = -15.0 if cue == "step" else -10.0
	output.play()

