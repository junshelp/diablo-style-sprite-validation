class_name MemoryProfileStorage
extends ProfileStoragePort

var _has_document: bool = false
var _document: Dictionary = {}
var _last_error_message: String = ""
var _write_count: int = 0
var _write_attempt_count: int = 0
var _fail_next_write: bool = false
var _next_write_error_message: String = ""


func _init(initial_document: Dictionary = {}) -> void:
	if not initial_document.is_empty():
		seed_profile(initial_document)


func profile_exists() -> bool:
	return _has_document


func read_profile() -> Dictionary:
	_last_error_message = ""
	if not _has_document:
		_last_error_message = "profile does not exist"
		return {}
	return _document.duplicate(true)


func write_profile(document: Dictionary) -> Error:
	_last_error_message = ""
	_write_attempt_count += 1
	if _fail_next_write:
		_fail_next_write = false
		_last_error_message = _next_write_error_message
		_next_write_error_message = ""
		return ERR_CANT_CREATE
	_document = document.duplicate(true)
	_has_document = true
	_write_count += 1
	return OK


func last_error_message() -> String:
	return _last_error_message


func seed_profile(document: Dictionary) -> void:
	_document = document.duplicate(true)
	_has_document = true


func stored_document() -> Dictionary:
	return _document.duplicate(true)


func write_count() -> int:
	return _write_count


func write_attempt_count() -> int:
	return _write_attempt_count


func fail_next_write(message: String = "forced memory storage write failure") -> void:
	_fail_next_write = true
	_next_write_error_message = message
