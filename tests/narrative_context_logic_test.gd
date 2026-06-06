## 叙事上下文逻辑冒烟测试（可用 Godot 编辑器或 `godot --headless -s tests/narrative_context_logic_test.gd` 运行）
extends SceneTree

const NarrativeArchiveServiceScript := preload(
	"res://src/game/logic/narrative/narrative_archive_service.gd"
)
const ReadModelScript := preload("res://src/game/logic/data/game_read_model.gd")
const ItemDisplayCatalogScript := preload("res://src/game/logic/data/item_display_catalog.gd")
const RuntimeStateServiceScript := preload("res://src/game/logic/state/runtime_state_service.gd")


func _initialize() -> void:
	var failed := 0
	failed += _test_split_story_log()
	failed += _test_resolve_retained_below_threshold()
	failed += _test_long_assistant_resolve()
	failed += _test_can_archive_pending()
	failed += _test_chars_since_last_archive_hysteresis()
	failed += _test_count_story_log_chars()
	failed += _test_should_archive_story()
	failed += _test_source_char_count_matches_story_body()
	failed += _test_hook_not_counted_in_story_log()
	failed += _test_recent_events_order()
	failed += _test_events_match_recall()
	failed += _test_pinned_recall_read_model()
	failed += _test_world_familiarity_inference()
	failed += _test_seed_starter_world_familiarity()
	if failed == 0:
		print("[OK] narrative context logic tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_split_story_log() -> int:
	var entries: Array = [
		{"role": "user", "content": "a".repeat(2500)},
		{"role": "assistant", "content": "b".repeat(2500)},
	]
	var split: Dictionary = NarrativeArchiveServiceScript.resolve_pending_archive_split(entries)
	var to_arch: Array = split.get("to_archive", [])
	var retained: Array = split.get("retained", [])
	if to_arch.is_empty():
		push_error("split_story_log: expected non-empty to_archive")
		return 1
	if retained.is_empty():
		push_error("split_story_log: expected non-empty retained tail")
		return 1
	var retained_chars: int = NarrativeArchiveServiceScript.count_story_log_chars(retained, 0)
	if retained_chars >= NarrativeArchiveServiceScript.ARCHIVE_CHAR_THRESHOLD:
		push_error("split_story_log: retained %d should be below threshold" % retained_chars)
		return 1
	return 0


func _test_resolve_retained_below_threshold() -> int:
	var entries: Array = [
		{"role": "user", "content": "u".repeat(50)},
		{"role": "assistant", "content": "a".repeat(5000)},
	]
	var split: Dictionary = NarrativeArchiveServiceScript.resolve_pending_archive_split(entries)
	var to_arch: Array = split.get("to_archive", [])
	var retained: Array = split.get("retained", [])
	if to_arch.is_empty():
		push_error("resolve: expected to_archive for long assistant tail")
		return 1
	var retained_chars: int = NarrativeArchiveServiceScript.count_story_log_chars(retained, 0)
	if retained_chars >= NarrativeArchiveServiceScript.ARCHIVE_CHAR_THRESHOLD:
		push_error("resolve: retained %d must stay below threshold" % retained_chars)
		return 1
	if retained_chars > NarrativeArchiveServiceScript.RETAIN_MAX_CHARS:
		push_error("resolve: retained %d exceeds RETAIN_MAX_CHARS" % retained_chars)
		return 1
	return 0


func _test_long_assistant_resolve() -> int:
	var single: Array = [{"role": "assistant", "content": "z".repeat(5000)}]
	var split: Dictionary = NarrativeArchiveServiceScript.resolve_pending_archive_split(single)
	var to_arch: Array = split.get("to_archive", [])
	if to_arch.is_empty():
		push_error("long assistant: entire entry should be archivable")
		return 1
	if not NarrativeArchiveServiceScript.can_archive_pending(single, 0, 5000):
		push_error("long assistant: can_archive_pending should be true")
		return 1
	return 0


func _test_can_archive_pending() -> int:
	var short: Array = [{"role": "assistant", "content": "hi"}]
	if NarrativeArchiveServiceScript.can_archive_pending(short, 0, 0):
		push_error("can_archive_pending: short log should not archive")
		return 1
	var over: Array = [
		{"role": "user", "content": "a".repeat(2000)},
		{"role": "assistant", "content": "b".repeat(2000)},
	]
	if not NarrativeArchiveServiceScript.can_archive_pending(over, 0, 4000):
		push_error("can_archive_pending: 4000+ log should be archivable")
		return 1
	return 0


func _test_chars_since_last_archive_hysteresis() -> int:
	if NarrativeArchiveServiceScript.should_archive_story([], 0, 3999):
		push_error("chars_since: 3999 should not trigger")
		return 1
	if not NarrativeArchiveServiceScript.should_archive_story([], 0, 4000):
		push_error("chars_since: 4000 should trigger")
		return 1
	var post_tail: Array = [
		{"role": "user", "content": "x".repeat(500)},
		{"role": "assistant", "content": "y".repeat(2000)},
	]
	var since := NarrativeArchiveServiceScript.count_story_log_chars(post_tail, 0)
	if NarrativeArchiveServiceScript.should_archive_story(post_tail, 0, since):
		push_error("post_archive tail: should not trigger at %d chars_since" % since)
		return 1
	return 0


func _test_count_story_log_chars() -> int:
	var entries: Array = [
		{"role": "user", "content": "x".repeat(100)},
		{"role": "assistant", "content": "y".repeat(200)},
		{"role": "system", "content": "ignored"},
		{"role": "assistant", "content": ""},
	]
	var n: int = NarrativeArchiveServiceScript.count_story_log_chars(entries, 0)
	if n != 300:
		push_error("count_story_log_chars: expected 300, got %d" % n)
		return 1
	var n2: int = NarrativeArchiveServiceScript.count_story_log_chars(entries, 1)
	if n2 != 200:
		push_error("count_story_log_chars from_index: expected 200, got %d" % n2)
		return 1
	return 0


func _test_should_archive_story() -> int:
	var below: Array = [{"role": "assistant", "content": "z".repeat(3999)}]
	if NarrativeArchiveServiceScript.should_archive_story(below, 0):
		push_error("should_archive_story: 3999 should not trigger")
		return 1
	var at: Array = [{"role": "assistant", "content": "z".repeat(4000)}]
	if not NarrativeArchiveServiceScript.should_archive_story(at, 0):
		push_error("should_archive_story: 4000 should trigger")
		return 1
	return 0


func _test_source_char_count_matches_story_body() -> int:
	var body_len := 4000
	var entries: Array = [{"role": "assistant", "content": "z".repeat(body_len)}]
	var story_text := NarrativeArchiveServiceScript.build_story_text_from_log(entries, 0, entries.size())
	var char_count: int = story_text.strip_edges().length()
	if char_count != body_len:
		push_error("source_char_count: expected %d, got %d" % [body_len, char_count])
		return 1
	return 0


func _test_hook_not_counted_in_story_log() -> int:
	var visible_log: Array = [{"role": "assistant", "content": "narrative only"}]
	var visible_count: int = NarrativeArchiveServiceScript.count_story_log_chars(visible_log, 0)
	if visible_count >= NarrativeArchiveServiceScript.ARCHIVE_CHAR_THRESHOLD:
		push_error("hook test: visible log should be below threshold")
		return 1
	if NarrativeArchiveServiceScript.should_archive_story(visible_log, 0):
		push_error("hook test: short visible log must not trigger archive")
		return 1
	return 0


func _test_recent_events_order() -> int:
	var rm := ReadModelScript.new()
	rm.game_state = {
		"event_log": [
			{"timestamp": 1, "title": "第一章", "summary": "s1", "compact_body": "c1"},
			{"timestamp": 2, "title": "第二章", "summary": "s2", "compact_body": "c2"},
			{"timestamp": 3, "title": "第三章", "summary": "s3", "compact_body": "c3"},
			{"timestamp": 4, "title": "第四章", "summary": "s4", "compact_body": "c4"},
		],
	}
	rm.mainrole = {"current_region_id": "r1"}
	var snap := rm.build_narrative_snapshot("", {})
	var recent: Array = snap.get("recent_events", [])
	if recent.size() != 3:
		push_error("recent_events: expected 3 items, got %d" % recent.size())
		return 1
	if str(recent[0].get("title", "")) != "第二章":
		push_error("recent_events: expected 第二章 first, got %s" % recent[0].get("title"))
		return 1
	if str(recent[2].get("title", "")) != "第四章":
		push_error("recent_events: expected 第四章 last, got %s" % recent[2].get("title"))
		return 1
	var rel := rm.get_relevant_events("第三章 线索", "r1", {}, 2)
	if rel.is_empty():
		push_error("relevant_events: expected match for 第三章")
		return 1
	return 0


func _test_events_match_recall() -> int:
	var a := {"title": "故事开端", "timestamp": 0}
	var b := {"title": "故事开端", "timestamp": 0}
	if not RuntimeStateServiceScript.events_match_recall(a, b):
		push_error("events_match_recall: same title+timestamp should match")
		return 1
	var c := {"title": "故事开端", "timestamp": 1}
	if RuntimeStateServiceScript.events_match_recall(a, c):
		push_error("events_match_recall: different timestamp should not match")
		return 1
	var d := {"title": "其他", "timestamp": 0}
	if RuntimeStateServiceScript.events_match_recall(a, d):
		push_error("events_match_recall: different title should not match")
		return 1
	return 0


func _test_pinned_recall_read_model() -> int:
	var rm := ReadModelScript.new()
	var event := {"title": "故事开端", "timestamp": 0}
	rm.game_state = {"pinned_recall_event": event.duplicate(true)}
	if not rm.is_event_pinned_for_recall(event):
		push_error("is_event_pinned_for_recall: expected pinned")
		return 1
	if rm.get_pinned_recall_event().is_empty():
		push_error("get_pinned_recall_event: expected non-empty")
		return 1
	rm.game_state.erase("pinned_recall_event")
	if rm.is_event_pinned_for_recall(event):
		push_error("is_event_pinned_for_recall: expected not pinned after erase")
		return 1
	return 0


func _test_world_familiarity_inference() -> int:
	if ItemDisplayCatalogScript.infer_world_familiarity_from_id("flashlight") != "域外异物":
		push_error("infer_world_familiarity_from_id: flashlight should be foreign")
		return 1
	if ItemDisplayCatalogScript.infer_world_familiarity_from_id("copper_coin") != "本土寻常":
		push_error("infer_world_familiarity_from_id: copper_coin should be native")
		return 1
	var row := {"world_familiarity": "本土罕见"}
	if ItemDisplayCatalogScript.resolve_world_familiarity(row, "any_id") != "本土罕见":
		push_error("resolve_world_familiarity: should prefer row value")
		return 1
	return 0


func _test_seed_starter_world_familiarity() -> int:
	var npc_db := {
		"npcs": {
			"hero": {
				"items": [
					{"id": "flashlight", "quantity": 1, "world_familiarity": "域外异物"},
					{"id": "copper_coin", "quantity": 10},
				],
			},
		},
	}
	var seeded: Dictionary = ItemDisplayCatalogScript.seed_starter_items_from_npcs(
		npc_db,
		{"items": {}},
	)
	var items: Variant = seeded.get("items", {})
	if not items is Dictionary:
		push_error("seed_starter: expected items dict")
		return 1
	var flash: Dictionary = (items as Dictionary).get("flashlight", {})
	if str(flash.get("world_familiarity", "")) != "域外异物":
		push_error("seed_starter: explicit world_familiarity not preserved")
		return 1
	var coin: Dictionary = (items as Dictionary).get("copper_coin", {})
	if str(coin.get("world_familiarity", "")) != "本土寻常":
		push_error("seed_starter: copper_coin should default to native")
		return 1
	return 0
