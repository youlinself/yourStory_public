extends VBoxContainer

const AppInfoScript := preload("res://src/app_info.gd")

@onready var _description_label: RichTextLabel = %DescriptionLabel
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	if _description_label:
		_description_label.text = AppInfoScript.APP_DESCRIPTION
	if _version_label:
		_version_label.text = "版本号：%s" % AppInfoScript.APP_VERSION
