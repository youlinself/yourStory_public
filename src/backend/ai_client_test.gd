extends Control
## 测试 AIClient 是否能正常对接后端

@onready var log_label: RichTextLabel = $VBoxContainer/LogLabel

var _ai_client: AIClient
var _test_done := false


func _ready() -> void:
	_ai_client = AIClient.new()
	add_child(_ai_client)
	_ai_client.chat_completed.connect(_on_chat_completed)
	_ai_client.stream_chunk.connect(_on_stream_chunk)
	_ai_client.stream_completed.connect(_on_stream_completed)
	_ai_client.request_failed.connect(_on_request_failed)

	_log("[color=yellow]等待后端启动...[/color]")
	BackendLauncher.backend_ready.connect(_on_backend_ready)
	BackendLauncher.backend_failed.connect(_on_backend_failed)
	BackendLauncher.start_backend()


func _on_backend_ready(port: int) -> void:
	_log("[color=green]后端已就绪，端口: %d[/color]" % port)
	_ai_client.set_port(port)
	_test_non_streaming()


func _on_backend_failed(reason: String) -> void:
	_log("[color=red]后端启动失败: %s[/color]" % reason)


func _test_non_streaming() -> void:
	_log("\n[color=cyan]=== 测试非流式对话 (/api/chat) ===[/color]")
	_log("发送消息: \"test\"")
	var messages := [{"role": "user", "content": "test"}]
	_ai_client.chat(messages)


func _on_chat_completed(response: Dictionary) -> void:
	_log("[color=green]非流式响应:[/color]")
	_log(JSON.stringify(response, "  "))
	_test_streaming()


func _test_streaming() -> void:
	_log("\n[color=cyan]=== 测试流式对话 (/api/chat/stream) ===[/color]")
	_log("发送消息: \"请用一句话介绍你自己\"")
	var messages := [{"role": "user", "content": "请用一句话介绍你自己"}]
	_ai_client.chat_stream(messages)


func _on_stream_chunk(text: String) -> void:
	_log.call_deferred("[color=white]%s[/color]" % text)


func _on_stream_completed(full_text: String) -> void:
	_log.call_deferred("\n[color=green]流式对话完成，完整回复:[/color]")
	_log.call_deferred(full_text)
	_log.call_deferred("[color=green]所有测试完成！[/color]")
	_test_done = true


func _on_request_failed(error: String) -> void:
	_log("[color=red]请求失败: %s[/color]" % error)


func _log(text: String) -> void:
	if log_label:
		log_label.append_text(text + "\n")
	print(text)
