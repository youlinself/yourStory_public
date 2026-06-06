## 人物侧栏地址树（`godot --headless -s tests/npc_sidebar_location_tree_test.gd`）
extends SceneTree

const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const TreeScript := preload("res://src/game/logic/world/npc_sidebar_location_tree.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_same_location_grouping()
	failed += _test_three_level_children()
	failed += _test_collect_ancestor_keys()
	failed += _test_protagonist_path_in_tree_without_npc()
	failed += _test_collect_prefix_keys_for_segments()
	if failed == 0:
		print("[OK] npc_sidebar_location_tree tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_same_location_grouping() -> int:
	var rm := _sample_read_model()
	var npcs: Array = [
		rm.npc_db["npcs"]["npc_a"],
		rm.npc_db["npcs"]["npc_b"],
	]
	var tree := TreeScript.build(rm, npcs)
	var groups := _leaf_groups(tree, ["派出所", "接待台"])
	if groups.size() != 1:
		push_error("same location: expected one group, got %d" % groups.size())
		return 1
	var entries: Array = groups[0]
	if entries.size() != 2:
		push_error("same location: expected 2 npcs, got %d" % entries.size())
		return 1
	return 0


func _test_three_level_children() -> int:
	var rm := _deep_path_read_model()
	var npcs: Array = [rm.npc_db["npcs"]["npc_deep"]]
	var tree := TreeScript.build(rm, npcs)
	if not tree["children"].has("老城区"):
		push_error("three level: missing 老城区")
		return 1
	var level1: Dictionary = tree["children"]["老城区"]
	if not level1["children"].has("南区"):
		push_error("three level: missing 南区")
		return 1
	var level2: Dictionary = level1["children"]["南区"]
	if not level2["children"].has("夜市入口"):
		push_error("three level: missing 夜市入口")
		return 1
	return 0


func _test_collect_ancestor_keys() -> int:
	var tree := {
		"children": {
			"老城区": {
				"children": {
					"南区": {
						"children": {
							"夜市入口": {
								"children": {},
								"groups": {
									"r|k": [{"id": "npc_x", "name": "X", "same_place": false}],
								},
							},
						},
						"groups": {},
					},
				},
				"groups": {},
			},
		},
		"groups": {},
	}
	var keys := TreeScript.collect_ancestor_keys(tree, "npc_x")
	if keys.size() != 3:
		push_error("ancestor keys: expected 3, got %s" % str(keys))
		return 1
	if keys[0] != "老城区" or keys[1] != "老城区/南区" or keys[2] != "老城区/南区/夜市入口":
		push_error("ancestor keys: unexpected %s" % str(keys))
		return 1
	return 0


func _test_protagonist_path_in_tree_without_npc() -> int:
	var rm := _sample_read_model()
	# 仅远处 NPC，主角在派出所/接待台
	rm.npc_db["npcs"] = {
		"npc_far": {
			"id": "npc_far",
			"name": "远",
			"current_region_id": "region_far",
			"current_key_node_id": "node_far",
		},
	}
	rm.map_db["regions"].append({"id": "region_far", "name": "东区港口"})
	rm.map_db["map_structure"]["key_nodes"].append(
		{"id": "node_far", "name": "港口广场", "region_id": "region_far"},
	)
	var tree := TreeScript.build(rm, [rm.npc_db["npcs"]["npc_far"]])
	if not tree["children"].has("派出所"):
		push_error("protagonist path: expected 派出所 branch without co-located npc")
		return 1
	var police: Dictionary = tree["children"]["派出所"]
	if not police["children"].has("接待台"):
		push_error("protagonist path: expected 接待台 under 派出所")
		return 1
	return 0


func _test_collect_prefix_keys_for_segments() -> int:
	var tree := {
		"children": {
			"老城区": {
				"children": {
					"警察总局": {"children": {}, "groups": {}},
				},
				"groups": {},
			},
		},
		"groups": {},
	}
	var keys := TreeScript.collect_prefix_keys_for_segments(
		tree,
		["老城区", "警察总局"],
	)
	if keys.size() != 2 or keys[0] != "老城区" or keys[1] != "老城区/警察总局":
		push_error("prefix keys: unexpected %s" % str(keys))
		return 1
	return 0


func _leaf_groups(tree: Dictionary, path: Array) -> Array:
	var node := tree
	for segment in path:
		node = node["children"][segment]
	var all: Array = []
	for group in node["groups"].values():
		if group is Array:
			all.append(group)
	return all


func _sample_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {
		"id": "hero",
		"current_region_id": "region_police",
		"current_key_node_id": "node_desk",
	}
	rm.map_db = {
		"regions": [
			{"id": "region_police", "name": "派出所"},
		],
		"map_structure": {
			"key_nodes": [
				{"id": "node_desk", "name": "接待台", "region_id": "region_police"},
			],
		},
	}
	rm.npc_db = {
		"npcs": {
			"npc_a": {
				"id": "npc_a",
				"name": "甲",
				"current_region_id": "region_police",
				"current_key_node_id": "node_desk",
			},
			"npc_b": {
				"id": "npc_b",
				"name": "乙",
				"current_region_id": "region_police",
				"current_key_node_id": "node_desk",
			},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	return rm


func _deep_path_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {
		"id": "hero",
		"current_region_id": "region_old",
		"current_key_node_id": "",
	}
	rm.map_db = {
		"regions": [
			{"id": "region_root", "name": "老城区"},
			{"id": "region_old", "name": "老城区 -> 南区"},
		],
		"map_structure": {
			"key_nodes": [
				{
					"id": "node_market",
					"name": "夜市入口",
					"region_id": "region_old",
				},
			],
		},
	}
	rm.npc_db = {
		"npcs": {
			"npc_deep": {
				"id": "npc_deep",
				"name": "深",
				"current_region_id": "region_old",
				"current_key_node_id": "node_market",
			},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	return rm
