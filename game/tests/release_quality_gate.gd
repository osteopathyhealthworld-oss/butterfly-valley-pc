extends SceneTree
## Hard release gate for the Windows build. The playable public world
## must never silently replace the architecture or terrain with placeholders.

const REQUIRED := [
	"res://assets/paki-hero.glb",
	"res://assets/buildings/village/Floor_WoodDark.gltf",
	"res://assets/buildings/village/Wall_Plaster_Straight.gltf",
	"res://assets/buildings/village/Wall_Plaster_Door_Flat.gltf",
	"res://assets/buildings/village/Wall_Plaster_Window_Wide_Flat.gltf",
	"res://assets/buildings/village/Roof_RoundTiles_6x6.gltf",
	"res://assets/buildings/village/Door_1_Flat.gltf",
	"res://assets/buildings/village/Window_Wide_Flat1.gltf",
	"res://assets/environment/grass-ground-color.jpg",
	"res://assets/environment/grass-ground-normal.jpg",
	"res://assets/environment/meadow-color.jpg",
	"res://assets/environment/soil-color.jpg",
	"res://assets/environment/canopy.glb",
	"res://assets/environment/undergrowth.glb",
	"res://assets/environment/river-stones.glb",
	"res://shaders/terrain_blend.gdshader",
	"res://assets/audio/music/oga-cathedral-forest.ogg",
	"res://assets/audio/sfx/amb-birds-01.ogg",
	"res://assets/audio/sfx/step-grass-01.ogg",
	"res://assets/audio/sfx/item-pickup-01.ogg",
	"res://assets/audio/sfx/impact-wood-medium-01.ogg",
	"res://library/prepared/gobkit/farm/Lamb.glb",
	"res://library/prepared/gobkit/insect/Swallowtail.glb"
]

func _initialize() -> void:
	var errors: PackedStringArray = []
	for path in REQUIRED:
		if not ResourceLoader.exists(path):
			errors.append("Нет ресурса: " + path)
		elif load(path) == null:
			errors.append("Не удалось импортировать: " + path)
	if errors.is_empty():
		var paki := load("res://assets/paki-hero.glb") as PackedScene
		if paki != null:
			var actor := paki.instantiate()
			var animations := _find_player(actor)
			if animations == null:
				errors.append("У Паки нет AnimationPlayer")
			else:
				for wanted in ["Paki_Walking", "Paki_Fast_Run", "Paki_Shared_Idle"]:
					var found := false
					for clip in animations.get_animation_list():
						if str(clip) == wanted or str(clip).ends_with("/" + wanted):
							found = true
					if not found:
						errors.append("Нет анимации Паки: " + wanted)
			actor.free()
	if not errors.is_empty():
		for issue in errors:
			push_error(issue)
		print("RELEASE FAILED: missing visual/audio/animation resources")
		quit(1)
		return
	print("RELEASE PASS: village modules, stylized nature atlas, terrain PBR, CC0 audio and Paki clips")
	quit(0)

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null

