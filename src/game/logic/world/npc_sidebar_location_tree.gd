extends RefCounted

const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")

const UNKNOWN_SEGMENT := "未知地点"
const PATH_SEP := "/"


static func build(read_model: GameReadModel, npcs: Array) -> Dictionary:
	var root := _empty_node()
	var here := LocationServiceScript.get_protagonist_location(read_model)
	for npc in npcs:
		if not npc is Dictionary:
			continue
		var npc_id := str(npc.get("id", "")).strip_edges()
		if npc_id.is_empty():
			continue
		var loc := LocationServiceScript.get_npc_location(read_model, npc)
		var segments := _path_segments(read_model, loc)
		var group_key := _location_group_key(loc)
		var same_place := LocationServiceScript.is_same_place(here, loc)
		var name := read_model.get_known_display_name(npc_id, "?")
		var node := root
		for segment in segments:
			var children: Dictionary = node["children"]
			if not children.has(segment):
				children[segment] = _empty_node()
			node = children[segment]
		var groups: Dictionary = node["groups"]
		if not groups.has(group_key):
			groups[group_key] = []
		(groups[group_key] as Array).append({
			"id": npc_id,
			"name": name,
			"same_place": same_place,
		})
	_ensure_segments_in_tree(root, _path_segments(read_model, here))
	return root


static func sorted_segment_keys(node: Dictionary) -> Array[String]:
	var children: Variant = node.get("children", {})
	if not children is Dictionary:
		return []
	var keys: Array[String] = []
	for key in (children as Dictionary).keys():
		keys.append(str(key))
	keys.sort()
	return keys


static func path_segments_for_location(read_model: GameReadModel, loc: Dictionary) -> Array[String]:
	return _path_segments(read_model, loc)


static func protagonist_path_segments(read_model: GameReadModel) -> Array[String]:
	return _path_segments(read_model, LocationServiceScript.get_protagonist_location(read_model))


static func collect_prefix_keys_for_segments(root: Dictionary, segments: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	var node: Dictionary = root
	var prefix := ""
	for segment in segments:
		var seg := str(segment).strip_edges()
		if seg.is_empty():
			continue
		var children: Variant = node.get("children", {})
		if not children is Dictionary or not (children as Dictionary).has(seg):
			break
		node = (children as Dictionary)[seg]
		prefix = join_path(prefix, seg)
		out.append(prefix)
	return out


static func collect_ancestor_keys(root: Dictionary, target_npc_id: String) -> PackedStringArray:
	var needle := target_npc_id.strip_edges()
	if needle.is_empty():
		return PackedStringArray()
	var found: PackedStringArray = []
	_walk_ancestors(root, "", needle, found)
	return found


static func header_kind_for_node(node: Dictionary) -> String:
	var flags := _place_flags_in_subtree(node)
	if flags.get("has_near", false) and flags.get("has_far", false):
		return "mixed"
	if flags.get("has_near", false):
		return "success"
	if flags.get("has_far", false):
		return "far"
	return "muted"


static func _place_flags_in_subtree(node: Dictionary) -> Dictionary:
	var has_near := false
	var has_far := false
	var groups: Variant = node.get("groups", {})
	if groups is Dictionary:
		for group in (groups as Dictionary).values():
			if not group is Array:
				continue
			for entry in group:
				if not entry is Dictionary:
					continue
				if bool((entry as Dictionary).get("same_place", false)):
					has_near = true
				else:
					has_far = true
	var children: Variant = node.get("children", {})
	if children is Dictionary:
		for child in (children as Dictionary).values():
			if child is Dictionary:
				var sub := _place_flags_in_subtree(child)
				has_near = has_near or bool(sub.get("has_near", false))
				has_far = has_far or bool(sub.get("has_far", false))
	return {"has_near": has_near, "has_far": has_far}


static func _walk_ancestors(
	node: Dictionary,
	path_prefix: String,
	target_npc_id: String,
	out: PackedStringArray,
) -> bool:
	var children: Variant = node.get("children", {})
	if children is Dictionary:
		for segment in sorted_segment_keys(node):
			var child: Dictionary = (children as Dictionary)[segment]
			var key := join_path(path_prefix, segment)
			if _walk_ancestors(child, key, target_npc_id, out):
				out.insert(0, key)
				return true
	var groups: Variant = node.get("groups", {})
	if groups is Dictionary:
		for group in (groups as Dictionary).values():
			if not group is Array:
				continue
			for entry in group:
				if entry is Dictionary and str(entry.get("id", "")).strip_edges() == target_npc_id:
					return true
	return false


static func _path_segments(read_model: GameReadModel, loc: Dictionary) -> Array[String]:
	var path := LocationServiceScript.format_location_path(read_model, loc).strip_edges()
	var segments: Array[String] = []
	if path.is_empty():
		segments.append(UNKNOWN_SEGMENT)
		return segments
	for part in path.split(" -> ", false):
		var seg := part.strip_edges()
		if not seg.is_empty():
			segments.append(seg)
	if segments.is_empty():
		segments.append(UNKNOWN_SEGMENT)
	return segments


static func _location_group_key(loc: Dictionary) -> String:
	return "%s|%s" % [
		str(loc.get("region_id", "")).strip_edges(),
		str(loc.get("key_node_id", "")).strip_edges(),
	]


static func join_path(prefix: String, segment: String) -> String:
	if prefix.is_empty():
		return segment
	return "%s%s%s" % [prefix, PATH_SEP, segment]


static func _ensure_segments_in_tree(root: Dictionary, segments: Array[String]) -> void:
	var node: Dictionary = root
	for segment in segments:
		var children: Dictionary = node["children"]
		if not children.has(segment):
			children[segment] = _empty_node()
		node = children[segment]


static func _empty_node() -> Dictionary:
	return {"children": {}, "groups": {}}
