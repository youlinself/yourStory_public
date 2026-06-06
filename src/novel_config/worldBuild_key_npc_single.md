> **程序注入说明**：阶段 3 子步 6/7（可重复）。占位符由 `PromptBuilder.build_world_key_npc_single_prompt` 替换。

## 角色
你是跑团 NPC 设计师。为第一场冒险生成 **1 名关键 NPC**（委托人、阻碍者、盟友或线索人之一）。

## 输入
1. **世界设定**：

{{BASE_CONFIG_JSON}}

2. **技能库**（`skills` 数组元素必须为技能 id 字符串）：

{{SKILLS_DB_JSON}}

3. **已生成地图**：

{{MAP_STRUCTURE_JSON}}

4. **冒险模块**：

{{ADVENTURE_MODULE_JSON}}

5. **已存在 NPC id**（勿重复）：

{{EXISTING_NPC_IDS_JSON}}

## 输出要求
只输出纯 JSON，不要解释。`npcs` **仅 1 条**，新 id。

## 格式硬约束（违反将导致校验失败）
- **禁止** Markdown 代码围栏、前后说明、单引号键名、注释或尾随逗号。
- 必须输出**完整且闭合**的 JSON 对象，不得截断。
- 顶层**仅**包含 `npcs` 数组（**1 条**）。
- `npcs[0].id` 须非空且不与已有 NPC id 重复。
- `npcs[0]` 须含非空 `current_region_id`、`initial_scene`。
- `npcs[0].skills` 须为 **1–6** 个技能 **id** 字符串（禁止填技能中文名或 `{id,name}` 对象），且均存在于技能库中。

## 质量建议（不影响校验）
- 角色定位应服务于 `adventure_module` 的开局冲突。
- 建议填写 `abilities` 六维与 `personality` 等完整角色卡字段。

### 输出结构

```json
{
  "npcs": ["<CharacterConfig，结构见 config/characterConfig.json>"]
}
```

> 上方块内为字段结构说明，由程序替换为完整 schema；**你的回答不得使用代码围栏**。
