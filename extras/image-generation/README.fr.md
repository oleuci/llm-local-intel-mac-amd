# Génération d'images (optionnelle, testée puis désinstallée)

🇬🇧 [English version](README.md)

> **Statut :** testée et mesurée sur l'iMac de référence (Radeon Pro 5700 XT, 16 Go) en novembre 2026, intégrée à Open WebUI, puis **désinstallée par choix** : les services d'images en ligne sont bien meilleurs, et cette carte graphique est plus utile au LLM. Tout est conservé ici pour la **réinstaller si besoin**. `install.sh` n'installe rien de tout cela.

## Ce qui marche

**[stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)** repose sur la même base ggml et le même **backend Vulkan sur MoltenVK** que llama.cpp, donc il tourne sur la Radeon. Il se compile en 2-3 min avec la chaîne d'outils de `scripts/build-llama-vulkan.sh` :

```bash
scripts/build-llama-vulkan.sh                      # si ce n'est pas déjà fait : MoltenVK, shaderc, en-têtes
extras/image-generation/build-sd-vulkan.sh         # -> ~/.local/share/sd-vk/{sd-server,sd-cli}
```

Les outils basés sur PyTorch (ComfyUI, AUTOMATIC1111) sont une impasse sur Mac Intel, pour la même raison qu'Open WebUI en natif : PyTorch s'y arrête à la version 2.2.2. Dans Docker, la VM Colima n'a pas accès au GPU.

## Mesures

| Modèle | Taille | 512×512 | 1024×1024 | Qualité |
|---|---|---|---|---|
| SDXL-Turbo fp16, 4 étapes | 6,9 Go | 28-30 s (17 s de calcul + 9 s de décodage) | — | correcte, mais écorche le texte (« BOUANGERE ») |
| SDXL-Turbo + décodeur rapide **TAESD** | +10 Mo | **~19 s** (décodage 9 s → 0,8 s) | — | quasi identique |
| **Z-Image-Turbo** Q4_K, 8 étapes | 6,4 Go (DiT 3,9 + encodeur texte Qwen3-4B 2,5 + VAE Flux 0,3) | ~65 s | **~4 min 30** (229 s de calcul + 42 s de décodage) | **nettement meilleure** : rendu photo, texte exact dans l'image, consigne respectée |

En 768×768, Z-Image prend environ 2 min 20. Le temps augmente un peu plus vite que le nombre de pixels.

Constats :
- **La limite est le calcul, pas la VRAM.** Sur MoltenVK, la flash attention et la convolution directe sont indisponibles ici (`probe output check failed`). La 5700 XT n'a pas de cœurs matriciels, donc une étape en 512 px prend environ 4,3 s avec SDXL.
- **Décharger le LLM n'aide pas** SDXL-Turbo ni Z-Image Q4 : ils tiennent à côté de lui, et la vitesse était identique. Recharger le LLM ensuite prend environ 3 s.
- **`--offload-to-cpu`** garde les poids en RAM et ne les monte sur la carte graphique que pendant une génération. Coût mesuré : nul (66 s dans les deux cas). Le LLM tournait encore à 31 tok/s juste après une image.
- La génération occupe la carte graphique par longs blocs : **l'affichage de macOS peut saccader pendant une génération**.

## Réinstaller (Z-Image-Turbo + Open WebUI)

```bash
mkdir -p ~/models/sd && cd ~/models/sd
curl -fLO https://huggingface.co/leejet/Z-Image-Turbo-GGUF/resolve/main/z_image_turbo-Q4_K.gguf
curl -fLO https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf
# VAE Flux : le dépôt de black-forest-labs exige une acceptation ; Comfy-Org redistribue le même fichier
curl -fL -o flux_ae.safetensors https://huggingface.co/Comfy-Org/z_image_turbo/resolve/main/split_files/vae/ae.safetensors

sed "s#__HOME__#$HOME#g" ~/.local/share/llm-local-intel-mac-amd/extras/image-generation/com.sdcpp.server.plist \
  > ~/Library/LaunchAgents/com.sdcpp.server.plist
mkdir -p ~/Library/Logs/sd-server && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.sdcpp.server.plist
```

Dans Open WebUI (Administration → Réglages → Images) :
- moteur **Automatic1111**, URL `http://host.docker.internal:8093` ;
- taille `1024x1024` (ou `512x512` pour environ 1 min), étapes `8` ;
- dans les paramètres Automatic1111, indiquer `{"cfg_scale": 1.0}`.

Ensuite, dans une conversation : **+** → **Image** → décrire l'image voulue.

Pièges d'Open WebUI (0.13) :
- **Le bouton « Image » ne fait rien quand les outils intégrés sont coupés.** Il ne force la génération qu'en mode d'appel de fonctions **legacy** ; en mode natif, c'est au modèle d'appeler l'outil intégré `generate_image`. Mettre l'appel de fonctions du modèle sur **Legacy**, ce qui évite quand même d'injecter les ~7 900 tokens des outils intégrés à chaque requête.
- **Pas de délai d'attente à craindre.** Open WebUI ne fixe aucune limite tant que `AIOHTTP_CLIENT_TIMEOUT` n'est pas défini, donc une génération de 4-5 min passe.
- **Ne jamais modifier `webui.db` depuis le Mac pendant que le conteneur tourne.** Les fichiers WAL et de mémoire partagée de SQLite ne supportent pas un accès simultané à travers virtiofs, et Open WebUI se met à renvoyer `disk I/O error`. Arrêter le conteneur, modifier, le redémarrer. Mieux encore : passer par l'interface d'administration.

## Autres modèles

stable-diffusion.cpp gère aussi **Qwen-Image** (voir son `docs/qwen_image.md`), Flux, SD 3.5, etc. Qwen-Image est un modèle bien plus gros (20B) : sur cette carte, il dépendrait de `--offload-to-cpu` et serait lent. Il n'a **pas été testé ici**.

## Désinstaller

```bash
launchctl bootout gui/$(id -u)/com.sdcpp.server; rm ~/Library/LaunchAgents/com.sdcpp.server.plist
rm -rf ~/.local/share/sd-vk ~/models/sd ~/Library/Logs/sd-server
```

Puis désactiver la génération d'images dans Open WebUI, et remettre l'appel de fonctions par défaut si vous l'aviez changé.
