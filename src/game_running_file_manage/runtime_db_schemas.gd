class_name RuntimeDbSchemas
extends RefCounted

const CharacterKnowledgeScript := preload("res://src/game/logic/data/character_knowledge.gd")
const LocationResolverScript := preload("res://src/game/logic/world/location_resolver.gd")

## 运行时 JSON 总表 envelope 约定（平铺在 user://game_runtime_data/）。

static func empty_skills_db() -> Dictionary:
	return {"skills": {}}


static func empty_items_db() -> Dictionary:
	return {"items": {}}


static func empty_weapon_db() -> Dictionary:
	return {"weapons": {}}


static func empty_npc_db() -> Dictionary:
	return {"npcs": {}}


static func empty_map_db() -> Dictionary:
	return {
		"novel_type": "",
		"map_structure": {},
		"factions": [],
	}


## 六维能力默认值（0–100，50 为常人基准）。
static func empty_abilities() -> Dictionary:
	return {
		"str": 50,
		"agi": 50,
		"con": 50,
		"int": 50,
		"mnd": 50,
		"cha": 50,
	}


## 大五人格默认值（0–100，50 为中性）。
static func empty_psychology() -> Dictionary:
	return {
		"openness": 50,
		"conscientiousness": 50,
		"extraversion": 50,
		"agreeableness": 50,
		"neuroticism": 50,
	}


static func normalize_abilities(data: Variant) -> Dictionary:
	var out := empty_abilities()
	if not data is Dictionary:
		return out
	for key in out:
		if (data as Dictionary).has(key):
			out[key] = clampi(int((data as Dictionary)[key]), 0, 100)
	return out


static func normalize_psychology(data: Variant) -> Dictionary:
	var out := empty_psychology()
	if not data is Dictionary:
		return out
	for key in out:
		if (data as Dictionary).has(key):
			out[key] = clampi(int((data as Dictionary)[key]), 0, 100)
	return out


## 主角运行时状态（由 world_init 中 protagonist 条目映射生成）。
static func empty_mainrole() -> Dictionary:
	return {
		"id": "",
		"name": "",
		"age": 0,
		"性别": "",
		"族群": "",
		"origin": "",
		"physical_traits": "",
		"personality": "",
		"deep_motivation": "",
		"core_conflict": "",
		"skills": [],
		"items": [],
		"equipment": [],
		"abilities": empty_abilities(),
		"psychology": empty_psychology(),
		"initial_scene": "",
		"current_region_id": "",
		"current_key_node_id": "",
		"current_map_cell": {},
		"stats": {"wallet": empty_wallet()},
	}


static func empty_wallet() -> Dictionary:
	return {
		"unit_id": "",
		"unit_name": "",
		"amount": 0,
	}


static func normalize_wallet(data: Variant) -> Dictionary:
	var out := empty_wallet()
	if not data is Dictionary:
		return out
	var d := data as Dictionary
	out["unit_id"] = str(d.get("unit_id", "")).strip_edges()
	out["unit_name"] = str(d.get("unit_name", "")).strip_edges()
	out["amount"] = maxi(0, int(d.get("amount", 0)))
	return out


static func ensure_mainrole_stats_wallet(role: Dictionary) -> void:
	var stats: Variant = role.get("stats", null)
	if not stats is Dictionary:
		stats = {}
		role["stats"] = stats
	var wallet: Variant = (stats as Dictionary).get("wallet", null)
	(stats as Dictionary)["wallet"] = normalize_wallet(wallet)


static func get_wallet_from_mainrole(role: Dictionary) -> Dictionary:
	var role_copy := role.duplicate(true)
	ensure_mainrole_stats_wallet(role_copy)
	var stats: Dictionary = role_copy.get("stats", {})
	return normalize_wallet(stats.get("wallet", {}))


static func format_wallet_display(wallet: Dictionary) -> String:
	var amount := int(wallet.get("amount", 0))
	var unit_name := str(wallet.get("unit_name", "")).strip_edges()
	if unit_name.is_empty():
		if amount <= 0:
			return ""
		return str(amount)
	return "%d %s" % [amount, unit_name]


static func seed_wallet_from_world(role: Dictionary, world_init: Dictionary, base_config: Dictionary) -> void:
	ensure_mainrole_stats_wallet(role)
	var stats: Dictionary = role.get("stats", {})
	var wallet := normalize_wallet(stats.get("wallet", {}))
	var currency: Variant = world_init.get("currency", null)
	if currency is Dictionary:
		var c := currency as Dictionary
		var uid := str(c.get("unit_id", "")).strip_edges()
		if not uid.is_empty():
			wallet["unit_id"] = uid
		var uname := str(c.get("unit_name", "")).strip_edges()
		if not uname.is_empty():
			wallet["unit_name"] = uname
		if c.has("starting_amount"):
			wallet["amount"] = maxi(0, int(c.get("starting_amount", 0)))
	var env_root: Variant = base_config.get("world_setting", base_config.get("base_config", {}))
	if env_root is Dictionary:
		var ce: Variant = (env_root as Dictionary).get("currency", null)
		if ce is Dictionary:
			var ec := ce as Dictionary
			if wallet["unit_name"].is_empty():
				var uname := str(ec.get("unit_name", "")).strip_edges()
				if not uname.is_empty():
					wallet["unit_name"] = uname
			if wallet["unit_id"].is_empty():
				var uid := str(ec.get("unit_id", "")).strip_edges()
				if not uid.is_empty():
					wallet["unit_id"] = uid
	stats["wallet"] = wallet
	role["stats"] = stats


static func skills_array_to_db(skills_array: Array) -> Dictionary:
	var db := empty_skills_db()
	for item in skills_array:
		if not item is Dictionary:
			continue
		var skill_id: String = str(item.get("id", "")).strip_edges()
		if skill_id.is_empty():
			continue
		db["skills"][skill_id] = {
			"name": str(item.get("name", "")),
			"desc": str(item.get("desc", "")),
		}
	return db


static func normalize_skills_db(data: Variant) -> Dictionary:
	if data is Dictionary:
		if data.has("skills"):
			var skills_val: Variant = data["skills"]
			if skills_val is Dictionary:
				return {"skills": skills_val.duplicate(true)}
			if skills_val is Array:
				return skills_array_to_db(skills_val)
	return empty_skills_db()


static func build_mainrole_from_npc(npc: Dictionary, world_init: Dictionary) -> Dictionary:
	var role := empty_mainrole()
	role["id"] = str(npc.get("id", ""))
	role["name"] = str(npc.get("name", ""))
	role["age"] = int(npc.get("age", 0))
	for key in ["性别", "族群", "origin", "physical_traits", "personality", "deep_motivation", "core_conflict"]:
		role[key] = str(npc.get(key, "")).strip_edges()
	role["skills"] = npc.get("skills", [])
	if role["skills"] is Array:
		role["skills"] = (role["skills"] as Array).duplicate()
	else:
		role["skills"] = []
	role["items"] = npc.get("items", [])
	if role["items"] is Array:
		role["items"] = (role["items"] as Array).duplicate()
	else:
		role["items"] = []
	role["equipment"] = npc.get("equipment", [])
	if role["equipment"] is Array:
		role["equipment"] = (role["equipment"] as Array).duplicate()
	else:
		role["equipment"] = []
	role["initial_scene"] = str(npc.get("initial_scene", ""))
	role["abilities"] = normalize_abilities(npc.get("abilities", {}))
	role["psychology"] = normalize_psychology(npc.get("psychology", {}))
	var map_structure: Variant = world_init.get("map_structure", {})
	if not map_structure is Dictionary:
		map_structure = {}
	LocationResolverScript.resolve_and_apply(
		role,
		map_structure as Dictionary,
		{
			"region_hint": str(npc.get("current_region_id", "")).strip_edges(),
			"key_node_hint": str(npc.get("current_key_node_id", "")).strip_edges(),
			"hint_text": LocationResolverScript.hint_text_from_world_init(world_init, npc),
		},
		{
			"allow_assign_key_node_cell": true,
			"include_map_cell": true,
		},
	)
	world_init["map_structure"] = map_structure
	if npc.has("wallet"):
		role["stats"] = {"wallet": normalize_wallet(npc.get("wallet"))}
	else:
		ensure_mainrole_stats_wallet(role)
	return role


static func build_map_db(base_config: Dictionary, world_init: Dictionary) -> Dictionary:
	return {
		"novel_type": str(base_config.get("novel_type", "")),
		"map_structure": world_init.get("map_structure", {}),
		"factions": world_init.get("factions", []),
	}


static func build_npc_db(world_init: Dictionary) -> Dictionary:
	var db := empty_npc_db()
	var npcs: Variant = world_init.get("npcs", [])
	if not npcs is Array:
		return db
	for npc in npcs:
		if not npc is Dictionary:
			continue
		var npc_id: String = str(npc.get("id", "")).strip_edges()
		if npc_id.is_empty():
			continue
		var entry: Dictionary = (npc as Dictionary).duplicate(true)
		normalize_npc_location(entry, world_init)
		db["npcs"][npc_id] = entry
	return db


static func normalize_npc_location(npc: Dictionary, world_init: Dictionary) -> void:
	var map_structure: Variant = world_init.get("map_structure", {})
	if not map_structure is Dictionary:
		map_structure = {}
	LocationResolverScript.resolve_and_apply(
		npc,
		map_structure as Dictionary,
		{
			"region_hint": str(npc.get("current_region_id", "")).strip_edges(),
			"key_node_hint": str(npc.get("current_key_node_id", "")).strip_edges(),
			"hint_text": LocationResolverScript.hint_text_from_world_init(world_init, npc),
		},
		{
			"allow_assign_key_node_cell": true,
			"include_map_cell": false,
		},
	)
	world_init["map_structure"] = map_structure


static func empty_game_state() -> Dictionary:
	return {
		"session_id": "",
		"started_at": 0,
		"novel_type": "",
		"datetime_display": "",
		"weather": "",
		"adventure_module": {},
		"scene_pressure": 0,
		"check_history": [],
		"unlocked_region_ids": [],
		"nearby_npc_ids": [],
		"talked_npc_ids": [],
		"npc_favorability": {},
		"present_npc_ids": [],
		"scene_targets": [],
		"character_knowledge": {},
		"event_log": [],
		"story_log": [],
		"narrative_messages": [],
		"narrative_memory": [],
		"narrative_outline": "",
		"last_archive_story_index": 0,
		"chars_since_last_archive": 0,
		"last_suggestions": [],
	}


static func ensure_talked_npc_ids(state: Dictionary) -> void:
	if not state.get("talked_npc_ids", null) is Array:
		state["talked_npc_ids"] = []


static func record_talked_npc(state: Dictionary, npc_id: String) -> void:
	var nid := npc_id.strip_edges()
	if nid.is_empty():
		return
	ensure_talked_npc_ids(state)
	var pool: Variant = state.get("talked_npc_ids", [])
	if nid in pool:
		return
	pool.append(nid)
	state["talked_npc_ids"] = pool


static func ensure_npc_favorability(state: Dictionary) -> void:
	if not state.get("npc_favorability", null) is Dictionary:
		state["npc_favorability"] = {}


static func get_npc_favorability_value(state: Dictionary, npc_id: String) -> int:
	ensure_npc_favorability(state)
	var store: Variant = state.get("npc_favorability", {})
	if not store is Dictionary:
		return 0
	return int((store as Dictionary).get(npc_id.strip_edges(), 0))


static func apply_npc_favorability_delta(state: Dictionary, npc_id: String, delta: int) -> void:
	var nid := npc_id.strip_edges()
	if nid.is_empty() or delta == 0:
		return
	ensure_npc_favorability(state)
	var store: Dictionary = state["npc_favorability"]
	var current := int(store.get(nid, 0))
	store[nid] = current + delta
	state["npc_favorability"] = store


static func build_game_state_from_world(
	world_init: Dictionary,
	base_config: Dictionary,
	mainrole: Dictionary,
) -> Dictionary:
	var state := empty_game_state()
	var env_root: Variant = base_config.get("world_setting", base_config.get("base_config", {}))
	var nature: Variant = env_root.get("nature_env", {}) if env_root is Dictionary else {}
	if nature is Dictionary:
		state["datetime_display"] = WorldSettingDisplay.format_start_time(nature)
		state["weather"] = WorldSettingDisplay.format_weather(nature)

	if str(state["datetime_display"]).is_empty():
		var dt := Time.get_datetime_dict_from_system()
		state["datetime_display"] = "%04d.%02d.%02d" % [dt.year, dt.month, dt.day]

	var region_id := str(mainrole.get("current_region_id", "")).strip_edges()
	if not region_id.is_empty():
		state["unlocked_region_ids"] = [region_id]

	var initial_scene := str(mainrole.get("initial_scene", "")).strip_edges()
	if not initial_scene.is_empty():
		state["event_log"].append({
			"timestamp": 0,
			"title": "故事开端",
			"summary": initial_scene,
			"region_id": region_id,
		})

	var adventure: Variant = world_init.get("adventure_module", {})
	if adventure is Dictionary:
		state["adventure_module"] = (adventure as Dictionary).duplicate(true)

	var protagonist_id := str(world_init.get("protagonist_id", "")).strip_edges()
	var hero_region := str(mainrole.get("current_region_id", "")).strip_edges()
	var npcs: Variant = world_init.get("npcs", [])
	if npcs is Array:
		for npc in npcs:
			if not npc is Dictionary:
				continue
			var npc_id: String = str(npc.get("id", "")).strip_edges()
			if npc_id.is_empty() or npc_id == protagonist_id:
				continue
			var npc_region := str(npc.get("current_region_id", "")).strip_edges()
			if hero_region.is_empty() or npc_region.is_empty() or npc_region == hero_region:
				state["nearby_npc_ids"].append(npc_id)

	state["character_knowledge"] = CharacterKnowledgeScript.seed_initial(
		protagonist_id,
		state["nearby_npc_ids"],
	)

	return state


