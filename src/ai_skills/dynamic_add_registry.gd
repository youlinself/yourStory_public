class_name DynamicAddRegistry
extends RefCounted

const REGISTRY_PATH := "res://ai_config/AiSkills/dynamic_add_registry.json"
const ResTextFileScript := preload("res://src/io/res_text_file.gd")

static var _cache: Dictionary = {}


static func get_registry() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var data: Variant = _load_json(REGISTRY_PATH)
	if data is Dictionary:
		_cache = data
	return _cache


static func resolve_schema_id(category_or_id: String) -> String:
	var key := category_or_id.strip_edges()
	if key.is_empty():
		return ""
	var registry := get_registry()
	var categories: Variant = registry.get("categories", [])
	if not categories is Array:
		return ""
	for entry in categories:
		if not entry is Dictionary:
			continue
		var schema_id := str(entry.get("schema_id", "")).strip_edges()
		if schema_id.is_empty():
			continue
		if key == schema_id:
			return schema_id
		var labels: Variant = entry.get("labels", [])
		if labels is Array:
			for label in labels:
				if str(label).strip_edges().to_lower() == key.to_lower():
					return schema_id
	return ""


static func get_category_entry(schema_id: String) -> Dictionary:
	var registry := get_registry()
	var categories: Variant = registry.get("categories", [])
	if not categories is Array:
		return {}
	for entry in categories:
		if entry is Dictionary and str(entry.get("schema_id", "")) == schema_id:
			return entry
	return {}


static func list_categories_for_prompt() -> String:
	var lines: PackedStringArray = []
	var registry := get_registry()
	var categories: Variant = registry.get("categories", [])
	if not categories is Array:
		return ""
	for entry in categories:
		if not entry is Dictionary:
			continue
		var schema_id := str(entry.get("schema_id", ""))
		var labels: Variant = entry.get("labels", [])
		var label_text := schema_id
		if labels is Array and not labels.is_empty():
			label_text = str(labels[0])
		var one_line := str(entry.get("one_line", ""))
		lines.append(
			"- 分类 `%s`（schema_id: `%s`）— %s" % [label_text, schema_id, one_line]
		)
	return "\n".join(lines)


static func get_trigger_examples() -> PackedStringArray:
	var registry := get_registry()
	var examples: Variant = registry.get("examples", [])
	if examples is Array:
		var out: PackedStringArray = []
		for ex in examples:
			out.append(str(ex))
		return out
	return PackedStringArray()


static func get_multi_examples() -> PackedStringArray:
	var registry := get_registry()
	var examples: Variant = registry.get("multi_examples", [])
	if examples is Array:
		var out: PackedStringArray = []
		for ex in examples:
			out.append(str(ex))
		return out
	return PackedStringArray()


static func get_max_per_response() -> int:
	var registry := get_registry()
	var limits: Variant = registry.get("limits", {})
	if limits is Dictionary:
		return maxi(1, int(limits.get("max_per_response", 5)))
	return 5


static func is_batch_generation_enabled() -> bool:
	var registry := get_registry()
	var batch: Variant = registry.get("batch_generation", {})
	if batch is Dictionary:
		return bool(batch.get("enabled", true))
	return true


static func get_batch_min_count() -> int:
	var registry := get_registry()
	var batch: Variant = registry.get("batch_generation", {})
	if batch is Dictionary:
		return maxi(2, int(batch.get("min_count", 2)))
	return 2


static func _load_json(path: String) -> Variant:
	var data: Variant = ResTextFileScript.read_json(path)
	if data == null:
		push_error("无法找到或解析: " + path)
	return data
