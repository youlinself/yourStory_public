extends VBoxContainer

const VENDORS: Array[Dictionary] = [
	{
		"name": "OpenAI",
		"models_url": "https://api.openai.com/v1/models",
		"website": "https://api.openai.com",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
	},
	{
		"name": "Anthropic",
		"models_url": "https://api.anthropic.com/v1/models",
		"website": "https://api.anthropic.com",
		"auth_header": "x-api-key",
		"auth_prefix": "",
	},
	{
		"name": "DeepSeek",
		"models_url": "https://api.deepseek.com/v1/models",
		"website": "https://api.deepseek.com",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
	},
	{
		"name": "Minimax",
		"models_url": "https://api.minimaxi.com/v1/models",
		"website": "https://api.minimaxi.com",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
	},
	{
		"name": "Mimo",
		"models_url": "https://token-plan-cn.xiaomimimo.com/v1/models",
		"website": "https://token-plan-cn.xiaomimimo.com",
		"auth_header": "api-key",
		"auth_prefix": "",
	},
	{
		"name": "通义千问",
		"models_url": "https://dashscope.aliyuncs.com/compatible-mode/v1/models",
		"website": "https://dashscope.aliyuncs.com/compatible-mode/v1",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
	},
	{
		"name": "智谱 GLM",
		"models_url": "https://open.bigmodel.cn/api/paas/v4/models",
		"website": "https://open.bigmodel.cn/api/paas/v4",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
	},
	{
		"name": "Kimi",
		"models_url": "https://api.moonshot.cn/v1/models",
		"website": "https://api.moonshot.cn",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
	},
	# {
	# 	"name": "豆包",
	# 	"models_url": "https://ark.cn-beijing.volces.com/api/v3/models",
	# 	"website": "https://ark.cn-beijing.volces.com/api/v3",
	# 	"auth_header": "Authorization",
	# 	"auth_prefix": "Bearer ",
	# },
	{
		"name": "SiliconFlow",
		"models_url": "https://api.siliconflow.cn/v1/models",
		"website": "https://api.siliconflow.cn",
		"auth_header": "Authorization",
		"auth_prefix": "Bearer ",
	},
	{
		"name": "其他",
		"models_url": "",
		"website": "",
		"auth_header": "",
		"auth_prefix": "",
	},
]

@onready var _vendor_option: OptionButton = %VendorOption
@onready var _website_input: LineEdit = %WebsiteInput
@onready var _models_url_input: LineEdit = %ModelsUrlInput
@onready var _auth_header_input: LineEdit = %AuthHeaderInput
@onready var _auth_prefix_input: LineEdit = %AuthPrefixInput
@onready var _api_key_input: LineEdit = %APIKeyInput
@onready var _test_button: Button = %TestButton
@onready var _model_option: OptionButton = %ModelOption
@onready var _reasoning_option: OptionButton = %ReasoningEffortOption
@onready var _http_request: HTTPRequest = %HttpRequest

func _ready() -> void:
	for vendor in VENDORS:
		_vendor_option.add_item(vendor["name"])

	_reasoning_option.add_item("low")
	_reasoning_option.add_item("medium")
	_reasoning_option.add_item("high")
	_reasoning_option.select(1)

	_vendor_option.item_selected.connect(_on_vendor_changed)
	_test_button.pressed.connect(_on_test_pressed)
	_http_request.request_completed.connect(_on_request_completed)

	_on_vendor_changed(0)

func _on_vendor_changed(idx: int) -> void:
	if idx < 0 or idx >= VENDORS.size():
		return
	_apply_vendor_defaults(VENDORS[idx])

func _apply_vendor_defaults(vendor: Dictionary) -> void:
	_website_input.text = vendor.get("website", "")
	_models_url_input.text = vendor.get("models_url", "")
	_auth_header_input.text = vendor.get("auth_header", "")
	_auth_prefix_input.text = vendor.get("auth_prefix", "")

func _get_connection_config() -> Dictionary:
	return {
		"website": _website_input.text.strip_edges(),
		"models_url": _models_url_input.text.strip_edges(),
		"auth_header": _auth_header_input.text.strip_edges(),
		"auth_prefix": _auth_prefix_input.text,
	}

func _on_test_pressed() -> void:
	if _test_button.disabled:
		return

	var api_key := _api_key_input.text.strip_edges()
	if api_key.is_empty():
		print_rich("[color=yellow]AI 设置: 请先输入 API Key[/color]")
		return

	var conn := _get_connection_config()
	if conn["models_url"].is_empty():
		print_rich("[color=yellow]AI 设置: 请先填写模型列表 URL[/color]")
		return
	if conn["auth_header"].is_empty():
		print_rich("[color=yellow]AI 设置: 请先填写认证 Header[/color]")
		return

	var headers := [conn["auth_header"] + ": " + conn["auth_prefix"] + api_key]

	_test_button.disabled = true
	_test_button.text = "测试中..."
	_model_option.clear()
	_model_option.add_item("加载中...")
	_model_option.disabled = true

	var error := _http_request.request(conn["models_url"], headers)
	if error != OK:
		_on_test_failed("请求发送失败: %d" % error)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_test_button.disabled = false
	_test_button.text = "测试"
	_model_option.clear()
	_model_option.disabled = false

	if result != HTTPRequest.RESULT_SUCCESS:
		_on_test_failed("网络请求失败 (%d)" % result)
		return

	if response_code != 200:
		_on_test_failed("服务器返回 HTTP %d" % response_code)
		return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json.has("data"):
		_on_test_failed("无法解析模型列表")
		return

	var models := json["data"] as Array
	if models.is_empty():
		_on_test_failed("未找到可用模型")
		return

	for model in models:
		if model.has("id"):
			_model_option.add_item(model["id"])

func _on_test_failed(msg: String) -> void:
	_test_button.disabled = false
	_test_button.text = "测试"
	_model_option.clear()
	_model_option.disabled = false
	_model_option.add_item("获取失败: %s" % msg)
	print_rich("[color=red]AI 设置: %s[/color]" % msg)


func get_config() -> Dictionary:
	var vendor_name := ""
	var vendor_idx := _vendor_option.selected
	if vendor_idx >= 0 and vendor_idx < VENDORS.size():
		vendor_name = VENDORS[vendor_idx]["name"]

	var model_name := ""
	var model_idx := _model_option.selected
	if model_idx >= 0 and model_idx < _model_option.item_count:
		model_name = _model_option.get_item_text(model_idx)

	var config := _get_connection_config()
	config["vendor"] = vendor_name
	config["api_key"] = _api_key_input.text
	config["model"] = model_name
	config["reasoning_effort"] = _reasoning_option.get_item_text(_reasoning_option.selected)
	return config


func set_config(data: Dictionary) -> void:
	if data.is_empty():
		return

	if data.has("vendor"):
		for i in _vendor_option.item_count:
			if _vendor_option.get_item_text(i) == data["vendor"]:
				_vendor_option.select(i)
				_on_vendor_changed(i)
				break

	if data.has("website") and data["website"] is String:
		_website_input.text = data["website"]

	if data.has("models_url") and data["models_url"] is String:
		_models_url_input.text = data["models_url"]

	if data.has("auth_header") and data["auth_header"] is String:
		_auth_header_input.text = data["auth_header"]

	if data.has("auth_prefix") and data["auth_prefix"] is String:
		_auth_prefix_input.text = data["auth_prefix"]

	if data.has("api_key") and data["api_key"] is String:
		_api_key_input.text = data["api_key"]

	if data.has("model") and data["model"] is String and not data["model"].is_empty():
		var model_name: String = data["model"]
		var found := false
		for i in _model_option.item_count:
			if _model_option.get_item_text(i) == model_name:
				_model_option.select(i)
				found = true
				break
		if not found:
			_model_option.add_item(model_name)
			_model_option.select(_model_option.item_count - 1)

	if data.has("reasoning_effort") and data["reasoning_effort"] is String:
		var effort: String = data["reasoning_effort"]
		for i in _reasoning_option.item_count:
			if _reasoning_option.get_item_text(i) == effort:
				_reasoning_option.select(i)
				break
