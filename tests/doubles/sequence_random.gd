class_name SequenceRandom
extends RandomPort

var _values: Array[int]
var _index: int = 0
var last_seed: int = 0


func _init(values: Array[int] = []) -> void:
	_values = values.duplicate()


func set_seed(value: int) -> void:
	last_seed = value
	_index = 0


func next_int(max_exclusive: int) -> int:
	if max_exclusive <= 0 or _values.is_empty():
		return 0
	var value: int = _values[_index % _values.size()]
	_index += 1
	return posmod(value, max_exclusive)
