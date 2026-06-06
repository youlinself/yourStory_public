class_name AiResponseParser
extends RefCounted

const LocalGridBuilderScript := preload("res://src/novel_config/local_grid_builder.gd")


static func extract_message_content(response: Dictionary) -> String:
	var message_text := extract_choice_message_content(response)
	if not message_text.is_empty():
		return message_text
	if response.has("message"):
		var msg: Variant = response["message"]
		if msg is Dictionary:
			return str(msg.get("content", "")).strip_edges()
	if response.has("content"):
		return str(response["content"]).strip_edges()
	return ""


## OpenAI 兼容响应中的 assistant 正文（未合并顶层 content）。
static func extract_choice_message_content(response: Dictionary) -> String:
	if response.is_empty():
		return ""
	if not response.has("choices"):
		return ""
	var choices: Variant = response["choices"]
	if not choices is Array or choices.is_empty():
		return ""
	var first: Variant = choices[0]
	if not first is Dictionary:
		return ""
	var message: Variant = (first as Dictionary).get("message", {})
	if message is Dictionary:
		return str(message.get("content", "")).strip_edges()
	return ""


## 后端清洗后抽出的 JSON 块（叙事回合的 STATE_HOOK 常在此字段）。
static func extract_top_level_content(response: Dictionary) -> String:
	if response.is_empty():
		return ""
	return str(response.get("content", "")).strip_edges()


## 世界初始化等 JSON 任务：优先选用可解析的 assistant 正文。
## 后端常把清洗后的 JSON 放在顶层 content，而 choices.message.content 仍含推理 prose。
static func extract_json_task_content(response: Dictionary) -> String:
	var from_choice := extract_choice_message_content(response)
	var from_top := extract_top_level_content(response)
	if from_choice.is_empty():
		return from_top
	if from_top.is_empty():
		return from_choice
	if from_top == from_choice:
		return from_choice
	var parsed_choice: Variant = parse_json_from_ai_text(from_choice)
	var parsed_top: Variant = parse_json_from_ai_text(from_top)
	if parsed_top != null and parsed_choice != null:
		return from_top if from_top.length() > from_choice.length() else from_choice
	if parsed_top != null:
		return from_top
	return from_choice


## 从 API 响应中提取 error / message 等错误说明（若存在）。
static func extract_api_error(response: Dictionary) -> String:
	if response.is_empty():
		return ""
	for key in ["error", "message", "detail", "msg"]:
		if not response.has(key):
			continue
		var val: Variant = response[key]
		if val is Dictionary:
			var nested := str(val.get("message", val.get("detail", ""))).strip_edges()
			if not nested.is_empty():
				return nested
		else:
			var text := str(val).strip_edges()
			if not text.is_empty() and text.to_lower() != "ok":
				return text
	if response.has("choices"):
		var choices: Variant = response["choices"]
		if choices is Array and not choices.is_empty():
			var first: Variant = choices[0]
			if first is Dictionary:
				var finish := str((first as Dictionary).get("finish_reason", "")).strip_edges()
				if finish == "error" or finish == "content_filter":
					return "choices.finish_reason=%s" % finish
	return ""


static func format_text_preview(text: String, max_len: int = 800) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return "(empty)"
	if trimmed.length() <= max_len:
		return trimmed
	return trimmed.substr(0, max_len) + "…(truncated %d chars)" % (trimmed.length() - max_len)


## 调试日志：摘要 API 响应各字段，便于排查 JSON 解析失败。
static func format_response_debug(response: Dictionary, max_body_len: int = 600) -> String:
	if response.is_empty():
		return "(empty response)"
	var lines: PackedStringArray = []
	var api_err := extract_api_error(response)
	if not api_err.is_empty():
		lines.append("api_error: " + api_err)
	var choice := extract_choice_message_content(response)
	var top := extract_top_level_content(response)
	lines.append("choice_content_len=%d top_content_len=%d" % [choice.length(), top.length()])
	if not choice.is_empty():
		lines.append("choice_preview: " + format_text_preview(choice, max_body_len))
	if not top.is_empty() and top != choice:
		lines.append("top_content_preview: " + format_text_preview(top, max_body_len))
	var reasoning := str(response.get("reasoning_content", "")).strip_edges()
	if reasoning.is_empty() and response.has("choices"):
		var choices: Variant = response["choices"]
		if choices is Array and not choices.is_empty():
			var first: Variant = choices[0]
			if first is Dictionary:
				var msg: Variant = (first as Dictionary).get("message", {})
				if msg is Dictionary:
					reasoning = str(msg.get("reasoning_content", "")).strip_edges()
	if not reasoning.is_empty():
		lines.append("reasoning_len=%d preview: %s" % [reasoning.length(), format_text_preview(reasoning, 200)])
	return "\n".join(lines)


static func strip_markdown_json_fence(text: String) -> String:
	var t := text.strip_edges()
	if not t.begins_with("```"):
		return t
	var lines := t.split("\n", false)
	if lines.is_empty():
		return t
	if lines[0].begins_with("```"):
		lines.remove_at(0)
	while not lines.is_empty() and lines[-1].strip_edges() == "```":
		lines.remove_at(lines.size() - 1)
	return "\n".join(lines).strip_edges()


static func parse_json_from_ai_text(text: String) -> Variant:
	var cleaned := strip_markdown_json_fence(text)
	if cleaned.is_empty():
		return null
	var block := extract_json_block(cleaned)
	var outer := extract_outermost_json_object(cleaned)
	var outer_from_block := extract_outermost_json_object(block)
	return _parse_json_candidates_with_repairs(
		[cleaned, block, outer, outer_from_block],
	)


## 阶段 3 子步编号（与 WorldInitDraft 一致，避免循环 preload）。
const WB_SUB_MAP_PAGE := 2
const WB_SUB_PROTAGONIST := 5
const WB_SUB_KEY_NPC := 6

const NPC_SKILLS_MIN_COUNT := 1
const NPC_SKILLS_MAX_COUNT := 6


## 将 AI 常见误形状规范为各子步期望的顶层字段；传入 skills_db 时顺带修复角色卡 skills。
static func normalize_world_build_substep_payload(
	sub: int,
	data: Variant,
	skills_db: Variant = null,
) -> Variant:
	if not data is Dictionary:
		return data
	var d: Dictionary = (data as Dictionary).duplicate(true)
	match sub:
		WB_SUB_MAP_PAGE:
			if d.has("map_page"):
				return d
			if _looks_like_local_map_page_spec(d):
				return {"map_page": d}
		WB_SUB_PROTAGONIST:
			d = _shape_protagonist_payload(d)
			if skills_db != null:
				d = _normalize_protagonist_skills_and_npcs(d, skills_db)
			return d
		WB_SUB_KEY_NPC:
			d = _shape_key_npc_payload(d)
			if skills_db != null:
				d = _normalize_key_npc_skills(d, skills_db)
			return d
	return d


static func _shape_protagonist_payload(d: Dictionary) -> Dictionary:
	if d.has("protagonist_id") and d.has("npcs"):
		return d
	var npcs_val: Variant = d.get("npcs", null)
	if npcs_val is Array and not (npcs_val as Array).is_empty():
		var first: Variant = (npcs_val as Array)[0]
		if first is Dictionary and not d.has("protagonist_id"):
			var pid := str((first as Dictionary).get("id", "")).strip_edges()
			if not pid.is_empty():
				d["protagonist_id"] = pid
				return d
	if _looks_like_character_card(d):
		var char_id := str(d.get("id", "")).strip_edges()
		if not char_id.is_empty():
			return {"protagonist_id": char_id, "npcs": [d]}
	return d


static func _shape_key_npc_payload(d: Dictionary) -> Dictionary:
	if d.has("npcs"):
		return d
	if _looks_like_character_card(d):
		return {"npcs": [d]}
	return d


static func _normalize_protagonist_skills_and_npcs(d: Dictionary, skills_db: Variant) -> Dictionary:
	var pid := str(d.get("protagonist_id", "")).strip_edges()
	var npcs_val: Variant = d.get("npcs", null)
	if not npcs_val is Array or (npcs_val as Array).is_empty():
		return d
	var npcs: Array = npcs_val
	var chosen: Dictionary = {}
	if npcs.size() == 1 and npcs[0] is Dictionary:
		chosen = (npcs[0] as Dictionary).duplicate(true)
	else:
		for raw in npcs:
			if not raw is Dictionary:
				continue
			var cand: Dictionary = raw as Dictionary
			var cid := str(cand.get("id", "")).strip_edges()
			if not pid.is_empty() and cid == pid:
				chosen = cand.duplicate(true)
				break
		if chosen.is_empty() and npcs[0] is Dictionary:
			chosen = (npcs[0] as Dictionary).duplicate(true)
	if chosen.is_empty():
		return d
	if pid.is_empty():
		pid = str(chosen.get("id", "")).strip_edges()
	chosen = normalize_role_card_npc(chosen, skills_db)
	d["protagonist_id"] = pid
	d["npcs"] = [chosen]
	return d


static func _normalize_key_npc_skills(d: Dictionary, skills_db: Variant) -> Dictionary:
	var npcs_val: Variant = d.get("npcs", null)
	if not npcs_val is Array or (npcs_val as Array).is_empty():
		return d
	var first: Variant = (npcs_val as Array)[0]
	if first is Dictionary:
		d["npcs"] = [normalize_role_card_npc(first as Dictionary, skills_db)]
	return d


static func normalize_role_card_npc(npc: Dictionary, skills_db: Variant) -> Dictionary:
	var out := npc.duplicate(true)
	out["skills"] = normalize_npc_skills_array(out.get("skills", []), skills_db)
	return out


static func normalize_npc_skills_array(skills_val: Variant, skills_db: Variant) -> Array:
	if not skills_db is Dictionary:
		return skills_val if skills_val is Array else []
	var allowed: Dictionary = _skill_id_lookup(skills_db as Dictionary)
	if allowed.is_empty():
		return []
	var name_lookup: Dictionary = _skill_name_to_id_lookup(skills_db as Dictionary)
	var out: Array = []
	var seen: Dictionary = {}
	if not skills_val is Array:
		return out
	for entry in skills_val:
		var sid := _normalize_skill_entry_to_id(entry, allowed, name_lookup)
		if sid.is_empty() or seen.has(sid):
			continue
		seen[sid] = true
		out.append(sid)
		if out.size() >= NPC_SKILLS_MAX_COUNT:
			break
	if out.size() < NPC_SKILLS_MIN_COUNT:
		var padded := _pad_npc_skills_to_minimum(out, allowed, seen)
		if padded.size() > out.size():
			push_warning(
				"[AiResponseParser] NPC skills 不足 %d 个，已从技能库补足至 %d 个"
				% [NPC_SKILLS_MIN_COUNT, padded.size()],
			)
		out = padded
	return out


static func _pad_npc_skills_to_minimum(
	current: Array,
	allowed: Dictionary,
	seen: Dictionary,
) -> Array:
	var out := current.duplicate()
	var keys: Array = allowed.keys()
	keys.sort()
	for key in keys:
		if out.size() >= NPC_SKILLS_MIN_COUNT:
			break
		var sid := str(key).strip_edges()
		if sid.is_empty() or seen.has(sid):
			continue
		seen[sid] = true
		out.append(sid)
	return out


static func _normalize_skill_entry_to_id(
	entry: Variant,
	allowed: Dictionary,
	name_lookup: Dictionary,
) -> String:
	if entry is Dictionary:
		var row: Dictionary = entry
		var sid := str(row.get("id", "")).strip_edges()
		if not sid.is_empty():
			if allowed.has(sid):
				return sid
			var ci_row := _resolve_skill_id_case_insensitive(sid, allowed)
			if not ci_row.is_empty():
				return ci_row
		var by_name := str(row.get("name", "")).strip_edges()
		if not by_name.is_empty():
			if name_lookup.has(by_name):
				return str(name_lookup[by_name]).strip_edges()
			var nk_row := _skill_name_lookup_key(by_name)
			if name_lookup.has(nk_row):
				return str(name_lookup[nk_row]).strip_edges()
		return ""
	var text := str(entry).strip_edges()
	if text.is_empty():
		return ""
	if allowed.has(text):
		return text
	var ci := _resolve_skill_id_case_insensitive(text, allowed)
	if not ci.is_empty():
		return ci
	if name_lookup.has(text):
		return str(name_lookup[text]).strip_edges()
	var name_key := _skill_name_lookup_key(text)
	if not name_key.is_empty() and name_lookup.has(name_key):
		return str(name_lookup[name_key]).strip_edges()
	return ""


static func _skill_name_to_id_lookup(skills_db: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var skills_val: Variant = skills_db.get("skills", null)
	if skills_val is Dictionary:
		for skill_id: String in skills_val:
			var entry: Variant = skills_val[skill_id]
			if not entry is Dictionary:
				continue
			var sid := skill_id.strip_edges()
			var display := str((entry as Dictionary).get("name", "")).strip_edges()
			if not display.is_empty():
				lookup[display] = sid
	elif skills_val is Array:
		for item in skills_val:
			if item is Dictionary:
				var sid := str(item.get("id", "")).strip_edges()
				var display := str(item.get("name", "")).strip_edges()
				if not sid.is_empty() and not display.is_empty():
					lookup[display] = sid
					var norm := _skill_name_lookup_key(display)
					if not norm.is_empty() and norm != display:
						lookup[norm] = sid
	return lookup


static func _skill_name_lookup_key(display: String) -> String:
	var s := display.strip_edges()
	if s.is_empty():
		return ""
	for ch in [" ", "\t", "，", "。", "、", "；", "：", "（", "）", "(", ")", "·"]:
		s = s.replace(ch, "")
	return s


static func _resolve_skill_id_case_insensitive(skill_id: String, allowed: Dictionary) -> String:
	var lower := skill_id.to_lower()
	for key in allowed:
		if str(key).to_lower() == lower:
			return str(key).strip_edges()
	return ""


static func _sample_skill_ids(allowed: Dictionary, max_count: int = 8) -> PackedStringArray:
	var out: PackedStringArray = []
	var keys: Array = allowed.keys()
	keys.sort()
	var limit := mini(max_count, keys.size())
	if keys.size() <= 12:
		limit = keys.size()
	for i in limit:
		out.append(str(keys[i]))
	return out


static func describe_npc_skills_db_failure(
	npc: Dictionary,
	skills_db: Variant,
	field_prefix: String = "npcs[0]",
) -> String:
	if not skills_db is Dictionary:
		return "%s.skills 技能库无效" % field_prefix
	var allowed: Dictionary = _skill_id_lookup(skills_db as Dictionary)
	if allowed.is_empty():
		return "%s.skills 技能库为空" % field_prefix

	var skills_val: Variant = npc.get("skills", [])
	if not skills_val is Array:
		return "%s.skills 须为 id 字符串数组" % field_prefix

	var skills: Array = skills_val
	var invalid: Array = []
	var current: Array = []
	for entry in skills:
		var display := _format_skill_entry_for_message(entry)
		current.append(display)
		var sid := str(entry).strip_edges()
		if entry is Dictionary:
			var row: Dictionary = entry
			sid = str(row.get("id", "")).strip_edges()
			if sid.is_empty() or not allowed.has(sid):
				var by_name := str(row.get("name", "")).strip_edges()
				if not by_name.is_empty():
					var name_lookup := _skill_name_to_id_lookup(skills_db as Dictionary)
					if name_lookup.has(by_name):
						sid = str(name_lookup[by_name]).strip_edges()
					else:
						var nk := _skill_name_lookup_key(by_name)
						if name_lookup.has(nk):
							sid = str(name_lookup[nk]).strip_edges()
		if sid.is_empty():
			sid = _resolve_skill_id_case_insensitive(str(entry).strip_edges(), allowed)
		if sid.is_empty() or not allowed.has(sid):
			invalid.append(display)

	if invalid.is_empty():
		return "%s.skills 须为 %d–%d 个且均存在于技能库中" % [
			field_prefix,
			NPC_SKILLS_MIN_COUNT,
			NPC_SKILLS_MAX_COUNT,
		]

	var sample := ", ".join(_sample_skill_ids(allowed, 8))
	var lines: PackedStringArray = [
		"%s.skills 中以下项不在技能库中：%s" % [field_prefix, JSON.stringify(invalid)],
		"当前 %s.skills：%s" % [field_prefix, JSON.stringify(current)],
		"请改为仅从技能库复制 id（%d–%d 个）。合法 id 示例：%s"
		% [NPC_SKILLS_MIN_COUNT, NPC_SKILLS_MAX_COUNT, sample],
	]
	return "\n".join(lines)


static func _format_skill_entry_for_message(entry: Variant) -> String:
	if entry is Dictionary:
		var row: Dictionary = entry
		var sid := str(row.get("id", "")).strip_edges()
		var sname := str(row.get("name", "")).strip_edges()
		if not sid.is_empty() and not sname.is_empty():
			return "%s (%s)" % [sid, sname]
		if not sid.is_empty():
			return sid
		if not sname.is_empty():
			return sname
	return str(entry).strip_edges()


static func repair_json_text(text: String) -> String:
	var out := text
	out = out.replace(",\n}", "\n}")
	out = out.replace(",\n]", "\n]")
	out = out.replace(", }", " }")
	out = out.replace(", ]", " ]")
	return out


## 将 JSON 字符串字面量内的裸换行/制表符转为转义序列（AI 常犯）。
static func escape_control_chars_in_json_strings(text: String) -> String:
	if text.is_empty():
		return text
	var parts: PackedStringArray = []
	var in_string := false
	var escaped := false
	for i in text.length():
		var ch: String = text.substr(i, 1)
		if not in_string:
			parts.append(ch)
			if ch == "\"":
				in_string = true
			continue
		if escaped:
			parts.append(ch)
			escaped = false
			continue
		if ch == "\\":
			parts.append(ch)
			escaped = true
			continue
		if ch == "\"":
			parts.append(ch)
			in_string = false
			continue
		if ch == "\n":
			parts.append("\\n")
			continue
		if ch == "\r":
			parts.append("\\r")
			continue
		if ch == "\t":
			parts.append("\\t")
			continue
		parts.append(ch)
	if in_string:
		parts.append("\"")
	return "".join(parts)


## 闭合因 token 截断而未结束的 JSON 对象/数组（尽力而为）。
static func repair_truncated_json_text(text: String) -> String:
	var block := extract_json_block(text)
	if block.is_empty():
		return text
	var start_obj := block.find("{")
	var start_arr := block.find("[")
	var start := -1
	if start_obj >= 0 and (start_arr < 0 or start_obj <= start_arr):
		start = start_obj
	elif start_arr >= 0:
		start = start_arr
	else:
		return block
	var slice := block.substr(start)
	var closers: Array[String] = []
	var in_string := false
	var escaped := false
	for i in slice.length():
		var ch: String = slice.substr(i, 1)
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				in_string = false
			continue
		if ch == "\"":
			in_string = true
			continue
		if ch == "{":
			closers.append("}")
		elif ch == "[":
			closers.append("]")
		elif ch == "}" or ch == "]":
			if not closers.is_empty() and closers[-1] == ch:
				closers.resize(closers.size() - 1)
	var out := slice
	if in_string:
		out += "\""
	while not closers.is_empty():
		out += closers.pop_back()
	return out


static func _parse_json_candidates_with_repairs(candidates: Array) -> Variant:
	var tried: Dictionary = {}
	for raw in candidates:
		var base := str(raw).strip_edges()
		if base.is_empty() or tried.has(base):
			continue
		tried[base] = true
		for variant in _json_repair_variants(base):
			var parsed: Variant = _try_parse_json_text(variant)
			if parsed != null:
				return parsed
	return null


static func _json_repair_variants(text: String) -> Array[String]:
	var ordered: Array[String] = [
		text,
		escape_control_chars_in_json_strings(text),
		repair_json_text(text),
		escape_control_chars_in_json_strings(repair_json_text(text)),
		repair_truncated_json_text(text),
		repair_truncated_json_text(escape_control_chars_in_json_strings(repair_json_text(text))),
	]
	var seen: Dictionary = {}
	var out: Array[String] = []
	for item in ordered:
		if item.is_empty() or seen.has(item):
			continue
		seen[item] = true
		out.append(item)
	return out


static func _looks_like_local_map_page_spec(data: Dictionary) -> bool:
	return (
		data.has("width")
		and data.has("height")
		and str(data.get("parent_type", "")).strip_edges() in ["region", "key_node"]
	)


static func _looks_like_character_card(data: Dictionary) -> bool:
	var id_ok := not str(data.get("id", "")).strip_edges().is_empty()
	var name_ok := not str(data.get("name", "")).strip_edges().is_empty()
	return id_ok and name_ok and (data.has("abilities") or data.has("skills"))


## 从文本中提取最外层 JSON 对象（首 `{` 至末 `}`），用于说明文字包裹的响应。
static func extract_outermost_json_object(text: String) -> String:
	var trimmed := text.strip_edges()
	var first := trimmed.find("{")
	var last := trimmed.rfind("}")
	if first < 0 or last <= first:
		return ""
	return trimmed.substr(first, last - first + 1).strip_edges()


## 从 prose 包裹的文本中提取首个完整 JSON 对象或数组。
static func extract_json_block(text: String) -> String:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.begins_with("{") or trimmed.begins_with("["):
		return trimmed

	var obj_idx := trimmed.find("{")
	var arr_idx := trimmed.find("[")
	var start := -1
	var open_ch := ""
	var close_ch := ""

	if obj_idx >= 0 and (arr_idx < 0 or obj_idx <= arr_idx):
		start = obj_idx
		open_ch = "{"
		close_ch = "}"
	elif arr_idx >= 0:
		start = arr_idx
		open_ch = "["
		close_ch = "]"
	else:
		return trimmed

	var depth := 0
	var in_string := false
	var escaped := false
	for i in range(start, trimmed.length()):
		var ch: String = trimmed.substr(i, 1)
		if in_string:
			if escaped:
				escaped = false
			elif ch == "\\":
				escaped = true
			elif ch == "\"":
				in_string = false
			continue
		if ch == "\"":
			in_string = true
			continue
		if ch == open_ch:
			depth += 1
		elif ch == close_ch:
			depth -= 1
			if depth == 0:
				return trimmed.substr(start, i - start + 1).strip_edges()

	return trimmed


static func _try_parse_json_text(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return null
	if not trimmed.begins_with("{") and not trimmed.begins_with("["):
		return null
	var json := JSON.new()
	if json.parse(trimmed) != OK:
		return null
	return json.data


## 将阶段 1 AI 常见误返回形状规范为 { novel_type: string, world_setting: {} }。
static func normalize_base_config_response(data: Variant, selected_novel_type: String) -> Dictionary:
	if not data is Dictionary:
		return {}
	var d: Dictionary = (data as Dictionary).duplicate(true)
	var selected := selected_novel_type.strip_edges()

	if d.has("novel_type"):
		var novel_type_val: Variant = d["novel_type"]
		if novel_type_val is Array:
			var resolved := _resolve_novel_type_from_array(novel_type_val as Array, selected)
			if not resolved.is_empty():
				d["novel_type"] = resolved
	elif not selected.is_empty():
		d["novel_type"] = selected

	var world_val: Variant = d.get("world_setting", null)
	if world_val == null or not world_val is Dictionary:
		for alt_key in ["base_config", "world_setting_schema"]:
			if not d.has(alt_key):
				continue
			var alt: Variant = d[alt_key]
			if alt is Dictionary and _looks_like_world_setting(alt as Dictionary):
				d["world_setting"] = (alt as Dictionary).duplicate(true)
				break

	for stray_key in ["base_config", "world_setting_schema"]:
		if stray_key in d and d.has("world_setting"):
			d.erase(stray_key)

	return d


static func describe_base_config_validation_failure(data: Variant, parsed_ok: bool) -> String:
	if not parsed_ok or data == null:
		return "阶段 1 AI 返回的内容无法解析为 JSON"
	if not data is Dictionary:
		return "阶段 1 AI 返回的 JSON 须为对象"
	var d: Dictionary = data
	if d.has("novel_type") and d["novel_type"] is Array:
		return "阶段 1 AI 返回的 novel_type 不能为候选数组，须为本次主题的字符串"
	if not d.has("novel_type") or str(d.get("novel_type", "")).strip_edges().is_empty():
		return "阶段 1 AI 返回的 JSON 缺少非空 novel_type"
	if d.has("base_config") and (not d.has("world_setting") or not d["world_setting"] is Dictionary):
		return "阶段 1 AI 返回使用了 base_config 字段，须改为 world_setting（结构应与模板一致）"
	if not d.has("world_setting") or not d["world_setting"] is Dictionary:
		return "阶段 1 AI 返回的 JSON 缺少 world_setting 对象"
	return "阶段 1 AI 返回的 JSON 无效（需要 novel_type 与 world_setting）"


static func validate_base_config(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var d: Dictionary = data
	if not d.has("novel_type"):
		return false
	var novel_type_val: Variant = d["novel_type"]
	if novel_type_val is Array:
		return false
	if str(novel_type_val).strip_edges().is_empty():
		return false
	if not d.has("world_setting"):
		return false
	return d["world_setting"] is Dictionary


## 阶段 1 分片校验：slice 1=nature_env, 2=people_env, 3=social_env。
static func validate_base_config_slice(slice: int, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var field_key := _base_config_slice_field_key(slice)
	if field_key.is_empty():
		return false
	if not data.has(field_key):
		return false
	var section_val: Variant = data[field_key]
	if not section_val is Dictionary:
		return false
	var section: Dictionary = section_val
	var required_keys: Array[String] = _base_config_slice_required_keys(slice)
	for key in required_keys:
		if not section.has(key):
			return false
		var val: Variant = section[key]
		if key.ends_with("_keywords"):
			if not val is Array:
				return false
			continue
		if str(val).strip_edges().is_empty():
			return false
	return true


static func normalize_base_config_slice_payload(slice: int, data: Variant) -> Variant:
	if not data is Dictionary:
		return data
	var d: Dictionary = (data as Dictionary).duplicate(true)
	var field_key := _base_config_slice_field_key(slice)
	if field_key.is_empty():
		return d
	if d.has(field_key):
		return d
	if _looks_like_base_config_section(slice, d):
		return {field_key: d}
	return d


static func _base_config_slice_field_key(slice: int) -> String:
	match slice:
		1:
			return "nature_env"
		2:
			return "people_env"
		3:
			return "social_env"
		_:
			return ""


static func _base_config_slice_required_keys(slice: int) -> Array[String]:
	match slice:
		1:
			return [
				"weather", "weather_keywords", "landform", "start_time",
				"start_time_keywords", "universe", "biome",
			]
		2:
			return ["building", "traffic", "technology", "city&town"]
		3:
			return [
				"background", "politics&power", "econ&prod", "culture&customs",
				"relationships", "values&beliefs",
			]
		_:
			return []


static func _looks_like_base_config_section(slice: int, data: Dictionary) -> bool:
	var keys := _base_config_slice_required_keys(slice)
	if keys.is_empty():
		return false
	var hit := 0
	for key in keys:
		if data.has(key):
			hit += 1
	return hit >= maxi(1, int(ceil(keys.size() / 2.0)))


static func describe_base_config_slice_failure(slice: int, parsed_ok: bool) -> String:
	if not parsed_ok:
		return "阶段 1 分片 %d AI 返回的内容无法解析为 JSON" % slice
	return "阶段 1 分片 %d 校验失败（字段缺失或为空）" % slice


static func describe_base_config_slice_validation_failure(slice: int, data: Variant) -> String:
	var field_key := _base_config_slice_field_key(slice)
	if field_key.is_empty():
		return "无效的分片编号 %d" % slice
	if not data is Dictionary:
		return "分片 %d 须为 JSON 对象，且含顶层字段 `%s`" % [slice, field_key]
	var d: Dictionary = data
	if not d.has(field_key):
		return "分片 %d 缺少顶层字段 `%s`" % [slice, field_key]
	var section_val: Variant = d[field_key]
	if not section_val is Dictionary:
		return "分片 %d 的 `%s` 须为对象" % [slice, field_key]
	var section: Dictionary = section_val
	var required_keys: Array[String] = _base_config_slice_required_keys(slice)
	var missing: PackedStringArray = []
	var empty_fields: PackedStringArray = []
	for key in required_keys:
		if not section.has(key):
			missing.append(key)
			continue
		var val: Variant = section[key]
		if key.ends_with("_keywords"):
			if not val is Array:
				empty_fields.append("%s（须为数组）" % key)
			continue
		if str(val).strip_edges().is_empty():
			empty_fields.append(key)
	if not missing.is_empty():
		return "分片 %d `%s` 缺少字段：%s" % [slice, field_key, ", ".join(missing)]
	if not empty_fields.is_empty():
		return "分片 %d `%s` 以下字段为空或类型错误：%s" % [slice, field_key, ", ".join(empty_fields)]
	return describe_base_config_slice_failure(slice, true)


static func validate_skills_batch_payload(data: Variant) -> bool:
	return describe_skills_batch_validation_failure(data).is_empty()


static func describe_skills_batch_validation_failure(data: Variant) -> String:
	if data == null:
		return "AI 返回的内容无法解析为 JSON"
	if not data is Dictionary:
		return "JSON 须为对象 `{ \"skills\": [...] }`，不能为裸数组或其他类型"
	var d: Dictionary = data
	if not d.has("skills"):
		return "缺少顶层 skills 字段"
	var skills_val: Variant = d.get("skills", null)
	if skills_val == null:
		return "skills 不能为 null"
	if skills_val is Dictionary:
		if skills_val.is_empty():
			return "skills 对象 map 不能为空"
		return "skills 须为对象数组 [{...}]，不要用 id 为键的对象 map"
	if skills_val is String:
		return "skills 必须是对象数组，不能为字符串"
	if not skills_val is Array:
		return "skills 必须是数组"
	var skills: Array = skills_val
	if skills.is_empty():
		return "skills 数组不能为空"
	if skills.size() < 3:
		return "skills 数量不足（本批须 3–5 项，当前 %d 项）" % skills.size()
	if skills.size() > 5:
		return "skills 数量过多（本批须 3–5 项，当前 %d 项；禁止一次输出 8–15 项）" % skills.size()
	for i in skills.size():
		var skill: Variant = skills[i]
		if not skill is Dictionary:
			return "skills[%d] 须为对象" % i
		var row: Dictionary = skill
		if str(row.get("id", "")).strip_edges().is_empty():
			return "skills[%d] 缺少非空 id" % i
		if str(row.get("name", "")).strip_edges().is_empty():
			return "skills[%d] 缺少非空 name" % i
		var desc := str(row.get("desc", "")).strip_edges()
		if desc.is_empty():
			if not str(row.get("description", "")).strip_edges().is_empty():
				return "skills[%d] 须使用 desc 字段，不能用 description" % i
			return "skills[%d] 缺少非空 desc" % i
	return ""


static func describe_skills_batch_failure(batch: int, parsed_ok: bool, data: Variant = null) -> String:
	if not parsed_ok:
		return "阶段 2 批次 %d AI 返回的内容无法解析为 JSON" % batch
	var detail := describe_skills_batch_validation_failure(data)
	if detail.is_empty():
		return "阶段 2 批次 %d 校验失败（skills 须为 3–5 项，每项含 id、name、desc）" % batch
	return "阶段 2 批次 %d 校验失败：%s" % [batch, detail]


static func _resolve_novel_type_from_array(types: Array, selected: String) -> String:
	if not selected.is_empty():
		for item in types:
			if str(item).strip_edges() == selected:
				return selected
	for item in types:
		var t := str(item).strip_edges()
		if not t.is_empty():
			return t
	return ""


static func _looks_like_world_setting(value: Dictionary) -> bool:
	for key in ["nature_env", "people_env", "social_env"]:
		if value.has(key):
			return true
	return false


static func describe_skills_validation_failure(data: Variant, parsed_ok: bool) -> String:
	if not parsed_ok or data == null:
		return "阶段 2 AI 返回的内容无法解析为 JSON"
	if not data is Dictionary:
		return "阶段 2 AI 返回的 JSON 须为对象"
	var d: Dictionary = data
	if not d.has("skills"):
		return "阶段 2 AI 返回的 JSON 缺少顶层 skills 字段"
	var skills_val: Variant = d.get("skills", null)
	if skills_val == null:
		return "阶段 2 AI 返回的 skills 不能为 null"
	if skills_val is String:
		return "阶段 2 AI 返回的 skills 必须是对象数组，不能为字符串"
	if skills_val is Array:
		if skills_val.is_empty():
			return "阶段 2 AI 返回的 skills 数组不能为空（需 8–15 个行动标签）"
		if skills_val.size() < 8:
			return "阶段 2 AI 返回的 skills 数组至少需要 8 项（轻规则行动标签）"
		return "阶段 2 AI 返回的 JSON 无效（需要非空 skills 数组，每项含 id、name、desc）"
	if skills_val is Dictionary:
		if skills_val.is_empty():
			return "阶段 2 AI 返回的 skills 对象不能为空"
		return "阶段 2 AI 返回的 skills 须为对象数组 [{...}]，不要用 id 为键的对象 map"
	return "阶段 2 AI 返回的 JSON 无效（需要非空 skills）"


static func validate_skills_payload(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var skills_val: Variant = data.get("skills", null)
	if skills_val is Array:
		return skills_val.size() >= 8
	if skills_val is Dictionary:
		return skills_val.size() >= 8
	return false


static func extract_skills_array(data: Dictionary) -> Array:
	var skills_val: Variant = data.get("skills", [])
	if skills_val is Array:
		return skills_val
	if skills_val is Dictionary:
		var arr: Array = []
		for skill_id: String in skills_val:
			var entry: Variant = skills_val[skill_id]
			if entry is Dictionary:
				var row: Dictionary = (entry as Dictionary).duplicate()
				if not row.has("id"):
					row["id"] = skill_id
				arr.append(row)
		return arr
	return []


## 地图骨架：regions + key_nodes，不要求 map_pages。
static func validate_map_skeleton(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var map: Dictionary = data
	if str(map.get("overview", "")).strip_edges().is_empty():
		return false
	var regions_val: Variant = map.get("regions", null)
	if not regions_val is Array:
		return false
	var regions: Array = regions_val
	var region_count := regions.size()
	if region_count < 1 or region_count > 3:
		return false
	if not _validate_map_regions_graph(regions):
		return false
	var nodes_val: Variant = map.get("key_nodes", null)
	if not nodes_val is Array:
		return false
	var nodes: Array = nodes_val
	if nodes.size() < 2 or nodes.size() > 5:
		return false
	var region_ids := _region_ids_from_map(map)
	for node in nodes:
		if not node is Dictionary:
			return false
		var nid := str(node.get("id", "")).strip_edges()
		if nid.is_empty():
			return false
		var rid := str(node.get("region_id", "")).strip_edges()
		if rid.is_empty() or not region_ids.has(rid):
			return false
	return true


## 单张 region 级 map_page，须覆盖该 region 全部 key_nodes 的 cell_marks 绑定。
static func validate_region_map_page(
	map_skeleton: Variant,
	map_page: Variant,
	region_id: String,
) -> bool:
	if not map_skeleton is Dictionary or not map_page is Dictionary:
		return false
	var page: Dictionary = map_page
	var target_region := region_id.strip_edges()
	if target_region.is_empty():
		return false
	if str(page.get("parent_type", "")).strip_edges() != "region":
		return false
	if str(page.get("parent_id", "")).strip_edges() != target_region:
		return false
	if not LocalGridBuilderScript.validate_map_page_spec(page):
		return false
	var skeleton: Dictionary = map_skeleton
	var key_node_ids: Dictionary = {}
	var nodes_val: Variant = skeleton.get("key_nodes", [])
	if nodes_val is Array:
		for node in nodes_val:
			if node is Dictionary and str(node.get("region_id", "")).strip_edges() == target_region:
				var kn_id := str(node.get("id", "")).strip_edges()
				if not kn_id.is_empty():
					key_node_ids[kn_id] = true
	if key_node_ids.is_empty():
		return true
	var bound: Dictionary = {}
	var marks_val: Variant = page.get("cell_marks", [])
	if marks_val is Array:
		for mark_raw in marks_val:
			var mark := LocalGridBuilderScript.parse_cell_mark(mark_raw)
			var kn_id := str(mark.get("key_node_id", "")).strip_edges()
			if not kn_id.is_empty() and key_node_ids.has(kn_id):
				bound[kn_id] = true
	for kn_id in key_node_ids:
		if not bound.has(kn_id):
			return false
	return true


static func validate_faction_shadows_payload(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var shadows_val: Variant = (data as Dictionary).get("faction_shadows", null)
	if not shadows_val is Array:
		return false
	var shadows: Array = shadows_val
	if shadows.size() > 2:
		return false
	var seen: Dictionary = {}
	for item in shadows:
		if not item is Dictionary:
			return false
		var d: Dictionary = item
		var fid := str(d.get("id", "")).strip_edges()
		if fid.is_empty() or seen.has(fid):
			return false
		seen[fid] = true
		if str(d.get("name", "")).strip_edges().is_empty():
			return false
		if str(d.get("role", "")).strip_edges().is_empty():
			return false
	return true


static func validate_protagonist_payload(data: Variant, skills_db: Variant) -> bool:
	return describe_protagonist_validation_failure(data, skills_db).is_empty()


static func describe_protagonist_validation_failure(data: Variant, skills_db: Variant) -> String:
	if not data is Dictionary:
		return "须为 JSON 对象"
	var d: Dictionary = data
	var pid := str(d.get("protagonist_id", "")).strip_edges()
	if pid.is_empty():
		return "缺少非空 protagonist_id"
	var npcs_val: Variant = d.get("npcs", null)
	if not npcs_val is Array or npcs_val.size() != 1:
		return "npcs 须为仅含 1 条主角的数组"
	var npc: Variant = npcs_val[0]
	if not npc is Dictionary:
		return "npcs[0] 须为对象"
	var npc_d: Dictionary = npc
	if str(npc_d.get("id", "")).strip_edges() != pid:
		return "protagonist_id 须与 npcs[0].id 一致"
	if str(npc_d.get("性别", "")).strip_edges().is_empty():
		return "npcs[0] 缺少非空 性别"
	if str(npc_d.get("族群", "")).strip_edges().is_empty():
		return "npcs[0] 缺少非空 族群"
	if str(npc_d.get("initial_scene", "")).strip_edges().is_empty():
		return "npcs[0] 缺少非空 initial_scene"
	var skills_err := _describe_npc_skills_count_failure(npc_d)
	if not skills_err.is_empty():
		return skills_err
	if not validate_npc_skills_in_db(npcs_val, skills_db):
		return describe_npc_skills_db_failure(npc_d, skills_db, "npcs[0]")
	return ""


static func validate_single_key_npc_payload(
	data: Variant,
	skills_db: Variant,
	existing_ids: Array = [],
) -> bool:
	return describe_single_key_npc_validation_failure(data, skills_db, existing_ids).is_empty()


static func describe_single_key_npc_validation_failure(
	data: Variant,
	skills_db: Variant,
	existing_ids: Array = [],
) -> String:
	if not data is Dictionary:
		return "须为 JSON 对象"
	var npcs_val: Variant = (data as Dictionary).get("npcs", null)
	if not npcs_val is Array or npcs_val.size() != 1:
		return "npcs 须为仅含 1 条的数组"
	var npc: Variant = npcs_val[0]
	if not npc is Dictionary:
		return "npcs[0] 须为对象"
	var npc_d: Dictionary = npc
	var nid := str(npc_d.get("id", "")).strip_edges()
	if nid.is_empty():
		return "npcs[0] 缺少非空 id"
	for existing in existing_ids:
		if str(existing).strip_edges() == nid:
			return "npcs[0].id 与已有 NPC 重复"
	if str(npc_d.get("current_region_id", "")).strip_edges().is_empty():
		return "npcs[0] 缺少非空 current_region_id"
	if str(npc_d.get("initial_scene", "")).strip_edges().is_empty():
		return "npcs[0] 缺少非空 initial_scene"
	var skills_err := _describe_npc_skills_count_failure(npc_d)
	if not skills_err.is_empty():
		return skills_err
	if not validate_npc_skills_in_db(npcs_val, skills_db):
		return describe_npc_skills_db_failure(npc_d, skills_db, "npcs[0]")
	return ""


static func _describe_npc_skills_count_failure(npc: Dictionary) -> String:
	var skills_val: Variant = npc.get("skills", [])
	if not skills_val is Array:
		return "skills 须为 id 字符串数组"
	var count := (skills_val as Array).size()
	if count < NPC_SKILLS_MIN_COUNT:
		return "skills 数量不足（须 %d–%d 个，当前 %d 个）" % [
			NPC_SKILLS_MIN_COUNT,
			NPC_SKILLS_MAX_COUNT,
			count,
		]
	if count > NPC_SKILLS_MAX_COUNT:
		return "skills 数量过多（须 %d–%d 个，当前 %d 个）" % [
			NPC_SKILLS_MIN_COUNT,
			NPC_SKILLS_MAX_COUNT,
			count,
		]
	return ""


## 跑团式局部地图：1–3 区域。
static func validate_adventure_map_structure(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var map: Dictionary = data
	var regions_val: Variant = map.get("regions", null)
	if not regions_val is Array:
		return false
	var regions: Array = regions_val
	var region_count := regions.size()
	if region_count < 1 or region_count > 3:
		return false
	if not _validate_map_regions_graph(regions):
		return false
	return _validate_map_pages_optional(map, regions)


static func validate_map_structure(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var map: Dictionary = data
	var regions_val: Variant = map.get("regions", null)
	if not regions_val is Array:
		return false
	var regions: Array = regions_val
	var region_count := regions.size()
	if region_count < 4 or region_count > 7:
		if validate_adventure_map_structure(data):
			return true
		return false
	return _validate_map_regions_graph(regions)


static func _validate_map_regions_graph(regions: Array) -> bool:
	var region_ids: Dictionary = {}
	for region in regions:
		if not region is Dictionary:
			return false
		var rid := str(region.get("id", "")).strip_edges()
		if rid.is_empty() or region_ids.has(rid):
			return false
		region_ids[rid] = true
	for region in regions:
		if not region is Dictionary:
			return false
		var adj_val: Variant = (region as Dictionary).get("adjacent_region_ids", [])
		if not adj_val is Array:
			continue
		var from_id := str(region.get("id", "")).strip_edges()
		for adj_id_raw in adj_val:
			var adj_id := str(adj_id_raw).strip_edges()
			if adj_id.is_empty() or not region_ids.has(adj_id):
				return false
			if not _region_lists_neighbor(regions, adj_id, from_id):
				return false
	return true


## map_pages 为空时跳过；非空则校验每页 spec。缺失 region 的 map_page 由 merge 阶段补全。
static func _validate_map_pages_optional(map: Dictionary, regions: Array) -> bool:
	var pages_val: Variant = map.get("map_pages", null)
	if pages_val == null:
		return true
	if not pages_val is Array:
		return false
	var pages: Array = pages_val
	if pages.is_empty():
		return true
	var region_ids: Dictionary = {}
	for region in regions:
		if region is Dictionary:
			var rid := str(region.get("id", "")).strip_edges()
			if not rid.is_empty():
				region_ids[rid] = true
	var key_node_ids: Dictionary = {}
	var nodes_val: Variant = map.get("key_nodes", [])
	if nodes_val is Array:
		for node in nodes_val:
			if node is Dictionary:
				var nid := str(node.get("id", "")).strip_edges()
				if not nid.is_empty():
					key_node_ids[nid] = true
	var page_ids: Dictionary = {}
	for raw in pages:
		if not raw is Dictionary:
			return false
		var page: Dictionary = raw
		if not LocalGridBuilderScript.validate_map_page_spec(page):
			return false
		var pid := str(page.get("id", "")).strip_edges()
		if pid.is_empty() or page_ids.has(pid):
			return false
		page_ids[pid] = true
	for raw in pages:
		var page: Dictionary = raw as Dictionary
		var parent_type := str(page.get("parent_type", "")).strip_edges()
		var parent_id := str(page.get("parent_id", "")).strip_edges()
		if parent_type == "region" and parent_id not in region_ids:
			return false
		if parent_type == "key_node" and parent_id not in key_node_ids:
			return false
		var marks_val: Variant = page.get("cell_marks", [])
		if marks_val is Array:
			for mark_raw in marks_val:
				var mark := LocalGridBuilderScript.parse_cell_mark(mark_raw)
				var child_id := str(mark.get("child_map_id", "")).strip_edges()
				if not child_id.is_empty() and child_id not in page_ids:
					return false
				var kn_id := str(mark.get("key_node_id", "")).strip_edges()
				if not kn_id.is_empty() and kn_id not in key_node_ids:
					return false
	return true


static func validate_adventure_module(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var d: Dictionary = data
	for key in ["opening_hook", "immediate_goal", "failure_pressure"]:
		if str(d.get(key, "")).strip_edges().is_empty():
			return false
	return true


static func validate_adventure_map_step(map_data: Variant, adventure_data: Variant) -> bool:
	if not validate_map_skeleton(map_data):
		return false
	if not validate_adventure_module(adventure_data):
		return false
	if not validate_adventure_map_structure(map_data):
		return false
	return true


static func _region_lists_neighbor(regions: Array, region_a: String, region_b: String) -> bool:
	for region in regions:
		if not region is Dictionary:
			continue
		if str(region.get("id", "")).strip_edges() != region_a:
			continue
		var adj_val: Variant = region.get("adjacent_region_ids", [])
		if not adj_val is Array:
			return false
		for adj_id_raw in adj_val:
			if str(adj_id_raw).strip_edges() == region_b:
				return true
		return false
	return false


static func validate_factions(data: Variant, map_structure: Dictionary) -> bool:
	if not data is Array:
		return false
	var factions: Array = data
	if factions.size() < 4:
		return false
	var region_ids := _region_ids_from_map(map_structure)
	var leader_ids: Dictionary = {}
	for faction in factions:
		if not faction is Dictionary:
			return false
		var f: Dictionary = faction
		var fid := str(f.get("id", "")).strip_edges()
		if fid.is_empty():
			return false
		var core_region := str(f.get("core_region_id", "")).strip_edges()
		if core_region.is_empty() or (not region_ids.is_empty() and not region_ids.has(core_region)):
			return false
		var leader_id := str(f.get("leader_id", "")).strip_edges()
		if leader_id.is_empty() or leader_ids.has(leader_id):
			return false
		leader_ids[leader_id] = true
	return true


static func _region_ids_from_map(map_structure: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var regions_val: Variant = map_structure.get("regions", [])
	if not regions_val is Array:
		return lookup
	for region in regions_val:
		if region is Dictionary:
			var rid := str(region.get("id", "")).strip_edges()
			if not rid.is_empty():
				lookup[rid] = true
	return lookup


static func validate_npc_batch(
	data: Variant,
	skills_db: Variant,
	required_ids: Array = [],
	allow_extra: bool = false,
) -> bool:
	if not data is Dictionary:
		return false
	var npcs_val: Variant = (data as Dictionary).get("npcs", null)
	if not npcs_val is Array or npcs_val.is_empty():
		return false
	if not validate_npc_skills_in_db(npcs_val, skills_db):
		return false
	var seen: Dictionary = {}
	for npc in npcs_val:
		if not npc is Dictionary:
			return false
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty() or seen.has(nid):
			return false
		seen[nid] = true
	if required_ids.is_empty():
		return true
	if seen.size() != required_ids.size() and not allow_extra:
		return false
	for rid in required_ids:
		var req := str(rid).strip_edges()
		if not seen.has(req):
			return false
	return true


static func describe_world_build_substep_failure(sub: int, detail: String) -> String:
	return "阶段 3 子步 %d：%s" % [sub, detail]


static func validate_world_init(data: Variant, skills_db: Variant = null) -> bool:
	return describe_world_init_validation_failure(data, skills_db).is_empty()


static func describe_world_init_validation_failure(data: Variant, skills_db: Variant = null) -> String:
	if not data is Dictionary:
		return "world_init 须为 JSON 对象"
	var d: Dictionary = data
	for key in ["map_structure", "npcs", "protagonist_id"]:
		if not d.has(key):
			return "缺少字段 %s" % key
	if not d["map_structure"] is Dictionary:
		return "map_structure 须为对象"
	if d.has("factions") and not d["factions"] is Array:
		return "factions 须为数组"
	if d.has("adventure_module") and not validate_adventure_module(d.get("adventure_module")):
		return "adventure_module 无效"
	if not d["npcs"] is Array:
		return "npcs 须为数组"
	var pid: String = str(d["protagonist_id"]).strip_edges()
	if pid.is_empty():
		return "protagonist_id 不能为空"

	var protagonist_found := false
	var seen_ids: Dictionary = {}
	for npc in d["npcs"]:
		if not npc is Dictionary:
			continue
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty():
			return "npc 缺少非空 id"
		if seen_ids.has(nid):
			return "NPC id 重复: %s" % nid
		seen_ids[nid] = true
		if nid == pid:
			protagonist_found = true
	if not protagonist_found:
		return "npcs 中未找到与 protagonist_id 一致的主角"

	if skills_db != null:
		if not validate_npc_skills_in_db(d["npcs"], skills_db):
			return "部分 NPC 的 skills 不在技能库中或数量不符合要求"
	return ""


## 校验每个 NPC 的 skills 数组元素均存在于 skills_db.skills 的 key 中。
static func validate_npc_skills_in_db(npcs: Variant, skills_db: Variant) -> bool:
	if not npcs is Array:
		return false
	if not skills_db is Dictionary:
		return false

	var allowed: Dictionary = _skill_id_lookup(skills_db as Dictionary)
	if allowed.is_empty():
		return false

	for npc in npcs:
		if not npc is Dictionary:
			continue
		var skills_val: Variant = (npc as Dictionary).get("skills", [])
		if not skills_val is Array:
			return false
		for skill_entry in skills_val:
			var skill_id := str(skill_entry).strip_edges()
			if skill_id.is_empty() or not allowed.has(skill_id):
				return false
	return true


static func _skill_id_lookup(skills_db: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var skills_val: Variant = skills_db.get("skills", null)
	if skills_val is Dictionary:
		for skill_id: String in skills_val:
			var sid := skill_id.strip_edges()
			if not sid.is_empty():
				lookup[sid] = true
	elif skills_val is Array:
		for item in skills_val:
			if item is Dictionary:
				var sid := str(item.get("id", "")).strip_edges()
				if not sid.is_empty():
					lookup[sid] = true
	return lookup
