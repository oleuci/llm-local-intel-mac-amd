#!/usr/bin/env bash
# Create (or update) the Open WebUI container from the OFFICIAL image, listening on 127.0.0.1 only.
#   scripts/owui-docker.sh            # default tag below
#   scripts/owui-docker.sh v0.13.4    # update: same data, new image
# Why Docker on an Intel Mac: Open WebUI >= 0.8 is no longer installable/reliable natively
# (onnxruntime, PyTorch >= 2.4 and a NumPy-2-compatible PyTorch don't exist for macOS x86_64).
# The container reaches the Mac's native services (llama-server, Whisper) through
# host.docker.internal, which Lima relays to the Mac's 127.0.0.1 — they stay loopback-only.
# Web search goes through a local SearXNG container (scripts/searxng-docker.sh) on the private Docker
# network below; nothing else is exposed.
# Env overrides: OWUI_NAME, OWUI_PORT, OWUI_DATA, OWUI_SECRET_FILE, OWUI_NETWORK, LLAMA_URL, STT_URL
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
TAG="${1:-v0.13.3}"
NAME="${OWUI_NAME:-open-webui}"
PORT="${OWUI_PORT:-3000}"
DATA="${OWUI_DATA:-$HOME/.local/share/open-webui-docker}"
SK_FILE="${OWUI_SECRET_FILE:-$HOME/.config/open-webui/secret_key}"
LLAMA_URL="${LLAMA_URL:-http://host.docker.internal:8080/v1}"
NET="${OWUI_NETWORK:-owui-net}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$DATA" "$(dirname "$SK_FILE")"; chmod 700 "$(dirname "$SK_FILE")"
[ -s "$SK_FILE" ] || { openssl rand -hex 32 > "$SK_FILE"; chmod 600 "$SK_FILE"; }
colima status >/dev/null 2>&1 || colima start --vm-type vz --mount-type virtiofs --cpu 4 --memory 6 --disk 30

docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
docker pull "ghcr.io/open-webui/open-webui:$TAG"
docker rm -f "$NAME" >/dev/null 2>&1 || true
# DEFAULT_MODEL_METADATA: Open WebUI >= 0.12 enables "builtin tools" on every model by default and
# injects their descriptions into EVERY request (~7,000 extra tokens -> 40 s of prompt processing
# on this GPU). Off by default here; per-model settings still win.
# Web search (button in the chat input, off until you click it):
#  - function_calling = legacy: in "native" mode Open WebUI 0.13 does NOT run the search when you click
#    the button — it waits for the model to call the builtin web_search tool, and builtin tools are off.
#  - engine snippets only (BYPASS_WEB_LOADER + BYPASS_EMBEDDING): title + link + ~150-char summary of
#    6 results per query, < 1,000 tokens; no page downloads, no CPU embedding -> fast. Downloading pages
#    was the slow part, identical for every model.
#  - RAG_SOURCE_METADATA_KEYS: pass each result's URL and title to the model; by default it only sees
#    numbered text and would invent links.
#  - RAG_TEMPLATE (open-webui/rag-template.md): the default template is appended to the USER message, so it
#    overrides the system prompt, and it only asks for [id] citations. Ours asks for a short summary
#    (5 points max) and a final "Sources" list with the real URLs.
#  - multilingual embedding model (used for attached documents): all-MiniLM-L6-v2 is English-only.
# These env values seed the configuration on FIRST start only; afterwards the admin UI is authoritative.
docker run -d --name "$NAME" --restart unless-stopped --network "$NET" \
  -p "127.0.0.1:$PORT:8080" --add-host=host.docker.internal:host-gateway \
  -v "$DATA":/app/backend/data \
  -e WEBUI_SECRET_KEY="$(cat "$SK_FILE")" \
  -e OPENAI_API_BASE_URL="$LLAMA_URL" -e OPENAI_API_KEY=local \
  -e ENABLE_OLLAMA_API=False \
  -e DEFAULT_MODEL_METADATA='{"capabilities":{"builtin_tools":false,"web_search":true}}' \
  -e DEFAULT_MODEL_PARAMS='{"function_calling":"legacy"}' \
  -e ENABLE_WEB_SEARCH=True -e WEB_SEARCH_ENGINE=searxng \
  -e SEARXNG_QUERY_URL=http://searxng:8080/search -e WEB_SEARCH_RESULT_COUNT=6 \
  -e BYPASS_WEB_SEARCH_WEB_LOADER=True -e BYPASS_WEB_SEARCH_EMBEDDING_AND_RETRIEVAL=True \
  -e RAG_SOURCE_METADATA_KEYS=source,title \
  -e RAG_TEMPLATE="$(cat "$HERE/open-webui/rag-template.md")" \
  -e RAG_EMBEDDING_MODEL=intfloat/multilingual-e5-small \
  -e 'RAG_EMBEDDING_QUERY_PREFIX=query: ' -e 'RAG_EMBEDDING_CONTENT_PREFIX=passage: ' \
  -e ENABLE_EVALUATION_ARENA_MODELS=False \
  -e SCARF_NO_ANALYTICS=true -e DO_NOT_TRACK=true -e ANONYMIZED_TELEMETRY=false \
  "ghcr.io/open-webui/open-webui:$TAG" >/dev/null
for _ in $(seq 120); do curl -sf -o /dev/null "127.0.0.1:$PORT/health" && break; sleep 3; done
echo "Open WebUI $(curl -s "127.0.0.1:$PORT/api/version") on http://localhost:$PORT"
