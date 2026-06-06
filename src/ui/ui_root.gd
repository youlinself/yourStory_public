class_name UiRoot
extends RefCounted

const AppThemeScript := preload("res://src/ui/app_theme.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")


## 为场景根节点挂载应用主题与全屏背景色
static func apply_to(root: Control) -> void:
	root.theme = AppThemeScript.get_theme()
	_ensure_background(root)


static func apply_menu_shell(root: Control, card: PanelContainer) -> void:
	apply_to(root)
	UiStylesScript.apply_panel_surface(card)


static func _ensure_background(root: Control) -> void:
	if root.get_node_or_null("UiBackground") != null:
		return
	var bg := ColorRect.new()
	bg.name = "UiBackground"
	bg.color = DesignTokensScript.COLOR_BG_ROOT
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	root.move_child(bg, 0)
