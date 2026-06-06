class_name NovelTypeSelector
extends RefCounted

const TEMPLATE_PATH := "res://src/novel_config/baseConfig.json"

static var _candidates: Array[String] = []
static var _rng := RandomNumberGenerator.new()


static func get_candidates() -> Array[String]:
	if _candidates.is_empty():
		_load_candidates()
	return _candidates.duplicate()


static func draw_random(exclude: String = "") -> String:
	var pool := get_candidates()
	if pool.is_empty():
		push_error("NovelTypeSelector: 候选小说类型为空")
		return ""

	var trimmed_exclude := exclude.strip_edges()
	if not trimmed_exclude.is_empty():
		pool = pool.filter(func(t: String) -> bool: return t != trimmed_exclude)

	if pool.is_empty():
		return trimmed_exclude if not trimmed_exclude.is_empty() else _candidates[0]

	_rng.randomize()
	return pool[_rng.randi_range(0, pool.size() - 1)]


static func build_prompt_payload(selected: String) -> Dictionary:
	var selected_trimmed := selected.strip_edges()
	if selected_trimmed.is_empty():
		push_error("NovelTypeSelector.build_prompt_payload: selected 为空")
		return {}

	var template := _load_template()
	if template.is_empty():
		return {}

	var schema: Variant = template.get("base_config", {})
	if not schema is Dictionary:
		push_error("NovelTypeSelector: 模板缺少 base_config")
		return {}

	return {
		"novel_type": selected_trimmed,
		"world_setting_schema": (schema as Dictionary).duplicate(true),
	}


## 阶段 1 分片用：仅携带当前 slice 的 schema，避免三片模板重复塞进 prompt。
static func build_slice_prompt_payload(selected: String, slice: int) -> Dictionary:
	var full := build_prompt_payload(selected)
	if full.is_empty():
		return {}

	var schema_val: Variant = full.get("world_setting_schema", {})
	if not schema_val is Dictionary:
		return full

	var field_key := ""
	match slice:
		1:
			field_key = "nature_env"
		2:
			field_key = "people_env"
		3:
			field_key = "social_env"
		_:
			return full

	var schema: Dictionary = schema_val as Dictionary
	if not schema.has(field_key):
		return full

	return {
		"novel_type": full.get("novel_type", selected.strip_edges()),
		"world_setting_schema": {field_key: schema[field_key]},
	}


static func _load_candidates() -> void:
	_candidates.clear()
	var template := _load_template()
	if template.is_empty():
		return

	var types_val: Variant = template.get("novel_type", [])
	if not types_val is Array or (types_val as Array).is_empty():
		push_error("NovelTypeSelector: novel_type 须为非空数组")
		return

	for item in types_val:
		var t := str(item).strip_edges()
		if not t.is_empty():
			_candidates.append(t)

	if _candidates.is_empty():
		push_error("NovelTypeSelector: novel_type 数组无有效字符串")


static func _load_template() -> Dictionary:
	var text := _read_file(TEMPLATE_PATH).strip_edges()
	if text.is_empty():
		push_error("NovelTypeSelector: 无法读取 " + TEMPLATE_PATH)
		return {}

	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("NovelTypeSelector: 模板 JSON 无效")
		return {}

	return data as Dictionary


static func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
