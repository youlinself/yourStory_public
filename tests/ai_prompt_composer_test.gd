## AiPromptComposer 单元测试（`godot --headless -s tests/ai_prompt_composer_test.gd`）
extends SceneTree

const ComposerScript := preload("res://src/ai_config/ai_prompt_composer.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_wrap_json_task_structure()
	failed += _test_wrap_json_task_system_contains_rules()
	failed += _test_merge_into_system_existing()
	failed += _test_merge_into_system_insert()
	failed += _test_prepend_json_rules()
	if failed == 0:
		print("[OK] ai_prompt_composer tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_wrap_json_task_structure() -> int:
	var messages: Array = ComposerScript.wrap_json_task("任务正文")
	if messages.size() != 2:
		push_error("wrap_json_task: expected 2 messages")
		return 1
	if str(messages[0].get("role", "")) != "system":
		push_error("wrap_json_task: first role should be system")
		return 1
	if str(messages[1].get("role", "")) != "user":
		push_error("wrap_json_task: second role should be user")
		return 1
	if str(messages[1].get("content", "")) != "任务正文":
		push_error("wrap_json_task: user content mismatch")
		return 1
	return 0


func _test_wrap_json_task_system_contains_rules() -> int:
	var messages: Array = ComposerScript.wrap_json_task("x")
	var system_text := str(messages[0].get("content", ""))
	if "纯 JSON" not in system_text or "Markdown 围栏" not in system_text:
		push_error("wrap_json_task: system missing JSON rules keywords")
		return 1
	return 0


func _test_merge_into_system_existing() -> int:
	var input: Array = [
		{"role": "system", "content": "已有 system"},
		{"role": "user", "content": "hi"},
	]
	var out: Array = ComposerScript.merge_into_system(input, "追加段")
	if out.size() != 2:
		push_error("merge_into_system: expected 2 messages")
		return 1
	var merged := str(out[0].get("content", ""))
	if "已有 system" not in merged or "追加段" not in merged:
		push_error("merge_into_system: merge content wrong")
		return 1
	return 0


func _test_merge_into_system_insert() -> int:
	var input: Array = [{"role": "user", "content": "hi"}]
	var out: Array = ComposerScript.merge_into_system(input, "新 system")
	if out.size() != 2:
		push_error("merge_into_system insert: expected 2 messages")
		return 1
	if str(out[0].get("role", "")) != "system":
		push_error("merge_into_system insert: first should be system")
		return 1
	return 0


func _test_prepend_json_rules() -> int:
	var out := ComposerScript.prepend_json_rules_to_system("业务 system")
	if "业务 system" not in out or "纯 JSON" not in out:
		push_error("prepend_json_rules_to_system: expected rules + body")
		return 1
	return 0
