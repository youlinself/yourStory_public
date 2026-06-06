extends Control

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiBindScript := preload("res://src/ui/ui_bind.gd")

const MAIN_MENU_SCENE := "res://sences/main_menu/main_menu.tscn"
const GAME_SCENE := "res://sences/game/game_scene.tscn"
const META_BACKEND_PORT := "pending_backend_port"

var _backend_port: int = -1
var _current_theme: String = ""
var _world_initializer: GameWorldInitializer
var _confirming := false
var _init_elapsed_start_msec: int = -1


func _ready() -> void:
	UiRootScript.apply_to(self)
	_style_picker_controls()
	_world_initializer = GameWorldInitializer.new()
	add_child(_world_initializer)
	_world_initializer.phase_started.connect(_on_init_phase_started)
	_world_initializer.phase_completed.connect(_on_init_phase_completed)
	_world_initializer.initialization_completed.connect(_on_init_completed)
	_world_initializer.initialization_failed_ex.connect(_on_init_failed_ex)

	UiBindScript.connect_pressed(self, "ConfirmButton", _on_confirm_pressed)
	UiBindScript.connect_pressed(self, "RetryButton", _on_retry_pressed)
	UiBindScript.connect_pressed(self, "RerollButton", _on_reroll_pressed)
	UiBindScript.connect_pressed(self, "CancelButton", _on_cancel_pressed)

	if not _load_backend_port():
		return

	_connect_backend_signals()
	_sync_backend_port_from_launcher()

	_roll_theme()
	_set_picker_interactive(true)
	_set_retry_visible(false)
	_set_status("")
	_stop_init_timer()


func _process(_delta: float) -> void:
	if _init_elapsed_start_msec < 0:
		return
	var elapsed_sec := int((Time.get_ticks_msec() - _init_elapsed_start_msec) / 1000.0)
	var elapsed := _label("ElapsedLabel")
	if elapsed:
		elapsed.text = "%d s" % elapsed_sec


func _load_backend_port() -> bool:
	var tree := get_tree()
	if not tree.has_meta(META_BACKEND_PORT):
		_show_fatal_and_return_menu("后端端口未传递，请从主菜单重新开始。")
		return false

	_backend_port = int(tree.get_meta(META_BACKEND_PORT))
	tree.remove_meta(META_BACKEND_PORT)

	if _backend_port <= 0:
		_show_fatal_and_return_menu("后端端口无效，请从主菜单重新开始。")
		return false

	return true


func _connect_backend_signals() -> void:
	if not BackendLauncher.backend_ready.is_connected(_on_backend_ready):
		BackendLauncher.backend_ready.connect(_on_backend_ready)
	if not BackendLauncher.backend_restarting.is_connected(_on_backend_restarting):
		BackendLauncher.backend_restarting.connect(_on_backend_restarting)
	if not BackendLauncher.backend_failed.is_connected(_on_backend_failed):
		BackendLauncher.backend_failed.connect(_on_backend_failed)


func _sync_backend_port_from_launcher() -> void:
	var live: int = BackendLauncher.get_live_port()
	if live > 0 and live != _backend_port:
		print(
			"[NovelTypePicker] 后端端口已更新 %d -> %d（可能发生过自动重启）" % [_backend_port, live]
		)
		_backend_port = live


func _on_backend_ready(port: int) -> void:
	if port > 0:
		_backend_port = port


func _on_backend_restarting(attempt: int, max_attempts: int, _reason: String) -> void:
	if _confirming or _world_initializer.is_running():
		return
	_set_status("AI 后端断开，正在自动重启 (%d/%d)…" % [attempt, max_attempts])


func _on_backend_failed(reason: String) -> void:
	if _confirming:
		_on_init_failed_ex("AI 后端启动失败: %s" % reason, AIClient.HTTP_RESULT_NONE)
		return
	_set_status("AI 后端启动失败: %s" % reason, true)


func _roll_theme() -> void:
	_current_theme = NovelTypeSelector.draw_random(_current_theme)
	if _current_theme.is_empty():
		_show_fatal_and_return_menu("无法加载小说类型列表。")
		return
	var theme_label := _label("ThemeLabel")
	if theme_label:
		theme_label.text = _current_theme


func _on_reroll_pressed() -> void:
	if _confirming or _world_initializer.is_running():
		return
	_set_retry_visible(false)
	_roll_theme()


func _on_cancel_pressed() -> void:
	if _world_initializer.is_running():
		return
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_confirm_pressed() -> void:
	_begin_initialization(false)


func _on_retry_pressed() -> void:
	_begin_initialization(true)


func _begin_initialization(is_retry: bool) -> void:
	if _confirming or _world_initializer.is_running():
		return
	if _current_theme.is_empty():
		_set_status("当前主题无效，请重抽或返回主菜单。", true)
		return

	if not BackendLauncher.is_ready():
		_set_status("后端未运行，请返回主菜单等待或检查 AI 设置。", true)
		_set_retry_visible(false)
		return

	var port := _resolve_backend_port()
	if port <= 0:
		_set_status("后端端口无效，请返回主菜单重试。", true)
		_set_retry_visible(false)
		return

	_confirming = true
	_set_retry_visible(false)
	_set_picker_interactive(false)
	_start_init_timer()
	if is_retry:
		var resume_phase := GameWorldInitializer.detect_start_phase(_current_theme)
		if resume_phase == 3:
			var sub := GameWorldInitializer.detect_resume_world_substep()
			_set_status("正在从第 3 阶段子步 %d 续跑…" % sub)
		else:
			_set_status("正在从第 %d 阶段重新生成…" % resume_phase)
		_world_initializer.run_retry(port, _current_theme)
	else:
		_set_status("正在连接 AI，开始生成世界…")
		_world_initializer.run(port, _current_theme)


func _resolve_backend_port() -> int:
	_sync_backend_port_from_launcher()
	return BackendLauncher.resolve_client_port(
		_backend_port,
		BackendLauncher.get_port(),
		BackendLauncher.is_ready(),
	)


func _on_init_phase_started(phase: int, label: String) -> void:
	_set_status("(%d/3) %s" % [phase, label])


func _on_init_phase_completed(phase: int) -> void:
	_set_status("(%d/3) 完成" % phase)


func _on_init_completed() -> void:
	_stop_init_timer()
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_init_failed_ex(reason: String, http_result: int) -> void:
	_confirming = false
	_stop_init_timer()
	_set_picker_interactive(true)
	_set_retry_visible(GameWorldInitializer.is_retriable_failure(reason, http_result))
	_set_status("初始化失败: %s" % reason, true)


func _show_fatal_and_return_menu(message: String) -> void:
	_set_picker_interactive(false)
	_set_retry_visible(false)
	_set_status(message, true)
	await get_tree().create_timer(1.5).timeout
	if is_inside_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _set_picker_interactive(enabled: bool) -> void:
	for node_name in ["ConfirmButton", "RerollButton", "CancelButton", "RetryButton"]:
		var btn := _picker_button(node_name)
		if btn:
			btn.disabled = not enabled


func _set_retry_visible(show_retry: bool) -> void:
	var retry := _picker_button("RetryButton")
	if retry:
		retry.visible = show_retry


func _start_init_timer() -> void:
	_init_elapsed_start_msec = Time.get_ticks_msec()
	var elapsed := _label("ElapsedLabel")
	if elapsed:
		elapsed.text = "0 s"
		elapsed.visible = true


func _stop_init_timer() -> void:
	_init_elapsed_start_msec = -1
	var elapsed := _label("ElapsedLabel")
	if elapsed:
		elapsed.visible = false


func _style_picker_controls() -> void:
	var theme_label := _label("ThemeLabel")
	if theme_label:
		theme_label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_DISPLAY)
		theme_label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	UiStylesScript.apply_primary_button(_picker_button("ConfirmButton"))
	UiStylesScript.apply_secondary_button(_picker_button("RerollButton"))
	UiStylesScript.apply_secondary_button(_picker_button("CancelButton"))
	UiStylesScript.apply_secondary_button(_picker_button("RetryButton"))
	UiStylesScript.style_hint_label(_label("StatusLabel"), "muted")
	UiStylesScript.style_hint_label(_label("ElapsedLabel"), "muted")


func _set_status(text: String, is_error: bool = false) -> void:
	var status := _label("StatusLabel")
	if status == null:
		return
	status.text = text
	if is_error:
		UiStylesScript.style_hint_label(status, "error")
	else:
		UiStylesScript.style_hint_label(status, "muted")


func _picker_button(node_name: String) -> Button:
	return UiBindScript.find_named(self, node_name) as Button


func _label(node_name: String) -> Label:
	return UiBindScript.find_named(self, node_name) as Label
