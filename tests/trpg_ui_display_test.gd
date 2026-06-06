## 跑团 UI 展示格式化（`godot --headless -s tests/trpg_ui_display_test.gd`）
extends SceneTree

const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")
const LightRulesScript := preload("res://src/game/logic/rules/light_rules.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_hud_objective()
	failed += _test_pressure_labels()
	failed += _test_adventure_card_hides_secrets()
	failed += _test_adventure_card_no_bold()
	failed += _test_ability_modifier_line()
	failed += _test_check_bbcode()
	failed += _test_check_plain_text_storage()

	if failed == 0:
		print("[OK] trpg_ui_display tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_hud_objective() -> int:
	var line := TrpgUiDisplayScript.build_hud_objective_line({
		"immediate_goal": "找到密函",
	})
	if line != "当前目标：找到密函":
		push_error("objective line mismatch: %s" % line)
		return 1
	return 0


func _test_pressure_labels() -> int:
	if not TrpgUiDisplayScript.format_scene_pressure(0).begins_with("压力："):
		push_error("pressure format failed")
		return 1
	var meta := TrpgUiDisplayScript.build_hud_meta_line(5, {
		"needs_check": true,
		"check_label": "敏捷 判定 DC13",
		"outcome_label": "成功",
	})
	if meta.find("紧迫") < 0 or meta.find("上次判定") < 0:
		push_error("meta line missing parts: %s" % meta)
		return 1
	return 0


func _test_adventure_card_hides_secrets() -> int:
	var raw := {
		"immediate_goal": "潜入",
		"dm_secrets": ["真相"],
	}
	var player := TrpgUiDisplayScript.player_adventure_module(raw)
	if player.has("dm_secrets"):
		push_error("dm_secrets should be stripped")
		return 1
	var card := TrpgUiDisplayScript.build_adventure_card_bbcode(
		player,
		["门闩"],
		PackedStringArray(["张三"]),
	)
	if card.find("真相") >= 0:
		push_error("card should not contain dm secrets")
		return 1
	if card.find("潜入") < 0 or card.find("张三") < 0:
		push_error("card missing expected content: %s" % card)
		return 1
	return 0


func _test_adventure_card_no_bold() -> int:
	var card := TrpgUiDisplayScript.build_adventure_card_bbcode(
		{"immediate_goal": "潜入", "failure_pressure": "暴露"},
		["门闩"],
		PackedStringArray(),
	)
	if card.find("[b]") >= 0:
		push_error("card should not contain bold bbcode: %s" % card)
		return 1
	if card.find("当前目标：") < 0 or card.find("若失手：") < 0:
		push_error("card missing plain labels: %s" % card)
		return 1
	if card.find("\n\n") < 0:
		push_error("card should use double newlines between sections: %s" % card)
		return 1
	return 0


func _test_ability_modifier_line() -> int:
	var line := TrpgUiDisplayScript.ability_display_line("敏捷", 60)
	if line != "敏捷 60（+1）":
		push_error("ability line mismatch: %s" % line)
		return 1
	return 0


func _test_check_bbcode() -> int:
	var block := TrpgUiDisplayScript.format_check_block_bbcode({
		"needs_check": true,
		"check_label": "智力 判定 DC11",
		"outcome": LightRulesScript.OUTCOME_SUCCESS,
		"outcome_label": "成功",
		"d20": 15,
		"total": 16,
		"dc": 11,
	})
	if block.find("【判定】") < 0 or block.find("[color=") < 0:
		push_error("check bbcode missing markup: %s" % block)
		return 1
	return 0


func _test_check_plain_text_storage() -> int:
	var check := {
		"needs_check": true,
		"check_label": "智力 判定 DC11",
		"outcome_label": "成功",
		"d20": 15,
		"total": 16,
		"dc": 11,
	}
	var plain := TrpgUiDisplayScript.format_check_block_text(check)
	if "[color" in plain or "[Color" in plain:
		push_error("stored check text must be plain: %s" % plain)
		return 1
	var parsed := TrpgUiDisplayScript.parse_check_block_line(plain)
	if parsed.is_empty():
		push_error("parse_check_block_line failed: %s" % plain)
		return 1
	if str(parsed.get("outcome_label", "")) != "成功":
		push_error("parsed outcome mismatch")
		return 1
	return 0
