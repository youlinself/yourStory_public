extends RefCounted

const AiResponseParserScript := preload("res://src/novel_config/ai_response_parser.gd")
const NarrativeTurnParserScript := preload(
	"res://src/game/logic/narrative/narrative_turn_parser.gd"
)

const TURN_JSON_KEY_MARKERS: PackedStringArray = [
	'"story_text"',
	'"tool_requests"',
	'"present_npc_ids"',
	'"datetime_display"',
	'"current_region_id"',
]


## 玩家可见叙述出口：从泄漏 JSON 中提取 story_text，绝不向 StoryLog 展示 JSON 结构。
static func coerce_player_narrative(text: String, raw_fallback: String = "") -> String:
	var candidate := text.strip_edges()
	if candidate.is_empty():
		candidate = raw_fallback.strip_edges()
	if candidate.is_empty():
		return ""
	if not looks_like_json_payload(candidate):
		return candidate

	var extracted := _extract_story_text(candidate)
	if not extracted.is_empty():
		return extracted

	var fallback := raw_fallback.strip_edges()
	if not fallback.is_empty() and fallback != candidate:
		extracted = _extract_story_text(fallback)
		if not extracted.is_empty():
			return extracted

	return ""


static func looks_like_json_payload(text: String) -> bool:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return false

	var parsed: Variant = AiResponseParserScript.parse_json_from_ai_text(trimmed)
	if parsed is Dictionary:
		return true

	for marker in TURN_JSON_KEY_MARKERS:
		if trimmed.find(marker) >= 0:
			return true

	var fenced := AiResponseParserScript.strip_markdown_json_fence(trimmed)
	return fenced.begins_with("{")


static func _extract_story_text(text: String) -> String:
	var parsed: Variant = AiResponseParserScript.parse_json_from_ai_text(text)
	if parsed is Dictionary:
		var data: Dictionary = parsed
		var story := str(data.get("story_text", "")).strip_edges()
		if story.is_empty():
			story = str(data.get("narrative", "")).strip_edges()
		if not story.is_empty() and not looks_like_json_payload(story):
			return story

	var from_parser := NarrativeTurnParserScript.story_text_only(text).strip_edges()
	if from_parser.is_empty():
		return ""
	if looks_like_json_payload(from_parser):
		return ""
	return from_parser
