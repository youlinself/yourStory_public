## 康宁子地点误挂老城区时改绑南郊片区
extends SceneTree

const RepairScript := preload("res://src/game/logic/world/map_structure_repair.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_rebind_kangning_nodes()
	if failed == 0:
		print("[OK] map structure repair tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_rebind_kangning_nodes() -> int:
	var map_db := {
		"map_structure": {
			"regions": [
				{"id": "region_oldcity", "name": "老城区"},
				{"id": "region_kangning", "name": "南郊康宁小区片区"},
			],
			"key_nodes": [
				{
					"id": "node_garden",
					"name": "康宁小区花园",
					"region_id": "region_oldcity",
				},
			],
		},
	}
	if not RepairScript.repair_misassigned_key_nodes(map_db):
		push_error("repair: expected change")
		return 1
	var nodes: Array = map_db["map_structure"]["key_nodes"]
	var node: Dictionary = nodes[0]
	if str(node.get("region_id", "")) != "region_kangning":
		push_error("repair: region_id not rebound")
		return 1
	return 0
