extends Camera3D
## View-only camera; no CharacterBody, gravity, collisions or fall timer.

const SPEED := 13.0
const BOOST := 3.0
const SENSITIVITY := 0.0023
const MIN_CLEARANCE := 1.75
const MAX_HEIGHT := 165.0
const MARGIN := 4.0

var _yaw := 0.0
var _pitch := 0.0
var _spawn := Vector3.ZERO
var _spawn_yaw := 0.0
var _spawn_pitch := 0.0


func _ready() -> void:
	current = true
	if not Engine.is_editor_hint():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func configure(spawn_position: Vector3, yaw: float, pitch: float) -> void:
	_spawn = spawn_position
	_spawn_yaw = yaw
	_spawn_pitch = pitch
	reset_view()


func reset_view() -> void:
	_yaw = _spawn_yaw
	_pitch = _spawn_pitch
	position = _spawn
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_R:
			reset_view()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * SENSITIVITY, deg_to_rad(-85.0), deg_to_rad(85.0))
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var side := float(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A)))
	var forward := float(int(Input.is_physical_key_pressed(KEY_W)) - int(Input.is_physical_key_pressed(KEY_S)))
	var up := float(int(Input.is_physical_key_pressed(KEY_SPACE)) - int(Input.is_physical_key_pressed(KEY_C)))
	move_by_axes(side, forward, up, minf(delta, 0.06), Input.is_physical_key_pressed(KEY_SHIFT))


func move_by_axes(side: float, forward: float, up: float, delta: float, boost: bool) -> void:
	var desired := Vector3(side, up, forward)
	if desired.length_squared() > 1.0:
		desired = desired.normalized()
	var direction := Vector3(cos(_yaw), 0.0, -sin(_yaw)) * desired.x
	direction += Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * desired.z
	direction += Vector3.UP * desired.y
	var next := position + direction * SPEED * (BOOST if boost else 1.0) * delta
	next.x = clampf(next.x, -142.0 + MARGIN, 142.0 - MARGIN)
	next.z = clampf(next.z, -142.0 + MARGIN, 142.0 - MARGIN)
	var ground_y: float = get_parent().call("height_at", next.x, next.z)
	next.y = clampf(next.y, maxf(ground_y, 0.15) + MIN_CLEARANCE, MAX_HEIGHT)
	position = next
