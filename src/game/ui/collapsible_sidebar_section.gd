extends RefCounted

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")

const INDENT_PX := 5
const COLLAPSED_ICON := "▸"
const EXPANDED_ICON := "▾"


static func wrap_with_left_margin(control: Control, margin_px: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if margin_px > 0:
		margin.add_theme_constant_override("margin_left", margin_px)
	margin.add_child(control)
	return margin


static func create(
	parent: VBoxContainer,
	title: String,
	depth: int,
	expanded: bool,
	header_kind: String,
	on_toggled: Callable,
) -> Dictionary:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var toggle_btn := Button.new()
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.custom_minimum_size = Vector2(22, 22)
	toggle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UiStylesScript.apply_chip_button(toggle_btn, false, DesignTokensScript.COLOR_BORDER_SUBTLE)
	toggle_btn.add_theme_font_size_override("font_size", DesignTokensScript.FONT_CAPTION)

	var title_label := Label.new()
	title_label.text = title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_apply_header_style(title_label, header_kind)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var apply_expanded := func(is_expanded: bool) -> void:
		body.visible = is_expanded
		toggle_btn.text = EXPANDED_ICON if is_expanded else COLLAPSED_ICON

	apply_expanded.call(expanded)

	toggle_btn.pressed.connect(func() -> void:
		var next := not body.visible
		apply_expanded.call(next)
		if on_toggled.is_valid():
			on_toggled.call(next)
	)

	header_row.add_child(toggle_btn)
	header_row.add_child(title_label)
	block.add_child(header_row)
	block.add_child(body)
	parent.add_child(wrap_with_left_margin(block, depth * INDENT_PX))

	return {
		"body": body,
		"set_expanded": apply_expanded,
	}


static func _apply_header_style(label: Label, kind: String) -> void:
	match kind:
		"success":
			UiStylesScript.style_hint_label(label, "success")
		"far":
			UiStylesScript.style_hint_label(label, "muted")
			label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_LOCATION_FAR)
		"mixed":
			UiStylesScript.style_hint_label(label, "accent")
		_:
			UiStylesScript.style_hint_label(label, "muted")
