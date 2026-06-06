> **程序注入说明**：阶段 3 子步 2/7（可重复）。占位符由 `PromptBuilder.build_world_map_page_prompt` 替换。

## 角色
你是跑团场景设计师。为**单个区域**生成一张本地图页（`map_page`）。

## 输入
1. **世界设定**：

{{BASE_CONFIG_JSON}}

2. **已生成地图骨架**：

{{MAP_STRUCTURE_JSON}}

3. **本步目标区域**（`parent_id` 须与其 `id` 一致）：

{{TARGET_REGION_JSON}}

4. **该区域须绑定的关键节点**（每个 `id` 须在 `cell_marks` 中恰好出现一次 `key_node_id`）：

{{TARGET_KEY_NODES_JSON}}

## 输出要求
只输出纯 JSON，不要解释。

## 格式硬约束（违反将导致校验失败）
- **禁止** Markdown 代码围栏、前后说明、单引号键名、注释或尾随逗号。
- 必须输出**完整且闭合**的 JSON 对象。
- 只输出 **1** 张 `map_page`；`parent_type` 必须为 `region`；`parent_id` 须与目标区域 id 一致。
- 该区域每个 `key_node_id` 须在 `cell_marks` 中**各绑定一次**（缺失绑定将导致校验失败）。
- `map_page` 须含合法 `id`、`width`、`height`（5–50）、非空 `terrain_types`、合法 `default_terrain`。

## 质量建议（不影响校验）
- `cell_marks` 建议不超过 **10** 条；只标关键地形与入口。
- **禁止** 输出完整 `cells` 数组；程序会生成格子。
- `cell_marks.type` 建议与 `terrain_types` **逐字相同**（近义词可能导致 mark 被跳过）。

### JSON Schema

```json
{
  "map_page": "<LocalMapPageConfig，结构见 config/localMapPageConfig.json>"
}
```
