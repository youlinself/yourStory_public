class_name MapRegionDisplay
extends RefCounted

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const RichTextFormatScript := preload("res://src/ui/rich_text_format.gd")

## 地图区域字段纯文本 → BBCode（展示层，不写回存档）


static func escape_bbcode(text: String) -> String:
	return RichTextFormatScript.escape_bbcode(text)


static func format_overview(plain: String) -> String:
	var t := plain.strip_edges()
	if t.is_empty():
		return RichTextFormatScript.color_wrap(
			DesignTokensScript.MAP_PLACEHOLDER_HEX,
			"探索已解锁区域以查看详情。",
		)
	return RichTextFormatScript.color_wrap(
		DesignTokensScript.MAP_OVERVIEW_HEX,
		escape_bbcode(t),
	)


static func format_placeholder(message: String) -> String:
	return RichTextFormatScript.placeholder(message)


static func format_field_body(field_key: String, plain: String) -> String:
	var text := plain.strip_edges()
	if text.is_empty():
		return ""
	var escaped := escape_bbcode(text)
	var hex: String = DesignTokensScript.map_field_hex(field_key)
	return RichTextFormatScript.color_wrap(hex, escaped)
