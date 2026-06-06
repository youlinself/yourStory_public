class_name MapShapeView
extends Control

signal region_selected(region_id: String)

const DRAG_THRESHOLD := 4.0
const CONTENT_PADDING := 48.0
const LABEL_WIDTH := 80.0
const LABEL_HEIGHT := 18.0
const REGION_LABEL_FONT_SIZE := 13
const KEY_NODE_CHIP_FONT_SIZE := 12
## 标点轨道与角度在总览/详情间共用；总览仅显示区域名，详情另显示当前关键节点名
const KEY_NODE_ORBIT_SCALE := 1.05
const KEY_NODE_LAYOUT_REGION_RADIUS := 22.0
const KEY_NODE_LABEL_OUTSET_COMPACT := 18.0
const KEY_NODE_LABEL_OUTSET_DETAIL := 36.0
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

var _regions: Array[Dictionary] = []
var _key_nodes: Array[Dictionary] = []
var _all_key_nodes_for_layout: Array[Dictionary] = []
var _highlight_region_id: String = ""
var _highlight_key_node_id: String = ""
var _visible_region_id: String = ""
var _key_node_slot: Dictionary = {}
var _region_key_node_counts: Dictionary = {}
var _positions: Dictionary = {}
var _pulse_phase: float = 0.0
var _pan_offset: Vector2 = Vector2.ZERO
var _virtual_size: Vector2 = Vector2.ZERO
var _content_bounds: Rect2 = Rect2()
var _can_pan: bool = false

var _press_pos: Vector2 = Vector2.ZERO
var _press_pan: Vector2 = Vector2.ZERO
var _drag_active: bool = false
var _labels_layer: Control
var _empty_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_labels_layer = Control.new()
	_labels_layer.name = "LabelsLayer"
	_labels_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_labels_layer)
	_empty_label = Label.new()
	_empty_label.name = "EmptyHint"
	_empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_label.position = Vector2(16, 16)
	_empty_label.add_theme_font_size_override("font_size", 16)
	_empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_empty_label.visible = false
	add_child(_empty_label)
	set_process(true)


func setup(
	regions: Array,
	key_nodes: Array,
	highlight_region_id: String = "",
	highlight_key_node_id: String = "",
	visible_region_id: String = "",
) -> void:
	_regions.clear()
	_key_nodes.clear()
	_all_key_nodes_for_layout.clear()
	_key_node_slot.clear()
	_region_key_node_counts.clear()
	for r in regions:
		if r is Dictionary:
			_regions.append(r)
	_visible_region_id = visible_region_id.strip_edges()
	for n in dedupe_key_nodes(key_nodes):
		if not n is Dictionary:
			continue
		_all_key_nodes_for_layout.append(n)
		if _visible_region_id.is_empty():
			_key_nodes.append(n)
		elif str(n.get("region_id", "")).strip_edges() == _visible_region_id:
			_key_nodes.append(n)
	_highlight_region_id = highlight_region_id.strip_edges()
	_highlight_key_node_id = highlight_key_node_id.strip_edges()
	_build_key_node_slots()
	_compute_layout()
	_rebuild_labels()
	reset_view()


func set_highlight_key_node(key_node_id: String) -> void:
	_highlight_key_node_id = key_node_id.strip_edges()
	_rebuild_labels()
	queue_redraw()


func reset_view() -> void:
	_pan_offset = _center_pan_offset()
	_drag_active = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_sync_labels_pan()
	queue_redraw()


func _process(delta: float) -> void:
	var needs_pulse := not _highlight_region_id.is_empty()
	if not needs_pulse and not _visible_region_id.is_empty() and not _highlight_key_node_id.is_empty():
		needs_pulse = true
	if not needs_pulse:
		return
	_pulse_phase += delta * 3.0
	queue_redraw()


static func dedupe_key_nodes(key_nodes: Array) -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	for raw in key_nodes:
		if not raw is Dictionary:
			continue
		var node: Dictionary = raw
		var key := key_node_dedupe_key(node)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(node)
	return out


static func key_node_dedupe_key(node: Dictionary) -> String:
	var node_id := str(node.get("id", "")).strip_edges()
	if not node_id.is_empty():
		return "id:%s" % node_id
	var region_id := str(node.get("region_id", "")).strip_edges()
	var name_text := str(node.get("name", "")).strip_edges()
	return "nr:%s|%s" % [region_id, name_text]


static func compute_key_node_layout(
	region_center: Vector2,
	layout_region_radius: float,
	index: int,
	count: int,
	node_radius: float,
	detail_labels: bool = false,
) -> Dictionary:
	var angle := _key_node_angle(index, count)
	var outward := Vector2(cos(angle), sin(angle))
	var orbit_dist := layout_region_radius * KEY_NODE_ORBIT_SCALE
	var label_outset := KEY_NODE_LABEL_OUTSET_DETAIL if detail_labels else KEY_NODE_LABEL_OUTSET_COMPACT
	var dot_pos := region_center + outward * orbit_dist
	var label_anchor := dot_pos + outward * (node_radius + 8.0)
	var label_pos := dot_pos + outward * (node_radius + label_outset)
	return {
		"angle": angle,
		"outward": outward,
		"dot_pos": dot_pos,
		"label_anchor": label_anchor,
		"label_pos": label_pos,
	}


static func _key_node_angle(index: int, count: int) -> float:
	if count <= 1:
		return -PI * 0.5
	return -PI * 0.5 + TAU * float(index) / float(count)


static func _sort_key_nodes_for_layout(nodes: Array) -> Array:
	var sorted: Array = nodes.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var id_a := str(a.get("id", "")).strip_edges()
		var id_b := str(b.get("id", "")).strip_edges()
		if not id_a.is_empty() and not id_b.is_empty():
			return id_a < id_b
		if not id_a.is_empty():
			return true
		if not id_b.is_empty():
			return false
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return sorted


func _build_key_node_slots() -> void:
	_key_node_slot.clear()
	_region_key_node_counts.clear()
	var by_region: Dictionary = {}
	for node in _all_key_nodes_for_layout:
		var region_id := str(node.get("region_id", "")).strip_edges()
		if region_id.is_empty():
			continue
		if not by_region.has(region_id):
			by_region[region_id] = []
		(by_region[region_id] as Array).append(node)
	for region_id in by_region:
		var list: Array = _sort_key_nodes_for_layout(by_region[region_id])
		by_region[region_id] = list
		var count := list.size()
		_region_key_node_counts[region_id] = count
		for i in count:
			var node: Dictionary = list[i]
			_key_node_slot[key_node_dedupe_key(node)] = {
				"index": i,
				"count": count,
				"region_id": region_id,
			}


func _is_detail_label_mode(region_id: String) -> bool:
	return not _visible_region_id.is_empty() and region_id == _visible_region_id


func _key_node_layout_radius(_region_id: String) -> float:
	return KEY_NODE_LAYOUT_REGION_RADIUS


func _region_draw_radius(region_id: String) -> float:
	return 28.0 if region_id == _highlight_region_id else 22.0


func _is_key_node_highlighted(node: Dictionary) -> bool:
	if _highlight_key_node_id.is_empty():
		return false
	var node_id := str(node.get("id", "")).strip_edges()
	if not node_id.is_empty():
		return node_id == _highlight_key_node_id
	return key_node_dedupe_key(node) == _highlight_key_node_id


func _key_node_draw_radius(node: Dictionary) -> float:
	return 9.0 if _is_key_node_highlighted(node) else 6.0


func _base_layout_for_node(node: Dictionary) -> Dictionary:
	var region_id := str(node.get("region_id", "")).strip_edges()
	if region_id.is_empty() or not _positions.has(region_id):
		return {}
	var slot_key := key_node_dedupe_key(node)
	if not _key_node_slot.has(slot_key):
		return {}
	var slot: Dictionary = _key_node_slot[slot_key]
	var base: Vector2 = _positions[region_id]
	var layout_radius := _key_node_layout_radius(region_id)
	var node_radius := _key_node_draw_radius(node)
	var detail_labels := _is_detail_label_mode(region_id)
	var layout := compute_key_node_layout(
		base,
		layout_radius,
		int(slot.get("index", 0)),
		int(slot.get("count", 1)),
		node_radius,
		detail_labels,
	)
	layout["node_radius"] = node_radius
	layout["region_id"] = region_id
	layout["region_center"] = base
	layout["region_radius"] = layout_radius
	return layout


func _layout_for_node(node: Dictionary) -> Dictionary:
	var layout := _base_layout_for_node(node)
	if layout.is_empty():
		return layout
	if _should_show_key_node_label(node):
		layout["label_pos"] = _adjust_highlight_label_pos(node, layout)
	return layout


func _should_show_key_node_label(node: Dictionary) -> bool:
	if _visible_region_id.is_empty():
		return false
	return _is_key_node_highlighted(node)


func _adjust_highlight_label_pos(node: Dictionary, layout: Dictionary) -> Vector2:
	var label_pos: Vector2 = layout["label_pos"]
	var region_center: Vector2 = layout["region_center"]
	var region_radius: float = layout["region_radius"]
	var outward: Vector2 = layout["outward"]
	var name_text := str(node.get("name", "")).strip_edges()
	var font := _map_font()
	if font == null:
		return label_pos
	var text_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, KEY_NODE_CHIP_FONT_SIZE)
	var tangent := Vector2(-outward.y, outward.x)
	for _pass in 2:
		var label_center := label_pos + text_size * 0.5
		if label_center.distance_to(region_center) < region_radius + text_size.length() * 0.35:
			label_pos += outward * 6.0
		for other in _key_nodes:
			if other == node:
				continue
			var other_layout := _base_layout_for_node(other)
			if other_layout.is_empty():
				continue
			var other_anchor: Vector2 = other_layout["label_anchor"]
			if label_pos.distance_to(other_anchor) < text_size.x * 0.6:
				label_pos += tangent * 8.0
	return label_pos


func _map_font() -> Font:
	var font := get_theme_font(&"font", "Label") as Font
	if font == null:
		font = ThemeDB.fallback_font
	return font


func _compute_layout() -> void:
	_positions.clear()
	var count := _regions.size()
	if count == 0:
		_virtual_size = size
		_content_bounds = Rect2()
		_can_pan = false
		return

	var viewport := size
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		viewport = Vector2(320, 240)

	var radius := minf(viewport.x, viewport.y) * 0.32
	if count > 1:
		radius = maxf(radius, 36.0 * float(count) * 0.55)
	var center := viewport * 0.5
	for i in count:
		var angle := (TAU * float(i) / float(count)) - PI * 0.5
		var region_id := str(_regions[i].get("id", ""))
		_positions[region_id] = center + Vector2(cos(angle), sin(angle)) * radius

	_content_bounds = _compute_content_bounds()
	_virtual_size = Vector2(
		maxf(viewport.x, _content_bounds.size.x + CONTENT_PADDING * 2.0),
		maxf(viewport.y, _content_bounds.size.y + CONTENT_PADDING * 2.0),
	)
	_can_pan = _content_bounds.size.x > viewport.x or _content_bounds.size.y > viewport.y


func _compute_content_bounds() -> Rect2:
	if _positions.is_empty():
		return Rect2()

	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for region in _regions:
		var region_id := str(region.get("id", "")).strip_edges()
		if not _positions.has(region_id):
			continue
		var pos: Vector2 = _positions[region_id]
		var node_radius := _region_draw_radius(region_id)
		min_pos.x = minf(min_pos.x, pos.x - node_radius - 40.0)
		min_pos.y = minf(min_pos.y, pos.y - node_radius - 8.0)
		max_pos.x = maxf(max_pos.x, pos.x + node_radius + LABEL_WIDTH)
		max_pos.y = maxf(max_pos.y, pos.y + node_radius + LABEL_HEIGHT + 18.0)

	for node in _key_nodes:
		var layout := _layout_for_node(node)
		if layout.is_empty():
			continue
		var dot_pos: Vector2 = layout["dot_pos"]
		var kn_radius: float = layout["node_radius"]
		min_pos.x = minf(min_pos.x, dot_pos.x - kn_radius)
		min_pos.y = minf(min_pos.y, dot_pos.y - kn_radius)
		max_pos.x = maxf(max_pos.x, dot_pos.x + kn_radius)
		max_pos.y = maxf(max_pos.y, dot_pos.y + kn_radius)
		if _should_show_key_node_label(node):
			var label_pos: Vector2 = layout["label_pos"]
			var name_text := str(node.get("name", ""))
			var label_width := maxf(60.0, float(name_text.length()) * 13.0)
			min_pos.x = minf(min_pos.x, label_pos.x)
			min_pos.y = minf(min_pos.y, label_pos.y)
			max_pos.x = maxf(max_pos.x, label_pos.x + label_width)
			max_pos.y = maxf(max_pos.y, label_pos.y + LABEL_HEIGHT + 8.0)

	if min_pos.x == INF:
		return Rect2()

	return Rect2(min_pos, max_pos - min_pos)


func _center_pan_offset() -> Vector2:
	if size.x <= 0.0 or size.y <= 0.0 or _content_bounds.size == Vector2.ZERO:
		return Vector2.ZERO
	var content_center := _content_bounds.get_center()
	var view_center := size * 0.5
	return view_center - content_center


func _clamp_pan() -> void:
	if not _can_pan or _content_bounds.size == Vector2.ZERO:
		_pan_offset = _center_pan_offset()
		return

	var min_offset := size - (_content_bounds.position + _content_bounds.size)
	var max_offset := -_content_bounds.position
	_pan_offset.x = clampf(_pan_offset.x, min_offset.x, max_offset.x)
	_pan_offset.y = clampf(_pan_offset.y, min_offset.y, max_offset.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_compute_layout()
		_clamp_pan()
		_rebuild_labels()
		_sync_labels_pan()
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_pos = mb.position
			_press_pan = _pan_offset
			_drag_active = false
			return

		if _drag_active:
			_drag_active = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			accept_event()
			return
		_try_select_region(mb.position)
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		if not _can_pan:
			return
		if not _drag_active and motion.position.distance_to(_press_pos) <= DRAG_THRESHOLD:
			return
		_drag_active = true
		mouse_default_cursor_shape = Control.CURSOR_MOVE
		_pan_offset = _press_pan + (motion.position - _press_pos)
		_clamp_pan()
		_sync_labels_pan()
		queue_redraw()
		accept_event()


func _try_select_region(local_pos: Vector2) -> void:
	var world_pos := local_pos - _pan_offset
	for region in _regions:
		var region_id := str(region.get("id", "")).strip_edges()
		if region_id.is_empty() or not _positions.has(region_id):
			continue
		var pos: Vector2 = _positions[region_id]
		var is_current := region_id == _highlight_region_id
		var hit_radius := 36.0 if is_current else 30.0
		if world_pos.distance_to(pos) <= hit_radius:
			region_selected.emit(region_id)
			accept_event()
			return


func _draw() -> void:
	if _positions.is_empty() and not _regions.is_empty():
		_compute_layout()
	_sync_labels_pan()
	if _regions.is_empty():
		return

	draw_set_transform(_pan_offset, 0.0, Vector2.ONE)
	_draw_region_links()
	for region in _regions:
		_draw_region_node(region)
	for node in _key_nodes:
		_draw_key_node_leader(node)
		_draw_key_node(node)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_key_node_leader(node: Dictionary) -> void:
	if not _should_show_key_node_label(node):
		return
	var layout := _layout_for_node(node)
	if layout.is_empty():
		return
	var dot_pos: Vector2 = layout["dot_pos"]
	var label_anchor: Vector2 = layout["label_anchor"]
	draw_line(dot_pos, label_anchor, DesignTokensScript.MAP_LEADER, 1.0)


func _sync_labels_pan() -> void:
	if _labels_layer:
		_labels_layer.position = _pan_offset


func _rebuild_labels() -> void:
	if _labels_layer == null:
		return
	for child in _labels_layer.get_children():
		_labels_layer.remove_child(child)
		child.free()

	var show_empty := _regions.is_empty()
	if _empty_label:
		_empty_label.visible = show_empty
		_empty_label.text = "暂无地图数据" if show_empty else ""
	if show_empty:
		return

	for region in _regions:
		var region_id := str(region.get("id", ""))
		if not _positions.has(region_id):
			continue
		var pos: Vector2 = _positions[region_id]
		var radius := _region_draw_radius(region_id)
		var name_text := str(region.get("name", region_id))
		var label := _make_map_label(
			name_text,
			REGION_LABEL_FONT_SIZE,
			Color(0.92, 0.92, 0.95),
			pos + Vector2(-40, radius + 10),
			LABEL_WIDTH,
		)
		_labels_layer.add_child(label)

	for node in _key_nodes:
		if not _should_show_key_node_label(node):
			continue
		var layout := _layout_for_node(node)
		if layout.is_empty():
			continue
		var is_current := _is_key_node_highlighted(node)
		var name_text := str(node.get("name", "")).strip_edges()
		if name_text.is_empty():
			continue
		var name_color := Color(0.78, 0.98, 0.82) if is_current else Color(0.9, 0.82, 0.55)
		var chip := _make_key_node_chip_label(name_text, name_color, layout["label_pos"])
		_labels_layer.add_child(chip)


func _make_map_label(
	text: String,
	font_size: int,
	color: Color,
	world_pos: Vector2,
	max_width: float = -1,
) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.position = world_pos
	if max_width > 0.0:
		label.custom_minimum_size.x = max_width
		label.size.x = max_width
	return label


func _make_key_node_chip_label(text: String, color: Color, world_pos: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = world_pos
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.92)
	style.border_color = Color(color.r, color.g, color.b, 0.75)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", KEY_NODE_CHIP_FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	panel.add_child(label)
	return panel


func _build_adjacency_edges() -> Array:
	var valid_ids: Dictionary = {}
	for region in _regions:
		var id_val := str(region.get("id", "")).strip_edges()
		if not id_val.is_empty():
			valid_ids[id_val] = true

	var edges: Dictionary = {}
	var has_any_adjacency := false
	for region in _regions:
		var a_id := str(region.get("id", "")).strip_edges()
		if a_id.is_empty():
			continue
		var raw_adj: Variant = region.get("adjacent_region_ids", [])
		if raw_adj is Array and not (raw_adj as Array).is_empty():
			has_any_adjacency = true
		if not raw_adj is Array:
			continue
		for neighbor in raw_adj:
			var b_id := str(neighbor).strip_edges()
			if b_id.is_empty() or a_id == b_id or not valid_ids.has(b_id):
				continue
			var edge_key := a_id + "|" + b_id if a_id < b_id else b_id + "|" + a_id
			if not edges.has(edge_key):
				edges[edge_key] = {"a": a_id if a_id < b_id else b_id, "b": b_id if a_id < b_id else a_id}

	if not has_any_adjacency:
		return []

	var out: Array = []
	for edge_key in edges:
		out.append(edges[edge_key])
	return out


func _draw_region_links() -> void:
	var edges := _build_adjacency_edges()
	for edge in edges:
		if not edge is Dictionary:
			continue
		var a_id: String = str(edge.get("a", ""))
		var b_id: String = str(edge.get("b", ""))
		if not _positions.has(a_id) or not _positions.has(b_id):
			continue
		var line_color := DesignTokensScript.MAP_LINK
		var line_width := 1.5
		if a_id == _highlight_region_id or b_id == _highlight_region_id:
			line_color = DesignTokensScript.MAP_LINK_HIGHLIGHT
			line_width = 2.5
		draw_line(_positions[a_id], _positions[b_id], line_color, line_width)


func _draw_region_node(region: Dictionary) -> void:
	var region_id := str(region.get("id", ""))
	if not _positions.has(region_id):
		return
	var pos: Vector2 = _positions[region_id]
	var is_current := region_id == _highlight_region_id
	var is_visible := not _visible_region_id.is_empty() and region_id == _visible_region_id
	var fill := (
		DesignTokensScript.MAP_REGION_CURRENT
		if is_current
		else DesignTokensScript.MAP_REGION_FILL
	)
	if is_visible and not is_current:
		fill = fill.lerp(DesignTokensScript.MAP_REGION_CURRENT, 0.35)
	var radius := _region_draw_radius(region_id)
	if is_current:
		var pulse_radius := radius + 8.0 + sin(_pulse_phase) * 4.0
		draw_arc(pos, pulse_radius, 0, TAU, 32, DesignTokensScript.MAP_REGION_PULSE, 2.5)
	draw_circle(pos, radius, fill)
	var stroke_w := 2.5 if is_current else 1.75
	draw_arc(pos, radius, 0, TAU, 32, DesignTokensScript.MAP_REGION_STROKE, stroke_w)


func _draw_key_node(node: Dictionary) -> void:
	var layout := _layout_for_node(node)
	if layout.is_empty():
		return
	var is_current := _is_key_node_highlighted(node)
	var pos: Vector2 = layout["dot_pos"]
	var radius: float = layout["node_radius"]
	var fill := (
		DesignTokensScript.MAP_KEY_NODE_CURRENT
		if is_current
		else DesignTokensScript.MAP_KEY_NODE
	)
	if is_current:
		draw_arc(pos, radius + 5.0, 0, TAU, 32, DesignTokensScript.MAP_KEY_NODE_PULSE, 2.5)
	draw_circle(pos, radius, fill)
	draw_arc(pos, radius, 0, TAU, 24, Color(0.96, 0.94, 0.88), 1.5 if is_current else 1.0)
