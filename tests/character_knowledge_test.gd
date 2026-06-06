## character_knowledge：探知解锁、可见档案、hook discoveries 规范化
extends SceneTree

const KnowledgeScript := preload("res://src/game/logic/data/character_knowledge.gd")
const ProfileDisplayScript := preload("res://src/game/logic/data/character_profile_display.gd")
const HookNormalizerScript := preload("res://src/game/logic/narrative/narrative_hook_normalizer.gd")
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const RuntimeDbSchemas := preload("res://src/game_running_file_manage/runtime_db_schemas.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_reveal_and_visible_profile()
	failed += _test_age_zero_not_visible_when_revealed()
	failed += _test_ensure_nearby_npc_baseline()
	failed += _test_normalize_discoveries_resolves_name()
	failed += _test_profile_display_only_revealed_fields()
	if failed == 0:
		print("[OK] character knowledge tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_reveal_and_visible_profile() -> int:
	var store := KnowledgeScript.seed_initial("hero", ["npc_zhao"])
	var npc_db := {
		"npcs": {
			"npc_zhao": {
				"name": "赵明",
				"age": 35,
				"性别": "男",
				"origin": "警校毕业",
				"physical_traits": "高个子",
			},
		},
	}
	KnowledgeScript.apply_discoveries(
		store,
		[{"target": "npc_zhao", "fields": ["age", "性别", "origin", "physical_traits"]}],
		{},
		npc_db,
	)
	var visible := KnowledgeScript.build_visible_profile(
		npc_db["npcs"]["npc_zhao"],
		store,
		"npc_zhao",
	)
	if int(visible.get("age", 0)) != 35:
		push_error("knowledge: expected age in visible profile")
		return 1
	if str(visible.get("origin", "")) != "警校毕业":
		push_error("knowledge: expected origin in visible profile")
		return 1
	if str(visible.get("性别", "")) != "男":
		push_error("knowledge: expected 性别 in visible profile")
		return 1
	return 0


func _test_age_zero_not_visible_when_revealed() -> int:
	var store := KnowledgeScript.seed_initial("hero", ["npc_zhao"])
	var truth := {"name": "赵明", "age": 0, "origin": ""}
	KnowledgeScript.reveal_fields(store, "npc_zhao", ["age", "origin"])
	var visible := KnowledgeScript.build_visible_profile(truth, store, "npc_zhao")
	if visible.has("age") or visible.has("origin"):
		push_error("knowledge: empty truth should not appear in visible profile")
		return 1
	return 0


func _test_ensure_nearby_npc_baseline() -> int:
	var store := {KnowledgeScript.SELF_KEY: KnowledgeScript.SELF_BASELINE_FIELDS.duplicate()}
	KnowledgeScript.ensure_nearby_npc_baseline(store, "hero", ["npc_zhao", "hero"])
	if not store.has("npc_zhao"):
		push_error("knowledge: expected npc_zhao baseline entry")
		return 1
	if "name" not in store["npc_zhao"]:
		push_error("knowledge: expected name revealed for nearby npc")
		return 1
	if store.has("hero"):
		push_error("knowledge: protagonist should not get npc knowledge entry")
		return 1
	return 0


func _test_normalize_discoveries_resolves_name() -> int:
	var rm := _read_model_with_zhao()
	var hook := {
		"discoveries": [
			{"target": "赵明", "fields": ["personality", "invalid_field"]},
		],
	}
	var normalized := HookNormalizerScript.normalize(hook, rm, {})
	var discoveries: Variant = normalized.get("discoveries", [])
	if not discoveries is Array or discoveries.is_empty():
		push_error("knowledge: expected normalized discoveries")
		return 1
	var entry: Dictionary = discoveries[0]
	if str(entry.get("target", "")) != "npc_zhao":
		push_error("knowledge: expected target resolved to npc_zhao, got %s" % entry.get("target", ""))
		return 1
	var fields: Variant = entry.get("fields", [])
	if fields is Array and "personality" not in fields:
		push_error("knowledge: expected personality field kept")
		return 1
	if fields is Array and "invalid_field" in fields:
		push_error("knowledge: invalid field should be stripped")
		return 1
	return 0


func _test_profile_display_only_revealed_fields() -> int:
	var lines := ProfileDisplayScript.build_text_field_lines({
		"physical_traits": "高个子",
		"personality": "果敢",
	})
	var joined := "\n".join(lines)
	if joined.find("年龄") >= 0 or joined.find("出身") >= 0 or joined.find("性别") >= 0:
		push_error("profile display: should not show unrevealed fields")
		return 1
	if joined.find("外貌") < 0 or joined.find("性格") < 0:
		push_error("profile display: should show revealed fields")
		return 1
	return 0


func _read_model_with_zhao() -> GameReadModel:
	var rm := ReadModelScript.new()
	rm.mainrole = {"id": "hero", "name": "主角"}
	rm.npc_db = {
		"npcs": {
			"npc_zhao": {"id": "npc_zhao", "name": "赵明", "personality": "果敢"},
		},
	}
	rm.game_state = RuntimeDbSchemas.empty_game_state()
	rm.game_state["nearby_npc_ids"] = ["npc_zhao"]
	return rm
