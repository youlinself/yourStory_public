class_name LightRules
extends RefCounted

## 轻规则跑团：d20 + 属性修正（50 为常人，每 10 点 ±1）。

const OUTCOME_CRITICAL_SUCCESS := "critical_success"
const OUTCOME_SUCCESS := "success"
const OUTCOME_PARTIAL := "partial"
const OUTCOME_FAIL := "fail"
const OUTCOME_CRITICAL_FAIL := "critical_fail"

const OUTCOME_LABELS: Dictionary = {
	OUTCOME_CRITICAL_SUCCESS: "大成功",
	OUTCOME_SUCCESS: "成功",
	OUTCOME_PARTIAL: "部分成功",
	OUTCOME_FAIL: "失败",
	OUTCOME_CRITICAL_FAIL: "大失败",
}


static func ability_modifier(score: int) -> int:
	return floori((clampi(score, 0, 100) - 50) / 10.0)


static func roll_d20(rng: RandomNumberGenerator = null) -> int:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	return r.randi_range(1, 20)


static func outcome_from_roll(d20: int, total: int, dc: int) -> String:
	if d20 >= 20:
		return OUTCOME_CRITICAL_SUCCESS
	if d20 <= 1:
		return OUTCOME_CRITICAL_FAIL
	if total >= dc + 5:
		return OUTCOME_SUCCESS
	if total >= dc:
		return OUTCOME_PARTIAL
	return OUTCOME_FAIL


static func resolve_check(
	abilities: Dictionary,
	ability_key: String,
	dc: int,
	skill_bonus: int = 0,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	var abil := ability_key.strip_edges()
	if abil.is_empty():
		abil = "int"
	var score := int(abilities.get(abil, 50))
	var mod := ability_modifier(score) + skill_bonus
	var d20 := roll_d20(rng)
	var total := d20 + mod
	var outcome := outcome_from_roll(d20, total, dc)
	return {
		"needs_check": true,
		"ability": abil,
		"dc": maxi(5, dc),
		"d20": d20,
		"modifier": mod,
		"total": total,
		"outcome": outcome,
		"outcome_label": str(OUTCOME_LABELS.get(outcome, outcome)),
	}


static func no_check_result(reason: String = "") -> Dictionary:
	return {
		"needs_check": false,
		"reason": reason,
	}
