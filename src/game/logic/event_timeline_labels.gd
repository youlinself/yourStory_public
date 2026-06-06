extends RefCounted

## 事件时间线显示名（序章 / 第 N 幕），供详情面板与历史导出共用。

const INVALID_FILENAME_CHARS := "\\/:*?\"<>|"


static func label_from_timestamp(ts: int) -> String:
	if ts <= 0:
		return "序章"
	return "第 %d 幕" % ts


static func safe_filename_from_label(label: String) -> String:
	var safe := label.strip_edges()
	if safe.is_empty():
		return "未命名"
	for ch in INVALID_FILENAME_CHARS:
		safe = safe.replace(ch, "_")
	return safe
