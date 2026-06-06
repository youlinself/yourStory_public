class_name UiStyles
extends RefCounted

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")


static func surface_stylebox(
	bg: Color = DesignTokensScript.COLOR_SURFACE,
	border: Color = DesignTokensScript.COLOR_BORDER,
	radius: int = DesignTokensScript.RADIUS_MD,
	margin: Vector4 = Vector4(12, 10, 12, 10),
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin.x
	style.content_margin_top = margin.y
	style.content_margin_right = margin.z
	style.content_margin_bottom = margin.w
	return style


static func card_stylebox(accent: Color = DesignTokensScript.COLOR_BORDER) -> StyleBoxFlat:
	var style := surface_stylebox(
		DesignTokensScript.COLOR_SURFACE_CARD,
		Color(accent.r, accent.g, accent.b, 0.35),
		DesignTokensScript.RADIUS_MD,
		Vector4(14, 12, 14, 12),
	)
	return style


static func chip_stylebox(is_selected: bool, accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if is_selected:
		style.bg_color = Color(0.18, 0.24, 0.3, 1.0)
		style.border_color = Color(accent.r, accent.g, accent.b, 0.95)
	else:
		style.bg_color = Color(0.15, 0.16, 0.2, 1.0)
		style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(DesignTokensScript.RADIUS_SM)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func apply_chip_button(btn: Button, is_selected: bool, accent: Color) -> void:
	if btn == null:
		return
	var normal := chip_stylebox(is_selected, accent)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = hover.bg_color.lightened(0.08)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = pressed.bg_color.darkened(0.06)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_font_size_override("font_size", DesignTokensScript.FONT_CHIP)
	if is_selected:
		btn.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(0.9, 0.96, 1.0))
	else:
		btn.add_theme_color_override("font_color", Color(0.82, 0.8, 0.72))
		btn.add_theme_color_override("font_hover_color", Color(0.92, 0.9, 0.82))


static func apply_sidebar_toggle(btn: Button, is_current_location: bool = false) -> void:
	if btn == null:
		return
	var unselected := chip_stylebox(false, DesignTokensScript.COLOR_CHIP_NEUTRAL)
	btn.add_theme_stylebox_override("normal", unselected)
	var hover_unselected := unselected.duplicate() as StyleBoxFlat
	hover_unselected.bg_color = hover_unselected.bg_color.lightened(0.08)
	btn.add_theme_stylebox_override("hover", hover_unselected)

	var selected := chip_stylebox(true, DesignTokensScript.MAP_SIDEBAR_CURRENT_BORDER)
	selected.bg_color = DesignTokensScript.MAP_SIDEBAR_CURRENT_FILL
	btn.add_theme_stylebox_override("pressed", selected)
	btn.add_theme_stylebox_override("focus", selected)
	var hover_selected := selected.duplicate() as StyleBoxFlat
	hover_selected.bg_color = hover_selected.bg_color.lightened(0.08)
	btn.add_theme_stylebox_override("hover_pressed", hover_selected)

	btn.add_theme_font_size_override("font_size", DesignTokensScript.FONT_CHIP)
	var unselected_font := (
		DesignTokensScript.COLOR_TEXT_ACCENT
		if is_current_location
		else DesignTokensScript.COLOR_TEXT_PRIMARY
	)
	btn.add_theme_color_override("font_color", unselected_font)
	btn.add_theme_color_override(
		"font_hover_color",
		unselected_font.lightened(0.1) if is_current_location else DesignTokensScript.COLOR_TEXT_PRIMARY,
	)
	btn.add_theme_color_override("font_pressed_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_pressed_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func apply_primary_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := surface_stylebox(
		Color(0.22, 0.32, 0.48, 1.0),
		Color(DesignTokensScript.COLOR_ACCENT.r, DesignTokensScript.COLOR_ACCENT.g, DesignTokensScript.COLOR_ACCENT.b, 0.9),
		DesignTokensScript.RADIUS_SM,
		Vector4(16, 10, 16, 10),
	)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.26, 0.38, 0.55, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.18, 0.28, 0.42, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	btn.add_theme_font_size_override("font_size", DesignTokensScript.FONT_BODY)


static func apply_secondary_button(btn: Button) -> void:
	if btn == null:
		return
	apply_chip_button(btn, false, DesignTokensScript.COLOR_BORDER)


static func apply_nav_toggle(btn: Button) -> void:
	if btn == null:
		return
	btn.toggle_mode = true
	var off := chip_stylebox(false, DesignTokensScript.COLOR_BORDER_SUBTLE)
	btn.add_theme_stylebox_override("normal", off)
	var hover := off.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.2, 0.26, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	var on := chip_stylebox(true, DesignTokensScript.COLOR_ACCENT)
	btn.add_theme_stylebox_override("pressed", on)
	btn.add_theme_stylebox_override("focus", on)
	btn.add_theme_font_size_override("font_size", DesignTokensScript.FONT_BODY_SM)
	btn.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_SECONDARY)
	btn.add_theme_color_override("font_hover_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	apply_top_nav_button_layout(btn)


static func apply_top_nav_button_layout(btn: Button) -> void:
	if btn == null:
		return
	var min_sz := btn.custom_minimum_size
	min_sz.y = DesignTokensScript.NAV_BUTTON_HEIGHT
	btn.custom_minimum_size = min_sz
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := btn.text.strip_edges()
	btn.tooltip_text = label


static func apply_panel_surface(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", surface_stylebox())


static func item_list_panel_stylebox(embedded_in_panel: bool = false) -> StyleBox:
	if embedded_in_panel:
		return StyleBoxEmpty.new()
	return surface_stylebox(
		DesignTokensScript.COLOR_SURFACE_RAISED,
		DesignTokensScript.COLOR_BORDER_SUBTLE,
		DesignTokensScript.RADIUS_SM,
		Vector4(4, 4, 4, 4),
	)


static func item_list_row_stylebox(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(DesignTokensScript.RADIUS_SM)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


static func item_list_guide_stylebox() -> StyleBoxLine:
	var guide := StyleBoxLine.new()
	guide.color = DesignTokensScript.COLOR_BORDER_SUBTLE
	guide.thickness = 1
	guide.vertical = false
	return guide


static func configure_item_list_theme(theme: Theme, embedded_panel: bool = false) -> void:
	var selected := item_list_row_stylebox(Color(0.18, 0.24, 0.32, 1.0))
	var hovered := item_list_row_stylebox(Color(0.15, 0.19, 0.25, 1.0))
	var hovered_sel := item_list_row_stylebox(Color(0.2, 0.28, 0.36, 1.0))
	theme.set_stylebox("panel", "ItemList", item_list_panel_stylebox(embedded_panel))
	theme.set_stylebox("selected", "ItemList", selected)
	theme.set_stylebox("selected_focus", "ItemList", selected)
	theme.set_stylebox("hovered", "ItemList", hovered)
	theme.set_stylebox("hovered_selected", "ItemList", hovered_sel)
	theme.set_stylebox("hovered_selected_focus", "ItemList", hovered_sel)
	theme.set_stylebox("guide", "ItemList", item_list_guide_stylebox())
	theme.set_color("font_color", "ItemList", DesignTokensScript.COLOR_TEXT_PRIMARY)
	theme.set_color("font_selected_color", "ItemList", Color(0.82, 0.92, 1.0))
	theme.set_color("font_hovered_color", "ItemList", DesignTokensScript.COLOR_TEXT_PRIMARY)
	theme.set_color("font_disabled_color", "ItemList", DesignTokensScript.COLOR_TEXT_MUTED)
	theme.set_font_size("font_size", "ItemList", DesignTokensScript.FONT_BODY_SM)


static func slider_track_stylebox() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.15, 0.19, 1.0)
	style.border_color = DesignTokensScript.COLOR_BORDER_SUBTLE
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


static func slider_grabber_stylebox(accent: Color = DesignTokensScript.COLOR_ACCENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_corner_radius_all(8)
	style.content_margin_left = -7
	style.content_margin_right = -7
	style.content_margin_top = -7
	style.content_margin_bottom = -7
	return style


static func configure_slider_theme(theme: Theme) -> void:
	var track := slider_track_stylebox()
	var grabber := slider_grabber_stylebox()
	var grabber_hl := slider_grabber_stylebox(DesignTokensScript.COLOR_ACCENT_HOVER)
	var grabber_disabled := slider_grabber_stylebox(DesignTokensScript.COLOR_TEXT_MUTED)
	for slider_type in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", slider_type, track)
		theme.set_stylebox("grabber", slider_type, grabber)
		theme.set_stylebox("grabber_highlight", slider_type, grabber_hl)
		theme.set_stylebox("grabber_disabled", slider_type, grabber_disabled)


static func configure_scrollbar_theme(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.09, 0.12, 0.6)
	track.set_corner_radius_all(3)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.32, 0.36, 0.44, 0.9)
	grabber.set_corner_radius_all(3)
	var grabber_hl := grabber.duplicate() as StyleBoxFlat
	grabber_hl.bg_color = Color(0.4, 0.45, 0.55, 1.0)
	for bar_type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", bar_type, track)
		theme.set_stylebox("scroll_focus", bar_type, track)
		theme.set_stylebox("grabber", bar_type, grabber)
		theme.set_stylebox("grabber_highlight", bar_type, grabber_hl)
		theme.set_stylebox("grabber_pressed", bar_type, grabber_hl)


static func apply_item_list(list: ItemList, embedded_in_panel: bool = false) -> void:
	if list == null:
		return
	var selected := item_list_row_stylebox(Color(0.18, 0.24, 0.32, 1.0))
	var hovered := item_list_row_stylebox(Color(0.15, 0.19, 0.25, 1.0))
	var hovered_sel := item_list_row_stylebox(Color(0.2, 0.28, 0.36, 1.0))
	list.add_theme_stylebox_override("panel", item_list_panel_stylebox(embedded_in_panel))
	list.add_theme_stylebox_override("selected", selected)
	list.add_theme_stylebox_override("selected_focus", selected)
	list.add_theme_stylebox_override("hovered", hovered)
	list.add_theme_stylebox_override("hovered_selected", hovered_sel)
	list.add_theme_stylebox_override("hovered_selected_focus", hovered_sel)
	list.add_theme_stylebox_override("guide", item_list_guide_stylebox())
	list.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	list.add_theme_color_override("font_selected_color", Color(0.82, 0.92, 1.0))
	list.add_theme_color_override("font_hovered_color", DesignTokensScript.COLOR_TEXT_PRIMARY)
	list.add_theme_color_override("font_disabled_color", DesignTokensScript.COLOR_TEXT_MUTED)
	list.add_theme_font_size_override("font_size", DesignTokensScript.FONT_BODY_SM)


static func configure_rich_body(label: RichTextLabel) -> void:
	if label == null:
		return
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("default_color", DesignTokensScript.COLOR_TEXT_PRIMARY)


static func style_hint_label(label: Label, kind: String = "muted") -> void:
	if label == null:
		return
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_CAPTION)
	match kind:
		"error":
			label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_ERROR)
		"accent":
			label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_ACCENT)
		"success":
			label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_SUCCESS)
		_:
			label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_HINT)


static func make_hint_panel(text: String, kind: String = "accent") -> PanelContainer:
	var panel := PanelContainer.new()
	var style := surface_stylebox(
		DesignTokensScript.COLOR_SURFACE_RAISED,
		DesignTokensScript.COLOR_BORDER_SUBTLE,
		DesignTokensScript.RADIUS_SM,
		Vector4(10, 8, 10, 8),
	)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_hint_label(label, kind)
	panel.add_child(label)
	return panel


static func make_skill_tag(text: String, tooltip: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.tooltip_text = tooltip
	panel.add_theme_stylebox_override("panel", card_stylebox(DesignTokensScript.COLOR_BORDER_SUBTLE))
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_CAPTION)
	label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_SECONDARY)
	panel.add_child(label)
	return panel


static func make_suggestion_chip(text: String, on_pressed: Callable, disabled: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = disabled
	btn.pressed.connect(on_pressed)
	apply_chip_button(btn, false, DesignTokensScript.COLOR_CHIP_ACTION)
	return btn


static func make_action_suggestion_chip(text: String, on_pressed: Callable, disabled: bool = false) -> Button:
	return make_suggestion_chip(text, on_pressed, disabled)


static func make_empty_hint(text: String) -> Control:
	# 置于 FlowContainer 时需占满行宽，否则 autowrap 会按一字宽竖排。
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_hint_label(label, "muted")
	row.add_child(label)
	return row
