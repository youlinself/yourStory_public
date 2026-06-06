## base_config_draft 分片检测（`godot --headless -s tests/base_config_draft_test.gd`）
extends SceneTree

const BaseConfigDraftScript := preload("res://src/novel_config/base_config_draft.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_detect_slices()
	failed += _test_apply_and_merge()
	failed += _test_clear_from_slice()

	if failed == 0:
		print("[OK] base_config_draft tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_detect_slices() -> int:
	var draft := BaseConfigDraftScript.empty_draft("异能流")
	if BaseConfigDraftScript.detect_next_slice(draft) != BaseConfigDraftScript.SLICE_NATURE_ENV:
		push_error("empty draft -> nature slice")
		return 1
	BaseConfigDraftScript.apply_slice(draft, BaseConfigDraftScript.SLICE_NATURE_ENV, _sample_nature())
	if BaseConfigDraftScript.detect_next_slice(draft) != BaseConfigDraftScript.SLICE_PEOPLE_ENV:
		push_error("after nature -> people slice")
		return 1
	return 0


func _test_apply_and_merge() -> int:
	var draft := BaseConfigDraftScript.empty_draft("历史")
	BaseConfigDraftScript.apply_slice(draft, 1, _sample_nature())
	BaseConfigDraftScript.apply_slice(draft, 2, _sample_people())
	BaseConfigDraftScript.apply_slice(draft, 3, _sample_social())
	if BaseConfigDraftScript.detect_next_slice(draft) <= BaseConfigDraftScript.SLICE_COUNT:
		push_error("all slices done should advance past SLICE_COUNT")
		return 1
	var base := BaseConfigDraftScript.to_base_config(draft)
	if str(base.get("novel_type", "")) != "历史":
		push_error("to_base_config novel_type mismatch")
		return 1
	var normalized := AiResponseParser.normalize_base_config_response(base, "历史")
	if not AiResponseParser.validate_base_config(normalized):
		push_error("merged base config should validate")
		return 1
	return 0


func _test_clear_from_slice() -> int:
	var draft := BaseConfigDraftScript.empty_draft("历史")
	BaseConfigDraftScript.apply_slice(draft, 1, _sample_nature())
	BaseConfigDraftScript.apply_slice(draft, 2, _sample_people())
	BaseConfigDraftScript.clear_from_slice(draft, BaseConfigDraftScript.SLICE_SOCIAL_ENV)
	var ws: Dictionary = draft.get("world_setting", {})
	if ws.has("social_env"):
		push_error("clear social should remove social_env")
		return 1
	if not ws.has("nature_env"):
		push_error("clear social should keep nature_env")
		return 1
	return 0


func _sample_nature() -> Dictionary:
	return {
		"weather": "阴雨",
		"weather_keywords": ["雨", "雾"],
		"landform": "平原",
		"start_time": "深夜",
		"start_time_keywords": ["冬", "夜"],
		"universe": "双月",
		"biome": "变异植物",
	}


func _sample_people() -> Dictionary:
	return {
		"building": "高楼",
		"traffic": "磁浮",
		"technology": "义体",
		"city&town": "分层城市",
	}


func _sample_social() -> Dictionary:
	return {
		"background": "公司统治。核心矛盾：底层与财团。",
		"politics&power": "寡头",
		"econ&prod": "贫富分化",
		"culture&customs": "赛博祭典",
		"relationships": "帮派",
		"values&beliefs": "实力至上",
	}
