class_name FieldInteractionService
extends RefCounted

var _random: RandomPort
var _rules: ObjectInteractionRules


func _init(random: RandomPort, rules: ObjectInteractionRules = null) -> void:
	_random = random
	_rules = rules if rules != null else ObjectInteractionRules.new()


func begin_interaction(session: FieldSession, object_id: StringName) -> bool:
	if session == null:
		return false
	return session.begin_interaction(object_id)


func cancel_interaction(session: FieldSession) -> bool:
	if session == null or not session.field_simulation_paused:
		return false
	session.end_interaction()
	return true


func prepare_base_search(session: FieldSession) -> ObjectInteractionResult:
	var object_state: FieldObjectState = _active_object(session)
	if object_state == null:
		return null
	return _rules.prepare_base_search(session, object_state)


func prepare_tool(session: FieldSession, tool_id: StringName) -> ObjectInteractionResult:
	var object_state: FieldObjectState = _active_object(session)
	if object_state == null or session.tool_count(tool_id) <= 0:
		return null
	_random.set_seed(_interaction_seed(session.seed, object_state.object_id, tool_id))
	return _rules.prepare_tool(session, object_state, tool_id, _random)


func apply_result(session: FieldSession, result: ObjectInteractionResult) -> bool:
	if session == null or result == null or result.applied:
		return false
	if not session.field_simulation_paused or session.active_object_id != result.object_id:
		return false
	var object_state: FieldObjectState = session.object_state(result.object_id)
	if object_state == null or object_state.attempted:
		return false

	# The menu owner closes first. The application boundary resumes field simulation
	# before committing the single interaction result.
	session.end_interaction()
	object_state.mark_attempted()
	result.parts_delta = session.add_unextracted_parts(result.parts_delta)
	if result.consumes_tool:
		session.consume_tool(result.tool_id)
	if result.loud_noise:
		session.loud_noise_occurred = true
	if result.restores_lighting:
		session.lighting_restored = true
	result.applied = true
	session.last_interaction_result = result
	session.result_application_count += 1
	return true


func base_reward_table() -> Dictionary:
	return ObjectInteractionRules.BASE_REWARD_TABLE.duplicate(true)


func _active_object(session: FieldSession) -> FieldObjectState:
	if session == null or not session.field_simulation_paused:
		return null
	return session.object_state(session.active_object_id)


func _interaction_seed(session_seed: int, object_id: StringName, tool_id: StringName) -> int:
	var value: int = session_seed & 0x7fffffff
	var identity: String = "%s|%s" % [String(object_id), String(tool_id)]
	for byte_value: int in identity.to_utf8_buffer():
		value = int((value * 33 + byte_value) & 0x7fffffff)
	return value
