## dynamic_add 地图数组写入与解锁
extends SceneTree

const StorageScript := preload("res://src/ai_skills/dynamic_add_storage.gd")
const PromptBuilderScript := preload("res://src/ai_skills/dynamic_add_prompt_builder.gd")
const GameRunningFileManager := preload("res://src/game_running_file_manage/game_running_file_manager.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_append_region_unlocks()
	failed += _test_append_key_node_dedupe()
	failed += _test_key_node_region_corrected_to_south()
	failed += _test_key_node_persists_map_cell()
	if failed == 0:
		print("[OK] dynamic add map storage tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_append_region_unlocks() -> int:
	_setup_runtime()
	var schema := PromptBuilderScript.load_schema("runtime_region")
	var record := {
		"id": "region_test_south",
		"name": "南郊",
		"location": "城郊",
		"adjacent_region_ids": [],
	}
	var result := StorageScript.apply_generation_result("runtime_region", {"data": record})
	if not result.get("ok", false):
		push_error("region append: %s" % str(result))
		return 1
	var map_db: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB)
	var regions: Variant = map_db.get("map_structure", {}).get("regions", [])
	var found := false
	if regions is Array:
		for r in regions:
			if r is Dictionary and str(r.get("id", "")) == "region_test_south":
				found = true
	if not found:
		push_error("region append: not in map_db")
		return 1
	var state: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.GAME_STATE)
	var unlocked: Variant = state.get("unlocked_region_ids", [])
	if not (unlocked is Array) or "region_test_south" not in unlocked:
		push_error("region append: not unlocked")
		return 1
	return 0


func _test_append_key_node_dedupe() -> int:
	_setup_runtime()
	var schema_id := "runtime_key_node"
	var record := {
		"id": "node_test_kangning",
		"name": "康宁小区",
		"type": "住宅",
		"description": "测试",
		"region_id": "region_test_south",
	}
	var first := StorageScript.apply_generation_result(schema_id, {"data": record})
	var second := StorageScript.apply_generation_result(schema_id, {"data": record.duplicate(true)})
	if not first.get("ok", false) or not second.get("ok", false):
		push_error("key_node append failed")
		return 1
	if second.get("status") != "already_exists":
		push_error("key_node dedupe: expected already_exists")
		return 1
	return 0


func _test_key_node_region_corrected_to_south() -> int:
	_setup_runtime()
	var map_db := {
		"map_structure": {
			"regions": [
				{"id": "region_oldcity", "name": "老城区"},
				{"id": "region_test_south", "name": "南郊康宁小区片区"},
			],
			"key_nodes": [],
		},
	}
	GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, map_db)
	var record := {
		"id": "node_kangning_garden",
		"name": "康宁小区花园",
		"type": "住宅",
		"description": "测试",
		"region_id": "region_oldcity",
	}
	var result := StorageScript.apply_generation_result("runtime_key_node", {"data": record})
	if not result.get("ok", false):
		push_error("key_node region fix: apply failed")
		return 1
	var data: Dictionary = result.get("data", {})
	if str(data.get("region_id", "")) != "region_test_south":
		push_error("key_node region fix: expected region_test_south, got %s" % str(data.get("region_id")))
		return 1
	return 0


func _test_key_node_persists_map_cell() -> int:
	_setup_runtime()
	var map_db := {
		"map_structure": {
			"regions": [{"id": "region_test_south", "name": "南郊"}],
			"key_nodes": [],
			"map_pages": [],
		},
	}
	GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, map_db)
	var record := {
		"id": "node_market",
		"name": "集市",
		"type": "地标",
		"description": "测试",
		"region_id": "region_test_south",
	}
	var first := StorageScript.apply_generation_result("runtime_key_node", {"data": record})
	if not first.get("ok", false):
		push_error("key_node map cell: first apply failed")
		return 1
	var saved: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB)
	var pages: Variant = saved.get("map_structure", {}).get("map_pages", [])
	if not pages is Array or (pages as Array).is_empty():
		push_error("key_node map cell: no map page created")
		return 1
	var page: Dictionary = pages[0]
	var cells: Array = page.get("cells", [])
	var found := false
	var first_coord := Vector2i(-1, -1)
	for raw in cells:
		if raw is Dictionary and str((raw as Dictionary).get("key_node_id", "")) == "node_market":
			found = true
			first_coord = Vector2i(int((raw as Dictionary).get("x", -1)), int((raw as Dictionary).get("y", -1)))
			break
	if not found:
		push_error("key_node map cell: not placed on grid")
		return 1
	var second := StorageScript.apply_generation_result("runtime_key_node", {"data": record.duplicate(true)})
	if second.get("status") != "already_exists":
		push_error("key_node map cell: expected dedupe")
		return 1
	var saved2: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB)
	var cells2: Array = saved2.get("map_structure", {}).get("map_pages", [])[0].get("cells", [])
	var count := 0
	for raw in cells2:
		if raw is Dictionary and str((raw as Dictionary).get("key_node_id", "")) == "node_market":
			count += 1
			if Vector2i(int((raw as Dictionary).get("x", -1)), int((raw as Dictionary).get("y", -1))) != first_coord:
				push_error("key_node map cell: coord changed on dedupe")
				return 1
	if count != 1:
		push_error("key_node map cell: duplicate cells after dedupe")
		return 1
	return 0


func _setup_runtime() -> void:
	GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, RuntimeDbSchemas.empty_map_db())
	GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, RuntimeDbSchemas.empty_game_state())
