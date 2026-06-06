## 阶段 3 微步骤 parser（`godot --headless -s tests/world_build_micro_parser_test.gd`）
extends SceneTree

const LocalGridBuilderScript := preload("res://src/novel_config/local_grid_builder.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_map_skeleton_requires_overview()
	failed += _test_region_map_page_key_node_binding()

	if failed == 0:
		print("[OK] world_build_micro_parser tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_map_skeleton_requires_overview() -> int:
	var map := _sample_map()
	map.erase("overview")
	if AiResponseParser.validate_map_skeleton(map):
		push_error("skeleton without overview should fail")
		return 1
	return 0


func _test_region_map_page_key_node_binding() -> int:
	var skeleton := _sample_map()
	var page := LocalGridBuilderScript.build_map_page({
		"id": "map_region_a",
		"name": "A",
		"parent_type": "region",
		"parent_id": "region_a",
		"width": 10,
		"height": 10,
		"default_terrain": "plain",
		"terrain_types": ["plain"],
		"cell_marks": [
			{"x": 1, "y": 1, "type": "plain", "key_node_id": "node_1"},
			{"x": 2, "y": 2, "type": "plain", "key_node_id": "node_2"},
		],
	})
	if not AiResponseParser.validate_region_map_page(skeleton, page, "region_a"):
		push_error("valid region page with key_node marks should pass")
		return 1
	var bad_page := page.duplicate(true)
	var marks: Array = (bad_page.get("cell_marks", []) as Array).duplicate(true)
	marks.erase_at(1)
	bad_page["cell_marks"] = marks
	if AiResponseParser.validate_region_map_page(skeleton, bad_page, "region_a"):
		push_error("missing key_node binding should fail")
		return 1
	return 0


func _sample_map() -> Dictionary:
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
