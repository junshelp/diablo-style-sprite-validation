class_name FieldRoute
extends RefCounted

var seed: int
var main_module_ids: Array[StringName]
var branch_module_id: StringName
var branch_main_index: int
var branch_direction: int
var entrance_position: Vector2
var endpoint_position: Vector2
var main_module_positions: Array[Vector2]
var branch_position: Vector2
var placeholder_objects: Array[Dictionary]
var bounds: Rect2
var connections: Array[Vector2i]


func _init(
	route_seed: int,
	route_main_module_ids: Array[StringName],
	route_branch_module_id: StringName,
	route_branch_main_index: int,
	route_branch_direction: int,
	route_entrance_position: Vector2,
	route_endpoint_position: Vector2,
	route_main_module_positions: Array[Vector2],
	route_branch_position: Vector2,
	route_placeholder_objects: Array[Dictionary],
	route_bounds: Rect2,
	route_connections: Array[Vector2i]
) -> void:
	seed = route_seed
	main_module_ids = route_main_module_ids.duplicate()
	branch_module_id = route_branch_module_id
	branch_main_index = route_branch_main_index
	branch_direction = route_branch_direction
	entrance_position = route_entrance_position
	endpoint_position = route_endpoint_position
	main_module_positions = route_main_module_positions.duplicate()
	branch_position = route_branch_position
	placeholder_objects = route_placeholder_objects.duplicate(true)
	bounds = route_bounds
	connections = route_connections.duplicate()


func module_count() -> int:
	return main_module_ids.size() + 1


func branch_count() -> int:
	return 1


func entrance_node_index() -> int:
	return 0


func endpoint_node_index() -> int:
	return main_module_ids.size() + 1


func branch_node_index() -> int:
	return endpoint_node_index() + 1


func is_entrance_to_endpoint_reachable() -> bool:
	return _is_reachable(entrance_node_index(), endpoint_node_index())


func snapshot() -> Dictionary:
	var module_names: Array[String] = []
	for module_id: StringName in main_module_ids:
		module_names.append(String(module_id))

	var object_snapshots: Array[Dictionary] = []
	for object_data: Dictionary in placeholder_objects:
		object_snapshots.append(object_data.duplicate(true))

	return {
		"seed": seed,
		"main_module_ids": module_names,
		"branch_module_id": String(branch_module_id),
		"branch_main_index": branch_main_index,
		"branch_direction": branch_direction,
		"entrance_position": entrance_position,
		"endpoint_position": endpoint_position,
		"main_module_positions": main_module_positions.duplicate(),
		"branch_position": branch_position,
		"placeholder_objects": object_snapshots,
		"bounds": bounds,
		"connections": connections.duplicate(),
	}


func _is_reachable(start_node: int, target_node: int) -> bool:
	var pending: Array[int] = [start_node]
	var visited: Dictionary = {start_node: true}
	while not pending.is_empty():
		var current: int = pending.pop_front()
		if current == target_node:
			return true
		for connection: Vector2i in connections:
			var neighbor: int = -1
			if connection.x == current:
				neighbor = connection.y
			elif connection.y == current:
				neighbor = connection.x
			if neighbor >= 0 and not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	return false
