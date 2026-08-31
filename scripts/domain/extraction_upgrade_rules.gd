class_name ExtractionUpgradeRules
extends RefCounted

const EXTRACTION_ENTRANCE: StringName = &"entrance"
const EXTRACTION_ENDPOINT: StringName = &"endpoint"

const SESSION_REWARD_CAP: int = 6
const ENDPOINT_MINIMUM_PARTS: int = 4
const PRODUCER_UPGRADE_COST: int = 4


static func is_valid_extraction_point(point_type: StringName) -> bool:
	return point_type == EXTRACTION_ENTRANCE or point_type == EXTRACTION_ENDPOINT


static func bounded_reward_delta(current_parts: int, requested_delta: int) -> int:
	var safe_current: int = clampi(current_parts, 0, SESSION_REWARD_CAP)
	var requested_total: int = safe_current + maxi(0, requested_delta)
	return mini(SESSION_REWARD_CAP, requested_total) - safe_current


static func settlement_parts(unextracted_parts: int, point_type: StringName) -> int:
	var bounded_parts: int = clampi(unextracted_parts, 0, SESSION_REWARD_CAP)
	if point_type == EXTRACTION_ENDPOINT:
		return maxi(ENDPOINT_MINIMUM_PARTS, bounded_parts)
	if point_type == EXTRACTION_ENTRANCE:
		return bounded_parts
	return 0


static func producer_upgrade_error(profile: HomeProfile) -> String:
	if profile == null:
		return "profile is required"
	if profile.producer_upgraded:
		return "생산 가구는 이미 강화되었습니다."
	if profile.facility_parts < PRODUCER_UPGRADE_COST:
		return "설비 부품이 %d개보다 적습니다." % PRODUCER_UPGRADE_COST
	return ""


static func apply_producer_upgrade(profile: HomeProfile) -> bool:
	if not producer_upgrade_error(profile).is_empty():
		return false
	profile.facility_parts -= PRODUCER_UPGRADE_COST
	profile.producer_upgraded = true
	return true
