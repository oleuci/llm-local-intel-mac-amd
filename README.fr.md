# LLM local sur Mac Intel avec GPU AMD (llama.cpp · Vulkan · MoltenVK)

🇬🇧 [English version](README.md)

Faire tourner une pile d'IA générative **100 % locale** (modèle de langage, interface de chat, dictée vocale) sur un **Mac Intel équipé d'une Radeon AMD**, en exploitant vraiment le GPU. Aucune donnée ne sort de la machine, et rien n'écoute en dehors de `127.0.0.1`.

Ollama, LM Studio et la plupart des outils « clé en main » **ignorent les GPU AMD sur Mac Intel** : ils n'utilisent que le CPU. Ce dépôt fournit une voie qui fonctionne, **le moteur Vulkan de llama.cpp au-dessus de MoltenVK**. Il se présente sous deux formes :
- un **paquet précompilé et relocalisable**, avec un installeur en une ligne ;
- des **scripts pour tout compiler soi-même**, sans Xcode ni Homebrew.

Trois modèles sont servis derrière une seule adresse compatible OpenAI (**mode routeur** de llama.cpp, un seul modèle sur le GPU à la fois) : **Qwen 3.5 9B** avec la vision et, en option, **Gemma 4 E4B** et **Gemma 4 12B** (versions QAT 4 bits officielles de Google).

> **Statut :** éprouvé sur une seule machine (voir ci-dessous). Tout ce qui est écrit ici a été mesuré, pas supposé. Les résultats varieront avec d'autres GPU. Les retours (issues) sont bienvenus.

---

## Sommaire

1. [Résultats](#résultats)
2. [Installation rapide](#installation-rapide)
3. [Ce qui n'a *pas* marché](#ce-qui-na-pas-marché-inutile-de-réessayer)
4. [Architecture](#architecture)
5. [Le paquet précompilé](#le-paquet-précompilé)
6. [Compiler soi-même](#compiler-soi-même)
7. [Réglages (mesurés)](#réglages-mesurés)
8. [Choisir un modèle / dimensionner la VRAM](#choisir-un-modèle--dimensionner-la-vram)
9. [Utiliser l'API](#utiliser-lapi)
10. [Open WebUI : pourquoi Docker sur Mac Intel](#open-webui--pourquoi-docker-sur-mac-intel)
11. [Configurer Open WebUI](#configurer-open-webui)
12. [Recherche web (SearXNG local)](#recherche-web-searxng-local)
13. [Dictée vocale](#dictée-vocale)
14. [Génération d'images (optionnelle, testée puis désinstallée)](#génération-dimages-optionnelle)
15. [Dépannage](#dépannage)
16. [Enseignements](#enseignements)
17. [Désinstallation](#désinstallation) · [Licence](#licence)

---

## Résultats

Machine de test : **iMac 27" (2020)**, macOS 26.6, Intel Core i7-10700K (8 cœurs / 16 threads, AVX2), 128 Go de DDR4-2667, **AMD Radeon Pro 5700 XT, 16 Go de GDDR6**.

Mesures faites avec `llama-bench` sur Qwen 3.5 9B, Q4_K_M (5,2 Go) :

| Moteur | Lecture du prompt (pp512) | Génération (tg128) |
|---|---:|---:|
| **Vulkan / MoltenVK, Radeon Pro 5700 XT** | **~270-286 tok/s** | **~30-35 tok/s** |
| CPU seul, 8 threads (AVX2) | 28 tok/s | 4,7 tok/s |

Via le serveur, en conversation réelle (avec les [réglages](#réglages-mesurés) ci-dessous, notamment `fa = auto`) :

| Modèle (4 bits) | Génération | Lecture du prompt | Remarques |
|---|---:|---:|---|
| **Qwen 3.5 9B** Q4_K_M + vision | **~30-33 tok/s** | ~225-250 tok/s | lit une capture d'écran pleine page (1 024 tokens d'image) en ~20-25 s |
| **Gemma 4 E4B** QAT Q4_0 | **~44 tok/s** | ~500 tok/s | le plus rapide |
| **Gemma 4 12B** QAT Q4_0 | **~24 tok/s** | ~130 tok/s | le plus capable |
| **Qwen3-Coder 30B-A3B** Q4_K_M (optionnel) | **~12 tok/s** | ~84 tok/s | code ; 18,6 Go, experts calculés depuis la RAM ([Réglages §12](#12-un-modèle-moe-plus-gros-que-la-vram--les-experts-en-ram)) |

`llama-bench` est un cas idéal : pas de gabarit de conversation, pas d'échantillonnage, contexte vide. Une réponse courte arrive en **~1 à 1,5 s**. Passer à un autre modèle prend **5 à 12 s** au premier message (chargement depuis le cache disque).

## Installation rapide

Prérequis : un Mac Intel sous macOS **12 ou plus récent**, un GPU AMD compatible Metal et **~10 Go** d'espace disque libre. Aucun `sudo` n'est nécessaire.

**GPU testé :** uniquement la Radeon Pro 5700 XT (Navi 10, 16 Go). Les autres GPU AMD pris en charge par MoltenVK (Polaris RX 5xx, Vega, autres cartes Navi) *devraient* fonctionner, mais ils ne sont **pas testés**. La VRAM limite la taille du modèle : avec une carte de 8 Go, prendre des modèles plus petits (≤ 4-7B). Les retours sont bienvenus.

```bash
# Serveur LLM seul (llama.cpp Vulkan + Qwen 3.5 9B + vision), en service d'arrière-plan
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash

# Pile complète : + Open WebUI (image Docker officielle, chat sur http://localhost:3000) + dictée
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash -s -- --full

# Idem, plus Gemma 4 E4B et Gemma 4 12B (QAT 4 bits de Google, ~12 Go de plus)
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash -s -- --full --gemma

# Idem, plus Qwen3-Coder 30B-A3B pour le code (18,6 Go de plus ; 32 Go de RAM ou plus conseillés)
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash -s -- --full --coder
```

`--full` exige **macOS 13 ou plus récent** : Open WebUI tourne dans une machine virtuelle basée sur le framework de virtualisation d'Apple.

Ce que fait l'installeur, étape par étape (lisez [`install.sh`](install.sh) avant de le lancer) :
1. Il vérifie que le Mac tourne sous macOS ≥ 12, est en x86_64, et dispose d'un GPU AMD et d'assez d'espace disque.
2. Il télécharge le **paquet llama.cpp Vulkan précompilé** depuis les Releases GitHub de ce dépôt, **vérifie son empreinte SHA-256**, puis l'installe dans `~/.local/share/llama-vk/`.
3. Il lance `llama-server --list-devices` pour confirmer que le GPU est bien visible via Vulkan.
4. Il télécharge **Qwen 3.5 9B Q4_K_M** et son **module vision** depuis Hugging Face (`unsloth/Qwen3.5-9B-GGUF`, ~6,5 Go) dans `~/models/`. Avec `--gemma`, il télécharge aussi les versions officielles QAT Q4_0 de **Gemma 4 E4B** et **Gemma 4 12B** publiées par Google (~12 Go ; 23 Go d'espace libre nécessaires). Avec `--coder`, il télécharge **Qwen3-Coder 30B-A3B** Q4_K_M (`unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF`, 18,6 Go ; 20 Go d'espace libre en plus).
5. Avec `--full`, il installe aussi :
   - l'**environnement de dictée Whisper**, un environnement Python dédié créé avec [uv](https://docs.astral.sh/uv/). Si uv est absent, il lance l'installeur officiel d'Astral. Le modèle Whisper (~1,5 Go) est téléchargé à la première utilisation ;
   - un **moteur Docker sans Docker Desktop** : Colima, Lima et le client Docker, tous en binaires officiels. Les empreintes de Colima et de Lima sont vérifiées ; pas de `sudo`, aucune licence à accepter.
6. Il installe les **LaunchAgents** (des services qui démarrent avec la session et redémarrent s'ils plantent). Le service llama.cpp tourne en **mode routeur** et ne liste que les modèles réellement téléchargés.
7. Avec `--full`, il lance un conteneur **SearXNG** pour la [recherche web](#recherche-web-searxng-local) (aucun port publié sur le Mac), puis **Open WebUI depuis l'image Docker officielle** sur `127.0.0.1:3000`. L'image d'Open WebUI pèse ~6,5 Go au premier lancement. Voir [pourquoi Docker](#open-webui--pourquoi-docker-sur-mac-intel).
8. Il fait un contrôle de santé.

Options : `--full`, `--gemma`, `--coder`, `--no-model`, `--no-service`.

## Ce qui n'a *pas* marché (inutile de réessayer)

| Piste | Résultat | Pourquoi |
|---|---|---|
| Ollama sur Mac Intel | CPU uniquement (`inference compute … library=cpu`) | la build x86_64 ne contient que des moteurs CPU ; Metal et MLX ne sont présents que dans la partie arm64 |
| Moteur **Metal** de llama.cpp sur la Radeon | `kIOAccelCommandBufferCallbackErrorTimeout`, puis le moteur reste en erreur | ses kernels Metal reposent sur des fonctions propres aux GPU Apple (opérations matricielles simdgroup) |
| Homebrew pour Vulkan (`vulkan-loader`, `shaderc`, `glslang`…) | tout est recompilé depuis les sources, Python compris (des heures) | pas de paquets précompilés x86_64 pour les macOS récents |
| **llama.cpp Vulkan + MoltenVK** | ✅ **fonctionne, 6 à 10 fois plus rapide que le CPU** | MoltenVK traduit Vulkan vers Metal ; les kernels Vulkan génériques tournent bien sur AMD |
| Open WebUI ≥ 0.8 installé en natif (pip/uv) | uv se rabat en silence sur la **0.7.2** | l'`onnxruntime` exigé (≥ 1.24) n'existe pas pour macOS x86_64 |
| …en forçant des dépendances plus anciennes (onnxruntime 1.23.2, transformers 4.x, NumPy 1.26) | démarre, mais combinaison non testée par le projet | transformers 5 exige PyTorch ≥ 2.4, or PyTorch s'arrête à la 2.2.2 sur Mac Intel |
| **Open WebUI en image Docker officielle** (Linux x86_64) | ✅ dépendances exactes du projet, même vitesse du LLM | voir [plus bas](#open-webui--pourquoi-docker-sur-mac-intel) |

## Architecture

```
Navigateur ──► Open WebUI       127.0.0.1:3000   (optionnel, --full : image Docker officielle dans une VM Colima)
                 │   via host.docker.internal → relayé par Lima vers le 127.0.0.1 du Mac
                 ├─► llama-server 127.0.0.1:8080  ── Vulkan ─► MoltenVK ─► Metal ─► Radeon   (natif)
                 │      ROUTEUR : qwen3.5-9b-gpu (texte + vision) | gemma-4-e4b | gemma-4-12b | qwen3-coder-30b
                 │      API compatible OpenAI /v1, un modèle sur le GPU et une requête à la fois
                 ├─► SearXNG      searxng:8080    (optionnel, --full : conteneur sur un réseau Docker privé, aucun port sur le Mac)
                 ├─► Whisper STT  127.0.0.1:8092  (optionnel, natif, CPU, dictée)
                 └─► Ollama       127.0.0.1:11434 (optionnel, CPU, gestion des modèles)
```

| LaunchAgent | Programme | Journaux |
|---|---|---|
| `com.llamacpp.vulkan` | `~/.local/share/llama-vk/bin/llama-server --models-preset …/models.ini --models-max 1` (routeur) | `~/Library/Logs/llama-vk/` |
| `com.whisper.stt` | `stt/whisper_server.py`, lancé avec `~/.local/share/whisper-stt/venv` | `~/Library/Logs/whisper-stt/` |
| `com.colima.start` | `~/.local/bin/colima start` : démarre la VM Docker à l'ouverture de session ; le conteneur `open-webui` redémarre ensuite seul (`--restart unless-stopped`) | `~/Library/Logs/colima/` |
| `com.ollama.serve` | `~/.local/share/ollama-bin/ollama` (optionnel) | `~/Library/Logs/ollama/` |

`scripts/install-services.sh` n'installe que les services dont le programme est présent. Les définitions des services sont des modèles dans [`launchd/`](launchd/), avec des marqueurs `__HOME__` et `__REPO__`. Le script produit aussi `~/.local/share/llama-vk/models.ini` à partir de [`llama/models.ini`](llama/models.ini), en retirant les modèles dont le fichier est absent.

## Le paquet précompilé

`llama-vulkan-macos-x64.tar.gz` (~33 Mo) est fabriqué par [`scripts/package-release.sh`](scripts/package-release.sh). Chacun peut le refabriquer à partir du même commit et comparer.

| Propriété | Comment | Pourquoi |
|---|---|---|
| Fonctionne sous **macOS 12+** | `CMAKE_OSX_DEPLOYMENT_TARGET=12.0` | une compilation locale par défaut cible la version de macOS de la machine (26 ici) et refuse de démarrer sur un système plus ancien |
| **Aucune dépendance à Homebrew** | `LLAMA_OPENSSL=OFF`, `LLAMA_CURL=OFF` | par défaut, la compilation se lie en silence à `/usr/local/opt/openssl@*` |
| **Un seul paquet pour tous les CPU Intel** | `GGML_NATIVE=OFF`, `GGML_BACKEND_DL=ON`, `GGML_CPU_ALL_VARIANTS=ON` | le moteur CPU (de Sandy Bridge à Ice Lake, Zen 4…) est choisi à l'exécution |
| **Relocalisable** | tous les rpath sont réécrits en `@loader_path`, et MoltenVK est lié en `@rpath/libMoltenVK.dylib` | fonctionne depuis n'importe quel dossier, y compris avec des espaces dans le chemin |
| MoltenVK inclus | `MoltenVK-macos.tar` officiel de KhronosGroup, v1.4.2 (Apache-2.0) | pas besoin du SDK Vulkan |
| Signature de code ad hoc | `codesign -s -` | voir la remarque sur Gatekeeper ci-dessous |

Vérifié avant publication : uniquement des dépendances système ou `@rpath` (`otool -L`), `minos 12.0`, GPU détecté et même vitesse en lançant depuis un dossier neuf avec un environnement vide (`env -i`).

**Gatekeeper.** Les binaires ne sont pas notarisés (il faudrait un Apple Developer ID payant).
- `curl` (utilisé par l'installeur) ne pose pas l'attribut de quarantaine : rien n'est bloqué.
- Si vous téléchargez l'archive **avec un navigateur**, macOS la rejettera. Retirez d'abord l'attribut :

```bash
xattr -dr com.apple.quarantine llama-vulkan-macos-x64/
```

## Compiler soi-même

Prérequis : les Command Line Tools (`xcode-select --install`), `cmake`, `git`, `python3` et `curl`. Xcode lui-même n'est **pas** nécessaire.

```bash
scripts/build-llama-vulkan.sh            # compilation locale, installée dans ~/.local/share/llama-vk/bin
scripts/package-release.sh <ref> dist/   # paquet redistribuable (macOS 12+, relocalisable)
```

Ce que le script de compilation assemble, dans l'ordre :
1. **MoltenVK** : le binaire officiel des releases de KhronosGroup. Il fournit Vulkan au-dessus de Metal.
2. **Vulkan-Headers** : les en-têtes C et `vulkan.hpp`.
3. **shaderc → `glslc`** : compilé depuis les sources en ~5 min. ggml-vulkan compile ses shaders pendant la compilation.
4. **SPIRV-Headers** : installés dans `~/.local/vulkan`. Ils fournissent `find_package(SPIRV-Headers CONFIG)` et `spirv/unified1/spirv.hpp`.
5. **llama.cpp**, configuré ainsi :

```
cmake -B build-vk -DGGML_METAL=OFF -DGGML_VULKAN=ON -DLLAMA_CURL=OFF \
  -DCMAKE_PREFIX_PATH=~/.local/vulkan -DCMAKE_CXX_FLAGS="-I$HOME/.local/vulkan/include" \
  -DVulkan_INCLUDE_DIR=…/Vulkan-Headers/include \
  -DVulkan_LIBRARY=…/libMoltenVK.dylib \          # lien direct vers MoltenVK, sans chargeur Vulkan
  -DVulkan_GLSLC_EXECUTABLE=…/shaderc/build/glslc/glslc
```

Erreurs de compilation possibles et leurs correctifs (les deux sont déjà gérés dans le script) :

| Erreur | Correctif |
|---|---|
| `Could not find a package configuration file provided by "SPIRV-Headers"` | installer SPIRV-Headers et ajouter leur préfixe à `CMAKE_PREFIX_PATH` |
| `'spirv/unified1/spirv.hpp' file not found` | ajouter `-I<préfixe>/include` à `CMAKE_CXX_FLAGS` |

## Réglages (mesurés)

Tous les réglages sont dans [`llama/models.ini`](llama/models.ini), commentés. Les réglages communs sont dans la section `[*]`, puis vient une section par modèle, dont le nom est l'identifiant du modèle :

```ini
[*]
ngl = 99, t = 2, tb = 2, poll = 0, c = 32768, parallel = 1, fa = auto, jinja = true, ub = 128
[qwen3.5-9b-gpu]   mmproj, image-max-tokens = 1024, enable_thinking false, temp 0.7 / top-p 0.8 / top-k 20 / presence 1.5
[gemma-4-e4b]      enable_thinking false, temp 1.0 / top-p 0.95 / top-k 64
[gemma-4-12b]      enable_thinking false, temp 1.0 / top-p 0.95 / top-k 64
```

(Le bloc ci-dessus est un résumé ; le vrai fichier a une clé par ligne.)

Garder des identifiants de modèle **sans espace** : Open WebUI ≥ 0.13 refuse les identifiants contenant des espaces lorsqu'on crée ou surcharge un modèle.

### 0. `fa = auto`, jamais `fa = on` : le plus gros gain

La flash attention **n'existe pas via Vulkan/MoltenVK sur ce GPU**. `-fa on` n'échoue pas : llama.cpp fait alors tourner l'attention **sur le CPU**, sans prévenir autrement que par un avertissement (`layer N is assigned to device Vulkan0 but Flash Attention is assigned to device CPU`). Avec `auto`, elle est simplement désactivée et tout reste sur le GPU :

| Même modèle, mêmes requêtes | Génération | Lecture du prompt |
|---|---:|---:|
| `-fa on` | 25,6 tok/s | 170 tok/s |
| **`-fa auto`** | **32,7 tok/s (+28 %)** | **248 tok/s (+46 %)** |

C'est pire avec un module vision. Sous `-fa on`, l'encodeur d'image tourne aussi sur le CPU : une capture d'écran prenait **~110 s au lieu de ~20 s**.

### 1. CPU à ~670 % alors que le modèle est à 100 % sur le GPU

Le journal confirme que le modèle est entièrement sur le GPU (`offloaded 33/33 layers to GPU`). Seule `token_embd` (~545 Mo) reste en RAM : c'est une table de correspondance, ce qui est normal. Pourtant le CPU tournait à environ 670 %, parce que les threads de llama.cpp **attendent le GPU en boucle** (`--poll 50` par défaut).

| Options | pp512 | tg128 | Temps CPU du test |
|---|---:|---:|---:|
| `-t 8 --poll 50` (défaut) | 251 tok/s | 23,5 tok/s | 43 s |
| `-t 8 --poll 0` | 272 tok/s | 30,2 tok/s | 6 s |
| **`-t 2 --poll 0`** | **273 tok/s** | **34,7 tok/s** | **5,6 s** |

Après correction, le CPU reste à ~50 % pendant la génération, le Mac chauffe moins, et la génération est **plus rapide**.

### 2. Modèles à réflexion (Qwen 3.5) : la piloter requête par requête

- **Ne pas** utiliser `--reasoning-budget 0`. Ce réglage coupe la réflexion pour tout le serveur, et les requêtes ne peuvent plus la réactiver (testé).
- **À la place**, la couper par défaut avec `--chat-template-kwargs '{"enable_thinking":false}'`, puis l'activer requête par requête :

```json
{ "chat_template_kwargs": {"enable_thinking": true},
  "reasoning_budget_tokens": 1024,
  "reasoning_budget_message": "\n\nJe dois maintenant conclure et donner ma réponse finale.\n" }
```

Sans plafond, Qwen 3.5 écrit de 1 300 à plus de 3 300 tokens de réflexion (2 à 4 min), même sur des questions simples. Avec plafond, sur 4 questions de logique à réponse connue :

| Plafond | Justes | Temps moyen / question |
|---|---:|---:|
| 512 | 3/4 | ~32 s |
| **1 024** | **4/4** | **~53 s** |
| 2 048 | 4/4 | ~110 s |
| aucun | — | > 2 min |

Le modèle épuise presque toujours son budget : c'est donc le plafond qui fixe la latence.

### 3. Une requête à la fois : `--parallel 1`

Par défaut, llama-server ouvre 4 « slots » parallèles **et divise le contexte entre eux** : `-c 32768` ne laisse que 8 192 tokens par conversation.

Sur ce GPU, les requêtes simultanées s'effondrent. Mesure faite avec Open WebUI 0.13, dont les tâches de fond (titre, tags, suggestions) tournent **en même temps** que votre réponse :
- **13 tok/s** en lecture, au lieu de ~270 ;
- **0,3 tok/s** en écriture : une simple question a pris environ une minute.

Avec `--parallel 1` :
- les requêtes font la queue : deux requêtes simultanées tournent chacune à **29,5 tok/s**, la seconde attendant simplement la première ;
- chaque conversation retrouve **tout le contexte de 32k**.

### 4. « Outils intégrés » d'Open WebUI ≥ 0.12 : à désactiver

Open WebUI active désormais **par défaut, sur tous les modèles**, des outils intégrés : recherche web, mémoire, notes, connaissances, compétences… Leur description est injectée **dans chaque requête**.

Mesure : une question de 8 tokens partait avec un **contexte d'environ 7 900 tokens**, soit **40 à 45 s de lecture** sur ce GPU avant le premier mot. Outils coupés, la même question part avec **639 tokens**, et la réponse arrive en **~1,5 s**.
- Par modèle : Espace de travail → Modèles → Capacités → décocher **Builtin Tools**.
- Globalement : définir la variable d'environnement `DEFAULT_MODEL_METADATA='{"capabilities":{"builtin_tools":false}}'`. [`scripts/owui-docker.sh`](scripts/owui-docker.sh) le fait ; les réglages par modèle restent prioritaires.

### 5. Chaleur

Une longue réflexion maintient la Radeon à 100 % pendant plusieurs minutes, et les ventilateurs montent nettement. Ils redescendent 1 à 2 min après la dernière requête.

### 6. Garder le Mac utilisable : `ub = 128`

macOS ne permet pas de régler une priorité GPU pour le calcul. Pendant que llama.cpp lit un prompt, chaque micro-lot est un long bloc de travail GPU, et le WindowServer doit l'attendre : **l'affichage se fige**.

| `ub` (micro-lot) | Lecture du prompt | GPU occupé par bloc |
|---|---:|---:|
| 512 (défaut) | 249 tok/s | ~2 s |
| 256 | 238 tok/s | ~1,1 s |
| **128** | **224 tok/s** | **~0,6 s** |

La génération n'est pas touchée (~27 tok/s dans les trois cas). La vision de Qwen garde son budget complet de 1 024 tokens avec `ub = 128`.

### 7. Plusieurs modèles, un seul GPU : le mode routeur

`llama-server` lancé **sans modèle** devient un routeur : `--models-preset models.ini --models-max 1`.
- `GET /v1/models` liste tous les modèles déclarés, avec leur état.
- Chaque requête est aiguillée selon son champ `"model"`. Le routeur démarre le processus `llama-server` de ce modèle et arrête le précédent.
- Une bascule coûte 5 à 12 s ; ensuite, le modèle tourne à pleine vitesse.
- Open WebUI voit tous les modèles automatiquement.

Une carte de 16 Go ne peut pas tenir trois modèles à la fois, d'où `--models-max 1`.

### 8. Vision : le budget de tokens par image

Le nombre de tokens qu'une image peut occuper compte plus que la taille du modèle :
- **Qwen 3.5** : `image-max-tokens = 1024`.
  - Au-delà, une opération de l'encodeur d'image (un softmax sur ~8 000 patchs) n'a pas de kernel Vulkan et bascule sur le CPU : ~260 s par image.
  - À 768, les chiffres commencent à être mal lus (3,04 au lieu de 3,06).
- **Gemma 4** encode toute l'image dans **un seul micro-lot** (attention non causale). L'image est donc plafonnée en silence à `ub` (`cap image_max_tokens … to 512 (n_ubatch = 512)`).
  - **E4B** a besoin de `ub = 1152` pour lire correctement une page dense. Le GPU est alors bloqué ~2 s à chaque fois, voir §6.
  - **12B** : avec `ub > 512`, son encodeur d'image **renvoie des valeurs fausses** sous Vulkan (il a lu 74,34 au lieu de 97,34). Rester à 512.
- D'où le choix par défaut ici : **Qwen est le modèle vision**, et les Gemma sont en texte seul. Réactiver leur vision tient en une ligne chacun dans `models.ini`.

### 9. Le 4 bits suffit (et le QAT de Gemma est fait pour)

Les mêmes requêtes, mesurées avec des versions 6 et 8 bits :

| Modèle | 4 bits | 6-8 bits | Coût en vitesse | Différence de qualité constatée |
|---|---|---|---:|---|
| Qwen 3.5 9B | Q4_K_M 5,7 Go | Q6_K 7,5 Go | −21 % | aucune sur nos vérifications |
| Gemma 4 E4B | QAT Q4_0 5,2 Go | Q8_0 8,0 Go | ~−20 % | aucune visible |

La génération est limitée par la bande passante mémoire : un fichier plus gros coûte de la vitesse presque proportionnellement. Les versions **QAT** de Google sont ré-entraînées pour bien fonctionner en 4 bits ; inutile de chercher un « QAT Q6 ».

### 10. Gemma 4 réfléchit par défaut

Sans `enable_thinking: false`, Gemma 4 E4B et 12B écrivent 600 à 750 caractères de réflexion cachée avant chaque réponse. Coupez-la dans leur section, comme pour Qwen, et réactivez-la requête par requête.

### 11. Testé, puis écarté

| Piste | Résultat |
|---|---|
| Têtes de prédiction MTP de Gemma 4 (`--spec-type draft-mtp` + `mtp-*.gguf` de ggml-org) | **0 à 0,3 % des propositions acceptées**, génération **divisée par 2,5** (ex. 42,9 → 16,4 tok/s) |
| `--swa-full` pour Gemma | aucun gain : le llama.cpp actuel ne relit déjà que le nouveau tour (17 à 100 tokens). La lecture du prompt est plus lente. |
| Q6_K / Q8_0 | voir §9 |

### 12. Un modèle MoE plus gros que la VRAM : les experts en RAM

Qwen3-Coder 30B-A3B est un modèle **à experts** (MoE) : 30 milliards de paramètres au total, mais ~3 milliards seulement servent à chaque token. En Q4_K_M, il pèse 18,6 Go, trop pour 16 Go de VRAM (macOS en occupe déjà ~4,4 Go ici). `--n-cpu-moe N` garde en RAM les experts des N premières couches, calculés par le CPU ; l'attention et le cache KV restent sur le GPU. Comme peu d'experts travaillent à chaque token, la perte de vitesse est bien moindre qu'en déchargeant un modèle dense.

| Réglage (prompt de 2 400 tokens) | Lecture | Génération | VRAM laissée à l'affichage |
|---|---:|---:|---:|
| `n-cpu-moe 30`, `ub 128` | — | 19,5 tok/s | **0,3 Go** : affichage étouffé, rejeté |
| `n-cpu-moe 40`, `ub 128` | 40 tok/s | 15 tok/s | 3,2 Go |
| `n-cpu-moe 40`, `ub 1024` | 119 tok/s | 13,6 tok/s | 2,0 Go |
| **`n-cpu-moe 48` (tous les experts en RAM), `ub 512`** | **84 tok/s** | **12 tok/s** | **5,0 Go** (Qwen 3.5 9B en laisse 4) |

- **Ici, `ub` compte, contrairement aux modèles denses** : avec les experts en RAM, chaque lot recopie leurs poids vers le GPU. Avec `ub 128`, la lecture du prompt est divisée par deux. C'est pénalisant pour les agents de code, qui envoient des prompts de ~10 000 tokens.
- Plus de threads CPU pour ce modèle seulement (`t = 6`) : les experts tournent sur le CPU.
- La VRAM libre se lit avec `ioreg -r -d1 -w0 -c IOAccelerator | grep -o '"vramFreeBytes"=[0-9]*'`.
- À l'usage, l'affichage est resté fluide, et la génération à ~12 tok/s va plus vite que la lecture. Le premier chargement est rapide une fois le fichier dans le cache de fichiers de macOS (ici, 128 Go de RAM).

## Choisir un modèle / dimensionner la VRAM

**Vitesse de génération ≈ débit mémoire effectif ÷ octets de poids actifs relus par token.**

- Débit VRAM théorique de la Pro 5700 XT : ~384-448 Go/s selon les sources. Débit effectif mesuré via MoltenVK : **~180 Go/s** (5,2 Go × 34,7 tok/s). La couche de traduction coûte environ la moitié.
- RAM : DDR4-2667 en double canal, ~43 Go/s théoriques, **~30 Go/s utiles**, environ 6 fois plus lente.

| Classe de modèle | Tient dans 16 Go de VRAM ? | Génération attendue |
|---|---|---|
| Dense ≤ 9B (Q4 ≈ 5-6 Go) | ✅ avec un grand contexte | ~30-35 tok/s (mesuré : Qwen 3.5 9B) |
| Gemma 4 E4B (QAT Q4_0, 5,2 Go, ~4B actifs) | ✅ | **~44 tok/s** (mesuré) |
| Dense 12-14B (Q4 ≈ 7-9 Go) | ✅, le contexte devient plus serré | **~24 tok/s** (mesuré : Gemma 4 12B QAT) |
| Dense ≥ 27B | ❌ déchargement partiel | lent |
| MoE moyen (30B, ~3B actifs), experts en RAM (`--n-cpu-moe`) | attention + KV seulement | **~12 tok/s** (mesuré : Qwen3-Coder 30B-A3B, §12) |
| Gros MoE (100B+, ~5-6B actifs) avec experts en RAM (`--n-cpu-moe`) | poids en RAM | **~5-8 tok/s (estimation)** : traitements par lots seulement |

**Le cache KV compte autant que les poids :**
- **Qwen 3.5 est hybride** : une couche sur quatre seulement utilise l'attention complète (les autres apparaissent en `filtered` dans le journal). Un contexte de 32k coûte donc peu, et le cache de prompt est réutilisé d'un tour à l'autre.
- Les modèles **Gemma** utilisent une attention à fenêtre glissante. Avec le cache SWA compact, les anciennes versions de llama.cpp relisaient tout l'historique à chaque tour. La version actuelle (celle du mode routeur) garde des points de reprise : mesuré, au 2ᵉ tour d'une conversation de 4 300 tokens, seuls **17 à 100 tokens** ont été relus. `--swa-full` n'est plus nécessaire.

## Utiliser l'API

Le serveur est compatible OpenAI :

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "messages": [{"role": "user", "content": "Explique MoltenVK en une phrase."}],
  "max_tokens": 200 }'
```

En mode routeur, **`"model"` est obligatoire** (`qwen3.5-9b-gpu`, `gemma-4-e4b`, `gemma-4-12b`, `qwen3-coder-30b`). Sans lui, le serveur répond HTTP 400 `model name is missing from the request`.

La réponse contient `timings` (`prompt_per_second`, `predicted_per_second`). Autres points d'accès utiles :
- `GET /health` ;
- `GET /v1/models` : tous les modèles et leur état (`loaded` / `unloaded`) ;
- `POST /models/unload` avec `{"model": "…"}` : libère le GPU ;
- `GET /slots?model=…` : ce qui tourne en ce moment.

Pour la vision, envoyer `content` sous forme de liste contenant `{"type":"image_url","image_url":{"url":"data:image/png;base64,…"}}`.

## Open WebUI : pourquoi Docker sur Mac Intel

Depuis la 0.8, une installation native d'Open WebUI ne fonctionne plus correctement sur Mac Intel :
- l'`onnxruntime` qu'elle exige (≥ 1.24) **n'existe pas pour macOS x86_64** : `uv`/`pip` se rabattent en silence sur la **0.7.2** (janvier 2026) ;
- en forçant des dépendances plus anciennes, la 0.13 démarre, mais `transformers` 5 exige **PyTorch ≥ 2.4**, qui **s'arrête à la 2.2.2 sur Mac Intel** ;
- PyTorch 2.2.2 a été compilé pour **NumPy 1.x** : avec NumPy 2, les embeddings échouent (`RuntimeError: Numpy is not available`). **Même en 0.7.2, les embeddings de documents (RAG) sont cassés.**

L'**image Docker officielle** tourne sous Linux x86_64, où toutes les dépendances existent : PyTorch 2.9, NumPy 2.5, onnxruntime 1.26, transformers 5.5. Mesures sur cette machine :

| | 0.7.2 native | **0.13.3 Docker** |
|---|---|---|
| Génération du LLM (le conteneur appelle le llama-server natif) | 26,3-26,5 tok/s | **26,1-26,5 tok/s** (surcoût réseau ~0,02 s) |
| Embeddings, 512 passages | cassés (NumPy 2 contre PyTorch 2.2) | **1,40 s** (CPU, VM) |
| Conteneur au repos | — | 0,4 % de CPU, ~1 Go de RAM |

**Réseau.** Depuis le conteneur, `host.docker.internal` (192.168.5.2) atteint le **127.0.0.1 du Mac** : Lima relaie le trafic. llama-server, Whisper et Ollama restent donc en boucle locale. Dans Open WebUI, utiliser `http://host.docker.internal:8080/v1` pour le LLM et `http://host.docker.internal:8092/v1` pour la dictée, jamais `127.0.0.1`, qui dans un conteneur désigne le conteneur lui-même.

**Lancer / mettre à jour :**
```bash
scripts/owui-docker.sh            # crée le conteneur (127.0.0.1:3000, données dans ~/.local/share/open-webui-docker)
scripts/owui-docker.sh v0.13.4    # mise à jour : nouvelle image, mêmes données
```

**Migrer depuis une installation native** : copier `webui.db` avec l'API de sauvegarde de SQLite (cohérente même en fonctionnement), ainsi que les dossiers `uploads/` et `vector_db/`, dans le dossier de données Docker. Corriger l'URL de dictée en `host.docker.internal`, puis réutiliser la même `WEBUI_SECRET_KEY`. Une migration 0.7.2 → 0.13.3 a appliqué 43 migrations de schéma sans erreur ; modèles, prompts, réglages et conversations ont tous été conservés.

## Configurer Open WebUI

`--full` branche automatiquement llama-server : `OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1`. Il coupe aussi les outils intégrés par défaut et configure la [recherche web](#recherche-web-searxng-local).

Tous les modèles du routeur apparaissent automatiquement dans le sélecteur. Puis configurer, dans cet ordre :
1. **Deux modèles sur la même base**, dans Espace de travail → Modèles → Nouveau. À refaire pour chaque base voulue, par exemple un « rapide » sur `gemma-4-e4b` :
   - **« rapide »** : Paramètres avancés → paramètre personnalisé `chat_template_kwargs` = `{"enable_thinking": false}` ;
   - **« réflexion »** : `chat_template_kwargs` = `{"enable_thinking": true}`, `reasoning_budget_tokens` = `1024`, `reasoning_budget_message` = `"\n\nJe dois maintenant conclure…\n"`.
2. **Modèle de tâche** : Réglages admin → Interface → Modèle de tâche = **« rapide »**. Sinon chaque génération de titre, de tags ou de suggestion lance elle aussi un long brouillon de réflexion, en parallèle de votre réponse.
3. **Modèle par défaut** = « rapide ». Réglages admin → Modèles.
4. Un **prompt système** par modèle (Espace de travail → Modèles → modifier → Prompt système) : [`open-webui/system-prompt-fr.md`](open-webui/system-prompt-fr.md) ou [`system-prompt-en.md`](open-webui/system-prompt-en.md). Il est généraliste : règles de fiabilité (ne pas inventer de faits, de sources ni de sigles) et format **synthèse courte + liens** pour les résultats de recherche web.
5. Optionnel : un **glossaire métier** dans le prompt système. Voir [Enseignements](#enseignements) et [`open-webui/system-prompt-sante-fr.md`](open-webui/system-prompt-sante-fr.md).

Le plus simple est **une seule entrée par modèle**, sans paires « rapide/réflexion », si vous utilisez rarement la réflexion. Dans ce cas, laissez le **modèle de tâche vide** (= le modèle de la conversation). S'il est fixé sur un modèle, chaque génération de titre ou de tags fait basculer le routeur d'un modèle à l'autre (5 à 12 s à chaque fois, et « Server disconnected » sur la réponse en cours).

## Recherche web (SearXNG local)

Un modèle local ne sait rien de ce qui suit son entraînement. Avec `--full`, Open WebUI propose un **bouton « Recherche web »** dans la zone de saisie (désactivé tant qu'on ne clique pas ; il se remet à zéro au changement de modèle ou de conversation) :
1. le modèle formule les requêtes ;
2. Open WebUI les envoie à **SearXNG**, un métamoteur qui tourne dans son propre conteneur (sans compte, sans clé API, sans profil publicitaire ; il interroge lui-même Google, Bing, DuckDuckGo…) ;
3. le modèle répond à partir des résultats : une **synthèse courte (5 points au maximum), puis une liste « Sources » avec les vrais liens**.

| Choix | Pourquoi |
|---|---|
| SearXNG en conteneur, **aucun port publié sur le Mac** | Open WebUI le joint par son nom sur un réseau Docker privé (`owui-net`, `http://searxng:8080/search`). Sortie JSON activée, limiteur coupé (un seul client). Version d'image épinglée ; ~130 Mo de RAM. |
| **Résumés des moteurs seulement** (`BYPASS_WEB_SEARCH_WEB_LOADER` + `BYPASS_WEB_SEARCH_EMBEDDING_AND_RETRIEVAL`) | titre + lien + résumé de ~150 caractères de 6 résultats par requête, **moins de 1 000 tokens**. Télécharger 4 pages entières puis calculer leurs embeddings prenait l'essentiel de l'attente, identique pour tous les modèles. Contrepartie : des réponses plus superficielles ; ouvrir les liens pour le détail. |
| `function_calling = legacy` (`DEFAULT_MODEL_PARAMS`) | en mode **natif**, le bouton d'Open WebUI 0.13 **ne fait rien** : il attend que le modèle appelle l'outil intégré `web_search`, or les outils intégrés sont coupés (ils ajoutent ~7 900 tokens à chaque requête). |
| `RAG_SOURCE_METADATA_KEYS=source,title` | par défaut, le modèle ne voit que les extraits numérotés, pas leurs adresses, et inventerait les liens qu'on lui demande. |
| `RAG_TEMPLATE` = [`open-webui/rag-template.md`](open-webui/rag-template.md) | le gabarit par défaut est placé dans le message de *l'utilisateur*, donc il l'emporte sur le prompt système, et il ne demande que des renvois `[id]` : pas de liens. Le nôtre demande 5 points au maximum, puis des lignes `[id] titre — URL`. **La consigne de format est placée *après* les résultats** : placée avant, Qwen 9B l'ignorait. Testé sur une installation vierge sans prompt système : Qwen 3.5 9B et Gemma 4 E4B ont donné 4 à 5 liens, **tous présents dans les résultats réels**, en 17 à 30 s. |
| Modèle d'embedding `intfloat/multilingual-e5-small` (préfixes `query: ` / `passage: `) | utilisé pour les documents joints. Celui par défaut, `all-MiniLM-L6-v2`, est anglais et rate les passages en français (avec e5 : 0,88 pour le passage pertinent contre 0,74 pour les hors-sujet). |

Ne pas combiner le téléchargement des pages et le contournement de la sélection d'extraits : Open WebUI injecte alors les pages **sans aucune limite de taille** (`WEB_FETCH_MAX_CONTENT_LENGTH` ne vaut que pour l'outil intégré) et peut remplir les 32 000 tokens de contexte.

**Le gabarit de conversation de Qwen 3.5 refuse un second message système** (HTTP 500 `System message must be at the beginning`). Open WebUI 0.13 ajoute le contexte de recherche au message de *l'utilisateur*, donc tout va bien, sauf si `RAG_SYSTEM_CONTEXT=true` est défini. Ne le définissez pas.

Ces réglages sont passés en variables d'environnement, qui initialisent la configuration d'Open WebUI **au premier démarrage seulement**. Sur une installation existante, réglez-les dans Réglages admin → Recherche web, et par modèle (Paramètres avancés → Appel de fonctions = Legacy ; Capacités → Recherche web).

```bash
scripts/searxng-docker.sh          # (re)crée le conteneur SearXNG ; Open WebUI est rattaché au même réseau
docker exec searxng wget -qO- 'http://127.0.0.1:8080/search?q=test&format=json' | head -c 300   # test
```

## Dictée vocale

**Le Whisper intégré à Open WebUI fait planter tout le processus (SIGSEGV) à la première transcription sous macOS Intel.**
- Le rapport de plantage macOS montre `libiomp5.dylib __kmp_suspend_64` dans le thread fautif.
- `ctranslate2` (faster-whisper) charge `libiomp5` d'Intel, et PyTorch charge `libomp` de LLVM. Deux runtimes OpenMP dans le même processus finissent par planter.

Le correctif : [`stt/whisper_server.py`](stt/whisper_server.py) fait tourner faster-whisper **dans son propre processus**, sans PyTorch, avec une API compatible OpenAI (`POST /v1/audio/transcriptions`) sur `127.0.0.1:8092`. Il tourne en natif, dans un environnement dédié : [`scripts/setup-stt.sh`](scripts/setup-stt.sh), dans `~/.local/share/whisper-stt/venv`.

Pour le brancher sur Open WebUI : Réglages admin → Audio → moteur STT **OpenAI**, URL `http://host.docker.internal:8092/v1` (Docker ; `http://127.0.0.1:8092/v1` pour un Open WebUI natif), une clé API quelconque, modèle `large-v3-turbo`.

Résultats sur une vraie dictée (en français, avec des sigles métier, sur le CPU pour laisser le GPU au LLM) :

| | `small` | **`large-v3-turbo`** |
|---|---|---|
| Temps pour 12-19 s d'audio | ~2,3 s | ~6 s |
| Erreurs | « pourgogne froche comptée » pour « Bourgogne-Franche-Comté », « cas d'ordre » pour « cadre » | aucune, hors un sigle inconnu |

Le vocabulaire métier est géré par deux fichiers placés à côté du serveur :
- [`stt/lexique.txt`](stt/lexique.txt) : transmis à Whisper comme `initial_prompt`. Efficace sur `small`, beaucoup moins sur turbo, dont le décodeur n'a que 4 couches.
- [`stt/corrections.tsv`](stt/corrections.tsv) : corrections déterministes par expressions régulières, appliquées après la transcription. La réponse contient aussi `raw_text`, la transcription avant correction, pour contrôle.

Après modification de l'un de ces fichiers, recharger le service : `launchctl kickstart -k gui/$(id -u)/com.whisper.stt`.

## Génération d'images (optionnelle)

La génération d'images a été **testée, intégrée à Open WebUI, puis désinstallée** : les services en ligne font bien mieux, et le GPU est plus utile au LLM. Tout le nécessaire pour la réinstaller est conservé dans [`extras/image-generation/`](extras/image-generation/README.fr.md) :
- stable-diffusion.cpp en Vulkan ;
- **Z-Image-Turbo** : ~65 s en 512 px, ~4 min 30 en 1024 px, texte exact dans les images ;
- SDXL-Turbo : ~19 s en 512 px avec TAESD ;
- le branchement dans Open WebUI et ses pièges ;
- une note sur Qwen-Image.

## Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `"llama-server" ne peut pas être ouvert` / tué au lancement | quarantaine Gatekeeper (archive téléchargée avec un navigateur) | `xattr -dr com.apple.quarantine ~/.local/share/llama-vk` |
| `--list-devices` n'affiche pas `Vulkan0` | MoltenVK introuvable, ou pas de GPU compatible Metal | `otool -L bin/libggml-vulkan.so` doit afficher `@rpath/libMoltenVK.dylib` ; vérifier `system_profiler SPDisplaysDataType` |
| `ggml_vulkan: WARNING: Instance extension VK_KHR_portability_enumeration not found` / `[mvk-warn] … robustness` | avertissements d'information de MoltenVK | sans conséquence |
| `Bootstrap failed: 5: Input/output error` en réinstallant un service | `launchctl bootout` est asynchrone | attendre que `launchctl print gui/$UID/<label>` échoue, puis relancer le bootstrap (`install-services.sh` le fait) |
| Réponse vide avec un petit `max_tokens` | le brouillon de réflexion a consommé tout le budget | réflexion coupée par défaut, et plafonnée avec `reasoning_budget_tokens` |
| Réponses très lentes, ~5 tok/s ou moins | requêtes simultanées (tâches de fond d'Open WebUI) et 4 slots parallèles | `--parallel 1` ; régler le modèle de tâche d'Open WebUI sur « rapide » ; vérifier `GET /slots` |
| 40 s ou plus avant le premier mot, même pour « bonjour » (Open WebUI ≥ 0.12) | outils intégrés injectés dans chaque requête (~7 900 tokens) | décocher Builtin Tools par modèle, ou `DEFAULT_MODEL_METADATA='{"capabilities":{"builtin_tools":false}}'` |
| Open WebUI ≥ 0.8 ne s'installe pas en natif ; uv installe la 0.7.2 | pas de paquets macOS x86_64 pour ses dépendances | utiliser l'image Docker officielle (`scripts/owui-docker.sh`) |
| `String should match pattern '^\S+$'` en modifiant un modèle | identifiant de modèle avec espaces (`--alias` de llama-server) | utiliser un alias sans espace, par exemple `qwen3.5-9b-gpu` |
| Open WebUI (Docker) n'atteint pas le LLM ni la dictée | `127.0.0.1` dans un conteneur désigne le conteneur lui-même | utiliser `http://host.docker.internal:<port>` |
| `Response payload is not completed: TransferEncodingError` | llama-server redémarré ou tué en pleine réponse | renvoyer la question ; consulter `~/Library/Logs/llama-vk/` |
| CPU ~700 % pendant la génération | attente active en boucle | `-t 2 -tb 2 --poll 0` |
| Open WebUI redémarre quand on dicte | conflit OpenMP dans son Whisper intégré | utiliser le service de dictée séparé |
| Micro « refusé » dans un navigateur intégré | certains navigateurs intégrés bloquent `getUserMedia` | utiliser Safari ou Chrome sur `http://localhost:3000` (localhost est considéré comme sûr) |
| `warmup: the mmproj graph uses unsupported operators by the backend` | quelques opérations du module vision n'ont pas de kernel Vulkan | sans conséquence à `image-max-tokens = 1024` (~20 s par page) ; au-delà, l'encodeur ralentit fortement, voir Réglages §8 |
| Génération ~25 % plus lente que prévu ; une image prend ~2 min | `-fa on` : la flash attention tourne sur le CPU | `fa = auto` (Réglages §0) |
| Tout le Mac se fige pendant la lecture d'un long prompt ou d'une image | de longs micro-lots GPU privent le WindowServer du GPU | `ub = 128` (Réglages §6) ; éviter de faire tourner plusieurs modèles à la fois |
| HTTP 400 `model name is missing from the request` | le mode routeur exige le champ `model` | ajouter `"model": "qwen3.5-9b-gpu"` (ou un autre identifiant de `/v1/models`) |
| Gemma répond lentement, ou `content` est vide avec un petit `max_tokens` | Gemma 4 réfléchit par défaut | `chat-template-kwargs = {"enable_thinking":false}` dans sa section |
| Gemma lit mal les chiffres d'une image, ou décrit des choses absentes | image plafonnée par `ub` (E4B), ou `ub > 512` (12B) | Réglages §8 ; utiliser Qwen pour les documents |
| Bouton « Recherche web » activé, mais le modèle répond de mémoire | appel de fonctions du modèle en « natif » (Open WebUI 0.13 attend alors un appel d'outil intégré) | Paramètres avancés → Appel de fonctions = **Legacy** (`DEFAULT_MODEL_PARAMS='{"function_calling":"legacy"}'`) |
| Pas de bouton « Recherche web » | recherche web désactivée, ou capacité absente sur le modèle | Réglages admin → Recherche web ; modèle → Capacités → Recherche web |
| Le modèle invente des liens dans ses « Sources » | les adresses ne sont pas transmises au modèle par défaut | `RAG_SOURCE_METADATA_KEYS=source,title` |
| Les réponses web citent `[1]` mais sans liste de liens | le gabarit RAG par défaut d'Open WebUI, dans le message de l'utilisateur, l'emporte sur le prompt système | `RAG_TEMPLATE` tiré de [`open-webui/rag-template.md`](open-webui/rag-template.md) (Réglages admin → Documents → Gabarit RAG sur une installation existante) |
| Qwen 3.5 : HTTP 500 `System message must be at the beginning` | un second message système (ex. `RAG_SYSTEM_CONTEXT=true`) | ne pas définir `RAG_SYSTEM_CONTEXT` |
| Qwen3-Coder : l'affichage saccade, ou il ne reste presque plus de VRAM | trop de couches d'experts sur le GPU | `n-cpu-moe = 48` (Réglages §12) |
| Open WebUI : `disk I/O error` après une modification de `webui.db` | base modifiée depuis le Mac pendant que le conteneur tournait (SQLite WAL via virtiofs) | arrêter le conteneur, modifier, le redémarrer |

Journaux : `~/Library/Logs/{llama-vk,whisper-stt,colima,ollama}/` et `docker logs open-webui`. Contrôle de l'état : `~/.local/share/llm-local-intel-mac-amd/scripts/healthcheck.sh`.

## Enseignements

1. **Mesurer plutôt que supposer.** L'installation par défaut de chaque outil passait à côté du matériel réel : CPU seul, mauvaise version de macOS ciblée, dépendance cachée à Homebrew, threads en attente active.
2. **Le vrai goulot, c'est la bande passante mémoire.** Choisir un modèle qui tient entièrement en VRAM, en dimensionnant aussi son cache KV.
3. **Tester la vitesse d'une vraie question dans l'interface, pas seulement que « ça marche ».** La montée en Open WebUI 0.13 passait tous les tests fonctionnels, mais chaque question avait pris ~40 s de plus, à cause des outils intégrés et des tâches de fond simultanées.
4. **Un petit modèle invente les faits métier avec aplomb.**
   - Sur une phrase parfaitement transcrite à propos de sigles du numérique en santé (INS, DNS), un modèle de 9B en a développé deux de travers et en a inventé un troisième, inexistant.
   - Un **glossaire et une règle « ne jamais inventer de sigle »** dans le prompt système ont réglé le problème : les définitions sont devenues justes, et sur un sigle inconnu le modèle **s'abstient** au lieu d'inventer.
   - Au-delà des sigles, pour le fond, utiliser une base documentaire (RAG) sur les documents de référence. La recherche elle-même est quasi instantanée ; le coût vient des tokens de prompt supplémentaires (~250 tok/s ici).
5. **Un réglage qui « marche » peut quand même être mauvais.** `-fa on` n'a jamais produit d'erreur, et pourtant il a fait tourner l'attention sur le CPU pendant des semaines (−28 %). Lire les avertissements du journal du serveur.
6. **Un banc d'essai répond à la question posée, dans les conditions fixées.** Une première comparaison vision plaçait ici Qwen loin devant Gemma. En la relisant, plusieurs biais sont apparus :
   - les images de Gemma avaient été plafonnées à la moitié du budget de Qwen par un réglage de lot ;
   - Gemma E4B était une version non QAT ;
   - tous les modèles utilisaient les mêmes réglages de génération, au lieu de ceux de chaque éditeur ;
   - le prompt avait été mis au point sur Qwen.

   Documenter les conditions, et se méfier d'un verdict tranché tiré d'un petit échantillon.
7. **Un bouton peut ne rien faire.** Les boutons « Recherche web » et « Image » d'Open WebUI étaient sans effet en appel de fonctions natif, sans aucune erreur. Vérifier ce qui s'est réellement exécuté (journaux, trafic vers le moteur de recherche), pas seulement que l'interface a accepté le clic.
8. **Sur un GPU partagé, réserver la part de l'affichage.** Le réglage le plus rapide du modèle de code 30B ne laissait que 0,3 Go de VRAM à macOS. Mesurer la VRAM libre, et garder au moins ce que laisse le modèle du quotidien.

## Désinstallation

```bash
~/.local/share/llm-local-intel-mac-amd/uninstall.sh            # services, binaires, conteneurs Open WebUI et SearXNG (conserve modèles, données, VM Colima)
~/.local/share/llm-local-intel-mac-amd/uninstall.sh --purge    # supprime aussi la VM Colima + outils Docker, les données d'Open WebUI et de SearXNG, et les modèles installés
```

## Licence

[MIT](LICENSE) pour les scripts et la documentation de ce dépôt. Les composants inclus et tiers gardent leurs propres licences :
- llama.cpp (MIT) et MoltenVK (Apache-2.0) : leurs textes de licence sont livrés dans `licenses/` à l'intérieur du paquet ;
- Ollama (MIT), Open WebUI (sa propre licence), faster-whisper (MIT) ;
- les modèles (Qwen 3.5 et Gemma 4 : Apache-2.0).
