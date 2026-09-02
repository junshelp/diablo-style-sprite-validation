extends SceneTree

const FIELD_SCENE_PATH: String = "res://scenes/field/field_session.tscn"
const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const DESKTOP_SIZE: Vector2i = Vector2i(1280, 720)
const MOBILE_SIZE: Vector2i = Vector2i(844, 390)
const FIXED_SEED: int = 4_242
const FIXED_CLOCK_MS: int = 3_000_000_000

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = DESKTOP_SIZE
	var packed_field := load(FIELD_SCENE_PATH) as PackedScene
	_check(packed_field != null, "field scene loads for player visibility smoke")
	if packed_field == null:
		_finish()
		return
	var field_view := packed_field.instantiate() as FieldSessionView
	field_view.configure_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	field_view.configure_encounter_service(FieldEncounterService.new())
	get_root().add_child(field_view)
	await process_frame

	await _test_normal_and_restored_occlusion(field_view)
	await _test_blackout_visibility_boundaries(field_view)
	await _test_hidden_simulation_and_ai_independence(field_view)
	field_view.queue_free()
	await process_frame

	await _test_mobile_initial_safe_area()
	get_root().size = Vector2i(1600, 900)
	await create_timer(0.25).timeout
	_finish()


func _test_normal_and_restored_occlusion(field_view: FieldSessionView) -> void:
	for restored: bool in [false, true]:
		var session := _new_session(FieldSession.CONDITION_BLACKOUT if restored else FieldSession.CONDITION_NORMAL, true)
		session.lighting_restored = restored
		await _start_active_encounter(field_view, session)
		var player_position := Vector2(620.0, 450.0)
		field_view.move_explorer_to(player_position)
		field_view.set_explorer_facing_for_test(Vector2.DOWN)
		field_view.set_entity_pose_for_test(player_position + Vector2(0.0, 150.0), Vector2.LEFT)
		_check(field_view.entity_visible() and field_view.entity_player_visible(), "%s clear active entity is presented" % ("restored" if restored else "normal"))
		var wall_rect: Rect2 = field_view.named_sight_blocker(&"wall")
		var behind_wall := Vector2(player_position.x, wall_rect.position.y - 56.0)
		field_view.set_entity_pose_for_test(behind_wall, Vector2.LEFT)
		_check(field_view.entity_visible() and not field_view.entity_player_visible(), "%s wall hides presentation without deactivating encounter" % ("restored" if restored else "normal"))
		field_view.end_session()
		await process_frame


func _test_blackout_visibility_boundaries(field_view: FieldSessionView) -> void:
	var player_position := Vector2(620.0, 450.0)
	var unprepared := _new_session(FieldSession.CONDITION_BLACKOUT, false)
	await _start_active_encounter(field_view, unprepared)
	field_view.move_explorer_to(player_position)
	field_view.set_explorer_facing_for_test(Vector2.UP)
	field_view.set_entity_pose_for_test(player_position + Vector2(0.0, -90.0), Vector2.LEFT)
	_check(field_view.entity_player_visible(), "unprepared blackout presents a clear entity inside the minimum halo")
	field_view.set_entity_pose_for_test(player_position + Vector2(0.0, 150.0), Vector2.LEFT)
	_check(field_view.entity_visible() and not field_view.entity_player_visible(), "unprepared blackout hides a clear entity beyond the minimum halo")
	field_view.end_session()
	await process_frame

	var flashlight := _new_session(FieldSession.CONDITION_BLACKOUT, true)
	await _start_active_encounter(field_view, flashlight)
	field_view.move_explorer_to(player_position)
	field_view.set_explorer_facing_for_test(Vector2.UP)
	field_view.set_entity_pose_for_test(player_position + Vector2(0.0, -150.0), Vector2.LEFT)
	_check(field_view.entity_player_visible(), "flashlight presents a clear entity beyond the halo inside the cone")
	field_view.set_entity_pose_for_test(player_position + Vector2(-150.0, 0.0), Vector2.LEFT)
	_check(not field_view.entity_player_visible(), "flashlight hides a clear entity outside its cone")
	field_view.set_explorer_facing_for_test(Vector2.LEFT)
	_check(field_view.entity_player_visible(), "rotating the flashlight into the entity reveals it on the same frame")
	field_view.set_explorer_facing_for_test(Vector2.UP)
	_check(not field_view.entity_player_visible(), "rotating the flashlight away hides it on the same frame")

	var wall_rect: Rect2 = field_view.named_sight_blocker(&"wall")
	var behind_wall := Vector2(player_position.x, wall_rect.position.y - 56.0)
	field_view.set_entity_pose_for_test(behind_wall, Vector2.LEFT)
	_check(field_view.visual_light_path_blocked_for_test(player_position, behind_wall), "wall blocks the player-to-entity Physics2D ray")
	_check(not field_view.entity_player_visible(), "wall hides an entity that is otherwise inside flashlight direction and range")
	field_view.end_session()
	await process_frame


func _test_hidden_simulation_and_ai_independence(field_view: FieldSessionView) -> void:
	var session := _new_session(FieldSession.CONDITION_BLACKOUT, true)
	await _start_active_encounter(field_view, session)
	var player_position := Vector2(620.0, 450.0)
	var entity_position := Vector2(470.0, 450.0)
	field_view.move_explorer_to(player_position)
	field_view.set_explorer_facing_for_test(Vector2.LEFT)
	field_view.set_entity_pose_for_test(entity_position, Vector2.LEFT)
	_check(not field_view.sight_between_for_test(entity_position, Vector2.LEFT, player_position), "enemy AI cannot see the player while facing away")
	_check(field_view.entity_player_visible(), "player perception can reveal an entity independently from enemy AI sight")

	field_view.set_explorer_facing_for_test(Vector2.UP)
	_check(field_view.entity_visible() and not field_view.entity_player_visible(), "outside-cone entity remains encounter-active while its presentation is hidden")
	var before: Vector2 = field_view.entity_position()
	field_view.advance_field_frame_for_test(0.05)
	var after: Vector2 = field_view.entity_position()
	_check(after.distance_to(before) > 0.1, "hidden entity chase simulation advances its position")
	_check(field_view.encounter_snapshot()["state"] == "chasing" and field_view.entity_visible(), "hidden presentation does not change chase state or active root")
	_check(not field_view.entity_player_visible(), "hidden moving entity stays concealed while still outside the cone")
	field_view.end_session()
	await process_frame


func _test_mobile_initial_safe_area() -> void:
	get_root().size = MOBILE_SIZE
	var app_root: AppRoot = _new_app_root()
	_check(app_root != null, "main scene loads for mobile safe-area smoke")
	if app_root == null:
		return
	get_root().add_child(app_root)
	await _wait_for_layout()
	app_root.set_mobile_test_environment(true, MOBILE_SIZE)
	await _wait_for_layout()
	_check(app_root.attempt_departure(FieldSession.CONDITION_BLACKOUT, true, FIXED_SEED), "mobile blackout flashlight departure succeeds")
	await _wait_for_layout()
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var controls: MobileFieldControls = app_root.mobile_controls_node()
	var route: Dictionary = (app_root.active_field_session_snapshot()["route"] as Dictionary)
	var expected_position: Vector2 = route["entrance_position"] + FieldSessionView.MOBILE_INITIAL_EXPLORER_OFFSET
	_check(field_view.explorer_position().is_equal_approx(expected_position), "mobile initial explorer uses the dedicated control-safe position")
	var explorer_screen: Vector2 = _screen_point(
		(field_view.get_node("%Explorer") as Node2D).get_global_transform_with_canvas().origin,
		MOBILE_SIZE
	)
	var pad_screen_rect: Rect2 = _direction_pad_screen_rect(controls, MOBILE_SIZE)
	_check(not pad_screen_rect.grow(12.0).has_point(explorer_screen), "mobile explorer origin does not overlap the movement pad")
	_check(explorer_screen.x > pad_screen_rect.end.x + 12.0, "mobile flashlight origin starts to the right of the movement pad")
	var lighting: Dictionary = field_view.lighting_state_snapshot()
	_check(lighting["state"] == "blackout_flashlight", "mobile entry keeps the equipped blackout flashlight state")
	_check(float(lighting["explorer_lights"]["flashlight_energy"]) >= 2.0, "mobile-visible flashlight uses the strengthened cone energy")
	app_root.queue_free()
	await process_frame


func _start_active_encounter(field_view: FieldSessionView, session: FieldSession) -> void:
	field_view.start_session(session)
	await physics_frame
	_check(field_view.trigger_encounter_for_test(FieldEncounterState.TRIGGER_DEEP_ENTRY), "fixture encounter triggers")
	field_view.advance_encounter_for_test(FieldEncounterState.WARNING_DURATION_SECONDS + 0.01, false, false)
	field_view.set_process(false)
	_check(field_view.encounter_snapshot()["state"] == "chasing" and field_view.entity_visible(), "fixture reaches active chasing")


func _new_session(condition: StringName, flashlight_equipped: bool) -> FieldSession:
	return FieldSession.new(condition, flashlight_equipped, FIXED_SEED, FieldRouteBuilder.new(SeededRandom.new()).build(FIXED_SEED))


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


func _wait_for_layout() -> void:
	await process_frame
	await process_frame


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


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("PLAYER_VISIBILITY_OCCLUSION_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("PLAYER_VISIBILITY_OCCLUSION_PASS")
		quit(0)
		return
	printerr("PLAYER_VISIBILITY_OCCLUSION_FAIL count=%d" % _failures.size())
	quit(1)
