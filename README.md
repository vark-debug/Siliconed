English · [Français](README.fr.md) · [简体中文](README.zh.md)

# Siliconed (community edition)

**This is a community fork. The original project is by Gwenn ([gwenn-ha-dev](https://github.com/gwenn-ha-dev)): [gwenn-ha-dev/Siliconed](https://github.com/gwenn-ha-dev/Siliconed) — credit where it belongs, and thanks for the remarkable work.**

The original app runs recent open-weight diffusion models natively in Swift and Metal on Apple silicon Macs (M1 and later) — [Krea 2 Turbo](https://huggingface.co/krea/Krea-2-Turbo), [Z-Image Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo), [Qwen-Image-2.1 Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo), [Anima Turbo](https://huggingface.co/circlestone-labs/Anima) and [MOSS-Image](https://huggingface.co/OpenMOSS-Team/MOSS-Image-SFT) — no Python, no cloud, no data leaving the Mac, every stage checked channel by channel against reference implementations. The original app's documentation lives in its repository and here in [docs/](docs/).

This repository continues from the original (version 0.20); every change here is open source under the same [Apache License 2.0](LICENSE) — the original copyright and license notices are kept as they are, and this fork's work is offered under the same license.

## Photoshop as the canvas: the rocxps plugin

**The goal of this fork**: Siliconed as Photoshop's external generation tool. The Photoshop side is [rocxps](https://github.com/vark-debug/rocxps) — a UXP panel (Photoshop 24.2+): you frame a selection, the panel captures it with a 32-px-aligned mask, and the local Siliconed — or a paired Mac — does the render, through the same `silicontrol` the terminal uses. The result is laid back on the canvas at its exact size: a whole replacement, a layer mask, or a pixel mask.

- **An empty prompt, or “force remove”, takes the selection's contents away**; a sentence redraws them — the branch is read from the prompt, in the panel as in the app.
- **The panel's queue** persists on disk, pauses and resumes, retries a task; the paste-back is automatic, or one click when you want to look first.
- The same panel also speaks to Volcengine (Seedream), RunningHub and IOPaint; Siliconed is its local, private backend.

## What this fork does

### 1. Qwen-Image-2.1 workflows, node for node against ComfyUI

- **Remove and inpaint (redraw)**: the masked crop, the green fill or a prompt-driven replacement, the feathered paste-back — σ table and 9-step ManualSigmas, the reference resolution, the crop's start, all equivalent to ComfyUI's Qwen-Image-2.1 remove/redraw workflow ([docs](docs/MASK-WORKFLOW.md)).
- **Outpaint (expand)**: the canvas grows outward by a percent of each side, filled in grey, sampled at sizes rounded to the nearest 32, pasted back as GH_CropRestore does — equivalent to ComfyUI's “Qwen Image 2.1 expand” workflow, with no stretch and no edge ghosting ([docs](docs/EXPAND-WORKFLOW.md)).
- **The workflows' preset LoRAs**: remove (1.0), redraw (0.48), expand (0.7) — Goohai's qwen2-1-gh series, shared on Bilibili, wired automatically per branch.
- **The comparison curtain**: the original and the result under a sliding curtain, the expand's empty areas shown as a checkerboard.

### 2. SeedVR2 upscaling

A Swift/MLX port of SeedVR2: ×N refinement of an image, 1:1. In the app (with a window and a remote mirror on another Mac), and from the CLI directly on a file, without the app.

### 3. Download sources (China-reachable)

The models' files come from huggingface.co; where that is out of reach, the app asks ModelScope (魔搭) and the hf-mirror.com mirror on its own — or you pick the source in the Models sheet, locked while an install runs. Whatever the door, every file is checked against its recipe's pinned sha256 ([docs](docs/HUB-SOURCES.md)).

### 4. The new abilities exposed to the CLI (`silicontrol`)

The original's `silicontrol` already drives renders from a terminal ([docs](docs/REMOTE-CONTROL.md)); this fork exposes the new editing branches to it:

- `add --mask MASK --mode remove|redraw` — remove and inpaint;
- `add --lora expand --pad L,R,T,B --image IMAGE` — expand (the 0.7 preset wired, a mask refused);
- `upscale FILE [DEST] [--scale N]` — SeedVR2 on a file, no app needed.

The [rocxps plugin](https://github.com/vark-debug/rocxps) drives the app through these commands.

## Speed, next to the ComfyUI workflows

On the same Apple M1 Ultra (64 GB), the same image, the same task, the workflow's own parameters (9-step ManualSigmas), random seeds, several timed rounds:

| Metric | ComfyUI workflow | Siliconed | Difference |
|---|---|---|---|
| Remove · cold start | 155.94 s | **45–49 s** | ~3.2× faster |
| Remove · warm | 61.02 s | **34.62 s** | ~1.76× faster |
| Expand · cold start | ~267 s | **153.1 s** | ~1.7× faster |
| Expand · warm | 225.98 s | **128.09 s** | ~1.76× faster |

Quality, compared side by side: the remove and expand reconstructions are equivalent. [Method, detail, reproduction](docs/SPEED-COMPARISON.md).

## Download

The original ships as a `.dmg` on the upstream [Releases](https://github.com/gwenn-ha-dev/Siliconed/releases) page; this fork publishes its own [Releases](https://github.com/vark-debug/Siliconed/releases) — 0.21 onward — and can also be built from source ([Build from source](docs/ENGINE.md#build-from-source), Xcode 26 or later). Requirements: macOS 26 or later, Apple silicon. Nothing comes preinstalled: you pick the models inside the app, read each license, and only then does a byte download.

## What the original app does (a summary)

- **Draws from text, edits by instruction**; **bracketing grids** (one finished image per cell); **the Prompt Lab** (prompts rewritten in each model's style, images described — beta); **your own models** (LoRAs and fine-tunes from Civitai / Hugging Face); **local and private** (no content filter, no history leaves the machine); **renders on another Mac** (paired once, encrypted); **scriptable** (`silicontrol`). The app's tour: [docs/APP.md](docs/APP.md).

![The Siliconed window: the rack on the left (text, text encoder, DiT, VAE decoder, each with its settings and time), the Krea 2 Turbo surf photo in the middle, the Prompt Lab folded to one line beneath it, the history on the right](docs/images/window.jpg)

## Documentation

The original project's docs (maintained here):

- [docs/APP.md](docs/APP.md) — the app; [docs/ENGINE.md](docs/ENGINE.md) — the engine, the numbers, the memory budget; [docs/VERIFY.md](docs/VERIFY.md) — verify on your Mac; [docs/REMOTE-CONTROL.md](docs/REMOTE-CONTROL.md) — `silicontrol` and the protocol; [docs/RELEASE-NOTES.md](docs/RELEASE-NOTES.md) — what each version changes.

This fork's additions:

- [docs/MASK-WORKFLOW.md](docs/MASK-WORKFLOW.md) — the remove/redraw workflow read from its sources; [docs/EXPAND-WORKFLOW.md](docs/EXPAND-WORKFLOW.md) — the expand workflow; [docs/HUB-SOURCES.md](docs/HUB-SOURCES.md) — the download sources.

## Acknowledgements

Siliconed was created by Gwenn — everything this fork adds stands on that foundation. The models belong to their publishers, each under its own license; the reference implementations are Hugging Face's [diffusers](https://github.com/huggingface/diffusers) and [transformers](https://github.com/huggingface/transformers), and the image resampling reproduces [Pillow](https://github.com/python-pillow/Pillow)'s Lanczos bit for bit. The remove/redraw/expand alignment of Qwen-Image-2.1 owes special thanks to Goohai ([Goohaitools-comfyui](https://github.com/goohai/Goohaitools-comfyui)) for open-sourcing the ComfyUI workflows “Qwen-2.1 remove, redraw, expand” — the reference implementations this project was read from; the workflows' LoRAs are Goohai's, shared on Bilibili; MOSS-Image's 8-step recipe comes from lodestones' [DMD LoRA](https://huggingface.co/lodestones/MOSS-Image-SFT-8-steps-dmd); the upscaler is based on SeedVR2 (ByteDance's Seed team).

## License

The code is [Apache License 2.0](LICENSE): the original project is its author Gwenn's, this fork's changes are offered under the same license, and the original copyright and license notices are preserved. Model weights are not part of this repository: you download each model yourself, under its own license, shown by the app before it installs.
