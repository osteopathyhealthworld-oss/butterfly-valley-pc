extends RefCounted
## Единый реестр подготовленных материалов. Модели импортируются Godot как PackedScene.
## Один и тот же идентификатор используется в витрине, размещении и будущей логике NPC.

const CATEGORY_TITLES := {
	"building_part": "Строительство и дороги",
	"wood_resource": "Древесина и костёр",
	"crop_or_soil": "Огород и растения",
	"food": "Продукты",
	"furniture": "Мебель",
	"craft_resource": "Материалы ремесла",
	"work_tool": "Рабочие инструменты",
	"farm_animal": "Домашние животные",
	"forest_animal": "Лесные животные",
	"bird": "Птицы",
	"insect": "Насекомые"
}
const ENTRIES := [
	{"id":"kenney.nature-kit.fence-simplehigh","path":"res://library/prepared/kenney/nature-kit/fence-simplehigh.glb","title":"Высокий забор","category":"building_part","rigged":false,"actions":["place","build"]},
	{"id":"kenney.nature-kit.log","path":"res://library/prepared/kenney/nature-kit/log.glb","title":"Бревно","category":"wood_resource","rigged":false,"actions":["collect","carry","store"]},
	{"id":"kenney.nature-kit.stump-rounddetailed","path":"res://library/prepared/kenney/nature-kit/stump-rounddetailed.glb","title":"Пень","category":"wood_resource","rigged":false,"actions":["collect","carry","store"]},
	{"id":"kenney.nature-kit.crops-dirtrowend","path":"res://library/prepared/kenney/nature-kit/crops-dirtrowend.glb","title":"Земляная грядка","category":"crop_or_soil","rigged":false,"actions":["plant","water","harvest"]},
	{"id":"kenney.nature-kit.crops-cornstaged","path":"res://library/prepared/kenney/nature-kit/crops-cornstaged.glb","title":"Кукуруза — стадии роста","category":"crop_or_soil","rigged":false,"actions":["plant","water","harvest"]},
	{"id":"kenney.nature-kit.fence-planks","path":"res://library/prepared/kenney/nature-kit/fence-planks.glb","title":"Ограда из досок","category":"building_part","rigged":false,"actions":["place","build"]},
	{"id":"kenney.nature-kit.campfire-logs","path":"res://library/prepared/kenney/nature-kit/campfire-logs.glb","title":"Костровые брёвна","category":"wood_resource","rigged":false,"actions":["collect","carry","store"]},
	{"id":"kenney.nature-kit.path-stone","path":"res://library/prepared/kenney/nature-kit/path-stone.glb","title":"Каменная дорожка","category":"building_part","rigged":false,"actions":["place","build"]},
	{"id":"kenney.food-kit.carrot","path":"res://library/prepared/kenney/food-kit/carrot.glb","title":"Морковь","category":"food","rigged":false,"actions":["collect","carry","store","trade","consume"]},
	{"id":"kenney.food-kit.onion","path":"res://library/prepared/kenney/food-kit/onion.glb","title":"Лук","category":"food","rigged":false,"actions":["collect","carry","store","trade","consume"]},
	{"id":"kenney.food-kit.apple","path":"res://library/prepared/kenney/food-kit/apple.glb","title":"Яблоко","category":"food","rigged":false,"actions":["collect","carry","store","trade","consume"]},
	{"id":"kenney.food-kit.corn","path":"res://library/prepared/kenney/food-kit/corn.glb","title":"Кукуруза","category":"food","rigged":false,"actions":["collect","carry","store","trade","consume"]},
	{"id":"kenney.food-kit.bread","path":"res://library/prepared/kenney/food-kit/bread.glb","title":"Хлеб","category":"food","rigged":false,"actions":["collect","carry","store","trade","consume"]},
	{"id":"kenney.food-kit.tomato","path":"res://library/prepared/kenney/food-kit/tomato.glb","title":"Помидор","category":"food","rigged":false,"actions":["collect","carry","store","trade","consume"]},
	{"id":"kenney.furniture-kit.tablecross","path":"res://library/prepared/kenney/furniture-kit/tablecross.glb","title":"Деревянный стол","category":"furniture","rigged":false,"actions":["place","interact"]},
	{"id":"kenney.furniture-kit.books","path":"res://library/prepared/kenney/furniture-kit/books.glb","title":"Книги","category":"furniture","rigged":false,"actions":["place","interact"]},
	{"id":"kenney.furniture-kit.bookcaseopenlow","path":"res://library/prepared/kenney/furniture-kit/bookcaseopenlow.glb","title":"Низкий шкаф","category":"furniture","rigged":false,"actions":["place","interact"]},
	{"id":"gobkit.insect.Swallowtail","path":"res://library/prepared/gobkit/insect/Swallowtail.glb","title":"Бабочка-махаон","category":"insect","rigged":true,"actions":["fly","perch","avoid_threat"]},
	{"id":"gobkit.farm.HolsteinCow","path":"res://library/prepared/gobkit/farm/HolsteinCow.glb","title":"Пятнистая корова","category":"farm_animal","rigged":true,"actions":["wander","graze","flee"]},
	{"id":"gobkit.farm.HighlandCow","path":"res://library/prepared/gobkit/farm/HighlandCow.glb","title":"Шотландская корова","category":"farm_animal","rigged":true,"actions":["wander","graze","flee"]},
	{"id":"gobkit.farm.Sheep","path":"res://library/prepared/gobkit/farm/Sheep.glb","title":"Овца","category":"farm_animal","rigged":true,"actions":["wander","graze","flee"]},
	{"id":"gobkit.farm.Pig","path":"res://library/prepared/gobkit/farm/Pig.glb","title":"Свинья","category":"farm_animal","rigged":true,"actions":["wander","graze","flee"]},
	{"id":"gobkit.farm.Lamb","path":"res://library/prepared/gobkit/farm/Lamb.glb","title":"Ягнёнок","category":"farm_animal","rigged":true,"actions":["wander","graze","flee"]},
	{"id":"gobkit.bird.Hummingbird","path":"res://library/prepared/gobkit/bird/Hummingbird.glb","title":"Колибри","category":"bird","rigged":true,"actions":["wander","flee"]},
	{"id":"gobkit.bird.Rooster","path":"res://library/prepared/gobkit/bird/Rooster.glb","title":"Петух","category":"bird","rigged":true,"actions":["wander","flee"]},
	{"id":"gobkit.insect.LeafcutterAnt","path":"res://library/prepared/gobkit/insect/LeafcutterAnt.glb","title":"Муравей-листорез","category":"insect","rigged":true,"actions":["fly","perch","avoid_threat"]},
	{"id":"gobkit.insect.HawkMoth","path":"res://library/prepared/gobkit/insect/HawkMoth.glb","title":"Бражник","category":"insect","rigged":true,"actions":["fly","perch","avoid_threat"]},
	{"id":"gobkit.forest.Tarsier","path":"res://library/prepared/gobkit/forest/Tarsier.glb","title":"Долгопят","category":"forest_animal","rigged":true,"actions":["wander","flee"]},
	{"id":"kaykit.resource.Wood_Log_A","path":"res://library/prepared/kaykit/resource/Wood_Log_A.gltf","title":"Деревянное бревно","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Wood_Plank_A","path":"res://library/prepared/kaykit/resource/Wood_Plank_A.gltf","title":"Доска А","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Wood_Plank_B","path":"res://library/prepared/kaykit/resource/Wood_Plank_B.gltf","title":"Доска Б","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Wood_Planks_Stack_Large","path":"res://library/prepared/kaykit/resource/Wood_Planks_Stack_Large.gltf","title":"Штабель досок","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Stone_Bricks_Stack_Large","path":"res://library/prepared/kaykit/resource/Stone_Bricks_Stack_Large.gltf","title":"Штабель камня","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Iron_Bar","path":"res://library/prepared/kaykit/resource/Iron_Bar.gltf","title":"Железный слиток","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Iron_Nuggets","path":"res://library/prepared/kaykit/resource/Iron_Nuggets.gltf","title":"Железная руда","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Containers_Crate_Medium_Wood","path":"res://library/prepared/kaykit/resource/Containers_Crate_Medium_Wood.gltf","title":"Деревянный ящик","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Pallet_Wood","path":"res://library/prepared/kaykit/resource/Pallet_Wood.gltf","title":"Поддон","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.resource.Gold_Bars","path":"res://library/prepared/kaykit/resource/Gold_Bars.gltf","title":"Золотые слитки","category":"craft_resource","rigged":false,"actions":["collect","carry","store","craft","trade"]},
	{"id":"kaykit.tools.axe","path":"res://library/prepared/kaykit/tools/axe.gltf","title":"Топор","category":"work_tool","rigged":false,"actions":["equip","use","store","craft"]},
	{"id":"kaykit.tools.hammer","path":"res://library/prepared/kaykit/tools/hammer.gltf","title":"Молоток","category":"work_tool","rigged":false,"actions":["equip","use","store","craft"]},
	{"id":"kaykit.tools.pickaxe","path":"res://library/prepared/kaykit/tools/pickaxe.gltf","title":"Кирка","category":"work_tool","rigged":false,"actions":["equip","use","store","craft"]},
	{"id":"kaykit.tools.shovel","path":"res://library/prepared/kaykit/tools/shovel.gltf","title":"Лопата","category":"work_tool","rigged":false,"actions":["equip","use","store","craft"]},
	{"id":"kaykit.tools.saw","path":"res://library/prepared/kaykit/tools/saw.gltf","title":"Пила","category":"work_tool","rigged":false,"actions":["equip","use","store","craft"]},
	{"id":"kaykit.tools.bucket_metal","path":"res://library/prepared/kaykit/tools/bucket_metal.gltf","title":"Металлическое ведро","category":"work_tool","rigged":false,"actions":["equip","use","store","craft"]},
	{"id":"kaykit.tools.anvil","path":"res://library/prepared/kaykit/tools/anvil.gltf","title":"Наковальня","category":"work_tool","rigged":false,"actions":["equip","use","store","craft"]}
]
const HEIGHTS := {
	"building_part": 1.35, "wood_resource": 0.95,
	"crop_or_soil": 1.20, "food": 0.56, "furniture": 1.70,
	"craft_resource": 0.90, "work_tool": 1.20, "farm_animal": 1.65,
	"forest_animal": 0.80, "bird": 0.75, "insect": 0.50
}

static func all() -> Array:
	return ENTRIES

static func find(id: String) -> Dictionary:
	for entry in ENTRIES:
		if str(entry["id"]) == id:
			return entry
	return {}

static func category_name(category: String) -> String:
	return str(CATEGORY_TITLES.get(category, category))

static func desired_height(id: String) -> float:
	var entry := find(id)
	return float(HEIGHTS.get(str(entry.get("category", "")), 1.0))

static func create(id: String) -> Node3D:
	var entry := find(id)
	if entry.is_empty():
		push_warning("Неизвестный материал: " + id)
		return null
	var path: String = str(entry["path"])
	if not ResourceLoader.exists(path):
		push_warning("Godot не видит материал: " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Ошибка импорта материала: " + path)
		return null
	var model := packed.instantiate() as Node3D
	if model != null:
		model.name = str(entry["title"])
	return model

static func fit_visual(root: Node3D, height: float) -> void:
	# Скелетные и обычные GLB приводим к единому видимому масштабу.
	# Для окончательной сцены масштабы можно настроить по конкретным объектам.
	var bounds := {"low": INF, "high": -INF}
	_scan_height(root, root, bounds)
	var low := float(bounds["low"])
	var span := float(bounds["high"]) - low
	if span < 0.001 or span > 100000.0:
		return
	var multiplier := height / span
	root.scale *= multiplier
	root.position.y -= low * multiplier

static func _scan_height(root: Node, origin: Node3D, bounds: Dictionary) -> void:
	if root is MeshInstance3D:
		var part := root as MeshInstance3D
		if part.mesh != null:
			# Импортированный GLB может ещё не находиться в дереве сцены.
			# Собираем локальные преобразования вдоль цепочки родителей.
			var relative := Transform3D.IDENTITY
			var cursor: Node = part
			while cursor != origin and cursor != null:
				if cursor is Node3D:
					relative = (cursor as Node3D).transform * relative
				cursor = cursor.get_parent()
			var aabb := part.get_aabb()
			for x in [aabb.position.x, aabb.end.x]:
				for y in [aabb.position.y, aabb.end.y]:
					for z in [aabb.position.z, aabb.end.z]:
						var point := relative * Vector3(x, y, z)
						bounds["low"] = minf(float(bounds["low"]), point.y)
						bounds["high"] = maxf(float(bounds["high"]), point.y)
	for child in root.get_children():
		_scan_height(child, origin, bounds)

static func first_animation(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := first_animation(child)
		if found != null:
			return found
	return null

static func play_idle(root: Node) -> String:
	var player := first_animation(root)
	if player == null:
		return ""
	var clips := player.get_animation_list()
	var chosen: StringName = &""
	for clip in clips:
		var name_lower := str(clip).to_lower()
		if name_lower == "idle" or name_lower.ends_with("/idle"):
			chosen = clip
			break
	if chosen == &"":
		for clip in clips:
			if str(clip).to_lower() != "reset":
				chosen = clip
				break
	if chosen != &"":
		player.play(chosen)
	return str(chosen)

