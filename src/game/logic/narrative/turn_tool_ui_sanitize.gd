class_name TurnToolUiSanitize
extends RefCounted

const TurnToolRegistryScript := preload("res://src/game/logic/narrative/turn_tool_registry.gd")
const RichTextFormatScript := preload("res://src/ui/rich_text_format.gd")
const ActionSuggestionBuilderScript := preload(
	"res://src/game/logic/narrative/action_suggestion_builder.gd"
)


static func sanitize_story_text(story_text: String) -> String:
	var text := story_text.strip_edges()
	if text.is_empty():
		return ""
	var lines := text.split("\n")
	var out: PackedStringArray = []
	for line in lines:
		var stripped := line.strip_edges()
		if stripped.is_empty():
			if out.size() > 0 and not out[out.size() - 1].is_empty():
				out.append("")
			continue
		out.append(RichTextFormatScript.sanitize_plain_text(stripped))
	return "\n".join(out)


static func sanitize_suggestions(suggestions: Array, read_model: GameReadModel) -> Array:
	return ActionSuggestionBuilderScript.filter_suggestions_against_world(read_model, suggestions)


static func run(
	story_text: String,
	suggestions: Array,
	read_model: GameReadModel,
) -> Dictionary:
	var clean_story := sanitize_story_text(story_text)
	var clean_suggestions: Array = []
	if read_model != null:
		clean_suggestions = sanitize_suggestions(suggestions, read_model)
	else:
		clean_suggestions = suggestions.duplicate(true)
	return {
		"story_text": clean_story,
		"suggestions": clean_suggestions,
		"tool_results": [
			TurnToolRegistryScript.make_result(
				TurnToolRegistryScript.TOOL_UI_TEXT_SANITIZE,
				true,
				{
					"story_len": clean_story.length(),
					"suggestion_count": clean_suggestions.size(),
				},
			),
		],
	}


static func run_requests(
	requests: Array,
	story_text: String,
	suggestions: Array,
	read_model: GameReadModel,
) -> Dictionary:
	var text := story_text
	var sugg: Array = suggestions.duplicate(true)
	for req in requests:
		if not req is Dictionary:
			continue
		if str(req.get("tool", "")) != TurnToolRegistryScript.TOOL_UI_TEXT_SANITIZE:
			continue
		var args: Dictionary = req.get("args", {}) if req.get("args") is Dictionary else {}
		if args.has("story_text"):
			text = str(args.get("story_text", text))
		if args.get("suggestions") is Array:
			sugg = args["suggestions"]
	return run(text, sugg, read_model)
