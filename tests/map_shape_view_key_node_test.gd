## 地图同区域多标点布局与去重（`godot --headless -s tests/map_shape_view_key_node_test.gd`）
extends SceneTree


func _initialize() -> void:
	var failed := 0
	failed += _test_dedupe_by_id_and_name_region()
	failed += _test_three_nodes_distinct_layout()
	failed += _test_dots_outside_layout_circle()
	failed += _test_overview_detail_same_dot_positions()
	failed += _test_region_filter_reduces_count()
	if failed == 0:
		print("[OK] map_shape_view key_node tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_dedupe_by_id_and_name_region() -> int:
	var nodes := [
		{"id": "a", "name": "盘口", "region_id": "r1"},
		{"id": "a", "name": "重复", "region_id": "r1"},
		{"name": "茶楼", "region_id": "r1"},
		{"name": "茶楼", "region_id": "r1"},
	]
	var out := MapShapeView.dedupe_key_nodes(nodes)
	if out.size() != 2:
		push_error("dedupe: expected 2 nodes, got %d" % out.size())
		return 1
	return 0


func _test_three_nodes_distinct_layout() -> int:
	var center := Vector2(200, 150)
	var layout_radius := MapShapeView.KEY_NODE_LAYOUT_REGION_RADIUS
	var node_radius := 6.0
	var dot_positions: Array[Vector2] = []
	for i in 3:
		var layout := MapShapeView.compute_key_node_layout(
			center, layout_radius, i, 3, node_radius, false
		)
		var dot_pos: Vector2 = layout["dot_pos"]
		for prev in dot_positions:
			if dot_pos.distance_to(prev) < 12.0:
				push_error("layout: dot positions overlap at index %d" % i)
				return 1
		dot_positions.append(dot_pos)
	return 0


func _test_dots_outside_layout_circle() -> int:
	var center := Vector2(100, 100)
	var layout_radius := MapShapeView.KEY_NODE_LAYOUT_REGION_RADIUS
	for i in 3:
		var layout := MapShapeView.compute_key_node_layout(center, layout_radius, i, 3, 6.0, false)
		var dot_pos: Vector2 = layout["dot_pos"]
		if dot_pos.distance_to(center) <= layout_radius + 1.0:
			push_error("dot should sit outside layout region circle")
			return 1
	return 0


func _test_overview_detail_same_dot_positions() -> int:
	var center := Vector2(180, 160)
	var layout_radius := MapShapeView.KEY_NODE_LAYOUT_REGION_RADIUS
	var overview_pos: Array[Vector2] = []
	var detail_pos: Array[Vector2] = []
	for i in 3:
		var o := MapShapeView.compute_key_node_layout(center, layout_radius, i, 3, 6.0, false)
		var d := MapShapeView.compute_key_node_layout(center, layout_radius, i, 3, 6.0, true)
		overview_pos.append(o["dot_pos"])
		detail_pos.append(d["dot_pos"])
	for i in 3:
		if overview_pos[i].distance_to(detail_pos[i]) > 0.5:
			push_error("overview/detail dot mismatch at index %d" % i)
			return 1
	return 0


func _test_region_filter_reduces_count() -> int:
	var view := MapShapeView.new()
	view.set_size(Vector2(400, 300))
	var regions := [{"id": "r1", "name": "老城区"}, {"id": "r2", "name": "北区"}]
	var key_nodes := [
		{"id": "k1", "name": "盘口", "region_id": "r1"},
		{"id": "k2", "name": "码头", "region_id": "r1"},
		{"id": "k3", "name": "驿站", "region_id": "r2"},
	]
	view.setup(regions, key_nodes, "r1", "k1", "r1")
	if view._key_nodes.size() != 2:
		push_error("visible_region filter: expected 2 key_nodes, got %d" % view._key_nodes.size())
		view.free()
		return 1
	view.free()
	return 0
