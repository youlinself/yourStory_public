class_name DynamicAddPromptBuilder
extends RefCounted

## 构建 dynamic_add 的分层提示词，避免每次把全部 schema JSON 打进上下文。
##
## - build_routing_prompt()：常驻（routing.md + schemas_index 路由表）
## - build_generation_prompt(schema_id)：拦截技能后按需注入单个 schema

const SKILLS_DIR := "res://ai_config/AiSkills/"
const ROUTING_MD := SKILLS_DIR + "dynamic_add.routing.md"
const SCHEMAS_DIR := SKILLS_DIR + "dynamic_add_schemas/"
const INDEX_PATH := SCHEMAS_DIR + "schemas_index.json"

const ResTextFileScript := preload("res://src/io/res_text_file.gd")
const DynamicAddRegistry = preload("res://src/ai_skills/dynamic_add_registry.gd")
const DynamicAddTriggerParser = preload("res://src/ai_skills/dynamic_add_trigger_parser.gd")
const ItemSettingGuardScript := preload("res://src/game/logic/data/item_setting_guard.gd")

const LOOT_SCHEMA_IDS: Array[String] = ["loot_item", "loot_weapon"]


## 技能注册段：告诉 AI 有哪些分类、如何输出 [[DYN_ADD:...]]（常驻系统提示用）。
static func build_registration_prompt() -> String:
	var lines: PackedStringArray = [
		"## 已注册技能：dynamic_add（运行时动态增加数据）",
		"",
		"当剧情需要**尚未存在于数据库**的物品、装备、技能、NPC、区域或子地点时，在 `story_text` 中嵌入**标记**（可夹在叙事句末），格式：",
		"`[[DYN_ADD:分类|来源与要点说明]]`",
		"",
		"分类（任选其一字面，区分大小写不敏感）：",
		DynamicAddRegistry.list_categories_for_prompt(),
		"",
		"规则：",
		"- **叙事与数据同轮绑定**：首次写出可对话的新 NPC、可前往的新地名时，**必须**打对应标记，禁止只写正文不维护数据。",
		"- **新 NPC**：`[[DYN_ADD:NPC|周德海，证人，南郊康宁小区501]]`",
		"- **新子地点**（小区/楼栋/店铺）：`[[DYN_ADD:子地点|康宁小区7栋501，住宅，属南郊/某 region_id]]`",
		"- **新区域**（全新城区）：`[[DYN_ADD:区域|南郊，城郊住宅带，邻接老城区]]`",
		"- 只输出标记请求动态生成，**不要**在本轮输出完整 JSON 属性；程序入库后再应用 STATE_HOOK。",
		"- `|` 后为来源/风味说明，越具体越好。",
		"- **同一轮回复可输出多条标记**；**最多 %d 条**，超出将被程序丢弃。" % DynamicAddRegistry.get_max_per_response(),
		"- 已存在于库中的同名事物勿重复标记。",
		"- 普通对话、已知实体不要使用该标记。",
		"",
		"示例：",
	]
	for ex in DynamicAddRegistry.get_trigger_examples():
		lines.append("- " + ex)
	for ex in DynamicAddRegistry.get_multi_examples():
		lines.append("- " + ex)
	return "\n".join(lines)


static func build_routing_prompt() -> String:
	var routing := _read_text(ROUTING_MD)
	if routing.is_empty():
		push_error("无法读取: " + ROUTING_MD)
		return ""

	var index: Variant = _load_json(INDEX_PATH)
	if index == null:
		return routing

	var table := _format_routing_table(index)
	if table.is_empty():
		return routing
	return routing.strip_edges() + "\n\n### 路由表（来自 schemas_index.json）\n\n" + table


static func build_generation_prompt(schema_id: String) -> String:
	var schema_id_clean := schema_id.strip_edges()
	if schema_id_clean.is_empty():
		push_error("build_generation_prompt: schema_id 为空")
		return ""

	var schema: Variant = load_schema(schema_id_clean)
	if schema == null:
		return ""

	var parts: PackedStringArray = []
	parts.append("## dynamic_add 生成轮 — schema: `%s`" % schema_id_clean)

	var reuse_path: String = str(schema.get("reuse_config_path", "")).strip_edges()
	if not reuse_path.is_empty():
		var reused: Variant = _load_json(reuse_path)
		if reused != null:
			parts.append("### 字段定义（复用已有配置）\n\n```json\n%s\n```" % JSON.stringify(reused, "  "))

	var compact: Variant = schema.get("prompt_compact", null)
	if compact != null:
		parts.append("### 输出 data 模板（填满后作为 response.data）\n\n```json\n%s\n```" % JSON.stringify(compact, "  "))

	var rules: Variant = schema.get("generation_rules", [])
	if rules is Array and not rules.is_empty():
		var lines: PackedStringArray = []
		for rule in rules:
			lines.append("- " + str(rule))
		parts.append("### 生成规则\n\n" + "\n".join(lines))

	return "\n\n".join(parts)


## 生成轮发给 AI 的 user 消息（由 DynamicAddService 在拦截标记后调用）。
static func build_generation_user_message(
	schema_id: String,
	source_context: String = "",
	world_context: String = "",
) -> String:
	var schema_block := build_generation_prompt(schema_id)
	if schema_block.is_empty():
		return ""

	var parts: PackedStringArray = [
		"你是游戏运行时数据生成器。根据下方 schema 生成**一条**记录。",
		"**只输出纯 JSON**，不要用 markdown 代码围栏，不要解释。",
		"",
		schema_block,
		"",
	]
	if schema_id.strip_edges() in LOOT_SCHEMA_IDS:
		parts.append_array(_loot_consistency_prompt_lines())
		parts.append("")
	parts.append("### 上下文")
	parts.append("- schema_id: `%s`" % schema_id.strip_edges())
	if not source_context.strip_edges().is_empty():
		parts.append("- 来源: %s" % source_context.strip_edges())
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


## 多条标记合并为一次生成请求（entries 与请求序号一一对应）。
static func build_batch_generation_user_message(
	requests: Array,
	world_context: String = "",
) -> String:
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
		var req: DynamicAddTriggerParser.TriggerRequest = requests[i]
		var idx := req.request_index if req.request_index >= 0 else i
		parts.append(
			"%d. schema_id=`%s`，分类=`%s`，来源：%s"
			% [
				idx,
				req.schema_id,
				req.category_raw,
				req.source_context if not req.source_context.is_empty() else "（未说明）",
			]
		)
		schema_ids_seen[req.schema_id] = true

	parts.append("")
	parts.append("### 各类型 schema（仅包含本批涉及的类型）")
	for schema_id: String in schema_ids_seen:
		var block := build_generation_prompt(schema_id)
		if not block.is_empty():
			parts.append(block)

	if _batch_includes_loot(schema_ids_seen):
		parts.append("")
		parts.append_array(_loot_consistency_prompt_lines())

	if not world_context.strip_edges().is_empty():
		parts.append("")
		parts.append("### 世界观设定\n\n%s" % world_context.strip_edges())

	parts.append("")
	parts.append("### 输出格式（严格遵守）")
	var sample_entries: Array = []
	for i in range(requests.size()):
		var req: DynamicAddTriggerParser.TriggerRequest = requests[i]
		sample_entries.append({
			"index": req.request_index if req.request_index >= 0 else i,
			"schema_id": req.schema_id,
			"status": "new_created",
			"data": {},
		})
	parts.append(JSON.stringify({"entries": sample_entries}, "\t"))
	parts.append(
		"`entries` 长度必须等于待生成条数（%d）；`index` 与上文编号一致；每条 `data` 按该条 schema 模板填满。"
		% requests.size()
	)
	return "\n".join(parts)


static func load_schema(schema_id: String) -> Dictionary:
	var path := SCHEMAS_DIR + schema_id + ".json"
	var data: Variant = _load_json(path)
	if data is Dictionary:
		return data
	push_error("未找到 schema: %s (%s)" % [schema_id, path])
	return {}


static func list_schema_ids() -> Array[String]:
	var index: Variant = _load_json(INDEX_PATH)
	if not index is Dictionary:
		return []
	var schemas: Variant = index.get("schemas", [])
	if not schemas is Array:
		return []
	var ids: Array[String] = []
	for entry in schemas:
		if entry is Dictionary:
			var id := str(entry.get("schema_id", "")).strip_edges()
			if not id.is_empty():
				ids.append(id)
	return ids


static func _format_routing_table(index: Dictionary) -> String:
	var schemas: Variant = index.get("schemas", [])
	if not schemas is Array:
		return ""
	var lines: PackedStringArray = ["| schema_id | 目标库 | 选用时机 |", "|-----------|--------|----------|"]
	for entry in schemas:
		if not entry is Dictionary:
			continue
		var id := str(entry.get("schema_id", ""))
		var db := str(entry.get("target_db", ""))
		var when: Variant = entry.get("when_to_use", [])
		var when_text := ""
		if when is Array:
			var parts: PackedStringArray = []
			for item in when:
				parts.append(str(item))
			when_text = "；".join(parts)
		if when_text.is_empty():
			when_text = str(entry.get("summary", ""))
		lines.append("| `%s` | %s | %s |" % [id, db, when_text])
	return "\n".join(lines)


static func loot_consistency_prompt_lines() -> PackedStringArray:
	return PackedStringArray([
		"### 设定一致性（必守）",
		ItemSettingGuardScript.setting_consistency_rule_blurb(),
		"以本消息中的「世界观设定」与「来源」为准，不要脱离本轮场景。",
		ItemSettingGuardScript.item_id_format_hint(),
	])


static func _loot_consistency_prompt_lines() -> PackedStringArray:
	return loot_consistency_prompt_lines()


static func _batch_includes_loot(schema_ids_seen: Dictionary) -> bool:
	for schema_id: String in LOOT_SCHEMA_IDS:
		if schema_ids_seen.has(schema_id):
			return true
	return false


static func _read_text(path: String) -> String:
	return ResTextFileScript.read(path)


static func _load_json(path: String) -> Variant:
	return ResTextFileScript.read_json(path)
