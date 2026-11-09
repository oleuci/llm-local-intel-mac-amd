#!/usr/bin/env bash
# Build the redistributable llama.cpp (Vulkan/MoltenVK) package published as a
# GitHub release asset. Reproducible: anyone can rebuild and compare.
#
# Differences from scripts/build-llama-vulkan.sh (local build):
#   - CMAKE_OSX_DEPLOYMENT_TARGET=12.0  -> runs on macOS 12+ (local builds target
#     the build host's macOS version and refuse to start on older systems)
#   - LLAMA_OPENSSL=OFF                 -> no hidden dependency on Homebrew's OpenSSL
#   - GGML_NATIVE=OFF + GGML_BACKEND_DL + GGML_CPU_ALL_VARIANTS
#                                       -> one package for every Intel CPU generation
#                                          (CPU backend picked at runtime)
#   - every rpath rewritten to @loader_path -> relocatable, no absolute paths
#
# Usage: scripts/package-release.sh [llama.cpp ref] [output dir]
# Prerequisite: run scripts/build-llama-vulkan.sh once (it fetches MoltenVK,
# Vulkan-Headers, shaderc/glslc and SPIRV-Headers).
set -euo pipefail

LLAMA_REF="${1:-master}"
OUT="${2:-$PWD/dist}"
SRC="${SRC:-$HOME/src}"
VK="$SRC/vk"
PREFIX_VK="$HOME/.local/vulkan"
MVK="$VK/mvk/MoltenVK/MoltenVK/dynamic/dylib/macOS"
MOLTENVK_VER="${MOLTENVK_VER:-v1.4.2}"
NAME="llama-vulkan-macos-x64"
JOBS="$(sysctl -n hw.ncpu)"

[ -f "$MVK/libMoltenVK.dylib" ] || { echo "MoltenVK missing: run scripts/build-llama-vulkan.sh first" >&2; exit 1; }

git -C "$SRC/llama.cpp" fetch -q --depth 1 origin "$LLAMA_REF"
git -C "$SRC/llama.cpp" checkout -q FETCH_HEAD
COMMIT="$(git -C "$SRC/llama.cpp" rev-parse --short HEAD)"

cd "$SRC/llama.cpp"
cmake -B build-rel -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DGGML_METAL=OFF -DGGML_VULKAN=ON \
  -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
  -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_PREFIX_PATH="$PREFIX_VK" -DCMAKE_CXX_FLAGS="-I$PREFIX_VK/include" \
  -DVulkan_INCLUDE_DIR="$VK/Vulkan-Headers/include" \
  -DVulkan_LIBRARY="$MVK/libMoltenVK.dylib" \
  -DVulkan_GLSLC_EXECUTABLE="$VK/shaderc/build/glslc/glslc"
cmake --build build-rel -j"$JOBS" --target llama-server llama-bench llama-cli

STAGE="$(mktemp -d)/$NAME"
mkdir -p "$STAGE/bin" "$STAGE/licenses"
cp -a build-rel/bin/llama-server build-rel/bin/llama-bench build-rel/bin/llama-cli \
      build-rel/bin/*.dylib build-rel/bin/*.so "$STAGE/bin/"
cp "$MVK/libMoltenVK.dylib" "$STAGE/bin/"

cd "$STAGE/bin"
for f in *; do
  [ -L "$f" ] && continue
  for r in $(otool -l "$f" | awk '/LC_RPATH/{getline;getline;print $2}'); do
    install_name_tool -delete_rpath "$r" "$f" 2>/dev/null || true
  done
  install_name_tool -add_rpath @loader_path "$f" 2>/dev/null || true
  OLD="$(otool -L "$f" | awk '/MoltenVK/ && !/@rpath/{print $1}')"
  if [ -n "$OLD" ]; then install_name_tool -change "$OLD" @rpath/libMoltenVK.dylib "$f"; fi
done 2>/dev/null   # install_name_tool warns that signatures are invalidated: we re-sign below
for f in *; do [ -L "$f" ] || codesign -f -s - "$f" 2>/dev/null; done

# Sanity checks: no absolute library path, minimum macOS 12
BAD="$(for f in *; do [ -L "$f" ] && continue; otool -L "$f" | tail -n +2 | awk '{print $1}' \
       | grep -vE '^@rpath|^@loader_path|^/usr/lib|^/System' | sed "s#^#$f -> #" || true; done)"
[ -z "$BAD" ] || { echo "absolute dependencies left:"; echo "$BAD"; exit 1; } >&2
otool -l llama-server | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print "minos", $2; exit}'

cp "$SRC/llama.cpp/LICENSE" "$STAGE/licenses/llama.cpp-LICENSE"
curl -fsSL "https://raw.githubusercontent.com/KhronosGroup/MoltenVK/${MOLTENVK_VER}/LICENSE" \
  -o "$STAGE/licenses/MoltenVK-LICENSE"
printf 'llama.cpp %s\nMoltenVK %s\nmacOS >= 12.0, x86_64\nbuilt %s\n' \
  "$COMMIT" "$MOLTENVK_VER" "$(date -u +%Y-%m-%dT%H:%MZ)" > "$STAGE/VERSION"

mkdir -p "$OUT"
cd "$(dirname "$STAGE")"
COPYFILE_DISABLE=1 tar czf "$OUT/$NAME.tar.gz" "$NAME"
(cd "$OUT" && shasum -a 256 "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
cat "$OUT/$NAME.tar.gz.sha256"
echo "OK: $OUT/$NAME.tar.gz (llama.cpp $COMMIT)"
