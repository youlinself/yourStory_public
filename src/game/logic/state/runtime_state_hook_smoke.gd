class_name RuntimeStateHookSmoke
extends RefCounted

## 本地冒烟：在 Godot 编辑器脚本或调试控制台调用 RuntimeStateHookSmoke.run_all()


static func run_all() -> Dictionary:
	var results: Array[String] = []
	results.append(_test_wallet_merge())
	results.append(_test_inventory_delta())
	results.append(_test_unlock_regions())
	var failed := 0
	for line in results:
		if line.begins_with("FAIL"):
			failed += 1
	return {"ok": failed == 0, "lines": results}


static func _test_wallet_merge() -> String:
	var role := RuntimeDbSchemas.empty_mainrole()
	role["stats"] = {"wallet": {"unit_id": "wen", "unit_name": "文", "amount": 50}}
	var svc := RuntimeStateService.new()
	svc._mainrole = role.duplicate(true)
	svc._game_state = RuntimeDbSchemas.empty_game_state()
	var warnings: PackedStringArray = []
	RuntimeStateService._apply_wallet_hook(role, {"amount": 20}, warnings)
	var w := RuntimeDbSchemas.get_wallet_from_mainrole(role)
	if int(w.get("amount", -1)) == 20 and str(w.get("unit_name", "")) == "文":
		return "OK wallet amount"
	return "FAIL wallet amount got %s" % str(w)


static func _test_inventory_delta() -> String:
	var role := RuntimeDbSchemas.empty_mainrole()
	role["items"] = [{"id": "coin", "quantity": 5}]
	var items_db := {"items": {"coin": {"id": "coin", "name": "铜钱"}}}
	GameRunningFileManager.save_json_data(GameRunningFileManager.ITEMS_DB, items_db)
	var warnings: PackedStringArray = []
	RuntimeStateService._apply_inventory_delta(role, [
		{"op": "add", "id": "coin", "quantity": 3},
		{"op": "remove", "id": "coin", "quantity": 2},
	], warnings)
	var qty := 0
	for entry in role.get("items", []):
		if entry is Dictionary and str(entry.get("id", "")) == "coin":
			qty = int(entry.get("quantity", 0))
	if qty == 6:
		return "OK inventory_delta"
	return "FAIL inventory_delta qty=%d" % qty


static func _test_unlock_regions() -> String:
	var state := RuntimeDbSchemas.empty_game_state()
	state["unlocked_region_ids"] = ["start"]
	var warnings: PackedStringArray = []
	RuntimeStateService._apply_unlock_region_ids(
		state,
		["start", "slum", "bad_id"],
		["start", "slum", "rich"],
		warnings,
	)
	var unlocked: Array = state.get("unlocked_region_ids", [])
	if "slum" in unlocked and "bad_id" not in unlocked and unlocked.size() == 2:
		return "OK unlock_region_ids"
	return "FAIL unlock_region_ids %s warnings=%s" % [str(unlocked), str(warnings)]
