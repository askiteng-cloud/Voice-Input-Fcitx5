# Voice-Input-Fcitx5 关键修复存档

## 1. 通信架构优化
- **变更**：通信接口从 `/tmp/fcitx5_sherpa.sock` 迁移至 `~/.fcitx5_sherpa.sock`。
- **原因**：避开 Linux 系统对 `/tmp` 目录的隔离（PrivateTmp），确保跨命名空间的可靠通信。
- **模式**：采用 UDP 风格的 `sendto` 机制，解决后端与 Fcitx5 启动顺序的依赖问题。

## 2. 插件加载策略
- **变更**：在 `sherpa-bridge.conf` 中显式指定 `Library` 为本地绝对路径 `~/.local/lib/fcitx5/sherpa-bridge`。
- **原因**：防止 Fcitx5 优先加载 `/usr/lib/fcitx5/` 下的旧版本插件。

## 3. 运行环境与模型路径
- **变更**：在 `server.py` 中使用绝对路径加载 ASR 模型与标点模型。
- **优化**：在 Systemd 服务中加入 `-u` 参数开启 Python 不缓存输出，便于日志实时调试。

## 4. 调试增强
- **变更**：在 C++ 插件中增加了详细的消息接收与焦点获取日志 (`FCITX_INFO`)。
- **效果**：实现了端到端的通信透明化，可精确判定故障点。

---
**存档时间**：2026-05-05
**存档人**：Antigravity AI
