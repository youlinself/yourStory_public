class_name RichTextFormat
extends RefCounted

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

static var _untrusted_bbcode_re: RegEx


static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


static func color_wrap(hex: String, inner_bbcode: String) -> String:
	return "[color=%s]%s[/color]" % [hex, inner_bbcode]


static func placeholder(message: String) -> String:
	return color_wrap(DesignTokensScript.MAP_PLACEHOLDER_HEX, escape_bbcode(message))


static func bold_label_line(label: String, value: String) -> String:
	return "[b]%s[/b]：%s" % [escape_bbcode(label), escape_bbcode(value)]


static func dialogue_prefix_line(prefix: String, dialogue: String, hex: String) -> String:
	return "%s：「%s」" % [
		color_wrap(hex, escape_bbcode(prefix)),
		escape_bbcode(dialogue),
	]


## 移除不可信来源中的 BBCode 标签（大小写不敏感），保留正文。
static func strip_untrusted_bbcode(text: String) -> String:
	if text.is_empty():
		return ""
	var re := _untrusted_bbcode_regex()
	var out := text
	while true:
		var next := re.sub(out, "", true)
		if next == out:
			break
		out = next
	return out


## 先剥离伪 BBCode，再转义方括号，供剧情/存档文本安全展示。
static func sanitize_plain_text(text: String) -> String:
	return escape_bbcode(strip_untrusted_bbcode(text))


## 展示层单次转义：先还原历史双重 [lb]/[rb]，再 strip + escape。
static func sanitize_plain_text_once(text: String) -> String:
	var decoded := text.replace("[lb]", "[").replace("[rb]", "]")
	return escape_bbcode(strip_untrusted_bbcode(decoded))


static func _untrusted_bbcode_regex() -> RegEx:
	if _untrusted_bbcode_re == null:
		_untrusted_bbcode_re = RegEx.new()
		_untrusted_bbcode_re.compile(
			"(?i)\\[\\s*/?\\s*(color|b|i|u|font|img|center|right|left|fill|indent|url|pulse|wave|tornado|rainbow|shader|table|cell|fgcolor|bgcolor)(?:\\s*=[^\\]]*)?\\s*\\]"
		)
	return _untrusted_bbcode_re
