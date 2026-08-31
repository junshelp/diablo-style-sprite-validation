class_name ObjectInteractionRules
extends RefCounted

const TOOL_CROWBAR: StringName = &"crowbar"
const TOOL_FUSE: StringName = &"fuse"

const REWARD_CONTEXT_NORMAL: StringName = &"normal"
const REWARD_CONTEXT_BLACKOUT_FLASHLIGHT: StringName = &"blackout_flashlight"
const REWARD_CONTEXT_BLACKOUT_UNPREPARED: StringName = &"blackout_unprepared"
const REWARD_CONTEXT_LIGHTING_RESTORED: StringName = &"lighting_restored"

const BASE_REWARD_TABLE: Dictionary = {
	REWARD_CONTEXT_NORMAL: 2,
	REWARD_CONTEXT_BLACKOUT_FLASHLIGHT: 1,
	REWARD_CONTEXT_BLACKOUT_UNPREPARED: 0,
	REWARD_CONTEXT_LIGHTING_RESTORED: 2,
}

const REACTION_TABLE: Dictionary = {
	"locker|crowbar": {
		"reaction": &"crowbar_locker",
		"consumes_tool": false,
		"loud_noise": true,
		"restores_lighting": false,
	},
	"power_panel|fuse": {
		"reaction": &"fuse_power_panel",
		"consumes_tool": true,
		"loud_noise": false,
		"restores_lighting": true,
	},
}


func prepare_base_search(session: FieldSession, object_state: FieldObjectState) -> ObjectInteractionResult:
	var context: StringName = reward_context_for(session)
	return ObjectInteractionResult.new(
		object_state.object_id,
		object_state.object_type,
		ObjectInteractionResult.ACTION_BASE_SEARCH,
		&"",
		int(BASE_REWARD_TABLE[context]),
		0,
		false,
		false,
		false,
		false,
		context
	)


func prepare_tool(
	session: FieldSession,
	object_state: FieldObjectState,
	tool_id: StringName,
	random: RandomPort
) -> ObjectInteractionResult:
	var reaction_key: String = "%s|%s" % [String(object_state.object_type), String(tool_id)]
	if not REACTION_TABLE.has(reaction_key):
		var fallback: ObjectInteractionResult = prepare_base_search(session, object_state)
		fallback.action = ObjectInteractionResult.ACTION_TOOL
		fallback.tool_id = tool_id
		fallback.used_base_fallback = true
		return fallback

	var reaction: Dictionary = REACTION_TABLE[reaction_key]
	if reaction["reaction"] == &"crowbar_locker":
		var context: StringName = reward_context_for(session)
		var extra_parts: int = 1 if random.next_int(2) == 0 else 0
		return ObjectInteractionResult.new(
			object_state.object_id,
			object_state.object_type,
			ObjectInteractionResult.ACTION_TOOL,
			tool_id,
			int(BASE_REWARD_TABLE[context]) + extra_parts,
			extra_parts,
			false,
			true,
			false,
			false,
			context
		)

	return ObjectInteractionResult.new(
		object_state.object_id,
		object_state.object_type,
		ObjectInteractionResult.ACTION_TOOL,
		tool_id,
		0,
		0,
		bool(reaction["consumes_tool"]),
		bool(reaction["loud_noise"]),
		bool(reaction["restores_lighting"]),
		false,
		reward_context_for(session)
	)


func reward_context_for(session: FieldSession) -> StringName:
	if session.lighting_restored:
		return REWARD_CONTEXT_LIGHTING_RESTORED
	if session.condition == FieldSession.CONDITION_NORMAL:
		return REWARD_CONTEXT_NORMAL
	if session.flashlight_equipped:
		return REWARD_CONTEXT_BLACKOUT_FLASHLIGHT
	return REWARD_CONTEXT_BLACKOUT_UNPREPARED
