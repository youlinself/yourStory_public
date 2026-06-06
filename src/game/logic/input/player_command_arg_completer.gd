class_name PlayerCommandArgCompleter
extends RefCounted

const SkillCatalog := preload("res://src/game/logic/data/skill_display_catalog.gd")
const PlayerCommandRegistryScript := preload("res://src/game/logic/input/player_command_registry.gd")
const LocationServiceScript := preload("res://src/game/logic/world/location_service.gd")

## 解析行内斜杠命令的参数段，生成与命令菜单相同结构的 entries。
## entry: { label, insert_text }


static func list_options_for(completer_id: String, read_model: GameReadModel, prefix: String = "") -> Array:
	return _list_options(completer_id.strip_edges(), read_model, prefix)


static func first_option_value(completer_id: String, read_model: GameReadModel) -> String:
	var opts := list_options_for(completer_id, read_model, "")
	if opts.is_empty():
		return ""
	return str(opts[0].get("value", "")).strip_edges()


static func try_build_entries(
	line_text: String,
	registry: PlayerCommandRegistryScript,
	read_model: GameReadModel,
) -> Dictionary:
	# 不可对整行 strip_edges：会吃掉「/观察 」末尾空格，导致无法进入参数补全阶段
	if not line_text.begins_with("/"):
		return _inactive()

	var body := line_text.substr(1)
	var first_space := body.find(" ")
	if first_space < 0:
		return _inactive()

	var cmd_token := body.substr(0, first_space).strip_edges()
	var arg_section := body.substr(first_space + 1)  # 保留尾部空格与未写完的参数
	var cmd := registry.find_command(cmd_token)
	if cmd.is_empty():
		return _inactive()

	var args: Variant = cmd.get("args", [])
	if not args is Array or (args as Array).is_empty():
		return _inactive()

	var arg_defs: Array = args
	var ends_with_space := arg_section.ends_with(" ")
	var segments: Array[String] = []
	var trimmed := arg_section.strip_edges()
	if not trimmed.is_empty():
		segments = _split_segments(trimmed, arg_defs.size())

	var arg_index := segments.size() if ends_with_space else maxi(0, segments.size() - 1)
	if arg_index >= arg_defs.size():
		return _inactive()

	var prefix := ""
	if not ends_with_space and not segments.is_empty():
		prefix = segments[arg_index]

	var arg_def: Dictionary = arg_defs[arg_index] if arg_defs[arg_index] is Dictionary else {}
	var completer_id := str(arg_def.get("completer", "")).strip_edges()
	if completer_id.is_empty():
		completer_id = str(arg_def.get("resolver", "")).strip_edges()
	if completer_id.is_empty():
		return _inactive()

	var slash := str(cmd.get("slash", cmd_token)).strip_edges()
	var options := _list_options(completer_id, read_model, prefix)
	if options.is_empty():
		var empty_hint := _build_empty_options_hint(completer_id, read_model, prefix)
		if empty_hint.is_empty():
			return _inactive()
		return {"active": true, "entries": [empty_hint], "mode": "arg"}

	var entries: Array = []
	for opt in options:
		if not opt is Dictionary:
			continue
		var value := str(opt.get("value", "")).strip_edges()
		var label := str(opt.get("label", value)).strip_edges()
		if value.is_empty():
			continue
		var new_segments := segments.duplicate()
		while new_segments.size() < arg_index:
			new_segments.append("")
		if new_segments.size() == arg_index:
			new_segments.append(value)
		else:
			new_segments[arg_index] = value
		var insert := _build_insert_line(slash, new_segments, arg_defs.size(), arg_index)
		entries.append({
			"label": label,
			"insert_text": insert,
			"kind": "arg",
		})

	return {"active": true, "entries": entries, "mode": "arg"}


static func _build_insert_line(slash: String, segments: Array[String], arg_count: int, _filled_index: int) -> String:
	var parts: PackedStringArray = []
	for i in range(arg_count):
		if i < segments.size():
			var s := segments[i].strip_edges()
			if not s.is_empty():
				parts.append(s)
	if parts.is_empty():
		return "/%s " % slash
	return "/%s %s" % [slash, " ".join(parts)]


static func _split_segments(trimmed_arg: String, max_args: int) -> Array[String]:
	if trimmed_arg.is_empty():
		return []
	if max_args <= 1:
		return [trimmed_arg]
	var parts: PackedStringArray = trimmed_arg.split(" ", false, max_args - 1)
	var out: Array[String] = []
	for part in parts:
		out.append(str(part).strip_edges())
	return out


static func _list_options(completer_id: String, read_model: GameReadModel, prefix: String) -> Array:
	var needle := prefix.strip_edges().to_lower()
	var out: Array = []
	match completer_id:
		"nearby_npc":
			_append_nearby_npcs(read_model, needle, out)
		"protagonist_skill":
			_append_skills(read_model, needle, out)
		"unlocked_region":
			_append_regions(read_model, needle, out)
		"generic_target":
			_append_generic_targets(read_model, needle, out)
		"duration_hints":
			_append_duration_hints(needle, out)
		_:
			pass
	return out


static func _append_nearby_npcs(read_model: GameReadModel, needle: String, out: Array) -> void:
	for npc in read_model.get_interactable_npcs():
		var nid := str(npc.get("id", "")).strip_edges()
		if nid.is_empty():
			continue
		var name := read_model.get_known_display_name(nid, str(npc.get("name", nid)))
		_maybe_append_option(out, name, name, needle)


static func _append_skills(read_model: GameReadModel, needle: String, out: Array) -> void:
	var catalog := SkillCatalog.new()
	catalog.bind_skills(read_model.get_skills_catalog())
	var known := read_model.get_known_protagonist_profile()
	var skill_ids: Variant = known.get("skills", [])
	if not skill_ids is Array:
		return
	for sid in skill_ids:
		var id_str := str(sid).strip_edges()
		if id_str.is_empty():
			continue
		var row := catalog.resolve(id_str)
		var sname := str(row.get("name", "")).strip_edges()
		if sname.is_empty():
			sname = SkillCatalog.humanize_skill_id(id_str)
		_maybe_append_option(out, sname, sname, needle)


static func _append_regions(read_model: GameReadModel, needle: String, out: Array) -> void:
	var current := str(read_model.mainrole.get("current_region_id", "")).strip_edges()
	for region in read_model.get_unlocked_regions():
		var rid := str(region.get("id", "")).strip_edges()
		var rname := str(region.get("name", rid)).strip_edges()
		if rid.is_empty() or rid == current:
			continue
		_maybe_append_option(out, rname, rname, needle)


static func _append_generic_targets(read_model: GameReadModel, needle: String, out: Array) -> void:
	_maybe_append_option(out, "周围环境", "周围环境", needle)
	var key_node_id := str(read_model.mainrole.get("current_key_node_id", "")).strip_edges()
	if not key_node_id.is_empty():
		var node := LocationServiceScript.get_key_node(read_model, key_node_id)
		var kn_name := str(node.get("name", "")).strip_edges()
		if not kn_name.is_empty():
			_maybe_append_option(out, kn_name, kn_name, needle)
	var current_id := str(read_model.mainrole.get("current_region_id", "")).strip_edges()
	for region in read_model.get_regions():
		if region is Dictionary:
			var rid := str(region.get("id", "")).strip_edges()
			if rid == current_id:
				var rname := str(region.get("name", "")).strip_edges()
				if not rname.is_empty():
					_maybe_append_option(out, rname, rname, needle)
				break
	for target in read_model.get_scene_target_display_names():
		_maybe_append_option(out, target, target, needle)
	for item in read_model.get_last_suggestions():
		var suggestion := str(item).strip_edges()
		if not suggestion.is_empty():
			_maybe_append_option(out, suggestion, suggestion, needle)
	for nid in read_model.get_present_npc_ids():
		var display := read_model.get_known_display_name(nid, nid)
		_maybe_append_option(out, display, display, needle)
	_append_nearby_npcs(read_model, needle, out)


static func _append_duration_hints(needle: String, out: Array) -> void:
	const HINTS: PackedStringArray = ["片刻", "几分钟", "一小时", "直到天亮"]
	for hint in HINTS:
		_maybe_append_option(out, hint, hint, needle)


static func _maybe_append_option(out: Array, label: String, value: String, needle: String) -> void:
	if label.is_empty():
		return
	if not needle.is_empty():
		var hay := label.to_lower()
		if not hay.begins_with(needle) and hay.find(needle) < 0:
			return
	for item in out:
		if item is Dictionary and str(item.get("value", "")) == value:
			return
	out.append({"label": label, "value": value})


static func _build_empty_options_hint(completer_id: String, read_model: GameReadModel, prefix: String) -> Dictionary:
	match completer_id:
		"nearby_npc":
			if read_model.get_interactable_npcs().is_empty():
				return _hint_entry("附近无人可对话")
			if not prefix.strip_edges().is_empty():
				return _hint_entry("未找到匹配的对象")
			return {}
		"protagonist_skill":
			return _hint_entry("尚未掌握可用技能")
		"unlocked_region":
			return _hint_entry("无其它可前往地点")
		_:
			return {}


static func _hint_entry(text: String) -> Dictionary:
	var msg := text.strip_edges()
	if msg.is_empty():
		return {}
	return {"label": "（%s）" % msg, "insert_text": "", "kind": "hint"}


static func _inactive() -> Dictionary:
	return {"active": false, "entries": [], "mode": ""}
