class_name NarrativeEntityRepair
extends RefCounted

const DynamicAddTriggerParser = preload("res://src/ai_skills/dynamic_add_trigger_parser.gd")
const DynamicAddRegistry = preload("res://src/ai_skills/dynamic_add_registry.gd")
const MapStructureRepairScript = preload("res://src/game/logic/world/map_structure_repair.gd")

const PLACE_KEYWORDS: PackedStringArray = [
	"小区", "大厦", "广场", "公寓", "楼栋", "单元", "胡同", "里弄", "村", "镇", "街", "路",
]

const SKIP_NPC_NAMES: PackedStringArray = [
	"他", "她", "他们", "众人", "对方", "某人", "主角", "警官", "警察",
]

const SCHEMA_PRIORITY: Dictionary = {
	"runtime_npc": 0,
	"runtime_key_node": 1,
	"runtime_region": 2,
}


## AI 未输出 DYN_ADD 时，根据正文启发式构造补全请求（程序自动入库）。
static func build_synthetic_requests(story_text: String, read_model: GameReadModel) -> Array:
	var text := story_text.strip_edges()
	if text.is_empty():
		return []

	var existing_markers: Array = DynamicAddTriggerParser.find_all(text)
	var known_npcs := NarrativeEntityGuard._collect_npc_names(read_model)
	var known_places := NarrativeEntityGuard._collect_place_names(read_model)
	var requests: Array = []
	var used_npc: Dictionary = {}
	var used_place: Dictionary = {}

	for npc_name in NarrativeEntityGuard.extract_npc_names(text):
		if npc_name in known_npcs or npc_name in used_npc:
			continue
		if npc_name in SKIP_NPC_NAMES:
			continue
		if _entity_has_marker(existing_markers, "runtime_npc", npc_name):
			continue
		used_npc[npc_name] = true
		var ctx := "%s，剧情新登场人物，" % npc_name
		var place_hint := _first_place_context(text)
		if not place_hint.is_empty():
			ctx += "相关地点：%s，" % place_hint
		ctx += "请根据正文补全身份与外貌"
		requests.append(_make_request("runtime_npc", "NPC", ctx))

	for place_ctx in _extract_place_contexts(text):
		if NarrativeEntityGuard._place_known(place_ctx, known_places):
			continue
		if place_ctx in used_place:
			continue
		if _entity_has_marker(existing_markers, "runtime_key_node", place_ctx):
			continue
		if _entity_has_marker(existing_markers, "runtime_region", place_ctx):
			continue
		used_place[place_ctx] = true
		var parent_region := _guess_parent_region_id(place_ctx, read_model)
		var ctx := place_ctx
		if not parent_region.is_empty():
			ctx += "，所属区域 id=%s" % parent_region
		requests.append(_make_request("runtime_key_node", "子地点", ctx))

	for region_name in _infer_new_region_names(text, read_model, known_places):
		if region_name in used_place:
			continue
		if _entity_has_marker(existing_markers, "runtime_region", region_name):
			continue
		used_place[region_name] = true
		requests.append(_make_request(
			"runtime_region",
			"区域",
			"%s，剧情新出现的城区/片区，须与现有地图邻接" % region_name,
		))

	return _sort_and_trim(requests)


static func _entity_has_marker(markers: Array, schema_id: String, entity_hint: String) -> bool:
	var hint := entity_hint.strip_edges()
	if hint.is_empty():
		return false
	for req in markers:
		if str(req.schema_id).strip_edges() != schema_id:
			continue
		var ctx := str(req.source_context).strip_edges()
		if ctx.is_empty():
			continue
		if hint in ctx or ctx in hint:
			return true
	return false


static func _make_request(schema_id: String, category: String, source_context: String) -> DynamicAddTriggerParser.TriggerRequest:
	var req := DynamicAddTriggerParser.TriggerRequest.new()
	req.schema_id = schema_id
	req.category_raw = category
	req.source_context = source_context.strip_edges()
	req.raw_token = ""
	return req


static func _sort_and_trim(requests: Array) -> Array:
	requests.sort_custom(_compare_request_priority)
	var max_count := DynamicAddRegistry.get_max_per_response()
	if requests.size() <= max_count:
		for i in range(requests.size()):
			requests[i].request_index = i
		return requests
	var out: Array = []
	for i in range(max_count):
		var req: DynamicAddTriggerParser.TriggerRequest = requests[i]
		req.request_index = i
		out.append(req)
	return out


static func _compare_request_priority(a: Variant, b: Variant) -> bool:
	var pa: int = int(SCHEMA_PRIORITY.get(str(a.schema_id), 99))
	var pb: int = int(SCHEMA_PRIORITY.get(str(b.schema_id), 99))
	return pa < pb


static func _extract_place_contexts(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var live_re := RegEx.new()
	if live_re.compile("住在([^。；\\n]{4,40})") == OK:
		for m in live_re.search_all(text):
			var chunk := str(m.get_string(1)).strip_edges()
			if chunk.length() >= 4:
				_append_place(out, chunk)
	for hint in NarrativeEntityGuard._extract_place_hints(text):
		_append_place(out, hint)
	return out


static func _infer_new_region_names(
	text: String,
	read_model: GameReadModel,
	_known_places: Dictionary,
) -> PackedStringArray:
	var out: PackedStringArray = []
	var region_labels: PackedStringArray = ["东郊", "西郊", "南郊", "北郊", "城郊", "开发区", "新城"]
	for label in region_labels:
		if text.find(label) < 0:
			continue
		var known := false
		for region in read_model.get_regions():
			var rname := str(region.get("name", "")).strip_edges()
			if label in rname or rname.find(label) >= 0:
				known = true
				break
		if known:
			continue
		if label not in out:
			out.append(label)
	return out


static func guess_parent_region_id_for_place(place_ctx: String, read_model: GameReadModel) -> String:
	return MapStructureRepairScript.guess_parent_region_id_for_place(place_ctx, read_model)


static func _guess_parent_region_id(place_ctx: String, read_model: GameReadModel) -> String:
	return guess_parent_region_id_for_place(place_ctx, read_model)


static func _first_place_context(text: String) -> String:
	var places := _extract_place_contexts(text)
	return places[0] if not places.is_empty() else ""


static func _append_place(out: PackedStringArray, place: String) -> void:
	var p := place.strip_edges()
	if p.length() < 3 or p in out:
		return
	out.append(p)
