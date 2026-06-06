class_name NarrativeEntityGuard
extends RefCounted

const DynamicAddTriggerParser = preload("res://src/ai_skills/dynamic_add_trigger_parser.gd")

const PLACE_KEYWORDS: PackedStringArray = [
	"小区", "大厦", "广场", "公寓", "楼栋", "单元", "胡同", "里弄", "村", "镇", "街", "路",
]

const NPC_SCHEMAS: PackedStringArray = ["runtime_npc"]
const PLACE_SCHEMAS: PackedStringArray = ["runtime_key_node", "runtime_region"]


## 检测叙事正文是否引入未登记实体却未打 DYN_ADD 标记。
static func check_orphan_entities(story_text: String, read_model: GameReadModel) -> PackedStringArray:
	var warnings: PackedStringArray = []
	var text := story_text.strip_edges()
	if text.is_empty():
		return warnings

	var requests: Array = DynamicAddTriggerParser.find_all(text)
	var known_npc_names := _collect_npc_names(read_model)
	var known_place_names := _collect_place_names(read_model)

	for name in extract_npc_names(text):
		if name in known_npc_names:
			continue
		if _entity_has_schema_marker(requests, NPC_SCHEMAS, name):
			continue
		warnings.append("叙事出现未登记角色「%s」，须同轮 [[DYN_ADD:NPC|…]]" % name)

	for hint in _extract_place_hints(text):
		if _place_known(hint, known_place_names):
			continue
		if _entity_has_schema_marker(requests, PLACE_SCHEMAS, hint):
			continue
		warnings.append(
			"叙事出现未登记地点「%s」，须同轮 [[DYN_ADD:子地点|…]] 或 [[DYN_ADD:区域|…]]" % hint
		)

	return warnings


static func _entity_has_schema_marker(markers: Array, schema_ids: PackedStringArray, hint: String) -> bool:
	var needle := hint.strip_edges()
	if needle.is_empty():
		return false
	for req in markers:
		var sid := str(req.schema_id).strip_edges()
		if sid not in schema_ids:
			continue
		var ctx := str(req.source_context).strip_edges()
		if ctx.is_empty():
			continue
		if needle in ctx or ctx in needle:
			return true
	return false


static func _collect_npc_names(read_model: GameReadModel) -> Dictionary:
	var out: Dictionary = {}
	var protagonist := str(read_model.mainrole.get("name", "")).strip_edges()
	if not protagonist.is_empty():
		out[protagonist] = true
	var npcs: Variant = read_model.npc_db.get("npcs", {})
	if npcs is Dictionary:
		for npc_id in npcs:
			var npc: Dictionary = npcs[npc_id]
			var nname := str(npc.get("name", "")).strip_edges()
			if not nname.is_empty():
				out[nname] = true
	return out


static func _collect_place_names(read_model: GameReadModel) -> Dictionary:
	var out: Dictionary = {}
	for region in read_model.get_regions():
		if not region is Dictionary:
			continue
		var rname := str(region.get("name", "")).strip_edges()
		if not rname.is_empty():
			out[rname] = true
	for node in read_model.get_key_nodes():
		if not node is Dictionary:
			continue
		var nname := str(node.get("name", "")).strip_edges()
		if not nname.is_empty():
			out[nname] = true
	return out


static func extract_npc_names(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for name in _extract_dialogue_speaker_names(text):
		_append_unique_name(out, name)
	var patterns: PackedStringArray = [
		"「([\\u4e00-\\u9fff]{2,6})[，,]",
		"(?:名叫|名为|叫作|叫)([\\u4e00-\\u9fff]{2,6})",
		"([\\u4e00-\\u9fff]{2,4})[，,][^「」]{0,12}(?:岁|馆长|先生|女士|同志)",
	]
	for pat in patterns:
		var re := RegEx.new()
		if re.compile(pat) != OK:
			continue
		for m in re.search_all(text):
			_append_unique_name(out, str(m.get_string(1)).strip_edges())
	_extract_in_scene_npc_names(text, out)
	return out


static func _extract_in_scene_npc_names(text: String, out: PackedStringArray) -> void:
	var patterns: PackedStringArray = [
		"([\\u4e00-\\u9fff]{2,4})[，,].{0,24}(?:说|问|道|喊|笑|颤|叹|开|抬|转|看|握|点|愣|抖)",
		"(?:见到|遇见|面对|望着|盯着|拜访|探访)([\\u4e00-\\u9fff]{2,4})",
	]
	for pat in patterns:
		var re := RegEx.new()
		if re.compile(pat) != OK:
			continue
		for m in re.search_all(text):
			_append_unique_name(out, str(m.get_string(1)).strip_edges())


static func _append_unique_name(out: PackedStringArray, name: String) -> void:
	var n := name.strip_edges()
	if n.length() < 2 or n in out:
		return
	if n in ["他", "她", "他们", "众人", "对方", "某人"]:
		return
	out.append(n)


static func _extract_dialogue_speaker_names(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var re := RegEx.new()
	if re.compile("([\\u4e00-\\u9fff]{2,6})[：:]") != OK:
		return out
	for m in re.search_all(text):
		var name := str(m.get_string(1)).strip_edges()
		if name.is_empty() or name in out:
			continue
		if name in ["他", "她", "他们", "众人", "对方", "某人"]:
			continue
		out.append(name)
	return out


static func _extract_place_hints(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for kw in PLACE_KEYWORDS:
		var idx := text.find(kw)
		while idx >= 0:
			var start := maxi(0, idx - 8)
			var end := mini(text.length(), idx + kw.length() + 6)
			var snippet := text.substr(start, end - start).strip_edges()
			if snippet.length() >= 3 and snippet not in out:
				out.append(snippet)
			idx = text.find(kw, idx + 1)
	return out


static func _place_known(hint: String, known_place_names: Dictionary) -> bool:
	for known in known_place_names:
		if hint.find(known) >= 0 or known.find(hint) >= 0:
			return true
	return false
