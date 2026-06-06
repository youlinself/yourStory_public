## 回合工具编排（`godot --headless -s tests/turn_tool_coordinator_test.gd`）
extends SceneTree

const RegistryScript := preload("res://src/game/logic/narrative/turn_tool_registry.gd")
const UiSanitizeScript := preload("res://src/game/logic/narrative/turn_tool_ui_sanitize.gd")
const StateHookScript := preload("res://src/game/logic/narrative/turn_tool_state_hook.gd")
const NarrativeTurnParserScript := preload(
	"res://src/game/logic/narrative/narrative_turn_parser.gd"
)
const NarrativePromptBuilderScript := preload(
	"res://src/game/logic/narrative/narrative_prompt_builder.gd"
)
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_normalize_request()
	failed += _test_collect_legacy_dyn_add()
	failed += _test_ui_sanitize_strips_bbcode()
	failed += _test_parse_tool_requests_json()
	failed += _test_prompt_includes_tool_protocol()
	failed += _test_state_hook_unknown_item()
	if failed == 0:
		print("[OK] turn_tool_coordinator tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_normalize_request() -> int:
	var req := RegistryScript.normalize_request({
		"tool": "dynamic_add",
		"args": {"category": "NPC", "source_context": "证人"},
		"reason": "新人物",
	})
	if str(req.get("tool", "")) != RegistryScript.TOOL_DYNAMIC_ADD:
		push_error("normalize_request: tool mismatch")
		return 1
	if RegistryScript.normalize_request({"tool": "invalid"}).is_empty():
		pass
	else:
		push_error("normalize_request: should reject invalid tool")
		return 1
	return 0


func _test_collect_legacy_dyn_add() -> int:
	var story := "他递来一物。[[DYN_ADD:物品|旧药瓶]]"
	var parsed := {"tool_requests": []}
	var collected: Array = RegistryScript.collect_requests(parsed, story)
	if collected.is_empty():
		push_error("collect_requests: expected legacy DYN_ADD request")
		return 1
	if str(collected[0].get("tool", "")) != RegistryScript.TOOL_DYNAMIC_ADD:
		push_error("collect_requests: wrong tool for legacy marker")
		return 1
	return 0


func _test_ui_sanitize_strips_bbcode() -> int:
	var out := UiSanitizeScript.sanitize_story_text("结果：[Color=red]失败[/Color]")
	if "[Color" in out or "[color" in out:
		push_error("ui sanitize should strip color tags: %s" % out)
		return 1
	if "失败" not in out:
		push_error("ui sanitize should keep inner text")
		return 1
	return 0


func _test_parse_tool_requests_json() -> int:
	var payload := (
		'{"story_text":"雨夜。","tool_requests":[{"tool":"ui_text_sanitize","args":{}}],'
		+ '"datetime_display":"秋","weather":"阴","current_region_id":"r1"}'
	)
	var parsed := NarrativeTurnParserScript.parse_from_api_response({
		"choices": [{"message": {"content": payload}}],
	})
	if not parsed.get("parse_ok", false):
		push_error("parse tool_requests: parse_ok false")
		return 1
	var reqs: Variant = parsed.get("tool_requests", [])
	if not reqs is Array or reqs.is_empty():
		push_error("parse tool_requests: missing array")
		return 1
	return 0


func _test_prompt_includes_tool_protocol() -> int:
	var prompt := NarrativePromptBuilderScript.build_system_prompt({"regions": []})
	if prompt.find("tool_requests") < 0:
		push_error("system prompt should mention tool_requests")
		return 1
	if prompt.find("禁止") < 0 or prompt.find("BBCode") < 0:
		push_error("system prompt should forbid BBCode")
		return 1
	if RegistryScript.build_protocol_prompt().find("dynamic_add") < 0:
		push_error("protocol prompt missing dynamic_add")
		return 1
	return 0


func _test_state_hook_unknown_item() -> int:
	var rm := ReadModelScript.new()
	rm.mainrole = {"id": "hero"}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.map_db = {"map_structure": {"regions": [], "key_nodes": []}}
	rm.npc_db = {"npcs": {}}
	var preview := StateHookScript.preview_hook(
		{
			"datetime_display": "春",
			"weather": "晴",
			"inventory_delta": [{"id": "unknown_item_xyz", "op": "add", "qty": 1}],
		},
		rm,
		rm.game_state,
	)
	var warnings: Variant = preview.get("warnings", [])
	if warnings is PackedStringArray and warnings.is_empty():
		push_error("state_hook should warn on unknown item id")
		return 1
	return 0
