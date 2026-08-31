class_name AppRoot
extends Control

signal surface_mode_changed(mode: StringName)

const COMPACT_HOME_MODE: StringName = &"compact_home"
const EXPANDED_FIELD_MODE: StringName = &"expanded_field"

@onready var compact_surface: Control = %CompactSurface
@onready var expanded_surface: Control = %ExpandedSurface
@onready var field_session_view: FieldSessionView = %FieldSessionView
@onready var mode_label: Label = %ModeLabel
@onready var surface_toggle: Button = %SurfaceToggle
@onready var supply_ticker: Label = %SupplyTicker
@onready var home_status: VBoxContainer = %HomeStatus
@onready var supply_value: Label = home_status.get_node("%SupplyValue") as Label
@onready var supply_progress: Label = home_status.get_node("%SupplyProgress") as Label
@onready var facility_parts_value: Label = home_status.get_node("%FacilityPartsValue") as Label
@onready var producer_state_value: Label = home_status.get_node("%ProducerStateValue") as Label
@onready var upgrade_button: Button = home_status.get_node("%UpgradeButton") as Button
@onready var storage_state: Label = home_status.get_node("%StorageState") as Label
@onready var condition_select: OptionButton = home_status.get_node("%ConditionSelect") as OptionButton
@onready var flashlight_select: OptionButton = home_status.get_node("%FlashlightSelect") as OptionButton
@onready var departure_button: Button = home_status.get_node("%DepartureButton") as Button
@onready var departure_message: Label = home_status.get_node("%DepartureMessage") as Label

var _surface_mode: StringName = COMPACT_HOME_MODE
var _home_profile_service: HomeProfileService
var _expedition_service: ExpeditionService
var _field_interaction_service: FieldInteractionService
var _field_encounter_service: FieldEncounterService
var _home_profile: HomeProfile
var _active_field_session: FieldSession
var _refresh_accumulator_seconds: float = 0.0
var _next_runtime_seed: int = 20_260_829


func _ready() -> void:
	if _home_profile_service == null:
		_home_profile_service = HomeProfileService.new(SystemClock.new(), JsonProfileStorage.new())
	if _expedition_service == null:
		_expedition_service = ExpeditionService.new(
			_home_profile_service,
			FieldRouteBuilder.new(SeededRandom.new())
		)
	if _field_interaction_service == null:
		_field_interaction_service = FieldInteractionService.new(SeededRandom.new())
	if _field_encounter_service == null:
		_field_encounter_service = FieldEncounterService.new()
	field_session_view.configure_interaction_service(_field_interaction_service)
	field_session_view.configure_encounter_service(_field_encounter_service)

	_initialize_preparation_options()
	surface_toggle.pressed.connect(toggle_surface)
	departure_button.pressed.connect(_on_departure_pressed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	field_session_view.extraction_requested.connect(_on_extraction_requested)
	field_session_view.rescue_requested.connect(_on_rescue_requested)
	_apply_surface_mode()
	_apply_profile_result(_home_profile_service.load_or_create())


func _process(delta: float) -> void:
	if _home_profile == null:
		return
	_refresh_accumulator_seconds += delta
	if _refresh_accumulator_seconds < 1.0:
		return
	_refresh_accumulator_seconds = fmod(_refresh_accumulator_seconds, 1.0)
	refresh_home_profile()


func configure_home_profile_service(service: HomeProfileService) -> void:
	if is_inside_tree():
		push_error("Home profile service must be configured before AppRoot enters the tree")
		return
	_home_profile_service = service


func configure_expedition_service(service: ExpeditionService) -> void:
	if is_inside_tree():
		push_error("Expedition service must be configured before AppRoot enters the tree")
		return
	_expedition_service = service


func configure_field_interaction_service(service: FieldInteractionService) -> void:
	if is_inside_tree():
		push_error("Field interaction service must be configured before AppRoot enters the tree")
		return
	_field_interaction_service = service


func configure_field_encounter_service(service: FieldEncounterService) -> void:
	if is_inside_tree():
		push_error("Field encounter service must be configured before AppRoot enters the tree")
		return
	_field_encounter_service = service


func refresh_home_profile() -> bool:
	if _home_profile == null:
		return false
	var result: HomeProfileService.LoadResult = _home_profile_service.refresh(_home_profile)
	_apply_profile_result(result)
	return result.ok


func home_profile_snapshot() -> Dictionary:
	if _home_profile == null:
		return {}
	return _home_profile.to_document()


func active_field_session_snapshot() -> Dictionary:
	if _active_field_session == null:
		return {}
	return _active_field_session.snapshot()


func current_surface_mode() -> StringName:
	return _surface_mode


func select_preparation(condition: StringName, flashlight_equipped: bool) -> void:
	condition_select.select(1 if condition == FieldSession.CONDITION_BLACKOUT else 0)
	flashlight_select.select(0 if flashlight_equipped else 1)


func attempt_departure(condition: StringName, flashlight_equipped: bool, seed: int) -> bool:
	if _home_profile == null or _active_field_session != null:
		return false
	var result: ExpeditionService.DepartureResult = _expedition_service.depart(
		_home_profile,
		condition,
		flashlight_equipped,
		seed
	)
	if not result.ok:
		departure_message.text = result.error_message
		return false

	_home_profile = result.profile
	_active_field_session = result.session
	_render_home_profile()
	departure_message.text = "보급 저장 완료 · 필드 진입"
	field_session_view.start_session(_active_field_session)
	_surface_mode = EXPANDED_FIELD_MODE
	_apply_surface_mode()
	surface_mode_changed.emit(_surface_mode)
	return true


func attempt_producer_upgrade() -> bool:
	if _home_profile == null or _active_field_session != null:
		return false
	var result: HomeProfileService.LoadResult = _home_profile_service.upgrade_producer(_home_profile)
	if not result.ok:
		departure_message.text = result.error_message
		return false
	_home_profile = result.profile
	_render_home_profile()
	departure_message.text = "생산 가구 강화 완료 · 8분마다 1회분 · 최대 3"
	return true


func toggle_surface() -> void:
	if _active_field_session != null:
		return
	_surface_mode = EXPANDED_FIELD_MODE if _surface_mode == COMPACT_HOME_MODE else COMPACT_HOME_MODE
	_apply_surface_mode()
	surface_mode_changed.emit(_surface_mode)


func _initialize_preparation_options() -> void:
	if condition_select.item_count == 0:
		condition_select.add_item("평상")
		condition_select.set_item_metadata(0, FieldSession.CONDITION_NORMAL)
		condition_select.add_item("정전")
		condition_select.set_item_metadata(1, FieldSession.CONDITION_BLACKOUT)
	if flashlight_select.item_count == 0:
		flashlight_select.add_item("손전등 장착")
		flashlight_select.set_item_metadata(0, true)
		flashlight_select.add_item("손전등 미장착")
		flashlight_select.set_item_metadata(1, false)
	select_preparation(FieldSession.CONDITION_NORMAL, true)


func _on_departure_pressed() -> void:
	var condition: StringName = condition_select.get_selected_metadata() as StringName
	var flashlight_equipped: bool = bool(flashlight_select.get_selected_metadata())
	if attempt_departure(condition, flashlight_equipped, _next_runtime_seed):
		_next_runtime_seed += 1


func _on_upgrade_pressed() -> void:
	attempt_producer_upgrade()


func _on_extraction_requested(point_type: StringName) -> void:
	if _active_field_session == null:
		return
	var result: HomeProfileService.SettlementResult = _home_profile_service.settle_extraction(
		_home_profile,
		_active_field_session,
		point_type
	)
	if not result.ok:
		return

	_home_profile = result.profile
	_active_field_session = null
	field_session_view.end_session()
	_surface_mode = COMPACT_HOME_MODE
	var point_label: String = "종착점" if point_type == ExtractionUpgradeRules.EXTRACTION_ENDPOINT else "입구"
	departure_message.text = "%s 회수 · 확정 부품 %d · 집 설비 부품 %d · 체력 3" % [
		point_label,
		result.confirmed_parts,
		_home_profile.facility_parts,
	]
	_render_home_profile()
	_apply_surface_mode()
	surface_mode_changed.emit(_surface_mode)


func _on_rescue_requested(lost_unextracted_parts: int) -> void:
	if _active_field_session == null:
		return
	_active_field_session = null
	field_session_view.end_session()
	_surface_mode = COMPACT_HOME_MODE
	departure_message.text = "관리인이 구조했습니다 · 미확정 부품 %d 손실 · 체력 3 회복" % lost_unextracted_parts
	_apply_surface_mode()
	refresh_home_profile()
	surface_mode_changed.emit(_surface_mode)


func _apply_surface_mode() -> void:
	var field_is_expanded: bool = _surface_mode == EXPANDED_FIELD_MODE
	compact_surface.visible = not field_is_expanded
	expanded_surface.visible = field_is_expanded
	field_session_view.visible = field_is_expanded and _active_field_session != null
	mode_label.text = "FIELD / EXPANDED" if field_is_expanded else "HOME / COMPACT"
	surface_toggle.text = "집으로 접기" if field_is_expanded else "필드 펼치기"
	surface_toggle.visible = _active_field_session == null


func _apply_profile_result(result: HomeProfileService.LoadResult) -> void:
	if not result.ok:
		_home_profile = null
		supply_value.text = "-- / --"
		supply_progress.text = "보급 상태를 불러올 수 없음"
		facility_parts_value.text = "--"
		producer_state_value.text = "--"
		upgrade_button.disabled = true
		storage_state.text = "저장 불러오기 실패"
		supply_ticker.text = "출발 보급 --"
		departure_button.disabled = true
		return
	_home_profile = result.profile
	departure_button.disabled = false
	_render_home_profile()


func _render_home_profile() -> void:
	var available: int = _home_profile.available_supply_units()
	var capacity: int = _home_profile.supply_capacity()
	supply_value.text = "%d / %d" % [available, capacity]
	supply_ticker.text = "출발 보급 %d / %d" % [available, capacity]
	facility_parts_value.text = str(_home_profile.facility_parts)
	producer_state_value.text = "강화 · 8분 · 최대 3" if _home_profile.producer_upgraded else "기본 · 12분 · 최대 2"
	upgrade_button.disabled = _home_profile.producer_upgraded or _home_profile.facility_parts < ExtractionUpgradeRules.PRODUCER_UPGRADE_COST
	upgrade_button.text = (
		"생산 가구 강화 완료 · 8분 · 최대 3"
		if _home_profile.producer_upgraded
		else "설비 부품 %d 소비 · 생산 가구 강화" % ExtractionUpgradeRules.PRODUCER_UPGRADE_COST
	)
	if _home_profile.departure_supply_units >= float(capacity):
		supply_progress.text = "보관 한도 도달 · 대기 시간은 이월되지 않음"
	else:
		var progress_percent: int = int(round(_home_profile.production_progress() * 100.0))
		var remaining: String = _format_duration(_home_profile.milliseconds_until_next_supply())
		supply_progress.text = "다음 1회분까지 %s · %d%%" % [remaining, progress_percent]
	storage_state.text = "schema v1 · 저장됨"


func _format_duration(milliseconds: int) -> String:
	var total_seconds: int = int(ceil(float(milliseconds) / 1000.0))
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
