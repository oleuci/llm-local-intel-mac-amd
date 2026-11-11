#!/usr/bin/env bash
# Create (or update) the SearXNG container used by Open WebUI's web search.
#   scripts/searxng-docker.sh            # pinned tag below
#   scripts/searxng-docker.sh <tag>      # update
# SearXNG is a metasearch engine: no account, no API key; it queries Google, Bing, DuckDuckGo... itself.
# NO port is published on the Mac: Open WebUI reaches it by name on the private Docker network
# (http://searxng:8080/search). Test: docker exec searxng wget -qO- 'http://127.0.0.1:8080/search?q=test&format=json'
# Env overrides: SEARXNG_NAME, SEARXNG_CONF, SEARXNG_SECRET_FILE, OWUI_NAME, OWUI_NETWORK
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
TAG="${1:-2026.11.11-248b8ffc0}"
NAME="${SEARXNG_NAME:-searxng}"
CONF="${SEARXNG_CONF:-$HOME/.local/share/searxng}"
SK_FILE="${SEARXNG_SECRET_FILE:-$HOME/.config/searxng/secret_key}"
NET="${OWUI_NETWORK:-owui-net}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

mkdir -p "$CONF" "$(dirname "$SK_FILE")"; chmod 700 "$(dirname "$SK_FILE")"
[ -s "$SK_FILE" ] || { openssl rand -hex 32 > "$SK_FILE"; chmod 600 "$SK_FILE"; }
sed "s#__SECRET__#$(cat "$SK_FILE")#" "$HERE/searxng/settings.yml" > "$CONF/settings.yml"
chmod 600 "$CONF/settings.yml"
colima status >/dev/null 2>&1 || colima start --vm-type vz --mount-type virtiofs --cpu 4 --memory 6 --disk 30
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
docker pull -q "searxng/searxng:$TAG" >/dev/null
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --network-alias searxng --restart unless-stopped --network "$NET" \
  -v "$CONF":/etc/searxng \
  --cap-drop ALL --cap-add CHOWN --cap-add SETGID --cap-add SETUID \
  "searxng/searxng:$TAG" >/dev/null
# If Open WebUI already runs, attach it to the network (owui-docker.sh does it at creation)
docker network connect "$NET" "${OWUI_NAME:-open-webui}" 2>/dev/null || true
for _ in $(seq 30); do docker exec "$NAME" wget -qO- 'http://127.0.0.1:8080/healthz' >/dev/null 2>&1 && break; sleep 2; done
N="$(docker exec "$NAME" wget -qO- 'http://127.0.0.1:8080/search?q=open+webui&format=json' | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["results"]))' 2>/dev/null || echo 0)"
echo "SearXNG $TAG ready ($N results for a test query), reachable from Open WebUI as http://searxng:8080"
