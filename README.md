# Fcitx5-Sherpa 离线语音输入法

基于 Sherpa-Onnx 的高性能、低延迟 Fcitx5 离线语音输入方案。支持 AI 智能标点恢复与中英文数字自动转写。

## 🚀 快速开始 (安装指南)

只需两步即可在你的 Linux 系统上完成安装：

### 1. 克隆并安装
```bash
git clone https://github.com/askiteng/Voice-Input-Fcitx5.git
cd Voice-Input-Fcitx5
./install.sh
```
该脚本会自动检测你的发行版（Arch, Ubuntu, Fedora），安装编译依赖，下载模型文件，并配置好后台服务。

### 2. 重启 Fcitx5
安装完成后，请运行以下命令或重新登录系统以加载插件：
```bash
fcitx5 -rd
```

## 🛠️ 使用说明
- **开启/关闭语音**：默认快捷键为 `$mod+Shift+v`（需根据你的窗口管理器配置，脚本会提示相关命令）。
- **实时日志**：`journalctl --user -u fcitx5-sherpa -f`
- **卸载**：`./uninstall.sh`

## ✨ 特性
- **完全离线**：无需网络，隐私安全。
- **智能标点**：自动识别停顿并添加“，。？！”，让语音输入更自然。
- **数字转写**：自动将“两千五百”转换为“2500”。
- **系统级集成**：原生 C++ 插件，极低延迟。
