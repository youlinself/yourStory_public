class_name GridMapMinimap
extends Control

signal viewport_center_changed(center_x: float, center_y: float)
signal viewport_drag_ended()

const GridMapViewScript := preload("res://src/game/grid_map_view.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

const MINI_PADDING := 4.0
const MIN_MINI_CELL_PX := 2.0
const MINIMAP_MIN_SIZE := Vector2(140, 96)
const DRAG_THRESHOLD := 4.0

var _width := 0
var _height := 0
var _cells: Array = []
var _highlight_key_node_id := ""
var _default_terrain := "plain"
var _viewport_rect := Rect2()
var _main_cell_px := 1.0
var _main_visible_n := GridMapViewScript.MAX_VISIBLE_CELLS
var _main_viewport_size := Vector2.ZERO
var _mini_cell_px := 2.0
var _grid_origin := Vector2.ZERO

var _dragging_viewport := false
var _drag_active := false
var _press_pos := Vector2.ZERO
var _drag_grab_offset := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = MINIMAP_MIN_SIZE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func update_snapshot(snapshot: Dictionary) -> void:
	var new_width := maxi(0, int(snapshot.get("width", 0)))
	var new_height := maxi(0, int(snapshot.get("height", 0)))
	var new_highlight := str(snapshot.get("highlight_key_node_id", "")).strip_edges()
	var new_default_terrain := str(snapshot.get("default_terrain", "plain")).strip_edges()
	if new_default_terrain.is_empty():
		new_default_terrain = "plain"
	var new_main_cell_px := maxf(0.001, float(snapshot.get("main_cell_px", 1.0)))
	var new_visible_n := maxi(1, int(snapshot.get("visible_n", GridMapViewScript.MAX_VISIBLE_CELLS)))
	var viewport_size_val: Variant = snapshot.get("main_viewport_size", Vector2.ZERO)
	var new_viewport_size: Vector2 = viewport_size_val if viewport_size_val is Vector2 else Vector2.ZERO
	var new_viewport_rect := _viewport_rect
	if not _dragging_viewport:
		new_viewport_rect = GridMapViewScript.read_viewport_rect_from_snapshot(snapshot)
	var cells_val: Variant = snapshot.get("cells", [])
	var new_cells: Array = cells_val if cells_val is Array else []
	var needs_redraw: bool = (
		_dragging_viewport
		or new_width != _width
		or new_height != _height
		or new_highlight != _highlight_key_node_id
		or new_default_terrain != _default_terrain
		or not is_equal_approx(new_main_cell_px, _main_cell_px)
		or new_visible_n != _main_visible_n
		or new_viewport_size != _main_viewport_size
		or new_viewport_rect != _viewport_rect
		or new_cells != _cells
	)
	_width = new_width
	_height = new_height
	_cells = new_cells
	_highlight_key_node_id = new_highlight
	_default_terrain = new_default_terrain
	_main_cell_px = new_main_cell_px
	_main_visible_n = new_visible_n
	_main_viewport_size = new_viewport_size
	if not _dragging_viewport:
		_viewport_rect = new_viewport_rect
	if needs_redraw:
		_recompute_layout()
		queue_redraw()
	elif _width > 0 and _height > 0:
		_recompute_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_recompute_layout()
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_end_viewport_drag()


func _recompute_layout() -> void:
	if _width <= 0 or _height <= 0:
		_mini_cell_px = MIN_MINI_CELL_PX
		_grid_origin = Vector2.ZERO
		return
	var avail := size - Vector2(MINI_PADDING * 2.0, MINI_PADDING * 2.0)
	if avail.x <= 0.0 or avail.y <= 0.0:
		return
	var px_w := avail.x / float(_width)
	var px_h := avail.y / float(_height)
	_mini_cell_px = maxf(MIN_MINI_CELL_PX, minf(px_w, px_h))
	var grid_w := _mini_cell_px * float(_width)
	var grid_h := _mini_cell_px * float(_height)
	_grid_origin = Vector2(
		(size.x - grid_w) * 0.5,
		(size.y - grid_h) * 0.5,
	)


func _draw() -> void:
	if _width <= 0 or _height <= 0:
		_draw_empty_hint()
		return
	for y in _height:
		for x in _width:
			_draw_mini_cell(x, y)
	_draw_viewport_frame()
	draw_rect(Rect2(Vector2.ZERO, size), DesignTokensScript.COLOR_BORDER_SUBTLE, false, 1.0)


func _draw_empty_hint() -> void:
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(MINI_PADDING, size.y * 0.5),
		"小地图",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		DesignTokensScript.COLOR_TEXT_HINT,
	)


func _draw_mini_cell(x: int, y: int) -> void:
	var cell := _cell_data_at(x, y)
	var terrain := str(cell.get("type", _default_terrain)).strip_edges()
	var rect := _mini_cell_rect(x, y)
	draw_rect(rect, GridMapViewScript.terrain_color(terrain))
	var kn_id := str(cell.get("key_node_id", "")).strip_edges()
	if not _highlight_key_node_id.is_empty() and kn_id == _highlight_key_node_id:
		draw_rect(rect, DesignTokensScript.MAP_HERO_CELL_FILL)
		draw_rect(rect.grow(-0.5), DesignTokensScript.MAP_HERO_CELL_STROKE, false, 1.0)


func _draw_viewport_frame() -> void:
	if _viewport_rect.size == Vector2.ZERO:
		return
	var frame := _viewport_frame_screen_rect()
	var fill := Color(
		DesignTokensScript.COLOR_ACCENT.r,
		DesignTokensScript.COLOR_ACCENT.g,
		DesignTokensScript.COLOR_ACCENT.b,
		0.18,
	)
	draw_rect(frame, fill)
	draw_rect(frame, DesignTokensScript.COLOR_ACCENT, false, 1.5)


func _viewport_frame_screen_rect() -> Rect2:
	return Rect2(
		_grid_origin + _viewport_rect.position * _mini_cell_px,
		_viewport_rect.size * _mini_cell_px,
	)


func _mini_cell_rect(x: int, y: int) -> Rect2:
	return Rect2(
		_grid_origin + Vector2(float(x), float(y)) * _mini_cell_px,
		Vector2(_mini_cell_px - 0.5, _mini_cell_px - 0.5),
	)


func _cell_data_at(x: int, y: int) -> Dictionary:
	return GridMapViewScript.cell_at_index(_cells, x, y, _width)


func _can_drag_viewport() -> bool:
	if _width <= 0 or _height <= 0:
		return false
	return (
		_viewport_rect.size.x < float(_width) - 0.01
		or _viewport_rect.size.y < float(_height) - 0.01
	)


func _gui_input(event: InputEvent) -> void:
	if _width <= 0 or _height <= 0 or _mini_cell_px <= 0.0:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press_pos = mb.position
			_drag_active = false
			if _can_drag_viewport() and _viewport_frame_screen_rect().has_point(mb.position):
				_dragging_viewport = true
				var mouse_grid := _local_to_grid_float(mb.position)
				var view_center := _viewport_rect.position + _viewport_rect.size * 0.5
				_drag_grab_offset = mouse_grid - view_center
				accept_event()
				return
			_dragging_viewport = false
			var grid_pos := _local_to_grid_float(mb.position)
			if grid_pos.x >= 0.0:
				_apply_viewport_center_from_local(mb.position, false)
				accept_event()
			return
		if _dragging_viewport:
			var was_dragging := _drag_active
			_end_viewport_drag()
			if not was_dragging:
				_apply_viewport_center_from_local(_press_pos, false)
			viewport_drag_ended.emit()
			accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if not _dragging_viewport:
			return
		if not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		if not _drag_active and motion.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_drag_active = true
		if _drag_active:
			_apply_viewport_center_from_local(motion.position, true)
			accept_event()


func _end_viewport_drag() -> void:
	_dragging_viewport = false
	_drag_active = false


func _apply_viewport_center_from_local(local_pos: Vector2, from_drag_motion: bool) -> void:
	var grid_pos := _local_to_grid_float(local_pos)
	if grid_pos.x < 0.0:
		return
	var target_center := grid_pos
	if from_drag_motion and _drag_active:
		target_center = grid_pos - _drag_grab_offset
	var clamped := GridMapViewScript.clamp_viewport_center_in_grid(
		target_center,
		_main_viewport_size,
		_main_cell_px,
		_width,
		_height,
		_main_visible_n,
	)
	if _main_viewport_size != Vector2.ZERO:
		_viewport_rect = GridMapViewScript.viewport_rect_for_center(
			clamped.x,
			clamped.y,
			_main_viewport_size,
			_main_cell_px,
			_width,
			_height,
			_main_visible_n,
		)
	else:
		var n := float(mini(_main_visible_n, mini(_width, _height)))
		_viewport_rect = Rect2(clamped.x - n * 0.5, clamped.y - n * 0.5, n, n)
	queue_redraw()
	if _main_viewport_size == Vector2.ZERO:
		return
	viewport_center_changed.emit(clamped.x, clamped.y)


func _local_to_grid_float(local_pos: Vector2) -> Vector2:
	var rel := local_pos - _grid_origin
	if rel.x < 0.0 or rel.y < 0.0:
		return Vector2(-1.0, -1.0)
	var gx := rel.x / _mini_cell_px
	var gy := rel.y / _mini_cell_px
	if gx < 0.0 or gy < 0.0 or gx > float(_width) or gy > float(_height):
		return Vector2(-1.0, -1.0)
	return Vector2(gx, gy)
