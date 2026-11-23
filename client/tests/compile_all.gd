## Loads every GDScript inside the real runtime (autoloads present) and fails on any parse/compile
## error or warning-as-error. Run: godot --headless --path client res://tests/compile_all.tscn
extends Node


class ErrorCounter:
	extends Logger
	var errors: PackedStringArray = []
	var _m := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_m.lock()
		errors.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_m.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _ready() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var files: PackedStringArray = []
	_collect("res://", files)
	var failed := 0
	for f: String in files:
		var before := counter.errors.size()
		var s: Variant = ResourceLoader.load(f)
		if s == null or counter.errors.size() > before or not (s as GDScript).can_instantiate():
			failed += 1
			printerr("✗ %s" % f)
			for i: int in range(before, counter.errors.size()):
				printerr("    %s" % counter.errors[i])
	print("%d scripts, %d failed" % [files.size(), failed])
	OS.remove_logger(counter)
	get_tree().quit(1 if failed > 0 else 0)


func _collect(dir: String, out: PackedStringArray) -> void:
	for d: String in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or (dir == "res://" and d in ["build"]):
			continue
		_collect(dir.path_join(d), out)
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") and not (dir.begins_with("res://addons/bp_tools") and f.begins_with("build_")) and f != "generate_theme.gd" and f != "compile_all.gd":
			out.append(dir.path_join(f))
