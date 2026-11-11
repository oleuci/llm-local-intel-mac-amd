#!/usr/bin/env bash
# Build stable-diffusion.cpp with the Vulkan backend (MoltenVK) and install sd-server / sd-cli into
# ~/.local/share/sd-vk. Reuses the Vulkan toolchain built by scripts/build-llama-vulkan.sh (run it first,
# or at least its MoltenVK / Vulkan-Headers / shaderc / SPIRV-Headers steps).
#   extras/image-generation/build-sd-vulkan.sh [git-ref]      (default: master)
set -euo pipefail
REF="${1:-master}"
SRC="${SRC:-$HOME/src}"; VK="$SRC/vk"; PREFIX_VK="$HOME/.local/vulkan"; DEST="$HOME/.local/share/sd-vk"
MVK="$VK/mvk/MoltenVK/MoltenVK/dynamic/dylib/macOS"
for f in "$MVK/libMoltenVK.dylib" "$VK/shaderc/build/glslc/glslc" "$VK/Vulkan-Headers/include"; do
  [ -e "$f" ] || { echo "missing $f: run scripts/build-llama-vulkan.sh first" >&2; exit 1; }
done
if [ -d "$SRC/stable-diffusion.cpp/.git" ]; then
  git -C "$SRC/stable-diffusion.cpp" fetch -q --depth 1 origin "$REF" && git -C "$SRC/stable-diffusion.cpp" checkout -q FETCH_HEAD
  git -C "$SRC/stable-diffusion.cpp" submodule update -q --init --recursive --depth 1
else
  git clone -q --depth 1 -b "$REF" --recurse-submodules --shallow-submodules https://github.com/leejet/stable-diffusion.cpp "$SRC/stable-diffusion.cpp"
fi
cd "$SRC/stable-diffusion.cpp"
cmake -B build-vk -DCMAKE_BUILD_TYPE=Release -DSD_VULKAN=ON -DGGML_METAL=OFF \
  -DCMAKE_PREFIX_PATH="$PREFIX_VK" -DCMAKE_CXX_FLAGS="-I$PREFIX_VK/include" \
  -DVulkan_INCLUDE_DIR="$VK/Vulkan-Headers/include" -DVulkan_LIBRARY="$MVK/libMoltenVK.dylib" \
  -DVulkan_GLSLC_EXECUTABLE="$VK/shaderc/build/glslc/glslc"
cmake --build build-vk -j"$(sysctl -n hw.ncpu)"          # ~2-3 min on an i7-10700K
mkdir -p "$DEST"
cp build-vk/bin/sd-server build-vk/bin/sd-cli "$MVK/libMoltenVK.dylib" "$DEST/"
cd "$DEST"
for f in sd-server sd-cli; do install_name_tool -add_rpath @executable_path "$f" 2>/dev/null || true; done
codesign -f -s - sd-server sd-cli libMoltenVK.dylib 2>/dev/null
./sd-cli --help >/dev/null && echo "OK: $DEST/sd-server"
