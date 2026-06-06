extends RefCounted

## 统一管理游戏数据根目录及其下的运行时/历史子目录。

const DEFAULT_DATA_ROOT := "user://"
const RUNTIME_SUBDIR := "game_runtime_data/"
const HISTORY_SUBDIR := "game_history/"

static var _data_root_dir: String = DEFAULT_DATA_ROOT


static func set_data_root_dir(root: String) -> void:
	_data_root_dir = normalize_root_dir(root)


static func get_data_root_dir() -> String:
	return _data_root_dir


static func normalize_root_dir(root: String) -> String:
	var trimmed := root.strip_edges().replace("\\", "/")
	if trimmed.is_empty():
		return DEFAULT_DATA_ROOT
	if not trimmed.ends_with("/"):
		trimmed += "/"
	return trimmed


static func runtime_dir() -> String:
	return normalize_root_dir(_data_root_dir) + RUNTIME_SUBDIR


static func history_dir() -> String:
	return normalize_root_dir(_data_root_dir) + HISTORY_SUBDIR


static func display_path(root: String = "") -> String:
	var normalized := normalize_root_dir(root if not root.is_empty() else _data_root_dir)
	if normalized.begins_with("user://"):
		return ProjectSettings.globalize_path(normalized).replace("\\", "/")
	return normalized


static func to_storage_path(display_or_storage: String) -> String:
	var trimmed := display_or_storage.strip_edges().replace("\\", "/")
	if trimmed.is_empty():
		return DEFAULT_DATA_ROOT
	if trimmed.begins_with("user://"):
		return normalize_root_dir(trimmed)
	var global_user := ProjectSettings.globalize_path(DEFAULT_DATA_ROOT).replace("\\", "/").rstrip("/")
	if trimmed.rstrip("/") == global_user:
		return DEFAULT_DATA_ROOT
	return normalize_root_dir(trimmed)


static func migrate_data_root(from_root: String, to_root: String) -> Dictionary:
	var from := normalize_root_dir(from_root)
	var to := normalize_root_dir(to_root)
	if from == to:
		return {"ok": true, "error": "", "copied_dirs": 0}

	var copied_dirs := 0
	for subdir in [RUNTIME_SUBDIR, HISTORY_SUBDIR]:
		var src: String = from + subdir
		var dest: String = to + subdir
		if not DirAccess.dir_exists_absolute(src):
			continue
		if not _copy_dir_recursive(src, dest):
			return {
				"ok": false,
				"error": "无法复制目录: %s" % subdir,
				"copied_dirs": copied_dirs,
			}
		copied_dirs += 1

	return {"ok": true, "error": "", "copied_dirs": copied_dirs}


static func _copy_dir_recursive(src_dir: String, dest_dir: String) -> bool:
	if not DirAccess.dir_exists_absolute(src_dir):
		return true

	var err := DirAccess.make_dir_recursive_absolute(dest_dir)
	if err != OK:
		return false

	var dir := DirAccess.open(src_dir)
	if dir == null:
		return false

	for file_name in dir.get_files():
		var src_path := src_dir + file_name
		var dest_path := dest_dir + file_name
		if FileAccess.file_exists(dest_path):
			var remove_err := DirAccess.remove_absolute(dest_path)
			if remove_err != OK:
				return false
		err = DirAccess.copy_absolute(src_path, dest_path)
		if err != OK:
			return false

	for subdir_name in dir.get_directories():
		if not _copy_dir_recursive(src_dir + subdir_name + "/", dest_dir + subdir_name + "/"):
			return false

	return true
