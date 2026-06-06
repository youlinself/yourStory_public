class_name PlayerCommandResolver
extends RefCounted

const SkillCatalog := preload("res://src/game/logic/data/skill_display_catalog.gd")
const PlayerCommandArgCompleter := preload("res://src/game/logic/input/player_command_arg_completer.gd")

var _registry := PlayerCommandRegistry.new()


func _init() -> void:
	_registry.load_registry()


func get_registry() -> PlayerCommandRegistry:
	return _registry


func build_arg_completion_entries(line_text: String, read_model: GameReadModel) -> Dictionary:
	return PlayerCommandArgCompleter.try_build_entries(line_text, _registry, read_model)


func resolve(text: String, read_model: GameReadModel) -> Dictionary:
	var raw := text.strip_edges()
	if not raw.begins_with("/"):
		return {"ok": false, "error": "不是斜杠命令", "expanded": ""}

	var body := raw.substr(1).strip_edges()
	if body.is_empty():
		return {"ok": false, "error": "请输入命令，例如 /观察", "expanded": ""}

	var parts := body.split(" ", false, 1)
	var cmd_token := parts[0].strip_edges()
	var arg_text := parts[1].strip_edges() if parts.size() > 1 else ""

	var cmd := _registry.find_command(cmd_token)
	if cmd.is_empty():
		return {"ok": false, "error": "未知命令：/%s" % cmd_token, "expanded": ""}

	var vars := _resolve_args(cmd, arg_text, read_model)
	if vars.has("error"):
		return {"ok": false, "error": str(vars["error"]), "expanded": ""}

	var template := str(cmd.get("template", "")).strip_edges()
	if template.is_empty():
		return {"ok": false, "error": "命令缺少 template", "expanded": ""}

	var expanded := _apply_template(template, vars)
	expanded = _cleanup_expanded(expanded)
	if expanded.is_empty():
		return {"ok": false, "error": "命令展开失败", "expanded": ""}

	var talk_npc_id := ""
	if str(cmd.get("id", "")).strip_edges() == "talk":
		talk_npc_id = str(vars.get("npc", "")).strip_edges()

	return {"ok": true, "expanded": expanded, "error": "", "talk_npc_id": talk_npc_id}


func _resolve_args(cmd: Dictionary, arg_text: String, read_model: GameReadModel) -> Dictionary:
	var vars: Dictionary = {}
	var defaults: Variant = cmd.get("defaults", {})
	if defaults is Dictionary:
		for key in defaults:
			vars[str(key)] = str(defaults[key])

	var args: Variant = cmd.get("args", [])
	if not args is Array:
		return vars

	var arg_defs: Array = args
	var positional: Array[String] = _split_positional_args(arg_text, arg_defs.size())

	for i in range(arg_defs.size()):
		var def: Dictionary = arg_defs[i] if arg_defs[i] is Dictionary else {}
		var name := str(def.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		var value: String = positional[i] if i < positional.size() else ""
		if value.is_empty() and vars.has(name):
			value = str(vars[name])
		var required := bool(def.get("required", false))
		if value.is_empty() and required:
			var ph := str(def.get("placeholder", name))
			return {"error": "请提供参数：%s" % ph}

		var resolver := str(def.get("resolver", "")).strip_edges()
		if not value.is_empty() and not resolver.is_empty():
			var resolved := _run_resolver(resolver, value, read_model)
			if resolved.has("error"):
				return resolved
			for k in resolved:
				if k != "error":
					vars[k] = resolved[k]
		elif not value.is_empty():
			vars[name] = value

	_apply_tail_template_parts(str(cmd.get("id", "")).strip_edges(), vars)
	return vars


func _run_resolver(resolver_id: String, value: String, read_model: GameReadModel) -> Dictionary:
	match resolver_id:
		"nearby_npc":
			return _resolve_nearby_npc(value, read_model)
		"protagonist_skill":
			return _resolve_protagonist_skill(value, read_model)
		"unlocked_region":
			return _resolve_unlocked_region(value, read_model)
		_:
			return {"error": "未知 resolver: %s" % resolver_id}


func _resolve_nearby_npc(value: String, read_model: GameReadModel) -> Dictionary:
	var needle := value.strip_edges()
	if needle.is_empty():
		return {"error": "请指定要对话的对象"}
	for npc in read_model.get_interactable_npcs():
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		if nid == needle or nid.to_lower() == needle.to_lower():
			return {
				"npc": nid,
				"npc_name": read_model.get_known_display_name(nid, str(npc.get("name", nid))),
			}
		var display := read_model.get_known_display_name(nid, "")
		if display == needle or display.find(needle) >= 0:
			return {"npc": nid, "npc_name": display}
	var names: PackedStringArray = []
	for npc in read_model.get_interactable_npcs():
		names.append(read_model.get_known_display_name(str(npc.get("id", "")), "?"))
	return {
		"error": "附近找不到「%s」。可选：%s" % [
			needle,
			"、".join(names) if not names.is_empty() else "（无人）",
		],
	}


func _resolve_protagonist_skill(value: String, read_model: GameReadModel) -> Dictionary:
	var needle := value.strip_edges()
	if needle.is_empty():
		return {"error": "请指定技能"}
	var catalog := SkillCatalog.new()
	catalog.bind_skills(read_model.get_skills_catalog())
	var known := read_model.get_known_protagonist_profile()
	var skill_ids: Variant = known.get("skills", [])
	if not skill_ids is Array:
		return {"error": "尚未掌握可用技能"}
	for sid in skill_ids:
		var id_str := str(sid).strip_edges()
		if id_str.is_empty():
			continue
		var row := catalog.resolve(id_str)
		var sname := str(row.get("name", ""))
		if id_str == needle or id_str.to_lower() == needle.to_lower():
			return {"skill": id_str, "skill_name": sname}
		if sname == needle or sname.find(needle) >= 0:
			return {"skill": id_str, "skill_name": sname}
	return {"error": "未掌握技能「%s」" % needle}


func _resolve_unlocked_region(value: String, read_model: GameReadModel) -> Dictionary:
	var needle := value.strip_edges()
	if needle.is_empty():
		return {"error": "请指定目的地"}
	var current := str(read_model.mainrole.get("current_region_id", "")).strip_edges()
	for region in read_model.get_unlocked_regions():
		var rid := str(region.get("id", "")).strip_edges()
		var rname := str(region.get("name", rid)).strip_edges()
		if rid.is_empty():
			continue
		if rid == current:
			continue
		if rid == needle or rname == needle or rname.find(needle) >= 0:
			return {"region": rid, "region_name": rname}
	var names: PackedStringArray = []
	for region in read_model.get_unlocked_regions():
		var rid := str(region.get("id", "")).strip_edges()
		if rid != current:
			names.append(str(region.get("name", rid)))
	var hint := "该地点尚未入库，请用自然语言描述行动，或等剧情通过 DYN_ADD 登记后再用 /前往。"
	return {
		"error": "无法前往「%s」。可选：%s。%s" % [
			needle,
			"、".join(names) if not names.is_empty() else "（无其它已解锁地点）",
			hint,
		],
	}


static func _apply_tail_template_parts(cmd_id: String, vars: Dictionary) -> void:
	match cmd_id:
		"talk":
			var msg := str(vars.get("message", "")).strip_edges()
			if msg.is_empty():
				vars["message_part"] = "开口打招呼，并试探对方的态度与意图。"
			else:
				vars["message_part"] = "说道：「%s」" % msg
		"move":
			var detail := str(vars.get("detail", "")).strip_edges()
			if detail.is_empty():
				vars["detail_part"] = "，一路保持警惕并留意沿途变化"
			else:
				vars["detail_part"] = "，%s" % detail
		_:
			pass


static func _split_positional_args(arg_text: String, max_args: int) -> Array[String]:
	if arg_text.is_empty() or max_args <= 0:
		return []
	if max_args == 1:
		return [arg_text.strip_edges()]
	var parts: PackedStringArray = arg_text.split(" ", false, max_args - 1)
	var out: Array[String] = []
	for part in parts:
		out.append(str(part).strip_edges())
	return out


static func _apply_template(template: String, vars: Dictionary) -> String:
	var out := template
	for key in vars:
		out = out.replace("{%s}" % key, str(vars[key]))
	return out


static func _cleanup_expanded(text: String) -> String:
	var out := text.strip_edges()
	while out.find("  ") >= 0:
		out = out.replace("  ", " ")
	out = out.replace("」 。", "」。")
	out = out.replace(" 。", "。")
	out = out.replace("。。", "。")
	return out
