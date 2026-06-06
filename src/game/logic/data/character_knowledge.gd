class_name CharacterKnowledge
extends RefCounted

## 主角对人物档案的「已知字段」——与 npc_db / mainrole 中的完整数据分离。

const SELF_KEY := "self"

const PROFILE_FIELDS: Array[String] = [
	"name",
	"age",
	"性别",
	"族群",
	"origin",
	"physical_traits",
	"personality",
	"deep_motivation",
	"core_conflict",
	"skills",
	"abilities",
	"psychology",
]

## 主角开局即自知（常识性自传信息，不依赖探知）。
const SELF_BASELINE_FIELDS: Array[String] = [
	"name",
	"age",
	"性别",
	"族群",
	"origin",
	"physical_traits",
	"personality",
	"abilities",
	"psychology",
	"skills",
]

## 主角内心深层设定，须通过叙事/自省 discoveries 解锁。
const SELF_DISCOVERABLE_FIELDS: Array[String] = ["deep_motivation", "core_conflict"]


static func empty_store() -> Dictionary:
	return {}


static func seed_initial(protagonist_id: String, nearby_npc_ids: Variant) -> Dictionary:
	var store := empty_store()
	store[SELF_KEY] = SELF_BASELINE_FIELDS.duplicate()
	if nearby_npc_ids is Array:
		for id_val in nearby_npc_ids:
			var npc_id := str(id_val).strip_edges()
			if npc_id.is_empty() or npc_id == protagonist_id:
				continue
			store[npc_id] = ["name"]
	return store


## 旧存档迁移：保证 self 至少拥有「自知」基准字段（数值仍可为未知）。
static func upgrade_self_baseline(store: Dictionary, _truth: Dictionary) -> void:
	if not store is Dictionary:
		return
	reveal_fields(store, SELF_KEY, SELF_BASELINE_FIELDS)


## 非空 knowledge 存档可能缺少附近 NPC 条目；补全「仅知名」基准，不覆盖已有解锁。
static func ensure_nearby_npc_baseline(
	store: Dictionary,
	protagonist_id: String,
	nearby_npc_ids: Variant,
) -> void:
	if not store is Dictionary:
		return
	if not nearby_npc_ids is Array:
		return
	for id_val in nearby_npc_ids:
		var npc_id := str(id_val).strip_edges()
		if npc_id.is_empty() or npc_id == protagonist_id:
			continue
		reveal_fields(store, npc_id, ["name"])


static func get_revealed_fields(store: Variant, target_id: String) -> Array:
	if not store is Dictionary:
		return []
	var key := _target_key(target_id)
	var raw: Variant = (store as Dictionary).get(key, [])
	if raw is Array:
		return raw.duplicate()
	return []


static func is_field_revealed(store: Variant, target_id: String, field: String) -> bool:
	var fid := field.strip_edges()
	if fid.is_empty():
		return false
	return fid in get_revealed_fields(store, target_id)


static func reveal_fields(store: Dictionary, target_id: String, fields: Variant) -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not fields is Array:
		return warnings
	var key := _target_key(target_id)
	var revealed: Array = get_revealed_fields(store, target_id)
	for raw_field in fields:
		var field := str(raw_field).strip_edges()
		if field.is_empty():
			continue
		if field not in PROFILE_FIELDS:
			warnings.append("未知档案字段: %s" % field)
			continue
		if field not in revealed:
			revealed.append(field)
	store[key] = revealed
	return warnings


static func apply_discoveries(
	store: Dictionary,
	discoveries: Variant,
	_mainrole: Dictionary,
	npc_db: Dictionary,
) -> PackedStringArray:
	var warnings: PackedStringArray = []
	if not discoveries is Array:
		return warnings
	var npcs: Dictionary = npc_db.get("npcs", {}) if npc_db is Dictionary else {}
	for entry in discoveries:
		if not entry is Dictionary:
			continue
		var target := str(entry.get("target", "")).strip_edges()
		if target.is_empty():
			warnings.append("discoveries 缺少 target")
			continue
		if target != SELF_KEY:
			if not npcs.has(target):
				warnings.append("discoveries 目标不存在: %s" % target)
				continue
		warnings.append_array(reveal_fields(store, target, entry.get("fields", [])))
	return warnings


static func build_visible_profile(truth: Dictionary, store: Variant, target_id: String) -> Dictionary:
	var out: Dictionary = {}
	if truth.is_empty():
		return out
	for field in get_revealed_fields(store, target_id):
		if not truth.has(field):
			continue
		var value: Variant = truth[field]
		if field == "skills":
			if value is Array and (value as Array).is_empty():
				continue
		elif field == "abilities" or field == "psychology":
			if value is Dictionary and (value as Dictionary).is_empty():
				continue
		else:
			var visible := SkillDisplayCatalog.format_player_visible(value)
			if visible == "未知":
				continue
		out[field] = value
	return out


static func merge_protagonist_truth(mainrole: Dictionary, npc_profile: Dictionary) -> Dictionary:
	var truth := mainrole.duplicate(true)
	if npc_profile.is_empty():
		return truth
	for field in PROFILE_FIELDS:
		if not npc_profile.has(field):
			continue
		var value: Variant = npc_profile[field]
		if field == "abilities" or field == "psychology" or field == "skills":
			if not truth.has(field) or _is_empty_profile_value(truth.get(field)):
				truth[field] = value
		else:
			if _is_empty_profile_value(truth.get(field, null)):
				truth[field] = value
	return truth


static func build_snapshot_known(
	store: Variant,
	mainrole: Dictionary,
	npc_db: Dictionary,
	protagonist_id: String,
	nearby_npc_ids: Variant,
) -> Dictionary:
	var out: Dictionary = {}
	var npcs: Dictionary = npc_db.get("npcs", {}) if npc_db is Dictionary else {}
	var truth_self := merge_protagonist_truth(mainrole, npcs.get(protagonist_id, {}))
	out[SELF_KEY] = build_visible_profile(truth_self, store, SELF_KEY)
	if nearby_npc_ids is Array:
		for id_val in nearby_npc_ids:
			var npc_id := str(id_val).strip_edges()
			if npc_id.is_empty() or npc_id == protagonist_id:
				continue
			if npcs.has(npc_id):
				out[npc_id] = build_visible_profile(npcs[npc_id], store, npc_id)
	return out


static func _target_key(target_id: String) -> String:
	var tid := target_id.strip_edges()
	return SELF_KEY if tid == SELF_KEY else tid


static func _is_empty_profile_value(value: Variant) -> bool:
	if value == null:
		return true
	if value is String:
		return (value as String).strip_edges().is_empty()
	if value is int:
		return (value as int) <= 0
	if value is float:
		return (value as float) <= 0.0
	if value is Array:
		return (value as Array).is_empty()
	if value is Dictionary:
		return (value as Dictionary).is_empty()
	return str(value).strip_edges().is_empty()
