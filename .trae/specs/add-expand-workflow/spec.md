# 扩图（Qwen Image 2.1 Expand）工作流分析与集成 Spec

## Why
当前分支 `feature/qwen21-workflow-parity` 已完成「移除 / 局部重绘」工作流的移植（见
`docs/MASK-WORKFLOW.md`）。下一个要集成的工作流是 **Qwen Image 2.1 扩图（outpaint）**：
ComfyUI 源文件为 `~/Downloads/Qwen image 2.1/工作流/Qwen Image 2.1 扩图.json`。它与移除/重绘
共享大部分骨架（GH 节点族、9 步 ManualSigmas、euler、CropRestore 回贴），但在画布构建、
扩展系数、noise-mask、LoRA 与输出尺寸上有实质差异。需要先产出一篇与 `MASK-WORKFLOW.md`
同风格的分析文档，再按文档落地集成。

## What Changes
- 从当前分支创建新分支 `feature/qwen21-expand-workflow`，后续工作全部在其上进行。
- 新增分析文档 `docs/EXPAND-WORKFLOW.md`（本阶段唯一交付物，评审通过后再进入集成任务）：
  - 工作流节点图逐步解析（画板可视化 → 系数计算 → 裁剪 → 缩放 → 编码 → 采样 → 回贴）；
  - 与移除/重绘路径（`Patch.swift`、`Paste.swift`、`MASK-WORKFLOW.md`）的逐项对齐表；
  - 应用侧集成设计（引擎几何、CLI 开关、GUI 入口、LoRA 预设、错误码）；
  - 已知差异与开放问题。
- 集成阶段（文档评审后实施）：
  - 引擎新增扩图几何：灰边画布构建（#808080、百分比外扩、最大输出长边 5120）、
    扩展系数公式 `1.0 if 相等 else (2/3×差)/min(遮罩宽,遮罩高)+1.0`、
    采样目标 `min(max(1024, 裁剪长边), 2048)`、÷32 取整；
  - 渲染接线：**无 noise-mask**（工作流中编码节点的 mask 输入未接线）、
    `Qwen2.1_扩图_GH_3750` LoRA @ **0.7**、固定提示词前缀
    「移除图像中的灰色区域，无缝自然延展为完整图像。」+ 用户补充提示词、
    9 步 ManualSigmas（与移除/重绘同表）、euler；
  - 回贴：`GH_CropRestore`（3/3/1）语义合成到**外扩后画布**，产物尺寸 = 画布尺寸（大于原图）；
  - CLI：`--mode expand`（或对等开关）、外扩百分比开关、解禁 `--lora expand`（现为拒绝
    `error: "lora"`）、对应错误码；
  - GUI：扩图入口（不依赖遮罩画笔——遮罩语义与移除/重绘相反，标记的是保留区）；
  - 测试：几何单元测试（画布、系数、plan、回贴）与文档核对。

## Impact
- Affected specs: 无既有 spec；新建 `add-expand-workflow`。
- Affected code:
  - 文档：`docs/EXPAND-WORKFLOW.md`（新增），交叉引用 `docs/MASK-WORKFLOW.md`；
  - 引擎：`Sources/Siliconed/Patch.swift`（扩展 `Mode` 或新增 `Expand` 模块）、
    `Paste.swift`（画布尺寸回贴）、`EngineRender.swift` / `Request.swift`（接线）、
    `MemoryNeedQwenImage21.swift`（扩图尺寸计价）；
  - CLI：`Sources/Siliconed/Request.swift`、`Preflight.swift`（`--lora expand` 解禁、新开关、错误码）；
  - GUI：`Sources/SiliconedApp/AppState+Mask.swift`、`AppState+Render.swift`、`PatchBranch.swift`、
    `PatchLoRAs.swift`（扩图预设卡）、`Localizable.xcstrings`；
  - 测试：`Tests/SiliconedTests/`（Patch/EngineError 相关测试旁新增扩图用例）。

## ADDED Requirements

### Requirement: 新分支
工作 SHALL 在 `feature/qwen21-workflow-parity` 之上创建并切换到新分支
`feature/qwen21-expand-workflow`，所有扩图相关的文档与代码变更都提交在该分支。

#### Scenario: 分支创建
- **WHEN** 在 `feature/qwen21-workflow-parity`（工作树干净）上执行分支创建
- **THEN** 当前分支为 `feature/qwen21-expand-workflow`，其父提交为 `b3ba44e`

### Requirement: 扩图工作流分析文档
系统 SHALL 新增 `docs/EXPAND-WORKFLOW.md`，风格与结构对齐 `docs/MASK-WORKFLOW.md`
（英文正文 + 中文速查），并包含：

1. **节点图解析**：从 JSON 逐步还原数据流——
   `LoadImageGoohai`(1) → `孤海外补画板可视化`(48：单位百分比，左30/右30/上0/下0，
   灰 #808080，最大输出长边 5120，整除数 0，输出「外补是否存在」) →
   `孤海遮罩分析`(40) → `数学运算`(39：竖向 `1.0 if b==d else (2/3*(b-d))/min(c,d)+1.0`，
   横向 `1.0 if a==c else (2/3*(a-c))/min(c,d)+1.0`；a=画布宽, b=画布高, c=遮罩宽, d=遮罩高) →
   `GH_MaskCropV2`(24：遮罩填充 false，扩展系数来自 39，输出尺寸=原像素) →
   `长边短边`(30) → `数学运算`(28：`min(max(1024,b),a)`，a=滑杆 2048) →
   `图像缩放V2_孤海`(5：按长边等比例，Lanczos，整除数 32) →
   `TextEncodeQwenImage21GH`(7：image_01=缩放后画布，**mask 未接线**，mode=填充，
   ref_image_size=自动，prompt=固定句+补充) → `SamplerCustomAdvanced`(19) ←
   `LoraLoaderModelOnly`(17：`Qwen2.1_扩图_GH_3750` @ **0.7**)、`KSamplerSelect`(euler)、
   `ManualSigmas`(16：9 步表，与移除/重绘同表) → `VAEDecode`(21) →
   `GH_CropRestore`(25：扩展 3 / 羽化 3 / 颜色还原 1) → `SaveImage`(46) + `Image Comparer`(23)。
2. **对齐表**：逐项对照应用现有路径（起点、noise-mask、LoRA、步数、采样器、缩放范围
   1024–2048 vs 768–2560、提示词、回贴语义、**输出尺寸=画布尺寸（大于原图）**），
   标注 aligned / near / not aligned 及理由。
3. **集成设计**：引擎几何、CLI 开关（含 `--lora expand` 从拒绝改为接线）、GUI 入口、
   错误码；明确扩图不依赖遮罩——用户以外扩百分比表达（默认 30/30/0/0 为工作流默认）。
4. **已知差异与开放问题**：提示词优化节点缺失（与移除路径同一差异）、cover vs 拉伸、
   「外补是否存在」为 0 时的行为、扩图短边下限是否沿用 448。

#### Scenario: 文档完整性
- **WHEN** 阅读 `docs/EXPAND-WORKFLOW.md`
- **THEN** 上述 4 部分齐备，且节点参数与 JSON 原文一致（含默认值与接线状态）

### Requirement: 引擎扩图渲染路径（集成阶段）
系统 SHALL 提供扩图渲染路径：构建灰边画布 → 按工作流公式计算扩展系数 →
裁剪（= 整幅画布）→ 目标 `min(max(1024, 画布长边), 2048)` 且 ÷32 →
以画布为 image_01 编码（**不接 noise-mask**）→ 9 步 euler 采样、扩图 LoRA 0.7 →
解码后按 `GH_CropRestore`（3/3/1）把原图合成回画布，输出画布尺寸的 PNG。

#### Scenario: 扩图成功
- **WHEN** 用户提交一张图与外扩百分比（如 左30/右30）
- **THEN** 产物为外扩后画布尺寸的 PNG，原像素区域与原图一致（羽化过渡），灰色区域被延展内容替代

### Requirement: CLI 扩图开关（集成阶段）
CLI SHALL 支持 `--mode expand` 与外扩百分比开关，解禁 `--lora expand`
（固定接线 `Qwen2.1_扩图_GH_3750` @ 0.7，不接受 `:strength`），冲突时拒绝而非静默覆盖
（沿用现有 `error` 语义）。

#### Scenario: 解禁扩图 LoRA
- **WHEN** `silicontrol add --model qwen-image-2.1 --mode expand ...`
- **THEN** 不再返回 `error: "lora"`，扩图预设被自动接线

### Requirement: GUI 扩图入口（集成阶段）
GUI SHALL 提供扩图入口（不要求遮罩），暴露外扩百分比（默认与工作流一致），
扩图预设在机架 Add 菜单可见； redo（Render Again / Reuse Settings）保留扩图设置。

#### Scenario: GUI 扩图渲染
- **WHEN** 用户在 GUI 选择扩图、设置百分比并渲染
- **THEN** 历史条目保留扩图设置，可再次渲染同样的扩图

### Requirement: 测试（集成阶段）
测试 SHALL 覆盖：画布构建与百分比换算、扩展系数公式（相等→1.0 分支）、
plan（1024 下限 / 2048 上限 / ÷32 / 短边下限）、回贴合成尺寸、`--lora expand` 接线与
冲突拒绝、GUI 设置保留。

#### Scenario: 系数公式
- **WHEN** 画布与遮罩同尺寸（某方向无外扩）
- **THEN** 该方向系数为 1.0，与工作流 `1.0 if b==d else ...` 一致

## Out of Scope
- 提示词优化节点（`提示词优化`）的移植——与移除路径保持同一「not aligned」口径；
- 非 Qwen-Image-2.1 模型的扩图；
- 孤海画板可视化的交互式布局编辑（仅取其默认行为）。
