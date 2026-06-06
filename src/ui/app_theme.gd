class_name AppTheme
extends RefCounted

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")

static var _cached: Theme


static func get_theme() -> Theme:
	if _cached != null:
		return _cached
	_cached = _build_theme()
	return _cached


static func _build_theme() -> Theme:
	var theme := Theme.new()

	# 默认字体色
	theme.set_color("font_color", "Label", DesignTokensScript.COLOR_TEXT_PRIMARY)
	theme.set_color("font_color", "Button", DesignTokensScript.COLOR_TEXT_PRIMARY)
	theme.set_color("font_color", "LineEdit", DesignTokensScript.COLOR_TEXT_PRIMARY)
	theme.set_color("font_color", "TextEdit", DesignTokensScript.COLOR_TEXT_PRIMARY)
	theme.set_color("font_color", "RichTextLabel", DesignTokensScript.COLOR_TEXT_PRIMARY)

	theme.set_font_size("font_size", "Label", DesignTokensScript.FONT_BODY)
	theme.set_font_size("font_size", "Button", DesignTokensScript.FONT_BODY)
	theme.set_font_size("font_size", "LineEdit", DesignTokensScript.FONT_BODY)
	theme.set_font_size("font_size", "TextEdit", DesignTokensScript.FONT_BODY)

	# Panel
	theme.set_stylebox("panel", "PanelContainer", UiStylesScript.surface_stylebox())

	# Button 默认
	var btn_normal := UiStylesScript.surface_stylebox(
		DesignTokensScript.COLOR_SURFACE_RAISED,
		DesignTokensScript.COLOR_BORDER_SUBTLE,
		DesignTokensScript.RADIUS_SM,
		Vector4(14, 8, 14, 8),
	)
	theme.set_stylebox("normal", "Button", btn_normal)
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = btn_hover.bg_color.lightened(0.06)
	theme.set_stylebox("hover", "Button", btn_hover)
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = btn_pressed.bg_color.darkened(0.05)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_normal)

	# LineEdit
	var input := UiStylesScript.surface_stylebox(
		Color(0.1, 0.11, 0.14, 1.0),
		DesignTokensScript.COLOR_BORDER_SUBTLE,
		DesignTokensScript.RADIUS_SM,
		Vector4(10, 8, 10, 8),
	)
	theme.set_stylebox("normal", "LineEdit", input)
	theme.set_stylebox("focus", "LineEdit", input)
	theme.set_stylebox("normal", "TextEdit", input)
	theme.set_stylebox("focus", "TextEdit", input)

	# ItemList / ScrollBar
	UiStylesScript.configure_item_list_theme(theme)
	UiStylesScript.configure_scrollbar_theme(theme)

	# OptionButton
	theme.set_stylebox("normal", "OptionButton", btn_normal)

	UiStylesScript.configure_slider_theme(theme)

	# Separator
	var sep := StyleBoxLine.new()
	sep.color = DesignTokensScript.COLOR_BORDER_SUBTLE
	sep.thickness = 1
	theme.set_stylebox("separator", "HSeparator", sep)
	theme.set_stylebox("separator", "VSeparator", sep)

	return theme
