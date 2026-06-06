extends Control

const DesignTokensScript := preload("res://src/ui/design_tokens.gd")

const MAIN_MENU_SCENE := "res://sences/main_menu/main_menu.tscn"
const FADE_IN_SEC := 0.7
const HOLD_SEC := 1.2

@onready var _bg: ColorRect = $SplashBackground
@onready var _logo: TextureRect = $LogoSlot/LogoTexture

var _leaving := false
var _sequence_tween: Tween
var _main_menu_packed: PackedScene


func _ready() -> void:
	_bg.color = DesignTokensScript.COLOR_BG_ROOT
	# 避免 change_scene 空帧时露出引擎默认灰底
	RenderingServer.set_default_clear_color(DesignTokensScript.COLOR_BG_ROOT)
	_main_menu_packed = load(MAIN_MENU_SCENE) as PackedScene
	_logo.modulate.a = 0.0
	_play_sequence()


func _play_sequence() -> void:
	_sequence_tween = create_tween()
	_sequence_tween.tween_property(_logo, "modulate:a", 1.0, FADE_IN_SEC)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_sequence_tween.tween_interval(HOLD_SEC)
	_sequence_tween.finished.connect(_transition_to_main_menu)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if event is InputEventMouseButton and event.pressed:
		_skip()
	elif event is InputEventKey and event.pressed and not event.echo:
		_skip()


func _skip() -> void:
	if _sequence_tween and _sequence_tween.is_valid():
		_sequence_tween.kill()
	_transition_to_main_menu()


## 不用 change_scene_to_packed：会先销毁闪屏再挂主菜单，中间会空 1～2 帧。
## 主菜单在闪屏下层完成 _ready 后再移除闪屏，避免「Logo 没了只剩灰底」。
func _transition_to_main_menu() -> void:
	if _leaving:
		return
	_leaving = true

	if _main_menu_packed == null:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
		return

	var menu: Node = _main_menu_packed.instantiate()
	var root := get_tree().root
	root.add_child(menu)
	root.move_child(menu, 0)

	if not menu.is_node_ready():
		await menu.ready
	# 再等一帧，确保 UiBackground 等已参与绘制
	await get_tree().process_frame

	get_tree().current_scene = menu
	queue_free()
