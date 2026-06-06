extends VBoxContainer

const GameDataPathsScript := preload("res://src/game_running_file_manage/game_data_paths.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")

const RESOLUTION_PRESETS: PackedStringArray = [
	"1280x720",
	"1600x900",
	"1920x1080",
	"2560x1440",
]

const WINDOW_MODE_OPTIONS: PackedStringArray = [
	"窗口化",
	"全屏",
	"无边框全屏",
]

const LANGUAGE_OPTIONS: PackedStringArray = [
	"中文",
	"English",
]

const DEFAULT_RESOLUTION := "1920x1080"
const DEFAULT_WINDOW_MODE := "窗口化"
const DEFAULT_LANGUAGE := "中文"

const FOLDER_DIALOG_MIN_SIZE := Vector2i(900, 520)
const FOLDER_DIALOG_VIEWPORT_RATIO := 0.72
const FOLDER_DIALOG_VIEWPORT_MARGIN := 80

@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value_label: Label = %VolumeValueLabel
@onready var _language_option: OptionButton = %LanguageOption
@onready var _resolution_option: OptionButton = %ResolutionOption
@onready var _window_mode_option: OptionButton = %WindowModeOption
@onready var _data_root_edit: LineEdit = %DataRootEdit
@onready var _data_root_browse_button: Button = %DataRootBrowseButton
@onready var _data_root_reset_button: Button = %DataRootResetButton
@onready var _data_root_folder_dialog: FileDialog = %DataRootFolderDialog

var _stored_data_root_dir: String = GameDataPathsScript.DEFAULT_DATA_ROOT


func _ready() -> void:
	_init_option_button(_language_option, LANGUAGE_OPTIONS)
	_init_option_button(_resolution_option, RESOLUTION_PRESETS)
	_init_option_button(_window_mode_option, WINDOW_MODE_OPTIONS)
	_select_option_by_text(_language_option, DEFAULT_LANGUAGE)
	_select_option_by_text(_resolution_option, DEFAULT_RESOLUTION)
	_select_option_by_text(_window_mode_option, DEFAULT_WINDOW_MODE)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_update_volume_label(_volume_slider.value)

	UiStylesScript.apply_secondary_button(_data_root_browse_button)
	UiStylesScript.apply_secondary_button(_data_root_reset_button)
	_data_root_browse_button.pressed.connect(_on_data_root_browse_pressed)
	_data_root_reset_button.pressed.connect(_on_data_root_reset_pressed)
	_configure_folder_dialog()
	_data_root_folder_dialog.dir_selected.connect(_on_data_root_dir_selected)
	_set_data_root_display(GameDataPathsScript.DEFAULT_DATA_ROOT)


func _init_option_button(button: OptionButton, items: PackedStringArray) -> void:
	button.clear()
	for item in items:
		button.add_item(item)


func _on_volume_changed(value: float) -> void:
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	if _volume_value_label:
		_volume_value_label.text = "%d" % int(round(value))


func _get_selected_text(option: OptionButton) -> String:
	var idx := option.selected
	if idx >= 0 and idx < option.item_count:
		return option.get_item_text(idx)
	return ""


func _select_option_by_text(option: OptionButton, text: String) -> void:
	for i in option.item_count:
		if option.get_item_text(i) == text:
			option.select(i)
			return


func _configure_folder_dialog() -> void:
	_data_root_folder_dialog.title = "选择游戏数据存放目录"
	_data_root_folder_dialog.ok_button_text = "选择此文件夹"
	_data_root_folder_dialog.min_size = FOLDER_DIALOG_MIN_SIZE
	_data_root_folder_dialog.unresizable = true
	_data_root_folder_dialog.use_native_dialog = false
	_data_root_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_data_root_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM


func _set_data_root_display(storage_path: String) -> void:
	_stored_data_root_dir = GameDataPathsScript.normalize_root_dir(storage_path)
	if _data_root_edit:
		_data_root_edit.text = GameDataPathsScript.display_path(_stored_data_root_dir)


func _on_data_root_browse_pressed() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var max_fit := Vector2i(
		maxi(640, int(viewport_size.x) - FOLDER_DIALOG_VIEWPORT_MARGIN),
		maxi(480, int(viewport_size.y) - FOLDER_DIALOG_VIEWPORT_MARGIN),
	)
	_data_root_folder_dialog.max_size = max_fit
	_data_root_folder_dialog.min_size = Vector2i(
		mini(FOLDER_DIALOG_MIN_SIZE.x, max_fit.x),
		mini(FOLDER_DIALOG_MIN_SIZE.y, max_fit.y),
	)
	_data_root_folder_dialog.reset_size()
	_data_root_folder_dialog.popup_centered_ratio(FOLDER_DIALOG_VIEWPORT_RATIO)


func _on_data_root_dir_selected(dir: String) -> void:
	_set_data_root_display(GameDataPathsScript.to_storage_path(dir))


func _on_data_root_reset_pressed() -> void:
	_set_data_root_display(GameDataPathsScript.DEFAULT_DATA_ROOT)


func get_config() -> Dictionary:
	var data_root := _stored_data_root_dir
	if _data_root_edit:
		data_root = GameDataPathsScript.to_storage_path(_data_root_edit.text)
	return {
		"volume": _volume_slider.value,
		"language": _get_selected_text(_language_option),
		"resolution": _get_selected_text(_resolution_option),
		"window_mode": _get_selected_text(_window_mode_option),
		"data_root_dir": data_root,
	}


func set_config(data: Dictionary) -> void:
	if data.is_empty():
		return

	if data.has("volume"):
		var vol: float = float(data["volume"])
		_volume_slider.value = vol
		_update_volume_label(_volume_slider.value)

	if data.has("language") and data["language"] is String:
		_select_option_by_text(_language_option, data["language"])

	if data.has("resolution") and data["resolution"] is String:
		_select_option_by_text(_resolution_option, data["resolution"])

	if data.has("window_mode") and data["window_mode"] is String:
		_select_option_by_text(_window_mode_option, data["window_mode"])

	if data.has("data_root_dir") and data["data_root_dir"] is String:
		_set_data_root_display(data["data_root_dir"])
