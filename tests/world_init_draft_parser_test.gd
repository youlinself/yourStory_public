## world_init_draft + 分步校验（`godot --headless -s tests/world_init_draft_parser_test.gd`）
extends SceneTree

const WorldInitDraftScript := preload("res://src/novel_config/world_init_draft.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_detect_substeps()
	failed += _test_append_npcs_dedup()
	failed += _test_clear_from_substep_3()
	failed += _test_validate_adventure_map()
	failed += _test_validate_protagonist()
	failed += _test_validate_npc_batch()
	failed += _test_micro_substep_detection()
	failed += _test_missing_region_pages()
	failed += _test_clear_from_substep_map_page()
	failed += _test_merge_adventure()
	failed += _test_to_world_init_includes_adventure()
	failed += _test_merge_builds_map_pages()

	if failed == 0:
		print("[OK] world_init_draft_parser tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_detect_substeps() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_MAP_SKELETON:
		push_error("empty draft should start at map skeleton")
		return 1
	WorldInitDraftScript.merge_adventure_step(draft, _sample_map(), _sample_adventure())
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_PROTAGONIST:
		push_error("after adventure merge -> protagonist substep")
		return 1
	WorldInitDraftScript.set_protagonist(draft, "npc_hero", {"id": "npc_hero", "skills": ["s1"]})
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_KEY_NPC:
		push_error("need key npcs -> key npc substep")
		return 1
	WorldInitDraftScript.append_npcs(
		draft,
		[{"id": "npc_a", "skills": ["s1"]}, {"id": "npc_b", "skills": ["s1"]}],
	)
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_STARTER_ITEMS:
		push_error("after key npcs -> starter items substep")
		return 1
	WorldInitDraftScript.mark_starter_items_materialized(draft)
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_FINALIZE:
		push_error("after starter items -> finalize substep")
		return 1
	return 0


func _test_append_npcs_dedup() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.append_npcs(draft, [{"id": "a", "skills": ["s1"]}])
	WorldInitDraftScript.append_npcs(draft, [{"id": "a", "skills": ["s1"]}, {"id": "b", "skills": ["s1"]}])
	var npcs: Array = draft.get("npcs", [])
	if npcs.size() != 2:
		push_error("append_npcs should dedupe by id")
		return 1
	return 0


func _test_clear_from_substep_3() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.merge_adventure_step(draft, _sample_map(), _sample_adventure())
	WorldInitDraftScript.set_protagonist(draft, "npc_hero", {"id": "npc_hero", "skills": ["s1"]})
	WorldInitDraftScript.append_npcs(draft, [{"id": "npc_a", "skills": ["s1"]}])
	WorldInitDraftScript.clear_from_substep(draft, 3)
	var npcs: Array = draft.get("npcs", [])
	if npcs.size() != 1 or str(npcs[0].get("id", "")) != "npc_hero":
		push_error("clear_from_substep(3) should keep protagonist only")
		return 1
	return 0


func _test_validate_adventure_map() -> int:
	if AiResponseParser.validate_adventure_map_structure(null):
		push_error("null map should fail")
		return 1
	if not AiResponseParser.validate_map_skeleton(_sample_map()):
		push_error("sample map skeleton should pass")
		return 1
	if not AiResponseParser.validate_adventure_map_step(_sample_map(), _sample_adventure()):
		push_error("sample adventure map step should pass")
		return 1
	return 0


func _test_micro_substep_detection() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.set_map_skeleton(draft, _sample_map())
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_MAP_PAGE:
		push_error("skeleton -> map page")
		return 1
	WorldInitDraftScript.set_adventure_module(draft, _sample_adventure())
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_MAP_PAGE:
		push_error("map pages must be completed before faction shadows")
		return 1
	return 0


func _test_missing_region_pages() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.set_map_skeleton(draft, _sample_map())
	var missing := WorldInitDraftScript.missing_region_page_ids(draft)
	if missing.size() != 2:
		push_error("two regions should need two map pages")
		return 1
	return 0


func _test_clear_from_substep_map_page() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.merge_adventure_step(draft, _sample_map(), _sample_adventure())
	WorldInitDraftScript.clear_from_substep(draft, WorldInitDraftScript.SUB_MAP_PAGE)
	var map: Dictionary = draft.get("map_structure", {})
	var pages: Array = map.get("map_pages", [])
	if not pages.is_empty():
		push_error("clear map page substep should remove pages")
		return 1
	if WorldInitDraftScript.detect_next_substep(draft) != WorldInitDraftScript.SUB_MAP_PAGE:
		push_error("should resume at map page after clear")
		return 1
	return 0


func _test_validate_protagonist() -> int:
	var skills_db := _sample_skills_db()
	var payload := _sample_protagonist_payload()
	if not AiResponseParser.validate_protagonist_payload(payload, skills_db):
		push_error("protagonist payload should pass")
		return 1
	var missing_scene := _sample_protagonist_payload()
	(missing_scene["npcs"] as Array)[0] = (missing_scene["npcs"] as Array)[0].duplicate(true)
	((missing_scene["npcs"] as Array)[0] as Dictionary).erase("initial_scene")
	if AiResponseParser.validate_protagonist_payload(missing_scene, skills_db):
		push_error("protagonist without initial_scene should fail")
		return 1
	return 0


func _test_validate_npc_batch() -> int:
	var skills_db := {"skills": {"s1": {"name": "A", "desc": "d"}}}
	var payload := {"npcs": [{"id": "npc_a", "skills": ["s1"]}, {"id": "npc_b", "skills": ["s1"]}]}
	if not AiResponseParser.validate_npc_batch(payload, skills_db, [], true):
		push_error("key npc batch should pass")
		return 1
	return 0


func _test_merge_adventure() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.merge_adventure_step(draft, _sample_map(), _sample_adventure(), [])
	if draft.get("adventure_module", {}).is_empty():
		push_error("adventure_module should be set")
		return 1
	return 0


func _test_to_world_init_includes_adventure() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.merge_adventure_step(draft, _sample_map(), _sample_adventure())
	var world := WorldInitDraftScript.to_world_init(draft)
	if not world.has("adventure_module"):
		push_error("to_world_init should include adventure_module")
		return 1
	return 0


func _test_merge_builds_map_pages() -> int:
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.merge_adventure_step(draft, _sample_map(), _sample_adventure())
	var map: Dictionary = draft.get("map_structure", {})
	var pages: Array = map.get("map_pages", [])
	if pages.is_empty():
		push_error("merge should synthesize map_pages for regions")
		return 1
	var page: Dictionary = pages[0]
	var cells: Array = page.get("cells", [])
	if cells.is_empty():
		push_error("cells should be built")
		return 1
	return 0


func _sample_map() -> Dictionary:
	return {
		"overview": "test",
		"regions": [
			{"id": "region_a", "name": "A", "adjacent_region_ids": ["region_b"]},
			{"id": "region_b", "name": "B", "adjacent_region_ids": ["region_a"]},
		],
		"key_nodes": [
			{"id": "node_1", "name": "入口", "region_id": "region_a"},
			{"id": "node_2", "name": "大厅", "region_id": "region_a"},
		],
	}


func _sample_adventure() -> Dictionary:
	return {
		"opening_hook": "钩子",
		"immediate_goal": "目标",
		"failure_pressure": "压力",
	}


func _sample_skills_db() -> Dictionary:
	return {
		"skills": {
			"s1": {"id": "s1", "name": "A", "desc": "八个字左右的描述"},
			"s2": {"id": "s2", "name": "B", "desc": "八个字左右的描述"},
			"s3": {"id": "s3", "name": "C", "desc": "八个字左右的描述"},
			"s4": {"id": "s4", "name": "D", "desc": "八个字左右的描述"},
		},
	}


func _sample_protagonist_payload() -> Dictionary:
	return {
		"protagonist_id": "npc_hero",
		"npcs": [{
			"id": "npc_hero",
			"性别": "男",
			"族群": "人类",
			"initial_scene": "开场场景描述",
			"skills": ["s1", "s2", "s3", "s4"],
		}],
	}
