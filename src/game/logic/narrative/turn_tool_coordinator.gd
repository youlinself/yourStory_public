class_name TurnToolCoordinator
extends RefCounted

## 回合工具编排：解析 tool_requests、调用受控子模块、聚合结果，可选 AI 续写。

const MAX_TOOL_LOOPS := 2

const TurnToolRegistryScript := preload("res://src/game/logic/narrative/turn_tool_registry.gd")
const TurnToolDynamicAddScript := preload("res://src/game/logic/narrative/turn_tool_dynamic_add.gd")
const TurnToolActionCheckScript := preload("res://src/game/logic/narrative/turn_tool_action_check.gd")
const TurnToolStateHookScript := preload("res://src/game/logic/narrative/turn_tool_state_hook.gd")
const TurnToolUiSanitizeScript := preload("res://src/game/logic/narrative/turn_tool_ui_sanitize.gd")
const NarrativeHookNormalizerScript := preload(
	"res://src/game/logic/narrative/narrative_hook_normalizer.gd"
)
const NarrativeEntityGuardScript := preload(
	"res://src/game/logic/narrative/narrative_entity_guard.gd"
)
const NarrativeTurnParserScript := preload(
	"res://src/game/logic/narrative/narrative_turn_parser.gd"
)
const AiResponseParserScript := preload("res://src/novel_config/ai_response_parser.gd")


## ctx 字段：parsed, story_text, hook, pending_check, user_content, read_model, state_service,
## dynamic_add, messages, request_ai_callable (func(messages:Array)->Dictionary)
func resolve_turn_tools(ctx: Dictionary) -> Dictionary:
	var parsed: Dictionary = ctx.get("parsed", {}) if ctx.get("parsed") is Dictionary else {}
	var story_text := str(ctx.get("story_text", "")).strip_edges()
	var hook: Dictionary = ctx.get("hook", {}) if ctx.get("hook") is Dictionary else {}
	var pending_check: Dictionary = (
		ctx.get("pending_check", {}) if ctx.get("pending_check") is Dictionary else {}
	)
	var user_content := str(ctx.get("user_content", "")).strip_edges()
	var read_model: GameReadModel = ctx.get("read_model")
	var state_service: RuntimeStateService = ctx.get("state_service")
	var dynamic_add: DynamicAddService = ctx.get("dynamic_add")
	var messages: Array = ctx.get("messages", []) if ctx.get("messages") is Array else []
	var request_ai: Callable = ctx.get("request_ai_callable", Callable())

	var tool_results: Array = []
	var tool_warnings: PackedStringArray = []
	var dynamic_add_results: Array = []
	var dynamic_add_in_turn := false
	var auto_repair_applied := false

	var world_context := ""
	if read_model != null:
		world_context = JSON.stringify(read_model.base_config, "\t")

	var tool_requests: Array = TurnToolRegistryScript.collect_requests(parsed, story_text)

	# --- dynamic_add（含正文内 legacy 标记）---
	var dyn_requests: Array = _filter_tool_requests(tool_requests, TurnToolRegistryScript.TOOL_DYNAMIC_ADD)
	var dyn_out: Dictionary
	if not dyn_requests.is_empty():
		dyn_out = await TurnToolDynamicAddScript.run_requests(
			dynamic_add,
			dyn_requests,
			story_text,
			read_model,
			world_context,
		)
	else:
		dyn_out = await TurnToolDynamicAddScript.run_from_story(
			dynamic_add,
			story_text,
			read_model,
			world_context,
		)
	story_text = str(dyn_out.get("assistant_text", story_text)).strip_edges()
	_append_tool_results(tool_results, dyn_out.get("tool_results", []))
	_merge_dynamic_results(dynamic_add_results, dyn_out.get("dynamic_add_results", []))
	if dyn_out.get("ran", false):
		dynamic_add_in_turn = true

	var repair_results := await TurnToolDynamicAddScript.run_auto_repair(
		dynamic_add,
		story_text,
		read_model,
		world_context,
	)
	if not repair_results.is_empty():
		auto_repair_applied = true
		dynamic_add_in_turn = true
		_merge_dynamic_results(dynamic_add_results, repair_results)

	# --- action_check ---
	var check_out := TurnToolActionCheckScript.run_requests(
		_filter_tool_requests(tool_requests, TurnToolRegistryScript.TOOL_ACTION_CHECK),
		read_model,
		pending_check,
		user_content,
	)
	pending_check = check_out.get("check_result", pending_check)
	_append_tool_results(tool_results, check_out.get("tool_results", []))

	# --- state_hook preview ---
	var hook_requests := _filter_tool_requests(tool_requests, TurnToolRegistryScript.TOOL_STATE_HOOK)
	var hook_out: Dictionary
	if not hook_requests.is_empty():
		hook_out = TurnToolStateHookScript.run_requests(
			hook_requests,
			hook,
			read_model,
			state_service.get_game_state() if state_service != null else {},
		)
	else:
		hook_out = TurnToolStateHookScript.preview_hook(
			hook,
			read_model,
			state_service.get_game_state() if state_service != null else {},
		)
	hook = hook_out.get("hook", hook) if hook_out.get("hook") is Dictionary else hook
	var can_apply_hook: bool = hook_out.get("can_apply", false)
	_append_tool_results(tool_results, hook_out.get("tool_results", []))
	if hook_out.get("warnings") is PackedStringArray:
		for w in hook_out["warnings"]:
			tool_warnings.append(str(w))

	# --- ui sanitize ---
	var raw_suggestions: Array = []
	if parsed.get("suggestions") is Array:
		raw_suggestions = parsed["suggestions"]
	var ui_requests := _filter_tool_requests(tool_requests, TurnToolRegistryScript.TOOL_UI_TEXT_SANITIZE)
	var ui_out: Dictionary
	if not ui_requests.is_empty():
		ui_out = TurnToolUiSanitizeScript.run_requests(
			ui_requests,
			story_text,
			raw_suggestions,
			read_model,
		)
	else:
		ui_out = TurnToolUiSanitizeScript.run(story_text, raw_suggestions, read_model)
	story_text = str(ui_out.get("story_text", story_text)).strip_edges()
	var suggestions: Array = ui_out.get("suggestions", raw_suggestions)
	_append_tool_results(tool_results, ui_out.get("tool_results", []))

	for w in NarrativeEntityGuardScript.check_orphan_entities(story_text, read_model):
		tool_warnings.append(w)

	var needs_continuation := _should_request_continuation(tool_results, dynamic_add_in_turn)
	var continuation_loops := 0
	while needs_continuation and continuation_loops < MAX_TOOL_LOOPS - 1:
		if not request_ai.is_valid():
			break
		continuation_loops += 1
		var follow_messages: Array = messages.duplicate(true)
		follow_messages.append({
			"role": "user",
			"content": TurnToolRegistryScript.build_continuation_user_message(tool_results),
		})
		var api_response: Dictionary = await request_ai.call(follow_messages)
		if api_response.is_empty() or api_response.has("_error"):
			break
		var reparsed: Dictionary = NarrativeTurnParserScript.parse_from_api_response(api_response)
		var new_story := str(reparsed.get("story_text", "")).strip_edges()
		if new_story.is_empty():
			new_story = AiResponseParserScript.extract_message_content(api_response)
		if not new_story.is_empty():
			story_text = new_story
		if reparsed.get("hook") is Dictionary and not (reparsed["hook"] as Dictionary).is_empty():
			hook = reparsed["hook"]
		parsed = reparsed
		tool_requests = TurnToolRegistryScript.collect_requests(parsed, story_text)
		# 仅再跑 dynamic_add + ui（避免重复 state_hook 应用前校验）
		if not tool_requests.is_empty():
			var dyn2 := await TurnToolDynamicAddScript.run_requests(
				dynamic_add,
				_filter_tool_requests(tool_requests, TurnToolRegistryScript.TOOL_DYNAMIC_ADD),
				story_text,
				read_model,
				world_context,
			)
			story_text = str(dyn2.get("assistant_text", story_text)).strip_edges()
			_append_tool_results(tool_results, dyn2.get("tool_results", []))
			_merge_dynamic_results(dynamic_add_results, dyn2.get("dynamic_add_results", []))
		var ui2 := TurnToolUiSanitizeScript.run(story_text, parsed.get("suggestions", []), read_model)
		story_text = str(ui2.get("story_text", story_text)).strip_edges()
		suggestions = ui2.get("suggestions", suggestions)
		_append_tool_results(tool_results, ui2.get("tool_results", []))
		hook_out = TurnToolStateHookScript.preview_hook(
			hook,
			read_model,
			state_service.get_game_state() if state_service != null else {},
		)
		hook = hook_out.get("hook", hook)
		can_apply_hook = hook_out.get("can_apply", false)
		needs_continuation = false

	return {
		"story_text": story_text,
		"hook": hook,
		"can_apply_hook": can_apply_hook,
		"suggestions": suggestions,
		"check_result": pending_check,
		"tool_results": tool_results,
		"tool_warnings": tool_warnings,
		"dynamic_add_in_turn": dynamic_add_in_turn,
		"auto_repair_applied": auto_repair_applied,
		"dynamic_add_results": dynamic_add_results,
		"continuation_loops": continuation_loops,
	}


static func _filter_tool_requests(requests: Array, tool_name: String) -> Array:
	var out: Array = []
	for req in requests:
		if req is Dictionary and str(req.get("tool", "")) == tool_name:
			out.append(req)
	return out


static func _append_tool_results(target: Array, items: Variant) -> void:
	if not items is Array:
		return
	for item in items:
		if item is Dictionary:
			target.append(item)


static func _merge_dynamic_results(target: Array, items: Variant) -> void:
	if not items is Array:
		return
	for item in items:
		if item is Dictionary:
			target.append(item)


static func _should_request_continuation(tool_results: Array, dynamic_add_ran: bool) -> bool:
	if not dynamic_add_ran:
		return false
	for item in tool_results:
		if not item is Dictionary:
			continue
		if not item.get("ok", false):
			return true
	return false
