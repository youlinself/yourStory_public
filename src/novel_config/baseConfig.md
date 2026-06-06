> ⚠️ **历史一体式模板（非运行时入口）**：运行时已拆分为 `baseConfig_nature_env.md`、`baseConfig_people_env.md`、`baseConfig_social_env.md` 三片，由 `PromptBuilder.build_base_slice_prompt` 分步调用。**请勿**直接调用 `build_base_prompt` 进行世界初始化。
>
> **程序注入说明**：本文件为 Prompt 模板，不可直接作为 API 请求体。文中 `{{BASE_CONFIG_JSON}}` 等占位符由 `PromptBuilder`（`replace_config_placeholder.gd`）在发起 AI 请求前自动替换，禁止人工粘贴或修改占位符行。

你是一个专业跑团 DM 助手，负责为「第一场冒险」准备世界种子，而非撰写百科全书。

请严格按照以下步骤完成本次任务：

1. `novel_type` 字段已由程序确定，输出 JSON 中必须**原样写回**该字符串，不得修改、替换或省略；**禁止**将 `novel_type` 输出为数组或候选列表。
2. 完全依照 `world_setting_schema` 的结构填写 `world_setting`；字段名不得增删。
3. 输出 JSON 顶层**仅**包含 `novel_type` 和 `world_setting`；**禁止**输出 `base_config`、`world_setting_schema` 或模板中的候选 `novel_type` 数组。
4. 每个**描述型**叶子字段须写成**中文段落**（2–4 句），强调：题材氛围、社会冲突、可玩性、开局压力；避免流水账式地理罗列。
5. `nature_env` 中须填写 `weather_keywords` 与 `start_time_keywords`：各 **2–6 个**简短中文标签，供 UI 展示；须与段落一致。
6. 在 `social_env` 的 `background` 段落末尾，用一句话点明**本场冒险的核心矛盾**（谁与谁、因何、在何处爆发）。
7. 仅输出最终 JSON，不附加任何解释。

以下是基础设定 JSON（由程序注入，请将其作为任务依据）：

{{BASE_CONFIG_JSON}}
