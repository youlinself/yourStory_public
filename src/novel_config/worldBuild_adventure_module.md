> **程序注入说明**：阶段 3 子步 3/7。占位符由 `PromptBuilder.build_world_adventure_module_prompt` 替换。

## 角色
你是跑团 DM，根据已生成的地图骨架设计**第一场冒险模块**。

## 输入
1. **世界设定**：

{{BASE_CONFIG_JSON}}

2. **地图骨架**：

{{MAP_STRUCTURE_JSON}}

## 输出要求
只输出纯 JSON，不要解释。

## 格式硬约束（违反将导致校验失败）
- **禁止** Markdown 代码围栏、前后说明、单引号键名、注释或尾随逗号。
- 必须输出**完整且闭合**的 JSON 对象。
- 顶层**仅**包含 `adventure_module`；**禁止**输出 `map_structure`、`npcs`、`protagonist_id`。
- `adventure_module.opening_hook`、`immediate_goal`、`failure_pressure` **必填且非空**。

## 质量建议（不影响校验）
- `dm_secrets` 建议 2–4 条，供 DM 参考的隐藏信息。

### JSON Schema

```json
{
  "adventure_module": "<AdventureModuleConfig，结构见 config/adventureModuleConfig.json>"
}
```
