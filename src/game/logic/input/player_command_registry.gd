class_name PlayerCommandRegistry
extends RefCounted

const REGISTRY_PATH := "res://game_config/player_commands/registry.json"
const ResTextFileScript := preload("res://src/io/res_text_file.gd")
const ArgCompleterScript := preload("res://src/game/logic/input/player_command_arg_completer.gd")

var _commands: Array = []


func load_registry() -> bool:
	_commands.clear()
	var parsed: Variant = ResTextFileScript.read_json(REGISTRY_PATH)
	if parsed == null:
		push_error("[PlayerCommandRegistry] 缺少或无法解析: " + REGISTRY_PATH)
		return false
	if not parsed is Dictionary:
		push_error("[PlayerCommandRegistry] JSON 无效")
		return false
	var raw_cmds: Variant = (parsed as Dictionary).get("commands", [])
	if raw_cmds is Array:
		for item in raw_cmds:
			if item is Dictionary:
				_commands.append(item)
	return not _commands.is_empty()


func get_commands() -> Array:
	return _commands.duplicate(true)


func find_command(token: String) -> Dictionary:
	var key := token.strip_edges().to_lower()
	if key.is_empty():
		return {}
	for cmd in _commands:
		if not cmd is Dictionary:
			continue
		var slash := str(cmd.get("slash", "")).strip_edges()
		if slash.to_lower() == key or slash == token.strip_edges():
			return cmd as Dictionary
		var aliases: Variant = cmd.get("aliases", [])
		if aliases is Array:
			for alias in aliases:
				if str(alias).strip_edges().to_lower() == key:
					return cmd as Dictionary
	return {}


## 前缀已唯一对应某条带补全的首参数时，返回该命令（如「对话」→ talk）。
func resolve_single_matched_command(prefix_after_slash: String) -> Dictionary:
	var needle := prefix_after_slash.strip_edges()
	if needle.is_empty():
		return {}
	var exact := find_command(needle)
	if not exact.is_empty():
		return exact
	var entries := filter_menu_entries(needle)
	if entries.size() != 1:
		return {}
	var cmd: Variant = entries[0].get("command", {})
	return cmd if cmd is Dictionary else {}


func command_first_arg_has_completion(cmd: Dictionary) -> bool:
	var args: Variant = cmd.get("args", [])
	if not args is Array or (args as Array).is_empty():
		return false
	var def: Variant = (args as Array)[0]
	if not def is Dictionary:
		return false
	var d := def as Dictionary
	var cid := str(d.get("completer", "")).strip_edges()
	if cid.is_empty():
		cid = str(d.get("resolver", "")).strip_edges()
	return not cid.is_empty()


func filter_menu_entries(prefix_after_slash: String) -> Array:
	var needle := prefix_after_slash.strip_edges().to_lower()
	var out: Array = []
	for cmd in _commands:
		if not cmd is Dictionary:
			continue
		var slash := str(cmd.get("slash", "")).strip_edges()
		if slash.is_empty():
			continue
		var matched := needle.is_empty()
		if not matched and slash.to_lower().begins_with(needle):
			matched = true
		var aliases: Variant = cmd.get("aliases", [])
		if not matched and aliases is Array:
			for alias in aliases:
				if str(alias).strip_edges().to_lower().begins_with(needle):
					matched = true
					break
		if not matched:
			continue
		out.append({
			"insert_text": "/" + slash,
			"label": _format_menu_label(cmd as Dictionary),
			"command": cmd,
			"kind": "command",
		})
	return out


func filter_menu_entries_with_preview(prefix_after_slash: String, read_model: GameReadModel) -> Array:
	var needle := prefix_after_slash.strip_edges().to_lower()
	var out: Array = []
	for cmd in _commands:
		if not cmd is Dictionary:
			continue
		var slash := str(cmd.get("slash", "")).strip_edges()
		if slash.is_empty():
			continue
		var matched := needle.is_empty()
		if not matched and slash.to_lower().begins_with(needle):
			matched = true
		var aliases: Variant = cmd.get("aliases", [])
		if not matched and aliases is Array:
			for alias in aliases:
				if str(alias).strip_edges().to_lower().begins_with(needle):
					matched = true
					break
		if not matched:
			continue
		var cmd_dict := cmd as Dictionary
		out.append({
			"insert_text": "/" + slash,
			"label": build_menu_label(cmd_dict, read_model),
			"command": cmd,
			"kind": "command",
		})
	return out


static func build_menu_label(cmd: Dictionary, read_model: GameReadModel) -> String:
	var slash := str(cmd.get("slash", "")).strip_edges()
	var args: Variant = cmd.get("args", [])
	if not args is Array or args.is_empty():
		return "/%s" % slash
	var defaults: Variant = cmd.get("defaults", {})
	var default_map: Dictionary = defaults if defaults is Dictionary else {}
	var parts: PackedStringArray = []
	for arg_def in args:
		if not arg_def is Dictionary:
			continue
		var def := arg_def as Dictionary
		var arg_name := str(def.get("name", "")).strip_edges()
		var completer_id := str(def.get("completer", "")).strip_edges()
		if completer_id.is_empty():
			completer_id = str(def.get("resolver", "")).strip_edges()
		# 命令级预览只展示「目录项」首参，不含 message/detail 等自由后缀占位
		if completer_id.is_empty():
			break
		var value := ""
		if read_model != null:
			value = ArgCompleterScript.first_option_value(completer_id, read_model)
		if value.is_empty() and default_map.has(arg_name):
			value = str(default_map.get(arg_name, "")).strip_edges()
		if value.is_empty():
			var ph := str(def.get("placeholder", arg_name)).strip_edges()
			var required := bool(def.get("required", false))
			value = ("<%s>" % ph) if required else ("[%s]" % ph)
		parts.append(value)
	if parts.is_empty():
		return "/%s" % slash
	return "/%s %s" % [slash, " ".join(parts)]


static func _format_menu_label(cmd: Dictionary) -> String:
	var slash := str(cmd.get("slash", "")).strip_edges()
	var args: Variant = cmd.get("args", [])
	if not args is Array or args.is_empty():
		return "/%s" % slash
	var parts: PackedStringArray = []
	for arg_def in args:
		if not arg_def is Dictionary:
			continue
		var name := str(arg_def.get("name", "")).strip_edges()
		var ph := str(arg_def.get("placeholder", name)).strip_edges()
		var required := bool(arg_def.get("required", false))
		if required:
			parts.append("<" + ph + ">")
		else:
			parts.append("[" + ph + "]")
	if parts.is_empty():
		return "/%s" % slash
	return "/%s %s" % [slash, " ".join(parts)]
