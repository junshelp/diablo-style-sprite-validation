class_name FieldObjectState
extends RefCounted

const TYPE_LOCKER: StringName = &"locker"
const TYPE_POWER_PANEL: StringName = &"power_panel"

var object_id: StringName
var object_type: StringName
var position: Vector2
var attempted: bool = false


func _init(state_id: StringName, state_type: StringName, state_position: Vector2) -> void:
	object_id = state_id
	object_type = state_type
	position = state_position


func display_name() -> String:
	return "사물함" if object_type == TYPE_LOCKER else "배전반"


func mark_attempted() -> void:
	attempted = true


func snapshot() -> Dictionary:
	return {
		"object_id": String(object_id),
		"object_type": String(object_type),
		"display_name": display_name(),
		"position": position,
		"attempted": attempted,
	}
