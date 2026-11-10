#!/usr/bin/env bash
# One-step installer: local LLM on an Intel Mac with an AMD GPU (Vulkan / MoltenVK).
#
#   curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --full      # + Open WebUI (Docker) + Whisper dictation
#
# Options:
#   --full          also install Open WebUI (official Docker image, via Colima) and Whisper dictation
#   --no-model      do not download the default model (Qwen 3.5 9B Q4_K_M + vision, ~6.5 GB)
#   --no-service    install files only, do not create/start LaunchAgents
#
# Everything goes under your home directory; nothing needs sudo.
# Nothing listens outside 127.0.0.1.
set -euo pipefail

REPO="oleuci/llm-local-intel-mac-amd"
REF="${LLM_LOCAL_REF:-main}"
PKG="llama-vulkan-macos-x64"
PKG_URL="${LLM_LOCAL_PKG_URL:-https://github.com/$REPO/releases/latest/download/$PKG.tar.gz}"
SRC_URL="${LLM_LOCAL_SRC_URL:-https://github.com/$REPO/archive/$REF.tar.gz}"   # overrides: for testing
HF="https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main"
MODEL="Qwen3.5-9B-Q4_K_M.gguf"
MMPROJ="mmproj-F16.gguf"

APP="$HOME/.local/share/llm-local-intel-mac-amd"   # repo files (templates, STT service)
BIN="$HOME/.local/share/llama-vk"                   # llama.cpp binaries
MODELS="$HOME/models"

FULL=0; WITH_MODEL=1; WITH_SERVICE=1
for a in "$@"; do case "$a" in
  --full) FULL=1 ;; --no-model) WITH_MODEL=0 ;; --no-service) WITH_SERVICE=0 ;;
  -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
  *) echo "unknown option: $a" >&2; exit 2 ;;
esac; done

say(){ printf '\n\033[1m==> %s\033[0m\n' "$*"; }
die(){ printf '\033[31mError: %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. Pre-flight checks ------------------------------------------------------
say "Checking this Mac"
[ "$(uname -s)" = Darwin ] || die "macOS only."
[ "$(uname -m)" = x86_64 ] || die "This package targets Intel Macs. On Apple Silicon, use Ollama/LM Studio directly (Metal works natively)."
OSMAJ="$(sw_vers -productVersion | cut -d. -f1)"
[ "$OSMAJ" -ge 12 ] || die "macOS 12 or later is required (found $(sw_vers -productVersion))."
GPU="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/{print $2}' | paste -sd ',' -)"
VRAM="$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/VRAM/{print $2}' | head -1)"
echo "macOS $(sw_vers -productVersion) | GPU: ${GPU:-unknown} | VRAM: ${VRAM:-unknown}"
case "$GPU" in *AMD*|*Radeon*) ;; *) echo "Warning: no AMD GPU detected; llama.cpp will fall back to the CPU." ;; esac
FREE_GB="$(df -g "$HOME" | awk 'NR==2{print $4}')"
[ "$FREE_GB" -ge 10 ] || die "At least 10 GB of free disk space is needed (found ${FREE_GB} GB)."

# --- 2. Repo files (templates, STT service) -----------------------------------
say "Fetching configuration files ($REPO@$REF)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$SRC_URL" | tar xz -C "$TMP"
mkdir -p "$APP"
cp -R "$TMP"/*/. "$APP/"
echo "-> $APP"

# --- 3. llama.cpp Vulkan binaries ---------------------------------------------
say "Downloading llama.cpp (Vulkan/MoltenVK) binaries"
curl -fsSL -o "$TMP/$PKG.tar.gz" "$PKG_URL"
curl -fsSL -o "$TMP/$PKG.tar.gz.sha256" "$PKG_URL.sha256"
(cd "$TMP" && shasum -a 256 -c "$PKG.tar.gz.sha256") || die "checksum mismatch"
tar xzf "$TMP/$PKG.tar.gz" -C "$TMP"
rm -rf "$BIN.new" && mv "$TMP/$PKG" "$BIN.new"
xattr -dr com.apple.quarantine "$BIN.new" 2>/dev/null || true   # curl sets none; belt and braces
rm -rf "$BIN.old"; [ -d "$BIN" ] && mv "$BIN" "$BIN.old"; mv "$BIN.new" "$BIN"; rm -rf "$BIN.old"
cat "$BIN/VERSION"

say "GPU check"
DEV="$("$BIN/bin/llama-server" --list-devices 2>/dev/null | grep -E '^\s*Vulkan[0-9]+:' || true)"
if [ -n "$DEV" ]; then echo "GPU usable by llama.cpp:$DEV"
else echo "Warning: no Vulkan device found — llama.cpp will run on the CPU (slow). See Troubleshooting in the README."; fi

# --- 4. Model -------------------------------------------------------------------
if [ "$WITH_MODEL" = 1 ]; then
  say "Downloading the default model (Qwen 3.5 9B Q4_K_M + vision projector, ~6.5 GB)"
  mkdir -p "$MODELS"
  for f in "$MODEL" "$MMPROJ"; do
    dest="$MODELS/$f"; [ "$f" = "$MMPROJ" ] && dest="$MODELS/mmproj-Qwen3.5-9B-F16.gguf"
    if [ -s "$dest" ]; then echo "already present: $dest"; continue; fi
    curl -fL --progress-bar -C - -o "$dest.part" "$HF/$f" && mv "$dest.part" "$dest"
  done
fi

# --- 5. Optional (--full): Whisper STT environment + Docker runtime ------------
if [ "$FULL" = 1 ]; then
  say "Installing the Whisper dictation environment (via uv)"
  if ! command -v uv >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/uv" ]; then
    echo "uv (Python package manager by Astral) is required: https://docs.astral.sh/uv/"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  PATH="$HOME/.local/bin:$PATH" "$APP/scripts/setup-stt.sh"
  say "Installing the Docker runtime (Colima + Lima + Docker CLI) for Open WebUI"
  "$APP/scripts/install-docker-tools.sh"
fi

# --- 6. Services ----------------------------------------------------------------
if [ "$WITH_SERVICE" = 1 ]; then
  say "Installing services (LaunchAgents)"
  "$APP/scripts/install-services.sh"
fi

# --- 7. Optional (--full): Open WebUI, official Docker image --------------------
# Native Open WebUI >= 0.8 can't be installed reliably on Intel Macs (see README).
if [ "$FULL" = 1 ]; then
  say "Starting Open WebUI (official Docker image) — first run downloads ~6.5 GB"
  "$APP/scripts/owui-docker.sh"
fi

if [ "$WITH_SERVICE" = 1 ]; then
  say "Health check"
  sleep 5
  "$APP/scripts/healthcheck.sh" || true
fi

say "Done"
echo "llama.cpp API (OpenAI-compatible): http://127.0.0.1:8080/v1"
[ "$FULL" = 1 ] && echo "Chat UI: http://localhost:3000  (first account created = admin)"
echo "Docs / tuning / troubleshooting: https://github.com/$REPO"
echo "Uninstall: $APP/uninstall.sh"
