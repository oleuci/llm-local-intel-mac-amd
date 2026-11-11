#!/usr/bin/env bash
# Check the services and time a short answer on the GPU.
set -u
ok(){ printf '  %-28s %s\n' "$1" "$2"; }
echo "Services:"
ok "Ollama (11434)"        "$(curl -s -m3 127.0.0.1:11434/api/version || echo KO)"
ok "llama.cpp GPU (8080)"  "$(curl -s -m3 127.0.0.1:8080/health || echo KO)"
ok "  router models"       "$(curl -s -m3 127.0.0.1:8080/v1/models | python3 -c 'import json,sys;print(" ".join(m["id"]+"("+str(m.get("status",{}).get("value","?"))+")" for m in json.load(sys.stdin)["data"]))' 2>/dev/null || echo KO)"
ok "Open WebUI (3000)"     "$(curl -s -m3 127.0.0.1:3000/health || echo KO) $(curl -s -m3 127.0.0.1:3000/api/version || true)"
ok "Docker container"      "$(PATH=$HOME/.local/bin:$PATH docker ps --filter name=open-webui --format '{{.Status}}' 2>/dev/null || echo KO)"
ok "Whisper STT (8092)"    "$(curl -s -m3 127.0.0.1:8092/health || echo KO)"
echo "Listening sockets (must be 127.0.0.1 only):"
lsof -nP -iTCP -sTCP:LISTEN | awk '/:(3000|8080|8092|11434) /{print "  "$1, $9}'
echo "GPU test:"
curl -s -m90 127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.5-9b-gpu","messages":[{"role":"user","content":"Say hello in one sentence."}],"max_tokens":60}' |
python3 -c 'import json,sys
d=json.load(sys.stdin);t=d["timings"]
print("  ",d["choices"][0]["message"]["content"].strip())
print("   %.1f tok/s, %.1f s" % (t["predicted_per_second"],(t["prompt_ms"]+t["predicted_ms"])/1000))'
