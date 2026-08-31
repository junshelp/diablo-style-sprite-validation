extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-020-departure-movement-route"
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

	var fixed_now_ms: int = 1_200_000_000
	var profile := HomeProfile.new(2.0, 0, false, fixed_now_ms)
	var clock := FakeClock.new(fixed_now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var service := HomeProfileService.new(clock, storage)
	var expedition := ExpeditionService.new(service, FieldRouteBuilder.new(SeededRandom.new()))
	var app_root := packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", service)
	app_root.call("configure_expedition_service", expedition)
	get_root().add_child(app_root)
	await _wait_for_draw()
	app_root.call("select_preparation", FieldSession.CONDITION_NORMAL, true)
	await _wait_for_draw()
	if not _save_viewport("home-preparation.png"):
		return

	if not bool(app_root.call("attempt_departure", FieldSession.CONDITION_NORMAL, true, 4_242)):
		_fail("normal departure failed")
		return
	await _wait_for_draw()
	if not _save_viewport("field-normal.png"):
		return

	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var normal_snapshot: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	field_view.move_explorer_to((normal_snapshot["route"] as Dictionary)["entrance_position"])
	if not field_view.try_return_at_entrance():
		_fail("normal entrance return failed")
		return
	await _wait_for_draw()

	app_root.call("select_preparation", FieldSession.CONDITION_BLACKOUT, false)
	if not bool(app_root.call("attempt_departure", FieldSession.CONDITION_BLACKOUT, false, 4_242)):
		_fail("blackout departure failed")
		return
	await _wait_for_draw()
	if not _save_viewport("field-blackout.png"):
		return

	print("DEPARTURE_MOVEMENT_ROUTE_SCREENSHOT_PASS home-preparation.png field-normal.png field-blackout.png 1600x900")
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
	printerr("DEPARTURE_MOVEMENT_ROUTE_SCREENSHOT_FAIL %s" % message)
	quit(1)
