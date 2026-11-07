import Foundation

/// **What a request is, once the chain has judged it — before any computation, any memory and any file.**
/// Pure: a request, a chain and one fact about the plan (does it bring up the Neural Engine?) go in; the grid in latent cells, the
/// steps and the starting step, the denoiser's plan and the two switches the render reads (Neural Engine, « Faster Rendering ») come out,
/// each **resolved here once** — the render, its memory need and its `Context` all read this value, never the settings again.
///
///     refusals, in this order    empty prompt · steps outside 1…maximumSteps · img2img (encoder, strength) · references ·
///                                an additive start (`Request.seededStart`) · the denoiser's own `check` · solver · detail ·
///                                a strength that leaves no evaluation
///     then                       the plan (`DenoisingModule.plan`): a LoRA or a Detail turns the half-size start off, and so do
///                                references and an additive start (`DenoisingPlan.unreduced`: the plan cannot see them, the chain can)
///
/// A request the model cannot render is refused for what it is, not for its memory: the preflight (`Preflight`) comes after.
package struct Admission: Sendable {
    package let space: LatentSpace
    /// The latent grid (`request` pixels over the space's factor).
    package let height: Int, width: Int
    package let steps: Int
    /// The first step executed (0 in txt2img, and 0 with an additive start: the crop is in the latent, not in the strength).
    package let start: Int
    package let plan: DenoisingPlan
    /// **The additive start's σ₀** (`Request.seededStart`): the first node of the schedule the render walks — the request's
    /// table when it gave one (whose first value need not be 1), the family's otherwise. `nil`: no additive start (`Latent.seeded`
    /// is never called); the img2img path keeps reading `plan.startSigma`, untouched.
    package let seededSigma: Float?
    /// **The 「移除」 patch's crop** (`Request.patch`): the box in the original's pixels and the size the render will have —
    /// the render draws the green crop from it, for both z₀ and the text encoder's first image.
    package let patch: Patch.Plan?
    /// **What the denoiser may compute on beyond fp32**: the switch asked (`Request.accelerators`), the Neural Engine where the plan
    /// offers it (`usesANE`); off, fp32 throughout.
    package let accelerators: Accelerators
    /// The denoiser's products may take the Neural Engine: asked and offered by the plan.
    package var neuralEngine: Bool { accelerators.neuralEngine }
    /// « Faster Rendering » as the request asks it (`Request.fasterRendering`): the plan above already honours it.
    package let fasterRendering: Bool

    package static func judge(_ request: Request, chain: Chain, usesANE: Bool) throws -> Admission {
        guard !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Request.Failure.emptyPrompt
        }
        let denoising = chain.denoising, space = denoising.space
        var height = request.height / space.factor, width = request.width / space.factor
        var steps = request.steps ?? denoising.defaultSteps
        // **A σ table the request supplies** (`Request.sigmas`): the steps follow it (`steps + 1`
        // values, the shape checked — strictly decreasing, the last 0), and the denoiser's own
        // `check(sigmas:)` judges it below: a count its published schedule does not have
        // (Qwen-Image-2.1's 9) is its business, not this one's. A `steps` asked beside the table
        // must be the table's length: the two would otherwise disagree on the render.
        if let σ = request.sigmas {
            steps = try Request.admit(sigmas: σ)
            if let asked = request.steps, asked != steps {
                throw Request.Failure.schedule("\(σ.count) σ: \(steps) steps, but \(asked) was asked")
            }
        }
        guard (1...Request.maximumSteps).contains(steps) else { throw Request.Failure.steps(steps) }
        // The references' area is a shape of its own (Qwen-Image-2.1 alone reads it): judged here,
        // before the memory that charges it (`QwenImage21Need`).
        try Request.admit(referenceResolution: request.referenceResolution)
        // **The 「移除」 patch** (`Request.patch`): its crop decides the render's format, and it is its
        // own start rule — the crop is the text encoder's image 1 (and the denoiser's reference block),
        // and with `patchSeededStart` also z₀. Judged here, before img2img, references and an additive
        // start, which it cannot share the request with. `patch.plan()` throws `EngineError.invalidPatch`
        // for a mask of another size, an empty one, or an unusable crop.
        var seededSigma: Float?
        var patchPlan: Patch.Plan?
        // **The patch's encoded start is opt-in** (`Request.patchSeededStart`, `--seeded-start`): asked
        // without a patch, it has no crop to start from — refused for what it is, not ignored.
        if request.patchSeededStart, request.patch == nil {
            throw Request.Failure.seededStart("a seeded start adds the noise to a patch's crop: "
                + "--seeded-start goes with --mask, and without one the render starts from noise alone")
        }
        if let patch = request.patch {
            guard request.image == nil else {
                throw EngineError.invalidPatch(reason: "an img2img image (its strength) and a patch (its mask) start two ways: choose one")
            }
            guard request.seededStart == nil else {
                throw EngineError.invalidPatch(reason: "a seeded start and a patch, not both: the patch's crop is the start")
            }
            guard request.references.isEmpty else {
                throw EngineError.invalidPatch(reason: "a patch is the edit's only image: its crop is the text encoder's image 1")
            }
            guard chain.encoding != nil else {
                throw EngineError.invalidPatch(reason: "this chain has no image encoder to turn the patch's crop into z₀")
            }
            guard denoising.acceptsSeededStart else {
                throw EngineError.invalidPatch(reason: "\(denoising.model) starts from no additive latent (Qwen-Image-2.1's patch workflow is the one)")
            }
            let planned = try patch.plan()
            // **`--ref-res` has no image to prepare when the crop is the render's own size**: the crop
            // is image 1 and the reference block at that size (the workflow's primary latent), so N is
            // refused, not ignored. A crop of another proportion is prepared at N, like a reference.
            if planned.primaryMatchesTarget, request.referenceResolution != nil {
                throw EngineError.invalidReferenceResolution(reason:
                    "a --mask crop that is the render's own size (within \(Patch.coverTolerance) px a side) is prepared at that size: --ref-res does not apply — leave it out")
            }
            patchPlan = planned
            width = planned.width / space.factor
            height = planned.height / space.factor
            // The crop as z₀ only when asked (`--seeded-start`): the default render starts from noise
            // with the crop as image 1 alone.
            if request.patchSeededStart {
                seededSigma = (request.sigmas ?? denoising.sigmas(steps: steps)).first
            }
        }
        // **img2img is judged before any computation, too**: an out-of-range strength, a chain
        // without an encoder, a strength that leaves no evaluation all throw here.
        var start = 0
        // The strength's N is the schedule's length as diffusers' `get_timesteps` reads it (`len(timesteps)`): the
        // steps asked, but fewer where a family's schedule merges σs (MOSS-Image's, snapped to its training grid).
        let scheduled = request.sigmas.map { $0.count - 1 } ?? denoising.sigmas(steps: steps).count - 1
        if request.image != nil {
            guard chain.encoding != nil else { throw Strength.Failure.withoutEncoder(model: denoising.model) }
            guard request.strength > 0, request.strength <= 1 else { throw Strength.Failure.outOfBounds(request.strength) }
            start = Strength.startStep(steps: scheduled, strength: request.strength)
        }
        if !request.references.isEmpty {
            guard chain.encoding != nil, request.references.count <= denoising.maxReferences else {
                throw Request.Failure.references(request.references.count,
                                                 max: chain.encoding == nil ? 0 : denoising.maxReferences)
            }
        }
        // **The additive start** (the « 移除、局部重绘 » workflow's crop) is its own path, judged here
        // and refused for what it is: it is not img2img (no strength, start stays 0), and a model that
        // reads no such start, a chain without an encoder to turn the crop into z₀, or an img2img image
        // beside it (two start rules in one request) throws before any computation. Its σ₀ is the
        // schedule's first node as the render will walk it — a custom table's first value may be below 1,
        // and `z₀ + σ₀·ε` (`Latent.seeded`) is then the start as defined.
        if request.seededStart != nil {
            guard request.image == nil else {
                throw Request.Failure.seededStart("a request starts from one image at most: "
                    + "an img2img image (its strength) or a seeded start (the workflow's crop), not both")
            }
            guard chain.encoding != nil else {
                throw Request.Failure.seededStart("this chain has no image encoder to turn the crop into z₀")
            }
            guard denoising.acceptsSeededStart else {
                throw Request.Failure.seededStart("\(denoising.model) starts from no additive latent "
                    + "(Qwen-Image-2.1's patch workflow is the one)")
            }
            seededSigma = (request.sigmas ?? denoising.sigmas(steps: steps)).first
        }
        if let σ = request.sigmas {
            try denoising.check(sigmas: σ, startImage: request.image != nil)
        } else {
            try denoising.check(steps: steps, startImage: request.image != nil)
        }
        guard denoising.solvers.contains(request.solver) else {
            throw Request.Failure.solver(request.solver, model: denoising.model)
        }
        guard request.detail == .normal || denoising.acceptsDetail else {
            throw Request.Failure.detail(model: denoising.model)
        }
        // Detail, like a LoRA, turns Qwen-Image-2.1's spectral schedule off; an edit and an additive start too.
        let faster = request.fasterRendering
        var plan = denoising.plan(height: height, width: width, steps: steps, start: start,
                                  withLoRA: !request.loras.isEmpty || request.detail != .normal, faster: faster)
        if !request.references.isEmpty || request.seededStart != nil || patchPlan != nil { plan = plan.unreduced }
        guard plan.evaluations > 0 else {
            // The floor: the last start that keeps an evaluation, `d`, is reached as soon as
            // `N − N·s < d + 1`, i.e. `s > (N − d − 1)/N`.
            let last = (0..<scheduled).last {
                denoising.plan(height: height, width: width, steps: steps, start: $0,
                               withLoRA: !request.loras.isEmpty, faster: faster).evaluations > 0
            } ?? 0
            throw Strength.Failure.noEvaluation(strength: request.strength, steps: steps,
                                                floor: Double(scheduled - last - 1) / Double(scheduled))
        }
        // **The images the text encoder reads and the reference blocks the denoiser receives are one
        // list** (`QwenImage21Sequence`: each block fills the rows its image made, 4 × slots == h·w).
        // A patch's crop is image 1 and the denoiser's block; an edit's references are both; img2img's
        // image is neither. Judged here, before the encoder's minutes: the wiring C4 dropped in the
        // render threw at the end of the text stage (`2373 slots for 5376 image tokens`) — a chain that
        // cannot keep the two together is refused at the door instead.
        let textImages = chain.text is any ImageTextModule
            ? (patchPlan == nil ? request.references.count : 1) : 0
        let referenceBlocks = patchPlan == nil
            ? min(request.references.count, denoising.maxReferences)
            : min(1, denoising.maxReferences)
        guard textImages == referenceBlocks else {
            throw EngineError.referenceSequence(text: textImages, blocks: referenceBlocks)
        }
        return Admission(space: space, height: height, width: width, steps: steps, start: start, plan: plan,
                         seededSigma: seededSigma, patch: patchPlan,
                         accelerators: Accelerators(requested: request.accelerators, usesANE: usesANE), fasterRendering: faster)
    }
}
