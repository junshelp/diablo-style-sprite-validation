class_name ExplorerController
extends CharacterBody2D

@export var movement_speed: float = 240.0

@onready var follow_camera: Camera2D = %FollowCamera
@onready var facing_marker: Polygon2D = %Facing
@onready var minimum_visibility_light: PointLight2D = %MinimumVisibilityLight
@onready var flashlight_light: PointLight2D = %FlashlightLight

var _simulation_enabled: bool = true
var _last_facing_direction: Vector2 = Vector2.RIGHT
var _mobile_movement_vector: Vector2 = Vector2.ZERO

const FACING_DIRECTIONS: Array[Vector2] = [
	Vector2.RIGHT,
	Vector2(0.70710678, 0.70710678),
	Vector2.DOWN,
	Vector2(-0.70710678, 0.70710678),
	Vector2.LEFT,
	Vector2(-0.70710678, -0.70710678),
	Vector2.UP,
	Vector2(0.70710678, -0.70710678),
]


func _ready() -> void:
	_apply_facing_presentation()


func _physics_process(_delta: float) -> void:
	if not _simulation_enabled:
		velocity = Vector2.ZERO
		return
	var input_vector: Vector2 = _read_movement_vector()
	_update_facing(input_vector)
	velocity = velocity_for_input(input_vector)
	move_and_slide()


func velocity_for_input(input_vector: Vector2) -> Vector2:
	if input_vector.length_squared() > 1.0:
		input_vector = input_vector.normalized()
	return input_vector * movement_speed


func move_for_test(input_vector: Vector2, delta: float) -> void:
	if not _simulation_enabled:
		velocity = Vector2.ZERO
		return
	_update_facing(input_vector)
	velocity = velocity_for_input(input_vector)
	move_and_collide(velocity * delta)


func configure_visibility_lights(radial_texture: Texture2D, cone_texture: Texture2D) -> void:
	minimum_visibility_light.texture = radial_texture
	flashlight_light.texture = cone_texture
	_apply_facing_presentation()


func set_visibility_lights(minimum_enabled: bool, flashlight_enabled: bool) -> void:
	minimum_visibility_light.visible = minimum_enabled
	flashlight_light.visible = flashlight_enabled


func set_mobile_movement(input_vector: Vector2) -> void:
	if not _simulation_enabled:
		_mobile_movement_vector = Vector2.ZERO
		return
	_mobile_movement_vector = input_vector.limit_length(1.0)


func mobile_movement_vector() -> Vector2:
	return _mobile_movement_vector


func last_facing_direction() -> Vector2:
	return _last_facing_direction


func set_facing_for_test(input_vector: Vector2) -> void:
	_update_facing(input_vector)


func visibility_light_snapshot() -> Dictionary:
	return {
		"minimum_visible": minimum_visibility_light.visible,
		"minimum_energy": minimum_visibility_light.energy,
		"minimum_texture_scale": minimum_visibility_light.texture_scale,
		"minimum_shadow_enabled": minimum_visibility_light.shadow_enabled,
		"flashlight_visible": flashlight_light.visible,
		"flashlight_energy": flashlight_light.energy,
		"flashlight_texture_scale": flashlight_light.texture_scale,
		"flashlight_shadow_enabled": flashlight_light.shadow_enabled,
		"flashlight_rotation": flashlight_light.rotation,
		"facing_direction": _last_facing_direction,
	}


func set_simulation_enabled(value: bool) -> void:
	_simulation_enabled = value
	if not value:
		velocity = Vector2.ZERO
		_mobile_movement_vector = Vector2.ZERO


func simulation_enabled() -> bool:
	return _simulation_enabled


func configure_camera_bounds(bounds: Rect2) -> void:
	follow_camera.limit_left = int(bounds.position.x)
	follow_camera.limit_top = int(bounds.position.y)
	follow_camera.limit_right = int(bounds.end.x)
	follow_camera.limit_bottom = int(bounds.end.y)


func camera_bounds() -> Rect2:
	return Rect2(
		float(follow_camera.limit_left),
		float(follow_camera.limit_top),
		float(follow_camera.limit_right - follow_camera.limit_left),
		float(follow_camera.limit_bottom - follow_camera.limit_top)
	)


func _update_facing(input_vector: Vector2) -> void:
	if input_vector.length_squared() <= 0.000001:
		return
	var octant: int = int(round(input_vector.angle() / (PI / 4.0)))
	var wrapped_octant: int = ((octant % FACING_DIRECTIONS.size()) + FACING_DIRECTIONS.size()) % FACING_DIRECTIONS.size()
	_last_facing_direction = FACING_DIRECTIONS[wrapped_octant]
	_apply_facing_presentation()


func _apply_facing_presentation() -> void:
	if facing_marker != null:
		facing_marker.rotation = _last_facing_direction.angle() + PI / 2.0
	if flashlight_light != null:
		flashlight_light.rotation = _last_facing_direction.angle()


func _read_keyboard_vector() -> Vector2:
	var horizontal: float = 0.0
	var vertical: float = 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		horizontal -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		horizontal += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		vertical -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		vertical += 1.0
	return Vector2(horizontal, vertical)


func _read_movement_vector() -> Vector2:
	return (_read_keyboard_vector() + _mobile_movement_vector).limit_length(1.0)
