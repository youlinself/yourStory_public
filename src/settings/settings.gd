extends Control

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiBindScript := preload("res://src/ui/ui_bind.gd")
const GameSettingsApplierScript := preload("res://src/settings/game_settings_applier.gd")
const GameDataPathsScript := preload("res://src/game_running_file_manage/game_data_paths.gd")

const TAB_SCENES := {
	"game": "res://sences/settings/sub/settings_game.tscn",
	"ai": "res://sences/settings/sub/settings_ai.tscn",
	"about": "res://sences/settings/sub/settings_about.tscn",
}

const TAB_ORDER: PackedStringArray = ["game", "ai", "about"]

const CONFIG_PATH := "user://ai_config/aiConfig.json"
const CONFIG_PATH_DEFAULT := "res://ai_config/aiConfig.json"

@onready var _tab_host: MarginContainer = %TabMargins
@onready var _save_button: Button = %SaveButton

var _tab_buttons: Array[Button] = []
var _tab_instances: Dictionary = {}
var _current_key: String = ""
var _saved_config: Dictionary = {}


func _ready() -> void:
    UiRootScript.apply_to(self)
    _style_settings_chrome()
    _tab_buttons = [
        UiBindScript.find_named(self, "GameTab") as Button,
        UiBindScript.find_named(self, "AITab") as Button,
        UiBindScript.find_named(self, "AboutTab") as Button,
    ]
    UiBindScript.connect_pressed(self, "BackButton", _on_back_pressed)
    UiBindScript.connect_pressed(self, "GameTab", _on_tab_pressed.bind("game"))
    UiBindScript.connect_pressed(self, "AITab", _on_tab_pressed.bind("ai"))
    UiBindScript.connect_pressed(self, "AboutTab", _on_tab_pressed.bind("about"))
    if _save_button:
        _save_button.pressed.connect(_on_save_pressed)
    else:
        UiBindScript.connect_pressed(self, "SaveButton", _on_save_pressed)
    _load_config()
    _select_tab("game")


func _on_tab_pressed(key: String) -> void:
    _select_tab(key)


func _select_tab(key: String) -> void:
    var active := _tab_button(key)
    if _current_key == key:
        if active:
            active.button_pressed = true
        return
    _current_key = key

    for btn in _tab_buttons:
        if btn:
            btn.button_pressed = false
    if active:
        active.button_pressed = true

    for child in _tab_host.get_children():
        _tab_host.remove_child(child)

    if not _tab_instances.has(key):
        var scene := load(TAB_SCENES[key]) as PackedScene
        _tab_instances[key] = scene.instantiate()
    var tab := _tab_instances[key] as Control
    tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _tab_host.add_child(tab)

    if _saved_config.has(key):
        _apply_saved_config.call_deferred(key)


func _tab_index(key: String) -> int:
    return TAB_ORDER.find(key)


func _tab_button(key: String) -> Button:
    var idx := _tab_index(key)
    if idx >= 0 and idx < _tab_buttons.size():
        return _tab_buttons[idx]
    return UiBindScript.find_named(self, "%sTab" % key.capitalize()) as Button


func _load_config() -> void:
    var path := CONFIG_PATH
    if not FileAccess.file_exists(path):
        path = CONFIG_PATH_DEFAULT
        if not FileAccess.file_exists(path):
            return
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return
    var text := file.get_as_text()
    if text.is_empty():
        return
    var json = JSON.parse_string(text)
    if json is Dictionary:
        _saved_config = json


func _apply_saved_config(key: String) -> void:
    if not _tab_instances.has(key):
        return
    var instance = _tab_instances[key]
    if instance.has_method("set_config"):
        instance.set_config(_saved_config[key])


func _on_save_pressed() -> void:
    var config: Dictionary = _saved_config.duplicate(true)
    for key in _tab_instances:
        var instance = _tab_instances[key]
        if instance.has_method("get_config"):
            config[key] = instance.get_config()

    var old_game: Dictionary = {}
    if _saved_config.has("game") and _saved_config["game"] is Dictionary:
        old_game = _saved_config["game"]
    var new_game: Dictionary = {}
    if config.has("game") and config["game"] is Dictionary:
        new_game = config["game"]

    var old_root := str(old_game.get("data_root_dir", GameDataPathsScript.DEFAULT_DATA_ROOT))
    var new_root := str(new_game.get("data_root_dir", GameDataPathsScript.DEFAULT_DATA_ROOT))
    if GameDataPathsScript.normalize_root_dir(old_root) != GameDataPathsScript.normalize_root_dir(new_root):
        var migrate_result := GameDataPathsScript.migrate_data_root(old_root, new_root)
        if not migrate_result.get("ok", false):
            print_rich(
                "[color=red]设置: 数据目录迁移失败 — %s[/color]"
                % str(migrate_result.get("error", "未知错误"))
            )
            return
        var copied_dirs := int(migrate_result.get("copied_dirs", 0))
        if copied_dirs > 0:
            print_rich(
                "[color=yellow]设置: 已复制 %d 个数据目录到新位置[/color]" % copied_dirs
            )

    var json_text := JSON.stringify(config, "\t")

    if not DirAccess.dir_exists_absolute("user://ai_config"):
        var err := DirAccess.make_dir_recursive_absolute("user://ai_config")
        if err != OK:
            print_rich("[color=red]设置: 无法创建 user://ai_config 目录 (error %d)[/color]" % err)
            return

    var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
    if file == null:
        print_rich("[color=red]设置: 无法写入配置文件[/color]")
        return
    var ai_changed: bool = _saved_config.get("ai", {}) != config.get("ai", {})
    file.store_string(json_text)
    _saved_config = config
    print_rich("[color=green]设置: 配置已保存到 %s[/color]" % ProjectSettings.globalize_path(CONFIG_PATH))

    if config.has("game") and config["game"] is Dictionary:
        GameSettingsApplierScript.apply_game_settings(config["game"])

    if ai_changed:
        print_rich("[color=yellow]设置: AI 配置已变更，正在重启后端…[/color]")
        BackendLauncher.restart_backend()


func _style_settings_chrome() -> void:
    UiStylesScript.apply_secondary_button(get_node_or_null("%BackButton") as Button)
    UiStylesScript.apply_primary_button(get_node_or_null("%SaveButton") as Button)
    for tab_name in ["GameTab", "AITab", "AboutTab"]:
        UiStylesScript.apply_sidebar_toggle(get_node_or_null("%%%s" % tab_name) as Button)


func _on_back_pressed() -> void:
    get_tree().change_scene_to_file("res://sences/main_menu/main_menu.tscn")
