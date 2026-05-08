# AGENTS.md — Voice-Input-Fcitx5

> This file provides context for AI coding assistants working on this project.

## Project Overview

- **Name**: Fcitx5-Sherpa Offline Voice Input Method
- **Purpose**: High-performance, low-latency offline speech recognition for Fcitx5 on Linux
- **Engine**: Sherpa-ONNX (ONNX Runtime-based ASR)
- **Languages**: C++ (Fcitx5 plugin), Python 3.10+ (backend)

## Key Architecture

1. **Backend (Python)**: `server.py`
   - Captures microphone stream via `sounddevice`
   - Streaming recognition with `sherpa_onnx.OnlineRecognizer`
   - Sends results via Unix Domain Socket (`~/.fcitx5_sherpa.sock`)
   - Toggled by `SIGUSR1`

2. **Frontend (C++ Fcitx5 Addon)**: `fcitx5-sherpa-bridge/`
   - Listens on UDS
   - Calls `fcitx.updatePreedit()` and `fcitx.commitString()`

## Critical File Mapping

| File | Role | Runtime Sync Required? |
|------|------|----------------------|
| `server.py` | Python backend logic | **Yes** → `~/.local/share/fcitx5-sherpa/server.py` |
| `config.json` | ASR / punctuation config | **Yes** → `~/.local/share/fcitx5-sherpa/config.json` |
| `hotwords.txt` | Custom hotwords for ASR | **Yes** → `~/.local/share/fcitx5-sherpa/hotwords.txt` |
| `fcitx5-sherpa-bridge/` | C++ plugin source | Compiled to `~/.local/lib/fcitx5/sherpa-bridge.so` |

## AI Installation & Troubleshooting

**For any install, fix, or debug task**:  
→ **Read `INSTALL.ai.md` first.**  
→ **Run `bash scripts/detect_env.sh` before making changes.**

That document contains:
- Environment discovery rules
- Decision trees for first-install vs repair
- OS-specific dependency matrices
- Known traps (API drift, audio sample rates, path sync)
- Verification checklists

## Coding Conventions

- Python: Follow PEP 8; use `True`/`False` (not JSON `true`/`false`) in dict literals
- C++: Follow existing Fcitx5 addon style
- Config files: JSON for user-facing config; `.conf` for Fcitx5 addon metadata

## Common Pitfalls for AI

1. **Path confusion**: `REPO_DIR` (source) vs `INSTALL_DIR` (`~/.local/share/fcitx5-sherpa/`). Always sync changes.
2. **API version**: `sherpa-onnx` 1.10+ uses `OnlineRecognizer.from_transducer()`, not `OnlineRecognizerConfig`.
3. **Hidden dependency**: `sounddevice` requires `numpy`, which may not be pulled in automatically.
4. **Audio devices**: Hardware ALSA devices often reject 16000Hz; use `pulse` or `pipewire` virtual device.
5. **Fcitx5 reload**: After installing/updating the C++ plugin, `fcitx5 -rd` is required to load it.
