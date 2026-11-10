#!/usr/bin/env bash
# Create (or update) the Open WebUI container from the OFFICIAL image, listening on 127.0.0.1 only.
#   scripts/owui-docker.sh            # default tag below
#   scripts/owui-docker.sh v0.13.4    # update: same data, new image
# Why Docker on an Intel Mac: Open WebUI >= 0.8 is no longer installable/reliable natively
# (onnxruntime, PyTorch >= 2.4 and a NumPy-2-compatible PyTorch don't exist for macOS x86_64).
# The container reaches the Mac's native services (llama-server, Whisper) through
# host.docker.internal, which Lima relays to the Mac's 127.0.0.1 — they stay loopback-only.
# Env overrides: OWUI_NAME, OWUI_PORT, OWUI_DATA, OWUI_SECRET_FILE, LLAMA_URL, STT_URL
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
TAG="${1:-v0.13.3}"
NAME="${OWUI_NAME:-open-webui}"
PORT="${OWUI_PORT:-3000}"
DATA="${OWUI_DATA:-$HOME/.local/share/open-webui-docker}"
SK_FILE="${OWUI_SECRET_FILE:-$HOME/.config/open-webui/secret_key}"
LLAMA_URL="${LLAMA_URL:-http://host.docker.internal:8080/v1}"

mkdir -p "$DATA" "$(dirname "$SK_FILE")"; chmod 700 "$(dirname "$SK_FILE")"
[ -s "$SK_FILE" ] || { openssl rand -hex 32 > "$SK_FILE"; chmod 600 "$SK_FILE"; }
colima status >/dev/null 2>&1 || colima start --vm-type vz --mount-type virtiofs --cpu 4 --memory 6 --disk 30

docker pull "ghcr.io/open-webui/open-webui:$TAG"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# DEFAULT_MODEL_METADATA: Open WebUI >= 0.12 enables "builtin tools" on every model by default and
# injects their descriptions into EVERY request (~7,000 extra tokens -> 40 s of prompt processing
# on this GPU). Off by default here; per-model settings still win.
docker run -d --name "$NAME" --restart unless-stopped \
  -p "127.0.0.1:$PORT:8080" --add-host=host.docker.internal:host-gateway \
  -v "$DATA":/app/backend/data \
  -e WEBUI_SECRET_KEY="$(cat "$SK_FILE")" \
  -e OPENAI_API_BASE_URL="$LLAMA_URL" -e OPENAI_API_KEY=local \
  -e ENABLE_OLLAMA_API=False \
  -e DEFAULT_MODEL_METADATA='{"capabilities":{"builtin_tools":false}}' \
  -e ENABLE_EVALUATION_ARENA_MODELS=False \
  -e SCARF_NO_ANALYTICS=true -e DO_NOT_TRACK=true -e ANONYMIZED_TELEMETRY=false \
  "ghcr.io/open-webui/open-webui:$TAG" >/dev/null
for _ in $(seq 120); do curl -sf -o /dev/null "127.0.0.1:$PORT/health" && break; sleep 3; done
echo "Open WebUI $(curl -s "127.0.0.1:$PORT/api/version") on http://localhost:$PORT"
