class_name DynamicAddTriggerParser
extends RefCounted

## 解析叙事回复中的 [[DYN_ADD:分类|来源说明]] 标记。

const TRIGGER_PATTERN := "\\[\\[DYN_ADD:([^|\\]]+)(?:\\|([^\\]]*))?\\]\\]"

const DynamicAddRegistry = preload("res://src/ai_skills/dynamic_add_registry.gd")

class TriggerRequest:
	var schema_id: String = ""
	var category_raw: String = ""
	var source_context: String = ""
	var match_start: int = 0
	var match_end: int = 0
	var raw_token: String = ""
	var request_index: int = -1


## 按单次上限拆分；accepted 保留顺序并写入 request_index。
static func partition_by_limit(requests: Array, max_count: int) -> Dictionary:
	var limit := maxi(1, max_count)
	var accepted: Array = []
	var overflow: Array = []
	for i in range(requests.size()):
		var req: TriggerRequest = requests[i]
		if i < limit:
			req.request_index = accepted.size()
			accepted.append(req)
		else:
			overflow.append(req)
	return {"accepted": accepted, "overflow": overflow, "max_count": limit}


static func find_all(text: String) -> Array:
	var requests: Array = []
	var regex := RegEx.new()
	if regex.compile(TRIGGER_PATTERN) != OK:
		push_error("DYN_ADD 正则编译失败")
		return requests

	var from := 0
	while true:
		var m := regex.search(text, from)
		if m == null:
			break
		var req := TriggerRequest.new()
		req.category_raw = m.get_string(1).strip_edges()
		req.source_context = m.get_string(2).strip_edges() if m.get_string_count() > 2 else ""
		req.schema_id = DynamicAddRegistry.resolve_schema_id(req.category_raw)
		req.match_start = m.get_start()
		req.match_end = m.get_end()
		req.raw_token = text.substr(req.match_start, req.match_end - req.match_start)
		requests.append(req)
		from = req.match_end
	return requests


static func strip_tokens(text: String) -> String:
	var regex := RegEx.new()
	if regex.compile(TRIGGER_PATTERN) != OK:
		return text
	var result := regex.sub(text, "", true)
	while "\n\n\n" in result:
		result = result.replace("\n\n\n", "\n\n")
	return result.strip_edges()


static func replace_tokens(text: String, replacements: Dictionary) -> String:
	## replacements: raw_token -> replacement string
	var out := text
	for req in find_all(text):
		if replacements.has(req.raw_token):
			out = out.replace(req.raw_token, str(replacements[req.raw_token]))
	return out
