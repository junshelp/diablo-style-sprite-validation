extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-100-mobile-web-controls"
const MOBILE_LANDSCAPE_SIZE: Vector2i = Vector2i(844, 390)
const MOBILE_PORTRAIT_SIZE: Vector2i = Vector2i(390, 844)
const FIXED_CLOCK_MS: int = 3_000_000_000
const FIXED_SEED: int = 4_242


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE_DIRECTORY))
	if directory_error != OK:
		_fail("evidence directory error=%d" % directory_error)
		return
	if not await _capture_home():
		return
	if not await _capture_field(false):
		return
	if not await _capture_field(true):
		return
	if not await _capture_portrait():
		return
	print("MOBILE_WEB_CONTROLS_SCREENSHOT_PASS mobile-home-844x390.png mobile-field-844x390.png mobile-object-menu-844x390.png portrait-notice-390x844.png")
	quit(0)


func _capture_home() -> bool:
	get_root().size = MOBILE_LANDSCAPE_SIZE
	var app_root: AppRoot = _new_app_root()
	get_root().add_child(app_root)
	await _wait_for_draw()
	app_root.set_mobile_test_environment(true, MOBILE_LANDSCAPE_SIZE)
	await _wait_for_draw()
	app_root.set_process(false)
	var result: bool = _save_viewport("mobile-home-844x390.png", MOBILE_LANDSCAPE_SIZE)
	app_root.queue_free()
	await process_frame
	return result


func _capture_field(with_menu: bool) -> bool:
	get_root().size = MOBILE_LANDSCAPE_SIZE
	var app_root: AppRoot = _new_app_root()
	get_root().add_child(app_root)
	await _wait_for_draw()
	app_root.set_mobile_test_environment(true, MOBILE_LANDSCAPE_SIZE)
	if not app_root.attempt_departure(FieldSession.CONDITION_BLACKOUT, true, FIXED_SEED):
		_fail("fixed-seed mobile departure failed")
		return false
	await _wait_for_draw()
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.move_explorer_to(Vector2(620.0, 450.0))
	field_view.set_explorer_facing_for_test(Vector2.RIGHT)
	if with_menu:
		var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
		if locker_id == &"" or not app_root.mobile_controls_node().press_action_for_test():
			_fail("mobile object menu could not open")
			return false
		field_view.interaction_menu_node().show_item_stage()
	await _wait_for_draw()
	app_root.set_process(false)
	field_view.set_process(false)
	var file_name: String = "mobile-object-menu-844x390.png" if with_menu else "mobile-field-844x390.png"
	var result: bool = _save_viewport(file_name, MOBILE_LANDSCAPE_SIZE)
	app_root.queue_free()
	await process_frame
	return result


func _capture_portrait() -> bool:
	get_root().size = MOBILE_PORTRAIT_SIZE
	var app_root: AppRoot = _new_app_root()
	get_root().add_child(app_root)
	await _wait_for_draw()
	app_root.set_mobile_test_environment(true, MOBILE_PORTRAIT_SIZE)
	await _wait_for_draw()
	app_root.set_process(false)
	var result: bool = _save_viewport("portrait-notice-390x844.png", MOBILE_PORTRAIT_SIZE)
	app_root.queue_free()
	await process_frame
	return result


func _new_app_root() -> AppRoot:
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("main scene could not be loaded")
		return null
	var profile := HomeProfile.new(2.0, 4, false, FIXED_CLOCK_MS)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(FIXED_CLOCK_MS)
	var home_service := HomeProfileService.new(clock, storage)
	var app_root := packed_scene.instantiate() as AppRoot
	app_root.configure_home_profile_service(home_service)
	app_root.configure_expedition_service(ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.configure_field_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	app_root.configure_field_encounter_service(FieldEncounterService.new())
	return app_root


func _wait_for_draw() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _save_viewport(file_name: String, expected_size: Vector2i) -> bool:
	var image: Image = get_root().get_texture().get_image()
	if image.get_size() != expected_size:
		_fail("%s size=%s expected=%s" % [file_name, image.get_size(), expected_size])
		return false
	var target_path: String = "%s/%s" % [EVIDENCE_DIRECTORY, file_name]
	var save_error: Error = image.save_png(ProjectSettings.globalize_path(target_path))
	if save_error != OK:
		_fail("%s save_error=%d" % [file_name, save_error])
		return false
	return true


func _fail(message: String) -> void:
	printerr("MOBILE_WEB_CONTROLS_SCREENSHOT_FAIL %s" % message)
	quit(1)
