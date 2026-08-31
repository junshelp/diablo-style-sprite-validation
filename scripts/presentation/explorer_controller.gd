class_name ExplorerController
extends CharacterBody2D

@export var movement_speed: float = 240.0

@onready var follow_camera: Camera2D = %FollowCamera

var _simulation_enabled: bool = true


func _physics_process(_delta: float) -> void:
	if not _simulation_enabled:
		velocity = Vector2.ZERO
		return
	velocity = velocity_for_input(_read_keyboard_vector())
	move_and_slide()


func velocity_for_input(input_vector: Vector2) -> Vector2:
	if input_vector.length_squared() > 1.0:
		input_vector = input_vector.normalized()
	return input_vector * movement_speed


func move_for_test(input_vector: Vector2, delta: float) -> void:
	if not _simulation_enabled:
		velocity = Vector2.ZERO
		return
	velocity = velocity_for_input(input_vector)
	move_and_collide(velocity * delta)


func set_simulation_enabled(value: bool) -> void:
	_simulation_enabled = value
	if not value:
		velocity = Vector2.ZERO


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
