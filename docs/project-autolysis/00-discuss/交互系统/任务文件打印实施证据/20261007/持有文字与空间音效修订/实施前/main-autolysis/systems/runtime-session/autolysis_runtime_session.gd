extends Node

var _telephone_test_consumed: bool = false


func consume_telephone_test_once() -> bool:
	if _telephone_test_consumed:
		return false
	_telephone_test_consumed = true
	return true


func is_telephone_test_consumed() -> bool:
	return _telephone_test_consumed
