## StoryTextEdit Enter 提交冒烟（`godot --headless -s tests/story_text_edit_submit_test.gd`）
extends SceneTree

const StoryTextEditScript := preload("res://src/game/ui/story_text_edit.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_enter_emits_submitted()
	failed += _test_shift_enter_does_not_submit()
	failed += _test_submit_gate_blocks_submit()
	if failed == 0:
		print("[OK] story_text_edit_submit tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_enter_emits_submitted() -> int:
	var edit := StoryTextEditScript.new()
	edit._ready()
	edit.text = "测试行动"
	var submitted := false
	var captured := ""
	edit.text_submitted.connect(func(t: String) -> void:
		submitted = true
		captured = t
	)
	edit._gui_input(_make_enter_key(false))
	if not submitted:
		push_error("enter: expected text_submitted")
		return 1
	if captured != "测试行动":
		push_error("enter: unexpected payload: %s" % captured)
		return 1
	return 0


func _test_shift_enter_does_not_submit() -> int:
	var edit := StoryTextEditScript.new()
	edit._ready()
	var submitted := false
	edit.text_submitted.connect(func(_t: String) -> void: submitted = true)
	edit._gui_input(_make_enter_key(true))
	if submitted:
		push_error("shift+enter: should not submit")
		return 1
	return 0


func _test_submit_gate_blocks_submit() -> int:
	var edit := StoryTextEditScript.new()
	edit._ready()
	edit.submit_gate = func() -> bool: return false
	var submitted := false
	edit.text_submitted.connect(func(_t: String) -> void: submitted = true)
	edit._gui_input(_make_enter_key(false))
	if submitted:
		push_error("submit_gate: should block submit")
		return 1
	return 0


func _make_enter_key(shift: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.echo = false
	ev.keycode = KEY_ENTER
	ev.shift_pressed = shift
	return ev
