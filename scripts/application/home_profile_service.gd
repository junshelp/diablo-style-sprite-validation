class_name HomeProfileService
extends RefCounted

class LoadResult:
	extends RefCounted

	var ok: bool
	var profile: HomeProfile
	var error_message: String

	func _init(result_ok: bool, result_profile: HomeProfile = null, result_error: String = "") -> void:
		ok = result_ok
		profile = result_profile
		error_message = result_error


class SettlementResult:
	extends RefCounted

	var ok: bool
	var profile: HomeProfile
	var extraction_point: StringName
	var confirmed_parts: int
	var error_message: String

	func _init(
		result_ok: bool,
		result_profile: HomeProfile = null,
		result_extraction_point: StringName = &"",
		result_confirmed_parts: int = 0,
		result_error: String = ""
	) -> void:
		ok = result_ok
		profile = result_profile
		extraction_point = result_extraction_point
		confirmed_parts = result_confirmed_parts
		error_message = result_error


var _clock: ClockPort
var _storage: ProfileStoragePort


func _init(clock: ClockPort, storage: ProfileStoragePort) -> void:
	_clock = clock
	_storage = storage


func load_or_create() -> LoadResult:
	var now_unix_ms: int = _clock.now_unix_ms()
	if not _storage.profile_exists():
		var new_profile: HomeProfile = HomeProfile.create_new(now_unix_ms)
		return _persist(new_profile)

	var document: Dictionary = _storage.read_profile()
	if not _storage.last_error_message().is_empty():
		return LoadResult.new(false, null, _storage.last_error_message())

	var validation_error: String = HomeProfile.document_error(document)
	if not validation_error.is_empty():
		return LoadResult.new(false, null, validation_error)

	var loaded_profile: HomeProfile = HomeProfile.from_document(document)
	loaded_profile.accrue_supply(now_unix_ms)
	return _persist(loaded_profile)


func refresh(profile: HomeProfile) -> LoadResult:
	if profile == null:
		return LoadResult.new(false, null, "profile is required")

	profile.accrue_supply(_clock.now_unix_ms())
	return _persist(profile)


func consume_one_departure_supply(profile: HomeProfile) -> LoadResult:
	if profile == null:
		return LoadResult.new(false, null, "profile is required")

	var candidate: HomeProfile = HomeProfile.from_document(profile.to_document())
	candidate.accrue_supply(_clock.now_unix_ms())
	if not candidate.consume_departure_supply():
		return LoadResult.new(false, null, "출발 보급이 1회분보다 적습니다.")

	return _persist(candidate)


func settle_extraction(
	profile: HomeProfile,
	session: FieldSession,
	point_type: StringName
) -> SettlementResult:
	if profile == null or session == null:
		return SettlementResult.new(false, null, point_type, 0, "profile and field session are required")
	if not ExtractionUpgradeRules.is_valid_extraction_point(point_type):
		return SettlementResult.new(false, null, point_type, 0, "알 수 없는 회수 지점입니다.")
	if not session.can_attempt_extraction():
		return SettlementResult.new(false, null, point_type, 0, "현재 상태에서는 회수할 수 없습니다.")

	var confirmed_parts: int = ExtractionUpgradeRules.settlement_parts(session.unextracted_parts, point_type)
	var candidate: HomeProfile = HomeProfile.from_document(profile.to_document())
	candidate.accrue_supply(_clock.now_unix_ms())
	candidate.facility_parts += confirmed_parts
	var persisted: LoadResult = _persist(candidate)
	if not persisted.ok:
		return SettlementResult.new(false, null, point_type, 0, persisted.error_message)

	session.complete_extraction(point_type)
	return SettlementResult.new(true, persisted.profile, point_type, confirmed_parts)


func upgrade_producer(profile: HomeProfile) -> LoadResult:
	if profile == null:
		return LoadResult.new(false, null, "profile is required")

	var candidate: HomeProfile = HomeProfile.from_document(profile.to_document())
	candidate.accrue_supply(_clock.now_unix_ms())
	var upgrade_error: String = ExtractionUpgradeRules.producer_upgrade_error(candidate)
	if not upgrade_error.is_empty():
		return LoadResult.new(false, null, upgrade_error)
	ExtractionUpgradeRules.apply_producer_upgrade(candidate)
	return _persist(candidate)


func _persist(profile: HomeProfile) -> LoadResult:
	var write_error: Error = _storage.write_profile(profile.to_document())
	if write_error != OK:
		var message: String = _storage.last_error_message()
		if message.is_empty():
			message = "profile could not be written"
		return LoadResult.new(false, null, message)

	return LoadResult.new(true, profile)
