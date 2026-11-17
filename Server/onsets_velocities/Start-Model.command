#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
python_bin=""
for candidate in python3.12 python3.11 python3.10 python3; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys; assert (3,10) <= sys.version_info[:2] <= (3,12)' 2>/dev/null; then
        python_bin="$candidate"; break
    fi
done
if [ -z "$python_bin" ]; then
    echo "请先安装 Python 3.10–3.12，再重新打开此文件。"
    exit 1
fi
if [ ! -d .venv ]; then "$python_bin" -m venv .venv; fi
source .venv/bin/activate
python -m pip install -r requirements.txt
mkdir -p .cache
source_path="$PWD/.cache/iamusica_training"
source_commit=629ff11aceadf01ecc456b1c7f26a104f7e1e571
if [ ! -d "$source_path/.git" ]; then
    git init "$source_path"
    git -C "$source_path" remote add origin https://github.com/andres-fr/iamusica_training.git
    git -C "$source_path" fetch --depth 1 origin "$source_commit"
    git -C "$source_path" checkout --detach "$source_commit"
fi
if [ "$(git -C "$source_path" rev-parse HEAD)" != "$source_commit" ]; then
    echo "模型源码版本不匹配。请使用一个新的工作目录，避免覆盖已有源码。"; exit 1
fi
if command -v ipconfig >/dev/null 2>&1; then
    model_ip=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || true)
    if [ -n "$model_ip" ]; then echo "iPad 中填写：ws://$model_ip:8765/recognize"; fi
fi
python server.py --source "$source_path" \
    --sha256 90901ff8c7cb15c76a4da2f4aca643a10295c834ac9e549ee16097d4bbce642d \
    --host 0.0.0.0 "$@"
