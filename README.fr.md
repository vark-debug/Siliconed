[English](README.md) · [Français](README.fr.md) · 简体中文

# Siliconed (édition communautaire)

**Ceci est un fork communautaire. Le projet original est l'œuvre de Gwenn ([gwenn-ha-dev](https://github.com/gwenn-ha-dev)) : [gwenn-ha-dev/Siliconed](https://github.com/gwenn-ha-dev/Siliconed) — à lui seul le mérite, et merci pour ce travail remarquable.**

L'app originale fait tourner nativement, en Swift et Metal, de récents modèles à poids ouverts sur les Mac Apple silicon (M1 et plus) — [Krea 2 Turbo](https://huggingface.co/krea/Krea-2-Turbo), [Z-Image Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo), [Qwen-Image-2.1 Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo), [Anima Turbo](https://huggingface.co/circlestone-labs/Anima) et [MOSS-Image](https://huggingface.co/OpenMOSS-Team/MOSS-Image-SFT) — sans Python, sans cloud, sans qu'une donnée quitte le Mac, chaque étage vérifié canal par canal contre des implémentations de référence. La documentation de l'app originale vit dans son dépôt et ici même, dans [docs/](docs/).

Ce dépôt continue depuis l'original (version 0.20) ; tout ce qui y est ajouté est ouvert sous la même [licence Apache 2.0](LICENSE) — les mentions de copyright et de licence originales sont conservées telles quelles, et le travail de ce fork est offert sous la même licence.

## Ce que fait ce fork

### 1. Les workflows de Qwen-Image-2.1, nœud par nœud contre ComfyUI

- **Retirer et repeindre (redraw)** : le recadrage du masque, le remplissage vert ou le remplacement dicté par le prompt, le recollage en fondu — table des σ et 9 étapes ManualSigmas, résolution de référence, départ du recadrage : tout équivalent au workflow « Qwen-Image-2.1 remove/redraw » de ComfyUI ([docs](docs/MASK-WORKFLOW.md)).
- **Étendre l'image (outpainting)** : le canevas grandit d'un pourcentage de chaque côté, rempli de gris, échantillonné aux tailles arrondies au 32 le plus proche, recollé comme le fait GH_CropRestore — équivalent au workflow « Qwen Image 2.1 expand » de ComfyUI, sans étirement ni traînée de bord ([docs](docs/EXPAND-WORKFLOW.md)).
- **Les LoRA préréglées des workflows** : remove (1.0), redraw (0.48), expand (0.7) — la série communautaire qwen2-1-gh de Civitai, câblée d'elle-même selon la branche.
- **Le rideau de comparaison** : l'original et le résultat sous un rideau coulissant, les zones vides de l'extension montrées en damier.

### 2. L'agrandissement SeedVR2

Un portage Swift/MLX de SeedVR2 : ×N le raffinement d'une image, 1:1. Dans l'app (avec une fenêtre et un miroir sur un autre Mac), et depuis le CLI directement sur un fichier, sans l'app.

### 3. Les sources de téléchargement (accessibles depuis la Chine)

Les fichiers des modèles viennent de huggingface.co ; quand il est inaccessible, l'app interroge d'elle-même ModelScope (魔搭) et le miroir hf-mirror.com — ou vous choisissez la source dans le panneau Modèles, verrouillée pendant une installation. Quelle que soit la source, chaque fichier est vérifié contre le sha256 épinglé de sa recette ([docs](docs/HUB-SOURCES.md)).

### 4. Les nouvelles capacités exposées au CLI (`silicontrol`)

Le `silicontrol` de l'originale pilote déjà les rendus depuis un terminal ([docs](docs/REMOTE-CONTROL.md)) ; ce fork lui expose les nouvelles branches d'édition :

- `add --mask MASQUE --mode remove|redraw` — retirer et repeindre ;
- `add --lora expand --pad G,D,H,B --image IMAGE` — étendre (la préréglée 0.7 câblée, un masque refusé) ;
- `upscale FICHIER [DEST] [--scale N]` — SeedVR2 sur un fichier, sans l'app.

## Téléchargement

L'originale est distribuée en `.dmg` sur la page [Releases](https://github.com/gwenn-ha-dev/Siliconed/releases) de l'amont ; le travail de ce fork se construit depuis les sources pour l'instant ([Construire depuis les sources](docs/ENGINE.fr.md#construire-depuis-les-sources), Xcode 26 ou plus). Prérequis : macOS 26 ou plus, Apple silicon. Rien n'est préinstallé : vous choisissez les modèles depuis l'app, vous lisez chaque licence, et c'est seulement ensuite qu'un octet se télécharge.

## Ce que fait l'app originale (en bref)

- **Dessine à partir de texte, retouche sur instruction** ; **bracketing en grille** (une image finie par case) ; **l'Atelier de prompts** (prompts réécrits au style de chaque modèle, images décrites — bêta) ; **vos propres modèles** (LoRA et fine-tunes de Civitai / Hugging Face) ; **local et privé** (aucun filtre de contenu, aucun historique ne quitte la machine) ; **calcule sur un autre Mac** (appairé une fois, chiffré) ; **scriptable** (`silicontrol`). La visite de l'app : [docs/APP.fr.md](docs/APP.fr.md).

![La fenêtre de Siliconed : le rack à gauche (texte, encodeur de texte, DiT, décodeur VAE, chacun avec ses réglages et son temps), la photo de surf de Krea 2 Turbo au centre, l'Atelier de prompt replié en une ligne dessous, l'historique à droite](docs/images/window.jpg)

## Documentation

Les docs du projet original (continuées ici) :

- [docs/APP.fr.md](docs/APP.fr.md) — l'app ; [docs/ENGINE.fr.md](docs/ENGINE.fr.md) — le moteur, les chiffres, le budget mémoire ; [docs/VERIFY.fr.md](docs/VERIFY.fr.md) — vérifier sur votre Mac ; [docs/REMOTE-CONTROL.fr.md](docs/REMOTE-CONTROL.fr.md) — `silicontrol` et le protocole ; [docs/RELEASE-NOTES.fr.md](docs/RELEASE-NOTES.fr.md) — ce que chaque version change.

Les ajouts de ce fork :

- [docs/MASK-WORKFLOW.md](docs/MASK-WORKFLOW.md) — le workflow retirer/repeindre lu dans ses sources ; [docs/EXPAND-WORKFLOW.md](docs/EXPAND-WORKFLOW.md) — le workflow d'extension ; [docs/HUB-SOURCES.md](docs/HUB-SOURCES.md) — les sources de téléchargement.

## Remerciements

Siliconed a été créé par Gwenn — tout ce que ce fork ajoute se tient sur ces fondations. Les modèles appartiennent à leurs éditeurs, chacun sous sa licence ; les implémentations de référence sont [diffusers](https://github.com/huggingface/diffusers) et [transformers](https://github.com/huggingface/transformers) de Hugging Face, et le rééchantillonnage d'image reproduit au bit près le Lanczos de [Pillow](https://github.com/python-pillow/Pillow). L'alignement retirer/repeindre/étendre prend pour référence les nœuds de workflow ComfyUI de Goohai (孤海) ; les LoRA des workflows viennent de la communauté Civitai ; la recette 8 étapes de MOSS-Image vient de la [DMD LoRA](https://huggingface.co/lodestones/MOSS-Image-SFT-8-steps-dmd) de lodestones ; l'agrandisseur s'appuie sur SeedVR2 (l'équipe Seed de ByteDance).

## Licence

Le code est sous [licence Apache 2.0](LICENSE) : le projet original appartient à son auteur Gwenn, les changements de ce fork sont offerts sous la même licence, et les mentions de copyright et de licence originales sont préservées. Les poids des modèles ne font pas partie de ce dépôt : vous téléchargez chaque modèle vous-même, sous sa propre licence, montrée par l'app avant l'installation.
