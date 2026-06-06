## scene_target 显示名解析（`godot --headless -s tests/scene_target_resolver_test.gd`）
extends SceneTree

const SceneTargetResolverScript := preload("res://src/game/logic/world/scene_target_resolver.gd")
const GameReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_key_node_id_to_name()
	failed += _test_plain_chinese_passthrough()
	failed += _test_unresolved_internal_dropped()

	if failed == 0:
		print("[OK] scene_target_resolver tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_key_node_id_to_name() -> int:
	var rm := GameReadModelScript.new()
	rm.map_db = {
		"map_structure": {
			"key_nodes": [
				{"id": "node_trial_stone", "name": "试炼石阵", "region_id": "region_camp"},
			],
			"regions": [{"id": "region_camp", "name": "营地"}],
		},
	}
	var display := SceneTargetResolverScript.resolve_display_name("node_trial_stone", rm)
	if display != "试炼石阵":
		push_error("expected 试炼石阵, got: %s" % display)
		return 1
	var list := SceneTargetResolverScript.normalize_target_list(["node_trial_stone"], rm)
	if list.size() != 1 or str(list[0]) != "试炼石阵":
		push_error("normalize_target_list failed: %s" % str(list))
		return 1
	return 0


func _test_plain_chinese_passthrough() -> int:
	var rm := GameReadModelScript.new()
	var display := SceneTargetResolverScript.resolve_display_name("门闩", rm)
	if display != "门闩":
		push_error("expected 门闩, got: %s" % display)
		return 1
	return 0


func _test_unresolved_internal_dropped() -> int:
	var rm := GameReadModelScript.new()
	var display := SceneTargetResolverScript.resolve_display_name("node_unknown_xyz", rm)
	if not display.is_empty():
		push_error("unresolved internal id should be empty, got: %s" % display)
		return 1
	return 0
