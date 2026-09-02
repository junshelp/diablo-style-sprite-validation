class_name AppRoot
extends Control

signal surface_mode_changed(mode: StringName)

const COMPACT_HOME_MODE: StringName = &"compact_home"
const EXPANDED_FIELD_MODE: StringName = &"expanded_field"

@onready var compact_surface: Control = %CompactSurface
@onready var expanded_surface: Control = %ExpandedSurface
@onready var field_session_view: FieldSessionView = %FieldSessionView
@onready var mobile_controls: MobileFieldControls = %MobileFieldControls
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
@onready var compact_margin: MarginContainer = $CompactSurface/CompactMargin
@onready var compact_layout: VBoxContainer = $CompactSurface/CompactMargin/CompactLayout
@onready var test_loadout: Label = home_status.get_node("TestLoadout") as Label

var _surface_mode: StringName = COMPACT_HOME_MODE
var _home_profile_service: HomeProfileService
var _expedition_service: ExpeditionService
var _field_interaction_service: FieldInteractionService
var _field_encounter_service: FieldEncounterService
var _home_profile: HomeProfile
var _active_field_session: FieldSession
var _refresh_accumulator_seconds: float = 0.0
var _next_runtime_seed: int = 20_260_829
var _mobile_touch_layout_enabled: bool = false
var _mobile_layout_scale: float = 1.0


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
	field_session_view.interaction_menu_visibility_changed.connect(_on_interaction_menu_visibility_changed)
	mobile_controls.movement_vector_changed.connect(field_session_view.set_mobile_movement)
	mobile_controls.action_requested.connect(_on_mobile_action_requested)
	mobile_controls.environment_changed.connect(_on_mobile_environment_changed)
	var mobile_environment: Dictionary = mobile_controls.environment_snapshot()
	_on_mobile_environment_changed(
		bool(mobile_environment["touch_environment"]),
		bool(mobile_environment["portrait"]),
		float(mobile_environment["layout_scale"])
	)
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


func mobile_controls_node() -> MobileFieldControls:
	return mobile_controls


func set_mobile_test_environment(touch_available: bool, viewport_size: Vector2i) -> void:
	mobile_controls.set_test_environment(touch_available, viewport_size)


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
	surface_toggle.visible = _active_field_session == null and not _mobile_touch_layout_enabled
	mobile_controls.set_field_active(field_is_expanded and _active_field_session != null)
	mobile_controls.set_menu_blocked(field_session_view.interaction_menu_node().visible)


func _on_mobile_environment_changed(touch_environment: bool, _portrait: bool, layout_scale: float) -> void:
	_mobile_touch_layout_enabled = touch_environment
	_mobile_layout_scale = layout_scale if touch_environment else 1.0
	_apply_mobile_home_layout(touch_environment, _mobile_layout_scale)
	field_session_view.set_mobile_touch_layout(touch_environment, _mobile_layout_scale)
	if is_node_ready():
		_apply_surface_mode()


func _on_interaction_menu_visibility_changed(is_open: bool) -> void:
	mobile_controls.set_menu_blocked(is_open)


func _on_mobile_action_requested() -> void:
	field_session_view.request_context_action()


func _apply_mobile_home_layout(enabled: bool, layout_scale: float) -> void:
	var scale_factor: float = layout_scale if enabled else 1.0
	compact_surface.custom_minimum_size = Vector2.ZERO if enabled else Vector2(720.0, 405.0)
	if enabled:
		compact_surface.anchor_left = 0.0
		compact_surface.anchor_top = 0.0
		compact_surface.anchor_right = 1.0
		compact_surface.anchor_bottom = 1.0
		compact_surface.offset_left = 12.0 * scale_factor
		compact_surface.offset_top = 12.0 * scale_factor
		compact_surface.offset_right = -12.0 * scale_factor
		compact_surface.offset_bottom = -12.0 * scale_factor
	else:
		compact_surface.anchor_left = 0.5
		compact_surface.anchor_top = 0.5
		compact_surface.anchor_right = 0.5
		compact_surface.anchor_bottom = 0.5
		compact_surface.offset_left = -360.0
		compact_surface.offset_top = -202.5
		compact_surface.offset_right = 360.0
		compact_surface.offset_bottom = 202.5
	compact_margin.add_theme_constant_override("margin_left", int(round((14.0 if enabled else 28.0) * scale_factor)))
	compact_margin.add_theme_constant_override("margin_top", int(round((8.0 if enabled else 18.0) * scale_factor)))
	compact_margin.add_theme_constant_override("margin_right", int(round((14.0 if enabled else 28.0) * scale_factor)))
	compact_margin.add_theme_constant_override("margin_bottom", int(round((8.0 if enabled else 18.0) * scale_factor)))
	compact_layout.add_theme_constant_override("separation", int(round((6.0 if enabled else 10.0) * scale_factor)))
	home_status.add_theme_constant_override("separation", int(round((3.0 if enabled else 4.0) * scale_factor)))
	upgrade_button.custom_minimum_size.y = (46.0 if enabled else 30.0) * scale_factor
	condition_select.custom_minimum_size = (Vector2(140.0, 48.0) if enabled else Vector2(104.0, 32.0)) * scale_factor
	flashlight_select.custom_minimum_size = (Vector2(180.0, 48.0) if enabled else Vector2(142.0, 32.0)) * scale_factor
	departure_button.custom_minimum_size = (Vector2(190.0, 48.0) if enabled else Vector2(116.0, 32.0)) * scale_factor
	_apply_mobile_home_font_sizes(enabled, scale_factor)
	test_loadout.visible = not enabled
	storage_state.visible = not enabled
	mode_label.visible = not enabled
	supply_ticker.visible = not enabled
	surface_toggle.visible = _active_field_session == null and not enabled


func _apply_mobile_home_font_sizes(enabled: bool, scale_factor: float) -> void:
	var font_sizes: Array[Dictionary] = [
		{"path": "CompactSurface/CompactMargin/CompactLayout/HomeTitle", "mobile": 20, "desktop": 23},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/StatusTitle", "mobile": 15, "desktop": 17},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/SupplyCard/SupplyMargin/SupplyLayout/SupplyRow/SupplyName", "mobile": 15, "desktop": 18},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/SupplyCard/SupplyMargin/SupplyLayout/SupplyRow/SupplyValue", "mobile": 23, "desktop": 27},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/SupplyCard/SupplyMargin/SupplyLayout/SupplyProgress", "mobile": 12, "desktop": 15},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/Details/PartsGroup/PartsTitle", "mobile": 11, "desktop": 14},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/Details/PartsGroup/FacilityPartsValue", "mobile": 14, "desktop": 20},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/Details/ProducerGroup/ProducerTitle", "mobile": 11, "desktop": 14},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/Details/ProducerGroup/ProducerStateValue", "mobile": 14, "desktop": 16},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/UpgradeButton", "mobile": 13, "desktop": 14},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/PreparationRow/ConditionSelect", "mobile": 13, "desktop": 14},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/PreparationRow/FlashlightSelect", "mobile": 13, "desktop": 14},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/PreparationRow/DepartureButton", "mobile": 13, "desktop": 15},
		{"path": "CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder/StatusMargin/HomeStatus/DepartureMessage", "mobile": 11, "desktop": 12},
	]
	for entry: Dictionary in font_sizes:
		var control := get_node(entry["path"] as String) as Control
		var target_size: int = int(entry["mobile"] if enabled else entry["desktop"])
		control.add_theme_font_size_override("font_size", int(round(float(target_size) * scale_factor)))


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
