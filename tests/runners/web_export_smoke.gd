extends SceneTree

const EXPORT_PRESET_PATH: String = "res://export_presets.cfg"
const WORKFLOW_PATH: String = "res://.github/workflows/deploy-pages.yml"
const WEB_DIRECTORY: String = "res://web"
const PROJECT_PATH: String = "res://project.godot"
const UI_FONT_PATH: String = "res://assets/fonts/NotoSansKR-UI.tres"
const BUNDLED_FONT_PATH: String = "res://assets/fonts/NotoSansKR-wght.fontdata"
const FONT_LICENSE_PATH: String = "res://assets/fonts/OFL.txt"
const REQUIRED_WEB_FILES: Array[String] = [
	"index.html",
	"index.js",
	"index.pck",
	"index.wasm",
]
const ACCEPTED_EVIDENCE_HASHES: Dictionary = {
	"res://_workspace/desktop-horror-prototype/evidence/task-000-bootstrap/compact.png": "c86c1c1f5aa15252ac768d864117914541a1f2c988dbdf2c8d5c3bb3d2787821",
	"res://_workspace/desktop-horror-prototype/evidence/task-000-bootstrap/expanded.png": "8c326318132104c2f43282f9e3fd12b6a84699ef41a3d304cd9351ed57af0732",
	"res://_workspace/desktop-horror-prototype/evidence/task-010-home-clock-save/compact.png": "7937f6925545da159b0281b575631a8e2909ad81c2cace60ba80efe8f457a312",
	"res://_workspace/desktop-horror-prototype/evidence/task-010-home-clock-save/expanded.png": "cadc0bcefc210a58048e7e3196c6b50fa5998166887482a9a30b6c7b8bee7564",
	"res://_workspace/desktop-horror-prototype/evidence/task-020-departure-movement-route/field-blackout.png": "af5bb691901d1e6e943f1dc8e94da6ea9bab94981b3e656fefa7849f1389606b",
	"res://_workspace/desktop-horror-prototype/evidence/task-020-departure-movement-route/field-normal.png": "9f20fbfbbaae287dd23c4dea3d81cece2af120084f56d204d9a20eab1fde9986",
	"res://_workspace/desktop-horror-prototype/evidence/task-020-departure-movement-route/home-preparation.png": "8040ffd1834e7bdfd774b4d794d96c5addbe840b1696693c563b4b0b92d34e40",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/blackout-no-flashlight.png": "39371e2818dc8fe3e2bc1204ced30b8d78d9c14a76d7fa381787aab21d40a50b",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/fuse-restored.png": "df51bd186a02fff12bea731fad6ba891b04dfcfe6151873dca89c408a35813a8",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/item-choice.png": "bdf1eb524e30155509d0f85c8f110a8b8432ddd2acdc30264ba23c9b8dd0d457",
	"res://_workspace/desktop-horror-prototype/evidence/task-030-search-tools-blackout/object-choice.png": "436bbf76cd8f41dd989402e363cab3f9b58636bf4070e728f2559d7864037918",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/chasing.png": "4794261310986f42ceffdb1f37a7d7db2b57672429cf099bc742e57911d24046",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/hide-resolved.png": "056339e17efc80aaaab5f6a9d3536edcf8228f79a34c5cc3f0ea9fbd1949aa8c",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/rescued-home.png": "0e4bd6c521b010cdda59d74a9e0d33a8fcbb9f0b7ecd08e50a5ee0bfa307e168",
	"res://_workspace/desktop-horror-prototype/evidence/task-040-chase-hide-rescue/warning.png": "aeaf6bc7b68936b69957e31f93bef04d8744755cb180b44bcdfd592fc9b5f2ca",
	"res://_workspace/desktop-horror-prototype/evidence/task-050-extraction-upgrade-loop/early-extraction.png": "71d5cf3005363ec4681f2b85b0cee540fa6457e3175011dcaa47728d18c42b7e",
	"res://_workspace/desktop-horror-prototype/evidence/task-050-extraction-upgrade-loop/endpoint-extraction.png": "15ad9e2e9268a8c862365b94af061da1ef2335acfaa0eb4e5973e339637a731d",
	"res://_workspace/desktop-horror-prototype/evidence/task-050-extraction-upgrade-loop/second-departure.png": "b1b93dbee38ab2fb00b2f672ca7f803b6eb28f870e3e88102d977a34a9fbcf58",
	"res://_workspace/desktop-horror-prototype/evidence/task-050-extraction-upgrade-loop/upgraded-home.png": "dea230fe7bde4817053dd69425ef9a8568169cee21bd4c5c89eab7f1f67842ab",
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_export_preset()
	_test_bundled_font()
	_test_web_build()
	_test_pages_workflow()
	_test_accepted_evidence()
	_finish()


func _test_export_preset() -> void:
	var source: String = _read_text(EXPORT_PRESET_PATH)
	_check(source.contains('name="Web"'), "export preset exposes the exact Web name")
	_check(source.contains('platform="Web"'), "export preset targets Web")
	_check(source.contains('variant/thread_support=false'), "Web build explicitly disables thread support")
	_check(source.contains('variant/extensions_support=false'), "Web build has no extension dependency")
	_check(source.contains('html/canvas_resize_policy=2'), "canvas follows browser size while project keeps logical viewport")
	_check(source.contains('progressive_web_app/enabled=false'), "no service worker or stale PWA cache is introduced")
	_check(source.contains('export_path="web/index.html"'), "preset output is the committed Web directory")
	for excluded: String in [".agents/*", ".github/*", "_workspace/*", "concepts/*", "docs/*", "tests/*", "web/*"]:
		_check(source.contains(excluded), "export excludes non-runtime path %s" % excluded)


func _test_bundled_font() -> void:
	var project_source: String = _read_text(PROJECT_PATH)
	_check(project_source.contains('theme/custom_font="%s"' % UI_FONT_PATH), "project uses the portable bundled UI font variation")
	_check(FileAccess.file_exists(UI_FONT_PATH), "bundled UI font variation exists")
	_check(FileAccess.file_exists(BUNDLED_FONT_PATH), "bundled UI font exists")
	_check(FileAccess.get_file_as_bytes(BUNDLED_FONT_PATH).size() > 1000000, "bundled UI font is non-empty and includes the Korean family")
	var font: Font = load(BUNDLED_FONT_PATH) as Font
	_check(font != null, "bundled UI font loads as a Godot Font resource")
	if font != null:
		for character: String in ["한", "국", "입", "구", "종", "착", "점"]:
			_check(font.has_char(character.unicode_at(0)), "bundled UI font contains Korean glyph %s" % character)
	var license_source: String = _read_text(FONT_LICENSE_PATH)
	_check(license_source.contains("SIL OPEN FONT LICENSE Version 1.1"), "bundled UI font includes its OFL 1.1 license")
	_check(license_source.contains("Reserved Font Name 'Source'"), "bundled license retains the upstream reserved-font notice")


func _test_web_build() -> void:
	for file_name: String in REQUIRED_WEB_FILES:
		var path: String = "%s/%s" % [WEB_DIRECTORY, file_name]
		_check(FileAccess.file_exists(path), "Web build file exists: %s" % file_name)
		if FileAccess.file_exists(path):
			_check(FileAccess.get_file_as_bytes(path).size() > 0, "Web build file is non-empty: %s" % file_name)
	var html: String = _read_text("%s/index.html" % WEB_DIRECTORY)
	_check(html.contains('src="index.js"'), "HTML loads the relative Godot JavaScript loader")
	_check(html.contains('"executable":"index"'), "HTML config resolves pck/wasm beside index by relative executable name")
	_check(not html.contains('src="/index.js"'), "HTML has no domain-root loader path")
	_check(not html.contains('<base href="/'), "HTML has no root base URL that breaks a Pages project subpath")
	_check(not FileAccess.file_exists("%s/coi-serviceworker.js" % WEB_DIRECTORY), "no-threads build needs no cross-origin service worker")
	_check(FileAccess.get_file_as_bytes("%s/index.pck" % WEB_DIRECTORY).size() > 1000000, "Web resource pack includes the bundled Korean font")
	for forbidden_name: String in ["tests", "docs", "concepts", "_workspace", ".agents", ".github"]:
		_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("%s/%s" % [WEB_DIRECTORY, forbidden_name])), "site root excludes source path %s" % forbidden_name)


func _test_pages_workflow() -> void:
	var source: String = _read_text(WORKFLOW_PATH)
	_check(source.contains("branches:\n      - main"), "Pages workflow deploys from main")
	_check(source.contains("pages: write") and source.contains("id-token: write"), "Pages workflow has only required deployment permissions")
	_check(source.contains("actions/checkout@v7"), "Pages workflow checks out the committed build")
	_check(source.contains("actions/configure-pages@v6"), "Pages workflow configures project metadata")
	_check(source.contains("actions/upload-pages-artifact@v5"), "Pages workflow uploads a Pages artifact")
	_check(source.contains("path: ./web"), "Pages artifact contains only the Web build directory")
	_check(source.contains("actions/deploy-pages@v5"), "Pages workflow deploys the uploaded artifact")
	for forbidden: String in ["secrets.", "/Users/", "_workspace/", "tests/", "docs/", "concepts/"]:
		_check(not source.contains(forbidden), "workflow contains no forbidden machine/source token: %s" % forbidden)


func _test_accepted_evidence() -> void:
	for path: String in ACCEPTED_EVIDENCE_HASHES:
		_check(FileAccess.file_exists(path), "accepted evidence still exists: %s" % path)
		if FileAccess.file_exists(path):
			_check(FileAccess.get_sha256(path) == ACCEPTED_EVIDENCE_HASHES[path], "accepted evidence hash remains unchanged: %s" % path)


func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		_fail("required text file does not exist: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_fail(message)


func _fail(message: String) -> void:
	_failures.append(message)
	printerr("WEB_EXPORT_FAILURE: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("WEB_EXPORT_PASS")
		quit(0)
		return
	printerr("WEB_EXPORT_FAIL count=%d" % _failures.size())
	quit(1)
