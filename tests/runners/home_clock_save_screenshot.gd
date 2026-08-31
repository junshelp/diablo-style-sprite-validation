extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-010-home-clock-save"
const EXPECTED_SIZE: Vector2i = Vector2i(1600, 900)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = EXPECTED_SIZE
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		printerr("HOME_CLOCK_SAVE_SCREENSHOT_FAIL main scene could not be loaded")
		quit(1)
		return

	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE_DIRECTORY))
	if directory_error != OK:
		printerr("HOME_CLOCK_SAVE_SCREENSHOT_FAIL evidence directory error=%d" % directory_error)
		quit(1)
		return

	var fixed_now_ms: int = 1_000_000_000
	var profile: HomeProfile = HomeProfile.new(1.5, 3, false, fixed_now_ms)
	var fake_clock: FakeClock = FakeClock.new(fixed_now_ms)
	var memory_storage: MemoryProfileStorage = MemoryProfileStorage.new(profile.to_document())
	var service: HomeProfileService = HomeProfileService.new(fake_clock, memory_storage)
	var app_root: Control = packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", service)
	get_root().add_child(app_root)
	await _wait_for_draw()

	if not _save_viewport("compact.png"):
		quit(1)
		return

	var surface_toggle: Button = app_root.get_node("%SurfaceToggle") as Button
	surface_toggle.pressed.emit()
	fake_clock.advance(HomeProfile.BASE_INTERVAL_MS / 2)
	if not bool(app_root.call("refresh_home_profile")):
		printerr("HOME_CLOCK_SAVE_SCREENSHOT_FAIL expanded refresh failed")
		quit(1)
		return
	await _wait_for_draw()

	if not _save_viewport("expanded.png"):
		quit(1)
		return

	print("HOME_CLOCK_SAVE_SCREENSHOT_PASS compact.png expanded.png 1600x900")
	app_root.queue_free()
	quit(0)


func _wait_for_draw() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _save_viewport(file_name: String) -> bool:
	var image: Image = get_root().get_texture().get_image()
	if image.get_size() != EXPECTED_SIZE:
		printerr("HOME_CLOCK_SAVE_SCREENSHOT_FAIL %s size=%s" % [file_name, image.get_size()])
		return false

	var target_path: String = "%s/%s" % [EVIDENCE_DIRECTORY, file_name]
	var save_error: Error = image.save_png(ProjectSettings.globalize_path(target_path))
	if save_error != OK:
		printerr("HOME_CLOCK_SAVE_SCREENSHOT_FAIL %s save_error=%d" % [file_name, save_error])
		return false

	return true
