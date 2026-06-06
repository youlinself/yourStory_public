class_name GameHudUI
extends RefCounted

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

var _date_weather_label: Label
var _location_label: Label
var _wallet_label: Label
var _objective_label: Label
var _meta_label: Label


func setup(
	date_weather_label: Label,
	location_label: Label,
	wallet_label: Label = null,
	objective_label: Label = null,
	meta_label: Label = null,
) -> void:
	_date_weather_label = date_weather_label
	_location_label = location_label
	_wallet_label = wallet_label
	_objective_label = objective_label
	_meta_label = meta_label


func render(hud_vm: Dictionary) -> void:
	if _date_weather_label:
		var dt := WorldSettingDisplay.clamp_hud_text(str(hud_vm.get("datetime_display", "")))
		var weather := WorldSettingDisplay.clamp_hud_text(str(hud_vm.get("weather", "")))
		var line := dt if weather.is_empty() else "%s  %s" % [dt, weather]
		_date_weather_label.text = WorldSettingDisplay.clamp_hud_text(
			line,
			WorldSettingDisplay.HUD_LINE_MAX_LEN,
		)
	if _location_label:
		_location_label.text = WorldSettingDisplay.clamp_hud_text(
			str(hud_vm.get("location_path", "")),
			WorldSettingDisplay.HUD_LOCATION_MAX_LEN,
		)
	if _wallet_label:
		var wallet_text := str(hud_vm.get("wallet_display", "")).strip_edges()
		_wallet_label.visible = not wallet_text.is_empty()
		if _wallet_label.visible:
			_wallet_label.text = WorldSettingDisplay.clamp_hud_text(wallet_text, 24)
	if _objective_label:
		var objective := str(hud_vm.get("hud_objective_line", "")).strip_edges()
		_objective_label.visible = not objective.is_empty()
		if _objective_label.visible:
			_objective_label.text = objective
			_objective_label.add_theme_color_override(
				"font_color",
				DesignTokensScript.COLOR_TEXT_GOAL,
			)
			_sync_objective_tooltip(objective)
		else:
			_objective_label.tooltip_text = ""
	if _meta_label:
		var meta := str(hud_vm.get("hud_meta_line", "")).strip_edges()
		_meta_label.visible = not meta.is_empty()
		if _meta_label.visible:
			_meta_label.text = meta
			_meta_label.add_theme_color_override(
				"font_color",
				DesignTokensScript.COLOR_TEXT_PRESSURE,
			)


func _sync_objective_tooltip(full_text: String) -> void:
	_objective_label.call_deferred("queue_tooltip_sync", full_text)
