# Sherpa-Voice-Fcitx5 设计文档

## 1. 目标
在 Linux (Arch Linux) 平台上实现一个基于 `sherpa-onnx` 的纯离线语音输入法，并深度集成到 Fcitx5 框架中。

## 2. 技术栈
- **ASR 引擎**: `sherpa-onnx` (基于 ONNX Runtime)
- **编程语言**: Python 3.10+ (后端逻辑), Lua (Fcitx5 插件)
- **音频处理**: PipeWire / PortAudio + RNNoise (降噪)
- **通信协议**: Unix Domain Socket (UDS)
- **输入集成**: Fcitx5 Lua Addon + DBus (作为备选)

## 3. 核心架构
1. **Back-end (Python)**:
   - 持续采集麦克风流。
   - VAD (语音活动检测) 识别说话起止。
   - `sherpa-onnx` 进行流式识别。
   - 通过 UDS 发送 `{"type": "preedit", "text": "..."}` 或 `{"type": "commit", "text": "..."}`。
2. **Front-end (Fcitx5 Lua)**:
   - 作为 Fcitx5 的 Addon 运行。
   - 监听 UDS。
   - 调用 `fcitx.updatePreedit()` 在光标处显示中间结果。
   - 调用 `fcitx.commitString()` 将最终结果上屏。

## 4. 关键考虑点
- **Wayland 兼容性**: 通过 Fcitx5 原生接口避开 Wayland 的模拟输入限制。
- **性能**: 使用流式 Zipformer 模型，确保延迟 < 200ms。
- **降噪**: 集成 RNNoise 过滤环境噪音。
