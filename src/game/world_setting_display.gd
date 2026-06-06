class_name WorldSettingDisplay
extends RefCounted

## 将 world_setting.nature_env 中的长段落转为状态栏可用的简短文案。

const UI_MAX_LEN := 32
const HUD_LINE_MAX_LEN := 52
const HUD_LOCATION_MAX_LEN := 40
const KEYWORD_JOIN_MAX := 4

const _WEATHER_TERMS: Array[String] = [
	"酸雨", "灰霾", "暴雨", "暴雪", "大雪", "浓雾", "雾霾", "大风", "高温", "严寒",
	"潮湿", "高湿", "晴", "阴", "雨", "雪", "风", "雾", "霾",
]


static func clamp_hud_text(text: String, max_len: int = UI_MAX_LEN) -> String:
	var s := text.strip_edges()
	if s.is_empty() or s.length() <= max_len:
		return s
	return _trim_to_len(s, max_len)


static func format_weather(nature: Dictionary) -> String:
	return _format_from_nature(nature, "weather", "weather_keywords", "晴")


static func format_start_time(nature: Dictionary) -> String:
	var s := _format_from_nature(nature, "start_time", "start_time_keywords", "")
	return s if not s.is_empty() else _default_datetime()


static func compact_stored_display(
	stored: String,
	nature: Dictionary,
	text_key: String,
	keywords_key: String,
	default_value: String = "",
) -> String:
	var s := stored.strip_edges()
	if s.is_empty():
		return _format_from_nature(nature, text_key, keywords_key, default_value)

	var long_text := str(nature.get(text_key, "")).strip_edges()
	if not long_text.is_empty() and s == long_text:
		return _format_from_nature(nature, text_key, keywords_key, default_value)

	return _compact_display_text(s, text_key, default_value)


static func _compact_display_text(s: String, text_key: String, default_value: String = "") -> String:
	if s.length() <= UI_MAX_LEN:
		return s

	if " / " in s:
		var from_slashes := _compact_tag_list(s.split(" / ", false))
		if not from_slashes.is_empty():
			return from_slashes

	if text_key == "weather":
		var terms := _heuristic_weather(s)
		if not terms.is_empty():
			return clamp_hud_text(" / ".join(terms))
	if text_key == "start_time":
		var dt := _heuristic_start_time(s)
		if not dt.is_empty():
			return dt

	var trimmed := _trim_to_len(s, UI_MAX_LEN)
	return default_value if trimmed.is_empty() and not default_value.is_empty() else trimmed


static func _format_from_nature(
	nature: Dictionary,
	text_key: String,
	keywords_key: String,
	default_value: String,
) -> String:
	var kw := _join_keywords(nature.get(keywords_key, []))
	if not kw.is_empty():
		return clamp_hud_text(kw)

	var text := str(nature.get(text_key, "")).strip_edges()
	if text.is_empty():
		return default_value

	if text.length() <= UI_MAX_LEN:
		return text

	if " / " in text:
		var from_slashes := _compact_tag_list(text.split(" / ", false))
		if not from_slashes.is_empty():
			return from_slashes

	if text_key == "weather":
		var terms := _heuristic_weather(text)
		if not terms.is_empty():
			return " / ".join(terms)
	if text_key == "start_time":
		var dt := _heuristic_start_time(text)
		if not dt.is_empty():
			return dt

	return _trim_to_len(text, UI_MAX_LEN)


static func _join_keywords(raw: Variant, max_parts: int = KEYWORD_JOIN_MAX) -> String:
	if not raw is Array:
		return ""
	return _compact_tag_list(raw, max_parts)


static func _compact_tag_list(raw: Variant, max_parts: int = KEYWORD_JOIN_MAX) -> String:
	var parts: PackedStringArray = []
	for item in raw:
		if parts.size() >= max_parts:
			break
		var s := str(item).strip_edges()
		if not s.is_empty() and s not in parts:
			parts.append(s)
	if parts.is_empty():
		return ""
	return clamp_hud_text(" / ".join(parts))


static func _heuristic_weather(text: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for term in _WEATHER_TERMS:
		if term in text and term not in found:
			found.append(term)
		if found.size() >= 4:
			break
	return found


static func _heuristic_start_time(text: String) -> String:
	var parts: PackedStringArray = []

	var year := _first_regex(text, "(\\d{4})年")
	if not year.is_empty():
		parts.append(year)

	var has_season := false
	for season in ["深秋", "盛夏", "隆冬", "初春", "春季", "夏季", "秋季", "冬季"]:
		if season in text:
			parts.append(season)
			has_season = true
			break
	if not has_season:
		for season in ["春", "夏", "秋", "冬"]:
			if season in text:
				parts.append("%s季" % season)
				break

	var weekday := _first_regex(text, "周[一二三四五六日天]")
	if not weekday.is_empty():
		parts.append(weekday)

	var clock := _extract_clock_phrase(text)
	if not clock.is_empty():
		parts.append(clock)
	else:
		_append_time_period(parts, text)

	if parts.is_empty():
		return ""
	return " ".join(parts)


static func _append_time_period(parts: PackedStringArray, text: String) -> bool:
	for period in ["凌晨", "黎明", "清晨", "上午", "正午", "下午", "黄昏", "傍晚", "晚上", "深夜"]:
		if period in text:
			parts.append(period)
			return true
	return false


static func _extract_clock_phrase(text: String) -> String:
	var re := RegEx.new()
	if re.compile("(凌晨|清晨|黎明|上午|正午|下午|黄昏|傍晚|晚上|深夜)?(\\d{1,2})点(?:(\\d{1,2}))?分?") == OK:
		var m := re.search(text)
		if m != null:
			var period := m.get_string(1)
			var hour := int(m.get_string(2))
			var minute_str := m.get_string(3)
			var minute := int(minute_str) if not minute_str.is_empty() else 0
			if period.contains("下午") and hour < 12:
				hour += 12
			elif period.contains("上午") and hour == 12:
				hour = 0
			if minute > 0:
				return "%02d:%02d" % [hour, minute]
			return "%02d:00" % hour

	var cn_re := RegEx.new()
	if cn_re.compile("(凌晨|清晨|黎明|上午|正午|下午|黄昏|傍晚|晚上|深夜)?([零一二三四五六七八九十两]+)点([零一二三四五六七八九十两]+)?分?") != OK:
		return ""
	var cn_m := cn_re.search(text)
	if cn_m == null:
		return ""
	var cn_period := cn_m.get_string(1)
	var hour := _chinese_number(cn_m.get_string(2))
	var minute := _chinese_number(cn_m.get_string(3)) if not cn_m.get_string(3).is_empty() else 0
	if hour < 0:
		return ""
	if cn_period.contains("下午") and hour < 12:
		hour += 12
	elif cn_period.contains("上午") and hour == 12:
		hour = 0
	if minute > 0:
		return "%02d:%02d" % [hour, minute]
	return "%02d:00" % hour


static func _chinese_number(text: String) -> int:
	var s := text.strip_edges()
	if s.is_empty():
		return -1
	if s.is_valid_int():
		return int(s)
	if s == "十":
		return 10
	if s.begins_with("十"):
		return 10 + _chinese_digit(s.substr(1))
	if s.ends_with("十"):
		return _chinese_digit(s.substr(0, s.length() - 1)) * 10
	if "十" in s:
		var bits := s.split("十", false)
		if bits.size() == 2:
			var tens := _chinese_digit(bits[0]) if not bits[0].is_empty() else 1
			var ones := _chinese_digit(bits[1]) if not bits[1].is_empty() else 0
			return tens * 10 + ones
	return _chinese_digit(s)


static func _chinese_digit(c: String) -> int:
	match c:
		"零", "〇": return 0
		"一": return 1
		"二", "两": return 2
		"三": return 3
		"四": return 4
		"五": return 5
		"六": return 6
		"七": return 7
		"八": return 8
		"九": return 9
		_: return -1


static func _first_regex(text: String, pattern: String) -> String:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		return ""
	var m := re.search(text)
	if m == null:
		return ""
	return m.get_string()


static func _trim_to_len(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	var cut := text.substr(0, max_len)
	var period_idx := cut.rfind("。")
	if period_idx > 8:
		return cut.substr(0, period_idx)
	return cut + "…"


static func _default_datetime() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d.%02d.%02d" % [now.year, now.month, now.day]
