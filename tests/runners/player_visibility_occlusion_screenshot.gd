extends SceneTree

const FIELD_SCENE_PATH: String = "res://scenes/field/field_session.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EVIDENCE_DIRECTORY: String = "res://_workspace/desktop-horror-prototype/evidence/task-110-player-visibility-occlusion"
const DESKTOP_SIZE: Vector2i = Vector2i(1600, 900)
const MOBILE_SIZE: Vector2i = Vector2i(844, 390)
const FIXED_SEED: int = 4_242
const FIXED_CLOCK_MS: int = 3_000_000_000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EVIDENCE_DIRECTORY))
	if directory_error != OK:
		_fail("evidence directory error=%d" % directory_error)
		return
	if not await _capture_desktop_entity_cases():
		return
	var unprepared: Dictionary = await _capture_mobile_state(false, "mobile-blackout-unprepared-844x390.png")
	if unprepared.is_empty():
		return
	var flashlight: Dictionary = await _capture_mobile_state(true, "mobile-blackout-flashlight-844x390.png")
	if flashlight.is_empty():
		return
	if not _validate_mobile_pair(unprepared, flashlight):
		return
	print("PLAYER_VISIBILITY_OCCLUSION_SCREENSHOT_PASS entity-baseline-no-entity.png entity-near-inside-cone.png entity-far-outside-cone.png entity-behind-wall.png mobile-blackout-unprepared-844x390.png mobile-blackout-flashlight-844x390.png")
	quit(0)


func _capture_desktop_entity_cases() -> bool:
	get_root().size = DESKTOP_SIZE
	var packed_field := load(FIELD_SCENE_PATH) as PackedScene
	if packed_field == null:
		_fail("field scene could not be loaded")
		return false
	var field_view := packed_field.instantiate() as FieldSessionView
	field_view.configure_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	field_view.configure_encounter_service(FieldEncounterService.new())
	get_root().add_child(field_view)
	await _wait_for_draw()
	var session := FieldSession.new(FieldSession.CONDITION_BLACKOUT, true, FIXED_SEED, FieldRouteBuilder.new(SeededRandom.new()).build(FIXED_SEED))
	field_view.start_session(session)
	await _wait_for_draw()
	var player_position := Vector2(620.0, 450.0)
	field_view.move_explorer_to(player_position)
	field_view.set_explorer_facing_for_test(Vector2.UP)
	if not field_view.trigger_encounter_for_test(FieldEncounterState.TRIGGER_DEEP_ENTRY):
		_fail("desktop entity fixture encounter trigger failed")
		return false
	field_view.advance_encounter_for_test(FieldEncounterState.WARNING_DURATION_SECONDS + 0.01, false, false)
	field_view.set_process(false)
	var entity := field_view.get_node("%ChaseEntity") as ChaseEntityView
	entity.set_debug_fov_visible(false)
	var far_position := player_position + Vector2(-430.0, 70.0)
	field_view.set_entity_pose_for_test(far_position, Vector2.LEFT)
	entity.set_player_visible(false)
	await _wait_for_draw()
	var baseline: Image = _viewport_image(DESKTOP_SIZE, "entity baseline")
	if baseline == null or not _save_image(baseline, "entity-baseline-no-entity.png"):
		return false

	field_view.set_entity_pose_for_test(player_position + Vector2(0.0, -90.0), Vector2.LEFT)
	if not field_view.entity_player_visible():
		_fail("near entity was not player-visible")
		return false
	await _wait_for_draw()
	var near: Image = _viewport_image(DESKTOP_SIZE, "near entity")
	if near == null or near.get_data() == baseline.get_data() or not _save_image(near, "entity-near-inside-cone.png"):
		_fail("near entity did not produce a visible silhouette")
		return false

	field_view.set_entity_pose_for_test(far_position, Vector2.LEFT)
	if field_view.entity_player_visible():
		_fail("far outside-cone entity remained player-visible")
		return false
	await _wait_for_draw()
	var far: Image = _viewport_image(DESKTOP_SIZE, "far entity")
	if far == null or far.get_data() != baseline.get_data() or not _save_image(far, "entity-far-outside-cone.png"):
		_fail("far outside-cone frame differs from no-entity baseline")
		return false

	var wall_rect: Rect2 = field_view.named_sight_blocker(&"wall")
	var behind_wall := Vector2(player_position.x, wall_rect.position.y - 56.0)
	field_view.set_entity_pose_for_test(behind_wall, Vector2.LEFT)
	if field_view.entity_player_visible() or not field_view.visual_light_path_blocked_for_test(player_position, behind_wall):
		_fail("behind-wall entity did not resolve to blocked and hidden")
		return false
	await _wait_for_draw()
	var wall: Image = _viewport_image(DESKTOP_SIZE, "behind-wall entity")
	if wall == null or wall.get_data() != baseline.get_data() or not _save_image(wall, "entity-behind-wall.png"):
		_fail("behind-wall frame differs from no-entity baseline")
		return false

	field_view.end_session()
	field_view.queue_free()
	await process_frame
	return true


func _capture_mobile_state(flashlight_equipped: bool, file_name: String) -> Dictionary:
	get_root().size = MOBILE_SIZE
	var app_root: AppRoot = _new_app_root()
	if app_root == null:
		_fail("main scene could not be loaded")
		return {}
	get_root().add_child(app_root)
	await _wait_for_draw()
	app_root.set_mobile_test_environment(true, MOBILE_SIZE)
	await _wait_for_draw()
	if not app_root.attempt_departure(FieldSession.CONDITION_BLACKOUT, flashlight_equipped, FIXED_SEED):
		_fail("mobile fixed-seed departure failed for %s" % file_name)
		return {}
	await _wait_for_draw()
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_explorer_facing_for_test(Vector2.RIGHT)
	app_root.set_process(false)
	field_view.set_process(false)
	await _wait_for_draw()
	var explorer_screen: Vector2 = _screen_point(
		(field_view.get_node("%Explorer") as Node2D).get_global_transform_with_canvas().origin,
		MOBILE_SIZE
	)
	var pad_screen_rect: Rect2 = _direction_pad_screen_rect(app_root.mobile_controls_node(), MOBILE_SIZE)
	var image: Image = _viewport_image(MOBILE_SIZE, file_name)
	if image == null or not _save_image(image, file_name):
		return {}
	var state: Dictionary = {
		"image": image,
		"explorer_screen": explorer_screen,
		"pad_screen_rect": pad_screen_rect,
		"lighting_state": field_view.lighting_state_snapshot()["state"],
	}
	app_root.queue_free()
	await process_frame
	return state


func _validate_mobile_pair(unprepared: Dictionary, flashlight: Dictionary) -> bool:
	if unprepared["lighting_state"] != "blackout_unprepared" or flashlight["lighting_state"] != "blackout_flashlight":
		_fail("mobile pair does not contain the two intended lighting states")
		return false
	var unprepared_origin := unprepared["explorer_screen"] as Vector2
	var flashlight_origin := flashlight["explorer_screen"] as Vector2
	if unprepared_origin.distance_to(flashlight_origin) > 0.5:
		_fail("mobile pair camera/explorer origins differ")
		return false
	var pad_rect := flashlight["pad_screen_rect"] as Rect2
	if pad_rect.grow(12.0).has_point(flashlight_origin) or flashlight_origin.x <= pad_rect.end.x + 12.0:
		_fail("mobile explorer/flashlight origin overlaps the movement pad origin=%s pad=%s" % [flashlight_origin, pad_rect])
		return false
	var roi := Rect2i(
		int(flashlight_origin.x + 20.0),
		maxi(0, int(flashlight_origin.y - 58.0)),
		mini(260, MOBILE_SIZE.x - int(flashlight_origin.x + 20.0)),
		mini(116, MOBILE_SIZE.y - maxi(0, int(flashlight_origin.y - 58.0)))
	)
	var mean_luma_gain: float = _mean_luma_gain(unprepared["image"] as Image, flashlight["image"] as Image, roi)
	if mean_luma_gain < 2.0:
		_fail("mobile flashlight forward ROI is not visually distinct gain=%.3f roi=%s" % [mean_luma_gain, roi])
		return false
	print("PLAYER_VISIBILITY_MOBILE_PAIR origin=%s pad=%s forward_roi=%s mean_luma_gain=%.3f" % [flashlight_origin, pad_rect, roi, mean_luma_gain])
	return true


func _mean_luma_gain(dark_image: Image, light_image: Image, roi: Rect2i) -> float:
	var total_gain: float = 0.0
	var sample_count: int = 0
	for y: int in range(roi.position.y, roi.end.y):
		for x: int in range(roi.position.x, roi.end.x):
			var dark: Color = dark_image.get_pixel(x, y)
			var light: Color = light_image.get_pixel(x, y)
			var dark_luma: float = (0.2126 * dark.r + 0.7152 * dark.g + 0.0722 * dark.b) * 255.0
			var light_luma: float = (0.2126 * light.r + 0.7152 * light.g + 0.0722 * light.b) * 255.0
			total_gain += light_luma - dark_luma
			sample_count += 1
	return total_gain / float(maxi(1, sample_count))


func _new_app_root() -> AppRoot:
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
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


func _direction_pad_screen_rect(controls: MobileFieldControls, screen_size: Vector2i) -> Rect2:
	var direction_rects: Array = controls.environment_snapshot()["direction_button_rects"] as Array
	var merged := Rect2()
	for rect_variant: Variant in direction_rects:
		var screen_rect: Rect2 = _screen_rect(rect_variant as Rect2, screen_size)
		merged = screen_rect if not merged.has_area() else merged.merge(screen_rect)
	return merged


func _screen_point(logical_point: Vector2, screen_size: Vector2i) -> Vector2:
	var logical_size: Vector2 = get_root().get_visible_rect().size
	var screen_scale: float = minf(float(screen_size.x) / logical_size.x, float(screen_size.y) / logical_size.y)
	var letterbox_offset: Vector2 = (Vector2(screen_size) - logical_size * screen_scale) * 0.5
	return letterbox_offset + logical_point * screen_scale


func _screen_rect(logical_rect: Rect2, screen_size: Vector2i) -> Rect2:
	var top_left: Vector2 = _screen_point(logical_rect.position, screen_size)
	var bottom_right: Vector2 = _screen_point(logical_rect.end, screen_size)
	return Rect2(top_left, bottom_right - top_left)


func _wait_for_draw() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw


func _viewport_image(expected_size: Vector2i, label: String) -> Image:
	var image: Image = get_root().get_texture().get_image()
	if image.get_size() != expected_size:
		_fail("%s size=%s expected=%s" % [label, image.get_size(), expected_size])
		return null
	return image


func _save_image(image: Image, file_name: String) -> bool:
	var target_path: String = "%s/%s" % [EVIDENCE_DIRECTORY, file_name]
	var save_error: Error = image.save_png(ProjectSettings.globalize_path(target_path))
	if save_error != OK:
		_fail("%s save_error=%d" % [file_name, save_error])
		return false
	return true


func _fail(message: String) -> void:
	printerr("PLAYER_VISIBILITY_OCCLUSION_SCREENSHOT_FAIL %s" % message)
	quit(1)
