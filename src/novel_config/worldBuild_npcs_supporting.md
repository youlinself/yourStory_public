> **程序注入说明**：阶段 3 子步 5/6。占位符由 `PromptBuilder.build_world_supporting_npcs_prompt` 替换。

## 角色
你是配角设计专家。生成 **2–3 名** 与已有势力、主角有关联的重要配角，丰富开局叙事网络。

## 输入
1. **世界设定**：

{{BASE_CONFIG_JSON}}

2. **技能库**：

{{SKILLS_DB_JSON}}

3. **已生成地图**：

{{MAP_STRUCTURE_JSON}}

4. **已生成势力**：

{{FACTIONS_JSON}}

5. **已存在 NPC id**（新配角 id 不得与下列重复）：

{{EXISTING_NPC_IDS_JSON}}

## 输出要求
只输出纯 JSON。本步 `npcs` **2–3 条**，均为新 id。`current_region_id` / `relationships` 中的 id 须引用已存在的区域、势力或 NPC。

### JSON Schema

```json
{
  "npcs": ["<CharacterConfig，结构见 config/characterConfig.json>"]
}
```
