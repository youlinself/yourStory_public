extends Control

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiBindScript := preload("res://src/ui/ui_bind.gd")

const NOVEL_TYPE_PICKER_SCENE := "res://sences/main_menu/novel_type_picker.tscn"
const GAME_HISTORY_SCENE := "res://sences/main_menu/game_history.tscn"
const META_BACKEND_PORT := "pending_backend_port"

var _backend_port: int = -1
var _backend_ready := false


func _ready() -> void:
	_apply_center_container_layout()
	UiRootScript.apply_to(self)
	_wrap_menu_card()
	_style_menu_controls()

	UiBindScript.connect_pressed(self, "NewGameButton", _on_new_game_pressed)
	UiBindScript.connect_pressed(self, "ContinueButton", _on_continue_pressed)
	UiBindScript.connect_pressed(self, "GameHistoryButton", _on_game_history_pressed)
	UiBindScript.connect_pressed(self, "SettingsButton", _on_settings_pressed)

	_connect_backend_signals()
	_sync_backend_state()
	_refresh_continue_button()
	_set_status("")


func _apply_center_container_layout() -> void:
	var center := $CenterContainer as Control
	var h := DesignTokensScript.MAIN_MENU_CONTENT_HALF_SIZE
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	center.grow_vertical = Control.GROW_DIRECTION_BEGIN
	center.offset_left = -h.x
	center.offset_top = -h.y
	center.offset_right = h.x
	center.offset_bottom = h.y


func _wrap_menu_card() -> void:
	var center := $CenterContainer
	if center.get_child_count() == 0:
		return
	var child := center.get_child(0)
	if child is PanelContainer:
		return
	var card := PanelContainer.new()
	UiStylesScript.apply_panel_surface(card)
	center.remove_child(child)
	card.add_child(child)
	center.add_child(card)


func _style_menu_controls() -> void:
	var center := $CenterContainer
	var title := center.get_node_or_null("VBoxContainer/TitleLabel") as Label
	if title == null:
		var card := center.get_child(0) as PanelContainer
		if card:
			title = card.get_node_or_null("VBoxContainer/TitleLabel") as Label
	if title:
		title.add_theme_font_size_override("font_size", DesignTokensScript.FONT_DISPLAY)
		title.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_PRIMARY)

	UiStylesScript.apply_primary_button(get_node_or_null("%NewGameButton") as Button)
	UiStylesScript.apply_secondary_button(get_node_or_null("%ContinueButton") as Button)
	UiStylesScript.apply_secondary_button(get_node_or_null("%GameHistoryButton") as Button)
	UiStylesScript.apply_secondary_button(get_node_or_null("%SettingsButton") as Button)
	UiStylesScript.style_hint_label(get_node_or_null("%StatusLabel") as Label, "muted")


func _on_new_game_pressed() -> void:
	if not _backend_ready or _backend_port <= 0:
		_set_status("后端未就绪，请稍候或检查 AI 设置。", true)
		return

	get_tree().set_meta(META_BACKEND_PORT, _backend_port)
	get_tree().change_scene_to_file(NOVEL_TYPE_PICKER_SCENE)


func _on_continue_pressed() -> void:
	if not GameRunningFileManager.has_playable_save():
		_set_status("未找到可继续的存档。", true)
		return
	_enter_game_scene()


func _on_game_history_pressed() -> void:
	get_tree().change_scene_to_file(GAME_HISTORY_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://sences/settings/settings.tscn")


func _connect_backend_signals() -> void:
	if not BackendLauncher.backend_ready.is_connected(_on_backend_ready):
		BackendLauncher.backend_ready.connect(_on_backend_ready)
	if not BackendLauncher.backend_restarting.is_connected(_on_backend_restarting):
		BackendLauncher.backend_restarting.connect(_on_backend_restarting)
	if not BackendLauncher.backend_failed.is_connected(_on_backend_failed):
		BackendLauncher.backend_failed.connect(_on_backend_failed)


func _sync_backend_state() -> void:
	if BackendLauncher.is_ready():
		_on_backend_ready(BackendLauncher.get_port())
	elif not BackendLauncher.is_running():
		BackendLauncher.start_backend()


func _on_backend_ready(port: int) -> void:
	_backend_port = port
	_backend_ready = true
	_set_menu_interactive(true)
	print("[MainMenu] 后端已就绪，端口: ", port)
	_set_status("")


func _on_backend_restarting(attempt: int, max_attempts: int, _reason: String) -> void:
	_backend_ready = false
	_backend_port = -1
	_set_menu_interactive(false)
	_set_status("后端已断开，正在自动重启 (%d/%d)…" % [attempt, max_attempts])


func _on_backend_failed(reason: String) -> void:
	_backend_ready = false
	_backend_port = -1
	_set_menu_interactive(true)
	printerr("[MainMenu] 后端启动失败: ", reason)
	_set_status("后端启动失败: %s" % reason, true)


func _enter_game_scene() -> void:
	get_tree().change_scene_to_file("res://sences/game/game_scene.tscn")


func _refresh_continue_button() -> void:
	var btn := UiBindScript.find_named(self, "ContinueButton") as Button
	if btn:
		btn.disabled = not GameRunningFileManager.has_playable_save()


func _set_menu_interactive(enabled: bool) -> void:
	var continue_btn := UiBindScript.find_named(self, "ContinueButton") as Button
	for name in ["NewGameButton", "ContinueButton", "GameHistoryButton", "SettingsButton"]:
		var btn := UiBindScript.find_named(self, name) as Button
		if not btn:
			continue
		if btn == continue_btn:
			btn.disabled = not enabled or not GameRunningFileManager.has_playable_save()
		else:
			btn.disabled = not enabled


func _set_status(text: String, is_error: bool = false) -> void:
	var status := UiBindScript.find_named(self, "StatusLabel") as Label
	if status == null:
		return
	status.text = text
	if is_error:
		UiStylesScript.style_hint_label(status, "error")
	else:
		UiStylesScript.style_hint_label(status, "muted")
