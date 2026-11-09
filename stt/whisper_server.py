"""Local speech-to-text service (faster-whisper) with an OpenAI-compatible API.

Why a separate process: inside Open WebUI, ctranslate2 (libiomp5) and PyTorch
(libomp) load two OpenMP runtimes into the same process -> SIGSEGV on the first
transcription on macOS (Intel). Isolated here, the conflict disappears.

POST /v1/audio/transcriptions  (multipart: file, model, language?, prompt?)
GET  /health
Listens on 127.0.0.1 only. Models stay in memory after first use.
Optional: lexique.txt (initial prompt / vocabulary) and corrections.tsv
(regex post-corrections) next to this file.
"""
import os
import re
import tempfile
import threading
import time

import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from faster_whisper import WhisperModel

MODEL_DIR = os.environ.get(
    "WHISPER_MODEL_DIR",
    os.path.expanduser("~/.local/share/open-webui/cache/whisper/models"),
)
DEFAULT_MODEL = os.environ.get("WHISPER_DEFAULT_MODEL", "large-v3-turbo")
ALLOWED = {"small", "medium", "large-v3", "large-v3-turbo"}
THREADS = int(os.environ.get("WHISPER_THREADS", "8"))

HERE = os.path.dirname(os.path.abspath(__file__))


def _load_prompt() -> str | None:
    """Domain vocabulary passed to Whisper (initial_prompt) to steer spelling."""
    path = os.environ.get("WHISPER_PROMPT_FILE", os.path.join(HERE, "lexique.txt"))
    try:
        return open(path, encoding="utf-8").read().strip() or None
    except OSError:
        return None


def _load_corrections() -> list[tuple[re.Pattern, str]]:
    """Deterministic post-transcription corrections (regex<TAB>replacement)."""
    path = os.environ.get("WHISPER_CORRECTIONS_FILE", os.path.join(HERE, "corrections.tsv"))
    rules = []
    try:
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#") or "\t" not in line:
                continue
            pat, repl = line.split("\t", 1)
            rules.append((re.compile(pat, re.IGNORECASE), repl))
    except OSError:
        pass
    return rules


PROMPT = _load_prompt()
CORRECTIONS = _load_corrections()


def correct(text: str) -> str:
    for pat, repl in CORRECTIONS:
        text = pat.sub(repl, text)
    return text


app = FastAPI(title="whisper-local")
_models: dict[str, WhisperModel] = {}
_lock = threading.Lock()


def get_model(name: str) -> WhisperModel:
    if name not in ALLOWED:
        name = DEFAULT_MODEL
    with _lock:
        if name not in _models:
            _models[name] = WhisperModel(
                name, device="cpu", compute_type="int8",
                cpu_threads=THREADS, download_root=MODEL_DIR,
            )
        return _models[name]


@app.get("/health")
def health():
    return {"status": "ok", "loaded": sorted(_models),
            "prompt": bool(PROMPT), "corrections": len(CORRECTIONS)}


@app.post("/v1/audio/transcriptions")
async def transcriptions(
    file: UploadFile = File(...),
    model: str = Form(DEFAULT_MODEL),
    language: str | None = Form("fr"),
    prompt: str | None = Form(None),
):
    data = await file.read()
    if not data:
        raise HTTPException(400, "empty audio file")
    suffix = os.path.splitext(file.filename or "")[1] or ".webm"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=True) as tmp:
        tmp.write(data)
        tmp.flush()
        m = get_model(model)
        t0 = time.time()
        segments, info = m.transcribe(
            tmp.name, language=language or None, initial_prompt=prompt or PROMPT,
            beam_size=5, vad_filter=True,
        )
        raw = " ".join(s.text.strip() for s in segments).strip()
        text = correct(raw)
    return {
        "text": text,
        "raw_text": raw,
        "language": info.language,
        "duration": round(info.duration, 2),
        "processing_s": round(time.time() - t0, 2),
        "model": model if model in ALLOWED else DEFAULT_MODEL,
    }


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=int(os.environ.get("PORT", "8092")),
                log_level="warning")
