# Checklist

## 分支与文档（本阶段）
- [x] 新分支 `feature/qwen21-expand-workflow` 已创建，基于 `feature/qwen21-workflow-parity`（父提交 b3ba44e）
- [x] `docs/EXPAND-WORKFLOW.md` 存在，风格与 `docs/MASK-WORKFLOW.md` 一致（英文正文 + 中文速查）
- [x] 文档含节点图解析，参数与 JSON 原文一致（30/30/0/0、#808080、5120、系数公式、min(max(1024,长边),2048)、÷32、9 步表、LoRA 0.7、CropRestore 3/3/1、编码节点 mask 未接线）
- [x] 文档含与移除/重绘的逐项对齐表，每项标注 aligned / near / not aligned 及理由
- [x] 文档含集成设计（引擎几何、CLI 开关、GUI 入口、错误码、LoRA 解禁）
- [x] 文档含已知差异与开放问题（提示词优化、cover vs 拉伸、外补不存在行为、短边下限、输出大于原图的处理）

## 集成阶段（文档评审后）
- [x] 灰边画布构建与百分比换算符合工作流（含最大输出长边 5120）——`ExpandTests.testTheCanvasPadsTheImageWithGrey` / `testTheCanvasIsCappedAt5120`
- [x] 扩展系数公式与 JSON 一致（无外扩方向系数 = 1.0）——`ExpandTests.testTheCoefficientsAreNodeThirtyNines`
- [x] plan 目标为 `min(max(1024, 画布长边), 2048)` 且两边为 32 的倍数——`ExpandTests.testThePlanSizesTheCanvas` / `testASmallCanvasIsScaledUpTo1024`
- [x] 渲染无 noise-mask，image_01 为带灰边画布——`EngineRender`：`prepared = [expandCanvas]`，无 Inpaint 掩码
- [x] 提示词为固定句「移除图像中的灰色区域，无缝自然延展为完整图像。」+ 用户补充——`ExpandTests.testThePromptLeadsWithTheFixedSentence`
- [x] 扩图 LoRA `Qwen2.1_扩图_GH_3750` 以 0.7 接线，`:strength` 被拒绝——`ExpandEntryTests.testTheExpandPresetIsWiredIntoTheStack` / `ExpandSwitchTests.testTheExpandPresetRefusesAStrengthSuffix`
- [x] 9 步 ManualSigmas 与 euler，与移除/重绘同表——`EngineAdmission`：expand 默认 `Patch.defaultSteps`
- [x] 回贴后产物为画布尺寸，原像素区域受羽化保护（3/3/1）——`ExpandTests.testTheCompositedImageIsTheCanvasWithTheOriginalInside`
- [x] CLI `--mode expand`、`--pad`、`--max-sample` 可用，冲突拒绝（patch/usage/mode/lora 语义沿用）——`ExpandSwitchTests` 15 例全绿
- [x] GUI 扩图入口可用（无遮罩依赖），redo 保留扩图设置——`ExpandEntryTests.testTheExpandSettingsSurviveReuseAndARedoStaysItsOwn`
- [x] 内存计价覆盖扩图尺寸——`EngineRender` 以 plan 尺寸 + `referenceMatchesTarget` 计价
- [x] `swift build` 通过，新增单元测试全部通过（引擎 10 + CLI 15 + GUI 9；全仓余下 5 个失败——DiagnosticMemoryTests×2、CapacityProbeSizesTests×1、MossImageTests.testALoRAIsCharged、NeuralEngineTests.testInt8RouteAgainstFloat64——在基线 b3ba44e 的干净 worktree 上复跑失败值逐字相同，为本机环境性失败，与本次改动无关）
- [x] 文档与实现逐条核对一致（并同步修正 `MASK-WORKFLOW.md` §2/§10 两处已过时的「`--lora expand` 被拒绝」描述）
