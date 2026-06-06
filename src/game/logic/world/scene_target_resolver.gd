extends RefCounted

const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")

const MAX_DISPLAY_LEN := 16
const MAX_TARGETS := 8


## 将 scene_targets 条目（内部 id 或中文名）解析为玩家可见显示名。
static func resolve_display_name(token: String, read_model: GameReadModel) -> String:
	var needle := token.strip_edges()
	if needle.is_empty():
		return ""
	if not _contains_internal_token(needle):
		return _clamp_display(needle)
	var from_key_node := _resolve_key_node_display(needle, read_model)
	if not from_key_node.is_empty():
		return from_key_node
	var from_region := _resolve_region_display(needle, read_model)
	if not from_region.is_empty():
		return from_region
	var from_npc := _resolve_npc_display(needle, read_model)
	if not from_npc.is_empty():
		return from_npc
	if _contains_internal_token(needle):
		return ""
	return _clamp_display(needle)


static func normalize_target_list(raw: Variant, read_model: GameReadModel) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for item in raw:
		var display := resolve_display_name(str(item), read_model)
		if display.is_empty() or display in out:
			continue
		out.append(display)
		if out.size() >= MAX_TARGETS:
			break
	return out


static func _resolve_key_node_display(needle: String, read_model: GameReadModel) -> String:
	if not LocationServiceScript.get_key_node(read_model, needle).is_empty():
		return _clamp_display(str(LocationServiceScript.get_key_node(read_model, needle).get("name", "")))
	for node in read_model.get_key_nodes():
		if not node is Dictionary:
			continue
		var nid := str(node.get("id", "")).strip_edges()
		var nname := str(node.get("name", "")).strip_edges()
		if needle == nid or needle == nname:
			return _clamp_display(nname)
		if not nname.is_empty() and (nname in needle or needle in nname):
			return _clamp_display(nname)
	return ""


static func _resolve_region_display(needle: String, read_model: GameReadModel) -> String:
	if not read_model.get_region(needle).is_empty():
		return _clamp_display(str(read_model.get_region(needle).get("name", "")))
	for region in read_model.get_regions():
		if not region is Dictionary:
			continue
		var rid := str(region.get("id", "")).strip_edges()
		var rname := str(region.get("name", "")).strip_edges()
		if needle == rid or needle == rname:
			return _clamp_display(rname)
		if not rname.is_empty() and (rname in needle or needle in rname):
			return _clamp_display(rname)
	return ""


static func _resolve_npc_display(needle: String, read_model: GameReadModel) -> String:
	if not read_model.get_npc(needle).is_empty():
		var name := read_model.get_known_display_name(needle, "")
		if not name.is_empty() and name != "未知" and name != "?":
			return _clamp_display(name)
	var npcs: Variant = read_model.npc_db.get("npcs", {})
	if npcs is Dictionary:
		for npc_id in npcs:
			var nid := str(npc_id).strip_edges()
			if nid.is_empty():
				continue
			if nid == needle or nid.to_lower() == needle.to_lower():
				var known := read_model.get_known_display_name(nid, "")
				if not known.is_empty() and known != "未知":
					return _clamp_display(known)
	return ""


static func _clamp_display(text: String) -> String:
	var s := text.strip_edges()
	if s.is_empty():
		return ""
	if s.length() > MAX_DISPLAY_LEN:
		s = s.substr(0, MAX_DISPLAY_LEN)
	return s


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
