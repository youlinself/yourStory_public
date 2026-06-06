## 斜杠补全与 STATE_HOOK 场景字段冒烟测试
extends SceneTree

const ArgCompleterScript := preload("res://src/game/logic/input/player_command_arg_completer.gd")
const HookNormalizerScript := preload("res://src/game/logic/narrative/narrative_hook_normalizer.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RegistryScript := preload("res://src/game/logic/input/player_command_registry.gd")
const RuntimeStateServiceScript := preload("res://src/game/logic/state/runtime_state_service.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_present_npc_ids_in_completer()
	failed += _test_scene_targets_in_completer()
	failed += _test_build_menu_label_preview()
	failed += _test_hook_normalizer_present_npcs()
	failed += _test_apply_present_npc_ids()
	failed += _test_interactable_after_location_update()
	if failed == 0:
		print("[OK] player command hook completer tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_present_npc_ids_in_completer() -> int:
	var rm := _sample_read_model()
	rm.game_state["present_npc_ids"] = ["npc_zhao"]
	var opts: Array = ArgCompleterScript.list_options_for("generic_target", rm, "")
	var values: PackedStringArray = []
	for opt in opts:
		if opt is Dictionary:
			values.append(str(opt.get("value", "")))
	if "赵队" not in values:
		push_error("generic_target: expected 赵队 in options, got %s" % str(values))
		return 1
	return 0


func _test_scene_targets_in_completer() -> int:
	var rm := _sample_read_model()
	rm.game_state["scene_targets"] = ["工人文化宫"]
	var opts: Array = ArgCompleterScript.list_options_for("generic_target", rm, "")
	for opt in opts:
		if opt is Dictionary and str(opt.get("value", "")) == "工人文化宫":
			return 0
	push_error("generic_target: expected scene_targets entry 工人文化宫")
	return 1


func _test_build_menu_label_preview() -> int:
	var reg := RegistryScript.new()
	if not reg.load_registry():
		push_error("build_menu_label: registry load failed")
		return 1
	var rm := _sample_read_model()
	rm.game_state["present_npc_ids"] = ["npc_zhao"]
	var cmd := reg.find_command("观察")
	if cmd.is_empty():
		push_error("build_menu_label: observe command missing")
		return 1
	var label := RegistryScript.build_menu_label(cmd, rm)
	if "[目标]" in label:
		push_error("build_menu_label: should not contain static placeholder, got %s" % label)
		return 1
	if not label.begins_with("/观察"):
		push_error("build_menu_label: unexpected label %s" % label)
		return 1
	return 0


func _test_hook_normalizer_present_npcs() -> int:
	var rm := _sample_read_model()
	var hook := {
		"datetime_display": "测试日",
		"weather": "晴",
		"present_npc_ids": ["赵队"],
	}
	var normalized := HookNormalizerScript.normalize(hook, rm, {})
	var ids: Variant = normalized.get("present_npc_ids", [])
	if not ids is Array or str(ids[0]) != "npc_zhao":
		push_error("normalizer: expected npc_zhao, got %s" % str(ids))
		return 1
	return 0


func _test_apply_present_npc_ids() -> int:
	var state := RuntimeDbSchemas.empty_game_state()
	var hook := {"present_npc_ids": ["npc_zhao", "npc_zhao"]}
	var warnings: PackedStringArray = []
	RuntimeStateServiceScript._apply_present_npc_ids(state, hook, warnings)
	var ids: Variant = state.get("present_npc_ids", [])
	if not ids is Array or ids.size() != 1 or str(ids[0]) != "npc_zhao":
		push_error("apply_present_npc_ids: unexpected ids %s" % str(ids))
		return 1
	var pool: Variant = state.get("nearby_npc_ids", [])
	if not pool is Array or str(pool[0]) != "npc_zhao":
		push_error("apply_present_npc_ids: expected nearby pool merge")
		return 1
	return 0


func _test_interactable_after_location_update() -> int:
	var rm := _sample_read_model()
	rm.mainrole["current_region_id"] = "region_police"
	rm.mainrole["current_key_node_id"] = "node_desk"
	rm.game_state["present_npc_ids"] = ["npc_zhao"]
	var npcs: Dictionary = rm.npc_db.get("npcs", {})
	npcs["npc_zhao"]["current_region_id"] = "region_police"
	npcs["npc_zhao"]["current_key_node_id"] = "node_desk"
	rm.npc_db["npcs"] = npcs
	var interactable := rm.get_interactable_npcs()
	if interactable.is_empty():
		push_error("interactable: expected npc_zhao at same place")
		return 1
	if str(interactable[0].get("id", "")) != "npc_zhao":
		push_error("interactable: wrong npc %s" % interactable[0])
		return 1
	var here := LocationServiceScript.get_protagonist_location(rm)
	var npc_loc := LocationServiceScript.get_npc_location(rm, interactable[0])
	if not LocationServiceScript.is_same_place(here, npc_loc):
		push_error("interactable: location mismatch")
		return 1
	return 0


func _sample_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {
		"id": "hero",
		"current_region_id": "region_police",
		"current_key_node_id": "node_desk",
	}
	rm.map_db = {
		"regions": [{"id": "region_police", "name": "派出所"}],
		"map_structure": {
			"key_nodes": [
				{"id": "node_desk", "name": "接待台", "region_id": "region_police"},
			],
		},
	}
	rm.npc_db = {
		"npcs": {
			"npc_zhao": {
				"id": "npc_zhao",
				"name": "赵队",
				"current_region_id": "region_old",
				"current_key_node_id": "",
			},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	return rm
