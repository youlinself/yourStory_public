> **程序注入说明**：已合并至 `worldBuild_adventure.md`（子步 1/4）。本文件保留仅供查阅，运行时不再调用。

## 角色
你是跑团场景设计师。根据世界设定生成**局部冒险地图**（非完整世界地图）。

## 输入
**世界设定**（`baseConfig.json`）：

{{BASE_CONFIG_JSON}}

## 输出要求
只输出纯 JSON。

- `regions` 数量 **1–3**；`key_nodes` **2–5** 个。
- `adjacent_region_ids` 仅引用本次 `regions` 中的 id，双向一致。
- 本步 **不要** 输出 `factions`、`npcs`、`protagonist_id`。

### JSON Schema

```json
{
  "map_structure": "<MapStructureConfig，结构见 config/mapStructureConfig.json>"
}
```
