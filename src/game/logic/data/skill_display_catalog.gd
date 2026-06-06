class_name SkillDisplayCatalog
extends RefCounted

var _skills: Dictionary = {}


func load_from_runtime() -> void:
	var db: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.SKILLS_DB)
	var normalized := RuntimeDbSchemas.normalize_skills_db(db)
	_skills = normalized.get("skills", {}) if normalized is Dictionary else {}


func bind_skills(skills: Dictionary) -> void:
	_skills = skills


func resolve(skill_id: String) -> Dictionary:
	var id := skill_id.strip_edges()
	if id.is_empty():
		return {"id": "", "name": "未知", "desc": ""}
	if _skills.has(id) and _skills[id] is Dictionary:
		var row: Dictionary = _skills[id]
		var name := str(row.get("name", "")).strip_edges()
		var desc := str(row.get("desc", "")).strip_edges()
		return {
			"id": id,
			"name": name if not name.is_empty() else humanize_skill_id(id),
			"desc": desc,
		}
	return {"id": id, "name": humanize_skill_id(id), "desc": ""}


static func humanize_skill_id(skill_id: String) -> String:
	var s := skill_id.strip_edges()
	if s.is_empty():
		return "未知"
	# 常见英文 id → 中文兜底（技能库无 name 时）
	const FALLBACK: Dictionary = {
		"info_brokering": "情报交易",
		"credit_fabrication": "信用伪造",
		"social_engineering": "社交工程",
		"neural_synchronization": "神经同步",
		"gray_market_dealing": "灰市交易",
	}
	if FALLBACK.has(s):
		return str(FALLBACK[s])
	return s.replace("_", " ")


static func format_player_visible(value: Variant) -> String:
	if value == null:
		return "未知"
	if value is String:
		var text: String = (value as String).strip_edges()
		if text.is_empty() or text == "—" or text == "-":
			return "未知"
		return text
	if value is int:
		if value <= 0:
			return "未知"
		return str(value)
	if value is float:
		if value <= 0.0:
			return "未知"
		var f: float = value
		if f == floorf(f):
			return str(int(f))
		return str(f)
	var fallback := str(value).strip_edges()
	if fallback.is_empty() or fallback == "—" or fallback == "-":
		return "未知"
	return fallback
