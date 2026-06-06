class_name NarrativeHookNormalizer
extends RefCounted

const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const CharacterKnowledgeScript := preload("res://src/game/logic/data/character_knowledge.gd")
const SceneTargetResolverScript := preload("res://src/game/logic/world/scene_target_resolver.gd")


## 将 AI 输出的 hook 规范为可写入运行时的结构（名称→id、缺省字段沿用当前状态）。
static func normalize(
	hook: Dictionary,
	read_model: GameReadModel,
	game_state: Dictionary,
) -> Dictionary:
	var out := hook.duplicate(true)
	var state := game_state if game_state is Dictionary else {}

	var nature := read_model.get_nature_env()

	var dt := str(out.get("datetime_display", "")).strip_edges()
	if dt.is_empty():
		dt = str(state.get("datetime_display", "")).strip_edges()
	out["datetime_display"] = WorldSettingDisplay.compact_stored_display(
		dt, nature, "start_time", "start_time_keywords",
	)

	var weather := str(out.get("weather", "")).strip_edges()
	if weather.is_empty():
		weather = str(state.get("weather", "")).strip_edges()
	out["weather"] = WorldSettingDisplay.compact_stored_display(
		weather, nature, "weather", "weather_keywords", "晴",
	)

	var region_raw := str(out.get("current_region_id", "")).strip_edges()
	if not region_raw.is_empty():
		out["current_region_id"] = _resolve_region_id(region_raw, read_model)

	if out.has("current_key_node_id"):
		var node_raw := str(out.get("current_key_node_id", "")).strip_edges()
		if node_raw.is_empty():
			out["current_key_node_id"] = ""
		else:
			out["current_key_node_id"] = _resolve_key_node_id(node_raw, read_model)

	if out.has("present_npc_ids"):
		out["present_npc_ids"] = _normalize_npc_id_list(out.get("present_npc_ids", []), read_model)

	if out.has("npc_location_updates"):
		out["npc_location_updates"] = _normalize_npc_location_updates(
			out.get("npc_location_updates", []),
			read_model,
		)

	if out.has("scene_targets"):
		out["scene_targets"] = _normalize_scene_targets(out.get("scene_targets", []), read_model)

	if out.has("discoveries"):
		out["discoveries"] = _normalize_discoveries(out.get("discoveries", []), read_model)

	if out.has("favorability_delta"):
		out["favorability_delta"] = _normalize_favorability_delta(
			out.get("favorability_delta", []),
			read_model,
		)

	return out


static func can_apply(hook: Dictionary) -> bool:
	return (
		not str(hook.get("datetime_display", "")).strip_edges().is_empty()
		and not str(hook.get("weather", "")).strip_edges().is_empty()
	)


static func _resolve_region_id(raw: String, read_model: GameReadModel) -> String:
	var token := raw.strip_edges()
	if token.is_empty():
		return ""
	if not read_model.get_region(token).is_empty():
		return token
	for region in read_model.get_regions():
		if region is Dictionary:
			var rid := str(region.get("id", "")).strip_edges()
			var rname := str(region.get("name", "")).strip_edges()
			if token == rname or token == rid:
				return rid
			if not rname.is_empty() and (rname in token or token in rname):
				return rid
	return token


static func _resolve_key_node_id(raw: String, read_model: GameReadModel) -> String:
	var token := raw.strip_edges()
	if token.is_empty():
		return ""
	if not LocationServiceScript.get_key_node(read_model, token).is_empty():
		return token
	for node in read_model.get_key_nodes():
		if not node is Dictionary:
			continue
		var nid := str(node.get("id", "")).strip_edges()
		var nname := str(node.get("name", "")).strip_edges()
		if token == nname or token == nid:
			return nid
		if not nname.is_empty() and (nname in token or token in nname):
			return nid
	return token


static func _normalize_npc_id_list(raw: Variant, read_model: GameReadModel) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for item in raw:
		var resolved := _resolve_npc_id(str(item).strip_edges(), read_model)
		if not resolved.is_empty() and resolved not in out:
			out.append(resolved)
	return out


static func _normalize_npc_location_updates(raw: Variant, read_model: GameReadModel) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for item in raw:
		if not item is Dictionary:
			continue
		var entry := (item as Dictionary).duplicate(true)
		var nid := _resolve_npc_id(str(entry.get("id", "")).strip_edges(), read_model)
		if nid.is_empty():
			continue
		entry["id"] = nid
		var region_raw := str(entry.get("current_region_id", "")).strip_edges()
		if not region_raw.is_empty():
			entry["current_region_id"] = _resolve_region_id(region_raw, read_model)
		var node_raw := str(entry.get("current_key_node_id", "")).strip_edges()
		if node_raw.is_empty():
			entry["current_key_node_id"] = ""
		else:
			entry["current_key_node_id"] = _resolve_key_node_id(node_raw, read_model)
		out.append(entry)
	return out


static func _normalize_discoveries(raw: Variant, read_model: GameReadModel) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for item in raw:
		if not item is Dictionary:
			continue
		var entry := (item as Dictionary).duplicate(true)
		var target := str(entry.get("target", "")).strip_edges()
		if target.is_empty():
			continue
		if target != CharacterKnowledgeScript.SELF_KEY:
			target = _resolve_npc_id(target, read_model)
			if target.is_empty():
				continue
		entry["target"] = target
		var fields_out: Array = []
		var fields_raw: Variant = entry.get("fields", [])
		if fields_raw is Array:
			for raw_field in fields_raw:
				var field := str(raw_field).strip_edges()
				if field.is_empty():
					continue
				if field not in CharacterKnowledgeScript.PROFILE_FIELDS:
					continue
				if field not in fields_out:
					fields_out.append(field)
		if fields_out.is_empty():
			continue
		entry["fields"] = fields_out
		out.append(entry)
	return out


static func _normalize_favorability_delta(raw: Variant, read_model: GameReadModel) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for item in raw:
		if not item is Dictionary:
			continue
		var entry := (item as Dictionary).duplicate(true)
		var nid := _resolve_npc_id(str(entry.get("id", "")).strip_edges(), read_model)
		if nid.is_empty():
			continue
		if not entry.has("delta"):
			continue
		out.append({"id": nid, "delta": int(entry.get("delta", 0))})
	return out


static func _normalize_scene_targets(raw: Variant, read_model: GameReadModel) -> Array:
	return SceneTargetResolverScript.normalize_target_list(raw, read_model)


static func resolve_npc_id(raw: String, read_model: GameReadModel) -> String:
	return _resolve_npc_id(raw, read_model)


static func _resolve_npc_id(raw: String, read_model: GameReadModel) -> String:
	var token := raw.strip_edges()
	if token.is_empty():
		return ""
	if not read_model.get_npc(token).is_empty():
		return token
	for npc in read_model.get_nearby_npcs():
		if not npc is Dictionary:
			continue
		var nid := str(npc.get("id", "")).strip_edges()
		var nname := str(npc.get("name", "")).strip_edges()
		if token == nid or token == nname:
			return nid
		if not nname.is_empty() and (nname in token or token in nname):
			return nid
	var npcs: Variant = read_model.npc_db.get("npcs", {})
	if npcs is Dictionary:
		for npc_id in npcs:
			var npc: Dictionary = npcs[npc_id]
			var nname := str(npc.get("name", "")).strip_edges()
			if token == str(npc_id) or token == nname:
				return str(npc_id).strip_edges()
			if not nname.is_empty() and (nname in token or token in nname):
				return str(npc_id).strip_edges()
	return token
