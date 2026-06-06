class_name ActionCheckPlanner
extends RefCounted

const LightRulesScript := preload("res://src/game/logic/rules/light_rules.gd")

## 根据玩家自然语言行动推断轻规则判定（本地、无 AI）。

const _PATTERNS: Array[Dictionary] = [
	{"keys": ["潜行", "偷偷", "隐蔽", "潜入", "躲藏"], "ability": "agi", "dc": 13},
	{"keys": ["说服", "劝说", "谈判", "哄", "欺骗", "谎"], "ability": "cha", "dc": 12},
	{"keys": ["调查", "搜查", "检查", "观察", "辨认", "分析"], "ability": "int", "dc": 11},
	{"keys": ["攻击", "打", "砍", "刺", "射击", "战斗"], "ability": "str", "dc": 13},
	{"keys": ["闪避", "躲开", "躲避", "格挡"], "ability": "agi", "dc": 12},
	{"keys": ["扛", "坚持", "抵抗", "忍耐", "撑"], "ability": "con", "dc": 12},
	{"keys": ["攀爬", "跳", "跑", "追"], "ability": "agi", "dc": 11},
	{"keys": ["读", "回忆", "想起", "推理"], "ability": "int", "dc": 10},
	{"keys": ["冷静", "镇定", "意志"], "ability": "mnd", "dc": 12},
]

const _TRIVIAL: Array[String] = [
	"休息",
	"等待",
	"看看周围",
	"环顾",
	"继续",
	"停下",
	"离开",
	"对话",
	"说话",
	"问",
]


static func plan(player_text: String, read_model: GameReadModel) -> Dictionary:
	var text := player_text.strip_edges()
	if text.is_empty():
		return LightRulesScript.no_check_result("空行动")

	for trivial in _TRIVIAL:
		if text == trivial or text.begins_with(trivial):
			return LightRulesScript.no_check_result("日常行动")

	for entry in _PATTERNS:
		var keys: Array = entry.get("keys", [])
		for key in keys:
			if str(key) in text:
				return _build_plan(entry, read_model)

	return LightRulesScript.no_check_result("无需判定")


static func execute_plan(check_plan: Dictionary, read_model: GameReadModel) -> Dictionary:
	if not check_plan.get("needs_check", false):
		return check_plan.duplicate(true)
	var abilities: Dictionary = {}
	if read_model != null and read_model.mainrole is Dictionary:
		var raw: Variant = read_model.mainrole.get("abilities", {})
		if raw is Dictionary:
			abilities = raw
	var dc := int(check_plan.get("dc", 12))
	var ability_key := str(check_plan.get("ability", "int"))
	var skill_bonus := int(check_plan.get("skill_bonus", 0))
	var resolved := LightRulesScript.resolve_check(abilities, ability_key, dc, skill_bonus)
	resolved["intent"] = str(check_plan.get("intent", ""))
	resolved["check_label"] = str(check_plan.get("check_label", ""))
	return resolved


static func plan_and_roll(player_text: String, read_model: GameReadModel) -> Dictionary:
	var check_plan := plan(player_text, read_model)
	if not check_plan.get("needs_check", false):
		return check_plan
	return execute_plan(check_plan, read_model)


static func _build_plan(entry: Dictionary, read_model: GameReadModel) -> Dictionary:
	var ability := str(entry.get("ability", "int"))
	var dc := int(entry.get("dc", 12))
	var skill_bonus := 0
	if read_model != null:
		skill_bonus = _skill_bonus_for_ability(read_model, ability)
	return {
		"needs_check": true,
		"ability": ability,
		"dc": dc,
		"skill_bonus": skill_bonus,
		"intent": _ability_label(ability),
		"check_label": "%s 判定 DC%d" % [_ability_label(ability), dc],
	}


static func _ability_label(key: String) -> String:
	match key:
		"str":
			return "力量"
		"agi":
			return "敏捷"
		"con":
			return "体质"
		"int":
			return "智力"
		"mnd":
			return "精神"
		"cha":
			return "魅力"
		_:
			return key


static func _skill_bonus_for_ability(read_model: GameReadModel, ability: String) -> int:
	var skills: Variant = read_model.mainrole.get("skills", [])
	if not skills is Array or skills.is_empty():
		return 0
	var skill_map: Variant = read_model.get_skills_catalog()
	if not skill_map is Dictionary:
		return 0
	var bonus := 0
	for sid_raw in skills:
		var sid := str(sid_raw).strip_edges()
		if sid.is_empty() or not skill_map.has(sid):
			continue
		var entry: Variant = skill_map[sid]
		if not entry is Dictionary:
			continue
		var desc := str(entry.get("desc", "")) + str(entry.get("name", ""))
		if _skill_matches_ability(desc, ability):
			bonus += 1
	return mini(bonus, 2)


static func _skill_matches_ability(desc: String, ability: String) -> bool:
	match ability:
		"str":
			return "力" in desc or "战" in desc or "武" in desc
		"agi":
			return "敏" in desc or "闪" in desc or "潜" in desc
		"con":
			return "体" in desc or "耐" in desc or "扛" in desc
		"int":
			return "智" in desc or "识" in desc or "查" in desc or "技" in desc
		"mnd":
			return "精" in desc or "意" in desc or "感" in desc
		"cha":
			return "魅" in desc or "说" in desc or "交" in desc
		_:
			return false
