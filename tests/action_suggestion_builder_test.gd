## 规则层行动建议：缩小 NPC 池、场景优先
extends SceneTree

const BuilderScript := preload("res://src/game/logic/narrative/action_suggestion_builder.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_no_four_remote_world_npcs()
	failed += _test_scene_targets_first()
	failed += _test_present_npc_prefers_talk()
	failed += _test_filter_internal_observe_suggestion()
	failed += _test_resolve_observe_npc_id()
	failed += _test_filters_unknown_travel()
	failed += _test_keeps_known_region()
	failed += _test_reserves_co_loc_talk()
	if failed == 0:
		print("[OK] action suggestion builder tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_no_four_remote_world_npcs() -> int:
	var rm := _base_read_model()
	rm.game_state["nearby_npc_ids"] = ["npc_far_a", "npc_far_b", "npc_far_c", "npc_far_d"]
	var rules := BuilderScript.build_from_read_model(rm)
	var remote_count := 0
	for text in rules:
		if str(text).begins_with("去") and str(text).find("找") > 0:
			remote_count += 1
	if remote_count > BuilderScript.MAX_REMOTE_NPC_SUGGESTIONS:
		push_error("expected at most %d remote NPC suggestions, got %s" % [
			BuilderScript.MAX_REMOTE_NPC_SUGGESTIONS,
			str(rules),
		])
		return 1
	var has_fallback := false
	for text in rules:
		if str(text) == "观察周围环境":
			has_fallback = true
	if not has_fallback:
		push_error("expected fallback when all NPCs are out of range: %s" % str(rules))
		return 1
	return 0


func _test_scene_targets_first() -> int:
	var rm := _base_read_model()
	rm.game_state["present_npc_ids"] = ["npc_zhou"]
	rm.game_state["scene_targets"] = ["来客", "门缝"]
	var rules := BuilderScript.build_from_read_model(rm)
	if rules.is_empty():
		push_error("expected non-empty rules")
		return 1
	if not str(rules[0]).begins_with("观察"):
		push_error("expected scene target first, got %s" % str(rules))
		return 1
	return 0


func _test_present_npc_prefers_talk() -> int:
	var rm := _base_read_model()
	rm.game_state["present_npc_ids"] = ["npc_zhou"]
	rm.npc_db["npcs"]["npc_zhou"]["current_region_id"] = "region_far"
	rm.npc_db["npcs"]["npc_zhou"]["current_key_node_id"] = ""
	var rules := BuilderScript.build_from_read_model(rm)
	var found_talk := false
	for text in rules:
		if str(text) == "与周德海搭话":
			found_talk = true
		if str(text).begins_with("去") and str(text).ends_with("找周德海"):
			push_error("present NPC should not suggest travel: %s" % str(rules))
			return 1
	if not found_talk:
		push_error("expected 与周德海搭话 in %s" % str(rules))
		return 1
	return 0


func _base_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {
		"id": "hero",
		"name": "林浩",
		"current_region_id": "region_home",
		"current_key_node_id": "node_home",
	}
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "region_home", "name": "康宁小区", "adjacent_region_ids": []},
				{"id": "region_far", "name": "函谷关", "adjacent_region_ids": []},
			],
			"key_nodes": [
				{"id": "node_home", "name": "7栋501", "region_id": "region_home"},
			],
		},
	}
	rm.npc_db = {
		"npcs": {
			"npc_zhou": {
				"id": "npc_zhou",
				"name": "周德海",
				"current_region_id": "region_home",
				"current_key_node_id": "node_home",
			},
			"npc_far_a": {
				"id": "npc_far_a",
				"name": "魏冉",
				"current_region_id": "region_far",
				"current_key_node_id": "",
			},
			"npc_far_b": {
				"id": "npc_far_b",
				"name": "张平",
				"current_region_id": "region_far",
				"current_key_node_id": "",
			},
			"npc_far_c": {
				"id": "npc_far_c",
				"name": "魏齐",
				"current_region_id": "region_far",
				"current_key_node_id": "",
			},
			"npc_far_d": {
				"id": "npc_far_d",
				"name": "周赧王",
				"current_region_id": "region_far",
				"current_key_node_id": "",
			},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["unlocked_region_ids"] = ["region_home"]
	return rm


func _test_filter_internal_observe_suggestion() -> int:
	var rm := _base_read_model()
	var filtered := BuilderScript.filter_suggestions_against_world(
		rm,
		["观察npc_smuggler_loo"],
	)
	if not filtered.is_empty():
		push_error("internal observe suggestion should be filtered: %s" % str(filtered))
		return 1
	return 0


func _test_resolve_observe_npc_id() -> int:
	var rm := _base_read_model()
	rm.game_state["present_npc_ids"] = ["npc_zhou"]
	var filtered := BuilderScript.filter_suggestions_against_world(
		rm,
		["观察npc_zhou"],
	)
	if filtered.size() != 1 or str(filtered[0]) != "观察周德海":
		push_error("known npc id should resolve to display name, got %s" % str(filtered))
		return 1
	return 0


func _test_filters_unknown_travel() -> int:
	var rm := _filter_read_model()
	var raw: Array = ["前往康宁小区", "与张三搭话"]
	var out := BuilderScript.filter_suggestions_against_world(rm, raw)
	if out.size() != 1 or str(out[0]) != "与张三搭话":
		push_error("filter: expected only non-travel suggestion, got %s" % str(out))
		return 1
	return 0


func _test_keeps_known_region() -> int:
	var rm := _filter_read_model()
	var raw: Array = ["前往老城区"]
	var out := BuilderScript.filter_suggestions_against_world(rm, raw)
	if out.size() != 1 or str(out[0]) != "前往老城区":
		push_error("filter: expected known region kept, got %s" % str(out))
		return 1
	return 0


func _test_reserves_co_loc_talk() -> int:
	var rm := _base_read_model()
	rm.game_state["present_npc_ids"] = ["npc_zhou"]
	var ai: Array = ["去夜市找阿华", "去法医中心找陈晓", "去法医中心找李娜", "检查档案"]
	var rules := BuilderScript.build_from_read_model(rm)
	var merged := BuilderScript.merge(ai, rules)
	var has_talk := false
	for text in merged:
		if str(text) == "与周德海搭话":
			has_talk = true
	if not has_talk:
		push_error("merge: expected 与周德海搭话 in %s" % str(merged))
		return 1
	return 0


func _filter_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {"current_region_id": "region_police"}
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "region_police", "name": "派出所"},
				{"id": "region_oldcity", "name": "老城区"},
			],
			"key_nodes": [],
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["unlocked_region_ids"] = ["region_police", "region_oldcity"]
	return rm
