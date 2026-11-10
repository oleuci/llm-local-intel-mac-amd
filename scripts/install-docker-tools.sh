#!/usr/bin/env bash
# Install a Docker runtime for Intel Macs without Docker Desktop, sudo or Homebrew:
#   Colima (VM manager) + Lima (VM, Apple Virtualization.framework) + Docker CLI (static).
# Official binaries; Colima and Lima checksums are verified (Docker publishes none for its static CLI).
# Usage: scripts/install-docker-tools.sh
set -euo pipefail
COLIMA_VER="${COLIMA_VER:-v0.10.3}"
LIMA_VER="${LIMA_VER:-2.3.0}"
DOCKER_VER="${DOCKER_VER:-29.9.3}"
BIN="$HOME/.local/bin"; OPT="$HOME/.local/opt"
[ "$(uname -m)" = x86_64 ] || { echo "This script targets Intel Macs." >&2; exit 1; }
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 13 ] || { echo "macOS 13+ is required (vz virtualization)." >&2; exit 1; }
mkdir -p "$BIN" "$OPT/lima"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; cd "$T"

curl -fsSLO "https://github.com/lima-vm/lima/releases/download/v${LIMA_VER}/lima-${LIMA_VER}-Darwin-x86_64.tar.gz"
curl -fsSLO "https://github.com/lima-vm/lima/releases/download/v${LIMA_VER}/SHA256SUMS"
grep " lima-${LIMA_VER}-Darwin-x86_64.tar.gz\$" SHA256SUMS | shasum -a 256 -c -
tar xzf "lima-${LIMA_VER}-Darwin-x86_64.tar.gz" -C "$OPT/lima"
for b in limactl lima; do ln -sf "$OPT/lima/bin/$b" "$BIN/$b"; done

curl -fsSL -o colima "https://github.com/abiosoft/colima/releases/download/${COLIMA_VER}/colima-Darwin-x86_64"
curl -fsSL -o colima.sha "https://github.com/abiosoft/colima/releases/download/${COLIMA_VER}/colima-Darwin-x86_64.sha256sum"
echo "$(awk '{print $1}' colima.sha)  colima" | shasum -a 256 -c -
install -m 755 colima "$BIN/colima"

curl -fsSLO "https://download.docker.com/mac/static/stable/x86_64/docker-${DOCKER_VER}.tgz"
tar xzf "docker-${DOCKER_VER}.tgz" && install -m 755 docker/docker "$BIN/docker"

export PATH="$BIN:$PATH"
colima version | head -1; limactl --version; docker --version
echo "Next: colima start --vm-type vz --mount-type virtiofs --cpu 4 --memory 6 --disk 30"
