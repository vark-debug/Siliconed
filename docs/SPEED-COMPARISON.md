# 与 ComfyUI 工作流的速度对比（Speed Next to ComfyUI）

本页汇总 2026-11-16 在同一台机器上做的两组同任务对比：**移除**与**扩图**。同一张图、同一份蒙版（或同样的外补百分比）、同一个任务描述、同样的工作流参数（9 步 ManualSigmas σ 表、相同的裁剪外扩与回贴羽化），随机种子多轮计时。完整原始报告见文末附件说明。

## 环境

- 设备：Apple M1 Ultra，64 GB 统一内存，交流电源供电
- 对照组：ComfyUI v0.44.1（MPS，文本编码器 qwen3vl-8B 运行于 CPU float16）
- 实验组：Siliconed（本仓库，qwen-image-2.1 compact，Turbo int8），经 `silicontrol` CLI 驱动
- 每组测试前检查 CPU/内存占用，无异常后台负载

## 一、移除（1024×1024，同一张原图 + 同一张蒙版）

| 指标 | ComfyUI 工作流 | Siliconed | 差异 |
|---|---|---|---|
| 冷启动（含模型加载） | 155.94 s | **45–49 s** | 快约 3.2 倍 |
| 热运行平均 | 61.02 s | **34.62 s**（引擎纯渲染 32.96 s） | 快约 43%（1.76 倍） |
| 热运行波动 | < 0.3% | ~1.7% | 两者都高度稳定 |
| 移除质量 | 方糖移除、木纹重建自然 | 方糖移除、木纹重建自然 | 视觉效果相当 |

## 二、扩图（1024×1024 左右各外扩 30%，同一张原图）

| 指标 | ComfyUI 工作流 | Siliconed | 差异 |
|---|---|---|---|
| 冷启动 | 约 267 s（4 分 27 秒） | **153.11 s** | 快约 1.7 倍 |
| 热运行平均 | 225.98 s | **128.09 s**（引擎纯渲染 126.48 s） | 快约 43%（1.76 倍） |
| 热运行波动 | < 0.1% | < 0.5% | 两者都高度稳定 |

## 说明

1. Siliconed 的 9 步 σ 表、裁剪外扩、涂绿标记、回贴羽化与 ComfyUI 工作流逐项对齐；Siliconed 默认还开启 noise-mask（逐步外填），计算量略多但仍更快。
2. ComfyUI 侧文本编码器（qwen3vl-8B）在 CPU 上执行、模型加载需从磁盘读约 16 GB 权重，是其冷启动与热运行偏高的主要原因；Siliconed 的权重按需从磁盘读取、编码器在 GPU/神经网络引擎间分派。
3. ComfyUI 有执行缓存（同参数重复提交 0.01 s 命中全图缓存）；Siliconed 无缓存机制，每轮全量重算——表内热运行数字均为真实重算。
4. 引擎耗时为应用自报的渲染秒数；wall 为从提交到 PNG 落盘的实测秒数。
5. 质量评估：两组移除/扩图结果并排肉眼对比，重建效果相当（附件见原始报告）。

## 复现

- 移除：`silicontrol add --wait --model qwen-image-2.1 --lora remove --mask 蒙版.png ""`（白 = 移除区，1024×1024）
- 扩图：`silicontrol add --wait --model qwen-image-2.1 --lora expand --pad 30,30,0,0 --image 原图.png ""`
- ComfyUI 侧使用孤海（Goohai）的工作流「Qwen-2.1 移除、局部重绘」与「Qwen Image 2.1 扩图」（API 格式 JSON 随原始报告留存）。

## 英文小结 (English summary)

On the same M1 Ultra, with the same image, the same task and the workflow's own parameters (9-step ManualSigmas), random seeds, several timed rounds: **remove** — cold start 155.94 s (ComfyUI) vs 45–49 s (Siliconed, ~3.2×), warm 61.02 s vs 34.62 s (~1.76×); **expand** (30% each side) — cold ~267 s vs 153.11 s (~1.7×), warm 225.98 s vs 128.09 s (~1.76×). Quality compared side by side: equivalent. ComfyUI's encoder on CPU and its 16 GB disk-load explain much of the gap; ComfyUI's execution cache (0.01 s on identical resubmission) is its own advantage — Siliconed recomputes every round.
