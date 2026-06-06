extends RefCounted

## 读取项目内文本文件。导出版 PCK 中 res:// 资源不能用 file_exists 预判，需直接 open。


static func read(path: String) -> String:
	var normalized := path.strip_edges()
	if normalized.is_empty():
		return ""
	if normalized.begins_with("res://"):
		return _open_text(normalized)
	if not FileAccess.file_exists(normalized):
		push_warning("[ResTextFile] 文件不存在: %s" % normalized)
		return ""
	return _open_text(normalized)


static func read_json(path: String) -> Variant:
	var text := read(path).strip_edges()
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[ResTextFile] JSON 解析失败: %s — %s" % [path, json.get_error_message()])
		return null
	return json.get_data()


static func _open_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[ResTextFile] 无法打开: %s (error %d)" % [path, FileAccess.get_open_error()])
		return ""
	return file.get_as_text()
