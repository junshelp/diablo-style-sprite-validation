class_name FieldSession
extends RefCounted

const CONDITION_NORMAL: StringName = &"normal"
const CONDITION_BLACKOUT: StringName = &"blackout"

var condition: StringName
var flashlight_equipped: bool
var crowbar_count: int = 1
var fuse_count: int = 1
var seed: int
var route: FieldRoute
var object_states: Array[FieldObjectState] = []
var unextracted_parts: int = 0
var lighting_restored: bool = false
var loud_noise_occurred: bool = false
var field_simulation_paused: bool = false
var field_simulation_elapsed_seconds: float = 0.0
var active_object_id: StringName = &""
var result_application_count: int = 0
var last_interaction_result: ObjectInteractionResult
var encounter: FieldEncounterState = FieldEncounterState.new()
var hide_spots: Array[FieldHideSpotState] = []
var extraction_settled: bool = false
var extraction_point: StringName = &""


func _init(
	session_condition: StringName,
	session_flashlight_equipped: bool,
	session_seed: int,
	session_route: FieldRoute
) -> void:
	condition = session_condition
	flashlight_equipped = session_flashlight_equipped
	seed = session_seed
	route = session_route
	_initialize_object_states()
	_initialize_hide_spots()


static func is_valid_condition(value: StringName) -> bool:
	return value == CONDITION_NORMAL or value == CONDITION_BLACKOUT


func snapshot() -> Dictionary:
	var object_snapshots: Array[Dictionary] = []
	for object_state: FieldObjectState in object_states:
		object_snapshots.append(object_state.snapshot())
	var hide_spot_snapshots: Array[Dictionary] = []
	for hide_spot: FieldHideSpotState in hide_spots:
		hide_spot_snapshots.append(hide_spot.snapshot())
	return {
		"condition": String(condition),
		"flashlight_equipped": flashlight_equipped,
		"crowbar_count": crowbar_count,
		"fuse_count": fuse_count,
		"seed": seed,
		"route": route.snapshot(),
		"object_states": object_snapshots,
		"unextracted_parts": unextracted_parts,
		"lighting_restored": lighting_restored,
		"loud_noise_occurred": loud_noise_occurred,
		"field_simulation_paused": field_simulation_paused,
		"field_simulation_elapsed_seconds": field_simulation_elapsed_seconds,
		"active_object_id": String(active_object_id),
		"result_application_count": result_application_count,
		"last_interaction_result": {} if last_interaction_result == null else last_interaction_result.snapshot(),
		"encounter": encounter.snapshot(),
		"hide_spots": hide_spot_snapshots,
		"extraction_settled": extraction_settled,
		"extraction_point": String(extraction_point),
	}


func object_state(object_id: StringName) -> FieldObjectState:
	for state: FieldObjectState in object_states:
		if state.object_id == object_id:
			return state
	return null


func begin_interaction(object_id: StringName) -> bool:
	if field_simulation_paused:
		return false
	var state: FieldObjectState = object_state(object_id)
	if state == null or state.attempted:
		return false
	active_object_id = object_id
	field_simulation_paused = true
	return true


func end_interaction() -> void:
	active_object_id = &""
	field_simulation_paused = false


func advance_field_simulation(delta: float) -> void:
	if field_simulation_paused or delta <= 0.0:
		return
	field_simulation_elapsed_seconds += delta


func tool_count(tool_id: StringName) -> int:
	if tool_id == ObjectInteractionRules.TOOL_CROWBAR:
		return crowbar_count
	if tool_id == ObjectInteractionRules.TOOL_FUSE:
		return fuse_count
	return 0


func consume_tool(tool_id: StringName) -> bool:
	if tool_count(tool_id) <= 0:
		return false
	if tool_id == ObjectInteractionRules.TOOL_CROWBAR:
		crowbar_count -= 1
	elif tool_id == ObjectInteractionRules.TOOL_FUSE:
		fuse_count -= 1
	return true


func add_unextracted_parts(requested_delta: int) -> int:
	var applied_delta: int = ExtractionUpgradeRules.bounded_reward_delta(unextracted_parts, requested_delta)
	unextracted_parts += applied_delta
	return applied_delta


func can_attempt_extraction() -> bool:
	return (
		not extraction_settled
		and not field_simulation_paused
		and not encounter.hide_active
		and not encounter.hidden
		and not encounter.rescued
	)


func complete_extraction(point_type: StringName) -> void:
	extraction_settled = true
	extraction_point = point_type
	unextracted_parts = 0


func hide_spot(spot_id: StringName) -> FieldHideSpotState:
	for spot: FieldHideSpotState in hide_spots:
		if spot.spot_id == spot_id:
			return spot
	return null


func _initialize_object_states() -> void:
	var has_power_panel: bool = false
	for object_data: Dictionary in route.placeholder_objects:
		if object_data["type"] == FieldObjectState.TYPE_POWER_PANEL:
			has_power_panel = true
			break

	for index: int in range(route.placeholder_objects.size()):
		var object_data: Dictionary = route.placeholder_objects[index]
		var object_type: StringName = object_data["type"]
		if not has_power_panel and index == 0:
			object_type = FieldObjectState.TYPE_POWER_PANEL
		var object_id := StringName("%s-%02d" % [String(object_type), index])
		object_states.append(FieldObjectState.new(object_id, object_type, object_data["position"]))


func _initialize_hide_spots() -> void:
	var cabinet_position: Vector2 = route.main_module_positions[1] + Vector2(-150.0, -100.0)
	var cabinet_rect := Rect2(cabinet_position - Vector2(28.0, 52.0), Vector2(56.0, 104.0))
	hide_spots.append(FieldHideSpotState.new(
		&"cabinet-00",
		FieldHideSpotState.TYPE_CABINET,
		cabinet_position,
		cabinet_position + Vector2(0.0, 82.0),
		cabinet_rect
	))

	var shutter_position: Vector2 = route.main_module_positions[-1] + Vector2(0.0, -135.0)
	var shutter_rect := Rect2(shutter_position - Vector2(96.0, 18.0), Vector2(192.0, 36.0))
	hide_spots.append(FieldHideSpotState.new(
		&"closed-shutter-00",
		FieldHideSpotState.TYPE_CLOSED_SHUTTER,
		shutter_position,
		shutter_position + Vector2(0.0, 66.0),
		shutter_rect
	))
