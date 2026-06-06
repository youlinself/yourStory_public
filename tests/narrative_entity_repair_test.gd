## 程序自动补全：从正文推断周德海/康宁小区
extends SceneTree

const RepairScript := preload("res://src/game/logic/narrative/narrative_entity_repair.gd")
const MapRepairScript := preload("res://src/game/logic/world/map_structure_repair.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_build_requests_for_zhou_and_kangning()
	failed += _test_zhou_repair_when_other_npc_marker()
	failed += _test_kangning_parent_not_oldcity()
	if failed == 0:
		print("[OK] narrative entity repair tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_build_requests_for_zhou_and_kangning() -> int:
	var rm := _read_model()
	var story := (
		"赵明：「周德海，工人文化宫最后一任馆长，六十七岁，"
		+ "退休后住在南郊康宁小区7栋3单元501。」"
	)
	var reqs := RepairScript.build_synthetic_requests(story, rm)
	if reqs.is_empty():
		push_error("repair: expected synthetic requests")
		return 1
	var has_npc := false
	var has_place := false
	for req in reqs:
		if str(req.schema_id) == "runtime_npc" and str(req.source_context).find("周德海") >= 0:
			has_npc = true
		if str(req.schema_id) in ["runtime_key_node", "runtime_region"]:
			has_place = true
	if not has_npc:
		push_error("repair: missing NPC request for 周德海")
		return 1
	if not has_place:
		push_error("repair: missing place request for 康宁小区")
		return 1
	return 0


func _test_zhou_repair_when_other_npc_marker() -> int:
	var rm := _read_model()
	var story := (
		"赵明打来电话。[[DYN_ADD:NPC|赵明，警官]]周德海颤声问：「你是谁？」"
	)
	var reqs := RepairScript.build_synthetic_requests(story, rm)
	var has_zhou := false
	for req in reqs:
		if str(req.schema_id) == "runtime_npc" and str(req.source_context).find("周德海") >= 0:
			has_zhou = true
	if not has_zhou:
		push_error("repair: expected 周德海 request despite 赵明 DYN_ADD")
		return 1
	return 0


func _test_kangning_parent_not_oldcity() -> int:
	var rm := ReadModelScript.new()
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "region_oldcity", "name": "老城区"},
				{"id": "region_kangning", "name": "南郊康宁小区片区"},
			],
			"key_nodes": [],
		},
	}
	var parent := MapRepairScript.guess_parent_region_id_for_place("南郊康宁小区7栋", rm)
	if parent != "region_kangning":
		push_error("repair: kangning parent expected region_kangning, got %s" % parent)
		return 1
	return 0


func _read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {"name": "林浩", "current_region_id": "region_police"}
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "region_oldcity", "name": "老城区"},
				{"id": "region_south", "name": "南区红灯区与夜市"},
			],
			"key_nodes": [
				{"id": "node_police", "name": "警察总局", "region_id": "region_oldcity"},
			],
		},
	}
	rm.npc_db = {
		"npcs": {
			"npc_zhao": {"id": "npc_zhao", "name": "赵明"},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["unlocked_region_ids"] = ["region_oldcity", "region_south"]
	return rm
