extends SceneTree

const FIELD_SCENE_PATH: String = "res://scenes/field/field_session.tscn"
const VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720)
const FIXED_SEED: int = 4_242

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = VIEWPORT_SIZE
	var packed_field := load(FIELD_SCENE_PATH) as PackedScene
	_check(packed_field != null, "field scene loads for visibility lighting smoke")
	if packed_field == null:
		_finish()
		return
	var field_view := packed_field.instantiate() as FieldSessionView
	field_view.configure_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	field_view.configure_encounter_service(FieldEncounterService.new())
	get_root().add_child(field_view)
	await process_frame

	await _test_state_priority(field_view)
	await _test_facing_and_hud_isolation(field_view)
	await _test_blocker_occlusion(field_view)
	await _test_actual_fuse_transition(field_view)

	field_view.queue_free()
	await process_frame
	get_root().size = Vector2i(1600, 900)
	_finish()


func _test_state_priority(field_view: FieldSessionView) -> void:
	var normal := _new_session(FieldSession.CONDITION_NORMAL, false)
	field_view.start_session(normal)
	await physics_frame
	var normal_state: Dictionary = field_view.lighting_state_snapshot()
	_check(normal_state["state"] == "normal_ambient", "normal uses stable world ambient")
	_check(not bool(normal_state["explorer_lights"]["minimum_visible"]) and not bool(normal_state["explorer_lights"]["flashlight_visible"]), "normal does not depend on player-local lights")
	_check(int(normal_state["visible_fixture_count"]) == 0, "normal keeps restored fixtures off")
	field_view.end_session()
	await process_frame

	var unprepared := _new_session(FieldSession.CONDITION_BLACKOUT, false)
	field_view.start_session(unprepared)
	await physics_frame
	var unprepared_state: Dictionary = field_view.lighting_state_snapshot()
	_check(unprepared_state["state"] == "blackout_unprepared", "blackout without equipment selects the narrowest state")
	_check(bool(unprepared_state["explorer_lights"]["minimum_visible"]) and not bool(unprepared_state["explorer_lights"]["flashlight_visible"]), "unprepared blackout keeps only short local visibility")
	_check(float(unprepared_state["minimum_visibility_radius"]) < float(unprepared_state["flashlight_cone_range"]), "minimum local visibility is shorter than flashlight range")
	field_view.end_session()
	await process_frame

	var flashlight := _new_session(FieldSession.CONDITION_BLACKOUT, true)
	field_view.start_session(flashlight)
	await physics_frame
	var flashlight_state: Dictionary = field_view.lighting_state_snapshot()
	_check(flashlight_state["state"] == "blackout_flashlight", "equipped blackout selects directional flashlight")
	_check(bool(flashlight_state["explorer_lights"]["minimum_visible"]) and bool(flashlight_state["explorer_lights"]["flashlight_visible"]), "flashlight keeps minimum local light and adds a cone")
	_check(bool(flashlight_state["explorer_lights"]["minimum_shadow_enabled"]) and bool(flashlight_state["explorer_lights"]["flashlight_shadow_enabled"]), "player-local lights cast blocker shadows")
	field_view.end_session()
	await process_frame

	var restored := _new_session(FieldSession.CONDITION_BLACKOUT, true)
	restored.lighting_restored = true
	field_view.start_session(restored)
	await physics_frame
	var restored_state: Dictionary = field_view.lighting_state_snapshot()
	_check(restored_state["state"] == "restored_fixtures", "lighting_restored takes priority over blackout and equipped flashlight")
	_check(not bool(restored_state["explorer_lights"]["minimum_visible"]) and not bool(restored_state["explorer_lights"]["flashlight_visible"]), "restoration ends blackout player-light dependency")
	_check(int(restored_state["fixture_count"]) == restored.route.module_count() and int(restored_state["visible_fixture_count"]) == restored.route.module_count(), "restoration lights each bounded route module including its branch")
	_check(bool(restored_state["fixture_shadows_enabled"]), "restored fixtures cast blocker shadows")
	_check(float(normal_state["darkness_strength"]) < float(restored_state["darkness_strength"]) and float(restored_state["darkness_strength"]) < float(flashlight_state["darkness_strength"]) and float(flashlight_state["darkness_strength"]) < float(unprepared_state["darkness_strength"]), "four visibility states preserve the approved external ordering")
	_check((normal_state["ambient"] as Color).get_luminance() > (restored_state["ambient"] as Color).get_luminance(), "restored ambient remains visually distinct from normal")
	field_view.end_session()
	await process_frame


func _test_facing_and_hud_isolation(field_view: FieldSessionView) -> void:
	var session := _new_session(FieldSession.CONDITION_BLACKOUT, true)
	field_view.start_session(session)
	await physics_frame
	var samples: Array[Dictionary] = [
		{"input": Vector2.RIGHT, "expected": Vector2.RIGHT},
		{"input": Vector2(1.0, 1.0), "expected": Vector2(0.70710678, 0.70710678)},
		{"input": Vector2.DOWN, "expected": Vector2.DOWN},
		{"input": Vector2(-1.0, 1.0), "expected": Vector2(-0.70710678, 0.70710678)},
		{"input": Vector2.LEFT, "expected": Vector2.LEFT},
		{"input": Vector2(-1.0, -1.0), "expected": Vector2(-0.70710678, -0.70710678)},
		{"input": Vector2.UP, "expected": Vector2.UP},
		{"input": Vector2(1.0, -1.0), "expected": Vector2(0.70710678, -0.70710678)},
	]
	for sample: Dictionary in samples:
		field_view.move_explorer_for_test(sample["input"], 0.0)
		var expected := sample["expected"] as Vector2
		_check(field_view.explorer_facing_direction().is_equal_approx(expected), "last movement quantizes to facing %s" % expected)
		var light_state: Dictionary = field_view.lighting_state_snapshot()["explorer_lights"]
		_check(is_zero_approx(angle_difference(float(light_state["flashlight_rotation"]), expected.angle())), "flashlight cone rotates with facing %s" % expected)
	var held_facing: Vector2 = field_view.explorer_facing_direction()
	field_view.move_explorer_for_test(Vector2.ZERO, 1.0)
	_check(field_view.explorer_facing_direction().is_equal_approx(held_facing), "zero input preserves last non-zero flashlight facing")

	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(locker_id != &"" and field_view.open_object_interaction_for_test(locker_id), "blackout flashlight fixture opens the actual object menu")
	await process_frame
	var menu_state: Dictionary = field_view.lighting_state_snapshot()
	_check(menu_state["state"] == "blackout_flashlight", "field-only menu pause preserves current world lighting")
	_check(int(menu_state["hud_canvas_layer"]) == 2 and bool(menu_state["world_canvas_modulated"]), "HUD is isolated on its existing CanvasLayer above world modulation")
	_check(menu_state["hud_modulate"] == Color.WHITE and menu_state["menu_modulate"] == Color.WHITE, "HUD and menu retain task-080 modulation")
	_check(not bool(menu_state["legacy_screen_overlay_visible"]), "legacy full-screen darkness overlay stays disabled")
	_check(field_view.interaction_menu_node().visible, "object menu remains visible over darkened world")
	field_view.interaction_menu_node().go_back()
	field_view.end_session()
	await process_frame


func _test_blocker_occlusion(field_view: FieldSessionView) -> void:
	var session := _new_session(FieldSession.CONDITION_BLACKOUT, true)
	field_view.start_session(session)
	await physics_frame
	var lighting: Dictionary = field_view.lighting_state_snapshot()
	_check(int(lighting["solid_count"]) > 0 and int(lighting["occluder_count"]) == int(lighting["solid_count"]), "every current route solid has one visual light occluder")
	for blocker_name: StringName in [&"wall", &"column", &"closed_shutter"]:
		var blocker: Rect2 = field_view.named_sight_blocker(blocker_name)
		var occluder: LightOccluder2D = field_view.named_light_occluder(blocker_name)
		_check(blocker.has_area() and occluder != null, "%s shares collision and light-occlusion presence" % blocker_name)
		if blocker.has_area() and occluder != null:
			_check(occluder.occluder != null and occluder.occluder.polygon.size() == 4 and occluder.occluder_light_mask == 1, "%s uses a closed rectangular light occluder" % blocker_name)
			var probe: Array[Vector2] = _probe_points(blocker)
			_check(field_view.visual_light_path_blocked_for_test(probe[0], probe[1]), "%s blocks the same world-light path" % blocker_name)
	_check(not field_view.visual_light_path_blocked_for_test(Vector2(300.0, 450.0), Vector2(500.0, 450.0)), "open corridor keeps a clear local-light path")
	field_view.end_session()
	await process_frame


func _test_actual_fuse_transition(field_view: FieldSessionView) -> void:
	var session := _new_session(FieldSession.CONDITION_BLACKOUT, false)
	field_view.start_session(session)
	await physics_frame
	var panel_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_POWER_PANEL)
	_check(panel_id != &"" and field_view.open_object_interaction_for_test(panel_id), "actual power-panel interaction opens in blackout")
	field_view.interaction_menu_node().show_item_stage()
	field_view.interaction_menu_node().select_tool_for_test(ObjectInteractionRules.TOOL_FUSE)
	await process_frame
	var restored: Dictionary = field_view.lighting_state_snapshot()
	_check(session.lighting_restored and session.fuse_count == 0, "actual fuse result preserves session consume and restore semantics")
	_check(restored["state"] == "restored_fixtures" and int(restored["visible_fixture_count"]) == session.route.module_count(), "actual fuse result immediately activates restored fixtures")
	field_view.end_session()
	await process_frame


func _new_session(condition: StringName, flashlight_equipped: bool) -> FieldSession:
	return FieldSession.new(condition, flashlight_equipped, FIXED_SEED, FieldRouteBuilder.new(SeededRandom.new()).build(FIXED_SEED))


func _probe_points(blocker: Rect2) -> Array[Vector2]:
	var center: Vector2 = blocker.get_center()
	if blocker.size.x >= blocker.size.y:
		return [center + Vector2(0.0, -blocker.size.y * 0.5 - 36.0), center + Vector2(0.0, blocker.size.y * 0.5 + 36.0)]
	return [center + Vector2(-blocker.size.x * 0.5 - 36.0, 0.0), center + Vector2(blocker.size.x * 0.5 + 36.0, 0.0)]


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("FIELD_VISIBILITY_LIGHTING_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("FIELD_VISIBILITY_LIGHTING_PASS")
		quit(0)
		return
	printerr("FIELD_VISIBILITY_LIGHTING_FAIL count=%d" % _failures.size())
	quit(1)
