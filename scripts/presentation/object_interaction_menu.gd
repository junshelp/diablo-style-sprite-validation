class_name ObjectInteractionMenu
extends Control

signal base_search_selected
signal tool_selected(tool_id: StringName)
signal cancel_requested

const STAGE_OBJECT: StringName = &"object"
const STAGE_ITEM: StringName = &"item"

@onready var interaction_panel: PanelContainer = %InteractionPanel
@onready var object_name_label: Label = %ObjectNameLabel
@onready var object_stage: VBoxContainer = %ObjectStage
@onready var item_stage: VBoxContainer = %ItemStage
@onready var base_search_button: Button = %BaseSearchButton
@onready var use_item_button: Button = %UseItemButton
@onready var crowbar_button: Button = %CrowbarButton
@onready var fuse_button: Button = %FuseButton

var _stage: StringName = STAGE_OBJECT


func _ready() -> void:
	base_search_button.pressed.connect(_select_base_search)
	use_item_button.pressed.connect(show_item_stage)
	crowbar_button.pressed.connect(_select_crowbar)
	fuse_button.pressed.connect(_select_fuse)
	close_menu()


func open_menu(object_display_name: String, crowbar_count: int, fuse_count: int) -> void:
	object_name_label.text = object_display_name
	crowbar_button.text = "빠루\n보유 %d" % crowbar_count
	fuse_button.text = "퓨즈\n보유 %d" % fuse_count
	crowbar_button.disabled = crowbar_count <= 0
	fuse_button.disabled = fuse_count <= 0
	visible = true
	show_object_stage()


func close_menu() -> void:
	visible = false
	_stage = STAGE_OBJECT
	object_stage.visible = true
	item_stage.visible = false


func show_object_stage() -> void:
	_stage = STAGE_OBJECT
	object_stage.visible = true
	item_stage.visible = false
	base_search_button.grab_focus()


func show_item_stage() -> void:
	_stage = STAGE_ITEM
	object_stage.visible = false
	item_stage.visible = true
	if not crowbar_button.disabled:
		crowbar_button.grab_focus()
	else:
		fuse_button.grab_focus()


func go_back() -> void:
	if _stage == STAGE_ITEM:
		show_object_stage()
	else:
		cancel_requested.emit()


func current_stage() -> StringName:
	return _stage


func top_level_choices() -> Array[String]:
	return [base_search_button.text, use_item_button.text]


func tool_entries() -> Array[Dictionary]:
	return [
		{"tool_id": ObjectInteractionRules.TOOL_CROWBAR, "label": "빠루", "button": crowbar_button},
		{"tool_id": ObjectInteractionRules.TOOL_FUSE, "label": "퓨즈", "button": fuse_button},
	]


func visible_text() -> String:
	var lines: Array[String] = [object_name_label.text]
	if _stage == STAGE_OBJECT:
		lines.append(base_search_button.text)
		lines.append(use_item_button.text)
	else:
		lines.append("사용할 아이템")
		lines.append(crowbar_button.text)
		lines.append(fuse_button.text)
		lines.append("한 번만 시도할 수 있습니다")
	lines.append("E 선택")
	lines.append("ESC 뒤로")
	return "\n".join(lines)


func panel_rect() -> Rect2:
	return interaction_panel.get_global_rect()


func tool_button_rects() -> Array[Rect2]:
	return [crowbar_button.get_global_rect(), fuse_button.get_global_rect()]


func select_base_search_for_test() -> void:
	_select_base_search()


func select_tool_for_test(tool_id: StringName) -> void:
	if tool_id == ObjectInteractionRules.TOOL_CROWBAR:
		_select_crowbar()
	elif tool_id == ObjectInteractionRules.TOOL_FUSE:
		_select_fuse()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_E:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is Button:
			(focused as Button).pressed.emit()
			get_viewport().set_input_as_handled()


func _select_base_search() -> void:
	base_search_selected.emit()


func _select_crowbar() -> void:
	if not crowbar_button.disabled:
		tool_selected.emit(ObjectInteractionRules.TOOL_CROWBAR)


func _select_fuse() -> void:
	if not fuse_button.disabled:
		tool_selected.emit(ObjectInteractionRules.TOOL_FUSE)
