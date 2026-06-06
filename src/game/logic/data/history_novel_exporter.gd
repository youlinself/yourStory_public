extends RefCounted

## 将历史对局 event_log 按时间线分文件导出为纯文本小说。

const EventTimelineLabelsScript := preload("res://src/game/logic/event_timeline_labels.gd")

const INVALID_PATH_CHARS := "\\/:*?\"<>|"


static func build_groups(events: Array) -> Array:
	var by_ts: Dictionary = {}
	var order: Array[int] = []

	for item in events:
		if not item is Dictionary:
			continue
		var event: Dictionary = item
		var ts := int(event.get("timestamp", 0))
		if not by_ts.has(ts):
			by_ts[ts] = []
			order.append(ts)
		(by_ts[ts] as Array).append(event)

	order.sort()
	var groups: Array = []
	for ts in order:
		var label := EventTimelineLabelsScript.label_from_timestamp(ts)
		groups.append({
			"timestamp": ts,
			"label": label,
			"events": by_ts[ts],
		})
	return groups


static func event_body_text(event: Dictionary) -> String:
	var story_body := str(event.get("story_body", "")).strip_edges()
	if not story_body.is_empty():
		return story_body
	var compact := str(event.get("compact_body", "")).strip_edges()
	if not compact.is_empty():
		return compact
	return str(event.get("summary", "")).strip_edges()


static func render_timeline_file(label: String, events: Array, region_resolver: Callable) -> String:
	var lines: PackedStringArray = [label]
	for event in events:
		if not event is Dictionary:
			continue
		var ev: Dictionary = event
		var title := str(ev.get("title", "事件")).strip_edges()
		if title.is_empty():
			title = "事件"
		lines.append("")
		lines.append("## %s" % title)

		var region_id := str(ev.get("region_id", "")).strip_edges()
		if region_resolver.is_valid() and not region_id.is_empty():
			var region_name: String = str(region_resolver.call(region_id)).strip_edges()
			if not region_name.is_empty():
				lines.append("地点：%s" % region_name)

		var body := event_body_text(ev)
		if not body.is_empty():
			lines.append("")
			lines.append(body)

	return "\n".join(lines)


static func export_session(
	read_model: RefCounted,
	session_summary: Dictionary,
	dest_dir: String,
) -> Dictionary:
	var base := dest_dir.strip_edges()
	if base.is_empty():
		return _fail("未选择导出目录")

	if read_model == null or not read_model.has_method("get_events_chronological"):
		return _fail("会话数据无效")

	var events: Array = read_model.get_events_chronological()
	if events.is_empty():
		return _fail("该对局没有可导出的事件")

	var groups := build_groups(events)
	if groups.is_empty():
		return _fail("该对局没有可导出的事件")

	var subfolder := _session_subfolder_name(session_summary)
	var output_dir := _join_path(base, subfolder)
	var dir_err := DirAccess.make_dir_recursive_absolute(output_dir)
	if dir_err != OK:
		return _fail("无法创建导出目录（错误 %d）" % dir_err)

	var region_resolver := Callable(read_model, "get_region_name")
	var written_paths: Array[String] = []
	var used_names: Dictionary = {}

	for group in groups:
		if not group is Dictionary:
			continue
		var g: Dictionary = group
		var label := str(g.get("label", "")).strip_edges()
		var group_events: Array = g.get("events", [])
		if label.is_empty() or group_events.is_empty():
			continue

		var base_name := EventTimelineLabelsScript.safe_filename_from_label(label)
		var file_name := base_name + ".txt"
		var n := int(used_names.get(base_name, 0))
		if n > 0:
			file_name = "%s_%d.txt" % [base_name, n + 1]
		used_names[base_name] = n + 1

		var content := render_timeline_file(label, group_events, region_resolver)
		var file_path := _join_path(output_dir, file_name)
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if file == null:
			return _fail("无法写入文件：%s" % file_path)
		file.store_string(content)
		written_paths.append(file_path)

	if written_paths.is_empty():
		return _fail("没有生成任何导出文件")

	return {
		"ok": true,
		"error": "",
		"written_paths": written_paths,
		"output_dir": output_dir,
	}


static func _session_subfolder_name(summary: Dictionary) -> String:
	var novel_type := str(summary.get("novel_type", "")).strip_edges()
	if novel_type.is_empty():
		novel_type = "未知类型"
	var protagonist := str(summary.get("protagonist_name", "主角")).strip_edges()
	if protagonist.is_empty():
		protagonist = "主角"
	var archived_at := int(summary.get("archived_at", 0))
	var time_part := "unknown"
	if archived_at > 0:
		var dt := Time.get_datetime_dict_from_unix_time(archived_at)
		time_part = "%04d%02d%02d_%02d%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]
	var raw := "%s_%s_%s" % [novel_type, protagonist, time_part]
	return _sanitize_path_segment(raw)


static func _sanitize_path_segment(name: String) -> String:
	var safe := name.strip_edges()
	if safe.is_empty():
		return "export"
	for ch in INVALID_PATH_CHARS:
		safe = safe.replace(ch, "_")
	return safe


static func _join_path(dir_path: String, file_name: String) -> String:
	var d := dir_path.replace("\\", "/").rstrip("/")
	return d + "/" + file_name


static func _fail(error: String) -> Dictionary:
	return {
		"ok": false,
		"error": error,
		"written_paths": [],
		"output_dir": "",
	}
