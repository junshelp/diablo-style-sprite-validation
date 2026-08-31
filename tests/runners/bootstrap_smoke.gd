extends SceneTree

const MAIN_SCENE_PATH: String = "res://scenes/app/main.tscn"
const EXPECTED_VIEWPORT_SIZE: Vector2 = Vector2(1600.0, 900.0)
const EXPECTED_COMPACT_SIZE: Vector2 = Vector2(720.0, 405.0)

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("main scene could not be loaded")
		_finish()
		return

	var app_root: Control = packed_scene.instantiate() as Control
	var bootstrap_service: HomeProfileService = HomeProfileService.new(
		FakeClock.new(1_000_000),
		MemoryProfileStorage.new()
	)
	app_root.call("configure_home_profile_service", bootstrap_service)
	get_root().add_child(app_root)
	await process_frame

	var compact_surface: Control = app_root.get_node("%CompactSurface") as Control
	var expanded_surface: Control = app_root.get_node("%ExpandedSurface") as Control
	var mode_label: Label = app_root.get_node("%ModeLabel") as Label
	var surface_toggle: Button = app_root.get_node("%SurfaceToggle") as Button

	_check(get_root().get_visible_rect().size == EXPECTED_VIEWPORT_SIZE, "viewport is 1600x900")
	_check(compact_surface.visible, "compact home is initially visible")
	_check(not expanded_surface.visible, "expanded field is initially hidden")
	_check(compact_surface.size.is_equal_approx(EXPECTED_COMPACT_SIZE), "compact home is 720x405")
	_check(mode_label.text == "HOME / COMPACT", "initial mode is exposed as compact home")
	_check(surface_toggle.text == "필드 펼치기", "initial action expands the field")

	surface_toggle.pressed.emit()
	await process_frame
	_check(not compact_surface.visible, "compact home hides after the public toggle action")
	_check(expanded_surface.visible, "expanded field appears after the public toggle action")
	_check(expanded_surface.size.is_equal_approx(EXPECTED_VIEWPORT_SIZE), "expanded field fills 1600x900")
	_check(mode_label.text == "FIELD / EXPANDED", "expanded mode is exposed to the user")
	_check(surface_toggle.text == "집으로 접기", "expanded action returns home")

	surface_toggle.pressed.emit()
	await process_frame
	_check(compact_surface.visible, "compact home is restored by the public toggle action")
	_check(not expanded_surface.visible, "expanded field hides after returning home")
	_check(mode_label.text == "HOME / COMPACT", "return restores compact mode")

	app_root.queue_free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("BOOTSTRAP_SMOKE_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("BOOTSTRAP_SMOKE_PASS compact -> expanded -> compact")
		quit(0)
		return

	printerr("BOOTSTRAP_SMOKE_FAIL count=%d" % _failures.size())
	quit(1)
