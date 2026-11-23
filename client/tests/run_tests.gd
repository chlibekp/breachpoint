## Headless test runner: godot --headless --path client -s res://tests/run_tests.gd
## Exits 1 on any failed check, script error or compile error (used by CI).
extends SceneTree

const SUITES: PackedStringArray = [
	"res://tests/test_protocol.gd",
	"res://tests/test_shared_config.gd",
	"res://tests/test_quality_manager.gd",
	"res://tests/test_json_schema.gd",
	"res://tests/test_sim_parity.gd",
	"res://tests/test_replay.gd",
]


## Counts engine/script errors so a test that crashes mid-way is reported as failed.
class ErrorCounter:
	extends Logger
	var count: int = 0
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		count += 1
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init() -> void:
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var total := 0
	var failed := 0
	for path: String in SUITES:
		var errors_before := errors.count
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate() or errors.count > errors_before:
			printerr("✗ %s failed to load/compile" % path)
			failed += 1
			total += 1
			continue
		var suite: TestCase = script.new()
		for method: Dictionary in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			var label := "%s::%s" % [path.get_file().get_basename(), method_name]
			var before := suite.failures.size()
			var err_before := errors.count
			suite.begin(label)
			suite.call(method_name)
			var crashed := errors.count > err_before
			if suite.failures.size() > before or crashed:
				failed += 1
				for i: int in range(before, suite.failures.size()):
					printerr("✗ %s" % suite.failures[i])
				if crashed:
					printerr("✗ %s: raised %d engine/script error(s)" % [label, errors.count - err_before])
			else:
				print("✓ %s" % label)
	print("\n%d tests, %d failed" % [total, failed])
	OS.remove_logger(errors)
	quit(1 if failed > 0 else 0)
