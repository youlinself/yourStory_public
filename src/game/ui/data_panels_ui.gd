class_name DataPanelsUI
extends RefCounted

signal travel_hint_changed(hint_text: String)
signal map_travel_target_changed(target: Dictionary)

const ProtagonistPanelScript := preload("res://src/game/panels/protagonist_panel.gd")
const GridMapViewScript := preload("res://src/game/grid_map_view.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const NpcSidebarLocationTreeScript := preload("res://src/game/logic/world/npc_sidebar_location_tree.gd")
const CollapsibleSidebarSectionScript := preload("res://src/game/ui/collapsible_sidebar_section.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")

enum NavMode { CHARACTERS, RELATIONSHIPS, SCENE_CHARACTERS, MAP, EVENTS }

const PANEL_SCENES := {
	NavMode.CHARACTERS: "res://sences/game/panels/protagonist_panel.tscn",
	NavMode.RELATIONSHIPS: "res://sences/game/panels/character_detail_panel.tscn",
	NavMode.SCENE_CHARACTERS: "res://sences/game/panels/character_detail_panel.tscn",
	NavMode.MAP: "res://sences/game/panels/map_detail_panel.tscn",
	NavMode.EVENTS: "res://sences/game/panels/event_detail_panel.tscn",
}

var _read_model: GameReadModel
var _sidebar_list: VBoxContainer
var _content_host: Control
var _nav_buttons: Array[Button] = []
var _current_mode: NavMode = NavMode.CHARACTERS
var _panel_instances: Dictionary = {}
var _selected_sidebar_id: String = ""
var _protagonist_subview: ProtagonistPanelScript.SubView = ProtagonistPanelScript.SubView.INFO
var _event_recall_connected := false
var _event_recall_cancel_connected := false
var _map_region_connected := false
var _map_child_connected := false
var _map_travel_connected := false
var _event_recall_handler: Callable = Callable()
var _event_recall_cancel_handler: Callable = Callable()
var _last_shown_event: Dictionary = {}
var _sidebar_expanded_keys: Dictionary = {}
var _sidebar_manual_expanded_keys: Dictionary = {}
var _rebuilding_sidebar := false


func set_event_recall_handler(handler: Callable) -> void:
	_event_recall_handler = handler


func set_event_recall_cancel_handler(handler: Callable) -> void:
	_event_recall_cancel_handler = handler


func setup(
	read_model: GameReadModel,
	sidebar_list: VBoxContainer,
	content_host: Control,
	nav_buttons: Array[Button],
) -> void:
	_read_model = read_model
	_sidebar_list = sidebar_list
	_content_host = content_host
	_nav_buttons = nav_buttons
	for i in _nav_buttons.size():
		var nav_btn := _nav_buttons[i]
		if nav_btn:
			nav_btn.pressed.connect(_on_nav_pressed.bind(i))


func bind_read_model(read_model: GameReadModel) -> void:
	_read_model = read_model


func render(_vm: Dictionary = {}) -> void:
	_rebuild_sidebar()
	_refresh_panel_content()


func select_initial_mode() -> void:
	_select_mode(NavMode.CHARACTERS)


func _on_nav_pressed(mode_index: int) -> void:
	_select_mode(mode_index as NavMode)


func _select_mode(mode: NavMode) -> void:
	_current_mode = mode
	_selected_sidebar_id = ""
	if mode == NavMode.CHARACTERS:
		_protagonist_subview = ProtagonistPanelScript.SubView.INFO
		_selected_sidebar_id = "__protagonist_info__"
	if mode == NavMode.RELATIONSHIPS or mode == NavMode.SCENE_CHARACTERS:
		_sidebar_manual_expanded_keys.clear()
		_sidebar_expanded_keys.clear()
	for i in _nav_buttons.size():
		var nav_btn := _nav_buttons[i]
		if nav_btn:
			nav_btn.button_pressed = i == int(mode)
	_swap_content_panel(mode)
	_rebuild_sidebar()
	_show_default_content()


func _swap_content_panel(mode: NavMode) -> void:
	for child in _content_host.get_children():
		_content_host.remove_child(child)
	if not _panel_instances.has(mode):
		var scene := load(PANEL_SCENES[mode]) as PackedScene
		_panel_instances[mode] = scene.instantiate()
		if mode == NavMode.EVENTS:
			_connect_event_recall_signal(_panel_instances[mode])
		if mode == NavMode.MAP:
			_connect_map_signals(_panel_instances[mode])
	var panel: Control = _panel_instances[mode] as Control
	_content_host.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _connect_map_signals(panel: Node) -> void:
	if panel == null:
		return
	if not _map_region_connected and panel.has_signal("region_selected"):
		panel.region_selected.connect(_on_map_region_selected)
		_map_region_connected = true
	if not _map_child_connected and panel.has_signal("child_map_selected"):
		panel.child_map_selected.connect(_on_child_map_selected)
		_map_child_connected = true
	if not _map_travel_connected and panel.has_signal("travel_cell_toggled"):
		panel.travel_cell_toggled.connect(_on_travel_cell_toggled)
		_map_travel_connected = true


func _on_map_region_selected(region_id: String) -> void:
	var page: Dictionary = _read_model.get_primary_map_page_for_region(region_id)
	if page.is_empty():
		return
	_on_map_page_sidebar_pressed(str(page.get("id", "")))


func _on_child_map_selected(child_map_id: String) -> void:
	var page_id := child_map_id.strip_edges()
	if page_id.is_empty():
		return
	_clear_map_travel()
	_on_map_page_sidebar_pressed(page_id)


func clear_map_travel() -> void:
	_clear_map_travel()


func _clear_map_travel() -> void:
	travel_hint_changed.emit("")
	map_travel_target_changed.emit({})


func _on_travel_cell_toggled(cell_data: Dictionary, active: bool) -> void:
	if not active:
		_clear_map_travel()
		return
	var label := GridMapViewScript.format_travel_cell_label(cell_data, _read_model)
	if label.is_empty():
		_clear_map_travel()
		return
	travel_hint_changed.emit("你准备去%s" % label)
	var map_page := _read_model.get_map_page(_selected_sidebar_id)
	var target := LocationServiceScript.resolve_map_cell_travel_target(
		_read_model,
		map_page,
		cell_data,
	)
	map_travel_target_changed.emit(target)


func _connect_event_recall_signal(panel: Node) -> void:
	if panel == null:
		return
	if not _event_recall_connected and panel.has_signal("recall_requested"):
		panel.recall_requested.connect(_on_event_recall_pressed)
		_event_recall_connected = true
	if not _event_recall_cancel_connected and panel.has_signal("recall_cancel_requested"):
		panel.recall_cancel_requested.connect(_on_event_recall_cancel_pressed)
		_event_recall_cancel_connected = true


func _on_event_recall_pressed(event: Dictionary) -> void:
	if _event_recall_handler.is_valid():
		_event_recall_handler.call(event)


func _on_event_recall_cancel_pressed() -> void:
	if _event_recall_cancel_handler.is_valid():
		_event_recall_cancel_handler.call()


func refresh_events_panel() -> void:
	if _current_mode != NavMode.EVENTS or _last_shown_event.is_empty():
		return
	_show_event(_last_shown_event)


func _rebuild_sidebar() -> void:
	for child in _sidebar_list.get_children():
		child.queue_free()
	match _current_mode:
		NavMode.CHARACTERS:
			_build_protagonist_sidebar()
		NavMode.RELATIONSHIPS:
			_build_npc_sidebar()
		NavMode.SCENE_CHARACTERS:
			_build_scene_characters_sidebar()
		NavMode.MAP:
			_build_map_sidebar()
		NavMode.EVENTS:
			_build_event_sidebar()


func _build_protagonist_sidebar() -> void:
	var known := _read_model.get_known_protagonist_profile()
	var name := ProtagonistPanelScript.format_protagonist_display_name(known.get("name", ""))
	_add_sidebar_hint("角色卡")
	_add_protagonist_name_card(name)
	_add_protagonist_subnav_button(
		"__protagonist_info__",
		"档案",
		ProtagonistPanelScript.SubView.INFO,
	)
	_add_protagonist_subnav_button(
		"__protagonist_backpack__",
		"装备",
		ProtagonistPanelScript.SubView.BACKPACK,
	)
	_add_protagonist_subnav_button(
		"__protagonist_skills__",
		"技能",
		ProtagonistPanelScript.SubView.SKILLS,
	)
	_add_protagonist_subnav_button(
		"__protagonist_assets__",
		"资产",
		ProtagonistPanelScript.SubView.ASSETS,
	)
	if _selected_sidebar_id.is_empty():
		_selected_sidebar_id = "__protagonist_info__"
		_protagonist_subview = ProtagonistPanelScript.SubView.INFO
	_apply_sidebar_selection()


func _build_npc_sidebar() -> void:
	var npcs := _read_model.get_talked_npcs()
	if npcs.is_empty():
		_add_sidebar_hint("尚未与任何角色建立联系")
		return
	var tree := NpcSidebarLocationTreeScript.build(_read_model, npcs)
	var pick_default := _selected_sidebar_id.is_empty()
	if pick_default:
		_selected_sidebar_id = _default_npc_id_for_sidebar()
	var required := _npc_sidebar_required_expanded_keys(tree, _selected_sidebar_id)
	if pick_default:
		_apply_protagonist_location_expansion(required, tree)
	_sidebar_expanded_keys = _merge_expanded_keys(required, _sidebar_manual_expanded_keys)
	_render_location_tree_node(_sidebar_list, tree, "", 0)
	_apply_sidebar_selection()


func _build_scene_characters_sidebar() -> void:
	var npcs := _read_model.get_same_place_npcs()
	if npcs.is_empty():
		_add_sidebar_hint("当前场景暂无其他角色")
		return
	if _selected_sidebar_id.is_empty():
		_selected_sidebar_id = _default_npc_id_for_sidebar()
	for npc in npcs:
		if not npc is Dictionary:
			continue
		var npc_id := str(npc.get("id", "")).strip_edges()
		if npc_id.is_empty():
			continue
		var display_name := _read_model.get_known_display_name(npc_id, str(npc.get("name", "?")))
		display_name += TrpgUiDisplayScript.format_npc_favorability_suffix(
			_read_model.get_npc_favorability(npc_id),
		)
		_add_sidebar_toggle_button(npc_id, display_name, _on_npc_sidebar_pressed.bind(npc_id), true)
	_apply_sidebar_selection()


func _npcs_for_sidebar() -> Array[Dictionary]:
	match _current_mode:
		NavMode.RELATIONSHIPS:
			return _read_model.get_talked_npcs()
		NavMode.SCENE_CHARACTERS:
			return _read_model.get_same_place_npcs()
	return []


func _npc_detail_panel() -> Node:
	return _panel_instances.get(_current_mode)


func _build_map_sidebar() -> void:
	var loc_path := _read_model.get_location_path()
	if not loc_path.is_empty():
		_add_map_sidebar_hint("当前：%s" % loc_path)
	var pages: Array[Dictionary] = _read_model.get_unlocked_map_pages()
	if pages.is_empty():
		_add_map_sidebar_hint("暂无已解锁地图")
		return
	_add_map_sidebar_button("__overview__", "总览", _on_map_overview_pressed)
	for page in pages:
		var page_id := str(page.get("id", "")).strip_edges()
		if page_id.is_empty():
			continue
		var label := str(page.get("name", page_id)).strip_edges()
		var is_current := _is_page_current_location(page)
		_add_map_sidebar_button(page_id, label, _on_map_page_sidebar_pressed.bind(page_id), is_current)


func _build_event_sidebar() -> void:
	var events := _read_model.get_events_chronological()
	if events.is_empty():
		_add_sidebar_hint("暂无历程记录")
		return
	for i in events.size():
		var event: Dictionary = events[i]
		var event_id := "event_%d" % i
		_add_text_sidebar_button(event_id, str(event.get("title", "事件")), _on_event_sidebar_pressed.bind(event))


func _add_sidebar_hint(text: String) -> void:
	_sidebar_list.add_child(UiStylesScript.make_hint_panel(text, "muted"))


func _add_map_sidebar_hint(text: String) -> void:
	_sidebar_list.add_child(UiStylesScript.make_hint_panel(text, "accent"))


func _add_map_sidebar_button(
	id: String,
	text: String,
	callback: Callable,
	is_current_location: bool = false,
) -> void:
	_add_sidebar_toggle_button(id, text, callback, is_current_location)


func _is_page_current_location(page: Dictionary) -> bool:
	var parent_type := str(page.get("parent_type", "")).strip_edges()
	var parent_id := str(page.get("parent_id", "")).strip_edges()
	if parent_id.is_empty():
		return false
	var current_region := str(_read_model.mainrole.get("current_region_id", "")).strip_edges()
	var current_kn := str(_read_model.mainrole.get("current_key_node_id", "")).strip_edges()
	match parent_type:
		"region":
			return parent_id == current_region
		"key_node":
			return parent_id == current_kn
		_:
			return false


func _add_protagonist_name_card(display_name: String) -> void:
	var panel := PanelContainer.new()
	UiStylesScript.apply_panel_surface(panel)
	var label := Label.new()
	label.text = display_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	panel.add_child(label)
	_sidebar_list.add_child(panel)


func _add_protagonist_subnav_button(id: String, text: String, subview: ProtagonistPanelScript.SubView) -> void:
	var btn := _create_sidebar_toggle(id, text, func() -> void:
		_protagonist_subview = subview
		_show_protagonist()
	)
	_sidebar_list.add_child(btn)


func _add_text_sidebar_button(id: String, text: String, callback: Callable) -> void:
	_add_sidebar_toggle_button(id, text, callback)


func _add_sidebar_toggle_button(
	id: String,
	text: String,
	callback: Callable,
	is_current_location: bool = false,
) -> void:
	var btn := _create_sidebar_toggle(id, text, callback, is_current_location)
	_sidebar_list.add_child(btn)
	if _selected_sidebar_id.is_empty():
		_selected_sidebar_id = id
		btn.button_pressed = true


func _create_sidebar_toggle(
	id: String,
	text: String,
	callback: Callable,
	is_current_location: bool = false,
) -> Button:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.text = text
	btn.set_meta("sidebar_id", id)
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesScript.apply_sidebar_toggle(btn, is_current_location)
	btn.pressed.connect(func() -> void:
		_select_sidebar_item(id, btn)
		callback.call()
	)
	return btn


func _render_location_tree_node(
	parent: VBoxContainer,
	node: Dictionary,
	path_prefix: String,
	depth: int,
) -> void:
	var children: Variant = node.get("children", {})
	if children is Dictionary:
		var child_map: Dictionary = children
		for segment in NpcSidebarLocationTreeScript.sorted_segment_keys(node):
			var child: Dictionary = child_map[segment]
			var path_key := NpcSidebarLocationTreeScript.join_path(path_prefix, segment)
			var expanded := bool(_sidebar_expanded_keys.get(path_key, false))
			var section := CollapsibleSidebarSectionScript.create(
				parent,
				segment,
				depth,
				expanded,
				NpcSidebarLocationTreeScript.header_kind_for_node(child),
				func(is_expanded: bool) -> void:
					_on_location_section_toggled(path_key, is_expanded),
			)
			var body: VBoxContainer = section["body"]
			_render_location_tree_node(body, child, path_key, depth + 1)

	var groups: Variant = node.get("groups", {})
	if not groups is Dictionary:
		return
	var group_keys: Array = (groups as Dictionary).keys()
	group_keys.sort()
	for group_key in group_keys:
		var entries: Variant = (groups as Dictionary)[group_key]
		if not entries is Array:
			continue
		for entry in entries:
			if entry is Dictionary:
				_add_npc_tree_button(parent, entry as Dictionary, depth)


func _add_npc_tree_button(parent: VBoxContainer, entry: Dictionary, depth: int) -> void:
	var npc_id := str(entry.get("id", "")).strip_edges()
	if npc_id.is_empty():
		return
	var display_name := str(entry.get("name", "?"))
	display_name += TrpgUiDisplayScript.format_npc_favorability_suffix(
		_read_model.get_npc_favorability(npc_id),
	)
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn := _create_sidebar_toggle(npc_id, display_name, _on_npc_sidebar_pressed.bind(npc_id))
	var same_place := bool(entry.get("same_place", false))
	if not same_place:
		btn.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_LOCATION_FAR)
		btn.add_theme_color_override("font_hover_color", DesignTokensScript.COLOR_TEXT_LOCATION_FAR.lightened(0.12))
	row.add_child(btn)
	var margin_px := (depth + 1) * CollapsibleSidebarSectionScript.INDENT_PX
	parent.add_child(CollapsibleSidebarSectionScript.wrap_with_left_margin(row, margin_px))


func _default_npc_id_for_sidebar() -> String:
	var here := LocationServiceScript.get_protagonist_location(_read_model)
	var fallback := ""
	for npc in _npcs_for_sidebar():
		if not npc is Dictionary:
			continue
		var npc_id := str(npc.get("id", "")).strip_edges()
		if npc_id.is_empty():
			continue
		if fallback.is_empty():
			fallback = npc_id
		var npc_loc := LocationServiceScript.get_npc_location(_read_model, npc)
		if LocationServiceScript.is_same_place(here, npc_loc):
			return npc_id
	return fallback


func _apply_protagonist_location_expansion(required: Dictionary, tree: Dictionary) -> void:
	var segments := NpcSidebarLocationTreeScript.protagonist_path_segments(_read_model)
	for path_key in NpcSidebarLocationTreeScript.collect_prefix_keys_for_segments(tree, segments):
		required[path_key] = true


func _select_sidebar_item(id: String, active_btn: Button) -> void:
	var prev_id := _selected_sidebar_id
	_selected_sidebar_id = id
	if (
		_current_mode == NavMode.RELATIONSHIPS
		and _is_npc_sidebar_id(id)
		and id != prev_id
		and not _rebuilding_sidebar
	):
		_sync_npc_sidebar_expansion_for(id)
		_rebuilding_sidebar = true
		_rebuild_sidebar()
		_rebuilding_sidebar = false
		_apply_sidebar_selection()
		return
	_apply_sidebar_selection(active_btn)


func _is_npc_sidebar_id(id: String) -> bool:
	var sid := id.strip_edges()
	return not sid.is_empty() and not sid.begins_with("__") and not sid.begins_with("event_")


func _npc_sidebar_required_expanded_keys(tree: Dictionary, npc_id: String) -> Dictionary:
	var out: Dictionary = {}
	for path_key in NpcSidebarLocationTreeScript.collect_ancestor_keys(tree, npc_id):
		out[path_key] = true
	return out


func _merge_expanded_keys(required: Dictionary, manual: Dictionary) -> Dictionary:
	var out := required.duplicate()
	for path_key in manual:
		out[path_key] = true
	return out


func _sync_npc_sidebar_expansion_for(npc_id: String) -> void:
	var npcs := _read_model.get_talked_npcs()
	if npcs.is_empty():
		return
	var tree := NpcSidebarLocationTreeScript.build(_read_model, npcs)
	var required := _npc_sidebar_required_expanded_keys(tree, npc_id)
	_sidebar_expanded_keys = _merge_expanded_keys(required, _sidebar_manual_expanded_keys)


func _on_location_section_toggled(path_key: String, is_expanded: bool) -> void:
	if is_expanded:
		_sidebar_manual_expanded_keys[path_key] = true
		_sidebar_expanded_keys[path_key] = true
	else:
		_sidebar_manual_expanded_keys.erase(path_key)
		_sidebar_expanded_keys.erase(path_key)


func _apply_sidebar_selection(active_btn: Button = null) -> void:
	for child in _sidebar_list.get_children():
		_apply_sidebar_selection_in(child, active_btn)


func _apply_sidebar_selection_in(node: Node, active_btn: Button = null) -> void:
	if node is Button:
		var btn := node as Button
		if btn.has_meta("sidebar_id"):
			if active_btn != null:
				btn.button_pressed = btn == active_btn
			else:
				btn.button_pressed = str(btn.get_meta("sidebar_id")) == _selected_sidebar_id
	for child in node.get_children():
		_apply_sidebar_selection_in(child, active_btn)


func _refresh_panel_content() -> void:
	_show_default_content()


func _show_default_content() -> void:
	match _current_mode:
		NavMode.CHARACTERS:
			_show_protagonist()
		NavMode.RELATIONSHIPS, NavMode.SCENE_CHARACTERS:
			if not _selected_sidebar_id.is_empty():
				_show_npc(_selected_sidebar_id)
			else:
				var npcs := _npcs_for_sidebar()
				if not npcs.is_empty():
					_show_npc(str(npcs[0].get("id", "")))
				else:
					_show_npc_empty()
		NavMode.MAP:
			if _selected_sidebar_id == "__overview__" or _selected_sidebar_id.is_empty():
				_show_map_overview()
			else:
				_show_map_page(_selected_sidebar_id)
		NavMode.EVENTS:
			var events := _read_model.get_events_chronological()
			if not events.is_empty():
				_show_event(events[0])


func _show_protagonist() -> void:
	var panel: Node = _panel_instances.get(NavMode.CHARACTERS)
	if panel and panel.has_method("show_protagonist"):
		var vm := _read_model.to_view_model()
		panel.show_protagonist(
			_read_model.mainrole,
			_read_model.get_known_protagonist_profile(),
			_read_model.get_skills_catalog(),
			_read_model.get_items_catalog(),
			_read_model.get_wallet(),
			str(vm.get("adventure_card_bbcode", "")),
		)
	if panel and panel.has_method("show_subview"):
		panel.show_subview(_protagonist_subview)


func _on_npc_sidebar_pressed(npc_id: String) -> void:
	_show_npc(npc_id)


func _show_npc(npc_id: String) -> void:
	var panel: Node = _npc_detail_panel()
	if panel and panel.has_method("show_npc"):
		var npc := _read_model.get_npc(npc_id)
		var here := LocationServiceScript.get_protagonist_location(_read_model)
		var npc_loc := LocationServiceScript.get_npc_location(_read_model, npc)
		panel.show_npc(
			_read_model.get_known_npc_profile(npc_id),
			_read_model.get_skills_catalog(),
			LocationServiceScript.format_location_path(_read_model, npc_loc),
			LocationServiceScript.is_same_place(here, npc_loc),
			_read_model.get_npc_favorability(npc_id),
		)


func _show_npc_empty() -> void:
	var panel: Node = _npc_detail_panel()
	if panel and panel.has_method("show_npc"):
		panel.show_npc({}, _read_model.get_skills_catalog())


func _on_map_overview_pressed() -> void:
	_selected_sidebar_id = "__overview__"
	_apply_sidebar_selection()
	_clear_map_travel()
	_show_map_overview()


func _on_map_page_sidebar_pressed(page_id: String) -> void:
	_selected_sidebar_id = page_id.strip_edges()
	_apply_sidebar_selection()
	_clear_map_travel()
	_show_map_page(_selected_sidebar_id)


func _show_map_page(page_id: String) -> void:
	var panel: Node = _panel_instances.get(NavMode.MAP)
	if not panel or not panel.has_method("show_map_page"):
		return
	var map_page: Dictionary = _read_model.get_map_page(page_id)
	var region: Dictionary = {}
	var parent_type := str(map_page.get("parent_type", "")).strip_edges()
	var parent_id := str(map_page.get("parent_id", "")).strip_edges()
	if parent_type == "region":
		region = _read_model.get_region(parent_id)
	elif parent_type == "key_node":
		var node: Dictionary = _read_model.get_key_node(parent_id)
		region = _read_model.get_region(str(node.get("region_id", "")))
	var current_kn := ""
	if parent_type == "key_node":
		current_kn = parent_id
	elif str(_read_model.mainrole.get("current_region_id", "")) == parent_id:
		current_kn = str(_read_model.mainrole.get("current_key_node_id", ""))
	var highlight_cell := Vector2i(-1, -1)
	var stored_cell: Variant = _read_model.mainrole.get("current_map_cell", null)
	if stored_cell is Dictionary:
		var cell: Dictionary = stored_cell
		if str(cell.get("page_id", "")).strip_edges() == page_id:
			highlight_cell = Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))
	panel.show_map_page(
		map_page,
		_read_model.get_location_path(),
		current_kn,
		region,
		highlight_cell,
	)


func _show_map_overview() -> void:
	var panel: Node = _panel_instances.get(NavMode.MAP)
	if panel and panel.has_method("show_overview"):
		panel.show_overview(
			_read_model.get_map_structure(),
			_read_model.get_unlocked_regions(),
			_read_model.get_key_nodes(),
			str(_read_model.mainrole.get("current_region_id", "")),
			str(_read_model.mainrole.get("current_key_node_id", "")),
			_read_model.get_location_path(),
		)


func _on_event_sidebar_pressed(event: Dictionary) -> void:
	_show_event(event)


func _show_event(event: Dictionary) -> void:
	_last_shown_event = event.duplicate(true) if event is Dictionary else {}
	var panel: Node = _panel_instances.get(NavMode.EVENTS)
	if panel and panel.has_method("show_event"):
		var region_id := str(event.get("region_id", ""))
		var region_name: String = (
			str(_read_model.get_region(region_id).get("name", "")) if not region_id.is_empty() else ""
		)
		var is_pinned: bool = _read_model.is_event_pinned_for_recall(event)
		panel.show_event(event, region_name, is_pinned)
