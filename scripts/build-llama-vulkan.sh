#!/usr/bin/env bash
# Build llama.cpp with the Vulkan backend on top of MoltenVK, for an Intel Mac
# with an AMD GPU — without Xcode and without Homebrew — then install it into
# ~/.local/share/llama-vk.
#
# Usage: scripts/build-llama-vulkan.sh [llama.cpp ref]   (default: master)
# Prerequisites: Command Line Tools (clang, git), cmake, python3, curl.
set -euo pipefail

LLAMA_REF="${1:-master}"
MOLTENVK_VER="${MOLTENVK_VER:-v1.4.2}"
SRC="${SRC:-$HOME/src}"
VK="$SRC/vk"
PREFIX_VK="$HOME/.local/vulkan"          # SPIRV-Headers are installed here
DEST="$HOME/.local/share/llama-vk/bin"  # final binaries (same layout as the release package)
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$VK" "$DEST"

# 1. MoltenVK (official KhronosGroup binary) — Vulkan implemented on top of Metal
if [ ! -f "$VK/mvk/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" ]; then
  curl -fsSL -o "$VK/mvk.tar" \
    "https://github.com/KhronosGroup/MoltenVK/releases/download/${MOLTENVK_VER}/MoltenVK-macos.tar"
  mkdir -p "$VK/mvk" && tar xf "$VK/mvk.tar" -C "$VK/mvk" && rm "$VK/mvk.tar"
fi
MVK="$VK/mvk/MoltenVK/MoltenVK/dynamic/dylib/macOS"

# 2. Vulkan-Headers (C headers + vulkan.hpp)
[ -d "$VK/Vulkan-Headers" ] || git clone --depth 1 -q https://github.com/KhronosGroup/Vulkan-Headers "$VK/Vulkan-Headers"

# 3. shaderc → glslc (shader compiler needed to build ggml-vulkan)
if [ ! -x "$VK/shaderc/build/glslc/glslc" ]; then
  [ -d "$VK/shaderc" ] || git clone --depth 1 -q https://github.com/google/shaderc "$VK/shaderc"
  (cd "$VK/shaderc" && ./utils/git-sync-deps)
  cmake -S "$VK/shaderc" -B "$VK/shaderc/build" -DCMAKE_BUILD_TYPE=Release \
    -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON -DSPIRV_SKIP_TESTS=ON -DENABLE_GLSLANG_BINARIES=OFF
  cmake --build "$VK/shaderc/build" -j"$JOBS" --target glslc_exe
fi

# 4. SPIRV-Headers (find_package(SPIRV-Headers CONFIG) + spirv/unified1/spirv.hpp)
cmake -S "$VK/shaderc/third_party/spirv-headers" -B "$VK/shaderc/third_party/spirv-headers/build" \
  -DCMAKE_INSTALL_PREFIX="$PREFIX_VK" -DSPIRV_HEADERS_ENABLE_TESTS=OFF >/dev/null
cmake --install "$VK/shaderc/third_party/spirv-headers/build" >/dev/null

# 5. llama.cpp with Vulkan (Metal disabled: it hits GPU timeouts on Radeon)
if [ -d "$SRC/llama.cpp/.git" ]; then
  git -C "$SRC/llama.cpp" fetch -q --depth 1 origin "$LLAMA_REF"
  git -C "$SRC/llama.cpp" checkout -q FETCH_HEAD
else
  git clone --depth 1 -q -b "$LLAMA_REF" https://github.com/ggml-org/llama.cpp "$SRC/llama.cpp"
fi
cd "$SRC/llama.cpp"
cmake -B build-vk -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=OFF -DGGML_VULKAN=ON -DLLAMA_CURL=OFF \
  -DCMAKE_PREFIX_PATH="$PREFIX_VK" -DCMAKE_CXX_FLAGS="-I$PREFIX_VK/include" \
  -DVulkan_INCLUDE_DIR="$VK/Vulkan-Headers/include" \
  -DVulkan_LIBRARY="$MVK/libMoltenVK.dylib" \
  -DVulkan_GLSLC_EXECUTABLE="$VK/shaderc/build/glslc/glslc"
cmake --build build-vk -j"$JOBS" --target llama-server llama-bench llama-cli

# 6. Relocatable install: libs + MoltenVK next to the binaries, rpath @executable_path
cp -a build-vk/bin/. "$DEST/"
cp "$MVK/libMoltenVK.dylib" "$DEST/"
cd "$DEST"
for f in llama-server llama-bench llama-cli; do
  install_name_tool -add_rpath @executable_path "$f" 2>/dev/null || true
  install_name_tool -delete_rpath "$SRC/llama.cpp/build-vk/bin" "$f" 2>/dev/null || true
done
OLD="$(otool -L libggml-vulkan.0.dylib | awk '/MoltenVK/{print $1}')"
[ "$OLD" = "@rpath/libMoltenVK.dylib" ] || install_name_tool -change "$OLD" @rpath/libMoltenVK.dylib libggml-vulkan.0.dylib
for f in *.dylib llama-server llama-bench llama-cli; do codesign -f -s - "$f" 2>/dev/null; done

"$DEST/llama-server" --version
echo "OK — restart the service: launchctl kickstart -k gui/\$(id -u)/com.llamacpp.vulkan"
