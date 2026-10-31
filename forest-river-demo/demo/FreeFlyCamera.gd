extends Camera3D
## Free-flying inspection camera. No gravity, CharacterBody3D or physics impulses.
const CRUISE_SPEED: float = 12.0
const FAST_MULTIPLIER: float = 3.0
const MOUSE_SENSITIVITY: float = 0.0024
const MIN_CLEARANCE: float = 1.7
const TOP_ALTITUDE: float = 140.0
const EDGE_MARGIN: float = 4.0
const RiverTerrainScript = preload("res://demo/RiverTerrain.gd")

var _terrain: Node3D
var _yaw: float = 0.0
var _pitch: float = 0.0
var _spawn: Vector3
var _spawn_yaw: float = 0.0
var _spawn_pitch: float = 0.0

func _ready() -> void:
    current = true
    if not Engine.is_editor_hint():
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func configure(terrain_node: Node3D, spawn_position: Vector3, yaw: float, pitch: float) -> void:
    _terrain = terrain_node
    _spawn = spawn_position
    _spawn_yaw = yaw
    _spawn_pitch = pitch
    reset_view()

func reset_view() -> void:
    _yaw = _spawn_yaw
    _pitch = _spawn_pitch
    global_position = _spawn
    rotation = Vector3(_pitch, _yaw, 0.0)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            get_viewport().set_input_as_handled()
            return
        if event.physical_keycode == KEY_R:
            reset_view()
            get_viewport().set_input_as_handled()
            return
    if event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT:
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
            get_viewport().set_input_as_handled()
            return
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _yaw -= event.relative.x * MOUSE_SENSITIVITY
        _pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY,
                deg_to_rad(-85.0), deg_to_rad(85.0))
        rotation = Vector3(_pitch, _yaw, 0.0)

func _process(delta: float) -> void:
    if _terrain == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        return
    var sideways := float(int(Input.is_physical_key_pressed(KEY_D)) -
            int(Input.is_physical_key_pressed(KEY_A)))
    var forward := float(int(Input.is_physical_key_pressed(KEY_W)) -
            int(Input.is_physical_key_pressed(KEY_S)))
    var vertical := float(int(Input.is_physical_key_pressed(KEY_SPACE)) -
            int(Input.is_physical_key_pressed(KEY_C)))
    _move_from_axes(sideways, forward, vertical, minf(delta, 0.05),
            Input.is_physical_key_pressed(KEY_SHIFT))

func _move_from_axes(sideways: float, forward: float, vertical: float,
        delta: float, fast: bool) -> void:
    if _terrain == null or delta <= 0.0:
        return
    var axes := Vector3(sideways, vertical, forward)
    if axes.length_squared() > 1.0:
        axes = axes.normalized()
    var forward_vec := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
    var right_vec := Vector3(cos(_yaw), 0.0, -sin(_yaw))
    var direction := right_vec * axes.x + Vector3.UP * axes.y + forward_vec * axes.z
    var speed := CRUISE_SPEED * (FAST_MULTIPLIER if fast else 1.0)
    var target := global_position + direction * speed * delta
    var terrain_size: Vector2 = _terrain.get("size")
    var half_x: float = terrain_size.x * 0.5 - EDGE_MARGIN
    var half_z: float = terrain_size.y * 0.5 - EDGE_MARGIN
    target.x = clampf(target.x, -half_x, half_x)
    target.z = clampf(target.z, -half_z, half_z)
    var land_y: float = _terrain.call("_sample_height", target.x, target.z)
    var water_y: float = RiverTerrainScript.water_height_at(target.z)
    target.y = clampf(target.y, maxf(land_y, water_y) + MIN_CLEARANCE, TOP_ALTITUDE)
    global_position = target
