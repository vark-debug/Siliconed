# Tasks

> 评审检查点：Task 2 的文档完成后请先评审，确认集成设计再进入 Task 3–8。

- [x] Task 1: 创建新分支 `feature/qwen21-expand-workflow`（自 `feature/qwen21-workflow-parity`，工作树干净，直接 `git switch -c`）
- [x] Task 2: 编写扩图工作流分析文档 `docs/EXPAND-WORKFLOW.md`
  - [x] SubTask 2.1: 节点图解析——按 JSON 还原数据流与全部默认参数（画板可视化 30/30/0/0、灰 #808080、最大输出长边 5120；系数公式；`min(max(1024,长边),2048)`；÷32；9 步 ManualSigmas；扩图 LoRA 0.7；CropRestore 3/3/1；编码节点 mask 未接线）
  - [x] SubTask 2.2: 与移除/重绘路径的逐项对齐表（起点、noise-mask、LoRA、步数、采样器、缩放范围、提示词、回贴语义、输出尺寸=画布尺寸），标注 aligned / near / not aligned 与理由（参照 `MASK-WORKFLOW.md` 第 12 节的表格风格）
  - [x] SubTask 2.3: 应用侧集成设计——引擎几何（`Patch.Mode.expand` 或独立 `Expand` 模块）、CLI 开关（`--mode expand`、外扩百分比、`--lora expand` 解禁）、GUI 入口（无遮罩依赖）、错误码（沿用 `usage`/`patch`/`lora` 语义）
  - [x] SubTask 2.4: 已知差异与开放问题（提示词优化缺失、cover vs 拉伸、「外补是否存在」=false 的行为、扩图短边下限是否沿用 448、输出大于原图时的 GUI 对照/历史处理）
- [x] Task 3: 引擎扩图几何实现（评审文档后）
  - [x] SubTask 3.1: 灰边画布构建（百分比外扩、#808080、最大输出长边 5120）
  - [x] SubTask 3.2: 扩展系数公式与 plan（目标 `min(max(1024,长边),2048)`、÷32、短边下限裁决）
  - [x] SubTask 3.3: 单元测试（画布、系数、plan 边界）
- [x] Task 4: 渲染路径接线（依赖 Task 3）
  - [x] SubTask 4.1: 编码接线——画布为 image_01、无 noise-mask、固定提示词前缀 + 用户补充
  - [x] SubTask 4.2: 采样接线——9 步 ManualSigmas、euler、扩图 LoRA 0.7
  - [x] SubTask 4.3: 内存计价（`MemoryNeedQwenImage21`）纳入扩图尺寸
- [x] Task 5: 回贴与输出（依赖 Task 4）
  - [x] SubTask 5.1: 画布尺寸合成（`GH_CropRestore` 3/3/1 语义，原像素羽化保护）
  - [x] SubTask 5.2: 单元测试（合成尺寸、原区域一致性）
- [x] Task 6: CLI 开关（依赖 Task 3–5）
  - [x] SubTask 6.1: `--mode expand` 与外扩百分比开关、`--lora expand` 解禁（0.7 固定、拒绝 `:strength`）、冲突拒绝
  - [x] SubTask 6.2: 错误码与 `Request`/`Preflight` 更新、CLI 测试
- [x] Task 7: GUI 入口（依赖 Task 3–5，可与 Task 6 并行）
  - [x] SubTask 7.1: 扩图入口与百分比控件、机架预设卡（`PatchLoRAs.swift`）、本地化
  - [x] SubTask 7.2: redo/settings 保留（Render Again / Reuse These Settings）与测试
- [x] Task 8: 收尾验证（依赖 Task 6–7）
  - [x] SubTask 8.1: `swift build` 与全量测试通过（5 个失败均为基线 b3ba44e 上即存在的环境性失败，已用干净 worktree 复跑确认与本次改动无关）
  - [x] SubTask 8.2: 文档与实现核对（默认值、开关语义、错误码表逐条比对；同步修正 `MASK-WORKFLOW.md` 中两处已过时的「`--lora expand` 被拒绝」描述）

# Task Dependencies
- Task 2 → Task 3/4/5/6/7（文档评审是集成的闸门）
- Task 1 → Task 2（文档在新分支上提交）
- Task 3 → Task 4 → Task 5 → Task 6；Task 7 依赖 Task 5
- Task 6 与 Task 7 可并行；Task 8 依赖 Task 6 与 Task 7
