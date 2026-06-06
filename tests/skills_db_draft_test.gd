## skills_db_draft 批次合并（`godot --headless -s tests/skills_db_draft_test.gd`）
extends SceneTree

const SkillsDbDraftScript := preload("res://src/novel_config/skills_db_draft.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_detect_batches()
	failed += _test_append_dedup()
	failed += _test_clear_from_batch()

	if failed == 0:
		print("[OK] skills_db_draft tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_detect_batches() -> int:
	var draft := SkillsDbDraftScript.empty_draft()
	if SkillsDbDraftScript.detect_next_batch(draft) != SkillsDbDraftScript.BATCH_COMBAT:
		push_error("empty -> combat batch")
		return 1
	SkillsDbDraftScript.append_batch(draft, 1, _sample_skills(3, "combat"))
	if SkillsDbDraftScript.detect_next_batch(draft) != SkillsDbDraftScript.BATCH_SOCIAL:
		push_error("after batch1 -> social")
		return 1
	return 0


func _test_append_dedup() -> int:
	var draft := SkillsDbDraftScript.empty_draft()
	SkillsDbDraftScript.append_batch(draft, 1, _sample_skills(3, "a"))
	SkillsDbDraftScript.append_batch(draft, 2, _sample_skills(3, "b"))
	SkillsDbDraftScript.append_batch(draft, 3, _sample_skills(3, "c"))
	if SkillsDbDraftScript.skill_count(draft) != 9:
		push_error("expected 9 merged skills")
		return 1
	var payload := SkillsDbDraftScript.to_skills_payload(draft)
	if not AiResponseParser.validate_skills_payload(payload):
		push_error("merged payload should pass validate_skills_payload")
		return 1
	return 0


func _test_clear_from_batch() -> int:
	var draft := SkillsDbDraftScript.empty_draft()
	SkillsDbDraftScript.append_batch(draft, 1, _sample_skills(3, "x"))
	SkillsDbDraftScript.append_batch(draft, 2, _sample_skills(3, "y"))
	SkillsDbDraftScript.clear_from_batch(draft, SkillsDbDraftScript.BATCH_SOCIAL)
	if SkillsDbDraftScript.skill_count(draft) != 3:
		push_error("clear batch2 should keep batch1 skills only")
		return 1
	if SkillsDbDraftScript.detect_next_batch(draft) != SkillsDbDraftScript.BATCH_SOCIAL:
		push_error("should resume at batch social")
		return 1
	return 0


func _sample_skills(count: int, prefix: String) -> Array:
	var out: Array = []
	for i in count:
		out.append({
			"id": "%s_skill_%d" % [prefix, i],
			"name": "技能%d" % i,
			"desc": "八个字左右的描述",
		})
	return out
