> **程序注入说明**：阶段 3 子步 2/6。占位符由 `PromptBuilder.build_world_factions_prompt` 替换。

## 角色
你是势力阵营设计专家。根据世界设定与已生成地图，设计 **4 个以上** 势力；为每个势力指定 `leader_id`（下一步将生成对应 NPC，本步勿输出 npcs）。

## 输入
1. **世界设定**：

{{BASE_CONFIG_JSON}}

2. **已生成地图**：

{{MAP_STRUCTURE_JSON}}

## 输出要求
只输出纯 JSON。`core_region_id` 必须来自上方地图的 `regions[].id`。`leader_id` 须唯一、语义清晰（如 `npc_leader_guild_01`）。

### JSON Schema

```json
{
  "factions": ["<FactionConfig，结构见 config/factionConfig.json>"]
}
```
