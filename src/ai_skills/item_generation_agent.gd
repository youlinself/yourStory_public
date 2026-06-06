class_name ItemGenerationAgent
extends Node

## 物品/装备元数据生成统一入口（世界初始化子步 7 + dynamic_add loot 类型）。

const DynamicAddPromptBuilder := preload("res://src/ai_skills/dynamic_add_prompt_builder.gd")
const DynamicAddStorage := preload("res://src/ai_skills/dynamic_add_storage.gd")
const DynamicAddTriggerParser := preload("res://src/ai_skills/dynamic_add_trigger_parser.gd")
const ItemSettingGuardScript := preload("res://src/game/logic/data/item_setting_guard.gd")
const ItemDisplayCatalogScript := preload("res://src/game/logic/data/item_display_catalog.gd")
const AiPromptComposerScript := preload("res://src/ai_config/ai_prompt_composer.gd")

const LOOT_SCHEMA_IDS: Array[String] = ["loot_item", "loot_weapon"]

var _ai_client: AIClient
var _request_ai_callable: Callable = Callable()


func _init() -> void:
	_ai_client = AIClient.new()


func _ready() -> void:
	add_child(_ai_client)


func set_port(port: int) -> void:
	_ai_client.set_port(port)


func set_request_ai_callable(callable: Callable) -> void:
	_request_ai_callable = callable


static func is_loot_schema(schema_id: String) -> bool:
	return schema_id.strip_edges() in LOOT_SCHEMA_IDS


static func infer_schema_id(item_id: String) -> String:
	var s := item_id.strip_edges().to_lower()
	if s.begins_with("weapon_") or s.begins_with("equip_"):
		return "loot_weapon"
	return "loot_item"


static func is_placeholder_record(row: Dictionary, item_id: String) -> bool:
	return ItemDisplayCatalogScript.is_placeholder_record(row, item_id)


static func build_locked_id_prompt_lines(request: Dictionary) -> PackedStringArray:
	var item_id := str(request.get("id", "")).strip_edges()
	var lines := PackedStringArray([
		"### id 锁定（必守）",
		"`data.id` 必须**逐字等于** `%s`，禁止自造或改写 id。" % item_id,
	])
	var familiarity := str(request.get("world_familiarity", "")).strip_edges()
	if not familiarity.is_empty():
		lines.append("`world_familiarity` 须为：%s" % familiarity)
	return lines


static func collect_from_npc_db(
	npc_db: Dictionary,
	world_init: Dictionary,
	_base_config: Dictionary,
) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var adventure: Dictionary = {}
	var adv_val: Variant = world_init.get("adventure_module", null)
	if adv_val is Dictionary:
		adventure = adv_val as Dictionary
	var opening_hook := str(adventure.get("opening_hook", "")).strip_edges()

	var npcs: Variant = npc_db.get("npcs", {})
	if not npcs is Dictionary:
		return out

	for npc in (npcs as Dictionary).values():
		if not npc is Dictionary:
			continue
		var npc_dict: Dictionary = npc as Dictionary
		var inv: Variant = npc_dict.get("items", [])
		if not inv is Array:
			continue
		for entry in inv:
			if not entry is Dictionary:
				continue
			var slot: Dictionary = entry as Dictionary
			var item_id := str(slot.get("id", "")).strip_edges()
			if item_id.is_empty() or seen.has(item_id):
				continue
			seen[item_id] = true
			var source := _build_starter_source_context(npc_dict, opening_hook)
			var req := {
				"id": item_id,
				"schema_id": infer_schema_id(item_id),
				"source_context": source,
				"world_familiarity": str(slot.get("world_familiarity", "")).strip_edges(),
				"lock_id": true,
			}
			out.append(req)
	return out


static func _build_starter_source_context(npc: Dictionary, opening_hook: String) -> String:
	var parts: PackedStringArray = []
	var npc_name := str(npc.get("name", "")).strip_edges()
	if not npc_name.is_empty():
		parts.append("持有者：%s" % npc_name)
	var scene := str(npc.get("initial_scene", "")).strip_edges()
	if not scene.is_empty():
		parts.append("开场场景：%s" % scene)
	var equip: Variant = npc.get("equipment", [])
	if equip is Array:
		for raw in equip:
			var text := str(raw).strip_edges()
			if not text.is_empty():
				parts.append("持物描述：%s" % text)
	if not opening_hook.is_empty():
		parts.append("冒险开场：%s" % opening_hook)
	if parts.is_empty():
		return "世界初始化主角/ NPC 初始背包物品"
	return "；".join(parts)


static func request_from_trigger(req: DynamicAddTriggerParser.TriggerRequest) -> Dictionary:
	return {
		"id": "",
		"schema_id": req.schema_id,
		"source_context": req.source_context,
		"world_familiarity": "",
		"lock_id": false,
		"request_index": req.request_index,
		"raw_token": req.raw_token,
		"category": req.category_raw,
	}


static func build_generation_user_message(request: Dictionary, world_context: String) -> String:
	var schema_id := str(request.get("schema_id", "")).strip_edges()
	var schema_block := DynamicAddPromptBuilder.build_generation_prompt(schema_id)
	if schema_block.is_empty():
		return ""

	var parts: PackedStringArray = [
		"你是游戏运行时数据生成器。根据下方 schema 生成**一条**记录。",
		"**只输出纯 JSON**，不要用 markdown 代码围栏，不要解释。",
		"",
		schema_block,
		"",
	]
	parts.append_array(DynamicAddPromptBuilder.loot_consistency_prompt_lines())
	parts.append("")

	if bool(request.get("lock_id", false)):
		parts.append_array(build_locked_id_prompt_lines(request))
		parts.append("")

	parts.append("### 上下文")
	parts.append("- schema_id: `%s`" % schema_id)
	var source := str(request.get("source_context", "")).strip_edges()
	if not source.is_empty():
		parts.append("- 来源: %s" % source)
	if not world_context.strip_edges().is_empty():
		parts.append("- 世界观设定:\n%s" % world_context.strip_edges())

	parts.append("")
	parts.append("### 输出格式（严格遵守）")
	parts.append(
		JSON.stringify(
			{
				"status": "new_created",
				"schema_id": schema_id,
				"data": {},
				"storage_note": "简短说明",
			},
			"\t",
		)
	)
	parts.append("将 `data` 按模板填满；`status` 固定写 new_created（查重由程序处理）。")
	return "\n".join(parts)


static func build_batch_generation_user_message(requests: Array, world_context: String) -> String:
	if requests.is_empty():
		return ""

	var schema_ids_seen: Dictionary = {}
	var parts: PackedStringArray = [
		"你是游戏运行时数据生成器。根据下方**编号请求**与对应 schema，一次生成**多条**记录。",
		"**只输出纯 JSON**，不要用 markdown 代码围栏，不要解释。",
		"",
		"### 待生成列表",
	]

	for i in range(requests.size()):
		var req: Dictionary = requests[i] if requests[i] is Dictionary else {}
		var idx := int(req.get("request_index", i))
		var schema_id := str(req.get("schema_id", "")).strip_edges()
		var source := str(req.get("source_context", "")).strip_edges()
		var id_line := ""
		if bool(req.get("lock_id", false)):
			var locked_id := str(req.get("id", "")).strip_edges()
			if not locked_id.is_empty():
				id_line = "，锁定 id=`%s`" % locked_id
		parts.append(
			"%d. schema_id=`%s`，来源：%s%s"
			% [idx, schema_id, source if not source.is_empty() else "（未说明）", id_line]
		)
		schema_ids_seen[schema_id] = true

	parts.append("")
	parts.append("### 各类型 schema（仅包含本批涉及的类型）")
	for schema_id: String in schema_ids_seen:
		var block := DynamicAddPromptBuilder.build_generation_prompt(schema_id)
		if not block.is_empty():
			parts.append(block)

	parts.append("")
	parts.append_array(DynamicAddPromptBuilder.loot_consistency_prompt_lines())

	var any_locked := false
	for req in requests:
		if req is Dictionary and bool((req as Dictionary).get("lock_id", false)):
			any_locked = true
			break
	if any_locked:
		parts.append("")
		parts.append("### id 锁定（必守）")
		for i in range(requests.size()):
			var req: Dictionary = requests[i] if requests[i] is Dictionary else {}
			if not bool(req.get("lock_id", false)):
				continue
			var locked_id := str(req.get("id", "")).strip_edges()
			if locked_id.is_empty():
				continue
			var idx := int(req.get("request_index", i))
			parts.append("%d. `data.id` 必须逐字等于 `%s`" % [idx, locked_id])

	if not world_context.strip_edges().is_empty():
		parts.append("")
		parts.append("### 世界观设定\n\n%s" % world_context.strip_edges())

	parts.append("")
	parts.append("### 输出格式（严格遵守）")
	var sample_entries: Array = []
	for i in range(requests.size()):
		var req: Dictionary = requests[i] if requests[i] is Dictionary else {}
		sample_entries.append({
			"index": int(req.get("request_index", i)),
			"schema_id": str(req.get("schema_id", "")),
			"status": "new_created",
			"data": {},
		})
	parts.append(JSON.stringify({"entries": sample_entries}, "\t"))
	parts.append(
		"`entries` 长度必须等于待生成条数（%d）；`index` 与上文编号一致；每条 `data` 按该条 schema 模板填满。"
		% requests.size()
	)
	return "\n".join(parts)


func generate_single(request: Dictionary, world_context: String) -> Dictionary:
	var schema_id := str(request.get("schema_id", "")).strip_edges()
	var gen_user := build_generation_user_message(request, world_context)
	var gen_raw := await _call_ai(AiPromptComposerScript.wrap_json_task(gen_user))
	if gen_raw.is_empty():
		return _fail_result(request, "生成轮 AI 无响应")

	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(gen_raw)
	if not _validate_payload(parsed, schema_id):
		var retry_user := gen_user + _retry_suffix("生成轮 JSON 无效")
		gen_raw = await _call_ai(AiPromptComposerScript.wrap_json_task(retry_user))
		if gen_raw.is_empty():
			return _fail_result(request, "生成轮 AI 无响应（重试）")
		parsed = AiResponseParser.parse_json_from_ai_text(gen_raw)
		if not _validate_payload(parsed, schema_id):
			return _fail_result(request, "生成轮 JSON 无效", gen_raw)

	var payload: Dictionary = parsed as Dictionary
	if not payload.has("schema_id") or str(payload["schema_id"]).is_empty():
		payload["schema_id"] = schema_id

	var record: Dictionary = (payload.get("data", {}) as Dictionary).duplicate(true)
	var lock_err := _enforce_locked_id(request, record)
	if not lock_err.is_empty():
		var retry_user := build_generation_user_message(request, world_context) + _retry_suffix(lock_err)
		gen_raw = await _call_ai(AiPromptComposerScript.wrap_json_task(retry_user))
		if gen_raw.is_empty():
			return _fail_result(request, lock_err)
		parsed = AiResponseParser.parse_json_from_ai_text(gen_raw)
		if not _validate_payload(parsed, schema_id):
			return _fail_result(request, lock_err, gen_raw)
		payload = parsed as Dictionary
		record = (payload.get("data", {}) as Dictionary).duplicate(true)
		lock_err = _enforce_locked_id(request, record)
		if not lock_err.is_empty():
			return _fail_result(request, lock_err)
	payload["data"] = record

	var stored := DynamicAddStorage.apply_generation_result(schema_id, payload, true)
	if not stored.get("ok", false):
		var store_err := str(stored.get("error", "")).strip_edges()
		if not store_err.is_empty():
			var retry_user := build_generation_user_message(request, world_context) + _retry_suffix(store_err)
			gen_raw = await _call_ai(AiPromptComposerScript.wrap_json_task(retry_user))
			if not gen_raw.is_empty():
				parsed = AiResponseParser.parse_json_from_ai_text(gen_raw)
				if _validate_payload(parsed, schema_id):
					payload = parsed as Dictionary
					record = (payload.get("data", {}) as Dictionary).duplicate(true)
					lock_err = _enforce_locked_id(request, record)
					if lock_err.is_empty():
						payload["data"] = record
						stored = DynamicAddStorage.apply_generation_result(schema_id, payload, true)
	return _decorate_result(stored, request)


func generate_batch(requests: Array, world_context: String) -> Array:
	if requests.is_empty():
		return []
	if requests.size() == 1 and requests[0] is Dictionary:
		return [await generate_single(requests[0] as Dictionary, world_context)]

	var gen_user := build_batch_generation_user_message(requests, world_context)
	var gen_raw := await _call_ai(AiPromptComposerScript.wrap_json_task(gen_user))
	if gen_raw.is_empty():
		return _batch_fail_all(requests, "批量生成轮 AI 无响应")

	var entries := _parse_batch_entries(gen_raw, requests.size())
	if entries.is_empty():
		gen_raw = await _call_ai(
			AiPromptComposerScript.wrap_json_task(gen_user + _retry_suffix("批量生成 JSON 无效"))
		)
		if gen_raw.is_empty():
			return _batch_fail_all(requests, "批量生成轮 AI 无响应（重试）")
		entries = _parse_batch_entries(gen_raw, requests.size())
		if entries.is_empty():
			return _batch_fail_all(requests, "批量生成 JSON 无效", gen_raw)

	_apply_locked_ids_to_batch_entries(requests, entries)
	var stored_list := DynamicAddStorage.apply_batch_entries(entries, true)
	return _merge_batch_results(requests, stored_list, entries)


func generate_from_trigger(req: DynamicAddTriggerParser.TriggerRequest, world_context: String) -> Dictionary:
	var request := request_from_trigger(req)
	return await generate_single(request, world_context)


func generate_from_triggers(triggers: Array, world_context: String) -> Array:
	var requests: Array = []
	for req in triggers:
		if req is DynamicAddTriggerParser.TriggerRequest:
			var row := request_from_trigger(req)
			requests.append(row)
	return await generate_batch(requests, world_context)


static func _apply_locked_ids_to_batch_entries(requests: Array, entries: Array) -> void:
	var by_index: Dictionary = {}
	for req in requests:
		if not req is Dictionary:
			continue
		var idx := int((req as Dictionary).get("request_index", -1))
		if idx >= 0:
			by_index[idx] = req
	for i in range(entries.size()):
		var entry: Variant = entries[i]
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry as Dictionary
		var idx := int(row.get("index", i))
		var req: Dictionary = by_index.get(idx, requests[i] if i < requests.size() else {})
		if not req is Dictionary:
			continue
		var data_val: Variant = row.get("data")
		if data_val is Dictionary:
			_enforce_locked_id(req, data_val as Dictionary)


static func _enforce_locked_id(request: Dictionary, record: Dictionary) -> String:
	if not bool(request.get("lock_id", false)):
		return ""
	var expected := str(request.get("id", "")).strip_edges()
	if expected.is_empty():
		return ""
	var actual := str(record.get("id", "")).strip_edges()
	if actual != expected:
		return "`data.id` 必须等于 `%s`，实际为 `%s`" % [expected, actual]
	record["id"] = expected
	return ""


static func _validate_payload(data: Variant, schema_id: String) -> bool:
	if not data is Dictionary:
		return false
	var d: Dictionary = data
	if not d.get("data") is Dictionary:
		return false
	var sid := str(d.get("schema_id", "")).strip_edges()
	if not schema_id.is_empty() and not sid.is_empty() and sid != schema_id:
		return false
	return true


static func _parse_batch_entries(raw: String, expected_count: int) -> Array:
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if parsed is Dictionary:
		var entries: Variant = parsed.get("entries", null)
		if entries is Array and not entries.is_empty():
			return _normalize_batch_entries(entries as Array, expected_count)
		if _validate_payload(parsed, ""):
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


static func _merge_batch_results(requests: Array, stored_list: Array, raw_entries: Array) -> Array:
	var by_index: Dictionary = {}
	for i in range(raw_entries.size()):
		var entry: Variant = raw_entries[i]
		if entry is Dictionary:
			var idx := int(entry.get("index", i))
			by_index[idx] = i

	var out: Array = []
	for pos in range(requests.size()):
		var req: Dictionary = requests[pos] if requests[pos] is Dictionary else {}
		var idx: int = int(req.get("request_index", pos))
		var stored: Dictionary = {"ok": false, "error": "批量结果缺少对应 index"}
		var si := -1
		if by_index.has(idx):
			si = int(by_index[idx])
		elif pos < stored_list.size():
			si = pos
		if si >= 0 and si < stored_list.size() and stored_list[si] is Dictionary:
			stored = (stored_list[si] as Dictionary).duplicate(true)
		out.append(_decorate_result(stored, req))
	return out


static func _decorate_result(stored: Dictionary, request: Dictionary) -> Dictionary:
	var out := stored.duplicate(true)
	if request is Dictionary:
		if request.has("request_index"):
			out["request_index"] = request.get("request_index")
		if request.has("raw_token"):
			out["raw_token"] = request.get("raw_token")
		if request.has("category"):
			out["category"] = request.get("category")
		if request.has("source_context"):
			out["source_context"] = request.get("source_context")
		if not out.has("schema_id") or str(out.get("schema_id", "")).is_empty():
			out["schema_id"] = str(request.get("schema_id", ""))
	return out


static func _fail_result(request: Dictionary, error: String, raw: String = "") -> Dictionary:
	var out := _decorate_result({"ok": false, "error": error}, request)
	if not raw.is_empty():
		out["raw"] = raw
	return out


static func _batch_fail_all(requests: Array, error: String, raw: String = "") -> Array:
	var out: Array = []
	for req in requests:
		var row := _fail_result(req if req is Dictionary else {}, error, raw)
		out.append(row)
	return out


static func _retry_suffix(reason: String) -> String:
	return (
		"\n\n## 重试\n上次输出未通过：%s\n请修正后重新输出**一个完整且闭合**的 JSON 对象。"
		% reason.strip_edges()
	)


func _call_ai(messages: Array) -> String:
	if _request_ai_callable.is_valid():
		var result: Variant = await _request_ai_callable.call(messages)
		if result is String:
			return result as String
		if result is Dictionary:
			return str(result.get("text", ""))
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
		push_error("[ItemGenerationAgent] " + state["error"])
		return ""

	return state["text"]
