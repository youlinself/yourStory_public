## talked_npc_ids 追踪与同处 NPC 查询
extends SceneTree

const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const PlayerCommandResolverScript := preload("res://src/game/logic/input/player_command_resolver.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_record_talked_npc_dedupes()
	failed += _test_get_talked_npcs()
	failed += _test_get_same_place_npcs_includes_non_nearby()
	failed += _test_resolve_talk_npc_id()
	failed += _test_favorability_delta()
	failed += _test_get_npc_favorability()
	if failed == 0:
		print("[OK] talked npc tracking tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _make_read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {
		"id": "hero",
		"current_region_id": "region_a",
		"current_key_node_id": "kn_market",
	}
	rm.npc_db = {
		"npcs": {
			"hero": {"id": "hero", "name": "主角"},
			"npc_near": {
				"id": "npc_near",
				"name": "近处 NPC",
				"current_region_id": "region_a",
				"current_key_node_id": "kn_market",
			},
			"npc_far": {
				"id": "npc_far",
				"name": "远处 NPC",
				"current_region_id": "region_b",
				"current_key_node_id": "kn_other",
			},
			"npc_same_not_nearby": {
				"id": "npc_same_not_nearby",
				"name": "同处未接触",
				"current_region_id": "region_a",
				"current_key_node_id": "kn_market",
			},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["nearby_npc_ids"] = ["npc_near"]
	rm.game_state["talked_npc_ids"] = ["npc_near", "npc_far"]
	return rm


func _test_record_talked_npc_dedupes() -> int:
	var state := RuntimeDbSchemas.empty_game_state()
	RuntimeDbSchemas.record_talked_npc(state, "npc_a")
	RuntimeDbSchemas.record_talked_npc(state, "npc_a")
	RuntimeDbSchemas.record_talked_npc(state, "npc_b")
	var ids: Variant = state.get("talked_npc_ids", [])
	if not ids is Array or ids.size() != 2:
		push_error("record_talked_npc: expected 2 ids, got %s" % str(ids))
		return 1
	return 0


func _test_get_talked_npcs() -> int:
	var rm := _make_read_model()
	var talked := rm.get_talked_npcs()
	if talked.size() != 2:
		push_error("get_talked_npcs: expected 2, got %d" % talked.size())
		return 1
	var ids: Array[String] = []
	for npc in talked:
		ids.append(str(npc.get("id", "")))
	if "npc_near" not in ids or "npc_far" not in ids:
		push_error("get_talked_npcs: unexpected ids %s" % str(ids))
		return 1
	if "hero" in ids:
		push_error("get_talked_npcs: should exclude protagonist")
		return 1
	return 0


func _test_get_same_place_npcs_includes_non_nearby() -> int:
	var rm := _make_read_model()
	var same_place := rm.get_same_place_npcs()
	if same_place.size() != 2:
		push_error("get_same_place_npcs: expected 2, got %d" % same_place.size())
		return 1
	var ids: Array[String] = []
	for npc in same_place:
		ids.append(str(npc.get("id", "")))
	if "npc_same_not_nearby" not in ids:
		push_error("get_same_place_npcs: missing non-nearby co-located npc")
		return 1
	if "npc_far" in ids:
		push_error("get_same_place_npcs: should exclude far npc")
		return 1
	var interactable := rm.get_interactable_npcs()
	if interactable.size() != 1:
		push_error("get_interactable_npcs: still filtered by nearby pool, got %d" % interactable.size())
		return 1
	return 0


func _test_resolve_talk_npc_id() -> int:
	var rm := _make_read_model()
	rm.game_state["nearby_npc_ids"] = ["npc_near"]
	var resolver := PlayerCommandResolverScript.new()
	var resolved: Dictionary = resolver.resolve("/对话 npc_near", rm)
	if not resolved.get("ok", false):
		push_error("resolve talk: %s" % str(resolved.get("error", "")))
		return 1
	if str(resolved.get("talk_npc_id", "")) != "npc_near":
		push_error("resolve talk: expected talk_npc_id npc_near, got %s" % str(resolved.get("talk_npc_id", "")))
		return 1
	var chip_id := LocationServiceScript.resolve_talk_target_npc_id("与近处 NPC搭话", rm)
	if chip_id != "npc_near":
		push_error("resolve chip talk: expected npc_near, got %s" % chip_id)
		return 1
	return 0


func _test_favorability_delta() -> int:
	var state := RuntimeDbSchemas.empty_game_state()
	RuntimeDbSchemas.apply_npc_favorability_delta(state, "npc_a", 5)
	RuntimeDbSchemas.apply_npc_favorability_delta(state, "npc_a", -2)
	RuntimeDbSchemas.apply_npc_favorability_delta(state, "npc_b", -3)
	if RuntimeDbSchemas.get_npc_favorability_value(state, "npc_a") != 3:
		push_error("favorability delta: npc_a expected 3")
		return 1
	if RuntimeDbSchemas.get_npc_favorability_value(state, "npc_b") != -3:
		push_error("favorability delta: npc_b expected -3")
		return 1
	return 0


func _test_get_npc_favorability() -> int:
	var rm := _make_read_model()
	rm.game_state["npc_favorability"] = {"npc_near": 8, "npc_far": -4}
	if rm.get_npc_favorability("npc_near") != 8:
		push_error("get_npc_favorability: expected 8")
		return 1
	if rm.get_npc_favorability("npc_missing") != 0:
		push_error("get_npc_favorability: missing should be 0")
		return 1
	return 0
