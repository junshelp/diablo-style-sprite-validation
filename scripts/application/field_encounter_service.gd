class_name FieldEncounterService
extends RefCounted

var _sight_rules: FieldSightRules


func _init(sight_rules: FieldSightRules = null) -> void:
	_sight_rules = sight_rules if sight_rules != null else FieldSightRules.new()


func try_trigger(session: FieldSession, source: StringName) -> bool:
	if session == null or session.field_simulation_paused:
		return false
	return session.encounter.try_trigger(source)


func try_trigger_from_interaction_result(
	session: FieldSession,
	result: ObjectInteractionResult
) -> bool:
	if result == null or not result.applied or not result.loud_noise:
		return false
	return try_trigger(session, FieldEncounterState.TRIGGER_LOUD_NOISE)


func begin_hide(session: FieldSession, spot_id: StringName) -> bool:
	if session == null or session.field_simulation_paused or session.hide_spot(spot_id) == null:
		return false
	return session.encounter.begin_hide(spot_id)


func tick(
	session: FieldSession,
	delta: float,
	explorer_visible: bool,
	contact: bool
) -> Dictionary:
	if session == null or session.field_simulation_paused:
		return _unchanged_result(session)
	var result: Dictionary = session.encounter.tick(delta, explorer_visible, contact)
	if bool(result["rescue_required"]):
		result["lost_unextracted_parts"] = session.unextracted_parts
		session.unextracted_parts = 0
	return result


func can_open_object_menu(session: FieldSession) -> bool:
	return session != null and not session.encounter.encounter_blocks_object_menu()


func can_see(
	observer_position: Vector2,
	forward: Vector2,
	target_position: Vector2,
	obstacle_blocked: bool
) -> bool:
	return _sight_rules.can_see(observer_position, forward, target_position, obstacle_blocked)


func _unchanged_result(session: FieldSession) -> Dictionary:
	var state_value: String = ""
	if session != null:
		state_value = String(session.encounter.state)
	return {
		"state_before": state_value,
		"state_after": state_value,
		"state_changed": false,
		"damage_applied": false,
		"damage_source": "",
		"knockback_required": false,
		"hide_ejected": false,
		"hide_completed": false,
		"encounter_resolved": false,
		"rescue_required": false,
		"lost_unextracted_parts": 0,
	}
