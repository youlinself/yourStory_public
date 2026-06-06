class_name EventReviewBrowser
extends HBoxContainer

const EventDetailPanelScene := preload("res://sences/game/panels/event_detail_panel.tscn")
const UiStylesScript := preload("res://src/ui/ui_styles.gd")

@onready var _sidebar_list: VBoxContainer = %SidebarList
@onready var _detail_host: Control = %DetailHost

var _detail_panel: Control
var _events: Array[Dictionary] = []
var _region_resolver: Callable


func _ready() -> void:
	_region_resolver = Callable(self, "_default_region_resolver")
	_detail_panel = EventDetailPanelScene.instantiate()
	_detail_host.add_child(_detail_panel)
	_detail_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _detail_panel.has_method("set_recall_enabled"):
		_detail_panel.set_recall_enabled(false)
	_show_empty_detail()


func bind_events(events: Array, region_resolver: Callable = Callable()) -> void:
	_events.clear()
	for item in events:
		if item is Dictionary:
			_events.append(item)
	if region_resolver.is_valid():
		_region_resolver = region_resolver
	else:
		_region_resolver = Callable(self, "_default_region_resolver")
	_rebuild_sidebar()


func _default_region_resolver(_region_id: String) -> String:
	return ""


func _rebuild_sidebar() -> void:
	for child in _sidebar_list.get_children():
		child.queue_free()

	if _events.is_empty():
		_sidebar_list.add_child(UiStylesScript.make_empty_hint("暂无事件记录"))
		_show_empty_detail()
		return

	for i in _events.size():
		var event: Dictionary = _events[i]
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = str(event.get("title", "事件"))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UiStylesScript.apply_sidebar_toggle(btn)
		btn.pressed.connect(_on_event_pressed.bind(event, btn))
		_sidebar_list.add_child(btn)

	var first_btn := _sidebar_list.get_child(0) as Button
	if first_btn:
		first_btn.button_pressed = true
		_show_event(_events[0])


func _on_event_pressed(event: Dictionary, active_btn: Button) -> void:
	for child in _sidebar_list.get_children():
		if child is Button:
			(child as Button).button_pressed = child == active_btn
	_show_event(event)


func _show_event(event: Dictionary) -> void:
	if _detail_panel and _detail_panel.has_method("show_event"):
		var region_id := str(event.get("region_id", "")).strip_edges()
		var region_name := ""
		if not region_id.is_empty() and _region_resolver.is_valid():
			region_name = str(_region_resolver.call(region_id))
		_detail_panel.show_event(event, region_name)


func _show_empty_detail() -> void:
	if _detail_panel and _detail_panel.has_method("show_event"):
		_detail_panel.show_event({})
