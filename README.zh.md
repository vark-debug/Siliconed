[English](README.md) · [Français](README.fr.md) · 简体中文

# Siliconed（社区版）

**这是一个社区分支。原项目由 Gwenn（[gwenn-ha-dev](https://github.com/gwenn-ha-dev)）开发：[gwenn-ha-dev/Siliconed](https://github.com/gwenn-ha-dev/Siliconed) —— 感谢原作者的出色工作。**

原应用在 Apple 芯片 Mac（M1 及更新机型）上，以 Swift 和 Metal 原生运行近期的开放权重扩散模型——[Krea 2 Turbo](https://huggingface.co/krea/Krea-2-Turbo)、[Z-Image Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)、[Qwen-Image-2.1 Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo)、[Anima Turbo](https://huggingface.co/circlestone-labs/Anima) 和 [MOSS-Image](https://huggingface.co/OpenMOSS-Team/MOSS-Image-SFT)——无需 Python，无需云端，任何数据都不离开你的 Mac，且每个阶段都对照参考实现逐通道核验。原项目的应用详解、引擎与核验文档见其仓库与本仓库的 [docs/](docs/)。

本仓库在原项目（0.20 版）基础上继续开发，全部改动同样以 [Apache License 2.0](LICENSE) 开源；原项目的版权与许可证声明原样保留，本仓库的修改按同一许可证提供。

## 本仓库做了什么

### 1. Qwen-Image-2.1 工作流强化（与 ComfyUI 工作流逐节点对齐）

- **移除与局部重绘**：遮罩区域裁剪、绿色填充或按提示词重绘、羽化回贴——σ 表与 9 步 ManualSigmas、参考分辨率、裁剪起点，全部与 ComfyUI 的「Qwen-Image-2.1 移除/局部重绘」工作流等效（[文档](docs/MASK-WORKFLOW.md)）。
- **扩图（outpainting）**：画布按每边百分比向外延伸、灰边填充、就近 32 取整的采样尺寸、GH_CropRestore 等效回贴——与 ComfyUI 的「Qwen Image 2.1 扩图」工作流等效，且无拉伸、无边缘拖影（[文档](docs/EXPAND-WORKFLOW.md)）。
- **工作流预设 LoRA**：remove (1.0) / redraw (0.48) / expand (0.7)，取自 Civitai 社区的 qwen2-1-gh 系列，随分支自动接线。
- **对比幕帘**：原图与结果拉幕对比，扩图结果以黑白格标注原本没有内容的区域。

### 2. SeedVR2 放大

SeedVR2 的 Swift/MLX 移植：图像 ×N 的 1:1 精修放大。应用内有窗口与远程镜像（在另一台 Mac 上算），CLI 也可以直接对文件使用、无需打开应用。

### 3. 模型下载源（国内可达）

模型的文件来自 huggingface.co；如果这个地址在你的网络上无法访问，应用会自动改问魔搭（ModelScope）和 hf-mirror.com 的镜像——也可以在模型面板里自己选择，安装进行中会锁定。无论哪个来源，每个文件都按配方固定的 sha256 校验后才入库（[文档](docs/HUB-SOURCES.md)）。

### 4. CLI 暴露的新能力（`silicontrol`）

原应用的 `silicontrol` 本就能在终端驱动渲染（[文档](docs/REMOTE-CONTROL.md)）；本仓库把新的编辑分支也暴露给了它：

- `add --mask 蒙版 --mode remove|redraw`：移除与局部重绘；
- `add --lora expand --pad L,R,T,B --image 图片`：扩图（预设 0.7 自动接线，掩码被拒）；
- `upscale 文件 [目标] [--scale N]`：SeedVR2 放大，直接处理文件，无需应用。

## 下载

原版应用以 `.dmg` 发布于上游的 [Releases](https://github.com/gwenn-ha-dev/Siliconed/releases) 页面；本仓库的改动目前需要自行构建（[从源码构建](docs/ENGINE.md#build-from-source)，需要 Xcode 26 或更高版本）。系统要求：macOS 26 或更高版本，Apple 芯片。应用不预装任何模型：你在应用内挑选模型，阅读各自的许可证，然后才开始下载。

## 原应用能做什么（概览）

- **文字作画，按指令编辑**；**包围曝光网格**（每个格子一张成品图）；**Prompt Lab**（按模型风格改写提示词、描述图片，beta）；**导入自己的模型**（Civitai / Hugging Face 的 LoRA 与微调）；**本地且私密**（无内容过滤器，历史不出机器）；**在另一台 Mac 上渲染**（配对一次，全程加密）；**可脚本化**（`silicontrol`）。应用导览：[docs/APP.md](docs/APP.md)。

![The Siliconed window: the rack on the left (text, text encoder, DiT, VAE decoder, each with its settings and time), the Krea 2 Turbo surf photo in the middle, the Prompt Lab folded to one line beneath it, the history on the right](docs/images/window.jpg)

## 文档

原项目的文档（本仓库继续维护）：

- [docs/APP.md](docs/APP.md)：应用详解；[docs/ENGINE.md](docs/ENGINE.md)：引擎、性能数据、内存预算；[docs/VERIFY.md](docs/VERIFY.md)：在你的 Mac 上核验；[docs/REMOTE-CONTROL.md](docs/REMOTE-CONTROL.md)：`silicontrol` 与协议；[docs/RELEASE-NOTES.md](docs/RELEASE-NOTES.md)：每个版本的变更。

本仓库新增：

- [docs/MASK-WORKFLOW.md](docs/MASK-WORKFLOW.md)：移除/局部重绘工作流解析与对齐；[docs/EXPAND-WORKFLOW.md](docs/EXPAND-WORKFLOW.md)：扩图工作流解析与集成；[docs/HUB-SOURCES.md](docs/HUB-SOURCES.md)：下载源设计与实现。

## 致谢

原项目 Siliconed 由 Gwenn 开发——本仓库的全部新增工作都站在它的地基上。模型归其发布方所有，各自遵循自己的许可证；参考实现是 Hugging Face 的 [diffusers](https://github.com/huggingface/diffusers) 和 [transformers](https://github.com/huggingface/transformers)，图像重采样逐比特复刻了 [Pillow](https://github.com/python-pillow/Pillow) 的 Lanczos。Qwen-Image-2.1 的移除/重绘/扩图对齐，特别感谢孤海（[Goohai](https://github.com/goohai/Goohaitools-comfyui)）开源的 ComfyUI 工作流「Qwen-2.1 移除、局部重绘、扩图」——它们是本项目的参考实现源；工作流 LoRA 来自 Civitai 社区；MOSS-Image 的 8 步配方来自 lodestones 的 [DMD LoRA](https://huggingface.co/lodestones/MOSS-Image-SFT-8-steps-dmd)；放大功能基于 SeedVR2（字节跳动 Seed 团队）。

## 许可证

代码采用 [Apache License 2.0](LICENSE)：原项目版权归其作者 Gwenn 所有，本仓库的修改按同一许可证提供，原作者的版权与许可声明原样保留。模型权重不属于本仓库：每个模型由你自己下载，遵循各自的许可证，应用会在安装前展示这些许可证。
