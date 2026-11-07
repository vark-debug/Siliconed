import Foundation
import os

// **The engine's render, stage by stage** (`Engine.render`, `renderBatch`): text, [image encoding,]
// denoising, decoding, each in its own scope. The modules and the chain are in `Chain.swift`.

extension Engine {
    /// **Renders an image. Blocks, and serializes concurrent calls** — the form for the CLI and
    /// tools; an app takes the `async` facade (`Facade.swift`), with the same parameters in the
    /// same order. `cancellation`: raised from another thread, the render stops at the next layer
    /// boundary and throws `EngineError.cancelled`, memory returned. `onProgress` is called on the
    /// render thread. A custom chain goes through a `Model(card:chain:)`. **Throws only
    /// `EngineError`**, the preflights first (`Preflight`).
    package func render(_ request: Request, model: Model, cancellation: Cancellation? = nil,
                       onProgress: (@Sendable (Event) -> Void)? = nil) throws(EngineError) -> Render {
        try renderBatch(request, seeds: [request.seed], model: model, cancellation: cancellation,
                      onProgress: onProgress)[0]
    }

    /// **A batch: the same request under several seeds**, the text (and the input image) encoded
    /// **only once**. `request.seed` is ignored. Each image has its events (`stage(_, image: n)`,
    /// `step(image: n, …)`, `image(index: n, …)`) and its `Render`; cancellation is checked between
    /// two images as everywhere else.
    package func renderBatch(_ request: Request, seeds: [UInt64], model: Model, cancellation: Cancellation? = nil,
                          onProgress: (@Sendable (Event) -> Void)? = nil) throws(EngineError) -> [Render] {
        // Called from the engine's own queue (a progress closure, a warning receiver), `sync` below would wait for itself for ever.
        dispatchPrecondition(condition: .notOnQueue(Engine.file))
        return try EngineError.boundary {
            try Engine.file.sync { try execute(request, seeds, model, cancellation, onProgress) }
        }
    }

    /// The same batch, called **from** the engine queue (the `async` facade is already on it).
    func renderBatchOnQueue(_ request: Request, seeds: [UInt64], model: Model, cancellation: Cancellation?,
                            onProgress: (@Sendable (Event) -> Void)?) throws -> [Render] {
        dispatchPrecondition(condition: .onQueue(Engine.file))
        return try execute(request, seeds, model, cancellation, onProgress)
    }

    /// **The render, stage by stage — a batch of one image or more.**
    ///
    /// The text and the input image each live in their own scope and return their memory before
    /// the DiT; only what they produce survives (the `Conditioning`, a few MB; the latent z₀).
    /// Then, **for each seed, exactly what an isolated render would do**: noise, start,
    /// denoising (the module builds its DiT and returns it, or keeps it for the next seed when the
    /// need counts it: `Context.keptDenoiser`, never beside a half-size start), decoding. What was
    /// costly and does not depend on the seed — Krea 2's fusion and modulation — is kept in
    /// `Context.reserve`. Image n of a batch stays **bit-identical** to an isolated render of its
    /// seed (verified). Between two
    /// renders — two processes, the CLI and the app —, the text, the encoded images and Qwen's last
    /// edit's K/V are read back from the library's cache (`RenderCache`), the same floats.
    private func execute(_ request: Request, _ seeds: [UInt64], _ model: Model,
                          _ cancellation: Cancellation?,
                          _ onProgress: (@Sendable (Event) -> Void)?) throws -> [Render] {
        // One render, one plan: a measure that ends meanwhile applies to the next one (`EngineSettings.adopt`).
        EngineSettings.renderBegan()
        defer { EngineSettings.renderEnded() }
        // A render assumes the whole of B: the Prompt Lab's resident weights go back first.
        PromptWriter.unloadResident()
        let chain = model.chain, cache = model.library?.renderCache
        guard !seeds.isEmpty else { return [] }
        // A request cancelled while waiting on the queue pays for nothing: neither `start`
        // nor the opening of its LoRA stack.
        try cancellation.check()
        // **The request's own refusals first, before any computation and before the memory is judged**
        // (`Admission`, pure): a request the model cannot render is refused for what it is, not for its memory.
        let admitted = try Admission.judge(request, chain: chain, usesANE: EngineSettings.effective.plan.usesANE)
        let (space, height, width, steps, start, plan) = (admitted.space, admitted.height, admitted.width, admitted.steps,
                                                           admitted.start, admitted.plan)
        // The additive start's σ₀ (`Admission`, `Request.seededStart`): nil — and `Latent.seeded`
        // never called — on every path that is not the workflow's; the img2img start keeps reading
        // `plan.startSigma`, untouched.
        let seededSigma = admitted.seededSigma
        // **The patch's crop decides the pixels** (`Admission.patch`): the plan's size, where the
        // workflow's scaling leaves it. Every other path renders the request's own format.
        let patchPlan = admitted.patch
        let pixelWidth = patchPlan?.width ?? request.width
        let pixelHeight = patchPlan?.height ?? request.height
        let referenceCount = patchPlan == nil ? request.references.count : 1
        // Installed, license, format, memory, no other render: the first that fails throws. The
        // lock is held until this function returns, the whole batch.
        // B, this Mac's budget (`MemoryBudget`): the preflight judges the floor against it, and the
        // plan is chosen in it (`MemoryPlan.choose`) — nothing read from the machine's state.
        let ceiling = MemoryBudget.machineCeiling()
        // **The need, from the request's own inputs** (`MemoryNeed`): each reference at its size, the
        // prompt's tokens bounded by its bytes, the batch, what this process holds now (`base`: B covers
        // the whole process, the app's interface included); the LoRA ranks join once the stack is open
        // (below). The base is what the process holds once its frameworks are up
        // (`OperatorFootprint.bringUp`), and alive: what `free` left queued goes back first
        // (`Arena.returnFreedPages`).
        OperatorFootprint.bringUp()
        Arena.returnFreedPages()
        var memoryRequest = model.card.memoryRequest(
            width: pixelWidth, height: pixelHeight,
            references: patchPlan.map { [($0.width, $0.height)] }
                ?? (request.image.map { [$0] } ?? request.references).map { ($0.width, $0.height) },
            promptTokens: MemoryNeed.Request.promptTokens(request.prompt, family: model.card.family,
                                                           references: referenceCount))
        // The crop is encoded once for the text encoder's image 1, which is also the denoiser's
        // reference block; with `--seeded-start` it is encoded a second time for z₀ (`Latent.seeded`),
        // and the VAE encoder is charged for the larger. The text's copy is the crop itself when it is
        // the target's own pixels (`Patch.Plan.primaryMatchesTarget`), at `--ref-res` otherwise.
        memoryRequest.seededStart = request.patchSeededStart
            ? patchPlan.map { ($0.width, $0.height) } : nil
        memoryRequest.solver = request.solver
        memoryRequest.referenceResolution = request.referenceResolution
        memoryRequest.referenceMatchesTarget = patchPlan?.primaryMatchesTarget ?? false
        memoryRequest.accelerators = admitted.accelerators
        memoryRequest.batch = seeds.count
        memoryRequest.library = model.library ?? .processWide
        let lock = try Preflight.run(model, width: pixelWidth, height: pixelHeight,
                                     references: referenceCount, ceiling: ceiling, memory: memoryRequest)
        defer { withExtendedLifetime(lock) {} }
        // The stack opens BEFORE any computation: an unreadable map throws here, not after a
        // minute — and so does a LoRA forged for another model. The DiTs apply a LoRA only to the
        // modules it names: Anima's on Krea 2 would touch none, and the render would come out
        // without it, without a word.
        let stack = request.loras.isEmpty
            ? nil : try LoRA(paths: request.loras.map { ($0.path, Float($0.strength)) })
        try stack?.checkTarget(model: chain.denoising.model)
        if let stack, model.library != nil {
            // Each LoRA's rank, not the cumulative one alone: two or more stage a `down` (`LoRA.downBytes`).
            memoryRequest.loraRanks = stack.layerRanks
            try model.card.checkMemory(memoryRequest, ceiling: ceiling)
        }
        // The machine's profile is read HERE, at render time — never at request construction.
        let context = Context(cancellation: cancellation,
                                previews: request.previews, onProgress: onProgress)
        context.cache = cache
        context.accelerators = admitted.accelerators
        context.fasterRendering = admitted.fasterRendering
        context.detail = request.detail
        context.detailScale = Detail.scale(width: pixelWidth, height: pixelHeight)
        context.solver = request.solver
        context.sigmas = request.sigmas
        // The workflow's crop, when it is also the start (`--seeded-start`): the denoiser keeps its
        // spectral schedule off (`Context.seededStart`), as for an edit — a half-size first evaluation
        // would project z₀ onto another grid. Without it the patch renders from noise, like an
        // edit, and the crop is a reference alone.
        context.seededStart = request.seededStart != nil
            || (request.patch != nil && request.patchSeededStart)
        // The library's warnings become events for the duration of the render (and go to
        // `Warnings.outsideRender` without `onProgress`: a "✗ step 3: the VELOCITY carries …" is not lost),
        // and memory is returned to the system on exit — **including on a cancellation**: the
        // arenas are unmapped by the scope unwinding, this returns what malloc kept.
        let warn: @Sendable (String) -> Void = { message in
            if let onProgress { onProgress(.warning(message)) } else { Warnings.outsideRender?(message) }
        }
        // The plan in B, and its need: what this render may take at most, the figure its own peak is
        // checked against at its end (`MemoryCheck`).
        let memoryPlan = MemoryPlan.choose(memoryRequest, ceiling: ceiling)
        // Never a render of a library's model without its need: the preflight refused an unknown one,
        // and a map replaced since would make it unknown here. A hand-composed chain (no library) is
        // outside the memory contract, like the installation, the license and the lock: its modules
        // are its caller's — the lean plan, no check.
        let need = memoryPlan.need
        if need == nil, model.library != nil { throw EngineError.memoryNeedUnknown(model: model.card.id) }
        // A hand-composed chain is the caller's: said in the render's warnings, so that nobody takes it for the product's.
        let outsideContract = model.library == nil
        PhaseBoundary.begin()
        defer { _ = PhaseBoundary.end() }
        return try MemoryPlan.during(memoryPlan) { try Warnings.during(warn) {
            // A GPU or AMX submission that failed reaches this render's journal, even when its cause
            // was already said by an earlier render (`Attention.report` says each cause once).
            let gpuFailures = Attention.failures
            defer { Attention.summarize(since: gpuFailures) }
            if outsideContract { Warnings.emit("⚠ a hand-composed chain: outside the memory contract (no need, no lock, no license check)") }
            let totalStart = Date()
            context.footprints.start = Arena.processFootprint()
            PhaseBoundary.mark("start")
            context.emit(.start(Plan(
                denoising: plan, seeds: seeds,
                stages: request.image != nil || request.seededStart != nil || request.patch != nil || !request.references.isEmpty
                    ? [.text, .image, .denoising, .decoding] : [.text, .denoising, .decoding])))

            // ── The patch's crop, made once (`Patch.render`): the tinted green crop is the text
            //    encoder's image 1 **and** z₀ below — the same pixels, the workflow's `#204`. ──
            let patchCrop = patchPlan.flatMap { plan in request.patch.map { $0.render(plan) } }
            // ── The references at the denoiser's size, once: a text stage that reads images and the
            //    image encoder below receive this same copy. A patch has one — its crop. When the
            //    crop is the target's own pixels (`Patch.Plan.primaryMatchesTarget`), that copy is
            //    the crop itself, as the workflow's `Text Encode Qwen Image 2.1 GH` keeps its primary
            //    latent; otherwise it is prepared at `--ref-res`. ──
            let prepared: [ImageRGB]
            if let patchCrop {
                prepared = patchPlan?.primaryMatchesTarget == true
                    ? [patchCrop]
                    : try chain.denoising.preparedReferences([patchCrop], referenceResolution: request.referenceResolution)
            } else if request.references.isEmpty {
                prepared = []
            } else {
                prepared = try chain.denoising.preparedReferences(request.references, referenceResolution: request.referenceResolution)
            }

            // ── The text, once for the whole batch. The module returns its memory on exit. ──
            try context.check()
            context.emit(.stage(.text, image: 0))
            let begin = Date()
            // Read back from the cache when the same module has already encoded the same prompt and
            // the same images (`RenderCache`): the floats it wrote, so the same bits.
            // The images enter the key only if the encoder sees them.
            let textKey = (chain.text as? any CacheIdentified).flatMap { module in
                cache.map { _ in RenderCache.textKey(module, prompt: request.prompt,
                                                     images: chain.text is any ImageTextModule ? prepared : []) }
            }
            let text: Conditioning
            var cached = false
            if let textKey, let kept = cache?.conditioning(textKey) {
                text = kept; cached = true
            } else {
                // Each phase in its own autorelease pool: the render is one item of the engine's
                // queue, whose pool drains only at its end — what MPS autoreleases in a phase
                // (descriptors, NDArrays and their buffers) would otherwise live beside the next.
                text = try autoreleasepool {
                    try (chain.text as? any ImageTextModule)?.encoder(request.prompt, images: prepared, context: context)
                        ?? chain.text.encoder(request.prompt, context: context)
                }
                if let textKey { cache?.store(text, key: textKey) }
            }
            context.timings.text = Date().timeIntervalSince(begin)
            context.timings.encoder = context.timings.text - context.timings.tokenizer
            context.emit(.text(tokens: text.tokens, tokenizer: context.timings.tokenizer,
                                    encoder: context.timings.encoder, cached: cached))
            context.footprints.text = Arena.processFootprint()
            PhaseBoundary.returned()
            PhaseBoundary.mark("text")

            // ── The image (img2img), once: the encoder lives in its own scope, before the DiT. ──
            var z₀: Latent? = nil
            if let image = request.image, let encoding = chain.encoding {
                try context.check()
                context.emit(.stage(.image, image: 0))
                let encodingStart = Date()
                // Already at the format (the request fitted it on receipt): `fitted` returns it as is.
                z₀ = try autoreleasepool {
                    try encode(image.fitted(width: request.width, height: request.height), with: encoding, context: context)
                }
                context.timings.encoding = Date().timeIntervalSince(encodingStart)
                context.emit(.encoding(seconds: context.timings.encoding))
                PhaseBoundary.mark("image")
            }

            // ── The additive start, once: the same encoder, its latent kept **under** the noise
            //    (`Latent.seeded`, z₀ + σ₀·ε) rather than mixed away by `Latent.start` at σ₀ = 1.
            //    Only two requests take it: a patch that asked for it (`--seeded-start`), and the
            //    engine's own additive start. **A patch without it starts from noise**, the crop being
            //    the text encoder's image 1 and the denoiser's reference block alone. Admission refuses
            //    it beside `image` and on a chain without an encoder, so at most one of the two blocks
            //    runs. ──
            var seeded: Latent? = nil
            if let image = request.seededStart ?? (request.patchSeededStart ? patchCrop : nil),
               let encoding = chain.encoding {
                try context.check()
                context.emit(.stage(.image, image: 0))
                let seedingStart = Date()
                // Fitted to the render's format, as img2img fits its image: z₀ then comes out at the
                // noise's grid, and `Latent.seeded` says by name if a pipeline ever gives another.
                seeded = try autoreleasepool {
                    try encode(image.fitted(width: pixelWidth, height: pixelHeight), with: encoding, context: context)
                }
                context.timings.encoding = Date().timeIntervalSince(seedingStart)
                context.emit(.encoding(seconds: context.timings.encoding))
                PhaseBoundary.mark("image")
            }

            // ── The references, once: the denoiser re-reads the **same images** the text encoder read,
            //    each at its own size. A patch has one — its crop: it is image 1 and the reference block
            //    (`QwenImage21Sequence`: 4 × slots == h·w). Dropping it here left the encoder's image
            //    slots without the rows they place (`2373 slots for 5376 image tokens`). ──
            var references: [Latent] = []
            if !prepared.isEmpty, let encoding = chain.encoding {
                try context.check()
                context.emit(.stage(.image, image: 0))
                let referencesStart = Date()
                for image in prepared {
                    try context.check()
                    references.append(try autoreleasepool { try encode(image, with: encoding, context: context) })
                    PhaseBoundary.mark("reference \(references.count)")
                }
                context.timings.encoding += Date().timeIntervalSince(referencesStart)
                context.emit(.encoding(seconds: context.timings.encoding))
            }

            // ── Every image's denoising, then every decoding. ──
            // **Not denoise-decode, denoise-decode** (measured: Z-Image 1408×704, a batch of 3 under an idle
            // ballast swapped 18 008 pages where 1 image left the compressor 5.8 GB of room). Each switch
            // between the DiT and the decoder is a wave of fresh allocations — the arenas released, the
            // decoder's graph, the arenas again — and each wave sends the others' anonymous memory into
            // the compressor, which keeps it: its floor climbed ~2.3 GB at every image boundary, never
            // within a denoising. In this order a batch has the one switch of a single render; the
            // latents waiting meanwhile are kilobytes. Same bits: each image is the same computation.
            var pending: [(latent: Latent, timings: Timings, elapsed: TimeInterval, classes: [ProductLedger.Tally], fallbacks: [ProductLedger.Fallback])] = []
            var imageStart = totalStart
            for (n, seed) in seeds.enumerated() {
                try context.check()
                context.image = n
                context.solverSeed = seed
                if n > 0 {
                    // The text and the input image were paid for by the first.
                    context.timings = Timings()
                    imageStart = Date()
                }
                var latent = Latent.noise(space, height: height, width: width, seed: seed,
                                          variations: request.variations)
                if let z₀ { latent = Latent.start(image: z₀, noise: latent, sigma: plan.startSigma) }
                // The workflow's start, when it was asked for (`--seeded-start`): z₀ + λ·ε (σ₀ the
                // schedule's first node, which a custom table may put below 1; λ = √(1 + σ₀²) on
                // ComfyUI's max_denoise branch). `seeded` is `nil` on every other path — a patch's
                // default among them, where `latent` above is the seed's noise alone.
                if let seeded, let seededSigma {
                    latent = try Latent.seeded(image: seeded, noise: latent, sigma: seededSigma)
                }

                context.emit(.stage(.denoising, image: n))
                let denoisingStart = Date()
                // The classes this image's evaluations ran, by route (`ProductLedger`): armed for the denoising alone.
                let ledger = ProductLedger()
                try autoreleasepool {
                    try ProductLedger.recording(into: ledger) {
                        try chain.denoising.denoise(&latent, text: text, steps: steps, start: start,
                                                    references: references, lora: stack, context: context)
                    }
                }
                context.timings.denoising = Date().timeIntervalSince(denoisingStart)
                PhaseBoundary.mark("denoising")
                pending.append((latent, context.timings, Date().timeIntervalSince(imageStart), ledger.tallies, ledger.fallbacks))
            }

            context.keptDenoiser = nil
            PhaseBoundary.returned()
            PhaseBoundary.mark("denoiser released")

            var renderResults: [Render] = []
            var refused = false
            for (n, (latent, timings, elapsed, classes, fallbacks)) in pending.enumerated() {
                try context.check()
                context.image = n
                context.timings = timings
                context.emit(.stage(.decoding, image: n))
                // **An image that is not finite is never delivered as done** (`FiniteImage`): the latent
                // before paying for its decoding, the pixels after it — a black image after 200 s, said
                // as such, rather than handed to the history as a success. In a batch it is skipped, not
                // the batch: the images after it are still decoded and delivered.
                guard FiniteImage.isFinite(latent.values, "the final latent", image: n) else { refused = true; continue }
                let image = try autoreleasepool { try chain.decoding.decode(latent, context: context) }
                guard FiniteImage.isFinite(image.pixels, "the decoded image", image: n) else { refused = true; continue }
                // An image's time: its own text, encoding and denoising, then its decoding.
                context.timings.total = elapsed + context.timings.decoding
                context.footprints.end = Arena.processFootprint()
                PhaseBoundary.mark("decoding")
                context.emit(.decoding(seconds: context.timings.decoding))
                let seed = seeds[n]

                var renderResult = Render(model: chain.denoising.model, prompt: request.prompt, seed: seed,
                                  steps: steps, loras: request.loras, loraSummary: stack?.summary, image: image,
                                  evaluations: plan.evaluations, spectral: plan.reduced,
                                  strength: request.image != nil ? request.strength : nil, startStep: plan.startStep,
                                  startSigma: seededSigma ?? plan.startSigma,
                                  timings: context.timings, footprints: context.footprints, tokens: text.tokens,
                                  detail: request.detail, solver: request.solver,
                                  variations: request.variations.filter { $0.effectiveStrength > 0 },
                                  modelName: model.card.name, isImportedModel: model.card.isImported,
                                  loraOrigins: stack?.origins ?? [], neuralEngine: context.accelerators.neuralEngine,
                                  accelerators: context.accelerators.isOn,
                                  offer: AcceleratorOffer(plan: EngineSettings.effective.plan.forDenoiser(context.accelerators)),
                                  fasterRendering: admitted.fasterRendering, classes: classes,
                                  loraRank: stack?.maxRank ?? 0)
                renderResult.fallbacks = fallbacks
                context.emit(.image(index: n, renderResult))
                renderResults.append(renderResult)
            }
            if refused, renderResults.isEmpty { throw EngineError.nonFiniteImage }
            // **The render's own peak against its need**: a phase above its need is a
            // defect of the code, logged and carried by every image of the batch.
            guard let need else { return renderResults }
            let check = MemoryCheck(need: need, marks: PhaseBoundary.end())
            for defect in check.defects {
                MemoryCheck.log.error("\(defect, privacy: .public) — \(model.card.id, privacy: .public) \(pixelWidth)×\(pixelHeight), \(referenceCount) reference(s)")
            }
            for slack in check.slack {
                MemoryCheck.log.info("\(slack, privacy: .public) — \(model.card.id, privacy: .public) \(pixelWidth)×\(pixelHeight)")
            }
            return renderResults.map { var r = $0; r.memory = check; return r }
        } }
    }

    /// An image through the chain's encoder — or its latent read back from the cache (`RenderCache`).
    private func encode(_ image: ImageRGB, with encoding: any ImageEncodingModule, context: Context) throws -> Latent {
        guard let cache = context.cache, let module = encoding as? any CacheIdentified else {
            return try encoding.encoder(image, context: context)
        }
        let key = RenderCache.imageKey(module, image: image)
        if let kept = cache.latent(key) { return kept }
        let latent = try encoding.encoder(image, context: context)
        cache.store(latent, key: key)
        return latent
    }
}

/// **A render's last guard**: a value that is not finite (NaN, ±∞) in the final latent or the decoded
/// pixels makes an image that comes out black or blank — whatever the family, whatever went wrong upstream
/// (a velocity gone non-finite, a GPU fault). That image gets no `Render`, no `.image` event, nothing in
/// the history; the render throws `EngineError.nonFiniteImage` when no image of it is left. One pass over each, at the end
/// of a render only (a 1024² latent is 65 536 to 262 144 floats, its pixels 3 Mi): never inside a step.
package enum FiniteImage {
    /// How many values of `values` are not finite.
    package static func nonFiniteCount(_ values: [Float]) -> Int {
        values.withUnsafeBufferPointer { b in
            var n = 0
            for v in b where !v.isFinite { n += 1 }
            return n
        }
    }

    /// Whether `values` is finite; when not, the count, and `what` it was found in, go to the render's
    /// warnings — the error the render may end with says nothing technical.
    package static func isFinite(_ values: [Float], _ what: String, image: Int) -> Bool {
        let bad = nonFiniteCount(values)
        guard bad > 0 else { return true }
        Warnings.emit("✗ image \(image + 1): \(what) carries \(bad) non-finite values out of \(values.count): not delivered")
        return false
    }

}
