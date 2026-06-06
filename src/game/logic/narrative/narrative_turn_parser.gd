class_name NarrativeTurnParser
extends RefCounted

const ActionSuggestionBuilderScript := preload(
	"res://src/game/logic/narrative/action_suggestion_builder.gd"
)
const AiResponseParserScript := preload("res://src/novel_config/ai_response_parser.gd")

const HOOK_START := "---STATE_HOOK---"
const HOOK_END := "---END_STATE_HOOK---"

const ALT_START_MARKERS: PackedStringArray = [
	"---STATE_HOOK---",
	"--- STATE_HOOK ---",
	"STATE_HOOK:",
	"STATE_HOOK",
	"【STATE_HOOK】",
	"## STATE_HOOK",
]
const ALT_END_MARKERS: PackedStringArray = [
	"---END_STATE_HOOK---",
	"--- END_STATE_HOOK ---",
	"END_STATE_HOOK",
	"【END_STATE_HOOK】",
]


## 合并 message.content（叙事）与顶层 content（后端 extractJson 抽出的 STATE_HOOK）。
static func parse_from_api_response(response: Dictionary) -> Dictionary:
	if response.is_empty():
		return _result("", {}, false, "AI 响应为空", [])

	var message_text: String = AiResponseParserScript.extract_choice_message_content(response)
	var top_content: String = AiResponseParserScript.extract_top_level_content(response)

	var unified := _try_unified_turn_json(message_text)
	if unified.get("parse_ok", false):
		return unified

	var inline := parse(message_text)
	if inline.get("parse_ok", false):
		return inline

	if not top_content.is_empty() and top_content != message_text:
		var hook := _parse_hook_dictionary(top_content)
		if not hook.is_empty():
			var story: String = message_text
			if story.is_empty():
				story = _story_before_first_hook_marker(message_text)
			return _result(
				story,
				hook,
				true,
				"",
				_extract_suggestions(hook),
			)

	if not message_text.is_empty():
		var hook_only := _parse_hook_dictionary(message_text)
		if not hook_only.is_empty() and _looks_like_state_hook(hook_only):
			return _result("", hook_only, true, "", _extract_suggestions(hook_only))

	return _result(
		message_text if not message_text.is_empty() else top_content,
		{},
		false,
		"缺少可解析的 STATE_HOOK（请检查后端是否剥离了状态 JSON）",
		[],
	)


static func parse(assistant_text: String) -> Dictionary:
	var raw := assistant_text.strip_edges()
	if raw.is_empty():
		return _result("", {}, false, "AI 响应为空", [])

	for start_marker in ALT_START_MARKERS:
		var attempt := _parse_with_markers(raw, start_marker)
		if attempt.get("parse_ok", false):
			return attempt

	var fenced := _parse_fenced_state_json(raw)
	if fenced.get("parse_ok", false):
		return fenced

	var trailing := _parse_trailing_state_json(raw)
	if trailing.get("parse_ok", false):
		return trailing

	var story_fallback := _story_before_first_hook_marker(raw)
	return _result(story_fallback, {}, false, "缺少可解析的 STATE_HOOK", [])


static func _parse_with_markers(raw: String, start_marker: String) -> Dictionary:
	var start_idx := _find_marker(raw, start_marker)
	if start_idx < 0:
		return _result("", {}, false, "", [])

	var story_text := raw.substr(0, start_idx).strip_edges()
	var after_start := raw.substr(start_idx + start_marker.length()).strip_edges()

	var end_idx := -1
	for end_marker in ALT_END_MARKERS:
		var idx := after_start.find(end_marker)
		if idx >= 0 and (end_idx < 0 or idx < end_idx):
			end_idx = idx

	var json_text := after_start if end_idx < 0 else after_start.substr(0, end_idx).strip_edges()
	var hook := _parse_hook_dictionary(json_text)
	if hook.is_empty():
		return _result(story_text, {}, false, "STATE_HOOK 不是合法 JSON", [])

	var suggestions := _extract_suggestions(hook)
	return _result(story_text, hook, true, "", suggestions)


static func _parse_fenced_state_json(raw: String) -> Dictionary:
	var fence_re := RegEx.new()
	fence_re.compile("```(?:json|state_hook)?\\s*([\\s\\S]*?)```", true)
	var matches := fence_re.search_all(raw)
	if matches.is_empty():
		return _result("", {}, false, "", [])

	for i in range(matches.size() - 1, -1, -1):
		var body := matches[i].get_string(1).strip_edges()
		var hook := _parse_hook_dictionary(body)
		if hook.is_empty():
			continue
		var story_text := raw.substr(0, matches[i].get_start()).strip_edges()
		return _result(story_text, hook, true, "", _extract_suggestions(hook))

	return _result("", {}, false, "", [])


static func _parse_trailing_state_json(raw: String) -> Dictionary:
	var last_brace := raw.rfind("}")
	if last_brace < 0:
		return _result("", {}, false, "", [])

	for start in range(last_brace, -1, -1):
		if raw[start] != "{":
			continue
		var candidate := raw.substr(start, last_brace - start + 1).strip_edges()
		var hook := _parse_hook_dictionary(candidate)
		if hook.is_empty():
			continue
		var story_text := raw.substr(0, start).strip_edges()
		return _result(story_text, hook, true, "", _extract_suggestions(hook))

	return _result("", {}, false, "", [])


static func _try_unified_turn_json(text: String) -> Dictionary:
	var parsed: Variant = AiResponseParserScript.parse_json_from_ai_text(text)
	if not parsed is Dictionary:
		return _result("", {}, false, "", [])
	var data: Dictionary = parsed
	if not _looks_like_state_hook(data):
		return _result("", {}, false, "", [])

	var story := str(data.get("story_text", "")).strip_edges()
	if story.is_empty():
		story = str(data.get("narrative", "")).strip_edges()

	var hook := data.duplicate(true)
	var tool_requests := _extract_tool_requests(data)
	hook.erase("story_text")
	hook.erase("narrative")
	hook.erase("tool_requests")
	return _result(story, hook, true, "", _extract_suggestions(hook), tool_requests)


static func _parse_hook_dictionary(json_text: String) -> Dictionary:
	var cleaned := AiResponseParserScript.strip_markdown_json_fence(json_text.strip_edges())
	if cleaned.is_empty():
		return {}

	var parsed: Variant = JSON.parse_string(cleaned)
	if parsed is Dictionary and _looks_like_state_hook(parsed as Dictionary):
		return parsed as Dictionary

	var repaired := AiResponseParserScript.repair_json_text(cleaned)
	if repaired != cleaned:
		parsed = JSON.parse_string(repaired)
		if parsed is Dictionary and _looks_like_state_hook(parsed as Dictionary):
			return parsed as Dictionary

	return {}


static func _looks_like_state_hook(data: Dictionary) -> bool:
	return (
		data.has("datetime_display")
		or data.has("weather")
		or data.has("current_region_id")
		or data.has("current_key_node_id")
	)


static func _find_marker(text: String, marker: String) -> int:
	var idx := text.find(marker)
	if idx >= 0:
		return idx
	return text.to_lower().find(marker.to_lower())


## 从 assistant 原文中剥离 STATE_HOOK，供 narrative_messages 历史存储。
static func story_text_only(assistant_text: String) -> String:
	var raw := assistant_text.strip_edges()
	if raw.is_empty():
		return ""
	var unified := _try_unified_turn_json(raw)
	if unified.get("parse_ok", false):
		return str(unified.get("story_text", "")).strip_edges()
	var inline := parse(raw)
	if not str(inline.get("story_text", "")).strip_edges().is_empty():
		return str(inline.get("story_text", "")).strip_edges()
	return _story_before_first_hook_marker(raw)


static func _story_before_first_hook_marker(raw: String) -> String:
	var earliest := -1
	for marker in ALT_START_MARKERS:
		var idx := _find_marker(raw, marker)
		if idx >= 0 and (earliest < 0 or idx < earliest):
			earliest = idx
	if earliest < 0:
		return raw
	return raw.substr(0, earliest).strip_edges()


static func _extract_suggestions(hook: Dictionary) -> Array:
	return ActionSuggestionBuilderScript.parse_hook_suggestions(hook)


static func _extract_tool_requests(data: Dictionary) -> Array:
	var raw: Variant = data.get("tool_requests", [])
	if not raw is Array:
		return []
	var out: Array = []
	for item in raw:
		if item is Dictionary:
			out.append((item as Dictionary).duplicate(true))
	return out


static func _result(
	story_text: String,
	hook: Dictionary,
	parse_ok: bool,
	error: String,
	suggestions: Array = [],
	tool_requests: Array = [],
) -> Dictionary:
	return {
		"story_text": story_text,
		"hook": hook,
		"parse_ok": parse_ok,
		"error": error,
		"suggestions": suggestions,
		"tool_requests": tool_requests,
	}
