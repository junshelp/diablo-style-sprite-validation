class_name ProfileStoragePort
extends RefCounted


func profile_exists() -> bool:
	push_error("ProfileStoragePort.profile_exists must be implemented")
	return false


func read_profile() -> Dictionary:
	push_error("ProfileStoragePort.read_profile must be implemented")
	return {}


func write_profile(_document: Dictionary) -> Error:
	push_error("ProfileStoragePort.write_profile must be implemented")
	return ERR_UNAVAILABLE


func last_error_message() -> String:
	return ""

