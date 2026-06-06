## 遗留面板：未接入 DataPanelsUI，见 docs/ui-legacy.md
extends Control

@onready var _body_label: RichTextLabel = %BodyLabel


func show_relationships(entries: Array) -> void:
	if entries.is_empty():
		_body_label.text = "暂无可展示的人物关系。"
		return
	var lines: PackedStringArray = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var row: Dictionary = entry
		lines.append(
			"• %s —[%s]→ %s"
			% [
				str(row.get("from_name", "")),
				str(row.get("relation", "")),
				str(row.get("to_name", "")),
			]
		)
	_body_label.text = "\n".join(lines)
