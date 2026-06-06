extends SceneTree

const LauncherScript := preload("res://src/backend/backend_launcher.gd")


func _init() -> void:
	_test_strips_ui_only_fields()
	_test_preserves_backend_fields()
	_test_empty_and_sparse()
	_test_resolve_client_port()
	_test_windows_godot_dict_argv()
	quit(0)


func _test_strips_ui_only_fields() -> void:
	var raw := {
		"api_key": "sk-test",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
		"models_url": "https://api.example.com/v1/models",
		"model": "test-model",
		"vendor": "Test",
		"website": "https://api.example.com",
		"reasoning_effort": "medium",
	}
	var out: Dictionary = LauncherScript._sanitize_ai_config_for_backend(raw)
	assert(not out.has("auth_header"))
	assert(not out.has("auth_prefix"))
	assert(not out.has("models_url"))
	var serialized := JSON.stringify(out)
	assert(not serialized.contains("auth_prefix"))
	assert(not serialized.contains("Bearer "))


func _test_preserves_backend_fields() -> void:
	var raw := {
		"api_key": "sk-test",
		"model": "MiniMax-M3",
		"vendor": "Minimax",
		"website": "https://api.minimaxi.com",
		"reasoning_effort": "medium",
		"thinking": {"type": "disabled"},
		"max_tokens": 4096,
	}
	var out: Dictionary = LauncherScript._sanitize_ai_config_for_backend(raw)
	assert(out.size() == 7)
	assert(out["model"] == "MiniMax-M3")
	assert(out["thinking"] is Dictionary)


func _test_empty_and_sparse() -> void:
	assert(LauncherScript._sanitize_ai_config_for_backend({}).is_empty())
	var sparse := {"auth_prefix": "Bearer ", "models_url": "https://x"}
	assert(LauncherScript._sanitize_ai_config_for_backend(sparse).is_empty())


func _test_resolve_client_port() -> void:
	assert(LauncherScript.resolve_client_port(54321, 54322, true) == 54322)
	assert(LauncherScript.resolve_client_port(54321, 54322, false) == 54321)
	assert(LauncherScript.resolve_client_port(-1, 54322, true) == 54322)


func _test_windows_godot_dict_argv() -> void:
	var raw := {
		"api_key": "sk-test",
		"model": "MiniMax-M3",
		"vendor": "Minimax",
		"website": "https://api.minimaxi.com",
		"reasoning_effort": "medium",
		"thinking": {"type": "disabled"},
	}
	var literal: String = LauncherScript._config_to_godot_dict_literal(raw)
	assert(literal.begins_with("{"))
	assert("api_key:sk-test" in literal)
	assert("thinking:{type:disabled}" in literal)
	assert(not literal.contains('"'))
