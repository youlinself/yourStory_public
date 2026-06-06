## 世界初始化断点续跑（`godot --headless -s tests/game_world_initializer_resume_test.gd`）
extends SceneTree

const PathsScript := preload("res://src/game_running_file_manage/game_data_paths.gd")
const WorldInitDraftScript := preload("res://src/novel_config/world_init_draft.gd")

const TEST_ROOT := "user://_test_world_init_resume/"
const SAMPLE_WORLD := {
	"nature_env": {"weather": "晴"},
	"people_env": {},
	"social_env": {},
}


func _initialize() -> void:
	PathsScript.set_data_root_dir(TEST_ROOT)
	GameRunningFileManager.clear_all_runtime_files()

	var failed := 0
	failed += _test_detect_no_checkpoint()
	failed += _test_detect_resume_at_phase_3()
	failed += _test_detect_novel_type_mismatch()
	failed += _test_load_validated_skills_db()
	failed += _test_clear_from_phase_3_keeps_phase_12()
	failed += _test_draft_checkpoint_substeps()
	failed += _test_clear_phase3_final_outputs_keeps_draft()
	failed += _test_clear_all_removes_phase12_drafts()
	failed += _test_clear_from_phase2_keeps_base_draft()

	GameRunningFileManager.clear_all_runtime_files()
	PathsScript.set_data_root_dir("user://")

	if failed == 0:
		print("[OK] game_world_initializer resume tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_detect_no_checkpoint() -> int:
	if GameWorldInitializer.detect_start_phase("历史") != 1:
		push_error("empty runtime should start at phase 1")
		return 1
	return 0


func _test_detect_resume_at_phase_3() -> int:
	_write_base_config("历史")
	_write_skills_db()
	if GameWorldInitializer.detect_start_phase("历史") != 3:
		push_error("valid phase 1+2 should resume at phase 3")
		return 1
	if GameWorldInitializer.load_validated_base_config("历史") == null:
		push_error("load_validated_base_config should succeed")
		return 1
	return 0


func _test_detect_novel_type_mismatch() -> int:
	GameRunningFileManager.clear_all_runtime_files()
	_write_base_config("科幻")
	_write_skills_db()
	if GameWorldInitializer.detect_start_phase("历史") != 1:
		push_error("novel_type mismatch should start at phase 1")
		return 1
	return 0


func _test_load_validated_skills_db() -> int:
	GameRunningFileManager.clear_all_runtime_files()
	if GameWorldInitializer.load_validated_skills_db() != null:
		push_error("missing skills_db should be null")
		return 1
	_write_skills_db()
	var db: Variant = GameWorldInitializer.load_validated_skills_db()
	if db == null:
		push_error("valid skills_db should load")
		return 1
	return 0


func _test_clear_from_phase_3_keeps_phase_12() -> int:
	GameRunningFileManager.clear_all_runtime_files()
	_write_base_config("历史")
	_write_skills_db()
	GameRunningFileManager.save_json_data(GameRunningFileManager.WORLD_INIT_SETTING, {"map_structure": {}})
	GameRunningFileManager.save_json_data(GameRunningFileManager.MAIN_ROLE, {"id": "p1"})

	if not GameRunningFileManager.clear_from_phase(3):
		push_error("clear_from_phase(3) failed")
		return 1
	if not GameRunningFileManager.exists(GameRunningFileManager.BASE_CONFIG):
		push_error("baseConfig should remain after clear_from_phase(3)")
		return 1
	if not GameRunningFileManager.exists(GameRunningFileManager.SKILLS_DB):
		push_error("skills_db should remain after clear_from_phase(3)")
		return 1
	if GameRunningFileManager.exists(GameRunningFileManager.WORLD_INIT_SETTING):
		push_error("world_init_setting should be removed")
		return 1
	if GameRunningFileManager.exists(GameRunningFileManager.MAIN_ROLE):
		push_error("mainrole should be removed")
		return 1
	return 0


func _write_base_config(novel_type: String) -> void:
	GameRunningFileManager.save_json_data(
		GameRunningFileManager.BASE_CONFIG,
		{"novel_type": novel_type, "world_setting": SAMPLE_WORLD.duplicate(true)},
	)


func _test_draft_checkpoint_substeps() -> int:
	GameRunningFileManager.clear_all_runtime_files()
	_write_base_config("历史")
	_write_skills_db()
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.merge_adventure_step(
		draft,
		{"overview": "x", "regions": _two_regions(), "key_nodes": [{"id": "n1", "name": "入口"}]},
		{
			"opening_hook": "钩子",
			"immediate_goal": "目标",
			"failure_pressure": "压力",
		},
	)
	WorldInitDraftScript.save(draft)
	if GameWorldInitializer.detect_resume_world_substep() != WorldInitDraftScript.SUB_PROTAGONIST:
		push_error("draft with adventure merge should resume at protagonist substep")
		return 1
	return 0


func _test_clear_phase3_final_outputs_keeps_draft() -> int:
	GameRunningFileManager.clear_all_runtime_files()
	_write_base_config("历史")
	var draft := WorldInitDraftScript.empty_draft()
	WorldInitDraftScript.save(draft)
	GameRunningFileManager.save_json_data(GameRunningFileManager.MAIN_ROLE, {"id": "p1"})
	if not GameRunningFileManager.clear_phase3_final_outputs():
		push_error("clear_phase3_final_outputs failed")
		return 1
	if not GameRunningFileManager.exists(GameRunningFileManager.WORLD_INIT_DRAFT):
		push_error("draft should remain after clear_phase3_final_outputs")
		return 1
	if GameRunningFileManager.exists(GameRunningFileManager.MAIN_ROLE):
		push_error("mainrole should be removed")
		return 1
	return 0


func _test_clear_all_removes_phase12_drafts() -> int:
	GameRunningFileManager.clear_all_runtime_files()
	GameRunningFileManager.save_json_data(
		GameRunningFileManager.BASE_CONFIG_DRAFT,
		{"novel_type": "历史", "world_setting": {}},
	)
	GameRunningFileManager.save_json_data(
		GameRunningFileManager.SKILLS_DB_DRAFT,
		{"skills": [], "batch_skills": {}, "completed_batches": []},
	)
	if not GameRunningFileManager.clear_all_runtime_files():
		push_error("clear_all_runtime_files failed")
		return 1
	if GameRunningFileManager.exists(GameRunningFileManager.BASE_CONFIG_DRAFT):
		push_error("base_config_draft should be removed by clear_all")
		return 1
	if GameRunningFileManager.exists(GameRunningFileManager.SKILLS_DB_DRAFT):
		push_error("skills_db_draft should be removed by clear_all")
		return 1
	return 0


func _test_clear_from_phase2_keeps_base_draft() -> int:
	GameRunningFileManager.clear_all_runtime_files()
	_write_base_config("历史")
	GameRunningFileManager.save_json_data(
		GameRunningFileManager.BASE_CONFIG_DRAFT,
		{"novel_type": "历史", "world_setting": {"nature_env": {}}},
	)
	GameRunningFileManager.save_json_data(
		GameRunningFileManager.SKILLS_DB_DRAFT,
		{"skills": [], "batch_skills": {}, "completed_batches": []},
	)
	if not GameRunningFileManager.clear_from_phase(2):
		push_error("clear_from_phase(2) failed")
		return 1
	if not GameRunningFileManager.exists(GameRunningFileManager.BASE_CONFIG):
		push_error("baseConfig should remain")
		return 1
	if not GameRunningFileManager.exists(GameRunningFileManager.BASE_CONFIG_DRAFT):
		push_error("base_config_draft should remain after clear_from_phase(2)")
		return 1
	if GameRunningFileManager.exists(GameRunningFileManager.SKILLS_DB_DRAFT):
		push_error("skills_db_draft should remain for resume after clear_from_phase(2)")
		return 1
	return 0


func _two_regions() -> Array:
	return [
		{"id": "r0", "name": "r0", "adjacent_region_ids": ["r1"]},
		{"id": "r1", "name": "r1", "adjacent_region_ids": ["r0"]},
	]


func _write_skills_db() -> void:
	var skills: Dictionary = {}
	for i in 8:
		var sid := "skill_%d" % i
		skills[sid] = {"name": "技能%d" % i, "desc": "描述"}
	GameRunningFileManager.save_json_data(GameRunningFileManager.SKILLS_DB, {"skills": skills})
