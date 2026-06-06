class_name StoryLogAnimator
extends Node

## 控制 StoryLog 的逐字显示与滚动条跟随。

@export var chars_per_tick: int = 1
@export var tick_interval: float = 0.048
@export var bottom_padding: int = 16

var _story_log: RichTextLabel
var _scroll: ScrollContainer
var _target_visible: int = 0
var _tick_accum: float = 0.0
var _animating: bool = false
var _pending_snap_end: bool = true
var _scroll_after_layout_running: bool = false


func bind(story_log: RichTextLabel, scroll: ScrollContainer = null) -> void:
	_story_log = story_log
	_scroll = scroll
	if _story_log != null and not _story_log.resized.is_connected(_on_story_log_resized):
		_story_log.resized.connect(_on_story_log_resized)


func is_animating() -> bool:
	return _animating


func stop_animation() -> void:
	if _story_log == null:
		_animating = false
		return
	_animating = false
	_tick_accum = 0.0
	_story_log.visible_characters = -1
	_scroll_follow_visible_end(true)


func clear_instant() -> void:
	_animating = false
	_tick_accum = 0.0
	if _story_log:
		_story_log.clear()
		_story_log.visible_characters = -1


func set_full_text_instant(bbcode: String) -> void:
	_animating = false
	_tick_accum = 0.0
	if _story_log == null:
		return
	_story_log.clear()
	if not bbcode.is_empty():
		_story_log.append_text(bbcode)
	_story_log.visible_characters = -1
	_scroll_follow_visible_end_deferred(true)


func append_text(bbcode: String, animated: bool) -> void:
	if _story_log == null or bbcode.is_empty():
		return
	var start := _current_visible_count()
	_story_log.append_text(bbcode)
	var target := _story_log.get_total_character_count()
	if not animated or target <= start:
		_story_log.visible_characters = -1
		_scroll_follow_visible_end_deferred(true)
		return
	_story_log.visible_characters = start
	_target_visible = target
	_animating = true
	_tick_accum = 0.0
	_scroll_follow_visible_end(false)


func _current_visible_count() -> int:
	if _story_log == null:
		return 0
	var visible := _story_log.visible_characters
	if visible < 0:
		return _story_log.get_total_character_count()
	return visible


func _process(delta: float) -> void:
	if not _animating or _story_log == null:
		return
	_tick_accum += delta
	while _tick_accum >= tick_interval:
		_tick_accum -= tick_interval
		var cur := _current_visible_count()
		if cur >= _target_visible:
			_finish_typing()
			return
		var next := mini(cur + chars_per_tick, _target_visible)
		_story_log.visible_characters = next
		_scroll_follow_visible_end(false)
		if next >= _target_visible:
			_finish_typing()
			return


func _finish_typing() -> void:
	_animating = false
	_tick_accum = 0.0
	if _story_log:
		_story_log.visible_characters = -1
	_scroll_follow_visible_end_deferred(true)


func _visible_text_bottom_y() -> int:
	if _story_log == null:
		return 0
	var visible := _story_log.visible_characters
	if visible < 0:
		return _story_log.get_content_height()
	if visible <= 0:
		return 0
	var total := _story_log.get_total_character_count()
	if total <= 0:
		return 0
	var char_idx := clampi(visible - 1, 0, total - 1)
	var line := _story_log.get_character_line(char_idx)
	return int(_story_log.get_line_offset(line) + _story_log.get_line_height(line))


func _scroll_follow_visible_end(snap_end: bool) -> void:
	if _story_log == null or _scroll == null:
		return

	var bar := _scroll.get_v_scroll_bar()
	if bar == null:
		return

	var viewport_h := int(_scroll.size.y)
	if viewport_h <= 0:
		_queue_scroll_after_layout(snap_end)
		return

	var max_scroll := int(bar.max_value)

	if snap_end or _story_log.visible_characters < 0:
		var content_bottom := _story_log.get_content_height() + bottom_padding
		var desired_end := content_bottom - viewport_h
		_scroll.scroll_vertical = clampi(maxi(desired_end, 0), 0, max_scroll)
		return

	var text_bottom := _visible_text_bottom_y()
	var desired := text_bottom + bottom_padding - viewport_h
	if desired <= 0:
		return

	_scroll.scroll_vertical = clampi(desired, 0, max_scroll)


func _scroll_follow_visible_end_deferred(snap_end: bool) -> void:
	_pending_snap_end = snap_end
	_scroll_follow_visible_end(snap_end)
	call_deferred("_deferred_scroll_follow", snap_end)
	_queue_scroll_after_layout(snap_end)


func _deferred_scroll_follow(snap_end: bool) -> void:
	_pending_snap_end = snap_end
	_scroll_follow_visible_end(snap_end)


func _queue_scroll_after_layout(snap_end: bool) -> void:
	_pending_snap_end = snap_end
	if _scroll_after_layout_running or not is_inside_tree():
		return
	_scroll_after_layout_running = true
	_scroll_after_layout_async()


func _scroll_after_layout_async() -> void:
	# fit_content 的 RichTextLabel 需等布局刷新后，滚动条 max_value 才准确。
	await get_tree().process_frame
	if is_instance_valid(self):
		_scroll_follow_visible_end(_pending_snap_end)
	await get_tree().process_frame
	if is_instance_valid(self):
		_scroll_follow_visible_end(_pending_snap_end)
		_scroll_after_layout_running = false


func _on_story_log_resized() -> void:
	if _animating and not _pending_snap_end:
		return
	_scroll_follow_visible_end(_pending_snap_end)
