extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const JSON_TEST_PATH: String = "user://task_010_home_clock_save_test.json"
const EXPECTED_SCHEMA_FIELDS: Array[String] = [
	"schema_version",
	"departure_supply_units",
	"facility_parts",
	"producer_upgraded",
	"last_saved_unix_ms",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_new_profile_and_memory_reload()
	_test_base_production_boundaries()
	_test_upgraded_production_boundaries()
	_test_cap_discards_hidden_backlog()
	_test_future_schema_memory_failure()
	_test_json_round_trip_and_future_schema()
	await _test_compact_ui_and_expanded_refresh()
	_cleanup_json_test_file()
	_check(not FileAccess.file_exists(JSON_TEST_PATH), "isolated user JSON fixture is removed after the test")
	_finish()


func _test_new_profile_and_memory_reload() -> void:
	var clock: FakeClock = FakeClock.new(1_234_567_890)
	var storage: MemoryProfileStorage = MemoryProfileStorage.new()
	var service: HomeProfileService = HomeProfileService.new(clock, storage)
	var created: HomeProfileService.LoadResult = service.load_or_create()
	_check(created.ok, "new profile is created")
	if not created.ok:
		return

	_check_float(created.profile.departure_supply_units, 2.0, "new profile starts with two supply units")
	_check(created.profile.facility_parts == 0, "new profile starts with zero facility parts")
	_check(not created.profile.producer_upgraded, "new profile producer starts at base level")
	_check(created.profile.last_saved_unix_ms == clock.now_unix_ms(), "new profile saves the injected clock")
	_check(_has_exact_schema_fields(storage.stored_document()), "schema v1 writes exactly five approved fields")

	var reloaded: HomeProfileService.LoadResult = HomeProfileService.new(clock, storage).load_or_create()
	_check(reloaded.ok, "memory profile reload succeeds")
	if reloaded.ok:
		_check(reloaded.profile.to_document() == created.profile.to_document(), "memory reload preserves the profile")


func _test_base_production_boundaries() -> void:
	var start_ms: int = 20_000_000
	var initial: HomeProfile = HomeProfile.new(1.0, 7, false, start_ms)
	var storage: MemoryProfileStorage = MemoryProfileStorage.new(initial.to_document())
	var clock: FakeClock = FakeClock.new(start_ms + HomeProfile.BASE_INTERVAL_MS / 2)
	var service: HomeProfileService = HomeProfileService.new(clock, storage)
	var half_interval: HomeProfileService.LoadResult = service.load_or_create()
	_check(half_interval.ok, "base partial elapsed load succeeds")
	if not half_interval.ok:
		return

	_check_float(half_interval.profile.departure_supply_units, 1.5, "six minutes preserves half a base supply unit")
	_check(half_interval.profile.available_supply_units() == 1, "partial base production is not available early")
	_check(half_interval.profile.facility_parts == 7, "offline base production does not alter facility parts")

	clock.advance(HomeProfile.BASE_INTERVAL_MS / 2 - 1)
	var before_boundary: HomeProfileService.LoadResult = service.refresh(half_interval.profile)
	_check(before_boundary.ok, "base refresh before boundary succeeds")
	_check(before_boundary.profile.available_supply_units() == 1, "base supply is not produced one millisecond early")

	clock.advance(1)
	var at_boundary: HomeProfileService.LoadResult = service.refresh(before_boundary.profile)
	_check(at_boundary.ok, "base refresh at boundary succeeds")
	_check_float(at_boundary.profile.departure_supply_units, 2.0, "base producer creates one unit at twelve minutes")

	clock.advance(30 * 24 * 60 * 60 * 1000)
	var long_gap: HomeProfileService.LoadResult = service.refresh(at_boundary.profile)
	_check(long_gap.ok, "long base offline gap succeeds")
	_check_float(long_gap.profile.departure_supply_units, 2.0, "base supply stops at capacity two")
	_check(long_gap.profile.facility_parts == 7, "long offline gap still does not alter facility parts")


func _test_upgraded_production_boundaries() -> void:
	var start_ms: int = 40_000_000
	var initial: HomeProfile = HomeProfile.new(0.0, 9, true, start_ms)
	var storage: MemoryProfileStorage = MemoryProfileStorage.new(initial.to_document())
	var clock: FakeClock = FakeClock.new(start_ms + HomeProfile.UPGRADED_INTERVAL_MS - 1)
	var service: HomeProfileService = HomeProfileService.new(clock, storage)
	var before_boundary: HomeProfileService.LoadResult = service.load_or_create()
	_check(before_boundary.ok, "upgraded load before boundary succeeds")
	if not before_boundary.ok:
		return

	_check(before_boundary.profile.available_supply_units() == 0, "upgraded supply is not produced one millisecond early")
	clock.advance(1)
	var first_unit: HomeProfileService.LoadResult = service.refresh(before_boundary.profile)
	_check_float(first_unit.profile.departure_supply_units, 1.0, "upgraded producer creates one unit at eight minutes")

	clock.advance(HomeProfile.UPGRADED_INTERVAL_MS * 2)
	var at_capacity: HomeProfileService.LoadResult = service.refresh(first_unit.profile)
	_check_float(at_capacity.profile.departure_supply_units, 3.0, "upgraded producer reaches capacity three after two more intervals")
	_check(at_capacity.profile.facility_parts == 9, "upgraded offline production preserves facility parts")
	_check(at_capacity.profile.producer_upgraded, "offline production preserves upgraded state")

	clock.advance(365 * 24 * 60 * 60 * 1000)
	var long_gap: HomeProfileService.LoadResult = service.refresh(at_capacity.profile)
	_check_float(long_gap.profile.departure_supply_units, 3.0, "upgraded long offline gap stops at capacity three")


func _test_cap_discards_hidden_backlog() -> void:
	var start_ms: int = 80_000_000
	var storage: MemoryProfileStorage = MemoryProfileStorage.new(HomeProfile.new(2.0, 0, false, start_ms).to_document())
	var clock: FakeClock = FakeClock.new(start_ms + 14 * 24 * 60 * 60 * 1000)
	var service: HomeProfileService = HomeProfileService.new(clock, storage)
	var capped: HomeProfileService.LoadResult = service.load_or_create()
	_check(capped.ok, "capped profile load succeeds")
	if not capped.ok:
		return

	_check(capped.profile.last_saved_unix_ms == clock.now_unix_ms(), "cap advances the saved clock and discards elapsed backlog")
	var simulated_post_spend: Dictionary = capped.profile.to_document()
	simulated_post_spend["departure_supply_units"] = 1.0
	storage.seed_profile(simulated_post_spend)
	var same_moment: HomeProfileService.LoadResult = HomeProfileService.new(clock, storage).load_or_create()
	_check_float(same_moment.profile.departure_supply_units, 1.0, "no hidden backlog appears after a capped period")


func _test_future_schema_memory_failure() -> void:
	var future_document: Dictionary = {
		"schema_version": 99,
		"departure_supply_units": 1.0,
		"facility_parts": 4,
		"producer_upgraded": false,
		"last_saved_unix_ms": 100,
		"future_only": true,
	}
	var storage: MemoryProfileStorage = MemoryProfileStorage.new(future_document)
	var writes_before: int = storage.write_count()
	var result: HomeProfileService.LoadResult = HomeProfileService.new(FakeClock.new(200), storage).load_or_create()
	_check(not result.ok, "future schema fails explicitly in memory storage")
	_check(result.error_message.contains("unsupported schema_version"), "future schema reports the unsupported version")
	_check(storage.write_count() == writes_before, "future schema failure does not write")
	_check(storage.stored_document() == future_document, "future schema memory document remains unchanged")


func _test_json_round_trip_and_future_schema() -> void:
	_cleanup_json_test_file()
	var storage: JsonProfileStorage = JsonProfileStorage.new(JSON_TEST_PATH)
	var clock: FakeClock = FakeClock.new(500_000_000)
	var service: HomeProfileService = HomeProfileService.new(clock, storage)
	var created: HomeProfileService.LoadResult = service.load_or_create()
	_check(created.ok, "isolated user JSON profile is created")
	_check(storage.profile_exists(), "isolated user JSON file exists after create")
	_check(_has_exact_schema_fields(storage.read_profile()), "isolated JSON contains the five schema v1 fields")

	var below_capacity: Dictionary = storage.read_profile()
	below_capacity["departure_supply_units"] = 1.0
	below_capacity["last_saved_unix_ms"] = clock.now_unix_ms()
	_check(storage.write_profile(below_capacity) == OK, "isolated JSON accepts a below-capacity profile fixture")
	clock.advance(HomeProfile.BASE_INTERVAL_MS)
	var reloaded: HomeProfileService.LoadResult = HomeProfileService.new(clock, storage).load_or_create()
	_check(reloaded.ok, "isolated user JSON round-trip reload succeeds")
	_check_float(reloaded.profile.departure_supply_units, 2.0, "isolated JSON reload applies twelve minutes of offline production")

	var future_document: Dictionary = {
		"schema_version": 2,
		"departure_supply_units": 1.0,
		"facility_parts": 5,
		"producer_upgraded": true,
		"last_saved_unix_ms": clock.now_unix_ms(),
		"future_only": "preserve me",
	}
	_check(storage.write_profile(future_document) == OK, "future schema fixture writes to isolated JSON")
	var before_failure: Dictionary = storage.read_profile()
	var future_result: HomeProfileService.LoadResult = HomeProfileService.new(clock, storage).load_or_create()
	var after_failure: Dictionary = storage.read_profile()
	_check(not future_result.ok, "future schema JSON load fails explicitly")
	_check(future_result.error_message.contains("unsupported schema_version"), "future JSON load reports unsupported schema")
	_check(after_failure == before_failure, "future schema JSON remains unchanged after failure")


func _test_compact_ui_and_expanded_refresh() -> void:
	get_root().size = Vector2i(960, 540)
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	_check(packed_scene != null, "main scene loads for compact UI smoke")
	if packed_scene == null:
		return

	var clock: FakeClock = FakeClock.new(900_000_000)
	var profile: HomeProfile = HomeProfile.new(1.5, 3, false, clock.now_unix_ms())
	var storage: MemoryProfileStorage = MemoryProfileStorage.new(profile.to_document())
	var service: HomeProfileService = HomeProfileService.new(clock, storage)
	var app_root: Control = packed_scene.instantiate() as Control
	app_root.call("configure_home_profile_service", service)
	get_root().add_child(app_root)
	await process_frame

	var compact_surface: Control = app_root.get_node("%CompactSurface") as Control
	var surface_toggle: Button = app_root.get_node("%SurfaceToggle") as Button
	var supply_ticker: Label = app_root.get_node("%SupplyTicker") as Label
	var home_status: VBoxContainer = app_root.get_node("%HomeStatus") as VBoxContainer
	var supply_value: Label = home_status.get_node("%SupplyValue") as Label
	var supply_progress: Label = home_status.get_node("%SupplyProgress") as Label
	var parts_value: Label = home_status.get_node("%FacilityPartsValue") as Label
	var producer_value: Label = home_status.get_node("%ProducerStateValue") as Label
	var storage_state: Label = home_status.get_node("%StorageState") as Label

	_check(supply_value.text == "1 / 2", "compact UI displays available base supply and capacity")
	_check(supply_progress.text.contains("06:00") and supply_progress.text.contains("50%"), "compact UI displays deterministic partial progress")
	_check(parts_value.text == "3", "compact UI displays facility parts")
	_check(producer_value.text == "기본 · 12분 · 최대 2", "compact UI displays the base producer rule")
	_check(storage_state.text == "schema v1 · 저장됨", "compact UI displays schema v1 storage state")
	_check(_viewport_contains(compact_surface.get_global_rect()), "compact surface remains inside a 960x540 viewport")
	_check(_viewport_contains(surface_toggle.get_global_rect()), "surface toggle remains inside a 960x540 viewport")
	_check(compact_surface.get_global_rect().encloses(supply_progress.get_global_rect()), "compact status text is not clipped by its surface")
	_check(compact_surface.get_global_rect().encloses(supply_value.get_global_rect()), "compact supply value is not clipped")
	_check(compact_surface.get_global_rect().encloses(parts_value.get_global_rect()), "compact facility parts value is not clipped")
	_check(compact_surface.get_global_rect().encloses(producer_value.get_global_rect()), "compact producer state is not clipped")
	_check(compact_surface.get_global_rect().encloses(storage_state.get_global_rect()), "compact storage state is not clipped")

	surface_toggle.pressed.emit()
	await process_frame
	clock.advance(HomeProfile.BASE_INTERVAL_MS / 2)
	var refresh_ok: bool = bool(app_root.call("refresh_home_profile"))
	_check(refresh_ok, "real-time refresh succeeds while expanded")
	var expanded_snapshot: Dictionary = app_root.call("home_profile_snapshot") as Dictionary
	_check_float(float(expanded_snapshot["departure_supply_units"]), 2.0, "expanded mode does not stop real-time production")
	_check(supply_ticker.text == "출발 보급 2 / 2", "expanded ticker reflects real-time supply production")

	surface_toggle.pressed.emit()
	await process_frame
	_check(supply_value.text == "2 / 2", "returning home shows the supply produced while expanded")
	app_root.queue_free()
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


func _cleanup_json_test_file() -> void:
	if FileAccess.file_exists(JSON_TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(JSON_TEST_PATH))


func _check_float(actual: float, expected: float, message: String) -> void:
	_check(is_equal_approx(actual, expected), "%s (actual=%f expected=%f)" % [message, actual, expected])


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("HOME_CLOCK_SAVE_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("HOME_CLOCK_SAVE_PASS")
		quit(0)
		return

	printerr("HOME_CLOCK_SAVE_FAIL count=%d" % _failures.size())
	quit(1)
