class_name FakeClock
extends ClockPort

var _now_unix_ms: int


func _init(initial_unix_ms: int = 0) -> void:
	_now_unix_ms = initial_unix_ms


func now_unix_ms() -> int:
	return _now_unix_ms


func advance(milliseconds: int) -> void:
	_now_unix_ms += milliseconds


func set_now(unix_ms: int) -> void:
	_now_unix_ms = unix_ms

