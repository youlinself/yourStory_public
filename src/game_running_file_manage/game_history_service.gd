class_name GameHistoryService
extends RefCounted

const GameDataPathsScript := preload("res://src/game_running_file_manage/game_data_paths.gd")

## 归档已完成或已被新游戏取代的运行时局，供主菜单「游戏记录」只读回顾。

const DEFAULT_HISTORY_DIR := "user://game_history/"
const INDEX_FILE := "index.json"

const ARCHIVE_FILES: Array[StringName] = [
	GameRunningFileManager.GAME_STATE,
	GameRunningFileManager.MAP_DB,
	GameRunningFileManager.MAIN_ROLE,
	GameRunningFileManager.BASE_CONFIG,
]


static func generate_session_id() -> String:
	var unix := int(Time.get_unix_time_from_system())
	var rand_hex := String.num_uint64(randi(), 16)
	return "%d_%s" % [unix, rand_hex]


static func has_any_history() -> bool:
	return not list_sessions().is_empty()


static func history_dir() -> String:
	return GameDataPathsScript.history_dir()


static func get_session_dir(session_id: String) -> String:
	return history_dir() + session_id.strip_edges() + "/"


static func load_session_dir(session_id: String) -> String:
	var id := session_id.strip_edges()
	if id.is_empty():
		return ""
	var dir := get_session_dir(id)
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	return dir


static func list_sessions() -> Array[Dictionary]:
	var index := _load_index()
	var sessions: Array = index.get("sessions", [])
	if not sessions is Array:
		return []
	var out: Array[Dictionary] = []
	for item in sessions:
		if item is Dictionary:
			out.append(item)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("archived_at", 0)) > int(b.get("archived_at", 0))
	)
	return out


static func archive_current_session() -> bool:
	if not GameRunningFileManager.has_playable_save():
		return true

	var game_state := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.GAME_STATE))
	var map_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB))
	var mainrole := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAIN_ROLE))

	var session_id := str(game_state.get("session_id", "")).strip_edges()
	if session_id.is_empty():
		session_id = generate_session_id()
		game_state["session_id"] = session_id

	var session_dir := get_session_dir(session_id)
	if not _ensure_session_dir(session_dir):
		return false

	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, game_state):
		push_warning("GameHistoryService: 无法回写 session_id 到运行时 game_state")

	for file_name in ARCHIVE_FILES:
		if not _copy_runtime_file_to_session(file_name, session_dir):
			return false

	var events := _extract_events(game_state)
	var summary := _build_index_entry(session_id, game_state, map_db, mainrole, events)
	if not _append_index_entry(summary):
		return false

	return true


static func _build_index_entry(
	session_id: String,
	game_state: Dictionary,
	map_db: Dictionary,
	mainrole: Dictionary,
	events: Array,
) -> Dictionary:
	var novel_type := str(game_state.get("novel_type", "")).strip_edges()
	if novel_type.is_empty():
		novel_type = str(map_db.get("novel_type", "")).strip_edges()

	var protagonist_name := _protagonist_display_name(mainrole)
	var last_title := ""
	if not events.is_empty():
		var last: Dictionary = events[events.size() - 1]
		last_title = str(last.get("title", "")).strip_edges()

	return {
		"id": session_id,
		"novel_type": novel_type,
		"protagonist_name": protagonist_name,
		"started_at": int(game_state.get("started_at", 0)),
		"archived_at": int(Time.get_unix_time_from_system()),
		"event_count": events.size(),
		"last_event_title": last_title,
	}


static func _protagonist_display_name(mainrole: Dictionary) -> String:
	var raw := str(mainrole.get("name", "")).strip_edges()
	if raw.is_empty():
		return "主角"
	return SkillDisplayCatalog.format_player_visible(raw)


static func _extract_events(game_state: Dictionary) -> Array:
	var raw: Variant = game_state.get("event_log", [])
	if not raw is Array:
		return []
	var events: Array = []
	for item in raw:
		if item is Dictionary:
			events.append(item)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("timestamp", 0)) < int(b.get("timestamp", 0))
	)
	return events


static func _copy_runtime_file_to_session(file_name: String, session_dir: String) -> bool:
	var src_path := GameRunningFileManager.runtime_file_path(file_name)
	if not FileAccess.file_exists(src_path):
		if file_name == GameRunningFileManager.BASE_CONFIG:
			return true
		push_error("GameHistoryService: 缺少归档源文件 %s" % file_name)
		return false

	var text := GameRunningFileManager.load_json_text(file_name)
	if text.is_empty() and file_name != GameRunningFileManager.BASE_CONFIG:
		push_error("GameHistoryService: 无法读取 %s" % file_name)
		return false

	var dest_path := session_dir + file_name
	var file := FileAccess.open(dest_path, FileAccess.WRITE)
	if file == null:
		push_error("GameHistoryService: 无法写入 %s" % dest_path)
		return false
	file.store_string(text)
	return true


static func _ensure_session_dir(session_dir: String) -> bool:
	var root := history_dir()
	if not DirAccess.dir_exists_absolute(root):
		var dir_err := DirAccess.make_dir_recursive_absolute(root)
		if dir_err != OK:
			push_error("GameHistoryService: 无法创建历史目录")
			return false
	if DirAccess.dir_exists_absolute(session_dir):
		return true
	var session_err := DirAccess.make_dir_recursive_absolute(session_dir)
	if session_err != OK:
		push_error("GameHistoryService: 无法创建会话目录 %s" % session_dir)
		return false
	return true


static func _load_index() -> Dictionary:
	var path := history_dir() + INDEX_FILE
	if not FileAccess.file_exists(path):
		return {"sessions": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"sessions": []}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("GameHistoryService: index.json 解析失败")
		return {"sessions": []}
	var data: Variant = json.get_data()
	return data if data is Dictionary else {"sessions": []}


static func _save_index(index: Dictionary) -> bool:
	var root := history_dir()
	if not DirAccess.dir_exists_absolute(root):
		var err := DirAccess.make_dir_recursive_absolute(root)
		if err != OK:
			return false
	var path := root + INDEX_FILE
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameHistoryService: 无法写入 index.json")
		return false
	file.store_string(JSON.stringify(index, "\t"))
	return true


static func _append_index_entry(entry: Dictionary) -> bool:
	var index := _load_index()
	var sessions: Array = index.get("sessions", [])
	if not sessions is Array:
		sessions = []

	var entry_id := str(entry.get("id", "")).strip_edges()
	var filtered: Array = []
	for item in sessions:
		if not item is Dictionary:
			continue
		if str(item.get("id", "")).strip_edges() == entry_id:
			continue
		filtered.append(item)
	filtered.append(entry)
	index["sessions"] = filtered
	return _save_index(index)


static func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}
