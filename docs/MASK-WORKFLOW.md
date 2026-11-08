# The mask workflow, from the command line

The 「附遮罩 → 裁剪 → 回贴」 path (局部重绘 / remove–redraw): one image, one mask, one sentence —
the region is cut out with a margin, drawn again by Qwen-Image-2.1, and laid back where it came
from. This page is the cookbook: every command the flow touches, in order, with the switches'
exact semantics and the refusals they raise. The app's side of it is in [APP](APP.md), the
engine's in [ENGINE](ENGINE.md), the protocol's in [REMOTE-CONTROL](REMOTE-CONTROL.md).

**中文速查**: 一条命令就是全部流程 ——

```sh
silicontrol add --model qwen-image-2.1 \
  --image photo.jpg --mask photo-mask.png \
  --mode remove --steps 9 \
  --wait --out ./out "remove the lamp and its cable"
```

遮罩与 `--image` 同尺寸（白区域/alpha 为要处理的部分）；默认 `--mode remove`（涂绿 + 移除 LoRA
1.0），`--mode redraw`（不涂绿 + 重绘 LoRA 0.48）；默认回贴，产物与原图同尺寸；`--no-paste`
（= `--crop-only`）只留裁剪图。**步数默认是 9**（工作流的 `ManualSigmas`，GUI 附遮罩后表单同样显示
9）；显式 `--steps 8` 才走 Turbo 发布的 8 步表，模型没有的表在解析时就拒绝。下面各节是同一条命令的
逐项说明。

## 1. Environment and launch

```sh
# Build the app (the bundle lands beside the sources)
tools/app.sh

# The command line tool: inside the bundle, or installed by the app
Siliconed.app/Contents/Helpers/silicontrol   # direct use
# Siliconed › Install the silicontrol command… → /usr/local/bin/silicontrol
```

`silicontrol` talks to the **running** app and launches it if it is not (`silicontrol open`
waits up to 30 s for the app to answer). Stdout is JSON lines; the last line carries `ok`.
Exit codes: `0` ok · `1` `ok:false` · `2` usage · `3` the app cannot be reached.

Starting the app from a terminal, without a Keychain prompt (it reads « Lend This Mac » and
« Borrow a Mac » at launch):

```sh
open ~/Desktop/Siliconed-build/Siliconed.app --args -lendThisMac false -borrowsAMac false
```

These are **launch arguments for this run only** — they land in the app's `NSArgumentDomain` and
are not written to its preferences; the next launch without them prompts again. The same app
instance serves GUI and CLI: they share one queue and one history.

## 2. Models and LoRAs

```sh
silicontrol models                          # ids, formats, LoRAs, default steps, "edit": true
silicontrol install qwen-image-2.1 --compact  # license and size shown in the app; accept there
silicontrol import /path/to/Qwen2.1_万物移除Remove_GH.safetensors
silicontrol import "/path/to/Qwen2.1 一致性无偏移_GH_V1.0.safetensors"
```

The workflow's two LoRAs are also **presets**, named by their branch and wired at the workflow's
own strength — no `:strength` suffix:

| preset | LoRA (`nom` inside the store's `.lora.silicon`) | strength |
|---|---|---|
| `--lora remove` | `Qwen2.1_万物移除Remove_GH` | **1.0** |
| `--lora redraw` | `Qwen2.1 一致性无偏移_GH_V1.0` | **0.48** |

A third file (`Qwen2.1_扩图_GH_3750`) belongs to the workflow's outpaint node, which this
workflow does not wire: `--lora expand` is refused (`error: "lora"`), not ignored.

## 3. The mask: what it must be

- **The same size as `--image`** — one pixel off is `invalid_patch`, not a resize.
- **White on black**, or a PNG whose **alpha** is the region; anything above the mask's
  threshold is the region to replace.
- **At least 10 pixels** of region; empty masks are refused (`invalid_patch`).
- The mask is **grown 30 px**, a 21-tap Gaussian (σ 10), and read bilinearly at the latent grid —
  the workflow's `Text Encode Qwen Image 2.1 GH` (`--noise-mask` keeps exactly this mask).

The region is filled, cropped with a margin, and that **crop is image 1** for the text encoder
(and the denoiser's reference block). The prompt says what happens in it. The render starts from
**noise** unless `--seeded-start` asks otherwise (section 5).

## 4. The default: `--mode remove`

```sh
silicontrol add --model qwen-image-2.1 --image photo.jpg --mask photo-mask.png \
  --steps 9 --wait --out out "remove the lamp and its cable"
```

`--mode` left out is `.remove`: the crop is tinted `#00FF00` at 0.4 inside the mask (the
workflow's `图像合并（遮罩）`), and `--lora remove` (1.0) is wired for you.

## 5. The two branches: `--mode remove | redraw`

| | `remove` (default) | `redraw` |
|---|---|---|
| crop | tinted green inside the mask | handed to the model untouched |
| prompt | says what **goes away** | says what it **becomes** |
| LoRA | `--lora remove` at **1.0** | `--lora redraw` at **0.48** |
| everything else | **the same** — same crop, `--expand`, `--max-side`, `--noise-mask`, `--seeded-start`, `--paste` | |

```sh
silicontrol add --model qwen-image-2.1 --image photo.jpg --mask photo-mask.png \
  --mode redraw --steps 9 --wait --out out "a red leather jacket, studio light"
```

- **Presets imply the mode**: `--lora redraw` alone is `--mode redraw`; `--lora remove` alone is
  the default. With `--mask` the preset is wired once, even when `--mode` is also given.
- **Conflicts are refused, never silently overridden** (`error: "mode"`): `--mode redraw
  --lora remove`, or both presets. The branch's preset is wired even when `--lora` names none;
  naming the same LoRA twice (a preset and a manual name that resolve to one file) is refused
  (`error: "lora"`).
- `--mode` without `--mask` is refused (`error: "usage"`): there is no crop to branch.

**中文**: 两个模式共用同一套裁剪/边距/回贴逻辑，差别只有「是否涂绿」与「接哪支 LoRA」。预设与
`--mode` 冲突时直接拒绝；不写 `--lora` 也会自动接上该分支的预设。

## 6. The switches, and every combination

| switch | default | with `remove` | with `redraw` |
|---|---|---|---|
| `--expand T,B,L,R` | `1.3,1.4,1.4,1.4` | margins as multipliers of the mask's **shortest side**, 1 or more | identical |
| `--max-side N` | `2560` | the crop's longest side after scaling, 768–2560, ×32 | identical |
| `--noise-mask` / `--no-noise-mask` | **on** | outside the mask the estimate is the crop's own latent at every step | identical |
| `--seeded-start` | **off** | the crop is also the start (`z₀ + √2·ε`, ComfyUI's max_denoise) | identical, but see below |
| `--paste` / `--no-paste` | **paste** | the crop laid back over the original, PNG at the original's size | identical |
| `--crop-only` | — | **the same switch as `--no-paste`** | identical |

**`--seeded-start` is off by default, on measurement.** At the workflow's 9 steps the schedule
could not wash a third of the crop out of the start: the tint the prompt asked to remove stayed
(mask G−R **36.2**, the original's 9.9), while the same crop as image 1 alone removed it (9.0).
So the crop is image 1 and the denoiser's reference block, and `z₀` is opt-in. In `redraw` the
seeded start usually fights the prompt (the crop's own structure lingers); it is wired the same
way if asked. Without `--mask` it is refused (`invalid_seeded_start` in the engine,
`error: "usage"` in the CLI).

**`--no-paste` and `--crop-only` are one switch, two spellings** — equal in every way; the alias
is kept because scripts already pass `--crop-only`. `--no-paste` writes the crop alone, at the
plan's size; the pasted render is at the **original's** size. The two spellings disagreeing
(`--paste` after `--no-paste`, or after `--crop-only`) is refused (`error: "usage"`), not
resolved by order.

**The compare button follows the paste**: a pasted patch's entry compares the whole result with
the original it started from; a `--no-paste` entry is a crop and offers no curtain
(`AppState.comparisonStart` requires `patch.paste`).

**中文**: `--paste` 默认开；`--no-paste` 与 `--crop-only` 是同一个开关的两种写法（保留旧写法
是为了已有脚本）；关掉回贴后产物是裁剪图，GUI 上不会出现对照按钮。`--seeded-start` 默认关是
实测结论：9 步洗不掉起点里约三分之一的裁剪内容。

## 7. `--ref-res`, and the crop

`--ref-res N` is Qwen-Image-2.1's reference resolution: each reference encodes at about `N²`
pixels, its own ratio kept, sides at 32; 768–2560, default 1024.

With `--mask` the flag is read **only when the crop keeps another proportion than the render's**
— its cover fit would cut more than 64 px a side, the workflow's tolerance. When the crop **is**
the render's own size, it is image 1 and the denoiser's reference block at that size, and
`--ref-res` is **refused there, not ignored** (`invalid_reference_resolution`).

## 8. Status, cancel, redo

```sh
silicontrol status            # what runs, what waits, the time left
silicontrol follow            # live events until the queue is empty
silicontrol cancel t3         # stops the running render, or removes a waiting job
silicontrol clear             # empties the queue

silicontrol wait t3 --out out # block, then write the PNGs
silicontrol again i7          # Render Again (Same Seed): the entry's settings, `--mode` and `--paste` included
silicontrol reuse i7          # Reuse These Settings
silicontrol undo --redo       # ⇧⌘Z for a history change
```

A patch entry keeps `settings.patch` (`mode`, `expansion`, `maximumSide`, `seededStart`, `paste`,
`noiseMask`), so `again` draws the same branch, the same crop and the same paste.

## 9. Known limits

- **Mask size**: exactly image 1's; anything else is `invalid_patch`. The GUI says it before the
  click too.
- **Region**: at least 10 pixels of mask.
- **Short side**: ordinary renders and edits stay **≥ 512 px** per side (`Format.minimumSide` =
  `Spectral.minimumSide × 8`). **A patch's own crop may go down to 448 px** on its short side
  (`Patch.minimumRenderSide`), and only there: its long side is 768–2560, a multiple of 32. This is
  not a workflow limit — `图像缩放（范围）` bounds the long side alone and `遮罩裁剪V2` has no
  short-side rule — nor a model one: 448 px is 28 latent cells (VAE ×16) and 14 steps of the
  32-px multiple, so it encodes and denoises as any other size, without a spectral schedule (its
  half, 224, is under the floor). 768×448 (12:7) is the smallest long-side crop; a crop under 448
  is refused as `invalid_patch`, with its crop and plan sizes, rather than silently upscaled.
  **The old "ratio > 1.5" rule was wrong**: the test is the short side, not the ratio — 2048×448
  (4.57:1) is accepted, 768×416 (1.85:1) is refused.
- **Area**: an ordinary edit (an image, no mask, no typed size) is capped at **1024 × 1536**
  (ratio 1.5); beyond it the **long side is cut**, keeping multiples of 32. A patch is **not**
  capped: its plan's size is the workflow's and the 448 short side is its only floor.
- **The crop decides the format**: with `--mask`, `--ref`, `--strength`, a typed format and
  `--grid` are refused (`error: "format"` / `"ref"` / `"grid"`).
- **`--mask` is Qwen-Image-2.1 only** (`error: "patch"` on other models).
- **GUI × CLI**: the GUI takes a mask **PNG** attached beside image 1 in the Prompt Lab — there is
  no brush; it does not expose `--expand`, `--max-side`, `--seeded-start`, `--noise-mask` or
  `--no-paste` (defaults apply), and its branch comes from the rack's **Add menu** presets
  (`Remove preset (1.0)` / `Redraw preset (0.48)`) — the same `Patch.Settings.mode` the CLI writes.
  A rack holding both presets is refused before the click.

## 10. Error codes, and what to do

The CLI refusals (`ok:false`, `error`) come before a job is queued:

| code | seen with | do |
|---|---|---|
| `usage` | `--mode` / `--paste` / `--no-paste` / `--crop-only` without `--mask`; two disagreeing spellings; an unknown `--mode` value | add the missing flag, keep one spelling, use `remove` or `redraw` |
| `patch` | mask of another size than image 1; an empty region; a crop that renders under 448 px on its short side; a model without the mask workflow; a mask with `--ref` on a non-Qwen model | fix the PNG, widen the mask or make the crop less elongated, or use Qwen-Image-2.1 |
| `mode` | `--mode` against the other branch's preset; both presets | name one branch |
| `lora` | a preset with `:strength`; `--lora expand`; the same LoRA twice; an uninstalled preset | `--lora remove` / `--lora redraw` bare; install it (`silicontrol models`) |
| `ref` | `--ref-res` without `--ref`, or a value out of 768–2560 / not ×32 | give a valid `--ref` and `N` |
| `format` | a typed format with `--mask` | leave the format out |
| `busy` | a model install or import in progress | `silicontrol install stop`, then retry |

The engine's codes arrive as a job's failure (`add --wait`, `status`, `follow`):

| code | meaning | do |
|---|---|---|
| `invalid_patch` | the crop cannot be made: mask size, empty region, `--crop-only`/`--noise-mask`/`--seeded-start` without a patch, or an img2img image beside a patch | fix the request; one start at most |
| `invalid_steps` | steps outside 1–50, or a step the model has no schedule for | `--steps 9` is the workflow's; `models` gives the default |
| `invalid_schedule` | the sigma table and the steps disagree (an engine-side schedule the model cannot walk) | use the model's own steps |
| `invalid_seeded_start` | `--seeded-start` with no patch, no image encoder, or a denoiser that takes no additive start | drop it, or use the patch path |
| `invalid_reference_resolution` | `--ref-res` out of range, not ×32, or asked where the crop is the render's own size | drop it there: the crop is image 1 at that size |
| `reference_sequence` | the references' roles and the prompt's template disagree (a model reading another number or order of images) | keep ≤ the model's `max_references`, in order; name them « image 1 »… |
| `insufficient_memory` | the render needs more than the Mac's budget (¾ of memory − 2 GB), judged before it starts | lower `--max-side`, `--ref-res` or the crop; the refusal is up front, not mid-render |
| `memory_need_unknown` | a size the engine cannot price before starting | use a format the model publishes |

## 11. A checklist for one good render

1. `silicontrol models` — the model is installed, `"edit": true`, and both LoRAs are listed.
2. The mask PNG is image 1's size, mostly black, white where the change goes.
3. Choose the branch: `--mode remove` with a sentence about what goes away; `--mode redraw`
   with a sentence about what it becomes.
4. Leave the format, `--ref`, `--strength` and `--grid` out; `--steps 9` for the workflow.
5. `--wait --out out` and read the last JSON line; on failure see section 10.
6. Compare: the pasted entry's compare button shows the original beside the result; for the raw
   crop, rerun with `--no-paste`.
