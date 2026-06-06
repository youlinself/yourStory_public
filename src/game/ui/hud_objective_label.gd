extends Label

const META_TOOLTIP_FULL := &"_hud_objective_tooltip_full"


func queue_tooltip_sync(full_text: String) -> void:
	set_meta(META_TOOLTIP_FULL, full_text)
	call_deferred("_apply_tooltip_sync")


func _apply_tooltip_sync() -> void:
	var full := str(get_meta(META_TOOLTIP_FULL, ""))
	tooltip_text = full if _is_text_overflowing(full) else ""


func _is_text_overflowing(full_text: String) -> bool:
	if full_text.is_empty() or size.x <= 1.0:
		return false
	var font := get_theme_font(&"font")
	if font == null:
		font = ThemeDB.fallback_font
	var font_size := get_theme_font_size(&"font_size")
	if font_size <= 0:
		font_size = ThemeDB.fallback_font_size
	var text_width := font.get_string_size(
		full_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
	).x
	return text_width > size.x - 1.0
