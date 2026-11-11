# Image generation (optional, tested then uninstalled)

🇫🇷 [Version française](README.fr.md)

> **Status:** tested and measured on the reference iMac (Radeon Pro 5700 XT, 16 GB) in November 2026, integrated into Open WebUI, then **uninstalled by choice**: hosted image services are far better, and this GPU is more useful to the LLM. Everything below is kept so it can be **reinstalled if needed**. Nothing here is installed by `install.sh`.

## What works

**[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)** uses the same ggml base and the same **Vulkan backend over MoltenVK** as llama.cpp, so it runs on the Radeon. It builds in ~2-3 min with the toolchain from `scripts/build-llama-vulkan.sh`:

```bash
scripts/build-llama-vulkan.sh                      # if not done yet: provides MoltenVK, shaderc, headers
extras/image-generation/build-sd-vulkan.sh         # -> ~/.local/share/sd-vk/{sd-server,sd-cli}
```

PyTorch-based tools (ComfyUI, AUTOMATIC1111) are a dead end on Intel Macs, for the same reason as native Open WebUI: PyTorch stops at 2.2.2 there. In Docker, the Colima VM has no GPU access.

## Measured

| Model | Size | 512×512 | 1024×1024 | Quality |
|---|---|---|---|---|
| SDXL-Turbo fp16, 4 steps | 6.9 GB | 28-30 s (17 s sampling + 9 s VAE) | — | correct, but misspells text ("BOUANGERE") |
| SDXL-Turbo + **TAESD** fast decoder | +10 MB | **~19 s** (VAE 9 s → 0.8 s) | — | near-identical |
| **Z-Image-Turbo** Q4_K, 8 steps | 6.4 GB (DiT 3.9 + Qwen3-4B text encoder 2.5 + Flux VAE 0.3) | ~65 s | **~4 min 30** (229 s sampling + 42 s VAE) | **much better**: photographic, correct text in the image, follows the prompt |

768×768 with Z-Image takes ~2 min 20. Generation time grows a little faster than the pixel count.

Findings:
- **The limit is compute, not VRAM.** On MoltenVK, flash attention and direct convolution are unavailable here (`probe output check failed`). The 5700 XT has no matrix cores, so a 512 px step takes ~4.3 s with SDXL.
- **Unloading the LLM does not help** SDXL-Turbo or Z-Image Q4: they fit next to it, and the speed was identical. Reloading the LLM afterwards takes ~3 s.
- **`--offload-to-cpu`** keeps the weights in RAM and moves them to the GPU only during a generation. Measured cost: none (66 s either way). The LLM still ran at 31 tok/s right after an image.
- Generating keeps the GPU busy with long kernels: **the macOS display can stutter during a generation**.

## Reinstall (Z-Image-Turbo + Open WebUI)

```bash
mkdir -p ~/models/sd && cd ~/models/sd
curl -fLO https://huggingface.co/leejet/Z-Image-Turbo-GGUF/resolve/main/z_image_turbo-Q4_K.gguf
curl -fLO https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf
# Flux VAE: black-forest-labs' repo is gated; Comfy-Org redistributes the same file
curl -fL -o flux_ae.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors

sed "s#__HOME__#$HOME#g" ~/.local/share/llm-local-intel-mac-amd/extras/image-generation/com.sdcpp.server.plist \
  > ~/Library/LaunchAgents/com.sdcpp.server.plist
mkdir -p ~/Library/Logs/sd-server && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.sdcpp.server.plist
```

In Open WebUI (Admin → Settings → Images):
- engine **Automatic1111**, URL `http://host.docker.internal:8093`;
- size `1024x1024` (or `512x512` for ~1 min), steps `8`;
- in the Automatic1111 parameters, set `{"cfg_scale": 1.0}`.

Then, in a chat: **+** → **Image** → describe the picture.

Open WebUI pitfalls (0.13):
- **The "Image" toggle does nothing when builtin tools are off.** It only forces generation in **legacy** function-calling mode; in native mode, the model must call the `generate_image` builtin tool. Set the model's *Function calling* to **Legacy** (already the default with this repo's `owui-docker.sh`, for web search), which still keeps the ~7,900 tokens of builtin tools out of every request.
- **No timeout to fear.** Open WebUI sets no client timeout unless `AIOHTTP_CLIENT_TIMEOUT` is defined, so a 4-5 min generation is fine.
- **Never edit `webui.db` from the Mac while the container runs.** SQLite's WAL/shared-memory files don't survive concurrent access across virtiofs, and Open WebUI starts failing with `disk I/O error`. Stop the container, edit, start it again. Better still, use the admin UI.

## Other models

stable-diffusion.cpp also supports **Qwen-Image** (see its `docs/qwen_image.md`), Flux, SD 3.5 and others. Qwen-Image is a much larger model (20B), so on this GPU it would rely on `--offload-to-cpu` and be slow. It is **untested here**.

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.sdcpp.server; rm ~/Library/LaunchAgents/com.sdcpp.server.plist
rm -rf ~/.local/share/sd-vk ~/models/sd ~/Library/Logs/sd-server
```

Then disable image generation in Open WebUI. Keep *Function calling* on **Legacy**: web search needs it too.
