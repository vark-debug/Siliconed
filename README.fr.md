[English](README.md) · Français · [简体中文](README.zh.md)

# Siliconed (édition communautaire)

**Ceci est un fork communautaire. Le projet original est l'œuvre de Gwenn ([gwenn-ha-dev](https://github.com/gwenn-ha-dev)) : [gwenn-ha-dev/Siliconed](https://github.com/gwenn-ha-dev/Siliconed) — à lui seul le mérite, et merci pour ce travail remarquable.**

L'app originale fait tourner nativement, en Swift et Metal, de récents modèles à poids ouverts sur les Mac Apple silicon (M1 et plus) — [Krea 2 Turbo](https://huggingface.co/krea/Krea-2-Turbo), [Z-Image Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo), [Qwen-Image-2.1 Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo), [Anima Turbo](https://huggingface.co/circlestone-labs/Anima) et [MOSS-Image](https://huggingface.co/OpenMOSS-Team/MOSS-Image-SFT) — sans Python, sans cloud, sans qu'une donnée quitte le Mac, chaque étage vérifié canal par canal contre des implémentations de référence. La documentation de l'app originale vit dans son dépôt et ici même, dans [docs/](docs/).

Ce dépôt continue depuis l'original (version 0.20) ; tout ce qui y est ajouté est ouvert sous la même [licence Apache 2.0](LICENSE) — les mentions de copyright et de licence originales sont conservées telles quelles, et le travail de ce fork est offert sous la même licence.

## Photoshop pour toile : le plugin rocxps

**Le but de ce fork** : Siliconed comme outil de génération externe de Photoshop. Le côté Photoshop est [rocxps](https://github.com/vark-debug/rocxps) — un panneau UXP (Photoshop 24.2+) : vous cernez une sélection, le panneau la capture avec un masque aligné au 32, et le Siliconed local — ou un Mac appairé — fait le rendu, par le même `silicontrol` que le terminal. Le résultat est recollé sur le canevas à sa taille exacte : un remplacement entier, un masque de calque, ou un masque de pixels.

- **Un prompt vide, ou « forcer le retrait », enlève le contenu de la sélection** ; une phrase le repeint — la branche se lit dans le prompt, dans le panneau comme dans l'app.
- **La file du panneau** se persiste sur disque, se suspend et reprend, réessaie une tâche ; le recollage est automatique, ou d'un clic quand vous voulez d'abord regarder.
- Le même panneau parle aussi à Volcengine (Seedream), RunningHub et IOPaint ; Siliconed en est le backend local et privé.

## Ce que fait ce fork

### 1. Les workflows de Qwen-Image-2.1, nœud par nœud contre ComfyUI

- **Retirer et repeindre (redraw)** : le recadrage du masque, le remplissage vert ou le remplacement dicté par le prompt, le recollage en fondu — table des σ et 9 étapes ManualSigmas, résolution de référence, départ du recadrage : tout équivalent au workflow « Qwen-Image-2.1 remove/redraw » de ComfyUI ([docs](docs/MASK-WORKFLOW.md)).
- **Étendre l'image (outpainting)** : le canevas grandit d'un pourcentage de chaque côté, rempli de gris, échantillonné aux tailles arrondies au 32 le plus proche, recollé comme le fait GH_CropRestore — équivalent au workflow « Qwen Image 2.1 expand » de ComfyUI, sans étirement ni traînée de bord ([docs](docs/EXPAND-WORKFLOW.md)).
- **Les LoRA préréglées des workflows** : remove (1.0), redraw (0.48), expand (0.7) — la série qwen2-1-gh de Goohai, partagée sur Bilibili, câblée d'elle-même selon la branche.
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

Le plugin [rocxps](https://github.com/vark-debug/rocxps) pilote l'app par ces commandes.

## La vitesse, face aux workflows ComfyUI

Sur le même Apple M1 Ultra (64 Go), la même image, la même tâche, les paramètres propres au workflow (9 étapes ManualSigmas), graines aléatoires, plusieurs tours chronométrés :

| Mesure | Workflow ComfyUI | Siliconed | Écart |
|---|---|---|---|
| Retrait · démarrage à froid | 155,94 s | **45–49 s** | ~3,2× plus vite |
| Retrait · à chaud | 61,02 s | **34,62 s** | ~1,76× plus vite |
| Extension · démarrage à froid | ~267 s | **153,1 s** | ~1,7× plus vite |
| Extension · à chaud | 225,98 s | **128,09 s** | ~1,76× plus vite |

La qualité, comparée côte à côte : les reconstructions du retrait et de l'extension sont équivalentes. [Méthode, détails, reproduction](docs/SPEED-COMPARISON.md).

## Téléchargement

L'originale est distribuée en `.dmg` sur la page [Releases](https://github.com/gwenn-ha-dev/Siliconed/releases) de l'amont ; ce fork publie ses propres [Releases](https://github.com/vark-debug/Siliconed/releases) — à partir de 0.21 — et se construit aussi depuis les sources ([Construire depuis les sources](docs/ENGINE.fr.md#construire-depuis-les-sources), Xcode 26 ou plus). Prérequis : macOS 26 ou plus, Apple silicon. Rien n'est préinstallé : vous choisissez les modèles depuis l'app, vous lisez chaque licence, et c'est seulement ensuite qu'un octet se télécharge.

## Ce que fait l'app originale (en bref)

- **Dessine à partir de texte, retouche sur instruction** ; **bracketing en grille** (une image finie par case) ; **l'Atelier de prompts** (prompts réécrits au style de chaque modèle, images décrites — bêta) ; **vos propres modèles** (LoRA et fine-tunes de Civitai / Hugging Face) ; **local et privé** (aucun filtre de contenu, aucun historique ne quitte la machine) ; **calcule sur un autre Mac** (appairé une fois, chiffré) ; **scriptable** (`silicontrol`). La visite de l'app : [docs/APP.fr.md](docs/APP.fr.md).

![La fenêtre de Siliconed : le rack à gauche (texte, encodeur de texte, DiT, décodeur VAE, chacun avec ses réglages et son temps), la photo de surf de Krea 2 Turbo au centre, l'Atelier de prompt replié en une ligne dessous, l'historique à droite](docs/images/window.jpg)

## Documentation

Les docs du projet original (continuées ici) :

- [docs/APP.fr.md](docs/APP.fr.md) — l'app ; [docs/ENGINE.fr.md](docs/ENGINE.fr.md) — le moteur, les chiffres, le budget mémoire ; [docs/VERIFY.fr.md](docs/VERIFY.fr.md) — vérifier sur votre Mac ; [docs/REMOTE-CONTROL.fr.md](docs/REMOTE-CONTROL.fr.md) — `silicontrol` et le protocole ; [docs/RELEASE-NOTES.fr.md](docs/RELEASE-NOTES.fr.md) — ce que chaque version change.

Les ajouts de ce fork :

- [docs/MASK-WORKFLOW.md](docs/MASK-WORKFLOW.md) — le workflow retirer/repeindre lu dans ses sources ; [docs/EXPAND-WORKFLOW.md](docs/EXPAND-WORKFLOW.md) — le workflow d'extension ; [docs/HUB-SOURCES.md](docs/HUB-SOURCES.md) — les sources de téléchargement.

## Remerciements

Siliconed a été créé par Gwenn — tout ce que ce fork ajoute se tient sur ces fondations. Les modèles appartiennent à leurs éditeurs, chacun sous sa licence ; les implémentations de référence sont [diffusers](https://github.com/huggingface/diffusers) et [transformers](https://github.com/huggingface/transformers) de Hugging Face, et le rééchantillonnage d'image reproduit au bit près le Lanczos de [Pillow](https://github.com/python-pillow/Pillow). L'alignement retirer/repeindre/étendre de Qwen-Image-2.1 doit un merci tout particulier à Goohai ([Goohaitools-comfyui](https://github.com/goohai/Goohaitools-comfyui)) pour l'ouverture des workflows ComfyUI « Qwen-2.1 remove, redraw, expand » — les implémentations de référence d'où ce projet a été lu ; les LoRA des workflows sont de Goohai, partagées sur Bilibili ; la recette 8 étapes de MOSS-Image vient de la [DMD LoRA](https://huggingface.co/lodestones/MOSS-Image-SFT-8-steps-dmd) de lodestones ; l'agrandisseur s'appuie sur SeedVR2 (l'équipe Seed de ByteDance).

## Licence

Le code est sous [licence Apache 2.0](LICENSE) : le projet original appartient à son auteur Gwenn, les changements de ce fork sont offerts sous la même licence, et les mentions de copyright et de licence originales sont préservées. Les poids des modèles ne font pas partie de ce dépôt : vous téléchargez chaque modèle vous-même, sous sa propre licence, montrée par l'app avant l'installation.
