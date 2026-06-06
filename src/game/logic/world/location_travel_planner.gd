class_name LocationTravelPlanner
extends RefCounted

const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")


## 解析跨地点互动计划（不修改玩家输入）。
static func plan_travel(player_text: String, read_model: GameReadModel) -> Dictionary:
	var text := player_text.strip_edges()
	var empty := {
		"needs_travel": false,
		"npc_id": "",
		"from_loc": {},
		"to_loc": {},
		"tier": LocationServiceScript.TravelTier.NONE,
	}
	if text.is_empty():
		return empty

	var npc_id := LocationServiceScript.resolve_talk_target_npc_id(text, read_model)
	if npc_id.is_empty():
		return empty

	var from_loc := LocationServiceScript.get_protagonist_location(read_model)
	var to_loc := LocationServiceScript.get_npc_location_by_id(read_model, npc_id)
	var tier := LocationServiceScript.travel_tier(from_loc, to_loc)
	if tier == LocationServiceScript.TravelTier.NONE:
		return empty

	return {
		"needs_travel": true,
		"npc_id": npc_id,
		"from_loc": from_loc,
		"to_loc": to_loc,
		"tier": tier,
	}


## 解析地图格子点击的旅行计划（由 UI 传入 page_id 与格子坐标）。
static func plan_map_cell_travel(map_travel: Dictionary, read_model: GameReadModel) -> Dictionary:
	var empty := {
		"needs_travel": false,
		"from_loc": {},
		"to_loc": {},
		"page_id": "",
		"x": -1,
		"y": -1,
	}
	if map_travel.is_empty() or not map_travel.get("needs_travel", false):
		return empty

	var region_id := str(map_travel.get("region_id", "")).strip_edges()
	if region_id.is_empty() or read_model.get_region(region_id).is_empty():
		return empty

	var key_node_id := str(map_travel.get("key_node_id", "")).strip_edges()
	if (
		not key_node_id.is_empty()
		and key_node_id not in LocationServiceScript.get_key_node_ids(read_model)
	):
		key_node_id = ""

	var from_loc := LocationServiceScript.get_protagonist_location(read_model)
	var to_loc := {"region_id": region_id, "key_node_id": key_node_id}

	return {
		"needs_travel": true,
		"from_loc": from_loc,
		"to_loc": to_loc,
		"page_id": str(map_travel.get("page_id", "")).strip_edges(),
		"x": int(map_travel.get("x", -1)),
		"y": int(map_travel.get("y", -1)),
	}


## 回合侧解析地图旅行：优先 UI 暂存，其次从玩家文本中的坐标兜底。
static func resolve_map_travel_for_turn(
	map_travel: Dictionary,
	player_text: String,
	read_model: GameReadModel,
) -> Dictionary:
	var plan := plan_map_cell_travel(map_travel, read_model)
	if plan.get("needs_travel", false):
		return plan
	var parsed := parse_map_travel_from_player_text(player_text, read_model)
	if parsed.is_empty():
		return empty_map_cell_plan()
	return plan_map_cell_travel(parsed, read_model)


static func empty_map_cell_plan() -> Dictionary:
	return {
		"needs_travel": false,
		"from_loc": {},
		"to_loc": {},
		"page_id": "",
		"x": -1,
		"y": -1,
	}


static func parse_map_travel_from_player_text(
	player_text: String,
	read_model: GameReadModel,
) -> Dictionary:
	var text := player_text.strip_edges()
	if text.is_empty():
		return {}
	var coord_re := RegEx.new()
	coord_re.compile("（\\s*(\\d+)\\s*,\\s*(\\d+)\\s*）|\\(\\s*(\\d+)\\s*,\\s*(\\d+)\\s*\\)")
	var m := coord_re.search(text)
	if m == null:
		return {}
	var display_x := int(m.get_string(1)) if not m.get_string(1).is_empty() else int(m.get_string(3))
	var display_y := int(m.get_string(2)) if not m.get_string(2).is_empty() else int(m.get_string(4))
	if display_x <= 0 or display_y <= 0:
		return {}

	var region_id := str(read_model.mainrole.get("current_region_id", "")).strip_edges()
	if region_id.is_empty():
		return {}
	var map_page := read_model.get_primary_map_page_for_region(region_id)
	if map_page.is_empty():
		return {}
	var cell_data := LocationServiceScript.find_cell_at_display_coord(map_page, display_x, display_y)
	if cell_data.is_empty():
		cell_data = {
			"x": display_x - 1,
			"y": display_y - 1,
			"name": "",
			"key_node_id": "",
		}
	return LocationServiceScript.resolve_map_cell_travel_target_from_page(
		read_model,
		map_page,
		cell_data,
	)


## 在发起叙事回合前，为跨地点互动注入位置/赶路说明。
static func enrich_player_text(
	player_text: String,
	read_model: GameReadModel,
	map_travel: Dictionary = {},
) -> String:
	var text := player_text.strip_edges()
	if text.is_empty():
		return player_text

	var map_plan := plan_map_cell_travel(map_travel, read_model)
	if map_plan.get("needs_travel", false):
		return _enrich_map_cell_travel(text, map_plan, read_model)

	var plan := plan_travel(text, read_model)
	if not plan.get("needs_travel", false):
		return player_text

	var npc_id: String = plan.get("npc_id", "")
	var from_loc: Dictionary = plan.get("from_loc", {})
	var to_loc: Dictionary = plan.get("to_loc", {})
	var tier: int = int(plan.get("tier", LocationServiceScript.TravelTier.NONE))

	var npc_name := read_model.get_known_display_name(npc_id, "?")
	var from_path := LocationServiceScript.format_location_path(read_model, from_loc)
	var to_path := LocationServiceScript.format_location_path(read_model, to_loc)
	var hook_region := str(to_loc.get("region_id", "")).strip_edges()
	var hook_node := str(to_loc.get("key_node_id", "")).strip_edges()

	var directive := ""
	match tier:
		LocationServiceScript.TravelTier.SUBPLACE:
			directive = (
				"【位置】主角当前在「%s」，将前往「%s」与 %s 会面。"
				+ "请在叙事开头用一两句自然交代离开现处、抵达目标场所；"
				+ "STATE_HOOK 须设 current_region_id=\"%s\"、current_key_node_id=\"%s\"。"
			) % [from_path, to_path, npc_name, hook_region, hook_node]
		LocationServiceScript.TravelTier.REGION:
			directive = (
				"【位置】主角当前在「%s」，需赶往「%s」才能与 %s 对话。"
				+ "请在叙事开头交代离开现处、途中见闻与抵达；"
				+ "STATE_HOOK 须更新 current_region_id=\"%s\"、current_key_node_id=\"%s\"（无子地点则填空字符串）。"
			) % [from_path, to_path, npc_name, hook_region, hook_node]

	if directive.is_empty():
		return player_text
	return "%s\n\n%s" % [text, directive]


static func _enrich_map_cell_travel(text: String, plan: Dictionary, read_model: GameReadModel) -> String:
	var from_loc: Dictionary = plan.get("from_loc", {})
	var to_loc: Dictionary = plan.get("to_loc", {})
	var from_path := LocationServiceScript.format_location_path(read_model, from_loc)
	var to_path := LocationServiceScript.format_location_path(read_model, to_loc)
	var hook_region := str(to_loc.get("region_id", "")).strip_edges()
	var hook_node := str(to_loc.get("key_node_id", "")).strip_edges()
	var x := int(plan.get("x", -1))
	var y := int(plan.get("y", -1))
	var coord_text := ""
	if x >= 0 and y >= 0:
		coord_text = "（%d,%d）" % [x + 1, y + 1]
	var page_id := str(plan.get("page_id", "")).strip_edges()
	var page := read_model.get_map_page(page_id)
	var page_name := str(page.get("name", page_id)).strip_edges()
	var node_hint := ""
	if hook_node.is_empty():
		node_hint = "（无子地点则 current_key_node_id 填空字符串）"
	var directive := (
		"【位置】主角当前在「%s」，将前往地图「%s」格子%s（目标：%s）。"
		+ "请在叙事开头自然交代离开现处、抵达目标；"
		+ "STATE_HOOK 须设 current_region_id=\"%s\"、current_key_node_id=\"%s\"%s。"
	) % [from_path, page_name, coord_text, to_path, hook_region, hook_node, node_hint]
	return "%s\n\n%s" % [text, directive]
