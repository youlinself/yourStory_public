## ItemGenerationAgent 单元测试（`godot --headless -s tests/item_generation_agent_test.gd`）
extends SceneTree

const AgentScript := preload("res://src/ai_skills/item_generation_agent.gd")
const GuardScript := preload("res://src/game/logic/data/item_setting_guard.gd")
const CatalogScript := preload("res://src/game/logic/data/item_display_catalog.gd")
const StorageScript := preload("res://src/ai_skills/dynamic_add_storage.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_collect_dedup_and_familiarity()
	failed += _test_infer_schema_id()
	failed += _test_placeholder_record()
	failed += _test_locked_id_prompt()
	failed += _test_storage_upserts_placeholder()
	failed += _test_inventory_slot_vs_record_validation()
	if failed == 0:
		print("[OK] item generation agent tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _sample_world_init() -> Dictionary:
	return {
		"adventure_module": {"opening_hook": "雨夜集市"},
	}


func _sample_npc_db() -> Dictionary:
	return {
		"npcs": {
			"hero": {
				"name": "林夜",
				"initial_scene": "南郊旧街",
				"equipment": ["破旧背包"],
				"items": [
					{"id": "item_market_loa_voucher", "quantity": 1, "world_familiarity": "本土寻常"},
					{"id": "copper_coin", "quantity": 3},
				],
			},
			"merchant": {
				"items": [
					{"id": "item_market_loa_voucher", "quantity": 2},
					{"id": "weapon_rusty_knife", "quantity": 1},
				],
			},
		},
	}


func _test_collect_dedup_and_familiarity() -> int:
	var requests := AgentScript.collect_from_npc_db(
		_sample_npc_db(),
		_sample_world_init(),
		{},
	)
	if requests.size() != 3:
		push_error("expected 3 unique item requests, got %d" % requests.size())
		return 1
	var voucher: Dictionary = {}
	for req in requests:
		if req is Dictionary and str(req.get("id", "")) == "item_market_loa_voucher":
			voucher = req
			break
	if voucher.is_empty():
		push_error("missing voucher request")
		return 1
	if str(voucher.get("world_familiarity", "")) != "本土寻常":
		push_error("world_familiarity should be preserved")
		return 1
	if not bool(voucher.get("lock_id", false)):
		push_error("starter requests should lock id")
		return 1
	if str(voucher.get("source_context", "")).find("林夜") < 0:
		push_error("source_context should mention holder")
		return 1
	return 0


func _test_infer_schema_id() -> int:
	if AgentScript.infer_schema_id("weapon_rusty_knife") != "loot_weapon":
		push_error("weapon prefix should map to loot_weapon")
		return 1
	if AgentScript.infer_schema_id("item_market_loa_voucher") != "loot_item":
		push_error("item prefix should map to loot_item")
		return 1
	return 0


func _test_placeholder_record() -> int:
	var placeholder := {
		"id": "item_market_loa_voucher",
		"name": "",
		"description": "",
		"effect": "",
	}
	if not AgentScript.is_placeholder_record(placeholder, "item_market_loa_voucher"):
		push_error("empty name record should be placeholder")
		return 1
	var full := {
		"id": "item_market_loa_voucher",
		"name": "集市欠条",
		"description": "一张皱巴巴的欠条。",
		"effect": "可在集市兑换少量物资。",
	}
	if AgentScript.is_placeholder_record(full, "item_market_loa_voucher"):
		push_error("complete record should not be placeholder")
		return 1
	return 0


func _test_locked_id_prompt() -> int:
	var lines := AgentScript.build_locked_id_prompt_lines({
		"id": "item_market_loa_voucher",
		"world_familiarity": "本土寻常",
	})
	var blob := "\n".join(lines)
	if blob.find("item_market_loa_voucher") < 0:
		push_error("locked id prompt should mention target id")
		return 1
	if blob.find("本土寻常") < 0:
		push_error("locked id prompt should mention world_familiarity")
		return 1
	return 0


func _test_storage_upserts_placeholder() -> int:
	if not GameRunningFileManager.ensure_dir():
		push_error("cannot ensure runtime dir")
		return 1
	GameRunningFileManager.save_json_data(
		GameRunningFileManager.ITEMS_DB,
		{
			"items": {
				"item_market_loa_voucher": {
					"id": "item_market_loa_voucher",
					"name": "",
					"description": "",
					"effect": "",
					"world_familiarity": "本土寻常",
				},
			},
		},
	)
	var result := StorageScript.apply_generation_result(
		"loot_item",
		{
			"status": "new_created",
			"schema_id": "loot_item",
			"data": {
				"id": "item_market_loa_voucher",
				"name": "集市欠条",
				"description": "皱巴巴的欠条。",
				"effect": "可在集市兑换物资。",
				"world_familiarity": "本土寻常",
			},
		},
		true,
	)
	if not result.get("ok", false):
		push_error("placeholder upsert should succeed: %s" % str(result))
		return 1
	if str(result.get("status", "")) != "updated_placeholder":
		push_error("expected updated_placeholder status, got %s" % str(result.get("status", "")))
		return 1
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.ITEMS_DB)
	var items: Dictionary = (loaded as Dictionary).get("items", {}) if loaded is Dictionary else {}
	var row: Dictionary = items.get("item_market_loa_voucher", {}) if items is Dictionary else {}
	if str(row.get("name", "")) != "集市欠条":
		push_error("upsert should replace placeholder name")
		return 1
	return 0


func _test_inventory_slot_vs_record_validation() -> int:
	var base := {
		"novel_type": "历史",
		"world_setting": {"social_env": {"background": "战国"}},
	}
	var slot_err := GuardScript.validate_inventory_slot(
		{"id": "bamboo_slip", "quantity": 2, "world_familiarity": "本土寻常"},
		base,
	)
	if not slot_err.is_empty():
		push_error("inventory slot should pass without name: %s" % slot_err)
		return 1
	var record_err := GuardScript.validate_item_record(
		{
			"id": "bamboo_slip",
			"name": "bamboo_slip",
			"world_familiarity": "本土寻常",
		},
		base,
		"loot_item",
	)
	if record_err.is_empty():
		push_error("item record with name==id should fail")
		return 1
	return 0
