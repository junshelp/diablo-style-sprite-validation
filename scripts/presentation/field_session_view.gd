class_name FieldSessionView
extends Node2D

signal entrance_return_requested
signal extraction_requested(point_type: StringName)
signal interaction_result_applied(result: ObjectInteractionResult)
signal rescue_requested(lost_unextracted_parts: int)

const RETURN_RADIUS: float = 78.0
const EXTRACTION_RADIUS: float = RETURN_RADIUS
const OBJECT_INTERACTION_RADIUS: float = 86.0
const HIDE_INTERACTION_RADIUS: float = 92.0
const ENTITY_CONTACT_RADIUS: float = 42.0
const DAMAGE_KNOCKBACK_DISTANCE: float = 118.0
const WALL_THICKNESS: float = 22.0
const BUNDLED_UI_FONT: Font = preload("res://assets/fonts/NotoSansKR-wght.fontdata")
const UI_THEME: Theme = preload("res://assets/ui/dark_horror_ui_theme.tres")
const LIGHTING_STATE_NORMAL: StringName = &"normal_ambient"
const LIGHTING_STATE_BLACKOUT_UNPREPARED: StringName = &"blackout_unprepared"
const LIGHTING_STATE_BLACKOUT_FLASHLIGHT: StringName = &"blackout_flashlight"
const LIGHTING_STATE_RESTORED: StringName = &"restored_fixtures"
const RADIAL_LIGHT_TEXTURE_SIZE: int = 256
const CONE_LIGHT_TEXTURE_SIZE: int = 512
const MINIMUM_VISIBILITY_RADIUS: float = 118.0
const FLASHLIGHT_CONE_RANGE: float = 384.0
const FLASHLIGHT_CONE_HALF_ANGLE_DEGREES: float = 34.0
const RESTORED_FIXTURE_RADIUS: float = 256.0
const NORMAL_AMBIENT: Color = Color(0.9, 0.92, 0.88, 1.0)
const BLACKOUT_AMBIENT: Color = Color(0.045, 0.055, 0.075, 1.0)
const RESTORED_AMBIENT: Color = Color(0.56, 0.58, 0.48, 1.0)
const DARKNESS_STRENGTHS: Dictionary = {
	LIGHTING_STATE_NORMAL: 0.1,
	LIGHTING_STATE_RESTORED: 0.48,
	LIGHTING_STATE_BLACKOUT_FLASHLIGHT: 0.86,
	LIGHTING_STATE_BLACKOUT_UNPREPARED: 0.92,
}

static var _radial_light_texture: ImageTexture
static var _flashlight_cone_texture: ImageTexture

@onready var geometry: Node2D = %Geometry
@onready var world_ambient: CanvasModulate = %WorldAmbient
@onready var restored_fixtures: Node2D = %RestoredFixtures
@onready var explorer: ExplorerController = %Explorer
@onready var chase_entity: ChaseEntityView = %ChaseEntity
@onready var condition_label: Label = %ConditionLabel
@onready var loadout_label: Label = %LoadoutLabel
@onready var route_label: Label = %RouteLabel
@onready var session_state_label: Label = %SessionStateLabel
@onready var hp_label: Label = %HpLabel
@onready var encounter_state_label: Label = %EncounterStateLabel
@onready var encounter_banner: Label = %EncounterBanner
@onready var return_prompt: Label = %ReturnPrompt
@onready var object_prompt: Label = %ObjectPrompt
@onready var hide_prompt: Label = %HidePrompt
@onready var result_label: Label = %ResultLabel
@onready var darkness_overlay: ColorRect = %DarknessOverlay
@onready var encounter_tint: ColorRect = %EncounterTint
@onready var field_canvas: CanvasLayer = %FieldCanvas
@onready var field_hud: Control = %FieldHud
@onready var interaction_menu: ObjectInteractionMenu = %ObjectInteractionMenu
@onready var warning_audio: AudioStreamPlayer = %WarningAudio

var _session: FieldSession
var _interaction_service: FieldInteractionService
var _encounter_service: FieldEncounterService
var _solid_rectangles: Array[Rect2] = []
var _light_occluders: Array[LightOccluder2D] = []
var _named_sight_blockers: Dictionary = {}
var _named_light_occluders: Dictionary = {}
var _interaction_was_pressed: bool = false
var _nearby_object_id: StringName = &""
var _nearby_hide_spot_id: StringName = &""
var _nearby_extraction_point: StringName = &""
var _object_check_count: int = 0
var _visual_elapsed_seconds: float = 0.0
var _warning_tone: AudioStreamWAV
var _warning_feedback_played: bool = false
var _entered_hide_spot_id: StringName = &""


func _ready() -> void:
	if _encounter_service == null:
		_encounter_service = FieldEncounterService.new()
	_ensure_light_textures()
	explorer.configure_visibility_lights(_radial_light_texture, _flashlight_cone_texture)
	explorer.set_visibility_lights(false, false)
	visible = false
	field_hud.visible = false
	interaction_menu.close_menu()
	interaction_menu.base_search_selected.connect(_on_base_search_selected)
	interaction_menu.tool_selected.connect(_on_tool_selected)
	interaction_menu.cancel_requested.connect(_on_menu_cancel_requested)
	explorer.follow_camera.enabled = false
	explorer.set_simulation_enabled(false)
	chase_entity.set_active(false)
	set_process(false)


func _process(delta: float) -> void:
	_tick_field(delta)


func configure_interaction_service(service: FieldInteractionService) -> void:
	_interaction_service = service


func configure_encounter_service(service: FieldEncounterService) -> void:
	_encounter_service = service


func start_session(session: FieldSession) -> void:
	_session = session
	visible = true
	field_hud.visible = true
	set_process(true)
	explorer.position = session.route.entrance_position + Vector2(110.0, 0.0)
	explorer.configure_camera_bounds(session.route.bounds)
	explorer.follow_camera.enabled = true
	explorer.follow_camera.reset_smoothing()
	explorer.set_simulation_enabled(true)
	chase_entity.position = _entity_spawn_position(session)
	chase_entity.set_forward(Vector2.LEFT)
	chase_entity.set_active(false)
	_rebuild_geometry(session.route)
	condition_label.text = "현장 상태  ·  %s" % ("정전" if session.condition == FieldSession.CONDITION_BLACKOUT else "평상")
	route_label.text = "SEED %d  ·  %d MODULES  ·  BRANCH 1" % [session.seed, session.route.module_count()]
	result_label.text = ""
	_nearby_object_id = &""
	_nearby_hide_spot_id = &""
	_nearby_extraction_point = &""
	_object_check_count = 0
	_visual_elapsed_seconds = 0.0
	_warning_feedback_played = false
	_entered_hide_spot_id = &""
	_interaction_was_pressed = false
	interaction_menu.close_menu()
	_render_session_state()
	_refresh_nearby_object()
	_refresh_nearby_hide_spot()
	_refresh_nearby_extraction_point()
	_sync_encounter_presentation()
	queue_redraw()


func end_session() -> void:
	if _session != null and _session.field_simulation_paused and _interaction_service != null:
		interaction_menu.close_menu()
		_interaction_service.cancel_interaction(_session)
	_session = null
	_nearby_object_id = &""
	_nearby_hide_spot_id = &""
	_nearby_extraction_point = &""
	_entered_hide_spot_id = &""
	visible = false
	field_hud.visible = false
	interaction_menu.close_menu()
	warning_audio.stop()
	warning_audio.stream = null
	_warning_tone = null
	explorer.follow_camera.enabled = false
	explorer.set_simulation_enabled(false)
	explorer.visible = true
	chase_entity.set_active(false)
	encounter_banner.visible = false
	hide_prompt.visible = false
	encounter_tint.color.a = 0.0
	world_ambient.color = Color.WHITE
	explorer.set_visibility_lights(false, false)
	_clear_restored_fixtures()
	set_process(false)
	for child: Node in geometry.get_children():
		child.queue_free()
	_solid_rectangles.clear()
	_light_occluders.clear()
	_named_light_occluders.clear()
	queue_redraw()


func active_session_snapshot() -> Dictionary:
	if _session == null:
		return {}
	return _session.snapshot()


func move_explorer_to(position: Vector2) -> void:
	explorer.position = position
	explorer.velocity = Vector2.ZERO
	explorer.follow_camera.reset_smoothing()
	if _session != null and not _session.field_simulation_paused:
		_refresh_nearby_object()
		_refresh_nearby_hide_spot()
		_refresh_nearby_extraction_point()


func move_explorer_to_object_type(object_type: StringName) -> StringName:
	if _session == null or _session.field_simulation_paused:
		return &""
	for state: FieldObjectState in _session.object_states:
		if state.object_type == object_type and not state.attempted:
			move_explorer_to(state.position)
			return state.object_id
	return &""


func move_explorer_to_object(object_id: StringName) -> bool:
	if _session == null or _session.field_simulation_paused:
		return false
	var state: FieldObjectState = _session.object_state(object_id)
	if state == null:
		return false
	move_explorer_to(state.position)
	return true


func move_explorer_for_test(input_vector: Vector2, delta: float) -> void:
	explorer.move_for_test(input_vector, delta)


func set_explorer_facing_for_test(input_vector: Vector2) -> void:
	explorer.set_facing_for_test(input_vector)


func explorer_facing_direction() -> Vector2:
	return explorer.last_facing_direction()


func explorer_position() -> Vector2:
	return explorer.position


func explorer_simulation_enabled() -> bool:
	return explorer.simulation_enabled()


func camera_bounds() -> Rect2:
	return explorer.camera_bounds()


func camera_global_position() -> Vector2:
	return explorer.follow_camera.global_position


func solid_rectangles() -> Array[Rect2]:
	return _solid_rectangles.duplicate()


func object_snapshots() -> Array[Dictionary]:
	if _session == null:
		return []
	var snapshots: Array[Dictionary] = []
	for state: FieldObjectState in _session.object_states:
		snapshots.append(state.snapshot())
	return snapshots


func hide_spot_snapshots() -> Array[Dictionary]:
	if _session == null:
		return []
	var snapshots: Array[Dictionary] = []
	for spot: FieldHideSpotState in _session.hide_spots:
		snapshots.append(spot.snapshot())
	return snapshots


func encounter_snapshot() -> Dictionary:
	if _session == null:
		return {}
	return _session.encounter.snapshot()


func move_explorer_to_hide_spot_type(spot_type: StringName) -> StringName:
	if _session == null or _session.field_simulation_paused:
		return &""
	for spot: FieldHideSpotState in _session.hide_spots:
		if spot.spot_type == spot_type:
			move_explorer_to(spot.entry_position)
			_refresh_nearby_hide_spot()
			return spot.spot_id
	return &""


func begin_hide_nearby_for_test() -> bool:
	_refresh_nearby_hide_spot()
	return _begin_hide(_nearby_hide_spot_id)


func trigger_encounter_for_test(source: StringName) -> bool:
	if not _encounter_service.try_trigger(_session, source):
		return false
	_on_warning_started()
	_sync_encounter_presentation()
	return true


func advance_encounter_for_test(delta: float, explorer_visible: bool, contact: bool) -> Dictionary:
	var result: Dictionary = _encounter_service.tick(_session, delta, explorer_visible, contact)
	_apply_encounter_result(result)
	_sync_encounter_presentation()
	return result


func set_entity_pose_for_test(position: Vector2, forward: Vector2) -> void:
	chase_entity.position = position
	chase_entity.set_forward(forward)


func entity_position() -> Vector2:
	return chase_entity.position


func entity_visible() -> bool:
	return chase_entity.visible


func set_fov_debug_visible(value: bool) -> void:
	chase_entity.set_debug_fov_visible(value)


func fov_debug_visible() -> bool:
	return chase_entity.debug_fov_visible()


func sight_between_for_test(origin: Vector2, forward: Vector2, target: Vector2) -> bool:
	return _encounter_service.can_see(origin, forward, target, _ray_is_blocked(origin, target))


func named_sight_blocker(blocker_name: StringName) -> Rect2:
	if not _named_sight_blockers.has(blocker_name):
		return Rect2()
	return _named_sight_blockers[blocker_name]


func named_light_occluder(blocker_name: StringName) -> LightOccluder2D:
	if not _named_light_occluders.has(blocker_name):
		return null
	return _named_light_occluders[blocker_name] as LightOccluder2D


func light_occluder_count() -> int:
	return _light_occluders.size()


func visual_light_path_blocked_for_test(origin: Vector2, target: Vector2) -> bool:
	return _ray_is_blocked(origin, target)


func interaction_menu_node() -> ObjectInteractionMenu:
	return interaction_menu


func object_check_count() -> int:
	return _object_check_count


func visual_elapsed_seconds() -> float:
	return _visual_elapsed_seconds


func advance_field_frame_for_test(delta: float) -> void:
	_tick_field(delta)


func darkness_alpha() -> float:
	if _session == null:
		return 0.0
	return float(DARKNESS_STRENGTHS[_resolved_lighting_state()])


func lighting_state_snapshot() -> Dictionary:
	if _session == null:
		return {}
	var explorer_lights: Dictionary = explorer.visibility_light_snapshot()
	var visible_fixture_count: int = 0
	var fixture_shadows_enabled: bool = true
	for child: Node in restored_fixtures.get_children():
		var fixture := child as PointLight2D
		if fixture == null:
			continue
		if fixture.visible:
			visible_fixture_count += 1
		fixture_shadows_enabled = fixture_shadows_enabled and fixture.shadow_enabled
	return {
		"state": String(_resolved_lighting_state()),
		"ambient": world_ambient.color,
		"darkness_strength": darkness_alpha(),
		"minimum_visibility_radius": MINIMUM_VISIBILITY_RADIUS,
		"flashlight_cone_range": FLASHLIGHT_CONE_RANGE,
		"flashlight_cone_half_angle_degrees": FLASHLIGHT_CONE_HALF_ANGLE_DEGREES,
		"restored_fixture_radius": RESTORED_FIXTURE_RADIUS,
		"fixture_count": restored_fixtures.get_child_count(),
		"visible_fixture_count": visible_fixture_count,
		"fixture_shadows_enabled": fixture_shadows_enabled,
		"solid_count": _solid_rectangles.size(),
		"occluder_count": _light_occluders.size(),
		"world_canvas_modulated": world_ambient.get_parent() == self,
		"hud_canvas_layer": field_canvas.layer,
		"hud_modulate": field_hud.modulate,
		"menu_modulate": interaction_menu.modulate,
		"legacy_screen_overlay_visible": darkness_overlay.visible,
		"explorer_lights": explorer_lights,
	}


func try_open_nearby_object() -> bool:
	if _session == null or _session.field_simulation_paused or not _encounter_service.can_open_object_menu(_session):
		return false
	_refresh_nearby_object()
	if _nearby_object_id == &"":
		return false
	return _open_object_interaction(_nearby_object_id)


func open_object_interaction_for_test(object_id: StringName) -> bool:
	if _session == null:
		return false
	var state: FieldObjectState = _session.object_state(object_id)
	if state == null or explorer.position.distance_to(state.position) > OBJECT_INTERACTION_RADIUS:
		return false
	return _open_object_interaction(object_id)


func try_return_at_entrance() -> bool:
	return _try_request_extraction(ExtractionUpgradeRules.EXTRACTION_ENTRANCE)


func try_extract_at_endpoint() -> bool:
	return _try_request_extraction(ExtractionUpgradeRules.EXTRACTION_ENDPOINT)


func move_explorer_to_extraction_point_for_test(point_type: StringName) -> bool:
	if _session == null or not ExtractionUpgradeRules.is_valid_extraction_point(point_type):
		return false
	var target: Vector2 = (
		_session.route.endpoint_position
		if point_type == ExtractionUpgradeRules.EXTRACTION_ENDPOINT
		else _session.route.entrance_position
	)
	move_explorer_to(target)
	return true


func extraction_prompt_text() -> String:
	return return_prompt.text if return_prompt.visible else ""


func _tick_field(delta: float) -> void:
	if _session == null or delta <= 0.0:
		return
	_visual_elapsed_seconds += delta
	var interaction_pressed: bool = Input.is_physical_key_pressed(KEY_E)
	if _session.field_simulation_paused:
		_interaction_was_pressed = interaction_pressed
		return

	_session.advance_field_simulation(delta)
	_check_deep_entry_trigger()
	_tick_encounter(delta)
	if _session == null:
		return
	_refresh_nearby_object()
	_refresh_nearby_hide_spot()
	_refresh_nearby_extraction_point()
	if interaction_pressed and not _interaction_was_pressed:
		if _session.encounter.state == FieldEncounterState.STATE_CHASING and _nearby_hide_spot_id != &"":
			_begin_hide(_nearby_hide_spot_id)
		elif _nearby_object_id != &"":
			_open_object_interaction(_nearby_object_id)
		elif _nearby_extraction_point != &"":
			_request_extraction(_nearby_extraction_point)
	_interaction_was_pressed = interaction_pressed


func _refresh_nearby_object() -> void:
	if _session == null or _session.field_simulation_paused:
		return
	_object_check_count += 1
	_nearby_object_id = &""
	if not _encounter_service.can_open_object_menu(_session):
		object_prompt.visible = false
		return
	var nearest_distance: float = OBJECT_INTERACTION_RADIUS
	for state: FieldObjectState in _session.object_states:
		if state.attempted:
			continue
		var distance: float = explorer.position.distance_to(state.position)
		if distance <= nearest_distance:
			nearest_distance = distance
			_nearby_object_id = state.object_id
	object_prompt.visible = _nearby_object_id != &""
	if _nearby_object_id != &"":
		var nearby_state: FieldObjectState = _session.object_state(_nearby_object_id)
		object_prompt.text = "%s  ·  E 조사" % nearby_state.display_name()
	return_prompt.visible = false


func _refresh_nearby_hide_spot() -> void:
	_nearby_hide_spot_id = &""
	hide_prompt.visible = false
	if _session == null or _session.field_simulation_paused:
		return
	if _session.encounter.state != FieldEncounterState.STATE_CHASING or _session.encounter.hide_active:
		return
	var nearest_distance: float = HIDE_INTERACTION_RADIUS
	for spot: FieldHideSpotState in _session.hide_spots:
		var distance: float = explorer.position.distance_to(spot.entry_position)
		if distance <= nearest_distance:
			nearest_distance = distance
			_nearby_hide_spot_id = spot.spot_id
	if _nearby_hide_spot_id != &"":
		var nearby_spot: FieldHideSpotState = _session.hide_spot(_nearby_hide_spot_id)
		hide_prompt.text = "%s  ·  E 은신" % nearby_spot.display_name()
		hide_prompt.visible = true
		object_prompt.visible = false
		return_prompt.visible = false


func _refresh_nearby_extraction_point() -> void:
	_nearby_extraction_point = &""
	return_prompt.visible = false
	if _session == null or not _session.can_attempt_extraction():
		return
	if _nearby_object_id != &"" or _nearby_hide_spot_id != &"":
		return
	if explorer.position.distance_to(_session.route.entrance_position) <= EXTRACTION_RADIUS:
		_nearby_extraction_point = ExtractionUpgradeRules.EXTRACTION_ENTRANCE
		return_prompt.text = "입구 회수 지점  ·  E 회수"
	elif explorer.position.distance_to(_session.route.endpoint_position) <= EXTRACTION_RADIUS:
		_nearby_extraction_point = ExtractionUpgradeRules.EXTRACTION_ENDPOINT
		return_prompt.text = "종착점 회수 지점  ·  E 회수 · 최소 4 보장"
	return_prompt.visible = _nearby_extraction_point != &""


func _try_request_extraction(point_type: StringName) -> bool:
	if _session == null or not _session.can_attempt_extraction():
		return false
	if not ExtractionUpgradeRules.is_valid_extraction_point(point_type):
		return false
	var point_position: Vector2 = (
		_session.route.endpoint_position
		if point_type == ExtractionUpgradeRules.EXTRACTION_ENDPOINT
		else _session.route.entrance_position
	)
	if explorer.position.distance_to(point_position) > EXTRACTION_RADIUS:
		return false
	_request_extraction(point_type)
	return true


func _request_extraction(point_type: StringName) -> void:
	if point_type == ExtractionUpgradeRules.EXTRACTION_ENTRANCE:
		entrance_return_requested.emit()
	extraction_requested.emit(point_type)


func _open_object_interaction(object_id: StringName) -> bool:
	if _interaction_service == null or not _encounter_service.can_open_object_menu(_session):
		return false
	if not _interaction_service.begin_interaction(_session, object_id):
		return false
	var state: FieldObjectState = _session.object_state(object_id)
	explorer.set_simulation_enabled(false)
	return_prompt.visible = false
	object_prompt.visible = false
	interaction_menu.open_menu(state.display_name(), _session.crowbar_count, _session.fuse_count)
	return true


func _check_deep_entry_trigger() -> void:
	if _session.encounter.triggered_once:
		return
	var last_module_position: Vector2 = _session.route.main_module_positions[-1]
	var deep_entry_rect := Rect2(last_module_position - Vector2(220.0, 155.0), Vector2(440.0, 310.0))
	if deep_entry_rect.has_point(explorer.position) and _encounter_service.try_trigger(_session, FieldEncounterState.TRIGGER_DEEP_ENTRY):
		_on_warning_started()


func _tick_encounter(delta: float) -> void:
	var encounter_state: StringName = _session.encounter.state
	var explorer_seen: bool = false
	var contact: bool = false
	if encounter_state == FieldEncounterState.STATE_CHASING:
		chase_entity.set_active(true)
		chase_entity.set_mode(encounter_state)
		chase_entity.chase_toward(explorer.position, delta)
		explorer_seen = _entity_can_see_explorer()
		contact = chase_entity.position.distance_to(explorer.position) <= ENTITY_CONTACT_RADIUS
	elif encounter_state == FieldEncounterState.STATE_SEARCHING:
		chase_entity.set_active(true)
		chase_entity.set_mode(encounter_state)
		chase_entity.stop_motion()

	var result: Dictionary = _encounter_service.tick(_session, delta, explorer_seen, contact)
	_apply_encounter_result(result)
	if _session != null:
		_sync_encounter_presentation()


func _apply_encounter_result(result: Dictionary) -> void:
	if _session == null:
		return
	if bool(result["damage_applied"]):
		result_label.text = "피해 1 · 체력 %d / %d" % [_session.encounter.hp, FieldEncounterState.MAX_HP]
	if bool(result["hide_ejected"]):
		_eject_explorer()
		result_label.text = "은신 진입 목격 · 피해 1 · 밖으로 배출"
	elif bool(result["knockback_required"]):
		_knockback_explorer()
		result_label.text = "엔티티 접촉 · 피해 1 · 짧은 무적"
	if bool(result["hide_completed"]):
		explorer.visible = false
		explorer.set_simulation_enabled(false)
		result_label.text = "은신 진입 완료 · 주변 수색 중"
	if bool(result["encounter_resolved"]):
		_emerge_from_hide()
		result_label.text = "은신 성공 · 추격 조우 종료"
	if bool(result["rescue_required"]):
		var lost_parts: int = int(result["lost_unextracted_parts"])
		rescue_requested.emit(lost_parts)


func _begin_hide(spot_id: StringName) -> bool:
	if _session == null or spot_id == &"" or not _encounter_service.begin_hide(_session, spot_id):
		return false
	var spot: FieldHideSpotState = _session.hide_spot(spot_id)
	_entered_hide_spot_id = spot_id
	explorer.position = spot.entry_position
	explorer.velocity = Vector2.ZERO
	explorer.visible = true
	explorer.set_simulation_enabled(false)
	hide_prompt.visible = false
	result_label.text = "%s 진입 중 · 시야를 끊으십시오" % spot.display_name()
	_sync_encounter_presentation()
	return true


func _entity_can_see_explorer() -> bool:
	return _encounter_service.can_see(
		chase_entity.position,
		chase_entity.forward_vector,
		explorer.position,
		_ray_is_blocked(chase_entity.position, explorer.position)
	)


func _ray_is_blocked(origin: Vector2, target: Vector2) -> bool:
	if origin.distance_squared_to(target) <= 0.000001:
		return false
	var query := PhysicsRayQueryParameters2D.create(origin, target, 1)
	query.exclude = [chase_entity.get_rid(), explorer.get_rid()]
	query.collide_with_areas = false
	return not get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _knockback_explorer() -> void:
	var direction: Vector2 = chase_entity.position.direction_to(explorer.position)
	if direction == Vector2.ZERO:
		direction = Vector2.LEFT
	_move_explorer_to_safe_position(explorer.position + direction * DAMAGE_KNOCKBACK_DISTANCE)


func _eject_explorer() -> void:
	explorer.visible = true
	explorer.set_simulation_enabled(true)
	var spot: FieldHideSpotState = _session.hide_spot(_entered_hide_spot_id)
	var base_position: Vector2 = explorer.position if spot == null else spot.entry_position
	var direction: Vector2 = chase_entity.position.direction_to(base_position)
	if direction == Vector2.ZERO:
		direction = Vector2.DOWN
	_move_explorer_to_safe_position(base_position + direction * DAMAGE_KNOCKBACK_DISTANCE)
	_entered_hide_spot_id = &""


func _emerge_from_hide() -> void:
	var spot: FieldHideSpotState = _session.hide_spot(_entered_hide_spot_id)
	if spot != null:
		_move_explorer_to_safe_position(spot.entry_position)
	explorer.visible = true
	explorer.set_simulation_enabled(true)
	_entered_hide_spot_id = &""


func _move_explorer_to_safe_position(target: Vector2) -> void:
	var safe_bounds: Rect2 = _session.route.bounds.grow(-36.0)
	explorer.position = Vector2(
		clampf(target.x, safe_bounds.position.x, safe_bounds.end.x),
		clampf(target.y, safe_bounds.position.y, safe_bounds.end.y)
	)
	explorer.velocity = Vector2.ZERO
	explorer.follow_camera.reset_smoothing()


func _sync_encounter_presentation() -> void:
	if _session == null:
		return
	var encounter: FieldEncounterState = _session.encounter
	hp_label.text = "체력  %s" % _hp_pips(encounter.hp)
	encounter_state_label.text = "조우  ·  %s" % String(encounter.state).to_upper()
	match encounter.state:
		FieldEncounterState.STATE_DORMANT:
			chase_entity.set_active(false)
			encounter_banner.visible = false
			encounter_tint.color = Color(0.28, 0.015, 0.01, 0.0)
		FieldEncounterState.STATE_WARNING:
			chase_entity.set_active(false)
			encounter_banner.text = "경고 · 통로 깊은 곳에서 움직임 감지"
			encounter_banner.visible = true
			encounter_tint.color = Color(0.34, 0.018, 0.012, 0.15)
		FieldEncounterState.STATE_CHASING:
			chase_entity.set_active(true)
			chase_entity.set_mode(encounter.state)
			encounter_banner.text = "추격 중 · 시야를 끊고 은신하십시오"
			encounter_banner.visible = true
			encounter_tint.color = Color(0.3, 0.012, 0.008, 0.055)
		FieldEncounterState.STATE_SEARCHING:
			chase_entity.set_active(true)
			chase_entity.set_mode(encounter.state)
			chase_entity.stop_motion()
			encounter_banner.text = "숨을 죽이십시오 · 주변 수색 중"
			encounter_banner.visible = true
			encounter_tint.color = Color(0.22, 0.08, 0.015, 0.04)
		FieldEncounterState.STATE_RESOLVED:
			chase_entity.set_active(false)
			encounter_banner.visible = false
			encounter_tint.color = Color(0.28, 0.015, 0.01, 0.0)
	var explorer_should_move: bool = (
		encounter.state != FieldEncounterState.STATE_SEARCHING
		and not encounter.hide_active
		and not encounter.hidden
		and not encounter.rescued
	)
	explorer.set_simulation_enabled(explorer_should_move)
	_render_session_state()


func _on_warning_started() -> void:
	if _warning_feedback_played:
		return
	_warning_feedback_played = true
	_play_warning_tone()
	_sync_encounter_presentation()


func _play_warning_tone() -> void:
	if _warning_tone == null:
		_warning_tone = _build_warning_tone()
	warning_audio.stream = _warning_tone
	warning_audio.play()


func _build_warning_tone() -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22_050
	stream.stereo = false
	var duration_seconds: float = 0.18
	var sample_count: int = int(float(stream.mix_rate) * duration_seconds)
	var sample_data := PackedByteArray()
	for sample_index: int in range(sample_count):
		var progress: float = float(sample_index) / float(sample_count)
		var wave: float = sin(TAU * 310.0 * float(sample_index) / float(stream.mix_rate))
		var sample_value: int = int(wave * (1.0 - progress) * 11_000.0)
		sample_data.append(sample_value & 0xff)
		sample_data.append((sample_value >> 8) & 0xff)
	stream.data = sample_data
	return stream


func _hp_pips(hp: int) -> String:
	var pips: Array[String] = []
	for index: int in range(FieldEncounterState.MAX_HP):
		pips.append("●" if index < hp else "○")
	return " ".join(pips)


func _entity_spawn_position(session: FieldSession) -> Vector2:
	return session.route.endpoint_position - Vector2(145.0, 0.0)


func _on_menu_cancel_requested() -> void:
	if _session == null or not _session.field_simulation_paused:
		return
	interaction_menu.close_menu()
	_interaction_service.cancel_interaction(_session)
	explorer.set_simulation_enabled(true)
	_interaction_was_pressed = Input.is_physical_key_pressed(KEY_E)
	_refresh_nearby_object()


func _on_base_search_selected() -> void:
	if _session == null:
		return
	_commit_interaction(_interaction_service.prepare_base_search(_session))


func _on_tool_selected(tool_id: StringName) -> void:
	if _session == null:
		return
	_commit_interaction(_interaction_service.prepare_tool(_session, tool_id))


func _commit_interaction(result: ObjectInteractionResult) -> void:
	if result == null:
		return
	# The approved transition is observable: close the modal and resume the field,
	# then apply one prepared result through the application boundary.
	interaction_menu.close_menu()
	explorer.set_simulation_enabled(true)
	if not _interaction_service.apply_result(_session, result):
		return
	var encounter_triggered: bool = _encounter_service.try_trigger_from_interaction_result(_session, result)
	_render_session_state()
	_render_result(result)
	if encounter_triggered:
		_on_warning_started()
	_interaction_was_pressed = Input.is_physical_key_pressed(KEY_E)
	_refresh_nearby_object()
	queue_redraw()
	interaction_result_applied.emit(result)


func _render_session_state() -> void:
	if _session == null:
		return
	loadout_label.text = "손전등 %s  ·  빠루 %d  ·  퓨즈 %d" % [
		"장착" if _session.flashlight_equipped else "미장착",
		_session.crowbar_count,
		_session.fuse_count,
	]
	session_state_label.text = "미확정 부품 %d  ·  조명 %s" % [
		_session.unextracted_parts,
		"복구" if _session.lighting_restored else "미복구",
	]
	_apply_lighting()


func _render_result(result: ObjectInteractionResult) -> void:
	if result.restores_lighting:
		result_label.text = "퓨즈 사용 · 조명 복구"
	elif result.used_base_fallback:
		result_label.text = "도구 반응 없음 · 기본 수색으로 부품 %d" % result.parts_delta
	elif result.loud_noise:
		result_label.text = "빠루 사용 · 부품 %d · 큰 소음" % result.parts_delta
	else:
		result_label.text = "수색 완료 · 부품 %d" % result.parts_delta


func _apply_lighting() -> void:
	var lighting_state: StringName = _resolved_lighting_state()
	darkness_overlay.visible = false
	darkness_overlay.color = Color.TRANSPARENT
	match lighting_state:
		LIGHTING_STATE_NORMAL:
			world_ambient.color = NORMAL_AMBIENT
			explorer.set_visibility_lights(false, false)
			_set_restored_fixtures_visible(false)
		LIGHTING_STATE_BLACKOUT_UNPREPARED:
			world_ambient.color = BLACKOUT_AMBIENT.darkened(0.12)
			explorer.set_visibility_lights(true, false)
			_set_restored_fixtures_visible(false)
		LIGHTING_STATE_BLACKOUT_FLASHLIGHT:
			world_ambient.color = BLACKOUT_AMBIENT
			explorer.set_visibility_lights(true, true)
			_set_restored_fixtures_visible(false)
		LIGHTING_STATE_RESTORED:
			world_ambient.color = RESTORED_AMBIENT
			explorer.set_visibility_lights(false, false)
			_set_restored_fixtures_visible(true)


func _resolved_lighting_state() -> StringName:
	if _session.lighting_restored:
		return LIGHTING_STATE_RESTORED
	if _session.condition == FieldSession.CONDITION_NORMAL:
		return LIGHTING_STATE_NORMAL
	if _session.flashlight_equipped:
		return LIGHTING_STATE_BLACKOUT_FLASHLIGHT
	return LIGHTING_STATE_BLACKOUT_UNPREPARED


func _ensure_light_textures() -> void:
	if _radial_light_texture == null:
		_radial_light_texture = _build_radial_light_texture()
	if _flashlight_cone_texture == null:
		_flashlight_cone_texture = _build_flashlight_cone_texture()


func _build_radial_light_texture() -> ImageTexture:
	var image := Image.create(RADIAL_LIGHT_TEXTURE_SIZE, RADIAL_LIGHT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(RADIAL_LIGHT_TEXTURE_SIZE - 1) * 0.5, float(RADIAL_LIGHT_TEXTURE_SIZE - 1) * 0.5)
	var radius: float = float(RADIAL_LIGHT_TEXTURE_SIZE) * 0.5
	for y: int in range(RADIAL_LIGHT_TEXTURE_SIZE):
		for x: int in range(RADIAL_LIGHT_TEXTURE_SIZE):
			var normalized_distance: float = Vector2(float(x), float(y)).distance_to(center) / radius
			var intensity: float = pow(maxf(0.0, 1.0 - normalized_distance), 1.35)
			image.set_pixel(x, y, Color(intensity, intensity, intensity, intensity))
	return ImageTexture.create_from_image(image)


func _build_flashlight_cone_texture() -> ImageTexture:
	var image := Image.create(CONE_LIGHT_TEXTURE_SIZE, CONE_LIGHT_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var origin := Vector2(float(CONE_LIGHT_TEXTURE_SIZE - 1) * 0.5, float(CONE_LIGHT_TEXTURE_SIZE - 1) * 0.5)
	var maximum_distance: float = float(CONE_LIGHT_TEXTURE_SIZE) * 0.5 - 8.0
	var inner_angle: float = deg_to_rad(FLASHLIGHT_CONE_HALF_ANGLE_DEGREES - 8.0)
	var outer_angle: float = deg_to_rad(FLASHLIGHT_CONE_HALF_ANGLE_DEGREES)
	for y: int in range(CONE_LIGHT_TEXTURE_SIZE):
		for x: int in range(CONE_LIGHT_TEXTURE_SIZE):
			var offset := Vector2(float(x), float(y)) - origin
			if offset.x <= 0.0:
				continue
			var distance: float = offset.length()
			if distance >= maximum_distance:
				continue
			var angle: float = absf(offset.angle())
			if angle >= outer_angle:
				continue
			var radial_fade: float = 1.0 - smoothstep(0.12, 1.0, distance / maximum_distance)
			var angular_fade: float = 1.0 - smoothstep(inner_angle, outer_angle, angle)
			var intensity: float = clampf(radial_fade * angular_fade, 0.0, 1.0)
			image.set_pixel(x, y, Color(intensity, intensity, intensity, intensity))
	return ImageTexture.create_from_image(image)


func _rebuild_restored_fixtures(route: FieldRoute) -> void:
	_clear_restored_fixtures()
	var fixture_positions: Array[Vector2] = route.main_module_positions.duplicate()
	fixture_positions.append(route.branch_position)
	for index: int in range(fixture_positions.size()):
		var fixture := PointLight2D.new()
		fixture.name = "RestoredFixture%02d" % index
		fixture.position = fixture_positions[index] + Vector2(0.0, -48.0)
		fixture.texture = _radial_light_texture
		fixture.texture_scale = 2.0
		fixture.energy = 1.25
		fixture.color = Color(1.0, 0.82, 0.5, 1.0)
		fixture.shadow_enabled = true
		fixture.shadow_filter = 1
		fixture.shadow_filter_smooth = 2.0
		fixture.range_item_cull_mask = 1
		fixture.shadow_item_cull_mask = 1
		fixture.visible = false
		restored_fixtures.add_child(fixture)


func _set_restored_fixtures_visible(value: bool) -> void:
	for child: Node in restored_fixtures.get_children():
		var fixture := child as PointLight2D
		if fixture != null:
			fixture.visible = value


func _clear_restored_fixtures() -> void:
	for child: Node in restored_fixtures.get_children():
		child.free()


func _draw() -> void:
	if _session == null:
		return
	var route: FieldRoute = _session.route
	var palette_floor := Color(0.105, 0.12, 0.12) if _session.condition == FieldSession.CONDITION_NORMAL else Color(0.055, 0.064, 0.073)
	var palette_edge := Color(0.24, 0.27, 0.27) if _session.condition == FieldSession.CONDITION_NORMAL else Color(0.11, 0.14, 0.16)
	var module_text_color: Color = UI_THEME.get_color(&"module_text", &"FieldCanvas")
	var object_text_color: Color = UI_THEME.get_color(&"object_text", &"FieldCanvas")
	var hide_text_color: Color = UI_THEME.get_color(&"hide_text", &"FieldCanvas")
	draw_rect(route.bounds, Color(0.025, 0.03, 0.035), true)
	draw_rect(Rect2(0.0, 260.0, route.bounds.size.x, 380.0), palette_floor, true)
	var branch_top: float = minf(450.0, route.branch_position.y)
	draw_rect(Rect2(route.branch_position.x - 150.0, branch_top, 300.0, absf(route.branch_position.y - 450.0)), palette_floor, true)

	for index: int in range(route.main_module_positions.size()):
		var position: Vector2 = route.main_module_positions[index]
		draw_rect(Rect2(position - Vector2(220.0, 155.0), Vector2(440.0, 310.0)), palette_edge, false, 3.0)
		draw_string(BUNDLED_UI_FONT, position + Vector2(-105.0, -118.0), String(route.main_module_ids[index]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, module_text_color)

	draw_rect(Rect2(route.branch_position - Vector2(140.0, 95.0), Vector2(280.0, 190.0)), palette_edge, false, 3.0)
	draw_circle(route.entrance_position, 42.0, Color(0.21, 0.43, 0.38))
	draw_string(BUNDLED_UI_FONT, route.entrance_position + Vector2(-38.0, 6.0), "입구", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.86, 0.91, 0.84))
	draw_rect(Rect2(route.endpoint_position - Vector2(50.0, 70.0), Vector2(100.0, 140.0)), Color(0.34, 0.12, 0.1), true)
	draw_string(BUNDLED_UI_FONT, route.endpoint_position + Vector2(-42.0, 6.0), "종착점", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Color(0.92, 0.68, 0.61))

	for state: FieldObjectState in _session.object_states:
		var color := Color(0.28, 0.3, 0.29) if state.object_type == FieldObjectState.TYPE_LOCKER else Color(0.42, 0.29, 0.13)
		if state.attempted:
			color = color.darkened(0.58)
		draw_rect(Rect2(state.position - Vector2(22.0, 30.0), Vector2(44.0, 60.0)), color, true)
		draw_string(BUNDLED_UI_FONT, state.position + Vector2(-34.0, 48.0), state.display_name(), HORIZONTAL_ALIGNMENT_CENTER, 68.0, 13, object_text_color)

	for solid_rect: Rect2 in _solid_rectangles:
		draw_rect(solid_rect, Color(0.17, 0.18, 0.18), true)

	for hide_spot: FieldHideSpotState in _session.hide_spots:
		var hide_color := Color(0.19, 0.24, 0.23) if hide_spot.spot_type == FieldHideSpotState.TYPE_CABINET else Color(0.24, 0.2, 0.17)
		draw_rect(hide_spot.blocker_rect, hide_color, true)
		draw_rect(hide_spot.blocker_rect, Color(0.38, 0.4, 0.36), false, 2.0)
		draw_string(BUNDLED_UI_FONT, hide_spot.position + Vector2(-58.0, 72.0), hide_spot.display_name(), HORIZONTAL_ALIGNMENT_CENTER, 116.0, 14, hide_text_color)


func _rebuild_geometry(route: FieldRoute) -> void:
	for child: Node in geometry.get_children():
		child.free()
	_solid_rectangles.clear()
	_light_occluders.clear()
	_named_sight_blockers.clear()
	_named_light_occluders.clear()
	var route_width: float = route.bounds.size.x
	var gap_left: float = route.branch_position.x - 170.0
	var gap_right: float = route.branch_position.x + 170.0
	if route.branch_direction < 0:
		_add_solid(Rect2(0.0, 238.0, gap_left, WALL_THICKNESS), &"wall")
		_add_solid(Rect2(gap_right, 238.0, route_width - gap_right, WALL_THICKNESS))
		_add_solid(Rect2(0.0, 640.0, route_width, WALL_THICKNESS))
		_add_solid(Rect2(gap_left - WALL_THICKNESS, 48.0, WALL_THICKNESS, 190.0))
		_add_solid(Rect2(gap_right, 48.0, WALL_THICKNESS, 190.0))
		_add_solid(Rect2(gap_left - WALL_THICKNESS, 38.0, gap_right - gap_left + WALL_THICKNESS * 2.0, WALL_THICKNESS))
	else:
		_add_solid(Rect2(0.0, 238.0, route_width, WALL_THICKNESS), &"wall")
		_add_solid(Rect2(0.0, 640.0, gap_left, WALL_THICKNESS))
		_add_solid(Rect2(gap_right, 640.0, route_width - gap_right, WALL_THICKNESS))
		_add_solid(Rect2(gap_left - WALL_THICKNESS, 662.0, WALL_THICKNESS, 190.0))
		_add_solid(Rect2(gap_right, 662.0, WALL_THICKNESS, 190.0))
		_add_solid(Rect2(gap_left - WALL_THICKNESS, 840.0, gap_right - gap_left + WALL_THICKNESS * 2.0, WALL_THICKNESS))
	_add_solid(Rect2(0.0, 238.0, WALL_THICKNESS, 424.0))
	_add_solid(Rect2(route_width - WALL_THICKNESS, 238.0, WALL_THICKNESS, 424.0))
	_add_solid(Rect2(route.main_module_positions[0] + Vector2(105.0, -55.0), Vector2(50.0, 110.0)), &"column")
	_add_solid(Rect2(route.main_module_positions[2] + Vector2(-80.0, -135.0), Vector2(160.0, 30.0)))
	for hide_spot: FieldHideSpotState in _session.hide_spots:
		var blocker_name: StringName = &"closed_shutter" if hide_spot.spot_type == FieldHideSpotState.TYPE_CLOSED_SHUTTER else &"cabinet"
		_add_solid(hide_spot.blocker_rect, blocker_name)
	_rebuild_restored_fixtures(route)


func _add_solid(rectangle: Rect2, blocker_name: StringName = &"") -> void:
	_solid_rectangles.append(rectangle)
	if blocker_name != &"":
		_named_sight_blockers[blocker_name] = rectangle
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	var collision_shape := CollisionShape2D.new()
	var rectangle_shape := RectangleShape2D.new()
	rectangle_shape.size = rectangle.size
	collision_shape.shape = rectangle_shape
	collision_shape.position = rectangle.position + rectangle.size * 0.5
	body.add_child(collision_shape)
	geometry.add_child(body)

	var light_occluder := LightOccluder2D.new()
	light_occluder.name = "LightOccluder%02d" % _light_occluders.size()
	light_occluder.position = rectangle.position
	light_occluder.occluder_light_mask = 1
	var occluder_polygon := OccluderPolygon2D.new()
	occluder_polygon.closed = true
	occluder_polygon.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(rectangle.size.x, 0.0),
		rectangle.size,
		Vector2(0.0, rectangle.size.y),
	])
	light_occluder.occluder = occluder_polygon
	geometry.add_child(light_occluder)
	_light_occluders.append(light_occluder)
	if blocker_name != &"":
		_named_light_occluders[blocker_name] = light_occluder
