class_name PromptBuilder
extends RefCounted

## 三阶段世界初始化 Prompt 组装。MD 内占位符仅作定位标记，由本类在运行时替换，禁止人工粘贴。
##
## 占位符注册表（须与 baseConfig.md / skillConfig.md / worldBuild.md 保持一致）：
## | 标记 | MD 文件 | 注入来源 | 阶段 |
## | {{BASE_CONFIG_JSON}} | baseConfig, skillConfig, worldBuild | 阶段1: NovelTypeSelector 注入 payload；阶段2/3: 运行时 baseConfig.json | 1/2/3 |
## | {{SKILLS_DB_JSON}} | worldBuild | 内存 skills_db JSON | 3 |
## | ```json 代码块 | skillConfig, worldBuild | config/skillConfig.json 或展开 world schema | 2/3 |
## | <RegionConfig…> 等 | mapStructureConfig（展开前） | config/*.json 递归合并 | 3 |

const BASE_DIR := "res://src/novel_config/"
const CONFIG_DIR := BASE_DIR + "config/"
const MD_FILE := BASE_DIR + "baseConfig.md"
const BASE_SLICE_NATURE_MD := BASE_DIR + "baseConfig_nature_env.md"
const BASE_SLICE_PEOPLE_MD := BASE_DIR + "baseConfig_people_env.md"
const BASE_SLICE_SOCIAL_MD := BASE_DIR + "baseConfig_social_env.md"
const JSON_FILE := BASE_DIR + "baseConfig.json"
const SKILL_MD := BASE_DIR + "skillConfig.md"
const SKILL_BATCH_COMBAT_MD := BASE_DIR + "skillConfig_batch_combat.md"
const SKILL_BATCH_SOCIAL_MD := BASE_DIR + "skillConfig_batch_social.md"
const SKILL_BATCH_SURVIVAL_MD := BASE_DIR + "skillConfig_batch_survival.md"
const WORLD_BUILD_MD := BASE_DIR + "worldBuild.md"
const WORLD_BUILD_ADVENTURE_MD := BASE_DIR + "worldBuild_adventure.md"
const WORLD_BUILD_MAP_SKELETON_MD := BASE_DIR + "worldBuild_map_skeleton.md"
const WORLD_BUILD_MAP_PAGE_MD := BASE_DIR + "worldBuild_map_page.md"
const WORLD_BUILD_ADVENTURE_MODULE_MD := BASE_DIR + "worldBuild_adventure_module.md"
const WORLD_BUILD_FACTION_SHADOWS_MD := BASE_DIR + "worldBuild_faction_shadows.md"
const WORLD_BUILD_KEY_NPC_SINGLE_MD := BASE_DIR + "worldBuild_key_npc_single.md"
const WORLD_BUILD_MAP_MD := BASE_DIR + "worldBuild_map.md"
const WORLD_BUILD_FACTIONS_MD := BASE_DIR + "worldBuild_factions.md"
const WORLD_BUILD_PROTAGONIST_MD := BASE_DIR + "worldBuild_protagonist.md"
const WORLD_BUILD_KEY_NPCS_MD := BASE_DIR + "worldBuild_key_npcs.md"
const WORLD_BUILD_NPC_LEADERS_MD := BASE_DIR + "worldBuild_npc_leaders.md"
const WORLD_BUILD_NPCS_SUPPORTING_MD := BASE_DIR + "worldBuild_npcs_supporting.md"
const PLACEHOLDER := "{{BASE_CONFIG_JSON}}"
const SKILLS_DB_PLACEHOLDER := "{{SKILLS_DB_JSON}}"
const MAP_STRUCTURE_PLACEHOLDER := "{{MAP_STRUCTURE_JSON}}"
const FACTIONS_PLACEHOLDER := "{{FACTIONS_JSON}}"
const ADVENTURE_MODULE_PLACEHOLDER := "{{ADVENTURE_MODULE_JSON}}"
const REQUIRED_NPC_IDS_PLACEHOLDER := "{{REQUIRED_NPC_IDS_JSON}}"
const EXISTING_NPC_IDS_PLACEHOLDER := "{{EXISTING_NPC_IDS_JSON}}"
const TARGET_REGION_PLACEHOLDER := "{{TARGET_REGION_JSON}}"
const TARGET_KEY_NODES_PLACEHOLDER := "{{TARGET_KEY_NODES_JSON}}"
const COMPLETED_SLICES_PLACEHOLDER := "{{COMPLETED_SLICES_JSON}}"
const EXISTING_SKILL_IDS_PLACEHOLDER := "{{EXISTING_SKILL_IDS_JSON}}"

const PH_REGION := "<RegionConfig，结构见 config/regionConfig.json>"
const PH_KEY_NODE := "<KeyNodeConfig，结构见 config/keyNodeConfig.json>"
const PH_MAP_STRUCTURE := "<MapStructureConfig，结构见 config/mapStructureConfig.json>"
const PH_LOCAL_MAP_PAGE := "<LocalMapPageConfig，结构见 config/localMapPageConfig.json>"
const PH_FACTION := "<FactionConfig，结构见 config/factionConfig.json>"
const PH_CHARACTER := "<CharacterConfig，结构见 config/characterConfig.json>"

const JSON_CODEBLOCK_START := "```json\n"
const JSON_CODEBLOCK_START_CRLF := "```json\r\n"
const JSON_CODEBLOCK_END := "```"

## 注入 prompt 的 JSON 不缩进，减小 /api/chat 请求体（本地后端默认约 100KB 上限）。
const PROMPT_JSON_COMPACT := ""


## 阶段 1：baseConfig.md + 程序选定的 novel_type（见 build_base_prompt）
static func build_prompt(selected_novel_type: String) -> String:
	return build_base_prompt(selected_novel_type)


static func build_base_prompt(selected_novel_type: String = "") -> String:
	push_warning(
		"PromptBuilder.build_base_prompt 已弃用；运行时应使用 build_base_slice_prompt 分片生成 baseConfig",
	)
	var md_content := _read_file(MD_FILE)
	if md_content.is_empty():
		push_error("无法读取 Markdown 文件: " + MD_FILE)
		return ""

	var selected := selected_novel_type.strip_edges()
	if selected.is_empty():
		push_error("build_base_prompt 需要非空的 selected_novel_type")
		return ""

	var payload := NovelTypeSelector.build_prompt_payload(selected)
	if payload.is_empty():
		return ""

	var json_content := JSON.stringify(payload, "\t")
	return _inject_placeholder(md_content, PLACEHOLDER, json_content)


## 阶段 1 分片：按 slice 编号构建小片段 prompt（1=nature_env, 2=people_env, 3=social_env）。
static func build_base_slice_prompt(
	selected_novel_type: String,
	slice: int,
	completed_slices_json: String = "",
) -> String:
	var md_path := ""
	var field_key := ""
	match slice:
		1:
			md_path = BASE_SLICE_NATURE_MD
			field_key = "nature_env"
		2:
			md_path = BASE_SLICE_PEOPLE_MD
			field_key = "people_env"
		3:
			md_path = BASE_SLICE_SOCIAL_MD
			field_key = "social_env"
		_:
			push_error("build_base_slice_prompt: 无效 slice %d" % slice)
			return ""

	var payload := NovelTypeSelector.build_slice_prompt_payload(selected_novel_type, slice)
	if payload.is_empty():
		return ""

	var schema_val: Variant = payload.get("world_setting_schema", {})
	var output_schema: Dictionary = {}
	if schema_val is Dictionary and (schema_val as Dictionary).has(field_key):
		output_schema[field_key] = (schema_val as Dictionary)[field_key]

	var md_content := _read_file(md_path)
	if md_content.is_empty():
		push_error("无法读取 Markdown 文件: " + md_path)
		return ""

	var schema_text := _prompt_json_stringify(output_schema)
	md_content = _replace_json_codeblock(md_content, schema_text)
	if md_content.is_empty():
		return ""

	var json_content := _prompt_json_stringify(payload)
	md_content = _inject_placeholder(md_content, PLACEHOLDER, json_content)
	if md_content.is_empty():
		return ""

	if COMPLETED_SLICES_PLACEHOLDER in md_content:
		var completed := completed_slices_json.strip_edges()
		if completed.is_empty():
			completed = "{}"
		md_content = md_content.replace(COMPLETED_SLICES_PLACEHOLDER, completed)

	return md_content


## 阶段 2 技能批次：按 batch 编号构建 prompt（1=战斗, 2=社交, 3=生存）。
static func build_skill_batch_prompt(
	runtime_base_config_json: String,
	batch: int,
	existing_skill_ids_json: String = "[]",
) -> String:
	var md_path := ""
	match batch:
		1:
			md_path = SKILL_BATCH_COMBAT_MD
		2:
			md_path = SKILL_BATCH_SOCIAL_MD
		3:
			md_path = SKILL_BATCH_SURVIVAL_MD
		_:
			push_error("build_skill_batch_prompt: 无效 batch %d" % batch)
			return ""

	var md_content := _read_file(md_path)
	if md_content.is_empty():
		push_error("无法读取 Markdown 文件: " + md_path)
		return ""

	if runtime_base_config_json.strip_edges().is_empty():
		push_error("build_skill_batch_prompt 需要非空的 baseConfig JSON")
		return ""

	var skill_schema: Variant = _load_config_json("skillConfig.json")
	if skill_schema == null:
		return ""

	var schema_block := JSON.stringify({"skills": [skill_schema]}, "  ")
	md_content = _replace_json_codeblock(md_content, schema_block)
	if md_content.is_empty():
		return ""

	md_content = _inject_placeholder(md_content, PLACEHOLDER, runtime_base_config_json.strip_edges())
	if EXISTING_SKILL_IDS_PLACEHOLDER in md_content:
		var ids_text := existing_skill_ids_json.strip_edges()
		if ids_text.is_empty():
			ids_text = "[]"
		md_content = md_content.replace(EXISTING_SKILL_IDS_PLACEHOLDER, ids_text)

	return md_content


## 压缩运行时 baseConfig：保留题材与三界设定，截断过长段落，供阶段 2/3 prompt 使用。
static func compact_base_config_json(base_config: Variant, max_leaf_chars: int = 800) -> String:
	if not base_config is Dictionary:
		return "{}"
	var cfg: Dictionary = base_config as Dictionary
	var ws_val: Variant = cfg.get("world_setting", {})
	var ws_compact: Dictionary = {}
	if ws_val is Dictionary:
		for section_key in ["nature_env", "people_env", "social_env"]:
			var section: Variant = (ws_val as Dictionary).get(section_key, null)
			if section is Dictionary:
				ws_compact[section_key] = _truncate_prompt_string_leaves(section as Dictionary, max_leaf_chars)
	return _prompt_json_stringify({
		"novel_type": str(cfg.get("novel_type", "")).strip_edges(),
		"world_setting": ws_compact,
	})


static func _prompt_json_stringify(value: Variant) -> String:
	if PROMPT_JSON_COMPACT.is_empty():
		return JSON.stringify(value)
	return JSON.stringify(value, PROMPT_JSON_COMPACT)


static func _truncate_prompt_string_leaves(dict: Dictionary, max_len: int) -> Dictionary:
	var out: Dictionary = {}
	for key: String in dict:
		var val: Variant = dict[key]
		if val is String:
			var s := (val as String).strip_edges()
			if s.length() > max_len:
				s = s.substr(0, max_len) + "…"
			out[key] = s
		elif val is Array:
			out[key] = val
		else:
			out[key] = val
	return out


## 压缩地图结构：overview + regions/key_nodes 摘要，不含 map_pages。
static func compact_map_structure_json(map_structure: Variant) -> String:
	if not map_structure is Dictionary:
		return "{}"
	var map: Dictionary = map_structure as Dictionary
	var regions_out: Array = []
	var regions_val: Variant = map.get("regions", [])
	if regions_val is Array:
		for region in regions_val:
			if not region is Dictionary:
				continue
			var r: Dictionary = region
			regions_out.append({
				"id": str(r.get("id", "")).strip_edges(),
				"name": str(r.get("name", "")).strip_edges(),
			})
	var nodes_out: Array = []
	var nodes_val: Variant = map.get("key_nodes", [])
	if nodes_val is Array:
		for node in nodes_val:
			if not node is Dictionary:
				continue
			var n: Dictionary = node
			nodes_out.append({
				"id": str(n.get("id", "")).strip_edges(),
				"name": str(n.get("name", "")).strip_edges(),
				"region_id": str(n.get("region_id", "")).strip_edges(),
			})
	var compact := {
		"overview": str(map.get("overview", "")).strip_edges(),
		"regions": regions_out,
		"key_nodes": nodes_out,
	}
	return _prompt_json_stringify(compact)


## 压缩技能库：仅 id + name，供角色卡 prompt 引用。
static func compact_skills_db_json(skills_db: Variant) -> String:
	if not skills_db is Dictionary:
		return "[]"
	var skills_map_val: Variant = (skills_db as Dictionary).get("skills", {})
	if not skills_map_val is Dictionary:
		return "[]"
	var out: Array = []
	for skill_id: String in skills_map_val:
		var entry: Variant = skills_map_val[skill_id]
		if entry is Dictionary:
			out.append({
				"id": skill_id,
				"name": str((entry as Dictionary).get("name", "")).strip_edges(),
			})
	return _prompt_json_stringify(out)


## 压缩冒险模块：仅三要素。
static func compact_adventure_module_json(adventure_module: Variant) -> String:
	if not adventure_module is Dictionary:
		return "{}"
	var adv: Dictionary = adventure_module as Dictionary
	var compact := {
		"opening_hook": str(adv.get("opening_hook", "")).strip_edges(),
		"immediate_goal": str(adv.get("immediate_goal", "")).strip_edges(),
		"failure_pressure": str(adv.get("failure_pressure", "")).strip_edges(),
	}
	return _prompt_json_stringify(compact)


## 阶段 2：skillConfig.md + 运行时 baseConfig.json 文本
static func build_skill_prompt(runtime_base_config_json: String) -> String:
	push_warning(
		"PromptBuilder.build_skill_prompt 已弃用；运行时应使用 build_skill_batch_prompt 分三批生成技能库",
	)
	var md_content := _read_file(SKILL_MD)
	if md_content.is_empty():
		push_error("无法读取 Markdown 文件: " + SKILL_MD)
		return ""

	if runtime_base_config_json.strip_edges().is_empty():
		push_error("build_skill_prompt 需要非空的 baseConfig JSON")
		return ""

	var skill_schema: Variant = _load_config_json("skillConfig.json")
	if skill_schema == null:
		return ""

	var schema_block := JSON.stringify({"skills": [skill_schema]}, "  ")
	md_content = _replace_json_codeblock(md_content, schema_block)
	if md_content.is_empty():
		return ""

	return _inject_placeholder(md_content, PLACEHOLDER, runtime_base_config_json.strip_edges())


## 阶段 3：worldBuild.md + 运行时 baseConfig + skills_db
static func build_world_build_prompt(
	runtime_base_config_json: String,
	skills_db_json: String = "",
) -> String:
	push_warning(
		"PromptBuilder.build_world_build_prompt 已弃用；运行时应使用 build_world_*_prompt 微步骤生成世界",
	)
	var md_content := _read_file(WORLD_BUILD_MD)
	if md_content.is_empty():
		push_error("无法读取 Markdown 文件: " + WORLD_BUILD_MD)
		return ""

	var expanded_schema: Dictionary = _build_expanded_world_build_schema()
	if expanded_schema.is_empty():
		return ""

	var schema_text := JSON.stringify(expanded_schema, "  ")
	md_content = _replace_json_codeblock(md_content, schema_text)
	if md_content.is_empty():
		return ""

	if runtime_base_config_json.strip_edges().is_empty():
		push_error("build_world_build_prompt 需要非空的 baseConfig JSON")
		return ""

	md_content = _inject_placeholder(md_content, PLACEHOLDER, runtime_base_config_json.strip_edges())

	if SKILLS_DB_PLACEHOLDER in md_content:
		if skills_db_json.strip_edges().is_empty():
			push_warning("worldBuild 提示词仍包含技能库占位符，调用方需传入 skills_db_json")
		else:
			md_content = md_content.replace(SKILLS_DB_PLACEHOLDER, skills_db_json.strip_edges())

	return md_content


static func build_world_map_skeleton_prompt(runtime_base_config_json: String) -> String:
	var map_schema := _build_expanded_map_structure_schema()
	if map_schema.is_empty():
		return ""
	if map_schema is Dictionary:
		(map_schema as Dictionary).erase("map_pages")
	return _build_world_substep_prompt(
		WORLD_BUILD_MAP_SKELETON_MD,
		{"map_structure": map_schema},
		runtime_base_config_json,
		"",
	)


static func build_world_map_page_prompt(
	runtime_base_config_json: String,
	map_structure_json: String,
	target_region_json: String,
	target_key_nodes_json: String,
) -> String:
	var local_map_page: Variant = _load_config_json("localMapPageConfig.json")
	if local_map_page == null:
		return ""
	var md := _build_world_substep_prompt(
		WORLD_BUILD_MAP_PAGE_MD,
		{"map_page": local_map_page},
		runtime_base_config_json,
		"",
		map_structure_json,
	)
	if md.is_empty():
		return ""
	md = _inject_placeholder(md, TARGET_REGION_PLACEHOLDER, target_region_json.strip_edges())
	return _inject_placeholder(md, TARGET_KEY_NODES_PLACEHOLDER, target_key_nodes_json.strip_edges())


static func build_world_adventure_module_prompt(
	runtime_base_config_json: String,
	map_structure_json: String,
) -> String:
	var adventure_schema: Variant = _load_config_json("adventureModuleConfig.json")
	if adventure_schema == null:
		return ""
	return _build_world_substep_prompt(
		WORLD_BUILD_ADVENTURE_MODULE_MD,
		{"adventure_module": adventure_schema},
		runtime_base_config_json,
		"",
		map_structure_json,
	)


static func build_world_faction_shadows_prompt(
	runtime_base_config_json: String,
	map_structure_json: String,
	adventure_module_json: String,
) -> String:
	var md := _build_world_substep_prompt(
		WORLD_BUILD_FACTION_SHADOWS_MD,
		{
			"faction_shadows": [
				{
					"id": "faction_shadow_01",
					"name": "string",
					"role": "string",
				},
			],
		},
		runtime_base_config_json,
		"",
		map_structure_json,
	)
	if md.is_empty():
		return ""
	return _inject_placeholder(md, ADVENTURE_MODULE_PLACEHOLDER, adventure_module_json.strip_edges())


static func build_world_key_npc_single_prompt(
	runtime_base_config_json: String,
	skills_db_json: String,
	map_structure_json: String,
	adventure_module_json: String,
	existing_npc_ids_json: String,
) -> String:
	var character: Variant = _load_config_json("characterConfig.json")
	if character == null:
		return ""
	var compact_map := map_structure_json
	if not map_structure_json.strip_edges().is_empty():
		var parsed: Variant = JSON.parse_string(map_structure_json)
		compact_map = compact_map_structure_json(parsed)
	var compact_skills := skills_db_json
	if not skills_db_json.strip_edges().is_empty():
		var parsed_skills: Variant = JSON.parse_string(skills_db_json)
		compact_skills = compact_skills_db_json(parsed_skills)
	var compact_adv := adventure_module_json
	if not adventure_module_json.strip_edges().is_empty():
		var parsed_adv: Variant = JSON.parse_string(adventure_module_json)
		compact_adv = compact_adventure_module_json(parsed_adv)
	var md := _build_world_substep_prompt(
		WORLD_BUILD_KEY_NPC_SINGLE_MD,
		{"npcs": [character]},
		runtime_base_config_json,
		compact_skills,
		compact_map,
		"",
		true,
	)
	if md.is_empty():
		return ""
	md = _inject_placeholder(md, ADVENTURE_MODULE_PLACEHOLDER, compact_adv.strip_edges())
	md = _inject_placeholder(md, EXISTING_NPC_IDS_PLACEHOLDER, existing_npc_ids_json.strip_edges())
	return _append_role_card_response_format_lock(md)


## 遗留一体式 prompt（运行时不再调用）。
static func build_world_adventure_prompt(runtime_base_config_json: String) -> String:
	return build_world_map_skeleton_prompt(runtime_base_config_json)


static func build_world_map_prompt(runtime_base_config_json: String) -> String:
	return build_world_adventure_prompt(runtime_base_config_json)


static func build_world_factions_prompt(
	runtime_base_config_json: String,
	map_structure_json: String,
) -> String:
	var faction_schema: Variant = _load_config_json("factionConfig.json")
	if faction_schema == null:
		return ""
	return _build_world_substep_prompt(
		WORLD_BUILD_FACTIONS_MD,
		{"factions": [faction_schema]},
		runtime_base_config_json,
		"",
		map_structure_json,
	)


static func build_world_protagonist_prompt(
	runtime_base_config_json: String,
	skills_db_json: String,
	map_structure_json: String,
	adventure_module_json: String,
) -> String:
	var character: Variant = _load_config_json("characterConfig.json")
	if character == null:
		return ""
	var compact_map := map_structure_json
	if not map_structure_json.strip_edges().is_empty():
		var parsed: Variant = JSON.parse_string(map_structure_json)
		compact_map = compact_map_structure_json(parsed)
	var compact_skills := skills_db_json
	if not skills_db_json.strip_edges().is_empty():
		var parsed_skills: Variant = JSON.parse_string(skills_db_json)
		compact_skills = compact_skills_db_json(parsed_skills)
	var compact_adv := adventure_module_json
	if not adventure_module_json.strip_edges().is_empty():
		var parsed_adv: Variant = JSON.parse_string(adventure_module_json)
		compact_adv = compact_adventure_module_json(parsed_adv)
	var md := _build_world_substep_prompt(
		WORLD_BUILD_PROTAGONIST_MD,
		{
			"protagonist_id": "string (主角 NPC ID，对应 npcs 中某条记录的 id)",
			"npcs": [character],
		},
		runtime_base_config_json,
		compact_skills,
		compact_map,
		"",
		true,
	)
	if md.is_empty():
		return ""
	md = _inject_placeholder(md, ADVENTURE_MODULE_PLACEHOLDER, compact_adv.strip_edges())
	return _append_role_card_response_format_lock(md)


static func build_world_key_npcs_prompt(
	runtime_base_config_json: String,
	skills_db_json: String,
	map_structure_json: String,
	adventure_module_json: String,
	existing_npc_ids_json: String,
) -> String:
	var character: Variant = _load_config_json("characterConfig.json")
	if character == null:
		return ""
	var md := _build_world_substep_prompt(
		WORLD_BUILD_KEY_NPCS_MD,
		{"npcs": [character]},
		runtime_base_config_json,
		skills_db_json,
		map_structure_json,
		"",
	)
	if md.is_empty():
		return ""
	md = _inject_placeholder(md, ADVENTURE_MODULE_PLACEHOLDER, adventure_module_json.strip_edges())
	return _inject_placeholder(md, EXISTING_NPC_IDS_PLACEHOLDER, existing_npc_ids_json.strip_edges())


static func build_world_npc_leaders_prompt(
	runtime_base_config_json: String,
	skills_db_json: String,
	map_structure_json: String,
	factions_json: String,
	required_npc_ids_json: String,
	existing_npc_ids_json: String,
) -> String:
	var character: Variant = _load_config_json("characterConfig.json")
	if character == null:
		return ""
	var md := _build_world_substep_prompt(
		WORLD_BUILD_NPC_LEADERS_MD,
		{"npcs": [character]},
		runtime_base_config_json,
		skills_db_json,
		map_structure_json,
		factions_json,
	)
	if md.is_empty():
		return ""
	md = _inject_placeholder(md, REQUIRED_NPC_IDS_PLACEHOLDER, required_npc_ids_json.strip_edges())
	return _inject_placeholder(md, EXISTING_NPC_IDS_PLACEHOLDER, existing_npc_ids_json.strip_edges())


static func build_world_supporting_npcs_prompt(
	runtime_base_config_json: String,
	skills_db_json: String,
	map_structure_json: String,
	factions_json: String,
	existing_npc_ids_json: String,
) -> String:
	var character: Variant = _load_config_json("characterConfig.json")
	if character == null:
		return ""
	var md := _build_world_substep_prompt(
		WORLD_BUILD_NPCS_SUPPORTING_MD,
		{"npcs": [character]},
		runtime_base_config_json,
		skills_db_json,
		map_structure_json,
		factions_json,
	)
	if md.is_empty():
		return ""
	return _inject_placeholder(md, EXISTING_NPC_IDS_PLACEHOLDER, existing_npc_ids_json.strip_edges())


static func _build_world_substep_prompt(
	md_path: String,
	output_schema: Dictionary,
	runtime_base_config_json: String,
	skills_db_json: String = "",
	map_structure_json: String = "",
	factions_json: String = "",
	plain_schema: bool = false,
) -> String:
	var md_content := _read_file(md_path)
	if md_content.is_empty():
		push_error("无法读取 Markdown 文件: " + md_path)
		return ""
	if runtime_base_config_json.strip_edges().is_empty():
		push_error("_build_world_substep_prompt 需要非空的 baseConfig JSON")
		return ""
	var schema_text := _prompt_json_stringify(output_schema)
	if plain_schema:
		md_content = _replace_json_codeblock_with_plain_schema(md_content, schema_text)
	else:
		md_content = _replace_json_codeblock(md_content, schema_text)
	if md_content.is_empty():
		return ""
	md_content = _inject_placeholder(md_content, PLACEHOLDER, runtime_base_config_json.strip_edges())
	if SKILLS_DB_PLACEHOLDER in md_content:
		if skills_db_json.strip_edges().is_empty():
			push_error("子步提示词需要 skills_db_json")
			return ""
		md_content = md_content.replace(SKILLS_DB_PLACEHOLDER, skills_db_json.strip_edges())
	if MAP_STRUCTURE_PLACEHOLDER in md_content:
		if map_structure_json.strip_edges().is_empty():
			push_error("子步提示词需要 map_structure_json")
			return ""
		md_content = md_content.replace(MAP_STRUCTURE_PLACEHOLDER, map_structure_json.strip_edges())
	if FACTIONS_PLACEHOLDER in md_content:
		if factions_json.strip_edges().is_empty():
			push_error("子步提示词需要 factions_json")
			return ""
		md_content = md_content.replace(FACTIONS_PLACEHOLDER, factions_json.strip_edges())
	return md_content


static func _build_expanded_map_structure_schema() -> Dictionary:
	var region: Variant = _load_config_json("regionConfig.json")
	var key_node: Variant = _load_config_json("keyNodeConfig.json")
	var local_map_page: Variant = _load_config_json("localMapPageConfig.json")
	var map_structure: Variant = _load_config_json("mapStructureConfig.json")
	if region == null or key_node == null or local_map_page == null or map_structure == null:
		return {}
	var map_replacements: Dictionary = {
		PH_REGION: region,
		PH_KEY_NODE: key_node,
		PH_LOCAL_MAP_PAGE: local_map_page,
	}
	return _expand_schema_value(map_structure, map_replacements)


static func _build_expanded_world_build_schema() -> Dictionary:
	var region: Variant = _load_config_json("regionConfig.json")
	var key_node: Variant = _load_config_json("keyNodeConfig.json")
	var faction: Variant = _load_config_json("factionConfig.json")
	var character: Variant = _load_config_json("characterConfig.json")
	var map_structure: Variant = _load_config_json("mapStructureConfig.json")

	if region == null or key_node == null or faction == null or character == null or map_structure == null:
		return {}

	var local_map_page: Variant = _load_config_json("localMapPageConfig.json")
	if local_map_page == null:
		return {}
	var map_replacements: Dictionary = {
		PH_REGION: region,
		PH_KEY_NODE: key_node,
		PH_LOCAL_MAP_PAGE: local_map_page,
	}
	map_structure = _expand_schema_value(map_structure, map_replacements)

	return {
		"map_structure": map_structure,
		"factions": [faction],
		"npcs": [character],
		"protagonist_id": "string (主角 NPC ID，对应 npcs 中某条记录的 id)",
	}


static func _expand_schema_value(value: Variant, replacements: Dictionary) -> Variant:
	if value is String:
		if replacements.has(value):
			return _expand_schema_value(replacements[value], replacements)
		return value
	if value is Array:
		var expanded_array: Array = []
		for item in value:
			expanded_array.append(_expand_schema_value(item, replacements))
		return expanded_array
	if value is Dictionary:
		var expanded_dict: Dictionary = {}
		for key: String in value:
			expanded_dict[key] = _expand_schema_value(value[key], replacements)
		return expanded_dict
	return value


static func _inject_placeholder(md_content: String, placeholder: String, replacement: String) -> String:
	if placeholder not in md_content:
		push_error("未找到占位符: " + placeholder)
		return ""
	return md_content.replace(placeholder, replacement)


static func _load_config_json(file_name: String) -> Variant:
	var text := _read_file(CONFIG_DIR + file_name).strip_edges()
	if text.is_empty():
		push_error("无法读取配置文件: " + CONFIG_DIR + file_name)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("无法解析配置文件: " + CONFIG_DIR + file_name + " — " + json.get_error_message())
		return null
	return json.get_data()


static func _find_json_codeblock_bounds(md_content: String) -> PackedInt32Array:
	var start := md_content.find(JSON_CODEBLOCK_START)
	var content_start := -1
	if start != -1:
		content_start = start + JSON_CODEBLOCK_START.length()
	else:
		start = md_content.find(JSON_CODEBLOCK_START_CRLF)
		if start != -1:
			content_start = start + JSON_CODEBLOCK_START_CRLF.length()
	if content_start == -1:
		return PackedInt32Array()
	var end := md_content.find(JSON_CODEBLOCK_END, content_start)
	if end == -1:
		return PackedInt32Array()
	return PackedInt32Array([start, content_start, end, end + JSON_CODEBLOCK_END.length()])


static func _replace_json_codeblock(md_content: String, json_text: String) -> String:
	var bounds := _find_json_codeblock_bounds(md_content)
	if bounds.is_empty():
		push_error("未找到 JSON 代码块起始/结束标记")
		return ""
	var content_start: int = bounds[1]
	var closing_fence_start: int = bounds[2]
	return md_content.substr(0, content_start) + json_text + "\n" + md_content.substr(closing_fence_start)


## 角色卡子步：注入纯文本 schema，去掉 ```json 围栏，避免模型模仿围栏输出。
static func _replace_json_codeblock_with_plain_schema(md_content: String, json_text: String) -> String:
	var bounds := _find_json_codeblock_bounds(md_content)
	if bounds.is_empty():
		push_error("未找到 JSON 代码块起始/结束标记")
		return ""
	var block_start: int = bounds[0]
	var block_end: int = bounds[3]
	var preamble := (
		"以下为本步须输出的 JSON 字段结构（类型说明，非示例值；你的回答须填真实内容，"
		+ "且禁止使用 Markdown 代码围栏）：\n\n"
	)
	return md_content.substr(0, block_start) + preamble + json_text + "\n" + md_content.substr(block_end)


## 角色卡子步末尾格式锁（置于 prompt 最末，减轻长上下文对「只输出 JSON」的稀释）。
static func _append_role_card_response_format_lock(md_content: String) -> String:
	return (
		md_content
		+ "\n\n## 最终输出格式（必须遵守）\n"
		+ "- 你的**整段回复**必须以 `{` 开头、以 `}` 结尾；中间不得有任何说明文字、标题或 Markdown ``` 围栏。\n"
		+ "- 禁止输出本提示词中的 schema 类型说明字面量（如 `string (...)`）；须填写真实角色数据。\n"
	)


static func _read_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
