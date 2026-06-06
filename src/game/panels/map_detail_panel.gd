extends Control

signal region_selected(region_id: String)
signal child_map_selected(child_map_id: String)
signal travel_cell_toggled(cell_data: Dictionary, active: bool)

const MapRegionDisplayScript := preload("res://src/game/logic/data/map_region_display.gd")
const GridMapViewScript := preload("res://src/game/grid_map_view.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")

const WIDE_BREAKPOINT := 0
const COLLAPSED_ICON := "▸"
const EXPANDED_ICON := "▾"
const FIELD_KEYS: Array[String] = [
	"location",
	"terrain",
	"climate",
	"resources",
	"hazards",
	"access",
	"settlements",
]

@onready var _title_label: Label = %TitleLabel
@onready var _current_location_label: Label = %CurrentLocationLabel
@onready var _body_host: Control = %BodyHost
@onready var _vertical_split: VBoxContainer = %VerticalSplit
@onready var _horizontal_split: HBoxContainer = %HorizontalSplit
@onready var _map_panel: PanelContainer = %MapPanel
@onready var _map_view: MapShapeView = %MapShapeView
@onready var _grid_view: GridMapViewScript = %GridMapView
@onready var _minimap_row: HBoxContainer = %MinimapRow
@onready var _grid_minimap: GridMapMinimap = %GridMapMinimap
@onready var _zoom_in_btn: Button = %ZoomInButton
@onready var _zoom_out_btn: Button = %ZoomOutButton
@onready var _key_nodes_scroll: ScrollContainer = %KeyNodesScroll
@onready var _key_nodes_bar: HBoxContainer = %KeyNodesBar
@onready var _content_scroll: ScrollContainer = %ContentScroll
@onready var _overview_label: RichTextLabel = %OverviewLabel
@onready var _info_cards_grid: GridContainer = %InfoCardsGrid
@onready var _adjacent_section: VBoxContainer = %AdjacentSection
@onready var _adjacent_chips: HBoxContainer = %AdjacentChips

var _is_horizontal := false
var _bar_key_nodes: Array = []
var _bar_region_id: String = ""
var _current_map_page: Dictionary = {}


func _ready() -> void:
	if _map_view:
		_map_view.region_selected.connect(_on_map_region_selected)
	if _grid_view:
		_grid_view.child_map_selected.connect(_on_child_map_selected)
		_grid_view.travel_cell_toggled.connect(_on_travel_cell_toggled)
		_grid_view.viewport_changed.connect(_sync_minimap)
	if _grid_minimap:
		_grid_minimap.viewport_center_changed.connect(_on_minimap_viewport_center_changed)
		_grid_minimap.viewport_drag_ended.connect(_sync_minimap)
	if _zoom_in_btn:
		UiStylesScript.apply_secondary_button(_zoom_in_btn)
		_zoom_in_btn.pressed.connect(_on_zoom_in_pressed)
	if _zoom_out_btn:
		UiStylesScript.apply_secondary_button(_zoom_out_btn)
		_zoom_out_btn.pressed.connect(_on_zoom_out_pressed)
	call_deferred("_apply_map_panel_chrome")
	call_deferred("_apply_responsive_layout")


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_apply_responsive_layout()


func show_region(
	region: Dictionary,
	_all_regions: Array,
	key_nodes: Array,
	_current_region_id: String,
	_current_key_node_id: String = "",
	location_path: String = "",
	_adjacent_region_ids: Array = [],
) -> void:
	_set_current_location_line(location_path)
	if region.is_empty():
		_title_label.text = "地图"
		_overview_label.visible = true
		_set_overview_bbcode(MapRegionDisplayScript.format_placeholder("请选择左侧已解锁区域查看详情。"))
		_clear_info_cards()
		_adjacent_section.visible = false
		_set_map_visual_visible(false)
		_bar_key_nodes = []
		_bar_region_id = ""
		_rebuild_key_nodes_bar([])
		_reset_scroll()
		return

	_title_label.text = str(region.get("name", "区域"))
	_overview_label.visible = false
	_rebuild_info_cards(region)
	_adjacent_section.visible = false
	var region_id := str(region.get("id", "")).strip_edges()
	var region_key_nodes := _key_nodes_for_region(key_nodes, region_id)
	_bar_region_id = region_id
	_bar_key_nodes = region_key_nodes
	_set_map_visual_visible(false)
	_rebuild_key_nodes_bar(region_key_nodes, "")
	_reset_scroll()


func show_map_page(
	map_page: Dictionary,
	location_path: String = "",
	current_key_node_id: String = "",
	region: Dictionary = {},
	highlight_cell: Vector2i = Vector2i(-1, -1),
) -> void:
	_set_current_location_line(location_path)
	if map_page.is_empty():
		_title_label.text = "地图"
		_set_map_visual_visible(false)
		_overview_label.visible = true
		_set_overview_bbcode(MapRegionDisplayScript.format_placeholder("暂无本地图数据。"))
		_clear_info_cards()
		_rebuild_key_nodes_bar([])
		_reset_scroll()
		return

	_title_label.text = str(map_page.get("name", "本地图"))
	_overview_label.visible = false
	if region.is_empty():
		_clear_info_cards()
	else:
		_rebuild_info_cards(region)
	_adjacent_section.visible = false
	_current_map_page = map_page.duplicate(true)
	_set_map_visual_visible(true)
	if _grid_view:
		_grid_view.clear_travel_selection()
		_grid_view.setup(_current_map_page, current_key_node_id, highlight_cell)
	call_deferred("_sync_minimap")
	_bar_key_nodes = []
	_bar_region_id = ""
	_rebuild_key_nodes_bar([])
	_reset_scroll()


func show_overview(
	map_structure: Dictionary,
	_all_regions: Array,
	_key_nodes: Array,
	_current_region_id: String,
	_current_key_node_id: String = "",
	location_path: String = "",
) -> void:
	_set_current_location_line(location_path)
	_title_label.text = "世界地图"
	var overview := str(map_structure.get("overview", "")).strip_edges()
	_overview_label.visible = true
	_set_overview_bbcode(MapRegionDisplayScript.format_overview(overview))
	_clear_info_cards()
	_adjacent_section.visible = false
	_current_map_page = {}
	_set_map_visual_visible(false)
	_bar_key_nodes = []
	_bar_region_id = ""
	_rebuild_key_nodes_bar([])
	_reset_scroll()


static func _resolve_bar_highlight_key(current_key_node_id: String, region_key_nodes: Array) -> String:
	var current_id := current_key_node_id.strip_edges()
	if not current_id.is_empty():
		return current_id
	if region_key_nodes.is_empty():
		return ""
	var first: Dictionary = region_key_nodes[0]
	var first_id := str(first.get("id", "")).strip_edges()
	if not first_id.is_empty():
		return first_id
	return MapShapeView.key_node_dedupe_key(first)


func _on_key_node_chip_pressed(node_id: String) -> void:
	if node_id.is_empty():
		return
	if _grid_view and _grid_view.visible and not _current_map_page.is_empty():
		_grid_view.setup(_current_map_page, node_id)
	elif _map_view:
		_map_view.set_highlight_key_node(node_id)
	_rebuild_key_nodes_bar(_bar_key_nodes, node_id)


func _on_child_map_selected(child_map_id: String) -> void:
	if not child_map_id.is_empty():
		child_map_selected.emit(child_map_id)


func _on_travel_cell_toggled(cell_data: Dictionary, active: bool) -> void:
	travel_cell_toggled.emit(cell_data, active)


func _set_map_visual_visible(show_grid: bool) -> void:
	if _map_panel:
		_map_panel.visible = show_grid
	if _map_view:
		_map_view.visible = false
	if _grid_view:
		_grid_view.visible = show_grid
	if _minimap_row:
		_minimap_row.visible = show_grid
	if _key_nodes_scroll:
		_key_nodes_scroll.visible = false


func _sync_minimap() -> void:
	if _grid_minimap == null or _grid_view == null or not _grid_view.visible:
		return
	_grid_minimap.update_snapshot(_grid_view.minimap_snapshot())


func _on_minimap_viewport_center_changed(center_x: float, center_y: float) -> void:
	if _grid_view:
		_grid_view.set_viewport_center(center_x, center_y)


func _on_zoom_in_pressed() -> void:
	if _grid_view and _grid_view.step_visible_n(-1):
		_sync_minimap()


func _on_zoom_out_pressed() -> void:
	if _grid_view and _grid_view.step_visible_n(1):
		_sync_minimap()


func _rebuild_key_nodes_bar(key_nodes: Array, current_key_node_id: String = "") -> void:
	if _key_nodes_bar == null or _key_nodes_scroll == null:
		return
	for child in _key_nodes_bar.get_children():
		child.queue_free()
	var nodes := MapShapeView.dedupe_key_nodes(key_nodes)
	if nodes.size() < 2:
		_key_nodes_scroll.visible = false
		return
	_key_nodes_scroll.visible = true
	_key_nodes_scroll.scroll_horizontal = 0
	var current_id := current_key_node_id.strip_edges()
	for raw in nodes:
		if not raw is Dictionary:
			continue
		var node: Dictionary = raw
		var name_text := str(node.get("name", "")).strip_edges()
		if name_text.is_empty():
			continue
		var node_id := str(node.get("id", "")).strip_edges()
		var chip_key := node_id if not node_id.is_empty() else MapShapeView.key_node_dedupe_key(node)
		var is_current := not current_id.is_empty() and chip_key == current_id
		var chip := _make_chip_button(name_text, is_current, _on_key_node_chip_pressed.bind(node_id))
		_key_nodes_bar.add_child(chip)


func _apply_map_panel_chrome() -> void:
	if _map_panel:
		UiStylesScript.apply_panel_surface(_map_panel)


func _make_chip_button(text: String, is_selected: bool, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(on_pressed)
	var accent := (
		DesignTokensScript.COLOR_CHIP_SELECTED
		if is_selected
		else DesignTokensScript.COLOR_CHIP_NEUTRAL
	)
	UiStylesScript.apply_chip_button(btn, is_selected, accent)
	return btn


func _set_overview_bbcode(bbcode: String) -> void:
	if _overview_label == null:
		return
	_overview_label.text = bbcode
	_overview_label.visible = not bbcode.is_empty()


static func _configure_rich_body(label: RichTextLabel) -> void:
	UiStylesScript.configure_rich_body(label)


static func _key_nodes_for_region(key_nodes: Array, region_id: String) -> Array:
	var rid := region_id.strip_edges()
	if rid.is_empty():
		return key_nodes
	var out: Array = []
	for raw in key_nodes:
		if raw is Dictionary and str(raw.get("region_id", "")).strip_edges() == rid:
			out.append(raw)
	return out


func _apply_responsive_layout() -> void:
	if _body_host == null or _vertical_split == null or _horizontal_split == null:
		return
	var want_horizontal := size.x >= WIDE_BREAKPOINT
	if want_horizontal != _is_horizontal:
		_is_horizontal = want_horizontal
		var target: BoxContainer
		if want_horizontal:
			target = _horizontal_split
		else:
			target = _vertical_split
		if _map_panel.get_parent() != target:
			_map_panel.reparent(target)
			_content_scroll.reparent(target)
			target.move_child(_map_panel, 0)
			target.move_child(_content_scroll, 1)
		_vertical_split.visible = not want_horizontal
		_horizontal_split.visible = want_horizontal
		_configure_split_child_flags(want_horizontal)
		if not want_horizontal:
			_info_cards_grid.columns = 2
		if _grid_view and _grid_view.visible:
			_grid_view.queue_redraw()
			_sync_minimap()
		elif _map_view:
			_map_view.queue_redraw()


func _configure_split_child_flags(horizontal: bool) -> void:
	_map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if horizontal:
		_map_panel.size_flags_stretch_ratio = 1.35
		_content_scroll.size_flags_stretch_ratio = 1.0
		_info_cards_grid.columns = 1
	else:
		_map_panel.size_flags_stretch_ratio = 1.0
		_content_scroll.size_flags_stretch_ratio = 1.0


func _on_map_region_selected(region_id: String) -> void:
	region_selected.emit(region_id)


func _rebuild_info_cards(region: Dictionary) -> void:
	_clear_info_cards()
	var has_cards := false
	for key in FIELD_KEYS:
		var val := str(region.get(key, "")).strip_edges()
		if val.is_empty():
			continue
		has_cards = true
		_info_cards_grid.add_child(_make_info_card(key, val))
	if not has_cards:
		_overview_label.visible = true
		_set_overview_bbcode(MapRegionDisplayScript.format_placeholder("暂无详细描述。"))


func _clear_info_cards() -> void:
	for child in _info_cards_grid.get_children():
		child.queue_free()


func _make_info_card(field_key: String, value: String) -> Control:
	var accent_color: Color = DesignTokensScript.MAP_FIELD_COLORS.get(
		field_key, DesignTokensScript.COLOR_BORDER
	)

	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 6)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var toggle_btn := Button.new()
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.custom_minimum_size = Vector2(22, 22)
	toggle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiStylesScript.apply_chip_button(toggle_btn, false, DesignTokensScript.COLOR_BORDER_SUBTLE)
	toggle_btn.add_theme_font_size_override("font_size", DesignTokensScript.FONT_CAPTION)

	var title := Label.new()
	title.text = _field_label(field_key)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiStylesScript.style_hint_label(title, "muted")

	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 10)
	body_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(4, 0)
	accent.size_flags_vertical = Control.SIZE_EXPAND_FILL
	accent.color = accent_color

	var body := RichTextLabel.new()
	_configure_rich_body(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.text = MapRegionDisplayScript.format_field_body(field_key, value)

	body_row.add_child(accent)
	body_row.add_child(body)

	var apply_expanded := func(is_expanded: bool) -> void:
		body_row.visible = is_expanded
		toggle_btn.text = EXPANDED_ICON if is_expanded else COLLAPSED_ICON

	apply_expanded.call(true)
	toggle_btn.pressed.connect(func() -> void:
		apply_expanded.call(not body_row.visible)
	)

	header_row.add_child(toggle_btn)
	header_row.add_child(title)
	block.add_child(header_row)
	block.add_child(body_row)
	return block


func _rebuild_adjacent_chips(adjacent_region_ids: Array, all_regions: Array) -> void:
	for child in _adjacent_chips.get_children():
		child.queue_free()
	if adjacent_region_ids.is_empty():
		_adjacent_section.visible = false
		return

	var name_by_id: Dictionary = {}
	for region in all_regions:
		if region is Dictionary:
			var rid := str(region.get("id", "")).strip_edges()
			if not rid.is_empty():
				name_by_id[rid] = str(region.get("name", rid))

	var has_chip := false
	var chip_accent := DesignTokensScript.COLOR_ACCENT
	for raw_id in adjacent_region_ids:
		var region_id := str(raw_id).strip_edges()
		if region_id.is_empty():
			continue
		has_chip = true
		var chip := _make_chip_button(
			str(name_by_id.get(region_id, region_id)),
			false,
			_on_adjacent_chip_pressed.bind(region_id),
		)
		UiStylesScript.apply_chip_button(chip, false, chip_accent)
		_adjacent_chips.add_child(chip)

	_adjacent_section.visible = has_chip


func _on_adjacent_chip_pressed(region_id: String) -> void:
	region_selected.emit(region_id)


func _reset_scroll() -> void:
	if _content_scroll == null:
		return
	_content_scroll.scroll_vertical = 0
	call_deferred("_deferred_reset_scroll")


func _deferred_reset_scroll() -> void:
	if _content_scroll:
		_content_scroll.scroll_vertical = 0


func _set_current_location_line(location_path: String) -> void:
	var path := location_path.strip_edges()
	if _current_location_label == null:
		return
	if path.is_empty():
		_current_location_label.visible = false
		_current_location_label.text = ""
	else:
		_current_location_label.visible = true
		_current_location_label.text = "当前位置：%s" % path


static func _field_label(key: String) -> String:
	match key:
		"location": return "位置"
		"terrain": return "地形"
		"climate": return "气候"
		"resources": return "资源"
		"hazards": return "危险"
		"access": return "进入"
		"settlements": return "聚落"
		_: return key
