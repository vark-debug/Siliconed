import Foundation

// **The request: what a render is asked for** — the prompt, the format, the seed, the LoRA stack
// (`LoRAEntry`), the images — whatever the model. The chain that runs it is in `Chain.swift`.

// ── the request ──────────────────────────────────────────────────────────────────────────────

/// A LoRA of the stack: a forged map (`ForgeLoRA`) and its strength.
///
/// **A strength is a `Double` everywhere in the API** (a LoRA's as well as img2img's); the LoRA
/// brings it down to `Float` at merge time, where it multiplies fp32 weights.
package struct LoRAEntry: Sendable, Hashable {
    package var path: String
    package var strength: Double
    package init(_ path: String, strength: Double = 1) { self.path = path; self.strength = strength }

    /// `carte.silicon:0.8,autre.silicon:0.5` — the syntax of the CLI's `SILICONED_LORA`. A missing or
    /// unreadable strength is 1. An entry made only of colons (`:`) names no file: it is kept as
    /// written, so the render refuses it by name (`EngineError.fileMissing(path: ":")`) rather than
    /// the parse trapping on a piece that is not there.
    package static func stack(_ text: String) -> [LoRAEntry] {
        text.split(separator: ",").map { entry in
            let pieces = entry.split(separator: ":")
            guard let path = pieces.first else { return LoRAEntry(String(entry)) }
            return LoRAEntry(String(path),
                              strength: pieces.count > 1 ? Double(Float(pieces[1]) ?? 1) : 1)
        }
    }

    /// `popart100` — the short form a file name carries.
    package var shortTag: String {
        let base = (((path as NSString).lastPathComponent) as NSString).deletingPathExtension
            .replacingOccurrences(of: ".lora", with: "").lowercased().prefix(12)
        return "\(base)\(Int((strength * 100).rounded()))"
    }
}

/// **A request, and everything that distinguishes it from another — whatever the model.** What is
/// specific to a model (Qwen-Image-2.1's spectral schedule, for instance) lives on its module.
///
/// **Building a request reads nothing** — neither the machine's profile nor a file: what depends
/// on them is resolved at render time. An app can therefore hold
/// one in its state before having chosen its library and loaded its profile.
package struct Request: Sendable, Equatable {
    package var prompt: String
    /// The image's format, in pixels. See `Format` for what is accepted. Changing it refits the
    /// input image — from the **already-fitted** image: to change format without losing edges,
    /// set the source image again (`image = …`) after the format.
    package var width: Int { didSet { fit() } }
    package var height: Int { didSet { fit() } }
    package var seed: UInt64
    /// `nil`: the denoiser's default (`ModelCard.defaultSteps`). At least 1, otherwise the render
    /// throws `EngineError.invalidSteps` before any computation.
    package var steps: Int?
    /// **A schedule a caller supplies** (the engine's API; `silicontrol` reaches a graph's
    /// `ManualSigmas` through `--steps 9`): `steps + 1` σ, the last 0, strictly decreasing — rather
    /// than the artifact's published `sample_sigmas`. `nil`: the family's own schedule, the product's
    /// path (to the bit).
    ///
    /// Only the denoisers whose `check(sigmas:startImage:)` accepts one read it (Qwen-Image-2.1's
    /// Turbo does — 9 steps and the extra 0.150000 of a ComfyUI graph, for one); the others refuse
    /// it before any computation. When it is set, `steps` follows its length: `steps + 1` values.
    package var sigmas: [Float]? = nil
    /// **The area the reference images are encoded at** (`R` in `QwenImage21Pipeline`'s
    /// `calculate_dimensions(R², w/h)`: the reference is ~`R²` pixels, its own ratio kept, sides at 32).
    /// `nil`: the published `R = 1024` (~1 MP), to the bit — the pipeline's default and the product's.
    /// Only Qwen-Image-2.1 reads it (its references, and the memory need they charge); the other
    /// families ignore it. The **output size's rule never reads it**: an edit's format still follows
    /// `QwenImage21Pipeline.outputSize` at 1024². Bounds: 768 to 2560, a multiple of 32
    /// (`Request.admit(referenceResolution:)`).
    package var referenceResolution: Int? = nil
    package var loras: [LoRAEntry]
    /// **The img2img starting image.** Set at any size, it is **immediately** filled and
    /// center-cropped to the request's format (`ImageRGB.fitted`): a request never keeps a
    /// full-size photo (48 Mpx would weigh 576 MB of floats for the whole render). `nil`: txt2img
    /// — one way of doing things, not two APIs.
    package var image: ImageRGB? { didSet { fit() } }
    /// diffusers' `strength` (`Strength`), in `]0 ; 1]`. No effect without `image`.
    package var strength: Double
    /// **The crop an additive start redraws** — the « 移除、局部重绘 » workflow's initial latent: the
    /// chain's image encoder turns it into z₀, and the seed's noise is **added** to it at the schedule's
    /// first σ (`Latent.seeded`: `z₀ + σ₀·ε`, a ComfyUI graph's `noise_scaling`) instead of
    /// `Latent.start`'s `σ₀·ε + (1 − σ₀)·z₀`, which at σ₀ = 1 is pure noise. **Fitted to the render's
    /// format when it is encoded** (like `image`), so z₀ must come out at the render's latent grid —
    /// it does not, the render throws `invalidSeededStart`.
    ///
    /// `nil`: no additive start — txt2img, img2img (`image`) and an edit by references are untouched,
    /// to the bit. Only a denoiser whose `acceptsSeededStart` says so reads it (Qwen-Image-2.1's Turbo);
    /// every other family, and a request that also carries `image`, refuses it before any computation
    /// (`Admission`). It always starts at step 0: `strength` has no effect on it. With a σ table
    /// (`sigmas`), σ₀ is its first value — which need not be 1, and `z₀ + σ₀·ε` is then the start
    /// as defined, not a rescaled one.
    package var seededStart: ImageRGB? = nil
    /// **A 「移除」 patch** (`Patch`): the image, its mask and the crop's margins, as the ComfyUI
    /// workflow's mask branch. The engine crops the image, tints the crop green, and hands the crop to
    /// the text encoder as its first image — the denoiser's reference block — and, **only when
    /// `patchSeededStart` says so**, to the additive start (`z₀`). The render's format is the plan's
    /// size, whatever `width` and `height` say (`Admission` takes the plan's).
    /// Refused beside `image`, `seededStart` or `references`, and by a denoiser without `acceptsSeededStart`
    /// (Qwen-Image-2.1's Turbo). `nil`: the path is not taken, and nothing else changes.
    package var patch: Patch? = nil
    /// **The patch's encoded start, opt-in** (`--seeded-start`): the crop becomes z₀ and the seed's
    /// noise is added to it (`Latent.seeded`: `z₀ + √2·ε` at σ₀ = 1, ComfyUI's `max_denoise` branch),
    /// as the workflow's `Text Encode Qwen Image 2.1 GH` keeps its primary latent. **Off by default**:
    /// the crop is image 1 alone, and the render starts from noise — measured on a 9-step manual
    /// schedule, where a third of the crop at z₀ kept the tint the prompt asked to remove, while the
    /// same pixels as a reference alone removed it (the crop's detail energy 10.95 → 21.76, near the
    /// original's 22.58). Refused without `patch`: there is no crop to start from.
    package var patchSeededStart = false
    /// **The crop kept alone** (`--crop-only`): false — the workflow's `GH_CropRestore` — lays the
    /// decoded crop back at its place in the original (`Patch.composited`), so the image delivered is
    /// the original's size; true returns the crop itself, at the plan's size, to compare the two.
    /// Refused without `patch`: there is no crop to keep.
    package var patchCropOnly = false
    /// **The workflow's `noise_mask`, opt-out** (`--noise-mask` turns it back on): true — the
    /// `Patch.Settings.noiseMask` default, as the workflow's `Text Encode Qwen Image 2.1 GH` attaches
    /// the mask whenever its primary latent is the crop — makes every step replace the model's estimate
    /// outside the mask (grown 30 px, feathered, on the latent grid) with the crop's own latent `z₀`,
    /// inside it with the model's (`KSamplerX0Inpaint`'s `out·mask + latent_image·(1−mask)`).
    /// **With `patchSeededStart`** the start stays `z₀ + √2·ε`; the backfill is `z₀`, never the noise.
    /// False: the whole crop is rebuilt, and the mask only tints. Refused without `patch`.
    package var patchNoiseMask = false
    /// **A 「扩图」 expand** (`Expand`): the image, the percents its canvas grows by, the sampling
    /// ceiling. The engine builds the grey canvas, stretches it to the plan's size and hands it to the
    /// text encoder as image 1 — the denoiser's reference block, **with no noise-mask** — starts from
    /// pure noise at the plan's size, and lays the original back inside the decoded canvas
    /// (`Expand.composited`): the image delivered is the **canvas's size**. The render's format is the
    /// plan's size, whatever `width` and `height` say (`Admission` takes the plan's), and the prompt
    /// the model reads is `Expand.prompt`'s — the workflow's fixed sentence leading, an empty
    /// supplement allowed. Refused beside `patch`, `image`, `seededStart` or `references`. `nil`: the
    /// path is not taken, and nothing else changes.
    package var expand: Expand? = nil
    /// **The editing reference images** ("change her jacket to red"): the denoiser re-reads them
    /// at each layer, and the generated image starts from noise — nothing to do with `image`,
    /// which is its starting point. Each keeps **its own** aspect ratio, at the size the denoiser
    /// gives it (`DenoisingModule.preparedReferences`): Qwen-Image-2.1 at ~1024² at multiples of 32
    /// (Pillow's Lanczos) — whatever the request's format.
    /// Qwen-Image-2.1's encoder also SEES them: the prompt names them `<image1>`, `<image2>`… in this
    /// order, and the first is the image being edited. Empty: no editing. Only the denoisers that
    /// announce it read them (`maxReferences`: 3 for Qwen-Image-2.1).
    package var references: [ImageRGB] = []
    /// **A preview at each step** (`Event.preview`, `Engine.Preview`). False by default: nothing
    /// is then computed or copied.
    package var previews: Bool
    /// **More detail** (`Detail`): the denoiser is told, mid-trajectory, that a little less noise
    /// remains than really does, and leaves finer texture. Same evaluations, same cost; `normal` is
    /// the render without it, to the bit. The models whose `DenoisingModule.acceptsDetail` says so
    /// honour it — Z-Image and Qwen-Image-2.1, not Anima nor Krea 2.
    package var detail: Detail = .normal
    /// **The update rule of each step** (`Solver`): Euler, the one the Turbo models were distilled
    /// for, unless another is asked — the same steps, the same σ, another walk between them. Only the
    /// models whose `DenoisingModule.solvers` name it accept it; the app offers them in Developer Mode.
    package var solver: Solver = .euler
    /// **Variations** (`Variation`): the seed's starting noise turned towards other seeds', in order —
    /// cousins of the image `seed` gives, its composition kept in proportion to `strength`
    /// (`Variation.Amount`). Empty: the seed's noise, to the bit. Only the noise changes:
    /// the text, the images and the render cache's keys do not see it. In a batch, each seed is turned
    /// by the same variations.
    package var variations: [Variation] = []
    /// **« Accelerators »: the Neural Engine and the GPU's tensor units in half precision, in the denoiser**, where this Mac's plan
    /// chooses them (`Accelerators`, resolved at admission):
    ///   - the Neural Engine beside the GPU (`EngineSettings.plan.usesANE`): the products it takes run in fp16, each weight column and
    ///     activation row lifted into fp16's range and undone in fp32 (`NeuralEngine`) — less energy, and another image than fp32's,
    ///     close to it (at 1024², Z-Image's and Qwen-Image-2.1's within a tenth of a level on average, Krea 2's finest details moved);
    ///   - the GPU's tensor units on rounded operands: an activation rounded to bf16 before a product on a bf16 weight (`bf16act`),
    ///     the attention on bf16 or fp16 operands (`tilesbf16`, `tiles16`), the sums fp32 — checked against the reference in bf16.
    /// False: the denoiser in fp32 throughout (`CapacityPlan.restricted(accelerators:)`), the image the fp32 checks compare with the
    /// reference. It can only turn them off: where the map chooses none, true changes nothing. The encoders never take them.
    package var accelerators = true
    /// The switch's name before it covered the GPU's tensor units (`accelerators`): what callers written then still set.
    package var neuralEngine: Bool {
        get { accelerators }
        set { accelerators = newValue }
    }
    /// **« Faster Rendering »**: the family's first evaluations on the half grid (`Spectral.reducedEvaluations`) — a quarter to a third
    /// faster at 1024² and above, **another image than the recipe at full size**, which is why it is a field of the request and not a
    /// setting of the machine: the same request renders the same image, whatever else runs. Off by default (the CLI, the checks and the
    /// judge render the recipe); the app sets it from its setting. Where the family's rule refuses it (a LoRA, Detail, an edit, another
    /// step count, a format that does not halve), true changes nothing.
    package var fasterRendering = false

    /// The most steps a request may ask for. The Turbo models are distilled for 6 to 8; the cap is
    /// there for what does not come from the stepper — a PNG's metadata, `silicontrol --steps`, the
    /// API — where 2·10⁹ steps would allocate the schedule (8 GB) before the first evaluation.
    package static let maximumSteps = 50

    /// What a request refuses, before any computation.
    package enum Failure: Error, CustomStringConvertible, Equatable {
        /// An empty or blank prompt: every model refuses it (Anima would have no token to
        /// encode; the others would render an image nothing asked for).
        case emptyPrompt
        /// A number of steps outside `1...maximumSteps`.
        case steps(Int)
        /// More references than the denoiser reads (0: it reads none).
        case references(Int, max: Int)
        /// A solver the model's sampler does not walk.
        case solver(Solver, model: String)
        /// More or Most detail asked of a model that does not offer it.
        case detail(model: String)
        /// A prompt longer than its encoder reads, counted without the template (`admitPrompt`).
        case promptTooLong(tokens: Int, max: Int)
        /// A σ table the engine cannot walk (`admit(sigmas:)`): what is wrong with it.
        case schedule(String)
        /// A σ table given to a denoiser that reads its artifact's schedule only.
        case noCustomSchedule(model: String)
        /// A reference resolution outside the pipeline's bounds (`admit(referenceResolution:)`): what is wrong with it.
        case referenceResolution(String)
        /// **An additive start the model, or the request, cannot take** (`seededStart`): `why` says
        /// which — a denoiser without one, an img2img image beside it, or an encoded crop off the grid.
        case seededStart(String)
        package var description: String {
            switch self {
            case let .references(n, max) where max == 0:
                return "\(n) reference image(s): this model does no reference editing (Qwen-Image-2.1 does)"
            case let .references(n, max):
                return "\(n) reference images: this model reads at most \(max)"
            case .emptyPrompt: return "empty prompt: there is nothing to render"
            case .steps(let n): return "\(n) steps: a render takes between 1 and \(Request.maximumSteps)"
            case let .solver(solver, model): return "\(model) does not offer the \(solver.rawValue) solver"
            case .detail(let model): return "\(model) does not offer Detail"
            case let .promptTooLong(tokens, max):
                return "the prompt is \(tokens) tokens long, this model reads at most \(max): shorten it"
            case .schedule(let why):
                return "the σ table is refused: \(why)"
            case .noCustomSchedule(let model):
                return "\(model) walks the schedule of its artifact: it takes no σ table"
            case .referenceResolution(let why):
                return "the reference resolution is refused: \(why)"
            case .seededStart(let why):
                return "the seeded start is refused: \(why)"
            }
        }
    }

    /// **The longest prompt any family renders: 1 024 tokens** of the prompt alone, the template's
    /// left out — per tokenizer when a family has two (Anima). diffusers cuts Z-Image, Anima and Krea 2
    /// at 512 (`max_sequence_length`, a pipeline default, not a bound of the models: their DiTs and
    /// RoPE take longer texts) and does not bound Qwen-Image-2.1; ComfyUI bounds none of them, and the
    /// long prompts users share are written there. 1 024 is Qwen-Image's own cut; past 512 the models
    /// read texts longer than diffusers ever hands them.
    package static let maximumPromptTokens = 1024

    /// **No prompt is ever cut in silence**: past its bound a prompt is refused, so an image always
    /// answers the whole prompt. `tokens` and `max` count the prompt's own tokens, the template's left
    /// out: what the user can shorten.
    package static func admitPrompt(tokens: Int, max: Int) throws {
        guard tokens <= max else { throw Failure.promptTooLong(tokens: tokens, max: max) }
    }

    /// **A σ table the request supplies is walkable**: at least two σ, finite, strictly decreasing, and
    /// ending in 0 — the sampler divides by the gaps between σ, so any other table would divide by zero
    /// or walk backwards. Returns the step count the table's length gives (`sigmas.count - 1`), so that
    /// `Admission` can hold it against `Request.steps` when both are given.
    ///
    /// The shape is all this method judges: whether a *denoiser* walks this particular table is
    /// `DenoisingModule.check(sigmas:startImage:)`'s (Qwen-Image-2.1's Turbo does — the ComfyUI graph's
    /// nine, among others).
    package static func admit(sigmas: [Float]) throws -> Int {
        guard sigmas.count >= 2 else {
            throw Failure.schedule("\(sigmas.count) σ: a schedule needs at least two, the last 0")
        }
        guard sigmas.count - 1 <= maximumSteps else {
            throw Failure.schedule("\(sigmas.count) σ: a render takes at most \(maximumSteps) steps")
        }
        guard sigmas.allSatisfy({ $0.isFinite }) else {
            throw Failure.schedule("a σ is not a finite number")
        }
        guard let last = sigmas.last, last == 0 else {
            throw Failure.schedule("the last σ must be 0, not \(sigmas.last.map { String($0) } ?? "none")")
        }
        for (i, (σ, next)) in zip(sigmas, sigmas.dropFirst()).enumerated() where σ <= next {
            throw Failure.schedule("the σ do not decrease strictly: #\(i) is \(σ), #\(i + 1) is \(next)")
        }
        return sigmas.count - 1
    }

    /// **A reference resolution the request supplies is one the pipeline has a size for**
    /// (`referenceResolution`: `R`, the area's side). `nil` is the published 1024 and needs no check.
    /// Qwen-Image-2.1's `calculate_dimensions` rounds each side to a multiple of 32; `R` itself must be
    /// one too (the workflow's crop sizes are), between 768 and 2560 — the bounds of its 长边 crop.
    /// Refused with `Failure.referenceResolution` rather than a resize the memory need would not see.
    package static func admit(referenceResolution: Int?) throws {
        guard let resolution = referenceResolution else { return }
        guard QwenImage21Pipeline.minimumReferenceResolution...QwenImage21Pipeline.maximumReferenceResolution
                ~= resolution else {
            throw Failure.referenceResolution("\(resolution) px: the reference resolution is "
                + "\(QwenImage21Pipeline.minimumReferenceResolution) to \(QwenImage21Pipeline.maximumReferenceResolution)")
        }
        guard resolution % QwenImage21Pipeline.referenceResolutionMultiple == 0 else {
            throw Failure.referenceResolution("\(resolution) px: not a multiple of \(QwenImage21Pipeline.referenceResolutionMultiple)")
        }
    }

    package init(_ prompt: String, width: Int, height: Int, seed: UInt64 = 42, steps: Int? = nil,
                loras: [LoRAEntry] = [], image: ImageRGB? = nil, strength: Double = Strength.defaultValue,
                previews: Bool = false) {
        self.prompt = prompt; self.width = width; self.height = height; self.seed = seed
        self.steps = steps; self.loras = loras; self.image = image; self.strength = strength
        self.previews = previews
        fit()   // `didSet` does not run inside an `init`
    }

    /// The `resolution × resolution` square — the common case, written short.
    package init(_ prompt: String, resolution: Int = 1024, seed: UInt64 = 42, steps: Int? = nil,
                loras: [LoRAEntry] = [], image: ImageRGB? = nil, strength: Double = Strength.defaultValue,
                previews: Bool = false) {
        self.init(prompt, width: resolution, height: resolution, seed: seed, steps: steps,
                  loras: loras, image: image, strength: strength, previews: previews)
    }

    /// The image at the current format. A format refused by `Format` is not fitted (the render
    /// will throw on the format, not here); an image already at the format comes back as is, bit
    /// for bit.
    private mutating func fit() {
        guard let source = image, source.width != width || source.height != height,
              (try? Format.check(width: width, height: height)) != nil else { return }
        image = source.fitted(width: width, height: height)
    }
}
