class_name FieldSightRules
extends RefCounted

const FOV_DEGREES: float = 120.0
const MAX_SIGHT_DISTANCE: float = 620.0


func can_see(
	observer_position: Vector2,
	forward: Vector2,
	target_position: Vector2,
	obstacle_blocked: bool
) -> bool:
	if obstacle_blocked:
		return false
	var offset: Vector2 = target_position - observer_position
	if offset.length_squared() <= 0.000001:
		return true
	if offset.length() > MAX_SIGHT_DISTANCE:
		return false
	var normalized_forward: Vector2 = forward.normalized()
	if normalized_forward == Vector2.ZERO:
		return false
	var minimum_dot: float = cos(deg_to_rad(FOV_DEGREES * 0.5))
	return normalized_forward.dot(offset.normalized()) >= minimum_dot - 0.000001
