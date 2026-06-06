class_name DynamicAddStorage
extends RefCounted

const DynamicAddPromptBuilder = preload("res://src/ai_skills/dynamic_add_prompt_builder.gd")
const MapStructureRepairScript = preload("res://src/game/logic/world/map_structure_repair.gd")
const LocalGridBuilderScript = preload("res://src/novel_config/local_grid_builder.gd")
const ItemSettingGuardScript := preload("res://src/game/logic/data/item_setting_guard.gd")
const ItemDisplayCatalogScript := preload("res://src/game/logic/data/item_display_catalog.gd")

## 批量写入。ai_payload 含 entries 数组，或与单条相同结构的 Dictionary 列表。
## 返回与 entries 等长的结果数组（每项含 ok、schema_id、data、raw_token 等，由调用方补 token）。
static func apply_batch_entries(entries: Array, allow_placeholder_upsert: bool = false) -> Array:
	var results: Array = []
	for item in entries:
		if not item is Dictionary:
			results.append(_fail("entries 项不是对象"))
			continue
		var row: Dictionary = item as Dictionary
		var schema_id := str(row.get("schema_id", "")).strip_edges()
		if schema_id.is_empty():
			results.append(_fail("entries 项缺少 schema_id"))
			continue
		var stored := apply_generation_result(schema_id, row, allow_placeholder_upsert)
		stored["index"] = row.get("index", results.size())
		results.append(stored)
	return results


static func apply_generation_result(
	schema_id: String,
	ai_payload: Dictionary,
	allow_placeholder_upsert: bool = false,
) -> Dictionary:
	var schema: Dictionary = DynamicAddPromptBuilder.load_schema(schema_id)
	if schema.is_empty():
		return _fail("未知 schema: %s" % schema_id)

	var data: Variant = ai_payload.get("data", null)
	if not data is Dictionary:
		return _fail("响应缺少 data 对象")

	var record: Dictionary = (data as Dictionary).duplicate(true)
	if schema_id == "runtime_key_node":
		record = _normalize_key_node_region(record)
	var target: Dictionary = schema.get("target", {}) if schema.get("target") is Dictionary else {}
	var key_field := str(target.get("record_key_field", "id"))
	var record_key := str(record.get(key_field, record.get("id", ""))).strip_edges()

	var dedupe_hit: Variant = find_existing_record(schema, record)
	if dedupe_hit != null:
		var existing: Dictionary = dedupe_hit as Dictionary
		if (
			allow_placeholder_upsert
			and ItemDisplayCatalogScript.is_placeholder_record(existing, record_key)
		):
			if not _write_record(schema, record, true):
				return _fail("写入运行时库失败")
			return {
				"ok": true,
				"status": "updated_placeholder",
				"schema_id": schema_id,
				"data": record,
				"storage_note": _storage_note(schema, record, false),
			}
		if schema_id == "runtime_key_node" and dedupe_hit is Dictionary:
			_persist_key_node_map_cell(dedupe_hit as Dictionary)
		return {
			"ok": true,
			"status": "already_exists",
			"schema_id": schema_id,
			"data": dedupe_hit,
			"storage_note": _storage_note(schema, dedupe_hit, true),
		}

	if schema_id == "loot_item" or schema_id == "loot_weapon":
		var base_cfg := ItemSettingGuardScript.parse_base_config_from_runtime()
		var setting_err := ItemSettingGuardScript.validate_loot_record(record, base_cfg, schema_id)
		if not setting_err.is_empty():
			push_warning("dynamic_add 物品设定校验: %s" % setting_err)
			return _fail(setting_err)

	if not _write_record(schema, record, false):
		return _fail("写入运行时库失败")

	if schema_id == "runtime_key_node":
		_persist_key_node_map_cell(record)

	return {
		"ok": true,
		"status": "new_created",
		"schema_id": schema_id,
		"data": record,
		"storage_note": _storage_note(schema, record, false),
	}


static func find_existing_record(schema: Dictionary, record: Dictionary) -> Variant:
	var target: Variant = schema.get("target", {})
	if not target is Dictionary:
		return null
	var target_dict: Dictionary = target
	if _is_map_array_target(target_dict):
		var arr := _load_map_structure_array(target_dict)
		var map_dedupe: Variant = schema.get("dedupe", {})
		return _find_in_array(arr, record, map_dedupe)
	var db_file := str(target_dict.get("db_file", ""))
	var envelope_key := str(target_dict.get("envelope_key", ""))
	if db_file.is_empty() or envelope_key.is_empty():
		return null

	var db: Variant = GameRunningFileManager.load_json_data(db_file)
	if db == null:
		db = _empty_db_for_file(db_file)
	if not db is Dictionary:
		return null

	var envelope: Variant = db.get(envelope_key, {})
	if not envelope is Dictionary:
		return null

	var dedupe: Variant = schema.get("dedupe", {})
	return _find_in_envelope(envelope as Dictionary, record, dedupe)


static func _write_record(schema: Dictionary, record: Dictionary, force_overwrite: bool = false) -> bool:
	var target: Dictionary = schema.get("target", {})
	var key_field := str(target.get("record_key_field", "id"))
	var record_key := str(record.get(key_field, "")).strip_edges()
	if record_key.is_empty():
		push_error("dynamic_add 记录缺少键字段: %s" % key_field)
		return false

	if _is_map_array_target(target):
		var ok := _append_map_structure_record(target, record)
		if ok:
			_post_write_actions(str(schema.get("schema_id", "")), record)
		return ok

	var db_file := str(target.get("db_file", ""))
	var envelope_key := str(target.get("envelope_key", ""))
	var db: Variant = GameRunningFileManager.load_json_data(db_file)
	if db == null:
		db = _empty_db_for_file(db_file)
	if not db is Dictionary:
		db = _empty_db_for_file(db_file)

	if not db.has(envelope_key) or not db[envelope_key] is Dictionary:
		db[envelope_key] = {}

	var envelope: Dictionary = db[envelope_key]
	if envelope.has(record_key) and not force_overwrite:
		var existing: Variant = envelope[record_key]
		if existing is Dictionary and not ItemDisplayCatalogScript.is_placeholder_record(existing as Dictionary, record_key):
			return true
	envelope[record_key] = record.duplicate(true)
	db[envelope_key] = envelope
	var saved := GameRunningFileManager.save_json_data(db_file, db)
	if saved:
		_post_write_actions(str(schema.get("schema_id", "")), record)
	return saved


static func _find_in_envelope(envelope: Dictionary, record: Dictionary, dedupe: Variant) -> Variant:
	var fields: Array = []
	var case_name := true
	if dedupe is Dictionary:
		var f: Variant = dedupe.get("fields", [])
		if f is Array:
			fields.assign(f)
		case_name = bool(dedupe.get("case_insensitive_name", true))

	for _key: String in envelope:
		var existing: Variant = envelope[_key]
		if not existing is Dictionary:
			continue
		if _records_match(existing as Dictionary, record, fields, case_name):
			return (existing as Dictionary).duplicate(true)
	return null


static func _records_match(a: Dictionary, b: Dictionary, fields: Array, case_insensitive_name: bool) -> bool:
	if fields.is_empty():
		fields = ["id", "name"]
	for field in fields:
		var fname := str(field)
		if not a.has(fname) or not b.has(fname):
			continue
		var va := str(a[fname]).strip_edges()
		var vb := str(b[fname]).strip_edges()
		if va.is_empty() or vb.is_empty():
			continue
		if fname == "name" and case_insensitive_name:
			if va.to_lower() == vb.to_lower():
				return true
		elif va == vb:
			return true
	return false


static func _empty_db_for_file(db_file: String) -> Dictionary:
	match db_file:
		GameRunningFileManager.ITEMS_DB:
			return RuntimeDbSchemas.empty_items_db()
		GameRunningFileManager.WEAPON_DB:
			return RuntimeDbSchemas.empty_weapon_db()
		GameRunningFileManager.SKILLS_DB:
			return RuntimeDbSchemas.empty_skills_db()
		GameRunningFileManager.NPC_DB:
			return RuntimeDbSchemas.empty_npc_db()
		GameRunningFileManager.MAP_DB:
			return RuntimeDbSchemas.empty_map_db()
		_:
			return {}


static func _is_map_array_target(target: Dictionary) -> bool:
	return str(target.get("storage_kind", "")).strip_edges() == "map_array"


static func _map_structure_key(target: Dictionary) -> String:
	return str(target.get("map_structure_key", "")).strip_edges()


static func _load_map_structure_array(target: Dictionary) -> Array:
	var db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB))
	var ms := _as_dict(db.get("map_structure", {}))
	var key := _map_structure_key(target)
	var arr: Variant = ms.get(key, [])
	return arr if arr is Array else []


static func _normalize_key_node_region(record: Dictionary) -> Dictionary:
	var out := record.duplicate(true)
	var node_name := str(out.get("name", "")).strip_edges()
	var region_id := str(out.get("region_id", "")).strip_edges()
	if node_name.is_empty():
		return out
	var db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB))
	var ms := _as_dict(db.get("map_structure", {}))
	var regions: Variant = ms.get("regions", [])
	if not regions is Array:
		return out
	var rm := GameReadModel.new()
	rm.map_db = db
	var hint := node_name
	if "康宁" in node_name or "南郊" in node_name:
		hint = "南郊%s" % node_name
	var resolved: String = MapStructureRepairScript.guess_parent_region_id_for_place(hint, rm)
	if resolved.is_empty():
		return out
	if region_id != resolved:
		var current_name := ""
		for region in regions:
			if region is Dictionary and str(region.get("id", "")).strip_edges() == region_id:
				current_name = str(region.get("name", "")).strip_edges()
				break
		var should_fix: bool = resolved != region_id
		if "康宁" in node_name and not current_name.is_empty():
			if "老城" in current_name and ("南郊" not in current_name and "康宁" not in current_name):
				should_fix = true
		if should_fix:
			push_warning(
				"[DynamicAddStorage] key_node「%s」region_id %s → %s（按地名校正父区）"
				% [node_name, region_id, resolved]
			)
			out["region_id"] = resolved
	return out


static func _append_map_structure_record(target: Dictionary, record: Dictionary) -> bool:
	var db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB))
	if db.is_empty():
		db = RuntimeDbSchemas.empty_map_db()
	var ms := _as_dict(db.get("map_structure", {}))
	var key := _map_structure_key(target)
	if key.is_empty():
		push_error("dynamic_add map_array 缺少 map_structure_key")
		return false
	if key == "key_nodes":
		record = _normalize_key_node_region(record)
	var arr: Array = _load_map_structure_array(target)
	var key_field := str(target.get("record_key_field", "id"))
	var record_key := str(record.get(key_field, "")).strip_edges()
	for existing in arr:
		if existing is Dictionary and str(existing.get(key_field, "")).strip_edges() == record_key:
			return true
	arr.append(record.duplicate(true))
	ms[key] = arr
	db["map_structure"] = ms
	return GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, db)


static func _find_in_array(arr: Array, record: Dictionary, dedupe: Variant) -> Variant:
	var fields: Array = []
	var case_name := true
	if dedupe is Dictionary:
		var f: Variant = dedupe.get("fields", [])
		if f is Array:
			fields.assign(f)
		case_name = bool(dedupe.get("case_insensitive_name", true))
	for existing in arr:
		if existing is Dictionary and _records_match(existing as Dictionary, record, fields, case_name):
			return (existing as Dictionary).duplicate(true)
	return null


static func _persist_key_node_map_cell(record: Dictionary) -> void:
	var db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB))
	if db.is_empty():
		return
	var ms := _as_dict(db.get("map_structure", {}))
	if ms.is_empty():
		return
	var updated := LocalGridBuilderScript.assign_key_node_cell(ms, record)
	db["map_structure"] = updated
	GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, db)


static func _post_write_actions(schema_id: String, record: Dictionary) -> void:
	if schema_id == "runtime_region":
		var region_id := str(record.get("id", "")).strip_edges()
		if not region_id.is_empty():
			_unlock_region_in_game_state(region_id)


static func _unlock_region_in_game_state(region_id: String) -> void:
	var state := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.GAME_STATE))
	if state.is_empty():
		state = RuntimeDbSchemas.empty_game_state()
	var unlocked: Array = state.get("unlocked_region_ids", [])
	if not unlocked is Array:
		unlocked = []
	if region_id not in unlocked:
		unlocked.append(region_id)
		state["unlocked_region_ids"] = unlocked
		GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state)


static func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _storage_note(schema: Dictionary, record: Dictionary, existed: bool) -> String:
	var target: Dictionary = schema.get("target", {})
	var key_field := str(target.get("record_key_field", "id"))
	var rid := str(record.get(key_field, ""))
	var prefix := "已存在" if existed else "已写入"
	if _is_map_array_target(target):
		return "%s %s → map_structure.%s[%s]" % [
			prefix,
			str(target.get("db_file", "")),
			_map_structure_key(target),
			rid,
		]
	var db_file := str(target.get("db_file", ""))
	var envelope_key := str(target.get("envelope_key", ""))
	return "%s %s → %s['%s']" % [prefix, db_file, envelope_key, rid]


static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
