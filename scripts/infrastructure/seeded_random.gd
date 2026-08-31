class_name SeededRandom
extends RandomPort

var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func set_seed(value: int) -> void:
	_random.seed = value


func next_int(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return _random.randi_range(0, max_exclusive - 1)
