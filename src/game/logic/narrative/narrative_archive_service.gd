extends RefCounted

const ARCHIVE_CHAR_THRESHOLD := 4000
## 归档后保留的最近对话字数目标（衔接尾巴，避免断崖断联）
const RETAIN_TAIL_CHAR_TARGET := 1500
## 保留区相对触发阈值的上限余量（避免归档后尾巴仍 ≥ 阈值导致空转）
const ARCHIVE_RETAIN_HEADROOM := 1000
const RETAIN_MAX_CHARS := ARCHIVE_CHAR_THRESHOLD - ARCHIVE_RETAIN_HEADROOM

const ResTextFileScript := preload("res://src/io/res_text_file.gd")
const AiPromptComposerScript := preload("res://src/ai_config/ai_prompt_composer.gd")
const TITLE_PROMPT_PATH := "res://src/novel_config/narrative_archive_title.md"
const COMPACT_SKILL_PATH := "res://ai_config/AiSkills/narrative_context_compact.md"

const PLACEHOLDER_CONTEXT := "{{ARCHIVE_CONTEXT_JSON}}"
const PLACEHOLDER_STORY := "{{ARCHIVE_STORY_TEXT}}"

var _ai_client: AIClient


func bind_ai_client(client: AIClient) -> void:
	_ai_client = client


static func should_archive_story(
	story_log: Array,
	from_index: int = 0,
	chars_since_last_archive: int = -1,
) -> bool:
	if chars_since_last_archive >= 0:
		return chars_since_last_archive >= ARCHIVE_CHAR_THRESHOLD
	return count_story_log_chars(story_log, from_index) >= ARCHIVE_CHAR_THRESHOLD


static func pending_story_log(story_log: Array, from_index: int = 0) -> Array:
	if from_index > 0:
		return story_log.slice(from_index)
	return story_log.duplicate(true)


## 超阈值且能切出非空 to_archive 时才应走归档（避免 UI 空转提示）。
static func can_archive_pending(
	story_log: Array,
	from_index: int = 0,
	chars_since_last_archive: int = -1,
) -> bool:
	if not should_archive_story(story_log, from_index, chars_since_last_archive):
		return false
	var split: Dictionary = resolve_pending_archive_split(pending_story_log(story_log, from_index))
	return not (split.get("to_archive", []) as Array).is_empty()


static func resolve_pending_archive_split(pending_log: Array) -> Dictionary:
	var split: Dictionary = split_story_log_for_archive(pending_log)
	var to_archive: Array = split.get("to_archive", [])
	var retained: Array = split.get("retained", [])
	_trim_retained_for_limits(retained, to_archive)
	_force_nonempty_to_archive(retained, to_archive)
	return {"to_archive": to_archive, "retained": retained}


static func _trim_retained_for_limits(retained: Array, to_archive: Array) -> void:
	while not retained.is_empty():
		var retained_chars := count_story_log_chars(retained, 0)
		if retained_chars < ARCHIVE_CHAR_THRESHOLD and retained_chars <= RETAIN_MAX_CHARS:
			break
		to_archive.append(retained[0])
		retained.remove_at(0)


static func _force_nonempty_to_archive(retained: Array, to_archive: Array) -> void:
	if not to_archive.is_empty():
		return
	while not retained.is_empty():
		to_archive.append(retained[0])
		retained.remove_at(0)


static func warn_if_retained_over_threshold(retained: Array) -> void:
	var n := count_story_log_chars(retained, 0)
	if n >= ARCHIVE_CHAR_THRESHOLD:
		push_warning(
			"[NarrativeArchiveService] 归档保留尾巴仍达 %d 字（阈值 %d）"
			% [n, ARCHIVE_CHAR_THRESHOLD]
		)


static func count_story_log_chars(story_log: Array, from_index: int = 0) -> int:
	var total := 0
	var start := clampi(from_index, 0, story_log.size())
	for i in range(start, story_log.size()):
		var entry: Variant = story_log[i]
		if not entry is Dictionary:
			continue
		var role := str(entry.get("role", "")).strip_edges()
		if role != "user" and role != "assistant":
			continue
		var content := str(entry.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		total += content.length()
	return total


static func split_story_log_for_archive(story_log: Array) -> Dictionary:
	var to_archive: Array = []
	var retained: Array = []
	if story_log.is_empty():
		return {"to_archive": to_archive, "retained": retained}

	var tail_indices: Array[int] = []
	var tail_chars := 0
	var tail_user_count := 0
	var i := story_log.size() - 1
	while i >= 0:
		var entry: Variant = story_log[i]
		if not entry is Dictionary:
			i -= 1
			continue
		var role := str(entry.get("role", "")).strip_edges()
		if role != "user" and role != "assistant":
			i -= 1
			continue
		var content := str(entry.get("content", "")).strip_edges()
		if content.is_empty():
			i -= 1
			continue
		var content_len := content.length()
		if tail_chars + content_len > RETAIN_MAX_CHARS:
			break
		if tail_user_count >= 1 and tail_chars >= RETAIN_TAIL_CHAR_TARGET:
			break
		if tail_user_count >= 2 and tail_chars + content_len > RETAIN_TAIL_CHAR_TARGET * 2:
			break
		tail_indices.insert(0, i)
		tail_chars += content_len
		if role == "user":
			tail_user_count += 1
		i -= 1

	if tail_indices.is_empty():
		for j in range(story_log.size()):
			var e: Variant = story_log[j]
			if e is Dictionary:
				var r := str(e.get("role", "")).strip_edges()
				if r == "user" or r == "assistant":
					var c := str(e.get("content", "")).strip_edges()
					if not c.is_empty():
						to_archive.append(e)
		return {"to_archive": to_archive, "retained": retained}

	var tail_set: Dictionary = {}
	for idx in tail_indices:
		tail_set[idx] = true

	for j in range(story_log.size()):
		var item: Variant = story_log[j]
		if not item is Dictionary:
			continue
		var r := str(item.get("role", "")).strip_edges()
		if r != "user" and r != "assistant":
			continue
		if str(item.get("content", "")).strip_edges().is_empty():
			continue
		if tail_set.has(j):
			retained.append(item)
		else:
			to_archive.append(item)
	return {"to_archive": to_archive, "retained": retained}


static func map_messages_for_story_retention(messages: Array, retained_story_count: int) -> Dictionary:
	var narrative: Array = []
	for msg in messages:
		if not msg is Dictionary:
			continue
		var role := str(msg.get("role", "")).strip_edges()
		if role == "user" or role == "assistant":
			narrative.append(msg)
	var retain_n := clampi(retained_story_count, 0, narrative.size())
	var archive_n := narrative.size() - retain_n
	var to_archive: Array = []
	var retained: Array = []
	for i in range(narrative.size()):
		if i < archive_n:
			to_archive.append(narrative[i])
		else:
			retained.append(narrative[i])
	return {"to_archive": to_archive, "retained": retained}


static func split_messages_for_archive(messages: Array) -> Dictionary:
	var to_archive: Array = []
	var retained: Array = []
	if messages.is_empty():
		return {"to_archive": to_archive, "retained": retained}

	var tail_indices: Array[int] = []
	var tail_chars := 0
	var tail_user_count := 0
	var i := messages.size() - 1
	while i >= 0:
		var msg: Variant = messages[i]
		if not msg is Dictionary:
			i -= 1
			continue
		var role := str(msg.get("role", "")).strip_edges()
		if role != "user" and role != "assistant":
			i -= 1
			continue
		var content_len := str(msg.get("content", "")).length()
		if tail_chars + content_len > RETAIN_MAX_CHARS:
			break
		if tail_user_count >= 1 and tail_chars >= RETAIN_TAIL_CHAR_TARGET:
			break
		if tail_user_count >= 2 and tail_chars + content_len > RETAIN_TAIL_CHAR_TARGET * 2:
			break
		tail_indices.insert(0, i)
		tail_chars += content_len
		if role == "user":
			tail_user_count += 1
		i -= 1

	if tail_indices.is_empty():
		for j in range(messages.size()):
			var m: Variant = messages[j]
			if m is Dictionary:
				var r := str(m.get("role", "")).strip_edges()
				if r == "user" or r == "assistant":
					to_archive.append(m)
		return {"to_archive": to_archive, "retained": retained}

	var tail_set: Dictionary = {}
	for idx in tail_indices:
		tail_set[idx] = true

	for j in range(messages.size()):
		var entry: Variant = messages[j]
		if not entry is Dictionary:
			continue
		var r := str(entry.get("role", "")).strip_edges()
		if r != "user" and r != "assistant":
			continue
		if tail_set.has(j):
			retained.append(entry)
		else:
			to_archive.append(entry)
	return {"to_archive": to_archive, "retained": retained}


static func build_story_text_from_log(story_log: Array, from_index: int = 0, to_index: int = -1) -> String:
	var parts: PackedStringArray = []
	var start := maxi(0, from_index)
	var end := story_log.size() if to_index < 0 else clampi(to_index, start, story_log.size())
	for i in range(start, end):
		var entry: Variant = story_log[i]
		if not entry is Dictionary:
			continue
		var content := str(entry.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		var role := str(entry.get("role", "")).strip_edges()
		if role == "user":
			parts.append("【玩家】\n%s" % content)
		else:
			parts.append(content)
	return "\n\n".join(parts)


func archive_pending_context(
	read_model: GameReadModel,
	state_service: RuntimeStateService,
) -> Dictionary:
	if _ai_client == null:
		return {"ok": false, "archived": false, "error": "AI 客户端未绑定"}

	var story_log := state_service.get_story_log()
	var from_index := state_service.get_last_archive_story_index()
	var chars_since: int = state_service.get_chars_since_last_archive()
	if not should_archive_story(story_log, from_index, chars_since):
		return {"ok": true, "archived": false, "error": ""}

	var pending_log: Array = pending_story_log(story_log, from_index)
	var story_split: Dictionary = resolve_pending_archive_split(pending_log)
	var to_archive_story: Array = story_split.get("to_archive", [])
	var retained_story: Array = story_split.get("retained", [])
	if to_archive_story.is_empty():
		return {"ok": false, "archived": false, "error": "无法切分待归档内容"}

	var messages := state_service.get_narrative_messages()
	var msg_split := map_messages_for_story_retention(messages, retained_story.size())
	var to_archive_msgs: Array = msg_split.get("to_archive", [])
	var retained_msgs: Array = msg_split.get("retained", [])

	var archive_to_index := from_index + to_archive_story.size()
	var story_text := build_story_text_from_log(story_log, from_index, archive_to_index)
	if story_text.strip_edges().is_empty():
		story_text = _fallback_story_text_from_messages(to_archive_msgs)
	if story_text.strip_edges().is_empty():
		return {"ok": false, "archived": false, "error": "无可归档叙事正文"}

	if retained_story.is_empty() and story_log.size() > archive_to_index:
		retained_story = story_log.slice(archive_to_index).duplicate(true)

	var char_count := story_text.strip_edges().length()
	var snapshot := read_model.build_narrative_snapshot()

	var title_raw := await _request_archive_title(snapshot, story_text)
	if title_raw.is_empty():
		return {"ok": false, "archived": false, "error": "归档标题生成失败"}

	var title_data: Variant = AiResponseParser.parse_json_from_ai_text(title_raw)
	if not title_data is Dictionary:
		return {"ok": false, "archived": false, "error": "归档标题 JSON 无效"}
	var title := str(title_data.get("title", "")).strip_edges()
	var summary := str(title_data.get("summary", "")).strip_edges()
	if title.is_empty():
		title = "未命名章节"
	if summary.is_empty():
		summary = story_text.substr(0, mini(200, story_text.length()))

	var compact_body := await _request_narrative_compact(story_text)
	if compact_body.is_empty():
		return {"ok": false, "archived": false, "error": "剧情压缩失败"}

	var region_id := str(read_model.mainrole.get("current_region_id", "")).strip_edges()
	var event_entry := {
		"title": title,
		"summary": summary,
		"story_body": story_text,
		"compact_body": compact_body,
		"region_id": region_id,
		"archived_at": int(Time.get_unix_time_from_system()),
		"source_char_count": char_count,
	}

	warn_if_retained_over_threshold(retained_story)

	if not state_service.finalize_archive(
		event_entry,
		compact_body,
		retained_msgs,
		retained_story,
	):
		return {"ok": false, "archived": false, "error": "无法保存归档状态"}

	return {"ok": true, "archived": true, "error": "", "event_title": title}


static func _fallback_story_text_from_messages(messages: Array) -> String:
	var parts: PackedStringArray = []
	for msg in messages:
		if not msg is Dictionary:
			continue
		var role := str(msg.get("role", "")).strip_edges()
		if role != "user" and role != "assistant":
			continue
		var content := str(msg.get("content", "")).strip_edges()
		if content.is_empty():
			continue
		if role == "user":
			parts.append("【玩家】\n%s" % content)
		else:
			var hook_start := content.find("---STATE_HOOK---")
			if hook_start >= 0:
				content = content.substr(0, hook_start).strip_edges()
			parts.append(content)
	return "\n\n".join(parts)


func _request_archive_title(snapshot: Dictionary, story_text: String) -> String:
	var template := _read_file(TITLE_PROMPT_PATH)
	if template.is_empty():
		push_error("无法读取 narrative_archive_title.md")
		return ""
	var context_json := JSON.stringify({
		"protagonist_name": snapshot.get("protagonist_name", ""),
		"datetime_display": snapshot.get("datetime_display", ""),
		"weather": snapshot.get("weather", ""),
		"location_path": snapshot.get("location_path", ""),
		"recent_events": snapshot.get("recent_events", []),
	}, "\t")
	var prompt := template.replace(PLACEHOLDER_CONTEXT, context_json)
	prompt = prompt.replace(PLACEHOLDER_STORY, story_text)
	return await _request_ai(AiPromptComposerScript.wrap_json_task(prompt))


func _request_narrative_compact(story_text: String) -> String:
	var template := _read_file(COMPACT_SKILL_PATH)
	if template.is_empty():
		push_error("无法读取 narrative_context_compact.md")
		return ""
	var prompt := template.replace(PLACEHOLDER_STORY, story_text)
	var raw := await _request_ai([{"role": "user", "content": prompt}])
	return _extract_compact_snapshot(raw)


static func _extract_compact_snapshot(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	var marker := "### 💾 NARRATIVE SNAPSHOT"
	var idx := text.find(marker)
	if idx >= 0:
		return text.substr(idx).strip_edges()
	marker = "NARRATIVE SNAPSHOT"
	idx = text.find(marker)
	if idx >= 0:
		return text.substr(idx).strip_edges()
	return text


func _request_ai(messages: Array) -> String:
	var state := {"done": false, "text": "", "error": ""}

	var on_completed := func(response: Dictionary) -> void:
		state["text"] = AiResponseParser.extract_message_content(response)
		if state["text"].is_empty():
			state["error"] = "AI 响应无正文"
		state["done"] = true

	var on_failed := func(err: String) -> void:
		state["error"] = err
		state["done"] = true

	_ai_client.chat_completed.connect(on_completed, CONNECT_ONE_SHOT)
	_ai_client.request_failed.connect(on_failed, CONNECT_ONE_SHOT)
	_ai_client.chat(messages)

	var loop := Engine.get_main_loop()
	while not state["done"]:
		if loop == null:
			break
		await loop.process_frame

	if not state["error"].is_empty():
		push_error("[NarrativeArchiveService] " + state["error"])
		return ""
	return state["text"]


static func _read_file(path: String) -> String:
	return ResTextFileScript.read(path)
