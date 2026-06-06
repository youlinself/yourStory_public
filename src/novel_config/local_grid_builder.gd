extends RefCounted

## 将 AI 输出的紧凑 cell_marks 转为完整 map_page.cells（row-major）。

const MIN_GRID_SIZE := 5
const MAX_GRID_SIZE := 50
const DEFAULT_TERRAIN := "plain"


static func normalize_map_structure(map_structure: Dictionary) -> Dictionary:
	var out := map_structure.duplicate(true)
	var pages_val: Variant = out.get("map_pages", [])
	if not pages_val is Array:
		out["map_pages"] = []
		return out
	var built: Array = []
	for raw in pages_val as Array:
		if not raw is Dictionary:
			continue
		built.append(build_map_page(raw as Dictionary))
	out["map_pages"] = built
	return out


static func build_map_page(page_spec: Dictionary) -> Dictionary:
	var page := page_spec.duplicate(true)
	var width := clampi(int(page.get("width", 0)), MIN_GRID_SIZE, MAX_GRID_SIZE)
	var height := clampi(int(page.get("height", 0)), MIN_GRID_SIZE, MAX_GRID_SIZE)
	page["width"] = width
	page["height"] = height
	var default_terrain := _resolve_default_terrain(page)
	page["default_terrain"] = default_terrain
	var marks_val: Variant = page.get("cell_marks", [])
	var marks: Array = marks_val if marks_val is Array else []
	var existing_cells: Array = []
	var cells_val: Variant = page.get("cells", [])
	if cells_val is Array:
		existing_cells = cells_val
	page["cells"] = build_cells(width, height, default_terrain, marks)
	if not existing_cells.is_empty():
		_apply_cell_overlays(page["cells"], existing_cells, width, height, default_terrain)
	page.erase("cell_marks")
	return page


static func build_cells(width: int, height: int, default_terrain: String, cell_marks: Array) -> Array:
	var cells: Array = []
	for y in height:
		for x in width:
			cells.append({
				"x": x,
				"y": y,
				"type": default_terrain,
				"name": "",
				"key_node_id": "",
				"child_map_id": "",
			})
	var index_by_xy := _index_cells(cells, width)
	for raw_mark in cell_marks:
		var mark := parse_cell_mark(raw_mark)
		if mark.is_empty():
			continue
		var mx := int(mark.get("x", -1))
		var my := int(mark.get("y", -1))
		if mx < 0 or my < 0 or mx >= width or my >= height:
			continue
		var key := "%d,%d" % [mx, my]
		if not index_by_xy.has(key):
			continue
		var idx: int = index_by_xy[key]
		var cell: Dictionary = cells[idx]
		cell["type"] = str(mark.get("type", default_terrain)).strip_edges()
		if mark.has("name"):
			cell["name"] = str(mark.get("name", "")).strip_edges()
		if mark.has("key_node_id"):
			cell["key_node_id"] = str(mark.get("key_node_id", "")).strip_edges()
		if mark.has("child_map_id"):
			cell["child_map_id"] = str(mark.get("child_map_id", "")).strip_edges()
		cells[idx] = cell
	return cells


## 将 key_node 绑定到所属区域主地图页的空格；仅填充无地点与子地图标记的格，不覆盖已有地点。
static func assign_key_node_cell(map_structure: Dictionary, key_node: Dictionary) -> Dictionary:
	var out := map_structure.duplicate(true)
	var region_id := str(key_node.get("region_id", "")).strip_edges()
	var node_id := str(key_node.get("id", "")).strip_edges()
	if region_id.is_empty() or node_id.is_empty():
		return out
	var pages_val: Variant = out.get("map_pages", [])
	var pages: Array = pages_val if pages_val is Array else []
	var page_idx := _find_region_map_page_index(pages, region_id)
	if page_idx < 0:
		var rname := region_id
		for region in out.get("regions", []):
			if region is Dictionary and str(region.get("id", "")).strip_edges() == region_id:
				rname = str(region.get("name", region_id)).strip_edges()
				break
		pages.append(
			build_map_page({
				"id": "map_%s" % region_id,
				"name": rname,
				"parent_type": "region",
				"parent_id": region_id,
				"width": 25,
				"height": 25,
				"default_terrain": "plain",
				"terrain_types": ["plain"],
				"cell_marks": [],
			}),
		)
		page_idx = pages.size() - 1
	var page: Dictionary = build_map_page(pages[page_idx] as Dictionary)
	if _page_has_key_node(page, node_id):
		pages[page_idx] = page
		out["map_pages"] = pages
		return out
	var coord := _pick_empty_cell_near_center(page)
	if coord.x < 0:
		pages[page_idx] = page
		out["map_pages"] = pages
		return out
	var cells: Array = page.get("cells", [])
	_apply_cell_overlays(
		cells,
		[
			{
				"x": coord.x,
				"y": coord.y,
				"type": "gate",
				"name": str(key_node.get("name", "")).strip_edges(),
				"key_node_id": node_id,
			},
		],
		int(page.get("width", 0)),
		int(page.get("height", 0)),
		str(page.get("default_terrain", DEFAULT_TERRAIN)).strip_edges(),
	)
	page["cells"] = cells
	pages[page_idx] = page
	out["map_pages"] = pages
	return out


static func cell_at_index(cells: Array, x: int, y: int, width: int) -> Dictionary:
	var idx := y * width + x
	if idx < 0 or idx >= cells.size():
		return {}
	var cell: Variant = cells[idx]
	return cell as Dictionary if cell is Dictionary else {}


static func parse_cell_mark(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return _normalize_mark_dict(raw as Dictionary)
	if raw is Array:
		return _normalize_mark_array(raw as Array)
	return {}


## 校验地图页结构；无效 cell_mark 跳过（与 build_cells 一致，不因 AI 笔误整页失败）。
static func validate_cell_marks(
	width: int,
	height: int,
	terrain_types: Array,
	cell_marks: Array,
) -> bool:
	if width < MIN_GRID_SIZE or width > MAX_GRID_SIZE:
		return false
	if height < MIN_GRID_SIZE or height > MAX_GRID_SIZE:
		return false
	var allowed := _terrain_set(terrain_types)
	if allowed.is_empty():
		return false
	var seen: Dictionary = {}
	for raw in cell_marks:
		var mark := parse_cell_mark(raw)
		if mark.is_empty():
			continue
		var mx := int(mark.get("x", -1))
		var my := int(mark.get("y", -1))
		if mx < 0 or my < 0 or mx >= width or my >= height:
			continue
		var coord := "%d,%d" % [mx, my]
		if seen.has(coord):
			continue
		var t := str(mark.get("type", "")).strip_edges()
		if t.is_empty() or t not in allowed:
			continue
		seen[coord] = true
	return true


static func validate_map_page_spec(page: Dictionary) -> bool:
	var page_id := str(page.get("id", "")).strip_edges()
	if page_id.is_empty():
		return false
	var parent_type := str(page.get("parent_type", "")).strip_edges()
	if parent_type != "region" and parent_type != "key_node":
		return false
	if str(page.get("parent_id", "")).strip_edges().is_empty():
		return false
	var width := int(page.get("width", 0))
	var height := int(page.get("height", 0))
	var terrain_val: Variant = page.get("terrain_types", [])
	if not terrain_val is Array:
		return false
	var terrain_types: Array = terrain_val
	if terrain_types.is_empty():
		return false
	var default_terrain := str(page.get("default_terrain", "")).strip_edges()
	if default_terrain.is_empty():
		default_terrain = str(terrain_types[0]).strip_edges()
	if default_terrain not in _terrain_set(terrain_types):
		return false
	var marks_val: Variant = page.get("cell_marks", [])
	var marks: Array = marks_val if marks_val is Array else []
	if not validate_cell_marks(width, height, terrain_types, marks):
		return false
	return true


static func _resolve_default_terrain(page: Dictionary) -> String:
	var terrain_val: Variant = page.get("terrain_types", [])
	var terrain_types: Array = terrain_val if terrain_val is Array else []
	var allowed := _terrain_set(terrain_types)
	var default_terrain := str(page.get("default_terrain", "")).strip_edges()
	if default_terrain.is_empty() and not terrain_types.is_empty():
		default_terrain = str(terrain_types[0]).strip_edges()
	if default_terrain in allowed:
		return default_terrain
	if not allowed.is_empty():
		return str(allowed.keys()[0])
	return DEFAULT_TERRAIN


static func _normalize_mark_dict(d: Dictionary) -> Dictionary:
	var x := int(d.get("x", -1))
	var y := int(d.get("y", -1))
	if x < 0 or y < 0:
		return {}
	var out := {"x": x, "y": y, "type": str(d.get("type", "")).strip_edges()}
	if d.has("name"):
		out["name"] = str(d.get("name", "")).strip_edges()
	if d.has("key_node_id"):
		out["key_node_id"] = str(d.get("key_node_id", "")).strip_edges()
	if d.has("child_map_id"):
		out["child_map_id"] = str(d.get("child_map_id", "")).strip_edges()
	return out


static func _normalize_mark_array(arr: Array) -> Dictionary:
	if arr.size() < 3:
		return {}
	var x := int(arr[0])
	var y := int(arr[1])
	var t := str(arr[2]).strip_edges()
	if x < 0 or y < 0 or t.is_empty():
		return {}
	var out := {"x": x, "y": y, "type": t}
	if arr.size() > 3:
		out["name"] = str(arr[3]).strip_edges()
	if arr.size() > 4:
		out["child_map_id"] = str(arr[4]).strip_edges()
	if arr.size() > 5:
		out["key_node_id"] = str(arr[5]).strip_edges()
	return out


static func _apply_cell_overlays(
	cells: Array,
	overlays: Array,
	width: int,
	height: int,
	_default_terrain: String,
) -> void:
	var index_by_xy := _index_cells(cells, width)
	for raw in overlays:
		if not raw is Dictionary:
			continue
		var mark: Dictionary = raw as Dictionary
		var mx := int(mark.get("x", -1))
		var my := int(mark.get("y", -1))
		if mx < 0 or my < 0 or mx >= width or my >= height:
			continue
		var key := "%d,%d" % [mx, my]
		if not index_by_xy.has(key):
			continue
		var idx: int = index_by_xy[key]
		var cell: Dictionary = cells[idx]
		if mark.has("type"):
			var t := str(mark.get("type", "")).strip_edges()
			if not t.is_empty():
				cell["type"] = t
		if mark.has("name"):
			cell["name"] = str(mark.get("name", "")).strip_edges()
		if mark.has("key_node_id"):
			cell["key_node_id"] = str(mark.get("key_node_id", "")).strip_edges()
		if mark.has("child_map_id"):
			cell["child_map_id"] = str(mark.get("child_map_id", "")).strip_edges()
		cells[idx] = cell


static func _find_region_map_page_index(pages: Array, region_id: String) -> int:
	for i in pages.size():
		if not pages[i] is Dictionary:
			continue
		var page: Dictionary = pages[i]
		if (
			str(page.get("parent_type", "")).strip_edges() == "region"
			and str(page.get("parent_id", "")).strip_edges() == region_id
		):
			return i
	return -1


static func _page_has_key_node(page: Dictionary, key_node_id: String) -> bool:
	var cells_val: Variant = page.get("cells", [])
	if not cells_val is Array:
		return false
	for raw in cells_val:
		if raw is Dictionary and str((raw as Dictionary).get("key_node_id", "")).strip_edges() == key_node_id:
			return true
	return false


static func _pick_empty_cell_near_center(page: Dictionary) -> Vector2i:
	var width := int(page.get("width", 0))
	var height := int(page.get("height", 0))
	if width <= 0 or height <= 0:
		return Vector2i(-1, -1)
	var cells: Array = page.get("cells", []) if page.get("cells") is Array else []
	var cx := width / 2
	var cy := height / 2
	var max_radius := maxi(width, height)
	for radius in range(max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var x := cx + dx
				var y := cy + dy
				if x < 0 or y < 0 or x >= width or y >= height:
					continue
				var cell := cell_at_index(cells, x, y, width)
				if cell.is_empty():
					continue
				if not str(cell.get("key_node_id", "")).strip_edges().is_empty():
					continue
				if not str(cell.get("child_map_id", "")).strip_edges().is_empty():
					continue
				return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _index_cells(cells: Array, width: int) -> Dictionary:
	var out: Dictionary = {}
	for i in cells.size():
		var cell: Variant = cells[i]
		if not cell is Dictionary:
			continue
		var c: Dictionary = cell
		var x := int(c.get("x", i % width))
		var y := int(c.get("y", i / width))
		out["%d,%d" % [x, y]] = i
	return out


static func _terrain_set(terrain_types: Array) -> Dictionary:
	var out: Dictionary = {}
	for t in terrain_types:
		var key := str(t).strip_edges()
		if not key.is_empty():
			out[key] = true
	return out
