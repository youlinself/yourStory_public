extends Control

const SkillCatalog := preload("res://src/game/logic/data/skill_display_catalog.gd")
const InfoBinder := preload("res://src/game/ui/character_profile_info_binder.gd")
const TrpgUiDisplayScript := preload("res://src/game/logic/data/trpg_ui_display.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

@onready var _name_label: Label = %NameLabel
@onready var _location_label: Label = %LocationLabel
@onready var _favorability_label: Label = %FavorabilityLabel
@onready var _body_label: RichTextLabel = %BodyLabel
@onready var _psychology_block: Control = %PsychologyBlock
@onready var _psychology_rows: VBoxContainer = %PsychologyRows
@onready var _psychology_radar: Control = %PsychologyRadar
@onready var _abilities_block: Control = %AbilitiesBlock
@onready var _abilities_rows: VBoxContainer = %AbilitiesRows
@onready var _abilities_radar: Control = %AbilitiesRadar
@onready var _skills_flow: FlowContainer = %SkillsFlow


func show_npc(
	known_profile: Dictionary,
	skills_catalog: Dictionary = {},
	location_path: String = "",
	is_at_same_place: bool = true,
	favorability: int = 0,
) -> void:
	_clear_skill_tags()

	if known_profile.is_empty():
		_name_label.text = "未选择角色"
		_set_location_line("", true)
		if _favorability_label:
			_favorability_label.visible = false
		_body_label.text = ""
		_hide_stat_blocks()
		return

	var catalog: SkillCatalog = SkillCatalog.new()
	if skills_catalog.is_empty():
		catalog.load_from_runtime()
	else:
		catalog.bind_skills(skills_catalog)

	_name_label.text = SkillCatalog.format_player_visible(known_profile.get("name", ""))
	if _name_label.text == "未知":
		_name_label.text = "未命名角色"
	_set_location_line(location_path, is_at_same_place)
	_set_favorability_line(favorability)

	InfoBinder.bind(
		_body_label,
		_psychology_block,
		_psychology_rows,
		_psychology_radar,
		_abilities_block,
		_abilities_rows,
		_abilities_radar,
		known_profile,
	)

	if known_profile.has("skills"):
		var skills: Variant = known_profile.get("skills", [])
		if skills is Array and not skills.is_empty():
			_build_skill_tags(skills, catalog)


func _set_location_line(location_path: String, is_at_same_place: bool) -> void:
	if _location_label == null:
		return
	var path := location_path.strip_edges()
	if path.is_empty():
		_location_label.visible = false
		_location_label.text = ""
		return
	_location_label.visible = true
	if is_at_same_place:
		_location_label.text = "所在：%s（同处）" % path
		_location_label.add_theme_color_override("font_color", Color(0.55, 0.82, 0.62))
	else:
		_location_label.text = "所在：%s" % path
		_location_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.55))


func _set_favorability_line(value: int) -> void:
	if _favorability_label == null:
		return
	_favorability_label.visible = true
	_favorability_label.text = TrpgUiDisplayScript.format_npc_favorability(value)
	if value > 0:
		_favorability_label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_SUCCESS)
	elif value < 0:
		_favorability_label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_ERROR)
	else:
		_favorability_label.add_theme_color_override("font_color", DesignTokensScript.COLOR_TEXT_MUTED)


func _hide_stat_blocks() -> void:
	_psychology_block.visible = false
	_abilities_block.visible = false


func _clear_skill_tags() -> void:
	if _skills_flow == null:
		return
	for child in _skills_flow.get_children():
		child.queue_free()


func _build_skill_tags(skill_ids: Array, catalog: SkillCatalog) -> void:
	for raw_id in skill_ids:
		var skill_id := str(raw_id).strip_edges()
		if skill_id.is_empty():
			continue
		var info: Dictionary = catalog.resolve(skill_id)
		var tag := _make_skill_tag(str(info.get("name", "未知")), str(info.get("desc", "")))
		_skills_flow.add_child(tag)


func _make_skill_tag(display_name: String, description: String) -> Control:
	var tip := description.strip_edges()
	if tip.is_empty():
		tip = display_name
	return UiStylesScript.make_skill_tag(display_name, tip)
