extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EPSILON: float = 0.001
const EXPECTED_SCHEMA_FIELDS: Array[String] = [
	"schema_version",
	"departure_supply_units",
	"facility_parts",
	"producer_upgraded",
	"last_saved_unix_ms",
]
const ACCEPTED_EVIDENCE_HASHES: Dictionary = {
	"res://_workspace/desktop-horror-prototype/evidence/task-000-bootstrap/compact.png": "c86c1c1f5aa15252ac768d864117914541a1f2c988dbdf2c8d5c3bb3d2787821",
	"res://_workspace/desktop-horror-prototype/evidence/task-000-bootstrap/expanded.png": "8c326318132104c2f43282f9e3fd12b6a84699ef41a3d304cd9351ed57af0732",
	"res://_workspace/desktop-horror-prototype/evidence/task-010-home-clock-save/compact.png": "7937f6925545da159b0281b575631a8e2909ad81c2cace60ba80efe8f457a312",
	"res://_workspace/desktop-horror-prototype/evidence/task-010-home-clock-save/expanded.png": "cadc0bcefc210a58048e7e3196c6b50fa5998166887482a9a30b6c7b8bee7564",
	"res://_workspace/desktop-horror-prototype/evidence/task-020-departure-movement-route/field-blackout.png": "af5bb691901d1e6e943f1dc8e94da6ea9bab94981b3e656fefa7849f1389606b",
	"res://_workspace/desktop-horror-prototype/evidence/task-020-departure-movement-route/field-normal.png": "9f20fbfbbaae287dd23c4dea3d81cece2af120084f56d204d9a20eab1fde9986",
	"res://_workspace/desktop-horror-prototype/evidence/task-020-departure-movement-route/home-preparation.png": "8040ffd1834e7bdfd774b4d794d96c5addbe840b1696693c563b4b0b92d34e40",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/blackout-no-flashlight.png": "39371e2818dc8fe3e2bc1204ced30b8d78d9c14a76d7fa381787aab21d40a50b",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/fuse-restored.png": "df51bd186a02fff12bea731fad6ba891b04dfcfe6151873dca89c408a35813a8",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/item-choice.png": "bdf1eb524e30155509d0f85c8f110a8b8432ddd2acdc30264ba23c9b8dd0d457",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/object-choice.png": "436bbf76cd8f41dd989402e363cab3f9b58636bf4070e728f2559d7864037918",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/chasing.png": "4794261310986f42ceffdb1f37a7d7db2b57672429cf099bc742e57911d24046",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/hide-resolved.png": "056339e17efc80aaaab5f6a9d3536edcf8228f79a34c5cc3f0ea9fbd1949aa8c",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/rescued-home.png": "0e4bd6c521b010cdda59d74a9e0d33a8fcbb9f0b7ecd08e50a5ee0bfa307e168",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/warning.png": "aeaf6bc7b68936b69957e31f93bef04d8744755cb180b44bcdfd592fc9b5f2ca",
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_reward_bounds_and_seeded_extra()
	_test_atomic_settlement_and_endpoint_rules()
	_test_atomic_upgrade_and_upgraded_production()
	_test_rescue_loss_boundary()
	_test_accepted_evidence_hashes()
	await _test_physical_extraction_and_failure_retry()
	await _test_hide_block_and_abort_restart_loss()
	await _test_endpoint_upgrade_second_departure_loop()
	_finish()


func _test_reward_bounds_and_seeded_extra() -> void:
	var interaction_service := FieldInteractionService.new(SeededRandom.new())
	var early: FieldSession = _new_session(4_242)
	var early_object: FieldObjectState = early.object_states[0]
	interaction_service.begin_interaction(early, early_object.object_id)
	var early_result: ObjectInteractionResult = interaction_service.prepare_base_search(early)
	_check(early_result.parts_delta == 2, "accepted normal base reward remains exactly two")
	_check(interaction_service.apply_result(early, early_result), "early normal result applies once")
	_check(early.unextracted_parts >= 1 and early.unextracted_parts <= 2, "one-object early reward remains in the approved 1..2 range")

	var all_five: FieldSession = _new_session(5_050)
	for state: FieldObjectState in all_five.object_states:
		_check(interaction_service.begin_interaction(all_five, state.object_id), "each finite-route object opens exactly once")
		var result: ObjectInteractionResult = interaction_service.prepare_base_search(all_five)
		_check(interaction_service.apply_result(all_five, result), "each finite-route object result applies")
	_check(all_five.object_states.size() == 5, "normal route exposes exactly five placeholder objects")
	_check(all_five.unextracted_parts >= 5 and all_five.unextracted_parts <= 6, "normal all-five reward remains in the approved 5..6 range")
	_check(all_five.unextracted_parts == ExtractionUpgradeRules.SESSION_REWARD_CAP, "named session cap clamps repeated normal rewards at six")

	var first: FieldSession = _new_session(4_242)
	var second: FieldSession = _new_session(4_242)
	var first_locker: FieldObjectState = _first_object(first, FieldObjectState.TYPE_LOCKER)
	var second_locker: FieldObjectState = second.object_state(first_locker.object_id)
	interaction_service.begin_interaction(first, first_locker.object_id)
	interaction_service.begin_interaction(second, second_locker.object_id)
	var first_crowbar: ObjectInteractionResult = interaction_service.prepare_tool(first, ObjectInteractionRules.TOOL_CROWBAR)
	var second_crowbar: ObjectInteractionResult = interaction_service.prepare_tool(second, ObjectInteractionRules.TOOL_CROWBAR)
	_check(first_crowbar.snapshot() == second_crowbar.snapshot(), "fixed seed reproduces crowbar extra before application")
	_check(first_crowbar.extra_parts == 1 and first_crowbar.parts_delta == 3, "chosen fixed seed exercises normal two plus one crowbar extra")
	first.unextracted_parts = 5
	interaction_service.apply_result(first, first_crowbar)
	_check(first.unextracted_parts == 6 and first_crowbar.parts_delta == 1, "crowbar extra is retained but actual applied delta respects cap six")


func _test_atomic_settlement_and_endpoint_rules() -> void:
	var now_ms: int = 2_000_000_000
	var clock := FakeClock.new(now_ms)
	var original := HomeProfile.new(0.5, 3, false, now_ms)
	var storage := MemoryProfileStorage.new(original.to_document())
	var service := HomeProfileService.new(clock, storage)
	var session: FieldSession = _new_session(501)
	session.unextracted_parts = 2
	var profile_before: Dictionary = original.to_document()
	var session_before: Dictionary = session.snapshot()
	var storage_before: Dictionary = storage.stored_document()
	storage.fail_next_write("forced settlement failure")
	var failed: HomeProfileService.SettlementResult = service.settle_extraction(
		original,
		session,
		ExtractionUpgradeRules.EXTRACTION_ENTRANCE
	)
	_check(not failed.ok, "forced extraction write fails")
	_check(original.to_document() == profile_before, "failed extraction leaves live profile byte-equivalent")
	_check(session.snapshot() == session_before, "failed extraction leaves session and unextracted parts byte-equivalent")
	_check(storage.stored_document() == storage_before, "failed extraction leaves stored document byte-equivalent")
	var retried: HomeProfileService.SettlementResult = service.settle_extraction(
		original,
		session,
		ExtractionUpgradeRules.EXTRACTION_ENTRANCE
	)
	_check(retried.ok and retried.confirmed_parts == 2, "same extraction retries successfully without inflated reward")
	_check(retried.profile.facility_parts == 5 and session.unextracted_parts == 0, "successful retry swaps candidate value and clears session reward")
	_check(session.extraction_settled and session.extraction_point == ExtractionUpgradeRules.EXTRACTION_ENTRANCE, "successful retry seals the session once")
	var stored_after_retry: Dictionary = storage.stored_document()
	var duplicate: HomeProfileService.SettlementResult = service.settle_extraction(
		retried.profile,
		session,
		ExtractionUpgradeRules.EXTRACTION_ENTRANCE
	)
	_check(not duplicate.ok and storage.stored_document() == stored_after_retry, "settled extraction cannot duplicate storage reward")

	var endpoint_profile := HomeProfile.new(0.0, 0, false, now_ms)
	var endpoint_storage := MemoryProfileStorage.new(endpoint_profile.to_document())
	var endpoint_service := HomeProfileService.new(clock, endpoint_storage)
	var endpoint_low: FieldSession = _new_session(502)
	var low_result: HomeProfileService.SettlementResult = endpoint_service.settle_extraction(
		endpoint_profile,
		endpoint_low,
		ExtractionUpgradeRules.EXTRACTION_ENDPOINT
	)
	_check(low_result.ok and low_result.confirmed_parts == 4 and low_result.profile.facility_parts == 4, "endpoint guarantees four when current reward is lower")
	var endpoint_high: FieldSession = _new_session(503)
	endpoint_high.unextracted_parts = 6
	var high_result: HomeProfileService.SettlementResult = endpoint_service.settle_extraction(
		low_result.profile,
		endpoint_high,
		ExtractionUpgradeRules.EXTRACTION_ENDPOINT
	)
	_check(high_result.ok and high_result.confirmed_parts == 6 and high_result.profile.facility_parts == 10, "endpoint never reduces an already higher bounded reward")


func _test_atomic_upgrade_and_upgraded_production() -> void:
	var now_ms: int = 2_100_000_000
	var clock := FakeClock.new(now_ms)
	var insufficient := HomeProfile.new(0.0, 3, false, now_ms)
	var insufficient_storage := MemoryProfileStorage.new(insufficient.to_document())
	var insufficient_service := HomeProfileService.new(clock, insufficient_storage)
	var insufficient_writes: int = insufficient_storage.write_attempt_count()
	var rejected: HomeProfileService.LoadResult = insufficient_service.upgrade_producer(insufficient)
	_check(not rejected.ok and insufficient.facility_parts == 3 and not insufficient.producer_upgraded, "upgrade rejects fewer than four parts without mutation")
	_check(insufficient_storage.write_attempt_count() == insufficient_writes, "insufficient upgrade never reaches storage")

	var original := HomeProfile.new(0.5, 5, false, now_ms)
	var storage := MemoryProfileStorage.new(original.to_document())
	var service := HomeProfileService.new(clock, storage)
	var original_before: Dictionary = original.to_document()
	var stored_before: Dictionary = storage.stored_document()
	storage.fail_next_write("forced upgrade failure")
	var failed: HomeProfileService.LoadResult = service.upgrade_producer(original)
	_check(not failed.ok and original.to_document() == original_before, "failed upgrade leaves live parts and producer byte-equivalent")
	_check(storage.stored_document() == stored_before, "failed upgrade leaves storage byte-equivalent")
	var upgraded: HomeProfileService.LoadResult = service.upgrade_producer(original)
	_check(upgraded.ok and upgraded.profile.facility_parts == 1 and upgraded.profile.producer_upgraded, "retry consumes exactly four and persists one-time upgrade")
	_check_float(upgraded.profile.departure_supply_units, 0.5, "upgrade preserves fractional supply progress")
	_check(upgraded.profile.production_interval_ms() == HomeProfile.UPGRADED_INTERVAL_MS and upgraded.profile.supply_capacity() == 3, "upgrade immediately selects eight-minute interval and cap three")
	var writes_after_upgrade: int = storage.write_attempt_count()
	var repurchase: HomeProfileService.LoadResult = service.upgrade_producer(upgraded.profile)
	_check(not repurchase.ok and storage.write_attempt_count() == writes_after_upgrade, "already-upgraded producer cannot repurchase or write")

	clock.advance(HomeProfile.UPGRADED_INTERVAL_MS / 2)
	var real_time: HomeProfileService.LoadResult = service.refresh(upgraded.profile)
	_check(real_time.ok, "upgraded real-time refresh succeeds")
	_check_float(real_time.profile.departure_supply_units, 1.0, "four upgraded minutes complete preserved half progress")
	clock.advance(HomeProfile.UPGRADED_INTERVAL_MS * 10)
	var capped: HomeProfileService.LoadResult = service.refresh(real_time.profile)
	_check_float(capped.profile.departure_supply_units, 3.0, "upgraded offline accrual caps at three")
	var consumed: HomeProfileService.LoadResult = service.consume_one_departure_supply(capped.profile)
	_check_float(consumed.profile.departure_supply_units, 2.0, "one upgraded supply can be consumed after cap")
	var no_backlog: HomeProfileService.LoadResult = service.refresh(consumed.profile)
	_check_float(no_backlog.profile.departure_supply_units, 2.0, "same-clock refresh reveals no hidden capped backlog")
	_check(_has_exact_schema_fields(storage.stored_document()), "upgrade and production keep exact schema v1 fields")


func _test_rescue_loss_boundary() -> void:
	var session: FieldSession = _new_session(504)
	session.unextracted_parts = 6
	var encounter_service := FieldEncounterService.new()
	encounter_service.try_trigger(session, FieldEncounterState.TRIGGER_DEEP_ENTRY)
	encounter_service.tick(session, FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	encounter_service.tick(session, EPSILON, true, true)
	encounter_service.tick(session, FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS, true, true)
	var rescued: Dictionary = encounter_service.tick(session, FieldEncounterState.DAMAGE_INVULNERABILITY_SECONDS, true, true)
	_check(bool(rescued["rescue_required"]) and int(rescued["lost_unextracted_parts"]) == 6, "rescue reports the bounded unextracted loss")
	_check(session.unextracted_parts == 0 and not session.extraction_settled, "rescue discards unconfirmed parts without pretending to extract")


func _test_accepted_evidence_hashes() -> void:
	for path: String in ACCEPTED_EVIDENCE_HASHES:
		_check(FileAccess.file_exists(path), "accepted evidence still exists: %s" % path)
		if FileAccess.file_exists(path):
			_check(FileAccess.get_sha256(path) == ACCEPTED_EVIDENCE_HASHES[path], "accepted evidence hash remains unchanged: %s" % path)


func _test_physical_extraction_and_failure_retry() -> void:
	get_root().size = Vector2i(960, 540)
	var fixture: Dictionary = await _spawn_app(HomeProfile.new(2.0, 0, false, 2_200_000_000), 2_200_000_000)
	var app_root := fixture["app"] as AppRoot
	var storage := fixture["storage"] as MemoryProfileStorage
	_check(app_root.attempt_departure(FieldSession.CONDITION_NORMAL, true, 4_242), "atomic presentation fixture departs")
	await process_frame
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	_check(not field_view.try_return_at_entrance(), "entrance extraction rejects a distant explorer")
	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(locker_id != &"" and field_view.open_object_interaction_for_test(locker_id), "early fixture opens one physical locker")
	field_view.interaction_menu_node().select_base_search_for_test()
	_check(int(app_root.active_field_session_snapshot()["unextracted_parts"]) == 2, "field HUD state keeps two parts unconfirmed")
	var stored_before: Dictionary = storage.stored_document()
	_check(int(stored_before["facility_parts"]) == 0, "home parts remain separate before extraction")
	field_view.move_explorer_to_extraction_point_for_test(ExtractionUpgradeRules.EXTRACTION_ENTRANCE)
	_check(field_view.extraction_prompt_text().contains("입구 회수 지점"), "physical entrance proximity exposes its E prompt")
	var profile_before: Dictionary = app_root.home_profile_snapshot()
	var session_before: Dictionary = app_root.active_field_session_snapshot()
	var surface_before: StringName = app_root.current_surface_mode()
	storage.fail_next_write("forced scene settlement failure")
	_check(field_view.try_return_at_entrance(), "physical entrance accepts a settlement request")
	await process_frame
	_check(app_root.home_profile_snapshot() == profile_before, "failed scene settlement leaves profile unchanged")
	_check(app_root.active_field_session_snapshot() == session_before, "failed scene settlement leaves session unchanged")
	_check(storage.stored_document() == stored_before, "failed scene settlement leaves stored profile unchanged")
	_check(app_root.current_surface_mode() == surface_before and field_view.visible, "failed scene settlement remains on the same field surface")
	_check(field_view.try_return_at_entrance(), "same physical entrance can retry")
	await process_frame
	_check(app_root.current_surface_mode() == AppRoot.COMPACT_HOME_MODE, "successful retry returns to compact home")
	_check(int(app_root.home_profile_snapshot()["facility_parts"]) == 2, "successful entrance retry confirms exactly the early reward")
	var home_status := app_root.get_node("%HomeStatus") as VBoxContainer
	var message := home_status.get_node("%DepartureMessage") as Label
	_check(message.text.contains("입구") and message.text.contains("확정 부품 2") and message.text.contains("집 설비 부품 2") and message.text.contains("체력 3"), "normal return feedback distinguishes point, confirmed parts, home total and HP")
	for node_path: String in ["%UpgradeButton", "%DepartureButton", "%DepartureMessage", "%ProducerStateValue", "%FacilityPartsValue"]:
		_check(_viewport_contains((home_status.get_node(node_path) as Control).get_global_rect()), "%s is unclipped at 960x540 home" % node_path)
	app_root.queue_free()
	await process_frame


func _test_hide_block_and_abort_restart_loss() -> void:
	var now_ms: int = 2_300_000_000
	var profile := HomeProfile.new(2.0, 5, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	var fixture: Dictionary = await _spawn_app_with_ports(profile, clock, storage)
	var app_root := fixture["app"] as AppRoot
	_check(app_root.attempt_departure(FieldSession.CONDITION_NORMAL, true, 5_050), "abort fixture departs after saving supply")
	await process_frame
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	field_view.open_object_interaction_for_test(locker_id)
	field_view.interaction_menu_node().select_base_search_for_test()
	var unattempted_id: StringName = _first_unattempted_object_id(field_view.object_snapshots())
	field_view.move_explorer_to_object(unattempted_id)
	field_view.open_object_interaction_for_test(unattempted_id)
	field_view.get_node("%Explorer").position = app_root.active_field_session_snapshot()["route"]["endpoint_position"]
	_check(not field_view.try_extract_at_endpoint(), "open object menu blocks endpoint settlement")
	field_view.interaction_menu_node().go_back()
	var live_session := field_view.get("_session") as FieldSession
	var encounter_service := FieldEncounterService.new()
	encounter_service.try_trigger(live_session, FieldEncounterState.TRIGGER_DEEP_ENTRY)
	encounter_service.tick(live_session, FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	var hide_spot_id: StringName = live_session.hide_spots[0].spot_id
	_check(encounter_service.begin_hide(live_session, hide_spot_id), "chasing fixture begins hide entry")
	field_view.get_node("%Explorer").position = app_root.active_field_session_snapshot()["route"]["endpoint_position"]
	_check(not field_view.try_extract_at_endpoint(), "active hide entry blocks endpoint settlement")
	_check(int(app_root.active_field_session_snapshot()["unextracted_parts"]) == 2, "abort fixture still carries unconfirmed parts")
	field_view.end_session()
	app_root.queue_free()
	await process_frame
	var restarted_service := HomeProfileService.new(clock, storage)
	var restarted := (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as AppRoot
	restarted.configure_home_profile_service(restarted_service)
	restarted.configure_expedition_service(ExpeditionService.new(restarted_service, FieldRouteBuilder.new(SeededRandom.new())))
	get_root().add_child(restarted)
	await process_frame
	_check(restarted.active_field_session_snapshot().is_empty(), "app abort/restart restores no field session")
	_check(int(restarted.home_profile_snapshot()["facility_parts"]) == 5, "app abort/restart loses unconfirmed parts and preserves confirmed home parts")
	_check_float(float(restarted.home_profile_snapshot()["departure_supply_units"]), 1.0, "app abort/restart preserves consumed departure supply")
	restarted.queue_free()
	await process_frame


func _test_endpoint_upgrade_second_departure_loop() -> void:
	var now_ms: int = 2_400_000_000
	var fixture: Dictionary = await _spawn_app(HomeProfile.new(2.0, 0, false, now_ms), now_ms)
	var app_root := fixture["app"] as AppRoot
	var clock := fixture["clock"] as FakeClock
	var storage := fixture["storage"] as MemoryProfileStorage
	_check(app_root.attempt_departure(FieldSession.CONDITION_NORMAL, true, 9_050), "new profile first departure consumes one of two supplies")
	await process_frame
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	var live_session := field_view.get("_session") as FieldSession
	var encounter_service := FieldEncounterService.new()
	_check(encounter_service.try_trigger(live_session, FieldEncounterState.TRIGGER_DEEP_ENTRY), "full-loop fixture starts warning")
	encounter_service.tick(live_session, FieldEncounterState.WARNING_DURATION_SECONDS, false, false)
	_check(field_view.encounter_snapshot()["state"] == "chasing", "full-loop fixture enters chase")
	field_view.move_explorer_to_extraction_point_for_test(ExtractionUpgradeRules.EXTRACTION_ENDPOINT)
	_check(field_view.extraction_prompt_text().contains("종착점") and field_view.extraction_prompt_text().contains("최소 4"), "physical endpoint proximity exposes distinct guarantee prompt")
	_check(field_view.try_extract_at_endpoint(), "chasing explorer can extract only after physically reaching endpoint")
	await process_frame
	var returned: Dictionary = app_root.home_profile_snapshot()
	_check(int(returned["facility_parts"]) == 4 and not bool(returned["producer_upgraded"]), "first endpoint extraction guarantees exactly four on a new profile")
	_check_float(float(returned["departure_supply_units"]), 1.0, "first endpoint extraction preserves remaining supply")
	_check(app_root.current_surface_mode() == AppRoot.COMPACT_HOME_MODE, "endpoint extraction returns to compact home")
	_check(app_root.attempt_producer_upgrade(), "four endpoint parts buy producer upgrade")
	var upgraded: Dictionary = app_root.home_profile_snapshot()
	_check(int(upgraded["facility_parts"]) == 0 and bool(upgraded["producer_upgraded"]), "upgrade consumes exactly four and persists producer flag")
	var home_status := app_root.get_node("%HomeStatus") as VBoxContainer
	_check((home_status.get_node("%ProducerStateValue") as Label).text.contains("8분") and (home_status.get_node("%ProducerStateValue") as Label).text.contains("최대 3"), "home immediately renders upgraded rule")
	_check((home_status.get_node("%UpgradeButton") as Button).disabled and (home_status.get_node("%UpgradeButton") as Button).text.contains("강화 완료"), "one-time upgrade action becomes visibly complete")
	_check(app_root.attempt_departure(FieldSession.CONDITION_NORMAL, true, 9_051), "remaining supply starts immediate second departure")
	await process_frame
	field_view = app_root.get_node("%FieldSessionView") as FieldSessionView
	field_view.set_process(false)
	var second: Dictionary = app_root.active_field_session_snapshot()
	_check(int(second["encounter"]["hp"]) == 3 and second["encounter"]["state"] == "dormant", "second field resets HP3 and chase dormant")
	_check_float(float(app_root.home_profile_snapshot()["departure_supply_units"]), 0.0, "second departure consumes the remaining supply")
	clock.advance(HomeProfile.UPGRADED_INTERVAL_MS / 2)
	_check(app_root.refresh_home_profile(), "upgraded producer refreshes while second field remains active")
	_check_float(float(app_root.home_profile_snapshot()["departure_supply_units"]), 0.5, "four real-time minutes produce half an upgraded supply in field")
	clock.advance(HomeProfile.UPGRADED_INTERVAL_MS / 2)
	_check(app_root.refresh_home_profile(), "second in-field upgraded refresh succeeds")
	_check_float(float(app_root.home_profile_snapshot()["departure_supply_units"]), 1.0, "eight real-time minutes complete one upgraded supply in field")
	_check(app_root.current_surface_mode() == AppRoot.EXPANDED_FIELD_MODE and not app_root.active_field_session_snapshot().is_empty(), "home production does not interrupt second field")
	_check(_has_exact_schema_fields(storage.stored_document()), "full loop leaves storage at exact schema v1")
	for node_path: String in ["%ConditionLabel", "%RouteLabel", "%SessionStateLabel", "%HpLabel", "%EncounterStateLabel"]:
		_check(_viewport_contains((field_view.get_node(node_path) as Control).get_global_rect()), "%s is unclipped at 960x540 field" % node_path)
	field_view.end_session()
	app_root.queue_free()
	await process_frame
	get_root().size = Vector2i(1600, 900)


func _spawn_app(profile: HomeProfile, now_ms: int) -> Dictionary:
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	return await _spawn_app_with_ports(profile, clock, storage)


func _spawn_app_with_ports(profile: HomeProfile, clock: FakeClock, storage: MemoryProfileStorage) -> Dictionary:
	var service := HomeProfileService.new(clock, storage)
	var app_root := (load(MAIN_SCENE_PATH) as PackedScene).instantiate() as AppRoot
	app_root.configure_home_profile_service(service)
	app_root.configure_expedition_service(ExpeditionService.new(service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.configure_field_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	app_root.configure_field_encounter_service(FieldEncounterService.new())
	get_root().add_child(app_root)
	await process_frame
	return {
		"app": app_root,
		"clock": clock,
		"storage": storage,
	}


func _new_session(seed: int) -> FieldSession:
	return FieldSession.new(FieldSession.CONDITION_NORMAL, true, seed, FieldRouteBuilder.new(SeededRandom.new()).build(seed))


func _first_object(session: FieldSession, object_type: StringName) -> FieldObjectState:
	for state: FieldObjectState in session.object_states:
		if state.object_type == object_type:
			return state
	return null


func _first_unattempted_object_id(objects: Array[Dictionary]) -> StringName:
	for object_snapshot: Dictionary in objects:
		if not bool(object_snapshot["attempted"]):
			return StringName(object_snapshot["object_id"])
	return &""


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
	printerr("EXTRACTION_UPGRADE_LOOP_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("EXTRACTION_UPGRADE_LOOP_PASS")
		quit(0)
		return
	printerr("EXTRACTION_UPGRADE_LOOP_FAIL count=%d" % _failures.size())
	quit(1)
