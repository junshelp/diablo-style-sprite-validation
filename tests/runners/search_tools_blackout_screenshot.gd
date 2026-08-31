extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout"
const EXPECTED_SIZE: Vector2i = Vector2i(1600, 900)


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

	var fixed_now_ms: int = 1_600_000_000
	var profile := HomeProfile.new(2.0, 0, false, fixed_now_ms)
	var clock := FakeClock.new(fixed_now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var home_service := HomeProfileService.new(clock, storage)
	var app_root := packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", home_service)
	app_root.call("configure_expedition_service", ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.call("configure_field_interaction_service", FieldInteractionService.new(SeededRandom.new()))
	get_root().add_child(app_root)
	await _wait_for_draw()

	if not bool(app_root.call("attempt_departure", FieldSession.CONDITION_BLACKOUT, false, 4_242)):
		_fail("blackout-no-flashlight departure failed")
		return
	await _wait_for_draw()
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var menu: ObjectInteractionMenu = field_view.interaction_menu_node()
	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	if locker_id == &"" or not field_view.open_object_interaction_for_test(locker_id):
		_fail("locker menu failed")
		return
	await _wait_for_draw()
	if not _save_viewport("object-choice.png"):
		return

	menu.show_item_stage()
	await _wait_for_draw()
	if not _save_viewport("item-choice.png"):
		return

	menu.go_back()
	menu.go_back()
	await _wait_for_draw()
	if not _save_viewport("blackout-no-flashlight.png"):
		return

	var panel_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_POWER_PANEL)
	if panel_id == &"" or not field_view.open_object_interaction_for_test(panel_id):
		_fail("power-panel menu failed")
		return
	menu.show_item_stage()
	menu.select_tool_for_test(ObjectInteractionRules.TOOL_FUSE)
	await _wait_for_draw()
	if not _save_viewport("fuse-restored.png"):
		return

	print("SEARCH_TOOLS_BLACKOUT_SCREENSHOT_PASS object-choice.png item-choice.png blackout-no-flashlight.png fuse-restored.png 1600x900")
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
	printerr("SEARCH_TOOLS_BLACKOUT_SCREENSHOT_FAIL %s" % message)
	quit(1)
