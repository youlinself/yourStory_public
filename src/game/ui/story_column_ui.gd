class_name StoryColumnUI
extends RefCounted

const PlayerCommandRegistryScript := preload("res://src/game/logic/input/player_command_registry.gd")
const PlayerCommandResolverScript := preload("res://src/game/logic/input/player_command_resolver.gd")
const StoryTextEditScript := preload("res://src/game/ui/story_text_edit.gd")
const StoryLogAnimatorScript := preload("res://src/game/ui/story_log_animator.gd")
const RichTextFormatScript := preload("res://src/ui/rich_text_format.gd")
const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")

signal story_submit_requested(text: String)
signal suggestion_selected(text: String)

enum CommandMenuMode { NONE, COMMAND, ARG }

const COMMAND_ITEM_HEIGHT := 32
const COMMAND_MENU_MAX_HEIGHT := 196

var _story_log: RichTextLabel
var _story_scroll: ScrollContainer
var _log_animator: StoryLogAnimatorScript
var _line_edit: StoryTextEditScript
var _send_button: Button
var _status_label: Label
var _suggestion_chips: FlowContainer
var _command_menu: PanelContainer
var _command_list: ItemList
var _command_registry: PlayerCommandRegistryScript
var _command_resolver: PlayerCommandResolverScript
var _read_model: GameReadModel

var _chip_buttons: Array[BaseButton] = []
var _menu_entries: Array = []
var _menu_mode: CommandMenuMode = CommandMenuMode.NONE
var _menu_highlight_index := -1
var _busy := false
var _busy_started_msec := 0
var _busy_timer_token := 0
var _busy_status_prefix := "回合结算中…"
var _showing_error := false
var _defer_command_menu_refresh := false
var _command_menu_refresh_queued := false
var _rendered_log_entry_count := 0
var _travel_hint := ""

static var _dialogue_line_re: RegEx


func setup(
	story_log: RichTextLabel,
	line_edit: StoryTextEditScript,
	send_button: Button,
	status_label: Label,
	suggestion_chips: FlowContainer = null,
	command_menu: PanelContainer = null,
	command_list: ItemList = null,
	command_registry: PlayerCommandRegistryScript = null,
) -> void:
	_story_log = story_log
	if story_log != null:
		_story_scroll = story_log.get_parent() as ScrollContainer
		_log_animator = StoryLogAnimatorScript.new()
		story_log.add_child(_log_animator)
		_log_animator.bind(story_log, _story_scroll)
		if not story_log.gui_input.is_connected(_on_story_log_gui_input):
			story_log.gui_input.connect(_on_story_log_gui_input)
	_line_edit = line_edit
	_send_button = send_button
	_status_label = status_label
	_suggestion_chips = suggestion_chips
	_command_menu = command_menu
	_command_list = command_list
	_command_registry = command_registry

	if _send_button:
		_send_button.pressed.connect(_on_send_pressed)
	if _line_edit:
		_line_edit.submit_gate = Callable(self, "_can_submit_on_enter")
		_line_edit.command_menu_input_handler = Callable(self, "_handle_command_menu_input")
		_line_edit.text_submitted.connect(_on_text_submitted)
		_line_edit.text_changed.connect(_on_line_edit_changed)
		_line_edit.caret_changed.connect(_on_line_edit_changed)
		_line_edit.ime_composition_ended.connect(_on_ime_composition_ended)

	if _command_menu:
		_command_menu.visible = false
	if _command_list:
		_command_list.focus_mode = Control.FOCUS_NONE
		_command_list.item_selected.connect(_on_command_item_selected)
		_command_list.item_activated.connect(_on_command_item_activated)


func bind_command_completion(resolver: PlayerCommandResolverScript, read_model: GameReadModel) -> void:
	_command_resolver = resolver
	_read_model = read_model


func set_suggestions(items: Array) -> void:
	if _suggestion_chips == null:
		return
	for child in _suggestion_chips.get_children():
		child.queue_free()
	_chip_buttons.clear()

	for item in items:
		var text := str(item).strip_edges()
		if text.is_empty():
			continue
		var btn := UiStylesScript.make_suggestion_chip(
			text,
			_on_chip_pressed.bind(text),
			_busy,
		)
		_suggestion_chips.add_child(btn)
		_chip_buttons.append(btn)


func fill_line_edit(text: String) -> void:
	if _line_edit == null:
		return
	_travel_hint = ""
	_line_edit.text = text
	_line_edit.set_caret_at_end()
	_line_edit.grab_focus()
	_refresh_command_menu()


func set_travel_hint(text: String) -> void:
	if _line_edit == null:
		return
	clear_travel_hint()
	var hint := text.strip_edges()
	if hint.is_empty():
		return
	_travel_hint = hint
	_line_edit.text += hint
	_line_edit.set_caret_at_end()
	_line_edit.grab_focus()


func clear_travel_hint() -> void:
	if _line_edit == null or _travel_hint.is_empty():
		_travel_hint = ""
		return
	var full := _line_edit.text
	if full.ends_with(_travel_hint):
		_line_edit.text = full.left(full.length() - _travel_hint.length())
	_travel_hint = ""


func render_story_log(
	story_log: Array,
	animate_last_assistant: bool = false,
	force_full: bool = false,
) -> void:
	if _story_log == null or _log_animator == null:
		return

	if story_log.is_empty():
		_log_animator.stop_animation()
		_log_animator.clear_instant()
		_rendered_log_entry_count = 0
		return

	if (
		not force_full
		and _rendered_log_entry_count > 0
		and story_log.size() > _rendered_log_entry_count
	):
		_append_story_log_range(story_log, _rendered_log_entry_count, false)
		_rendered_log_entry_count = story_log.size()
		return

	if (
		not force_full
		and story_log.size() == _rendered_log_entry_count
		and _rendered_log_entry_count > 0
	):
		return

	_log_animator.stop_animation()
	var blocks: PackedStringArray = []
	for entry in story_log:
		if not entry is Dictionary:
			continue
		var block := _format_entry_block(str(entry.get("role", "")), str(entry.get("content", "")))
		if not block.is_empty():
			blocks.append(block)

	if blocks.is_empty():
		_log_animator.clear_instant()
		_rendered_log_entry_count = 0
		return

	var last_idx := blocks.size() - 1
	var last_role := ""
	if story_log.size() > 0:
		var last_entry: Variant = story_log[story_log.size() - 1]
		if last_entry is Dictionary:
			last_role = str(last_entry.get("role", ""))

	var use_typewriter := animate_last_assistant and last_role == "assistant"

	if not use_typewriter:
		_log_animator.set_full_text_instant("".join(blocks))
		_rendered_log_entry_count = story_log.size()
		return

	_log_animator.clear_instant()
	for i in blocks.size():
		_log_animator.append_text(blocks[i], i == last_idx)
	_rendered_log_entry_count = story_log.size()


func _append_story_log_range(story_log: Array, from_index: int, animated: bool) -> void:
	for i in range(from_index, story_log.size()):
		var entry: Variant = story_log[i]
		if not entry is Dictionary:
			continue
		var role := str(entry.get("role", ""))
		var content := str(entry.get("content", ""))
		append_entry(role, content, animated and role == "assistant" and i == story_log.size() - 1)


func _on_story_log_gui_input(event: InputEvent) -> void:
	if _log_animator == null or not _log_animator.is_animating():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_log_animator.stop_animation()


func append_entry(role: String, content: String, animated: bool = true) -> void:
	if _log_animator == null:
		return
	if _log_animator.is_animating():
		_log_animator.stop_animation()
	var block := _format_entry_block(role, content)
	if block.is_empty():
		return
	var typewriter := animated and role == "assistant"
	_log_animator.append_text(block, typewriter)
	_rendered_log_entry_count += 1


func set_busy(busy: bool) -> void:
	_busy = busy
	_busy_timer_token += 1
	if _line_edit:
		_line_edit.editable = not busy
	if _send_button:
		_send_button.disabled = busy
	for btn in _chip_buttons:
		btn.disabled = busy
	if _status_label:
		if busy:
			_showing_error = false
			_busy_started_msec = Time.get_ticks_msec()
			_busy_status_prefix = "回合结算中…"
			_update_busy_status()
			_run_busy_timer(_busy_timer_token)
		elif not _showing_error:
			_status_label.text = ""
			_status_label.remove_theme_color_override("font_color")
	if busy:
		_hide_command_popup()


func show_error(message: String) -> void:
	_busy_timer_token += 1
	_showing_error = true
	if _status_label:
		var text := message.strip_edges()
		if not text.begins_with("调用失败"):
			text = "调用失败：%s" % text
		_status_label.text = text
		_status_label.add_theme_color_override("font_color", Color(0.9, 0.35, 0.35))


func show_notice(message: String) -> void:
	_showing_error = false
	if _status_label:
		if _busy:
			_busy_status_prefix = message.strip_edges() if not message.strip_edges().is_empty() else "回合结算中…"
			_update_busy_status()
		else:
			_status_label.text = message
		_status_label.remove_theme_color_override("font_color")


func _run_busy_timer(token: int) -> void:
	while _busy and token == _busy_timer_token and _status_label != null:
		await _status_label.get_tree().create_timer(1.0).timeout
		if _busy and token == _busy_timer_token:
			_update_busy_status()


func _update_busy_status() -> void:
	if _status_label == null:
		return
	var elapsed_seconds := int((Time.get_ticks_msec() - _busy_started_msec) / 1000.0)
	_status_label.text = "%s %s" % [_busy_status_prefix, _format_elapsed_time(elapsed_seconds)]


func _format_elapsed_time(total_seconds: int) -> String:
	var minutes := int(total_seconds / 60.0)
	var seconds := total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func _on_send_pressed() -> void:
	_submit_current()


func _on_text_submitted(_text: String) -> void:
	if _is_command_menu_active():
		_confirm_menu_highlight()
		return
	_submit_current()


func _submit_current() -> void:
	if _line_edit == null:
		return
	var text := _line_edit.text.strip_edges()
	if text.is_empty():
		return
	_travel_hint = ""
	_line_edit.clear()
	_hide_command_popup()
	story_submit_requested.emit(text)


func _on_chip_pressed(text: String) -> void:
	fill_line_edit(text)
	suggestion_selected.emit(text)


func _on_line_edit_changed() -> void:
	if not _travel_hint.is_empty() and _line_edit != null:
		if not _line_edit.text.ends_with(_travel_hint):
			_travel_hint = ""
	_queue_command_menu_refresh()


func _on_ime_composition_ended() -> void:
	if _defer_command_menu_refresh or _is_command_text(_command_input_text()):
		_defer_command_menu_refresh = false
		_queue_command_menu_refresh()


func _queue_command_menu_refresh() -> void:
	if _command_menu_refresh_queued:
		return
	_command_menu_refresh_queued = true
	Callable(self, "_flush_command_menu_refresh").call_deferred()


func _flush_command_menu_refresh() -> void:
	_command_menu_refresh_queued = false
	if _line_edit == null:
		return
	var cmd_text := _command_input_text()
	if _is_command_text(cmd_text):
		_defer_command_menu_refresh = false
		_refresh_command_menu(cmd_text)
		return
	if _line_edit.is_ime_composing():
		_defer_command_menu_refresh = true
		return
	_defer_command_menu_refresh = false
	_refresh_command_menu(cmd_text)


func _command_input_text() -> String:
	if _line_edit == null:
		return ""
	var raw := _line_edit.text
	var candidate := raw.strip_edges()
	if candidate.is_empty() and raw.contains("\n"):
		candidate = raw.get_slice("\n", 0).strip_edges()
	return _normalize_command_slashes(candidate)


func _normalize_command_slashes(text: String) -> String:
	if text.begins_with("／"):
		return "/" + text.substr(1)
	return text


func _is_command_text(text: String) -> bool:
	return text.begins_with("/")


func _can_submit_on_enter() -> bool:
	return not _is_command_menu_active()


## 命令名已输全（或唯一匹配）时，直接弹出首参补全（如 NPC 列表），避免只剩一行预览无法点选。
func _try_show_first_arg_completion(prefix_after_slash: String) -> bool:
	if _command_resolver == null or _read_model == null:
		return false
	_read_model.load_from_runtime()
	var cmd: Dictionary = _command_registry.resolve_single_matched_command(prefix_after_slash)
	if cmd.is_empty() or not _command_registry.command_first_arg_has_completion(cmd):
		return false
	var slash := str(cmd.get("slash", "")).strip_edges()
	if slash.is_empty():
		return false
	var synthetic := "/%s " % slash
	var arg_result: Dictionary = _command_resolver.build_arg_completion_entries(
		synthetic,
		_read_model,
	)
	if not arg_result.get("active", false):
		return false
	_menu_mode = CommandMenuMode.ARG
	_menu_entries = arg_result.get("entries", [])
	_update_command_popup()
	if _is_hint_only_menu():
		show_notice(str(_menu_entries[0].get("label", "")))
	elif not _busy:
		show_notice("")
	return true


func _refresh_command_menu(cmd_text: String = "") -> void:
	if _line_edit == null or _command_registry == null:
		return
	var text := cmd_text if not cmd_text.is_empty() else _command_input_text()
	if not _is_command_text(text):
		_hide_command_popup()
		return

	var space_idx := text.find(" ")
	if space_idx < 0:
		var prefix := text.substr(1)
		if _try_show_first_arg_completion(prefix):
			return
		_menu_mode = CommandMenuMode.COMMAND
		if _read_model != null:
			_read_model.load_from_runtime()
			_menu_entries = _command_registry.filter_menu_entries_with_preview(prefix, _read_model)
		else:
			_menu_entries = _command_registry.filter_menu_entries(prefix)
		_update_command_popup()
		if not _busy:
			show_notice("")
		return

	if _command_resolver == null or _read_model == null:
		_hide_command_popup()
		return

	_read_model.load_from_runtime()
	var arg_result: Dictionary = _command_resolver.build_arg_completion_entries(text, _read_model)
	if arg_result.get("active", false):
		_menu_mode = CommandMenuMode.ARG
		_menu_entries = arg_result.get("entries", [])
		_update_command_popup()
		if _is_hint_only_menu():
			show_notice(str(_menu_entries[0].get("label", "")))
		elif not _busy:
			show_notice("")
		return

	_hide_command_popup()


func _handle_command_menu_input(event: InputEvent) -> bool:
	if not _is_command_menu_active():
		return false
	if not event is InputEventKey:
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	match key.keycode:
		KEY_ESCAPE:
			_hide_command_popup()
			return true
		KEY_UP:
			_move_menu_highlight(-1)
			return true
		KEY_DOWN:
			_move_menu_highlight(1)
			return true
		KEY_ENTER, KEY_KP_ENTER:
			_confirm_menu_highlight()
			return true
	return false


func _on_command_item_selected(index: int, selected_on_mouse_event: bool) -> void:
	if selected_on_mouse_event:
		_apply_menu_entry(index)


func _on_command_item_activated(index: int) -> void:
	_apply_menu_entry(index)


func _apply_menu_entry(index: int) -> void:
	if index < 0 or index >= _menu_entries.size():
		return
	var entry: Dictionary = _menu_entries[index]
	if not _entry_is_actionable(entry):
		return
	var insert := str(entry.get("insert_text", "")).strip_edges()
	if insert.is_empty():
		return
	if str(entry.get("kind", "")) == "command":
		var cmd: Variant = entry.get("command", {})
		if cmd is Dictionary:
			var args: Variant = (cmd as Dictionary).get("args", [])
			if args is Array and not (args as Array).is_empty() and not insert.ends_with(" "):
				insert += " "
	fill_line_edit(insert)


func _is_command_menu_active() -> bool:
	return _command_menu != null and _command_menu.visible and not _menu_entries.is_empty()


func _move_menu_highlight(delta: int) -> void:
	if _menu_entries.is_empty():
		return
	var next := _menu_highlight_index
	if next < 0:
		next = 0 if delta > 0 else _menu_entries.size() - 1
	else:
		next += delta
	while next >= 0 and next < _menu_entries.size():
		if _entry_is_actionable(_menu_entries[next]):
			_menu_highlight_index = next
			_sync_menu_highlight()
			return
		next += delta
	_menu_highlight_index = -1
	_sync_menu_highlight()


func _confirm_menu_highlight() -> void:
	if not _is_command_menu_active():
		return
	if _menu_highlight_index < 0:
		_menu_highlight_index = 0
	_apply_menu_entry(_menu_highlight_index)


func _sync_menu_highlight() -> void:
	if _command_list == null:
		return
	if _menu_highlight_index < 0 or _menu_entries.is_empty():
		_command_list.deselect_all()
		return
	if not _entry_is_actionable(_menu_entries[_menu_highlight_index]):
		_command_list.deselect_all()
		return
	_command_list.select(_menu_highlight_index, true)
	_command_list.ensure_current_is_visible()


func _update_command_popup() -> void:
	if _command_menu == null or _command_list == null or _line_edit == null:
		return
	_command_list.clear()
	if _menu_entries.is_empty():
		_hide_command_popup()
		return
	for i in _menu_entries.size():
		var entry: Dictionary = _menu_entries[i]
		_command_list.add_item(str(entry.get("label", "")))
		if not _entry_is_actionable(entry):
			_command_list.set_item_disabled(i, true)
	var list_h := mini(COMMAND_MENU_MAX_HEIGHT, _menu_entries.size() * COMMAND_ITEM_HEIGHT)
	_command_list.custom_minimum_size = Vector2(0, list_h)
	_command_menu.custom_minimum_size = Vector2.ZERO
	var was_visible := _command_menu.visible
	_command_menu.visible = true
	if not was_visible or _menu_highlight_index < 0:
		_menu_highlight_index = _first_actionable_menu_index()
	else:
		_menu_highlight_index = clampi(_menu_highlight_index, 0, _menu_entries.size() - 1)
		if _menu_highlight_index >= 0 and not _entry_is_actionable(_menu_entries[_menu_highlight_index]):
			_menu_highlight_index = _first_actionable_menu_index()
	_sync_menu_highlight()
	if _line_edit and not _line_edit.has_focus() and not _line_edit.is_ime_composing():
		_line_edit.call_deferred("grab_focus")


func _hide_command_popup() -> void:
	if _command_menu:
		_command_menu.visible = false
	if _is_hint_only_menu() and not _busy:
		show_notice("")
	_menu_entries.clear()
	_menu_mode = CommandMenuMode.NONE
	_menu_highlight_index = -1
	if _command_list:
		_command_list.deselect_all()


func _entry_is_actionable(entry: Dictionary) -> bool:
	if str(entry.get("kind", "")) == "hint":
		return false
	return not str(entry.get("insert_text", "")).strip_edges().is_empty()


func _is_hint_only_menu() -> bool:
	return (
		_menu_entries.size() == 1
		and _menu_entries[0] is Dictionary
		and str((_menu_entries[0] as Dictionary).get("kind", "")) == "hint"
	)


func _first_actionable_menu_index() -> int:
	for i in _menu_entries.size():
		if _menu_entries[i] is Dictionary and _entry_is_actionable(_menu_entries[i]):
			return i
	return -1


func _format_entry_block(role: String, content: String) -> String:
	if content.is_empty():
		return ""
	if role == "user":
		return "[color=%s]【行动】[/color] %s\n\n" % [
			DesignTokensScript.STORY_ACTION_HEX,
			RichTextFormatScript.escape_bbcode(content),
		]
	return "%s\n\n" % _format_assistant_text(content)


static func _dialogue_line_regex() -> RegEx:
	if _dialogue_line_re == null:
		_dialogue_line_re = RegEx.new()
		_dialogue_line_re.compile("^(.+?)：「(.+?)」\\s*$")
	return _dialogue_line_re


func _format_assistant_text(text: String) -> String:
	var lines := text.split("\n")
	var out: PackedStringArray = []
	var dialogue_re := _dialogue_line_regex()
	var in_new_para := true
	for line in lines:
		var stripped := line.strip_edges()
		if stripped.is_empty():
			if out.size() > 0 and not out[out.size() - 1].is_empty():
				out.append("")
				in_new_para = true
			continue
		var m := dialogue_re.search(stripped)
		if m != null:
			out.append(
				RichTextFormatScript.dialogue_prefix_line(
					m.get_string(1),
					m.get_string(2),
					DesignTokensScript.STORY_DIALOGUE_PREFIX_HEX,
				)
			)
			in_new_para = true
		else:
			var check_bbcode := TrpgUiDisplayScript.format_check_line_bbcode(stripped)
			if not check_bbcode.is_empty():
				out.append(check_bbcode)
				in_new_para = true
				continue
			var formatted := RichTextFormatScript.sanitize_plain_text_once(stripped)
			if in_new_para:
				formatted = "　　" + formatted
			out.append(formatted)
			in_new_para = false
	return "\n".join(out)
