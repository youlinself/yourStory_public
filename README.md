# Your Story

> 一款基于 AI 驱动的**类小说生成器**，让你以**游戏**的视角沉浸式体验小说世界。

## 项目简介

**Your Story（你的故事）** 将传统小说阅读与游戏化体验相结合。借助大语言模型，你可以：

- **以游戏的方式阅读小说** — 亲历主角的冒险，而非被动翻页
- **AI 实时生成剧情** — 每一次选择都通向不同的命运
- **沉浸式体验** — 文字、剧情、抉择融为一体

告别旁观者视角，在这里，**你即是主角**。

## 简单体验

无需克隆源码或安装 Godot，Windows 用户可直接试玩：

1. 从 [github](https://github.com/youlinself/yourStory_public/blob/main/dist.zip) 下载 `dist.zip`
2. 解压到任意目录
3. 双击运行 `main.exe`

首次启动请在游戏内 **设置 → AI** 填写 API Key（需自行准备兼容 OpenAI API 的服务，见下方「环境要求」）。

## 许可证

本仓库采用**双组件许可**：

| 范围 | 许可 |
|------|------|
| Godot 源码、场景、Prompt 模板、测试等 | [GNU AGPL-3.0](LICENSE)（版权人：良思工作室） |
| `ai_backend/` 预编译二进制 | [伴生程序许可](ai_backend/LICENSE) |

第三方组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 环境要求

- **Godot Engine 4.6**（从 [godotengine.org](https://godotengine.org/download) 下载；勿将本地 Godot 放入 `.tools/` 并提交）
- **操作系统**：Windows（当前主要开发与导出平台；仓库内含 Linux / macOS 后端二进制）
- **AI 服务**：需自行准备兼容 OpenAI API 的 API Key（OpenAI、DeepSeek、MiniMax 等，见游戏内设置）

## 快速开始（开发）

### 1. 克隆并打开项目

```bash
git clone <仓库 URL>
```

用 Godot 4.6 打开根目录下的 `project.godot`。

### 2. 配置 AI

任选其一：

**方式 A — 开发默认配置（推荐首次运行）**

```bash
cp ai_config/aiConfig.example.json ai_config/aiConfig.json
```

编辑 `ai_config/aiConfig.json`，将 `ai.api_key` 替换为你的 Key，并填写 `model` 等字段。

**方式 B — 游戏内设置**

启动游戏 → **设置** → **AI** 页填写并保存。配置将写入 `user://ai_config/aiConfig.json`。

> `ai_config/aiConfig.json` 已在 `.gitignore` 中，**切勿提交含真实 Key 的文件**。

### 3. 运行

在 Godot 编辑器中按 F5，或导出后运行 `dist/main.exe`（导出目录见下方「构建发行」）。

### 4. 运行测试（可选）

安装 [GUT](https://github.com/bitwes/Gut) 到 `addons/gut/` 后，可用 headless 运行单个测试脚本，例如：

```powershell
godot --headless -s tests/backend_launcher_ai_config_test.gd
godot --headless -s tests/narrative_context_logic_test.gd
```

更多排查说明见 [docs/godot-gdscript-troubleshooting.md](docs/godot-gdscript-troubleshooting.md)。

## 项目结构（摘要）

```
your-story-public/
├── LICENSE                    # AGPL-3.0（主项目源码）
├── THIRD_PARTY_NOTICES.md     # 第三方组件声明
├── project.godot
├── ai_config/
│   ├── aiConfig.example.json  # AI / 游戏配置模板
│   └── AiSkills/              # Prompt 与技能配置
├── ai_backend/                # 预编译 AI 代理（独立许可）
├── src/                       # GDScript 源码
├── sences/                    # 场景
├── tests/                     # Headless 测试
└── docs/                      # 开发文档
```

## 构建发行

导出预设见 `export_presets.cfg`，默认输出到 `dist/main.exe`。`dist/` 与 `dist.zip` 已在 `.gitignore` 中。

在 Godot 中选择 **项目 → 导出** → **Windows Desktop** 进行打包。导出物需与 `ai_backend/` 目录一并分发。

## 安全提示

- **不要**提交 `ai_config/aiConfig.json`、`.env` 或任何含 API Key 的文件
- **不要**提交 `ai_backend/*.txt` 等后端运行日志（可能泄露 Key）
- **不要**提交 `novel_txt/`（个人游戏导出）、`.tools/`（本地 Godot SDK）、`game_runtime_data/` / `game_history/`（本地存档）
- 若 Key 曾意外写入日志或提交，请立即在服务商控制台**轮换/作废**该 Key

## 技术栈

- Godot 4.6 + GDScript
- 本地 AI HTTP 代理（`ai_backend`）
- 多厂商 OpenAI 兼容 API

## 后续计划

- [ ] 支持 macOS / Linux 平台导出
- [ ] 更多剧情模板与世界观
- [ ] 角色自定义与存档系统增强
