extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue"
const EXPECTED_SIZE: Vector2i = Vector2i(1600, 900)
const FIXED_CLOCK_MS: int = 1_800_000_000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = EXPECTED_SIZE
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("main scene could not be loaded")
		return
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE_DIRECTORY))
	if directory_error != OK:
		_fail("evidence directory error=%d" % directory_error)
		return

	var profile := HomeProfile.new(2.0, 7, false, FIXED_CLOCK_MS)
	var clock := FakeClock.new(FIXED_CLOCK_MS)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var home_service := HomeProfileService.new(clock, storage)
	var app_root := packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", home_service)
	app_root.call("configure_expedition_service", ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.call("configure_field_interaction_service", FieldInteractionService.new(SeededRandom.new()))
	app_root.call("configure_field_encounter_service", FieldEncounterService.new())
	get_root().add_child(app_root)
	await _wait_for_draw()

	if not bool(app_root.call("attempt_departure", FieldSession.CONDITION_NORMAL, true, 4_242)):
		_fail("first fixed-seed departure failed")
		return
	await _wait_for_draw()
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	# Drive encounter deltas explicitly so captured poses do not depend on render frame timing.
	field_view.set_process(false)
	var route: Dictionary = app_root.call("active_field_session_snapshot")["route"]
	var deep_position: Vector2 = (route["main_module_positions"] as Array)[-1]
	field_view.move_explorer_to(deep_position)
	field_view.advance_field_frame_for_test(0.001)
	if field_view.encounter_snapshot()["state"] != "warning":
		_fail("deep entry did not produce warning evidence state")
		return
	await _wait_for_draw()
	if not _save_viewport("warning.png"):
		return

	field_view.advance_encounter_for_test(FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	if field_view.encounter_snapshot()["state"] != "chasing" or not field_view.entity_visible():
		_fail("warning did not produce chasing evidence state")
		return
	await _wait_for_draw()
	if not _save_viewport("chasing.png"):
		return

	var cabinet_id: StringName = field_view.move_explorer_to_hide_spot_type(FieldHideSpotState.TYPE_CABINET)
	if cabinet_id == &"" or not field_view.begin_hide_nearby_for_test():
		_fail("cabinet hide could not begin")
		return
	field_view.advance_encounter_for_test(FieldEncounterState.HIDE_ENTRY_DURATION_SECONDS, false, false)
	field_view.advance_encounter_for_test(FieldEncounterState.SEARCHING_DURATION_SECONDS, false, false)
	if field_view.encounter_snapshot()["state"] != "resolved" or field_view.entity_visible():
		_fail("successful hide did not resolve encounter")
		return
	await _wait_for_draw()
	if not _save_viewport("hide-resolved.png"):
		return

	field_view.move_explorer_to(route["entrance_position"])
	if not field_view.try_return_at_entrance():
		_fail("first session could not return at physical entrance")
		return
	await _wait_for_draw()
	if not bool(app_root.call("attempt_departure", FieldSession.CONDITION_NORMAL, true, 7_777)):
		_fail("second fixed-seed departure failed")
		return
	await _wait_for_draw()
	field_view = app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	if locker_id == &"" or not field_view.open_object_interaction_for_test(locker_id):
		_fail("second-session locker search could not open")
		return
	field_view.interaction_menu_node().select_base_search_for_test()
	var second_route: Dictionary = app_root.call("active_field_session_snapshot")["route"]
	field_view.move_explorer_to((second_route["main_module_positions"] as Array)[-1])
	field_view.advance_field_frame_for_test(0.001)
	field_view.advance_encounter_for_test(FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	field_view.advance_encounter_for_test(0.001, true, true)
	field_view.advance_encounter_for_test(FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS, true, true)
	field_view.advance_encounter_for_test(FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS, true, true)
	await _wait_for_draw()
	if app_root.call("current_surface_mode") != AppRoot.COMPACT_HOME_MODE:
		_fail("HP 0 did not return to rescued home evidence state")
		return
	if not _save_viewport("rescued-home.png"):
		return

	print("CHASE_HIDE_RESCUE_SCREENSHOT_PASS warning.png chasing.png hide-resolved.png rescued-home.png 1600x900")
	app_root.queue_free()
	quit(0)


func _wait_for_draw() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _save_viewport(file_name: String) -> bool:
	var image: Image = get_root().get_texture().get_image()
	if image.get_size() != EXPECTED_SIZE:
		_fail("%s size=%s" % [file_name, image.get_size()])
		return false
	var target_path: String = "%s/%s" % [EVIDENCE_DIRECTORY, file_name]
	var save_error: Error = image.save_png(ProjectSettings.globalize_path(target_path))
	if save_error != OK:
		_fail("%s save_error=%d" % [file_name, save_error])
		return false
	return true


func _fail(message: String) -> void:
	printerr("CHASE_HIDE_RESCUE_SCREENSHOT_FAIL %s" % message)
	quit(1)
