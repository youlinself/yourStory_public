## 物品设定一致性守卫
extends SceneTree

const GuardScript := preload("res://src/game/logic/data/item_setting_guard.gd")
const StorageScript := preload("res://src/ai_skills/dynamic_add_storage.gd")
const PromptBuilderScript := preload("res://src/ai_skills/dynamic_add_prompt_builder.gd")
const ItemCatalogScript := preload("res://src/game/logic/data/item_display_catalog.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_blurb_non_empty()
	failed += _test_historical_rejects_modern_phone()
	failed += _test_historical_accepts_bamboo()
	failed += _test_crossworld_allows_phone_foreign()
	failed += _test_mixed_script_id_rejected()
	failed += _test_loot_validate_same_rules()
	failed += _test_storage_rejects_invalid_loot()
	failed += _test_prompt_includes_consistency()
	failed += _test_loot_name_must_differ_from_id()
	failed += _test_unknown_item_display_name()
	failed += _test_inventory_slot_without_name()
	if failed == 0:
		print("[OK] item setting guard tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _historical_base_config() -> Dictionary:
	return {
		"novel_type": "历史",
		"world_setting": {
			"social_env": {
				"background": "战国中期，公元前280年，诸侯争霸",
			},
			"people_env": {
				"technology": "青铜铁器、竹简帛书、车马舟楫",
			},
		},
	}


func _crossworld_base_config() -> Dictionary:
	return {
		"novel_type": "穿越",
		"world_setting": {
			"social_env": {
				"background": "主角穿越至古代，随身保留现代物品",
			},
		},
	}


func _test_blurb_non_empty() -> int:
	if GuardScript.setting_consistency_rule_blurb().strip_edges().is_empty():
		push_error("blurb should be non-empty")
		return 1
	return 0


func _test_historical_rejects_modern_phone() -> int:
	var npc := {
		"items": [
			{"id": "modern_phone", "quantity": 1, "world_familiarity": "本土寻常"},
		],
	}
	var err := GuardScript.validate_starter_items(npc, _historical_base_config())
	if err.is_empty():
		push_error("expected rejection for modern phone in historical setting")
		return 1
	return 0


func _test_historical_accepts_bamboo() -> int:
	var npc := {
		"items": [
			{"id": "bamboo_slip", "quantity": 2, "world_familiarity": "本土寻常"},
		],
	}
	var err := GuardScript.validate_starter_items(npc, _historical_base_config())
	if not err.is_empty():
		push_error("expected bamboo_slip to pass: %s" % err)
		return 1
	return 0


func _test_crossworld_allows_phone_foreign() -> int:
	var npc := {
		"items": [
			{"id": "modern_phone", "quantity": 1, "world_familiarity": "域外异物"},
		],
	}
	var err := GuardScript.validate_starter_items(npc, _crossworld_base_config())
	if not err.is_empty():
		push_error("expected crossworld phone with 域外异物 to pass: %s" % err)
		return 1
	return 0


func _test_mixed_script_id_rejected() -> int:
	var npc := {
		"items": [
			{"id": "protagonist现代pen", "quantity": 1},
		],
	}
	var err := GuardScript.validate_starter_items(npc, _historical_base_config())
	if err != GuardScript.item_id_format_hint():
		push_error("expected id format hint, got: %s" % err)
		return 1
	return 0


func _test_loot_validate_same_rules() -> int:
	var record := {
		"id": "smartphone_001",
		"name": "智能手机",
		"world_familiarity": "本土寻常",
	}
	var err := GuardScript.validate_loot_record(record, _historical_base_config(), "loot_item")
	if err.is_empty():
		push_error("loot record should fail when foreign item marked native")
		return 1
	return 0


func _test_storage_rejects_invalid_loot() -> int:
	var result := StorageScript.apply_generation_result(
		"loot_item",
		{
			"status": "new_created",
			"schema_id": "loot_item",
			"data": {
				"id": "modern_lighter",
				"name": "打火机",
				"world_familiarity": "本土寻常",
			},
		},
	)
	if result.get("ok", false):
		push_error("storage should reject loot inconsistent with runtime base_config")
		return 1
	return 0


func _test_prompt_includes_consistency() -> int:
	var msg := PromptBuilderScript.build_generation_user_message("loot_item", "医疗柜", "{}")
	if msg.find("设定一致性") < 0:
		push_error("loot_item generation prompt should include consistency section")
		return 1
	if msg.find(GuardScript.setting_consistency_rule_blurb().substr(0, 8)) < 0:
		push_error("loot_item prompt should include consistency blurb")
		return 1
	return 0


func _test_loot_name_must_differ_from_id() -> int:
	var record := {
		"id": "stonebonechiprift",
		"name": "stonebonechiprift",
		"world_familiarity": "本土寻常",
	}
	var err := GuardScript.validate_loot_record(record, _historical_base_config(), "loot_item")
	if err.is_empty():
		push_error("loot with name==id should be rejected")
		return 1
	return 0


func _test_inventory_slot_without_name() -> int:
	var slot_err := GuardScript.validate_inventory_slot(
		{"id": "bamboo_slip", "quantity": 2, "world_familiarity": "本土寻常"},
		_historical_base_config(),
	)
	if not slot_err.is_empty():
		push_error("inventory slot without name should pass: %s" % slot_err)
		return 1
	return 0


func _test_unknown_item_display_name() -> int:
	var catalog := ItemCatalogScript.new()
	var info := catalog.resolve("stonebonechiprift")
	if str(info.get("name", "")) != "未登记物品":
		push_error("unknown item should not expose raw id as name: %s" % str(info))
		return 1
	if str(info.get("desc", "")).find("stonebonechiprift") < 0:
		push_error("unknown item desc should mention id for tooltip")
		return 1
	return 0
