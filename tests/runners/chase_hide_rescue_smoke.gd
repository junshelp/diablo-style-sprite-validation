extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EPSILON: float = 0.001
const EXPECTED_SCHEMA_FIELDS: Array[String] = [
	"schema_version",
	"departure_supply_units",
	"facility_parts",
	"producer_upgraded",
	"last_saved_unix_ms",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_one_shot_trigger_and_state_timer_edges()
	_test_fov_geometry()
	_test_successful_and_witnessed_hide()
	_test_contact_damage_invulnerability_and_rescue()
	_test_menu_pause_gates_encounter()
	await _test_scene_chase_hide_rescue_integration()
	await process_frame
	await create_timer(0.25).timeout
	_finish()


func _test_one_shot_trigger_and_state_timer_edges() -> void:
	var service := FieldEncounterService.new()
	var deep_first: FieldSession = _new_session(4_242)
	_check(deep_first.encounter.state == FieldEncounterState.STATE_DORMANT, "new session encounter is dormant")
	_check(deep_first.encounter.hp == 3 and not deep_first.encounter.triggered_once, "new session starts at HP 3 with no encounter")
	_check(service.try_trigger(deep_first, FieldEncounterState.TRIGGER_DEEP_ENTRY), "deep entry triggers the dormant encounter")
	_check(not service.try_trigger(deep_first, FieldEncounterState.TRIGGER_LOUD_NOISE), "later loud noise cannot retrigger the same session")
	_check(deep_first.encounter.trigger_source == FieldEncounterState.TRIGGER_DEEP_ENTRY, "first trigger source is retained")
	service.tick(deep_first, FieldEncounterState.WARNING_DURATION_SECONDS - EPSILON, false, false)
	_check(deep_first.encounter.state == FieldEncounterState.STATE_WARNING, "warning remains before its named duration")
	service.tick(deep_first, EPSILON, false, false)
	_check(deep_first.encounter.state == FieldEncounterState.STATE_CHASING, "warning transitions to chasing at its duration")

	var noise_first: FieldSession = _new_session(4_242)
	var locker: FieldObjectState = _first_object(noise_first, FieldObjectState.TYPE_LOCKER)
	var interaction_service := FieldInteractionService.new(SeededRandom.new())
	interaction_service.begin_interaction(noise_first, locker.object_id)
	var crowbar_result: ObjectInteractionResult = interaction_service.prepare_tool(noise_first, ObjectInteractionRules.TOOL_CROWBAR)
	interaction_service.apply_result(noise_first, crowbar_result)
	_check(service.try_trigger_from_interaction_result(noise_first, crowbar_result), "applied crowbar loud noise triggers a second fixture")
	_check(noise_first.encounter.trigger_source == FieldEncounterState.TRIGGER_LOUD_NOISE, "crowbar result records loud-noise as the first trigger")
	_check(not service.try_trigger(noise_first, FieldEncounterState.TRIGGER_DEEP_ENTRY), "later deep entry cannot replace the noise trigger")


func _test_fov_geometry() -> void:
	var sight := FieldSightRules.new()
	var origin := Vector2.ZERO
	var forward := Vector2.RIGHT
	_check(sight.can_see(origin, forward, Vector2(300.0, 0.0), false), "front target is inside the 120 degree FOV")
	var boundary_target := Vector2.RIGHT.rotated(deg_to_rad(60.0)) * 300.0
	var outside_target := Vector2.RIGHT.rotated(deg_to_rad(60.5)) * 300.0
	_check(sight.can_see(origin, forward, boundary_target, false), "60 degree half-angle boundary is visible")
	_check(not sight.can_see(origin, forward, outside_target, false), "target just outside the half-angle is not visible")
	_check(not sight.can_see(origin, forward, Vector2(0.0, 300.0), false), "side target is outside the cone")
	_check(not sight.can_see(origin, forward, Vector2(-300.0, 0.0), false), "back target is outside the cone")
	_check(not sight.can_see(origin, forward, Vector2(300.0, 0.0), true), "explicit obstacle blocks an otherwise visible target")
	_check(not sight.can_see(origin, forward, Vector2(FieldSightRules.MAX_SIGHT_DISTANCE + 1.0, 0.0), false), "target beyond named sight range is not visible")


func _test_successful_and_witnessed_hide() -> void:
	var service := FieldEncounterService.new()
	var successful: FieldSession = _new_session(501)
	service.try_trigger(successful, FieldEncounterState.TRIGGER_DEEP_ENTRY)
	service.tick(successful, FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	_check(service.begin_hide(successful, successful.hide_spots[0].spot_id), "chasing explorer can begin cabinet hide")
	service.tick(successful, FieldEncounterState.HIDE_ENTRY_DURATION_SECONDS - EPSILON, false, false)
	_check(successful.encounter.state == FieldEncounterState.STATE_CHASING and successful.encounter.hide_active, "hide entry remains in progress before its boundary")
	var completed: Dictionary = service.tick(successful, EPSILON, false, false)
	_check(bool(completed["hide_completed"]) and successful.encounter.state == FieldEncounterState.STATE_SEARCHING, "unwitnessed full entry begins searching")
	service.tick(successful, FieldEncounterState.SEARCHING_DURATION_SECONDS - EPSILON, false, false)
	_check(successful.encounter.state == FieldEncounterState.STATE_SEARCHING, "search remains active before its boundary")
	var resolved: Dictionary = service.tick(successful, EPSILON, false, false)
	_check(bool(resolved["encounter_resolved"]) and successful.encounter.state == FieldEncounterState.STATE_RESOLVED, "searching resolves exactly at its named duration")
	_check(not service.try_trigger(successful, FieldEncounterState.TRIGGER_LOUD_NOISE), "resolved encounter never respawns")

	var witnessed: FieldSession = _new_session(502)
	service.try_trigger(witnessed, FieldEncounterState.TRIGGER_DEEP_ENTRY)
	service.tick(witnessed, FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	_check(service.begin_hide(witnessed, witnessed.hide_spots[1].spot_id), "chasing explorer can begin shutter hide")
	service.tick(witnessed, 0.2, true, false)
	_check(witnessed.encounter.hide_witnessed, "one sight sample latches witnessed entry")
	var ejected: Dictionary = service.tick(witnessed, FieldEncounterState.HIDE_ENTRY_DURATION_SECONDS - 0.2, false, false)
	_check(bool(ejected["hide_ejected"]) and bool(ejected["damage_applied"]), "latched witness causes deterministic damage and ejection")
	_check(witnessed.encounter.hp == 2 and witnessed.encounter.state == FieldEncounterState.STATE_CHASING, "witnessed hide removes exactly one HP and continues chasing")
	_check(witnessed.encounter.grace_remaining_seconds > 0.0, "witnessed ejection grants named grace")
	var grace_contact: Dictionary = service.tick(witnessed, EPSILON, false, true)
	_check(not bool(grace_contact["damage_applied"]) and witnessed.encounter.hp == 2, "grace prevents immediate post-ejection contact damage")


func _test_contact_damage_invulnerability_and_rescue() -> void:
	var service := FieldEncounterService.new()
	var session: FieldSession = _new_session(601)
	session.unextracted_parts = 5
	service.try_trigger(session, FieldEncounterState.TRIGGER_DEEP_ENTRY)
	service.tick(session, FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	var first_hit: Dictionary = service.tick(session, EPSILON, true, true)
	_check(bool(first_hit["damage_applied"]) and bool(first_hit["knockback_required"]), "contact applies one damage and requests knockback")
	_check(session.encounter.hp == 2, "first contact changes HP 3 to 2")
	var protected_hit: Dictionary = service.tick(session, FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS - EPSILON, true, true)
	_check(not bool(protected_hit["damage_applied"]) and session.encounter.hp == 2, "invulnerability blocks repeated contact before boundary")
	var second_hit: Dictionary = service.tick(session, EPSILON, true, true)
	_check(bool(second_hit["damage_applied"]) and session.encounter.hp == 1, "contact at invulnerability boundary changes HP 2 to 1")
	var final_hit: Dictionary = service.tick(session, FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS, true, true)
	_check(bool(final_hit["damage_applied"]) and bool(final_hit["rescue_required"]), "third unprotected contact changes HP 1 to 0 and requests rescue")
	_check(session.encounter.hp == 0 and session.encounter.damage_count == 3, "all damage entries are exactly one HP")
	_check(int(final_hit["lost_unextracted_parts"]) == 5 and session.unextracted_parts == 0, "rescue boundary discards only current unextracted parts")


func _test_menu_pause_gates_encounter() -> void:
	var service := FieldEncounterService.new()
	var session: FieldSession = _new_session(701)
	service.try_trigger(session, FieldEncounterState.TRIGGER_DEEP_ENTRY)
	service.tick(session, FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	service.begin_hide(session, session.hide_spots[0].spot_id)
	var before: Dictionary = session.encounter.snapshot()
	session.field_simulation_paused = true
	var paused_result: Dictionary = service.tick(session, 100.0, true, true)
	var after: Dictionary = session.encounter.snapshot()
	_check(before == after, "field menu pause freezes entity state, chase timers, hide progress and witnessed latch")
	_check(not bool(paused_result["damage_applied"]) and not bool(paused_result["state_changed"]), "paused encounter tick produces no damage or transition")
	var unpaused_session := _new_session(702)
	_check(service.try_trigger(unpaused_session, FieldEncounterState.TRIGGER_DEEP_ENTRY), "unpaused fixture remains triggerable")


func _test_scene_chase_hide_rescue_integration() -> void:
	get_root().size = Vector2i(960, 540)
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	_check(packed_scene != null, "main scene loads for chase integration")
	if packed_scene == null:
		return

	var now_ms: int = 1_800_000_000
	var profile := HomeProfile.new(1.5, 7, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	var home_service := HomeProfileService.new(clock, storage)
	var app_root := packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", home_service)
	app_root.call("configure_expedition_service", ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.call("configure_field_interaction_service", FieldInteractionService.new(SeededRandom.new()))
	app_root.call("configure_field_encounter_service", FieldEncounterService.new())
	get_root().add_child(app_root)
	await process_frame
	_check(bool(app_root.call("attempt_departure", FieldSession.CONDITION_NORMAL, true, 4_242)), "first field departure succeeds")
	await process_frame
	await physics_frame
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var menu: ObjectInteractionMenu = field_view.interaction_menu_node()
	var initial_entity_position: Vector2 = field_view.entity_position()
	field_view.advance_field_frame_for_test(0.5)
	_check(field_view.encounter_snapshot()["state"] == "dormant", "early field remains dormant without patrol")
	_check(not field_view.entity_visible() and field_view.entity_position() == initial_entity_position, "entity is hidden and stationary before trigger")
	_check(not field_view.fov_debug_visible(), "FOV debug cone is hidden in normal play")

	var hide_spots: Array[Dictionary] = field_view.hide_spot_snapshots()
	_check(hide_spots.size() == 2, "route exposes two pre-trigger hiding spots")
	_check(_has_hide_type(hide_spots, "cabinet") and _has_hide_type(hide_spots, "closed_shutter"), "cabinet and closed shutter are both available before chase")
	var clear_origin := Vector2(300.0, 450.0)
	var clear_target := Vector2(500.0, 450.0)
	_check(field_view.sight_between_for_test(clear_origin, Vector2.RIGHT, clear_target), "unobstructed route ray remains visible")
	for blocker_name: StringName in [&"wall", &"column", &"closed_shutter"]:
		var blocker: Rect2 = field_view.named_sight_blocker(blocker_name)
		_check(blocker.has_area(), "%s sight blocker exists" % String(blocker_name))
		if blocker.has_area():
			_check(not _probe_across_blocker(field_view, blocker), "%s blocks Physics2D line of sight" % String(blocker_name))

	var panel_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_POWER_PANEL)
	_check(panel_id != &"" and field_view.open_object_interaction_for_test(panel_id), "pre-trigger object menu opens")
	var paused_encounter: Dictionary = field_view.encounter_snapshot()
	field_view.advance_field_frame_for_test(5.0)
	_check(field_view.encounter_snapshot() == paused_encounter, "open menu freezes encounter snapshot in scene integration")
	_check(not paused, "menu does not pause SceneTree")
	clock.advance(HomeProfile.BASE_INTERVAL_MS / 2)
	_check(bool(app_root.call("refresh_home_profile")), "home real-time refresh continues during encounter-gated menu pause")
	_check_float(float((app_root.call("home_profile_snapshot") as Dictionary)["departure_supply_units"]), 1.0, "home supply advances 0.5 to 1.0 while field menu is open")
	menu.go_back()

	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(locker_id != &"" and field_view.open_object_interaction_for_test(locker_id), "locker menu opens before encounter")
	menu.show_item_stage()
	menu.select_tool_for_test(ObjectInteractionRules.TOOL_CROWBAR)
	var warning_snapshot: Dictionary = field_view.encounter_snapshot()
	_check(warning_snapshot["state"] == "warning" and warning_snapshot["trigger_source"] == "loud_noise", "crowbar result starts warning after menu closes")
	_check(not menu.visible and not bool((app_root.call("active_field_session_snapshot") as Dictionary)["field_simulation_paused"]), "noise warning preserves close-before-apply and resumed field")
	_check(not field_view.entity_visible(), "entity remains absent during warning")

	var unattempted_id: StringName = _first_unattempted_object_id(field_view.object_snapshots())
	_check(field_view.move_explorer_to_object(unattempted_id), "test moves beside a second object during warning")
	_check(not field_view.open_object_interaction_for_test(unattempted_id), "warning rejects object menu entry")
	field_view.advance_encounter_for_test(FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	_check(field_view.encounter_snapshot()["state"] == "chasing" and field_view.entity_visible(), "warning completes into one visible chasing entity")
	_check(not field_view.open_object_interaction_for_test(unattempted_id), "chasing rejects object menu entry")

	var cabinet_id: StringName = field_view.move_explorer_to_hide_spot_type(FieldHideSpotState.TYPE_CABINET)
	_check(cabinet_id != &"", "explorer can approach route-bound cabinet")
	await process_frame
	var hide_prompt := field_view.get_node("%HidePrompt") as Label
	_check(hide_prompt.visible and _viewport_contains(hide_prompt.get_global_rect()), "cabinet hide prompt is visible and unclipped at 960x540")
	var cabinet: Dictionary = _hide_spot_by_id(hide_spots, cabinet_id)
	var cabinet_rect: Rect2 = cabinet["blocker_rect"]
	var entity_pose: Vector2 = cabinet_rect.get_center() + Vector2(0.0, -110.0)
	field_view.set_entity_pose_for_test(entity_pose, entity_pose.direction_to(field_view.explorer_position()))
	_check(field_view.begin_hide_nearby_for_test(), "nearby E-equivalent begins deterministic hide entry")
	_check(not field_view.explorer_simulation_enabled(), "hide entry freezes explorer movement")
	field_view.advance_encounter_for_test(FieldEncounterState.HIDE_ENTRY_DURATION_SECONDS, false, false)
	_check(field_view.encounter_snapshot()["state"] == "searching" and not field_view.get_node("%Explorer").visible, "unwitnessed hide completion enters searching and conceals explorer")
	_check(not field_view.open_object_interaction_for_test(unattempted_id), "searching rejects object menu entry")
	field_view.advance_encounter_for_test(FieldEncounterState.SEARCHING_DURATION_SECONDS, false, false)
	_check(field_view.encounter_snapshot()["state"] == "resolved" and not field_view.entity_visible(), "searching resolves and removes entity")
	_check(field_view.get_node("%Explorer").visible and field_view.explorer_simulation_enabled(), "resolved hide returns explorer control")
	_check(not field_view.trigger_encounter_for_test(FieldEncounterState.TRIGGER_DEEP_ENTRY), "resolved field encounter does not respawn")

	var viewport_rect := Rect2(Vector2.ZERO, get_root().get_visible_rect().size)
	for node_name: String in ["%HpLabel", "%EncounterStateLabel", "%EncounterBanner", "%SessionStateLabel"]:
		var hud_label := field_view.get_node(node_name) as Label
		_check(viewport_rect.encloses(hud_label.get_global_rect()), "%s stays inside 960x540" % node_name)
	var first_route: Dictionary = (app_root.call("active_field_session_snapshot") as Dictionary)["route"]
	field_view.move_explorer_to(first_route["entrance_position"])
	_check(field_view.try_return_at_entrance(), "accepted physical entrance return remains available after resolved chase")
	await process_frame

	_check(bool(app_root.call("attempt_departure", FieldSession.CONDITION_NORMAL, true, 7_777)), "produced supply starts a second field session")
	await process_frame
	field_view = app_root.get_node("%FieldSessionView") as FieldSessionView
	_check(field_view.encounter_snapshot()["hp"] == 3, "second session starts at full HP 3")
	var reward_locker: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(reward_locker != &"" and field_view.open_object_interaction_for_test(reward_locker), "second session can obtain session-only parts before danger")
	field_view.interaction_menu_node().select_base_search_for_test()
	_check(int((app_root.call("active_field_session_snapshot") as Dictionary)["unextracted_parts"]) == 2, "second session carries two unextracted parts into rescue test")
	var second_route: Dictionary = (app_root.call("active_field_session_snapshot") as Dictionary)["route"]
	var deep_position: Vector2 = (second_route["main_module_positions"] as Array)[-1]
	field_view.move_explorer_to(deep_position)
	field_view.advance_field_frame_for_test(EPSILON)
	_check(field_view.encounter_snapshot()["trigger_source"] == "deep_entry", "last main module starts deep-entry warning")
	field_view.advance_encounter_for_test(FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	var contact_origin: Vector2 = field_view.explorer_position()
	field_view.set_entity_pose_for_test(contact_origin, Vector2.RIGHT)
	field_view.advance_encounter_for_test(EPSILON, true, true)
	_check(field_view.encounter_snapshot()["hp"] == 2, "presentation contact changes HP 3 to 2")
	_check(field_view.explorer_position().distance_to(contact_origin) >= FieldSessionView.DAMAGE_KNOCKBACK_DISTANCE - 1.0, "contact pushes explorer to a safe distance")
	field_view.advance_encounter_for_test(0.1, true, true)
	_check(field_view.encounter_snapshot()["hp"] == 2, "presentation invulnerability blocks immediate repeat contact")
	field_view.advance_encounter_for_test(FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS, true, true)
	_check(field_view.encounter_snapshot()["hp"] == 1, "next unprotected contact changes HP 2 to 1")
	var rescue_tick: Dictionary = field_view.advance_encounter_for_test(FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS, true, true)
	_check(bool(rescue_tick["rescue_required"]) and int(rescue_tick["lost_unextracted_parts"]) == 2, "HP 0 rescue reports all lost unextracted parts")
	await process_frame
	_check(app_root.call("current_surface_mode") == AppRoot.COMPACT_HOME_MODE, "HP 0 returns to compact home through manager rescue")
	_check((app_root.call("active_field_session_snapshot") as Dictionary).is_empty(), "rescued field session is discarded")
	var home_snapshot: Dictionary = app_root.call("home_profile_snapshot") as Dictionary
	_check(int(home_snapshot["facility_parts"]) == 10, "rescue preserves the initial and entrance-confirmed home facility parts")
	_check(_has_exact_schema_fields(storage.stored_document()), "rescue storage remains exact schema v1")
	var departure_message := (app_root.get_node("%HomeStatus") as VBoxContainer).get_node("%DepartureMessage") as Label
	_check(departure_message.text.contains("관리인이 구조") and departure_message.text.contains("2 손실") and departure_message.text.contains("체력 3"), "compact home shows manager rescue, loss and recovery feedback")

	clock.advance(HomeProfile.BASE_INTERVAL_MS)
	_check(bool(app_root.call("refresh_home_profile")), "real-time supply can prepare a post-rescue departure")
	_check(bool(app_root.call("attempt_departure", FieldSession.CONDITION_NORMAL, true, 8_888)), "next departure starts immediately when supply exists")
	_check(int((app_root.call("active_field_session_snapshot") as Dictionary)["encounter"]["hp"]) == 3, "post-rescue next session resets HP to 3")
	var third_route: Dictionary = (app_root.call("active_field_session_snapshot") as Dictionary)["route"]
	field_view.move_explorer_to(third_route["entrance_position"])
	_check(field_view.try_return_at_entrance(), "accepted entrance return still works after rescue cycle")
	await process_frame

	app_root.queue_free()
	await process_frame
	var restarted_home := HomeProfileService.new(clock, storage)
	var restarted_app := packed_scene.instantiate() as Control
	restarted_app.call("configure_home_profile_service", restarted_home)
	restarted_app.call("configure_expedition_service", ExpeditionService.new(restarted_home, FieldRouteBuilder.new(SeededRandom.new())))
	restarted_app.call("configure_field_interaction_service", FieldInteractionService.new(SeededRandom.new()))
	restarted_app.call("configure_field_encounter_service", FieldEncounterService.new())
	get_root().add_child(restarted_app)
	await process_frame
	_check((restarted_app.call("active_field_session_snapshot") as Dictionary).is_empty(), "restart restores no HP, entity, chase, hiding or unextracted session")
	_check(int((restarted_app.call("home_profile_snapshot") as Dictionary)["facility_parts"]) == 10, "restart preserves home progress after rescue")
	_check(_has_exact_schema_fields(storage.stored_document()), "restart still uses the five schema v1 fields")
	restarted_app.queue_free()
	await process_frame
	get_root().size = Vector2i(1600, 900)


func _new_session(seed: int) -> FieldSession:
	return FieldSession.new(FieldSession.CONDITION_NORMAL, true, seed, FieldRouteBuilder.new(SeededRandom.new()).build(seed))


func _first_object(session: FieldSession, object_type: StringName) -> FieldObjectState:
	for state: FieldObjectState in session.object_states:
		if state.object_type == object_type:
			return state
	return null


func _has_hide_type(hide_spots: Array[Dictionary], spot_type: String) -> bool:
	for spot: Dictionary in hide_spots:
		if spot["spot_type"] == spot_type:
			return true
	return false


func _hide_spot_by_id(hide_spots: Array[Dictionary], spot_id: StringName) -> Dictionary:
	for spot: Dictionary in hide_spots:
		if spot["spot_id"] == String(spot_id):
			return spot
	return {}


func _first_unattempted_object_id(objects: Array[Dictionary]) -> StringName:
	for object_snapshot: Dictionary in objects:
		if not bool(object_snapshot["attempted"]):
			return StringName(object_snapshot["object_id"])
	return &""


func _probe_across_blocker(field_view: FieldSessionView, blocker: Rect2) -> bool:
	var center: Vector2 = blocker.get_center()
	var origin: Vector2
	var target: Vector2
	if blocker.size.x >= blocker.size.y:
		origin = center + Vector2(0.0, -blocker.size.y * 0.5 - 36.0)
		target = center + Vector2(0.0, blocker.size.y * 0.5 + 36.0)
	else:
		origin = center + Vector2(-blocker.size.x * 0.5 - 36.0, 0.0)
		target = center + Vector2(blocker.size.x * 0.5 + 36.0, 0.0)
	return field_view.sight_between_for_test(origin, origin.direction_to(target), target)


func _has_exact_schema_fields(document: Dictionary) -> bool:
	if document.size() != EXPECTED_SCHEMA_FIELDS.size():
		return false
	for field_name: String in EXPECTED_SCHEMA_FIELDS:
		if not document.has(field_name):
			return false
	return true


func _viewport_contains(rect: Rect2) -> bool:
	return Rect2(Vector2.ZERO, get_root().get_visible_rect().size).encloses(rect)


func _check_float(actual: float, expected: float, message: String) -> void:
	_check(is_equal_approx(actual, expected), "%s (actual=%f expected=%f)" % [message, actual, expected])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("CHASE_HIDE_RESCUE_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("CHASE_HIDE_RESCUE_PASS")
		quit(0)
		return
	printerr("CHASE_HIDE_RESCUE_FAIL count=%d" % _failures.size())
	quit(1)
