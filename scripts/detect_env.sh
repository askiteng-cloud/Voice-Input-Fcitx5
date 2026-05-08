#!/bin/bash
# detect_env.sh - Environment probe for AI-assisted installation
# Usage: bash scripts/detect_env.sh
# Outputs a single-line JSON to stdout.

set -euo pipefail

# --- Helper functions ---
json_str() {
    # Minimal JSON string escape
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n\r'
}

bool_json() {
    if "$@" >/dev/null 2>&1; then
        echo "true"
    else
        echo "false"
    fi
}

# --- Path Detection ---
PWD_VAL="${PWD}"
REPO_DIR=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_DIR="$(git rev-parse --show-toplevel)"
else
    # Fallback: assume current dir if markers exist
    if [[ -f "install.sh" && -f "server.py" ]]; then
        REPO_DIR="${PWD}"
    else
        REPO_DIR="NOT_FOUND"
    fi
fi

HOME_VAL="${HOME}"
INSTALL_DIR="${HOME}/.local/share/fcitx5-sherpa"
PLUGIN_SO="${HOME}/.local/lib/fcitx5/sherpa-bridge.so"
PLUGIN_CONF="${HOME}/.local/share/fcitx5/addon/sherpa-bridge.conf"
SOCKET_PATH="${HOME}/.fcitx5_sherpa.sock"

# --- OS Detection ---
OS_ID="unknown"
OS_FAMILY="unknown"
PKG_MANAGER="unknown"
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    case "${ID}" in
        arch|manjaro)
            OS_FAMILY="arch"
            PKG_MANAGER="pacman"
            ;;
        ubuntu|debian|pop|linuxmint|zorin)
            OS_FAMILY="debian"
            PKG_MANAGER="apt"
            ;;
        fedora|rhel|centos|almalinux|rocky)
            OS_FAMILY="redhat"
            PKG_MANAGER="dnf"
            ;;
        opensuse*)
            OS_FAMILY="suse"
            PKG_MANAGER="zypper"
            ;;
    esac
fi

# --- Version Detection ---
FCITX5_VERSION="not_found"
if command -v fcitx5 >/dev/null 2>&1; then
    FCITX5_VERSION="$(fcitx5 --version 2>/dev/null || echo "found_but_failed")"
fi

PYTHON3_VERSION="not_found"
if command -v python3 >/dev/null 2>&1; then
    PYTHON3_VERSION="$(python3 --version 2>&1 || echo "found_but_failed")"
fi

CMAKE_VERSION="not_found"
if command -v cmake >/dev/null 2>&1; then
    CMAKE_VERSION="$(cmake --version 2>/dev/null | head -n1 || echo "found_but_failed")"
fi

# --- Installation State ---
HAS_GIT_REPO="false"
if [[ "${REPO_DIR}" != "NOT_FOUND" ]]; then
    HAS_GIT_REPO="true"
fi

HAS_EXISTING_INSTALL="false"
if [[ -d "${INSTALL_DIR}" && -f "${INSTALL_DIR}/server.py" ]]; then
    HAS_EXISTING_INSTALL="true"
fi

HAS_SYSTEMD_SERVICE="false"
if systemctl --user list-unit-files fcitx5-sherpa.service >/dev/null 2>&1; then
    HAS_SYSTEMD_SERVICE="true"
fi

HAS_MODELS="false"
MODEL_TOTAL_SIZE=0
if [[ -d "${INSTALL_DIR}/models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20" ]]; then
    HAS_MODELS="true"
    MODEL_TOTAL_SIZE="$(du -sb "${INSTALL_DIR}/models" 2>/dev/null | awk '{print $1}' || echo 0)"
elif [[ -d "${REPO_DIR}/models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20" ]]; then
    HAS_MODELS="true"
    MODEL_TOTAL_SIZE="$(du -sb "${REPO_DIR}/models" 2>/dev/null | awk '{print $1}' || echo 0)"
fi

PLUGIN_INSTALLED="false"
if [[ -f "${PLUGIN_SO}" && -f "${PLUGIN_CONF}" ]]; then
    PLUGIN_INSTALLED="true"
fi

SOCKET_EXISTS="false"
SOCKET_OWNER_PID=""
if [[ -S "${SOCKET_PATH}" ]]; then
    SOCKET_EXISTS="true"
    # Try to find owner via fuser or ss
    if command -v fuser >/dev/null 2>&1; then
        SOCKET_OWNER_PID="$(fuser "${SOCKET_PATH}" 2>/dev/null || true)"
    elif command -v ss >/dev/null 2>&1; then
        SOCKET_OWNER_PID="$(ss -xp | grep -o 'pid=[0-9]*' | head -n1 | cut -d= -f2 || true)"
    fi
fi

# --- Audio Subsystem ---
AUDIO_SYSTEM="unknown"
if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
    AUDIO_SYSTEM="pulseaudio"
elif command -v pw-cli >/dev/null 2>&1; then
    AUDIO_SYSTEM="pipewire"
elif command -v pipewire >/dev/null 2>&1; then
    AUDIO_SYSTEM="pipewire"
fi

HAS_MICROPHONE="false"
if command -v arecord >/dev/null 2>&1; then
    if arecord -l 2>/dev/null | grep -q 'card'; then
        HAS_MICROPHONE="true"
    fi
elif command -v pactl >/dev/null 2>&1; then
    if pactl list sources 2>/dev/null | grep -qi 'Name:.*input'; then
        HAS_MICROPHONE="true"
    fi
fi

# --- Service Status ---
SERVICE_STATUS="not_installed"
SERVICE_PID=""
SERVICE_MEMORY_PEAK=""
if [[ "${HAS_SYSTEMD_SERVICE}" == "true" ]]; then
    SERVICE_STATUS="$(systemctl --user show fcitx5-sherpa.service -p ActiveState --value 2>/dev/null || echo "unknown")"
    SERVICE_PID="$(systemctl --user show fcitx5-sherpa.service -p MainPID --value 2>/dev/null || echo "")"
    SERVICE_MEMORY_PEAK="$(systemctl --user show fcitx5-sherpa.service -p MemoryPeak --value 2>/dev/null || echo "")"
fi

# --- Python Virtual Environment ---
VENV_PYTHON="not_found"
VENV_HAS_SHERPA="false"
VENV_HAS_NUMPY="false"
VENV_HAS_SOUNDDEVICE="false"
VENV_HAS_CN2AN="false"
if [[ -f "${INSTALL_DIR}/venv/bin/python" ]]; then
    VENV_PYTHON="${INSTALL_DIR}/venv/bin/python"
    pip_list="$(${VENV_PYTHON} -m pip list 2>/dev/null || true)"
    if echo "${pip_list}" | grep -qi '^sherpa-onnx'; then
        VENV_HAS_SHERPA="true"
    fi
    if echo "${pip_list}" | grep -qi '^numpy'; then
        VENV_HAS_NUMPY="true"
    fi
    if echo "${pip_list}" | grep -qi '^sounddevice'; then
        VENV_HAS_SOUNDDEVICE="true"
    fi
    if echo "${pip_list}" | grep -qi '^cn2an'; then
        VENV_HAS_CN2AN="true"
    fi
fi

# --- Output JSON ---
cat <<EOF
{
  "paths": {
    "pwd": "$(json_str "${PWD_VAL}")",
    "repo_dir": "$(json_str "${REPO_DIR}")",
    "home": "$(json_str "${HOME_VAL}")",
    "install_dir": "$(json_str "${INSTALL_DIR}")",
    "plugin_so": "$(json_str "${PLUGIN_SO}")",
    "plugin_conf": "$(json_str "${PLUGIN_CONF}")",
    "socket_path": "$(json_str "${SOCKET_PATH}")"
  },
  "os": {
    "id": "$(json_str "${OS_ID}")",
    "family": "$(json_str "${OS_FAMILY}")",
    "package_manager": "$(json_str "${PKG_MANAGER}")"
  },
  "versions": {
    "fcitx5": "$(json_str "${FCITX5_VERSION}")",
    "python3": "$(json_str "${PYTHON3_VERSION}")",
    "cmake": "$(json_str "${CMAKE_VERSION}")"
  },
  "state": {
    "has_git_repo": ${HAS_GIT_REPO},
    "has_existing_install": ${HAS_EXISTING_INSTALL},
    "has_systemd_service": ${HAS_SYSTEMD_SERVICE},
    "has_models": ${HAS_MODELS},
    "model_total_size_bytes": ${MODEL_TOTAL_SIZE},
    "plugin_installed": ${PLUGIN_INSTALLED},
    "socket_exists": ${SOCKET_EXISTS},
    "socket_owner_pid": "$(json_str "${SOCKET_OWNER_PID}")"
  },
  "hardware_audio": {
    "audio_system": "$(json_str "${AUDIO_SYSTEM}")",
    "has_microphone": ${HAS_MICROPHONE}
  },
  "service": {
    "status": "$(json_str "${SERVICE_STATUS}")",
    "pid": "$(json_str "${SERVICE_PID}")",
    "memory_peak_bytes": "$(json_str "${SERVICE_MEMORY_PEAK}")"
  },
  "python_venv": {
    "python_executable": "$(json_str "${VENV_PYTHON}")",
    "has_sherpa_onnx": ${VENV_HAS_SHERPA},
    "has_numpy": ${VENV_HAS_NUMPY},
    "has_sounddevice": ${VENV_HAS_SOUNDDEVICE},
    "has_cn2an": ${VENV_HAS_CN2AN}
  }
}
EOF
