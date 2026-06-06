class_name WorldInitSplitter
extends RefCounted

const ItemDisplayCatalog := preload("res://src/game/logic/data/item_display_catalog.gd")

## 将 world_init_setting.json 拆分到各运行时总表，并初始化主角状态。


static func apply(world_init: Dictionary, base_config: Dictionary) -> bool:
	if world_init.is_empty():
		push_error("WorldInitSplitter: world_init 为空")
		return false
	if base_config.is_empty():
		push_error("WorldInitSplitter: base_config 为空")
		return false

	var protagonist_id: String = str(world_init.get("protagonist_id", "")).strip_edges()
	var npc_db: Dictionary = RuntimeDbSchemas.build_npc_db(world_init)
	var npcs: Dictionary = npc_db.get("npcs", {})
	if not npcs.has(protagonist_id):
		push_error("WorldInitSplitter: 未找到主角 NPC id=%s" % protagonist_id)
		return false

	if not GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, RuntimeDbSchemas.build_map_db(base_config, world_init)):
		return false
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.NPC_DB, npc_db):
		return false
	var mainrole: Dictionary = RuntimeDbSchemas.build_mainrole_from_npc(npcs[protagonist_id], world_init)
	RuntimeDbSchemas.seed_wallet_from_world(mainrole, world_init, base_config)
	if not GameRunningFileManager.save_json_data(
		GameRunningFileManager.MAP_DB,
		RuntimeDbSchemas.build_map_db(base_config, world_init),
	):
		return false
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.MAIN_ROLE, mainrole):
		return false
	var items_db := _load_or_seed_items_db(npc_db)
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.ITEMS_DB, items_db):
		return false
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.WEAPON_DB, RuntimeDbSchemas.empty_weapon_db()):
		return false
	if not GameRunningFileManager.save_json_data(
		GameRunningFileManager.GAME_STATE,
		RuntimeDbSchemas.build_game_state_from_world(world_init, base_config, mainrole),
	):
		return false

	return true


static func _load_or_seed_items_db(npc_db: Dictionary) -> Dictionary:
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.ITEMS_DB)
	var base: Dictionary = loaded if loaded is Dictionary else RuntimeDbSchemas.empty_items_db()
	return ItemDisplayCatalog.seed_starter_items_fallback(npc_db, base)
