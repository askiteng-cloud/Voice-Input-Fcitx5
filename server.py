#!/home/askiteng/app/vi-fcitx5/venv/bin/python
import sherpa_onnx
import sounddevice as sd
import sys
import socket
import cn2an
import time
import os
import signal

# --- 全局状态与配置 ---
is_listening = False
ui_needs_update = True
last_active_time = time.time()
last_text = ""
sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)

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
        os.system('notify-send "🎙️ 语音输入开启" -t 1000')
    else:
        os.system('notify-send "🔇 语音输入关闭" -t 1000')
    print(f"\n[Signal] Toggled listening state to: {state_str}", flush=True)

# 立即注册信号，防止启动期间崩溃
signal.signal(signal.SIGUSR1, toggle_listening)

def main():
    global is_listening, ui_needs_update, last_active_time, last_text
    
    home = os.path.expanduser("~")
    base_dir = f"{home}/.local/share/fcitx5-sherpa"
    model_dir = f"{base_dir}/models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
    punct_model_dir = f"{base_dir}/models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12"
    
    print("Loading models...", flush=True)
    
    # 标点模型加载
    punct_model_config = sherpa_onnx.OfflinePunctuationModelConfig(
        ct_transformer=f"{punct_model_dir}/model.onnx",
        num_threads=1,
    )
    punct_config = sherpa_onnx.OfflinePunctuationConfig(punct_model_config)
    punct_model = sherpa_onnx.OfflinePunctuation(punct_config)
    
    # 识别模型加载
    try:
        recognizer = sherpa_onnx.OnlineRecognizer.from_transducer(
            tokens=f"{model_dir}/tokens.txt",
            encoder=f"{model_dir}/encoder-epoch-99-avg-1.onnx",
            decoder=f"{model_dir}/decoder-epoch-99-avg-1.onnx",
            joiner=f"{model_dir}/joiner-epoch-99-avg-1.onnx",
            num_threads=1,
            sample_rate=16000,
            feature_dim=80,
            decoding_method="modified_beam_search",
            hotwords_file="hotwords.txt",
            hotwords_score=2.5,
            modeling_unit="cjkchar+bpe",
            bpe_vocab=f"{model_dir}/bpe.vocab",
            enable_endpoint_detection=True,
            rule1_min_trailing_silence=2.4,
            rule2_min_trailing_silence=1.2,
            rule3_min_utterance_length=300,
        )
    except Exception:
        config = sherpa_onnx.OnlineRecognizerConfig()
        config.model_config.transducer.encoder = f"{model_dir}/encoder-epoch-99-avg-1.onnx"
        config.model_config.transducer.decoder = f"{model_dir}/decoder-epoch-99-avg-1.onnx"
        config.model_config.transducer.joiner = f"{model_dir}/joiner-epoch-99-avg-1.onnx"
        config.model_config.tokens = f"{model_dir}/tokens.txt"
        config.model_config.num_threads = 1
        config.decoding_method = "greedy_search"
        config.endpoint_config.rule1.min_trailing_silence = 2.4
        config.endpoint_config.rule2.min_trailing_silence = 1.2
        config.endpoint_config.rule3.min_utterance_length = 300
        recognizer = sherpa_onnx.OnlineRecognizer(config)

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
        with sd.InputStream(channels=1, samplerate=16000, dtype="float32", callback=callback):
            while True:
                # 1. 状态更新处理
                if ui_needs_update:
                    if is_listening:
                        send_to_fcitx("PREEDIT", "🎙️ 录音中...")
                        last_text = ""
                    else:
                        send_to_fcitx("PREEDIT", "")
                        recognizer.reset(stream)
                        last_text = ""
                    ui_needs_update = False

                # 2. 暂停模式优化
                if not is_listening:
                    time.sleep(0.1)
                    continue

                # 3. 语音解码
                while recognizer.is_ready(stream):
                    recognizer.decode_stream(stream)
                
                is_endpoint = recognizer.is_endpoint(stream)
                text = recognizer.get_result(stream)
                
                # 4. 实时反馈
                if text and text != last_text:
                    print(f"\r{text}", end="", flush=True)
                    send_to_fcitx("PREEDIT", text)
                    last_text = text
                    last_active_time = time.time() # 只要有新字，就重置计时器
                
                # 5. 完成提交
                if is_endpoint:
                    if text:
                        itn_text = cn2an.transform(text, "cn2an")
                        punctuated_text = punct_model.add_punctuation(itn_text)
                        print(f"\r{punctuated_text}", flush=True)
                        send_to_fcitx("COMMIT", punctuated_text)
                    recognizer.reset(stream)
                    last_text = ""
                
                # 6. 自动超时检测 (10秒)
                now = time.time()
                diff = now - last_active_time
                if is_listening and diff > 10:
                    is_listening = False
                    ui_needs_update = True
                    os.system('notify-send "🔇 语音输入已自动关闭 (10s超时)" -t 1500')
                    print(f"\n[Timeout] Auto-closed after {diff:.1f}s of silence.", flush=True)
                
                # 7. 每隔5秒在日志打印一次心跳，方便观察计时器
                if is_listening and int(diff) > last_print_tick and int(diff) % 5 == 0:
                    print(f"[Timer] Current silence: {int(diff)}s / 10s", flush=True)
                    last_print_tick = int(diff)
                elif not is_listening:
                    last_print_tick = 0

                time.sleep(0.02)
    except KeyboardInterrupt:
        print("\nExiting...", flush=True)

if __name__ == "__main__":
    main()
