extends SceneTree

const ResTextFileScript := preload("res://src/io/res_text_file.gd")

const NARRATIVE_TURN_MD := "res://src/novel_config/narrative_turn.md"


func _init() -> void:
	_test_read_res_md()
	_test_read_json_registry()
	quit(0)


func _test_read_res_md() -> void:
	var text := ResTextFileScript.read(NARRATIVE_TURN_MD)
	assert(not text.is_empty(), "res:// md should be readable without file_exists")
	assert(text.contains("NARRATIVE_SNAPSHOT_JSON"), "narrative_turn.md content mismatch")


func _test_read_json_registry() -> void:
	var data: Variant = ResTextFileScript.read_json(
		"res://ai_config/AiSkills/dynamic_add_registry.json"
	)
	assert(data is Dictionary, "registry json should parse")
	assert((data as Dictionary).has("categories"), "registry should have categories")
