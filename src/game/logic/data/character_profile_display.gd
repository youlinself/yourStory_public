class_name CharacterProfileDisplay
extends RefCounted

const SkillCatalog := preload("res://src/game/logic/data/skill_display_catalog.gd")
const RichTextFormatScript := preload("res://src/ui/rich_text_format.gd")
const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")

const INFO_FIELD_LABELS: Dictionary = {
	"age": "年龄",
	"性别": "性别",
	"族群": "族群",
	"origin": "出身",
	"physical_traits": "外貌",
	"personality": "性格",
	"deep_motivation": "深层动机",
	"core_conflict": "核心冲突",
}

const ABILITY_KEYS: Array[String] = ["str", "agi", "con", "int", "mnd", "cha"]

const PSYCHOLOGY_KEYS: Array[String] = [
	"openness",
	"conscientiousness",
	"extraversion",
	"agreeableness",
	"neuroticism",
]

const PSYCHOLOGY_SECTION_TOOLTIP := "心境：解释为角色长期心理倾向与互动风格。"

const ABILITY_SECTION_TOOLTIP := "属性：解释为行动判定中常用的基础能力，50 约等于普通水平。"

const PSYCHOLOGY_TOOLTIPS: Dictionary = {
	"openness": "对新经验、想象力、变化与非常规线索的接受度。",
	"conscientiousness": "计划性、自律、可靠性与执行承诺的倾向。",
	"extraversion": "主动表达、社交能量与在人群中行动的倾向。",
	"agreeableness": "共情、合作、信任与缓和冲突的倾向。",
	"neuroticism": "压力敏感度、情绪波动与危机下不安程度。",
}

const ABILITY_TOOLTIPS: Dictionary = {
	"str": "爆发力、负重、近身对抗与强行突破。",
	"agi": "速度、反应、闪避、潜行与精细身手。",
	"con": "耐力、抗伤、抗病、长时间行动与环境承受力。",
	"int": "分析、学习、记忆、推理与技术理解。",
	"mnd": "意志、专注、感知、抗压与抵御精神影响。",
	"cha": "说服、表演、领导、谈判与社交影响力。",
}


static func build_info_text(known_profile: Dictionary) -> String:
	return build_text_fields_text(known_profile)


static func build_text_fields_text(known_profile: Dictionary) -> String:
	var lines := build_text_field_lines(known_profile)
	return "\n\n".join(lines)


static func build_text_field_lines(known_profile: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	for field in INFO_FIELD_LABELS:
		if not known_profile.has(field):
			continue
		var label: String = INFO_FIELD_LABELS[field]
		lines.append(
			RichTextFormatScript.bold_label_line(
				label,
				SkillCatalog.format_player_visible(known_profile[field]),
			),
		)
	return lines


static func build_psychology_stat_rows(known_profile: Dictionary) -> Array:
	if not known_profile.has("psychology"):
		return []
	var psychology: Variant = known_profile.get("psychology", {})
	if not psychology is Dictionary:
		return []
	return _build_stat_rows(
		psychology as Dictionary,
		PSYCHOLOGY_KEYS,
		_psychology_label,
		PSYCHOLOGY_TOOLTIPS,
	)


static func build_ability_stat_rows(known_profile: Dictionary) -> Array:
	if not known_profile.has("abilities"):
		return []
	var abilities: Variant = known_profile.get("abilities", {})
	if not abilities is Dictionary:
		return []
	var stats: Dictionary = abilities as Dictionary
	var rows: Array = []
	for key in ABILITY_KEYS:
		if stats.has(key):
			var value := int(stats[key])
			var short_label := _ability_label(key)
			var tip_desc := str(ABILITY_TOOLTIPS.get(key, "")).strip_edges()
			rows.append({
				"key": key,
				"label": short_label,
				"value": value,
				"display_label": TrpgUiDisplayScript.ability_display_line(short_label, value),
				"tooltip": _format_stat_tooltip(short_label, tip_desc),
			})
	return rows


static func _build_stat_rows(
	stats: Dictionary,
	keys: Array[String],
	label_fn: Callable,
	tooltip_map: Dictionary,
) -> Array:
	var rows: Array = []
	for key in keys:
		if stats.has(key):
			var short_label: String = str(label_fn.call(key))
			var tip_desc := str(tooltip_map.get(key, "")).strip_edges()
			rows.append({
				"key": key,
				"label": short_label,
				"value": int(stats[key]),
				"tooltip": _format_stat_tooltip(short_label, tip_desc),
			})
	return rows


static func _format_stat_tooltip(label: String, description: String) -> String:
	var name := label.strip_edges()
	var desc := description.strip_edges()
	if name.is_empty():
		return desc
	if desc.is_empty():
		return name
	return "%s：%s" % [name, desc]


static func _ability_label(key: String) -> String:
	match key:
		"str": return "力量"
		"agi": return "敏捷"
		"con": return "体质"
		"int": return "智力"
		"mnd": return "精神"
		"cha": return "魅力"
		_: return key


static func _psychology_label(key: String) -> String:
	match key:
		"openness": return "开放性"
		"conscientiousness": return "尽责性"
		"extraversion": return "外倾性"
		"agreeableness": return "宜人性"
		"neuroticism": return "神经质"
		_: return key
