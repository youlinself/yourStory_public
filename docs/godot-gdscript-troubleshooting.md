# Godot GDScript 常见问题排查

本文档覆盖本项目中四类高频问题：**class_name 静态调用**、**试探性 JSON 解析噪音**、**导出版无法读取 `.md` 模板**、**AI 后端连接异常**。

---

## A. `Static function "..." not found in base "ClassName"`

### 典型报错

```text
Static function "split_story_log_for_archive()" not found in base "NarrativeArchiveService".
```

### 原因

脚本声明了 `class_name` 时，**即使**用 `preload` 别名做静态调用，Godot 4 仍常走**全局类注册表** `NarrativeArchiveService`；若该类是新建/刚加 `static func` 而 `.godot` 缓存未刷新，注册表里没有新方法，就会报「未找到」——与磁盘上的 `.gd` 内容无关。

**根治（仅通过 preload 使用的工具脚本）**：去掉 `class_name`，只保留 `extends RefCounted`，让 `NarrativeArchiveServiceScript.foo()` 直接绑定脚本资源（本项目 `narrative_archive_service.gd` 已采用）。

### 修复清单

1. 打开对应 `.gd`，确认 `static func` 已保存且拼写一致。
2. **调用方已 `preload` 该脚本时**（如 `GameSessionController`）：静态方法与常量用 **`PreloadAlias.method()`**（与 `ActionSuggestionBuilderScript.build_from_read_model` 一致），不要改用全局 `ClassName`（易与过期全局类缓存冲突）。
3. **独立测试脚本**（无 preload）：同样 `const X := preload("...")` 后 `X.static_method()`，或确认已重载项目后再用 `ClassName`。
4. **实例化**：`PreloadAlias.new()` 或 `ClassName.new()`。
4. 编辑器：**项目 → 重新加载当前项目**；仍异常时可关闭编辑器后删除 `.godot/` 再打开。
5. 运行 headless 测试验证，例如：
   ```powershell
   godot --headless -s tests/narrative_context_logic_test.gd
   ```

### 本项目约定

| 场景 | 推荐 | 避免 |
|------|------|------|
| 文件内已有 `const S := preload(...)` | `S.foo()` / `S.CONST` | 同文件再写 `ClassName.foo()` |
| 无 preload 的独立脚本 | `preload` 后 `S.foo()`，或重载项目后用 `ClassName.foo()` | 混用两种风格且不刷新缓存 |
| 需要 `.new()` | `S.new()`（与 preload 常量一致） | — |
| 无 `class_name` 的纯脚本 | `preload` + 任意调用 | — |

### 相关文件

- `src/game/logic/narrative/narrative_archive_service.gd`
- `tests/narrative_context_logic_test.gd`

---

## B. `Parse JSON failed`（试探解析噪音）

### 典型栈

```text
ai_response_parser.gd @ parse_json_from_ai_text()
narrative_turn_parser.gd @ _try_unified_turn_json()
narrative_turn_parser.gd @ parse_from_api_response()
narrative_service.gd @ parse_ok_preview()
narrative_service.gd @ _request_ai_response()
```

### 原因

叙事回合解析会**先**把整段 `message.content`（多为自然语言）当作「统一 JSON 回合」试探解析。若对非 JSON 文本调用 `JSON.parse_string`，Godot 4.x 会向控制台输出 **E** 级 `Parse JSON failed`，随后解析器再走 STATE_HOOK / marker 等后备路径——**游戏往往仍正常**，只是控制台吓人。

`parse_ok_preview` 在每轮 AI 成功响应后都会触发该试探，故每回合至少可能出现一次（修复前）。

### 区分「噪音」与「真故障」

| 现象 | 含义 |
|------|------|
| 仅有 `Parse JSON failed`，剧情照常 | 试探失败，属噪音（已用静默解析缓解） |
| `[NarrativeService] 未解析到 STATE_HOOK` 且 `parse_ok: false` | 真正未解析到 hook，查后端剥离或 Prompt |
| `game_world_initializer` / `dynamic_add` 路径报错 | 该路径期望纯 JSON，查 AI 返回内容 |

### 修复与约定

- 所有「可能不是 JSON」的 AI 文本统一走 `AiResponseParser.parse_json_from_ai_text()`：
  - `strip_edges` 后非 `{` / `[` 开头 → 直接 `return null`（不解析）。
  - 使用 `JSON.new().parse()`，失败返回 `null`，**不要**对未知文本使用会打 E 日志的 `JSON.parse_string` 做试探。
- 需要解析的 HOOK 片段等，优先复用上述函数或同等静默逻辑。

### 相关文件

- `src/novel_config/ai_response_parser.gd` — `parse_json_from_ai_text`
- `src/game/logic/narrative/narrative_turn_parser.gd` — `_try_unified_turn_json`
- `src/game/logic/narrative/narrative_service.gd` — `parse_ok_preview`

### 测试

```powershell
godot --headless -s tests/ai_response_parser_base_config_test.gd
```

含散文返回 `null`、合法 JSON / fenced JSON 仍可解析的用例。

---

## C. 导出版无法读取 `.md`（如 narrative_turn.md）

### 典型报错

游戏界面底部（或日志）：

```text
调用失败：无法读取叙事模板（narrative_turn.md），请确认已完整导出 main.pck
```

编辑器内运行正常，仅 **Windows 导出版**（`main.exe` + `main.pck`）失败。

### 原因

- 叙事与世界初始化 Prompt 存放在 `res://` 下的 **纯 Markdown 文件**（无 `.import`，不是 Godot 资源）。
- [`export_presets.cfg`](../export_presets.cfg) 使用 `export_filter="all_resources"` 时，这些 `.md` **默认不会**打进 PCK。
- [`ResTextFile`](../src/io/res_text_file.gd) 对 `res://` 已直接 `FileAccess.open`；失败是因为 PCK 里根本没有该文件，而非 `file_exists` 误判。

### 修复

在导出预设中设置 `include_filter`（已配置示例）：

```ini
include_filter="src/novel_config/*.md,ai_config/AiSkills/*.md"
```

修改后须 **重新导出**，并将新的 `main.exe`、`main.console.exe`、`main.pck` 一并部署（与 `ai_backend` 同目录）。

### 验证

```powershell
findstr /C:"narrative_turn.md" dist\main.pck
```

应能看到 `src/novel_config/narrative_turn.md` 路径。亦可运行：

```powershell
powershell -File scripts/verify_export_pck.ps1
```

### 相关文件

- `export_presets.cfg` — `include_filter`
- `src/game/logic/narrative/narrative_prompt_builder.gd` — 读取 `narrative_turn.md`
- `scripts/verify_export_pck.ps1` — 导出后 PCK 自检

---

## D. 「HTTP 413 / PayloadTooLargeError: request entity too large」

### 典型现象

主题页或世界生成：`初始化失败: HTTP 413: ... PayloadTooLargeError: request entity too large`

### 原因

本地 `ai-backend` 使用 Express 默认请求体上限（约 **100KB**）。阶段 2/3 会把 `baseConfig`、地图草稿、`characterConfig` schema 等拼进单次 `/api/chat`；AI 已写出很长段落或地图含 `map_pages` 时，JSON 请求体易超限。

### 处理

1. 项目已对世界初始化 prompt 做 **compact**（截断过长设定、压缩地图/技能库 JSON）；拉取最新代码后点 **重试生成**。
2. 若仍 413：更新 `ai_backend/ai-backend-win.exe`（需将服务端 `express.json({ limit })` 提高到如 `10mb` 后重新打包）。
3. 或删除 `user://game_running/` 下草稿后从主菜单 **重抽主题** 重新生成。

---

## E. 「与 AI 后端的连接异常中断」/ 后端反复退出

### 典型现象

- 主题选择页：`初始化失败：与 AI 后端的连接异常中断`
- 控制台：`[BackendLauncher] 后端进程已退出`，随后自动重启 `(1/5)…`
- 后端日志：`[AIConfig] 标准 JSON 解析失败: Unexpected token a in JSON at position 1`（随后常有 `Godot dict 格式解析成功`）

### 原因（按优先级）

1. **端口过期（最常见）**  
   主菜单把 `pending_backend_port` 写入场景 meta；若在进入主题页后后端**自动重启**或绑定到其它端口（54322），meta 仍为 54321，首次 `/api/chat` 会连到错误进程或空端口 → `HTTPRequest.RESULT_CONNECTION_ERROR`。

2. **残留 `ai-backend-win.exe`**  
   上次 Godot/测试未退出干净，54321 被占用，新进程监听 54322，而客户端仍访问 54321。

3. **Windows 命令行剥掉 JSON 引号**  
   `JSON.stringify` 经 `OS.execute_with_pipe` 传给子进程时，引号被剥掉，Node 先报 JSON 解析失败；exe 内 Godot dict fallback 通常仍能启动。Launcher 在 Windows 上已改为直接传 Godot 字典字面量，减少误导日志。

4. **首次世界生成时后端真崩溃**  
   若日志在 `SERVER_STARTED_ON_PORT=` 之后立刻 `后端进程已退出`，需查看同段 `[BackendLauncher]` 输出中的 API/端口提示；无效 API Key 一般返回 HTTP 500 而不会杀进程。

### 100% 复现步骤（开发机）

```powershell
# 1. 制造残留后端（占用 54321）
Start-Process ".\ai_backend\ai-backend-win.exe"
# 2. 启动 Godot，主菜单等后端就绪（Launcher 可能绑到 54322）
# 3. 新游戏 → 主题页 → 确认主题（meta 仍为 54321 时必现连接中断）

# 或：主题页停留期间，在设置里保存 AI 配置触发 restart_backend，再确认主题
```

### 修复与自检

1. 主题页在发起生成前调用 `BackendLauncher.get_live_port()`（见 `novel_type_picker.gd`）。
2. 启动前清理残留：`taskkill /F /IM ai-backend-win.exe`（Launcher `_cleanup_stale_backend` 已加长 settle 时间）。
3. 确认 `user://ai_config/aiConfig.json` 含有效 `api_key` / `model` / `website`。
4. 运行：`godot --headless -s tests/backend_launcher_ai_config_test.gd`

### 相关文件

- `src/backend/backend_launcher.gd` — 启动、清理、Windows argv 格式
- `src/main_menu/novel_type_picker.gd` — 端口同步与 `resolve_client_port`
- `src/backend/ai_client.gd` — `RESULT_CONNECTION_ERROR` 文案
