class_name GameSessionController
extends Node

const PlayerCommandResolverScript := preload("res://src/game/logic/input/player_command_resolver.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const StoryTextEditScript := preload("res://src/game/ui/story_text_edit.gd")
const UiBindScript := preload("res://src/ui/ui_bind.gd")
const ActionSuggestionBuilderScript := preload("res://src/game/logic/narrative/action_suggestion_builder.gd")
const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")
const NarrativeArchiveServiceScript := preload(
	"res://src/game/logic/narrative/narrative_archive_service.gd"
)

var _scene_root: Control
var _read_model := GameReadModel.new()
var _narrative := NarrativeService.new()
var _ai_client: AIClient
var _dynamic_add: DynamicAddService
var _command_resolver := PlayerCommandResolverScript.new()

var _hud_ui := GameHudUI.new()
var _story_ui := StoryColumnUI.new()
var _data_panels_ui := DataPanelsUI.new()

var _busy := false
var _session_started := false
var _pending_map_travel: Dictionary = {}


func setup(scene_root: Control) -> void:
	_scene_root = scene_root
	_ai_client = AIClient.new()
	add_child(_ai_client)
	_dynamic_add = DynamicAddService.new()
	add_child(_dynamic_add)
	_narrative.bind_ai_client(_ai_client)
	_narrative.bind_dynamic_add(_dynamic_add)

	_hud_ui.setup(
		_find_scene_node(scene_root, "DateWeatherLabel") as Label,
		_find_scene_node(scene_root, "LocationLabel") as Label,
		_find_scene_node(scene_root, "WalletLabel") as Label,
		_find_scene_node(scene_root, "ObjectiveLabel") as Label,
		_find_scene_node(scene_root, "SessionMetaLabel") as Label,
	)
	_story_ui.setup(
		_find_scene_node(scene_root, "StoryLog") as RichTextLabel,
		_find_scene_node(scene_root, "StoryLineEdit") as StoryTextEditScript,
		_find_scene_node(scene_root, "StorySendButton") as Button,
		_find_scene_node(scene_root, "StoryStatusLabel") as Label,
		_find_scene_node(scene_root, "SuggestionChips") as FlowContainer,
		_find_scene_node(scene_root, "CommandMenuPanel") as PanelContainer,
		_find_scene_node(scene_root, "CommandList") as ItemList,
		_command_resolver.get_registry(),
	)
	_story_ui.bind_command_completion(_command_resolver, _read_model)
	_data_panels_ui.setup(
		_read_model,
		_find_scene_node(scene_root, "SidebarList") as VBoxContainer,
		_find_scene_node(scene_root, "ContentHost") as Control,
		[
			_find_scene_node(scene_root, "CharactersNavButton") as Button,
			_find_scene_node(scene_root, "RelationshipsNavButton") as Button,
			_find_scene_node(scene_root, "SceneCharactersNavButton") as Button,
			_find_scene_node(scene_root, "MapNavButton") as Button,
			_find_scene_node(scene_root, "EventsNavButton") as Button,
		],
	)

	_story_ui.story_submit_requested.connect(_on_story_submit_requested)
	_data_panels_ui.travel_hint_changed.connect(_on_travel_hint_changed)
	_data_panels_ui.map_travel_target_changed.connect(_on_map_travel_target_changed)
	_data_panels_ui.set_event_recall_handler(Callable(self, "_on_event_recall_requested"))
	_data_panels_ui.set_event_recall_cancel_handler(Callable(self, "_on_event_recall_cancel_requested"))
	_connect_backend_signals()
	_sync_backend_port()
	if BackendLauncher.is_ready():
		_begin_session()
	else:
		_story_ui.show_notice("正在启动 AI 后端…")
		if not BackendLauncher.is_running():
			BackendLauncher.start_backend()


func _connect_backend_signals() -> void:
	if not BackendLauncher.backend_ready.is_connected(_on_backend_ready):
		BackendLauncher.backend_ready.connect(_on_backend_ready)
	if not BackendLauncher.backend_restarting.is_connected(_on_backend_restarting):
		BackendLauncher.backend_restarting.connect(_on_backend_restarting)
	if not BackendLauncher.backend_failed.is_connected(_on_backend_failed):
		BackendLauncher.backend_failed.connect(_on_backend_failed)


func _on_backend_ready(port: int) -> void:
	_ai_client.set_port(port)
	_dynamic_add.set_port(port)
	if not _session_started:
		_begin_session()
		_session_started = true
	else:
		_story_ui.show_notice("AI 后端已重新连接。")


func _on_backend_restarting(attempt: int, max_attempts: int, _reason: String) -> void:
	_busy = false
	_story_ui.set_busy(false)
	_story_ui.show_notice("AI 后端断开，正在自动重启 (%d/%d)…" % [attempt, max_attempts])


func _on_backend_failed(reason: String) -> void:
	printerr("[GameSession] 后端启动失败: ", reason)
	_busy = false
	_story_ui.set_busy(false)
	_story_ui.show_error("AI 后端启动失败：%s" % reason)


func _sync_backend_port() -> void:
	if BackendLauncher.is_ready():
		var port := BackendLauncher.get_port()
		_ai_client.set_port(port)
		_dynamic_add.set_port(port)


func _begin_session() -> void:
	_read_model.load_from_runtime()
	_refresh_all_ui()
	_apply_suggestions_from_rules()
	_data_panels_ui.select_initial_mode()
	if _narrative.needs_bootstrap():
		await _run_bootstrap()


func _refresh_all_ui(refresh_story_log: bool = true, restore_suggestions: bool = true) -> void:
	_read_model.load_from_runtime()
	var vm := _read_model.to_view_model()
	_hud_ui.render(vm)
	if refresh_story_log:
		_story_ui.render_story_log(vm.get("story_log", []), false, true)
	_data_panels_ui.bind_read_model(_read_model)
	_data_panels_ui.render(vm)
	if restore_suggestions:
		var saved: Array = _read_model.get_last_suggestions()
		if not saved.is_empty():
			_story_ui.set_suggestions(saved)


func _on_event_recall_requested(event: Dictionary) -> void:
	if event.is_empty():
		return
	var state_svc := RuntimeStateService.new()
	state_svc.load_from_runtime()
	if not state_svc.set_pinned_recall_event(event):
		_story_ui.show_error("无法标记回顾事件")
		return
	var title := str(event.get("title", "该事件")).strip_edges()
	_story_ui.show_notice("已标记「%s」：下一轮叙事将优先衔接此段记忆。" % title)
	_refresh_event_recall_panel()


func _on_event_recall_cancel_requested() -> void:
	var state_svc := RuntimeStateService.new()
	state_svc.load_from_runtime()
	var pinned: Dictionary = state_svc.get_pinned_recall_event()
	if pinned.is_empty():
		_refresh_event_recall_panel()
		return
	var title := str(pinned.get("title", "该事件")).strip_edges()
	if not state_svc.set_pinned_recall_event({}):
		_story_ui.show_error("无法取消标记")
		return
	_story_ui.show_notice("已取消标记「%s」。" % title)
	_refresh_event_recall_panel()


func _refresh_event_recall_panel() -> void:
	_read_model.load_from_runtime()
	_data_panels_ui.bind_read_model(_read_model)
	_data_panels_ui.refresh_events_panel()


func _on_story_submit_requested(text: String) -> void:
	if _busy:
		return
	if not BackendLauncher.is_ready():
		if not BackendLauncher.is_running():
			_story_ui.show_notice("正在启动 AI 后端…")
			BackendLauncher.start_backend()
		_story_ui.show_error("AI 后端未就绪，请稍候或检查设置中的 AI 配置")
		return

	var player_text := text.strip_edges()
	var talk_npc_id := ""
	if player_text.begins_with("/"):
		_read_model.load_from_runtime()
		var resolved: Dictionary = _command_resolver.resolve(player_text, _read_model)
		if not resolved.get("ok", false):
			_story_ui.show_error(str(resolved.get("error", "命令无效")))
			return
		player_text = str(resolved.get("expanded", "")).strip_edges()
		talk_npc_id = str(resolved.get("talk_npc_id", "")).strip_edges()
		if player_text.is_empty():
			_story_ui.show_error("命令展开为空")
			return

	await _run_turn(player_text, talk_npc_id)


func _on_travel_hint_changed(text: String) -> void:
	if text.is_empty():
		_story_ui.clear_travel_hint()
	else:
		_story_ui.set_travel_hint(text)


func _on_map_travel_target_changed(target: Dictionary) -> void:
	_pending_map_travel = target.duplicate(true) if target is Dictionary else {}


func _run_bootstrap() -> void:
	_busy = true
	_story_ui.set_busy(true)
	var result: Dictionary = await _narrative.bootstrap_opening()
	await _finish_turn(result, false)
	_update_suggestions_after_turn(result)
	_busy = false
	_story_ui.set_busy(false)


func _run_turn(player_text: String, talk_npc_id: String = "") -> void:
	_busy = true
	_story_ui.set_busy(true)
	_story_ui.append_entry("user", player_text, false)
	_read_model.load_from_runtime()
	var state_svc := RuntimeStateService.new()
	state_svc.load_from_runtime()
	var npc_to_record := talk_npc_id.strip_edges()
	if npc_to_record.is_empty():
		npc_to_record = LocationServiceScript.resolve_talk_target_npc_id(player_text, _read_model)
	if not npc_to_record.is_empty():
		state_svc.record_talked_npc(npc_to_record)
	if NarrativeArchiveServiceScript.can_archive_pending(
		state_svc.get_story_log(),
		state_svc.get_last_archive_story_index(),
		state_svc.get_chars_since_last_archive(),
	):
		_story_ui.show_notice("正在整理章节记忆…")
	var map_travel := _pending_map_travel.duplicate(true)
	_pending_map_travel = {}
	var result: Dictionary = await _narrative.submit_turn(player_text, map_travel)
	if result.get("ok", false):
		_data_panels_ui.clear_map_travel()
	await _finish_turn(result, true)
	_update_suggestions_after_turn(result)
	_busy = false
	_story_ui.set_busy(false)


func _finish_turn(result: Dictionary, _already_appended_user: bool) -> void:
	if not result.get("ok", false):
		_story_ui.show_error(str(result.get("error", "叙事失败")))
		return

	var story_text := str(result.get("story_text", "")).strip_edges()
	var resolved_text := story_text
	if not result.get("dynamic_add_in_turn", false):
		resolved_text = await _resolve_dynamic_add(story_text)
		if resolved_text != story_text and not resolved_text.is_empty():
			_persist_resolved_assistant_story(resolved_text)
			_story_ui.show_notice("动态内容已更新（已写入数据库）")
	elif result.get("dynamic_add_results") is Array:
		var dyn_results: Array = result["dynamic_add_results"]
		for item in dyn_results:
			if item is Dictionary and item.get("ok", false) and item.get("status") == "new_created":
				if result.get("auto_repair_applied", false):
					_story_ui.show_notice("已根据剧情自动登记新地点/人物（写入数据库）")
				else:
					_story_ui.show_notice("动态内容已更新（已写入数据库）")
				break

	var archive_warning := str(result.get("archive_warning", "")).strip_edges()
	if not archive_warning.is_empty():
		_story_ui.show_notice("章节记忆整理未完成：%s" % archive_warning)

	if result.get("archived", false):
		var archive_title := str(result.get("archive_title", "")).strip_edges()
		if archive_title.is_empty():
			_story_ui.show_notice("较早剧情已收入事件回顾，继续新的章节。")
		else:
			_story_ui.show_notice("章节「%s」已归档至事件回顾。" % archive_title)

	if not result.get("parse_ok", false):
		_story_ui.show_notice("提示：%s" % str(result.get("error", "状态 hook 未应用")))

	var warnings: Variant = result.get("hook_warnings", [])
	if warnings is PackedStringArray and not warnings.is_empty():
		for w in warnings:
			push_warning("[GameSession] %s" % w)
		_story_ui.show_notice(_format_hook_warnings(warnings))

	var archived: bool = result.get("archived", false)
	if archived:
		_refresh_all_ui(true, false)
	else:
		var display_text := resolved_text if not resolved_text.is_empty() else story_text
		var check: Variant = result.get("check_result", {})
		if check is Dictionary and check.get("needs_check", false):
			var check_block := TrpgUiDisplayScript.format_check_block_text(check as Dictionary)
			if not check_block.is_empty():
				display_text = check_block + "\n\n" + display_text
		if not display_text.is_empty():
			_persist_resolved_assistant_story(display_text)
			_story_ui.append_entry("assistant", display_text, true)
		_refresh_all_ui(false, false)


static func _format_hook_warnings(warnings: PackedStringArray) -> String:
	var prioritized: PackedStringArray = []
	var rest: PackedStringArray = []
	for w in warnings:
		var text := str(w)
		if text.begins_with("discoveries") or text.find("未知档案字段") >= 0:
			prioritized.append(text)
		else:
			rest.append(text)
	var ordered: PackedStringArray = []
	ordered.append_array(prioritized)
	ordered.append_array(rest)
	var parts: PackedStringArray = []
	var limit := mini(3, ordered.size())
	for i in range(limit):
		parts.append(ordered[i])
	var msg := "；".join(parts)
	if ordered.size() > limit:
		msg += " 等"
	return "状态同步提示：%s" % msg


func _persist_resolved_assistant_story(resolved_text: String) -> void:
	var state_svc := RuntimeStateService.new()
	state_svc.load_from_runtime()
	state_svc.update_last_assistant_story_content(resolved_text)


func _update_suggestions_after_turn(result: Dictionary) -> void:
	_read_model.load_from_runtime()
	var ai_list: Array = []
	if result.get("suggestions") is Array:
		ai_list = result["suggestions"]
	var rule_list := ActionSuggestionBuilderScript.build_from_read_model(_read_model)
	var filtered_ai := ActionSuggestionBuilderScript.filter_suggestions_against_world(_read_model, ai_list)
	var merged := ActionSuggestionBuilderScript.merge(filtered_ai, rule_list)
	var merged_array: Array = []
	for text in merged:
		merged_array.append(text)
	if merged_array.is_empty():
		merged_array = _read_model.get_last_suggestions()
	var state_svc := RuntimeStateService.new()
	state_svc.load_from_runtime()
	state_svc.save_last_suggestions(merged_array)
	_story_ui.set_suggestions(merged_array)


func _apply_suggestions_from_rules() -> void:
	_read_model.load_from_runtime()
	var saved: Array = _read_model.get_last_suggestions()
	if not saved.is_empty():
		_story_ui.set_suggestions(saved)
		return
	var rule_list := ActionSuggestionBuilderScript.build_from_read_model(_read_model)
	var items: Array = []
	for text in rule_list:
		items.append(text)
	if not items.is_empty():
		_story_ui.set_suggestions(items)


static func _find_scene_node(root: Node, node_name: String) -> Node:
	return UiBindScript.find_named(root, node_name)


func _resolve_dynamic_add(story_text: String) -> String:
	if story_text.is_empty():
		return story_text
	var world_context := JSON.stringify(_read_model.base_config, "\t")
	var pipeline: Dictionary = await _dynamic_add.resolve_triggers_in_text(
		story_text,
		world_context,
		false,
	)
	if pipeline.get("ok", false):
		return str(pipeline.get("assistant_text", story_text))
	return story_text
