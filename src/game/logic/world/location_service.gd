class_name LocationService
extends RefCounted

const LocalGridBuilderScript := preload("res://src/novel_config/local_grid_builder.gd")

## 区域 / 关键节点（酒馆、据点等）位置解析与路径展示。


static func get_protagonist_location(read_model: GameReadModel) -> Dictionary:
	return {
		"region_id": str(read_model.mainrole.get("current_region_id", "")).strip_edges(),
		"key_node_id": str(read_model.mainrole.get("current_key_node_id", "")).strip_edges(),
	}


static func get_npc_location(read_model: GameReadModel, npc: Dictionary) -> Dictionary:
	var region_id := str(npc.get("current_region_id", "")).strip_edges()
	var key_node_id := str(npc.get("current_key_node_id", "")).strip_edges()
	if region_id.is_empty():
		region_id = str(read_model.mainrole.get("current_region_id", "")).strip_edges()
	return {"region_id": region_id, "key_node_id": key_node_id}


static func get_npc_location_by_id(read_model: GameReadModel, npc_id: String) -> Dictionary:
	return get_npc_location(read_model, read_model.get_npc(npc_id))


static func is_same_place(a: Dictionary, b: Dictionary) -> bool:
	return (
		str(a.get("region_id", "")).strip_edges()
		== str(b.get("region_id", "")).strip_edges()
		and str(a.get("key_node_id", "")).strip_edges()
		== str(b.get("key_node_id", "")).strip_edges()
	)


static func is_same_place_from_role(role: Dictionary, to_loc: Dictionary) -> bool:
	return is_same_place(
		{
			"region_id": str(role.get("current_region_id", "")).strip_edges(),
			"key_node_id": str(role.get("current_key_node_id", "")).strip_edges(),
		},
		to_loc,
	)


static func get_protagonist_map_cell(read_model: GameReadModel, page_id: String) -> Vector2i:
	var pid := page_id.strip_edges()
	if pid.is_empty():
		return Vector2i(-1, -1)
	var stored: Variant = read_model.mainrole.get("current_map_cell", null)
	if stored is Dictionary:
		var cell: Dictionary = stored
		if str(cell.get("page_id", "")).strip_edges() == pid:
			return Vector2i(int(cell.get("x", -1)), int(cell.get("y", -1)))
	var kn_id := str(read_model.mainrole.get("current_key_node_id", "")).strip_edges()
	if kn_id.is_empty():
		return Vector2i(-1, -1)
	var map_page := read_model.get_map_page(pid)
	if map_page.is_empty():
		return Vector2i(-1, -1)
	var cells_val: Variant = map_page.get("cells", [])
	var cells: Array = cells_val if cells_val is Array else []
	var width := int(map_page.get("width", 0))
	for raw in cells:
		if not raw is Dictionary:
			continue
		var c: Dictionary = raw
		if str(c.get("key_node_id", "")).strip_edges() == kn_id:
			return Vector2i(int(c.get("x", -1)), int(c.get("y", -1)))
	return Vector2i(-1, -1)


static func is_same_map_cell(read_model: GameReadModel, page_id: String, x: int, y: int) -> bool:
	if x < 0 or y < 0:
		return false
	var current := get_protagonist_map_cell(read_model, page_id)
	return current.x == x and current.y == y


static func needs_map_cell_travel(
	read_model: GameReadModel,
	map_page: Dictionary,
	cell_data: Dictionary,
	to_loc: Dictionary,
) -> bool:
	if not is_same_place(get_protagonist_location(read_model), to_loc):
		return true
	var page_id := str(map_page.get("id", "")).strip_edges()
	var x := int(cell_data.get("x", -1))
	var y := int(cell_data.get("y", -1))
	if page_id.is_empty() or x < 0 or y < 0:
		return false
	return not is_same_map_cell(read_model, page_id, x, y)


static func find_cell_at_display_coord(
	map_page: Dictionary,
	display_x: int,
	display_y: int,
) -> Dictionary:
	if display_x <= 0 or display_y <= 0:
		return {}
	var x := display_x - 1
	var y := display_y - 1
	var width := int(map_page.get("width", 0))
	var cells_val: Variant = map_page.get("cells", [])
	var cells: Array = cells_val if cells_val is Array else []
	if width <= 0 or cells.is_empty():
		return {}
	return LocalGridBuilderScript.cell_at_index(cells, x, y, width)


static func resolve_map_cell_travel_target_from_page(
	read_model: GameReadModel,
	map_page: Dictionary,
	cell_data: Dictionary,
) -> Dictionary:
	var empty := {
		"needs_travel": false,
		"page_id": "",
		"x": -1,
		"y": -1,
		"region_id": "",
		"key_node_id": "",
	}
	if map_page.is_empty() or cell_data.is_empty():
		return empty

	var x := int(cell_data.get("x", -1))
	var y := int(cell_data.get("y", -1))
	if x < 0 or y < 0:
		return empty

	var parent_type := str(map_page.get("parent_type", "")).strip_edges()
	var parent_id := str(map_page.get("parent_id", "")).strip_edges()
	var region_id := ""
	if parent_type == "region":
		region_id = parent_id
	elif parent_type == "key_node":
		var kn := get_key_node(read_model, parent_id)
		region_id = str(kn.get("region_id", "")).strip_edges()
	if region_id.is_empty():
		return empty

	var key_node_id := str(cell_data.get("key_node_id", "")).strip_edges()
	var to_loc := {"region_id": region_id, "key_node_id": key_node_id}
	var page_id := str(map_page.get("id", "")).strip_edges()
	return {
		"needs_travel": needs_map_cell_travel(read_model, map_page, cell_data, to_loc),
		"page_id": page_id,
		"x": x,
		"y": y,
		"region_id": region_id,
		"key_node_id": key_node_id,
	}


enum TravelTier { NONE, SUBPLACE, REGION }


static func travel_tier(from_loc: Dictionary, to_loc: Dictionary) -> TravelTier:
	if is_same_place(from_loc, to_loc):
		return TravelTier.NONE
	if str(from_loc.get("region_id", "")).strip_edges() != str(to_loc.get("region_id", "")).strip_edges():
		return TravelTier.REGION
	return TravelTier.SUBPLACE


static func format_location_path(read_model: GameReadModel, loc: Dictionary) -> String:
	var region_id := str(loc.get("region_id", "")).strip_edges()
	var key_node_id := str(loc.get("key_node_id", "")).strip_edges()
	var regions := read_model.get_regions()

	if region_id.is_empty() and not regions.is_empty():
		region_id = str(regions[0].get("id", "")).strip_edges()

	var region_name := _region_name(region_id, regions)
	var key_node := get_key_node(read_model, key_node_id)
	var node_name := str(key_node.get("name", "")).strip_edges()

	if not node_name.is_empty():
		if region_name.is_empty():
			return node_name
		return "%s -> %s" % [region_name, node_name]

	var cell_name := _protagonist_map_cell_name(read_model, region_id)
	if not cell_name.is_empty():
		if region_name.is_empty():
			return cell_name
		return "%s -> %s" % [region_name, cell_name]

	if region_name.is_empty():
		return "未知地点"

	return region_name


static func _protagonist_map_cell_name(read_model: GameReadModel, region_id: String) -> String:
	var stored: Variant = read_model.mainrole.get("current_map_cell", null)
	if not stored is Dictionary:
		return ""
	var page_id := str((stored as Dictionary).get("page_id", "")).strip_edges()
	var x := int((stored as Dictionary).get("x", -1))
	var y := int((stored as Dictionary).get("y", -1))
	if page_id.is_empty() or x < 0 or y < 0:
		return ""
	var map_page := read_model.get_map_page(page_id)
	if map_page.is_empty():
		return ""
	var page_region := ""
	var parent_type := str(map_page.get("parent_type", "")).strip_edges()
	var parent_id := str(map_page.get("parent_id", "")).strip_edges()
	if parent_type == "region":
		page_region = parent_id
	elif parent_type == "key_node":
		page_region = str(get_key_node(read_model, parent_id).get("region_id", "")).strip_edges()
	if not region_id.is_empty() and not page_region.is_empty() and page_region != region_id:
		return ""
	var width := int(map_page.get("width", 0))
	var cells_val: Variant = map_page.get("cells", [])
	var cells: Array = cells_val if cells_val is Array else []
	if width <= 0 or cells.is_empty():
		return ""
	var cell := LocalGridBuilderScript.cell_at_index(cells, x, y, width)
	return str(cell.get("name", "")).strip_edges()


static func get_key_node(read_model: GameReadModel, key_node_id: String) -> Dictionary:
	var nid := key_node_id.strip_edges()
	if nid.is_empty():
		return {}
	for node in read_model.get_key_nodes():
		if node is Dictionary and str(node.get("id", "")).strip_edges() == nid:
			return node
	return {}


static func get_key_node_ids(read_model: GameReadModel) -> Array[String]:
	var out: Array[String] = []
	for node in read_model.get_key_nodes():
		if node is Dictionary:
			var nid := str(node.get("id", "")).strip_edges()
			if not nid.is_empty():
				out.append(nid)
	return out


static func key_node_belongs_to_region(read_model: GameReadModel, key_node_id: String, region_id: String) -> bool:
	var node := get_key_node(read_model, key_node_id)
	if node.is_empty():
		return false
	var node_region := str(node.get("region_id", "")).strip_edges()
	if node_region.is_empty():
		return true
	return node_region == region_id.strip_edges()


static func resolve_map_cell_travel_target(
	read_model: GameReadModel,
	map_page: Dictionary,
	cell_data: Dictionary,
) -> Dictionary:
	return resolve_map_cell_travel_target_from_page(read_model, map_page, cell_data)


static func npc_location_hint(read_model: GameReadModel, npc: Dictionary) -> String:
	var loc := get_npc_location(read_model, npc)
	return format_location_path(read_model, loc)


static func resolve_talk_target_npc_id(player_text: String, read_model: GameReadModel) -> String:
	var text := player_text.strip_edges()
	if text.is_empty():
		return ""

	var talk_re := RegEx.new()
	talk_re.compile("^我找到.+，开口打招呼")
	if talk_re.search(text) != null:
		return _match_npc_by_display_name(text, read_model)

	var chip_re := RegEx.new()
	chip_re.compile("^与(.+)搭话$")
	var chip_m := chip_re.search(text)
	if chip_m != null:
		var name := chip_m.get_string(1).strip_edges()
		return _npc_id_for_display_name(name, read_model)

	var goto_re := RegEx.new()
	goto_re.compile("^去.+找(.+)$")
	var goto_m := goto_re.search(text)
	if goto_m != null:
		return _npc_id_for_display_name(goto_m.get_string(1).strip_edges(), read_model)

	return ""


static func _match_npc_by_display_name(text: String, read_model: GameReadModel) -> String:
	for npc in read_model.get_nearby_npcs():
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		var name := read_model.get_known_display_name(nid, str(npc.get("name", "")))
		if not name.is_empty() and text.find(name) >= 0:
			return nid
	return ""


static func _npc_id_for_display_name(display_name: String, read_model: GameReadModel) -> String:
	var needle := display_name.strip_edges()
	for npc in read_model.get_nearby_npcs():
		var nid := str(npc.get("id", "")).strip_edges()
		if read_model.get_known_display_name(nid, str(npc.get("name", ""))) == needle:
			return nid
	return ""


static func _region_name(region_id: String, regions: Array) -> String:
	for region in regions:
		if region is Dictionary and str(region.get("id", "")) == region_id:
			return str(region.get("name", region_id))
	return region_id
