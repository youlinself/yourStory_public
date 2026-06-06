class_name StoryTextEdit
extends TextEdit

## 故事行动输入：自动换行、限高、Enter 提交；IME 组合期间避免应用层干扰。

signal text_submitted(new_text: String)
signal ime_composition_ended

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

const MAX_VISIBLE_LINES := 3
const LINE_HEIGHT_FACTOR := 1.35
const CONTENT_PADDING_Y := 16.0

## 返回 false 时 Enter 不提交（由外部 gui_input 处理，例如命令菜单确认）。
var submit_gate: Callable = Callable()
## 返回 true 表示事件已由命令菜单消费（应 accept_event）。
var command_menu_input_handler: Callable = Callable()

var _ime_was_active := false


func _ready() -> void:
	wrap_mode = LineWrappingMode.LINE_WRAPPING_BOUNDARY
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll_fit_content_width = true
	scroll_fit_content_height = false
	custom_minimum_size.y = int(_resolve_line_height() * MAX_VISIBLE_LINES + CONTENT_PADDING_Y)
	text_changed.connect(_on_internal_text_changed)
	set_process(true)


func is_ime_composing() -> bool:
	return has_ime_text()


func set_caret_at_end() -> void:
	var last_line := maxi(get_line_count() - 1, 0)
	set_caret_line(last_line)
	set_caret_column(get_line(last_line).length())


func _gui_input(event: InputEvent) -> void:
	if command_menu_input_handler.is_valid() and command_menu_input_handler.call(event):
		accept_event()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode != KEY_ENTER and key.keycode != KEY_KP_ENTER:
		return
	if key.shift_pressed:
		return
	if submit_gate.is_valid() and not submit_gate.call():
		return
	accept_event()
	text_submitted.emit(text)


func _process(_delta: float) -> void:
	_poll_ime_state()


func _on_internal_text_changed() -> void:
	_poll_ime_state()


func _poll_ime_state() -> void:
	var active := has_ime_text()
	if _ime_was_active and not active:
		ime_composition_ended.emit()
	_ime_was_active = active


func _resolve_line_height() -> float:
	var font_size := get_theme_font_size(&"font_size")
	if font_size <= 0:
		font_size = DesignTokensScript.FONT_BODY
	return float(font_size) * LINE_HEIGHT_FACTOR
