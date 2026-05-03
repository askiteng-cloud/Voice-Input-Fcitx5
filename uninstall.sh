#!/bin/bash

# 颜色定义
RED='\033[0;31m'
NC='\033[0m'

echo -e "${RED}=== 正在卸载 Fcitx5-Sherpa ... ===${NC}"

# 1. 停止并禁用服务
systemctl --user stop fcitx5-sherpa.service || true
systemctl --user disable fcitx5-sherpa.service || true
rm -f "$HOME/.config/systemd/user/fcitx5-sherpa.service"
systemctl --user daemon-reload

# 2. 删除插件文件
rm -f "$HOME/.local/lib/fcitx5/sherpa-bridge.so"
rm -f "$HOME/.local/share/fcitx5/addon/sherpa-bridge.conf"

# 3. 删除部署目录
INSTALL_DIR="$HOME/.local/share/fcitx5-sherpa"
if [ -d "$INSTALL_DIR" ]; then
    echo "正在删除部署目录: $INSTALL_DIR"
    rm -rf "$INSTALL_DIR"
fi

echo "卸载完成。请手动重启 Fcitx5 以释放插件占用的资源。"
