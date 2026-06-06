## 位置路径：无子地点时不伪造父级前缀
extends SceneTree

const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_no_fake_parent_prefix()
	if failed == 0:
		print("[OK] location service path tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_no_fake_parent_prefix() -> int:
	var rm := ReadModelScript.new()
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "region_oldcity", "name": "老城区"},
				{"id": "region_south", "name": "南郊康宁小区片区"},
			],
			"key_nodes": [],
		},
	}
	rm.mainrole = {
		"current_region_id": "region_south",
		"current_key_node_id": "",
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	var path := LocationServiceScript.format_location_path(
		rm,
		{"region_id": "region_south", "key_node_id": ""},
	)
	if path.find("老城区") >= 0:
		push_error("path: should not prefix 老城区, got %s" % path)
		return 1
	if path != "南郊康宁小区片区":
		push_error("path: unexpected %s" % path)
		return 1
	return 0
