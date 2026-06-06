class_name LocationResolver
extends RefCounted

const LocalGridBuilderScript := preload("res://src/novel_config/local_grid_builder.gd")

## 位置解析子步骤：region → key_node → map_cell，初始化与运行时共用。


static func resolve_and_apply(
	role: Dictionary,
	map_structure: Dictionary,
	hints: Dictionary,
	options: Dictionary = {},
) -> Dictionary:
	var warnings: PackedStringArray = []
	var prev_region := str(role.get("current_region_id", "")).strip_edges()
	var prev_key_node := str(role.get("current_key_node_id", "")).strip_edges()

	var region_id := prev_region
	if hints.has("region_hint"):
		region_id = resolve_region(
			str(hints.get("region_hint", "")).strip_edges(),
			str(hints.get("hint_text", "")).strip_edges(),
			map_structure,
			str(options.get("fallback_region_id", "")).strip_edges(),
		)

	var valid_regions: Variant = options.get("valid_region_ids", [])
	if valid_regions is Array and not (valid_regions as Array).is_empty() and not region_id.is_empty():
		if not _region_id_in_list(region_id, valid_regions as Array):
			warnings.append("非法 region: %s" % region_id)
			region_id = prev_region

	var key_node_id := prev_key_node
	if hints.has("key_node_hint"):
		key_node_id = resolve_key_node(
			str(hints.get("key_node_hint", "")).strip_edges(),
			region_id,
			str(hints.get("hint_text", "")).strip_edges(),
			map_structure,
		)
	elif prev_region != region_id and hints.has("region_hint"):
		key_node_id = ""

	var map_cell_hint: Dictionary = {}
	if hints.get("map_cell_hint") is Dictionary:
		map_cell_hint = (hints.get("map_cell_hint") as Dictionary).duplicate(true)

	var assign_allowed := bool(options.get("allow_assign_key_node_cell", false))
	var map_cell := resolve_map_cell(
		region_id,
		key_node_id,
		map_structure,
		map_cell_hint,
		str(hints.get("hint_text", "")).strip_edges(),
		assign_allowed,
	)

	var include_map_cell := bool(options.get("include_map_cell", true))
	apply_to_role(
		role,
		region_id,
		key_node_id,
		map_cell,
		{
			"prev_region_id": prev_region,
			"include_map_cell": include_map_cell,
		},
	)

	return {
		"ok": true,
		"warnings": warnings,
		"location": {
			"region_id": region_id,
			"key_node_id": key_node_id,
			"map_cell": map_cell.duplicate(true) if map_cell is Dictionary else {},
		},
		"map_structure_updated": assign_allowed and not map_cell.is_empty(),
	}


static func resolve_region(
	region_hint: String,
	hint_text: String,
	map_structure: Dictionary,
	fallback_region_id: String = "",
) -> String:
	var token := region_hint.strip_edges()
	if not token.is_empty():
		if _region_exists(token, map_structure):
			return token
		var by_name := _region_id_for_name(token, map_structure)
		if not by_name.is_empty():
			return by_name

	var hay := hint_text.strip_edges()
	if not hay.is_empty():
		for region in _regions(map_structure):
			if not region is Dictionary:
				continue
			var rid := str(region.get("id", "")).strip_edges()
			var rname := str(region.get("name", "")).strip_edges()
			if rid.is_empty():
				continue
			if not rname.is_empty() and hay.find(rname) >= 0:
				return rid

	var fallback := fallback_region_id.strip_edges()
	if not fallback.is_empty() and _region_exists(fallback, map_structure):
		return fallback
	return _first_region_id(map_structure)


static func resolve_key_node(
	key_node_hint: String,
	region_id: String,
	hint_text: String,
	map_structure: Dictionary,
) -> String:
	var token := key_node_hint.strip_edges()
	if token.is_empty():
		return _infer_key_node_from_text(hint_text, map_structure, region_id)

	if _key_node_belongs_to_region(token, region_id, map_structure):
		return token

	for node in _key_nodes(map_structure):
		if not node is Dictionary:
			continue
		var nid := str(node.get("id", "")).strip_edges()
		var nname := str(node.get("name", "")).strip_edges()
		if token == nname or token == nid:
			if _key_node_belongs_to_region(nid, region_id, map_structure):
				return nid
		if not nname.is_empty() and (nname in token or token in nname):
			if _key_node_belongs_to_region(nid, region_id, map_structure):
				return nid

	return ""


static func resolve_map_cell(
	region_id: String,
	key_node_id: String,
	map_structure: Dictionary,
	map_cell_hint: Dictionary,
	hint_text: String,
	allow_assign_key_node_cell: bool = false,
) -> Dictionary:
	var explicit := _normalize_map_cell_hint(map_cell_hint)
	if not explicit.is_empty():
		if _validate_map_cell(explicit, map_structure):
			return explicit
		return {}

	var cell := _find_cell_for_key_node(region_id, key_node_id, map_structure)
	if not cell.is_empty():
		return cell

	if not hint_text.strip_edges().is_empty():
		cell = _find_cell_by_name_in_region(region_id, hint_text, map_structure)
		if not cell.is_empty():
			return cell

	if allow_assign_key_node_cell and not key_node_id.is_empty() and not region_id.is_empty():
		var node := _get_key_node(key_node_id, map_structure)
		if not node.is_empty():
			var updated := LocalGridBuilderScript.assign_key_node_cell(map_structure, node)
			map_structure.clear()
			map_structure.merge(updated, true)
			cell = _find_cell_for_key_node(region_id, key_node_id, map_structure)
			if not cell.is_empty():
				return cell

	return {}


static func apply_to_role(
	role: Dictionary,
	region_id: String,
	key_node_id: String,
	map_cell: Dictionary,
	options: Dictionary = {},
) -> void:
	var prev_region := str(options.get("prev_region_id", role.get("current_region_id", ""))).strip_edges()
	role["current_region_id"] = region_id.strip_edges()
	role["current_key_node_id"] = key_node_id.strip_edges()
	if not bool(options.get("include_map_cell", true)):
		return
	if prev_region != region_id.strip_edges() and map_cell.is_empty():
		role["current_map_cell"] = {}
	elif not map_cell.is_empty():
		role["current_map_cell"] = {
			"page_id": str(map_cell.get("page_id", "")).strip_edges(),
			"x": int(map_cell.get("x", -1)),
			"y": int(map_cell.get("y", -1)),
		}
	elif not key_node_id.strip_edges().is_empty():
		role["current_map_cell"] = {}
	else:
		role["current_map_cell"] = {}


static func sync_map_cell_for_role(role: Dictionary, map_structure: Dictionary) -> Dictionary:
	var region_id := str(role.get("current_region_id", "")).strip_edges()
	var key_node_id := str(role.get("current_key_node_id", "")).strip_edges()
	var map_cell := resolve_map_cell(region_id, key_node_id, map_structure, {}, "", false)
	if not map_cell.is_empty():
		role["current_map_cell"] = {
			"page_id": str(map_cell.get("page_id", "")).strip_edges(),
			"x": int(map_cell.get("x", -1)),
			"y": int(map_cell.get("y", -1)),
		}
	return map_cell


static func map_structure_from_read_model(read_model: GameReadModel) -> Dictionary:
	if read_model == null:
		return {}
	return read_model.get_map_structure()


static func hint_text_from_world_init(world_init: Dictionary, npc: Dictionary) -> String:
	var parts: PackedStringArray = []
	var initial_scene := str(npc.get("initial_scene", "")).strip_edges()
	if not initial_scene.is_empty():
		parts.append(initial_scene)
	var adventure: Variant = world_init.get("adventure_module", {})
	if adventure is Dictionary:
		var hook := str((adventure as Dictionary).get("opening_hook", "")).strip_edges()
		if not hook.is_empty():
			parts.append(hook)
	var name := str(npc.get("name", "")).strip_edges()
	if not name.is_empty():
		parts.append(name)
	return " ".join(parts)


static func _normalize_map_cell_hint(hint: Dictionary) -> Dictionary:
	var page_id := str(hint.get("page_id", "")).strip_edges()
	var x := int(hint.get("x", -1))
	var y := int(hint.get("y", -1))
	if page_id.is_empty() or x < 0 or y < 0:
		return {}
	return {"page_id": page_id, "x": x, "y": y}


static func _validate_map_cell(cell: Dictionary, map_structure: Dictionary) -> bool:
	var page_id := str(cell.get("page_id", "")).strip_edges()
	var x := int(cell.get("x", -1))
	var y := int(cell.get("y", -1))
	if page_id.is_empty() or x < 0 or y < 0:
		return false
	var page := _find_map_page(page_id, map_structure)
	if page.is_empty():
		return false
	var width := int(page.get("width", 0))
	var height := int(page.get("height", 0))
	return x < width and y < height


static func _find_cell_for_key_node(
	region_id: String,
	key_node_id: String,
	map_structure: Dictionary,
) -> Dictionary:
	var kn_id := key_node_id.strip_edges()
	var rid := region_id.strip_edges()
	if kn_id.is_empty() or rid.is_empty():
		return {}
	var page := _find_region_map_page(rid, map_structure)
	if page.is_empty():
		return {}
	var page_id := str(page.get("id", "")).strip_edges()
	var cells_val: Variant = page.get("cells", [])
	if not cells_val is Array:
		return {}
	for raw in cells_val as Array:
		if not raw is Dictionary:
			continue
		var c: Dictionary = raw
		if str(c.get("key_node_id", "")).strip_edges() == kn_id:
			return {
				"page_id": page_id,
				"x": int(c.get("x", -1)),
				"y": int(c.get("y", -1)),
			}
	return {}


static func _find_cell_by_name_in_region(
	region_id: String,
	hint_text: String,
	map_structure: Dictionary,
) -> Dictionary:
	var hay := hint_text.strip_edges()
	if hay.is_empty():
		return {}
	var page := _find_region_map_page(region_id.strip_edges(), map_structure)
	if page.is_empty():
		return {}
	var page_id := str(page.get("id", "")).strip_edges()
	var cells_val: Variant = page.get("cells", [])
	if not cells_val is Array:
		return {}
	for raw in cells_val as Array:
		if not raw is Dictionary:
			continue
		var c: Dictionary = raw
		var name := str(c.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		if hay.find(name) >= 0:
			return {
				"page_id": page_id,
				"x": int(c.get("x", -1)),
				"y": int(c.get("y", -1)),
			}
	return {}


static func _find_region_map_page(region_id: String, map_structure: Dictionary) -> Dictionary:
	var target := region_id.strip_edges()
	if target.is_empty():
		return {}
	for raw in _map_pages(map_structure):
		if not raw is Dictionary:
			continue
		var page: Dictionary = raw
		if (
			str(page.get("parent_type", "")).strip_edges() == "region"
			and str(page.get("parent_id", "")).strip_edges() == target
		):
			return page
	return {}


static func _find_map_page(page_id: String, map_structure: Dictionary) -> Dictionary:
	var target := page_id.strip_edges()
	for raw in _map_pages(map_structure):
		if raw is Dictionary and str(raw.get("id", "")).strip_edges() == target:
			return raw as Dictionary
	return {}


static func _infer_key_node_from_text(
	text: String,
	map_structure: Dictionary,
	region_id: String = "",
) -> String:
	var hay := text.strip_edges()
	if hay.is_empty():
		return ""
	for node in _key_nodes(map_structure):
		if not node is Dictionary:
			continue
		var nid := str(node.get("id", "")).strip_edges()
		if not region_id.is_empty() and not _key_node_belongs_to_region(nid, region_id, map_structure):
			continue
		var name := str(node.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		if hay.find(name) >= 0:
			return nid
	return ""


static func _key_node_belongs_to_region(
	key_node_id: String,
	region_id: String,
	map_structure: Dictionary,
) -> bool:
	var node := _get_key_node(key_node_id, map_structure)
	if node.is_empty():
		return false
	var node_region := str(node.get("region_id", "")).strip_edges()
	if node_region.is_empty():
		return true
	return node_region == region_id.strip_edges()


static func _get_key_node(key_node_id: String, map_structure: Dictionary) -> Dictionary:
	var target := key_node_id.strip_edges()
	if target.is_empty():
		return {}
	for node in _key_nodes(map_structure):
		if node is Dictionary and str(node.get("id", "")).strip_edges() == target:
			return node as Dictionary
	return {}


static func _region_id_for_name(name: String, map_structure: Dictionary) -> String:
	var token := name.strip_edges()
	if token.is_empty():
		return ""
	for region in _regions(map_structure):
		if not region is Dictionary:
			continue
		var rid := str(region.get("id", "")).strip_edges()
		var rname := str(region.get("name", "")).strip_edges()
		if token == rname or token == rid:
			return rid
		if not rname.is_empty() and (rname in token or token in rname):
			return rid
	return ""


static func _region_exists(region_id: String, map_structure: Dictionary) -> bool:
	var target := region_id.strip_edges()
	if target.is_empty():
		return false
	for region in _regions(map_structure):
		if region is Dictionary and str(region.get("id", "")).strip_edges() == target:
			return true
	return false


static func _first_region_id(map_structure: Dictionary) -> String:
	for region in _regions(map_structure):
		if region is Dictionary:
			var rid := str(region.get("id", "")).strip_edges()
			if not rid.is_empty():
				return rid
	return ""


static func _regions(map_structure: Dictionary) -> Array:
	var regions_val: Variant = map_structure.get("regions", [])
	return regions_val if regions_val is Array else []


static func _key_nodes(map_structure: Dictionary) -> Array:
	var nodes_val: Variant = map_structure.get("key_nodes", [])
	return nodes_val if nodes_val is Array else []


static func _map_pages(map_structure: Dictionary) -> Array:
	var pages_val: Variant = map_structure.get("map_pages", [])
	return pages_val if pages_val is Array else []


static func _region_id_in_list(region_id: String, valid_region_ids: Array) -> bool:
	var target := region_id.strip_edges()
	for id_val in valid_region_ids:
		if str(id_val).strip_edges() == target:
			return true
	return false
