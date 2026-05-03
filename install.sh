#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Fcitx5-Sherpa 离线语音输入法通用安装程序 ===${NC}"

# 1. 发行版检测与依赖安装
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case $ID in
        arch|manjaro)
            echo "检测到 Arch-based 系统，正在安装依赖..."
            sudo pacman -S --needed --noconfirm base-devel cmake extra-cmake-modules fcitx5 fcitx5-qt python python-pip
            ;;
        ubuntu|debian|pop)
            echo "检测到 Debian-based 系统，正在安装依赖..."
            sudo apt update
            sudo apt install -y build-essential cmake extra-cmake-modules fcitx5-module-dev python3 python3-pip python3-venv
            ;;
        fedora)
            echo "检测到 Fedora 系统，正在安装依赖..."
            sudo dnf install -y gcc-c++ cmake extra-cmake-modules fcitx5-devel python3 python3-pip
            ;;
        *)
            echo -e "${RED}未识别的发行版: $ID。请确保已手动安装 fcitx5-dev, cmake, gcc 和 python。${NC}"
            ;;
    esac
fi

# 2. 下载模型
if [ ! -d "models" ]; then
    echo -e "${BLUE}正在调用模型下载脚本...${NC}"
    bash scripts/download_models.sh
fi

# 3. 编译并安装 C++ Bridge
echo -e "${BLUE}正在编译 C++ 插件...${NC}"
mkdir -p fcitx5-sherpa-bridge/build
cd fcitx5-sherpa-bridge/build
cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/.local
make install
cd ../..

# 4. 部署 Python 后端
INSTALL_DIR="$HOME/.local/share/fcitx5-sherpa"
echo -e "${BLUE}正在部署服务至 $INSTALL_DIR ...${NC}"
mkdir -p "$INSTALL_DIR/models"
cp server.py hotwords.txt "$INSTALL_DIR/"
cp -r models/* "$INSTALL_DIR/models/"

# 5. 配置 Python 虚拟环境
echo -e "${BLUE}正在配置 Python 虚拟环境并安装依赖...${NC}"
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install sherpa-onnx sounddevice cn2an

# 6. 配置 Systemd User Service
echo -e "${BLUE}正在配置 Systemd 用户服务...${NC}"
mkdir -p "$HOME/.config/systemd/user/"
cat <<EOF > "$HOME/.config/systemd/user/fcitx5-sherpa.service"
[Unit]
Description=Fcitx5 Sherpa Voice Backend
After=fcitx5.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/server.py
WorkingDirectory=$INSTALL_DIR
Restart=always
RestartSec=3
StandardOutput=append:/tmp/sherpa_server.log
StandardError=append:/tmp/sherpa_server.log

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now fcitx5-sherpa.service

echo -e "${GREEN}安装完成！${NC}"
echo -e "你可以通过运行以下命令查看实时识别日志："
echo -e "${BLUE}journalctl --user -u fcitx5-sherpa -f${NC}"
echo -e "提示：如果是首次安装，请尝试运行 'fcitx5 -rd' 重启输入法以加载插件。"
