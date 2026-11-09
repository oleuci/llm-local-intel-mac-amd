#!/usr/bin/env bash
# Install (or reinstall) the LaunchAgents from this repo's templates.
# Replaces __HOME__ / __REPO__ and keeps the existing WEBUI_SECRET_KEY
# (or generates one on first install).
# Prerequisites: see README (Ollama, llama.cpp Vulkan build, open-webui via uv, a GGUF model).
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"
LA="$HOME/Library/LaunchAgents"
UID_="$(id -u)"
mkdir -p "$LA" ~/Library/Logs/{ollama,llama-vk,open-webui,whisper-stt} ~/.local/share/open-webui

# Reuse the existing key, otherwise every Open WebUI session is invalidated
SK="$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:WEBUI_SECRET_KEY' \
      "$LA/com.openwebui.serve.plist" 2>/dev/null || openssl rand -hex 32)"

for p in launchd/*.plist; do
  label="$(basename "$p" .plist)"
  # Skip services whose program is not installed (e.g. Ollama or Open WebUI not chosen)
  exe="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" | sed "s#__HOME__#$HOME#g")"
  if [ ! -x "$exe" ]; then echo "skipped: $label (not installed: $exe)"; continue; fi
  launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  # bootout is asynchronous: wait for unload, otherwise bootstrap fails (error 5)
  for _ in $(seq 1 20); do launchctl print "gui/$UID_/$label" >/dev/null 2>&1 || break; sleep 0.5; done
  sed -e "s#__HOME__#$HOME#g" -e "s#__REPO__#$REPO#g" -e "s#__WEBUI_SECRET_KEY__#$SK#g" "$p" > "$LA/$label.plist"
  plutil -lint -s "$LA/$label.plist"
  launchctl bootstrap "gui/$UID_" "$LA/$label.plist"
  echo "loaded: $label"
done
chmod 600 "$LA/com.openwebui.serve.plist"
