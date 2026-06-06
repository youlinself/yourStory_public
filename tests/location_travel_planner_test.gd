## 地图格子旅行：标签坐标、目标解析与叙事注入
extends SceneTree

const GridMapViewScript := preload("res://src/game/grid_map_view.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const LocationTravelPlannerScript := preload("res://src/game/logic/world/location_travel_planner.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeStateServiceScript := preload("res://src/game/logic/state/runtime_state_service.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_format_travel_cell_label_named()
	failed += _test_format_travel_cell_label_key_node()
	failed += _test_format_travel_cell_label_terrain()
	failed += _test_resolve_map_cell_travel_target_region_page()
	failed += _test_resolve_map_cell_travel_target_key_node_page()
	failed += _test_plan_map_cell_travel_same_place()
	failed += _test_enrich_map_cell_travel()
	failed += _test_is_same_place_from_role()
	failed += _test_reconcile_after_partial_hook()
	failed += _test_reconcile_skips_same_place()
	failed += _test_needs_map_cell_travel_same_region_terrain()
	failed += _test_parse_map_travel_from_player_text()
	failed += _test_apply_map_cell_travel_persists_cell()
	if failed == 0:
		print("[OK] location travel planner tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _make_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.map_db = {
		"map_structure": {
			"regions": [
				{"id": "region_market", "name": "补丁集市"},
			],
			"key_nodes": [
				{"id": "kn_shallow", "name": "浅地下水脉", "region_id": "region_market"},
				{"id": "kn_inner", "name": "内层据点", "region_id": "region_market"},
			],
			"map_pages": [
				{
					"id": "page_market",
					"name": "集市地图",
					"parent_type": "region",
					"parent_id": "region_market",
					"width": 8,
					"height": 8,
				},
				{
					"id": "page_inner",
					"name": "内层地图",
					"parent_type": "key_node",
					"parent_id": "kn_inner",
					"width": 5,
					"height": 5,
				},
			],
		},
	}
	rm.mainrole = {
		"current_region_id": "region_market",
		"current_key_node_id": "kn_shallow",
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["datetime_display"] = "Day 1 08:00"
	rm.game_state["weather"] = "阴"
	rm.npc_db = RuntimeDbSchemas.empty_npc_db()
	return rm


func _test_format_travel_cell_label_named() -> int:
	var label := GridMapViewScript.format_travel_cell_label(
		{"name": "浅地", "x": 2, "y": 4},
	)
	if label != "浅地（3,5）":
		push_error("named label: expected 浅地（3,5）, got %s" % label)
		return 1
	return 0


func _test_format_travel_cell_label_key_node() -> int:
	var rm := _make_read_model()
	var label := GridMapViewScript.format_travel_cell_label(
		{"key_node_id": "kn_shallow", "x": 1, "y": 1},
		rm,
	)
	if label != "浅地下水脉（2,2）":
		push_error("key_node label: expected 浅地下水脉（2,2）, got %s" % label)
		return 1
	return 0


func _test_format_travel_cell_label_terrain() -> int:
	var label := GridMapViewScript.format_travel_cell_label(
		{"type": "平原", "x": 0, "y": 0},
	)
	if label != "平原（1,1）":
		push_error("terrain label: expected 平原（1,1）, got %s" % label)
		return 1
	return 0


func _test_resolve_map_cell_travel_target_region_page() -> int:
	var rm := _make_read_model()
	var map_page := rm.get_map_page("page_market")
	var target := LocationServiceScript.resolve_map_cell_travel_target(
		rm,
		map_page,
		{"x": 3, "y": 4, "key_node_id": "kn_inner"},
	)
	if not target.get("needs_travel", false):
		push_error("region page target: expected needs_travel true")
		return 1
	if target.get("region_id", "") != "region_market":
		push_error("region page target: bad region_id %s" % str(target.get("region_id")))
		return 1
	if target.get("key_node_id", "") != "kn_inner":
		push_error("region page target: bad key_node_id %s" % str(target.get("key_node_id")))
		return 1
	if target.get("page_id", "") != "page_market":
		push_error("region page target: bad page_id %s" % str(target.get("page_id")))
		return 1
	return 0


func _test_resolve_map_cell_travel_target_key_node_page() -> int:
	var rm := _make_read_model()
	var map_page := rm.get_map_page("page_inner")
	var target := LocationServiceScript.resolve_map_cell_travel_target(
		rm,
		map_page,
		{"x": 2, "y": 2, "name": "密室"},
	)
	if not target.get("needs_travel", false):
		push_error("key_node page target: expected needs_travel true")
		return 1
	if target.get("region_id", "") != "region_market":
		push_error("key_node page target: bad region_id %s" % str(target.get("region_id")))
		return 1
	if not str(target.get("key_node_id", "")).is_empty():
		push_error("key_node page target: expected empty key_node_id")
		return 1
	return 0


func _test_plan_map_cell_travel_same_place() -> int:
	var rm := _make_read_model()
	var map_travel := LocationServiceScript.resolve_map_cell_travel_target(
		rm,
		rm.get_map_page("page_market"),
		{"x": 0, "y": 0, "key_node_id": "kn_shallow"},
	)
	if map_travel.get("needs_travel", true):
		push_error("same place: resolve should set needs_travel false")
		return 1
	var plan := LocationTravelPlannerScript.plan_map_cell_travel(map_travel, rm)
	if plan.get("needs_travel", false):
		push_error("same place: plan should not need travel")
		return 1
	return 0


func _test_enrich_map_cell_travel() -> int:
	var rm := _make_read_model()
	var map_travel := LocationServiceScript.resolve_map_cell_travel_target(
		rm,
		rm.get_map_page("page_market"),
		{"x": 2, "y": 4, "key_node_id": "kn_inner"},
	)
	var enriched := LocationTravelPlannerScript.enrich_player_text(
		"你准备去浅地（3,5）",
		rm,
		map_travel,
	)
	if enriched.find("【位置】") < 0:
		push_error("enrich: missing 【位置】 directive")
		return 1
	if enriched.find("current_region_id=\"region_market\"") < 0:
		push_error("enrich: missing region id in directive")
		return 1
	if enriched.find("current_key_node_id=\"kn_inner\"") < 0:
		push_error("enrich: missing key_node id in directive")
		return 1
	if enriched.find("（3,5）") < 0:
		push_error("enrich: missing display coordinates in directive")
		return 1
	return 0


func _test_is_same_place_from_role() -> int:
	var role := {
		"current_region_id": "region_market",
		"current_key_node_id": "kn_shallow",
	}
	var same := LocationServiceScript.is_same_place_from_role(
		role,
		{"region_id": "region_market", "key_node_id": "kn_shallow"},
	)
	if not same:
		push_error("is_same_place_from_role: expected true for matching loc")
		return 1
	var diff := LocationServiceScript.is_same_place_from_role(
		role,
		{"region_id": "region_market", "key_node_id": "kn_inner"},
	)
	if diff:
		push_error("is_same_place_from_role: expected false for different key_node")
		return 1
	return 0


func _make_state_with_mainrole(rm: GameReadModel) -> RuntimeStateService:
	var state_svc := RuntimeStateServiceScript.new()
	state_svc._game_state = rm.game_state.duplicate(true)
	state_svc._mainrole = rm.mainrole.duplicate(true)
	return state_svc


func _simulate_map_reconcile(
	state_svc: RuntimeStateService,
	rm: GameReadModel,
	plan: Dictionary,
) -> bool:
	if not plan.get("needs_travel", false):
		return false
	var to_loc: Dictionary = plan.get("to_loc", {}) if plan.get("to_loc") is Dictionary else {}
	if to_loc.is_empty():
		return false
	var page_id := str(plan.get("page_id", "")).strip_edges()
	var x := int(plan.get("x", -1))
	var y := int(plan.get("y", -1))
	var role := state_svc.get_mainrole()
	var same_loc := LocationServiceScript.is_same_place_from_role(role, to_loc)
	var same_cell := false
	if not page_id.is_empty() and x >= 0 and y >= 0:
		same_cell = LocationServiceScript.is_same_map_cell(rm, page_id, x, y)
	if same_loc and same_cell:
		return false
	var result: Dictionary = state_svc.apply_map_cell_travel(
		to_loc,
		page_id,
		x,
		y,
		["region_market"],
		rm,
	)
	return result.get("ok", false)


func _test_reconcile_after_partial_hook() -> int:
	var rm := _make_read_model()
	var state_svc := _make_state_with_mainrole(rm)
	var hook := {
		"datetime_display": "Day 1 08:00",
		"weather": "阴",
	}
	var hook_result := state_svc.apply_hook(hook, ["region_market"], rm)
	if not hook_result.get("ok", false):
		push_error("partial hook: apply_hook should succeed")
		return 1
	if str(state_svc.get_mainrole().get("current_key_node_id", "")) != "kn_shallow":
		push_error("partial hook: key_node should remain kn_shallow before reconcile")
		return 1
	var map_plan := LocationTravelPlannerScript.plan_map_cell_travel(
		{
			"needs_travel": true,
			"region_id": "region_market",
			"key_node_id": "kn_inner",
			"page_id": "page_market",
			"x": 3,
			"y": 4,
		},
		rm,
	)
	if not _simulate_map_reconcile(state_svc, rm, map_plan):
		push_error("reconcile: expected location travel to apply after partial hook")
		return 1
	if str(state_svc.get_mainrole().get("current_key_node_id", "")) != "kn_inner":
		push_error(
			"reconcile: expected kn_inner after reconcile, got %s"
			% str(state_svc.get_mainrole().get("current_key_node_id", ""))
		)
		return 1
	return 0


func _test_reconcile_skips_same_place() -> int:
	var rm := _make_read_model()
	var state_svc := _make_state_with_mainrole(rm)
	var map_plan := LocationTravelPlannerScript.plan_map_cell_travel(
		{
			"needs_travel": false,
			"to_loc": {"region_id": "region_market", "key_node_id": "kn_shallow"},
		},
		rm,
	)
	if _simulate_map_reconcile(state_svc, rm, map_plan):
		push_error("reconcile: should not apply when needs_travel is false")
		return 1
	if str(state_svc.get_mainrole().get("current_key_node_id", "")) != "kn_shallow":
		push_error("reconcile: location should remain unchanged")
		return 1
	return 0


func _test_needs_map_cell_travel_same_region_terrain() -> int:
	var rm := _make_read_model()
	rm.mainrole = {
		"current_region_id": "region_market",
		"current_key_node_id": "",
		"current_map_cell": {},
	}
	var map_page := rm.get_map_page("page_market")
	var target := LocationServiceScript.resolve_map_cell_travel_target(
		rm,
		map_page,
		{"x": 15, "y": 9, "name": "浅地下水脉", "type": "地下水脉"},
	)
	if not target.get("needs_travel", false):
		push_error("terrain cell: expected needs_travel true for same region without key_node")
		return 1
	return 0


func _test_parse_map_travel_from_player_text() -> int:
	var rm := _make_read_model()
	rm.mainrole = {
		"current_region_id": "region_market",
		"current_key_node_id": "",
	}
	var parsed := LocationTravelPlannerScript.parse_map_travel_from_player_text(
		"你准备去浅地下水脉（16,10）",
		rm,
	)
	if not parsed.get("needs_travel", false):
		push_error("parse text: expected needs_travel true")
		return 1
	if int(parsed.get("x", -1)) != 15 or int(parsed.get("y", -1)) != 9:
		push_error("parse text: bad coords x=%s y=%s" % [str(parsed.get("x")), str(parsed.get("y"))])
		return 1
	return 0


func _test_apply_map_cell_travel_persists_cell() -> int:
	var rm := _make_read_model()
	rm.mainrole = {
		"current_region_id": "region_market",
		"current_key_node_id": "",
	}
	var state_svc := _make_state_with_mainrole(rm)
	var result := state_svc.apply_map_cell_travel(
		{"region_id": "region_market", "key_node_id": ""},
		"page_market",
		15,
		9,
		["region_market"],
		rm,
	)
	if not result.get("ok", false):
		push_error("apply_map_cell_travel: expected ok")
		return 1
	var cell: Variant = state_svc.get_mainrole().get("current_map_cell", null)
	if not cell is Dictionary:
		push_error("apply_map_cell_travel: missing current_map_cell")
		return 1
	if str(cell.get("page_id", "")) != "page_market":
		push_error("apply_map_cell_travel: bad page_id")
		return 1
	if int(cell.get("x", -1)) != 15 or int(cell.get("y", -1)) != 9:
		push_error("apply_map_cell_travel: bad stored coords")
		return 1
	return 0
