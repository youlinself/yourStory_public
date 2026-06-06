## 叙事实体守卫：未登记实体且无 DYN_ADD 时告警
extends SceneTree

const GuardScript := preload("res://src/game/logic/narrative/narrative_entity_guard.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_warns_orphan_npc()
	failed += _test_silent_when_dyn_add_present()
	if failed == 0:
		print("[OK] narrative entity guard tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_warns_orphan_npc() -> int:
	var rm := _read_model()
	var story := "赵明：「周德海，工人文化宫馆长，住在南郊康宁小区。」"
	var warnings := GuardScript.check_orphan_entities(story, rm)
	if warnings.is_empty():
		push_error("guard: expected orphan NPC warning")
		return 1
	return 0


func _test_silent_when_dyn_add_present() -> int:
	var rm := _read_model()
	var story := "周德海递来纸条。[[DYN_ADD:NPC|周德海，证人]]"
	var warnings := GuardScript.check_orphan_entities(story, rm)
	for w in warnings:
		if str(w).find("周德海") >= 0:
			push_error("guard: should not warn when DYN_ADD present: %s" % w)
			return 1
	return 0


func _read_model() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {"name": "主角"}
	rm.map_db = {"map_structure": {"regions": [], "key_nodes": []}}
	rm.npc_db = {"npcs": {}}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	return rm
