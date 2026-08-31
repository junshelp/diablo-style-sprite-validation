class_name FieldEncounterState
extends RefCounted

const STATE_DORMANT: StringName = &"dormant"
const STATE_WARNING: StringName = &"warning"
const STATE_CHASING: StringName = &"chasing"
const STATE_SEARCHING: StringName = &"searching"
const STATE_RESOLVED: StringName = &"resolved"

const TRIGGER_DEEP_ENTRY: StringName = &"deep_entry"
const TRIGGER_LOUD_NOISE: StringName = &"loud_noise"

const DAMAGE_CONTACT: StringName = &"contact"
const DAMAGE_WITNESSED_HIDE: StringName = &"witnessed_hide"

const MAX_HP: int = 3
const DAMAGE_AMOUNT: int = 1
const WARNING_DURATION_SECONDS: float = 1.2
const HIDE_ENTRY_DURATION_SECONDS: float = 1.0
const SEARCHING_DURATION_SECONDS: float = 1.4
const DAMAGE_INVULNERABILITY_SECONDS: float = 0.9
const WITNESSED_GRACE_SECONDS: float = 0.75
const TIMER_EPSILON_SECONDS: float = 0.00001

var state: StringName = STATE_DORMANT
var state_elapsed_seconds: float = 0.0
var triggered_once: bool = false
var trigger_source: StringName = &""
var hp: int = MAX_HP
var invulnerability_remaining_seconds: float = 0.0
var grace_remaining_seconds: float = 0.0
var hide_active: bool = false
var hidden: bool = false
var hide_progress_seconds: float = 0.0
var hide_witnessed: bool = false
var active_hide_spot_id: StringName = &""
var damage_count: int = 0
var last_damage_source: StringName = &""
var rescued: bool = false


func try_trigger(source: StringName) -> bool:
	if triggered_once or state != STATE_DORMANT or rescued:
		return false
	if source != TRIGGER_DEEP_ENTRY and source != TRIGGER_LOUD_NOISE:
		return false
	triggered_once = true
	trigger_source = source
	_transition_to(STATE_WARNING)
	return true


func begin_hide(spot_id: StringName) -> bool:
	if state != STATE_CHASING or hide_active or hidden or rescued or spot_id == &"":
		return false
	hide_active = true
	hide_progress_seconds = 0.0
	hide_witnessed = false
	active_hide_spot_id = spot_id
	return true


func tick(delta: float, explorer_visible: bool, contact: bool) -> Dictionary:
	var result: Dictionary = {
		"state_before": String(state),
		"state_after": String(state),
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
	if delta <= 0.0 or rescued:
		return result

	invulnerability_remaining_seconds = _decrement_timer(invulnerability_remaining_seconds, delta)
	grace_remaining_seconds = _decrement_timer(grace_remaining_seconds, delta)
	state_elapsed_seconds += delta

	match state:
		STATE_WARNING:
			if state_elapsed_seconds >= WARNING_DURATION_SECONDS:
				_transition_to(STATE_CHASING)
				result["state_changed"] = true
		STATE_CHASING:
			if hide_active:
				hide_witnessed = hide_witnessed or explorer_visible
				hide_progress_seconds += delta
				if hide_progress_seconds >= HIDE_ENTRY_DURATION_SECONDS:
					if hide_witnessed:
						_apply_damage(DAMAGE_WITNESSED_HIDE, result)
						hide_active = false
						hidden = false
						hide_progress_seconds = 0.0
						active_hide_spot_id = &""
						grace_remaining_seconds = WITNESSED_GRACE_SECONDS
						result["hide_ejected"] = true
					else:
						hide_active = false
						hidden = true
						result["hide_completed"] = true
						_transition_to(STATE_SEARCHING)
						result["state_changed"] = true
			elif contact and invulnerability_remaining_seconds <= 0.0 and grace_remaining_seconds <= 0.0:
				_apply_damage(DAMAGE_CONTACT, result)
				result["knockback_required"] = true
		STATE_SEARCHING:
			if state_elapsed_seconds >= SEARCHING_DURATION_SECONDS:
				hidden = false
				active_hide_spot_id = &""
				_transition_to(STATE_RESOLVED)
				result["state_changed"] = true
				result["encounter_resolved"] = true

	result["state_after"] = String(state)
	result["rescue_required"] = rescued
	return result


func encounter_blocks_object_menu() -> bool:
	return state == STATE_WARNING or state == STATE_CHASING or state == STATE_SEARCHING


func snapshot() -> Dictionary:
	return {
		"state": String(state),
		"state_elapsed_seconds": state_elapsed_seconds,
		"triggered_once": triggered_once,
		"trigger_source": String(trigger_source),
		"hp": hp,
		"max_hp": MAX_HP,
		"invulnerability_remaining_seconds": invulnerability_remaining_seconds,
		"grace_remaining_seconds": grace_remaining_seconds,
		"hide_active": hide_active,
		"hidden": hidden,
		"hide_progress_seconds": hide_progress_seconds,
		"hide_witnessed": hide_witnessed,
		"active_hide_spot_id": String(active_hide_spot_id),
		"damage_count": damage_count,
		"last_damage_source": String(last_damage_source),
		"rescued": rescued,
	}


func _apply_damage(source: StringName, result: Dictionary) -> void:
	hp = maxi(0, hp - DAMAGE_AMOUNT)
	damage_count += 1
	last_damage_source = source
	invulnerability_remaining_seconds = DAMAGE_INVULNERABILITY_SECONDS
	result["damage_applied"] = true
	result["damage_source"] = String(source)
	if hp == 0:
		rescued = true


func _transition_to(next_state: StringName) -> void:
	state = next_state
	state_elapsed_seconds = 0.0


func _decrement_timer(value: float, delta: float) -> float:
	var remaining := maxf(0.0, value - delta)
	return 0.0 if remaining <= TIMER_EPSILON_SECONDS else remaining
