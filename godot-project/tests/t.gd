# Assertion helpers shared by every suite.
#
# Two properties matter and both are learned the hard way, so they are enforced
# here rather than left to each suite:
#
#   1. A suite must print a "Result:" line. verify.sh asserts on that positive
#      signal, because grepping for "FAIL" reports a suite that died before its
#      assertions ran — parse error, crash, missing data — as passing.
#
#   2. finish() sets the process exit code, so a suite is also usable on its own
#      outside verify.sh without silently "succeeding".
class_name T

var _checks := 0
var _fails := 0
var _label := ""


func _init(label: String = "") -> void:
	_label = label


func ok(condition: bool, what: String) -> bool:
	_checks += 1
	if not condition:
		_fails += 1
		print("FAIL %s" % what)
	return condition


func eq(actual: Variant, expected: Variant, what: String) -> bool:
	_checks += 1
	if actual != expected:
		_fails += 1
		print("FAIL %s: expected %s, got %s" % [what, expected, actual])
		return false
	return true


## Float comparison with an explicit tolerance. There is no default epsilon on
## purpose: the right tolerance depends on what is being compared, and a
## borrowed one hides real drift.
func close(actual: float, expected: float, tol: float, what: String) -> bool:
	_checks += 1
	if absf(actual - expected) > tol:
		_fails += 1
		print("FAIL %s: expected %f +/- %f, got %f" % [what, expected, tol, actual])
		return false
	return true


func note(message: String) -> void:
	print("     %s" % message)


func checks() -> int:
	return _checks


func failures() -> int:
	return _fails


## Print the mandatory Result: line and return the exit code to quit() with.
func finish() -> int:
	var name := _label if not _label.is_empty() else "suite"
	print("Result: %s — %d checks, %d failures" % [name, _checks, _fails])
	return 1 if _fails > 0 else 0
