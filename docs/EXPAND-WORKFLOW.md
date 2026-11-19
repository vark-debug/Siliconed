# The expand workflow, from the ComfyUI graph

The 「扩图」 path (outpaint): one image, no mask to edit — the canvas grows outward, the grey
border is drawn over by Qwen-Image-2.1, and the original is laid back inside the bigger picture.
This page is the analysis the integration was built from: the graph as the JSON has it, every
default the widgets hold, the item-by-item comparison with the mask path (`MASK-WORKFLOW.md`),
and the design the app took. The ComfyUI source is
`Qwen image 2.1/工作流/Qwen Image 2.1 扩图.json`; the app's side is in [APP](APP.md), the
engine's in [ENGINE](ENGINE.md).

**中文速查**: 扩图不需要遮罩 —— 图像本身就是「保留区」，用户给的是**外扩百分比**（工作流默认
左 30 / 右 30 / 上 0 / 下 0）。应用把原图放进灰色（`#808080`）画布，按工作流公式算出扩展系数，
以整幅画布为 image 1 渲染（**无 noise-mask**），提示词是固定句
「移除图像中的灰色区域，无缝自然延展为完整图像。」加上用户补充；接 `Qwen2.1_扩图_GH_3750`
LoRA（**0.7**），9 步 euler（与移除/重绘同一张 `ManualSigmas` 表）；解码后按
`GH_CropRestore`（扩展 3 / 羽化 3 / 颜色还原 1）把原图合成回**外扩后的画布** —— 产物比原图大。

## 1. The graph, node by node

| node | type | role | widgets that matter |
|---|---|---|---|
| 1 | `LoadImageGoohai` | the image and its mask (the mask marks the **image itself** — the region to keep) | `保留透明通道 false` |
| 48 | `孤海外补画板可视化` | **the canvas**: pads the image with grey on all four sides | 单位 `百分比`，左 **30**，右 **30**，上 **0**，下 **0**，最大输出长边 **5120**，整除数 **0**，外补颜色 **`#808080`** |
| 40 | `孤海遮罩分析` | reads the padded mask: 画布宽 / 画布高 / 遮罩宽 / 遮罩高 | all expansions 0 |
| 39 | `数学运算_孤海` | the **expansion coefficients** (below) | 值1 `1.0 if b==d else (2/3*(b-d))/min(c,d)+1.0` · 值2 `1.0 if a==c else (2/3*(a-c))/min(c,d)+1.0` |
| 24 | `GH_MaskCropV2` | crops around the mask with those coefficients — in effect the whole canvas | 遮罩填充 **false**，输出尺寸 `原像素`，倍数取整 0 |
| 30 | `长边短边` | the crop's long side | — |
| 28 | `数学运算_孤海` | the sampling target | `min(max(1024, 长边), a)`，a = 滑杆 27 的 **2048** |
| 27 | `GoohaiUniversalSlider` | 最大采样尺寸（长边） | 2048，range 1024–3840, step 128 |
| 5 | `图像缩放V2_孤海` | scales the crop to the target | `按长边等比例`，`Lanczos`，`拉伸`，整除数 **32** |
| 7 | `TextEncodeQwenImage21GH` | the text encoder | **mask 未接线** — no noise-mask; `mode 填充`; `ref_image_size 自动`; latent_width/height **from node 5** |
| 32 | `CR Text Concatenate` | joins the prompts | separator **空** |
| 33 | `easy string` | the fixed prefix | 「移除图像中的灰色区域，无缝自然延展为完整图像。」 |
| 2 | `DF_Text_Box` | 补充提示词 | empty by default |
| 17 | `LoraLoaderModelOnly` | the expand LoRA | `Qwen2.1_扩图_GH_3750.safetensors` @ **0.7** |
| 15 | `KSamplerSelect` | the sampler | `euler` |
| 16 | `ManualSigmas` | the schedule | `1.0, 0.978453, 0.954180, 0.926626, 0.895080, 0.845148, 0.704534, 0.414568, 0.150000, 0` — **9 steps, the mask path's own table** |
| 18 | `RandomNoise` | the seed | randomize |
| 19 | `SamplerCustomAdvanced` | samples from **pure noise** at the scaled canvas's size | — |
| 21 | `VAEDecode` | the render, at the plan's size | — |
| 25 | `GH_CropRestore` | **the paste-back**: the render laid over the padded canvas | 遮罩扩展百分比 **3**，遮罩羽化百分比 **3**，颜色还原强度 **1**；裁剪遮罩与背景图像未接线 |
| 46 / 23 | `SaveImage` / `Image Comparer` | output / the render against the padded original | — |

Models: `qwen_image_2.1_turbo_int8_convrot` (UNET), `qwen3vl_8b_int8_convrot` (CLIP),
`qwen_image_2.1_vae_bf16` (VAE) — the same files the mask path loads.

## 2. The mask marks the expansion — and the crop is the canvas

Reading the Goohai sources settled the question the JSON alone could not: **the mask of the
expand graph marks the grey border, not the image**. `孤海外补画板可视化` (`外补画板（可视化）.py`)
with no user mask answers a mask that is **1 over the pads and 0 over the image** — so:

- node 40's 遮罩宽 / 遮罩高 (`遮罩分析`'s bounding box of the non-zero mask) are the **canvas's own
  size** on a padded axis and the image's own size on an axis without one;
- node 39's coefficients — vertical `1.0 if b == d else (2/3 × (b − d)) / min(c, d) + 1.0`,
  horizontal `1.0 if a == c else (2/3 × (a − c)) / min(c, d) + 1.0` — therefore answer **1.0 on
  every axis** (a padded axis makes 画布 == 遮罩, an unpadded one makes 画布高 == 遮罩高);
- `GH_MaskCropV2` (`遮罩裁剪V2.py`) grows the crop by `(系数 − 1) × the mask's shortest side` per
  side — **by nothing here** — and clamps the crop to the image's bounds (`扩展量上 = min(扩展量上,
  最小y)` and friends): the crop lands exactly on the mask's bounding box, **the whole padded
  canvas**, grey border and image together.

The app takes the canvas directly and records the coefficients node 39 returns for those same
mask bounds — 1.0 across, the settings reading like the graph. (A first reading of this page had
the mask marking the *image* and the coefficients at 1.4; the sources said otherwise, and the
plan follows the sources.)

**中文**: 读孤海源码定案 —— 扩图链路的遮罩标记的是**外扩区域（灰边）**，不是原图。因此
遮罩 bbox 在有灰边的轴上就是画布尺寸，节点 39 的系数恒为 1.0，`GH_MaskCropV2` 的边距为零、
裁剪就是**整幅画布**。应用直接取画布为裁剪，并按同样的遮罩 bbox 记录系数（全 1.0）。

**The sampling size follows node 5's own arithmetic** (`图像缩放V2.py`, `计算等比例目标`), not the
patch path's two-scheme rounding: the fixed side rounds to the **nearest** multiple of 32
(`就近整除`, `max(d, floor(size / d + 0.5) × d)`), the other side follows the ratio (`round`) and
rounds to the nearest multiple too — the 拉伸 mode's rule. Rounding to the *nearest* is what
keeps the render's shape the canvas's: a floor here drops up to 31 px off the long side, and the
paste-back's resample (`GH_CropRestore` scales the render back with Pillow's Lanczos, L744–766)
stretches the picture to cover the difference — a distortion the workflow never shows. A canvas
1180×1024 under the floor scheme renders at 1152×1024 and comes back stretched 2.4 %; under
node 5's own rounding it renders at 1184×1024 and comes back honest.

**中文**: 采样尺寸的 ÷32 必须用节点 5 的「**就近整除**」（指定边四舍五入到 32 的倍数，另一边
先等比 round 再就近整除）——不能沿用遮罩路径的「向下取整两方案」。向下取整会把长边砍掉最多
31 px，回贴的 Lanczos 缩放再把它拉回来，产生 ComfyUI 里不存在的拉伸（1180×1024 的画布会被
渲染成 1152×1024、回贴拉伸 2.4%；就近整除是 1184×1024，无形变）。

## 3. What reaches the model

| item | the workflow | the app (`--mode expand`) | alignment |
|---|---|---|---|
| canvas | 48: grey `#808080` pads, percent of the image's own sides, 30/30/0/0 default, capped at a long side of 5120, no rounding (整除数 0) | `Expand.canvas`: the same pads, the same grey, the same 5120 cap | **aligned** |
| crop | 24 with the coefficients → the whole canvas (§2: the mask marks the expansion, the coefficients are 1.0) | the canvas as it is; the same 1.0 coefficients recorded in the plan | **aligned** |
| sampling size | 28 + 5: long side `min(max(1024, cropLong), 2048)`, then node 5's `就近整除` — the fixed side and the ratio-following side both to the nearest multiple of 32, Lanczos | `Expand.plan`: the same target, node 5's own nearest-multiple arithmetic (`nearestMultiple`) | **aligned** |
| image 1 | 5's output — the padded canvas stretched to the sampling size | the canvas resized exactly to the plan (the ÷32 rounding leaves ≤ 32 px of difference) | **near** — Lanczos vs the engine's resampler, sub-visible at 9 steps |
| noise-mask | 7's **mask input is not wired** — none | none: `Expand` renders without a noise mask, the whole canvas is rebuilt | **aligned** |
| start | `latent_image` = 7's latent (empty) + `RandomNoise` — pure noise | `Latent.noise` at the plan's size | **aligned** |
| steps | `ManualSigmas` 9 steps (10 σ: 1.0 … 0) | `Patch.defaultSteps` = 9, the same table | **aligned** |
| sampler | `KSamplerSelect` euler | Euler (the default solver) | **aligned** |
| LoRA | 17: `Qwen2.1_扩图_GH_3750` @ **0.7** | the `expand` preset @ **0.7**, wired for you | **aligned** |
| prompt | 33 + 32: the fixed sentence + 补充提示词, separator empty | the fixed sentence, then the user's sentence if there is one | **aligned** |
| paste | 25: `GH_CropRestore` 3 / 3 / 1 — the render over the canvas, the **expansion ring** (the mask, 1 over the grey border) grown 3 % *inward* and feathered 3 %: the band lies inside the image's edge, past it the render alone | `Expand.composited`: the render scaled back to the canvas, the keep-mask the image's rectangle *shrunk* 3 % and feathered 3 % — no pixel read outside the image's bounds | **aligned** |
| output | the **canvas's size** — bigger than the image | the canvas's size | **aligned** (the mask path pastes to the *original's* size; expand does not) |
| prompt optimizer | absent in this graph | absent | **aligned** |

The one deliberate departure: the crop. The workflow walks mask → coefficients → crop and
arrives at the canvas; the app starts at the canvas and records the coefficients. What the
scaler, the encoder and the denoiser see is the same image either way.

## 4. The app's integration

**Engine** (`Expand.swift`, beside `Patch.swift`):

- `Expand.Pads` — one percent per side (left / right / top / bottom), default **30 / 30 / 0 / 0**,
  0–200 each. A pad of 0 on every side is refused (`invalid_patch`): nothing to expand.
- `Expand.canvas(image, pads)` — pad = `round(percent × the image's own side)` per side; grey
  `#808080` fills the border. If the canvas's long side passes 5120 the whole canvas is scaled
  back under it, pads and image together.
- `Expand.plan(pads, width, height, maximumSample)` — crop = the canvas; the sampling long side
  is `min(max(1024, canvasLong), maximumSample)` (default 2048, the workflow's slider), both
  sides brought to multiples of 32 the same two-scheme way `Patch.plan` rounds; the canvas's
  coefficients are computed with node 39's formula and kept in the plan. A plan whose **short
  side** falls under 448 is refused (`invalid_patch`) — the patch path's own floor, adopted here
  because a grey strip that thin renders nothing legible; the workflow itself has no short-side
  rule, only the 1024 floor on the long side.
- The render hands the canvas (scaled to the plan) to the text encoder as image 1 with **no
  noise-mask**, starts from noise, walks the 9-step table with euler, and takes the `expand`
  preset at 0.7.
- `Expand.composited(render, canvas, image)` — the decoded render is scaled back to the canvas's
  size; the keep-mask is the image's rectangle **shrunk** 3 % and feathered 3 % (the workflow's
  expansion ring grown *inward* — the blend band lies inside the image's edge, and past the edge
  the render stands alone, so no pixel is ever read outside the image's bounds), the original
  colour-matched to the render over the band alone with colour restore at 1 — the `GH_CropRestore`
  semantics read from `遮罩裁剪V2.py`, pointed at a bigger canvas instead of a same-size one.

**CLI** (`silicontrol`):

```sh
silicontrol add --model qwen-image-2.1 --image photo.jpg \
  --mode expand --pad 30,30,0,0 --steps 9 --wait --out ./out \
  "the beach continues, more waves"
```

| switch | default | meaning |
|---|---|---|
| `--mode expand` | — | the expand branch; **`--mask` beside it is refused** (`error: "patch"`): the masks of remove/redraw mean the opposite of expand's keep-region |
| `--pad L,R,T,B` | `30,30,0,0` | percents of the image's own sides, 0–200; all zero is refused |
| `--max-sample N` | `2048` | the sampling long side's ceiling, 1024–3840, ×128 as the slider steps |
| `--lora expand` | wired by `--mode expand` | the preset, pinned at 0.7; a `:strength` beside it is refused (`error: "lora"`) |

The old refusal is gone: `--lora expand` used to answer `error: "lora"` because no workflow
wired it — now `--mode expand` does. Conflicts refuse as ever: `--mode expand` against a remove /
redraw preset (`error: "mode"`), the same LoRA twice (`error: "lora"`), `--mode` switches without
an image (`error: "usage"`). The prompt is **optional** — the fixed sentence carries an empty
one; the user's words are appended after it.

**GUI**: an « Expand » entry beside « Paint Mask… » / « Attach Mask… » — no brush, four pad
fields at the workflow's defaults, and the rack's Add menu carries `Expand preset (0.7)`. The
history entry keeps `settings.expand` (`pads`, `maximumSample`), so Render Again and Reuse These
Settings draw the same canvas. The compare button shows the **original image** beside the result
— the original sits inside the bigger picture, which is the comparison the workflow's own
`Image Comparer` draws.

**Errors** (the codes the CLI and engine add):

| code | seen with | do |
|---|---|---|
| `patch` | all four pads 0; a plan whose short side falls under 448; a canvas that cannot reach 1024 on its long side; `--mask` beside `--mode expand` | give at least one pad a percent; make the image or pads less extreme; drop the mask |
| `lora` | `--lora expand:0.5`; `expand` with another preset | take the preset bare, or switch the mode |
| `mode` | `--mode expand` against a remove / redraw preset card | one branch at a time |

## 5. Known limits, and the questions this analysis leaves open

- **No mask**: expand's region is the whole image; the mask painter's white-means-replace
  language does not bend to it. `--mode expand` and `--mask` refuse each other rather than
  translate.
- **The fixed prompt leads**: the user's sentence is the 补充提示词 — appended after the fixed
  sentence, never replacing it. The workflow hands the model the same two-part prompt.
- **The prompt optimizer is absent** — this graph has no `提示词优化` node, so nothing to align;
  the mask path's one gap does not exist here.
- **「外补是否存在」** (node 48's boolean) is left **unconnected** in the JSON: a canvas with no
  pads still runs, regenerating the image from noise at its own size. The app refuses it instead
  (`patch`) — a render that redraws everything and changes nothing the user asked for.
- **The short-side floor (448) is the app's choice**: the graph only floors the *long* side at
  1024. A canvas taller than it is wide by more than 4.5:1 is refused where ComfyUI would run it;
  widen the pads instead.
- **The crop's overshoot, settled by the sources** (§2): the Goohai sources show the mask marks
  the expansion, the coefficients answer 1.0, and `GH_MaskCropV2` clamps its margins to the
  image's bounds — the crop is the canvas, and the app takes it whole.
- **`--pad` counts in percent of the image's own sides**, matching the widget's 单位 `百分比`.
  The JSON's saved signature (`2880×3840`, pads 858) is leftover UI state of an earlier session,
  not a second unit.
- **Memory**: a canvas padded to the 5120 cap renders at a long side of 2048 — the same budget
  the mask path prices a 2048-px crop at; `MemoryNeedQwenImage21` prices the plan's size before
  the render starts, as ever.
