class_name ChaseEntityView
extends CharacterBody2D

@export var chase_speed: float = 178.0

@onready var body_shape: Polygon2D = %BodyShape
@onready var facing_mark: Polygon2D = %FacingMark
@onready var fov_debug_cone: Polygon2D = %FovDebugCone

var forward_vector: Vector2 = Vector2.LEFT
var _simulation_enabled: bool = false
var _debug_fov_enabled: bool = false


func _ready() -> void:
	_build_debug_cone()
	set_active(false)


func set_active(value: bool) -> void:
	visible = value
	_simulation_enabled = value
	if not value:
		velocity = Vector2.ZERO
	fov_debug_cone.visible = value and _debug_fov_enabled


func is_active() -> bool:
	return visible and _simulation_enabled


func set_simulation_enabled(value: bool) -> void:
	_simulation_enabled = value and visible
	if not _simulation_enabled:
		velocity = Vector2.ZERO


func set_forward(value: Vector2) -> void:
	if value.length_squared() <= 0.000001:
		return
	forward_vector = value.normalized()
	body_shape.rotation = forward_vector.angle()
	facing_mark.rotation = forward_vector.angle()
	fov_debug_cone.rotation = forward_vector.angle()


func chase_toward(target_position: Vector2, delta: float) -> void:
	if not is_active() or delta <= 0.0:
		velocity = Vector2.ZERO
		return
	var direction: Vector2 = global_position.direction_to(target_position)
	if direction == Vector2.ZERO:
		velocity = Vector2.ZERO
		return
	set_forward(direction)
	velocity = direction * chase_speed
	move_and_collide(velocity * delta)


func stop_motion() -> void:
	velocity = Vector2.ZERO


func set_debug_fov_visible(value: bool) -> void:
	_debug_fov_enabled = value
	fov_debug_cone.visible = visible and value


func debug_fov_visible() -> bool:
	return fov_debug_cone.visible


func set_mode(encounter_state: StringName) -> void:
	if encounter_state == FieldEncounterState.STATE_SEARCHING:
		body_shape.color = Color(0.72, 0.45, 0.16, 1.0)
	else:
		body_shape.color = Color(0.62, 0.08, 0.075, 1.0)


func _build_debug_cone() -> void:
	var points := PackedVector2Array([Vector2.ZERO])
	for index: int in range(13):
		var angle_degrees: float = -FieldSightRules.FOV_DEGREES * 0.5 + FieldSightRules.FOV_DEGREES * float(index) / 12.0
		points.append(Vector2.RIGHT.rotated(deg_to_rad(angle_degrees)) * FieldSightRules.MAX_SIGHT_DISTANCE)
	fov_debug_cone.polygon = points
