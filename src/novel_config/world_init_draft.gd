extends RefCounted

## 阶段 3 微步骤草稿：地图骨架 → 区域地图页(可重复) → 冒险模块 → 势力阴影 → 主角 → 关键NPC(可重复) → 初始物品 → 写入。

const MIN_KEY_NPC_COUNT := 2
const MAX_KEY_NPC_COUNT := 4
const MIN_REGION_COUNT := 1
const MAX_REGION_COUNT := 3

## 子步骤编号（与 detect_next_substep 返回值一致）
const SUB_MAP_SKELETON := 1
const SUB_MAP_PAGE := 2
const SUB_ADVENTURE := 3
const SUB_FACTION_SHADOWS := 4
const SUB_PROTAGONIST := 5
const SUB_KEY_NPC := 6
const SUB_STARTER_ITEMS := 7
const SUB_FINALIZE := 8

const SUBSTEP_COUNT := 8

const KEY_BUILD_SUBSTEP := "build_substep"
const KEY_MAP := "map_structure"
const KEY_ADVENTURE := "adventure_module"
const KEY_FACTION_SHADOWS := "faction_shadows"
const KEY_FACTION_SHADOWS_DONE := "faction_shadows_done"
const KEY_FACTIONS := "factions"
const KEY_NPCS := "npcs"
const KEY_PROTAGONIST_ID := "protagonist_id"
const KEY_STARTER_ITEMS_MATERIALIZED := "starter_items_materialized"

const LocalGridBuilderScript := preload("res://src/novel_config/local_grid_builder.gd")


static func load_or_empty() -> Dictionary:
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.WORLD_INIT_DRAFT)
	if loaded is Dictionary:
		return (loaded as Dictionary).duplicate(true)
	return {}


static func save(draft: Dictionary) -> bool:
	return GameRunningFileManager.save_json_data(GameRunningFileManager.WORLD_INIT_DRAFT, draft)


static func delete_file() -> bool:
	var path := GameRunningFileManager.runtime_file_path(GameRunningFileManager.WORLD_INIT_DRAFT)
	if FileAccess.file_exists(path):
		var err := DirAccess.remove_absolute(path)
		return err == OK
	return true


static func empty_draft() -> Dictionary:
	return {
		KEY_BUILD_SUBSTEP: SUB_MAP_SKELETON,
		KEY_MAP: {},
		KEY_ADVENTURE: {},
		KEY_FACTION_SHADOWS: [],
		KEY_FACTION_SHADOWS_DONE: false,
		KEY_FACTIONS: [],
		KEY_NPCS: [],
		KEY_PROTAGONIST_ID: "",
		KEY_STARTER_ITEMS_MATERIALIZED: false,
	}


static func detect_next_substep(draft: Dictionary) -> int:
	if draft.is_empty():
		return SUB_MAP_SKELETON
	var map_val: Variant = draft.get(KEY_MAP, null)
	if not AiResponseParser.validate_map_skeleton(map_val):
		return SUB_MAP_SKELETON
	if not missing_region_page_ids(draft).is_empty():
		return SUB_MAP_PAGE
	if not AiResponseParser.validate_adventure_module(draft.get(KEY_ADVENTURE, null)):
		return SUB_ADVENTURE
	if not _faction_shadows_step_done(draft):
		return SUB_FACTION_SHADOWS
	if not _has_protagonist_in_draft(draft):
		return SUB_PROTAGONIST
	if count_key_npcs(draft) < MIN_KEY_NPC_COUNT:
		return SUB_KEY_NPC
	if not bool(draft.get(KEY_STARTER_ITEMS_MATERIALIZED, false)):
		return SUB_STARTER_ITEMS
	return SUB_FINALIZE


static func has_meaningful_checkpoint(draft: Dictionary) -> bool:
	return detect_next_substep(draft) > SUB_MAP_SKELETON


static func substep_label(sub: int, draft: Dictionary = {}) -> String:
	match sub:
		SUB_MAP_SKELETON:
			return "地图骨架"
		SUB_MAP_PAGE:
			var missing := missing_region_page_ids(draft)
			if missing.is_empty():
				return "区域地图页"
			return "区域地图页 (%s)" % missing[0]
		SUB_ADVENTURE:
			return "冒险模块"
		SUB_FACTION_SHADOWS:
			return "势力阴影"
		SUB_PROTAGONIST:
			return "主角角色卡"
		SUB_KEY_NPC:
			var have := count_key_npcs(draft)
			return "关键 NPC (%d/%d)" % [have + 1, MIN_KEY_NPC_COUNT]
		SUB_STARTER_ITEMS:
			return "初始物品"
		SUB_FINALIZE:
			return "校验并写入世界"
		_:
			return "未知子步"


## 写入地图骨架（不含 map_pages；由后续子步逐区补齐）。
static func set_map_skeleton(draft: Dictionary, map_structure: Dictionary) -> void:
	var skeleton := map_structure.duplicate(true)
	skeleton.erase("map_pages")
	var normalized := LocalGridBuilderScript.normalize_map_structure(skeleton)
	draft[KEY_MAP] = normalized
	draft[KEY_BUILD_SUBSTEP] = SUB_MAP_PAGE


## 为指定 region 追加一张本地图页。
static func append_region_map_page(draft: Dictionary, map_page: Dictionary) -> void:
	var map_val: Variant = draft.get(KEY_MAP, {})
	if not map_val is Dictionary:
		return
	var map: Dictionary = (map_val as Dictionary).duplicate(true)
	var pages_val: Variant = map.get("map_pages", [])
	var pages: Array = pages_val if pages_val is Array else []
	var parent_id := str(map_page.get("parent_id", "")).strip_edges()
	var filtered: Array = []
	for raw in pages:
		if not raw is Dictionary:
			filtered.append(raw)
			continue
		var page: Dictionary = raw
		var is_same_region := (
			str(page.get("parent_type", "")).strip_edges() == "region"
			and str(page.get("parent_id", "")).strip_edges() == parent_id
		)
		if not is_same_region:
			filtered.append(page)
	filtered.append(map_page.duplicate(true))
	map["map_pages"] = filtered
	draft[KEY_MAP] = LocalGridBuilderScript.normalize_map_structure(map)
	if missing_region_page_ids(draft).is_empty():
		draft[KEY_BUILD_SUBSTEP] = SUB_ADVENTURE
	else:
		draft[KEY_BUILD_SUBSTEP] = SUB_MAP_PAGE


static func set_adventure_module(draft: Dictionary, adventure_module: Dictionary) -> void:
	draft[KEY_ADVENTURE] = adventure_module.duplicate(true)
	draft[KEY_BUILD_SUBSTEP] = SUB_FACTION_SHADOWS


static func set_faction_shadows(draft: Dictionary, faction_shadows: Array) -> void:
	draft[KEY_FACTION_SHADOWS] = faction_shadows.duplicate(true)
	draft[KEY_FACTIONS] = _shadows_to_factions(faction_shadows)
	draft[KEY_FACTION_SHADOWS_DONE] = true
	draft[KEY_BUILD_SUBSTEP] = SUB_PROTAGONIST


## 兼容旧测试：一次性合并地图+冒险+阴影。
static func merge_adventure_step(
	draft: Dictionary,
	map_structure: Dictionary,
	adventure_module: Dictionary,
	faction_shadows: Array = [],
) -> void:
	set_map_skeleton(draft, map_structure)
	var pages_val: Variant = map_structure.get("map_pages", [])
	if pages_val is Array:
		for raw in pages_val:
			if raw is Dictionary:
				append_region_map_page(draft, raw as Dictionary)
	var missing := missing_region_page_ids(draft)
	for rid in missing:
		_ensure_placeholder_page(draft, rid)
	set_adventure_module(draft, adventure_module)
	set_faction_shadows(draft, faction_shadows)


static func set_protagonist(draft: Dictionary, protagonist_id: String, protagonist_npc: Dictionary) -> void:
	draft[KEY_PROTAGONIST_ID] = protagonist_id.strip_edges()
	var npcs: Array = _ensure_npcs_array(draft)
	_remove_npc_id(npcs, protagonist_id)
	npcs.append(protagonist_npc.duplicate(true))
	draft[KEY_NPCS] = npcs
	draft[KEY_BUILD_SUBSTEP] = SUB_KEY_NPC


static func append_npcs(draft: Dictionary, new_npcs: Array) -> void:
	var npcs: Array = _ensure_npcs_array(draft)
	var seen := _npc_id_set(npcs)
	for npc in new_npcs:
		if not npc is Dictionary:
			continue
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty() or seen.has(nid):
			continue
		npcs.append((npc as Dictionary).duplicate(true))
		seen[nid] = true
	draft[KEY_NPCS] = npcs


static func append_single_key_npc(draft: Dictionary, npc: Dictionary) -> void:
	append_npcs(draft, [npc])


## 返回尚缺 region 级 map_page 的 region.id 列表（有序）。
static func missing_region_page_ids(draft: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var map_val: Variant = draft.get(KEY_MAP, null)
	if not map_val is Dictionary:
		return out
	var map: Dictionary = map_val
	var regions_val: Variant = map.get("regions", [])
	if not regions_val is Array:
		return out
	var covered: Dictionary = {}
	var pages_val: Variant = map.get("map_pages", [])
	if pages_val is Array:
		for raw in pages_val:
			if not raw is Dictionary:
				continue
			var page: Dictionary = raw
			if str(page.get("parent_type", "")).strip_edges() == "region":
				var pid := str(page.get("parent_id", "")).strip_edges()
				if not pid.is_empty():
					covered[pid] = true
	for region in regions_val:
		if not region is Dictionary:
			continue
		var rid := str(region.get("id", "")).strip_edges()
		if rid.is_empty() or covered.has(rid):
			continue
		out.append(rid)
	return out


static func next_map_page_region_id(draft: Dictionary) -> String:
	var missing := missing_region_page_ids(draft)
	if missing.is_empty():
		return ""
	return missing[0]


static func region_by_id(draft: Dictionary, region_id: String) -> Dictionary:
	var map_val: Variant = draft.get(KEY_MAP, {})
	if not map_val is Dictionary:
		return {}
	var regions_val: Variant = (map_val as Dictionary).get("regions", [])
	if not regions_val is Array:
		return {}
	var target := region_id.strip_edges()
	for region in regions_val:
		if region is Dictionary and str(region.get("id", "")).strip_edges() == target:
			return (region as Dictionary).duplicate(true)
	return {}


static func key_nodes_for_region(draft: Dictionary, region_id: String) -> Array:
	var out: Array = []
	var map_val: Variant = draft.get(KEY_MAP, {})
	if not map_val is Dictionary:
		return out
	var nodes_val: Variant = (map_val as Dictionary).get("key_nodes", [])
	if not nodes_val is Array:
		return out
	var target := region_id.strip_edges()
	for node in nodes_val:
		if node is Dictionary and str(node.get("region_id", "")).strip_edges() == target:
			out.append(node)
	return out


static func mark_substep_completed(draft: Dictionary, completed_sub: int) -> void:
	draft[KEY_BUILD_SUBSTEP] = mini(completed_sub + 1, SUB_FINALIZE)


static func mark_starter_items_materialized(draft: Dictionary) -> void:
	draft[KEY_STARTER_ITEMS_MATERIALIZED] = true
	draft[KEY_BUILD_SUBSTEP] = SUB_FINALIZE


static func is_starter_items_materialized(draft: Dictionary) -> bool:
	return bool(draft.get(KEY_STARTER_ITEMS_MATERIALIZED, false))


static func to_world_init(draft: Dictionary) -> Dictionary:
	var map_copy: Dictionary = {}
	var map_val: Variant = draft.get(KEY_MAP, {})
	if map_val is Dictionary:
		map_copy = _ensure_region_map_pages(map_val as Dictionary)
	return {
		KEY_MAP: map_copy,
		KEY_ADVENTURE: draft.get(KEY_ADVENTURE, {}),
		KEY_FACTIONS: draft.get(KEY_FACTIONS, []),
		KEY_NPCS: draft.get(KEY_NPCS, []),
		KEY_PROTAGONIST_ID: str(draft.get(KEY_PROTAGONIST_ID, "")).strip_edges(),
	}


static func collect_existing_npc_ids(draft: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for npc in _ensure_npcs_array(draft):
		if npc is Dictionary:
			var nid := str(npc.get("id", "")).strip_edges()
			if not nid.is_empty() and nid not in out:
				out.append(nid)
	return out


static func count_key_npcs(draft: Dictionary) -> int:
	var pid := str(draft.get(KEY_PROTAGONIST_ID, "")).strip_edges()
	var count := 0
	for npc in _ensure_npcs_array(draft):
		if not npc is Dictionary:
			continue
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty() or nid == pid:
			continue
		count += 1
	return count


static func clear_from_substep(draft: Dictionary, from_sub: int) -> void:
	match from_sub:
		SUB_MAP_SKELETON:
			draft.clear()
			draft.merge(empty_draft(), true)
		SUB_MAP_PAGE:
			var map_val: Variant = draft.get(KEY_MAP, {})
			if map_val is Dictionary:
				var map: Dictionary = (map_val as Dictionary).duplicate(true)
				map["map_pages"] = []
				draft[KEY_MAP] = map
			draft[KEY_BUILD_SUBSTEP] = SUB_MAP_PAGE
		SUB_ADVENTURE:
			draft[KEY_ADVENTURE] = {}
			draft[KEY_FACTION_SHADOWS] = []
			draft[KEY_FACTION_SHADOWS_DONE] = false
			draft[KEY_FACTIONS] = []
			draft[KEY_BUILD_SUBSTEP] = SUB_ADVENTURE
		SUB_FACTION_SHADOWS:
			draft[KEY_FACTION_SHADOWS] = []
			draft[KEY_FACTION_SHADOWS_DONE] = false
			draft[KEY_FACTIONS] = []
			draft[KEY_BUILD_SUBSTEP] = SUB_FACTION_SHADOWS
		SUB_PROTAGONIST:
			draft[KEY_NPCS] = []
			draft[KEY_PROTAGONIST_ID] = ""
			draft[KEY_BUILD_SUBSTEP] = SUB_PROTAGONIST
		SUB_KEY_NPC:
			_strip_npcs_except_protagonist(draft)
			draft[KEY_STARTER_ITEMS_MATERIALIZED] = false
			draft[KEY_BUILD_SUBSTEP] = SUB_KEY_NPC
		SUB_STARTER_ITEMS:
			draft[KEY_STARTER_ITEMS_MATERIALIZED] = false
			draft[KEY_BUILD_SUBSTEP] = SUB_STARTER_ITEMS
		SUB_FINALIZE, _:
			pass


static func _faction_shadows_step_done(draft: Dictionary) -> bool:
	return bool(draft.get(KEY_FACTION_SHADOWS_DONE, false))


static func _has_protagonist_in_draft(draft: Dictionary) -> bool:
	var pid := str(draft.get(KEY_PROTAGONIST_ID, "")).strip_edges()
	if pid.is_empty():
		return false
	for npc in _ensure_npcs_array(draft):
		if npc is Dictionary and str(npc.get("id", "")).strip_edges() == pid:
			return true
	return false


static func _ensure_npcs_array(draft: Dictionary) -> Array:
	var npcs_val: Variant = draft.get(KEY_NPCS, [])
	if npcs_val is Array:
		return npcs_val
	return []


static func _npc_id_set(npcs: Array) -> Dictionary:
	var seen: Dictionary = {}
	for npc in npcs:
		if npc is Dictionary:
			var nid := str(npc.get("id", "")).strip_edges()
			if not nid.is_empty():
				seen[nid] = true
	return seen


static func _remove_npc_id(npcs: Array, npc_id: String) -> void:
	var target := npc_id.strip_edges()
	for i in range(npcs.size() - 1, -1, -1):
		var npc: Variant = npcs[i]
		if npc is Dictionary and str(npc.get("id", "")).strip_edges() == target:
			npcs.remove_at(i)


static func _strip_npcs_except_protagonist(draft: Dictionary) -> void:
	var pid := str(draft.get(KEY_PROTAGONIST_ID, "")).strip_edges()
	var kept: Array = []
	for npc in _ensure_npcs_array(draft):
		if npc is Dictionary and str(npc.get("id", "")).strip_edges() == pid:
			kept.append(npc)
	draft[KEY_NPCS] = kept


static func _ensure_placeholder_page(draft: Dictionary, region_id: String) -> void:
	var region := region_by_id(draft, region_id)
	var rname := str(region.get("name", region_id)).strip_edges()
	append_region_map_page(
		draft,
		LocalGridBuilderScript.build_map_page({
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


static func _ensure_region_map_pages(map_structure: Dictionary) -> Dictionary:
	var out := map_structure.duplicate(true)
	var pages_val: Variant = out.get("map_pages", [])
	var pages: Array = pages_val if pages_val is Array else []
	var regions_val: Variant = out.get("regions", [])
	if not regions_val is Array:
		return out
	var covered: Dictionary = {}
	for raw in pages:
		if not raw is Dictionary:
			continue
		var page: Dictionary = raw
		if str(page.get("parent_type", "")).strip_edges() == "region":
			var pid := str(page.get("parent_id", "")).strip_edges()
			if not pid.is_empty():
				covered[pid] = true
	for region in regions_val:
		if not region is Dictionary:
			continue
		var rid := str(region.get("id", "")).strip_edges()
		if rid.is_empty() or covered.has(rid):
			continue
		var rname := str(region.get("name", rid)).strip_edges()
		pages.append(
			LocalGridBuilderScript.build_map_page({
				"id": "map_%s" % rid,
				"name": rname,
				"parent_type": "region",
				"parent_id": rid,
				"width": 25,
				"height": 25,
				"default_terrain": "plain",
				"terrain_types": ["plain"],
				"cell_marks": [],
			}),
		)
	out["map_pages"] = pages
	return LocalGridBuilderScript.normalize_map_structure(out)


static func _shadows_to_factions(shadows: Array) -> Array:
	var out: Array = []
	for item in shadows:
		if not item is Dictionary:
			continue
		var d: Dictionary = item as Dictionary
		var fid := str(d.get("id", "")).strip_edges()
		if fid.is_empty():
			continue
		out.append({
			"id": fid,
			"name": str(d.get("name", "")),
			"type": "shadow",
			"core_region_id": "",
			"population": "",
			"leader_id": "",
			"structure": str(d.get("role", "")),
			"economy": "",
			"culture": "",
			"military": "",
			"relationships": {"allies": [], "enemies": [], "neutral": []},
		})
	return out
