## 地图区域富文本格式化（`godot --headless -s tests/map_region_display_test.gd`）
extends SceneTree


func _initialize() -> void:
	var failed := 0
	failed += _test_escape_bbcode()
	failed += _test_map_field_hex()
	failed += _test_format_field_plain("terrain", "平原、丘陵")
	failed += _test_format_field_plain("location", "城市中心偏东，靠近黄浦江")
	failed += _test_format_hazards_plain()
	if failed == 0:
		print("[OK] map_region_display tests passed")
	else:
		push_error("[FAIL] %d test(s) failed" % failed)
	quit(1 if failed > 0 else 0)


func _test_escape_bbcode() -> int:
	var out := MapRegionDisplay.escape_bbcode("a[b]c")
	if out != "a[lb]b[rb]c":
		push_error("escape_bbcode: expected bracket escapes")
		return 1
	return 0


func _test_map_field_hex() -> int:
	var hex := DesignTokens.map_field_hex("terrain")
	if hex != "#73a673":
		push_error("map_field_hex mismatch: %s" % hex)
		return 1
	return 0


func _test_format_field_plain(field_key: String, plain: String) -> int:
	var bb := MapRegionDisplay.format_field_body(field_key, plain)
	if "[u]" in bb or "[/u]" in bb or "[b]" in bb or "[/b]" in bb:
		push_error("%s: should not use bold or underline" % field_key)
		return 1
	if not bb.begins_with("[color=#"):
		push_error("%s: expected field color wrapper" % field_key)
		return 1
	return 0


func _test_format_hazards_plain() -> int:
	var bb := MapRegionDisplay.format_field_body("hazards", "瘴气、野兽")
	if "[b]" in bb or "[/b]" in bb:
		push_error("hazards: should not use bold")
		return 1
	if not bb.begins_with("[color=#"):
		push_error("hazards: expected field color wrapper")
		return 1
	return 0
