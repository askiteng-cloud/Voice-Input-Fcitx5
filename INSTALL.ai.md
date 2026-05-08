# Voice-Input-Fcitx5 — AI Installation Guide

> **Audience**: This document is designed for AI coding assistants (Claude, Kimi, GPT, etc.)  
> **Purpose**: Enable reliable, dynamic installation and troubleshooting of this project across diverse Linux environments.  
> **Language**: 中文为主，代码注释保留英文。

---

## 0. 核心原则（Golden Rules）

### 0.1 诊断优先，修改后置
**在执行任何修改前，必须先运行环境探测脚本。**

```bash
bash scripts/detect_env.sh
```

将输出的 JSON 解析后，确认以下关键字段再决定下一步：
- `state.has_existing_install` — 区分「首次安装」与「修复/更新」
- `state.has_systemd_service` — 区分「文件已复制」与「服务已注册」
- `paths.repo_dir` — 用户当前是否位于项目目录
- `python_venv.has_*` — 虚拟环境依赖完整性

### 0.2 路径分离原则
本项目存在**两套并行路径**，AI 必须时刻区分：

| 类型 | 变量名 | 典型路径 | 用途 |
|------|--------|---------|------|
| 源码目录 | `REPO_DIR` | `~/projects/Voice-Input-Fcitx5/` | 编译、阅读文档、Git 操作 |
| 安装目录 | `INSTALL_DIR` | `~/.local/share/fcitx5-sherpa/` | 服务实际运行的文件、模型 |
| 插件目录 | `PLUGIN_DIR` | `~/.local/lib/fcitx5/` | C++ `.so` 运行时 |
| 插件配置 | `PLUGIN_CONF_DIR` | `~/.local/share/fcitx5/addon/` | Fcitx5 插件元数据 |

**致命错误示例**：仅修改 `REPO_DIR/server.py`，未同步到 `INSTALL_DIR/server.py`，导致服务重启后仍运行旧代码。

**正确流程**：
```bash
# 1. 修改源码
vim "${REPO_DIR}/server.py"

# 2. 必须同步到安装目录
cp "${REPO_DIR}/server.py" "${INSTALL_DIR}/server.py"
cp "${REPO_DIR}/config.json" "${INSTALL_DIR}/config.json"

# 3. 重启服务
systemctl --user restart fcitx5-sherpa

# 4. 验证生效
journalctl --user -u fcitx5-sherpa -n 5 --no-pager
```

### 0.3 权限边界
- ✅ **AI 可自动执行**：依赖安装（需用户确认 `sudo`）、模型下载、编译、venv 创建、服务启停
- ⚠️ **需用户确认**：覆盖现有配置文件、卸载其他输入法、修改系统级 Fcitx5 配置
- ❌ **禁止自动执行**：`rm -rf /`、`reboot`、删除用户主目录中非项目文件

---

## 1. 决策树（Decision Tree）

根据 `detect_env.sh` 的输出，按以下逻辑分支：

```
has_existing_install?
├── false → 首次安装流程（Section 2）
└── true
    ├── has_systemd_service == false → 半安装状态，补全服务配置（Section 3）
    ├── service.status != "active" → 故障排查流程（Section 4）
    └── has_models == false → 模型缺失，执行下载（Section 2.3）
```

---

## 2. 首次安装流程

### 2.1 前置检查清单
在运行 `install.sh` 前，确保：
- `os.package_manager` 不为 `unknown`
- `versions.python3` 包含 `3.10` 或更高版本
- `versions.cmake` 不为 `not_found`
- `hardware_audio.has_microphone` 为 `true`（若 `false`，警告用户可能无法使用语音功能，但不阻塞安装）

### 2.2 发行版依赖矩阵

| OS Family | 包管理器 | 必需包 | Python venv 模块 |
|-----------|---------|--------|-----------------|
| arch | `pacman -S --needed --noconfirm` | `base-devel cmake extra-cmake-modules fcitx5 fcitx5-qt python python-pip` | `python-virtualenv` 或 `python` 自带 |
| debian | `apt install -y` | `build-essential cmake extra-cmake-modules fcitx5-module-dev python3 python3-pip python3-venv` | `python3-venv` |
| redhat | `dnf install -y` | `gcc-c++ cmake extra-cmake-modules fcitx5-devel python3 python3-pip` | `python3-virtualenv` |
| suse | `zypper install -y` | `cmake extra-cmake-modules fcitx5-devel python3 python3-pip` | `python3-virtualenv` |

**注意**：`install.sh` 已包含部分发行版的自动检测，但 AI 应准备好处理：
- 包名差异（如 `fcitx5` vs `fcitx5-module-dev`）
- 用户拒绝提供 `sudo` 权限时的手动安装指导

### 2.3 模型下载与校验

模型文件很大（总计约 500MB+），下载中断会导致损坏。

**下载前检查**：
```bash
# 若 REPO_DIR 下 models/ 已存在且非空，询问用户是否跳过下载
if [[ -d "${REPO_DIR}/models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20" && \
      -s "${REPO_DIR}/models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/encoder-epoch-99-avg-1.onnx" ]]; then
    echo "Models appear to exist. Skipping download."
fi
```

**最小文件清单**（必须全部存在且大小 > 0）：
- `models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20/`
  - `encoder-epoch-99-avg-1.onnx` (~330MB)
  - `decoder-epoch-99-avg-1.onnx` (~13MB)
  - `joiner-epoch-99-avg-1.onnx` (~12MB)
  - `tokens.txt`
- `models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12/`
  - `model.onnx` (~280MB)

### 2.4 Python 虚拟环境依赖

`install.sh` 会安装：`sherpa-onnx sounddevice cn2an`

**AI 必须额外确保安装 `numpy`**（`sounddevice` 的隐式依赖，在部分环境中会缺失）：
```bash
"${INSTALL_DIR}/venv/bin/pip" install numpy
```

### 2.5 C++ 插件编译

编译发生在 `REPO_DIR/fcitx5-sherpa-bridge/build/`，但产物会被 `make install` 安装到 `${HOME}/.local/lib/fcitx5/`。

**常见问题**：
- CMake 找不到 Fcitx5 开发文件 → 确认 `fcitx5-module-dev`（Debian）或 `fcitx5-devel`（Fedora）已安装
- 编译成功但 Fcitx5 未加载 → 确认 `~/.local/share/fcitx5/addon/sherpa-bridge.conf` 存在且 `Library` 指向绝对路径

### 2.6 Fcitx5 加载插件

安装完成后，**必须**提醒用户：
```bash
fcitx5 -rd   # 重启 Fcitx5 以加载新插件
```

或在 AI 有权限时执行（可能断开当前输入法会话，需谨慎）。

---

## 3. 修复 / 更新流程

### 3.1 更新代码（如 server.py 修复）
```bash
REPO_DIR="$(git rev-parse --show-toplevel)"
INSTALL_DIR="${HOME}/.local/share/fcitx5-sherpa"

# 修改源码
# ... edit REPO_DIR/server.py ...

# 强制同步到运行时
cp "${REPO_DIR}/server.py" "${INSTALL_DIR}/server.py"
cp "${REPO_DIR}/config.json" "${INSTALL_DIR}/config.json"

# 重启
systemctl --user restart fcitx5-sherpa
```

### 3.2 模型更新
若用户需要更换模型：
1. 将新模型放入 `REPO_DIR/models/`
2. 修改 `REPO_DIR/config.json` 中的 `model_dir`
3. 同步 `config.json` 到 `INSTALL_DIR/`
4. 复制模型到 `INSTALL_DIR/models/`
5. 重启服务

---

## 4. 故障排查（Troubleshooting）

### 4.1 服务反复重启（`status=1/FAILURE`）

**排查步骤**：
1. 查看日志：
   ```bash
   journalctl --user -u fcitx5-sherpa -n 30 --no-pager
   ```
2. 直接运行以获取完整 Traceback：
   ```bash
   cd "${INSTALL_DIR}" && ./venv/bin/python server.py
   ```

**已知根本原因**：

| 症状 | 原因 | 修复 |
|------|------|------|
| `NameError: name 'true' is not defined` | `server.py` 中 `default_config` 误用 JSON 的 `true` | 改为 Python 的 `True` |
| `AttributeError: no attribute 'OnlineRecognizerConfig'` | `sherpa-onnx` >= 1.10 移除旧 API | 改用 `OnlineRecognizer.from_transducer(...)` |
| `ModuleNotFoundError: No module named 'numpy'` | 缺少 `numpy` | `venv/bin/pip install numpy` |
| `PortAudioError: Invalid sample rate` | 硬件声卡不支持 16000Hz | 指定 `device='pulse'` 或 `'pipewire'` |
| `Failed to encode some hotwords` | `hotwords.txt` 中有词不在模型词表 | 非致命，可忽略或清理 `hotwords.txt` |

### 4.2 插件未加载（Socket 文件不存在）

```bash
ls -la ~/.fcitx5_sherpa.sock
```

若不存在：
1. 检查插件文件是否存在：
   ```bash
   ls -la ~/.local/lib/fcitx5/sherpa-bridge.so
   ls -la ~/.local/share/fcitx5/addon/sherpa-bridge.conf
   ```
2. 检查 Fcitx5 是否加载了它：
   ```bash
   pgrep -a fcitx5   # 确认 fcitx5 正在运行
   # 查看 Fcitx5 日志（若可用）
   journalctl --user --no-pager | grep -i "sherpa\|bridge" | tail -20
   ```
3. 若 Fcitx5 是在插件安装前启动的，必须重启：
   ```bash
   fcitx5 -rd
   ```

### 4.3 语音输入无响应（服务运行但无文字上屏）

**分层诊断**：
1. **后端是否收到信号？**
   ```bash
   pkill -SIGUSR1 -f server.py
   tail -5 /tmp/sherpa_server.log
   # 应看到: [Signal] Toggled listening state to: ON
   ```
2. **后端是否采集到音频？**
   - 对着麦克风说话，观察日志是否有实时识别文本输出
   - 若无，检查 `hardware_audio.has_microphone`
3. **通信是否通畅？**
   - Socket 文件存在且属于 fcitx5 进程？
   - Python 端发送消息无报错？
4. **Fcitx5 是否获取到焦点？**
   - 必须在可输入文本的窗口（如文本编辑器）中测试
   - 插件日志中应出现 `handleSocket` 相关输出（若开启了调试）

---

## 5. 已知陷阱（Known Traps）

### Trap 1: API 版本漂移
`sherpa-onnx` 的 Python API 在 1.10+ 有重大变更。当前项目已适配 `from_transducer()` 模式，但若用户自行升级 `sherpa-onnx` 到未来版本，可能再次损坏。

**防御策略**：在 `server.py` 顶部添加版本检查：
```python
import sherpa_onnx
if not hasattr(sherpa_onnx.OnlineRecognizer, 'from_transducer'):
    raise RuntimeError("sherpa-onnx version too old or too new. Please check INSTALL.ai.md")
```

### Trap 2: 音频设备采样率
绝大多数笔记本内置麦克风通过 ALSA 直接访问时**不支持 16000Hz**。必须通过 PulseAudio/PipeWire 的软件重采样层。

**修复**：`sd.InputStream(device='pulse', ...)` 或 `'pipewire'`。

### Trap 3: PrivateTmp / 命名空间隔离
早期版本使用 `/tmp/fcitx5_sherpa.sock`，在 Systemd 的 `PrivateTmp` 环境下会导致 Python 与 Fcitx5 看不到同一个 socket。当前已迁移到 `${HOME}/.fcitx5_sherpa.sock`，AI 不应再建议使用 `/tmp`。

### Trap 4: 热词编码失败
`hotwords.txt` 中的英文大写词汇（如 `Docker`, `GPT`）可能不在模型的 `tokens.txt` 中。这会产生 C++ 级别警告，但**不会导致崩溃**。若用户报告启动时大量警告，告知这是正常的。

### Trap 5: 工作目录陷阱
用户可能在任意目录调用 AI。AI 必须先定位 `REPO_DIR`，不要假设 `PWD` 就是项目根目录。

---

## 6. 验证清单（Verification Checklist）

任何安装或修复操作完成后，AI 必须逐项确认：

- [ ] `bash scripts/detect_env.sh` 的 `state.has_existing_install` = `true`
- [ ] `state.has_systemd_service` = `true`
- [ ] `service.status` = `active`（或至少不是 `failed`）
- [ ] `state.plugin_installed` = `true`
- [ ] `state.socket_exists` = `true`
- [ ] `python_venv.has_sherpa_onnx` = `true`
- [ ] `python_venv.has_numpy` = `true`
- [ ] `python_venv.has_sounddevice` = `true`
- [ ] `python_venv.has_cn2an` = `true`
- [ ] `state.has_models` = `true` 且 `model_total_size_bytes` > 400000000（约 400MB）
- [ ] 发送 `SIGUSR1` 后，`/tmp/sherpa_server.log` 或 journalctl 中出现 `Toggled listening state to: ON`
- [ ] 用户已被告知需要运行 `fcitx5 -rd` 或重新登录（如果这是首次安装）

---

## 7. 快捷命令参考

```bash
# 查看服务状态
systemctl --user status fcitx5-sherpa --no-pager

# 实时跟踪日志
journalctl --user -u fcitx5-sherpa -f

# 手动重启服务
systemctl --user restart fcitx5-sherpa

# 切换语音输入开关
pkill -SIGUSR1 -f "fcitx5-sherpa/venv/bin/python.*server.py"

# 直接运行后端（调试用）
cd ~/.local/share/fcitx5-sherpa && ./venv/bin/python server.py

# 重启 Fcitx5（加载新插件）
fcitx5 -rd
```

---

## Appendix: 文件变更追踪

当 AI 修改以下文件时，必须同步到对应位置：

| 源文件（REPO_DIR） | 目标文件（INSTALL_DIR） | 同步命令 |
|-------------------|----------------------|---------|
| `server.py` | `~/.local/share/fcitx5-sherpa/server.py` | `cp server.py ~/.local/share/fcitx5-sherpa/` |
| `config.json` | `~/.local/share/fcitx5-sherpa/config.json` | `cp config.json ~/.local/share/fcitx5-sherpa/` |
| `hotwords.txt` | `~/.local/share/fcitx5-sherpa/hotwords.txt` | `cp hotwords.txt ~/.local/share/fcitx5-sherpa/` |
| `models/*` | `~/.local/share/fcitx5-sherpa/models/*` | `cp -r models/* ~/.local/share/fcitx5-sherpa/models/` |
| `fcitx5-sherpa-bridge/` | `~/.local/lib/fcitx5/sherpa-bridge.so` | `cd build && make install` |
