extends RefCounted

## 物品生成设定一致性：通用 Prompt 条文与入库前校验（初始化 + dynamic_add）。

const ItemDisplayCatalogScript := preload("res://src/game/logic/data/item_display_catalog.gd")

const SETTING_CONSISTENCY_BLURB := (
	"结合本次 novel_type 与已提供的世界设定、剧情/来源说明，生成与该题材、时代、科技水平"
	+ "及场景一致的物品；名称、描述、效果、world_familiarity 均不得偏离上述文本。"
	+ "若世界设定中未出现跨时代、异界或超前科技要素，则不得生成与之不符的物品。"
)

const ITEM_ID_FORMAT_HINT := "物品 id 建议使用小写英文与下划线，避免中英混写。"

## 世界设定文本中出现下列表述时，允许域外/跨时代物品（且宜标 world_familiarity 为域外异物）。
const SETTING_FOREIGN_ALLOW_KEYWORDS: Array[String] = [
	"穿越",
	"异世",
	"异界",
	"异世界",
	"超前",
	"未来",
	"赛博",
	"科幻",
	"时空",
	"重生",
	"系统流",
	"游戏入侵",
	"现代都市",
	"二十一世纪",
	"20世纪",
	"当代",
]

## 名称字段中的域外科技用语（程序启发式，非 Prompt 枚举题材）。
const FOREIGN_NAME_ZH_TOKENS: Array[String] = [
	"现代",
	"手机",
	"智能手机",
	"笔记本",
	"打火机",
	"眼镜",
	"钢笔",
	"圆珠笔",
]


static func setting_consistency_rule_blurb() -> String:
	return SETTING_CONSISTENCY_BLURB


static func item_id_format_hint() -> String:
	return ITEM_ID_FORMAT_HINT


static func build_setting_context(base_config: Dictionary) -> String:
	if base_config.is_empty():
		return ""
	var parts: PackedStringArray = []
	var novel_type := str(base_config.get("novel_type", "")).strip_edges()
	if not novel_type.is_empty():
		parts.append("novel_type: %s" % novel_type)
	var world_setting: Variant = base_config.get("world_setting", null)
	if world_setting is Dictionary:
		_flatten_dict_to_lines(world_setting as Dictionary, parts, 0)
	elif world_setting != null:
		parts.append(str(world_setting))
	return "\n".join(parts)


static func parse_base_config_from_world_context(world_context: String) -> Dictionary:
	var text := world_context.strip_edges()
	if text.is_empty():
		return parse_base_config_from_runtime()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return parse_base_config_from_runtime()


static func parse_base_config_from_runtime() -> Dictionary:
	var base: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.BASE_CONFIG)
	if base is Dictionary:
		return base as Dictionary
	return {}


static func validate_starter_items(npc: Dictionary, base_config: Dictionary) -> String:
	var inv: Variant = npc.get("items", [])
	if not inv is Array:
		return ""
	for entry in inv:
		if not entry is Dictionary:
			continue
		var err := validate_inventory_slot(entry as Dictionary, base_config)
		if not err.is_empty():
			return err
	return ""


static func validate_inventory_slot(entry: Dictionary, base_config: Dictionary) -> String:
	var item_id := str(entry.get("id", "")).strip_edges()
	if item_id.is_empty():
		return ""
	if item_id_has_mixed_script(item_id):
		return ITEM_ID_FORMAT_HINT

	var context := build_setting_context(base_config)
	var familiarity := ItemDisplayCatalogScript.normalize_world_familiarity(
		str(entry.get("world_familiarity", "")),
	)
	if familiarity.is_empty():
		familiarity = ItemDisplayCatalogScript.infer_world_familiarity_from_id(item_id)

	if not text_has_foreign_token(item_id):
		return ""

	var native_fam := ItemDisplayCatalogScript.WORLD_FAMILIARITY_NATIVE
	var rare_fam := ItemDisplayCatalogScript.WORLD_FAMILIARITY_RARE
	if familiarity == native_fam or familiarity == rare_fam:
		return "含跨时代或域外科技特征的物品不得标为%s或%s" % [native_fam, rare_fam]

	if not setting_allows_foreign_elements(context):
		return "物品与当前世界设定不一致（含跨时代/域外科技特征，但设定文本未体现异界或超前科技）"

	return ""


static func validate_item_record(record: Dictionary, base_config: Dictionary, _schema_id: String) -> String:
	var context := build_setting_context(base_config)
	return _validate_item_fields(record, context, "")


static func validate_loot_record(record: Dictionary, base_config: Dictionary, schema_id: String) -> String:
	return validate_item_record(record, base_config, schema_id)


static func setting_allows_foreign_elements(setting_context: String) -> bool:
	var ctx := setting_context.strip_edges()
	if ctx.is_empty():
		return false
	for kw in SETTING_FOREIGN_ALLOW_KEYWORDS:
		if ctx.find(kw) >= 0:
			return true
	return false


static func text_has_foreign_token(text: String) -> bool:
	var blob := text.strip_edges()
	if blob.is_empty():
		return false
	var lower := blob.to_lower()
	for token in ItemDisplayCatalogScript.FOREIGN_ITEM_ID_TOKENS:
		if lower.find(token) >= 0:
			return true
	for zh in FOREIGN_NAME_ZH_TOKENS:
		if blob.find(zh) >= 0:
			return true
	return false


static func item_id_has_mixed_script(item_id: String) -> bool:
	var s := item_id.strip_edges()
	if s.is_empty():
		return false
	var has_ascii_word := false
	var has_cjk := false
	for i in s.length():
		var code := s.unicode_at(i)
		if (code >= 0x4E00 and code <= 0x9FFF) or (code >= 0x3400 and code <= 0x4DBF):
			has_cjk = true
		elif (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A):
			has_ascii_word = true
	return has_cjk and has_ascii_word


static func _validate_item_fields(
	entry: Dictionary,
	setting_context: String,
	source_extra: String,
) -> String:
	var item_id := str(entry.get("id", "")).strip_edges()
	if item_id.is_empty():
		return ""

	if item_id_has_mixed_script(item_id):
		return ITEM_ID_FORMAT_HINT

	var name := str(entry.get("name", "")).strip_edges()
	if name.is_empty():
		return "物品缺少可读名称 name"
	if name.to_lower() == item_id.to_lower():
		return "物品 name 不得与 id 相同"
	if (
		ItemDisplayCatalogScript.looks_like_internal_item_id(item_id)
		and name == ItemDisplayCatalogScript.humanize_item_id(item_id)
	):
		return "物品须填写玩家可读的中文名称，不能仅使用 id 的机械拼接"
	var desc_parts: PackedStringArray = []
	for key in ["description", "effect", "special_effect"]:
		var t := str(entry.get(key, "")).strip_edges()
		if not t.is_empty():
			desc_parts.append(t)
	var desc := " ".join(desc_parts)
	var blob := "%s %s %s" % [item_id, name, desc]

	var familiarity := ItemDisplayCatalogScript.normalize_world_familiarity(
		str(entry.get("world_familiarity", "")),
	)
	if familiarity.is_empty():
		familiarity = ItemDisplayCatalogScript.infer_world_familiarity_from_id(item_id)

	if not text_has_foreign_token(blob):
		return ""

	var native_fam := ItemDisplayCatalogScript.WORLD_FAMILIARITY_NATIVE
	var rare_fam := ItemDisplayCatalogScript.WORLD_FAMILIARITY_RARE
	if familiarity == native_fam or familiarity == rare_fam:
		return "含跨时代或域外科技特征的物品不得标为%s或%s" % [native_fam, rare_fam]

	var full_context := setting_context
	var extra := source_extra.strip_edges()
	if not extra.is_empty():
		if full_context.is_empty():
			full_context = extra
		else:
			full_context += "\n" + extra

	if not setting_allows_foreign_elements(full_context):
		return "物品与当前世界设定不一致（含跨时代/域外科技特征，但设定文本未体现异界或超前科技）"

	return ""


static func _flatten_dict_to_lines(data: Dictionary, parts: PackedStringArray, depth: int) -> void:
	if depth > 4:
		return
	for key in data:
		var val: Variant = data[key]
		var label := str(key)
		if val is Dictionary:
			_flatten_dict_to_lines(val as Dictionary, parts, depth + 1)
		elif val is Array:
			for item in val:
				if item is Dictionary:
					_flatten_dict_to_lines(item as Dictionary, parts, depth + 1)
				else:
					var text := str(item).strip_edges()
					if not text.is_empty():
						parts.append(text)
		else:
			var text := str(val).strip_edges()
			if not text.is_empty() and text.length() < 500:
				parts.append("%s: %s" % [label, text])
