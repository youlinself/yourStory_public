extends Control

const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const EventTimelineLabelsScript := preload("res://src/game/logic/event_timeline_labels.gd")
const RichTextFormatScript := preload("res://src/ui/rich_text_format.gd")

signal recall_requested(event: Dictionary)
signal recall_cancel_requested

@onready var _title_label: Label = %TitleLabel
@onready var _recall_button: Button = %RecallButton
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _content_scroll: ScrollContainer = %ContentScroll

var _current_event: Dictionary = {}
var _is_pinned := false
var _recall_enabled := true


func set_recall_enabled(enabled: bool) -> void:
	_recall_enabled = enabled
	if _recall_button and not _recall_enabled:
		_recall_button.visible = false


func _ready() -> void:
	if _title_label:
		_title_label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_PANEL_TITLE)
	UiStylesScript.configure_rich_body(_body_label)
	if _recall_button:
		UiStylesScript.apply_secondary_button(_recall_button)
		_recall_button.pressed.connect(_on_recall_pressed)


func show_event(event: Dictionary, region_name: String = "", is_pinned: bool = false) -> void:
	_current_event = event.duplicate(true) if event is Dictionary else {}
	_is_pinned = is_pinned
	if event.is_empty():
		_title_label.text = "事件回顾"
		_body_label.text = "请选择左侧事件查看详情。"
		if _recall_button:
			_recall_button.visible = false
		_reset_scroll()
		return

	_title_label.text = str(event.get("title", "事件"))
	if _recall_button:
		_recall_button.visible = _recall_enabled
		if _recall_enabled:
			_recall_button.text = "取消标记" if _is_pinned else "在剧情中回顾此事件"
	var ts := int(event.get("timestamp", 0))
	var time_line := EventTimelineLabelsScript.label_from_timestamp(ts)
	var lines: PackedStringArray = ["[b]时间线[/b]：%s" % time_line]
	if not region_name.is_empty():
		lines.append("[b]地点[/b]：%s" % region_name)
	lines.append("")
	lines.append(RichTextFormatScript.escape_bbcode(str(event.get("summary", ""))))
	var story_body := str(event.get("story_body", "")).strip_edges()
	if story_body.is_empty():
		story_body = str(event.get("compact_body", "")).strip_edges()
	if not story_body.is_empty():
		lines.append("")
		lines.append("[b]剧情原文[/b]")
		lines.append(RichTextFormatScript.escape_bbcode(story_body))
	_body_label.text = "\n".join(lines)
	_reset_scroll()


func _on_recall_pressed() -> void:
	if _current_event.is_empty():
		return
	if _is_pinned:
		recall_cancel_requested.emit()
	else:
		recall_requested.emit(_current_event)


func _reset_scroll() -> void:
	if _content_scroll == null:
		return
	_content_scroll.scroll_vertical = 0
	call_deferred("_deferred_reset_scroll")


func _deferred_reset_scroll() -> void:
	if _content_scroll:
		_content_scroll.scroll_vertical = 0
