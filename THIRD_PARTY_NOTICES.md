# 第三方组件声明

本仓库在开发与运行时可能依赖以下第三方软件。除另有说明外，**未随仓库分发**的编辑器插件需自行安装（见 [README.md](README.md)）。

## 运行时依赖

| 组件 | 版本 | 用途 | 许可 |
|------|------|------|------|
| [Godot Engine](https://godotengine.org/) | 4.6 | 游戏引擎 | [MIT](https://github.com/godotengine/godot/blob/master/LICENSE.txt) |

## 开发时依赖（可选，未入库）

以下插件位于 `addons/`，已在 `.gitignore` 中排除，克隆仓库后需自行获取：

| 组件 | 版本 | 用途 | 许可 / 上游 |
|------|------|------|-------------|
| [GUT](https://github.com/bitwes/Gut) | 9.6.0 | 单元测试 | [MIT](https://github.com/bitwes/Gut/blob/master/LICENSE) |
| HasturOperationGD | 0.1 | 编辑器远程执行（AI 辅助开发） | 见 [Raiix/hasturoperationgd](https://github.com/Raiix/hasturoperationgd) |
| Godot AI | 2.5.0 | 编辑器 MCP / AI 工具 | 见上游仓库 |
| 2D_making_tool | — | 2D 多边形角色制作（编辑器） | 见上游 |

## 伴生程序（随仓库分发）

| 组件 | 用途 | 许可 |
|------|------|------|
| `ai_backend/ai-backend-*` | 本地 AI HTTP 代理 | [ai_backend/LICENSE](ai_backend/LICENSE)（伴生程序许可，非 AGPL） |

## 主项目许可

Godot 项目源码、场景、Prompt 模板等（不含 `ai_backend/` 预编译二进制）适用 [LICENSE](LICENSE)（GNU AGPL-3.0），版权人：良思工作室。
