class_name HomeProfile
extends RefCounted

const SCHEMA_VERSION: int = 1
const BASE_INTERVAL_MS: int = 12 * 60 * 1000
const UPGRADED_INTERVAL_MS: int = 8 * 60 * 1000
const BASE_CAPACITY: int = 2
const UPGRADED_CAPACITY: int = 3
const REQUIRED_FIELDS: Array[String] = [
	"schema_version",
	"departure_supply_units",
	"facility_parts",
	"producer_upgraded",
	"last_saved_unix_ms",
]

var departure_supply_units: float
var facility_parts: int
var producer_upgraded: bool
var last_saved_unix_ms: int


func _init(
	initial_supply_units: float = float(BASE_CAPACITY),
	initial_facility_parts: int = 0,
	initial_producer_upgraded: bool = false,
	initial_last_saved_unix_ms: int = 0
) -> void:
	departure_supply_units = initial_supply_units
	facility_parts = initial_facility_parts
	producer_upgraded = initial_producer_upgraded
	last_saved_unix_ms = initial_last_saved_unix_ms


static func create_new(now_unix_ms: int) -> HomeProfile:
	return HomeProfile.new(float(BASE_CAPACITY), 0, false, now_unix_ms)


static func document_error(document: Dictionary) -> String:
	if not document.has("schema_version"):
		return "missing required field: schema_version"
	if not _is_number(document["schema_version"]):
		return "schema_version must be numeric"
	if not _is_whole_number(document["schema_version"]):
		return "schema_version must be an integer"

	var schema_version: int = int(document["schema_version"])
	if schema_version > SCHEMA_VERSION:
		return "unsupported schema_version: %d" % schema_version
	if schema_version != SCHEMA_VERSION:
		return "invalid schema_version: %d" % schema_version

	for field_name: String in REQUIRED_FIELDS:
		if not document.has(field_name):
			return "missing required field: %s" % field_name

	if document.size() != REQUIRED_FIELDS.size():
		return "schema v1 document contains unexpected fields"

	if not _is_number(document["departure_supply_units"]):
		return "departure_supply_units must be numeric"
	if not _is_number(document["facility_parts"]):
		return "facility_parts must be numeric"
	if not _is_whole_number(document["facility_parts"]):
		return "facility_parts must be an integer"
	if typeof(document["producer_upgraded"]) != TYPE_BOOL:
		return "producer_upgraded must be boolean"
	if not _is_number(document["last_saved_unix_ms"]):
		return "last_saved_unix_ms must be numeric"
	if not _is_whole_number(document["last_saved_unix_ms"]):
		return "last_saved_unix_ms must be an integer"

	var upgraded: bool = bool(document["producer_upgraded"])
	var capacity: int = UPGRADED_CAPACITY if upgraded else BASE_CAPACITY
	var supply_units: float = float(document["departure_supply_units"])
	var parts: int = int(document["facility_parts"])
	var saved_at: int = int(document["last_saved_unix_ms"])
	if supply_units < 0.0 or supply_units > float(capacity):
		return "departure_supply_units is outside the current capacity"
	if parts < 0:
		return "facility_parts cannot be negative"
	if saved_at < 0:
		return "last_saved_unix_ms cannot be negative"

	return ""


static func from_document(document: Dictionary) -> HomeProfile:
	if not document_error(document).is_empty():
		return null

	return HomeProfile.new(
		float(document["departure_supply_units"]),
		int(document["facility_parts"]),
		bool(document["producer_upgraded"]),
		int(document["last_saved_unix_ms"])
	)


func to_document() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"departure_supply_units": departure_supply_units,
		"facility_parts": facility_parts,
		"producer_upgraded": producer_upgraded,
		"last_saved_unix_ms": last_saved_unix_ms,
	}


func accrue_supply(now_unix_ms: int) -> void:
	if now_unix_ms <= last_saved_unix_ms:
		return

	var elapsed_ms: int = now_unix_ms - last_saved_unix_ms
	var capacity: int = supply_capacity()
	if departure_supply_units >= float(capacity):
		departure_supply_units = float(capacity)
		last_saved_unix_ms = now_unix_ms
		return

	var produced_units: float = float(elapsed_ms) / float(production_interval_ms())
	departure_supply_units = minf(float(capacity), departure_supply_units + produced_units)
	last_saved_unix_ms = now_unix_ms


func production_interval_ms() -> int:
	return UPGRADED_INTERVAL_MS if producer_upgraded else BASE_INTERVAL_MS


func supply_capacity() -> int:
	return UPGRADED_CAPACITY if producer_upgraded else BASE_CAPACITY


func available_supply_units() -> int:
	return mini(int(floor(departure_supply_units + 0.000001)), supply_capacity())


func consume_departure_supply() -> bool:
	if available_supply_units() < 1:
		return false
	departure_supply_units -= 1.0
	return true


func production_progress() -> float:
	if departure_supply_units >= float(supply_capacity()):
		return 1.0
	return departure_supply_units - floor(departure_supply_units)


func milliseconds_until_next_supply() -> int:
	if departure_supply_units >= float(supply_capacity()):
		return 0
	return int(ceil((1.0 - production_progress()) * float(production_interval_ms())))


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_whole_number(value: Variant) -> bool:
	return is_equal_approx(float(value), float(int(value)))
