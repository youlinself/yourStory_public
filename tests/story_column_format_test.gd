## 叙事 StoryLog BBCode 格式化（`godot --headless -s tests/story_column_format_test.gd`）
extends SceneTree

const RichTextFormatScript := preload("res://src/ui/rich_text_format.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const StoryColumnUIScript := preload("res://src/game/ui/story_column_ui.gd")
const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_dialogue_prefix_line()
	failed += _test_format_assistant_dialogue()
	failed += _test_format_assistant_plain()
	failed += _test_format_assistant_escape()
	failed += _test_format_assistant_paragraphs()
	failed += _test_sanitize_strips_ai_bbcode()
	failed += _test_format_assistant_check_line()
	failed += _test_sanitize_plain_text_once_double_escape()
	if failed == 0:
		print("[OK] story_column_format tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_dialogue_prefix_line() -> int:
	var out := RichTextFormatScript.dialogue_prefix_line(
		"林浩",
		"你好",
		DesignTokensScript.STORY_DIALOGUE_PREFIX_HEX,
	)
	if "[color=%s]" % DesignTokensScript.STORY_DIALOGUE_PREFIX_HEX not in out:
		push_error("dialogue_prefix_line: expected color wrapper")
		return 1
	if "[b]" in out or "[/b]" in out:
		push_error("dialogue_prefix_line: should not use bold")
		return 1
	if out != "[color=%s]林浩[/color]：「你好」" % DesignTokensScript.STORY_DIALOGUE_PREFIX_HEX:
		push_error("dialogue_prefix_line: unexpected output: %s" % out)
		return 1
	return 0


func _test_format_assistant_dialogue() -> int:
	var ui := StoryColumnUIScript.new()
	var out := ui._format_assistant_text("林浩在椅子上坐下：「死者男性，中年」")
	if "[b]" in out:
		push_error("assistant dialogue: should not use bold")
		return 1
	if DesignTokensScript.STORY_DIALOGUE_PREFIX_HEX not in out:
		push_error("assistant dialogue: expected dialogue prefix color")
		return 1
	if "林浩在椅子上坐下" not in out or "死者男性，中年" not in out:
		push_error("assistant dialogue: expected prefix and dialogue text preserved")
		return 1
	return 0


func _test_format_assistant_plain() -> int:
	var ui := StoryColumnUIScript.new()
	var out := ui._format_assistant_text("雨雾贴着广场的青石砖面缓缓流动。")
	if "[color=" in out or "[b]" in out:
		push_error("assistant plain: should not wrap non-dialogue lines")
		return 1
	return 0


func _test_format_assistant_escape() -> int:
	var ui := StoryColumnUIScript.new()
	var out := ui._format_assistant_text("含括号[a[b]c")
	if "[lb]" not in out or "[rb]" not in out:
		push_error("assistant escape: expected bbcode bracket escapes")
		return 1
	return 0


func _test_format_assistant_paragraphs() -> int:
	var ui := StoryColumnUIScript.new()
	var text := "第一段开场。\n\n第二段动作。\n铜锣：「还不下来！」\n\n第三段收尾。"
	var out := ui._format_assistant_text(text)
	if not out.begins_with("　　第一段开场。"):
		push_error("assistant paragraphs: first line should have indent")
		return 1
	if "　　第二段动作。" not in out:
		push_error("assistant paragraphs: new paragraph should have indent")
		return 1
	if "\n\n" not in out:
		push_error("assistant paragraphs: expected blank line between paragraphs")
		return 1
	if DesignTokensScript.STORY_DIALOGUE_PREFIX_HEX not in out:
		push_error("assistant paragraphs: dialogue line should keep prefix color")
		return 1
	if "　　第三段收尾。" not in out:
		push_error("assistant paragraphs: final paragraph should have indent")
		return 1
	return 0


func _test_sanitize_strips_ai_bbcode() -> int:
	var raw := "结果：[Color=#ff0000]失败[/Color]"
	var out := RichTextFormatScript.sanitize_plain_text(raw)
	if "[Color" in out or "[/Color]" in out or "[color" in out:
		push_error("sanitize should strip color tags, got: %s" % out)
		return 1
	if "失败" not in out:
		push_error("sanitize should keep inner text")
		return 1
	return 0


func _test_sanitize_plain_text_once_double_escape() -> int:
	var double_escaped := '{"tool_requests":[lb][lb][lb]rb][lb]rb]'
	var out := RichTextFormatScript.sanitize_plain_text_once(double_escaped)
	if "[lb][lb][lb]rb]" in out:
		push_error("double escape: expected decoded brackets, got %s" % out)
		return 1
	if "tool_requests" not in out:
		push_error("double escape: expected readable key name")
		return 1
	var ui := StoryColumnUIScript.new()
	var rendered := ui._format_assistant_text(double_escaped)
	if "[lb][lb][lb]rb]" in rendered:
		push_error("assistant double escape: expected clean display, got %s" % rendered)
		return 1
	return 0


func _test_format_assistant_check_line() -> int:
	var plain := TrpgUiDisplayScript.format_check_block_text({
		"needs_check": true,
		"check_label": "敏捷 判定 DC13",
		"outcome_label": "成功",
		"d20": 15,
		"total": 16,
		"dc": 13,
	})
	var ui := StoryColumnUIScript.new()
	var out := ui._format_assistant_text(plain)
	if "[color=" not in out:
		push_error("check line should get local color bbcode: %s" % out)
		return 1
	if "[Color" in out:
		push_error("should not leak raw Color tag: %s" % out)
		return 1
	if "成功" not in out:
		push_error("check outcome text missing")
		return 1
	return 0
