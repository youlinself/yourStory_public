## 斜杠命令参数拆分（目录项 + 自由后缀）冒烟测试
extends SceneTree

const ArgCompleterScript := preload("res://src/game/logic/input/player_command_arg_completer.gd")
const ResolverScript := preload("res://src/game/logic/input/player_command_resolver.gd")
const RegistryScript := preload("res://src/game/logic/input/player_command_registry.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_single_match_opens_first_arg()
	failed += _test_talk_split_resolve()
	failed += _test_talk_completer_stages()
	failed += _test_move_split_resolve()
	failed += _test_observe_whole_target()
	failed += _test_skill_two_args()
	failed += _test_move_unknown_region_hint()
	if failed == 0:
		print("[OK] player command resolver tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_single_match_opens_first_arg() -> int:
	var reg := RegistryScript.new()
	reg.load_registry()
	var rm := _command_read_model()
	var cmd: Dictionary = reg.resolve_single_matched_command("对话")
	if cmd.is_empty() or str(cmd.get("id", "")) != "talk":
		push_error("resolve_single_matched_command: expected talk for 对话")
		return 1
	if not reg.command_first_arg_has_completion(cmd):
		push_error("command_first_arg_has_completion: talk should have npc resolver")
		return 1
	var label := RegistryScript.build_menu_label(cmd, rm)
	if "[想说什么]" in label:
		push_error("build_menu_label: command preview should not include message placeholder, got %s" % label)
		return 1
	return 0


func _test_talk_split_resolve() -> int:
	var rm := _command_read_model()
	var resolver := ResolverScript.new()
	var r := resolver.resolve("/对话 赵明 你好", rm)
	if not r.get("ok", false):
		push_error("talk resolve: %s" % r.get("error", ""))
		return 1
	var expanded := str(r.get("expanded", ""))
	if expanded.find("找不到") >= 0:
		push_error("talk resolve: should not fail npc lookup, got %s" % expanded)
		return 1
	if expanded.find("赵明") < 0 or expanded.find("你好") < 0:
		push_error("talk resolve: expected npc and message in %s" % expanded)
		return 1
	var r2 := resolver.resolve("/对话 赵明", rm)
	if not r2.get("ok", false):
		push_error("talk resolve no message: %s" % r2.get("error", ""))
		return 1
	if str(r2.get("expanded", "")).find("开口打招呼") < 0:
		push_error("talk resolve: expected default greeting")
		return 1
	return 0


func _test_talk_completer_stages() -> int:
	var rm := _command_read_model()
	var reg := RegistryScript.new()
	reg.load_registry()
	var active := ArgCompleterScript.try_build_entries("/对话 赵明", reg, rm)
	if not active.get("active", false):
		push_error("talk completer: expected active on /对话 赵明")
		return 1
	var inactive := ArgCompleterScript.try_build_entries("/对话 赵明 你", reg, rm)
	if inactive.get("active", false):
		push_error("talk completer: should be inactive when typing message")
		return 1
	return 0


func _test_move_split_resolve() -> int:
	var rm := _command_read_model()
	var resolver := ResolverScript.new()
	var r := resolver.resolve("/前往 老城区 悄悄接近", rm)
	if not r.get("ok", false):
		push_error("move resolve: %s" % r.get("error", ""))
		return 1
	var expanded := str(r.get("expanded", ""))
	if expanded.find("无法前往") >= 0:
		push_error("move resolve: should not fail region lookup, got %s" % expanded)
		return 1
	if expanded.find("老城区") < 0 or expanded.find("悄悄接近") < 0:
		push_error("move resolve: expected region and detail in %s" % expanded)
		return 1
	return 0


func _test_observe_whole_target() -> int:
	var rm := _command_read_model()
	var resolver := ResolverScript.new()
	var r := resolver.resolve("/观察 赵明 的袖口", rm)
	if not r.get("ok", false):
		push_error("observe resolve: %s" % r.get("error", ""))
		return 1
	var expanded := str(r.get("expanded", ""))
	if expanded.find("赵明 的袖口") < 0:
		push_error("observe resolve: expected full target phrase, got %s" % expanded)
		return 1
	return 0


func _test_move_unknown_region_hint() -> int:
	var rm := _command_read_model()
	var resolver := ResolverScript.new()
	var r := resolver.resolve("/前往 康宁小区", rm)
	if r.get("ok", false):
		push_error("move unknown: expected failure")
		return 1
	var err := str(r.get("error", ""))
	if err.find("尚未入库") < 0:
		push_error("move unknown: expected storage hint, got %s" % err)
		return 1
	return 0


func _test_skill_two_args() -> int:
	var parts: Array[String] = ResolverScript._split_positional_args("急救 按住伤口", 2)
	if parts.size() != 2 or parts[0] != "急救" or parts[1] != "按住伤口":
		push_error("skill split: expected [急救, 按住伤口], got %s" % str(parts))
		return 1
	var observe_parts: Array[String] = ResolverScript._split_positional_args("赵明 的袖口", 1)
	if observe_parts.size() != 1 or observe_parts[0] != "赵明 的袖口":
		push_error("observe split: expected single segment, got %s" % str(observe_parts))
		return 1
	return 0


func _command_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {
		"id": "hero",
		"current_region_id": "region_police",
		"current_key_node_id": "node_desk",
		"skills": ["skill_first_aid"],
	}
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "region_police", "name": "派出所"},
				{"id": "region_oldcity", "name": "老城区"},
			],
			"key_nodes": [
				{"id": "node_desk", "name": "接待台", "region_id": "region_police"},
			],
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["unlocked_region_ids"] = ["region_police", "region_oldcity"]
	rm.npc_db = {
		"npcs": {
			"hero": {
				"id": "hero",
				"name": "主角",
				"skills": ["skill_first_aid"],
				"current_region_id": "region_police",
				"current_key_node_id": "node_desk",
			},
			"npc_ming": {
				"id": "npc_ming",
				"name": "赵明",
				"current_region_id": "region_police",
				"current_key_node_id": "node_desk",
			},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["present_npc_ids"] = ["npc_ming"]
	rm.game_state["unlocked_region_ids"] = ["region_police", "region_oldcity"]
	return rm
