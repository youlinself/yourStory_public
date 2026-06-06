class_name AiPromptComposer
extends RefCounted

## 跨场景通用 AI 提示词组装（JSON 输出规范等）。

const COMMON_MD := "res://ai_config/ai_json_output_common.md"
const ResTextFileScript := preload("res://src/io/res_text_file.gd")

static var _cached_json_rules: String = ""


static func load_json_output_system_prompt() -> String:
	if not _cached_json_rules.is_empty():
		return _cached_json_rules
	var text := ResTextFileScript.read(COMMON_MD).strip_edges()
	if text.is_empty():
		push_error("无法读取通用 JSON 输出规范: " + COMMON_MD)
		return ""
	_cached_json_rules = text
	return _cached_json_rules


static func wrap_json_task(user_content: String) -> Array:
	var user := user_content.strip_edges()
	if user.is_empty():
		push_error("wrap_json_task: user_content 为空")
		return []
	var rules := load_json_output_system_prompt()
	if rules.is_empty():
		return [{"role": "user", "content": user}]
	return [
		{"role": "system", "content": rules},
		{"role": "user", "content": user},
	]


static func merge_into_system(messages: Array, fragment: String) -> Array:
	var piece := fragment.strip_edges()
	if piece.is_empty():
		return messages.duplicate(true)

	var out: Array = []
	var merged := false
	for msg in messages:
		if not msg is Dictionary:
			out.append(msg)
			continue
		var role := str(msg.get("role", "")).strip_edges()
		if role == "system" and not merged:
			merged = true
			var existing := str(msg.get("content", "")).strip_edges()
			var combined := piece
			if not existing.is_empty():
				combined = existing + "\n\n---\n\n" + piece
			out.append({"role": "system", "content": combined})
		else:
			out.append((msg as Dictionary).duplicate(true))

	if not merged:
		out.insert(0, {"role": "system", "content": piece})
	return out


static func prepend_json_rules_to_system(system_content: String) -> String:
	var body := system_content.strip_edges()
	var rules := load_json_output_system_prompt()
	if rules.is_empty():
		return body
	if body.is_empty():
		return rules
	return rules + "\n\n---\n\n" + body
