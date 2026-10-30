extends Node3D
## Игровая витрина 45 готовых моделей с живым 3D-просмотром.
## Материалы загружаются по одному: выбор модели не загружает всю библиотеку в память.

const LIBRARY = preload("res://scripts/asset_library.gd")
const PLACEMENTS = preload("res://scripts/material_placements.gd")
const CATEGORY_KEYS := [
	"", "building_part", "wood_resource", "crop_or_soil", "food",
	"furniture", "craft_resource", "work_tool",
	"farm_animal", "forest_animal", "bird", "insect"
]

var _preview_holder: Node3D
var _model: Node3D
var _list: ItemList
var _categories: OptionButton
var _details: Label
var _status: Label
var _animation_button: Button
var _selected: Dictionary = {}
var _filtered: Array = []
var _anim_player: AnimationPlayer
var _clips: Array = []
var _clip_index := -1

func _ready() -> void:
	_make_stage()
	_make_menu()
	_rebuild_list()
	get_viewport().get_window().title = "Долина бабочек — материалы мира"

func _make_stage() -> void:
	var sky := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#b8d2c4")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#fff0d5")
	settings.ambient_light_energy = 0.8
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	sky.environment = settings
	add_child(sky)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 32, 0)
	sun.light_color = Color("#fff0d0")
	sun.light_energy = 1.5
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Площадка для просмотра"
	var ground := PlaneMesh.new()
	ground.size = Vector2(12, 12)
	floor_mesh.mesh = ground
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("#7f9c78")
	floor_mat.roughness = 0.95
	floor_mesh.material_override = floor_mat
	floor_mesh.position.y = -0.012
	add_child(floor_mesh)

	_preview_holder = Node3D.new()
	_preview_holder.name = "Выбранная модель"
	add_child(_preview_holder)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.2
	camera.position = Vector3(6.6, 4.2, 8.6)
	camera.look_at(Vector3(0, 1.15, 0), Vector3.UP)
	camera.current = true
	add_child(camera)

func _make_menu() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18, 18)
	panel.custom_minimum_size = Vector2(358, 620)
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Материалы Долины"
	title.add_theme_font_size_override("font_size", 25)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "45 моделей · природа, ремёсла и животные"
	column.add_child(subtitle)

	_categories = OptionButton.new()
	for i in range(CATEGORY_KEYS.size()):
		var key: String = CATEGORY_KEYS[i]
		_categories.add_item("Все материалы" if key == "" else LIBRARY.category_name(key), i)
	_categories.select(0)
	_categories.item_selected.connect(_on_category_changed)
	column.add_child(_categories)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(324, 205)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	column.add_child(_list)

	_details = Label.new()
	_details.custom_minimum_size = Vector2(300, 64)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_details)

	_animation_button = Button.new()
	_animation_button.text = "Следующая анимация"
	_animation_button.disabled = true
	_animation_button.pressed.connect(_next_animation)
	column.add_child(_animation_button)

	var place := Button.new()
	place.text = "Поставить выбранное в мире"
	place.pressed.connect(_place_in_world)
	column.add_child(place)

	var remove := Button.new()
	remove.text = "Убрать последнее размещение"
	remove.pressed.connect(_remove_last)
	column.add_child(remove)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 48)
	_status.text = "Объекты размещаются рядом с Паки. Животные пока только показывают анимацию."
	column.add_child(_status)

	var back := Button.new()
	back.text = "Вернуться в долину · Esc"
	back.pressed.connect(_return_to_world)
	column.add_child(back)

	var hint := Label.new()
	hint.position = Vector2(410, 18)
	hint.text = "Модель поворачивается для осмотра. Предметы остаются после перезагрузки."
	hint.add_theme_color_override("font_color", Color("#253e35"))
	canvas.add_child(hint)

func _on_category_changed(_index: int) -> void:
	_rebuild_list()

func _rebuild_list() -> void:
	_list.clear()
	_filtered.clear()
	var group: String = CATEGORY_KEYS[_categories.selected]
	for entry in LIBRARY.all():
		if group != "" and str(entry["category"]) != group:
			continue
		_filtered.append(entry)
		_list.add_item(str(entry["title"]))
	if not _filtered.is_empty():
		_list.select(0)
		_on_item_selected(0)
	else:
		_details.text = "В этой категории пока нет моделей."

func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _filtered.size():
		return
	_selected = _filtered[index]
	if _model != null:
		_preview_holder.remove_child(_model)
		_model.queue_free()
		_model = null
	_anim_player = null
	_clips.clear()
	_clip_index = -1
	_preview_holder.rotation.y = 0.0

	_model = LIBRARY.create(str(_selected["id"]))
	if _model == null:
		_details.text = "Модель не загрузилась. Проверьте импорт Godot и зависимости."
		_animation_button.disabled = true
		return
	_preview_holder.add_child(_model)
	LIBRARY.fit_visual(_model, 2.45)
	_anim_player = LIBRARY.first_animation(_model)
	if _anim_player != null:
		for clip in _anim_player.get_animation_list():
			if str(clip).to_lower() != "reset":
				_clips.append(clip)
		var played := LIBRARY.play_idle(_model)
		for i in range(_clips.size()):
			if str(_clips[i]) == played:
				_clip_index = i
				break
	_animation_button.disabled = _clips.is_empty()
	_refresh_details()

func _refresh_details() -> void:
	if _selected.is_empty():
		return
	var actions: Array = _selected.get("actions", [])
	var action_line := ", ".join(PackedStringArray(actions)) if not actions.is_empty() else "нет"
	var clip := str(_clips[_clip_index]) if _clip_index >= 0 and _clip_index < _clips.size() else "нет"
	_details.text = "%s\n%s · %s\nАнимация: %s · Возможные действия: %s" % [
		_selected["title"], LIBRARY.category_name(str(_selected["category"])),
		_selected["id"], clip, action_line
	]

func _next_animation() -> void:
	if _clips.is_empty() or _anim_player == null:
		return
	_clip_index = (_clip_index + 1) % _clips.size()
	_anim_player.play(_clips[_clip_index])
	_refresh_details()

func _place_in_world() -> void:
	if _selected.is_empty():
		return
	var id := str(_selected["id"])
	if PLACEMENTS.queue_asset(id):
		_return_to_world()
	else:
		_status.text = "Не удалось сохранить выбор или достигнут предел 32 размещений."

func _remove_last() -> void:
	var removed := PLACEMENTS.pop_last()
	_status.text = "Удалён последний объект: " + removed if removed != "" else "Размещённых объектов пока нет."
	_status.text += " Вернитесь в долину, чтобы увидеть изменение."

func _return_to_world() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _process(delta: float) -> void:
	if _model != null:
		_preview_holder.rotation.y = fposmod(_preview_holder.rotation.y + delta * 0.36, TAU)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_return_to_world()

