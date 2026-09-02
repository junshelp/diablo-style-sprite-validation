extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const MOBILE_LANDSCAPE_SIZE: Vector2i = Vector2i(844, 390)
const MOBILE_PORTRAIT_SIZE: Vector2i = Vector2i(390, 844)
const DESKTOP_SIZE: Vector2i = Vector2i(1280, 720)
const FIXED_CLOCK_MS: int = 3_000_000_000

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = MOBILE_LANDSCAPE_SIZE
	var app_root: AppRoot = _new_app_root()
	if app_root == null:
		_finish()
		return
	get_root().add_child(app_root)
	await process_frame
	app_root.set_mobile_test_environment(true, MOBILE_LANDSCAPE_SIZE)
	await _wait_for_layout()

	_test_mobile_home(app_root)
	var home_status := app_root.get_node("%HomeStatus") as VBoxContainer
	var condition_select := home_status.get_node("%ConditionSelect") as OptionButton
	var flashlight_select := home_status.get_node("%FlashlightSelect") as OptionButton
	condition_select.select(1)
	flashlight_select.select(0)
	(home_status.get_node("%DepartureButton") as Button).pressed.emit()
	await _wait_for_layout()

	_check(app_root.current_surface_mode() == AppRoot.EXPANDED_FIELD_MODE, "mobile HOME departure button reaches FIELD")
	var first_session: Dictionary = app_root.active_field_session_snapshot()
	_check(first_session.get("condition", &"") == FieldSession.CONDITION_BLACKOUT and bool(first_session.get("flashlight_equipped", false)), "mobile preparation selectors preserve approved condition/loadout meaning")
	_check(is_equal_approx(float(app_root.home_profile_snapshot().get("departure_supply_units", -1.0)), 1.0), "mobile departure consumes the same saved one supply")

	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var controls: MobileFieldControls = app_root.mobile_controls_node()
	await _test_field_movement(field_view, controls)
	await _test_menu_and_context_actions(app_root, field_view, controls)

	_check(app_root.current_surface_mode() == AppRoot.COMPACT_HOME_MODE, "mobile entrance action returns to HOME through existing extraction")
	_check(app_root.attempt_departure(FieldSession.CONDITION_NORMAL, true, 9_002), "second mobile field session starts for hide priority")
	await _wait_for_layout()
	field_view = app_root.get_node("%FieldSessionView") as FieldSessionView
	_check(field_view.trigger_encounter_for_test(FieldEncounterState.TRIGGER_DEEP_ENTRY), "mobile action fixture triggers the existing one-shot encounter")
	field_view.advance_encounter_for_test(FieldEncounterState.WARNING_DURATION_SECONDS + 0.01, false, false)
	var hide_id: StringName = field_view.move_explorer_to_hide_spot_type(FieldHideSpotState.TYPE_CABINET)
	_check(hide_id != &"" and controls.press_action_for_test(), "mobile action is accepted beside a chase hide spot")
	var hiding_state: Dictionary = app_root.active_field_session_snapshot()
	var hiding_encounter: Dictionary = hiding_state.get("encounter", {}) as Dictionary
	_check(bool(hiding_encounter.get("hide_active", false)), "E-equivalent mobile action gives chasing hide priority")

	get_root().size = MOBILE_PORTRAIT_SIZE
	app_root.set_mobile_test_environment(true, MOBILE_PORTRAIT_SIZE)
	await _wait_for_layout()
	var portrait: Dictionary = controls.environment_snapshot()
	_check(bool(portrait["portrait_notice_visible"]), "mobile portrait shows the rotation notice")
	_check(bool(portrait["portrait_notice_blocks_input"]), "portrait notice consumes gameplay touch")
	var portrait_notice := controls.get_node("%PortraitNotice") as Control
	var portrait_notice_rect: Rect2 = _screen_rect(portrait_notice.get_global_rect(), MOBILE_PORTRAIT_SIZE)
	_check(
		portrait_notice_rect.grow(0.25).encloses(Rect2(Vector2.ZERO, Vector2(MOBILE_PORTRAIT_SIZE))),
		"portrait blocker covers the full CSS viewport (rect=%s)" % portrait_notice_rect
	)
	_check(not bool(portrait["gameplay_input_enabled"]) and not bool(portrait["landscape_controls_visible"]), "portrait disables FIELD pad/action")
	_check(not controls.hold_direction_for_test(Vector2.RIGHT) and not controls.press_action_for_test(), "portrait rejects movement and context commands")
	_check(controls.movement_vector() == Vector2.ZERO and field_view.mobile_movement_vector() == Vector2.ZERO, "portrait transition clears held movement")

	get_root().size = DESKTOP_SIZE
	app_root.set_mobile_test_environment(false, DESKTOP_SIZE)
	await _wait_for_layout()
	var desktop: Dictionary = controls.environment_snapshot()
	_check(not bool(desktop["portrait_notice_visible"]) and not bool(desktop["landscape_controls_visible"]), "non-touch desktop hides the entire mobile overlay")
	var explorer := field_view.get_node("%Explorer") as ExplorerController
	var keyboard_diagonal: Vector2 = explorer.velocity_for_input(Vector2(1.0, 1.0))
	_check(is_equal_approx(keyboard_diagonal.length(), explorer.movement_speed), "desktop keyboard diagonal normalization remains unchanged")
	_check(not controls.hold_direction_for_test(Vector2.LEFT), "hidden desktop overlay cannot inject touch movement")

	field_view.end_session()
	app_root.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	get_root().size = Vector2i(1600, 900)
	_finish()


func _test_mobile_home(app_root: AppRoot) -> void:
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(MOBILE_LANDSCAPE_SIZE))
	var compact := app_root.get_node("%CompactSurface") as PanelContainer
	var home_status := app_root.get_node("%HomeStatus") as VBoxContainer
	var compact_screen_rect: Rect2 = _screen_rect(compact.get_global_rect(), MOBILE_LANDSCAPE_SIZE)
	_check(viewport_rect.encloses(compact_screen_rect), "mobile HOME surface stays inside 844x390")
	_check(compact_screen_rect.size.distance_to(Vector2(820.0, 366.0)) < 2.0, "mobile HOME uses the narrow landscape viewport without clipping")
	for control_name: StringName in [&"ConditionSelect", &"FlashlightSelect", &"DepartureButton", &"UpgradeButton"]:
		var control := home_status.get_node("%%%s" % control_name) as Control
		var control_rect: Rect2 = _screen_rect(control.get_global_rect(), MOBILE_LANDSCAPE_SIZE) if control != null else Rect2()
		_check(control != null and viewport_rect.encloses(control_rect), "mobile HOME %s stays visible" % control_name)
		if control != null:
			_check(control_rect.size.y >= 44.0, "mobile HOME %s has a touch-sized height" % control_name)
	_check(not (home_status.get_node("TestLoadout") as Label).visible, "mobile HOME hides the nonessential loadout debug line")
	_check(not (home_status.get_node("%StorageState") as Label).visible, "mobile HOME hides the nonessential storage debug line")


func _test_field_movement(field_view: FieldSessionView, controls: MobileFieldControls) -> void:
	var mobile_state: Dictionary = controls.environment_snapshot()
	_check(bool(mobile_state["landscape_controls_visible"]) and bool(mobile_state["gameplay_input_enabled"]), "mobile landscape FIELD shows enabled pad/action controls")
	_check(Vector2i(mobile_state["viewport_size"]) == MOBILE_LANDSCAPE_SIZE, "mobile layout uses the browser CSS viewport boundary")
	var expected_layout_scale: float = maxf(1600.0 / float(MOBILE_LANDSCAPE_SIZE.x), 900.0 / float(MOBILE_LANDSCAPE_SIZE.y))
	_check(is_equal_approx(float(mobile_state["layout_scale"]), expected_layout_scale), "mobile controls scale logical targets back to CSS pixels")
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(MOBILE_LANDSCAPE_SIZE))
	var direction_rects: Array = mobile_state["direction_button_rects"] as Array
	_check(direction_rects.size() == 8, "mobile direction pad exposes exactly eight directions")
	for direction_rect_variant: Variant in direction_rects:
		var direction_rect: Rect2 = _screen_rect(direction_rect_variant as Rect2, MOBILE_LANDSCAPE_SIZE)
		_check(viewport_rect.encloses(direction_rect), "direction touch target stays inside mobile viewport")
		_check(direction_rect.size.x >= 58.0 and direction_rect.size.y >= 58.0, "direction touch target is at least 58x58")
	var action_rect: Rect2 = _screen_rect(mobile_state["action_button_rect"] as Rect2, MOBILE_LANDSCAPE_SIZE)
	_check(viewport_rect.encloses(action_rect) and action_rect.size.x >= 120.0 and action_rect.size.y >= 72.0, "mobile action button is large and fully visible")
	for direction_rect_variant: Variant in direction_rects:
		var direction_screen_rect: Rect2 = _screen_rect(direction_rect_variant as Rect2, MOBILE_LANDSCAPE_SIZE)
		_check(not action_rect.intersects(direction_screen_rect), "action button does not overlap the direction pad")

	var directions: Array[Vector2] = [
		Vector2.RIGHT,
		Vector2(0.70710678, 0.70710678),
		Vector2.DOWN,
		Vector2(-0.70710678, 0.70710678),
		Vector2.LEFT,
		Vector2(-0.70710678, -0.70710678),
		Vector2.UP,
		Vector2(0.70710678, -0.70710678),
	]
	var direction_buttons: Array[Button] = [
		controls.get_node("%EastButton") as Button,
		controls.get_node("%SouthEastButton") as Button,
		controls.get_node("%SouthButton") as Button,
		controls.get_node("%SouthWestButton") as Button,
		controls.get_node("%WestButton") as Button,
		controls.get_node("%NorthWestButton") as Button,
		controls.get_node("%NorthButton") as Button,
		controls.get_node("%NorthEastButton") as Button,
	]
	for direction_index: int in range(directions.size()):
		var direction: Vector2 = directions[direction_index]
		var direction_button: Button = direction_buttons[direction_index]
		field_view.move_explorer_to(Vector2(620.0, 450.0))
		var before: Vector2 = field_view.explorer_position()
		_emit_touch(direction_button, true)
		_check(controls.movement_vector().is_equal_approx(direction), "direction button hold is accepted for %s" % direction)
		await physics_frame
		await physics_frame
		_check(field_view.mobile_movement_vector().is_equal_approx(direction), "held touch direction reaches explorer input %s" % direction)
		_check(field_view.explorer_facing_direction().is_equal_approx(direction), "held touch direction preserves 8-way facing %s" % direction)
		_check(field_view.explorer_position().distance_to(before) > 0.1, "held direction moves the explorer for %s" % direction)
		_emit_touch(direction_button, false)
		await physics_frame
		_check(controls.movement_vector() == Vector2.ZERO and field_view.mobile_movement_vector() == Vector2.ZERO, "release returns touch movement to neutral")
	_check(controls.hold_direction_for_test(Vector2.RIGHT), "cancel fixture begins movement")
	controls.cancel_movement_for_test()
	_check(controls.movement_vector() == Vector2.ZERO and field_view.mobile_movement_vector() == Vector2.ZERO, "cancel/outside boundary cannot leave stuck movement")


func _test_menu_and_context_actions(app_root: AppRoot, field_view: FieldSessionView, controls: MobileFieldControls) -> void:
	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(locker_id != &"" and controls.press_action_for_test(), "mobile action opens the same nearby object interaction")
	await _wait_for_layout()
	var menu: ObjectInteractionMenu = field_view.interaction_menu_node()
	var paused_snapshot: Dictionary = app_root.active_field_session_snapshot()
	_check(menu.visible and bool(paused_snapshot.get("field_simulation_paused", false)), "mobile object menu preserves field-only pause")
	_check(not controls.gameplay_input_enabled() and not bool(controls.environment_snapshot()["landscape_controls_visible"]), "open object menu blocks FIELD pad/action")
	_check(not controls.hold_direction_for_test(Vector2.RIGHT) and controls.movement_vector() == Vector2.ZERO, "blocked menu cannot start movement")
	var back_rect: Rect2 = _screen_rect(menu.back_button_rect(), MOBILE_LANDSCAPE_SIZE)
	_check(Rect2(Vector2.ZERO, Vector2(MOBILE_LANDSCAPE_SIZE)).encloses(back_rect), "touch back button stays inside mobile menu viewport")
	_check(back_rect.size.x >= 120.0 and back_rect.size.y >= 44.0, "touch back button has a usable target")

	(menu.get_node("%UseItemButton") as Button).pressed.emit()
	_check(menu.current_stage() == ObjectInteractionMenu.STAGE_ITEM, "touch item-use opens the approved second stage")
	(menu.get_node("%BackButton") as Button).pressed.emit()
	_check(menu.current_stage() == ObjectInteractionMenu.STAGE_OBJECT and menu.visible, "touch back returns item stage to object stage")
	(menu.get_node("%BackButton") as Button).pressed.emit()
	await _wait_for_layout()
	_check(not menu.visible and controls.gameplay_input_enabled(), "touch back closes the object stage and restores FIELD controls")
	_check(controls.press_action_for_test(), "mobile action can reopen the nearby object menu after touch back")
	await _wait_for_layout()
	(menu.get_node("%UseItemButton") as Button).pressed.emit()
	(menu.get_node("%CrowbarButton") as Button).pressed.emit()
	await _wait_for_layout()
	var after_tool: Dictionary = app_root.active_field_session_snapshot()
	_check(not menu.visible and not bool(after_tool.get("field_simulation_paused", true)), "touch tool choice closes menu before applying the existing result")
	_check(int(after_tool.get("crowbar_count", -1)) == 1 and int(after_tool.get("unextracted_parts", 0)) > 0, "touch tool choice preserves non-consumed crowbar and existing reward semantics")
	_check(controls.gameplay_input_enabled(), "FIELD touch controls restore after menu result")

	_check(field_view.move_explorer_to_extraction_point_for_test(ExtractionUpgradeRules.EXTRACTION_ENTRANCE), "mobile fixture reaches the physical entrance")
	_check(controls.press_action_for_test(), "mobile action invokes the entrance extraction context")
	await _wait_for_layout()


func _new_app_root() -> AppRoot:
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	_check(packed_scene != null, "main scene loads for mobile Web controls smoke")
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


func _screen_rect(logical_rect: Rect2, screen_size: Vector2i) -> Rect2:
	var logical_size: Vector2 = get_root().get_visible_rect().size
	if logical_size.x <= 0.0 or logical_size.y <= 0.0:
		return logical_rect
	var screen_scale: float = minf(
		float(screen_size.x) / logical_size.x,
		float(screen_size.y) / logical_size.y
	)
	var letterbox_offset: Vector2 = (Vector2(screen_size) - logical_size * screen_scale) * 0.5
	return Rect2(letterbox_offset + logical_rect.position * screen_scale, logical_rect.size * screen_scale)


func _emit_touch(button: Button, pressed: bool) -> void:
	var touch_event := InputEventScreenTouch.new()
	touch_event.index = 0
	touch_event.pressed = pressed
	button.gui_input.emit(touch_event)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("MOBILE_WEB_CONTROLS_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("MOBILE_WEB_CONTROLS_PASS")
		quit(0)
		return
	printerr("MOBILE_WEB_CONTROLS_FAIL count=%d" % _failures.size())
	quit(1)
