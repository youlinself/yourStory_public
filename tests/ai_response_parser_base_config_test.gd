## 阶段 1 baseConfig 规范化与校验（`godot --headless -s tests/ai_response_parser_base_config_test.gd`）
extends SceneTree

const SAMPLE_WORLD := {
	"nature_env": {"weather": "阴雨连绵"},
	"people_env": {},
	"social_env": {},
}


func _initialize() -> void:
	var failed := 0
	failed += _test_mirror_base_config_field()
	failed += _test_novel_type_array_with_selected()
	failed += _test_novel_type_array_without_selected()
	failed += _test_validate_rejects_unnormalized_array()
	failed += _test_describe_parse_failure()
	failed += _test_describe_base_config_field_error()
	failed += _test_ai_client_timeout_message()
	failed += _test_parse_json_prose_returns_null()
	failed += _test_parse_json_object_ok()
	failed += _test_parse_json_fenced_ok()
	failed += _test_parse_json_with_prose_prefix()
	failed += _test_parse_json_trailing_comma_repair()
	failed += _test_parse_json_unescaped_newline_in_string()
	failed += _test_parse_json_truncated_repair()
	failed += _test_parse_json_outermost_object_with_suffix()
	failed += _test_normalize_protagonist_bare_character()
	failed += _test_normalize_map_page_bare_spec()
	failed += _test_extract_json_task_content_prefers_top_level()
	failed += _test_format_response_debug()
	failed += _test_validate_base_config_slice()
	failed += _test_normalize_base_config_slice_bare()
	failed += _test_validate_skills_batch_payload()
	failed += _test_describe_skills_batch_validation_failure()
	if failed == 0:
		print("[OK] ai_response_parser base_config tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_mirror_base_config_field() -> int:
	var raw := {
		"novel_type": "历史",
		"base_config": SAMPLE_WORLD.duplicate(true),
	}
	var normalized := AiResponseParser.normalize_base_config_response(raw, "历史")
	if not AiResponseParser.validate_base_config(normalized):
		push_error("mirror base_config: expected valid after normalize")
		return 1
	if not normalized.has("world_setting"):
		push_error("mirror base_config: missing world_setting")
		return 1
	if normalized.has("base_config"):
		push_error("mirror base_config: stray base_config key")
		return 1
	return 0


func _test_novel_type_array_with_selected() -> int:
	var raw := {
		"novel_type": ["神话", "历史", "科幻"],
		"base_config": SAMPLE_WORLD.duplicate(true),
	}
	var normalized := AiResponseParser.normalize_base_config_response(raw, "历史")
	if str(normalized.get("novel_type", "")) != "历史":
		push_error("novel_type array: expected selected '历史'")
		return 1
	if not AiResponseParser.validate_base_config(normalized):
		push_error("novel_type array: expected valid after normalize")
		return 1
	return 0


func _test_novel_type_array_without_selected() -> int:
	var raw := {
		"novel_type": ["", "武侠"],
		"world_setting": SAMPLE_WORLD.duplicate(true),
	}
	var normalized := AiResponseParser.normalize_base_config_response(raw, "历史")
	if str(normalized.get("novel_type", "")) != "武侠":
		push_error("novel_type array fallback: expected first non-empty '武侠'")
		return 1
	return 0


func _test_validate_rejects_unnormalized_array() -> int:
	var raw := {
		"novel_type": ["神话", "历史"],
		"world_setting": SAMPLE_WORLD.duplicate(true),
	}
	if AiResponseParser.validate_base_config(raw):
		push_error("validate: should reject array novel_type before normalize")
		return 1
	return 0


func _test_describe_parse_failure() -> int:
	var msg := AiResponseParser.describe_base_config_validation_failure(null, false)
	if "无法解析" not in msg:
		push_error("describe: expected parse failure message")
		return 1
	return 0


func _test_describe_base_config_field_error() -> int:
	var raw := {
		"novel_type": "历史",
		"base_config": SAMPLE_WORLD.duplicate(true),
	}
	var msg := AiResponseParser.describe_base_config_validation_failure(raw, true)
	if "base_config" not in msg or "world_setting" not in msg:
		push_error("describe: expected base_config field hint")
		return 1
	return 0


func _test_parse_json_prose_returns_null() -> int:
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text("你好，世界。这是叙事正文。")
	if parsed != null:
		push_error("parse_json_from_ai_text: prose should return null")
		return 1
	return 0


func _test_parse_json_object_ok() -> int:
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text("{\"novel_type\":\"历史\"}")
	if not parsed is Dictionary:
		push_error("parse_json_from_ai_text: expected object")
		return 1
	if str((parsed as Dictionary).get("novel_type", "")) != "历史":
		push_error("parse_json_from_ai_text: wrong field value")
		return 1
	return 0


func _test_parse_json_fenced_ok() -> int:
	var raw := "```json\n{\"ok\": true}\n```"
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if not parsed is Dictionary:
		push_error("parse_json_from_ai_text: fenced json expected object")
		return 1
	if not (parsed as Dictionary).get("ok", false):
		push_error("parse_json_from_ai_text: fenced json wrong value")
		return 1
	return 0


func _test_parse_json_with_prose_prefix() -> int:
	var raw := "好的，以下是 JSON：\n{\"novel_type\":\"历史\"}"
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if not parsed is Dictionary:
		push_error("parse_json_with_prose_prefix: expected object")
		return 1
	if str((parsed as Dictionary).get("novel_type", "")) != "历史":
		push_error("parse_json_with_prose_prefix: wrong field value")
		return 1
	return 0


func _test_parse_json_trailing_comma_repair() -> int:
	var raw := "{\n\t\"ok\": true,\n}"
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if not parsed is Dictionary:
		push_error("parse_json_trailing_comma_repair: expected object")
		return 1
	if not (parsed as Dictionary).get("ok", false):
		push_error("parse_json_trailing_comma_repair: wrong value")
		return 1
	return 0


func _test_parse_json_unescaped_newline_in_string() -> int:
	var raw := "{\"name\": \"第一行\n第二行\"}"
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if not parsed is Dictionary:
		push_error("parse_json_unescaped_newline: expected object")
		return 1
	if str((parsed as Dictionary).get("name", "")) != "第一行\n第二行":
		push_error("parse_json_unescaped_newline: wrong value")
		return 1
	return 0


func _test_parse_json_truncated_repair() -> int:
	var raw := "{\"protagonist_id\":\"p1\",\"npcs\":[{\"id\":\"p1\",\"name\":\"测试\",\"skills\":[\"skill_a\""
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if not parsed is Dictionary:
		push_error("parse_json_truncated_repair: expected object")
		return 1
	var npcs: Variant = (parsed as Dictionary).get("npcs", null)
	if not npcs is Array or (npcs as Array).is_empty():
		push_error("parse_json_truncated_repair: expected npcs array")
		return 1
	return 0


func _test_parse_json_outermost_object_with_suffix() -> int:
	var raw := (
		"说明：以下是主角卡。\n"
		+ "{\"protagonist_id\":\"p1\",\"npcs\":[{\"id\":\"p1\",\"name\":\"测试\"}]}\n"
		+ "以上完毕。"
	)
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if not parsed is Dictionary:
		push_error("parse_json_outermost_object_with_suffix: expected object")
		return 1
	if str((parsed as Dictionary).get("protagonist_id", "")) != "p1":
		push_error("parse_json_outermost_object_with_suffix: wrong protagonist_id")
		return 1
	return 0


func _test_normalize_protagonist_bare_character() -> int:
	var bare := {
		"id": "npc_hero",
		"name": "主角",
		"skills": ["skill_a"],
		"abilities": {"str": 50, "agi": 50, "con": 50, "int": 50, "mnd": 50, "cha": 50},
	}
	var normalized: Variant = AiResponseParser.normalize_world_build_substep_payload(
		AiResponseParser.WB_SUB_PROTAGONIST,
		bare,
	)
	if not normalized is Dictionary:
		push_error("normalize_protagonist: expected dict")
		return 1
	var d: Dictionary = normalized
	if str(d.get("protagonist_id", "")) != "npc_hero":
		push_error("normalize_protagonist: wrong protagonist_id")
		return 1
	var npcs: Variant = d.get("npcs", null)
	if not npcs is Array or (npcs as Array).size() != 1:
		push_error("normalize_protagonist: expected single npc")
		return 1
	return 0


func _test_normalize_map_page_bare_spec() -> int:
	var bare := {
		"id": "map_region_a",
		"parent_type": "region",
		"parent_id": "region_a",
		"width": 10,
		"height": 10,
	}
	var normalized: Variant = AiResponseParser.normalize_world_build_substep_payload(
		AiResponseParser.WB_SUB_MAP_PAGE,
		bare,
	)
	if not normalized is Dictionary:
		push_error("normalize_map_page: expected dict")
		return 1
	if not (normalized as Dictionary).has("map_page"):
		push_error("normalize_map_page: expected map_page wrapper")
		return 1
	return 0


func _test_extract_json_task_content_prefers_top_level() -> int:
	var response := {
		"choices": [{
			"message": {
				"content": "好的，以下是生成的 JSON：这不是有效 JSON",
			},
		}],
		"content": "{\"novel_type\":\"历史\"}",
	}
	var text := AiResponseParser.extract_json_task_content(response)
	if text != "{\"novel_type\":\"历史\"}":
		push_error("extract_json_task_content: expected top-level cleaned JSON")
		return 1
	return 0


func _test_format_response_debug() -> int:
	var response := {
		"error": "rate_limit",
		"choices": [{"message": {"content": "x"}}],
		"content": "y",
	}
	var debug := AiResponseParser.format_response_debug(response)
	if "api_error" not in debug or "choice_content_len" not in debug:
		push_error("format_response_debug: missing expected fields")
		return 1
	return 0


func _test_validate_base_config_slice() -> int:
	var nature := {
		"nature_env": {
			"weather": "晴",
			"weather_keywords": ["晴"],
			"landform": "平原",
			"start_time": "正午",
			"start_time_keywords": ["夏"],
			"universe": "单星",
			"biome": "草原",
		},
	}
	if not AiResponseParser.validate_base_config_slice(1, nature):
		push_error("validate_base_config_slice: nature should pass")
		return 1
	if AiResponseParser.validate_base_config_slice(1, {"people_env": {}}):
		push_error("validate_base_config_slice: wrong key should fail")
		return 1
	return 0


func _test_normalize_base_config_slice_bare() -> int:
	var bare := {
		"weather": "雨",
		"weather_keywords": ["雨"],
		"landform": "山",
		"start_time": "夜",
		"start_time_keywords": ["冬"],
		"universe": "月",
		"biome": "林",
	}
	var normalized: Variant = AiResponseParser.normalize_base_config_slice_payload(1, bare)
	if not normalized is Dictionary:
		push_error("normalize bare slice: expected dict")
		return 1
	if not (normalized as Dictionary).has("nature_env"):
		push_error("normalize bare slice: expected nature_env wrapper")
		return 1
	return 0


func _test_validate_skills_batch_payload() -> int:
	var payload := {
		"skills": [
			{"id": "s1", "name": "A", "desc": "八个字左右的描述"},
			{"id": "s2", "name": "B", "desc": "八个字左右的描述"},
			{"id": "s3", "name": "C", "desc": "八个字左右的描述"},
		],
	}
	if not AiResponseParser.validate_skills_batch_payload(payload):
		push_error("skills batch 3 items should pass")
		return 1
	var too_few := {"skills": [{"id": "s1", "name": "A", "desc": "八个字左右的描述"}]}
	if AiResponseParser.validate_skills_batch_payload(too_few):
		push_error("skills batch 1 item should fail")
		return 1
	return 0


func _test_describe_skills_batch_validation_failure() -> int:
	var bare_array := [{"id": "s1", "name": "A", "desc": "八个字左右的描述"}]
	if AiResponseParser.describe_skills_batch_validation_failure(bare_array).is_empty():
		push_error("bare array should fail validation")
		return 1

	var skill_map := {
		"skills": {
			"s1": {"id": "s1", "name": "A", "desc": "八个字左右的描述"},
		},
	}
	var map_msg := AiResponseParser.describe_skills_batch_validation_failure(skill_map)
	if "对象 map" not in map_msg:
		push_error("skill map should mention object map")
		return 1

	var too_many := {"skills": []}
	for i in 8:
		too_many["skills"].append({
			"id": "s%d" % i,
			"name": "N",
			"desc": "八个字左右的描述",
		})
	var count_msg := AiResponseParser.describe_skills_batch_validation_failure(too_many)
	if "8" not in count_msg:
		push_error("too many skills should mention count")
		return 1

	var bad_desc := {
		"skills": [
			{"id": "s1", "name": "A", "description": "用了错误字段名"},
			{"id": "s2", "name": "B", "desc": "八个字左右的描述"},
			{"id": "s3", "name": "C", "desc": "八个字左右的描述"},
		],
	}
	var desc_msg := AiResponseParser.describe_skills_batch_validation_failure(bad_desc)
	if "description" not in desc_msg:
		push_error("description alias should be detected")
		return 1

	var batch_msg := AiResponseParser.describe_skills_batch_failure(1, true, too_many)
	if "阶段 2 批次 1" not in batch_msg or "校验失败" not in batch_msg:
		push_error("batch failure should include batch label")
		return 1
	return 0


func _test_ai_client_timeout_message() -> int:
	var msg := AIClient.describe_request_result(HTTPRequest.RESULT_TIMEOUT)
	if "超时" not in msg:
		push_error("describe_request_result: expected timeout hint")
		return 1
	if not AIClient.is_timeout_result(HTTPRequest.RESULT_TIMEOUT):
		push_error("is_timeout_result: expected true for RESULT_TIMEOUT")
		return 1
	if AIClient.is_timeout_result(AIClient.HTTP_RESULT_NONE):
		push_error("is_timeout_result: expected false for HTTP_RESULT_NONE")
		return 1
	return 0
