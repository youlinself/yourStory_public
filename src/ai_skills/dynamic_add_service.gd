class_name DynamicAddService
extends Node

## 封装 dynamic_add 全流程：
## 1. 注册技能说明（系统提示）
## 2. AI 在叙事中输出一条或多条 [[DYN_ADD:分类|来源]]
## 3. 程序解析（单次上限 max_per_response）→ 单条或批量生成 → 写入 *_db.json
## 4. 将结果回填叙事（可选继续对话）

signal dynamic_add_completed(results: Array)
signal dynamic_add_failed(reason: String)

const DynamicAddRegistry = preload("res://src/ai_skills/dynamic_add_registry.gd")
const DynamicAddPromptBuilder = preload("res://src/ai_skills/dynamic_add_prompt_builder.gd")
const DynamicAddTriggerParser = preload("res://src/ai_skills/dynamic_add_trigger_parser.gd")
const DynamicAddStorage = preload("res://src/ai_skills/dynamic_add_storage.gd")
const ItemGenerationAgentScript := preload("res://src/ai_skills/item_generation_agent.gd")
const AiPromptComposerScript := preload("res://src/ai_config/ai_prompt_composer.gd")

## 小于 0 时使用 registry 中的 max_per_response（默认 5）。
var max_per_response_override: int = -1

var _ai_client: AIClient
var _item_agent: ItemGenerationAgentScript


func _init() -> void:
	_ai_client = AIClient.new()
	_item_agent = ItemGenerationAgentScript.new()


func _ready() -> void:
	add_child(_ai_client)
	add_child(_item_agent)
	_item_agent.set_request_ai_callable(_wrap_item_agent_ai_request)


func set_port(port: int) -> void:
	_ai_client.set_port(port)
	_item_agent.set_port(port)


func get_max_per_response() -> int:
	if max_per_response_override > 0:
		return max_per_response_override
	return DynamicAddRegistry.get_max_per_response()


## 供系统提示词拼接的「技能注册」段落（体积小，可常驻）。
static func build_skill_registration_prompt() -> String:
	return DynamicAddPromptBuilder.build_registration_prompt()


## 带技能注册的对话：自动处理回复中的 DYN_ADD 标记。
func chat_and_resolve(messages: Array, world_context: String = "", continue_narrative: bool = true) -> Dictionary:
	if world_context.strip_edges().is_empty():
		world_context = load_world_context_from_runtime()
	var raw := await _request_ai(messages)
	if raw.is_empty():
		return {"ok": false, "error": "AI 无响应"}

	var pipeline := await resolve_triggers_in_text(raw, world_context, continue_narrative, messages)
	pipeline["raw_assistant_text"] = raw
	return pipeline


## 程序根据正文推断的补全请求（无 [[DYN_ADD]] 标记时使用）。
func process_synthetic_requests(requests: Array, world_context: String = "") -> Dictionary:
	if requests.is_empty():
		return {"ok": true, "dynamic_add_results": [], "processed_count": 0}
	if world_context.strip_edges().is_empty():
		world_context = load_world_context_from_runtime()
	var accepted: Array = []
	for i in range(requests.size()):
		var req: Variant = requests[i]
		if req is DynamicAddTriggerParser.TriggerRequest:
			req.request_index = accepted.size()
			accepted.append(req)
	var max_count := get_max_per_response()
	if accepted.size() > max_count:
		accepted = accepted.slice(0, max_count)
	var results: Array = await _process_accepted_requests(accepted, world_context)
	dynamic_add_completed.emit(results)
	return {
		"ok": true,
		"dynamic_add_results": results,
		"processed_count": accepted.size(),
		"auto_repair": true,
	}


## 仅处理已有文本中的标记（不发起首轮对话）。
func resolve_triggers_in_text(
	assistant_text: String,
	world_context: String = "",
	continue_narrative: bool = false,
	prior_messages: Array = [],
) -> Dictionary:
	var all_requests: Array = DynamicAddTriggerParser.find_all(assistant_text)
	if all_requests.is_empty():
		return {
			"ok": true,
			"assistant_text": assistant_text,
			"dynamic_add_results": [],
		}

	var max_count := get_max_per_response()
	var split: Dictionary = DynamicAddTriggerParser.partition_by_limit(all_requests, max_count)
	var accepted: Array = split.get("accepted", [])
	var overflow: Array = split.get("overflow", [])

	var results: Array = []
	var token_replacements: Dictionary = {}

	for req in overflow:
		token_replacements[req.raw_token] = (
			"（已达单次动态添加上限 %d 项，此项已跳过）" % max_count
		)
		results.append({
			"ok": false,
			"skipped": true,
			"reason": "max_per_response",
			"raw_token": req.raw_token,
		})

	if accepted.is_empty():
		var only_overflow := DynamicAddTriggerParser.replace_tokens(assistant_text, token_replacements)
		return {
			"ok": true,
			"assistant_text": only_overflow,
			"dynamic_add_results": results,
			"truncated_count": overflow.size(),
		}

	var batch_results := await _process_accepted_requests(accepted, world_context)
	for item in batch_results:
		results.append(item)
		_apply_result_to_replacement(item, token_replacements)

	var cleaned := DynamicAddTriggerParser.replace_tokens(assistant_text, token_replacements)
	dynamic_add_completed.emit(results)

	var out := {
		"ok": true,
		"assistant_text": cleaned,
		"dynamic_add_results": results,
		"processed_count": accepted.size(),
		"truncated_count": overflow.size(),
	}

	if not continue_narrative or prior_messages.is_empty():
		return out

	var follow_messages: Array = prior_messages.duplicate(true)
	follow_messages.append({"role": "assistant", "content": cleaned})
	follow_messages.append({
		"role": "user",
		"content": _build_continuation_user_message(results),
	})

	var continued := await _request_ai(follow_messages)
	if continued.is_empty():
		out["continuation_skipped"] = true
		return out

	var nested := DynamicAddTriggerParser.find_all(continued)
	if nested.is_empty():
		out["assistant_text"] = continued
		return out

	var second := await resolve_triggers_in_text(continued, world_context, false, [])
	second["dynamic_add_results"] = results + second.get("dynamic_add_results", [])
	return second


func _process_accepted_requests(accepted: Array, world_context: String) -> Array:
	var out: Array = []
	var valid: Array = []
	for req in accepted:
		if req.schema_id.is_empty():
			var err := "无法识别 DYN_ADD 分类: %s" % req.category_raw
			dynamic_add_failed.emit(err)
			out.append({
				"ok": false,
				"error": err,
				"raw_token": req.raw_token,
				"request_index": req.request_index,
			})
		else:
			valid.append(req)

	var loot_requests: Array = []
	var other_requests: Array = []
	for req in valid:
		if ItemGenerationAgentScript.is_loot_schema(req.schema_id):
			loot_requests.append(req)
		else:
			other_requests.append(req)

	if not loot_requests.is_empty():
		out.append_array(await _run_loot_generation_rounds(loot_requests, world_context))

	var use_batch := (
		other_requests.size() >= DynamicAddRegistry.get_batch_min_count()
		and DynamicAddRegistry.is_batch_generation_enabled()
	)
	if use_batch:
		out.append_array(await _run_batch_generation_round(other_requests, world_context))
	elif other_requests.size() == 1:
		out.append(await _run_generation_round(other_requests[0], world_context))
	else:
		for req in other_requests:
			out.append(await _run_generation_round(req, world_context))

	out.sort_custom(func(a, b): return int(a.get("request_index", 0)) < int(b.get("request_index", 0)))
	return out


func _run_batch_generation_round(valid: Array, world_context: String) -> Array:
	if valid.is_empty():
		return []

	var gen_user := DynamicAddPromptBuilder.build_batch_generation_user_message(valid, world_context)
	var gen_raw := await _request_ai(AiPromptComposerScript.wrap_json_task(gen_user))
	if gen_raw.is_empty():
		return _batch_fail_all(valid, "批量生成轮 AI 无响应")

	var entries := _parse_batch_entries(gen_raw, valid.size())
	if entries.is_empty():
		return _batch_fail_all(valid, "批量生成 JSON 无效", gen_raw)

	var stored_list := DynamicAddStorage.apply_batch_entries(entries)
	return _merge_batch_results(valid, stored_list, entries)


func _merge_batch_results(
	requests: Array,
	stored_list: Array,
	raw_entries: Array,
) -> Array:
	var by_index: Dictionary = {}
	for i in range(raw_entries.size()):
		var entry: Variant = raw_entries[i]
		if entry is Dictionary:
			var idx := int(entry.get("index", i))
			by_index[idx] = i

	var out: Array = []
	for pos in range(requests.size()):
		var req: DynamicAddTriggerParser.TriggerRequest = requests[pos]
		var idx: int = req.request_index
		var stored: Dictionary = {"ok": false, "error": "批量结果缺少对应 index"}
		var si := -1
		if by_index.has(idx):
			si = int(by_index[idx])
		elif pos < stored_list.size():
			si = pos
		if si >= 0 and si < stored_list.size() and stored_list[si] is Dictionary:
			stored = (stored_list[si] as Dictionary).duplicate(true)
		stored["raw_token"] = req.raw_token
		stored["category"] = req.category_raw
		stored["source_context"] = req.source_context
		stored["request_index"] = idx
		if not stored.has("schema_id") or str(stored.get("schema_id", "")).is_empty():
			stored["schema_id"] = req.schema_id
		out.append(stored)
	return out


func _batch_fail_all(requests: Array, error: String, raw: String = "") -> Array:
	var out: Array = []
	for req in requests:
		var row := {
			"ok": false,
			"error": error,
			"schema_id": req.schema_id,
			"raw_token": req.raw_token,
			"request_index": req.request_index,
		}
		if not raw.is_empty():
			row["raw"] = raw
		out.append(row)
	return out


func _parse_batch_entries(raw: String, expected_count: int) -> Array:
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if parsed is Dictionary:
		var entries: Variant = parsed.get("entries", null)
		if entries is Array and not entries.is_empty():
			return _normalize_batch_entries(entries as Array, expected_count)
		if _validate_single_entry_payload(parsed, ""):
			return [{"index": 0, "schema_id": parsed.get("schema_id", ""), "data": parsed.get("data", {})}]
	if parsed is Array:
		return _normalize_batch_entries(parsed, expected_count)
	return []


static func _normalize_batch_entries(entries: Array, expected_count: int) -> Array:
	var out: Array = []
	for i in range(entries.size()):
		var item: Variant = entries[i]
		if not item is Dictionary:
			continue
		var row: Dictionary = (item as Dictionary).duplicate(true)
		if not row.has("index"):
			row["index"] = i
		if not row.has("schema_id"):
			continue
		if not row.get("data") is Dictionary:
			continue
		out.append(row)
	if expected_count > 0 and out.size() > expected_count:
		return out.slice(0, expected_count)
	return out


func _run_loot_generation_rounds(requests: Array, world_context: String) -> Array:
	var use_batch := (
		requests.size() >= DynamicAddRegistry.get_batch_min_count()
		and DynamicAddRegistry.is_batch_generation_enabled()
	)
	if use_batch:
		return await _item_agent.generate_from_triggers(requests, world_context)
	var out: Array = []
	for req in requests:
		if req is DynamicAddTriggerParser.TriggerRequest:
			out.append(await _item_agent.generate_from_trigger(req, world_context))
	return out


func _wrap_item_agent_ai_request(messages: Array) -> String:
	return await _request_ai(messages)


func _run_generation_round(req: DynamicAddTriggerParser.TriggerRequest, world_context: String) -> Dictionary:
	if ItemGenerationAgentScript.is_loot_schema(req.schema_id):
		return await _item_agent.generate_from_trigger(req, world_context)
	var gen_user := DynamicAddPromptBuilder.build_generation_user_message(
		req.schema_id,
		req.source_context,
		world_context,
	)
	var gen_raw := await _request_ai(AiPromptComposerScript.wrap_json_task(gen_user))
	if gen_raw.is_empty():
		return {
			"ok": false,
			"error": "生成轮 AI 无响应",
			"schema_id": req.schema_id,
			"request_index": req.request_index,
		}

	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(gen_raw)
	if not _validate_single_entry_payload(parsed, req.schema_id):
		return {
			"ok": false,
			"error": "生成轮 JSON 无效",
			"schema_id": req.schema_id,
			"raw": gen_raw,
			"request_index": req.request_index,
		}

	var payload: Dictionary = parsed as Dictionary
	if not payload.has("schema_id") or str(payload["schema_id"]).is_empty():
		payload["schema_id"] = req.schema_id
	var stored := DynamicAddStorage.apply_generation_result(req.schema_id, payload)
	stored["raw_token"] = req.raw_token
	stored["category"] = req.category_raw
	stored["source_context"] = req.source_context
	stored["request_index"] = req.request_index
	return stored


static func _validate_single_entry_payload(data: Variant, schema_id: String) -> bool:
	if not data is Dictionary:
		return false
	var d: Dictionary = data
	if not d.get("data") is Dictionary:
		return false
	var sid := str(d.get("schema_id", "")).strip_edges()
	if not schema_id.is_empty() and not sid.is_empty() and sid != schema_id:
		return false
	return true


func _apply_result_to_replacement(item: Dictionary, token_replacements: Dictionary) -> void:
	var raw_token := str(item.get("raw_token", ""))
	if raw_token.is_empty():
		return
	if item.get("skipped", false):
		return
	if not item.get("ok", false):
		token_replacements[raw_token] = "（动态生成失败）"
		return
	var data: Dictionary = item.get("data", {})
	var display_name := str(data.get("name", data.get("id", "")))
	var status := str(item.get("status", ""))
	if display_name.is_empty():
		token_replacements[raw_token] = ""
	elif status == "already_exists":
		token_replacements[raw_token] = "【已有：%s】" % display_name
	else:
		token_replacements[raw_token] = "【%s】" % display_name


static func _build_continuation_user_message(results: Array) -> String:
	var lines: PackedStringArray = [
		"[系统] 下列动态数据已写入运行时总表，请据此继续叙事，勿重复输出 [[DYN_ADD:...]] 标记。",
		"",
	]
	for item in results:
		if not item is Dictionary:
			continue
		if item.get("skipped", false):
			continue
		if not item.get("ok", false):
			lines.append("- 失败: %s" % str(item.get("error", "")))
			continue
		lines.append(
			"- [%s] %s / %s: %s"
			% [
				str(item.get("request_index", "")),
				str(item.get("schema_id", "")),
				str(item.get("status", "")),
				JSON.stringify(item.get("data", {})),
			]
		)
	return "\n".join(lines)


func _request_ai(messages: Array) -> String:
	if messages.is_empty():
		return ""
	var state := {"done": false, "text": "", "error": ""}

	var on_completed := func(response: Dictionary) -> void:
		state["text"] = AiResponseParser.extract_message_content(response)
		if state["text"].is_empty():
			state["error"] = "AI 响应无正文"
		state["done"] = true

	var on_failed := func(err: String) -> void:
		state["error"] = err
		state["done"] = true

	_ai_client.chat_completed.connect(on_completed, CONNECT_ONE_SHOT)
	_ai_client.request_failed.connect(on_failed, CONNECT_ONE_SHOT)
	_ai_client.chat(messages)

	while not state["done"]:
		await get_tree().process_frame

	if not state["error"].is_empty():
		push_error("[DynamicAddService] " + state["error"])
		dynamic_add_failed.emit(state["error"])
		return ""

	return state["text"]


static func wrap_messages_with_skill_registration(messages: Array) -> Array:
	var reg := build_skill_registration_prompt()
	var out: Array = []
	var has_system := false
	for msg in messages:
		if msg is Dictionary and str(msg.get("role", "")) == "system":
			has_system = true
			var merged := str(msg.get("content", "")).strip_edges()
			if not merged.is_empty():
				merged += "\n\n"
			merged += reg
			out.append({"role": "system", "content": merged})
		else:
			out.append(msg)
	if not has_system:
		out.insert(0, {"role": "system", "content": reg})
	return out


static func load_world_context_from_runtime() -> String:
	var base: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.BASE_CONFIG)
	if base is Dictionary:
		return JSON.stringify(base, "\t")
	return ""
