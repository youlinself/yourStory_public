class_name GameReadModel
extends RefCounted

const CharacterKnowledgeScript := preload("res://src/game/logic/data/character_knowledge.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const LocationResolverScript := preload("res://src/game/logic/world/location_resolver.gd")
const MapStructureRepairScript := preload("res://src/game/logic/world/map_structure_repair.gd")
const RuntimeStateServiceScript := preload("res://src/game/logic/state/runtime_state_service.gd")
const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")
const SceneTargetResolverScript := preload("res://src/game/logic/world/scene_target_resolver.gd")
const LocalGridBuilderScript := preload("res://src/novel_config/local_grid_builder.gd")

var mainrole: Dictionary = {}
var map_db: Dictionary = {}
var npc_db: Dictionary = {}
var base_config: Dictionary = {}
var game_state: Dictionary = {}


func load_from_runtime() -> void:
	mainrole = _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAIN_ROLE))
	map_db = _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB))
	if MapStructureRepairScript.repair_misassigned_key_nodes(map_db):
		GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, map_db)
	if _normalize_map_db_structure():
		GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, map_db)
	npc_db = _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.NPC_DB))
	base_config = _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.BASE_CONFIG))
	game_state = _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.GAME_STATE))
	if game_state.is_empty():
		game_state = RuntimeDbSchemas.empty_game_state()
	RuntimeDbSchemas.ensure_talked_npc_ids(game_state)
	RuntimeDbSchemas.ensure_npc_favorability(game_state)
	var stats_raw: Variant = mainrole.get("stats", {})
	var had_wallet := stats_raw is Dictionary and (stats_raw as Dictionary).has("wallet")
	RuntimeDbSchemas.ensure_mainrole_stats_wallet(mainrole)
	if not had_wallet:
		GameRunningFileManager.save_json_data(GameRunningFileManager.MAIN_ROLE, mainrole)
	_ensure_character_knowledge()
	_repair_npc_locations_if_needed()
	_repair_protagonist_map_cell_if_needed()


func get_skills_catalog() -> Dictionary:
	var db := RuntimeDbSchemas.normalize_skills_db(
		GameRunningFileManager.load_json_data(GameRunningFileManager.SKILLS_DB),
	)
	var skills: Variant = db.get("skills", {})
	return skills if skills is Dictionary else {}


func get_items_catalog() -> Dictionary:
	var items_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.ITEMS_DB))
	var items: Variant = items_db.get("items", {})
	var merged: Dictionary = items.duplicate(true) if items is Dictionary else {}
	var weapon_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.WEAPON_DB))
	var weapons: Variant = weapon_db.get("weapons", {})
	if weapons is Dictionary:
		for weapon_id in weapons:
			if not merged.has(weapon_id):
				merged[weapon_id] = weapons[weapon_id]
	return merged


func get_protagonist_npc() -> Dictionary:
	var pid := str(mainrole.get("id", "")).strip_edges()
	if pid.is_empty():
		return {}
	return get_npc(pid)


func get_protagonist_truth() -> Dictionary:
	return CharacterKnowledgeScript.merge_protagonist_truth(mainrole, get_protagonist_npc())


func get_character_knowledge_store() -> Dictionary:
	_ensure_character_knowledge()
	var raw: Variant = game_state.get("character_knowledge", {})
	return raw if raw is Dictionary else {}


func get_known_protagonist_profile() -> Dictionary:
	return CharacterKnowledgeScript.build_visible_profile(
		get_protagonist_truth(),
		get_character_knowledge_store(),
		CharacterKnowledgeScript.SELF_KEY,
	)


func get_known_npc_profile(npc_id: String) -> Dictionary:
	var id := npc_id.strip_edges()
	if id.is_empty():
		return {}
	return CharacterKnowledgeScript.build_visible_profile(
		get_npc(id),
		get_character_knowledge_store(),
		id,
	)


func get_known_display_name(target_id: String, fallback: String = "未知") -> String:
	var known := (
		get_known_protagonist_profile()
		if target_id == CharacterKnowledgeScript.SELF_KEY
		else get_known_npc_profile(target_id)
	)
	var name := SkillDisplayCatalog.format_player_visible(known.get("name", ""))
	if name == "未知":
		return fallback
	return name


func to_view_model() -> Dictionary:
	var adventure := get_player_adventure_module()
	var last_check := get_last_check()
	return {
		"datetime_display": get_status_datetime(),
		"weather": get_status_weather(),
		"location_path": get_location_path(),
		"wallet_display": get_wallet_display(),
		"current_region_id": str(mainrole.get("current_region_id", "")).strip_edges(),
		"story_log": get_story_log(),
		"protagonist_name": get_known_display_name(CharacterKnowledgeScript.SELF_KEY, "主角"),
		"initial_scene": str(mainrole.get("initial_scene", "")).strip_edges(),
		"novel_type": str(map_db.get("novel_type", "")).strip_edges(),
		"adventure_module": adventure,
		"scene_pressure": get_scene_pressure(),
		"last_check": last_check,
		"hud_objective_line": TrpgUiDisplayScript.build_hud_objective_line(adventure),
		"hud_meta_line": TrpgUiDisplayScript.build_hud_meta_line(get_scene_pressure(), last_check),
		"present_npc_names": get_present_npc_display_names(),
		"scene_targets": get_scene_targets(),
		"adventure_card_bbcode": TrpgUiDisplayScript.build_adventure_card_bbcode(
			adventure,
			get_scene_target_display_names(),
			get_present_npc_display_names(),
		),
	}


func get_wallet() -> Dictionary:
	return RuntimeDbSchemas.get_wallet_from_mainrole(mainrole)


func get_wallet_display() -> String:
	return RuntimeDbSchemas.format_wallet_display(get_wallet())


func get_player_adventure_module() -> Dictionary:
	return TrpgUiDisplayScript.player_adventure_module(game_state.get("adventure_module", {}))


func get_scene_pressure() -> int:
	return maxi(0, int(game_state.get("scene_pressure", 0)))


func get_last_check() -> Dictionary:
	return _last_check_from_history(game_state.get("check_history", []))


func get_present_npc_display_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for nid in get_present_npc_ids():
		var name := get_known_display_name(nid, "?")
		if name != "?" and name not in out:
			out.append(name)
	return out


func get_unlocked_region_id_list() -> Array[String]:
	var out: Array[String] = []
	var raw_ids: Variant = game_state.get("unlocked_region_ids", [])
	if raw_ids is Array:
		for id_val in raw_ids:
			var rid := str(id_val).strip_edges()
			if not rid.is_empty() and rid not in out:
				out.append(rid)
	return out


func get_inventory_brief() -> Array:
	var catalog := get_items_catalog()
	var out: Array = []
	var items: Variant = mainrole.get("items", [])
	if not items is Array:
		return out
	for entry in items:
		if not entry is Dictionary:
			continue
		var item_id := str(entry.get("id", "")).strip_edges()
		if item_id.is_empty():
			continue
		var qty := maxi(1, int(entry.get("quantity", 1)))
		var row: Dictionary = catalog.get(item_id, {}) if catalog.has(item_id) else {}
		if row.is_empty():
			row = {"id": item_id, "name": ""}
		out.append({
			"id": item_id,
			"quantity": qty,
			"name": str(row.get("name", item_id)),
			"category": str(row.get("category", "")).strip_edges(),
			"world_familiarity": ItemDisplayCatalog.resolve_world_familiarity(row, item_id),
		})
	return out


func get_story_log() -> Array:
	var raw: Variant = game_state.get("story_log", [])
	if raw is Array:
		return raw.duplicate(true)
	return []


func get_narrative_memory_segments() -> Array:
	var raw: Variant = game_state.get("narrative_memory", [])
	return raw.duplicate(true) if raw is Array else []


func get_narrative_outline() -> String:
	return str(game_state.get("narrative_outline", "")).strip_edges()


func get_pinned_recall_event() -> Dictionary:
	var raw: Variant = game_state.get("pinned_recall_event", null)
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		return (raw as Dictionary).duplicate(true)
	return {}


func is_event_pinned_for_recall(event: Dictionary) -> bool:
	var pinned := get_pinned_recall_event()
	return RuntimeStateServiceScript.events_match_recall(pinned, event)


func get_narrative_memory_for_prompt() -> String:
	const MAX_PROMPT_CHARS := 9000
	var memory_parts: PackedStringArray = []
	var total := 0
	var segments: Array = get_narrative_memory_segments()
	for i in range(segments.size() - 1, -1, -1):
		var block := str(segments[i]).strip_edges()
		if block.is_empty():
			continue
		if total + block.length() > MAX_PROMPT_CHARS and not memory_parts.is_empty():
			break
		memory_parts.insert(0, block)
		total += block.length()

	var outline := get_narrative_outline()
	if not outline.is_empty():
		var outline_block := "【全局大纲】\n%s" % outline
		if memory_parts.is_empty():
			return outline_block
		return outline_block + "\n\n---\n\n" + "\n\n---\n\n".join(memory_parts)
	if memory_parts.is_empty():
		return ""
	return "\n\n---\n\n".join(memory_parts)


static func _truncate_for_prompt(text: String, max_len: int) -> String:
	var t := text.strip_edges()
	if t.length() <= max_len:
		return t
	return t.substr(0, max_len) + "…"


func get_relevant_events(
	query_text: String,
	current_region_id: String = "",
	pinned_event: Dictionary = {},
	max_results: int = 2,
) -> Array:
	var out: Array = []
	if not pinned_event.is_empty():
		out.append(_event_for_prompt(pinned_event, true))
		if out.size() >= max_results:
			return out

	var query := query_text.strip_edges().to_lower()
	var tokens := _tokenize_query(query)
	var events := get_events_chronological()
	if events.is_empty():
		return out

	var scored: Array = []
	for event in events:
		if not event is Dictionary:
			continue
		var e: Dictionary = event
		if not pinned_event.is_empty():
			if RuntimeStateServiceScript.events_match_recall(e, pinned_event):
				continue
		var score := 0
		var region_id := str(e.get("region_id", "")).strip_edges()
		if not current_region_id.is_empty() and region_id == current_region_id:
			score += 3
		var title := str(e.get("title", "")).to_lower()
		var summary := str(e.get("summary", "")).to_lower()
		var compact := str(e.get("compact_body", "")).to_lower()
		if not query.is_empty():
			if title.find(query) >= 0:
				score += 6
			if summary.find(query) >= 0:
				score += 4
			if compact.find(query) >= 0:
				score += 2
		for tok in tokens:
			if tok.length() < 2:
				continue
			if title.find(tok) >= 0:
				score += 4
			if summary.find(tok) >= 0:
				score += 2
			if compact.find(tok) >= 0:
				score += 1
		if score > 0:
			scored.append({"score": score, "event": e})

	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)

	for item in scored:
		if out.size() >= max_results:
			break
		var ev: Dictionary = item.get("event", {})
		if ev.is_empty():
			continue
		out.append(_event_for_prompt(ev, false))
	return out


static func _tokenize_query(query: String) -> Array:
	var tokens: Array = []
	if query.is_empty():
		return tokens
	for part in query.split(" ", false):
		var t := str(part).strip_edges()
		if not t.is_empty():
			tokens.append(t)
	if tokens.is_empty() and query.length() >= 2:
		tokens.append(query)
	return tokens


static func _event_for_prompt(event: Dictionary, pinned: bool) -> Dictionary:
	var compact := str(event.get("compact_body", "")).strip_edges()
	if compact.is_empty():
		compact = str(event.get("summary", "")).strip_edges()
	return {
		"title": str(event.get("title", "")),
		"summary": str(event.get("summary", "")),
		"compact_excerpt": _truncate_for_prompt(compact, 1200),
		"region_id": str(event.get("region_id", "")),
		"pinned": pinned,
	}


func get_last_suggestions() -> Array:
	var raw: Variant = game_state.get("last_suggestions", [])
	return raw.duplicate(true) if raw is Array else []


func get_region_ids() -> Array[String]:
	var out: Array[String] = []
	for region in get_regions():
		if region is Dictionary:
			var rid := str(region.get("id", "")).strip_edges()
			if not rid.is_empty():
				out.append(rid)
	return out


const MAX_REGIONS_IN_SNAPSHOT := 16
const MAX_KEY_NODES_IN_SNAPSHOT := 24
const MAX_INVENTORY_ITEMS_IN_SNAPSHOT := 20


func build_narrative_snapshot(
	player_query: String = "",
	pinned_recall_event: Dictionary = {},
) -> Dictionary:
	var current_region_id := str(mainrole.get("current_region_id", "")).strip_edges()
	var region_allow := _snapshot_region_id_set(current_region_id)
	var regions_brief: Array = []
	for region in get_regions():
		if not region is Dictionary:
			continue
		var rid := str(region.get("id", "")).strip_edges()
		if rid.is_empty() or (not region_allow.is_empty() and rid not in region_allow):
			continue
		regions_brief.append({
			"id": rid,
			"name": str(region.get("name", "")),
		})
		if regions_brief.size() >= MAX_REGIONS_IN_SNAPSHOT:
			break
	var all_events := get_events_chronological()
	var events: Array = []
	var start_idx := maxi(0, all_events.size() - 3)
	for i in range(start_idx, all_events.size()):
		var event: Variant = all_events[i]
		if not event is Dictionary:
			continue
		var e: Dictionary = event
		var compact := str(e.get("compact_body", "")).strip_edges()
		if compact.is_empty():
			compact = str(e.get("summary", "")).strip_edges()
		events.append({
			"title": str(e.get("title", "")),
			"summary": str(e.get("summary", "")),
			"compact_excerpt": _truncate_for_prompt(compact, 400),
		})
	var relevant := get_relevant_events(player_query, current_region_id, pinned_recall_event, 2)
	var key_nodes_brief: Array = []
	for node in get_key_nodes():
		if not node is Dictionary:
			continue
		var node_region := str(node.get("region_id", "")).strip_edges()
		if (
			not region_allow.is_empty()
			and not node_region.is_empty()
			and node_region not in region_allow
		):
			continue
		key_nodes_brief.append({
			"id": str(node.get("id", "")),
			"name": str(node.get("name", "")),
			"region_id": node_region,
		})
		if key_nodes_brief.size() >= MAX_KEY_NODES_IN_SNAPSHOT:
			break
	var protagonist_loc := LocationServiceScript.get_protagonist_location(self)
	var adventure: Variant = game_state.get("adventure_module", {})
	var adventure_copy: Dictionary = {}
	if adventure is Dictionary:
		adventure_copy = _adventure_for_player_snapshot(adventure as Dictionary)
	var abilities: Variant = mainrole.get("abilities", {})
	return {
		"novel_type": str(map_db.get("novel_type", "")),
		"play_mode": "light_dnd",
		"protagonist_name": get_known_display_name(CharacterKnowledgeScript.SELF_KEY, "主角"),
		"abilities": abilities if abilities is Dictionary else RuntimeDbSchemas.empty_abilities(),
		"adventure_module": adventure_copy,
		"scene_pressure": int(game_state.get("scene_pressure", 0)),
		"last_check": _last_check_from_history(game_state.get("check_history", [])),
		"datetime_display": get_status_datetime(),
		"weather": get_status_weather(),
		"location_path": get_location_path(),
		"current_region_id": str(mainrole.get("current_region_id", "")),
		"current_key_node_id": str(mainrole.get("current_key_node_id", "")),
		"protagonist_location": protagonist_loc,
		"wallet": get_wallet(),
		"inventory_brief": _inventory_brief_for_snapshot(),
		"unlocked_region_ids": get_unlocked_region_id_list(),
		"regions": regions_brief,
		"key_nodes": key_nodes_brief,
		"map_pages_brief": get_map_pages_brief_for_snapshot(),
		"npc_locations": _build_npc_locations_snapshot(),
		"recent_events": events,
		"relevant_events": relevant,
		"narrative_memory": get_narrative_memory_for_prompt(),
		"initial_scene": str(mainrole.get("initial_scene", "")),
		"known_profiles": CharacterKnowledgeScript.build_snapshot_known(
			get_character_knowledge_store(),
			mainrole,
			npc_db,
			str(mainrole.get("id", "")),
			game_state.get("nearby_npc_ids", []),
		),
		"npc_favorability": _npc_favorability_for_snapshot(),
	}


func has_save() -> bool:
	return not mainrole.is_empty()


func get_nature_env() -> Dictionary:
	return _nature_dict()


func get_status_datetime() -> String:
	var nature := _nature_dict()
	var dt := str(game_state.get("datetime_display", "")).strip_edges()
	if dt.is_empty():
		return WorldSettingDisplay.format_start_time(nature)
	return WorldSettingDisplay.compact_stored_display(dt, nature, "start_time", "start_time_keywords")


func get_status_weather() -> String:
	var nature := _nature_dict()
	var w := str(game_state.get("weather", "")).strip_edges()
	if w.is_empty():
		return WorldSettingDisplay.format_weather(nature)
	return WorldSettingDisplay.compact_stored_display(w, nature, "weather", "weather_keywords", "晴")


func get_location_path() -> String:
	return LocationServiceScript.format_location_path(
		self,
		LocationServiceScript.get_protagonist_location(self),
	)


## 当前与主角同区域、同关键节点、可立即对话的 NPC。
func get_interactable_npcs() -> Array[Dictionary]:
	var here := LocationServiceScript.get_protagonist_location(self)
	var out: Array[Dictionary] = []
	for npc in get_nearby_npcs():
		var npc_loc := LocationServiceScript.get_npc_location(self, npc)
		if LocationServiceScript.is_same_place(here, npc_loc):
			out.append(npc)
	return out


## 人物关系 Tab：主角曾对话/搭话过的 NPC。
func get_talked_npcs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var protagonist_id := str(mainrole.get("id", "")).strip_edges()
	var raw: Variant = game_state.get("talked_npc_ids", [])
	if not raw is Array:
		return out
	var npcs: Dictionary = npc_db.get("npcs", {})
	for id_val in raw:
		var npc_id := str(id_val).strip_edges()
		if npc_id.is_empty() or npc_id == protagonist_id:
			continue
		if npcs.has(npc_id):
			out.append(npcs[npc_id])
	return out


## 当前场景 Tab：与主角同区域、同关键节点的全部 NPC（不限 nearby 池）。
func get_same_place_npcs() -> Array[Dictionary]:
	var here := LocationServiceScript.get_protagonist_location(self)
	var out: Array[Dictionary] = []
	var protagonist_id := str(mainrole.get("id", "")).strip_edges()
	var npcs: Dictionary = npc_db.get("npcs", {})
	for npc_id in npcs:
		if str(npc_id).strip_edges() == protagonist_id:
			continue
		var npc: Dictionary = npcs[npc_id]
		var npc_loc := LocationServiceScript.get_npc_location(self, npc)
		if LocationServiceScript.is_same_place(here, npc_loc):
			out.append(npc)
	return out


func get_npc_favorability(npc_id: String) -> int:
	return RuntimeDbSchemas.get_npc_favorability_value(game_state, npc_id)


func get_present_npc_ids() -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = game_state.get("present_npc_ids", [])
	if raw is Array:
		for id_val in raw:
			var nid := str(id_val).strip_edges()
			if not nid.is_empty() and nid not in out:
				out.append(nid)
	return out


func get_scene_targets() -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = game_state.get("scene_targets", [])
	if raw is Array:
		for item in raw:
			var text := str(item).strip_edges()
			if not text.is_empty() and text not in out:
				out.append(text)
	return out


func get_scene_target_display_names() -> PackedStringArray:
	var out: PackedStringArray = []
	for token in get_scene_targets():
		var display := SceneTargetResolverScript.resolve_display_name(token, self)
		if not display.is_empty() and display not in out:
			out.append(display)
	return out


## 本回合有在场 NPC 或可调查场景物（规则层优先场景内建议）。
func has_scene_context() -> bool:
	return not get_present_npc_ids().is_empty() or not get_scene_targets().is_empty()


## 规则层行动建议用的 NPC 池：有 present 时仅在场角色；否则仅当前/相邻/已解锁区域内的 nearby 角色。
func get_rule_suggestion_npcs() -> Array[Dictionary]:
	var present := get_present_npc_ids()
	if not present.is_empty():
		var out: Array[Dictionary] = []
		for nid in present:
			var npc := get_npc(nid)
			if not npc.is_empty():
				out.append(npc)
		return out
	return _npcs_in_local_travel_range()


func get_nearby_npcs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Variant = game_state.get("present_npc_ids", [])
	if not ids is Array or ids.is_empty():
		ids = game_state.get("nearby_npc_ids", [])
	var npcs: Dictionary = npc_db.get("npcs", {})
	if ids is Array and not ids.is_empty():
		for id_val in ids:
			var npc_id := str(id_val).strip_edges()
			if npcs.has(npc_id):
				out.append(npcs[npc_id])
		return out
	for npc_id in npcs:
		var npc: Dictionary = npcs[npc_id]
		if str(npc.get("id", "")) == str(mainrole.get("id", "")):
			continue
		out.append(npc)
	return out


func get_unlocked_regions() -> Array[Dictionary]:
	var unlocked: Array[String] = []
	var raw_ids: Variant = game_state.get("unlocked_region_ids", [])
	if raw_ids is Array:
		for id_val in raw_ids:
			var rid := str(id_val).strip_edges()
			if not rid.is_empty():
				unlocked.append(rid)
	var current_id := str(mainrole.get("current_region_id", "")).strip_edges()
	if not current_id.is_empty() and current_id not in unlocked:
		unlocked.append(current_id)
	var regions := get_regions()
	var out: Array[Dictionary] = []
	for region in regions:
		var rid := str(region.get("id", "")).strip_edges()
		if rid.is_empty():
			continue
		if unlocked.is_empty() or rid in unlocked:
			out.append(region)
	return out


func get_events_chronological() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var raw: Variant = game_state.get("event_log", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				events.append(item)
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("timestamp", 0)) < int(b.get("timestamp", 0))
	)
	return events


func get_npc(npc_id: String) -> Dictionary:
	var npcs: Dictionary = npc_db.get("npcs", {})
	if npcs.has(npc_id):
		return npcs[npc_id]
	return {}


func get_region(region_id: String) -> Dictionary:
	for region in get_regions():
		if str(region.get("id", "")) == region_id:
			return region
	return {}


func get_adjacent_region_ids(region_id: String) -> Array[String]:
	var rid := region_id.strip_edges()
	if rid.is_empty():
		return []
	var valid_ids := get_region_ids()
	var adjacency: Dictionary = {}
	for region in get_regions():
		if not region is Dictionary:
			continue
		var a_id := str(region.get("id", "")).strip_edges()
		if a_id.is_empty() or a_id not in valid_ids:
			continue
		var raw_adj: Variant = region.get("adjacent_region_ids", [])
		if not raw_adj is Array:
			continue
		for neighbor in raw_adj:
			var b_id := str(neighbor).strip_edges()
			if b_id.is_empty() or b_id == a_id or b_id not in valid_ids:
				continue
			if not adjacency.has(a_id):
				adjacency[a_id] = {}
			(adjacency[a_id] as Dictionary)[b_id] = true
			if not adjacency.has(b_id):
				adjacency[b_id] = {}
			(adjacency[b_id] as Dictionary)[a_id] = true
	if not adjacency.has(rid):
		return []
	var out: Array[String] = []
	for neighbor in (adjacency[rid] as Dictionary).keys():
		out.append(str(neighbor))
	out.sort()
	return out


func _normalize_map_db_structure() -> bool:
	var ms := _as_dict(map_db.get("map_structure", {}))
	if ms.is_empty():
		return false
	var before := JSON.stringify(ms)
	var normalized := LocalGridBuilderScript.normalize_map_structure(ms)
	var after := JSON.stringify(normalized)
	if before == after:
		return false
	map_db["map_structure"] = normalized
	return true


func get_map_structure() -> Dictionary:
	var ms: Variant = map_db.get("map_structure", {})
	return ms if ms is Dictionary else {}


func get_regions() -> Array:
	var ms := get_map_structure()
	var regions: Variant = ms.get("regions", [])
	return regions if regions is Array else []


func get_key_nodes() -> Array:
	var ms := get_map_structure()
	var nodes: Variant = ms.get("key_nodes", [])
	return nodes if nodes is Array else []


func get_map_pages() -> Array:
	var ms := get_map_structure()
	var pages: Variant = ms.get("map_pages", [])
	return pages if pages is Array else []


func get_map_page(page_id: String) -> Dictionary:
	var target := page_id.strip_edges()
	if target.is_empty():
		return {}
	for raw in get_map_pages():
		if raw is Dictionary and str(raw.get("id", "")).strip_edges() == target:
			return raw as Dictionary
	return {}


func get_key_node(key_node_id: String) -> Dictionary:
	var target := key_node_id.strip_edges()
	if target.is_empty():
		return {}
	for raw in get_key_nodes():
		if raw is Dictionary and str(raw.get("id", "")).strip_edges() == target:
			return raw as Dictionary
	return {}


func get_unlocked_region_id_set() -> Dictionary:
	var out: Dictionary = {}
	for region in get_unlocked_regions():
		var rid := str(region.get("id", "")).strip_edges()
		if not rid.is_empty():
			out[rid] = true
	return out


func get_unlocked_map_pages() -> Array[Dictionary]:
	var unlocked_regions := get_unlocked_region_id_set()
	var out: Array[Dictionary] = []
	for raw in get_map_pages():
		if not raw is Dictionary:
			continue
		var page: Dictionary = raw
		if _is_map_page_unlocked_instance(page, unlocked_regions):
			out.append(page)
	return out


func get_primary_map_page_for_region(region_id: String) -> Dictionary:
	var rid := region_id.strip_edges()
	if rid.is_empty():
		return {}
	for raw in get_map_pages():
		if not raw is Dictionary:
			continue
		var page: Dictionary = raw
		if (
			str(page.get("parent_type", "")).strip_edges() == "region"
			and str(page.get("parent_id", "")).strip_edges() == rid
		):
			return page
	return {}


func get_map_pages_brief_for_snapshot(max_pages: int = 6) -> Array:
	var out: Array = []
	for page in get_unlocked_map_pages():
		if out.size() >= max_pages:
			break
		out.append({
			"id": str(page.get("id", "")),
			"name": str(page.get("name", "")),
			"parent_type": str(page.get("parent_type", "")),
			"parent_id": str(page.get("parent_id", "")),
			"width": int(page.get("width", 0)),
			"height": int(page.get("height", 0)),
		})
	return out


func _is_map_page_unlocked_instance(page: Dictionary, unlocked_regions: Dictionary) -> bool:
	var parent_type := str(page.get("parent_type", "")).strip_edges()
	var parent_id := str(page.get("parent_id", "")).strip_edges()
	if parent_type == "region":
		return unlocked_regions.has(parent_id)
	if parent_type == "key_node":
		var node := get_key_node(parent_id)
		var region_id := str(node.get("region_id", "")).strip_edges()
		return not region_id.is_empty() and unlocked_regions.has(region_id)
	return false


func get_relationship_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var protagonist_id := str(mainrole.get("id", "")).strip_edges()
	for npc in get_nearby_npcs():
		var rel: Variant = npc.get("relationships", {})
		if not rel is Dictionary:
			continue
		for key in ["potential_allies", "enemy_npcs"]:
			var list: Variant = rel.get(key, [])
			if not list is Array:
				continue
			for target_id in list:
				var tid := str(target_id).strip_edges()
				if tid.is_empty():
					continue
				var label := "盟友" if key == "potential_allies" else "敌对"
				var from_id := str(npc.get("id", ""))
				out.append({
					"from_id": from_id,
					"from_name": get_known_display_name(from_id, "?"),
					"to_id": tid,
					"to_name": get_known_display_name(tid, "?"),
					"relation": label,
				})
	if protagonist_id.is_empty():
		return out
	for npc in get_nearby_npcs():
		var to_id := str(npc.get("id", ""))
		out.append({
			"from_id": protagonist_id,
			"from_name": get_known_display_name(CharacterKnowledgeScript.SELF_KEY, "主角"),
			"to_id": to_id,
			"to_name": get_known_display_name(to_id, "?"),
			"relation": "相识",
		})
	return out


func _repair_npc_locations_if_needed() -> void:
	var npcs: Variant = npc_db.get("npcs", {})
	if not npcs is Dictionary:
		return
	var protagonist_id := str(mainrole.get("id", "")).strip_edges()
	var world_stub := {"map_structure": get_map_structure()}
	var dirty := false
	for npc_id in npcs:
		var npc: Dictionary = npcs[npc_id]
		if str(npc_id) == protagonist_id:
			continue
		var before_k := str(npc.get("current_key_node_id", "")).strip_edges()
		var before_r := str(npc.get("current_region_id", "")).strip_edges()
		RuntimeDbSchemas.normalize_npc_location(npc, world_stub)
		if (
			str(npc.get("current_key_node_id", "")).strip_edges() != before_k
			or str(npc.get("current_region_id", "")).strip_edges() != before_r
		):
			dirty = true
	if dirty:
		var payload := npc_db.duplicate(true)
		GameRunningFileManager.save_json_data(GameRunningFileManager.NPC_DB, payload)


func _repair_protagonist_map_cell_if_needed() -> void:
	var stored: Variant = mainrole.get("current_map_cell", null)
	if stored is Dictionary:
		var cell: Dictionary = stored
		if not str(cell.get("page_id", "")).strip_edges().is_empty():
			return
	var region_id := str(mainrole.get("current_region_id", "")).strip_edges()
	var key_node_id := str(mainrole.get("current_key_node_id", "")).strip_edges()
	if region_id.is_empty() and key_node_id.is_empty():
		return
	var ms := get_map_structure().duplicate(true)
	if ms.is_empty():
		return
	var before_role := JSON.stringify(mainrole)
	var before_map := JSON.stringify(ms)
	LocationResolverScript.resolve_and_apply(
		mainrole,
		ms,
		{
			"region_hint": region_id,
			"key_node_hint": key_node_id,
			"hint_text": str(mainrole.get("initial_scene", "")).strip_edges(),
		},
		{
			"allow_assign_key_node_cell": true,
			"include_map_cell": true,
		},
	)
	if JSON.stringify(mainrole) != before_role:
		GameRunningFileManager.save_json_data(GameRunningFileManager.MAIN_ROLE, mainrole)
	if JSON.stringify(ms) != before_map:
		map_db["map_structure"] = ms
		GameRunningFileManager.save_json_data(GameRunningFileManager.MAP_DB, map_db)


func _ensure_character_knowledge() -> void:
	var raw: Variant = game_state.get("character_knowledge", null)
	var protagonist_id := str(mainrole.get("id", "")).strip_edges()
	var nearby: Variant = game_state.get("nearby_npc_ids", [])
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		game_state["character_knowledge"] = CharacterKnowledgeScript.seed_initial(
			protagonist_id,
			nearby,
		)
	else:
		var store: Dictionary = raw as Dictionary
		CharacterKnowledgeScript.ensure_nearby_npc_baseline(store, protagonist_id, nearby)
		game_state["character_knowledge"] = store
	CharacterKnowledgeScript.upgrade_self_baseline(
		game_state["character_knowledge"],
		get_protagonist_truth(),
	)


static func _as_dict(data: Variant) -> Dictionary:
	return data if data is Dictionary else {}


func _snapshot_region_id_set(current_region_id: String) -> Dictionary:
	var allow: Dictionary = {}
	for rid in get_unlocked_region_id_list():
		if not rid.is_empty():
			allow[rid] = true
	if not current_region_id.is_empty():
		allow[current_region_id] = true
		for adj in get_adjacent_region_ids(current_region_id):
			allow[adj] = true
	return allow


func _npcs_in_local_travel_range() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var current_region := str(mainrole.get("current_region_id", "")).strip_edges()
	if current_region.is_empty():
		return out
	var allow := _snapshot_region_id_set(current_region)
	var protagonist_id := str(mainrole.get("id", "")).strip_edges()
	var ids: Variant = game_state.get("nearby_npc_ids", [])
	if not ids is Array:
		return out
	for id_val in ids:
		var npc_id := str(id_val).strip_edges()
		if npc_id.is_empty() or npc_id == protagonist_id:
			continue
		var npc := get_npc(npc_id)
		if npc.is_empty():
			continue
		var loc := LocationServiceScript.get_npc_location(self, npc)
		var region_id := str(loc.get("region_id", "")).strip_edges()
		if region_id.is_empty() or not allow.has(region_id):
			continue
		out.append(npc)
	return out


func _inventory_brief_for_snapshot() -> Array:
	var full := get_inventory_brief()
	if full.size() <= MAX_INVENTORY_ITEMS_IN_SNAPSHOT:
		return full
	return full.slice(0, MAX_INVENTORY_ITEMS_IN_SNAPSHOT)


func _build_npc_locations_snapshot() -> Dictionary:
	var out: Dictionary = {}
	var pool: Array[Dictionary] = []
	var present_ids := get_present_npc_ids()
	if not present_ids.is_empty():
		for nid in present_ids:
			var npc := get_npc(nid)
			if not npc.is_empty():
				pool.append(npc)
	else:
		pool = get_nearby_npcs()
	for npc in pool:
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		var loc := LocationServiceScript.get_npc_location(self, npc)
		out[nid] = {
			"region_id": loc.get("region_id", ""),
			"key_node_id": loc.get("key_node_id", ""),
			"path": LocationServiceScript.format_location_path(self, loc),
		}
	return out


func _npc_favorability_for_snapshot() -> Dictionary:
	var out: Dictionary = {}
	RuntimeDbSchemas.ensure_npc_favorability(game_state)
	var store: Variant = game_state.get("npc_favorability", {})
	if not store is Dictionary:
		return out
	for nid in (store as Dictionary):
		var npc_id := str(nid).strip_edges()
		if npc_id.is_empty():
			continue
		var value := int((store as Dictionary)[nid])
		if value == 0:
			continue
		out[npc_id] = value
	return out


func _nature_dict() -> Dictionary:
	var env_root: Variant = base_config.get("world_setting", base_config.get("base_config", {}))
	if not env_root is Dictionary:
		return {}
	var nature: Variant = (env_root as Dictionary).get("nature_env", {})
	return nature if nature is Dictionary else {}


func _npc_name(npc_id: String) -> String:
	return get_known_display_name(npc_id, npc_id)


static func _adventure_for_player_snapshot(adventure: Dictionary) -> Dictionary:
	var out := adventure.duplicate(true)
	out.erase("dm_secrets")
	return out


static func _last_check_from_history(history: Variant) -> Dictionary:
	if not history is Array or history.is_empty():
		return {}
	var last: Variant = history[history.size() - 1]
	return last if last is Dictionary else {}
