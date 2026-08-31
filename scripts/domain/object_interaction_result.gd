class_name ObjectInteractionResult
extends RefCounted

const ACTION_BASE_SEARCH: StringName = &"base_search"
const ACTION_TOOL: StringName = &"tool"

var object_id: StringName
var object_type: StringName
var action: StringName
var tool_id: StringName
var parts_delta: int
var extra_parts: int
var consumes_tool: bool
var loud_noise: bool
var restores_lighting: bool
var used_base_fallback: bool
var reward_context: StringName
var applied: bool = false


func _init(
	result_object_id: StringName,
	result_object_type: StringName,
	result_action: StringName,
	result_tool_id: StringName,
	result_parts_delta: int,
	result_extra_parts: int,
	result_consumes_tool: bool,
	result_loud_noise: bool,
	result_restores_lighting: bool,
	result_used_base_fallback: bool,
	result_reward_context: StringName
) -> void:
	object_id = result_object_id
	object_type = result_object_type
	action = result_action
	tool_id = result_tool_id
	parts_delta = result_parts_delta
	extra_parts = result_extra_parts
	consumes_tool = result_consumes_tool
	loud_noise = result_loud_noise
	restores_lighting = result_restores_lighting
	used_base_fallback = result_used_base_fallback
	reward_context = result_reward_context


func snapshot() -> Dictionary:
	return {
		"object_id": String(object_id),
		"object_type": String(object_type),
		"action": String(action),
		"tool_id": String(tool_id),
		"parts_delta": parts_delta,
		"extra_parts": extra_parts,
		"consumes_tool": consumes_tool,
		"loud_noise": loud_noise,
		"restores_lighting": restores_lighting,
		"used_base_fallback": used_base_fallback,
		"reward_context": String(reward_context),
		"applied": applied,
	}
