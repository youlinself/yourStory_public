## map_pages 校验（`godot --headless -s tests/ai_response_parser_local_grid_test.gd`）
extends SceneTree


func _initialize() -> void:
	var failed := 0
	failed += _test_empty_map_pages_ok()
	failed += _test_valid_map_pages()
	failed += _test_partial_region_pages_ok()

	if failed == 0:
		print("[OK] ai_response_parser_local_grid tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_empty_map_pages_ok() -> int:
	var map := _base_map()
	if not AiResponseParser.validate_adventure_map_structure(map):
		push_error("map without map_pages should pass")
		return 1
	return 0


func _test_valid_map_pages() -> int:
	var map := _base_map()
	map["map_pages"] = [
		{
			"id": "map_region_a",
			"name": "A",
			"parent_type": "region",
			"parent_id": "region_a",
			"width": 10,
			"height": 10,
			"default_terrain": "plain",
			"terrain_types": ["plain", "forest"],
			"cell_marks": [{"x": 2, "y": 2, "type": "forest", "key_node_id": "node_1"}],
		},
		{
			"id": "map_region_b",
			"name": "B",
			"parent_type": "region",
			"parent_id": "region_b",
			"width": 8,
			"height": 8,
			"default_terrain": "plain",
			"terrain_types": ["plain"],
			"cell_marks": [],
		},
	]
	if not AiResponseParser.validate_adventure_map_structure(map):
		push_error("valid map_pages should pass")
		return 1
	return 0


func _test_partial_region_pages_ok() -> int:
	var map := _base_map()
	map["map_pages"] = [
		{
			"id": "map_region_b_only",
			"name": "B",
			"parent_type": "region",
			"parent_id": "region_b",
			"width": 10,
			"height": 10,
			"default_terrain": "plain",
			"terrain_types": ["plain"],
			"cell_marks": [],
		},
	]
	if not AiResponseParser.validate_adventure_map_structure(map):
		push_error("partial region map_pages should pass; merge will补全缺失页")
		return 1
	return 0


func _base_map() -> Dictionary:
	return {
		"overview": "test",
		"regions": [
			{"id": "region_a", "name": "A", "adjacent_region_ids": ["region_b"]},
			{"id": "region_b", "name": "B", "adjacent_region_ids": ["region_a"]},
		],
		"key_nodes": [
			{"id": "node_1", "name": "入口", "region_id": "region_a"},
			{"id": "node_2", "name": "大厅", "region_id": "region_a"},
		],
	}
