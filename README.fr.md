# LLM local sur Mac Intel avec GPU AMD (Vulkan / MoltenVK)

🇬🇧 [English version](README.md)

Faire tourner une pile d'IA générative **100 % locale** (modèle de langage, interface de chat et dictée vocale) sur un **Mac Intel équipé d'une Radeon AMD**, en exploitant le GPU. Aucune donnée ne sort de la machine, et rien n'écoute en dehors de `127.0.0.1`.

Ollama et la plupart des outils « clé en main » **ignorent les GPU AMD sur Mac Intel** et tournent uniquement sur le CPU. Ce dépôt documente une voie qui fonctionne : **llama.cpp avec son moteur Vulkan au-dessus de MoltenVK**, compilé sans Xcode ni Homebrew.

> Testé sur une seule machine (voir ci-dessous). C'est un retour d'expérience avec scripts, pas un produit maintenu. Mesurez sur votre propre matériel.

## Machine de test

| | |
|---|---|
| Machine | iMac 27" (2020), macOS 26 (Tahoe), Intel x86_64 |
| CPU | Intel Core i7-10700K (8 cœurs / 16 threads, AVX2) |
| RAM | 128 Go DDR4-2667 |
| GPU | AMD Radeon Pro 5700 XT, 16 Go de VRAM |
| Logiciels | llama.cpp (Vulkan), MoltenVK 1.4.2, Ollama 0.40, Open WebUI 0.7, faster-whisper 1.2 |

## Résultats (Qwen 3.5 9B, Q4_K_M)

| Moteur | Lecture du prompt | Génération |
|---|---:|---:|
| **Vulkan / MoltenVK sur la Radeon** | **~270-286 tok/s** | **~31-35 tok/s** |
| CPU seul (8 threads) | 28 tok/s | 4,7 tok/s |

Une réponse courte arrive en **environ 1 s**.

## Ce qui n'a *pas* marché (inutile de réessayer)

| Piste | Résultat |
|---|---|
| Ollama sur Mac Intel | CPU uniquement : la build x86_64 n'a aucun moteur GPU (Metal/MLX sont réservés à ARM) |
| Moteur **Metal** de llama.cpp sur la Radeon | `kIOAccelCommandBufferCallbackErrorTimeout` : ses kernels visent Apple Silicon |
| Homebrew pour la chaîne Vulkan | pas de paquets précompilés x86_64 sous macOS récent : tout est recompilé depuis les sources (des heures) |
| **llama.cpp Vulkan + MoltenVK** | ✅ fonctionne, 6 à 10 fois plus rapide que le CPU |

## Architecture

```
Navigateur ──► Open WebUI 127.0.0.1:3000
                 ├─► llama-server 127.0.0.1:8080 ─ Vulkan ─► MoltenVK ─► Metal ─► Radeon
                 ├─► Ollama       127.0.0.1:11434 (CPU, optionnel : gestion des modèles)
                 └─► Whisper STT  127.0.0.1:8092  (CPU, dictée)
```

Chaque service est un **LaunchAgent** utilisateur (`launchd/`, avec `RunAtLoad` et `KeepAlive`).

## Installation

```bash
# 1. Compiler llama.cpp (Vulkan) — ~10-15 min, sans Xcode (Command Line Tools suffisent)
scripts/build-llama-vulkan.sh

# 2. Ollama (binaire officiel universel), utilisé ici pour télécharger les modèles
mkdir -p ~/.local/share/ollama-bin && cd ~/.local/share/ollama-bin
curl -fsSL -o o.tgz https://github.com/ollama/ollama/releases/latest/download/ollama-darwin.tgz && tar xzf o.tgz && rm o.tgz
cd -

# 3. Open WebUI (via uv)
uv tool install --python 3.11 open-webui

# 4. Un modèle : le télécharger avec Ollama, puis créer un lien physique vers le GGUF pour llama.cpp
#    (ou télécharger n'importe quel GGUF depuis Hugging Face dans ~/models/)
mkdir -p ~/models   # et pointer -m de launchd/com.llamacpp.vulkan.plist vers votre fichier

# 5. Installer et démarrer tous les services
scripts/install-services.sh
scripts/healthcheck.sh
```

Ouvrir ensuite `http://localhost:3000`. Le premier compte créé devient administrateur.

## Les réglages qui comptent

1. **CPU à ~670 % alors que le modèle est à 100 % sur le GPU.**
   - Cause : les threads de llama.cpp attendent le GPU en boucle (`--poll 50` par défaut).
   - Correctif : `-t 2 -tb 2 --poll 0`. Le CPU tombe à ~50 %, et la génération accélère même (23,5 → 34,7 tok/s avec `llama-bench`).
2. **Les modèles « à réflexion » (Qwen 3.5) écrivent des romans.**
   - Ne pas utiliser `--reasoning-budget 0` : ce réglage coupe la réflexion pour tout le serveur, sans possibilité de la réactiver requête par requête.
   - À la place, la couper par défaut avec `--chat-template-kwargs '{"enable_thinking":false}'`, et l'activer à la demande avec `chat_template_kwargs: {"enable_thinking": true}`.
   - Plafonner le brouillon avec `reasoning_budget_tokens` (accepté par requête). Sur 4 questions de logique à réponse connue :

   | Plafond | Justes | Temps moyen / question |
   |---|---:|---:|
   | 512 | 3/4 | ~32 s |
   | **1 024** | **4/4** | **~53 s** |
   | 2 048 | 4/4 | ~110 s |
   | aucun | — | > 2 min |

   Dans Open WebUI, créer deux modèles sur la même base (« rapide » et « réflexion ») avec ces paramètres personnalisés.
3. **Les tâches de fond d'Open WebUI** (titres, tags, suggestions) utilisent par défaut le modèle de la conversation.
   - En mode réflexion, chacune lance son propre long brouillon en parallèle de la réponse, et le GPU est partagé.
   - Correctif : Réglages admin → Interface → Modèle de tâche = le modèle « rapide ».
4. **C'est la bande passante mémoire qui fixe la vitesse, pas la taille du modèle.**
   - Chaque mot généré relit tous les poids actifs.
   - Débit VRAM effectif mesuré via MoltenVK : ~180 Go/s, environ la moitié du débit théorique.
   - La RAM est environ 6 fois plus lente : les gros modèles MoE « tiennent » dans 128 Go, mais tourneraient à environ 5-8 tok/s (estimation). **Choisir un modèle qui tient entièrement en VRAM.**
5. **Vision** : Qwen 3.5 9B est multimodal. Lui passer son module vision avec `--mmproj <fichier>` (≈0,9 Go de VRAM).
   - Certaines opérations du module vision basculent sur le CPU avec Vulkan, mais ça fonctionne.

## Dictée vocale

Le Whisper intégré à Open WebUI **fait planter tout le processus (SIGSEGV) à la première transcription** sur Mac Intel.
- Cause : `ctranslate2` charge `libiomp5` et PyTorch charge `libomp`. Deux runtimes OpenMP se retrouvent dans le même processus.
- Correctif : [`stt/whisper_server.py`](stt/whisper_server.py) fait tourner faster-whisper **dans son propre processus**, avec une API compatible OpenAI (`/v1/audio/transcriptions`).
- Dans Open WebUI : Réglages admin → Audio → moteur STT « OpenAI », URL `http://127.0.0.1:8092/v1`, modèle `large-v3-turbo`.

Comparaison sur une vraie dictée, en français et avec du jargon métier :

| | `small` | `large-v3-turbo` |
|---|---|---|
| Temps (12-19 s d'audio, CPU) | ~2,3 s | ~6 s |
| Erreurs | « pourgogne froche comptée » pour « Bourgogne-Franche-Comté » | aucune, hors un sigle inconnu |

Les sigles métier sont gérés par deux fichiers placés à côté du serveur, tous deux optionnels et faciles à enrichir :
- `stt/lexique.txt` : vocabulaire transmis à Whisper comme lexique de départ ;
- `stt/corrections.tsv` : corrections par expressions régulières, appliquées après la transcription.

**Remarque** : le navigateur intégré de l'app de bureau Claude bloque le micro. Utilisez Safari ou Chrome sur `http://localhost:3000`.

## Leçon : les petits modèles inventent les sigles

Sur une phrase parfaitement transcrite à propos de l'INS et de la DNS, un modèle de 9B a donné des développements faux, avec aplomb, et a même inventé un sigle inexistant. Les petits modèles locaux maîtrisent bien la langue, mais mal les connaissances de niche.

Un **glossaire officiel et une règle « ne jamais inventer » dans le prompt système** ont réglé le problème :
- les définitions sont justes ;
- le modèle **s'abstient** sur un sigle inconnu au lieu d'inventer.

Exemple pour le numérique en santé : [`open-webui/system-prompt-sante-fr.md`](open-webui/system-prompt-sante-fr.md). Pour des réponses factuelles sur le fond, l'étape suivante est une base documentaire (RAG) sur les documents de référence.

## Contenu du dépôt

```
scripts/build-llama-vulkan.sh   MoltenVK + shaderc + llama.cpp (Vulkan), installation relocalisable
scripts/install-services.sh     installation/réinstallation des LaunchAgents (conserve WEBUI_SECRET_KEY)
scripts/healthcheck.sh          état des services + test GPU
launchd/*.plist                 modèles de LaunchAgents (marqueurs __HOME__, __REPO__, secret)
stt/                            service de dictée Whisper + lexique + corrections
open-webui/                     exemple de prompt système (glossaire)
```

## Licence

[MIT](LICENSE). Les composants tiers (llama.cpp, MoltenVK, Ollama, Open WebUI, Whisper, les modèles) gardent leurs propres licences.
