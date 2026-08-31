class_name FieldHideSpotState
extends RefCounted

const TYPE_CABINET: StringName = &"cabinet"
const TYPE_CLOSED_SHUTTER: StringName = &"closed_shutter"

var spot_id: StringName
var spot_type: StringName
var position: Vector2
var entry_position: Vector2
var blocker_rect: Rect2


func _init(
	hide_spot_id: StringName,
	hide_spot_type: StringName,
	hide_position: Vector2,
	hide_entry_position: Vector2,
	hide_blocker_rect: Rect2
) -> void:
	spot_id = hide_spot_id
	spot_type = hide_spot_type
	position = hide_position
	entry_position = hide_entry_position
	blocker_rect = hide_blocker_rect


func display_name() -> String:
	return "캐비닛" if spot_type == TYPE_CABINET else "폐점포 셔터"


func snapshot() -> Dictionary:
	return {
		"spot_id": String(spot_id),
		"spot_type": String(spot_type),
		"display_name": display_name(),
		"position": position,
		"entry_position": entry_position,
		"blocker_rect": blocker_rect,
	}
