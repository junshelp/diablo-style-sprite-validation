extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EXPECTED_SCHEMA_FIELDS: Array[String] = [
	"schema_version",
	"departure_supply_units",
	"facility_parts",
	"producer_upgraded",
	"last_saved_unix_ms",
]

class FailingProfileStorage:
	extends ProfileStoragePort

	var _document: Dictionary
	var write_attempts: int = 0

	func _init(initial_document: Dictionary) -> void:
		_document = initial_document.duplicate(true)

	func profile_exists() -> bool:
		return true

	func read_profile() -> Dictionary:
		return _document.duplicate(true)

	func write_profile(_document_to_write: Dictionary) -> Error:
		write_attempts += 1
		return ERR_CANT_CREATE

	func last_error_message() -> String:
		return "intentional write failure"

	func stored_document() -> Dictionary:
		return _document.duplicate(true)


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_insufficient_supply_no_write()
	_test_fractional_pre_save_and_restart_document()
	_test_storage_failure_blocks_session()
	_test_seeded_route_and_session_reset()
	_test_normalized_eight_way_speed()
	await _test_scene_departure_collision_camera_return_and_clock()
	_finish()


func _test_insufficient_supply_no_write() -> void:
	var now_ms: int = 100_000
	var profile := HomeProfile.new(0.75, 2, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var service := HomeProfileService.new(FakeClock.new(now_ms), storage)
	var expedition := ExpeditionService.new(service, FieldRouteBuilder.new(SeededRandom.new()))
	var writes_before: int = storage.write_count()
	var before_document: Dictionary = storage.stored_document()
	var result: ExpeditionService.DepartureResult = expedition.depart(profile, FieldSession.CONDITION_NORMAL, true, 11)
	_check(not result.ok, "less than one supply rejects departure")
	_check(result.session == null, "insufficient supply creates no field session")
	_check(storage.write_count() == writes_before, "insufficient supply performs no storage write")
	_check(storage.stored_document() == before_document, "insufficient supply preserves the stored document")


func _test_fractional_pre_save_and_restart_document() -> void:
	var now_ms: int = 200_000
	var profile := HomeProfile.new(1.5, 7, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	var service := HomeProfileService.new(clock, storage)
	var expedition := ExpeditionService.new(service, FieldRouteBuilder.new(SeededRandom.new()))
	var result: ExpeditionService.DepartureResult = expedition.depart(profile, FieldSession.CONDITION_NORMAL, true, 22)
	_check(result.ok, "one supply is persisted before a field session is returned")
	if not result.ok:
		return
	_check_float(result.profile.departure_supply_units, 0.5, "departure subtracts exactly one and preserves fractional progress")
	_check_float(float(storage.stored_document()["departure_supply_units"]), 0.5, "stored supply is consumed before transition")
	_check(_has_exact_schema_fields(storage.stored_document()), "departure storage still has exactly schema v1 fields")
	_check(not storage.stored_document().has("route") and not storage.stored_document().has("field_session"), "route and session are not stored")

	var restarted: HomeProfileService.LoadResult = HomeProfileService.new(clock, storage).load_or_create()
	_check(restarted.ok, "restart loads the consumed profile")
	if restarted.ok:
		_check_float(restarted.profile.departure_supply_units, 0.5, "restart does not refund consumed supply")


func _test_storage_failure_blocks_session() -> void:
	var now_ms: int = 300_000
	var profile := HomeProfile.new(1.25, 0, false, now_ms)
	var before_document: Dictionary = profile.to_document()
	var storage := FailingProfileStorage.new(before_document)
	var service := HomeProfileService.new(FakeClock.new(now_ms), storage)
	var expedition := ExpeditionService.new(service, FieldRouteBuilder.new(SeededRandom.new()))
	var result: ExpeditionService.DepartureResult = expedition.depart(profile, FieldSession.CONDITION_BLACKOUT, false, 33)
	_check(not result.ok, "storage failure rejects departure")
	_check(result.session == null, "storage failure creates no field session")
	_check(storage.write_attempts == 1, "storage failure is observed at the pre-save boundary")
	_check(storage.stored_document() == before_document, "failed pre-save preserves stored data")
	_check_float(profile.departure_supply_units, 1.25, "failed pre-save preserves the in-memory source profile")


func _test_seeded_route_and_session_reset() -> void:
	var route_a: FieldRoute = FieldRouteBuilder.new(SeededRandom.new()).build(4_242)
	var route_b: FieldRoute = FieldRouteBuilder.new(SeededRandom.new()).build(4_242)
	var route_c: FieldRoute = FieldRouteBuilder.new(SeededRandom.new()).build(7_777)
	var signature_a: Dictionary = _route_choice_signature(route_a)
	var signature_b: Dictionary = _route_choice_signature(route_b)
	var signature_c: Dictionary = _route_choice_signature(route_c)
	_check(signature_a == signature_b, "same seed reproduces module order, branch and object positions")
	var changed_choices: Array[String] = _changed_route_choices(signature_a, signature_c)
	_check(not changed_choices.is_empty(), "fixed seeds 4242 and 7777 vary actual route choices independently of seed identity")
	if not changed_choices.is_empty():
		print("ROUTE_CHOICE_VARIATION seeds=4242,7777 changed=%s" % ",".join(changed_choices))
	_check(route_a.module_count() <= 6, "route respects the six-module cap")
	_check(route_a.branch_count() == 1, "route exposes exactly one branch")
	_check(route_a.is_entrance_to_endpoint_reachable(), "entrance can reach the endpoint in the route graph")
	_check(route_a.entrance_position == FieldRouteBuilder.ENTRANCE_POSITION, "route exposes the fixed entrance anchor")
	_check(route_a.endpoint_position == Vector2(2620.0, 450.0), "route exposes the fixed endpoint anchor")
	_check(not route_a.placeholder_objects.is_empty(), "route exposes deterministic placeholder objects")

	var first := FieldSession.new(FieldSession.CONDITION_NORMAL, true, 1, route_a)
	first.crowbar_count = 0
	first.fuse_count = 0
	var second := FieldSession.new(FieldSession.CONDITION_BLACKOUT, false, 2, route_c)
	_check(second.condition == FieldSession.CONDITION_BLACKOUT, "field session carries the selected condition")
	_check(not second.flashlight_equipped, "field session carries flashlight selection")
	_check(second.crowbar_count == 1 and second.fuse_count == 1, "each departure resets the free test tools")


func _route_choice_signature(route: FieldRoute) -> Dictionary:
	var snapshot: Dictionary = route.snapshot()
	return {
		"main_module_ids": (snapshot["main_module_ids"] as Array).duplicate(true),
		"branch_main_index": int(snapshot["branch_main_index"]),
		"branch_direction": int(snapshot["branch_direction"]),
		"branch_position": snapshot["branch_position"],
		"placeholder_objects": (snapshot["placeholder_objects"] as Array).duplicate(true),
	}


func _changed_route_choices(first: Dictionary, second: Dictionary) -> Array[String]:
	var changed: Array[String] = []
	for field_name: String in [
		"main_module_ids",
		"branch_main_index",
		"branch_direction",
		"branch_position",
		"placeholder_objects",
	]:
		if first[field_name] != second[field_name]:
			changed.append(field_name)
	return changed


func _test_normalized_eight_way_speed() -> void:
	var explorer := ExplorerController.new()
	var cardinal: Vector2 = explorer.velocity_for_input(Vector2.RIGHT)
	var diagonal: Vector2 = explorer.velocity_for_input(Vector2(1.0, 1.0))
	_check_float(cardinal.length(), explorer.movement_speed, "cardinal movement uses configured speed")
	_check_float(diagonal.length(), explorer.movement_speed, "diagonal movement is normalized to cardinal speed")
	explorer.free()


func _test_scene_departure_collision_camera_return_and_clock() -> void:
	get_root().size = Vector2i(960, 540)
	var packed_scene := load(MAIN_SCENE_PATH) as PackedScene
	_check(packed_scene != null, "main scene loads for departure integration")
	if packed_scene == null:
		return

	var now_ms: int = 400_000
	var profile := HomeProfile.new(1.5, 0, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	var service := HomeProfileService.new(clock, storage)
	var expedition := ExpeditionService.new(service, FieldRouteBuilder.new(SeededRandom.new()))
	var app_root := packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", service)
	app_root.call("configure_expedition_service", expedition)
	get_root().add_child(app_root)
	await process_frame

	var compact_surface := app_root.get_node("%CompactSurface") as Control
	var home_status := app_root.get_node("%HomeStatus") as VBoxContainer
	var condition_select := home_status.get_node("%ConditionSelect") as OptionButton
	var flashlight_select := home_status.get_node("%FlashlightSelect") as OptionButton
	var departure_button := home_status.get_node("%DepartureButton") as Button
	var loadout_label := home_status.get_node("TestLoadout") as Label
	_check(_viewport_contains(compact_surface.get_global_rect()), "compact surface stays inside 960x540")
	_check(compact_surface.get_global_rect().encloses(condition_select.get_global_rect()), "condition selector is not clipped at 960x540")
	_check(compact_surface.get_global_rect().encloses(flashlight_select.get_global_rect()), "flashlight selector is not clipped at 960x540")
	_check(compact_surface.get_global_rect().encloses(departure_button.get_global_rect()), "departure action is not clipped at 960x540")
	_check(compact_surface.get_global_rect().encloses(loadout_label.get_global_rect()), "free crowbar and fuse notice is not clipped at 960x540")

	var departed: bool = bool(app_root.call("attempt_departure", FieldSession.CONDITION_NORMAL, true, 4_242))
	_check(departed, "successful pre-save transitions the app to field")
	await process_frame
	await physics_frame
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var first_snapshot: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	_check(app_root.call("current_surface_mode") == AppRoot.EXPANDED_FIELD_MODE, "departure expands the field surface")
	_check(field_view.visible, "field presentation is visible after departure")
	_check(first_snapshot["condition"] == "normal" and bool(first_snapshot["flashlight_equipped"]), "normal flashlight session reaches presentation")
	_check(int(first_snapshot["crowbar_count"]) == 1 and int(first_snapshot["fuse_count"]) == 1, "presentation session starts with one of each test tool")
	var route_snapshot: Dictionary = first_snapshot["route"]
	_check(field_view.camera_bounds() == route_snapshot["bounds"], "following Camera2D is bounded by the finite route")
	var field_viewport_rect := Rect2(Vector2.ZERO, get_root().get_visible_rect().size)
	_check(field_viewport_rect.encloses((field_view.get_node("%ConditionLabel") as Label).get_global_rect()), "field condition HUD is not clipped at 960x540")
	_check(field_viewport_rect.encloses((field_view.get_node("%LoadoutLabel") as Label).get_global_rect()), "field loadout HUD is not clipped at 960x540")
	_check(field_viewport_rect.encloses((field_view.get_node("%RouteLabel") as Label).get_global_rect()), "field route HUD is not clipped at 960x540")
	var camera_start: Vector2 = field_view.camera_global_position()
	field_view.move_explorer_to(Vector2(1700.0, 450.0))
	await process_frame
	_check(field_view.camera_global_position().x > camera_start.x, "Camera2D follows explorer movement inside route bounds")

	var solids: Array[Rect2] = field_view.solid_rectangles()
	_check(solids.size() >= 2, "field presentation creates solid wall and obstacle rectangles")
	if solids.size() >= 2:
		var obstacle: Rect2 = solids[solids.size() - 2]
		field_view.move_explorer_to(Vector2(obstacle.position.x - 42.0, obstacle.get_center().y))
		await physics_frame
		field_view.move_explorer_for_test(Vector2.RIGHT, 1.0)
		_check(field_view.explorer_position().x < obstacle.position.x, "explorer cannot pass through the column collision")

	clock.advance(HomeProfile.BASE_INTERVAL_MS / 2)
	_check(bool(app_root.call("refresh_home_profile")), "real-time supply refresh continues during field")
	var in_field_profile: Dictionary = app_root.call("home_profile_snapshot") as Dictionary
	_check_float(float(in_field_profile["departure_supply_units"]), 1.0, "field time produces supply from preserved half progress")

	var entrance_position: Vector2 = route_snapshot["entrance_position"]
	field_view.move_explorer_to(entrance_position + Vector2(110.0, 0.0))
	_check(not field_view.try_return_at_entrance(), "return is rejected away from the physical entrance radius")
	field_view.move_explorer_to(entrance_position)
	_check(field_view.try_return_at_entrance(), "interacting at the physical entrance requests return")
	await process_frame
	_check(app_root.call("current_surface_mode") == AppRoot.COMPACT_HOME_MODE, "physical entrance return restores compact home")
	_check((app_root.call("active_field_session_snapshot") as Dictionary).is_empty(), "returned field session is discarded from memory")
	_check(int((app_root.call("home_profile_snapshot") as Dictionary)["facility_parts"]) == 0, "entrance return grants no reward in this slice")

	var second_departed: bool = bool(app_root.call("attempt_departure", FieldSession.CONDITION_BLACKOUT, false, 7_777))
	_check(second_departed, "produced supply can start a second selected-condition session")
	var second_snapshot: Dictionary = app_root.call("active_field_session_snapshot") as Dictionary
	_check(second_snapshot["condition"] == "blackout" and not bool(second_snapshot["flashlight_equipped"]), "blackout without flashlight is retained in memory")
	_check(int(second_snapshot["crowbar_count"]) == 1 and int(second_snapshot["fuse_count"]) == 1, "second departure resets both tools")
	field_view.move_explorer_to((second_snapshot["route"] as Dictionary)["entrance_position"])
	_check(field_view.try_return_at_entrance(), "second session can also return physically")
	await process_frame

	app_root.queue_free()
	await process_frame
	var restarted_service := HomeProfileService.new(clock, storage)
	var restarted_expedition := ExpeditionService.new(restarted_service, FieldRouteBuilder.new(SeededRandom.new()))
	var restarted_app := packed_scene.instantiate() as Control
	restarted_app.call("configure_home_profile_service", restarted_service)
	restarted_app.call("configure_expedition_service", restarted_expedition)
	get_root().add_child(restarted_app)
	await process_frame
	_check(restarted_app.call("current_surface_mode") == AppRoot.COMPACT_HOME_MODE, "restart always starts at compact home")
	_check((restarted_app.call("active_field_session_snapshot") as Dictionary).is_empty(), "restart restores no field route or session")
	_check_float(float((restarted_app.call("home_profile_snapshot") as Dictionary)["departure_supply_units"]), 0.0, "restart keeps both supply consumptions")
	restarted_app.queue_free()
	await process_frame
	get_root().size = Vector2i(1600, 900)


func _has_exact_schema_fields(document: Dictionary) -> bool:
	if document.size() != EXPECTED_SCHEMA_FIELDS.size():
		return false
	for field_name: String in EXPECTED_SCHEMA_FIELDS:
		if not document.has(field_name):
			return false
	return true


func _viewport_contains(rect: Rect2) -> bool:
	return Rect2(Vector2.ZERO, get_root().get_visible_rect().size).encloses(rect)


func _check_float(actual: float, expected: float, message: String) -> void:
	_check(is_equal_approx(actual, expected), "%s (actual=%f expected=%f)" % [message, actual, expected])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("DEPARTURE_MOVEMENT_ROUTE_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("DEPARTURE_MOVEMENT_ROUTE_PASS")
		quit(0)
		return
	printerr("DEPARTURE_MOVEMENT_ROUTE_FAIL count=%d" % _failures.size())
	quit(1)
