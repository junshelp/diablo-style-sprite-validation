class_name MobileFieldControls
extends CanvasLayer

signal movement_vector_changed(vector: Vector2)
signal action_requested
signal environment_changed(touch_environment: bool, portrait: bool, layout_scale: float)

const MINIMUM_TOUCH_TARGET: float = 58.0
const BROWSER_TEST_QUERY: String = "mobile"

@onready var landscape_controls: Control = %LandscapeControls
@onready var portrait_notice: Control = %PortraitNotice
@onready var action_button: Button = %ActionButton
@onready var direction_pad: PanelContainer = $ResponsiveRoot/LandscapeControls/DirectionPad
@onready var pad_margin: MarginContainer = $ResponsiveRoot/LandscapeControls/DirectionPad/PadMargin
@onready var pad_grid: GridContainer = $ResponsiveRoot/LandscapeControls/DirectionPad/PadMargin/PadGrid
@onready var notice_panel: PanelContainer = $ResponsiveRoot/PortraitNotice/NoticeCenter/NoticePanel
@onready var notice_margin: MarginContainer = $ResponsiveRoot/PortraitNotice/NoticeCenter/NoticePanel/NoticeMargin
@onready var notice_layout: VBoxContainer = $ResponsiveRoot/PortraitNotice/NoticeCenter/NoticePanel/NoticeMargin/NoticeLayout
@onready var notice_title: Label = $ResponsiveRoot/PortraitNotice/NoticeCenter/NoticePanel/NoticeMargin/NoticeLayout/NoticeTitle
@onready var notice_body: Label = $ResponsiveRoot/PortraitNotice/NoticeCenter/NoticePanel/NoticeMargin/NoticeLayout/NoticeBody

var _field_active: bool = false
var _menu_blocked: bool = false
var _touch_environment: bool = false
var _portrait: bool = false
var _layout_scale: float = 1.0
var _movement_vector: Vector2 = Vector2.ZERO
var _active_touch_index: int = -1
var _mouse_direction_active: bool = false
var _test_override_enabled: bool = false
var _test_touch_available: bool = false
var _test_viewport_size: Vector2i = Vector2i.ZERO
var _direction_buttons: Array[Button] = []
var _desktop_content_scale_aspect: int = Window.CONTENT_SCALE_ASPECT_KEEP


func _ready() -> void:
	_desktop_content_scale_aspect = get_window().content_scale_aspect
	_bind_direction_button(%NorthWestButton, Vector2(-0.70710678, -0.70710678))
	_bind_direction_button(%NorthButton, Vector2.UP)
	_bind_direction_button(%NorthEastButton, Vector2(0.70710678, -0.70710678))
	_bind_direction_button(%WestButton, Vector2.LEFT)
	_bind_direction_button(%EastButton, Vector2.RIGHT)
	_bind_direction_button(%SouthWestButton, Vector2(-0.70710678, 0.70710678))
	_bind_direction_button(%SouthButton, Vector2.DOWN)
	_bind_direction_button(%SouthEastButton, Vector2(0.70710678, 0.70710678))
	action_button.pressed.connect(_emit_action)
	get_viewport().size_changed.connect(refresh_environment)
	refresh_environment()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_movement()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if not touch_event.pressed and touch_event.index == _active_touch_index:
			_release_movement()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and not mouse_event.pressed and _mouse_direction_active:
			_release_movement()


func refresh_environment() -> void:
	var viewport_size: Vector2i = _effective_viewport_size()
	var touch_available: bool = (
		_test_touch_available
		if _test_override_enabled
		else DisplayServer.is_touchscreen_available() or _browser_test_override_enabled()
	)
	var portrait: bool = touch_available and viewport_size.y > viewport_size.x
	var layout_scale: float = _layout_scale_for_viewport(viewport_size) if touch_available else 1.0
	var environment_did_change: bool = (
		touch_available != _touch_environment
		or portrait != _portrait
		or not is_equal_approx(layout_scale, _layout_scale)
	)
	_touch_environment = touch_available
	_portrait = portrait
	_layout_scale = layout_scale
	get_window().content_scale_aspect = (
		Window.CONTENT_SCALE_ASPECT_EXPAND
		if _touch_environment
		else _desktop_content_scale_aspect
	)
	_apply_touch_metrics()
	portrait_notice.visible = _touch_environment and _portrait
	_update_landscape_controls()
	if environment_did_change:
		environment_changed.emit(_touch_environment, _portrait, _layout_scale)


func set_field_active(value: bool) -> void:
	_field_active = value
	_update_landscape_controls()


func set_menu_blocked(value: bool) -> void:
	_menu_blocked = value
	_update_landscape_controls()


func set_test_environment(touch_available: bool, viewport_size: Vector2i) -> void:
	_test_override_enabled = true
	_test_touch_available = touch_available
	_test_viewport_size = viewport_size
	refresh_environment()


func clear_test_environment() -> void:
	_test_override_enabled = false
	_test_viewport_size = Vector2i.ZERO
	refresh_environment()


func hold_direction_for_test(direction: Vector2) -> bool:
	if not gameplay_input_enabled():
		return false
	_set_movement(direction)
	return true


func release_movement_for_test() -> void:
	_release_movement()


func cancel_movement_for_test() -> void:
	_release_movement()


func press_action_for_test() -> bool:
	if not gameplay_input_enabled():
		return false
	action_requested.emit()
	return true


func gameplay_input_enabled() -> bool:
	return _touch_environment and not _portrait and _field_active and not _menu_blocked


func movement_vector() -> Vector2:
	return _movement_vector


func environment_snapshot() -> Dictionary:
	var direction_rects: Array[Rect2] = []
	for button: Button in _direction_buttons:
		direction_rects.append(button.get_global_rect())
	return {
		"touch_environment": _touch_environment,
		"portrait": _portrait,
		"field_active": _field_active,
		"menu_blocked": _menu_blocked,
		"gameplay_input_enabled": gameplay_input_enabled(),
		"landscape_controls_visible": landscape_controls.visible,
		"portrait_notice_visible": portrait_notice.visible,
		"portrait_notice_blocks_input": portrait_notice.mouse_filter == Control.MOUSE_FILTER_STOP,
		"movement_vector": _movement_vector,
		"direction_button_rects": direction_rects,
		"action_button_rect": action_button.get_global_rect(),
		"minimum_touch_target": MINIMUM_TOUCH_TARGET,
		"viewport_size": _effective_viewport_size(),
		"layout_scale": _layout_scale,
	}


func _bind_direction_button(button: Button, direction: Vector2) -> void:
	_direction_buttons.append(button)
	button.gui_input.connect(_on_direction_gui_input.bind(direction))


func _on_direction_gui_input(event: InputEvent, direction: Vector2) -> void:
	if not gameplay_input_enabled():
		return
	if event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed and (_active_touch_index < 0 or _active_touch_index == touch_event.index):
			_active_touch_index = touch_event.index
			_set_movement(direction)
			get_viewport().set_input_as_handled()
		elif not touch_event.pressed and touch_event.index == _active_touch_index:
			_release_movement()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_mouse_direction_active = true
			_set_movement(direction)
		else:
			_release_movement()
		get_viewport().set_input_as_handled()


func _set_movement(direction: Vector2) -> void:
	var next_vector: Vector2 = direction
	if next_vector.length_squared() > 1.0:
		next_vector = next_vector.normalized()
	if next_vector.is_equal_approx(_movement_vector):
		return
	_movement_vector = next_vector
	movement_vector_changed.emit(_movement_vector)


func _release_movement() -> void:
	_active_touch_index = -1
	_mouse_direction_active = false
	_set_movement(Vector2.ZERO)


func _emit_action() -> void:
	if gameplay_input_enabled():
		action_requested.emit()


func _update_landscape_controls() -> void:
	var controls_should_show: bool = gameplay_input_enabled()
	if not controls_should_show:
		_release_movement()
	landscape_controls.visible = controls_should_show
	action_button.disabled = not controls_should_show


func _apply_touch_metrics() -> void:
	var scale_factor: float = _layout_scale if _touch_environment else 1.0
	var target_size: float = MINIMUM_TOUCH_TARGET * scale_factor
	for button: Button in _direction_buttons:
		button.custom_minimum_size = Vector2(target_size, target_size)
		button.add_theme_font_size_override("font_size", int(round(23.0 * scale_factor)))
	($ResponsiveRoot/LandscapeControls/DirectionPad/PadMargin/PadGrid/PadCenter as Control).custom_minimum_size = Vector2(target_size, target_size)
	pad_grid.add_theme_constant_override("h_separation", int(round(4.0 * scale_factor)))
	pad_grid.add_theme_constant_override("v_separation", int(round(4.0 * scale_factor)))
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		pad_margin.add_theme_constant_override(side, int(round(6.0 * scale_factor)))
	direction_pad.offset_left = 16.0 * scale_factor
	direction_pad.offset_top = -210.0 * scale_factor
	direction_pad.offset_right = 210.0 * scale_factor
	direction_pad.offset_bottom = -16.0 * scale_factor
	action_button.offset_left = -152.0 * scale_factor
	action_button.offset_top = -108.0 * scale_factor
	action_button.offset_right = -16.0 * scale_factor
	action_button.offset_bottom = -16.0 * scale_factor
	action_button.custom_minimum_size = Vector2(136.0, 92.0) * scale_factor
	action_button.add_theme_font_size_override("font_size", int(round(24.0 * scale_factor)))
	notice_panel.custom_minimum_size = Vector2(340.0, 174.0) * scale_factor
	for side: StringName in [&"margin_left", &"margin_right"]:
		notice_margin.add_theme_constant_override(side, int(round(24.0 * scale_factor)))
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		notice_margin.add_theme_constant_override(side, int(round(22.0 * scale_factor)))
	notice_layout.add_theme_constant_override("separation", int(round(12.0 * scale_factor)))
	notice_title.add_theme_font_size_override("font_size", int(round(25.0 * scale_factor)))
	notice_body.add_theme_font_size_override("font_size", int(round(16.0 * scale_factor)))


func _effective_viewport_size() -> Vector2i:
	if _test_override_enabled and _test_viewport_size != Vector2i.ZERO:
		return _test_viewport_size
	if OS.has_feature("web"):
		var browser_size: Vector2i = _browser_viewport_size()
		if browser_size != Vector2i.ZERO:
			return browser_size
	return Vector2i(get_viewport().get_visible_rect().size)


func _browser_test_override_enabled() -> bool:
	if not OS.has_feature("web"):
		return false
	var result: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(window.location.search).get('%s') === '1'" % BROWSER_TEST_QUERY,
		true
	)
	return bool(result)


func _browser_viewport_size() -> Vector2i:
	var size_text: String = str(JavaScriptBridge.eval(
		"window.innerWidth.toString() + ',' + window.innerHeight.toString()",
		true
	))
	var parts: PackedStringArray = size_text.split(",", false, 1)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	return Vector2i(parts[0].to_int(), parts[1].to_int())


func _layout_scale_for_viewport(viewport_size: Vector2i) -> float:
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return 1.0
	var base_size: Vector2i = get_window().content_scale_size
	if base_size == Vector2i.ZERO:
		base_size = Vector2i(1600, 900)
	return maxf(
		float(base_size.x) / float(viewport_size.x),
		float(base_size.y) / float(viewport_size.y)
	)
