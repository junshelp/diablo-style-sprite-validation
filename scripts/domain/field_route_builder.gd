class_name FieldRouteBuilder
extends RefCounted

const MAIN_MODULE_COUNT: int = 4
const MODULE_SPACING: float = 500.0
const MAIN_Y: float = 450.0
const ENTRANCE_POSITION: Vector2 = Vector2(180.0, MAIN_Y)
const ROUTE_BOUNDS: Rect2 = Rect2(0.0, 0.0, 2800.0, 900.0)
const MAIN_MODULE_LIBRARY: Array[StringName] = [
	&"closed_shops",
	&"service_hall",
	&"storage_row",
]

var _random: RandomPort


func _init(random: RandomPort) -> void:
	_random = random


func build(seed: int) -> FieldRoute:
	_random.set_seed(seed)
	var branch_main_index: int = 1 + _random.next_int(2)
	var branch_direction: int = -1 if _random.next_int(2) == 0 else 1
	var main_module_ids: Array[StringName] = []
	var main_positions: Array[Vector2] = []
	var placeholder_objects: Array[Dictionary] = []

	for index: int in range(MAIN_MODULE_COUNT):
		var module_id: StringName = &"junction" if index == branch_main_index else MAIN_MODULE_LIBRARY[_random.next_int(MAIN_MODULE_LIBRARY.size())]
		var position := Vector2(620.0 + MODULE_SPACING * float(index), MAIN_Y)
		main_module_ids.append(module_id)
		main_positions.append(position)
		var object_type: StringName = &"locker" if _random.next_int(2) == 0 else &"power_panel"
		var horizontal_offset: float = -90.0 + float(_random.next_int(4)) * 60.0
		var vertical_offset: float = -105.0 if _random.next_int(2) == 0 else 105.0
		placeholder_objects.append({
			"type": object_type,
			"position": position + Vector2(horizontal_offset, vertical_offset),
		})

	var branch_position: Vector2 = main_positions[branch_main_index] + Vector2(0.0, 300.0 * float(branch_direction))
	placeholder_objects.append({
		"type": &"locker",
		"position": branch_position + Vector2(80.0, 0.0),
	})
	var endpoint_position := Vector2(2620.0, MAIN_Y)
	var connections: Array[Vector2i] = []
	for node_index: int in range(MAIN_MODULE_COUNT + 1):
		connections.append(Vector2i(node_index, node_index + 1))
	connections.append(Vector2i(branch_main_index + 1, MAIN_MODULE_COUNT + 2))

	return FieldRoute.new(
		seed,
		main_module_ids,
		&"service_branch",
		branch_main_index,
		branch_direction,
		ENTRANCE_POSITION,
		endpoint_position,
		main_positions,
		branch_position,
		placeholder_objects,
		ROUTE_BOUNDS,
		connections
	)
