#!/usr/bin/env python3
import sherpa_onnx
import sounddevice as sd
import sys
import socket
import cn2an
import time
import os
import signal
import json
import subprocess

# --- 全局状态 ---
is_listening = False
ui_needs_update = True
last_active_time = time.time()
last_text = ""
sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
CONFIG = {}

def load_config():
    global CONFIG
    home = os.path.expanduser("~")
    base_dir = f"{home}/.local/share/fcitx5-sherpa"
    config_path = os.path.join(base_dir, "config.json")
    
    default_config = {
        "asr": {
            "model_dir": "models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20",
            "hotwords_file": "hotwords.txt",
            "hotwords_score": 2.5,
            "rule1_min_trailing_silence": 2.4,
            "rule2_min_trailing_silence": 1.2,
            "rule3_min_utterance_length": 300
        },
        "punctuation": {
            "model_dir": "models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12",
            "enabled": True
        },
        "ui": {
            "auto_timeout": 10.0,
            "enable_notifications": True,
            "realtime_itn": True
        }
    }

    if os.path.exists(config_path):
        try:
            with open(config_path, "r") as f:
                CONFIG = json.load(f)
        except Exception as e:
            print(f"Error loading config: {e}, using defaults")
            CONFIG = default_config
    else:
        CONFIG = default_config
    
    # 补全绝对路径
    CONFIG["asr"]["model_dir"] = os.path.join(base_dir, CONFIG["asr"]["model_dir"])
    CONFIG["punctuation"]["model_dir"] = os.path.join(base_dir, CONFIG["punctuation"]["model_dir"])
    CONFIG["asr"]["hotwords_file"] = os.path.join(base_dir, CONFIG["asr"]["hotwords_file"])

def send_notification(text, timeout=1000):
    if CONFIG.get("ui", {}).get("enable_notifications", True):
        try:
            subprocess.Popen(['notify-send', text, '-t', str(timeout)])
        except Exception:
            pass

def send_to_fcitx(text_type, text):
    msg = f"{text_type}:{text}".encode('utf-8')
    socket_path = os.path.expanduser("~/.fcitx5_sherpa.sock")
    try:
        sock.sendto(msg, socket_path)
    except Exception:
        pass

def toggle_listening(signum, frame):
    global is_listening, ui_needs_update, last_active_time
    is_listening = not is_listening
    ui_needs_update = True
    if is_listening:
        last_active_time = time.time()
    
    state_str = "ON" if is_listening else "OFF"
    if is_listening:
        send_notification("🎙️ 语音输入开启")
    else:
        send_notification("🔇 语音输入关闭")
    print(f"\n[Signal] Toggled listening state to: {state_str}", flush=True)

# 注册信号
signal.signal(signal.SIGUSR1, toggle_listening)

def main():
    global is_listening, ui_needs_update, last_active_time, last_text
    
    load_config()
    print("Loading models from config...", flush=True)
    
    # 标点模型加载
    punct_model = None
    if CONFIG["punctuation"]["enabled"]:
        punct_model_config = sherpa_onnx.OfflinePunctuationModelConfig(
            ct_transformer=os.path.join(CONFIG["punctuation"]["model_dir"], "model.onnx"),
            num_threads=1,
        )
        punct_config = sherpa_onnx.OfflinePunctuationConfig(punct_model_config)
        punct_model = sherpa_onnx.OfflinePunctuation(punct_config)
    
    # 识别模型加载
    recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
        tokens=os.path.join(CONFIG["asr"]["model_dir"], "tokens.txt"),
        encoder=os.path.join(CONFIG["asr"]["model_dir"], "encoder-epoch-99-avg-1.onnx"),
        decoder=os.path.join(CONFIG["asr"]["model_dir"], "decoder-epoch-99-avg-1.onnx"),
        joiner=os.path.join(CONFIG["asr"]["model_dir"], "joiner-epoch-99-avg-1.onnx"),
        num_threads=1,
        decoding_method="modified_beam_search",
        hotwords_file=CONFIG["asr"]["hotwords_file"],
        hotwords_score=CONFIG["asr"]["hotwords_score"],
        rule1_min_trailing_silence=CONFIG["asr"]["rule1_min_trailing_silence"],
        rule2_min_trailing_silence=CONFIG["asr"]["rule2_min_trailing_silence"],
        rule3_min_utterance_length=CONFIG["asr"]["rule3_min_utterance_length"],
        enable_endpoint_detection=True,
    )
    stream = recognizer.create_stream()

    def callback(indata, frames, time_info, status):
        if not is_listening:
            return
        if status:
            print(status, file=sys.stderr, flush=True)
        samples = indata[:, 0].flatten()
        stream.accept_waveform(16000, samples)

    print("Started. Ready for SIGUSR1 signals.", flush=True)
    last_print_tick = 0

    try:
        # 尝试使用 pulse/pipewire 设备以获得更好的采样率兼容性
        audio_device = None
        for dev in ['pulse', 'pipewire']:
            try:
                sd.check_input_settings(device=dev, samplerate=16000, channels=1)
                audio_device = dev
                break
            except Exception:
                pass
        
        with sd.InputStream(device=audio_device, channels=1, samplerate=16000, dtype="float32", callback=callback):
            while True:
                if ui_needs_update:
                    if is_listening:
                        send_to_fcitx("PREEDIT", "🎙️ 录音中...")
                        last_text = ""
                    else:
                        send_to_fcitx("PREEDIT", "")
                        recognizer.reset(stream)
                        last_text = ""
                    ui_needs_update = False

                if not is_listening:
                    time.sleep(0.1)
                    continue

                while recognizer.is_ready(stream):
                    recognizer.decode_stream(stream)
                
                is_endpoint = recognizer.is_endpoint(stream)
                text = recognizer.get_result(stream).strip()
                
                if text and text != last_text:
                    display_text = text
                    if CONFIG["ui"]["realtime_itn"]:
                        try:
                            display_text = cn2an.transform(text, "cn2an")
                        except: pass
                    
                    print(f"\r{display_text}", end="", flush=True)
                    send_to_fcitx("PREEDIT", display_text)
                    last_text = text
                    last_active_time = time.time()
                
                if is_endpoint:
                    if text:
                        final_text = cn2an.transform(text, "cn2an")
                        if punct_model:
                            final_text = punct_model.add_punctuation(final_text)
                        print(f"\r{final_text}", flush=True)
                        send_to_fcitx("COMMIT", final_text)
                    recognizer.reset(stream)
                    last_text = ""
                
                now = time.time()
                diff = now - last_active_time
                if is_listening and diff > CONFIG["ui"]["auto_timeout"]:
                    is_listening = False
                    ui_needs_update = True
                    send_notification("🔇 语音输入已自动关闭 (超时)", 1500)
                    print(f"\n[Timeout] Auto-closed after {diff:.1f}s.", flush=True)
                
                time.sleep(0.02)
    except KeyboardInterrupt:
        print("\nExiting...", flush=True)

if __name__ == "__main__":
    main()
