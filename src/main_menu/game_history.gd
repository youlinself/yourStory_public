extends Control

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiBindScript := preload("res://src/ui/ui_bind.gd")

const MAIN_MENU_SCENE := "res://sences/main_menu/main_menu.tscn"
const EventReviewBrowserScene := preload("res://sences/game/ui/event_review_browser.tscn")
const HistorySessionReadModelScript := preload("res://src/game/logic/data/history_session_read_model.gd")
const HistoryNovelExporterScript := preload("res://src/game/logic/data/history_novel_exporter.gd")

const EXPORT_DIALOG_MIN_SIZE := Vector2i(900, 520)
const EXPORT_DIALOG_VIEWPORT_RATIO := 0.72
const EXPORT_DIALOG_VIEWPORT_MARGIN := 80

var _sessions: Array[Dictionary] = []
var _read_model: RefCounted = HistorySessionReadModelScript.new()
var _review_browser: Control
var _session_list: ItemList
var _empty_hint: Label
var _export_button: Button
var _export_status: Label
var _export_dialog: FileDialog
var _selected_session_index := -1
var _session_loaded := false


func _ready() -> void:
	UiRootScript.apply_to(self)
	UiStylesScript.apply_secondary_button(get_node_or_null("%BackButton") as Button)
	UiStylesScript.apply_secondary_button(get_node_or_null("%ExportNovelButton") as Button)
	UiStylesScript.style_hint_label(get_node_or_null("%EmptyHint") as Label, "muted")
	_export_status = get_node_or_null("%ExportStatusLabel") as Label
	if _export_status:
		UiStylesScript.style_hint_label(_export_status, "muted")
	UiBindScript.connect_pressed(self, "BackButton", _on_back_pressed)
	_export_button = get_node_or_null("%ExportNovelButton") as Button
	if _export_button:
		_export_button.pressed.connect(_on_export_novel_pressed)
	_session_list = UiBindScript.find_named(self, "SessionList") as ItemList
	_empty_hint = UiBindScript.find_named(self, "EmptyHint") as Label
	if _session_list:
		UiStylesScript.apply_item_list(_session_list)
		_session_list.item_selected.connect(_on_session_selected)

	_export_dialog = get_node_or_null("%ExportFolderDialog") as FileDialog
	if _export_dialog:
		_configure_export_dialog()
		_export_dialog.dir_selected.connect(_on_export_dir_selected)

	_review_browser = EventReviewBrowserScene.instantiate()
	var review_host := UiBindScript.find_named(self, "ReviewHost") as Control
	if review_host:
		review_host.add_child(_review_browser)
	_review_browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_reload_sessions()


func _reload_sessions() -> void:
	_sessions = GameHistoryService.list_sessions()
	_selected_session_index = -1
	_session_loaded = false
	if _session_list:
		_session_list.clear()
	if _empty_hint:
		_empty_hint.visible = _sessions.is_empty()
	if _session_list:
		_session_list.visible = not _sessions.is_empty()
	_update_export_button_state()
	_clear_export_status()

	if _sessions.is_empty():
		_call_bind_events([])
		return

	if _session_list:
		for summary in _sessions:
			_session_list.add_item(_format_session_label(summary))
		_session_list.select(0)
		_on_session_selected(0)


func _format_session_label(summary: Dictionary) -> String:
	var novel_type := str(summary.get("novel_type", "")).strip_edges()
	if novel_type.is_empty():
		novel_type = "未知类型"
	var protagonist := str(summary.get("protagonist_name", "主角")).strip_edges()
	var archived_at := int(summary.get("archived_at", 0))
	var time_str := _format_unix_time(archived_at)
	var event_count := int(summary.get("event_count", 0))
	return "%s · %s\n%s · %d 个事件" % [novel_type, protagonist, time_str, event_count]


func _format_unix_time(unix: int) -> String:
	if unix <= 0:
		return "未知时间"
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d %02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute,
	]


func _on_session_selected(index: int) -> void:
	_selected_session_index = index
	_session_loaded = false
	if index < 0 or index >= _sessions.size():
		_call_bind_events([])
		_update_export_button_state()
		return
	var summary: Dictionary = _sessions[index]
	var session_id := str(summary.get("id", "")).strip_edges()
	if session_id.is_empty():
		_call_bind_events([])
		_update_export_button_state()
		return

	if not _read_model.load(session_id):
		_call_bind_events([])
		_update_export_button_state()
		return

	_session_loaded = true
	var events: Array = []
	for event in _read_model.get_events_chronological():
		events.append(event)

	var resolver := Callable(_read_model, "get_region_name")
	_call_bind_events(events, resolver)
	_update_export_button_state()


func _call_bind_events(events: Array, region_resolver: Callable = Callable()) -> void:
	if _review_browser and _review_browser.has_method("bind_events"):
		_review_browser.bind_events(events, region_resolver)


func _update_export_button_state() -> void:
	if _export_button == null:
		return
	var can_export := (
		not _sessions.is_empty()
		and _selected_session_index >= 0
		and _selected_session_index < _sessions.size()
		and _session_loaded
	)
	_export_button.disabled = not can_export


func _on_export_novel_pressed() -> void:
	if _sessions.is_empty() or _selected_session_index < 0:
		_set_export_status("请先选择对局", true)
		return
	if not _session_loaded:
		_set_export_status("无法加载该对局数据", true)
		return
	if _export_dialog:
		_popup_export_dialog()
	else:
		_set_export_status("导出对话框未配置", true)


func _configure_export_dialog() -> void:
	_export_dialog.title = "选择导出目录"
	_export_dialog.ok_button_text = "选择此文件夹"
	_export_dialog.min_size = EXPORT_DIALOG_MIN_SIZE
	_export_dialog.unresizable = true
	_export_dialog.use_native_dialog = false


func _popup_export_dialog() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var max_fit := Vector2i(
		maxi(640, int(viewport_size.x) - EXPORT_DIALOG_VIEWPORT_MARGIN),
		maxi(480, int(viewport_size.y) - EXPORT_DIALOG_VIEWPORT_MARGIN),
	)
	_export_dialog.max_size = max_fit
	_export_dialog.min_size = Vector2i(
		mini(EXPORT_DIALOG_MIN_SIZE.x, max_fit.x),
		mini(EXPORT_DIALOG_MIN_SIZE.y, max_fit.y),
	)
	_export_dialog.reset_size()
	_export_dialog.popup_centered_ratio(EXPORT_DIALOG_VIEWPORT_RATIO)


func _on_export_dir_selected(dir: String) -> void:
	if _selected_session_index < 0 or _selected_session_index >= _sessions.size():
		_set_export_status("请先选择对局", true)
		return
	var summary: Dictionary = _sessions[_selected_session_index]
	var result: Dictionary = HistoryNovelExporterScript.export_session(_read_model, summary, dir)
	if not result.get("ok", false):
		_set_export_status(str(result.get("error", "导出失败")), true)
		return
	var paths: Array = result.get("written_paths", [])
	var output_dir := str(result.get("output_dir", ""))
	_set_export_status("已导出 %d 个文件至：%s" % [paths.size(), output_dir], false)


func _set_export_status(message: String, is_error: bool) -> void:
	if _export_status == null:
		return
	_export_status.text = message
	if is_error:
		_export_status.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_ERROR)
	else:
		_export_status.remove_theme_color_override("font_color")


func _clear_export_status() -> void:
	if _export_status:
		_export_status.text = ""


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
