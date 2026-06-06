extends RefCounted

## 阶段 2 技能批次草稿：战斗/行动 → 社交/调查 → 生存/专业 → 写入 skills_db.json。

const BATCH_COMBAT := 1
const BATCH_SOCIAL := 2
const BATCH_SURVIVAL := 3
const BATCH_COUNT := 3

const MIN_TOTAL_SKILLS := 8
const MIN_BATCH_SIZE := 3
const MAX_BATCH_SIZE := 5

const KEY_SKILLS := "skills"
const KEY_BATCH_SKILLS := "batch_skills"
const KEY_COMPLETED_BATCHES := "completed_batches"
const KEY_BUILD_BATCH := "build_batch"


static func load_or_empty() -> Dictionary:
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.SKILLS_DB_DRAFT)
	if loaded is Dictionary:
		return (loaded as Dictionary).duplicate(true)
	return {}


static func save(draft: Dictionary) -> bool:
	return GameRunningFileManager.save_json_data(GameRunningFileManager.SKILLS_DB_DRAFT, draft)


static func delete_file() -> bool:
	var path := GameRunningFileManager.runtime_file_path(GameRunningFileManager.SKILLS_DB_DRAFT)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		return err == OK
	return true


static func empty_draft() -> Dictionary:
	return {
		KEY_SKILLS: [],
		KEY_BATCH_SKILLS: {},
		KEY_COMPLETED_BATCHES: [],
		KEY_BUILD_BATCH: BATCH_COMBAT,
	}


static func detect_next_batch(draft: Dictionary) -> int:
	if draft.is_empty():
		return BATCH_COMBAT
	var completed: Array = _completed_batches(draft)
	for batch in [BATCH_COMBAT, BATCH_SOCIAL, BATCH_SURVIVAL]:
		if batch not in completed:
			return batch
	return BATCH_COUNT + 1


static func batch_label(batch: int) -> String:
	match batch:
		BATCH_COMBAT:
			return "战斗与行动标签"
		BATCH_SOCIAL:
			return "社交与调查标签"
		BATCH_SURVIVAL:
			return "生存与专业标签"
		_:
			return "未知批次"


static func append_batch(draft: Dictionary, batch: int, skills: Array) -> void:
	var batch_map_val: Variant = draft.get(KEY_BATCH_SKILLS, {})
	var batch_map: Dictionary = batch_map_val if batch_map_val is Dictionary else {}
	batch_map[str(batch)] = skills.duplicate(true)
	draft[KEY_BATCH_SKILLS] = batch_map
	var completed: Array = _completed_batches(draft)
	if batch not in completed:
		completed.append(batch)
	draft[KEY_COMPLETED_BATCHES] = completed
	draft[KEY_BUILD_BATCH] = mini(batch + 1, BATCH_COUNT + 1)
	_rebuild_merged_skills(draft)


static func to_skills_payload(draft: Dictionary) -> Dictionary:
	return {"skills": _ensure_skills_array(draft).duplicate(true)}


static func clear_from_batch(draft: Dictionary, from_batch: int) -> void:
	var completed: Array = _completed_batches(draft)
	var keep_completed: Array = []
	for b in completed:
		if int(b) < from_batch:
			keep_completed.append(b)
	draft[KEY_COMPLETED_BATCHES] = keep_completed
	var batch_map_val: Variant = draft.get(KEY_BATCH_SKILLS, {})
	if batch_map_val is Dictionary:
		var batch_map: Dictionary = (batch_map_val as Dictionary).duplicate(true)
		for b in [BATCH_COMBAT, BATCH_SOCIAL, BATCH_SURVIVAL]:
			if b >= from_batch:
				batch_map.erase(str(b))
		draft[KEY_BATCH_SKILLS] = batch_map
	draft[KEY_BUILD_BATCH] = from_batch
	_rebuild_merged_skills(draft)


static func existing_skill_ids_json(draft: Dictionary) -> String:
	var ids: Array[String] = []
	for skill in _ensure_skills_array(draft):
		if skill is Dictionary:
			var sid := str(skill.get("id", "")).strip_edges()
			if not sid.is_empty() and sid not in ids:
				ids.append(sid)
	return JSON.stringify(ids, "\t")


static func skill_count(draft: Dictionary) -> int:
	return _ensure_skills_array(draft).size()


static func _completed_batches(draft: Dictionary) -> Array:
	var val: Variant = draft.get(KEY_COMPLETED_BATCHES, [])
	return val if val is Array else []


static func _ensure_skills_array(draft: Dictionary) -> Array:
	var val: Variant = draft.get(KEY_SKILLS, [])
	return val if val is Array else []


static func _rebuild_merged_skills(draft: Dictionary) -> void:
	var merged: Array = []
	var seen: Dictionary = {}
	var batch_map_val: Variant = draft.get(KEY_BATCH_SKILLS, {})
	if not batch_map_val is Dictionary:
		draft[KEY_SKILLS] = merged
		return
	for batch in [BATCH_COMBAT, BATCH_SOCIAL, BATCH_SURVIVAL]:
		var batch_skills_val: Variant = (batch_map_val as Dictionary).get(str(batch), null)
		if not batch_skills_val is Array:
			continue
		for skill in batch_skills_val:
			if not skill is Dictionary:
				continue
			var sid := str(skill.get("id", "")).strip_edges()
			if sid.is_empty() or seen.has(sid):
				continue
			merged.append((skill as Dictionary).duplicate(true))
			seen[sid] = true
	draft[KEY_SKILLS] = merged
