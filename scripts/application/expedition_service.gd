class_name ExpeditionService
extends RefCounted

class DepartureResult:
	extends RefCounted

	var ok: bool
	var profile: HomeProfile
	var session: FieldSession
	var error_message: String

	func _init(
		result_ok: bool,
		result_profile: HomeProfile = null,
		result_session: FieldSession = null,
		result_error: String = ""
	) -> void:
		ok = result_ok
		profile = result_profile
		session = result_session
		error_message = result_error


var _home_profile_service: HomeProfileService
var _route_builder: FieldRouteBuilder


func _init(home_profile_service: HomeProfileService, route_builder: FieldRouteBuilder) -> void:
	_home_profile_service = home_profile_service
	_route_builder = route_builder


func depart(
	profile: HomeProfile,
	condition: StringName,
	flashlight_equipped: bool,
	seed: int
) -> DepartureResult:
	if not FieldSession.is_valid_condition(condition):
		return DepartureResult.new(false, null, null, "알 수 없는 현장 상태입니다.")

	var consumption: HomeProfileService.LoadResult = _home_profile_service.consume_one_departure_supply(profile)
	if not consumption.ok:
		return DepartureResult.new(false, null, null, consumption.error_message)

	var route: FieldRoute = _route_builder.build(seed)
	var session := FieldSession.new(condition, flashlight_equipped, seed, route)
	return DepartureResult.new(true, consumption.profile, session)
