## 历史小说导出逻辑测试（`godot --headless -s tests/history_novel_exporter_test.gd`）
extends SceneTree

const EventTimelineLabelsScript := preload("res://src/game/logic/event_timeline_labels.gd")
const HistoryNovelExporterScript := preload("res://src/game/logic/data/history_novel_exporter.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_build_groups_order_and_labels()
	failed += _test_render_prefers_story_body()
	failed += _test_safe_filename()
	if failed == 0:
		print("[OK] history novel exporter tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_build_groups_order_and_labels() -> int:
	var events: Array = [
		{"timestamp": 2, "title": "第三"},
		{"timestamp": 0, "title": "开端"},
		{"timestamp": 1, "title": "第二"},
	]
	var groups: Array = HistoryNovelExporterScript.build_groups(events)
	if groups.size() != 3:
		push_error("build_groups: expected 3 groups, got %d" % groups.size())
		return 1
	var g0: Dictionary = groups[0]
	if int(g0.get("timestamp", -1)) != 0 or str(g0.get("label", "")) != "序章":
		push_error("build_groups: first group should be 序章")
		return 1
	var g2: Dictionary = groups[2]
	if str(g2.get("label", "")) != "第 2 幕":
		push_error("build_groups: third group label wrong: %s" % g2.get("label"))
		return 1
	var evs: Array = g0.get("events", [])
	if evs.size() != 1 or str((evs[0] as Dictionary).get("title", "")) != "开端":
		push_error("build_groups: 序章 events mismatch")
		return 1
	return 0


func _test_render_prefers_story_body() -> int:
	var events: Array = [
		{
			"title": "测试章",
			"summary": "摘要",
			"story_body": "完整剧情",
			"compact_body": "压缩",
		},
	]
	var text := HistoryNovelExporterScript.render_timeline_file("序章", events, Callable())
	if not text.contains("完整剧情"):
		push_error("render: should use story_body")
		return 1
	if text.contains("压缩"):
		push_error("render: should not use compact_body when story_body present")
		return 1
	if not text.begins_with("序章"):
		push_error("render: should start with timeline label")
		return 1
	return 0


func _test_safe_filename() -> int:
	if EventTimelineLabelsScript.safe_filename_from_label("第 1 幕") != "第 1 幕":
		push_error("safe_filename: spaces should be kept")
		return 1
	var bad := EventTimelineLabelsScript.safe_filename_from_label('a/b:c')
	if bad.find("/") >= 0 or bad.find(":") >= 0:
		push_error("safe_filename: invalid chars not replaced: %s" % bad)
		return 1
	if EventTimelineLabelsScript.safe_filename_from_label("   ") != "未命名":
		push_error("safe_filename: empty should be 未命名")
		return 1
	return 0
