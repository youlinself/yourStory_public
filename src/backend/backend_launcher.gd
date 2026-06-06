extends Node

## Emitted when the backend has started and its port number has been discovered.
signal backend_ready(port: int)

## Emitted when the backend fails to start or exits unexpectedly (after auto-restart retries are exhausted).
signal backend_failed(reason: String)

## Emitted when the backend exited unexpectedly and an automatic restart is scheduled.
signal backend_restarting(attempt: int, max_attempts: int, reason: String)

const BACKEND_DIR := "res://ai_backend"
## 导出版：与 main.exe 同目录下的后端子目录名。
const EXPORTED_BACKEND_DIR := "ai_backend"
const CONFIG_PATH := "user://ai_config/aiConfig.json"
const CONFIG_PATH_DEFAULT := "res://ai_config/aiConfig.json"
const PID_FILE := "user://backend.pid"
const PORT_PREFIX := "SERVER_STARTED_ON_PORT="
const PORT_RANGE_START := 54321
const PORT_RANGE_END := 54330
const MAX_AUTO_RESTART_ATTEMPTS := 5
const AUTO_RESTART_DELAY_SEC := 2.0
## taskkill 后等待端口释放（Windows 上 FIN_WAIT 可能导致新进程绑定到其它端口）。
const CLEANUP_SETTLE_MS := 800

## 传给 ai-backend 进程的字段；不含 auth_* / models_url（含空格，Windows argv 会拆参）。
const BACKEND_AI_CONFIG_KEYS: Array[StringName] = [
	&"api_key",
	&"model",
	&"vendor",
	&"website",
	&"reasoning_effort",
	&"thinking",
	&"max_tokens",
]

var _thread: Thread
var _stdio: FileAccess
var _pid: int = -1
var _port: int = -1
var _started := false
var _intentional_stop := false
var _failure_hint := ""
var _auto_restart_attempts := 0
var _restart_timer: Timer


func _ready() -> void:
	_restart_timer = Timer.new()
	_restart_timer.one_shot = true
	_restart_timer.timeout.connect(_on_auto_restart_timer_timeout)
	add_child(_restart_timer)
	_cleanup_stale_backend()


func start_backend() -> void:
	_cancel_auto_restart()
	if _started:
		printerr("[BackendLauncher] 后端已经在启动或运行中")
		return
	_started = true
	_intentional_stop = false
	_failure_hint = ""

	_cleanup_stale_backend()

	var exe_name := _exe_name_for_platform()
	var exe_path := _resolve_path(exe_name)
	print("[BackendLauncher] 后端路径: ", exe_path)

	if not FileAccess.file_exists(exe_path):
		_reset_launch_state()
		backend_failed.emit("后端程序不存在: %s" % exe_path)
		printerr("后端程序不存在: %s" % exe_path)
		return

	var ai_config := _sanitize_ai_config_for_backend(_load_ai_config())
	var args: PackedStringArray = []
	if not ai_config.is_empty():
		args.append(_format_ai_config_argv(ai_config))

	var result := OS.execute_with_pipe(exe_path, args)
	if result.is_empty():
		_reset_launch_state()
		backend_failed.emit("启动后端失败")
		printerr("启动后端失败")
		return

	_stdio = result["stdio"]
	_pid = result["pid"]
	_write_pid_file(_pid)
	print("[BackendLauncher] 后端进程已启动，PID: ", _pid)

	_thread = Thread.new()
	_thread.start(_read_stdout)


func restart_backend() -> void:
	print("[BackendLauncher] 正在重启后端…")
	_cancel_auto_restart()
	_auto_restart_attempts = 0
	stop_backend()
	start_backend()


func stop_backend() -> void:
	_kill_backend()


func is_ready() -> bool:
	return _port > 0 and _pid > 0 and OS.is_process_running(_pid)


func is_running() -> bool:
	return _started


func _load_ai_config() -> Dictionary:
	var path := CONFIG_PATH
	if not FileAccess.file_exists(path):
		path = CONFIG_PATH_DEFAULT
		if not FileAccess.file_exists(path):
			printerr("[BackendLauncher] 配置文件不存在: %s 或 %s" % [CONFIG_PATH, CONFIG_PATH_DEFAULT])
			return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("[BackendLauncher] 无法读取配置文件")
		return {}
	var text := file.get_as_text()
	if text.is_empty():
		return {}
	var json = JSON.parse_string(text)
	if json is Dictionary and json.has("ai"):
		return json["ai"]
	return {}


static func _sanitize_ai_config_for_backend(ai_config: Dictionary) -> Dictionary:
	if ai_config.is_empty():
		return {}
	var out: Dictionary = {}
	for key in BACKEND_AI_CONFIG_KEYS:
		if not ai_config.has(key):
			continue
		var value: Variant = ai_config[key]
		if value is String and (value as String).strip_edges().is_empty():
			continue
		out[key] = value
	return out


func _exe_name_for_platform() -> String:
	match OS.get_name():
		"Windows":
			return "ai-backend-win.exe"
		"macOS":
			return "ai-backend-macos"
		_:
			return "ai-backend-linux"


func _resolve_path(exe_name: String) -> String:
	if OS.has_feature("standalone"):
		var base := OS.get_executable_path().get_base_dir()
		var subdir_path := base.path_join(EXPORTED_BACKEND_DIR).path_join(exe_name)
		if FileAccess.file_exists(subdir_path):
			return subdir_path
		var flat_path := base.path_join(exe_name)
		if FileAccess.file_exists(flat_path):
			return flat_path
		return subdir_path
	return ProjectSettings.globalize_path(BACKEND_DIR.path_join(exe_name))


func _read_stdout() -> void:
	var port_reported := false
	while _stdio and _stdio.is_open():
		var line: String = _stdio.get_line()
		if line.is_empty():
			if _pid > 0 and not OS.is_process_running(_pid):
				break
			OS.delay_msec(50)
			continue

		print("[BackendLauncher] ", line)
		_capture_failure_hint(line)

		if not port_reported and line.begins_with(PORT_PREFIX):
			port_reported = true
			var port_str := line.trim_suffix("\n").substr(PORT_PREFIX.length())
			_port = int(port_str)
			_on_backend_port_ready.call_deferred(_port)

	if _intentional_stop:
		return

	if not port_reported:
		_on_backend_died.call_deferred()
	else:
		_on_backend_exited.call_deferred()


func _on_backend_port_ready(port: int) -> void:
	_auto_restart_attempts = 0
	print("[BackendLauncher] 获取到后端端口: ", port)
	backend_ready.emit(port)


func _on_backend_died() -> void:
	var reason := _failure_hint if not _failure_hint.is_empty() else "后端进程意外退出"
	printerr("[BackendLauncher] 后端进程在报告端口前退出: ", reason)
	_handle_unexpected_exit(reason)


func _on_backend_exited() -> void:
	printerr("[BackendLauncher] 后端进程已退出")
	_handle_unexpected_exit("后端进程已退出")


func _handle_unexpected_exit(reason: String) -> void:
	if _intentional_stop:
		return
	_reset_launch_state()
	if _auto_restart_attempts >= MAX_AUTO_RESTART_ATTEMPTS:
		printerr("[BackendLauncher] 自动重启已达上限 (%d 次): %s" % [MAX_AUTO_RESTART_ATTEMPTS, reason])
		backend_failed.emit(reason)
		return
	_auto_restart_attempts += 1
	print(
		"[BackendLauncher] 将在 %.1f 秒后自动重启后端（第 %d/%d 次）: %s"
		% [AUTO_RESTART_DELAY_SEC, _auto_restart_attempts, MAX_AUTO_RESTART_ATTEMPTS, reason]
	)
	backend_restarting.emit(_auto_restart_attempts, MAX_AUTO_RESTART_ATTEMPTS, reason)
	_restart_timer.start(AUTO_RESTART_DELAY_SEC)


func _on_auto_restart_timer_timeout() -> void:
	if _intentional_stop or _started:
		return
	print("[BackendLauncher] 正在自动重启后端…")
	start_backend()


func _cancel_auto_restart() -> void:
	if _restart_timer and _restart_timer.time_left > 0.0:
		_restart_timer.stop()


func get_port() -> int:
	return _port


## 客户端应连接的端口：仅在后端就绪时返回 Launcher 跟踪的端口（自动重启后会变化）。
func get_live_port() -> int:
	if is_ready():
		return _port
	return -1


## 优先使用 Launcher 当前端口，避免场景 meta 在自动重启后过期。
static func resolve_client_port(meta_port: int, launcher_port: int, launcher_ready: bool) -> int:
	if launcher_ready and launcher_port > 0:
		return launcher_port
	return meta_port


static func _format_ai_config_argv(ai_config: Dictionary) -> String:
	# Windows CreateProcess 会剥掉 JSON 引号，Node 端会 fallback 到 Godot dict 解析；
	# 在 Windows 上直接传 Godot 字典字面量，避免「标准 JSON 解析失败」误导日志。
	if OS.get_name() == "Windows":
		return _config_to_godot_dict_literal(ai_config)
	return JSON.stringify(ai_config)


static func _config_to_godot_dict_literal(ai_config: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in BACKEND_AI_CONFIG_KEYS:
		if not ai_config.has(key):
			continue
		var value: Variant = ai_config[key]
		if value is Dictionary:
			parts.append("%s:%s" % [key, _nested_dict_to_godot_literal(value as Dictionary)])
		elif value is String:
			parts.append("%s:%s" % [key, value])
		elif value is bool:
			parts.append("%s:%s" % [key, "true" if value else "false"])
		elif value is int or value is float:
			parts.append("%s:%s" % [key, str(value)])
		else:
			parts.append("%s:%s" % [key, str(value)])
	return "{%s}" % ",".join(parts)


static func _nested_dict_to_godot_literal(dict: Dictionary) -> String:
	var inner: PackedStringArray = []
	for k in dict.keys():
		var v: Variant = dict[k]
		if v is String:
			inner.append("%s:%s" % [k, v])
		elif v is bool:
			inner.append("%s:%s" % [k, "true" if v else "false"])
		else:
			inner.append("%s:%s" % [k, str(v)])
	return "{%s}" % ",".join(inner)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			_kill_backend()
		NOTIFICATION_PREDELETE:
			_kill_backend()


func _exit_tree() -> void:
	_kill_backend()


func _kill_backend() -> void:
	_intentional_stop = true
	_cancel_auto_restart()

	if _pid != -1:
		var pid := _pid
		_pid = -1
		print("[BackendLauncher] 正在关闭后端进程 PID: ", pid)
		_kill_process_tree(pid)
	else:
		_pid = -1
		_kill_all_backend_processes()

	_remove_pid_file()

	if _stdio:
		_stdio = null

	if _thread and _thread.is_alive():
		_thread.wait_to_finish()
	_thread = null

	_reset_launch_state()


func _reset_launch_state() -> void:
	_started = false
	_port = -1
	_pid = -1


func _kill_process_tree(pid: int) -> void:
	if pid <= 0:
		return
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/PID", str(pid), "/T", "/F"])
	elif OS.is_process_running(pid):
		OS.kill(pid)


func _write_pid_file(pid: int) -> void:
	var file := FileAccess.open(PID_FILE, FileAccess.WRITE)
	if file == null:
		printerr("[BackendLauncher] 无法写入 PID 文件")
		return
	file.store_string(str(pid))


func _remove_pid_file() -> void:
	if FileAccess.file_exists(PID_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_FILE))


func _capture_failure_hint(line: String) -> void:
	var trimmed := line.strip_edges()
	if trimmed.contains("Could not find an available port"):
		_failure_hint = "无法找到可用端口（54321–54330 均被占用）"
	elif trimmed.contains("未传入") and trimmed.contains("AI 配置"):
		_failure_hint = "未配置 AI（请在设置中填写并保存 AI 配置）"


func _kill_all_backend_processes() -> void:
	var exe_name := _exe_name_for_platform()
	match OS.get_name():
		"Windows":
			OS.execute("taskkill", ["/F", "/IM", exe_name])
		_:
			OS.execute("pkill", ["-f", exe_name])


func _cleanup_stale_backend() -> void:
	if FileAccess.file_exists(PID_FILE):
		var file := FileAccess.open(PID_FILE, FileAccess.READ)
		if file != null:
			var pid := int(file.get_as_text().strip_edges())
			file.close()
			if pid > 0 and OS.is_process_running(pid):
				print("[BackendLauncher] 发现残留后端进程 PID: ", pid, "，正在清理…")
				_kill_process_tree(pid)

	_kill_all_backend_processes()
	_remove_pid_file()
	OS.delay_msec(CLEANUP_SETTLE_MS)
