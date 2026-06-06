class_name CharacterProfileInfoBinder
extends RefCounted

const ProfileDisplayScript := preload("res://src/game/logic/data/character_profile_display.gd")


static func bind(
	info_body: RichTextLabel,
	psychology_block: Control,
	psychology_rows: VBoxContainer,
	psychology_radar: Control,
	abilities_block: Control,
	abilities_rows: VBoxContainer,
	abilities_radar: Control,
	known_profile: Dictionary,
) -> void:
	info_body.text = ProfileDisplayScript.build_text_fields_text(known_profile)
	_bind_stat_block(
		psychology_block,
		psychology_rows,
		psychology_radar,
		ProfileDisplayScript.build_psychology_stat_rows(known_profile),
		ProfileDisplayScript.PSYCHOLOGY_SECTION_TOOLTIP,
	)
	_bind_stat_block(
		abilities_block,
		abilities_rows,
		abilities_radar,
		ProfileDisplayScript.build_ability_stat_rows(known_profile),
		ProfileDisplayScript.ABILITY_SECTION_TOOLTIP,
	)


static func _bind_stat_block(
	block: Control,
	rows_container: VBoxContainer,
	radar: Control,
	rows: Array,
	section_tooltip: String = "",
) -> void:
	_clear_children(rows_container)
	if rows.is_empty():
		block.visible = false
		return
	block.visible = true
	_apply_section_tooltip(block, rows_container, section_tooltip)
	var values: Array = []
	for row in rows:
		if not row is Dictionary:
			continue
		var label := Label.new()
		var display := str(row.get("display_label", "")).strip_edges()
		if display.is_empty():
			display = "%s：%d" % [str(row.get("label", "")), int(row.get("value", 0))]
		label.text = display
		var tip := str(row.get("tooltip", "")).strip_edges()
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		if not tip.is_empty():
			label.tooltip_text = tip
		rows_container.add_child(label)
		values.append(row.get("value", 0))
	if radar.has_method("set_stats"):
		radar.call("set_stats", rows, section_tooltip)
	elif radar.has_method("set_values"):
		radar.call("set_values", values)


static func _apply_section_tooltip(
	block: Control,
	rows_container: VBoxContainer,
	section_tooltip: String,
) -> void:
	var tip := section_tooltip.strip_edges()
	if tip.is_empty():
		return
	# 分组 tooltip 只挂在标题上；block 若也设置 tooltip，子项 Label 默认 IGNORE 鼠标会穿透并误显示分组说明。
	block.tooltip_text = ""
	var parent_col := rows_container.get_parent()
	if parent_col == null:
		return
	for child in parent_col.get_children():
		if child is Label and child != rows_container:
			child.tooltip_text = tip
			child.mouse_filter = Control.MOUSE_FILTER_STOP
			break


static func _clear_children(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
