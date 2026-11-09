#!/usr/bin/env bash
# Remove the services and binaries installed by install.sh.
# Models (~/models) and Open WebUI data are KEPT unless you pass --purge.
set -euo pipefail
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1
UID_="$(id -u)"
for l in com.llamacpp.vulkan com.whisper.stt com.openwebui.serve com.ollama.serve; do
  launchctl bootout "gui/$UID_/$l" 2>/dev/null && echo "stopped: $l" || true
  rm -f "$HOME/Library/LaunchAgents/$l.plist"
done
rm -rf "$HOME/.local/share/llama-vk" "$HOME/.local/share/llm-local-intel-mac-amd"
echo "Removed binaries and service definitions."
if [ "$PURGE" = 1 ]; then
  command -v uv >/dev/null && uv tool uninstall open-webui || true
  rm -rf "$HOME/.local/share/open-webui" "$HOME/models/Qwen3.5-9B-Q4_K_M.gguf" "$HOME/models/mmproj-Qwen3.5-9B-F16.gguf"
  echo "Purged Open WebUI (app + data) and the default model."
else
  echo "Kept: ~/models, Open WebUI and its data (~/.local/share/open-webui). Use --purge to remove them."
fi
