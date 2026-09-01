extends SceneTree

const FIELD_SCENE_PATH: String = "res://scenes/field/field_session.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-090-field-visibility-lighting"
const EXPECTED_SIZE: Vector2i = Vector2i(1600, 900)
const FIXED_SEED: int = 4_242


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = EXPECTED_SIZE
	var packed_field := load(FIELD_SCENE_PATH) as PackedScene
	if packed_field == null:
		_fail("field scene could not be loaded")
		return
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE_DIRECTORY))
	if directory_error != OK:
		_fail("evidence directory error=%d" % directory_error)
		return

	if not await _capture_state(packed_field, FieldSession.CONDITION_NORMAL, false, false, "normal.png"):
		return
	if not await _capture_state(packed_field, FieldSession.CONDITION_BLACKOUT, false, false, "blackout-unprepared.png"):
		return
	if not await _capture_state(packed_field, FieldSession.CONDITION_BLACKOUT, true, false, "blackout-flashlight.png"):
		return
	if not await _capture_state(packed_field, FieldSession.CONDITION_BLACKOUT, false, true, "fuse-restored.png"):
		return

	print("FIELD_VISIBILITY_LIGHTING_SCREENSHOT_PASS normal.png blackout-unprepared.png blackout-flashlight.png fuse-restored.png 1600x900")
	quit(0)


func _capture_state(packed_field: PackedScene, condition: StringName, flashlight_equipped: bool, restore_with_fuse: bool, file_name: String) -> bool:
	var field_view := packed_field.instantiate() as FieldSessionView
	field_view.configure_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	field_view.configure_encounter_service(FieldEncounterService.new())
	get_root().add_child(field_view)
	await _wait_for_draw()
	var session := FieldSession.new(condition, flashlight_equipped, FIXED_SEED, FieldRouteBuilder.new(SeededRandom.new()).build(FIXED_SEED))
	field_view.start_session(session)
	await _wait_for_draw()
	if restore_with_fuse:
		var panel_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_POWER_PANEL)
		if panel_id == &"" or not field_view.open_object_interaction_for_test(panel_id):
			_fail("%s could not open fixed power panel" % file_name)
			return false
		field_view.interaction_menu_node().show_item_stage()
		field_view.interaction_menu_node().select_tool_for_test(ObjectInteractionRules.TOOL_FUSE)
		await _wait_for_draw()
		if not session.lighting_restored or session.fuse_count != 0:
			_fail("%s did not apply actual fuse restoration" % file_name)
			return false
	var fixed_position: Vector2 = session.route.main_module_positions[0]
	field_view.move_explorer_to(fixed_position)
	field_view.set_explorer_facing_for_test(Vector2.RIGHT)
	field_view.set_process(false)
	await _wait_for_draw()
	var expected_state: String = "restored_fixtures" if restore_with_fuse else (
		"normal_ambient" if condition == FieldSession.CONDITION_NORMAL else (
			"blackout_flashlight" if flashlight_equipped else "blackout_unprepared"
		)
	)
	if field_view.lighting_state_snapshot()["state"] != expected_state:
		_fail("%s state mismatch" % file_name)
		return false
	if not _save_viewport(file_name):
		return false
	field_view.end_session()
	field_view.queue_free()
	await process_frame
	return true


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
	printerr("FIELD_VISIBILITY_LIGHTING_SCREENSHOT_FAIL %s" % message)
	quit(1)
