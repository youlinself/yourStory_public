class_name MapStructureRepair
extends RefCounted

## 修正 map_db 中误挂父区的 key_node（如康宁子地点挂在老城区下）。


static func guess_parent_region_id_for_place(place_ctx: String, read_model: GameReadModel) -> String:
	var best_id := ""
	var best_score := 0
	for region in read_model.get_regions():
		if not region is Dictionary:
			continue
		var rid := str(region.get("id", "")).strip_edges()
		var rname := str(region.get("name", "")).strip_edges()
		if rid.is_empty():
			continue
		var score := 0
		if not rname.is_empty() and rname in place_ctx:
			score += rname.length()
		if place_ctx.find("康宁") >= 0 and rname.find("康宁") >= 0:
			score += 10
		if place_ctx.find("南郊") >= 0 and rname.find("南郊") >= 0:
			score += 8
		if place_ctx.find("南") >= 0 and rname.find("南") >= 0:
			score += 4
		if place_ctx.find("北") >= 0 and rname.find("北") >= 0:
			score += 4
		if place_ctx.find("东") >= 0 and rname.find("东") >= 0:
			score += 4
		if place_ctx.find("西") >= 0 and rname.find("西") >= 0:
			score += 4
		if place_ctx.find("老") >= 0 and rname.find("老") >= 0:
			score += 3
		if score > best_score:
			best_score = score
			best_id = rid
	return best_id


static func repair_misassigned_key_nodes(map_db: Dictionary) -> bool:
	if map_db.is_empty():
		return false
	var ms: Variant = map_db.get("map_structure", {})
	if not ms is Dictionary:
		return false
	var map_structure: Dictionary = ms
	var regions: Variant = map_structure.get("regions", [])
	var key_nodes: Variant = map_structure.get("key_nodes", [])
	if not regions is Array or not key_nodes is Array:
		return false

	var target_region_id := _find_kangning_parent_region_id(regions as Array)
	if target_region_id.is_empty():
		return false

	var changed := false
	var out_nodes: Array = []
	for node in key_nodes:
		if not node is Dictionary:
			out_nodes.append(node)
			continue
		var row: Dictionary = (node as Dictionary).duplicate(true)
		if _should_rebind_kangning_node(row, regions as Array, target_region_id):
			row["region_id"] = target_region_id
			changed = true
		out_nodes.append(row)

	if changed:
		map_structure["key_nodes"] = out_nodes
		map_db["map_structure"] = map_structure
	return changed


static func _find_kangning_parent_region_id(regions: Array) -> String:
	var best_id := ""
	var best_score := 0
	for region in regions:
		if not region is Dictionary:
			continue
		var rid := str(region.get("id", "")).strip_edges()
		var rname := str(region.get("name", "")).strip_edges()
		if rid.is_empty() or rname.is_empty():
			continue
		var score := 0
		if "康宁" in rname:
			score += 8
		if "南郊" in rname:
			score += 6
		if score > best_score:
			best_score = score
			best_id = rid
	return best_id


static func _should_rebind_kangning_node(
	node: Dictionary,
	regions: Array,
	target_region_id: String,
) -> bool:
	var nname := str(node.get("name", "")).strip_edges()
	if nname.is_empty() or "康宁" not in nname:
		return false
	var current_rid := str(node.get("region_id", "")).strip_edges()
	if current_rid == target_region_id:
		return false
	var current_name := _region_name_by_id(current_rid, regions)
	if current_name.is_empty():
		return true
	if "康宁" in current_name or "南郊" in current_name:
		return false
	return "老城" in current_name or current_rid != target_region_id


static func _region_name_by_id(region_id: String, regions: Array) -> String:
	for region in regions:
		if region is Dictionary and str(region.get("id", "")).strip_edges() == region_id:
			return str(region.get("name", "")).strip_edges()
	return ""
