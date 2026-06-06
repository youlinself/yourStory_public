## GridMapView 正方形视窗（`godot --headless -s tests/grid_map_view_viewport_test.gd`）
extends SceneTree


func _initialize() -> void:
	var failed := 0
	failed += _test_square_n_extents_large_map()
	failed += _test_square_n_extents_small_maps()
	failed += _test_cell_px_for_square_n()
	failed += _test_square_viewport_rect_centered()
	failed += _test_large_map_default_viewport_is_square_15()
	failed += _test_large_map_min_zoom_viewport_is_square_9()
	failed += _test_wide_viewport_is_square_not_wide()
	failed += _test_small_map_has_zoom_range()
	failed += _test_tiny_map_no_zoom_range()
	failed += _test_pan_offset_square_clamped()
	failed += _test_clamp_viewport_center_in_grid_square()
	failed += _test_pan_offset_for_viewport_center_square()
	failed += _test_viewport_rect_for_center_matches_offset()
	failed += _test_read_viewport_rect_from_snapshot()
	failed += _test_pan_direction_at_top_edge()
	failed += _test_viewport_step_moves_one_cell()
	failed += _test_grid_delta_moves_one_cell()
	failed += _test_visible_n_changes_square_size()
	failed += _test_snapshot_viewport_is_square()
	failed += _test_find_cell_with_key_node_id()

	if failed == 0:
		print("[OK] grid_map_view_viewport tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_square_n_extents_large_map() -> int:
	var extents := GridMapView.square_n_extents(50, 50)
	if extents != Vector2i(9, 15):
		push_error("50x50 map should use 9..15 square window")
		return 1
	return 0


func _test_square_n_extents_small_maps() -> int:
	var map_10 := GridMapView.square_n_extents(10, 15)
	if map_10 != Vector2i(9, 10):
		push_error("10x15 map should use 9..10 square window")
		return 1
	var map_8 := GridMapView.square_n_extents(8, 8)
	if map_8 != Vector2i(8, 8):
		push_error("8x8 map should use 8..8 square window")
		return 1
	return 0


func _test_cell_px_for_square_n() -> int:
	var avail := Vector2(292, 292)
	var cell_px := GridMapView.cell_px_for_square_n(avail, 15)
	if not is_equal_approx(cell_px, 292.0 / 15.0):
		push_error("square cell px should use shorter viewport side / N")
		return 1
	return 0


func _test_square_viewport_rect_centered() -> int:
	var viewport := Vector2(400, 300)
	var cell_px := GridMapView.cell_px_for_square_n(
		viewport - Vector2(GridMapView.CELL_PADDING * 2.0, GridMapView.CELL_PADDING * 2.0),
		15,
	)
	var rect := GridMapView.square_viewport_rect_local(viewport, 15, cell_px)
	if not is_equal_approx(rect.size.x, rect.size.y):
		push_error("square viewport rect should be square in pixels")
		return 1
	if not is_equal_approx(rect.position.x, (viewport.x - rect.size.x) * 0.5):
		push_error("square viewport rect should be horizontally centered")
		return 1
	return 0


func _square_layout(
	viewport: Vector2,
	map_w: int,
	map_h: int,
	visible_n: int,
) -> Dictionary:
	var avail := viewport - Vector2(GridMapView.CELL_PADDING * 2.0, GridMapView.CELL_PADDING * 2.0)
	var cell_px := GridMapView.cell_px_for_square_n(avail, visible_n)
	var view_square := GridMapView.square_viewport_rect_local(viewport, visible_n, cell_px)
	var grid_w := cell_px * float(map_w)
	var grid_h := cell_px * float(map_h)
	var grid_origin := view_square.position + (view_square.size - Vector2(grid_w, grid_h)) * 0.5
	var rect := GridMapView.viewport_rect_in_grid(
		viewport, grid_origin, cell_px, map_w, map_h, visible_n
	)
	return {
		"cell_px": cell_px,
		"view_square": view_square,
		"grid_origin": grid_origin,
		"rect": rect,
	}


func _test_large_map_default_viewport_is_square_15() -> int:
	var layout := _square_layout(Vector2(400, 300), 50, 50, 15)
	var rect: Rect2 = layout["rect"]
	if not is_equal_approx(rect.size.x, rect.size.y):
		push_error("default viewport should be square")
		return 1
	if rect.size.x > 15.01:
		push_error("default viewport should be at most 15x15")
		return 1
	return 0


func _test_large_map_min_zoom_viewport_is_square_9() -> int:
	var layout := _square_layout(Vector2(400, 300), 50, 50, 9)
	var rect: Rect2 = layout["rect"]
	if not is_equal_approx(rect.size.x, 9.0) or not is_equal_approx(rect.size.y, 9.0):
		push_error("max zoom should show 9x9 square viewport")
		return 1
	return 0


func _test_wide_viewport_is_square_not_wide() -> int:
	var layout := _square_layout(Vector2(640, 200), 50, 50, 15)
	var rect: Rect2 = layout["rect"]
	if not is_equal_approx(rect.size.x, rect.size.y):
		push_error("wide viewport should still use square cell window")
		return 1
	if rect.size.x > 15.01:
		push_error("wide viewport should not exceed 15 cells")
		return 1
	var view_square: Rect2 = layout["view_square"]
	if view_square.position.x <= 1.0:
		push_error("wide viewport should leave side letterbox space")
		return 1
	return 0


func _test_small_map_has_zoom_range() -> int:
	var extents := GridMapView.square_n_extents(10, 10)
	if extents.y <= extents.x:
		push_error("10x10 map should allow zoom between 9 and 10")
		return 1
	return 0


func _test_tiny_map_no_zoom_range() -> int:
	var extents := GridMapView.square_n_extents(8, 8)
	if extents.x != 8 or extents.y != 8:
		push_error("8x8 map should have no zoom range")
		return 1
	return 0


func _test_pan_offset_square_clamped() -> int:
	var view_square := Rect2(Vector2.ZERO, Vector2(200, 200))
	var pan := GridMapView.clamp_pan_offset_square(
		Vector2(9999, -9999), view_square, 400, 400
	)
	if pan.x > 0.01 or pan.y < -0.01:
		push_error("square pan should clamp inside view square")
		return 1
	return 0


func _test_clamp_viewport_center_in_grid_square() -> int:
	var viewport := Vector2(200, 200)
	var cell_px := 20.0
	var center := GridMapView.clamp_viewport_center_in_grid(
		Vector2(1.0, 1.0), viewport, cell_px, 10, 8, 5
	)
	if center.x < 2.4 or center.y < 2.4:
		push_error("square viewport center should stay inside draggable bounds")
		return 1
	return 0


func _test_pan_offset_for_viewport_center_square() -> int:
	var viewport := Vector2(200, 200)
	var cell_px := 20.0
	var visible_n := 5
	var pan := GridMapView.pan_offset_for_viewport_center(
		viewport, cell_px, 10, 8, 7.0, 5.0, visible_n
	)
	var view_square := GridMapView.square_viewport_rect_local(viewport, visible_n, cell_px)
	var grid_w := cell_px * 10.0
	var grid_h := cell_px * 8.0
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w, grid_h)) * 0.5
	var grid_origin := center_origin + pan
	var view_center := view_square.position + view_square.size * 0.5
	var aligned := grid_origin + Vector2(7.0, 5.0) * cell_px
	if aligned.distance_to(view_center) > 1.0:
		push_error("square viewport center pan should align with square middle")
		return 1
	return 0


func _test_viewport_rect_for_center_matches_offset() -> int:
	var viewport := Vector2(200, 200)
	var cell_px := 20.0
	var visible_n := 5
	var rect := GridMapView.viewport_rect_for_center(
		7.0, 5.0, viewport, cell_px, 10, 8, visible_n
	)
	if not is_equal_approx(rect.size.x, rect.size.y):
		push_error("viewport rect for center should remain square")
		return 1
	var pan := GridMapView.pan_offset_for_viewport_center(
		viewport, cell_px, 10, 8, 7.0, 5.0, visible_n
	)
	var view_square := GridMapView.square_viewport_rect_local(viewport, visible_n, cell_px)
	var grid_w := cell_px * 10.0
	var grid_h := cell_px * 8.0
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w, grid_h)) * 0.5
	var expected := GridMapView.viewport_rect_in_grid(
		viewport,
		center_origin + pan,
		cell_px,
		10,
		8,
		visible_n,
	)
	if rect.position.distance_to(expected.position) > 0.01:
		push_error("viewport rect for center should match pan-derived rect")
		return 1
	return 0


func _test_read_viewport_rect_from_snapshot() -> int:
	var snapshot := {
		"viewport_x": 2.0,
		"viewport_y": 1.5,
		"viewport_w": 9.0,
		"viewport_h": 9.0,
	}
	var rect := GridMapView.read_viewport_rect_from_snapshot(snapshot)
	if not is_equal_approx(rect.size.x, 9.0) or not is_equal_approx(rect.size.y, 9.0):
		push_error("snapshot viewport fields should parse")
		return 1
	return 0


func _test_pan_direction_at_top_edge() -> int:
	var rect := Rect2(17.5, 0.0, 15.0, 15.0)
	var dirs := GridMapView.pan_direction_enabled(rect, 50, 50, true)
	if dirs["up"]:
		push_error("up pan should be disabled when viewport is at top edge")
		return 1
	if not dirs["down"] or not dirs["left"] or not dirs["right"]:
		push_error("other pan directions should remain enabled away from edges")
		return 1
	return 0


func _viewport_rect_after_step(
	viewport: Vector2,
	map_w: int,
	map_h: int,
	visible_n: int,
	grid_origin: Vector2,
	cell_px: float,
	direction: Vector2,
) -> Rect2:
	var rect := GridMapView.viewport_rect_in_grid(
		viewport, grid_origin, cell_px, map_w, map_h, visible_n
	)
	var n := float(mini(visible_n, mini(map_w, map_h)))
	var new_origin := rect.position + Vector2(-direction.x, -direction.y)
	new_origin.x = clampf(new_origin.x, 0.0, maxf(0.0, float(map_w) - n))
	new_origin.y = clampf(new_origin.y, 0.0, maxf(0.0, float(map_h) - n))
	var pan := GridMapView.pan_offset_for_viewport_center(
		viewport,
		cell_px,
		map_w,
		map_h,
		new_origin.x + n * 0.5,
		new_origin.y + n * 0.5,
		visible_n,
	)
	var view_square := GridMapView.square_viewport_rect_local(viewport, visible_n, cell_px)
	var grid_w := cell_px * float(map_w)
	var grid_h := cell_px * float(map_h)
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w, grid_h)) * 0.5
	return GridMapView.viewport_rect_in_grid(
		viewport,
		center_origin + pan,
		cell_px,
		map_w,
		map_h,
		visible_n,
	)


func _test_viewport_step_moves_one_cell() -> int:
	var viewport := Vector2(400, 300)
	var map_w := 50
	var map_h := 50
	var visible_n := 15
	var layout := _square_layout(viewport, map_w, map_h, visible_n)
	var cell_px: float = layout["cell_px"]
	var view_square: Rect2 = layout["view_square"]
	var grid_w := cell_px * float(map_w)
	var grid_h := cell_px * float(map_h)
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w, grid_h)) * 0.5
	var pan := GridMapView.pan_offset_for_viewport_center(
		viewport, cell_px, map_w, map_h, 25.0, 25.0, visible_n
	)
	var grid_origin := center_origin + pan
	var rect := GridMapView.viewport_rect_in_grid(
		viewport, grid_origin, cell_px, map_w, map_h, visible_n
	)
	var after_up := _viewport_rect_after_step(
		viewport, map_w, map_h, visible_n, grid_origin, cell_px, Vector2(0, 1)
	)
	if not is_equal_approx(after_up.position.y, rect.position.y - 1.0):
		push_error("up step should move viewport up by one cell")
		return 1
	var after_right := _viewport_rect_after_step(
		viewport, map_w, map_h, visible_n, grid_origin, cell_px, Vector2(-1, 0)
	)
	if not is_equal_approx(after_right.position.x, rect.position.x + 1.0):
		push_error("right step should move viewport right by one cell")
		return 1
	return 0


func _viewport_rect_after_grid_delta(
	viewport: Vector2,
	map_w: int,
	map_h: int,
	visible_n: int,
	grid_origin: Vector2,
	cell_px: float,
	delta: Vector2i,
) -> Rect2:
	var rect := GridMapView.viewport_rect_in_grid(
		viewport, grid_origin, cell_px, map_w, map_h, visible_n
	)
	var n := float(mini(visible_n, mini(map_w, map_h)))
	var new_origin := rect.position + Vector2(float(delta.x), float(delta.y))
	new_origin.x = clampf(new_origin.x, 0.0, maxf(0.0, float(map_w) - n))
	new_origin.y = clampf(new_origin.y, 0.0, maxf(0.0, float(map_h) - n))
	var pan := GridMapView.pan_offset_for_viewport_center(
		viewport,
		cell_px,
		map_w,
		map_h,
		new_origin.x + n * 0.5,
		new_origin.y + n * 0.5,
		visible_n,
	)
	var view_square := GridMapView.square_viewport_rect_local(viewport, visible_n, cell_px)
	var grid_w := cell_px * float(map_w)
	var grid_h := cell_px * float(map_h)
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w, grid_h)) * 0.5
	return GridMapView.viewport_rect_in_grid(
		viewport,
		center_origin + pan,
		cell_px,
		map_w,
		map_h,
		visible_n,
	)


func _test_grid_delta_moves_one_cell() -> int:
	var viewport := Vector2(400, 300)
	var map_w := 50
	var map_h := 50
	var visible_n := 15
	var layout := _square_layout(viewport, map_w, map_h, visible_n)
	var cell_px: float = layout["cell_px"]
	var view_square: Rect2 = layout["view_square"]
	var grid_w := cell_px * float(map_w)
	var grid_h := cell_px * float(map_h)
	var center_origin := view_square.position + (view_square.size - Vector2(grid_w, grid_h)) * 0.5
	var pan := GridMapView.pan_offset_for_viewport_center(
		viewport, cell_px, map_w, map_h, 25.0, 25.0, visible_n
	)
	var grid_origin := center_origin + pan
	var rect := GridMapView.viewport_rect_in_grid(
		viewport, grid_origin, cell_px, map_w, map_h, visible_n
	)
	var after_up := _viewport_rect_after_grid_delta(
		viewport, map_w, map_h, visible_n, grid_origin, cell_px, Vector2i(0, -1)
	)
	if not is_equal_approx(after_up.position.y, rect.position.y - 1.0):
		push_error("grid delta up should move viewport up by one cell")
		return 1
	var after_left := _viewport_rect_after_grid_delta(
		viewport, map_w, map_h, visible_n, grid_origin, cell_px, Vector2i(-1, 0)
	)
	if not is_equal_approx(after_left.position.x, rect.position.x - 1.0):
		push_error("grid delta left should move viewport left by one cell")
		return 1
	return 0


func _test_visible_n_changes_square_size() -> int:
	var viewport := Vector2(400, 300)
	var map_w := 50
	var map_h := 50
	var layout_15 := _square_layout(viewport, map_w, map_h, 15)
	var layout_9 := _square_layout(viewport, map_w, map_h, 9)
	var rect_15: Rect2 = layout_15["rect"]
	var rect_9: Rect2 = layout_9["rect"]
	if not is_equal_approx(rect_15.size.x, 15.0) or not is_equal_approx(rect_15.size.y, 15.0):
		push_error("visible_n 15 should produce 15x15 viewport rect")
		return 1
	if not is_equal_approx(rect_9.size.x, 9.0) or not is_equal_approx(rect_9.size.y, 9.0):
		push_error("visible_n 9 should produce 9x9 viewport rect")
		return 1
	var hero_center := Vector2(12.5, 9.5)
	var rect_9_hero := GridMapView.viewport_rect_for_center(
		hero_center.x, hero_center.y, viewport, layout_9["cell_px"], map_w, map_h, 9
	)
	var center_9_hero := rect_9_hero.position + rect_9_hero.size * 0.5
	if center_9_hero.distance_to(hero_center) > 0.05:
		push_error("zoom viewport should align with hero grid center")
		return 1
	return 0


func _test_snapshot_viewport_is_square() -> int:
	var viewport := Vector2(400, 300)
	for visible_n in [15, 12, 9]:
		var layout := _square_layout(viewport, 50, 50, visible_n)
		var rect: Rect2 = layout["rect"]
		if not is_equal_approx(rect.size.x, rect.size.y):
			push_error("snapshot viewport should stay square for visible_n=%d" % visible_n)
			return 1
		if not is_equal_approx(rect.size.x, float(visible_n)):
			push_error("snapshot viewport size should match visible_n=%d" % visible_n)
			return 1
	return 0


func _test_find_cell_with_key_node_id() -> int:
	var cells: Array = [
		{"x": 3, "y": 5, "key_node_id": "node_a", "name": "浅地"},
		{"x": 12, "y": 9, "key_node_id": "node_hero", "name": "集装箱贫民窟"},
	]
	var found := GridMapView.find_cell_with_key_node_id(cells, "node_hero")
	if found.is_empty():
		push_error("should find hero cell by key_node_id")
		return 1
	if int(found.get("x", -1)) != 12 or int(found.get("y", -1)) != 9:
		push_error("found cell should match hero coordinates")
		return 1
	var missing := GridMapView.find_cell_with_key_node_id(cells, "node_missing")
	if not missing.is_empty():
		push_error("missing key_node_id should return empty dict")
		return 1
	var empty_id := GridMapView.find_cell_with_key_node_id(cells, "")
	if not empty_id.is_empty():
		push_error("empty key_node_id should return empty dict")
		return 1
	var viewport := Vector2(400, 300)
	var map_w := 50
	var map_h := 50
	var visible_n := 15
	var layout := _square_layout(viewport, map_w, map_h, visible_n)
	var cell_px: float = layout["cell_px"]
	var far_center := Vector2(2.0, 2.0)
	var far_rect := GridMapView.viewport_rect_for_center(
		far_center.x, far_center.y, viewport, cell_px, map_w, map_h, visible_n
	)
	var hero_center := Vector2(12.5, 9.5)
	if far_rect.has_point(hero_center):
		push_error("test setup: viewport should not cover hero cell")
		return 1
	var off_viewport := GridMapView.find_cell_with_key_node_id(cells, "node_hero")
	if off_viewport.is_empty():
		push_error("hero lookup should work regardless of viewport position")
		return 1
	return 0
