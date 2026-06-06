class_name TurnToolRegistry
extends RefCounted

## 回合工具注册表与 tool_request / tool_result 数据契约。

const TOOL_DYNAMIC_ADD := "dynamic_add"
const TOOL_ACTION_CHECK := "action_check"
const TOOL_STATE_HOOK := "state_hook"
const TOOL_UI_TEXT_SANITIZE := "ui_text_sanitize"

const ALL_TOOLS: Array[String] = [
	TOOL_DYNAMIC_ADD,
	TOOL_ACTION_CHECK,
	TOOL_STATE_HOOK,
	TOOL_UI_TEXT_SANITIZE,
]


static func normalize_request(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	var tool := str(d.get("tool", "")).strip_edges().to_lower()
	if tool.is_empty() or tool not in ALL_TOOLS:
		return {}
	var args: Variant = d.get("args", {})
	if not args is Dictionary:
		args = {}
	return {
		"tool": tool,
		"args": (args as Dictionary).duplicate(true),
		"reason": str(d.get("reason", "")).strip_edges(),
	}


static func make_result(
	tool: String,
	ok: bool,
	data: Dictionary = {},
	error: String = "",
) -> Dictionary:
	return {
		"tool": tool,
		"ok": ok,
		"data": data if data is Dictionary else {},
		"error": str(error).strip_edges(),
	}


static func collect_requests(parsed: Dictionary, story_text: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	var from_parsed: Variant = parsed.get("tool_requests", [])
	if from_parsed is Array:
		for item in from_parsed:
			var req := normalize_request(item)
			if req.is_empty():
				continue
			var key := _request_key(req)
			if seen.has(key):
				continue
			seen[key] = true
			out.append(req)
	_append_legacy_dyn_add_requests(story_text, out, seen)
	return out


static func build_protocol_prompt() -> String:
	var lines: PackedStringArray = [
		"## 回合工具协议（tool_requests）",
		"",
		"除 `story_text` 与状态字段外，可在 JSON 根级增加 `tool_requests` 数组。",
		"程序会**先执行工具**再应用状态；你不得伪造骰点、内部 id、BBCode 或未经工具确认的新实体数据。",
		"",
		"请求格式（每项）：",
		'{"tool":"工具名","args":{...},"reason":"简短说明"}',
		"",
		"可用工具：",
		"- `dynamic_add`：需要**库中不存在**的 NPC/地点/区域/物品/装备/技能时。",
		"  - args: `category`（如 NPC、物品）、`source_context`（来源说明）；或 `schema_id` + `source_context`。",
		"  - 仍可在 `story_text` 内写 `[[DYN_ADD:分类|来源]]`（兼容旧格式，程序会转换）。",
		"- `action_check`：仅当快照**无** `pending_check` 且行动可能需检定时请求；**禁止**自造 d20/合计/DC。",
		"  - args: `player_action`（默认用本轮玩家行动）。",
		"- `state_hook`：请求程序校验并规范化你拟写入的 STATE_HOOK 字段。",
		"  - args: `hook`（对象，含 datetime_display、weather、位置、inventory_delta 等）。",
		"- `ui_text_sanitize`：请求清洗 `story_text` / `suggestions` 中的伪富文本与内部 id 展示。",
		"  - args: `story_text`、`suggestions`（可选数组）。",
		"",
		"硬约束：",
		"- 禁止在 `story_text` 中输出 `[color]`、`[b]` 等 BBCode；判定展示由程序生成。",
		"- `suggestions` 不得含 `npc_` 前缀、region_id 等内部标识；用玩家可读中文名。",
		"- 新物品/NPC 须先 `dynamic_add` 或 `[[DYN_ADD:...]]`，再在 STATE_HOOK 中引用其 id。",
		"- 若快照已有 `pending_check`，必须按其 `outcome`/`total`/`dc` 叙述，勿再请求 `action_check` 重掷。",
	]
	return "\n".join(lines)


static func build_continuation_user_message(tool_results: Array) -> String:
	var lines: PackedStringArray = [
		"[系统] 下列工具已执行完毕。请**仅基于工具结果**输出最终 JSON（含 story_text 与状态字段），",
		"勿重复提交已完成的 tool_requests，勿输出未确认的数据。",
		"",
	]
	for item in tool_results:
		if not item is Dictionary:
			continue
		var row: Dictionary = item
		var tool := str(row.get("tool", ""))
		var ok: bool = row.get("ok", false)
		var err := str(row.get("error", "")).strip_edges()
		var data: Dictionary = row.get("data", {}) if row.get("data") is Dictionary else {}
		if ok:
			lines.append("- [%s] 成功: %s" % [tool, JSON.stringify(data)])
		else:
			lines.append("- [%s] 失败: %s" % [tool, err if not err.is_empty() else "未知错误"])
	return "\n".join(lines)


static func _request_key(req: Dictionary) -> String:
	var tool := str(req.get("tool", ""))
	var args: Dictionary = req.get("args", {}) if req.get("args") is Dictionary else {}
	return "%s|%s" % [tool, JSON.stringify(args)]


static func _append_legacy_dyn_add_requests(story_text: String, out: Array, seen: Dictionary) -> void:
	var triggers: Array = DynamicAddTriggerParserScript.find_all(story_text)
	for req_obj in triggers:
		if req_obj == null:
			continue
		var trigger_req = req_obj
		var normalized := normalize_request({
			"tool": TOOL_DYNAMIC_ADD,
			"args": {
				"category": trigger_req.category_raw,
				"schema_id": trigger_req.schema_id,
				"source_context": trigger_req.source_context,
				"raw_token": trigger_req.raw_token,
			},
			"reason": "legacy DYN_ADD marker",
		})
		if normalized.is_empty():
			continue
		var key := _request_key(normalized)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(normalized)


const DynamicAddTriggerParserScript := preload(
	"res://src/ai_skills/dynamic_add_trigger_parser.gd"
)
