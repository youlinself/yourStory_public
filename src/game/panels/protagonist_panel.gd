extends Control

enum SubView { INFO, BACKPACK, SKILLS, ASSETS }

const SkillCatalog := preload("res://src/game/logic/data/skill_display_catalog.gd")
const ItemCatalog := preload("res://src/game/logic/data/item_display_catalog.gd")
const InfoBinder := preload("res://src/game/ui/character_profile_info_binder.gd")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")
const DesignTokensScript := preload("res://src/ui/design_tokens.gd")
const PLAYER_NAME_SUFFIX := "(你)"

@onready var _name_label: Label = %NameLabel
@onready var _info_body: RichTextLabel = %InfoBody
@onready var _psychology_block: Control = %PsychologyBlock
@onready var _psychology_rows: VBoxContainer = %PsychologyRows
@onready var _psychology_radar: Control = %PsychologyRadar
@onready var _abilities_block: Control = %AbilitiesBlock
@onready var _abilities_rows: VBoxContainer = %AbilitiesRows
@onready var _abilities_radar: Control = %AbilitiesRadar
@onready var _backpack_flow: FlowContainer = %BackpackFlow
@onready var _skills_flow: FlowContainer = %SkillsFlow
@onready var _adventure_section: Control = %AdventureSection
@onready var _adventure_card: RichTextLabel = %AdventureCard
@onready var _info_section: Control = %InfoSection
@onready var _backpack_section: Control = %BackpackSection
@onready var _skills_section: Control = %SkillsSection
@onready var _assets_section: Control = %AssetsSection
@onready var _wallet_label: Label = %WalletLabel
@onready var _currency_flow: FlowContainer = %CurrencyFlow
@onready var _key_items_flow: FlowContainer = %KeyItemsFlow

var _catalog: SkillCatalog
var _item_catalog: ItemCatalog
var _current_view: SubView = SubView.INFO
var _has_adventure_card: bool = false


func show_subview(view: SubView) -> void:
	_show_view(view)


func show_protagonist(
	mainrole: Dictionary,
	known_profile: Dictionary,
	skills_catalog: Dictionary,
	items_catalog: Dictionary,
	wallet: Dictionary = {},
	adventure_card_bbcode: String = "",
) -> void:
	_catalog = SkillCatalog.new()
	if skills_catalog.is_empty():
		_catalog.load_from_runtime()
	else:
		_catalog.bind_skills(skills_catalog)

	_item_catalog = ItemCatalog.new()
	if items_catalog.is_empty():
		_item_catalog.load_from_runtime()
	else:
		_item_catalog.bind_catalog(items_catalog)

	_name_label.text = format_protagonist_display_name(known_profile.get("name", ""))
	_render_adventure_card(adventure_card_bbcode)
	_render_info(known_profile)
	_render_backpack(mainrole)
	_render_assets(mainrole, wallet)
	var skill_ids: Variant = []
	if known_profile.has("skills"):
		skill_ids = known_profile.get("skills", [])
	_render_skills(skill_ids)
	_show_view(_current_view)


func _render_adventure_card(bbcode: String) -> void:
	if _adventure_card == null or _adventure_section == null:
		return
	var text := bbcode.strip_edges()
	_has_adventure_card = not text.is_empty()
	if _has_adventure_card:
		_adventure_card.text = text
		_adventure_card.add_theme_color_override(
			"default_color",
			DesignTokensScript.COLOR_TEXT_SECONDARY,
		)


func _show_view(view: SubView) -> void:
	_current_view = view
	_adventure_section.visible = _has_adventure_card and view == SubView.INFO
	_info_section.visible = view == SubView.INFO
	_backpack_section.visible = view == SubView.BACKPACK
	_skills_section.visible = view == SubView.SKILLS
	_assets_section.visible = view == SubView.ASSETS


func _render_info(known_profile: Dictionary) -> void:
	InfoBinder.bind(
		_info_body,
		_psychology_block,
		_psychology_rows,
		_psychology_radar,
		_abilities_block,
		_abilities_rows,
		_abilities_radar,
		known_profile,
	)


func _render_backpack(mainrole: Dictionary) -> void:
	for child in _backpack_flow.get_children():
		child.queue_free()
	var items: Variant = mainrole.get("items", [])
	if not items is Array or items.is_empty():
		_backpack_flow.add_child(_make_empty_hint("装备栏为空。"))
		return
	for entry in items:
		if not entry is Dictionary:
			continue
		var item_id := str(entry.get("id", "")).strip_edges()
		if item_id.is_empty():
			continue
		var qty := maxi(int(entry.get("quantity", 1)), 1)
		var info: Dictionary = _item_catalog.resolve(item_id)
		var display_name := "%s × %d" % [str(info.get("name", "未知")), qty]
		var tip := str(info.get("desc", "")).strip_edges()
		if tip.is_empty():
			tip = "暂无效果说明"
		_backpack_flow.add_child(_make_skill_tag(display_name, tip))


func _render_assets(mainrole: Dictionary, wallet: Dictionary) -> void:
	var normalized := RuntimeDbSchemas.normalize_wallet(wallet)
	var display := RuntimeDbSchemas.format_wallet_display(normalized)
	if display.is_empty():
		_wallet_label.text = "持金：暂无记录"
	else:
		_wallet_label.text = "持金：%s" % display

	_clear_flow(_currency_flow)
	_clear_flow(_key_items_flow)
	var items: Variant = mainrole.get("items", [])
	if not items is Array:
		items = []
	var has_currency := false
	var has_key := false
	for entry in items:
		if not entry is Dictionary:
			continue
		var item_id := str(entry.get("id", "")).strip_edges()
		if item_id.is_empty():
			continue
		var qty := maxi(int(entry.get("quantity", 1)), 1)
		var info: Dictionary = _item_catalog.resolve(item_id)
		var category := str(info.get("category", "")).strip_edges()
		var item_name := str(info.get("name", "未知"))
		var display_name := "%s × %d" % [item_name, qty]
		var tip := str(info.get("desc", "")).strip_edges()
		if tip.is_empty():
			tip = display_name
		if category == "货币":
			_currency_flow.add_child(_make_skill_tag(display_name, tip))
			has_currency = true
		elif _is_key_asset_item(item_id, item_name, category):
			_key_items_flow.add_child(_make_skill_tag(display_name, tip))
			has_key = true
	if not has_currency:
		_currency_flow.add_child(_make_empty_hint("无实物货币。"))
	if not has_key:
		_key_items_flow.add_child(_make_empty_hint("无地图或钥匙类持有物。"))


static func _is_key_asset_item(item_id: String, display_name: String, category: String) -> bool:
	if category == "关键" or category == "关键道具":
		return true
	var id_lower := item_id.to_lower()
	if id_lower.contains("map") or id_lower.contains("key"):
		return true
	if display_name.contains("地图") or display_name.contains("钥匙"):
		return true
	return false


func _render_skills(skill_ids: Variant) -> void:
	for child in _skills_flow.get_children():
		child.queue_free()
	if not skill_ids is Array or skill_ids.is_empty():
		return
	for raw_id in skill_ids:
		var skill_id := str(raw_id).strip_edges()
		if skill_id.is_empty():
			continue
		var info: Dictionary = _catalog.resolve(skill_id)
		_skills_flow.add_child(_make_skill_tag(str(info.get("name", "未知")), str(info.get("desc", ""))))


static func format_protagonist_display_name(raw_name: Variant) -> String:
	var base := SkillCatalog.format_player_visible(raw_name)
	if base == "未知":
		base = "主角"
	if base.ends_with(PLAYER_NAME_SUFFIX):
		return base
	return "%s%s" % [base, PLAYER_NAME_SUFFIX]


func _make_skill_tag(display_name: String, description: String) -> Control:
	var tip := description.strip_edges()
	if tip.is_empty():
		tip = display_name
	return UiStylesScript.make_skill_tag(display_name, tip)


func _make_empty_hint(text: String) -> Control:
	return UiStylesScript.make_empty_hint(text)


static func _clear_flow(flow: FlowContainer) -> void:
	for child in flow.get_children():
		child.queue_free()
