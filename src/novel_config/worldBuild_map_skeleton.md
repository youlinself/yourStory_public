> **程序注入说明**：阶段 3 子步 1/7。占位符由 `PromptBuilder.build_world_map_skeleton_prompt` 替换。

## 角色
你是跑团 DM，负责设计**第一场冒险**的地图骨架（区域与关键节点），本步**不**生成格子地图页。

## 输入
**世界设定**（`baseConfig.json`）：

{{BASE_CONFIG_JSON}}

## 输出要求
只输出纯 JSON，不要解释。

**格式硬约束（违反将导致解析失败）：**
- **禁止** Markdown 代码围栏（不要 ` ```json ` 或 ` ``` `）。
- **禁止** 在 JSON 前后添加任何文字、标题、注释或解释。
- **禁止** 单引号键名、JavaScript 注释（`//`、`/* */`）或尾随逗号。
- 必须输出**完整且闭合**的 JSON 对象，不得省略字段、用 `...` 占位或截断。

**体积控制：**
- `regions` **1–2** 个（上限 3）；`key_nodes` **2–3** 个（上限 5）。
- `overview` 一句话（≤40 字）。

- `map_structure` 须含 `overview`、`regions`、`key_nodes`。
- **禁止** 输出 `map_pages`、`npcs`、`protagonist_id`、`adventure_module`。
- 每个 `key_node` 须有 `region_id` 指向已有 region。

### JSON Schema

```json
{
  "map_structure": "<MapStructureConfig 骨架，不含 map_pages>"
}
```
