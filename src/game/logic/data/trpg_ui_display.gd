class_name TrpgUiDisplay
extends RefCounted

const LightRulesScript := preload("res://src/game/logic/rules/light_rules.gd")
const RichTextFormatScript := preload("res://src/ui/rich_text_format.gd")

static var _check_line_re: RegEx

## 跑团式 UI 文案与格式化（中性标签；具体内容来自 adventure_module / 运行时状态）。


static func clamp_line(text: String, max_len: int = 56) -> String:
	var t := text.strip_edges()
	if t.length() <= max_len:
		return t
	return t.substr(0, maxi(0, max_len - 1)) + "…"


static func player_adventure_module(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var out := (raw as Dictionary).duplicate(true)
	out.erase("dm_secrets")
	return out


static func format_scene_pressure(level: int) -> String:
	var p := maxi(0, level)
	if p <= 1:
		return "压力：平稳"
	if p <= 4:
		return "压力：升高（%d）" % p
	return "压力：紧迫（%d）" % p


static func format_npc_favorability(value: int) -> String:
	if value > 0:
		return "好感：+%d" % value
	if value < 0:
		return "好感：%d" % value
	return "好感：0"


static func format_npc_favorability_suffix(value: int) -> String:
	if value > 0:
		return " +%d" % value
	if value < 0:
		return " %d" % value
	return ""


static func format_last_check_summary(check: Variant) -> String:
	if not check is Dictionary:
		return ""
	var c: Dictionary = check
	if not c.get("needs_check", false):
		return ""
	var label := str(c.get("check_label", "")).strip_edges()
	var outcome := str(c.get("outcome_label", c.get("outcome", ""))).strip_edges()
	if label.is_empty():
		return ""
	if outcome.is_empty():
		return "上次判定：%s" % label
	return "上次判定：%s → %s" % [label, outcome]


static func build_hud_objective_line(adventure: Dictionary) -> String:
	var goal := str(adventure.get("immediate_goal", "")).strip_edges()
	if goal.is_empty():
		return ""
	return "当前目标：%s" % goal


static func build_hud_meta_line(scene_pressure: int, last_check: Variant) -> String:
	var parts: PackedStringArray = []
	var pressure := format_scene_pressure(scene_pressure)
	if not pressure.is_empty():
		parts.append(pressure)
	var check_line := format_last_check_summary(last_check)
	if not check_line.is_empty():
		parts.append(clamp_line(check_line, 40))
	return "  ".join(parts)


static func build_adventure_card_bbcode(
	adventure: Dictionary,
	scene_targets: Array,
	present_npc_names: PackedStringArray,
) -> String:
	if adventure.is_empty() and scene_targets.is_empty() and present_npc_names.is_empty():
		return ""

	var lines: PackedStringArray = []
	lines.append("本场局势")

	var tone := str(adventure.get("tone", "")).strip_edges()
	if not tone.is_empty():
		lines.append("基调：%s" % tone)

	var hook := str(adventure.get("opening_hook", "")).strip_edges()
	if not hook.is_empty():
		lines.append(hook)

	var goal := str(adventure.get("immediate_goal", "")).strip_edges()
	if not goal.is_empty():
		lines.append("当前目标：%s" % goal)

	var fail := str(adventure.get("failure_pressure", "")).strip_edges()
	if not fail.is_empty():
		lines.append("若失手：%s" % fail)

	var timer := str(adventure.get("scene_timer", "")).strip_edges()
	if not timer.is_empty():
		lines.append("时限：%s" % timer)

	if not present_npc_names.is_empty():
		lines.append("在场：%s" % "、".join(present_npc_names))

	if not scene_targets.is_empty():
		var targets: PackedStringArray = []
		for t in scene_targets:
			var s := str(t).strip_edges()
			if not s.is_empty():
				targets.append(s)
		if not targets.is_empty():
			lines.append("可调查：%s" % "、".join(targets))

	return "\n\n".join(lines)


## 存档与 story_log 使用的纯文本判定行（无 BBCode）。
static func format_check_block_text(check: Dictionary) -> String:
	if check.is_empty() or not check.get("needs_check", false):
		return ""
	var label := str(check.get("check_label", "")).strip_edges()
	var outcome := str(check.get("outcome_label", check.get("outcome", ""))).strip_edges()
	var d20 := int(check.get("d20", 0))
	var total := int(check.get("total", 0))
	var dc := int(check.get("dc", 0))
	return "【判定】%s → %s（d20=%d，合计=%d，DC=%d）" % [label, outcome, d20, total, dc]


static func format_check_block_bbcode(check: Dictionary) -> String:
	var plain := format_check_block_text(check)
	if plain.is_empty():
		return ""
	return format_check_line_bbcode(plain)


static func parse_check_block_line(line: String) -> Dictionary:
	var stripped := line.strip_edges()
	if stripped.is_empty():
		return {}
	var m := _check_line_regex().search(stripped)
	if m == null:
		return {}
	return {
		"check_label": m.get_string(1).strip_edges(),
		"outcome_label": m.get_string(2).strip_edges(),
		"d20": int(m.get_string(3)),
		"total": int(m.get_string(4)),
		"dc": int(m.get_string(5)),
	}


static func format_check_line_bbcode(line: String) -> String:
	var parsed := parse_check_block_line(line)
	if parsed.is_empty():
		return ""
	var label := str(parsed.get("check_label", ""))
	var outcome := str(parsed.get("outcome_label", ""))
	var d20 := int(parsed.get("d20", 0))
	var total := int(parsed.get("total", 0))
	var dc := int(parsed.get("dc", 0))
	var hex := _outcome_hex_from_label(outcome)
	return "【判定】%s → [color=%s]%s[/color]（d20=%d，合计=%d，DC=%d）" % [
		RichTextFormatScript.escape_bbcode(label),
		hex,
		RichTextFormatScript.escape_bbcode(outcome),
		d20,
		total,
		dc,
	]


static func _check_line_regex() -> RegEx:
	if _check_line_re == null:
		_check_line_re = RegEx.new()
		_check_line_re.compile(
			"^【判定】(.+?) → (.+?)（d20=(\\d+)，合计=(\\d+)，DC=(\\d+)）\\s*$"
		)
	return _check_line_re


static func ability_display_line(label: String, value: int) -> String:
	var mod := LightRulesScript.ability_modifier(value)
	var mod_text := "%+d" % mod if mod != 0 else "±0"
	return "%s %d（%s）" % [label, value, mod_text]


static func _outcome_hex(outcome: String) -> String:
	match outcome:
		LightRulesScript.OUTCOME_CRITICAL_SUCCESS, LightRulesScript.OUTCOME_SUCCESS:
			return "#6bcf7a"
		LightRulesScript.OUTCOME_PARTIAL:
			return "#d4b86a"
		LightRulesScript.OUTCOME_FAIL, LightRulesScript.OUTCOME_CRITICAL_FAIL:
			return "#e86b6b"
		_:
			return "#9ec5e8"


static func _outcome_hex_from_label(outcome_label: String) -> String:
	var label := outcome_label.strip_edges()
	for key in LightRulesScript.OUTCOME_LABELS:
		if str(LightRulesScript.OUTCOME_LABELS[key]) == label:
			return _outcome_hex(str(key))
	return _outcome_hex("")
