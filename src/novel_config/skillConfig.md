> ⚠️ **历史一体式模板（非运行时入口）**：运行时已拆分为 `skillConfig_batch_combat.md`、`skillConfig_batch_social.md`、`skillConfig_batch_survival.md` 三批，由 `PromptBuilder.build_skill_batch_prompt` 分步调用（每批 3–5 项，三批合计 ≥8 项）。**请勿**直接调用 `build_skill_prompt` 一次生成 8–15 项。
>
> **程序注入说明**：本文件为 Prompt 模板，不可直接作为 API 请求体。占位符 `{{BASE_CONFIG_JSON}}` 由 `PromptBuilder`（`replace_config_placeholder.gd`）在发起 AI 请求前自动替换，禁止人工粘贴或修改占位符行。

## 角色
你是跑团规则设计师，根据世界设定设计本局**轻规则行动标签**（供 d20 判定与叙事引用）。

## 输入
阶段 1 产出的 `baseConfig.json`，由程序注入如下：

{{BASE_CONFIG_JSON}}

## 输出要求

1. 阅读 `novel_type` 与 `world_setting`，技能须贴合题材。
2. 顶层**仅**包含 `skills` 字段。
3. `skills` 为对象数组 `[{...}]`，**8–15** 个；少于 8 个不合格。
4. 每项含 `id`（小写英文+下划线）、`name`、`desc`（8–15 字中文）。
5. 覆盖：战斗、社交、调查、生存、专业、风险等；`desc` 可暗示适用属性（如「敏捷·潜行」）。
6. **仅输出 JSON**，无 Markdown 围栏、无解释。

### JSON Schema

```json
{
  "skills": [
    {
      "id": "skill_example",
      "name": "示例",
      "desc": "八个字左右的描述"
    }
  ]
}
```
