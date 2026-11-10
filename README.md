# Local LLM on an Intel Mac with an AMD GPU (llama.cpp · Vulkan · MoltenVK)

🇫🇷 [Version française](README.fr.md)

Run a **fully local** generative-AI stack (LLM, chat UI, speech-to-text) on an **Intel Mac with an AMD Radeon GPU**, actually using the GPU, with no data leaving the machine and nothing listening outside `127.0.0.1`.

Ollama, LM Studio and most "one-click" tools **ignore AMD GPUs on Intel Macs**: they only use the CPU. This repo gives you a working path, **llama.cpp's Vulkan backend running on top of MoltenVK**. It comes as:
- a **prebuilt, relocatable package** with a one-line installer;
- **scripts to build everything yourself**, without Xcode or Homebrew.

> **Status:** field-tested on one machine (below). Everything here is measured, not assumed. Your mileage will vary with other GPUs. Issues and reports are welcome.

---

## Contents

1. [Results](#results)
2. [Quick install](#quick-install)
3. [What did *not* work](#what-did-not-work-so-you-dont-have-to-try)
4. [Architecture](#architecture)
5. [The prebuilt package](#the-prebuilt-package)
6. [Build it yourself](#build-it-yourself)
7. [Tuning (measured)](#tuning-measured)
8. [Choosing a model / sizing VRAM](#choosing-a-model--sizing-vram)
9. [Using the API](#using-the-api)
10. [Open WebUI: why Docker on an Intel Mac](#open-webui-why-docker-on-an-intel-mac)
11. [Open WebUI setup](#open-webui-setup)
12. [Speech-to-text (dictation)](#speech-to-text-dictation)
13. [Troubleshooting](#troubleshooting)
14. [Lessons learned](#lessons-learned)
15. [Uninstall](#uninstall) · [License](#license)

---

## Results

Test machine: **iMac 27" (2020)**, macOS 26.6, Intel Core i7-10700K (8C/16T, AVX2), 128 GB DDR4-2667, **AMD Radeon Pro 5700 XT, 16 GB GDDR6**.

Measured with `llama-bench` on Qwen 3.5 9B, Q4_K_M (5.2 GB):

| Backend | Prompt processing (pp512) | Generation (tg128) |
|---|---:|---:|
| **Vulkan / MoltenVK, Radeon Pro 5700 XT** | **~270-286 tok/s** | **~30-35 tok/s** |
| CPU only, 8 threads (AVX2) | 28 tok/s | 4.7 tok/s |

In real chat use through the server, generation runs at **~26-30 tok/s**: `llama-bench` is a best case, with no chat template, no sampling and an empty context. A short chat answer comes back in about **1-1.5 s**. Image description (vision projector loaded) takes about **5 s**.

## Quick install

Requirements: an Intel Mac with macOS **12 or later**, a Metal-capable AMD GPU, and about **10 GB** of free disk space. No sudo is needed.

**Tested GPU:** only the Radeon Pro 5700 XT (Navi 10, 16 GB). Other AMD GPUs supported by MoltenVK (Polaris RX 5xx, Vega, other Navi cards) *should* work, but they are **untested**. VRAM limits the model size: 8 GB cards should use smaller models (≤ 4-7B). Reports are welcome.

```bash
# LLM server only (llama.cpp Vulkan + Qwen 3.5 9B + vision), as a background service
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash

# Full stack: + Open WebUI (official Docker image, chat UI on http://localhost:3000) + dictation
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash -s -- --full
```

`--full` requires **macOS 13 or later**: Open WebUI runs in a VM based on Apple's Virtualization.framework.

What the installer does, step by step (read [`install.sh`](install.sh) before running it):
1. It checks that the Mac runs macOS ≥ 12, is x86_64, and has an AMD GPU and enough free disk space.
2. It downloads the **prebuilt llama.cpp Vulkan package** from this repo's GitHub Releases, **verifies its SHA-256**, and installs it into `~/.local/share/llama-vk/`.
3. It runs `llama-server --list-devices` to confirm the GPU is visible through Vulkan.
4. It downloads **Qwen 3.5 9B Q4_K_M** and its **vision projector** from Hugging Face (`unsloth/Qwen3.5-9B-GGUF`, about 6.5 GB) into `~/models/`.
5. With `--full`, it also installs:
   - the **Whisper dictation environment**, a dedicated Python venv created with [uv](https://docs.astral.sh/uv/). If uv is missing, it runs Astral's official uv installer. The Whisper model (~1.5 GB) is downloaded on first use;
   - a **Docker runtime without Docker Desktop**: Colima, Lima and the Docker CLI, all official binaries. The Colima and Lima checksums are verified; no sudo, no license to accept.
6. It installs **LaunchAgents** (services that start at login and restart if they crash).
7. With `--full`, it starts **Open WebUI from the official Docker image** on `127.0.0.1:3000`. The image is ~6.5 GB on first run. See [why Docker](#open-webui-why-docker-on-an-intel-mac).
8. It runs a health check.

Options: `--full`, `--no-model`, `--no-service`.

## What did *not* work (so you don't have to try)

| Approach | Result | Why |
|---|---|---|
| Ollama on an Intel Mac | CPU only (`inference compute … library=cpu`) | the x86_64 build ships only CPU backends; Metal/MLX are in the arm64 slice only |
| llama.cpp **Metal** backend on the Radeon | `kIOAccelCommandBufferCallbackErrorTimeout`, then the backend enters an error state | its Metal kernels target Apple-GPU features (simdgroup matrix ops) |
| Homebrew for Vulkan (`vulkan-loader`, `shaderc`, `glslang`, …) | builds everything from source, Python included (hours) | no x86_64 bottles for recent macOS |
| **llama.cpp Vulkan + MoltenVK** | ✅ **works, 6-10× faster than CPU** | MoltenVK translates Vulkan to Metal; the generic Vulkan kernels run fine on AMD |
| Open WebUI ≥ 0.8 installed natively (pip/uv) | uv silently falls back to **0.7.2** | pinned `onnxruntime` ≥ 1.24 has no macOS x86_64 wheel |
| …forcing older deps (onnxruntime 1.23.2, transformers 4.x, NumPy 1.26) | starts, but untested combination | transformers 5 needs PyTorch ≥ 2.4, and PyTorch stops at 2.2.2 on Intel Macs |
| **Open WebUI in its official Docker image** (Linux x86_64) | ✅ exact upstream dependencies, same LLM speed | see [below](#open-webui-why-docker-on-an-intel-mac) |

## Architecture

```
Browser ──► Open WebUI         127.0.0.1:3000   (optional, --full: official Docker image in a Colima VM)
               │   via host.docker.internal → relayed by Lima to the Mac's 127.0.0.1
               ├─► llama-server 127.0.0.1:8080  ── Vulkan ─► MoltenVK ─► Metal ─► Radeon   (native)
               │      OpenAI-compatible API /v1, text + vision, one request at a time
               ├─► Whisper STT  127.0.0.1:8092  (optional, native, CPU, dictation)
               └─► Ollama       127.0.0.1:11434 (optional, CPU, model management)
```

| LaunchAgent | Program | Logs |
|---|---|---|
| `com.llamacpp.vulkan` | `~/.local/share/llama-vk/bin/llama-server` | `~/Library/Logs/llama-vk/` |
| `com.whisper.stt` | `stt/whisper_server.py`, run with `~/.local/share/whisper-stt/venv` | `~/Library/Logs/whisper-stt/` |
| `com.colima.start` | `~/.local/bin/colima start`: boots the Docker VM at login; the `open-webui` container then restarts by itself (`--restart unless-stopped`) | `~/Library/Logs/colima/` |
| `com.ollama.serve` | `~/.local/share/ollama-bin/ollama` (optional) | `~/Library/Logs/ollama/` |

`scripts/install-services.sh` installs only the services whose program is present. Service definitions are templates in [`launchd/`](launchd/), with `__HOME__` and `__REPO__` placeholders.

## The prebuilt package

`llama-vulkan-macos-x64.tar.gz` (~33 MB) is built by [`scripts/package-release.sh`](scripts/package-release.sh). Anyone can rebuild it from the same commit and compare.

| Property | How | Why |
|---|---|---|
| Runs on **macOS 12+** | `CMAKE_OSX_DEPLOYMENT_TARGET=12.0` | a default local build targets the build host's macOS (26 here) and refuses to start on older systems |
| **No Homebrew dependency** | `LLAMA_OPENSSL=OFF`, `LLAMA_CURL=OFF` | a default build silently links `/usr/local/opt/openssl@*` |
| **One package for all Intel CPUs** | `GGML_NATIVE=OFF`, `GGML_BACKEND_DL=ON`, `GGML_CPU_ALL_VARIANTS=ON` | the CPU backend (Sandy Bridge → Ice Lake, Zen 4…) is chosen at runtime |
| **Relocatable** | every rpath is rewritten to `@loader_path`, and MoltenVK is linked as `@rpath/libMoltenVK.dylib` | works from any directory, including paths with spaces |
| MoltenVK bundled | official KhronosGroup `MoltenVK-macos.tar` v1.4.2 (Apache-2.0) | no Vulkan SDK needed |
| Ad-hoc code signature | `codesign -s -` | see the Gatekeeper note below |

Verified before release: only system or `@rpath` dependencies (`otool -L`), `minos 12.0`, GPU detected and same speed when run from a fresh directory with an empty environment (`env -i`).

**Gatekeeper.** The binaries are not notarized (that requires a paid Apple Developer ID).
- `curl` (used by the installer) does not set the quarantine attribute, so nothing is blocked.
- If you download the tarball **with a browser**, macOS will reject it. Clear the attribute first:

```bash
xattr -dr com.apple.quarantine llama-vulkan-macos-x64/
```

## Build it yourself

Prerequisites: the Command Line Tools (`xcode-select --install`), `cmake`, `git`, `python3` and `curl`. Xcode itself is **not** needed.

```bash
scripts/build-llama-vulkan.sh            # local build, installs into ~/.local/share/llama-vk/bin
scripts/package-release.sh <ref> dist/   # redistributable package (macOS 12+, relocatable)
```

What the build script assembles, in order:
1. **MoltenVK**: the official binary from KhronosGroup releases. It provides Vulkan on top of Metal.
2. **Vulkan-Headers**: the C headers and `vulkan.hpp`.
3. **shaderc → `glslc`**: compiled from source in ~5 min. ggml-vulkan compiles its shaders at build time.
4. **SPIRV-Headers**: installed to `~/.local/vulkan`. They provide `find_package(SPIRV-Headers CONFIG)` and `spirv/unified1/spirv.hpp`.
5. **llama.cpp**, configured with:

```
cmake -B build-vk -DGGML_METAL=OFF -DGGML_VULKAN=ON -DLLAMA_CURL=OFF \
  -DCMAKE_PREFIX_PATH=~/.local/vulkan -DCMAKE_CXX_FLAGS="-I$HOME/.local/vulkan/include" \
  -DVulkan_INCLUDE_DIR=…/Vulkan-Headers/include \
  -DVulkan_LIBRARY=…/libMoltenVK.dylib \          # link MoltenVK directly, no Vulkan loader needed
  -DVulkan_GLSLC_EXECUTABLE=…/shaderc/build/glslc/glslc
```

Build errors you may hit, and their fixes (both are already handled in the script):

| Error | Fix |
|---|---|
| `Could not find a package configuration file provided by "SPIRV-Headers"` | install SPIRV-Headers and add its prefix to `CMAKE_PREFIX_PATH` |
| `'spirv/unified1/spirv.hpp' file not found` | add `-I<prefix>/include` to `CMAKE_CXX_FLAGS` |

## Tuning (measured)

The service flags, in [`launchd/com.llamacpp.vulkan.plist`](launchd/com.llamacpp.vulkan.plist):

```
-ngl 99 -t 2 -tb 2 --poll 0 -c 32768 --parallel 1 -fa on --jinja
--chat-template-kwargs '{"enable_thinking":false}'
--alias qwen3.5-9b-gpu --mmproj <vision projector> --host 127.0.0.1 --port 8080
```

Keep the alias **free of spaces**: Open WebUI ≥ 0.13 rejects model IDs with spaces when you create or override a model.

### 1. CPU at ~670 % while the model is 100 % on the GPU

The log confirms the model is fully on the GPU (`offloaded 33/33 layers to GPU`). Only `token_embd` (~545 MB) stays in RAM: it is a lookup table, which is normal. Yet the CPU sat at about 670 %, because llama.cpp's worker threads **busy-wait** for the GPU (`--poll 50` by default).

| Flags | pp512 | tg128 | CPU time for the run |
|---|---:|---:|---:|
| `-t 8 --poll 50` (default) | 251 tok/s | 23.5 tok/s | 43 s |
| `-t 8 --poll 0` | 272 tok/s | 30.2 tok/s | 6 s |
| **`-t 2 --poll 0`** | **273 tok/s** | **34.7 tok/s** | **5.6 s** |

After the fix, the CPU stays at ~50 % during generation, the Mac runs cooler, and generation is **faster**.

### 2. Thinking models (Qwen 3.5): control them per request

- **Don't** use `--reasoning-budget 0`. It disables thinking server-wide, and requests can no longer turn it back on (tested).
- **Do** turn it off by default with `--chat-template-kwargs '{"enable_thinking":false}'`, then enable it per request:

```json
{ "chat_template_kwargs": {"enable_thinking": true},
  "reasoning_budget_tokens": 1024,
  "reasoning_budget_message": "\n\nI must now conclude and give my final answer.\n" }
```

Uncapped, Qwen 3.5 writes 1,300 to more than 3,300 thinking tokens (2-4 min) even on simple questions. Capped, on 4 logic questions with known answers:

| Thinking cap | Correct | Avg time / question |
|---|---:|---:|
| 512 | 3/4 | ~32 s |
| **1024** | **4/4** | **~53 s** |
| 2048 | 4/4 | ~110 s |
| none | — | > 2 min |

The model almost always uses its full budget, so the cap effectively sets the latency.

### 3. One request at a time: `--parallel 1`

By default llama-server opens 4 parallel slots **and splits the context between them**: `-c 32768` gives each conversation only 8,192 tokens.

On this GPU, concurrent requests collapse. Measured with Open WebUI 0.13, whose background tasks (title, tags, follow-ups) run **at the same time** as your answer:
- **13 tok/s** prompt processing, instead of ~270;
- **0.3 tok/s** generation, so a simple question took about a minute.

With `--parallel 1`:
- requests queue instead: two simultaneous requests each ran at **29.5 tok/s**, the second one simply waiting for the first;
- each conversation gets the **full 32k context**.

### 4. Open WebUI ≥ 0.12 "builtin tools": turn them off

Open WebUI now enables **builtin tools by default on every model**: web search, memory, notes, knowledge, skills… Their descriptions are injected into **every request**.

Measured: an 8-token question was sent with a **~7,900-token context**, i.e. **40-45 s of prompt processing** on this GPU before the first word. With the tools off, the same question was sent with **639 tokens** and answered in **~1.5 s**.
- Per model: Workspace → Models → Capabilities → untick **Builtin Tools**.
- Globally: set the environment variable `DEFAULT_MODEL_METADATA='{"capabilities":{"builtin_tools":false}}'`. [`scripts/owui-docker.sh`](scripts/owui-docker.sh) does this; per-model settings still win.

### 5. Thermal

Long thinking keeps the Radeon at 100 % for minutes, and the fans spin up loudly. They settle down 1-2 min after the last request.

## Choosing a model / sizing VRAM

**Generation speed ≈ effective memory bandwidth ÷ bytes of active weights read per token.**

- Theoretical VRAM bandwidth of the Pro 5700 XT: ~384-448 GB/s depending on the source. Measured effective bandwidth through MoltenVK: **~180 GB/s** (5.2 GB × 34.7 tok/s). The translation layer costs about half.
- System RAM: DDR4-2667, dual channel, ~43 GB/s theoretical, **~30 GB/s usable**, about 6× slower.

| Model class | Fits in 16 GB VRAM? | Expected generation |
|---|---|---|
| Dense ≤ 9B (Q4 ≈ 5-6 GB) | ✅ with a large context | ~30-35 tok/s (measured for Qwen 3.5 9B) |
| Dense 12-14B (Q4 ≈ 7-9 GB) | ✅, context gets tighter | ~20 tok/s (estimated) |
| Dense ≥ 27B | ❌ partial offload | slow |
| Large MoE (100B+, ~5-6B active) with experts in RAM (`--n-cpu-moe`) | weights in RAM | **~5-8 tok/s (estimated)**: batch jobs only |

**KV cache matters as much as the weights:**
- **Qwen 3.5 is hybrid**: only 1 layer in 4 uses full attention (the others show `filtered` in the log). A 32k context is therefore cheap, and the prompt cache is reused across turns.
- **Gemma** models use sliding-window attention. The default compact SWA cache fits, but llama.cpp then re-processes the whole history on every turn (`forcing full prompt re-processing due to SWA`). `--swa-full` avoids that, but costs far more VRAM. Gemma suits short exchanges better than long chats on 16 GB.

## Using the API

The server is OpenAI-compatible:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "messages": [{"role": "user", "content": "Explain MoltenVK in one sentence."}],
  "max_tokens": 200 }'
```

The response includes `timings` (`prompt_per_second`, `predicted_per_second`). Other useful endpoints:
- `GET /health`;
- `GET /slots`: what is running right now;
- `GET /v1/models`.

For vision, send `content` as a list containing `{"type":"image_url","image_url":{"url":"data:image/png;base64,…"}}`.

## Open WebUI: why Docker on an Intel Mac

Since 0.8, a native Open WebUI install no longer works properly on Intel Macs:
- its pinned `onnxruntime` (≥ 1.24) has **no macOS x86_64 wheel**, so `uv`/`pip` silently fall back to **0.7.2** (January 2026);
- forcing older dependencies gets 0.13 to start, but `transformers` 5 needs **PyTorch ≥ 2.4**, which **stops at 2.2.2 on Intel Macs**;
- PyTorch 2.2.2 was built against **NumPy 1.x**, so with NumPy 2 the embeddings fail (`RuntimeError: Numpy is not available`). **Even in 0.7.2, document embeddings (RAG) are broken.**

The **official Docker image** runs Linux x86_64, where every dependency exists: PyTorch 2.9, NumPy 2.5, onnxruntime 1.26, transformers 5.5. Measured on this machine:

| | Native 0.7.2 | **Docker 0.13.3** |
|---|---|---|
| LLM generation (the container calls the native llama-server) | 26.3-26.5 tok/s | **26.1-26.5 tok/s** (network overhead ~0.02 s) |
| Embeddings, 512 passages | broken (NumPy 2 vs PyTorch 2.2) | **1.40 s** (CPU, VM) |
| Container at idle | — | 0.4 % CPU, ~1 GB RAM |

**Networking.** From the container, `host.docker.internal` (192.168.5.2) reaches the Mac's **127.0.0.1**: Lima relays it. llama-server, Whisper and Ollama therefore stay loopback-only. In Open WebUI, use `http://host.docker.internal:8080/v1` for the LLM and `http://host.docker.internal:8092/v1` for dictation, never `127.0.0.1`, which inside a container is the container itself.

**Run / update:**
```bash
scripts/owui-docker.sh            # create the container (127.0.0.1:3000, data in ~/.local/share/open-webui-docker)
scripts/owui-docker.sh v0.13.4    # update: new image, same data
```

**Migrating from a native install**: copy `webui.db` with SQLite's backup API (consistent even while running), plus the `uploads/` and `vector_db/` folders, into the Docker data folder. Fix the dictation URL to `host.docker.internal`, then reuse the same `WEBUI_SECRET_KEY`. A 0.7.2 → 0.13.3 migration applied 43 schema migrations without errors; models, prompts, settings and chats were all kept.

## Open WebUI setup

`--full` connects llama-server automatically: `OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1`. It also turns builtin tools off by default.

Then configure, in this order:
1. **Two models on the same base**, in Workspace → Models → New:
   - **"fast"**: Advanced params → custom parameter `chat_template_kwargs` = `{"enable_thinking": false}`;
   - **"thinking"**: `chat_template_kwargs` = `{"enable_thinking": true}`, `reasoning_budget_tokens` = `1024`, `reasoning_budget_message` = `"\n\nI must now conclude…\n"`.
2. **Task model**: Admin → Settings → Interface → Task model = **"fast"**. Otherwise every title, tag and follow-up generation also starts a long thinking draft, in parallel with your answer.
3. **Default model** = "fast". Admin → Settings → Models.
4. Optional: a **system prompt with a domain glossary**. See [Lessons learned](#lessons-learned) and [`open-webui/system-prompt-sante-fr.md`](open-webui/system-prompt-sante-fr.md).

## Speech-to-text (dictation)

**Open WebUI's built-in Whisper crashes the whole process (SIGSEGV) on the first transcription on Intel macOS.**
- The macOS crash report shows `libiomp5.dylib __kmp_suspend_64` in the faulting thread.
- `ctranslate2` (faster-whisper) loads Intel's `libiomp5`, and PyTorch loads LLVM's `libomp`. Two OpenMP runtimes in one process crash.

The fix: [`stt/whisper_server.py`](stt/whisper_server.py) runs faster-whisper in **its own process**, without PyTorch, with an OpenAI-compatible `POST /v1/audio/transcriptions` endpoint on `127.0.0.1:8092`. It runs natively in a dedicated venv: [`scripts/setup-stt.sh`](scripts/setup-stt.sh), at `~/.local/share/whisper-stt/venv`.

To connect it to Open WebUI: Admin → Settings → Audio → STT engine **OpenAI**, base URL `http://host.docker.internal:8092/v1` (Docker; use `http://127.0.0.1:8092/v1` for a native Open WebUI), any API key, model `large-v3-turbo`.

Results on real dictation (French, with domain acronyms, on the CPU so the GPU stays free for the LLM):

| | `small` | **`large-v3-turbo`** |
|---|---|---|
| Time for 12-19 s of audio | ~2.3 s | ~6 s |
| Errors | "pourgogne froche comptée" for "Bourgogne-Franche-Comté", "cas d'ordre" for "cadre" | none, except one unknown acronym |

Domain vocabulary is handled by two files next to the server:
- [`stt/lexique.txt`](stt/lexique.txt): passed to Whisper as its `initial_prompt`. It worked on `small`, much less on turbo, whose decoder has only 4 layers.
- [`stt/corrections.tsv`](stt/corrections.tsv): deterministic regex fixes applied after transcription. The response also includes `raw_text`, the transcription before correction, for checking.

Reload after editing either file: `launchctl kickstart -k gui/$(id -u)/com.whisper.stt`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `"llama-server" cannot be opened` / killed at launch | Gatekeeper quarantine (tarball downloaded with a browser) | `xattr -dr com.apple.quarantine ~/.local/share/llama-vk` |
| `--list-devices` shows no `Vulkan0` | MoltenVK not found, or no Metal-capable GPU | `otool -L bin/libggml-vulkan.so` must show `@rpath/libMoltenVK.dylib`; check `system_profiler SPDisplaysDataType` |
| `ggml_vulkan: WARNING: Instance extension VK_KHR_portability_enumeration not found` / `[mvk-warn] … robustness` | MoltenVK informational warnings | harmless |
| `Bootstrap failed: 5: Input/output error` when reinstalling a service | `launchctl bootout` is asynchronous | wait until `launchctl print gui/$UID/<label>` fails, then bootstrap again (`install-services.sh` does this) |
| Empty answer with `max_tokens` small | the thinking draft used up the whole budget | thinking off by default, cap it with `reasoning_budget_tokens` |
| Very slow answers, ~5 tok/s or less | concurrent requests (Open WebUI background tasks) and 4 parallel slots | `--parallel 1`; set Open WebUI's task model to the "fast" model; check `GET /slots` |
| 40 s+ before the first word, even for "hello" (Open WebUI ≥ 0.12) | builtin tools injected into every request (~7,900 tokens) | untick Builtin Tools per model, or `DEFAULT_MODEL_METADATA='{"capabilities":{"builtin_tools":false}}'` |
| Open WebUI ≥ 0.8 won't install natively; uv installs 0.7.2 | no macOS x86_64 wheels for its dependencies | use the official Docker image (`scripts/owui-docker.sh`) |
| `String should match pattern '^\S+$'` when editing a model | model ID with spaces (llama-server `--alias`) | use an alias without spaces, e.g. `qwen3.5-9b-gpu` |
| Open WebUI (Docker) can't reach the LLM or dictation | `127.0.0.1` inside a container is the container itself | use `http://host.docker.internal:<port>` |
| `Response payload is not completed: TransferEncodingError` | llama-server restarted or was killed mid-answer | resend the question; check `~/Library/Logs/llama-vk/` |
| CPU ~700 % during generation | busy-wait polling | `-t 2 -tb 2 --poll 0` |
| Open WebUI restarts when you dictate | OpenMP conflict in its built-in Whisper | use the separate STT service |
| Microphone "denied" in an embedded browser | some embedded webviews block `getUserMedia` | use Safari or Chrome on `http://localhost:3000` (localhost counts as a secure context) |
| `warmup: the mmproj graph uses unsupported operators by the backend` | a few vision ops have no Vulkan kernel | harmless: those ops fall back to the CPU, and images still work (~5 s) |

Logs: `~/Library/Logs/{llama-vk,whisper-stt,colima,ollama}/` and `docker logs open-webui`. Status check: `~/.local/share/llm-local-intel-mac-amd/scripts/healthcheck.sh`.

## Lessons learned

1. **Measure, don't assume.** The default install of every tool missed the actual hardware (CPU only, wrong macOS target, hidden Homebrew dependency, busy-wait threads).
2. **The real bottleneck is memory bandwidth.** Pick a model that fits entirely in VRAM, and size its KV cache too.
3. **Test the speed of a real question through the UI, not just that it works.** The Open WebUI 0.13 upgrade passed every functional test, but each question became ~40 s slower, because of builtin tools and concurrent background tasks.
4. **A small model invents domain facts with confidence.**
   - Given a perfectly transcribed sentence about French health-IT acronyms, a 9B model expanded two of them wrongly and invented a third, non-existent one.
   - A **glossary + "never invent an acronym" rule** in the system prompt fixed it: definitions became correct, and on unknown acronyms the model now **abstains** instead of inventing.
   - For facts beyond acronyms, use retrieval (RAG) over reference documents. Retrieval itself is near-instant; the cost is the extra prompt tokens (~270 tok/s here).

## Uninstall

```bash
~/.local/share/llm-local-intel-mac-amd/uninstall.sh            # services, binaries, Open WebUI container (keeps models, data, Colima VM)
~/.local/share/llm-local-intel-mac-amd/uninstall.sh --purge    # also deletes the Colima VM + Docker tools, Open WebUI data and the default model
```

## License

[MIT](LICENSE) for this repo's scripts and docs. Bundled and third-party components keep their own licenses:
- llama.cpp (MIT) and MoltenVK (Apache-2.0): their license texts are shipped in `licenses/` inside the package;
- Ollama (MIT), Open WebUI (its own license), faster-whisper (MIT);
- the models (Qwen 3.5: Apache-2.0).
