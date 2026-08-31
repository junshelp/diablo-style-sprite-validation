class_name ClockPort
extends RefCounted


func now_unix_ms() -> int:
	push_error("ClockPort.now_unix_ms must be implemented")
	return 0

