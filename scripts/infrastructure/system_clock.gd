class_name SystemClock
extends ClockPort


func now_unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

