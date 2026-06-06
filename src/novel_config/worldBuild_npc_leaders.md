> **程序注入说明**：阶段 3 子步 4/6。占位符由 `PromptBuilder.build_world_npc_leaders_prompt` 替换。

## 角色
你是 NPC 设定专家。为下列势力领袖 **逐一生成** 完整角色卡（数量与 ID 必须与列表一致）。

## 输入
1. **世界设定**：

{{BASE_CONFIG_JSON}}

2. **技能库**：

{{SKILLS_DB_JSON}}

3. **已生成地图**：

{{MAP_STRUCTURE_JSON}}

4. **已生成势力**：

{{FACTIONS_JSON}}

5. **必须生成的领袖 NPC id**（每条 id 对应 `npcs` 中恰好一条记录）：

{{REQUIRED_NPC_IDS_JSON}}

6. **已存在 NPC id**（勿重复生成）：

{{EXISTING_NPC_IDS_JSON}}

## 输出要求
只输出纯 JSON。`npcs` 长度与 REQUIRED 列表相同；每个 `id` 必须完全匹配。技能 id 仅来自技能库。

### JSON Schema

```json
{
  "npcs": ["<CharacterConfig，结构见 config/characterConfig.json>"]
}
```
