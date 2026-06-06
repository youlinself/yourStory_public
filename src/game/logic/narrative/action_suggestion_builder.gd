class_name ActionSuggestionBuilder
extends RefCounted

## 行动建议（红框）：AI 的 STATE_HOOK.suggestions 经 filter 后与规则兜底 merge，最多 4 条。
## 规则顺序：场景物 → 在场/近途 NPC（同场搭话）→ 区域/技能/观察兜底；有场景上下文时不罗列远途寻人。

const SkillCatalog := preload("res://src/game/logic/data/skill_display_catalog.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")
const SceneTargetResolverScript := preload("res://src/game/logic/world/scene_target_resolver.gd")

const MAX_SUGGESTIONS := 4
const MAX_LABEL_LEN := 24
const MAX_SCENE_TARGET_SUGGESTIONS := 2
const MAX_REMOTE_NPC_SUGGESTIONS := 2


static func build_from_read_model(read_model: GameReadModel) -> PackedStringArray:
	var out: PackedStringArray = []
	_append_scene_target_suggestions(read_model, out)
	_append_npc_suggestions(read_model, out)
	if not read_model.has_scene_context():
		_append_region_suggestions(read_model, out)
	_append_skill_suggestions(read_model, out)
	_append_fallback_suggestions(out)
	return _trim_unique(out)


static func merge(ai_suggestions: Array, rule_suggestions: PackedStringArray) -> PackedStringArray:
	var co_loc_talk := ""
	var other_rules: PackedStringArray = []
	for text in rule_suggestions:
		if text.begins_with("与") and text.ends_with("搭话"):
			if co_loc_talk.is_empty():
				co_loc_talk = text
			else:
				other_rules.append(text)
		else:
			other_rules.append(text)

	var out: PackedStringArray = []
	var ai_cap := MAX_SUGGESTIONS - (1 if not co_loc_talk.is_empty() else 0)
	for item in ai_suggestions:
		var label := _normalize_label(str(item))
		if label.is_empty():
			continue
		_append_unique(out, label)
		if out.size() >= ai_cap:
			break
	if not co_loc_talk.is_empty():
		_append_unique(out, co_loc_talk)
	for text in other_rules:
		_append_unique(out, text)
		if out.size() >= MAX_SUGGESTIONS:
			break
	return _trim_unique(out)


static func filter_suggestions_against_world(read_model: GameReadModel, suggestions: Array) -> Array:
	var out: Array = []
	for item in suggestions:
		var text := _sanitize_suggestion(str(item), read_model)
		if text.is_empty():
			continue
		if _is_invalid_travel_suggestion(text, read_model):
			push_warning("[ActionSuggestionBuilder] 过滤未登记地点建议: %s" % text)
			continue
		out.append(text)
	return out


static func _is_invalid_travel_suggestion(text: String, read_model: GameReadModel) -> bool:
	var prefixes: PackedStringArray = ["前往", "去", "赶往", "赶到"]
	var destination := ""
	for prefix in prefixes:
		if text.begins_with(prefix):
			destination = text.substr(prefix.length()).strip_edges()
			break
	if destination.is_empty():
		return false
	if _destination_known(destination, read_model):
		return false
	return true


static func _destination_known(destination: String, read_model: GameReadModel) -> bool:
	var needle := destination.strip_edges()
	if needle.is_empty():
		return true
	for region in read_model.get_unlocked_regions():
		var rname := str(region.get("name", "")).strip_edges()
		var rid := str(region.get("id", "")).strip_edges()
		if needle == rname or needle == rid or (not rname.is_empty() and rname in needle):
			return true
	for node in read_model.get_key_nodes():
		var nname := str(node.get("name", "")).strip_edges()
		if nname.is_empty():
			continue
		if needle == nname or nname in needle or needle in nname:
			return true
	return false


static func parse_hook_suggestions(hook: Dictionary) -> Array:
	var raw: Variant = hook.get("suggestions", [])
	if not raw is Array:
		return []
	var out: Array = []
	for item in raw:
		var text := _normalize_label(str(item))
		if not text.is_empty():
			out.append(text)
	return out


static func _append_scene_target_suggestions(read_model: GameReadModel, out: PackedStringArray) -> void:
	var added := 0
	for target in read_model.get_scene_targets():
		var display := _resolve_observe_target(str(target), read_model)
		if display.is_empty():
			continue
		var label := "观察%s" % display
		_append_unique(out, label)
		added += 1
		if added >= MAX_SCENE_TARGET_SUGGESTIONS or out.size() >= MAX_SUGGESTIONS:
			return


static func _append_npc_suggestions(read_model: GameReadModel, out: PackedStringArray) -> void:
	var here := LocationServiceScript.get_protagonist_location(read_model)
	var present_set: Dictionary = {}
	for nid in read_model.get_present_npc_ids():
		present_set[nid] = true
	var remote_added := 0
	for npc in read_model.get_rule_suggestion_npcs():
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		var name := read_model.get_known_display_name(nid, str(npc.get("name", "?")))
		var npc_loc := LocationServiceScript.get_npc_location(read_model, npc)
		if LocationServiceScript.is_same_place(here, npc_loc) or present_set.has(nid):
			_append_unique(out, "与%s搭话" % name)
		else:
			if remote_added >= MAX_REMOTE_NPC_SUGGESTIONS:
				continue
			var place := _short_place_label(read_model, npc_loc)
			if place.is_empty():
				continue
			_append_unique(out, "去%s找%s" % [place, name])
			remote_added += 1
		if out.size() >= MAX_SUGGESTIONS:
			return


static func _append_region_suggestions(read_model: GameReadModel, out: PackedStringArray) -> void:
	var current := str(read_model.mainrole.get("current_region_id", "")).strip_edges()
	for region in read_model.get_unlocked_regions():
		var rid := str(region.get("id", "")).strip_edges()
		if rid.is_empty() or rid == current:
			continue
		var rname := str(region.get("name", rid)).strip_edges()
		_append_unique(out, "前往%s" % rname)
		if out.size() >= MAX_SUGGESTIONS:
			return


static func _append_skill_suggestions(read_model: GameReadModel, out: PackedStringArray) -> void:
	var catalog := SkillCatalog.new()
	catalog.bind_skills(read_model.get_skills_catalog())
	var known := read_model.get_known_protagonist_profile()
	var skill_ids: Variant = known.get("skills", [])
	if not skill_ids is Array:
		return
	for sid in skill_ids:
		var id_str := str(sid).strip_edges()
		if id_str.is_empty():
			continue
		var row := catalog.resolve(id_str)
		var sname := str(row.get("name", "")).strip_edges()
		if sname.is_empty():
			continue
		_append_unique(out, "尝试使用「%s」" % sname)
		if out.size() >= MAX_SUGGESTIONS:
			return


static func _append_fallback_suggestions(out: PackedStringArray) -> void:
	const FALLBACK: PackedStringArray = [
		"观察周围环境",
		"整理装备与随身物品",
	]
	for text in FALLBACK:
		_append_unique(out, text)


static func _append_unique(out: PackedStringArray, text: String) -> void:
	var norm := _normalize_label(text)
	if norm.is_empty():
		return
	for existing in out:
		if existing == norm:
			return
	out.append(norm)


static func _trim_unique(items: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for text in items:
		_append_unique(out, text)
		if out.size() >= MAX_SUGGESTIONS:
			break
	return out


static func _short_place_label(read_model: GameReadModel, loc: Dictionary) -> String:
	var key_node_id := str(loc.get("key_node_id", "")).strip_edges()
	if not key_node_id.is_empty():
		var node := LocationServiceScript.get_key_node(read_model, key_node_id)
		var nname := str(node.get("name", "")).strip_edges()
		if not nname.is_empty():
			return nname
	return LocationServiceScript.format_location_path(read_model, loc)


static func _normalize_label(text: String) -> String:
	var s := text.strip_edges()
	if s.length() > MAX_LABEL_LEN:
		s = s.substr(0, MAX_LABEL_LEN)
	return s


static func _sanitize_suggestion(text: String, read_model: GameReadModel) -> String:
	var s := _normalize_label(text)
	if s.is_empty():
		return ""
	if s.begins_with("观察"):
		var target := s.substr(2).strip_edges()
		var display := _resolve_observe_target(target, read_model)
		if display.is_empty():
			return ""
		return "观察%s" % display
	if _contains_internal_token(s):
		return ""
	return s


static func _resolve_observe_target(target: String, read_model: GameReadModel) -> String:
	return SceneTargetResolverScript.resolve_display_name(target, read_model)


static func _resolve_npc_display_name(needle: String, read_model: GameReadModel) -> String:
	var token := needle.strip_edges()
	if token.is_empty():
		return ""
	if not read_model.get_npc(token).is_empty():
		return _npc_display_name(read_model, token)
	var npcs: Variant = read_model.npc_db.get("npcs", {})
	if npcs is Dictionary:
		for npc_id in npcs:
			var nid := str(npc_id).strip_edges()
			if nid.is_empty():
				continue
			if nid == token or nid.to_lower() == token.to_lower():
				return _npc_display_name(read_model, nid)
			if token.begins_with(nid) or nid.begins_with(token):
				var name := _npc_display_name(read_model, nid)
				if not name.is_empty():
					return name
	return ""


static func _npc_display_name(read_model: GameReadModel, npc_id: String) -> String:
	var known := read_model.get_known_display_name(npc_id, "")
	if not known.is_empty() and known != "未知" and known != "?":
		return known
	var truth := str(read_model.get_npc(npc_id).get("name", "")).strip_edges()
	if truth.is_empty() or _contains_internal_token(truth):
		return ""
	return truth


static func _contains_internal_token(text: String) -> bool:
	var s := text.strip_edges()
	if s.is_empty():
		return false
	if s.begins_with("npc_") or s.find("npc_") >= 0:
		return true
	if s.begins_with("region_") or s.begins_with("node_") or s.begins_with("item_"):
		return true
	if s.find("_") >= 0 and _is_mostly_ascii_identifier(s):
		return true
	if s.length() >= 12 and _is_mostly_ascii_identifier(s):
		return true
	return false


static func _is_mostly_ascii_identifier(s: String) -> bool:
	var ascii_count := 0
	for i in s.length():
		var code := s.unicode_at(i)
		if code == 0x5F or (code >= 0x30 and code <= 0x39) or (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A):
			ascii_count += 1
	return ascii_count >= s.length()
