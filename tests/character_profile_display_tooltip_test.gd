## 角色资料 tooltip 数据（`godot --headless -s tests/character_profile_display_tooltip_test.gd`）
extends SceneTree

const ProfileDisplayScript := preload("res://src/game/logic/data/character_profile_display.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_section_tooltips()
	failed += _test_psychology_row_tooltips()
	failed += _test_ability_row_tooltips()

	if failed == 0:
		print("[OK] character_profile_display tooltip tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_section_tooltips() -> int:
	var psych := ProfileDisplayScript.PSYCHOLOGY_SECTION_TOOLTIP
	if psych != "心境：解释为角色长期心理倾向与互动风格。":
		push_error("psychology section tooltip mismatch: %s" % psych)
		return 1
	var ability := ProfileDisplayScript.ABILITY_SECTION_TOOLTIP
	if ability != "属性：解释为行动判定中常用的基础能力，50 约等于普通水平。":
		push_error("ability section tooltip mismatch: %s" % ability)
		return 1
	return 0


func _test_psychology_row_tooltips() -> int:
	var profile := {
		"psychology": {
			"openness": 72,
			"conscientiousness": 48,
			"extraversion": 55,
			"agreeableness": 62,
			"neuroticism": 64,
		},
	}
	var rows: Array = ProfileDisplayScript.build_psychology_stat_rows(profile)
	if rows.size() != ProfileDisplayScript.PSYCHOLOGY_KEYS.size():
		push_error("psychology row count mismatch: %d" % rows.size())
		return 1
	for row in rows:
		if not row is Dictionary:
			push_error("psychology row is not a dictionary")
			return 1
		var tip := str(row.get("tooltip", "")).strip_edges()
		if tip.is_empty():
			push_error("psychology row missing tooltip: %s" % str(row.get("key", "")))
			return 1
		var label := str(row.get("label", "")).strip_edges()
		if not tip.begins_with("%s：" % label):
			push_error("psychology tooltip format mismatch: %s" % tip)
			return 1
	return 0


func _test_ability_row_tooltips() -> int:
	var profile := {
		"abilities": {
			"str": 38,
			"agi": 62,
			"con": 45,
			"int": 71,
			"mnd": 66,
			"cha": 58,
		},
	}
	var rows: Array = ProfileDisplayScript.build_ability_stat_rows(profile)
	if rows.size() != ProfileDisplayScript.ABILITY_KEYS.size():
		push_error("ability row count mismatch: %d" % rows.size())
		return 1
	for row in rows:
		if not row is Dictionary:
			push_error("ability row is not a dictionary")
			return 1
		var tip := str(row.get("tooltip", "")).strip_edges()
		if tip.is_empty():
			push_error("ability row missing tooltip: %s" % str(row.get("key", "")))
			return 1
		var label := str(row.get("label", "")).strip_edges()
		if not tip.begins_with("%s：" % label):
			push_error("ability tooltip format mismatch: %s" % tip)
			return 1
	return 0
