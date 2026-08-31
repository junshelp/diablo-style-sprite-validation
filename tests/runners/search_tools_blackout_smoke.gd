extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
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
	_test_reaction_and_reward_tables()
	_test_wrong_tool_and_one_attempt()
	_test_seeded_crowbar_reaction()
	_test_fuse_reaction()
	await _test_placeholder_lighting_levels()
	await _test_menu_pause_result_storage_and_return()
	_finish()


func _test_reaction_and_reward_tables() -> void:
	var rules := ObjectInteractionRules.new()
	var table: Dictionary = ObjectInteractionRules.REACTION_TABLE
	_check(table.size() == 2, "reaction table is limited to the approved object-tool pairs")
	_check(table.has("locker|crowbar"), "reaction table contains crowbar + locker")
	_check(table.has("power_panel|fuse"), "reaction table contains fuse + power panel")

	var normal: FieldSession = _new_session(FieldSession.CONDITION_NORMAL, false, 101)
	var blackout_flashlight: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, true, 102)
	var blackout_unprepared: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, false, 103)
	var restored: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, false, 104)
	restored.lighting_restored = true
	var normal_result: ObjectInteractionResult = rules.prepare_base_search(normal, normal.object_states[0])
	var flashlight_result: ObjectInteractionResult = rules.prepare_base_search(blackout_flashlight, blackout_flashlight.object_states[0])
	var unprepared_result: ObjectInteractionResult = rules.prepare_base_search(blackout_unprepared, blackout_unprepared.object_states[0])
	var restored_result: ObjectInteractionResult = rules.prepare_base_search(restored, restored.object_states[0])
	_check(normal_result.reward_context == ObjectInteractionRules.REWARD_CONTEXT_NORMAL and normal_result.parts_delta == 2, "normal base search exposes the two-part baseline")
	_check(flashlight_result.reward_context == ObjectInteractionRules.REWARD_CONTEXT_BLACKOUT_FLASHLIGHT and flashlight_result.parts_delta == 1, "flashlight mitigates blackout recovery loss")
	_check(unprepared_result.reward_context == ObjectInteractionRules.REWARD_CONTEXT_BLACKOUT_UNPREPARED and unprepared_result.parts_delta == 0, "blackout without flashlight remains enterable but yields the explicit lower recovery")
	_check(restored_result.reward_context == ObjectInteractionRules.REWARD_CONTEXT_LIGHTING_RESTORED and restored_result.parts_delta == 2, "restored lighting updates later search context")
	_check(normal_result.parts_delta > flashlight_result.parts_delta and flashlight_result.parts_delta > unprepared_result.parts_delta, "soft-counter table keeps normal, flashlight and unprepared outcomes distinct")


func _test_wrong_tool_and_one_attempt() -> void:
	var session: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, true, 202)
	var locker: FieldObjectState = _first_object(session, FieldObjectState.TYPE_LOCKER)
	_check(locker != null, "wrong-tool fixture contains a locker")
	if locker == null:
		return
	var service := FieldInteractionService.new(SeededRandom.new())
	_check(service.begin_interaction(session, locker.object_id), "locker interaction begins once")
	var fuse_before: int = session.fuse_count
	var result: ObjectInteractionResult = service.prepare_tool(session, ObjectInteractionRules.TOOL_FUSE)
	_check(result != null and result.used_base_fallback, "wrong fuse uses the current base-search result")
	_check(result != null and result.parts_delta == 1, "wrong tool fallback uses blackout + flashlight recovery")
	_check(service.apply_result(session, result), "wrong-tool result applies after interaction closes")
	_check(session.fuse_count == fuse_before, "wrong tool is not consumed")
	_check(locker.attempted, "wrong tool closes the object for the session")
	_check(not service.begin_interaction(session, locker.object_id), "attempted object cannot reopen")
	_check(not service.apply_result(session, result), "the same prepared result cannot apply twice")
	_check(session.result_application_count == 1, "one object attempt increments result count exactly once")


func _test_seeded_crowbar_reaction() -> void:
	var first: FieldSession = _new_session(FieldSession.CONDITION_NORMAL, true, 4_242)
	var second: FieldSession = _new_session(FieldSession.CONDITION_NORMAL, true, 4_242)
	var first_locker: FieldObjectState = _first_object(first, FieldObjectState.TYPE_LOCKER)
	var second_locker: FieldObjectState = second.object_state(first_locker.object_id) if first_locker != null else null
	_check(first_locker != null and second_locker != null, "same-seed crowbar fixtures expose the same locker id")
	if first_locker == null or second_locker == null:
		return
	var first_service := FieldInteractionService.new(SeededRandom.new())
	var second_service := FieldInteractionService.new(SeededRandom.new())
	first_service.begin_interaction(first, first_locker.object_id)
	second_service.begin_interaction(second, second_locker.object_id)
	var first_result: ObjectInteractionResult = first_service.prepare_tool(first, ObjectInteractionRules.TOOL_CROWBAR)
	var second_result: ObjectInteractionResult = second_service.prepare_tool(second, ObjectInteractionRules.TOOL_CROWBAR)
	_check(first_result.snapshot() == second_result.snapshot(), "same seed/object/crowbar reproduces the prepared result")
	_check(first_result.extra_parts == 1, "chosen fixed seed 4242 exercises the extra crowbar recovery branch")
	_check(first_result.parts_delta == 2 + first_result.extra_parts, "crowbar adds seeded recovery to the normal base result")
	_check(first_result.loud_noise and not first_result.consumes_tool, "crowbar + locker is loud and reusable")
	first_service.apply_result(first, first_result)
	_check(first.crowbar_count == 1 and first.loud_noise_occurred, "applied crowbar result preserves the tool and records noise without starting chase")


func _test_fuse_reaction() -> void:
	var session: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, false, 303)
	var panel: FieldObjectState = _first_object(session, FieldObjectState.TYPE_POWER_PANEL)
	_check(panel != null, "fuse fixture contains a power panel")
	if panel == null:
		return
	var service := FieldInteractionService.new(SeededRandom.new())
	service.begin_interaction(session, panel.object_id)
	var result: ObjectInteractionResult = service.prepare_tool(session, ObjectInteractionRules.TOOL_FUSE)
	_check(result != null and result.consumes_tool and result.restores_lighting, "fuse + panel prepares consume and lighting restore")
	_check(result != null and result.parts_delta == 0, "fuse reaction does not invent a parts reward")
	_check(service.apply_result(session, result), "fuse result applies once")
	_check(session.fuse_count == 0 and session.lighting_restored, "fuse is consumed and session lighting is restored")


func _test_placeholder_lighting_levels() -> void:
	var packed_field := load("res://scenes/field/field_session.tscn") as PackedScene
	_check(packed_field != null, "field scene loads for lighting-level presentation smoke")
	if packed_field == null:
		return
	var field_view := packed_field.instantiate() as FieldSessionView
	field_view.configure_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	get_root().add_child(field_view)
	await process_frame

	var normal: FieldSession = _new_session(FieldSession.CONDITION_NORMAL, false, 401)
	field_view.start_session(normal)
	var normal_alpha: float = field_view.darkness_alpha()
	field_view.end_session()
	await process_frame
	var restored: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, false, 402)
	restored.lighting_restored = true
	field_view.start_session(restored)
	var restored_alpha: float = field_view.darkness_alpha()
	field_view.end_session()
	await process_frame
	var flashlight: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, true, 403)
	field_view.start_session(flashlight)
	var flashlight_alpha: float = field_view.darkness_alpha()
	field_view.end_session()
	await process_frame
	var unprepared: FieldSession = _new_session(FieldSession.CONDITION_BLACKOUT, false, 404)
	field_view.start_session(unprepared)
	var unprepared_alpha: float = field_view.darkness_alpha()
	_check(normal_alpha < restored_alpha and restored_alpha < flashlight_alpha and flashlight_alpha < unprepared_alpha, "normal, restored, flashlight and unprepared placeholder darkness stay externally distinct")
	_check(flashlight_alpha > normal_alpha, "flashlight mitigates blackout without making it visually normal")
	field_view.queue_free()
	await process_frame


func _test_menu_pause_result_storage_and_return() -> void:
	get_root().size = Vector2i(960, 540)
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	_check(packed_scene != null, "main scene loads for task-030 integration")
	if packed_scene == null:
		return

	var now_ms: int = 1_500_000_000
	var profile := HomeProfile.new(1.5, 0, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	var home_service := HomeProfileService.new(clock, storage)
	var expedition_service := ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new()))
	var interaction_service := FieldInteractionService.new(SeededRandom.new())
	var app_root := packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", home_service)
	app_root.call("configure_expedition_service", expedition_service)
	app_root.call("configure_field_interaction_service", interaction_service)
	get_root().add_child(app_root)
	await process_frame
	_check(bool(app_root.call("attempt_departure", FieldSession.CONDITION_BLACKOUT, false, 4_242)), "blackout-no-flashlight departure reaches the field")
	await process_frame
	await physics_frame

	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var menu: ObjectInteractionMenu = field_view.interaction_menu_node()
	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(locker_id != &"" and field_view.open_object_interaction_for_test(locker_id), "nearby locker opens the object menu")
	await process_frame
	_check(menu.visible, "object menu is visible after nearby E-equivalent interaction")
	_check(menu.top_level_choices() == ["그냥 수색", "아이템 사용"], "first stage exposes the exact approved choices")
	_check(menu.current_stage() == ObjectInteractionMenu.STAGE_OBJECT, "menu opens on the object-choice stage")
	_check(not _contains_forbidden_compatibility_text(menu.visible_text()), "first stage contains no compatibility or outcome hint")
	_check(not paused, "object menu does not pause the SceneTree")
	_check(_viewport_contains(menu.panel_rect()), "interaction panel is not clipped at 960x540")

	menu.show_item_stage()
	await process_frame
	_check(menu.current_stage() == ObjectInteractionMenu.STAGE_ITEM, "item action opens the second stage")
	var entries: Array[Dictionary] = menu.tool_entries()
	_check(entries.size() == 2 and entries[0]["label"] == "빠루" and entries[1]["label"] == "퓨즈", "item stage exposes both carried tools without ranking")
	if entries.size() == 2:
		var crowbar_button := entries[0]["button"] as Button
		var fuse_button := entries[1]["button"] as Button
		_check(crowbar_button.text.contains("보유 1") and fuse_button.text.contains("보유 1"), "item stage shows quantity for both tools")
		_check(crowbar_button.get_global_rect().size == fuse_button.get_global_rect().size, "crowbar and fuse use equal visual slot geometry")
	_check(not _contains_forbidden_compatibility_text(menu.visible_text()), "item stage contains no compatibility, answer or expected-result text")
	menu.go_back()
	_check(menu.current_stage() == ObjectInteractionMenu.STAGE_OBJECT and menu.visible, "ESC-equivalent back returns to the first stage without closing")

	var position_before: Vector2 = field_view.explorer_position()
	var paused_snapshot: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	var simulation_before: float = float(paused_snapshot["field_simulation_elapsed_seconds"])
	var checks_before: int = field_view.object_check_count()
	var visual_before: float = field_view.visual_elapsed_seconds()
	field_view.move_explorer_for_test(Vector2.RIGHT, 2.0)
	field_view.advance_field_frame_for_test(5.0)
	var still_paused: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	_check(field_view.explorer_position() == position_before, "menu freezes explorer movement")
	_check_float(float(still_paused["field_simulation_elapsed_seconds"]), simulation_before, "menu freezes field simulation elapsed")
	_check(field_view.object_check_count() == checks_before, "menu freezes proximity/object checks")
	_check(field_view.visual_elapsed_seconds() > visual_before, "field presentation/UI process remains live while interaction simulation is paused")
	_check(not field_view.explorer_simulation_enabled(), "explorer controller owns an explicit menu pause gate")

	clock.advance(HomeProfile.BASE_INTERVAL_MS / 2)
	_check(bool(app_root.call("refresh_home_profile")), "fake real-time profile refresh continues while menu is open")
	_check_float(float((app_root.call("home_profile_snapshot") as Dictionary)["departure_supply_units"]), 1.0, "home supply advances from preserved half progress during menu pause")

	var ordering_observations: Array[Dictionary] = []
	field_view.interaction_result_applied.connect(func(result: ObjectInteractionResult) -> void:
		ordering_observations.append({
			"result": result,
			"menu_hidden": not menu.visible,
			"field_resumed": not bool((app_root.call("active_field_session_snapshot") as Dictionary)["field_simulation_paused"]),
			"explorer_resumed": field_view.explorer_simulation_enabled(),
		})
	)
	menu.show_item_stage()
	menu.select_tool_for_test(ObjectInteractionRules.TOOL_FUSE)
	_check(ordering_observations.size() == 1, "one selection emits one applied result")
	if ordering_observations.size() == 1:
		var observation: Dictionary = ordering_observations[0]
		_check(bool(observation["menu_hidden"]) and bool(observation["field_resumed"]) and bool(observation["explorer_resumed"]), "menu closes and field resumes before result notification")
		var wrong_result := observation["result"] as ObjectInteractionResult
		_check(wrong_result.used_base_fallback and not wrong_result.consumes_tool, "presentation path preserves wrong-tool fallback without consume")
		var live_session := field_view.get("_session") as FieldSession
		_check(not interaction_service.apply_result(live_session, wrong_result), "already applied presentation result is rejected at application boundary")
	var after_wrong: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	_check(int(after_wrong["fuse_count"]) == 1 and int(after_wrong["unextracted_parts"]) == 0, "blackout-no-flashlight fallback retains fuse and applies the lower recovery")
	_check(int(after_wrong["result_application_count"]) == 1, "post-close result count is exactly one")
	_check(not field_view.open_object_interaction_for_test(locker_id), "resolved locker cannot reopen")

	var blackout_alpha: float = field_view.darkness_alpha()
	_check(blackout_alpha >= 0.65, "blackout without flashlight exposes the strongest placeholder darkness")
	var panel_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_POWER_PANEL)
	_check(panel_id != &"" and field_view.open_object_interaction_for_test(panel_id), "nearby power panel opens the same two-stage menu")
	menu.show_item_stage()
	menu.select_tool_for_test(ObjectInteractionRules.TOOL_FUSE)
	var after_fuse: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	_check(int(after_fuse["fuse_count"]) == 0 and bool(after_fuse["lighting_restored"]), "presentation fuse choice consumes one and restores lighting")
	_check(field_view.darkness_alpha() < blackout_alpha, "lighting restore updates the current blackout overlay")

	var later_locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(later_locker_id != &"" and field_view.open_object_interaction_for_test(later_locker_id), "later unattempted locker remains searchable")
	menu.select_base_search_for_test()
	var after_restored_search: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	_check(int(after_restored_search["unextracted_parts"]) == 2, "restored-light base search uses normal-equivalent session-only parts")
	_check(int(after_restored_search["result_application_count"]) == 3, "each of three distinct objects applies once")

	var viewport_rect := Rect2(Vector2.ZERO, get_root().get_visible_rect().size)
	for node_name: String in ["%ConditionLabel", "%LoadoutLabel", "%RouteLabel", "%SessionStateLabel", "%ResultLabel"]:
		var hud_label := field_view.get_node(node_name) as Label
		_check(viewport_rect.encloses(hud_label.get_global_rect()), "%s is not clipped at 960x540" % node_name)

	var stored_during_field: Dictionary = storage.stored_document()
	_check(_has_exact_schema_fields(stored_during_field), "stored profile keeps exactly the five schema v1 fields")
	_check(not stored_during_field.has("unextracted_parts") and not stored_during_field.has("object_states"), "unextracted parts and object attempts never cross the storage boundary")
	var route_snapshot: Dictionary = after_restored_search["route"]
	field_view.move_explorer_to(route_snapshot["entrance_position"])
	_check(field_view.try_return_at_entrance(), "physical entrance return still works after object interactions")
	await process_frame
	_check((app_root.call("active_field_session_snapshot") as Dictionary).is_empty(), "entrance extraction settles and discards field session state")
	_check(int((app_root.call("home_profile_snapshot") as Dictionary)["facility_parts"]) == 2, "entrance extraction confirms the restored-light session parts")

	app_root.queue_free()
	await process_frame
	var restarted_home := HomeProfileService.new(clock, storage)
	var restarted_app := packed_scene.instantiate() as Control
	restarted_app.call("configure_home_profile_service", restarted_home)
	restarted_app.call("configure_expedition_service", ExpeditionService.new(restarted_home, FieldRouteBuilder.new(SeededRandom.new())))
	restarted_app.call("configure_field_interaction_service", FieldInteractionService.new(SeededRandom.new()))
	get_root().add_child(restarted_app)
	await process_frame
	_check((restarted_app.call("active_field_session_snapshot") as Dictionary).is_empty(), "restart restores no unextracted field session")
	_check(int((restarted_app.call("home_profile_snapshot") as Dictionary)["facility_parts"]) == 2, "restart preserves only the entrance-confirmed parts")
	_check(_has_exact_schema_fields(storage.stored_document()), "restart storage remains schema v1")
	restarted_app.queue_free()
	await process_frame
	get_root().size = Vector2i(1600, 900)


func _new_session(condition: StringName, flashlight_equipped: bool, seed: int) -> FieldSession:
	return FieldSession.new(condition, flashlight_equipped, seed, FieldRouteBuilder.new(SeededRandom.new()).build(seed))


func _first_object(session: FieldSession, object_type: StringName) -> FieldObjectState:
	for state: FieldObjectState in session.object_states:
		if state.object_type == object_type:
			return state
	return null


func _contains_forbidden_compatibility_text(value: String) -> bool:
	for forbidden: String in ["호환", "추천", "정답", "예상 결과", "성공률", "효과 미리보기"]:
		if value.contains(forbidden):
			return true
	return false


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
	printerr("SEARCH_TOOLS_BLACKOUT_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("SEARCH_TOOLS_BLACKOUT_PASS")
		quit(0)
		return
	printerr("SEARCH_TOOLS_BLACKOUT_FAIL count=%d" % _failures.size())
	quit(1)
