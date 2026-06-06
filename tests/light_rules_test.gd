## 轻规则掷骰（`godot --headless -s tests/light_rules_test.gd`）
extends SceneTree

const LightRulesScript := preload("res://src/game/logic/rules/light_rules.gd")
const ActionCheckPlannerScript := preload("res://src/game/logic/rules/action_check_planner.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_ability_modifier()
	failed += _test_outcome_tiers()
	failed += _test_planner_detects_stealth()

	if failed == 0:
		print("[OK] light_rules tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_ability_modifier() -> int:
	if LightRulesScript.ability_modifier(50) != 0:
		push_error("50 should be +0 modifier")
		return 1
	if LightRulesScript.ability_modifier(60) != 1:
		push_error("60 should be +1 modifier")
		return 1
	return 0


func _test_outcome_tiers() -> int:
	if LightRulesScript.outcome_from_roll(20, 5, 15) != LightRulesScript.OUTCOME_CRITICAL_SUCCESS:
		push_error("nat 20 should be critical success")
		return 1
	if LightRulesScript.outcome_from_roll(10, 14, 12) != LightRulesScript.OUTCOME_PARTIAL:
		push_error("total>=dc should be partial or success")
		return 1
	return 0


func _test_planner_detects_stealth() -> int:
	var plan := ActionCheckPlannerScript.plan("悄悄潜入仓库", null)
	if not plan.get("needs_check", false):
		push_error("stealth action should need check")
		return 1
	if str(plan.get("ability", "")) != "agi":
		push_error("stealth should use agi")
		return 1
	return 0
