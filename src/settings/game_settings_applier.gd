extends Node

const GameDataPathsScript := preload("res://src/game_running_file_manage/game_data_paths.gd")

const CONFIG_PATH := "user://ai_config/aiConfig.json"
const CONFIG_PATH_DEFAULT := "res://ai_config/aiConfig.json"

const DEFAULT_RESOLUTION := "1920x1080"
const DEFAULT_WINDOW_MODE := "窗口化"

const WINDOW_MODE_BY_LABEL: Dictionary = {
	"窗口化": DisplayServer.WINDOW_MODE_WINDOWED,
	"全屏": DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	"无边框全屏": DisplayServer.WINDOW_MODE_FULLSCREEN,
}


func _ready() -> void:
	apply_from_saved_config()


static func apply_from_saved_config() -> void:
	var game_config := load_game_config()
	apply_game_settings(game_config)


static func load_game_config() -> Dictionary:
	var path := CONFIG_PATH
	if not FileAccess.file_exists(path):
		path = CONFIG_PATH_DEFAULT
		if not FileAccess.file_exists(path):
			return default_game_config()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return default_game_config()
	var text := file.get_as_text()
	file.close()
	if text.is_empty():
		return default_game_config()
	var json = JSON.parse_string(text)
	if json is Dictionary and json.has("game") and json["game"] is Dictionary:
		return json["game"]
	return default_game_config()


static func default_game_config() -> Dictionary:
	return {
		"volume": 80.0,
		"language": "中文",
		"resolution": DEFAULT_RESOLUTION,
		"window_mode": DEFAULT_WINDOW_MODE,
		"data_root_dir": GameDataPathsScript.DEFAULT_DATA_ROOT,
	}


static func apply_data_paths(game_config: Dictionary) -> void:
	var root := str(game_config.get("data_root_dir", GameDataPathsScript.DEFAULT_DATA_ROOT))
	GameDataPathsScript.set_data_root_dir(root)


static func apply_game_settings(game_config: Dictionary) -> void:
	apply_data_paths(game_config)
	var resolution_str: String = str(game_config.get("resolution", DEFAULT_RESOLUTION))
	var window_mode_str: String = str(game_config.get("window_mode", DEFAULT_WINDOW_MODE))
	var size := parse_resolution(resolution_str)
	var mode: DisplayServer.WindowMode = WINDOW_MODE_BY_LABEL.get(
		window_mode_str,
		DisplayServer.WINDOW_MODE_WINDOWED
	)

	match mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(size)
			_center_window()
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


static func parse_resolution(resolution_str: String) -> Vector2i:
	var parts := resolution_str.split("x", false)
	if parts.size() == 2:
		var w := int(parts[0])
		var h := int(parts[1])
		if w > 0 and h > 0:
			return Vector2i(w, h)
	return Vector2i(1920, 1080)


static func _center_window() -> void:
	var screen_idx := DisplayServer.window_get_current_screen()
	var screen_pos := DisplayServer.screen_get_position(screen_idx)
	var screen_size := DisplayServer.screen_get_size(screen_idx)
	var window_size := DisplayServer.window_get_size()
	var center_offset := (Vector2(screen_size) - Vector2(window_size)) * 0.5
	var pos := Vector2(screen_pos) + center_offset
	DisplayServer.window_set_position(pos.round())
