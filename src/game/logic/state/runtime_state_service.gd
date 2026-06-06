class_name RuntimeStateService
extends RefCounted

const CharacterKnowledgeScript := preload("res://src/game/logic/data/character_knowledge.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const SceneTargetResolverScript := preload("res://src/game/logic/world/scene_target_resolver.gd")
const LocationResolverScript := preload("res://src/game/logic/world/location_resolver.gd")
const NarrativeArchiveServiceScript := preload(
	"res://src/game/logic/narrative/narrative_archive_service.gd"
)

var _game_state: Dictionary = {}
var _mainrole: Dictionary = {}


func load_from_runtime() -> void:
	_game_state = _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.GAME_STATE))
	_mainrole = _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.MAIN_ROLE))
	if _game_state.is_empty():
		_game_state = RuntimeDbSchemas.empty_game_state()
	RuntimeDbSchemas.ensure_talked_npc_ids(_game_state)
	RuntimeDbSchemas.ensure_npc_favorability(_game_state)


func get_game_state() -> Dictionary:
	return _game_state


func get_mainrole() -> Dictionary:
	return _mainrole


func apply_location_travel(target_loc: Dictionary, valid_region_ids: Array, read_model: GameReadModel = null) -> Dictionary:
	var hook := {
		"datetime_display": str(_game_state.get("datetime_display", "")).strip_edges(),
		"weather": str(_game_state.get("weather", "")).strip_edges(),
		"current_region_id": str(target_loc.get("region_id", "")).strip_edges(),
		"current_key_node_id": str(target_loc.get("key_node_id", "")).strip_edges(),
	}
	return apply_hook(hook, valid_region_ids, read_model)


func apply_map_cell_travel(
	target_loc: Dictionary,
	page_id: String,
	x: int,
	y: int,
	valid_region_ids: Array,
	read_model: GameReadModel = null,
) -> Dictionary:
	var hook := {
		"datetime_display": str(_game_state.get("datetime_display", "")).strip_edges(),
		"weather": str(_game_state.get("weather", "")).strip_edges(),
		"current_region_id": str(target_loc.get("region_id", "")).strip_edges(),
		"current_key_node_id": str(target_loc.get("key_node_id", "")).strip_edges(),
		"current_map_cell": {
			"page_id": page_id.strip_edges(),
			"x": x,
			"y": y,
		},
	}
	return apply_hook(hook, valid_region_ids, read_model)


func apply_hook(hook: Dictionary, valid_region_ids: Array, read_model: GameReadModel = null) -> Dictionary:
	if hook.is_empty():
		return {"ok": false, "reason": "hook 为空"}

	var state := _game_state.duplicate(true)
	var role := _mainrole.duplicate(true)
	var warnings: PackedStringArray = []

	var dt := str(hook.get("datetime_display", "")).strip_edges()
	if dt.is_empty():
		return {"ok": false, "reason": "datetime_display 必填"}
	state["datetime_display"] = dt

	var weather := str(hook.get("weather", "")).strip_edges()
	if weather.is_empty():
		return {"ok": false, "reason": "weather 必填"}
	state["weather"] = weather

	var region_id := str(hook.get("current_region_id", "")).strip_edges()
	var resolver_hints := {"hint_text": ""}
	var should_resolve_location := false
	if not region_id.is_empty():
		if not _region_id_valid(region_id, valid_region_ids):
			warnings.append("非法 current_region_id: %s" % region_id)
		else:
			resolver_hints["region_hint"] = region_id
			should_resolve_location = true
			var unlocked: Array = state.get("unlocked_region_ids", [])
			if unlocked is Array and region_id not in unlocked:
				unlocked.append(region_id)
				state["unlocked_region_ids"] = unlocked

	if hook.has("current_key_node_id"):
		var key_node_id := str(hook.get("current_key_node_id", "")).strip_edges()
		if key_node_id.is_empty():
			resolver_hints["key_node_hint"] = ""
			should_resolve_location = true
		elif read_model == null:
			resolver_hints["key_node_hint"] = key_node_id
			should_resolve_location = true
		elif key_node_id in LocationServiceScript.get_key_node_ids(read_model):
			var target_region := str(resolver_hints.get("region_hint", role.get("current_region_id", ""))).strip_edges()
			if LocationServiceScript.key_node_belongs_to_region(read_model, key_node_id, target_region):
				resolver_hints["key_node_hint"] = key_node_id
				should_resolve_location = true
			else:
				warnings.append("key_node %s 与当前 region 不匹配" % key_node_id)
		else:
			warnings.append("非法 current_key_node_id: %s" % key_node_id)
	elif resolver_hints.has("region_hint"):
		var prev_region := str(role.get("current_region_id", "")).strip_edges()
		if prev_region != resolver_hints["region_hint"]:
			resolver_hints["key_node_hint"] = ""
			should_resolve_location = true

	if hook.get("current_map_cell") is Dictionary:
		resolver_hints["map_cell_hint"] = (hook.get("current_map_cell") as Dictionary).duplicate(true)
		should_resolve_location = true

	var map_structure := LocationResolverScript.map_structure_from_read_model(read_model)
	if should_resolve_location:
		var loc_result := LocationResolverScript.resolve_and_apply(
			role,
			map_structure,
			resolver_hints,
			{"valid_region_ids": valid_region_ids, "include_map_cell": true},
		)
		for w in loc_result.get("warnings", []):
			warnings.append(str(w))
	elif _needs_map_cell_sync(role):
		LocationResolverScript.sync_map_cell_for_role(role, map_structure)

	var discoveries: Variant = hook.get("discoveries", [])
	if discoveries is Array and not discoveries.is_empty():
		var knowledge: Variant = state.get("character_knowledge", null)
		if not knowledge is Dictionary or (knowledge as Dictionary).is_empty():
			state["character_knowledge"] = CharacterKnowledgeScript.seed_initial(
				str(role.get("id", "")),
				state.get("nearby_npc_ids", []),
			)
		var npc_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.NPC_DB))
		var discovery_warnings := CharacterKnowledgeScript.apply_discoveries(
			state["character_knowledge"],
			discoveries,
			role,
			npc_db,
		)
		for w in discovery_warnings:
			warnings.append(w)

	var suggestions: Variant = hook.get("suggestions", null)
	if suggestions is Array:
		state["last_suggestions"] = _normalize_suggestion_list(suggestions)

	var hook_wallet: Variant = hook.get("wallet", null)
	if hook_wallet is Dictionary:
		_apply_wallet_hook(role, hook_wallet as Dictionary, warnings)

	var inventory_delta: Variant = hook.get("inventory_delta", [])
	if inventory_delta is Array and not (inventory_delta as Array).is_empty():
		_apply_inventory_delta(role, inventory_delta as Array, warnings)

	var unlock_ids: Variant = hook.get("unlock_region_ids", [])
	if unlock_ids is Array and not (unlock_ids as Array).is_empty():
		_apply_unlock_region_ids(state, unlock_ids as Array, valid_region_ids, warnings)

	if hook.has("present_npc_ids"):
		_apply_present_npc_ids(state, hook, warnings)

	var location_warnings := _apply_npc_location_updates(hook, read_model, valid_region_ids)
	for w in location_warnings:
		warnings.append(w)

	_apply_scene_targets(state, hook, read_model)
	_apply_scene_pressure_delta(state, hook)
	_apply_favorability_delta(state, hook, warnings)

	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return {"ok": false, "reason": "无法保存 game_state"}
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.MAIN_ROLE, role):
		return {"ok": false, "reason": "无法保存 mainrole"}

	_game_state = state
	_mainrole = role
	return {"ok": true, "warnings": warnings}


func append_story_entry(role: String, content: String) -> bool:
	var text := content.strip_edges()
	var state := _game_state.duplicate(true)
	var log: Array = state.get("story_log", [])
	if not log is Array:
		log = []
	log.append({
		"role": role,
		"content": content,
		"ts": int(Time.get_unix_time_from_system()),
	})
	state["story_log"] = log
	if not text.is_empty() and (str(role).strip_edges() == "user" or str(role).strip_edges() == "assistant"):
		var since := maxi(0, int(state.get("chars_since_last_archive", 0)))
		state["chars_since_last_archive"] = since + text.length()
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return false
	_game_state = state
	return true


## 将 story_log 中最后一条 assistant 正文替换为 display 文本（如 dynamic_add 回填后）。
func update_last_assistant_story_content(content: String) -> bool:
	var text := content.strip_edges()
	if text.is_empty():
		return false
	var state := _game_state.duplicate(true)
	var log: Array = state.get("story_log", [])
	if not log is Array or log.is_empty():
		return false
	for i in range(log.size() - 1, -1, -1):
		var entry: Variant = log[i]
		if not entry is Dictionary:
			continue
		if str(entry.get("role", "")).strip_edges() != "assistant":
			continue
		var row: Dictionary = (entry as Dictionary).duplicate(true)
		row["content"] = text
		log[i] = row
		state["story_log"] = log
		if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
			return false
		_game_state = state
		return true
	return false


func record_talked_npc(npc_id: String) -> bool:
	var state := _game_state.duplicate(true)
	RuntimeDbSchemas.record_talked_npc(state, npc_id)
	if state.get("talked_npc_ids", []) == _game_state.get("talked_npc_ids", []):
		return true
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return false
	_game_state = state
	return true


func save_narrative_messages(messages: Array) -> bool:
	var state := _game_state.duplicate(true)
	state["narrative_messages"] = messages.duplicate(true)
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return false
	_game_state = state
	return true


func get_narrative_messages() -> Array:
	var raw: Variant = _game_state.get("narrative_messages", [])
	return raw.duplicate(true) if raw is Array else []


func get_story_log() -> Array:
	var raw: Variant = _game_state.get("story_log", [])
	return raw.duplicate(true) if raw is Array else []


func get_last_archive_story_index() -> int:
	return maxi(0, int(_game_state.get("last_archive_story_index", 0)))


func get_chars_since_last_archive() -> int:
	if _game_state.has("chars_since_last_archive"):
		return maxi(0, int(_game_state.get("chars_since_last_archive", 0)))
	return NarrativeArchiveServiceScript.count_story_log_chars(get_story_log(), 0)


func get_narrative_memory() -> Array:
	var raw: Variant = _game_state.get("narrative_memory", [])
	return raw.duplicate(true) if raw is Array else []


func finalize_archive(
	event_entry: Dictionary,
	compact_body: String,
	retained_messages: Array = [],
	retained_story_tail: Array = [],
) -> bool:
	var state := _game_state.duplicate(true)
	var log: Array = state.get("event_log", [])
	if not log is Array:
		log = []
	var entry: Dictionary = event_entry.duplicate()
	if not entry.has("timestamp"):
		entry["timestamp"] = _next_event_timestamp(log)
	log.append(entry)
	state["event_log"] = log

	var memory: Array = state.get("narrative_memory", [])
	if not memory is Array:
		memory = []
	var compact := compact_body.strip_edges()
	if not compact.is_empty():
		memory.append(compact)
		const MAX_MEMORY_SEGMENTS := 12
		while memory.size() > MAX_MEMORY_SEGMENTS:
			memory.remove_at(0)
	state["narrative_memory"] = memory

	_append_narrative_outline(state, entry)

	var kept_msgs: Array = []
	for msg in retained_messages:
		if msg is Dictionary:
			kept_msgs.append((msg as Dictionary).duplicate(true))
	state["narrative_messages"] = kept_msgs

	var kept_story: Array = []
	for item in retained_story_tail:
		if item is Dictionary:
			kept_story.append((item as Dictionary).duplicate(true))
	state["story_log"] = kept_story
	state["last_archive_story_index"] = 0
	state["chars_since_last_archive"] = NarrativeArchiveServiceScript.count_story_log_chars(
		kept_story,
		0,
	)

	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return false
	_game_state = state
	return true


static func _append_narrative_outline(state: Dictionary, event_entry: Dictionary) -> void:
	var summary := str(event_entry.get("summary", "")).strip_edges()
	var title := str(event_entry.get("title", "")).strip_edges()
	var line := ""
	if not title.is_empty() and not summary.is_empty():
		line = "%s：%s" % [title, summary]
	elif not summary.is_empty():
		line = summary
	elif not title.is_empty():
		line = title
	if line.is_empty():
		return
	var outline := str(state.get("narrative_outline", "")).strip_edges()
	if outline.is_empty():
		state["narrative_outline"] = line
	else:
		state["narrative_outline"] = "%s\n%s" % [outline, line]
	const MAX_OUTLINE_CHARS := 3000
	var full := str(state.get("narrative_outline", ""))
	if full.length() > MAX_OUTLINE_CHARS:
		state["narrative_outline"] = full.substr(full.length() - MAX_OUTLINE_CHARS)


func get_pinned_recall_event() -> Dictionary:
	var raw: Variant = _game_state.get("pinned_recall_event", null)
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		return (raw as Dictionary).duplicate(true)
	return {}


static func events_match_recall(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var title_a := str(a.get("title", "")).strip_edges()
	var title_b := str(b.get("title", "")).strip_edges()
	if title_a.is_empty() or title_b.is_empty() or title_a != title_b:
		return false
	var ts_a := int(a.get("timestamp", -1))
	var ts_b := int(b.get("timestamp", -1))
	if ts_a >= 0 and ts_b >= 0:
		return ts_a == ts_b
	return true


func set_pinned_recall_event(event: Dictionary) -> bool:
	var state := _game_state.duplicate(true)
	if event.is_empty():
		state.erase("pinned_recall_event")
	else:
		state["pinned_recall_event"] = event.duplicate(true)
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return false
	_game_state = state
	return true


func consume_pinned_recall_event() -> Dictionary:
	var raw: Variant = _game_state.get("pinned_recall_event", null)
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	var state := _game_state.duplicate(true)
	state.erase("pinned_recall_event")
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return raw if raw is Dictionary else {}
	_game_state = state
	return raw


func has_story_log() -> bool:
	var raw: Variant = _game_state.get("story_log", [])
	return raw is Array and not raw.is_empty()


func get_last_suggestions() -> Array:
	var raw: Variant = _game_state.get("last_suggestions", [])
	return raw.duplicate(true) if raw is Array else []


func save_last_suggestions(items: Array) -> bool:
	var state := _game_state.duplicate(true)
	state["last_suggestions"] = _normalize_suggestion_list(items)
	if not GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, state):
		return false
	_game_state = state
	return true


static func _normalize_suggestion_list(items: Array) -> Array:
	var out: Array = []
	for item in items:
		var text := str(item).strip_edges()
		if not text.is_empty() and text not in out:
			out.append(text)
		if out.size() >= 4:
			break
	return out


static func _region_id_valid(region_id: String, valid_region_ids: Array) -> bool:
	for id_val in valid_region_ids:
		if str(id_val).strip_edges() == region_id:
			return true
	return false


static func _needs_map_cell_sync(role: Dictionary) -> bool:
	var stored: Variant = role.get("current_map_cell", null)
	if stored is Dictionary:
		var cell: Dictionary = stored
		if not str(cell.get("page_id", "")).strip_edges().is_empty():
			return false
	var region_id := str(role.get("current_region_id", "")).strip_edges()
	var key_node_id := str(role.get("current_key_node_id", "")).strip_edges()
	return not region_id.is_empty() or not key_node_id.is_empty()


static func _next_event_timestamp(event_log: Array) -> int:
	var max_ts := 0
	for item in event_log:
		if item is Dictionary:
			max_ts = maxi(max_ts, int(item.get("timestamp", 0)))
	return max_ts + 1


static func _apply_wallet_hook(role: Dictionary, hook_wallet: Dictionary, warnings: PackedStringArray) -> void:
	RuntimeDbSchemas.ensure_mainrole_stats_wallet(role)
	var stats: Dictionary = role.get("stats", {})
	var current := RuntimeDbSchemas.normalize_wallet(stats.get("wallet", {}))
	var merged := current.duplicate(true)

	var unit_id := str(hook_wallet.get("unit_id", "")).strip_edges()
	if not unit_id.is_empty():
		if not current["unit_id"].is_empty() and current["unit_id"] != unit_id:
			warnings.append("wallet unit_id 与已有不一致，已忽略: %s" % unit_id)
		else:
			merged["unit_id"] = unit_id

	var unit_name := str(hook_wallet.get("unit_name", "")).strip_edges()
	if not unit_name.is_empty():
		if current["unit_name"].is_empty():
			merged["unit_name"] = unit_name
		elif current["unit_name"] != unit_name:
			warnings.append("wallet unit_name 与已有不一致，已忽略: %s" % unit_name)

	if hook_wallet.has("amount"):
		merged["amount"] = maxi(0, int(hook_wallet.get("amount", 0)))
	elif hook_wallet.has("delta"):
		merged["amount"] = maxi(0, int(current.get("amount", 0)) + int(hook_wallet.get("delta", 0)))

	stats["wallet"] = merged
	role["stats"] = stats


static func _apply_inventory_delta(role: Dictionary, deltas: Array, warnings: PackedStringArray) -> void:
	var catalog := _load_item_ids_catalog()
	var items: Array = role.get("items", [])
	if not items is Array:
		items = []
	for raw in deltas:
		if not raw is Dictionary:
			warnings.append("inventory_delta 条目须为对象")
			continue
		var entry := raw as Dictionary
		var op := str(entry.get("op", "")).strip_edges().to_lower()
		var item_id := str(entry.get("id", "")).strip_edges()
		var qty := maxi(1, int(entry.get("quantity", 1)))
		if item_id.is_empty():
			warnings.append("inventory_delta 缺少 id")
			continue
		if not catalog.has(item_id):
			warnings.append("未知物品 id: %s" % item_id)
			continue
		if op == "add":
			_add_item_quantity(items, item_id, qty)
		elif op == "remove":
			if not _remove_item_quantity(items, item_id, qty):
				warnings.append("物品数量不足: %s" % item_id)
		else:
			warnings.append("inventory_delta 非法 op: %s" % op)
	role["items"] = items


static func _apply_present_npc_ids(
	state: Dictionary,
	hook: Dictionary,
	warnings: PackedStringArray,
) -> void:
	var raw: Variant = hook.get("present_npc_ids", null)
	if raw == null:
		return
	if not raw is Array:
		warnings.append("present_npc_ids 须为数组")
		return
	var npc_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.NPC_DB))
	var npcs: Variant = npc_db.get("npcs", {})
	var ids: Array = []
	for item in raw:
		var nid := str(item).strip_edges()
		if nid.is_empty() or nid in ids:
			continue
		if npcs is Dictionary and not npcs.is_empty() and not npcs.has(nid):
			warnings.append("present_npc_ids 未知 NPC: %s" % nid)
		ids.append(nid)
	state["present_npc_ids"] = ids
	var pool: Variant = state.get("nearby_npc_ids", [])
	if not pool is Array:
		pool = []
	for nid in ids:
		if nid not in pool:
			pool.append(nid)
	state["nearby_npc_ids"] = pool


static func _apply_npc_location_updates(
	hook: Dictionary,
	read_model: GameReadModel,
	valid_region_ids: Array,
) -> PackedStringArray:
	var warnings: PackedStringArray = []
	var raw: Variant = hook.get("npc_location_updates", [])
	if not raw is Array or (raw as Array).is_empty():
		return warnings

	var npc_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.NPC_DB))
	var npcs: Variant = npc_db.get("npcs", {})
	if not npcs is Dictionary:
		warnings.append("npc_db 无效，无法更新 NPC 位置")
		return warnings

	var dirty := false
	for item in raw:
		if not item is Dictionary:
			warnings.append("npc_location_updates 条目须为对象")
			continue
		var entry := item as Dictionary
		var nid := str(entry.get("id", "")).strip_edges()
		if nid.is_empty():
			warnings.append("npc_location_updates 缺少 id")
			continue
		if not npcs.has(nid):
			warnings.append("未知 NPC id: %s" % nid)
			continue
		var npc: Dictionary = npcs[nid]
		var resolver_hints := {"hint_text": ""}
		var should_update := false
		var region_id := str(entry.get("current_region_id", "")).strip_edges()
		if not region_id.is_empty():
			if not _region_id_valid(region_id, valid_region_ids):
				warnings.append("npc_location_updates 非法 region: %s" % region_id)
			else:
				resolver_hints["region_hint"] = region_id
				should_update = true
		if entry.has("current_key_node_id"):
			var key_node_id := str(entry.get("current_key_node_id", "")).strip_edges()
			if key_node_id.is_empty():
				resolver_hints["key_node_hint"] = ""
				should_update = true
			elif read_model == null:
				resolver_hints["key_node_hint"] = key_node_id
				should_update = true
			elif key_node_id in LocationServiceScript.get_key_node_ids(read_model):
				resolver_hints["key_node_hint"] = key_node_id
				should_update = true
			else:
				warnings.append("npc_location_updates 非法 key_node: %s" % key_node_id)
		if should_update:
			var map_structure := LocationResolverScript.map_structure_from_read_model(read_model)
			var loc_result := LocationResolverScript.resolve_and_apply(
				npc,
				map_structure,
				resolver_hints,
				{
					"valid_region_ids": valid_region_ids,
					"include_map_cell": false,
				},
			)
			for w in loc_result.get("warnings", []):
				warnings.append(str(w))
			dirty = true
		npcs[nid] = npc

	if dirty:
		npc_db["npcs"] = npcs
		if not GameRunningFileManager.save_json_data(GameRunningFileManager.NPC_DB, npc_db):
			warnings.append("无法保存 npc_db")

	return warnings


static func _apply_scene_targets(
	state: Dictionary,
	hook: Dictionary,
	read_model: GameReadModel = null,
) -> void:
	if hook.has("scene_targets"):
		var raw: Variant = hook.get("scene_targets", [])
		if raw is Array:
			state["scene_targets"] = _normalize_scene_target_list(raw as Array, read_model)
			return
	var suggestions: Variant = hook.get("suggestions", null)
	if suggestions is Array and not (suggestions as Array).is_empty():
		state["scene_targets"] = _normalize_scene_target_list(suggestions as Array, read_model)


static func _normalize_scene_target_list(items: Array, read_model: GameReadModel = null) -> Array:
	if read_model != null:
		return SceneTargetResolverScript.normalize_target_list(items, read_model)
	var out: Array = []
	for item in items:
		var text := str(item).strip_edges()
		if text.is_empty() or text in out:
			continue
		if text.length() > SceneTargetResolverScript.MAX_DISPLAY_LEN:
			text = text.substr(0, SceneTargetResolverScript.MAX_DISPLAY_LEN)
		out.append(text)
		if out.size() >= SceneTargetResolverScript.MAX_TARGETS:
			break
	return out


static func _apply_unlock_region_ids(
	state: Dictionary,
	unlock_ids: Array,
	valid_region_ids: Array,
	warnings: PackedStringArray,
) -> void:
	var unlocked: Array = state.get("unlocked_region_ids", [])
	if not unlocked is Array:
		unlocked = []
	for raw_id in unlock_ids:
		var region_id := str(raw_id).strip_edges()
		if region_id.is_empty():
			continue
		if not _region_id_valid(region_id, valid_region_ids):
			warnings.append("非法 unlock_region_id: %s" % region_id)
			continue
		if region_id not in unlocked:
			unlocked.append(region_id)
	state["unlocked_region_ids"] = unlocked


static func _load_item_ids_catalog() -> Dictionary:
	var ids: Dictionary = {}
	var items_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.ITEMS_DB))
	var items: Variant = items_db.get("items", {})
	if items is Dictionary:
		for item_id in items:
			ids[str(item_id)] = true
	var weapon_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.WEAPON_DB))
	var weapons: Variant = weapon_db.get("weapons", {})
	if weapons is Dictionary:
		for weapon_id in weapons:
			ids[str(weapon_id)] = true
	return ids


static func _add_item_quantity(items: Array, item_id: String, qty: int) -> void:
	for entry in items:
		if entry is Dictionary and str(entry.get("id", "")).strip_edges() == item_id:
			entry["quantity"] = maxi(1, int(entry.get("quantity", 1)) + qty)
			return
	items.append({"id": item_id, "quantity": qty})


static func _remove_item_quantity(items: Array, item_id: String, qty: int) -> bool:
	for i in items.size():
		var entry: Variant = items[i]
		if not entry is Dictionary:
			continue
		if str(entry.get("id", "")).strip_edges() != item_id:
			continue
		var have := maxi(1, int(entry.get("quantity", 1)))
		if have < qty:
			return false
		var left := have - qty
		if left <= 0:
			items.remove_at(i)
		else:
			(entry as Dictionary)["quantity"] = left
		return true
	return false


static func _apply_scene_pressure_delta(state: Dictionary, hook: Dictionary) -> void:
	if not hook.has("scene_pressure_delta"):
		return
	var delta := int(hook.get("scene_pressure_delta", 0))
	if delta == 0:
		return
	var current := maxi(0, int(state.get("scene_pressure", 0)))
	state["scene_pressure"] = maxi(0, current + delta)


static func _apply_favorability_delta(
	state: Dictionary,
	hook: Dictionary,
	warnings: PackedStringArray,
) -> void:
	var raw: Variant = hook.get("favorability_delta", [])
	if not raw is Array or (raw as Array).is_empty():
		return
	var npc_db := _as_dict(GameRunningFileManager.load_json_data(GameRunningFileManager.NPC_DB))
	var npcs: Variant = npc_db.get("npcs", {})
	for item in raw:
		if not item is Dictionary:
			warnings.append("favorability_delta 条目须为对象")
			continue
		var entry := item as Dictionary
		var nid := str(entry.get("id", "")).strip_edges()
		if nid.is_empty():
			warnings.append("favorability_delta 缺少 id")
			continue
		if npcs is Dictionary and not npcs.is_empty() and not npcs.has(nid):
			warnings.append("favorability_delta 未知 NPC: %s" % nid)
		if not entry.has("delta"):
			warnings.append("favorability_delta 缺少 delta: %s" % nid)
			continue
		RuntimeDbSchemas.apply_npc_favorability_delta(state, nid, int(entry.get("delta", 0)))


static func _as_dict(data: Variant) -> Dictionary:
	return data if data is Dictionary else {}
