#!/usr/bin/env bash
# Install (or reinstall) the LaunchAgents from this repo's templates (replaces __HOME__ / __REPO__).
# Only services whose program is installed are loaded (e.g. Colima/Whisper only after --full).
# Open WebUI itself runs as a Docker container: see scripts/owui-docker.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"
LA="$HOME/Library/LaunchAgents"
UID_="$(id -u)"
mkdir -p "$LA" ~/Library/Logs/{ollama,llama-vk,whisper-stt,colima}

for p in launchd/*.plist; do
  label="$(basename "$p" .plist)"
  # Skip services whose program is not installed (e.g. Ollama, or Colima/Whisper without --full)
  exe="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$p" | sed "s#__HOME__#$HOME#g")"
  if [ ! -x "$exe" ]; then echo "skipped: $label (not installed: $exe)"; continue; fi
  launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  # bootout is asynchronous: wait for unload, otherwise bootstrap fails (error 5)
  for _ in $(seq 1 20); do launchctl print "gui/$UID_/$label" >/dev/null 2>&1 || break; sleep 0.5; done
  sed -e "s#__HOME__#$HOME#g" -e "s#__REPO__#$REPO#g" "$p" > "$LA/$label.plist"
  plutil -lint -s "$LA/$label.plist"
  launchctl bootstrap "gui/$UID_" "$LA/$label.plist"
  echo "loaded: $label"
done
