extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-080-ui-visibility"
const EXPECTED_SIZE: Vector2i = Vector2i(1600, 900)
const FIXED_CLOCK_MS: int = 3_000_000_000
const FIXED_ROUTE_SEED: int = 4_242


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

	var now_ms: int = FIXED_CLOCK_MS
	var profile := HomeProfile.new(2.0, 4, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	var home_service := HomeProfileService.new(clock, storage)
	var app_root := packed_scene.instantiate() as AppRoot
	app_root.configure_home_profile_service(home_service)
	app_root.configure_expedition_service(ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.configure_field_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	app_root.configure_field_encounter_service(FieldEncounterService.new())
	get_root().add_child(app_root)
	await _wait_for_draw()

	var departure := app_root.get_node("%HomeStatus").get_node("%DepartureButton") as Button
	departure.grab_focus()
	await _wait_for_draw()
	if not _save_viewport("after-home-1600x900.png"):
		return

	if not app_root.attempt_departure(FieldSession.CONDITION_NORMAL, true, FIXED_ROUTE_SEED):
		_fail("fixed-seed departure failed")
		return
	await _wait_for_draw()
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	if not _save_viewport("after-field-1600x900.png"):
		return

	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	if locker_id == &"" or not field_view.open_object_interaction_for_test(locker_id):
		_fail("fixed locker interaction could not open")
		return
	await _wait_for_draw()
	var menu: ObjectInteractionMenu = field_view.interaction_menu_node()
	(menu.get_node("ScreenMargin/PanelLayout/InteractionPanel/PanelMargin/Content/ObjectStage/UseItemButton") as Button).grab_focus()
	await _wait_for_draw()
	if not _save_viewport("after-object-menu-1600x900.png"):
		return

	print("UI_VISIBILITY_SCREENSHOT_PASS after-home-1600x900.png after-field-1600x900.png after-object-menu-1600x900.png 1600x900")
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
	printerr("UI_VISIBILITY_SCREENSHOT_FAIL %s" % message)
	quit(1)
