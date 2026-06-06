## LocalGridBuilder（`godot --headless -s tests/local_grid_builder_test.gd`）
extends SceneTree

const LocalGridBuilderScript := preload("res://src/novel_config/local_grid_builder.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_build_cells_default_fill()
	failed += _test_array_mark_format()
	failed += _test_normalize_map_structure()
	failed += _test_validate_skips_invalid_marks()
	failed += _test_validate_map_page_spec()
	failed += _test_sparse_cells_normalized()
	failed += _test_assign_key_node_cell()

	if failed == 0:
		print("[OK] local_grid_builder tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_build_cells_default_fill() -> int:
	var cells := LocalGridBuilderScript.build_cells(3, 2, "plain", [])
	if cells.size() != 6:
		push_error("expected 6 cells")
		return 1
	if str(cells[0].get("type", "")) != "plain":
		push_error("default terrain")
		return 1
	return 0


func _test_array_mark_format() -> int:
	var mark := LocalGridBuilderScript.parse_cell_mark([1, 0, "forest", "古井"])
	if str(mark.get("type", "")) != "forest" or str(mark.get("name", "")) != "古井":
		push_error("array mark parse")
		return 1
	var cells := LocalGridBuilderScript.build_cells(
		3,
		3,
		"plain",
		[mark, {"x": 2, "y": 2, "type": "gate", "child_map_id": "map_inner"}],
	)
	var c10: Dictionary = LocalGridBuilderScript.cell_at_index(cells, 1, 0, 3)
	if str(c10.get("type", "")) != "forest":
		push_error("mark applied at 1,0")
		return 1
	var c22: Dictionary = LocalGridBuilderScript.cell_at_index(cells, 2, 2, 3)
	if str(c22.get("child_map_id", "")) != "map_inner":
		push_error("child_map_id")
		return 1
	return 0


func _test_normalize_map_structure() -> int:
	var map := {
		"overview": "o",
		"regions": [{"id": "r1", "name": "R1", "adjacent_region_ids": []}],
		"key_nodes": [],
		"map_pages": [
			{
				"id": "map_r1",
				"name": "R1",
				"parent_type": "region",
				"parent_id": "r1",
				"width": 5,
				"height": 5,
				"default_terrain": "plain",
				"terrain_types": ["plain", "forest"],
				"cell_marks": [{"x": 0, "y": 0, "type": "forest"}],
			},
		],
	}
	var out := LocalGridBuilderScript.normalize_map_structure(map)
	var pages: Array = out.get("map_pages", [])
	if pages.is_empty():
		push_error("map_pages missing")
		return 1
	var page: Dictionary = pages[0]
	if page.has("cell_marks"):
		push_error("cell_marks should be removed after build")
		return 1
	var cells: Array = page.get("cells", [])
	if cells.size() != 25:
		push_error("expected 25 cells")
		return 1
	return 0


func _test_validate_skips_invalid_marks() -> int:
	# 越界、非法 type、重复坐标均跳过，与 build_cells 一致
	if not LocalGridBuilderScript.validate_cell_marks(
		5,
		5,
		["plain"],
		[
			{"x": 9, "y": 0, "type": "plain"},
			{"x": 0, "y": 0, "type": "forest"},
			{"x": 0, "y": 0, "type": "plain"},
		],
	):
		push_error("invalid marks should be skipped, page still valid")
		return 1
	if not LocalGridBuilderScript.validate_cell_marks(5, 5, ["plain"], [{"x": 1, "y": 1, "type": "plain"}]):
		push_error("valid mark should pass")
		return 1
	return 0


func _test_sparse_cells_normalized() -> int:
	var sparse_page := {
		"id": "map_sparse",
		"name": "Sparse",
		"parent_type": "region",
		"parent_id": "region_sparse",
		"width": 5,
		"height": 5,
		"default_terrain": "plain",
		"terrain_types": ["plain", "forest"],
		"cells": [
			{"x": 1, "y": 1, "type": "forest", "name": "古井", "key_node_id": "node_old"},
		],
	}
	var built := LocalGridBuilderScript.build_map_page(sparse_page)
	var cells: Array = built.get("cells", [])
	if cells.size() != 25:
		push_error("sparse page should expand to 25 cells")
		return 1
	var marked: Dictionary = LocalGridBuilderScript.cell_at_index(cells, 1, 1, 5)
	if str(marked.get("key_node_id", "")) != "node_old":
		push_error("sparse overlay should preserve key_node_id")
		return 1
	var empty_cell: Dictionary = LocalGridBuilderScript.cell_at_index(cells, 0, 0, 5)
	if str(empty_cell.get("type", "")) != "plain":
		push_error("sparse page should fill defaults")
		return 1
	return 0


func _test_assign_key_node_cell() -> int:
	var map_structure := {
		"regions": [{"id": "region_a", "name": "A"}],
		"key_nodes": [],
		"map_pages": [
			LocalGridBuilderScript.build_map_page({
				"id": "map_region_a",
				"name": "A",
				"parent_type": "region",
				"parent_id": "region_a",
				"width": 5,
				"height": 5,
				"default_terrain": "plain",
				"terrain_types": ["plain"],
				"cell_marks": [],
			}),
		],
	}
	var key_node := {
		"id": "node_tavern",
		"name": "酒馆",
		"region_id": "region_a",
	}
	var out := LocalGridBuilderScript.assign_key_node_cell(map_structure, key_node)
	var pages: Array = out.get("map_pages", [])
	if pages.is_empty():
		push_error("assign_key_node_cell: no pages")
		return 1
	var page: Dictionary = pages[0]
	var cells: Array = page.get("cells", [])
	var found := false
	for raw in cells:
		if raw is Dictionary and str((raw as Dictionary).get("key_node_id", "")) == "node_tavern":
			found = true
			break
	if not found:
		push_error("assign_key_node_cell: key node not on grid")
		return 1
	var out2 := LocalGridBuilderScript.assign_key_node_cell(out, key_node)
	var pages2: Array = out2.get("map_pages", [])
	var count := 0
	for raw in pages2[0].get("cells", []):
		if raw is Dictionary and str((raw as Dictionary).get("key_node_id", "")) == "node_tavern":
			count += 1
	if count != 1:
		push_error("assign_key_node_cell: duplicate placement")
		return 1
	return 0


func _test_validate_map_page_spec() -> int:
	var ok_page := {
		"id": "map_a",
		"name": "A",
		"parent_type": "region",
		"parent_id": "region_a",
		"width": 10,
		"height": 10,
		"default_terrain": "plain",
		"terrain_types": ["plain", "forest"],
		"cell_marks": [{"x": 1, "y": 1, "type": "forest"}],
	}
	if not LocalGridBuilderScript.validate_map_page_spec(ok_page):
		push_error("valid page spec")
		return 1
	return 0
