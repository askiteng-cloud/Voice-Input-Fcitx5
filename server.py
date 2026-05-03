#!/home/askiteng/app/vi-fcitx5/venv/bin/python
import sherpa_onnx
import sounddevice as sd
import sys
import socket
import cn2an

def send_to_fcitx(sock, text_type, text):
    msg = f"{text_type}:{text}".encode('utf-8')
    try:
        sock.send(msg)
    except Exception as e:
        pass

def main():
    model_dir = "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
    
    punct_model_dir = "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12"
    punct_model_config = sherpa_onnx.OfflinePunctuationModelConfig(
        ct_transformer=f"{punct_model_dir}/model.onnx",
        num_threads=1,
    )
    punct_config = sherpa_onnx.OfflinePunctuationConfig(punct_model_config)
    punct_model = sherpa_onnx.OfflinePunctuation(punct_config)
    
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    try:
        sock.connect("/tmp/fcitx5_sherpa.sock")
    except Exception as e:
        print(f"Warning: Failed to connect to Fcitx5 sherpa socket: {e}")
    
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
    except AttributeError:
        # Fallback to newer API if from_transducer doesn't exist
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
        
        try:
            recognizer = sherpa_onnx.OnlineRecognizer.from_config(config)
        except AttributeError:
            recognizer = sherpa_onnx.OnlineRecognizer(config)

    stream = recognizer.create_stream()
    
    # Global state for toggling
    global is_listening, ui_needs_update
    is_listening = False
    ui_needs_update = True

    def toggle_listening(signum, frame):
        global is_listening, ui_needs_update
        is_listening = not is_listening
        ui_needs_update = True
        state_str = "ON" if is_listening else "OFF"
        import os
        if is_listening:
            os.system('notify-send "🎙️ 语音输入开启" -t 1000')
        else:
            os.system('notify-send "🔇 语音输入关闭" -t 1000')
        print(f"\n[Signal] Toggled listening state to: {state_str}")

    import signal
    signal.signal(signal.SIGUSR1, toggle_listening)
    
    print("Started in PAUSED state. (Press Ctrl+C to stop)")
    print("Run `pkill -SIGUSR1 -f server.py` to toggle recording ON/OFF.")
    
    def callback(indata, frames, time, status):
        if not is_listening:
            return
        if status:
            print(status, file=sys.stderr)
        samples = indata[:, 0].flatten()
        stream.accept_waveform(16000, samples)

    try:
        last_text = ""
        import time
        with sd.InputStream(channels=1, samplerate=16000, dtype="float32", callback=callback):
            while True:
                if ui_needs_update:
                    if is_listening:
                        send_to_fcitx(sock, "PREEDIT", "🎙️ 录音中...")
                        last_text = ""
                    else:
                        send_to_fcitx(sock, "PREEDIT", "")
                        recognizer.reset(stream)
                        last_text = ""
                    ui_needs_update = False

                if not is_listening:
                    time.sleep(0.1)
                    continue

                while recognizer.is_ready(stream):
                    recognizer.decode_stream(stream)
                
                is_endpoint = recognizer.is_endpoint(stream)
                text = recognizer.get_result(stream)
                
                if text and text != last_text:
                    print(f"\r{text}", end="")
                    sys.stdout.flush()
                    send_to_fcitx(sock, "PREEDIT", text)
                    last_text = text
                
                if is_endpoint:
                    if text:
                        itn_text = cn2an.transform(text, "cn2an")
                        punctuated_text = punct_model.add_punctuation(itn_text)
                        print(f"\r{punctuated_text}")
                        send_to_fcitx(sock, "COMMIT", punctuated_text)
                    recognizer.reset(stream)
                    last_text = ""
                
                time.sleep(0.02)  # Prevent 100% CPU polling
    except KeyboardInterrupt:
        print("\nExiting...")

if __name__ == "__main__":
    main()
