class_name TurnToolDynamicAdd
extends RefCounted

const TurnToolRegistryScript := preload("res://src/game/logic/narrative/turn_tool_registry.gd")
const DynamicAddTriggerParserScript := preload("res://src/ai_skills/dynamic_add_trigger_parser.gd")
const DynamicAddRegistryScript := preload("res://src/ai_skills/dynamic_add_registry.gd")
const NarrativeEntityRepairScript := preload(
	"res://src/game/logic/narrative/narrative_entity_repair.gd"
)


static func run_from_story(
	dynamic_add: DynamicAddService,
	story_text: String,
	read_model: GameReadModel,
	world_context: String,
) -> Dictionary:
	if dynamic_add == null or story_text.strip_edges().is_empty():
		return _empty(story_text)
	var pipeline: Dictionary = await dynamic_add.resolve_triggers_in_text(
		story_text,
		world_context,
		false,
	)
	return _pipeline_to_output(pipeline, story_text)


static func run_requests(
	dynamic_add: DynamicAddService,
	requests: Array,
	story_text: String,
	read_model: GameReadModel,
	world_context: String,
) -> Dictionary:
	if dynamic_add == null:
		return _empty(story_text)
	for req in requests:
		if not req is Dictionary:
			continue
		var args: Dictionary = req.get("args", {}) if req.get("args") is Dictionary else {}
		if not str(args.get("raw_token", "")).strip_edges().is_empty():
			return await run_from_story(dynamic_add, story_text, read_model, world_context)
	var assistant_text := story_text
	var all_results: Array = []
	var ran := false
	for req in requests:
		if not req is Dictionary:
			continue
		if str(req.get("tool", "")) != TurnToolRegistryScript.TOOL_DYNAMIC_ADD:
			continue
		var args: Dictionary = req.get("args", {}) if req.get("args") is Dictionary else {}
		var single := await _run_single_request(dynamic_add, args, world_context)
		if single.get("ok", false):
			ran = true
		if single.get("result") is Dictionary:
			all_results.append(single["result"])
		if single.get("assistant_text", "").strip_edges().is_empty():
			continue
		assistant_text = str(single.get("assistant_text", assistant_text))
	if not ran and not assistant_text.is_empty():
		var from_markers := await run_from_story(dynamic_add, assistant_text, read_model, world_context)
		return from_markers
	return {
		"assistant_text": assistant_text.strip_edges(),
		"dynamic_add_results": all_results,
		"ran": ran or not all_results.is_empty(),
		"tool_results": [
			TurnToolRegistryScript.make_result(
				TurnToolRegistryScript.TOOL_DYNAMIC_ADD,
				not all_results.is_empty(),
				{"results": all_results, "processed": all_results.size()},
			),
		],
	}


static func run_auto_repair(
	dynamic_add: DynamicAddService,
	story_text: String,
	read_model: GameReadModel,
	world_context: String,
) -> Array:
	if dynamic_add == null:
		return []
	var repair_reqs := NarrativeEntityRepairScript.build_synthetic_requests(story_text, read_model)
	if repair_reqs.is_empty():
		return []
	var pipeline: Dictionary = await dynamic_add.process_synthetic_requests(repair_reqs, world_context)
	if pipeline.get("dynamic_add_results") is Array:
		return pipeline["dynamic_add_results"]
	return []


static func _run_single_request(
	dynamic_add: DynamicAddService,
	args: Dictionary,
	world_context: String,
) -> Dictionary:
	var raw_token := str(args.get("raw_token", "")).strip_edges()
	if not raw_token.is_empty():
		var pipeline: Dictionary = await dynamic_add.resolve_triggers_in_text(
			raw_token,
			world_context,
			false,
		)
		return {
			"ok": pipeline.get("ok", false),
			"assistant_text": "",
			"result": TurnToolRegistryScript.make_result(
				TurnToolRegistryScript.TOOL_DYNAMIC_ADD,
				pipeline.get("ok", false),
				{"dynamic_add_results": pipeline.get("dynamic_add_results", [])},
			),
		}
	var category := str(args.get("category", "")).strip_edges()
	var schema_id := str(args.get("schema_id", "")).strip_edges()
	if schema_id.is_empty() and not category.is_empty():
		schema_id = DynamicAddRegistryScript.resolve_schema_id(category)
	if schema_id.is_empty():
		return {
			"ok": false,
			"assistant_text": "",
			"result": TurnToolRegistryScript.make_result(
				TurnToolRegistryScript.TOOL_DYNAMIC_ADD,
				false,
				{},
				"缺少 category 或 schema_id",
			),
		}
	var source := str(args.get("source_context", "")).strip_edges()
	var synthetic_text := "[[DYN_ADD:%s|%s]]" % [category if not category.is_empty() else schema_id, source]
	var pipeline: Dictionary = await dynamic_add.resolve_triggers_in_text(
		synthetic_text,
		world_context,
		false,
	)
	var cleaned := str(pipeline.get("assistant_text", "")).strip_edges()
	return {
		"ok": pipeline.get("ok", false),
		"assistant_text": cleaned,
		"result": TurnToolRegistryScript.make_result(
			TurnToolRegistryScript.TOOL_DYNAMIC_ADD,
			pipeline.get("ok", false),
			{"schema_id": schema_id, "dynamic_add_results": pipeline.get("dynamic_add_results", [])},
		),
	}


static func _pipeline_to_output(pipeline: Dictionary, fallback_story: String) -> Dictionary:
	var assistant_text := str(pipeline.get("assistant_text", fallback_story)).strip_edges()
	if assistant_text.is_empty():
		assistant_text = fallback_story
	var results: Array = (
		pipeline.get("dynamic_add_results", [])
		if pipeline.get("dynamic_add_results") is Array
		else []
	)
	return {
		"assistant_text": assistant_text,
		"dynamic_add_results": results,
		"ran": not results.is_empty() or assistant_text != fallback_story,
		"tool_results": [
			TurnToolRegistryScript.make_result(
				TurnToolRegistryScript.TOOL_DYNAMIC_ADD,
				pipeline.get("ok", true),
				{"results": results},
			),
		],
	}


static func _empty(story_text: String) -> Dictionary:
	return {
		"assistant_text": story_text,
		"dynamic_add_results": [],
		"ran": false,
		"tool_results": [],
	}
