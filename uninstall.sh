#!/usr/bin/env bash
# Remove the services, binaries and Open WebUI container installed by install.sh.
# Models (~/models), Open WebUI data and the Colima VM are KEPT unless you pass --purge.
set -euo pipefail
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1
UID_="$(id -u)"
export PATH="$HOME/.local/bin:$PATH"
command -v docker >/dev/null 2>&1 && docker rm -f open-webui >/dev/null 2>&1 && echo "removed container: open-webui" || true
for l in com.llamacpp.vulkan com.whisper.stt com.ollama.serve com.colima.start; do
  launchctl bootout "gui/$UID_/$l" 2>/dev/null && echo "stopped: $l" || true
  rm -f "$HOME/Library/LaunchAgents/$l.plist"
done
rm -rf "$HOME/.local/share/llama-vk" "$HOME/.local/share/llm-local-intel-mac-amd" "$HOME/.local/share/whisper-stt"
echo "Removed binaries, STT environment and service definitions."
if [ "$PURGE" = 1 ]; then
  command -v colima >/dev/null 2>&1 && colima delete -f >/dev/null 2>&1 && echo "deleted the Colima VM" || true
  rm -f "$HOME/.local/bin/colima" "$HOME/.local/bin/docker" "$HOME/.local/bin/limactl" "$HOME/.local/bin/lima"
  rm -rf "$HOME/.local/opt/lima" "$HOME/.local/share/open-webui-docker" "$HOME/.config/open-webui" \
         "$HOME/models/Qwen3.5-9B-Q4_K_M.gguf" "$HOME/models/mmproj-Qwen3.5-9B-F16.gguf" \
         "$HOME/models/gemma-4-e4b-it-qat-q4_0.gguf" "$HOME/models/gemma-4-12b-it-qat-q4_0.gguf"
  echo "Purged: Colima VM + Docker tools, Open WebUI data and secret, the installed models."
else
  echo "Kept: ~/models, Open WebUI data (~/.local/share/open-webui-docker), Colima VM and Docker tools. Use --purge to remove them."
fi
