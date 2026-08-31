extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-050-extraction-upgrade-loop"
const EXPECTED_SIZE: Vector2i = Vector2i(1600, 900)
const FIXED_CLOCK_MS: int = 2_500_000_000


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

	var early_fixture: Dictionary = await _spawn_app(packed_scene, HomeProfile.new(2.0, 0, false, FIXED_CLOCK_MS), FIXED_CLOCK_MS)
	var early_app := early_fixture["app"] as AppRoot
	if not early_app.attempt_departure(FieldSession.CONDITION_NORMAL, true, 4_242):
		_fail("early fixed-seed departure failed")
		return
	await _wait_for_draw()
	var early_field := early_app.get_node("%FieldSessionView") as FieldSessionView
	early_field.set_process(false)
	var locker_id: StringName = early_field.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	if locker_id == &"" or not early_field.open_object_interaction_for_test(locker_id):
		_fail("early locker search could not open")
		return
	early_field.interaction_menu_node().select_base_search_for_test()
	early_field.move_explorer_to_extraction_point_for_test(ExtractionUpgradeRules.EXTRACTION_ENTRANCE)
	if not early_field.try_return_at_entrance():
		_fail("early entrance extraction failed")
		return
	await _wait_for_draw()
	if int(early_app.home_profile_snapshot()["facility_parts"]) != 2:
		_fail("early extraction did not confirm two parts")
		return
	if not _save_viewport("early-extraction.png"):
		return
	early_app.queue_free()
	await process_frame

	var loop_fixture: Dictionary = await _spawn_app(packed_scene, HomeProfile.new(2.0, 0, false, FIXED_CLOCK_MS), FIXED_CLOCK_MS)
	var loop_app := loop_fixture["app"] as AppRoot
	var clock := loop_fixture["clock"] as FakeClock
	if not loop_app.attempt_departure(FieldSession.CONDITION_NORMAL, true, 9_050):
		_fail("endpoint fixed-seed departure failed")
		return
	await _wait_for_draw()
	var field_view := loop_app.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	field_view.move_explorer_to_extraction_point_for_test(ExtractionUpgradeRules.EXTRACTION_ENDPOINT)
	if not field_view.try_extract_at_endpoint():
		_fail("endpoint extraction failed")
		return
	await _wait_for_draw()
	if int(loop_app.home_profile_snapshot()["facility_parts"]) != 4:
		_fail("endpoint extraction did not guarantee four parts")
		return
	if not _save_viewport("endpoint-extraction.png"):
		return

	if not loop_app.attempt_producer_upgrade():
		_fail("four-part producer upgrade failed")
		return
	await _wait_for_draw()
	var upgraded: Dictionary = loop_app.home_profile_snapshot()
	if int(upgraded["facility_parts"]) != 0 or not bool(upgraded["producer_upgraded"]):
		_fail("upgrade did not consume exactly four parts")
		return
	if not _save_viewport("upgraded-home.png"):
		return

	if not loop_app.attempt_departure(FieldSession.CONDITION_NORMAL, true, 9_051):
		_fail("immediate second departure failed")
		return
	await _wait_for_draw()
	field_view = loop_app.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	clock.advance(HomeProfile.UPGRADED_INTERVAL_MS / 2)
	if not loop_app.refresh_home_profile():
		_fail("second-field upgraded production refresh failed")
		return
	await _wait_for_draw()
	var second: Dictionary = loop_app.active_field_session_snapshot()
	if int(second["encounter"]["hp"]) != 3 or second["encounter"]["state"] != "dormant":
		_fail("second departure did not reset HP and encounter")
		return
	if not _save_viewport("second-departure.png"):
		return

	print("EXTRACTION_UPGRADE_LOOP_SCREENSHOT_PASS early-extraction.png endpoint-extraction.png upgraded-home.png second-departure.png 1600x900")
	loop_app.queue_free()
	quit(0)


func _spawn_app(packed_scene: PackedScene, profile: HomeProfile, now_ms: int) -> Dictionary:
	var clock := FakeClock.new(now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var home_service := HomeProfileService.new(clock, storage)
	var app_root := packed_scene.instantiate() as AppRoot
	app_root.configure_home_profile_service(home_service)
	app_root.configure_expedition_service(ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.configure_field_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	app_root.configure_field_encounter_service(FieldEncounterService.new())
	get_root().add_child(app_root)
	await _wait_for_draw()
	return {
		"app": app_root,
		"clock": clock,
		"storage": storage,
	}


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
	printerr("EXTRACTION_UPGRADE_LOOP_SCREENSHOT_FAIL %s" % message)
	quit(1)
