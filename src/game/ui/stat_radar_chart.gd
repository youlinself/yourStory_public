class_name StatRadarChart
extends Control

const GRID_LEVELS: Array[float] = [0.25, 0.5, 0.75, 1.0]
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

const GRID_COLOR := DesignTokensScript.RADAR_GRID
const AXIS_COLOR := DesignTokensScript.RADAR_GRID
const FILL_COLOR := DesignTokensScript.RADAR_FILL
const STROKE_COLOR := DesignTokensScript.RADAR_STROKE
const POINT_COLOR := DesignTokensScript.RADAR_STROKE
const LABEL_COLOR := DesignTokensScript.COLOR_TEXT_SECONDARY
const LABEL_FONT_SIZE := 11
const LABEL_GAP := 8.0
const LABEL_DOWN_BIAS := 6.0
const PAD_TOP := 18.0
const PAD_BOTTOM := 18.0
const PAD_SIDE := 34.0

const LABEL_HOVER_PAD := Vector2(6.0, 4.0)
const VERTEX_HOVER_RADIUS := 14.0

var _values: PackedFloat32Array = PackedFloat32Array()
var _labels: PackedStringArray = PackedStringArray()
var _tooltips: PackedStringArray = PackedStringArray()
var _group_tooltip: String = ""
var _label_hover_rects: Array[Rect2] = []
var _vertex_hover_points: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_stats(rows: Array, group_tooltip: String = "") -> void:
	_values = PackedFloat32Array()
	_labels = PackedStringArray()
	_tooltips = PackedStringArray()
	_group_tooltip = group_tooltip.strip_edges()
	for row in rows:
		if not row is Dictionary:
			continue
		_labels.append(str(row.get("label", "")).strip_edges())
		_values.append(clampf(float(row.get("value", 0)), 0.0, 100.0))
		_tooltips.append(str(row.get("tooltip", "")).strip_edges())
	var count := _values.size()
	var dim := 188 if count <= 5 else 208
	custom_minimum_size = Vector2(dim, dim)
	_rebuild_hover_regions()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_rebuild_hover_regions()


func set_values(values: Array) -> void:
	var rows: Array = []
	for raw in values:
		rows.append({"label": "", "value": raw})
	set_stats(rows)


func _draw() -> void:
	if _values.is_empty():
		return
	var count := _values.size()
	if count < 3:
		return

	var metrics := _chart_metrics()
	var center: Vector2 = metrics["center"]
	var radius: float = metrics["radius"]

	for level in GRID_LEVELS:
		_draw_ring(center, radius * level, count, GRID_COLOR, 1.0)

	for i in count:
		var outer := _vertex_at(center, radius, i, count, 1.0)
		draw_line(center, outer, AXIS_COLOR, 1.0)

	var data_points: PackedVector2Array = PackedVector2Array()
	for i in count:
		var value_scale: float = _values[i] / 100.0
		data_points.append(_vertex_at(center, radius, i, count, value_scale))

	if data_points.size() >= 3:
		draw_colored_polygon(data_points, FILL_COLOR)
		var outline := data_points.duplicate()
		outline.append(data_points[0])
		draw_polyline(outline, STROKE_COLOR, 2.0)
		for point in data_points:
			draw_circle(point, 3.0, POINT_COLOR)

	_draw_axis_labels(center, radius, count)


func _get_tooltip(at_position: Vector2) -> String:
	for i in _label_hover_rects.size():
		if _label_hover_rects[i].has_point(at_position):
			if i < _tooltips.size() and not _tooltips[i].is_empty():
				return _tooltips[i]
	for i in _vertex_hover_points.size():
		if at_position.distance_to(_vertex_hover_points[i]) <= VERTEX_HOVER_RADIUS:
			if i < _tooltips.size() and not _tooltips[i].is_empty():
				return _tooltips[i]
	if not _group_tooltip.is_empty():
		return _group_tooltip
	return ""


func _rebuild_hover_regions() -> void:
	_label_hover_rects.clear()
	_vertex_hover_points = PackedVector2Array()
	if _values.is_empty() or _labels.is_empty():
		return
	var count := _values.size()
	if count < 3:
		return

	var metrics := _chart_metrics()
	var center: Vector2 = metrics["center"]
	var radius: float = metrics["radius"]
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	var label_radius: float = radius + LABEL_GAP
	for i in count:
		if i >= _labels.size():
			continue
		var text := _labels[i]
		if text.is_empty():
			continue
		var angle := -TAU * 0.25 + TAU * float(i) / float(count)
		var axis_pos := _vertex_at(center, label_radius, i, count, 1.0)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var draw_pos := _label_position(axis_pos, text_size, angle)
		var rect := Rect2(draw_pos, text_size)
		rect = rect.grow_individual(
			LABEL_HOVER_PAD.x,
			LABEL_HOVER_PAD.y,
			LABEL_HOVER_PAD.x,
			LABEL_HOVER_PAD.y,
		)
		_label_hover_rects.append(rect)
		_vertex_hover_points.append(_vertex_at(center, radius, i, count, 1.0))


func _chart_metrics() -> Dictionary:
	var inner_w: float = size.x - PAD_SIDE * 2.0
	var inner_h: float = size.y - PAD_TOP - PAD_BOTTOM
	var center := Vector2(size.x * 0.5, PAD_TOP + inner_h * 0.5)
	var radius: float = minf(inner_w, inner_h) * 0.42
	return {"center": center, "radius": radius}


func _draw_axis_labels(center: Vector2, radius: float, count: int) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var label_radius: float = radius + LABEL_GAP
	for i in count:
		if i >= _labels.size():
			continue
		var text := _labels[i]
		if text.is_empty():
			continue
		var angle := -TAU * 0.25 + TAU * float(i) / float(count)
		var axis_pos := _vertex_at(center, label_radius, i, count, 1.0)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
		var draw_pos := _label_position(axis_pos, text_size, angle)
		draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, LABEL_COLOR)


static func _label_position(axis_pos: Vector2, text_size: Vector2, angle: float) -> Vector2:
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	var pos: Vector2

	# 标签贴近顶点外侧，避免整体偏高
	if sin_a <= -0.82:
		pos = Vector2(axis_pos.x - text_size.x * 0.5, axis_pos.y - text_size.y * 0.15)
	elif sin_a >= 0.82:
		pos = Vector2(axis_pos.x - text_size.x * 0.5, axis_pos.y + 3.0)
	elif cos_a >= 0.55:
		pos = Vector2(axis_pos.x + 3.0, axis_pos.y - text_size.y * 0.32)
	elif cos_a <= -0.55:
		pos = Vector2(axis_pos.x - text_size.x - 3.0, axis_pos.y - text_size.y * 0.32)
	elif cos_a > 0.0 and sin_a < 0.0:
		pos = Vector2(axis_pos.x + 2.0, axis_pos.y - text_size.y * 0.2)
	elif cos_a < 0.0 and sin_a < 0.0:
		pos = Vector2(axis_pos.x - text_size.x - 2.0, axis_pos.y - text_size.y * 0.2)
	elif cos_a > 0.0:
		pos = Vector2(axis_pos.x + 2.0, axis_pos.y - text_size.y * 0.1)
	else:
		pos = Vector2(axis_pos.x - text_size.x - 2.0, axis_pos.y - text_size.y * 0.1)

	pos.y += LABEL_DOWN_BIAS
	return pos


func _vertex_at(center: Vector2, chart_radius: float, index: int, count: int, value_scale: float) -> Vector2:
	var angle := -TAU * 0.25 + TAU * float(index) / float(count)
	return center + Vector2(cos(angle), sin(angle)) * chart_radius * value_scale


func _draw_ring(center: Vector2, ring_radius: float, count: int, color: Color, width: float) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in count:
		points.append(_vertex_at(center, ring_radius, i, count, 1.0))
	points.append(points[0])
	draw_polyline(points, color, width)
