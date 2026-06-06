## NarrativePromptBuilder 冒烟测试（`godot --headless -s tests/narrative_prompt_builder_test.gd`）
extends SceneTree

const NarrativePromptBuilderScript := preload(
	"res://src/game/logic/narrative/narrative_prompt_builder.gd"
)
const NarrativeTurnParserScript := preload(
	"res://src/game/logic/narrative/narrative_turn_parser.gd"
)
const RuntimeStateServiceScript := preload("res://src/game/logic/state/runtime_state_service.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_system_prompt_includes_dynamic_add()
	failed += _test_system_prompt_includes_tool_protocol()
	failed += _test_trim_preserves_system()
	failed += _test_trim_char_budget()
	failed += _test_unified_json_story_text_only()
	failed += _test_update_last_assistant_story()
	failed += _test_snapshot_region_budget()
	if failed == 0:
		print("[OK] narrative_prompt_builder tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_system_prompt_includes_dynamic_add() -> int:
	var snap := {"protagonist_name": "测试", "regions": []}
	var prompt := NarrativePromptBuilderScript.build_system_prompt(snap)
	if prompt.is_empty():
		push_error("build_system_prompt: empty")
		return 1
	if "[[DYN_ADD:" not in prompt:
		push_error("build_system_prompt: missing DYN_ADD registration")
		return 1
	if "纯 JSON" not in prompt:
		push_error("build_system_prompt: missing common JSON output rules")
		return 1
	if "dynamic_add" not in prompt.to_lower() and "动态" not in prompt:
		push_error("build_system_prompt: missing dynamic_add section hint")
		return 1
	return 0


func _test_system_prompt_includes_tool_protocol() -> int:
	var snap := {"protagonist_name": "测试", "regions": []}
	var prompt := NarrativePromptBuilderScript.build_system_prompt(snap)
	if prompt.find("tool_requests") < 0:
		push_error("build_system_prompt: missing tool_requests protocol")
		return 1
	if prompt.find("禁止") < 0 and prompt.find("不得伪造") < 0:
		push_error("build_system_prompt: missing tool hard constraints")
		return 1
	return 0


func _test_trim_preserves_system() -> int:
	var system := {"role": "system", "content": "SYS_PROMPT"}
	var messages: Array = [system]
	for i in range(25):
		messages.append({"role": "user" if i % 2 == 0 else "assistant", "content": "x".repeat(50)})

	var trimmed := NarrativePromptBuilderScript.trim_messages(messages)
	if trimmed.is_empty():
		push_error("trim_messages: empty result")
		return 1
	if str(trimmed[0].get("role", "")) != "system":
		push_error("trim_messages: system message not first")
		return 1
	if str(trimmed[0].get("content", "")) != "SYS_PROMPT":
		push_error("trim_messages: system content changed")
		return 1
	if trimmed.size() > NarrativePromptBuilderScript.MAX_HISTORY_MESSAGES + 1:
		push_error("trim_messages: too many messages after trim")
		return 1
	return 0


func _test_trim_char_budget() -> int:
	var messages: Array = [{"role": "system", "content": "s"}]
	for i in range(30):
		messages.append({"role": "assistant", "content": "y".repeat(2000)})

	var trimmed := NarrativePromptBuilderScript.trim_messages(messages)
	var total := 0
	for i in range(1, trimmed.size()):
		total += str(trimmed[i].get("content", "")).length()
	if total > NarrativePromptBuilderScript.MAX_HISTORY_CHARS + 2000:
		push_error("trim_messages: char budget exceeded badly: %d" % total)
		return 1
	return 0


func _test_unified_json_story_text_only() -> int:
	var payload := (
		'{"story_text":"雨夜。","datetime_display":"秋 周三 12:00","weather":"阴",'
		+ '"current_region_id":"r1","current_key_node_id":""}'
	)
	var text := NarrativeTurnParserScript.story_text_only(payload)
	if text != "雨夜。":
		push_error("story_text_only unified: expected 雨夜。, got %s" % text)
		return 1
	var marker_text := "叙事正文\n---STATE_HOOK---\n{\"weather\":\"晴\"}\n---END_STATE_HOOK---"
	var stripped := NarrativeTurnParserScript.story_text_only(marker_text)
	if stripped != "叙事正文":
		push_error("story_text_only marker: got %s" % stripped)
		return 1
	return 0


func _test_update_last_assistant_story() -> int:
	var svc := RuntimeStateServiceScript.new()
	svc._game_state = {
		"story_log": [
			{"role": "user", "content": "行动"},
			{"role": "assistant", "content": "[[DYN_ADD:物品|旧]]"},
		],
	}
	if not svc.update_last_assistant_story_content("【手电筒】"):
		push_error("update_last_assistant_story_content: failed")
		return 1
	var log: Array = svc.get_story_log()
	if str(log[-1].get("content", "")) != "【手电筒】":
		push_error("update_last_assistant_story_content: content not updated")
		return 1
	return 0


func _test_snapshot_region_budget() -> int:
	var rm := ReadModelScript.new()
	rm.mainrole = {"current_region_id": "r_center", "current_key_node_id": ""}
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "r_center", "name": "中心", "adjacent_region_ids": ["r_north"]},
				{"id": "r_north", "name": "北"},
				{"id": "r_far", "name": "远"},
			],
			"key_nodes": [
				{"id": "kn1", "name": "酒馆", "region_id": "r_center"},
				{"id": "kn2", "name": "码头", "region_id": "r_far"},
			],
		},
	}
	rm.game_state = {"unlocked_region_ids": ["r_center"]}
	var snap := rm.build_narrative_snapshot("", {})
	var regions: Array = snap.get("regions", [])
	var region_ids: Dictionary = {}
	for r in regions:
		if r is Dictionary:
			region_ids[str(r.get("id", ""))] = true
	if region_ids.has("r_far"):
		push_error("snapshot: r_far should be filtered out")
		return 1
	if not region_ids.has("r_center"):
		push_error("snapshot: missing current region")
		return 1
	var nodes: Array = snap.get("key_nodes", [])
	for n in nodes:
		if n is Dictionary and str(n.get("region_id", "")) == "r_far":
			push_error("snapshot: key_node from far region should be filtered")
			return 1
	return 0
