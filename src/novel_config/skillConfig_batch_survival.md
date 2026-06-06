> **程序注入说明**：阶段 2 批次 3/3。占位符由 `PromptBuilder.build_skill_batch_prompt` 替换。

## 角色
你是跑团规则设计师，根据世界设定设计**生存与专业**类轻规则标签。

## 输入
**世界设定**：

{{BASE_CONFIG_JSON}}

**已有技能 id**（勿重复）：

{{EXISTING_SKILL_IDS_JSON}}

## 输出要求
1. 顶层**仅**包含 `skills` 数组。
2. 本批 **3–5** 个技能，侧重：生存、医疗、技术、潜行、驾驶、专业技艺等。
3. 每项含 `id`、`name`、`desc`（8–15 字中文）。
4. **仅输出 JSON**，无 Markdown 围栏、无解释。

## 格式硬约束（违反将导致校验失败）
- 顶层必须是 JSON 对象 `{ "skills": [...] }`；**禁止**裸数组、`{ "skill_id": {...} }` 对象 map。
- `skills` 必须是对象数组，本批 **3–5** 项；**禁止**一次输出 8–15 项（共三批生成，每批 3–5 项）。
- 每项字段名必须为 `id`、`name`、`desc`；**禁止** `description`、`说明` 等别名。
- **禁止** Markdown 代码围栏、前后说明、注释或尾随逗号。

## 质量建议（不影响校验）
- `desc` 可暗示适用属性（如「体质·生存」）。
- 技能 id 须与已有 id 不重复，贴合 `novel_type` 与 `world_setting`。

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
