extends RefCounted

## 阶段 1 分片草稿：nature_env → people_env → social_env → 写入 baseConfig.json。

const SLICE_NATURE_ENV := 1
const SLICE_PEOPLE_ENV := 2
const SLICE_SOCIAL_ENV := 3
const SLICE_COUNT := 3

const KEY_NOVEL_TYPE := "novel_type"
const KEY_WORLD_SETTING := "world_setting"
const KEY_BUILD_SLICE := "build_slice"

const SLICE_FIELD_KEYS: Dictionary = {
	SLICE_NATURE_ENV: "nature_env",
	SLICE_PEOPLE_ENV: "people_env",
	SLICE_SOCIAL_ENV: "social_env",
}


static func load_or_empty() -> Dictionary:
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.BASE_CONFIG_DRAFT)
	if loaded is Dictionary:
		return (loaded as Dictionary).duplicate(true)
	return {}


static func save(draft: Dictionary) -> bool:
	return GameRunningFileManager.save_json_data(GameRunningFileManager.BASE_CONFIG_DRAFT, draft)


static func delete_file() -> bool:
	var path := GameRunningFileManager.runtime_file_path(GameRunningFileManager.BASE_CONFIG_DRAFT)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		return err == OK
	return true


static func empty_draft(novel_type: String) -> Dictionary:
	return {
		KEY_NOVEL_TYPE: novel_type.strip_edges(),
		KEY_WORLD_SETTING: {},
		KEY_BUILD_SLICE: SLICE_NATURE_ENV,
	}


static func detect_next_slice(draft: Dictionary) -> int:
	if draft.is_empty():
		return SLICE_NATURE_ENV
	for slice in [SLICE_NATURE_ENV, SLICE_PEOPLE_ENV, SLICE_SOCIAL_ENV]:
		var field_key: String = SLICE_FIELD_KEYS[slice]
		var ws_val: Variant = draft.get(KEY_WORLD_SETTING, {})
		if not ws_val is Dictionary:
			return slice
		var ws: Dictionary = ws_val
		if not AiResponseParser.validate_base_config_slice(slice, {field_key: ws.get(field_key, null)}):
			return slice
	return SLICE_COUNT + 1


static func slice_label(slice: int) -> String:
	match slice:
		SLICE_NATURE_ENV:
			return "自然与环境"
		SLICE_PEOPLE_ENV:
			return "人文与设施"
		SLICE_SOCIAL_ENV:
			return "社会与冲突"
		_:
			return "未知分片"


static func apply_slice(draft: Dictionary, slice: int, field_data: Dictionary) -> void:
	var field_key: String = SLICE_FIELD_KEYS.get(slice, "")
	if field_key.is_empty():
		return
	var ws_val: Variant = draft.get(KEY_WORLD_SETTING, {})
	var ws: Dictionary = ws_val if ws_val is Dictionary else {}
	ws[field_key] = field_data.duplicate(true)
	draft[KEY_WORLD_SETTING] = ws
	draft[KEY_BUILD_SLICE] = mini(slice + 1, SLICE_COUNT + 1)


static func to_base_config(draft: Dictionary) -> Dictionary:
	return {
		"novel_type": str(draft.get(KEY_NOVEL_TYPE, "")).strip_edges(),
		"world_setting": (draft.get(KEY_WORLD_SETTING, {}) as Dictionary).duplicate(true),
	}


static func clear_from_slice(draft: Dictionary, from_slice: int) -> void:
	match from_slice:
		SLICE_NATURE_ENV:
			var novel_type := str(draft.get(KEY_NOVEL_TYPE, "")).strip_edges()
			draft.clear()
			draft.merge(empty_draft(novel_type if not novel_type.is_empty() else "历史"), true)
		SLICE_PEOPLE_ENV:
			_erase_world_field(draft, "people_env")
			_erase_world_field(draft, "social_env")
			draft[KEY_BUILD_SLICE] = SLICE_PEOPLE_ENV
		SLICE_SOCIAL_ENV:
			_erase_world_field(draft, "social_env")
			draft[KEY_BUILD_SLICE] = SLICE_SOCIAL_ENV
		_:
			pass


static func has_meaningful_checkpoint(draft: Dictionary) -> bool:
	return detect_next_slice(draft) > SLICE_NATURE_ENV


static func completed_slices_json(draft: Dictionary) -> String:
	var ws_val: Variant = draft.get(KEY_WORLD_SETTING, {})
	if ws_val is Dictionary and not (ws_val as Dictionary).is_empty():
		return PromptBuilder.compact_base_config_json({
			"novel_type": str(draft.get(KEY_NOVEL_TYPE, "")).strip_edges(),
			"world_setting": ws_val,
		}, 600)
	return "{}"


static func _erase_world_field(draft: Dictionary, field_key: String) -> void:
	var ws_val: Variant = draft.get(KEY_WORLD_SETTING, {})
	if not ws_val is Dictionary:
		return
	var ws: Dictionary = (ws_val as Dictionary).duplicate(true)
	ws.erase(field_key)
	draft[KEY_WORLD_SETTING] = ws
