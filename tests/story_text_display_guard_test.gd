## 玩家叙述展示层净化（`godot --headless -s tests/story_text_display_guard_test.gd`）
extends SceneTree

const GuardScript := preload("res://src/game/logic/narrative/story_text_display_guard.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_json_leak_extracts_story_text()
	failed += _test_plain_narrative_unchanged()
	failed += _test_unparseable_json_returns_empty()
	failed += _test_json_without_hook_fields()
	failed += _test_fallback_raw_extraction()
	if failed == 0:
		print("[OK] story_text_display_guard tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_json_leak_extracts_story_text() -> int:
	var payload := (
		'{"story_text":"深秋暮色里，苏霍贴着断墙根前行。","tool_requests":[],"'
		+ '"present_npc_ids":[],"datetime_display":"深秋 / 黄昏","weather":"湿冷薄雾",'
		+ '"current_region_id":"region_inner_city","current_key_node_id":"node_ruin_market",'
		+ '"suggestions":["观察周围环境"]}'
	)
	var out := GuardScript.coerce_player_narrative(payload)
	if "深秋暮色里" not in out:
		push_error("json leak: expected story_text body, got %s" % out)
		return 1
	if "tool_requests" in out or out.begins_with("{"):
		push_error("json leak: should not expose JSON structure: %s" % out)
		return 1
	return 0


func _test_plain_narrative_unchanged() -> int:
	var plain := "雨雾贴着广场的青石砖面缓缓流动。"
	var out := GuardScript.coerce_player_narrative(plain)
	if out != plain:
		push_error("plain narrative: expected unchanged, got %s" % out)
		return 1
	return 0


func _test_unparseable_json_returns_empty() -> int:
	var broken := '{"story_text":未闭合'
	var out := GuardScript.coerce_player_narrative(broken)
	if not out.is_empty():
		push_error("unparseable json: expected empty, got %s" % out)
		return 1
	return 0


func _test_json_without_hook_fields() -> int:
	var payload := '{"story_text":"巷口风更冷了。","suggestions":["整理装备"]}'
	var out := GuardScript.coerce_player_narrative(payload)
	if out != "巷口风更冷了。":
		push_error("json without hook: expected story_text only, got %s" % out)
		return 1
	return 0


func _test_fallback_raw_extraction() -> int:
	var display := ""
	var raw := '{"story_text":"从 fallback 提取的叙事。","tool_requests":[]}'
	var out := GuardScript.coerce_player_narrative(display, raw)
	if out != "从 fallback 提取的叙事。":
		push_error("fallback raw: expected extracted story, got %s" % out)
		return 1
	return 0
