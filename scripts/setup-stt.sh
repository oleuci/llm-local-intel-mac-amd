#!/usr/bin/env bash
# Create the dedicated Python environment for the Whisper speech-to-text service.
# (Independent from Open WebUI: on Intel Macs Open WebUI runs in Docker, see README.)
# Usage: scripts/setup-stt.sh
set -euo pipefail
VENV="$HOME/.local/share/whisper-stt/venv"
UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
[ -x "$UV" ] || { echo "uv is required: https://docs.astral.sh/uv/" >&2; exit 1; }
"$UV" venv -q --python 3.11 "$VENV"
VIRTUAL_ENV="$VENV" "$UV" pip install -q "faster-whisper==1.2.1" "fastapi" "uvicorn" "python-multipart"
"$VENV/bin/python" -c "import faster_whisper, fastapi, uvicorn; print('STT environment OK:', faster_whisper.__version__)"
