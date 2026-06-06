class_name GameRunningFileManager
extends RefCounted

const GameDataPathsScript := preload("res://src/game_running_file_manage/game_data_paths.gd")

## 管理游戏运行时写入 user:// 的动态数据（封包后仍落在用户目录）。
## 以 *_db.json 命名的文件为总表；mainrole.json 为主角运行时状态。

const DEFAULT_RUNTIME_DIR := "user://game_runtime_data/"

const ITEMS_DB := "items_db.json"
const WEAPON_DB := "weapon_db.json"
const NPC_DB := "npc_db.json"
const MAP_DB := "map_db.json"
const SKILLS_DB := "skills_db.json"
const MAIN_ROLE := "mainrole.json"
const GAME_STATE := "game_state.json"
const BASE_CONFIG := "baseConfig.json"
const BASE_CONFIG_DRAFT := "base_config_draft.json"
const SKILLS_DB_DRAFT := "skills_db_draft.json"
const WORLD_INIT_SETTING := "world_init_setting.json"
const WORLD_INIT_DRAFT := "world_init_draft.json"

const DB_FILE_NAMES: Array[StringName] = [
	ITEMS_DB,
	WEAPON_DB,
	NPC_DB,
	MAP_DB,
	SKILLS_DB,
]

const INIT_FILE_NAMES: Array[StringName] = [
	BASE_CONFIG,
	WORLD_INIT_SETTING,
]

## 阶段 3 产物：world_init 与 WorldInitSplitter 写入的运行时表。
const PHASE_3_RUNTIME_FILES: Array[StringName] = [
	WORLD_INIT_DRAFT,
	WORLD_INIT_SETTING,
	MAP_DB,
	NPC_DB,
	MAIN_ROLE,
	ITEMS_DB,
	WEAPON_DB,
	GAME_STATE,
]


static func all_runtime_file_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.assign(DB_FILE_NAMES)
	names.append_array(INIT_FILE_NAMES)
	names.append(MAIN_ROLE)
	names.append(GAME_STATE)
	return names


## 是否已有可继续的游戏存档（主角 + 基础世界配置）。
static func has_playable_save() -> bool:
	return exists(MAIN_ROLE) and exists(BASE_CONFIG)


static func is_db_file(file_name: String) -> bool:
	return file_name in DB_FILE_NAMES


static func runtime_dir() -> String:
	return GameDataPathsScript.runtime_dir()


static func runtime_file_path(file_name: String) -> String:
	return runtime_dir() + file_name


static func ensure_dir() -> bool:
	var dir := runtime_dir()
	if DirAccess.dir_exists_absolute(dir):
		return true
	var err := DirAccess.make_dir_recursive_absolute(dir)
	if err != OK:
		push_error("无法创建运行时数据目录: %s (error %d)" % [dir, err])
		return false
	return true


static func save_json(file_name: String, json_content: String) -> bool:
	if not ensure_dir():
		return false
	var path := runtime_file_path(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("无法写入运行时数据: " + path)
		return false
	file.store_string(json_content)
	return true


static func save_json_data(file_name: String, data: Variant, indent: String = "\t") -> bool:
	return save_json(file_name, JSON.stringify(data, indent))


static func load_json_text(file_name: String) -> String:
	var path := runtime_file_path(file_name)
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取运行时数据: " + path)
		return ""
	return file.get_as_text()


static func load_json_data(file_name: String) -> Variant:
	var text := load_json_text(file_name).strip_edges()
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("无法解析运行时 JSON: %s — %s" % [file_name, json.get_error_message()])
		return null
	return json.get_data()


static func exists(file_name: String) -> bool:
	return FileAccess.file_exists(runtime_file_path(file_name))


## 阶段 1/2 分片草稿（断点续跑用，完成后删除）。
const PHASE_12_DRAFT_FILES: Array[StringName] = [
	BASE_CONFIG_DRAFT,
	SKILLS_DB_DRAFT,
]


## 开始新游戏前清空已有运行时文件，避免与本次初始化数据混杂。
static func clear_all_runtime_files() -> bool:
	var names: Array[StringName] = []
	names.assign(all_runtime_file_names())
	names.append_array(PHASE_12_DRAFT_FILES)
	names.append(WORLD_INIT_DRAFT)
	return _remove_runtime_files(names)


## 从指定阶段起清理产物，用于重试时保留更早阶段的合格检查点。
## phase 1：等同 clear_all_runtime_files；2：删 skills_db 及阶段 3；3：仅删阶段 3。
static func clear_from_phase(phase: int) -> bool:
	match phase:
		1:
			return clear_all_runtime_files()
		2:
			var names: Array[StringName] = [SKILLS_DB]
			names.append_array(PHASE_3_RUNTIME_FILES)
			return _remove_runtime_files(names)
		3:
			return _remove_runtime_files(PHASE_3_RUNTIME_FILES)
		_:
			push_error("clear_from_phase: 无效阶段 %d" % phase)
			return false


## 删除阶段 3 最终产物，保留 world_init_draft.json（子步骤续跑用）。
static func clear_phase3_final_outputs() -> bool:
	var names: Array[StringName] = []
	for file_name in PHASE_3_RUNTIME_FILES:
		if file_name != WORLD_INIT_DRAFT:
			names.append(file_name)
	return _remove_runtime_files(names)


static func _remove_runtime_files(file_names: Array) -> bool:
	if not ensure_dir():
		return false
	for file_name in file_names:
		var path := runtime_file_path(str(file_name))
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				push_error("无法删除运行时数据: %s (error %d)" % [path, err])
				return false
	return true
