#!/bin/bash
set -e

# 定义模型下载地址
ASR_MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20.tar.bz2"
PUNCT_MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/punctuation-models/sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12.tar.bz2"

MODEL_DIR="models"
mkdir -p "$MODEL_DIR"

download_and_extract() {
    local url=$1
    local target_dir=$2
    local filename=$(basename "$url")

    if [ -d "$MODEL_DIR/$target_dir" ]; then
        echo "--- 模型 $target_dir 已存在，跳过下载。"
        return
    fi

    echo "--- 正在下载 $filename ..."
    curl -L "$url" -o "$filename"
    
    echo "--- 正在解压 $filename ..."
    tar -xjf "$filename" -C "$MODEL_DIR"
    rm "$filename"
}

# 执行下载
download_and_extract "$ASR_MODEL_URL" "sherpa-onnx-streaming-zipformer-bilingual-zh-en-2023-02-20"
download_and_extract "$PUNCT_MODEL_URL" "sherpa-onnx-punct-ct-transformer-zh-en-vocab272727-2024-04-12"

echo "--- 所有模型已准备就绪。"
