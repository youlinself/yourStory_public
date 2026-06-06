## is_retriable_failure（`godot --headless -s tests/game_world_initializer_retriable_test.gd`）
extends SceneTree


func _initialize() -> void:
	var failed := 0
	failed += _test_stage2_validation_is_retriable()
	failed += _test_port_invalid_not_retriable()
	failed += _test_timeout_is_retriable()
	failed += _test_describe_skills_missing_field()
	if failed == 0:
		print("[OK] game_world_initializer retriable tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_stage2_validation_is_retriable() -> int:
	var reason := "阶段 2 AI 返回的 JSON 缺少顶层 skills 字段"
	if not GameWorldInitializer.is_retriable_failure(reason, AIClient.HTTP_RESULT_NONE):
		push_error("stage2 validation should be retriable")
		return 1
	return 0


func _test_port_invalid_not_retriable() -> int:
	if GameWorldInitializer.is_retriable_failure("后端端口无效", AIClient.HTTP_RESULT_NONE):
		push_error("port invalid should not be retriable")
		return 1
	return 0


func _test_timeout_is_retriable() -> int:
	if not GameWorldInitializer.is_retriable_failure("任意", HTTPRequest.RESULT_TIMEOUT):
		push_error("timeout should be retriable")
		return 1
	return 0


func _test_describe_skills_missing_field() -> int:
	var msg := AiResponseParser.describe_skills_validation_failure({"novel_type": "x"}, true)
	if not msg.contains("skills"):
		push_error("describe_skills: expected skills-related message, got: %s" % msg)
		return 1
	return 0
