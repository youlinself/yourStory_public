class_name NarrativePromptBuilder
extends RefCounted

const MD_FILE := "res://src/novel_config/narrative_turn.md"
const PLACEHOLDER := "{{NARRATIVE_SNAPSHOT_JSON}}"
const ResTextFileScript := preload("res://src/io/res_text_file.gd")
const DynamicAddServiceScript := preload("res://src/ai_skills/dynamic_add_service.gd")
const TurnToolRegistryScript := preload("res://src/game/logic/narrative/turn_tool_registry.gd")
const AiPromptComposerScript := preload("res://src/ai_config/ai_prompt_composer.gd")

## 对话历史上限（不含 system）。
const MAX_HISTORY_MESSAGES := 20
## 对话历史字符预算（不含 system 正文）。
const MAX_HISTORY_CHARS := 24000


static func build_system_prompt(snapshot: Dictionary) -> String:
	var md := _read_file(MD_FILE)
	if md.is_empty():
		push_error("无法读取 narrative_turn.md")
		return ""
	var snapshot_text := JSON.stringify(snapshot, "\t")
	var body := md.replace(PLACEHOLDER, snapshot_text)
	var reg := DynamicAddServiceScript.build_skill_registration_prompt()
	var tool_protocol := TurnToolRegistryScript.build_protocol_prompt()
	var merged := body.strip_edges()
	if not tool_protocol.is_empty():
		merged = merged + "\n\n---\n\n" + tool_protocol
	if not reg.is_empty():
		merged = merged + "\n\n---\n\n" + reg
	return AiPromptComposerScript.prepend_json_rules_to_system(merged)


## 固定保留 system 消息，再按条数与字符预算从尾部保留 user/assistant。
static func trim_messages(messages: Array) -> Array:
	if messages.is_empty():
		return []

	var system_msg: Dictionary = {}
	var narrative: Array = []
	for msg in messages:
		if not msg is Dictionary:
			continue
		var role := str(msg.get("role", "")).strip_edges()
		if role == "system":
			system_msg = (msg as Dictionary).duplicate(true)
		elif role == "user" or role == "assistant":
			narrative.append((msg as Dictionary).duplicate(true))

	var out: Array = []
	if not system_msg.is_empty():
		out.append(system_msg)

	if narrative.is_empty():
		return out

	var kept: Array = []
	var total_chars := 0
	for i in range(narrative.size() - 1, -1, -1):
		if kept.size() >= MAX_HISTORY_MESSAGES:
			break
		var entry: Dictionary = narrative[i]
		var content_len := str(entry.get("content", "")).length()
		if not kept.is_empty() and total_chars + content_len > MAX_HISTORY_CHARS:
			break
		kept.insert(0, entry)
		total_chars += content_len

	out.append_array(kept)
	return out


static func bootstrap_user_message(snapshot: Dictionary) -> String:
	var scene := str(snapshot.get("initial_scene", "")).strip_edges()
	var hook := ""
	var adventure: Variant = snapshot.get("adventure_module", {})
	if adventure is Dictionary:
		hook = str((adventure as Dictionary).get("opening_hook", "")).strip_edges()
	if scene.is_empty() and not hook.is_empty():
		scene = hook
	if scene.is_empty():
		scene = "冒险刚刚开始，描述当前场面并给出可行动线索。"
	return (
		"【开局】玩家尚未行动。以 DM 口吻描述开场场面（80–220 字），"
		+ "点明即时目标与可互动对象，不要替玩家做决定。情境：\n\n%s" % scene
	)


static func _read_file(path: String) -> String:
	return ResTextFileScript.read(path)
