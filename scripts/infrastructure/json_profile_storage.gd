class_name JsonProfileStorage
extends ProfileStoragePort

const DEFAULT_STORAGE_PATH: String = "user://home_profile_v1.json"

var _storage_path: String
var _last_error_message: String = ""


func _init(storage_path: String = DEFAULT_STORAGE_PATH) -> void:
	_storage_path = storage_path


func profile_exists() -> bool:
	return FileAccess.file_exists(_storage_path)


func read_profile() -> Dictionary:
	_last_error_message = ""
	if not profile_exists():
		_last_error_message = "profile does not exist"
		return {}

	var file: FileAccess = FileAccess.open(_storage_path, FileAccess.READ)
	if file == null:
		_last_error_message = "profile could not be opened for reading"
		return {}

	var source_text: String = file.get_as_text()
	file.close()
	var parser: JSON = JSON.new()
	var parse_error: Error = parser.parse(source_text)
	if parse_error != OK:
		_last_error_message = "profile JSON could not be parsed"
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		_last_error_message = "profile JSON root must be an object"
		return {}

	var document: Dictionary = parser.data
	return document


func write_profile(document: Dictionary) -> Error:
	_last_error_message = ""
	var file: FileAccess = FileAccess.open(_storage_path, FileAccess.WRITE)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		_last_error_message = "profile could not be opened for writing"
		return open_error

	file.store_string(JSON.stringify(document, "\t") + "\n")
	file.close()
	return OK


func last_error_message() -> String:
	return _last_error_message

