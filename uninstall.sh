#!/bin/bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="${HOME}/.local/share/fcitx5-sherpa"
PLUGIN_SO="${HOME}/.local/lib/fcitx5/sherpa-bridge.so"
PLUGIN_CONF="${HOME}/.local/share/fcitx5/addon/sherpa-bridge.conf"
SERVICE_FILE="${HOME}/.config/systemd/user/fcitx5-sherpa.service"
SOCKET_PATH="${HOME}/.fcitx5_sherpa.sock"
LOG_FILE="/tmp/sherpa_server.log"

# 统计将要删除的内容
TO_DELETE=()

[ -f "$SERVICE_FILE" ] && TO_DELETE+=("$SERVICE_FILE")
[ -f "$PLUGIN_SO" ] && TO_DELETE+=("$PLUGIN_SO")
[ -f "$PLUGIN_CONF" ] && TO_DELETE+=("$PLUGIN_CONF")
[ -S "$SOCKET_PATH" ] && TO_DELETE+=("$SOCKET_PATH")
[ -f "$LOG_FILE" ] && TO_DELETE+=("$LOG_FILE")
[ -d "$INSTALL_DIR" ] && TO_DELETE+=("$INSTALL_DIR")

if [ ${#TO_DELETE[@]} -eq 0 ]; then
    echo -e "${YELLOW}⚠️  未检测到已安装的 Fcitx5-Sherpa 组件。${NC}"
    exit 0
fi

echo -e "${RED}=== Fcitx5-Sherpa 卸载程序 ===${NC}"
echo ""
echo -e "${YELLOW}以下项目将被永久删除：${NC}"
for item in "${TO_DELETE[@]}"; do
    echo "  - $item"
done
echo ""

# 非交互式模式检测
if [ -t 0 ]; then
    read -rp "确认卸载? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}已取消卸载。${NC}"
        exit 0
    fi
fi

echo ""

# 1. 停止并禁用服务
echo -e "${BLUE}[1/5] 停止并移除 Systemd 服务...${NC}"
if systemctl --user list-unit-files fcitx5-sherpa.service >/dev/null 2>&1; then
    systemctl --user stop fcitx5-sherpa.service || true
    systemctl --user disable fcitx5-sherpa.service || true
fi

if [ -f "$SERVICE_FILE" ]; then
    rm -f "$SERVICE_FILE"
    echo "  ✓ 已删除: $SERVICE_FILE"
fi

systemctl --user daemon-reload

# 2. 删除插件文件
echo -e "${BLUE}[2/5] 删除 Fcitx5 插件...${NC}"
if [ -f "$PLUGIN_SO" ]; then
    rm -f "$PLUGIN_SO"
    echo "  ✓ 已删除: $PLUGIN_SO"
fi

if [ -f "$PLUGIN_CONF" ]; then
    rm -f "$PLUGIN_CONF"
    echo "  ✓ 已删除: $PLUGIN_CONF"
fi

# 3. 清理 Socket 和日志
echo -e "${BLUE}[3/5] 清理运行时文件...${NC}"
if [ -S "$SOCKET_PATH" ]; then
    rm -f "$SOCKET_PATH"
    echo "  ✓ 已删除 socket: $SOCKET_PATH"
fi

if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
    echo "  ✓ 已删除日志: $LOG_FILE"
fi

# 4. 删除部署目录（包括模型、venv、配置）
echo -e "${BLUE}[4/5] 删除部署目录...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    # 获取目录大小用于显示
    size=$(du -sh "$INSTALL_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    rm -rf "$INSTALL_DIR"
    echo "  ✓ 已删除: $INSTALL_DIR (释放约 ${size} 空间)"
fi

# 5. 清理可能残留的用户级 Fcitx5 配置中的插件状态
echo -e "${BLUE}[5/5] 检查残留配置...${NC}"
FCITX5_CONFIG_DIR="${HOME}/.config/fcitx5"
if [ -d "$FCITX5_CONFIG_DIR" ]; then
    # 插件状态缓存目录，不同版本路径可能不同
    for cache_dir in \
        "${FCITX5_CONFIG_DIR}/addon/sherpa-bridge" \
        "${HOME}/.local/share/fcitx5/addon/sherpa-bridge" \
        "${HOME}/.cache/fcitx5/sherpa-bridge"
    do
        if [ -d "$cache_dir" ]; then
            rm -rf "$cache_dir"
            echo "  ✓ 已删除残留缓存: $cache_dir"
        fi
    done
fi

echo ""
echo -e "${GREEN}=== 卸载完成 ===${NC}"
echo ""
echo "Fcitx5-Sherpa 已完全移除。建议执行以下操作以完成清理："
echo ""
echo "  1) 重启 Fcitx5 以释放插件资源:"
echo -e "     ${YELLOW}fcitx5 -rd${NC}"
echo ""
echo "  2) 若不再需要模型文件，确认以下目录已清空："
echo "     $INSTALL_DIR"
echo ""

# 验证：列出仍存在的相关文件（应该是空的）
REMAINING=()
[ -f "$SERVICE_FILE" ] && REMAINING+=("$SERVICE_FILE")
[ -f "$PLUGIN_SO" ] && REMAINING+=("$PLUGIN_SO")
[ -f "$PLUGIN_CONF" ] && REMAINING+=("$PLUGIN_CONF")
[ -S "$SOCKET_PATH" ] && REMAINING+=("$SOCKET_PATH")
[ -d "$INSTALL_DIR" ] && REMAINING+=("$INSTALL_DIR")

if [ ${#REMAINING[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  警告: 以下文件仍存在于系统中（可能权限不足）：${NC}"
    for item in "${REMAINING[@]}"; do
        echo "  - $item"
    done
    exit 1
else
    echo -e "${GREEN}✓ 验证通过：所有组件已彻底清除。${NC}"
fi
