extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const UI_THEME_PATH: String = "res://assets/ui/dark_horror_ui_theme.tres"
const FONT_VARIATION_PATH: String = "res://assets/fonts/NotoSansKR-UI.tres"
const WEB_VIEWPORT_SIZE: Vector2i = Vector2i(1280, 720)
const COMPACT_SIZE: Vector2 = Vector2(720.0, 405.0)
const PRIMARY_TEXT_CONTRAST: float = 4.5
const MUTED_TEXT_CONTRAST: float = 3.0
const CONTROL_BOUNDARY_CONTRAST: float = 3.0
const ACCEPTED_UI_EVIDENCE_HASHES: Dictionary = {
	"res://_workspace/desktop-horror-prototype/evidence/task-070-web-playtest/local-web.png": "910d075ec22edd458b2d7f4abfd99897e37e994192ee139053c38fe512418600",
	"res://_workspace/desktop-horror-prototype/evidence/task-070-web-playtest/pages-home.png": "910d075ec22edd458b2d7f4abfd99897e37e994192ee139053c38fe512418600",
	"res://_workspace/desktop-horror-prototype/evidence/task-070-web-playtest/pages-field.png": "1565a475b6c701b56e589cb8b457b7ed06d150203a411fdf074770ece7950f4a",
	"res://_workspace/desktop-horror-prototype/evidence/task-070-web-playtest/pages-reload-home.png": "e7a620fbc3516c2bfe52e45ef7b17195f7b15e1347368bffb7690164c2b2047c",
	"res://_workspace/desktop-horror-prototype/evidence/task-080-ui-visibility/before-home.png": "4cfbddf5c53236f79f84d56e6a1d8c7963dc6fd6d7e4143f8cac10561ab6fb71",
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	get_root().size = WEB_VIEWPORT_SIZE
	_test_shared_theme_and_font()
	await _test_home_field_and_menu()
	_test_accepted_evidence()
	get_root().size = Vector2i(1600, 900)
	_finish()


func _test_shared_theme_and_font() -> void:
	var theme: Theme = load(UI_THEME_PATH) as Theme
	_check(theme != null, "shared dark horror UI theme loads")
	if theme == null:
		return
	_check(ProjectSettings.get_setting("gui/theme/custom") == UI_THEME_PATH, "project connects the shared global UI theme")
	_check(ProjectSettings.get_setting("gui/theme/custom_font") == FONT_VARIATION_PATH, "project keeps the bundled Korean FontVariation")
	var font_variation: FontVariation = load(FONT_VARIATION_PATH) as FontVariation
	_check(font_variation != null and font_variation.variation_embolden >= 0.2, "Web Korean font uses a modest legibility embolden")
	for color_name: StringName in [&"module_text", &"object_text", &"hide_text"]:
		_check(theme.has_color(color_name, &"FieldCanvas"), "shared theme exposes field canvas %s" % color_name)
	var field_background := Color(0.105, 0.12, 0.12)
	_check_contrast(theme.get_color(&"module_text", &"FieldCanvas"), field_background, PRIMARY_TEXT_CONTRAST, "module canvas text")
	_check_contrast(theme.get_color(&"object_text", &"FieldCanvas"), field_background, PRIMARY_TEXT_CONTRAST, "object canvas text")
	_check_contrast(theme.get_color(&"hide_text", &"FieldCanvas"), field_background, PRIMARY_TEXT_CONTRAST, "hide canvas text")


func _test_home_field_and_menu() -> void:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	_check(packed_scene != null, "main scene loads for visibility smoke")
	if packed_scene == null:
		return
	var now_ms: int = 3_000_000_000
	var profile := HomeProfile.new(2.0, 4, false, now_ms)
	var storage := MemoryProfileStorage.new(profile.to_document())
	var clock := FakeClock.new(now_ms)
	var home_service := HomeProfileService.new(clock, storage)
	var app_root := packed_scene.instantiate() as AppRoot
	app_root.configure_home_profile_service(home_service)
	app_root.configure_expedition_service(ExpeditionService.new(home_service, FieldRouteBuilder.new(SeededRandom.new())))
	app_root.configure_field_interaction_service(FieldInteractionService.new(SeededRandom.new()))
	app_root.configure_field_encounter_service(FieldEncounterService.new())
	get_root().add_child(app_root)
	await process_frame
	await process_frame

	var compact := app_root.get_node("%CompactSurface") as PanelContainer
	var room := app_root.get_node("CompactSurface/CompactMargin/CompactLayout/RoomPlaceholder") as PanelContainer
	var home_status := app_root.get_node("%HomeStatus") as VBoxContainer
	var compact_background := (compact.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color
	var room_background := (room.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color
	var supply_card := home_status.get_node("SupplyCard") as PanelContainer
	var supply_background := (supply_card.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color
	_check(compact.size.is_equal_approx(COMPACT_SIZE), "shared theme preserves the 720x405 compact surface")
	_check(_viewport_contains(compact.get_global_rect()), "compact surface remains visible at 1280x720")
	_check_label(app_root.get_node("CompactSurface/CompactMargin/CompactLayout/HomeTitle") as Label, compact_background, PRIMARY_TEXT_CONTRAST, "home title")
	_check_label(home_status.get_node("StatusTitle") as Label, room_background, PRIMARY_TEXT_CONTRAST, "home status title")
	for node_name: String in ["SupplyName", "SupplyValue", "SupplyProgress"]:
		_check_label(home_status.get_node("SupplyCard/SupplyMargin/SupplyLayout/%s" % ("SupplyRow/" + node_name if node_name != "SupplyProgress" else node_name)) as Label, supply_background, PRIMARY_TEXT_CONTRAST, node_name)
	for node_path: String in ["Details/PartsGroup/PartsTitle", "Details/PartsGroup/FacilityPartsValue", "Details/ProducerGroup/ProducerTitle", "Details/ProducerGroup/ProducerStateValue", "TestLoadout", "DepartureMessage", "StorageState"]:
		_check_label(home_status.get_node(node_path) as Label, room_background, MUTED_TEXT_CONTRAST if node_path in ["TestLoadout", "StorageState"] else PRIMARY_TEXT_CONTRAST, node_path)

	var departure := home_status.get_node("%DepartureButton") as Button
	var upgrade := home_status.get_node("%UpgradeButton") as Button
	var condition := home_status.get_node("%ConditionSelect") as OptionButton
	var flashlight := home_status.get_node("%FlashlightSelect") as OptionButton
	var surface_toggle := app_root.get_node("%SurfaceToggle") as Button
	_check(not departure.disabled and not upgrade.disabled, "active fixture exposes departure and upgrade as enabled controls")
	_check(departure.theme_type_variation == &"PrimaryButton" and upgrade.theme_type_variation == &"PrimaryButton", "departure and upgrade use the primary control variation")
	_check(surface_toggle.theme_type_variation == &"PrimaryButton", "surface toggle reads as a primary control")
	_check_button_states(departure, room_background, "departure")
	_check_button_states(upgrade, room_background, "upgrade")
	_check_button_states(surface_toggle, Color(0.0235294, 0.027451, 0.0352941), "surface toggle")
	_check_button_states(condition, room_background, "condition option")
	_check_button_states(flashlight, room_background, "flashlight option")
	for control: Control in [departure, upgrade, condition, flashlight]:
		_check(compact.get_global_rect().encloses(control.get_global_rect()), "%s remains inside compact home at 1280x720" % control.name)

	_check(app_root.attempt_departure(FieldSession.CONDITION_NORMAL, true, 4_242), "visibility fixture reaches the real field")
	await process_frame
	await physics_frame
	var field_view := app_root.get_node("%FieldSessionView") as FieldSessionView
	var hud_background := Color(0.025, 0.03, 0.034)
	var field_labels: Dictionary = {
		"ConditionLabel": field_view.get_node("%ConditionLabel"),
		"LoadoutLabel": field_view.get_node("%LoadoutLabel"),
		"RouteLabel": field_view.get_node("%RouteLabel"),
		"SessionStateLabel": field_view.get_node("%SessionStateLabel"),
		"HpLabel": field_view.get_node("%HpLabel"),
		"EncounterStateLabel": field_view.get_node("%EncounterStateLabel"),
		"ControlHint": field_view.get_node("FieldCanvas/FieldHud/ControlHint"),
		"ReturnPrompt": field_view.get_node("%ReturnPrompt"),
		"ObjectPrompt": field_view.get_node("%ObjectPrompt"),
		"HidePrompt": field_view.get_node("%HidePrompt"),
		"ResultLabel": field_view.get_node("%ResultLabel"),
	}
	for node_name: String in field_labels:
		var label := field_labels[node_name] as Label
		_check(label != null, "field %s label exists" % node_name)
		if label == null:
			continue
		_check_label(label, hud_background, MUTED_TEXT_CONTRAST if node_name in ["RouteLabel", "EncounterStateLabel"] else PRIMARY_TEXT_CONTRAST, "field %s" % node_name)
		_check(_viewport_contains(label.get_global_rect()), "%s stays inside 1280x720 field viewport" % node_name)

	var locker_id: StringName = field_view.move_explorer_to_object_type(FieldObjectState.TYPE_LOCKER)
	_check(locker_id != &"" and field_view.open_object_interaction_for_test(locker_id), "visibility fixture opens the real object menu")
	await process_frame
	var menu: ObjectInteractionMenu = field_view.interaction_menu_node()
	var panel := menu.get_node("ScreenMargin/PanelLayout/InteractionPanel") as PanelContainer
	var panel_background := (panel.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color
	var content := panel.get_node("PanelMargin/Content")
	_check(_viewport_contains(menu.panel_rect()), "object interaction panel remains visible at 1280x720")
	_check_label(content.get_node("Kicker") as Label, panel_background, MUTED_TEXT_CONTRAST, "menu kicker")
	_check_label(content.get_node("ObjectNameLabel") as Label, panel_background, PRIMARY_TEXT_CONTRAST, "menu object name")
	_check_label(content.get_node("Footer") as Label, panel_background, MUTED_TEXT_CONTRAST, "menu footer")
	var base_search := content.get_node("ObjectStage/BaseSearchButton") as Button
	var use_item := content.get_node("ObjectStage/UseItemButton") as Button
	_check_button_states(base_search, panel_background, "base search")
	_check_button_states(use_item, panel_background, "item use")
	_check(use_item.theme_type_variation == &"PrimaryButton", "item use remains the emphasized menu action")
	menu.show_item_stage()
	await process_frame
	_check_label(content.get_node("ItemStage/ItemLabel") as Label, panel_background, PRIMARY_TEXT_CONTRAST, "menu item heading")
	_check_label(content.get_node("ItemStage/AttemptWarning") as Label, panel_background, PRIMARY_TEXT_CONTRAST, "menu attempt warning")
	_check_button_states(content.get_node("ItemStage/ToolRow/CrowbarButton") as Button, panel_background, "crowbar choice")
	_check_button_states(content.get_node("ItemStage/ToolRow/FuseButton") as Button, panel_background, "fuse choice")

	app_root.queue_free()
	await process_frame


func _check_button_states(control: Control, adjacent_background: Color, label: String) -> void:
	var normal := control.get_theme_stylebox(&"normal") as StyleBoxFlat
	var hover := control.get_theme_stylebox(&"hover") as StyleBoxFlat
	var pressed := control.get_theme_stylebox(&"pressed") as StyleBoxFlat
	var disabled := control.get_theme_stylebox(&"disabled") as StyleBoxFlat
	var focus := control.get_theme_stylebox(&"focus") as StyleBoxFlat
	_check(normal != null and hover != null and pressed != null and disabled != null and focus != null, "%s exposes all control state styles" % label)
	if normal == null or hover == null or pressed == null or disabled == null or focus == null:
		return
	_check(normal.get_border_width(SIDE_LEFT) >= 2 and focus.get_border_width(SIDE_LEFT) >= 3, "%s has a visible normal outline and stronger focus ring" % label)
	_check(normal.bg_color != hover.bg_color and normal.bg_color != pressed.bg_color and normal.bg_color != disabled.bg_color, "%s normal/hover/pressed/disabled fills are distinct" % label)
	_check_contrast(normal.border_color, adjacent_background, CONTROL_BOUNDARY_CONTRAST, "%s normal boundary" % label)
	_check_contrast(disabled.border_color, adjacent_background, CONTROL_BOUNDARY_CONTRAST, "%s disabled boundary" % label)
	_check_contrast(control.get_theme_color(&"font_color"), normal.bg_color, PRIMARY_TEXT_CONTRAST, "%s normal label" % label)
	_check_contrast(control.get_theme_color(&"font_hover_color"), hover.bg_color, PRIMARY_TEXT_CONTRAST, "%s hover label" % label)
	_check_contrast(control.get_theme_color(&"font_pressed_color"), pressed.bg_color, PRIMARY_TEXT_CONTRAST, "%s pressed label" % label)
	_check_contrast(control.get_theme_color(&"font_disabled_color"), disabled.bg_color, PRIMARY_TEXT_CONTRAST, "%s disabled label" % label)


func _check_label(label: Label, background: Color, minimum: float, description: String) -> void:
	_check_contrast(label.get_theme_color(&"font_color"), background, minimum, description)


func _check_contrast(foreground: Color, background: Color, minimum: float, description: String) -> void:
	var actual: float = _contrast_ratio(foreground, background)
	_check(actual + 0.0001 >= minimum, "%s contrast %.2f is below %.2f" % [description, actual, minimum])


func _contrast_ratio(first: Color, second: Color) -> float:
	var first_luminance: float = _relative_luminance(first)
	var second_luminance: float = _relative_luminance(second)
	return (maxf(first_luminance, second_luminance) + 0.05) / (minf(first_luminance, second_luminance) + 0.05)


func _relative_luminance(color: Color) -> float:
	return 0.2126 * _linear_channel(color.r) + 0.7152 * _linear_channel(color.g) + 0.0722 * _linear_channel(color.b)


func _linear_channel(value: float) -> float:
	if value <= 0.04045:
		return value / 12.92
	return pow((value + 0.055) / 1.055, 2.4)


func _viewport_contains(rect: Rect2) -> bool:
	return Rect2(Vector2.ZERO, get_root().get_visible_rect().size).encloses(rect)


func _test_accepted_evidence() -> void:
	for path: String in ACCEPTED_UI_EVIDENCE_HASHES:
		_check(FileAccess.file_exists(path), "accepted/baseline UI evidence exists: %s" % path)
		if FileAccess.file_exists(path):
			_check(FileAccess.get_sha256(path) == ACCEPTED_UI_EVIDENCE_HASHES[path], "accepted/baseline UI evidence hash stays unchanged: %s" % path)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	printerr("UI_VISIBILITY_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("UI_VISIBILITY_PASS")
		quit(0)
		return
	printerr("UI_VISIBILITY_FAIL count=%d" % _failures.size())
	quit(1)
