extends Control

const UiRootScript := preload("res://src/ui/ui_root.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

var _controller: GameSessionController


func _ready() -> void:
	UiRootScript.apply_to(self)
	_apply_game_chrome()
	_controller = GameSessionController.new()
	add_child(_controller)
	_controller.setup(self)
	var back_btn := get_node_or_null("%BackButton") as Button
	if back_btn == null:
		back_btn = find_child("BackButton", true, false) as Button
	if back_btn:
		back_btn.pressed.connect(_on_back_pressed)


func _apply_game_chrome() -> void:
	for panel_path in [
		"RootVBox/TopRow/StatusPanel",
		"RootVBox/TopRow/NavPanel",
		"RootVBox/BodyRow/StoryPanel",
		"RootVBox/BodyRow/DataRow/SidebarPanel",
		"RootVBox/BodyRow/DataRow/ContentPanel",
	]:
		var panel := get_node_or_null(panel_path) as PanelContainer
		if panel:
			UiStylesScript.apply_panel_surface(panel)

	var story_log := get_node_or_null("%StoryLog") as RichTextLabel
	if story_log:
		UiStylesScript.configure_rich_body(story_log)
	UiStylesScript.apply_primary_button(get_node_or_null("%StorySendButton") as Button)

	for nav_name in [
		"CharactersNavButton",
		"RelationshipsNavButton",
		"SceneCharactersNavButton",
		"MapNavButton",
		"EventsNavButton",
	]:
		UiStylesScript.apply_nav_toggle(get_node_or_null("%%%s" % nav_name) as Button)
	var back_btn := get_node_or_null("%BackButton") as Button
	UiStylesScript.apply_secondary_button(back_btn)
	UiStylesScript.apply_top_nav_button_layout(back_btn)

	var date_label := get_node_or_null("%DateWeatherLabel") as Label
	if date_label:
		date_label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_SECTION)
	var loc_label := get_node_or_null("%LocationLabel") as Label
	if loc_label:
		loc_label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_BODY)
	var wallet_label := get_node_or_null("%WalletLabel") as Label
	if wallet_label:
		wallet_label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_BODY)
		wallet_label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_WALLET)
	var objective_label := get_node_or_null("%ObjectiveLabel") as Label
	if objective_label:
		objective_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		objective_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		objective_label.clip_text = true
		objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		objective_label.add_theme_font_size_override("font_size", DesignTokensScript.FONT_BODY_SM)
	UiStylesScript.style_hint_label(get_node_or_null("%SessionMetaLabel") as Label, "accent")
	UiStylesScript.style_hint_label(get_node_or_null("%StoryStatusLabel") as Label, "muted")

	var cmd_panel := %CommandMenuPanel as PanelContainer
	if cmd_panel:
		UiStylesScript.apply_panel_surface(cmd_panel)
	var cmd_list := %CommandList as ItemList
	if cmd_list:
		UiStylesScript.apply_item_list(cmd_list, true)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://sences/main_menu/main_menu.tscn")
