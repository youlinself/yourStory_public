> **程序注入说明**：阶段 3 子步 4/7。占位符由 `PromptBuilder.build_world_faction_shadows_prompt` 替换。

## 角色
你是跑团 DM。为第一场冒险补充 **0–2 条势力阴影**（仅简述，非完整势力设定）。

## 输入
1. **世界设定**：

{{BASE_CONFIG_JSON}}

2. **地图骨架**：

{{MAP_STRUCTURE_JSON}}

3. **冒险模块**：

{{ADVENTURE_MODULE_JSON}}

## 输出要求
只输出纯 JSON，不要解释。

**格式硬约束（违反将导致解析失败）：**
- **禁止** Markdown 代码围栏、前后说明、单引号键名、注释或尾随逗号。
- 必须输出**完整且闭合**的 JSON 对象。

- `faction_shadows`：**0–2** 条；每条含 `id`、`name`、`role`（一句话）。
- 若无合适势力，输出空数组 `[]`。

### JSON Schema

```json
{
  "faction_shadows": [
    {
      "id": "faction_shadow_01",
      "name": "string",
      "role": "string"
    }
  ]
}
```
