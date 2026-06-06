## 阶段 2/3 解析与校验回归（`godot --headless -s tests/ai_response_parser_skills_world_test.gd`）
extends SceneTree


func _initialize() -> void:
	var failed := 0
	failed += _test_key_npc_requires_region_and_scene()
	failed += _test_key_npc_skills_count()
	failed += _test_key_npc_invalid_skill_id()
	failed += _test_protagonist_invalid_skill_id_message()
	failed += _test_protagonist_skills_count_bounds()
	failed += _test_normalize_skill_fuzzy_name()
	failed += _test_normalize_skill_name_to_id()
	failed += _test_normalize_skill_object_to_id()
	failed += _test_protagonist_multi_npc_collapses()
	failed += _test_world_init_rejects_duplicate_npc_id()

	if failed == 0:
		print("[OK] ai_response_parser skills/world regression tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _sample_skills_db() -> Dictionary:
	return {
		"skills": {
			"s1": {"id": "s1", "name": "A", "desc": "八个字左右的描述"},
			"s2": {"id": "s2", "name": "B", "desc": "八个字左右的描述"},
			"s3": {"id": "s3", "name": "C", "desc": "八个字左右的描述"},
			"s4": {"id": "s4", "name": "D", "desc": "八个字左右的描述"},
		},
	}


func _sample_key_npc(extra: Dictionary = {}) -> Dictionary:
	var npc := {
		"id": "npc_key_1",
		"current_region_id": "region_a",
		"initial_scene": "关键 NPC 开场",
		"skills": ["s1", "s2", "s3", "s4"],
	}
	for key in extra:
		npc[key] = extra[key]
	return {"npcs": [npc]}


func _test_key_npc_requires_region_and_scene() -> int:
	var skills_db := _sample_skills_db()
	var payload := _sample_key_npc()
	if not AiResponseParser.validate_single_key_npc_payload(payload, skills_db, []):
		push_error("valid key npc should pass")
		return 1

	var missing_region := _sample_key_npc()
	((missing_region["npcs"] as Array)[0] as Dictionary).erase("current_region_id")
	var region_msg := AiResponseParser.describe_single_key_npc_validation_failure(
		missing_region, skills_db, [],
	)
	if "current_region_id" not in region_msg:
		push_error("missing current_region_id should be reported")
		return 1
	return 0


func _test_key_npc_skills_count() -> int:
	var skills_db := _sample_skills_db()
	var two_skills := _sample_key_npc({"skills": ["s1", "s2"]})
	if not AiResponseParser.validate_single_key_npc_payload(two_skills, skills_db, []):
		push_error("two skills should pass with min 1")
		return 1
	var empty_skills := _sample_key_npc({"skills": []})
	var msg := AiResponseParser.describe_single_key_npc_validation_failure(empty_skills, skills_db, [])
	if "不足" not in msg:
		push_error("empty skills should fail with count message")
		return 1
	return 0


func _test_key_npc_invalid_skill_id() -> int:
	var skills_db := _sample_skills_db()
	var bad_skill := _sample_key_npc({"skills": ["s1", "s2", "s3", "missing_skill"]})
	if AiResponseParser.validate_single_key_npc_payload(bad_skill, skills_db, []):
		push_error("invalid skill id should fail")
		return 1
	return 0


func _test_protagonist_invalid_skill_id_message() -> int:
	var skills_db := _sample_skills_db()
	var payload := {
		"protagonist_id": "npc_hero",
		"npcs": [{
			"id": "npc_hero",
			"性别": "女",
			"族群": "人类",
			"initial_scene": "开场",
			"skills": ["s1", "剑术", "missing_skill"],
		}],
	}
	var msg := AiResponseParser.describe_protagonist_validation_failure(payload, skills_db)
	if "不在技能库中" not in msg:
		push_error("invalid protagonist skills should mention missing entries")
		return 1
	if "剑术" not in msg and "missing_skill" not in msg:
		push_error("invalid protagonist skills message should list bad entries")
		return 1
	if "s1" not in msg:
		push_error("invalid protagonist skills message should show current skills")
		return 1
	return 0


func _test_normalize_skill_fuzzy_name() -> int:
	var skills_db := {
		"skills": {
			"s1": {"id": "s1", "name": "空中 监视", "desc": "八个字左右的描述"},
		},
	}
	var npc := {"skills": ["空中监视"]}
	var normalized := AiResponseParser.normalize_role_card_npc(npc, skills_db)
	var skills: Array = normalized.get("skills", [])
	if skills.size() != 1 or skills[0] != "s1":
		push_error("fuzzy skill name should map to id")
		return 1
	return 0


func _test_protagonist_skills_count_bounds() -> int:
	var skills_db := _sample_skills_db()
	var payload := {
		"protagonist_id": "npc_hero",
		"npcs": [{
			"id": "npc_hero",
			"性别": "女",
			"族群": "人类",
			"initial_scene": "开场",
			"skills": ["s1", "s2", "s3", "s4", "s5", "s6", "s7"],
		}],
	}
	var msg := AiResponseParser.describe_protagonist_validation_failure(payload, skills_db)
	if "过多" not in msg:
		push_error("too many protagonist skills should fail with count message")
		return 1
	return 0


func _test_normalize_skill_name_to_id() -> int:
	var skills_db := _sample_skills_db()
	var npc := {"skills": ["A", "B"]}
	var normalized := AiResponseParser.normalize_role_card_npc(npc, skills_db)
	var skills: Array = normalized.get("skills", [])
	if skills.size() != 2 or skills[0] != "s1" or skills[1] != "s2":
		push_error("skill names should map to ids")
		return 1
	return 0


func _test_normalize_skill_object_to_id() -> int:
	var skills_db := _sample_skills_db()
	var npc := {"skills": [{"id": "s3"}, {"name": "D"}]}
	var normalized := AiResponseParser.normalize_role_card_npc(npc, skills_db)
	var skills: Array = normalized.get("skills", [])
	if skills.size() != 2 or skills[0] != "s3" or skills[1] != "s4":
		push_error("skill objects should map to ids")
		return 1
	return 0


func _test_protagonist_multi_npc_collapses() -> int:
	var skills_db := _sample_skills_db()
	var payload := {
		"protagonist_id": "npc_hero",
		"npcs": [
			{
				"id": "npc_other",
				"性别": "男",
				"族群": "人类",
				"initial_scene": "其他",
				"skills": ["s1"],
			},
			{
				"id": "npc_hero",
				"性别": "女",
				"族群": "精灵",
				"initial_scene": "主角开场",
				"skills": ["A", "B"],
			},
		],
	}
	var normalized: Variant = AiResponseParser.normalize_world_build_substep_payload(
		AiResponseParser.WB_SUB_PROTAGONIST,
		payload,
		skills_db,
	)
	if not normalized is Dictionary:
		push_error("multi npc protagonist: expected dict")
		return 1
	var d: Dictionary = normalized
	var npcs: Variant = d.get("npcs", null)
	if not npcs is Array or (npcs as Array).size() != 1:
		push_error("multi npc protagonist: expected single npc")
		return 1
	var hero: Dictionary = (npcs as Array)[0]
	if str(hero.get("id", "")) != "npc_hero":
		push_error("multi npc protagonist: wrong hero picked")
		return 1
	if not AiResponseParser.validate_protagonist_payload(normalized, skills_db):
		push_error("collapsed protagonist should validate")
		return 1
	return 0


func _test_world_init_rejects_duplicate_npc_id() -> int:
	var skills_db := _sample_skills_db()
	var world_init := {
		"protagonist_id": "npc_hero",
		"map_structure": {"overview": "x", "regions": [], "key_nodes": []},
		"npcs": [
			{
				"id": "npc_hero",
				"性别": "女",
				"族群": "人类",
				"initial_scene": "开场",
				"skills": ["s1"],
			},
			{
				"id": "npc_hero",
				"current_region_id": "region_a",
				"initial_scene": "重复",
				"skills": ["s2"],
			},
		],
	}
	var msg := AiResponseParser.describe_world_init_validation_failure(world_init, skills_db)
	if "重复" not in msg:
		push_error("duplicate npc id should be reported")
		return 1
	return 0
