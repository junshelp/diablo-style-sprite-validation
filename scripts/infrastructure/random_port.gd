class_name RandomPort
extends RefCounted


func set_seed(_seed: int) -> void:
	push_error("RandomPort.set_seed must be implemented")


func next_int(_max_exclusive: int) -> int:
	push_error("RandomPort.next_int must be implemented")
	return 0
