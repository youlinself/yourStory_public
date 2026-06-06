class_name NarrativeService
extends RefCounted

const NarrativeArchiveServiceScript := preload(
	"res://src/game/logic/narrative/narrative_archive_service.gd"
)
const LocationTravelPlannerScript := preload(
	"res://src/game/logic/world/location_travel_planner.gd"
)
const NarrativeHookNormalizerScript := preload(
	"res://src/game/logic/narrative/narrative_hook_normalizer.gd"
)
const ActionSuggestionBuilderScript := preload(
	"res://src/game/logic/narrative/action_suggestion_builder.gd"
)
const NarrativeEntityGuardScript := preload(
	"res://src/game/logic/narrative/narrative_entity_guard.gd"
)
const NarrativeEntityRepairScript := preload(
	"res://src/game/logic/narrative/narrative_entity_repair.gd"
)
const DynamicAddTriggerParserScript := preload(
	"res://src/ai_skills/dynamic_add_trigger_parser.gd"
)
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const ActionCheckPlannerScript := preload("res://src/game/logic/rules/action_check_planner.gd")
const TurnToolCoordinatorScript := preload(
	"res://src/game/logic/narrative/turn_tool_coordinator.gd"
)
const StoryTextDisplayGuardScript := preload(
	"res://src/game/logic/narrative/story_text_display_guard.gd"
)

var _ai_client: AIClient
var _dynamic_add: DynamicAddService
var _read_model := GameReadModel.new()
var _state_service := RuntimeStateService.new()
var _archive_service


func bind_ai_client(client: AIClient) -> void:
	_ai_client = client
	_archive_service = NarrativeArchiveServiceScript.new()
	_archive_service.bind_ai_client(client)


func bind_dynamic_add(service: DynamicAddService) -> void:
	_dynamic_add = service


func reload_runtime() -> void:
	_read_model.load_from_runtime()
	_state_service.load_from_runtime()


## hook 应用后：若旅行计划仍与主角位置不一致，按程序解析的目标强制更新。
func _reconcile_travel_location(plan: Dictionary, warning_prefix: String) -> Dictionary:
	var out := {"applied": false, "warnings": []}
	if not plan.get("needs_travel", false):
		return out
	var to_loc: Dictionary = plan.get("to_loc", {}) if plan.get("to_loc") is Dictionary else {}
	if to_loc.is_empty():
		return out
	if LocationServiceScript.is_same_place_from_role(_state_service.get_mainrole(), to_loc):
		return out
	var result: Dictionary = _state_service.apply_location_travel(
		to_loc,
		_read_model.get_region_ids(),
		_read_model,
	)
	if result.get("ok", false):
		out["applied"] = true
		reload_runtime()
	if result.get("warnings") is PackedStringArray:
		for w in result["warnings"]:
			out["warnings"].append("%s: %s" % [warning_prefix, w])
	return out


func _reconcile_map_cell_travel(plan: Dictionary) -> Dictionary:
	var out := {"applied": false, "warnings": []}
	if not plan.get("needs_travel", false):
		return out
	var to_loc: Dictionary = plan.get("to_loc", {}) if plan.get("to_loc") is Dictionary else {}
	if to_loc.is_empty():
		return out
	var page_id := str(plan.get("page_id", "")).strip_edges()
	var x := int(plan.get("x", -1))
	var y := int(plan.get("y", -1))
	var role := _state_service.get_mainrole()
	var same_loc := LocationServiceScript.is_same_place_from_role(role, to_loc)
	var same_cell := false
	if not page_id.is_empty() and x >= 0 and y >= 0:
		same_cell = LocationServiceScript.is_same_map_cell(_read_model, page_id, x, y)
	if same_loc and same_cell:
		return out
	var result: Dictionary = _state_service.apply_map_cell_travel(
		to_loc,
		page_id,
		x,
		y,
		_read_model.get_region_ids(),
		_read_model,
	)
	if result.get("ok", false):
		out["applied"] = true
		reload_runtime()
	if result.get("warnings") is PackedStringArray:
		for w in result["warnings"]:
			out["warnings"].append("地图位置兜底: %s" % w)
	return out


func needs_bootstrap() -> bool:
	_state_service.load_from_runtime()
	return not _state_service.has_story_log()


func submit_turn(player_text: String, map_travel: Dictionary = {}) -> Dictionary:
	var text := player_text.strip_edges()
	if text.is_empty():
		return _fail("请输入行动")
	var travel_ctx := map_travel.duplicate(true) if map_travel is Dictionary else {}
	return await _run_turn(text, true, travel_ctx)


func bootstrap_opening() -> Dictionary:
	reload_runtime()
	var snapshot := _read_model.build_narrative_snapshot("", {})
	var user_msg := NarrativePromptBuilder.bootstrap_user_message(snapshot)
	return await _run_turn(user_msg, false)


func _run_turn(user_content: String, append_user_to_story: bool, map_travel: Dictionary = {}) -> Dictionary:
	if _ai_client == null:
		return _fail("AI 客户端未绑定")

	reload_runtime()

	var archived := false
	var archive_title := ""
	var archive_warning := ""
	if _archive_service != null:
		var story_log := _state_service.get_story_log()
		var from_index := _state_service.get_last_archive_story_index()
		var chars_since: int = _state_service.get_chars_since_last_archive()
		var needs_archive := NarrativeArchiveServiceScript.should_archive_story(
			story_log,
			from_index,
			chars_since,
		)
		if needs_archive and NarrativeArchiveServiceScript.can_archive_pending(
			story_log,
			from_index,
			chars_since,
		):
			var archive_result: Dictionary = await _archive_service.archive_pending_context(
				_read_model,
				_state_service,
			)
			if archive_result.get("ok", false):
				archived = archive_result.get("archived", false)
				if archived:
					archive_title = str(archive_result.get("event_title", ""))
					reload_runtime()
				else:
					var err := str(archive_result.get("error", "")).strip_edges()
					if err.is_empty():
						err = "无法切分待归档内容"
					archive_warning = err
					push_warning("[NarrativeService] 归档未完成: %s" % archive_warning)
			else:
				archive_warning = str(archive_result.get("error", "归档失败"))
				push_warning("[NarrativeService] 归档跳过: %s" % archive_warning)
		elif needs_archive:
			archive_warning = "无法切分待归档内容"
			push_warning("[NarrativeService] 归档未完成: %s" % archive_warning)

	var state_for_recall := RuntimeStateService.new()
	state_for_recall.load_from_runtime()
	var pinned: Dictionary = state_for_recall.consume_pinned_recall_event()
	var query_for_snapshot := user_content if append_user_to_story else ""
	var pending_check: Dictionary = {}
	if append_user_to_story and not user_content.is_empty():
		pending_check = ActionCheckPlannerScript.plan_and_roll(user_content, _read_model)
	var snapshot := _read_model.build_narrative_snapshot(query_for_snapshot, pinned)
	if not pending_check.is_empty():
		snapshot["pending_check"] = pending_check
		snapshot["player_action"] = user_content
	var system_prompt := NarrativePromptBuilder.build_system_prompt(snapshot)
	if system_prompt.is_empty():
		return _fail("无法读取叙事模板（narrative_turn.md），请确认已完整导出 main.pck")

	var messages: Array = _state_service.get_narrative_messages()
	if messages.is_empty():
		messages.append({"role": "system", "content": system_prompt})
	else:
		messages[0] = {"role": "system", "content": system_prompt}

	var travel_plan := LocationTravelPlannerScript.plan_travel(user_content, _read_model)
	var map_cell_plan := LocationTravelPlannerScript.resolve_map_travel_for_turn(
		map_travel,
		user_content,
		_read_model,
	)
	var turn_input := LocationTravelPlannerScript.enrich_player_text(
		user_content,
		_read_model,
		map_travel,
	)
	if not pending_check.is_empty():
		turn_input = _enrich_turn_with_check(turn_input, pending_check)
	messages.append({"role": "user", "content": turn_input})
	messages = NarrativePromptBuilder.trim_messages(messages)

	if append_user_to_story:
		_state_service.append_story_entry("user", user_content)

	var api_response: Dictionary = await _request_ai_response(messages)
	if api_response.has("_error"):
		return _fail(str(api_response["_error"]))
	if api_response.is_empty():
		return _fail("AI 无响应")

	var raw := AiResponseParser.extract_message_content(api_response)
	if raw.is_empty():
		raw = AiResponseParser.extract_top_level_content(api_response)

	var parsed: Dictionary = NarrativeTurnParser.parse_from_api_response(api_response)
	var story_text := str(parsed.get("story_text", "")).strip_edges()
	var parse_ok: bool = parsed.get("parse_ok", false)
	var hook: Dictionary = parsed.get("hook", {}) if parsed.get("hook") is Dictionary else {}

	if story_text.is_empty() and not raw.is_empty():
		story_text = raw

	var request_ai_callable := func(continuation_messages: Array) -> Dictionary:
		return await _request_ai_response(continuation_messages)

	var coordinator := TurnToolCoordinatorScript.new()
	var tool_pass: Dictionary = await coordinator.resolve_turn_tools({
		"parsed": parsed,
		"story_text": story_text,
		"hook": hook,
		"pending_check": pending_check,
		"user_content": user_content,
		"read_model": _read_model,
		"state_service": _state_service,
		"dynamic_add": _dynamic_add,
		"messages": messages,
		"request_ai_callable": request_ai_callable,
	})

	var dynamic_add_in_turn: bool = tool_pass.get("dynamic_add_in_turn", false)
	var auto_repair_applied: bool = tool_pass.get("auto_repair_applied", false)
	var dynamic_add_results: Array = (
		tool_pass.get("dynamic_add_results", [])
		if tool_pass.get("dynamic_add_results") is Array
		else []
	)
	var display_story_text := str(tool_pass.get("story_text", story_text)).strip_edges()
	if display_story_text.is_empty():
		display_story_text = story_text
	pending_check = (
		tool_pass.get("check_result", pending_check)
		if tool_pass.get("check_result") is Dictionary
		else pending_check
	)

	if dynamic_add_in_turn:
		reload_runtime()

	var hook_applied := false
	var hook_warnings: PackedStringArray = []
	var normalized_hook: Dictionary = {}
	if tool_pass.get("hook") is Dictionary:
		normalized_hook = (tool_pass["hook"] as Dictionary).duplicate(true)
	elif not hook.is_empty():
		normalized_hook = hook.duplicate(true)
	if not normalized_hook.is_empty():
		_enrich_hook_from_dynamic_add(normalized_hook, dynamic_add_results)
		_enrich_present_npcs_from_story(display_story_text, normalized_hook, _read_model)
		normalized_hook = NarrativeHookNormalizerScript.normalize(
			normalized_hook,
			_read_model,
			_state_service.get_game_state(),
		)
	if tool_pass.get("tool_warnings") is PackedStringArray:
		for w in tool_pass["tool_warnings"]:
			hook_warnings.append(str(w))
	if not pending_check.is_empty() and pending_check.get("needs_check", false):
		_persist_check_record(pending_check, user_content)

	if NarrativeHookNormalizerScript.can_apply(normalized_hook):
		var apply_result: Dictionary = _state_service.apply_hook(
			normalized_hook,
			_read_model.get_region_ids(),
			_read_model,
		)
		hook_applied = apply_result.get("ok", false)
		if hook_applied:
			parse_ok = true
			reload_runtime()
		else:
			parse_ok = false
		if apply_result.get("warnings") is PackedStringArray:
			hook_warnings = apply_result["warnings"]
	elif parse_ok:
		parse_ok = false

	var npc_reconcile := _reconcile_travel_location(travel_plan, "位置兜底")
	if npc_reconcile.get("applied", false):
		hook_applied = true
		parse_ok = true
	for w in npc_reconcile.get("warnings", []):
		hook_warnings.append(str(w))

	var map_reconcile := _reconcile_map_cell_travel(map_cell_plan)
	if map_reconcile.get("applied", false):
		hook_applied = true
		parse_ok = true
	for w in map_reconcile.get("warnings", []):
		hook_warnings.append(str(w))

	var assistant_for_history := display_story_text
	if assistant_for_history.is_empty():
		assistant_for_history = NarrativeTurnParser.story_text_only(raw)
	messages.append({"role": "assistant", "content": assistant_for_history})
	_state_service.save_narrative_messages(messages)

	var player_narrative := StoryTextDisplayGuardScript.coerce_player_narrative(
		display_story_text,
		raw,
	)
	if not player_narrative.is_empty():
		_state_service.append_story_entry("assistant", player_narrative)

	var suggestions: Array = []
	if tool_pass.get("suggestions") is Array and not (tool_pass["suggestions"] as Array).is_empty():
		suggestions = tool_pass["suggestions"]
	elif hook_applied and not normalized_hook.is_empty():
		suggestions = ActionSuggestionBuilderScript.parse_hook_suggestions(normalized_hook)
	elif parsed.get("suggestions") is Array:
		suggestions = parsed["suggestions"]
	suggestions = ActionSuggestionBuilderScript.filter_suggestions_against_world(
		_read_model,
		suggestions,
	)

	var tool_results: Array = (
		tool_pass.get("tool_results", []) if tool_pass.get("tool_results") is Array else []
	)

	var return_story_text := (
		player_narrative if not player_narrative.is_empty() else display_story_text
	)
	return {
		"ok": not display_story_text.is_empty(),
		"story_text": return_story_text,
		"hook_applied": hook_applied,
		"parse_ok": parse_ok,
		"hook_warnings": hook_warnings,
		"suggestions": suggestions,
		"archived": archived,
		"archive_title": archive_title,
		"archive_warning": archive_warning,
		"dynamic_add_in_turn": dynamic_add_in_turn,
		"auto_repair_applied": auto_repair_applied,
		"dynamic_add_results": dynamic_add_results,
		"check_result": pending_check,
		"tool_results": tool_results,
		"error": "" if parse_ok else str(parsed.get("error", "状态 hook 解析或应用失败")),
		"raw_assistant_text": raw,
	}


func _request_ai_response(messages: Array) -> Dictionary:
	var state := {"done": false, "response": {}, "error": ""}

	var on_completed := func(response: Dictionary) -> void:
		state["response"] = response if response is Dictionary else {}
		if state["response"].is_empty():
			state["error"] = "AI 响应为空"
		state["done"] = true

	var on_failed := func(err: String) -> void:
		state["error"] = err
		state["done"] = true

	_ai_client.chat_completed.connect(on_completed, CONNECT_ONE_SHOT)
	_ai_client.request_failed.connect(on_failed, CONNECT_ONE_SHOT)
	_ai_client.chat(messages)

	var loop := Engine.get_main_loop()
	while not state["done"]:
		if loop == null:
			break
		await loop.process_frame

	if not state["error"].is_empty():
		push_error("[NarrativeService] " + state["error"])
		return {"_error": state["error"]}

	var api_payload: Dictionary = state["response"]
	if not parse_ok_preview(api_payload):
		push_warning(
			"[NarrativeService] 未解析到 STATE_HOOK；message.len=%d top.len=%d"
			% [
				AiResponseParser.extract_choice_message_content(api_payload).length(),
				AiResponseParser.extract_top_level_content(api_payload).length(),
			]
		)
	return api_payload


static func parse_ok_preview(response: Dictionary) -> bool:
	return NarrativeTurnParser.parse_from_api_response(response).get("parse_ok", false)


func _auto_repair_orphan_entities(story_text: String) -> Array:
	if _dynamic_add == null:
		return []
	var repair_reqs := NarrativeEntityRepairScript.build_synthetic_requests(story_text, _read_model)
	if repair_reqs.is_empty():
		return []
	push_warning(
		"[NarrativeService] AI 未输出 DYN_ADD，程序自动补全 %d 项实体数据"
		% repair_reqs.size()
	)
	var world_context := JSON.stringify(_read_model.base_config, "\t")
	var pipeline: Dictionary = await _dynamic_add.process_synthetic_requests(
		repair_reqs,
		world_context,
	)
	var results: Array = []
	if pipeline.get("dynamic_add_results") is Array:
		results = pipeline["dynamic_add_results"]
	var any_ok := false
	for item in results:
		if item is Dictionary and item.get("ok", false):
			any_ok = true
			break
	if not any_ok and not results.is_empty():
		push_warning("[NarrativeService] 自动补全实体数据失败，请检查 AI 后端是否可用")
	return results


func _resolve_dynamic_add_in_turn(story_text: String) -> Dictionary:
	if _dynamic_add == null:
		return {"ran": false, "assistant_text": story_text, "dynamic_add_results": []}
	if DynamicAddTriggerParserScript.find_all(story_text).is_empty():
		return {"ran": false, "assistant_text": story_text, "dynamic_add_results": []}
	var world_context := JSON.stringify(_read_model.base_config, "\t")
	var pipeline: Dictionary = await _dynamic_add.resolve_triggers_in_text(
		story_text,
		world_context,
		false,
	)
	return {
		"ran": true,
		"assistant_text": str(pipeline.get("assistant_text", story_text)),
		"dynamic_add_results": pipeline.get("dynamic_add_results", []),
	}


static func _enrich_hook_from_dynamic_add(hook: Dictionary, dynamic_add_results: Array) -> void:
	if dynamic_add_results.is_empty():
		return
	var npc_ids: Array = []
	if hook.get("present_npc_ids") is Array:
		for item in hook["present_npc_ids"]:
			var s := str(item).strip_edges()
			if not s.is_empty():
				npc_ids.append(s)
	for item in dynamic_add_results:
		if not item is Dictionary:
			continue
		if not item.get("ok", false):
			continue
		var schema_id := str(item.get("schema_id", "")).strip_edges()
		var data: Dictionary = item.get("data", {}) if item.get("data") is Dictionary else {}
		if schema_id == "runtime_npc":
			var nid := str(data.get("id", "")).strip_edges()
			if not nid.is_empty() and nid not in npc_ids:
				npc_ids.append(nid)
		elif schema_id == "runtime_key_node":
			var node_id := str(data.get("id", "")).strip_edges()
			if not node_id.is_empty() and not hook.has("current_key_node_id"):
				hook["current_key_node_id"] = node_id
			var region_id := str(data.get("region_id", "")).strip_edges()
			if not region_id.is_empty() and str(hook.get("current_region_id", "")).strip_edges().is_empty():
				hook["current_region_id"] = region_id
		elif schema_id == "runtime_region":
			var region_id := str(data.get("id", "")).strip_edges()
			if not region_id.is_empty():
				if str(hook.get("current_region_id", "")).strip_edges().is_empty():
					hook["current_region_id"] = region_id
				var unlock: Array = []
				if hook.get("unlock_region_ids") is Array:
					unlock.assign(hook["unlock_region_ids"])
				if region_id not in unlock:
					unlock.append(region_id)
				hook["unlock_region_ids"] = unlock
	if not npc_ids.is_empty():
		hook["present_npc_ids"] = npc_ids


static func _enrich_present_npcs_from_story(
	story_text: String,
	hook: Dictionary,
	read_model: GameReadModel,
) -> void:
	var text := story_text.strip_edges()
	if text.is_empty():
		return
	var npc_ids: Array = []
	if hook.get("present_npc_ids") is Array:
		for item in hook["present_npc_ids"]:
			var s := str(item).strip_edges()
			if not s.is_empty():
				npc_ids.append(s)

	var protagonist := str(read_model.mainrole.get("name", "")).strip_edges()
	var here := LocationServiceScript.get_protagonist_location(read_model)
	var speakers: Dictionary = {}
	for speaker in NarrativeEntityGuardScript._extract_dialogue_speaker_names(text):
		speakers[speaker] = true

	for name in NarrativeEntityGuardScript.extract_npc_names(text):
		if name == protagonist:
			continue
		var nid := NarrativeHookNormalizerScript.resolve_npc_id(name, read_model)
		if nid.is_empty() or read_model.get_npc(nid).is_empty():
			continue
		if nid in npc_ids:
			continue
		var in_scene := speakers.has(name) or _npc_interacts_in_story(name, text)
		if not in_scene:
			continue
		var npc_loc := LocationServiceScript.get_npc_location(read_model, read_model.get_npc(nid))
		if LocationServiceScript.is_same_place(here, npc_loc) or speakers.has(name):
			npc_ids.append(nid)

	if not npc_ids.is_empty():
		hook["present_npc_ids"] = npc_ids


static func _npc_interacts_in_story(npc_name: String, text: String) -> bool:
	var patterns: PackedStringArray = [
		"%s[，,].{0,24}(?:说|问|道|喊|笑|颤|叹|开|抬|转|看|握|点|愣|抖)" % npc_name,
		"(?:见到|遇见|面对|望着|盯着|拜访|探访)%s" % npc_name,
	]
	for pat in patterns:
		var re := RegEx.new()
		if re.compile(pat) != OK:
			continue
		if re.search(text) != null:
			return true
	return false


static func _enrich_turn_with_check(turn_input: String, check: Dictionary) -> String:
	if not check.get("needs_check", false):
		return turn_input
	var label := str(check.get("check_label", "")).strip_edges()
	var outcome := str(check.get("outcome_label", check.get("outcome", ""))).strip_edges()
	var d20 := int(check.get("d20", 0))
	var total := int(check.get("total", 0))
	var dc := int(check.get("dc", 0))
	var block := (
		"\n\n【程序已掷骰】%s：d20=%d + 修正 → %d，DC %d，结果：%s。"
		% [label, d20, total, dc, outcome]
	)
	block += "请按此结果写 80–220 字叙事，并在 JSON 中填写 check_summary。"
	return turn_input + block


func _persist_check_record(check: Dictionary, player_action: String) -> void:
	_state_service.load_from_runtime()
	var state := _state_service.get_game_state().duplicate(true)
	var history: Array = state.get("check_history", [])
	if not history is Array:
		history = []
	var entry := check.duplicate(true)
	entry["player_action"] = player_action
	entry["ts"] = int(Time.get_unix_time_from_system())
	history.append(entry)
	if history.size() > 30:
		history = history.slice(history.size() - 30)
	state["check_history"] = history
	GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state)


static func _fail(reason: String) -> Dictionary:
	return {
		"ok": false,
		"story_text": "",
		"hook_applied": false,
		"parse_ok": false,
		"hook_warnings": PackedStringArray(),
		"suggestions": [],
		"archived": false,
		"archive_title": "",
		"archive_warning": "",
		"dynamic_add_in_turn": false,
		"auto_repair_applied": false,
		"dynamic_add_results": [],
		"check_result": {},
		"tool_results": [],
		"error": reason,
		"raw_assistant_text": "",
	}
