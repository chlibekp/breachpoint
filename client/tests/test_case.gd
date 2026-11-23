## Base class for client unit tests. Methods named test_* are run by run_tests.gd.
class_name TestCase
extends RefCounted

var failures := PackedStringArray()
var _current: String = ""


func check(cond: bool, message: String) -> void:
	if not cond:
		failures.append("%s: %s" % [_current, message])


func check_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s: %s expected %s, got %s" % [_current, message, str(expected), str(actual)])


func check_near(actual: float, expected: float, tolerance: float, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: %s expected %f ± %f, got %f" % [_current, message, expected, tolerance, actual])


func begin(test_name: String) -> void:
	_current = test_name
