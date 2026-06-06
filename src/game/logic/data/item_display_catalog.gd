class_name ItemDisplayCatalog
extends RefCounted

const WORLD_FAMILIARITY_NATIVE := "本土寻常"
const WORLD_FAMILIARITY_RARE := "本土罕见"
const WORLD_FAMILIARITY_FOREIGN := "域外异物"

const VALID_WORLD_FAMILIARITY: Array[String] = [
	WORLD_FAMILIARITY_NATIVE,
	WORLD_FAMILIARITY_RARE,
	WORLD_FAMILIARITY_FOREIGN,
]

## 物品 id 片段暗示来自异世/现代/超前科技，种子入库时标为域外异物。
const FOREIGN_ITEM_ID_TOKENS: Array[String] = [
	"modern",
	"phone",
	"flashlight",
	"smartphone",
	"laptop",
	"tablet",
	"notebook",
	"pen",
	"lighter",
	"glasses",
	"plastic",
	"battery",
	"electric",
	"electronics",
	"foreign",
	"alien",
	"futuristic",
	"现代",
	"手机",
]

var _items: Dictionary = {}
var _weapons: Dictionary = {}


func load_from_runtime() -> void:
	var items_db: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.ITEMS_DB)
	var items_root: Dictionary = items_db if items_db is Dictionary else {}
	var items_val: Variant = items_root.get("items", {})
	_items = items_val if items_val is Dictionary else {}

	var weapon_db: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.WEAPON_DB)
	var weapon_root: Dictionary = weapon_db if weapon_db is Dictionary else {}
	var weapons_val: Variant = weapon_root.get("weapons", {})
	_weapons = weapons_val if weapons_val is Dictionary else {}


func bind_catalog(items: Dictionary, weapons: Dictionary = {}) -> void:
	_items = items if items is Dictionary else {}
	_weapons = weapons if weapons is Dictionary else {}


func resolve(item_id: String) -> Dictionary:
	var id := item_id.strip_edges()
	if id.is_empty():
		return {"id": "", "name": "未知", "desc": ""}
	var row: Variant = _items.get(id)
	if row == null:
		row = _weapons.get(id)
	if row is Dictionary:
		return _from_record(id, row as Dictionary)
	return {
		"id": id,
		"name": "未登记物品",
		"desc": "物品资料尚未入库（%s）" % id,
		"category": "",
	}


static func seed_starter_items_from_npcs(npc_db: Dictionary, items_db: Dictionary) -> Dictionary:
	return seed_starter_items_fallback(npc_db, items_db)


static func seed_starter_items_fallback(npc_db: Dictionary, items_db: Dictionary) -> Dictionary:
	var out: Dictionary = items_db.duplicate(true) if items_db is Dictionary else {"items": {}}
	var items: Variant = out.get("items", {})
	if not items is Dictionary:
		items = {}
		out["items"] = items
	var npcs: Variant = npc_db.get("npcs", {})
	if not npcs is Dictionary:
		return out
	for npc in (npcs as Dictionary).values():
		if not npc is Dictionary:
			continue
		var inv: Variant = (npc as Dictionary).get("items", [])
		if not inv is Array:
			continue
		for entry in inv:
			if not entry is Dictionary:
				continue
			var iid := str(entry.get("id", "")).strip_edges()
			if iid.is_empty() or (items as Dictionary).has(iid):
				continue
			var familiarity := normalize_world_familiarity(str(entry.get("world_familiarity", "")))
			if familiarity.is_empty():
				familiarity = infer_world_familiarity_from_id(iid)
			(items as Dictionary)[iid] = {
				"id": iid,
				"name": "",
				"description": "",
				"effect": "",
				"world_familiarity": familiarity,
			}
	return out


static func resolve_world_familiarity(row: Dictionary, item_id: String = "") -> String:
	var from_row := normalize_world_familiarity(str(row.get("world_familiarity", "")))
	if not from_row.is_empty():
		return from_row
	var iid := item_id.strip_edges()
	if iid.is_empty():
		iid = str(row.get("id", "")).strip_edges()
	return infer_world_familiarity_from_id(iid)


static func normalize_world_familiarity(value: String) -> String:
	var v := value.strip_edges()
	if v in VALID_WORLD_FAMILIARITY:
		return v
	return ""


static func infer_world_familiarity_from_id(item_id: String) -> String:
	var raw := item_id.strip_edges()
	if raw.is_empty():
		return WORLD_FAMILIARITY_NATIVE
	var s := raw.to_lower()
	for prefix in ["item_", "weapon_", "equip_"]:
		if s.begins_with(prefix):
			s = s.substr(prefix.length())
			raw = raw.substr(prefix.length())
			break
	for token in FOREIGN_ITEM_ID_TOKENS:
		if _foreign_token_matches(token, raw, s):
			return WORLD_FAMILIARITY_FOREIGN
	return WORLD_FAMILIARITY_NATIVE


static func _foreign_token_matches(token: String, raw: String, lowered: String) -> bool:
	if token.is_empty():
		return false
	for i in token.length():
		var code := token.unicode_at(i)
		if code >= 0x4E00:
			return raw.find(token) >= 0
	return lowered == token or lowered.find(token) >= 0


static func _from_record(id: String, row: Dictionary) -> Dictionary:
	var name := str(row.get("name", "")).strip_edges()
	if name.is_empty() or _name_is_unusable_display(name, id):
		name = "未命名物品"
	var desc := _build_tooltip(row)
	if desc.is_empty() and _looks_like_internal_item_id(id):
		desc = "物品 id：%s" % id
	return {
		"id": id,
		"name": name,
		"desc": desc,
		"category": str(row.get("category", "")).strip_edges(),
	}


static func _name_is_unusable_display(name: String, item_id: String) -> bool:
	var n := name.strip_edges()
	var iid := item_id.strip_edges()
	if n.is_empty() or iid.is_empty():
		return true
	if n.to_lower() == iid.to_lower():
		return true
	if n == humanize_item_id(iid) and _looks_like_internal_item_id(iid):
		return true
	return false


static func looks_like_internal_item_id(item_id: String) -> bool:
	return _looks_like_internal_item_id(item_id)


static func is_placeholder_record(row: Dictionary, item_id: String = "") -> bool:
	if row.is_empty():
		return true
	var iid := item_id.strip_edges()
	if iid.is_empty():
		iid = str(row.get("id", "")).strip_edges()
	var name := str(row.get("name", "")).strip_edges()
	if name.is_empty():
		return true
	if _name_is_unusable_display(name, iid):
		return true
	var desc := str(row.get("description", "")).strip_edges()
	var effect := str(row.get("effect", "")).strip_edges()
	var special := str(row.get("special_effect", "")).strip_edges()
	return desc.is_empty() and effect.is_empty() and special.is_empty()


static func _looks_like_internal_item_id(item_id: String) -> bool:
	var s := item_id.strip_edges()
	if s.is_empty():
		return false
	if s.begins_with("item_") or s.begins_with("weapon_") or s.begins_with("equip_"):
		return true
	if s.find("_") >= 0:
		return true
	return s.length() >= 10 and _is_ascii_letters_only(s)


static func _is_ascii_letters_only(s: String) -> bool:
	for i in s.length():
		var code := s.unicode_at(i)
		if not ((code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A)):
			return false
	return true


static func _build_tooltip(row: Dictionary) -> String:
	for key in ["effect", "description", "special_effect"]:
		var text := str(row.get(key, "")).strip_edges()
		if not text.is_empty():
			return text
	var parts: PackedStringArray = []
	for key in ["category", "rarity", "slot"]:
		var text := str(row.get(key, "")).strip_edges()
		if not text.is_empty():
			parts.append(text)
	return " · ".join(parts)


static func humanize_item_id(item_id: String) -> String:
	var s := item_id.strip_edges()
	if s.is_empty():
		return "未知"
	for prefix in ["item_", "weapon_", "equip_"]:
		if s.begins_with(prefix):
			s = s.substr(prefix.length())
			break
	const FALLBACK: Dictionary = {
		"modern_clothes": "现代衣物",
		"phone": "手机",
		"flashlight": "手电筒",
		"iodine_vial": "碘酊",
	}
	if FALLBACK.has(s):
		return str(FALLBACK[s])
	const TOKEN_ZH: Dictionary = {
		"modern": "现代",
		"clothes": "衣物",
		"phone": "手机",
		"flashlight": "手电筒",
		"medical": "医疗",
		"food": "食物",
		"water": "水",
		"knife": "刀",
		"gun": "枪",
		"armor": "护甲",
	}
	var tokens := s.split("_", false)
	var zh_parts: PackedStringArray = []
	for token in tokens:
		var t := str(token).strip_edges()
		if t.is_empty():
			continue
		if TOKEN_ZH.has(t):
			zh_parts.append(str(TOKEN_ZH[t]))
		else:
			zh_parts.append(t)
	if not zh_parts.is_empty():
		return "".join(zh_parts)
	return s.replace("_", " ")
