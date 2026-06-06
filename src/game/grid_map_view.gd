class_name GridMapView
extends Control

signal child_map_selected(child_map_id: String)
signal travel_cell_toggled(cell_data: Dictionary, active: bool)
signal viewport_changed()

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

const CELL_PADDING := 1.0
const MIN_CELL_PX := 8.0
const MAX_CELL_PX := 28.0
const MIN_VISIBLE_CELLS := 9
const MAX_VISIBLE_CELLS := 15
const LABEL_FONT_SIZE := 9

const TOOLTIP_PADDING := Vector2(8.0, 6.0)
const TOOLTIP_FONT_SIZE_TITLE := 11
const TOOLTIP_FONT_SIZE_BODY := 10

var _page: Dictionary = {}
var _cells: Array = []
var _width := 0
var _height := 0
var _highlight_key_node_id := ""
var _highlight_cell := Vector2i(-1, -1)
var _visible_n := MAX_VISIBLE_CELLS
var _viewport_center := Vector2.ZERO
var _cell_px := 12.0
var _grid_origin := Vector2.ZERO
var _view_square := Rect2()
var _hover_cell := Vector2i(-1, -1)
var _hover_cell_data: Dictionary = {}
var _hover_mouse_pos := Vector2.ZERO
var _selected_travel_cell := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


func setup(
	map_page: Dictionary,
	highlight_key_node_id: String = "",
	highlight_cell: Vector2i = Vector2i(-1, -1),
) -> void:
	_page = map_page.duplicate(true) if map_page is Dictionary else {}
	_highlight_key_node_id = highlight_key_node_id.strip_edges()
	_highlight_cell = highlight_cell
	_width = maxi(0, int(_page.get("width", 0)))
	_height = maxi(0, int(_page.get("height", 0)))
	var cells_val: Variant = _page.get("cells", [])
	_cells = cells_val if cells_val is Array else []
	_selected_travel_cell = Vector2i(-1, -1)
	var extents := square_n_extents(_width, _height)
	_visible_n = extents.y
	_viewport_center = _hero_grid_center()
	if _width > 0 and _height > 0:
		var avail := size - Vector2(CELL_PADDING * 2.0, CELL_PADDING * 2.0)
		var cell_px := cell_px_for_square_n(avail, _visible_n)
		_viewport_center = clamp_viewport_center_in_grid(
			_viewport_center, size, cell_px, _width, _height, _visible_n
		)
	_recompute_layout()
	queue_redraw()
	viewport_changed.emit()


func clear_travel_selection() -> void:
	if _selected_travel_cell.x < 0:
		return
	_selected_travel_cell = Vector2i(-1, -1)
	queue_redraw()


func step_visible_n(delta: int) -> bool:
	if _width <= 0 or _height <= 0:
		return false
	var extents := square_n_extents(_width, _height)
	if extents.x >= extents.y:
		return false
	var new_n := clampi(_visible_n + delta, extents.x, extents.y)
	if new_n == _visible_n:
		return false
	_visible_n = new_n
	_recenter_on_hero()
	_recompute_layout()
	queue_redraw()
	viewport_changed.emit()
	return true


func set_viewport_center(cx: float, cy: float) -> void:
	if _width <= 0 or _height <= 0:
		return
	_viewport_center = clamp_viewport_center_in_grid(
		Vector2(cx, cy), size, _cell_px, _width, _height, _visible_n
	)
	_recompute_layout()
	queue_redraw()
	viewport_changed.emit()


func minimap_snapshot() -> Dictionary:
	var rect := _current_viewport_grid_rect()
	return {
		"width": _width,
		"height": _height,
		"cells": _cells,
		"highlight_key_node_id": _highlight_key_node_id,
		"default_terrain": str(_page.get("default_terrain", "plain")).strip_edges(),
		"visible_n": _visible_n,
		"main_cell_px": _cell_px,
		"main_viewport_size": size,
		"viewport_x": rect.position.x,
		"viewport_y": rect.position.y,
		"viewport_w": rect.size.x,
		"viewport_h": rect.size.y,
	}


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recompute_layout()
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover_cell = Vector2i(-1, -1)
		_hover_cell_data = {}
		queue_redraw()


func _recenter_on_hero() -> void:
	if _width <= 0 or _height <= 0:
		return
	var avail := size - Vector2(CELL_PADDING * 2.0, CELL_PADDING * 2.0)
	var cell_px := cell_px_for_square_n(avail, _visible_n)
	_viewport_center = clamp_viewport_center_in_grid(
		_hero_grid_center(), size, cell_px, _width, _height, _visible_n
	)


func _hero_grid_center() -> Vector2:
	if _highlight_cell.x >= 0 and _highlight_cell.y >= 0:
		return Vector2(float(_highlight_cell.x) + 0.5, float(_highlight_cell.y) + 0.5)
	var hero := find_cell_with_key_node_id(_cells, _highlight_key_node_id)
	if not hero.is_empty():
		return Vector2(float(int(hero.get("x", 0))) + 0.5, float(int(hero.get("y", 0))) + 0.5)
	if _width > 0 and _height > 0:
		return Vector2(float(_width) * 0.5, float(_height) * 0.5)
	return Vector2.ZERO


func _recompute_layout() -> void:
	if _width <= 0 or _height <= 0:
		_cell_px = MIN_CELL_PX
		_grid_origin = Vector2.ZERO
		_view_square = Rect2()
		return
	var extents := square_n_extents(_width, _height)
	_visible_n = clampi(_visible_n, extents.x, extents.y)
	var avail := size - Vector2(CELL_PADDING * 2.0, CELL_PADDING * 2.0)
	_cell_px = cell_px_for_square_n(avail, _visible_n)
	_view_square = square_viewport_rect_local(size, _visible_n, _cell_px)
	var pan := pan_offset_for_viewport_center(
		size, _cell_px, _width, _height, _viewport_center.x, _viewport_center.y, _visible_n
	)
	var grid_w_px := _cell_px * float(_width)
	var grid_h_px := _cell_px * float(_height)
	var center_origin := _view_square.position + (_view_square.size - Vector2(grid_w_px, grid_h_px)) * 0.5
	_grid_origin = center_origin + pan


func _current_viewport_grid_rect() -> Rect2:
	return viewport_rect_for_center(
		_viewport_center.x, _viewport_center.y, size, _cell_px, _width, _height, _visible_n
	)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DesignTokensScript.COLOR_BG_ROOT)
	if _width <= 0 or _height <= 0 or _cells.is_empty():
		_draw_empty_hint()
		return
	var view_rect := _current_viewport_grid_rect()
	var x0 := maxi(0, int(floorf(view_rect.position.x)))
	var y0 := maxi(0, int(floorf(view_rect.position.y)))
	var x1 := mini(_width - 1, int(ceilf(view_rect.position.x + view_rect.size.x)) - 1)
	var y1 := mini(_height - 1, int(ceilf(view_rect.position.y + view_rect.size.y)) - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell_data := _cell_data_at(x, y)
			if cell_data.is_empty():
				continue
			_draw_cell(cell_data)
	var hero_mapped := _highlight_cell.x >= 0 and _highlight_cell.y >= 0
	if not hero_mapped:
		hero_mapped = (
			_highlight_key_node_id.is_empty()
			or not find_cell_with_key_node_id(_cells, _highlight_key_node_id).is_empty()
		)
	if not _highlight_key_node_id.is_empty() and not hero_mapped:
		_draw_unmapped_location_hint()
	if _hover_cell.x >= 0:
		var rect := _cell_rect(_hover_cell.x, _hover_cell.y)
		if _view_square.intersects(rect):
			draw_rect(rect, Color(1, 1, 1, 0.12), false, 1.5)
			if not _hover_cell_data.is_empty():
				_draw_cell_tooltip(_hover_cell_data, _hover_mouse_pos)


func _draw_empty_hint() -> void:
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(12, 24),
		"暂无格子地图",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.65, 0.65, 0.7),
	)


func _draw_cell(cell: Dictionary) -> bool:
	var x := int(cell.get("x", 0))
	var y := int(cell.get("y", 0))
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return false
	var rect := _cell_rect(x, y)
	if not _view_square.intersects(rect):
		return false
	var terrain := str(cell.get("type", "")).strip_edges()
	draw_rect(rect, terrain_color(terrain))
	var kn_id := str(cell.get("key_node_id", "")).strip_edges()
	var is_current := (
		(_highlight_cell.x == x and _highlight_cell.y == y)
		or (
			not _highlight_key_node_id.is_empty()
			and kn_id == _highlight_key_node_id
			and _highlight_cell.x < 0
		)
	)
	var is_blocked := _is_cell_blocked(cell)
	if is_blocked:
		draw_rect(rect, DesignTokensScript.MAP_BLOCKED_CELL_FILL)
	if is_current:
		draw_rect(rect, DesignTokensScript.MAP_HERO_CELL_FILL)
		draw_rect(rect.grow(-0.5), DesignTokensScript.MAP_HERO_CELL_STROKE, false, 2.0)
		draw_rect(rect.grow(-2.5), Color(1, 1, 1, 0.15), false, 1.0)
	if _selected_travel_cell.x == x and _selected_travel_cell.y == y:
		draw_rect(rect, DesignTokensScript.MAP_TRAVEL_CELL_FILL)
		draw_rect(rect.grow(-0.5), DesignTokensScript.MAP_TRAVEL_CELL_STROKE, false, 2.0)
	var label := str(cell.get("name", "")).strip_edges()
	if label.is_empty() and not kn_id.is_empty():
		label = kn_id
	if not label.is_empty() and rect.size.x >= 14:
		var font := ThemeDB.fallback_font
		var shown := label if label.length() <= 4 else label.substr(0, 3) + "…"
		draw_string(
			font,
			rect.position + Vector2(2, rect.size.y - 3),
			shown,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(rect.size.x - 2),
			LABEL_FONT_SIZE,
			Color(0.95, 0.95, 0.98),
		)
	var child_id := str(cell.get("child_map_id", "")).strip_edges()
	if not child_id.is_empty():
		var dot_r := minf(rect.size.x, rect.size.y) * 0.12
		draw_circle(rect.position + rect.size * 0.85, dot_r, DesignTokensScript.MAP_KEY_NODE)
	return is_current


func _draw_unmapped_location_hint() -> void:
	var font := ThemeDB.fallback_font
	var lines: PackedStringArray = PackedStringArray([
		"当前位置未映射到格子",
		"（cell_marks 缺少 key_node_id）",
	])
	var fs := 11
	var line_h := float(fs) + 4.0
	var max_w := 0.0
	for line in lines:
		var tw := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > max_w:
			max_w = tw
	var pad := Vector2(8.0, 6.0)
	var box_size := Vector2(max_w + pad.x * 2.0, line_h * float(lines.size()) + pad.y * 2.0)
	var box_pos := Vector2(size.x - box_size.x - 8.0, size.y - box_size.y - 8.0)
	var bg_rect := Rect2(box_pos, box_size)
	draw_rect(bg_rect, Color(0.08, 0.09, 0.12, 0.88))
	draw_rect(bg_rect, DesignTokensScript.COLOR_TEXT_HINT, false, 1.0)
	var text_x := box_pos.x + pad.x
	var cursor_y := box_pos.y + pad.y + float(fs)
	for line in lines:
		draw_string(
			font,
			Vector2(text_x, cursor_y),
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			fs,
			DesignTokensScript.COLOR_TEXT_HINT,
		)
		cursor_y += line_h


func _cell_rect(x: int, y: int) -> Rect2:
	return Rect2(
		_grid_origin + Vector2(float(x) * _cell_px, float(y) * _cell_px),
		Vector2(_cell_px - CELL_PADDING, _cell_px - CELL_PADDING),
	)


static func terrain_color(terrain: String) -> Color:
	match terrain:
		"plain", "平原":
			return Color(0.32, 0.38, 0.34, 1.0)
		"forest", "树林", "林":
			return Color(0.22, 0.42, 0.28, 1.0)
		"wall", "城墙", "墙":
			return Color(0.42, 0.42, 0.48, 1.0)
		"gate", "门":
			return Color(0.55, 0.48, 0.32, 1.0)
		"water", "水", "河":
			return Color(0.22, 0.36, 0.52, 1.0)
		"road", "路", "道":
			return Color(0.38, 0.36, 0.32, 1.0)
		"mountain", "山":
			return Color(0.36, 0.34, 0.38, 1.0)
		_:
			return Color(0.3, 0.32, 0.36, 1.0)


func _gui_input(event: InputEvent) -> void:
	if _width <= 0 or _height <= 0:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				if step_visible_n(-1):
					accept_event()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if step_visible_n(1):
					accept_event()
				return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var cell_pos := _cell_at_local(mb.position)
			if cell_pos.x >= 0:
				var cell_data := _cell_data_at(cell_pos.x, cell_pos.y)
				var child_id := str(cell_data.get("child_map_id", "")).strip_edges()
				if not child_id.is_empty():
					_try_select_child_map(cell_pos.x, cell_pos.y)
				else:
					_try_toggle_travel_cell(cell_pos.x, cell_pos.y)
	elif event is InputEventMouseMotion:
		_hover_mouse_pos = event.position
		_hover_cell = _cell_at_local(event.position)
		_hover_cell_data = _cell_data_at(_hover_cell.x, _hover_cell.y) if _hover_cell.x >= 0 else {}
		queue_redraw()


func _cell_at_local(local_pos: Vector2) -> Vector2i:
	if not _view_square.has_point(local_pos):
		return Vector2i(-1, -1)
	var rel := local_pos - _grid_origin
	if rel.x < 0 or rel.y < 0:
		return Vector2i(-1, -1)
	var x := int(rel.x / _cell_px)
	var y := int(rel.y / _cell_px)
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _cell_data_at(x: int, y: int) -> Dictionary:
	var found := cell_at_index(_cells, x, y, _width)
	if not found.is_empty():
		return found
	if x < 0 or y < 0 or x >= _width or y >= _height:
		return {}
	var default_terrain := str(_page.get("default_terrain", "plain")).strip_edges()
	if default_terrain.is_empty():
		default_terrain = "plain"
	return {
		"x": x,
		"y": y,
		"type": default_terrain,
		"name": "",
		"key_node_id": "",
		"child_map_id": "",
	}


func _draw_cell_tooltip(cell: Dictionary, mouse_pos: Vector2) -> void:
	var full_name := str(cell.get("name", "")).strip_edges()
	if full_name.is_empty():
		full_name = str(cell.get("key_node_id", "")).strip_edges()
	if full_name.is_empty():
		return

	var terrain := str(cell.get("type", "")).strip_edges()
	var child_id := str(cell.get("child_map_id", "")).strip_edges()
	var kn_id := str(cell.get("key_node_id", "")).strip_edges()

	var lines: Array[String] = []
	lines.append(full_name)
	if not terrain.is_empty():
		lines.append("地形：%s" % terrain)
	if not kn_id.is_empty() and kn_id != full_name:
		lines.append("节点：%s" % kn_id)
	if not child_id.is_empty():
		lines.append("→ 可进入子地图")

	var font := ThemeDB.fallback_font
	var title_fs := TOOLTIP_FONT_SIZE_TITLE
	var body_fs := TOOLTIP_FONT_SIZE_BODY
	var line_h_title := float(title_fs) + 4.0
	var line_h_body := float(body_fs) + 3.0

	var max_w := 0.0
	for i in lines.size():
		var fs := title_fs if i == 0 else body_fs
		var tw := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if tw > max_w:
			max_w = tw

	var total_h := line_h_title
	if lines.size() > 1:
		total_h += float(lines.size() - 1) * line_h_body + 2.0

	var tip_size := Vector2(max_w + TOOLTIP_PADDING.x * 2.0, total_h + TOOLTIP_PADDING.y * 2.0)
	var tip_pos := mouse_pos + Vector2(12.0, -tip_size.y - 4.0)
	tip_pos.x = clampf(tip_pos.x, 2.0, size.x - tip_size.x - 2.0)
	tip_pos.y = clampf(tip_pos.y, 2.0, size.y - tip_size.y - 2.0)

	var bg_rect := Rect2(tip_pos, tip_size)
	draw_rect(bg_rect, Color(0.08, 0.09, 0.12, 0.92))
	draw_rect(bg_rect, Color(0.45, 0.55, 0.75, 0.55), false, 1.0)

	var text_x := tip_pos.x + TOOLTIP_PADDING.x
	var cursor_y := tip_pos.y + TOOLTIP_PADDING.y + float(title_fs)
	draw_string(font, Vector2(text_x, cursor_y), lines[0],
		HORIZONTAL_ALIGNMENT_LEFT, -1, title_fs, Color(0.95, 0.96, 1.0))

	cursor_y += line_h_body + 2.0
	for i in range(1, lines.size()):
		var col := Color(0.62, 0.78, 0.95) if lines[i].begins_with("→") else Color(0.72, 0.75, 0.80)
		draw_string(font, Vector2(text_x, cursor_y), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, body_fs, col)
		cursor_y += line_h_body


func _try_select_child_map(x: int, y: int) -> void:
	for cell in _cells:
		if not cell is Dictionary:
			continue
		var c: Dictionary = cell
		if int(c.get("x", -1)) == x and int(c.get("y", -1)) == y:
			var child_id := str(c.get("child_map_id", "")).strip_edges()
			if not child_id.is_empty():
				child_map_selected.emit(child_id)
			return


func _try_toggle_travel_cell(x: int, y: int) -> void:
	var cell_data := _cell_data_at(x, y)
	if cell_data.is_empty():
		return
	if _is_cell_blocked(cell_data):
		return
	var was_selected := _selected_travel_cell.x == x and _selected_travel_cell.y == y
	if was_selected:
		_selected_travel_cell = Vector2i(-1, -1)
		travel_cell_toggled.emit(cell_data, false)
	else:
		_selected_travel_cell = Vector2i(x, y)
		travel_cell_toggled.emit(cell_data, true)
	queue_redraw()


func _is_cell_blocked(_cell: Dictionary) -> bool:
	return false


static func square_n_extents(map_w: int, map_h: int) -> Vector2i:
	var cap := mini(maxi(map_w, 0), maxi(map_h, 0))
	if cap <= 0:
		return Vector2i(0, 0)
	if cap < MIN_VISIBLE_CELLS:
		return Vector2i(cap, cap)
	return Vector2i(MIN_VISIBLE_CELLS, mini(MAX_VISIBLE_CELLS, cap))


static func cell_px_for_square_n(avail: Vector2, visible_n: int) -> float:
	if visible_n <= 0:
		return MIN_CELL_PX
	var px := minf(avail.x, avail.y) / float(visible_n)
	return clampf(px, MIN_CELL_PX, MAX_CELL_PX)


static func square_viewport_rect_local(viewport: Vector2, visible_n: int, cell_px: float) -> Rect2:
	var side := float(visible_n) * cell_px
	var sq_size := Vector2(side, side)
	return Rect2((viewport - sq_size) * 0.5, sq_size)


static func effective_visible_n(visible_n: int, map_w: int, map_h: int) -> float:
	return float(mini(visible_n, mini(maxi(map_w, 0), maxi(map_h, 0))))


static func clamp_pan_offset_square(
	pan: Vector2,
	view_square: Rect2,
	grid_w_px: float,
	grid_h_px: float,
) -> Vector2:
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w_px, grid_h_px)) * 0.5
	var origin := center_origin + pan
	var min_origin := view_square.position + view_square.size - Vector2(grid_w_px, grid_h_px)
	origin.x = clampf(origin.x, min_origin.x, view_square.position.x)
	origin.y = clampf(origin.y, min_origin.y, view_square.position.y)
	return origin - center_origin


static func pan_offset_for_viewport_center(
	viewport: Vector2,
	cell_px: float,
	map_w: int,
	map_h: int,
	center_x: float,
	center_y: float,
	visible_n: int,
) -> Vector2:
	var view_square := square_viewport_rect_local(viewport, visible_n, cell_px)
	var grid_w_px := cell_px * float(map_w)
	var grid_h_px := cell_px * float(map_h)
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w_px, grid_h_px)) * 0.5
	var view_center := view_square.position + view_square.size * 0.5
	var desired_origin := view_center - Vector2(center_x, center_y) * cell_px
	var pan := desired_origin - center_origin
	return clamp_pan_offset_square(pan, view_square, grid_w_px, grid_h_px)


static func clamp_viewport_center_in_grid(
	center: Vector2,
	viewport: Vector2,
	cell_px: float,
	map_w: int,
	map_h: int,
	visible_n: int,
) -> Vector2:
	var n := effective_visible_n(visible_n, map_w, map_h)
	var half := n * 0.5
	var min_x := half
	var min_y := half
	var max_x := maxf(half, float(map_w) - half)
	var max_y := maxf(half, float(map_h) - half)
	return Vector2(
		clampf(center.x, min_x, max_x),
		clampf(center.y, min_y, max_y),
	)


static func viewport_rect_in_grid(
	viewport: Vector2,
	grid_origin: Vector2,
	cell_px: float,
	map_w: int,
	map_h: int,
	visible_n: int,
) -> Rect2:
	var view_square := square_viewport_rect_local(viewport, visible_n, cell_px)
	var view_center := view_square.position + view_square.size * 0.5
	var center_grid := (view_center - grid_origin) / cell_px
	var n := effective_visible_n(visible_n, map_w, map_h)
	var half := n * 0.5
	var origin := Vector2(center_grid.x - half, center_grid.y - half)
	origin.x = clampf(origin.x, 0.0, maxf(0.0, float(map_w) - n))
	origin.y = clampf(origin.y, 0.0, maxf(0.0, float(map_h) - n))
	return Rect2(origin, Vector2(n, n))


static func viewport_rect_for_center(
	center_x: float,
	center_y: float,
	viewport: Vector2,
	cell_px: float,
	map_w: int,
	map_h: int,
	visible_n: int,
) -> Rect2:
	var clamped := clamp_viewport_center_in_grid(
		Vector2(center_x, center_y), viewport, cell_px, map_w, map_h, visible_n
	)
	var n := effective_visible_n(visible_n, map_w, map_h)
	return Rect2(clamped.x - n * 0.5, clamped.y - n * 0.5, n, n)


static func read_viewport_rect_from_snapshot(snapshot: Dictionary) -> Rect2:
	return Rect2(
		float(snapshot.get("viewport_x", 0.0)),
		float(snapshot.get("viewport_y", 0.0)),
		float(snapshot.get("viewport_w", 0.0)),
		float(snapshot.get("viewport_h", 0.0)),
	)


static func pan_direction_enabled(
	rect: Rect2,
	map_w: int,
	map_h: int,
	_square: bool,
) -> Dictionary:
	var n := rect.size.x
	var at_left := rect.position.x <= 0.01
	var at_top := rect.position.y <= 0.01
	var at_right := rect.position.x + n >= float(map_w) - 0.01
	var at_bottom := rect.position.y + n >= float(map_h) - 0.01
	return {
		"up": not at_top,
		"down": not at_bottom,
		"left": not at_left,
		"right": not at_right,
	}


static func format_travel_cell_label(cell_data: Dictionary, read_model: GameReadModel = null) -> String:
	var x := int(cell_data.get("x", -1))
	var y := int(cell_data.get("y", -1))
	var coord := ""
	if x >= 0 and y >= 0:
		coord = "（%d,%d）" % [x + 1, y + 1]

	var label := str(cell_data.get("name", "")).strip_edges()
	if label.is_empty():
		var kn_id := str(cell_data.get("key_node_id", "")).strip_edges()
		if not kn_id.is_empty() and read_model != null:
			var node: Dictionary = read_model.get_key_node(kn_id)
			label = str(node.get("name", kn_id)).strip_edges()
	if label.is_empty():
		var terrain := str(cell_data.get("type", "")).strip_edges()
		label = terrain if not terrain.is_empty() else "空地"

	if coord.is_empty():
		return label
	return "%s%s" % [label, coord]


static func find_cell_with_key_node_id(cells: Array, key_node_id: String) -> Dictionary:
	var target := key_node_id.strip_edges()
	if target.is_empty():
		return {}
	for raw in cells:
		if not raw is Dictionary:
			continue
		var c: Dictionary = raw
		if str(c.get("key_node_id", "")).strip_edges() == target:
			return c
	return {}


static func cell_at_index(cells: Array, x: int, y: int, width: int) -> Dictionary:
	for raw in cells:
		if raw is Dictionary:
			var c: Dictionary = raw
			if int(c.get("x", -1)) == x and int(c.get("y", -1)) == y:
				return c
	if width > 0:
		var idx := y * width + x
		if idx >= 0 and idx < cells.size() and cells[idx] is Dictionary:
			return cells[idx] as Dictionary
	return {}
