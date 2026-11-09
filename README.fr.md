# LLM local sur Mac Intel avec GPU AMD (llama.cpp · Vulkan · MoltenVK)

🇬🇧 [English version](README.md)

Faire tourner une pile d'IA générative **100 % locale** (modèle de langage, interface de chat, dictée vocale) sur un **Mac Intel équipé d'une Radeon AMD**, en exploitant vraiment le GPU. Aucune donnée ne sort de la machine, et rien n'écoute en dehors de `127.0.0.1`.

Ollama, LM Studio et la plupart des outils « clé en main » **ignorent les GPU AMD sur Mac Intel** : ils n'utilisent que le CPU. Ce dépôt fournit une voie qui fonctionne, **le moteur Vulkan de llama.cpp au-dessus de MoltenVK**. Il se présente sous deux formes :
- un **paquet précompilé et relocalisable**, avec un installeur en une ligne ;
- des **scripts pour tout compiler soi-même**, sans Xcode ni Homebrew.

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
10. [Configurer Open WebUI](#configurer-open-webui)
11. [Dictée vocale](#dictée-vocale)
12. [Dépannage](#dépannage)
13. [Enseignements](#enseignements)
14. [Désinstallation](#désinstallation) · [Licence](#licence)

---

## Résultats

Machine de test : **iMac 27" (2020)**, macOS 26.6, Intel Core i7-10700K (8 cœurs / 16 threads, AVX2), 128 Go de DDR4-2667, **AMD Radeon Pro 5700 XT, 16 Go de GDDR6**.

Mesures faites avec `llama-bench` sur Qwen 3.5 9B, Q4_K_M (5,2 Go) :

| Moteur | Lecture du prompt (pp512) | Génération (tg128) |
|---|---:|---:|
| **Vulkan / MoltenVK, Radeon Pro 5700 XT** | **~270-286 tok/s** | **~30-35 tok/s** |
| CPU seul, 8 threads (AVX2) | 28 tok/s | 4,7 tok/s |

Une réponse courte commence à s'afficher en **~1 s**. La description d'une image (module vision chargé) prend **~5 s**.

## Installation rapide

Prérequis : un Mac Intel sous macOS **12 ou plus récent**, un GPU AMD compatible Metal et **~10 Go** d'espace disque libre. Aucun `sudo` n'est nécessaire.

**GPU testé :** uniquement la Radeon Pro 5700 XT (Navi 10, 16 Go). Les autres GPU AMD pris en charge par MoltenVK (Polaris RX 5xx, Vega, autres cartes Navi) *devraient* fonctionner, mais ils ne sont **pas testés**. La VRAM limite la taille du modèle : avec une carte de 8 Go, prendre des modèles plus petits (≤ 4-7B). Les retours sont bienvenus.

```bash
# Serveur LLM seul (llama.cpp Vulkan + Qwen 3.5 9B + vision), en service d'arrière-plan
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash

# Pile complète : + Open WebUI (chat sur http://localhost:3000) + service de dictée
curl -fsSL https://raw.githubusercontent.com/oleuci/llm-local-intel-mac-amd/main/install.sh | bash -s -- --full
```

Ce que fait l'installeur, étape par étape (lisez [`install.sh`](install.sh) avant de le lancer) :
1. Il vérifie que le Mac tourne sous macOS ≥ 12, est en x86_64, et dispose d'un GPU AMD et d'assez d'espace disque.
2. Il télécharge le **paquet llama.cpp Vulkan précompilé** depuis les Releases GitHub de ce dépôt, **vérifie son empreinte SHA-256**, puis l'installe dans `~/.local/share/llama-vk/`.
3. Il lance `llama-server --list-devices` pour confirmer que le GPU est bien visible via Vulkan.
4. Il télécharge **Qwen 3.5 9B Q4_K_M** et son **module vision** depuis Hugging Face (`unsloth/Qwen3.5-9B-GGUF`, ~6,5 Go) dans `~/models/`.
5. Avec `--full`, il installe aussi **Open WebUI** via [uv](https://docs.astral.sh/uv/). Si uv est absent, il lance l'installeur officiel d'Astral.
   - Le **service de dictée Whisper** est alors installé lui aussi, puisqu'il réutilise le Python d'Open WebUI.
   - Son modèle (~1,5 Go) est téléchargé à la première utilisation.
   - Il reste à brancher Open WebUI dessus : voir [Dictée vocale](#dictée-vocale).
6. Il installe les **LaunchAgents** (des services qui démarrent avec la session et redémarrent s'ils plantent), puis fait un contrôle de santé.

Options : `--full`, `--no-model`, `--no-service`.

## Ce qui n'a *pas* marché (inutile de réessayer)

| Piste | Résultat | Pourquoi |
|---|---|---|
| Ollama sur Mac Intel | CPU uniquement (`inference compute … library=cpu`) | la build x86_64 ne contient que des moteurs CPU ; Metal et MLX ne sont présents que dans la partie arm64 |
| Moteur **Metal** de llama.cpp sur la Radeon | `kIOAccelCommandBufferCallbackErrorTimeout`, puis le moteur reste en erreur | ses kernels Metal reposent sur des fonctions propres aux GPU Apple (opérations matricielles simdgroup) |
| Homebrew pour Vulkan (`vulkan-loader`, `shaderc`, `glslang`…) | tout est recompilé depuis les sources, Python compris (des heures) | pas de paquets précompilés x86_64 pour les macOS récents |
| **llama.cpp Vulkan + MoltenVK** | ✅ **fonctionne, 6 à 10 fois plus rapide que le CPU** | MoltenVK traduit Vulkan vers Metal ; les kernels Vulkan génériques tournent bien sur AMD |

## Architecture

```
Navigateur ──► Open WebUI       127.0.0.1:3000   (optionnel, --full)
                 │
                 ├─► llama-server 127.0.0.1:8080  ── Vulkan ─► MoltenVK ─► Metal ─► Radeon
                 │      API compatible OpenAI /v1, texte + vision
                 │
                 ├─► Whisper STT  127.0.0.1:8092  (optionnel, CPU, dictée)
                 └─► Ollama       127.0.0.1:11434 (optionnel, CPU, gestion des modèles)
```

| LaunchAgent | Programme | Journaux |
|---|---|---|
| `com.llamacpp.vulkan` | `~/.local/share/llama-vk/bin/llama-server` | `~/Library/Logs/llama-vk/` |
| `com.openwebui.serve` | `~/.local/bin/open-webui` | `~/Library/Logs/open-webui/` |
| `com.whisper.stt` | `stt/whisper_server.py`, lancé avec le Python d'Open WebUI | `~/Library/Logs/whisper-stt/` |
| `com.ollama.serve` | `~/.local/share/ollama-bin/ollama` | `~/Library/Logs/ollama/` |

`scripts/install-services.sh` n'installe que les services dont le programme est présent. Les définitions des services sont des modèles dans [`launchd/`](launchd/), avec des marqueurs `__HOME__` et `__REPO__`.

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

Les options du service, dans [`launchd/com.llamacpp.vulkan.plist`](launchd/com.llamacpp.vulkan.plist) :

```
-ngl 99 -t 2 -tb 2 --poll 0 -c 32768 -fa on --jinja
--chat-template-kwargs '{"enable_thinking":false}'
--mmproj <module vision> --host 127.0.0.1 --port 8080
```

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

### 3. Pas de requêtes en parallèle sur ce GPU

Deux requêtes simultanées font tomber chacune à **~5 tok/s**, contre ~30 seule. Attention aux clients qui lancent des requêtes de fond : Open WebUI génère des titres, des tags et des suggestions ([voir plus bas](#configurer-open-webui)).

### 4. Chaleur

Une longue réflexion maintient la Radeon à 100 % pendant plusieurs minutes, et les ventilateurs montent nettement. Ils redescendent 1 à 2 min après la dernière requête.

## Choisir un modèle / dimensionner la VRAM

**Vitesse de génération ≈ débit mémoire effectif ÷ octets de poids actifs relus par token.**

- Débit VRAM théorique de la Pro 5700 XT : ~384-448 Go/s selon les sources. Débit effectif mesuré via MoltenVK : **~180 Go/s** (5,2 Go × 34,7 tok/s). La couche de traduction coûte environ la moitié.
- RAM : DDR4-2667 en double canal, ~43 Go/s théoriques, **~30 Go/s utiles**, environ 6 fois plus lente.

| Classe de modèle | Tient dans 16 Go de VRAM ? | Génération attendue |
|---|---|---|
| Dense ≤ 9B (Q4 ≈ 5-6 Go) | ✅ avec un grand contexte | ~30-35 tok/s (mesuré pour Qwen 3.5 9B) |
| Dense 12-14B (Q4 ≈ 7-9 Go) | ✅, le contexte devient plus serré | ~20 tok/s (estimation) |
| Dense ≥ 27B | ❌ déchargement partiel | lent |
| Gros MoE (100B+, ~5-6B actifs) avec experts en RAM (`--n-cpu-moe`) | poids en RAM | **~5-8 tok/s (estimation)** : traitements par lots seulement |

**Le cache KV compte autant que les poids :**
- **Qwen 3.5 est hybride** : une couche sur quatre seulement utilise l'attention complète (les autres apparaissent en `filtered` dans le journal). Un contexte de 32k coûte donc peu, et le cache de prompt est réutilisé d'un tour à l'autre.
- Les modèles **Gemma** utilisent une attention à fenêtre glissante. Le cache SWA compact par défaut tient en mémoire, mais llama.cpp doit alors relire tout l'historique à chaque tour (`forcing full prompt re-processing due to SWA`). `--swa-full` évite cela, mais coûte beaucoup plus de VRAM. Sur 16 Go, Gemma convient mieux aux échanges courts qu'aux longues conversations.

## Utiliser l'API

Le serveur est compatible OpenAI :

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "messages": [{"role": "user", "content": "Explique MoltenVK en une phrase."}],
  "max_tokens": 200 }'
```

La réponse contient `timings` (`prompt_per_second`, `predicted_per_second`). Autres points d'accès utiles :
- `GET /health` ;
- `GET /slots` : ce qui tourne en ce moment ;
- `GET /v1/models`.

Pour la vision, envoyer `content` sous forme de liste contenant `{"type":"image_url","image_url":{"url":"data:image/png;base64,…"}}`.

## Configurer Open WebUI

Ajouter llama-server comme connexion OpenAI (`--full` le fait via des variables d'environnement) : `OPENAI_API_BASE_URL=http://127.0.0.1:8080/v1`.

Puis configurer, dans cet ordre :
1. **Deux modèles sur la même base**, dans Espace de travail → Modèles → Nouveau :
   - **« rapide »** : Paramètres avancés → paramètre personnalisé `chat_template_kwargs` = `{"enable_thinking": false}` ;
   - **« réflexion »** : `chat_template_kwargs` = `{"enable_thinking": true}`, `reasoning_budget_tokens` = `1024`, `reasoning_budget_message` = `"\n\nJe dois maintenant conclure…\n"`.
2. **Modèle de tâche** : Réglages admin → Interface → Modèle de tâche = **« rapide »**. Sinon chaque génération de titre, de tags ou de suggestion lance elle aussi un long brouillon de réflexion, en parallèle de votre réponse.
3. **Modèle par défaut** = « rapide ». Réglages admin → Modèles.
4. Optionnel : un **prompt système avec un glossaire métier**. Voir [Enseignements](#enseignements) et [`open-webui/system-prompt-sante-fr.md`](open-webui/system-prompt-sante-fr.md).

## Dictée vocale

**Le Whisper intégré à Open WebUI fait planter tout le processus (SIGSEGV) à la première transcription sous macOS Intel.**
- Le rapport de plantage macOS montre `libiomp5.dylib __kmp_suspend_64` dans le thread fautif.
- `ctranslate2` (faster-whisper) charge `libiomp5` d'Intel, et PyTorch charge `libomp` de LLVM. Deux runtimes OpenMP dans le même processus finissent par planter.

Le correctif : [`stt/whisper_server.py`](stt/whisper_server.py) fait tourner faster-whisper **dans son propre processus** (sans PyTorch), avec une API compatible OpenAI (`POST /v1/audio/transcriptions`) sur `127.0.0.1:8092`.

Pour le brancher sur Open WebUI : Réglages admin → Audio → moteur STT **OpenAI**, URL `http://127.0.0.1:8092/v1`, une clé API quelconque, modèle `large-v3-turbo`.

Résultats sur une vraie dictée (en français, avec des sigles métier, sur le CPU pour laisser le GPU au LLM) :

| | `small` | **`large-v3-turbo`** |
|---|---|---|
| Temps pour 12-19 s d'audio | ~2,3 s | ~6 s |
| Erreurs | « pourgogne froche comptée » pour « Bourgogne-Franche-Comté », « cas d'ordre » pour « cadre » | aucune, hors un sigle inconnu |

Le vocabulaire métier est géré par deux fichiers placés à côté du serveur :
- [`stt/lexique.txt`](stt/lexique.txt) : transmis à Whisper comme `initial_prompt`. Efficace sur `small`, beaucoup moins sur turbo, dont le décodeur n'a que 4 couches.
- [`stt/corrections.tsv`](stt/corrections.tsv) : corrections déterministes par expressions régulières, appliquées après la transcription. La réponse contient aussi `raw_text`, la transcription avant correction, pour contrôle.

Après modification de l'un de ces fichiers, recharger le service : `launchctl kickstart -k gui/$(id -u)/com.whisper.stt`.

## Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `"llama-server" ne peut pas être ouvert` / tué au lancement | quarantaine Gatekeeper (archive téléchargée avec un navigateur) | `xattr -dr com.apple.quarantine ~/.local/share/llama-vk` |
| `--list-devices` n'affiche pas `Vulkan0` | MoltenVK introuvable, ou pas de GPU compatible Metal | `otool -L bin/libggml-vulkan.so` doit afficher `@rpath/libMoltenVK.dylib` ; vérifier `system_profiler SPDisplaysDataType` |
| `ggml_vulkan: WARNING: Instance extension VK_KHR_portability_enumeration not found` / `[mvk-warn] … robustness` | avertissements d'information de MoltenVK | sans conséquence |
| `Bootstrap failed: 5: Input/output error` en réinstallant un service | `launchctl bootout` est asynchrone | attendre que `launchctl print gui/$UID/<label>` échoue, puis relancer le bootstrap (`install-services.sh` le fait) |
| Réponse vide avec un petit `max_tokens` | le brouillon de réflexion a consommé tout le budget | réflexion coupée par défaut, et plafonnée avec `reasoning_budget_tokens` |
| Réponses très lentes, ~5 tok/s | requêtes simultanées (tâches de fond d'Open WebUI) | régler le modèle de tâche d'Open WebUI sur « rapide » ; vérifier `GET /slots` |
| CPU ~700 % pendant la génération | attente active en boucle | `-t 2 -tb 2 --poll 0` |
| Open WebUI redémarre quand on dicte | conflit OpenMP dans son Whisper intégré | utiliser le service de dictée séparé |
| Micro « refusé » dans un navigateur intégré | certains navigateurs intégrés bloquent `getUserMedia` | utiliser Safari ou Chrome sur `http://localhost:3000` (localhost est considéré comme sûr) |
| `warmup: the mmproj graph uses unsupported operators by the backend` | quelques opérations du module vision n'ont pas de kernel Vulkan | sans conséquence : ces opérations basculent sur le CPU, et les images fonctionnent (~5 s) |

Journaux : `~/Library/Logs/{llama-vk,open-webui,whisper-stt,ollama}/`. Contrôle de l'état : `~/.local/share/llm-local-intel-mac-amd/scripts/healthcheck.sh`.

## Enseignements

1. **Mesurer plutôt que supposer.** L'installation par défaut de chaque outil passait à côté du matériel réel : CPU seul, mauvaise version de macOS ciblée, dépendance cachée à Homebrew, threads en attente active.
2. **Le vrai goulot, c'est la bande passante mémoire.** Choisir un modèle qui tient entièrement en VRAM, en dimensionnant aussi son cache KV.
3. **Un petit modèle invente les faits métier avec aplomb.**
   - Sur une phrase parfaitement transcrite à propos de sigles du numérique en santé (INS, DNS), un modèle de 9B en a développé deux de travers et en a inventé un troisième, inexistant.
   - Un **glossaire et une règle « ne jamais inventer de sigle »** dans le prompt système ont réglé le problème : les définitions sont devenues justes, et sur un sigle inconnu le modèle **s'abstient** au lieu d'inventer.
   - Au-delà des sigles, pour le fond, utiliser une base documentaire (RAG) sur les documents de référence. La recherche elle-même est quasi instantanée ; le coût vient des tokens de prompt supplémentaires (~270 tok/s ici).

## Désinstallation

```bash
~/.local/share/llm-local-intel-mac-amd/uninstall.sh            # services + binaires (conserve les modèles et les données d'Open WebUI)
~/.local/share/llm-local-intel-mac-amd/uninstall.sh --purge    # supprime aussi Open WebUI, ses données et le modèle par défaut
```

## Licence

[MIT](LICENSE) pour les scripts et la documentation de ce dépôt. Les composants inclus et tiers gardent leurs propres licences :
- llama.cpp (MIT) et MoltenVK (Apache-2.0) : leurs textes de licence sont livrés dans `licenses/` à l'intérieur du paquet ;
- Ollama (MIT), Open WebUI (sa propre licence), faster-whisper (MIT) ;
- les modèles (Qwen 3.5 : Apache-2.0).
