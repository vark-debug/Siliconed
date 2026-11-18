[English](README.md) · [Français](README.fr.md) · 简体中文

# Siliconed

**在你的 Mac 上本地生成和编辑图像，使用近期的开放权重模型：全精度计算、对照原始代码逐一核验，内存占用从不超过固定预算。**

Siliconed 是一款免费开源的 macOS 应用，可在 Apple 芯片 Mac（M1 及更新机型）上进行**本地文生图和图像编辑**。它以 Swift 和 Metal 原生运行近期的扩散模型——[Krea 2 Turbo](https://huggingface.co/krea/Krea-2-Turbo)、[Z-Image Turbo](https://huggingface.co/Tongyi-MAI/Z-Image-Turbo)、[Qwen-Image-2.1 Turbo](https://huggingface.co/Qwen/Qwen-Image-2.1-Turbo)、[Anima Turbo](https://huggingface.co/circlestone-labs/Anima) 和 [MOSS-Image](https://huggingface.co/OpenMOSS-Team/MOSS-Image-SFT)（beta：其 8 步配方来自社区）——无需 Python，无需服务器，无需云端，任何数据都不会离开你的 Mac。模型安装完成后即可离线使用。

一位开发者，一台 16 GB 的 MacBook Pro，以及一条不容妥协的规则：凡是无法对照原始代码核验的结果，一律不予发布。剩下的，就是看着一个 129 亿参数的模型在一台纸面上根本不该跑得动的笔记本上运行时的纯粹喜悦。

![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-M1%20and%20later-black)
[![unit tests](https://img.shields.io/github/actions/workflow/status/gwenn-ha-dev/Siliconed/test.yml?branch=main&label=unit%20tests)](https://github.com/gwenn-ha-dev/Siliconed/actions/workflows/test.yml)
[![kernels checked, CPU stages](https://img.shields.io/github/actions/workflow/status/gwenn-ha-dev/Siliconed/kernels.yml?branch=main&label=kernels%20checked%2C%20CPU%20stages)](https://github.com/gwenn-ha-dev/Siliconed/actions/workflows/kernels.yml)

![A sunny Krea 2 Turbo photo — a laughing red-haired Irish woman in a shorty wetsuit wading out of the shore break, her surfboard under her arm, backlit by a low sun — and its cel-shaded western comic-book edit by Qwen-Image-2.1, under a sliding curtain](docs/images/curtain.gif)

*一张来自 Krea 2 Turbo 的照片，由 Qwen-Image-2.1 用一句话编辑（“Convert this photo to a western comic book style with cel shading”，种子 42），在拉幕对比中呈现。*

## 下载（就是一个 .dmg，没有任何花哨的东西）

应用以 `.dmg` 形式发布在 [Releases](https://github.com/gwenn-ha-dev/Siliconed/releases) 页面。系统要求：macOS 26 或更高版本，Apple 芯片。应用不预装任何模型：你在应用内挑选模型，阅读各自的许可证，然后才开始下载。若要自行构建：[从源码构建](docs/ENGINE.md#build-from-source)；需要 Xcode 26 或更高版本（仅靠 Command Line Tools 无法构建该应用）。

## 它能做什么

- **文字作画，按指令编辑。** Qwen-Image-2.1 Turbo 接受 1 到 3 张图和一句话（“把阴天的天空换成蓝天”），并且只改动你点名的部分。哪个模型适合什么用途，以及许可证和体积：[模型](docs/APP.md#models)。
- **像相机一样包围曝光。** 改变一个词、种子、某个 LoRA 的强度、LoRA 组合、Detail 或起始图像：每个格子出一张成品图，并排铺在画布上，每一张都是单次渲染能得到的那张图。
- **替你写提示词**（beta）。Prompt Lab 会按每个模型偏好的风格改写一句短提示词，或者描述你拖进去的一张图。它使用你已安装的模型，且绝不会在图像渲染时运行。
- **接受你自己的模型。** 从 Civitai 或 Hugging Face 导入 LoRA 和微调模型。
- **本地且私密。** 渲染在你的 Mac 上进行，应用不附加任何内容过滤器，也不向任何地方发送历史记录。它跟随系统语言（英语、法语、德语、西班牙语、意大利语、日语或简体中文）。
- **在另一台 Mac 上渲染。** 你的 MacBook 可以调用隔壁房间 Mac mini 的算力，只需配对一次，全程加密（[如何操作](docs/APP.md#render-on-another-mac)）。
- **可脚本化。** `silicontrol` 可以在终端驱动正在运行的应用，适合脚本和编码智能体使用（[详情](docs/REMOTE-CONTROL.md)）。

![The Siliconed window: the rack on the left (text, text encoder, DiT, VAE decoder, each with its settings and time), the Krea 2 Turbo surf photo in the middle, the Prompt Lab folded to one line beneath it, the history on the right](docs/images/window.jpg)

应用导览：[docs/APP.md](docs/APP.md)。

## 那么为什么要费这个劲

- **快，但不偷工减料。** 在完成全部测试的那台 16 GB M1 Pro 上，1024² 分辨率，按各家配方要求以全尺寸跑满全部 8 次评估（模型的完整执行次数）：Qwen-Image-2.1 Turbo 用时 85.8 秒，Z-Image Turbo 用时 101.9 秒，Krea 2 Turbo 用时 140.9 秒，均使用应用推荐的 Compact 版（8 比特权重的模型，磁盘占用减半；[三个版本](docs/APP.md#model-management)）。每次计算都会分派到这台 Mac 实测出的 GPU、CPU 矩阵单元或神经网络引擎。在全精度下，即发布方的 bf16 权重以 fp32 计算时：分别为 135.6 秒、113.1 秒和 213.3 秒。[全部数据](docs/ENGINE.md#numbers)。
- **大模型，小 Mac。** 在 16 GB 的 Mac 上跑 34 GB 的模型，听起来是个坏主意。权重在需要时才从磁盘读取，Siliconed 占用的内存从不超过 Mac 内存的 ¾ 减去 2 GB，这个预算绝不突破。每次渲染在开始前先算好自己需要什么；超出预算的请求会被礼貌地当场拒绝。[测量方法](docs/ENGINE.md#memory-and-the-budget)。
- **即使在 8 GB 的 MacBook Neo 上也行。** 就是那台用 iPhone 芯片（A18 Pro）的机型：在 0.19 版本下，Anima Turbo 在它上面用 Compact 版、每次评估全尺寸，一分钟内就能出一张 1024² 的方图。我们已经没有 Neo 可以认真计时了：如果你有一台，或者一台我们从未见过的 Mac，[把你的数据发给我们](docs/ENGINE.md#on-a-macbook-neo)。
- **对照原始模型核验，近乎执念。** 每个阶段都与参考实现（CPU 上 fp32 的 diffusers / transformers）逐通道比对，无法核验的部分不予发布。亲自运行核验：[VERIFY.md](docs/VERIFY.md)。每当引擎有改动，CI 都会运行各内核的 CPU 阶段；它的 GPU 是虚拟的，所以 GPU 阶段要在你的 Mac 上运行。
- **了解你的 Mac。** 在首次渲染前，大约一分钟（最多五分钟）、不需要任何模型，它会测量你 Mac 的每个引擎——GPU、CPU 矩阵单元、神经网络引擎——单独和协同时的计算能力，并将每个结果与精确值核对；然后为每次渲染的每个乘积和每个注意力计算如何在算得对的引擎之间分配行。[如何做到](docs/ENGINE.md#an-engine-measured-on-your-mac)。
- **与 Draw Things 的引擎同机对比实测。** 方法和全部数字见[与 Draw Things 对比](docs/ENGINE.md#next-to-draw-things)。

## 文档

- [docs/APP.md](docs/APP.md)：应用详解：创作、编辑、撰写提示词、系列、模型管理、设置、隐私。
- [docs/ENGINE.md](docs/ENGINE.md)：引擎：测量你的 Mac、神经网络引擎、性能数据、Faster Rendering、Draw Things、内存、社区诊断、核验、从源码构建。
- [docs/VERIFY.md](docs/VERIFY.md)：在你的 Mac 上对照参考实现核验结果。
- [docs/REMOTE-CONTROL.md](docs/REMOTE-CONTROL.md)：`silicontrol`，协议与内部实现。
- [docs/RELEASE-NOTES.md](docs/RELEASE-NOTES.md)：每个版本的变更内容。
- 问题反馈：[诊断报告、bug、想法](https://github.com/gwenn-ha-dev/Siliconed/issues/new/choose)。

## 致谢

模型归其发布方所有（列于[模型](docs/APP.md#models)之下），各自遵循自己的许可证。参考实现是 Hugging Face 的 [diffusers](https://github.com/huggingface/diffusers) 和 [transformers](https://github.com/huggingface/transformers)；图像重采样逐比特复刻了 [Pillow](https://github.com/python-pillow/Pillow) 的 Lanczos。LoRA 和微调模型来自 [Civitai](https://civitai.com) 和 [Hugging Face](https://huggingface.co) 上的社区；MOSS-Image 的 8 步配方来自 lodestones 的 [DMD LoRA](https://huggingface.co/lodestones/MOSS-Image-SFT-8-steps-dmd)。

## 许可证

代码采用 [Apache License 2.0](LICENSE)。模型权重不属于本仓库：每个模型由你自己下载，遵循各自的许可证，应用会在安装前展示这些许可证。
