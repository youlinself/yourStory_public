# AI Backend（伴生程序）

本目录包含「你的故事」(Your Story) 的本地 AI 代理后端，以预编译二进制形式分发。

## 文件说明

| 文件 | 平台 |
|------|------|
| `ai-backend-win.exe` | Windows |
| `ai-backend-linux` | Linux |
| `ai-backend-macos` | macOS |

## 运行方式

通常**不需要手动启动**。游戏启动时由 [`BackendLauncher`](../src/backend/backend_launcher.gd) 自动：

1. 根据当前操作系统选择对应二进制；
2. 从 `user://ai_config/aiConfig.json`（或 `res://ai_config/aiConfig.json`）读取 AI 配置；
3. 在本地端口范围 `54321–54330` 上启动 HTTP 服务。

开发模式下，二进制路径为 `res://ai_backend/<平台可执行文件>`；导出后位于与 `main.exe` 同级的 `ai_backend/` 目录。

## 配置

AI 相关字段（`api_key`、`model`、`vendor`、`website` 等）由游戏设置页写入配置文件。请参考仓库根目录的 [`ai_config/aiConfig.example.json`](../ai_config/aiConfig.example.json)。

**切勿**将含真实 API Key 的配置或后端运行日志（`*.txt`）提交到版本库。

## 许可

本目录中的预编译二进制适用 [`LICENSE`](LICENSE)（伴生程序许可），**不适用**仓库根目录的 GNU AGPL-3.0 源码提供义务。

主游戏源码（GDScript、场景、Prompt 模板等）的许可见根目录 [`LICENSE`](../LICENSE)。
