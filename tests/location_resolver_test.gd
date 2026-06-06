## LocationResolver：初始化与运行时位置解析
extends SceneTree

const LocationResolverScript := preload("res://src/game/logic/world/location_resolver.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")
const RuntimeStateServiceScript := preload("res://src/game/logic/state/runtime_state_service.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")


func _initialize() -> void:
	GameRunningFileManager.ensure_dir()
	var failed := 0
	failed += _test_init_respects_non_first_region()
	failed += _test_init_seeds_map_cell_from_key_node()
	failed += _test_init_infers_key_node_from_initial_scene()
	failed += _test_runtime_hook_syncs_map_cell()
	failed += _test_runtime_region_change_clears_key_node_and_resyncs()
	failed += _test_apply_map_cell_travel_explicit_coords()
	failed += _test_assign_key_node_cell_fallback()
	if failed == 0:
		print("[OK] location resolver tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _sample_map_structure(with_cell_binding: bool = true) -> Dictionary:
	var cells: Array = []
	for y in 5:
		for x in 5:
			cells.append({
				"x": x,
				"y": y,
				"type": "plain",
				"name": "",
				"key_node_id": "kn_gate" if with_cell_binding and x == 2 and y == 2 else "",
				"child_map_id": "",
			})
	return {
		"regions": [
			{"id": "region_a", "name": "北境"},
			{"id": "region_b", "name": "南郊"},
		],
		"key_nodes": [
			{"id": "kn_gate", "name": "旧城门", "region_id": "region_b"},
			{"id": "kn_market", "name": "集市", "region_id": "region_a"},
		],
		"map_pages": [
			{
				"id": "page_b",
				"name": "南郊地图",
				"parent_type": "region",
				"parent_id": "region_b",
				"width": 5,
				"height": 5,
				"cells": cells,
			},
		],
	}


func _sample_world_init(with_cell_binding: bool = true) -> Dictionary:
	return {
		"protagonist_id": "hero_01",
		"adventure_module": {"opening_hook": "雨夜旧城门下"},
		"map_structure": _sample_map_structure(with_cell_binding),
		"npcs": [],
	}


func _test_init_respects_non_first_region() -> int:
	var world_init := _sample_world_init()
	var npc := {
		"id": "hero_01",
		"name": "主角",
		"initial_scene": "南郊旧城门",
		"current_region_id": "region_b",
		"current_key_node_id": "kn_gate",
		"skills": ["s1"],
	}
	var role := RuntimeDbSchemas.build_mainrole_from_npc(npc, world_init)
	if str(role.get("current_region_id", "")) != "region_b":
		push_error("init: expected region_b, got %s" % str(role.get("current_region_id", "")))
		return 1
	return 0


func _test_init_seeds_map_cell_from_key_node() -> int:
	var world_init := _sample_world_init(true)
	var npc := {
		"id": "hero_01",
		"name": "主角",
		"initial_scene": "旧城门",
		"current_region_id": "region_b",
		"current_key_node_id": "kn_gate",
		"skills": ["s1"],
	}
	var role := RuntimeDbSchemas.build_mainrole_from_npc(npc, world_init)
	var cell: Variant = role.get("current_map_cell", null)
	if not cell is Dictionary:
		push_error("init: missing current_map_cell")
		return 1
	if str(cell.get("page_id", "")) != "page_b":
		push_error("init: bad page_id %s" % str(cell.get("page_id", "")))
		return 1
	if int(cell.get("x", -1)) != 2 or int(cell.get("y", -1)) != 2:
		push_error("init: bad cell coords (%s,%s)" % [str(cell.get("x")), str(cell.get("y"))])
		return 1
	return 0


func _test_init_infers_key_node_from_initial_scene() -> int:
	var world_init := _sample_world_init(true)
	var npc := {
		"id": "hero_01",
		"name": "主角",
		"initial_scene": "站在旧城门前",
		"current_region_id": "region_b",
		"skills": ["s1"],
	}
	var role := RuntimeDbSchemas.build_mainrole_from_npc(npc, world_init)
	if str(role.get("current_key_node_id", "")) != "kn_gate":
		push_error("init infer key_node: got %s" % str(role.get("current_key_node_id", "")))
		return 1
	return 0


func _make_state_with_mainrole(rm: GameReadModel) -> RuntimeStateService:
	var state_svc := RuntimeStateServiceScript.new()
	state_svc._game_state = rm.game_state.duplicate(true)
	state_svc._mainrole = rm.mainrole.duplicate(true)
	return state_svc


func _test_runtime_hook_syncs_map_cell() -> int:
	var rm := ReadModelScript.new()
	rm.map_db = {"map_structure": _sample_map_structure(true)}
	rm.mainrole = {
		"id": "hero_01",
		"current_region_id": "region_b",
		"current_key_node_id": "",
		"current_map_cell": {},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["datetime_display"] = "Day 1"
	rm.game_state["weather"] = "晴"

	var state_svc := _make_state_with_mainrole(rm)

	var result := state_svc.apply_hook(
		{
			"datetime_display": "Day 1",
			"weather": "晴",
			"current_key_node_id": "kn_gate",
		},
		["region_a", "region_b"],
		rm,
	)
	if not result.get("ok", false):
		push_error("hook sync: apply_hook failed")
		return 1
	var cell: Variant = state_svc.get_mainrole().get("current_map_cell", null)
	if not cell is Dictionary or str(cell.get("page_id", "")).is_empty():
		push_error("hook sync: map_cell not synced")
		return 1
	return 0


func _test_runtime_region_change_clears_key_node_and_resyncs() -> int:
	var rm := ReadModelScript.new()
	rm.map_db = {"map_structure": _sample_map_structure(true)}
	rm.mainrole = {
		"id": "hero_01",
		"current_region_id": "region_b",
		"current_key_node_id": "kn_gate",
		"current_map_cell": {"page_id": "page_b", "x": 2, "y": 2},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["datetime_display"] = "Day 1"
	rm.game_state["weather"] = "晴"

	var state_svc := _make_state_with_mainrole(rm)

	var result := state_svc.apply_hook(
		{
			"datetime_display": "Day 1",
			"weather": "晴",
			"current_region_id": "region_a",
		},
		["region_a", "region_b"],
		rm,
	)
	if not result.get("ok", false):
		push_error("region change: apply_hook failed")
		return 1
	var role := state_svc.get_mainrole()
	if str(role.get("current_region_id", "")) != "region_a":
		push_error("region change: bad region")
		return 1
	if not str(role.get("current_key_node_id", "")).is_empty():
		push_error("region change: key_node should clear")
		return 1
	var cell: Variant = role.get("current_map_cell", null)
	if cell is Dictionary and not str(cell.get("page_id", "")).is_empty():
		push_error("region change: map_cell should clear without new key_node")
		return 1
	return 0


func _test_apply_map_cell_travel_explicit_coords() -> int:
	var rm := ReadModelScript.new()
	rm.map_db = {"map_structure": _sample_map_structure(true)}
	rm.mainrole = {
		"id": "hero_01",
		"current_region_id": "region_b",
		"current_key_node_id": "",
		"current_map_cell": {},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["datetime_display"] = "Day 1"
	rm.game_state["weather"] = "晴"

	var state_svc := _make_state_with_mainrole(rm)

	var result := state_svc.apply_map_cell_travel(
		{"region_id": "region_b", "key_node_id": "kn_gate"},
		"page_b",
		3,
		4,
		["region_a", "region_b"],
		rm,
	)
	if not result.get("ok", false):
		push_error("map cell travel: failed")
		return 1
	var cell: Variant = state_svc.get_mainrole().get("current_map_cell", null)
	if not cell is Dictionary:
		push_error("map cell travel: missing cell")
		return 1
	if int(cell.get("x", -1)) != 3 or int(cell.get("y", -1)) != 4:
		push_error("map cell travel: bad coords")
		return 1
	return 0


func _test_assign_key_node_cell_fallback() -> int:
	var map_structure := _sample_map_structure(false)
	var role := RuntimeDbSchemas.empty_mainrole()
	LocationResolverScript.resolve_and_apply(
		role,
		map_structure,
		{
			"region_hint": "region_b",
			"key_node_hint": "kn_gate",
			"hint_text": "旧城门",
		},
		{"allow_assign_key_node_cell": true, "include_map_cell": true},
	)
	var cell: Variant = role.get("current_map_cell", null)
	if not cell is Dictionary or str(cell.get("page_id", "")).is_empty():
		push_error("assign fallback: map_cell still empty")
		return 1
	return 0
