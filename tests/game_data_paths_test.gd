## 游戏数据路径与设置（`godot --headless -s tests/game_data_paths_test.gd`）
extends SceneTree

const PathsScript := preload("res://src/game_running_file_manage/game_data_paths.gd")
const ApplierScript := preload("res://src/settings/game_settings_applier.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_normalize_root_dir()
	failed += _test_runtime_and_history_dirs()
	failed += _test_display_and_storage_path()
	failed += _test_migrate_same_root()
	failed += _test_default_config_has_data_root()
	failed += _test_parse_resolution()
	failed += _test_window_mode_labels()
	if failed == 0:
		print("[OK] game_data_paths tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_normalize_root_dir() -> int:
	if PathsScript.normalize_root_dir("") != "user://":
		push_error("normalize_root_dir: empty")
		return 1
	if PathsScript.normalize_root_dir("user://") != "user://":
		push_error("normalize_root_dir: user://")
		return 1
	if PathsScript.normalize_root_dir("D:/GameData") != "D:/GameData/":
		push_error("normalize_root_dir: D:/GameData")
		return 1
	if PathsScript.normalize_root_dir("D:/GameData/") != "D:/GameData/":
		push_error("normalize_root_dir: D:/GameData/")
		return 1
	return 0


func _test_runtime_and_history_dirs() -> int:
	PathsScript.set_data_root_dir("user://")
	if PathsScript.runtime_dir() != "user://game_runtime_data/":
		push_error("runtime_dir user://")
		return 1
	if PathsScript.history_dir() != "user://game_history/":
		push_error("history_dir user://")
		return 1

	PathsScript.set_data_root_dir("D:/SaveRoot/")
	if PathsScript.runtime_dir() != "D:/SaveRoot/game_runtime_data/":
		push_error("runtime_dir D:/SaveRoot/")
		return 1
	if PathsScript.history_dir() != "D:/SaveRoot/game_history/":
		push_error("history_dir D:/SaveRoot/")
		return 1
	return 0


func _test_display_and_storage_path() -> int:
	PathsScript.set_data_root_dir("user://")
	var display := PathsScript.display_path("user://")
	if display.is_empty():
		push_error("display_path should not be empty")
		return 1
	if PathsScript.to_storage_path(display) != "user://":
		push_error("to_storage_path round-trip user://")
		return 1
	if PathsScript.to_storage_path("user://custom/") != "user://custom/":
		push_error("to_storage_path custom")
		return 1
	return 0


func _test_migrate_same_root() -> int:
	var result := PathsScript.migrate_data_root("user://", "user://")
	if not result.get("ok", false):
		push_error("migrate same root should ok")
		return 1
	if int(result.get("copied_dirs", -1)) != 0:
		push_error("migrate same root should copy 0 dirs")
		return 1
	return 0


func _test_default_config_has_data_root() -> int:
	var cfg := ApplierScript.default_game_config()
	if not cfg.has("data_root_dir"):
		push_error("default config missing data_root_dir")
		return 1
	if cfg["data_root_dir"] != "user://":
		push_error("default data_root_dir should be user://")
		return 1
	return 0


func _test_parse_resolution() -> int:
	if ApplierScript.parse_resolution("1920x1080") != Vector2i(1920, 1080):
		push_error("parse_resolution 1920x1080")
		return 1
	if ApplierScript.parse_resolution("1280x720") != Vector2i(1280, 720):
		push_error("parse_resolution 1280x720")
		return 1
	if ApplierScript.parse_resolution("invalid") != Vector2i(1920, 1080):
		push_error("parse_resolution invalid fallback")
		return 1
	return 0


func _test_window_mode_labels() -> int:
	var labels := ApplierScript.WINDOW_MODE_BY_LABEL
	if not labels.has("窗口化"):
		push_error("window mode missing 窗口化")
		return 1
	if not labels.has("全屏"):
		push_error("window mode missing 全屏")
		return 1
	if not labels.has("无边框全屏"):
		push_error("window mode missing 无边框全屏")
		return 1
	return 0
