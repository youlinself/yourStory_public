class_name GameWorldInitializer
extends Node

const WorldInitDraftScript := preload("res://src/novel_config/world_init_draft.gd")
const BaseConfigDraftScript := preload("res://src/novel_config/base_config_draft.gd")
const SkillsDbDraftScript := preload("res://src/novel_config/skills_db_draft.gd")
const AiPromptComposerScript := preload("res://src/ai_config/ai_prompt_composer.gd")
const ItemSettingGuardScript := preload("res://src/game/logic/data/item_setting_guard.gd")
const ItemGenerationAgentScript := preload("res://src/ai_skills/item_generation_agent.gd")

signal phase_started(phase: int, label: String)
signal phase_completed(phase: int)
signal initialization_completed
signal initialization_failed(reason: String)
## reason 为错误说明；http_result 为 HTTPRequest.Result，非 HTTP 错误时为 AIClient.HTTP_RESULT_NONE
signal initialization_failed_ex(reason: String, http_result: int)

const PHASE_LABELS: Array[String] = [
	"正在生成冒险基调…",
	"正在生成行动标签…",
	"正在构建第一场冒险…",
]

const WORLD_BUILD_AI_LOOP_GUARD := 48

var _ai_client: AIClient
var _item_agent: ItemGenerationAgentScript
var _running := false
var _selected_novel_type: String = ""


func _init() -> void:
	_ai_client = AIClient.new()
	_item_agent = ItemGenerationAgentScript.new()


func _ready() -> void:
	add_child(_ai_client)
	add_child(_item_agent)
	_item_agent.set_request_ai_callable(_wrap_item_agent_ai_request)


func is_running() -> bool:
	return _running


func run(port: int, novel_type: String = "") -> void:
	if _running:
		_finish_fail("世界初始化正在进行中")
		return
	if port <= 0:
		_finish_fail("后端端口无效")
		return

	_selected_novel_type = novel_type.strip_edges()
	if _selected_novel_type.is_empty():
		_finish_fail("小说类型未指定")
		return

	_running = true
	_ai_client.set_port(port)
	_item_agent.set_port(port)
	_ai_client.set_request_timeout(AIClient.WORLD_INIT_TIMEOUT_SEC)

	if not GameRunningFileManager.ensure_dir():
		_abort_run("无法创建运行时数据目录")
		return
	if GameRunningFileManager.has_playable_save():
		if not GameHistoryService.archive_current_session():
			_abort_run("无法归档上一局游戏记录")
			return
	if not GameRunningFileManager.clear_all_runtime_files():
		_abort_run("无法清空旧的游戏运行时数据")
		return

	var ok: bool = await _run_phases(1)
	_running = false
	_ai_client.reset_request_timeout()
	if ok:
		initialization_completed.emit()
	else:
		pass


func run_retry(port: int, novel_type: String = "") -> void:
	if _running:
		_finish_fail("世界初始化正在进行中")
		return
	if port <= 0:
		_finish_fail("后端端口无效")
		return

	_selected_novel_type = novel_type.strip_edges()
	if _selected_novel_type.is_empty():
		_finish_fail("小说类型未指定")
		return

	_running = true
	_ai_client.set_port(port)
	_item_agent.set_port(port)
	_ai_client.set_request_timeout(AIClient.WORLD_INIT_TIMEOUT_SEC)

	if not GameRunningFileManager.ensure_dir():
		_abort_run("无法创建运行时数据目录")
		return

	var start_phase := detect_start_phase(_selected_novel_type)
	if start_phase == 1:
		if not _prepare_phase1_retry():
			_abort_run("无法清理阶段 1 待重试数据")
			return
	elif start_phase == 2:
		if not _prepare_phase2_retry():
			_abort_run("无法清理待重试阶段的运行时数据")
			return
	elif start_phase == 3:
		if not _prepare_phase3_retry():
			_abort_run("无法清理阶段 3 待重试数据")
			return

	var ok: bool = await _run_phases(start_phase)
	_running = false
	_ai_client.reset_request_timeout()
	if ok:
		initialization_completed.emit()


## 返回第一个需要重新 AI 生成的阶段（1–3）。
static func detect_start_phase(novel_type: String) -> int:
	var selected := novel_type.strip_edges()
	if load_validated_base_config(selected) == null:
		return 1
	if load_validated_skills_db() == null:
		return 2
	return 3


static func load_validated_base_config(novel_type: String) -> Variant:
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.BASE_CONFIG)
	if not loaded is Dictionary:
		return null
	var data: Dictionary = loaded as Dictionary
	if not AiResponseParser.validate_base_config(data):
		return null
	var on_disk := str(data.get("novel_type", "")).strip_edges()
	if on_disk != novel_type.strip_edges():
		return null
	return data


static func load_validated_skills_db() -> Variant:
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.SKILLS_DB)
	var skills_db: Dictionary = RuntimeDbSchemas.normalize_skills_db(loaded)
	var skills_map: Variant = skills_db.get("skills", {})
	if not skills_map is Dictionary:
		return null
	if (skills_map as Dictionary).is_empty():
		return null
	return skills_db


## 阶段 3 子步骤续跑起点（1–4），供 UI 展示。
static func detect_resume_world_substep() -> int:
	return WorldInitDraftScript.detect_next_substep(WorldInitDraftScript.load_or_empty())


## 阶段 1 分片续跑起点（1–3），供 UI 展示。
static func detect_resume_base_slice() -> int:
	var draft := BaseConfigDraftScript.load_or_empty()
	if draft.is_empty():
		return BaseConfigDraftScript.SLICE_NATURE_ENV
	return BaseConfigDraftScript.detect_next_slice(draft)


## 阶段 2 批次续跑起点（1–3），供 UI 展示。
static func detect_resume_skills_batch() -> int:
	var draft := SkillsDbDraftScript.load_or_empty()
	if draft.is_empty():
		return SkillsDbDraftScript.BATCH_COMBAT
	return SkillsDbDraftScript.detect_next_batch(draft)


func _prepare_phase1_retry() -> bool:
	var draft := BaseConfigDraftScript.load_or_empty()
	var on_disk := str(draft.get(BaseConfigDraftScript.KEY_NOVEL_TYPE, "")).strip_edges()
	if (
		not draft.is_empty()
		and on_disk == _selected_novel_type
		and BaseConfigDraftScript.has_meaningful_checkpoint(draft)
	):
		var slice := BaseConfigDraftScript.detect_next_slice(draft)
		BaseConfigDraftScript.clear_from_slice(draft, slice)
		return BaseConfigDraftScript.save(draft)
	return GameRunningFileManager.clear_all_runtime_files()


func _prepare_phase2_retry() -> bool:
	if not GameRunningFileManager.clear_from_phase(2):
		return false
	var draft := SkillsDbDraftScript.load_or_empty()
	if draft.is_empty() or SkillsDbDraftScript.detect_next_batch(draft) <= SkillsDbDraftScript.BATCH_COMBAT:
		return true
	var batch := SkillsDbDraftScript.detect_next_batch(draft)
	SkillsDbDraftScript.clear_from_batch(draft, batch)
	return SkillsDbDraftScript.save(draft)


func _prepare_phase3_retry() -> bool:
	var draft := WorldInitDraftScript.load_or_empty()
	var sub := WorldInitDraftScript.detect_next_substep(draft)
	if sub <= 1 and not WorldInitDraftScript.has_meaningful_checkpoint(draft):
		return GameRunningFileManager.clear_from_phase(3)
	if not GameRunningFileManager.clear_phase3_final_outputs():
		return false
	WorldInitDraftScript.clear_from_substep(draft, sub)
	return WorldInitDraftScript.save(draft)


func _run_phases(start_phase: int = 1) -> bool:
	var base_config: Variant = null
	var skills_db: Variant = null

	if start_phase <= 1:
		base_config = await _phase_base_config()
		if base_config == null:
			return false
		phase_completed.emit(1)
	else:
		base_config = load_validated_base_config(_selected_novel_type)
		if base_config == null:
			_finish_fail("无法复用 baseConfig 检查点，请重抽主题或返回主菜单")
			return false

	if start_phase <= 2:
		skills_db = await _phase_skills_db(base_config)
		if skills_db == null:
			return false
		phase_completed.emit(2)
	else:
		skills_db = load_validated_skills_db()
		if skills_db == null:
			_finish_fail("无法复用 skills_db 检查点，请重抽主题或返回主菜单")
			return false

	if not await _phase_world_build(base_config, skills_db):
		return false
	phase_completed.emit(3)

	return true


func _phase_base_config() -> Variant:
	var draft := BaseConfigDraftScript.load_or_empty()
	var on_disk_type := str(draft.get(BaseConfigDraftScript.KEY_NOVEL_TYPE, "")).strip_edges()
	if draft.is_empty() or on_disk_type != _selected_novel_type:
		draft = BaseConfigDraftScript.empty_draft(_selected_novel_type)

	var loop_guard := 0
	while loop_guard < 12:
		loop_guard += 1
		var slice := BaseConfigDraftScript.detect_next_slice(draft)
		if slice > BaseConfigDraftScript.SLICE_COUNT:
			break

		var label := "%s (%d/%d)" % [
			BaseConfigDraftScript.slice_label(slice),
			slice,
			BaseConfigDraftScript.SLICE_COUNT,
		]
		phase_started.emit(1, label)

		var prompt := PromptBuilder.build_base_slice_prompt(
			_selected_novel_type,
			slice,
			BaseConfigDraftScript.completed_slices_json(draft),
		)
		if prompt.is_empty():
			_finish_fail("无法构建阶段 1 分片 %d 提示词" % slice)
			return null

		var parsed: Variant = await _request_and_parse_base_slice_json(prompt, slice)
		if parsed == null:
			return null

		if not parsed is Dictionary:
			_finish_fail(AiResponseParser.describe_base_config_slice_failure(slice, true))
			return null

		var field_key: String = BaseConfigDraftScript.SLICE_FIELD_KEYS[slice]
		var wrapped: Dictionary = {field_key: (parsed as Dictionary).get(field_key, null)}
		if not AiResponseParser.validate_base_config_slice(slice, wrapped):
			var slice_err := AiResponseParser.describe_base_config_slice_validation_failure(
				slice, wrapped,
			)
			var retry_prompt := prompt + build_ai_retry_suffix(slice_err, [])
			parsed = await _request_and_parse_base_slice_json(retry_prompt, slice)
			if parsed == null:
				return null
			if not parsed is Dictionary:
				_finish_fail(AiResponseParser.describe_base_config_slice_failure(slice, true))
				return null
			wrapped = {field_key: (parsed as Dictionary).get(field_key, null)}
			if not AiResponseParser.validate_base_config_slice(slice, wrapped):
				_finish_fail(
					AiResponseParser.describe_base_config_slice_validation_failure(slice, wrapped),
				)
				return null
		var section_val: Variant = wrapped[field_key]

		BaseConfigDraftScript.apply_slice(draft, slice, section_val as Dictionary)
		if not BaseConfigDraftScript.save(draft):
			_finish_fail("无法保存 base_config_draft.json")
			return null

	var data: Dictionary = BaseConfigDraftScript.to_base_config(draft)
	data = AiResponseParser.normalize_base_config_response(data, _selected_novel_type)
	if not AiResponseParser.validate_base_config(data):
		_finish_fail(AiResponseParser.describe_base_config_validation_failure(data, true))
		return null

	var returned_type := str(data.get("novel_type", "")).strip_edges()
	if returned_type != _selected_novel_type:
		_finish_fail("阶段 1 AI 返回的 novel_type 与选定主题不一致")
		return null

	if not GameRunningFileManager.save_json_data(GameRunningFileManager.BASE_CONFIG, data):
		_finish_fail("无法保存 baseConfig.json")
		return null

	if not BaseConfigDraftScript.delete_file():
		push_warning("[GameWorldInitializer] 无法删除 base_config_draft.json")

	return data


func _request_and_parse_base_slice_json(prompt: String, slice: int) -> Variant:
	var context_label := "阶段 1 分片 %d" % slice
	var raw := await _request_ai(prompt, -1.0, context_label)
	if raw.is_empty():
		return null

	var parsed: Variant = _parse_base_slice_ai_payload(slice, raw)
	if parsed != null:
		return parsed

	var retry_prompt := prompt + build_ai_retry_suffix(
		"JSON 解析失败（无法从回复中提取合法对象）",
		PackedStringArray([
			"请严格按任务说明只输出**一个完整且闭合**的 JSON 对象。",
		]),
	)
	raw = await _request_ai(retry_prompt, -1.0, context_label + "（重试）")
	if raw.is_empty():
		return null

	parsed = _parse_base_slice_ai_payload(slice, raw)
	if parsed == null:
		_log_json_parse_failure(context_label, raw)
		_finish_fail(AiResponseParser.describe_base_config_slice_failure(slice, false))
	return parsed


func _parse_base_slice_ai_payload(slice: int, raw: String) -> Variant:
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if parsed == null:
		return null
	return AiResponseParser.normalize_base_config_slice_payload(slice, parsed)


func _phase_skills_db(base_config: Variant) -> Variant:
	var base_text := PromptBuilder.compact_base_config_json(base_config)
	var draft := SkillsDbDraftScript.load_or_empty()
	if draft.is_empty():
		draft = SkillsDbDraftScript.empty_draft()

	var loop_guard := 0
	while loop_guard < 12:
		loop_guard += 1
		var batch := SkillsDbDraftScript.detect_next_batch(draft)
		if batch > SkillsDbDraftScript.BATCH_COUNT:
			break

		var label := "%s (%d/%d)" % [
			SkillsDbDraftScript.batch_label(batch),
			batch,
			SkillsDbDraftScript.BATCH_COUNT,
		]
		phase_started.emit(2, label)

		var prompt := PromptBuilder.build_skill_batch_prompt(
			base_text,
			batch,
			SkillsDbDraftScript.existing_skill_ids_json(draft),
		)
		if prompt.is_empty():
			_finish_fail("无法构建阶段 2 批次 %d 提示词" % batch)
			return null

		var parsed: Variant = await _request_and_parse_skills_batch_json(prompt, batch)
		if parsed == null:
			return null

		if not AiResponseParser.validate_skills_batch_payload(parsed):
			_finish_fail(AiResponseParser.describe_skills_batch_failure(batch, parsed != null, parsed))
			return null

		var skills_array: Array = AiResponseParser.extract_skills_array(parsed as Dictionary)
		SkillsDbDraftScript.append_batch(draft, batch, skills_array)
		if not SkillsDbDraftScript.save(draft):
			_finish_fail("无法保存 skills_db_draft.json")
			return null

	var payload := SkillsDbDraftScript.to_skills_payload(draft)
	if SkillsDbDraftScript.skill_count(draft) < SkillsDbDraftScript.MIN_TOTAL_SKILLS:
		_finish_fail("阶段 2 技能库总数不足（至少需要 %d 个）" % SkillsDbDraftScript.MIN_TOTAL_SKILLS)
		return null

	if not AiResponseParser.validate_skills_payload(payload):
		_finish_fail(AiResponseParser.describe_skills_validation_failure(payload, true))
		return null

	var skills_db: Dictionary = RuntimeDbSchemas.skills_array_to_db(
		AiResponseParser.extract_skills_array(payload),
	)
	if skills_db["skills"].is_empty():
		_finish_fail("阶段 2 技能库为空")
		return null

	if not GameRunningFileManager.save_json_data(GameRunningFileManager.SKILLS_DB, skills_db):
		_finish_fail("无法保存 skills_db.json")
		return null

	if not SkillsDbDraftScript.delete_file():
		push_warning("[GameWorldInitializer] 无法删除 skills_db_draft.json")

	return skills_db


func _request_and_parse_skills_batch_json(prompt: String, batch: int) -> Variant:
	var context_label := "阶段 2 批次 %d" % batch
	var raw := await _request_ai(prompt, -1.0, context_label)
	if raw.is_empty():
		return null

	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if parsed != null and AiResponseParser.validate_skills_batch_payload(parsed):
		return parsed

	var batch_reason := "AI 返回的内容无法解析为 JSON"
	if parsed != null:
		batch_reason = AiResponseParser.describe_skills_batch_validation_failure(parsed)
	var batch_hints := PackedStringArray([
		"请严格输出 `{ \"skills\": [{ \"id\", \"name\", \"desc\" }, ...] }`。",
		"顶层为对象、skills 为 3–5 项数组、每项含非空 id/name/desc（禁止 description 别名、禁止对象 map、禁止一次 8–15 项）。",
	])
	var retry_prompt := prompt + build_ai_retry_suffix(batch_reason, batch_hints)
	raw = await _request_ai(retry_prompt, -1.0, context_label + "（重试）")
	if raw.is_empty():
		return null

	parsed = AiResponseParser.parse_json_from_ai_text(raw)
	if parsed == null:
		_log_json_parse_failure(context_label, raw)
		_finish_fail(AiResponseParser.describe_skills_batch_failure(batch, false))
		return null
	if not AiResponseParser.validate_skills_batch_payload(parsed):
		_finish_fail(
			AiResponseParser.describe_skills_batch_failure(batch, true, parsed),
		)
		return null
	return parsed


func _phase_world_build(base_config: Variant, skills_db: Variant) -> bool:
	var draft := WorldInitDraftScript.load_or_empty()
	if draft.is_empty():
		draft = WorldInitDraftScript.empty_draft()

	var loop_guard := 0
	while loop_guard < WORLD_BUILD_AI_LOOP_GUARD:
		loop_guard += 1
		var sub := WorldInitDraftScript.detect_next_substep(draft)
		if sub >= WorldInitDraftScript.SUB_FINALIZE:
			var finalize_label := "%s (%d/%d)" % [
				WorldInitDraftScript.substep_label(sub, draft),
				sub,
				WorldInitDraftScript.SUBSTEP_COUNT,
			]
			phase_started.emit(3, finalize_label)
			if not _finalize_world_init(draft, base_config, skills_db):
				return false
			return true

		var label := "%s (%d/%d)" % [
			WorldInitDraftScript.substep_label(sub, draft),
			sub,
			WorldInitDraftScript.SUBSTEP_COUNT,
		]
		phase_started.emit(3, label)
		var sub_ok := false
		if sub == WorldInitDraftScript.SUB_STARTER_ITEMS:
			sub_ok = await _run_starter_items_substep(draft, base_config)
		else:
			sub_ok = await _run_world_build_substep(sub, draft, base_config, skills_db)
		if not sub_ok:
			return false
		if not WorldInitDraftScript.save(draft):
			_finish_fail("无法保存 world_init_draft.json")
			return false

	_finish_fail("阶段 3 子步骤循环次数过多，请重试生成")
	return false


func _run_starter_items_substep(draft: Dictionary, base_config: Variant) -> bool:
	var world_init := WorldInitDraftScript.to_world_init(draft)
	var npc_db := RuntimeDbSchemas.build_npc_db(world_init)
	var requests := ItemGenerationAgentScript.collect_from_npc_db(
		npc_db,
		world_init,
		base_config as Dictionary,
	)
	if requests.is_empty():
		WorldInitDraftScript.mark_starter_items_materialized(draft)
		return true

	var world_context := PromptBuilder.compact_base_config_json(base_config)
	for i in range(requests.size()):
		if requests[i] is Dictionary:
			(requests[i] as Dictionary)["request_index"] = i

	var results: Array = await _item_agent.generate_batch(requests, world_context)
	var failures: PackedStringArray = []
	for item in results:
		if not item is Dictionary:
			continue
		if not (item as Dictionary).get("ok", false):
			failures.append(str((item as Dictionary).get("error", "未知错误")))

	if not failures.is_empty():
		_finish_fail(
			AiResponseParser.describe_world_build_substep_failure(
				WorldInitDraftScript.SUB_STARTER_ITEMS,
				"；".join(failures),
			),
		)
		return false

	WorldInitDraftScript.mark_starter_items_materialized(draft)
	return true


func _wrap_item_agent_ai_request(messages: Array) -> String:
	return await _request_ai_messages(
		messages,
		AIClient.WORLD_BUILD_SUBSTEP_TIMEOUT_SEC,
		"初始物品生成",
	)


func _run_world_build_substep(
	sub: int,
	draft: Dictionary,
	base_config: Variant,
	skills_db: Variant,
) -> bool:
	var base_text := PromptBuilder.compact_base_config_json(base_config)
	var skills_text := PromptBuilder.compact_skills_db_json(skills_db)
	var map_text := PromptBuilder.compact_map_structure_json(draft.get(WorldInitDraftScript.KEY_MAP, {}))
	var adventure_text := PromptBuilder.compact_adventure_module_json(
		draft.get(WorldInitDraftScript.KEY_ADVENTURE, {}),
	)

	var prompt := ""
	match sub:
		WorldInitDraftScript.SUB_MAP_SKELETON:
			prompt = PromptBuilder.build_world_map_skeleton_prompt(base_text)
		WorldInitDraftScript.SUB_MAP_PAGE:
			var region_id := WorldInitDraftScript.next_map_page_region_id(draft)
			if region_id.is_empty():
				_finish_fail(
					AiResponseParser.describe_world_build_substep_failure(sub, "无待生成的区域地图页"),
				)
				return false
			var region := WorldInitDraftScript.region_by_id(draft, region_id)
			var key_nodes := WorldInitDraftScript.key_nodes_for_region(draft, region_id)
			prompt = PromptBuilder.build_world_map_page_prompt(
				base_text,
				map_text,
				JSON.stringify(region),
				JSON.stringify(key_nodes),
			)
		WorldInitDraftScript.SUB_ADVENTURE:
			prompt = PromptBuilder.build_world_adventure_module_prompt(base_text, map_text)
		WorldInitDraftScript.SUB_FACTION_SHADOWS:
			prompt = PromptBuilder.build_world_faction_shadows_prompt(
				base_text, map_text, adventure_text,
			)
		WorldInitDraftScript.SUB_PROTAGONIST:
			prompt = PromptBuilder.build_world_protagonist_prompt(
				base_text, skills_text, map_text, adventure_text,
			)
		WorldInitDraftScript.SUB_KEY_NPC:
			prompt = PromptBuilder.build_world_key_npc_single_prompt(
				base_text,
				skills_text,
				map_text,
				adventure_text,
				JSON.stringify(WorldInitDraftScript.collect_existing_npc_ids(draft)),
			)
		_:
			_finish_fail("无效的世界构建子步骤: %d" % sub)
			return false

	if prompt.is_empty():
		_finish_fail("无法构建阶段 3 子步 %d 提示词" % sub)
		return false

	var parsed: Variant = await _request_and_parse_world_build_json(
		prompt,
		sub,
		AIClient.WORLD_BUILD_SUBSTEP_TIMEOUT_SEC,
		skills_db,
	)
	if parsed == null:
		return false

	var apply_err := _describe_world_build_apply_failure(sub, parsed, skills_db, draft, base_config)
	if not apply_err.is_empty():
		var retry_prompt := prompt + _world_build_validation_retry_suffix(sub, apply_err)
		parsed = await _request_and_parse_world_build_json(
			retry_prompt,
			sub,
			AIClient.WORLD_BUILD_SUBSTEP_TIMEOUT_SEC,
			skills_db,
		)
		if parsed == null:
			return false
		apply_err = _describe_world_build_apply_failure(sub, parsed, skills_db, draft, base_config)
		if not apply_err.is_empty():
			_finish_fail(AiResponseParser.describe_world_build_substep_failure(sub, apply_err))
			return false

	return _commit_world_build_substep(sub, draft, parsed, skills_db, base_config)


func _request_and_parse_world_build_json(
	prompt: String,
	sub: int,
	timeout_sec: float,
	skills_db: Variant = null,
) -> Variant:
	var context_label := "阶段 3 子步 %d" % sub
	var raw := await _request_ai(prompt, timeout_sec, context_label)
	if raw.is_empty():
		return null

	var parsed: Variant = _parse_world_build_ai_payload(sub, raw, skills_db)
	if parsed != null:
		return parsed

	var json_hints := _world_build_json_parse_hint_lines(sub)
	var retry_prompt := prompt + build_ai_retry_suffix(
		"JSON 解析失败（无法从回复中提取合法对象）",
		json_hints,
	)
	raw = await _request_ai(retry_prompt, timeout_sec, context_label + "（重试）")
	if raw.is_empty():
		return null

	parsed = _parse_world_build_ai_payload(sub, raw, skills_db)
	if parsed == null:
		_log_json_parse_failure(context_label, raw)
		_finish_fail(
			AiResponseParser.describe_world_build_substep_failure(sub, "AI 返回的内容无法解析为 JSON"),
		)
	return parsed


func _parse_world_build_ai_payload(sub: int, raw: String, skills_db: Variant = null) -> Variant:
	var parsed: Variant = AiResponseParser.parse_json_from_ai_text(raw)
	if parsed == null:
		return null
	return AiResponseParser.normalize_world_build_substep_payload(sub, parsed, skills_db)


static func build_ai_retry_suffix(reason: String, extra_hints: PackedStringArray = []) -> String:
	var lines: PackedStringArray = [
		"",
		"## 重试",
		"上次输出未通过：%s" % reason.strip_edges(),
		"请修正后重新输出**一个完整且闭合**的 JSON 对象：整段回复必须以 `{` 开头、以 `}` 结尾。",
		"- 禁止 Markdown ``` 围栏、前后说明、注释、尾随逗号与 `...` 占位。",
	]
	for hint in extra_hints:
		var h := str(hint).strip_edges()
		if h.is_empty():
			continue
		if h.begins_with("- "):
			lines.append(h)
		else:
			lines.append("- %s" % h)
	return "\n".join(lines)


func _world_build_validation_retry_suffix(sub: int, apply_err: String) -> String:
	var hints := _world_build_role_card_retry_hints(sub)
	return build_ai_retry_suffix(apply_err, hints)


func _world_build_json_parse_hint_lines(sub: int) -> PackedStringArray:
	var lines: PackedStringArray = [
		"请严格按任务说明只输出**一个完整且闭合**的 JSON 对象。",
		"整段回复必须以 `{` 开头、以 `}` 结尾；中间不得有任何说明文字或 Markdown ``` 围栏。",
		"禁止：注释、尾随逗号、`...` 占位、单引号键名。",
	]
	lines.append_array(_world_build_role_card_retry_hints(sub))
	return lines


func _world_build_role_card_retry_hints(sub: int) -> PackedStringArray:
	var lines: PackedStringArray = []
	_append_role_card_retry_hints(sub, lines)
	return lines


func _append_role_card_retry_hints(sub: int, lines: PackedStringArray) -> void:
	if sub == WorldInitDraftScript.SUB_PROTAGONIST:
		lines.append("- 顶层须含 `protagonist_id` 与 `npcs`（**仅 1 条**）；二者 id 须完全一致。")
		lines.append("- `npcs[0].skills` 须为技能库中的 **id** 字符串（1–6 个），禁止中文名或 `{id,name}` 对象。")
		lines.append("- `npcs[0]` 须含非空 `性别`、`族群`、`initial_scene`。")
	elif sub == WorldInitDraftScript.SUB_KEY_NPC:
		lines.append("- 顶层**仅**含 `npcs` 数组（**1 条**），`id` 不得与已有 NPC 重复。")
		lines.append("- `npcs[0].skills` 须为技能库中的 **id** 字符串（1–6 个），禁止中文名或 `{id,name}` 对象。")
		lines.append("- `npcs[0]` 须含非空 `current_region_id`、`initial_scene`。")


func _describe_world_build_apply_failure(
	sub: int,
	parsed: Variant,
	skills_db: Variant,
	draft: Dictionary,
	base_config: Variant,
) -> String:
	match sub:
		WorldInitDraftScript.SUB_PROTAGONIST:
			var protagonist_err := AiResponseParser.describe_protagonist_validation_failure(
				parsed, skills_db,
			)
			if not protagonist_err.is_empty():
				return protagonist_err
			if parsed is Dictionary:
				var pdata: Dictionary = parsed as Dictionary
				var pnpcs: Variant = pdata.get("npcs", [])
				if pnpcs is Array and not pnpcs.is_empty() and pnpcs[0] is Dictionary:
					if base_config is Dictionary:
						var item_err := ItemSettingGuardScript.validate_starter_items(
							pnpcs[0] as Dictionary,
							base_config as Dictionary,
						)
						if not item_err.is_empty():
							return item_err
		WorldInitDraftScript.SUB_KEY_NPC:
			var existing: Array[String] = WorldInitDraftScript.collect_existing_npc_ids(draft)
			return AiResponseParser.describe_single_key_npc_validation_failure(
				parsed, skills_db, existing,
			)
		WorldInitDraftScript.SUB_MAP_SKELETON:
			if not parsed is Dictionary:
				return "须为 JSON 对象"
			var map_val: Variant = (parsed as Dictionary).get("map_structure", null)
			if not AiResponseParser.validate_map_skeleton(map_val):
				return "地图骨架无效"
		WorldInitDraftScript.SUB_MAP_PAGE:
			if not parsed is Dictionary:
				return "须为 JSON 对象"
			var page_val: Variant = (parsed as Dictionary).get("map_page", null)
			var region_id := WorldInitDraftScript.next_map_page_region_id(draft)
			if region_id.is_empty():
				return "无待生成的区域地图页"
			if not AiResponseParser.validate_region_map_page(
				draft.get(WorldInitDraftScript.KEY_MAP, {}),
				page_val,
				region_id,
			):
				return "区域地图页无效或未绑定全部 key_node"
		WorldInitDraftScript.SUB_ADVENTURE:
			if not parsed is Dictionary:
				return "须为 JSON 对象"
			var adventure_val: Variant = (parsed as Dictionary).get("adventure_module", null)
			if not AiResponseParser.validate_adventure_module(adventure_val):
				return "冒险模块无效"
		WorldInitDraftScript.SUB_FACTION_SHADOWS:
			if not AiResponseParser.validate_faction_shadows_payload(parsed):
				return "势力阴影 JSON 无效"
	return ""


func _commit_world_build_substep(
	sub: int,
	draft: Dictionary,
	parsed: Variant,
	skills_db: Variant,
	base_config: Variant,
) -> bool:
	match sub:
		WorldInitDraftScript.SUB_MAP_SKELETON:
			var map_val: Variant = (parsed as Dictionary).get("map_structure", null)
			WorldInitDraftScript.set_map_skeleton(draft, map_val as Dictionary)
		WorldInitDraftScript.SUB_MAP_PAGE:
			var page_val: Variant = (parsed as Dictionary).get("map_page", null)
			WorldInitDraftScript.append_region_map_page(draft, page_val as Dictionary)
		WorldInitDraftScript.SUB_ADVENTURE:
			var adventure_val: Variant = (parsed as Dictionary).get("adventure_module", null)
			WorldInitDraftScript.set_adventure_module(draft, adventure_val as Dictionary)
		WorldInitDraftScript.SUB_FACTION_SHADOWS:
			var shadows: Array = []
			if parsed is Dictionary:
				var shadows_val: Variant = (parsed as Dictionary).get("faction_shadows", [])
				if shadows_val is Array:
					shadows = shadows_val
			WorldInitDraftScript.set_faction_shadows(draft, shadows)
		WorldInitDraftScript.SUB_PROTAGONIST:
			var pdata: Dictionary = parsed as Dictionary
			var pid := str(pdata.get("protagonist_id", "")).strip_edges()
			var pnpcs: Array = pdata.get("npcs", []) as Array
			var protagonist_npc: Dictionary = pnpcs[0] as Dictionary
			WorldInitDraftScript.set_protagonist(draft, pid, protagonist_npc)
		WorldInitDraftScript.SUB_KEY_NPC:
			var npcs_val: Variant = (parsed as Dictionary).get("npcs", [])
			if npcs_val is Array and not npcs_val.is_empty() and npcs_val[0] is Dictionary:
				WorldInitDraftScript.append_single_key_npc(draft, npcs_val[0] as Dictionary)
		_:
			return false
	return true


func _finalize_world_init(draft: Dictionary, base_config: Variant, skills_db: Variant) -> bool:
	var world_init := WorldInitDraftScript.to_world_init(draft)
	var merge_err := AiResponseParser.describe_world_init_validation_failure(world_init, skills_db)
	if not merge_err.is_empty():
		_finish_fail("阶段 3 合并校验失败：%s" % merge_err)
		return false
	if WorldInitDraftScript.count_key_npcs(draft) < WorldInitDraftScript.MIN_KEY_NPC_COUNT:
		_finish_fail(
			AiResponseParser.describe_world_build_substep_failure(
				WorldInitDraftScript.SUB_KEY_NPC,
				"关键 NPC 数量不足（至少需要 %d 名）" % WorldInitDraftScript.MIN_KEY_NPC_COUNT,
			),
		)
		return false
	if not WorldInitDraftScript.is_starter_items_materialized(draft):
		_finish_fail(
			AiResponseParser.describe_world_build_substep_failure(
				WorldInitDraftScript.SUB_STARTER_ITEMS,
				"初始物品尚未生成",
			),
		)
		return false

	if not GameRunningFileManager.save_json_data(GameRunningFileManager.WORLD_INIT_SETTING, world_init):
		_finish_fail("无法保存 world_init_setting.json")
		return false

	if not WorldInitSplitter.apply(world_init, base_config as Dictionary):
		_finish_fail("拆分 world_init_setting 失败")
		return false

	if not _write_session_metadata():
		_finish_fail("无法写入本局会话元数据")
		return false

	if not WorldInitDraftScript.delete_file():
		push_warning("[GameWorldInitializer] 无法删除 world_init_draft.json")
	return true


func _write_session_metadata() -> bool:
	var loaded: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.GAME_STATE)
	var game_state: Dictionary
	if loaded is Dictionary:
		game_state = (loaded as Dictionary).duplicate(true)
	else:
		game_state = RuntimeDbSchemas.empty_game_state()

	var map_db: Variant = GameRunningFileManager.load_json_data(GameRunningFileManager.MAP_DB)
	var novel_type := _selected_novel_type
	if map_db is Dictionary:
		var from_map := str(map_db.get("novel_type", "")).strip_edges()
		if not from_map.is_empty():
			novel_type = from_map

	game_state["session_id"] = GameHistoryService.generate_session_id()
	game_state["started_at"] = int(Time.get_unix_time_from_system())
	game_state["novel_type"] = novel_type

	return GameRunningFileManager.save_json_data(GameRunningFileManager.GAME_STATE, game_state)


func _request_ai(prompt: String, timeout_sec: float = -1.0, context_label: String = "") -> String:
	var messages: Array = AiPromptComposerScript.wrap_json_task(prompt)
	return await _request_ai_messages(messages, timeout_sec, context_label)


func _request_ai_messages(messages: Array, timeout_sec: float = -1.0, context_label: String = "") -> String:
	if messages.is_empty():
		_finish_fail("无法组装 AI 请求提示词")
		return ""
	var state := {
		"done": false,
		"text": "",
		"error": "",
		"http_result": AIClient.HTTP_RESULT_NONE,
		"response": {},
	}

	var on_completed := func(response: Dictionary) -> void:
		state["response"] = response
		state["text"] = AiResponseParser.extract_json_task_content(response)
		if state["text"].is_empty():
			state["error"] = "AI 响应无正文内容"
			_log_api_response_issue(context_label, state["error"], response)
		else:
			var api_err := AiResponseParser.extract_api_error(response)
			if not api_err.is_empty():
				push_warning("[GameWorldInitializer] %s API 警告: %s" % [context_label, api_err])
		state["done"] = true

	var on_failed := func(err: String, http_result: int) -> void:
		state["error"] = err
		state["http_result"] = http_result
		push_error(
			"[GameWorldInitializer] %s 后台请求失败: %s (http_result=%d)"
			% [context_label if not context_label.is_empty() else "AI", err, http_result]
		)
		state["done"] = true

	_ai_client.chat_completed.connect(on_completed, CONNECT_ONE_SHOT)
	_ai_client.request_failed_ex.connect(on_failed, CONNECT_ONE_SHOT)
	var effective_timeout := timeout_sec if timeout_sec > 0.0 else AIClient.WORLD_INIT_TIMEOUT_SEC
	_ai_client.chat(messages, effective_timeout)

	while not state["done"]:
		await get_tree().process_frame

	if not state["error"].is_empty():
		_finish_fail(state["error"], state["http_result"])
		return ""

	return state["text"]


func _log_api_response_issue(context_label: String, reason: String, response: Dictionary) -> void:
	var tag := context_label if not context_label.is_empty() else "AI"
	push_error("[GameWorldInitializer] %s %s\n%s" % [tag, reason, AiResponseParser.format_response_debug(response)])


func _log_json_parse_failure(context_label: String, raw: String) -> void:
	push_error(
		"[GameWorldInitializer] %s JSON 解析失败，assistant 正文预览:\n%s"
		% [context_label, AiResponseParser.format_text_preview(raw, 1200)]
	)


func _abort_run(reason: String, http_result: int = AIClient.HTTP_RESULT_NONE) -> void:
	_running = false
	_ai_client.reset_request_timeout()
	_finish_fail(reason, http_result)


func _finish_fail(reason: String, http_result: int = AIClient.HTTP_RESULT_NONE) -> void:
	push_error("[GameWorldInitializer] " + reason)
	initialization_failed.emit(reason)
	initialization_failed_ex.emit(reason, http_result)


## 初始化失败后是否应向用户展示「重试生成」（从合格检查点续跑）。
static func is_retriable_failure(reason: String, http_result: int) -> bool:
	var r := reason.strip_edges()
	if r.is_empty():
		return false
	for blocked in [
		"世界初始化正在进行中",
		"后端端口无效",
		"小说类型未指定",
	]:
		if r == blocked:
			return false
	if AIClient.is_timeout_result(http_result):
		return true
	if http_result != AIClient.HTTP_RESULT_NONE:
		return true
	if "AI 响应无正文" in r or "无法解析为 JSON" in r:
		return true
	if r.begins_with("阶段 1") or r.begins_with("阶段 2") or r.begins_with("阶段 3"):
		return true
	if "分片" in r or "批次" in r:
		return true
	if "world_init_draft" in r:
		return true
	if "AI 返回" in r:
		return true
	if "技能库为空" in r or "skills_db" in r:
		return true
	if "无法保存" in r or "无法构建阶段" in r:
		return true
	if "拆分 world_init" in r or "world_init_setting" in r:
		return true
	if "无法写入本局会话" in r:
		return true
	if "无法创建运行时" in r or "无法归档" in r or "无法清空" in r:
		return true
	if r.begins_with("HTTP ") or "连接后端" in r or "发起请求" in r or "后端无响应" in r:
		return true
	return false
