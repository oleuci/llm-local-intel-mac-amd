# Local LLM on an Intel Mac with an AMD GPU (Vulkan / MoltenVK)

🇫🇷 [Version française](README.fr.md)

Run a **fully local** generative AI stack (LLM + chat UI + speech-to-text) on an **Intel Mac with an AMD Radeon GPU**, using the GPU, with no data leaving the machine and nothing listening outside `127.0.0.1`.

Ollama and most "one-click" tools **ignore AMD GPUs on Intel Macs**. They run on the CPU only. This repo documents a working path: **llama.cpp with its Vulkan backend on top of MoltenVK**, built without Xcode or Homebrew.

> Tested on a single machine (see below). It is a field report with scripts, not a supported product. Measure on your own hardware.

## Tested on

| | |
|---|---|
| Machine | iMac 27" (2020), macOS 26 (Tahoe), Intel x86_64 |
| CPU | Intel Core i7-10700K (8C/16T, AVX2) |
| RAM | 128 GB DDR4-2667 |
| GPU | AMD Radeon Pro 5700 XT, 16 GB VRAM |
| Software | llama.cpp (Vulkan), MoltenVK 1.4.2, Ollama 0.40, Open WebUI 0.7, faster-whisper 1.2 |

## Results (Qwen 3.5 9B, Q4_K_M)

| Backend | Prompt processing | Generation |
|---|---:|---:|
| **Vulkan / MoltenVK on the Radeon** | **~270-286 tok/s** | **~31-35 tok/s** |
| CPU only (8 threads) | 28 tok/s | 4.7 tok/s |

A short answer comes back in about **1 s**.

## What did *not* work (so you don't have to try)

| Approach | Result |
|---|---|
| Ollama on an Intel Mac | CPU only: the x86_64 build ships no GPU backend (Metal/MLX are ARM-only) |
| llama.cpp **Metal** backend on the Radeon | `kIOAccelCommandBufferCallbackErrorTimeout`: its Metal kernels target Apple Silicon |
| Homebrew for the Vulkan toolchain | no x86_64 bottles on recent macOS: it compiles everything from source (hours) |
| **llama.cpp Vulkan + MoltenVK** | ✅ works, 6-10× faster than CPU |

## Architecture

```
Browser ──► Open WebUI 127.0.0.1:3000
               ├─► llama-server 127.0.0.1:8080 ─ Vulkan ─► MoltenVK ─► Metal ─► Radeon
               ├─► Ollama       127.0.0.1:11434 (CPU, optional: model management)
               └─► Whisper STT  127.0.0.1:8092  (CPU, dictation)
```

Each service is a user **LaunchAgent** (`launchd/`, `RunAtLoad` + `KeepAlive`).

## Install

```bash
# 1. Build llama.cpp (Vulkan) — ~10-15 min, no Xcode needed (Command Line Tools only)
scripts/build-llama-vulkan.sh

# 2. Ollama (official universal binary), used here to download models
mkdir -p ~/.local/share/ollama-bin && cd ~/.local/share/ollama-bin
curl -fsSL -o o.tgz https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.tgz && tar xzf o.tgz && rm o.tgz
cd -

# 3. Open WebUI (via uv)
uv tool install --python 3.11 open-webui

# 4. A model: pull it with Ollama, then hard-link the GGUF for llama.cpp
#    (or download any GGUF from Hugging Face into ~/models/)
mkdir -p ~/models   # and point -m in launchd/com.llamacpp.vulkan.plist at your file

# 5. Install and start all services
scripts/install-services.sh
scripts/healthcheck.sh
```

Then open `http://localhost:3000`. The first account created becomes the admin.

## Tuning that matters

1. **CPU at ~670 % while the model is 100 % on the GPU.**
   - Cause: llama.cpp's worker threads busy-wait for the GPU (`--poll 50` by default).
   - Fix: `-t 2 -tb 2 --poll 0`. CPU drops to ~50 %, and generation even gets faster (23.5 → 34.7 tok/s in `llama-bench`).
2. **"Thinking" models (Qwen 3.5) write novels.**
   - Don't use `--reasoning-budget 0`: it disables thinking server-wide, with no per-request override.
   - Instead, default it off with `--chat-template-kwargs '{"enable_thinking":false}'`, and turn it on per request with `chat_template_kwargs: {"enable_thinking": true}`.
   - Cap the draft with `reasoning_budget_tokens` (accepted per request). On 4 logic questions with known answers:

   | Thinking cap | Correct | Avg time / question |
   |---|---:|---:|
   | 512 | 3/4 | ~32 s |
   | **1024** | **4/4** | **~53 s** |
   | 2048 | 4/4 | ~110 s |
   | none | — | > 2 min |

   In Open WebUI, create two models on the same base ("fast" / "thinking") with these custom parameters.
3. **Open WebUI background tasks** (titles, tags, follow-ups) use the chat model by default.
   - With thinking on, each of them starts its own long reasoning draft in parallel with your answer, and the GPU is shared.
   - Fix: Admin → Settings → Interface → Task model = your "fast" model.
4. **Memory bandwidth sets the speed, not model size.**
   - Each generated token re-reads the active weights.
   - Measured effective VRAM bandwidth through MoltenVK is ~180 GB/s, about half the theoretical value.
   - System RAM is ~6× slower: large MoE models "fit" in 128 GB RAM, but would run at an estimated 5-8 tok/s. **Pick a model that fits entirely in VRAM.**
5. **Vision**: Qwen 3.5 9B is multimodal. Pass its projector with `--mmproj <file>` (≈0.9 GB VRAM).
   - Some projector ops fall back to the CPU on Vulkan, but it works.

## Speech-to-text (dictation)

Open WebUI's built-in Whisper **crashes the whole process (SIGSEGV) on the first transcription** on macOS Intel.
- Cause: `ctranslate2` loads `libiomp5`, PyTorch loads `libomp`. Two OpenMP runtimes end up in one process.
- Fix: [`stt/whisper_server.py`](stt/whisper_server.py) runs faster-whisper in **its own process**, with an OpenAI-compatible `/v1/audio/transcriptions` endpoint.
- In Open WebUI: Admin → Audio → STT engine "OpenAI", URL `http://127.0.0.1:8092/v1`, model `large-v3-turbo`.

Comparison on real dictation (French, with domain jargon):

| | `small` | `large-v3-turbo` |
|---|---|---|
| Time (12-19 s of audio, CPU) | ~2.3 s | ~6 s |
| Errors | "pourgogne froche comptée" for "Bourgogne-Franche-Comté" | none except one unknown acronym |

Domain acronyms are handled by two files next to the server, both optional and easy to extend:
- `stt/lexique.txt`: vocabulary passed to Whisper as its initial prompt ;
- `stt/corrections.tsv`: regex post-corrections applied after transcription.

**Note:** the Claude desktop app's embedded browser blocks the microphone. Use Safari or Chrome on `http://localhost:3000`.

## Lesson learned: small models invent acronyms

With a perfectly transcribed sentence about French health-IT acronyms, a 9B model confidently "expanded" them wrongly, and even invented a non-existent acronym. Small local models know language well, but niche domain facts poorly.

A **glossary + "never invent" rule in the system prompt** fixed it:
- correct definitions;
- the model **abstains** on unknown acronyms instead of inventing one.

Example for French health IT: [`open-webui/system-prompt-sante-fr.md`](open-webui/system-prompt-sante-fr.md). The next step for factual answers is retrieval (RAG) over reference documents.

## Repository layout

```
scripts/build-llama-vulkan.sh   MoltenVK + shaderc + llama.cpp (Vulkan), relocatable install
scripts/install-services.sh     install/reinstall LaunchAgents (keeps WEBUI_SECRET_KEY)
scripts/healthcheck.sh          service status + GPU test
launchd/*.plist                 LaunchAgent templates (__HOME__, __REPO__, secret placeholder)
stt/                            Whisper STT service + vocabulary + corrections
open-webui/                     example system prompt (glossary)
```

## License

[MIT](LICENSE). Third-party components (llama.cpp, MoltenVK, Ollama, Open WebUI, Whisper, the models) keep their own licenses.
