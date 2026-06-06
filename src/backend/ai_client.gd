class_name AIClient
extends Node
## 对接后端 AI 接口的客户端
## 通过 BackendLauncher 获取端口，然后访问 /api/chat 和 /api/chat/stream

const DEFAULT_TIMEOUT_SEC := 120.0
const WORLD_INIT_TIMEOUT_SEC := 600.0
const WORLD_BUILD_SUBSTEP_TIMEOUT_SEC := 180.0

## 非 HTTP 层错误（未发起请求等）时 request_failed_ex 的 http_result 取值。
const HTTP_RESULT_NONE := -1

## 非流式对话完成
signal chat_completed(response: Dictionary)
## 流式每收到一段文本时触发
signal stream_chunk(text: String)
## 流式结束
signal stream_completed(full_text: String)
## 任意请求出错（兼容旧连接）
signal request_failed(error: String)
## 请求出错，附带 HTTPRequest.Result（非 HTTP 错误时为 HTTP_RESULT_NONE）
signal request_failed_ex(error: String, http_result: int)

var _base_url: String = ""
var _http_request: HTTPRequest
var _stream_http: HTTPClient
var _stream_active := false
var _request_timeout_sec := DEFAULT_TIMEOUT_SEC


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_apply_request_timeout()
	add_child(_http_request)


## 设置单次非流式请求超时（秒）。世界初始化建议 WORLD_INIT_TIMEOUT_SEC。
func set_request_timeout(seconds: float) -> void:
	_request_timeout_sec = maxf(seconds, 1.0)
	_apply_request_timeout()


func reset_request_timeout() -> void:
	set_request_timeout(DEFAULT_TIMEOUT_SEC)


func _apply_request_timeout() -> void:
	if _http_request != null:
		_http_request.timeout = _request_timeout_sec


## 设置后端端口，由 BackendLauncher.backend_ready 回调调用
func set_port(port: int) -> void:
	_base_url = "http://127.0.0.1:%d" % port
	print("[AIClient] 后端地址: ", _base_url)


## 发送非流式对话请求
## messages: [{"role": "user", "content": "你好"}]
func chat(messages: Array, timeout_sec: float = -1.0) -> void:
	if _base_url.is_empty():
		_emit_request_failed("后端地址未设置，请先调用 set_port()", HTTP_RESULT_NONE)
		return

	var prev_timeout := _request_timeout_sec
	if timeout_sec > 0.0:
		set_request_timeout(timeout_sec)

	var body := JSON.stringify({"messages": messages})
	var headers := ["Content-Type: application/json"]
	var url := _base_url + "/api/chat"

	_http_request.request_completed.connect(
		func(result: int, response_code: int, hdrs: PackedStringArray, response_body: PackedByteArray) -> void:
			if timeout_sec > 0.0:
				set_request_timeout(prev_timeout)
			_on_chat_completed(result, response_code, hdrs, response_body),
		CONNECT_ONE_SHOT,
	)
	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		if timeout_sec > 0.0:
			set_request_timeout(prev_timeout)
		_emit_request_failed("发起请求失败: %d" % err, HTTP_RESULT_NONE)


## 发送流式对话请求（使用 HTTPClient 轮询读取）
## messages: [{"role": "user", "content": "你好"}]
func chat_stream(messages: Array) -> void:
	if _base_url.is_empty():
		_emit_request_failed("后端地址未设置，请先调用 set_port()", HTTP_RESULT_NONE)
		return
	if _stream_active:
		_emit_request_failed("上一个流式请求尚未结束", HTTP_RESULT_NONE)
		return

	_stream_active = true
	var body := JSON.stringify({"messages": messages})
	var headers := ["Content-Type: application/json", "Content-Length: %d" % body.to_utf8_buffer().size()]

	_stream_http = HTTPClient.new()
	# 从 _base_url 解析 host 和 port
	var host := "127.0.0.1"
	var port := _base_url.rsplit(":", true, 1)[-1].to_int()

	var err := _stream_http.connect_to_host(host, port)
	if err != OK:
		_stream_active = false
		_emit_request_failed("连接后端失败: %d" % err, HTTP_RESULT_NONE)
		return

	# 等待连接建立
	while _stream_http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		_stream_http.poll()
		await get_tree().process_frame

	if _stream_http.get_status() != HTTPClient.STATUS_CONNECTED:
		_stream_active = false
		_emit_request_failed("无法连接到后端，状态: %d" % _stream_http.get_status(), HTTP_RESULT_NONE)
		return

	# 发送请求
	err = _stream_http.request(HTTPClient.METHOD_POST, "/api/chat/stream", headers, body)
	if err != OK:
		_stream_active = false
		_emit_request_failed("发送流式请求失败: %d" % err, HTTP_RESULT_NONE)
		return

	# 等待响应头
	while _stream_http.get_status() == HTTPClient.STATUS_REQUESTING:
		_stream_http.poll()
		await get_tree().process_frame

	if not _stream_http.has_response():
		_stream_active = false
		_emit_request_failed("后端无响应", HTTP_RESULT_NONE)
		return

	# 读取响应体（流式）
	var full_text := ""
	while _stream_http.get_status() in [HTTPClient.STATUS_BODY, HTTPClient.STATUS_CONNECTED]:
		_stream_http.poll()

		if _stream_http.get_status() == HTTPClient.STATUS_BODY:
			var chunk := _stream_http.read_response_body_chunk()
			if chunk.size() > 0:
				var text := chunk.get_string_from_utf8()
				# 解析 SSE 格式: "data: {...}\n\n"
				for line in text.split("\n"):
					line = line.strip_edges()
					if line.begins_with("data:"):
						var json_str := line.substr(5).strip_edges()
						var parsed = JSON.parse_string(json_str)
						if parsed is Dictionary:
							var delta: String = parsed.get("content", "")
							if not delta.is_empty():
								full_text += delta
								stream_chunk.emit(delta)
					elif line == "[DONE]":
						break
		else:
			await get_tree().process_frame

	_stream_active = false
	stream_completed.emit(full_text)


static func describe_request_result(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "响应分块传输大小不匹配"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "无法连接 AI 后端，请确认后端已启动"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "无法解析 AI 后端地址"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "与 AI 后端的连接异常中断"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS 握手失败"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "AI 后端无响应"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "AI 响应体过大，超过客户端限制"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "AI 响应解压失败"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "AI 请求失败"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "无法打开下载文件"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "下载文件写入失败"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "重定向次数过多"
		HTTPRequest.RESULT_TIMEOUT:
			return "AI 请求超时。世界生成耗时较长，可点击「重试生成」或稍后重试；也可在设置中换用更快模型"
		_:
			return "AI 请求失败（错误码 %d）" % result


static func is_timeout_result(http_result: int) -> bool:
	return http_result == HTTPRequest.RESULT_TIMEOUT


func _emit_request_failed(message: String, http_result: int) -> void:
	push_error("[AIClient] %s (http_result=%d)" % [message, http_result])
	request_failed.emit(message)
	request_failed_ex.emit(message, http_result)


func _on_chat_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_str := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		var detail := describe_request_result(result)
		if not body_str.is_empty():
			push_error("[AIClient] /api/chat body: %s" % AiResponseParser.format_text_preview(body_str, 500))
		_emit_request_failed(detail, result)
		return
	if response_code != 200:
		push_error("[AIClient] /api/chat HTTP %d body: %s" % [response_code, AiResponseParser.format_text_preview(body_str, 800)])
		if response_code == 413:
			_emit_request_failed(
				"世界生成请求过大（HTTP 413），请重试；若仍失败请更新 ai_backend 或缩短已生成设定后重试",
				HTTP_RESULT_NONE,
			)
			return
		_emit_request_failed("HTTP %d: %s" % [response_code, AiResponseParser.format_text_preview(body_str, 200)], HTTP_RESULT_NONE)
		return

	var json = JSON.parse_string(body_str)
	if json is Dictionary:
		var api_err := AiResponseParser.extract_api_error(json as Dictionary)
		if not api_err.is_empty():
			push_error("[AIClient] /api/chat 业务错误: %s" % api_err)
		chat_completed.emit(json)
	else:
		push_error("[AIClient] /api/chat 响应非 JSON body: %s" % AiResponseParser.format_text_preview(body_str, 800))
		_emit_request_failed("响应不是有效的 JSON", HTTP_RESULT_NONE)
